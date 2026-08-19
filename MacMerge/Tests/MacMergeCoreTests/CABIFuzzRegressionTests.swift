import CXDiff
import Foundation
import MacMergeCore
import XCTest

final class CABIFuzzRegressionTests: XCTestCase {
    private let diffSeed: UInt64 = 0xCA81_D1FF_5EED_0001
    private let regexSeed: UInt64 = 0xCA81_2E6E_5EED_0002
    private let encodingSeed: UInt64 = 0xCA81_EAC0_5EED_0003

    override func setUp() {
        super.setUp()
        mmx_test_disable_allocation_failures()
    }

    override func tearDown() {
        mmx_test_disable_allocation_failures()
        // Counter covers CXDiff's xdiff allocator; regex backend allocations remain outside this diagnostic.
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
        super.tearDown()
    }

    func testSeededSafeLengthsAndSupportedFlagsAgreeAcrossDiffEntryPoints() {
        var random = CABIFuzzGenerator(seed: diffSeed)

        for caseIndex in 0..<96 {
            let leftBacking = random.bytes(maximumCount: 256)
            let rightBacking = random.bytes(maximumCount: 256)
            let leftSize = random.int(through: leftBacking.count)
            let rightSize = random.int(through: rightBacking.count)
            let flags = supportedFlags(random: &random)
            let context = fuzzContext(seed: diffSeed, caseIndex: caseIndex)

            mmx_test_disable_allocation_failures()
            let plain = nativeDiff(
                left: leftBacking,
                leftSize: leftSize,
                right: rightBacking,
                rightSize: rightSize,
                flags: flags,
                detectMoves: false
            )
            mmx_test_disable_allocation_failures()
            let moved = nativeDiff(
                left: leftBacking,
                leftSize: leftSize,
                right: rightBacking,
                rightSize: rightSize,
                flags: flags,
                detectMoves: true
            )

            XCTAssertEqual(plain.status, 0, context)
            XCTAssertEqual(moved.status, 0, context)
            XCTAssertEqual(plain.hunks, moved.hunks, context)
            assertValidHunks(plain, context: context)
            assertValidHunks(moved, context: context)
            XCTAssertEqual(plain.hunkCount, plain.hunks.count, context)
            XCTAssertEqual(moved.hunkCount, moved.hunks.count, context)
            XCTAssertEqual(plain.hasHunkStorage, !plain.hunks.isEmpty, context)
            XCTAssertEqual(moved.hasHunkStorage, !moved.hunks.isEmpty, context)
            XCTAssertEqual(moved.hasLeftToRightStorage, !moved.leftToRight.isEmpty, context)
            XCTAssertEqual(moved.hasRightToLeftStorage, !moved.rightToLeft.isEmpty, context)
            XCTAssertEqual(plain.leftToRightCount, 0, context)
            XCTAssertEqual(plain.rightToLeftCount, 0, context)
            assertValidMovedLines(moved, context: context)
            XCTAssertTrue(plain.outputsResetAfterFree, context)
            XCTAssertTrue(moved.outputsResetAfterFree, context)
            XCTAssertEqual(plain.outstandingAllocations, 0, context)
            XCTAssertEqual(moved.outstandingAllocations, 0, context)
        }

        let deterministicLeft = Array("head\nmove-a\nmove-b\nstable\ntail\n".utf8)
        let deterministicRight = Array("head\nstable\nmove-a\nmove-b\ntail\n".utf8)
        let deterministicMoved = nativeDiff(
            left: deterministicLeft,
            leftSize: deterministicLeft.count,
            right: deterministicRight,
            rightSize: deterministicRight.count,
            flags: 0,
            detectMoves: true
        )
        XCTAssertEqual(deterministicMoved.status, 0)
        assertValidMovedLines(deterministicMoved, requireMoves: true, context: "deterministic moved fixture")
        XCTAssertEqual(deterministicMoved.outstandingAllocations, 0)
    }

    func testSeededInvalidFlagsAndNonzeroResultsFailBeforeAllocation() {
        var random = CABIFuzzGenerator(seed: diffSeed ^ 0xF1A6_5BAD)
        let input = Array("alpha\nbeta\n".utf8)
        let algorithmFlags = [
            UInt64(MMX_DIFF_PATIENCE),
            UInt64(MMX_DIFF_HISTOGRAM),
            UInt64(MMX_DIFF_NONE)
        ]

        for caseIndex in 0..<32 {
            let flags = random.next() | (UInt64(1) << 63)
            mmx_test_disable_allocation_failures()
            let outcome = nativeDiff(
                left: input,
                leftSize: random.int(through: input.count),
                right: input,
                rightSize: random.int(through: input.count),
                flags: flags,
                detectMoves: random.bool()
            )

            XCTAssertEqual(outcome.status, -1, fuzzContext(seed: diffSeed, caseIndex: caseIndex))
            XCTAssertTrue(outcome.hunks.isEmpty)
            XCTAssertTrue(outcome.leftToRight.isEmpty)
            XCTAssertTrue(outcome.rightToLeft.isEmpty)
            XCTAssertEqual(outcome.allocationAttempts, 0)
            XCTAssertEqual(outcome.outstandingAllocations, 0)
        }

        for leftIndex in algorithmFlags.indices {
            for rightIndex in algorithmFlags.indices where leftIndex < rightIndex {
                mmx_test_disable_allocation_failures()
                let outcome = nativeDiff(
                    left: input,
                    leftSize: input.count,
                    right: input,
                    rightSize: input.count,
                    flags: algorithmFlags[leftIndex] | algorithmFlags[rightIndex],
                    detectMoves: true
                )
                XCTAssertEqual(outcome.status, -1)
                XCTAssertEqual(outcome.allocationAttempts, 0)
                XCTAssertEqual(outcome.outstandingAllocations, 0)
            }
        }

        input.withUnsafeBytes { inputBuffer in
            XCTAssertEqual(
                mmx_diff(inputBuffer.baseAddress, inputBuffer.count, inputBuffer.baseAddress, inputBuffer.count, 0, nil),
                -1
            )

            var zeroResult = mmx_diff_result(hunks: nil, count: 0)
            XCTAssertEqual(
                mmx_diff_with_moves(
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    0,
                    &zeroResult,
                    nil
                ),
                -1
            )
            XCTAssertNil(zeroResult.hunks)
            XCTAssertEqual(zeroResult.count, 0)
        }

        var hunk = mmx_diff_hunk(left_start: 1, left_count: 2, right_start: 3, right_count: 4, is_trivial: 1)
        var movedLine = mmx_moved_line(left_line: 5, right_line: 6)
        withUnsafeMutablePointer(to: &hunk) { hunkPointer in
            withUnsafeMutablePointer(to: &movedLine) { movedPointer in
                input.withUnsafeBytes { inputBuffer in
                    var nonzeroResult = mmx_diff_result(hunks: hunkPointer, count: 1)
                    XCTAssertEqual(
                        mmx_diff(
                            inputBuffer.baseAddress,
                            inputBuffer.count,
                            inputBuffer.baseAddress,
                            inputBuffer.count,
                            0,
                            &nonzeroResult
                        ),
                        -1
                    )
                    XCTAssertEqual(nonzeroResult.hunks, hunkPointer)
                    XCTAssertEqual(nonzeroResult.count, 1)

                    var cleanResult = mmx_diff_result(hunks: nil, count: 0)
                    var nonzeroMoved = mmx_moved_result(
                        left_to_right: movedPointer,
                        left_to_right_count: 1,
                        right_to_left: nil,
                        right_to_left_count: 0
                    )
                    XCTAssertEqual(
                        mmx_diff_with_moves(
                            inputBuffer.baseAddress,
                            inputBuffer.count,
                            inputBuffer.baseAddress,
                            inputBuffer.count,
                            0,
                            &cleanResult,
                            &nonzeroMoved
                        ),
                        -1
                    )
                    XCTAssertNil(cleanResult.hunks)
                    XCTAssertEqual(cleanResult.count, 0)
                    XCTAssertEqual(nonzeroMoved.left_to_right, movedPointer)
                    XCTAssertEqual(nonzeroMoved.left_to_right_count, 1)
                }
            }
        }
        XCTAssertEqual(mmx_test_allocation_attempt_count(), 0)
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
    }

    func testSeededAllocationFailuresLeaveReusableZeroedResults() {
        var random = CABIFuzzGenerator(seed: diffSeed ^ 0xA110_CA7E)

        for caseIndex in 0..<12 {
            let token = String(random.next(), radix: 16)
            let left = Array("head\nmove-\(token)\nstable-a\nstable-b\ntail-left-\(caseIndex)\n".utf8)
            let right = Array("head\nstable-a\nstable-b\nmove-\(token)\ntail-right-\(caseIndex)\n".utf8)
            let flags = supportedFlags(random: &random)
            let context = fuzzContext(seed: diffSeed, caseIndex: caseIndex)

            mmx_test_disable_allocation_failures()
            let successful = nativeDiff(
                left: left,
                leftSize: left.count,
                right: right,
                rightSize: right.count,
                flags: flags,
                detectMoves: true
            )
            XCTAssertEqual(successful.status, 0, context)
            XCTAssertGreaterThan(successful.allocationAttempts, 0, context)
            XCTAssertEqual(successful.outstandingAllocations, 0, context)

            let failureIndices = Set([
                0,
                successful.allocationAttempts / 2,
                successful.allocationAttempts - 1
            ])
            for failureIndex in failureIndices.sorted() {
                mmx_test_fail_allocation_after(failureIndex)
                let failed = nativeDiff(
                    left: left,
                    leftSize: left.count,
                    right: right,
                    rightSize: right.count,
                    flags: flags,
                    detectMoves: true
                )

                XCTAssertNotEqual(failed.status, 0, "\(context), allocation \(failureIndex)")
                XCTAssertTrue(failed.hunks.isEmpty, context)
                XCTAssertTrue(failed.leftToRight.isEmpty, context)
                XCTAssertTrue(failed.rightToLeft.isEmpty, context)
                XCTAssertFalse(failed.hasHunkStorage, context)
                XCTAssertFalse(failed.hasLeftToRightStorage, context)
                XCTAssertFalse(failed.hasRightToLeftStorage, context)
                XCTAssertTrue(failed.outputsResetAfterFree, context)
                XCTAssertEqual(failed.outstandingAllocations, 0, context)
            }

            mmx_test_disable_allocation_failures()
            let recovered = nativeDiff(
                left: left,
                leftSize: left.count,
                right: right,
                rightSize: right.count,
                flags: flags,
                detectMoves: true
            )
            XCTAssertEqual(recovered.status, 0, context)
            XCTAssertEqual(recovered.hunks, successful.hunks, context)
            XCTAssertEqual(recovered.leftToRight, successful.leftToRight, context)
            XCTAssertEqual(recovered.rightToLeft, successful.rightToLeft, context)
            XCTAssertEqual(recovered.outstandingAllocations, 0, context)
        }
    }

    func testSeededCRegexAndFilterBuffersHaveBoundedResultsAndCleanup() {
        var random = CABIFuzzGenerator(seed: regexSeed)
        let malformedPatterns = ["[", "(", "\\", "*", "(?", "[z-a]", "a{2,1}", "(?<name"]
        let validPatterns = ["", "a", ".", "^a", "a$", "[ab]+", "(a)?b", "[0-9]{1,3}", "\\s+"]
        let caseFlags: [Int32] = [0, 1, -1, Int32.max]

        for caseIndex in 0..<96 {
            let subject = random.bytes(maximumCount: 64)
            let pattern: [UInt8]
            switch caseIndex % 3 {
            case 0:
                pattern = Array(malformedPatterns[random.int(below: malformedPatterns.count)].utf8)
            case 1:
                pattern = Array(validPatterns[random.int(below: validPatterns.count)].utf8)
            default:
                pattern = random.bytes(maximumCount: 16)
            }
            let replacement = random.bytes(maximumCount: 24)
            let maximumSize = random.int(through: 96)
            let caseSensitive = caseFlags[random.int(below: caseFlags.count)]
            let context = fuzzContext(seed: regexSeed, caseIndex: caseIndex)

            var bytesResult = mmx_bytes_result(bytes: nil, size: 0)
            let substituteStatus = subject.withUnsafeBytes { subjectBuffer in
                pattern.withUnsafeBytes { patternBuffer in
                    replacement.withUnsafeBytes { replacementBuffer in
                        mmx_regex_substitute(
                            subjectBuffer.baseAddress,
                            subjectBuffer.count,
                            patternBuffer.baseAddress,
                            patternBuffer.count,
                            replacementBuffer.baseAddress,
                            replacementBuffer.count,
                            caseSensitive,
                            maximumSize,
                            &bytesResult
                        )
                    }
                }
            }
            XCTAssertTrue((0...4).contains(substituteStatus), context)
            if substituteStatus == 0 {
                XCTAssertLessThanOrEqual(bytesResult.size, maximumSize, context)
                XCTAssertEqual(bytesResult.bytes != nil, bytesResult.size != 0, context)
            } else {
                XCTAssertNil(bytesResult.bytes, context)
                XCTAssertEqual(bytesResult.size, 0, context)
            }
            mmx_bytes_result_free(&bytesResult)
            XCTAssertNil(bytesResult.bytes, context)
            XCTAssertEqual(bytesResult.size, 0, context)
            mmx_bytes_result_free(&bytesResult)

            var filter: UnsafeMutableRawPointer?
            let createStatus = pattern.withUnsafeBytes { patternBuffer in
                mmx_line_filter_create(
                    patternBuffer.baseAddress,
                    patternBuffer.count,
                    caseSensitive,
                    &filter
                )
            }
            XCTAssertTrue((0...3).contains(createStatus), context)
            if createStatus == 0 {
                XCTAssertNotNil(filter, context)
                var matched = Int32.max
                let matchStatus = subject.withUnsafeBytes { subjectBuffer in
                    mmx_line_filter_matches(
                        filter,
                        subjectBuffer.baseAddress,
                        subjectBuffer.count,
                        &matched
                    )
                }
                XCTAssertTrue(matchStatus == 0 || matchStatus == 2 || matchStatus == 3, context)
                XCTAssertTrue(matched == 0 || matched == 1, context)
                mmx_line_filter_free(filter)
                filter = nil
                mmx_line_filter_free(filter)
            } else {
                XCTAssertNil(filter, context)
            }
        }

        let safe = Array("safe".utf8)
        safe.withUnsafeBytes { buffer in
            var nonzeroBytesResult = mmx_bytes_result(bytes: nil, size: 1)
            XCTAssertEqual(
                mmx_regex_substitute(
                    buffer.baseAddress,
                    buffer.count,
                    buffer.baseAddress,
                    buffer.count,
                    buffer.baseAddress,
                    buffer.count,
                    1,
                    buffer.count,
                    &nonzeroBytesResult
                ),
                2
            )
            XCTAssertNil(nonzeroBytesResult.bytes)
            XCTAssertEqual(nonzeroBytesResult.size, 1)

            var sentinel: UInt8 = 0
            withUnsafeMutablePointer(to: &sentinel) { sentinelPointer in
                var nonzeroFilter: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(sentinelPointer)
                XCTAssertEqual(
                    mmx_line_filter_create(buffer.baseAddress, buffer.count, 1, &nonzeroFilter),
                    1
                )
                XCTAssertEqual(nonzeroFilter, UnsafeMutableRawPointer(sentinelPointer))
            }
        }
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
    }

    func testSeededPublicRegexAndLineFilterPatternsMapMalformedInput() {
        var random = CABIFuzzGenerator(seed: regexSeed ^ 0xF117_E25)
        let malformedPatterns = ["[", "(", "\\", "*", "(?", "[z-a]", "a{2,1}", "(?<name", "(?#"]
        let validPatterns = ["", "a", ".", "^alpha", "beta$", "[ab]+", "(alpha)?", "[0-9]{1,3}", "\\s+", "(?:alpha|beta)"]

        for caseIndex in 0..<72 {
            let malformed = caseIndex.isMultiple(of: 3)
            let pattern =
                malformed
                ? malformedPatterns[random.int(below: malformedPatterns.count)]
                : validPatterns[random.int(below: validPatterns.count)]
            let lineFilterOptions = LineDiffOptions(
                lineFilters: [LineFilterRule(pattern: pattern, caseSensitive: random.bool())]
            )
            let substitutionOptions = LineDiffOptions(
                substitutions: [SubstitutionRule(pattern: pattern, replacement: "normalized", caseSensitive: random.bool())]
            )
            let context = "\(fuzzContext(seed: regexSeed, caseIndex: caseIndex)), pattern: \(pattern.debugDescription)"

            if malformed {
                XCTAssertThrowsError(
                    try LineDiff.compare(left: "alpha 1", right: "beta 2", options: lineFilterOptions),
                    context
                ) { error in
                    XCTAssertEqual(error as? LineDiffError, .invalidRegularExpression(pattern), context)
                }
                XCTAssertThrowsError(
                    try LineDiff.compare(left: "alpha 1", right: "beta 2", options: substitutionOptions),
                    context
                ) { error in
                    XCTAssertEqual(error as? LineDiffError, .invalidRegularExpression(pattern), context)
                }
            } else {
                XCTAssertNoThrow(
                    try LineDiff.compare(left: "alpha 1", right: "beta 2", options: lineFilterOptions),
                    context
                )
                XCTAssertNoThrow(
                    try LineDiff.compare(left: "alpha 1", right: "beta 2", options: substitutionOptions),
                    context
                )
            }
            XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0, context)
        }
    }

    func testSeededMalformedEncodingDataEitherFailsTypedOrRoundTripsExactly() {
        var random = CABIFuzzGenerator(seed: encodingSeed)
        let encodings: [TextFileEncoding] = [
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .shiftJIS,
            .japaneseEUC,
            .iso2022JP,
            .windows1250,
            .windows1251,
            .windows1252,
            .windows1253,
            .windows1254
        ]
        let malformedFixtures: [[UInt8]] = [
            [0xC0, 0xAF],
            [0xE2, 0x82],
            [0xFF, 0xFE, 0x00, 0x00, 0x41],
            [0x00, 0x00, 0xFE, 0xFF, 0x41],
            [0x1B],
            [0x1B, 0x24],
            [0x1B, 0x24, 0x42, 0x24],
            [0x8E],
            [0x8F, 0xA1],
            [0x81]
        ]

        for caseIndex in 0..<64 {
            let bytes =
                caseIndex < malformedFixtures.count
                ? malformedFixtures[caseIndex]
                : random.bytes(maximumCount: 48)
            let data = Data(bytes)
            let context = fuzzContext(seed: encodingSeed, caseIndex: caseIndex)

            assertCodecOutcome(data, assuming: nil, context: "\(context), automatic")
            for encoding in encodings {
                assertCodecOutcome(data, assuming: encoding, context: "\(context), \(encoding)")
            }
        }
    }

    @MainActor
    func testSeededPreCancelledLineFilterWorkAlwaysThrowsCancellation() async {
        var random = CABIFuzzGenerator(seed: regexSeed ^ 0xCA11_CE1)

        for caseIndex in 0..<24 {
            let token = String(random.next(), radix: 16)
            let caseSensitive = random.bool()
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try LineDiff.compare(
                        left: "generated-\(token)\nleft-\(caseIndex)",
                        right: "generated-\(token)\nright-\(caseIndex)",
                        options: LineDiffOptions(lineFilters: [
                            LineFilterRule(pattern: "^generated-[0-9a-f]+$", caseSensitive: caseSensitive),
                            LineFilterRule(pattern: "^never$")
                        ])
                    )
                    XCTFail("Expected cancellation. \(fuzzContext(seed: regexSeed, caseIndex: caseIndex))")
                } catch is CancellationError {
                } catch {
                    XCTFail("Unexpected error: \(error). \(fuzzContext(seed: regexSeed, caseIndex: caseIndex))")
                }
                return Int(mmx_test_outstanding_allocation_count())
            }

            let outstandingAllocations = await task.value
            XCTAssertEqual(outstandingAllocations, 0)
        }
    }

    private func supportedFlags(random: inout CABIFuzzGenerator) -> UInt64 {
        let algorithmFlags: [UInt64] = [
            0,
            UInt64(MMX_DIFF_PATIENCE),
            UInt64(MMX_DIFF_HISTOGRAM),
            UInt64(MMX_DIFF_NONE)
        ]
        let optionFlags = [
            UInt64(MMX_DIFF_NEED_MINIMAL),
            UInt64(MMX_DIFF_IGNORE_WHITESPACE),
            UInt64(MMX_DIFF_IGNORE_WHITESPACE_CHANGE),
            UInt64(MMX_DIFF_IGNORE_WHITESPACE_AT_EOL),
            UInt64(MMX_DIFF_IGNORE_CR_AT_EOL),
            UInt64(MMX_DIFF_IGNORE_CASE),
            UInt64(MMX_DIFF_IGNORE_NUMBERS),
            UInt64(MMX_DIFF_IGNORE_BLANK_LINES),
            UInt64(MMX_DIFF_INDENT_HEURISTIC)
        ]
        var flags = algorithmFlags[random.int(below: algorithmFlags.count)]
        for option in optionFlags where random.bool() {
            flags |= option
        }
        return flags
    }

    private func nativeDiff(
        left: [UInt8],
        leftSize: Int,
        right: [UInt8],
        rightSize: Int,
        flags: UInt64,
        detectMoves: Bool
    ) -> CABINativeOutcome {
        precondition(left.indices.contains(leftSize) || leftSize == left.endIndex)
        precondition(right.indices.contains(rightSize) || rightSize == right.endIndex)
        var result = mmx_diff_result(hunks: nil, count: 0)
        var moved = mmx_moved_result(
            left_to_right: nil,
            left_to_right_count: 0,
            right_to_left: nil,
            right_to_left_count: 0
        )
        let status = left.withUnsafeBytes { leftBuffer in
            right.withUnsafeBytes { rightBuffer in
                if detectMoves {
                    mmx_diff_with_moves(
                        leftBuffer.baseAddress,
                        leftSize,
                        rightBuffer.baseAddress,
                        rightSize,
                        flags,
                        &result,
                        &moved
                    )
                } else {
                    mmx_diff(
                        leftBuffer.baseAddress,
                        leftSize,
                        rightBuffer.baseAddress,
                        rightSize,
                        flags,
                        &result
                    )
                }
            }
        }
        let leftLineCount = nativeLineCount(in: left, size: leftSize)
        let rightLineCount = nativeLineCount(in: right, size: rightSize)
        let maximumHunkCount = leftLineCount + rightLineCount
        let hunkCount = result.count
        let leftToRightCount = moved.left_to_right_count
        let rightToLeftCount = moved.right_to_left_count
        let hunkStorageIsCoherent = (result.hunks != nil) == (hunkCount != 0)
        let leftToRightStorageIsCoherent = (moved.left_to_right != nil) == (leftToRightCount != 0)
        let rightToLeftStorageIsCoherent = (moved.right_to_left != nil) == (rightToLeftCount != 0)
        let hunkCountIsBounded = (0...maximumHunkCount).contains(hunkCount)
        let leftToRightCountIsBounded = (0...leftLineCount).contains(leftToRightCount)
        let rightToLeftCountIsBounded = (0...rightLineCount).contains(rightToLeftCount)
        XCTAssertTrue(hunkStorageIsCoherent)
        XCTAssertTrue(leftToRightStorageIsCoherent)
        XCTAssertTrue(rightToLeftStorageIsCoherent)
        XCTAssertTrue(hunkCountIsBounded)
        XCTAssertTrue(leftToRightCountIsBounded)
        XCTAssertTrue(rightToLeftCountIsBounded)

        let hunks: [CABIHunk]
        if hunkStorageIsCoherent, hunkCountIsBounded, let pointer = result.hunks {
            hunks = UnsafeBufferPointer(start: pointer, count: hunkCount).map {
                CABIHunk(
                    leftStart: $0.left_start,
                    leftCount: $0.left_count,
                    rightStart: $0.right_start,
                    rightCount: $0.right_count,
                    isTrivial: $0.is_trivial
                )
            }
        } else {
            hunks = []
        }
        let leftToRight: [CABIMovedPair]
        if leftToRightStorageIsCoherent, leftToRightCountIsBounded, let pointer = moved.left_to_right {
            leftToRight = UnsafeBufferPointer(start: pointer, count: leftToRightCount).map {
                CABIMovedPair(leftLine: $0.left_line, rightLine: $0.right_line)
            }
        } else {
            leftToRight = []
        }
        let rightToLeft: [CABIMovedPair]
        if rightToLeftStorageIsCoherent, rightToLeftCountIsBounded, let pointer = moved.right_to_left {
            rightToLeft = UnsafeBufferPointer(start: pointer, count: rightToLeftCount).map {
                CABIMovedPair(leftLine: $0.left_line, rightLine: $0.right_line)
            }
        } else {
            rightToLeft = []
        }
        let hasHunkStorage = result.hunks != nil
        let hasLeftToRightStorage = moved.left_to_right != nil
        let hasRightToLeftStorage = moved.right_to_left != nil
        let allocationAttempts = Int(mmx_test_allocation_attempt_count())

        mmx_diff_result_free(&result)
        mmx_moved_result_free(&moved)
        let outputsResetAfterFree =
            result.hunks == nil && result.count == 0
            && moved.left_to_right == nil && moved.left_to_right_count == 0
            && moved.right_to_left == nil && moved.right_to_left_count == 0
        mmx_diff_result_free(&result)
        mmx_moved_result_free(&moved)

        return CABINativeOutcome(
            status: status,
            hunks: hunks,
            leftToRight: leftToRight,
            rightToLeft: rightToLeft,
            hunkCount: hunkCount,
            leftToRightCount: leftToRightCount,
            rightToLeftCount: rightToLeftCount,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount,
            hasHunkStorage: hasHunkStorage,
            hasLeftToRightStorage: hasLeftToRightStorage,
            hasRightToLeftStorage: hasRightToLeftStorage,
            allocationAttempts: allocationAttempts,
            outstandingAllocations: Int(mmx_test_outstanding_allocation_count()),
            outputsResetAfterFree: outputsResetAfterFree
        )
    }

    private func nativeLineCount(in bytes: [UInt8], size: Int) -> Int {
        guard size != 0 else { return 0 }

        var lineCount = 0
        var index = 0
        while index < size {
            if bytes[index] == 0x0D {
                lineCount += 1
                if index + 1 < size, bytes[index + 1] == 0x0A {
                    index += 1
                }
            } else if bytes[index] == 0x0A {
                lineCount += 1
            }
            index += 1
        }
        if bytes[size - 1] != 0x0D, bytes[size - 1] != 0x0A {
            lineCount += 1
        }
        return lineCount
    }

    private func assertValidHunks(
        _ outcome: CABINativeOutcome,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var previousLeftEnd: Int64 = 0
        var previousRightEnd: Int64 = 0
        let leftLineCount = Int64(outcome.leftLineCount)
        let rightLineCount = Int64(outcome.rightLineCount)

        for hunk in outcome.hunks {
            XCTAssertGreaterThanOrEqual(hunk.leftStart, 0, context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(hunk.leftCount, 0, context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(hunk.rightStart, 0, context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(hunk.rightCount, 0, context, file: file, line: line)
            guard hunk.leftStart >= 0, hunk.leftCount >= 0,
                hunk.rightStart >= 0, hunk.rightCount >= 0
            else {
                continue
            }

            XCTAssertGreaterThanOrEqual(hunk.leftStart, previousLeftEnd, context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(hunk.rightStart, previousRightEnd, context, file: file, line: line)
            XCTAssertLessThanOrEqual(hunk.leftStart, leftLineCount, context, file: file, line: line)
            XCTAssertLessThanOrEqual(hunk.rightStart, rightLineCount, context, file: file, line: line)
            guard hunk.leftStart <= leftLineCount, hunk.rightStart <= rightLineCount else {
                continue
            }

            XCTAssertLessThanOrEqual(
                hunk.leftCount,
                leftLineCount - hunk.leftStart,
                context,
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                hunk.rightCount,
                rightLineCount - hunk.rightStart,
                context,
                file: file,
                line: line
            )
            guard hunk.leftCount <= leftLineCount - hunk.leftStart,
                hunk.rightCount <= rightLineCount - hunk.rightStart
            else {
                continue
            }
            previousLeftEnd = hunk.leftStart + hunk.leftCount
            previousRightEnd = hunk.rightStart + hunk.rightCount
        }
    }

    private func assertValidMovedLines(
        _ outcome: CABINativeOutcome,
        requireMoves: Bool = false,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(outcome.leftToRightCount, outcome.leftToRight.count, context, file: file, line: line)
        XCTAssertEqual(outcome.rightToLeftCount, outcome.rightToLeft.count, context, file: file, line: line)
        XCTAssertEqual(outcome.leftToRightCount, outcome.rightToLeftCount, context, file: file, line: line)
        if requireMoves {
            XCTAssertGreaterThan(outcome.leftToRightCount, 0, context, file: file, line: line)
        }
        XCTAssertEqual(Set(outcome.leftToRight).count, outcome.leftToRightCount, context, file: file, line: line)
        XCTAssertEqual(Set(outcome.rightToLeft).count, outcome.rightToLeftCount, context, file: file, line: line)
        XCTAssertEqual(
            Set(outcome.leftToRight.map(\.leftLine)).count,
            outcome.leftToRightCount,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(outcome.leftToRight.map(\.rightLine)).count,
            outcome.leftToRightCount,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(outcome.rightToLeft.map(\.leftLine)).count,
            outcome.rightToLeftCount,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(outcome.rightToLeft.map(\.rightLine)).count,
            outcome.rightToLeftCount,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(Set(outcome.leftToRight), Set(outcome.rightToLeft), context, file: file, line: line)
        for pair in outcome.leftToRight + outcome.rightToLeft {
            XCTAssertGreaterThanOrEqual(pair.leftLine, 0, context, file: file, line: line)
            XCTAssertLessThan(pair.leftLine, Int32(outcome.leftLineCount), context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(pair.rightLine, 0, context, file: file, line: line)
            XCTAssertLessThan(pair.rightLine, Int32(outcome.rightLineCount), context, file: file, line: line)
        }
    }

    private func assertCodecOutcome(
        _ data: Data,
        assuming encoding: TextFileEncoding?,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let decoded =
                try encoding.map { try TextFileCodec.decode(data, assuming: $0) }
                ?? TextFileCodec.decode(data)
            do {
                XCTAssertEqual(try TextFileCodec.encode(decoded), data, context, file: file, line: line)

                let freshDocument = DecodedTextFile(
                    text: decoded.text,
                    encoding: decoded.encoding,
                    hasByteOrderMark: decoded.hasByteOrderMark
                )
                let freshEncoding = try TextFileCodec.encode(freshDocument)
                let freshDecoded = try TextFileCodec.decode(freshEncoding, assuming: decoded.encoding)
                XCTAssertEqual(freshDecoded.text, decoded.text, context, file: file, line: line)
                XCTAssertEqual(freshDecoded.encoding, decoded.encoding, context, file: file, line: line)
                XCTAssertEqual(
                    freshDecoded.hasByteOrderMark,
                    decoded.hasByteOrderMark,
                    context,
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    try TextFileCodec.encode(
                        DecodedTextFile(
                            text: freshDecoded.text,
                            encoding: freshDecoded.encoding,
                            hasByteOrderMark: freshDecoded.hasByteOrderMark
                        )),
                    freshEncoding,
                    context,
                    file: file,
                    line: line
                )
            } catch {
                XCTFail("Accepted input did not encode: \(error). \(context)", file: file, line: line)
            }
        } catch is TextFileCodecError {
        } catch {
            XCTFail("Unexpected codec error: \(error). \(context)", file: file, line: line)
        }
    }

    private func fuzzContext(seed: UInt64, caseIndex: Int) -> String {
        "Seed 0x\(String(seed, radix: 16)), case \(caseIndex)"
    }
}

private struct CABIHunk: Equatable {
    let leftStart: Int64
    let leftCount: Int64
    let rightStart: Int64
    let rightCount: Int64
    let isTrivial: Int32
}

private struct CABIMovedPair: Hashable {
    let leftLine: Int32
    let rightLine: Int32
}

private struct CABINativeOutcome {
    let status: Int32
    let hunks: [CABIHunk]
    let leftToRight: [CABIMovedPair]
    let rightToLeft: [CABIMovedPair]
    let hunkCount: Int
    let leftToRightCount: Int
    let rightToLeftCount: Int
    let leftLineCount: Int
    let rightLineCount: Int
    let hasHunkStorage: Bool
    let hasLeftToRightStorage: Bool
    let hasRightToLeftStorage: Bool
    let allocationAttempts: Int
    let outstandingAllocations: Int
    let outputsResetAfterFree: Bool
}

private struct CABIFuzzGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func int(below upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    mutating func int(through upperBound: Int) -> Int {
        int(below: upperBound + 1)
    }

    mutating func bool() -> Bool {
        next() & 1 == 0
    }

    mutating func bytes(maximumCount: Int) -> [UInt8] {
        (0..<int(through: maximumCount)).map { _ in UInt8(truncatingIfNeeded: next()) }
    }
}
