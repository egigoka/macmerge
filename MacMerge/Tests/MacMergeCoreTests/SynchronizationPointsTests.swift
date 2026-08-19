import Foundation
import XCTest

@testable import MacMergeCore

final class SynchronizationPointsTests: XCTestCase {
    func testPointRejectsSourceLinesOutsidePracticalLimitAndRoundTripsBoundary() throws {
        assertSynchronizationError(.negativeLeftSourceLine(-1)) {
            try SynchronizationPoint(leftSourceLine: -1, rightSourceLine: 0)
        }
        assertSynchronizationError(.negativeRightSourceLine(Int.min)) {
            try SynchronizationPoint(leftSourceLine: 0, rightSourceLine: Int.min)
        }
        assertSynchronizationError(
            .leftSourceLineOutOfBounds(
                line: SynchronizationPoints.maximumLineCount,
                lineCount: SynchronizationPoints.maximumLineCount
            )
        ) {
            try point(SynchronizationPoints.maximumLineCount, 0)
        }
        assertSynchronizationError(
            .rightSourceLineOutOfBounds(
                line: Int.max,
                lineCount: SynchronizationPoints.maximumLineCount
            )
        ) {
            try point(0, Int.max)
        }

        let boundary = try SynchronizationPoint(
            leftSourceLine: SynchronizationPoints.maximumLineCount - 1,
            rightSourceLine: SynchronizationPoints.maximumLineCount - 1
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                SynchronizationPoint.self,
                from: JSONEncoder().encode(boundary)
            ),
            boundary
        )
    }

    func testBoundedPointAcceptsLastLinesAndRejectsExactAndOneBeyondLineCounts() throws {
        XCTAssertEqual(
            try SynchronizationPoint(
                leftSourceLine: 2,
                rightSourceLine: 3,
                leftLineCount: 3,
                rightLineCount: 4
            ),
            try point(2, 3)
        )

        assertSynchronizationError(.leftSourceLineOutOfBounds(line: 3, lineCount: 3)) {
            try SynchronizationPoint(
                leftSourceLine: 3,
                rightSourceLine: 0,
                leftLineCount: 3,
                rightLineCount: 1
            )
        }
        assertSynchronizationError(.leftSourceLineOutOfBounds(line: 4, lineCount: 3)) {
            try SynchronizationPoint(
                leftSourceLine: 4,
                rightSourceLine: 0,
                leftLineCount: 3,
                rightLineCount: 1
            )
        }
        assertSynchronizationError(.rightSourceLineOutOfBounds(line: 4, lineCount: 4)) {
            try SynchronizationPoint(
                leftSourceLine: 0,
                rightSourceLine: 4,
                leftLineCount: 1,
                rightLineCount: 4
            )
        }
        assertSynchronizationError(.rightSourceLineOutOfBounds(line: 5, lineCount: 4)) {
            try SynchronizationPoint(
                leftSourceLine: 0,
                rightSourceLine: 5,
                leftLineCount: 1,
                rightLineCount: 4
            )
        }
        assertSynchronizationError(.invalidLeftLineCount(-1)) {
            try SynchronizationPoint(
                leftSourceLine: 0,
                rightSourceLine: 0,
                leftLineCount: -1,
                rightLineCount: 1
            )
        }
        assertSynchronizationError(.invalidRightLineCount(-1)) {
            try SynchronizationPoint(
                leftSourceLine: 0,
                rightSourceLine: 0,
                leftLineCount: 1,
                rightLineCount: -1
            )
        }
        assertSynchronizationError(
            .invalidLeftLineCount(SynchronizationPoints.maximumLineCount + 1)
        ) {
            try SynchronizationPoint(
                leftSourceLine: 0,
                rightSourceLine: 0,
                leftLineCount: SynchronizationPoints.maximumLineCount + 1,
                rightLineCount: 1
            )
        }
        assertSynchronizationError(.invalidRightLineCount(Int.max)) {
            try SynchronizationPoint(
                leftSourceLine: 0,
                rightSourceLine: 0,
                leftLineCount: 1,
                rightLineCount: Int.max
            )
        }

        XCTAssertEqual(
            try SynchronizationPoint(
                leftSourceLine: SynchronizationPoints.maximumLineCount - 1,
                rightSourceLine: SynchronizationPoints.maximumLineCount - 1,
                leftLineCount: SynchronizationPoints.maximumLineCount,
                rightLineCount: SynchronizationPoints.maximumLineCount
            ),
            try point(
                SynchronizationPoints.maximumLineCount - 1,
                SynchronizationPoints.maximumLineCount - 1
            )
        )
    }

    func testBoundedInitializerAndAddEnforceCountsBoundsAndNoOpAtCap() throws {
        let maximum = SynchronizationPoints.maximumLineCount
        let last = try point(maximum - 1, maximum - 1)

        XCTAssertEqual(
            try SynchronizationPoints(
                anchors: [last],
                leftLineCount: maximum,
                rightLineCount: maximum
            ).anchors,
            [last]
        )
        assertSynchronizationError(.invalidLeftLineCount(maximum + 1)) {
            try SynchronizationPoints(
                anchors: [],
                leftLineCount: maximum + 1,
                rightLineCount: maximum
            )
        }
        assertSynchronizationError(.invalidRightLineCount(Int.max)) {
            try SynchronizationPoints(
                anchors: [],
                leftLineCount: maximum,
                rightLineCount: Int.max
            )
        }
        assertSynchronizationError(.leftSourceLineOutOfBounds(line: 2, lineCount: 2)) {
            try SynchronizationPoints(
                anchors: [try point(2, 3)],
                leftLineCount: 2,
                rightLineCount: 4
            )
        }
        assertSynchronizationError(.rightSourceLineOutOfBounds(line: 3, lineCount: 3)) {
            try SynchronizationPoints(
                anchors: [try point(2, 3)],
                leftLineCount: 3,
                rightLineCount: 3
            )
        }

        var points = try SynchronizationPoints(anchors: [last])
        XCTAssertFalse(
            try points.add(
                last,
                leftLineCount: maximum,
                rightLineCount: maximum
            )
        )
        XCTAssertEqual(points.anchors, [last])

        let original = points
        assertSynchronizationError(.invalidLeftLineCount(maximum + 1)) {
            try points.add(
                last,
                leftLineCount: maximum + 1,
                rightLineCount: maximum
            )
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(
            .rightSourceLineOutOfBounds(line: maximum - 1, lineCount: maximum - 1)
        ) {
            try points.add(
                last,
                leftLineCount: maximum,
                rightLineCount: maximum - 1
            )
        }
        XCTAssertEqual(points, original)

        var empty = SynchronizationPoints()
        let emptyOriginal = empty
        assertSynchronizationError(.leftSourceLineOutOfBounds(line: 2, lineCount: 2)) {
            try empty.add(
                try point(2, 3),
                leftLineCount: 2,
                rightLineCount: 4
            )
        }
        XCTAssertEqual(empty, emptyOriginal)
        assertSynchronizationError(.rightSourceLineOutOfBounds(line: 3, lineCount: 3)) {
            try empty.add(
                try point(2, 3),
                leftLineCount: 3,
                rightLineCount: 3
            )
        }
        XCTAssertEqual(empty, emptyOriginal)
    }

    func testInitializerRejectsDuplicateUnorderedAndCrossingAnchors() throws {
        let a = try point(1, 10)
        let duplicateLeft = try point(1, 11)
        let duplicateRight = try point(2, 10)
        let crossing = try point(2, 9)

        assertSynchronizationError(
            .leftSourceLinesNotStrictlyIncreasing(previous: 1, next: 1)
        ) {
            try SynchronizationPoints(anchors: [a, duplicateLeft])
        }
        assertSynchronizationError(
            .rightSourceLinesNotStrictlyIncreasing(previous: 10, next: 10)
        ) {
            try SynchronizationPoints(anchors: [a, duplicateRight])
        }
        assertSynchronizationError(
            .rightSourceLinesNotStrictlyIncreasing(previous: 10, next: 9)
        ) {
            try SynchronizationPoints(anchors: [a, crossing])
        }
        assertSynchronizationError(
            .leftSourceLinesNotStrictlyIncreasing(previous: 2, next: 1)
        ) {
            try SynchronizationPoints(anchors: [try point(2, 20), a])
        }
    }

    func testAddMaintainsCanonicalOrderAndRejectsCrossingsAtomically() throws {
        var points = SynchronizationPoints()
        XCTAssertTrue(try points.add(leftSourceLine: 5, rightSourceLine: 50))
        XCTAssertTrue(try points.add(leftSourceLine: 1, rightSourceLine: 10))
        XCTAssertTrue(try points.add(leftSourceLine: 3, rightSourceLine: 30))
        XCTAssertEqual(points.anchors, [try point(1, 10), try point(3, 30), try point(5, 50)])
        XCTAssertFalse(try points.add(leftSourceLine: 3, rightSourceLine: 30))

        let original = points
        assertSynchronizationError(
            .rightSourceLinesNotStrictlyIncreasing(previous: 10, next: 9)
        ) {
            try points.add(leftSourceLine: 2, rightSourceLine: 9)
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(
            .rightSourceLinesNotStrictlyIncreasing(previous: 60, next: 50)
        ) {
            try points.add(leftSourceLine: 4, rightSourceLine: 60)
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(
            .leftSourceLinesNotStrictlyIncreasing(previous: 3, next: 3)
        ) {
            try points.add(leftSourceLine: 3, rightSourceLine: 31)
        }
        XCTAssertEqual(points, original)
    }

    func testAddChecksBothNeighborsForDuplicatesAndCrossings() throws {
        let original = try SynchronizationPoints(
            anchors: [try point(10, 10), try point(30, 30)]
        )
        var points = original

        XCTAssertFalse(try points.add(leftSourceLine: 10, rightSourceLine: 10))
        assertSynchronizationError(
            .leftSourceLinesNotStrictlyIncreasing(previous: 10, next: 10)
        ) {
            try points.add(leftSourceLine: 10, rightSourceLine: 20)
        }
        assertSynchronizationError(
            .rightSourceLinesNotStrictlyIncreasing(previous: 10, next: 10)
        ) {
            try points.add(leftSourceLine: 20, rightSourceLine: 10)
        }
        assertSynchronizationError(
            .rightSourceLinesNotStrictlyIncreasing(previous: 30, next: 30)
        ) {
            try points.add(leftSourceLine: 20, rightSourceLine: 30)
        }
        assertSynchronizationError(
            .rightSourceLinesNotStrictlyIncreasing(previous: 10, next: 9)
        ) {
            try points.add(leftSourceLine: 20, rightSourceLine: 9)
        }
        assertSynchronizationError(
            .rightSourceLinesNotStrictlyIncreasing(previous: 31, next: 30)
        ) {
            try points.add(leftSourceLine: 20, rightSourceLine: 31)
        }
        XCTAssertEqual(points, original)
    }

    func testArrayInitializerAndAddEnforceAnchorCapButAllowIdempotentNoOp() throws {
        let anchors = try (0..<SynchronizationPoints.maximumAnchorCount).map {
            try point($0, $0)
        }
        var points = try SynchronizationPoints(anchors: anchors)

        XCTAssertEqual(points.count, SynchronizationPoints.maximumAnchorCount)
        XCTAssertFalse(try points.add(anchors[anchors.count / 2]))
        XCTAssertEqual(points.anchors, anchors)

        assertSynchronizationError(
            .tooManyAnchors(maximum: SynchronizationPoints.maximumAnchorCount)
        ) {
            try points.add(
                leftSourceLine: SynchronizationPoints.maximumAnchorCount,
                rightSourceLine: SynchronizationPoints.maximumAnchorCount
            )
        }
        XCTAssertEqual(points.anchors, anchors)

        assertSynchronizationError(
            .tooManyAnchors(maximum: SynchronizationPoints.maximumAnchorCount)
        ) {
            try SynchronizationPoints(
                anchors: anchors + [
                    try point(
                        SynchronizationPoints.maximumAnchorCount,
                        SynchronizationPoints.maximumAnchorCount
                    )
                ]
            )
        }
    }

    func testRemoveClearAndInvalidateReportMutation() throws {
        let first = try point(1, 10)
        let second = try point(3, 30)
        var points = try SynchronizationPoints(anchors: [first, second])

        XCTAssertFalse(points.remove(try point(2, 20)))
        XCTAssertTrue(points.remove(first))
        XCTAssertEqual(points.anchors, [second])
        XCTAssertFalse(try points.remove(leftSourceLine: 1, rightSourceLine: 10))
        XCTAssertTrue(points.invalidate())
        XCTAssertTrue(points.isEmpty)
        XCTAssertFalse(points.invalidate())
        XCTAssertFalse(points.clear())
    }

    func testReloadingEitherSourceInvalidatesAllAnchors() throws {
        let anchors = [try point(1, 2), try point(3, 4)]
        var leftReload = try SynchronizationPoints(anchors: anchors)
        var rightReload = try SynchronizationPoints(anchors: anchors)

        XCTAssertTrue(leftReload.invalidateAfterReloadingLeftSource())
        XCTAssertTrue(leftReload.isEmpty)
        XCTAssertFalse(leftReload.invalidateAfterReloadingLeftSource())

        XCTAssertTrue(rightReload.invalidateAfterReloadingRightSource())
        XCTAssertTrue(rightReload.isEmpty)
        XCTAssertFalse(rightReload.invalidateAfterReloadingRightSource())
    }

    func testMappingCoversEmptySingleClampExactAndFloorInterpolation() throws {
        let empty = SynchronizationPoints()
        XCTAssertNil(try empty.mapLeftToRight(0))
        XCTAssertNil(try empty.mapRightToLeft(SynchronizationPoints.maximumLineCount - 1))

        let single = try SynchronizationPoints(anchors: [try point(5, 9)])
        XCTAssertEqual(try single.mapLeftToRight(0), 9)
        XCTAssertEqual(
            try single.mapLeftToRight(SynchronizationPoints.maximumLineCount - 1),
            9
        )
        XCTAssertEqual(try single.mapRightToLeft(0), 5)
        XCTAssertEqual(
            try single.mapRightToLeft(SynchronizationPoints.maximumLineCount - 1),
            5
        )

        let points = try SynchronizationPoints(
            anchors: [try point(10, 20), try point(14, 30), try point(20, 33)]
        )
        XCTAssertEqual(try points.mapLeftToRight(0), 20)
        XCTAssertEqual(try points.mapLeftToRight(10), 20)
        XCTAssertEqual(try points.mapLeftToRight(11), 22)
        XCTAssertEqual(try points.mapLeftToRight(13), 27)
        XCTAssertEqual(try points.mapLeftToRight(14), 30)
        XCTAssertEqual(try points.mapLeftToRight(19), 32)
        XCTAssertEqual(
            try points.mapLeftToRight(SynchronizationPoints.maximumLineCount - 1),
            33
        )

        XCTAssertEqual(try points.mapRightToLeft(0), 10)
        XCTAssertEqual(try points.mapRightToLeft(20), 10)
        XCTAssertEqual(try points.mapRightToLeft(21), 10)
        XCTAssertEqual(try points.mapRightToLeft(29), 13)
        XCTAssertEqual(try points.mapRightToLeft(30), 14)
        XCTAssertEqual(try points.mapRightToLeft(31), 16)
        XCTAssertEqual(try points.mapRightToLeft(32), 18)
        XCTAssertEqual(try points.mapRightToLeft(33), 20)
        XCTAssertEqual(
            try points.mapRightToLeft(SynchronizationPoints.maximumLineCount - 1),
            20
        )
    }

    func testInterpolationIsExactAtSupportedLineLimit() throws {
        let maximumLine = SynchronizationPoints.maximumLineCount - 1
        let identity = try SynchronizationPoints(
            anchors: [try point(0, 0), try point(maximumLine, maximumLine)]
        )
        for line in [0, 1, maximumLine / 2, maximumLine - 1, maximumLine] {
            XCTAssertEqual(try identity.mapLeftToRight(line), line)
            XCTAssertEqual(try identity.mapRightToLeft(line), line)
        }

        let narrowDestination = try SynchronizationPoints(
            anchors: [try point(0, maximumLine - 2), try point(maximumLine, maximumLine)]
        )
        XCTAssertEqual(
            try narrowDestination.mapLeftToRight(maximumLine / 2),
            maximumLine - 2
        )
        XCTAssertEqual(
            try narrowDestination.mapLeftToRight(maximumLine - 1),
            maximumLine - 1
        )
    }

    func testMappingRejectsNegativeAndOutOfRangeQueriesOnBothSides() throws {
        let points = try SynchronizationPoints(anchors: [try point(0, 0)])
        assertSynchronizationError(.negativeLeftSourceLine(-1)) {
            try points.mapLeftToRight(-1)
        }
        assertSynchronizationError(.negativeRightSourceLine(Int.min)) {
            try points.mapRightToLeft(Int.min)
        }
        assertSynchronizationError(
            .leftSourceLineOutOfBounds(
                line: SynchronizationPoints.maximumLineCount,
                lineCount: SynchronizationPoints.maximumLineCount
            )
        ) {
            try points.mapLeftToRight(SynchronizationPoints.maximumLineCount)
        }
        assertSynchronizationError(
            .rightSourceLineOutOfBounds(
                line: Int.max,
                lineCount: SynchronizationPoints.maximumLineCount
            )
        ) {
            try points.mapRightToLeft(Int.max)
        }
    }

    func testBoundedMappingRejectsCountsQueriesAndStaleAnchorsOnBothSides() throws {
        let maximum = SynchronizationPoints.maximumLineCount
        let points = try SynchronizationPoints(anchors: [try point(2, 3)])

        XCTAssertEqual(
            try points.mapLeftToRight(
                maximum - 1,
                leftLineCount: maximum,
                rightLineCount: maximum
            ),
            3
        )
        XCTAssertEqual(
            try points.mapRightToLeft(
                maximum - 1,
                leftLineCount: maximum,
                rightLineCount: maximum
            ),
            2
        )
        assertSynchronizationError(.invalidLeftLineCount(maximum + 1)) {
            try points.mapLeftToRight(
                0,
                leftLineCount: maximum + 1,
                rightLineCount: maximum
            )
        }
        assertSynchronizationError(.invalidRightLineCount(Int.max)) {
            try points.mapRightToLeft(
                0,
                leftLineCount: maximum,
                rightLineCount: Int.max
            )
        }
        assertSynchronizationError(.leftSourceLineOutOfBounds(line: 4, lineCount: 4)) {
            try points.mapLeftToRight(4, leftLineCount: 4, rightLineCount: 4)
        }
        assertSynchronizationError(.rightSourceLineOutOfBounds(line: 4, lineCount: 4)) {
            try points.mapRightToLeft(4, leftLineCount: 4, rightLineCount: 4)
        }
        assertSynchronizationError(.leftSourceLineOutOfBounds(line: 2, lineCount: 2)) {
            try points.mapRightToLeft(0, leftLineCount: 2, rightLineCount: 4)
        }
        assertSynchronizationError(.rightSourceLineOutOfBounds(line: 3, lineCount: 3)) {
            try points.mapLeftToRight(0, leftLineCount: 3, rightLineCount: 3)
        }
    }

    func testRemapHandlesInsertionReplacementAndBothSides() throws {
        let anchors = [
            try point(1, 10),
            try point(3, 20),
            try point(5, 30),
            try point(8, 40)
        ]

        var insertion = try SynchronizationPoints(anchors: anchors)
        try insertion.remap(
            afterEditing: .left,
            replacing: 3..<3,
            withLineCount: 2
        )
        XCTAssertEqual(
            insertion.anchors,
            [try point(1, 10), try point(5, 20), try point(7, 30), try point(10, 40)]
        )

        var replacement = try SynchronizationPoints(anchors: anchors)
        try replacement.remap(
            afterEditing: .left,
            replacing: 3..<6,
            withLineCount: 2
        )
        XCTAssertEqual(replacement.anchors, [try point(1, 10), try point(7, 40)])

        var deletion = try SynchronizationPoints(anchors: anchors)
        try deletion.remap(
            afterEditing: .right,
            replacing: 15..<31,
            withLineCount: 0
        )
        XCTAssertEqual(deletion.anchors, [try point(1, 10), try point(8, 24)])
    }

    func testBoundedLeftAndRightInsertionsShiftAnchorsAndReturnLineCounts() throws {
        let anchors = [
            try point(1, 1),
            try point(3, 3),
            try point(6, 6),
            try point(9, 9)
        ]
        var left = try SynchronizationPoints(anchors: anchors)
        var right = try SynchronizationPoints(anchors: anchors)

        XCTAssertEqual(
            try left.remapLeftSource(
                replacing: 2..<2,
                withLineCount: 2,
                currentLineCount: 10
            ),
            12
        )
        XCTAssertEqual(
            left.anchors,
            [try point(1, 1), try point(5, 3), try point(8, 6), try point(11, 9)]
        )

        XCTAssertEqual(
            try right.remapRightSource(
                replacing: 2..<2,
                withLineCount: 2,
                currentLineCount: 10
            ),
            12
        )
        XCTAssertEqual(
            right.anchors,
            [try point(1, 1), try point(3, 5), try point(6, 8), try point(9, 11)]
        )
    }

    func testBoundedLeftAndRightReplacementsRemoveAndShiftAnchors() throws {
        let anchors = [
            try point(1, 1),
            try point(3, 3),
            try point(6, 6),
            try point(9, 9)
        ]
        var left = try SynchronizationPoints(anchors: anchors)
        var right = try SynchronizationPoints(anchors: anchors)

        XCTAssertEqual(
            try left.remapLeftSource(
                replacing: 2..<5,
                withLineCount: 1,
                currentLineCount: 10
            ),
            8
        )
        XCTAssertEqual(
            left.anchors,
            [try point(1, 1), try point(4, 6), try point(7, 9)]
        )

        XCTAssertEqual(
            try right.remapRightSource(
                replacing: 2..<5,
                withLineCount: 1,
                currentLineCount: 10
            ),
            8
        )
        XCTAssertEqual(
            right.anchors,
            [try point(1, 1), try point(6, 4), try point(9, 7)]
        )
    }

    func testBoundedLeftAndRightRemapAcceptCapAndIdempotentNoOp() throws {
        let maximum = SynchronizationPoints.maximumLineCount
        let last = try point(maximum - 1, maximum - 1)
        let original = try SynchronizationPoints(anchors: [last])
        var left = original
        var right = original

        XCTAssertEqual(
            try left.remapLeftSource(
                replacing: maximum..<maximum,
                withLineCount: 0,
                currentLineCount: maximum
            ),
            maximum
        )
        XCTAssertEqual(left, original)
        XCTAssertEqual(
            try right.remapRightSource(
                replacing: maximum..<maximum,
                withLineCount: 0,
                currentLineCount: maximum
            ),
            maximum
        )
        XCTAssertEqual(right, original)
    }

    func testReplacementKeepsAnchorAtUpperEndpointOnBothSides() throws {
        let anchors = [try point(1, 1), try point(4, 4), try point(5, 5), try point(8, 8)]
        var left = try SynchronizationPoints(anchors: anchors)
        var right = try SynchronizationPoints(anchors: anchors)

        XCTAssertEqual(
            try left.remapLeftSource(
                replacing: 2..<5,
                withLineCount: 1,
                currentLineCount: 9
            ),
            7
        )
        XCTAssertEqual(left.anchors, [try point(1, 1), try point(3, 5), try point(6, 8)])

        XCTAssertEqual(
            try right.remapRightSource(
                replacing: 2..<5,
                withLineCount: 1,
                currentLineCount: 9
            ),
            7
        )
        XCTAssertEqual(right.anchors, [try point(1, 1), try point(5, 3), try point(8, 6)])
    }

    func testBoundedLeftAndRightRemapRejectGrowthPastCapAtomically() throws {
        let maximum = SynchronizationPoints.maximumLineCount
        let original = try SynchronizationPoints(anchors: [try point(0, 0)])
        var left = original
        var right = original

        assertSynchronizationError(.sourceLineOverflow(side: .left)) {
            try left.remapLeftSource(
                replacing: maximum..<maximum,
                withLineCount: 1,
                currentLineCount: maximum
            )
        }
        XCTAssertEqual(left, original)

        assertSynchronizationError(.sourceLineOverflow(side: .right)) {
            try right.remapRightSource(
                replacing: maximum..<maximum,
                withLineCount: 1,
                currentLineCount: maximum
            )
        }
        XCTAssertEqual(right, original)
    }

    func testBoundedRemapRejectsNegativeOutOfRangeAndStaleInputsAtomicallyBothSides() throws {
        let maximum = SynchronizationPoints.maximumLineCount
        let original = try SynchronizationPoints(anchors: [try point(2, 2)])

        for side in [SynchronizationPointSide.left, .right] {
            var points = original
            assertSynchronizationError(
                side == .left ? .invalidLeftLineCount(-1) : .invalidRightLineCount(-1)
            ) {
                try points.remap(
                    afterEditing: side,
                    replacing: 0..<0,
                    withLineCount: 0,
                    currentLineCount: -1
                )
            }
            XCTAssertEqual(points, original)

            assertSynchronizationError(
                .invalidEditRange(side: side, lowerBound: -1, upperBound: 0)
            ) {
                try points.remap(
                    afterEditing: side,
                    replacing: -1..<0,
                    withLineCount: 0,
                    currentLineCount: 4
                )
            }
            XCTAssertEqual(points, original)

            assertSynchronizationError(.invalidInsertedLineCount(-1)) {
                try points.remap(
                    afterEditing: side,
                    replacing: 0..<0,
                    withLineCount: -1,
                    currentLineCount: 4
                )
            }
            XCTAssertEqual(points, original)

            assertSynchronizationError(.invalidInsertedLineCount(maximum + 1)) {
                try points.remap(
                    afterEditing: side,
                    replacing: 0..<0,
                    withLineCount: maximum + 1,
                    currentLineCount: 4
                )
            }
            XCTAssertEqual(points, original)

            assertSynchronizationError(.invalidInsertedLineCount(Int.max)) {
                try points.remap(
                    afterEditing: side,
                    replacing: 0..<0,
                    withLineCount: Int.max,
                    currentLineCount: 4
                )
            }
            XCTAssertEqual(points, original)

            assertSynchronizationError(
                side == .left
                    ? .invalidLeftLineCount(maximum + 1)
                    : .invalidRightLineCount(maximum + 1)
            ) {
                try points.remap(
                    afterEditing: side,
                    replacing: 0..<0,
                    withLineCount: 0,
                    currentLineCount: maximum + 1
                )
            }
            XCTAssertEqual(points, original)

            assertSynchronizationError(
                side == .left
                    ? .invalidLeftLineCount(Int.max)
                    : .invalidRightLineCount(Int.max)
            ) {
                try points.remap(
                    afterEditing: side,
                    replacing: 0..<0,
                    withLineCount: 0,
                    currentLineCount: Int.max
                )
            }
            XCTAssertEqual(points, original)

            assertSynchronizationError(
                .invalidEditRange(side: side, lowerBound: 0, upperBound: 5)
            ) {
                try points.remap(
                    afterEditing: side,
                    replacing: 0..<5,
                    withLineCount: 0,
                    currentLineCount: 4
                )
            }
            XCTAssertEqual(points, original)

            assertSynchronizationError(
                .invalidEditRange(side: side, lowerBound: 0, upperBound: Int.max)
            ) {
                try points.remap(
                    afterEditing: side,
                    replacing: 0..<Int.max,
                    withLineCount: 0,
                    currentLineCount: 4
                )
            }
            XCTAssertEqual(points, original)

            let staleError: SynchronizationPointsError =
                side == .left
                ? .leftSourceLineOutOfBounds(line: 2, lineCount: 2)
                : .rightSourceLineOutOfBounds(line: 2, lineCount: 2)
            assertSynchronizationError(staleError) {
                try points.remap(
                    afterEditing: side,
                    replacing: 0..<0,
                    withLineCount: 0,
                    currentLineCount: 2
                )
            }
            XCTAssertEqual(points, original)
        }
    }

    func testRemapNoOpAndFailuresAreAtomic() throws {
        let maximum = SynchronizationPoints.maximumLineCount
        let original = try SynchronizationPoints(
            anchors: [try point(0, 0), try point(maximum - 1, 1)]
        )
        var points = original

        try points.remap(afterEditing: .left, replacing: 4..<4, withLineCount: 0)
        XCTAssertEqual(points, original)

        assertSynchronizationError(.invalidInsertedLineCount(-1)) {
            try points.remap(afterEditing: .left, replacing: 0..<0, withLineCount: -1)
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(
            .invalidEditRange(side: .right, lowerBound: -1, upperBound: 0)
        ) {
            try points.remap(afterEditing: .right, replacing: -1..<0, withLineCount: 0)
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(.sourceLineOverflow(side: .left)) {
            try points.remap(afterEditing: .left, replacing: 0..<0, withLineCount: 1)
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(.sourceLineOverflow(side: .right)) {
            try points.remap(
                afterEditing: .right,
                replacing: maximum..<maximum,
                withLineCount: 1
            )
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(
            .invalidEditRange(side: .left, lowerBound: 0, upperBound: maximum + 1)
        ) {
            try points.remap(
                afterEditing: .left,
                replacing: 0..<(maximum + 1),
                withLineCount: 0
            )
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(
            .invalidEditRange(side: .right, lowerBound: 0, upperBound: Int.max)
        ) {
            try points.remap(
                afterEditing: .right,
                replacing: 0..<Int.max,
                withLineCount: 0
            )
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(.invalidInsertedLineCount(maximum + 1)) {
            try points.remap(
                afterEditing: .right,
                replacing: 0..<0,
                withLineCount: maximum + 1
            )
        }
        XCTAssertEqual(points, original)
        assertSynchronizationError(.invalidInsertedLineCount(Int.max)) {
            try points.remap(
                afterEditing: .left,
                replacing: 0..<0,
                withLineCount: Int.max
            )
        }
        XCTAssertEqual(points, original)
    }

    func testMappingAndEditingAreSymmetricWhenSidesAreSwapped() throws {
        let points = try SynchronizationPoints(
            anchors: [try point(1, 2), try point(4, 7), try point(9, 11)]
        )
        var edited = points
        var swapped = try SynchronizationPoints(
            anchors: points.anchors.map {
                try point($0.rightSourceLine, $0.leftSourceLine)
            }
        )

        for line in [0, 1, 2, 3, 4, 6, 7, 9, 11, 12] {
            XCTAssertEqual(
                try points.mapLeftToRight(line),
                try swapped.mapRightToLeft(line)
            )
            XCTAssertEqual(
                try points.mapRightToLeft(line),
                try swapped.mapLeftToRight(line)
            )
        }

        XCTAssertEqual(
            try edited.remapLeftSource(
                replacing: 3..<6,
                withLineCount: 2,
                currentLineCount: 12
            ),
            try swapped.remapRightSource(
                replacing: 3..<6,
                withLineCount: 2,
                currentLineCount: 12
            )
        )
        XCTAssertEqual(
            try edited.anchors.map {
                try point($0.rightSourceLine, $0.leftSourceLine)
            },
            swapped.anchors
        )
    }

    func testCodableRoundTripsCanonicalStateAndRejectsBrokenInvariants() throws {
        let maximumLine = SynchronizationPoints.maximumLineCount - 1
        let points = try SynchronizationPoints(
            anchors: [try point(0, 1), try point(5, 9), try point(maximumLine, maximumLine)]
        )
        let data = try JSONEncoder().encode(points)
        XCTAssertEqual(try JSONDecoder().decode(SynchronizationPoints.self, from: data), points)

        for payload in [
            #"{"anchors":[{"leftSourceLine":-1,"rightSourceLine":0}]}"#,
            #"{"anchors":[{"leftSourceLine":1048576,"rightSourceLine":0}]}"#,
            #"{"anchors":[{"leftSourceLine":0,"rightSourceLine":9223372036854775807}]}"#,
            #"{"anchors":[{"leftSourceLine":1,"rightSourceLine":1},{"leftSourceLine":1,"rightSourceLine":2}]}"#,
            #"{"anchors":[{"leftSourceLine":1,"rightSourceLine":2},{"leftSourceLine":2,"rightSourceLine":1}]}"#,
            #"{"anchors":null}"#,
            #"{"anchors":{}}"#,
            #"{"other":[]}"#,
            #"[]"#
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(SynchronizationPoints.self, from: Data(payload.utf8)),
                "Payload unexpectedly decoded: \(payload)"
            )
        }
    }

    func testDecoderAcceptsExactlyMaximumAnchorCount() throws {
        let points = try SynchronizationPoints(
            anchors: try (0..<SynchronizationPoints.maximumAnchorCount).map {
                try point($0, $0)
            }
        )

        let encoded = try JSONEncoder().encode(points)

        XCTAssertEqual(
            try JSONDecoder().decode(SynchronizationPoints.self, from: encoded),
            points
        )
    }

    func testSequenceInitializerBuildsMaximumUnknownCountInLinearOrder() throws {
        let anchors = AnySequence(
            (0..<SynchronizationPoints.maximumAnchorCount).lazy.map { index in
                try! SynchronizationPoint(leftSourceLine: index, rightSourceLine: index)
            }
        )

        let points = try SynchronizationPoints(anchors: anchors)

        XCTAssertEqual(points.count, SynchronizationPoints.maximumAnchorCount)
        XCTAssertEqual(points.anchors.first, try point(0, 0))
        XCTAssertEqual(
            points.anchors.last,
            try point(
                SynchronizationPoints.maximumAnchorCount - 1,
                SynchronizationPoints.maximumAnchorCount - 1
            )
        )
    }

    func testSequenceInitializerRejectsUnknownCountAboveMaximum() throws {
        let anchors = AnySequence(
            (0...SynchronizationPoints.maximumAnchorCount).lazy.map { index in
                try! SynchronizationPoint(leftSourceLine: index, rightSourceLine: index)
            }
        )

        assertSynchronizationError(
            .tooManyAnchors(maximum: SynchronizationPoints.maximumAnchorCount)
        ) {
            try SynchronizationPoints(anchors: anchors)
        }
    }

    func testDecoderBuildsMaximumUnknownCountWithoutMiddleInsertion() throws {
        let anchors = try (0..<SynchronizationPoints.maximumAnchorCount).map {
            try point($0, $0)
        }

        let points = try SynchronizationPoints(
            from: UnknownCountSynchronizationPointsDecoder(anchors: anchors)
        )

        XCTAssertEqual(points.count, SynchronizationPoints.maximumAnchorCount)
        XCTAssertEqual(points.anchors.first, anchors.first)
        XCTAssertEqual(points.anchors.last, anchors.last)
    }

    func testDecoderRejectsUnknownCountIncrementallyAtAnchorCap() throws {
        let anchors = try (0...SynchronizationPoints.maximumAnchorCount).map {
            try point($0, $0)
        }
        let counter = SynchronizationPointDecodeCounter()

        XCTAssertThrowsError(
            try SynchronizationPoints(
                from: UnknownCountSynchronizationPointsDecoder(
                    anchors: anchors,
                    counter: counter
                )
            )
        ) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "anchors")
            XCTAssertTrue(context.debugDescription.contains("anchor limit"))
        }
        XCTAssertEqual(counter.count, SynchronizationPoints.maximumAnchorCount)
    }

    func testDecoderRejectsMonotonicViolationBeforeDecodingFollowingElement() {
        let payload = #"{"anchors":[{"leftSourceLine":1,"rightSourceLine":2},{"leftSourceLine":2,"rightSourceLine":1},false]}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(SynchronizationPoints.self, from: Data(payload.utf8))
        ) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "anchors")
            XCTAssertTrue(context.debugDescription.contains("strictly increasing"))
        }
    }

    func testDecoderRejectsAnchorCountAboveHardLimitBeforeElementValidation() {
        let anchor = #"{"leftSourceLine":0,"rightSourceLine":0}"#
        let payload =
            #"{"anchors":["#
            + String(repeating: anchor + ",", count: SynchronizationPoints.maximumAnchorCount)
            + anchor
            + "]}"

        XCTAssertThrowsError(
            try JSONDecoder().decode(SynchronizationPoints.self, from: Data(payload.utf8))
        ) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "anchors")
            XCTAssertTrue(context.debugDescription.contains("anchor limit"))
        }
    }

    private func point(_ left: Int, _ right: Int) throws -> SynchronizationPoint {
        try SynchronizationPoint(leftSourceLine: left, rightSourceLine: right)
    }

    private func assertSynchronizationError<T>(
        _ expected: SynchronizationPointsError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? SynchronizationPointsError, expected, file: file, line: line)
        }
    }
}

private struct UnknownCountSynchronizationPointsDecoder: Decoder {
    let anchors: [SynchronizationPoint]
    var counter = SynchronizationPointDecodeCounter()
    let codingPath: [any CodingKey] = []
    let userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws
        -> KeyedDecodingContainer<Key>
    {
        KeyedDecodingContainer(
            UnknownCountSynchronizationPointsKeyedContainer<Key>(
                anchors: anchors,
                counter: counter
            )
        )
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw unsupportedDecodingType([Any].self)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw unsupportedDecodingType(SynchronizationPoints.self)
    }
}

private struct UnknownCountSynchronizationPointsKeyedContainer<Key: CodingKey>:
    KeyedDecodingContainerProtocol
{
    let anchors: [SynchronizationPoint]
    let counter: SynchronizationPointDecodeCounter
    let codingPath: [any CodingKey] = []
    var allKeys: [Key] { [] }

    func contains(_ key: Key) -> Bool { key.stringValue == "anchors" }
    func decodeNil(forKey key: Key) throws -> Bool { false }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard key.stringValue == "anchors" else {
            throw DecodingError.keyNotFound(
                key,
                .init(codingPath: codingPath, debugDescription: "Unknown key")
            )
        }
        return UnknownCountSynchronizationPointsUnkeyedContainer(
            anchors: anchors,
            counter: counter,
            codingPath: codingPath + [key]
        )
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        throw unsupportedDecodingType(type, codingPath: codingPath + [key])
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        throw unsupportedDecodingType(type, codingPath: codingPath + [key])
    }

    func superDecoder() throws -> any Decoder {
        throw unsupportedDecodingType(SynchronizationPoints.self, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        throw unsupportedDecodingType(
            SynchronizationPoints.self,
            codingPath: codingPath + [key]
        )
    }
}

private struct UnknownCountSynchronizationPointsUnkeyedContainer:
    UnkeyedDecodingContainer
{
    let anchors: [SynchronizationPoint]
    let counter: SynchronizationPointDecodeCounter
    let codingPath: [any CodingKey]
    var count: Int? { nil }
    var isAtEnd: Bool { currentIndex == anchors.count }
    private(set) var currentIndex = 0

    mutating func decodeNil() throws -> Bool { false }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard currentIndex < anchors.count else {
            throw DecodingError.valueNotFound(
                type,
                .init(codingPath: codingPath, debugDescription: "No remaining anchors")
            )
        }
        guard let anchor = anchors[currentIndex] as? T else {
            throw unsupportedDecodingType(type, codingPath: codingPath)
        }
        currentIndex += 1
        counter.count += 1
        return anchor
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        throw unsupportedDecodingType(type, codingPath: codingPath)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw unsupportedDecodingType([Any].self, codingPath: codingPath)
    }

    mutating func superDecoder() throws -> any Decoder {
        throw unsupportedDecodingType(SynchronizationPoint.self, codingPath: codingPath)
    }
}

private final class SynchronizationPointDecodeCounter {
    var count = 0
}

private func unsupportedDecodingType(
    _ type: Any.Type,
    codingPath: [any CodingKey] = []
) -> DecodingError {
    .typeMismatch(
        type,
        .init(codingPath: codingPath, debugDescription: "Unsupported test decode")
    )
}
