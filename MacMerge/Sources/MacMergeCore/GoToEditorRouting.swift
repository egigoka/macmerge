import Foundation

/// UI-independent routing from a validated Go To resolution to one editor selection request.
///
/// Planning only: validates caller-supplied identity/revision (stale-generation check),
/// delegates grapheme safety, difference/bookmark validation, work limits, and cancellation
/// to ``TextGoTo``, then maps the resolution to selection coordinates a future editor
/// executor can apply. This file never touches an editor, pane, menu, or dialog; scrolling,
/// focus, and pane activation remain UI policy.
public enum GoToEditorRouting {
    public struct Limits: Equatable, Sendable {
        public static let `default` = Limits()

        public let goTo: TextGoToLimits

        public init(goTo: TextGoToLimits = .default) {
            self.goTo = goTo
        }
    }

    /// Planned editor selection. The executor reveals `selectionRange` without claiming
    /// focus, scrolling, or pane-activation behavior.
    public struct EditorRequest: Equatable, Sendable {
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

        public init(resolution: TextGoToResolution) {
            documentIdentity = resolution.documentIdentity
            documentRevision = resolution.documentRevision
            target = resolution.target
            selectionRange = resolution.selectionRange
            selectionStart = resolution.selectionStart
            selectionEnd = resolution.selectionEnd
            workUnitsConsumed = resolution.workUnitsConsumed
        }
    }

    public static func route(
        _ request: TextGoToRequest,
        in document: TextGoToDocumentSnapshot,
        limits: Limits = .default
    ) throws -> EditorRequest {
        try Task.checkCancellation()
        let resolution: TextGoToResolution
        do {
            resolution = try TextGoTo.resolve(request, in: document, limits: limits.goTo)
        } catch let error as GoToEditorRoutingError {
            throw error
        } catch let error as TextGoToError {
            throw GoToEditorRoutingError.goTo(error)
        }
        try Task.checkCancellation()
        return EditorRequest(resolution: resolution)
    }

    public static func route(
        target: TextGoToTarget,
        in document: TextGoToDocumentSnapshot,
        limits: Limits = .default
    ) throws -> EditorRequest {
        try route(TextGoToRequest(document: document, target: target), in: document, limits: limits)
    }
}

public enum GoToEditorRoutingError: Error, Equatable, LocalizedError, Sendable {
    case goTo(TextGoToError)

    public var errorDescription: String? {
        switch self {
        case .goTo(let error):
            error.localizedDescription
        }
    }
}
