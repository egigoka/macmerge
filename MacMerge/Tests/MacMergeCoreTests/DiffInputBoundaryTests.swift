import CXDiff
import MacMergeCore
import XCTest

final class DiffInputBoundaryTests: XCTestCase {
    func testExposedInputLimitsRemainPracticalAndStable() {
        XCTAssertEqual(Int(MMX_MAX_INPUT_SIZE), 64 * 1024 * 1024)
        XCTAssertEqual(Int(MMX_MAX_LINE_COUNT), 1024 * 1024)
    }

    func testCABIRejectsByteLimitPlusOneBeforeReadingSafeBuffer() {
        var byte: UInt8 = 0
        var result = mmx_diff_result(hunks: nil, count: 0)
        let oversizedCount = Int(MMX_MAX_INPUT_SIZE) + 1

        mmx_test_disable_allocation_failures()
        mmx_test_fail_allocation_after(0)
        defer { mmx_test_disable_allocation_failures() }

        let status = withUnsafePointer(to: &byte) { pointer in
            mmx_diff(pointer, oversizedCount, nil, 0, 0, &result)
        }

        XCTAssertEqual(status, -1)
        XCTAssertEqual(mmx_test_allocation_attempt_count(), 0)
        XCTAssertNil(result.hunks)
        XCTAssertEqual(result.count, 0)
    }

    func testCABILineLimitIsAcceptedButLimitPlusOneIsRejectedBeforeAllocation() {
        let maximumLines = Int(MMX_MAX_LINE_COUNT)
        let accepted = Data(repeating: 0x0A, count: maximumLines)
        let rejected = Data(repeating: 0x0A, count: maximumLines + 1)

        mmx_test_disable_allocation_failures()
        defer { mmx_test_disable_allocation_failures() }

        var acceptedResult = mmx_diff_result(hunks: nil, count: 0)
        mmx_test_fail_allocation_after(0)
        let acceptedStatus = accepted.withUnsafeBytes { buffer in
            mmx_diff(buffer.baseAddress, buffer.count, nil, 0, 0, &acceptedResult)
        }
        XCTAssertEqual(acceptedStatus, -2)
        XCTAssertGreaterThan(mmx_test_allocation_attempt_count(), 0)
        XCTAssertNil(acceptedResult.hunks)
        XCTAssertEqual(acceptedResult.count, 0)

        var rejectedResult = mmx_diff_result(hunks: nil, count: 0)
        mmx_test_fail_allocation_after(0)
        let rejectedStatus = rejected.withUnsafeBytes { buffer in
            mmx_diff(buffer.baseAddress, buffer.count, nil, 0, 0, &rejectedResult)
        }
        XCTAssertEqual(rejectedStatus, -1)
        XCTAssertEqual(mmx_test_allocation_attempt_count(), 0)
        XCTAssertNil(rejectedResult.hunks)
        XCTAssertEqual(rejectedResult.count, 0)
    }

    func testSwiftRejectsLineLimitPlusOneBeforeCallingCABI() {
        let text = String(repeating: "\n", count: Int(MMX_MAX_LINE_COUNT) + 1)

        mmx_test_disable_allocation_failures()
        mmx_test_fail_allocation_after(0)
        defer { mmx_test_disable_allocation_failures() }

        XCTAssertThrowsError(try LineDiff.compare(left: text, right: "")) { error in
            XCTAssertEqual(
                error as? LineDiffError,
                .tooManyLines(maximumLines: Int(MMX_MAX_LINE_COUNT))
            )
        }
        XCTAssertEqual(mmx_test_allocation_attempt_count(), 0)
    }
}
