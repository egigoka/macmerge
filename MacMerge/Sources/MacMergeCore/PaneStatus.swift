import Foundation

public struct PaneStatusLimits: Equatable, Sendable {
    public static let `default` = PaneStatusLimits()

    public let maximumInputUTF16Length: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumInputUTF16Length: Int = 64 * 1024 * 1024,
        cancellationCheckInterval: Int = 4_096
    ) {
        self.maximumInputUTF16Length = maximumInputUTF16Length
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum PaneStatusError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case invalidTabWidth(Int)
    case inputTooLarge(maximumUTF16Length: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Pane status limits are invalid."
        case .invalidTabWidth(let width):
            "Pane status tab width \(width) is invalid."
        case .inputTooLarge(let maximumUTF16Length):
            "Pane text exceeds the \(maximumUTF16Length)-UTF-16-unit status limit."
        }
    }
}

public struct PaneStatusInput: Equatable, Sendable {
    public let text: String
    public let caretUTF16Offset: Int
    public let selectionUTF16Range: NSRange?
    public let encoding: TextFileEncoding
    public let hasByteOrderMark: Bool
    public let isReadOnly: Bool
    public let isDirty: Bool
    public let tabWidth: Int

    public init(
        text: String,
        caretUTF16Offset: Int,
        selectionUTF16Range: NSRange? = nil,
        encoding: TextFileEncoding,
        hasByteOrderMark: Bool,
        isReadOnly: Bool,
        isDirty: Bool,
        tabWidth: Int = 4
    ) {
        self.text = text
        self.caretUTF16Offset = caretUTF16Offset
        self.selectionUTF16Range = selectionUTF16Range
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
        self.isReadOnly = isReadOnly
        self.isDirty = isDirty
        self.tabWidth = tabWidth
    }
}

public struct PaneTextPosition: Equatable, Sendable {
    /// One-based logical line. Empty text starts on line 1.
    public let line: Int
    /// One-based visual column. Tabs advance to the next configured tab stop.
    public let column: Int
    /// One-based extended-grapheme-cluster position within the logical line.
    public let character: Int
    /// Zero-based UTF-16 offset, clamped down to an extended grapheme boundary.
    public let utf16Offset: Int

    public init(line: Int, column: Int, character: Int, utf16Offset: Int) {
        self.line = line
        self.column = column
        self.character = character
        self.utf16Offset = utf16Offset
    }
}

public struct PaneSelectionStatus: Equatable, Sendable {
    /// Clamped UTF-16 range. A split start moves down and a split end moves up.
    public let utf16Range: NSRange
    public let unicodeScalarCount: Int
    public let graphemeCount: Int
    public let utf16Count: Int

    public var isEmpty: Bool { utf16Count == 0 }

    public init(
        utf16Range: NSRange,
        unicodeScalarCount: Int,
        graphemeCount: Int,
        utf16Count: Int
    ) {
        self.utf16Range = utf16Range
        self.unicodeScalarCount = unicodeScalarCount
        self.graphemeCount = graphemeCount
        self.utf16Count = utf16Count
    }
}

public struct PaneLineEndingStatus: Equatable, Sendable {
    public let crlfCount: Int
    public let lfCount: Int
    public let crCount: Int
    /// Most frequent ending. Ties use the ending encountered first.
    public let dominant: LineEnding?
    public let isMixed: Bool

    public var totalCount: Int {
        let (firstSum, firstOverflow) = crlfCount.addingReportingOverflow(lfCount)
        guard !firstOverflow else { return .max }
        let (total, totalOverflow) = firstSum.addingReportingOverflow(crCount)
        return totalOverflow ? .max : total
    }

    public var displayName: String {
        guard let dominant else { return "None" }
        return isMixed ? "Mixed (\(dominant.displayName))" : dominant.displayName
    }

    public init(
        crlfCount: Int,
        lfCount: Int,
        crCount: Int,
        dominant: LineEnding?,
        isMixed: Bool
    ) {
        self.crlfCount = crlfCount
        self.lfCount = lfCount
        self.crCount = crCount
        self.dominant = dominant
        self.isMixed = isMixed
    }
}

public struct PaneStatus: Equatable, Sendable {
    public let position: PaneTextPosition
    /// Logical editor lines, including an empty line after a final terminator.
    public let lineCount: Int
    public let selection: PaneSelectionStatus
    public let encoding: TextFileEncoding
    public let encodingDisplayName: String
    public let hasByteOrderMark: Bool
    public let lineEndings: PaneLineEndingStatus
    public let isReadOnly: Bool
    public let isDirty: Bool
    public let didClampCaret: Bool
    public let didClampSelection: Bool

    public var line: Int { position.line }
    public var column: Int { position.column }
    public var character: Int { position.character }
    public var caretUTF16Offset: Int { position.utf16Offset }
    public var selectionUTF16Range: NSRange { selection.utf16Range }
    public var selectedUnicodeScalarCount: Int { selection.unicodeScalarCount }
    public var selectedScalarCount: Int { selection.unicodeScalarCount }
    public var selectedGraphemeCount: Int { selection.graphemeCount }
    public var selectedUTF16Count: Int { selection.utf16Count }
    public var dominantLineEnding: LineEnding? { lineEndings.dominant }
    public var hasMixedLineEndings: Bool { lineEndings.isMixed }
    public var lineEndingDisplayName: String { lineEndings.displayName }

    public init(
        input: PaneStatusInput,
        limits: PaneStatusLimits = .default
    ) throws {
        guard limits.maximumInputUTF16Length >= 0,
              limits.cancellationCheckInterval > 0 else {
            throw PaneStatusError.invalidLimits
        }
        guard input.tabWidth > 0 else {
            throw PaneStatusError.invalidTabWidth(input.tabWidth)
        }

        try Self.validateInputLength(input.text, limits: limits)

        let requestedCaret = max(0, input.caretUTF16Offset)
        let requestedSelection = Self.requestedSelection(
            input.selectionUTF16Range,
            defaultOffset: requestedCaret
        )
        var resolvedCaret: PaneTextPosition?
        var resolvedSelectionStart: Int?
        var resolvedSelectionEnd: Int?
        var selectedUnicodeScalars = 0
        var selectedGraphemes = 0

        var utf16Offset = 0
        var line = 1
        var column = 1
        var character = 1
        var crlfCount = 0
        var lfCount = 0
        var crCount = 0
        var endingOrder: [LineEnding] = []
        endingOrder.reserveCapacity(3)
        var workSinceCancellationCheck = 0

        for grapheme in input.text {
            let utf16Length = grapheme.utf16.count
            let nextOffset = utf16Offset + utf16Length

            if resolvedCaret == nil, requestedCaret < nextOffset {
                resolvedCaret = PaneTextPosition(
                    line: line,
                    column: column,
                    character: character,
                    utf16Offset: utf16Offset
                )
            }
            if resolvedSelectionStart == nil, requestedSelection.lowerBound < nextOffset {
                resolvedSelectionStart = utf16Offset
            }
            if resolvedSelectionEnd == nil {
                if requestedSelection.upperBound <= utf16Offset {
                    resolvedSelectionEnd = utf16Offset
                } else if requestedSelection.upperBound < nextOffset {
                    resolvedSelectionEnd = nextOffset
                }
            }

            if requestedSelection.upperBound > requestedSelection.lowerBound,
               nextOffset > requestedSelection.lowerBound,
               utf16Offset < requestedSelection.upperBound {
                selectedGraphemes = Self.saturatingIncrement(selectedGraphemes)
                selectedUnicodeScalars = Self.saturatingAdd(
                    selectedUnicodeScalars,
                    grapheme.unicodeScalars.count
                )
            }

            if let ending = Self.lineEnding(of: grapheme) {
                if !endingOrder.contains(ending) {
                    endingOrder.append(ending)
                }
                switch ending {
                case .crlf: crlfCount += 1
                case .lf: lfCount += 1
                case .cr: crCount += 1
                }
                line = Self.saturatingIncrement(line)
                column = 1
                character = 1
            } else {
                character += 1
                if grapheme == "\t" {
                    column = Self.columnAfterTab(column, tabWidth: input.tabWidth)
                } else {
                    column = Self.saturatingIncrement(column)
                }
            }

            utf16Offset = nextOffset
            workSinceCancellationCheck += utf16Length
            if workSinceCancellationCheck >= limits.cancellationCheckInterval {
                try Task.checkCancellation()
                workSinceCancellationCheck = 0
            }
        }

        try Task.checkCancellation()

        let finalPosition = PaneTextPosition(
            line: line,
            column: column,
            character: character,
            utf16Offset: utf16Offset
        )
        let position = resolvedCaret ?? finalPosition
        let selectionStart = resolvedSelectionStart ?? utf16Offset
        let selectionEnd: Int
        if requestedSelection.isCollapsed {
            selectionEnd = selectionStart
        } else {
            selectionEnd = resolvedSelectionEnd ?? utf16Offset
        }
        let selectionLength = selectionEnd - selectionStart
        let normalizedSelectionRange = NSRange(
            location: selectionStart,
            length: selectionLength
        )
        let dominantEnding = Self.dominantLineEnding(
            in: endingOrder,
            crlfCount: crlfCount,
            lfCount: lfCount,
            crCount: crCount
        )

        self.position = position
        lineCount = line
        selection = PaneSelectionStatus(
            utf16Range: normalizedSelectionRange,
            unicodeScalarCount: selectedUnicodeScalars,
            graphemeCount: selectedGraphemes,
            utf16Count: selectionLength
        )
        encoding = input.encoding
        encodingDisplayName = input.encoding.displayName
            + (input.hasByteOrderMark ? " BOM" : "")
        hasByteOrderMark = input.hasByteOrderMark
        lineEndings = PaneLineEndingStatus(
            crlfCount: crlfCount,
            lfCount: lfCount,
            crCount: crCount,
            dominant: dominantEnding,
            isMixed: endingOrder.count > 1
        )
        isReadOnly = input.isReadOnly
        isDirty = input.isDirty
        didClampCaret = position.utf16Offset != input.caretUTF16Offset
        if let requestedRange = input.selectionUTF16Range {
            didClampSelection = normalizedSelectionRange != requestedRange
        } else {
            didClampSelection = false
        }
    }

    public init(
        text: String,
        caretUTF16Offset: Int,
        selectionUTF16Range: NSRange? = nil,
        encoding: TextFileEncoding,
        hasByteOrderMark: Bool,
        isReadOnly: Bool,
        isDirty: Bool,
        tabWidth: Int = 4,
        limits: PaneStatusLimits = .default
    ) throws {
        try self.init(
            input: PaneStatusInput(
                text: text,
                caretUTF16Offset: caretUTF16Offset,
                selectionUTF16Range: selectionUTF16Range,
                encoding: encoding,
                hasByteOrderMark: hasByteOrderMark,
                isReadOnly: isReadOnly,
                isDirty: isDirty,
                tabWidth: tabWidth
            ),
            limits: limits
        )
    }

    public static func calculate(
        input: PaneStatusInput,
        limits: PaneStatusLimits = .default
    ) throws -> PaneStatus {
        try PaneStatus(input: input, limits: limits)
    }

    private struct RequestedSelection {
        let lowerBound: Int
        let upperBound: Int
        let isCollapsed: Bool
    }

    private static func requestedSelection(
        _ range: NSRange?,
        defaultOffset: Int
    ) -> RequestedSelection {
        guard let range else {
            return RequestedSelection(
                lowerBound: defaultOffset,
                upperBound: defaultOffset,
                isCollapsed: true
            )
        }

        let lowerBound = max(0, range.location)
        guard range.length > 0 else {
            return RequestedSelection(
                lowerBound: lowerBound,
                upperBound: lowerBound,
                isCollapsed: true
            )
        }
        let (rawUpperBound, overflow) = range.location.addingReportingOverflow(range.length)
        let upperBound = max(0, overflow ? Int.max : rawUpperBound)
        return RequestedSelection(
            lowerBound: lowerBound,
            upperBound: max(lowerBound, upperBound),
            isCollapsed: false
        )
    }

    private static func validateInputLength(
        _ text: String,
        limits: PaneStatusLimits
    ) throws {
        var length = 0
        var workSinceCancellationCheck = 0
        for _ in text.utf16 {
            guard length < limits.maximumInputUTF16Length else {
                throw PaneStatusError.inputTooLarge(
                    maximumUTF16Length: limits.maximumInputUTF16Length
                )
            }
            length += 1
            workSinceCancellationCheck += 1
            if workSinceCancellationCheck >= limits.cancellationCheckInterval {
                try Task.checkCancellation()
                workSinceCancellationCheck = 0
            }
        }
        try Task.checkCancellation()
    }

    private static func lineEnding(of grapheme: Character) -> LineEnding? {
        switch grapheme {
        case "\r\n": .crlf
        case "\n": .lf
        case "\r": .cr
        default: nil
        }
    }

    private static func dominantLineEnding(
        in occurrenceOrder: [LineEnding],
        crlfCount: Int,
        lfCount: Int,
        crCount: Int
    ) -> LineEnding? {
        let maximumCount = max(crlfCount, lfCount, crCount)
        guard maximumCount > 0 else { return nil }
        return occurrenceOrder.first { ending in
            switch ending {
            case .crlf: crlfCount == maximumCount
            case .lf: lfCount == maximumCount
            case .cr: crCount == maximumCount
            }
        }
    }

    private static func columnAfterTab(_ column: Int, tabWidth: Int) -> Int {
        let remainder = (column - 1) % tabWidth
        let advance = tabWidth - remainder
        let (result, overflow) = column.addingReportingOverflow(advance)
        return overflow ? .max : result
    }

    private static func saturatingIncrement(_ value: Int) -> Int {
        let (result, overflow) = value.addingReportingOverflow(1)
        return overflow ? .max : result
    }

    private static func saturatingAdd(_ left: Int, _ right: Int) -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        return overflow ? .max : result
    }
}
