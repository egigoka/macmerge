import Foundation

public struct ConflictFileParserLimits: Equatable, Sendable {
    public static let `default` = ConflictFileParserLimits()

    public let maximumInputBytes: Int
    public let maximumLineCount: Int
    public let maximumConflictCount: Int
    public let maximumMarkerCount: Int
    public let maximumMarkerWidth: Int
    public let maximumLabelBytes: Int

    public init(
        maximumInputBytes: Int = 64 * 1024 * 1024,
        maximumLineCount: Int = 1_000_000,
        maximumConflictCount: Int = 100_000,
        maximumMarkerCount: Int = 400_000,
        maximumMarkerWidth: Int = 1_024,
        maximumLabelBytes: Int = 64 * 1024
    ) {
        precondition(maximumInputBytes >= 0)
        precondition(maximumLineCount >= 0)
        precondition(maximumConflictCount >= 0)
        precondition(maximumMarkerCount >= 0)
        precondition(maximumMarkerWidth >= ConflictFileParser.minimumMarkerWidth)
        precondition(maximumLabelBytes >= 0)
        self.maximumInputBytes = maximumInputBytes
        self.maximumLineCount = maximumLineCount
        self.maximumConflictCount = maximumConflictCount
        self.maximumMarkerCount = maximumMarkerCount
        self.maximumMarkerWidth = maximumMarkerWidth
        self.maximumLabelBytes = maximumLabelBytes
    }
}

public enum ConflictMarkerKind: String, Equatable, Sendable {
    case current
    case base
    case separator
    case incoming
}

public struct ConflictFileConflict: Equatable, Sendable {
    /// One-based source lines from the opening marker through the closing marker.
    public let sourceLineRange: ClosedRange<Int>
    public let markerWidth: Int
    public let currentLabel: String?
    public let baseLabel: String?
    public let incomingLabel: String?

    public init(
        sourceLineRange: ClosedRange<Int>,
        markerWidth: Int,
        currentLabel: String?,
        baseLabel: String?,
        incomingLabel: String?
    ) {
        self.sourceLineRange = sourceLineRange
        self.markerWidth = markerWidth
        self.currentLabel = currentLabel
        self.baseLabel = baseLabel
        self.incomingLabel = incomingLabel
    }
}

public struct ConflictFileParseResult: Equatable, Sendable {
    public let currentText: String
    public let baseText: String?
    public let incomingText: String
    public let conflicts: [ConflictFileConflict]

    public var isThreeWay: Bool { baseText != nil }

    public init(
        currentText: String,
        baseText: String?,
        incomingText: String,
        conflicts: [ConflictFileConflict]
    ) {
        self.currentText = currentText
        self.baseText = baseText
        self.incomingText = incomingText
        self.conflicts = conflicts
    }
}

public enum ConflictFileParserError: Error, LocalizedError, Equatable, Sendable {
    case inputTooLarge(maximumBytes: Int)
    case tooManyLines(maximum: Int)
    case tooManyConflicts(maximum: Int)
    case tooManyMarkers(maximum: Int)
    case markerTooWide(line: Int, maximum: Int)
    case markerLabelTooLong(line: Int, maximumBytes: Int)
    case malformedMarker(line: Int)
    case unexpectedMarker(kind: ConflictMarkerKind, line: Int)
    case inconsistentMarkerWidth(line: Int, expected: Int, actual: Int)
    case mixedConflictStyles(line: Int)
    case nestedConflict(line: Int)
    case unterminatedConflict(startLine: Int)
    case noConflictMarkers

    public var errorDescription: String? {
        switch self {
        case .inputTooLarge(let maximumBytes):
            "Conflict file exceeds the current \(maximumBytes)-byte safety limit."
        case .tooManyLines(let maximum):
            "Conflict file exceeds the current \(maximum)-line safety limit."
        case .tooManyConflicts(let maximum):
            "Conflict file exceeds the current \(maximum)-conflict safety limit."
        case .tooManyMarkers(let maximum):
            "Conflict file exceeds the current \(maximum)-marker safety limit."
        case .markerTooWide(let line, let maximum):
            "Conflict marker on line \(line) exceeds the current \(maximum)-character limit."
        case .markerLabelTooLong(let line, let maximumBytes):
            "Conflict marker label on line \(line) exceeds the current \(maximumBytes)-byte limit."
        case .malformedMarker(let line):
            "Conflict marker on line \(line) is malformed."
        case .unexpectedMarker(let kind, let line):
            "Unexpected \(kind.rawValue) conflict marker on line \(line)."
        case .inconsistentMarkerWidth(let line, let expected, let actual):
            "Conflict marker on line \(line) has width \(actual); expected \(expected)."
        case .mixedConflictStyles(let line):
            "Conflict marker on line \(line) mixes two-way and diff3 conflict styles."
        case .nestedConflict(let line):
            "Nested conflict starts on line \(line). Resolve the inner conflict before opening this file."
        case .unterminatedConflict(let startLine):
            "Conflict starting on line \(startLine) has no closing marker."
        case .noConflictMarkers:
            "File contains no Git conflict markers."
        }
    }
}

public enum ConflictFileParser: Sendable {
    public static let minimumMarkerWidth = 1

    /// Splits conflict-marked text without normalizing any retained line ending.
    public static func parse(
        _ text: String,
        limits: ConflictFileParserLimits = .default
    ) throws -> ConflictFileParseResult {
        let inputByteCount = text.utf8.count
        guard inputByteCount <= limits.maximumInputBytes else {
            throw ConflictFileParserError.inputTooLarge(maximumBytes: limits.maximumInputBytes)
        }

        if let result = try text.utf8.withContiguousStorageIfAvailable({ input in
            try parse(input, limits: limits)
        }) {
            return result
        }

        let input = Array(text.utf8)
        return try input.withUnsafeBufferPointer { input in
            try parse(input, limits: limits)
        }
    }

    private static func parse(
        _ input: UnsafeBufferPointer<UInt8>,
        limits: ConflictFileParserLimits
    ) throws -> ConflictFileParseResult {
        var currentOutput: [UInt8] = []
        var baseOutput: [UInt8]?
        var incomingOutput: [UInt8] = []
        let initialOutputCapacity = min(input.count, 1024 * 1024)
        currentOutput.reserveCapacity(initialOutputCapacity)

        var phase = Phase.common
        var activeConflict: ActiveConflict?
        var conflicts: [ConflictFileConflict] = []
        var conflictStyle: ConflictStyle?
        var hasSeenConflictStart = false
        var markerCount = 0
        var lineNumber = 1
        var lineStart = 0

        while lineStart < input.count {
            guard lineNumber <= limits.maximumLineCount else {
                throw ConflictFileParserError.tooManyLines(maximum: limits.maximumLineCount)
            }

            var contentEnd = lineStart
            while contentEnd < input.count, input[contentEnd] != 0x0A, input[contentEnd] != 0x0D {
                contentEnd += 1
            }
            var recordEnd = contentEnd
            if recordEnd < input.count {
                if input[recordEnd] == 0x0D,
                    recordEnd + 1 < input.count,
                    input[recordEnd + 1] == 0x0A
                {
                    recordEnd += 2
                } else {
                    recordEnd += 1
                }
            }

            let marker = try marker(
                in: input,
                range: lineStart..<contentEnd,
                line: lineNumber,
                activeMarkerWidth: activeConflict?.markerWidth,
                limits: limits
            )
            if let marker {
                guard markerCount < limits.maximumMarkerCount else {
                    throw ConflictFileParserError.tooManyMarkers(maximum: limits.maximumMarkerCount)
                }
                markerCount += 1

                if phase != .common, marker.kind == .current {
                    throw ConflictFileParserError.nestedConflict(line: lineNumber)
                }

                switch (phase, marker.kind) {
                case (.common, .current):
                    guard conflicts.count < limits.maximumConflictCount else {
                        throw ConflictFileParserError.tooManyConflicts(
                            maximum: limits.maximumConflictCount
                        )
                    }
                    if !hasSeenConflictStart {
                        incomingOutput = currentOutput
                        hasSeenConflictStart = true
                    }
                    activeConflict = ActiveConflict(
                        startLine: lineNumber,
                        markerWidth: marker.width,
                        currentLabel: marker.label,
                        baseLabel: nil,
                        currentOutputStart: currentOutput.count
                    )
                    phase = .current

                case (.current, .base):
                    guard conflictStyle != .twoWay else {
                        throw ConflictFileParserError.mixedConflictStyles(line: lineNumber)
                    }
                    guard let conflict = activeConflict else {
                        preconditionFailure("Current phase requires an active conflict")
                    }
                    if baseOutput == nil {
                        baseOutput = Array(currentOutput[..<conflict.currentOutputStart])
                    }
                    activeConflict?.baseLabel = marker.label
                    phase = .base

                case (.current, .separator):
                    guard conflictStyle != .diff3 else {
                        throw ConflictFileParserError.mixedConflictStyles(line: lineNumber)
                    }
                    conflictStyle = .twoWay
                    phase = .incoming

                case (.base, .separator):
                    conflictStyle = .diff3
                    phase = .incoming

                case (.incoming, .incoming):
                    guard let completedConflict = activeConflict else {
                        preconditionFailure("Incoming phase requires an active conflict")
                    }
                    conflicts.append(
                        ConflictFileConflict(
                            sourceLineRange: completedConflict.startLine...lineNumber,
                            markerWidth: completedConflict.markerWidth,
                            currentLabel: completedConflict.currentLabel,
                            baseLabel: completedConflict.baseLabel,
                            incomingLabel: marker.label
                        )
                    )
                    activeConflict = nil
                    phase = .common

                default:
                    throw ConflictFileParserError.unexpectedMarker(
                        kind: marker.kind,
                        line: lineNumber
                    )
                }
            } else {
                let record = input[lineStart..<recordEnd]
                switch phase {
                case .common:
                    currentOutput.append(contentsOf: record)
                    if hasSeenConflictStart {
                        baseOutput?.append(contentsOf: record)
                        incomingOutput.append(contentsOf: record)
                    }
                case .current:
                    currentOutput.append(contentsOf: record)
                case .base:
                    baseOutput?.append(contentsOf: record)
                case .incoming:
                    incomingOutput.append(contentsOf: record)
                }
            }

            lineStart = recordEnd
            lineNumber += 1
        }

        if let activeConflict {
            throw ConflictFileParserError.unterminatedConflict(startLine: activeConflict.startLine)
        }
        guard !conflicts.isEmpty else {
            throw ConflictFileParserError.noConflictMarkers
        }

        let currentText = String(decoding: currentOutput, as: UTF8.self)
        currentOutput.removeAll(keepingCapacity: false)
        let baseText = baseOutput.map { String(decoding: $0, as: UTF8.self) }
        baseOutput = nil
        let incomingText = String(decoding: incomingOutput, as: UTF8.self)
        incomingOutput.removeAll(keepingCapacity: false)

        return ConflictFileParseResult(
            currentText: currentText,
            baseText: baseText,
            incomingText: incomingText,
            conflicts: conflicts
        )
    }

    private enum Phase {
        case common
        case current
        case base
        case incoming
    }

    private enum ConflictStyle {
        case twoWay
        case diff3
    }

    private struct ActiveConflict {
        let startLine: Int
        let markerWidth: Int
        let currentLabel: String?
        var baseLabel: String?
        let currentOutputStart: Int
    }

    private struct Marker {
        let kind: ConflictMarkerKind
        let width: Int
        let label: String?
    }

    private static func marker(
        in input: UnsafeBufferPointer<UInt8>,
        range: Range<Int>,
        line lineNumber: Int,
        activeMarkerWidth: Int?,
        limits: ConflictFileParserLimits
    ) throws -> Marker? {
        guard let first = range.first else { return nil }

        let kind: ConflictMarkerKind
        switch input[first] {
        case 0x3C: kind = .current
        case 0x7C: kind = .base
        case 0x3D: kind = .separator
        case 0x3E: kind = .incoming
        default: return nil
        }
        if activeMarkerWidth == nil, kind != .current {
            return nil
        }

        var suffixStart = range.startIndex
        while suffixStart < range.endIndex, input[suffixStart] == input[first] {
            suffixStart += 1
        }
        let width = suffixStart - range.startIndex
        if kind != .current, let activeMarkerWidth, width != activeMarkerWidth {
            return nil
        }
        guard width <= limits.maximumMarkerWidth else {
            throw ConflictFileParserError.markerTooWide(
                line: lineNumber,
                maximum: limits.maximumMarkerWidth
            )
        }

        let suffix = input[suffixStart..<range.endIndex]
        if kind == .separator {
            guard suffix.isEmpty else {
                throw ConflictFileParserError.malformedMarker(line: lineNumber)
            }
            return Marker(kind: kind, width: width, label: nil)
        }

        guard suffix.isEmpty || suffix.first == 0x20 else {
            if kind == .current {
                return nil
            }
            throw ConflictFileParserError.malformedMarker(line: lineNumber)
        }
        let labelBytes = suffix.isEmpty ? suffix : suffix.dropFirst()
        guard labelBytes.count <= limits.maximumLabelBytes else {
            throw ConflictFileParserError.markerLabelTooLong(
                line: lineNumber,
                maximumBytes: limits.maximumLabelBytes
            )
        }
        guard !labelBytes.contains(0) else {
            throw ConflictFileParserError.malformedMarker(line: lineNumber)
        }
        let label = suffix.isEmpty ? nil : String(decoding: labelBytes, as: UTF8.self)
        return Marker(kind: kind, width: width, label: label)
    }

}
