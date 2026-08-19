import Darwin
import Foundation
import MacMergeCore
import XCTest

final class DiffContextTests: XCTestCase {
    private static let invalidArgumentScenarioEnvironment =
        "MACMERGE_DIFF_CONTEXT_INVALID_ARGUMENT_SCENARIO"

    func testAllAndSupportedLineCountsProjectExpectedRanges() {
        XCTAssertEqual(DiffContextMode.supportedLineCounts, [0, 1, 3, 5, 7, 9])

        let rows = numberedRows(count: 21, differences: [10])
        let expectedRanges: [(Int, Range<Int>)] = [
            (0, 10..<11),
            (1, 9..<12),
            (3, 7..<14),
            (5, 5..<16),
            (7, 3..<18),
            (9, 1..<20)
        ]

        for (lineCount, expectedRange) in expectedRanges {
            let projection = DiffContext(lineCount: lineCount).project(rows)

            XCTAssertEqual(projection.hunks.map(\.sourceRange), [expectedRange], "Context: \(lineCount)")
            XCTAssertEqual(projection.rows.map(\.sourceIndex), Array(expectedRange), "Context: \(lineCount)")
            XCTAssertEqual(projection.visibleRows, Array(rows[expectedRange]), "Context: \(lineCount)")
        }

        let all = DiffContext(mode: .all).project(rows)
        XCTAssertTrue(all.isIdentity)
        XCTAssertEqual(all.hunks.map(\.sourceRange), [rows.indices])
        XCTAssertEqual(all.visibleRows, rows)
        XCTAssertTrue(all.gaps.isEmpty)

        let maximum = DiffContext(lineCount: Int.max).project(rows)
        XCTAssertTrue(maximum.isIdentity)
        XCTAssertEqual(maximum.hunks.map(\.sourceRange), [rows.indices])
    }

    func testAdjacentContextRangesMergeIntoOneHunk() {
        let rows = numberedRows(count: 15, differences: [4, 9])
        let projection = DiffContext(lineCount: 2).project(rows)

        XCTAssertEqual(projection.hunks.map(\.sourceRange), [2..<12])
        XCTAssertEqual(projection.hunks.map(\.projectedRange), [0..<10])
        XCTAssertEqual(projection.rows.map(\.sourceIndex), Array(2..<12))
        XCTAssertEqual(projection.gaps.map(\.sourceRange), [0..<2, 12..<15])
    }

    func testDisjointHunksTrackProjectedRangesAndSelections() {
        let rows = numberedRows(count: 12, differences: [2, 9])
        let projection = DiffContext(lineCount: 1).project(rows)

        XCTAssertEqual(
            projection.hunks,
            [
                DiffContextHunk(index: 0, sourceRange: 1..<4, projectedRange: 0..<3),
                DiffContextHunk(index: 1, sourceRange: 8..<11, projectedRange: 3..<6)
            ])
        XCTAssertEqual(projection.rows.map(\.sourceIndex), [1, 2, 3, 8, 9, 10])
        XCTAssertEqual(projection.gaps.map(\.sourceRange), [0..<1, 4..<8, 11..<12])
        XCTAssertEqual(
            projection.selection(forSourceIndex: 9),
            DiffContextSelectionMapping(
                sourceIndex: 9,
                projectedIndex: 4,
                itemIndex: 6,
                gapIndex: nil
            )
        )
        XCTAssertEqual(
            projection.selection(forRowID: rows[6].id),
            DiffContextSelectionMapping(
                sourceIndex: 6,
                projectedIndex: nil,
                itemIndex: 4,
                gapIndex: 1
            )
        )
    }

    func testPositiveInvertedContextSurvivesAllModeTransition() {
        let rows = numberedRows(count: 7, differences: [2, 3, 4])
        var context = DiffContext(lineCount: 1, isInverted: true)
        let limited = context.project(rows)

        XCTAssertEqual(limited.hunks.map(\.sourceRange), [0..<3, 4..<7])
        XCTAssertEqual(limited.hunks.map(\.projectedRange), [0..<3, 3..<6])
        XCTAssertEqual(limited.gaps.map(\.sourceRange), [3..<4])

        context.setMode(.all)
        XCTAssertTrue(context.isAll)
        XCTAssertTrue(context.isInverted)
        XCTAssertFalse(context.invert())
        XCTAssertTrue(context.project(rows).isIdentity)

        context.toggle()
        XCTAssertEqual(context.mode, .one)
        XCTAssertEqual(context.project(rows), limited)
    }

    func testInvertedProjectionEmitsExplicitOneSidedGapSpans() throws {
        let rows = [
            row(left: 1, right: 1, kind: .unchanged),
            row(left: 2, right: nil, kind: .removed),
            row(left: 3, right: nil, kind: .removed),
            row(left: 4, right: 2, kind: .unchanged),
            row(left: nil, right: 3, kind: .added),
            row(left: nil, right: 4, kind: .added),
            row(left: 5, right: 5, kind: .unchanged)
        ]
        let projection = DiffContext(lineCount: 0, isInverted: true).project(rows)

        XCTAssertEqual(projection.rows.map(\.sourceIndex), [0, 3, 6])
        XCTAssertEqual(projection.hunks.map(\.sourceRange), [0..<1, 3..<4, 6..<7])
        XCTAssertEqual(
            projection.items.map(\.id),
            [
                .row(sourceIndex: 0),
                .gap(sourceRange: 1..<3),
                .row(sourceIndex: 3),
                .gap(sourceRange: 4..<6),
                .row(sourceIndex: 6)
            ])

        let leftOnly = try XCTUnwrap(projection.gaps.first)
        XCTAssertEqual(leftOnly.sourceRange, 1..<3)
        XCTAssertEqual(leftOnly.insertionIndex, 1)
        XCTAssertEqual(leftOnly.omittedRowCount, 2)
        XCTAssertEqual(leftOnly.leftLines, DiffContextLineSpan(first: 2, last: 3))
        XCTAssertNil(leftOnly.rightLines)

        let rightOnly = try XCTUnwrap(projection.gaps.last)
        XCTAssertEqual(rightOnly.sourceRange, 4..<6)
        XCTAssertEqual(rightOnly.insertionIndex, 2)
        XCTAssertEqual(rightOnly.omittedRowCount, 2)
        XCTAssertNil(rightOnly.leftLines)
        XCTAssertEqual(rightOnly.rightLines, DiffContextLineSpan(first: 3, last: 4))
    }

    func testInvertedSelectionMapsVisibleEqualAndHiddenDifferenceRows() {
        let rows = numberedRows(count: 5, differences: [2])
        let projection = DiffContext(lineCount: 0, isInverted: true).project(rows)

        XCTAssertEqual(projection.hunks.map(\.sourceRange), [0..<2, 3..<5])
        XCTAssertEqual(
            projection.selection(forRowID: rows[1].id),
            DiffContextSelectionMapping(
                sourceIndex: 1,
                projectedIndex: 1,
                itemIndex: 1,
                gapIndex: nil
            )
        )
        XCTAssertEqual(
            projection.selection(forSourceIndex: 2),
            DiffContextSelectionMapping(
                sourceIndex: 2,
                projectedIndex: nil,
                itemIndex: 2,
                gapIndex: 0
            )
        )
        XCTAssertEqual(
            projection.selection(forSourceIndex: 3),
            DiffContextSelectionMapping(
                sourceIndex: 3,
                projectedIndex: 2,
                itemIndex: 3,
                gapIndex: nil
            )
        )
    }

    func testFullyOmittedProjectionReportsGapInsertionCountAndSpans() throws {
        let rows = numberedRows(count: 3, differences: [])
        let projection = DiffContext(lineCount: 0).project(rows)
        XCTAssertEqual(projection.gaps.count, 1)
        let gap = try XCTUnwrap(projection.gaps.first)

        XCTAssertEqual(gap.sourceRange, 0..<3)
        XCTAssertEqual(gap.insertionIndex, 0)
        XCTAssertEqual(gap.omittedRowCount, 3)
        XCTAssertEqual(gap.leftLines, DiffContextLineSpan(first: 1, last: 3))
        XCTAssertEqual(gap.rightLines, DiffContextLineSpan(first: 1, last: 3))
        XCTAssertEqual(projection.items, [.gap(gap)])
    }

    func testHiddenRowsIgnoreNonpositiveLineNumbers() throws {
        let rows = [
            row(left: 0, right: Int.min, kind: .unchanged),
            row(left: -1, right: -2, kind: .unchanged),
            row(left: 4, right: 7, kind: .unchanged),
            row(left: -3, right: 0, kind: .unchanged)
        ]
        let gap = try XCTUnwrap(DiffContext(lineCount: 0).project(rows).gaps.first)

        XCTAssertEqual(gap.sourceRange, rows.indices)
        XCTAssertEqual(gap.leftLines, DiffContextLineSpan(first: 4, last: 4))
        XCTAssertEqual(gap.rightLines, DiffContextLineSpan(first: 7, last: 7))

        let invalidOnly = [
            row(left: Int.min, right: 1, kind: .unchanged),
            row(left: 0, right: 2, kind: .unchanged),
            row(left: -1, right: 3, kind: .unchanged)
        ]
        let invalidOnlyGap = try XCTUnwrap(
            DiffContext(lineCount: 0).project(invalidOnly).gaps.first
        )
        XCTAssertNil(invalidOnlyGap.leftLines)
        XCTAssertEqual(invalidOnlyGap.rightLines, DiffContextLineSpan(first: 1, last: 3))
    }

    func testHiddenRowsNormalizeDescendingLineNumbers() throws {
        let rows = [
            row(left: 9, right: 30, kind: .unchanged),
            row(left: 2, right: 20, kind: .unchanged),
            row(left: 5, right: 10, kind: .unchanged)
        ]
        let gap = try XCTUnwrap(DiffContext(lineCount: 0).project(rows).gaps.first)

        XCTAssertEqual(gap.leftLines, DiffContextLineSpan(first: 2, last: 9))
        XCTAssertEqual(gap.rightLines, DiffContextLineSpan(first: 10, last: 30))
    }

    func testHiddenRowsHandleExtremeLineNumbersWithoutOverflow() throws {
        let rows = [
            row(left: Int.max, right: Int.min, kind: .unchanged),
            row(left: Int.min, right: Int.max, kind: .unchanged),
            row(left: 1, right: 1, kind: .unchanged)
        ]
        let gap = try XCTUnwrap(DiffContext(lineCount: 0).project(rows).gaps.first)

        XCTAssertEqual(gap.leftLines, DiffContextLineSpan(first: 1, last: Int.max))
        XCTAssertEqual(gap.rightLines, DiffContextLineSpan(first: 1, last: Int.max))
        XCTAssertEqual(gap.leftLines?.count, Int.max)
        XCTAssertEqual(gap.rightLines?.count, Int.max)
    }

    func testEmptyEqualAndDifferentInputsHaveStableProjections() throws {
        for context in [DiffContext(mode: .all), DiffContext(lineCount: 0)] {
            let empty = context.project([])
            XCTAssertEqual(empty.sourceRowCount, 0)
            XCTAssertTrue(empty.isIdentity)
            XCTAssertTrue(empty.rows.isEmpty)
            XCTAssertTrue(empty.gaps.isEmpty)
            XCTAssertTrue(empty.hunks.isEmpty)
            XCTAssertTrue(empty.items.isEmpty)
        }

        let equalRows = numberedRows(count: 4, differences: [])
        let equalAll = DiffContext(mode: .all).project(equalRows)
        let equalZero = DiffContext(lineCount: 0).project(equalRows)
        XCTAssertTrue(equalAll.isIdentity)
        XCTAssertTrue(equalZero.rows.isEmpty)
        XCTAssertEqual(equalZero.gaps.map(\.sourceRange), [0..<4])
        XCTAssertTrue(equalZero.hunks.isEmpty)
        XCTAssertEqual(equalZero.items.map(\.id), [.gap(sourceRange: 0..<4)])
        XCTAssertEqual(
            equalZero.selection(forRowID: equalRows[2].id),
            DiffContextSelectionMapping(
                sourceIndex: 2,
                projectedIndex: nil,
                itemIndex: 0,
                gapIndex: 0
            )
        )

        let differentRows = [
            row(left: 1, right: 1, kind: .modified),
            row(left: 2, right: nil, kind: .removed),
            row(left: nil, right: 2, kind: .added)
        ]
        let differentZero = DiffContext(lineCount: 0).project(differentRows)
        XCTAssertTrue(differentZero.isIdentity)
        XCTAssertEqual(differentZero.hunks.map(\.sourceRange), [0..<3])
        XCTAssertTrue(differentZero.gaps.isEmpty)

        let invertedEqual = DiffContext(lineCount: 0, isInverted: true).project(equalRows)
        XCTAssertTrue(invertedEqual.isIdentity)
        let invertedDifferent = DiffContext(lineCount: 0, isInverted: true).project(differentRows)
        XCTAssertTrue(invertedDifferent.rows.isEmpty)
        XCTAssertEqual(invertedDifferent.gaps.map(\.sourceRange), [0..<3])
    }

    func testToggleRemembersLimitedModeAndInvertOnlyAppliesWhenLimited() {
        var context = DiffContext(mode: .three)
        XCTAssertEqual(context.lineCount, 3)
        XCTAssertEqual(context.lastLimitedLineCount, 3)
        XCTAssertTrue(context.canInvert)

        context.toggle()
        XCTAssertTrue(context.isAll)
        XCTAssertFalse(context.canInvert)
        XCTAssertFalse(context.invert())
        XCTAssertFalse(context.isInverted)

        context.toggle()
        XCTAssertEqual(context.mode, .three)
        XCTAssertTrue(context.invert())
        XCTAssertTrue(context.isInverted)
        XCTAssertTrue(context.invert())
        XCTAssertFalse(context.isInverted)

        context.setMode(.one)
        context.setMode(.all)
        context.toggle()
        XCTAssertEqual(context.mode, .one)
        XCTAssertEqual(context.lastLimitedLineCount, 1)

        var initiallyAll = DiffContext(mode: .all, lastLimitedLineCount: 7)
        initiallyAll.toggle()
        XCTAssertEqual(initiallyAll.mode, .seven)
        initiallyAll.setLineCount(5)
        XCTAssertEqual(initiallyAll.mode, .five)
        initiallyAll.setLineCount(nil)
        initiallyAll.toggle()
        XCTAssertEqual(initiallyAll.mode, .five)
    }

    func testSelectionMappingCoversVisibleHiddenAndRowIDLookups() {
        let rows = numberedRows(count: 6, differences: [2])
        let projection = DiffContext(lineCount: 1).project(rows)

        XCTAssertEqual(
            projection.items.map(\.id),
            [
                .gap(sourceRange: 0..<1),
                .row(sourceIndex: 1),
                .row(sourceIndex: 2),
                .row(sourceIndex: 3),
                .gap(sourceRange: 4..<6)
            ])
        XCTAssertEqual(
            projection.selection(forSourceIndex: 2),
            DiffContextSelectionMapping(
                sourceIndex: 2,
                projectedIndex: 1,
                itemIndex: 2,
                gapIndex: nil
            )
        )
        XCTAssertEqual(
            projection.selection(forSourceIndex: 0),
            DiffContextSelectionMapping(
                sourceIndex: 0,
                projectedIndex: nil,
                itemIndex: 0,
                gapIndex: 0
            )
        )
        XCTAssertEqual(
            projection.selection(forSourceIndex: 5),
            DiffContextSelectionMapping(
                sourceIndex: 5,
                projectedIndex: nil,
                itemIndex: 4,
                gapIndex: 1
            )
        )

        XCTAssertEqual(projection.sourceIndex(forProjectedIndex: 0), 1)
        XCTAssertEqual(projection.projectedIndex(forSourceIndex: 3), 2)
        XCTAssertNil(projection.projectedIndex(forSourceIndex: 4))
        XCTAssertEqual(projection.sourceIndex(forRowID: rows[2].id), 2)
        XCTAssertEqual(projection.projectedIndex(forRowID: rows[2].id), 1)
        XCTAssertEqual(projection.itemIndex(forRowID: rows[0].id), 0)
        XCTAssertEqual(projection.selection(forRowID: rows[5].id), projection.selection(forSourceIndex: 5))
        XCTAssertNil(projection.selection(forRowID: DiffRow.ID(leftNumber: 99, rightNumber: 99)))
    }

    func testExtremeValidSpansAndRangesDoNotOverflow() {
        XCTAssertEqual(DiffContextLineSpan(first: 1, last: Int.max).count, Int.max)
        XCTAssertEqual(DiffContextLineSpan(first: Int.max, last: Int.max).count, 1)

        let gap = DiffContextGap(
            sourceRange: 0..<Int.max,
            insertionIndex: Int.max,
            leftLines: DiffContextLineSpan(first: 1, last: Int.max),
            rightLines: nil
        )
        XCTAssertEqual(gap.omittedRowCount, Int.max)
        XCTAssertEqual(gap.id, 0..<Int.max)

        let hunk = DiffContextHunk(
            index: Int.max,
            sourceRange: 0..<Int.max,
            projectedRange: 0..<Int.max
        )
        XCTAssertEqual(hunk.id, Int.max)
        XCTAssertEqual(hunk.sourceRange, 0..<Int.max)
    }

    func testHunkPreservesDistinctSourceAndProjectedRanges() {
        let hunk = DiffContextHunk(
            index: 3,
            sourceRange: 40..<44,
            projectedRange: 7..<11
        )

        XCTAssertEqual(hunk.id, 3)
        XCTAssertEqual(hunk.sourceRange, 40..<44)
        XCTAssertEqual(hunk.projectedRange, 7..<11)
    }

    func testInvalidExtremeIndicesReturnNilWithoutTrapping() {
        let rows = numberedRows(count: 3, differences: [1])
        let projection = DiffContext(lineCount: 0).project(rows)
        let extremeID = DiffRow.ID(leftNumber: Int.min, rightNumber: Int.max)

        for index in [Int.min, Int.max] {
            XCTAssertNil(projection.projectedIndex(forSourceIndex: index))
            XCTAssertNil(projection.sourceIndex(forProjectedIndex: index))
            XCTAssertNil(projection.itemIndex(forSourceIndex: index))
            XCTAssertNil(projection.selection(forSourceIndex: index))
        }
        XCTAssertNil(projection.sourceIndex(forRowID: extremeID))
        XCTAssertNil(projection.projectedIndex(forRowID: extremeID))
        XCTAssertNil(projection.itemIndex(forRowID: extremeID))
        XCTAssertNil(projection.selection(forRowID: extremeID))
    }

    func testSequentialEqualRowIDOptimizationRejectsExtremeIDsWithoutTrapping() {
        let rows = numberedRows(count: 3, differences: [])
        let projection = DiffContext(lineCount: 0).project(rows)

        for id in [
            DiffRow.ID(leftNumber: Int.min, rightNumber: Int.min),
            DiffRow.ID(leftNumber: Int.max, rightNumber: Int.max),
            DiffRow.ID(leftNumber: Int.min, rightNumber: Int.max)
        ] {
            XCTAssertNil(projection.sourceIndex(forRowID: id))
            XCTAssertNil(projection.projectedIndex(forRowID: id))
            XCTAssertNil(projection.itemIndex(forRowID: id))
            XCTAssertNil(projection.selection(forRowID: id))
        }
    }

    func testInvalidPublicArgumentsAreRejectedInIsolation() throws {
        if let scenario = ProcessInfo.processInfo.environment[
            Self.invalidArgumentScenarioEnvironment
        ] {
            switch scenario {
            case "span-minimum":
                _ = DiffContextLineSpan(first: Int.min, last: Int.max)
            case "span-reversed":
                _ = DiffContextLineSpan(first: Int.max, last: Int.min)
            case "gap-minimum":
                _ = DiffContextGap(
                    sourceRange: Range(uncheckedBounds: (lower: Int.min, upper: Int.max)),
                    insertionIndex: 0,
                    leftLines: nil,
                    rightLines: nil
                )
            case "hunk-index-minimum":
                _ = DiffContextHunk(
                    index: Int.min,
                    sourceRange: 0..<1,
                    projectedRange: 0..<1
                )
            case "hunk-source-minimum":
                _ = DiffContextHunk(
                    index: 0,
                    sourceRange: Range(uncheckedBounds: (lower: Int.min, upper: Int.max)),
                    projectedRange: 0..<1
                )
            case "hunk-projected-minimum":
                _ = DiffContextHunk(
                    index: 0,
                    sourceRange: 0..<1,
                    projectedRange: Range(uncheckedBounds: (lower: Int.min, upper: Int.max))
                )
            case "mode-line-count-minimum":
                _ = DiffContextMode(lineCount: Int.min)
            case "context-mode-minimum":
                _ = DiffContext(mode: .lines(Int.min))
            case "context-line-count-minimum":
                _ = DiffContext(lineCount: Int.min)
            case "context-last-limited-minimum":
                _ = DiffContext(mode: .all, lastLimitedLineCount: Int.min)
            case "set-mode-minimum":
                var context = DiffContext()
                context.setMode(.lines(Int.min))
            case "set-line-count-minimum":
                var context = DiffContext()
                context.setLineCount(Int.min)
            default:
                XCTFail("Unknown invalid-bound scenario: \(scenario)")
            }
            XCTFail("Invalid extreme bounds were accepted: \(scenario)")
            return
        }

        let scenarios = [
            ("span-minimum", "Diff context line span must use positive 1-based line numbers"),
            ("span-reversed", "Diff context line span must not be reversed"),
            ("gap-minimum", "Diff context gap source range must not be negative"),
            ("hunk-index-minimum", "Diff context hunk index must not be negative"),
            ("hunk-source-minimum", "Diff context hunk source range must not be negative"),
            ("hunk-projected-minimum", "Diff context hunk projected range must not be negative"),
            ("mode-line-count-minimum", "Diff context line count must not be negative"),
            ("context-mode-minimum", "Diff context line count must not be negative"),
            ("context-line-count-minimum", "Diff context line count must not be negative"),
            ("context-last-limited-minimum", "Diff context line count must not be negative"),
            ("set-mode-minimum", "Diff context line count must not be negative"),
            ("set-line-count-minimum", "Diff context line count must not be negative")
        ]
        for (scenario, diagnostic) in scenarios {
            try assertPreconditionRejects(scenario: scenario, expectedDiagnostic: diagnostic)
        }
    }

    func testSourceBackedInsertionAndDeletionFormSeparateHunks() throws {
        let rows = try LineDiff.compare(
            left: "alpha\ndelete\ncommon\nomega",
            right: "alpha\ncommon\ninsert\nomega"
        )
        let projection = DiffContext(lineCount: 0).project(rows)

        XCTAssertEqual(rows.map(\.kind), [.unchanged, .removed, .unchanged, .added, .unchanged])
        XCTAssertEqual(projection.hunks.map(\.sourceRange), [1..<2, 3..<4])
        XCTAssertEqual(projection.hunks.map(\.projectedRange), [0..<1, 1..<2])
        XCTAssertEqual(projection.gaps.map(\.sourceRange), [0..<1, 2..<3, 4..<5])
        XCTAssertEqual(projection.visibleRows.map(\.left?.text), ["delete", nil])
        XCTAssertEqual(projection.visibleRows.map(\.right?.text), [nil, "insert"])
    }

    private func numberedRows(count: Int, differences: Set<Int>) -> [DiffRow] {
        (0..<count).map { index in
            let number = index + 1
            return row(
                left: number,
                right: number,
                kind: differences.contains(index) ? .modified : .unchanged
            )
        }
    }

    private func row(left: Int?, right: Int?, kind: DiffKind) -> DiffRow {
        DiffRow(
            left: left.map { DiffLine(number: $0, text: "L\($0)") },
            right: right.map { DiffLine(number: $0, text: "R\($0)") },
            kind: kind
        )
    }

    private func assertPreconditionRejects(
        scenario: String,
        expectedDiagnostic: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let diagnosticsURL = FileManager.default.temporaryDirectory.appending(
            path: "MacMergeDiffContextInvalidBounds-\(UUID().uuidString).log"
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: diagnosticsURL.path, contents: nil))
        let diagnostics = try FileHandle(forUpdating: diagnosticsURL)
        defer {
            try? diagnostics.close()
            try? FileManager.default.removeItem(at: diagnosticsURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [
            "-XCTest",
            "MacMergeCoreTests.DiffContextTests/testInvalidPublicArgumentsAreRejectedInIsolation",
            Bundle(for: Self.self).bundleURL.path
        ]
        var environment = ProcessInfo.processInfo.environment
        environment[Self.invalidArgumentScenarioEnvironment] = scenario
        process.environment = environment
        process.standardOutput = diagnostics
        process.standardError = diagnostics
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        guard terminated.wait(timeout: .now() + .seconds(5)) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            XCTFail("Invalid-bound child exceeded timeout: \(scenario)", file: file, line: line)
            return
        }
        process.waitUntilExit()
        try diagnostics.synchronize()
        try diagnostics.seek(toOffset: 0)
        let output = try diagnostics.readToEnd() ?? Data()
        let diagnosticText = String(decoding: output, as: UTF8.self)

        XCTAssertEqual(process.terminationReason, .uncaughtSignal, file: file, line: line)
        XCTAssertTrue(
            [SIGABRT, SIGILL, SIGTRAP].contains(process.terminationStatus),
            "Unexpected fatal signal \(process.terminationStatus): \(diagnosticText)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            diagnosticText.contains(expectedDiagnostic),
            "Unexpected precondition diagnostic: \(diagnosticText)",
            file: file,
            line: line
        )
    }
}
