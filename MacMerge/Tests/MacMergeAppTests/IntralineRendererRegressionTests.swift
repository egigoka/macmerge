import AppKit
import Foundation
import MacMergeCore
import XCTest

@testable import MacMerge

@MainActor
final class IntralineRendererRegressionTests: XCTestCase {
    func testDirectionalRangesAreExactSortedDisjointUTF16Ranges() throws {
        let left = "p😀qOLD r𠮷s"
        let right = "p😃qNEW r吉s"
        let cases: [(String, String, [NSRange])] = [
            (
                left,
                right,
                [
                    NSRange(location: 1, length: 2),
                    NSRange(location: 4, length: 3),
                    NSRange(location: 9, length: 2),
                ]
            ),
            (
                right,
                left,
                [
                    NSRange(location: 1, length: 2),
                    NSRange(location: 4, length: 3),
                    NSRange(location: 9, length: 1),
                ]
            ),
        ]

        for (text, other, expected) in cases {
            let ranges = intralineDifferenceRanges(in: text, comparedWith: other)

            XCTAssertEqual(ranges, expected)
            try assertSortedDisjointUTF16(ranges, in: text)
        }
    }

    func testProductionRendererAppliesExactOrangeBackgroundWithoutSpill() throws {
        let left = "p😀qOLD r𠮷s"
        let right = "p😃qNEW r吉s"
        let row = DiffRow(
            left: DiffLine(number: 1, text: left),
            right: DiffLine(number: 1, text: right),
            kind: .modified
        )
        let table = AccessibilityCommandTestHarness.Table(rows: [row])
        defer { table.close() }

        let views = try mountedTextViews(in: table)
        let leftView = try XCTUnwrap(views.first { $0.string == left })
        let rightView = try XCTUnwrap(views.first { $0.string == right })

        try assertRenderedBackgrounds(
            [
                NSRange(location: 1, length: 2),
                NSRange(location: 4, length: 3),
                NSRange(location: 9, length: 2),
            ],
            in: leftView
        )
        try assertRenderedBackgrounds(
            [
                NSRange(location: 1, length: 2),
                NSRange(location: 4, length: 3),
                NSRange(location: 9, length: 1),
            ],
            in: rightView
        )
    }

    func testReusedProductionCellClearsHighlightsAndRetainsForeground() throws {
        let highlighted = DiffRow(
            left: DiffLine(number: 1, text: "before OLD value"),
            right: DiffLine(number: 1, text: "before NEW value"),
            kind: .modified
        )
        let rows = [highlighted] + (2...140).map { number in
            DiffRow(
                left: DiffLine(number: number, text: "plain reused left \(number)"),
                right: DiffLine(number: number, text: "plain reused right \(number)"),
                kind: .unchanged
            )
        }
        let table = AccessibilityCommandTestHarness.Table(rows: rows)
        defer { table.close() }

        let originalCell = try XCTUnwrap(table.visibleCells.first { $0.row == 0 })
        let originalViews = try mountedTextViews(in: table)
        let originalLeftView = try XCTUnwrap(
            originalViews.first { $0.string == highlighted.left?.text }
        )
        let originalRightView = try XCTUnwrap(
            originalViews.first { $0.string == highlighted.right?.text }
        )
        let originalLeftIdentity = ObjectIdentifier(originalLeftView)
        let originalRightIdentity = ObjectIdentifier(originalRightView)
        let leftTextColor = try XCTUnwrap(originalLeftView.textColor)
        let rightTextColor = try XCTUnwrap(originalRightView.textColor)
        let leftPermanentForeground = permanentForegroundColor(in: originalLeftView)
        let rightPermanentForeground = permanentForegroundColor(in: originalRightView)
        try assertForeground(
            textColor: leftTextColor,
            permanentColor: leftPermanentForeground,
            in: originalLeftView
        )
        try assertForeground(
            textColor: rightTextColor,
            permanentColor: rightPermanentForeground,
            in: originalRightView
        )
        XCTAssertNotNil(
            try XCTUnwrap(originalLeftView.layoutManager).temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: 7,
                effectiveRange: nil
            )
        )
        XCTAssertNotNil(
            try XCTUnwrap(originalRightView.layoutManager).temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: 7,
                effectiveRange: nil
            )
        )

        var reusedRowCandidate: Int?
        for targetRow in stride(from: 3, through: 138, by: 9) {
            table.scrollRowToVisible(targetRow)
            guard !table.visibleRows.contains(0) else { continue }
            if let reused = table.visibleCells.first(where: {
                $0.row != 0 && $0.identity == originalCell.identity
            }) {
                reusedRowCandidate = reused.row
                break
            }
        }

        let reusedRow = try XCTUnwrap(reusedRowCandidate, "Expected production table cell reuse")
        let reusedLeftText = try XCTUnwrap(rows[reusedRow].left?.text)
        let reusedRightText = try XCTUnwrap(rows[reusedRow].right?.text)
        let reusedViews = try mountedTextViews(in: table)
        let reusedLeftView = try XCTUnwrap(
            reusedViews.first { $0.string == reusedLeftText }
        )
        let reusedRightView = try XCTUnwrap(
            reusedViews.first { $0.string == reusedRightText }
        )
        XCTAssertEqual(ObjectIdentifier(reusedLeftView), originalLeftIdentity)
        XCTAssertEqual(ObjectIdentifier(reusedRightView), originalRightIdentity)
        try assertNoTemporaryColors(
            in: reusedLeftView,
            textColor: leftTextColor,
            permanentForeground: leftPermanentForeground
        )
        try assertNoTemporaryColors(
            in: reusedRightView,
            textColor: rightTextColor,
            permanentForeground: rightPermanentForeground
        )
    }

    func testModelMetadataMatchesMountedProductionEditorSelection() async throws {
        let model = await makeCurrentModel(
            left: "one OLD three STALE\n",
            right: "one new three fresh\n"
        )
        let row = try XCTUnwrap(model.rows.first { $0.kind == .modified })
        let ranges = [
            NSRange(location: 4, length: 3),
            NSRange(location: 14, length: 5),
        ]
        XCTAssertEqual(
            intralineDifferenceRanges(
                in: try XCTUnwrap(row.left?.text),
                comparedWith: try XCTUnwrap(row.right?.text)
            ),
            ranges
        )
        let table = AccessibilityCommandTestHarness.Table(rows: [row])
        defer { table.close() }
        let mountedLeftView = try XCTUnwrap(
            try mountedTextViews(in: table).first { $0.string == row.left?.text }
        )
        model.activateRow(row.id)
        model.activateSide(.left)

        var selectionRevision = model.lineDifferenceSelectionRevision
        var revealRevision = model.selectedDifferenceRevealRevision
        model.selectLineDifference()
        XCTAssertEqual(model.activeSide, .left)
        XCTAssertEqual(model.lineDifferenceSelectionDirection, .next)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, selectionRevision + 1)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision + 1)
        XCTAssertTrue(
            table.captureLineDifferenceSelection(
                rowID: row.id,
                side: model.activeSide,
                direction: model.lineDifferenceSelectionDirection
            )()
        )
        XCTAssertEqual(mountedLeftView.selectedRange(), ranges[0])

        selectionRevision = model.lineDifferenceSelectionRevision
        revealRevision = model.selectedDifferenceRevealRevision
        model.selectLineDifference()
        XCTAssertEqual(model.lineDifferenceSelectionDirection, .next)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, selectionRevision + 1)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision + 1)
        XCTAssertTrue(
            table.captureLineDifferenceSelection(
                rowID: row.id,
                side: model.activeSide,
                direction: model.lineDifferenceSelectionDirection
            )()
        )
        XCTAssertEqual(mountedLeftView.selectedRange(), ranges[1])

        selectionRevision = model.lineDifferenceSelectionRevision
        revealRevision = model.selectedDifferenceRevealRevision
        model.selectPreviousLineDifference()
        XCTAssertEqual(model.lineDifferenceSelectionDirection, .previous)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, selectionRevision + 1)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision + 1)
        XCTAssertTrue(
            table.captureLineDifferenceSelection(
                rowID: row.id,
                side: model.activeSide,
                direction: model.lineDifferenceSelectionDirection
            )()
        )
        XCTAssertEqual(mountedLeftView.selectedRange(), ranges[0])
    }

    private func assertSortedDisjointUTF16(
        _ ranges: [NSRange],
        in text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let utf16Length = (text as NSString).length
        var previousUpperBound = 0

        for range in ranges {
            XCTAssertGreaterThan(range.length, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(range.location, previousUpperBound, file: file, line: line)
            XCTAssertLessThanOrEqual(NSMaxRange(range), utf16Length, file: file, line: line)
            XCTAssertNotNil(Range(range, in: text), file: file, line: line)
            previousUpperBound = NSMaxRange(range)
        }
    }

    private func assertRenderedBackgrounds(
        _ expectedRanges: [NSRange],
        in textView: NSTextView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let layoutManager = try XCTUnwrap(textView.layoutManager, file: file, line: line)
        let utf16Length = (textView.string as NSString).length
        let expectedColor = NSColor.systemOrange.withAlphaComponent(0.48)
        let textColor = try XCTUnwrap(textView.textColor, file: file, line: line)
        let permanentForeground = permanentForegroundColor(in: textView)

        for index in 0..<utf16Length {
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            let background = layoutManager.temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: index,
                effectiveRange: &effectiveRange
            ) as? NSColor
            if let expectedRange = expectedRanges.first(where: { NSLocationInRange(index, $0) }) {
                let background = try XCTUnwrap(background, file: file, line: line)
                try assertColor(background, equals: expectedColor, file: file, line: line)
                XCTAssertEqual(effectiveRange, expectedRange, file: file, line: line)
            } else {
                XCTAssertNil(background, "Background spilled to UTF-16 index \(index)", file: file, line: line)
            }
        }
        try assertForeground(
            textColor: textColor,
            permanentColor: permanentForeground,
            in: textView,
            file: file,
            line: line
        )
    }

    private func assertNoTemporaryColors(
        in textView: NSTextView,
        textColor: NSColor,
        permanentForeground: NSColor?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let layoutManager = try XCTUnwrap(textView.layoutManager, file: file, line: line)
        try assertForeground(
            textColor: textColor,
            permanentColor: permanentForeground,
            in: textView,
            file: file,
            line: line
        )
        for index in 0..<(textView.string as NSString).length {
            XCTAssertNil(
                layoutManager.temporaryAttribute(
                    .backgroundColor,
                    atCharacterIndex: index,
                    effectiveRange: nil
                ),
                "Reused cell retained background at UTF-16 index \(index)",
                file: file,
                line: line
            )
        }
    }

    private func assertForeground(
        textColor expectedTextColor: NSColor,
        permanentColor expectedPermanentColor: NSColor?,
        in textView: NSTextView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try assertColor(
            try XCTUnwrap(textView.textColor, file: file, line: line),
            equals: expectedTextColor,
            file: file,
            line: line
        )
        let textStorage = try XCTUnwrap(textView.textStorage, file: file, line: line)
        let layoutManager = try XCTUnwrap(textView.layoutManager, file: file, line: line)
        for index in 0..<(textView.string as NSString).length {
            let permanentColor = textStorage.attribute(
                .foregroundColor,
                at: index,
                effectiveRange: nil
            ) as? NSColor
            if let expectedPermanentColor {
                let permanentColor = try XCTUnwrap(permanentColor, file: file, line: line)
                try assertColor(
                    permanentColor,
                    equals: expectedPermanentColor,
                    file: file,
                    line: line
                )
                try assertColor(
                    permanentColor,
                    equals: expectedTextColor,
                    file: file,
                    line: line
                )
            } else {
                XCTAssertNil(
                    permanentColor,
                    "Unexpected permanent foreground at UTF-16 index \(index)",
                    file: file,
                    line: line
                )
            }
            XCTAssertNil(
                layoutManager.temporaryAttribute(
                    .foregroundColor,
                    atCharacterIndex: index,
                    effectiveRange: nil
                ),
                "Unexpected temporary foreground at UTF-16 index \(index)",
                file: file,
                line: line
            )
        }
    }

    private func permanentForegroundColor(in textView: NSTextView) -> NSColor? {
        guard !textView.string.isEmpty else { return nil }
        return textView.textStorage?.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
    }

    private func assertColor(
        _ actual: NSColor,
        equals expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actualRGB = try XCTUnwrap(actual.usingColorSpace(.deviceRGB), file: file, line: line)
        let expectedRGB = try XCTUnwrap(expected.usingColorSpace(.deviceRGB), file: file, line: line)
        XCTAssertEqual(actualRGB.redComponent, expectedRGB.redComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actualRGB.greenComponent, expectedRGB.greenComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actualRGB.blueComponent, expectedRGB.blueComponent, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actualRGB.alphaComponent, expectedRGB.alphaComponent, accuracy: 0.0001, file: file, line: line)
    }

    private func mountedTextViews(
        in table: AccessibilityCommandTestHarness.Table
    ) throws -> [NSTextView] {
        let container = try XCTUnwrap(
            Mirror(reflecting: table).children
                .first(where: { $0.label == "container" })?.value as? NSView
        )
        return textViews(in: container)
    }

    private func textViews(in root: NSView) -> [NSTextView] {
        let current = (root as? NSTextView).map { [$0] } ?? []
        return current + root.subviews.flatMap(textViews(in:))
    }

    private func makeCurrentModel(left: String, right: String) async -> ComparisonModel {
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editText(left, on: .left)
        model.editText(right, on: .right)
        model.refresh()
        let idle = expectation(description: "Comparison model becomes idle")
        model.whenIdle { idle.fulfill() }
        await fulfillment(of: [idle], timeout: 5)
        XCTAssertTrue(model.isComparisonCurrent)
        return model
    }
}
