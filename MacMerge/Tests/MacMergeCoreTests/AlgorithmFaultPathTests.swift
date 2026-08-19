import CXDiff
import MacMergeCore
import XCTest

final class AlgorithmFaultPathTests: XCTestCase {
    private let algorithms: [DiffAlgorithm] = [.default, .minimal, .patience, .histogram, .none]
    private let maximumAllocationSweepCount = 128

    override func setUp() {
        super.setUp()
        mmx_test_disable_allocation_failures()
    }

    override func tearDown() {
        mmx_test_disable_allocation_failures()
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
        super.tearDown()
    }

    func testPatienceAndHistogramClassicFallbackMatchesDefault() throws {
        let input = fallbackInput()
        let expected = try successfulComparison(
            left: input.left,
            right: input.right,
            algorithm: .default
        ).rows

        for algorithm in [DiffAlgorithm.patience, .histogram] {
            let comparison = try successfulComparison(
                left: input.left,
                right: input.right,
                algorithm: algorithm
            )

            XCTAssertEqual(comparison.rows, expected, "Algorithm: \(algorithm)")
            XCTAssertGreaterThan(comparison.allocationCount, 0, "Algorithm: \(algorithm)")
            XCTAssertEqual(comparison.outstandingAllocationCount, 0, "Algorithm: \(algorithm)")
        }
    }

    func testEveryAlgorithmPropagatesEachAllocationFailure() throws {
        let input = fallbackInput()

        try assertEveryAllocationFailure(left: input.left, right: input.right)
    }

    func testEveryAlgorithmPropagatesEachNonFallbackAllocationFailure() throws {
        let input = nonFallbackInput()

        try assertEveryAllocationFailure(left: input.left, right: input.right)
    }

    func testEveryAlgorithmCompareResultWithMovedBlocksCleansUpEachAllocationFailure() throws {
        let input = movedBlockInput()

        for algorithm in algorithms {
            let withoutMoves = try successfulComparison(
                left: input.left,
                right: input.right,
                algorithm: algorithm
            )
            let successful = try successfulMovedComparison(
                left: input.left,
                right: input.right,
                algorithm: algorithm
            )
            let firstMovedPhaseAllocation = withoutMoves.allocationCount - 1

            XCTAssertEqual(successful.result.rows, withoutMoves.rows, "Algorithm: \(algorithm)")
            XCTAssertGreaterThan(successful.result.movedLines.leftToRightCount, 0, "Algorithm: \(algorithm)")
            XCTAssertGreaterThan(successful.result.movedLines.rightToLeftCount, 0, "Algorithm: \(algorithm)")
            XCTAssertGreaterThan(firstMovedPhaseAllocation, 0, "Algorithm: \(algorithm)")
            XCTAssertLessThan(firstMovedPhaseAllocation, successful.allocationCount, "Algorithm: \(algorithm)")
            XCTAssertEqual(successful.outstandingAllocationCount, 0, "Algorithm: \(algorithm)")

            for failedAllocation in allocationSweep(
                count: successful.allocationCount,
                algorithm: algorithm
            ) {
                let failure = comparisonFailure(
                    left: input.left,
                    right: input.right,
                    algorithm: algorithm,
                    detectMovedBlocks: true,
                    after: failedAllocation
                )
                let expectedCode: Int32 = failedAllocation < firstMovedPhaseAllocation ? -2 : -3

                XCTAssertEqual(
                    failure.error as? LineDiffError,
                    .nativeEngineFailure(expectedCode),
                    "Algorithm: \(algorithm), allocation: \(failedAllocation)"
                )
                XCTAssertEqual(
                    failure.outstandingAllocationCount,
                    0,
                    "Algorithm: \(algorithm), allocation: \(failedAllocation) leaked"
                )
            }
        }
    }

    private func assertEveryAllocationFailure(left: String, right: String) throws {
        for algorithm in algorithms {
            let successful = try successfulComparison(left: left, right: right, algorithm: algorithm)
            XCTAssertGreaterThan(successful.allocationCount, 0, "Algorithm: \(algorithm)")
            XCTAssertEqual(successful.outstandingAllocationCount, 0, "Algorithm: \(algorithm)")

            for failedAllocation in allocationSweep(
                count: successful.allocationCount,
                algorithm: algorithm
            ) {
                let failure = comparisonFailure(
                    left: left,
                    right: right,
                    algorithm: algorithm,
                    after: failedAllocation
                )
                let expectedCode: Int32 = failedAllocation == successful.allocationCount - 1 ? -3 : -2

                XCTAssertEqual(
                    failure.error as? LineDiffError,
                    .nativeEngineFailure(expectedCode),
                    "Algorithm: \(algorithm), allocation: \(failedAllocation)"
                )
                XCTAssertEqual(
                    failure.allocationAttemptCount,
                    failedAllocation + 1,
                    "Algorithm: \(algorithm), allocation: \(failedAllocation) unexpectedly retried or fell back"
                )
                XCTAssertEqual(
                    failure.outstandingAllocationCount,
                    0,
                    "Algorithm: \(algorithm), allocation: \(failedAllocation) leaked"
                )
            }
        }
    }

    private func allocationSweep(count: Int, algorithm: DiffAlgorithm) -> Range<Int> {
        XCTAssertLessThanOrEqual(
            count,
            maximumAllocationSweepCount,
            "Algorithm: \(algorithm), allocation sweep exceeds test bound"
        )
        return 0..<min(count, maximumAllocationSweepCount)
    }

    private func fallbackInput() -> (left: String, right: String) {
        // No unique shared line forces patience fallback; 65 occurrences exceed histogram's 64-line cutoff.
        let repeated = Array(repeating: "repeat", count: 65)
        return (
            (["left boundary"] + repeated + ["left tail"]).joined(separator: "\n"),
            (["right boundary"] + repeated + ["right tail"]).joined(separator: "\n")
        )
    }

    private func nonFallbackInput() -> (left: String, right: String) {
        (
            "root\nshared alpha\nleft change\nshared beta\nshared gamma\ntail",
            "root\nshared alpha\nright change\nshared beta\nshared gamma\ntail"
        )
    }

    private func movedBlockInput() -> (left: String, right: String) {
        (
            "head\nduplicate\nunique moved seed\nduplicate\nstable one\nstable two\nstable three\ntail",
            "head\nstable one\nstable two\nstable three\nduplicate\nunique moved seed\nduplicate\ntail"
        )
    }

    private func successfulComparison(
        left: String,
        right: String,
        algorithm: DiffAlgorithm
    ) throws -> (rows: [DiffRow], allocationCount: Int, outstandingAllocationCount: Int) {
        mmx_test_disable_allocation_failures()
        defer { mmx_test_disable_allocation_failures() }

        let rows = try LineDiff.compare(
            left: left,
            right: right,
            options: LineDiffOptions(algorithm: algorithm)
        )
        return (
            rows,
            Int(mmx_test_allocation_attempt_count()),
            Int(mmx_test_outstanding_allocation_count())
        )
    }

    private func successfulMovedComparison(
        left: String,
        right: String,
        algorithm: DiffAlgorithm
    ) throws -> (result: LineDiffResult, allocationCount: Int, outstandingAllocationCount: Int) {
        mmx_test_disable_allocation_failures()
        defer { mmx_test_disable_allocation_failures() }

        let result = try LineDiff.compareResult(
            left: left,
            right: right,
            options: LineDiffOptions(algorithm: algorithm, detectMovedBlocks: true)
        )
        return (
            result,
            Int(mmx_test_allocation_attempt_count()),
            Int(mmx_test_outstanding_allocation_count())
        )
    }

    private func comparisonFailure(
        left: String,
        right: String,
        algorithm: DiffAlgorithm,
        detectMovedBlocks: Bool = false,
        after successfulAllocations: Int
    ) -> (error: Error?, allocationAttemptCount: Int, outstandingAllocationCount: Int) {
        mmx_test_disable_allocation_failures()
        defer { mmx_test_disable_allocation_failures() }
        mmx_test_fail_allocation_after(successfulAllocations)

        do {
            if detectMovedBlocks {
                _ = try LineDiff.compareResult(
                    left: left,
                    right: right,
                    options: LineDiffOptions(algorithm: algorithm, detectMovedBlocks: true)
                )
            } else {
                _ = try LineDiff.compare(
                    left: left,
                    right: right,
                    options: LineDiffOptions(algorithm: algorithm)
                )
            }
            return (
                nil,
                Int(mmx_test_allocation_attempt_count()),
                Int(mmx_test_outstanding_allocation_count())
            )
        } catch {
            return (
                error,
                Int(mmx_test_allocation_attempt_count()),
                Int(mmx_test_outstanding_allocation_count())
            )
        }
    }
}
