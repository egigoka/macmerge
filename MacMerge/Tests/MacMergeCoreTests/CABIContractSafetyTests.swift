import CXDiff
import XCTest

final class CABIContractSafetyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        mmx_test_disable_allocation_failures()
    }

    override func tearDown() {
        mmx_test_disable_allocation_failures()
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
        super.tearDown()
    }

    func testMalformedLengthsAndFlagsFailBeforeAllocation() {
        let byte: [UInt8] = [0x61]
        let empty: [UInt8] = []

        assertPreflightRejection(
            left: empty,
            leftCount: 1,
            right: empty,
            rightCount: 0,
            forceNilLeft: true,
            context: "nil left with nonzero count"
        )
        assertPreflightRejection(
            left: empty,
            leftCount: 0,
            right: empty,
            rightCount: 1,
            forceNilRight: true,
            context: "nil right with nonzero count"
        )
        assertPreflightRejection(
            left: byte,
            leftCount: -1,
            right: empty,
            rightCount: 0,
            context: "negative Swift count crosses C ABI as oversized size_t"
        )
        assertPreflightRejection(
            left: byte,
            leftCount: Int(MMX_MAX_INPUT_SIZE) + 1,
            right: empty,
            rightCount: 0,
            context: "left byte limit plus one"
        )
        assertPreflightRejection(
            left: empty,
            leftCount: 0,
            right: byte,
            rightCount: Int.max,
            context: "oversized right count"
        )

        for flags in [
            UInt64(1) << 63,
            UInt64.max,
            UInt64(MMX_DIFF_PATIENCE) | UInt64(MMX_DIFF_HISTOGRAM),
            UInt64(MMX_DIFF_PATIENCE) | UInt64(MMX_DIFF_NONE),
            UInt64(MMX_DIFF_HISTOGRAM) | UInt64(MMX_DIFF_NONE)
        ] {
            assertPreflightRejection(
                left: byte,
                leftCount: byte.count,
                right: byte,
                rightCount: byte.count,
                flags: flags,
                detectMoves: true,
                context: "flags 0x\(String(flags, radix: 16))"
            )
        }
    }

    func testOutputPointerCountStateMustBeZeroInitialized() {
        let input = Array("input\n".utf8)
        var hunk = mmx_diff_hunk(
            left_start: 0,
            left_count: 1,
            right_start: 0,
            right_count: 1,
            is_trivial: 0
        )
        var leftMovedLine = mmx_moved_line(left_line: 11, right_line: 12)
        var rightMovedLine = mmx_moved_line(left_line: 21, right_line: 22)

        mmx_test_fail_allocation_after(0)
        defer { mmx_test_disable_allocation_failures() }
        input.withUnsafeBytes { inputBuffer in
            var countOnlyResult = mmx_diff_result(hunks: nil, count: 1)
            XCTAssertEqual(
                mmx_diff(
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    0,
                    &countOnlyResult
                ),
                -1
            )
            XCTAssertNil(countOnlyResult.hunks)
            XCTAssertEqual(countOnlyResult.count, 1)

            withUnsafeMutablePointer(to: &hunk) { hunkPointer in
                var pointerOnlyResult = mmx_diff_result(hunks: hunkPointer, count: 0)
                XCTAssertEqual(
                    mmx_diff(
                        inputBuffer.baseAddress,
                        inputBuffer.count,
                        inputBuffer.baseAddress,
                        inputBuffer.count,
                        0,
                        &pointerOnlyResult
                    ),
                    -1
                )
                XCTAssertEqual(pointerOnlyResult.hunks, hunkPointer)
                XCTAssertEqual(pointerOnlyResult.count, 0)
            }

            withUnsafeMutablePointer(to: &leftMovedLine) { leftMovedPointer in
                withUnsafeMutablePointer(to: &rightMovedLine) { rightMovedPointer in
                    var pointerOnlyMoved = mmx_moved_result(
                        left_to_right: leftMovedPointer,
                        left_to_right_count: 0,
                        right_to_left: nil,
                        right_to_left_count: 0
                    )
                    assertMalformedMovedOutputRejection(
                        input: inputBuffer,
                        moved: &pointerOnlyMoved,
                        expectedLeftToRight: leftMovedPointer,
                        expectedLeftToRightCount: 0,
                        expectedRightToLeft: nil,
                        expectedRightToLeftCount: 0,
                        context: "left pointer with zero count"
                    )

                    var countOnlyMoved = mmx_moved_result(
                        left_to_right: nil,
                        left_to_right_count: 1,
                        right_to_left: nil,
                        right_to_left_count: 0
                    )
                    assertMalformedMovedOutputRejection(
                        input: inputBuffer,
                        moved: &countOnlyMoved,
                        expectedLeftToRight: nil,
                        expectedLeftToRightCount: 1,
                        expectedRightToLeft: nil,
                        expectedRightToLeftCount: 0,
                        context: "nil left pointer with nonzero count"
                    )

                    var pointerOnlyRightMoved = mmx_moved_result(
                        left_to_right: nil,
                        left_to_right_count: 0,
                        right_to_left: rightMovedPointer,
                        right_to_left_count: 0
                    )
                    assertMalformedMovedOutputRejection(
                        input: inputBuffer,
                        moved: &pointerOnlyRightMoved,
                        expectedLeftToRight: nil,
                        expectedLeftToRightCount: 0,
                        expectedRightToLeft: rightMovedPointer,
                        expectedRightToLeftCount: 0,
                        context: "right pointer with zero count"
                    )

                    var countOnlyRightMoved = mmx_moved_result(
                        left_to_right: nil,
                        left_to_right_count: 0,
                        right_to_left: nil,
                        right_to_left_count: 1
                    )
                    assertMalformedMovedOutputRejection(
                        input: inputBuffer,
                        moved: &countOnlyRightMoved,
                        expectedLeftToRight: nil,
                        expectedLeftToRightCount: 0,
                        expectedRightToLeft: nil,
                        expectedRightToLeftCount: 1,
                        context: "nil right pointer with nonzero count"
                    )
                }
            }
            XCTAssertEqual(leftMovedLine.left_line, 11)
            XCTAssertEqual(leftMovedLine.right_line, 12)
            XCTAssertEqual(rightMovedLine.left_line, 21)
            XCTAssertEqual(rightMovedLine.right_line, 22)

            var cleanResult = mmx_diff_result(hunks: nil, count: 0)
            XCTAssertEqual(
                mmx_diff(
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    0,
                    nil
                ),
                -1
            )
            XCTAssertEqual(
                mmx_diff_with_moves(
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    0,
                    &cleanResult,
                    nil
                ),
                -1
            )
        }

        XCTAssertEqual(mmx_test_allocation_attempt_count(), 0)
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
    }

    func testHunksHaveCoherentStorageMonotonicRangesAndInputBounds() {
        let left = Array("root\nleft-a\nshared-a\nleft-b\nshared-b\ntail\n".utf8)
        let right = Array("root\nright-a\nshared-a\nright-b\nshared-b\ntail\n".utf8)
        let leftLines = lines(in: left)
        let rightLines = lines(in: right)

        let outcome = runDiff(left: left, right: right, detectMoves: false)

        XCTAssertEqual(outcome.status, 0)
        XCTAssertGreaterThanOrEqual(outcome.hunks.count, 2)
        XCTAssertEqual(outcome.hunkCount, outcome.hunks.count)
        XCTAssertEqual(outcome.hasHunkStorage, !outcome.hunks.isEmpty)
        XCTAssertEqual(outcome.leftToRightCount, 0)
        XCTAssertEqual(outcome.rightToLeftCount, 0)
        assertValidHunks(
            outcome.hunks,
            leftLines: leftLines,
            rightLines: rightLines
        )
    }

    func testMovedMapsHaveCoherentStorageEqualCountsAndUniqueLines() {
        let left = Array("head\nmove-a\nmove-b\nstable\ntail\n".utf8)
        let right = Array("head\nstable\nmove-a\nmove-b\ntail\n".utf8)
        let leftLines = lines(in: left)
        let rightLines = lines(in: right)

        let outcome = runDiff(left: left, right: right, detectMoves: true)

        XCTAssertEqual(outcome.status, 0)
        XCTAssertGreaterThan(outcome.leftToRight.count, 0)
        assertValidHunks(
            outcome.hunks,
            leftLines: leftLines,
            rightLines: rightLines
        )
        assertValidMovedMaps(
            outcome,
            leftLines: leftLines,
            rightLines: rightLines
        )
    }

    func testEveryAllocationFaultIsDeterministicAndRecoverable() {
        let left = Array("head\nmove-a\nmove-b\nstable-a\nstable-b\ntail-left\n".utf8)
        let right = Array("head\nstable-a\nstable-b\nmove-a\nmove-b\ntail-right\n".utf8)

        defer { mmx_test_disable_allocation_failures() }
        mmx_test_disable_allocation_failures()
        let baseline = runDiff(left: left, right: right, detectMoves: true)
        XCTAssertEqual(baseline.status, 0)
        XCTAssertGreaterThan(baseline.allocationAttempts, 0)
        XCTAssertGreaterThan(baseline.leftToRight.count, 0)

        for failedAllocation in 0..<baseline.allocationAttempts {
            mmx_test_fail_allocation_after(failedAllocation)
            let firstFailure = runDiff(left: left, right: right, detectMoves: true)
            mmx_test_fail_allocation_after(failedAllocation)
            let repeatedFailure = runDiff(left: left, right: right, detectMoves: true)

            XCTAssertNotEqual(firstFailure.status, 0, "allocation \(failedAllocation)")
            XCTAssertEqual(
                repeatedFailure.status,
                firstFailure.status,
                "allocation \(failedAllocation) returned nondeterministic status"
            )
            XCTAssertEqual(
                repeatedFailure.allocationAttempts,
                firstFailure.allocationAttempts,
                "allocation \(failedAllocation) took a nondeterministic path"
            )
            assertEmptyOutputs(firstFailure, context: "allocation \(failedAllocation), first run")
            assertEmptyOutputs(repeatedFailure, context: "allocation \(failedAllocation), repeated run")

            mmx_test_disable_allocation_failures()
            let recovered = runDiff(left: left, right: right, detectMoves: true)
            XCTAssertEqual(recovered.status, 0, "allocation \(failedAllocation) recovery")
            XCTAssertEqual(recovered.hunks, baseline.hunks, "allocation \(failedAllocation) recovery")
            XCTAssertEqual(
                recovered.leftToRight,
                baseline.leftToRight,
                "allocation \(failedAllocation) recovery"
            )
            XCTAssertEqual(
                recovered.rightToLeft,
                baseline.rightToLeft,
                "allocation \(failedAllocation) recovery"
            )
        }
    }

    private func assertPreflightRejection(
        left: [UInt8],
        leftCount: Int,
        right: [UInt8],
        rightCount: Int,
        flags: UInt64 = 0,
        detectMoves: Bool = false,
        forceNilLeft: Bool = false,
        forceNilRight: Bool = false,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        mmx_test_fail_allocation_after(0)
        defer { mmx_test_disable_allocation_failures() }
        let outcome = runDiff(
            left: left,
            leftCount: leftCount,
            right: right,
            rightCount: rightCount,
            flags: flags,
            detectMoves: detectMoves,
            forceNilLeft: forceNilLeft,
            forceNilRight: forceNilRight
        )

        XCTAssertEqual(outcome.status, -1, context, file: file, line: line)
        XCTAssertEqual(outcome.allocationAttempts, 0, context, file: file, line: line)
        assertEmptyOutputs(outcome, context: context, file: file, line: line)
    }

    private func runDiff(
        left: [UInt8],
        leftCount: Int? = nil,
        right: [UInt8],
        rightCount: Int? = nil,
        flags: UInt64 = 0,
        detectMoves: Bool,
        forceNilLeft: Bool = false,
        forceNilRight: Bool = false
    ) -> RawDiffOutcome {
        var result = mmx_diff_result(hunks: nil, count: 0)
        var moved = mmx_moved_result(
            left_to_right: nil,
            left_to_right_count: 0,
            right_to_left: nil,
            right_to_left_count: 0
        )
        let status = left.withUnsafeBytes { leftBuffer in
            right.withUnsafeBytes { rightBuffer in
                let leftPointer = forceNilLeft ? nil : leftBuffer.baseAddress
                let rightPointer = forceNilRight ? nil : rightBuffer.baseAddress
                if detectMoves {
                    return mmx_diff_with_moves(
                        leftPointer,
                        leftCount ?? leftBuffer.count,
                        rightPointer,
                        rightCount ?? rightBuffer.count,
                        flags,
                        &result,
                        &moved
                    )
                }
                return mmx_diff(
                    leftPointer,
                    leftCount ?? leftBuffer.count,
                    rightPointer,
                    rightCount ?? rightBuffer.count,
                    flags,
                    &result
                )
            }
        }

        let leftLineCount = lineCount(in: left)
        let rightLineCount = lineCount(in: right)
        let hunkCount = result.count
        let leftToRightCount = moved.left_to_right_count
        let rightToLeftCount = moved.right_to_left_count
        let hasHunkStorage = result.hunks != nil
        let hasLeftToRightStorage = moved.left_to_right != nil
        let hasRightToLeftStorage = moved.right_to_left != nil
        let allocationAttempts = Int(mmx_test_allocation_attempt_count())

        guard status == 0 else {
            XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
            return RawDiffOutcome(
                status: status,
                hunks: [],
                leftToRight: [],
                rightToLeft: [],
                hunkCount: hunkCount,
                leftToRightCount: leftToRightCount,
                rightToLeftCount: rightToLeftCount,
                hasHunkStorage: hasHunkStorage,
                hasLeftToRightStorage: hasLeftToRightStorage,
                hasRightToLeftStorage: hasRightToLeftStorage,
                allocationAttempts: allocationAttempts
            )
        }

        let hunks = validatedHunks(
            pointer: result.hunks,
            count: hunkCount,
            maximumCount: leftLineCount + rightLineCount
        )
        let leftToRight = validatedMovedLines(
            pointer: moved.left_to_right,
            count: leftToRightCount,
            maximumCount: leftLineCount
        )
        let rightToLeft = validatedMovedLines(
            pointer: moved.right_to_left,
            count: rightToLeftCount,
            maximumCount: rightLineCount
        )

        mmx_diff_result_free(&result)
        if detectMoves {
            mmx_moved_result_free(&moved)
        }
        XCTAssertNil(result.hunks)
        XCTAssertEqual(result.count, 0)
        XCTAssertNil(moved.left_to_right)
        XCTAssertEqual(moved.left_to_right_count, 0)
        XCTAssertNil(moved.right_to_left)
        XCTAssertEqual(moved.right_to_left_count, 0)
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)

        return RawDiffOutcome(
            status: status,
            hunks: hunks,
            leftToRight: leftToRight,
            rightToLeft: rightToLeft,
            hunkCount: hunkCount,
            leftToRightCount: leftToRightCount,
            rightToLeftCount: rightToLeftCount,
            hasHunkStorage: hasHunkStorage,
            hasLeftToRightStorage: hasLeftToRightStorage,
            hasRightToLeftStorage: hasRightToLeftStorage,
            allocationAttempts: allocationAttempts
        )
    }

    private func validatedHunks(
        pointer: UnsafeMutablePointer<mmx_diff_hunk>?,
        count: Int,
        maximumCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [RawHunk] {
        guard count >= 0, count <= maximumCount, (pointer != nil) == (count != 0) else {
            XCTFail("Invalid hunk pointer/count pair: pointer=\(pointer != nil), count=\(count)", file: file, line: line)
            return []
        }
        guard let pointer else { return [] }

        return UnsafeBufferPointer(start: pointer, count: count).map {
            RawHunk(
                leftStart: $0.left_start,
                leftCount: $0.left_count,
                rightStart: $0.right_start,
                rightCount: $0.right_count,
                isTrivial: $0.is_trivial
            )
        }
    }

    private func validatedMovedLines(
        pointer: UnsafeMutablePointer<mmx_moved_line>?,
        count: Int,
        maximumCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [RawMovedLine] {
        guard count >= 0, count <= maximumCount, (pointer != nil) == (count != 0) else {
            XCTFail("Invalid moved pointer/count pair: pointer=\(pointer != nil), count=\(count)", file: file, line: line)
            return []
        }
        guard let pointer else { return [] }

        return UnsafeBufferPointer(start: pointer, count: count).map {
            RawMovedLine(leftLine: $0.left_line, rightLine: $0.right_line)
        }
    }

    private func assertValidHunks(
        _ hunks: [RawHunk],
        leftLines: [[UInt8]],
        rightLines: [[UInt8]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let leftLimit = Int64(leftLines.count)
        let rightLimit = Int64(rightLines.count)
        var previousLeftEnd: Int64 = 0
        var previousRightEnd: Int64 = 0

        for hunk in hunks {
            XCTAssertGreaterThanOrEqual(hunk.leftStart, previousLeftEnd, file: file, line: line)
            XCTAssertGreaterThanOrEqual(hunk.rightStart, previousRightEnd, file: file, line: line)
            XCTAssertGreaterThanOrEqual(hunk.leftCount, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(hunk.rightCount, 0, file: file, line: line)
            XCTAssertTrue(hunk.leftCount != 0 || hunk.rightCount != 0, file: file, line: line)
            XCTAssertTrue(hunk.isTrivial == 0 || hunk.isTrivial == 1, file: file, line: line)

            guard hunk.leftStart >= previousLeftEnd,
                hunk.rightStart >= previousRightEnd,
                hunk.leftCount >= 0,
                hunk.rightCount >= 0,
                hunk.leftStart <= leftLimit,
                hunk.rightStart <= rightLimit
            else {
                continue
            }

            XCTAssertLessThanOrEqual(hunk.leftCount, leftLimit - hunk.leftStart, file: file, line: line)
            XCTAssertLessThanOrEqual(hunk.rightCount, rightLimit - hunk.rightStart, file: file, line: line)
            guard hunk.leftCount <= leftLimit - hunk.leftStart,
                hunk.rightCount <= rightLimit - hunk.rightStart
            else {
                continue
            }

            XCTAssertEqual(
                hunk.leftStart - previousLeftEnd,
                hunk.rightStart - previousRightEnd,
                "unchanged gap must consume equal line counts",
                file: file,
                line: line
            )
            XCTAssertEqual(
                Array(leftLines[Int(previousLeftEnd)..<Int(hunk.leftStart)]),
                Array(rightLines[Int(previousRightEnd)..<Int(hunk.rightStart)]),
                "unchanged gap must have equal bytes",
                file: file,
                line: line
            )
            previousLeftEnd = hunk.leftStart + hunk.leftCount
            previousRightEnd = hunk.rightStart + hunk.rightCount
        }

        XCTAssertEqual(
            leftLimit - previousLeftEnd,
            rightLimit - previousRightEnd,
            "unchanged trailing suffix must consume equal line counts",
            file: file,
            line: line
        )
        guard previousLeftEnd <= leftLimit, previousRightEnd <= rightLimit else { return }
        XCTAssertEqual(
            Array(leftLines[Int(previousLeftEnd)..<leftLines.endIndex]),
            Array(rightLines[Int(previousRightEnd)..<rightLines.endIndex]),
            "unchanged trailing suffix must have equal bytes",
            file: file,
            line: line
        )
    }

    private func assertValidMovedMaps(
        _ outcome: RawDiffOutcome,
        leftLines: [[UInt8]],
        rightLines: [[UInt8]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(outcome.leftToRightCount, outcome.leftToRight.count, file: file, line: line)
        XCTAssertEqual(outcome.rightToLeftCount, outcome.rightToLeft.count, file: file, line: line)
        XCTAssertEqual(outcome.leftToRightCount, outcome.rightToLeftCount, file: file, line: line)
        XCTAssertEqual(outcome.hasLeftToRightStorage, !outcome.leftToRight.isEmpty, file: file, line: line)
        XCTAssertEqual(outcome.hasRightToLeftStorage, !outcome.rightToLeft.isEmpty, file: file, line: line)
        XCTAssertEqual(Set(outcome.leftToRight).count, outcome.leftToRight.count, file: file, line: line)
        XCTAssertEqual(Set(outcome.rightToLeft).count, outcome.rightToLeft.count, file: file, line: line)
        XCTAssertEqual(
            Set(outcome.leftToRight.map(\.leftLine)).count,
            outcome.leftToRight.count,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(outcome.leftToRight.map(\.rightLine)).count,
            outcome.leftToRight.count,
            file: file,
            line: line
        )
        XCTAssertEqual(Set(outcome.leftToRight), Set(outcome.rightToLeft), file: file, line: line)

        for (previous, current) in zip(outcome.leftToRight, outcome.leftToRight.dropFirst()) {
            XCTAssertLessThan(previous.leftLine, current.leftLine, file: file, line: line)
        }
        for (previous, current) in zip(outcome.rightToLeft, outcome.rightToLeft.dropFirst()) {
            XCTAssertLessThan(previous.rightLine, current.rightLine, file: file, line: line)
        }

        for movedLine in outcome.leftToRight + outcome.rightToLeft {
            XCTAssertGreaterThanOrEqual(movedLine.leftLine, 0, file: file, line: line)
            XCTAssertLessThan(movedLine.leftLine, Int32(leftLines.count), file: file, line: line)
            XCTAssertGreaterThanOrEqual(movedLine.rightLine, 0, file: file, line: line)
            XCTAssertLessThan(movedLine.rightLine, Int32(rightLines.count), file: file, line: line)

            guard movedLine.leftLine >= 0,
                movedLine.leftLine < Int32(leftLines.count),
                movedLine.rightLine >= 0,
                movedLine.rightLine < Int32(rightLines.count)
            else {
                continue
            }

            let leftLine = Int64(movedLine.leftLine)
            let rightLine = Int64(movedLine.rightLine)
            XCTAssertTrue(
                outcome.hunks.contains {
                    $0.leftCount > 0 && leftLine >= $0.leftStart && leftLine - $0.leftStart < $0.leftCount
                },
                "moved left line must belong to a changed hunk",
                file: file,
                line: line
            )
            XCTAssertTrue(
                outcome.hunks.contains {
                    $0.rightCount > 0 && rightLine >= $0.rightStart && rightLine - $0.rightStart < $0.rightCount
                },
                "moved right line must belong to a changed hunk",
                file: file,
                line: line
            )
            XCTAssertEqual(
                leftLines[Int(movedLine.leftLine)],
                rightLines[Int(movedLine.rightLine)],
                "untransformed moved lines must have equal bytes",
                file: file,
                line: line
            )
        }
    }

    private func assertMalformedMovedOutputRejection(
        input: UnsafeRawBufferPointer,
        moved: inout mmx_moved_result,
        expectedLeftToRight: UnsafeMutablePointer<mmx_moved_line>?,
        expectedLeftToRightCount: Int,
        expectedRightToLeft: UnsafeMutablePointer<mmx_moved_line>?,
        expectedRightToLeftCount: Int,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var result = mmx_diff_result(hunks: nil, count: 0)

        XCTAssertEqual(
            mmx_diff_with_moves(
                input.baseAddress,
                input.count,
                input.baseAddress,
                input.count,
                0,
                &result,
                &moved
            ),
            -1,
            context,
            file: file,
            line: line
        )
        XCTAssertNil(result.hunks, context, file: file, line: line)
        XCTAssertEqual(result.count, 0, context, file: file, line: line)
        XCTAssertEqual(moved.left_to_right, expectedLeftToRight, context, file: file, line: line)
        XCTAssertEqual(moved.left_to_right_count, expectedLeftToRightCount, context, file: file, line: line)
        XCTAssertEqual(moved.right_to_left, expectedRightToLeft, context, file: file, line: line)
        XCTAssertEqual(moved.right_to_left_count, expectedRightToLeftCount, context, file: file, line: line)
    }

    private func assertEmptyOutputs(
        _ outcome: RawDiffOutcome,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(outcome.hunks.isEmpty, context, file: file, line: line)
        XCTAssertTrue(outcome.leftToRight.isEmpty, context, file: file, line: line)
        XCTAssertTrue(outcome.rightToLeft.isEmpty, context, file: file, line: line)
        XCTAssertEqual(outcome.hunkCount, 0, context, file: file, line: line)
        XCTAssertEqual(outcome.leftToRightCount, 0, context, file: file, line: line)
        XCTAssertEqual(outcome.rightToLeftCount, 0, context, file: file, line: line)
        XCTAssertFalse(outcome.hasHunkStorage, context, file: file, line: line)
        XCTAssertFalse(outcome.hasLeftToRightStorage, context, file: file, line: line)
        XCTAssertFalse(outcome.hasRightToLeftStorage, context, file: file, line: line)
    }

    private func lineCount(in bytes: [UInt8]) -> Int {
        lines(in: bytes).count
    }

    private func lines(in bytes: [UInt8]) -> [[UInt8]] {
        var result: [[UInt8]] = []
        var index = 0
        while index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0x0D, bytes[index] != 0x0A {
                index += 1
            }
            guard index < bytes.count else {
                result.append(Array(bytes[start..<index]))
                break
            }
            if bytes[index] == 0x0D {
                index += 1
                if index < bytes.count, bytes[index] == 0x0A {
                    index += 1
                }
            } else if bytes[index] == 0x0A {
                index += 1
            }
            result.append(Array(bytes[start..<index]))
        }
        return result
    }
}

private struct RawHunk: Equatable {
    let leftStart: Int64
    let leftCount: Int64
    let rightStart: Int64
    let rightCount: Int64
    let isTrivial: Int32
}

private struct RawMovedLine: Hashable {
    let leftLine: Int32
    let rightLine: Int32
}

private struct RawDiffOutcome {
    let status: Int32
    let hunks: [RawHunk]
    let leftToRight: [RawMovedLine]
    let rightToLeft: [RawMovedLine]
    let hunkCount: Int
    let leftToRightCount: Int
    let rightToLeftCount: Int
    let hasHunkStorage: Bool
    let hasLeftToRightStorage: Bool
    let hasRightToLeftStorage: Bool
    let allocationAttempts: Int
}
