import Foundation
import XCTest

@testable import MacMergeCore

final class TextReplacementTests: XCTestCase {
    func testLiteralReplacementTreatsTemplateLiterallyAndBuildsUTF16Edits() throws {
        let document = snapshot("foo foo", revision: 7)
        let query = TextSearchQuery(literal: "foo")

        let plan = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: query,
            with: "$1"
        )

        XCTAssertEqual(plan.action, .replaceAll)
        XCTAssertEqual(plan.query, query)
        XCTAssertEqual(plan.replacement, "$1")
        XCTAssertEqual(plan.sourceRevision, 7)
        XCTAssertEqual(plan.sourceUTF16Length, 7)
        XCTAssertNil(plan.match)
        XCTAssertFalse(plan.didWrap)
        XCTAssertEqual(plan.resultText, "$1 $1")
        XCTAssertEqual(plan.replacementCount, 2)
        XCTAssertEqual(plan.changedCount, 2)
        XCTAssertTrue(plan.hasChanges)
        XCTAssertEqual(
            plan.edits.map(\.sourceRange),
            [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)]
        )
        XCTAssertEqual(plan.edits.map(\.originalText), ["foo", "foo"])
        XCTAssertEqual(plan.edits.map(\.replacementText), ["$1", "$1"])
        XCTAssertEqual(
            plan.edits.map(\.resultRange),
            [NSRange(location: 0, length: 2), NSRange(location: 3, length: 2)]
        )
        XCTAssertEqual(plan.changedSourceRanges, plan.edits.map(\.sourceRange))
        XCTAssertEqual(plan.changedResultRanges, plan.edits.map(\.resultRange))
        XCTAssertNil(plan.selectionRange)
        XCTAssertEqual(try plan.apply(to: document), "$1 $1")
    }

    func testRegularExpressionReplacementExpandsCapturesPerEdit() throws {
        let document = snapshot("item-42 note-7")
        let query = TextSearchQuery(regularExpression: #"([a-z]+)-(\d+)"#)

        let plan = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: query,
            with: #"<$2:$1:\$>"#
        )

        XCTAssertEqual(plan.resultText, "<42:item:$> <7:note:$>")
        XCTAssertEqual(plan.replacementCount, 2)
        XCTAssertEqual(
            plan.edits.map(\.sourceRange),
            [NSRange(location: 0, length: 7), NSRange(location: 8, length: 6)]
        )
        XCTAssertEqual(plan.edits.map(\.originalText), ["item-42", "note-7"])
        XCTAssertEqual(plan.edits.map(\.replacementText), ["<42:item:$>", "<7:note:$>"])
        XCTAssertEqual(
            plan.edits.map(\.resultRange),
            [NSRange(location: 0, length: 11), NSRange(location: 12, length: 10)]
        )
        XCTAssertEqual(try plan.apply(to: document), plan.resultText)
    }

    func testRegexTemplateDistinguishesCaptureTenFromCaptureOneFollowedByZero() throws {
        let tenCaptures = try TextReplacementPlanner.replaceAll(
            in: snapshot("abcdefghij"),
            matching: TextSearchQuery(
                regularExpression: "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)"
            ),
            with: "$10-$1"
        )
        let oneCapture = try TextReplacementPlanner.replaceAll(
            in: snapshot("a"),
            matching: TextSearchQuery(regularExpression: "(a)"),
            with: "$10"
        )

        XCTAssertEqual(tenCaptures.resultText, "j-a")
        XCTAssertEqual(tenCaptures.edits.map(\.replacementText), ["j-a"])
        XCTAssertEqual(oneCapture.resultText, "a0")
        XCTAssertEqual(oneCapture.edits.map(\.replacementText), ["a0"])
    }

    func testWholeWordAndCaseOptionsAgreeForLiteralAndRegexPlans() throws {
        let document = snapshot("Cat cat scatter CAT猫 CAT")
        let literalQuery = TextSearchQuery(literal: "cat", caseSensitive: false, wholeWord: true)
        let regexQuery = TextSearchQuery(
            regularExpression: "cat",
            caseSensitive: false,
            wholeWord: true
        )
        let expectedRanges = [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 3),
            NSRange(location: 21, length: 3)
        ]

        let literal = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: literalQuery,
            with: "X"
        )
        let regex = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: regexQuery,
            with: "X"
        )
        let caseSensitive = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: TextSearchQuery(literal: "Cat", wholeWord: true),
            with: "X"
        )

        XCTAssertEqual(literal.edits.map(\.sourceRange), expectedRanges)
        XCTAssertEqual(regex.edits.map(\.sourceRange), expectedRanges)
        XCTAssertEqual(literal.resultText, "X X scatter CAT猫 X")
        XCTAssertEqual(regex.resultText, literal.resultText)
        XCTAssertEqual(caseSensitive.edits.map(\.sourceRange), [expectedRanges[0]])
        XCTAssertEqual(caseSensitive.resultText, "X cat scatter CAT猫 CAT")
    }

    func testWholeWordRegexHandlesTrailingCommentsAndOpenQuotes() throws {
        let document = snapshot("foo foobar")
        let queries = [
            TextSearchQuery(
                regularExpression: "(?x)foo # trailing comment",
                wholeWord: true
            ),
            TextSearchQuery(regularExpression: #"\Qfoo"#, wholeWord: true),
            TextSearchQuery(
                regularExpression: "(?x)foo # \\Q",
                wholeWord: true
            )
        ]

        for query in queries {
            let plan = try TextReplacementPlanner.replaceAll(
                in: document,
                matching: query,
                with: "X"
            )

            XCTAssertEqual(plan.edits.map(\.sourceRange), [NSRange(location: 0, length: 3)])
            XCTAssertEqual(plan.resultText, "X foobar")
        }
    }

    func testRegexReplacementFallsBackToGraphemeSafeLongerAlternative() throws {
        let decomposed = "e\u{301}"
        let plan = try TextReplacementPlanner.replaceAll(
            in: snapshot(decomposed),
            matching: TextSearchQuery(regularExpression: "(e)|(e\u{301})"),
            with: "<$2>"
        )

        XCTAssertEqual(plan.edits.map(\.sourceRange), [NSRange(location: 0, length: 2)])
        XCTAssertEqual(plan.edits.map(\.replacementText), ["<\(decomposed)>"])
        XCTAssertEqual(plan.resultText, "<\(decomposed)>")
    }

    func testZeroLengthRegexPlansProgressAcrossGraphemes() throws {
        let document = snapshot("😀a")
        let query = TextSearchQuery(regularExpression: "")
        let ranges = [
            NSRange(location: 0, length: 0),
            NSRange(location: 2, length: 0),
            NSRange(location: 3, length: 0)
        ]

        let all = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: query,
            with: "-"
        )

        XCTAssertEqual(all.edits.map(\.sourceRange), ranges)
        XCTAssertEqual(
            all.edits.map(\.resultRange),
            [
                NSRange(location: 0, length: 1),
                NSRange(location: 3, length: 1),
                NSRange(location: 5, length: 1)
            ]
        )
        XCTAssertEqual(all.resultText, "-😀-a-")

        let current = try TextReplacementPlanner.replaceCurrent(
            in: document,
            match: TextSearchMatch(range: ranges[1]),
            matching: query,
            with: "X"
        )
        XCTAssertEqual(current.resultText, "😀Xa")
        XCTAssertEqual(current.selectionRange, NSRange(location: 2, length: 1))

        let next = try TextReplacementPlanner.next(
            in: document,
            matching: query,
            after: TextSearchMatch(range: ranges[0])
        )
        let previous = try TextReplacementPlanner.previous(
            in: document,
            matching: query,
            after: TextSearchMatch(range: ranges[0])
        )
        XCTAssertEqual(next.match?.range, ranges[1])
        XCTAssertFalse(next.didWrap)
        XCTAssertEqual(previous.match?.range, ranges[2])
        XCTAssertTrue(previous.didWrap)
    }

    func testUnicodeCanonicalLiteralPreservesComposedSelectionRanges() throws {
        let text = "Cafe\u{301} café"
        let document = snapshot(text)
        let query = TextSearchQuery(literal: "CAFÉ", caseSensitive: false)

        let first = try TextReplacementPlanner.next(
            in: document,
            matching: query,
            fromUTF16Offset: 0
        )
        let second = try TextReplacementPlanner.next(
            in: document,
            matching: query,
            after: try XCTUnwrap(first.match)
        )

        XCTAssertEqual(first.match?.range, NSRange(location: 0, length: 5))
        XCTAssertEqual(first.selectionRange, NSRange(location: 0, length: 5))
        XCTAssertEqual(second.match?.range, NSRange(location: 6, length: 4))
        XCTAssertEqual(second.selectionRange, NSRange(location: 6, length: 4))

        let replacement = try TextReplacementPlanner.replaceCurrent(
            in: document,
            match: try XCTUnwrap(first.match),
            matching: query,
            with: "😀"
        )
        XCTAssertEqual(replacement.resultText, "😀 café")
        XCTAssertEqual(replacement.edits[0].sourceRange, NSRange(location: 0, length: 5))
        XCTAssertEqual(replacement.edits[0].resultRange, NSRange(location: 0, length: 2))
        XCTAssertEqual(replacement.selectionRange, NSRange(location: 0, length: 2))
    }

    func testApplyIsAtomicAndChangedRangesExcludeScalarIdenticalEdits() throws {
        let document = snapshot("Cafe\u{301} café", revision: 42)
        let plan = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: TextSearchQuery(literal: "CAFÉ", caseSensitive: false),
            with: "café"
        )

        XCTAssertEqual(plan.resultText, "café café")
        XCTAssertEqual(plan.replacementCount, 2)
        XCTAssertEqual(plan.changedCount, 1)
        XCTAssertTrue(plan.edits[0].didChange)
        XCTAssertFalse(plan.edits[1].didChange)
        XCTAssertEqual(plan.changedSourceRanges, [NSRange(location: 0, length: 5)])
        XCTAssertEqual(plan.changedResultRanges, [NSRange(location: 0, length: 4)])
        XCTAssertEqual(
            plan.edits.map(\.resultRange),
            [NSRange(location: 0, length: 4), NSRange(location: 5, length: 4)]
        )
        XCTAssertEqual(try plan.apply(to: document), "café café")
        XCTAssertEqual(document.text, "Cafe\u{301} café")
    }

    func testPlanningAndApplyEnforceEditabilityAndExactSnapshotIdentity() throws {
        let document = snapshot("one one", revision: 9)
        let query = TextSearchQuery(literal: "one")

        assertPlanningError(.documentNotEditable) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot(document.text, revision: document.revision, isEditable: false),
                matching: query,
                with: "two"
            )
        }

        let navigation = try TextReplacementPlanner.next(
            in: snapshot(document.text, revision: document.revision, isEditable: false),
            matching: query,
            fromUTF16Offset: 0
        )
        XCTAssertEqual(navigation.match?.range, NSRange(location: 0, length: 3))
        XCTAssertEqual(
            try navigation.apply(
                to: snapshot(document.text, revision: document.revision, isEditable: false)
            ),
            document.text
        )

        let plan = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: query,
            with: "two"
        )
        assertPlanningError(.documentRevisionChanged(expected: 9, actual: 10)) {
            try plan.apply(to: snapshot("changed", revision: 10, isEditable: false))
        }
        assertPlanningError(.documentTextChanged) {
            try plan.apply(to: snapshot("changed", revision: 9, isEditable: false))
        }
        assertPlanningError(.documentNotEditable) {
            try plan.apply(to: snapshot(document.text, revision: 9, isEditable: false))
        }

        let decomposed = snapshot("e\u{301}", revision: 9)
        let canonicalPlan = try TextReplacementPlanner.replaceAll(
            in: decomposed,
            matching: TextSearchQuery(literal: "é"),
            with: "x"
        )
        assertPlanningError(.documentTextChanged) {
            try canonicalPlan.apply(to: snapshot("é", revision: 9))
        }
    }

    func testMaximumEditLimitAcceptsExactCountAndRejectsOneMoreOrZero() throws {
        let query = TextSearchQuery(literal: "a")
        let exactLimits = planningLimits(maximumMatches: 10, maximumEdits: 2)

        let exact = try TextReplacementPlanner.replaceAll(
            in: snapshot("aa"),
            matching: query,
            with: "x",
            limits: exactLimits
        )
        XCTAssertEqual(exact.replacementCount, 2)

        assertPlanningError(.tooManyEdits(maximumEdits: 2)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("aaa"),
                matching: query,
                with: "x",
                limits: exactLimits
            )
        }
        assertPlanningError(.tooManyEdits(maximumEdits: 0)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("a"),
                matching: query,
                with: "x",
                limits: planningLimits(maximumMatches: 10, maximumEdits: 0)
            )
        }
    }

    func testOutputAndTemplateLimitsApplyAtExactUTF16Boundaries() throws {
        let exact = try TextReplacementPlanner.replaceAll(
            in: snapshot("aa"),
            matching: TextSearchQuery(literal: "a"),
            with: "bb",
            limits: planningLimits(maximumOutputUTF16Length: 4)
        )
        XCTAssertEqual(exact.resultText, "bbbb")

        assertSearchError(.outputTooLarge(maximumUTF16Length: 3)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("aa"),
                matching: TextSearchQuery(literal: "a"),
                with: "bb",
                limits: planningLimits(maximumOutputUTF16Length: 3)
            )
        }
        assertSearchError(.outputTooLarge(maximumUTF16Length: 3)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("four"),
                matching: TextSearchQuery(literal: "absent"),
                with: "x",
                limits: planningLimits(maximumOutputUTF16Length: 3)
            )
        }

        XCTAssertEqual(
            try TextReplacementPlanner.replaceAll(
                in: snapshot("a"),
                matching: TextSearchQuery(literal: "a"),
                with: "😀",
                limits: planningLimits(maximumReplacementTemplateUTF16Length: 2)
            ).resultText,
            "😀"
        )
        assertSearchError(.replacementTemplateTooLarge(maximumUTF16Length: 2)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("a"),
                matching: TextSearchQuery(literal: "a"),
                with: "😀x",
                limits: planningLimits(maximumReplacementTemplateUTF16Length: 2)
            )
        }
    }

    func testLiteralInputPatternAndStoredCaptureLimitsAcceptExactBoundsAndRejectOneMore() throws {
        let inputLimits = planningLimits(maximumInputUTF16Length: 4)
        XCTAssertEqual(
            try TextReplacementPlanner.replaceAll(
                in: snapshot("😀ab"),
                matching: TextSearchQuery(literal: "ab"),
                with: "X",
                limits: inputLimits
            ).resultText,
            "😀X"
        )
        assertSearchError(.inputTooLarge(maximumUTF16Length: 4)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("😀abc"),
                matching: TextSearchQuery(literal: "a"),
                with: "X",
                limits: inputLimits
            )
        }

        let patternLimits = planningLimits(maximumPatternUTF16Length: 2)
        XCTAssertEqual(
            try TextReplacementPlanner.replaceAll(
                in: snapshot("😀"),
                matching: TextSearchQuery(literal: "😀"),
                with: "X",
                limits: patternLimits
            ).resultText,
            "X"
        )
        assertSearchError(.patternTooLarge(maximumUTF16Length: 2)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("😀a"),
                matching: TextSearchQuery(literal: "😀a"),
                with: "X",
                limits: patternLimits
            )
        }

        let captureLimits = planningLimits(maximumStoredCaptureRanges: 2)
        XCTAssertEqual(
            try TextReplacementPlanner.replaceAll(
                in: snapshot("aa"),
                matching: TextSearchQuery(literal: "a"),
                with: "x",
                limits: captureLimits
            ).replacementCount,
            2
        )
        assertSearchError(.tooManyCaptureRanges(maximumRanges: 2)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("aaa"),
                matching: TextSearchQuery(literal: "a"),
                with: "x",
                limits: captureLimits
            )
        }
    }

    func testLiteralWorkLimitAcceptsExactBudgetAndRejectsOneLess() throws {
        let document = snapshot("aa")
        let query = TextSearchQuery(literal: "a")

        let exact = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: query,
            with: "bb",
            limits: planningLimits(maximumWork: 17)
        )
        XCTAssertEqual(exact.resultText, "bbbb")

        assertPlanningError(.workLimitExceeded(maximumWork: 16)) {
            try TextReplacementPlanner.replaceAll(
                in: document,
                matching: query,
                with: "bb",
                limits: planningLimits(maximumWork: 16)
            )
        }
    }

    func testInvalidRegexPreflightWorkOverflowTakesPrecedenceOverPatternValidation() {
        assertPlanningError(.workLimitExceeded(maximumWork: Int.max)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("a"),
                matching: TextSearchQuery(regularExpression: "["),
                with: "",
                limits: planningLimits(
                    maximumRegularExpressionProgressSteps: Int.max,
                    maximumWork: Int.max
                )
            )
        }
    }

    func testRepeatedLargeCaptureExpansionIsPreflightedAgainstOutputLimit() throws {
        let source = String(repeating: "a", count: 1_024)
        let template = String(repeating: "$1", count: 16)
        let exactLength = 16 * 1_024
        let query = TextSearchQuery(regularExpression: "(a+)")

        let exact = try TextReplacementPlanner.replaceAll(
            in: snapshot(source),
            matching: query,
            with: template,
            limits: planningLimits(maximumOutputUTF16Length: exactLength)
        )
        XCTAssertEqual(exact.resultText.utf16.count, exactLength)
        XCTAssertEqual(exact.replacementCount, 1)

        assertSearchError(.outputTooLarge(maximumUTF16Length: exactLength - 1)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot(source),
                matching: query,
                with: template,
                limits: planningLimits(maximumOutputUTF16Length: exactLength - 1)
            )
        }
    }

    func testRepeatedUnmatchedCapturesProduceEmptyEditsWithoutMaterializedCaptureText() throws {
        let matchCount = 64
        let document = snapshot(String(repeating: "b", count: matchCount))
        let plan = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: TextSearchQuery(regularExpression: "(a)?b"),
            with: String(repeating: "$1", count: 128),
            limits: planningLimits(
                maximumOutputUTF16Length: 0,
                maximumMatches: matchCount,
                maximumStoredCaptureRanges: matchCount,
                maximumRegularExpressionProgressSteps: matchCount
            )
        )

        XCTAssertEqual(plan.replacementCount, matchCount)
        XCTAssertEqual(plan.changedCount, matchCount)
        XCTAssertEqual(plan.resultText, "")
        XCTAssertTrue(plan.edits.allSatisfy { $0.replacementText.isEmpty })
        XCTAssertEqual(try plan.apply(to: document), "")
    }

    func testRegexTemplateComponentExplosionConsumesWorkBeforeExpansion() {
        let template = String(repeating: "$1", count: 100)

        assertPlanningError(.workLimitExceeded(maximumWork: 441)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("b"),
                matching: TextSearchQuery(regularExpression: "(a)?b"),
                with: template,
                limits: planningLimits(
                    maximumOutputUTF16Length: 0,
                    maximumRegularExpressionProgressSteps: 10,
                    maximumWork: 441
                )
            )
        }
    }

    func testRegexProgressLimitAllowsAmpleBudgetAndRejectsLimitTwo() throws {
        let ampleLimits = planningLimits(
            maximumMatches: 10,
            maximumStoredCaptureRanges: 10,
            maximumRegularExpressionProgressSteps: 100
        )
        let query = TextSearchQuery(regularExpression: "a")

        let ample = try TextReplacementPlanner.replaceAll(
            in: snapshot("aa"),
            matching: query,
            with: "x",
            limits: ampleLimits
        )
        XCTAssertEqual(ample.resultText, "xx")

        assertSearchError(.evaluationLimitExceeded(maximumProgressSteps: 2)) {
            try TextReplacementPlanner.replaceAll(
                in: snapshot("aaa"),
                matching: query,
                with: "x",
                limits: planningLimits(
                    maximumMatches: 10,
                    maximumStoredCaptureRanges: 10,
                    maximumRegularExpressionProgressSteps: 2
                )
            )
        }
    }

    func testInvalidAndOverflowingCurrentRangesFailWithoutEdits() {
        let query = TextSearchQuery(literal: "a")

        assertSearchError(.invalidUTF16Range(NSRange(location: Int.max, length: 1))) {
            try TextReplacementPlanner.replaceCurrent(
                in: snapshot("a"),
                match: TextSearchMatch(range: NSRange(location: Int.max, length: 1)),
                matching: query,
                with: "x"
            )
        }
        assertSearchError(.rangeSplitsGrapheme(NSRange(location: 1, length: 0))) {
            try TextReplacementPlanner.replaceCurrent(
                in: snapshot("e\u{301}"),
                match: TextSearchMatch(range: NSRange(location: 1, length: 0)),
                matching: TextSearchQuery(literal: "é"),
                with: "x"
            )
        }
    }

    func testPreCancelledPlanningAndApplyAlwaysThrowCancellation() async throws {
        let document = snapshot("a")
        let plan = try TextReplacementPlanner.replaceAll(
            in: document,
            matching: TextSearchQuery(literal: "a"),
            with: "x"
        )
        let operations: [@Sendable () throws -> Void] = [
            {
                _ = try TextReplacementPlanner.replaceAll(
                    in: document,
                    matching: TextSearchQuery(literal: "a"),
                    with: "x"
                )
            },
            { _ = try plan.apply(to: document) }
        ]

        for operation in operations {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try operation()
            }
            do {
                try await task.value
                XCTFail("Pre-cancelled replacement unexpectedly succeeded")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCancellationInterruptsLiteralMatchCollection() async {
        let count = 1_000_000
        let text = String(repeating: "a", count: count)
        let document = snapshot(text)
        let limits = planningLimits(
            maximumInputUTF16Length: count,
            maximumOutputUTF16Length: count,
            maximumMatches: count,
            maximumStoredCaptureRanges: count,
            maximumEdits: count,
            maximumWork: count * 6
        )

        await assertInFlightCancellation {
            _ = try TextReplacementPlanner.replaceAll(
                in: document,
                matching: TextSearchQuery(literal: "a"),
                with: "x",
                limits: limits
            )
        }
    }

    func testCancellationInterruptsRegexEnumeration() async {
        let count = 250_000
        let text = String(repeating: "a", count: count)
        let document = snapshot(text)
        let limits = planningLimits(
            maximumInputUTF16Length: count,
            maximumOutputUTF16Length: count,
            maximumMatches: count,
            maximumStoredCaptureRanges: count,
            maximumRegularExpressionProgressSteps: count,
            maximumEdits: count,
            maximumWork: count * 12
        )

        await assertInFlightCancellation {
            _ = try TextReplacementPlanner.replaceAll(
                in: document,
                matching: TextSearchQuery(regularExpression: "a"),
                with: "x",
                limits: limits
            )
        }
    }

    func testCancellationInterruptsLargeLiteralNoMatchScan() async {
        let count = 32 * 1_024 * 1_024
        let text = String(repeating: "a", count: count)
        let document = snapshot(text)
        let limits = planningLimits(
            maximumInputUTF16Length: count,
            maximumOutputUTF16Length: count,
            maximumWork: count + 2
        )

        await assertInFlightCancellation {
            _ = try TextReplacementPlanner.replaceAll(
                in: document,
                matching: TextSearchQuery(literal: "z"),
                with: "x",
                limits: limits
            )
        }
    }

    func testPlansAndNavigationAreDeterministicAcrossRepeatedCalls() throws {
        let document = snapshot("one two one", revision: 3, isEditable: false)
        let query = TextSearchQuery(literal: "one")

        let first = try TextReplacementPlanner.next(
            in: document,
            matching: query,
            fromUTF16Offset: 0
        )
        let repeated = try TextReplacementPlanner.next(
            in: document,
            matching: query,
            fromUTF16Offset: 0
        )
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.match?.range, NSRange(location: 0, length: 3))
        XCTAssertEqual(first.selectionRange, first.match?.range)

        let last = try TextReplacementPlanner.next(
            in: document,
            matching: query,
            after: try XCTUnwrap(first.match)
        )
        XCTAssertEqual(last.match?.range, NSRange(location: 8, length: 3))
        XCTAssertFalse(last.didWrap)

        let wrappedNext = try TextReplacementPlanner.next(
            in: document,
            matching: query,
            after: try XCTUnwrap(last.match)
        )
        let wrappedPrevious = try TextReplacementPlanner.previous(
            in: document,
            matching: query,
            fromUTF16Offset: 0
        )
        XCTAssertEqual(wrappedNext.match, first.match)
        XCTAssertTrue(wrappedNext.didWrap)
        XCTAssertEqual(wrappedPrevious.match, last.match)
        XCTAssertTrue(wrappedPrevious.didWrap)
        XCTAssertEqual(first.edits, [])
        XCTAssertEqual(first.resultText, document.text)
    }

    func testLiteralAndRegexNavigationDoNotWrapWhenDisabled() throws {
        let document = snapshot("one two one")
        let first = TextSearchMatch(range: NSRange(location: 0, length: 3))
        let last = TextSearchMatch(range: NSRange(location: 8, length: 3))
        let queries = [
            TextSearchQuery(literal: "one"),
            TextSearchQuery(regularExpression: "one")
        ]

        for query in queries {
            let next = try TextReplacementPlanner.next(
                in: document,
                matching: query,
                after: last,
                wrap: false
            )
            let previous = try TextReplacementPlanner.previous(
                in: document,
                matching: query,
                after: first,
                wrap: false
            )

            XCTAssertNil(next.match)
            XCTAssertFalse(next.didWrap)
            XCTAssertNil(next.selectionRange)
            XCTAssertNil(previous.match)
            XCTAssertFalse(previous.didWrap)
            XCTAssertNil(previous.selectionRange)
        }
    }

    private func snapshot(
        _ text: String,
        revision: UInt64 = 1,
        isEditable: Bool = true
    ) -> TextReplacementDocumentSnapshot {
        TextReplacementDocumentSnapshot(
            text: text,
            revision: revision,
            isEditable: isEditable
        )
    }

    private func planningLimits(
        maximumInputUTF16Length: Int = 100_000,
        maximumPatternUTF16Length: Int = 100_000,
        maximumOutputUTF16Length: Int = 100_000,
        maximumMatches: Int = 100_000,
        maximumReplacementTemplateUTF16Length: Int = 100_000,
        maximumStoredCaptureRanges: Int = 100_000,
        maximumRegularExpressionProgressSteps: Int = 100_000,
        maximumEdits: Int = 100_000,
        maximumWork: Int = TextReplacementPlanningLimits.defaultMaximumWork
    ) -> TextReplacementPlanningLimits {
        TextReplacementPlanningLimits(
            search: TextSearchLimits(
                maximumInputUTF16Length: maximumInputUTF16Length,
                maximumPatternUTF16Length: maximumPatternUTF16Length,
                maximumOutputUTF16Length: maximumOutputUTF16Length,
                maximumMatches: maximumMatches,
                maximumMarkers: 0,
                maximumCombinedPatternUTF16Length: 0,
                maximumReplacementTemplateUTF16Length: maximumReplacementTemplateUTF16Length,
                maximumStoredCaptureRanges: maximumStoredCaptureRanges,
                maximumRegularExpressionProgressSteps: maximumRegularExpressionProgressSteps
            ),
            maximumEdits: maximumEdits,
            maximumWork: maximumWork
        )
    }

    private func assertPlanningError<T>(
        _ expected: TextReplacementPlanningError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> T
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? TextReplacementPlanningError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func assertSearchError<T>(
        _ expected: TextSearchError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> T
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? TextSearchError, expected, file: file, line: line)
        }
    }

    private func assertInFlightCancellation(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping @Sendable () throws -> Void
    ) async {
        let gate = TextReplacementCancellationGate()
        let task = Task.detached {
            await gate.enterOperationPhase()
            let outcome: TextReplacementCancellationOutcome
            do {
                try operation()
                outcome = .succeeded
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed(String(describing: error))
            }
            await gate.recordCompletion(outcome)
        }
        guard await gate.waitUntilOperationPhase(timeout: .seconds(5)) else {
            task.cancel()
            await gate.releaseOperationPhase()
            XCTFail("Replacement did not reach cancellation phase", file: file, line: line)
            return
        }
        task.cancel()
        await gate.releaseOperationPhase()

        guard let outcome = await gate.waitUntilCompleted(timeout: .seconds(5)) else {
            task.cancel()
            XCTFail("Cancelled replacement exceeded bounded wait", file: file, line: line)
            return
        }
        switch outcome {
        case .cancelled:
            break
        case .succeeded:
            XCTFail("In-flight replacement unexpectedly succeeded", file: file, line: line)
        case .failed(let description):
            XCTFail("Unexpected error: \(description)", file: file, line: line)
        }
    }
}

private enum TextReplacementCancellationOutcome: Sendable {
    case succeeded
    case cancelled
    case failed(String)
}

private actor TextReplacementCancellationGate {
    private var operationPhaseReached = false
    private var operationPhaseReleased = false
    private var completion: TextReplacementCancellationOutcome?

    func enterOperationPhase() async {
        operationPhaseReached = true
        while !operationPhaseReleased {
            await Task.yield()
        }
    }

    func waitUntilOperationPhase(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !operationPhaseReached, clock.now < deadline {
            await Task.yield()
        }
        return operationPhaseReached
    }

    func releaseOperationPhase() {
        operationPhaseReleased = true
    }

    func recordCompletion(_ outcome: TextReplacementCancellationOutcome) {
        completion = outcome
    }

    func waitUntilCompleted(timeout: Duration) async -> TextReplacementCancellationOutcome? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while completion == nil, clock.now < deadline {
            await Task.yield()
        }
        return completion
    }
}
