import Foundation

/// Pure validation for changing how document-backed panes are decoded or encoded.
public enum EncodingSelectionPolicy: Sendable {
    public enum Pane: Int, CaseIterable, Equatable, Hashable, Sendable {
        case left
        case middle
        case right
    }

    public struct PaneScope: Equatable, Sendable {
        public let panes: Set<Pane>

        public init(_ panes: Set<Pane>) {
            self.panes = panes
        }

        public init(_ panes: [Pane]) {
            self.panes = Set(panes)
        }

        public static func pane(_ pane: Pane) -> Self {
            Self([pane])
        }
    }

    /// `nil` means preserve BOM presence when possible. Explicit BOM policy is only legal for
    /// UTF encodings; code pages always omit a BOM.
    public enum ByteOrderMarkPolicy: Equatable, Sendable {
        case include
        case omit
    }

    public enum Choice: Equatable, Sendable {
        /// Reinterpret persisted bytes and replace current pane contents.
        case load(TextFileEncoding)
        /// Change encoding used by a later save without replacing current pane contents.
        case save(TextFileEncoding, byteOrderMark: ByteOrderMarkPolicy?)

        public var encoding: TextFileEncoding {
            switch self {
            case .load(let encoding), .save(let encoding, _):
                encoding
            }
        }
    }

    public struct PaneState: Equatable, Sendable {
        public let pane: Pane
        public let text: String
        public let persistedText: String
        public let persistedData: Data
        public let encoding: TextFileEncoding
        public let hasByteOrderMark: Bool
        public let allowsReload: Bool
        public let allowsRescan: Bool

        public init(
            pane: Pane,
            text: String,
            persistedText: String,
            persistedData: Data,
            encoding: TextFileEncoding,
            hasByteOrderMark: Bool,
            allowsReload: Bool = true,
            allowsRescan: Bool = true
        ) {
            self.pane = pane
            self.text = text
            self.persistedText = persistedText
            self.persistedData = persistedData
            self.encoding = encoding
            self.hasByteOrderMark = hasByteOrderMark
            self.allowsReload = allowsReload
            self.allowsRescan = allowsRescan
        }

        public init(
            pane: Pane,
            document: TextFileDocument,
            allowsReload: Bool = true,
            allowsRescan: Bool = true
        ) {
            self.init(
                pane: pane,
                text: document.text,
                persistedText: document.persistedText,
                persistedData: document.persistedData,
                encoding: document.encoding,
                hasByteOrderMark: document.hasByteOrderMark,
                allowsReload: allowsReload,
                allowsRescan: allowsRescan
            )
        }

        public var isDirty: Bool {
            !text.unicodeScalars.elementsEqual(persistedText.unicodeScalars)
        }

        /// False when re-encoding persisted text would alter bytes even without an edit.
        public var hasCanonicalPersistedEncoding: Bool {
            guard let data = try? TextFileCodec.encode(DecodedTextFile(
                text: persistedText,
                encoding: encoding,
                hasByteOrderMark: hasByteOrderMark
            )) else {
                return false
            }
            return data == persistedData
        }
    }

    public struct Request: Equatable, Sendable {
        public let choice: Choice
        public let scope: PaneScope
        public let paneStates: [PaneState]

        public init(choice: Choice, scope: PaneScope, paneStates: [PaneState]) {
            self.choice = choice
            self.scope = scope
            self.paneStates = paneStates
        }
    }

    public enum DeniedReason: Equatable, Sendable {
        case emptyPaneScope
        case duplicatePaneState(Pane)
        case paneUnavailable(Pane)
        case byteOrderMarkUnsupported(TextFileEncoding)
        case unsavedChangesPreventReload(Pane)
        case reloadNotPermitted(Pane)
        case rescanNotPermitted(Pane)
        case decodingFailed(Pane, TextFileEncoding)
        case noncanonicalDirtySource(Pane, TextFileEncoding)
        case textNotRepresentable(Pane, TextFileEncoding)
    }

    public struct PanePlan: Equatable, Sendable {
        public enum Action: Equatable, Sendable {
            case reloadAndRescan
            case setSaveEncoding
            case noChange
        }

        public let pane: Pane
        public let action: Action
        public let encoding: TextFileEncoding
        public let hasByteOrderMark: Bool
        public let isDirtyAfterApplying: Bool

        public init(
            pane: Pane,
            action: Action,
            encoding: TextFileEncoding,
            hasByteOrderMark: Bool,
            isDirtyAfterApplying: Bool
        ) {
            self.pane = pane
            self.action = action
            self.encoding = encoding
            self.hasByteOrderMark = hasByteOrderMark
            self.isDirtyAfterApplying = isDirtyAfterApplying
        }

        public var requiresReload: Bool { action == .reloadAndRescan }
        public var requiresRescan: Bool { action == .reloadAndRescan }
    }

    public struct Plan: Equatable, Sendable {
        /// Always ordered left, middle, right, independent of request collection order.
        public let panes: [PanePlan]

        public init(panes: [PanePlan]) {
            self.panes = panes
        }

        public var requiresReload: Bool { panes.contains(where: \.requiresReload) }
        public var requiresRescan: Bool { panes.contains(where: \.requiresRescan) }
    }

    public enum Result: Equatable, Sendable {
        case permitted(Plan)
        case denied(DeniedReason)

        public var plan: Plan? {
            guard case .permitted(let plan) = self else { return nil }
            return plan
        }

        public var deniedReason: DeniedReason? {
            guard case .denied(let reason) = self else { return nil }
            return reason
        }
    }

    /// Validation precedence is structural errors, BOM legality, then pane safety in
    /// left-middle-right order. First failure is returned so callers get stable reasons.
    public static func evaluate(_ request: Request) -> Result {
        guard !request.scope.panes.isEmpty else { return .denied(.emptyPaneScope) }

        var stateCounts: [Pane: Int] = [:]
        for state in request.paneStates {
            stateCounts[state.pane, default: 0] += 1
        }
        if let duplicate = Pane.allCases.first(where: { stateCounts[$0, default: 0] > 1 }) {
            return .denied(.duplicatePaneState(duplicate))
        }
        let statesByPane = Dictionary(uniqueKeysWithValues: request.paneStates.map { ($0.pane, $0) })

        let selectedPanes = Pane.allCases.filter(request.scope.panes.contains)
        for pane in selectedPanes where statesByPane[pane] == nil {
            return .denied(.paneUnavailable(pane))
        }

        if case .save(let encoding, let byteOrderMark) = request.choice,
           byteOrderMark != nil,
           !supportsByteOrderMark(encoding) {
            return .denied(.byteOrderMarkUnsupported(encoding))
        }

        var plans: [PanePlan] = []
        for pane in selectedPanes {
            guard let state = statesByPane[pane] else {
                return .denied(.paneUnavailable(pane))
            }
            switch request.choice {
            case .load(let encoding):
                if state.isDirty { return .denied(.unsavedChangesPreventReload(pane)) }
                guard state.allowsReload else { return .denied(.reloadNotPermitted(pane)) }
                guard state.allowsRescan else { return .denied(.rescanNotPermitted(pane)) }
                guard let decoded = try? TextFileCodec.decode(state.persistedData, assuming: encoding)
                else {
                    return .denied(.decodingFailed(pane, encoding))
                }
                plans.append(PanePlan(
                    pane: pane,
                    action: .reloadAndRescan,
                    encoding: encoding,
                    hasByteOrderMark: decoded.hasByteOrderMark,
                    isDirtyAfterApplying: false
                ))

            case .save(let encoding, let byteOrderMark):
                let hasByteOrderMark = resolvedByteOrderMark(
                    policy: byteOrderMark,
                    encoding: encoding,
                    state: state
                )
                let changesEncoding = encoding != state.encoding
                let changesByteOrderMark = hasByteOrderMark != state.hasByteOrderMark
                let changesSavePolicy = changesEncoding || changesByteOrderMark
                if state.isDirty, !state.hasCanonicalPersistedEncoding {
                    return .denied(.noncanonicalDirtySource(pane, state.encoding))
                }
                guard canEncodeLosslessly(
                    state.text,
                    encoding: encoding,
                    hasByteOrderMark: hasByteOrderMark
                ) else {
                    return .denied(.textNotRepresentable(pane, encoding))
                }
                plans.append(PanePlan(
                    pane: pane,
                    action: changesSavePolicy ? .setSaveEncoding : .noChange,
                    encoding: encoding,
                    hasByteOrderMark: hasByteOrderMark,
                    isDirtyAfterApplying: state.isDirty || changesSavePolicy
                ))
            }
        }

        return .permitted(Plan(panes: plans))
    }

    private static func supportsByteOrderMark(_ encoding: TextFileEncoding) -> Bool {
        switch encoding {
        case .utf8, .utf16LittleEndian, .utf16BigEndian:
            true
        default:
            false
        }
    }

    private static func resolvedByteOrderMark(
        policy: ByteOrderMarkPolicy?,
        encoding: TextFileEncoding,
        state: PaneState
    ) -> Bool {
        guard supportsByteOrderMark(encoding) else { return false }
        switch policy {
        case .include:
            return true
        case .omit:
            return false
        case nil:
            return state.hasByteOrderMark
        }
    }

    private static func canEncodeLosslessly(
        _ text: String,
        encoding: TextFileEncoding,
        hasByteOrderMark: Bool
    ) -> Bool {
        guard let data = try? TextFileCodec.encode(DecodedTextFile(
            text: text,
            encoding: encoding,
            hasByteOrderMark: hasByteOrderMark
        )),
            let decoded = try? TextFileCodec.decode(data, assuming: encoding)
        else {
            return false
        }
        return decoded.text.unicodeScalars.elementsEqual(text.unicodeScalars)
    }
}
