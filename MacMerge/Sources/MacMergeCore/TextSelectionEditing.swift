import Foundation

/// Immutable text-editor state used to create or apply a selection-editing plan.
/// For one `documentID`, the owner must use `revision` as an opaque, never-reused token and
/// advance it whenever `text` or `isEditable` changes. Selection changes are revalidated
/// separately and do not require a new revision.
public struct TextSelectionEditingDocumentSnapshot: Sendable {
    public let documentID: UUID
    public let revision: UInt64
    public let text: String
    /// Zero-based, half-open UTF-16 range. Both bounds must be grapheme boundaries.
    public let selectionRange: NSRange
    public let isEditable: Bool

    public init(
        documentID: UUID,
        revision: UInt64,
        text: String,
        selectionRange: NSRange,
        isEditable: Bool
    ) {
        self.documentID = documentID
        self.revision = revision
        self.text = text
        self.selectionRange = selectionRange
        self.isEditable = isEditable
    }
}

extension TextSelectionEditingDocumentSnapshot: Equatable {
    public static func == (
        lhs: TextSelectionEditingDocumentSnapshot,
        rhs: TextSelectionEditingDocumentSnapshot
    ) -> Bool {
        lhs.documentID == rhs.documentID
            && lhs.revision == rhs.revision
            && lhs.selectionRange == rhs.selectionRange
            && lhs.isEditable == rhs.isEditable
            && textSelectionEditingStringsAreIdentical(lhs.text, rhs.text)
    }
}

public struct TextSelectionEditingLimits: Equatable, Sendable {
    public static let `default` = TextSelectionEditingLimits()

    public let maximumInputUTF16Length: Int
    public let maximumPasteUTF16Length: Int
    public let maximumOutputUTF16Length: Int
    /// Rejects any source or result extended grapheme cluster above this UTF-16 length.
    public let maximumGraphemeClusterUTF16Length: Int
    /// Bounds UTF-16 validation, exact comparison, output assembly, and result validation.
    public let maximumWork: Int

    public init(
        maximumInputUTF16Length: Int = 64 * 1024 * 1024,
        maximumPasteUTF16Length: Int = 64 * 1024 * 1024,
        maximumOutputUTF16Length: Int = 64 * 1024 * 1024,
        maximumGraphemeClusterUTF16Length: Int = 16 * 1024,
        maximumWork: Int = 384 * 1024 * 1024
    ) {
        self.maximumInputUTF16Length = maximumInputUTF16Length
        self.maximumPasteUTF16Length = maximumPasteUTF16Length
        self.maximumOutputUTF16Length = maximumOutputUTF16Length
        self.maximumGraphemeClusterUTF16Length = maximumGraphemeClusterUTF16Length
        self.maximumWork = maximumWork
    }
}

public enum TextSelectionEditingAction: Equatable, Sendable {
    case cut
    case copy
    case paste
    case selectAll
}

/// Plain text supplied by a UI or service boundary. This type never reads a system pasteboard.
public struct TextSelectionEditingPastePayload: Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

extension TextSelectionEditingPastePayload: Equatable {
    public static func == (
        lhs: TextSelectionEditingPastePayload,
        rhs: TextSelectionEditingPastePayload
    ) -> Bool {
        textSelectionEditingStringsAreIdentical(lhs.text, rhs.text)
    }
}

public enum TextSelectionEditingNoOpReason: Equatable, Sendable {
    case emptySelection
    case emptyPastePayload
    case emptyDocument
    case selectionAlreadyCoversDocument
}

/// Receipt describing text, selection, and transfer data committed by a document owner.
public struct TextSelectionEditingApplication: Sendable {
    public let action: TextSelectionEditingAction
    public let documentID: UUID
    public let sourceRevision: UInt64
    public let sourceSelectionRange: NSRange
    public let text: String
    /// Grapheme-safe selection in `text` after the action.
    public let selectionRange: NSRange
    /// Text committed to the owner's transfer service for Cut or Copy.
    public let copiedText: String?
    /// Changed range in source coordinates, or `nil` when text is scalar-identical.
    public let changedSourceRange: NSRange?
    /// Changed range in result coordinates, or `nil` when text is scalar-identical.
    public let changedRange: NSRange?
    public let noOpReason: TextSelectionEditingNoOpReason?
    public let workUnitsConsumed: Int

    public var didChangeText: Bool { changedSourceRange != nil }
    public var didChangeSelection: Bool { sourceSelectionRange != selectionRange }
    public var isNoOp: Bool { noOpReason != nil }
    public var hasEffect: Bool {
        copiedText != nil || didChangeText || didChangeSelection
    }

    fileprivate init(
        action: TextSelectionEditingAction,
        document: TextSelectionEditingDocumentSnapshot,
        text: String,
        selectionRange: NSRange,
        copiedText: String?,
        changedSourceRange: NSRange?,
        changedRange: NSRange?,
        noOpReason: TextSelectionEditingNoOpReason?,
        workUnitsConsumed: Int
    ) {
        self.action = action
        documentID = document.documentID
        sourceRevision = document.revision
        sourceSelectionRange = document.selectionRange
        self.text = text
        self.selectionRange = selectionRange
        self.copiedText = copiedText
        self.changedSourceRange = changedSourceRange
        self.changedRange = changedRange
        self.noOpReason = noOpReason
        self.workUnitsConsumed = workUnitsConsumed
    }
}

extension TextSelectionEditingApplication: Equatable {
    public static func == (
        lhs: TextSelectionEditingApplication,
        rhs: TextSelectionEditingApplication
    ) -> Bool {
        lhs.action == rhs.action
            && lhs.documentID == rhs.documentID
            && lhs.sourceRevision == rhs.sourceRevision
            && lhs.sourceSelectionRange == rhs.sourceSelectionRange
            && lhs.selectionRange == rhs.selectionRange
            && textSelectionEditingOptionalStringsAreIdentical(lhs.copiedText, rhs.copiedText)
            && lhs.changedSourceRange == rhs.changedSourceRange
            && lhs.changedRange == rhs.changedRange
            && lhs.noOpReason == rhs.noOpReason
            && lhs.workUnitsConsumed == rhs.workUnitsConsumed
            && textSelectionEditingStringsAreIdentical(lhs.text, rhs.text)
    }
}

public typealias TextSelectionEditingResult = TextSelectionEditingApplication

/// Immutable CAS input. Only a `TextSelectionEditingAtomicCommitOwner` may commit it.
public struct TextSelectionEditingCommitTransaction: Sendable {
    public let action: TextSelectionEditingAction
    public let expectedDocument: TextSelectionEditingDocumentSnapshot
    public let text: String
    public let selectionRange: NSRange
    public let copiedText: String?
    public let changedSourceRange: NSRange?
    public let changedRange: NSRange?
    public let noOpReason: TextSelectionEditingNoOpReason?
    public let workUnitsConsumed: Int

    public var didChangeText: Bool { changedSourceRange != nil }
    public var didChangeSelection: Bool {
        expectedDocument.selectionRange != selectionRange
    }
    public var isNoOp: Bool { noOpReason != nil }
    public var hasEffect: Bool {
        copiedText != nil || didChangeText || didChangeSelection
    }

    fileprivate init(
        action: TextSelectionEditingAction,
        document: TextSelectionEditingDocumentSnapshot,
        draft: TextSelectionEditingDraft
    ) {
        self.action = action
        expectedDocument = document
        text = draft.text
        selectionRange = draft.selectionRange
        copiedText = draft.copiedText
        changedSourceRange = draft.changedSourceRange
        changedRange = draft.changedRange
        noOpReason = draft.noOpReason
        workUnitsConsumed = draft.workUnitsConsumed
    }
}

extension TextSelectionEditingCommitTransaction: Equatable {
    public static func == (
        lhs: TextSelectionEditingCommitTransaction,
        rhs: TextSelectionEditingCommitTransaction
    ) -> Bool {
        lhs.action == rhs.action
            && lhs.expectedDocument == rhs.expectedDocument
            && lhs.selectionRange == rhs.selectionRange
            && textSelectionEditingOptionalStringsAreIdentical(lhs.copiedText, rhs.copiedText)
            && lhs.changedSourceRange == rhs.changedSourceRange
            && lhs.changedRange == rhs.changedRange
            && lhs.noOpReason == rhs.noOpReason
            && lhs.workUnitsConsumed == rhs.workUnitsConsumed
            && textSelectionEditingStringsAreIdentical(lhs.text, rhs.text)
    }
}

public enum TextSelectionEditingAtomicCommitOutcome: Equatable, Sendable {
    /// Owner compared live state and committed every transaction effect in one isolation turn.
    case committed
    /// Owner observed a mismatch and committed no transaction effect.
    case notCommitted(currentDocument: TextSelectionEditingDocumentSnapshot)
}

/// Exclusive owner of document and transfer state used by selection editing.
///
/// `compareAndCommit(_:)` is deliberately synchronous and actor-isolated. Its implementation must,
/// without suspending, compare live document identity, revision, exact text, selection, and
/// editability with `transaction.expectedDocument` using its scalar-exact equality. If they all
/// match, it must atomically commit `text`, `selectionRange`, and non-`nil` `copiedText`, advance its
/// revision when text changes, and return `.committed`. A `nil` `copiedText` leaves transfer state
/// unchanged. Otherwise it must commit nothing and return `.notCommitted` with the live snapshot
/// captured in that same isolation turn. Every mutation of owned state must use the same actor.
public protocol TextSelectionEditingAtomicCommitOwner: Actor {
    func compareAndCommit(
        _ transaction: TextSelectionEditingCommitTransaction
    ) -> TextSelectionEditingAtomicCommitOutcome
}

private struct TextSelectionEditingDraft: Sendable {
    let text: String
    let selectionRange: NSRange
    let copiedText: String?
    let changedSourceRange: NSRange?
    let changedRange: NSRange?
    let noOpReason: TextSelectionEditingNoOpReason?
    let workUnitsConsumed: Int

    func application(
        action: TextSelectionEditingAction,
        document: TextSelectionEditingDocumentSnapshot
    ) -> TextSelectionEditingApplication {
        TextSelectionEditingApplication(
            action: action,
            document: document,
            text: text,
            selectionRange: selectionRange,
            copiedText: copiedText,
            changedSourceRange: changedSourceRange,
            changedRange: changedRange,
            noOpReason: noOpReason,
            workUnitsConsumed: workUnitsConsumed
        )
    }
}

extension TextSelectionEditingDraft: Equatable {
    static func == (
        lhs: TextSelectionEditingDraft,
        rhs: TextSelectionEditingDraft
    ) -> Bool {
        lhs.selectionRange == rhs.selectionRange
            && textSelectionEditingOptionalStringsAreIdentical(lhs.copiedText, rhs.copiedText)
            && lhs.changedSourceRange == rhs.changedSourceRange
            && lhs.changedRange == rhs.changedRange
            && lhs.noOpReason == rhs.noOpReason
            && lhs.workUnitsConsumed == rhs.workUnitsConsumed
            && textSelectionEditingStringsAreIdentical(lhs.text, rhs.text)
    }
}

public enum TextSelectionEditingError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case documentNotEditable
    case pastePayloadRequired
    case unexpectedPastePayload
    case inputTooLarge(maximumUTF16Length: Int)
    case pastePayloadTooLarge(maximumUTF16Length: Int)
    case outputTooLarge(maximumUTF16Length: Int)
    case invalidSelectionRange(range: NSRange, documentUTF16Length: Int)
    case selectionSplitsGrapheme(NSRange)
    case graphemeSegmentationTooComplex(maximumClusterUTF16Length: Int)
    case workLimitExceeded(maximumWork: Int)
    case documentIDChanged(expected: UUID, actual: UUID)
    case documentRevisionChanged(expected: UInt64, actual: UInt64)
    case documentTextChanged
    case documentSelectionChanged(expected: NSRange, actual: NSRange)
    case documentEditabilityChanged(expected: Bool, actual: Bool)
    case inconsistentCommitOutcome
    case inconsistentPlan

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Text selection-editing limits are invalid."
        case .documentNotEditable:
            "Cut and Paste require an editable document."
        case .pastePayloadRequired:
            "Paste requires a text payload."
        case .unexpectedPastePayload:
            "Only Paste accepts a text payload."
        case .inputTooLarge(let maximumUTF16Length):
            "Text exceeds the \(maximumUTF16Length)-UTF-16-unit selection-editing input limit."
        case .pastePayloadTooLarge(let maximumUTF16Length):
            "Paste text exceeds the \(maximumUTF16Length)-UTF-16-unit payload limit."
        case .outputTooLarge(let maximumUTF16Length):
            "Selection editing exceeds the \(maximumUTF16Length)-UTF-16-unit output limit."
        case .invalidSelectionRange(let range, let documentUTF16Length):
            "UTF-16 selection {\(range.location), \(range.length)} is outside the \(documentUTF16Length)-unit document."
        case .selectionSplitsGrapheme(let range):
            "UTF-16 selection {\(range.location), \(range.length)} splits an extended grapheme cluster."
        case .graphemeSegmentationTooComplex(let maximumClusterUTF16Length):
            "Text contains an extended grapheme cluster exceeding the \(maximumClusterUTF16Length)-UTF-16-unit limit."
        case .workLimitExceeded(let maximumWork):
            "Text selection editing exceeds the \(maximumWork)-unit work limit."
        case .documentIDChanged:
            "The selection-editing plan belongs to another document."
        case .documentRevisionChanged(let expected, let actual):
            "Selection editing was planned for document revision \(expected), not revision \(actual)."
        case .documentTextChanged:
            "Document text no longer matches the text used to plan selection editing."
        case .documentSelectionChanged(let expected, let actual):
            "Document selection changed from {\(expected.location), \(expected.length)} to {\(actual.location), \(actual.length)}."
        case .documentEditabilityChanged(let expected, let actual):
            "Document editability changed from \(expected) to \(actual)."
        case .inconsistentCommitOutcome:
            "The document owner rejected a selection-editing transaction without reporting a live-state mismatch."
        case .inconsistentPlan:
            "Selection editing produced an inconsistent result."
        }
    }
}

/// Immutable operation derived from one exact document state.
public struct TextSelectionEditingPlan: Sendable {
    public let action: TextSelectionEditingAction
    public let pastePayload: TextSelectionEditingPastePayload?
    public let sourceDocumentID: UUID
    public let sourceRevision: UInt64
    public let sourceUTF16Length: Int

    private let draft: TextSelectionEditingDraft
    private let sourceText: String
    private let sourceSelectionRange: NSRange
    private let sourceIsEditable: Bool
    private let limits: TextSelectionEditingLimits

    public var changedSourceRange: NSRange? { draft.changedSourceRange }
    public var changedRange: NSRange? { draft.changedRange }
    public var noOpReason: TextSelectionEditingNoOpReason? { draft.noOpReason }
    public var didChangeText: Bool { draft.changedSourceRange != nil }
    public var didChangeSelection: Bool { sourceSelectionRange != draft.selectionRange }
    public var isNoOp: Bool { draft.noOpReason != nil }
    public var hasEffect: Bool {
        draft.copiedText != nil || didChangeText || didChangeSelection
    }
    public var workUnitsConsumed: Int { draft.workUnitsConsumed }

    fileprivate init(
        action: TextSelectionEditingAction,
        pastePayload: TextSelectionEditingPastePayload?,
        document: TextSelectionEditingDocumentSnapshot,
        sourceUTF16Length: Int,
        draft: TextSelectionEditingDraft,
        limits: TextSelectionEditingLimits
    ) {
        self.action = action
        self.pastePayload = pastePayload
        sourceDocumentID = document.documentID
        sourceRevision = document.revision
        self.sourceUTF16Length = sourceUTF16Length
        self.draft = draft
        sourceText = document.text
        sourceSelectionRange = document.selectionRange
        sourceIsEditable = document.isEditable
        self.limits = limits
    }

    /// Commits through the document owner's synchronous actor-isolated CAS operation.
    /// A successful application is returned only after the owner reports an atomic commit.
    public func commit<Owner: TextSelectionEditingAtomicCommitOwner>(
        to owner: isolated Owner
    ) throws -> TextSelectionEditingApplication {
        try Task.checkCancellation()
        let sourceDocument = TextSelectionEditingDocumentSnapshot(
            documentID: sourceDocumentID,
            revision: sourceRevision,
            text: sourceText,
            selectionRange: sourceSelectionRange,
            isEditable: sourceIsEditable
        )
        let transaction = TextSelectionEditingCommitTransaction(
            action: action,
            document: sourceDocument,
            draft: draft
        )
        switch owner.compareAndCommit(transaction) {
        case .committed:
            return draft.application(action: action, document: sourceDocument)
        case .notCommitted(let currentDocument):
            try validateCommitConflict(currentDocument)
            throw TextSelectionEditingError.inconsistentCommitOutcome
        }
    }

    private func validateCommitConflict(
        _ document: TextSelectionEditingDocumentSnapshot
    ) throws {
        guard document.documentID == sourceDocumentID else {
            throw TextSelectionEditingError.documentIDChanged(
                expected: sourceDocumentID,
                actual: document.documentID
            )
        }
        guard document.revision == sourceRevision else {
            throw TextSelectionEditingError.documentRevisionChanged(
                expected: sourceRevision,
                actual: document.revision
            )
        }
        guard document.selectionRange == sourceSelectionRange else {
            throw TextSelectionEditingError.documentSelectionChanged(
                expected: sourceSelectionRange,
                actual: document.selectionRange
            )
        }
        guard document.isEditable == sourceIsEditable else {
            throw TextSelectionEditingError.documentEditabilityChanged(
                expected: sourceIsEditable,
                actual: document.isEditable
            )
        }

        var work = TextSelectionEditingWorkBudget(maximum: limits.maximumWork)
        let validation = try textSelectionEditingValidate(
            document.text,
            against: sourceText,
            expectedUTF16Length: sourceUTF16Length,
            maximum: limits.maximumInputUTF16Length,
            work: &work
        )
        guard validation.utf16Length == sourceUTF16Length, validation.isIdentical else {
            throw TextSelectionEditingError.documentTextChanged
        }
        if action.requiresEditableDocument, !document.isEditable {
            throw TextSelectionEditingError.documentNotEditable
        }
        try Task.checkCancellation()
    }
}

extension TextSelectionEditingPlan: Equatable {
    public static func == (
        lhs: TextSelectionEditingPlan,
        rhs: TextSelectionEditingPlan
    ) -> Bool {
        lhs.action == rhs.action
            && lhs.pastePayload == rhs.pastePayload
            && lhs.sourceDocumentID == rhs.sourceDocumentID
            && lhs.sourceRevision == rhs.sourceRevision
            && lhs.sourceUTF16Length == rhs.sourceUTF16Length
            && lhs.sourceSelectionRange == rhs.sourceSelectionRange
            && lhs.sourceIsEditable == rhs.sourceIsEditable
            && lhs.limits == rhs.limits
            && lhs.draft == rhs.draft
            && textSelectionEditingStringsAreIdentical(lhs.sourceText, rhs.sourceText)
    }
}

public enum TextSelectionEditingPlanner: Sendable {
    public static func cut(
        in document: TextSelectionEditingDocumentSnapshot,
        limits: TextSelectionEditingLimits = .default
    ) throws -> TextSelectionEditingPlan {
        try plan(.cut, in: document, limits: limits)
    }

    public static func copy(
        in document: TextSelectionEditingDocumentSnapshot,
        limits: TextSelectionEditingLimits = .default
    ) throws -> TextSelectionEditingPlan {
        try plan(.copy, in: document, limits: limits)
    }

    public static func paste(
        in document: TextSelectionEditingDocumentSnapshot,
        payload: TextSelectionEditingPastePayload,
        limits: TextSelectionEditingLimits = .default
    ) throws -> TextSelectionEditingPlan {
        try plan(.paste, in: document, pastePayload: payload, limits: limits)
    }

    public static func paste(
        in document: TextSelectionEditingDocumentSnapshot,
        text: String,
        limits: TextSelectionEditingLimits = .default
    ) throws -> TextSelectionEditingPlan {
        try paste(
            in: document,
            payload: TextSelectionEditingPastePayload(text: text),
            limits: limits
        )
    }

    public static func selectAll(
        in document: TextSelectionEditingDocumentSnapshot,
        limits: TextSelectionEditingLimits = .default
    ) throws -> TextSelectionEditingPlan {
        try plan(.selectAll, in: document, limits: limits)
    }

    public static func plan(
        _ action: TextSelectionEditingAction,
        in document: TextSelectionEditingDocumentSnapshot,
        pastePayload: TextSelectionEditingPastePayload? = nil,
        limits: TextSelectionEditingLimits = .default
    ) throws -> TextSelectionEditingPlan {
        try Task.checkCancellation()
        try validate(limits)
        switch action {
        case .paste:
            guard pastePayload != nil else {
                throw TextSelectionEditingError.pastePayloadRequired
            }
        case .cut, .copy, .selectAll:
            guard pastePayload == nil else {
                throw TextSelectionEditingError.unexpectedPastePayload
            }
        }
        if action.requiresEditableDocument, !document.isEditable {
            throw TextSelectionEditingError.documentNotEditable
        }

        var work = TextSelectionEditingWorkBudget(maximum: limits.maximumWork)
        let uncheckedSelectionEnd = uncheckedSelectionEnd(document.selectionRange)
        let analysis = try analyze(
            document.text,
            selectionRange: document.selectionRange,
            uncheckedSelectionEnd: uncheckedSelectionEnd,
            capturesSelection: action != .selectAll,
            maximumInputUTF16Length: limits.maximumInputUTF16Length,
            maximumGraphemeClusterUTF16Length: limits.maximumGraphemeClusterUTF16Length,
            work: &work
        )
        let inputLength = analysis.utf16Length
        let payloadLength: Int
        if let pastePayload {
            payloadLength = try textSelectionEditingUTF16Length(
                of: pastePayload.text,
                maximum: limits.maximumPasteUTF16Length,
                limitError: .pastePayloadTooLarge(
                    maximumUTF16Length: limits.maximumPasteUTF16Length
                ),
                work: &work
            )
        } else {
            payloadLength = 0
        }
        let selectionEnd = try validateBasicSelection(
            document.selectionRange,
            documentUTF16Length: inputLength
        )
        let outputLength = try expectedOutputLength(
            action: action,
            inputLength: inputLength,
            selectionLength: document.selectionRange.length,
            pasteLength: payloadLength,
            maximum: limits.maximumOutputUTF16Length
        )
        if action == .cut || action == .copy {
            guard document.selectionRange.length <= limits.maximumOutputUTF16Length else {
                throw TextSelectionEditingError.outputTooLarge(
                    maximumUTF16Length: limits.maximumOutputUTF16Length
                )
            }
        }

        guard !analysis.containsOversizedGraphemeCluster else {
            try Task.checkCancellation()
            throw TextSelectionEditingError.graphemeSegmentationTooComplex(
                maximumClusterUTF16Length: limits.maximumGraphemeClusterUTF16Length
            )
        }
        guard analysis.selectionStartsAtGraphemeBoundary,
            analysis.selectionEndsAtGraphemeBoundary
        else {
            throw TextSelectionEditingError.selectionSplitsGrapheme(
                document.selectionRange
            )
        }
        if action != .selectAll,
            analysis.selectedTextUTF16Length != document.selectionRange.length
        {
            throw TextSelectionEditingError.inconsistentPlan
        }

        let draft: TextSelectionEditingDraft
        switch action {
        case .cut:
            draft = try cutDraft(
                document: document,
                selectedText: analysis.selectedText,
                sourceUTF16Length: inputLength,
                outputLength: outputLength,
                limits: limits,
                work: &work
            )
        case .copy:
            draft = copyDraft(
                document: document,
                selectedText: analysis.selectedText,
                workUnitsConsumed: work.consumed
            )
        case .paste:
            guard let pastePayload else {
                throw TextSelectionEditingError.inconsistentPlan
            }
            draft = try pasteDraft(
                document: document,
                selectedText: analysis.selectedText,
                selectionEnd: selectionEnd,
                payload: pastePayload,
                payloadUTF16Length: payloadLength,
                sourceUTF16Length: inputLength,
                outputLength: outputLength,
                limits: limits,
                work: &work
            )
        case .selectAll:
            draft = selectAllDraft(
                document: document,
                inputLength: inputLength,
                workUnitsConsumed: work.consumed
            )
        }
        try Task.checkCancellation()
        return TextSelectionEditingPlan(
            action: action,
            pastePayload: pastePayload,
            document: document,
            sourceUTF16Length: inputLength,
            draft: draft,
            limits: limits
        )
    }

    private static func cutDraft(
        document: TextSelectionEditingDocumentSnapshot,
        selectedText: String?,
        sourceUTF16Length: Int,
        outputLength: Int,
        limits: TextSelectionEditingLimits,
        work: inout TextSelectionEditingWorkBudget
    ) throws -> TextSelectionEditingDraft {
        guard document.selectionRange.length > 0 else {
            return noOpDraft(
                document: document,
                noOpReason: .emptySelection,
                workUnitsConsumed: work.consumed
            )
        }
        guard let selectedText else {
            throw TextSelectionEditingError.inconsistentPlan
        }

        let resultText = try replacingSelection(
            in: document.text,
            selectionRange: document.selectionRange,
            with: "",
            sourceUTF16Length: sourceUTF16Length,
            replacementUTF16Length: 0,
            expectedUTF16Length: outputLength,
            work: &work
        )
        let insertionOffset = try resolvedInsertionOffset(
            in: resultText,
            textUTF16Length: outputLength,
            preferredUTF16Offset: document.selectionRange.location,
            maximumGraphemeClusterUTF16Length: limits.maximumGraphemeClusterUTF16Length,
            work: &work
        )
        return TextSelectionEditingDraft(
            text: resultText,
            selectionRange: NSRange(location: insertionOffset, length: 0),
            copiedText: selectedText,
            changedSourceRange: document.selectionRange,
            changedRange: NSRange(location: document.selectionRange.location, length: 0),
            noOpReason: nil,
            workUnitsConsumed: work.consumed
        )
    }

    private static func copyDraft(
        document: TextSelectionEditingDocumentSnapshot,
        selectedText: String?,
        workUnitsConsumed: Int
    ) -> TextSelectionEditingDraft {
        guard document.selectionRange.length > 0 else {
            return noOpDraft(
                document: document,
                noOpReason: .emptySelection,
                workUnitsConsumed: workUnitsConsumed
            )
        }
        return TextSelectionEditingDraft(
            text: document.text,
            selectionRange: document.selectionRange,
            copiedText: selectedText,
            changedSourceRange: nil,
            changedRange: nil,
            noOpReason: nil,
            workUnitsConsumed: workUnitsConsumed
        )
    }

    private static func pasteDraft(
        document: TextSelectionEditingDocumentSnapshot,
        selectedText: String?,
        selectionEnd: Int,
        payload: TextSelectionEditingPastePayload,
        payloadUTF16Length: Int,
        sourceUTF16Length: Int,
        outputLength: Int,
        limits: TextSelectionEditingLimits,
        work: inout TextSelectionEditingWorkBudget
    ) throws -> TextSelectionEditingDraft {
        guard document.selectionRange.length > 0 || !payload.text.isEmpty else {
            return noOpDraft(
                document: document,
                noOpReason: .emptyPastePayload,
                workUnitsConsumed: work.consumed
            )
        }
        guard let selectedText else {
            throw TextSelectionEditingError.inconsistentPlan
        }

        let textChanges = try !textSelectionEditingStringsAreIdentical(
            selectedText,
            payload.text,
            lhsUTF16Length: document.selectionRange.length,
            rhsUTF16Length: payloadUTF16Length,
            work: &work
        )
        let resultText: String
        let resultSelectionOffset: Int
        if textChanges {
            resultText = try replacingSelection(
                in: document.text,
                selectionRange: document.selectionRange,
                with: payload.text,
                sourceUTF16Length: sourceUTF16Length,
                replacementUTF16Length: payloadUTF16Length,
                expectedUTF16Length: outputLength,
                work: &work
            )
            let (preferredOffset, overflow) = document.selectionRange.location
                .addingReportingOverflow(payloadUTF16Length)
            guard !overflow else {
                try Task.checkCancellation()
                throw TextSelectionEditingError.inconsistentPlan
            }
            resultSelectionOffset = try resolvedInsertionOffset(
                in: resultText,
                textUTF16Length: outputLength,
                preferredUTF16Offset: preferredOffset,
                maximumGraphemeClusterUTF16Length: limits.maximumGraphemeClusterUTF16Length,
                work: &work
            )
        } else {
            resultText = document.text
            resultSelectionOffset = selectionEnd
        }

        return TextSelectionEditingDraft(
            text: resultText,
            selectionRange: NSRange(location: resultSelectionOffset, length: 0),
            copiedText: nil,
            changedSourceRange: textChanges ? document.selectionRange : nil,
            changedRange: textChanges
                ? NSRange(
                    location: document.selectionRange.location,
                    length: payloadUTF16Length
                )
                : nil,
            noOpReason: nil,
            workUnitsConsumed: work.consumed
        )
    }

    private static func selectAllDraft(
        document: TextSelectionEditingDocumentSnapshot,
        inputLength: Int,
        workUnitsConsumed: Int
    ) -> TextSelectionEditingDraft {
        let selection = NSRange(location: 0, length: inputLength)
        let noOpReason: TextSelectionEditingNoOpReason?
        if inputLength == 0 {
            noOpReason = .emptyDocument
        } else if document.selectionRange == selection {
            noOpReason = .selectionAlreadyCoversDocument
        } else {
            noOpReason = nil
        }
        return TextSelectionEditingDraft(
            text: document.text,
            selectionRange: selection,
            copiedText: nil,
            changedSourceRange: nil,
            changedRange: nil,
            noOpReason: noOpReason,
            workUnitsConsumed: workUnitsConsumed
        )
    }

    private static func noOpDraft(
        document: TextSelectionEditingDocumentSnapshot,
        noOpReason: TextSelectionEditingNoOpReason,
        workUnitsConsumed: Int
    ) -> TextSelectionEditingDraft {
        TextSelectionEditingDraft(
            text: document.text,
            selectionRange: document.selectionRange,
            copiedText: nil,
            changedSourceRange: nil,
            changedRange: nil,
            noOpReason: noOpReason,
            workUnitsConsumed: workUnitsConsumed
        )
    }

    private static func validate(_ limits: TextSelectionEditingLimits) throws {
        guard limits.maximumInputUTF16Length >= 0,
            limits.maximumPasteUTF16Length >= 0,
            limits.maximumOutputUTF16Length >= 0,
            limits.maximumGraphemeClusterUTF16Length > 0,
            limits.maximumWork >= 0
        else {
            throw TextSelectionEditingError.invalidLimits
        }
    }

    private static func validateBasicSelection(
        _ range: NSRange,
        documentUTF16Length: Int
    ) throws -> Int {
        let (end, overflow) = range.location.addingReportingOverflow(range.length)
        guard range.location >= 0,
            range.location != NSNotFound,
            range.length >= 0,
            !overflow,
            end <= documentUTF16Length
        else {
            throw TextSelectionEditingError.invalidSelectionRange(
                range: range,
                documentUTF16Length: documentUTF16Length
            )
        }
        return end
    }

    private static func uncheckedSelectionEnd(_ range: NSRange) -> Int? {
        guard range.location >= 0,
            range.location != NSNotFound,
            range.length >= 0
        else {
            return nil
        }
        let (end, overflow) = range.location.addingReportingOverflow(range.length)
        return overflow ? nil : end
    }

    private static func expectedOutputLength(
        action: TextSelectionEditingAction,
        inputLength: Int,
        selectionLength: Int,
        pasteLength: Int,
        maximum: Int
    ) throws -> Int {
        let replacementLength = action == .paste ? pasteLength : 0
        let result: Int
        switch action {
        case .cut, .paste:
            let remaining = inputLength - selectionLength
            let (length, overflow) = remaining.addingReportingOverflow(replacementLength)
            guard !overflow, length >= 0 else {
                throw TextSelectionEditingError.outputTooLarge(
                    maximumUTF16Length: maximum
                )
            }
            result = length
        case .copy, .selectAll:
            result = inputLength
        }
        guard result <= maximum else {
            throw TextSelectionEditingError.outputTooLarge(
                maximumUTF16Length: maximum
            )
        }
        return result
    }
}

private struct TextSelectionEditingAnalysis {
    let utf16Length: Int
    let selectionStartsAtGraphemeBoundary: Bool
    let selectionEndsAtGraphemeBoundary: Bool
    let selectedText: String?
    let selectedTextUTF16Length: Int
    let containsOversizedGraphemeCluster: Bool
}

private func analyze(
    _ text: String,
    selectionRange: NSRange,
    uncheckedSelectionEnd: Int?,
    capturesSelection: Bool,
    maximumInputUTF16Length: Int,
    maximumGraphemeClusterUTF16Length: Int,
    work: inout TextSelectionEditingWorkBudget
) throws -> TextSelectionEditingAnalysis {
    var selectionStartsAtBoundary = false
    var selectionEndsAtBoundary = false
    var selectedText = ""
    var selectedTextUTF16Length = 0
    var recognizer = Unicode._CharacterRecognizer()
    var clusterLength = 0
    var containsOversizedGraphemeCluster = false
    var utf16Offset = 0
    var isFirstScalar = true

    for scalar in text.unicodeScalars {
        let hasBreak = recognizer.hasBreak(before: scalar)
        if isFirstScalar || hasBreak {
            clusterLength = 0
            if utf16Offset == selectionRange.location {
                selectionStartsAtBoundary = true
            }
            if utf16Offset == uncheckedSelectionEnd {
                selectionEndsAtBoundary = true
            }
        }

        let scalarLength = textSelectionEditingUTF16Length(of: scalar)
        try work.consume(scalarLength)
        guard utf16Offset <= maximumInputUTF16Length - scalarLength else {
            try Task.checkCancellation()
            throw TextSelectionEditingError.inputTooLarge(
                maximumUTF16Length: maximumInputUTF16Length
            )
        }
        if clusterLength <= maximumGraphemeClusterUTF16Length - scalarLength {
            clusterLength += scalarLength
        } else {
            containsOversizedGraphemeCluster = true
        }
        if capturesSelection,
            let uncheckedSelectionEnd,
            utf16Offset >= selectionRange.location,
            utf16Offset < uncheckedSelectionEnd
        {
            selectedText.unicodeScalars.append(scalar)
            selectedTextUTF16Length += scalarLength
        }
        utf16Offset += scalarLength
        isFirstScalar = false
    }

    if utf16Offset == selectionRange.location {
        selectionStartsAtBoundary = true
    }
    if utf16Offset == uncheckedSelectionEnd {
        selectionEndsAtBoundary = true
    }
    try Task.checkCancellation()
    return TextSelectionEditingAnalysis(
        utf16Length: utf16Offset,
        selectionStartsAtGraphemeBoundary: selectionStartsAtBoundary,
        selectionEndsAtGraphemeBoundary: selectionEndsAtBoundary,
        selectedText: capturesSelection ? selectedText : nil,
        selectedTextUTF16Length: selectedTextUTF16Length,
        containsOversizedGraphemeCluster: containsOversizedGraphemeCluster
    )
}

/// Appends Unicode scalars directly so neither retained text nor payload line endings are normalized.
private func replacingSelection(
    in source: String,
    selectionRange: NSRange,
    with replacement: String,
    sourceUTF16Length: Int,
    replacementUTF16Length: Int,
    expectedUTF16Length: Int,
    work: inout TextSelectionEditingWorkBudget
) throws -> String {
    let selectionEnd = selectionRange.location + selectionRange.length
    var result = ""
    var sourceOffset = 0
    var resultUTF16Length = 0
    var insertedReplacement = false

    for scalar in source.unicodeScalars {
        if !insertedReplacement, sourceOffset == selectionRange.location {
            try append(
                replacement,
                to: &result,
                expectedUTF16Length: replacementUTF16Length,
                work: &work
            )
            resultUTF16Length += replacementUTF16Length
            insertedReplacement = true
        }
        let scalarLength = textSelectionEditingUTF16Length(of: scalar)
        try work.consume(scalarLength)
        if sourceOffset < selectionRange.location || sourceOffset >= selectionEnd {
            result.unicodeScalars.append(scalar)
            resultUTF16Length += scalarLength
        }
        sourceOffset += scalarLength
    }
    if !insertedReplacement, sourceOffset == selectionRange.location {
        try append(
            replacement,
            to: &result,
            expectedUTF16Length: replacementUTF16Length,
            work: &work
        )
        resultUTF16Length += replacementUTF16Length
        insertedReplacement = true
    }
    guard insertedReplacement,
        sourceOffset == sourceUTF16Length,
        resultUTF16Length == expectedUTF16Length
    else {
        throw TextSelectionEditingError.inconsistentPlan
    }
    try Task.checkCancellation()
    return result
}

private func append(
    _ text: String,
    to result: inout String,
    expectedUTF16Length: Int,
    work: inout TextSelectionEditingWorkBudget
) throws {
    var appendedUTF16Length = 0
    for scalar in text.unicodeScalars {
        let scalarLength = textSelectionEditingUTF16Length(of: scalar)
        try work.consume(scalarLength)
        result.unicodeScalars.append(scalar)
        appendedUTF16Length += scalarLength
    }
    guard appendedUTF16Length == expectedUTF16Length else {
        try Task.checkCancellation()
        throw TextSelectionEditingError.inconsistentPlan
    }
}

/// If replacement joins neighboring scalars into one grapheme, moves the insertion point to that
/// grapheme's following boundary instead of returning a split selection.
private func resolvedInsertionOffset(
    in text: String,
    textUTF16Length: Int,
    preferredUTF16Offset: Int,
    maximumGraphemeClusterUTF16Length: Int,
    work: inout TextSelectionEditingWorkBudget
) throws -> Int {
    guard preferredUTF16Offset >= 0, preferredUTF16Offset <= textUTF16Length else {
        throw TextSelectionEditingError.inconsistentPlan
    }
    var recognizer = Unicode._CharacterRecognizer()
    var clusterLength = 0
    var utf16Offset = 0
    var resolvedOffset: Int?
    var isFirstScalar = true

    for scalar in text.unicodeScalars {
        let hasBreak = recognizer.hasBreak(before: scalar)
        if isFirstScalar || hasBreak {
            try validateGraphemeCluster(
                length: clusterLength,
                maximum: maximumGraphemeClusterUTF16Length
            )
            clusterLength = 0
            if resolvedOffset == nil, utf16Offset >= preferredUTF16Offset {
                resolvedOffset = utf16Offset
            }
        }
        let scalarLength = textSelectionEditingUTF16Length(of: scalar)
        try work.consume(scalarLength)
        guard clusterLength <= maximumGraphemeClusterUTF16Length - scalarLength else {
            try Task.checkCancellation()
            throw TextSelectionEditingError.graphemeSegmentationTooComplex(
                maximumClusterUTF16Length: maximumGraphemeClusterUTF16Length
            )
        }
        clusterLength += scalarLength
        utf16Offset += scalarLength
        isFirstScalar = false
    }

    try validateGraphemeCluster(
        length: clusterLength,
        maximum: maximumGraphemeClusterUTF16Length
    )
    if resolvedOffset == nil, utf16Offset >= preferredUTF16Offset {
        resolvedOffset = utf16Offset
    }
    guard utf16Offset == textUTF16Length, let resolvedOffset else {
        try Task.checkCancellation()
        throw TextSelectionEditingError.inconsistentPlan
    }
    try Task.checkCancellation()
    return resolvedOffset
}

private func validateGraphemeCluster(length: Int, maximum: Int) throws {
    guard length <= maximum else {
        try Task.checkCancellation()
        throw TextSelectionEditingError.graphemeSegmentationTooComplex(
            maximumClusterUTF16Length: maximum
        )
    }
}

private struct TextSelectionEditingWorkBudget {
    let maximum: Int
    private(set) var consumed = 0
    private var uncheckedWork = 0

    init(maximum: Int) {
        self.maximum = maximum
    }

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= maximum - consumed else {
            try Task.checkCancellation()
            throw TextSelectionEditingError.workLimitExceeded(maximumWork: maximum)
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

private func textSelectionEditingStringsAreIdentical(
    _ lhs: String,
    _ rhs: String,
    lhsUTF16Length: Int,
    rhsUTF16Length: Int,
    work: inout TextSelectionEditingWorkBudget
) throws -> Bool {
    guard lhsUTF16Length == rhsUTF16Length else {
        try Task.checkCancellation()
        return false
    }
    var lhsScalars = lhs.unicodeScalars.makeIterator()
    var rhsScalars = rhs.unicodeScalars.makeIterator()
    while true {
        let lhsScalar = lhsScalars.next()
        let rhsScalar = rhsScalars.next()
        let comparedLength = max(
            lhsScalar.map(textSelectionEditingUTF16Length(of:)) ?? 0,
            rhsScalar.map(textSelectionEditingUTF16Length(of:)) ?? 0
        )
        try work.consume(comparedLength)
        guard lhsScalar == rhsScalar else {
            try Task.checkCancellation()
            return false
        }
        guard lhsScalar != nil else {
            try Task.checkCancellation()
            return true
        }
    }
}

private func textSelectionEditingUTF16Length(
    of text: String,
    maximum: Int,
    limitError: TextSelectionEditingError,
    work: inout TextSelectionEditingWorkBudget
) throws -> Int {
    var length = 0
    for scalar in text.unicodeScalars {
        let scalarLength = textSelectionEditingUTF16Length(of: scalar)
        try work.consume(scalarLength)
        guard length <= maximum - scalarLength else {
            try Task.checkCancellation()
            throw limitError
        }
        length += scalarLength
    }
    try Task.checkCancellation()
    return length
}

private func textSelectionEditingValidate(
    _ text: String,
    against expected: String,
    expectedUTF16Length: Int,
    maximum: Int,
    work: inout TextSelectionEditingWorkBudget
) throws -> (utf16Length: Int, isIdentical: Bool) {
    var expectedScalars = expected.unicodeScalars.makeIterator()
    var length = 0
    var isIdentical = true
    for scalar in text.unicodeScalars {
        let scalarLength = textSelectionEditingUTF16Length(of: scalar)
        let expectedScalar = expectedScalars.next()
        let comparedLength = max(
            scalarLength,
            expectedScalar.map(textSelectionEditingUTF16Length(of:)) ?? 0
        )
        try work.consume(comparedLength)
        guard length <= maximum - scalarLength else {
            try Task.checkCancellation()
            throw TextSelectionEditingError.inputTooLarge(
                maximumUTF16Length: maximum
            )
        }
        length += scalarLength
        if expectedScalar != scalar {
            isIdentical = false
        }
    }
    if length != expectedUTF16Length {
        isIdentical = false
    }
    try Task.checkCancellation()
    return (length, isIdentical)
}

private func textSelectionEditingStringsAreIdentical(_ lhs: String, _ rhs: String) -> Bool {
    lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
}

private func textSelectionEditingOptionalStringsAreIdentical(
    _ lhs: String?,
    _ rhs: String?
) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        true
    case (.some(let lhs), .some(let rhs)):
        textSelectionEditingStringsAreIdentical(lhs, rhs)
    case (.none, .some), (.some, .none):
        false
    }
}

private func textSelectionEditingUTF16Length(of scalar: Unicode.Scalar) -> Int {
    scalar.value > 0xFFFF ? 2 : 1
}

extension TextSelectionEditingAction {
    fileprivate var requiresEditableDocument: Bool {
        switch self {
        case .cut, .paste:
            true
        case .copy, .selectAll:
            false
        }
    }
}
