@testable import MacMergeCore
import XCTest

final class MergeInvariantTests: XCTestCase {
    private struct RowFixture {
        let name: String
        let left: String
        let right: String
        let options: LineDiffOptions
        let kind: DiffKind
        let selectedLeft: String?
        let selectedRight: String?
        let leftToRightTarget: String
        let rightToLeftTarget: String
    }

    private struct MergeAllFixture {
        let name: String
        let left: String
        let right: String
        let options: LineDiffOptions
    }

    func testRowMergeResolvesOnlySelectedDifferenceAndPreservesOtherBytes() throws {
        for fixture in rowFixtures {
            let initialRows = try LineDiff.compare(
                left: fixture.left,
                right: fixture.right,
                options: fixture.options
            )
            let selectedRow = try XCTUnwrap(initialRows.first {
                $0.kind == fixture.kind
                    && $0.left?.text == fixture.selectedLeft
                    && $0.right?.text == fixture.selectedRight
            }, "\(fixture.name): selected row")
            let initialDifferenceCount = DiffSummary(rows: initialRows).differences

            XCTAssertEqual(initialDifferenceCount, 2, fixture.name)

            for direction in [MergeDirection.leftToRight, .rightToLeft] {
                let context = "\(fixture.name), \(direction)"
                let result = try XCTUnwrap(LineMerge.apply(
                    rowID: selectedRow.id,
                    direction: direction,
                    left: fixture.left,
                    right: fixture.right,
                    options: fixture.options
                ), context)

                switch direction {
                case .leftToRight:
                    assertBytesEqual(result.left, fixture.left, context)
                    assertBytesEqual(result.right, fixture.leftToRightTarget, context)
                case .rightToLeft:
                    assertBytesEqual(result.left, fixture.rightToLeftTarget, context)
                    assertBytesEqual(result.right, fixture.right, context)
                }

                let recomparison = try LineDiff.compare(
                    left: result.left,
                    right: result.right,
                    options: fixture.options
                )
                XCTAssertEqual(
                    DiffSummary(rows: recomparison).differences,
                    initialDifferenceCount - 1,
                    context
                )
                XCTAssertTrue(recomparison.contains {
                    $0.kind == .modified
                        && $0.left?.text == "unrelated-left"
                        && $0.right?.text == "unrelated-right"
                }, "\(context): unrelated difference must remain")
                assertSelectedDifferenceResolved(
                    selectedRow,
                    direction: direction,
                    recomparison: recomparison,
                    context: context
                )
            }
        }
    }

    func testMergeAllRecomparisonHasNoSignificantDifferencesUnderSameOptions() throws {
        let fixtures = rowFixtures.map {
            MergeAllFixture(name: $0.name, left: $0.left, right: $0.right, options: $0.options)
        } + [
            MergeAllFixture(
                name: "strict mixed and final EOL",
                left: "alpha\r\nleft\rfinal",
                right: "alpha\nright\r\nfinal\n",
                options: LineDiffOptions(algorithm: .minimal, ignoreLineEndings: false)
            ),
        ]

        for fixture in fixtures {
            let initialRows = try LineDiff.compare(
                left: fixture.left,
                right: fixture.right,
                options: fixture.options
            )
            XCTAssertGreaterThan(DiffSummary(rows: initialRows).differences, 0, fixture.name)

            for direction in [MergeDirection.leftToRight, .rightToLeft] {
                let context = "\(fixture.name), \(direction)"
                let result = try XCTUnwrap(LineMerge.applyAll(
                    direction: direction,
                    left: fixture.left,
                    right: fixture.right,
                    options: fixture.options
                ), context)

                switch direction {
                case .leftToRight:
                    assertBytesEqual(result.left, fixture.left, context)
                    XCTAssertNotEqual(Array(result.right.utf8), Array(fixture.right.utf8), context)
                case .rightToLeft:
                    assertBytesEqual(result.right, fixture.right, context)
                    XCTAssertNotEqual(Array(result.left.utf8), Array(fixture.left.utf8), context)
                }

                let recomparison = try LineDiff.compare(
                    left: result.left,
                    right: result.right,
                    options: fixture.options
                )
                XCTAssertEqual(DiffSummary(rows: recomparison).differences, 0, context)
            }
        }
    }

    private var rowFixtures: [RowFixture] {
        [
            RowFixture(
                name: "modified with ignored case",
                left: "case sentinel\r\nleft-selected\nstable\runrelated-left\r\nfinal",
                right: "CASE SENTINEL\nright-selected\r\nstable\r\nunrelated-right\nfinal",
                options: LineDiffOptions(algorithm: .histogram, ignoreCase: true),
                kind: .modified,
                selectedLeft: "left-selected",
                selectedRight: "right-selected",
                leftToRightTarget: "CASE SENTINEL\nleft-selected\r\nstable\r\nunrelated-right\nfinal",
                rightToLeftTarget: "case sentinel\r\nright-selected\nstable\runrelated-left\r\nfinal"
            ),
            RowFixture(
                name: "removed row",
                left: "guard\r\nleft-only\nstable\runrelated-left\r\nfinal",
                right: "guard\nstable\r\nunrelated-right\nfinal",
                options: LineDiffOptions(),
                kind: .removed,
                selectedLeft: "left-only",
                selectedRight: nil,
                leftToRightTarget: "guard\nleft-only\nstable\r\nunrelated-right\nfinal",
                rightToLeftTarget: "guard\r\nstable\runrelated-left\r\nfinal"
            ),
            RowFixture(
                name: "added row",
                left: "guard\r\nstable\runrelated-left\r\nfinal",
                right: "guard\nright-only\r\nstable\r\nunrelated-right\nfinal",
                options: LineDiffOptions(),
                kind: .added,
                selectedLeft: nil,
                selectedRight: "right-only",
                leftToRightTarget: "guard\nstable\r\nunrelated-right\nfinal",
                rightToLeftTarget: "guard\r\nright-only\r\nstable\runrelated-left\r\nfinal"
            ),
        ]
    }

    private func assertSelectedDifferenceResolved(
        _ selectedRow: DiffRow,
        direction: MergeDirection,
        recomparison: [DiffRow],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = direction == .leftToRight ? selectedRow.left : selectedRow.right
        let target = direction == .leftToRight ? selectedRow.right : selectedRow.left

        if let source {
            XCTAssertTrue(recomparison.contains {
                $0.kind == .unchanged
                    && $0.left?.text == source.text
                    && $0.right?.text == source.text
            }, "\(context): copied source must recompare unchanged", file: file, line: line)
        } else if let target {
            XCTAssertFalse(recomparison.contains {
                $0.left?.text == target.text || $0.right?.text == target.text
            }, "\(context): copied absence must remove target row", file: file, line: line)
        } else {
            XCTFail("\(context): nontrivial row has no source or target", file: file, line: line)
        }
    }

    private func assertBytesEqual(
        _ actual: String,
        _ expected: String,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Array(actual.utf8), Array(expected.utf8), context, file: file, line: line)
    }
}
