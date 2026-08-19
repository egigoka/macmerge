import CXDiff
import XCTest

final class ExactInputBoundaryTests: XCTestCase {
    func testExactByteLimitPassesPreflightAndReachesNativeAllocatorWhileLimitPlusOneFailsPreflight() {
        let maximumBytes = Int(MMX_MAX_INPUT_SIZE)
        let input = [UInt8](repeating: 0x61, count: maximumBytes + 1)

        mmx_test_disable_allocation_failures()
        defer { mmx_test_disable_allocation_failures() }

        var exactLimitResult = mmx_diff_result(hunks: nil, count: 0)
        mmx_test_fail_allocation_after(0)
        let exactLimitStatus = input.withUnsafeBytes { buffer in
            mmx_diff(buffer.baseAddress, maximumBytes, nil, 0, 0, &exactLimitResult)
        }

        XCTAssertEqual(exactLimitStatus, -2, "Expected injected native allocation failure")
        XCTAssertGreaterThan(
            mmx_test_allocation_attempt_count(),
            0,
            "Exact-limit input did not pass preflight and reach the native allocator"
        )
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
        XCTAssertNil(exactLimitResult.hunks)
        XCTAssertEqual(exactLimitResult.count, 0)

        var limitPlusOneResult = mmx_diff_result(hunks: nil, count: 0)
        mmx_test_fail_allocation_after(0)
        let limitPlusOneStatus = input.withUnsafeBytes { buffer in
            mmx_diff(buffer.baseAddress, buffer.count, nil, 0, 0, &limitPlusOneResult)
        }

        XCTAssertEqual(limitPlusOneStatus, -1, "Expected preflight size rejection")
        XCTAssertEqual(
            mmx_test_allocation_attempt_count(),
            0,
            "Limit-plus-one input reached the native allocator"
        )
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
        XCTAssertNil(limitPlusOneResult.hunks)
        XCTAssertEqual(limitPlusOneResult.count, 0)
    }
}
