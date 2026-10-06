import Foundation
import MacMergeCore
import XCTest

final class BinaryHexEditingPolicyTests: XCTestCase {
    private let identity = BinaryHexContentIdentity(
        rawValue: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    )

    func testPublicValueCatalogsDefaultsAndSelectionMetrics() {
        XCTAssertEqual(BinaryHexPane.allCases, [.left, .middle, .right])
        XCTAssertEqual(BinaryHexSelectionSurface.allCases, [.bytes, .characters])
        XCTAssertEqual(
            BinaryHexCharacterSet.allCases,
            [.ascii, .isoLatin1, .windows1252, .utf8, .utf16LittleEndian, .utf16BigEndian]
        )
        XCTAssertEqual(BinaryHexOffsetRadix.allCases, [.hexadecimal, .decimal])
        XCTAssertEqual(BinaryHexEditMode.allCases, [.insert, .overwrite])
        XCTAssertEqual(BinaryHexSearchDirection.allCases, [.forward, .backward])
        XCTAssertEqual(BinaryHexDisplaySettings.maximumBytesPerRow, 256)
        XCTAssertEqual(BinaryHexDisplaySettings.default.bytesPerRow, 16)
        XCTAssertEqual(BinaryHexDisplaySettings.default.byteGroupSize, 1)
        XCTAssertEqual(BinaryHexDisplaySettings.default.characterSet, .ascii)
        XCTAssertEqual(BinaryHexDisplaySettings.default.offsetRadix, .hexadecimal)
        XCTAssertTrue(BinaryHexDisplaySettings.default.usesUppercaseHex)
        XCTAssertTrue(BinaryHexDisplaySettings.default.showsOffsetColumn)
        XCTAssertTrue(BinaryHexDisplaySettings.default.showsCharacterColumn)
        XCTAssertEqual(BinaryHexDisplaySettings.default.editMode, .overwrite)

        let range = BinaryHexSelection(byteRange: 2..<5, surface: .characters)
        XCTAssertEqual(range.byteCount, 3)
        XCTAssertFalse(range.isEmpty)
        XCTAssertEqual(range.insertionOffset, 2)
        let insertion = BinaryHexSelection(byteOffset: 4)
        XCTAssertEqual(insertion.byteRange, 4..<4)
        XCTAssertEqual(insertion.byteCount, 0)
        XCTAssertTrue(insertion.isEmpty)

        let overflowing = BinaryHexSelection(byteRange: Int.min..<Int.max)
        XCTAssertEqual(overflowing.byteCount, .max)
        XCTAssertFalse(overflowing.isEmpty)
    }

    func testSelectionSetSelectAllAndUnchangedReason() throws {
        let source = pane([0x10, 0x20, 0x30], selection: selection(1..<1))
        let requested = selection(1..<3, surface: .characters)

        let set = try BinaryHexEditingPolicy.plan(.selection(.set(requested)), in: source)
        XCTAssertEqual(set.resultData, source.data)
        XCTAssertEqual(set.resultSelection, requested)
        XCTAssertFalse(set.didChangeContent)
        XCTAssertTrue(set.didChangeSelection)
        XCTAssertTrue(set.hasEffect)
        XCTAssertNil(set.noOpReason)

        let all = try BinaryHexEditingPolicy.plan(
            .selection(.selectAll(surface: .bytes)),
            in: source
        )
        XCTAssertEqual(all.resultSelection, selection(0..<3))

        let unchanged = try BinaryHexEditingPolicy.plan(
            .selection(.set(source.selection)),
            in: source
        )
        XCTAssertTrue(unchanged.isNoOp)
        XCTAssertEqual(unchanged.noOpReason, .selectionUnchanged)
        XCTAssertFalse(unchanged.didChangeSelection)
    }

    func testAlignedSelectionMapsGapsAndEOFToEachSource() throws {
        let comparison = BinaryComparison.compare(
            left: Data([0x10, 0x20]),
            right: Data([0x10, 0xAA, 0x20])
        )
        XCTAssertEqual(comparison.alignedByteCount, 3)

        XCTAssertEqual(
            try BinaryHexEditingPolicy.selection(
                atAlignedOffset: 1,
                side: .left,
                in: comparison,
                surface: .characters
            ),
            selection(1..<1, surface: .characters)
        )
        XCTAssertEqual(
            try BinaryHexEditingPolicy.selection(
                atAlignedOffset: 1,
                side: .right,
                in: comparison
            ),
            selection(1..<1)
        )
        XCTAssertEqual(
            try BinaryHexEditingPolicy.selection(
                atAlignedOffset: comparison.alignedByteCount,
                side: .left,
                in: comparison
            ),
            selection(2..<2)
        )
        XCTAssertEqual(
            try BinaryHexEditingPolicy.selection(
                atAlignedOffset: comparison.alignedByteCount,
                side: .right,
                in: comparison
            ),
            selection(3..<3)
        )
        assertPolicyError(.invalidByteOffset(offset: -1, byteCount: 3)) {
            try BinaryHexEditingPolicy.selection(
                atAlignedOffset: -1,
                side: .left,
                in: comparison
            )
        }
        assertPolicyError(.invalidByteOffset(offset: 4, byteCount: 3)) {
            try BinaryHexEditingPolicy.selection(
                atAlignedOffset: 4,
                side: .right,
                in: comparison
            )
        }
    }

    func testInsertAtOffsetAndSelectionBuildsExactMutations() throws {
        let source = pane([0x10, 0x20, 0x30], selection: selection(1..<2))

        let insertion = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .bytes(Data([0xAA, 0xBB])), target: .byteOffset(1))),
            in: source
        )
        XCTAssertEqual(insertion.resultData, Data([0x10, 0xAA, 0xBB, 0x20, 0x30]))
        XCTAssertEqual(insertion.resultSelection, selection(3..<3))
        XCTAssertEqual(insertion.mutations.count, 1)
        XCTAssertEqual(insertion.mutations[0].sourceRange, 1..<1)
        XCTAssertEqual(insertion.mutations[0].replacementData, Data([0xAA, 0xBB]))
        XCTAssertEqual(insertion.mutations[0].resultRange, 1..<3)
        XCTAssertEqual(insertion.replacementCount, 1)
        XCTAssertTrue(insertion.didChangeContent)

        let replacement = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .characters("Z"), target: .currentSelection)),
            in: source
        )
        XCTAssertEqual(replacement.resultData, Data([0x10, 0x5A, 0x30]))
        XCTAssertEqual(replacement.resultSelection, selection(2..<2, surface: .characters))
        XCTAssertEqual(replacement.mutations[0].sourceRange, 1..<2)
        XCTAssertEqual(replacement.mutations[0].resultRange, 1..<2)
    }

    func testOverwriteAtOffsetAndSelectionRequiresExactSpan() throws {
        let source = pane([0x10, 0x20, 0x30, 0x40], selection: selection(1..<3))

        let atOffset = try BinaryHexEditingPolicy.plan(
            .edit(.overwrite(payload: .bytes(Data([0xAA, 0xBB])), target: .byteOffset(2))),
            in: source
        )
        XCTAssertEqual(atOffset.resultData, Data([0x10, 0x20, 0xAA, 0xBB]))
        XCTAssertEqual(atOffset.mutations[0].sourceRange, 2..<4)
        XCTAssertEqual(atOffset.resultSelection, selection(4..<4))

        let selected = try BinaryHexEditingPolicy.plan(
            .edit(.overwrite(payload: .characters("xy"), target: .currentSelection)),
            in: source
        )
        XCTAssertEqual(selected.resultData, Data([0x10, 0x78, 0x79, 0x40]))
        XCTAssertEqual(selected.mutations[0].sourceRange, 1..<3)
        XCTAssertEqual(selected.resultSelection, selection(3..<3, surface: .characters))
    }

    func testDeleteAndEmptyOrIdenticalEditsReportDistinctNoOpReasons() throws {
        let source = pane([0x10, 0x20, 0x30], selection: selection(1..<2, surface: .characters))
        let deletion = try BinaryHexEditingPolicy.plan(.edit(.delete()), in: source)

        XCTAssertEqual(deletion.resultData, Data([0x10, 0x30]))
        XCTAssertEqual(deletion.resultSelection, selection(1..<1, surface: .characters))
        XCTAssertEqual(deletion.mutations[0].sourceRange, 1..<2)
        XCTAssertEqual(deletion.mutations[0].replacementData, Data())

        let emptySource = pane([0x10], selection: selection(1..<1))
        let empty = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .bytes(Data()), target: .currentSelection)),
            in: emptySource
        )
        XCTAssertTrue(empty.isNoOp)
        XCTAssertEqual(empty.noOpReason, .emptyPayload)

        let identicalSource = pane([0x10], selection: selection(0..<1))
        let identical = try BinaryHexEditingPolicy.plan(
            .edit(.overwrite(payload: .bytes(Data([0x10])), target: .currentSelection)),
            in: identicalSource
        )
        XCTAssertTrue(identical.didChangeSelection)
        XCTAssertFalse(identical.didChangeContent)
        XCTAssertTrue(identical.hasEffect)
        XCTAssertNil(identical.noOpReason)

        let identicalAtInsertionPoint = pane([0x10], selection: selection(1..<1))
        let unchanged = try BinaryHexEditingPolicy.plan(
            .edit(.overwrite(payload: .bytes(Data()), target: .currentSelection)),
            in: identicalAtInsertionPoint
        )
        XCTAssertTrue(unchanged.isNoOp)
        XCTAssertEqual(unchanged.noOpReason, .emptyPayload)
    }

    func testOverwriteErrorsDistinguishLengthEndOffsetAndMalformedRange() {
        let source = pane([0x10, 0x20, 0x30], selection: selection(1..<3))

        assertPolicyError(.overwriteSelectionLengthMismatch(selectionBytes: 2, payloadBytes: 1)) {
            try BinaryHexEditingPolicy.plan(
                .edit(.overwrite(payload: .bytes(Data([0xAA])), target: .currentSelection)),
                in: source
            )
        }
        assertPolicyError(.overwriteBeyondEnd(range: 2..<4, byteCount: 3)) {
            try BinaryHexEditingPolicy.plan(
                .edit(.overwrite(payload: .bytes(Data([0xAA, 0xBB])), target: .byteOffset(2))),
                in: source
            )
        }
        assertPolicyError(.invalidByteOffset(offset: Int.max, byteCount: 3)) {
            try BinaryHexEditingPolicy.plan(
                .edit(.overwrite(payload: .bytes(Data([0xAA])), target: .byteOffset(Int.max))),
                in: source
            )
        }

        let overflowingRange = Int.min..<Int.max
        assertPolicyError(.invalidSelection(range: overflowingRange, byteCount: 3)) {
            try BinaryHexEditingPolicy.plan(
                .edit(
                    .overwrite(
                        payload: .bytes(Data([0xAA])),
                        target: .selection(selection(overflowingRange))
                    )
                ),
                in: source
            )
        }
    }

    func testReadOnlyPaneAllowsNavigationButRejectsMutationBeforePayloadValidation() throws {
        let source = pane(
            [0x10, 0x20, 0x10],
            selection: selection(0..<0),
            isReadOnly: true,
            pane: .right
        )

        XCTAssertEqual(
            try BinaryHexEditingPolicy.plan(
                .find(BinaryHexFindIntent(pattern: .bytes(Data([0x10])))),
                in: source
            ).resultSelection,
            selection(0..<1)
        )
        XCTAssertEqual(
            try BinaryHexEditingPolicy.plan(
                .selection(.selectAll(surface: .characters)),
                in: source
            ).resultSelection,
            selection(0..<3, surface: .characters)
        )
        assertPolicyError(.readOnlyPane(.right)) {
            try BinaryHexEditingPolicy.plan(
                .edit(.insert(payload: .bytes(Data(repeating: 0, count: 2)), target: .byteOffset(0))),
                in: source,
                limits: self.limits(maximumPayloadBytes: 1)
            )
        }
        assertPolicyError(.readOnlyPane(.right)) {
            try BinaryHexEditingPolicy.plan(
                .replace(
                    BinaryHexReplaceIntent(
                        pattern: .bytes(Data()),
                        replacement: .bytes(Data()),
                        scope: .all
                    )
                ),
                in: source
            )
        }
    }

    func testReadOnlyPaneRejectsEachValidMutationIntent() {
        let source = pane(
            [0x10, 0x20, 0x10],
            selection: selection(0..<1),
            isReadOnly: true,
            pane: .middle
        )
        let intents: [BinaryHexIntent] = [
            .edit(.insert(payload: .bytes(Data([0x30])), target: .byteOffset(1))),
            .edit(.delete(selection: selection(0..<1))),
            .edit(.overwrite(payload: .bytes(Data([0x30])), target: .currentSelection)),
            .replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([0x10])),
                    replacement: .bytes(Data([0x30])),
                    scope: .all
                )
            )
        ]

        for intent in intents {
            assertPolicyError(.readOnlyPane(.middle)) {
                try BinaryHexEditingPolicy.plan(intent, in: source)
            }
        }
    }

    func testForwardSearchStartsAfterSelectionAndWrapsOnlyWhenNeeded() throws {
        let source = pane(
            [0x41, 0x42, 0x41, 0x42, 0x41, 0x42],
            selection: selection(0..<2)
        )
        let pattern = BinaryHexSearchPattern.bytes(Data([0x41, 0x42]))

        let next = try BinaryHexEditingPolicy.plan(
            .find(BinaryHexFindIntent(pattern: pattern, direction: .forward, wraps: false)),
            in: source
        )
        XCTAssertEqual(next.resultSelection, selection(2..<4))
        XCTAssertFalse(next.didWrap)

        let explicit = try BinaryHexEditingPolicy.plan(
            .find(
                BinaryHexFindIntent(
                    pattern: pattern,
                    direction: .forward,
                    startByteOffset: 4,
                    wraps: false
                )
            ),
            in: source
        )
        XCTAssertEqual(explicit.resultSelection, selection(4..<6))

        let wrapped = try BinaryHexEditingPolicy.plan(
            .find(
                BinaryHexFindIntent(
                    pattern: pattern,
                    direction: .forward,
                    startByteOffset: 6,
                    wraps: true
                )
            ),
            in: source
        )
        XCTAssertEqual(wrapped.resultSelection, selection(0..<2))
        XCTAssertTrue(wrapped.didWrap)
        XCTAssertEqual(wrapped.noOpReason, .selectionUnchanged)

        let missing = try BinaryHexEditingPolicy.plan(
            .find(BinaryHexFindIntent(pattern: .bytes(Data([0xFF])), wraps: true)),
            in: source
        )
        XCTAssertEqual(missing.resultSelection, source.selection)
        XCTAssertEqual(missing.noOpReason, .patternNotFound)
        XCTAssertFalse(missing.didWrap)
    }

    func testBackwardSearchUsesSelectionStartAndWrapsToLastMatch() throws {
        let bytes: [UInt8] = [0x41, 0x42, 0x00, 0x41, 0x42, 0x00, 0x41, 0x42]
        let pattern = BinaryHexSearchPattern.bytes(Data([0x41, 0x42]))
        let source = pane(bytes, selection: selection(6..<8))

        let previous = try BinaryHexEditingPolicy.plan(
            .find(BinaryHexFindIntent(pattern: pattern, direction: .backward, wraps: false)),
            in: source
        )
        XCTAssertEqual(previous.resultSelection, selection(3..<5))
        XCTAssertFalse(previous.didWrap)

        let noWrap = try BinaryHexEditingPolicy.plan(
            .find(
                BinaryHexFindIntent(
                    pattern: pattern,
                    direction: .backward,
                    startByteOffset: 0,
                    wraps: false
                )
            ),
            in: source
        )
        XCTAssertEqual(noWrap.noOpReason, .patternNotFound)
        XCTAssertFalse(noWrap.didWrap)

        let wrapped = try BinaryHexEditingPolicy.plan(
            .find(
                BinaryHexFindIntent(
                    pattern: pattern,
                    direction: .backward,
                    startByteOffset: 0,
                    wraps: true
                )
            ),
            in: source
        )
        XCTAssertEqual(wrapped.resultSelection, selection(6..<8))
        XCTAssertTrue(wrapped.didWrap)
        XCTAssertEqual(wrapped.noOpReason, .selectionUnchanged)
    }

    func testWrappedSearchesChangeSelectionWhenWrappedResultIsDistinct() throws {
        let bytes: [UInt8] = [0x41, 0x42, 0x00, 0x41, 0x42]
        let pattern = BinaryHexSearchPattern.bytes(Data([0x41, 0x42]))
        let cases: [(BinaryHexSearchDirection, Int, BinaryHexSelection, Range<Int>)] = [
            (.forward, 5, selection(3..<5, surface: .characters), 0..<2),
            (.backward, 0, selection(0..<2), 3..<5)
        ]

        for (direction, start, initialSelection, expectedRange) in cases {
            let plan = try BinaryHexEditingPolicy.plan(
                .find(
                    BinaryHexFindIntent(
                        pattern: pattern,
                        direction: direction,
                        startByteOffset: start,
                        wraps: true
                    )
                ),
                in: pane(bytes, selection: initialSelection)
            )
            XCTAssertEqual(plan.resultSelection, selection(expectedRange))
            XCTAssertTrue(plan.didWrap)
            XCTAssertTrue(plan.didChangeSelection)
            XCTAssertNil(plan.noOpReason)
        }
    }

    func testCharacterSearchUsesConfiguredEncodingAndCharacterSurface() throws {
        let settings = display(characterSet: .utf16LittleEndian)
        let source = pane(
            [0x00, 0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE, 0x00],
            selection: selection(0..<0),
            displaySettings: settings
        )

        let plan = try BinaryHexEditingPolicy.plan(
            .find(
                BinaryHexFindIntent(
                    pattern: .characters("😀"),
                    direction: .forward,
                    startByteOffset: 0,
                    wraps: false
                )
            ),
            in: source
        )

        XCTAssertEqual(plan.resultSelection, selection(3..<7, surface: .characters))
        XCTAssertEqual(plan.resultData, source.data)
        XCTAssertFalse(plan.didChangeContent)
    }

    func testReplaceCurrentAndFirstProduceAtomicSingleMutationPlans() throws {
        let source = pane([1, 2, 0, 1, 2], selection: selection(0..<2))
        let current = try BinaryHexEditingPolicy.plan(
            .replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([1, 2])),
                    replacement: .bytes(Data([9])),
                    scope: .currentSelection
                )
            ),
            in: source
        )
        XCTAssertEqual(current.resultData, Data([9, 0, 1, 2]))
        XCTAssertEqual(current.resultSelection, selection(0..<1))
        XCTAssertEqual(current.mutations[0].sourceRange, 0..<2)
        XCTAssertEqual(current.mutations[0].resultRange, 0..<1)

        let first = try BinaryHexEditingPolicy.plan(
            .replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([1, 2])),
                    replacement: .characters("XY"),
                    scope: .first(fromByteOffset: 4, wraps: true)
                )
            ),
            in: source
        )
        XCTAssertEqual(first.resultData, Data([0x58, 0x59, 0, 1, 2]))
        XCTAssertEqual(first.resultSelection, selection(0..<2, surface: .characters))
        XCTAssertTrue(first.didWrap)
        XCTAssertEqual(first.replacementCount, 1)
    }

    func testReplaceAllUsesNonoverlappingMatchesAndCumulativeResultRanges() throws {
        let source = pane([1, 2, 1, 2, 1, 2], selection: selection(0..<0))
        let plan = try BinaryHexEditingPolicy.plan(
            .replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([1, 2])),
                    replacement: .bytes(Data([9, 8, 7])),
                    scope: .all
                )
            ),
            in: source
        )

        XCTAssertEqual(plan.resultData, Data([9, 8, 7, 9, 8, 7, 9, 8, 7]))
        XCTAssertEqual(plan.replacementCount, 3)
        XCTAssertEqual(plan.mutations.map(\.sourceRange), [0..<2, 2..<4, 4..<6])
        XCTAssertEqual(plan.mutations.map(\.resultRange), [0..<3, 3..<6, 6..<9])
        XCTAssertEqual(plan.resultSelection, selection(6..<9))
        XCTAssertFalse(plan.didWrap)

        let overlapping = try BinaryHexEditingPolicy.plan(
            .replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([1, 1])),
                    replacement: .bytes(Data([2])),
                    scope: .all
                )
            ),
            in: pane([1, 1, 1], selection: selection(0..<0))
        )
        XCTAssertEqual(overlapping.resultData, Data([2, 1]))
        XCTAssertEqual(overlapping.replacementCount, 1)
    }

    func testReplaceNoMatchAndIdenticalReplacementReasonsRemainDistinct() throws {
        let source = pane([1, 2, 3], selection: selection(0..<1))
        let notFound = try BinaryHexEditingPolicy.plan(
            .replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([9])),
                    replacement: .bytes(Data([8])),
                    scope: .all
                )
            ),
            in: source
        )
        XCTAssertTrue(notFound.isNoOp)
        XCTAssertEqual(notFound.noOpReason, .patternNotFound)
        XCTAssertEqual(notFound.mutations, [])

        let identical = try BinaryHexEditingPolicy.plan(
            .replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([1])),
                    replacement: .bytes(Data([1])),
                    scope: .currentSelection
                )
            ),
            in: source
        )
        XCTAssertTrue(identical.isNoOp)
        XCTAssertEqual(identical.noOpReason, .replacementIdentical)
        XCTAssertEqual(identical.replacementCount, 1)
        XCTAssertEqual(identical.mutations.count, 1)
    }

    func testReplacementCountLimitAcceptsExactCountAndRejectsOneMoreAtomically() throws {
        let source = pane([1, 1, 1], selection: selection(0..<0))
        let intent = BinaryHexIntent.replace(
            BinaryHexReplaceIntent(
                pattern: .bytes(Data([1])),
                replacement: .bytes(Data([2])),
                scope: .all
            )
        )

        let exact = try BinaryHexEditingPolicy.plan(
            intent,
            in: source,
            limits: limits(maximumReplacements: 3)
        )
        XCTAssertEqual(exact.replacementCount, 3)
        XCTAssertEqual(exact.resultData, Data([2, 2, 2]))

        assertPolicyError(.tooManyReplacements(maximum: 2)) {
            try BinaryHexEditingPolicy.plan(
                intent,
                in: source,
                limits: self.limits(maximumReplacements: 2)
            )
        }
        XCTAssertEqual(source.data, Data([1, 1, 1]))
        XCTAssertEqual(source.selection, selection(0..<0))
    }

    func testReplaceAllCumulativeOutputLimitAcceptsExactAndRejectsOneMoreForPolicyAndPane() throws {
        let intent = BinaryHexIntent.replace(
            BinaryHexReplaceIntent(
                pattern: .bytes(Data([1, 2])),
                replacement: .bytes(Data([9, 8, 7])),
                scope: .all
            )
        )
        let policySource = pane(
            [1, 2, 1, 2, 1, 2],
            selection: selection(0..<0),
            maximumByteCount: 100
        )
        let exactPolicy = try BinaryHexEditingPolicy.plan(
            intent,
            in: policySource,
            limits: limits(maximumOutputBytes: 9)
        )
        XCTAssertEqual(exactPolicy.resultData, Data([9, 8, 7, 9, 8, 7, 9, 8, 7]))
        XCTAssertEqual(exactPolicy.replacementCount, 3)
        assertPolicyError(.outputTooLarge(maximumBytes: 8)) {
            try BinaryHexEditingPolicy.plan(
                intent,
                in: policySource,
                limits: self.limits(maximumOutputBytes: 8)
            )
        }

        let exactPaneSource = pane(
            [1, 2, 1, 2, 1, 2],
            selection: selection(0..<0),
            maximumByteCount: 9
        )
        XCTAssertEqual(
            try BinaryHexEditingPolicy.plan(intent, in: exactPaneSource).resultData.count,
            9
        )
        let narrowPaneSource = pane(
            [1, 2, 1, 2, 1, 2],
            selection: selection(0..<0),
            maximumByteCount: 8
        )
        assertPolicyError(.outputTooLarge(maximumBytes: 8)) {
            try BinaryHexEditingPolicy.plan(intent, in: narrowPaneSource)
        }
        XCTAssertEqual(policySource.data, Data([1, 2, 1, 2, 1, 2]))
        XCTAssertEqual(narrowPaneSource.data, Data([1, 2, 1, 2, 1, 2]))
    }

    func testGoToSupportsOffsetRowRoundedPercentAndEnd() throws {
        let source = pane(
            Array(0..<20),
            selection: selection(0..<0),
            displaySettings: display(bytesPerRow: 8)
        )
        let cases: [(BinaryHexGoToTarget, Int)] = [
            (.byteOffset(7), 7),
            (.row(index: 2, column: 3), 19),
            (.percent(12.5), 3),
            (.percent(100), 20),
            (.end, 20)
        ]

        for (target, expectedOffset) in cases {
            let plan = try BinaryHexEditingPolicy.plan(
                .goTo(BinaryHexGoToIntent(target: target, surface: .characters)),
                in: source
            )
            XCTAssertEqual(
                plan.resultSelection,
                selection(expectedOffset..<expectedOffset, surface: .characters)
            )
            XCTAssertFalse(plan.didChangeContent)
        }

        let unchanged = try BinaryHexEditingPolicy.plan(
            .goTo(BinaryHexGoToIntent(target: .byteOffset(0))),
            in: source
        )
        XCTAssertEqual(unchanged.noOpReason, .destinationUnchanged)
        XCTAssertTrue(unchanged.isNoOp)
    }

    func testGoToRejectsInvalidAndOverflowingDestinationsAndNormalizesSignedZeroFingerprint() throws {
        let source = pane(
            Array(0..<20),
            selection: selection(4..<4),
            displaySettings: display(bytesPerRow: 8)
        )
        assertPolicyError(.invalidByteOffset(offset: -1, byteCount: 20)) {
            try BinaryHexEditingPolicy.plan(
                .goTo(BinaryHexGoToIntent(target: .byteOffset(-1))),
                in: source
            )
        }
        for (index, column) in [(-1, 0), (0, -1), (0, 8), (2, 5), (Int.max, 1)] {
            assertPolicyError(.invalidRow(index: index, column: column)) {
                try BinaryHexEditingPolicy.plan(
                    .goTo(BinaryHexGoToIntent(target: .row(index: index, column: column))),
                    in: source
                )
            }
        }
        for percent in [Double.nan, .infinity, -.infinity] {
            assertPolicyError(.nonFinitePercent) {
                try BinaryHexEditingPolicy.plan(
                    .goTo(BinaryHexGoToIntent(target: .percent(percent))),
                    in: source
                )
            }
        }
        assertPolicyError(.percentOutsideRange(-0.1)) {
            try BinaryHexEditingPolicy.plan(
                .goTo(BinaryHexGoToIntent(target: .percent(-0.1))),
                in: source
            )
        }
        assertPolicyError(.percentOutsideRange(100.1)) {
            try BinaryHexEditingPolicy.plan(
                .goTo(BinaryHexGoToIntent(target: .percent(100.1))),
                in: source
            )
        }

        let positive = try BinaryHexEditingPolicy.plan(
            .goTo(BinaryHexGoToIntent(target: .percent(0.0))),
            in: source
        )
        let negative = try BinaryHexEditingPolicy.plan(
            .goTo(BinaryHexGoToIntent(target: .percent(-0.0))),
            in: source
        )
        let roundedNonzero = try BinaryHexEditingPolicy.plan(
            .goTo(BinaryHexGoToIntent(target: .percent(0.1))),
            in: source
        )
        XCTAssertEqual(positive.fingerprint, negative.fingerprint)
        XCTAssertEqual(positive, negative)
        XCTAssertEqual(positive.resultSelection, roundedNonzero.resultSelection)
        XCTAssertNotEqual(positive.fingerprint, roundedNonzero.fingerprint)
        XCTAssertNotEqual(positive.intent, roundedNonzero.intent)
    }

    func testDisplaySettingsAndStatusProjectEveryVisibleField() throws {
        let settings = display(
            bytesPerRow: 8,
            byteGroupSize: 4,
            characterSet: .windows1252,
            offsetRadix: .decimal,
            usesUppercaseHex: false,
            showsOffsetColumn: false,
            showsCharacterColumn: false,
            editMode: .insert
        )
        let source = pane(
            Array(0..<20),
            persisted: Array(0..<19),
            selection: selection(10..<13, surface: .characters),
            displaySettings: settings,
            isReadOnly: true,
            pane: .middle,
            revision: 42
        )

        let status = try BinaryHexEditingPolicy.status(for: source)
        XCTAssertEqual(status.pane, .middle)
        XCTAssertEqual(status.sourceVersion, source.version)
        XCTAssertFalse(status.requiresNewRevision)
        XCTAssertEqual(status.byteCount, 20)
        XCTAssertEqual(status.byteOffset, 10)
        XCTAssertEqual(status.row, 1)
        XCTAssertEqual(status.column, 2)
        XCTAssertEqual(status.selection, source.selection)
        XCTAssertEqual(status.selectedByteCount, 3)
        XCTAssertFalse(status.isInsertionPoint)
        XCTAssertEqual(status.currentByte, 10)
        XCTAssertEqual(status.characterSet, .windows1252)
        XCTAssertEqual(status.editMode, .insert)
        XCTAssertTrue(status.isReadOnly)
        XCTAssertTrue(status.isDirty)

        let changedSettings = display(bytesPerRow: 4, byteGroupSize: 2, editMode: .overwrite)
        let changed = try BinaryHexEditingPolicy.plan(
            .displaySettings(changedSettings),
            in: source
        )
        XCTAssertEqual(changed.resultDisplaySettings, changedSettings)
        XCTAssertTrue(changed.didChangeDisplaySettings)
        XCTAssertTrue(changed.hasEffect)
        XCTAssertFalse(changed.didChangeContent)
        XCTAssertEqual(changed.statusAfter.row, 2)
        XCTAssertEqual(changed.statusAfter.column, 2)

        let unchanged = try BinaryHexEditingPolicy.plan(
            .displaySettings(source.displaySettings),
            in: source
        )
        XCTAssertEqual(unchanged.noOpReason, .displaySettingsUnchanged)
        XCTAssertTrue(unchanged.isNoOp)
    }

    func testEveryCharacterSetEncodesExactBytes() throws {
        let cases: [(BinaryHexCharacterSet, String, [UInt8])] = [
            (.ascii, "A", [0x41]),
            (.isoLatin1, "é", [0xE9]),
            (.windows1252, "€", [0x80]),
            (.utf8, "😀", [0xF0, 0x9F, 0x98, 0x80]),
            (.utf16LittleEndian, "😀", [0x3D, 0xD8, 0x00, 0xDE]),
            (.utf16BigEndian, "😀", [0xD8, 0x3D, 0xDE, 0x00])
        ]

        for (characterSet, text, expected) in cases {
            let source = pane(
                [],
                selection: selection(0..<0),
                displaySettings: display(characterSet: characterSet)
            )
            let plan = try BinaryHexEditingPolicy.plan(
                .edit(.insert(payload: .characters(text), target: .byteOffset(0))),
                in: source
            )
            XCTAssertEqual(plan.resultData, Data(expected), "Character set: \(characterSet)")
            XCTAssertEqual(
                plan.resultSelection,
                selection(expected.count..<expected.count, surface: .characters)
            )
        }
    }

    func testSingleByteCharacterSetsCoverFullMappingsAndUndefinedC1Scalars() throws {
        let directMappingCases: [(BinaryHexCharacterSet, ClosedRange<UInt32>, UInt32)] = [
            (.ascii, 0x00...0x7F, 0x80),
            (.isoLatin1, 0x00...0xFF, 0x100)
        ]
        for (characterSet, scalars, rejectedScalar) in directMappingCases {
            let source = pane(
                [],
                selection: selection(0..<0),
                displaySettings: display(characterSet: characterSet)
            )
            let text = String(
                String.UnicodeScalarView(scalars.map { Unicode.Scalar($0)! })
            )
            XCTAssertEqual(
                try BinaryHexEditingPolicy.plan(
                    .edit(.insert(payload: .characters(text), target: .byteOffset(0))),
                    in: source
                ).resultData,
                Data(scalars.map { UInt8($0) })
            )
            assertPolicyError(
                .characterNotRepresentable(characterSet: characterSet, scalar: rejectedScalar)
            ) {
                try BinaryHexEditingPolicy.plan(
                    .edit(
                        .insert(
                            payload: .characters(String(Unicode.Scalar(rejectedScalar)!)),
                            target: .byteOffset(0)
                        )
                    ),
                    in: source
                )
            }
        }

        let mappings: [(UInt32, UInt8)] = [
            (0x20AC, 0x80), (0x201A, 0x82), (0x0192, 0x83), (0x201E, 0x84),
            (0x2026, 0x85), (0x2020, 0x86), (0x2021, 0x87), (0x02C6, 0x88),
            (0x2030, 0x89), (0x0160, 0x8A), (0x2039, 0x8B), (0x0152, 0x8C),
            (0x017D, 0x8E), (0x2018, 0x91), (0x2019, 0x92), (0x201C, 0x93),
            (0x201D, 0x94), (0x2022, 0x95), (0x2013, 0x96), (0x2014, 0x97),
            (0x02DC, 0x98), (0x2122, 0x99), (0x0161, 0x9A), (0x203A, 0x9B),
            (0x0153, 0x9C), (0x017E, 0x9E), (0x0178, 0x9F)
        ]
        let windowsSource = pane(
            [],
            selection: selection(0..<0),
            displaySettings: display(characterSet: .windows1252)
        )
        let mappedText = String(
            String.UnicodeScalarView(mappings.map { Unicode.Scalar($0.0)! })
        )
        XCTAssertEqual(
            try BinaryHexEditingPolicy.plan(
                .edit(.insert(payload: .characters(mappedText), target: .byteOffset(0))),
                in: windowsSource
            ).resultData,
            Data(mappings.map(\.1))
        )
        for scalar in [UInt32(0x81), 0x8D, 0x8F, 0x90, 0x9D] {
            assertPolicyError(.characterNotRepresentable(characterSet: .windows1252, scalar: scalar)) {
                try BinaryHexEditingPolicy.plan(
                    .edit(
                        .insert(
                            payload: .characters(String(Unicode.Scalar(scalar)!)),
                            target: .byteOffset(0)
                        )
                    ),
                    in: windowsSource
                )
            }
        }
    }

    func testCharacterEncodingErrorsAndUTF8InputBoundaryAreExact() throws {
        let ascii = pane(
            [],
            selection: selection(0..<0),
            displaySettings: display(characterSet: .ascii)
        )
        assertPolicyError(.characterNotRepresentable(characterSet: .ascii, scalar: 0xE9)) {
            try BinaryHexEditingPolicy.plan(
                .edit(.insert(payload: .characters("é"), target: .byteOffset(0))),
                in: ascii
            )
        }
        let windows = pane(
            [],
            selection: selection(0..<0),
            displaySettings: display(characterSet: .windows1252)
        )
        assertPolicyError(.characterNotRepresentable(characterSet: .windows1252, scalar: 0x81)) {
            try BinaryHexEditingPolicy.plan(
                .edit(.insert(payload: .characters("\u{81}"), target: .byteOffset(0))),
                in: windows
            )
        }

        let exact = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .characters("é"), target: .byteOffset(0))),
            in: pane(
                [],
                selection: selection(0..<0),
                displaySettings: display(characterSet: .utf8)
            ),
            limits: limits(maximumPayloadBytes: 2, maximumCharacterInputUTF8Bytes: 2)
        )
        XCTAssertEqual(exact.resultData, Data([0xC3, 0xA9]))
        assertPolicyError(.characterInputTooLarge(maximumUTF8Bytes: 1)) {
            try BinaryHexEditingPolicy.plan(
                .edit(.insert(payload: .characters("é"), target: .byteOffset(0))),
                in: self.pane(
                    [],
                    selection: self.selection(0..<0),
                    displaySettings: self.display(characterSet: .utf8)
                ),
                limits: self.limits(maximumCharacterInputUTF8Bytes: 1)
            )
        }
    }

    func testCharacterInputAndEncodedOutputLimitsRemainIndependentForPayloadsAndPatterns() throws {
        let windowsSource = pane(
            [0x80],
            selection: selection(0..<0),
            displaySettings: display(characterSet: .windows1252)
        )
        let compactPayload = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .characters("€"), target: .byteOffset(0))),
            in: windowsSource,
            limits: limits(maximumPayloadBytes: 1, maximumCharacterInputUTF8Bytes: 3)
        )
        XCTAssertEqual(Array(compactPayload.mutations[0].replacementData), [0x80])
        assertPolicyError(.characterInputTooLarge(maximumUTF8Bytes: 2)) {
            try BinaryHexEditingPolicy.plan(
                .find(BinaryHexFindIntent(pattern: .characters("€"))),
                in: windowsSource,
                limits: self.limits(maximumCharacterInputUTF8Bytes: 2, maximumPatternBytes: 1)
            )
        }
        XCTAssertEqual(
            try BinaryHexEditingPolicy.plan(
                .find(BinaryHexFindIntent(pattern: .characters("€"))),
                in: windowsSource,
                limits: limits(maximumCharacterInputUTF8Bytes: 3, maximumPatternBytes: 1)
            ).resultSelection,
            selection(0..<1, surface: .characters)
        )

        let utf16Source = pane(
            [0x00, 0x41],
            selection: selection(0..<0),
            displaySettings: display(characterSet: .utf16BigEndian)
        )
        let expandedPayload = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .characters("A"), target: .byteOffset(0))),
            in: utf16Source,
            limits: limits(maximumPayloadBytes: 2, maximumCharacterInputUTF8Bytes: 1)
        )
        XCTAssertEqual(Array(expandedPayload.mutations[0].replacementData), [0x00, 0x41])
        assertPolicyError(.payloadTooLarge(maximumBytes: 1)) {
            try BinaryHexEditingPolicy.plan(
                .edit(.insert(payload: .characters("A"), target: .byteOffset(0))),
                in: utf16Source,
                limits: self.limits(maximumPayloadBytes: 1, maximumCharacterInputUTF8Bytes: 1)
            )
        }
        assertPolicyError(.patternTooLarge(maximumBytes: 1)) {
            try BinaryHexEditingPolicy.plan(
                .find(BinaryHexFindIntent(pattern: .characters("A"))),
                in: utf16Source,
                limits: self.limits(maximumPatternBytes: 1)
            )
        }
    }

    func testCharacterInputLimitCoversEveryUTF8ScalarWidthBoundary() throws {
        let cases: [(String, Int, [UInt8])] = [
            ("\u{7F}", 1, [0x7F]),
            ("\u{80}", 2, [0xC2, 0x80]),
            ("\u{800}", 3, [0xE0, 0xA0, 0x80]),
            ("\u{10000}", 4, [0xF0, 0x90, 0x80, 0x80])
        ]
        let source = pane(
            [],
            selection: selection(0..<0),
            displaySettings: display(characterSet: .utf8)
        )

        for (text, utf8Count, expected) in cases {
            let exact = try BinaryHexEditingPolicy.plan(
                .edit(.insert(payload: .characters(text), target: .byteOffset(0))),
                in: source,
                limits: limits(
                    maximumPayloadBytes: utf8Count,
                    maximumCharacterInputUTF8Bytes: utf8Count
                )
            )
            XCTAssertEqual(Array(exact.resultData), expected)
            assertPolicyError(.characterInputTooLarge(maximumUTF8Bytes: utf8Count - 1)) {
                try BinaryHexEditingPolicy.plan(
                    .edit(.insert(payload: .characters(text), target: .byteOffset(0))),
                    in: source,
                    limits: self.limits(
                        maximumPayloadBytes: utf8Count,
                        maximumCharacterInputUTF8Bytes: utf8Count - 1
                    )
                )
            }
        }
    }

    func testSnapshotValidationReportsSelectionDisplayDirtyAndMaximumReasons() {
        let malformedRange = Int.min..<Int.max
        assertPolicyError(.invalidSelection(range: malformedRange, byteCount: 1)) {
            try BinaryHexEditingPolicy.status(
                for: self.pane([1], selection: self.selection(malformedRange))
            )
        }
        assertPolicyError(.invalidDisplaySettings) {
            try BinaryHexEditingPolicy.status(
                for: self.pane(
                    [1],
                    selection: self.selection(0..<0),
                    displaySettings: self.display(bytesPerRow: 3, byteGroupSize: 2)
                )
            )
        }
        assertPolicyError(.inconsistentDirtyState) {
            try BinaryHexEditingPolicy.status(
                for: self.pane(
                    [1],
                    persisted: [2],
                    selection: self.selection(0..<0),
                    isDirty: false
                )
            )
        }
        assertPolicyError(.invalidMaximumByteCount(-1)) {
            try BinaryHexEditingPolicy.status(
                for: self.pane(
                    [],
                    selection: self.selection(0..<0),
                    maximumByteCount: -1
                )
            )
        }
        assertPolicyError(.invalidMaximumByteCount(1)) {
            try BinaryHexEditingPolicy.status(
                for: self.pane(
                    [1, 2],
                    selection: self.selection(0..<0),
                    maximumByteCount: 1
                )
            )
        }
    }

    func testEveryInvalidLimitFamilyReturnsTypedInvalidLimits() {
        let source = pane([], selection: selection(0..<0), maximumByteCount: 0)
        let invalidLimits = [
            limits(maximumInputBytes: -1),
            limits(maximumPersistedBytes: -1),
            limits(maximumPayloadBytes: -1),
            limits(maximumCharacterInputUTF8Bytes: -1),
            limits(maximumPatternBytes: 0),
            limits(maximumOutputBytes: -1),
            limits(maximumReplacements: 0),
            limits(maximumPlanBytes: -1),
            limits(maximumWork: -1),
            limits(cancellationCheckInterval: 0)
        ]

        for invalid in invalidLimits {
            assertPolicyError(.invalidLimits) {
                try BinaryHexEditingPolicy.status(for: source, limits: invalid)
            }
        }
    }

    func testInputAndPersistedDataLimitsAcceptExactCountsAndRejectOneMore() throws {
        let exact = pane([1, 2], persisted: [1, 3], selection: selection(0..<0))
        XCTAssertEqual(
            try BinaryHexEditingPolicy.status(
                for: exact,
                limits: limits(maximumInputBytes: 2, maximumPersistedBytes: 2)
            ).byteCount,
            2
        )

        assertPolicyError(.inputTooLarge(maximumBytes: 1)) {
            try BinaryHexEditingPolicy.status(
                for: exact,
                limits: self.limits(maximumInputBytes: 1, maximumPersistedBytes: 2)
            )
        }
        assertPolicyError(.persistedDataTooLarge(maximumBytes: 1)) {
            try BinaryHexEditingPolicy.status(
                for: exact,
                limits: self.limits(maximumInputBytes: 2, maximumPersistedBytes: 1)
            )
        }
    }

    func testPayloadAndPatternLimitsAcceptExactBytesAndRejectOneMore() throws {
        let source = pane([1, 2], selection: selection(0..<0))
        let payload = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .bytes(Data([3, 4])), target: .byteOffset(2))),
            in: source,
            limits: limits(maximumPayloadBytes: 2)
        )
        XCTAssertEqual(payload.resultData, Data([1, 2, 3, 4]))
        assertPolicyError(.payloadTooLarge(maximumBytes: 1)) {
            try BinaryHexEditingPolicy.plan(
                .edit(.insert(payload: .bytes(Data([3, 4])), target: .byteOffset(2))),
                in: source,
                limits: self.limits(maximumPayloadBytes: 1)
            )
        }

        let pattern = try BinaryHexEditingPolicy.plan(
            .find(BinaryHexFindIntent(pattern: .bytes(Data([1, 2])))),
            in: source,
            limits: limits(maximumPatternBytes: 2)
        )
        XCTAssertEqual(pattern.resultSelection, selection(0..<2))
        assertPolicyError(.patternTooLarge(maximumBytes: 1)) {
            try BinaryHexEditingPolicy.plan(
                .find(BinaryHexFindIntent(pattern: .bytes(Data([1, 2])))),
                in: source,
                limits: self.limits(maximumPatternBytes: 1)
            )
        }
        assertPolicyError(.emptySearchPattern) {
            try BinaryHexEditingPolicy.plan(
                .find(BinaryHexFindIntent(pattern: .characters(""))),
                in: source
            )
        }
    }

    func testOutputLimitAndPaneMaximumAcceptExactResultAndRejectOneMore() throws {
        let source = pane([1, 2], selection: selection(2..<2), maximumByteCount: 3)
        let intent = BinaryHexIntent.edit(
            .insert(payload: .bytes(Data([3])), target: .currentSelection)
        )

        let exact = try BinaryHexEditingPolicy.plan(
            intent,
            in: source,
            limits: limits(maximumOutputBytes: 3)
        )
        XCTAssertEqual(exact.resultData, Data([1, 2, 3]))

        assertPolicyError(.outputTooLarge(maximumBytes: 2)) {
            try BinaryHexEditingPolicy.plan(
                intent,
                in: source,
                limits: self.limits(maximumOutputBytes: 2)
            )
        }
        assertPolicyError(.outputTooLarge(maximumBytes: 3)) {
            try BinaryHexEditingPolicy.plan(
                .edit(
                    .insert(
                        payload: .bytes(Data([3, 4])),
                        target: .currentSelection
                    )
                ),
                in: source,
                limits: self.limits(maximumOutputBytes: 10)
            )
        }
        XCTAssertEqual(source.data, Data([1, 2]))
    }

    func testRetainedPlanMemoryLimitAcceptsExactCountAndRejectsOneLess() throws {
        let source = pane([1, 2], persisted: [1, 0], selection: selection(1..<2))
        let intent = BinaryHexIntent.edit(
            .insert(payload: .bytes(Data([7, 8])), target: .currentSelection)
        )
        let baseline = try BinaryHexEditingPolicy.plan(intent, in: source)
        XCTAssertGreaterThan(baseline.retainedByteCount, 0)

        let exact = try BinaryHexEditingPolicy.plan(
            intent,
            in: source,
            limits: limits(maximumPlanBytes: baseline.retainedByteCount)
        )
        XCTAssertEqual(exact.retainedByteCount, baseline.retainedByteCount)

        assertPolicyError(.planTooLarge(maximumBytes: baseline.retainedByteCount - 1)) {
            try BinaryHexEditingPolicy.plan(
                intent,
                in: source,
                limits: self.limits(maximumPlanBytes: baseline.retainedByteCount - 1)
            )
        }
    }

    func testWorkLimitAcceptsExactConsumedUnitsAndRejectsOneLess() throws {
        let source = pane([1, 2, 1, 2], selection: selection(0..<0))
        let intent = BinaryHexIntent.replace(
            BinaryHexReplaceIntent(
                pattern: .bytes(Data([1, 2])),
                replacement: .bytes(Data([3, 4, 5])),
                scope: .all
            )
        )
        let baseline = try BinaryHexEditingPolicy.plan(intent, in: source)
        XCTAssertGreaterThan(baseline.workUnitsConsumed, 0)

        let exact = try BinaryHexEditingPolicy.plan(
            intent,
            in: source,
            limits: limits(maximumWork: baseline.workUnitsConsumed)
        )
        XCTAssertEqual(exact.workUnitsConsumed, baseline.workUnitsConsumed)

        assertPolicyError(.workLimitExceeded(maximumWork: baseline.workUnitsConsumed - 1)) {
            try BinaryHexEditingPolicy.plan(
                intent,
                in: source,
                limits: self.limits(maximumWork: baseline.workUnitsConsumed - 1)
            )
        }
    }

    func testWorkUnitAccountingMatchesFixedPublicVectors() throws {
        let vectors: [(BinaryHexIntent, BinaryHexPaneSnapshot, Int)] = [
            (
                .selection(.selectAll(surface: .bytes)),
                pane([1, 2], selection: selection(0..<0)),
                54
            ),
            (
                .find(
                    BinaryHexFindIntent(
                        pattern: .bytes(Data([9])),
                        direction: .forward,
                        wraps: false
                    )
                ),
                pane([1, 2, 3], selection: selection(0..<0)),
                68
            ),
            (
                .edit(.insert(payload: .characters("€"), target: .byteOffset(0))),
                pane(
                    [],
                    selection: selection(0..<0),
                    displaySettings: display(characterSet: .windows1252)
                ),
                55
            ),
            (
                .replace(
                    BinaryHexReplaceIntent(
                        pattern: .bytes(Data([1, 2])),
                        replacement: .bytes(Data([3, 4, 5])),
                        scope: .all
                    )
                ),
                pane([1, 2, 1, 2], selection: selection(0..<0)),
                103
            )
        ]

        for (intent, source, expectedWork) in vectors {
            XCTAssertEqual(
                try BinaryHexEditingPolicy.plan(intent, in: source, limits: limits())
                    .workUnitsConsumed,
                expectedWork,
                "Intent: \(intent)"
            )
        }
    }

    func testPlansAndFingerprintsAreDeterministicAndScalarExact() throws {
        let source = pane(
            [0xC3, 0x85],
            selection: selection(0..<2),
            displaySettings: display(characterSet: .utf8),
            revision: 9
        )
        let intent = BinaryHexIntent.edit(
            .insert(payload: .characters("Å"), target: .currentSelection)
        )
        let first = try BinaryHexEditingPolicy.plan(intent, in: source)
        let repeated = try BinaryHexEditingPolicy.plan(intent, in: source)
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.fingerprint, repeated.fingerprint)
        XCTAssertEqual(first.transaction, repeated.transaction)

        let canonicalIntent = BinaryHexIntent.edit(
            .insert(payload: .characters("A\u{30A}"), target: .currentSelection)
        )
        let canonical = try BinaryHexEditingPolicy.plan(canonicalIntent, in: source)
        XCTAssertEqual("Å", "A\u{30A}")
        XCTAssertNotEqual(intent, canonicalIntent)
        XCTAssertNotEqual(first.fingerprint, canonical.fingerprint)
        XCTAssertNotEqual(first, canonical)

        let changedRevision = pane(
            [0xC3, 0x85],
            selection: selection(0..<2),
            displaySettings: display(characterSet: .utf8),
            revision: 10
        )
        XCTAssertNotEqual(
            first.fingerprint,
            try BinaryHexEditingPolicy.plan(intent, in: changedRevision).fingerprint
        )
    }

    func testFingerprintWordsMatchGoldenPublicVectors() throws {
        let selectionPlan = try BinaryHexEditingPolicy.plan(
            .selection(.set(selection(1..<2, surface: .characters))),
            in: pane([0x10, 0x20], selection: selection(0..<0)),
            limits: limits()
        )
        XCTAssertEqual(selectionPlan.fingerprint.low, 12_342_706_441_144_928_012)
        XCTAssertEqual(selectionPlan.fingerprint.high, 8_968_998_422_932_081_352)

        let replacementPlan = try BinaryHexEditingPolicy.plan(
            .replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([1, 2])),
                    replacement: .bytes(Data([3, 4, 5])),
                    scope: .all
                )
            ),
            in: pane([1, 2, 1, 2], selection: selection(0..<0)),
            limits: limits()
        )
        XCTAssertEqual(replacementPlan.fingerprint.low, 8_763_767_498_458_537_833)
        XCTAssertEqual(replacementPlan.fingerprint.high, 4_890_652_548_629_646_371)
    }

    func testSuccessfulExecutionProducesDeterministicReceiptsAndCorrectRevisionRules() async throws {
        let source = pane([1, 2], selection: selection(1..<1), revision: 12)
        let effect = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .bytes(Data([9])), target: .currentSelection)),
            in: source
        )
        let firstOwner = BinaryHexPolicyTestExecutor(pane: source)
        let secondOwner = BinaryHexPolicyTestExecutor(pane: source)

        let first = try await firstOwner.execute(effect)
        let repeated = try await secondOwner.execute(effect)
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.fingerprint, effect.fingerprint)
        XCTAssertEqual(first.sourceVersion, source.version)
        XCTAssertEqual(first.mutationCount, 1)
        XCTAssertEqual(first.replacementCount, 1)
        XCTAssertEqual(first.workUnitsConsumed, effect.workUnitsConsumed)
        XCTAssertEqual(first.committedPane.version.identity, source.version.identity)
        XCTAssertEqual(first.committedPane.version.revision, 13)
        XCTAssertEqual(first.committedPane.data, Data([1, 9, 2]))
        XCTAssertTrue(first.committedPane.isDirty)

        let noOpSource = pane([1, 2], selection: selection(0..<0), revision: 20)
        let noOp = try BinaryHexEditingPolicy.plan(
            .selection(.set(noOpSource.selection)),
            in: noOpSource
        )
        let noOpOwner = BinaryHexPolicyTestExecutor(pane: noOpSource)
        let noOpReceipt = try await noOpOwner.execute(noOp)
        XCTAssertEqual(noOpReceipt.committedPane.version, noOpSource.version)
        XCTAssertEqual(noOpReceipt.committedPane, noOpSource)
    }

    func testReplaceAllTransactionCommitsOneAtomicBatchAndRejectedCASMutatesNothing() async throws {
        let source = pane([1, 2, 1, 2, 1, 2], selection: selection(0..<0), revision: 70)
        let plan = try BinaryHexEditingPolicy.plan(
            .replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([1, 2])),
                    replacement: .bytes(Data([9, 8, 7])),
                    scope: .all
                )
            ),
            in: source
        )
        XCTAssertEqual(plan.mutations.count, 3)

        let committing = BinaryHexPolicyTestExecutor(pane: source)
        let receipt = try await committing.execute(plan)
        let committedSnapshot = await committing.snapshot()
        let compareCount = await committing.compareCount()
        let commitCount = await committing.commitCount()
        XCTAssertEqual(compareCount, 1)
        XCTAssertEqual(commitCount, 1)
        XCTAssertEqual(receipt.mutationCount, 3)
        XCTAssertEqual(committedSnapshot, receipt.committedPane)
        XCTAssertEqual(committedSnapshot.data, plan.resultData)
        XCTAssertEqual(committedSnapshot.version.revision, 71)

        let rejecting = BinaryHexPolicyTestExecutor(pane: source, mode: .reject)
        await assertAsyncPolicyError(.inconsistentCommitOutcome) {
            try await rejecting.execute(plan)
        }
        let rejectedSnapshot = await rejecting.snapshot()
        let rejectedCompareCount = await rejecting.compareCount()
        let rejectedCommitCount = await rejecting.commitCount()
        XCTAssertEqual(rejectedCompareCount, 1)
        XCTAssertEqual(rejectedCommitCount, 0)
        XCTAssertEqual(rejectedSnapshot, source)
    }

    func testCASConflictsDistinguishPaneIdentityAndRevisionWithoutCommit() async throws {
        let source = pane([1, 2], selection: selection(0..<1), pane: .left, revision: 7)
        let plan = try BinaryHexEditingPolicy.plan(.edit(.delete()), in: source)
        let otherIdentity = BinaryHexContentIdentity(
            rawValue: UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!
        )
        let cases: [(BinaryHexPaneSnapshot, BinaryHexPolicyError)] = [
            (
                pane([1, 2], selection: source.selection, pane: .right, revision: 7),
                .paneChanged(expected: .left, actual: .right)
            ),
            (
                pane(
                    [1, 2],
                    selection: source.selection,
                    pane: .left,
                    identity: otherIdentity,
                    revision: 7
                ),
                .contentIdentityChanged(expected: identity, actual: otherIdentity)
            ),
            (
                pane([1, 2], selection: source.selection, pane: .left, revision: 8),
                .revisionChanged(expected: 7, actual: 8)
            )
        ]

        for (live, expectedError) in cases {
            let owner = BinaryHexPolicyTestExecutor(pane: live)
            await assertAsyncPolicyError(expectedError) {
                try await owner.execute(plan)
            }
            let actual = await owner.snapshot()
            let commitCount = await owner.commitCount()
            XCTAssertEqual(actual, live)
            XCTAssertEqual(commitCount, 0)
        }
    }

    func testCASConflictsDistinguishEveryCompleteStateFieldWithoutCommit() async throws {
        let source = pane([1, 2], selection: selection(0..<1), revision: 7)
        let plan = try BinaryHexEditingPolicy.plan(.edit(.delete()), in: source)
        let alteredDisplay = display(bytesPerRow: 8)
        let cases: [(BinaryHexPaneSnapshot, BinaryHexPolicyError)] = [
            (
                pane([9, 2], persisted: [1, 2], selection: source.selection, isDirty: false, revision: 7),
                .contentChanged
            ),
            (
                pane([1, 2], persisted: [1, 9], selection: source.selection, isDirty: false, revision: 7),
                .persistedDataChanged
            ),
            (
                pane([1, 2], selection: selection(1..<2), revision: 7),
                .selectionChanged
            ),
            (
                pane([1, 2], selection: source.selection, displaySettings: alteredDisplay, revision: 7),
                .displaySettingsChanged
            ),
            (
                pane([1, 2], selection: source.selection, isReadOnly: true, revision: 7),
                .readOnlyStateChanged
            ),
            (
                pane([1, 2], selection: source.selection, isDirty: true, revision: 7),
                .dirtyStateChanged
            ),
            (
                pane([1, 2], selection: source.selection, maximumByteCount: 99, revision: 7),
                .maximumByteCountChanged
            )
        ]

        for (live, expectedError) in cases {
            let owner = BinaryHexPolicyTestExecutor(pane: live)
            await assertAsyncPolicyError(expectedError) {
                try await owner.execute(plan)
            }
            let actual = await owner.snapshot()
            let commitCount = await owner.commitCount()
            XCTAssertEqual(actual, live)
            XCTAssertEqual(commitCount, 0)
        }
    }

    func testRejectedMatchingStateAndInvalidCommittedReceiptFailClosed() async throws {
        let source = pane([1, 2], selection: selection(0..<1), revision: 7)
        let plan = try BinaryHexEditingPolicy.plan(.edit(.delete()), in: source)

        let rejecting = BinaryHexPolicyTestExecutor(pane: source, mode: .reject)
        await assertAsyncPolicyError(.inconsistentCommitOutcome) {
            try await rejecting.execute(plan)
        }
        let rejectedSnapshot = await rejecting.snapshot()
        let rejectedCommitCount = await rejecting.commitCount()
        XCTAssertEqual(rejectedSnapshot, source)
        XCTAssertEqual(rejectedCommitCount, 0)

        let invalidReceipt = BinaryHexPolicyTestExecutor(pane: source, mode: .invalidReceipt)
        await assertAsyncPolicyError(.inconsistentReceipt) {
            try await invalidReceipt.execute(plan)
        }
        let invalidReceiptSnapshot = await invalidReceipt.snapshot()
        let invalidReceiptCommitCount = await invalidReceipt.commitCount()
        XCTAssertEqual(invalidReceiptSnapshot, source)
        XCTAssertEqual(invalidReceiptCommitCount, 0)
    }

    func testReceiptRejectsForeignFingerprintWhenEveryOtherReceiptFieldMatches() async throws {
        let source = pane([1, 2], selection: selection(1..<1), revision: 7)
        let intent = BinaryHexIntent.edit(
            .insert(payload: .bytes(Data([9])), target: .currentSelection)
        )
        let primary = try BinaryHexEditingPolicy.plan(
            intent,
            in: source,
            limits: limits(maximumWork: 10_000)
        )
        let foreign = try BinaryHexEditingPolicy.plan(
            intent,
            in: source,
            limits: limits(maximumWork: 10_001)
        )
        XCTAssertNotEqual(primary.fingerprint, foreign.fingerprint)
        XCTAssertEqual(primary.sourcePane.version, foreign.sourcePane.version)
        XCTAssertEqual(primary.mutations.count, foreign.mutations.count)
        XCTAssertEqual(primary.replacementCount, foreign.replacementCount)
        XCTAssertEqual(primary.workUnitsConsumed, foreign.workUnitsConsumed)
        XCTAssertEqual(primary.executionState, foreign.executionState)

        let owner = BinaryHexPolicyTestExecutor(
            pane: source,
            mode: .receiptFrom(foreign.transaction)
        )
        await assertAsyncPolicyError(.inconsistentReceipt) {
            try await owner.execute(primary)
        }
        let snapshot = await owner.snapshot()
        let commitCount = await owner.commitCount()
        XCTAssertEqual(snapshot, source)
        XCTAssertEqual(commitCount, 0)
    }

    func testReceiptRejectsEachCommittedPaneFieldCorruptionIndependently() async throws {
        let source = pane([1, 2], selection: selection(1..<1), revision: 7)
        let plan = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .bytes(Data([9])), target: .currentSelection)),
            in: source
        )

        for corruption in BinaryHexReceiptCorruption.allCases {
            let owner = BinaryHexPolicyTestExecutor(
                pane: source,
                mode: .corruptReceipt(corruption)
            )
            await assertAsyncPolicyError(.inconsistentReceipt) {
                try await owner.execute(plan)
            }
            let snapshot = await owner.snapshot()
            let commitCount = await owner.commitCount()
            XCTAssertEqual(snapshot, source, "Corruption: \(corruption)")
            XCTAssertEqual(commitCount, 0, "Corruption: \(corruption)")
        }
    }

    func testConcurrentPlansFromOneRevisionAllowExactlyOneCASCommit() async throws {
        let source = pane([1, 2], selection: selection(0..<2), revision: 40)
        let firstPlan = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .bytes(Data([3])), target: .currentSelection)),
            in: source
        )
        let secondPlan = try BinaryHexEditingPolicy.plan(
            .edit(.insert(payload: .bytes(Data([4])), target: .currentSelection)),
            in: source
        )
        let owner = BinaryHexPolicyTestExecutor(pane: source)

        async let first = executionAttempt(firstPlan, on: owner)
        async let second = executionAttempt(secondPlan, on: owner)
        let attempts = await [first, second]

        XCTAssertEqual(attempts.filter { $0.receipt != nil }.count, 1)
        XCTAssertEqual(
            attempts.filter { $0.error == .revisionChanged(expected: 40, actual: 41) }.count,
            1
        )
        let commitCount = await owner.commitCount()
        XCTAssertEqual(commitCount, 1)
        let committed = await owner.snapshot()
        XCTAssertEqual(committed.version.revision, 41)
        XCTAssertTrue([Data([3]), Data([4])].contains(committed.data))
    }

    func testPreCancelledPlanningStatusAndExecutionReturnTypedCancellation() async throws {
        let source = pane([1], selection: selection(0..<0), isReadOnly: true)
        await assertPreCancelled {
            try BinaryHexEditingPolicy.plan(
                .edit(.delete()),
                in: source
            )
        }
        await assertPreCancelled {
            try BinaryHexEditingPolicy.status(for: source)
        }

        let editable = pane([1], selection: selection(0..<1))
        let plan = try BinaryHexEditingPolicy.plan(.edit(.delete()), in: editable)
        let owner = BinaryHexPolicyTestExecutor(pane: editable)
        await assertPreCancelled {
            try await owner.execute(plan)
        }
        let compareCount = await owner.compareCount()
        let commitCount = await owner.commitCount()
        XCTAssertEqual(compareCount, 0)
        XCTAssertEqual(commitCount, 0)
    }

    func testCancellationInsideCASCannotInvalidateCommitButInterruptsRejectedComparison() async throws {
        let source = pane([1, 2], selection: selection(0..<1), revision: 6)
        let plan = try BinaryHexEditingPolicy.plan(.edit(.delete()), in: source)
        let committing = BinaryHexPolicyTestExecutor(
            pane: source,
            mode: .normal,
            cancelInsideCAS: true
        )
        let commitTask = Task { try await committing.execute(plan) }
        let receipt = try await commitTask.value
        XCTAssertTrue(commitTask.isCancelled)
        XCTAssertEqual(receipt.committedPane.data, Data([2]))
        XCTAssertEqual(receipt.committedPane.version.revision, 7)
        let committedCount = await committing.commitCount()
        XCTAssertEqual(committedCount, 1)

        let rejectionData = Data(repeating: 1, count: 4_096)
        let rejectionSource = pane(
            rejectionData,
            persistedData: rejectionData,
            selection: selection(0..<1),
            maximumByteCount: rejectionData.count
        )
        let rejectionPlan = try BinaryHexEditingPolicy.plan(
            .edit(.delete()),
            in: rejectionSource
        )
        let rejecting = BinaryHexPolicyTestExecutor(
            pane: rejectionSource,
            mode: .reject,
            cancelInsideCAS: true
        )
        let rejectTask = Task { try await rejecting.execute(rejectionPlan) }
        do {
            _ = try await rejectTask.value
            XCTFail("Cancelled rejected execution unexpectedly succeeded")
        } catch let error as BinaryHexPolicyError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let rejectedCount = await rejecting.commitCount()
        let rejectedSnapshot = await rejecting.snapshot()
        XCTAssertEqual(rejectedCount, 0)
        XCTAssertEqual(rejectedSnapshot, rejectionSource)
    }

    func testCASComparisonCancellationChecksExactlyAtConfiguredWorkInterval() async throws {
        let source = pane([0, 0, 0, 0], selection: selection(0..<0), revision: 9)
        let plan = try BinaryHexEditingPolicy.plan(
            .selection(.selectAll(surface: .bytes)),
            in: source,
            limits: limits(cancellationCheckInterval: 4)
        )
        let beforeCheckpoint = pane(
            [0, 0, 1, 0],
            persisted: [0, 0, 0, 0],
            selection: source.selection,
            isDirty: true,
            revision: 9
        )
        let atCheckpoint = pane(
            [0, 0, 0, 1],
            persisted: [0, 0, 0, 0],
            selection: source.selection,
            isDirty: true,
            revision: 9
        )

        let earlyBarrier = BinaryHexCancellationBarrier()
        let earlyOwner = BinaryHexPolicyTestExecutor(
            pane: beforeCheckpoint,
            mode: .rejectAtBarrier(earlyBarrier)
        )
        let earlyTask = Task.detached { try await earlyOwner.execute(plan) }
        earlyBarrier.waitUntilEntered()
        earlyTask.cancel()
        earlyBarrier.release()
        await assertAsyncPolicyError(.contentChanged) { try await earlyTask.value }
        XCTAssertTrue(earlyTask.isCancelled)

        let boundaryBarrier = BinaryHexCancellationBarrier()
        let boundaryOwner = BinaryHexPolicyTestExecutor(
            pane: atCheckpoint,
            mode: .rejectAtBarrier(boundaryBarrier)
        )
        let boundaryTask = Task.detached { try await boundaryOwner.execute(plan) }
        boundaryBarrier.waitUntilEntered()
        boundaryTask.cancel()
        boundaryBarrier.release()
        await assertAsyncPolicyError(.cancelled) { try await boundaryTask.value }
        XCTAssertTrue(boundaryTask.isCancelled)

        let earlyCommitCount = await earlyOwner.commitCount()
        let boundaryCommitCount = await boundaryOwner.commitCount()
        XCTAssertEqual(earlyCommitCount, 0)
        XCTAssertEqual(boundaryCommitCount, 0)
    }

    func testErrorsRemainTypedLocalizedAndPublicValuesRemainSendable() {
        let operation: () throws(BinaryHexPolicyError) -> BinaryHexPaneStatus = {
            try BinaryHexEditingPolicy.status(
                for: self.pane([1], selection: self.selection(0..<2))
            )
        }
        do {
            _ = try operation()
            XCTFail("Invalid selection unexpectedly succeeded")
        } catch let error {
            XCTAssertEqual(error, .invalidSelection(range: 0..<2, byteCount: 1))
            XCTAssertEqual(
                error.errorDescription,
                "Byte selection 0..<2 is outside the 1-byte pane."
            )
        }

        XCTAssertEqual(
            BinaryHexPolicyError.characterNotRepresentable(
                characterSet: .ascii,
                scalar: 0x1F600
            ).errorDescription,
            "Unicode scalar U+1F600 is not representable in ascii."
        )
        XCTAssertEqual(
            BinaryHexPolicyError.revisionChanged(expected: 1, actual: 2).errorDescription,
            "Binary hex plan was created for revision 1, not revision 2."
        )
        requireSendable(BinaryHexPolicyLimits.default)
        requireSendable(BinaryHexIntent.selection(.selectAll(surface: .bytes)))
        requireSendable(BinaryHexPolicyError.cancelled)
    }

    private func pane(
        _ bytes: [UInt8],
        persisted: [UInt8]? = nil,
        selection: BinaryHexSelection,
        displaySettings: BinaryHexDisplaySettings = .default,
        isReadOnly: Bool = false,
        isDirty: Bool? = nil,
        maximumByteCount: Int = 1_000_000,
        pane: BinaryHexPane = .left,
        identity: BinaryHexContentIdentity? = nil,
        revision: UInt64 = 1
    ) -> BinaryHexPaneSnapshot {
        self.pane(
            Data(bytes),
            persistedData: Data(persisted ?? bytes),
            selection: selection,
            displaySettings: displaySettings,
            isReadOnly: isReadOnly,
            isDirty: isDirty,
            maximumByteCount: maximumByteCount,
            pane: pane,
            identity: identity,
            revision: revision
        )
    }

    private func pane(
        _ data: Data,
        persistedData: Data,
        selection: BinaryHexSelection,
        displaySettings: BinaryHexDisplaySettings = .default,
        isReadOnly: Bool = false,
        isDirty: Bool? = nil,
        maximumByteCount: Int = 1_000_000,
        pane: BinaryHexPane = .left,
        identity: BinaryHexContentIdentity? = nil,
        revision: UInt64 = 1
    ) -> BinaryHexPaneSnapshot {
        BinaryHexPaneSnapshot(
            pane: pane,
            version: BinaryHexContentVersion(
                identity: identity ?? self.identity,
                revision: revision
            ),
            data: data,
            persistedData: persistedData,
            maximumByteCount: maximumByteCount,
            selection: selection,
            displaySettings: displaySettings,
            isReadOnly: isReadOnly,
            isDirty: isDirty ?? (data != persistedData)
        )
    }

    private func selection(
        _ range: Range<Int>,
        surface: BinaryHexSelectionSurface = .bytes
    ) -> BinaryHexSelection {
        BinaryHexSelection(byteRange: range, surface: surface)
    }

    private func display(
        bytesPerRow: Int = 16,
        byteGroupSize: Int = 1,
        characterSet: BinaryHexCharacterSet = .ascii,
        offsetRadix: BinaryHexOffsetRadix = .hexadecimal,
        usesUppercaseHex: Bool = true,
        showsOffsetColumn: Bool = true,
        showsCharacterColumn: Bool = true,
        editMode: BinaryHexEditMode = .overwrite
    ) -> BinaryHexDisplaySettings {
        BinaryHexDisplaySettings(
            bytesPerRow: bytesPerRow,
            byteGroupSize: byteGroupSize,
            characterSet: characterSet,
            offsetRadix: offsetRadix,
            usesUppercaseHex: usesUppercaseHex,
            showsOffsetColumn: showsOffsetColumn,
            showsCharacterColumn: showsCharacterColumn,
            editMode: editMode
        )
    }

    private func limits(
        maximumInputBytes: Int = 100_000,
        maximumPersistedBytes: Int = 100_000,
        maximumPayloadBytes: Int = 100_000,
        maximumCharacterInputUTF8Bytes: Int = 100_000,
        maximumPatternBytes: Int = 100_000,
        maximumOutputBytes: Int = 100_000,
        maximumReplacements: Int = 100_000,
        maximumPlanBytes: Int = 1_000_000,
        maximumWork: Int = 10_000_000,
        cancellationCheckInterval: Int = 64
    ) -> BinaryHexPolicyLimits {
        BinaryHexPolicyLimits(
            maximumInputBytes: maximumInputBytes,
            maximumPersistedBytes: maximumPersistedBytes,
            maximumPayloadBytes: maximumPayloadBytes,
            maximumCharacterInputUTF8Bytes: maximumCharacterInputUTF8Bytes,
            maximumPatternBytes: maximumPatternBytes,
            maximumOutputBytes: maximumOutputBytes,
            maximumReplacements: maximumReplacements,
            maximumPlanBytes: maximumPlanBytes,
            maximumWork: maximumWork,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func assertPolicyError<T>(
        _ expected: BinaryHexPolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? BinaryHexPolicyError, expected, file: file, line: line)
        }
    }

    private func assertAsyncPolicyError<T>(
        _ expected: BinaryHexPolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as BinaryHexPolicyError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertPreCancelled<T: Sendable>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping @Sendable () async throws -> T
    ) async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await operation()
        }
        do {
            _ = try await task.value
            XCTFail("Pre-cancelled operation unexpectedly succeeded", file: file, line: line)
        } catch let error as BinaryHexPolicyError {
            XCTAssertEqual(error, .cancelled, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }
}

private enum BinaryHexReceiptCorruption: CaseIterable, Equatable, Sendable {
    case pane
    case identity
    case revision
    case data
    case persistedData
    case maximumByteCount
    case selection
    case displaySettings
    case readOnly
    case dirty
}

private enum BinaryHexPolicyTestExecutorMode: Sendable {
    case normal
    case reject
    case rejectAtBarrier(BinaryHexCancellationBarrier)
    case invalidReceipt
    case receiptFrom(BinaryHexExecutionTransaction)
    case corruptReceipt(BinaryHexReceiptCorruption)
}

private final class BinaryHexCancellationBarrier: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func block() {
        entered.signal()
        released.wait()
    }

    func waitUntilEntered() {
        entered.wait()
    }

    func release() {
        released.signal()
    }
}

private actor BinaryHexPolicyTestExecutor: BinaryHexPlanExecutor {
    private var pane: BinaryHexPaneSnapshot
    private let mode: BinaryHexPolicyTestExecutorMode
    private let cancelInsideCAS: Bool
    private var comparisons = 0
    private var commits = 0

    init(
        pane: BinaryHexPaneSnapshot,
        mode: BinaryHexPolicyTestExecutorMode = .normal,
        cancelInsideCAS: Bool = false
    ) {
        self.pane = pane
        self.mode = mode
        self.cancelInsideCAS = cancelInsideCAS
    }

    func execute(
        _ plan: BinaryHexEditingPlan
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try plan.execute(on: self)
    }

    func compareAndExecute(
        _ transaction: BinaryHexExecutionTransaction
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionOutcome {
        comparisons += 1
        guard pane == transaction.expectedPane else {
            if case .rejectAtBarrier(let barrier) = mode { barrier.block() }
            if cancelInsideCAS { withUnsafeCurrentTask { $0?.cancel() } }
            return .notCommitted(currentPane: pane)
        }

        if case .reject = mode {
            if cancelInsideCAS { withUnsafeCurrentTask { $0?.cancel() } }
            return .notCommitted(currentPane: pane)
        }
        if case .rejectAtBarrier(let barrier) = mode {
            barrier.block()
            return .notCommitted(currentPane: pane)
        }

        let committedPane = try projectedPane(for: transaction)
        switch mode {
        case .invalidReceipt:
            return .committed(
                BinaryHexExecutionReceipt(transaction: transaction, committedPane: pane)
            )
        case .receiptFrom(let foreignTransaction):
            return .committed(
                BinaryHexExecutionReceipt(
                    transaction: foreignTransaction,
                    committedPane: committedPane
                )
            )
        case .corruptReceipt(let corruption):
            return .committed(
                BinaryHexExecutionReceipt(
                    transaction: transaction,
                    committedPane: corrupt(committedPane, field: corruption)
                )
            )
        case .normal, .reject, .rejectAtBarrier:
            break
        }

        pane = committedPane
        commits += 1
        let receipt = BinaryHexExecutionReceipt(
            transaction: transaction,
            committedPane: pane
        )
        if cancelInsideCAS { withUnsafeCurrentTask { $0?.cancel() } }
        return .committed(receipt)
    }

    private func projectedPane(
        for transaction: BinaryHexExecutionTransaction
    ) throws(BinaryHexPolicyError) -> BinaryHexPaneSnapshot {
        let revision: UInt64
        if transaction.requiresNewRevision {
            let (successor, overflow) = pane.version.revision.addingReportingOverflow(1)
            guard !overflow else { throw .inconsistentPlan }
            revision = successor
        } else {
            revision = pane.version.revision
        }
        let state = transaction.executionState
        return BinaryHexPaneSnapshot(
            pane: pane.pane,
            version: BinaryHexContentVersion(
                identity: pane.version.identity,
                revision: revision
            ),
            data: state.data,
            persistedData: state.persistedData,
            maximumByteCount: state.maximumByteCount,
            selection: state.selection,
            displaySettings: state.displaySettings,
            isReadOnly: state.isReadOnly,
            isDirty: state.isDirty
        )
    }

    private func corrupt(
        _ snapshot: BinaryHexPaneSnapshot,
        field: BinaryHexReceiptCorruption
    ) -> BinaryHexPaneSnapshot {
        let differentIdentity = BinaryHexContentIdentity(
            rawValue: UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!
        )
        return BinaryHexPaneSnapshot(
            pane: field == .pane ? (snapshot.pane == .left ? .right : .left) : snapshot.pane,
            version: BinaryHexContentVersion(
                identity: field == .identity ? differentIdentity : snapshot.version.identity,
                revision: field == .revision
                    ? snapshot.version.revision &- 1
                    : snapshot.version.revision
            ),
            data: field == .data ? snapshot.data + Data([0xFF]) : snapshot.data,
            persistedData: field == .persistedData
                ? snapshot.persistedData + Data([0xFF])
                : snapshot.persistedData,
            maximumByteCount: field == .maximumByteCount
                ? snapshot.maximumByteCount + 1
                : snapshot.maximumByteCount,
            selection: field == .selection
                ? BinaryHexSelection(byteOffset: 0)
                : snapshot.selection,
            displaySettings: field == .displaySettings
                ? BinaryHexDisplaySettings(bytesPerRow: 8)
                : snapshot.displaySettings,
            isReadOnly: field == .readOnly ? !snapshot.isReadOnly : snapshot.isReadOnly,
            isDirty: field == .dirty ? !snapshot.isDirty : snapshot.isDirty
        )
    }

    func snapshot() -> BinaryHexPaneSnapshot { pane }

    func compareCount() -> Int { comparisons }

    func commitCount() -> Int { commits }

}

private struct BinaryHexExecutionAttempt: Sendable {
    let receipt: BinaryHexExecutionReceipt?
    let error: BinaryHexPolicyError?
}

private func executionAttempt(
    _ plan: BinaryHexEditingPlan,
    on executor: BinaryHexPolicyTestExecutor
) async -> BinaryHexExecutionAttempt {
    do {
        return BinaryHexExecutionAttempt(
            receipt: try await executor.execute(plan),
            error: nil
        )
    } catch let error {
        return BinaryHexExecutionAttempt(receipt: nil, error: error)
    }
}
