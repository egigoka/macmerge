import CXDiff
@testable import MacMergeCore
import XCTest

final class MovedTransformBoundaryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        mmx_test_disable_allocation_failures()
    }

    override func tearDown() {
        mmx_test_disable_allocation_failures()
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
        super.tearDown()
    }

    func testMovedAndEditedBlockKeepsOnlyExactAnchorsInMetadata() throws {
        let fixture = movedAndEditedFixture(
            openingLeft: "boundary-opening",
            editedLeft: "boundary-edited-left",
            closingLeft: "boundary-closing",
            openingRight: "boundary-opening",
            editedRight: "boundary-edited-right",
            closingRight: "boundary-closing"
        )
        let options = LineDiffOptions(detectMovedBlocks: true)

        let rows = try LineDiff.compare(left: fixture.left, right: fixture.right, options: options)
        let result = try LineDiff.compareResult(
            left: fixture.left,
            right: fixture.right,
            options: options
        )

        XCTAssertEqual(result.rows, rows)
        assertMovedAndEditedRows(result.rows)
        assertOnlyExactMovedAnchors(result.movedLines)
    }

    func testCommentTransformedMoveKeepsExactAnchorsAndRejectsEditedMiddle() throws {
        let fixture = movedAndEditedFixture(
            openingLeft: "comment-opening /* left */",
            editedLeft: "comment-edited-left /* ignored */",
            closingLeft: "comment-closing /* left */",
            openingRight: "comment-opening /* right */",
            editedRight: "comment-edited-right /* ignored */",
            closingRight: "comment-closing /* right */"
        )

        let result = try LineDiff.compareResult(
            left: fixture.left,
            right: fixture.right,
            options: LineDiffOptions(
                ignoreComments: true,
                detectMovedBlocks: true,
                commentSyntax: .cFamily
            )
        )

        assertMovedAndEditedRows(result.rows)
        assertOnlyExactMovedAnchors(result.movedLines)
    }

    func testSubstitutionTransformedMoveKeepsExactAnchorsAndRejectsEditedMiddle() throws {
        let fixture = movedAndEditedFixture(
            openingLeft: "substitution-opening-left",
            editedLeft: "substitution-edited-left",
            closingLeft: "substitution-closing-left",
            openingRight: "substitution-opening-right",
            editedRight: "substitution-edited-right",
            closingRight: "substitution-closing-right"
        )

        let result = try LineDiff.compareResult(
            left: fixture.left,
            right: fixture.right,
            options: LineDiffOptions(
                detectMovedBlocks: true,
                substitutions: [
                    SubstitutionRule(
                        pattern: #"(substitution-(?:opening|closing))-(?:left|right)"#,
                        replacement: "$1-same"
                    )
                ]
            )
        )

        assertMovedAndEditedRows(result.rows)
        assertOnlyExactMovedAnchors(result.movedLines)
    }

    func testTransformedMoveAnalysisBudgetBoundariesAreInclusive() {
        let maximumBytes = LineDiff.transformedMoveAnalysisMaximumBytesPerFile
        let maximumLines = LineDiff.transformedMoveAnalysisMaximumLinesPerFile

        XCTAssertTrue(LineDiff.transformedMoveAnalysisIsWithinBudget(
            leftByteCount: maximumBytes,
            rightByteCount: maximumBytes,
            leftLineCount: maximumLines,
            rightLineCount: maximumLines
        ))
        XCTAssertFalse(LineDiff.transformedMoveAnalysisIsWithinBudget(
            leftByteCount: maximumBytes + 1,
            rightByteCount: maximumBytes,
            leftLineCount: maximumLines,
            rightLineCount: maximumLines
        ))
        XCTAssertFalse(LineDiff.transformedMoveAnalysisIsWithinBudget(
            leftByteCount: maximumBytes,
            rightByteCount: maximumBytes,
            leftLineCount: maximumLines,
            rightLineCount: maximumLines + 1
        ))
    }

    func testRowOnlyCompareDoesNotRunOrFailUnusedMovedAnalysis() throws {
        let fixture = movedAndEditedFixture(
            openingLeft: "allocation-opening",
            editedLeft: "allocation-edited-left",
            closingLeft: "allocation-closing",
            openingRight: "allocation-opening",
            editedRight: "allocation-edited-right",
            closingRight: "allocation-closing"
        )
        let options = LineDiffOptions(detectMovedBlocks: true)

        let expectedRows = try LineDiff.compare(
            left: fixture.left,
            right: fixture.right,
            options: options
        )
        let rowOnlyAllocationCount = mmx_test_allocation_attempt_count()
        XCTAssertGreaterThan(rowOnlyAllocationCount, 0)

        mmx_test_disable_allocation_failures()
        mmx_test_fail_allocation_after(rowOnlyAllocationCount)
        let rows = try LineDiff.compare(left: fixture.left, right: fixture.right, options: options)
        XCTAssertEqual(rows, expectedRows)
        XCTAssertEqual(mmx_test_allocation_attempt_count(), rowOnlyAllocationCount)
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)

        mmx_test_disable_allocation_failures()
        mmx_test_fail_allocation_after(rowOnlyAllocationCount)
        XCTAssertThrowsError(
            try LineDiff.compareResult(left: fixture.left, right: fixture.right, options: options)
        ) { error in
            XCTAssertEqual(error as? LineDiffError, .nativeEngineFailure(-3))
        }
        XCTAssertGreaterThan(mmx_test_allocation_attempt_count(), rowOnlyAllocationCount)
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
    }

    func testActiveTransformPropagatesInjectedNativeMoveFailure() throws {
        let fixture = movedAndEditedFixture(
            openingLeft: "failure-opening-left",
            editedLeft: "failure-edited-left",
            closingLeft: "failure-closing-left",
            openingRight: "failure-opening-right",
            editedRight: "failure-edited-right",
            closingRight: "failure-closing-right"
        )
        let primaryOptions = LineDiffOptions(ignoreLineEndings: false)
        let options = LineDiffOptions(
            ignoreLineEndings: false,
            detectMovedBlocks: true,
            substitutions: [
                SubstitutionRule(
                    pattern: #"(failure-(?:opening|closing))-(?:left|right)"#,
                    replacement: "$1-same"
                )
            ]
        )

        _ = try LineDiff.compare(
            left: fixture.left,
            right: fixture.right,
            options: primaryOptions
        )
        let primaryAllocationCount = Int(mmx_test_allocation_attempt_count())
        XCTAssertGreaterThan(primaryAllocationCount, 0)

        mmx_test_fail_allocation_after(primaryAllocationCount)
        XCTAssertThrowsError(
            try LineDiff.compareResult(
                left: fixture.left,
                right: fixture.right,
                options: options
            )
        ) { error in
            XCTAssertEqual(error as? LineDiffError, .nativeEngineFailure(-2))
        }
        XCTAssertEqual(
            Int(mmx_test_allocation_attempt_count()),
            primaryAllocationCount + 1
        )
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
    }

    func testTransformedMoveAnalysisByteBudgetSkipsOnlyMetadataAboveBoundary() throws {
        let maximumBytes = LineDiff.transformedMoveAnalysisMaximumBytesPerFile
        let options = LineDiffOptions(
            ignoreBlankLines: true,
            ignoreLineEndings: false,
            detectMovedBlocks: true
        )

        do {
            let fixture = budgetedMovedAndEditedFixture(byteCount: maximumBytes)
            let result = try LineDiff.compareResult(
                left: fixture.left,
                right: fixture.right,
                options: options
            )

            XCTAssertEqual(fixture.left.utf8.count, maximumBytes)
            XCTAssertEqual(fixture.right.utf8.count, maximumBytes)
            assertMovedAndEditedRows(result.rows)
            assertOnlyExactMovedAnchors(result.movedLines)
            XCTAssertEqual(result.movedLineAnalysisStatus, .available)
        }

        let fixture = budgetedMovedAndEditedFixture(byteCount: maximumBytes + 1)
        let result = try LineDiff.compareResult(
            left: fixture.left,
            right: fixture.right,
            options: options
        )

        XCTAssertEqual(fixture.left.utf8.count, maximumBytes + 1)
        XCTAssertEqual(fixture.right.utf8.count, maximumBytes + 1)
        assertMovedAndEditedRows(result.rows)
        XCTAssertTrue(result.movedLines.isEmpty)
        XCTAssertEqual(result.movedLineAnalysisStatus, .unavailableWithinResourceLimits)
    }

    func testSubstitutionExpansionPastMoveBudgetSkipsOnlyMetadata() throws {
        let repeatedLineCount = 256
        let movedLines = ["expand-opening", "expand-middle", "expand-closing"]
        let left = substitutionExpansionFixture(
            repeatedLineCount: repeatedLineCount,
            movedLines: movedLines.map { $0 + "-left" },
            movedLinesFirst: true
        )
        let right = substitutionExpansionFixture(
            repeatedLineCount: repeatedLineCount,
            movedLines: movedLines.map { $0 + "-right" },
            movedLinesFirst: false
        )
        let replacement = String(repeating: "x", count: 32 * 1024)
        let options = LineDiffOptions(
            detectMovedBlocks: true,
            substitutions: [
                SubstitutionRule(pattern: "^x$", replacement: replacement),
                SubstitutionRule(
                    pattern: #"(expand-(?:opening|middle|closing))-(?:left|right)"#,
                    replacement: "$1-same"
                )
            ]
        )

        XCTAssertLessThan(left.utf8.count, 1024)
        XCTAssertGreaterThan(
            repeatedLineCount * (replacement.utf8.count + 1),
            LineDiff.transformedMoveAnalysisMaximumBytesPerFile
        )

        let controlLineCount = 3
        let control = try LineDiff.compareResult(
            left: substitutionExpansionFixture(
                repeatedLineCount: controlLineCount,
                movedLines: movedLines.map { $0 + "-left" },
                movedLinesFirst: true
            ),
            right: substitutionExpansionFixture(
                repeatedLineCount: controlLineCount,
                movedLines: movedLines.map { $0 + "-right" },
                movedLinesFirst: false
            ),
            options: options
        )
        XCTAssertEqual(control.movedLines.leftToRightCount, movedLines.count)
        for index in movedLines.indices {
            XCTAssertEqual(
                control.movedLines.rightLine(forLeftLine: index + 2),
                controlLineCount + index + 2
            )
        }

        let expectedRows = try LineDiff.compare(left: left, right: right, options: options)
        let result = try LineDiff.compareResult(left: left, right: right, options: options)

        XCTAssertEqual(result.rows, expectedRows)
        XCTAssertFalse(result.rows.isEmpty)
        XCTAssertTrue(result.movedLines.isEmpty)
        XCTAssertEqual(result.movedLineAnalysisStatus, .unavailableWithinResourceLimits)
    }

    private func movedAndEditedFixture(
        openingLeft: String,
        editedLeft: String,
        closingLeft: String,
        openingRight: String,
        editedRight: String,
        closingRight: String
    ) -> (left: String, right: String) {
        let stable = ["boundary-stable-one", "boundary-stable-two", "boundary-stable-three"]
        return (
            (["boundary-root", openingLeft, editedLeft, closingLeft] + stable + ["boundary-tail"])
                .joined(separator: "\n"),
            (["boundary-root"] + stable + [openingRight, editedRight, closingRight, "boundary-tail"])
                .joined(separator: "\n")
        )
    }

    private func budgetedMovedAndEditedFixture(byteCount: Int) -> (left: String, right: String) {
        let stable = ["boundary-stable-one", "boundary-stable-two", "boundary-stable-three"]
        let leftSuffix = ([
            "boundary-opening",
            "boundary-edited-one",
            "boundary-closing"
        ] + stable + ["boundary-tail"]).joined(separator: "\n")
        let rightSuffix = (stable + [
            "boundary-opening",
            "boundary-edited-two",
            "boundary-closing",
            "boundary-tail"
        ]).joined(separator: "\n")
        precondition(leftSuffix.utf8.count == rightSuffix.utf8.count)
        let padding = String(repeating: "x", count: byteCount - leftSuffix.utf8.count - 1)
        return (padding + "\n" + leftSuffix, padding + "\n" + rightSuffix)
    }

    private func substitutionExpansionFixture(
        repeatedLineCount: Int,
        movedLines: [String],
        movedLinesFirst: Bool
    ) -> String {
        let repeatedLines = Array(repeating: "x", count: repeatedLineCount)
        let body = movedLinesFirst ? movedLines + repeatedLines : repeatedLines + movedLines
        return (["expand-root"] + body + ["expand-tail"]).joined(separator: "\n")
    }

    private func assertMovedAndEditedRows(
        _ rows: [DiffRow],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            rows.map(\.id),
            [
                id(1, 1), id(2, nil), id(3, nil), id(4, nil),
                id(5, 2), id(6, 3), id(7, 4),
                id(nil, 5), id(nil, 6), id(nil, 7), id(8, 8)
            ],
            file: file,
            line: line
        )
        XCTAssertEqual(
            rows.map(\.kind),
            [
                .unchanged, .removed, .removed, .removed,
                .unchanged, .unchanged, .unchanged,
                .added, .added, .added, .unchanged
            ],
            file: file,
            line: line
        )
    }

    private func assertOnlyExactMovedAnchors(
        _ movedLines: MovedLines,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(movedLines.leftToRightCount, 2, file: file, line: line)
        XCTAssertEqual(movedLines.rightToLeftCount, 2, file: file, line: line)
        XCTAssertEqual(movedLines.rightLine(forLeftLine: 2), 5, file: file, line: line)
        XCTAssertNil(movedLines.rightLine(forLeftLine: 3), file: file, line: line)
        XCTAssertEqual(movedLines.rightLine(forLeftLine: 4), 7, file: file, line: line)
        XCTAssertEqual(movedLines.leftLine(forRightLine: 5), 2, file: file, line: line)
        XCTAssertNil(movedLines.leftLine(forRightLine: 6), file: file, line: line)
        XCTAssertEqual(movedLines.leftLine(forRightLine: 7), 4, file: file, line: line)
    }

    private func id(_ left: Int?, _ right: Int?) -> DiffRow.ID {
        DiffRow.ID(leftNumber: left, rightNumber: right)
    }
}
