import Foundation
import MacMergeCore
import XCTest

private actor StartProbe {
    private var started = false

    func markStarted() {
        started = true
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }
}

final class IntraLineDifferenceWorkflowTests: XCTestCase {
    private typealias Workflow = IntraLineDifferenceWorkflow
    private typealias WorkflowError = IntraLineDifferenceWorkflowError

    func testTwoWayBindingUsesAuthoritativeRowIndexIdentityLineNumbersAndDirection() throws {
        let rows = [
            DiffRow(
                left: DiffLine(number: 8, text: "prefix"),
                right: DiffLine(number: 9, text: "prefix"),
                kind: .unchanged
            ),
            DiffRow(
                left: DiffLine(number: 12, text: "left"),
                right: DiffLine(number: 17, text: "right"),
                kind: .modified
            )
        ]
        let binding = try IntraLineDifferenceTwoWayRowBinding(
            alignedRows: rows,
            rowID: DiffRow.ID(leftNumber: 12, rightNumber: 17)
        )
        let comparison = IntraLineDifferenceComparisonReference(identity: uuid(1), revision: 41)
        let left = snapshot("left", role: .left, line: 12, identity: uuid(2), revision: 42)
        let right = snapshot("right", role: .right, line: 17, identity: uuid(3), revision: 43)

        let forward = IntraLineDifferencePairInput.twoWay(
            comparison: comparison,
            row: binding,
            pair: .leftRight,
            left: left,
            right: right
        )
        XCTAssertEqual(binding.rowIndex, 1)
        XCTAssertEqual(forward.row.rowIndex, 1)
        XCTAssertEqual(forward.row.comparison, comparison)
        XCTAssertEqual(
            forward.row.identity,
            .twoWay(id: DiffRow.ID(leftNumber: 12, rightNumber: 17), kind: .modified)
        )
        XCTAssertEqual(forward.source?.reference, left.reference)
        XCTAssertEqual(forward.comparison?.reference, right.reference)
        let forwardPlan = try Workflow.plan(forward)
        XCTAssertEqual(forwardPlan.source?.reference, left.reference)
        XCTAssertEqual(forwardPlan.comparison?.reference, right.reference)
        assertChanges(
            forwardPlan,
            [(.replace, NSRange(location: 0, length: 4), NSRange(location: 0, length: 5))]
        )

        let reverse = IntraLineDifferencePairInput.twoWay(
            comparison: comparison,
            row: binding,
            pair: .rightLeft,
            left: left,
            right: right
        )
        XCTAssertEqual(reverse.source?.reference, right.reference)
        XCTAssertEqual(reverse.comparison?.reference, left.reference)
        let reversePlan = try Workflow.plan(reverse)
        XCTAssertEqual(reversePlan.pairKind, .twoWay(.rightLeft))
        XCTAssertEqual(reversePlan.source?.reference, right.reference)
        XCTAssertEqual(reversePlan.comparison?.reference, left.reference)
        assertChanges(
            reversePlan,
            [(.replace, NSRange(location: 0, length: 5), NSRange(location: 0, length: 4))]
        )

        assertWorkflowError(.rowIdentityMismatch) {
            _ = try IntraLineDifferenceTwoWayRowBinding(
                alignedRows: [rows[1], rows[1]],
                rowID: rows[1].id
            )
        }
        assertWorkflowError(.invalidRowIndex) {
            _ = try IntraLineDifferenceTwoWayRowBinding(
                alignedRows: rows,
                rowID: DiffRow.ID(leftNumber: 999, rightNumber: 999)
            )
        }
        assertWorkflowError(.rowIdentityMismatch) {
            _ = try Workflow.plan(
                .twoWay(
                    comparison: comparison,
                    row: binding,
                    left: snapshot("left", role: .left, line: 13),
                    right: right
                )
            )
        }
        assertWorkflowError(.invalidPairRoles) {
            _ = try Workflow.plan(
                .twoWay(
                    comparison: comparison,
                    row: binding,
                    left: snapshot("left", role: .right, line: 12),
                    right: right
                )
            )
        }
        assertWorkflowError(.rowIdentityMismatch) {
            _ = try Workflow.plan(
                .twoWay(
                    comparison: comparison,
                    row: binding,
                    left: snapshot("forged", role: .left, line: 12),
                    right: right
                )
            )
        }
        assertWorkflowError(.invalidSourceLineNumber) {
            _ = try Workflow.plan(
                .twoWay(
                    comparison: comparison,
                    row: binding,
                    left: snapshot("left", role: .left, line: 0),
                    right: right
                )
            )
        }

        let malformedRows = [
            DiffRow(left: nil, right: DiffLine(number: 1, text: "right"), kind: .modified),
            DiffRow(
                left: DiffLine(number: 1, text: "left"),
                right: DiffLine(number: 1, text: "right"),
                kind: .added
            ),
            DiffRow(
                left: DiffLine(number: 1, text: "left"),
                right: DiffLine(number: 1, text: "right"),
                kind: .removed
            )
        ]
        for row in malformedRows {
            let malformedBinding = try IntraLineDifferenceTwoWayRowBinding(
                alignedRows: [row],
                rowID: row.id
            )
            assertWorkflowError(.rowIdentityMismatch) {
                _ = try Workflow.plan(
                    .twoWay(
                        comparison: comparison,
                        row: malformedBinding,
                        left: row.left.map {
                            snapshot($0.text, role: .left, line: $0.number)
                        },
                        right: row.right.map {
                            snapshot($0.text, role: .right, line: $0.number)
                        }
                    )
                )
            }
        }
    }

    func testThreeWayBindingUsesAuthoritativeRegionIndexAndSourceLineIDsForEveryPair() throws {
        let merge = try ThreeWayTextMerge.merge(
            base: "first\nsecond",
            left: "first\nsecond",
            right: "first\nsecond"
        )
        let region = try XCTUnwrap(
            merge.regions.first {
                $0.baseLines.count == 2 && $0.leftLines.count == 2 && $0.rightLines.count == 2
            }
        )
        let baseLine = region.baseLines[1]
        let leftLine = region.leftLines[1]
        let rightLine = region.rightLines[1]
        let binding = try IntraLineDifferenceThreeWayRowBinding(region: region, row: leftLine)
        let comparison = IntraLineDifferenceComparisonReference(identity: uuid(4), revision: 50)
        let base = IntraLineDifferenceTextSnapshot(identity: uuid(5), revision: 51, line: baseLine)
        let left = IntraLineDifferenceTextSnapshot(identity: uuid(6), revision: 52, line: leftLine)
        let right = IntraLineDifferenceTextSnapshot(identity: uuid(7), revision: 53, line: rightLine)

        XCTAssertEqual(binding.regionID, region.id)
        XCTAssertEqual(binding.rowIndex, 1)
        for row in [baseLine, leftLine, rightLine] {
            let roleBinding = try IntraLineDifferenceThreeWayRowBinding(region: region, row: row)
            XCTAssertEqual(roleBinding.regionID, region.id)
            XCTAssertEqual(roleBinding.rowIndex, 1)
        }
        let roleCases:
            [(
                pair: IntraLineDifferenceThreeWayPair,
                source: IntraLineDifferenceTextSnapshot,
                comparison: IntraLineDifferenceTextSnapshot,
                sourceID: ThreeWayTextMergeLine.ID,
                comparisonID: ThreeWayTextMergeLine.ID
            )] = [
                (.baseLeft, base, left, baseLine.id, leftLine.id),
                (.baseRight, base, right, baseLine.id, rightLine.id),
                (.leftRight, left, right, leftLine.id, rightLine.id)
            ]
        for roleCase in roleCases {
            let input = IntraLineDifferencePairInput.threeWay(
                comparison: comparison,
                row: binding,
                pair: roleCase.pair,
                base: base,
                left: left,
                right: right
            )
            XCTAssertEqual(input.row.rowIndex, binding.rowIndex)
            XCTAssertEqual(input.source?.reference, roleCase.source.reference)
            XCTAssertEqual(input.comparison?.reference, roleCase.comparison.reference)
            let plan = try Workflow.plan(input)
            XCTAssertEqual(plan.pairKind, .threeWay(roleCase.pair))
            XCTAssertEqual(plan.source?.reference, roleCase.source.reference)
            XCTAssertEqual(plan.comparison?.reference, roleCase.comparison.reference)
            guard case .threeWay(let regionID, let sourceID, let comparisonID) = input.row.identity
            else {
                return XCTFail("Expected three-way identity")
            }
            XCTAssertEqual(regionID, region.id)
            XCTAssertEqual(sourceID, roleCase.sourceID)
            XCTAssertEqual(comparisonID, roleCase.comparisonID)
        }

        assertWorkflowError(.rowIdentityMismatch) {
            _ = try Workflow.plan(
                .threeWay(
                    comparison: comparison,
                    row: binding,
                    pair: .baseLeft,
                    base: snapshot("second", role: .base, line: baseLine.number + 1),
                    left: left,
                    right: right
                )
            )
        }
        assertWorkflowError(.invalidPairRoles) {
            _ = try Workflow.plan(
                .threeWay(
                    comparison: comparison,
                    row: binding,
                    pair: .baseLeft,
                    base: snapshot("second", role: .right, line: baseLine.number),
                    left: left,
                    right: right
                )
            )
        }
    }

    func testThreeWayUnequalRegionBindsMissingAlignedLinesExactly() throws {
        let merge = try ThreeWayTextMerge.merge(
            base: "same\nold\ntail",
            left: "same\nleft-one\nleft-two\ntail",
            right: "same\nold\ntail"
        )
        let region = try XCTUnwrap(
            merge.regions.first { $0.leftLines.contains { $0.text == "left-two" } }
        )
        let leftLine = try XCTUnwrap(region.leftLines.first { $0.text == "left-two" })
        let binding = try IntraLineDifferenceThreeWayRowBinding(region: region, row: leftLine)
        XCTAssertEqual(binding.rowIndex, 1)
        let left = IntraLineDifferenceTextSnapshot(identity: uuid(30), revision: 90, line: leftLine)
        let comparison = IntraLineDifferenceComparisonReference(identity: uuid(31), revision: 91)

        let insertionInput = IntraLineDifferencePairInput.threeWay(
            comparison: comparison,
            row: binding,
            pair: .baseLeft,
            base: nil,
            left: left,
            right: nil
        )
        XCTAssertEqual(
            insertionInput.row.identity,
            .threeWay(regionID: region.id, sourceLine: nil, comparisonLine: leftLine.id)
        )
        assertChanges(
            try Workflow.plan(insertionInput),
            [(.insert, nil, NSRange(location: 0, length: leftLine.text.utf16.count))]
        )

        let deletionInput = IntraLineDifferencePairInput.threeWay(
            comparison: comparison,
            row: binding,
            pair: .leftRight,
            base: nil,
            left: left,
            right: nil
        )
        XCTAssertEqual(
            deletionInput.row.identity,
            .threeWay(regionID: region.id, sourceLine: leftLine.id, comparisonLine: nil)
        )
        assertChanges(
            try Workflow.plan(deletionInput),
            [(.delete, NSRange(location: 0, length: leftLine.text.utf16.count), nil)]
        )

        assertWorkflowError(.rowIdentityMismatch) {
            _ = try Workflow.plan(
                .threeWay(
                    comparison: comparison,
                    row: binding,
                    pair: .baseLeft,
                    base: snapshot("forged", role: .base, line: leftLine.number),
                    left: left,
                    right: nil
                )
            )
        }
    }

    func testCharacterAndWordModesProduceIndependentExactRanges() throws {
        let character = try plan(
            "ab cd",
            "ax yd",
            options: options(granularity: .character)
        )
        assertChanges(
            character,
            [
                (.replace, NSRange(location: 1, length: 1), NSRange(location: 1, length: 1)),
                (.replace, NSRange(location: 3, length: 1), NSRange(location: 3, length: 1))
            ]
        )

        let word = try plan("ab cd", "ax yd", options: options(granularity: .word))
        assertChanges(
            word,
            [
                (.replace, NSRange(location: 0, length: 2), NSRange(location: 0, length: 2)),
                (.replace, NSRange(location: 3, length: 2), NSRange(location: 3, length: 2))
            ]
        )
    }

    func testEmojiZWJCombiningMarksAndVariationSelectorsUseWholeUTF16Graphemes() throws {
        let cases: [(String, String, NSRange, NSRange)] = [
            ("a😀b", "a😃b", NSRange(location: 1, length: 2), NSRange(location: 1, length: 2)),
            (
                "a👨‍👩‍👧b",
                "a👨‍👩‍👦b",
                NSRange(location: 1, length: 8),
                NSRange(location: 1, length: 8)
            ),
            ("ae\u{301}b", "ao\u{308}b", NSRange(location: 1, length: 2), NSRange(location: 1, length: 2)),
            ("a✈️b", "a☂️b", NSRange(location: 1, length: 2), NSRange(location: 1, length: 2))
        ]
        for (source, comparison, sourceRange, comparisonRange) in cases {
            let result = try plan(source, comparison, options: options(granularity: .character))
            assertChanges(result, [(.replace, sourceRange, comparisonRange)])
            assertGraphemeSafe(result, source: source, comparison: comparison)
        }

        assertChanges(
            try plan("😀a", "😀xa", options: options(granularity: .character)),
            [(.insert, NSRange(location: 2, length: 0), NSRange(location: 2, length: 1))]
        )
        assertChanges(
            try plan("😀xa", "😀a", options: options(granularity: .character)),
            [(.delete, NSRange(location: 2, length: 1), NSRange(location: 2, length: 0))]
        )
        let canonicallyEquivalent = try plan(
            "aéb",
            "ae\u{301}b",
            options: options(granularity: .character)
        )
        assertChanges(
            canonicallyEquivalent,
            [(.replace, NSRange(location: 1, length: 1), NSRange(location: 1, length: 2))]
        )
        assertGraphemeSafe(canonicallyEquivalent, source: "aéb", comparison: "ae\u{301}b")

        let supplementarySelectors = try plan(
            "a一\u{E0100}b",
            "a一\u{E0101}b",
            options: options(granularity: .character)
        )
        assertChanges(
            supplementarySelectors,
            [(.replace, NSRange(location: 1, length: 3), NSRange(location: 1, length: 3))]
        )
        assertGraphemeSafe(
            supplementarySelectors,
            source: "a一\u{E0100}b",
            comparison: "a一\u{E0101}b"
        )

        let joinControls = try plan(
            "A\u{200C}",
            "A\u{200D}",
            options: options(granularity: .character)
        )
        assertChanges(
            joinControls,
            [(.replace, NSRange(location: 0, length: 2), NSRange(location: 0, length: 2))]
        )
        assertGraphemeSafe(joinControls, source: "A\u{200C}", comparison: "A\u{200D}")
    }

    func testDependentOnlyGraphemesRemainComparableAndGraphemeSafe() throws {
        let combining = try plan(
            "\u{301}A",
            "\u{308}A",
            options: options(granularity: .character)
        )
        assertChanges(
            combining,
            [(.replace, NSRange(location: 0, length: 1), NSRange(location: 0, length: 1))]
        )
        assertGraphemeSafe(combining, source: "\u{301}A", comparison: "\u{308}A")

        let selector = try plan(
            "\u{FE0E}A",
            "\u{FE0F}A",
            options: options(granularity: .character)
        )
        assertChanges(
            selector,
            [(.replace, NSRange(location: 0, length: 1), NSRange(location: 0, length: 1))]
        )
        assertGraphemeSafe(selector, source: "\u{FE0E}A", comparison: "\u{FE0F}A")
    }

    func testWhitespaceModesCompareIgnoreChangesAndIgnoreAllIndependently() throws {
        XCTAssertTrue(try plan("a b", "a\tb").hasDifferences)
        XCTAssertFalse(
            try plan("a  b", "a\tb", options: options(whitespace: .ignoreChanges))
                .hasDifferences
        )
        XCTAssertFalse(
            try plan("a b", "ab", options: options(whitespace: .ignoreAll)).hasDifferences
        )
        for whitespace in ["\u{000B}", "\u{000C}"] {
            XCTAssertFalse(
                try plan("a\(whitespace)b", "ab", options: options(whitespace: .ignoreAll))
                    .hasDifferences
            )
        }
        XCTAssertTrue(
            try plan("a\u{00A0}b", "ab", options: options(whitespace: .ignoreAll))
                .hasDifferences
        )
    }

    func testIgnoredNumbersCaseAndPunctuationAreIndependent() throws {
        XCTAssertFalse(try plan("item12", "item98", options: options(ignoreNumbers: true)).hasDifferences)
        XCTAssertTrue(try plan("item12", "item98").hasDifferences)
        XCTAssertFalse(try plan("Alpha", "aLPHA", options: options(ignoreCase: true)).hasDifferences)
        XCTAssertTrue(try plan("Alpha", "aLPHA").hasDifferences)
        XCTAssertFalse(
            try plan("a-b!", "ab", options: options(punctuation: .ignoreAll)).hasDifferences
        )
        XCTAssertTrue(try plan("a-b!", "ab").hasDifferences)
        assertChanges(
            try plan(
                "A١B",
                "A٢B",
                options: options(granularity: .character, ignoreNumbers: true)
            ),
            [(.replace, NSRange(location: 1, length: 1), NSRange(location: 1, length: 1))]
        )

        let everyPunctuationCategory = "A_‐()‘’!B"
        XCTAssertFalse(
            try plan(
                everyPunctuationCategory,
                "AB",
                options: options(
                    granularity: .character,
                    punctuation: .ignoreAll
                )
            ).hasDifferences
        )
    }

    func testCustomWordBreakCharactersSplitWordsAndRequireCustomMode() throws {
        let custom = options(
            granularity: .word,
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: "+"
        )
        let split = try plan("abc+def", "abc+xyz", options: custom)
        assertChanges(
            split,
            [(.replace, NSRange(location: 4, length: 3), NSRange(location: 4, length: 3))]
        )

        let unsplit = try plan("abc+def", "abc+xyz", options: options(granularity: .word))
        assertChanges(
            unsplit,
            [(.replace, NSRange(location: 0, length: 7), NSRange(location: 0, length: 7))]
        )
        assertWorkflowError(.inconsistentWordBreakConfiguration) {
            _ = try self.plan(
                "abc+def",
                "abc+xyz",
                options: self.options(wordBreakCharacters: "+")
            )
        }

        let composedBreak = options(
            granularity: .word,
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: "é"
        )
        assertChanges(
            try plan("abcédef", "abcéxyz", options: composedBreak),
            [(.replace, NSRange(location: 4, length: 3), NSRange(location: 4, length: 3))]
        )
        assertChanges(
            try plan("abce\u{301}def", "abce\u{301}xyz", options: composedBreak),
            [(.replace, NSRange(location: 0, length: 8), NSRange(location: 0, length: 8))]
        )

        let foldedBreak = options(
            granularity: .word,
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: "X",
            ignoreCase: true
        )
        assertChanges(
            try plan("abcxdef", "abcxghi", options: foldedBreak),
            [(.replace, NSRange(location: 4, length: 3), NSRange(location: 4, length: 3))]
        )
    }

    func testIgnoreCaseUsesPOSIXUnicodeFolding() throws {
        let pairs = [
            ("Straße", "STRASSE"),
            ("Σ", "ς"),
            ("İ", "i\u{307}")
        ]
        for (source, comparison) in pairs {
            XCTAssertFalse(
                try plan(source, comparison, options: options(ignoreCase: true)).hasDifferences
            )
            XCTAssertTrue(try plan(source, comparison).hasDifferences)
        }

        assertChanges(
            try plan("Straße X", "STRASSE Y", options: options(ignoreCase: true)),
            [(.replace, NSRange(location: 7, length: 1), NSRange(location: 8, length: 1))]
        )
    }

    func testIgnoredLeadingInteriorAndTrailingGapsChooseExactInsertionAnchors() throws {
        let ignored = options(granularity: .character, whitespace: .ignoreAll)
        let cases: [(String, String, NSRange, NSRange)] = [
            (" a", " x a", NSRange(location: 1, length: 0), NSRange(location: 1, length: 1)),
            ("a b", "a x b", NSRange(location: 2, length: 0), NSRange(location: 2, length: 1)),
            ("a ", "a x ", NSRange(location: 2, length: 0), NSRange(location: 2, length: 1))
        ]
        for (source, comparison, sourceRange, comparisonRange) in cases {
            let result = try plan(source, comparison, options: ignored)
            assertChanges(result, [(.insert, sourceRange, comparisonRange)])
            assertChanges(
                try plan(comparison, source, options: ignored),
                [(.delete, comparisonRange, sourceRange)]
            )
        }
    }

    func testTrailingJoinControlsAreRetainedOnlyWithRetainedBase() throws {
        let ignoredNumbers = options(granularity: .character, ignoreNumbers: true)
        XCTAssertFalse(try plan("A1‍", "A", options: ignoredNumbers).hasDifferences)

        let retained = try plan("A‍", "A", options: ignoredNumbers)
        assertChanges(
            retained,
            [(.replace, NSRange(location: 0, length: 2), NSRange(location: 0, length: 1))]
        )
        assertGraphemeSafe(retained, source: "A‍", comparison: "A")
    }

    func testCommonSuffixBeyondLookaheadIsRecoveredExactly() throws {
        let suffix = String(repeating: "s", count: 300)
        let result = try plan(
            "A" + suffix,
            "B" + suffix,
            options: options(granularity: .character),
            limits: limits(alignmentLookahead: 1)
        )
        assertChanges(
            result,
            [(.replace, NSRange(location: 0, length: 1), NSRange(location: 0, length: 1))]
        )
    }

    func testBoundedDPFindsMinimalAxybcdToBcadEdits() throws {
        let result = try plan(
            "axybcd",
            "bcad",
            options: options(granularity: .character),
            limits: limits(alignmentLookahead: 8)
        )
        assertChanges(
            result,
            [
                (.delete, NSRange(location: 0, length: 3), NSRange(location: 0, length: 0)),
                (.insert, NSRange(location: 5, length: 0), NSRange(location: 2, length: 1))
            ]
        )
    }

    func testBoundedDPDoesNotCreateSpuriousXYAToAZWAnchor() throws {
        let result = try plan(
            "xyA",
            "Azw",
            options: options(granularity: .character),
            limits: limits(alignmentLookahead: 8)
        )
        assertChanges(
            result,
            [(.replace, NSRange(location: 0, length: 3), NSRange(location: 0, length: 3))]
        )
    }

    func testBoundedDPMatchesIndependentLevenshteinMinimumForShortInputs() throws {
        let inputs = strings(alphabet: ["a", "b"], maximumLength: 4)
        for source in inputs {
            for comparison in inputs {
                let result = try plan(
                    source,
                    comparison,
                    options: options(granularity: .character),
                    limits: limits(alignmentLookahead: 4)
                )
                let actualCost = result.changes.reduce(into: 0) { cost, change in
                    cost += max(
                        change.sourceUTF16Range?.length ?? 0,
                        change.comparisonUTF16Range?.length ?? 0
                    )
                }
                XCTAssertEqual(
                    actualCost,
                    levenshteinDistance(source, comparison),
                    "Nonminimal alignment for \(String(reflecting: source)) -> \(String(reflecting: comparison))"
                )
            }
        }
    }

    func testInsertionDeletionAndReplacementMapDirectionalRangesExactly() throws {
        let insertion = try plan("ab", "axb", options: options(granularity: .character))
        assertChanges(
            insertion,
            [(.insert, NSRange(location: 1, length: 0), NSRange(location: 1, length: 1))]
        )

        let deletion = try plan("axb", "ab", options: options(granularity: .character))
        assertChanges(
            deletion,
            [(.delete, NSRange(location: 1, length: 1), NSRange(location: 1, length: 0))]
        )

        let replacement = try plan("ab", "ac", options: options(granularity: .character))
        assertChanges(
            replacement,
            [(.replace, NSRange(location: 1, length: 1), NSRange(location: 1, length: 1))]
        )
    }

    func testMissingSidesMapWholeLineInsertionsAndDeletions() throws {
        let added = DiffRow(left: nil, right: DiffLine(number: 4, text: "new"), kind: .added)
        let addedBinding = try IntraLineDifferenceTwoWayRowBinding(
            alignedRows: [added],
            rowID: added.id
        )
        let insertion = try Workflow.plan(
            .twoWay(
                comparison: .init(identity: uuid(8), revision: 60),
                row: addedBinding,
                left: nil,
                right: snapshot("new", role: .right, line: 4)
            )
        )
        assertChanges(insertion, [(.insert, nil, NSRange(location: 0, length: 3))])

        let removed = DiffRow(left: DiffLine(number: 5, text: "old"), right: nil, kind: .removed)
        let removedBinding = try IntraLineDifferenceTwoWayRowBinding(
            alignedRows: [removed],
            rowID: removed.id
        )
        let deletion = try Workflow.plan(
            .twoWay(
                comparison: .init(identity: uuid(9), revision: 61),
                row: removedBinding,
                left: snapshot("old", role: .left, line: 5),
                right: nil
            )
        )
        assertChanges(deletion, [(.delete, NSRange(location: 0, length: 3), nil)])

        for text in ["", " \t"] {
            let filteredOptions = options(granularity: .character, whitespace: .ignoreAll)
            let addedRow = DiffRow(
                left: nil,
                right: DiffLine(number: 6, text: text),
                kind: .added
            )
            let addedRowBinding = try IntraLineDifferenceTwoWayRowBinding(
                alignedRows: [addedRow],
                rowID: addedRow.id
            )
            assertChanges(
                try Workflow.plan(
                    .twoWay(
                        comparison: .init(identity: uuid(32), revision: 92),
                        row: addedRowBinding,
                        left: nil,
                        right: snapshot(text, role: .right, line: 6)
                    ),
                    options: filteredOptions
                ),
                [(.insert, nil, NSRange(location: 0, length: text.utf16.count))]
            )

            let removedRow = DiffRow(
                left: DiffLine(number: 7, text: text),
                right: nil,
                kind: .removed
            )
            let removedRowBinding = try IntraLineDifferenceTwoWayRowBinding(
                alignedRows: [removedRow],
                rowID: removedRow.id
            )
            assertChanges(
                try Workflow.plan(
                    .twoWay(
                        comparison: .init(identity: uuid(33), revision: 93),
                        row: removedRowBinding,
                        left: snapshot(text, role: .left, line: 7),
                        right: nil
                    ),
                    options: filteredOptions
                ),
                [(.delete, NSRange(location: 0, length: text.utf16.count), nil)]
            )
        }

        assertWorkflowError(.missingPairText) {
            let row = DiffRow(left: nil, right: nil, kind: .modified)
            let binding = try IntraLineDifferenceTwoWayRowBinding(
                alignedRows: [row],
                rowID: row.id
            )
            _ = try Workflow.plan(
                .twoWay(
                    comparison: .init(identity: uuid(34), revision: 94),
                    row: binding,
                    left: nil,
                    right: nil
                )
            )
        }
    }

    func testOptionsInitializerMapsComparisonAndEditorPreferencesExactly() throws {
        let comparisonOptions = LineDiffOptions(
            whitespace: .ignoreChanges,
            ignoreCase: true,
            ignoreNumbers: true
        )
        let editorPreferences = try EditorPreferencesWorkflow.CompareAndMergePreferences(
            lineDifferenceGranularity: .character,
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: "é/"
        )
        XCTAssertEqual(
            IntraLineDifferenceOptions(
                comparisonOptions: comparisonOptions,
                editorPreferences: editorPreferences,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            )
        )
    }

    func testOptionsEqualityAndHashingCoverEveryFieldAndExactCustomBreakBytes() {
        let baseline = options(
            granularity: .character,
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: "é/",
            whitespace: .ignoreChanges,
            ignoreCase: true,
            ignoreNumbers: true,
            punctuation: .ignoreAll
        )
        XCTAssertEqual(baseline, baseline)
        XCTAssertEqual(hash(baseline), hash(baseline))
        let independentlyBuiltEqualValue = options(
            granularity: .character,
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: "é/",
            whitespace: .ignoreChanges,
            ignoreCase: true,
            ignoreNumbers: true,
            punctuation: .ignoreAll
        )
        XCTAssertEqual(baseline, independentlyBuiltEqualValue)
        XCTAssertEqual(hash(baseline), hash(independentlyBuiltEqualValue))
        let variants = [
            options(
                granularity: .word,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespace,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "e\u{301}/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreAll,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: false,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: false,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .compareAll
            )
        ]
        for variant in variants {
            XCTAssertNotEqual(baseline, variant)
        }
    }

    func testPlanUsesKeyedCommitmentsWithoutPlaintextOrEqualityLeaks() throws {
        let secret = "intraline-secret-canary-9281"
        let boundInput = try input(secret, secret + "!")
        let first = try Workflow.plan(boundInput)
        let second = try Workflow.plan(boundInput)

        for value in [boundInput as Any, first as Any, first.receipt as Any] {
            let renderings = renderings(of: value)
            XCTAssertFalse(renderings.contains { $0.contains(secret) })
            XCTAssertTrue(renderings.contains { $0.contains("<redacted>") })
        }
        let firstCommitments = try XCTUnwrap(mirrorValue(first, label: "commitments") as? String)
        let secondCommitments = try XCTUnwrap(mirrorValue(second, label: "commitments") as? String)
        XCTAssertEqual(firstCommitments, "<redacted>")
        XCTAssertEqual(secondCommitments, "<redacted>")
        let opaquePlan: Any = first
        XCTAssertFalse(opaquePlan is any Equatable)
        XCTAssertFalse(opaquePlan is any Hashable)

        let sourceReference = try XCTUnwrap(boundInput.source?.reference)
        let comparisonReference = try XCTUnwrap(boundInput.comparison?.reference)
        let snapshotOnlySourceChange = try input(
            secret,
            secret + "!",
            sourceSnapshotText: secret + "x",
            sourceReference: sourceReference,
            comparisonReference: comparisonReference
        )
        assertWorkflowError(.staleSourceText) {
            try first.validateCurrentInput(
                snapshotOnlySourceChange,
                options: first.options,
                limits: first.limits
            )
        }

        let bindingOnlySourceChange = try input(
            secret + "x",
            secret + "!",
            sourceSnapshotText: secret,
            sourceReference: sourceReference,
            comparisonReference: comparisonReference
        )
        assertWorkflowError(.staleSourceText) {
            try first.validateCurrentInput(
                bindingOnlySourceChange,
                options: first.options,
                limits: first.limits
            )
        }

        let snapshotOnlyComparisonChange = try input(
            secret,
            secret + "!",
            comparisonSnapshotText: secret + "?",
            sourceReference: sourceReference,
            comparisonReference: comparisonReference
        )
        assertWorkflowError(.staleComparisonText) {
            try first.validateCurrentInput(
                snapshotOnlyComparisonChange,
                options: first.options,
                limits: first.limits
            )
        }

        let bindingOnlyComparisonChange = try input(
            secret,
            secret + "?",
            comparisonSnapshotText: secret + "!",
            sourceReference: sourceReference,
            comparisonReference: comparisonReference
        )
        assertWorkflowError(.staleComparisonText) {
            try first.validateCurrentInput(
                bindingOnlyComparisonChange,
                options: first.options,
                limits: first.limits
            )
        }
    }

    func testValidationRejectsEveryStaleOptionFieldAndExactCustomBreakChange() throws {
        let plannedOptions = options(
            granularity: .character,
            wordBreakMode: .whitespaceOrCustomCharacters,
            wordBreakCharacters: "é/",
            whitespace: .ignoreChanges,
            ignoreCase: true,
            ignoreNumbers: true,
            punctuation: .ignoreAll
        )
        let current = try input("Alpha 12/a", "alpha 34/b")
        let plan = try Workflow.plan(current, options: plannedOptions)
        let stale = [
            options(
                granularity: .word,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespace,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "e\u{301}/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreAll,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: false,
                ignoreNumbers: true,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: false,
                punctuation: .ignoreAll
            ),
            options(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/",
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: true,
                punctuation: .compareAll
            )
        ]
        for staleOptions in stale {
            assertWorkflowError(.staleOptions) {
                try plan.validateCurrentInput(
                    current,
                    options: staleOptions,
                    limits: plan.limits
                )
            }
        }
    }

    func testValidationDetectsStaleComparisonRowBindingsAndTextsInOrder() throws {
        let current = try input("source", "comparison")
        let plan = try Workflow.plan(current)
        try plan.validateCurrentInput(current, options: plan.options, limits: plan.limits)

        let staleLimits = limits(maximumOutputRangePairs: plan.limits.maximumOutputRangePairs - 1)
        assertWorkflowError(.staleLimits) {
            try plan.validateCurrentInput(current, options: plan.options, limits: staleLimits)
        }

        let staleComparison = try input(
            "source",
            "comparison",
            comparisonIdentity: uuid(100),
            comparisonRevision: current.row.comparison.revision
        )
        assertWorkflowError(.staleComparison) {
            try plan.validateCurrentInput(staleComparison, options: plan.options, limits: plan.limits)
        }

        let staleRow = try input("source", "comparison", rowIndexPrefix: true)
        assertWorkflowError(.staleRow) {
            try plan.validateCurrentInput(staleRow, options: plan.options, limits: plan.limits)
        }

        let sourceReference = try XCTUnwrap(current.source?.reference)
        let comparisonReference = try XCTUnwrap(current.comparison?.reference)
        let staleSourceBinding = try input(
            "source",
            "comparison",
            sourceReference: .init(
                identity: uuid(101),
                revision: sourceReference.revision,
                role: sourceReference.role,
                lineNumber: sourceReference.lineNumber
            ),
            comparisonReference: comparisonReference
        )
        assertWorkflowError(.staleSourceBinding) {
            try plan.validateCurrentInput(
                staleSourceBinding,
                options: plan.options,
                limits: plan.limits
            )
        }

        let staleComparisonBinding = try input(
            "source",
            "comparison",
            sourceReference: sourceReference,
            comparisonReference: .init(
                identity: uuid(102),
                revision: comparisonReference.revision,
                role: comparisonReference.role,
                lineNumber: comparisonReference.lineNumber
            )
        )
        assertWorkflowError(.staleComparisonBinding) {
            try plan.validateCurrentInput(
                staleComparisonBinding,
                options: plan.options,
                limits: plan.limits
            )
        }

        let staleSourceText = try input(
            "sourcf",
            "comparison",
            sourceReference: sourceReference,
            comparisonReference: comparisonReference
        )
        assertWorkflowError(.staleSourceText) {
            try plan.validateCurrentInput(staleSourceText, options: plan.options, limits: plan.limits)
        }

        let staleComparisonText = try input(
            "source",
            "comparisoo",
            sourceReference: sourceReference,
            comparisonReference: comparisonReference
        )
        assertWorkflowError(.staleComparisonText) {
            try plan.validateCurrentInput(
                staleComparisonText,
                options: plan.options,
                limits: plan.limits
            )
        }
    }

    func testValidationRejectsMultipleStaleFieldsInDocumentedOrder() throws {
        let current = try input("source", "comparison")
        let plan = try Workflow.plan(current)
        let sourceReference = try XCTUnwrap(current.source?.reference)
        let comparisonReference = try XCTUnwrap(current.comparison?.reference)
        let staleEverything = try input(
            "changed-source",
            "changed-comparison",
            comparisonIdentity: uuid(110),
            rowIndexPrefix: true,
            sourceReference: .init(
                identity: uuid(111),
                revision: sourceReference.revision,
                role: sourceReference.role,
                lineNumber: sourceReference.lineNumber
            ),
            comparisonReference: .init(
                identity: uuid(112),
                revision: comparisonReference.revision,
                role: comparisonReference.role,
                lineNumber: comparisonReference.lineNumber
            )
        )
        let staleOptions = options(ignoreCase: true)
        let staleLimits = limits(maximumOutputRangePairs: plan.limits.maximumOutputRangePairs - 1)
        assertWorkflowError(.staleOptions) {
            try plan.validateCurrentInput(
                staleEverything,
                options: staleOptions,
                limits: staleLimits
            )
        }
        assertWorkflowError(.staleLimits) {
            try plan.validateCurrentInput(
                staleEverything,
                options: plan.options,
                limits: staleLimits
            )
        }
        assertWorkflowError(.staleComparison) {
            try plan.validateCurrentInput(
                staleEverything,
                options: plan.options,
                limits: plan.limits
            )
        }

        let staleRowAndLater = try input(
            "changed-source",
            "changed-comparison",
            rowIndexPrefix: true,
            sourceReference: staleEverything.source?.reference,
            comparisonReference: staleEverything.comparison?.reference
        )
        assertWorkflowError(.staleRow) {
            try plan.validateCurrentInput(
                staleRowAndLater,
                options: plan.options,
                limits: plan.limits
            )
        }

        let staleBindingsAndTexts = try input(
            "changed-source",
            "changed-comparison",
            sourceReference: staleEverything.source?.reference,
            comparisonReference: staleEverything.comparison?.reference
        )
        assertWorkflowError(.staleSourceBinding) {
            try plan.validateCurrentInput(
                staleBindingsAndTexts,
                options: plan.options,
                limits: plan.limits
            )
        }

        let staleComparisonBindingAndTexts = try input(
            "changed-source",
            "changed-comparison",
            sourceReference: sourceReference,
            comparisonReference: staleEverything.comparison?.reference
        )
        assertWorkflowError(.staleComparisonBinding) {
            try plan.validateCurrentInput(
                staleComparisonBindingAndTexts,
                options: plan.options,
                limits: plan.limits
            )
        }

        let staleBothTexts = try input(
            "changed-source",
            "changed-comparison",
            sourceReference: sourceReference,
            comparisonReference: comparisonReference
        )
        assertWorkflowError(.staleSourceText) {
            try plan.validateCurrentInput(
                staleBothTexts,
                options: plan.options,
                limits: plan.limits
            )
        }
    }

    func testPlanningWorkReceiptIsExactAndEnforced() throws {
        let current = try input("a", "b")
        let configured = limits(
            alignmentLookahead: 1,
            maximumWorkUnits: 10_000,
            cancellationCheckInterval: 1
        )
        let consumed = try Workflow.plan(
            current,
            options: options(granularity: .character),
            limits: configured
        ).receipt.workUnitsConsumed
        XCTAssertEqual(consumed, 280)
        assertWorkflowError(.workLimitExceeded(maximumWorkUnits: consumed - 1)) {
            _ = try Workflow.plan(
                current,
                options: self.options(granularity: .character),
                limits: self.limits(
                    alignmentLookahead: 1,
                    maximumWorkUnits: consumed - 1,
                    cancellationCheckInterval: 1
                )
            )
        }
    }

    func testPlanningAndValidationHonorCancellation() async throws {
        let current = try input(String(repeating: "a", count: 256), String(repeating: "b", count: 256))
        let plan = try Workflow.plan(current)
        let planningError = await Task.detached { () -> WorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Workflow.plan(current)
                return nil
            } catch let error as WorkflowError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(planningError, .cancelled)

        let validationError = await Task.detached { () -> WorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try plan.validateCurrentInput(current, options: plan.options, limits: plan.limits)
                return nil
            } catch let error as WorkflowError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(validationError, .cancelled)

        let longText = String(repeating: "😀", count: 128_000)
        let longInput = try input(longText, longText)
        let cancellationLimits = limits(
            maximumInputUTF8BytesPerSide: 512_000,
            maximumInputUTF16UnitsPerSide: 256_000,
            maximumInputGraphemesPerSide: 128_000,
            maximumCombinedInputUTF8Bytes: 1_024_000,
            maximumWorkUnits: IntraLineDifferenceLimits.hardMaximumWorkUnits,
            cancellationCheckInterval: 1
        )
        let planningStart = StartProbe()
        let inFlightPlanning = Task.detached { () -> WorkflowError? in
            await planningStart.markStarted()
            do {
                _ = try Workflow.plan(longInput, limits: cancellationLimits)
                return nil
            } catch let error as WorkflowError {
                return error
            } catch {
                return nil
            }
        }
        await planningStart.waitUntilStarted()
        try await ContinuousClock().sleep(for: .milliseconds(1))
        inFlightPlanning.cancel()
        let inFlightPlanningError = await inFlightPlanning.value
        XCTAssertEqual(inFlightPlanningError, .cancelled)

        let longPlan = try Workflow.plan(longInput, limits: cancellationLimits)
        let validationStart = StartProbe()
        let inFlightValidation = Task.detached { () -> WorkflowError? in
            await validationStart.markStarted()
            do {
                while true {
                    try longPlan.validateCurrentInput(
                        longInput,
                        options: longPlan.options,
                        limits: longPlan.limits
                    )
                }
            } catch let error as WorkflowError {
                return error
            } catch {
                return nil
            }
        }
        await validationStart.waitUntilStarted()
        try await ContinuousClock().sleep(for: .milliseconds(1))
        let cancellationStart = ContinuousClock().now
        inFlightValidation.cancel()
        let inFlightValidationError = await inFlightValidation.value
        XCTAssertEqual(inFlightValidationError, .cancelled)
        XCTAssertLessThan(cancellationStart.duration(to: .now), .seconds(1))
    }

    func testAlignmentDPChargesFullPreflightBeforeAllocationAndWork() throws {
        let current = try input("a", "b")
        let baseLimits = limits(alignmentLookahead: 1, maximumWorkUnits: 10_000)
        let exactWork = try Workflow.plan(current, limits: baseLimits).receipt.workUnitsConsumed

        assertWorkflowError(.workLimitExceeded(maximumWorkUnits: exactWork - 1)) {
            _ = try Workflow.plan(
                current,
                limits: self.limits(
                    alignmentLookahead: 1,
                    maximumWorkUnits: exactWork - 1
                )
            )
        }
        XCTAssertEqual(
            try Workflow.plan(
                current,
                limits: limits(alignmentLookahead: 1, maximumWorkUnits: exactWork)
            ).receipt.workUnitsConsumed,
            exactWork
        )

        let longInput = try input(
            String(repeating: "a", count: 300),
            String(repeating: "b", count: 300)
        )
        assertWorkflowError(.workLimitExceeded(maximumWorkUnits: 30_000)) {
            _ = try Workflow.plan(
                longInput,
                options: self.options(granularity: .character),
                limits: self.limits(
                    alignmentLookahead: IntraLineDifferenceLimits.hardMaximumAlignmentLookahead,
                    maximumWorkUnits: 30_000,
                    cancellationCheckInterval: 1
                )
            )
        }
    }

    func testEveryConfiguredLimitRejectsBoundaryViolationWithTypedError() throws {
        let baseInput = try input("aa", "bb")
        let cases: [(IntraLineDifferenceLimits, WorkflowError)] = [
            (
                limits(maximumInputUTF8BytesPerSide: 1),
                .inputTooLarge(role: .left, maximumUTF8Bytes: 1)
            ),
            (
                limits(maximumInputUTF16UnitsPerSide: 1),
                .inputTooLong(role: .left, maximumUTF16Units: 1)
            ),
            (
                limits(maximumInputGraphemesPerSide: 1),
                .tooManyGraphemes(role: .left, maximumGraphemes: 1)
            ),
            (
                limits(maximumCombinedInputUTF8Bytes: 3),
                .combinedInputTooLarge(maximumUTF8Bytes: 3)
            )
        ]
        for (testLimits, error) in cases {
            assertWorkflowError(error) {
                _ = try Workflow.plan(baseInput, limits: testLimits)
            }
        }

        assertWorkflowError(.inputTooLarge(role: .right, maximumUTF8Bytes: 1)) {
            _ = try self.plan("a", "é", limits: self.limits(maximumInputUTF8BytesPerSide: 1))
        }
        assertWorkflowError(.inputTooLong(role: .right, maximumUTF16Units: 1)) {
            _ = try self.plan("a", "😀", limits: self.limits(maximumInputUTF16UnitsPerSide: 1))
        }
        assertWorkflowError(.tooManyGraphemes(role: .right, maximumGraphemes: 1)) {
            _ = try self.plan("a", "bc", limits: self.limits(maximumInputGraphemesPerSide: 1))
        }

        assertWorkflowError(.graphemeTooLong(role: .left, maximumUTF16Units: 2)) {
            _ = try self.plan(
                "👨‍👩‍👧",
                "x",
                limits: self.limits(maximumGraphemeUTF16Units: 2)
            )
        }
        assertWorkflowError(.wordBreakCharactersTooLarge(maximumUTF8Bytes: 1)) {
            _ = try self.plan(
                "a",
                "b",
                options: self.options(
                    wordBreakMode: .whitespaceOrCustomCharacters,
                    wordBreakCharacters: "é"
                ),
                limits: self.limits(maximumWordBreakUTF8Bytes: 1)
            )
        }
        assertWorkflowError(.tooManyOutputRanges(maximumRangePairs: 1)) {
            _ = try self.plan(
                "abcde",
                "axcye",
                options: self.options(granularity: .character),
                limits: self.limits(maximumOutputRangePairs: 1)
            )
        }
        assertWorkflowError(.workLimitExceeded(maximumWorkUnits: 1)) {
            _ = try Workflow.plan(baseInput, limits: self.limits(maximumWorkUnits: 1))
        }
    }

    func testEveryConfiguredLimitAcceptsItsInclusiveBoundary() throws {
        _ = try plan("é", "x", limits: limits(maximumInputUTF8BytesPerSide: 2))
        _ = try plan("😀", "x", limits: limits(maximumInputUTF16UnitsPerSide: 2))
        _ = try plan("👨‍👩‍👧", "x", limits: limits(maximumInputGraphemesPerSide: 1))
        _ = try plan("é", "x", limits: limits(maximumCombinedInputUTF8Bytes: 3))

        let grapheme = "👨‍👩‍👧"
        _ = try plan(
            grapheme,
            "x",
            limits: limits(maximumGraphemeUTF16Units: grapheme.utf16.count)
        )
        _ = try plan(
            "a",
            "b",
            options: options(
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é"
            ),
            limits: limits(maximumWordBreakUTF8Bytes: "é".utf8.count)
        )
        XCTAssertEqual(
            try plan(
                "abcde",
                "axcye",
                options: options(granularity: .character),
                limits: limits(maximumOutputRangePairs: 2)
            ).changes.count,
            2
        )
        XCTAssertFalse(
            try plan("same", "same", limits: limits(maximumOutputRangePairs: 0))
                .hasDifferences
        )
    }

    func testEveryLimitRejectsNegativeZeroOrAboveHardMaximumWithoutTrap() throws {
        let current = try input("a", "b")
        let cases: [(IntraLineDifferenceLimits, IntraLineDifferenceLimit)] = [
            (limits(maximumInputUTF8BytesPerSide: -1), .inputUTF8BytesPerSide),
            (limits(maximumInputUTF16UnitsPerSide: -1), .inputUTF16UnitsPerSide),
            (limits(maximumInputGraphemesPerSide: -1), .inputGraphemesPerSide),
            (limits(maximumCombinedInputUTF8Bytes: -1), .combinedInputUTF8Bytes),
            (limits(maximumGraphemeUTF16Units: -1), .graphemeUTF16Units),
            (limits(maximumWordBreakUTF8Bytes: -1), .wordBreakUTF8Bytes),
            (limits(maximumOutputRangePairs: -1), .outputRangePairs),
            (
                limits(
                    maximumInputUTF8BytesPerSide:
                        IntraLineDifferenceLimits.hardMaximumInputUTF8BytesPerSide + 1
                ),
                .inputUTF8BytesPerSide
            ),
            (
                limits(
                    maximumInputUTF16UnitsPerSide:
                        IntraLineDifferenceLimits.hardMaximumInputUTF16UnitsPerSide + 1
                ),
                .inputUTF16UnitsPerSide
            ),
            (
                limits(
                    maximumInputGraphemesPerSide:
                        IntraLineDifferenceLimits.hardMaximumInputGraphemesPerSide + 1
                ),
                .inputGraphemesPerSide
            ),
            (
                limits(
                    maximumCombinedInputUTF8Bytes:
                        IntraLineDifferenceLimits.hardMaximumCombinedInputUTF8Bytes + 1
                ),
                .combinedInputUTF8Bytes
            ),
            (
                limits(
                    maximumGraphemeUTF16Units:
                        IntraLineDifferenceLimits.hardMaximumGraphemeUTF16Units + 1
                ),
                .graphemeUTF16Units
            ),
            (
                limits(
                    maximumWordBreakUTF8Bytes:
                        IntraLineDifferenceLimits.hardMaximumWordBreakUTF8Bytes + 1
                ),
                .wordBreakUTF8Bytes
            ),
            (
                limits(
                    maximumOutputRangePairs:
                        IntraLineDifferenceLimits.hardMaximumOutputRangePairs + 1
                ),
                .outputRangePairs
            ),
            (limits(alignmentLookahead: 0), .alignmentLookahead),
            (limits(maximumWorkUnits: 0), .workUnits),
            (limits(cancellationCheckInterval: 0), .cancellationCheckInterval),
            (
                limits(
                    alignmentLookahead:
                        IntraLineDifferenceLimits.hardMaximumAlignmentLookahead + 1
                ),
                .alignmentLookahead
            ),
            (
                limits(maximumWorkUnits: IntraLineDifferenceLimits.hardMaximumWorkUnits + 1),
                .workUnits
            ),
            (
                limits(
                    cancellationCheckInterval:
                        IntraLineDifferenceLimits.hardMaximumCancellationCheckInterval + 1
                ),
                .cancellationCheckInterval
            )
        ]
        for (testLimits, limit) in cases {
            assertWorkflowError(.invalidLimit(limit)) {
                _ = try Workflow.plan(current, limits: testLimits)
            }
        }
    }

    func testReceiptsAreDeterministicAndCarryOnlyBoundedMetadata() throws {
        let current = try input("a😀b", "a😃b")
        let first = try Workflow.plan(current, options: options(granularity: .character))
        let second = try Workflow.plan(current, options: options(granularity: .character))

        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(hash(first.receipt), hash(second.receipt))
        XCTAssertEqual(first.receipt.version, IntraLineDifferencePlanningReceipt.currentVersion)
        XCTAssertEqual(first.receipt.comparison, current.row.comparison)
        XCTAssertEqual(first.receipt.row, current.row)
        XCTAssertEqual(first.receipt.pairKind, current.kind)
        XCTAssertEqual(first.receipt.sourceReference, current.source?.reference)
        XCTAssertEqual(first.receipt.comparisonReference, current.comparison?.reference)
        XCTAssertEqual(first.receipt.sourceUTF8ByteCount, "a😀b".utf8.count)
        XCTAssertEqual(first.receipt.comparisonUTF8ByteCount, "a😃b".utf8.count)
        XCTAssertEqual(first.receipt.changeCount, first.changes.count)
        XCTAssertGreaterThan(first.receipt.workUnitsConsumed, 0)
    }

    func testAllPublicContainersRedactDescriptionsDebugDescriptionsAndReflection() throws {
        let secret = "reflection-secret-canary-5501"
        let current = try input(secret, secret + "!")
        let plan = try Workflow.plan(current)
        let binding = try IntraLineDifferenceTwoWayRowBinding(
            alignedRows: [
                DiffRow(
                    left: DiffLine(number: 1, text: secret),
                    right: DiffLine(number: 1, text: secret + "!"),
                    kind: .modified
                )
            ],
            rowID: DiffRow.ID(leftNumber: 1, rightNumber: 1)
        )
        let merge = try ThreeWayTextMerge.merge(
            base: "base-\(secret)",
            left: "left-\(secret)",
            right: "right-\(secret)"
        )
        let region = try XCTUnwrap(merge.regions.first)
        let threeWayBinding = try IntraLineDifferenceThreeWayRowBinding(
            region: region,
            row: try XCTUnwrap(region.leftLines.first)
        )
        let values: [Any] = [
            try XCTUnwrap(current.source),
            binding,
            threeWayBinding,
            current,
            plan,
            plan.receipt,
            options(wordBreakMode: .whitespaceOrCustomCharacters, wordBreakCharacters: secret)
        ]
        for value in values {
            let rendered = renderings(of: value)
            XCTAssertFalse(rendered.contains { $0.contains(secret) })
            XCTAssertTrue(rendered.contains { $0.contains("<redacted>") })
        }
    }

    private func input(
        _ source: String,
        _ comparison: String,
        comparisonIdentity: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
        comparisonRevision: UInt64 = 70,
        rowIndexPrefix: Bool = false,
        sourceSnapshotText: String? = nil,
        comparisonSnapshotText: String? = nil,
        sourceReference: IntraLineDifferenceSourceReference? = nil,
        comparisonReference: IntraLineDifferenceSourceReference? = nil
    ) throws -> IntraLineDifferencePairInput {
        let row = DiffRow(
            left: DiffLine(number: 1, text: source),
            right: DiffLine(number: 1, text: comparison),
            kind: .modified
        )
        let rows =
            rowIndexPrefix
            ? [
                DiffRow(
                    left: DiffLine(number: 9, text: "prefix"),
                    right: DiffLine(number: 9, text: "prefix"),
                    kind: .unchanged
                ),
                row
            ]
            : [row]
        let binding = try IntraLineDifferenceTwoWayRowBinding(alignedRows: rows, rowID: row.id)
        return .twoWay(
            comparison: .init(identity: comparisonIdentity, revision: comparisonRevision),
            row: binding,
            left: IntraLineDifferenceTextSnapshot(
                reference: sourceReference
                    ?? .init(
                        identity: uuid(11),
                        revision: 71,
                        role: .left,
                        lineNumber: 1
                    ),
                text: sourceSnapshotText ?? source
            ),
            right: IntraLineDifferenceTextSnapshot(
                reference: comparisonReference
                    ?? .init(
                        identity: uuid(12),
                        revision: 72,
                        role: .right,
                        lineNumber: 1
                    ),
                text: comparisonSnapshotText ?? comparison
            )
        )
    }

    private func plan(
        _ source: String,
        _ comparison: String,
        options: IntraLineDifferenceOptions = .default,
        limits: IntraLineDifferenceLimits = .default
    ) throws -> IntraLineDifferencePlan {
        try Workflow.plan(input(source, comparison), options: options, limits: limits)
    }

    private func snapshot(
        _ text: String,
        role: IntraLineDifferenceRole,
        line: Int,
        identity: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
        revision: UInt64 = 80
    ) -> IntraLineDifferenceTextSnapshot {
        IntraLineDifferenceTextSnapshot(
            reference: .init(
                identity: identity,
                revision: revision,
                role: role,
                lineNumber: line
            ),
            text: text
        )
    }

    private func options(
        granularity: EditorPreferencesWorkflow.LineDifferenceGranularity = .word,
        wordBreakMode: EditorPreferencesWorkflow.WordBreakMode = .whitespace,
        wordBreakCharacters: String = "",
        whitespace: WhitespaceComparison = .compareAll,
        ignoreCase: Bool = false,
        ignoreNumbers: Bool = false,
        punctuation: IntraLineDifferencePunctuationComparison = .compareAll
    ) -> IntraLineDifferenceOptions {
        IntraLineDifferenceOptions(
            granularity: granularity,
            wordBreakMode: wordBreakMode,
            wordBreakCharacters: wordBreakCharacters,
            whitespace: whitespace,
            ignoreCase: ignoreCase,
            ignoreNumbers: ignoreNumbers,
            punctuation: punctuation
        )
    }

    private func limits(
        maximumInputUTF8BytesPerSide: Int = IntraLineDifferenceLimits.default.maximumInputUTF8BytesPerSide,
        maximumInputUTF16UnitsPerSide: Int = IntraLineDifferenceLimits.default.maximumInputUTF16UnitsPerSide,
        maximumInputGraphemesPerSide: Int = IntraLineDifferenceLimits.default.maximumInputGraphemesPerSide,
        maximumCombinedInputUTF8Bytes: Int = IntraLineDifferenceLimits.default.maximumCombinedInputUTF8Bytes,
        maximumGraphemeUTF16Units: Int = IntraLineDifferenceLimits.default.maximumGraphemeUTF16Units,
        maximumWordBreakUTF8Bytes: Int = IntraLineDifferenceLimits.default.maximumWordBreakUTF8Bytes,
        maximumOutputRangePairs: Int = IntraLineDifferenceLimits.default.maximumOutputRangePairs,
        alignmentLookahead: Int = IntraLineDifferenceLimits.default.alignmentLookahead,
        maximumWorkUnits: UInt64 = IntraLineDifferenceLimits.default.maximumWorkUnits,
        cancellationCheckInterval: UInt64 = IntraLineDifferenceLimits.default.cancellationCheckInterval
    ) -> IntraLineDifferenceLimits {
        IntraLineDifferenceLimits(
            maximumInputUTF8BytesPerSide: maximumInputUTF8BytesPerSide,
            maximumInputUTF16UnitsPerSide: maximumInputUTF16UnitsPerSide,
            maximumInputGraphemesPerSide: maximumInputGraphemesPerSide,
            maximumCombinedInputUTF8Bytes: maximumCombinedInputUTF8Bytes,
            maximumGraphemeUTF16Units: maximumGraphemeUTF16Units,
            maximumWordBreakUTF8Bytes: maximumWordBreakUTF8Bytes,
            maximumOutputRangePairs: maximumOutputRangePairs,
            alignmentLookahead: alignmentLookahead,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func assertChanges(
        _ plan: IntraLineDifferencePlan,
        _ expected: [(IntraLineDifferenceChangeKind, NSRange?, NSRange?)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(plan.changes.count, expected.count, file: file, line: line)
        for (ordinal, expectedChange) in expected.enumerated() where plan.changes.indices.contains(ordinal) {
            let actual = plan.changes[ordinal]
            XCTAssertEqual(actual.ordinal, ordinal, file: file, line: line)
            XCTAssertEqual(actual.kind, expectedChange.0, file: file, line: line)
            XCTAssertEqual(actual.sourceUTF16Range, expectedChange.1, file: file, line: line)
            XCTAssertEqual(actual.comparisonUTF16Range, expectedChange.2, file: file, line: line)
        }
        if let source = plan.source {
            XCTAssertEqual(source.utf16Ranges, expected.compactMap(\.1), file: file, line: line)
        } else {
            XCTAssertTrue(expected.allSatisfy { $0.1 == nil }, file: file, line: line)
        }
        if let comparison = plan.comparison {
            XCTAssertEqual(comparison.utf16Ranges, expected.compactMap(\.2), file: file, line: line)
        } else {
            XCTAssertTrue(expected.allSatisfy { $0.2 == nil }, file: file, line: line)
        }
    }

    private func assertGraphemeSafe(
        _ plan: IntraLineDifferencePlan,
        source: String,
        comparison: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRanges(plan.source?.utf16Ranges ?? [], in: source, file: file, line: line)
        assertRanges(plan.comparison?.utf16Ranges ?? [], in: comparison, file: file, line: line)
    }

    private func assertRanges(
        _ ranges: [NSRange],
        in text: String,
        file: StaticString,
        line: UInt
    ) {
        var boundaries: Set<Int> = [0]
        var offset = 0
        for character in text {
            offset += String(character).utf16.count
            boundaries.insert(offset)
        }
        for range in ranges {
            XCTAssertTrue(boundaries.contains(range.location), "start \(range)", file: file, line: line)
            XCTAssertTrue(
                boundaries.contains(NSMaxRange(range)),
                "end \(range)",
                file: file,
                line: line
            )
        }
    }

    private func assertWorkflowError<T>(
        _ expected: WorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? WorkflowError, expected, file: file, line: line)
        }
    }

    private func strings(alphabet: [Character], maximumLength: Int) -> [String] {
        var result = [""]
        var level = [""]
        for _ in 0..<maximumLength {
            level = level.flatMap { prefix in
                alphabet.map { prefix + String($0) }
            }
            result.append(contentsOf: level)
        }
        return result
    }

    private func levenshteinDistance(_ source: String, _ comparison: String) -> Int {
        let source = Array(source)
        let comparison = Array(comparison)
        var previous = Array(0...comparison.count)
        for (sourceIndex, sourceCharacter) in source.enumerated() {
            var current = Array(repeating: 0, count: comparison.count + 1)
            current[0] = sourceIndex + 1
            for (comparisonIndex, comparisonCharacter) in comparison.enumerated() {
                current[comparisonIndex + 1] = min(
                    previous[comparisonIndex + 1] + 1,
                    current[comparisonIndex] + 1,
                    previous[comparisonIndex] + (sourceCharacter == comparisonCharacter ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[comparison.count]
    }

    private func hash<T: Hashable>(_ value: T) -> Int {
        var hasher = Hasher()
        value.hash(into: &hasher)
        return hasher.finalize()
    }

    private func renderings(of value: Any) -> [String] {
        let mirror = Mirror(reflecting: value)
        let children = mirror.children.map {
            "\($0.label ?? "_")=\(String(reflecting: $0.value))"
        }.joined(separator: "|")
        return [String(describing: value), String(reflecting: value), children]
    }

    private func mirrorValue(_ value: Any, label: String) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == label }?.value
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
