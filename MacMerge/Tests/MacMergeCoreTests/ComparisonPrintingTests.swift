import Foundation
import XCTest

@testable import MacMergeCore

final class ComparisonPrintingTests: XCTestCase {
    func testPageSetupIntersectsMarginsAndImageableBoundsInBothOrientations() throws {
        let portrait = try ComparisonPrintPageSetup(
            paperBounds: ComparisonPrintRect(x: 0, y: 0, width: 612, height: 792),
            imageableBounds: ComparisonPrintRect(x: 18, y: 20, width: 576, height: 750),
            orientation: .portrait,
            margins: ComparisonPrintMargins(top: 72, leading: 54, bottom: 36, trailing: 90),
            scale: 1.25
        )

        XCTAssertEqual(portrait.printableBounds, ComparisonPrintRect(x: 54, y: 36, width: 468, height: 684))
        XCTAssertEqual(portrait.orientation, .portrait)
        XCTAssertEqual(portrait.scale, 1.25)

        let landscape = try ComparisonPrintPageSetup(
            paperBounds: ComparisonPrintRect(x: 10, y: 20, width: 120, height: 80),
            imageableBounds: ComparisonPrintRect(x: 10, y: 20, width: 120, height: 80),
            orientation: .landscape,
            margins: ComparisonPrintMargins(5),
            scale: 0.5
        )

        XCTAssertEqual(landscape.printableBounds, ComparisonPrintRect(x: 15, y: 25, width: 110, height: 70))
        XCTAssertEqual(landscape.orientation, .landscape)
        XCTAssertEqual(ComparisonPrintOrientation.allCases, [.portrait, .landscape])
    }

    func testPageSetupClipsPrintableBoundsToRestrictiveImageableBounds() throws {
        let setup = try ComparisonPrintPageSetup(
            paperBounds: ComparisonPrintRect(x: 0, y: 0, width: 100, height: 120),
            imageableBounds: ComparisonPrintRect(x: 20, y: 30, width: 60, height: 50),
            margins: ComparisonPrintMargins(10)
        )

        XCTAssertEqual(setup.printableBounds, ComparisonPrintRect(x: 20, y: 30, width: 60, height: 50))
    }

    func testScaleChangesContentMetricsWithoutChangingPaperSpaceBounds() throws {
        let document = twoPaneDocument(rowCount: 1)
        let layout = compactLayout(characterWidth: 5, lineHeight: 10)
        let unscaledSetup = try squarePageSetup(side: 100, scale: 1)
        let scaledSetup = try squarePageSetup(side: 100, scale: 2)

        let unscaled = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: unscaledSetup,
            layout: layout,
            headerFooter: noHeaderFooter
        )
        let scaled = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: scaledSetup,
            layout: layout,
            headerFooter: noHeaderFooter
        )

        XCTAssertEqual(unscaled.charactersPerLine, 9)
        XCTAssertEqual(scaled.charactersPerLine, 4)
        XCTAssertEqual(unscaled.pages[0].printableBounds, scaled.pages[0].printableBounds)
        XCTAssertEqual(unscaled.pages[0].paneContentBounds, scaled.pages[0].paneContentBounds)
        XCTAssertEqual(unscaled.pages[0].rowFragments[0].frame.height, 10)
        XCTAssertEqual(scaled.pages[0].rowFragments[0].frame.height, 40)
    }

    func testScaledNonzeroMetricsProduceExactPaperSpaceBounds() throws {
        let setup = try ComparisonPrintPageSetup(
            paperBounds: ComparisonPrintRect(x: 0, y: 0, width: 120, height: 140),
            imageableBounds: ComparisonPrintRect(x: 10, y: 20, width: 100, height: 100),
            margins: ComparisonPrintMargins(0),
            scale: 2
        )
        let layout = compactLayout(
            characterWidth: 2,
            lineHeight: 3,
            horizontalCellPadding: 1,
            verticalCellPadding: 2,
            paneSpacing: 4,
            lineNumberColumnWidth: 6,
            paneTitleHeight: 5
        )

        let plan = try ComparisonPrintPlanner.planPreview(
            document: twoPaneDocument(rowCount: 1),
            pageSetup: setup,
            layout: layout,
            headerFooter: noHeaderFooter
        )
        let page = try XCTUnwrap(plan.pages.first)

        XCTAssertEqual(plan.layout, layout)
        XCTAssertEqual(plan.charactersPerLine, 7)
        XCTAssertEqual(page.printableBounds, ComparisonPrintRect(x: 10, y: 20, width: 100, height: 100))
        XCTAssertEqual(
            page.paneHeaderBounds,
            [
                ComparisonPrintRect(x: 10, y: 110, width: 46, height: 10),
                ComparisonPrintRect(x: 64, y: 110, width: 46, height: 10)
            ])
        XCTAssertEqual(
            page.paneContentBounds,
            [
                ComparisonPrintRect(x: 10, y: 20, width: 46, height: 90),
                ComparisonPrintRect(x: 64, y: 20, width: 46, height: 90)
            ])
        XCTAssertEqual(page.rowFragments.map(\.frame), [ComparisonPrintRect(x: 10, y: 96, width: 100, height: 14)])
    }

    func testPageSetupRejectsInvalidGeometryMarginsOrientationAndScale() throws {
        let portraitPaper = ComparisonPrintRect(x: 0, y: 0, width: 100, height: 120)
        let fullPortraitImageable = portraitPaper

        assertPrintingError(.nonFinitePageGeometry) {
            try ComparisonPrintPageSetup(
                paperBounds: ComparisonPrintRect(x: .infinity, y: 0, width: 100, height: 120),
                imageableBounds: fullPortraitImageable
            )
        }
        assertPrintingError(.nonFinitePageGeometry) {
            try ComparisonPrintPageSetup(
                paperBounds: ComparisonPrintRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 120),
                imageableBounds: fullPortraitImageable
            )
        }
        assertPrintingError(.invalidPaperBounds) {
            try ComparisonPrintPageSetup(
                paperBounds: ComparisonPrintRect(x: 0, y: 0, width: 0, height: 120),
                imageableBounds: fullPortraitImageable
            )
        }
        assertPrintingError(.orientationDoesNotMatchPaperBounds) {
            try ComparisonPrintPageSetup(
                paperBounds: portraitPaper,
                imageableBounds: fullPortraitImageable,
                orientation: .landscape
            )
        }
        assertPrintingError(.invalidImageableBounds) {
            try ComparisonPrintPageSetup(
                paperBounds: portraitPaper,
                imageableBounds: ComparisonPrintRect(x: 0, y: 0, width: 0, height: 120)
            )
        }
        assertPrintingError(.imageableBoundsOutsidePaper) {
            try ComparisonPrintPageSetup(
                paperBounds: portraitPaper,
                imageableBounds: ComparisonPrintRect(x: -1, y: 0, width: 100, height: 120)
            )
        }
        assertPrintingError(.nonFiniteMargins) {
            try ComparisonPrintPageSetup(
                paperBounds: portraitPaper,
                imageableBounds: fullPortraitImageable,
                margins: ComparisonPrintMargins(top: .nan, leading: 0, bottom: 0, trailing: 0)
            )
        }
        assertPrintingError(.negativeMargins) {
            try ComparisonPrintPageSetup(
                paperBounds: portraitPaper,
                imageableBounds: fullPortraitImageable,
                margins: ComparisonPrintMargins(top: 0, leading: -1, bottom: 0, trailing: 0)
            )
        }
        assertPrintingError(.marginsExcludePrintableArea) {
            try ComparisonPrintPageSetup(
                paperBounds: portraitPaper,
                imageableBounds: fullPortraitImageable,
                margins: ComparisonPrintMargins(top: 60, leading: 50, bottom: 60, trailing: 50)
            )
        }
        for scale in [CGFloat.nan, 0, ComparisonPrintPageSetup.minimumScale.nextDown, ComparisonPrintPageSetup.maximumScale.nextUp, .infinity] {
            assertPrintingError(.invalidScale) {
                try ComparisonPrintPageSetup(
                    paperBounds: portraitPaper,
                    imageableBounds: fullPortraitImageable,
                    scale: scale
                )
            }
        }

        XCTAssertNoThrow(
            try ComparisonPrintPageSetup(
                paperBounds: portraitPaper,
                imageableBounds: fullPortraitImageable,
                scale: ComparisonPrintPageSetup.minimumScale
            )
        )
        XCTAssertNoThrow(
            try ComparisonPrintPageSetup(
                paperBounds: portraitPaper,
                imageableBounds: fullPortraitImageable,
                scale: ComparisonPrintPageSetup.maximumScale
            )
        )
    }

    func testTwoAndThreePaneDocumentsPaginateWithStableGeometry() throws {
        for paneCount in [2, 3] {
            let pageWidth: CGFloat = paneCount == 2 ? 100 : 120
            let setup = try ComparisonPrintPageSetup(
                paperBounds: ComparisonPrintRect(x: 0, y: 0, width: pageWidth, height: 120),
                imageableBounds: ComparisonPrintRect(x: 0, y: 0, width: pageWidth, height: 120),
                margins: ComparisonPrintMargins(top: 10, leading: 0, bottom: 10, trailing: 0)
            )
            let document = document(paneCount: paneCount, rowCount: 21)
            let plan = try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter
            )

            XCTAssertEqual(plan.totalPageCount, 3, "paneCount=\(paneCount)")
            XCTAssertEqual(plan.pages.map(\.pageNumber), [1, 2, 3], "paneCount=\(paneCount)")
            XCTAssertEqual(plan.pages.map { $0.rowFragments.count }, [10, 10, 1], "paneCount=\(paneCount)")
            XCTAssertEqual(plan.pages.flatMap(\.rowFragments).map(\.sourceRowIndex), Array(0..<21), "paneCount=\(paneCount)")
            for page in plan.pages {
                XCTAssertEqual(page.paneHeaderBounds.count, paneCount)
                XCTAssertEqual(page.paneContentBounds.count, paneCount)
                XCTAssertTrue(page.rowFragments.allSatisfy { $0.cells.count == paneCount })
                XCTAssertTrue(page.rowFragments.allSatisfy { $0.frame.width == pageWidth })
            }
        }
    }

    func testThreePaneFramesAreExactAndRowsDoNotOverlapVertically() throws {
        let setup = try squarePageSetup(side: 120)
        let layout = compactLayout(
            verticalCellPadding: 2,
            paneSpacing: 3,
            paneTitleHeight: 10
        )
        let plan = try ComparisonPrintPlanner.planPreview(
            document: document(paneCount: 3, rowCount: 3),
            pageSetup: setup,
            layout: layout,
            headerFooter: noHeaderFooter
        )
        let page = try XCTUnwrap(plan.pages.first)

        XCTAssertEqual(
            page.paneHeaderBounds,
            [
                ComparisonPrintRect(x: 0, y: 110, width: 38, height: 10),
                ComparisonPrintRect(x: 41, y: 110, width: 38, height: 10),
                ComparisonPrintRect(x: 82, y: 110, width: 38, height: 10)
            ])
        XCTAssertEqual(
            page.paneContentBounds,
            [
                ComparisonPrintRect(x: 0, y: 0, width: 38, height: 110),
                ComparisonPrintRect(x: 41, y: 0, width: 38, height: 110),
                ComparisonPrintRect(x: 82, y: 0, width: 38, height: 110)
            ])
        XCTAssertEqual(
            page.rowFragments.map(\.frame),
            [
                ComparisonPrintRect(x: 0, y: 96, width: 120, height: 14),
                ComparisonPrintRect(x: 0, y: 82, width: 120, height: 14),
                ComparisonPrintRect(x: 0, y: 68, width: 120, height: 14)
            ])
        for (upperRow, lowerRow) in zip(page.rowFragments, page.rowFragments.dropFirst()) {
            XCTAssertLessThanOrEqual(lowerRow.frame.maxY, upperRow.frame.minY)
        }
    }

    func testWrappingExpandsTabsUsesUnicodeScalarsAndAlignsCells() throws {
        let setup = try ComparisonPrintPageSetup(
            paperBounds: ComparisonPrintRect(x: 0, y: 0, width: 20, height: 100),
            imageableBounds: ComparisonPrintRect(x: 0, y: 0, width: 20, height: 100),
            margins: ComparisonPrintMargins(0)
        )
        let document = ComparisonPrintDocument(
            title: "Wrap",
            paneTitles: ["Left", "Right"],
            rows: [
                ComparisonPrintRow(
                    left: ComparisonPrintCell(lineNumber: 7, text: "abcdefghi\tZ\r\nline"),
                    right: ComparisonPrintCell(lineNumber: 8, text: "🙂e\u{301}")
                )
            ]
        )

        let plan = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: compactLayout(),
            headerFooter: noHeaderFooter
        )
        let fragment = try XCTUnwrap(plan.pages.first?.rowFragments.first)

        XCTAssertEqual(plan.charactersPerLine, 9)
        XCTAssertEqual(fragment.visualLineRange, 0..<3)
        XCTAssertEqual(fragment.cells[0].lines, ["abcdefghi", "    Z", "line"])
        XCTAssertEqual(fragment.cells[1].lines, ["🙂e\u{301}", "", ""])
        XCTAssertEqual(fragment.cells.map(\.lineNumber), [7, 8])
        XCTAssertFalse(fragment.isContinuation)
        XCTAssertFalse(fragment.isContinued)
    }

    func testTabExpansionUsesNextStopFromNonzeroColumn() throws {
        let plan = try ComparisonPrintPlanner.planPreview(
            document: ComparisonPrintDocument(
                title: "Tab",
                paneTitles: ["Left", "Right"],
                rows: [
                    ComparisonPrintRow(
                        left: ComparisonPrintCell(text: "ab\tZ"),
                        right: ComparisonPrintCell(text: "")
                    )
                ]
            ),
            pageSetup: squarePageSetup(side: 20),
            layout: compactLayout(),
            headerFooter: noHeaderFooter
        )
        let fragment = try XCTUnwrap(plan.pages.first?.rowFragments.first)

        XCTAssertEqual(plan.charactersPerLine, 10)
        XCTAssertEqual(fragment.cells[0].lines, ["ab  Z"])
    }

    func testCombiningScalarsWrapAtExactColumnBoundary() throws {
        let bounds = ComparisonPrintRect(x: 0, y: 0, width: 4, height: 20)
        let setup = try ComparisonPrintPageSetup(
            paperBounds: bounds,
            imageableBounds: bounds,
            margins: ComparisonPrintMargins(0)
        )
        let plan = try ComparisonPrintPlanner.planPreview(
            document: ComparisonPrintDocument(
                title: "Combining",
                paneTitles: ["Left", "Right"],
                rows: [
                    ComparisonPrintRow(
                        left: ComparisonPrintCell(text: "e\u{301}x\u{301}"),
                        right: ComparisonPrintCell(text: "")
                    )
                ]
            ),
            pageSetup: setup,
            layout: compactLayout(),
            headerFooter: noHeaderFooter
        )
        let fragment = try XCTUnwrap(plan.pages.first?.rowFragments.first)

        XCTAssertEqual(plan.charactersPerLine, 2)
        XCTAssertEqual(fragment.visualLineRange, 0..<2)
        XCTAssertEqual(fragment.cells[0].lines, ["e\u{301}", "x\u{301}"])
        XCTAssertEqual(fragment.cells[1].lines, ["", ""])
    }

    func testOversizedRowSplitsAcrossPagesWithContinuationMetadata() throws {
        let setup = try squarePageSetup(side: 20)
        let document = ComparisonPrintDocument(
            title: "Split",
            paneTitles: ["Left", "Right"],
            rows: [
                ComparisonPrintRow(
                    left: ComparisonPrintCell(lineNumber: 42, text: "a\nb\nc\nd\ne"),
                    right: ComparisonPrintCell(lineNumber: 84, text: "one")
                )
            ]
        )

        let plan = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: compactLayout(),
            headerFooter: noHeaderFooter
        )
        let fragments = plan.pages.flatMap(\.rowFragments)

        XCTAssertEqual(plan.totalPageCount, 3)
        XCTAssertEqual(fragments.map(\.visualLineRange), [0..<2, 2..<4, 4..<5])
        XCTAssertEqual(fragments.map { $0.cells[0].lines }.flatMap { $0 }, ["a", "b", "c", "d", "e"])
        XCTAssertEqual(fragments.map { $0.cells[1].lines }.flatMap { $0 }, ["one", "", "", "", ""])
        XCTAssertEqual(fragments.map { $0.cells[0].lineNumber }, [42, nil, nil])
        XCTAssertEqual(fragments.map { $0.cells[1].lineNumber }, [84, nil, nil])
        XCTAssertEqual(fragments.map(\.isContinuation), [false, true, true])
        XCTAssertEqual(fragments.map(\.isContinued), [true, true, false])
        XCTAssertEqual(
            fragments.map(\.frame),
            [
                ComparisonPrintRect(x: 0, y: 0, width: 20, height: 20),
                ComparisonPrintRect(x: 0, y: 0, width: 20, height: 20),
                ComparisonPrintRect(x: 0, y: 10, width: 20, height: 10)
            ])
    }

    func testCompleteRowMovesToNextPartiallyFilledPageInsteadOfSplitting() throws {
        let document = ComparisonPrintDocument(
            title: "Move",
            paneTitles: ["Left", "Right"],
            rows: [
                ComparisonPrintRow(
                    left: ComparisonPrintCell(text: "first"),
                    right: ComparisonPrintCell(text: "first")
                ),
                ComparisonPrintRow(
                    left: ComparisonPrintCell(text: "a\nb\nc\nd"),
                    right: ComparisonPrintCell(text: "one\ntwo\nthree\nfour")
                )
            ]
        )

        let plan = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: squarePageSetup(side: 40),
            layout: compactLayout(),
            headerFooter: noHeaderFooter
        )

        XCTAssertEqual(plan.totalPageCount, 2)
        XCTAssertEqual(plan.pages.map { $0.rowFragments.map(\.sourceRowIndex) }, [[0], [1]])
        XCTAssertEqual(plan.pages[0].rowFragments[0].frame, ComparisonPrintRect(x: 0, y: 30, width: 40, height: 10))
        XCTAssertEqual(plan.pages[1].rowFragments[0].frame, ComparisonPrintRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertEqual(plan.pages[1].rowFragments[0].visualLineRange, 0..<4)
        XCTAssertFalse(plan.pages[1].rowFragments[0].isContinuation)
        XCTAssertFalse(plan.pages[1].rowFragments[0].isContinued)
    }

    func testHeadersFootersPageRangeAndPreviewMetadataUseCompletePageCount() throws {
        let setup = try squarePageSetup(side: 100)
        let layout = compactLayout(paneTitleHeight: 10)
        let document = twoPaneDocument(title: "Comparison", rowCount: 15)
        let range = try ComparisonPrintPageRange(firstPage: 2, lastPage: 2)

        let preview = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: layout,
            headerFooter: ComparisonPrintHeaderFooter(
                header: .documentTitle,
                footer: .pageNumberAndCount,
                bandHeight: 10
            ),
            pageRange: range
        )
        let page = try XCTUnwrap(preview.pages.first)

        XCTAssertEqual(preview.title, "Comparison")
        XCTAssertEqual(preview.paneTitles, ["Left", "Right"])
        XCTAssertEqual(preview.pageSetup, setup)
        XCTAssertEqual(preview.layout.lineNumberColumnWidth, 2)
        XCTAssertEqual(preview.totalPageCount, 3)
        XCTAssertEqual(preview.selectedPageRange, range)
        XCTAssertEqual(preview.charactersPerLine, 48)
        XCTAssertEqual(preview.pages.count, 1)
        XCTAssertEqual(page.id, 2)
        XCTAssertEqual(page.pageNumber, 2)
        XCTAssertEqual(page.headerText, "Comparison")
        XCTAssertEqual(page.footerText, "2 of 3")
        XCTAssertEqual(page.headerBounds, ComparisonPrintRect(x: 0, y: 90, width: 100, height: 10))
        XCTAssertEqual(page.footerBounds, ComparisonPrintRect(x: 0, y: 0, width: 100, height: 10))
        XCTAssertEqual(
            page.paneHeaderBounds,
            [
                ComparisonPrintRect(x: 0, y: 80, width: 50, height: 10),
                ComparisonPrintRect(x: 50, y: 80, width: 50, height: 10)
            ])
        XCTAssertEqual(
            page.paneContentBounds,
            [
                ComparisonPrintRect(x: 0, y: 10, width: 50, height: 70),
                ComparisonPrintRect(x: 50, y: 10, width: 50, height: 70)
            ])
        XCTAssertEqual(page.rowFragments.map(\.sourceRowIndex), Array(7..<14))

        let customLabels = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: layout,
            headerFooter: ComparisonPrintHeaderFooter(
                header: .text("Confidential"),
                footer: .pageNumber,
                bandHeight: 10
            )
        )
        XCTAssertEqual(customLabels.pages.map(\.headerText), ["Confidential", "Confidential", "Confidential"])
        XCTAssertEqual(customLabels.pages.map(\.footerText), ["1", "2", "3"])
    }

    func testSelectedPageRangeDoesNotChargeUnselectedOutputItems() throws {
        let setup = try squarePageSetup(side: 100)
        let document = twoPaneDocument(title: "", rowCount: 20)
        let limits = ComparisonPrintLimits(maximumOutputItems: 54)

        assertPrintingError(.tooManyOutputItems(maximum: 54)) {
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: limits
            )
        }

        let selected = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: compactLayout(),
            headerFooter: noHeaderFooter,
            pageRange: ComparisonPrintPageRange(firstPage: 2, lastPage: 2),
            limits: limits
        )

        XCTAssertEqual(selected.totalPageCount, 2)
        XCTAssertEqual(selected.pages.map(\.pageNumber), [2])
        XCTAssertEqual(selected.pages[0].rowFragments.map(\.sourceRowIndex), Array(10..<20))
    }

    func testRetainedOutputItemLimitAcceptsExactCountAndRejectsOneBelow() throws {
        let setup = try squarePageSetup(side: 20)
        let document = ComparisonPrintDocument(
            title: "",
            paneTitles: ["", ""],
            rows: [
                ComparisonPrintRow(
                    left: ComparisonPrintCell(text: ""),
                    right: ComparisonPrintCell(text: "")
                )
            ]
        )

        let exact = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: compactLayout(),
            headerFooter: noHeaderFooter,
            limits: ComparisonPrintLimits(maximumOutputItems: 9)
        )

        XCTAssertEqual(exact.pages.count, 1)
        XCTAssertEqual(exact.pages[0].rowFragments.count, 1)
        assertPrintingError(.tooManyOutputItems(maximum: 8)) {
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: ComparisonPrintLimits(maximumOutputItems: 8)
            )
        }
    }

    func testLineNumberColumnExpandsDynamicallyThroughIntMax() throws {
        let setup = try squarePageSetup(side: 200)
        let layout = compactLayout(characterWidth: 2, lineNumberColumnWidth: 2)
        let document = ComparisonPrintDocument(
            title: "Numbers",
            paneTitles: ["Left", "Right"],
            rows: [
                ComparisonPrintRow(
                    left: ComparisonPrintCell(lineNumber: Int.max, text: "maximum"),
                    right: ComparisonPrintCell(lineNumber: 1, text: "one")
                )
            ]
        )

        let plan = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: layout,
            headerFooter: noHeaderFooter
        )
        let expectedWidth = CGFloat(String(Int.max).utf8.count) * layout.characterWidth
        let expectedCharactersPerLine = Int(((100 - expectedWidth) / layout.characterWidth).rounded(.down))

        XCTAssertEqual(plan.layout.lineNumberColumnWidth, expectedWidth)
        XCTAssertEqual(plan.charactersPerLine, expectedCharactersPerLine)
        XCTAssertEqual(plan.pages[0].rowFragments[0].cells.map(\.lineNumber), [Int.max, 1])
    }

    func testIntMaxErrorDescriptionsUseOverflowSafeOneBasedIndices() {
        let onePastIntMax = String(UInt(Int.max) + 1)

        XCTAssertEqual(
            ComparisonPrintingError.rowPaneCountMismatch(rowIndex: Int.max, expected: 2, actual: 3).errorDescription,
            "Print row \(onePastIntMax) has 3 panes; expected 2."
        )
        XCTAssertEqual(
            ComparisonPrintingError.invalidLineNumber(rowIndex: Int.max, paneIndex: Int.max, value: Int.max).errorDescription,
            "Print row \(onePastIntMax), pane \(onePastIntMax) has invalid line number \(Int.max)."
        )
    }

    func testLayoutAndHeaderFooterValidationRejectsNonfiniteAndInvalidMetrics() throws {
        let setup = try squarePageSetup(side: 100)
        let document = twoPaneDocument(rowCount: 1)

        assertPrintingError(.nonFiniteLayoutMetric("characterWidth")) {
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(characterWidth: .nan),
                headerFooter: noHeaderFooter
            )
        }
        assertPrintingError(.invalidLayoutMetric("lineHeight")) {
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(lineHeight: 0),
                headerFooter: noHeaderFooter
            )
        }
        assertPrintingError(.invalidLayoutMetric("paneSpacing")) {
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(paneSpacing: -1),
                headerFooter: noHeaderFooter
            )
        }
        assertPrintingError(.invalidLayoutMetric("headerFooter.bandHeight")) {
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: ComparisonPrintHeaderFooter(header: .documentTitle, footer: nil, bandHeight: 0)
            )
        }
        for tabWidth in [0, 33] {
            assertPrintingError(.invalidTabWidth(tabWidth)) {
                try ComparisonPrintPlanner.planPreview(
                    document: document,
                    pageSetup: setup,
                    layout: compactLayout(tabWidth: tabWidth),
                    headerFooter: noHeaderFooter
                )
            }
        }
        assertPrintingError(.printableAreaTooSmall) {
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: try squarePageSetup(side: 20),
                layout: compactLayout(lineNumberColumnWidth: 10),
                headerFooter: noHeaderFooter
            )
        }

        XCTAssertNoThrow(
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: ComparisonPrintHeaderFooter(header: nil, footer: nil, bandHeight: 0)
            )
        )
    }

    func testArithmeticOverflowIsReportedForGeometryAndScaledMetrics() throws {
        let greatest = CGFloat.greatestFiniteMagnitude
        assertPrintingError(.arithmeticOverflow) {
            try ComparisonPrintPageSetup(
                paperBounds: ComparisonPrintRect(x: -greatest, y: 0, width: 1, height: 2),
                imageableBounds: ComparisonPrintRect(x: -greatest, y: 0, width: 1, height: 2),
                margins: ComparisonPrintMargins(top: 0, leading: 0, bottom: 0, trailing: greatest)
            )
        }

        assertPrintingError(.arithmeticOverflow) {
            try ComparisonPrintPlanner.planPreview(
                document: twoPaneDocument(rowCount: 1),
                pageSetup: squarePageSetup(side: 100, scale: ComparisonPrintPageSetup.maximumScale),
                layout: compactLayout(characterWidth: greatest),
                headerFooter: noHeaderFooter
            )
        }
    }

    func testDocumentAndPageRangeValidationReportsExactErrors() throws {
        let setup = try squarePageSetup(side: 100)

        for paneCount in [0, 1, 4] {
            assertPrintingError(.unsupportedPaneCount(paneCount)) {
                try ComparisonPrintPlanner.planPreview(
                    document: ComparisonPrintDocument(title: "Invalid", paneTitles: Array(repeating: "Pane", count: paneCount), rows: []),
                    pageSetup: setup,
                    layout: compactLayout(),
                    headerFooter: noHeaderFooter
                )
            }
        }
        assertPrintingError(.rowPaneCountMismatch(rowIndex: 0, expected: 2, actual: 3)) {
            try ComparisonPrintPlanner.planPreview(
                document: ComparisonPrintDocument(
                    title: "Mismatch",
                    paneTitles: ["Left", "Right"],
                    rows: [ComparisonPrintRow(cells: Array(repeating: ComparisonPrintCell(text: "value"), count: 3))]
                ),
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter
            )
        }
        assertPrintingError(.invalidLineNumber(rowIndex: 0, paneIndex: 1, value: 0)) {
            try ComparisonPrintPlanner.planPreview(
                document: ComparisonPrintDocument(
                    title: "Line",
                    paneTitles: ["Left", "Right"],
                    rows: [
                        ComparisonPrintRow(
                            left: ComparisonPrintCell(lineNumber: 1, text: "left"),
                            right: ComparisonPrintCell(lineNumber: 0, text: "right")
                        )
                    ]
                ),
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter
            )
        }
        assertPrintingError(.invalidPageRange(firstPage: 0, lastPage: 1)) {
            try ComparisonPrintPageRange(firstPage: 0, lastPage: 1)
        }
        assertPrintingError(.invalidPageRange(firstPage: 2, lastPage: 1)) {
            try ComparisonPrintPageRange(firstPage: 2, lastPage: 1)
        }
        assertPrintingError(.pageRangeOutOfBounds(firstPage: 2, lastPage: 2, pageCount: 1)) {
            try ComparisonPrintPlanner.planPreview(
                document: twoPaneDocument(rowCount: 1),
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                pageRange: ComparisonPrintPageRange(firstPage: 2, lastPage: 2)
            )
        }
    }

    func testResourceLimitsRejectInvalidAndExceededBudgets() throws {
        let setup = try squarePageSetup(side: 100)
        let emptyDocument = twoPaneDocument(title: "", rowCount: 0)
        let invalidLimits: [(String, ComparisonPrintLimits)] = [
            ("maximumRows", ComparisonPrintLimits(maximumRows: 0)),
            ("maximumInputBytes", ComparisonPrintLimits(maximumInputBytes: 0)),
            ("maximumWork", ComparisonPrintLimits(maximumWork: 0)),
            ("maximumPages", ComparisonPrintLimits(maximumPages: 0)),
            ("maximumOutputBytes", ComparisonPrintLimits(maximumOutputBytes: 0)),
            ("maximumOutputItems", ComparisonPrintLimits(maximumOutputItems: 0))
        ]

        for (name, limits) in invalidLimits {
            assertPrintingError(.invalidLimit(name: name, value: 0)) {
                try ComparisonPrintPlanner.planPreview(
                    document: emptyDocument,
                    pageSetup: setup,
                    layout: compactLayout(),
                    headerFooter: noHeaderFooter,
                    limits: limits
                )
            }
        }
        let negativeLimits: [(String, ComparisonPrintLimits)] = [
            ("maximumRows", ComparisonPrintLimits(maximumRows: -1)),
            ("maximumInputBytes", ComparisonPrintLimits(maximumInputBytes: -1)),
            ("maximumWork", ComparisonPrintLimits(maximumWork: -1)),
            ("maximumPages", ComparisonPrintLimits(maximumPages: -1)),
            ("maximumOutputBytes", ComparisonPrintLimits(maximumOutputBytes: -1)),
            ("maximumOutputItems", ComparisonPrintLimits(maximumOutputItems: -1))
        ]

        for (name, limits) in negativeLimits {
            assertPrintingError(.invalidLimit(name: name, value: -1)) {
                try ComparisonPrintPlanner.planPreview(
                    document: emptyDocument,
                    pageSetup: setup,
                    layout: compactLayout(),
                    headerFooter: noHeaderFooter,
                    limits: limits
                )
            }
        }

        assertPrintingError(.tooManyRows(maximum: 1)) {
            try ComparisonPrintPlanner.planPreview(
                document: twoPaneDocument(rowCount: 2),
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: ComparisonPrintLimits(maximumRows: 1)
            )
        }
        assertPrintingError(.inputTooLarge(maximumBytes: 1)) {
            try ComparisonPrintPlanner.planPreview(
                document: twoPaneDocument(title: "xx", rowCount: 0),
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: ComparisonPrintLimits(maximumInputBytes: 1)
            )
        }
        assertPrintingError(.workLimitExceeded(maximum: 1)) {
            try ComparisonPrintPlanner.planPreview(
                document: emptyDocument,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: ComparisonPrintLimits(maximumWork: 1)
            )
        }
        assertPrintingError(.tooManyPages(maximum: 1)) {
            try ComparisonPrintPlanner.planPreview(
                document: twoPaneDocument(rowCount: 11),
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: ComparisonPrintLimits(maximumPages: 1)
            )
        }
        assertPrintingError(.outputTooLarge(maximumBytes: 1)) {
            try ComparisonPrintPlanner.planPreview(
                document: twoPaneDocument(title: "xx", rowCount: 0),
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: ComparisonPrintLimits(maximumOutputBytes: 1)
            )
        }
        assertPrintingError(.tooManyOutputItems(maximum: 1)) {
            try ComparisonPrintPlanner.planPreview(
                document: emptyDocument,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: ComparisonPrintLimits(maximumOutputItems: 1)
            )
        }
    }

    func testUTF8ByteLimitsAcceptExactIsolatedInputAndOutputAndRejectOneBelow() throws {
        let setup = try squarePageSetup(side: 20)
        let document = ComparisonPrintDocument(
            title: "🙂",
            paneTitles: ["", ""],
            rows: []
        )

        let exact = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: compactLayout(),
            headerFooter: noHeaderFooter,
            limits: ComparisonPrintLimits(maximumInputBytes: 4, maximumOutputBytes: 4)
        )

        XCTAssertEqual(exact.title, "🙂")
        assertPrintingError(.inputTooLarge(maximumBytes: 3)) {
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: ComparisonPrintLimits(maximumInputBytes: 3, maximumOutputBytes: 4)
            )
        }
        assertPrintingError(.outputTooLarge(maximumBytes: 3)) {
            try ComparisonPrintPlanner.planPreview(
                document: document,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: ComparisonPrintLimits(maximumInputBytes: 4, maximumOutputBytes: 3)
            )
        }
    }

    func testWorkLimitAppliesToPlanningLoopAfterValidation() throws {
        let setup = try squarePageSetup(side: 20)
        let emptyDocument = ComparisonPrintDocument(title: "", paneTitles: ["", ""], rows: [])
        let oneRowDocument = ComparisonPrintDocument(
            title: "",
            paneTitles: ["", ""],
            rows: [
                ComparisonPrintRow(
                    left: ComparisonPrintCell(text: ""),
                    right: ComparisonPrintCell(text: "")
                )
            ]
        )
        let limits = ComparisonPrintLimits(maximumWork: 6)

        XCTAssertNoThrow(
            try ComparisonPrintPlanner.planPreview(
                document: emptyDocument,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: limits
            ))
        assertPrintingError(.workLimitExceeded(maximum: 6)) {
            try ComparisonPrintPlanner.planPreview(
                document: oneRowDocument,
                pageSetup: setup,
                layout: compactLayout(),
                headerFooter: noHeaderFooter,
                limits: limits
            )
        }
    }

    func testPreCancelledPlanningStopsBeforeEmptyNonemptyOrInvalidInputWork() async throws {
        let setup = try squarePageSetup(side: 100)
        let layout = compactLayout()
        let headerFooter = noHeaderFooter
        let cases: [(String, ComparisonPrintDocument, ComparisonPrintLimits)] = [
            ("empty", twoPaneDocument(rowCount: 0), .default),
            ("nonempty", twoPaneDocument(rowCount: 100), .default),
            (
                "invalid",
                ComparisonPrintDocument(title: "Invalid", paneTitles: ["Only"], rows: []),
                ComparisonPrintLimits(maximumRows: -1)
            )
        ]

        for (name, document, limits) in cases {
            let outcome = await Task { () -> String in
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try ComparisonPrintPlanner.planPreview(
                        document: document,
                        pageSetup: setup,
                        layout: layout,
                        headerFooter: headerFooter,
                        limits: limits
                    )
                    return "succeeded"
                } catch is CancellationError {
                    return "cancelled"
                } catch {
                    return "unexpected: \(error)"
                }
            }.value

            XCTAssertEqual(outcome, "cancelled", name)
        }
    }

    func testPlanningIsDeterministicAndSelectedPlanMatchesCompletePlan() throws {
        let setup = try ComparisonPrintPageSetup(
            paperBounds: ComparisonPrintRect(x: 0, y: 0, width: 120, height: 100),
            imageableBounds: ComparisonPrintRect(x: 0, y: 0, width: 120, height: 100),
            orientation: .landscape,
            margins: ComparisonPrintMargins(0)
        )
        let rows = (0..<25).map { index in
            ComparisonPrintRow(
                base: ComparisonPrintCell(lineNumber: index + 1, text: "base-\(index)\t🙂"),
                left: ComparisonPrintCell(lineNumber: index + 101, text: "left-\(index)\ncontinued"),
                right: ComparisonPrintCell(lineNumber: index + 201, text: "right-\(index)")
            )
        }
        let document = ComparisonPrintDocument(title: "Deterministic", paneTitles: ["Base", "Left", "Right"], rows: rows)
        let layout = compactLayout(characterWidth: 1, lineNumberColumnWidth: 3)

        let first = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: layout,
            headerFooter: ComparisonPrintHeaderFooter(header: .documentTitle, footer: .pageNumberAndCount, bandHeight: 10)
        )
        let second = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: layout,
            headerFooter: ComparisonPrintHeaderFooter(header: .documentTitle, footer: .pageNumberAndCount, bandHeight: 10)
        )
        let selectedRange = try ComparisonPrintPageRange(firstPage: 2, lastPage: 2)
        let selected = try ComparisonPrintPlanner.planPreview(
            document: document,
            pageSetup: setup,
            layout: layout,
            headerFooter: ComparisonPrintHeaderFooter(header: .documentTitle, footer: .pageNumberAndCount, bandHeight: 10),
            pageRange: selectedRange
        )

        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.totalPageCount, 2)
        XCTAssertEqual(selected.totalPageCount, first.totalPageCount)
        XCTAssertEqual(selected.selectedPageRange, selectedRange)
        XCTAssertEqual(selected.pages, first.pages.filter { $0.pageNumber == 2 })
        XCTAssertTrue(
            first.pages.flatMap(\.rowFragments).allSatisfy { fragment in
                [fragment.frame.x, fragment.frame.y, fragment.frame.width, fragment.frame.height].allSatisfy(\.isFinite)
            })
    }

    private var noHeaderFooter: ComparisonPrintHeaderFooter {
        ComparisonPrintHeaderFooter(header: nil, footer: nil, bandHeight: 0)
    }

    private func squarePageSetup(side: CGFloat, scale: CGFloat = 1) throws -> ComparisonPrintPageSetup {
        let bounds = ComparisonPrintRect(x: 0, y: 0, width: side, height: side)
        return try ComparisonPrintPageSetup(
            paperBounds: bounds,
            imageableBounds: bounds,
            margins: ComparisonPrintMargins(0),
            scale: scale
        )
    }

    private func compactLayout(
        characterWidth: CGFloat = 1,
        lineHeight: CGFloat = 10,
        horizontalCellPadding: CGFloat = 0,
        verticalCellPadding: CGFloat = 0,
        paneSpacing: CGFloat = 0,
        lineNumberColumnWidth: CGFloat = 0,
        paneTitleHeight: CGFloat = 0,
        tabWidth: Int = 4
    ) -> ComparisonPrintLayout {
        ComparisonPrintLayout(
            characterWidth: characterWidth,
            lineHeight: lineHeight,
            horizontalCellPadding: horizontalCellPadding,
            verticalCellPadding: verticalCellPadding,
            paneSpacing: paneSpacing,
            lineNumberColumnWidth: lineNumberColumnWidth,
            paneTitleHeight: paneTitleHeight,
            tabWidth: tabWidth
        )
    }

    private func twoPaneDocument(title: String = "Document", rowCount: Int) -> ComparisonPrintDocument {
        document(paneCount: 2, title: title, rowCount: rowCount)
    }

    private func document(paneCount: Int, title: String = "Document", rowCount: Int) -> ComparisonPrintDocument {
        let paneTitles = (0..<paneCount).map { paneIndex in
            paneCount == 2 ? ["Left", "Right"][paneIndex] : "Pane \(paneIndex + 1)"
        }
        let rows = (0..<rowCount).map { rowIndex in
            ComparisonPrintRow(
                cells: (0..<paneCount).map { paneIndex in
                    ComparisonPrintCell(lineNumber: rowIndex + 1, text: "r\(rowIndex)-p\(paneIndex)")
                }
            )
        }
        return ComparisonPrintDocument(title: title, paneTitles: paneTitles, rows: rows)
    }

    private func assertPrintingError<T>(
        _ expected: ComparisonPrintingError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ComparisonPrintingError, expected, file: file, line: line)
        }
    }
}
