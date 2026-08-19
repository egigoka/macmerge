import XCTest

@testable import MacMergeCore

final class ThreeWayTextMergeTests: XCTestCase {
    func testUnchangedInputsPreserveBaseLinesAndMetadata() throws {
        let text = "alpha\r\nbeta\r\n"

        let result = try merge(base: text, left: text, right: text)

        XCTAssertFalse(result.hasConflicts)
        XCTAssertEqual(result.mergedText, text)
        XCTAssertEqual(result.regions.map(\.resolution), [.unchanged])
        XCTAssertEqual(result.regions[0].baseRange, 0..<2)
        XCTAssertEqual(result.regions[0].leftRange, 0..<2)
        XCTAssertEqual(result.regions[0].rightRange, 0..<2)
        XCTAssertEqual(result.mergedLines?.map(\.source), [.base, .base])
        XCTAssertEqual(result.base.source, .base)
        XCTAssertEqual(result.base.text, text)
        XCTAssertEqual(result.base.predominantLineEnding, .crlf)
        XCTAssertTrue(result.base.hasFinalNewline)
    }

    func testEmptyInputsProduceEmptyMergeWithoutRegions() throws {
        let result = try merge(base: "", left: "", right: "")

        XCTAssertEqual(result.regions, [])
        XCTAssertEqual(result.conflicts, [])
        XCTAssertEqual(result.mergedLines, [])
        XCTAssertEqual(result.mergedText, "")
        XCTAssertFalse(result.hasConflicts)
        XCTAssertNil(result.base.predominantLineEnding)
        XCTAssertFalse(result.base.hasFinalNewline)
    }

    func testOneSideReplacementWinsAndUnchangedLinesRetainBaseIdentity() throws {
        let result = try merge(
            base: "alpha\nbeta\nomega\n",
            left: "alpha\nBETA\nomega\n",
            right: "alpha\nbeta\nomega\n"
        )

        XCTAssertEqual(result.mergedText, "alpha\nBETA\nomega\n")
        XCTAssertEqual(result.regions.map(\.resolution), [.unchanged, .left, .unchanged])
        XCTAssertEqual(result.mergedLines?.map(\.source), [.base, .left, .base])
        XCTAssertEqual(result.mergedLines?.map(\.number), [1, 2, 3])
    }

    func testOneSideInsertionAndDeletionMergeCleanly() throws {
        let insertion = try merge(
            base: "alpha\nomega\n",
            left: "alpha\ninserted\nomega\n",
            right: "alpha\nomega\n"
        )
        XCTAssertEqual(insertion.mergedText, "alpha\ninserted\nomega\n")
        XCTAssertEqual(insertion.regions.map(\.resolution), [.unchanged, .left, .unchanged])
        XCTAssertEqual(insertion.regions[1].baseRange, 1..<1)
        XCTAssertEqual(insertion.regions[1].leftRange, 1..<2)
        XCTAssertEqual(insertion.regions[1].rightRange, 1..<1)

        let deletion = try merge(
            base: "alpha\ndeleted\nomega\n",
            left: "alpha\nomega\n",
            right: "alpha\ndeleted\nomega\n"
        )
        XCTAssertEqual(deletion.mergedText, "alpha\nomega\n")
        XCTAssertEqual(deletion.regions.map(\.resolution), [.unchanged, .left, .unchanged])
        XCTAssertEqual(deletion.regions[1].baseRange, 1..<2)
        XCTAssertEqual(deletion.regions[1].leftRange, 1..<1)
        XCTAssertEqual(deletion.regions[1].rightRange, 1..<2)
    }

    func testIdenticalEditsAreAppliedOnce() throws {
        let result = try merge(
            base: "alpha\nold\nomega\n",
            left: "alpha\nnew\nomega\n",
            right: "alpha\nnew\nomega\n"
        )

        XCTAssertEqual(result.mergedText, "alpha\nnew\nomega\n")
        XCTAssertEqual(result.regions.map(\.resolution), [.unchanged, .identical, .unchanged])
        XCTAssertEqual(result.mergedLines?.map(\.source), [.base, .left, .base])
        XCTAssertEqual(result.mergedLines?.filter { $0.text == "new" }.count, 1)
    }

    func testIndependentReplacementsFromBothSidesMerge() throws {
        let result = try merge(
            base: "alpha\nbeta\ngamma\nomega\n",
            left: "alpha\nBETA\ngamma\nomega\n",
            right: "alpha\nbeta\nGAMMA\nomega\n"
        )

        XCTAssertEqual(result.mergedText, "alpha\nBETA\nGAMMA\nomega\n")
        XCTAssertEqual(result.regions.map(\.resolution), [.unchanged, .left, .right, .unchanged])
        XCTAssertFalse(result.hasConflicts)
    }

    func testOverlappingCompatibleEditsAreSplitIntoResolvableAtoms() throws {
        let result = try merge(
            base: "a\nb\nc\nd\ne\n",
            left: "a\nB\nC\nd\ne\n",
            right: "a\nb\nC\nD\ne\n"
        )

        XCTAssertEqual(result.mergedText, "a\nB\nC\nD\ne\n")
        XCTAssertEqual(
            result.regions.map(\.resolution),
            [.unchanged, .left, .identical, .right, .unchanged]
        )
        XCTAssertEqual(result.mergedLines?.map(\.source), [.base, .left, .left, .right, .base])
    }

    func testOverlappingIncompatibleReplacementsConflict() throws {
        let result = try merge(
            base: "alpha\nbeta\nomega\n",
            left: "alpha\nleft beta\nomega\n",
            right: "alpha\nright beta\nomega\n"
        )

        XCTAssertTrue(result.hasConflicts)
        XCTAssertNil(result.mergedLines)
        XCTAssertNil(result.mergedText)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts[0].resolution, .conflict)
        XCTAssertEqual(result.conflicts[0].baseRange, 1..<2)
        XCTAssertEqual(result.conflicts[0].leftLines.map(\.text), ["left beta"])
        XCTAssertEqual(result.conflicts[0].rightLines.map(\.text), ["right beta"])
        XCTAssertNil(result.conflicts[0].automaticallyMergedLines)
    }

    func testSameBoundaryInsertionAndOpposingReplacementDoNotDuplicateLines() throws {
        let result = try merge(
            base: "alpha\nbeta\nomega\n",
            left: "alpha\ninserted\nbeta\nomega\n",
            right: "alpha\nBETA\nomega\n"
        )

        XCTAssertEqual(result.mergedText, "alpha\ninserted\nBETA\nomega\n")
        XCTAssertEqual(result.mergedLines?.map(\.text), ["alpha", "inserted", "BETA", "omega"])
        XCTAssertEqual(result.mergedLines?.filter { $0.text == "inserted" }.count, 1)
        XCTAssertEqual(result.mergedLines?.filter { $0.text.lowercased() == "beta" }.count, 1)
        XCTAssertFalse(result.hasConflicts)
    }

    func testSharedInsertionAndOpposingReplacementApplyInsertionOnce() throws {
        let result = try merge(base: "A\n", left: "X\nA\n", right: "X\nB\n")

        XCTAssertEqual(result.mergedText, "X\nB\n")
        XCTAssertEqual(result.mergedLines?.map(\.text), ["X", "B"])
        XCTAssertEqual(result.mergedLines?.filter { $0.text == "X" }.count, 1)
        XCTAssertEqual(result.regions.map(\.resolution), [.identical, .right])
        XCTAssertFalse(result.hasConflicts)
    }

    func testSharedBoundaryInsertionAcrossTouchingChangesIsAppliedOnce() throws {
        let result = try merge(
            base: "A\nB\n",
            left: "L\nX\nB\n",
            right: "A\nX\nR\n"
        )

        XCTAssertEqual(result.mergedText, "L\nX\nR\n")
        XCTAssertEqual(result.mergedLines?.map(\.text), ["L", "X", "R"])
        XCTAssertEqual(result.mergedLines?.filter { $0.text == "X" }.count, 1)
        XCTAssertFalse(result.hasConflicts)
    }

    func testSharedBoundaryInsertionAcrossTouchingChangesIsAppliedOnceWhenMirrored() throws {
        let result = try merge(
            base: "A\nB\n",
            left: "A\nX\nR\n",
            right: "L\nX\nB\n"
        )

        XCTAssertEqual(result.mergedText, "L\nX\nR\n")
        XCTAssertEqual(result.mergedLines?.map(\.text), ["L", "X", "R"])
        XCTAssertEqual(result.mergedLines?.map(\.source), [.right, .left, .left])
        XCTAssertFalse(result.hasConflicts)
    }

    func testEqualInsertionAndOneForOneOpposingReplacementRemainIndependent() throws {
        let result = try merge(
            base: "A\r\nB\r\nC",
            left: "L\r\nX\r\nB\r\nC",
            right: "A\r\nX\r\nC"
        )

        XCTAssertEqual(result.mergedText, "L\r\nX\r\nX\r\nC")
        XCTAssertEqual(result.mergedLines?.map(\.text), ["L", "X", "X", "C"])
        XCTAssertEqual(result.mergedLines?.map(\.source), [.left, .left, .right, .base])
        XCTAssertEqual(result.mergedLines?.map(\.number), [1, 2, 2, 3])
        XCTAssertEqual(result.mergedLines?.map(\.lineEnding), [.crlf, .crlf, .crlf, nil])
        XCTAssertFalse(result.hasConflicts)
    }

    func testEqualInsertionAndOneForOneOpposingReplacementRemainIndependentWhenMirrored() throws {
        let result = try merge(
            base: "A\r\nB\r\nC",
            left: "A\r\nX\r\nC",
            right: "L\r\nX\r\nB\r\nC"
        )

        XCTAssertEqual(result.mergedText, "L\r\nX\r\nX\r\nC")
        XCTAssertEqual(result.mergedLines?.map(\.text), ["L", "X", "X", "C"])
        XCTAssertEqual(result.mergedLines?.map(\.source), [.right, .right, .left, .base])
        XCTAssertEqual(result.mergedLines?.map(\.number), [1, 2, 2, 3])
        XCTAssertEqual(result.mergedLines?.map(\.lineEnding), [.crlf, .crlf, .crlf, nil])
        XCTAssertFalse(result.hasConflicts)
    }

    func testEOFInsertionVersusFinalTerminatorRemovalConflicts() throws {
        let result = try merge(
            base: "alpha\nbeta\n",
            left: "alpha\nbeta\ninserted\n",
            right: "alpha\nbeta"
        )

        XCTAssertTrue(result.hasConflicts)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts[0].baseRange, 1..<2)
        XCTAssertEqual(result.conflicts[0].baseLines.map(\.text), ["beta"])
        XCTAssertEqual(result.conflicts[0].leftLines.map(\.text), ["beta", "inserted"])
        XCTAssertEqual(result.conflicts[0].rightLines.map(\.text), ["beta"])
        XCTAssertEqual(result.conflicts[0].leftLines.map(\.lineEnding), [.lf, .lf])
        XCTAssertEqual(result.conflicts[0].rightLines.map(\.lineEnding), [nil])
    }

    func testOverlappingDeletionsMergeAsTheirUnion() throws {
        let result = try merge(
            base: "a\nb\nc\nd\ne\n",
            left: "a\nd\ne\n",
            right: "a\nb\ne\n"
        )

        XCTAssertEqual(result.mergedText, "a\ne\n")
        XCTAssertFalse(result.hasConflicts)
        XCTAssertEqual(
            result.regions.map(\.resolution),
            [.unchanged, .left, .identical, .right, .unchanged]
        )
        XCTAssertEqual(result.regions[1].automaticallyMergedLines, [])
        XCTAssertEqual(result.regions[2].automaticallyMergedLines, [])
        XCTAssertEqual(result.regions[3].automaticallyMergedLines, [])
    }

    func testDeleteVersusModificationConflicts() throws {
        let result = try merge(
            base: "alpha\nbeta\nomega\n",
            left: "alpha\nomega\n",
            right: "alpha\nmodified beta\nomega\n"
        )

        XCTAssertTrue(result.hasConflicts)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts[0].baseLines.map(\.text), ["beta"])
        XCTAssertEqual(result.conflicts[0].leftLines, [])
        XCTAssertEqual(result.conflicts[0].rightLines.map(\.text), ["modified beta"])
    }

    func testModificationVersusDeleteConflicts() throws {
        let result = try merge(
            base: "alpha\nbeta\nomega\n",
            left: "alpha\nmodified beta\nomega\n",
            right: "alpha\nomega\n"
        )

        XCTAssertTrue(result.hasConflicts)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts[0].baseRange, 1..<2)
        XCTAssertEqual(result.conflicts[0].baseLines.map(\.text), ["beta"])
        XCTAssertEqual(result.conflicts[0].leftLines.map(\.text), ["modified beta"])
        XCTAssertEqual(result.conflicts[0].rightLines, [])
    }

    func testRepeatedLineOverlapsRemainCorrectForEveryAlgorithm() throws {
        let algorithms: [DiffAlgorithm] = [.default, .minimal, .patience, .histogram, .none]

        for algorithm in algorithms {
            let compatible = try merge(
                base: "head\nrepeat\nrepeat\ntail\n",
                left: "head\nleft\nrepeat\ntail\n",
                right: "head\nrepeat\nright\ntail\n",
                options: ThreeWayTextMergeOptions(diffAlgorithm: algorithm)
            )
            XCTAssertEqual(
                compatible.mergedText,
                "head\nleft\nright\ntail\n",
                "Algorithm: \(algorithm)"
            )
            XCTAssertFalse(compatible.hasConflicts, "Algorithm: \(algorithm)")
            XCTAssertEqual(
                compatible.regions.map(\.baseRange),
                [0..<1, 1..<2, 2..<3, 3..<4],
                "Algorithm: \(algorithm)"
            )

            let conflict = try merge(
                base: "head\nrepeat\nrepeat\ntail\n",
                left: "head\nrepeat\nleft\ntail\n",
                right: "head\nrepeat\nright\ntail\n",
                options: ThreeWayTextMergeOptions(diffAlgorithm: algorithm)
            )
            XCTAssertEqual(conflict.conflicts.count, 1, "Algorithm: \(algorithm)")
            XCTAssertEqual(conflict.conflicts.first?.baseRange, 2..<3, "Algorithm: \(algorithm)")
            XCTAssertEqual(
                conflict.conflicts.first?.leftLines.map(\.text),
                ["left"],
                "Algorithm: \(algorithm)"
            )
            XCTAssertEqual(
                conflict.conflicts.first?.rightLines.map(\.text),
                ["right"],
                "Algorithm: \(algorithm)"
            )
        }
    }

    func testLineEndingOnlyChangesAreExactEdits() throws {
        let oneSide = try merge(
            base: "alpha\nbeta\n",
            left: "alpha\r\nbeta\r\n",
            right: "alpha\nbeta\n"
        )
        XCTAssertEqual(oneSide.mergedText, "alpha\r\nbeta\r\n")
        XCTAssertEqual(oneSide.regions.map(\.resolution), [.left])
        XCTAssertEqual(oneSide.left.predominantLineEnding, .crlf)

        let identical = try merge(
            base: "alpha\nbeta\n",
            left: "alpha\r\nbeta\r\n",
            right: "alpha\r\nbeta\r\n"
        )
        XCTAssertEqual(identical.mergedText, "alpha\r\nbeta\r\n")
        XCTAssertEqual(identical.regions.map(\.resolution), [.identical])

        let conflict = try merge(
            base: "alpha\nbeta\n",
            left: "alpha\r\nbeta\r\n",
            right: "alpha\rbeta\r"
        )
        XCTAssertTrue(conflict.hasConflicts)
        XCTAssertEqual(conflict.conflicts.count, 2)
        XCTAssertEqual(conflict.conflicts.map(\.baseRange), [0..<1, 1..<2])
        XCTAssertTrue(conflict.conflicts.allSatisfy { $0.leftLines.first?.lineEnding == .crlf })
        XCTAssertTrue(conflict.conflicts.allSatisfy { $0.rightLines.first?.lineEnding == .cr })
    }

    func testFinalNewlineAdditionAndRemovalFollowEditedSide() throws {
        let addition = try merge(base: "alpha", left: "alpha\n", right: "alpha")
        XCTAssertEqual(addition.mergedText, "alpha\n")
        XCTAssertTrue(addition.left.hasFinalNewline)
        XCTAssertFalse(addition.base.hasFinalNewline)

        let removal = try merge(base: "alpha\n", left: "alpha", right: "alpha\n")
        XCTAssertEqual(removal.mergedText, "alpha")
        XCTAssertFalse(removal.left.hasFinalNewline)
        XCTAssertTrue(removal.base.hasFinalNewline)
    }

    func testAgreedFinalNewlineAdditionMergesWithEOFInsertion() throws {
        let result = try merge(base: "a", left: "a\nx", right: "a\n")

        XCTAssertEqual(result.mergedText, "a\nx")
        XCTAssertEqual(result.mergedLines?.map(\.text), ["a", "x"])
        XCTAssertEqual(result.mergedLines?.map(\.lineEnding), [.lf, nil])
        XCTAssertFalse(result.hasConflicts)
    }

    func testMixedLineEndingsAndFinalNewlineArePreservedByteForByte() throws {
        let base = "one\r\ntwo\rthree\nlast"
        let left = "one\r\nTWO\rthree\nlast"
        let right = "one\r\ntwo\rTHREE\nlast"

        let result = try merge(base: base, left: left, right: right)

        XCTAssertEqual(result.mergedText, "one\r\nTWO\rTHREE\nlast")
        XCTAssertEqual(result.mergedLines?.map(\.lineEnding), [.crlf, .cr, .lf, nil])
        XCTAssertFalse(result.base.hasFinalNewline)
        XCTAssertEqual(result.base.predominantLineEnding, .crlf)
    }

    func testConflictCanBeResolvedWithBaseLeftOrRightByRegionID() throws {
        let result = try merge(
            base: "alpha\nbeta\nomega\n",
            left: "alpha\nleft beta\nomega\n",
            right: "alpha\nright beta\nomega\n"
        )
        let conflictID = try XCTUnwrap(result.conflicts.first?.id)

        XCTAssertNil(try result.lines(resolvingConflictsWith: [:]))
        XCTAssertNil(try result.text(resolvingConflictsWith: [conflictID + 100: .left]))
        XCTAssertEqual(
            try result.text(resolvingConflictsWith: [conflictID: .base]),
            "alpha\nbeta\nomega\n"
        )
        XCTAssertEqual(
            try result.text(resolvingConflictsWith: [conflictID: .left]),
            "alpha\nleft beta\nomega\n"
        )
        XCTAssertEqual(
            try result.text(resolvingConflictsWith: [conflictID: .right]),
            "alpha\nright beta\nomega\n"
        )
        XCTAssertEqual(
            try result.lines(resolvingConflictsWith: [conflictID: .right])?.map(\.source),
            [.base, .right, .base]
        )
    }

    func testSeparatedConflictsRequireCompleteChoicesAndApplyMixedChoicesInOrder() throws {
        let result = try merge(
            base: "head\none\nmiddle\ntwo\ntail\n",
            left: "head\nleft one\nmiddle\nleft two\ntail\n",
            right: "head\nright one\nmiddle\nright two\ntail\n"
        )
        XCTAssertEqual(result.conflicts.count, 2)
        let firstID = result.conflicts[0].id
        let secondID = result.conflicts[1].id

        XCTAssertNil(try result.lines(resolvingConflictsWith: [firstID: .left]))
        XCTAssertNil(try result.text(resolvingConflictsWith: [secondID: .right]))
        XCTAssertEqual(
            try result.text(resolvingConflictsWith: [firstID: .left, secondID: .right]),
            "head\nleft one\nmiddle\nright two\ntail\n"
        )
        XCTAssertEqual(
            try result.lines(
                resolvingConflictsWith: [firstID: .right, secondID: .left]
            )?.map(\.source),
            [.base, .right, .base, .left, .base]
        )
    }

    func testRegionIDsRangesAndLineIDsAreStableAndSourceRelative() throws {
        let result = try merge(
            base: "a\nb\nc\n",
            left: "a\ninserted\nb\nc\n",
            right: "a\nb\nC\n"
        )

        XCTAssertEqual(result.regions.map(\.id), Array(result.regions.indices))
        XCTAssertEqual(result.regions.map(\.baseRange), [0..<1, 1..<1, 1..<2, 2..<3])
        XCTAssertEqual(result.regions.map(\.leftRange), [0..<1, 1..<2, 2..<3, 3..<4])
        XCTAssertEqual(result.regions.map(\.rightRange), [0..<1, 1..<1, 1..<2, 2..<3])
        assertLineIDs(result.base.lines, source: .base, numbers: [1, 2, 3])
        assertLineIDs(result.left.lines, source: .left, numbers: [1, 2, 3, 4])
        assertLineIDs(result.right.lines, source: .right, numbers: [1, 2, 3])
    }

    func testInputByteAndLineLimitsReportOffendingSource() throws {
        let byteOptions = ThreeWayTextMergeOptions(maximumInputBytes: 3)
        for source in ThreeWayTextMergeSource.allCases {
            let inputs = inputs(overriding: source, with: "four")
            XCTAssertThrowsError(
                try merge(base: inputs.base, left: inputs.left, right: inputs.right, options: byteOptions)
            ) { error in
                XCTAssertEqual(
                    error as? ThreeWayTextMergeError,
                    .inputTooLarge(source: source, maximumBytes: 3)
                )
            }
        }

        let lineOptions = ThreeWayTextMergeOptions(maximumInputLines: 1)
        for source in ThreeWayTextMergeSource.allCases {
            let inputs = inputs(overriding: source, with: "a\nb\n")
            XCTAssertThrowsError(
                try merge(base: inputs.base, left: inputs.left, right: inputs.right, options: lineOptions)
            ) { error in
                XCTAssertEqual(
                    error as? ThreeWayTextMergeError,
                    .tooManyLines(source: source, maximumLines: 1)
                )
            }
        }
    }

    func testOutputByteLineAndRegionLimitsAreEnforced() throws {
        let base = "a\n"
        let edited = "a\nb\n"

        XCTAssertThrowsError(
            try merge(
                base: base,
                left: edited,
                right: base,
                options: ThreeWayTextMergeOptions(maximumOutputBytes: 3)
            )
        ) { error in
            XCTAssertEqual(error as? ThreeWayTextMergeError, .outputTooLarge(maximumBytes: 3))
        }
        XCTAssertThrowsError(
            try merge(
                base: base,
                left: edited,
                right: base,
                options: ThreeWayTextMergeOptions(maximumOutputLines: 1)
            )
        ) { error in
            XCTAssertEqual(error as? ThreeWayTextMergeError, .tooManyOutputLines(maximumLines: 1))
        }
        XCTAssertThrowsError(
            try merge(
                base: base,
                left: base,
                right: base,
                options: ThreeWayTextMergeOptions(maximumRegions: 0)
            )
        ) { error in
            XCTAssertEqual(error as? ThreeWayTextMergeError, .tooManyRegions(maximumRegions: 0))
        }

        let exact = try merge(
            base: base,
            left: edited,
            right: base,
            options: ThreeWayTextMergeOptions(
                maximumOutputBytes: edited.utf8.count,
                maximumOutputLines: 2,
                maximumRegions: 2
            )
        )
        XCTAssertEqual(exact.mergedText, edited)
    }

    func testConflictCandidateOutputLimitsUseLargestCandidateExactly() throws {
        let base = "old one\nold two\n"
        let left = ""
        let right = "right replacement payload\n"
        let maximumBytes = right.utf8.count

        XCTAssertThrowsError(
            try merge(
                base: base,
                left: left,
                right: right,
                options: ThreeWayTextMergeOptions(
                    maximumOutputBytes: maximumBytes - 1,
                    maximumOutputLines: 2
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayTextMergeError,
                .outputTooLarge(maximumBytes: maximumBytes - 1)
            )
        }
        XCTAssertThrowsError(
            try merge(
                base: base,
                left: left,
                right: right,
                options: ThreeWayTextMergeOptions(
                    maximumOutputBytes: maximumBytes,
                    maximumOutputLines: 1
                )
            )
        ) { error in
            XCTAssertEqual(error as? ThreeWayTextMergeError, .tooManyOutputLines(maximumLines: 1))
        }

        let exact = try merge(
            base: base,
            left: left,
            right: right,
            options: ThreeWayTextMergeOptions(
                maximumOutputBytes: maximumBytes,
                maximumOutputLines: 2
            )
        )
        XCTAssertEqual(exact.conflicts.count, 1)
        XCTAssertEqual(exact.conflicts[0].baseLines.map(\.text), ["old one", "old two"])
        XCTAssertEqual(exact.conflicts[0].leftLines, [])
        XCTAssertEqual(exact.conflicts[0].rightLines.map(\.text), ["right replacement payload"])
    }

    func testAlreadyCancelledTaskStopsMerge() async {
        let task = Task { () throws -> ThreeWayTextMergeResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ThreeWayTextMerge.merge(base: "a\n", left: "a\n", right: "a\n")
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testAlreadyCancelledTaskStopsConflictResolution() async throws {
        let result = try merge(
            base: "alpha\nbeta\nomega\n",
            left: "alpha\nleft beta\nomega\n",
            right: "alpha\nright beta\nomega\n"
        )
        let conflictID = try XCTUnwrap(result.conflicts.first?.id)

        let operations: [@Sendable () throws -> Void] = [
            { _ = try result.lines(resolvingConflictsWith: [conflictID: .left]) },
            { _ = try result.text(resolvingConflictsWith: [conflictID: .right]) }
        ]
        for operation in operations {
            let task = Task { () throws -> Void in
                withUnsafeCurrentTask { $0?.cancel() }
                return try operation()
            }

            do {
                _ = try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {
                // Expected.
            } catch {
                XCTFail("Expected CancellationError, got \(error)")
            }
        }
    }

    private func merge(
        base: String,
        left: String,
        right: String,
        options: ThreeWayTextMergeOptions = ThreeWayTextMergeOptions()
    ) throws -> ThreeWayTextMergeResult {
        try ThreeWayTextMerge.merge(base: base, left: left, right: right, options: options)
    }

    private func inputs(
        overriding source: ThreeWayTextMergeSource,
        with text: String
    ) -> (base: String, left: String, right: String) {
        (
            source == .base ? text : "ok",
            source == .left ? text : "ok",
            source == .right ? text : "ok"
        )
    }

    private func assertLineIDs(
        _ lines: [ThreeWayTextMergeLine],
        source: ThreeWayTextMergeSource,
        numbers: [Int],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lines.map(\.id), numbers.map { .init(source: source, number: $0) }, file: file, line: line)
        XCTAssertEqual(lines.map(\.source), Array(repeating: source, count: numbers.count), file: file, line: line)
        XCTAssertEqual(lines.map(\.number), numbers, file: file, line: line)
    }
}
