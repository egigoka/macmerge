import Foundation

/// UI-independent routing from editor/menu bookmark commands to the ``LineBookmarks`` core.
///
/// Planning only: validates caller-supplied document identity/generation (stale-generation
/// check), enforces bounded limits, delegates line validation, navigation, and edit remapping
/// to ``LineBookmarks``, and returns values the owner applies. This file never touches an
/// editor, pane, menu, or dialog; selection, scrolling, focus, and persistence remain with
/// the future editor executor. The owner advances `generation` whenever text or bookmarks
/// change; routing only checks equality and never assigns new tokens.
public enum BookmarkEditorRouting: Sendable {
    public static func toggle(
        line: Int,
        in snapshot: BookmarkEditorDocumentSnapshot,
        expected: BookmarkEditorExpectation,
        limits: BookmarkEditorRoutingLimits = .default
    ) throws -> BookmarkEditorToggleOutcome {
        try Task.checkCancellation()
        try validate(snapshot, expected: expected, limits: limits)
        guard line >= 1, line <= snapshot.lineCount else {
            throw BookmarkEditorRoutingError.lineOutOfRange(line: line, lineCount: snapshot.lineCount)
        }
        try Task.checkCancellation()
        var bookmarks = snapshot.bookmarks
        let isBookmarked: Bool
        do {
            isBookmarked = try bookmarks.toggle(line: line)
        } catch let error as LineBookmarksError {
            throw BookmarkEditorRoutingError.core(error)
        }
        try Task.checkCancellation()
        return BookmarkEditorToggleOutcome(bookmarks: bookmarks, isBookmarked: isBookmarked, line: line)
    }

    public static func next(
        from line: Int,
        in snapshot: BookmarkEditorDocumentSnapshot,
        expected: BookmarkEditorExpectation,
        wrapPolicy: LineBookmarkWrapPolicy = .wrap,
        limits: BookmarkEditorRoutingLimits = .default
    ) throws -> LineBookmarkNavigationResult? {
        try Task.checkCancellation()
        try validate(snapshot, expected: expected, limits: limits)
        guard line >= 1, line <= snapshot.lineCount else {
            throw BookmarkEditorRoutingError.lineOutOfRange(line: line, lineCount: snapshot.lineCount)
        }
        try Task.checkCancellation()
        do {
            return try snapshot.bookmarks.navigate(from: line, direction: .next, wrapPolicy: wrapPolicy)
        } catch let error as LineBookmarksError {
            throw BookmarkEditorRoutingError.core(error)
        }
    }

    public static func previous(
        before line: Int,
        in snapshot: BookmarkEditorDocumentSnapshot,
        expected: BookmarkEditorExpectation,
        wrapPolicy: LineBookmarkWrapPolicy = .wrap,
        limits: BookmarkEditorRoutingLimits = .default
    ) throws -> LineBookmarkNavigationResult? {
        try Task.checkCancellation()
        try validate(snapshot, expected: expected, limits: limits)
        guard line >= 1, line <= snapshot.lineCount else {
            throw BookmarkEditorRoutingError.lineOutOfRange(line: line, lineCount: snapshot.lineCount)
        }
        try Task.checkCancellation()
        do {
            return try snapshot.bookmarks.navigate(from: line, direction: .previous, wrapPolicy: wrapPolicy)
        } catch let error as LineBookmarksError {
            throw BookmarkEditorRoutingError.core(error)
        }
    }

    public static func clearAll(
        in snapshot: BookmarkEditorDocumentSnapshot,
        expected: BookmarkEditorExpectation,
        limits: BookmarkEditorRoutingLimits = .default
    ) throws -> BookmarkEditorClearOutcome {
        try Task.checkCancellation()
        try validate(snapshot, expected: expected, limits: limits)
        try Task.checkCancellation()
        var bookmarks = snapshot.bookmarks
        let didClear = bookmarks.clear()
        return BookmarkEditorClearOutcome(bookmarks: bookmarks, didClear: didClear)
    }

    public static func insertLines(
        at line: Int,
        count: Int,
        in snapshot: BookmarkEditorDocumentSnapshot,
        expected: BookmarkEditorExpectation,
        limits: BookmarkEditorRoutingLimits = .default
    ) throws -> BookmarkEditorEditOutcome {
        try Task.checkCancellation()
        try validate(snapshot, expected: expected, limits: limits)
        guard line >= 1, (line - 1) <= snapshot.lineCount else {
            throw BookmarkEditorRoutingError.lineOutOfRange(line: line, lineCount: snapshot.lineCount)
        }
        guard count >= 0 else {
            throw BookmarkEditorRoutingError.core(.invalidLineCount(count))
        }
        let (lineCount, overflow) = snapshot.lineCount.addingReportingOverflow(count)
        guard !overflow, lineCount <= limits.maximumLineCount else {
            throw BookmarkEditorRoutingError.lineCountExceedsLimit(maximumLineCount: limits.maximumLineCount)
        }
        try Task.checkCancellation()
        var bookmarks = snapshot.bookmarks
        do {
            try bookmarks.insertLines(at: line, count: count)
        } catch let error as LineBookmarksError {
            throw BookmarkEditorRoutingError.core(error)
        }
        try Task.checkCancellation()
        return BookmarkEditorEditOutcome(bookmarks: bookmarks, lineCount: lineCount)
    }

    public static func deleteLines(
        in range: Range<Int>,
        in snapshot: BookmarkEditorDocumentSnapshot,
        expected: BookmarkEditorExpectation,
        limits: BookmarkEditorRoutingLimits = .default
    ) throws -> BookmarkEditorEditOutcome {
        try Task.checkCancellation()
        try validate(snapshot, expected: expected, limits: limits)
        guard range.lowerBound >= 1, range.upperBound >= range.lowerBound, (range.upperBound - 1) <= snapshot.lineCount else {
            throw BookmarkEditorRoutingError.core(.invalidLineRange(lowerBound: range.lowerBound, upperBound: range.upperBound))
        }
        try Task.checkCancellation()
        var bookmarks = snapshot.bookmarks
        do {
            try bookmarks.deleteLines(in: range)
        } catch let error as LineBookmarksError {
            throw BookmarkEditorRoutingError.core(error)
        }
        try Task.checkCancellation()
        return BookmarkEditorEditOutcome(bookmarks: bookmarks, lineCount: snapshot.lineCount - (range.upperBound - range.lowerBound))
    }

    public static func deleteLines(
        in range: ClosedRange<Int>,
        in snapshot: BookmarkEditorDocumentSnapshot,
        expected: BookmarkEditorExpectation,
        limits: BookmarkEditorRoutingLimits = .default
    ) throws -> BookmarkEditorEditOutcome {
        try Task.checkCancellation()
        try validate(snapshot, expected: expected, limits: limits)
        guard range.lowerBound >= 1, range.lowerBound <= range.upperBound, range.upperBound <= snapshot.lineCount else {
            throw BookmarkEditorRoutingError.core(.invalidLineRange(lowerBound: range.lowerBound, upperBound: range.upperBound))
        }
        try Task.checkCancellation()
        var bookmarks = snapshot.bookmarks
        do {
            try bookmarks.deleteLines(in: range)
        } catch let error as LineBookmarksError {
            throw BookmarkEditorRoutingError.core(error)
        }
        try Task.checkCancellation()
        return BookmarkEditorEditOutcome(bookmarks: bookmarks, lineCount: snapshot.lineCount - (range.upperBound - range.lowerBound + 1))
    }

    private static func validate(
        _ snapshot: BookmarkEditorDocumentSnapshot,
        expected: BookmarkEditorExpectation,
        limits: BookmarkEditorRoutingLimits
    ) throws {
        try limits.validate()
        guard expected.documentID == snapshot.documentID else {
            throw BookmarkEditorRoutingError.documentIdentityChanged(expected: expected.documentID, actual: snapshot.documentID)
        }
        guard expected.generation == snapshot.generation else {
            throw BookmarkEditorRoutingError.documentGenerationChanged(expected: expected.generation, actual: snapshot.generation)
        }
        guard snapshot.lineCount >= 1, snapshot.lineCount <= limits.maximumLineCount else {
            throw BookmarkEditorRoutingError.lineCountExceedsLimit(maximumLineCount: limits.maximumLineCount)
        }
        guard snapshot.bookmarks.count <= limits.maximumBookmarks else {
            throw BookmarkEditorRoutingError.tooManyBookmarks(maximumBookmarks: limits.maximumBookmarks)
        }
        let (work, overflow) = snapshot.bookmarks.count.addingReportingOverflow(snapshot.lineCount)
        guard !overflow, work <= limits.maximumWork else {
            throw BookmarkEditorRoutingError.workLimitExceeded(maximumWork: limits.maximumWork)
        }
        for line in snapshot.bookmarks.bookmarkedLines {
            guard line >= 1, line <= snapshot.lineCount else {
                throw BookmarkEditorRoutingError.bookmarkOutsideDocument(line: line, lineCount: snapshot.lineCount)
            }
        }
    }
}

/// Immutable editor state used to plan one bookmark request.
/// For one `documentID`, the owner uses `generation` as an opaque, never-reused token and
/// advances it whenever text or bookmarks change; caret moves alone need no new token.
public struct BookmarkEditorDocumentSnapshot: Equatable, Sendable {
    public let documentID: UUID
    public let generation: UInt64
    public let lineCount: Int
    public let bookmarks: LineBookmarks

    public init(documentID: UUID, generation: UInt64, lineCount: Int, bookmarks: LineBookmarks = LineBookmarks()) {
        self.documentID = documentID
        self.generation = generation
        self.lineCount = lineCount
        self.bookmarks = bookmarks
    }
}

/// Identity/generation pair a command captured at enablement time.
/// Routing rejects the command when it no longer matches the current snapshot.
public struct BookmarkEditorExpectation: Equatable, Sendable {
    public let documentID: UUID
    public let generation: UInt64

    public init(documentID: UUID, generation: UInt64) {
        self.documentID = documentID
        self.generation = generation
    }

    public init(snapshot: BookmarkEditorDocumentSnapshot) {
        documentID = snapshot.documentID
        generation = snapshot.generation
    }
}

/// Bounds for every pass behind bookmark routing. The core keeps its own overflow checks.
public struct BookmarkEditorRoutingLimits: Equatable, Sendable {
    public static let `default` = BookmarkEditorRoutingLimits()

    public let maximumBookmarks: Int
    public let maximumLineCount: Int
    public let maximumWork: Int

    public init(maximumBookmarks: Int = 100_000, maximumLineCount: Int = 1_048_576, maximumWork: Int = 8_388_608) {
        self.maximumBookmarks = maximumBookmarks
        self.maximumLineCount = maximumLineCount
        self.maximumWork = maximumWork
    }

    public func validate() throws {
        guard maximumBookmarks >= 0, maximumLineCount > 0, maximumWork >= 0 else {
            throw BookmarkEditorRoutingError.invalidLimits
        }
    }
}

/// Toggle result. The owner stores `bookmarks` under a new generation.
public struct BookmarkEditorToggleOutcome: Equatable, Sendable {
    public let bookmarks: LineBookmarks
    public let isBookmarked: Bool
    public let line: Int

    public init(bookmarks: LineBookmarks, isBookmarked: Bool, line: Int) {
        self.bookmarks = bookmarks
        self.isBookmarked = isBookmarked
        self.line = line
    }
}

/// Clear-all result. The owner stores `bookmarks` under a new generation when `didClear`.
public struct BookmarkEditorClearOutcome: Equatable, Sendable {
    public let bookmarks: LineBookmarks
    public let didClear: Bool

    public init(bookmarks: LineBookmarks, didClear: Bool) {
        self.bookmarks = bookmarks
        self.didClear = didClear
    }
}

/// Edit-remap result. The owner stores `bookmarks` with `lineCount` under a new generation.
public struct BookmarkEditorEditOutcome: Equatable, Sendable {
    public let bookmarks: LineBookmarks
    public let lineCount: Int

    public init(bookmarks: LineBookmarks, lineCount: Int) {
        self.bookmarks = bookmarks
        self.lineCount = lineCount
    }
}

public enum BookmarkEditorRoutingError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case documentIdentityChanged(expected: UUID, actual: UUID)
    case documentGenerationChanged(expected: UInt64, actual: UInt64)
    case lineCountExceedsLimit(maximumLineCount: Int)
    case tooManyBookmarks(maximumBookmarks: Int)
    case workLimitExceeded(maximumWork: Int)
    case lineOutOfRange(line: Int, lineCount: Int)
    case bookmarkOutsideDocument(line: Int, lineCount: Int)
    case core(LineBookmarksError)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Bookmark editor routing limits are invalid."
        case .documentIdentityChanged:
            "The bookmark request belongs to another document."
        case .documentGenerationChanged(let expected, let actual):
            "Bookmarks were planned for generation \(expected), not generation \(actual)."
        case .lineCountExceedsLimit(let maximumLineCount):
            "Bookmark line count exceeds the \(maximumLineCount)-line limit."
        case .tooManyBookmarks(let maximumBookmarks):
            "Bookmark metadata exceeds the \(maximumBookmarks)-bookmark limit."
        case .workLimitExceeded(let maximumWork):
            "Bookmark routing exceeds the \(maximumWork)-unit work limit."
        case .lineOutOfRange(let line, let lineCount):
            "Bookmark line \(line) is outside 1...\(lineCount)."
        case .bookmarkOutsideDocument(let line, let lineCount):
            "Stored bookmark \(line) is outside 1...\(lineCount)."
        case .core(let error):
            error.localizedDescription
        }
    }
}
