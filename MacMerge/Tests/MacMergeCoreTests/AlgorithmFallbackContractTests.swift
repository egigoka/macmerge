import CXDiff
import MacMergeCore
import XCTest

final class AlgorithmFallbackContractTests: XCTestCase {
    private struct AlgorithmCase {
        let algorithm: DiffAlgorithm
        let flags: UInt64
    }

    private struct Corpus {
        let name: String
        let left: String
        let right: String
    }

    private struct Hunk: Equatable {
        let leftStart: Int64
        let leftCount: Int64
        let rightStart: Int64
        let rightCount: Int64
        let isTrivial: Int32
    }

    private struct NativeOutcome {
        let status: Int32
        let hunks: [Hunk]
        let hasHunkStorage: Bool
        let leftToRightCount: Int
        let rightToLeftCount: Int
        let hasLeftToRightStorage: Bool
        let hasRightToLeftStorage: Bool
        let allocationAttempts: Int
        let outstandingAllocations: Int
    }

    private let algorithms = [
        AlgorithmCase(algorithm: .default, flags: 0),
        AlgorithmCase(algorithm: .minimal, flags: UInt64(MMX_DIFF_NEED_MINIMAL)),
        AlgorithmCase(algorithm: .patience, flags: UInt64(MMX_DIFF_PATIENCE)),
        AlgorithmCase(algorithm: .histogram, flags: UInt64(MMX_DIFF_HISTOGRAM)),
        AlgorithmCase(algorithm: .none, flags: UInt64(MMX_DIFF_NONE)),
    ]
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

    func testFallbackAndNonFallbackCorpusContractForEveryAlgorithmAndAPI() throws {
        let fallback = fallbackCorpus()
        let defaultFallbackRows = try LineDiff.compare(
            left: fallback.left,
            right: fallback.right,
            options: LineDiffOptions(algorithm: .default)
        )

        for corpus in corpora {
            for algorithmCase in algorithms {
                let context = testContext(corpus: corpus, algorithm: algorithmCase.algorithm)
                let noMove = nativeDiff(corpus: corpus, flags: algorithmCase.flags, detectMoves: false)
                let withMoves = nativeDiff(corpus: corpus, flags: algorithmCase.flags, detectMoves: true)

                XCTAssertEqual(noMove.status, 0, context)
                XCTAssertEqual(withMoves.status, 0, context)
                XCTAssertEqual(withMoves.hunks, noMove.hunks, context)
                XCTAssertFalse(noMove.hunks.isEmpty, context)
                XCTAssertEqual(noMove.hasHunkStorage, !noMove.hunks.isEmpty, context)
                XCTAssertEqual(withMoves.hasHunkStorage, !withMoves.hunks.isEmpty, context)
                XCTAssertEqual(
                    withMoves.hasLeftToRightStorage,
                    withMoves.leftToRightCount != 0,
                    context
                )
                XCTAssertEqual(
                    withMoves.hasRightToLeftStorage,
                    withMoves.rightToLeftCount != 0,
                    context
                )
                XCTAssertEqual(withMoves.leftToRightCount, withMoves.rightToLeftCount, context)
                XCTAssertEqual(noMove.outstandingAllocations, 0, context)
                XCTAssertEqual(withMoves.outstandingAllocations, 0, context)

                let options = LineDiffOptions(
                    algorithm: algorithmCase.algorithm,
                    detectMovedBlocks: true
                )
                let rows = try LineDiff.compare(left: corpus.left, right: corpus.right, options: options)
                let result = try LineDiff.compareResult(
                    left: corpus.left,
                    right: corpus.right,
                    options: options
                )
                XCTAssertEqual(result.rows, rows, context)
                XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0, context)

                if corpus.name == fallback.name,
                   algorithmCase.algorithm == .patience || algorithmCase.algorithm == .histogram {
                    XCTAssertEqual(rows, defaultFallbackRows, context)
                }
            }
        }
    }

    func testNoMoveFaultSweepMapsStatusesAndCleansEveryAlgorithmAndCorpus() {
        for corpus in corpora {
            for algorithmCase in algorithms {
                mmx_test_disable_allocation_failures()
                let successful = nativeDiff(
                    corpus: corpus,
                    flags: algorithmCase.flags,
                    detectMoves: false
                )
                let context = testContext(corpus: corpus, algorithm: algorithmCase.algorithm)
                let sweep = allocationSweep(count: successful.allocationAttempts, context: context)

                XCTAssertEqual(successful.status, 0, context)
                XCTAssertEqual(successful.outstandingAllocations, 0, context)

                for failedAllocation in sweep {
                    let expectedStatus: Int32 = failedAllocation == successful.allocationAttempts - 1
                        ? -3
                        : -2
                    assertNativeFailure(
                        corpus: corpus,
                        algorithmCase: algorithmCase,
                        detectMoves: false,
                        failedAllocation: failedAllocation,
                        expectedStatus: expectedStatus
                    )
                    assertSwiftFailure(
                        corpus: corpus,
                        algorithm: algorithmCase.algorithm,
                        detectMoves: false,
                        failedAllocation: failedAllocation,
                        expectedStatus: expectedStatus
                    )
                }
            }
        }
    }

    func testMoveFaultSweepMapsStatusesAndCleansEveryAlgorithmAndCorpus() {
        for corpus in corpora {
            for algorithmCase in algorithms {
                mmx_test_disable_allocation_failures()
                let noMove = nativeDiff(
                    corpus: corpus,
                    flags: algorithmCase.flags,
                    detectMoves: false
                )
                mmx_test_disable_allocation_failures()
                let successful = nativeDiff(
                    corpus: corpus,
                    flags: algorithmCase.flags,
                    detectMoves: true
                )
                let context = testContext(corpus: corpus, algorithm: algorithmCase.algorithm)
                let firstMovePhaseAllocation = noMove.allocationAttempts - 1
                let sweep = allocationSweep(count: successful.allocationAttempts, context: context)

                XCTAssertEqual(noMove.status, 0, context)
                XCTAssertEqual(successful.status, 0, context)
                XCTAssertGreaterThan(firstMovePhaseAllocation, 0, context)
                XCTAssertLessThan(firstMovePhaseAllocation, successful.allocationAttempts, context)
                XCTAssertEqual(successful.outstandingAllocations, 0, context)

                for failedAllocation in sweep {
                    let expectedStatus: Int32 = failedAllocation < firstMovePhaseAllocation ? -2 : -3
                    assertNativeFailure(
                        corpus: corpus,
                        algorithmCase: algorithmCase,
                        detectMoves: true,
                        failedAllocation: failedAllocation,
                        expectedStatus: expectedStatus,
                        expectedAllocationAttempts: failedAllocation
                            + (failedAllocation == firstMovePhaseAllocation ? 2 : 1)
                    )
                    assertSwiftFailure(
                        corpus: corpus,
                        algorithm: algorithmCase.algorithm,
                        detectMoves: true,
                        failedAllocation: failedAllocation,
                        expectedStatus: expectedStatus,
                        expectedAllocationAttempts: failedAllocation
                            + (failedAllocation == firstMovePhaseAllocation ? 2 : 1)
                    )
                }
            }
        }
    }

    func testFaultResetRestoresEveryAlgorithmAndAPI() {
        for corpus in corpora {
            for algorithmCase in algorithms {
                for detectMoves in [false, true] {
                    let context = testContext(corpus: corpus, algorithm: algorithmCase.algorithm)

                    mmx_test_fail_allocation_after(0)
                    let failed = nativeDiff(
                        corpus: corpus,
                        flags: algorithmCase.flags,
                        detectMoves: detectMoves
                    )
                    XCTAssertEqual(failed.status, -2, context)
                    XCTAssertEqual(failed.allocationAttempts, 1, context)
                    XCTAssertEqual(failed.outstandingAllocations, 0, context)

                    mmx_test_disable_allocation_failures()
                    XCTAssertEqual(mmx_test_allocation_attempt_count(), 0, context)
                    let recovered = nativeDiff(
                        corpus: corpus,
                        flags: algorithmCase.flags,
                        detectMoves: detectMoves
                    )
                    XCTAssertEqual(recovered.status, 0, context)
                    XCTAssertGreaterThan(recovered.allocationAttempts, 1, context)
                    XCTAssertEqual(recovered.outstandingAllocations, 0, context)

                    mmx_test_disable_allocation_failures()
                    let options = LineDiffOptions(
                        algorithm: algorithmCase.algorithm,
                        detectMovedBlocks: detectMoves
                    )
                    XCTAssertNoThrow(
                        detectMoves
                            ? try LineDiff.compareResult(
                                left: corpus.left,
                                right: corpus.right,
                                options: options
                            ).rows
                            : try LineDiff.compare(
                                left: corpus.left,
                                right: corpus.right,
                                options: options
                            ),
                        context
                    )
                    XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0, context)
                }
            }
        }
    }

    private var corpora: [Corpus] {
        [fallbackCorpus(), nonFallbackCorpus()]
    }

    private func fallbackCorpus() -> Corpus {
        // No unique shared line forces patience fallback; 65 repeats exceed histogram's cutoff.
        let repeated = Array(repeating: "repeat", count: 65)
        return Corpus(
            name: "fallback",
            left: (["left boundary"] + repeated + ["left tail"]).joined(separator: "\n"),
            right: (["right boundary"] + repeated + ["right tail"]).joined(separator: "\n")
        )
    }

    private func nonFallbackCorpus() -> Corpus {
        Corpus(
            name: "nonfallback",
            left: "head\nduplicate\nunique moved seed\nduplicate\nstable one\nstable two\nstable three\ntail",
            right: "head\nstable one\nstable two\nstable three\nduplicate\nunique moved seed\nduplicate\ntail"
        )
    }

    private func allocationSweep(count: Int, context: String) -> Range<Int> {
        XCTAssertGreaterThan(count, 0, context)
        XCTAssertLessThanOrEqual(
            count,
            maximumAllocationSweepCount,
            "\(context), allocation sweep exceeds test bound"
        )
        return 0..<min(count, maximumAllocationSweepCount)
    }

    private func assertNativeFailure(
        corpus: Corpus,
        algorithmCase: AlgorithmCase,
        detectMoves: Bool,
        failedAllocation: Int,
        expectedStatus: Int32,
        expectedAllocationAttempts: Int? = nil
    ) {
        mmx_test_fail_allocation_after(failedAllocation)
        let outcome = nativeDiff(
            corpus: corpus,
            flags: algorithmCase.flags,
            detectMoves: detectMoves
        )
        let context = "\(testContext(corpus: corpus, algorithm: algorithmCase.algorithm)), "
            + "moves: \(detectMoves), allocation: \(failedAllocation)"

        XCTAssertEqual(outcome.status, expectedStatus, context)
        XCTAssertTrue(outcome.hunks.isEmpty, context)
        XCTAssertFalse(outcome.hasHunkStorage, context)
        XCTAssertEqual(outcome.leftToRightCount, 0, context)
        XCTAssertEqual(outcome.rightToLeftCount, 0, context)
        XCTAssertFalse(outcome.hasLeftToRightStorage, context)
        XCTAssertFalse(outcome.hasRightToLeftStorage, context)
        XCTAssertEqual(
            outcome.allocationAttempts,
            expectedAllocationAttempts ?? failedAllocation + 1,
            context
        )
        XCTAssertEqual(outcome.outstandingAllocations, 0, context)
    }

    private func assertSwiftFailure(
        corpus: Corpus,
        algorithm: DiffAlgorithm,
        detectMoves: Bool,
        failedAllocation: Int,
        expectedStatus: Int32,
        expectedAllocationAttempts: Int? = nil
    ) {
        mmx_test_fail_allocation_after(failedAllocation)
        let options = LineDiffOptions(algorithm: algorithm, detectMovedBlocks: detectMoves)
        let context = "\(testContext(corpus: corpus, algorithm: algorithm)), "
            + "moves: \(detectMoves), allocation: \(failedAllocation)"

        XCTAssertThrowsError(try {
            if detectMoves {
                _ = try LineDiff.compareResult(
                    left: corpus.left,
                    right: corpus.right,
                    options: options
                )
            } else {
                _ = try LineDiff.compare(
                    left: corpus.left,
                    right: corpus.right,
                    options: options
                )
            }
        }()) { error in
            XCTAssertEqual(error as? LineDiffError, .nativeEngineFailure(expectedStatus), context)
        }
        XCTAssertEqual(
            Int(mmx_test_allocation_attempt_count()),
            expectedAllocationAttempts ?? failedAllocation + 1,
            context
        )
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0, context)
    }

    private func nativeDiff(corpus: Corpus, flags: UInt64, detectMoves: Bool) -> NativeOutcome {
        let leftBytes = Array(corpus.left.utf8)
        let rightBytes = Array(corpus.right.utf8)
        var result = mmx_diff_result(hunks: nil, count: 0)
        var moved = mmx_moved_result(
            left_to_right: nil,
            left_to_right_count: 0,
            right_to_left: nil,
            right_to_left_count: 0
        )
        let status = leftBytes.withUnsafeBytes { leftBuffer in
            rightBytes.withUnsafeBytes { rightBuffer in
                if detectMoves {
                    mmx_diff_with_moves(
                        leftBuffer.baseAddress,
                        leftBuffer.count,
                        rightBuffer.baseAddress,
                        rightBuffer.count,
                        flags,
                        &result,
                        &moved
                    )
                } else {
                    mmx_diff(
                        leftBuffer.baseAddress,
                        leftBuffer.count,
                        rightBuffer.baseAddress,
                        rightBuffer.count,
                        flags,
                        &result
                    )
                }
            }
        }
        let hunks = UnsafeBufferPointer(start: result.hunks, count: result.count).map {
            Hunk(
                leftStart: $0.left_start,
                leftCount: $0.left_count,
                rightStart: $0.right_start,
                rightCount: $0.right_count,
                isTrivial: $0.is_trivial
            )
        }
        let hasHunkStorage = result.hunks != nil
        let leftToRightCount = Int(moved.left_to_right_count)
        let rightToLeftCount = Int(moved.right_to_left_count)
        let hasLeftToRightStorage = moved.left_to_right != nil
        let hasRightToLeftStorage = moved.right_to_left != nil
        let allocationAttempts = Int(mmx_test_allocation_attempt_count())

        mmx_diff_result_free(&result)
        mmx_moved_result_free(&moved)

        return NativeOutcome(
            status: status,
            hunks: hunks,
            hasHunkStorage: hasHunkStorage,
            leftToRightCount: leftToRightCount,
            rightToLeftCount: rightToLeftCount,
            hasLeftToRightStorage: hasLeftToRightStorage,
            hasRightToLeftStorage: hasRightToLeftStorage,
            allocationAttempts: allocationAttempts,
            outstandingAllocations: Int(mmx_test_outstanding_allocation_count())
        )
    }

    private func testContext(corpus: Corpus, algorithm: DiffAlgorithm) -> String {
        "Corpus: \(corpus.name), algorithm: \(algorithm)"
    }
}
