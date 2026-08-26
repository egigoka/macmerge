import Foundation

/// Immutable text and editor state used to create or apply a replacement plan.
/// The owner is responsible for advancing `revision` whenever `text` changes.
public struct TextReplacementDocumentSnapshot: Sendable {
    public let text: String
    public let revision: UInt64
    public let isEditable: Bool

    public init(text: String, revision: UInt64, isEditable: Bool) {
        self.text = text
        self.revision = revision
        self.isEditable = isEditable
    }

}

extension TextReplacementDocumentSnapshot: Equatable {
    public static func == (
        lhs: TextReplacementDocumentSnapshot,
        rhs: TextReplacementDocumentSnapshot
    ) -> Bool {
        lhs.revision == rhs.revision
            && lhs.isEditable == rhs.isEditable
            && textReplacementStringsAreIdentical(lhs.text, rhs.text)
    }
}

public struct TextReplacementPlanningLimits: Equatable, Sendable {
    public static let `default` = TextReplacementPlanningLimits()
    public static let defaultMaximumWork = 1_024 * 1_024 * 1_024

    public let search: TextSearchLimits
    public let maximumEdits: Int
    /// Bounds estimated UTF-16 visits and regular-expression progress across all search passes.
    public let maximumWork: Int

    public init(
        search: TextSearchLimits = .default,
        maximumEdits: Int = 100_000,
        maximumWork: Int = Self.defaultMaximumWork
    ) {
        precondition(maximumEdits >= 0, "Maximum edit count must not be negative")
        precondition(maximumWork >= 0, "Maximum replacement work must not be negative")
        self.search = search
        self.maximumEdits = maximumEdits
        self.maximumWork = maximumWork
    }
}

public enum TextReplacementPlanAction: Equatable, Sendable {
    case next
    case previous
    case replaceCurrent
    case replaceAll
}

/// One nonoverlapping replacement. Ranges use UTF-16 offsets in source and result text.
public struct TextReplacementEdit: Sendable {
    public let sourceRange: NSRange
    public let originalText: String
    public let replacementText: String
    public let resultRange: NSRange

    public var didChange: Bool {
        !textReplacementStringsAreIdentical(originalText, replacementText)
    }

    fileprivate init(
        sourceRange: NSRange,
        originalText: String,
        replacementText: String,
        resultRange: NSRange
    ) {
        self.sourceRange = sourceRange
        self.originalText = originalText
        self.replacementText = replacementText
        self.resultRange = resultRange
    }
}

extension TextReplacementEdit: Equatable {
    public static func == (lhs: TextReplacementEdit, rhs: TextReplacementEdit) -> Bool {
        lhs.sourceRange == rhs.sourceRange
            && lhs.resultRange == rhs.resultRange
            && textReplacementStringsAreIdentical(lhs.originalText, rhs.originalText)
            && textReplacementStringsAreIdentical(lhs.replacementText, rhs.replacementText)
    }
}

public enum TextReplacementPlanningError: Error, Equatable, LocalizedError, Sendable {
    case documentNotEditable
    case documentRevisionChanged(expected: UInt64, actual: UInt64)
    case documentTextChanged
    case tooManyEdits(maximumEdits: Int)
    case workLimitExceeded(maximumWork: Int)
    case inconsistentSearchResults

    public var errorDescription: String? {
        switch self {
        case .documentNotEditable:
            "Text replacement requires an editable document."
        case .documentRevisionChanged(let expected, let actual):
            "Text replacement was planned for document revision \(expected), not revision \(actual)."
        case .documentTextChanged:
            "Document text no longer matches the text used to plan replacement."
        case .tooManyEdits(let maximumEdits):
            "Text replacement exceeds the \(maximumEdits)-edit limit."
        case .workLimitExceeded(let maximumWork):
            "Text replacement exceeds the \(maximumWork)-unit work limit."
        case .inconsistentSearchResults:
            "Text search produced inconsistent replacement results."
        }
    }
}

/// Immutable navigation or replacement result. Replacement edits are stored in source order and
/// applied in one pass through the source document.
public struct TextReplacementPlan: Sendable {
    public let action: TextReplacementPlanAction
    public let query: TextSearchQuery
    public let replacement: String?
    public let sourceRevision: UInt64
    public let sourceUTF16Length: Int
    public let match: TextSearchMatch?
    public let didWrap: Bool
    public let edits: [TextReplacementEdit]
    public let resultText: String

    private let sourceText: String

    public var replacementCount: Int { edits.count }
    public var changedCount: Int { edits.lazy.filter(\.didChange).count }
    public var hasChanges: Bool { edits.contains(where: \.didChange) }

    public var changedSourceRanges: [NSRange] {
        edits.compactMap { $0.didChange ? $0.sourceRange : nil }
    }

    public var changedResultRanges: [NSRange] {
        edits.compactMap { $0.didChange ? $0.resultRange : nil }
    }

    /// Range suitable for restoring selection after navigation or replacing the current match.
    public var selectionRange: NSRange? {
        let range: NSRange?
        let text: String
        switch action {
        case .next, .previous:
            range = match?.range
            text = sourceText
        case .replaceCurrent:
            range = edits.first?.resultRange
            text = resultText
        case .replaceAll:
            range = nil
            text = resultText
        }
        return range.flatMap { textReplacementComposedCharacterRange($0, in: text) }
    }

    fileprivate init(
        action: TextReplacementPlanAction,
        query: TextSearchQuery,
        replacement: String?,
        document: TextReplacementDocumentSnapshot,
        match: TextSearchMatch?,
        didWrap: Bool,
        edits: [TextReplacementEdit],
        resultText: String
    ) {
        self.action = action
        self.query = query
        self.replacement = replacement
        sourceRevision = document.revision
        sourceUTF16Length = document.text.utf16.count
        self.match = match
        self.didWrap = didWrap
        self.edits = edits
        self.resultText = resultText
        sourceText = document.text
    }

    /// Revalidates editor state and applies every edit atomically to a local value.
    /// No partially edited text is returned when validation, cancellation, or a limit fails.
    public func apply(to document: TextReplacementDocumentSnapshot) throws -> String {
        try Task.checkCancellation()
        guard document.revision == sourceRevision else {
            throw TextReplacementPlanningError.documentRevisionChanged(
                expected: sourceRevision,
                actual: document.revision
            )
        }
        guard
            try textReplacementStringsAreIdenticalCheckingCancellation(
                document.text,
                sourceText
            )
        else {
            throw TextReplacementPlanningError.documentTextChanged
        }
        if action.requiresEditableDocument {
            guard document.isEditable else {
                throw TextReplacementPlanningError.documentNotEditable
            }
        }

        let applied = try Self.applyOnePass(edits, to: document.text)
        guard try textReplacementStringsAreIdenticalCheckingCancellation(applied, resultText) else {
            throw TextReplacementPlanningError.inconsistentSearchResults
        }
        try Task.checkCancellation()
        return applied
    }

    fileprivate static func applyOnePass(
        _ edits: [TextReplacementEdit],
        to sourceText: String
    ) throws -> String {
        try Task.checkCancellation()
        guard !edits.isEmpty else {
            try Task.checkCancellation()
            return sourceText
        }
        let source = sourceText as NSString
        var previousLocation: Int?
        var previousUpperBound = 0
        var outputLength = source.length

        for (index, edit) in edits.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let range = edit.sourceRange
            let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
            guard range.location >= 0,
                range.length >= 0,
                !overflow,
                upperBound <= source.length,
                range.location >= previousUpperBound,
                range.location != previousLocation,
                try textReplacementStringsAreIdenticalCheckingCancellation(
                    source.substring(with: range),
                    edit.originalText
                )
            else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            let (withoutOriginal, removalOverflow) = outputLength.subtractingReportingOverflow(
                range.length
            )
            let (nextOutputLength, additionOverflow) = withoutOriginal.addingReportingOverflow(
                edit.replacementText.utf16.count
            )
            guard !removalOverflow, !additionOverflow, nextOutputLength >= 0 else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            outputLength = nextOutputLength
            previousLocation = range.location
            previousUpperBound = upperBound
        }

        try Task.checkCancellation()
        let output = NSMutableString(capacity: outputLength)
        var cursor = 0
        for (index, edit) in edits.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            output.append(
                source.substring(
                    with: NSRange(
                        location: cursor,
                        length: edit.sourceRange.location - cursor
                    )))
            output.append(edit.replacementText)
            cursor = edit.sourceRange.location + edit.sourceRange.length
        }
        output.append(
            source.substring(with: NSRange(location: cursor, length: source.length - cursor)))
        try Task.checkCancellation()
        return output as String
    }
}

extension TextReplacementPlan: Equatable {
    public static func == (lhs: TextReplacementPlan, rhs: TextReplacementPlan) -> Bool {
        lhs.action == rhs.action
            && lhs.query == rhs.query
            && textReplacementOptionalStringsAreIdentical(lhs.replacement, rhs.replacement)
            && lhs.sourceRevision == rhs.sourceRevision
            && lhs.sourceUTF16Length == rhs.sourceUTF16Length
            && lhs.match == rhs.match
            && lhs.didWrap == rhs.didWrap
            && lhs.edits == rhs.edits
            && textReplacementStringsAreIdentical(lhs.resultText, rhs.resultText)
            && textReplacementStringsAreIdentical(lhs.sourceText, rhs.sourceText)
    }
}

public enum TextReplacementPlanner: Sendable {
    public static func next(
        in document: TextReplacementDocumentSnapshot,
        matching query: TextSearchQuery,
        fromUTF16Offset offset: Int,
        wrap: Bool = true,
        limits: TextReplacementPlanningLimits = .default
    ) throws -> TextReplacementPlan {
        try navigationPlan(
            action: .next,
            document: document,
            query: query,
            offset: offset,
            currentMatch: nil,
            wrap: wrap,
            limits: limits
        )
    }

    public static func next(
        in document: TextReplacementDocumentSnapshot,
        matching query: TextSearchQuery,
        after match: TextSearchMatch,
        wrap: Bool = true,
        limits: TextReplacementPlanningLimits = .default
    ) throws -> TextReplacementPlan {
        try navigationPlan(
            action: .next,
            document: document,
            query: query,
            offset: nil,
            currentMatch: match,
            wrap: wrap,
            limits: limits
        )
    }

    public static func previous(
        in document: TextReplacementDocumentSnapshot,
        matching query: TextSearchQuery,
        fromUTF16Offset offset: Int,
        wrap: Bool = true,
        limits: TextReplacementPlanningLimits = .default
    ) throws -> TextReplacementPlan {
        try navigationPlan(
            action: .previous,
            document: document,
            query: query,
            offset: offset,
            currentMatch: nil,
            wrap: wrap,
            limits: limits
        )
    }

    public static func previous(
        in document: TextReplacementDocumentSnapshot,
        matching query: TextSearchQuery,
        after match: TextSearchMatch,
        wrap: Bool = true,
        limits: TextReplacementPlanningLimits = .default
    ) throws -> TextReplacementPlan {
        try navigationPlan(
            action: .previous,
            document: document,
            query: query,
            offset: nil,
            currentMatch: match,
            wrap: wrap,
            limits: limits
        )
    }

    public static func replaceCurrent(
        in document: TextReplacementDocumentSnapshot,
        match: TextSearchMatch,
        matching query: TextSearchQuery,
        with replacement: String,
        limits: TextReplacementPlanningLimits = .default
    ) throws -> TextReplacementPlan {
        try Task.checkCancellation()
        guard document.isEditable else {
            throw TextReplacementPlanningError.documentNotEditable
        }

        var work = TextReplacementWorkBudget(maximum: limits.maximumWork)
        try work.consume(replacement.utf16.count)
        guard replacement.utf16.count <= limits.search.maximumReplacementTemplateUTF16Length else {
            throw TextSearchError.replacementTemplateTooLarge(
                maximumUTF16Length: limits.search.maximumReplacementTemplateUTF16Length
            )
        }
        try work.consumeSearch(in: document.text, query: query, limits: limits.search)
        let result: TextReplacementResult
        switch query.pattern {
        case .literal:
            try textReplacementValidate(range: match.range, in: document.text)
            let ranges = try textReplacementLiteralRanges(
                in: document.text,
                query: query,
                limits: limits.search
            )
            let replacementCount = try textReplacementContains(match.range, in: ranges) ? 1 : 0
            if replacementCount == 0 {
                try textReplacementValidateUnchangedOutput(
                    document.text,
                    maximumUTF16Length: limits.search.maximumOutputUTF16Length
                )
            }
            result = TextReplacementResult(
                text: document.text,
                replacementCount: replacementCount
            )
        case .regularExpression:
            // Validate the supplied match without expanding captures before the planner can charge them.
            try textReplacementCheckCancellationDuringRegularExpressionSearch(
                in: document.text,
                query: query,
                limits: limits.search
            )
            try work.consumeSearch(in: document.text, query: query, limits: limits.search)
            result = try TextSearch.replaceCurrent(
                in: document.text,
                match: match,
                matching: query,
                with: "",
                limits: limits.search
            )
        }
        try Task.checkCancellation()
        guard result.replacementCount <= limits.maximumEdits else {
            throw TextReplacementPlanningError.tooManyEdits(
                maximumEdits: limits.maximumEdits
            )
        }
        guard result.replacementCount == 1 else {
            try Task.checkCancellation()
            return TextReplacementPlan(
                action: .replaceCurrent,
                query: query,
                replacement: replacement,
                document: document,
                match: nil,
                didWrap: false,
                edits: [],
                resultText: result.text
            )
        }

        let evaluatedReplacement: String
        switch query.pattern {
        case .literal:
            evaluatedReplacement = replacement
        case .regularExpression:
            guard
                let value = try regularExpressionReplacements(
                    in: document.text,
                    query: query,
                    ranges: [match.range],
                    template: replacement,
                    limits: limits.search,
                    work: &work
                ).first
            else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            evaluatedReplacement = value
        }
        try Task.checkCancellation()
        return try replacementPlan(
            action: .replaceCurrent,
            document: document,
            query: query,
            replacement: replacement,
            matchedRanges: [match.range],
            evaluatedReplacements: [evaluatedReplacement],
            maximumOutputUTF16Length: limits.search.maximumOutputUTF16Length,
            work: &work
        )
    }

    public static func replaceAll(
        in document: TextReplacementDocumentSnapshot,
        matching query: TextSearchQuery,
        with replacement: String,
        limits: TextReplacementPlanningLimits = .default
    ) throws -> TextReplacementPlan {
        try Task.checkCancellation()
        guard document.isEditable else {
            throw TextReplacementPlanningError.documentNotEditable
        }

        var work = TextReplacementWorkBudget(maximum: limits.maximumWork)
        try work.consume(replacement.utf16.count)
        guard replacement.utf16.count <= limits.search.maximumReplacementTemplateUTF16Length else {
            throw TextSearchError.replacementTemplateTooLarge(
                maximumUTF16Length: limits.search.maximumReplacementTemplateUTF16Length
            )
        }
        try work.consumeSearch(in: document.text, query: query, limits: limits.search)
        let boundedSearchLimits = textReplacementSearchLimits(
            limits.search,
            maximumMatches: limits.maximumEdits
        )
        let ranges: [NSRange]
        do {
            switch query.pattern {
            case .literal:
                ranges = try textReplacementLiteralRanges(
                    in: document.text,
                    query: query,
                    limits: boundedSearchLimits
                )
            case .regularExpression:
                try textReplacementCheckCancellationDuringRegularExpressionSearch(
                    in: document.text,
                    query: query,
                    limits: boundedSearchLimits
                )
                try work.consumeSearch(
                    in: document.text,
                    query: query,
                    limits: boundedSearchLimits
                )
                ranges = try TextSearch.markerRanges(
                    in: document.text,
                    matching: query,
                    limits: boundedSearchLimits
                )
            }
        } catch TextSearchError.tooManyMatches {
            guard limits.maximumEdits <= limits.search.maximumMatches else {
                throw TextSearchError.tooManyMatches(
                    maximumMatches: limits.search.maximumMatches
                )
            }
            throw TextReplacementPlanningError.tooManyEdits(
                maximumEdits: limits.maximumEdits
            )
        }
        try Task.checkCancellation()
        guard ranges.count <= limits.maximumEdits else {
            throw TextReplacementPlanningError.tooManyEdits(
                maximumEdits: limits.maximumEdits
            )
        }

        guard !ranges.isEmpty else {
            guard document.text.utf16.count <= limits.search.maximumOutputUTF16Length else {
                throw TextSearchError.outputTooLarge(
                    maximumUTF16Length: limits.search.maximumOutputUTF16Length
                )
            }
            try Task.checkCancellation()
            return TextReplacementPlan(
                action: .replaceAll,
                query: query,
                replacement: replacement,
                document: document,
                match: nil,
                didWrap: false,
                edits: [],
                resultText: document.text
            )
        }

        let evaluatedReplacements: [String]
        switch query.pattern {
        case .literal:
            evaluatedReplacements = Array(repeating: replacement, count: ranges.count)
        case .regularExpression:
            evaluatedReplacements = try regularExpressionReplacements(
                in: document.text,
                query: query,
                ranges: ranges,
                template: replacement,
                limits: limits.search,
                work: &work
            )
        }

        try Task.checkCancellation()
        return try replacementPlan(
            action: .replaceAll,
            document: document,
            query: query,
            replacement: replacement,
            matchedRanges: ranges,
            evaluatedReplacements: evaluatedReplacements,
            maximumOutputUTF16Length: limits.search.maximumOutputUTF16Length,
            work: &work
        )
    }

    private static func navigationPlan(
        action: TextReplacementPlanAction,
        document: TextReplacementDocumentSnapshot,
        query: TextSearchQuery,
        offset: Int?,
        currentMatch: TextSearchMatch?,
        wrap: Bool,
        limits: TextReplacementPlanningLimits
    ) throws -> TextReplacementPlan {
        try Task.checkCancellation()
        var work = TextReplacementWorkBudget(maximum: limits.maximumWork)
        try work.consumeSearch(in: document.text, query: query, limits: limits.search)
        let direction: TextSearchDirection = action == .next ? .forward : .backward
        let result: TextSearchResult
        switch query.pattern {
        case .literal:
            let ranges = try textReplacementLiteralRanges(
                in: document.text,
                query: query,
                limits: limits.search
            )
            result = try textReplacementFind(
                in: ranges,
                text: document.text,
                direction: direction,
                offset: offset,
                currentMatch: currentMatch,
                wrap: wrap
            )
        case .regularExpression:
            try textReplacementCheckCancellationDuringRegularExpressionSearch(
                in: document.text,
                query: query,
                limits: limits.search
            )
            try work.consumeSearch(in: document.text, query: query, limits: limits.search)
            if let currentMatch {
                result = try TextSearch.find(
                    in: document.text,
                    matching: query,
                    direction: direction,
                    after: currentMatch,
                    wrap: wrap,
                    limits: limits.search
                )
            } else if let offset {
                result = try TextSearch.find(
                    in: document.text,
                    matching: query,
                    direction: direction,
                    fromUTF16Offset: offset,
                    wrap: wrap,
                    limits: limits.search
                )
            } else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
        }
        try Task.checkCancellation()
        return TextReplacementPlan(
            action: action,
            query: query,
            replacement: nil,
            document: document,
            match: result.match,
            didWrap: result.didWrap,
            edits: [],
            resultText: document.text
        )
    }

    private static func replacementPlan(
        action: TextReplacementPlanAction,
        document: TextReplacementDocumentSnapshot,
        query: TextSearchQuery,
        replacement: String,
        matchedRanges: [NSRange],
        evaluatedReplacements: [String],
        maximumOutputUTF16Length: Int,
        work: inout TextReplacementWorkBudget
    ) throws -> TextReplacementPlan {
        guard matchedRanges.count == evaluatedReplacements.count else {
            throw TextReplacementPlanningError.inconsistentSearchResults
        }
        try Task.checkCancellation()
        try work.consume(matchedRanges.count)
        let source = document.text as NSString
        var cumulativeDelta = 0
        var previousLocation: Int?
        var previousUpperBound = 0
        var replacementLengths: [Int] = []
        replacementLengths.reserveCapacity(matchedRanges.count)

        for (index, pair) in zip(matchedRanges, evaluatedReplacements).enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let range = pair.0
            let replacementText = pair.1
            let (upperBound, rangeOverflow) = range.location.addingReportingOverflow(range.length)
            guard range.location >= 0,
                range.length >= 0,
                !rangeOverflow,
                upperBound <= source.length,
                range.location >= previousUpperBound,
                range.location != previousLocation
            else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            let (resultLocation, locationOverflow) = range.location.addingReportingOverflow(
                cumulativeDelta
            )
            guard !locationOverflow, resultLocation >= 0 else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            let replacementLength = replacementText.utf16.count
            try work.consume(range.length)
            try work.consume(replacementLength)
            replacementLengths.append(replacementLength)

            let (change, changeOverflow) = replacementLength.subtractingReportingOverflow(
                range.length
            )
            guard !changeOverflow else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            let (nextDelta, deltaOverflow) = cumulativeDelta.addingReportingOverflow(change)
            guard !deltaOverflow else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            cumulativeDelta = nextDelta
            previousLocation = range.location
            previousUpperBound = upperBound
        }

        let (expectedLength, lengthOverflow) = document.text.utf16.count.addingReportingOverflow(
            cumulativeDelta
        )
        guard !lengthOverflow, expectedLength >= 0 else {
            throw TextReplacementPlanningError.inconsistentSearchResults
        }
        guard expectedLength <= maximumOutputUTF16Length else {
            throw TextSearchError.outputTooLarge(maximumUTF16Length: maximumOutputUTF16Length)
        }
        try work.consume(expectedLength)
        try Task.checkCancellation()

        var edits: [TextReplacementEdit] = []
        edits.reserveCapacity(matchedRanges.count)
        cumulativeDelta = 0
        for (index, pair) in zip(matchedRanges, evaluatedReplacements).enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let range = pair.0
            let replacementText = pair.1
            let (resultLocation, locationOverflow) = range.location.addingReportingOverflow(
                cumulativeDelta
            )
            let replacementLength = replacementLengths[index]
            guard !locationOverflow, resultLocation >= 0 else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            edits.append(
                TextReplacementEdit(
                    sourceRange: range,
                    originalText: source.substring(with: range),
                    replacementText: replacementText,
                    resultRange: NSRange(location: resultLocation, length: replacementLength)
                ))
            let (change, changeOverflow) = replacementLength.subtractingReportingOverflow(
                range.length
            )
            let (nextDelta, deltaOverflow) = cumulativeDelta.addingReportingOverflow(change)
            guard !changeOverflow, !deltaOverflow else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            cumulativeDelta = nextDelta
        }

        let resultText = try TextReplacementPlan.applyOnePass(edits, to: document.text)
        guard expectedLength == resultText.utf16.count
        else {
            throw TextReplacementPlanningError.inconsistentSearchResults
        }
        try Task.checkCancellation()
        return TextReplacementPlan(
            action: action,
            query: query,
            replacement: replacement,
            document: document,
            match: action == .replaceCurrent
                ? matchedRanges.first.map { TextSearchMatch(range: $0) }
                : nil,
            didWrap: false,
            edits: edits,
            resultText: resultText
        )
    }

    private static func regularExpressionReplacements(
        in text: String,
        query: TextSearchQuery,
        ranges: [NSRange],
        template: String,
        limits: TextSearchLimits,
        work: inout TextReplacementWorkBudget
    ) throws -> [String] {
        guard case .regularExpression(let pattern) = query.pattern else {
            throw TextReplacementPlanningError.inconsistentSearchResults
        }
        try Task.checkCancellation()
        try work.consumeSearch(in: text, query: query, limits: limits)
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(
                pattern: pattern.isEmpty ? "(?:)" : pattern,
                options: query.caseSensitive ? [] : [.caseInsensitive]
            )
        } catch {
            throw TextSearchError.invalidPattern(pattern)
        }
        let parsedTemplate = try textReplacementRegexTemplate(
            template,
            numberOfRanges: expression.numberOfCaptureGroups + 1
        )

        let textLength = text.utf16.count
        var replacedSourceLength = 0
        for (index, range) in ranges.enumerated() {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            let (nextLength, overflow) = replacedSourceLength.addingReportingOverflow(range.length)
            guard range.length >= 0, !overflow, nextLength <= textLength else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            replacedSourceLength = nextLength
        }
        try work.consumeRepeated(
            parsedTemplate.components.count,
            count: ranges.count,
            passes: 2
        )
        let unchangedLength = textLength - replacedSourceLength
        guard unchangedLength <= limits.maximumOutputUTF16Length else {
            throw TextSearchError.outputTooLarge(
                maximumUTF16Length: limits.maximumOutputUTF16Length
            )
        }
        var remainingReplacementLength = limits.maximumOutputUTF16Length - unchangedLength

        var evaluated: [(index: Int, result: NSTextCheckingResult)] = []
        evaluated.reserveCapacity(ranges.count)
        var rangeIndex = 0
        var progressSteps = 0
        var evaluationFailed = false
        var exceededProgressLimit = false
        var cancelled = false
        let evaluationExpression = try textReplacementWholeWordExpression(
            for: expression,
            query: query
        )
        try Task.checkCancellation()
        evaluationExpression.enumerateMatches(
            in: text,
            options: [
                .reportProgress,
                .reportCompletion,
                .withTransparentBounds,
                .withoutAnchoringBounds
            ],
            range: NSRange(location: 0, length: text.utf16.count)
        ) { result, flags, stop in
            if Task.isCancelled {
                cancelled = true
                stop.pointee = true
                return
            }
            if flags.contains(.internalError) {
                evaluationFailed = true
                stop.pointee = true
                return
            }
            let progressCharge = (flags.contains(.progress) ? 1 : 0) + (result == nil ? 0 : 1)
            guard progressCharge > 0 else { return }
            let (nextProgressSteps, overflow) = progressSteps.addingReportingOverflow(
                progressCharge
            )
            guard !overflow, nextProgressSteps <= limits.maximumRegularExpressionProgressSteps else {
                exceededProgressLimit = true
                stop.pointee = true
                return
            }
            progressSteps = nextProgressSteps
            guard let result else { return }
            while rangeIndex < ranges.count,
                ranges[rangeIndex].location < result.range.location
            {
                rangeIndex += 1
            }
            guard rangeIndex < ranges.count else {
                stop.pointee = true
                return
            }
            guard result.range == ranges[rangeIndex] else { return }
            evaluated.append((rangeIndex, result))
            rangeIndex += 1
        }
        if cancelled { try Task.checkCancellation() }
        guard !evaluationFailed else { throw TextSearchError.evaluationFailed }
        guard !exceededProgressLimit else {
            throw TextSearchError.evaluationLimitExceeded(
                maximumProgressSteps: limits.maximumRegularExpressionProgressSteps
            )
        }
        try Task.checkCancellation()

        var replacements: [String] = []
        replacements.reserveCapacity(ranges.count)
        var evaluatedIndex = 0
        for (index, range) in ranges.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            if evaluatedIndex < evaluated.count, evaluated[evaluatedIndex].index == index {
                let result = evaluated[evaluatedIndex].result
                let replacementLength = try textReplacementRegexExpansionLength(
                    for: result,
                    template: parsedTemplate,
                    maximumUTF16Length: remainingReplacementLength,
                    outputLimit: limits.maximumOutputUTF16Length
                )
                try work.consume(replacementLength)
                try Task.checkCancellation()
                let replacement = try textReplacementRegexExpansion(
                    for: result,
                    in: text,
                    template: parsedTemplate,
                    expectedUTF16Length: replacementLength
                )
                replacements.append(replacement)
                remainingReplacementLength -= replacementLength
                evaluatedIndex += 1
                continue
            }
            // Charge the cancellation preflight before running it and TextSearch independently.
            try work.consumeSearch(in: text, query: query, limits: limits)
            try textReplacementCheckCancellationDuringRegularExpressionSearch(
                in: text,
                query: query,
                limits: limits
            )
            try work.consumeSearch(in: text, query: query, limits: limits)
            try work.consume(range.length)
            let unchangedLength = textLength - range.length
            let (maximumIntermediateLength, outputOverflow) =
                unchangedLength.addingReportingOverflow(
                    remainingReplacementLength
                )
            guard !outputOverflow, maximumIntermediateLength >= 0 else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            // TextSearch builds a whole-document result, so reserve its full bounded materialization.
            try work.consume(maximumIntermediateLength)
            let boundedLimits = textReplacementSearchLimits(
                limits,
                maximumOutputUTF16Length: maximumIntermediateLength
            )
            try Task.checkCancellation()
            let currentResult: TextReplacementResult
            do {
                currentResult = try TextSearch.replaceCurrent(
                    in: text,
                    match: TextSearchMatch(range: range),
                    matching: query,
                    with: template,
                    limits: boundedLimits
                )
            } catch TextSearchError.outputTooLarge {
                throw TextSearchError.outputTooLarge(
                    maximumUTF16Length: limits.maximumOutputUTF16Length
                )
            }
            try Task.checkCancellation()
            guard currentResult.replacementCount == 1 else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            let replacement = try replacementText(
                fromSingleReplacement: currentResult.text,
                sourceText: text,
                range: range,
                maximumUTF16Length: remainingReplacementLength,
                outputLimit: limits.maximumOutputUTF16Length
            )
            work.release(maximumIntermediateLength - replacement.resultUTF16Length)
            replacements.append(replacement.text)
            remainingReplacementLength -= replacement.utf16Length
        }
        try Task.checkCancellation()
        return replacements
    }

    private static func replacementText(
        fromSingleReplacement resultText: String,
        sourceText: String,
        range: NSRange,
        maximumUTF16Length: Int,
        outputLimit: Int
    ) throws -> (text: String, utf16Length: Int, resultUTF16Length: Int) {
        try Task.checkCancellation()
        let sourceLength = sourceText.utf16.count
        let (sourceUpperBound, sourceRangeOverflow) = range.location.addingReportingOverflow(
            range.length
        )
        let (unchangedLength, unchangedOverflow) = sourceLength.subtractingReportingOverflow(
            range.length
        )
        let (replacementLength, replacementOverflow) = resultText.utf16.count
            .subtractingReportingOverflow(unchangedLength)
        let result = resultText as NSString
        let (maximumResultLocation, locationOverflow) = result.length.subtractingReportingOverflow(
            replacementLength
        )
        guard range.location >= 0,
            range.length >= 0,
            range.location <= sourceLength,
            !sourceRangeOverflow,
            sourceUpperBound <= sourceLength,
            !unchangedOverflow,
            unchangedLength >= 0,
            !replacementOverflow,
            replacementLength >= 0,
            !locationOverflow,
            range.location <= maximumResultLocation,
            replacementLength <= maximumUTF16Length
        else {
            if replacementLength > maximumUTF16Length {
                throw TextSearchError.outputTooLarge(maximumUTF16Length: outputLimit)
            }
            throw TextReplacementPlanningError.inconsistentSearchResults
        }
        try Task.checkCancellation()
        let replacement = result.substring(
            with: NSRange(
                location: range.location,
                length: replacementLength
            ))
        try Task.checkCancellation()
        return (replacement, replacementLength, result.length)
    }
}

private func textReplacementSearchLimits(
    _ limits: TextSearchLimits,
    maximumMatches: Int
) -> TextSearchLimits {
    TextSearchLimits(
        maximumInputUTF16Length: limits.maximumInputUTF16Length,
        maximumPatternUTF16Length: limits.maximumPatternUTF16Length,
        maximumOutputUTF16Length: limits.maximumOutputUTF16Length,
        maximumMatches: max(1, min(limits.maximumMatches, maximumMatches)),
        maximumMarkers: limits.maximumMarkers,
        maximumCombinedPatternUTF16Length: limits.maximumCombinedPatternUTF16Length,
        maximumReplacementTemplateUTF16Length: limits.maximumReplacementTemplateUTF16Length,
        maximumStoredCaptureRanges: limits.maximumStoredCaptureRanges,
        maximumRegularExpressionProgressSteps: limits.maximumRegularExpressionProgressSteps
    )
}

private func textReplacementSearchLimits(
    _ limits: TextSearchLimits,
    maximumOutputUTF16Length: Int
) -> TextSearchLimits {
    TextSearchLimits(
        maximumInputUTF16Length: limits.maximumInputUTF16Length,
        maximumPatternUTF16Length: limits.maximumPatternUTF16Length,
        maximumOutputUTF16Length: maximumOutputUTF16Length,
        maximumMatches: limits.maximumMatches,
        maximumMarkers: limits.maximumMarkers,
        maximumCombinedPatternUTF16Length: limits.maximumCombinedPatternUTF16Length,
        maximumReplacementTemplateUTF16Length: limits.maximumReplacementTemplateUTF16Length,
        maximumStoredCaptureRanges: limits.maximumStoredCaptureRanges,
        maximumRegularExpressionProgressSteps: limits.maximumRegularExpressionProgressSteps
    )
}

private func textReplacementLiteralRanges(
    in text: String,
    query: TextSearchQuery,
    limits: TextSearchLimits
) throws -> [NSRange] {
    guard case .literal(let pattern) = query.pattern else {
        throw TextReplacementPlanningError.inconsistentSearchResults
    }
    try textReplacementValidateSearchInput(text, query: query, limits: limits)
    guard !pattern.isEmpty else { return [] }

    let source = text as NSString
    let options: NSString.CompareOptions = query.caseSensitive ? [] : [.caseInsensitive]
    var ranges: [NSRange] = []
    ranges.reserveCapacity(min(limits.maximumMatches, 1_024))
    var cursor = 0
    while cursor < source.length {
        try Task.checkCancellation()
        let range = source.range(
            of: pattern,
            options: options,
            range: NSRange(location: cursor, length: source.length - cursor)
        )
        try Task.checkCancellation()
        guard range.location != NSNotFound else { break }
        let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
        guard !overflow, upperBound > cursor, upperBound <= source.length else {
            throw TextReplacementPlanningError.inconsistentSearchResults
        }
        guard textReplacementIsComposedCharacterBoundary(range.location, in: source),
            textReplacementIsComposedCharacterBoundary(upperBound, in: source),
            !query.wholeWord || textReplacementHasWholeWordBoundaries(range, in: source)
        else {
            let next = source.rangeOfComposedCharacterSequence(at: range.location).upperBound
            guard next > range.location else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            cursor = next
            continue
        }
        cursor = upperBound
        guard ranges.count < limits.maximumMatches else {
            throw TextSearchError.tooManyMatches(maximumMatches: limits.maximumMatches)
        }
        guard ranges.count < limits.maximumStoredCaptureRanges else {
            throw TextSearchError.tooManyCaptureRanges(
                maximumRanges: limits.maximumStoredCaptureRanges
            )
        }
        ranges.append(range)
    }
    try Task.checkCancellation()
    return ranges
}

private func textReplacementContains(_ target: NSRange, in ranges: [NSRange]) throws -> Bool {
    for (index, range) in ranges.enumerated() {
        if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
        if range == target { return true }
    }
    try Task.checkCancellation()
    return false
}

private func textReplacementFind(
    in ranges: [NSRange],
    text: String,
    direction: TextSearchDirection,
    offset: Int?,
    currentMatch: TextSearchMatch?,
    wrap: Bool
) throws -> TextSearchResult {
    let searchOffset: Int
    let excludedRange: NSRange?
    if let currentMatch {
        try textReplacementValidate(range: currentMatch.range, in: text)
        switch direction {
        case .forward:
            let (upperBound, overflow) = currentMatch.range.location.addingReportingOverflow(
                currentMatch.range.length
            )
            guard !overflow else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            searchOffset = upperBound
        case .backward:
            searchOffset = currentMatch.range.location
        }
        excludedRange = currentMatch.range.length == 0 ? currentMatch.range : nil
    } else if let offset {
        try textReplacementValidate(range: NSRange(location: offset, length: 0), in: text)
        searchOffset = offset
        excludedRange = nil
    } else {
        throw TextReplacementPlanningError.inconsistentSearchResults
    }

    var primary: NSRange?
    var wrapped: NSRange?
    for (index, range) in ranges.enumerated() {
        if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
        guard excludedRange == nil || range != excludedRange else { continue }
        switch direction {
        case .forward:
            if wrapped == nil { wrapped = range }
            if primary == nil, range.location >= searchOffset { primary = range }
        case .backward:
            wrapped = range
            let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
            guard !overflow else {
                throw TextReplacementPlanningError.inconsistentSearchResults
            }
            if upperBound <= searchOffset { primary = range }
        }
    }
    try Task.checkCancellation()
    if let primary {
        return TextSearchResult(match: TextSearchMatch(range: primary), didWrap: false)
    }
    guard wrap, let wrapped else {
        return TextSearchResult(match: nil, didWrap: false)
    }
    return TextSearchResult(match: TextSearchMatch(range: wrapped), didWrap: true)
}

private func textReplacementCheckCancellationDuringRegularExpressionSearch(
    in text: String,
    query: TextSearchQuery,
    limits: TextSearchLimits
) throws {
    guard case .regularExpression(let pattern) = query.pattern else {
        throw TextReplacementPlanningError.inconsistentSearchResults
    }
    try textReplacementValidateSearchInput(text, query: query, limits: limits)
    let expression: NSRegularExpression
    do {
        expression = try NSRegularExpression(
            pattern: pattern.isEmpty ? "(?:)" : pattern,
            options: query.caseSensitive ? [] : [.caseInsensitive]
        )
    } catch {
        throw TextSearchError.invalidPattern(pattern)
    }
    let evaluationExpression = try textReplacementWholeWordExpression(
        for: expression,
        query: query
    )
    var progressSteps = 0
    var evaluationFailed = false
    var exceededProgressLimit = false
    var cancelled = false
    evaluationExpression.enumerateMatches(
        in: text,
        options: [
            .reportProgress,
            .reportCompletion,
            .withTransparentBounds,
            .withoutAnchoringBounds
        ],
        range: NSRange(location: 0, length: text.utf16.count)
    ) { result, flags, stop in
        if Task.isCancelled {
            cancelled = true
            stop.pointee = true
            return
        }
        if flags.contains(.internalError) {
            evaluationFailed = true
            stop.pointee = true
            return
        }
        let progressCharge = (flags.contains(.progress) ? 1 : 0) + (result == nil ? 0 : 1)
        guard progressCharge > 0 else { return }
        let (nextProgressSteps, overflow) = progressSteps.addingReportingOverflow(progressCharge)
        guard !overflow, nextProgressSteps <= limits.maximumRegularExpressionProgressSteps else {
            exceededProgressLimit = true
            stop.pointee = true
            return
        }
        progressSteps = nextProgressSteps
    }
    if cancelled { try Task.checkCancellation() }
    guard !evaluationFailed else { throw TextSearchError.evaluationFailed }
    guard !exceededProgressLimit else {
        throw TextSearchError.evaluationLimitExceeded(
            maximumProgressSteps: limits.maximumRegularExpressionProgressSteps
        )
    }
    try Task.checkCancellation()
}

private func textReplacementValidateSearchInput(
    _ text: String,
    query: TextSearchQuery,
    limits: TextSearchLimits
) throws {
    guard text.utf16.count <= limits.maximumInputUTF16Length else {
        throw TextSearchError.inputTooLarge(
            maximumUTF16Length: limits.maximumInputUTF16Length
        )
    }
    guard query.pattern.text.utf16.count <= limits.maximumPatternUTF16Length else {
        throw TextSearchError.patternTooLarge(
            maximumUTF16Length: limits.maximumPatternUTF16Length
        )
    }
    try Task.checkCancellation()
}

private func textReplacementValidate(range: NSRange, in text: String) throws {
    let source = text as NSString
    let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
    guard range.location >= 0, range.length >= 0, !overflow, upperBound <= source.length else {
        throw TextSearchError.invalidUTF16Range(range)
    }
    guard textReplacementIsComposedCharacterBoundary(range.location, in: source),
        textReplacementIsComposedCharacterBoundary(upperBound, in: source)
    else {
        throw TextSearchError.rangeSplitsGrapheme(range)
    }
    try Task.checkCancellation()
}

private func textReplacementValidateUnchangedOutput(
    _ text: String,
    maximumUTF16Length: Int
) throws {
    guard text.utf16.count <= maximumUTF16Length else {
        throw TextSearchError.outputTooLarge(maximumUTF16Length: maximumUTF16Length)
    }
    try Task.checkCancellation()
}

private func textReplacementIsComposedCharacterBoundary(
    _ offset: Int,
    in text: NSString
) -> Bool {
    guard offset >= 0, offset <= text.length else { return false }
    return offset == text.length
        || text.rangeOfComposedCharacterSequence(at: offset).location == offset
}

private func textReplacementHasWholeWordBoundaries(_ range: NSRange, in text: NSString) -> Bool {
    let upperBound = range.location + range.length
    let previous =
        range.location > 0
        ? text.substring(with: text.rangeOfComposedCharacterSequence(at: range.location - 1))
        : nil
    let next =
        upperBound < text.length
        ? text.substring(with: text.rangeOfComposedCharacterSequence(at: upperBound))
        : nil
    return previous.map(textReplacementIsWordCharacter) != true
        && next.map(textReplacementIsWordCharacter) != true
}

private func textReplacementIsWordCharacter(_ character: String) -> Bool {
    var hasMark = false
    for scalar in character.unicodeScalars {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
            .otherLetter, .decimalNumber, .letterNumber, .otherNumber,
            .connectorPunctuation:
            return true
        case .nonspacingMark, .spacingMark, .enclosingMark:
            if !scalar.properties.isVariationSelector {
                hasMark = true
            }
        default:
            break
        }
    }
    return hasMark
}

private func textReplacementComposedCharacterRange(_ range: NSRange, in text: String) -> NSRange? {
    let source = text as NSString
    let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
    guard range.location >= 0, range.length >= 0, !overflow, upperBound <= source.length else {
        return nil
    }
    let startsAtBoundary =
        range.location == source.length
        || source.rangeOfComposedCharacterSequence(at: range.location).location == range.location
    let endsAtBoundary =
        upperBound == source.length
        || source.rangeOfComposedCharacterSequence(at: upperBound).location == upperBound
    guard !startsAtBoundary || !endsAtBoundary else { return range }
    return source.rangeOfComposedCharacterSequences(for: range)
}

private func textReplacementWholeWordExpression(
    for expression: NSRegularExpression,
    query: TextSearchQuery
) throws -> NSRegularExpression {
    guard query.wholeWord, !query.pattern.text.isEmpty else { return expression }
    let word = "[\\p{L}\\p{N}\\p{Pc}]"
    let suffixes = ["", "\\E", "\n", "\n\\E"]
    for suffix in suffixes {
        if let wrapped = try? NSRegularExpression(
            pattern: "(?<!\(word))(?:\(expression.pattern)\(suffix))(?!\(word))",
            options: expression.options
        ) {
            return wrapped
        }
    }
    throw TextSearchError.evaluationFailed
}

private enum TextReplacementRegexTemplateComponent {
    case literal(String, utf16Length: Int)
    case capture(Int)
}

private struct TextReplacementRegexTemplate {
    let components: [TextReplacementRegexTemplateComponent]
}

private func textReplacementRegexTemplate(
    _ template: String,
    numberOfRanges: Int
) throws -> TextReplacementRegexTemplate {
    let units = Array(template.utf16)
    let maximumCaptureDigits = String(max(0, numberOfRanges - 1)).count
    var components: [TextReplacementRegexTemplateComponent] = []
    var literalUnits: [UInt16] = []
    var index = 0

    func flushLiteral() {
        guard !literalUnits.isEmpty else { return }
        components.append(
            .literal(
                String(decoding: literalUnits, as: UTF16.self),
                utf16Length: literalUnits.count
            ))
        literalUnits.removeAll(keepingCapacity: true)
    }

    while index < units.count {
        if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
        if units[index] == 0x5C {
            guard index + 1 < units.count else { break }
            let escapedLength =
                units[index + 1].textReplacementIsLeadSurrogate && index + 2 < units.count
                    && units[index + 2].textReplacementIsTrailSurrogate
                ? 2 : 1
            literalUnits.append(contentsOf: units[(index + 1)..<(index + 1 + escapedLength)])
            index += 1 + escapedLength
            continue
        }
        if units[index] == 0x24, index + 1 < units.count,
            units[index + 1] >= 0x30, units[index + 1] <= 0x39
        {
            flushLiteral()
            var capture = 0
            var consumed = 0
            index += 1
            while index < units.count, consumed < maximumCaptureDigits,
                units[index] >= 0x30, units[index] <= 0x39
            {
                capture = capture * 10 + Int(units[index] - 0x30)
                index += 1
                consumed += 1
            }
            components.append(.capture(capture))
            continue
        }
        literalUnits.append(units[index])
        index += 1
    }
    flushLiteral()
    try Task.checkCancellation()
    return TextReplacementRegexTemplate(components: components)
}

private func textReplacementRegexExpansionLength(
    for result: NSTextCheckingResult,
    template: TextReplacementRegexTemplate,
    maximumUTF16Length: Int,
    outputLimit: Int
) throws -> Int {
    var length = 0
    for (index, component) in template.components.enumerated() {
        if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
        let added: Int
        switch component {
        case .literal(_, let utf16Length):
            added = utf16Length
        case .capture(let capture):
            guard capture < result.numberOfRanges else { continue }
            let range = result.range(at: capture)
            added = range.location == NSNotFound ? 0 : range.length
        }
        let (nextLength, overflow) = length.addingReportingOverflow(added)
        guard !overflow, nextLength <= maximumUTF16Length else {
            throw TextSearchError.outputTooLarge(maximumUTF16Length: outputLimit)
        }
        length = nextLength
    }
    try Task.checkCancellation()
    return length
}

private func textReplacementRegexExpansion(
    for result: NSTextCheckingResult,
    in text: String,
    template: TextReplacementRegexTemplate,
    expectedUTF16Length: Int
) throws -> String {
    try Task.checkCancellation()
    let source = text as NSString
    let replacement = NSMutableString(capacity: expectedUTF16Length)
    for (index, component) in template.components.enumerated() {
        if index.isMultiple(of: 64) { try Task.checkCancellation() }
        switch component {
        case .literal(let literal, _):
            replacement.append(literal)
        case .capture(let capture):
            guard capture < result.numberOfRanges else { continue }
            let range = result.range(at: capture)
            if range.location != NSNotFound {
                replacement.append(source.substring(with: range))
            }
        }
    }
    try Task.checkCancellation()
    guard replacement.length == expectedUTF16Length else {
        throw TextReplacementPlanningError.inconsistentSearchResults
    }
    return replacement as String
}

private struct TextReplacementWorkBudget {
    let maximum: Int
    private(set) var consumed = 0

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0 else {
            throw TextReplacementPlanningError.inconsistentSearchResults
        }
        let (next, overflow) = consumed.addingReportingOverflow(amount)
        guard !overflow, next <= maximum else {
            throw TextReplacementPlanningError.workLimitExceeded(maximumWork: maximum)
        }
        if consumed / 4_096 != next / 4_096 {
            try Task.checkCancellation()
        }
        consumed = next
    }

    mutating func consumeRepeated(_ amount: Int, count: Int, passes: Int) throws {
        guard amount >= 0, count >= 0, passes >= 0 else {
            throw TextReplacementPlanningError.inconsistentSearchResults
        }
        let (perPass, countOverflow) = amount.multipliedReportingOverflow(by: count)
        let (total, passOverflow) = perPass.multipliedReportingOverflow(by: passes)
        guard !countOverflow, !passOverflow else {
            throw TextReplacementPlanningError.workLimitExceeded(maximumWork: maximum)
        }
        try consume(total)
    }

    mutating func release(_ amount: Int) {
        precondition(amount >= 0 && amount <= consumed)
        consumed -= amount
    }

    mutating func consumeSearch(
        in text: String,
        query: TextSearchQuery,
        limits: TextSearchLimits
    ) throws {
        try consume(text.utf16.count)
        try consume(query.pattern.text.utf16.count)
        if case .regularExpression = query.pattern {
            try consume(limits.maximumRegularExpressionProgressSteps)
        }
    }
}

extension TextReplacementPlanAction {
    fileprivate var requiresEditableDocument: Bool {
        switch self {
        case .next, .previous:
            false
        case .replaceCurrent, .replaceAll:
            true
        }
    }
}

private func textReplacementStringsAreIdentical(_ lhs: String, _ rhs: String) -> Bool {
    lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
}

private func textReplacementStringsAreIdenticalCheckingCancellation(
    _ lhs: String,
    _ rhs: String
) throws -> Bool {
    var lhsScalars = lhs.unicodeScalars.makeIterator()
    var rhsScalars = rhs.unicodeScalars.makeIterator()
    var compared = 0
    while true {
        if compared.isMultiple(of: 4_096) { try Task.checkCancellation() }
        let lhsScalar = lhsScalars.next()
        let rhsScalar = rhsScalars.next()
        guard lhsScalar == rhsScalar else {
            try Task.checkCancellation()
            return false
        }
        guard lhsScalar != nil else {
            try Task.checkCancellation()
            return true
        }
        compared += 1
    }
}

private func textReplacementOptionalStringsAreIdentical(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        true
    case (.some(let lhs), .some(let rhs)):
        textReplacementStringsAreIdentical(lhs, rhs)
    case (.none, .some), (.some, .none):
        false
    }
}

extension UInt16 {
    fileprivate var textReplacementIsLeadSurrogate: Bool { (0xD800...0xDBFF).contains(self) }
    fileprivate var textReplacementIsTrailSurrogate: Bool { (0xDC00...0xDFFF).contains(self) }
}
