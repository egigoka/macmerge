import Foundation

private final class TextPaneStatusSourceIdentity: Sendable {
    let text: String

    init(text: String) {
        self.text = text
    }
}

public struct TextPaneStatusLimits: Equatable, Sendable {
    public static let `default` = TextPaneStatusLimits()

    public let maximumInputUTF16Length: Int
    public let maximumWorkUnits: Int
    public let maximumGraphemeUTF16Length: Int
    public let maximumReportedScalarsPerGrapheme: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumInputUTF16Length: Int = 64 * 1024 * 1024,
        maximumWorkUnits: Int = 320 * 1024 * 1024,
        maximumGraphemeUTF16Length: Int = 1024 * 1024,
        maximumReportedScalarsPerGrapheme: Int = 256,
        cancellationCheckInterval: Int = 4_096
    ) {
        self.maximumInputUTF16Length = maximumInputUTF16Length
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumGraphemeUTF16Length = maximumGraphemeUTF16Length
        self.maximumReportedScalarsPerGrapheme = maximumReportedScalarsPerGrapheme
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public struct TextPaneStatusSnapshotFingerprint: Equatable, Sendable {
    public let revision: UInt64
    public let textUTF16Length: Int
    public let textDigestLow: UInt64
    public let textDigestHigh: UInt64
    public let caretUTF16Offset: Int
    public let selectionUTF16Range: NSRange?
    public let encoding: TextFileEncoding
    public let hasByteOrderMark: Bool
    public let isReadOnly: Bool
    public let isDirty: Bool
    public let tabWidth: Int
    public let limits: TextPaneStatusLimits
    fileprivate let sourceIdentity: TextPaneStatusSourceIdentity

    public static func == (
        lhs: TextPaneStatusSnapshotFingerprint,
        rhs: TextPaneStatusSnapshotFingerprint
    ) -> Bool {
        lhs.sourceIdentity === rhs.sourceIdentity
            && lhs.revision == rhs.revision
            && lhs.textUTF16Length == rhs.textUTF16Length
            && lhs.textDigestLow == rhs.textDigestLow
            && lhs.textDigestHigh == rhs.textDigestHigh
            && lhs.caretUTF16Offset == rhs.caretUTF16Offset
            && lhs.selectionUTF16Range == rhs.selectionUTF16Range
            && lhs.encoding == rhs.encoding
            && lhs.hasByteOrderMark == rhs.hasByteOrderMark
            && lhs.isReadOnly == rhs.isReadOnly
            && lhs.isDirty == rhs.isDirty
            && lhs.tabWidth == rhs.tabWidth
            && lhs.limits == rhs.limits
    }
}

public enum TextPaneStatusError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case invalidTabWidth(Int)
    case inputTooLarge(maximumUTF16Length: Int)
    case workLimitExceeded(maximumWorkUnits: Int)
    case graphemeTooLarge(maximumUTF16Length: Int)
    case invalidCaretUTF16Offset(Int)
    case invalidSelectionUTF16Range(NSRange)
    case utf16OffsetSplitsGrapheme(Int)
    case invalidByteOrderMark(TextFileEncoding)
    case staleRevision(expected: UInt64, actual: UInt64)
    case staleSnapshot

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Text pane status limits are invalid."
        case .invalidTabWidth(let width):
            "Text pane tab width \(width) is invalid."
        case .inputTooLarge(let maximumUTF16Length):
            "Text exceeds the \(maximumUTF16Length)-UTF-16-unit pane status limit."
        case .workLimitExceeded(let maximumWorkUnits):
            "Text pane status calculation exceeds the \(maximumWorkUnits)-unit work limit."
        case .graphemeTooLarge(let maximumUTF16Length):
            "A text grapheme exceeds the \(maximumUTF16Length)-UTF-16-unit pane status limit."
        case .invalidCaretUTF16Offset(let offset):
            "Caret UTF-16 offset \(offset) is outside the text."
        case .invalidSelectionUTF16Range(let range):
            "Selection UTF-16 range \(NSStringFromRange(range)) is outside the text."
        case .utf16OffsetSplitsGrapheme(let offset):
            "UTF-16 offset \(offset) splits an extended grapheme cluster."
        case .invalidByteOrderMark(let encoding):
            "\(encoding.displayName) cannot contain a byte-order mark."
        case .staleRevision(let expected, let actual):
            "Text pane status is stale (computed for revision \(expected), current revision \(actual))."
        case .staleSnapshot:
            "Text pane status is stale because pane inputs changed without a revision change."
        }
    }
}

/// Immutable pane state captured before status calculation.
public struct TextPaneStatusInput: Equatable, Sendable {
    public let text: String
    public let revision: UInt64
    public let caretUTF16Offset: Int
    public let selectionUTF16Range: NSRange?
    public let encoding: TextFileEncoding
    public let hasByteOrderMark: Bool
    public let isReadOnly: Bool
    public let isDirty: Bool
    public let tabWidth: Int
    fileprivate let sourceIdentity: TextPaneStatusSourceIdentity

    public init(
        text: String,
        revision: UInt64,
        caretUTF16Offset: Int,
        selectionUTF16Range: NSRange? = nil,
        encoding: TextFileEncoding,
        hasByteOrderMark: Bool,
        isReadOnly: Bool,
        isDirty: Bool,
        tabWidth: Int = 4
    ) {
        self.text = text
        self.revision = revision
        self.caretUTF16Offset = caretUTF16Offset
        self.selectionUTF16Range = selectionUTF16Range
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
        self.isReadOnly = isReadOnly
        self.isDirty = isDirty
        self.tabWidth = tabWidth
        sourceIdentity = TextPaneStatusSourceIdentity(text: text)
    }

    public init(
        document: TextFileDocument,
        revision: UInt64,
        caretUTF16Offset: Int,
        selectionUTF16Range: NSRange? = nil,
        isReadOnly: Bool,
        isDirty: Bool,
        tabWidth: Int = 4
    ) {
        self.init(
            text: document.text,
            revision: revision,
            caretUTF16Offset: caretUTF16Offset,
            selectionUTF16Range: selectionUTF16Range,
            encoding: document.encoding,
            hasByteOrderMark: document.hasByteOrderMark,
            isReadOnly: isReadOnly,
            isDirty: isDirty || document.isDirty,
            tabWidth: tabWidth
        )
    }

    public static func == (lhs: TextPaneStatusInput, rhs: TextPaneStatusInput) -> Bool {
        lhs.sourceIdentity === rhs.sourceIdentity
            && lhs.revision == rhs.revision
            && lhs.caretUTF16Offset == rhs.caretUTF16Offset
            && (lhs.selectionUTF16Range
                ?? NSRange(location: lhs.caretUTF16Offset, length: 0))
                == (rhs.selectionUTF16Range
                    ?? NSRange(location: rhs.caretUTF16Offset, length: 0))
            && lhs.encoding == rhs.encoding
            && lhs.hasByteOrderMark == rhs.hasByteOrderMark
            && lhs.isReadOnly == rhs.isReadOnly
            && lhs.isDirty == rhs.isDirty
            && lhs.tabWidth == rhs.tabWidth
    }
}

public struct TextPanePositionStatus: Equatable, Sendable {
    /// One-based logical line. Empty text starts on line 1.
    public let line: Int
    /// One-based extended-grapheme-cluster column.
    public let logicalColumn: Int
    /// One-based display column. Tabs advance to the next configured tab stop.
    public let visualColumn: Int
    /// One-based UTF-16 column within the logical line.
    public let utf16Column: Int
    /// Zero-based UTF-16 offset in the complete text.
    public let utf16Offset: Int

    public init(
        line: Int,
        logicalColumn: Int,
        visualColumn: Int,
        utf16Column: Int,
        utf16Offset: Int
    ) {
        self.line = line
        self.logicalColumn = logicalColumn
        self.visualColumn = visualColumn
        self.utf16Column = utf16Column
        self.utf16Offset = utf16Offset
    }
}

public struct TextPaneUnicodeScalarStatus: Equatable, Sendable {
    public let value: UInt32
    public let codePoint: String
    public let name: String?
    public let accessibilityLabel: String

    public init(value: UInt32, codePoint: String, name: String?, accessibilityLabel: String) {
        self.value = value
        self.codePoint = codePoint
        self.name = name
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct TextPaneCharacterStatus: Equatable, Sendable {
    public let character: String
    public let displayName: String
    public let unicodeScalarCount: Int
    public let utf16Count: Int
    public let scalars: [TextPaneUnicodeScalarStatus]
    public let areScalarsTruncated: Bool
    public let accessibilityLabel: String

    public init(
        character: String,
        displayName: String,
        unicodeScalarCount: Int,
        utf16Count: Int,
        scalars: [TextPaneUnicodeScalarStatus],
        areScalarsTruncated: Bool,
        accessibilityLabel: String
    ) {
        self.character = character
        self.displayName = displayName
        self.unicodeScalarCount = unicodeScalarCount
        self.utf16Count = utf16Count
        self.scalars = scalars
        self.areScalarsTruncated = areScalarsTruncated
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct TextPaneSelectionStatus: Equatable, Sendable {
    public let utf16Range: NSRange
    public let graphemeCount: Int
    public let unicodeScalarCount: Int
    public let utf16Count: Int
    /// Logical lines containing at least one selected grapheme. Empty selections report zero.
    public let lineCount: Int

    public var isEmpty: Bool { utf16Count == 0 }

    public init(
        utf16Range: NSRange,
        graphemeCount: Int,
        unicodeScalarCount: Int,
        utf16Count: Int,
        lineCount: Int
    ) {
        self.utf16Range = utf16Range
        self.graphemeCount = graphemeCount
        self.unicodeScalarCount = unicodeScalarCount
        self.utf16Count = utf16Count
        self.lineCount = lineCount
    }
}

public struct TextPaneLineEndingSummary: Equatable, Sendable {
    public let crlfCount: Int
    public let lfCount: Int
    public let crCount: Int
    /// Most frequent ending. Ties use first occurrence in the text.
    public let dominant: LineEnding?
    public let isMixed: Bool

    public var totalCount: Int {
        let (partial, partialOverflow) = crlfCount.addingReportingOverflow(lfCount)
        guard !partialOverflow else { return .max }
        let (total, totalOverflow) = partial.addingReportingOverflow(crCount)
        return totalOverflow ? .max : total
    }

    public var displayName: String {
        guard let dominant else { return "None" }
        return isMixed ? "Mixed (\(dominant.displayName) dominant)" : dominant.displayName
    }

    public var accessibilityLabel: String {
        guard let dominant else { return "No line endings" }
        if !isMixed {
            return "Line endings: \(dominant.displayName), \(totalCount) total"
        }
        return "Mixed line endings, \(dominant.displayName) dominant; \(crlfCount) CRLF, \(lfCount) LF, \(crCount) CR"
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

public struct TextPaneStatusLabels: Equatable, Sendable {
    public let position: String
    public let character: String
    public let selection: String
    public let encoding: String
    public let lineEndings: String
    public let documentState: String
    public let combined: String

    public init(
        position: String,
        character: String,
        selection: String,
        encoding: String,
        lineEndings: String,
        documentState: String,
        combined: String
    ) {
        self.position = position
        self.character = character
        self.selection = selection
        self.encoding = encoding
        self.lineEndings = lineEndings
        self.documentState = documentState
        self.combined = combined
    }
}

public struct TextPaneStatus: Equatable, Sendable {
    public let sourceRevision: UInt64
    public let sourceSnapshotFingerprint: TextPaneStatusSnapshotFingerprint
    public let textUTF16Length: Int
    public let position: TextPanePositionStatus
    public let currentCharacter: TextPaneCharacterStatus?
    /// Logical editor lines, including an empty line after a final terminator.
    public let lineCount: Int
    public let selection: TextPaneSelectionStatus
    public let encoding: TextFileEncoding
    public let encodingDisplayName: String
    public let hasByteOrderMark: Bool
    public let lineEndings: TextPaneLineEndingSummary
    public let isReadOnly: Bool
    public let isDirty: Bool
    public let tabWidth: Int
    public let accessibilityLabels: TextPaneStatusLabels

    public var line: Int { position.line }
    public var logicalColumn: Int { position.logicalColumn }
    public var visualColumn: Int { position.visualColumn }
    public var utf16Column: Int { position.utf16Column }
    public var caretUTF16Offset: Int { position.utf16Offset }
    public var selectionUTF16Range: NSRange { selection.utf16Range }
    public var selectedGraphemeCount: Int { selection.graphemeCount }
    public var selectedUnicodeScalarCount: Int { selection.unicodeScalarCount }
    public var selectedUTF16Count: Int { selection.utf16Count }
    public var selectedLineCount: Int { selection.lineCount }
    public var dominantLineEnding: LineEnding? { lineEndings.dominant }
    public var hasMixedLineEndings: Bool { lineEndings.isMixed }

    public static func == (lhs: TextPaneStatus, rhs: TextPaneStatus) -> Bool {
        lhs.sourceSnapshotFingerprint == rhs.sourceSnapshotFingerprint
    }

    public init(
        input: TextPaneStatusInput,
        limits: TextPaneStatusLimits = .default
    ) throws {
        try Self.validate(limits)
        try Self.validateMetadata(input)

        let requestedSelection = try Self.selectionRange(
            input.selectionUTF16Range,
            defaultOffset: input.caretUTF16Offset
        )
        var work = WorkBudget(limits: limits)
        try Task.checkCancellation()
        let preflight = try Self.preflight(input.text, work: &work)
        let snapshotFingerprint = Self.snapshotFingerprint(
            input: input,
            limits: limits,
            preflight: preflight,
            selectionUTF16Range: requestedSelection.range
        )

        guard input.caretUTF16Offset <= preflight.utf16Length else {
            throw TextPaneStatusError.invalidCaretUTF16Offset(input.caretUTF16Offset)
        }
        guard requestedSelection.upperBound <= preflight.utf16Length else {
            throw TextPaneStatusError.invalidSelectionUTF16Range(requestedSelection.range)
        }

        var offset = 0
        var lineStartOffset = 0
        var line = 1
        var logicalColumn = 1
        var visualColumn = 1
        var caretPosition: TextPanePositionStatus?
        var caretCharacter: TextPaneCharacterStatus?
        var foundCaretBoundary = false
        var foundSelectionStartBoundary = false
        var foundSelectionEndBoundary = false
        var selectedGraphemes = 0
        var selectedScalars = 0
        var selectedLines = 0
        var lastSelectedLine: Int?
        var crlfCount = 0
        var lfCount = 0
        var crCount = 0
        var lineEndingOrder: [LineEnding] = []
        lineEndingOrder.reserveCapacity(3)
        var graphemeScanner = InterruptibleGraphemeScanner(input.text)
        while let grapheme = try graphemeScanner.next(
            capturingDetailsAt: input.caretUTF16Offset,
            maximumReportedScalars: limits.maximumReportedScalarsPerGrapheme,
            work: &work
        ) {
            precondition(grapheme.utf16Offset == offset)
            let isCaretCharacter = input.caretUTF16Offset == offset
            if isCaretCharacter {
                foundCaretBoundary = true
                caretPosition = TextPanePositionStatus(
                    line: line,
                    logicalColumn: logicalColumn,
                    visualColumn: visualColumn,
                    utf16Column: offset - lineStartOffset + 1,
                    utf16Offset: offset
                )
            }
            if requestedSelection.lowerBound == offset {
                foundSelectionStartBoundary = true
            }
            if requestedSelection.upperBound == offset {
                foundSelectionEndBoundary = true
            }

            let (nextOffset, offsetOverflow) = offset.addingReportingOverflow(
                grapheme.utf16Count
            )
            guard !offsetOverflow, nextOffset <= limits.maximumInputUTF16Length else {
                throw TextPaneStatusError.inputTooLarge(
                    maximumUTF16Length: limits.maximumInputUTF16Length
                )
            }
            if isCaretCharacter {
                caretCharacter = Self.characterStatus(
                    grapheme.capturedText ?? "",
                    kind: grapheme.kind,
                    utf16Count: grapheme.utf16Count,
                    scalarCount: grapheme.scalarCount,
                    reportedScalars: grapheme.reportedScalars
                )
            }

            if requestedSelection.lowerBound <= offset,
                nextOffset <= requestedSelection.upperBound,
                requestedSelection.lowerBound < requestedSelection.upperBound
            {
                selectedGraphemes = Self.saturatingIncrement(selectedGraphemes)
                selectedScalars = Self.saturatingAdd(selectedScalars, grapheme.scalarCount)
                if lastSelectedLine != line {
                    selectedLines = Self.saturatingIncrement(selectedLines)
                    lastSelectedLine = line
                }
            }

            if let ending = grapheme.kind.lineEnding {
                if !lineEndingOrder.contains(ending) {
                    lineEndingOrder.append(ending)
                }
                switch ending {
                case .crlf:
                    crlfCount = Self.saturatingIncrement(crlfCount)
                case .lf:
                    lfCount = Self.saturatingIncrement(lfCount)
                case .cr:
                    crCount = Self.saturatingIncrement(crCount)
                }
            }
            if grapheme.kind.lineEnding != nil {
                line = Self.saturatingIncrement(line)
                logicalColumn = 1
                visualColumn = 1
                lineStartOffset = nextOffset
            } else {
                logicalColumn = Self.saturatingIncrement(logicalColumn)
                visualColumn = Self.visualColumn(
                    after: grapheme.kind,
                    from: visualColumn,
                    tabWidth: input.tabWidth
                )
            }
            offset = nextOffset
        }

        if input.caretUTF16Offset == offset {
            foundCaretBoundary = true
            caretPosition = TextPanePositionStatus(
                line: line,
                logicalColumn: logicalColumn,
                visualColumn: visualColumn,
                utf16Column: offset - lineStartOffset + 1,
                utf16Offset: offset
            )
            caretCharacter = nil
        }
        if requestedSelection.lowerBound == offset {
            foundSelectionStartBoundary = true
        }
        if requestedSelection.upperBound == offset {
            foundSelectionEndBoundary = true
        }
        try work.finish()

        guard foundCaretBoundary, let caretPosition else {
            throw TextPaneStatusError.utf16OffsetSplitsGrapheme(input.caretUTF16Offset)
        }
        guard foundSelectionStartBoundary else {
            throw TextPaneStatusError.utf16OffsetSplitsGrapheme(requestedSelection.lowerBound)
        }
        guard foundSelectionEndBoundary else {
            throw TextPaneStatusError.utf16OffsetSplitsGrapheme(requestedSelection.upperBound)
        }

        let selectedLineCount =
            requestedSelection.range.length == 0
            ? 0
            : selectedLines
        let selection = TextPaneSelectionStatus(
            utf16Range: requestedSelection.range,
            graphemeCount: selectedGraphemes,
            unicodeScalarCount: selectedScalars,
            utf16Count: requestedSelection.range.length,
            lineCount: selectedLineCount
        )
        let dominantLineEnding = Self.dominantLineEnding(
            occurrenceOrder: lineEndingOrder,
            crlfCount: crlfCount,
            lfCount: lfCount,
            crCount: crCount
        )
        let lineEndings = TextPaneLineEndingSummary(
            crlfCount: crlfCount,
            lfCount: lfCount,
            crCount: crCount,
            dominant: dominantLineEnding,
            isMixed: lineEndingOrder.count > 1
        )
        let encodingDisplayName =
            input.encoding.displayName
            + (input.hasByteOrderMark ? " BOM" : "")
        let labels = Self.labels(
            position: caretPosition,
            character: caretCharacter,
            selection: selection,
            encoding: input.encoding,
            hasByteOrderMark: input.hasByteOrderMark,
            lineEndings: lineEndings,
            isReadOnly: input.isReadOnly,
            isDirty: input.isDirty
        )
        try work.finish()

        sourceRevision = input.revision
        sourceSnapshotFingerprint = snapshotFingerprint
        textUTF16Length = offset
        position = caretPosition
        currentCharacter = caretCharacter
        lineCount = line
        self.selection = selection
        encoding = input.encoding
        self.encodingDisplayName = encodingDisplayName
        hasByteOrderMark = input.hasByteOrderMark
        self.lineEndings = lineEndings
        isReadOnly = input.isReadOnly
        isDirty = input.isDirty
        tabWidth = input.tabWidth
        accessibilityLabels = labels
    }

    public init(
        document: TextFileDocument,
        revision: UInt64,
        caretUTF16Offset: Int,
        selectionUTF16Range: NSRange? = nil,
        isReadOnly: Bool,
        isDirty: Bool,
        tabWidth: Int = 4,
        limits: TextPaneStatusLimits = .default
    ) throws {
        try self.init(
            input: TextPaneStatusInput(
                document: document,
                revision: revision,
                caretUTF16Offset: caretUTF16Offset,
                selectionUTF16Range: selectionUTF16Range,
                isReadOnly: isReadOnly,
                isDirty: isDirty,
                tabWidth: tabWidth
            ),
            limits: limits
        )
    }

    public static func calculate(
        input: TextPaneStatusInput,
        limits: TextPaneStatusLimits = .default
    ) throws -> TextPaneStatus {
        try TextPaneStatus(input: input, limits: limits)
    }

    public static func snapshotFingerprint(
        for input: TextPaneStatusInput,
        limits: TextPaneStatusLimits = .default
    ) throws -> TextPaneStatusSnapshotFingerprint {
        try validate(limits)
        var work = WorkBudget(limits: limits)
        return try validatedSnapshotFingerprint(
            for: input,
            limits: limits,
            matching: nil,
            work: &work
        ).fingerprint
    }

    public func isCurrent(
        input: TextPaneStatusInput,
        limits: TextPaneStatusLimits = .default
    ) throws -> Bool {
        try Self.validate(limits)
        try Task.checkCancellation()
        guard input.revision == sourceRevision else { return false }
        var work = WorkBudget(limits: limits)
        let current = try Self.validatedSnapshotFingerprint(
            for: input,
            limits: limits,
            matching: sourceSnapshotFingerprint.sourceIdentity.text,
            work: &work
        )
        return try Self.fingerprintsMatch(
            sourceSnapshotFingerprint,
            current.fingerprint,
            knownExactTextMatch: current.matchesExpectedText,
            work: &work
        )
    }

    public func validateCurrent(
        input: TextPaneStatusInput,
        limits: TextPaneStatusLimits = .default
    ) throws {
        try Self.validate(limits)
        try Task.checkCancellation()
        guard input.revision == sourceRevision else {
            throw TextPaneStatusError.staleRevision(
                expected: sourceRevision,
                actual: input.revision
            )
        }
        var work = WorkBudget(limits: limits)
        let current = try Self.validatedSnapshotFingerprint(
            for: input,
            limits: limits,
            matching: sourceSnapshotFingerprint.sourceIdentity.text,
            work: &work
        )
        try validateCurrent(
            snapshotFingerprint: current.fingerprint,
            knownExactTextMatch: current.matchesExpectedText,
            work: &work
        )
    }

    public func validateCurrent(
        snapshotFingerprint currentFingerprint: TextPaneStatusSnapshotFingerprint
    ) throws {
        try Self.validate(currentFingerprint.limits)
        var work = WorkBudget(limits: currentFingerprint.limits)
        try validateCurrent(
            snapshotFingerprint: currentFingerprint,
            knownExactTextMatch: nil,
            work: &work
        )
    }

    private func validateCurrent(
        snapshotFingerprint currentFingerprint: TextPaneStatusSnapshotFingerprint,
        knownExactTextMatch: Bool?,
        work: inout WorkBudget
    ) throws {
        let isCurrent = try Self.fingerprintsMatch(
            sourceSnapshotFingerprint,
            currentFingerprint,
            knownExactTextMatch: knownExactTextMatch,
            work: &work
        )
        guard isCurrent else {
            if currentFingerprint.revision != sourceRevision {
                throw TextPaneStatusError.staleRevision(
                    expected: sourceRevision,
                    actual: currentFingerprint.revision
                )
            }
            throw TextPaneStatusError.staleSnapshot
        }
    }

    public func hasSourceRevision(_ revision: UInt64) -> Bool {
        revision == sourceRevision
    }

    public func validateSourceRevision(_ revision: UInt64) throws {
        guard hasSourceRevision(revision) else {
            throw TextPaneStatusError.staleRevision(
                expected: sourceRevision,
                actual: revision
            )
        }
    }

    private struct RequestedSelection {
        let range: NSRange
        let lowerBound: Int
        let upperBound: Int
    }

    private struct TextPreflight {
        let utf16Length: Int
        let digestLow: UInt64
        let digestHigh: UInt64
        let matchesExpectedText: Bool
    }

    private struct ValidatedSnapshotFingerprint {
        let fingerprint: TextPaneStatusSnapshotFingerprint
        let matchesExpectedText: Bool
    }

    private enum GraphemeKind {
        case other
        case tab
        case crlf
        case lf
        case cr

        var lineEnding: LineEnding? {
            switch self {
            case .crlf:
                .crlf
            case .lf:
                .lf
            case .cr:
                .cr
            case .other, .tab:
                nil
            }
        }
    }

    private struct ScannedGrapheme {
        let utf16Offset: Int
        let utf16Count: Int
        let scalarCount: Int
        let kind: GraphemeKind
        let capturedText: String?
        let reportedScalars: [TextPaneUnicodeScalarStatus]
    }

    private struct InterruptibleGraphemeScanner {
        private struct PendingScalar {
            let scalar: Unicode.Scalar
            let utf16Offset: Int
            let utf16Count: Int
            let startsGrapheme: Bool
        }

        private var iterator: String.UnicodeScalarView.Iterator
        private var pending: PendingScalar?
        private var nextUTF16Offset = 0
        private var recognizer = Unicode._CharacterRecognizer()

        init(_ text: String) {
            iterator = text.unicodeScalars.makeIterator()
        }

        mutating func next(
            capturingDetailsAt captureOffset: Int?,
            maximumReportedScalars: Int,
            work: inout WorkBudget
        ) throws -> ScannedGrapheme? {
            guard let first = try takePendingOrRead(work: &work) else { return nil }

            let start = first.utf16Offset
            var utf16Count = 0
            var scalarCount = 0
            var firstScalarValue: UInt32?
            var secondScalarValue: UInt32?
            let capturesDetails = captureOffset == start
            var capturedText = capturesDetails ? "" : nil
            var reportedScalars: [TextPaneUnicodeScalarStatus] = []
            var current: PendingScalar? = first

            while let scalar = current {
                if scalar.utf16Offset != start, scalar.startsGrapheme {
                    pending = scalar
                    break
                }

                let (newUTF16Count, overflow) = utf16Count.addingReportingOverflow(
                    scalar.utf16Count
                )
                guard !overflow,
                    newUTF16Count <= work.limits.maximumGraphemeUTF16Length
                else {
                    throw TextPaneStatusError.graphemeTooLarge(
                        maximumUTF16Length: work.limits.maximumGraphemeUTF16Length
                    )
                }
                utf16Count = newUTF16Count
                scalarCount = saturatingIncrement(scalarCount)
                if firstScalarValue == nil {
                    firstScalarValue = scalar.scalar.value
                } else if secondScalarValue == nil {
                    secondScalarValue = scalar.scalar.value
                }
                if capturesDetails {
                    capturedText?.unicodeScalars.append(scalar.scalar)
                    if reportedScalars.count < maximumReportedScalars {
                        reportedScalars.append(scalarStatus(scalar.scalar))
                    }
                }
                current = try read(work: &work)
            }

            let kind: GraphemeKind
            switch (scalarCount, firstScalarValue, secondScalarValue) {
            case (1, 0x09, _):
                kind = .tab
            case (1, 0x0A, _):
                kind = .lf
            case (1, 0x0D, _):
                kind = .cr
            case (2, 0x0D, 0x0A):
                kind = .crlf
            default:
                kind = .other
            }
            return ScannedGrapheme(
                utf16Offset: start,
                utf16Count: utf16Count,
                scalarCount: scalarCount,
                kind: kind,
                capturedText: capturedText,
                reportedScalars: reportedScalars
            )
        }

        private mutating func takePendingOrRead(
            work: inout WorkBudget
        ) throws -> PendingScalar? {
            if let pending {
                self.pending = nil
                return pending
            }
            return try read(work: &work)
        }

        private mutating func read(work: inout WorkBudget) throws -> PendingScalar? {
            guard let scalar = iterator.next() else { return nil }
            let utf16Count = scalar.value > 0xFFFF ? 2 : 1
            try work.consume(utf16Count)
            let result = PendingScalar(
                scalar: scalar,
                utf16Offset: nextUTF16Offset,
                utf16Count: utf16Count,
                startsGrapheme: recognizer.hasBreak(before: scalar)
            )
            nextUTF16Offset += utf16Count
            return result
        }
    }

    private struct TextFingerprintBuilder {
        private(set) var low: UInt64 = 0xCBF2_9CE4_8422_2325
        private(set) var high: UInt64 = 0x8422_2325_CBF2_9CE4

        mutating func append(_ unit: UInt16) {
            low = (low ^ UInt64(unit)) &* 0x0000_0100_0000_01B3
            high ^= UInt64(unit) &+ 0x9E37_79B9_7F4A_7C15 &+ (high << 6) &+ (high >> 2)
        }

        mutating func append(_ scalar: Unicode.Scalar) {
            let value = scalar.value
            if value <= 0xFFFF {
                append(UInt16(value))
                return
            }
            let supplementary = value - 0x1_0000
            append(UInt16(0xD800 + (supplementary >> 10)))
            append(UInt16(0xDC00 + (supplementary & 0x3FF)))
        }
    }

    private struct WorkBudget {
        let limits: TextPaneStatusLimits
        var consumed = 0
        var sinceCancellationCheck = 0

        mutating func consume(_ units: Int) throws {
            let (newConsumed, overflow) = consumed.addingReportingOverflow(units)
            guard !overflow, newConsumed <= limits.maximumWorkUnits else {
                try Task.checkCancellation()
                throw TextPaneStatusError.workLimitExceeded(
                    maximumWorkUnits: limits.maximumWorkUnits
                )
            }
            consumed = newConsumed
            let (uncheckedUnits, uncheckedOverflow) = sinceCancellationCheck.addingReportingOverflow(
                units
            )
            if uncheckedOverflow {
                try Task.checkCancellation()
                sinceCancellationCheck = 0
            } else if uncheckedUnits >= limits.cancellationCheckInterval {
                try Task.checkCancellation()
                sinceCancellationCheck = uncheckedUnits % limits.cancellationCheckInterval
            } else {
                sinceCancellationCheck = uncheckedUnits
            }
        }

        func finish() throws {
            try Task.checkCancellation()
        }

        func checkCancellation() throws {
            try Task.checkCancellation()
        }
    }

    private static func validate(_ limits: TextPaneStatusLimits) throws {
        guard limits.maximumInputUTF16Length >= 0,
            limits.maximumWorkUnits >= 0,
            limits.maximumGraphemeUTF16Length > 0,
            limits.maximumReportedScalarsPerGrapheme >= 0,
            limits.cancellationCheckInterval > 0
        else {
            throw TextPaneStatusError.invalidLimits
        }
    }

    private static func validateMetadata(_ input: TextPaneStatusInput) throws {
        guard input.tabWidth > 0 else {
            throw TextPaneStatusError.invalidTabWidth(input.tabWidth)
        }
        guard input.caretUTF16Offset >= 0 else {
            throw TextPaneStatusError.invalidCaretUTF16Offset(input.caretUTF16Offset)
        }
        if input.hasByteOrderMark {
            switch input.encoding {
            case .utf8, .utf16LittleEndian, .utf16BigEndian:
                break
            case .shiftJIS, .japaneseEUC, .iso2022JP, .windows1250, .windows1251,
                .windows1252, .windows1253, .windows1254, .windows1255:
                throw TextPaneStatusError.invalidByteOrderMark(input.encoding)
            }
        }
    }

    private static func preflight(
        _ text: String,
        matching expectedText: String? = nil,
        work: inout WorkBudget
    ) throws -> TextPreflight {
        let limits = work.limits
        var utf16Length = 0
        var fingerprint = TextFingerprintBuilder()
        var graphemeUTF16Length = 0
        var recognizer = Unicode._CharacterRecognizer()
        let comparesExpectedText = expectedText != nil
        var expectedUTF16Iterator = (expectedText ?? "").utf16.makeIterator()
        var matchesExpectedText = true

        for scalar in text.unicodeScalars {
            let startsGrapheme = recognizer.hasBreak(before: scalar)
            if startsGrapheme { graphemeUTF16Length = 0 }
            let scalarUTF16Length = scalar.value > 0xFFFF ? 2 : 1
            let (nextUTF16Length, overflow) = utf16Length.addingReportingOverflow(
                scalarUTF16Length
            )
            guard !overflow, nextUTF16Length <= limits.maximumInputUTF16Length else {
                throw TextPaneStatusError.inputTooLarge(
                    maximumUTF16Length: limits.maximumInputUTF16Length
                )
            }

            try work.consume(scalarUTF16Length)
            if comparesExpectedText, matchesExpectedText {
                let value = scalar.value
                if value <= 0xFFFF {
                    matchesExpectedText = expectedUTF16Iterator.next() == UInt16(value)
                } else {
                    let supplementary = value - 0x1_0000
                    matchesExpectedText =
                        expectedUTF16Iterator.next()
                        == UInt16(0xD800 + (supplementary >> 10))
                        && expectedUTF16Iterator.next()
                            == UInt16(0xDC00 + (supplementary & 0x3FF))
                }
            }
            utf16Length = nextUTF16Length
            fingerprint.append(scalar)
            let (nextGraphemeUTF16Length, graphemeOverflow) =
                graphemeUTF16Length.addingReportingOverflow(scalarUTF16Length)
            guard !graphemeOverflow,
                nextGraphemeUTF16Length <= limits.maximumGraphemeUTF16Length
            else {
                throw TextPaneStatusError.graphemeTooLarge(
                    maximumUTF16Length: limits.maximumGraphemeUTF16Length
                )
            }
            graphemeUTF16Length = nextGraphemeUTF16Length
        }
        try work.finish()
        if comparesExpectedText, matchesExpectedText {
            let expectedHasRemainingText = expectedUTF16Iterator.next() != nil
            if expectedHasRemainingText {
                try work.consume(1)
                matchesExpectedText = false
            }
        }

        return TextPreflight(
            utf16Length: utf16Length,
            digestLow: fingerprint.low,
            digestHigh: fingerprint.high,
            matchesExpectedText: matchesExpectedText
        )
    }

    private static func snapshotFingerprint(
        input: TextPaneStatusInput,
        limits: TextPaneStatusLimits,
        preflight: TextPreflight,
        selectionUTF16Range: NSRange
    ) -> TextPaneStatusSnapshotFingerprint {
        TextPaneStatusSnapshotFingerprint(
            revision: input.revision,
            textUTF16Length: preflight.utf16Length,
            textDigestLow: preflight.digestLow,
            textDigestHigh: preflight.digestHigh,
            caretUTF16Offset: input.caretUTF16Offset,
            selectionUTF16Range: selectionUTF16Range,
            encoding: input.encoding,
            hasByteOrderMark: input.hasByteOrderMark,
            isReadOnly: input.isReadOnly,
            isDirty: input.isDirty,
            tabWidth: input.tabWidth,
            limits: limits,
            sourceIdentity: input.sourceIdentity
        )
    }

    private static func validatedSnapshotFingerprint(
        for input: TextPaneStatusInput,
        limits: TextPaneStatusLimits,
        matching expectedText: String?,
        work: inout WorkBudget
    ) throws -> ValidatedSnapshotFingerprint {
        try validateMetadata(input)
        let requestedSelection = try selectionRange(
            input.selectionUTF16Range,
            defaultOffset: input.caretUTF16Offset
        )
        let preflight = try preflight(input.text, matching: expectedText, work: &work)
        guard input.caretUTF16Offset <= preflight.utf16Length else {
            throw TextPaneStatusError.invalidCaretUTF16Offset(input.caretUTF16Offset)
        }
        guard requestedSelection.upperBound <= preflight.utf16Length else {
            throw TextPaneStatusError.invalidSelectionUTF16Range(requestedSelection.range)
        }
        try validateGraphemeBoundaries(
            in: input.text,
            caretUTF16Offset: input.caretUTF16Offset,
            selection: requestedSelection,
            work: &work
        )
        return ValidatedSnapshotFingerprint(
            fingerprint: snapshotFingerprint(
                input: input,
                limits: limits,
                preflight: preflight,
                selectionUTF16Range: requestedSelection.range
            ),
            matchesExpectedText: preflight.matchesExpectedText
        )
    }

    private static func fingerprintsMatch(
        _ lhs: TextPaneStatusSnapshotFingerprint,
        _ rhs: TextPaneStatusSnapshotFingerprint,
        knownExactTextMatch: Bool?,
        work: inout WorkBudget
    ) throws -> Bool {
        try work.checkCancellation()
        guard lhs.revision == rhs.revision,
            lhs.textUTF16Length == rhs.textUTF16Length,
            lhs.textDigestLow == rhs.textDigestLow,
            lhs.textDigestHigh == rhs.textDigestHigh,
            lhs.caretUTF16Offset == rhs.caretUTF16Offset,
            lhs.selectionUTF16Range == rhs.selectionUTF16Range,
            lhs.encoding == rhs.encoding,
            lhs.hasByteOrderMark == rhs.hasByteOrderMark,
            lhs.isReadOnly == rhs.isReadOnly,
            lhs.isDirty == rhs.isDirty,
            lhs.tabWidth == rhs.tabWidth,
            lhs.limits == rhs.limits
        else {
            return false
        }
        if let knownExactTextMatch {
            return knownExactTextMatch
        }

        var leftIterator = lhs.sourceIdentity.text.utf16.makeIterator()
        var rightIterator = rhs.sourceIdentity.text.utf16.makeIterator()
        while let left = leftIterator.next() {
            try work.consume(1)
            guard left == rightIterator.next() else { return false }
        }
        try work.finish()
        return rightIterator.next() == nil
    }

    private static func validateGraphemeBoundaries(
        in text: String,
        caretUTF16Offset: Int,
        selection: RequestedSelection,
        work: inout WorkBudget
    ) throws {
        var offset = 0
        var foundCaret = caretUTF16Offset == 0
        var foundSelectionStart = selection.lowerBound == 0
        var foundSelectionEnd = selection.upperBound == 0
        var scanner = InterruptibleGraphemeScanner(text)
        while let grapheme = try scanner.next(
            capturingDetailsAt: nil,
            maximumReportedScalars: 0,
            work: &work
        ) {
            offset += grapheme.utf16Count
            foundCaret = foundCaret || caretUTF16Offset == offset
            foundSelectionStart = foundSelectionStart || selection.lowerBound == offset
            foundSelectionEnd = foundSelectionEnd || selection.upperBound == offset
        }
        try work.finish()
        guard foundCaret else {
            throw TextPaneStatusError.utf16OffsetSplitsGrapheme(caretUTF16Offset)
        }
        guard foundSelectionStart else {
            throw TextPaneStatusError.utf16OffsetSplitsGrapheme(selection.lowerBound)
        }
        guard foundSelectionEnd else {
            throw TextPaneStatusError.utf16OffsetSplitsGrapheme(selection.upperBound)
        }
    }

    private static func selectionRange(
        _ range: NSRange?,
        defaultOffset: Int
    ) throws -> RequestedSelection {
        let range = range ?? NSRange(location: defaultOffset, length: 0)
        guard range.location >= 0, range.length >= 0 else {
            throw TextPaneStatusError.invalidSelectionUTF16Range(range)
        }
        let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
        guard !overflow else {
            throw TextPaneStatusError.invalidSelectionUTF16Range(range)
        }
        return RequestedSelection(
            range: range,
            lowerBound: range.location,
            upperBound: upperBound
        )
    }

    private static func scalarStatus(_ scalar: Unicode.Scalar) -> TextPaneUnicodeScalarStatus {
        let codePoint = codePoint(scalar.value)
        let name = scalarName(scalar)
        return TextPaneUnicodeScalarStatus(
            value: scalar.value,
            codePoint: codePoint,
            name: name,
            accessibilityLabel: name.map { "\(codePoint), \($0)" } ?? "\(codePoint), unnamed Unicode scalar"
        )
    }

    private static func scalarName(_ scalar: Unicode.Scalar) -> String? {
        switch scalar.value {
        case 0x09:
            "CHARACTER TABULATION"
        case 0x0A:
            "LINE FEED"
        case 0x0D:
            "CARRIAGE RETURN"
        case 0x20:
            "SPACE"
        default:
            scalar.properties.name
        }
    }

    private static func codePoint(_ value: UInt32) -> String {
        let hexadecimal = String(value, radix: 16, uppercase: true)
        let padding = String(repeating: "0", count: max(0, 4 - hexadecimal.count))
        return "U+\(padding)\(hexadecimal)"
    }

    private static func characterStatus(
        _ characterText: String,
        kind: GraphemeKind,
        utf16Count: Int,
        scalarCount: Int,
        reportedScalars: [TextPaneUnicodeScalarStatus]
    ) -> TextPaneCharacterStatus {
        let displayName: String
        switch kind {
        case .tab:
            displayName = "Tab"
        case .crlf:
            displayName = "Carriage return and line feed"
        case .lf:
            displayName = "Line feed"
        case .cr:
            displayName = "Carriage return"
        case .other:
            displayName = characterText == " " ? "Space" : characterText
        }
        let truncated = reportedScalars.count < scalarCount
        let scalarLabels = reportedScalars.map(\.accessibilityLabel).joined(separator: ", ")
        let scalarDescription =
            scalarLabels.isEmpty
            ? "\(scalarCount) Unicode \(scalarCount == 1 ? "scalar" : "scalars")"
            : scalarLabels
        let truncationSuffix =
            truncated
            ? ", first \(reportedScalars.count) of \(scalarCount) Unicode scalars shown"
            : ""
        let accessibilityLabel = "Character \(displayName); \(scalarDescription)\(truncationSuffix)"
        return TextPaneCharacterStatus(
            character: characterText,
            displayName: displayName,
            unicodeScalarCount: scalarCount,
            utf16Count: utf16Count,
            scalars: reportedScalars,
            areScalarsTruncated: truncated,
            accessibilityLabel: accessibilityLabel
        )
    }

    private static func dominantLineEnding(
        occurrenceOrder: [LineEnding],
        crlfCount: Int,
        lfCount: Int,
        crCount: Int
    ) -> LineEnding? {
        let maximumCount = max(crlfCount, lfCount, crCount)
        guard maximumCount > 0 else { return nil }
        return occurrenceOrder.first { ending in
            switch ending {
            case .crlf:
                crlfCount == maximumCount
            case .lf:
                lfCount == maximumCount
            case .cr:
                crCount == maximumCount
            }
        }
    }

    private static func labels(
        position: TextPanePositionStatus,
        character: TextPaneCharacterStatus?,
        selection: TextPaneSelectionStatus,
        encoding: TextFileEncoding,
        hasByteOrderMark: Bool,
        lineEndings: TextPaneLineEndingSummary,
        isReadOnly: Bool,
        isDirty: Bool
    ) -> TextPaneStatusLabels {
        let positionLabel = "Line \(position.line), logical column \(position.logicalColumn), visual column \(position.visualColumn)"
        let characterLabel = character?.accessibilityLabel ?? "No character at insertion point"
        let selectionLabel: String
        if selection.isEmpty {
            selectionLabel = "No selection"
        } else {
            let graphemeWord = selection.graphemeCount == 1 ? "grapheme" : "graphemes"
            let scalarWord = selection.unicodeScalarCount == 1 ? "Unicode scalar" : "Unicode scalars"
            let unitWord = selection.utf16Count == 1 ? "UTF-16 unit" : "UTF-16 units"
            let lineWord = selection.lineCount == 1 ? "line" : "lines"
            selectionLabel =
                "\(selection.graphemeCount) \(graphemeWord), \(selection.unicodeScalarCount) \(scalarWord), "
                + "\(selection.utf16Count) \(unitWord) selected across \(selection.lineCount) \(lineWord)"
        }
        let byteOrderMarkLabel =
            hasByteOrderMark
            ? "with byte-order mark"
            : "without byte-order mark"
        let encodingLabel = "Encoding: \(encoding.displayName), \(byteOrderMarkLabel)"
        let documentStateLabel = "\(isReadOnly ? "Read only" : "Editable"), \(isDirty ? "modified" : "unmodified")"
        let combined = [
            positionLabel,
            characterLabel,
            selectionLabel,
            encodingLabel,
            lineEndings.accessibilityLabel,
            documentStateLabel
        ].joined(separator: ". ")
        return TextPaneStatusLabels(
            position: positionLabel,
            character: characterLabel,
            selection: selectionLabel,
            encoding: encodingLabel,
            lineEndings: lineEndings.accessibilityLabel,
            documentState: documentStateLabel,
            combined: combined
        )
    }

    private static func visualColumn(
        after kind: GraphemeKind,
        from column: Int,
        tabWidth: Int
    ) -> Int {
        let advance = kind == .tab ? tabWidth - (column - 1) % tabWidth : 1
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
