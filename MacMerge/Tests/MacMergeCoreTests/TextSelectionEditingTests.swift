import Foundation
import XCTest

@testable import MacMergeCore

@MainActor
final class TextSelectionEditingTests: XCTestCase {
    private let documentID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

    func testCutPlanAndCommittedReceiptContainExactAtomicEffects() async throws {
        let document = snapshot(
            "A\u{1F600}B",
            revision: 7,
            selection: NSRange(location: 1, length: 2)
        )
        let owner = TextSelectionEditingTestOwner(
            document: document,
            transferText: "previous"
        )

        let plan = try TextSelectionEditingPlanner.cut(in: document)
        let receipt = try await owner.commit(plan)
        let state = await owner.state()
        let transaction = try XCTUnwrap(state.lastCommittedTransaction)

        XCTAssertEqual(plan.action, .cut)
        XCTAssertNil(plan.pastePayload)
        XCTAssertEqual(plan.sourceDocumentID, documentID)
        XCTAssertEqual(plan.sourceRevision, 7)
        XCTAssertEqual(plan.sourceUTF16Length, 4)
        XCTAssertEqual(plan.changedSourceRange, NSRange(location: 1, length: 2))
        XCTAssertEqual(plan.changedRange, NSRange(location: 1, length: 0))
        XCTAssertTrue(plan.didChangeText)
        XCTAssertTrue(plan.didChangeSelection)
        XCTAssertFalse(plan.isNoOp)
        XCTAssertTrue(plan.hasEffect)
        XCTAssertGreaterThan(plan.workUnitsConsumed, 0)

        XCTAssertEqual(transaction.action, .cut)
        XCTAssertEqual(transaction.expectedDocument, document)
        XCTAssertEqual(transaction.text, "AB")
        XCTAssertEqual(transaction.selectionRange, NSRange(location: 1, length: 0))
        XCTAssertEqual(transaction.copiedText, "\u{1F600}")
        XCTAssertEqual(transaction.changedSourceRange, plan.changedSourceRange)
        XCTAssertEqual(transaction.changedRange, plan.changedRange)
        XCTAssertEqual(transaction.workUnitsConsumed, plan.workUnitsConsumed)
        XCTAssertTrue(transaction.didChangeText)
        XCTAssertTrue(transaction.didChangeSelection)
        XCTAssertFalse(transaction.isNoOp)
        XCTAssertTrue(transaction.hasEffect)

        XCTAssertEqual(receipt.action, .cut)
        XCTAssertEqual(receipt.documentID, documentID)
        XCTAssertEqual(receipt.sourceRevision, 7)
        XCTAssertEqual(receipt.sourceSelectionRange, document.selectionRange)
        XCTAssertEqual(receipt.text, transaction.text)
        XCTAssertEqual(receipt.selectionRange, transaction.selectionRange)
        XCTAssertEqual(receipt.copiedText, transaction.copiedText)
        XCTAssertEqual(receipt.changedSourceRange, transaction.changedSourceRange)
        XCTAssertEqual(receipt.changedRange, transaction.changedRange)
        XCTAssertEqual(receipt.workUnitsConsumed, transaction.workUnitsConsumed)
        XCTAssertTrue(receipt.didChangeText)
        XCTAssertTrue(receipt.didChangeSelection)
        XCTAssertFalse(receipt.isNoOp)
        XCTAssertTrue(receipt.hasEffect)

        XCTAssertEqual(state.document.documentID, documentID)
        XCTAssertEqual(state.document.revision, 8)
        XCTAssertEqual(state.document.text, "AB")
        XCTAssertEqual(state.document.selectionRange, NSRange(location: 1, length: 0))
        XCTAssertTrue(state.document.isEditable)
        XCTAssertEqual(state.transferText, "\u{1F600}")
        XCTAssertEqual(state.compareCount, 1)
        XCTAssertEqual(state.commitCount, 1)
    }

    func testCopyWorksReadOnlyAndPublishesExactSelectedPayloadOnly() async throws {
        let decomposed = "e\u{301}"
        let text = "left\r\n" + decomposed + "\r\nright"
        let document = snapshot(
            text,
            revision: 11,
            selection: NSRange(location: 6, length: 2),
            isEditable: false
        )
        let owner = TextSelectionEditingTestOwner(
            document: document,
            transferText: "old"
        )

        let plan = try TextSelectionEditingPlanner.copy(in: document)
        let receipt = try await owner.commit(plan)
        let state = await owner.state()

        XCTAssertEqual(receipt.action, .copy)
        XCTAssertEqual(scalarValues(receipt.text), scalarValues(text))
        XCTAssertEqual(receipt.selectionRange, document.selectionRange)
        XCTAssertEqual(scalarValues(try XCTUnwrap(receipt.copiedText)), scalarValues(decomposed))
        XCTAssertNil(receipt.changedSourceRange)
        XCTAssertNil(receipt.changedRange)
        XCTAssertFalse(receipt.didChangeText)
        XCTAssertFalse(receipt.didChangeSelection)
        XCTAssertFalse(receipt.isNoOp)
        XCTAssertTrue(receipt.hasEffect)
        XCTAssertEqual(state.document, document)
        XCTAssertEqual(scalarValues(try XCTUnwrap(state.transferText)), scalarValues(decomposed))
    }

    func testPasteReplacesSelectionPreservesPayloadScalarsAndLeavesTransferUntouched() async throws {
        let payloadText = "x\r\ny\u{301}\u{1F600}"
        let document = snapshot(
            "before OLD after",
            revision: 4,
            selection: NSRange(location: 7, length: 3)
        )
        let payload = TextSelectionEditingPastePayload(text: payloadText)
        let owner = TextSelectionEditingTestOwner(
            document: document,
            transferText: "clipboard"
        )

        let plan = try TextSelectionEditingPlanner.paste(in: document, payload: payload)
        let receipt = try await owner.commit(plan)
        let state = await owner.state()
        let expectedText = "before " + payloadText + " after"

        XCTAssertEqual(plan.action, .paste)
        XCTAssertEqual(plan.pastePayload, payload)
        XCTAssertEqual(plan.changedSourceRange, NSRange(location: 7, length: 3))
        XCTAssertEqual(
            plan.changedRange,
            NSRange(location: 7, length: payloadText.utf16.count)
        )
        XCTAssertEqual(scalarValues(receipt.text), scalarValues(expectedText))
        XCTAssertEqual(
            receipt.selectionRange,
            NSRange(location: 7 + payloadText.utf16.count, length: 0)
        )
        XCTAssertNil(receipt.copiedText)
        XCTAssertEqual(state.document.revision, 5)
        XCTAssertEqual(scalarValues(state.document.text), scalarValues(expectedText))
        XCTAssertEqual(state.transferText, "clipboard")
    }

    func testScalarIdenticalPasteChangesOnlySelectionAndDoesNotAdvanceRevision() async throws {
        let document = snapshot(
            "abc",
            revision: 20,
            selection: NSRange(location: 1, length: 1)
        )
        let owner = TextSelectionEditingTestOwner(document: document)

        let plan = try TextSelectionEditingPlanner.paste(in: document, text: "b")
        let receipt = try await owner.commit(plan)
        let state = await owner.state()

        XCTAssertFalse(plan.didChangeText)
        XCTAssertTrue(plan.didChangeSelection)
        XCTAssertTrue(plan.hasEffect)
        XCTAssertNil(plan.noOpReason)
        XCTAssertEqual(receipt.text, "abc")
        XCTAssertEqual(receipt.selectionRange, NSRange(location: 2, length: 0))
        XCTAssertNil(receipt.changedSourceRange)
        XCTAssertNil(receipt.changedRange)
        XCTAssertEqual(state.document.revision, 20)
        XCTAssertEqual(state.commitCount, 1)
    }

    func testCanonicallyEquivalentPasteStillChangesScalarRepresentation() async throws {
        let decomposed = "e\u{301}"
        let composed = "\u{E9}"
        let document = snapshot(
            decomposed,
            revision: 3,
            selection: NSRange(location: 0, length: 2)
        )
        let owner = TextSelectionEditingTestOwner(document: document)

        let plan = try TextSelectionEditingPlanner.paste(in: document, text: composed)
        let receipt = try await owner.commit(plan)
        let state = await owner.state()

        XCTAssertEqual(decomposed, composed)
        XCTAssertTrue(plan.didChangeText)
        XCTAssertEqual(plan.changedSourceRange, NSRange(location: 0, length: 2))
        XCTAssertEqual(plan.changedRange, NSRange(location: 0, length: 1))
        XCTAssertEqual(scalarValues(receipt.text), scalarValues(composed))
        XCTAssertNotEqual(scalarValues(receipt.text), scalarValues(decomposed))
        XCTAssertEqual(receipt.selectionRange, NSRange(location: 1, length: 0))
        XCTAssertEqual(state.document.revision, 4)
    }

    func testSelectAllWorksReadOnlyAndReportsBothNoOpReasons() async throws {
        let document = snapshot(
            "A\u{1F600}e\u{301}",
            revision: 8,
            selection: NSRange(location: 1, length: 0),
            isEditable: false
        )
        let owner = TextSelectionEditingTestOwner(document: document)

        let receipt = try await owner.commit(
            TextSelectionEditingPlanner.selectAll(in: document)
        )
        let selectedState = await owner.state()

        XCTAssertEqual(receipt.selectionRange, NSRange(location: 0, length: 5))
        XCTAssertFalse(receipt.didChangeText)
        XCTAssertTrue(receipt.didChangeSelection)
        XCTAssertNil(receipt.noOpReason)
        XCTAssertNil(receipt.copiedText)
        XCTAssertEqual(selectedState.document.revision, 8)
        XCTAssertEqual(selectedState.document.selectionRange, receipt.selectionRange)

        let fullSelection = snapshot(
            document.text,
            selection: NSRange(location: 0, length: 5),
            isEditable: false
        )
        let fullPlan = try TextSelectionEditingPlanner.selectAll(in: fullSelection)
        XCTAssertEqual(fullPlan.noOpReason, .selectionAlreadyCoversDocument)
        XCTAssertTrue(fullPlan.isNoOp)
        XCTAssertFalse(fullPlan.hasEffect)

        let empty = snapshot(
            "",
            selection: NSRange(location: 0, length: 0),
            isEditable: false
        )
        let emptyPlan = try TextSelectionEditingPlanner.selectAll(in: empty)
        XCTAssertEqual(emptyPlan.noOpReason, .emptyDocument)
        XCTAssertTrue(emptyPlan.isNoOp)
        XCTAssertFalse(emptyPlan.hasEffect)
    }

    func testEmptyCutCopyAndPasteNoOpsDoNotOverwriteTransferState() async throws {
        for action in [
            TextSelectionEditingAction.cut,
            .copy,
            .paste
        ] {
            let document = snapshot("abc", selection: NSRange(location: 1, length: 0))
            let owner = TextSelectionEditingTestOwner(
                document: document,
                transferText: "retained"
            )
            let plan: TextSelectionEditingPlan
            switch action {
            case .cut:
                plan = try TextSelectionEditingPlanner.cut(in: document)
            case .copy:
                plan = try TextSelectionEditingPlanner.copy(in: document)
            case .paste:
                plan = try TextSelectionEditingPlanner.paste(in: document, text: "")
            case .selectAll:
                XCTFail("Unexpected action")
                continue
            }

            let receipt = try await owner.commit(plan)
            let state = await owner.state()

            XCTAssertEqual(
                receipt.noOpReason,
                action == .paste ? .emptyPastePayload : .emptySelection
            )
            XCTAssertTrue(receipt.isNoOp)
            XCTAssertFalse(receipt.hasEffect)
            XCTAssertEqual(state.document, document)
            XCTAssertEqual(state.transferText, "retained")
            XCTAssertEqual(state.commitCount, 1)
        }
    }

    func testEmptyPasteDeletesNonemptySelectionInsteadOfBecomingNoOp() async throws {
        let document = snapshot(
            "abc",
            revision: 2,
            selection: NSRange(location: 1, length: 1)
        )
        let owner = TextSelectionEditingTestOwner(document: document)

        let plan = try TextSelectionEditingPlanner.paste(in: document, text: "")
        let receipt = try await owner.commit(plan)
        let state = await owner.state()

        XCTAssertNil(plan.noOpReason)
        XCTAssertTrue(plan.didChangeText)
        XCTAssertEqual(receipt.text, "ac")
        XCTAssertEqual(receipt.selectionRange, NSRange(location: 1, length: 0))
        XCTAssertEqual(receipt.changedSourceRange, NSRange(location: 1, length: 1))
        XCTAssertEqual(receipt.changedRange, NSRange(location: 1, length: 0))
        XCTAssertEqual(state.document.revision, 3)
    }

    func testReadOnlyDocumentsRejectCutAndPasteBeforeTextValidation() {
        let malformedSelection = NSRange(location: Int.max - 1, length: 2)
        let document = snapshot(
            "abc",
            selection: malformedSelection,
            isEditable: false
        )

        assertEditingError(.documentNotEditable) {
            try TextSelectionEditingPlanner.cut(in: document)
        }
        assertEditingError(.documentNotEditable) {
            try TextSelectionEditingPlanner.paste(in: document, text: "x")
        }

        let validSelection = snapshot(
            "abc",
            selection: NSRange(location: 0, length: 1),
            isEditable: false
        )
        let undersizedInput = limits(maximumInputUTF16Length: 2)
        assertEditingError(.documentNotEditable) {
            try TextSelectionEditingPlanner.cut(
                in: validSelection,
                limits: undersizedInput
            )
        }
        assertEditingError(.documentNotEditable) {
            try TextSelectionEditingPlanner.paste(
                in: validSelection,
                text: "x",
                limits: undersizedInput
            )
        }
        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.copy(
                in: snapshot(
                    "abc",
                    selection: NSRange(location: 0, length: 1),
                    isEditable: false
                )
            )
        )
    }

    func testGenericPlannerEnforcesPastePayloadShape() {
        let document = snapshot("abc", selection: NSRange(location: 0, length: 1))
        let payload = TextSelectionEditingPastePayload(text: "x")

        assertEditingError(.pastePayloadRequired) {
            try TextSelectionEditingPlanner.plan(.paste, in: document)
        }
        for action in [
            TextSelectionEditingAction.cut,
            .copy,
            .selectAll
        ] {
            assertEditingError(.unexpectedPastePayload) {
                try TextSelectionEditingPlanner.plan(
                    action,
                    in: document,
                    pastePayload: payload
                )
            }
        }
    }

    func testMalformedUTF16SelectionRangesProduceExactDiagnostics() {
        let text = "A\u{1F600}B"
        let malformedRanges = [
            NSRange(location: -1, length: 0),
            NSRange(location: 0, length: -1),
            NSRange(location: NSNotFound, length: 0),
            NSRange(location: Int.max - 1, length: 2),
            NSRange(location: 5, length: 0),
            NSRange(location: 3, length: 2)
        ]

        for range in malformedRanges {
            let expected = TextSelectionEditingError.invalidSelectionRange(
                range: range,
                documentUTF16Length: 4
            )
            assertEditingError(expected) {
                try TextSelectionEditingPlanner.copy(
                    in: self.snapshot(text, selection: range)
                )
            }
            XCTAssertEqual(
                expected.errorDescription,
                "UTF-16 selection {\(range.location), \(range.length)} is outside the "
                    + "4-unit document."
            )
        }
    }

    func testCRLFSplitSelectionsRejectZeroLengthAndEitherNonemptyEndpoint() {
        let text = "\r\n"
        let splitRanges = [
            NSRange(location: 1, length: 0),
            NSRange(location: 0, length: 1),
            NSRange(location: 1, length: 1)
        ]

        for range in splitRanges {
            assertEditingError(.selectionSplitsGrapheme(range)) {
                try TextSelectionEditingPlanner.copy(
                    in: self.snapshot(text, selection: range)
                )
            }
        }
    }

    func testSurrogateCombiningZWJAndRegionalIndicatorSplitsAreRejected() {
        let combining = "e\u{301}"
        let zwj = "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"
        let flag = "\u{1F1FA}\u{1F1F8}"
        let text = combining + "|" + zwj + "|" + flag
        let splitOffsets = [1, 4, 5, 6, 7, 8, 9, 12, 13, 14]

        for offset in splitOffsets {
            let range = NSRange(location: offset, length: 0)
            let expected = TextSelectionEditingError.selectionSplitsGrapheme(range)
            assertEditingError(expected) {
                try TextSelectionEditingPlanner.copy(
                    in: self.snapshot(text, selection: range)
                )
            }
            XCTAssertEqual(
                expected.errorDescription,
                "UTF-16 selection {\(offset), 0} splits an extended grapheme cluster."
            )
        }

        let surrogateRange = NSRange(location: 1, length: 0)
        assertEditingError(.selectionSplitsGrapheme(surrogateRange)) {
            try TextSelectionEditingPlanner.copy(
                in: self.snapshot("\u{1F600}", selection: surrogateRange)
            )
        }
    }

    func testNonemptySelectionsSplittingOnlyOneGraphemeEndpointAreRejected() {
        let combining = "e\u{301}"
        let zwj = "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"
        let flag = "\u{1F1FA}\u{1F1F8}"
        let cases = [
            (combining, NSRange(location: 0, length: 1)),
            (combining, NSRange(location: 1, length: 1)),
            (zwj, NSRange(location: 0, length: 2)),
            (zwj, NSRange(location: 2, length: 5)),
            (flag, NSRange(location: 0, length: 2)),
            (flag, NSRange(location: 2, length: 2))
        ]

        for (text, range) in cases {
            assertEditingError(.selectionSplitsGrapheme(range)) {
                try TextSelectionEditingPlanner.copy(
                    in: self.snapshot(text, selection: range)
                )
            }
        }
    }

    func testCombiningZWJAndRegionalIndicatorSelectionsCopyAndCutWholeGraphemes() async throws {
        let combining = "e\u{301}"
        let zwj = "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"
        let flag = "\u{1F1FA}\u{1F1F8}"
        let text = combining + "|" + zwj + "|" + flag
        let cases = [
            (
                NSRange(location: 0, length: 2),
                combining,
                "|" + zwj + "|" + flag,
                NSRange(location: 0, length: 0)
            ),
            (
                NSRange(location: 3, length: 7),
                zwj,
                combining + "||" + flag,
                NSRange(location: 3, length: 0)
            ),
            (
                NSRange(location: 11, length: 4),
                flag,
                combining + "|" + zwj + "|",
                NSRange(location: 11, length: 0)
            )
        ]

        for (range, selectedText, resultText, resultSelection) in cases {
            let document = snapshot(text, selection: range)
            let copyOwner = TextSelectionEditingTestOwner(document: document)
            let cutOwner = TextSelectionEditingTestOwner(document: document)

            let copy = try await copyOwner.commit(
                TextSelectionEditingPlanner.copy(in: document)
            )
            let cut = try await cutOwner.commit(
                TextSelectionEditingPlanner.cut(in: document)
            )

            XCTAssertEqual(
                scalarValues(try XCTUnwrap(copy.copiedText)),
                scalarValues(selectedText)
            )
            XCTAssertEqual(
                scalarValues(try XCTUnwrap(cut.copiedText)),
                scalarValues(selectedText)
            )
            XCTAssertEqual(cut.changedSourceRange, range)
            XCTAssertEqual(cut.changedRange, NSRange(location: range.location, length: 0))
            XCTAssertEqual(scalarValues(cut.text), scalarValues(resultText))
            XCTAssertEqual(cut.selectionRange, resultSelection)
        }
    }

    func testCutAndPasteResolveInsertionPointAfterNewlyJoinedGrapheme() async throws {
        let regionalU = "\u{1F1FA}"
        let regionalS = "\u{1F1F8}"
        let cutDocument = snapshot(
            regionalU + "X" + regionalS,
            selection: NSRange(location: 2, length: 1)
        )
        let cutOwner = TextSelectionEditingTestOwner(document: cutDocument)

        let cut = try await cutOwner.commit(
            TextSelectionEditingPlanner.cut(in: cutDocument)
        )

        XCTAssertEqual(scalarValues(cut.text), scalarValues(regionalU + regionalS))
        XCTAssertEqual(cut.selectionRange, NSRange(location: 4, length: 0))

        let woman = "\u{1F469}"
        let laptop = "\u{1F4BB}"
        let pasteDocument = snapshot(
            woman + laptop,
            selection: NSRange(location: 2, length: 0)
        )
        let pasteOwner = TextSelectionEditingTestOwner(document: pasteDocument)

        let paste = try await pasteOwner.commit(
            TextSelectionEditingPlanner.paste(
                in: pasteDocument,
                text: "\u{200D}"
            )
        )

        XCTAssertEqual(
            scalarValues(paste.text),
            scalarValues(woman + "\u{200D}" + laptop)
        )
        XCTAssertEqual(paste.selectionRange, NSRange(location: 5, length: 0))
    }

    func testRegionalIndicatorCutResultAcceptsExactClusterLimitAndRejectsOneUnder() async throws {
        let regionalU = "\u{1F1FA}"
        let regionalS = "\u{1F1F8}"
        let document = snapshot(
            regionalU + "X" + regionalS,
            selection: NSRange(location: 2, length: 1)
        )
        let exactPlan = try TextSelectionEditingPlanner.cut(
            in: document,
            limits: limits(maximumGraphemeClusterUTF16Length: 4)
        )
        let owner = TextSelectionEditingTestOwner(document: document)

        let receipt = try await owner.commit(exactPlan)

        XCTAssertEqual(scalarValues(receipt.text), scalarValues(regionalU + regionalS))
        XCTAssertEqual(receipt.selectionRange, NSRange(location: 4, length: 0))
        assertEditingError(
            .graphemeSegmentationTooComplex(maximumClusterUTF16Length: 3)
        ) {
            try TextSelectionEditingPlanner.cut(
                in: document,
                limits: self.limits(maximumGraphemeClusterUTF16Length: 3)
            )
        }
    }

    func testEveryInvalidLimitIsRejectedAndMinimumLimitsAcceptEmptyCopy() throws {
        let document = snapshot("", selection: NSRange(location: 0, length: 0))
        let invalidLimits = [
            limits(maximumInputUTF16Length: -1),
            limits(maximumPasteUTF16Length: -1),
            limits(maximumOutputUTF16Length: -1),
            limits(maximumGraphemeClusterUTF16Length: 0),
            limits(maximumWork: -1)
        ]

        for invalid in invalidLimits {
            assertEditingError(.invalidLimits) {
                try TextSelectionEditingPlanner.copy(in: document, limits: invalid)
            }
        }

        let minimum = limits(
            maximumInputUTF16Length: 0,
            maximumPasteUTF16Length: 0,
            maximumOutputUTF16Length: 0,
            maximumGraphemeClusterUTF16Length: 1,
            maximumWork: 0
        )
        let plan = try TextSelectionEditingPlanner.copy(in: document, limits: minimum)
        XCTAssertEqual(plan.workUnitsConsumed, 0)
        XCTAssertEqual(plan.noOpReason, .emptySelection)
    }

    func testInputAndPastePayloadLimitsUseExactUTF16Boundaries() throws {
        let inputDocument = snapshot(
            "\u{1F600}a",
            selection: NSRange(location: 2, length: 1)
        )
        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.copy(
                in: inputDocument,
                limits: limits(maximumInputUTF16Length: 3)
            )
        )
        assertEditingError(.inputTooLarge(maximumUTF16Length: 2)) {
            try TextSelectionEditingPlanner.copy(
                in: inputDocument,
                limits: self.limits(maximumInputUTF16Length: 2)
            )
        }

        let insertionDocument = snapshot(
            "a",
            selection: NSRange(location: 1, length: 0)
        )
        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.paste(
                in: insertionDocument,
                text: "\u{1F600}b",
                limits: limits(maximumPasteUTF16Length: 3)
            )
        )
        assertEditingError(.pastePayloadTooLarge(maximumUTF16Length: 2)) {
            try TextSelectionEditingPlanner.paste(
                in: insertionDocument,
                text: "\u{1F600}b",
                limits: self.limits(maximumPasteUTF16Length: 2)
            )
        }
    }

    func testEachOperationUsesItsSeparateExactOutputBoundary() throws {
        let cutDocument = snapshot(
            "abcd",
            selection: NSRange(location: 1, length: 1)
        )
        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.cut(
                in: cutDocument,
                limits: limits(maximumOutputUTF16Length: 3)
            )
        )
        assertEditingError(.outputTooLarge(maximumUTF16Length: 2)) {
            try TextSelectionEditingPlanner.cut(
                in: cutDocument,
                limits: self.limits(maximumOutputUTF16Length: 2)
            )
        }

        let copyDocument = snapshot(
            "abcd",
            selection: NSRange(location: 1, length: 1)
        )
        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.copy(
                in: copyDocument,
                limits: limits(maximumOutputUTF16Length: 4)
            )
        )
        assertEditingError(.outputTooLarge(maximumUTF16Length: 3)) {
            try TextSelectionEditingPlanner.copy(
                in: copyDocument,
                limits: self.limits(maximumOutputUTF16Length: 3)
            )
        }

        let pasteDocument = snapshot(
            "ab",
            selection: NSRange(location: 1, length: 1)
        )
        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.paste(
                in: pasteDocument,
                text: "\u{1F600}",
                limits: limits(maximumOutputUTF16Length: 3)
            )
        )
        assertEditingError(.outputTooLarge(maximumUTF16Length: 2)) {
            try TextSelectionEditingPlanner.paste(
                in: pasteDocument,
                text: "\u{1F600}",
                limits: self.limits(maximumOutputUTF16Length: 2)
            )
        }

        let selectAllDocument = snapshot(
            "abcd",
            selection: NSRange(location: 1, length: 0),
            isEditable: false
        )
        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.selectAll(
                in: selectAllDocument,
                limits: limits(maximumOutputUTF16Length: 4)
            )
        )
        assertEditingError(.outputTooLarge(maximumUTF16Length: 3)) {
            try TextSelectionEditingPlanner.selectAll(
                in: selectAllDocument,
                limits: self.limits(maximumOutputUTF16Length: 3)
            )
        }
    }

    func testGraphemeClusterLimitChecksWholeSourceAndJoinedResultAtExactBoundary() throws {
        let zwj = "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"
        XCTAssertEqual(zwj.utf16.count, 7)
        let source = snapshot(zwj, selection: NSRange(location: 0, length: 7))

        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.copy(
                in: source,
                limits: limits(maximumGraphemeClusterUTF16Length: 7)
            )
        )
        let oversized = TextSelectionEditingError.graphemeSegmentationTooComplex(
            maximumClusterUTF16Length: 6
        )
        assertEditingError(oversized) {
            try TextSelectionEditingPlanner.copy(
                in: source,
                limits: self.limits(maximumGraphemeClusterUTF16Length: 6)
            )
        }
        XCTAssertEqual(
            oversized.errorDescription,
            "Text contains an extended grapheme cluster exceeding the 6-UTF-16-unit limit."
        )

        let woman = "\u{1F469}"
        let laptop = "\u{1F4BB}"
        let joinsAtFive = snapshot(
            woman + laptop,
            selection: NSRange(location: 2, length: 0)
        )
        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.paste(
                in: joinsAtFive,
                text: "\u{200D}",
                limits: limits(maximumGraphemeClusterUTF16Length: 5)
            )
        )
        assertEditingError(
            .graphemeSegmentationTooComplex(maximumClusterUTF16Length: 4)
        ) {
            try TextSelectionEditingPlanner.paste(
                in: joinsAtFive,
                text: "\u{200D}",
                limits: self.limits(maximumGraphemeClusterUTF16Length: 4)
            )
        }
    }

    func testGraphemeClusterLimitRejectsOversizedSourceClusterOutsideSelection() {
        let oversizedCluster = "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"
        let document = snapshot(
            oversizedCluster + "|ok",
            selection: NSRange(location: 8, length: 2)
        )

        XCTAssertNoThrow(
            try TextSelectionEditingPlanner.copy(
                in: document,
                limits: limits(maximumGraphemeClusterUTF16Length: 7)
            )
        )
        assertEditingError(
            .graphemeSegmentationTooComplex(maximumClusterUTF16Length: 6)
        ) {
            try TextSelectionEditingPlanner.copy(
                in: document,
                limits: self.limits(maximumGraphemeClusterUTF16Length: 6)
            )
        }
    }

    func testEachActionReportsIndependentWorkTotalAndEnforcesItsBoundary() throws {
        let cutDocument = snapshot("ab", selection: NSRange(location: 0, length: 1))
        try assertWorkBoundary(expectedWork: 5) { limits in
            try TextSelectionEditingPlanner.cut(in: cutDocument, limits: limits)
        }

        let copyDocument = snapshot("ab", selection: NSRange(location: 1, length: 1))
        try assertWorkBoundary(expectedWork: 2) { limits in
            try TextSelectionEditingPlanner.copy(in: copyDocument, limits: limits)
        }

        let pasteDocument = snapshot("ab", selection: NSRange(location: 1, length: 1))
        try assertWorkBoundary(expectedWork: 11) { limits in
            try TextSelectionEditingPlanner.paste(
                in: pasteDocument,
                text: "\u{1F600}",
                limits: limits
            )
        }

        try assertWorkBoundary(expectedWork: 5) { limits in
            try TextSelectionEditingPlanner.paste(
                in: snapshot("abc", selection: NSRange(location: 1, length: 1)),
                text: "b",
                limits: limits
            )
        }

        let selectAllDocument = snapshot("ab", selection: NSRange(location: 1, length: 0))
        try assertWorkBoundary(expectedWork: 2) { limits in
            try TextSelectionEditingPlanner.selectAll(
                in: selectAllDocument,
                limits: limits
            )
        }
    }

    func testOversizedLiveTextCASConflictHonorsInputAndWorkGuardsWithoutEffects() async throws {
        let expected = snapshot(
            "a",
            revision: 50,
            selection: NSRange(location: 0, length: 1)
        )
        let live = snapshot(
            "ab",
            revision: expected.revision,
            selection: expected.selectionRange
        )
        let cases = [
            (
                try TextSelectionEditingPlanner.copy(
                    in: expected,
                    limits: limits(maximumInputUTF16Length: 1)
                ),
                TextSelectionEditingError.inputTooLarge(maximumUTF16Length: 1)
            ),
            (
                try TextSelectionEditingPlanner.copy(
                    in: expected,
                    limits: limits(maximumWork: 1)
                ),
                TextSelectionEditingError.workLimitExceeded(maximumWork: 1)
            )
        ]

        for (plan, expectedError) in cases {
            let owner = TextSelectionEditingTestOwner(
                document: live,
                transferText: "untouched"
            )

            await assertAsyncEditingError(expectedError) {
                try await owner.commit(plan)
            }
            let state = await owner.state()

            XCTAssertEqual(state.document, live)
            XCTAssertEqual(state.transferText, "untouched")
            XCTAssertEqual(state.compareCount, 1)
            XCTAssertEqual(state.commitCount, 0)
            XCTAssertNil(state.lastCommittedTransaction)
        }
    }

    func testPlanningIsDeterministicAndUsesScalarExactValueEquality() throws {
        let document = snapshot(
            "a\u{1F600}b",
            revision: 9,
            selection: NSRange(location: 1, length: 2)
        )
        let first = try TextSelectionEditingPlanner.cut(in: document)
        let repeated = try TextSelectionEditingPlanner.cut(in: document)

        XCTAssertEqual(first, repeated)

        let canonicalA = snapshot(
            "\u{C5}",
            selection: NSRange(location: 0, length: 1)
        )
        let canonicalB = snapshot(
            "\u{212B}",
            selection: NSRange(location: 0, length: 1)
        )
        XCTAssertEqual(canonicalA.text, canonicalB.text)
        XCTAssertNotEqual(canonicalA, canonicalB)

        let payloadA = TextSelectionEditingPastePayload(text: "\u{C5}")
        let payloadB = TextSelectionEditingPastePayload(text: "\u{212B}")
        XCTAssertEqual(payloadA.text, payloadB.text)
        XCTAssertNotEqual(payloadA, payloadB)

        let planA = try TextSelectionEditingPlanner.paste(
            in: document,
            payload: payloadA
        )
        let planB = try TextSelectionEditingPlanner.paste(
            in: document,
            payload: payloadB
        )
        XCTAssertNotEqual(planA, planB)
    }

    func testCommitCASRejectsEveryChangedExpectedDocumentFieldWithoutAnyEffect() async throws {
        let expected = snapshot(
            "\u{C5}bc",
            revision: 30,
            selection: NSRange(location: 1, length: 1),
            isEditable: true
        )
        let plan = try TextSelectionEditingPlanner.cut(in: expected)
        let otherID = UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!
        let cases: [(TextSelectionEditingDocumentSnapshot, TextSelectionEditingError)] = [
            (
                snapshot(
                    expected.text,
                    documentID: otherID,
                    revision: expected.revision,
                    selection: expected.selectionRange
                ),
                .documentIDChanged(expected: documentID, actual: otherID)
            ),
            (
                snapshot(
                    expected.text,
                    revision: 31,
                    selection: expected.selectionRange
                ),
                .documentRevisionChanged(expected: 30, actual: 31)
            ),
            (
                snapshot(
                    "\u{212B}bc",
                    revision: expected.revision,
                    selection: expected.selectionRange
                ),
                .documentTextChanged
            ),
            (
                snapshot(
                    expected.text,
                    revision: expected.revision,
                    selection: NSRange(location: 2, length: 1)
                ),
                .documentSelectionChanged(
                    expected: expected.selectionRange,
                    actual: NSRange(location: 2, length: 1)
                )
            ),
            (
                snapshot(
                    expected.text,
                    revision: expected.revision,
                    selection: expected.selectionRange,
                    isEditable: false
                ),
                .documentEditabilityChanged(expected: true, actual: false)
            )
        ]

        for (liveDocument, expectedError) in cases {
            let owner = TextSelectionEditingTestOwner(
                document: liveDocument,
                transferText: "untouched"
            )

            await assertAsyncEditingError(expectedError) {
                try await owner.commit(plan)
            }
            let state = await owner.state()

            XCTAssertEqual(state.document, liveDocument)
            XCTAssertEqual(state.transferText, "untouched")
            XCTAssertEqual(state.compareCount, 1)
            XCTAssertEqual(state.commitCount, 0)
            XCTAssertNil(state.lastCommittedTransaction)
        }
    }

    func testRejectedCommitWithNoReportedMismatchIsInconsistentAndAtomic() async throws {
        let document = snapshot(
            "abc",
            selection: NSRange(location: 0, length: 1)
        )
        let plan = try TextSelectionEditingPlanner.cut(in: document)
        let owner = TextSelectionEditingTestOwner(
            document: document,
            transferText: "old",
            alwaysReject: true
        )

        await assertAsyncEditingError(.inconsistentCommitOutcome) {
            try await owner.commit(plan)
        }
        let state = await owner.state()

        XCTAssertEqual(state.document, document)
        XCTAssertEqual(state.transferText, "old")
        XCTAssertEqual(state.compareCount, 1)
        XCTAssertEqual(state.commitCount, 0)
    }

    func testConcurrentPlansFromSameSnapshotAllowExactlyOneAtomicCommit() async throws {
        let document = snapshot(
            "base",
            revision: 40,
            selection: NSRange(location: 0, length: 4)
        )
        let owner = TextSelectionEditingTestOwner(
            document: document,
            transferText: "stable"
        )
        let firstPlan = try TextSelectionEditingPlanner.paste(in: document, text: "first")
        let secondPlan = try TextSelectionEditingPlanner.paste(in: document, text: "second")

        async let first = commitAttempt(firstPlan, to: owner)
        async let second = commitAttempt(secondPlan, to: owner)
        let attempts = await [first, second]
        let state = await owner.state()

        XCTAssertEqual(attempts.filter(\.isSuccess).count, 1)
        XCTAssertEqual(
            attempts.filter {
                $0.error
                    == .documentRevisionChanged(expected: 40, actual: 41)
            }.count,
            1
        )
        XCTAssertEqual(state.compareCount, 2)
        XCTAssertEqual(state.commitCount, 1)
        XCTAssertEqual(state.document.revision, 41)
        XCTAssertTrue(["first", "second"].contains(state.document.text))
        XCTAssertEqual(state.document.selectionRange.location, state.document.text.utf16.count)
        XCTAssertEqual(state.document.selectionRange.length, 0)
        XCTAssertEqual(state.transferText, "stable")
    }

    func testCommittedTransactionAndReceiptRemainImmutableAfterOwnerChanges() async throws {
        let document = snapshot(
            "abc",
            revision: 5,
            selection: NSRange(location: 1, length: 1)
        )
        let owner = TextSelectionEditingTestOwner(document: document)
        let plan = try TextSelectionEditingPlanner.paste(in: document, text: "XYZ")

        let receipt = try await owner.commit(plan)
        let committedState = await owner.state()
        let transaction = try XCTUnwrap(committedState.lastCommittedTransaction)
        let replacement = snapshot(
            "external",
            revision: 99,
            selection: NSRange(location: 0, length: 0),
            isEditable: false
        )
        await owner.replaceOwnedState(document: replacement, transferText: "changed")
        let detachedTransaction = await Task.detached { transaction }.value
        let typedReceipt: TextSelectionEditingResult = receipt

        XCTAssertEqual(detachedTransaction, transaction)
        XCTAssertEqual(transaction.expectedDocument, document)
        XCTAssertEqual(transaction.text, "aXYZc")
        XCTAssertEqual(transaction.selectionRange, NSRange(location: 4, length: 0))
        XCTAssertEqual(typedReceipt.text, "aXYZc")
        XCTAssertEqual(typedReceipt.selectionRange, transaction.selectionRange)
        XCTAssertEqual(typedReceipt.sourceRevision, 5)
        XCTAssertEqual(typedReceipt.sourceSelectionRange, document.selectionRange)
        XCTAssertEqual(
            scalarValues(typedReceipt.text),
            scalarValues(detachedTransaction.text)
        )
    }

    func testStaleNoOpPlanStillRequiresExactCAS() async throws {
        let document = snapshot("abc", revision: 1, selection: NSRange(location: 1, length: 0))
        let plan = try TextSelectionEditingPlanner.copy(in: document)
        let stale = snapshot("abc", revision: 2, selection: document.selectionRange)
        let owner = TextSelectionEditingTestOwner(
            document: stale,
            transferText: "retained"
        )

        await assertAsyncEditingError(
            .documentRevisionChanged(expected: 1, actual: 2)
        ) {
            try await owner.commit(plan)
        }
        let state = await owner.state()

        XCTAssertEqual(state.document, stale)
        XCTAssertEqual(state.transferText, "retained")
        XCTAssertEqual(state.commitCount, 0)
    }

    func testPreCancelledEntryStopsBeforePlanningValidationOrCommitCAS() async throws {
        let document = snapshot(
            "abc",
            selection: NSRange(location: 0, length: 1),
            isEditable: false
        )
        let invalidLimits = limits(maximumInputUTF16Length: -1)

        await assertPreCancelled {
            try TextSelectionEditingPlanner.plan(
                .paste,
                in: document,
                limits: invalidLimits
            )
        }

        let editable = snapshot("abc", selection: NSRange(location: 0, length: 1))
        let plan = try TextSelectionEditingPlanner.cut(in: editable)
        let owner = TextSelectionEditingTestOwner(
            document: editable,
            transferText: "unchanged"
        )

        await assertPreCancelled {
            try await owner.commit(plan)
        }
        let state = await owner.state()

        XCTAssertEqual(state.compareCount, 0)
        XCTAssertEqual(state.commitCount, 0)
        XCTAssertEqual(state.document, editable)
        XCTAssertEqual(state.transferText, "unchanged")
    }

    func testCancellationRaisedInsideSuccessfulCASCannotTurnCommitIntoFailure() async throws {
        let document = snapshot(
            "abc",
            revision: 6,
            selection: NSRange(location: 0, length: 1)
        )
        let plan = try TextSelectionEditingPlanner.cut(in: document)
        let owner = TextSelectionEditingTestOwner(
            document: document,
            cancelInsideCAS: true
        )

        let task = Task {
            try await owner.commit(plan)
        }
        let receipt = try await task.value
        let state = await owner.state()

        XCTAssertTrue(task.isCancelled)
        XCTAssertEqual(receipt.text, "bc")
        XCTAssertEqual(receipt.copiedText, "a")
        XCTAssertEqual(state.document.text, "bc")
        XCTAssertEqual(state.document.revision, 7)
        XCTAssertEqual(state.transferText, "a")
        XCTAssertEqual(state.commitCount, 1)
    }

    func testCancellationRaisedInsideRejectedCASPrecedesInconsistentOutcome() async throws {
        let document = snapshot(
            "abc",
            selection: NSRange(location: 0, length: 1)
        )
        let plan = try TextSelectionEditingPlanner.copy(in: document)
        let owner = TextSelectionEditingTestOwner(
            document: document,
            alwaysReject: true,
            cancelInsideCAS: true
        )

        let task = Task {
            try await owner.commit(plan)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled rejected commit unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let state = await owner.state()
        XCTAssertEqual(state.document, document)
        XCTAssertNil(state.transferText)
        XCTAssertEqual(state.compareCount, 1)
        XCTAssertEqual(state.commitCount, 0)
    }

    private func snapshot(
        _ text: String,
        documentID: UUID? = nil,
        revision: UInt64 = 1,
        selection: NSRange,
        isEditable: Bool = true
    ) -> TextSelectionEditingDocumentSnapshot {
        TextSelectionEditingDocumentSnapshot(
            documentID: documentID ?? self.documentID,
            revision: revision,
            text: text,
            selectionRange: selection,
            isEditable: isEditable
        )
    }

    private func limits(
        maximumInputUTF16Length: Int = 1_000,
        maximumPasteUTF16Length: Int = 1_000,
        maximumOutputUTF16Length: Int = 1_000,
        maximumGraphemeClusterUTF16Length: Int = 100,
        maximumWork: Int = 10_000
    ) -> TextSelectionEditingLimits {
        TextSelectionEditingLimits(
            maximumInputUTF16Length: maximumInputUTF16Length,
            maximumPasteUTF16Length: maximumPasteUTF16Length,
            maximumOutputUTF16Length: maximumOutputUTF16Length,
            maximumGraphemeClusterUTF16Length: maximumGraphemeClusterUTF16Length,
            maximumWork: maximumWork
        )
    }

    private func assertWorkBoundary(
        expectedWork: Int,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: (TextSelectionEditingLimits) throws -> TextSelectionEditingPlan
    ) throws {
        let baseline = try operation(limits())
        XCTAssertEqual(baseline.workUnitsConsumed, expectedWork, file: file, line: line)
        XCTAssertGreaterThan(expectedWork, 0, file: file, line: line)

        let exact = try operation(limits(maximumWork: expectedWork))
        XCTAssertEqual(exact.workUnitsConsumed, expectedWork, file: file, line: line)

        assertEditingError(
            .workLimitExceeded(maximumWork: expectedWork - 1),
            file: file,
            line: line
        ) {
            try operation(self.limits(maximumWork: expectedWork - 1))
        }
    }

    private func assertEditingError<T>(
        _ expected: TextSelectionEditingError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? TextSelectionEditingError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func assertAsyncEditingError<T>(
        _ expected: TextSelectionEditingError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as TextSelectionEditingError {
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
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private struct TextSelectionEditingOwnerState: Sendable {
    let document: TextSelectionEditingDocumentSnapshot
    let transferText: String?
    let compareCount: Int
    let commitCount: Int
    let lastCommittedTransaction: TextSelectionEditingCommitTransaction?
}

private actor TextSelectionEditingTestOwner: TextSelectionEditingAtomicCommitOwner {
    private var document: TextSelectionEditingDocumentSnapshot
    private var transferText: String?
    private var compareCount = 0
    private var commitCount = 0
    private var lastCommittedTransaction: TextSelectionEditingCommitTransaction?
    private let alwaysReject: Bool
    private let cancelInsideCAS: Bool

    init(
        document: TextSelectionEditingDocumentSnapshot,
        transferText: String? = nil,
        alwaysReject: Bool = false,
        cancelInsideCAS: Bool = false
    ) {
        self.document = document
        self.transferText = transferText
        self.alwaysReject = alwaysReject
        self.cancelInsideCAS = cancelInsideCAS
    }

    func commit(
        _ plan: TextSelectionEditingPlan
    ) throws -> TextSelectionEditingApplication {
        try plan.commit(to: self)
    }

    func compareAndCommit(
        _ transaction: TextSelectionEditingCommitTransaction
    ) -> TextSelectionEditingAtomicCommitOutcome {
        compareCount += 1
        guard !alwaysReject, document == transaction.expectedDocument else {
            if cancelInsideCAS {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return .notCommitted(currentDocument: document)
        }

        document = TextSelectionEditingDocumentSnapshot(
            documentID: document.documentID,
            revision: transaction.didChangeText ? document.revision + 1 : document.revision,
            text: transaction.text,
            selectionRange: transaction.selectionRange,
            isEditable: document.isEditable
        )
        if let copiedText = transaction.copiedText {
            transferText = copiedText
        }
        commitCount += 1
        lastCommittedTransaction = transaction
        if cancelInsideCAS {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return .committed
    }

    func state() -> TextSelectionEditingOwnerState {
        TextSelectionEditingOwnerState(
            document: document,
            transferText: transferText,
            compareCount: compareCount,
            commitCount: commitCount,
            lastCommittedTransaction: lastCommittedTransaction
        )
    }

    func replaceOwnedState(
        document: TextSelectionEditingDocumentSnapshot,
        transferText: String?
    ) {
        self.document = document
        self.transferText = transferText
    }
}

private struct TextSelectionEditingCommitAttempt: Sendable {
    let receipt: TextSelectionEditingApplication?
    let error: TextSelectionEditingError?

    var isSuccess: Bool { receipt != nil }
}

private func commitAttempt(
    _ plan: TextSelectionEditingPlan,
    to owner: TextSelectionEditingTestOwner
) async -> TextSelectionEditingCommitAttempt {
    do {
        return TextSelectionEditingCommitAttempt(
            receipt: try await owner.commit(plan),
            error: nil
        )
    } catch let error as TextSelectionEditingError {
        return TextSelectionEditingCommitAttempt(receipt: nil, error: error)
    } catch {
        return TextSelectionEditingCommitAttempt(receipt: nil, error: nil)
    }
}

private func scalarValues(_ text: String) -> [UInt32] {
    text.unicodeScalars.map(\.value)
}
