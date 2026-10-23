import Foundation
import MacMergeCore
import XCTest

final class TwoPaneHexNewPlanTests: XCTestCase {
    func testHappyPathPlansOrderedPanesWithReceipt() throws {
        let request = makeValidRequest()
        let plan = try TwoPaneHexNewPlanner.plan(request)
        XCTAssertEqual(plan.panes.map(\.side), [.left, .right])
        XCTAssertEqual(plan.window, request.window)
        XCTAssertEqual(plan.bytesPerRow, request.bytesPerRow)
        XCTAssertEqual(plan.receipt.sourceCount, 2)
        XCTAssertEqual(plan.receipt.windowOffset, request.window.offset)
        XCTAssertEqual(plan.receipt.windowLength, request.window.length)
        XCTAssertEqual(plan.receipt.bytesPerRow, request.bytesPerRow)
        XCTAssertEqual(plan.receipt.value.count, 64)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertTrue(plan.executorContract.readOnly)
        XCTAssertEqual(plan.limits, request.limits)
        XCTAssertGreaterThan(plan.estimatedWorkUnits, 0)
        XCTAssertEqual(plan.receipt.workUnits, plan.estimatedWorkUnits)
        XCTAssertEqual(plan.findings.count, 2)
        XCTAssertNoThrow(try plan.requireReceipt(plan.receipt))
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(plan))
    }

    func testMaximumSourcesMustEqualTwo() throws {
        XCTAssertEqual(TwoPaneHexNewLimits.hardMaximumSources, 2)
        let one = try TwoPaneHexNewLimits(maximumSources: 1)
        assertPlanningError(.invalidLimit(.sources)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(limits: one))
        }
        assertPlanningError(.invalidLimit(.sources)) {
            try TwoPaneHexNewLimits(maximumSources: 0)
        }
        assertPlanningError(.invalidLimit(.sources)) {
            try TwoPaneHexNewLimits(maximumSources: 3)
        }
        let ok = try TwoPaneHexNewLimits(maximumSources: 2)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.plan(makeValidRequest(limits: ok)))
    }

    func testDuplicateRevisionByDigestAloneRejected() {
        let shared = [UInt8](repeating: 0xAA, count: 32)
        let leftURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/digest-left.bin", isDirectory: false)
        let rightURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/digest-right.bin", isDirectory: false)
        let left = TwoPaneHexNewFileIdentity(canonicalURL: leftURL, canonicalPath: leftURL.path(percentEncoded: false), byteSize: 100, contentSHA256: shared)
        let right = TwoPaneHexNewFileIdentity(canonicalURL: rightURL, canonicalPath: rightURL.path(percentEncoded: false), byteSize: 200, contentSHA256: shared)
        let request = TwoPaneHexNewRequest(left: .file(left), right: .file(right), window: TwoPaneHexNewByteWindow(offset: 0, length: 16))
        assertPlanningError(.duplicateSourceRevision(first: .left, second: .right)) {
            try TwoPaneHexNewPlanner.plan(request)
        }
    }

    func testDuplicateRevisionByURLRejected() {
        let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/shared.bin", isDirectory: false)
        let path = url.path(percentEncoded: false)
        let left = TwoPaneHexNewFileIdentity(canonicalURL: url, canonicalPath: path, byteSize: 4096, contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let right = TwoPaneHexNewFileIdentity(canonicalURL: url, canonicalPath: path, byteSize: 4096, contentSHA256: [UInt8](repeating: 0x33, count: 32))
        let request = TwoPaneHexNewRequest(left: .file(left), right: .file(right), window: TwoPaneHexNewByteWindow(offset: 0, length: 16))
        assertPlanningError(.duplicateSourceRevision(first: .left, second: .right)) {
            try TwoPaneHexNewPlanner.plan(request)
        }
    }

    func testCancellationErrorMappedToCancelled() {
        let request = makeValidRequest()
        assertPlanningError(.cancelled) {
            try TwoPaneHexNewPlanner.plan(request, cancellationCheck: { throw CancellationError() })
        }
    }

    func testUnknownErrorRethrownUnchanged() {
        let request = makeValidRequest()
        XCTAssertThrowsError(try TwoPaneHexNewPlanner.plan(request, cancellationCheck: { throw CustomProbeError.boom })) { error in
            XCTAssertEqual(error as? CustomProbeError, .boom)
        }
        XCTAssertThrowsError(try TwoPaneHexNewPlanner.plan(request, cancellationCheck: { throw TwoPaneHexNewPlanningError.emptyByteRange })) { error in
            XCTAssertEqual(error as? TwoPaneHexNewPlanningError, .emptyByteRange)
        }
    }

    func testInvalidLimitEveryKind() {
        assertPlanningError(.invalidLimit(.sources)) {
            try TwoPaneHexNewLimits(maximumSources: 0)
        }
        assertPlanningError(.invalidLimit(.pathUTF8Bytes)) {
            try TwoPaneHexNewLimits(maximumPathUTF8Bytes: 0)
        }
        assertPlanningError(.invalidLimit(.pathUTF8Bytes)) {
            try TwoPaneHexNewLimits(maximumPathUTF8Bytes: TwoPaneHexNewLimits.hardMaximumPathUTF8Bytes + 1)
        }
        assertPlanningError(.invalidLimit(.totalPathUTF8Bytes)) {
            try TwoPaneHexNewLimits(maximumTotalPathUTF8Bytes: 0)
        }
        assertPlanningError(.invalidLimit(.totalPathUTF8Bytes)) {
            try TwoPaneHexNewLimits(maximumPathUTF8Bytes: 40, maximumTotalPathUTF8Bytes: 39)
        }
        assertPlanningError(.invalidLimit(.totalPathUTF8Bytes)) {
            try TwoPaneHexNewLimits(maximumTotalPathUTF8Bytes: TwoPaneHexNewLimits.hardMaximumTotalPathUTF8Bytes + 1)
        }
        assertPlanningError(.invalidLimit(.byteSize)) {
            try TwoPaneHexNewLimits(maximumByteSize: 0)
        }
        assertPlanningError(.invalidLimit(.byteSize)) {
            try TwoPaneHexNewLimits(maximumByteSize: TwoPaneHexNewLimits.hardMaximumByteSize + 1)
        }
        assertPlanningError(.invalidLimit(.windowLength)) {
            try TwoPaneHexNewLimits(maximumWindowLength: 0)
        }
        assertPlanningError(.invalidLimit(.windowLength)) {
            try TwoPaneHexNewLimits(maximumWindowLength: TwoPaneHexNewLimits.hardMaximumWindowLength + 1)
        }
        assertPlanningError(.invalidLimit(.bytesPerRow)) {
            try TwoPaneHexNewLimits(maximumBytesPerRow: 0)
        }
        assertPlanningError(.invalidLimit(.bytesPerRow)) {
            try TwoPaneHexNewLimits(maximumBytesPerRow: TwoPaneHexNewLimits.hardMaximumBytesPerRow + 1)
        }
        assertPlanningError(.invalidLimit(.stringBytes)) {
            try TwoPaneHexNewLimits(maximumStringBytes: 0)
        }
        assertPlanningError(.invalidLimit(.stringBytes)) {
            try TwoPaneHexNewLimits(maximumStringBytes: TwoPaneHexNewLimits.hardMaximumStringBytes + 1)
        }
        assertPlanningError(.invalidLimit(.findings)) {
            try TwoPaneHexNewLimits(maximumFindings: 0)
        }
        assertPlanningError(.invalidLimit(.findings)) {
            try TwoPaneHexNewLimits(maximumFindings: TwoPaneHexNewLimits.hardMaximumFindings + 1)
        }
        assertPlanningError(.invalidLimit(.workUnits)) {
            try TwoPaneHexNewLimits(maximumWorkUnits: 0)
        }
        assertPlanningError(.invalidLimit(.workUnits)) {
            try TwoPaneHexNewLimits(maximumWorkUnits: TwoPaneHexNewLimits.hardMaximumWorkUnits + 1)
        }
        assertPlanningError(.invalidLimit(.cancellationCheckInterval)) {
            try TwoPaneHexNewLimits(cancellationCheckInterval: 0)
        }
        assertPlanningError(.invalidLimit(.cancellationCheckInterval)) {
            try TwoPaneHexNewLimits(cancellationCheckInterval: TwoPaneHexNewLimits.hardMaximumCancellationCheckInterval + 1)
        }
    }

    func testInvalidPaneCount() {
        let full = makeValidRequest()
        assertPlanningError(.invalidPaneCount(actual: 0)) {
            try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(panes: [], window: full.window))
        }
        assertPlanningError(.invalidPaneCount(actual: 1)) {
            try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(panes: Array(full.panes.prefix(1)), window: full.window))
        }
        assertPlanningError(.invalidPaneCount(actual: 3)) {
            try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(panes: full.panes + [full.panes[0]], window: full.window))
        }
    }

    func testDuplicatePane() {
        let request = makeValidRequest()
        let duplicated = TwoPaneHexNewRequest(panes: [request.panes[0], request.panes[0]], window: request.window)
        assertPlanningError(.duplicatePane(.left)) {
            try TwoPaneHexNewPlanner.plan(duplicated)
        }
    }

    func testMissingPaneMetadata() {
        for side in TwoPaneHexNewSide.allCases {
            let error = TwoPaneHexNewPlanningError.missingPane(side)
            XCTAssertTrue(error.errorDescription?.contains(side.rawValue) ?? false)
            XCTAssertEqual(error.debugDescription, error.errorDescription)
        }
        XCTAssertEqual(TwoPaneHexNewPlanningError.missingPane(.right).errorDescription, "Two-pane hex new is missing the right pane.")
    }

    func testEmptyPanesAllowedForNew() throws {
        let right = makeIdentity(name: "empty-right.bin", byteSize: 4096, digestByte: 0x33)
        let range = TwoPaneHexNewByteWindow(offset: 0, length: 16)
        let mixed = try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(left: .empty, right: .file(right), window: range))
        XCTAssertEqual(mixed.receipt.sourceCount, 1)
        XCTAssertTrue(mixed.panes[0].isEmpty)
        let bothEmpty = try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(left: .empty, right: .empty, window: range))
        XCTAssertEqual(bothEmpty.receipt.sourceCount, 0)
    }

    func testInvalidCanonicalURL() {
        let right = makeIdentity(name: "url-right.bin", byteSize: 4096, digestByte: 0x33)
        let range = TwoPaneHexNewByteWindow(offset: 0, length: 16)
        let badHTTPS = URL(string: "https://example.com/file.bin")!
        XCTAssertEqual(badHTTPS.scheme, "https")
        let httpsIdentity = TwoPaneHexNewFileIdentity(
            canonicalURL: badHTTPS, canonicalPath: "/file.bin", byteSize: 4096, contentSHA256: [UInt8](repeating: 0x11, count: 32))
        assertPlanningError(.invalidCanonicalURL(.left)) {
            try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(left: .file(httpsIdentity), right: .file(right), window: range))
        }
        for badPath in ["/tmp/macmerge-hex-new/a/../b.bin", "/tmp/macmerge-hex-new/./c.bin"] {
            let badURL = URL(fileURLWithPath: badPath, isDirectory: false)
            XCTAssertNotEqual(badURL, badURL.standardizedFileURL)
            let badIdentity = TwoPaneHexNewFileIdentity(
                canonicalURL: badURL, canonicalPath: badURL.path(percentEncoded: false), byteSize: 4096,
                contentSHA256: [UInt8](repeating: 0x11, count: 32))
            assertPlanningError(.invalidCanonicalURL(.left)) {
                try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(left: .file(badIdentity), right: .file(right), window: range))
            }
        }
        let slashURL = URL(string: "file:///tmp//macmerge-hex-new/d.bin")!
        XCTAssertNotEqual(slashURL, slashURL.standardizedFileURL)
        let slashIdentity = TwoPaneHexNewFileIdentity(
            canonicalURL: slashURL, canonicalPath: slashURL.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x11, count: 32))
        assertPlanningError(.invalidCanonicalURL(.left)) {
            try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(left: .file(slashIdentity), right: .file(right), window: range))
        }
    }

    func testCanonicalPathMismatch() {
        let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/left.bin", isDirectory: false)
        let identity = TwoPaneHexNewFileIdentity(
            canonicalURL: url, canonicalPath: "/tmp/mismatch.bin", byteSize: 4096, contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let right = makeIdentity(name: "mismatch-right.bin", byteSize: 4096, digestByte: 0x33)
        let request = TwoPaneHexNewRequest(left: .file(identity), right: .file(right), window: TwoPaneHexNewByteWindow(offset: 0, length: 16))
        assertPlanningError(.canonicalPathMismatch(.left)) {
            try TwoPaneHexNewPlanner.plan(request)
        }
    }

    func testPathTooLargeBoundary() throws {
        let left = makeIdentity(name: "aa.bin", byteSize: 4096, digestByte: 0x11)
        let right = makeIdentity(name: "bb.bin", byteSize: 4096, digestByte: 0x33)
        let exactBytes = left.canonicalPath.utf8.count
        XCTAssertEqual(right.canonicalPath.utf8.count, exactBytes)
        let exact = try TwoPaneHexNewLimits(maximumPathUTF8Bytes: exactBytes)
        let range = TwoPaneHexNewByteWindow(offset: 0, length: 16)
        let exactRequest = TwoPaneHexNewRequest(left: .file(left), right: .file(right), window: range, limits: exact)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.plan(exactRequest))
        let short = try TwoPaneHexNewLimits(maximumPathUTF8Bytes: exactBytes - 1)
        let shortRequest = TwoPaneHexNewRequest(left: .file(left), right: .file(right), window: range, limits: short)
        assertPlanningError(.pathTooLarge(side: .left, maximumBytes: exactBytes - 1)) {
            try TwoPaneHexNewPlanner.plan(shortRequest)
        }
    }

    func testPathGuardRejectsEachSide() throws {
        let left = makeIdentity(name: "aa.bin", byteSize: 4096, digestByte: 0x11)
        let exactBytes = left.canonicalPath.utf8.count
        let limit = try TwoPaneHexNewLimits(maximumPathUTF8Bytes: exactBytes)
        let range = TwoPaneHexNewByteWindow(offset: 0, length: 16)
        let longRight = makeIdentity(name: String(repeating: "r", count: 64) + ".bin", byteSize: 4096, digestByte: 0x33)
        assertPlanningError(.pathTooLarge(side: .right, maximumBytes: exactBytes)) {
            try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(left: .file(left), right: .file(longRight), window: range, limits: limit))
        }
    }

    func testTotalPathTooLarge() throws {
        let left = makeIdentity(name: "aa.bin", byteSize: 4096, digestByte: 0x11)
        let right = makeIdentity(name: "bb.bin", byteSize: 4096, digestByte: 0x33)
        let exactBytes = left.canonicalPath.utf8.count
        let total = exactBytes + right.canonicalPath.utf8.count
        let limit = try TwoPaneHexNewLimits(maximumPathUTF8Bytes: exactBytes, maximumTotalPathUTF8Bytes: total - 1)
        let request = TwoPaneHexNewRequest(left: .file(left), right: .file(right), window: TwoPaneHexNewByteWindow(offset: 0, length: 16), limits: limit)
        assertPlanningError(.totalPathTooLarge(maximumBytes: total - 1)) {
            try TwoPaneHexNewPlanner.plan(request)
        }
    }

    func testByteSizeTooLargeBoundary() throws {
        let exact = try TwoPaneHexNewLimits(maximumByteSize: 4096)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.plan(makeValidRequest(byteSize: 4096, limits: exact)))
        let short = try TwoPaneHexNewLimits(maximumByteSize: 4095)
        assertPlanningError(.byteSizeTooLarge(side: .left, maximumBytes: 4095)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(byteSize: 4096, limits: short))
        }
    }

    func testInvalidDigestEverySize() {
        for count in [0, 31, 33] {
            let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/bad-digest.bin", isDirectory: false)
            let bad = TwoPaneHexNewFileIdentity(
                canonicalURL: url, canonicalPath: url.path(percentEncoded: false), byteSize: 4096, contentSHA256: [UInt8](repeating: 0x11, count: count))
            let right = makeIdentity(name: "digest-ok-right.bin", byteSize: 4096, digestByte: 0x33)
            let request = TwoPaneHexNewRequest(left: .file(bad), right: .file(right), window: TwoPaneHexNewByteWindow(offset: 0, length: 16))
            assertPlanningError(.invalidDigest(.left)) {
                try TwoPaneHexNewPlanner.plan(request)
            }
        }
    }

    func testInvalidBytesPerRowBoundaries() throws {
        XCTAssertEqual(TwoPaneHexNewRequest.minimumBytesPerRow, 1)
        XCTAssertEqual(TwoPaneHexNewRequest.maximumBytesPerRow, 64)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 1)))
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 16)))
        let wide = try TwoPaneHexNewLimits(maximumBytesPerRow: 64)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 64, limits: wide)))
        assertPlanningError(.invalidBytesPerRow(actual: 0)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(bytesPerRow: 0))
        }
        assertPlanningError(.invalidBytesPerRow(actual: 65)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(bytesPerRow: 65))
        }
        let narrow = try TwoPaneHexNewLimits(maximumBytesPerRow: 8)
        assertPlanningError(.invalidBytesPerRow(actual: 16)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(bytesPerRow: 16, limits: narrow))
        }
    }

    func testEmptyByteRange() {
        assertPlanningError(.emptyByteRange) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(window: TwoPaneHexNewByteWindow(offset: 0, length: 0)))
        }
    }

    func testByteRangeTooLargeBoundary() throws {
        let exact = try TwoPaneHexNewLimits(maximumWindowLength: 16)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.plan(makeValidRequest(window: TwoPaneHexNewByteWindow(offset: 0, length: 16), limits: exact)))
        assertPlanningError(.byteRangeTooLarge(maximumBytes: 16)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(window: TwoPaneHexNewByteWindow(offset: 0, length: 17), limits: exact))
        }
    }

    func testInvalidByteRangeOverflow() {
        assertPlanningError(.invalidByteRange) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(window: TwoPaneHexNewByteWindow(offset: UInt64.max, length: 1)))
        }
    }

    func testRangeOutOfBounds() {
        assertPlanningError(.rangeOutOfBounds(.left)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(byteSize: 100, window: TwoPaneHexNewByteWindow(offset: 90, length: 20)))
        }
        let bigLeft = makeIdentity(name: "oob-left.bin", byteSize: 4096, digestByte: 0x11)
        let smallRight = makeIdentity(name: "oob-right.bin", byteSize: 100, digestByte: 0x33)
        assertPlanningError(.rangeOutOfBounds(.right)) {
            try TwoPaneHexNewPlanner.plan(
                TwoPaneHexNewRequest(left: .file(bigLeft), right: .file(smallRight), window: TwoPaneHexNewByteWindow(offset: 90, length: 20)))
        }
    }

    func testRangeAtExactFileEndAccepted() throws {
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.plan(makeValidRequest(byteSize: 100, window: TwoPaneHexNewByteWindow(offset: 84, length: 16))))
        assertPlanningError(.rangeOutOfBounds(.left)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(byteSize: 100, window: TwoPaneHexNewByteWindow(offset: 85, length: 16)))
        }
    }

    func testReceiptMismatch() throws {
        let plan = try TwoPaneHexNewPlanner.plan(makeValidRequest())
        let wrong = TwoPaneHexNewReceipt(
            value: String(repeating: "0", count: 64), sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset,
            windowLength: plan.receipt.windowLength, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits)
        XCTAssertNotEqual(wrong, plan.receipt)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(wrong)
        }
        XCTAssertNoThrow(try plan.requireReceipt(plan.receipt))
    }

    func testStaleReceiptFieldsRejected() throws {
        let plan = try TwoPaneHexNewPlanner.plan(makeValidRequest())
        let tamperedCount = TwoPaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount + 1, windowOffset: plan.receipt.windowOffset,
            windowLength: plan.receipt.windowLength, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedCount)
        }
        let tamperedLength = TwoPaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset,
            windowLength: plan.receipt.windowLength + 1, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedLength)
        }
        let tamperedRow = TwoPaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset, windowLength: plan.receipt.windowLength,
            bytesPerRow: plan.receipt.bytesPerRow + 1, workUnits: plan.receipt.workUnits)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedRow)
        }
        let tamperedOffset = TwoPaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset + 1,
            windowLength: plan.receipt.windowLength, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedOffset)
        }
        let tamperedWork = TwoPaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset,
            windowLength: plan.receipt.windowLength, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits + 1)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedWork)
        }
    }

    func testWorkLimitExceededBoundary() throws {
        let baseline = try TwoPaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertGreaterThan(baseline.estimatedWorkUnits, 1)
        // findingBytes = findings.count(2) + 16 = 18 must fit in work budget.
        let required = max(baseline.estimatedWorkUnits, UInt64(baseline.findings.count) + 16)
        XCTAssertEqual(required, 18)
        let exact = try TwoPaneHexNewLimits(maximumWorkUnits: required)
        let exactPlan = try TwoPaneHexNewPlanner.plan(makeValidRequest(limits: exact))
        XCTAssertEqual(exactPlan.estimatedWorkUnits, baseline.estimatedWorkUnits)
        let short = try TwoPaneHexNewLimits(maximumWorkUnits: required - 1)
        assertPlanningError(.workLimitExceeded(maximumUnits: required - 1)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(limits: short))
        }
    }

    func testTinyWorkBudgetThrowsSpecificWorkLimitExceeded() throws {
        let tiny = try TwoPaneHexNewLimits(maximumWorkUnits: 1)
        assertPlanningError(.workLimitExceeded(maximumUnits: 1)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(limits: tiny))
        }
    }

    func testLimitsValidatedBeforeMetering() throws {
        let tinyInvalidSources = try TwoPaneHexNewLimits(maximumSources: 1, maximumWorkUnits: 1)
        assertPlanningError(.invalidLimit(.sources)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(limits: tinyInvalidSources))
        }
    }

    func testCancellationAbortsPlanning() throws {
        let request = makeValidRequest()
        let immediate = CancellationProbe(cancelAtCall: 1)
        assertPlanningError(.cancelled) {
            try TwoPaneHexNewPlanner.plan(request, cancellationCheck: { try immediate.check() })
        }
        XCTAssertEqual(immediate.callCount, 1)
        let later = CancellationProbe(cancelAtCall: 5)
        assertPlanningError(.cancelled) {
            try TwoPaneHexNewPlanner.plan(request, cancellationCheck: { try later.check() })
        }
        let passing = CancellationProbe(cancelAtCall: Int.max)
        let plan = try TwoPaneHexNewPlanner.plan(request, cancellationCheck: { try passing.check() })
        XCTAssertGreaterThan(plan.estimatedWorkUnits, 0)
        XCTAssertGreaterThan(passing.callCount, 0)
    }

    func testReceiptDeterministicAcrossOrderAndRepeats() throws {
        let request = makeValidRequest()
        let first = try TwoPaneHexNewPlanner.plan(request)
        let second = try TwoPaneHexNewPlanner.plan(request)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
        let reversed = TwoPaneHexNewRequest(panes: Array(request.panes.reversed()), window: request.window, bytesPerRow: request.bytesPerRow)
        let ordered = try TwoPaneHexNewPlanner.plan(reversed)
        XCTAssertEqual(ordered.receipt, first.receipt)
        XCTAssertEqual(ordered.panes.map(\.side), [.left, .right])
        let differentRow = try TwoPaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 8))
        XCTAssertNotEqual(differentRow.receipt, first.receipt)
    }

    func testReceiptBindsRangeRowAndSourceCount() throws {
        let base = try TwoPaneHexNewPlanner.plan(makeValidRequest())
        let diffOffset = try TwoPaneHexNewPlanner.plan(makeValidRequest(window: TwoPaneHexNewByteWindow(offset: 1, length: 16)))
        XCTAssertNotEqual(diffOffset.receipt, base.receipt)
        XCTAssertNotEqual(diffOffset.receipt.value, base.receipt.value)
        let diffRow = try TwoPaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 8))
        XCTAssertNotEqual(diffRow.receipt, base.receipt)
        let diffLength = try TwoPaneHexNewPlanner.plan(makeValidRequest(window: TwoPaneHexNewByteWindow(offset: 0, length: 17)))
        XCTAssertNotEqual(diffLength.receipt, base.receipt)
        XCTAssertNotEqual(diffLength.receipt.value, base.receipt.value)
        XCTAssertEqual(diffLength.receipt.windowLength, 17)
        let diffRightDigest = try TwoPaneHexNewPlanner.plan(
            TwoPaneHexNewRequest(
                left: .file(makeIdentity(name: "left.bin", byteSize: 4096, digestByte: 0x11)),
                right: .file(makeIdentity(name: "right.bin", byteSize: 4096, digestByte: 0x44)),
                window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertNotEqual(diffRightDigest.receipt, base.receipt)
        XCTAssertNotEqual(diffRightDigest.receipt.value, base.receipt.value)
        let forgedURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/right.bin", isDirectory: false)
        let forgedRight = TwoPaneHexNewFileIdentity(
            canonicalURL: forgedURL, canonicalPath: forgedURL.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0xFF, count: 32))
        let forged = try TwoPaneHexNewPlanner.plan(
            TwoPaneHexNewRequest(
                left: .file(makeIdentity(name: "left.bin", byteSize: 4096, digestByte: 0x11)),
                right: .file(forgedRight),
                window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertNotEqual(forged.receipt, base.receipt)
        XCTAssertNotEqual(forged.receipt.value, base.receipt.value)
        let oneEmpty = try TwoPaneHexNewPlanner.plan(
            TwoPaneHexNewRequest(
                left: .file(makeIdentity(name: "rb-left.bin", byteSize: 4096, digestByte: 0x11)),
                right: .empty,
                window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertEqual(oneEmpty.receipt.sourceCount, 1)
        XCTAssertNotEqual(oneEmpty.receipt, base.receipt)
    }

    func testRedactionHidesPathsAndDigests() throws {
        let identity = makeIdentity(name: "secret.bin", byteSize: 4096, digestByte: 0xAB)
        XCTAssertFalse(identity.description.contains(identity.canonicalPath))
        XCTAssertFalse(identity.description.contains(identity.canonicalURL.absoluteString))
        XCTAssertFalse(identity.debugDescription.contains(identity.canonicalPath))
        XCTAssertNil(identity.customMirror.children.first(where: { "\($0.value)".contains(identity.canonicalPath) }))
        let source = TwoPaneHexNewPaneSource.file(identity)
        XCTAssertFalse(source.description.contains(identity.canonicalPath))
        XCTAssertTrue(source.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
        let pane = TwoPaneHexNewPane(side: .left, source: source)
        XCTAssertTrue(pane.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
        let request = makeValidRequest()
        XCTAssertFalse(request.description.contains(identity.canonicalPath))
        XCTAssertTrue(request.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
        let plan = try TwoPaneHexNewPlanner.plan(request)
        XCTAssertFalse(plan.description.contains(request.panes[0].source.description))
        XCTAssertTrue(plan.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
        let error = TwoPaneHexNewPlanningError.cancelled
        XCTAssertTrue(error.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
    }

    func testCommandIDAndExecutorContract() throws {
        XCTAssertEqual(TwoPaneHexNewPlanner.commandID, "ID_FILE_NEW_HEX")
        let fileManager = FileManager.default
        XCTAssertFalse(fileManager.fileExists(atPath: "/tmp/macmerge-hex-new/left.bin"))
        XCTAssertFalse(fileManager.fileExists(atPath: "/tmp/macmerge-hex-new/right.bin"))
        let plan = try TwoPaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertEqual(plan.executorContract.sourceRevision, .exactDigestPinnedThroughExecution)
        XCTAssertEqual(plan.executorContract.range, .windowedReadOnlyNoMutation)
        XCTAssertEqual(plan.executorContract.fileSystem, .planOnlyNoFileSystemAccess)
        XCTAssertEqual(plan.executorContract.cancellation, .cancellableDuringPlanningOnly)
        XCTAssertTrue(plan.executorContract.readOnly)
        XCTAssertTrue(plan.panes.allSatisfy(\.isReadOnly))
    }

    func testLimitsHardBoundariesAccepted() throws {
        let hard = try TwoPaneHexNewLimits(
            maximumSources: TwoPaneHexNewLimits.hardMaximumSources,
            maximumPathUTF8Bytes: TwoPaneHexNewLimits.hardMaximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: TwoPaneHexNewLimits.hardMaximumTotalPathUTF8Bytes,
            maximumByteSize: TwoPaneHexNewLimits.hardMaximumByteSize,
            maximumWindowLength: TwoPaneHexNewLimits.hardMaximumWindowLength,
            maximumBytesPerRow: TwoPaneHexNewLimits.hardMaximumBytesPerRow,
            maximumStringBytes: TwoPaneHexNewLimits.hardMaximumStringBytes,
            maximumFindings: TwoPaneHexNewLimits.hardMaximumFindings,
            maximumWorkUnits: TwoPaneHexNewLimits.hardMaximumWorkUnits,
            cancellationCheckInterval: TwoPaneHexNewLimits.hardMaximumCancellationCheckInterval
        )
        XCTAssertNoThrow(try hard.validate())
        XCTAssertNoThrow(try TwoPaneHexNewLimits.default.validate())
        XCTAssertEqual(TwoPaneHexNewLimits.default.maximumSources, 2)
        let hardPlan = try TwoPaneHexNewPlanner.plan(makeValidRequest(limits: hard))
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(hardPlan))
        XCTAssertEqual(hardPlan.limits, hard)
    }

    func testZeroCancellationIntervalThrowsInvalidLimitNotTrap() {
        assertPlanningError(.invalidLimit(.cancellationCheckInterval)) {
            try TwoPaneHexNewLimits(cancellationCheckInterval: 0)
        }
        assertPlanningError(.invalidLimit(.cancellationCheckInterval)) {
            try TwoPaneHexNewLimits(cancellationCheckInterval: TwoPaneHexNewLimits.hardMaximumCancellationCheckInterval + 1)
        }
    }

    func testNotReadOnlyRejected() throws {
        let left = makeIdentity(name: "ro-left.bin", byteSize: 4096, digestByte: 0x11)
        let right = makeIdentity(name: "ro-right.bin", byteSize: 4096, digestByte: 0x33)
        let range = TwoPaneHexNewByteWindow(offset: 0, length: 16)
        let leftWritable = TwoPaneHexNewRequest(
            panes: [
                TwoPaneHexNewPane(side: .left, source: .file(left), isReadOnly: false),
                TwoPaneHexNewPane(side: .right, source: .file(right), isReadOnly: true)
            ],
            window: range
        )
        assertPlanningError(.notReadOnly(.left)) {
            try TwoPaneHexNewPlanner.plan(leftWritable)
        }
        let rightWritable = TwoPaneHexNewRequest(
            panes: [
                TwoPaneHexNewPane(side: .left, source: .file(left), isReadOnly: true),
                TwoPaneHexNewPane(side: .right, source: .file(right), isReadOnly: false)
            ],
            window: range
        )
        assertPlanningError(.notReadOnly(.right)) {
            try TwoPaneHexNewPlanner.plan(rightWritable)
        }
    }

    func testStringBudgetExceeded() throws {
        let tight = try TwoPaneHexNewLimits(maximumStringBytes: 1)
        assertPlanningError(.stringBudgetExceeded(maximumBytes: 1)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(limits: tight))
        }
    }

    func testTooManyFindings() throws {
        let tight = try TwoPaneHexNewLimits(maximumFindings: 1)
        assertPlanningError(.tooManyFindings(maximum: 1)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(limits: tight))
        }
    }

    func testUnsupportedCapability() throws {
        let badThreeWay = ThreeWayBinaryComparisonOptions(
            maximumInputBytes: -1,
            maximumExactEditDistance: 0,
            maximumAlignmentWork: 0,
            maximumRegions: 0,
            maximumOutputBytes: 0
        )
        let capability = TwoPaneHexNewCapabilityRequirement(threeWay: badThreeWay)
        assertPlanningError(.unsupportedCapability) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(capability: capability))
        }
    }

    func testFindingsCoverFullAndWindowed() throws {
        let full = try TwoPaneHexNewPlanner.plan(makeValidRequest(byteSize: 16, window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertEqual(full.findings, [.fullCoverage, .fullCoverage])
        let partial = try TwoPaneHexNewPlanner.plan(makeValidRequest(byteSize: 4096, window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertEqual(partial.findings, [.windowedView, .windowedView])
        XCTAssertNotEqual(full.receipt, partial.receipt)
    }

    // validate() is limits-bound: plans sitting exactly on the window,
    // byteSize, and work-unit boundaries revalidate cleanly.
    func testValidateAcceptsLimitsBoundWindowByteSizeWorkUnits() throws {
        let windowExact = try TwoPaneHexNewLimits(maximumWindowLength: 16)
        let windowPlan = try TwoPaneHexNewPlanner.plan(
            makeValidRequest(window: TwoPaneHexNewByteWindow(offset: 0, length: 16), limits: windowExact))
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(windowPlan))

        let byteExact = try TwoPaneHexNewLimits(maximumByteSize: 4096)
        let bytePlan = try TwoPaneHexNewPlanner.plan(makeValidRequest(byteSize: 4096, limits: byteExact))
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(bytePlan))

        let baseline = try TwoPaneHexNewPlanner.plan(makeValidRequest())
        let required = max(baseline.estimatedWorkUnits, UInt64(baseline.findings.count) + 16)
        let workExact = try TwoPaneHexNewLimits(maximumWorkUnits: required)
        let workPlan = try TwoPaneHexNewPlanner.plan(makeValidRequest(limits: workExact))
        XCTAssertEqual(workPlan.estimatedWorkUnits, baseline.estimatedWorkUnits)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(workPlan))

        let hardWindow = try TwoPaneHexNewLimits(maximumWindowLength: TwoPaneHexNewLimits.hardMaximumWindowLength)
        let hardWindowPlan = try TwoPaneHexNewPlanner.plan(
            makeValidRequest(window: TwoPaneHexNewByteWindow(offset: 0, length: 16), limits: hardWindow))
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(hardWindowPlan))
        assertPlanningError(.invalidLimit(.windowLength)) {
            try TwoPaneHexNewLimits(maximumWindowLength: TwoPaneHexNewLimits.hardMaximumWindowLength + 1)
        }
        let wider = try TwoPaneHexNewPlanner.plan(makeValidRequest(window: TwoPaneHexNewByteWindow(offset: 0, length: 17)))
        assertPlanningError(.receiptMismatch) {
            try windowPlan.requireReceipt(wider.receipt)
        }
        let row8 = try TwoPaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 8))
        let row16 = try TwoPaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 16))
        assertPlanningError(.receiptMismatch) {
            try row16.requireReceipt(row8.receipt)
        }
        let full = try TwoPaneHexNewPlanner.plan(makeValidRequest(byteSize: 16, window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        let partial = try TwoPaneHexNewPlanner.plan(makeValidRequest(byteSize: 4096, window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertNotEqual(full.findings, partial.findings)
        assertPlanningError(.receiptMismatch) {
            try full.requireReceipt(partial.receipt)
        }
        let tamperedWork = TwoPaneHexNewReceipt(
            value: workPlan.receipt.value, sourceCount: workPlan.receipt.sourceCount, windowOffset: workPlan.receipt.windowOffset,
            windowLength: workPlan.receipt.windowLength, bytesPerRow: workPlan.receipt.bytesPerRow, workUnits: workPlan.receipt.workUnits + 1)
        assertPlanningError(.receiptMismatch) {
            try workPlan.requireReceipt(tamperedWork)
        }
    }

    // Limits-bound rejection with fresh SHA: distinct digests (0x11 vs 0x33)
    // ensure the over-limit guard fires, not duplicate detection. None pass.
    func testOverLimitWindowByteSizeWorkUnitsRejectedWithFreshSHA() throws {
        let windowLimit = try TwoPaneHexNewLimits(maximumWindowLength: 16)
        assertPlanningError(.byteRangeTooLarge(maximumBytes: 16)) {
            try TwoPaneHexNewPlanner.plan(
                self.makeValidRequest(window: TwoPaneHexNewByteWindow(offset: 0, length: 17), limits: windowLimit))
        }
        let byteLimit = try TwoPaneHexNewLimits(maximumByteSize: 4095)
        assertPlanningError(.byteSizeTooLarge(side: .left, maximumBytes: 4095)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(byteSize: 4096, limits: byteLimit))
        }
        let tiny = try TwoPaneHexNewLimits(maximumWorkUnits: 1)
        assertPlanningError(.workLimitExceeded(maximumUnits: 1)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(limits: tiny))
        }
    }

    // Trust-boundary revalidation: validate() re-checks canonical URL shape,
    // path budgets, digest shape, distinct revisions, and capability
    // carry-through on the materialized plan.
    func testValidateRevalidatesTrustBoundaryInputs() throws {
        let left = makeIdentity(name: "budget-l.bin", byteSize: 4096, digestByte: 0x11)
        let right = makeIdentity(name: "budget-r.bin", byteSize: 4096, digestByte: 0x33)
        let exactBytes = left.canonicalPath.utf8.count
        XCTAssertEqual(right.canonicalPath.utf8.count, exactBytes)
        let budgeted = try TwoPaneHexNewLimits(maximumPathUTF8Bytes: exactBytes)
        let budgetedPlan = try TwoPaneHexNewPlanner.plan(
            TwoPaneHexNewRequest(
                left: .file(left), right: .file(right),
                window: TwoPaneHexNewByteWindow(offset: 0, length: 16), limits: budgeted))
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(budgetedPlan))

        let zeroCapability = TwoPaneHexNewCapabilityRequirement(
            threeWay: ThreeWayBinaryComparisonOptions(
                maximumInputBytes: 0, maximumExactEditDistance: 0, maximumAlignmentWork: 0,
                maximumRegions: 0, maximumOutputBytes: 0))
        let zeroPlan = try TwoPaneHexNewPlanner.plan(makeValidRequest(capability: zeroCapability))
        XCTAssertEqual(zeroPlan.capability, zeroCapability)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(zeroPlan))
        let defaultPlan = try TwoPaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertNotEqual(zeroPlan.receipt, defaultPlan.receipt)
        XCTAssertNotEqual(zeroPlan.receipt.value, defaultPlan.receipt.value)

        let mixed = try TwoPaneHexNewPlanner.plan(
            TwoPaneHexNewRequest(
                left: .file(makeIdentity(name: "tv-mixed-left.bin", byteSize: 4096, digestByte: 0x11)),
                right: .empty,
                window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertEqual(mixed.receipt.sourceCount, 1)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(mixed))
    }

    func testTmpVsPrivateTmpDuplicateSemantics() throws {
        let tmpURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/alias-tmp.bin", isDirectory: false)
        let privateURL = URL(fileURLWithPath: "/private/tmp/macmerge-hex-new/alias-tmp.bin", isDirectory: false)
        XCTAssertNotEqual(tmpURL, privateURL)
        let tmpIdentity = TwoPaneHexNewFileIdentity(
            canonicalURL: tmpURL, canonicalPath: tmpURL.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let privateIdentity = TwoPaneHexNewFileIdentity(
            canonicalURL: privateURL, canonicalPath: privateURL.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x33, count: 32))
        let distinct = try TwoPaneHexNewPlanner.plan(
            TwoPaneHexNewRequest(
                left: .file(tmpIdentity), right: .file(privateIdentity),
                window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(distinct))
        let sharedPrivateURL = URL(fileURLWithPath: "/private/tmp/macmerge-hex-new/shared-private.bin", isDirectory: false)
        let sharedPrivatePath = sharedPrivateURL.path(percentEncoded: false)
        let leftShared = TwoPaneHexNewFileIdentity(
            canonicalURL: sharedPrivateURL, canonicalPath: sharedPrivatePath, byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let rightShared = TwoPaneHexNewFileIdentity(
            canonicalURL: sharedPrivateURL, canonicalPath: sharedPrivatePath, byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x33, count: 32))
        assertPlanningError(.duplicateSourceRevision(first: .left, second: .right)) {
            try TwoPaneHexNewPlanner.plan(
                TwoPaneHexNewRequest(
                    left: .file(leftShared), right: .file(rightShared),
                    window: TwoPaneHexNewByteWindow(offset: 0, length: 16)))
        }
    }

    // Dual-tier maximumSources: Limits accepts 1...hardMaximumSources so
    // restricted configurations validate, but planning always requires
    // exactly two panes (unbound slots model as .empty, never a shorter array).
    func testDualTierMaximumSourcesDocumentsRestrictedConfigs() throws {
        XCTAssertEqual(TwoPaneHexNewLimits.hardMaximumSources, 2)
        let restricted = try TwoPaneHexNewLimits(maximumSources: 1)
        XCTAssertNoThrow(try restricted.validate())
        assertPlanningError(.invalidLimit(.sources)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(limits: restricted))
        }
        let exact = try TwoPaneHexNewLimits(maximumSources: 2)
        let plan = try TwoPaneHexNewPlanner.plan(makeValidRequest(limits: exact))
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.validate(plan))
    }

    // Pane-count-before-consume precedence: an invalid pane count reports
    // invalidPaneCount even when the work budget is already exhausted,
    // because the count guard runs before the per-pane work charges.
    func testPaneCountCheckedBeforeMeteringPrecedence() throws {
        let baseline = try TwoPaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertGreaterThan(baseline.estimatedWorkUnits, 1)
        let tight = try TwoPaneHexNewLimits(maximumWorkUnits: baseline.estimatedWorkUnits - 1)
        let full = makeValidRequest()
        assertPlanningError(.invalidPaneCount(actual: 0)) {
            try TwoPaneHexNewPlanner.plan(TwoPaneHexNewRequest(panes: [], window: full.window, limits: tight))
        }
        assertPlanningError(.invalidPaneCount(actual: 3)) {
            try TwoPaneHexNewPlanner.plan(
                TwoPaneHexNewRequest(panes: full.panes + [full.panes[0]], window: full.window, limits: tight))
        }
    }

    // findingBytes overflow-safe path: findings.count(2) + 16 = 18 uses
    // addingReportingOverflow, never traps. 17 rejects, 18 accepts.
    func testFindingBytesOverflowSafeBoundaryRequiresEighteen() throws {
        let baseline = try TwoPaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertEqual(baseline.findings.count, 2)
        let (bytes, overflow) = UInt64(baseline.findings.count).addingReportingOverflow(16)
        XCTAssertFalse(overflow)
        XCTAssertEqual(bytes, 18)
        let tight = try TwoPaneHexNewLimits(maximumWorkUnits: 17)
        assertPlanningError(.workLimitExceeded(maximumUnits: 17)) {
            try TwoPaneHexNewPlanner.plan(self.makeValidRequest(limits: tight))
        }
        let ok = try TwoPaneHexNewLimits(maximumWorkUnits: 18)
        XCTAssertNoThrow(try TwoPaneHexNewPlanner.plan(makeValidRequest(limits: ok)))
    }

    // Limit-first vs cancel precedence: immediate cancellation wins (first
    // check runs before any guard), but a later cancellation loses to an
    // earlier limit guard.
    func testLimitsValidatedBeforeCancellationPrecedence() throws {
        let invalidSources = try TwoPaneHexNewLimits(maximumSources: 1)
        assertPlanningError(.cancelled) {
            try TwoPaneHexNewPlanner.plan(
                self.makeValidRequest(limits: invalidSources), cancellationCheck: { throw CancellationError() })
        }
        let later = CancellationProbe(cancelAtCall: 5)
        assertPlanningError(.invalidLimit(.sources)) {
            try TwoPaneHexNewPlanner.plan(
                self.makeValidRequest(limits: invalidSources), cancellationCheck: { try later.check() })
        }
    }

    private func makeValidRequest(
        byteSize: UInt64 = 4096,
        window: TwoPaneHexNewByteWindow = TwoPaneHexNewByteWindow(offset: 0, length: 16),
        bytesPerRow: Int = 16,
        capability: TwoPaneHexNewCapabilityRequirement = TwoPaneHexNewCapabilityRequirement(),
        limits: TwoPaneHexNewLimits = TwoPaneHexNewLimits.default
    ) -> TwoPaneHexNewRequest {
        TwoPaneHexNewRequest(
            left: .file(makeIdentity(name: "left.bin", byteSize: byteSize, digestByte: 0x11)),
            right: .file(makeIdentity(name: "right.bin", byteSize: byteSize, digestByte: 0x33)),
            window: window,
            bytesPerRow: bytesPerRow,
            capability: capability,
            limits: limits
        )
    }

    private func makeIdentity(name: String, byteSize: UInt64 = 4096, digestByte: UInt8) -> TwoPaneHexNewFileIdentity {
        let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/\(name)", isDirectory: false)
        return TwoPaneHexNewFileIdentity(
            canonicalURL: url,
            canonicalPath: url.path(percentEncoded: false),
            byteSize: byteSize,
            contentSHA256: [UInt8](repeating: digestByte, count: 32)
        )
    }

    private func assertPlanningError<T>(
        _ expected: TwoPaneHexNewPlanningError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as TwoPaneHexNewPlanningError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private enum CustomProbeError: Error, Equatable {
    case boom
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAtCall: Int
    private var calls = 0

    init(cancelAtCall: Int) {
        self.cancelAtCall = cancelAtCall
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func check() throws {
        lock.lock()
        calls += 1
        let shouldCancel = calls >= cancelAtCall
        lock.unlock()
        if shouldCancel {
            throw CancellationError()
        }
    }
}
