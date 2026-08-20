import Foundation

public enum AutomaticTextMergeDirection: Equatable, Hashable, Sendable {
    case intoLeft
    case intoMiddle
    case intoRight

    public init(destination: MergeCommandPolicy.Side) {
        switch destination {
        case .left:
            self = .intoLeft
        case .middle:
            self = .intoMiddle
        case .right:
            self = .intoRight
        }
    }

    public var destination: MergeCommandPolicy.Side {
        switch self {
        case .intoLeft: .left
        case .intoMiddle: .middle
        case .intoRight: .right
        }
    }
}

public struct AutomaticTextMergePolicy: Equatable, Sendable {
    public static let defaultMaximumRows = 3 * 1_048_576 + 1
    public static let defaultMaximumAppliedRanges = 1_048_576
    public static let defaultMaximumWorkUnits = 2 * 1_024 * 1_024 * 1_024
    public static let defaultMaximumOutputBytes = TextFileDocumentIO.maximumFileSize
    public static let defaultMaximumOutputLines = 1_048_576

    public let destinationIsEditable: Bool
    public let maximumRows: Int
    public let maximumAppliedRanges: Int
    /// Bounds line and UTF-8 byte visits performed outside the bounded diff engine.
    public let maximumWorkUnits: Int
    public let maximumOutputBytes: Int
    public let maximumOutputLines: Int

    public init(
        destinationIsEditable: Bool,
        maximumRows: Int = Self.defaultMaximumRows,
        maximumAppliedRanges: Int = Self.defaultMaximumAppliedRanges,
        maximumWorkUnits: Int = Self.defaultMaximumWorkUnits,
        maximumOutputBytes: Int = Self.defaultMaximumOutputBytes,
        maximumOutputLines: Int = Self.defaultMaximumOutputLines
    ) {
        precondition(maximumRows >= 0, "Maximum row count must not be negative")
        precondition(maximumAppliedRanges >= 0, "Maximum applied range count must not be negative")
        precondition(maximumWorkUnits >= 0, "Maximum work must not be negative")
        precondition(maximumOutputBytes >= 0, "Maximum output size must not be negative")
        precondition(maximumOutputLines >= 0, "Maximum output line count must not be negative")
        self.destinationIsEditable = destinationIsEditable
        self.maximumRows = maximumRows
        self.maximumAppliedRanges = maximumAppliedRanges
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumOutputLines = maximumOutputLines
    }
}

public enum AutomaticTextMergeError: Error, LocalizedError, Equatable, Sendable {
    case destinationReadOnly(MergeCommandPolicy.Side)
    case ambiguousComparison
    case tooManyRows(maximumRows: Int)
    case tooManyAppliedRanges(maximumRanges: Int)
    case workLimitExceeded(maximumWorkUnits: Int)
    case outputTooLarge(maximumBytes: Int)
    case tooManyOutputLines(maximumLines: Int)

    public var errorDescription: String? {
        switch self {
        case .destinationReadOnly(let side):
            "Automatic merge destination \(side) is read-only."
        case .ambiguousComparison:
            "Automatic merge comparison rows do not unambiguously describe the source documents."
        case .tooManyRows(let maximumRows):
            "Automatic merge exceeds the \(maximumRows)-row limit."
        case .tooManyAppliedRanges(let maximumRanges):
            "Automatic merge exceeds the \(maximumRanges)-applied-range limit."
        case .workLimitExceeded(let maximumWorkUnits):
            "Automatic merge exceeds the \(maximumWorkUnits)-unit work limit."
        case .outputTooLarge(let maximumBytes):
            "Automatic merge output exceeds the \(maximumBytes)-byte limit."
        case .tooManyOutputLines(let maximumLines):
            "Automatic merge output exceeds the \(maximumLines)-line limit."
        }
    }
}

public struct AutomaticTextMergeRange: Equatable, Hashable, Sendable {
    public let rowID: Int
    public let baseRange: Range<Int>
    public let leftRange: Range<Int>
    public let rightRange: Range<Int>

    public init(
        rowID: Int,
        baseRange: Range<Int>,
        leftRange: Range<Int>,
        rightRange: Range<Int>
    ) {
        self.rowID = rowID
        self.baseRange = baseRange
        self.leftRange = leftRange
        self.rightRange = rightRange
    }
}

public struct AutomaticTextMergeAppliedRange: Equatable, Hashable, Sendable {
    public let range: AutomaticTextMergeRange
    public let source: ThreeWayTextMergeSource

    public init(range: AutomaticTextMergeRange, source: ThreeWayTextMergeSource) {
        self.range = range
        self.source = source
    }
}

public struct AutomaticTextMergeResult: Equatable, Sendable {
    public let text: String
    /// Applied ranges in deterministic end-to-start application order.
    public let appliedRanges: [AutomaticTextMergeAppliedRange]
    public let skippedRanges: [AutomaticTextMergeRange]
    public let conflictedRanges: [AutomaticTextMergeRange]

    public var changed: Bool { !appliedRanges.isEmpty }

    public init(
        text: String,
        appliedRanges: [AutomaticTextMergeAppliedRange],
        skippedRanges: [AutomaticTextMergeRange],
        conflictedRanges: [AutomaticTextMergeRange]
    ) {
        self.text = text
        self.appliedRanges = appliedRanges
        self.skippedRanges = skippedRanges
        self.conflictedRanges = conflictedRanges
    }
}

public enum AutomaticTextMerge: Sendable {
    public static func apply(
        comparison: ThreeWayTextMergeResult,
        direction: AutomaticTextMergeDirection,
        policy: AutomaticTextMergePolicy
    ) throws -> AutomaticTextMergeResult {
        try apply(
            rows: comparison.regions,
            base: comparison.base,
            left: comparison.left,
            right: comparison.right,
            direction: direction,
            policy: policy
        )
    }

    /// Applies only ranges with one unambiguous source. Inputs must be one complete,
    /// ordered snapshot produced from the supplied three-way documents.
    public static func apply(
        rows: [ThreeWayTextMergeRegion],
        base: ThreeWayTextMergeDocument,
        left: ThreeWayTextMergeDocument,
        right: ThreeWayTextMergeDocument,
        direction: AutomaticTextMergeDirection,
        policy: AutomaticTextMergePolicy
    ) throws -> AutomaticTextMergeResult {
        try Task.checkCancellation()
        guard policy.destinationIsEditable else {
            throw AutomaticTextMergeError.destinationReadOnly(direction.destination)
        }
        guard rows.count <= policy.maximumRows else {
            throw AutomaticTextMergeError.tooManyRows(maximumRows: policy.maximumRows)
        }

        var work = WorkBudget(maximum: policy.maximumWorkUnits)
        try validate(rows: rows, base: base, left: left, right: right, work: &work)

        let destination = document(
            for: destinationSource(for: direction),
            base: base,
            left: left,
            right: right
        )
        var selections: [Selection] = []
        var skippedRanges: [AutomaticTextMergeRange] = []
        var conflictedRanges: [AutomaticTextMergeRange] = []
        selections.reserveCapacity(min(rows.count, policy.maximumAppliedRanges))

        for (index, row) in rows.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            try work.add(1)
            let reportedRange = range(for: row)
            if row.isConflict {
                conflictedRanges.append(reportedRange)
                continue
            }
            guard let source = mergeSource(for: row.resolution, direction: direction) else {
                skippedRanges.append(reportedRange)
                continue
            }
            let sourceDocument = document(for: source, base: base, left: left, right: right)
            let sourceRange = lineRange(for: row, source: source)
            let destinationRange = lineRange(for: row, source: destination.source)
            if try contentsAreEqual(
                sourceDocument.lines[sourceRange],
                destination.lines[destinationRange],
                work: &work
            ) {
                skippedRanges.append(reportedRange)
                continue
            }
            guard selections.count < policy.maximumAppliedRanges else {
                throw AutomaticTextMergeError.tooManyAppliedRanges(
                    maximumRanges: policy.maximumAppliedRanges
                )
            }
            selections.append(Selection(
                reportedRange: reportedRange,
                destinationRange: destinationRange,
                source: source,
                sourceRange: sourceRange
            ))
        }

        selections.sort { leftSelection, rightSelection in
            if leftSelection.destinationRange.lowerBound != rightSelection.destinationRange.lowerBound {
                return leftSelection.destinationRange.lowerBound > rightSelection.destinationRange.lowerBound
            }
            if leftSelection.destinationRange.upperBound != rightSelection.destinationRange.upperBound {
                return leftSelection.destinationRange.upperBound > rightSelection.destinationRange.upperBound
            }
            return leftSelection.reportedRange.rowID > rightSelection.reportedRange.rowID
        }

        guard !selections.isEmpty else {
            try enforceOutputBounds(
                text: destination.text,
                lineCount: destination.lines.count,
                policy: policy,
                work: &work
            )
            return AutomaticTextMergeResult(
                text: destination.text,
                appliedRanges: [],
                skippedRanges: skippedRanges,
                conflictedRanges: conflictedRanges
            )
        }

        let outputLineCount = try prospectiveLineCount(
            destinationCount: destination.lines.count,
            selections: selections,
            policy: policy
        )
        let mergedLines = try appliedLines(
            destination: destination,
            selections: selections,
            base: base,
            left: left,
            right: right,
            outputLineCount: outputLineCount,
            work: &work
        )
        let semanticText = try semanticText(
            from: mergedLines,
            maximumBytes: policy.maximumOutputBytes,
            work: &work
        )
        let semanticByteCount = semanticText.utf8.count
        guard outputLineCount <= policy.maximumOutputBytes - semanticByteCount else {
            throw AutomaticTextMergeError.outputTooLarge(maximumBytes: policy.maximumOutputBytes)
        }
        try work.add(try measuredUTF8Count(of: destination.text, work: &work))
        try work.add(semanticByteCount)
        try Task.checkCancellation()

        let options = LineDiffOptions(
            ignoreLineEndings: true,
            lineFiltersEnabled: false,
            substitutionsEnabled: false
        )
        let mergedText: String
        do {
            mergedText = try LineMerge.applyAll(
                direction: .leftToRight,
                left: semanticText,
                right: destination.text,
                options: options
            )?.right ?? destination.text
        } catch LineDiffError.inputTooLarge {
            throw AutomaticTextMergeError.outputTooLarge(maximumBytes: policy.maximumOutputBytes)
        } catch LineDiffError.tooManyLines {
            throw AutomaticTextMergeError.tooManyOutputLines(maximumLines: policy.maximumOutputLines)
        }
        try enforceOutputBounds(
            text: mergedText,
            lineCount: outputLineCount,
            policy: policy,
            work: &work
        )

        return AutomaticTextMergeResult(
            text: mergedText,
            appliedRanges: selections.map {
                AutomaticTextMergeAppliedRange(range: $0.reportedRange, source: $0.source)
            },
            skippedRanges: skippedRanges,
            conflictedRanges: conflictedRanges
        )
    }

    private struct Selection {
        let reportedRange: AutomaticTextMergeRange
        let destinationRange: Range<Int>
        let source: ThreeWayTextMergeSource
        let sourceRange: Range<Int>
    }

    private struct WorkBudget {
        let maximum: Int
        var used = 0

        mutating func add(_ count: Int) throws {
            guard count >= 0, count <= maximum - used else {
                throw AutomaticTextMergeError.workLimitExceeded(maximumWorkUnits: maximum)
            }
            used += count
        }
    }

    private static func validate(
        rows: [ThreeWayTextMergeRegion],
        base: ThreeWayTextMergeDocument,
        left: ThreeWayTextMergeDocument,
        right: ThreeWayTextMergeDocument,
        work: inout WorkBudget
    ) throws {
        guard base.source == .base, left.source == .left, right.source == .right else {
            throw AutomaticTextMergeError.ambiguousComparison
        }
        var basePosition = 0
        var leftPosition = 0
        var rightPosition = 0
        for (index, row) in rows.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            try work.add(1)
            guard row.id == index,
                row.baseRange.lowerBound == basePosition,
                row.leftRange.lowerBound == leftPosition,
                row.rightRange.lowerBound == rightPosition,
                row.baseRange.upperBound <= base.lines.count,
                row.leftRange.upperBound <= left.lines.count,
                row.rightRange.upperBound <= right.lines.count,
                try linesAreEqual(row.baseLines[...], base.lines[row.baseRange], work: &work),
                try linesAreEqual(row.leftLines[...], left.lines[row.leftRange], work: &work),
                try linesAreEqual(row.rightLines[...], right.lines[row.rightRange], work: &work)
            else {
                throw AutomaticTextMergeError.ambiguousComparison
            }
            basePosition = row.baseRange.upperBound
            leftPosition = row.leftRange.upperBound
            rightPosition = row.rightRange.upperBound
        }
        guard basePosition == base.lines.count,
            leftPosition == left.lines.count,
            rightPosition == right.lines.count
        else {
            throw AutomaticTextMergeError.ambiguousComparison
        }
    }

    private static func mergeSource(
        for resolution: ThreeWayTextMergeResolution,
        direction: AutomaticTextMergeDirection
    ) -> ThreeWayTextMergeSource? {
        switch direction {
        case .intoMiddle:
            switch resolution {
            case .left, .identical: .left
            case .right: .right
            case .unchanged, .conflict: nil
            }
        case .intoLeft, .intoRight:
            resolution == .identical ? .base : nil
        }
    }

    private static func destinationSource(
        for direction: AutomaticTextMergeDirection
    ) -> ThreeWayTextMergeSource {
        switch direction {
        case .intoLeft: .left
        case .intoMiddle: .base
        case .intoRight: .right
        }
    }

    private static func document(
        for source: ThreeWayTextMergeSource,
        base: ThreeWayTextMergeDocument,
        left: ThreeWayTextMergeDocument,
        right: ThreeWayTextMergeDocument
    ) -> ThreeWayTextMergeDocument {
        switch source {
        case .base: base
        case .left: left
        case .right: right
        }
    }

    private static func lineRange(
        for row: ThreeWayTextMergeRegion,
        source: ThreeWayTextMergeSource
    ) -> Range<Int> {
        switch source {
        case .base: row.baseRange
        case .left: row.leftRange
        case .right: row.rightRange
        }
    }

    private static func range(for row: ThreeWayTextMergeRegion) -> AutomaticTextMergeRange {
        AutomaticTextMergeRange(
            rowID: row.id,
            baseRange: row.baseRange,
            leftRange: row.leftRange,
            rightRange: row.rightRange
        )
    }

    private static func prospectiveLineCount(
        destinationCount: Int,
        selections: [Selection],
        policy: AutomaticTextMergePolicy
    ) throws -> Int {
        var count = destinationCount
        for (index, selection) in selections.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let removed = selection.destinationRange.count
            let added = selection.sourceRange.count
            guard removed <= count, added <= Int.max - (count - removed) else {
                throw AutomaticTextMergeError.tooManyOutputLines(
                    maximumLines: policy.maximumOutputLines
                )
            }
            count = count - removed + added
            guard count <= policy.maximumOutputLines else {
                throw AutomaticTextMergeError.tooManyOutputLines(
                    maximumLines: policy.maximumOutputLines
                )
            }
        }
        return count
    }

    private static func appliedLines(
        destination: ThreeWayTextMergeDocument,
        selections: [Selection],
        base: ThreeWayTextMergeDocument,
        left: ThreeWayTextMergeDocument,
        right: ThreeWayTextMergeDocument,
        outputLineCount: Int,
        work: inout WorkBudget
    ) throws -> [ThreeWayTextMergeLine] {
        var result = destination.lines
        try work.add(result.count)
        for (index, selection) in selections.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let source = document(for: selection.source, base: base, left: left, right: right)
            try work.add(selection.destinationRange.count)
            try work.add(selection.sourceRange.count)
            result.replaceSubrange(
                selection.destinationRange,
                with: source.lines[selection.sourceRange]
            )
        }
        guard result.count == outputLineCount else {
            throw AutomaticTextMergeError.ambiguousComparison
        }
        return result
    }

    private static func semanticText(
        from lines: [ThreeWayTextMergeLine],
        maximumBytes: Int,
        work: inout WorkBudget
    ) throws -> String {
        var result = ""
        var byteCount = 0
        for (index, line) in lines.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let lineBytes = try measuredUTF8Count(of: line.text, work: &work)
            let separatorBytes = index + 1 < lines.count || line.hasLineEnding ? 1 : 0
            guard lineBytes <= maximumBytes - byteCount,
                separatorBytes <= maximumBytes - byteCount - lineBytes
            else {
                throw AutomaticTextMergeError.outputTooLarge(maximumBytes: maximumBytes)
            }
            result.append(line.text)
            byteCount += lineBytes
            if separatorBytes != 0 {
                result.append("\n")
                byteCount += 1
                try work.add(1)
            }
        }
        return result
    }

    private static func enforceOutputBounds(
        text: String,
        lineCount: Int,
        policy: AutomaticTextMergePolicy,
        work: inout WorkBudget
    ) throws {
        guard lineCount <= policy.maximumOutputLines else {
            throw AutomaticTextMergeError.tooManyOutputLines(
                maximumLines: policy.maximumOutputLines
            )
        }
        let byteCount = try measuredUTF8Count(of: text, work: &work)
        guard byteCount <= policy.maximumOutputBytes else {
            throw AutomaticTextMergeError.outputTooLarge(maximumBytes: policy.maximumOutputBytes)
        }
    }

    private static func contentsAreEqual(
        _ left: ArraySlice<ThreeWayTextMergeLine>,
        _ right: ArraySlice<ThreeWayTextMergeLine>,
        work: inout WorkBudget
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for (index, pair) in zip(left, right).enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            try work.add(1)
            if try !textIsEqual(pair.0.text, pair.1.text, work: &work) { return false }
        }
        return true
    }

    private static func linesAreEqual(
        _ left: ArraySlice<ThreeWayTextMergeLine>,
        _ right: ArraySlice<ThreeWayTextMergeLine>,
        work: inout WorkBudget
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for (index, pair) in zip(left, right).enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            try work.add(1)
            guard pair.0.id == pair.1.id,
                pair.0.lineEnding == pair.1.lineEnding,
                try textIsEqual(pair.0.text, pair.1.text, work: &work)
            else {
                return false
            }
        }
        return true
    }

    private static func textIsEqual(
        _ left: String,
        _ right: String,
        work: inout WorkBudget
    ) throws -> Bool {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        var compared = 0
        while true {
            let leftByte = leftIterator.next()
            let rightByte = rightIterator.next()
            if leftByte == nil || rightByte == nil {
                try work.add(compared)
                return leftByte == nil && rightByte == nil
            }
            compared += 1
            if compared == 64 * 1_024 {
                try work.add(compared)
                try Task.checkCancellation()
                compared = 0
            }
            if leftByte != rightByte {
                try work.add(compared)
                return false
            }
        }
    }

    private static func measuredUTF8Count(
        of text: String,
        work: inout WorkBudget
    ) throws -> Int {
        var total = 0
        var pending = 0
        for _ in text.utf8 {
            total += 1
            pending += 1
            if pending == 64 * 1_024 {
                try work.add(pending)
                try Task.checkCancellation()
                pending = 0
            }
        }
        try work.add(pending)
        return total
    }
}
