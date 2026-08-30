import Foundation

public struct TextGoToDocumentIdentity: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        rawValue = UUID()
    }
}

/// One difference destination in document coordinates. Array order defines its one-based index.
public struct TextGoToDifference: Equatable, Sendable {
    /// Zero-based, half-open UTF-16 range. Both bounds must be grapheme boundaries.
    public let selectionRange: NSRange

    public init(selectionRange: NSRange) {
        self.selectionRange = selectionRange
    }
}

/// Immutable state used to resolve a Go To request.
/// For one `identity`, the owner must use `revision` as an opaque, never-reused token and change it
/// whenever text, differences, or bookmarks change. Undo and content reversion still require a new
/// token; before the token space wraps, the owner must assign a new document identity.
public struct TextGoToDocumentSnapshot: Sendable {
    public let identity: TextGoToDocumentIdentity
    /// Never-reused snapshot token within `identity`; values need not be consecutive.
    public let revision: UInt64
    public let text: String
    public let differences: [TextGoToDifference]
    public let bookmarks: LineBookmarks

    public init(
        identity: TextGoToDocumentIdentity,
        revision: UInt64,
        text: String,
        differences: [TextGoToDifference] = [],
        bookmarks: LineBookmarks = LineBookmarks()
    ) {
        self.identity = identity
        self.revision = revision
        self.text = text
        self.differences = differences
        self.bookmarks = bookmarks
    }
}

public enum TextGoToTarget: Equatable, Sendable {
    /// One-based line and extended-grapheme-cluster column.
    case line(TextPosition)
    /// Percentage from the first line (0) through the last line (100).
    case percent(Double)
    /// One-based index in `TextGoToDocumentSnapshot.differences`.
    case difference(Int)
    /// One-based document line that must currently be bookmarked.
    case bookmark(line: Int)
    /// Zero-based UTF-16 offset in the complete document.
    case utf16Offset(Int)
}

public struct TextGoToRequest: Equatable, Sendable {
    public let documentIdentity: TextGoToDocumentIdentity
    /// Opaque snapshot token copied from `TextGoToDocumentSnapshot.revision`.
    public let documentRevision: UInt64
    public let target: TextGoToTarget

    public init(
        documentIdentity: TextGoToDocumentIdentity,
        documentRevision: UInt64,
        target: TextGoToTarget
    ) {
        self.documentIdentity = documentIdentity
        self.documentRevision = documentRevision
        self.target = target
    }

    public init(document: TextGoToDocumentSnapshot, target: TextGoToTarget) {
        documentIdentity = document.identity
        documentRevision = document.revision
        self.target = target
    }
}

public struct TextGoToLimits: Equatable, Sendable {
    public static let `default` = TextGoToLimits()

    public let navigation: TextNavigationLimits
    public let maximumDifferences: Int
    public let maximumBookmarks: Int
    /// Rejects a single extended grapheme cluster above this UTF-16 length.
    public let maximumGraphemeClusterUTF16Length: Int
    /// Bounds UTF-16 validation, line indexing, location resolution, and metadata visits.
    public let maximumWork: Int

    public init(
        navigation: TextNavigationLimits = .default,
        maximumDifferences: Int = 1_000_000,
        maximumBookmarks: Int = 100_000,
        maximumGraphemeClusterUTF16Length: Int = 16 * 1024,
        maximumWork: Int = 320 * 1024 * 1024
    ) {
        self.navigation = navigation
        self.maximumDifferences = maximumDifferences
        self.maximumBookmarks = maximumBookmarks
        self.maximumGraphemeClusterUTF16Length = maximumGraphemeClusterUTF16Length
        self.maximumWork = maximumWork
    }
}

public enum TextGoToResolvedTarget: Equatable, Sendable {
    case line(requested: TextPosition)
    case percent(requested: Double, resolvedLine: Int)
    case difference(index: Int)
    case bookmark(line: Int)
    case utf16Offset(Int)
}

/// Deterministic document coordinates only; scrolling, focus, and pane activation remain UI policy.
public struct TextGoToResolution: Equatable, Sendable {
    public let documentIdentity: TextGoToDocumentIdentity
    public let documentRevision: UInt64
    public let target: TextGoToResolvedTarget
    /// Zero-based, half-open UTF-16 selection suitable for Cocoa text storage.
    public let selectionRange: NSRange
    public let selectionStart: TextLocation
    /// Location of the half-open selection end; equals `selectionStart` for an insertion point.
    public let selectionEnd: TextLocation
    public let workUnitsConsumed: Int

    public var isInsertionPoint: Bool { selectionRange.length == 0 }
    public var position: TextPosition { selectionStart.position }

    fileprivate init(
        documentIdentity: TextGoToDocumentIdentity,
        documentRevision: UInt64,
        target: TextGoToResolvedTarget,
        selectionRange: NSRange,
        selectionStart: TextLocation,
        selectionEnd: TextLocation,
        workUnitsConsumed: Int
    ) {
        self.documentIdentity = documentIdentity
        self.documentRevision = documentRevision
        self.target = target
        self.selectionRange = selectionRange
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
        self.workUnitsConsumed = workUnitsConsumed
    }
}

public enum TextGoToError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case documentIdentityChanged(
        expected: TextGoToDocumentIdentity,
        actual: TextGoToDocumentIdentity
    )
    case documentRevisionChanged(expected: UInt64, actual: UInt64)
    case tooManyDifferences(maximumDifferences: Int)
    case tooManyBookmarks(maximumBookmarks: Int)
    case nonFinitePercent
    case percentOutsideRange(Double)
    case invalidDifferenceIndex(index: Int, differenceCount: Int)
    case invalidDifferenceRange(index: Int, location: Int, length: Int)
    case lineIsNotBookmarked(Int)
    case graphemeSegmentationTooComplex(maximumClusterUTF16Length: Int)
    case workLimitExceeded(maximumWork: Int)
    case navigation(TextNavigationError)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Go To limits are invalid."
        case .documentIdentityChanged:
            "The Go To request belongs to another document."
        case .documentRevisionChanged(let expected, let actual):
            "The Go To request was created for revision \(expected), not revision \(actual)."
        case .tooManyDifferences(let maximumDifferences):
            "Go To difference metadata exceeds the \(maximumDifferences)-difference limit."
        case .tooManyBookmarks(let maximumBookmarks):
            "Go To bookmark metadata exceeds the \(maximumBookmarks)-bookmark limit."
        case .nonFinitePercent:
            "Go To percentage must be finite."
        case .percentOutsideRange(let percent):
            "Go To percentage \(percent) is outside 0...100."
        case .invalidDifferenceIndex(let index, let differenceCount):
            "Difference index \(index) is outside 1...\(differenceCount)."
        case .invalidDifferenceRange(let index, let location, let length):
            "Difference \(index) has invalid UTF-16 range {\(location), \(length)}."
        case .lineIsNotBookmarked(let line):
            "Line \(line) is not bookmarked."
        case .graphemeSegmentationTooComplex(let maximumClusterUTF16Length):
            "Go To text contains an extended grapheme cluster exceeding the \(maximumClusterUTF16Length)-UTF-16-unit limit."
        case .workLimitExceeded(let maximumWork):
            "Go To resolution exceeds the \(maximumWork)-unit work limit."
        case .navigation(let error):
            error.localizedDescription
        }
    }
}

public enum TextGoTo {
    public static func resolve(
        _ request: TextGoToRequest,
        in document: TextGoToDocumentSnapshot,
        limits: TextGoToLimits = .default
    ) throws -> TextGoToResolution {
        try Task.checkCancellation()
        try validate(limits)
        guard request.documentIdentity == document.identity else {
            throw TextGoToError.documentIdentityChanged(
                expected: request.documentIdentity,
                actual: document.identity
            )
        }
        guard request.documentRevision == document.revision else {
            throw TextGoToError.documentRevisionChanged(
                expected: request.documentRevision,
                actual: document.revision
            )
        }
        guard document.differences.count <= limits.maximumDifferences else {
            throw TextGoToError.tooManyDifferences(
                maximumDifferences: limits.maximumDifferences
            )
        }
        guard document.bookmarks.count <= limits.maximumBookmarks else {
            throw TextGoToError.tooManyBookmarks(maximumBookmarks: limits.maximumBookmarks)
        }
        var work = TextGoToWorkBudget(maximum: limits.maximumWork)
        try validate(request.target, in: document, work: &work)
        let index = try TextGoToLineIndex(
            text: document.text,
            limits: limits.navigation,
            maximumGraphemeClusterUTF16Length: limits.maximumGraphemeClusterUTF16Length,
            work: &work
        )
        try Task.checkCancellation()

        let resolved = try resolveTarget(
            request.target,
            document: document,
            index: index,
            work: &work
        )
        try Task.checkCancellation()
        return TextGoToResolution(
            documentIdentity: document.identity,
            documentRevision: document.revision,
            target: resolved.target,
            selectionRange: resolved.range,
            selectionStart: resolved.start,
            selectionEnd: resolved.end,
            workUnitsConsumed: work.consumed
        )
    }

    private struct ResolvedSelection {
        let target: TextGoToResolvedTarget
        let range: NSRange
        let start: TextLocation
        let end: TextLocation
    }

    private static func resolveTarget(
        _ target: TextGoToTarget,
        document: TextGoToDocumentSnapshot,
        index: TextGoToLineIndex,
        work: inout TextGoToWorkBudget
    ) throws -> ResolvedSelection {
        switch target {
        case .line(let position):
            let location = try resolve(position, index: index, work: &work)
            return insertionPoint(
                at: location,
                target: .line(requested: position)
            )
        case .percent(let percent):
            let line = line(for: percent, lineCount: index.lineCount)
            let location = try resolve(
                TextPosition(line: line),
                index: index,
                work: &work
            )
            return insertionPoint(
                at: location,
                target: .percent(requested: percent, resolvedLine: line)
            )
        case .difference(let requestedIndex):
            try work.consume(1)
            let difference = document.differences[requestedIndex - 1]
            let range = difference.selectionRange
            let (endOffset, overflow) = range.location.addingReportingOverflow(range.length)
            guard !overflow, endOffset <= index.utf16Length else {
                throw TextGoToError.invalidDifferenceRange(
                    index: requestedIndex,
                    location: range.location,
                    length: range.length
                )
            }
            let start: TextLocation
            let end: TextLocation
            do {
                start = try index.location(atUTF16Offset: range.location, work: &work)
                end = try index.location(atUTF16Offset: endOffset, work: &work)
            } catch TextGoToError.navigation(.offsetSplitsCharacter) {
                throw TextGoToError.invalidDifferenceRange(
                    index: requestedIndex,
                    location: range.location,
                    length: range.length
                )
            }
            return ResolvedSelection(
                target: .difference(index: requestedIndex),
                range: range,
                start: start,
                end: end
            )
        case .bookmark(let line):
            let location = try resolve(
                TextPosition(line: line),
                index: index,
                work: &work
            )
            return insertionPoint(at: location, target: .bookmark(line: line))
        case .utf16Offset(let offset):
            let location = try index.location(atUTF16Offset: offset, work: &work)
            return insertionPoint(at: location, target: .utf16Offset(offset))
        }
    }

    private static func insertionPoint(
        at location: TextLocation,
        target: TextGoToResolvedTarget
    ) -> ResolvedSelection {
        ResolvedSelection(
            target: target,
            range: NSRange(location: location.utf16Offset, length: 0),
            start: location,
            end: location
        )
    }

    private static func resolve(
        _ position: TextPosition,
        index: TextGoToLineIndex,
        work: inout TextGoToWorkBudget
    ) throws -> TextLocation {
        try index.location(at: position, work: &work)
    }

    private static func line(for percent: Double, lineCount: Int) -> Int {
        guard percent > 0 else { return 1 }
        guard percent < 100 else { return lineCount }

        let lastLineOffset = lineCount - 1
        let roundedOffset = (Double(lastLineOffset) * (percent / 100)).rounded()
        if roundedOffset >= Double(lastLineOffset) { return lineCount }
        return Int(roundedOffset) + 1
    }

    private static func validate(
        _ target: TextGoToTarget,
        in document: TextGoToDocumentSnapshot,
        work: inout TextGoToWorkBudget
    ) throws {
        switch target {
        case .line(let position):
            guard position.line > 0 else {
                throw TextGoToError.navigation(.invalidLine(position.line))
            }
            guard position.column > 0 else {
                throw TextGoToError.navigation(
                    .invalidColumn(line: position.line, column: position.column)
                )
            }
        case .percent(let percent):
            guard percent.isFinite else { throw TextGoToError.nonFinitePercent }
            guard (0...100).contains(percent) else {
                throw TextGoToError.percentOutsideRange(percent)
            }
        case .difference(let index):
            guard index > 0, index <= document.differences.count else {
                throw TextGoToError.invalidDifferenceIndex(
                    index: index,
                    differenceCount: document.differences.count
                )
            }
            try work.consume(1)
            let range = document.differences[index - 1].selectionRange
            let (_, overflow) = range.location.addingReportingOverflow(range.length)
            guard range.location >= 0,
                range.location != NSNotFound,
                range.length >= 0,
                !overflow
            else {
                throw TextGoToError.invalidDifferenceRange(
                    index: index,
                    location: range.location,
                    length: range.length
                )
            }
        case .bookmark(let line):
            guard line > 0 else {
                throw TextGoToError.navigation(.invalidLine(line))
            }
            try work.consume(1)
            guard document.bookmarks.contains(line: line) else {
                throw TextGoToError.lineIsNotBookmarked(line)
            }
        case .utf16Offset(let offset):
            guard offset >= 0 else {
                throw TextGoToError.navigation(.invalidUTF16Offset(offset))
            }
        }
    }

    private static func validate(_ limits: TextGoToLimits) throws {
        let navigation = limits.navigation
        guard navigation.maximumInputUTF16Length >= 0,
            navigation.maximumLineCount > 0,
            navigation.maximumLineUTF16Length >= 0,
            navigation.maximumTokenCount > 0,
            navigation.maximumSymbolCount >= 0,
            navigation.maximumSymbolNameUTF16Length > 0,
            navigation.maximumLookupResults > 0,
            limits.maximumDifferences >= 0,
            limits.maximumBookmarks >= 0,
            limits.maximumGraphemeClusterUTF16Length > 0,
            limits.maximumWork >= 0
        else {
            throw TextGoToError.invalidLimits
        }
    }

}

private struct TextGoToLineIndex {
    private struct Record {
        let startOffset: Int
        let contentEndOffset: Int
        let endOffset: Int
        let startIndex: String.Index
        let contentEndIndex: String.Index
    }

    let text: String
    private let maximumGraphemeClusterUTF16Length: Int
    private let records: [Record]

    var lineCount: Int { records.count }
    var utf16Length: Int { records.last?.endOffset ?? 0 }

    init(
        text: String,
        limits: TextNavigationLimits,
        maximumGraphemeClusterUTF16Length: Int,
        work: inout TextGoToWorkBudget
    ) throws {
        var records: [Record] = []
        records.reserveCapacity(min(limits.maximumLineCount, 4_096))
        let scalars = text.unicodeScalars
        var lineStartOffset = 0
        var lineStartIndex = scalars.startIndex
        var offset = 0
        var index = scalars.startIndex
        var uncheckedScanLength = 0

        while index < scalars.endIndex {
            try Self.checkCancellation(
                beforeScanningAtMost: 3,
                uncheckedLength: &uncheckedScanLength
            )
            let scalar = scalars[index]
            var next = scalars.index(after: index)
            var width = scalar.value > 0xFFFF ? 2 : 1
            var scannedLength = width
            if scalar.value == 0x0D, next < scalars.endIndex, scalars[next].value == 0x0A {
                next = scalars.index(after: next)
                width += 1
                scannedLength += 1
            } else if scalar.value == 0x0D, next < scalars.endIndex {
                scannedLength += scalars[next].value > 0xFFFF ? 2 : 1
            }
            guard width <= limits.maximumInputUTF16Length - offset else {
                throw TextGoToError.navigation(
                    .inputTooLarge(
                        maximumUTF16Length: limits.maximumInputUTF16Length
                    )
                )
            }
            Self.recordScan(scannedLength, uncheckedLength: &uncheckedScanLength)
            try work.consume(width)

            if scalar.value == 0x0A || scalar.value == 0x0D {
                try Self.append(
                    to: &records,
                    startOffset: lineStartOffset,
                    contentEndOffset: offset,
                    endOffset: offset + width,
                    startIndex: lineStartIndex,
                    contentEndIndex: index,
                    limits: limits
                )
                offset += width
                lineStartOffset = offset
                lineStartIndex = next
            } else {
                offset += width
                guard offset - lineStartOffset <= limits.maximumLineUTF16Length else {
                    throw TextGoToError.navigation(
                        .lineTooLong(
                            line: records.count + 1,
                            maximumUTF16Length: limits.maximumLineUTF16Length
                        )
                    )
                }
            }
            index = next
        }

        try Self.append(
            to: &records,
            startOffset: lineStartOffset,
            contentEndOffset: offset,
            endOffset: offset,
            startIndex: lineStartIndex,
            contentEndIndex: scalars.endIndex,
            limits: limits
        )
        try Task.checkCancellation()
        self.text = text
        self.maximumGraphemeClusterUTF16Length = maximumGraphemeClusterUTF16Length
        self.records = records
        try validateGraphemeClusters(work: &work)
    }

    func location(
        at position: TextPosition,
        work: inout TextGoToWorkBudget
    ) throws -> TextLocation {
        guard position.line > 0, position.line <= records.count else {
            throw TextGoToError.navigation(.invalidLine(position.line))
        }
        guard position.column > 0 else {
            throw TextGoToError.navigation(
                .invalidColumn(line: position.line, column: position.column)
            )
        }

        let record = records[position.line - 1]
        let resolved = try graphemeLocation(
            in: record,
            target: .column(position.column),
            work: &work
        )
        return TextLocation(
            position: position,
            utf16Column: resolved.offset - record.startOffset + 1,
            utf16Offset: resolved.offset
        )
    }

    func location(
        atUTF16Offset requestedOffset: Int,
        work: inout TextGoToWorkBudget
    ) throws -> TextLocation {
        guard requestedOffset >= 0, requestedOffset <= utf16Length else {
            throw TextGoToError.navigation(.invalidUTF16Offset(requestedOffset))
        }

        let recordIndex = recordIndex(containing: requestedOffset)
        let record = records[recordIndex]
        guard requestedOffset <= record.contentEndOffset else {
            throw TextGoToError.navigation(.offsetSplitsCharacter(requestedOffset))
        }

        let resolved = try graphemeLocation(
            in: record,
            target: .utf16Offset(requestedOffset),
            work: &work
        )
        return TextLocation(
            position: TextPosition(line: recordIndex + 1, column: resolved.column),
            utf16Column: requestedOffset - record.startOffset + 1,
            utf16Offset: requestedOffset
        )
    }

    private enum GraphemeTarget {
        case column(Int)
        case utf16Offset(Int)
    }

    private struct GraphemeLocation {
        let offset: Int
        let column: Int
    }

    private func validateGraphemeClusters(work: inout TextGoToWorkBudget) throws {
        var recognizer = Unicode._CharacterRecognizer()
        var clusterLength = 0
        var uncheckedScanLength = 0
        let scalars = text.unicodeScalars
        var scalarIndex = scalars.startIndex
        while scalarIndex < scalars.endIndex {
            try Self.checkCancellation(
                beforeScanningAtMost: 2,
                uncheckedLength: &uncheckedScanLength
            )
            let scalar = scalars[scalarIndex]
            let scalarLength = scalar.value > 0xFFFF ? 2 : 1
            Self.recordScan(scalarLength, uncheckedLength: &uncheckedScanLength)
            try work.consume(scalarLength)
            if recognizer.hasBreak(before: scalar) {
                try validateGraphemeCluster(length: clusterLength)
                clusterLength = 0
            }
            clusterLength += scalarLength
            try validateGraphemeCluster(length: clusterLength)
            scalarIndex = scalars.index(after: scalarIndex)
        }
        try validateGraphemeCluster(length: clusterLength)
    }

    private func validateGraphemeCluster(length: Int) throws {
        guard length <= maximumGraphemeClusterUTF16Length else {
            try Task.checkCancellation()
            throw TextGoToError.graphemeSegmentationTooComplex(
                maximumClusterUTF16Length: maximumGraphemeClusterUTF16Length
            )
        }
    }

    private func graphemeLocation(
        in record: Record,
        target: GraphemeTarget,
        work: inout TextGoToWorkBudget
    ) throws -> GraphemeLocation {
        var location = GraphemeLocation(offset: record.startOffset, column: 1)
        if Self.matches(location, target: target) { return location }

        try work.consume(record.contentEndOffset - record.startOffset)
        var recognizer = Unicode._CharacterRecognizer()
        var offset = record.startOffset
        var uncheckedLength = 0
        let scalars = text.unicodeScalars
        var scalarIndex = record.startIndex
        let scalarEnd = record.contentEndIndex

        while scalarIndex < scalarEnd {
            try Self.checkCancellation(
                beforeScanningAtMost: 2,
                uncheckedLength: &uncheckedLength
            )
            let scalar = scalars[scalarIndex]
            let scalarLength = scalar.value > 0xFFFF ? 2 : 1
            Self.recordScan(scalarLength, uncheckedLength: &uncheckedLength)
            if recognizer.hasBreak(before: scalar), offset > record.startOffset {
                location = GraphemeLocation(offset: offset, column: location.column + 1)
                if Self.matches(location, target: target) { return location }
            }
            offset += scalarLength
            scalarIndex = scalars.index(after: scalarIndex)
        }

        if offset > record.startOffset {
            location = GraphemeLocation(offset: offset, column: location.column + 1)
            if Self.matches(location, target: target) { return location }
        }

        switch target {
        case .column(let column):
            throw TextGoToError.navigation(
                .invalidColumn(line: recordIndex(containing: record.startOffset) + 1, column: column)
            )
        case .utf16Offset(let offset):
            throw TextGoToError.navigation(.offsetSplitsCharacter(offset))
        }
    }

    private static func matches(_ location: GraphemeLocation, target: GraphemeTarget) -> Bool {
        switch target {
        case .column(let column):
            location.column == column
        case .utf16Offset(let offset):
            location.offset == offset
        }
    }

    private func recordIndex(containing offset: Int) -> Int {
        var lower = records.startIndex
        var upper = records.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if records[middle].startOffset <= offset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return max(records.startIndex, lower - 1)
    }

    private static func append(
        to records: inout [Record],
        startOffset: Int,
        contentEndOffset: Int,
        endOffset: Int,
        startIndex: String.Index,
        contentEndIndex: String.Index,
        limits: TextNavigationLimits
    ) throws {
        guard records.count < limits.maximumLineCount else {
            throw TextGoToError.navigation(
                .tooManyLines(maximumLines: limits.maximumLineCount)
            )
        }
        guard contentEndOffset - startOffset <= limits.maximumLineUTF16Length else {
            throw TextGoToError.navigation(
                .lineTooLong(
                    line: records.count + 1,
                    maximumUTF16Length: limits.maximumLineUTF16Length
                )
            )
        }
        records.append(
            Record(
                startOffset: startOffset,
                contentEndOffset: contentEndOffset,
                endOffset: endOffset,
                startIndex: startIndex,
                contentEndIndex: contentEndIndex
            )
        )
    }

    private static func checkCancellation(
        beforeScanningAtMost maximumLength: Int,
        uncheckedLength: inout Int
    ) throws {
        let interval = 4_096
        precondition((0...interval).contains(maximumLength))
        if maximumLength > interval - uncheckedLength {
            uncheckedLength = 0
            try Task.checkCancellation()
        }
    }

    private static func recordScan(_ length: Int, uncheckedLength: inout Int) {
        precondition(length >= 0 && length <= 4_096 - uncheckedLength)
        uncheckedLength += length
    }
}

private struct TextGoToWorkBudget {
    let maximum: Int
    private(set) var consumed = 0
    private var uncheckedWork = 0

    init(maximum: Int) {
        self.maximum = maximum
    }

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= maximum - consumed else {
            throw TextGoToError.workLimitExceeded(maximumWork: maximum)
        }
        consumed += amount
        let interval = 4_096
        let distanceToCheck = interval - uncheckedWork
        if amount >= distanceToCheck {
            uncheckedWork = (amount - distanceToCheck) % interval
            try Task.checkCancellation()
        } else {
            uncheckedWork += amount
        }
    }
}
