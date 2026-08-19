import Foundation

public enum LineEnding: String, CaseIterable, Equatable, Hashable, Sendable {
    case crlf = "\r\n"
    case lf = "\n"
    case cr = "\r"

    public var displayName: String {
        switch self {
        case .crlf: "CRLF"
        case .lf: "LF"
        case .cr: "CR"
        }
    }
}

public struct LineEndingConversionResult: Equatable, Sendable {
    public let text: String
    public let lineCount: Int
    public let changedTerminatorCount: Int

    public var changed: Bool { changedTerminatorCount > 0 }

    public init(text: String, lineCount: Int, changedTerminatorCount: Int) {
        self.text = text
        self.lineCount = lineCount
        self.changedTerminatorCount = changedTerminatorCount
    }
}

public enum LineEndingConversionError: Error, LocalizedError, Equatable, Sendable {
    case invalidLineRange(requested: Range<Int>, lineCount: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLineRange(let requested, let lineCount):
            "Line range \(requested.lowerBound)..<\(requested.upperBound) is outside the document's \(lineCount) lines."
        }
    }
}

public enum LineEndingConversion: Sendable {
    /// Converts every CRLF, LF, or CR terminator without adding or removing a final terminator.
    public static func convert(
        _ text: String,
        to lineEnding: LineEnding
    ) -> LineEndingConversionResult {
        convertValidated(text, lines: nil, to: lineEnding, lineCount: lineCount(in: text))
    }

    /// Converts terminators belonging to a zero-based, half-open range of lines.
    /// Nonselected terminators and an unterminated final line remain unchanged.
    public static func convert(
        _ text: String,
        lines lineRange: Range<Int>,
        to lineEnding: LineEnding
    ) throws -> LineEndingConversionResult {
        let count = lineCount(in: text)
        guard lineRange.lowerBound >= 0,
            lineRange.upperBound >= lineRange.lowerBound,
            lineRange.upperBound <= count
        else {
            throw LineEndingConversionError.invalidLineRange(
                requested: lineRange,
                lineCount: count
            )
        }
        return convertValidated(text, lines: lineRange, to: lineEnding, lineCount: count)
    }

    public static func lineCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        var count = 0
        var hasUnterminatedContent = false
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar.value == 0x0D {
                let next = scalars.index(after: index)
                index =
                    next < scalars.endIndex && scalars[next].value == 0x0A
                    ? scalars.index(after: next)
                    : next
                count += 1
                hasUnterminatedContent = false
            } else if scalar.value == 0x0A {
                index = scalars.index(after: index)
                count += 1
                hasUnterminatedContent = false
            } else {
                index = scalars.index(after: index)
                hasUnterminatedContent = true
            }
        }
        return count + (hasUnterminatedContent ? 1 : 0)
    }

    private static func convertValidated(
        _ text: String,
        lines lineRange: Range<Int>?,
        to lineEnding: LineEnding,
        lineCount: Int
    ) -> LineEndingConversionResult {
        var converted = ""
        converted.reserveCapacity(text.utf8.count)

        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        var lineIndex = 0
        var changedTerminatorCount = 0
        while index < scalars.endIndex {
            let scalar = scalars[index]
            let sourceEnding: LineEnding
            let terminatorEnd: String.UnicodeScalarView.Index
            if scalar.value == 0x0D {
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next].value == 0x0A {
                    sourceEnding = .crlf
                    terminatorEnd = scalars.index(after: next)
                } else {
                    sourceEnding = .cr
                    terminatorEnd = next
                }
            } else if scalar.value == 0x0A {
                sourceEnding = .lf
                terminatorEnd = scalars.index(after: index)
            } else {
                converted.unicodeScalars.append(scalar)
                index = scalars.index(after: index)
                continue
            }

            if lineRange?.contains(lineIndex) != false {
                converted.append(lineEnding.rawValue)
                if sourceEnding != lineEnding {
                    changedTerminatorCount += 1
                }
            } else {
                converted.unicodeScalars.append(contentsOf: scalars[index..<terminatorEnd])
            }
            lineIndex += 1
            index = terminatorEnd
        }

        return LineEndingConversionResult(
            text: converted,
            lineCount: lineCount,
            changedTerminatorCount: changedTerminatorCount
        )
    }
}

extension TextFileDocument {
    @discardableResult
    public mutating func convertLineEndings(to lineEnding: LineEnding) -> LineEndingConversionResult {
        let result = LineEndingConversion.convert(text, to: lineEnding)
        text = result.text
        return result
    }

    @discardableResult
    public mutating func convertLineEndings(
        in lineRange: Range<Int>,
        to lineEnding: LineEnding
    ) throws -> LineEndingConversionResult {
        let result = try LineEndingConversion.convert(text, lines: lineRange, to: lineEnding)
        text = result.text
        return result
    }
}
