import MacMergeCore
import XCTest

@testable import MacMerge

#if DEBUG
    @MainActor
    final class DiffTableHorizontalScrollIntegrationTests: XCTestCase {
        func testRealWindowRoutesScrollerOuterWheelAndNestedWheelToEveryClipOrigin() {
            let harness = DiffTableHorizontalScrollTestHarness(
                rows: makeRows(count: 80, textLength: 180),
                width: 700,
                height: 190,
                maximumTextWidth: 900
            )
            defer { harness.close() }

            XCTAssertTrue(harness.scrollWithScroller(to: 120), "Expected NSScroller target/action delivery")
            XCTAssertEqual(harness.horizontalOffset, 120, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: 120, contentWidth: 900)

            XCTAssertTrue(harness.scrollWithWheel(by: 48))
            XCTAssertEqual(harness.horizontalOffset, 168, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: 168, contentWidth: 900)

            XCTAssertTrue(harness.scrollWithWindowWheelFromVisiblePane(by: 72))
            XCTAssertEqual(harness.horizontalOffset, 240, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: 240, contentWidth: 900)
        }

        func testNewlyRealizedAndReusedRowsKeepBothPaneClipOriginsDuringResize() throws {
            let rows = makeRows(count: 80, textLength: 180)
            let harness = DiffTableHorizontalScrollTestHarness(
                rows: rows,
                width: 700,
                height: 190,
                maximumTextWidth: 900
            )
            defer { harness.close() }
            harness.resize(to: 700)

            let initialCells = harness.visibleCells()
            XCTAssertGreaterThan(initialCells.count, 2)

            XCTAssertTrue(harness.scrollWithScroller(to: 240))
            let sharedOffset = harness.horizontalOffset
            XCTAssertEqual(sharedOffset, 240, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: sharedOffset, contentWidth: 900)

            let initialRows = Set(initialCells.map(\.row))
            let initialCellIDs = Set(initialCells.map(\.identity))
            var newlyRealizedRows = Set<Int>()
            var reusedRows = Set<Int>()
            for targetRow in [30, 60] {
                harness.scrollRowToVisible(targetRow)
                let currentCells = harness.visibleCells()
                XCTAssertTrue(initialRows.isDisjoint(with: currentCells.map(\.row)))
                newlyRealizedRows.formUnion(currentCells.map(\.row))
                reusedRows.formUnion(
                    currentCells.compactMap { cell in
                        initialCellIDs.contains(cell.identity) ? cell.row : nil
                    })
                assertEveryPane(in: harness, hasOffset: sharedOffset, contentWidth: 900)
            }
            XCTAssertFalse(newlyRealizedRows.isEmpty, "Expected rows outside the initial viewport")
            XCTAssertFalse(reusedRows.isEmpty, "Expected NSTableView to reuse at least one production cell")

            harness.resize(to: 1_700)
            let expectedMaximum = harness.maximumOffset
            XCTAssertLessThan(expectedMaximum, sharedOffset)
            XCTAssertEqual(harness.horizontalOffset, expectedMaximum, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(harness.horizontalOffset, 0)
            assertEveryPane(in: harness, hasOffset: expectedMaximum, contentWidth: 900)

            harness.resize(to: 2_200)
            XCTAssertEqual(harness.maximumOffset, 0, accuracy: 0.001)
            XCTAssertEqual(harness.horizontalOffset, 0, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: 0, contentWidth: 900)
        }

        func testMaximumTextWidthChangeAtSameOffsetPreservesOrClampsEveryClipOrigin() {
            let harness = DiffTableHorizontalScrollTestHarness(
                rows: makeRows(count: 80, textLength: 180),
                width: 700,
                height: 190,
                maximumTextWidth: 900
            )
            defer { harness.close() }

            XCTAssertTrue(harness.scrollWithScroller(to: 240))

            harness.setMaximumTextWidth(1_200)
            XCTAssertEqual(harness.horizontalOffset, 240, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: 240, contentWidth: 1_200)

            harness.setMaximumTextWidth(700)
            XCTAssertGreaterThan(harness.maximumOffset, 240)
            XCTAssertEqual(harness.horizontalOffset, 240, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: 240, contentWidth: 700)

            harness.setMaximumTextWidth(350)
            let clampedOffset = harness.maximumOffset
            XCTAssertGreaterThan(clampedOffset, 0)
            XCTAssertLessThan(clampedOffset, 240)
            XCTAssertEqual(harness.horizontalOffset, clampedOffset, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: clampedOffset, contentWidth: 350)
        }

        func testReloadPropagatesLongerAndShorterWidthsAtNonzeroOffsetAndClampsNewCells() {
            let harness = DiffTableHorizontalScrollTestHarness(
                rows: makeRows(count: 80, textLength: 180),
                width: 700,
                height: 190,
                maximumTextWidth: 900
            )
            defer { harness.close() }

            XCTAssertTrue(harness.scrollWithScroller(to: 240))
            XCTAssertEqual(harness.horizontalOffset, 240, accuracy: 0.001)

            harness.reload(
                rows: makeRows(count: 100, textLength: 260),
                maximumTextWidth: 1_200
            )
            XCTAssertGreaterThan(harness.maximumOffset, 240)
            XCTAssertEqual(harness.horizontalOffset, 240, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: 240, contentWidth: 1_200)

            harness.reload(
                rows: makeRows(count: 90, textLength: 120),
                maximumTextWidth: 700
            )
            XCTAssertGreaterThan(harness.maximumOffset, 240)
            XCTAssertEqual(harness.horizontalOffset, 240, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: 240, contentWidth: 700)

            harness.scrollRowToVisible(70)
            XCTAssertTrue(harness.visibleCells().allSatisfy { $0.row >= 60 })
            assertEveryPane(in: harness, hasOffset: 240, contentWidth: 700)

            harness.reload(
                rows: makeRows(count: 90, textLength: 40),
                maximumTextWidth: 350
            )
            let clampedOffset = harness.maximumOffset
            XCTAssertGreaterThan(clampedOffset, 0)
            XCTAssertLessThan(clampedOffset, 240)
            XCTAssertEqual(harness.horizontalOffset, clampedOffset, accuracy: 0.001)
            assertEveryPane(in: harness, hasOffset: clampedOffset, contentWidth: 350)

            harness.scrollRowToVisible(20)
            XCTAssertTrue(harness.visibleCells().allSatisfy { $0.row < 30 })
            assertEveryPane(in: harness, hasOffset: clampedOffset, contentWidth: 350)
        }

        private func assertEveryPane(
            in harness: DiffTableHorizontalScrollTestHarness,
            hasOffset expectedOffset: CGFloat,
            contentWidth expectedContentWidth: CGFloat
        ) {
            let cells = harness.visibleCells()
            XCTAssertFalse(cells.isEmpty)
            for cell in cells {
                XCTAssertEqual(cell.leftOffset, expectedOffset, accuracy: 0.001, "Left pane row \(cell.row)")
                XCTAssertEqual(cell.rightOffset, expectedOffset, accuracy: 0.001, "Right pane row \(cell.row)")
                XCTAssertEqual(
                    cell.leftContentWidth,
                    expectedContentWidth,
                    accuracy: 0.001,
                    "Left pane width row \(cell.row)"
                )
                XCTAssertEqual(
                    cell.rightContentWidth,
                    expectedContentWidth,
                    accuracy: 0.001,
                    "Right pane width row \(cell.row)"
                )
            }
        }

        private func makeRows(count: Int, textLength: Int) -> [DiffRow] {
            (1...count).map { number in
                DiffRow(
                    left: DiffLine(
                        number: number,
                        text: "left \(number) " + String(repeating: "L", count: textLength)
                    ),
                    right: DiffLine(
                        number: number,
                        text: "right \(number) " + String(repeating: "R", count: textLength)
                    ),
                    kind: number.isMultiple(of: 2) ? .modified : .unchanged
                )
            }
        }
    }
#else
    final class DiffTableHorizontalScrollReleaseCompileTests: XCTestCase {
        func testDebugOnlyHorizontalScrollHarnessIsExcluded() {}
    }
#endif
