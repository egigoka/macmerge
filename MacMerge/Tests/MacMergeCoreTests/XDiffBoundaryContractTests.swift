import CXDiff
import Foundation
import MacMergeCore
import XCTest

final class XDiffBoundaryContractTests: XCTestCase {
    private struct AlgorithmCase {
        let algorithm: DiffAlgorithm
        let flags: UInt64
    }

    private struct NativeHunk: Equatable {
        let leftStart: Int
        let leftCount: Int
        let rightStart: Int
        let rightCount: Int
        let isTrivial: Bool
    }

    private struct NativeOutcome {
        let status: Int32
        let hunks: [NativeHunk]
        let allocationAttempts: Int
    }

    private let algorithms = [
        AlgorithmCase(algorithm: .default, flags: 0),
        AlgorithmCase(algorithm: .minimal, flags: UInt64(MMX_DIFF_NEED_MINIMAL)),
        AlgorithmCase(algorithm: .patience, flags: UInt64(MMX_DIFF_PATIENCE)),
        AlgorithmCase(algorithm: .histogram, flags: UInt64(MMX_DIFF_HISTOGRAM)),
        AlgorithmCase(algorithm: .none, flags: UInt64(MMX_DIFF_NONE))
    ]
    private let maximumAllocationSweepIndex = 128

    override func setUp() {
        super.setUp()
        mmx_test_disable_allocation_failures()
    }

    override func tearDown() {
        mmx_test_disable_allocation_failures()
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
        super.tearDown()
    }

    func testPublicLineDiffMatchesDirectMMXDiffForEveryAlgorithm() throws {
        let corpora = [repeatedLineCorpus(), minimalHeuristicCorpus(), lineEndingCorpus()]

        for algorithmCase in algorithms {
            for corpus in corpora {
                mmx_test_disable_allocation_failures()
                let native = nativeDiff(left: corpus.left, right: corpus.right, flags: algorithmCase.flags)
                let expected = rowSignature(
                    hunks: native.hunks,
                    leftLineCount: lineCount(in: corpus.left),
                    rightLineCount: lineCount(in: corpus.right)
                )
                let actual = rowSignature(
                    try LineDiff.compare(
                        left: corpus.left,
                        right: corpus.right,
                        options: LineDiffOptions(
                            algorithm: algorithmCase.algorithm,
                            ignoreLineEndings: false
                        )
                    ))
                let context = "Algorithm: \(algorithmCase.algorithm)"

                XCTAssertEqual(native.status, 0, context)
                XCTAssertEqual(actual, expected, context)
                XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0, context)
            }
        }
    }

    func testInjectedNativeFailureNeverFallsBackForAnyAlgorithm() {
        mmx_test_disable_allocation_failures()
        defer { mmx_test_disable_allocation_failures() }

        let corpus = allocationFaultCorpus()
        for algorithmCase in algorithms {
            var reachedSuccessSentinel = false
            var observedLaterFailure = false

            for failedAllocation in 0...maximumAllocationSweepIndex {
                mmx_test_fail_allocation_after(failedAllocation)
                let native = nativeDiff(left: corpus.left, right: corpus.right, flags: algorithmCase.flags)
                let context = "Algorithm: \(algorithmCase.algorithm), allocation: \(failedAllocation)"

                if native.status == 0 {
                    mmx_test_fail_allocation_after(failedAllocation)
                    do {
                        let rows = try LineDiff.compare(
                            left: corpus.left,
                            right: corpus.right,
                            options: LineDiffOptions(
                                algorithm: algorithmCase.algorithm,
                                ignoreLineEndings: false
                            )
                        )
                        XCTAssertEqual(
                            rowSignature(rows),
                            rowSignature(
                                hunks: native.hunks,
                                leftLineCount: lineCount(in: corpus.left),
                                rightLineCount: lineCount(in: corpus.right)
                            ),
                            context
                        )
                    } catch {
                        XCTFail("Success sentinel unexpectedly failed with \(error): \(context)")
                    }
                    XCTAssertEqual(
                        Int(mmx_test_allocation_attempt_count()),
                        native.allocationAttempts,
                        context
                    )
                    XCTAssertTrue(observedLaterFailure, "No later native failure observed: \(context)")
                    reachedSuccessSentinel = true
                    break
                }

                XCTAssertTrue(native.status == -2 || native.status == -3, context)
                XCTAssertTrue(native.hunks.isEmpty, context)
                XCTAssertGreaterThan(native.allocationAttempts, failedAllocation, context)
                observedLaterFailure = observedLaterFailure || native.status == -3

                mmx_test_fail_allocation_after(failedAllocation)
                XCTAssertThrowsError(
                    try LineDiff.compare(
                        left: corpus.left,
                        right: corpus.right,
                        options: LineDiffOptions(
                            algorithm: algorithmCase.algorithm,
                            ignoreLineEndings: false
                        )
                    ),
                    context
                ) { error in
                    XCTAssertEqual(error as? LineDiffError, .nativeEngineFailure(native.status), context)
                }
                XCTAssertEqual(
                    Int(mmx_test_allocation_attempt_count()),
                    native.allocationAttempts,
                    "Retry or fallback changed native allocation path: \(context)"
                )
                XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0, context)
            }

            XCTAssertTrue(
                reachedSuccessSentinel,
                "Algorithm \(algorithmCase.algorithm) exceeded allocation sweep cap "
                    + "\(maximumAllocationSweepIndex)"
            )
        }
    }

    func testExportedHeaderHasExactMMXDeclarationAllowlistAndRuntimeBoundary() throws {
        let root = packageRoot
        let header = try String(
            contentsOf: root.appendingPathComponent("Sources/CXDiff/include/macmerge_xdiff.h"),
            encoding: .utf8
        )
        let lineDiff = try String(
            contentsOf: root.appendingPathComponent("Sources/MacMergeCore/LineDiff.swift"),
            encoding: .utf8
        )
        let uncommentedHeader = removingCComments(from: header)
        let expectedTypes: Set<String> = [
            "mmx_bytes_result",
            "mmx_diff_hunk",
            "mmx_diff_result",
            "mmx_moved_line",
            "mmx_moved_result"
        ]
        let expectedFunctions: Set<String> = [
            "mmx_bytes_result_free",
            "mmx_diff",
            "mmx_diff_result_free",
            "mmx_diff_with_moves",
            "mmx_line_filter_create",
            "mmx_line_filter_free",
            "mmx_line_filter_matches",
            "mmx_moved_result_free",
            "mmx_regex_substitute",
            "mmx_test_allocation_attempt_count",
            "mmx_test_disable_allocation_failures",
            "mmx_test_fail_allocation_after",
            "mmx_test_outstanding_allocation_count"
        ]
        let declaredTypes = try typeDeclarationNames(in: uncommentedHeader)
        let declaredFunctions = Set(
            try captures(
                matching: #"(?m)^[ \t]*(?:int32_t|void|size_t)[ \t\r\n]+(mmx_[A-Za-z0-9_]+)[ \t\r\n]*\("#,
                in: uncommentedHeader
            ))
        let allMMXIdentifiers = Set(
            try captures(
                matching: #"\b(mmx_[A-Za-z0-9_]+)\b"#,
                in: uncommentedHeader
            ))

        XCTAssertEqual(declaredTypes, expectedTypes)
        XCTAssertEqual(declaredFunctions, expectedFunctions)
        XCTAssertEqual(
            allMMXIdentifiers,
            expectedTypes.union(expectedFunctions),
            "Every exported mmx_ declaration must be reviewed and allowlisted"
        )
        for forbiddenType in ["file_data", "xdchange_t", "DiffList"] {
            XCTAssertFalse(header.contains(forbiddenType), "Native ABI exposed \(forbiddenType)")
            XCTAssertFalse(lineDiff.contains(forbiddenType), "Swift boundary imported \(forbiddenType)")
        }
        XCTAssertFalse(lineDiff.contains("xdl_"), "LineDiff must not bypass the mmx_* boundary")
        XCTAssertEqual(lineDiff.components(separatedBy: "mmx_diff(").count - 1, 1)
        XCTAssertEqual(lineDiff.components(separatedBy: "mmx_diff_with_moves(").count - 1, 1)

        XCTAssertEqual(UInt64(MMX_DIFF_NEED_MINIMAL), UInt64(1) << 0)
        XCTAssertEqual(UInt64(MMX_DIFF_IGNORE_CR_AT_EOL), UInt64(1) << 4)
        XCTAssertEqual(UInt64(MMX_DIFF_PATIENCE), UInt64(1) << 14)
        XCTAssertEqual(UInt64(MMX_DIFF_HISTOGRAM), UInt64(1) << 15)
        XCTAssertEqual(UInt64(MMX_DIFF_NONE), UInt64(1) << 16)

        let smoke = nativeDiff(left: "same\nleft\n", right: "same\nright\n", flags: 0)
        XCTAssertEqual(smoke.status, 0)
        XCTAssertEqual(
            smoke.hunks,
            [NativeHunk(leftStart: 1, leftCount: 1, rightStart: 1, rightCount: 1, isTrivial: false)]
        )
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func repeatedLineCorpus() -> (left: String, right: String) {
        (
            ["A", "B", "E", "B", "F", "B", "B", "C", "F", "B", "E", "E"]
                .joined(separator: "\n"),
            ["E", "D", "D", "D", "E", "B", "C", "B", "B", "F", "D", "E"]
                .joined(separator: "\n")
        )
    }

    private func minimalHeuristicCorpus() -> (left: String, right: String) {
        let leftLines = (0..<330).map(numberedLine)
        let blockOrder = [12, 13, 14, 11, 9, 7, 10, 4, 5, 8, 2, 0, 1, 6, 3]
        let rightLines = blockOrder.flatMap { block in
            (block * 22..<(block + 1) * 22).map(numberedLine)
        }
        return (
            leftLines.joined(separator: "\n") + "\n",
            rightLines.joined(separator: "\n") + "\n"
        )
    }

    private func numberedLine(_ number: Int) -> String {
        String(format: "L%06d", number)
    }

    private func lineEndingCorpus() -> (left: String, right: String) {
        ("same\r\nleft\r\n", "same\nright\n")
    }

    private func allocationFaultCorpus() -> (left: String, right: String) {
        (
            "head\nmove-a\nmove-b\nstable-a\nstable-b\ntail-left\n",
            "head\nstable-a\nstable-b\nmove-a\nmove-b\ntail-right\n"
        )
    }

    private func rowSignature(_ rows: [DiffRow]) -> String {
        rows.map { row in
            "\(row.left?.number ?? 0):\(row.right?.number ?? 0):\(String(describing: row.kind))"
        }.joined(separator: ",")
    }

    private func rowSignature(hunks: [NativeHunk], leftLineCount: Int, rightLineCount: Int) -> String {
        var rows: [String] = []
        var leftIndex = 0
        var rightIndex = 0

        for hunk in hunks {
            while leftIndex < hunk.leftStart {
                rows.append("\(leftIndex + 1):\(rightIndex + 1):unchanged")
                leftIndex += 1
                rightIndex += 1
            }

            let leftEnd = leftIndex + hunk.leftCount
            let rightEnd = rightIndex + hunk.rightCount
            while leftIndex < leftEnd || rightIndex < rightEnd {
                let hasLeft = leftIndex < leftEnd
                let hasRight = rightIndex < rightEnd
                let leftNumber = hasLeft ? leftIndex + 1 : 0
                let rightNumber = hasRight ? rightIndex + 1 : 0
                let kind: String
                if hunk.isTrivial {
                    kind = "unchanged"
                } else if hasLeft && hasRight {
                    kind = "modified"
                } else if hasLeft {
                    kind = "removed"
                } else {
                    kind = "added"
                }
                rows.append("\(leftNumber):\(rightNumber):\(kind)")
                if hasLeft { leftIndex += 1 }
                if hasRight { rightIndex += 1 }
            }
        }

        while leftIndex < leftLineCount {
            rows.append("\(leftIndex + 1):\(rightIndex + 1):unchanged")
            leftIndex += 1
            rightIndex += 1
        }
        XCTAssertEqual(rightIndex, rightLineCount)
        return rows.joined(separator: ",")
    }

    private func lineCount(in text: String) -> Int {
        let bytes = Array(text.utf8)
        guard let last = bytes.last else { return 0 }

        var count = 0
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0D {
                count += 1
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    index += 1
                }
            } else if bytes[index] == 0x0A {
                count += 1
            }
            index += 1
        }
        if last != 0x0D, last != 0x0A { count += 1 }
        return count
    }

    private func nativeDiff(left: String, right: String, flags: UInt64) -> NativeOutcome {
        let leftBytes = Array(left.utf8)
        let rightBytes = Array(right.utf8)
        var result = mmx_diff_result(hunks: nil, count: 0)
        defer { mmx_diff_result_free(&result) }

        let status = leftBytes.withUnsafeBytes { leftBuffer in
            rightBytes.withUnsafeBytes { rightBuffer in
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
        let hunks = UnsafeBufferPointer(start: result.hunks, count: result.count).map {
            NativeHunk(
                leftStart: Int($0.left_start),
                leftCount: Int($0.left_count),
                rightStart: Int($0.right_start),
                rightCount: Int($0.right_count),
                isTrivial: $0.is_trivial != 0
            )
        }
        return NativeOutcome(
            status: status,
            hunks: hunks,
            allocationAttempts: Int(mmx_test_allocation_attempt_count())
        )
    }

    private func removingCComments(from source: String) -> String {
        source.replacingOccurrences(
            of: #"(?s)/\*.*?\*/|(?m)//[^\r\n]*"#,
            with: "",
            options: .regularExpression
        )
    }

    private func typeDeclarationNames(in source: String) throws -> Set<String> {
        let expression = try NSRegularExpression(
            pattern: #"(?s)\btypedef\s+struct\s+(mmx_[A-Za-z0-9_]+)\s*\{.*?\}\s*(mmx_[A-Za-z0-9_]+)\s*;"#
        )
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var names: Set<String> = []
        for match in expression.matches(in: source, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: source),
                let aliasRange = Range(match.range(at: 2), in: source)
            else {
                continue
            }
            let tag = String(source[tagRange])
            let alias = String(source[aliasRange])
            XCTAssertEqual(tag, alias, "Public C struct tag and typedef alias must match")
            names.insert(tag)
        }
        return names
    }

    private func captures(matching pattern: String, in source: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        }
    }
}
