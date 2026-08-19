import AppKit
import Foundation
import MacMergeCore
import XCTest
@testable import MacMerge

@MainActor
final class IntralineConsistencyTests: XCTestCase {
    private let productionHighlightColor = NSColor.systemOrange.withAlphaComponent(0.48)

    func testSharedRangeHelpersReturnExactSortedDisjointDirectionalUTF16Ranges() throws {
        let left = "A👨‍👩‍👧‍👦B old C cafe\u{301} D𠮷E"
        let right = "A👩‍👩‍👧‍👦B new C cafe D吉E"
        let cases: [(text: String, other: String, expected: [NSRange])] = [
            (
                left,
                right,
                [
                    NSRange(location: 1, length: 11),
                    NSRange(location: 14, length: 3),
                    NSRange(location: 23, length: 2),
                    NSRange(location: 27, length: 2),
                ]
            ),
            (
                right,
                left,
                [
                    NSRange(location: 1, length: 11),
                    NSRange(location: 14, length: 3),
                    NSRange(location: 23, length: 1),
                    NSRange(location: 26, length: 1),
                ]
            ),
        ]

        for side in cases {
            let ranges = intralineDifferenceRanges(in: side.text, comparedWith: side.other)

            XCTAssertEqual(ranges, side.expected)
            try assertSortedDisjointUTF16Ranges(ranges, in: side.text)
            let firstRange = try XCTUnwrap(ranges.first)
            let lastRange = try XCTUnwrap(ranges.last)
            XCTAssertEqual(
                intralineDifferenceRange(in: side.text, comparedWith: side.other),
                firstRange
            )

            var selection = NSRange(location: 0, length: 0)
            for expected in side.expected {
                selection = try XCTUnwrap(
                    lineDifferenceRange(in: ranges, from: selection, direction: .next)
                )
                XCTAssertEqual(selection, expected)
            }
            XCTAssertEqual(
                lineDifferenceRange(in: ranges, from: firstRange, direction: .previous),
                lastRange
            )
        }
    }

    func testMountedProductionRendererUsesExactHighlightsAndCleansTemporaryAttributes() throws {
        let left = "A👨‍👩‍👧‍👦B old C cafe\u{301} D𠮷E"
        let right = "A👩‍👩‍👧‍👦B new C cafe D吉E"
        let leftRanges = [
            NSRange(location: 1, length: 11),
            NSRange(location: 14, length: 3),
            NSRange(location: 23, length: 2),
            NSRange(location: 27, length: 2),
        ]
        let rightRanges = [
            NSRange(location: 1, length: 11),
            NSRange(location: 14, length: 3),
            NSRange(location: 23, length: 1),
            NSRange(location: 26, length: 1),
        ]
        let row = DiffRow(
            left: DiffLine(number: 1, text: left),
            right: DiffLine(number: 1, text: right),
            kind: .modified
        )
        let table = AccessibilityCommandTestHarness.Table(
            rows: [row],
            selectedDifferenceID: row.id
        )
        defer { table.close() }
        let container = try XCTUnwrap(
            Mirror(reflecting: table).children
                .first(where: { $0.label == "container" })?.value as? NSView
        )
        let mountedTextViews = textViews(in: container)
        let mountedLeft = try XCTUnwrap(mountedTextViews.first { $0.string == left })
        let mountedRight = try XCTUnwrap(mountedTextViews.first { $0.string == right })

        try assertRenderedHighlights(leftRanges, in: mountedLeft)
        try assertRenderedHighlights(rightRanges, in: mountedRight)

        let editor = AccessibilityCommandTestHarness.LineDifferenceEditor(
            text: left,
            ranges: leftRanges
        )
        defer { editor.close() }
        let lineView = try XCTUnwrap(
            Mirror(reflecting: editor).children
                .first(where: { $0.label == "lineView" })?.value as? NSView
        )
        let editorTextView = try XCTUnwrap(textViews(in: lineView).first)
        let foregroundColor = editorTextView.textColor

        try assertRenderedHighlights(leftRanges, in: editorTextView)
        editor.reuse(text: left, ranges: [])
        XCTAssertEqual(editorTextView.textColor, foregroundColor)
        try assertNoTemporaryHighlights(in: editorTextView)
    }

    func testProductionEditorSelectionUsesExactRangesAndDoesNotChangeOtherEditor() throws {
        let leftRanges = [
            NSRange(location: 1, length: 11),
            NSRange(location: 14, length: 3),
            NSRange(location: 23, length: 2),
            NSRange(location: 27, length: 2),
        ]
        let rightRanges = [
            NSRange(location: 1, length: 11),
            NSRange(location: 14, length: 3),
            NSRange(location: 23, length: 1),
            NSRange(location: 26, length: 1),
        ]
        let leftEditor = AccessibilityCommandTestHarness.LineDifferenceEditor(
            text: "A👨‍👩‍👧‍👦B old C cafe\u{301} D𠮷E",
            ranges: leftRanges
        )
        let rightEditor = AccessibilityCommandTestHarness.LineDifferenceEditor(
            text: "A👩‍👩‍👧‍👦B new C cafe D吉E",
            ranges: rightRanges
        )
        defer {
            leftEditor.close()
            rightEditor.close()
        }
        let inactiveSelection = rightEditor.selectedRange

        for expected in leftRanges {
            leftEditor.select(.next)
            XCTAssertEqual(leftEditor.selectedRange, expected)
            XCTAssertEqual(rightEditor.selectedRange, inactiveSelection)
        }
        rightEditor.select(.previous)
        XCTAssertEqual(rightEditor.selectedRange, try XCTUnwrap(rightRanges.last))
        XCTAssertEqual(leftEditor.selectedRange, try XCTUnwrap(leftRanges.last))
    }

    // Existing seams expose model requests and production editor actions separately,
    // but do not bridge a model revision through DiffTableView.updateNSView.
    func testModelPublishesActiveSideDirectionAndMonotonicSelectionRequestMetadata() async throws {
        let leftLines = [
            "A👨‍👩‍👧‍👦B old C cafe\u{301} D𠮷E",
            "unchanged",
            "second LEFT hunk",
        ]
        let rightLines = [
            "A👩‍👩‍👧‍👦B new C cafe D吉E",
            "unchanged",
            "second RIGHT hunk",
        ]
        let model = try await makeModel(left: leftLines, right: rightLines)
        let modifiedRows = model.rows.filter { $0.kind == .modified }
        XCTAssertEqual(modifiedRows.count, 2)
        XCTAssertFalse(model.canSelectLineDifference)
        assertRequestDoesNotChange(model, performing: model.selectLineDifference)
        let expectedRanges: [Int: (left: [NSRange], right: [NSRange])] = [
            1: (
                left: [
                    NSRange(location: 1, length: 11),
                    NSRange(location: 14, length: 3),
                    NSRange(location: 23, length: 2),
                    NSRange(location: 27, length: 2),
                ],
                right: [
                    NSRange(location: 1, length: 11),
                    NSRange(location: 14, length: 3),
                    NSRange(location: 23, length: 1),
                    NSRange(location: 26, length: 1),
                ]
            ),
            3: (
                left: [NSRange(location: 7, length: 3)],
                right: [NSRange(location: 7, length: 4)]
            ),
        ]

        for row in modifiedRows {
            let lineNumber = try XCTUnwrap(row.left?.number)
            let rowExpectedRanges = try XCTUnwrap(expectedRanges[lineNumber])
            model.activateRow(row.id)
            for side in [ComparisonSide.left, .right] {
                model.activateSide(side)
                let text = try XCTUnwrap(side == .left ? row.left?.text : row.right?.text)
                let other = try XCTUnwrap(side == .left ? row.right?.text : row.left?.text)
                let sharedRanges = intralineDifferenceRanges(in: text, comparedWith: other)
                let expected = side == .left ? rowExpectedRanges.left : rowExpectedRanges.right

                XCTAssertEqual(sharedRanges, expected)
                XCTAssertTrue(model.canSelectLineDifference)
                try assertSortedDisjointUTF16Ranges(sharedRanges, in: text)

                let selectedID = model.selectedDifferenceID
                let revealRevision = model.selectedDifferenceRevealRevision
                let selectionRevision = model.lineDifferenceSelectionRevision
                model.selectLineDifference()
                XCTAssertEqual(model.activeSide, side)
                XCTAssertEqual(model.selectedDifferenceID, row.id)
                XCTAssertEqual(model.selectedDifferenceID, selectedID)
                XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision + 1)
                XCTAssertEqual(model.lineDifferenceSelectionRevision, selectionRevision + 1)
                XCTAssertEqual(model.lineDifferenceSelectionDirection, .next)

                let previousRevealRevision = model.selectedDifferenceRevealRevision
                let previousSelectionRevision = model.lineDifferenceSelectionRevision
                model.selectPreviousLineDifference()
                XCTAssertEqual(model.activeSide, side)
                XCTAssertEqual(model.selectedDifferenceID, row.id)
                XCTAssertEqual(model.selectedDifferenceRevealRevision, previousRevealRevision + 1)
                XCTAssertEqual(model.lineDifferenceSelectionRevision, previousSelectionRevision + 1)
                XCTAssertEqual(model.lineDifferenceSelectionDirection, .previous)
            }
        }

        let unchangedRow = try XCTUnwrap(model.rows.first { $0.kind == .unchanged })
        model.activateRow(unchangedRow.id)
        XCTAssertFalse(model.canSelectLineDifference)
        assertRequestDoesNotChange(model, performing: model.selectPreviousLineDifference)
    }

    private func assertSortedDisjointUTF16Ranges(
        _ ranges: [NSRange],
        in text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var previousUpperBound = 0

        for range in ranges {
            XCTAssertGreaterThanOrEqual(range.location, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(range.length, 0, file: file, line: line)
            guard range.location >= 0, range.length >= 0 else { continue }
            XCTAssertEqual(NSIntersectionRange(range, fullRange), range, file: file, line: line)
            XCTAssertNotNil(Range(range, in: text), file: file, line: line)
            XCTAssertGreaterThanOrEqual(
                range.location,
                previousUpperBound,
                "Ranges must be sorted and disjoint",
                file: file,
                line: line
            )
            previousUpperBound = NSMaxRange(range)
        }
    }

    private func assertRenderedHighlights(
        _ expectedRanges: [NSRange],
        in textView: NSTextView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let layoutManager = try XCTUnwrap(textView.layoutManager, file: file, line: line)
        let fullLength = (textView.string as NSString).length

        for expectedRange in expectedRanges {
            guard expectedRange.length > 0 else {
                XCTFail("Rendered highlight ranges must be nonempty", file: file, line: line)
                continue
            }
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            let color = try XCTUnwrap(
                layoutManager.temporaryAttribute(
                    .backgroundColor,
                    atCharacterIndex: expectedRange.location,
                    effectiveRange: &effectiveRange
                ) as? NSColor,
                file: file,
                line: line
            )
            assertColor(color, equals: productionHighlightColor, file: file, line: line)
            XCTAssertEqual(effectiveRange, expectedRange, file: file, line: line)
        }

        for index in 0..<fullLength {
            let expectedRange = expectedRanges.first { NSLocationInRange(index, $0) }
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            let color = layoutManager.temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: index,
                effectiveRange: &effectiveRange
            ) as? NSColor
            if let expectedRange {
                let color = try XCTUnwrap(color, file: file, line: line)
                assertColor(color, equals: productionHighlightColor, file: file, line: line)
                XCTAssertEqual(effectiveRange, expectedRange, file: file, line: line)
            } else {
                XCTAssertNil(color, "Highlight spilled to UTF-16 index \(index)", file: file, line: line)
            }
            XCTAssertNil(
                layoutManager.temporaryAttribute(
                    .foregroundColor,
                    atCharacterIndex: index,
                    effectiveRange: nil
                ),
                "Highlighting must preserve foreground attributes",
                file: file,
                line: line
            )
        }
    }

    private func assertNoTemporaryHighlights(
        in textView: NSTextView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let layoutManager = try XCTUnwrap(textView.layoutManager, file: file, line: line)
        let fullLength = (textView.string as NSString).length
        for index in 0..<fullLength {
            XCTAssertNil(
                layoutManager.temporaryAttribute(
                    .backgroundColor,
                    atCharacterIndex: index,
                    effectiveRange: nil
                ),
                "Reused editor retained highlight at UTF-16 index \(index)",
                file: file,
                line: line
            )
            XCTAssertNil(
                layoutManager.temporaryAttribute(
                    .foregroundColor,
                    atCharacterIndex: index,
                    effectiveRange: nil
                ),
                file: file,
                line: line
            )
        }
    }

    private func assertColor(
        _ actual: NSColor,
        equals expected: NSColor,
        file: StaticString,
        line: UInt
    ) {
        guard let actualRGB = actual.usingColorSpace(.deviceRGB),
              let expectedRGB = expected.usingColorSpace(.deviceRGB) else {
            XCTFail("Expected RGB-compatible highlight colors", file: file, line: line)
            return
        }
        XCTAssertEqual(actualRGB.redComponent, expectedRGB.redComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actualRGB.greenComponent, expectedRGB.greenComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actualRGB.blueComponent, expectedRGB.blueComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actualRGB.alphaComponent, 0.48, accuracy: 0.0001, file: file, line: line)
    }

    private func textViews(in root: NSView) -> [NSTextView] {
        let current = (root as? NSTextView).map { [$0] } ?? []
        return current + root.subviews.flatMap(textViews(in:))
    }

    private func assertRequestDoesNotChange(
        _ model: ComparisonModel,
        performing request: () -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let selectedID = model.selectedDifferenceID
        let revealRevision = model.selectedDifferenceRevealRevision
        let selectionRevision = model.lineDifferenceSelectionRevision
        let direction = model.lineDifferenceSelectionDirection

        request()

        XCTAssertEqual(model.selectedDifferenceID, selectedID, file: file, line: line)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision, file: file, line: line)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, selectionRevision, file: file, line: line)
        XCTAssertEqual(model.lineDifferenceSelectionDirection, direction, file: file, line: line)
    }

    private func makeModel(left: [String], right: [String]) async throws -> ComparisonModel {
        let leftURL = try temporaryFile(name: "left.txt", lines: left)
        let rightURL = try temporaryFile(name: "right.txt", lines: right)
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await fulfillment(of: [idleExpectation(for: model)], timeout: 5)
        return model
    }

    private func idleExpectation(for model: ComparisonModel) -> XCTestExpectation {
        let idle = expectation(description: "Comparison model becomes idle")
        model.whenIdle { idle.fulfill() }
        return idle
    }

    private func temporaryFile(name: String, lines: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }
}
