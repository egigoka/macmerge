import Foundation

/// UI-independent routing from editor state to the find/replace/marker cores.
///
/// Planning validates one immutable editor snapshot per call, adapts it to the snapshot shape each
/// core expects, and returns core plans or navigation results for the owner to apply. It never
/// presents dialogs, edits text, touches the file system, or retains state between calls.
/// Find/replace/marker dialogs, menus, and editor views remain unclaimed: they adopt this routing
/// by owning snapshots, applying returned plans, and rendering outcomes.
public enum FindReplaceEditorRouting: Sendable {
    public static func findNext(
        in snapshot: FindReplaceEditorDocumentSnapshot,
        matching query: TextSearchQuery,
        fromUTF16Offset offset: Int? = nil,
        wrap: Bool = true,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws -> TextReplacementPlan {
        try Task.checkCancellation()
        try validate(snapshot, limits: limits)
        let origin = try validatedCaretOrOffset(offset, in: snapshot)
        try Task.checkCancellation()
        return try TextReplacementPlanner.next(
            in: snapshot.replacementDocument,
            matching: query,
            fromUTF16Offset: origin,
            wrap: wrap,
            limits: limits.replacement
        )
    }

    public static func findNext(
        in snapshot: FindReplaceEditorDocumentSnapshot,
        matching query: TextSearchQuery,
        after match: TextSearchMatch,
        wrap: Bool = true,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws -> TextReplacementPlan {
        try Task.checkCancellation()
        try validate(snapshot, limits: limits)
        try Task.checkCancellation()
        return try TextReplacementPlanner.next(
            in: snapshot.replacementDocument,
            matching: query,
            after: match,
            wrap: wrap,
            limits: limits.replacement
        )
    }

    public static func findPrevious(
        in snapshot: FindReplaceEditorDocumentSnapshot,
        matching query: TextSearchQuery,
        fromUTF16Offset offset: Int? = nil,
        wrap: Bool = true,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws -> TextReplacementPlan {
        try Task.checkCancellation()
        try validate(snapshot, limits: limits)
        let origin = try validatedCaretOrOffset(offset, in: snapshot)
        try Task.checkCancellation()
        return try TextReplacementPlanner.previous(
            in: snapshot.replacementDocument,
            matching: query,
            fromUTF16Offset: origin,
            wrap: wrap,
            limits: limits.replacement
        )
    }

    public static func findPrevious(
        in snapshot: FindReplaceEditorDocumentSnapshot,
        matching query: TextSearchQuery,
        after match: TextSearchMatch,
        wrap: Bool = true,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws -> TextReplacementPlan {
        try Task.checkCancellation()
        try validate(snapshot, limits: limits)
        try Task.checkCancellation()
        return try TextReplacementPlanner.previous(
            in: snapshot.replacementDocument,
            matching: query,
            after: match,
            wrap: wrap,
            limits: limits.replacement
        )
    }

    public static func replaceCurrent(
        in snapshot: FindReplaceEditorDocumentSnapshot,
        match: TextSearchMatch,
        matching query: TextSearchQuery,
        with replacement: String,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws -> TextReplacementPlan {
        try Task.checkCancellation()
        try validate(snapshot, limits: limits)
        guard snapshot.isEditable else {
            throw FindReplaceEditorRoutingError.documentNotEditable
        }
        try Task.checkCancellation()
        return try TextReplacementPlanner.replaceCurrent(
            in: snapshot.replacementDocument,
            match: match,
            matching: query,
            with: replacement,
            limits: limits.replacement
        )
    }

    public static func replaceAll(
        in snapshot: FindReplaceEditorDocumentSnapshot,
        matching query: TextSearchQuery,
        with replacement: String,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws -> TextReplacementPlan {
        try Task.checkCancellation()
        try validate(snapshot, limits: limits)
        guard snapshot.isEditable else {
            throw FindReplaceEditorRoutingError.documentNotEditable
        }
        try Task.checkCancellation()
        return try TextReplacementPlanner.replaceAll(
            in: snapshot.replacementDocument,
            matching: query,
            with: replacement,
            limits: limits.replacement
        )
    }

    /// Revalidates revision before delegating to the plan's atomic, all-or-nothing apply.
    /// Plans carry no document identity, so owners must only apply a plan to the document
    /// snapshot it was planned from; revision plus exact-text comparison rejects the rest.
    public static func apply(
        _ plan: TextReplacementPlan,
        to snapshot: FindReplaceEditorDocumentSnapshot
    ) throws -> String {
        try Task.checkCancellation()
        guard plan.sourceRevision == snapshot.revision else {
            throw FindReplaceEditorRoutingError.documentRevisionChanged(
                expected: plan.sourceRevision,
                actual: snapshot.revision
            )
        }
        let needsEditable: Bool
        switch plan.action {
        case .replaceCurrent, .replaceAll:
            needsEditable = true
        case .next, .previous:
            needsEditable = false
        }
        guard snapshot.isEditable || !needsEditable else {
            throw FindReplaceEditorRoutingError.documentNotEditable
        }
        try Task.checkCancellation()
        return try plan.apply(to: snapshot.replacementDocument)
    }

    public static func markerMatchSet(
        in snapshot: FindReplaceEditorDocumentSnapshot,
        markers: TextMarkers,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws -> TextMarkerMatchSet {
        try Task.checkCancellation()
        try validate(snapshot, limits: limits)
        try Task.checkCancellation()
        return try markers.matches(
            in: snapshot.markerDocument,
            limits: limits.markers
        )
    }

    public static func markerNavigate(
        in snapshot: FindReplaceEditorDocumentSnapshot,
        markers: TextMarkers,
        markerID: String? = nil,
        direction: TextSearchDirection? = nil,
        fromUTF16Offset offset: Int? = nil,
        wrap: Bool = true,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws -> FindReplaceMarkerNavigation {
        try Task.checkCancellation()
        try validate(snapshot, limits: limits)
        let matchSet = try markers.matches(
            in: snapshot.markerDocument,
            limits: limits.markers
        )
        try Task.checkCancellation()
        let origin = try validatedCaretOrOffset(offset, in: snapshot)
        let result = try matchSet.navigate(
            fromUTF16Offset: origin,
            markerID: markerID,
            direction: direction,
            wrap: wrap,
            in: snapshot.markerDocument
        )
        return FindReplaceMarkerNavigation(matchSet: matchSet, result: result)
    }

    /// Repeats the previous marker jump against a retained match set with strict stale validation.
    /// The match set, not the routing layer, owns revision and exact-text comparison.
    public static func markerRepeat(
        _ previous: TextMarkerNavigationResult,
        in matchSet: TextMarkerMatchSet,
        document snapshot: FindReplaceEditorDocumentSnapshot,
        direction: TextSearchDirection? = nil,
        wrap: Bool = true,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws -> TextMarkerNavigationResult {
        try Task.checkCancellation()
        try validate(snapshot, limits: limits)
        try Task.checkCancellation()
        return try matchSet.repeatSearch(
            after: previous,
            direction: direction,
            wrap: wrap,
            in: snapshot.markerDocument
        )
    }

    /// Toggle intent for the active marker: deactivate when `id` is already active,
    /// otherwise activate it. The owner applies the intent to its `TextMarkers` value.
    public static func markerToggle(
        id: String,
        in markers: TextMarkers
    ) throws -> FindReplaceMarkerActivation {
        try Task.checkCancellation()
        guard markers.marker(id: id) != nil else {
            throw FindReplaceEditorRoutingError.unknownMarker(id)
        }
        try Task.checkCancellation()
        if markers.activeMarkerID == id {
            return .deactivate
        }
        return .activate(id: id)
    }

    public static func validate(
        _ snapshot: FindReplaceEditorDocumentSnapshot,
        limits: FindReplaceEditorRoutingLimits = .default
    ) throws {
        try Task.checkCancellation()
        try limits.validate()
        _ = try validatedCaretOrOffset(nil, in: snapshot)
        if let selection = snapshot.selectionRange {
            let length = snapshot.text.utf16.count
            let (end, overflow) = selection.location.addingReportingOverflow(selection.length)
            guard selection.location >= 0,
                selection.length >= 0,
                !overflow,
                end <= length
            else {
                throw FindReplaceEditorRoutingError.invalidSelectionRange(selection)
            }
            let source = snapshot.text as NSString
            guard isGraphemeBoundary(selection.location, in: source),
                isGraphemeBoundary(end, in: source)
            else {
                throw FindReplaceEditorRoutingError.selectionSplitsGrapheme(selection)
            }
        }
        try Task.checkCancellation()
    }

    private static func validatedCaretOrOffset(
        _ offset: Int?,
        in snapshot: FindReplaceEditorDocumentSnapshot
    ) throws -> Int {
        let origin = offset ?? snapshot.caretUTF16Offset
        let length = snapshot.text.utf16.count
        guard origin >= 0, origin <= length else {
            throw FindReplaceEditorRoutingError.invalidCaretOffset(origin)
        }
        guard isGraphemeBoundary(origin, in: snapshot.text as NSString) else {
            throw FindReplaceEditorRoutingError.caretOffsetSplitsGrapheme(origin)
        }
        return origin
    }

    private static func isGraphemeBoundary(_ offset: Int, in text: NSString) -> Bool {
        guard offset >= 0, offset <= text.length else { return false }
        guard offset < text.length else { return true }
        return text.rangeOfComposedCharacterSequence(at: offset).location == offset
    }
}

/// Immutable editor state used to plan or revalidate one find/replace/marker request.
/// For one `documentID`, the owner must use `revision` as an opaque, never-reused token and
/// advance it whenever `text` changes. Caret and selection moves alone need no new revision.
public struct FindReplaceEditorDocumentSnapshot: Sendable {
    public let documentID: UUID
    public let revision: UInt64
    public let text: String
    /// Zero-based UTF-16 caret offset. Must be a grapheme boundary in `text`.
    public let caretUTF16Offset: Int
    /// Zero-based, half-open UTF-16 selection. Both bounds must be grapheme boundaries.
    public let selectionRange: NSRange?
    public let isEditable: Bool

    public init(
        documentID: UUID,
        revision: UInt64,
        text: String,
        caretUTF16Offset: Int,
        selectionRange: NSRange? = nil,
        isEditable: Bool
    ) {
        self.documentID = documentID
        self.revision = revision
        self.text = text
        self.caretUTF16Offset = caretUTF16Offset
        self.selectionRange = selectionRange
        self.isEditable = isEditable
    }

    fileprivate var replacementDocument: TextReplacementDocumentSnapshot {
        TextReplacementDocumentSnapshot(
            text: text,
            revision: revision,
            isEditable: isEditable
        )
    }

    fileprivate var markerDocument: TextMarkerDocument {
        TextMarkerDocument(
            text: text,
            revision: TextMarkerDocumentRevision(rawValue: revision)
        )
    }
}

extension FindReplaceEditorDocumentSnapshot: Equatable {
    public static func == (
        lhs: FindReplaceEditorDocumentSnapshot,
        rhs: FindReplaceEditorDocumentSnapshot
    ) -> Bool {
        lhs.documentID == rhs.documentID
            && lhs.revision == rhs.revision
            && lhs.caretUTF16Offset == rhs.caretUTF16Offset
            && lhs.selectionRange == rhs.selectionRange
            && lhs.isEditable == rhs.isEditable
            && lhs.text == rhs.text
    }
}

/// Bounds for every core pass behind editor routing. Core limits keep their own defaults.
public struct FindReplaceEditorRoutingLimits: Equatable, Sendable {
    public static let `default` = FindReplaceEditorRoutingLimits()

    public let replacement: TextReplacementPlanningLimits
    public let markers: TextMarkersLimits

    public init(
        replacement: TextReplacementPlanningLimits = .default,
        markers: TextMarkersLimits = .default
    ) {
        self.replacement = replacement
        self.markers = markers
    }

    /// Rejects incoherent bounds before planning. Core constructors already precondition
    /// their own fields; this guards the values routing can observe without trapping.
    public func validate() throws {
        guard replacement.maximumEdits >= 0,
            replacement.maximumWork >= 0,
            markers.maximumMarkers > 0,
            markers.maximumResultRanges > 0,
            markers.maximumWorkUnits >= 0,
            markers.maximumScopeUTF16Length >= 0
        else {
            throw FindReplaceEditorRoutingError.invalidLimits
        }
    }
}

/// Toggle intent for the active named marker. The owner applies it to its `TextMarkers` value.
public enum FindReplaceMarkerActivation: Equatable, Sendable {
    case activate(id: String)
    case deactivate
}

/// One marker jump: the revision-tagged match set plus the navigation result within it.
/// Retain `matchSet` for `markerRepeat`; it revalidates revision and exact text on use.
public struct FindReplaceMarkerNavigation: Equatable, Sendable {
    public let matchSet: TextMarkerMatchSet
    public let result: TextMarkerNavigationResult

    public init(matchSet: TextMarkerMatchSet, result: TextMarkerNavigationResult) {
        self.matchSet = matchSet
        self.result = result
    }
}

public enum FindReplaceEditorRoutingError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case documentRevisionChanged(expected: UInt64, actual: UInt64)
    case documentNotEditable
    case invalidCaretOffset(Int)
    case caretOffsetSplitsGrapheme(Int)
    case invalidSelectionRange(NSRange)
    case selectionSplitsGrapheme(NSRange)
    case unknownMarker(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Find/replace editor routing limits are invalid."
        case .documentRevisionChanged(let expected, let actual):
            "Find/replace was planned for revision \(expected), not revision \(actual)."
        case .documentNotEditable:
            "Find/replace replacement requires an editable document."
        case .invalidCaretOffset(let offset):
            "Find/replace caret offset is outside the document: \(offset)."
        case .caretOffsetSplitsGrapheme(let offset):
            "Find/replace caret offset splits an extended grapheme cluster: \(offset)."
        case .invalidSelectionRange(let range):
            "Find/replace selection range is outside the document: \(NSStringFromRange(range))."
        case .selectionSplitsGrapheme(let range):
            "Find/replace selection range splits an extended grapheme cluster: \(NSStringFromRange(range))."
        case .unknownMarker(let id):
            "Find/replace marker does not exist: \(id)."
        }
    }
}
