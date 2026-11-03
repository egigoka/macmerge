import Foundation
import XCTest

@testable import MacMergeCore

final class FindReplaceEditorRoutingTests: XCTestCase {
    func testFindNextWrapsForward() throws {
        let snap = snapshot("one two one", caret: 1)
        let query = TextSearchQuery(literal: "one")

        let advanced = try FindReplaceEditorRouting.findNext(in: snap, matching: query)
        XCTAssertEqual(advanced.match?.range, NSRange(location: 8, length: 3))
        XCTAssertFalse(advanced.didWrap)
        XCTAssertEqual(advanced.selectionRange, advanced.match?.range)

        let wrapped = try FindReplaceEditorRouting.findNext(
            in: snapshot("one two one", caret: 9),
            matching: query
        )
        XCTAssertEqual(wrapped.match?.range, NSRange(location: 0, length: 3))
        XCTAssertTrue(wrapped.didWrap)

        let noWrap = try FindReplaceEditorRouting.findNext(
            in: snapshot("one two one", caret: 9),
            matching: query,
            wrap: false
        )
        XCTAssertNil(noWrap.match)
        XCTAssertFalse(noWrap.didWrap)
        XCTAssertNil(noWrap.selectionRange)
    }

    func testFindPreviousWrapsBackward() throws {
        let query = TextSearchQuery(literal: "one")

        let found = try FindReplaceEditorRouting.findPrevious(
            in: snapshot("one two one", caret: 11),
            matching: query
        )
        XCTAssertEqual(found.match?.range, NSRange(location: 8, length: 3))
        XCTAssertFalse(found.didWrap)

        let wrapped = try FindReplaceEditorRouting.findPrevious(
            in: snapshot("one two one", caret: 0),
            matching: query
        )
        XCTAssertEqual(wrapped.match?.range, NSRange(location: 8, length: 3))
        XCTAssertTrue(wrapped.didWrap)

        let noWrap = try FindReplaceEditorRouting.findPrevious(
            in: snapshot("one two one", caret: 0),
            matching: query,
            wrap: false
        )
        XCTAssertNil(noWrap.match)
        XCTAssertFalse(noWrap.didWrap)
    }

    func testFindAfterMatchProgressesBothDirections() throws {
        let snap = snapshot("one two one", caret: 0)
        let query = TextSearchQuery(literal: "one")
        let first = try XCTUnwrap(
            try FindReplaceEditorRouting.findNext(in: snap, matching: query).match
        )
        XCTAssertEqual(first.range, NSRange(location: 0, length: 3))

        let next = try FindReplaceEditorRouting.findNext(in: snap, matching: query, after: first)
        XCTAssertEqual(next.match?.range, NSRange(location: 8, length: 3))
        XCTAssertFalse(next.didWrap)

        let last = try XCTUnwrap(next.match)
        let rewound = try FindReplaceEditorRouting.findNext(
            in: snap, matching: query, after: last
        )
        XCTAssertEqual(rewound.match?.range, NSRange(location: 0, length: 3))
        XCTAssertTrue(rewound.didWrap)

        let back = try FindReplaceEditorRouting.findPrevious(
            in: snap, matching: query, after: last
        )
        XCTAssertEqual(back.match?.range, NSRange(location: 0, length: 3))
        XCTAssertFalse(back.didWrap)
    }

    func testReplaceCurrentAppliesAtomically() throws {
        let snap = snapshot("foo foo", caret: 0)
        let query = TextSearchQuery(literal: "foo")
        let found = try XCTUnwrap(
            try FindReplaceEditorRouting.findNext(in: snap, matching: query).match
        )

        let plan = try FindReplaceEditorRouting.replaceCurrent(
            in: snap, match: found, matching: query, with: "bar"
        )
        XCTAssertEqual(plan.action, .replaceCurrent)
        XCTAssertEqual(plan.replacementCount, 1)
        XCTAssertEqual(plan.resultText, "bar foo")
        XCTAssertEqual(plan.selectionRange, NSRange(location: 0, length: 3))
        XCTAssertEqual(try FindReplaceEditorRouting.apply(plan, to: snap), "bar foo")
        XCTAssertEqual(snap.text, "foo foo")
    }

    func testReplaceCurrentWithStaleMatchIsNoOp() throws {
        let snap = snapshot("foo foo", caret: 0)
        let plan = try FindReplaceEditorRouting.replaceCurrent(
            in: snap,
            match: TextSearchMatch(range: NSRange(location: 4, length: 3)),
            matching: TextSearchQuery(literal: "absent"),
            with: "bar"
        )
        XCTAssertEqual(plan.replacementCount, 0)
        XCTAssertEqual(plan.resultText, "foo foo")
        XCTAssertEqual(try FindReplaceEditorRouting.apply(plan, to: snap), "foo foo")
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.replaceCurrent(
                in: snap,
                match: TextSearchMatch(range: NSRange(location: 99, length: 3)),
                matching: TextSearchQuery(literal: "foo"),
                with: "bar"
            )
        ) {
            XCTAssertEqual(
                $0 as? TextSearchError,
                .invalidUTF16Range(NSRange(location: 99, length: 3))
            )
        }
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.replaceCurrent(
                in: snapshot("😀a", caret: 0),
                match: TextSearchMatch(range: NSRange(location: 1, length: 1)),
                matching: TextSearchQuery(literal: "a"),
                with: "bar"
            )
        ) {
            XCTAssertEqual(
                $0 as? TextSearchError,
                .rangeSplitsGrapheme(NSRange(location: 1, length: 1))
            )
        }
    }

    func testReplaceAllIsAtomic() throws {
        let snap = snapshot("foo foo", caret: 0)
        let plan = try FindReplaceEditorRouting.replaceAll(
            in: snap, matching: TextSearchQuery(literal: "foo"), with: "bar"
        )
        XCTAssertEqual(plan.action, .replaceAll)
        XCTAssertEqual(plan.replacementCount, 2)
        XCTAssertEqual(plan.resultText, "bar bar")
        XCTAssertNil(plan.selectionRange)
        XCTAssertEqual(try FindReplaceEditorRouting.apply(plan, to: snap), "bar bar")
        XCTAssertEqual(snap.text, "foo foo")
    }

    func testReplaceRequiresEditableDocument() throws {
        let locked = snapshot("foo", caret: 0, isEditable: false)
        let query = TextSearchQuery(literal: "foo")
        let match = TextSearchMatch(range: NSRange(location: 0, length: 3))

        XCTAssertThrowsError(
            try FindReplaceEditorRouting.replaceCurrent(
                in: locked, match: match, matching: query, with: "bar"
            )
        ) { XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .documentNotEditable) }
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.replaceAll(in: locked, matching: query, with: "bar")
        ) { XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .documentNotEditable) }

        let editable = snapshot("foo", caret: 0)
        let plan = try FindReplaceEditorRouting.replaceAll(
            in: editable, matching: query, with: "bar"
        )
        XCTAssertThrowsError(try FindReplaceEditorRouting.apply(plan, to: locked)) {
            XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .documentNotEditable)
        }

        let navigation = try FindReplaceEditorRouting.findNext(in: locked, matching: query)
        XCTAssertEqual(navigation.match?.range, NSRange(location: 0, length: 3))
        XCTAssertEqual(try FindReplaceEditorRouting.apply(navigation, to: locked), "foo")
        let previousLocked = try FindReplaceEditorRouting.findPrevious(in: locked, matching: query)
        XCTAssertEqual(previousLocked.match?.range, NSRange(location: 0, length: 3))
        let lockedMarkers = try markerSet(literal: "foo")
        let lockedSet = try FindReplaceEditorRouting.markerMatchSet(
            in: locked, markers: lockedMarkers
        )
        XCTAssertEqual(
            try lockedSet.allRanges(
                in: TextMarkerDocument(
                    text: "foo",
                    revision: TextMarkerDocumentRevision(rawValue: 1)
                )
            ).count,
            1
        )
        let lockedNavigation = try FindReplaceEditorRouting.markerNavigate(
            in: locked, markers: lockedMarkers
        )
        XCTAssertEqual(lockedNavigation.result.match?.range, NSRange(location: 0, length: 3))
    }

    func testRevisionDriftRejectsApply() throws {
        let snap = snapshot("foo foo", caret: 0, revision: 4)
        let plan = try FindReplaceEditorRouting.replaceAll(
            in: snap, matching: TextSearchQuery(literal: "foo"), with: "bar"
        )
        let drifted = snapshot("foo foo!", caret: 0, revision: 5)
        XCTAssertThrowsError(try FindReplaceEditorRouting.apply(plan, to: drifted)) {
            XCTAssertEqual(
                $0 as? FindReplaceEditorRoutingError,
                .documentRevisionChanged(expected: 4, actual: 5)
            )
        }
        let sameRevisionChangedText = snapshot("foo foo!", caret: 0, revision: 4)
        XCTAssertThrowsError(try FindReplaceEditorRouting.apply(plan, to: sameRevisionChangedText)) {
            XCTAssertEqual($0 as? TextReplacementPlanningError, .documentTextChanged)
        }
    }

    func testOutOfBoundsCaretAndSelectionRejected() throws {
        let query = TextSearchQuery(literal: "a")
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot("abc", caret: 0), matching: query, fromUTF16Offset: 99
            )
        ) { XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .invalidCaretOffset(99)) }
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot("abc", caret: -1), matching: query
            )
        ) { XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .invalidCaretOffset(-1)) }
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot("abc", caret: 0, selection: NSRange(location: 0, length: 99)),
                matching: query
            )
        ) {
            XCTAssertEqual(
                $0 as? FindReplaceEditorRoutingError,
                .invalidSelectionRange(NSRange(location: 0, length: 99))
            )
        }
    }

    func testGraphemeSplittingCaretAndSelectionRejected() throws {
        let text = "😀a"
        let query = TextSearchQuery(literal: "a")
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot(text, caret: 0), matching: query, fromUTF16Offset: 1
            )
        ) { XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .caretOffsetSplitsGrapheme(1)) }
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot(text, caret: 1), matching: query
            )
        ) { XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .caretOffsetSplitsGrapheme(1)) }
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot(text, caret: 0, selection: NSRange(location: 1, length: 0)),
                matching: query
            )
        ) {
            XCTAssertEqual(
                $0 as? FindReplaceEditorRoutingError,
                .selectionSplitsGrapheme(NSRange(location: 1, length: 0))
            )
        }
    }

    func testLiteralRegexAndWholeWordQueries() throws {
        let insensitive = try FindReplaceEditorRouting.replaceAll(
            in: snapshot("Cat CAT cat", caret: 0),
            matching: TextSearchQuery(literal: "cat", caseSensitive: false),
            with: "X"
        )
        XCTAssertEqual(insensitive.resultText, "X X X")

        let sensitive = try FindReplaceEditorRouting.replaceAll(
            in: snapshot("Cat CAT cat", caret: 0),
            matching: TextSearchQuery(literal: "cat"),
            with: "X"
        )
        XCTAssertEqual(sensitive.resultText, "Cat CAT X")

        let wholeWord = try FindReplaceEditorRouting.replaceAll(
            in: snapshot("cat scatter CAT", caret: 0),
            matching: TextSearchQuery(literal: "cat", caseSensitive: false, wholeWord: true),
            with: "X"
        )
        XCTAssertEqual(wholeWord.resultText, "X scatter X")
        XCTAssertEqual(wholeWord.replacementCount, 2)

        let regex = try FindReplaceEditorRouting.replaceAll(
            in: snapshot("cat cot cut", caret: 0),
            matching: TextSearchQuery(regularExpression: "c.t"),
            with: "X"
        )
        XCTAssertEqual(regex.resultText, "X X X")

        let capture = try FindReplaceEditorRouting.replaceAll(
            in: snapshot("item-42", caret: 0),
            matching: TextSearchQuery(regularExpression: #"([a-z]+)-(\d+)"#),
            with: "$2:$1"
        )
        XCTAssertEqual(capture.resultText, "42:item")
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot("abc", caret: 0),
                matching: TextSearchQuery(regularExpression: "[")
            )
        ) { XCTAssertEqual($0 as? TextSearchError, .invalidPattern("[")) }
    }

    func testMarkerToggleActivatesAndDeactivates() throws {
        var markers = try TextMarkers(
            markers: [
                try NamedTextMarker(id: "a", name: "A", query: TextSearchQuery(literal: "foo")),
                try NamedTextMarker(id: "b", name: "B", query: TextSearchQuery(literal: "bar")),
            ],
            activeMarkerID: "a"
        )
        XCTAssertEqual(try FindReplaceEditorRouting.markerToggle(id: "a", in: markers), .deactivate)
        XCTAssertEqual(
            try FindReplaceEditorRouting.markerToggle(id: "b", in: markers), .activate(id: "b")
        )
        try markers.activate(id: "b")
        XCTAssertEqual(try FindReplaceEditorRouting.markerToggle(id: "b", in: markers), .deactivate)
        XCTAssertThrowsError(try FindReplaceEditorRouting.markerToggle(id: "missing", in: markers)) {
            XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .unknownMarker("missing"))
        }
    }

    func testMarkerNavigateAndRepeat() throws {
        let markers = try markerSet(literal: "foo")
        let snap = snapshot("foo bar foo", caret: 4)

        let navigation = try FindReplaceEditorRouting.markerNavigate(in: snap, markers: markers)
        XCTAssertEqual(navigation.result.match?.range, NSRange(location: 8, length: 3))
        XCTAssertFalse(navigation.result.didWrap)

        let backward = try FindReplaceEditorRouting.markerNavigate(
            in: snap, markers: markers, direction: .backward
        )
        XCTAssertEqual(backward.result.match?.range, NSRange(location: 0, length: 3))

        let wrapped = try FindReplaceEditorRouting.markerNavigate(
            in: snapshot("foo bar foo", caret: 9), markers: markers
        )
        XCTAssertEqual(wrapped.result.match?.range, NSRange(location: 0, length: 3))
        XCTAssertTrue(wrapped.result.didWrap)

        let repeated = try FindReplaceEditorRouting.markerRepeat(
            navigation.result, in: navigation.matchSet, document: snap, wrap: false
        )
        XCTAssertNil(repeated.match)

        let rewound = try FindReplaceEditorRouting.markerRepeat(
            navigation.result, in: navigation.matchSet, document: snap
        )
        XCTAssertEqual(rewound.match?.range, NSRange(location: 0, length: 3))
        XCTAssertTrue(rewound.didWrap)
        let twoMarkers = try TextMarkers(
            markers: [
                try NamedTextMarker(id: "a", name: "A", query: TextSearchQuery(literal: "foo")),
                try NamedTextMarker(id: "b", name: "B", query: TextSearchQuery(literal: "bar")),
            ],
            activeMarkerID: "a"
        )
        let explicit = try FindReplaceEditorRouting.markerNavigate(
            in: snapshot("foo bar", caret: 0),
            markers: twoMarkers,
            markerID: "b"
        )
        XCTAssertEqual(explicit.result.match?.range, NSRange(location: 4, length: 3))
        let inactive = try TextMarkers(
            markers: [
                try NamedTextMarker(
                    id: "a", name: "A", query: TextSearchQuery(literal: "foo")
                ),
            ],
            activeMarkerID: nil
        )
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.markerNavigate(in: snap, markers: inactive)
        ) { XCTAssertEqual($0 as? TextMarkersError, .noActiveMarker) }
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.markerNavigate(
                in: snap, markers: markers, fromUTF16Offset: 99
            )
        ) {
            XCTAssertEqual(
                $0 as? FindReplaceEditorRoutingError,
                .invalidCaretOffset(99)
            )
        }
    }

    func testMarkerRepeatRejectsStaleDocument() throws {
        let markers = try markerSet(literal: "foo")
        let snap = snapshot("foo bar foo", caret: 4)
        let navigation = try FindReplaceEditorRouting.markerNavigate(in: snap, markers: markers)
        let edited = snapshot("foo bar foo!", caret: 4)

        XCTAssertThrowsError(
            try FindReplaceEditorRouting.markerRepeat(
                navigation.result, in: navigation.matchSet, document: edited
            )
        ) {
            XCTAssertEqual($0 as? TextMarkersError, .staleDocument)
        }
        XCTAssertThrowsError(
            try navigation.matchSet.navigate(
                fromUTF16Offset: 4,
                in: TextMarkerDocument(
                    text: "foo bar foo!",
                    revision: TextMarkerDocumentRevision(rawValue: 1)
                )
            )
        ) {
            XCTAssertEqual($0 as? TextMarkersError, .staleDocument)
        }
        let revised = snapshot("foo bar foo", caret: 4, revision: 2)
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.markerRepeat(
                navigation.result, in: navigation.matchSet, document: revised
            )
        ) {
            XCTAssertEqual(
                $0 as? TextMarkersError,
                .staleDocumentRevision(
                    expected: TextMarkerDocumentRevision(rawValue: 1),
                    actual: TextMarkerDocumentRevision(rawValue: 2)
                )
            )
        }
    }

    func testInvalidLimitsRejected() throws {
        let limits = FindReplaceEditorRoutingLimits(
            markers: TextMarkersLimits(maximumMarkers: 0)
        )
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot("abc", caret: 0),
                matching: TextSearchQuery(literal: "a"),
                limits: limits
            )
        ) { XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .invalidLimits) }
        let negativeWork = FindReplaceEditorRoutingLimits(
            markers: TextMarkersLimits(maximumWorkUnits: -1)
        )
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot("abc", caret: 0),
                matching: TextSearchQuery(literal: "a"),
                limits: negativeWork
            )
        ) { XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .invalidLimits) }
        let zeroRanges = FindReplaceEditorRoutingLimits(
            markers: TextMarkersLimits(maximumResultRanges: 0)
        )
        XCTAssertThrowsError(
            try FindReplaceEditorRouting.findNext(
                in: snapshot("abc", caret: 0),
                matching: TextSearchQuery(literal: "a"),
                limits: zeroRanges
            )
        ) { XCTAssertEqual($0 as? FindReplaceEditorRoutingError, .invalidLimits) }
    }

    func testPreCancelledRoutingThrowsCancellation() async throws {
        let snap = snapshot("abc", caret: 0)
        let query = TextSearchQuery(literal: "b")
        let markers = try markerSet(literal: "b")

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try FindReplaceEditorRouting.findNext(in: snap, matching: query)
        }
        do {
            _ = try await task.value
            XCTFail("Pre-cancelled find unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let markerTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try FindReplaceEditorRouting.markerMatchSet(in: snap, markers: markers)
        }
        do {
            _ = try await markerTask.value
            XCTFail("Pre-cancelled marker search unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let replaceTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try FindReplaceEditorRouting.replaceAll(in: snap, matching: query, with: "X")
        }
        do {
            _ = try await replaceTask.value
            XCTFail("Pre-cancelled replace unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let replacePlan = try FindReplaceEditorRouting.replaceAll(
            in: snap, matching: query, with: "X"
        )
        let applyTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try FindReplaceEditorRouting.apply(replacePlan, to: snap)
        }
        do {
            _ = try await applyTask.value
            XCTFail("Pre-cancelled apply unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let navigateTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try FindReplaceEditorRouting.markerNavigate(in: snap, markers: markers)
        }
        do {
            _ = try await navigateTask.value
            XCTFail("Pre-cancelled marker navigate unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let navigation = try FindReplaceEditorRouting.markerNavigate(in: snap, markers: markers)
        let repeatTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try FindReplaceEditorRouting.markerRepeat(
                navigation.result, in: navigation.matchSet, document: snap
            )
        }
        do {
            _ = try await repeatTask.value
            XCTFail("Pre-cancelled marker repeat unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func snapshot(
        _ text: String,
        caret: Int = 0,
        revision: UInt64 = 1,
        isEditable: Bool = true,
        selection: NSRange? = nil
    ) -> FindReplaceEditorDocumentSnapshot {
        FindReplaceEditorDocumentSnapshot(
            documentID: UUID(),
            revision: revision,
            text: text,
            caretUTF16Offset: caret,
            selectionRange: selection,
            isEditable: isEditable
        )
    }

    private func markerSet(literal pattern: String, id: String = "m1") throws -> TextMarkers {
        try TextMarkers(
            markers: [
                try NamedTextMarker(id: id, name: "M", query: TextSearchQuery(literal: pattern)),
            ],
            activeMarkerID: id
        )
    }
}
