import Foundation
import XCTest

@testable import MacMergeCore

final class LineBookmarksTests: XCTestCase {
    func testToggleClearAndSortedSnapshotsAreDeterministic() throws {
        var bookmarks = LineBookmarks()

        XCTAssertTrue(bookmarks.isEmpty)
        XCTAssertEqual(bookmarks.count, 0)
        XCTAssertEqual(bookmarks.lines, [])
        XCTAssertFalse(bookmarks.contains(line: 0))
        XCTAssertFalse(bookmarks.clear())

        XCTAssertTrue(try bookmarks.toggle(line: 9))
        XCTAssertTrue(try bookmarks.toggle(line: 1))
        XCTAssertTrue(try bookmarks.toggle(line: 5))
        XCTAssertEqual(bookmarks.lines, [1, 5, 9])
        XCTAssertEqual(bookmarks.bookmarkedLines, [1, 5, 9])
        XCTAssertEqual(bookmarks.count, 3)
        XCTAssertTrue(bookmarks.contains(line: 5))

        XCTAssertFalse(try bookmarks.toggle(line: 5))
        XCTAssertEqual(bookmarks.lines, [1, 9])
        XCTAssertFalse(bookmarks.contains(line: 5))
        XCTAssertTrue(bookmarks.clear())
        XCTAssertTrue(bookmarks.isEmpty)
        XCTAssertFalse(bookmarks.clear())

        let forward = try LineBookmarks(lines: [1, 5, 9, 5])
        let reverse = try LineBookmarks(lines: [9, 5, 1, 9])
        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.lines, [1, 5, 9])
    }

    func testNextNavigationCoversExactBetweenAndOuterBoundaries() throws {
        let bookmarks = try LineBookmarks(lines: [2, 5, 9])

        XCTAssertEqual(
            try bookmarks.next(after: 1),
            LineBookmarkNavigationResult(line: 2, didWrap: false)
        )
        XCTAssertEqual(
            try bookmarks.next(after: 2),
            LineBookmarkNavigationResult(line: 5, didWrap: false)
        )
        XCTAssertEqual(
            try bookmarks.next(after: 6),
            LineBookmarkNavigationResult(line: 9, didWrap: false)
        )
        XCTAssertEqual(
            try bookmarks.next(after: 9),
            LineBookmarkNavigationResult(line: 2, didWrap: true)
        )
        XCTAssertEqual(
            try bookmarks.next(after: Int.max),
            LineBookmarkNavigationResult(line: 2, didWrap: true)
        )
        XCTAssertNil(try bookmarks.next(after: 9, wrapPolicy: .noWrap))
        XCTAssertNil(try bookmarks.next(after: Int.max, wrap: false))
    }

    func testPreviousNavigationCoversExactBetweenAndOuterBoundaries() throws {
        let bookmarks = try LineBookmarks(lines: [2, 5, 9])

        XCTAssertEqual(
            try bookmarks.previous(before: 10),
            LineBookmarkNavigationResult(line: 9, didWrap: false)
        )
        XCTAssertEqual(
            try bookmarks.previous(before: 9),
            LineBookmarkNavigationResult(line: 5, didWrap: false)
        )
        XCTAssertEqual(
            try bookmarks.previous(before: 6),
            LineBookmarkNavigationResult(line: 5, didWrap: false)
        )
        XCTAssertEqual(
            try bookmarks.previous(before: 2),
            LineBookmarkNavigationResult(line: 9, didWrap: true)
        )
        XCTAssertEqual(
            try bookmarks.previous(before: 1),
            LineBookmarkNavigationResult(line: 9, didWrap: true)
        )
        XCTAssertNil(try bookmarks.previous(before: 2, wrapPolicy: .noWrap))
        XCTAssertNil(try bookmarks.previous(before: 1, wrap: false))
    }

    func testNavigationHandlesEmptyAndSingleBookmarkSets() throws {
        let empty = LineBookmarks()
        XCTAssertNil(try empty.navigate(from: 1, direction: .next))
        XCTAssertNil(try empty.navigate(from: Int.max, direction: .previous, wrapPolicy: .noWrap))

        let single = try LineBookmarks(lines: [4])
        XCTAssertEqual(
            try single.navigate(from: 4, direction: .next),
            LineBookmarkNavigationResult(line: 4, didWrap: true)
        )
        XCTAssertEqual(
            try single.navigate(from: 4, direction: .previous),
            LineBookmarkNavigationResult(line: 4, didWrap: true)
        )
        XCTAssertNil(try single.navigate(from: 4, direction: .next, wrapPolicy: .noWrap))
        XCTAssertNil(try single.navigate(from: 4, direction: .previous, wrapPolicy: .noWrap))
    }

    func testInsertionRemapsBookmarksBeforeAtAndAfterEveryBoundary() throws {
        var beforeAll = try LineBookmarks(lines: [1, 3, 5])
        try beforeAll.insertLines(at: 1, count: 2)
        XCTAssertEqual(beforeAll.lines, [3, 5, 7])

        var throughMiddle = try LineBookmarks(lines: [1, 3, 5])
        try throughMiddle.insertLines(at: 3, count: 2)
        XCTAssertEqual(throughMiddle.lines, [1, 5, 7])

        var afterAll = try LineBookmarks(lines: [1, 3, 5])
        try afterAll.insertLines(at: 6, count: 2)
        XCTAssertEqual(afterAll.lines, [1, 3, 5])

        var maximumBoundary = try LineBookmarks(lines: [Int.max - 1])
        try maximumBoundary.insertLines(at: Int.max, count: 1)
        XCTAssertEqual(maximumBoundary.lines, [Int.max - 1])

        var maximumRemap = try LineBookmarks(lines: [Int.max - 1])
        try maximumRemap.insertLines(at: Int.max - 1, count: 1)
        XCTAssertEqual(maximumRemap.lines, [Int.max])
    }

    func testHalfOpenDeletionRemapsEveryEdgePosition() throws {
        var bookmarks = try LineBookmarks(lines: [1, 3, 4, 5, 7])

        try bookmarks.deleteLines(in: 3..<5)

        XCTAssertEqual(bookmarks.lines, [1, 3, 5])

        var firstLine = try LineBookmarks(lines: [1, 2, 4])
        try firstLine.deleteLines(in: 1..<2)
        XCTAssertEqual(firstLine.lines, [1, 3])

        var afterAll = try LineBookmarks(lines: [1, 3])
        try afterAll.deleteLines(in: 4..<7)
        XCTAssertEqual(afterAll.lines, [1, 3])
    }

    func testClosedDeletionRemapsEveryEdgePosition() throws {
        var bookmarks = try LineBookmarks(lines: [1, 3, 4, 5, 6, 8])

        try bookmarks.deleteLines(in: 3...5)

        XCTAssertEqual(bookmarks.lines, [1, 3, 5])

        var firstLine = try LineBookmarks(lines: [1, 2, 4])
        try firstLine.deleteLines(in: 1...1)
        XCTAssertEqual(firstLine.lines, [1, 3])

        var maximumBoundary = try LineBookmarks(lines: [Int.max - 1, Int.max])
        try maximumBoundary.deleteLines(in: Int.max...Int.max)
        XCTAssertEqual(maximumBoundary.lines, [Int.max - 1])
    }

    func testZeroInsertionAndEmptyDeletionAreNoOps() throws {
        let original = try LineBookmarks(lines: [1, 4, Int.max])
        var bookmarks = original

        try bookmarks.insertLines(at: Int.max, count: 0)
        try bookmarks.deleteLines(in: 2..<2)

        XCTAssertEqual(bookmarks, original)
    }

    func testInvalidLinesAreRejectedWithoutMutation() throws {
        for line in [Int.min, -1, 0] {
            assertBookmarkError(.invalidLine(line), try LineBookmarks(lines: [2, line, 4]))
        }

        var bookmarks = try LineBookmarks(lines: [2, 4])
        for line in [Int.min, -1, 0] {
            let original = bookmarks
            assertBookmarkError(.invalidLine(line), try bookmarks.toggle(line: line))
            XCTAssertEqual(bookmarks, original)

            assertBookmarkError(.invalidLine(line), try bookmarks.next(after: line))
            XCTAssertEqual(bookmarks, original)

            assertBookmarkError(.invalidLine(line), try bookmarks.previous(before: line))
            XCTAssertEqual(bookmarks, original)
        }
    }

    func testInvalidInsertionCountAndOverflowAreAtomic() throws {
        var bookmarks = try LineBookmarks(lines: [2, 4, Int.max])

        assertMutationError(.invalidLine(0), bookmarks: &bookmarks) {
            try $0.insertLines(at: 0, count: 1)
        }
        assertMutationError(.invalidLineCount(-1), bookmarks: &bookmarks) {
            try $0.insertLines(at: 2, count: -1)
        }
        assertMutationError(.invalidLineCount(Int.min), bookmarks: &bookmarks) {
            try $0.insertLines(at: 2, count: Int.min)
        }
        assertMutationError(.lineNumberOverflow, bookmarks: &bookmarks) {
            try $0.insertLines(at: Int.max, count: 2)
        }
        assertMutationError(.lineNumberOverflow, bookmarks: &bookmarks) {
            try $0.insertLines(at: 1, count: Int.max)
        }
        assertMutationError(.lineNumberOverflow, bookmarks: &bookmarks) {
            try $0.insertLines(at: 2, count: 1)
        }
    }

    func testInvalidDeletionRangesAreAtomic() throws {
        var bookmarks = try LineBookmarks(lines: [1, 3, 5])

        assertMutationError(
            .invalidLineRange(lowerBound: -2, upperBound: 0),
            bookmarks: &bookmarks
        ) {
            try $0.deleteLines(in: -2..<0)
        }
        assertMutationError(
            .invalidLineRange(lowerBound: 0, upperBound: 2),
            bookmarks: &bookmarks
        ) {
            try $0.deleteLines(in: 0..<2)
        }
        assertMutationError(
            .invalidLineRange(lowerBound: 0, upperBound: 2),
            bookmarks: &bookmarks
        ) {
            try $0.deleteLines(in: 0...2)
        }
    }

    func testCodableCanonicalizesOrderAndDuplicates() throws {
        let ascending = try LineBookmarks(lines: [1, 5, 9])
        let shuffled = try LineBookmarks(lines: [9, 1, 5, 9, 1])
        let encoder = JSONEncoder()

        let ascendingData = try encoder.encode(ascending)
        let shuffledData = try encoder.encode(shuffled)
        XCTAssertEqual(ascendingData, shuffledData)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: shuffledData) as? [String: Any]
        )
        XCTAssertEqual(object["lines"] as? [Int], [1, 5, 9])

        let decoded = try JSONDecoder().decode(
            LineBookmarks.self,
            from: Data(#"{"lines":[9,1,5,9,1]}"#.utf8)
        )
        XCTAssertEqual(decoded, ascending)
        XCTAssertEqual(try encoder.encode(decoded), ascendingData)
    }

    func testCodableRoundTripsEmptyAndMaximumLine() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for bookmarks in [LineBookmarks(), try LineBookmarks(lines: [Int.max])] {
            XCTAssertEqual(
                try decoder.decode(LineBookmarks.self, from: encoder.encode(bookmarks)),
                bookmarks
            )
        }
    }

    func testDecoderRejectsHostilePayloads() {
        for payload in [
            #"{"lines":[1,0,2]}"#,
            #"{"lines":[-1]}"#,
            #"{"lines":[true]}"#,
            #"{"lines":[1.5]}"#,
            #"{"lines":[9223372036854775808]}"#,
            #"{"lines":null}"#,
            #"{"lines":"1"}"#,
            #"{"other":[1]}"#,
            #"[]"#
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(LineBookmarks.self, from: Data(payload.utf8)),
                "Payload unexpectedly decoded: \(payload)"
            )
        }
    }

    func testDecoderReportsInvalidLinesAtLinesKey() {
        let data = Data(#"{"lines":[1,0,2]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(LineBookmarks.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "lines")
            XCTAssertTrue(context.debugDescription.contains("Line number must be positive"))
        }
    }

    private func assertBookmarkError<T>(
        _ expected: LineBookmarksError,
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? LineBookmarksError, expected, file: file, line: line)
        }
    }

    private func assertMutationError(
        _ expected: LineBookmarksError,
        bookmarks: inout LineBookmarks,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: (inout LineBookmarks) throws -> Void
    ) {
        let original = bookmarks
        XCTAssertThrowsError(try operation(&bookmarks), file: file, line: line) { error in
            XCTAssertEqual(error as? LineBookmarksError, expected, file: file, line: line)
        }
        XCTAssertEqual(bookmarks, original, file: file, line: line)
    }
}
