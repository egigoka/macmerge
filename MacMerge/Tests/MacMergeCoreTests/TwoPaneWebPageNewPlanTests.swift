import Foundation
import MacMergeCore
import XCTest

final class TwoPaneWebPageNewPlanTests: XCTestCase {
    private func digest(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 32)
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: false)
    }

    private func snapshot(path: String, byteCount: Int = 1_024, byte: UInt8) -> TwoPaneWebPageNewPlanSnapshot {
        TwoPaneWebPageNewPlanSnapshot(normalizedURL: url(path), byteCount: byteCount, digest: digest(byte))
    }

    private func validRequest(
        leftByte: UInt8 = 0x11,
        rightByte: UInt8 = 0x33,
        mode: WebPageComparisonMode = .source,
        limits: TwoPaneWebPageNewPlanLimits = .default
    ) -> TwoPaneWebPageNewPlanRequest {
        let options = WebPageComparisonOptions(mode: mode)
        return TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/mm-left.html", byte: leftByte),
            right: snapshot(path: "/tmp/mm-right.html", byte: rightByte),
            comparisonOptions: options,
            limits: limits
        )
    }

    private func assertPlanError(
        _ expected: TwoPaneWebPageNewPlanError,
        request: TwoPaneWebPageNewPlanRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try TwoPaneWebPageNewPlan.plan(request)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let actual as TwoPaneWebPageNewPlanError {
            XCTAssertEqual(actual, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func testCommandIDMatchesTodoLedger() {
        XCTAssertEqual(TwoPaneWebPageNewPlan.commandID, "ID_FILE_NEW_WEBPAGE")
    }

    func testHappyPathBindsURLsRevisionsOptionsModeLimits() throws {
        let request = validRequest()
        let plan = try TwoPaneWebPageNewPlan.plan(request)
        XCTAssertEqual(plan.left.side, .left)
        XCTAssertEqual(plan.right.side, .right)
        XCTAssertEqual(plan.left.normalizedURL, url("/tmp/mm-left.html"))
        XCTAssertEqual(plan.right.normalizedURL, url("/tmp/mm-right.html"))
        XCTAssertEqual(plan.left.digest, digest(0x11))
        XCTAssertEqual(plan.right.digest, digest(0x33))
        XCTAssertEqual(plan.comparisonOptions.mode, .source)
        XCTAssertEqual(plan.mode, .source)
        XCTAssertEqual(plan.flags, TwoPaneWebPageNewPlanFlags(mode: .source))
        XCTAssertEqual(plan.limits, request.limits)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertGreaterThan(plan.receipt.workUnits, 0)
        XCTAssertEqual(plan.receipt.leftDigest, digest(0x11))
        XCTAssertEqual(plan.receipt.rightDigest, digest(0x33))
        XCTAssertEqual(plan.receipt.leftByteCount, 1_024)
        XCTAssertEqual(plan.receipt.rightByteCount, 1_024)
        XCTAssertEqual(plan.receipt.byteCounts.left, 1_024)
        XCTAssertEqual(plan.receipt.byteCounts.right, 1_024)
        XCTAssertEqual(plan.receipt.flags.mode, .source)
        XCTAssertEqual(plan.receipt.planSHA256.count, 32)
        XCTAssertNoThrow(try plan.validateReceipt())
        XCTAssertNoThrow(try plan.resolvedComparisonOptions())
        XCTAssertEqual(try plan.resolvedComparisonOptions(), request.comparisonOptions)
        XCTAssertEqual(try request.resolvedComparisonOptions(), request.comparisonOptions)
    }

    func testMakeAliasMatchesPlanDeterministic() throws {
        let request = validRequest()
        let viaPlan = try TwoPaneWebPageNewPlan.plan(request)
        let viaMake = try TwoPaneWebPageNewPlan.make(request)
        XCTAssertEqual(viaPlan, viaMake)
        let again = try TwoPaneWebPageNewPlan.plan(request)
        XCTAssertEqual(viaPlan.receipt, again.receipt)
        XCTAssertEqual(viaPlan.receipt.planSHA256, again.receipt.planSHA256)
    }

    func testModeDriftsReceiptAndFlags() throws {
        let source = try TwoPaneWebPageNewPlan.plan(validRequest(mode: .source))
        let rendered = try TwoPaneWebPageNewPlan.plan(validRequest(mode: .renderedText))
        XCTAssertNotEqual(source.receipt.planSHA256, rendered.receipt.planSHA256)
        XCTAssertNotEqual(source.receipt.flags, rendered.receipt.flags)
        XCTAssertNotEqual(source, rendered)
    }

    func testResolvedComparisonOptionsThrowsAfterValidate() {
        let badLimits = TwoPaneWebPageNewPlanLimits(maximumURLPathBytes: 0)
        let request = validRequest(limits: badLimits)
        XCTAssertThrowsError(try request.resolvedComparisonOptions()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidLimit(.urlPathBytes))
        }
        do {
            let plan = try TwoPaneWebPageNewPlan.plan(validRequest())
            let tamperedLimits = TwoPaneWebPageNewPlan(
                left: plan.left,
                right: plan.right,
                comparisonOptions: plan.comparisonOptions,
                limits: badLimits,
                receipt: plan.receipt
            )
            _ = try tamperedLimits.resolvedComparisonOptions()
            XCTFail("Expected invalidLimit")
        } catch let error as TwoPaneWebPageNewPlanError {
            XCTAssertEqual(error, .invalidLimit(.urlPathBytes))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvalidComparisonOptionsExceedingMarkupRejected() {
        var comparisonLimits = WebPageComparisonLimits()
        comparisonLimits = WebPageComparisonLimits(
            maximumInputBytes: 64 * 1_024 * 1_024,
            maximumTokenCount: comparisonLimits.maximumTokenCount,
            maximumAttributeCount: comparisonLimits.maximumAttributeCount,
            maximumAttributesPerTag: comparisonLimits.maximumAttributesPerTag,
            maximumElementDepth: comparisonLimits.maximumElementDepth,
            maximumWorkUnits: comparisonLimits.maximumWorkUnits,
            maximumOutputBytes: comparisonLimits.maximumOutputBytes
        )
        let tight = TwoPaneWebPageNewPlanLimits(maximumMarkupBytes: 1_024)
        let request = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/a.html", byteCount: 100, byte: 0x11),
            right: snapshot(path: "/tmp/b.html", byteCount: 100, byte: 0x33),
            comparisonOptions: WebPageComparisonOptions(mode: .source, limits: comparisonLimits),
            limits: tight
        )
        XCTAssertThrowsError(try request.resolvedComparisonOptions()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidComparisonOptions)
        }
        XCTAssertThrowsError(try TwoPaneWebPageNewPlan.plan(request)) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidComparisonOptions)
        }
    }

    func testLimitsRequireAtLeastOne() {
        assertPlanError(.invalidLimit(.urlPathBytes), request: validRequest(limits: TwoPaneWebPageNewPlanLimits(maximumURLPathBytes: 0)))
        assertPlanError(.invalidLimit(.markupBytes), request: validRequest(limits: TwoPaneWebPageNewPlanLimits(maximumMarkupBytes: 0)))
        let tinyWork = TwoPaneWebPageNewPlanLimits(maximumWorkUnits: 0)
        assertPlanError(.invalidLimit(.workUnits), request: validRequest(limits: tinyWork))
        let tinyInterval = TwoPaneWebPageNewPlanLimits(cancellationCheckInterval: 0)
        assertPlanError(.invalidLimit(.cancellationCheckInterval), request: validRequest(limits: tinyInterval))
    }

    func testLimitsHardBoundaries() {
        XCTAssertThrowsError(try TwoPaneWebPageNewPlanLimits(maximumURLPathBytes: TwoPaneWebPageNewPlanLimits.hardMaximumURLPathBytes + 1).validate())
        XCTAssertThrowsError(try TwoPaneWebPageNewPlanLimits(maximumMarkupBytes: TwoPaneWebPageNewPlanLimits.hardMaximumMarkupBytes + 1).validate())
        let overWork = TwoPaneWebPageNewPlanLimits(maximumWorkUnits: TwoPaneWebPageNewPlanLimits.hardMaximumWorkUnits + 1)
        XCTAssertThrowsError(try overWork.validate()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidLimit(.workUnits))
        }
        XCTAssertNoThrow(try TwoPaneWebPageNewPlanLimits.default.validate())
    }

    func testInvalidNormalizedURLRejected() {
        let http = TwoPaneWebPageNewPlanSnapshot(normalizedURL: URL(string: "https://example.com/a.html")!, byteCount: 100, digest: digest(0x11))
        let request = TwoPaneWebPageNewPlanRequest(left: http, right: snapshot(path: "/tmp/b.html", byte: 0x33))
        assertPlanError(.invalidNormalizedURL(side: .left), request: request)
    }

    func testURLPathBoundaryAcceptMaxRejectOver() throws {
        let exactPath = "/a"
        let exactBytes = exactPath.utf8.count
        let limits = TwoPaneWebPageNewPlanLimits(maximumURLPathBytes: exactBytes, maximumMarkupBytes: 4_096)
        let smallOptions = WebPageComparisonOptions(
            mode: .source,
            limits: WebPageComparisonLimits(maximumInputBytes: 4_096, maximumOutputBytes: 4_096)
        )
        let fitting = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: exactPath, byteCount: 10, byte: 0x11),
            right: snapshot(path: "/b", byteCount: 10, byte: 0x33),
            comparisonOptions: smallOptions,
            limits: limits
        )
        XCTAssertNoThrow(try TwoPaneWebPageNewPlan.plan(fitting))
        let overflowing = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/ab", byteCount: 10, byte: 0x11),
            right: snapshot(path: "/b", byteCount: 10, byte: 0x33),
            comparisonOptions: smallOptions,
            limits: limits
        )
        assertPlanError(.urlPathTooLarge(side: .left, maximum: exactBytes), request: overflowing)
    }

    func testMarkupBoundaryAcceptMaxRejectOver() throws {
        let limits = TwoPaneWebPageNewPlanLimits(maximumMarkupBytes: 100)
        let fitting = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/a.html", byteCount: 100, byte: 0x11),
            right: snapshot(path: "/tmp/b.html", byteCount: 100, byte: 0x33),
            comparisonOptions: WebPageComparisonOptions(
                mode: .source,
                limits: WebPageComparisonLimits(maximumInputBytes: 100, maximumOutputBytes: 100)
            ),
            limits: limits
        )
        XCTAssertNoThrow(try TwoPaneWebPageNewPlan.plan(fitting))
        let overflowing = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/a.html", byteCount: 101, byte: 0x11),
            right: snapshot(path: "/tmp/b.html", byteCount: 100, byte: 0x33),
            comparisonOptions: WebPageComparisonOptions(
                mode: .source,
                limits: WebPageComparisonLimits(maximumInputBytes: 101, maximumOutputBytes: 101)
            ),
            limits: limits
        )
        assertPlanError(.markupTooLarge(side: .left, maximum: 100), request: overflowing)
    }

    func testInvalidDigestEverySide() {
        let short = Data(repeating: 0x01, count: 16)
        let shortLeft = TwoPaneWebPageNewPlanRequest(
            left: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/a.html"), byteCount: 10, digest: short),
            right: snapshot(path: "/tmp/b.html", byte: 0x33)
        )
        assertPlanError(.invalidDigest(side: .left), request: shortLeft)
        let zeros = Data(repeating: 0, count: 32)
        let zeroRight = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/a.html", byte: 0x11),
            right: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/b.html"), byteCount: 10, digest: zeros)
        )
        assertPlanError(.invalidDigest(side: .right), request: zeroRight)
    }

    func testDuplicateSnapshotRejected() {
        let sameDigest = digest(0xAA)
        let request = TwoPaneWebPageNewPlanRequest(
            left: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/a.html"), byteCount: 100, digest: sameDigest),
            right: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/b.html"), byteCount: 100, digest: sameDigest)
        )
        assertPlanError(.duplicateSnapshot, request: request)
        let sameURL = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/same.html", byte: 0x11),
            right: snapshot(path: "/tmp/same.html", byte: 0x33)
        )
        assertPlanError(.duplicateSnapshot, request: sameURL)
    }

    func testReceiptTamperRejectedAsMismatch() throws {
        let plan = try TwoPaneWebPageNewPlan.plan(validRequest())
        let tamperedDigest = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: TwoPaneWebPageNewPlanReceipt(
                leftDigest: digest(0xFF),
                rightDigest: plan.receipt.rightDigest,
                leftByteCount: plan.receipt.leftByteCount,
                rightByteCount: plan.receipt.rightByteCount,
                flags: plan.receipt.flags,
                workUnits: plan.receipt.workUnits,
                planSHA256: plan.receipt.planSHA256
            )
        )
        XCTAssertThrowsError(try tamperedDigest.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
        let tamperedRight = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: TwoPaneWebPageNewPlanReceipt(
                leftDigest: plan.receipt.leftDigest,
                rightDigest: digest(0xFE),
                leftByteCount: plan.receipt.leftByteCount,
                rightByteCount: plan.receipt.rightByteCount,
                flags: plan.receipt.flags,
                workUnits: plan.receipt.workUnits,
                planSHA256: plan.receipt.planSHA256
            )
        )
        XCTAssertThrowsError(try tamperedRight.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
        let tamperedCounts = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: TwoPaneWebPageNewPlanReceipt(
                leftDigest: plan.receipt.leftDigest,
                rightDigest: plan.receipt.rightDigest,
                leftByteCount: plan.receipt.leftByteCount + 1,
                rightByteCount: plan.receipt.rightByteCount,
                flags: plan.receipt.flags,
                workUnits: plan.receipt.workUnits,
                planSHA256: plan.receipt.planSHA256
            )
        )
        XCTAssertThrowsError(try tamperedCounts.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
        let tamperedFlags = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: TwoPaneWebPageNewPlanReceipt(
                leftDigest: plan.receipt.leftDigest,
                rightDigest: plan.receipt.rightDigest,
                leftByteCount: plan.receipt.leftByteCount,
                rightByteCount: plan.receipt.rightByteCount,
                flags: TwoPaneWebPageNewPlanFlags(mode: plan.mode == .source ? .renderedText : .source),
                workUnits: plan.receipt.workUnits,
                planSHA256: plan.receipt.planSHA256
            )
        )
        XCTAssertThrowsError(try tamperedFlags.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
        let tamperedHash = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: TwoPaneWebPageNewPlanReceipt(
                leftDigest: plan.receipt.leftDigest,
                rightDigest: plan.receipt.rightDigest,
                leftByteCount: plan.receipt.leftByteCount,
                rightByteCount: plan.receipt.rightByteCount,
                flags: plan.receipt.flags,
                workUnits: plan.receipt.workUnits,
                planSHA256: digest(0xAB)
            )
        )
        XCTAssertThrowsError(try tamperedHash.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
    }

    func testReceiptTamperRightByteCountRejectedAsMismatch() throws {
        let plan = try TwoPaneWebPageNewPlan.plan(validRequest())
        let tampered = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: TwoPaneWebPageNewPlanReceipt(
                leftDigest: plan.receipt.leftDigest,
                rightDigest: plan.receipt.rightDigest,
                leftByteCount: plan.receipt.leftByteCount,
                rightByteCount: plan.receipt.rightByteCount + 1,
                flags: plan.receipt.flags,
                workUnits: plan.receipt.workUnits,
                planSHA256: plan.receipt.planSHA256
            )
        )
        XCTAssertThrowsError(try tampered.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
    }

    func testReceiptBindsNarrowedLimitsRevalidated() throws {
        let plan = try TwoPaneWebPageNewPlan.plan(validRequest())
        XCTAssertGreaterThan(plan.receipt.workUnits, 1)
        let tightWorkMaximum = plan.receipt.workUnits - 1
        let tightWork = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: TwoPaneWebPageNewPlanLimits(maximumWorkUnits: tightWorkMaximum),
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try tightWork.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .workLimitExceeded(limit: .workUnits, maximum: tightWorkMaximum))
        }
        let narrowPathMaximum = 8
        let narrowPath = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: TwoPaneWebPageNewPlanLimits(maximumURLPathBytes: narrowPathMaximum),
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try narrowPath.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .urlPathTooLarge(side: .left, maximum: narrowPathMaximum))
        }
        let narrowMarkupMaximum = 100
        let narrowMarkup = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: TwoPaneWebPageNewPlanLimits(maximumMarkupBytes: narrowMarkupMaximum),
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try narrowMarkup.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .markupTooLarge(side: .left, maximum: narrowMarkupMaximum))
        }
        let fittingNarrowed = TwoPaneWebPageNewPlanLimits(maximumURLPathBytes: 8 * 1_024)
        let staleReceipt = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: fittingNarrowed,
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try staleReceipt.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
    }

    func testValidateReceiptRechecksBindInvariants() throws {
        let plan = try TwoPaneWebPageNewPlan.plan(validRequest())
        let flippedSide = TwoPaneWebPageNewPlan(
            left: TwoPaneWebPageNewPlanBoundSource(
                side: .right,
                normalizedURL: plan.left.normalizedURL,
                byteCount: plan.left.byteCount,
                digest: plan.left.digest
            ),
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try flippedSide.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
        let httpsURL = URL(string: "https://example.com/a.html")!
        let httpsLeft = TwoPaneWebPageNewPlan(
            left: TwoPaneWebPageNewPlanBoundSource(
                side: .left,
                normalizedURL: httpsURL,
                byteCount: plan.left.byteCount,
                digest: plan.left.digest
            ),
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try httpsLeft.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidNormalizedURL(side: .left))
        }
        let longPath = "/tmp/" + String(repeating: "a", count: 20_000) + ".html"
        let overPathLeft = TwoPaneWebPageNewPlan(
            left: TwoPaneWebPageNewPlanBoundSource(
                side: .left,
                normalizedURL: url(longPath),
                byteCount: plan.left.byteCount,
                digest: plan.left.digest
            ),
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try overPathLeft.validateReceipt()) { error in
            XCTAssertEqual(
                error as? TwoPaneWebPageNewPlanError,
                .urlPathTooLarge(side: .left, maximum: plan.limits.maximumURLPathBytes)
            )
        }
        let overBytesLeft = TwoPaneWebPageNewPlan(
            left: TwoPaneWebPageNewPlanBoundSource(
                side: .left,
                normalizedURL: plan.left.normalizedURL,
                byteCount: plan.limits.maximumMarkupBytes + 1,
                digest: plan.left.digest
            ),
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try overBytesLeft.validateReceipt()) { error in
            XCTAssertEqual(
                error as? TwoPaneWebPageNewPlanError,
                .markupTooLarge(side: .left, maximum: plan.limits.maximumMarkupBytes)
            )
        }
        let shortLeft = TwoPaneWebPageNewPlan(
            left: TwoPaneWebPageNewPlanBoundSource(
                side: .left,
                normalizedURL: plan.left.normalizedURL,
                byteCount: plan.left.byteCount,
                digest: Data(repeating: 0x01, count: 16)
            ),
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try shortLeft.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidDigest(side: .left))
        }
    }

    func testPositiveComparisonExceedRejectedAsInvalidOptions() {
        let base = WebPageComparisonLimits.default
        let outputExceed = WebPageComparisonLimits(
            maximumInputBytes: 100,
            maximumTokenCount: base.maximumTokenCount,
            maximumAttributeCount: base.maximumAttributeCount,
            maximumAttributesPerTag: base.maximumAttributesPerTag,
            maximumElementDepth: base.maximumElementDepth,
            maximumWorkUnits: 100,
            maximumOutputBytes: 1_025
        )
        let outputRequest = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/a.html", byteCount: 100, byte: 0x11),
            right: snapshot(path: "/tmp/b.html", byteCount: 100, byte: 0x33),
            comparisonOptions: WebPageComparisonOptions(mode: .source, limits: outputExceed),
            limits: TwoPaneWebPageNewPlanLimits(maximumMarkupBytes: 1_024)
        )
        XCTAssertThrowsError(try outputRequest.resolvedComparisonOptions()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidComparisonOptions)
        }
        XCTAssertThrowsError(try TwoPaneWebPageNewPlan.plan(outputRequest)) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidComparisonOptions)
        }
        let workExceed = WebPageComparisonLimits(
            maximumInputBytes: 100,
            maximumTokenCount: base.maximumTokenCount,
            maximumAttributeCount: base.maximumAttributeCount,
            maximumAttributesPerTag: base.maximumAttributesPerTag,
            maximumElementDepth: base.maximumElementDepth,
            maximumWorkUnits: 1_001,
            maximumOutputBytes: 100
        )
        let workRequest = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/a.html", byteCount: 100, byte: 0x11),
            right: snapshot(path: "/tmp/b.html", byteCount: 100, byte: 0x33),
            comparisonOptions: WebPageComparisonOptions(mode: .source, limits: workExceed),
            limits: TwoPaneWebPageNewPlanLimits(maximumMarkupBytes: 4_096, maximumWorkUnits: 1_000)
        )
        XCTAssertThrowsError(try workRequest.resolvedComparisonOptions()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidComparisonOptions)
        }
        XCTAssertThrowsError(try TwoPaneWebPageNewPlan.plan(workRequest)) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidComparisonOptions)
        }
    }

    func testRightSideInvalidRejected() {
        let https = TwoPaneWebPageNewPlanSnapshot(normalizedURL: URL(string: "https://example.com/b.html")!, byteCount: 100, digest: digest(0x33))
        let badURL = TwoPaneWebPageNewPlanRequest(left: snapshot(path: "/tmp/a.html", byte: 0x11), right: https)
        assertPlanError(.invalidNormalizedURL(side: .right), request: badURL)
        let exactPath = "/a"
        let exactBytes = exactPath.utf8.count
        let pathLimits = TwoPaneWebPageNewPlanLimits(maximumURLPathBytes: exactBytes, maximumMarkupBytes: 4_096)
        let smallOptions = WebPageComparisonOptions(
            mode: .source,
            limits: WebPageComparisonLimits(maximumInputBytes: 4_096, maximumOutputBytes: 4_096)
        )
        let pathOverRight = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/a", byteCount: 10, byte: 0x11),
            right: snapshot(path: "/abc", byteCount: 10, byte: 0x33),
            comparisonOptions: smallOptions,
            limits: pathLimits
        )
        assertPlanError(.urlPathTooLarge(side: .right, maximum: exactBytes), request: pathOverRight)
        let markupLimits = TwoPaneWebPageNewPlanLimits(maximumMarkupBytes: 100)
        let markupOverRight = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/a.html", byteCount: 100, byte: 0x11),
            right: snapshot(path: "/tmp/b.html", byteCount: 101, byte: 0x33),
            comparisonOptions: WebPageComparisonOptions(
                mode: .source,
                limits: WebPageComparisonLimits(maximumInputBytes: 101, maximumOutputBytes: 101)
            ),
            limits: markupLimits
        )
        assertPlanError(.markupTooLarge(side: .right, maximum: 100), request: markupOverRight)
    }

    func testInflatedWorkRejectedAsWorkLimitExceeded() throws {
        let plan = try TwoPaneWebPageNewPlan.plan(validRequest())
        let maximum = plan.limits.maximumWorkUnits
        let inflated = TwoPaneWebPageNewPlan(
            left: plan.left,
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: TwoPaneWebPageNewPlanReceipt(
                leftDigest: plan.receipt.leftDigest,
                rightDigest: plan.receipt.rightDigest,
                leftByteCount: plan.receipt.leftByteCount,
                rightByteCount: plan.receipt.rightByteCount,
                flags: plan.receipt.flags,
                workUnits: maximum + 1,
                planSHA256: plan.receipt.planSHA256
            )
        )
        XCTAssertThrowsError(try inflated.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .workLimitExceeded(limit: .workUnits, maximum: maximum))
        }
    }

    func testTinyWorkBudgetThrowsWorkLimitExceeded() {
        let limits = TwoPaneWebPageNewPlanLimits(maximumWorkUnits: 1)
        XCTAssertThrowsError(try TwoPaneWebPageNewPlan.plan(validRequest(limits: limits))) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .workLimitExceeded(limit: .workUnits, maximum: 1))
        }
    }

    func testCancellationMapsToCancelled() {
        XCTAssertThrowsError(try TwoPaneWebPageNewPlan.plan(validRequest(), cancellationCheck: { throw CancellationError() })) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .cancelled)
        }
    }

    func testReceiptBindsLimits() throws {
        let baseline = try TwoPaneWebPageNewPlan.plan(validRequest()).receipt
        let narrowed = try TwoPaneWebPageNewPlan.plan(
            validRequest(limits: TwoPaneWebPageNewPlanLimits(maximumURLPathBytes: 8 * 1_024))
        ).receipt
        XCTAssertNotEqual(baseline.planSHA256, narrowed.planSHA256)
    }

    func testReceiptBindsNormalizedURLs() throws {
        let first = try TwoPaneWebPageNewPlan.plan(validRequest()).receipt
        let moved = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/mm-moved.html", byte: 0x11),
            right: snapshot(path: "/tmp/mm-right.html", byte: 0x33)
        )
        let second = try TwoPaneWebPageNewPlan.plan(moved).receipt
        XCTAssertNotEqual(first.planSHA256, second.planSHA256)
    }

    func testRedactionHidesURLsAndDigests() throws {
        let secretPath = "/Users/secret/hunter2-left.html"
        let secretDigest = digest(0xAB)
        let secretHex = secretDigest.map { String(format: "%02x", $0) }.joined()
        let snapshot = TwoPaneWebPageNewPlanSnapshot(normalizedURL: url(secretPath), byteCount: 100, digest: secretDigest)
        let request = TwoPaneWebPageNewPlanRequest(left: snapshot, right: self.snapshot(path: "/tmp/b.html", byte: 0x33))
        let plan = try TwoPaneWebPageNewPlan.plan(request)
        XCTAssertFalse(snapshot.description.contains(secretPath))
        XCTAssertFalse(snapshot.debugDescription.contains(secretPath))
        XCTAssertFalse(request.description.contains(secretPath))
        XCTAssertFalse(plan.description.contains(secretPath))
        XCTAssertFalse(plan.receipt.description.contains(secretPath))
        XCTAssertFalse(snapshot.description.contains(secretHex))
        XCTAssertFalse(plan.receipt.description.contains(secretHex))
        for child in snapshot.customMirror.children {
            XCTAssertFalse(String(describing: child.value).contains(secretPath))
        }
        for child in request.customMirror.children {
            XCTAssertFalse(String(describing: child.value).contains(secretPath))
        }
        for child in plan.customMirror.children {
            XCTAssertFalse(String(describing: child.value).contains(secretPath))
        }
        for child in plan.receipt.customMirror.children {
            XCTAssertFalse(String(describing: child.value).contains(secretHex))
        }
        let error = TwoPaneWebPageNewPlanError.receiptMismatch
        XCTAssertTrue(error.description.contains("<redacted>"))
        XCTAssertFalse(error.errorDescription?.contains(secretPath) ?? false)
    }

    func testBoundedLedgerCountsWork() throws {
        let plan = try TwoPaneWebPageNewPlan.plan(validRequest())
        XCTAssertGreaterThan(plan.receipt.workUnits, 0)
        XCTAssertLessThanOrEqual(plan.receipt.workUnits, plan.limits.maximumWorkUnits)
    }

    func testNegativeComparisonInputOutputWorkRejectedAsInvalidOptions() {
        let base = WebPageComparisonLimits.default
        let negativeInput = WebPageComparisonLimits(
            maximumInputBytes: -1,
            maximumTokenCount: base.maximumTokenCount,
            maximumAttributeCount: base.maximumAttributeCount,
            maximumAttributesPerTag: base.maximumAttributesPerTag,
            maximumElementDepth: base.maximumElementDepth,
            maximumWorkUnits: base.maximumWorkUnits,
            maximumOutputBytes: base.maximumOutputBytes
        )
        let negativeOutput = WebPageComparisonLimits(
            maximumInputBytes: base.maximumInputBytes,
            maximumTokenCount: base.maximumTokenCount,
            maximumAttributeCount: base.maximumAttributeCount,
            maximumAttributesPerTag: base.maximumAttributesPerTag,
            maximumElementDepth: base.maximumElementDepth,
            maximumWorkUnits: base.maximumWorkUnits,
            maximumOutputBytes: -1
        )
        let negativeWork = WebPageComparisonLimits(
            maximumInputBytes: base.maximumInputBytes,
            maximumTokenCount: base.maximumTokenCount,
            maximumAttributeCount: base.maximumAttributeCount,
            maximumAttributesPerTag: base.maximumAttributesPerTag,
            maximumElementDepth: base.maximumElementDepth,
            maximumWorkUnits: -1,
            maximumOutputBytes: base.maximumOutputBytes
        )
        for bad in [negativeInput, negativeOutput, negativeWork] {
            let request = TwoPaneWebPageNewPlanRequest(
                left: snapshot(path: "/tmp/a.html", byteCount: 100, byte: 0x11),
                right: snapshot(path: "/tmp/b.html", byteCount: 100, byte: 0x33),
                comparisonOptions: WebPageComparisonOptions(mode: .source, limits: bad),
                limits: .default
            )
            XCTAssertThrowsError(try request.resolvedComparisonOptions()) { error in
                XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidComparisonOptions)
            }
            XCTAssertThrowsError(try TwoPaneWebPageNewPlan.plan(request)) { error in
                XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .invalidComparisonOptions)
            }
        }
    }

    func testValidateReceiptRechecksBindInvariant() throws {
        let plan = try TwoPaneWebPageNewPlan.plan(validRequest())
        let movedLeft = TwoPaneWebPageNewPlan(
            left: TwoPaneWebPageNewPlanBoundSource(
                side: .left,
                normalizedURL: url("/tmp/mm-moved.html"),
                byteCount: plan.left.byteCount,
                digest: plan.left.digest
            ),
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try movedLeft.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
        let swappedDigest = TwoPaneWebPageNewPlan(
            left: TwoPaneWebPageNewPlanBoundSource(
                side: .left,
                normalizedURL: plan.left.normalizedURL,
                byteCount: plan.left.byteCount,
                digest: plan.right.digest
            ),
            right: plan.right,
            comparisonOptions: plan.comparisonOptions,
            limits: plan.limits,
            receipt: plan.receipt
        )
        XCTAssertThrowsError(try swappedDigest.validateReceipt()) { error in
            XCTAssertEqual(error as? TwoPaneWebPageNewPlanError, .receiptMismatch)
        }
    }

    func testCanonicalSHABindsComparisonLimits() throws {
        let baseline = try TwoPaneWebPageNewPlan.plan(validRequest()).receipt
        let base = WebPageComparisonLimits.default
        let inflatedTokens = WebPageComparisonLimits(
            maximumInputBytes: base.maximumInputBytes,
            maximumTokenCount: base.maximumTokenCount + 1_000,
            maximumAttributeCount: base.maximumAttributeCount,
            maximumAttributesPerTag: base.maximumAttributesPerTag,
            maximumElementDepth: base.maximumElementDepth,
            maximumWorkUnits: base.maximumWorkUnits,
            maximumOutputBytes: base.maximumOutputBytes
        )
        let inflatedRequest = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/mm-left.html", byte: 0x11),
            right: snapshot(path: "/tmp/mm-right.html", byte: 0x33),
            comparisonOptions: WebPageComparisonOptions(mode: .source, limits: inflatedTokens),
            limits: .default
        )
        let inflated = try TwoPaneWebPageNewPlan.plan(inflatedRequest).receipt
        XCTAssertNotEqual(baseline.planSHA256, inflated.planSHA256)
        XCTAssertNoThrow(try TwoPaneWebPageNewPlan.plan(inflatedRequest).validateReceipt())
        let inflatedDepth = WebPageComparisonLimits(
            maximumInputBytes: base.maximumInputBytes,
            maximumTokenCount: base.maximumTokenCount,
            maximumAttributeCount: base.maximumAttributeCount,
            maximumAttributesPerTag: base.maximumAttributesPerTag,
            maximumElementDepth: base.maximumElementDepth + 1_000,
            maximumWorkUnits: base.maximumWorkUnits,
            maximumOutputBytes: base.maximumOutputBytes
        )
        let depthRequest = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/mm-left.html", byte: 0x11),
            right: snapshot(path: "/tmp/mm-right.html", byte: 0x33),
            comparisonOptions: WebPageComparisonOptions(mode: .source, limits: inflatedDepth),
            limits: .default
        )
        let depthReceipt = try TwoPaneWebPageNewPlan.plan(depthRequest).receipt
        XCTAssertNotEqual(baseline.planSHA256, depthReceipt.planSHA256)
    }

    func testNonCancellationCheckpointErrorsPropagate() {
        struct ProbeFailure: Error {}
        XCTAssertThrowsError(
            try TwoPaneWebPageNewPlan.plan(validRequest(), cancellationCheck: { throw ProbeFailure() })
        ) { error in
            XCTAssertTrue(error is ProbeFailure)
            XCTAssertNil(error as? TwoPaneWebPageNewPlanError)
        }
    }

    func testComparisonTokenDepthLimitsAreUnbound() throws {
        let base = WebPageComparisonLimits.default
        let unbound = WebPageComparisonLimits(
            maximumInputBytes: base.maximumInputBytes,
            maximumTokenCount: base.maximumTokenCount * 10,
            maximumAttributeCount: base.maximumAttributeCount * 10,
            maximumAttributesPerTag: base.maximumAttributesPerTag * 10,
            maximumElementDepth: base.maximumElementDepth * 10,
            maximumWorkUnits: base.maximumWorkUnits,
            maximumOutputBytes: base.maximumOutputBytes
        )
        let request = TwoPaneWebPageNewPlanRequest(
            left: snapshot(path: "/tmp/a.html", byteCount: 100, byte: 0x11),
            right: snapshot(path: "/tmp/b.html", byteCount: 100, byte: 0x33),
            comparisonOptions: WebPageComparisonOptions(mode: .source, limits: unbound),
            limits: .default
        )
        XCTAssertNoThrow(try request.resolvedComparisonOptions())
        let plan = try TwoPaneWebPageNewPlan.plan(request)
        XCTAssertNoThrow(try plan.validateReceipt())
        XCTAssertEqual(try plan.resolvedComparisonOptions().limits.maximumTokenCount, unbound.maximumTokenCount)
        XCTAssertEqual(try plan.resolvedComparisonOptions().limits.maximumElementDepth, unbound.maximumElementDepth)
    }

    func testDuplicateRequiresDigestAndCountMatch() throws {
        let sameDigest = digest(0xAA)
        let digestOnlyMatch = TwoPaneWebPageNewPlanRequest(
            left: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/a.html"), byteCount: 100, digest: sameDigest),
            right: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/b.html"), byteCount: 101, digest: sameDigest)
        )
        XCTAssertNoThrow(try TwoPaneWebPageNewPlan.plan(digestOnlyMatch))
        let countOnlyMatch = TwoPaneWebPageNewPlanRequest(
            left: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/a.html"), byteCount: 100, digest: digest(0x11)),
            right: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/b.html"), byteCount: 100, digest: digest(0x33))
        )
        XCTAssertNoThrow(try TwoPaneWebPageNewPlan.plan(countOnlyMatch))
        let exactDuplicate = TwoPaneWebPageNewPlanRequest(
            left: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/a.html"), byteCount: 100, digest: sameDigest),
            right: TwoPaneWebPageNewPlanSnapshot(normalizedURL: url("/tmp/b.html"), byteCount: 100, digest: sameDigest)
        )
        assertPlanError(.duplicateSnapshot, request: exactDuplicate)
    }
}
