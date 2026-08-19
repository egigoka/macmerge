import Foundation
import MacMergeCore
import XCTest

final class ConflictNavigationTests: XCTestCase {
    func testEmptyIndexHasNoNavigationTargets() throws {
        let navigation = try makeNavigation([], generation: 1)

        XCTAssertTrue(navigation.isEmpty)
        XCTAssertEqual(navigation.count, 0)
        XCTAssertNil(navigation.first)
        XCTAssertNil(navigation.last)
        XCTAssertNil(navigation.current(cursorRow: 1))
        XCTAssertNil(navigation.next(cursorRow: 1))
        XCTAssertNil(navigation.previous(cursorRow: 1))
    }

    func testRangesAreSortedAndTargetsUseSourceOrder() throws {
        let navigation = try makeNavigation([20...22, 2...4, 10...12], generation: 7)

        XCTAssertEqual(navigation.generation, 7)
        XCTAssertEqual(navigation.sourceLineRanges, [2...4, 10...12, 20...22])
        XCTAssertEqual(navigation.conflicts.map(\.index), [0, 1, 2])
        XCTAssertEqual(navigation.conflicts.map(\.id.ordinal), [0, 1, 2])
        XCTAssertTrue(navigation.conflicts.allSatisfy { $0.generation == 7 })
    }

    func testInvalidAndOverlappingRangesAreRejectedWithOriginalIndices() throws {
        XCTAssertThrowsError(try makeNavigation([4...5, 0...2], generation: 1)) { error in
            XCTAssertEqual(
                error as? ConflictNavigationError,
                .invalidSourceLineRange(conflictIndex: 1, lowerBound: 0, upperBound: 2)
            )
        }
        XCTAssertThrowsError(try makeNavigation([10...12, 2...5, 5...8], generation: 1)) { error in
            XCTAssertEqual(
                error as? ConflictNavigationError,
                .overlappingSourceLineRanges(firstConflictIndex: 1, secondConflictIndex: 2)
            )
        }

        XCTAssertNoThrow(try makeNavigation([1...3, 4...6], generation: 1))
    }

    func testTargetInitializerRejectsInvalidIndexAndSourceRange() {
        XCTAssertThrowsError(
            try ConflictNavigationTarget(
                generation: 1,
                index: -1,
                sourceLineRange: 1...2,
                topology: .twoWay
            )
        ) { error in
            XCTAssertEqual(error as? ConflictNavigationError, .invalidTargetIndex(-1))
        }
        XCTAssertThrowsError(
            try ConflictNavigationTarget(
                generation: 1,
                index: 3,
                sourceLineRange: 0...2,
                topology: .twoWay
            )
        ) { error in
            XCTAssertEqual(
                error as? ConflictNavigationError,
                .invalidSourceLineRange(conflictIndex: 3, lowerBound: 0, upperBound: 2)
            )
        }
        XCTAssertThrowsError(
            try ConflictNavigationTarget(
                generation: 1,
                index: 4,
                sourceLineRange: -2 ... -1,
                topology: .twoWay
            )
        ) { error in
            XCTAssertEqual(
                error as? ConflictNavigationError,
                .invalidSourceLineRange(conflictIndex: 4, lowerBound: -2, upperBound: -1)
            )
        }
    }

    func testIdenticalParserBackedRebuildPreservesSelectionRoundTrip() throws {
        let firstBuild = try ConflictNavigationIndex(
            parseResult: ConflictFileParser.parse(threeConflictSource),
            generation: 20
        )
        let rebuilt = try ConflictNavigationIndex(
            parseResult: ConflictFileParser.parse(threeConflictSource),
            generation: 20
        )
        let selected = try XCTUnwrap(firstBuild.conflict(at: 1))

        XCTAssertEqual(firstBuild.conflicts.map(\.id), rebuilt.conflicts.map(\.id))
        XCTAssertEqual(rebuilt.current(selectedConflict: selected), rebuilt.conflict(at: 1))
        XCTAssertEqual(rebuilt.next(after: selected), rebuilt.conflict(at: 2))
        XCTAssertEqual(rebuilt.previous(before: selected), rebuilt.conflict(at: 0))
    }

    func testReusedGenerationRejectsEveryChangedConflictMetadataField() throws {
        let originalResult = try ConflictFileParser.parse(threeConflictSource)
        let original = try ConflictNavigationIndex(parseResult: originalResult, generation: 21)
        let selected = try XCTUnwrap(original.conflict(at: 1))
        let originalConflict = originalResult.conflicts[1]
        let changedConflicts = [
            conflict(
                replacing: originalConflict,
                markerWidth: originalConflict.markerWidth + 1
            ),
            conflict(replacing: originalConflict, currentLabel: "changed"),
            conflict(replacing: originalConflict, baseLabel: "changed"),
            conflict(replacing: originalConflict, incomingLabel: "changed")
        ]

        for changedConflict in changedConflicts {
            var conflicts = originalResult.conflicts
            conflicts[1] = changedConflict
            let rebuilt = try ConflictNavigationIndex(
                parseResult: ConflictFileParseResult(
                    currentText: originalResult.currentText,
                    baseText: originalResult.baseText,
                    incomingText: originalResult.incomingText,
                    conflicts: conflicts
                ),
                generation: 21
            )

            XCTAssertEqual(selected.sourceLineRange, rebuilt.conflict(at: 1)?.sourceLineRange)
            XCTAssertNotEqual(selected.id, rebuilt.conflict(at: 1)?.id)
            XCTAssertNil(rebuilt.current(selectedConflict: selected))
            XCTAssertNil(rebuilt.next(after: selected))
            XCTAssertNil(rebuilt.previous(before: selected))
        }
    }

    func testReusedGenerationRejectsChangedRange() throws {
        let originalResult = try ConflictFileParser.parse(threeConflictSource)
        let changedResult = try ConflictFileParser.parse(
            threeConflictSource.replacingOccurrences(
                of: "between\n<<<<<<< ours-two",
                with: "between\nextra\n<<<<<<< ours-two"
            )
        )
        let original = try ConflictNavigationIndex(parseResult: originalResult, generation: 21)
        let rebuilt = try ConflictNavigationIndex(parseResult: changedResult, generation: 21)
        let selected = try XCTUnwrap(original.conflict(at: 1))

        XCTAssertEqual(selected.index, rebuilt.conflict(at: 1)?.index)
        XCTAssertNotEqual(selected.sourceLineRange, rebuilt.conflict(at: 1)?.sourceLineRange)
        XCTAssertNotEqual(selected.id, rebuilt.conflict(at: 1)?.id)
        XCTAssertNil(rebuilt.current(selectedConflict: selected))
        XCTAssertNil(rebuilt.next(after: selected))
        XCTAssertNil(rebuilt.previous(before: selected))
    }

    func testReusedGenerationRejectsChangedOrdinalAtSameRange() throws {
        let original = try makeNavigation([2...4, 8...10], generation: 21)
        let rebuilt = try makeNavigation([1...1, 2...4, 8...10], generation: 21)
        let selected = try XCTUnwrap(original.first)

        XCTAssertEqual(selected.sourceLineRange, rebuilt.conflict(at: 1)?.sourceLineRange)
        XCTAssertNotEqual(selected.index, rebuilt.conflict(at: 1)?.index)
        XCTAssertNotEqual(selected.id, rebuilt.conflict(at: 1)?.id)
        XCTAssertNil(rebuilt.current(selectedConflict: selected))
        XCTAssertNil(rebuilt.next(after: selected))
        XCTAssertNil(rebuilt.previous(before: selected))
    }

    func testReusedGenerationRejectsChangedConflictTopology() throws {
        let twoWay = try ConflictNavigationIndex(
            parseResult: ConflictFileParser.parse(
                ["<<<<<<<", "current", "=======", "incoming", ">>>>>>>"].joined(
                    separator: "\n"
                )
            ),
            generation: 22
        )
        let diff3 = try ConflictNavigationIndex(
            parseResult: ConflictFileParser.parse(
                ["<<<<<<<", "current", "|||||||", "=======", ">>>>>>>"].joined(
                    separator: "\n"
                )
            ),
            generation: 22
        )
        let selected = try XCTUnwrap(twoWay.first)
        let reparsed = try XCTUnwrap(diff3.first)

        XCTAssertEqual(selected.sourceLineRange, reparsed.sourceLineRange)
        XCTAssertEqual(selected.id.currentLabel, reparsed.id.currentLabel)
        XCTAssertEqual(selected.id.baseLabel, reparsed.id.baseLabel)
        XCTAssertEqual(selected.id.incomingLabel, reparsed.id.incomingLabel)
        XCTAssertEqual(selected.id.topology, .twoWay)
        XCTAssertEqual(reparsed.id.topology, .diff3)
        XCTAssertNotEqual(selected.id, reparsed.id)
        XCTAssertNil(diff3.current(selectedConflict: selected))
        XCTAssertNil(diff3.next(after: selected))
        XCTAssertNil(diff3.previous(before: selected))
    }

    func testConflictIdentityTopologyIsCodableAndHashable() throws {
        let navigation = try makeNavigation([2...4], generation: 23)
        let id = try XCTUnwrap(navigation.first?.id)
        let decoded = try JSONDecoder().decode(
            ConflictNavigationTarget.ID.self,
            from: JSONEncoder().encode(id)
        )

        XCTAssertEqual(decoded, id)
        XCTAssertEqual(Set([id, decoded]).count, 1)
        XCTAssertEqual(decoded.topology, .twoWay)
    }

    func testChangedGenerationInvalidatesOtherwiseIdenticalSelection() throws {
        let parseResult = try ConflictFileParser.parse(threeConflictSource)
        let original = try ConflictNavigationIndex(parseResult: parseResult, generation: 22)
        let rebuilt = try ConflictNavigationIndex(parseResult: parseResult, generation: 23)
        let selected = try XCTUnwrap(original.conflict(at: 1))

        XCTAssertEqual(selected.index, rebuilt.conflict(at: 1)?.index)
        XCTAssertEqual(selected.sourceLineRange, rebuilt.conflict(at: 1)?.sourceLineRange)
        XCTAssertNotEqual(selected.id, rebuilt.conflict(at: 1)?.id)
        XCTAssertNil(rebuilt.current(selectedConflict: selected))
        XCTAssertNil(rebuilt.next(after: selected))
        XCTAssertNil(rebuilt.previous(before: selected))
    }

    func testCurrentUsesSelectionThenCursorContainment() throws {
        let navigation = try makeNavigation([2...4, 8...10], generation: 3)
        let selected = try XCTUnwrap(navigation.conflict(at: 1))

        XCTAssertEqual(navigation.current(selectedConflict: selected, cursorRow: 3), selected)
        XCTAssertEqual(navigation.current(cursorRow: 2)?.index, 0)
        XCTAssertEqual(navigation.current(cursorRow: 4)?.index, 0)
        XCTAssertEqual(navigation.current(cursorRow: 8)?.index, 1)
        XCTAssertEqual(navigation.current(cursorRow: 10)?.index, 1)
        XCTAssertNil(navigation.current(cursorRow: 1))
        XCTAssertNil(navigation.current(cursorRow: 5))
        XCTAssertNil(navigation.current(cursorRow: 11))
    }

    func testNextAndPreviousHonorBoundariesWithoutWrapping() throws {
        let navigation = try makeNavigation([2...4, 8...10, 15...18], generation: 4)
        let first = try XCTUnwrap(navigation.first)
        let middle = try XCTUnwrap(navigation.conflict(at: 1))
        let last = try XCTUnwrap(navigation.last)

        XCTAssertEqual(navigation.next(), first)
        XCTAssertEqual(navigation.next(after: first), middle)
        XCTAssertEqual(navigation.next(after: middle), last)
        XCTAssertNil(navigation.next(after: last))
        XCTAssertEqual(navigation.next(cursorRow: 4), middle)
        XCTAssertEqual(navigation.next(cursorRow: 8), middle)
        XCTAssertNil(navigation.next(cursorRow: 19))

        XCTAssertEqual(navigation.previous(), last)
        XCTAssertEqual(navigation.previous(before: last), middle)
        XCTAssertEqual(navigation.previous(before: middle), first)
        XCTAssertNil(navigation.previous(before: first))
        XCTAssertEqual(navigation.previous(cursorRow: 8), first)
        XCTAssertEqual(navigation.previous(cursorRow: 10), middle)
        XCTAssertNil(navigation.previous(cursorRow: 1))
    }

    func testNoWrapBoundariesOverrideCursorFallbackForValidSelections() throws {
        let navigation = try makeNavigation([2...4, 8...10], generation: 5)
        let first = try XCTUnwrap(navigation.first)
        let last = try XCTUnwrap(navigation.last)

        XCTAssertNil(navigation.next(after: last, cursorRow: 1))
        XCTAssertNil(navigation.previous(before: first, cursorRow: .max))
        XCTAssertNil(navigation.next(cursorRow: 11))
        XCTAssertNil(navigation.previous(cursorRow: 1))
    }

    func testStaleIdentityGenerationRangeAndOrdinalAreRejected() throws {
        let navigation = try makeNavigation([2...4, 8...10], generation: 12)
        let selected = try XCTUnwrap(navigation.first)
        let staleTargets = [
            try ConflictNavigationTarget(
                generation: selected.generation,
                index: selected.index,
                sourceLineRange: selected.sourceLineRange,
                markerWidth: selected.id.markerWidth,
                topology: selected.id.topology,
                currentLabel: "changed",
                baseLabel: selected.id.baseLabel,
                incomingLabel: selected.id.incomingLabel
            ),
            try ConflictNavigationTarget(
                generation: selected.generation + 1,
                index: selected.index,
                sourceLineRange: selected.sourceLineRange,
                markerWidth: selected.id.markerWidth,
                topology: selected.id.topology,
                currentLabel: selected.id.currentLabel,
                baseLabel: selected.id.baseLabel,
                incomingLabel: selected.id.incomingLabel
            ),
            try ConflictNavigationTarget(
                generation: selected.generation,
                index: selected.index,
                sourceLineRange: 3...5,
                markerWidth: selected.id.markerWidth,
                topology: selected.id.topology,
                currentLabel: selected.id.currentLabel,
                baseLabel: selected.id.baseLabel,
                incomingLabel: selected.id.incomingLabel
            ),
            try ConflictNavigationTarget(
                generation: selected.generation,
                index: 1,
                sourceLineRange: selected.sourceLineRange,
                markerWidth: selected.id.markerWidth,
                topology: selected.id.topology,
                currentLabel: selected.id.currentLabel,
                baseLabel: selected.id.baseLabel,
                incomingLabel: selected.id.incomingLabel
            )
        ]

        for staleTarget in staleTargets {
            XCTAssertNil(navigation.current(selectedConflict: staleTarget))
            XCTAssertNil(navigation.next(after: staleTarget))
            XCTAssertNil(navigation.previous(before: staleTarget))
        }
    }

    func testInvalidSelectionUsesExplicitCursorFallbackWithoutRestarting() throws {
        let navigation = try makeNavigation([2...4, 8...10, 15...18], generation: 13)
        let selected = try XCTUnwrap(navigation.first)
        let staleSelection = try ConflictNavigationTarget(
            generation: selected.generation + 1,
            index: selected.index,
            sourceLineRange: selected.sourceLineRange,
            markerWidth: selected.id.markerWidth,
            topology: selected.id.topology,
            currentLabel: selected.id.currentLabel,
            baseLabel: selected.id.baseLabel,
            incomingLabel: selected.id.incomingLabel
        )

        XCTAssertNil(navigation.current(selectedConflict: staleSelection))
        XCTAssertNil(navigation.next(after: staleSelection))
        XCTAssertNil(navigation.previous(before: staleSelection))

        XCTAssertEqual(
            navigation.current(selectedConflict: staleSelection, cursorRow: 9)?.index,
            1
        )
        XCTAssertEqual(navigation.next(after: staleSelection, cursorRow: 5)?.index, 1)
        XCTAssertEqual(navigation.previous(before: staleSelection, cursorRow: 14)?.index, 1)
        XCTAssertNil(navigation.next(after: staleSelection, cursorRow: 19))
        XCTAssertNil(navigation.previous(before: staleSelection, cursorRow: 1))
    }

    func testParserRangesSupportEmptyConflictArmsAndGapInsertionNavigation() throws {
        let parseResult = try ConflictFileParser.parse(
            [
                "before",
                "<<<<<<< ours",
                "=======",
                ">>>>>>> theirs",
                "between",
                "<<<<<<< ours-again",
                "=======",
                ">>>>>>> theirs-again",
                "after"
            ].joined(separator: "\n")
        )
        let navigation = try ConflictNavigationIndex(parseResult: parseResult, generation: 14)

        XCTAssertEqual(navigation.sourceLineRanges, [2...4, 6...8])
        XCTAssertNil(navigation.current(cursorRow: 5))
        XCTAssertEqual(navigation.next(cursorRow: 5)?.sourceLineRange, 6...8)
        XCTAssertEqual(navigation.previous(cursorRow: 5)?.sourceLineRange, 2...4)
    }

    func testExtremeRowsAndRangesDoNotOverflowNavigation() throws {
        let navigation = try makeNavigation([1...1, Int.max...Int.max], generation: .max)

        XCTAssertNil(navigation.current(cursorRow: Int.min))
        XCTAssertEqual(navigation.current(cursorRow: Int.max)?.sourceLineRange, Int.max...Int.max)
        XCTAssertEqual(navigation.next(cursorRow: Int.min), navigation.first)
        XCTAssertEqual(navigation.next(cursorRow: Int.max), navigation.last)
        XCTAssertNil(navigation.previous(cursorRow: Int.min))
        XCTAssertEqual(navigation.previous(cursorRow: Int.max), navigation.last)
    }

    private func makeNavigation(
        _ ranges: [ClosedRange<Int>],
        generation: UInt64
    ) throws -> ConflictNavigationIndex {
        let conflicts = ranges.map { range in
            ConflictFileConflict(
                sourceLineRange: range,
                markerWidth: 7,
                currentLabel: nil,
                baseLabel: nil,
                incomingLabel: nil
            )
        }
        return try ConflictNavigationIndex(
            parseResult: ConflictFileParseResult(
                currentText: "",
                baseText: nil,
                incomingText: "",
                conflicts: conflicts
            ),
            generation: generation
        )
    }

    private func conflict(
        replacing conflict: ConflictFileConflict,
        markerWidth: Int? = nil,
        currentLabel: String? = nil,
        baseLabel: String? = nil,
        incomingLabel: String? = nil
    ) -> ConflictFileConflict {
        ConflictFileConflict(
            sourceLineRange: conflict.sourceLineRange,
            markerWidth: markerWidth ?? conflict.markerWidth,
            currentLabel: currentLabel ?? conflict.currentLabel,
            baseLabel: baseLabel ?? conflict.baseLabel,
            incomingLabel: incomingLabel ?? conflict.incomingLabel
        )
    }

    private var threeConflictSource: String {
        [
            "before",
            "<<<<<<< ours-one",
            "left one",
            "=======",
            "right one",
            ">>>>>>> theirs-one",
            "between",
            "<<<<<<< ours-two",
            "left two",
            "=======",
            "right two",
            ">>>>>>> theirs-two",
            "between again",
            "<<<<<<< ours-three",
            "left three",
            "=======",
            "right three",
            ">>>>>>> theirs-three",
            "after"
        ].joined(separator: "\n")
    }
}
