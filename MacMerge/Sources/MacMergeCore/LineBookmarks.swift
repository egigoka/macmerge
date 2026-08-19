import Foundation

public enum LineBookmarkNavigationDirection: String, Codable, Equatable, Sendable {
    case next
    case previous
}

public enum LineBookmarkWrapPolicy: String, Codable, Equatable, Sendable {
    case wrap
    case noWrap
}

public struct LineBookmarkNavigationResult: Equatable, Sendable {
    public let line: Int
    public let didWrap: Bool

    public init(line: Int, didWrap: Bool) {
        self.line = line
        self.didWrap = didWrap
    }
}

public enum LineBookmarksError: Error, LocalizedError, Equatable, Sendable {
    case invalidLine(Int)
    case invalidLineCount(Int)
    case invalidLineRange(lowerBound: Int, upperBound: Int)
    case lineNumberOverflow

    public var errorDescription: String? {
        switch self {
        case .invalidLine(let line):
            "Line number must be positive: \(line)."
        case .invalidLineCount(let count):
            "Line count must not be negative: \(count)."
        case .invalidLineRange(let lowerBound, let upperBound):
            "Line range \(lowerBound)..<\(upperBound) is invalid."
        case .lineNumberOverflow:
            "Line edit exceeds the supported line-number range."
        }
    }
}

/// A set of bookmarks using the same one-based line numbers displayed by a comparison.
public struct LineBookmarks: Codable, Equatable, Sendable {
    private var storage: Set<Int>

    public var lines: [Int] { storage.sorted() }
    public var bookmarkedLines: Set<Int> { storage }
    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public init() {
        storage = []
    }

    public init<S: Sequence>(lines: S) throws where S.Element == Int {
        var storage: Set<Int> = []
        for line in lines {
            try Self.validate(line: line)
            storage.insert(line)
        }
        self.storage = storage
    }

    public func contains(line: Int) -> Bool {
        guard line > 0 else { return false }
        return storage.contains(line)
    }

    /// Returns `true` when the line is bookmarked after the operation.
    @discardableResult
    public mutating func toggle(line: Int) throws -> Bool {
        try Self.validate(line: line)
        if storage.remove(line) != nil {
            return false
        }
        storage.insert(line)
        return true
    }

    /// Returns whether any bookmarks were removed.
    @discardableResult
    public mutating func clear() -> Bool {
        guard !storage.isEmpty else { return false }
        storage.removeAll(keepingCapacity: true)
        return true
    }

    public func navigate(
        from line: Int,
        direction: LineBookmarkNavigationDirection,
        wrapPolicy: LineBookmarkWrapPolicy = .wrap
    ) throws -> LineBookmarkNavigationResult? {
        try Self.validate(line: line)
        let sortedLines = lines
        guard !sortedLines.isEmpty else { return nil }

        let index = Self.insertionIndex(for: line, in: sortedLines)
        switch direction {
        case .next:
            let nextIndex = index < sortedLines.count && sortedLines[index] == line ? index + 1 : index
            if nextIndex < sortedLines.count {
                return LineBookmarkNavigationResult(line: sortedLines[nextIndex], didWrap: false)
            }
            guard wrapPolicy == .wrap else { return nil }
            return LineBookmarkNavigationResult(line: sortedLines[0], didWrap: true)
        case .previous:
            if index > 0 {
                return LineBookmarkNavigationResult(line: sortedLines[index - 1], didWrap: false)
            }
            guard wrapPolicy == .wrap else { return nil }
            return LineBookmarkNavigationResult(line: sortedLines[sortedLines.count - 1], didWrap: true)
        }
    }

    public func next(
        after line: Int,
        wrapPolicy: LineBookmarkWrapPolicy = .wrap
    ) throws -> LineBookmarkNavigationResult? {
        try navigate(from: line, direction: .next, wrapPolicy: wrapPolicy)
    }

    public func previous(
        before line: Int,
        wrapPolicy: LineBookmarkWrapPolicy = .wrap
    ) throws -> LineBookmarkNavigationResult? {
        try navigate(from: line, direction: .previous, wrapPolicy: wrapPolicy)
    }

    public func next(after line: Int, wrap: Bool) throws -> LineBookmarkNavigationResult? {
        try next(after: line, wrapPolicy: wrap ? .wrap : .noWrap)
    }

    public func previous(before line: Int, wrap: Bool) throws -> LineBookmarkNavigationResult? {
        try previous(before: line, wrapPolicy: wrap ? .wrap : .noWrap)
    }

    /// Remaps bookmarks after `count` lines are inserted before `line`.
    public mutating func insertLines(at line: Int, count: Int) throws {
        try Self.validate(line: line)
        guard count >= 0 else { throw LineBookmarksError.invalidLineCount(count) }
        guard count > 0 else { return }
        guard !line.addingReportingOverflow(count - 1).overflow else {
            throw LineBookmarksError.lineNumberOverflow
        }

        for bookmarkedLine in storage where bookmarkedLine >= line {
            guard !bookmarkedLine.addingReportingOverflow(count).overflow else {
                throw LineBookmarksError.lineNumberOverflow
            }
        }
        storage = Set(storage.map { $0 >= line ? $0 + count : $0 })
    }

    /// Removes bookmarks in the half-open range and shifts following bookmarks upward.
    public mutating func deleteLines(in range: Range<Int>) throws {
        guard range.lowerBound > 0, range.upperBound >= range.lowerBound else {
            throw LineBookmarksError.invalidLineRange(
                lowerBound: range.lowerBound,
                upperBound: range.upperBound
            )
        }
        guard !range.isEmpty else { return }

        let deletedCount = range.upperBound - range.lowerBound
        storage = Set(
            storage.compactMap { line in
                if range.contains(line) { return nil }
                return line >= range.upperBound ? line - deletedCount : line
            }
        )
    }

    /// Removes bookmarks in the closed range and shifts following bookmarks upward.
    public mutating func deleteLines(in range: ClosedRange<Int>) throws {
        guard range.lowerBound > 0, range.upperBound >= range.lowerBound else {
            throw LineBookmarksError.invalidLineRange(
                lowerBound: range.lowerBound,
                upperBound: range.upperBound
            )
        }

        let deletedCount = range.upperBound - range.lowerBound + 1
        storage = Set(
            storage.compactMap { line in
                if range.contains(line) { return nil }
                return line > range.upperBound ? line - deletedCount : line
            }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedLines = try container.decode([Int].self, forKey: .lines)
        do {
            try self.init(lines: decodedLines)
        } catch let error as LineBookmarksError {
            throw DecodingError.dataCorruptedError(
                forKey: .lines,
                in: container,
                debugDescription: error.localizedDescription
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lines, forKey: .lines)
    }

    private static func validate(line: Int) throws {
        guard line > 0 else { throw LineBookmarksError.invalidLine(line) }
    }

    private static func insertionIndex(for line: Int, in lines: [Int]) -> Int {
        var lowerBound = 0
        var upperBound = lines.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if lines[middle] < line {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }
}
