@testable import MacMergeCore
import XCTest

final class DirectionalSymmetryTests: XCTestCase {
    private struct Fixture {
        let name: String
        let left: String
        let right: String
        let options: LineDiffOptions
        let expectedKinds: [DiffKind]
    }

    func testSwappingInputsMirrorsRowsAndInvertsDirectionalKinds() throws {
        for fixture in fixtures {
            let original = try LineDiff.compare(
                left: fixture.left,
                right: fixture.right,
                options: fixture.options
            )
            let swapped = try LineDiff.compare(
                left: fixture.right,
                right: fixture.left,
                options: fixture.options
            )

            XCTAssertEqual(original.map(\.kind), fixture.expectedKinds, fixture.name)
            XCTAssertEqual(swapped.count, original.count, fixture.name)

            for (originalRow, swappedRow) in zip(original, swapped) {
                XCTAssertEqual(
                    swappedRow.id,
                    DiffRow.ID(
                        leftNumber: originalRow.id.rightNumber,
                        rightNumber: originalRow.id.leftNumber
                    ),
                    fixture.name
                )
                XCTAssertEqual(swappedRow.left, originalRow.right, fixture.name)
                XCTAssertEqual(swappedRow.right, originalRow.left, fixture.name)
                XCTAssertEqual(swappedRow.kind, mirrored(originalRow.kind), fixture.name)
            }

            let originalSummary = DiffSummary(rows: original)
            let swappedSummary = DiffSummary(rows: swapped)
            XCTAssertEqual(swappedSummary.unchanged, originalSummary.unchanged, fixture.name)
            XCTAssertEqual(swappedSummary.modified, originalSummary.modified, fixture.name)
            XCTAssertEqual(swappedSummary.removed, originalSummary.added, fixture.name)
            XCTAssertEqual(swappedSummary.added, originalSummary.removed, fixture.name)
        }
    }

    func testSwappingInputsAndCopyDirectionMirrorsMergeResults() throws {
        for fixture in fixtures {
            let rows = try LineDiff.compare(
                left: fixture.left,
                right: fixture.right,
                options: fixture.options
            )

            for row in rows where row.kind != .unchanged {
                let swappedID = DiffRow.ID(
                    leftNumber: row.id.rightNumber,
                    rightNumber: row.id.leftNumber
                )
                let leftToRight = try XCTUnwrap(LineMerge.apply(
                    rowID: row.id,
                    direction: .leftToRight,
                    left: fixture.left,
                    right: fixture.right,
                    options: fixture.options
                ), fixture.name)
                let swappedRightToLeft = try XCTUnwrap(LineMerge.apply(
                    rowID: swappedID,
                    direction: .rightToLeft,
                    left: fixture.right,
                    right: fixture.left,
                    options: fixture.options
                ), fixture.name)
                assertMirrored(leftToRight, swappedRightToLeft, fixture.name)

                let rightToLeft = try XCTUnwrap(LineMerge.apply(
                    rowID: row.id,
                    direction: .rightToLeft,
                    left: fixture.left,
                    right: fixture.right,
                    options: fixture.options
                ), fixture.name)
                let swappedLeftToRight = try XCTUnwrap(LineMerge.apply(
                    rowID: swappedID,
                    direction: .leftToRight,
                    left: fixture.right,
                    right: fixture.left,
                    options: fixture.options
                ), fixture.name)
                assertMirrored(rightToLeft, swappedLeftToRight, fixture.name)
            }

            let leftToRight = try XCTUnwrap(LineMerge.applyAll(
                direction: .leftToRight,
                left: fixture.left,
                right: fixture.right,
                options: fixture.options
            ), fixture.name)
            let swappedRightToLeft = try XCTUnwrap(LineMerge.applyAll(
                direction: .rightToLeft,
                left: fixture.right,
                right: fixture.left,
                options: fixture.options
            ), fixture.name)
            assertMirrored(leftToRight, swappedRightToLeft, fixture.name)

            let rightToLeft = try XCTUnwrap(LineMerge.applyAll(
                direction: .rightToLeft,
                left: fixture.left,
                right: fixture.right,
                options: fixture.options
            ), fixture.name)
            let swappedLeftToRight = try XCTUnwrap(LineMerge.applyAll(
                direction: .leftToRight,
                left: fixture.right,
                right: fixture.left,
                options: fixture.options
            ), fixture.name)
            assertMirrored(rightToLeft, swappedLeftToRight, fixture.name)
        }
    }

    private var fixtures: [Fixture] {
        [
            Fixture(
                name: "mixed independent changes",
                left: "anchor-zero\nleft-replacement\nanchor-one\nleft-only\nanchor-two\nanchor-three",
                right: "anchor-zero\r\nright-replacement\r\nanchor-one\r\nanchor-two\r\nright-only\r\nanchor-three",
                options: LineDiffOptions(),
                expectedKinds: [.unchanged, .modified, .unchanged, .removed, .unchanged, .added, .unchanged]
            ),
            Fixture(
                name: "boundary and uneven changes",
                left: "left-prefix\nboundary-anchor\nleft-paired\nleft-extra\nfinal-anchor\nleft-suffix\n",
                right: "boundary-anchor\r\nright-paired\r\nfinal-anchor\r\nright-suffix\r\n",
                options: LineDiffOptions(algorithm: .minimal),
                expectedKinds: [.removed, .unchanged, .modified, .removed, .unchanged, .modified]
            ),
            Fixture(
                name: "strict line endings",
                left: "strict-start\r\nleft-body\nstrict-end",
                right: "strict-start\nright-body\r\nstrict-end\n",
                options: LineDiffOptions(ignoreLineEndings: false),
                expectedKinds: [.modified, .modified, .modified]
            ),
            Fixture(
                name: "one-sided ignored line",
                left: "filter-anchor\nignored-left-only\nfilter-middle\nleft-real\nfilter-end",
                right: "filter-anchor\nfilter-middle\nright-real\nfilter-end",
                options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: "^ignored-")]),
                expectedKinds: [.unchanged, .unchanged, .unchanged, .modified, .unchanged]
            ),
        ]
    }

    private func mirrored(_ kind: DiffKind) -> DiffKind {
        switch kind {
        case .unchanged:
            .unchanged
        case .modified:
            .modified
        case .removed:
            .added
        case .added:
            .removed
        }
    }

    private func assertMirrored(
        _ original: LineMergeResult,
        _ swapped: LineMergeResult,
        _ fixture: String
    ) {
        XCTAssertEqual(swapped.left, original.right, fixture)
        XCTAssertEqual(swapped.right, original.left, fixture)
    }
}
