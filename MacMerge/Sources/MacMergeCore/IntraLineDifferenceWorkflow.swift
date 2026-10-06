import CryptoKit
import Foundation

public enum IntraLineDifferenceRole: String, CaseIterable, Hashable, Sendable {
    case base
    case left
    case right
}

public struct IntraLineDifferenceComparisonReference: Hashable, Sendable {
    public let identity: UUID
    public let revision: UInt64

    public init(identity: UUID = UUID(), revision: UInt64) {
        self.identity = identity
        self.revision = revision
    }
}

/// Exact owner-issued source-line binding. Owners must not reuse one identity/revision pair after
/// changing text or rebinding a role.
public struct IntraLineDifferenceSourceReference: Hashable, Sendable {
    public let identity: UUID
    public let revision: UInt64
    public let role: IntraLineDifferenceRole
    public let lineNumber: Int

    public init(
        identity: UUID,
        revision: UInt64,
        role: IntraLineDifferenceRole,
        lineNumber: Int
    ) {
        self.identity = identity
        self.revision = revision
        self.role = role
        self.lineNumber = lineNumber
    }
}

public struct IntraLineDifferenceTextSnapshot: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: IntraLineDifferenceSourceReference
    public let text: String

    public init(reference: IntraLineDifferenceSourceReference, text: String) {
        self.reference = reference
        self.text = text
    }

    public init(
        identity: UUID,
        revision: UInt64,
        role: IntraLineDifferenceRole,
        line: DiffLine
    ) {
        reference = IntraLineDifferenceSourceReference(
            identity: identity,
            revision: revision,
            role: role,
            lineNumber: line.number
        )
        text = line.text
    }

    public init(identity: UUID, revision: UInt64, line: ThreeWayTextMergeLine) {
        let role: IntraLineDifferenceRole =
            switch line.source {
            case .base: .base
            case .left: .left
            case .right: .right
            }
        reference = IntraLineDifferenceSourceReference(
            identity: identity,
            revision: revision,
            role: role,
            lineNumber: line.number
        )
        text = line.text
    }

    public var description: String {
        "IntraLineDifferenceTextSnapshot(role: \(reference.role.rawValue), line: \(reference.lineNumber), text: <redacted>)"
    }

    public var debugDescription: String { description }

    public static func == (
        left: IntraLineDifferenceTextSnapshot,
        right: IntraLineDifferenceTextSnapshot
    ) -> Bool {
        left.reference == right.reference && left.text.utf8.elementsEqual(right.text.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "reference": reference,
                "text": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension IntraLineDifferenceTextSnapshot: Hashable {}

public enum IntraLineDifferenceTwoWayPair: String, CaseIterable, Hashable, Sendable {
    case leftRight
    case rightLeft

    public var sourceRole: IntraLineDifferenceRole {
        self == .leftRight ? .left : .right
    }

    public var comparisonRole: IntraLineDifferenceRole {
        self == .leftRight ? .right : .left
    }
}

public enum IntraLineDifferenceThreeWayPair: String, CaseIterable, Hashable, Sendable {
    case baseLeft
    case baseRight
    case leftRight

    public var sourceRole: IntraLineDifferenceRole {
        switch self {
        case .baseLeft, .baseRight: .base
        case .leftRight: .left
        }
    }

    public var comparisonRole: IntraLineDifferenceRole {
        switch self {
        case .baseLeft: .left
        case .baseRight, .leftRight: .right
        }
    }
}

public enum IntraLineDifferencePairKind: Hashable, Sendable {
    case twoWay(IntraLineDifferenceTwoWayPair)
    case threeWay(IntraLineDifferenceThreeWayPair)
}

public enum IntraLineDifferenceRowIdentity: Hashable, Sendable {
    case twoWay(id: DiffRow.ID, kind: DiffKind)
    case threeWay(
        regionID: Int,
        sourceLine: ThreeWayTextMergeLine.ID?,
        comparisonLine: ThreeWayTextMergeLine.ID?
    )
}

/// Exact aligned-row binding. Two-way indices belong to the comparison's aligned rows; three-way
/// indices are local to the identified merge region.
public struct IntraLineDifferenceRowReference: Hashable, Sendable {
    public let comparison: IntraLineDifferenceComparisonReference
    public let rowIndex: Int
    public let identity: IntraLineDifferenceRowIdentity

    fileprivate init(
        comparison: IntraLineDifferenceComparisonReference,
        rowIndex: Int,
        identity: IntraLineDifferenceRowIdentity
    ) {
        self.comparison = comparison
        self.rowIndex = rowIndex
        self.identity = identity
    }
}

public struct IntraLineDifferenceTwoWayRowBinding: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let rowIndex: Int
    fileprivate let id: DiffRow.ID
    fileprivate let kind: DiffKind
    fileprivate let leftText: String?
    fileprivate let rightText: String?

    public init(alignedRows: [DiffRow], rowID: DiffRow.ID) throws {
        var matchedIndex: Int?
        for (index, row) in alignedRows.enumerated() where row.id == rowID {
            guard matchedIndex == nil else {
                throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
            }
            matchedIndex = index
        }
        guard let rowIndex = matchedIndex else {
            throw IntraLineDifferenceWorkflowError.invalidRowIndex
        }
        let row = alignedRows[rowIndex]
        self.rowIndex = rowIndex
        id = row.id
        kind = row.kind
        leftText = row.left?.text
        rightText = row.right?.text
    }

    public var description: String {
        "IntraLineDifferenceTwoWayRowBinding(row: \(rowIndex), text: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["rowIndex": rowIndex, "identity": id, "kind": kind, "text": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public struct IntraLineDifferenceThreeWayRowBinding: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let regionID: Int
    public let rowIndex: Int
    fileprivate let baseLine: ThreeWayTextMergeLine?
    fileprivate let leftLine: ThreeWayTextMergeLine?
    fileprivate let rightLine: ThreeWayTextMergeLine?

    public init(region: ThreeWayTextMergeRegion, row: ThreeWayTextMergeLine) throws {
        guard region.id >= 0,
            region.baseRange.lowerBound >= 0,
            region.leftRange.lowerBound >= 0,
            region.rightRange.lowerBound >= 0,
            region.baseLines.count == region.baseRange.count,
            region.leftLines.count == region.leftRange.count,
            region.rightLines.count == region.rightRange.count
        else {
            throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
        }

        let anchor: (lines: [ThreeWayTextMergeLine], range: Range<Int>) =
            switch row.source {
            case .base: (region.baseLines, region.baseRange)
            case .left: (region.leftLines, region.leftRange)
            case .right: (region.rightLines, region.rightRange)
            }
        guard row.number > 0 else {
            throw IntraLineDifferenceWorkflowError.invalidSourceLineNumber
        }
        let documentIndex = row.number - 1
        guard anchor.range.contains(documentIndex) else {
            throw IntraLineDifferenceWorkflowError.invalidRowIndex
        }
        let rowIndex = documentIndex - anchor.range.lowerBound
        guard anchor.lines.indices.contains(rowIndex), anchor.lines[rowIndex].id == row.id else {
            throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
        }

        func line(
            in lines: [ThreeWayTextMergeLine],
            range: Range<Int>,
            source: ThreeWayTextMergeSource
        ) throws -> ThreeWayTextMergeLine? {
            guard lines.indices.contains(rowIndex) else { return nil }
            let line = lines[rowIndex]
            guard
                line.id
                    == ThreeWayTextMergeLine.ID(
                        source: source,
                        number: range.lowerBound + rowIndex + 1
                    )
            else {
                throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
            }
            return line
        }

        regionID = region.id
        self.rowIndex = rowIndex
        baseLine = try line(in: region.baseLines, range: region.baseRange, source: .base)
        leftLine = try line(in: region.leftLines, range: region.leftRange, source: .left)
        rightLine = try line(in: region.rightLines, range: region.rightRange, source: .right)
    }

    public var description: String {
        "IntraLineDifferenceThreeWayRowBinding(region: \(regionID), row: \(rowIndex), text: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["regionID": regionID, "rowIndex": rowIndex, "text": "<redacted>"],
            displayStyle: .struct
        )
    }

    fileprivate func line(for role: IntraLineDifferenceRole) -> ThreeWayTextMergeLine? {
        switch role {
        case .base: baseLine
        case .left: leftLine
        case .right: rightLine
        }
    }
}

public struct IntraLineDifferencePairInput: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let kind: IntraLineDifferencePairKind
    public let row: IntraLineDifferenceRowReference
    public let source: IntraLineDifferenceTextSnapshot?
    public let comparison: IntraLineDifferenceTextSnapshot?
    fileprivate let rowTextBinding: IntraLineDifferenceRowTextBinding

    private init(
        kind: IntraLineDifferencePairKind,
        row: IntraLineDifferenceRowReference,
        source: IntraLineDifferenceTextSnapshot?,
        comparison: IntraLineDifferenceTextSnapshot?,
        rowTextBinding: IntraLineDifferenceRowTextBinding
    ) {
        self.kind = kind
        self.row = row
        self.source = source
        self.comparison = comparison
        self.rowTextBinding = rowTextBinding
    }

    public static func twoWay(
        comparison: IntraLineDifferenceComparisonReference,
        row: IntraLineDifferenceTwoWayRowBinding,
        pair: IntraLineDifferenceTwoWayPair = .leftRight,
        left: IntraLineDifferenceTextSnapshot?,
        right: IntraLineDifferenceTextSnapshot?
    ) -> IntraLineDifferencePairInput {
        let rowReference = IntraLineDifferenceRowReference(
            comparison: comparison,
            rowIndex: row.rowIndex,
            identity: .twoWay(id: row.id, kind: row.kind)
        )
        return IntraLineDifferencePairInput(
            kind: .twoWay(pair),
            row: rowReference,
            source: pair == .leftRight ? left : right,
            comparison: pair == .leftRight ? right : left,
            rowTextBinding: IntraLineDifferenceRowTextBinding(
                source: pair == .leftRight ? row.leftText : row.rightText,
                comparison: pair == .leftRight ? row.rightText : row.leftText
            )
        )
    }

    public static func threeWay(
        comparison: IntraLineDifferenceComparisonReference,
        row: IntraLineDifferenceThreeWayRowBinding,
        pair: IntraLineDifferenceThreeWayPair,
        base: IntraLineDifferenceTextSnapshot?,
        left: IntraLineDifferenceTextSnapshot?,
        right: IntraLineDifferenceTextSnapshot?
    ) -> IntraLineDifferencePairInput {
        func snapshot(for role: IntraLineDifferenceRole) -> IntraLineDifferenceTextSnapshot? {
            switch role {
            case .base: base
            case .left: left
            case .right: right
            }
        }
        let source = snapshot(for: pair.sourceRole)
        let compared = snapshot(for: pair.comparisonRole)
        let sourceRow = row.line(for: pair.sourceRole)
        let comparisonRow = row.line(for: pair.comparisonRole)
        return IntraLineDifferencePairInput(
            kind: .threeWay(pair),
            row: IntraLineDifferenceRowReference(
                comparison: comparison,
                rowIndex: row.rowIndex,
                identity: .threeWay(
                    regionID: row.regionID,
                    sourceLine: sourceRow?.id,
                    comparisonLine: comparisonRow?.id
                )
            ),
            source: source,
            comparison: compared,
            rowTextBinding: IntraLineDifferenceRowTextBinding(
                source: sourceRow?.text,
                comparison: comparisonRow?.text
            )
        )
    }

    public var description: String {
        "IntraLineDifferencePairInput(row: \(row.rowIndex), kind: \(kind.redactedName), text: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": kind.redactedName,
                "row": row,
                "source": source == nil ? "missing" : "<redacted>",
                "comparison": comparison == nil ? "missing" : "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum IntraLineDifferencePunctuationComparison: String, CaseIterable, Hashable, Sendable {
    case compareAll
    case ignoreAll
}

public struct IntraLineDifferenceOptions: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = IntraLineDifferenceOptions()

    public let granularity: EditorPreferencesWorkflow.LineDifferenceGranularity
    public let wordBreakMode: EditorPreferencesWorkflow.WordBreakMode
    public let wordBreakCharacters: String
    public let whitespace: WhitespaceComparison
    public let ignoreCase: Bool
    public let ignoreNumbers: Bool
    public let punctuation: IntraLineDifferencePunctuationComparison

    public init(
        granularity: EditorPreferencesWorkflow.LineDifferenceGranularity = .word,
        wordBreakMode: EditorPreferencesWorkflow.WordBreakMode = .whitespace,
        wordBreakCharacters: String = "",
        whitespace: WhitespaceComparison = .compareAll,
        ignoreCase: Bool = false,
        ignoreNumbers: Bool = false,
        punctuation: IntraLineDifferencePunctuationComparison = .compareAll
    ) {
        self.granularity = granularity
        self.wordBreakMode = wordBreakMode
        self.wordBreakCharacters = wordBreakCharacters
        self.whitespace = whitespace
        self.ignoreCase = ignoreCase
        self.ignoreNumbers = ignoreNumbers
        self.punctuation = punctuation
    }

    /// Copies comparison behavior that can be mapped to exact source ranges. Number ignoring is
    /// limited to ASCII digits, matching `LineDiff`'s byte policy. Line filters, substitutions,
    /// comment removal, blank-line handling, and line-ending policy remain row-level.
    public init(
        comparisonOptions: LineDiffOptions,
        editorPreferences: EditorPreferencesWorkflow.CompareAndMergePreferences,
        punctuation: IntraLineDifferencePunctuationComparison = .compareAll
    ) {
        self.init(
            granularity: editorPreferences.lineDifferenceGranularity,
            wordBreakMode: editorPreferences.wordBreakMode,
            wordBreakCharacters: editorPreferences.wordBreakCharacters,
            whitespace: comparisonOptions.whitespace,
            ignoreCase: comparisonOptions.ignoreCase,
            ignoreNumbers: comparisonOptions.ignoreNumbers,
            punctuation: punctuation
        )
    }

    public var description: String {
        "IntraLineDifferenceOptions(granularity: \(granularity.rawValue), wordBreakMode: \(wordBreakMode.rawValue), whitespace: \(whitespace.rawValue), ignoreCase: \(ignoreCase), ignoreNumbers: \(ignoreNumbers), punctuation: \(punctuation.rawValue), wordBreakCharacters: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "granularity": granularity,
                "wordBreakMode": wordBreakMode,
                "whitespace": whitespace,
                "ignoreCase": ignoreCase,
                "ignoreNumbers": ignoreNumbers,
                "punctuation": punctuation,
                "wordBreakCharacters": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension IntraLineDifferenceOptions: Hashable {
    public static func == (
        left: IntraLineDifferenceOptions,
        right: IntraLineDifferenceOptions
    ) -> Bool {
        left.granularity == right.granularity
            && left.wordBreakMode == right.wordBreakMode
            && left.wordBreakCharacters.utf8.elementsEqual(right.wordBreakCharacters.utf8)
            && left.whitespace == right.whitespace
            && left.ignoreCase == right.ignoreCase
            && left.ignoreNumbers == right.ignoreNumbers
            && left.punctuation == right.punctuation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(granularity)
        hasher.combine(wordBreakMode)
        hasher.combine(wordBreakCharacters.utf8.count)
        for byte in wordBreakCharacters.utf8 { hasher.combine(byte) }
        hasher.combine(whitespace.rawValue)
        hasher.combine(ignoreCase)
        hasher.combine(ignoreNumbers)
        hasher.combine(punctuation)
    }
}

public enum IntraLineDifferenceLimit: String, CaseIterable, Hashable, Sendable {
    case inputUTF8BytesPerSide
    case inputUTF16UnitsPerSide
    case inputGraphemesPerSide
    case combinedInputUTF8Bytes
    case graphemeUTF16Units
    case wordBreakUTF8Bytes
    case outputRangePairs
    case alignmentLookahead
    case workUnits
    case cancellationCheckInterval
}

public struct IntraLineDifferenceLimits: Hashable, Sendable {
    public static let hardMaximumInputUTF8BytesPerSide = 1 * 1_024 * 1_024
    public static let hardMaximumInputUTF16UnitsPerSide = 512 * 1_024
    public static let hardMaximumInputGraphemesPerSide = 128 * 1_024
    public static let hardMaximumCombinedInputUTF8Bytes = 2 * 1_024 * 1_024
    public static let hardMaximumGraphemeUTF16Units = 64 * 1_024
    public static let hardMaximumWordBreakUTF8Bytes = 64 * 1_024
    public static let hardMaximumOutputRangePairs = 128 * 1_024
    public static let hardMaximumAlignmentLookahead = 256
    public static let hardMaximumWorkUnits: UInt64 = 1 << 34
    public static let hardMaximumCancellationCheckInterval: UInt64 = 4_096
    public static let `default` = IntraLineDifferenceLimits()

    public let maximumInputUTF8BytesPerSide: Int
    public let maximumInputUTF16UnitsPerSide: Int
    public let maximumInputGraphemesPerSide: Int
    public let maximumCombinedInputUTF8Bytes: Int
    public let maximumGraphemeUTF16Units: Int
    public let maximumWordBreakUTF8Bytes: Int
    public let maximumOutputRangePairs: Int
    public let alignmentLookahead: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: UInt64

    public init(
        maximumInputUTF8BytesPerSide: Int = 16_384,
        maximumInputUTF16UnitsPerSide: Int = 8_192,
        maximumInputGraphemesPerSide: Int = 2_048,
        maximumCombinedInputUTF8Bytes: Int = 32_768,
        maximumGraphemeUTF16Units: Int = 8_192,
        maximumWordBreakUTF8Bytes: Int = 4_096,
        maximumOutputRangePairs: Int = 2_048,
        alignmentLookahead: Int = 64,
        maximumWorkUnits: UInt64 = 8 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 1_024
    ) {
        self.maximumInputUTF8BytesPerSide = maximumInputUTF8BytesPerSide
        self.maximumInputUTF16UnitsPerSide = maximumInputUTF16UnitsPerSide
        self.maximumInputGraphemesPerSide = maximumInputGraphemesPerSide
        self.maximumCombinedInputUTF8Bytes = maximumCombinedInputUTF8Bytes
        self.maximumGraphemeUTF16Units = maximumGraphemeUTF16Units
        self.maximumWordBreakUTF8Bytes = maximumWordBreakUTF8Bytes
        self.maximumOutputRangePairs = maximumOutputRangePairs
        self.alignmentLookahead = alignmentLookahead
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum IntraLineDifferenceChangeKind: String, CaseIterable, Hashable, Sendable {
    case insert
    case delete
    case replace
}

public struct IntraLineDifferenceRangePair: Hashable, Sendable {
    public let ordinal: Int
    public let kind: IntraLineDifferenceChangeKind
    public let sourceUTF16Range: NSRange?
    public let comparisonUTF16Range: NSRange?

    public init(
        ordinal: Int,
        kind: IntraLineDifferenceChangeKind,
        sourceUTF16Range: NSRange?,
        comparisonUTF16Range: NSRange?
    ) {
        self.ordinal = ordinal
        self.kind = kind
        self.sourceUTF16Range = sourceUTF16Range
        self.comparisonUTF16Range = comparisonUTF16Range
    }
}

public struct IntraLineDifferenceSideOutput: Hashable, Sendable {
    public let reference: IntraLineDifferenceSourceReference
    /// Sorted grapheme-safe ranges in the source line's UTF-16 coordinate space.
    public let utf16Ranges: [NSRange]

    fileprivate init(reference: IntraLineDifferenceSourceReference, utf16Ranges: [NSRange]) {
        self.reference = reference
        self.utf16Ranges = utf16Ranges
    }
}

public struct IntraLineDifferencePlanningReceipt: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let currentVersion = 1

    public let version: Int
    public let comparison: IntraLineDifferenceComparisonReference
    public let row: IntraLineDifferenceRowReference
    public let pairKind: IntraLineDifferencePairKind
    public let sourceReference: IntraLineDifferenceSourceReference?
    public let comparisonReference: IntraLineDifferenceSourceReference?
    public let sourceUTF8ByteCount: Int
    public let comparisonUTF8ByteCount: Int
    public let changeCount: Int
    public let workUnitsConsumed: UInt64
    fileprivate init(
        input: IntraLineDifferencePairInput,
        sourceUTF8ByteCount: Int,
        comparisonUTF8ByteCount: Int,
        changeCount: Int,
        workUnitsConsumed: UInt64
    ) {
        version = Self.currentVersion
        comparison = input.row.comparison
        row = input.row
        pairKind = input.kind
        sourceReference = input.source?.reference
        comparisonReference = input.comparison?.reference
        self.sourceUTF8ByteCount = sourceUTF8ByteCount
        self.comparisonUTF8ByteCount = comparisonUTF8ByteCount
        self.changeCount = changeCount
        self.workUnitsConsumed = workUnitsConsumed
    }

    public var description: String {
        "IntraLineDifferencePlanningReceipt(version: \(version), row: \(row.rowIndex), changes: \(changeCount), work: \(workUnitsConsumed), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "version": version,
                "comparison": comparison,
                "row": row,
                "pairKind": pairKind.redactedName,
                "sourceUTF8ByteCount": sourceUTF8ByteCount,
                "comparisonUTF8ByteCount": comparisonUTF8ByteCount,
                "changeCount": changeCount,
                "workUnitsConsumed": workUnitsConsumed
            ],
            displayStyle: .struct
        )
    }
}

public enum IntraLineDifferenceWorkflowError: Error, Equatable, LocalizedError, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    case invalidLimit(IntraLineDifferenceLimit)
    case invalidRowIndex
    case invalidSourceLineNumber
    case missingPairText
    case invalidPairRoles
    case rowIdentityMismatch
    case inconsistentWordBreakConfiguration
    case wordBreakCharactersTooLarge(maximumUTF8Bytes: Int)
    case inputTooLarge(role: IntraLineDifferenceRole, maximumUTF8Bytes: Int)
    case inputTooLong(role: IntraLineDifferenceRole, maximumUTF16Units: Int)
    case tooManyGraphemes(role: IntraLineDifferenceRole, maximumGraphemes: Int)
    case combinedInputTooLarge(maximumUTF8Bytes: Int)
    case graphemeTooLong(role: IntraLineDifferenceRole, maximumUTF16Units: Int)
    case tooManyOutputRanges(maximumRangePairs: Int)
    case workLimitExceeded(maximumWorkUnits: UInt64)
    case cancelled
    case staleOptions
    case staleLimits
    case staleComparison
    case staleRow
    case staleSourceBinding
    case staleComparisonBinding
    case staleSourceText
    case staleComparisonText
    case inconsistentPlan

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let limit):
            "Invalid intra-line difference limit: \(limit.rawValue)."
        case .invalidRowIndex:
            "Intra-line difference row index is invalid."
        case .invalidSourceLineNumber:
            "Intra-line difference source line number is invalid."
        case .missingPairText:
            "Intra-line difference input has no source or comparison text."
        case .invalidPairRoles:
            "Intra-line difference pair roles do not match its pair kind."
        case .rowIdentityMismatch:
            "Intra-line difference text does not match its bound row identity."
        case .inconsistentWordBreakConfiguration:
            "Custom word-break characters require custom-character word-break mode."
        case .wordBreakCharactersTooLarge(let maximumUTF8Bytes):
            "Word-break characters exceed the \(maximumUTF8Bytes)-byte limit."
        case .inputTooLarge(let role, let maximumUTF8Bytes):
            "Intra-line \(role.rawValue) input exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .inputTooLong(let role, let maximumUTF16Units):
            "Intra-line \(role.rawValue) input exceeds the \(maximumUTF16Units)-UTF-16-unit limit."
        case .tooManyGraphemes(let role, let maximumGraphemes):
            "Intra-line \(role.rawValue) input exceeds the \(maximumGraphemes)-grapheme limit."
        case .combinedInputTooLarge(let maximumUTF8Bytes):
            "Combined intra-line input exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .graphemeTooLong(let role, let maximumUTF16Units):
            "Intra-line \(role.rawValue) input contains a grapheme exceeding the \(maximumUTF16Units)-UTF-16-unit limit."
        case .tooManyOutputRanges(let maximumRangePairs):
            "Intra-line output exceeds the \(maximumRangePairs)-range-pair limit."
        case .workLimitExceeded(let maximumWorkUnits):
            "Intra-line planning exceeds the \(maximumWorkUnits)-unit work limit."
        case .cancelled:
            "Intra-line planning was cancelled."
        case .staleOptions:
            "Intra-line options no longer match the planned comparison policy."
        case .staleLimits:
            "Intra-line limits no longer match the planned configuration."
        case .staleComparison:
            "Intra-line comparison identity or revision is stale."
        case .staleRow:
            "Intra-line row identity is stale."
        case .staleSourceBinding:
            "Intra-line source binding is stale."
        case .staleComparisonBinding:
            "Intra-line comparison-side binding is stale."
        case .staleSourceText:
            "Intra-line source text no longer matches the planned input."
        case .staleComparisonText:
            "Intra-line comparison text no longer matches the planned input."
        case .inconsistentPlan:
            "Intra-line planning produced an inconsistent result."
        }
    }

    public var description: String { errorDescription ?? "Intra-line planning failed." }
    public var debugDescription: String { description }
}

public struct IntraLineDifferencePlan: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let row: IntraLineDifferenceRowReference
    public let pairKind: IntraLineDifferencePairKind
    public let source: IntraLineDifferenceSideOutput?
    public let comparison: IntraLineDifferenceSideOutput?
    public let changes: [IntraLineDifferenceRangePair]
    public let options: IntraLineDifferenceOptions
    public let limits: IntraLineDifferenceLimits
    public let receipt: IntraLineDifferencePlanningReceipt

    private let sourceCommitment: IntraLineDifferenceTextCommitment
    private let comparisonCommitment: IntraLineDifferenceTextCommitment

    fileprivate init(
        input: IntraLineDifferencePairInput,
        source: IntraLineDifferenceSideOutput?,
        comparison: IntraLineDifferenceSideOutput?,
        changes: [IntraLineDifferenceRangePair],
        options: IntraLineDifferenceOptions,
        limits: IntraLineDifferenceLimits,
        receipt: IntraLineDifferencePlanningReceipt,
        sourceCommitment: IntraLineDifferenceTextCommitment,
        comparisonCommitment: IntraLineDifferenceTextCommitment
    ) {
        row = input.row
        pairKind = input.kind
        self.source = source
        self.comparison = comparison
        self.changes = changes
        self.options = options
        self.limits = limits
        self.receipt = receipt
        self.sourceCommitment = sourceCommitment
        self.comparisonCommitment = comparisonCommitment
    }

    public var hasDifferences: Bool { !changes.isEmpty }

    public func validateCurrentInput(
        _ input: IntraLineDifferencePairInput,
        options currentOptions: IntraLineDifferenceOptions,
        limits currentLimits: IntraLineDifferenceLimits
    ) throws {
        try IntraLineDifferenceWorkflow.validateCurrent(
            input,
            options: currentOptions,
            currentLimits: currentLimits,
            expectedRow: row,
            expectedPairKind: pairKind,
            expectedSourceReference: source?.reference,
            expectedComparisonReference: comparison?.reference,
            sourceCommitment: sourceCommitment,
            comparisonCommitment: comparisonCommitment,
            expectedOptions: options,
            limits: limits
        )
    }

    public var description: String {
        "IntraLineDifferencePlan(row: \(row.rowIndex), changes: \(changes.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "row": row,
                "pairKind": pairKind.redactedName,
                "sourceRanges": source?.utf16Ranges.count ?? 0,
                "comparisonRanges": comparison?.utf16Ranges.count ?? 0,
                "changes": changes.count,
                "options": "<redacted>",
                "limits": limits,
                "receipt": receipt,
                "commitments": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Bounded UI-independent intra-line planner. Outputs use native text-view UTF-16 coordinates and
/// never split an extended grapheme cluster. Alignment uses at most `(L + 1)²` DP cells per step;
/// lookahead, total work, and cancellation latency all have hard limits.
public enum IntraLineDifferenceWorkflow: Sendable {
    public static func plan(
        _ input: IntraLineDifferencePairInput,
        options: IntraLineDifferenceOptions = .default,
        limits: IntraLineDifferenceLimits = .default
    ) throws -> IntraLineDifferencePlan {
        try validate(limits)
        var work = IntraLineDifferenceWorkBudget(limits: limits)
        try validate(input, options: options, limits: limits, work: &work)

        let sourceTokenization = try input.source.map {
            try tokenize($0, options: options, limits: limits, work: &work)
        }
        let comparisonTokenization = try input.comparison.map {
            try tokenize($0, options: options, limits: limits, work: &work)
        }
        let sourceTokens = sourceTokenization?.tokens ?? []
        let comparisonTokens = comparisonTokenization?.tokens ?? []
        var tokenHunks = try alignedChanges(
            source: sourceTokens,
            comparison: comparisonTokens,
            lookahead: limits.alignmentLookahead,
            maximumResultCount: limits.maximumOutputRangePairs,
            work: &work
        )
        if tokenHunks.isEmpty, (input.source == nil) != (input.comparison == nil) {
            guard limits.maximumOutputRangePairs > 0 else {
                throw IntraLineDifferenceWorkflowError.tooManyOutputRanges(
                    maximumRangePairs: limits.maximumOutputRangePairs
                )
            }
            tokenHunks.append(
                IntraLineDifferenceTokenHunk(source: 0..<0, comparison: 0..<0)
            )
        }
        guard tokenHunks.count <= limits.maximumOutputRangePairs else {
            throw IntraLineDifferenceWorkflowError.tooManyOutputRanges(
                maximumRangePairs: limits.maximumOutputRangePairs
            )
        }

        var changes: [IntraLineDifferenceRangePair] = []
        changes.reserveCapacity(tokenHunks.count)
        for (ordinal, hunk) in tokenHunks.enumerated() {
            try work.consume()
            let sourceRange = sourceTokenization.map {
                if input.comparison == nil {
                    return NSRange(location: 0, length: $0.utf16Count)
                }
                return utf16Range(
                    for: hunk.source,
                    in: $0,
                    alignedWith: hunk.comparison,
                    in: comparisonTokenization
                )
            }
            let comparisonRange = comparisonTokenization.map {
                if input.source == nil {
                    return NSRange(location: 0, length: $0.utf16Count)
                }
                return utf16Range(
                    for: hunk.comparison,
                    in: $0,
                    alignedWith: hunk.source,
                    in: sourceTokenization
                )
            }
            let kind: IntraLineDifferenceChangeKind
            if input.source == nil {
                kind = .insert
            } else if input.comparison == nil {
                kind = .delete
            } else if sourceRange?.length == 0 {
                kind = .insert
            } else if comparisonRange?.length == 0 {
                kind = .delete
            } else {
                kind = .replace
            }
            changes.append(
                IntraLineDifferenceRangePair(
                    ordinal: ordinal,
                    kind: kind,
                    sourceUTF16Range: sourceRange,
                    comparisonUTF16Range: comparisonRange
                )
            )
        }

        var sourceRanges: [NSRange] = []
        var comparisonRanges: [NSRange] = []
        sourceRanges.reserveCapacity(changes.count)
        comparisonRanges.reserveCapacity(changes.count)
        for change in changes {
            try work.consume()
            if let range = change.sourceUTF16Range { sourceRanges.append(range) }
            if let range = change.comparisonUTF16Range { comparisonRanges.append(range) }
        }
        try validateRanges(sourceRanges, in: sourceTokenization, work: &work)
        try validateRanges(comparisonRanges, in: comparisonTokenization, work: &work)
        let sourceCommitment = try IntraLineDifferenceTextCommitment(
            text: input.source?.text,
            binding: input.rowTextBinding.source,
            work: &work
        )
        let comparisonCommitment = try IntraLineDifferenceTextCommitment(
            text: input.comparison?.text,
            binding: input.rowTextBinding.comparison,
            work: &work
        )
        let receipt = IntraLineDifferencePlanningReceipt(
            input: input,
            sourceUTF8ByteCount: sourceTokenization?.utf8Count ?? 0,
            comparisonUTF8ByteCount: comparisonTokenization?.utf8Count ?? 0,
            changeCount: changes.count,
            workUnitsConsumed: work.consumed
        )
        return IntraLineDifferencePlan(
            input: input,
            source: input.source.map {
                IntraLineDifferenceSideOutput(
                    reference: $0.reference,
                    utf16Ranges: sourceRanges
                )
            },
            comparison: input.comparison.map {
                IntraLineDifferenceSideOutput(
                    reference: $0.reference,
                    utf16Ranges: comparisonRanges
                )
            },
            changes: changes,
            options: options,
            limits: limits,
            receipt: receipt,
            sourceCommitment: sourceCommitment,
            comparisonCommitment: comparisonCommitment
        )
    }

    fileprivate static func validateCurrent(
        _ current: IntraLineDifferencePairInput,
        options currentOptions: IntraLineDifferenceOptions,
        currentLimits: IntraLineDifferenceLimits,
        expectedRow: IntraLineDifferenceRowReference,
        expectedPairKind: IntraLineDifferencePairKind,
        expectedSourceReference: IntraLineDifferenceSourceReference?,
        expectedComparisonReference: IntraLineDifferenceSourceReference?,
        sourceCommitment: IntraLineDifferenceTextCommitment,
        comparisonCommitment: IntraLineDifferenceTextCommitment,
        expectedOptions: IntraLineDifferenceOptions,
        limits: IntraLineDifferenceLimits
    ) throws {
        try validate(limits)
        var work = IntraLineDifferenceWorkBudget(limits: limits)
        try work.checkCancellation()
        guard try optionsEqual(currentOptions, expectedOptions, work: &work) else {
            throw IntraLineDifferenceWorkflowError.staleOptions
        }
        guard currentLimits == limits else {
            throw IntraLineDifferenceWorkflowError.staleLimits
        }
        guard current.row.comparison == expectedRow.comparison else {
            throw IntraLineDifferenceWorkflowError.staleComparison
        }
        guard current.kind == expectedPairKind, current.row == expectedRow else {
            throw IntraLineDifferenceWorkflowError.staleRow
        }
        guard current.source?.reference == expectedSourceReference else {
            throw IntraLineDifferenceWorkflowError.staleSourceBinding
        }
        guard current.comparison?.reference == expectedComparisonReference else {
            throw IntraLineDifferenceWorkflowError.staleComparisonBinding
        }

        try validateBindingIdentity(current)
        guard
            try sourceCommitment.matches(
                text: current.source?.text,
                binding: current.rowTextBinding.source,
                work: &work
            )
        else {
            throw IntraLineDifferenceWorkflowError.staleSourceText
        }
        guard
            try comparisonCommitment.matches(
                text: current.comparison?.text,
                binding: current.rowTextBinding.comparison,
                work: &work
            )
        else {
            throw IntraLineDifferenceWorkflowError.staleComparisonText
        }
    }

    private static func optionsEqual(
        _ left: IntraLineDifferenceOptions,
        _ right: IntraLineDifferenceOptions,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> Bool {
        guard left.granularity == right.granularity,
            left.wordBreakMode == right.wordBreakMode,
            left.whitespace == right.whitespace,
            left.ignoreCase == right.ignoreCase,
            left.ignoreNumbers == right.ignoreNumbers,
            left.punctuation == right.punctuation
        else {
            return false
        }
        return try exactTextEqual(
            left.wordBreakCharacters,
            right.wordBreakCharacters,
            work: &work
        )
    }

    private static func validate(_ limits: IntraLineDifferenceLimits) throws {
        let integerLimits: [(Int, Int, IntraLineDifferenceLimit)] = [
            (
                limits.maximumInputUTF8BytesPerSide,
                IntraLineDifferenceLimits.hardMaximumInputUTF8BytesPerSide,
                .inputUTF8BytesPerSide
            ),
            (
                limits.maximumInputUTF16UnitsPerSide,
                IntraLineDifferenceLimits.hardMaximumInputUTF16UnitsPerSide,
                .inputUTF16UnitsPerSide
            ),
            (
                limits.maximumInputGraphemesPerSide,
                IntraLineDifferenceLimits.hardMaximumInputGraphemesPerSide,
                .inputGraphemesPerSide
            ),
            (
                limits.maximumCombinedInputUTF8Bytes,
                IntraLineDifferenceLimits.hardMaximumCombinedInputUTF8Bytes,
                .combinedInputUTF8Bytes
            ),
            (
                limits.maximumGraphemeUTF16Units,
                IntraLineDifferenceLimits.hardMaximumGraphemeUTF16Units,
                .graphemeUTF16Units
            ),
            (
                limits.maximumWordBreakUTF8Bytes,
                IntraLineDifferenceLimits.hardMaximumWordBreakUTF8Bytes,
                .wordBreakUTF8Bytes
            ),
            (
                limits.maximumOutputRangePairs,
                IntraLineDifferenceLimits.hardMaximumOutputRangePairs,
                .outputRangePairs
            )
        ]
        for (value, maximum, limit) in integerLimits where value < 0 || value > maximum {
            throw IntraLineDifferenceWorkflowError.invalidLimit(limit)
        }
        guard limits.alignmentLookahead > 0,
            limits.alignmentLookahead <= IntraLineDifferenceLimits.hardMaximumAlignmentLookahead
        else {
            throw IntraLineDifferenceWorkflowError.invalidLimit(.alignmentLookahead)
        }
        guard limits.maximumWorkUnits > 0,
            limits.maximumWorkUnits <= IntraLineDifferenceLimits.hardMaximumWorkUnits
        else {
            throw IntraLineDifferenceWorkflowError.invalidLimit(.workUnits)
        }
        guard limits.cancellationCheckInterval > 0,
            limits.cancellationCheckInterval
                <= IntraLineDifferenceLimits.hardMaximumCancellationCheckInterval
        else {
            throw IntraLineDifferenceWorkflowError.invalidLimit(.cancellationCheckInterval)
        }
    }

    private static func validate(
        _ input: IntraLineDifferencePairInput,
        options: IntraLineDifferenceOptions,
        limits: IntraLineDifferenceLimits,
        work: inout IntraLineDifferenceWorkBudget
    ) throws {
        guard input.row.rowIndex >= 0 else {
            throw IntraLineDifferenceWorkflowError.invalidRowIndex
        }
        guard input.source != nil || input.comparison != nil else {
            throw IntraLineDifferenceWorkflowError.missingPairText
        }
        for snapshot in [input.source, input.comparison].compactMap({ $0 }) {
            guard snapshot.reference.lineNumber > 0 else {
                throw IntraLineDifferenceWorkflowError.invalidSourceLineNumber
            }
        }
        try validateWordBreakCharacters(options.wordBreakCharacters, limits: limits, work: &work)
        guard
            options.wordBreakMode == .whitespaceOrCustomCharacters
                || options.wordBreakCharacters.isEmpty
        else {
            throw IntraLineDifferenceWorkflowError.inconsistentWordBreakConfiguration
        }
        let sourceBytes = try measure(
            input.source,
            limits: limits,
            work: &work
        )
        let comparisonBytes = try measure(
            input.comparison,
            limits: limits,
            work: &work
        )
        guard sourceBytes <= limits.maximumCombinedInputUTF8Bytes - comparisonBytes else {
            throw IntraLineDifferenceWorkflowError.combinedInputTooLarge(
                maximumUTF8Bytes: limits.maximumCombinedInputUTF8Bytes
            )
        }
        try validateBinding(input, work: &work)
    }

    private static func validateBinding(
        _ input: IntraLineDifferencePairInput,
        work: inout IntraLineDifferenceWorkBudget
    ) throws {
        try validateBindingIdentity(input)
        guard
            try exactTextEqual(
                input.rowTextBinding.source,
                input.source?.text,
                work: &work
            ),
            try exactTextEqual(
                input.rowTextBinding.comparison,
                input.comparison?.text,
                work: &work
            )
        else {
            throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
        }
    }

    private static func validateBindingIdentity(
        _ input: IntraLineDifferencePairInput
    ) throws {
        let sourceRole = input.source?.reference.role
        let comparisonRole = input.comparison?.reference.role
        switch (input.kind, input.row.identity) {
        case (.twoWay(let pair), .twoWay(let id, let kind)):
            guard sourceRole == nil || sourceRole == pair.sourceRole,
                comparisonRole == nil || comparisonRole == pair.comparisonRole
            else {
                throw IntraLineDifferenceWorkflowError.invalidPairRoles
            }
            guard validateTwoWayRow(id, kind: kind),
                validateTwoWayLine(input.source, rowID: id, role: pair.sourceRole),
                validateTwoWayLine(
                    input.comparison,
                    rowID: id,
                    role: pair.comparisonRole
                )
            else {
                throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
            }
        case (.threeWay(let pair), .threeWay(let regionID, let sourceID, let comparisonID)):
            guard regionID >= 0 else {
                throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
            }
            guard sourceRole == nil || sourceRole == pair.sourceRole,
                comparisonRole == nil || comparisonRole == pair.comparisonRole
            else {
                throw IntraLineDifferenceWorkflowError.invalidPairRoles
            }
            guard validateThreeWayLine(input.source, id: sourceID),
                validateThreeWayLine(input.comparison, id: comparisonID)
            else {
                throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
            }
        case (.twoWay, .threeWay), (.threeWay, .twoWay):
            throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
        }
    }

    private static func validateTwoWayLine(
        _ snapshot: IntraLineDifferenceTextSnapshot?,
        rowID: DiffRow.ID,
        role: IntraLineDifferenceRole
    ) -> Bool {
        let expected: Int? =
            switch role {
            case .base: nil
            case .left: rowID.leftNumber
            case .right: rowID.rightNumber
            }
        guard let snapshot else { return expected == nil }
        return snapshot.reference.role == role && expected == snapshot.reference.lineNumber
    }

    private static func validateTwoWayRow(_ id: DiffRow.ID, kind: DiffKind) -> Bool {
        switch kind {
        case .unchanged, .modified:
            id.leftNumber != nil && id.rightNumber != nil
        case .removed:
            id.leftNumber != nil && id.rightNumber == nil
        case .added:
            id.leftNumber == nil && id.rightNumber != nil
        }
    }

    private static func validateThreeWayLine(
        _ snapshot: IntraLineDifferenceTextSnapshot?,
        id: ThreeWayTextMergeLine.ID?
    ) -> Bool {
        switch (snapshot, id) {
        case (.none, .none):
            true
        case (.some(let snapshot), .some(let id)):
            snapshot.reference.role.threeWaySource == id.source
                && snapshot.reference.lineNumber == id.number
        case (.none, .some), (.some, .none):
            false
        }
    }

    private static func measure(
        _ snapshot: IntraLineDifferenceTextSnapshot?,
        limits: IntraLineDifferenceLimits,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> Int {
        guard let snapshot else { return 0 }
        var utf8Count = 0
        var utf16Count = 0
        for scalar in snapshot.text.unicodeScalars {
            let utf8Length = utf8Length(of: scalar)
            let utf16Length = scalar.value > 0xFFFF ? 2 : 1
            try work.consume(UInt64(utf8Length + utf16Length))
            guard utf8Count <= limits.maximumInputUTF8BytesPerSide - utf8Length else {
                throw IntraLineDifferenceWorkflowError.inputTooLarge(
                    role: snapshot.reference.role,
                    maximumUTF8Bytes: limits.maximumInputUTF8BytesPerSide
                )
            }
            guard utf16Count <= limits.maximumInputUTF16UnitsPerSide - utf16Length else {
                throw IntraLineDifferenceWorkflowError.inputTooLong(
                    role: snapshot.reference.role,
                    maximumUTF16Units: limits.maximumInputUTF16UnitsPerSide
                )
            }
            utf8Count += utf8Length
            utf16Count += utf16Length
        }
        return utf8Count
    }

    private static func tokenize(
        _ snapshot: IntraLineDifferenceTextSnapshot,
        options: IntraLineDifferenceOptions,
        limits: IntraLineDifferenceLimits,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> IntraLineDifferenceTokenization {
        var customBreaks: Set<[UInt8]> = []
        if options.wordBreakMode == .whitespaceOrCustomCharacters {
            for character in options.wordBreakCharacters {
                customBreaks.insert(
                    try comparisonBytes(
                        for: character,
                        ignoreCase: options.ignoreCase,
                        work: &work
                    )
                )
            }
        }
        var tokens: [IntraLineDifferenceToken] = []
        var utf16Offset = 0
        var utf8Count = 0
        var graphemeCount = 0
        var pending: IntraLineDifferencePendingToken?

        func finishPending() throws {
            guard let value = pending else { return }
            try work.consume()
            tokens.append(
                IntraLineDifferenceToken(
                    key: value.key,
                    utf16Range: NSRange(
                        location: value.utf16Start,
                        length: value.utf16End - value.utf16Start
                    )
                )
            )
            pending = nil
        }

        let scalars = snapshot.text.unicodeScalars
        var graphemeStart = scalars.startIndex
        while graphemeStart < scalars.endIndex {
            try work.checkCancellation()
            guard graphemeCount < limits.maximumInputGraphemesPerSide else {
                throw IntraLineDifferenceWorkflowError.tooManyGraphemes(
                    role: snapshot.reference.role,
                    maximumGraphemes: limits.maximumInputGraphemesPerSide
                )
            }
            var length = 0
            var graphemeUTF8Length = 0
            var hasBaseScalar = false
            var baseScalarsAreWhitespace = true
            var baseScalarsArePunctuation = true
            var graphemeEnd = graphemeStart
            repeat {
                let scalar = scalars[graphemeEnd]
                let scalarUTF8Length = utf8Length(of: scalar)
                let scalarUTF16Length = scalar.value > 0xFFFF ? 2 : 1
                try work.consume(UInt64(scalarUTF8Length + scalarUTF16Length))
                guard length <= limits.maximumGraphemeUTF16Units - scalarUTF16Length else {
                    throw IntraLineDifferenceWorkflowError.graphemeTooLong(
                        role: snapshot.reference.role,
                        maximumUTF16Units: limits.maximumGraphemeUTF16Units
                    )
                }
                length += scalarUTF16Length
                graphemeUTF8Length += scalarUTF8Length
                if !isDependentScalar(scalar) {
                    hasBaseScalar = true
                    baseScalarsAreWhitespace =
                        baseScalarsAreWhitespace && isComparisonWhitespace(scalar)
                    baseScalarsArePunctuation =
                        baseScalarsArePunctuation
                        && scalar.properties.generalCategory.isPunctuation
                }
                graphemeEnd = scalars.index(after: graphemeEnd)
            } while graphemeEnd < scalars.endIndex
                && graphemeEnd.samePosition(in: snapshot.text) == nil

            guard let character = snapshot.text[graphemeStart..<graphemeEnd].first else {
                throw IntraLineDifferenceWorkflowError.inconsistentPlan
            }
            graphemeStart = graphemeEnd
            graphemeCount += 1
            utf8Count += graphemeUTF8Length
            let category = tokenCategory(
                comparisonBytes: try comparisonBytes(
                    for: character,
                    ignoreCase: options.ignoreCase,
                    work: &work
                ),
                isWhitespace: hasBaseScalar && baseScalarsAreWhitespace,
                isPunctuation: hasBaseScalar && baseScalarsArePunctuation,
                customBreaks: customBreaks
            )
            guard
                let key = try normalizedKey(
                    character,
                    category: category,
                    hasBaseScalar: hasBaseScalar,
                    options: options,
                    work: &work
                )
            else {
                utf16Offset += length
                continue
            }
            let coalescesWhitespace =
                category == .whitespace
                && options.whitespace == .ignoreChanges
            let usesCharacterTokens = options.granularity == .character
            if usesCharacterTokens && !coalescesWhitespace {
                try finishPending()
                pending = IntraLineDifferencePendingToken(
                    key: key,
                    utf16Start: utf16Offset,
                    utf16End: utf16Offset + length
                )
                try finishPending()
            } else if pending?.key.category == category {
                pending?.key.value.append(contentsOf: key.value)
                pending?.utf16End = utf16Offset + length
            } else {
                try finishPending()
                pending = IntraLineDifferencePendingToken(
                    key: key,
                    utf16Start: utf16Offset,
                    utf16End: utf16Offset + length
                )
            }
            utf16Offset += length
        }
        try finishPending()
        try work.checkCancellation()
        var insertionUTF16Gaps: [Range<Int>] = []
        insertionUTF16Gaps.reserveCapacity(tokens.count + 1)
        for index in 0...tokens.count {
            try work.consume()
            let lowerBound = index == 0 ? 0 : NSMaxRange(tokens[index - 1].utf16Range)
            let upperBound =
                index == tokens.count
                ? utf16Offset
                : tokens[index].utf16Range.location
            guard lowerBound <= upperBound else {
                throw IntraLineDifferenceWorkflowError.inconsistentPlan
            }
            insertionUTF16Gaps.append(lowerBound..<upperBound)
        }
        return IntraLineDifferenceTokenization(
            tokens: tokens,
            utf8Count: utf8Count,
            utf16Count: utf16Offset,
            insertionUTF16Gaps: insertionUTF16Gaps
        )
    }

    private static func normalizedKey(
        _ character: Character,
        category: IntraLineDifferenceTokenCategory,
        hasBaseScalar: Bool,
        options: IntraLineDifferenceOptions,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> IntraLineDifferenceTokenKey? {
        if category == .whitespace {
            switch options.whitespace {
            case .compareAll:
                break
            case .ignoreChanges:
                return IntraLineDifferenceTokenKey(category: .whitespace, value: [])
            case .ignoreAll:
                return nil
            }
        }

        if !hasBaseScalar {
            let value = try comparisonBytes(
                for: character,
                ignoreCase: options.ignoreCase,
                work: &work
            )
            return IntraLineDifferenceTokenKey(category: category, value: value)
        }
        var value: [UInt8] = []
        var retainsPreviousBase = false
        var retainedScalars: [Unicode.Scalar] = []
        var pendingDependentScalars: [Unicode.Scalar] = []
        for scalar in character.unicodeScalars {
            try work.consume()
            if isJoinControl(scalar) {
                if retainsPreviousBase { pendingDependentScalars.append(scalar) }
                continue
            }
            if scalar.properties.generalCategory.isDependentMark || isVariationSelector(scalar) {
                if pendingDependentScalars.isEmpty {
                    if retainsPreviousBase { retainedScalars.append(scalar) }
                } else {
                    pendingDependentScalars.append(scalar)
                }
                continue
            }
            let ignoresBase =
                (options.whitespace == .ignoreAll && isComparisonWhitespace(scalar))
                || (options.punctuation == .ignoreAll
                    && scalar.properties.generalCategory.isPunctuation)
                || (options.ignoreNumbers && (48...57).contains(scalar.value))
            guard !ignoresBase else {
                pendingDependentScalars.removeAll(keepingCapacity: true)
                retainsPreviousBase = false
                continue
            }
            if retainsPreviousBase {
                retainedScalars.append(contentsOf: pendingDependentScalars)
            }
            pendingDependentScalars.removeAll(keepingCapacity: true)
            retainsPreviousBase = true
            retainedScalars.append(scalar)
        }
        if retainsPreviousBase {
            retainedScalars.append(contentsOf: pendingDependentScalars)
        }
        let retained = String(String.UnicodeScalarView(retainedScalars))
        let normalized =
            options.ignoreCase
            ? retained.folding(
                options: [.caseInsensitive],
                locale: IntraLineDifferenceLocale.posix
            )
            : retained
        for byte in normalized.utf8 {
            try work.consume()
            value.append(byte)
        }
        guard !value.isEmpty else { return nil }
        return IntraLineDifferenceTokenKey(category: category, value: value)
    }

    private static func comparisonBytes(
        for character: Character,
        ignoreCase: Bool,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> [UInt8] {
        let text = String(character)
        let normalized =
            ignoreCase
            ? text.folding(options: [.caseInsensitive], locale: IntraLineDifferenceLocale.posix)
            : text
        var bytes: [UInt8] = []
        bytes.reserveCapacity(normalized.utf8.count)
        for byte in normalized.utf8 {
            try work.consume()
            bytes.append(byte)
        }
        return bytes
    }

    private static func alignedChanges(
        source: [IntraLineDifferenceToken],
        comparison: [IntraLineDifferenceToken],
        lookahead: Int,
        maximumResultCount: Int,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> [IntraLineDifferenceTokenHunk] {
        var sourceIndex = 0
        var comparisonIndex = 0
        var sourceEnd = source.count
        var comparisonEnd = comparison.count
        var hunkStart: (source: Int, comparison: Int)?
        var result: [IntraLineDifferenceTokenHunk] = []

        func finishHunk() throws {
            guard let start = hunkStart else { return }
            guard result.count < maximumResultCount else {
                throw IntraLineDifferenceWorkflowError.tooManyOutputRanges(
                    maximumRangePairs: maximumResultCount
                )
            }
            result.append(
                IntraLineDifferenceTokenHunk(
                    source: start.source..<sourceIndex,
                    comparison: start.comparison..<comparisonIndex
                )
            )
            hunkStart = nil
        }

        while sourceEnd > sourceIndex, comparisonEnd > comparisonIndex,
            try tokenKeysEqual(
                source[sourceEnd - 1].key,
                comparison[comparisonEnd - 1].key,
                work: &work
            )
        {
            sourceEnd -= 1
            comparisonEnd -= 1
        }
        while sourceIndex < sourceEnd || comparisonIndex < comparisonEnd {
            try work.consume()
            if sourceIndex < sourceEnd, comparisonIndex < comparisonEnd {
                if try tokenKeysEqual(
                    source[sourceIndex].key,
                    comparison[comparisonIndex].key,
                    work: &work
                ) {
                    try finishHunk()
                    sourceIndex += 1
                    comparisonIndex += 1
                    continue
                }
            }
            if hunkStart == nil {
                hunkStart = (sourceIndex, comparisonIndex)
            }
            if sourceIndex == sourceEnd {
                comparisonIndex = comparisonEnd
                break
            }
            if comparisonIndex == comparisonEnd {
                sourceIndex = sourceEnd
                break
            }

            let step = try alignmentStep(
                source: source,
                sourceIndex: sourceIndex,
                sourceEnd: sourceEnd,
                comparison: comparison,
                comparisonIndex: comparisonIndex,
                comparisonEnd: comparisonEnd,
                lookahead: lookahead,
                work: &work
            )
            sourceIndex += step.source
            comparisonIndex += step.comparison
        }
        try finishHunk()
        try work.checkCancellation()
        return result
    }

    private static func alignmentStep(
        source: [IntraLineDifferenceToken],
        sourceIndex: Int,
        sourceEnd: Int,
        comparison: [IntraLineDifferenceToken],
        comparisonIndex: Int,
        comparisonEnd: Int,
        lookahead: Int,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> (source: Int, comparison: Int) {
        let sourceCount = min(sourceEnd - sourceIndex, lookahead)
        let comparisonCount = min(comparisonEnd - comparisonIndex, lookahead)
        let columnCount = comparisonCount + 1
        let (cellCount, overflow) = (sourceCount + 1).multipliedReportingOverflow(
            by: columnCount
        )
        guard !overflow, let chargedCellCount = UInt64(exactly: cellCount) else {
            throw IntraLineDifferenceWorkflowError.workLimitExceeded(
                maximumWorkUnits: work.limits.maximumWorkUnits
            )
        }
        try work.checkCancellation()
        try work.consume(chargedCellCount)
        var scores = Array(repeating: IntraLineDifferenceAlignmentScore.zero, count: cellCount)
        var directions = Array(
            repeating: IntraLineDifferenceAlignmentDirection.replace,
            count: cellCount
        )

        func offset(_ sourceOffset: Int, _ comparisonOffset: Int) -> Int {
            sourceOffset * columnCount + comparisonOffset
        }

        for sourceOffset in stride(from: sourceCount, through: 0, by: -1) {
            for comparisonOffset in stride(from: comparisonCount, through: 0, by: -1) {
                guard sourceOffset < sourceCount || comparisonOffset < comparisonCount else {
                    continue
                }
                if sourceOffset == sourceCount {
                    let next = scores[offset(sourceOffset, comparisonOffset + 1)]
                    scores[offset(sourceOffset, comparisonOffset)] = next.addingGap()
                    directions[offset(sourceOffset, comparisonOffset)] = .insert
                    continue
                }
                if comparisonOffset == comparisonCount {
                    let next = scores[offset(sourceOffset + 1, comparisonOffset)]
                    scores[offset(sourceOffset, comparisonOffset)] = next.addingGap()
                    directions[offset(sourceOffset, comparisonOffset)] = .delete
                    continue
                }

                let keysMatch = try tokenKeysEqual(
                    source[sourceIndex + sourceOffset].key,
                    comparison[comparisonIndex + comparisonOffset].key,
                    work: &work
                )
                if keysMatch {
                    let next = scores[offset(sourceOffset + 1, comparisonOffset + 1)]
                    scores[offset(sourceOffset, comparisonOffset)] = next.addingMatch()
                    directions[offset(sourceOffset, comparisonOffset)] = .match
                    continue
                }

                let replacement = scores[
                    offset(sourceOffset + 1, comparisonOffset + 1)
                ].addingReplacement()
                let deletion = scores[offset(sourceOffset + 1, comparisonOffset)].addingGap()
                let insertion = scores[offset(sourceOffset, comparisonOffset + 1)].addingGap()
                var best = (replacement, IntraLineDifferenceAlignmentDirection.replace)
                if deletion.isBetter(than: best.0) {
                    best = (deletion, .delete)
                }
                if insertion.isBetter(than: best.0) {
                    best = (insertion, .insert)
                }
                scores[offset(sourceOffset, comparisonOffset)] = best.0
                directions[offset(sourceOffset, comparisonOffset)] = best.1
            }
        }

        let firstDirection = directions[offset(0, 0)]
        var sourceOffset = 0
        var comparisonOffset = 0
        while sourceOffset < sourceCount || comparisonOffset < comparisonCount {
            try work.consume()
            switch directions[offset(sourceOffset, comparisonOffset)] {
            case .match:
                if sourceOffset > 0 || comparisonOffset > 0 {
                    return (sourceOffset, comparisonOffset)
                }
                return (1, 1)
            case .replace:
                sourceOffset += 1
                comparisonOffset += 1
            case .delete:
                sourceOffset += 1
            case .insert:
                comparisonOffset += 1
            }
        }
        return firstDirection.advance
    }

    private static func utf16Range(
        for tokenRange: Range<Int>,
        in tokenization: IntraLineDifferenceTokenization,
        alignedWith otherRange: Range<Int>,
        in otherTokenization: IntraLineDifferenceTokenization?
    ) -> NSRange {
        guard !tokenRange.isEmpty else {
            let gap = tokenization.insertionUTF16Gaps[tokenRange.lowerBound]
            let otherGap = otherTokenization.map {
                $0.insertionUTF16Gaps[otherRange.lowerBound]
            }
            let followsIgnoredGap = otherGap?.isEmpty == false
            let location = followsIgnoredGap ? gap.upperBound : gap.lowerBound
            return NSRange(location: location, length: 0)
        }
        let first = tokenization.tokens[tokenRange.lowerBound].utf16Range
        let last = tokenization.tokens[tokenRange.upperBound - 1].utf16Range
        let end = last.location + last.length
        return NSRange(location: first.location, length: end - first.location)
    }

    private static func validateRanges(
        _ ranges: [NSRange],
        in tokenization: IntraLineDifferenceTokenization?,
        work: inout IntraLineDifferenceWorkBudget
    ) throws {
        guard let tokenization else {
            guard ranges.isEmpty else {
                throw IntraLineDifferenceWorkflowError.inconsistentPlan
            }
            return
        }
        var boundaries: Set<Int> = [0, tokenization.utf16Count]
        boundaries.reserveCapacity(tokenization.tokens.count * 2 + 2)
        for token in tokenization.tokens {
            try work.consume()
            boundaries.insert(token.utf16Range.location)
            boundaries.insert(token.utf16Range.location + token.utf16Range.length)
        }
        var previousEnd = 0
        for range in ranges {
            try work.consume()
            let (end, overflow) = range.location.addingReportingOverflow(range.length)
            guard range.location >= previousEnd, range.length >= 0, !overflow,
                end <= tokenization.utf16Count,
                boundaries.contains(range.location),
                boundaries.contains(end)
            else {
                throw IntraLineDifferenceWorkflowError.inconsistentPlan
            }
            previousEnd = end
        }
    }

    private static func exactTextEqual(
        _ left: String?,
        _ right: String?,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> Bool {
        switch (left, right) {
        case (.none, .none):
            return true
        case (.some(let left), .some(let right)):
            var leftIterator = left.utf8.makeIterator()
            var rightIterator = right.utf8.makeIterator()
            while true {
                let leftByte = leftIterator.next()
                let rightByte = rightIterator.next()
                if leftByte != nil || rightByte != nil { try work.consume() }
                guard leftByte == rightByte else { return false }
                if leftByte == nil { return true }
            }
        case (.none, .some), (.some, .none):
            return false
        }
    }

    private static func validateWordBreakCharacters(
        _ characters: String,
        limits: IntraLineDifferenceLimits,
        work: inout IntraLineDifferenceWorkBudget
    ) throws {
        var count = 0
        for _ in characters.utf8 {
            try work.consume()
            guard count < limits.maximumWordBreakUTF8Bytes else {
                throw IntraLineDifferenceWorkflowError.wordBreakCharactersTooLarge(
                    maximumUTF8Bytes: limits.maximumWordBreakUTF8Bytes
                )
            }
            count += 1
        }
    }

    private static func tokenCategory(
        comparisonBytes: [UInt8],
        isWhitespace: Bool,
        isPunctuation: Bool,
        customBreaks: Set<[UInt8]>
    ) -> IntraLineDifferenceTokenCategory {
        if isWhitespace { return .whitespace }
        if isPunctuation { return .punctuation }
        if customBreaks.contains(comparisonBytes) { return .separator }
        return .content
    }

    private static func isComparisonWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x20 || scalar.value == 0x09 || scalar.value == 0x0B
            || scalar.value == 0x0C
    }

    private static func isVariationSelector(_ scalar: Unicode.Scalar) -> Bool {
        (0xFE00...0xFE0F).contains(scalar.value)
            || (0xE0100...0xE01EF).contains(scalar.value)
    }

    private static func isJoinControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x200C || scalar.value == 0x200D
    }

    private static func isDependentScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory.isDependentMark
            || isVariationSelector(scalar)
            || isJoinControl(scalar)
    }

    private static func utf8Length(of scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case 0...0x7F: 1
        case 0x80...0x7FF: 2
        case 0x800...0xFFFF: 3
        default: 4
        }
    }

    private static func appendUTF8(_ scalar: Unicode.Scalar, to bytes: inout [UInt8]) {
        let value = scalar.value
        switch value {
        case 0...0x7F:
            bytes.append(UInt8(value))
        case 0x80...0x7FF:
            bytes.append(UInt8(0xC0 | (value >> 6)))
            bytes.append(UInt8(0x80 | (value & 0x3F)))
        case 0x800...0xFFFF:
            bytes.append(UInt8(0xE0 | (value >> 12)))
            bytes.append(UInt8(0x80 | ((value >> 6) & 0x3F)))
            bytes.append(UInt8(0x80 | (value & 0x3F)))
        default:
            bytes.append(UInt8(0xF0 | (value >> 18)))
            bytes.append(UInt8(0x80 | ((value >> 12) & 0x3F)))
            bytes.append(UInt8(0x80 | ((value >> 6) & 0x3F)))
            bytes.append(UInt8(0x80 | (value & 0x3F)))
        }
    }

    private static func tokenKeysEqual(
        _ left: IntraLineDifferenceTokenKey,
        _ right: IntraLineDifferenceTokenKey,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> Bool {
        try work.consume()
        guard left.category == right.category, left.value.count == right.value.count else {
            return false
        }
        for index in left.value.indices {
            try work.consume()
            guard left.value[index] == right.value[index] else { return false }
        }
        return true
    }

}

private struct IntraLineDifferenceTokenKey: Hashable, Sendable {
    let category: IntraLineDifferenceTokenCategory
    var value: [UInt8]
}

private struct IntraLineDifferenceRowTextBinding: Sendable {
    let source: String?
    let comparison: String?
}

private struct IntraLineDifferenceTextCommitment: Sendable {
    private static let authenticationCodeByteCount = 32
    private static let domain = Data("com.macmerge.intra-line-text-commitment.v1".utf8)
    private static let chunkByteCount = 4_096

    private let key: SymmetricKey
    private let authenticationCode: [UInt8]

    init(
        text: String?,
        binding: String?,
        work: inout IntraLineDifferenceWorkBudget
    ) throws {
        let key = SymmetricKey(size: .bits256)
        let authenticationCode = try Self.authenticationCode(for: text, key: key, work: &work)
        let bindingCode = try Self.authenticationCode(for: binding, key: key, work: &work)
        guard
            try Self.authenticationCodesEqual(
                authenticationCode,
                bindingCode,
                work: &work
            )
        else {
            throw IntraLineDifferenceWorkflowError.rowIdentityMismatch
        }
        guard authenticationCode.count == Self.authenticationCodeByteCount else {
            throw IntraLineDifferenceWorkflowError.inconsistentPlan
        }
        self.key = key
        self.authenticationCode = authenticationCode
    }

    func matches(
        text: String?,
        binding: String?,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> Bool {
        let candidate = try Self.authenticationCode(for: text, key: key, work: &work)
        let bindingCandidate = try Self.authenticationCode(
            for: binding,
            key: key,
            work: &work
        )
        let textMatches = try Self.authenticationCodesEqual(
            authenticationCode,
            candidate,
            work: &work
        )
        let bindingMatches = try Self.authenticationCodesEqual(
            authenticationCode,
            bindingCandidate,
            work: &work
        )
        return textMatches && bindingMatches
    }

    private static func authenticationCodesEqual(
        _ expected: [UInt8],
        _ candidate: [UInt8],
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> Bool {
        guard expected.count == authenticationCodeByteCount,
            candidate.count == authenticationCodeByteCount
        else { return false }
        var difference: UInt8 = 0
        for index in 0..<authenticationCodeByteCount {
            try work.consume()
            difference |= expected[index] ^ candidate[index]
        }
        return difference == 0
    }

    private static func authenticationCode(
        for value: String?,
        key: SymmetricKey,
        work: inout IntraLineDifferenceWorkBudget
    ) throws -> [UInt8] {
        var authenticator = HMAC<SHA256>(key: key)
        try update(domain, authenticator: &authenticator, work: &work)
        guard let value else {
            try update(Data([0]), authenticator: &authenticator, work: &work)
            return Array(authenticator.finalize())
        }

        try update(Data([1]), authenticator: &authenticator, work: &work)
        var chunk: [UInt8] = []
        chunk.reserveCapacity(chunkByteCount)
        for byte in value.utf8 {
            try work.consume()
            chunk.append(byte)
            if chunk.count == chunkByteCount {
                authenticator.update(data: Data(chunk))
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            authenticator.update(data: Data(chunk))
        }
        return Array(authenticator.finalize())
    }

    private static func update(
        _ data: Data,
        authenticator: inout HMAC<SHA256>,
        work: inout IntraLineDifferenceWorkBudget
    ) throws {
        try work.consume(UInt64(data.count))
        authenticator.update(data: data)
    }
}

private struct IntraLineDifferenceToken: Hashable, Sendable {
    let key: IntraLineDifferenceTokenKey
    let utf16Range: NSRange
}

private enum IntraLineDifferenceTokenCategory: Hashable, Sendable {
    case content
    case whitespace
    case punctuation
    case separator
}

private struct IntraLineDifferencePendingToken {
    var key: IntraLineDifferenceTokenKey
    let utf16Start: Int
    var utf16End: Int
}

private struct IntraLineDifferenceTokenization {
    let tokens: [IntraLineDifferenceToken]
    let utf8Count: Int
    let utf16Count: Int
    let insertionUTF16Gaps: [Range<Int>]
}

private struct IntraLineDifferenceTokenHunk {
    let source: Range<Int>
    let comparison: Range<Int>
}

private struct IntraLineDifferenceAlignmentScore: Equatable {
    static let zero = IntraLineDifferenceAlignmentScore(matches: 0, edits: 0, gaps: 0)

    let matches: Int
    let edits: Int
    let gaps: Int

    func addingMatch() -> IntraLineDifferenceAlignmentScore {
        IntraLineDifferenceAlignmentScore(matches: matches + 1, edits: edits, gaps: gaps)
    }

    func addingReplacement() -> IntraLineDifferenceAlignmentScore {
        IntraLineDifferenceAlignmentScore(matches: matches, edits: edits + 1, gaps: gaps)
    }

    func addingGap() -> IntraLineDifferenceAlignmentScore {
        IntraLineDifferenceAlignmentScore(matches: matches, edits: edits + 1, gaps: gaps + 1)
    }

    func isBetter(than other: IntraLineDifferenceAlignmentScore) -> Bool {
        if edits != other.edits { return edits < other.edits }
        if matches != other.matches { return matches > other.matches }
        return gaps < other.gaps
    }
}

private enum IntraLineDifferenceAlignmentDirection {
    case match
    case replace
    case delete
    case insert

    var advance: (source: Int, comparison: Int) {
        switch self {
        case .match, .replace: (1, 1)
        case .delete: (1, 0)
        case .insert: (0, 1)
        }
    }

}

private struct IntraLineDifferenceWorkBudget {
    let limits: IntraLineDifferenceLimits
    private(set) var consumed: UInt64 = 0
    private var uncheckedWork: UInt64 = 0

    init(limits: IntraLineDifferenceLimits) {
        self.limits = limits
    }

    mutating func consume(_ amount: UInt64 = 1) throws {
        guard amount <= limits.maximumWorkUnits - consumed else {
            try checkCancellation()
            throw IntraLineDifferenceWorkflowError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        consumed += amount
        let distance = limits.cancellationCheckInterval - uncheckedWork
        if amount >= distance {
            uncheckedWork = (amount - distance) % limits.cancellationCheckInterval
            try checkCancellation()
        } else {
            uncheckedWork += amount
        }
    }

    func checkCancellation() throws {
        if Task.isCancelled { throw IntraLineDifferenceWorkflowError.cancelled }
    }
}

private enum IntraLineDifferenceLocale {
    static let posix = Locale(identifier: "en_US_POSIX")
}

extension IntraLineDifferenceRole {
    fileprivate var threeWaySource: ThreeWayTextMergeSource {
        switch self {
        case .base: .base
        case .left: .left
        case .right: .right
        }
    }
}

extension IntraLineDifferencePairKind {
    fileprivate var redactedName: String {
        switch self {
        case .twoWay(let pair): "twoWay.\(pair.rawValue)"
        case .threeWay(let pair): "threeWay.\(pair.rawValue)"
        }
    }
}

extension Unicode.GeneralCategory {
    fileprivate var isPunctuation: Bool {
        switch self {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
            .initialPunctuation, .finalPunctuation, .otherPunctuation:
            true
        default:
            false
        }
    }

    fileprivate var isDependentMark: Bool {
        switch self {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            true
        default:
            false
        }
    }
}
