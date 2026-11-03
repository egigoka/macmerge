import Foundation
import MacMergeCore
import XCTest

final class BookmarkEditorRoutingTests: XCTestCase {
    func testToggleAddsAndRemovesBookmark() throws {
        let (snapshot, expected) = try makeSnapshot(bookmarkLines: [])
        XCTAssertTrue(snapshot.bookmarks.isEmpty)

        let added = try BookmarkEditorRouting.toggle(line: 4, in: snapshot, expected: expected)
        XCTAssertTrue(added.isBookmarked)
        XCTAssertEqual(added.line, 4)
        XCTAssertEqual(added.bookmarks.lines, [4])
        XCTAssertTrue(snapshot.bookmarks.isEmpty)

        let (reselected, _) = try makeSnapshot(
            bookmarkLines: added.bookmarks.lines,
            documentID: snapshot.documentID,
            generation: snapshot.generation
        )
        let removed = try BookmarkEditorRouting.toggle(line: 4, in: reselected, expected: expected)
        XCTAssertFalse(removed.isBookmarked)
        XCTAssertEqual(removed.bookmarks.lines, [])
    }

    func testToggleRejectsOutOfRangeLine() throws {
        let (snapshot, expected) = try makeSnapshot(lineCount: 10)

        assertRoutingError(
            .lineOutOfRange(line: 0, lineCount: 10),
            try BookmarkEditorRouting.toggle(line: 0, in: snapshot, expected: expected)
        )
        assertRoutingError(
            .lineOutOfRange(line: 11, lineCount: 10),
            try BookmarkEditorRouting.toggle(line: 11, in: snapshot, expected: expected)
        )
    }

    func testNextNavigatesWithWrapPolicies() throws {
        let (snapshot, expected) = try makeSnapshot(lineCount: 10, bookmarkLines: [2, 5, 9])

        XCTAssertEqual(
            try BookmarkEditorRouting.next(from: 5, in: snapshot, expected: expected),
            LineBookmarkNavigationResult(line: 9, didWrap: false)
        )
        XCTAssertEqual(
            try BookmarkEditorRouting.next(from: 6, in: snapshot, expected: expected),
            LineBookmarkNavigationResult(line: 9, didWrap: false)
        )
        XCTAssertEqual(
            try BookmarkEditorRouting.next(from: 9, in: snapshot, expected: expected),
            LineBookmarkNavigationResult(line: 2, didWrap: true)
        )
        XCTAssertNil(
            try BookmarkEditorRouting.next(
                from: 9, in: snapshot, expected: expected, wrapPolicy: .noWrap
            )
        )
        XCTAssertEqual(
            try BookmarkEditorRouting.next(from: 10, in: snapshot, expected: expected),
            LineBookmarkNavigationResult(line: 2, didWrap: true)
        )
    }

    func testPreviousNavigatesWithWrapPolicies() throws {
        let (snapshot, expected) = try makeSnapshot(lineCount: 10, bookmarkLines: [2, 5, 9])

        XCTAssertEqual(
            try BookmarkEditorRouting.previous(before: 5, in: snapshot, expected: expected),
            LineBookmarkNavigationResult(line: 2, didWrap: false)
        )
        XCTAssertEqual(
            try BookmarkEditorRouting.previous(before: 6, in: snapshot, expected: expected),
            LineBookmarkNavigationResult(line: 5, didWrap: false)
        )
        XCTAssertEqual(
            try BookmarkEditorRouting.previous(before: 2, in: snapshot, expected: expected),
            LineBookmarkNavigationResult(line: 9, didWrap: true)
        )
        XCTAssertNil(
            try BookmarkEditorRouting.previous(
                before: 2, in: snapshot, expected: expected, wrapPolicy: .noWrap
            )
        )
        XCTAssertEqual(
            try BookmarkEditorRouting.previous(before: 1, in: snapshot, expected: expected),
            LineBookmarkNavigationResult(line: 9, didWrap: true)
        )
    }

    func testNavigationFromOutOfRangeLineFails() throws {
        let (snapshot, expected) = try makeSnapshot(lineCount: 10, bookmarkLines: [2])

        assertRoutingError(
            .lineOutOfRange(line: 0, lineCount: 10),
            try BookmarkEditorRouting.next(from: 0, in: snapshot, expected: expected)
        )
        assertRoutingError(
            .lineOutOfRange(line: 11, lineCount: 10),
            try BookmarkEditorRouting.next(from: 11, in: snapshot, expected: expected)
        )
        assertRoutingError(
            .lineOutOfRange(line: 0, lineCount: 10),
            try BookmarkEditorRouting.previous(before: 0, in: snapshot, expected: expected)
        )
        assertRoutingError(
            .lineOutOfRange(line: 11, lineCount: 10),
            try BookmarkEditorRouting.previous(before: 11, in: snapshot, expected: expected)
        )
    }

    func testNavigationWithEmptyBookmarksReturnsNil() throws {
        let (snapshot, expected) = try makeSnapshot(lineCount: 10, bookmarkLines: [])

        XCTAssertNil(try BookmarkEditorRouting.next(from: 5, in: snapshot, expected: expected))
        XCTAssertNil(
            try BookmarkEditorRouting.previous(before: 5, in: snapshot, expected: expected)
        )
    }

    func testClearAllReportsDidClear() throws {
        let (snapshot, expected) = try makeSnapshot(lineCount: 10, bookmarkLines: [2, 5])

        let cleared = try BookmarkEditorRouting.clearAll(in: snapshot, expected: expected)
        XCTAssertTrue(cleared.didClear)
        XCTAssertEqual(cleared.bookmarks.lines, [])
        XCTAssertEqual(snapshot.bookmarks.lines, [2, 5])

        let (empty, _) = try makeSnapshot(
            lineCount: 10,
            documentID: snapshot.documentID,
            generation: snapshot.generation
        )
        let repeated = try BookmarkEditorRouting.clearAll(in: empty, expected: expected)
        XCTAssertFalse(repeated.didClear)
    }

    func testInsertLinesRemapsBookmarksAndLineCount() throws {
        let (snapshot, expected) = try makeSnapshot(lineCount: 10, bookmarkLines: [2, 5])

        let shifted = try BookmarkEditorRouting.insertLines(
            at: 3, count: 2, in: snapshot, expected: expected
        )
        XCTAssertEqual(shifted.bookmarks.lines, [2, 7])
        XCTAssertEqual(shifted.lineCount, 12)

        let appended = try BookmarkEditorRouting.insertLines(
            at: 11, count: 3, in: snapshot, expected: expected
        )
        XCTAssertEqual(appended.bookmarks.lines, [2, 5])
        XCTAssertEqual(appended.lineCount, 13)

        let untouched = try BookmarkEditorRouting.insertLines(
            at: 5, count: 0, in: snapshot, expected: expected
        )
        XCTAssertEqual(untouched.bookmarks.lines, [2, 5])
        XCTAssertEqual(untouched.lineCount, 10)
    }

    func testDeleteLinesRemapsHalfOpenAndClosedRanges() throws {
        let (halfOpenSnapshot, halfOpenExpectation) = try makeSnapshot(
            lineCount: 10, bookmarkLines: [1, 3, 4, 5, 7]
        )
        let halfOpen = try BookmarkEditorRouting.deleteLines(
            in: 3..<5, in: halfOpenSnapshot, expected: halfOpenExpectation
        )
        XCTAssertEqual(halfOpen.bookmarks.lines, [1, 3, 5])
        XCTAssertEqual(halfOpen.lineCount, 8)

        let (closedSnapshot, closedExpectation) = try makeSnapshot(
            lineCount: 10, bookmarkLines: [1, 3, 4, 5, 6, 8]
        )
        let closed = try BookmarkEditorRouting.deleteLines(
            in: 3...5, in: closedSnapshot, expected: closedExpectation
        )
        XCTAssertEqual(closed.bookmarks.lines, [1, 3, 5])
        XCTAssertEqual(closed.lineCount, 7)
    }

    func testDeleteLinesRejectsInvalidRangesAndCounts() throws {
        let (snapshot, expected) = try makeSnapshot(lineCount: 10, bookmarkLines: [2, 5])

        assertRoutingError(
            .core(.invalidLineCount(-1)),
            try BookmarkEditorRouting.insertLines(at: 2, count: -1, in: snapshot, expected: expected)
        )
        assertRoutingError(
            .core(.invalidLineRange(lowerBound: 0, upperBound: 2)),
            try BookmarkEditorRouting.deleteLines(in: 0..<2, in: snapshot, expected: expected)
        )
        assertRoutingError(
            .core(.invalidLineRange(lowerBound: 0, upperBound: 2)),
            try BookmarkEditorRouting.deleteLines(in: 0...2, in: snapshot, expected: expected)
        )
        assertRoutingError(
            .core(.invalidLineRange(lowerBound: 9, upperBound: 20)),
            try BookmarkEditorRouting.deleteLines(in: 9..<20, in: snapshot, expected: expected)
        )
        assertRoutingError(
            .core(.invalidLineRange(lowerBound: 9, upperBound: 20)),
            try BookmarkEditorRouting.deleteLines(in: 9...20, in: snapshot, expected: expected)
        )
    }

    func testStaleGenerationAndIdentityAreRejectedOnEveryEntry() throws {
        let (snapshot, _) = try makeSnapshot(lineCount: 10, bookmarkLines: [2, 5])
        let stale = BookmarkEditorExpectation(
            documentID: snapshot.documentID, generation: snapshot.generation + 1
        )
        let foreign = BookmarkEditorExpectation(documentID: UUID(), generation: snapshot.generation)

        let calls: [(String, (BookmarkEditorExpectation) throws -> Void)] = [
            ("toggle", { _ = try BookmarkEditorRouting.toggle(line: 2, in: snapshot, expected: $0) }),
            ("next", { _ = try BookmarkEditorRouting.next(from: 2, in: snapshot, expected: $0) }),
            (
                "previous",
                { _ = try BookmarkEditorRouting.previous(before: 5, in: snapshot, expected: $0) }
            ),
            ("clearAll", { _ = try BookmarkEditorRouting.clearAll(in: snapshot, expected: $0) }),
            (
                "insertLines",
                { _ = try BookmarkEditorRouting.insertLines(at: 3, count: 1, in: snapshot, expected: $0) }
            ),
            (
                "deleteRange",
                { _ = try BookmarkEditorRouting.deleteLines(in: 3..<5, in: snapshot, expected: $0) }
            ),
            (
                "deleteClosedRange",
                { _ = try BookmarkEditorRouting.deleteLines(in: 3...5, in: snapshot, expected: $0) }
            )
        ]
        for (name, call) in calls {
            assertRoutingError(
                .documentGenerationChanged(
                    expected: stale.generation, actual: snapshot.generation
                ),
                try call(stale),
                name
            )
            assertRoutingError(
                .documentIdentityChanged(expected: foreign.documentID, actual: snapshot.documentID),
                try call(foreign),
                name
            )
        }
    }

    func testLimitsAndOverflowBoundsAreEnforced() throws {
        let invalidLimits = [
            BookmarkEditorRoutingLimits(maximumBookmarks: -1),
            BookmarkEditorRoutingLimits(maximumLineCount: 0),
            BookmarkEditorRoutingLimits(maximumWork: -1)
        ]
        for limits in invalidLimits {
            let snapshot = try makeSnapshot().snapshot
            assertRoutingError(
                .invalidLimits,
                try BookmarkEditorRouting.toggle(line: 1, in: snapshot, expected: expectation(for: snapshot), limits: limits)
            )
        }

        let tight = BookmarkEditorRoutingLimits(
            maximumBookmarks: 100, maximumLineCount: 10, maximumWork: 1_000
        )
        let emptyLineCount = try makeSnapshot(lineCount: 0).snapshot
        assertRoutingError(
            .lineCountExceedsLimit(maximumLineCount: tight.maximumLineCount),
            try BookmarkEditorRouting.toggle(
                line: 1,
                in: emptyLineCount,
                expected: expectation(for: emptyLineCount),
                limits: tight
            )
        )
        let overLineCount = try makeSnapshot(lineCount: 11, bookmarkLines: []).snapshot
        assertRoutingError(
            .lineCountExceedsLimit(maximumLineCount: tight.maximumLineCount),
            try BookmarkEditorRouting.toggle(
                line: 1,
                in: overLineCount,
                expected: expectation(for: overLineCount),
                limits: tight
            )
        )

        let crowded = try makeSnapshot(lineCount: 10, bookmarkLines: [1, 2]).snapshot
        let fewBookmarks = BookmarkEditorRoutingLimits(
            maximumBookmarks: 1, maximumLineCount: 10, maximumWork: 1_000
        )
        assertRoutingError(
            .tooManyBookmarks(maximumBookmarks: 1),
            try BookmarkEditorRouting.toggle(
                line: 1,
                in: crowded,
                expected: expectation(for: crowded),
                limits: fewBookmarks
            )
        )

        let littleWork = BookmarkEditorRoutingLimits(
            maximumBookmarks: 100, maximumLineCount: 10, maximumWork: 3
        )
        assertRoutingError(
            .workLimitExceeded(maximumWork: 3),
            try BookmarkEditorRouting.toggle(
                line: 1,
                in: crowded,
                expected: expectation(for: crowded),
                limits: littleWork
            )
        )

        let dangling = try makeSnapshot(lineCount: 4, bookmarkLines: [5]).snapshot
        assertRoutingError(
            .bookmarkOutsideDocument(line: 5, lineCount: 4),
            try BookmarkEditorRouting.toggle(
                line: 1, in: dangling, expected: expectation(for: dangling)
            )
        )

        let full = try makeSnapshot(lineCount: 10, bookmarkLines: [2]).snapshot
        assertRoutingError(
            .lineCountExceedsLimit(maximumLineCount: tight.maximumLineCount),
            try BookmarkEditorRouting.insertLines(
                at: 10, count: 1, in: full, expected: expectation(for: full), limits: tight
            )
        )

        let unbounded = BookmarkEditorRoutingLimits(
            maximumBookmarks: .max, maximumLineCount: .max, maximumWork: .max
        )
        let huge = BookmarkEditorDocumentSnapshot(
            documentID: UUID(), generation: 7, lineCount: .max, bookmarks: LineBookmarks()
        )
        assertRoutingError(
            .lineCountExceedsLimit(maximumLineCount: .max),
            try BookmarkEditorRouting.insertLines(
                at: 1, count: 1, in: huge, expected: expectation(for: huge), limits: unbounded
            )
        )
    }

    func testCancellationThrowsForToggleAndClear() async throws {
        let (snapshot, expected) = try makeSnapshot(lineCount: 10, bookmarkLines: [2, 5])

        try await assertCancelled { _ = try BookmarkEditorRouting.toggle(line: 2, in: snapshot, expected: expected) }
        try await assertCancelled { _ = try BookmarkEditorRouting.clearAll(in: snapshot, expected: expected) }

        let applied = try BookmarkEditorRouting.toggle(line: 3, in: snapshot, expected: expected)
        XCTAssertTrue(applied.isBookmarked)
    }

    private func makeSnapshot(
        lineCount: Int = 10,
        bookmarkLines: [Int] = [],
        documentID: UUID? = nil,
        generation: UInt64 = 7
    ) throws -> (snapshot: BookmarkEditorDocumentSnapshot, expected: BookmarkEditorExpectation) {
        let resolvedID = documentID ?? UUID()
        let snapshot = BookmarkEditorDocumentSnapshot(
            documentID: resolvedID,
            generation: generation,
            lineCount: lineCount,
            bookmarks: try LineBookmarks(lines: bookmarkLines)
        )
        return (snapshot, BookmarkEditorExpectation(snapshot: snapshot))
    }

    private func expectation(for snapshot: BookmarkEditorDocumentSnapshot) -> BookmarkEditorExpectation {
        BookmarkEditorExpectation(snapshot: snapshot)
    }

    private func assertRoutingError<T>(
        _ expected: BookmarkEditorRoutingError,
        _ expression: @autoclosure () throws -> T,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), message, file: file, line: line) { error in
            XCTAssertEqual(error as? BookmarkEditorRoutingError, expected, file: file, line: line)
        }
    }

    private func assertCancelled(
        _ operation: @escaping @Sendable () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in stream { break }
                    try operation()
                }
                group.cancelAll()
                continuation.yield()
                try await group.waitForAll()
            }
            XCTFail("Expected CancellationError", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)", file: file, line: line)
        }
    }
}
