import CXDiff
import MacMergeCore
import XCTest

final class AlgorithmRouteParityRegressionTests: XCTestCase {
    private struct Hunk: Equatable, CustomStringConvertible {
        let leftStart: Int64
        let leftCount: Int64
        let rightStart: Int64
        let rightCount: Int64

        var description: String {
            "(\(leftStart),\(leftCount),\(rightStart),\(rightCount))"
        }

        var mirrored: Hunk {
            Hunk(
                leftStart: rightStart,
                leftCount: rightCount,
                rightStart: leftStart,
                rightCount: leftCount
            )
        }
    }

    private struct RowSpan: Equatable, CustomStringConvertible {
        let leftStart: Int?
        let rightStart: Int?
        var count: Int
        let kind: DiffKind

        var description: String {
            "(\(leftStart.map(String.init) ?? "-"),\(rightStart.map(String.init) ?? "-"),\(count),\(kind))"
        }

        var mirrored: RowSpan {
            let mirroredKind: DiffKind =
                switch kind {
                case .unchanged: .unchanged
                case .modified: .modified
                case .removed: .added
                case .added: .removed
                }
            return RowSpan(
                leftStart: rightStart,
                rightStart: leftStart,
                count: count,
                kind: mirroredKind
            )
        }
    }

    private struct DirectionalCapture {
        let forwardHunks: [Hunk]
        let reverseHunks: [Hunk]
        let forwardSpans: [RowSpan]
        let reverseSpans: [RowSpan]
    }

    private struct AlgorithmCapture {
        let algorithm: DiffAlgorithm
        let flags: UInt64
        let repeatedHunks: [Hunk]
        let repeatedSpans: [RowSpan]
        let directional: DirectionalCapture
    }

    func testRepeated360LineFixtureMatchesCapturedOutputs() throws {
        let left = document(blockOrder: Array(0..<15))
        let right = document(blockOrder: [12, 10, 6, 14, 4, 13, 2, 11, 8, 1, 9, 3, 0, 7, 5])
        let captures = algorithmCaptures

        assertCompleteAlgorithmTable(captures)
        for capture in captures {
            let context = "Algorithm: \(capture.algorithm.rawValue)"
            XCTAssertEqual(
                nativeHunks(left: left, right: right, flags: capture.flags),
                capture.repeatedHunks,
                context
            )
            XCTAssertEqual(
                rowSpans(
                    try LineDiff.compare(
                        left: left,
                        right: right,
                        options: LineDiffOptions(
                            algorithm: capture.algorithm,
                            ignoreLineEndings: false
                        )
                    )),
                capture.repeatedSpans,
                context
            )
        }

        let capturesByAlgorithm = captures.reduce(into: [String: AlgorithmCapture]()) {
            $0[$1.algorithm.rawValue] = $1
        }
        guard
            let defaultCapture = capturesByAlgorithm[DiffAlgorithm.default.rawValue],
            let minimalCapture = capturesByAlgorithm[DiffAlgorithm.minimal.rawValue]
        else {
            return XCTFail("Missing default or minimal capture")
        }
        XCTAssertNotEqual(defaultCapture.repeatedHunks, minimalCapture.repeatedHunks)
        XCTAssertNotEqual(defaultCapture.repeatedSpans, minimalCapture.repeatedSpans)
    }

    func testDirectionalFixtureMatchesCapturedOutputs() throws {
        let fixture = directionalFixture
        let captures = algorithmCaptures

        assertCompleteAlgorithmTable(captures)
        for capture in captures {
            let context = "Algorithm: \(capture.algorithm.rawValue)"
            XCTAssertEqual(
                nativeHunks(left: fixture.left, right: fixture.right, flags: capture.flags),
                capture.directional.forwardHunks,
                "Forward \(context)"
            )
            XCTAssertEqual(
                nativeHunks(left: fixture.right, right: fixture.left, flags: capture.flags),
                capture.directional.reverseHunks,
                "Reverse \(context)"
            )
            XCTAssertEqual(
                rowSpans(
                    try LineDiff.compare(
                        left: fixture.left,
                        right: fixture.right,
                        options: LineDiffOptions(
                            algorithm: capture.algorithm,
                            ignoreLineEndings: false
                        )
                    )),
                capture.directional.forwardSpans,
                "Forward \(context)"
            )
            XCTAssertEqual(
                rowSpans(
                    try LineDiff.compare(
                        left: fixture.right,
                        right: fixture.left,
                        options: LineDiffOptions(
                            algorithm: capture.algorithm,
                            ignoreLineEndings: false
                        )
                    )),
                capture.directional.reverseSpans,
                "Reverse \(context)"
            )
        }
    }

    func testDirectionalFixtureMirrorsNativeHunksAndNormalizedSpans() throws {
        let fixture = directionalFixture

        for capture in algorithmCaptures {
            let forwardHunks = nativeHunks(left: fixture.left, right: fixture.right, flags: capture.flags)
            let reverseHunks = nativeHunks(left: fixture.right, right: fixture.left, flags: capture.flags)
            let forwardSpans = rowSpans(
                try LineDiff.compare(
                    left: fixture.left,
                    right: fixture.right,
                    options: LineDiffOptions(
                        algorithm: capture.algorithm,
                        ignoreLineEndings: false
                    )
                ))
            let reverseSpans = rowSpans(
                try LineDiff.compare(
                    left: fixture.right,
                    right: fixture.left,
                    options: LineDiffOptions(
                        algorithm: capture.algorithm,
                        ignoreLineEndings: false
                    )
                ))
            let context = "Algorithm: \(capture.algorithm.rawValue)"

            XCTAssertEqual(reverseHunks, forwardHunks.map(\.mirrored), context)
            XCTAssertEqual(reverseSpans, forwardSpans.map(\.mirrored), context)
        }
    }

    func testLineDiffCompareExecutesBundledNativeRouteForEveryAlgorithm() {
        let fixture = directionalFixture
        defer { mmx_test_disable_allocation_failures() }

        for capture in algorithmCaptures {
            mmx_test_disable_allocation_failures()
            mmx_test_fail_allocation_after(0)
            let context = "Algorithm: \(capture.algorithm.rawValue)"

            XCTAssertThrowsError(
                try LineDiff.compare(
                    left: fixture.left,
                    right: fixture.right,
                    options: LineDiffOptions(
                        algorithm: capture.algorithm,
                        ignoreLineEndings: false
                    )
                ),
                context
            ) { error in
                guard case LineDiffError.nativeEngineFailure = error else {
                    return XCTFail("Expected instrumented native failure, got \(error)")
                }
            }
            XCTAssertGreaterThan(
                mmx_test_allocation_attempt_count(),
                0,
                "\(context) did not execute instrumented mmx_diff"
            )
            XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0, context)
        }
    }

    private var directionalFixture: (left: String, right: String) {
        (
            left: "anchor\nleft replacement\nshared\nleft only\ntail\n",
            right: "anchor\nright replacement\nshared\nright one\nright two\ntail\n"
        )
    }

    // Expected values are captures from the current bundled-native route: direct
    // mmx_diff hunks followed by LineDiff's row normalization. They are not a
    // Windows CDiffWrapper oracle. Native hunk coordinates are zero-based;
    // normalized row coordinates are one-based.
    private var algorithmCaptures: [AlgorithmCapture] {
        let standardDirectional = DirectionalCapture(
            forwardHunks: [hunk(1, 1, 1, 1), hunk(3, 1, 3, 2)],
            reverseHunks: [hunk(1, 1, 1, 1), hunk(3, 2, 3, 1)],
            forwardSpans: [
                span(1, 1, 1, .unchanged),
                span(2, 2, 1, .modified),
                span(3, 3, 1, .unchanged),
                span(4, 4, 1, .modified),
                span(nil, 5, 1, .added),
                span(5, 6, 1, .unchanged)
            ],
            reverseSpans: [
                span(1, 1, 1, .unchanged),
                span(2, 2, 1, .modified),
                span(3, 3, 1, .unchanged),
                span(4, 4, 1, .modified),
                span(5, nil, 1, .removed),
                span(6, 5, 1, .unchanged)
            ]
        )
        let noneDirectional = DirectionalCapture(
            forwardHunks: [hunk(1, 1, 1, 1), hunk(3, 2, 3, 3)],
            reverseHunks: [hunk(1, 1, 1, 1), hunk(3, 3, 3, 2)],
            forwardSpans: [
                span(1, 1, 1, .unchanged),
                span(2, 2, 1, .modified),
                span(3, 3, 1, .unchanged),
                span(4, 4, 2, .modified),
                span(nil, 6, 1, .added)
            ],
            reverseSpans: [
                span(1, 1, 1, .unchanged),
                span(2, 2, 1, .modified),
                span(3, 3, 1, .unchanged),
                span(4, 4, 2, .modified),
                span(6, nil, 1, .removed)
            ]
        )

        return [
            AlgorithmCapture(
                algorithm: .default,
                flags: 0,
                repeatedHunks: [
                    hunk(1, 22, 1, 22),
                    hunk(25, 22, 25, 22),
                    hunk(49, 22, 49, 22),
                    hunk(73, 22, 73, 22),
                    hunk(121, 46, 121, 22),
                    hunk(169, 22, 145, 46),
                    hunk(217, 0, 217, 24),
                    hunk(241, 46, 265, 22),
                    hunk(289, 22, 289, 22),
                    hunk(313, 22, 313, 22),
                    hunk(337, 22, 337, 22)
                ],
                repeatedSpans: [
                    span(1, 1, 1, .unchanged),
                    span(2, 2, 22, .modified),
                    span(24, 24, 2, .unchanged),
                    span(26, 26, 22, .modified),
                    span(48, 48, 2, .unchanged),
                    span(50, 50, 22, .modified),
                    span(72, 72, 2, .unchanged),
                    span(74, 74, 22, .modified),
                    span(96, 96, 26, .unchanged),
                    span(122, 122, 22, .modified),
                    span(144, nil, 24, .removed),
                    span(168, 144, 2, .unchanged),
                    span(170, 146, 22, .modified),
                    span(nil, 168, 24, .added),
                    span(192, 192, 26, .unchanged),
                    span(nil, 218, 24, .added),
                    span(218, 242, 24, .unchanged),
                    span(242, 266, 22, .modified),
                    span(264, nil, 24, .removed),
                    span(288, 288, 2, .unchanged),
                    span(290, 290, 22, .modified),
                    span(312, 312, 2, .unchanged),
                    span(314, 314, 22, .modified),
                    span(336, 336, 2, .unchanged),
                    span(338, 338, 22, .modified),
                    span(360, 360, 1, .unchanged)
                ],
                directional: standardDirectional
            ),
            AlgorithmCapture(
                algorithm: .minimal,
                flags: UInt64(MMX_DIFF_NEED_MINIMAL),
                repeatedHunks: [
                    hunk(1, 22, 1, 22),
                    hunk(25, 22, 25, 22),
                    hunk(49, 22, 49, 22),
                    hunk(73, 22, 73, 22),
                    hunk(121, 22, 121, 22),
                    hunk(145, 22, 145, 22),
                    hunk(169, 22, 169, 22),
                    hunk(217, 0, 217, 24),
                    hunk(241, 46, 265, 22),
                    hunk(289, 22, 289, 22),
                    hunk(313, 22, 313, 22),
                    hunk(337, 22, 337, 22)
                ],
                repeatedSpans: [
                    span(1, 1, 1, .unchanged),
                    span(2, 2, 22, .modified),
                    span(24, 24, 2, .unchanged),
                    span(26, 26, 22, .modified),
                    span(48, 48, 2, .unchanged),
                    span(50, 50, 22, .modified),
                    span(72, 72, 2, .unchanged),
                    span(74, 74, 22, .modified),
                    span(96, 96, 26, .unchanged),
                    span(122, 122, 22, .modified),
                    span(144, 144, 2, .unchanged),
                    span(146, 146, 22, .modified),
                    span(168, 168, 2, .unchanged),
                    span(170, 170, 22, .modified),
                    span(192, 192, 26, .unchanged),
                    span(nil, 218, 24, .added),
                    span(218, 242, 24, .unchanged),
                    span(242, 266, 22, .modified),
                    span(264, nil, 24, .removed),
                    span(288, 288, 2, .unchanged),
                    span(290, 290, 22, .modified),
                    span(312, 312, 2, .unchanged),
                    span(314, 314, 22, .modified),
                    span(336, 336, 2, .unchanged),
                    span(338, 338, 22, .modified),
                    span(360, 360, 1, .unchanged)
                ],
                directional: standardDirectional
            ),
            AlgorithmCapture(
                algorithm: .patience,
                flags: UInt64(MMX_DIFF_PATIENCE),
                repeatedHunks: [
                    hunk(1, 142, 1, 46),
                    hunk(169, 22, 73, 118),
                    hunk(217, 0, 217, 24),
                    hunk(241, 22, 265, 22),
                    hunk(265, 22, 289, 22),
                    hunk(289, 22, 313, 22),
                    hunk(313, 46, 337, 22)
                ],
                repeatedSpans: [
                    span(1, 1, 1, .unchanged),
                    span(2, 2, 46, .modified),
                    span(48, nil, 96, .removed),
                    span(144, 48, 26, .unchanged),
                    span(170, 74, 22, .modified),
                    span(nil, 96, 96, .added),
                    span(192, 192, 26, .unchanged),
                    span(nil, 218, 24, .added),
                    span(218, 242, 24, .unchanged),
                    span(242, 266, 22, .modified),
                    span(264, 288, 2, .unchanged),
                    span(266, 290, 22, .modified),
                    span(288, 312, 2, .unchanged),
                    span(290, 314, 22, .modified),
                    span(312, 336, 2, .unchanged),
                    span(314, 338, 22, .modified),
                    span(336, nil, 24, .removed),
                    span(360, 360, 1, .unchanged)
                ],
                directional: standardDirectional
            ),
            AlgorithmCapture(
                algorithm: .histogram,
                flags: UInt64(MMX_DIFF_HISTOGRAM),
                repeatedHunks: [
                    hunk(1, 238, 1, 22),
                    hunk(265, 22, 49, 22),
                    hunk(289, 22, 73, 46),
                    hunk(337, 22, 145, 214)
                ],
                repeatedSpans: [
                    span(1, 1, 1, .unchanged),
                    span(2, 2, 22, .modified),
                    span(24, nil, 216, .removed),
                    span(240, 24, 26, .unchanged),
                    span(266, 50, 22, .modified),
                    span(288, 72, 2, .unchanged),
                    span(290, 74, 22, .modified),
                    span(nil, 96, 24, .added),
                    span(312, 120, 26, .unchanged),
                    span(338, 146, 22, .modified),
                    span(nil, 168, 192, .added),
                    span(360, 360, 1, .unchanged)
                ],
                directional: standardDirectional
            ),
            AlgorithmCapture(
                algorithm: .none,
                flags: UInt64(MMX_DIFF_NONE),
                repeatedHunks: [
                    hunk(1, 22, 1, 22),
                    hunk(25, 22, 25, 22),
                    hunk(49, 22, 49, 22),
                    hunk(73, 22, 73, 22),
                    hunk(121, 22, 121, 22),
                    hunk(145, 22, 145, 22),
                    hunk(169, 22, 169, 22),
                    hunk(217, 22, 217, 22),
                    hunk(241, 22, 241, 22),
                    hunk(265, 22, 265, 22),
                    hunk(289, 22, 289, 22),
                    hunk(313, 22, 313, 22),
                    hunk(337, 22, 337, 22)
                ],
                repeatedSpans: [
                    span(1, 1, 1, .unchanged),
                    span(2, 2, 22, .modified),
                    span(24, 24, 2, .unchanged),
                    span(26, 26, 22, .modified),
                    span(48, 48, 2, .unchanged),
                    span(50, 50, 22, .modified),
                    span(72, 72, 2, .unchanged),
                    span(74, 74, 22, .modified),
                    span(96, 96, 26, .unchanged),
                    span(122, 122, 22, .modified),
                    span(144, 144, 2, .unchanged),
                    span(146, 146, 22, .modified),
                    span(168, 168, 2, .unchanged),
                    span(170, 170, 22, .modified),
                    span(192, 192, 26, .unchanged),
                    span(218, 218, 22, .modified),
                    span(240, 240, 2, .unchanged),
                    span(242, 242, 22, .modified),
                    span(264, 264, 2, .unchanged),
                    span(266, 266, 22, .modified),
                    span(288, 288, 2, .unchanged),
                    span(290, 290, 22, .modified),
                    span(312, 312, 2, .unchanged),
                    span(314, 314, 22, .modified),
                    span(336, 336, 2, .unchanged),
                    span(338, 338, 22, .modified),
                    span(360, 360, 1, .unchanged)
                ],
                directional: noneDirectional
            )
        ]
    }

    private func assertCompleteAlgorithmTable(
        _ captures: [AlgorithmCapture],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            captures.map(\.algorithm),
            [.default, .minimal, .patience, .histogram, .none],
            file: file,
            line: line
        )
    }

    private func document(blockOrder: [Int]) -> String {
        blockOrder.flatMap { block -> [String] in
            ["ambiguous-repeat"]
                + (0..<22).map { "block-\(block)-line-\($0)" }
                + ["ambiguous-repeat"]
        }.joined(separator: "\n") + "\n"
    }

    private func hunk(_ leftStart: Int64, _ leftCount: Int64, _ rightStart: Int64, _ rightCount: Int64) -> Hunk {
        Hunk(
            leftStart: leftStart,
            leftCount: leftCount,
            rightStart: rightStart,
            rightCount: rightCount
        )
    }

    private func span(_ leftStart: Int?, _ rightStart: Int?, _ count: Int, _ kind: DiffKind) -> RowSpan {
        RowSpan(leftStart: leftStart, rightStart: rightStart, count: count, kind: kind)
    }

    private func nativeHunks(left: String, right: String, flags: UInt64) -> [Hunk] {
        let leftBytes = Array(left.utf8)
        let rightBytes = Array(right.utf8)
        var result = mmx_diff_result(hunks: nil, count: 0)
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
        XCTAssertEqual(status, 0)
        guard status == 0 else { return [] }
        defer { mmx_diff_result_free(&result) }
        guard result.count <= leftBytes.count + rightBytes.count else {
            XCTFail("Native hunk count exceeds deterministic input bound")
            return []
        }
        guard result.count > 0 else {
            XCTAssertNil(result.hunks)
            return []
        }
        guard let hunks = result.hunks else {
            XCTFail("Native result has positive count with nil hunk pointer")
            return []
        }
        return UnsafeBufferPointer(start: hunks, count: result.count).map {
            Hunk(
                leftStart: $0.left_start,
                leftCount: $0.left_count,
                rightStart: $0.right_start,
                rightCount: $0.right_count
            )
        }
    }

    private func rowSpans(_ rows: [DiffRow]) -> [RowSpan] {
        var spans: [RowSpan] = []
        for row in rows {
            if let last = spans.last,
                last.kind == row.kind,
                row.left?.number == last.leftStart.map({ $0 + last.count }),
                row.right?.number == last.rightStart.map({ $0 + last.count })
            {
                spans[spans.count - 1].count += 1
            } else {
                spans.append(
                    RowSpan(
                        leftStart: row.left?.number,
                        rightStart: row.right?.number,
                        count: 1,
                        kind: row.kind
                    ))
            }
        }
        return spans
    }
}
