import Foundation

/// Bounded, UI-independent state matrix for Keyboard Shortcut Audit rows.
///
/// Covers New/Open/Save/Quit/Close, Next/Previous Difference `F8`/`F7` plus
/// platform-safe `Option`-arrow equivalents, First/Current/Last `Option`-`Home`/
/// `Return`/`End` equivalents, and directional copy without stealing word or
/// paragraph navigation. Every shortcut is bound to lifecycle, focus, dirty,
/// selection, and read-only contexts with exact expected outcome and enablement.
/// Collision and inventory expectations reuse `KeyboardShortcutPolicy` state.
/// This type performs no event routing, responder-chain dispatch, or I/O.
public enum KeyboardShortcutStateMatrix: Sendable {
    public typealias Policy = KeyboardShortcutPolicy
    public typealias CancellationCheck = @Sendable () -> Bool

    public enum ShortcutID: String, CaseIterable, Comparable, Hashable, Sendable {
        case newCommandN = "new-command-n"
        case openCommandO = "open-command-o"
        case saveCommandS = "save-command-s"
        case quitCommandQ = "quit-command-q"
        case closeCommandW = "close-command-w"
        case undoCommandZ = "undo-command-z"
        case redoCommandShiftZ = "redo-command-shift-z"
        case selectLineDifferenceF4 = "select-line-difference-f4"
        case selectPreviousLineDifferenceShiftF4 = "select-previous-line-difference-shift-f4"
        case nextDifferenceF8 = "next-difference-f8"
        case nextDifferenceOptionDown = "next-difference-option-down"
        case previousDifferenceF7 = "previous-difference-f7"
        case previousDifferenceOptionUp = "previous-difference-option-up"
        case nextConflictShiftF8 = "next-conflict-shift-f8"
        case nextConflictOptionShiftDown = "next-conflict-option-shift-down"
        case previousConflictShiftF7 = "previous-conflict-shift-f7"
        case previousConflictOptionShiftUp = "previous-conflict-option-shift-up"
        case firstDifferenceOptionHome = "first-difference-option-home"
        case currentDifferenceOptionReturn = "current-difference-option-return"
        case lastDifferenceOptionEnd = "last-difference-option-end"
        case copyRightOptionRight = "copy-right-option-right"
        case copyLeftOptionLeft = "copy-left-option-left"
        case copyRightAdvanceCommandOptionRight = "copy-right-advance-command-option-right"
        case copyLeftAdvanceCommandOptionLeft = "copy-left-advance-command-option-left"
        case previousComparedFileCommandF7 = "previous-compared-file-command-f7"
        case nextComparedFileCommandF8 = "next-compared-file-command-f8"
        case reloadCommandF5 = "reload-command-f5"
        case refreshF5 = "refresh-f5"
        case changePaneF6 = "change-pane-f6"
        case changePaneBackShiftF6 = "change-pane-back-shift-f6"
        case mergeModeF9 = "merge-mode-f9"
        case optionsCommandComma = "options-command-comma"

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public enum MatrixContextID: String, CaseIterable, Comparable, Hashable, Sendable {
        case empty
        case disabled
        case loading
        case selected
        case dirty
        case textFocused
        case readOnly

        public static func < (left: Self, right: Self) -> Bool {
            left.rank < right.rank
        }

        fileprivate var rank: Int {
            switch self {
            case .empty: 0
            case .disabled: 1
            case .loading: 2
            case .selected: 3
            case .dirty: 4
            case .textFocused: 5
            case .readOnly: 6
            }
        }
    }

    public enum Owner: String, CaseIterable, Hashable, Sendable {
        case application
        case nativeTextEditor
        case system
        case none
    }

    public enum Invocation: String, CaseIterable, Hashable, Sendable {
        case invoked
        case blocked
        case unhandled
    }

    public struct MatrixKey: Comparable, Hashable, Sendable {
        public let shortcutID: ShortcutID
        public let contextID: MatrixContextID

        public init(shortcutID: ShortcutID, contextID: MatrixContextID) {
            self.shortcutID = shortcutID
            self.contextID = contextID
        }

        public static func < (left: Self, right: Self) -> Bool {
            if left.shortcutID != right.shortcutID { return left.shortcutID < right.shortcutID }
            return left.contextID < right.contextID
        }
    }

    public struct Requirement: Equatable, Hashable, Sendable {
        public let enabledLifecycleStates: Set<Policy.LifecycleState>
        public let requiresDirty: Bool
        public let requiresSelection: Bool
        public let allowsReadOnly: Bool

        public init(
            enabledLifecycleStates: Set<Policy.LifecycleState>,
            requiresDirty: Bool = false,
            requiresSelection: Bool = false,
            allowsReadOnly: Bool = true
        ) {
            self.enabledLifecycleStates = enabledLifecycleStates
            self.requiresDirty = requiresDirty
            self.requiresSelection = requiresSelection
            self.allowsReadOnly = allowsReadOnly
        }

        fileprivate init(_ shortcut: Policy.CommandShortcut) {
            enabledLifecycleStates = shortcut.enabledLifecycleStates
            requiresDirty = shortcut.requiresDirty
            requiresSelection = shortcut.requiresSelection
            allowsReadOnly = shortcut.allowsReadOnly
        }
    }

    public struct ShortcutDescriptor: Hashable, Sendable {
        public let id: ShortcutID
        public let chord: Policy.Chord
        public let applicationCommand: Policy.Command?
        public let winMergeAccelerator: String?
        public let requirement: Requirement?
        public let preservesNativeEditing: Bool
        public let isSystemCommand: Bool

        fileprivate init(
            id: ShortcutID,
            chord: Policy.Chord,
            applicationCommand: Policy.Command?,
            winMergeAccelerator: String? = nil,
            requirement: Requirement? = nil,
            preservesNativeEditing: Bool = false,
            isSystemCommand: Bool = false
        ) {
            self.id = id
            self.chord = chord
            self.applicationCommand = applicationCommand
            self.winMergeAccelerator = winMergeAccelerator
            self.requirement = requirement
            self.preservesNativeEditing = preservesNativeEditing
            self.isSystemCommand = isSystemCommand
        }
    }

    public struct MatrixContext: Hashable, Sendable {
        public let id: MatrixContextID
        public let policyContext: Policy.Context
        public let systemCommandsEnabled: Bool

        public init(
            id: MatrixContextID,
            policyContext: Policy.Context,
            systemCommandsEnabled: Bool
        ) {
            self.id = id
            self.policyContext = policyContext
            self.systemCommandsEnabled = systemCommandsEnabled
        }
    }

    public struct Expectation: Hashable, Sendable {
        public let key: MatrixKey
        public let chordCanonical: String
        public let owner: Owner
        public let applicationCommand: Policy.Command?
        public let nativeCommand: Policy.NativeTextEditingCommand?
        public let isEnabled: Bool
        public let invocation: Invocation
        public let preservesNativeEditing: Bool

        fileprivate init(
            key: MatrixKey,
            chordCanonical: String,
            owner: Owner,
            applicationCommand: Policy.Command?,
            nativeCommand: Policy.NativeTextEditingCommand?,
            isEnabled: Bool,
            invocation: Invocation,
            preservesNativeEditing: Bool
        ) {
            self.key = key
            self.chordCanonical = chordCanonical
            self.owner = owner
            self.applicationCommand = applicationCommand
            self.nativeCommand = nativeCommand
            self.isEnabled = isEnabled
            self.invocation = invocation
            self.preservesNativeEditing = preservesNativeEditing
        }
    }

    public enum FindingSeverity: String, CaseIterable, Hashable, Sendable {
        case advisory
        case warning
        case error
    }

    public enum FindingCode: String, CaseIterable, Hashable, Sendable {
        case duplicateCanonicalShortcut
        case missingPolicyBinding
        case unexpectedPolicyBinding
        case chordMismatch
        case policyRequirementMismatch
        case missingCollision
        case unexpectedCollision
        case unexpectedApplicationCollision
        case nativePreservationMismatch
        case resolutionMismatch
    }

    public struct Finding: Identifiable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }

            public static func < (left: Self, right: Self) -> Bool {
                left.rawValue < right.rawValue
            }
        }

        public let id: ID
        public let severity: FindingSeverity
        public let code: FindingCode
        public let shortcutID: ShortcutID?
        public let contextID: MatrixContextID?
        public let occurrenceCount: Int?
        public let message: String

        fileprivate init(
            severity: FindingSeverity,
            code: FindingCode,
            shortcutID: ShortcutID? = nil,
            contextID: MatrixContextID? = nil,
            occurrenceCount: Int? = nil
        ) {
            self.severity = severity
            self.code = code
            self.shortcutID = shortcutID
            self.contextID = contextID
            self.occurrenceCount = occurrenceCount
            message = KeyboardShortcutStateMatrix.message(for: code)
            var rawValue = code.rawValue
            if let shortcutID { rawValue += "|\(shortcutID.rawValue)" }
            if let contextID { rawValue += "|\(contextID.rawValue)" }
            id = ID(rawValue: rawValue)
        }

        public var description: String {
            "KeyboardShortcutStateFinding(code: \(code.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["code": code, "details": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public enum CellStatus: String, CaseIterable, Hashable, Sendable {
        case complete
        case mismatched
    }

    public struct Cell: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let expectation: Expectation
        public let status: CellStatus

        fileprivate init(expectation: Expectation, status: CellStatus) {
            self.expectation = expectation
            self.status = status
        }

        public var description: String {
            "KeyboardShortcutStateCell(status: \(status.rawValue), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["status": status, "contents": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public struct Matrix: Hashable, Sendable {
        public let cells: [Cell]

        fileprivate init(cells: [Cell]) {
            self.cells = cells
        }

        public var requiredCount: Int { cells.count }
        public var completeCount: Int { cells.count(where: { $0.status == .complete }) }
        public var mismatchedCount: Int { cells.count(where: { $0.status == .mismatched }) }
        public var isComplete: Bool { mismatchedCount == 0 }
    }

    public struct Report: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public static let scopeStatement =
            "Deterministic validation of every audited shortcut across empty, disabled, loading, selected, dirty, text-focused, and read-only states; not independent runtime UI verification."

        public let formatVersion: Int
        public let matrix: Matrix
        public let findings: [Finding]

        fileprivate init(formatVersion: Int, matrix: Matrix, findings: [Finding]) {
            self.formatVersion = formatVersion
            self.matrix = matrix
            self.findings = findings
        }

        public var containsErrors: Bool { findings.contains { $0.severity == .error } }
        public var isCompleteAndValid: Bool { matrix.isComplete && findings.isEmpty }

        public var description: String {
            "KeyboardShortcutStateReport(required: \(matrix.requiredCount), findings: \(findings.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "requiredCount": matrix.requiredCount,
                    "findingCount": findings.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Fingerprint: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public struct Receipt: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let formatVersion: Int
        public let descriptorFingerprint: Fingerprint
        public let matrixFingerprint: Fingerprint
        public let findingFingerprint: Fingerprint
        public let requiredCellCount: Int
        public let completeCellCount: Int
        public let findingCount: Int

        fileprivate init(
            formatVersion: Int,
            descriptorFingerprint: Fingerprint,
            matrixFingerprint: Fingerprint,
            findingFingerprint: Fingerprint,
            requiredCellCount: Int,
            completeCellCount: Int,
            findingCount: Int
        ) {
            self.formatVersion = formatVersion
            self.descriptorFingerprint = descriptorFingerprint
            self.matrixFingerprint = matrixFingerprint
            self.findingFingerprint = findingFingerprint
            self.requiredCellCount = requiredCellCount
            self.completeCellCount = completeCellCount
            self.findingCount = findingCount
        }

        public func validateCurrent(
            policy: Policy? = nil,
            limits: Limits = .default,
            cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
        ) throws {
            try KeyboardShortcutStateMatrix.validate(
                receipt: self,
                policy: policy,
                limits: limits,
                cancellationCheck: cancellationCheck
            )
        }

        public var description: String {
            "KeyboardShortcutStateReceipt(required: \(requiredCellCount), complete: \(completeCellCount), findings: \(findingCount), fingerprints: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "requiredCellCount": requiredCellCount,
                    "completeCellCount": completeCellCount,
                    "findingCount": findingCount,
                    "fingerprints": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Result: Hashable, Sendable {
        public let report: Report
        public let receipt: Receipt

        fileprivate init(report: Report, receipt: Receipt) {
            self.report = report
            self.receipt = receipt
        }
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumShortcuts = 256
        public static let hardMaximumContexts = 32
        public static let hardMaximumCells = 8_192
        public static let hardMaximumFindings = 4_096
        public static let hardMaximumWorkUnits = 1_000_000
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumShortcuts: Int
        public let maximumContexts: Int
        public let maximumCells: Int
        public let maximumFindings: Int
        public let maximumWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumShortcuts: Int = 64,
            maximumContexts: Int = 16,
            maximumCells: Int = 2_048,
            maximumFindings: Int = 1_024,
            maximumWorkUnits: Int = 100_000,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumShortcuts = maximumShortcuts
            self.maximumContexts = maximumContexts
            self.maximumCells = maximumCells
            self.maximumFindings = maximumFindings
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case shortcuts
        case contexts
        case cells
        case findings
        case workUnits
        case cancellationCheckInterval
    }

    public enum StateError: Error, Equatable, LocalizedError, Sendable {
        case cancelled
        case invalidLimit(Limit, value: Int)
        case shortcutLimitExceeded(maximum: Int)
        case contextLimitExceeded(maximum: Int)
        case cellLimitExceeded(maximum: Int)
        case findingLimitExceeded(maximum: Int)
        case workLimitExceeded(maximum: Int)
        case canonicalPolicyUnavailable
        case receiptMismatch

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                "Keyboard shortcut state matrix was cancelled."
            case .invalidLimit(let limit, let value):
                "Keyboard shortcut state limit \(limit.rawValue) is invalid: \(value)."
            case .shortcutLimitExceeded(let maximum):
                "Keyboard shortcut state exceeds the \(maximum)-shortcut limit."
            case .contextLimitExceeded(let maximum):
                "Keyboard shortcut state exceeds the \(maximum)-context limit."
            case .cellLimitExceeded(let maximum):
                "Keyboard shortcut state exceeds the \(maximum)-cell limit."
            case .findingLimitExceeded(let maximum):
                "Keyboard shortcut state exceeds the \(maximum)-finding limit."
            case .workLimitExceeded(let maximum):
                "Keyboard shortcut state exceeds the \(maximum)-unit work limit."
            case .canonicalPolicyUnavailable:
                "Canonical keyboard shortcut policy could not be constructed."
            case .receiptMismatch:
                "Keyboard shortcut state receipt no longer matches current contents."
            }
        }
    }

    public static let reportFormatVersion = 1

    public static let canonicalDescriptors: [ShortcutDescriptor] = makeCanonicalDescriptors()

    public static let canonicalContexts: [MatrixContext] = makeCanonicalContexts()

    public static func canonicalExpectations(
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> [Expectation] {
        var budget = WorkBudget(limits: .default, cancellationCheck: cancellationCheck)
        let expectations = try makeCanonicalExpectations(budget: &budget)
        try budget.finish()
        return expectations
    }

    public static func audit(
        policy: Policy? = nil,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Result {
        var budget = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try validate(limits, budget: &budget)
        let resolvedPolicy: Policy
        if let policy {
            resolvedPolicy = policy
        } else {
            do {
                resolvedPolicy = try Policy.makeUnfinishedAudit(cancellationCheck: {
                    () throws(KeyboardShortcutPolicyError) in
                    if cancellationCheck() { throw KeyboardShortcutPolicyError.cancelled }
                })
            } catch KeyboardShortcutPolicyError.cancelled {
                throw StateError.cancelled
            } catch {
                throw StateError.canonicalPolicyUnavailable
            }
        }
        var context = AuditContext(
            policy: resolvedPolicy,
            limits: limits,
            budget: budget,
            cancellationCheck: cancellationCheck
        )
        let report = try context.run()
        let receipt = try context.receipt(for: report)
        try context.budget.finish()
        return Result(report: report, receipt: receipt)
    }

    public static func validate(
        receipt: Receipt,
        policy: Policy? = nil,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws {
        let current = try audit(
            policy: policy,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        guard current.receipt == receipt else {
            throw StateError.receiptMismatch
        }
    }

    static func message(for code: FindingCode) -> String {
        switch code {
        case .duplicateCanonicalShortcut:
            "Canonical inventory repeats a shortcut identity."
        case .missingPolicyBinding:
            "Shortcut policy has no required application binding."
        case .unexpectedPolicyBinding:
            "Shortcut policy has a binding outside the audited inventory."
        case .chordMismatch:
            "Shortcut chord differs from canonical policy chord."
        case .policyRequirementMismatch:
            "Shortcut policy conditions differ from canonical requirement."
        case .missingCollision:
            "Expected editor-focus reservation collision is missing."
        case .unexpectedCollision:
            "Shortcut policy has an unexpected editor-focus collision."
        case .unexpectedApplicationCollision:
            "Shortcut policy has an unexpected application-command collision."
        case .nativePreservationMismatch:
            "Directional or navigation shortcut does not preserve native editing ownership."
        case .resolutionMismatch:
            "Policy owner, command, or enabled outcome differs from matrix."
        }
    }
}

private struct WorkBudget {
    let maximumWork: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: KeyboardShortcutStateMatrix.CancellationCheck
    private(set) var completedWork = 0
    private var workAtLastCancellationCheck = 0

    init(
        limits: KeyboardShortcutStateMatrix.Limits,
        cancellationCheck: @escaping KeyboardShortcutStateMatrix.CancellationCheck
    ) {
        maximumWork = limits.maximumWorkUnits
        cancellationCheckInterval = limits.cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
    }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0, amount <= maximumWork else {
            try checkCancellation()
            throw KeyboardShortcutStateMatrix.StateError.workLimitExceeded(maximum: maximumWork)
        }
        guard completedWork <= maximumWork - amount else {
            try checkCancellation()
            throw KeyboardShortcutStateMatrix.StateError.workLimitExceeded(maximum: maximumWork)
        }
        completedWork += amount
        if completedWork - workAtLastCancellationCheck >= cancellationCheckInterval {
            try checkCancellation()
            workAtLastCancellationCheck = completedWork
        }
    }

    func checkCancellation() throws {
        if cancellationCheck() {
            throw KeyboardShortcutStateMatrix.StateError.cancelled
        }
    }

    mutating func finish() throws {
        try checkCancellation()
        workAtLastCancellationCheck = completedWork
    }
}

private struct FingerprintHasher {
    private var hash: UInt64 = 14_695_981_039_346_656_037

    mutating func append(_ string: String) {
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        hash ^= 0xFF
        hash = hash &* 1_099_511_628_211
    }

    func finalize() -> KeyboardShortcutStateMatrix.Fingerprint {
        KeyboardShortcutStateMatrix.Fingerprint(rawValue: hash)
    }
}

extension KeyboardShortcutStateMatrix {
    fileprivate static func validate(_ limits: Limits, budget: inout WorkBudget) throws {
        guard (1...Limits.hardMaximumShortcuts).contains(limits.maximumShortcuts) else {
            throw StateError.invalidLimit(.shortcuts, value: limits.maximumShortcuts)
        }
        guard (1...Limits.hardMaximumContexts).contains(limits.maximumContexts) else {
            throw StateError.invalidLimit(.contexts, value: limits.maximumContexts)
        }
        guard (1...Limits.hardMaximumCells).contains(limits.maximumCells) else {
            throw StateError.invalidLimit(.cells, value: limits.maximumCells)
        }
        guard (1...Limits.hardMaximumFindings).contains(limits.maximumFindings) else {
            throw StateError.invalidLimit(.findings, value: limits.maximumFindings)
        }
        guard (1...Limits.hardMaximumWorkUnits).contains(limits.maximumWorkUnits) else {
            throw StateError.invalidLimit(.workUnits, value: limits.maximumWorkUnits)
        }
        guard (1...Limits.hardMaximumCancellationCheckInterval).contains(limits.cancellationCheckInterval) else {
            throw StateError.invalidLimit(
                .cancellationCheckInterval,
                value: limits.cancellationCheckInterval
            )
        }
        guard canonicalDescriptors.count <= limits.maximumShortcuts else {
            throw StateError.shortcutLimitExceeded(maximum: limits.maximumShortcuts)
        }
        guard canonicalContexts.count <= limits.maximumContexts else {
            throw StateError.contextLimitExceeded(maximum: limits.maximumContexts)
        }
        let cellCount = canonicalDescriptors.count * canonicalContexts.count
        guard cellCount <= limits.maximumCells else {
            throw StateError.cellLimitExceeded(maximum: limits.maximumCells)
        }
        try budget.checkCancellation()
    }

    fileprivate static func makeChord(
        _ key: Policy.Key,
        _ modifiers: Set<Policy.Modifier>
    ) -> Policy.Chord {
        // swiftlint:disable:next force_try
        try! Policy.Chord(key, modifiers: modifiers)
    }

    fileprivate static func makeCanonicalDescriptors() -> [ShortcutDescriptor] {
        let workspace: Set<Policy.LifecycleState> = [.empty, .equal, .different, .failed]
        let differences: Set<Policy.LifecycleState> = [.different]
        let current: Set<Policy.LifecycleState> = [.equal, .different]
        let all = Set(Policy.LifecycleState.allCases)
        let failedUnion = Set([Policy.LifecycleState.equal, .different, .failed])
        return [
            ShortcutDescriptor(
                id: .newCommandN,
                chord: makeChord(.character("n"), [.command]),
                applicationCommand: .newComparison,
                requirement: Requirement(enabledLifecycleStates: workspace)
            ),
            ShortcutDescriptor(
                id: .openCommandO,
                chord: makeChord(.character("o"), [.command]),
                applicationCommand: .openComparison,
                requirement: Requirement(enabledLifecycleStates: workspace)
            ),
            ShortcutDescriptor(
                id: .saveCommandS,
                chord: makeChord(.character("s"), [.command]),
                applicationCommand: .save,
                requirement: Requirement(
                    enabledLifecycleStates: workspace,
                    requiresDirty: true,
                    allowsReadOnly: false
                )
            ),
            ShortcutDescriptor(
                id: .quitCommandQ,
                chord: makeChord(.character("q"), [.command]),
                applicationCommand: nil,
                isSystemCommand: true
            ),
            ShortcutDescriptor(
                id: .closeCommandW,
                chord: makeChord(.character("w"), [.command]),
                applicationCommand: nil,
                isSystemCommand: true
            ),
            ShortcutDescriptor(
                id: .undoCommandZ,
                chord: makeChord(.character("z"), [.command]),
                applicationCommand: .undo,
                requirement: Requirement(
                    enabledLifecycleStates: workspace,
                    allowsReadOnly: false
                ),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .redoCommandShiftZ,
                chord: makeChord(.character("z"), [.command, .shift]),
                applicationCommand: .redo,
                requirement: Requirement(
                    enabledLifecycleStates: workspace,
                    allowsReadOnly: false
                ),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .selectLineDifferenceF4,
                chord: makeChord(.function(4), []),
                applicationCommand: .selectLineDifference,
                requirement: Requirement(enabledLifecycleStates: differences)
            ),
            ShortcutDescriptor(
                id: .selectPreviousLineDifferenceShiftF4,
                chord: makeChord(.function(4), [.shift]),
                applicationCommand: .selectPreviousLineDifference,
                requirement: Requirement(enabledLifecycleStates: differences)
            ),
            ShortcutDescriptor(
                id: .nextDifferenceF8,
                chord: makeChord(.function(8), []),
                applicationCommand: .nextDifference,
                requirement: Requirement(enabledLifecycleStates: differences)
            ),
            ShortcutDescriptor(
                id: .nextDifferenceOptionDown,
                chord: makeChord(.special(.downArrow), [.option]),
                applicationCommand: .nextDifference,
                winMergeAccelerator: "Alt+Down",
                requirement: Requirement(enabledLifecycleStates: differences),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .previousDifferenceF7,
                chord: makeChord(.function(7), []),
                applicationCommand: .previousDifference,
                requirement: Requirement(enabledLifecycleStates: differences)
            ),
            ShortcutDescriptor(
                id: .previousDifferenceOptionUp,
                chord: makeChord(.special(.upArrow), [.option]),
                applicationCommand: .previousDifference,
                winMergeAccelerator: "Alt+Up",
                requirement: Requirement(enabledLifecycleStates: differences),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .nextConflictShiftF8,
                chord: makeChord(.function(8), [.shift]),
                applicationCommand: .nextConflict,
                requirement: Requirement(enabledLifecycleStates: differences)
            ),
            ShortcutDescriptor(
                id: .nextConflictOptionShiftDown,
                chord: makeChord(.special(.downArrow), [.option, .shift]),
                applicationCommand: .nextConflict,
                winMergeAccelerator: "Alt+Shift+Down",
                requirement: Requirement(enabledLifecycleStates: differences),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .previousConflictShiftF7,
                chord: makeChord(.function(7), [.shift]),
                applicationCommand: .previousConflict,
                requirement: Requirement(enabledLifecycleStates: differences)
            ),
            ShortcutDescriptor(
                id: .previousConflictOptionShiftUp,
                chord: makeChord(.special(.upArrow), [.option, .shift]),
                applicationCommand: .previousConflict,
                winMergeAccelerator: "Alt+Shift+Up",
                requirement: Requirement(enabledLifecycleStates: differences),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .firstDifferenceOptionHome,
                chord: makeChord(.special(.home), [.option]),
                applicationCommand: .firstDifference,
                winMergeAccelerator: "Alt+Home",
                requirement: Requirement(enabledLifecycleStates: differences),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .currentDifferenceOptionReturn,
                chord: makeChord(.special(.return), [.option]),
                applicationCommand: .currentDifference,
                winMergeAccelerator: "Alt+Enter",
                requirement: Requirement(enabledLifecycleStates: differences),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .lastDifferenceOptionEnd,
                chord: makeChord(.special(.end), [.option]),
                applicationCommand: .lastDifference,
                winMergeAccelerator: "Alt+End",
                requirement: Requirement(enabledLifecycleStates: differences),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .copyRightOptionRight,
                chord: makeChord(.special(.rightArrow), [.option]),
                applicationCommand: .copyToRight,
                winMergeAccelerator: "Alt+Right",
                requirement: Requirement(
                    enabledLifecycleStates: differences,
                    requiresSelection: true,
                    allowsReadOnly: false
                ),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .copyLeftOptionLeft,
                chord: makeChord(.special(.leftArrow), [.option]),
                applicationCommand: .copyToLeft,
                winMergeAccelerator: "Alt+Left",
                requirement: Requirement(
                    enabledLifecycleStates: differences,
                    requiresSelection: true,
                    allowsReadOnly: false
                ),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .copyRightAdvanceCommandOptionRight,
                chord: makeChord(.special(.rightArrow), [.command, .option]),
                applicationCommand: .copyToRightAndAdvance,
                requirement: Requirement(
                    enabledLifecycleStates: differences,
                    requiresSelection: true,
                    allowsReadOnly: false
                )
            ),
            ShortcutDescriptor(
                id: .copyLeftAdvanceCommandOptionLeft,
                chord: makeChord(.special(.leftArrow), [.command, .option]),
                applicationCommand: .copyToLeftAndAdvance,
                requirement: Requirement(
                    enabledLifecycleStates: differences,
                    requiresSelection: true,
                    allowsReadOnly: false
                )
            ),
            ShortcutDescriptor(
                id: .previousComparedFileCommandF7,
                chord: makeChord(.function(7), [.command]),
                applicationCommand: .previousComparedFile,
                requirement: Requirement(enabledLifecycleStates: current)
            ),
            ShortcutDescriptor(
                id: .nextComparedFileCommandF8,
                chord: makeChord(.function(8), [.command]),
                applicationCommand: .nextComparedFile,
                requirement: Requirement(enabledLifecycleStates: current)
            ),
            ShortcutDescriptor(
                id: .reloadCommandF5,
                chord: makeChord(.function(5), [.command]),
                applicationCommand: .reloadFromDisk,
                requirement: Requirement(enabledLifecycleStates: current)
            ),
            ShortcutDescriptor(
                id: .refreshF5,
                chord: makeChord(.function(5), []),
                applicationCommand: .refresh,
                requirement: Requirement(enabledLifecycleStates: failedUnion),
                preservesNativeEditing: true
            ),
            ShortcutDescriptor(
                id: .changePaneF6,
                chord: makeChord(.function(6), []),
                applicationCommand: .changePane,
                requirement: Requirement(enabledLifecycleStates: current)
            ),
            ShortcutDescriptor(
                id: .changePaneBackShiftF6,
                chord: makeChord(.function(6), [.shift]),
                applicationCommand: .changePaneBack,
                requirement: Requirement(enabledLifecycleStates: current)
            ),
            ShortcutDescriptor(
                id: .mergeModeF9,
                chord: makeChord(.function(9), []),
                applicationCommand: .mergeMode,
                requirement: Requirement(enabledLifecycleStates: current)
            ),
            ShortcutDescriptor(
                id: .optionsCommandComma,
                chord: makeChord(.character(","), [.command]),
                applicationCommand: .options,
                requirement: Requirement(enabledLifecycleStates: all)
            )
        ]
    }

    fileprivate static func enabledCommands(for context: MatrixContextID) -> Set<Policy.Command> {
        let workspace: Set<Policy.Command> = [.newComparison, .openComparison]
        let statics: Set<Policy.Command> = [.mergeMode, .options]
        let loaded: Set<Policy.Command> = [
            .reloadFromDisk, .refresh, .changePane, .changePaneBack,
            .previousComparedFile, .nextComparedFile
        ]
        let difference: Set<Policy.Command> = [
            .selectLineDifference, .selectPreviousLineDifference,
            .nextDifference, .previousDifference,
            .firstDifference, .currentDifference, .lastDifference
        ]
        let conflict: Set<Policy.Command> = [.nextConflict, .previousConflict]
        let copy: Set<Policy.Command> = [
            .copyToRight, .copyToLeft, .copyToRightAndAdvance, .copyToLeftAndAdvance
        ]
        switch context {
        case .empty:
            return workspace.union(statics)
        case .disabled:
            return statics
        case .loading:
            return workspace.union(statics).union(loaded).union(difference).union(conflict)
                .union(copy).union([.save, .undo, .redo])
        case .selected:
            return workspace.union(statics).union(loaded).union(difference).union(conflict)
                .union(copy)
        case .dirty:
            return workspace.union(statics).union(loaded).union(difference).union(conflict)
                .union(copy).union([.save, .undo, .redo])
        case .textFocused:
            return workspace.union(statics).union(loaded).union(difference).union(conflict)
                .union(copy).union([.save, .undo, .redo])
        case .readOnly:
            return workspace.union(statics).union(loaded).union(difference).union(conflict)
                .union(copy).union([.save, .undo, .redo])
        }
    }

    fileprivate static func makeCanonicalContexts() -> [MatrixContext] {
        let emptyCommands = enabledCommands(for: .empty)
        let disabledCommands = enabledCommands(for: .disabled)
        let loadingCommands = enabledCommands(for: .loading)
        let selectedCommands = enabledCommands(for: .selected)
        let dirtyCommands = enabledCommands(for: .dirty)
        let textFocusedCommands = enabledCommands(for: .textFocused)
        let readOnlyCommands = enabledCommands(for: .readOnly)
        return [
            MatrixContext(
                id: .empty,
                policyContext: Policy.Context(
                    lifecycle: .empty,
                    isDirty: false,
                    hasSelection: false,
                    isReadOnly: false,
                    editorFocus: .none,
                    enabledCommands: emptyCommands
                ),
                systemCommandsEnabled: true
            ),
            MatrixContext(
                id: .disabled,
                policyContext: Policy.Context(
                    lifecycle: .different,
                    isDirty: true,
                    hasSelection: true,
                    isReadOnly: false,
                    editorFocus: .none,
                    enabledCommands: disabledCommands
                ),
                systemCommandsEnabled: false
            ),
            MatrixContext(
                id: .loading,
                policyContext: Policy.Context(
                    lifecycle: .loading,
                    isDirty: false,
                    hasSelection: false,
                    isReadOnly: false,
                    editorFocus: .none,
                    enabledCommands: loadingCommands
                ),
                systemCommandsEnabled: true
            ),
            MatrixContext(
                id: .selected,
                policyContext: Policy.Context(
                    lifecycle: .different,
                    isDirty: false,
                    hasSelection: true,
                    isReadOnly: false,
                    editorFocus: .none,
                    enabledCommands: selectedCommands
                ),
                systemCommandsEnabled: true
            ),
            MatrixContext(
                id: .dirty,
                policyContext: Policy.Context(
                    lifecycle: .different,
                    isDirty: true,
                    hasSelection: true,
                    isReadOnly: false,
                    editorFocus: .none,
                    enabledCommands: dirtyCommands
                ),
                systemCommandsEnabled: true
            ),
            MatrixContext(
                id: .textFocused,
                policyContext: Policy.Context(
                    lifecycle: .different,
                    isDirty: true,
                    hasSelection: true,
                    isReadOnly: false,
                    editorFocus: .editable,
                    enabledCommands: textFocusedCommands
                ),
                systemCommandsEnabled: true
            ),
            MatrixContext(
                id: .readOnly,
                policyContext: Policy.Context(
                    lifecycle: .different,
                    isDirty: false,
                    hasSelection: true,
                    isReadOnly: true,
                    editorFocus: .none,
                    enabledCommands: readOnlyCommands
                ),
                systemCommandsEnabled: true
            )
        ]
    }

    fileprivate static func makeCanonicalExpectations(budget: inout WorkBudget) throws -> [Expectation] {
        var result: [Expectation] = []
        result.reserveCapacity(canonicalDescriptors.count * canonicalContexts.count)
        for descriptor in canonicalDescriptors {
            for context in canonicalContexts {
                try budget.consume()
                result.append(expectedOutcome(for: descriptor, in: context))
            }
        }
        return result
    }

    fileprivate static func expectedOutcome(
        for descriptor: ShortcutDescriptor,
        in context: MatrixContext
    ) -> Expectation {
        let key = MatrixKey(shortcutID: descriptor.id, contextID: context.id)
        let chordCanonical = descriptor.chord.canonicalDescription
        if descriptor.isSystemCommand {
            let isEnabled = context.systemCommandsEnabled
            return Expectation(
                key: key,
                chordCanonical: chordCanonical,
                owner: .system,
                applicationCommand: nil,
                nativeCommand: nil,
                isEnabled: isEnabled,
                invocation: isEnabled ? .invoked : .blocked,
                preservesNativeEditing: false
            )
        }
        if let native = nativeReservation(for: descriptor.chord, focus: context.policyContext.editorFocus) {
            return Expectation(
                key: key,
                chordCanonical: chordCanonical,
                owner: .nativeTextEditor,
                applicationCommand: nil,
                nativeCommand: native,
                isEnabled: true,
                invocation: .invoked,
                preservesNativeEditing: descriptor.preservesNativeEditing
            )
        }
        guard let requirement = descriptor.requirement else {
            return Expectation(
                key: key,
                chordCanonical: chordCanonical,
                owner: .application,
                applicationCommand: descriptor.applicationCommand,
                nativeCommand: nil,
                isEnabled: true,
                invocation: .invoked,
                preservesNativeEditing: descriptor.preservesNativeEditing
            )
        }
        let requirementAllows =
            requirement.enabledLifecycleStates.contains(context.policyContext.lifecycle)
            && (!requirement.requiresDirty || context.policyContext.isDirty)
            && (!requirement.requiresSelection || context.policyContext.hasSelection)
            && (requirement.allowsReadOnly || !context.policyContext.isReadOnly)
        let gateAllows =
            context.policyContext.enabledCommands?.contains(descriptor.applicationCommand!) ?? true
        let isEnabled = requirementAllows && gateAllows
        return Expectation(
            key: key,
            chordCanonical: chordCanonical,
            owner: .application,
            applicationCommand: descriptor.applicationCommand,
            nativeCommand: nil,
            isEnabled: isEnabled,
            invocation: isEnabled ? .invoked : .blocked,
            preservesNativeEditing: descriptor.preservesNativeEditing
        )
    }

    fileprivate static func nativeReservation(
        for chord: Policy.Chord,
        focus: Policy.EditorFocus
    ) -> Policy.NativeTextEditingCommand? {
        for reservation in Policy.standardNativeTextEditingReservations where reservation.chord == chord {
            switch (reservation.applicability, focus) {
            case (.readOnlyAndEditable, .readOnly), (.readOnlyAndEditable, .editable),
                (.readOnly, .readOnly), (.editable, .editable):
                return reservation.command
            case (_, .none), (.readOnly, .editable), (.editable, .readOnly):
                continue
            }
        }
        return nil
    }

    fileprivate struct AuditContext {
        let policy: Policy
        let limits: Limits
        var budget: WorkBudget
        let cancellationCheck: CancellationCheck
        private var findings: [Finding] = []
        private var findingIDs: Set<Finding.ID> = []

        init(
            policy: Policy,
            limits: Limits,
            budget: WorkBudget,
            cancellationCheck: @escaping CancellationCheck
        ) {
            self.policy = policy
            self.limits = limits
            self.budget = budget
            self.cancellationCheck = cancellationCheck
        }

        mutating func run() throws -> Report {
            try inspectInventory()
            let cells = try inspectResolutions()
            try inspectCollisions()
            return Report(
                formatVersion: KeyboardShortcutStateMatrix.reportFormatVersion,
                matrix: Matrix(cells: cells),
                findings: try sortedFindings()
            )
        }

        mutating func receipt(for report: Report) throws -> Receipt {
            var descriptorHasher = FingerprintHasher()
            for descriptor in KeyboardShortcutStateMatrix.canonicalDescriptors {
                try budget.consume()
                descriptorHasher.append(descriptor.id.rawValue)
                descriptorHasher.append(descriptor.chord.canonicalDescription)
                if let command = descriptor.applicationCommand {
                    descriptorHasher.append(command.rawValue)
                } else {
                    descriptorHasher.append("system")
                }
                descriptorHasher.append(descriptor.preservesNativeEditing ? "preserves" : "claims")
            }
            var matrixHasher = FingerprintHasher()
            for context in KeyboardShortcutStateMatrix.canonicalContexts {
                try budget.consume()
                matrixHasher.append(context.id.rawValue)
                matrixHasher.append(context.policyContext.lifecycle.rawValue)
            }
            let expectations = try KeyboardShortcutStateMatrix.makeCanonicalExpectations(
                budget: &budget
            )
            for expectation in expectations {
                try budget.consume()
                matrixHasher.append(expectation.key.shortcutID.rawValue)
                matrixHasher.append(expectation.key.contextID.rawValue)
                matrixHasher.append(expectation.owner.rawValue)
                matrixHasher.append(expectation.isEnabled ? "enabled" : "disabled")
                matrixHasher.append(expectation.invocation.rawValue)
            }
            var findingHasher = FingerprintHasher()
            for finding in report.findings {
                try budget.consume()
                findingHasher.append(finding.id.rawValue)
            }
            return Receipt(
                formatVersion: KeyboardShortcutStateMatrix.reportFormatVersion,
                descriptorFingerprint: descriptorHasher.finalize(),
                matrixFingerprint: matrixHasher.finalize(),
                findingFingerprint: findingHasher.finalize(),
                requiredCellCount: report.matrix.requiredCount,
                completeCellCount: report.matrix.completeCount,
                findingCount: report.findings.count
            )
        }

        private mutating func inspectInventory() throws {
            var seen: Set<KeyboardShortcutStateMatrix.ShortcutID> = []
            for descriptor in KeyboardShortcutStateMatrix.canonicalDescriptors {
                try budget.consume()
                if !seen.insert(descriptor.id).inserted {
                    try add(.error, .duplicateCanonicalShortcut, shortcutID: descriptor.id)
                }
            }
            let expectedShortcuts = Policy.unfinishedAuditCommandShortcuts
            var policyByChord: [Policy.Chord: [Policy.CommandShortcut]] = [:]
            for shortcut in policy.commandShortcuts {
                try budget.consume()
                policyByChord[shortcut.chord, default: []].append(shortcut)
            }
            for descriptor in KeyboardShortcutStateMatrix.canonicalDescriptors {
                try budget.consume()
                if descriptor.isSystemCommand {
                    if let matches = policyByChord[descriptor.chord], !matches.isEmpty {
                        try add(.error, .unexpectedPolicyBinding, shortcutID: descriptor.id)
                    }
                    continue
                }
                guard let command = descriptor.applicationCommand else {
                    try add(.error, .missingPolicyBinding, shortcutID: descriptor.id)
                    continue
                }
                let matches = (policyByChord[descriptor.chord] ?? []).filter {
                    $0.command == command
                }
                if matches.isEmpty {
                    try add(.error, .missingPolicyBinding, shortcutID: descriptor.id)
                } else {
                    if matches.count > 1 {
                        try add(
                            .error,
                            .duplicateCanonicalShortcut,
                            shortcutID: descriptor.id,
                            occurrenceCount: matches.count
                        )
                    }
                    guard let expected = descriptor.requirement else {
                        try add(.error, .policyRequirementMismatch, shortcutID: descriptor.id)
                        continue
                    }
                    if matches.contains(where: { Requirement($0) != expected }) {
                        try add(.error, .policyRequirementMismatch, shortcutID: descriptor.id)
                    }
                }
                let others = (policyByChord[descriptor.chord] ?? []).filter {
                    $0.command != command
                }
                if !others.isEmpty {
                    try add(
                        .error,
                        .unexpectedPolicyBinding,
                        shortcutID: descriptor.id,
                        occurrenceCount: others.count
                    )
                }
            }
            var expectedChords: Set<String> = []
            for descriptor in KeyboardShortcutStateMatrix.canonicalDescriptors where !descriptor.isSystemCommand {
                try budget.consume()
                expectedChords.insert(descriptor.chord.canonicalDescription)
            }
            for shortcut in policy.commandShortcuts {
                try budget.consume()
                if !expectedChords.contains(shortcut.chord.canonicalDescription) {
                    try add(.error, .unexpectedPolicyBinding)
                }
            }
            for shortcut in expectedShortcuts {
                try budget.consume()
                if !expectedChords.contains(shortcut.chord.canonicalDescription) {
                    try add(.error, .unexpectedPolicyBinding)
                }
            }
            for descriptor in KeyboardShortcutStateMatrix.canonicalDescriptors where !descriptor.isSystemCommand {
                try budget.consume()
                let hasNative = policy.nativeTextEditingReservations.contains {
                    $0.chord == descriptor.chord
                }
                if descriptor.preservesNativeEditing != hasNative {
                    try add(.error, .nativePreservationMismatch, shortcutID: descriptor.id)
                }
            }
        }

        private mutating func inspectResolutions() throws -> [Cell] {
            var cells: [Cell] = []
            let count =
                KeyboardShortcutStateMatrix.canonicalDescriptors.count
                * KeyboardShortcutStateMatrix.canonicalContexts.count
            cells.reserveCapacity(count)
            for descriptor in KeyboardShortcutStateMatrix.canonicalDescriptors {
                for context in KeyboardShortcutStateMatrix.canonicalContexts {
                    try budget.consume()
                    if cancellationCheck() {
                        throw KeyboardShortcutStateMatrix.StateError.cancelled
                    }
                    let expected = KeyboardShortcutStateMatrix.expectedOutcome(
                        for: descriptor,
                        in: context
                    )
                    let matches = try resolutionMatches(descriptor: descriptor, context: context, expected: expected)
                    cells.append(Cell(expectation: expected, status: matches ? .complete : .mismatched))
                    if !matches {
                        try add(
                            .error,
                            .resolutionMismatch,
                            shortcutID: descriptor.id,
                            contextID: context.id
                        )
                    }
                }
            }
            return cells.sorted { left, right in
                left.expectation.key < right.expectation.key
            }
        }

        private mutating func resolutionMatches(
            descriptor: KeyboardShortcutStateMatrix.ShortcutDescriptor,
            context: KeyboardShortcutStateMatrix.MatrixContext,
            expected: KeyboardShortcutStateMatrix.Expectation
        ) throws -> Bool {
            if descriptor.isSystemCommand {
                let systemResolution: Policy.Resolution
                do {
                    systemResolution = try policy.resolve(
                        descriptor.chord,
                        in: context.policyContext,
                        cancellationCheck: policyCancellationCheck()
                    )
                } catch KeyboardShortcutPolicyError.cancelled {
                    throw KeyboardShortcutStateMatrix.StateError.cancelled
                } catch {
                    return false
                }
                return systemResolution.route == .unhandled
                    && systemResolution.disabledReason == .noBinding
                    && expected.owner == .system
            }
            let resolution: Policy.Resolution
            do {
                resolution = try policy.resolve(
                    descriptor.chord,
                    in: context.policyContext,
                    cancellationCheck: policyCancellationCheck()
                )
            } catch KeyboardShortcutPolicyError.cancelled {
                throw KeyboardShortcutStateMatrix.StateError.cancelled
            } catch {
                return false
            }
            switch resolution.route {
            case .applicationCommand(let command):
                return expected.owner == .application
                    && expected.applicationCommand == command
                    && expected.nativeCommand == nil
                    && expected.isEnabled == resolution.isEnabled
                    && expected.invocation == (resolution.isEnabled ? .invoked : .blocked)
            case .nativeTextEditing(let command):
                return expected.owner == .nativeTextEditor
                    && expected.nativeCommand == command
                    && expected.isEnabled
                    && expected.invocation == .invoked
                    && resolution.isEnabled
            case .blocked:
                return !expected.isEnabled && expected.invocation == .blocked
            case .unhandled:
                return expected.owner == .none && !expected.isEnabled
            }
        }

        private mutating func inspectCollisions() throws {
            var expectedColliding: Set<String> = []
            for descriptor in KeyboardShortcutStateMatrix.canonicalDescriptors where descriptor.preservesNativeEditing {
                try budget.consume()
                expectedColliding.insert(descriptor.chord.canonicalDescription)
            }
            var actualColliding: Set<String> = []
            for collision in policy.collisions {
                try budget.consume()
                guard collision.kinds.contains(.editorFocusReservation) else { continue }
                actualColliding.insert(collision.chord.canonicalDescription)
            }
            for chord in expectedColliding.sorted() where !actualColliding.contains(chord) {
                try budget.consume()
                try add(.error, .missingCollision)
            }
            for chord in actualColliding.sorted() where !expectedColliding.contains(chord) {
                try budget.consume()
                try add(.error, .unexpectedCollision)
            }
            for collision in policy.collisions {
                try budget.consume()
                if collision.kinds.contains(.applicationCommands) {
                    try add(.error, .unexpectedApplicationCollision)
                }
            }
        }

        private func policyCancellationCheck() -> Policy.CancellationCheck {
            let check = cancellationCheck
            return { () throws(KeyboardShortcutPolicyError) in
                if check() { throw KeyboardShortcutPolicyError.cancelled }
            }
        }

        private mutating func add(
            _ severity: KeyboardShortcutStateMatrix.FindingSeverity,
            _ code: KeyboardShortcutStateMatrix.FindingCode,
            shortcutID: KeyboardShortcutStateMatrix.ShortcutID? = nil,
            contextID: KeyboardShortcutStateMatrix.MatrixContextID? = nil,
            occurrenceCount: Int? = nil
        ) throws {
            try budget.consume()
            if findings.count >= limits.maximumFindings {
                throw KeyboardShortcutStateMatrix.StateError.findingLimitExceeded(
                    maximum: limits.maximumFindings
                )
            }
            let finding = Finding(
                severity: severity,
                code: code,
                shortcutID: shortcutID,
                contextID: contextID,
                occurrenceCount: occurrenceCount
            )
            guard findingIDs.insert(finding.id).inserted else { return }
            findings.append(finding)
        }

        private mutating func sortedFindings() throws -> [Finding] {
            try budget.consume(findings.count + 1)
            return findings.sorted { $0.id < $1.id }
        }
    }
}
