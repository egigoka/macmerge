import Foundation
import MacMergeCore
import XCTest

final class ThreePaneHexNewPlanTests: XCTestCase {
    func testHappyPathPlansOrderedPanesWithReceipt() throws {
        // Planning never touches the filesystem: missing files still plan.
        let missingToken = UUID().uuidString
        let missingLeftURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/missing-\(missingToken)-left.bin", isDirectory: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingLeftURL.path(percentEncoded: false)))
        let missingRequest = ThreePaneHexNewRequest(
            left: .file(ThreePaneHexNewFileIdentity(
                canonicalURL: missingLeftURL,
                canonicalPath: missingLeftURL.path(percentEncoded: false),
                byteSize: 4096,
                contentSHA256: [UInt8](repeating: 0x11, count: 32))),
            middle: .file(makeIdentity(name: "missing-\(missingToken)-middle.bin", byteSize: 4096, digestByte: 0x22)),
            right: .file(makeIdentity(name: "missing-\(missingToken)-right.bin", byteSize: 4096, digestByte: 0x33)),
            window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(missingRequest))
        let request = makeValidRequest()
        let plan = try ThreePaneHexNewPlanner.plan(request)
        XCTAssertEqual(plan.panes.map(\.side), [.left, .middle, .right])
        XCTAssertEqual(plan.window, request.window)
        XCTAssertEqual(plan.bytesPerRow, request.bytesPerRow)
        XCTAssertEqual(plan.receipt.sourceCount, 3)
        XCTAssertEqual(plan.receipt.windowOffset, request.window.offset)
        XCTAssertEqual(plan.receipt.windowLength, request.window.length)
        XCTAssertEqual(plan.receipt.bytesPerRow, request.bytesPerRow)
        XCTAssertEqual(plan.receipt.value.count, 64)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertTrue(plan.executorContract.readOnly)
        XCTAssertEqual(plan.limits, request.limits)
        XCTAssertGreaterThan(plan.estimatedWorkUnits, 0)
        XCTAssertEqual(plan.receipt.workUnits, plan.estimatedWorkUnits)
        XCTAssertEqual(plan.findings.count, 3)
        XCTAssertNoThrow(try plan.requireReceipt(plan.receipt))
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(plan))
    }

    func testMaximumSourcesMustEqualThree() throws {
        XCTAssertEqual(ThreePaneHexNewLimits.hardMaximumSources, 3)
        for sources in [1, 2] {
            let limited = try ThreePaneHexNewLimits(maximumSources: sources)
            assertPlanningError(.invalidLimit(.sources)) {
                try ThreePaneHexNewPlanner.plan(self.makeValidRequest(limits: limited))
            }
        }
        assertPlanningError(.invalidLimit(.sources)) {
            try ThreePaneHexNewLimits(maximumSources: 0)
        }
        assertPlanningError(.invalidLimit(.sources)) {
            try ThreePaneHexNewLimits(maximumSources: 4)
        }
        let ok = try ThreePaneHexNewLimits(maximumSources: 3)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(makeValidRequest(limits: ok)))
    }

    func testDuplicateRevisionByDigestAloneRejected() {
        let shared = [UInt8](repeating: 0xAA, count: 32)
        let leftURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/digest-left.bin", isDirectory: false)
        let rightURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/digest-right.bin", isDirectory: false)
        let left = ThreePaneHexNewFileIdentity(canonicalURL: leftURL, canonicalPath: leftURL.path(percentEncoded: false), byteSize: 100, contentSHA256: shared)
        let right = ThreePaneHexNewFileIdentity(
            canonicalURL: rightURL, canonicalPath: rightURL.path(percentEncoded: false), byteSize: 200, contentSHA256: shared)
        let middle = makeIdentity(name: "digest-middle.bin", byteSize: 4096, digestByte: 0x22)
        let request = ThreePaneHexNewRequest(
            left: .file(left), middle: .file(middle), right: .file(right), window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
        assertPlanningError(.duplicateSourceRevision(first: .left, second: .right)) {
            try ThreePaneHexNewPlanner.plan(request)
        }
    }

    func testDuplicateRevisionByURLRejected() {
        let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/shared.bin", isDirectory: false)
        let path = url.path(percentEncoded: false)
        let left = ThreePaneHexNewFileIdentity(canonicalURL: url, canonicalPath: path, byteSize: 4096, contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let right = ThreePaneHexNewFileIdentity(canonicalURL: url, canonicalPath: path, byteSize: 4096, contentSHA256: [UInt8](repeating: 0x33, count: 32))
        let middle = makeIdentity(name: "url-middle.bin", byteSize: 4096, digestByte: 0x22)
        let request = ThreePaneHexNewRequest(
            left: .file(left), middle: .file(middle), right: .file(right), window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
        assertPlanningError(.duplicateSourceRevision(first: .left, second: .right)) {
            try ThreePaneHexNewPlanner.plan(request)
        }
    }

    func testDuplicateRevisionRejectsEveryPair() {
        let pairs: [(ThreePaneHexNewSide, ThreePaneHexNewSide)] = [(.left, .middle), (.middle, .right)]
        for (first, second) in pairs {
            var digests: [ThreePaneHexNewSide: UInt8] = [.left: 0x11, .middle: 0x22, .right: 0x33]
            digests[second] = digests[first]
            let request = ThreePaneHexNewRequest(
                left: .file(makeIdentity(name: "dup-left.bin", byteSize: 4096, digestByte: digests[.left]!)),
                middle: .file(makeIdentity(name: "dup-middle.bin", byteSize: 4096, digestByte: digests[.middle]!)),
                right: .file(makeIdentity(name: "dup-right.bin", byteSize: 4096, digestByte: digests[.right]!)),
                window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
            assertPlanningError(.duplicateSourceRevision(first: first, second: second)) {
                try ThreePaneHexNewPlanner.plan(request)
            }
        }
        let sharedURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/dup-shared.bin", isDirectory: false)
        let sharedPath = sharedURL.path(percentEncoded: false)
        let middleURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/dup-middle.bin", isDirectory: false)
        let leftShared = ThreePaneHexNewFileIdentity(
            canonicalURL: sharedURL, canonicalPath: sharedPath, byteSize: 4096, contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let middleOther = ThreePaneHexNewFileIdentity(
            canonicalURL: middleURL, canonicalPath: middleURL.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x22, count: 32))
        let rightShared = ThreePaneHexNewFileIdentity(
            canonicalURL: sharedURL, canonicalPath: sharedPath, byteSize: 4096, contentSHA256: [UInt8](repeating: 0x33, count: 32))
        assertPlanningError(.duplicateSourceRevision(first: .left, second: .right)) {
            try ThreePaneHexNewPlanner.plan(
                ThreePaneHexNewRequest(
                    left: .file(leftShared), middle: .file(middleOther), right: .file(rightShared),
                    window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
        }
    }

    func testCancellationErrorMappedToCancelled() {
        let request = makeValidRequest()
        assertPlanningError(.cancelled) {
            try ThreePaneHexNewPlanner.plan(request, cancellationCheck: { throw CancellationError() })
        }
    }

    func testUnknownErrorRethrownUnchanged() {
        let request = makeValidRequest()
        XCTAssertThrowsError(try ThreePaneHexNewPlanner.plan(request, cancellationCheck: { throw CustomProbeError.boom })) { error in
            XCTAssertEqual(error as? CustomProbeError, .boom)
        }
        XCTAssertThrowsError(try ThreePaneHexNewPlanner.plan(request, cancellationCheck: { throw ThreePaneHexNewPlanningError.emptyByteRange })) { error in
            XCTAssertEqual(error as? ThreePaneHexNewPlanningError, .emptyByteRange)
        }
    }

    func testInvalidLimitEveryKind() {
        assertPlanningError(.invalidLimit(.sources)) {
            try ThreePaneHexNewLimits(maximumSources: 0)
        }
        assertPlanningError(.invalidLimit(.pathUTF8Bytes)) {
            try ThreePaneHexNewLimits(maximumPathUTF8Bytes: 0)
        }
        assertPlanningError(.invalidLimit(.pathUTF8Bytes)) {
            try ThreePaneHexNewLimits(maximumPathUTF8Bytes: ThreePaneHexNewLimits.hardMaximumPathUTF8Bytes + 1)
        }
        assertPlanningError(.invalidLimit(.totalPathUTF8Bytes)) {
            try ThreePaneHexNewLimits(maximumTotalPathUTF8Bytes: 0)
        }
        assertPlanningError(.invalidLimit(.totalPathUTF8Bytes)) {
            try ThreePaneHexNewLimits(maximumPathUTF8Bytes: 40, maximumTotalPathUTF8Bytes: 39)
        }
        assertPlanningError(.invalidLimit(.totalPathUTF8Bytes)) {
            try ThreePaneHexNewLimits(maximumTotalPathUTF8Bytes: ThreePaneHexNewLimits.hardMaximumTotalPathUTF8Bytes + 1)
        }
        assertPlanningError(.invalidLimit(.byteSize)) {
            try ThreePaneHexNewLimits(maximumByteSize: 0)
        }
        assertPlanningError(.invalidLimit(.byteSize)) {
            try ThreePaneHexNewLimits(maximumByteSize: ThreePaneHexNewLimits.hardMaximumByteSize + 1)
        }
        assertPlanningError(.invalidLimit(.windowLength)) {
            try ThreePaneHexNewLimits(maximumWindowLength: 0)
        }
        assertPlanningError(.invalidLimit(.windowLength)) {
            try ThreePaneHexNewLimits(maximumWindowLength: ThreePaneHexNewLimits.hardMaximumWindowLength + 1)
        }
        assertPlanningError(.invalidLimit(.bytesPerRow)) {
            try ThreePaneHexNewLimits(maximumBytesPerRow: 0)
        }
        assertPlanningError(.invalidLimit(.bytesPerRow)) {
            try ThreePaneHexNewLimits(maximumBytesPerRow: ThreePaneHexNewLimits.hardMaximumBytesPerRow + 1)
        }
        assertPlanningError(.invalidLimit(.stringBytes)) {
            try ThreePaneHexNewLimits(maximumStringBytes: 0)
        }
        assertPlanningError(.invalidLimit(.stringBytes)) {
            try ThreePaneHexNewLimits(maximumStringBytes: ThreePaneHexNewLimits.hardMaximumStringBytes + 1)
        }
        assertPlanningError(.invalidLimit(.findings)) {
            try ThreePaneHexNewLimits(maximumFindings: 0)
        }
        assertPlanningError(.invalidLimit(.findings)) {
            try ThreePaneHexNewLimits(maximumFindings: ThreePaneHexNewLimits.hardMaximumFindings + 1)
        }
        assertPlanningError(.invalidLimit(.workUnits)) {
            try ThreePaneHexNewLimits(maximumWorkUnits: 0)
        }
        assertPlanningError(.invalidLimit(.workUnits)) {
            try ThreePaneHexNewLimits(maximumWorkUnits: ThreePaneHexNewLimits.hardMaximumWorkUnits + 1)
        }
        assertPlanningError(.invalidLimit(.cancellationCheckInterval)) {
            try ThreePaneHexNewLimits(cancellationCheckInterval: 0)
        }
        assertPlanningError(.invalidLimit(.cancellationCheckInterval)) {
            try ThreePaneHexNewLimits(cancellationCheckInterval: ThreePaneHexNewLimits.hardMaximumCancellationCheckInterval + 1)
        }
    }

    func testInvalidPaneCount() {
        let full = makeValidRequest()
        assertPlanningError(.invalidPaneCount(actual: 0)) {
            try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(panes: [], window: full.window))
        }
        assertPlanningError(.invalidPaneCount(actual: 2)) {
            try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(panes: Array(full.panes.prefix(2)), window: full.window))
        }
        assertPlanningError(.invalidPaneCount(actual: 4)) {
            try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(panes: full.panes + [full.panes[0]], window: full.window))
        }
    }

    func testDuplicatePane() {
        let request = makeValidRequest()
        let duplicated = ThreePaneHexNewRequest(panes: [request.panes[0], request.panes[0], request.panes[2]], window: request.window)
        assertPlanningError(.duplicatePane(.left)) {
            try ThreePaneHexNewPlanner.plan(duplicated)
        }
    }

    func testMissingPaneMetadata() {
        for side in ThreePaneHexNewSide.allCases {
            let error = ThreePaneHexNewPlanningError.missingPane(side)
            XCTAssertTrue(error.errorDescription?.contains(side.rawValue) ?? false)
            XCTAssertEqual(error.debugDescription, error.errorDescription)
        }
        XCTAssertEqual(ThreePaneHexNewPlanningError.missingPane(.right).errorDescription, "Three-pane hex new is missing the right pane.")
    }

    func testEmptyPanesAllowedForNew() throws {
        let right = makeIdentity(name: "empty-right.bin", byteSize: 4096, digestByte: 0x33)
        let range = ThreePaneHexNewByteWindow(offset: 0, length: 16)
        let middleForMixed = makeIdentity(name: "empty-middle.bin", byteSize: 4096, digestByte: 0x22)
        let mixed = try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(left: .empty, middle: .file(middleForMixed), right: .file(right), window: range))
        XCTAssertEqual(mixed.receipt.sourceCount, 2)
        XCTAssertTrue(mixed.panes[0].isEmpty)
        let bothEmpty = try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(left: .empty, middle: .empty, right: .empty, window: range))
        XCTAssertEqual(bothEmpty.receipt.sourceCount, 0)
    }

    func testInvalidCanonicalURL() {
        let bad = URL(string: "https://example.com/file.bin")!
        XCTAssertEqual(bad.scheme, "https")
        let identity = ThreePaneHexNewFileIdentity(
            canonicalURL: bad, canonicalPath: "/file.bin", byteSize: 4096, contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let right = makeIdentity(name: "url-right.bin", byteSize: 4096, digestByte: 0x33)
        let middle = makeIdentity(name: "url-middle.bin", byteSize: 4096, digestByte: 0x22)
        let request = ThreePaneHexNewRequest(
            left: .file(identity), middle: .file(middle), right: .file(right), window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
        assertPlanningError(.invalidCanonicalURL(.left)) {
            try ThreePaneHexNewPlanner.plan(request)
        }
    }

    func testCanonicalPathMismatch() {
        let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/left.bin", isDirectory: false)
        let identity = ThreePaneHexNewFileIdentity(
            canonicalURL: url, canonicalPath: "/tmp/mismatch.bin", byteSize: 4096, contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let right = makeIdentity(name: "mismatch-right.bin", byteSize: 4096, digestByte: 0x33)
        let middle = makeIdentity(name: "mismatch-middle.bin", byteSize: 4096, digestByte: 0x22)
        let request = ThreePaneHexNewRequest(
            left: .file(identity), middle: .file(middle), right: .file(right), window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
        assertPlanningError(.canonicalPathMismatch(.left)) {
            try ThreePaneHexNewPlanner.plan(request)
        }
    }

    func testPathTooLargeBoundary() throws {
        let left = makeIdentity(name: "aa.bin", byteSize: 4096, digestByte: 0x11)
        let middle = makeIdentity(name: "bb.bin", byteSize: 4096, digestByte: 0x22)
        let right = makeIdentity(name: "cc.bin", byteSize: 4096, digestByte: 0x33)
        let exactBytes = left.canonicalPath.utf8.count
        XCTAssertEqual(middle.canonicalPath.utf8.count, exactBytes)
        XCTAssertEqual(right.canonicalPath.utf8.count, exactBytes)
        let exact = try ThreePaneHexNewLimits(maximumPathUTF8Bytes: exactBytes)
        let range = ThreePaneHexNewByteWindow(offset: 0, length: 16)
        let exactRequest = ThreePaneHexNewRequest(left: .file(left), middle: .file(middle), right: .file(right), window: range, limits: exact)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(exactRequest))
        let short = try ThreePaneHexNewLimits(maximumPathUTF8Bytes: exactBytes - 1)
        let shortRequest = ThreePaneHexNewRequest(left: .file(left), middle: .file(middle), right: .file(right), window: range, limits: short)
        assertPlanningError(.pathTooLarge(side: .left, maximumBytes: exactBytes - 1)) {
            try ThreePaneHexNewPlanner.plan(shortRequest)
        }
    }

    func testPathGuardRejectsEachSide() throws {
        let left = makeIdentity(name: "aa.bin", byteSize: 4096, digestByte: 0x11)
        let middle = makeIdentity(name: "bb.bin", byteSize: 4096, digestByte: 0x22)
        let right = makeIdentity(name: "cc.bin", byteSize: 4096, digestByte: 0x33)
        let exactBytes = left.canonicalPath.utf8.count
        XCTAssertEqual(middle.canonicalPath.utf8.count, exactBytes)
        XCTAssertEqual(right.canonicalPath.utf8.count, exactBytes)
        let limit = try ThreePaneHexNewLimits(maximumPathUTF8Bytes: exactBytes)
        let range = ThreePaneHexNewByteWindow(offset: 0, length: 16)
        let longMiddle = makeIdentity(name: String(repeating: "m", count: 64) + ".bin", byteSize: 4096, digestByte: 0x22)
        assertPlanningError(.pathTooLarge(side: .middle, maximumBytes: exactBytes)) {
            try ThreePaneHexNewPlanner.plan(
                ThreePaneHexNewRequest(left: .file(left), middle: .file(longMiddle), right: .file(right), window: range, limits: limit))
        }
        let longRight = makeIdentity(name: String(repeating: "r", count: 64) + ".bin", byteSize: 4096, digestByte: 0x33)
        assertPlanningError(.pathTooLarge(side: .right, maximumBytes: exactBytes)) {
            try ThreePaneHexNewPlanner.plan(
                ThreePaneHexNewRequest(left: .file(left), middle: .file(middle), right: .file(longRight), window: range, limits: limit))
        }
    }

    func testTotalPathTooLarge() throws {
        let left = makeIdentity(name: "aa.bin", byteSize: 4096, digestByte: 0x11)
        let middle = makeIdentity(name: "bb.bin", byteSize: 4096, digestByte: 0x22)
        let right = makeIdentity(name: "cc.bin", byteSize: 4096, digestByte: 0x33)
        let exactBytes = left.canonicalPath.utf8.count
        let total = exactBytes + middle.canonicalPath.utf8.count + right.canonicalPath.utf8.count
        let limit = try ThreePaneHexNewLimits(maximumPathUTF8Bytes: exactBytes, maximumTotalPathUTF8Bytes: total - 1)
        let request = ThreePaneHexNewRequest(
            left: .file(left), middle: .file(middle), right: .file(right), window: ThreePaneHexNewByteWindow(offset: 0, length: 16), limits: limit)
        assertPlanningError(.totalPathTooLarge(maximumBytes: total - 1)) {
            try ThreePaneHexNewPlanner.plan(request)
        }
    }

    func testByteSizeTooLargeBoundary() throws {
        let exact = try ThreePaneHexNewLimits(maximumByteSize: 4096)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(makeValidRequest(byteSize: 4096, limits: exact)))
        let short = try ThreePaneHexNewLimits(maximumByteSize: 4095)
        assertPlanningError(.byteSizeTooLarge(side: .left, maximumBytes: 4095)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(byteSize: 4096, limits: short))
        }
    }

    func testInvalidDigestEverySize() throws {
        for count in [0, 31, 33] {
            let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/bad-digest.bin", isDirectory: false)
            let bad = ThreePaneHexNewFileIdentity(
                canonicalURL: url, canonicalPath: url.path(percentEncoded: false), byteSize: 4096, contentSHA256: [UInt8](repeating: 0x11, count: count))
            let middle = makeIdentity(name: "digest-ok-middle.bin", byteSize: 4096, digestByte: 0x22)
            let right = makeIdentity(name: "digest-ok-right.bin", byteSize: 4096, digestByte: 0x33)
            let request = ThreePaneHexNewRequest(
                left: .file(bad), middle: .file(middle), right: .file(right), window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
            assertPlanningError(.invalidDigest(.left)) {
                try ThreePaneHexNewPlanner.plan(request)
            }
        }
        // Forged 32-byte digests are accepted by shape: planning binds the
        // exact bytes without verifying hash content, so distinct forgeries
        // yield distinct receipts.
        let forgedURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/forged-digest.bin", isDirectory: false)
        let forged = ThreePaneHexNewFileIdentity(
            canonicalURL: forgedURL, canonicalPath: forgedURL.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0xFF, count: 32))
        let forgedRequest = ThreePaneHexNewRequest(
            left: .file(forged),
            middle: .file(makeIdentity(name: "forged-middle.bin", byteSize: 4096, digestByte: 0x22)),
            right: .file(makeIdentity(name: "forged-right.bin", byteSize: 4096, digestByte: 0x33)),
            window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
        let forgedPlan = try ThreePaneHexNewPlanner.plan(forgedRequest)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(forgedPlan))
        let baseline = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertNotEqual(forgedPlan.receipt, baseline.receipt)
        XCTAssertNotEqual(forgedPlan.receipt.value, baseline.receipt.value)
    }

    func testInvalidBytesPerRowBoundaries() throws {
        XCTAssertEqual(ThreePaneHexNewRequest.minimumBytesPerRow, 1)
        XCTAssertEqual(ThreePaneHexNewRequest.maximumBytesPerRow, 64)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 1)))
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 16)))
        let wide = try ThreePaneHexNewLimits(maximumBytesPerRow: 64)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 64, limits: wide)))
        assertPlanningError(.invalidBytesPerRow(actual: 0)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(bytesPerRow: 0))
        }
        assertPlanningError(.invalidBytesPerRow(actual: 65)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(bytesPerRow: 65))
        }
        let narrow = try ThreePaneHexNewLimits(maximumBytesPerRow: 8)
        assertPlanningError(.invalidBytesPerRow(actual: 16)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(bytesPerRow: 16, limits: narrow))
        }
    }

    func testEmptyByteRange() {
        assertPlanningError(.emptyByteRange) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(window: ThreePaneHexNewByteWindow(offset: 0, length: 0)))
        }
    }

    func testByteRangeTooLargeBoundary() throws {
        let exact = try ThreePaneHexNewLimits(maximumWindowLength: 16)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(makeValidRequest(window: ThreePaneHexNewByteWindow(offset: 0, length: 16), limits: exact)))
        assertPlanningError(.byteRangeTooLarge(maximumBytes: 16)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(window: ThreePaneHexNewByteWindow(offset: 0, length: 17), limits: exact))
        }
    }

    func testInvalidByteRangeOverflow() {
        assertPlanningError(.invalidByteRange) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(window: ThreePaneHexNewByteWindow(offset: UInt64.max, length: 1)))
        }
    }

    func testRangeOutOfBounds() {
        assertPlanningError(.rangeOutOfBounds(.left)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(byteSize: 100, window: ThreePaneHexNewByteWindow(offset: 90, length: 20)))
        }
        let bigLeft = makeIdentity(name: "oob-left.bin", byteSize: 4096, digestByte: 0x11)
        let bigMiddle = makeIdentity(name: "oob-middle.bin", byteSize: 4096, digestByte: 0x22)
        let smallRight = makeIdentity(name: "oob-right.bin", byteSize: 100, digestByte: 0x33)
        assertPlanningError(.rangeOutOfBounds(.right)) {
            try ThreePaneHexNewPlanner.plan(
                ThreePaneHexNewRequest(
                    left: .file(bigLeft), middle: .file(bigMiddle), right: .file(smallRight), window: ThreePaneHexNewByteWindow(offset: 90, length: 20)))
        }
        let smallMiddle = makeIdentity(name: "oob-middle.bin", byteSize: 100, digestByte: 0x22)
        assertPlanningError(.rangeOutOfBounds(.middle)) {
            try ThreePaneHexNewPlanner.plan(
                ThreePaneHexNewRequest(
                    left: .file(bigLeft), middle: .file(smallMiddle), right: .file(bigMiddle), window: ThreePaneHexNewByteWindow(offset: 90, length: 20)))
        }
    }

    func testRangeAtExactFileEndAccepted() throws {
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(makeValidRequest(byteSize: 100, window: ThreePaneHexNewByteWindow(offset: 84, length: 16))))
        assertPlanningError(.rangeOutOfBounds(.left)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(byteSize: 100, window: ThreePaneHexNewByteWindow(offset: 85, length: 16)))
        }
    }

    func testReceiptMismatch() throws {
        let plan = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        let wrong = ThreePaneHexNewReceipt(
            value: String(repeating: "0", count: 64), sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset,
            windowLength: plan.receipt.windowLength, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits)
        XCTAssertNotEqual(wrong, plan.receipt)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(wrong)
        }
        XCTAssertNoThrow(try plan.requireReceipt(plan.receipt))
    }

    func testStaleReceiptFieldsRejected() throws {
        let plan = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        let tamperedCount = ThreePaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount + 1, windowOffset: plan.receipt.windowOffset,
            windowLength: plan.receipt.windowLength, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedCount)
        }
        let tamperedLength = ThreePaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset,
            windowLength: plan.receipt.windowLength + 1, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedLength)
        }
        let tamperedRow = ThreePaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset, windowLength: plan.receipt.windowLength,
            bytesPerRow: plan.receipt.bytesPerRow + 1, workUnits: plan.receipt.workUnits)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedRow)
        }
        let tamperedOffset = ThreePaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset + 1,
            windowLength: plan.receipt.windowLength, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedOffset)
        }
        let tamperedWork = ThreePaneHexNewReceipt(
            value: plan.receipt.value, sourceCount: plan.receipt.sourceCount, windowOffset: plan.receipt.windowOffset,
            windowLength: plan.receipt.windowLength, bytesPerRow: plan.receipt.bytesPerRow, workUnits: plan.receipt.workUnits + 1)
        assertPlanningError(.receiptMismatch) {
            try plan.requireReceipt(tamperedWork)
        }
    }

    func testWorkLimitExceededBoundary() throws {
        let baseline = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertGreaterThan(baseline.estimatedWorkUnits, 1)
        let exact = try ThreePaneHexNewLimits(maximumWorkUnits: baseline.estimatedWorkUnits)
        let exactPlan = try ThreePaneHexNewPlanner.plan(makeValidRequest(limits: exact))
        XCTAssertEqual(exactPlan.estimatedWorkUnits, baseline.estimatedWorkUnits)
        let short = try ThreePaneHexNewLimits(maximumWorkUnits: baseline.estimatedWorkUnits - 1)
        assertPlanningError(.workLimitExceeded(maximumUnits: baseline.estimatedWorkUnits - 1)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(limits: short))
        }
    }

    func testTinyWorkBudgetThrowsSpecificWorkLimitExceeded() throws {
        let tiny = try ThreePaneHexNewLimits(maximumWorkUnits: 1)
        assertPlanningError(.workLimitExceeded(maximumUnits: 1)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(limits: tiny))
        }
        // Negative three-way capability fields are never clamped: each
        // reports unsupportedCapability even under the tightest work budget.
        let negativeCases: [(String, ThreeWayBinaryComparisonOptions)] = [
            ("inputBytes", ThreeWayBinaryComparisonOptions(
                maximumInputBytes: -1, maximumExactEditDistance: 0, maximumAlignmentWork: 0,
                maximumRegions: 0, maximumOutputBytes: 0)),
            ("exactEditDistance", ThreeWayBinaryComparisonOptions(
                maximumInputBytes: 0, maximumExactEditDistance: -1, maximumAlignmentWork: 0,
                maximumRegions: 0, maximumOutputBytes: 0)),
            ("alignmentWork", ThreeWayBinaryComparisonOptions(
                maximumInputBytes: 0, maximumExactEditDistance: 0, maximumAlignmentWork: -1,
                maximumRegions: 0, maximumOutputBytes: 0)),
            ("regions", ThreeWayBinaryComparisonOptions(
                maximumInputBytes: 0, maximumExactEditDistance: 0, maximumAlignmentWork: 0,
                maximumRegions: -1, maximumOutputBytes: 0)),
            ("outputBytes", ThreeWayBinaryComparisonOptions(
                maximumInputBytes: 0, maximumExactEditDistance: 0, maximumAlignmentWork: 0,
                maximumRegions: 0, maximumOutputBytes: -1))
        ]
        for (_, threeWay) in negativeCases {
            let capability = ThreePaneHexNewCapabilityRequirement(threeWay: threeWay)
            assertPlanningError(.unsupportedCapability) {
                try ThreePaneHexNewPlanner.plan(self.makeValidRequest(capability: capability))
            }
        }
        // Capability-before-metering precedence: a negative capability wins
        // over an exhausted work budget (maximumWorkUnits 1), because
        // validateCapability runs before the per-pane work charges.
        let badCapability = ThreePaneHexNewCapabilityRequirement(threeWay: ThreeWayBinaryComparisonOptions(
            maximumInputBytes: -1, maximumExactEditDistance: 0, maximumAlignmentWork: 0,
            maximumRegions: 0, maximumOutputBytes: 0))
        assertPlanningError(.unsupportedCapability) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(capability: badCapability, limits: tiny))
        }
    }

    func testLimitsValidatedBeforeMetering() throws {
        let tinyInvalidSources = try ThreePaneHexNewLimits(maximumSources: 1, maximumWorkUnits: 1)
        assertPlanningError(.invalidLimit(.sources)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(limits: tinyInvalidSources))
        }
    }

    func testCancellationAbortsPlanning() throws {
        let request = makeValidRequest()
        let immediate = CancellationProbe(cancelAtCall: 1)
        assertPlanningError(.cancelled) {
            try ThreePaneHexNewPlanner.plan(request, cancellationCheck: { try immediate.check() })
        }
        XCTAssertEqual(immediate.callCount, 1)
        let later = CancellationProbe(cancelAtCall: 5)
        assertPlanningError(.cancelled) {
            try ThreePaneHexNewPlanner.plan(request, cancellationCheck: { try later.check() })
        }
        let passing = CancellationProbe(cancelAtCall: Int.max)
        let plan = try ThreePaneHexNewPlanner.plan(request, cancellationCheck: { try passing.check() })
        XCTAssertGreaterThan(plan.estimatedWorkUnits, 0)
        XCTAssertGreaterThan(passing.callCount, 0)
    }

    func testReceiptDeterministicAcrossOrderAndRepeats() throws {
        let request = makeValidRequest()
        let first = try ThreePaneHexNewPlanner.plan(request)
        let second = try ThreePaneHexNewPlanner.plan(request)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
        let reversed = ThreePaneHexNewRequest(panes: Array(request.panes.reversed()), window: request.window, bytesPerRow: request.bytesPerRow)
        let ordered = try ThreePaneHexNewPlanner.plan(reversed)
        XCTAssertEqual(ordered.receipt, first.receipt)
        XCTAssertEqual(ordered.panes.map(\.side), [.left, .middle, .right])
        let differentRow = try ThreePaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 8))
        XCTAssertNotEqual(differentRow.receipt, first.receipt)
    }

    func testReceiptBindsRangeRowAndSourceCount() throws {
        let base = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        let diffOffset = try ThreePaneHexNewPlanner.plan(makeValidRequest(window: ThreePaneHexNewByteWindow(offset: 1, length: 16)))
        XCTAssertNotEqual(diffOffset.receipt, base.receipt)
        XCTAssertNotEqual(diffOffset.receipt.value, base.receipt.value)
        let diffLengthOnly = try ThreePaneHexNewPlanner.plan(makeValidRequest(window: ThreePaneHexNewByteWindow(offset: 0, length: 8)))
        XCTAssertNotEqual(diffLengthOnly.receipt, base.receipt)
        XCTAssertNotEqual(diffLengthOnly.receipt.value, base.receipt.value)
        XCTAssertEqual(diffLengthOnly.receipt.windowOffset, base.receipt.windowOffset)
        XCTAssertNotEqual(diffLengthOnly.receipt.windowLength, base.receipt.windowLength)
        let diffRow = try ThreePaneHexNewPlanner.plan(makeValidRequest(bytesPerRow: 8))
        XCTAssertNotEqual(diffRow.receipt, base.receipt)
        let rightDrift = try ThreePaneHexNewPlanner.plan(
            ThreePaneHexNewRequest(
                left: .file(makeIdentity(name: "left.bin", byteSize: 4096, digestByte: 0x11)),
                middle: .file(makeIdentity(name: "middle.bin", byteSize: 4096, digestByte: 0x22)),
                right: .file(makeIdentity(name: "right.bin", byteSize: 4096, digestByte: 0x44)),
                window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertNotEqual(rightDrift.receipt, base.receipt)
        XCTAssertNotEqual(rightDrift.receipt.value, base.receipt.value)
        let oneEmpty = try ThreePaneHexNewPlanner.plan(
            ThreePaneHexNewRequest(
                left: .file(makeIdentity(name: "rb-left.bin", byteSize: 4096, digestByte: 0x11)),
                middle: .file(makeIdentity(name: "rb-middle.bin", byteSize: 4096, digestByte: 0x22)),
                right: .empty,
                window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertEqual(oneEmpty.receipt.sourceCount, 2)
        XCTAssertNotEqual(oneEmpty.receipt, base.receipt)
    }

    func testRedactionHidesPathsAndDigests() throws {
        let identity = makeIdentity(name: "secret.bin", byteSize: 4096, digestByte: 0xAB)
        XCTAssertFalse(identity.description.contains(identity.canonicalPath))
        XCTAssertFalse(identity.description.contains(identity.canonicalURL.absoluteString))
        XCTAssertFalse(identity.debugDescription.contains(identity.canonicalPath))
        XCTAssertNil(identity.customMirror.children.first(where: { "\($0.value)".contains(identity.canonicalPath) }))
        let source = ThreePaneHexNewPaneSource.file(identity)
        XCTAssertFalse(source.description.contains(identity.canonicalPath))
        XCTAssertTrue(source.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
        let pane = ThreePaneHexNewPane(side: .left, source: source)
        XCTAssertTrue(pane.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
        let request = makeValidRequest()
        XCTAssertFalse(request.description.contains(identity.canonicalPath))
        XCTAssertTrue(request.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
        let plan = try ThreePaneHexNewPlanner.plan(request)
        XCTAssertFalse(plan.description.contains(request.panes[0].source.description))
        XCTAssertTrue(plan.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
        let error = ThreePaneHexNewPlanningError.cancelled
        XCTAssertTrue(error.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
    }

    func testCommandIDAndExecutorContract() throws {
        XCTAssertEqual(ThreePaneHexNewPlanner.commandID, "ID_FILE_NEW3_HEX")
        let plan = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertEqual(plan.executorContract.sourceRevision, .exactDigestPinnedThroughExecution)
        XCTAssertEqual(plan.executorContract.range, .windowedReadOnlyNoMutation)
        XCTAssertEqual(plan.executorContract.fileSystem, .planOnlyNoFileSystemAccess)
        XCTAssertEqual(plan.executorContract.cancellation, .cancellableDuringPlanningOnly)
        XCTAssertTrue(plan.executorContract.readOnly)
        XCTAssertTrue(plan.panes.allSatisfy(\.isReadOnly))
    }

    func testLimitsHardBoundariesAccepted() throws {
        let hard = try ThreePaneHexNewLimits(
            maximumSources: ThreePaneHexNewLimits.hardMaximumSources,
            maximumPathUTF8Bytes: ThreePaneHexNewLimits.hardMaximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: ThreePaneHexNewLimits.hardMaximumTotalPathUTF8Bytes,
            maximumByteSize: ThreePaneHexNewLimits.hardMaximumByteSize,
            maximumWindowLength: ThreePaneHexNewLimits.hardMaximumWindowLength,
            maximumBytesPerRow: ThreePaneHexNewLimits.hardMaximumBytesPerRow,
            maximumStringBytes: ThreePaneHexNewLimits.hardMaximumStringBytes,
            maximumFindings: ThreePaneHexNewLimits.hardMaximumFindings,
            maximumWorkUnits: ThreePaneHexNewLimits.hardMaximumWorkUnits,
            cancellationCheckInterval: ThreePaneHexNewLimits.hardMaximumCancellationCheckInterval
        )
        XCTAssertNoThrow(try hard.validate())
        XCTAssertNoThrow(try ThreePaneHexNewLimits.default.validate())
        XCTAssertEqual(ThreePaneHexNewLimits.default.maximumSources, 3)
    }

    func testZeroCancellationIntervalThrowsInvalidLimitNotTrap() {
        assertPlanningError(.invalidLimit(.cancellationCheckInterval)) {
            try ThreePaneHexNewLimits(cancellationCheckInterval: 0)
        }
        assertPlanningError(.invalidLimit(.cancellationCheckInterval)) {
            try ThreePaneHexNewLimits(cancellationCheckInterval: ThreePaneHexNewLimits.hardMaximumCancellationCheckInterval + 1)
        }
    }

    func testNotReadOnlyRejected() throws {
        let left = makeIdentity(name: "ro-left.bin", byteSize: 4096, digestByte: 0x11)
        let middle = makeIdentity(name: "ro-middle.bin", byteSize: 4096, digestByte: 0x22)
        let right = makeIdentity(name: "ro-right.bin", byteSize: 4096, digestByte: 0x33)
        let range = ThreePaneHexNewByteWindow(offset: 0, length: 16)
        let leftWritable = ThreePaneHexNewRequest(
            panes: [
                ThreePaneHexNewPane(side: .left, source: .file(left), isReadOnly: false),
                ThreePaneHexNewPane(side: .middle, source: .file(middle), isReadOnly: true),
                ThreePaneHexNewPane(side: .right, source: .file(right), isReadOnly: true)
            ],
            window: range
        )
        assertPlanningError(.notReadOnly(.left)) {
            try ThreePaneHexNewPlanner.plan(leftWritable)
        }
        let middleWritable = ThreePaneHexNewRequest(
            panes: [
                ThreePaneHexNewPane(side: .left, source: .file(left), isReadOnly: true),
                ThreePaneHexNewPane(side: .middle, source: .file(middle), isReadOnly: false),
                ThreePaneHexNewPane(side: .right, source: .file(right), isReadOnly: true)
            ],
            window: range
        )
        assertPlanningError(.notReadOnly(.middle)) {
            try ThreePaneHexNewPlanner.plan(middleWritable)
        }
        let rightWritable = ThreePaneHexNewRequest(
            panes: [
                ThreePaneHexNewPane(side: .left, source: .file(left), isReadOnly: true),
                ThreePaneHexNewPane(side: .middle, source: .file(middle), isReadOnly: true),
                ThreePaneHexNewPane(side: .right, source: .file(right), isReadOnly: false)
            ],
            window: range
        )
        assertPlanningError(.notReadOnly(.right)) {
            try ThreePaneHexNewPlanner.plan(rightWritable)
        }
    }

    func testStringBudgetExceeded() throws {
        let tight = try ThreePaneHexNewLimits(maximumStringBytes: 1)
        assertPlanningError(.stringBudgetExceeded(maximumBytes: 1)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(limits: tight))
        }
        // Exact-accept boundary: the minimal passing string budget accepts,
        // one byte less rejects with the same maximum.
        let minimalPassing = try self.minimalPassingStringBytes()
        let exact = try ThreePaneHexNewLimits(maximumStringBytes: minimalPassing)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.plan(makeValidRequest(limits: exact)))
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(try ThreePaneHexNewPlanner.plan(makeValidRequest(limits: exact))))
        if minimalPassing > 1 {
            let oneShort = try ThreePaneHexNewLimits(maximumStringBytes: minimalPassing - 1)
            assertPlanningError(.stringBudgetExceeded(maximumBytes: minimalPassing - 1)) {
                try ThreePaneHexNewPlanner.plan(self.makeValidRequest(limits: oneShort))
            }
        }
    }

    func testTooManyFindings() throws {
        let tight = try ThreePaneHexNewLimits(maximumFindings: 1)
        assertPlanningError(.tooManyFindings(maximum: 1)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(limits: tight))
        }
        // Exact-accept boundary: three findings (one per pane) accept on ==,
        // two reject.
        let exact = try ThreePaneHexNewLimits(maximumFindings: 3)
        let exactPlan = try ThreePaneHexNewPlanner.plan(makeValidRequest(limits: exact))
        XCTAssertEqual(exactPlan.findings.count, 3)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(exactPlan))
        let short = try ThreePaneHexNewLimits(maximumFindings: 2)
        assertPlanningError(.tooManyFindings(maximum: 2)) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(limits: short))
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
        let capability = ThreePaneHexNewCapabilityRequirement(threeWay: badThreeWay)
        assertPlanningError(.unsupportedCapability) {
            try ThreePaneHexNewPlanner.plan(self.makeValidRequest(capability: capability))
        }
    }

    func testFindingsCoverFullAndWindowed() throws {
        let full = try ThreePaneHexNewPlanner.plan(makeValidRequest(byteSize: 16, window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertEqual(full.findings, [.fullCoverage, .fullCoverage, .fullCoverage])
        let partial = try ThreePaneHexNewPlanner.plan(makeValidRequest(byteSize: 4096, window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertEqual(partial.findings, [.windowedView, .windowedView, .windowedView])
        XCTAssertNotEqual(full.receipt, partial.receipt)
    }

    // Dual-tier maximumSources: Limits accepts 1...hardMaximumSources so
    // restricted configurations validate, but planning always requires
    // exactly three panes (unbound slots model as .empty, never a
    // shorter array).
    func testDualTierMaximumSourcesDocumentsRestrictedConfigs() throws {
        XCTAssertEqual(ThreePaneHexNewLimits.hardMaximumSources, 3)
        for sources in [1, 2] {
            let restricted = try ThreePaneHexNewLimits(maximumSources: sources)
            XCTAssertNoThrow(try restricted.validate())
            assertPlanningError(.invalidLimit(.sources)) {
                try ThreePaneHexNewPlanner.plan(self.makeValidRequest(limits: restricted))
            }
        }
        let exact = try ThreePaneHexNewLimits(maximumSources: 3)
        let plan = try ThreePaneHexNewPlanner.plan(makeValidRequest(limits: exact))
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(plan))
    }

    // Zero-byte exclusion: a file identity must bind >= 1 byte. Model an
    // unbound slot as .empty, never as a zero-byte file, so sourceCount,
    // window-bounds checks, and receipt binding stay unambiguous.
    func testZeroByteFileIdentityExcludedUseEmptyPaneInstead() {
        for side in ThreePaneHexNewSide.allCases {
            let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/zero-\(side.rawValue).bin", isDirectory: false)
            let zero = ThreePaneHexNewFileIdentity(
                canonicalURL: url, canonicalPath: url.path(percentEncoded: false), byteSize: 0,
                contentSHA256: [UInt8](repeating: 0xAA, count: 32))
            let filler = { (name: String, byte: UInt8) -> ThreePaneHexNewFileIdentity in
                let u = URL(fileURLWithPath: "/tmp/macmerge-hex-new/\(name)", isDirectory: false)
                return ThreePaneHexNewFileIdentity(
                    canonicalURL: u, canonicalPath: u.path(percentEncoded: false), byteSize: 4096,
                    contentSHA256: [UInt8](repeating: byte, count: 32))
            }
            let request: ThreePaneHexNewRequest
            switch side {
            case .left:
                request = ThreePaneHexNewRequest(
                    left: .file(zero), middle: .file(filler("zb-middle.bin", 0x22)), right: .file(filler("zb-right.bin", 0x33)),
                    window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
            case .middle:
                request = ThreePaneHexNewRequest(
                    left: .file(filler("zb-left.bin", 0x11)), middle: .file(zero), right: .file(filler("zb-right.bin", 0x33)),
                    window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
            case .right:
                request = ThreePaneHexNewRequest(
                    left: .file(filler("zb-left.bin", 0x11)), middle: .file(filler("zb-middle.bin", 0x22)), right: .file(zero),
                    window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
            }
            assertPlanningError(.byteSizeTooLarge(side: side, maximumBytes: ThreePaneHexNewLimits.default.maximumByteSize)) {
                try ThreePaneHexNewPlanner.plan(request)
            }
        }
    }

    // sourceCount == 0 with a non-empty window is intentional: a fresh
    // window with nothing bound yet (findings all .windowedView), ready
    // for later binding without changing window shape.
    func testSourceCountZeroWithWindowIsIntentionalFreshWindow() throws {
        let window = ThreePaneHexNewByteWindow(offset: 0, length: 16)
        let plan = try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(left: .empty, middle: .empty, right: .empty, window: window))
        XCTAssertEqual(plan.receipt.sourceCount, 0)
        XCTAssertEqual(plan.window, window)
        XCTAssertEqual(plan.findings, [.windowedView, .windowedView, .windowedView])
        XCTAssertTrue(plan.panes.allSatisfy(\.isEmpty))
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(plan))
        XCTAssertNoThrow(try plan.requireReceipt(plan.receipt))
    }

    // Capability carry-through: the plan binds the exact core
    // configuration the host must honor. Nothing redeclared here; the
    // receipt binds the carried values so a swapped configuration cannot
    // reuse the same receipt.
    func testCapabilityCarriedThroughAndBoundInReceipt() throws {
        let customThreeWay = ThreeWayBinaryComparisonOptions(
            maximumInputBytes: 1024,
            maximumExactEditDistance: 7,
            maximumAlignmentWork: 2048,
            maximumRegions: 9,
            maximumOutputBytes: 4096
        )
        let capability = ThreePaneHexNewCapabilityRequirement(threeWay: customThreeWay)
        let request = makeValidRequest(capability: capability)
        let plan = try ThreePaneHexNewPlanner.plan(request)
        XCTAssertEqual(plan.capability, capability)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(plan))
        let baseline = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertNotEqual(plan.receipt, baseline.receipt)
        XCTAssertNotEqual(plan.receipt.value, baseline.receipt.value)
    }

    // Directory-URL acceptance: planning never touches the filesystem, so
    // a trailing-slash directory path still satisfies the absolute
    // standardized file-scheme shape. Directory-vs-file enforcement
    // belongs to the executor, not the plan.
    func testDirectoryURLAcceptedPlanningOnlyExecutorEnforcesFileVsDirectory() throws {
        func dirIdentity(name: String, digestByte: UInt8) -> ThreePaneHexNewFileIdentity {
            let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/\(name)", isDirectory: true)
            return ThreePaneHexNewFileIdentity(
                canonicalURL: url, canonicalPath: url.path(percentEncoded: false), byteSize: 4096,
                contentSHA256: [UInt8](repeating: digestByte, count: 32))
        }
        let request = ThreePaneHexNewRequest(
            left: .file(dirIdentity(name: "left-dir", digestByte: 0x11)),
            middle: .file(dirIdentity(name: "middle-dir", digestByte: 0x22)),
            right: .file(dirIdentity(name: "right-dir", digestByte: 0x33)),
            window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
        let plan = try ThreePaneHexNewPlanner.plan(request)
        XCTAssertEqual(plan.receipt.sourceCount, 3)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(plan))
        // Symlink vs target: planning never resolves the filesystem, so two
        // distinct canonical paths with distinct digests both plan even when
        // one names a symlink-like alias of the other. Same digest still
        // collides as a duplicate revision, not via filesystem resolution.
        let target = makeIdentity(name: "sym-target.bin", byteSize: 4096, digestByte: 0x11)
        let linkLike = makeIdentity(name: "sym-link.bin", byteSize: 4096, digestByte: 0x44)
        XCTAssertNotEqual(target.canonicalPath, linkLike.canonicalPath)
        let symlinkRequest = ThreePaneHexNewRequest(
            left: .file(target),
            middle: .file(makeIdentity(name: "sym-middle.bin", byteSize: 4096, digestByte: 0x22)),
            right: .file(linkLike),
            window: ThreePaneHexNewByteWindow(offset: 0, length: 16))
        let symlinkPlan = try ThreePaneHexNewPlanner.plan(symlinkRequest)
        XCTAssertEqual(symlinkPlan.receipt.sourceCount, 3)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(symlinkPlan))
        let aliasedDigest = ThreePaneHexNewFileIdentity(
            canonicalURL: linkLike.canonicalURL, canonicalPath: linkLike.canonicalPath, byteSize: 4096,
            contentSHA256: target.contentSHA256)
        assertPlanningError(.duplicateSourceRevision(first: .left, second: .right)) {
            try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(
                left: .file(target),
                middle: .file(makeIdentity(name: "sym-middle2.bin", byteSize: 4096, digestByte: 0x22)),
                right: .file(aliasedDigest),
                window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
        }
    }

    // Host-normalized alias: empty host and localhost name the same file,
    // so file:///p and file://localhost/p must never slip through as two
    // distinct sources. The localhost form is not canonical (it never
    // equals its standardized file URL), so identity validation rejects
    // it before duplicate detection; same-path aliases that do validate
    // collide on canonicalPath plus the host-normalized URL comparison.
    func testHostNormalizedFileLocalhostAliasRejectedAsNonCanonical() throws {
        let leftURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/alias.bin", isDirectory: false)
        var components = URLComponents(url: leftURL, resolvingAgainstBaseURL: false)
        XCTAssertNotNil(components)
        components?.host = "localhost"
        let rightURL = try XCTUnwrap(components?.url)
        XCTAssertEqual(rightURL.path(percentEncoded: false), leftURL.path(percentEncoded: false))
        let left = ThreePaneHexNewFileIdentity(
            canonicalURL: leftURL, canonicalPath: leftURL.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let right = ThreePaneHexNewFileIdentity(
            canonicalURL: rightURL, canonicalPath: rightURL.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x33, count: 32))
        let middle = makeIdentity(name: "alias-middle.bin", byteSize: 4096, digestByte: 0x22)
        assertPlanningError(.invalidCanonicalURL(.right)) {
            try ThreePaneHexNewPlanner.plan(
                ThreePaneHexNewRequest(
                    left: .file(left), middle: .file(middle), right: .file(right),
                    window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
        }
        // Canonical-shape matrix: query, fragment, baseURL, NUL,
        // dot-segment, user, and port forms are all non-canonical.
        func assertLeftCanonicalRejected(_ url: URL, _ label: String) {
            let identity = ThreePaneHexNewFileIdentity(
                canonicalURL: url, canonicalPath: url.path(percentEncoded: false), byteSize: 4096,
                contentSHA256: [UInt8](repeating: 0x11, count: 32))
            assertPlanningError(.invalidCanonicalURL(.left), file: #filePath, line: #line) {
                try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(
                    left: .file(identity),
                    middle: .file(makeIdentity(name: "canon-middle-\(label).bin", byteSize: 4096, digestByte: 0x22)),
                    right: .file(makeIdentity(name: "canon-right-\(label).bin", byteSize: 4096, digestByte: 0x33)),
                    window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
            }
        }
        let baseFile = URL(fileURLWithPath: "/tmp/macmerge-hex-new/canon.bin", isDirectory: false)
        var queryComponents = try XCTUnwrap(URLComponents(url: baseFile, resolvingAgainstBaseURL: false))
        queryComponents.query = "q=1"
        assertLeftCanonicalRejected(try XCTUnwrap(queryComponents.url), "query")
        var fragmentComponents = try XCTUnwrap(URLComponents(url: baseFile, resolvingAgainstBaseURL: false))
        fragmentComponents.fragment = "frag"
        assertLeftCanonicalRejected(try XCTUnwrap(fragmentComponents.url), "fragment")
        let baseDir = URL(fileURLWithPath: "/tmp/", isDirectory: true)
        assertLeftCanonicalRejected(try XCTUnwrap(URL(string: "left.bin", relativeTo: baseDir)), "baseURL")
        assertLeftCanonicalRejected(try XCTUnwrap(URL(string: "file:///tmp/macmerge-hex-new/bad%00.bin")), "NUL")
        assertLeftCanonicalRejected(
            try XCTUnwrap(URL(string: "file:///tmp/macmerge-hex-new/../macmerge-hex-new/dot.bin")), "dot-segment")
        var userComponents = try XCTUnwrap(URLComponents(url: baseFile, resolvingAgainstBaseURL: false))
        userComponents.user = "alice"
        assertLeftCanonicalRejected(try XCTUnwrap(userComponents.url), "user")
        var portComponents = try XCTUnwrap(URLComponents(url: baseFile, resolvingAgainstBaseURL: false))
        portComponents.host = "localhost"
        portComponents.port = 8080
        assertLeftCanonicalRejected(try XCTUnwrap(portComponents.url), "port")
    }

    // Pane-count-before-consume precedence: an invalid pane count reports
    // invalidPaneCount even when the work budget is already exhausted,
    // because the count guard runs before the per-pane work charges.
    func testPaneCountCheckedBeforeMeteringPrecedence() throws {
        let baseline = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertGreaterThan(baseline.estimatedWorkUnits, 1)
        let tight = try ThreePaneHexNewLimits(maximumWorkUnits: baseline.estimatedWorkUnits - 1)
        let full = makeValidRequest()
        assertPlanningError(.invalidPaneCount(actual: 0)) {
            try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(panes: [], window: full.window, limits: tight))
        }
        assertPlanningError(.invalidPaneCount(actual: 4)) {
            try ThreePaneHexNewPlanner.plan(
                ThreePaneHexNewRequest(panes: full.panes + [full.panes[0]], window: full.window, limits: tight))
        }
    }

    // Identity-before-consume precedence: an invalid identity reports its
    // identity error even when the work budget could not cover a full
    // plan, because identity validation runs before the per-pane work
    // charge below it.
    func testIdentityCheckedBeforePerPaneMeteringPrecedence() throws {
        let baseline = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        XCTAssertGreaterThan(baseline.estimatedWorkUnits, 1)
        let tight = try ThreePaneHexNewLimits(maximumWorkUnits: baseline.estimatedWorkUnits - 1)
        let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/bad-digest-precedence.bin", isDirectory: false)
        let bad = ThreePaneHexNewFileIdentity(
            canonicalURL: url, canonicalPath: url.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x11, count: 31))
        let request = ThreePaneHexNewRequest(
            left: .file(bad),
            middle: .file(makeIdentity(name: "prec-middle.bin", byteSize: 4096, digestByte: 0x22)),
            right: .file(makeIdentity(name: "prec-right.bin", byteSize: 4096, digestByte: 0x33)),
            window: ThreePaneHexNewByteWindow(offset: 0, length: 16),
            limits: tight)
        assertPlanningError(.invalidDigest(.left)) {
            try ThreePaneHexNewPlanner.plan(request)
        }
    }

    // validate() is limits-bound: plans sitting exactly on the window,
    // byteSize, and work-unit boundaries revalidate cleanly.
    func testValidateAcceptsLimitsBoundWindowByteSizeWorkUnits() throws {
        let windowExact = try ThreePaneHexNewLimits(maximumWindowLength: 16)
        let windowPlan = try ThreePaneHexNewPlanner.plan(
            makeValidRequest(window: ThreePaneHexNewByteWindow(offset: 0, length: 16), limits: windowExact))
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(windowPlan))

        let byteExact = try ThreePaneHexNewLimits(maximumByteSize: 4096)
        let bytePlan = try ThreePaneHexNewPlanner.plan(makeValidRequest(byteSize: 4096, limits: byteExact))
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(bytePlan))

        let baseline = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        let workExact = try ThreePaneHexNewLimits(maximumWorkUnits: baseline.estimatedWorkUnits)
        let workPlan = try ThreePaneHexNewPlanner.plan(makeValidRequest(limits: workExact))
        XCTAssertEqual(workPlan.estimatedWorkUnits, baseline.estimatedWorkUnits)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(workPlan))
    }

    // Limits-bound acceptance: validate() accepts plans sitting exactly on
    // path budgets, zero capability, and mixed empty/file shapes. Full
    // mutated-plan validate() coverage needs internal init (Plan init is
    // fileprivate, no production edits in this lane), so trust-boundary
    // mutations are proven via requireReceipt/planning below.
    func testValidateAcceptsLimitsBoundInputs() throws {
        let left = makeIdentity(name: "tv-aa.bin", byteSize: 4096, digestByte: 0x11)
        let middle = makeIdentity(name: "tv-bb.bin", byteSize: 4096, digestByte: 0x22)
        let right = makeIdentity(name: "tv-cc.bin", byteSize: 4096, digestByte: 0x33)
        let exactBytes = left.canonicalPath.utf8.count
        let budgeted = try ThreePaneHexNewLimits(maximumPathUTF8Bytes: exactBytes)
        let budgetedPlan = try ThreePaneHexNewPlanner.plan(
            ThreePaneHexNewRequest(
                left: .file(left), middle: .file(middle), right: .file(right),
                window: ThreePaneHexNewByteWindow(offset: 0, length: 16), limits: budgeted))
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(budgetedPlan))

        let zeroCapability = ThreePaneHexNewCapabilityRequirement(
            threeWay: ThreeWayBinaryComparisonOptions(
                maximumInputBytes: 0, maximumExactEditDistance: 0, maximumAlignmentWork: 0,
                maximumRegions: 0, maximumOutputBytes: 0))
        let zeroPlan = try ThreePaneHexNewPlanner.plan(makeValidRequest(capability: zeroCapability))
        XCTAssertEqual(zeroPlan.capability, zeroCapability)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(zeroPlan))

        let mixed = try ThreePaneHexNewPlanner.plan(
            ThreePaneHexNewRequest(
                left: .file(makeIdentity(name: "tv-mixed-left.bin", byteSize: 4096, digestByte: 0x11)),
                middle: .empty,
                right: .file(makeIdentity(name: "tv-mixed-right.bin", byteSize: 4096, digestByte: 0x33)),
                window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
        XCTAssertEqual(mixed.receipt.sourceCount, 2)
        XCTAssertNoThrow(try ThreePaneHexNewPlanner.validate(mixed))
    }

    // Trust-boundary mutations: a mutated window, byteSize, work, duplicate,
    // or capability cannot reuse another plan's receipt. Cross-plan
    // requireReceipt proves receiptMismatch for each dimension; duplicate
    // and unsupported inputs are rejected at plan time before a receipt
    // exists (validate would also report receiptMismatch if smuggled).
    func testTrustBoundaryMutationsRejectWithReceiptMismatch() throws {
        let base = try ThreePaneHexNewPlanner.plan(makeValidRequest())
        // Window mutation.
        let windowMutated = try ThreePaneHexNewPlanner.plan(
            makeValidRequest(window: ThreePaneHexNewByteWindow(offset: 0, length: 8)))
        XCTAssertNotEqual(windowMutated.receipt, base.receipt)
        assertPlanningError(.receiptMismatch) {
            try base.requireReceipt(windowMutated.receipt)
        }
        // ByteSize mutation binds into the receipt value.
        let byteMutated = try ThreePaneHexNewPlanner.plan(makeValidRequest(byteSize: 2048))
        XCTAssertNotEqual(byteMutated.receipt, base.receipt)
        XCTAssertNotEqual(byteMutated.receipt.value, base.receipt.value)
        assertPlanningError(.receiptMismatch) {
            try base.requireReceipt(byteMutated.receipt)
        }
        // Work mutation: tampered workUnits never match.
        let workTampered = ThreePaneHexNewReceipt(
            value: base.receipt.value, sourceCount: base.receipt.sourceCount,
            windowOffset: base.receipt.windowOffset, windowLength: base.receipt.windowLength,
            bytesPerRow: base.receipt.bytesPerRow, workUnits: base.receipt.workUnits + 1)
        assertPlanningError(.receiptMismatch) {
            try base.requireReceipt(workTampered)
        }
        // Duplicate mutation: same digest or same path cannot plan.
        let dupDigestURL = URL(fileURLWithPath: "/tmp/macmerge-hex-new/tb-dup.bin", isDirectory: false)
        let dupDigestLeft = ThreePaneHexNewFileIdentity(
            canonicalURL: dupDigestURL, canonicalPath: dupDigestURL.path(percentEncoded: false), byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x11, count: 32))
        let dupDigestRight = ThreePaneHexNewFileIdentity(
            canonicalURL: URL(fileURLWithPath: "/tmp/macmerge-hex-new/tb-dup-right.bin", isDirectory: false),
            canonicalPath: "/tmp/macmerge-hex-new/tb-dup-right.bin", byteSize: 4096,
            contentSHA256: [UInt8](repeating: 0x11, count: 32))
        assertPlanningError(.duplicateSourceRevision(first: .left, second: .right)) {
            try ThreePaneHexNewPlanner.plan(ThreePaneHexNewRequest(
                left: .file(dupDigestLeft),
                middle: .file(makeIdentity(name: "tb-dup-middle.bin", byteSize: 4096, digestByte: 0x22)),
                right: .file(dupDigestRight),
                window: ThreePaneHexNewByteWindow(offset: 0, length: 16)))
        }
        // Capability mutation binds into the receipt value.
        let capMutated = try ThreePaneHexNewPlanner.plan(makeValidRequest(capability: ThreePaneHexNewCapabilityRequirement(
            threeWay: ThreeWayBinaryComparisonOptions(
                maximumInputBytes: 1024, maximumExactEditDistance: 7, maximumAlignmentWork: 2048,
                maximumRegions: 9, maximumOutputBytes: 4096))))
        XCTAssertNotEqual(capMutated.receipt, base.receipt)
        assertPlanningError(.receiptMismatch) {
            try base.requireReceipt(capMutated.receipt)
        }
        let badCapability = ThreePaneHexNewCapabilityRequirement(threeWay: ThreeWayBinaryComparisonOptions(
            maximumInputBytes: -1, maximumExactEditDistance: 0, maximumAlignmentWork: 0,
            maximumRegions: 0, maximumOutputBytes: 0))
        assertPlanningError(.unsupportedCapability) {
            try ThreePaneHexNewPlanner.plan(makeValidRequest(capability: badCapability))
        }
    }

    private func makeValidRequest(
        byteSize: UInt64 = 4096,
        window: ThreePaneHexNewByteWindow = ThreePaneHexNewByteWindow(offset: 0, length: 16),
        bytesPerRow: Int = 16,
        capability: ThreePaneHexNewCapabilityRequirement = ThreePaneHexNewCapabilityRequirement(),
        limits: ThreePaneHexNewLimits = ThreePaneHexNewLimits.default
    ) -> ThreePaneHexNewRequest {
        ThreePaneHexNewRequest(
            left: .file(makeIdentity(name: "left.bin", byteSize: byteSize, digestByte: 0x11)),
            middle: .file(makeIdentity(name: "middle.bin", byteSize: byteSize, digestByte: 0x22)),
            right: .file(makeIdentity(name: "right.bin", byteSize: byteSize, digestByte: 0x33)),
            window: window,
            bytesPerRow: bytesPerRow,
            capability: capability,
            limits: limits
        )
    }

    private func makeIdentity(name: String, byteSize: UInt64 = 4096, digestByte: UInt8) -> ThreePaneHexNewFileIdentity {
        let url = URL(fileURLWithPath: "/tmp/macmerge-hex-new/\(name)", isDirectory: false)
        return ThreePaneHexNewFileIdentity(
            canonicalURL: url,
            canonicalPath: url.path(percentEncoded: false),
            byteSize: byteSize,
            contentSHA256: [UInt8](repeating: digestByte, count: 32)
        )
    }

    private func minimalPassingStringBytes() throws -> Int {
        var low = 1
        var high = ThreePaneHexNewLimits.default.maximumStringBytes
        // Ensure high passes; default must pass for a valid request.
        _ = try ThreePaneHexNewPlanner.plan(makeValidRequest(limits: try ThreePaneHexNewLimits(maximumStringBytes: high)))
        while low < high {
            let mid = (low + high) / 2
            do {
                _ = try ThreePaneHexNewPlanner.plan(makeValidRequest(limits: try ThreePaneHexNewLimits(maximumStringBytes: mid)))
                high = mid
            } catch let error as ThreePaneHexNewPlanningError {
                if error == .stringBudgetExceeded(maximumBytes: mid) {
                    low = mid + 1
                } else {
                    throw error
                }
            }
        }
        return low
    }

    private func assertPlanningError<T>(
        _ expected: ThreePaneHexNewPlanningError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ThreePaneHexNewPlanningError {
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
