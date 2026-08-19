import CXDiff
import MacMergeCore
import XCTest

final class XDiffRuntimeRouteTests: XCTestCase {
    func testLineDiffCompareExecutesLinkedMMXDiff() {
        mmx_test_disable_allocation_failures()
        mmx_test_fail_allocation_after(0)
        defer { mmx_test_disable_allocation_failures() }

        XCTAssertThrowsError(
            try LineDiff.compare(
                left: "root\nleft changed\ntail",
                right: "root\nright changed\ntail"
            )
        ) { error in
            guard case LineDiffError.nativeEngineFailure = error else {
                return XCTFail("Expected linked mmx_diff failure, got \(error)")
            }
        }
        XCTAssertGreaterThan(
            mmx_test_allocation_attempt_count(),
            0,
            "LineDiff.compare did not execute instrumented mmx_diff"
        )
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
    }
}
