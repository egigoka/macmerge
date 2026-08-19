import CXDiff
import XCTest

final class InputBoundaryContractTests: XCTestCase {
    override func setUp() {
        super.setUp()
        mmx_test_disable_allocation_failures()
    }

    override func tearDown() {
        mmx_test_disable_allocation_failures()
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
        super.tearDown()
    }

    func testExactByteLimitReachesNativeEngineAndLimitPlusOneFailsPreflight() {
        let maximumBytes = Int(MMX_MAX_INPUT_SIZE)
        let input = Data(repeating: 0x61, count: maximumBytes + 1)

        let exact = runWithFirstAllocationFailure(input, reportedSize: maximumBytes)
        XCTAssertEqual(exact.status, -2)
        XCTAssertGreaterThan(exact.allocationAttempts, 0)

        let oversized = runWithFirstAllocationFailure(input)
        XCTAssertEqual(oversized.status, -1)
        XCTAssertEqual(oversized.allocationAttempts, 0)
    }

    func testExactLineLimitWithTerminalEOLReachesNativeEngineAndLimitPlusOneFailsPreflight() {
        let maximumLines = Int(MMX_MAX_LINE_COUNT)

        let exact = runWithFirstAllocationFailure(Data(repeating: 0x0A, count: maximumLines))
        XCTAssertEqual(exact.status, -2)
        XCTAssertGreaterThan(exact.allocationAttempts, 0)

        let oversized = runWithFirstAllocationFailure(
            Data(repeating: 0x0A, count: maximumLines + 1)
        )
        XCTAssertEqual(oversized.status, -1)
        XCTAssertEqual(oversized.allocationAttempts, 0)
    }

    func testExactCRLineLimitReachesNativeEngineAndLimitPlusOneFailsPreflight() {
        assertTerminalLineBoundary(lineEnding: [0x0D])
    }

    func testExactCRLFLineLimitReachesNativeEngineAndLimitPlusOneFailsPreflight() {
        assertTerminalLineBoundary(lineEnding: [0x0D, 0x0A])
    }

    func testExactLineLimitWithoutTerminalEOLReachesNativeEngineAndLimitPlusOneFailsPreflight() {
        let maximumLines = Int(MMX_MAX_LINE_COUNT)
        var exactInput = Data(repeating: 0x0A, count: maximumLines - 1)
        exactInput.append(0x61)

        let exact = runWithFirstAllocationFailure(exactInput)
        XCTAssertEqual(exact.status, -2)
        XCTAssertGreaterThan(exact.allocationAttempts, 0)

        exactInput.append(contentsOf: [0x0A, 0x61])
        let oversized = runWithFirstAllocationFailure(exactInput)
        XCTAssertEqual(oversized.status, -1)
        XCTAssertEqual(oversized.allocationAttempts, 0)
    }

    func testInjectedAllocationFaultCanBeClearedAndResultReused() {
        let left = Data("left\n".utf8)
        let right = Data("right\n".utf8)
        var result = mmx_diff_result(hunks: nil, count: 0)
        defer {
            mmx_test_disable_allocation_failures()
            mmx_diff_result_free(&result)
        }

        mmx_test_fail_allocation_after(0)
        let failedStatus = diff(left: left, right: right, result: &result)
        XCTAssertEqual(failedStatus, -2)
        XCTAssertGreaterThan(mmx_test_allocation_attempt_count(), 0)
        XCTAssertNil(result.hunks)
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)

        mmx_test_disable_allocation_failures()
        let successfulStatus = diff(left: left, right: right, result: &result)
        XCTAssertEqual(successfulStatus, 0)
        XCTAssertNotNil(result.hunks)
        XCTAssertGreaterThan(result.count, 0)

        mmx_diff_result_free(&result)
        XCTAssertNil(result.hunks)
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
    }

    private func assertTerminalLineBoundary(
        lineEnding: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let maximumLines = Int(MMX_MAX_LINE_COUNT)
        var input = Data(count: lineEnding.count * (maximumLines + 1))
        input.withUnsafeMutableBytes { buffer in
            for index in buffer.indices {
                buffer[index] = lineEnding[index % lineEnding.count]
            }
        }

        let exact = runWithFirstAllocationFailure(
            input,
            reportedSize: lineEnding.count * maximumLines,
            file: file,
            line: line
        )
        XCTAssertEqual(exact.status, -2, file: file, line: line)
        XCTAssertGreaterThan(exact.allocationAttempts, 0, file: file, line: line)

        let oversized = runWithFirstAllocationFailure(input, file: file, line: line)
        XCTAssertEqual(oversized.status, -1, file: file, line: line)
        XCTAssertEqual(oversized.allocationAttempts, 0, file: file, line: line)
    }

    private func runWithFirstAllocationFailure(
        _ input: Data,
        reportedSize: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (status: Int32, allocationAttempts: Int) {
        var result = mmx_diff_result(hunks: nil, count: 0)
        defer {
            mmx_diff_result_free(&result)
            mmx_test_disable_allocation_failures()
        }

        mmx_test_fail_allocation_after(0)
        let status = input.withUnsafeBytes { buffer in
            mmx_diff(
                buffer.baseAddress,
                reportedSize ?? buffer.count,
                nil,
                0,
                0,
                &result
            )
        }
        let allocationAttempts = Int(mmx_test_allocation_attempt_count())

        XCTAssertNil(result.hunks, file: file, line: line)
        XCTAssertEqual(result.count, 0, file: file, line: line)
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0, file: file, line: line)
        return (status, allocationAttempts)
    }

    private func diff(
        left: Data,
        right: Data,
        result: UnsafeMutablePointer<mmx_diff_result>
    ) -> Int32 {
        left.withUnsafeBytes { leftBuffer in
            right.withUnsafeBytes { rightBuffer in
                mmx_diff(
                    leftBuffer.baseAddress,
                    leftBuffer.count,
                    rightBuffer.baseAddress,
                    rightBuffer.count,
                    0,
                    result
                )
            }
        }
    }
}
