import CryptoKit
import Foundation

/// Bounded, UI-independent validation of the unfinished production shortcut surface.
///
/// Expected inventory and matrix rows are requirements. Only exact automated or manual
/// measurements with complete build provenance count toward measured production coverage.
/// This type performs no event handling, responder-chain dispatch, AppKit work, or I/O.
public enum ShortcutCoverageAudit: Sendable {
    public typealias Policy = KeyboardShortcutPolicy
    public typealias ComparisonCommand = ComparisonCommandState.Identifier
    public typealias CancellationCheck = @Sendable () -> Bool
    public typealias CaptureResolver =
        @Sendable (
            _ digest: ArtifactDigest,
            _ maximumByteCount: Int,
            _ cancellationCheck: CancellationCheck,
            _ stream: CaptureStream
        ) throws -> Void

    public struct StableID: RawRepresentable, Comparable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue.precomposedStringWithCanonicalMapping
        }

        public static func < (left: Self, right: Self) -> Bool {
            shortcutCoverageCompareUTF8(left.rawValue, right.rawValue) < 0
        }

        public var description: String { "ShortcutCoverageStableID(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct RevisionReference: Comparable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let id: StableID
        public let revision: UInt64

        public init(id: StableID, revision: UInt64) {
            self.id = id
            self.revision = revision
        }

        public static func < (left: Self, right: Self) -> Bool {
            if left.id != right.id { return left.id < right.id }
            return left.revision < right.revision
        }

        public var description: String { "ShortcutRevisionReference(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
        }
    }

    public enum ApplicationCommand: Hashable, Sendable {
        case comparison(ComparisonCommand)
        case quit
        case close

        fileprivate var identity: String {
            switch self {
            case .comparison(let command): "comparison.\(command.rawValue)"
            case .quit: "application.quit"
            case .close: "application.close"
            }
        }
    }

    public enum RoutedCommand: Hashable, Sendable {
        case application(ApplicationCommand)
        case nativeTextEditing(Policy.NativeTextEditingCommand)

        fileprivate var identity: String {
            switch self {
            case .application(let command): command.identity
            case .nativeTextEditing(let command): "native.\(command.rawValue)"
            }
        }
    }

    public enum Owner: String, CaseIterable, Comparable, Hashable, Sendable {
        case application
        case nativeTextEditor
        case none

        public static func < (left: Self, right: Self) -> Bool {
            left.rank < right.rank
        }

        fileprivate var rank: Int {
            switch self {
            case .application: 0
            case .nativeTextEditor: 1
            case .none: 2
            }
        }
    }

    public enum InvocationDisposition: String, CaseIterable, Comparable, Hashable, Sendable {
        case invoked
        case blocked
        case unhandled
        case failed

        public static func < (left: Self, right: Self) -> Bool {
            left.rank < right.rank
        }

        fileprivate var rank: Int {
            switch self {
            case .invoked: 0
            case .blocked: 1
            case .unhandled: 2
            case .failed: 3
            }
        }
    }

    public struct Outcome: Hashable, Sendable {
        public let owner: Owner
        public let command: RoutedCommand?
        public let isEnabled: Bool
        public let invocation: InvocationDisposition

        public init(
            owner: Owner,
            command: RoutedCommand?,
            isEnabled: Bool,
            invocation: InvocationDisposition
        ) {
            self.owner = owner
            self.command = command
            self.isEnabled = isEnabled
            self.invocation = invocation
        }

        fileprivate var identityComponents: [String] {
            [
                owner.rawValue,
                command?.identity ?? "",
                isEnabled ? "enabled" : "disabled",
                invocation.rawValue
            ]
        }
    }

    public struct InvocationReceipt: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let source: MenuInvocationSource
        public let targetAction: MenuTargetAction?
        public let result: MenuCommandResult

        public init(
            source: MenuInvocationSource,
            targetAction: MenuTargetAction?,
            result: MenuCommandResult
        ) {
            self.source = source
            self.targetAction = targetAction
            self.result = result
        }

        public var description: String { "ShortcutInvocationReceipt(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
        }

        fileprivate var identityComponents: [String] {
            var result = [
                shortcutCoverageInvocationSourceIdentity(source),
                targetAction?.targetID.rawValue ?? "",
                targetAction?.actionID.rawValue ?? ""
            ]
            shortcutCoverageForEachCommandResultComponent(self.result) {
                result.append($0)
            }
            return result
        }
    }

    public enum DispatchDecision: String, CaseIterable, Comparable, Hashable, Sendable {
        case declined
        case claimed
        case blocked
        case failed

        public static func < (left: Self, right: Self) -> Bool {
            left.rank < right.rank
        }

        fileprivate var rank: Int {
            switch self {
            case .declined: 0
            case .claimed: 1
            case .blocked: 2
            case .failed: 3
            }
        }
    }

    /// One decision from each possible owner, in native-then-application dispatch order.
    public struct OwnershipDecision: Hashable, Sendable {
        public let owner: Owner
        public let command: RoutedCommand?
        public let decision: DispatchDecision

        public init(owner: Owner, command: RoutedCommand?, decision: DispatchDecision) {
            self.owner = owner
            self.command = command
            self.decision = decision
        }

        fileprivate var identityComponents: [String] {
            [owner.rawValue, command?.identity ?? "", decision.rawValue]
        }
    }

    /// Complete observable route: canonicalization, both ownership decisions, target, and result.
    public struct DispatchTrace: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let canonicalChord: Policy.Chord
        public let ownershipDecisions: [OwnershipDecision]
        public let targetActions: [MenuTargetAction]
        public let results: [MenuCommandResult]

        public init(
            canonicalChord: Policy.Chord,
            ownershipDecisions: [OwnershipDecision],
            targetActions: [MenuTargetAction],
            results: [MenuCommandResult]
        ) {
            self.canonicalChord = canonicalChord
            self.ownershipDecisions = ownershipDecisions
            self.targetActions = targetActions
            self.results = results
        }

        public var description: String {
            "ShortcutDispatchTrace(decisions: \(ownershipDecisions.count), targets: \(targetActions.count), results: \(results.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "decisionCount": ownershipDecisions.count,
                    "targetCount": targetActions.count,
                    "resultCount": results.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        fileprivate var identityComponents: [String] {
            var result = [canonicalChord.canonicalDescription]
            result.append(String(ownershipDecisions.count))
            for decision in ownershipDecisions {
                result.append(contentsOf: decision.identityComponents)
            }
            result.append(String(targetActions.count))
            for action in targetActions {
                result.append(action.targetID.rawValue)
                result.append(action.actionID.rawValue)
            }
            result.append(String(results.count))
            for commandResult in results {
                shortcutCoverageForEachCommandResultComponent(commandResult) {
                    result.append($0)
                }
            }
            return result
        }
    }

    /// Raw macOS key-down fields used to independently reconstruct a policy chord.
    public struct HardwareKeyCapture: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let hardwareKeyCode: UInt16
        public let inputSourceID: StableID
        public let charactersIgnoringModifiers: String
        public let rawModifierFlags: UInt64

        public init(
            hardwareKeyCode: UInt16,
            inputSourceID: StableID,
            charactersIgnoringModifiers: String,
            rawModifierFlags: UInt64
        ) {
            self.hardwareKeyCode = hardwareKeyCode
            self.inputSourceID = inputSourceID
            self.charactersIgnoringModifiers = charactersIgnoringModifiers
            self.rawModifierFlags = rawModifierFlags
        }

        public var description: String { "ShortcutHardwareKeyCapture(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
        }

        public func canonicalChord() throws -> Policy.Chord {
            let hardwareKey = shortcutCoverageHardwareKey(hardwareKeyCode)
            var modifiers = shortcutCoverageModifiers(rawModifierFlags)
            if let hardwareKey {
                modifiers.remove(.function)
                guard
                    shortcutCoverageSpecialCharactersMatch(
                        hardwareKeyCode,
                        charactersIgnoringModifiers
                    )
                else {
                    throw AuditError.invalidEvidence(
                        field: "observation.charactersIgnoringModifiers"
                    )
                }
                return try Policy.Chord(hardwareKey, modifiers: modifiers)
            }
            guard let character = shortcutCoverageCharacter(charactersIgnoringModifiers) else {
                throw AuditError.invalidEvidence(
                    field: "observation.charactersIgnoringModifiers"
                )
            }
            return try Policy.Chord(.character(character), modifiers: modifiers)
        }

        fileprivate var identityComponents: [String] {
            [
                String(hardwareKeyCode),
                inputSourceID.rawValue,
                charactersIgnoringModifiers,
                String(rawModifierFlags)
            ]
        }
    }

    public struct PolicyRequirement: Hashable, Sendable {
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

    public struct NativeReservationRequirement: Hashable, Sendable {
        public let command: Policy.NativeTextEditingCommand
        public let applicability: Policy.NativeTextEditingApplicability

        public init(
            command: Policy.NativeTextEditingCommand,
            applicability: Policy.NativeTextEditingApplicability
        ) {
            self.command = command
            self.applicability = applicability
        }

        fileprivate init(_ reservation: Policy.NativeTextEditingReservation) {
            command = reservation.command
            applicability = reservation.applicability
        }
    }

    public struct Binding: Identifiable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let id: StableID
        public let command: ApplicationCommand
        public let shortcut: MenuShortcutDescriptor
        public let policyChord: Policy.Chord
        public let winMergeReference: MenuShortcutDescriptor?
        public let policyRequirement: PolicyRequirement?
        public let focusedEditorReservation: NativeReservationRequirement?
        public let invocationTargetAction: MenuTargetAction
        public let expectedResultID: MenuValidationResultID

        public init(
            id: StableID,
            command: ApplicationCommand,
            shortcut: MenuShortcutDescriptor,
            policyChord: Policy.Chord,
            winMergeReference: MenuShortcutDescriptor? = nil,
            policyRequirement: PolicyRequirement? = nil,
            focusedEditorReservation: NativeReservationRequirement? = nil,
            invocationTargetAction: MenuTargetAction,
            expectedResultID: MenuValidationResultID
        ) {
            self.id = id
            self.command = command
            self.shortcut = shortcut
            self.policyChord = policyChord
            self.winMergeReference = winMergeReference
            self.policyRequirement = policyRequirement
            self.focusedEditorReservation = focusedEditorReservation
            self.invocationTargetAction = invocationTargetAction
            self.expectedResultID = expectedResultID
        }

        public var description: String { "ShortcutBinding(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
        }

        fileprivate var identityComponents: [String] {
            var result =
                [
                    id.rawValue,
                    command.identity
                ] + shortcutCoverageShortcutIdentity(shortcut) + [policyChord.canonicalDescription]
            if let reference = winMergeReference {
                result.append(contentsOf: shortcutCoverageShortcutIdentity(reference))
            } else {
                result.append(contentsOf: ["", "", ""])
            }
            if let requirement = policyRequirement {
                result.append(
                    Policy.LifecycleState.allCases
                        .filter(requirement.enabledLifecycleStates.contains)
                        .map(\.rawValue)
                        .joined(separator: ",")
                )
                result.append(requirement.requiresDirty ? "dirty" : "")
                result.append(requirement.requiresSelection ? "selection" : "")
                result.append(requirement.allowsReadOnly ? "read-only" : "editable")
            } else {
                result.append(contentsOf: ["", "", "", ""])
            }
            if let reservation = focusedEditorReservation {
                result.append(reservation.command.rawValue)
                result.append(reservation.applicability.rawValue)
            } else {
                result.append(contentsOf: ["", ""])
            }
            result.append(invocationTargetAction.targetID.rawValue)
            result.append(invocationTargetAction.actionID.rawValue)
            result.append(expectedResultID.rawValue)
            return result
        }
    }

    public struct NativeBinding: Identifiable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let id: StableID
        public let shortcut: MenuShortcutDescriptor
        public let policyChord: Policy.Chord
        public let reservation: NativeReservationRequirement
        public let invocationTargetAction: MenuTargetAction
        public let expectedResultID: MenuValidationResultID

        public init(
            id: StableID,
            shortcut: MenuShortcutDescriptor,
            policyChord: Policy.Chord,
            reservation: NativeReservationRequirement,
            invocationTargetAction: MenuTargetAction,
            expectedResultID: MenuValidationResultID
        ) {
            self.id = id
            self.shortcut = shortcut
            self.policyChord = policyChord
            self.reservation = reservation
            self.invocationTargetAction = invocationTargetAction
            self.expectedResultID = expectedResultID
        }

        public var description: String { "ShortcutNativeBinding(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
        }

        fileprivate var identityComponents: [String] {
            [id.rawValue]
                + shortcutCoverageShortcutIdentity(shortcut)
                + [
                    policyChord.canonicalDescription,
                    reservation.command.rawValue,
                    reservation.applicability.rawValue,
                    invocationTargetAction.targetID.rawValue,
                    invocationTargetAction.actionID.rawValue,
                    expectedResultID.rawValue
                ]
        }
    }

    public struct TrustedCollector: Comparable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let collector: RevisionReference
        public let signingPublicKey: [UInt8]

        public init(collector: RevisionReference, signingPublicKey: [UInt8]) {
            self.collector = collector
            self.signingPublicKey = signingPublicKey
        }

        public static func < (left: Self, right: Self) -> Bool {
            if left.collector != right.collector { return left.collector < right.collector }
            return left.signingPublicKey.lexicographicallyPrecedes(right.signingPublicKey)
        }

        public var description: String { "ShortcutTrustedCollector(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
        }

        fileprivate var identityComponents: [String] {
            [
                collector.id.rawValue,
                String(collector.revision),
                signingPublicKey.map { String(format: "%02x", $0) }.joined()
            ]
        }
    }

    /// Process-owned trust anchors. Keep this outside caller-supplied inventory and evidence.
    public struct MeasurementTrust: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let build: RevisionReference
        public let executableArtifact: ArtifactDigest
        public let inventoryRevision: UInt64
        public let inventoryArtifact: ArtifactDigest
        public let trustedCollectors: [TrustedCollector]

        public init(
            build: RevisionReference,
            executableArtifact: ArtifactDigest,
            inventoryRevision: UInt64,
            inventoryArtifact: ArtifactDigest,
            trustedCollectors: [TrustedCollector]
        ) {
            self.build = build
            self.executableArtifact = executableArtifact
            self.inventoryRevision = inventoryRevision
            self.inventoryArtifact = inventoryArtifact
            self.trustedCollectors = trustedCollectors
        }

        public var description: String {
            "ShortcutMeasurementTrust(collectors: \(trustedCollectors.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "trustedCollectorCount": trustedCollectors.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        fileprivate var identityComponents: [String] {
            [
                build.id.rawValue,
                String(build.revision),
                executableArtifact.identity,
                String(inventoryRevision),
                inventoryArtifact.identity
            ]
                + trustedCollectors.sorted().flatMap(\.identityComponents)
        }
    }

    public struct Inventory: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public static let canonicalRevision: UInt64 = 3
        public static let canonical = Inventory(
            revision: canonicalRevision,
            bindings: ShortcutCoverageAudit.makeCanonicalBindings(),
            nativeBindings: ShortcutCoverageAudit.makeCanonicalNativeBindings()
        )

        public let revision: UInt64
        public let bindings: [Binding]
        public let nativeBindings: [NativeBinding]

        public init(
            revision: UInt64,
            bindings: [Binding],
            nativeBindings: [NativeBinding] = []
        ) {
            self.revision = revision
            self.bindings = bindings
            self.nativeBindings = nativeBindings
        }

        public var description: String {
            "ShortcutCoverageInventory(revision: \(revision), bindings: \(bindings.count), nativeBindings: \(nativeBindings.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "revision": revision,
                    "bindingCount": bindings.count,
                    "nativeBindingCount": nativeBindings.count
                ],
                displayStyle: .struct
            )
        }
    }

    public enum ContextID: String, CaseIterable, Comparable, Hashable, Sendable {
        case empty
        case disabled
        case loading
        case selected
        case dirty
        case textFocused
        case textFocusedClean
        case equal
        case failed
        case readOnly
        case editorReadOnly
        case directionalLeft
        case directionalRight
        case leftDestinationReadOnly
        case rightDestinationReadOnly
        case leftDestinationUnloaded
        case rightDestinationUnloaded
        case lineSelectionUnavailable
        case currentDifferenceUnavailable
        case changePaneUnavailable
        case changePaneBackUnavailable
        case navigationAtStart
        case navigationAtEnd
        case refreshing
        case stale
        case canceled
        case undoEnabled
        case redoEnabled
        case differencePreviousOnly
        case differenceNextOnly
        case conflictPreviousOnly
        case conflictNextOnly
        case comparedFilePreviousOnly
        case comparedFileNextOnly

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
            case .textFocusedClean: 6
            case .equal: 7
            case .failed: 8
            case .readOnly: 9
            case .editorReadOnly: 10
            case .directionalLeft: 11
            case .directionalRight: 12
            case .leftDestinationReadOnly: 13
            case .rightDestinationReadOnly: 14
            case .leftDestinationUnloaded: 15
            case .rightDestinationUnloaded: 16
            case .lineSelectionUnavailable: 17
            case .currentDifferenceUnavailable: 18
            case .changePaneUnavailable: 19
            case .changePaneBackUnavailable: 20
            case .navigationAtStart: 21
            case .navigationAtEnd: 22
            case .refreshing: 23
            case .stale: 24
            case .canceled: 25
            case .undoEnabled: 26
            case .redoEnabled: 27
            case .differencePreviousOnly: 28
            case .differenceNextOnly: 29
            case .conflictPreviousOnly: 30
            case .conflictNextOnly: 31
            case .comparedFilePreviousOnly: 32
            case .comparedFileNextOnly: 33
            }
        }
    }

    /// Exact command-state and keyboard-policy inputs for one required matrix row.
    public struct InvocationContext: Identifiable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public var id: ContextID { contextID }

        public let contextID: ContextID
        public let commandState: ComparisonCommandState.Context
        public let keyboardState: Policy.Context
        public let systemCommandsEnabled: Bool

        public init(
            contextID: ContextID,
            commandState: ComparisonCommandState.Context,
            keyboardState: Policy.Context,
            systemCommandsEnabled: Bool
        ) {
            self.contextID = contextID
            self.commandState = commandState
            self.keyboardState = keyboardState
            self.systemCommandsEnabled = systemCommandsEnabled
        }

        fileprivate var identityComponents: [String] {
            let enabledCommands =
                keyboardState.enabledCommands?.sorted { left, right in
                    shortcutCoverageCompareUTF8(left.rawValue, right.rawValue) < 0
                }.map(\.rawValue).joined(separator: ",") ?? "*"
            return [
                contextID.rawValue,
                keyboardState.lifecycle.rawValue,
                keyboardState.isDirty ? "dirty" : "clean",
                keyboardState.hasSelection ? "selected" : "unselected",
                keyboardState.isReadOnly ? "read-only" : "editable",
                keyboardState.editorFocus.rawValue,
                enabledCommands,
                systemCommandsEnabled ? "system-enabled" : "system-disabled"
            ] + shortcutCoverageCommandStateIdentity(commandState)
        }

        public var description: String { "ShortcutInvocationContext(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct MatrixKey: Comparable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let bindingID: StableID
        public let contextID: ContextID

        public init(bindingID: StableID, contextID: ContextID) {
            self.bindingID = bindingID
            self.contextID = contextID
        }

        public static func < (left: Self, right: Self) -> Bool {
            if left.bindingID != right.bindingID { return left.bindingID < right.bindingID }
            return left.contextID < right.contextID
        }

        fileprivate var identityComponents: [String] {
            [bindingID.rawValue, contextID.rawValue]
        }

        public var description: String { "ShortcutMatrixKey(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct Expectation: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let key: MatrixKey
        public let outcome: Outcome

        public init(key: MatrixKey, outcome: Outcome) {
            self.key = key
            self.outcome = outcome
        }

        public var description: String { "ShortcutExpectation(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .struct)
        }
    }

    public enum EvidenceOrigin: String, CaseIterable, Hashable, Sendable {
        case designSpecification
        case callerAssertion
        case automatedMeasurement
        case manualMeasurement

        public var isMeasured: Bool {
            self == .automatedMeasurement || self == .manualMeasurement
        }
    }

    public struct ArtifactDigest: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public enum Algorithm: String, CaseIterable, Hashable, Sendable {
            case sha256
        }

        public let algorithm: Algorithm
        public let bytes: [UInt8]

        public init(algorithm: Algorithm = .sha256, bytes: [UInt8]) {
            self.algorithm = algorithm
            self.bytes = bytes
        }

        public static func sha256(of data: Data) -> Self {
            Self(bytes: Array(SHA256.hash(data: data)))
        }

        public var description: String { "ArtifactDigest(algorithm: \(algorithm.rawValue), <redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["algorithm": algorithm, "bytes": "<redacted>"],
                displayStyle: .struct
            )
        }

        fileprivate var identity: String {
            algorithm.rawValue + ":" + bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Synchronous, bounded sink. Resolver must append each capture chunk before returning.
    public final class CaptureStream: @unchecked Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        private let lock = NSLock()
        private let maximumByteCount: Int
        private let expected: Data
        private let cancellationCheck: CancellationCheck
        private var byteCount = 0
        private var chunks: [Data] = []
        private var finished = false
        private var failure: AuditError?
        private let budget: WorkBudget

        fileprivate init(
            expected: Data,
            maximumByteCount: Int,
            cancellationCheck: @escaping CancellationCheck,
            budget: WorkBudget
        ) {
            self.expected = expected
            self.maximumByteCount = maximumByteCount
            self.cancellationCheck = cancellationCheck
            self.budget = budget
        }

        public func append(_ chunk: Data) throws {
            try checkCancellation()
            do {
                try budget.consume(UInt64(max(1, chunk.count)))
            } catch let error as AuditError {
                record(error)
                throw error
            }
            lock.lock()
            defer { lock.unlock() }
            if let failure { throw failure }
            guard !finished else {
                throw AuditError.invalidEvidence(field: "measurement.capture")
            }
            guard chunk.count <= maximumByteCount,
                byteCount <= maximumByteCount - chunk.count
            else {
                let error = AuditError.captureTooLarge(maximumBytes: maximumByteCount)
                failure = error
                throw error
            }
            chunks.append(chunk)
            byteCount += chunk.count
        }

        fileprivate func finish() throws -> (digest: ArtifactDigest, matches: Bool, byteCount: Int) {
            if cancellationCheck() { throw AuditError.cancelled }
            lock.lock()
            if let failure {
                lock.unlock()
                throw failure
            }
            guard !finished else {
                lock.unlock()
                throw AuditError.invalidEvidence(field: "measurement.capture")
            }
            finished = true
            let capturedChunks = chunks
            let capturedByteCount = byteCount
            lock.unlock()

            var hasher = SHA256()
            var matches = true
            var comparedByteCount = 0
            let sliceByteCount = max(1, Int(clamping: budget.cancellationCheckInterval))
            for chunk in capturedChunks {
                var lowerBound = chunk.startIndex
                while lowerBound < chunk.endIndex {
                    if cancellationCheck() { throw AuditError.cancelled }
                    let upperBound = chunk.index(
                        lowerBound,
                        offsetBy: min(
                            sliceByteCount,
                            chunk.distance(from: lowerBound, to: chunk.endIndex)
                        )
                    )
                    let slice = chunk[lowerBound..<upperBound]
                    hasher.update(data: slice)
                    for byte in slice {
                        if comparedByteCount >= expected.count
                            || expected[comparedByteCount] != byte
                        {
                            matches = false
                        }
                        comparedByteCount += 1
                    }
                    lowerBound = upperBound
                }
            }
            if cancellationCheck() { throw AuditError.cancelled }
            return (
                ArtifactDigest(bytes: Array(hasher.finalize())),
                matches && comparedByteCount == expected.count,
                capturedByteCount
            )
        }

        fileprivate func recordedFailure() -> AuditError? {
            lock.lock()
            defer { lock.unlock() }
            return failure
        }

        private func checkCancellation() throws {
            if cancellationCheck() {
                let error = AuditError.cancelled
                record(error)
                throw error
            }
        }

        private func record(_ error: AuditError) {
            lock.lock()
            if failure == nil { failure = error }
            lock.unlock()
        }
        public var description: String { "ShortcutCaptureStream(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["contents": "<redacted>"], displayStyle: .class)
        }
    }

    /// Caller-captured production binding. Validation checks shape and exact references only.
    public struct MeasurementProvenance: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let captureID: StableID
        public let collector: RevisionReference
        public let build: RevisionReference
        public let executableArtifact: ArtifactDigest
        public let inventoryRevision: UInt64
        public let inventoryArtifact: ArtifactDigest
        public let measurementArtifact: ArtifactDigest
        public let capturedAtUnixMilliseconds: UInt64
        public let runNonce: [UInt8]
        public let captureSignature: [UInt8]

        public init(
            captureID: StableID,
            collector: RevisionReference,
            build: RevisionReference,
            executableArtifact: ArtifactDigest,
            inventoryRevision: UInt64,
            inventoryArtifact: ArtifactDigest,
            measurementArtifact: ArtifactDigest,
            capturedAtUnixMilliseconds: UInt64,
            runNonce: [UInt8],
            captureSignature: [UInt8]
        ) {
            self.captureID = captureID
            self.collector = collector
            self.build = build
            self.executableArtifact = executableArtifact
            self.inventoryRevision = inventoryRevision
            self.inventoryArtifact = inventoryArtifact
            self.measurementArtifact = measurementArtifact
            self.capturedAtUnixMilliseconds = capturedAtUnixMilliseconds
            self.runNonce = runNonce
            self.captureSignature = captureSignature
        }

        public var description: String {
            "MeasurementProvenance(<redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["provenance": "<redacted>"],
                displayStyle: .struct
            )
        }

        fileprivate var identityComponents: [String] {
            [
                captureID.rawValue,
                collector.id.rawValue,
                String(collector.revision),
                build.id.rawValue,
                String(build.revision),
                executableArtifact.identity,
                String(inventoryRevision),
                inventoryArtifact.identity,
                measurementArtifact.identity,
                String(capturedAtUnixMilliseconds),
                runNonce.map { String(format: "%02x", $0) }.joined(),
                captureSignature.map { String(format: "%02x", $0) }.joined()
            ]
        }

    }

    public struct EvidenceProvenance: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let origin: EvidenceOrigin
        public let sourceID: StableID
        public let measurement: MeasurementProvenance?

        public init(
            origin: EvidenceOrigin,
            sourceID: StableID,
            measurement: MeasurementProvenance? = nil
        ) {
            self.origin = origin
            self.sourceID = sourceID
            self.measurement = measurement
        }

        public var description: String {
            "EvidenceProvenance(origin: \(origin.rawValue), source: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["origin": origin, "source": "<redacted>"],
                displayStyle: .struct
            )
        }

        fileprivate var identityComponents: [String] {
            [origin.rawValue, sourceID.rawValue] + (measurement?.identityComponents ?? [])
        }

    }

    /// One caller-supplied invocation observation. Initializers never perform production work.
    public struct Observation: Identifiable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let id: StableID
        public let key: MatrixKey
        public let shortcut: MenuShortcutDescriptor
        public let hardwareKeyCapture: HardwareKeyCapture
        public let context: InvocationContext
        public let outcome: Outcome
        public let invocationReceipt: InvocationReceipt
        public let dispatchTrace: DispatchTrace
        public let provenance: EvidenceProvenance

        public init(
            id: StableID,
            key: MatrixKey,
            shortcut: MenuShortcutDescriptor,
            hardwareKeyCapture: HardwareKeyCapture,
            context: InvocationContext,
            outcome: Outcome,
            invocationReceipt: InvocationReceipt,
            dispatchTrace: DispatchTrace,
            provenance: EvidenceProvenance
        ) {
            self.id = id
            self.key = key
            self.shortcut = shortcut
            self.hardwareKeyCapture = hardwareKeyCapture
            self.context = context
            self.outcome = outcome
            self.invocationReceipt = invocationReceipt
            self.dispatchTrace = dispatchTrace
            self.provenance = provenance
        }

        public var description: String {
            "ShortcutObservation(contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "fieldCount": 9,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        fileprivate var identityComponents: [String] {
            [id.rawValue] + key.identityComponents + shortcutCoverageShortcutIdentity(shortcut)
                + hardwareKeyCapture.identityComponents + context.identityComponents
                + outcome.identityComponents
                + invocationReceipt.identityComponents
                + dispatchTrace.identityComponents
                + provenance.identityComponents
        }

        fileprivate func forEachCaptureBindingComponent(
            _ body: (String) throws -> Void
        ) rethrows {
            try body(id.rawValue)
            for component in key.identityComponents { try body(component) }
            for component in shortcutCoverageShortcutIdentity(shortcut) { try body(component) }
            for component in hardwareKeyCapture.identityComponents { try body(component) }
            for component in context.identityComponents { try body(component) }
            for component in outcome.identityComponents { try body(component) }
            try body(shortcutCoverageInvocationSourceIdentity(invocationReceipt.source))
            try body(invocationReceipt.targetAction?.targetID.rawValue ?? "")
            try body(invocationReceipt.targetAction?.actionID.rawValue ?? "")
            try shortcutCoverageForEachCommandResultComponent(invocationReceipt.result, body)
            try body(dispatchTrace.canonicalChord.canonicalDescription)
            try body(String(dispatchTrace.ownershipDecisions.count))
            for decision in dispatchTrace.ownershipDecisions {
                for component in decision.identityComponents { try body(component) }
            }
            try body(String(dispatchTrace.targetActions.count))
            for action in dispatchTrace.targetActions {
                try body(action.targetID.rawValue)
                try body(action.actionID.rawValue)
            }
            try body(String(dispatchTrace.results.count))
            for result in dispatchTrace.results {
                try shortcutCoverageForEachCommandResultComponent(result, body)
            }
            try body(provenance.origin.rawValue)
            try body(provenance.sourceID.rawValue)
            guard let measurement = provenance.measurement else { return }
            try body(measurement.captureID.rawValue)
            try body(measurement.collector.id.rawValue)
            try body(String(measurement.collector.revision))
            try body(measurement.build.id.rawValue)
            try body(String(measurement.build.revision))
            try body(measurement.executableArtifact.identity)
            try body(String(measurement.inventoryRevision))
            try body(measurement.inventoryArtifact.identity)
            try body(String(measurement.capturedAtUnixMilliseconds))
            try body(shortcutCoverageHex(measurement.runNonce))
        }
    }

    public struct Evidence: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let inventoryRevision: UInt64
        public let observations: [Observation]

        public init(inventoryRevision: UInt64, observations: [Observation]) {
            self.inventoryRevision = inventoryRevision
            self.observations = observations
        }

        public var description: String {
            "ShortcutCoverageEvidence(revision: \(inventoryRevision), observations: \(observations.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "inventoryRevision": inventoryRevision,
                    "observationCount": observations.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum FindingSeverity: String, CaseIterable, Comparable, Hashable, Sendable {
        case advisory
        case warning
        case error

        public static func < (left: Self, right: Self) -> Bool {
            left.rank < right.rank
        }

        fileprivate var rank: Int {
            switch self {
            case .advisory: 0
            case .warning: 1
            case .error: 2
            }
        }
    }

    public enum FindingCode: String, CaseIterable, Hashable, Sendable {
        case duplicateInventoryBinding
        case duplicateInventoryChord
        case inventoryRevisionMismatch
        case missingInventoryBinding
        case unexpectedInventoryBinding
        case inventoryBindingMismatch
        case missingPolicyBinding
        case duplicatePolicyBinding
        case unexpectedPolicyBinding
        case policyBindingMismatch
        case unexpectedPolicyCollision
        case collisionMismatch
        case missingNativeReservation
        case nativeReservationMismatch
        case unexpectedNativeReservation
        case commandStateResolutionMismatch
        case policyResolutionMismatch
        case staleEvidence
        case duplicateObservationID
        case duplicateObservation
        case missingObservation
        case unexpectedObservation
        case assertionOnlyEvidence
        case invalidMeasuredProvenance
        case measurementTrustMissing
        case measuredBuildMismatch
        case measuredArtifactMismatch
        case untrustedMeasurementCollector
        case measurementCaptureUnavailable
        case measurementCaptureMismatch
        case measurementSignatureMismatch
        case measuredInventoryMismatch
        case hardwareKeyMismatch
        case dispatchTraceMismatch
        case shortcutMismatch
        case contextMismatch
        case invocationReceiptMismatch
        case outcomeMismatch
    }

    public struct Finding: Identifiable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public struct ID: RawRepresentable, Comparable, Hashable, Sendable,
            CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
        {
            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }

            public static func < (left: Self, right: Self) -> Bool {
                shortcutCoverageCompareUTF8(left.rawValue, right.rawValue) < 0
            }

            public var description: String { "ShortcutCoverageFindingID(<redacted>)" }
            public var debugDescription: String { description }
            public var customMirror: Mirror {
                Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
            }
        }

        public let id: ID
        public let severity: FindingSeverity
        public let code: FindingCode
        public let bindingID: StableID?
        public let contextID: ContextID?
        public let occurrenceCount: Int?
        public let message: String

        fileprivate init(
            id: ID,
            severity: FindingSeverity,
            code: FindingCode,
            bindingID: StableID? = nil,
            contextID: ContextID? = nil,
            occurrenceCount: Int? = nil,
            discriminator: String = ""
        ) {
            self.id = id
            self.severity = severity
            self.code = code
            self.bindingID = bindingID
            self.contextID = contextID
            self.occurrenceCount = occurrenceCount
            message = ShortcutCoverageAudit.message(for: code)
        }

        public var description: String {
            "ShortcutCoverageFinding(code: \(code.rawValue), details: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "code": code,
                    "occurrenceCount": occurrenceCount as Any,
                    "details": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum CellStatus: String, CaseIterable, Hashable, Sendable {
        case complete
        case missing
        case duplicate
        case mismatched
        case invalid
        case assertionOnly
    }

    public struct MatrixCell: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let expectation: Expectation
        public let observedOutcome: Outcome?
        public let evidenceCount: Int
        public let status: CellStatus
        public let statuses: Set<CellStatus>

        fileprivate init(
            expectation: Expectation,
            observedOutcome: Outcome?,
            evidenceCount: Int,
            statuses: Set<CellStatus>
        ) {
            self.expectation = expectation
            self.observedOutcome = observedOutcome
            self.evidenceCount = evidenceCount
            self.status = shortcutCoveragePrimaryStatus(statuses)
            self.statuses = statuses
        }

        public var description: String {
            "ShortcutMatrixCell(status: \(status.rawValue), evidence: \(evidenceCount), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "status": status,
                    "evidenceCount": evidenceCount,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Matrix: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let cells: [MatrixCell]

        fileprivate init(cells: [MatrixCell]) {
            self.cells = cells
        }

        public var requiredCount: Int { cells.count }
        public var completeCount: Int { cells.count(where: { $0.statuses == [.complete] }) }
        public var missingCount: Int { cells.count(where: { $0.statuses.contains(.missing) }) }
        public var duplicateCount: Int { cells.count(where: { $0.statuses.contains(.duplicate) }) }
        public var mismatchCount: Int { cells.count(where: { $0.statuses.contains(.mismatched) }) }
        public var invalidCount: Int { cells.count(where: { $0.statuses.contains(.invalid) }) }
        public var assertionOnlyCount: Int {
            cells.count(where: { $0.statuses.contains(.assertionOnly) })
        }
        public var hasCompleteMeasuredCoverage: Bool { completeCount == requiredCount }

        public var description: String {
            "ShortcutCoverageMatrix(required: \(requiredCount), complete: \(completeCount), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "requiredCount": requiredCount,
                    "completeCount": completeCount,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Report: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public static let scopeStatement =
            "Deterministic validation of the canonical unfinished shortcut inventory, command-state matrix, native editor reservations, and caller-supplied build-bound measurements; not independent runtime UI verification."

        public let formatVersion: Int
        public let inventoryRevision: UInt64
        public let matrix: Matrix
        public let findings: [Finding]

        public var highestSeverity: FindingSeverity? { findings.first?.severity }
        public var containsErrors: Bool { findings.contains { $0.severity == .error } }
        /// Caller assertions and design specifications never contribute to this result.
        public var hasMeasuredProductionCoverage: Bool {
            matrix.hasCompleteMeasuredCoverage && findings.isEmpty
        }

        fileprivate init(
            formatVersion: Int,
            inventoryRevision: UInt64,
            matrix: Matrix,
            findings: [Finding]
        ) {
            self.formatVersion = formatVersion
            self.inventoryRevision = inventoryRevision
            self.matrix = matrix
            self.findings = findings
        }

        public var description: String {
            "ShortcutCoverageReport(revision: \(inventoryRevision), required: \(matrix.requiredCount), findings: \(findings.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "formatVersion": formatVersion,
                    "inventoryRevision": inventoryRevision,
                    "requiredCount": matrix.requiredCount,
                    "findingCount": findings.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Fingerprint: RawRepresentable, Comparable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue < right.rawValue
        }

        public var description: String { "ShortcutCoverageFingerprint(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
        }
    }

    /// Deterministic content receipt. FNV-1a fingerprints detect drift; they are not signatures.
    public struct Receipt: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let formatVersion: Int
        public let inventoryRevision: UInt64
        public let inventoryFingerprint: Fingerprint
        public let policyFingerprint: Fingerprint
        public let matrixFingerprint: Fingerprint
        public let evidenceFingerprint: Fingerprint
        public let findingFingerprint: Fingerprint
        public let requiredObservationCount: Int
        public let completeMeasuredObservationCount: Int
        public let assertionOnlyObservationCount: Int
        public let findingCount: Int

        fileprivate init(
            formatVersion: Int,
            inventoryRevision: UInt64,
            inventoryFingerprint: Fingerprint,
            policyFingerprint: Fingerprint,
            matrixFingerprint: Fingerprint,
            evidenceFingerprint: Fingerprint,
            findingFingerprint: Fingerprint,
            requiredObservationCount: Int,
            completeMeasuredObservationCount: Int,
            assertionOnlyObservationCount: Int,
            findingCount: Int
        ) {
            self.formatVersion = formatVersion
            self.inventoryRevision = inventoryRevision
            self.inventoryFingerprint = inventoryFingerprint
            self.policyFingerprint = policyFingerprint
            self.matrixFingerprint = matrixFingerprint
            self.evidenceFingerprint = evidenceFingerprint
            self.findingFingerprint = findingFingerprint
            self.requiredObservationCount = requiredObservationCount
            self.completeMeasuredObservationCount = completeMeasuredObservationCount
            self.assertionOnlyObservationCount = assertionOnlyObservationCount
            self.findingCount = findingCount
        }

        public var description: String {
            "ShortcutCoverageReceipt(revision: \(inventoryRevision), required: \(requiredObservationCount), measured: \(completeMeasuredObservationCount), assertions: \(assertionOnlyObservationCount), findings: \(findingCount), fingerprints: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "formatVersion": formatVersion,
                    "inventoryRevision": inventoryRevision,
                    "requiredObservationCount": requiredObservationCount,
                    "completeMeasuredObservationCount": completeMeasuredObservationCount,
                    "assertionOnlyObservationCount": assertionOnlyObservationCount,
                    "findingCount": findingCount,
                    "fingerprints": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Result: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let report: Report
        public let receipt: Receipt

        fileprivate init(report: Report, receipt: Receipt) {
            self.report = report
            self.receipt = receipt
        }

        public var description: String {
            "ShortcutCoverageResult(required: \(report.matrix.requiredCount), findings: \(report.findings.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "requiredCount": report.matrix.requiredCount,
                    "findingCount": report.findings.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumBindings = 4_096
        public static let hardMaximumContexts = 256
        public static let hardMaximumTrustedCollectors = 4_096
        public static let hardMaximumObservations = 1_000_000
        public static let hardMaximumFindings = 1_000_000
        public static let hardMaximumStringUTF8Bytes = 1 * 1_024 * 1_024
        public static let hardMaximumTotalStringUTF8Bytes = 128 * 1_024 * 1_024
        public static let hardMaximumCaptureBytes = 128 * 1_024 * 1_024
        public static let hardMaximumWorkUnits: UInt64 = 1 << 40
        public static let hardMaximumCancellationCheckInterval = 65_536
        public static let `default` = Limits()

        public let maximumBindings: Int
        public let maximumContexts: Int
        public let maximumTrustedCollectors: Int
        public let maximumObservations: Int
        public let maximumFindings: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumCaptureBytes: Int
        public let maximumWorkUnits: UInt64
        public let cancellationCheckInterval: Int

        public init(
            maximumBindings: Int = 256,
            maximumContexts: Int = 64,
            maximumTrustedCollectors: Int = 256,
            maximumObservations: Int = 65_536,
            maximumFindings: Int = 100_000,
            maximumStringUTF8Bytes: Int = 64 * 1_024,
            maximumTotalStringUTF8Bytes: Int = 16 * 1_024 * 1_024,
            maximumCaptureBytes: Int = 1 * 1_024 * 1_024,
            maximumWorkUnits: UInt64 = 64 * 1_024 * 1_024,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumBindings = maximumBindings
            self.maximumContexts = maximumContexts
            self.maximumTrustedCollectors = maximumTrustedCollectors
            self.maximumObservations = maximumObservations
            self.maximumFindings = maximumFindings
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumCaptureBytes = maximumCaptureBytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case bindings
        case contexts
        case trustedCollectors
        case observations
        case findings
        case stringUTF8Bytes
        case totalStringUTF8Bytes
        case captureBytes
        case workUnits
        case cancellationCheckInterval
    }

    public enum AuditError: Error, Equatable, LocalizedError, Sendable {
        case cancelled
        case invalidLimit(Limit)
        case countLimitExceeded(Limit, maximum: Int)
        case stringTooLarge(field: String, maximumUTF8Bytes: Int)
        case captureTooLarge(maximumBytes: Int)
        case totalStringsTooLarge(maximumUTF8Bytes: Int)
        case workLimitExceeded(maximum: UInt64)
        case findingLimitExceeded(maximum: Int)
        case invalidInventory(field: String)
        case invalidEvidence(field: String)
        case canonicalPolicyUnavailable

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                "Shortcut coverage audit was cancelled."
            case .invalidLimit(let limit):
                "Shortcut coverage limit is invalid: \(limit.rawValue)."
            case .countLimitExceeded(let limit, let maximum):
                "Shortcut coverage exceeds the \(maximum)-\(limit.rawValue) limit."
            case .stringTooLarge(let field, let maximum):
                "Shortcut coverage field \(field) exceeds \(maximum) UTF-8 bytes; contents are redacted."
            case .captureTooLarge(let maximum):
                "Shortcut coverage capture exceeds \(maximum) bytes; contents are redacted."
            case .totalStringsTooLarge(let maximum):
                "Shortcut coverage strings exceed \(maximum) UTF-8 bytes; contents are redacted."
            case .workLimitExceeded(let maximum):
                "Shortcut coverage audit exceeds \(maximum) work units."
            case .findingLimitExceeded(let maximum):
                "Shortcut coverage audit exceeds \(maximum) findings."
            case .invalidInventory(let field):
                "Shortcut coverage inventory is invalid at \(field); contents are redacted."
            case .invalidEvidence(let field):
                "Shortcut coverage evidence is invalid at \(field); contents are redacted."
            case .canonicalPolicyUnavailable:
                "Canonical shortcut policy could not be constructed."
            }
        }
    }

    public static let reportFormatVersion = 3
    public static let captureFormatVersion = 2
    public static let requiredContexts = makeCanonicalContexts()

    public static func canonicalMatrix(
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> [Expectation] {
        var budget = try WorkBudget(limits: .default, cancellationCheck: cancellationCheck)
        let matrix = try makeCanonicalMatrix(budget: &budget, cancellationCheck: cancellationCheck)
        try budget.finish()
        return matrix
    }

    /// Canonical payload persisted by a trusted collector and resolved by measurement digest.
    public static func canonicalCaptureData(
        for observation: Observation,
        maximumBytes: Int = Limits.default.maximumCaptureBytes,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try canonicalCaptureData(
            for: observation,
            maximumBytes: maximumBytes,
            cancellationCheck: cancellationCheck,
            budget: nil
        )
    }

    private static func canonicalCaptureData(
        for observation: Observation,
        maximumBytes: Int,
        cancellationCheck: @escaping CancellationCheck,
        budget: WorkBudget?
    ) throws -> Data {
        guard (0...Limits.hardMaximumCaptureBytes).contains(maximumBytes) else {
            throw AuditError.invalidLimit(.captureBytes)
        }
        guard
            shortcutCoverageCaptureBinaryInputIsBounded(
                observation,
                maximumBytes: maximumBytes
            )
        else {
            throw AuditError.captureTooLarge(maximumBytes: maximumBytes)
        }
        var result = Data()
        for component in [
            "org.macmerge.shortcut-coverage.capture",
            String(captureFormatVersion)
        ] {
            try shortcutCoverageAppendFramed(
                component,
                to: &result,
                maximumBytes: maximumBytes,
                cancellationCheck: cancellationCheck,
                budget: budget
            )
        }
        try observation.forEachCaptureBindingComponent { component in
            try shortcutCoverageAppendFramed(
                component,
                to: &result,
                maximumBytes: maximumBytes,
                cancellationCheck: cancellationCheck,
                budget: budget
            )
        }
        if cancellationCheck() { throw AuditError.cancelled }
        return result
    }

    public static func inventoryArtifact(
        for inventory: Inventory,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> ArtifactDigest {
        var budget = try WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        guard inventory.bindings.count <= limits.maximumBindings,
            inventory.nativeBindings.count <= limits.maximumBindings
        else {
            throw AuditError.countLimitExceeded(.bindings, maximum: limits.maximumBindings)
        }
        var totalStringBytes = 0
        for binding in inventory.bindings {
            for component in binding.identityComponents {
                try inspectString(
                    component,
                    field: "binding.inventoryArtifact",
                    limits: limits,
                    totalStringBytes: &totalStringBytes,
                    budget: &budget
                )
            }
        }
        for binding in inventory.nativeBindings {
            for component in binding.identityComponents {
                try inspectString(
                    component,
                    field: "nativeBinding.inventoryArtifact",
                    limits: limits,
                    totalStringBytes: &totalStringBytes,
                    budget: &budget
                )
            }
        }
        var hasher = SHA256()
        try shortcutCoverageHashFramed(
            String(inventory.revision),
            into: &hasher,
            budget: budget
        )
        for binding in try shortcutCoverageSortedBindings(inventory.bindings, budget: budget) {
            for component in binding.identityComponents {
                try shortcutCoverageHashFramed(component, into: &hasher, budget: budget)
            }
        }
        for binding in try shortcutCoverageSortedNativeBindings(
            inventory.nativeBindings,
            budget: budget
        ) {
            for component in binding.identityComponents {
                try shortcutCoverageHashFramed(component, into: &hasher, budget: budget)
            }
        }
        try budget.finish()
        return ArtifactDigest(bytes: Array(hasher.finalize()))
    }

    public static func signaturePayload(
        for observation: Observation,
        maximumBytes: Int = Limits.default.maximumCaptureBytes,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        guard (0...Limits.hardMaximumCaptureBytes).contains(maximumBytes) else {
            throw AuditError.invalidLimit(.captureBytes)
        }
        guard let measurement = observation.provenance.measurement else {
            throw AuditError.invalidEvidence(field: "measurement")
        }
        guard measurement.measurementArtifact.algorithm == .sha256,
            measurement.measurementArtifact.bytes.count == 32
        else {
            throw AuditError.invalidEvidence(field: "measurement.measurementArtifact")
        }
        var data = Data()
        for component in [
            "org.macmerge.shortcut-coverage.signature",
            String(captureFormatVersion),
            measurement.measurementArtifact.identity
        ] {
            try shortcutCoverageAppendFramed(
                component,
                to: &data,
                maximumBytes: maximumBytes,
                cancellationCheck: cancellationCheck
            )
        }
        return data
    }

    public static func audit(
        evidence: Evidence,
        inventory: Inventory = .canonical,
        measurementTrust: MeasurementTrust? = nil,
        limits: Limits = .default,
        captureResolver: CaptureResolver? = nil,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Result {
        let policy: Policy
        do {
            policy = try Policy.makeUnfinishedAudit(
                cancellationCheck: policyCancellationCheck(cancellationCheck)
            )
        } catch KeyboardShortcutPolicyError.cancelled {
            throw AuditError.cancelled
        } catch {
            throw AuditError.canonicalPolicyUnavailable
        }
        return try audit(
            inventory: inventory,
            policy: policy,
            evidence: evidence,
            measurementTrust: measurementTrust,
            limits: limits,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck
        )
    }

    public static func audit(
        inventory: Inventory,
        policy: Policy,
        evidence: Evidence,
        measurementTrust: MeasurementTrust? = nil,
        limits: Limits = .default,
        captureResolver: CaptureResolver? = nil,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Result {
        var budget = try WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try preflight(
            inventory: inventory,
            evidence: evidence,
            measurementTrust: measurementTrust,
            limits: limits,
            budget: &budget
        )
        let expectations = try makeCanonicalMatrix(
            budget: &budget,
            cancellationCheck: cancellationCheck
        )
        var context = AuditContext(
            inventory: inventory,
            policy: policy,
            evidence: evidence,
            expectations: expectations,
            measurementTrust: measurementTrust,
            limits: limits,
            budget: budget,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck
        )
        let report = try context.run()
        let receipt = try context.receipt(for: report)
        try context.budget.finish()
        return Result(report: report, receipt: receipt)
    }

    private static func makeCanonicalBindings() -> [Binding] {
        let workspace: Set<Policy.LifecycleState> = [.empty, .equal, .different, .failed]
        let differences: Set<Policy.LifecycleState> = [.different]
        let writableWorkspace = PolicyRequirement(
            enabledLifecycleStates: workspace,
            requiresDirty: true,
            allowsReadOnly: false
        )
        let editableWorkspace = PolicyRequirement(
            enabledLifecycleStates: workspace,
            allowsReadOnly: false
        )
        let navigation = PolicyRequirement(enabledLifecycleStates: differences)
        let copy = PolicyRequirement(
            enabledLifecycleStates: differences,
            requiresSelection: true,
            allowsReadOnly: false
        )
        let both = Policy.NativeTextEditingApplicability.readOnlyAndEditable
        let editable = Policy.NativeTextEditingApplicability.editable

        return [
            binding(
                "new-command-n",
                .comparison(.newComparison),
                FileLifecycleShortcuts.key(.new),
                FileLifecycleShortcuts.modifiers(.new),
                requirement: PolicyRequirement(enabledLifecycleStates: workspace)
            ),
            binding(
                "open-command-o",
                .comparison(.openComparison),
                FileLifecycleShortcuts.key(.open),
                FileLifecycleShortcuts.modifiers(.open),
                requirement: PolicyRequirement(enabledLifecycleStates: workspace)
            ),
            binding(
                "save-command-s",
                .comparison(.save),
                FileLifecycleShortcuts.key(.save),
                FileLifecycleShortcuts.modifiers(.save),
                requirement: writableWorkspace
            ),
            binding(
                "quit-command-q",
                .quit,
                FileLifecycleShortcuts.key(.quit),
                FileLifecycleShortcuts.modifiers(.quit)
            ),
            binding(
                "close-command-w",
                .close,
                FileLifecycleShortcuts.key(.close),
                FileLifecycleShortcuts.modifiers(.close)
            ),
            binding(
                "undo-command-z", .comparison(.undo), .character("z"), [.command],
                requirement: editableWorkspace
            ),
            binding(
                "redo-command-shift-z", .comparison(.redo), .character("z"), [.command, .shift],
                requirement: editableWorkspace
            ),
            binding(
                "select-line-difference-f4", .comparison(.selectLineDifference), .function(4), [],
                requirement: navigation
            ),
            binding(
                "select-previous-line-difference-shift-f4",
                .comparison(.selectPreviousLineDifference),
                .function(4),
                [.shift],
                requirement: navigation
            ),
            binding(
                "next-difference-f8",
                .comparison(.nextDifference),
                .function(8),
                [],
                requirement: navigation
            ),
            binding(
                "next-difference-option-down",
                .comparison(.nextDifference),
                .special(.downArrow),
                [.option],
                winMergeKey: "down",
                requirement: navigation,
                reservation: NativeReservationRequirement(
                    command: .moveParagraphDown,
                    applicability: both
                )
            ),
            binding(
                "previous-difference-f7",
                .comparison(.previousDifference),
                .function(7),
                [],
                requirement: navigation
            ),
            binding(
                "previous-difference-option-up",
                .comparison(.previousDifference),
                .special(.upArrow),
                [.option],
                winMergeKey: "up",
                requirement: navigation,
                reservation: NativeReservationRequirement(
                    command: .moveParagraphUp,
                    applicability: both
                )
            ),
            binding(
                "next-conflict-shift-f8", .comparison(.nextConflict), .function(8), [.shift],
                requirement: navigation
            ),
            binding(
                "next-conflict-option-shift-down",
                .comparison(.nextConflict),
                .special(.downArrow),
                [.option, .shift],
                requirement: navigation
            ),
            binding(
                "previous-conflict-shift-f7",
                .comparison(.previousConflict),
                .function(7),
                [.shift],
                requirement: navigation
            ),
            binding(
                "previous-conflict-option-shift-up",
                .comparison(.previousConflict),
                .special(.upArrow),
                [.option, .shift],
                requirement: navigation
            ),
            binding(
                "first-difference-option-home",
                .comparison(.firstDifference),
                .special(.home),
                [.option],
                winMergeKey: "home",
                requirement: navigation,
                reservation: NativeReservationRequirement(
                    command: .moveBackwardToParagraphStart,
                    applicability: both
                )
            ),
            binding(
                "current-difference-option-return",
                .comparison(.currentDifference),
                .special(.return),
                [.option],
                winMergeKey: "return",
                requirement: navigation,
                reservation: NativeReservationRequirement(
                    command: .insertNewlineIgnoringFieldEditor,
                    applicability: editable
                )
            ),
            binding(
                "last-difference-option-end",
                .comparison(.lastDifference),
                .special(.end),
                [.option],
                winMergeKey: "end",
                requirement: navigation,
                reservation: NativeReservationRequirement(
                    command: .moveForwardToParagraphEnd,
                    applicability: both
                )
            ),
            binding(
                "copy-right-option-right",
                .comparison(.copyToRight),
                .special(.rightArrow),
                [.option],
                winMergeKey: "right",
                requirement: copy,
                reservation: NativeReservationRequirement(command: .moveWordRight, applicability: both)
            ),
            binding(
                "copy-left-option-left",
                .comparison(.copyToLeft),
                .special(.leftArrow),
                [.option],
                winMergeKey: "left",
                requirement: copy,
                reservation: NativeReservationRequirement(command: .moveWordLeft, applicability: both)
            ),
            binding(
                "copy-right-advance-command-option-right",
                .comparison(.copyToRightAndAdvance),
                .special(.rightArrow),
                [.command, .option],
                requirement: copy
            ),
            binding(
                "copy-left-advance-command-option-left",
                .comparison(.copyToLeftAndAdvance),
                .special(.leftArrow),
                [.command, .option],
                requirement: copy
            ),
            binding(
                "previous-compared-file-command-f7",
                .comparison(.previousComparedFile),
                .function(7),
                [.command],
                requirement: PolicyRequirement(enabledLifecycleStates: [.equal, .different])
            ),
            binding(
                "next-compared-file-command-f8",
                .comparison(.nextComparedFile),
                .function(8),
                [.command],
                requirement: PolicyRequirement(enabledLifecycleStates: [.equal, .different])
            ),
            binding(
                "reload-command-f5",
                .comparison(.reloadFromDisk),
                .function(5),
                [.command],
                requirement: PolicyRequirement(enabledLifecycleStates: [.equal, .different])
            ),
            binding(
                "refresh-f5", .comparison(.refresh), .function(5), [],
                requirement: PolicyRequirement(enabledLifecycleStates: [.equal, .different, .failed])
            ),
            binding(
                "change-pane-f6", .comparison(.changePane), .function(6), [],
                requirement: PolicyRequirement(enabledLifecycleStates: [.equal, .different])
            ),
            binding(
                "change-pane-back-shift-f6", .comparison(.changePaneBack), .function(6), [.shift],
                requirement: PolicyRequirement(enabledLifecycleStates: [.equal, .different])
            ),
            binding(
                "merge-mode-f9", .comparison(.mergeMode), .function(9), [],
                requirement: PolicyRequirement(enabledLifecycleStates: [.equal, .different])
            ),
            binding(
                "options-command-comma", .comparison(.options), .character(","), [.command],
                requirement: PolicyRequirement(
                    enabledLifecycleStates: Set(Policy.LifecycleState.allCases)
                )
            )
        ]
    }

    private static func binding(
        _ id: String,
        _ command: ApplicationCommand,
        _ key: Policy.Key,
        _ modifiers: Set<Policy.Modifier>,
        winMergeKey: String? = nil,
        requirement: PolicyRequirement? = nil,
        reservation: NativeReservationRequirement? = nil
    ) -> Binding {
        let chord = try! Policy.Chord(key, modifiers: modifiers)
        let shortcut = MenuShortcutDescriptor(
            platform: .macOS,
            key: menuKey(for: key),
            modifiers: menuModifiers(for: modifiers)
        )
        let reference = winMergeKey.map {
            MenuShortcutDescriptor(platform: .windows, key: $0, modifiers: [.alt])
        }
        let targetAction = MenuTargetAction(
            targetID: MenuValidationTargetID(rawValue: "macmerge.application"),
            actionID: MenuValidationActionID(rawValue: command.identity)
        )
        let expectedResultID = MenuValidationResultID(rawValue: "result.\(command.identity).completed")
        let policyReservations = Policy.standardNativeTextEditingReservations.filter {
            $0.chord == chord
        }
        precondition(policyReservations.count <= 1)
        let effectiveReservation =
            reservation
            ?? policyReservations.first.map(NativeReservationRequirement.init)
        return Binding(
            id: StableID(rawValue: id),
            command: command,
            shortcut: shortcut,
            policyChord: chord,
            winMergeReference: reference,
            policyRequirement: requirement,
            focusedEditorReservation: effectiveReservation,
            invocationTargetAction: targetAction,
            expectedResultID: expectedResultID
        )
    }

    private static func makeCanonicalNativeBindings() -> [NativeBinding] {
        var occurrences: [String: Int] = [:]
        return Policy.standardNativeTextEditingReservations.map { reservation in
            let identity = shortcutCoverageReservationIdentity(reservation)
            let discriminator = shortcutCoverageOpaqueID(identity)
            let occurrence = occurrences[discriminator, default: 0]
            occurrences[discriminator] = occurrence + 1
            let commandIdentity = "native.\(reservation.command.rawValue)"
            return NativeBinding(
                id: StableID(rawValue: "native.\(discriminator).\(occurrence)"),
                shortcut: MenuShortcutDescriptor(
                    platform: .macOS,
                    key: menuKey(for: reservation.chord.key),
                    modifiers: menuModifiers(for: reservation.chord.modifiers)
                ),
                policyChord: reservation.chord,
                reservation: NativeReservationRequirement(reservation),
                invocationTargetAction: MenuTargetAction(
                    targetID: MenuValidationTargetID(rawValue: "macos.native-text-editor"),
                    actionID: MenuValidationActionID(rawValue: commandIdentity)
                ),
                expectedResultID: MenuValidationResultID(
                    rawValue: "result.\(commandIdentity).completed"
                )
            )
        }
    }

    private static func menuKey(for key: Policy.Key) -> String {
        switch key {
        case .character(let character): String(character)
        case .function(let number): "f\(number)"
        case .special(let key):
            switch key {
            case .backspace: "backspace"
            case .delete: "delete"
            case .downArrow: "down"
            case .end: "end"
            case .escape: "escape"
            case .home: "home"
            case .leftArrow: "left"
            case .pageDown: "pagedown"
            case .pageUp: "pageup"
            case .return: "return"
            case .rightArrow: "right"
            case .space: "space"
            case .tab: "tab"
            case .upArrow: "up"
            }
        }
    }

    private static func menuModifiers(
        for modifiers: Set<Policy.Modifier>
    ) -> Set<MenuShortcutModifier> {
        Set(
            modifiers.map { modifier in
                switch modifier {
                case .command: .command
                case .control: .control
                case .option: .option
                case .shift: .shift
                case .function: .function
                }
            })
    }

    private static func nativeTargetAction(
        for command: Policy.NativeTextEditingCommand
    ) -> MenuTargetAction {
        MenuTargetAction(
            targetID: MenuValidationTargetID(rawValue: "macos.native-text-editor"),
            actionID: MenuValidationActionID(rawValue: "native.\(command.rawValue)")
        )
    }

    private static func nativeResultID(
        for command: Policy.NativeTextEditingCommand
    ) -> MenuValidationResultID {
        MenuValidationResultID(rawValue: "result.native.\(command.rawValue).completed")
    }

    private static func makeCanonicalContexts() -> [InvocationContext] {
        let empty = ComparisonCommandState.Context()
        let loading = comparisonContext(lifecycle: .loading)
        let selected = comparisonContext(hasSelection: true)
        let dirty = comparisonContext(isDirty: true)
        let textFocused = comparisonContext(isDirty: true, hasSelection: true)
        let textFocusedClean = comparisonContext()
        let disabled = comparisonContext(hasSelection: true, isSessionLocked: true)
        let equal = comparisonContext(hasDifferences: false)
        let failed = comparisonContext(lifecycle: .failed, hasDifferences: false)
        let readOnly = comparisonContext(hasSelection: true, isEditable: false)
        let directionalLeft = comparisonContext(hasSelection: true, activePane: .left)
        let directionalRight = comparisonContext(hasSelection: true, activePane: .right)
        let leftDestinationReadOnly = comparisonContext(
            hasSelection: true,
            leftEditable: false,
            rightEditable: true,
            activePane: .right
        )
        let rightDestinationReadOnly = comparisonContext(
            hasSelection: true,
            leftEditable: true,
            rightEditable: false,
            activePane: .left
        )
        let leftDestinationUnloaded = comparisonContext(
            hasSelection: true,
            leftLoaded: false,
            rightLoaded: true,
            activePane: .right
        )
        let rightDestinationUnloaded = comparisonContext(
            hasSelection: true,
            leftLoaded: true,
            rightLoaded: false,
            activePane: .left
        )
        let lineSelectionUnavailable = comparisonContext(
            hasSelection: true,
            canSelectLineDifference: false
        )
        let currentDifferenceUnavailable = comparisonContext(
            hasSelection: true,
            canSelectCurrentDifference: false
        )
        let changePaneUnavailable = comparisonContext(hasSelection: true, canChangePane: false)
        let changePaneBackUnavailable = comparisonContext(
            hasSelection: true,
            canChangePaneBack: false
        )
        let navigationAtStart = comparisonContext(
            hasSelection: true,
            canNavigatePrevious: false,
            canNavigateNext: true
        )
        let navigationAtEnd = comparisonContext(
            hasSelection: true,
            canNavigatePrevious: true,
            canNavigateNext: false
        )
        let refreshing = comparisonContext(lifecycle: .refreshing)
        let stale = comparisonContext(lifecycle: .stale)
        let canceled = comparisonContext(lifecycle: .canceled)
        let undoEnabled = comparisonContext(canUndo: true)
        let redoEnabled = comparisonContext(canRedo: true)
        let differencePreviousOnly = comparisonContext(
            hasSelection: true,
            canDifferencePrevious: true,
            canDifferenceNext: false
        )
        let differenceNextOnly = comparisonContext(
            hasSelection: true,
            canDifferencePrevious: false,
            canDifferenceNext: true
        )
        let conflictPreviousOnly = comparisonContext(
            hasSelection: true,
            canConflictPrevious: true,
            canConflictNext: false
        )
        let conflictNextOnly = comparisonContext(
            hasSelection: true,
            canConflictPrevious: false,
            canConflictNext: true
        )
        let comparedFilePreviousOnly = comparisonContext(
            canComparedFilePrevious: true,
            canComparedFileNext: false
        )
        let comparedFileNextOnly = comparisonContext(
            canComparedFilePrevious: false,
            canComparedFileNext: true
        )

        return [
            invocationContext(
                .empty,
                commandState: empty,
                lifecycle: .empty,
                systemEnabled: true
            ),
            invocationContext(
                .disabled,
                commandState: disabled,
                lifecycle: .different,
                systemEnabled: false
            ),
            invocationContext(
                .loading,
                commandState: loading,
                lifecycle: .loading,
                systemEnabled: true
            ),
            invocationContext(
                .selected,
                commandState: selected,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .dirty,
                commandState: dirty,
                lifecycle: .different,
                isDirty: true,
                systemEnabled: true
            ),
            invocationContext(
                .textFocused,
                commandState: textFocused,
                lifecycle: .different,
                isDirty: true,
                hasSelection: true,
                editorFocus: .editable,
                systemEnabled: true
            ),
            invocationContext(
                .textFocusedClean,
                commandState: textFocusedClean,
                lifecycle: .different,
                editorFocus: .editable,
                systemEnabled: true
            ),
            invocationContext(
                .equal,
                commandState: equal,
                lifecycle: .equal,
                systemEnabled: true
            ),
            invocationContext(
                .failed,
                commandState: failed,
                lifecycle: .failed,
                systemEnabled: true
            ),
            invocationContext(
                .readOnly,
                commandState: readOnly,
                lifecycle: .different,
                hasSelection: true,
                isReadOnly: true,
                systemEnabled: true
            ),
            invocationContext(
                .editorReadOnly,
                commandState: readOnly,
                lifecycle: .different,
                hasSelection: true,
                isReadOnly: true,
                editorFocus: .readOnly,
                systemEnabled: true
            ),
            invocationContext(
                .directionalLeft,
                commandState: directionalLeft,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .directionalRight,
                commandState: directionalRight,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .leftDestinationReadOnly,
                commandState: leftDestinationReadOnly,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .rightDestinationReadOnly,
                commandState: rightDestinationReadOnly,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .leftDestinationUnloaded,
                commandState: leftDestinationUnloaded,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .rightDestinationUnloaded,
                commandState: rightDestinationUnloaded,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .lineSelectionUnavailable,
                commandState: lineSelectionUnavailable,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .currentDifferenceUnavailable,
                commandState: currentDifferenceUnavailable,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .changePaneUnavailable,
                commandState: changePaneUnavailable,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .changePaneBackUnavailable,
                commandState: changePaneBackUnavailable,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .navigationAtStart,
                commandState: navigationAtStart,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .navigationAtEnd,
                commandState: navigationAtEnd,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .refreshing,
                commandState: refreshing,
                lifecycle: .loading,
                systemEnabled: true
            ),
            invocationContext(
                .stale,
                commandState: stale,
                lifecycle: .failed,
                systemEnabled: true
            ),
            invocationContext(
                .canceled,
                commandState: canceled,
                lifecycle: .failed,
                systemEnabled: true
            ),
            invocationContext(
                .undoEnabled,
                commandState: undoEnabled,
                lifecycle: .different,
                systemEnabled: true
            ),
            invocationContext(
                .redoEnabled,
                commandState: redoEnabled,
                lifecycle: .different,
                systemEnabled: true
            ),
            invocationContext(
                .differencePreviousOnly,
                commandState: differencePreviousOnly,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .differenceNextOnly,
                commandState: differenceNextOnly,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .conflictPreviousOnly,
                commandState: conflictPreviousOnly,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .conflictNextOnly,
                commandState: conflictNextOnly,
                lifecycle: .different,
                hasSelection: true,
                systemEnabled: true
            ),
            invocationContext(
                .comparedFilePreviousOnly,
                commandState: comparedFilePreviousOnly,
                lifecycle: .different,
                systemEnabled: true
            ),
            invocationContext(
                .comparedFileNextOnly,
                commandState: comparedFileNextOnly,
                lifecycle: .different,
                systemEnabled: true
            )
        ]
    }

    private static func comparisonContext(
        lifecycle: ComparisonCommandState.ComparisonLifecycle = .currentSuccess,
        isDirty: Bool = false,
        hasSelection: Bool = false,
        isEditable: Bool = true,
        leftLoaded: Bool = true,
        rightLoaded: Bool = true,
        leftEditable: Bool? = nil,
        rightEditable: Bool? = nil,
        hasDifferences: Bool = true,
        activePane: MergeCommandPolicy.Side = .left,
        canNavigatePrevious: Bool = true,
        canNavigateNext: Bool = true,
        canDifferencePrevious: Bool? = nil,
        canDifferenceNext: Bool? = nil,
        canConflictPrevious: Bool? = nil,
        canConflictNext: Bool? = nil,
        canComparedFilePrevious: Bool? = nil,
        canComparedFileNext: Bool? = nil,
        canSelectLineDifference: Bool = true,
        canSelectCurrentDifference: Bool = true,
        canChangePane: Bool = true,
        canChangePaneBack: Bool = true,
        canUndo: Bool = false,
        canRedo: Bool = false,
        isSessionLocked: Bool = false
    ) -> ComparisonCommandState.Context {
        let differencePrevious = canDifferencePrevious ?? canNavigatePrevious
        let differenceNext = canDifferenceNext ?? canNavigateNext
        let conflictPrevious = canConflictPrevious ?? canNavigatePrevious
        let conflictNext = canConflictNext ?? canNavigateNext
        let comparedFilePrevious = canComparedFilePrevious ?? canNavigatePrevious
        let comparedFileNext = canComparedFileNext ?? canNavigateNext
        let left = ComparisonCommandState.PaneState(
            isLoaded: leftLoaded,
            isEditable: leftEditable ?? isEditable,
            isDirty: leftLoaded && isDirty
        )
        let right = ComparisonCommandState.PaneState(
            isLoaded: rightLoaded,
            isEditable: rightEditable ?? isEditable
        )
        let navigation = ComparisonCommandState.DifferenceNavigation(
            canSelectLineDifference: canSelectLineDifference,
            canSelectPreviousLineDifference: differencePrevious,
            canSelectNextDifference: differenceNext,
            canSelectPreviousDifference: differencePrevious,
            canSelectFirstDifference: differencePrevious,
            canSelectCurrentDifference: canSelectCurrentDifference,
            canSelectLastDifference: differenceNext
        )
        let layoutContext = try! ComparisonCommandState.LayoutContext(
            visualOrder: [.left, .right],
            activePane: activePane
        )
        return ComparisonCommandState.Context(
            left: left,
            right: right,
            layoutContext: layoutContext,
            lifecycle: lifecycle,
            hasSelection: hasSelection,
            hasSignificantDifferences: hasDifferences,
            canUndo: canUndo,
            canRedo: canRedo,
            differenceNavigation: navigation,
            conflictNavigation: ComparisonCommandState.ConflictNavigationState(
                isSupported: true,
                hasConflicts: hasDifferences,
                canSelectFirstConflict: conflictPrevious,
                canSelectNextConflict: conflictNext,
                canSelectPreviousConflict: conflictPrevious,
                canSelectCurrentConflict: hasDifferences,
                canSelectLastConflict: conflictNext
            ),
            comparedFileNavigation: ComparisonCommandState.ComparedFileNavigation(
                isSupported: true,
                canSelectFirst: comparedFilePrevious,
                canSelectPrevious: comparedFilePrevious,
                canSelectNext: comparedFileNext,
                canSelectLast: comparedFileNext
            ),
            canChangePane: canChangePane,
            canChangePaneBack: canChangePaneBack,
            isSessionLocked: isSessionLocked
        )
    }

    private static func invocationContext(
        _ id: ContextID,
        commandState: ComparisonCommandState.Context,
        lifecycle: Policy.LifecycleState,
        isDirty: Bool = false,
        hasSelection: Bool = false,
        isReadOnly: Bool = false,
        editorFocus: Policy.EditorFocus = .none,
        systemEnabled: Bool
    ) -> InvocationContext {
        let enabledCommands = expectedEnabledCommands(for: id)
        return InvocationContext(
            contextID: id,
            commandState: commandState,
            keyboardState: Policy.Context(
                lifecycle: lifecycle,
                isDirty: isDirty,
                hasSelection: hasSelection,
                isReadOnly: isReadOnly,
                editorFocus: editorFocus,
                enabledCommands: enabledCommands
            ),
            systemCommandsEnabled: systemEnabled
        )
    }

    private static func expectedEnabledCommands(for context: ContextID) -> Set<ComparisonCommand> {
        let workspace: Set<ComparisonCommand> = [.newComparison, .openComparison]
        let staticCommands: Set<ComparisonCommand> = [.mergeMode, .options]
        let loaded: Set<ComparisonCommand> = [
            .reloadFromDisk, .refresh, .changePane, .changePaneBack,
            .previousComparedFile, .nextComparedFile
        ]
        let difference: Set<ComparisonCommand> = [
            .selectLineDifference, .selectPreviousLineDifference,
            .nextDifference, .previousDifference,
            .firstDifference, .currentDifference, .lastDifference
        ]
        let conflict: Set<ComparisonCommand> = [.nextConflict, .previousConflict]
        let copy: Set<ComparisonCommand> = [
            .copyToRight, .copyToLeft, .copyToRightAndAdvance, .copyToLeftAndAdvance
        ]
        let current = workspace.union(staticCommands).union(loaded).union(difference).union(conflict)
        switch context {
        case .empty: return workspace.union(staticCommands)
        case .disabled: return staticCommands
        case .loading, .refreshing: return staticCommands
        case .equal: return workspace.union(staticCommands).union(loaded)
        case .failed, .stale, .canceled: return workspace.union(staticCommands).union(loaded)
        case .selected, .textFocused, .directionalLeft, .directionalRight:
            return current.union(copy).union(context == .textFocused ? [.save] : [])
        case .textFocusedClean:
            return current
        case .leftDestinationReadOnly, .leftDestinationUnloaded:
            if context == .leftDestinationUnloaded {
                return workspace.union(staticCommands).union([
                    .reloadFromDisk, .previousComparedFile, .nextComparedFile
                ])
            }
            return current.union(copy).subtracting([.copyToLeft, .copyToLeftAndAdvance])
        case .rightDestinationReadOnly, .rightDestinationUnloaded:
            if context == .rightDestinationUnloaded {
                return workspace.union(staticCommands).union([
                    .reloadFromDisk, .previousComparedFile, .nextComparedFile
                ])
            }
            return current.union(copy).subtracting([.copyToRight, .copyToRightAndAdvance])
        case .lineSelectionUnavailable:
            return current.union(copy).subtracting([.selectLineDifference])
        case .currentDifferenceUnavailable:
            return current.union(copy).subtracting([.currentDifference])
        case .changePaneUnavailable:
            return current.union(copy).subtracting([.changePane])
        case .changePaneBackUnavailable:
            return current.union(copy).subtracting([.changePaneBack])
        case .dirty: return current.union([.save])
        case .readOnly, .editorReadOnly: return current
        case .navigationAtStart, .differenceNextOnly:
            let disabled: Set<ComparisonCommand> = [
                .selectPreviousLineDifference, .previousDifference, .firstDifference
            ]
            if context == .navigationAtStart {
                return current.union(copy).subtracting(
                    disabled.union([.previousConflict, .previousComparedFile])
                )
            }
            return current.union(copy).subtracting(disabled)
        case .navigationAtEnd, .differencePreviousOnly:
            let disabled: Set<ComparisonCommand> = [.nextDifference, .lastDifference]
            if context == .navigationAtEnd {
                return current.union(copy).subtracting(
                    disabled.union([.nextConflict, .nextComparedFile])
                )
            }
            return current.union(copy).subtracting(disabled)
        case .conflictPreviousOnly:
            return current.union(copy).subtracting([.nextConflict])
        case .conflictNextOnly:
            return current.union(copy).subtracting([.previousConflict])
        case .comparedFilePreviousOnly:
            return current.subtracting([.nextComparedFile])
        case .comparedFileNextOnly:
            return current.subtracting([.previousComparedFile])
        case .undoEnabled: return current.union([.undo])
        case .redoEnabled: return current.union([.redo])
        }
    }

    private static func makeCanonicalMatrix(
        budget: inout WorkBudget,
        cancellationCheck: @escaping CancellationCheck
    ) throws -> [Expectation] {
        var result: [Expectation] = []
        result.reserveCapacity(
            (Inventory.canonical.bindings.count + Inventory.canonical.nativeBindings.count)
                * requiredContexts.count
        )
        for binding in Inventory.canonical.bindings {
            for context in requiredContexts {
                try budget.consume()
                if cancellationCheck() { throw AuditError.cancelled }
                result.append(
                    Expectation(
                        key: MatrixKey(bindingID: binding.id, contextID: context.id),
                        outcome: expectedOutcome(for: binding, in: context)
                    )
                )
            }
        }
        let applicationBindingsByChord = Dictionary(
            grouping: Inventory.canonical.bindings,
            by: \.policyChord
        )
        for binding in Inventory.canonical.nativeBindings {
            for context in requiredContexts {
                try budget.consume()
                if cancellationCheck() { throw AuditError.cancelled }
                let applicationBinding = applicationBindingsByChord[binding.policyChord]?.first
                result.append(
                    Expectation(
                        key: MatrixKey(bindingID: binding.id, contextID: context.id),
                        outcome: expectedOutcome(
                            for: binding,
                            applicationBinding: applicationBinding,
                            in: context
                        )
                    )
                )
            }
        }
        return result
    }

    private static func expectedOutcome(
        for binding: NativeBinding,
        applicationBinding: Binding?,
        in context: InvocationContext
    ) -> Outcome {
        if reservationApplies(binding.reservation.applicability, to: context.keyboardState.editorFocus) {
            return Outcome(
                owner: .nativeTextEditor,
                command: .nativeTextEditing(binding.reservation.command),
                isEnabled: true,
                invocation: .invoked
            )
        }
        if let applicationBinding {
            return expectedOutcome(for: applicationBinding, in: context)
        }
        return Outcome(owner: .none, command: nil, isEnabled: false, invocation: .unhandled)
    }

    private static func expectedOutcome(
        for binding: Binding,
        in context: InvocationContext
    ) -> Outcome {
        switch binding.command {
        case .quit, .close:
            return Outcome(
                owner: .application,
                command: .application(binding.command),
                isEnabled: context.systemCommandsEnabled,
                invocation: context.systemCommandsEnabled ? .invoked : .blocked
            )
        case .comparison(let command):
            if let reservation = binding.focusedEditorReservation,
                reservationApplies(reservation.applicability, to: context.keyboardState.editorFocus)
            {
                return Outcome(
                    owner: .nativeTextEditor,
                    command: .nativeTextEditing(reservation.command),
                    isEnabled: true,
                    invocation: .invoked
                )
            }
            let requirementAllowsCommand: Bool
            if let requirement = binding.policyRequirement {
                requirementAllowsCommand =
                    requirement.enabledLifecycleStates.contains(context.keyboardState.lifecycle)
                    && (!requirement.requiresDirty || context.keyboardState.isDirty)
                    && (!requirement.requiresSelection || context.keyboardState.hasSelection)
                    && (requirement.allowsReadOnly || !context.keyboardState.isReadOnly)
            } else {
                requirementAllowsCommand = true
            }
            let commandStateAllowsCommand =
                context.keyboardState.enabledCommands?.contains(command) ?? true
            let isEnabled = requirementAllowsCommand && commandStateAllowsCommand
            return Outcome(
                owner: .application,
                command: .application(binding.command),
                isEnabled: isEnabled,
                invocation: isEnabled ? .invoked : .blocked
            )
        }
    }

    private static func reservationApplies(
        _ applicability: Policy.NativeTextEditingApplicability,
        to focus: Policy.EditorFocus
    ) -> Bool {
        switch (applicability, focus) {
        case (.readOnlyAndEditable, .readOnly), (.readOnlyAndEditable, .editable),
            (.readOnly, .readOnly), (.editable, .editable):
            true
        case (_, .none), (.readOnly, .editable), (.editable, .readOnly):
            false
        }
    }

    private static func outcome(for resolution: Policy.Resolution, binding: Binding) -> Outcome {
        switch resolution.route {
        case .applicationCommand(let command):
            return Outcome(
                owner: .application,
                command: .application(.comparison(command)),
                isEnabled: resolution.isEnabled,
                invocation: resolution.isEnabled ? .invoked : .blocked
            )
        case .nativeTextEditing(let command):
            return Outcome(
                owner: .nativeTextEditor,
                command: .nativeTextEditing(command),
                isEnabled: resolution.isEnabled,
                invocation: resolution.isEnabled ? .invoked : .blocked
            )
        case .blocked:
            return Outcome(
                owner: .application,
                command: .application(binding.command),
                isEnabled: false,
                invocation: .blocked
            )
        case .unhandled:
            return Outcome(
                owner: .none,
                command: nil,
                isEnabled: false,
                invocation: .unhandled
            )
        }
    }

    private static func policyCancellationCheck(
        _ cancellationCheck: @escaping CancellationCheck
    ) -> Policy.CancellationCheck {
        { () throws(KeyboardShortcutPolicyError) in
            if cancellationCheck() { throw KeyboardShortcutPolicyError.cancelled }
        }
    }

    private static func preflight(
        inventory: Inventory,
        evidence: Evidence,
        measurementTrust: MeasurementTrust?,
        limits: Limits,
        budget: inout WorkBudget
    ) throws {
        guard inventory.bindings.count <= limits.maximumBindings,
            inventory.nativeBindings.count <= limits.maximumBindings
        else {
            throw AuditError.countLimitExceeded(.bindings, maximum: limits.maximumBindings)
        }
        guard requiredContexts.count <= limits.maximumContexts else {
            throw AuditError.countLimitExceeded(.contexts, maximum: limits.maximumContexts)
        }
        guard evidence.observations.count <= limits.maximumObservations else {
            throw AuditError.countLimitExceeded(.observations, maximum: limits.maximumObservations)
        }
        if let trust = measurementTrust,
            trust.trustedCollectors.count > limits.maximumTrustedCollectors
        {
            throw AuditError.countLimitExceeded(
                .trustedCollectors,
                maximum: limits.maximumTrustedCollectors
            )
        }
        guard inventory.revision > 0 else {
            throw AuditError.invalidInventory(field: "revision")
        }

        var totalStringBytes = 0
        for binding in inventory.bindings {
            try budget.consume()
            try inspectID(
                binding.id,
                field: "binding.id",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                binding.shortcut.key.rawValue,
                field: "binding.shortcut.key",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                binding.shortcut.canonicalChord,
                field: "binding.shortcut.canonicalChord",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                binding.policyChord.canonicalDescription,
                field: "binding.policyChord",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            if let reference = binding.winMergeReference {
                try inspectString(
                    reference.key.rawValue,
                    field: "binding.winMergeReference.key",
                    limits: limits,
                    totalStringBytes: &totalStringBytes,
                    budget: &budget
                )
                try inspectString(
                    reference.canonicalChord,
                    field: "binding.winMergeReference.canonicalChord",
                    limits: limits,
                    totalStringBytes: &totalStringBytes,
                    budget: &budget
                )
            }
            for (field, value) in [
                ("binding.invocationTargetID", binding.invocationTargetAction.targetID.rawValue),
                ("binding.invocationActionID", binding.invocationTargetAction.actionID.rawValue),
                ("binding.expectedResultID", binding.expectedResultID.rawValue)
            ] {
                try inspectString(
                    value,
                    field: field,
                    limits: limits,
                    totalStringBytes: &totalStringBytes,
                    budget: &budget
                )
                guard shortcutCoverageIsValidID(value) else {
                    throw AuditError.invalidInventory(field: field)
                }
            }
        }
        for binding in inventory.nativeBindings {
            try budget.consume()
            try inspectID(
                binding.id,
                field: "nativeBinding.id",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                binding.shortcut.key.rawValue,
                field: "nativeBinding.shortcut.key",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                binding.shortcut.canonicalChord,
                field: "nativeBinding.shortcut.canonicalChord",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                binding.policyChord.canonicalDescription,
                field: "nativeBinding.policyChord",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            for (field, value) in [
                ("nativeBinding.invocationTargetID", binding.invocationTargetAction.targetID.rawValue),
                ("nativeBinding.invocationActionID", binding.invocationTargetAction.actionID.rawValue),
                ("nativeBinding.expectedResultID", binding.expectedResultID.rawValue)
            ] {
                try inspectString(
                    value,
                    field: field,
                    limits: limits,
                    totalStringBytes: &totalStringBytes,
                    budget: &budget
                )
                guard shortcutCoverageIsValidID(value) else {
                    throw AuditError.invalidInventory(field: field)
                }
            }
        }
        if let trust = measurementTrust {
            try inspectID(
                trust.build.id,
                field: "measurementTrust.build.id",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            guard trust.build.revision > 0,
                trust.executableArtifact.algorithm == .sha256,
                trust.executableArtifact.bytes.count == 32,
                trust.inventoryRevision > 0,
                trust.inventoryArtifact.algorithm == .sha256,
                trust.inventoryArtifact.bytes.count == 32
            else {
                throw AuditError.invalidInventory(field: "measurementTrust")
            }
            var collectors: [RevisionReference] = []
            collectors.reserveCapacity(trust.trustedCollectors.count)
            for collector in trust.trustedCollectors {
                try budget.consume()
                try inspectID(
                    collector.collector.id,
                    field: "measurementTrust.collector.id",
                    limits: limits,
                    totalStringBytes: &totalStringBytes,
                    budget: &budget
                )
                guard collector.collector.revision > 0,
                    collector.signingPublicKey.count == 32
                else {
                    throw AuditError.invalidInventory(field: "measurementTrust.collectors")
                }
                collectors.append(collector.collector)
            }
            let sortedCollectors = try shortcutCoverageBoundedSorted(
                collectors,
                budget: budget
            ) {
                try shortcutCoverageCompareRevisionReferences($0, $1, budget: budget) < 0
            }
            for index in sortedCollectors.indices.dropFirst() {
                guard
                    try shortcutCoverageCompareRevisionReferences(
                        sortedCollectors[index - 1],
                        sortedCollectors[index],
                        budget: budget
                    ) != 0
                else {
                    throw AuditError.invalidInventory(field: "measurementTrust.collectors")
                }
            }
        }
        for observation in evidence.observations {
            try budget.consume()
            guard observation.dispatchTrace.ownershipDecisions.count <= 2,
                observation.dispatchTrace.targetActions.count <= 1,
                observation.dispatchTrace.results.count <= 1
            else {
                throw AuditError.invalidEvidence(field: "observation.dispatchTrace.count")
            }
            try inspectID(
                observation.id,
                field: "observation.id",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectID(
                observation.key.bindingID,
                field: "observation.bindingID",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                observation.shortcut.key.rawValue,
                field: "observation.shortcut.key",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                observation.shortcut.canonicalChord,
                field: "observation.shortcut.canonicalChord",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                observation.dispatchTrace.canonicalChord.canonicalDescription,
                field: "observation.dispatchTrace.canonicalChord",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectID(
                observation.hardwareKeyCapture.inputSourceID,
                field: "observation.inputSourceID",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectString(
                observation.hardwareKeyCapture.charactersIgnoringModifiers,
                field: "observation.charactersIgnoringModifiers",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            try inspectID(
                observation.provenance.sourceID,
                field: "observation.provenance.sourceID",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            if let targetAction = observation.invocationReceipt.targetAction {
                for (field, value) in [
                    ("observation.targetID", targetAction.targetID.rawValue),
                    ("observation.actionID", targetAction.actionID.rawValue)
                ] {
                    try inspectString(
                        value,
                        field: field,
                        limits: limits,
                        totalStringBytes: &totalStringBytes,
                        budget: &budget
                    )
                    guard shortcutCoverageIsValidID(value) else {
                        throw AuditError.invalidEvidence(field: field)
                    }
                }
            }
            try inspectCommandResultComponents(
                observation.invocationReceipt.result,
                field: "observation.result",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
            if let resultID = shortcutCoverageCommandResultID(observation.invocationReceipt.result) {
                guard shortcutCoverageIsValidID(resultID.rawValue) else {
                    throw AuditError.invalidEvidence(field: "observation.resultID")
                }
            }
            for (index, targetAction) in observation.dispatchTrace.targetActions.enumerated() {
                for (field, value) in [
                    ("observation.dispatchTrace.target[\(index)].targetID", targetAction.targetID.rawValue),
                    ("observation.dispatchTrace.target[\(index)].actionID", targetAction.actionID.rawValue)
                ] {
                    try inspectString(
                        value,
                        field: field,
                        limits: limits,
                        totalStringBytes: &totalStringBytes,
                        budget: &budget
                    )
                    guard shortcutCoverageIsValidID(value) else {
                        throw AuditError.invalidEvidence(field: field)
                    }
                }
            }
            for (index, commandResult) in observation.dispatchTrace.results.enumerated() {
                let field = "observation.dispatchTrace.result[\(index)].id"
                try inspectCommandResultComponents(
                    commandResult,
                    field: field,
                    limits: limits,
                    totalStringBytes: &totalStringBytes,
                    budget: &budget
                )
                guard let resultID = shortcutCoverageCommandResultID(commandResult) else { continue }
                guard shortcutCoverageIsValidID(resultID.rawValue) else {
                    throw AuditError.invalidEvidence(field: field)
                }
            }
            if let measurement = observation.provenance.measurement {
                guard measurement.executableArtifact.bytes.count <= 64 else {
                    throw AuditError.invalidEvidence(field: "measurement.executableArtifact")
                }
                guard measurement.measurementArtifact.bytes.count <= 64 else {
                    throw AuditError.invalidEvidence(field: "measurement.measurementArtifact")
                }
                guard measurement.runNonce.count <= 64 else {
                    throw AuditError.invalidEvidence(field: "measurement.runNonce")
                }
                guard measurement.inventoryArtifact.bytes.count <= 64 else {
                    throw AuditError.invalidEvidence(field: "measurement.inventoryArtifact")
                }
                guard measurement.captureSignature.count <= 128 else {
                    throw AuditError.invalidEvidence(field: "measurement.captureSignature")
                }
                for (field, id) in [
                    ("measurement.captureID", measurement.captureID),
                    ("measurement.collector.id", measurement.collector.id),
                    ("measurement.build.id", measurement.build.id)
                ] {
                    try inspectID(
                        id,
                        field: field,
                        limits: limits,
                        totalStringBytes: &totalStringBytes,
                        budget: &budget
                    )
                }
            }
        }
    }

    private static func inspectID(
        _ id: StableID,
        field: String,
        limits: Limits,
        totalStringBytes: inout Int,
        budget: inout WorkBudget
    ) throws {
        try inspectString(
            id.rawValue,
            field: field,
            limits: limits,
            totalStringBytes: &totalStringBytes,
            budget: &budget
        )
        guard shortcutCoverageIsValidID(id.rawValue) else {
            if field.hasPrefix("binding") || field.hasPrefix("nativeBinding")
                || field.hasPrefix("measurementTrust")
            {
                throw AuditError.invalidInventory(field: field)
            }
            throw AuditError.invalidEvidence(field: field)
        }
    }

    private static func inspectString(
        _ value: String,
        field: String,
        limits: Limits,
        totalStringBytes: inout Int,
        budget: inout WorkBudget
    ) throws {
        var byteCount = 0
        for _ in value.utf8 {
            try budget.consume()
            byteCount += 1
            guard byteCount <= limits.maximumStringUTF8Bytes else {
                throw AuditError.stringTooLarge(
                    field: field,
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
        }
        guard totalStringBytes <= limits.maximumTotalStringUTF8Bytes - byteCount else {
            throw AuditError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        totalStringBytes += byteCount
    }

    private static func inspectCommandResultComponents(
        _ result: MenuCommandResult,
        field: String,
        limits: Limits,
        totalStringBytes: inout Int,
        budget: inout WorkBudget
    ) throws {
        var index = 0
        try shortcutCoverageForEachCommandResultComponent(result) { component in
            defer { index += 1 }
            try inspectString(
                component,
                field: "\(field).component[\(index)]",
                limits: limits,
                totalStringBytes: &totalStringBytes,
                budget: &budget
            )
        }
    }

    private static func message(for code: FindingCode) -> String {
        switch code {
        case .duplicateInventoryBinding: "Inventory repeats a stable binding identity."
        case .duplicateInventoryChord: "Inventory assigns one canonical chord more than once."
        case .inventoryRevisionMismatch: "Inventory revision differs from canonical revision."
        case .missingInventoryBinding: "Canonical binding is missing from inventory."
        case .unexpectedInventoryBinding: "Inventory contains a noncanonical binding."
        case .inventoryBindingMismatch: "Inventory binding differs from canonical tuple."
        case .missingPolicyBinding: "Shortcut policy has no required application binding."
        case .duplicatePolicyBinding: "Shortcut policy repeats a required application binding."
        case .unexpectedPolicyBinding: "Shortcut policy has an unexpected binding for a covered command."
        case .policyBindingMismatch: "Shortcut policy conditions differ from canonical binding."
        case .unexpectedPolicyCollision: "Shortcut policy has an unexpected application collision."
        case .collisionMismatch: "Shortcut collision metadata differs from canonical reservation ownership."
        case .missingNativeReservation: "Focused editor reservation is missing."
        case .nativeReservationMismatch: "Focused editor reservation differs from requirement."
        case .unexpectedNativeReservation: "Chord unexpectedly steals focused editor ownership."
        case .commandStateResolutionMismatch:
            "Shared command-state enablement differs from canonical matrix input."
        case .policyResolutionMismatch: "Policy owner, command, or enabled outcome differs from matrix."
        case .staleEvidence: "Evidence inventory revision differs from canonical revision."
        case .duplicateObservationID: "Evidence repeats a stable observation identity."
        case .duplicateObservation: "Matrix coordinate has duplicate evidence."
        case .missingObservation: "Matrix coordinate has no evidence."
        case .unexpectedObservation: "Evidence targets a noncanonical matrix coordinate."
        case .assertionOnlyEvidence: "Assertion-only evidence does not prove production behavior."
        case .invalidMeasuredProvenance: "Measured evidence lacks valid build-bound provenance."
        case .measurementTrustMissing: "Inventory has no production measurement trust anchors."
        case .measuredBuildMismatch: "Measured evidence targets a different production build."
        case .measuredArtifactMismatch: "Measured evidence targets a different executable artifact."
        case .untrustedMeasurementCollector: "Measured evidence came from an untrusted collector."
        case .measurementCaptureUnavailable: "Measured evidence has no resolved canonical capture."
        case .measurementCaptureMismatch: "Measured evidence digest does not bind its observation."
        case .measurementSignatureMismatch: "Measured evidence has invalid collector authentication."
        case .measuredInventoryMismatch: "Measured evidence targets a different shortcut inventory."
        case .hardwareKeyMismatch: "Raw hardware event does not reconstruct the required chord."
        case .dispatchTraceMismatch: "Dispatch trace does not prove complete exclusive ownership."
        case .shortcutMismatch: "Observed shortcut differs from canonical binding."
        case .contextMismatch: "Observed invocation context differs from canonical matrix row."
        case .invocationReceiptMismatch:
            "Observed shortcut source, target/action, or result conflicts with invocation outcome."
        case .outcomeMismatch: "Measured owner, command, enabled state, or invocation differs."
        }
    }
}

extension ShortcutCoverageAudit {
    fileprivate struct AuditContext {
        private enum EvidenceBinding {
            case application(Binding)
            case native(NativeBinding, application: Binding?)

            var shortcut: MenuShortcutDescriptor {
                switch self {
                case .application(let binding): binding.shortcut
                case .native(let binding, _): binding.shortcut
                }
            }

            var policyChord: Policy.Chord {
                switch self {
                case .application(let binding): binding.policyChord
                case .native(let binding, _): binding.policyChord
                }
            }

            var nativeCommand: RoutedCommand? {
                switch self {
                case .application(let binding):
                    binding.focusedEditorReservation.map {
                        .nativeTextEditing($0.command)
                    }
                case .native(let binding, _):
                    .nativeTextEditing(binding.reservation.command)
                }
            }

            var applicationCommand: RoutedCommand? {
                switch self {
                case .application(let binding): .application(binding.command)
                case .native(_, let application): application.map { .application($0.command) }
                }
            }

            func targetAction(for outcome: Outcome) -> MenuTargetAction? {
                switch (self, outcome.command) {
                case (.application(let binding), .application):
                    binding.invocationTargetAction
                case (.application, .nativeTextEditing(let command)):
                    ShortcutCoverageAudit.nativeTargetAction(for: command)
                case (.native(let binding, _), .nativeTextEditing):
                    binding.invocationTargetAction
                case (.native(_, let application), .application):
                    application?.invocationTargetAction
                case (_, nil):
                    nil
                }
            }

            func resultID(for outcome: Outcome) -> MenuValidationResultID? {
                switch (self, outcome.command) {
                case (.application(let binding), .application):
                    binding.expectedResultID
                case (.application, .nativeTextEditing(let command)):
                    ShortcutCoverageAudit.nativeResultID(for: command)
                case (.native(let binding, _), .nativeTextEditing):
                    binding.expectedResultID
                case (.native(_, let application), .application):
                    application?.expectedResultID
                case (_, nil):
                    nil
                }
            }
        }

        let inventory: Inventory
        let policy: Policy
        let evidence: Evidence
        let expectations: [Expectation]
        let measurementTrust: MeasurementTrust?
        let limits: Limits
        var budget: WorkBudget
        let captureResolver: CaptureResolver?
        let cancellationCheck: CancellationCheck
        private var findings: [Finding] = []
        private var findingIDs: Set<Finding.ID> = []
        private var sortedTrustedCollectors: [TrustedCollector] = []
        private var cachedInventoryDigest: ArtifactDigest?

        init(
            inventory: Inventory,
            policy: Policy,
            evidence: Evidence,
            expectations: [Expectation],
            measurementTrust: MeasurementTrust?,
            limits: Limits,
            budget: WorkBudget,
            captureResolver: CaptureResolver?,
            cancellationCheck: @escaping CancellationCheck
        ) {
            self.inventory = inventory
            self.policy = policy
            self.evidence = evidence
            self.expectations = expectations
            self.measurementTrust = measurementTrust
            self.limits = limits
            self.budget = budget
            self.captureResolver = captureResolver
            self.cancellationCheck = cancellationCheck
        }

        mutating func run() throws -> Report {
            if let measurementTrust {
                sortedTrustedCollectors = try boundedSorted(
                    measurementTrust.trustedCollectors,
                    by: trustedCollectorPrecedes
                )
            }
            try inspectInventory()
            try inspectPolicy()
            let matrix = try inspectEvidence()
            return Report(
                formatVersion: reportFormatVersion,
                inventoryRevision: Inventory.canonical.revision,
                matrix: matrix,
                findings: try sortedFindings()
            )
        }

        mutating func receipt(for report: Report) throws -> Receipt {
            var inventoryHasher = FingerprintHasher()
            try inventoryHasher.append(String(inventory.revision), budget: &budget)
            for binding in try sortedBindings(inventory.bindings) {
                try inventoryHasher.append(binding.identityComponents, budget: &budget)
            }
            for binding in try sortedNativeBindings(inventory.nativeBindings) {
                try inventoryHasher.append(binding.identityComponents, budget: &budget)
            }
            var policyHasher = FingerprintHasher()
            for shortcut in try boundedSorted(policy.commandShortcuts, by: policyShortcutPrecedes) {
                try policyHasher.append(shortcutCoveragePolicyIdentity(shortcut), budget: &budget)
            }
            for reservation in try boundedSorted(
                policy.nativeTextEditingReservations,
                by: reservationPrecedes
            ) {
                try policyHasher.append(
                    shortcutCoverageReservationIdentity(reservation),
                    budget: &budget
                )
            }
            for collision in try boundedSorted(policy.collisions, by: collisionPrecedes) {
                try policyHasher.append(shortcutCoverageCollisionIdentity(collision), budget: &budget)
            }
            try policyHasher.append(
                [
                    "policy-limits",
                    String(policy.limits.maximumCommandShortcutCount),
                    String(policy.limits.maximumNativeReservationCount),
                    String(policy.limits.maximumCollisionCount),
                    String(policy.limits.maximumWork),
                    String(policy.limits.cancellationCheckInterval)
                ],
                budget: &budget
            )
            var matrixHasher = FingerprintHasher()
            for context in requiredContexts {
                try matrixHasher.append(context.identityComponents, budget: &budget)
            }
            for expectation in expectations {
                try matrixHasher.append(expectation.key.identityComponents, budget: &budget)
                try matrixHasher.append(expectation.outcome.identityComponents, budget: &budget)
            }
            var evidenceHasher = FingerprintHasher()
            try evidenceHasher.append(String(evidence.inventoryRevision), budget: &budget)
            if let measurementTrust {
                try evidenceHasher.append("measurement-trust-present", budget: &budget)
                try evidenceHasher.append(
                    [
                        measurementTrust.build.id.rawValue,
                        String(measurementTrust.build.revision),
                        measurementTrust.executableArtifact.identity,
                        String(measurementTrust.inventoryRevision),
                        measurementTrust.inventoryArtifact.identity
                    ],
                    budget: &budget
                )
                for collector in sortedTrustedCollectors {
                    try evidenceHasher.append(collector.identityComponents, budget: &budget)
                }
            } else {
                try evidenceHasher.append("measurement-trust-nil", budget: &budget)
            }
            var observationDigests: [ArtifactDigest] = []
            observationDigests.reserveCapacity(evidence.observations.count)
            for observation in evidence.observations {
                var hasher = SHA256()
                for component in observation.identityComponents {
                    try shortcutCoverageHashFramed(component, into: &hasher, budget: budget)
                }
                observationDigests.append(ArtifactDigest(bytes: Array(hasher.finalize())))
            }
            for digest in try boundedSorted(observationDigests, by: digestPrecedes) {
                try evidenceHasher.append(digest.identity, budget: &budget)
            }
            var findingHasher = FingerprintHasher()
            for finding in report.findings {
                try findingHasher.append(finding.id.rawValue, budget: &budget)
            }
            return Receipt(
                formatVersion: reportFormatVersion,
                inventoryRevision: Inventory.canonical.revision,
                inventoryFingerprint: inventoryHasher.finalize(),
                policyFingerprint: policyHasher.finalize(),
                matrixFingerprint: matrixHasher.finalize(),
                evidenceFingerprint: evidenceHasher.finalize(),
                findingFingerprint: findingHasher.finalize(),
                requiredObservationCount: report.matrix.requiredCount,
                completeMeasuredObservationCount: report.matrix.completeCount,
                assertionOnlyObservationCount: evidence.observations.count {
                    !$0.provenance.origin.isMeasured
                },
                findingCount: report.findings.count
            )
        }

        private mutating func inspectInventory() throws {
            if inventory.revision != Inventory.canonical.revision {
                try add(.error, .inventoryRevisionMismatch)
            }
            let canonicalByID = Dictionary(
                uniqueKeysWithValues: Inventory.canonical.bindings.map { ($0.id, $0) }
            )
            var groups: [StableID: [Binding]] = [:]
            for binding in inventory.bindings {
                try budget.consume()
                groups[binding.id, default: []].append(binding)
            }
            for id in try sortedIDs(Array(groups.keys)) {
                guard let bindings = groups[id] else { continue }
                if bindings.count > 1 {
                    try add(
                        .error,
                        .duplicateInventoryBinding,
                        bindingID: id,
                        occurrenceCount: bindings.count
                    )
                }
                guard let canonical = canonicalByID[id] else {
                    try add(.error, .unexpectedInventoryBinding, bindingID: id)
                    continue
                }
                if bindings.contains(where: { $0 != canonical }) {
                    try add(.error, .inventoryBindingMismatch, bindingID: id)
                }
            }
            for binding in Inventory.canonical.bindings where groups[binding.id] == nil {
                try add(.error, .missingInventoryBinding, bindingID: binding.id)
            }
            let canonicalNativeByID = Dictionary(
                uniqueKeysWithValues: Inventory.canonical.nativeBindings.map { ($0.id, $0) }
            )
            var nativeGroups: [StableID: [NativeBinding]] = [:]
            for binding in inventory.nativeBindings {
                try budget.consume()
                nativeGroups[binding.id, default: []].append(binding)
            }
            for id in try sortedIDs(Array(nativeGroups.keys)) {
                guard let bindings = nativeGroups[id] else { continue }
                if bindings.count > 1 {
                    try add(
                        .error,
                        .duplicateInventoryBinding,
                        bindingID: id,
                        occurrenceCount: bindings.count
                    )
                }
                guard let canonical = canonicalNativeByID[id] else {
                    try add(.error, .unexpectedInventoryBinding, bindingID: id)
                    continue
                }
                if bindings.contains(where: { $0 != canonical }) {
                    try add(.error, .inventoryBindingMismatch, bindingID: id)
                }
            }
            for binding in Inventory.canonical.nativeBindings where nativeGroups[binding.id] == nil {
                try add(.error, .missingInventoryBinding, bindingID: binding.id)
            }

            var chordGroups: [String: [Binding]] = [:]
            for binding in inventory.bindings {
                try budget.consume()
                chordGroups[binding.shortcut.canonicalChord, default: []].append(binding)
            }
            let sortedChords = try sortedStrings(Array(chordGroups.keys))
            for chord in sortedChords {
                guard let bindings = chordGroups[chord], bindings.count > 1 else { continue }
                let firstID = try sortedIDs(bindings.map(\.id)).first
                try add(
                    .error,
                    .duplicateInventoryChord,
                    bindingID: firstID,
                    occurrenceCount: bindings.count,
                    discriminator: chord
                )
            }
        }

        private mutating func inspectPolicy() throws {
            let expectedShortcuts = Policy.unfinishedAuditCommandShortcuts
            let shortcutsMatch = try comparePolicyShortcutMultisets(
                expected: expectedShortcuts,
                actual: policy.commandShortcuts
            )
            let expectedReservations = Policy.standardNativeTextEditingReservations
            let reservationsMatch = try compareReservationMultisets(
                expected: expectedReservations,
                actual: policy.nativeTextEditingReservations
            )
            let expectedCollisions: [Policy.Collision]
            do {
                expectedCollisions = try Policy(
                    commandShortcuts: expectedShortcuts,
                    nativeTextEditingReservations: expectedReservations,
                    cancellationCheck: policyCancellationCheck(cancellationCheck)
                ).collisions
            } catch KeyboardShortcutPolicyError.cancelled {
                throw AuditError.cancelled
            } catch KeyboardShortcutPolicyError.workLimitExceeded(let maximum) {
                throw AuditError.workLimitExceeded(maximum: UInt64(maximum))
            } catch {
                throw AuditError.canonicalPolicyUnavailable
            }
            let collisionsMatch = try compareCollisionMultisets(
                expected: expectedCollisions,
                actual: policy.collisions
            )
            let coveredCommands = Set(
                Inventory.canonical.bindings.compactMap { binding -> ComparisonCommand? in
                    guard case .comparison(let command) = binding.command else { return nil }
                    return command
                }
            )
            var shortcutsByChord: [Policy.Chord: [Policy.CommandShortcut]] = [:]
            for shortcut in policy.commandShortcuts {
                try budget.consume()
                shortcutsByChord[shortcut.chord, default: []].append(shortcut)
            }
            var reservationsByChord: [Policy.Chord: [Policy.NativeTextEditingReservation]] = [:]
            for reservation in policy.nativeTextEditingReservations {
                try budget.consume()
                reservationsByChord[reservation.chord, default: []].append(reservation)
            }
            for binding in Inventory.canonical.bindings {
                try budget.consume()
                guard case .comparison(let command) = binding.command,
                    let expectedRequirement = binding.policyRequirement
                else {
                    continue
                }
                let sameChord = shortcutsByChord[binding.policyChord] ?? []
                let matches = sameChord.filter { $0.command == command }
                if matches.isEmpty {
                    try add(.error, .missingPolicyBinding, bindingID: binding.id)
                } else {
                    if matches.count > 1 {
                        try add(
                            .error,
                            .duplicatePolicyBinding,
                            bindingID: binding.id,
                            occurrenceCount: matches.count
                        )
                    }
                    if matches.contains(where: { PolicyRequirement($0) != expectedRequirement }) {
                        try add(.error, .policyBindingMismatch, bindingID: binding.id)
                    }
                }
                let otherCommands = sameChord.filter { $0.command != command }
                if !otherCommands.isEmpty {
                    try add(
                        .error,
                        .unexpectedPolicyCollision,
                        bindingID: binding.id,
                        occurrenceCount: otherCommands.count
                    )
                }

                let reservations = reservationsByChord[binding.policyChord] ?? []
                if let expectedReservation = binding.focusedEditorReservation {
                    let exact = reservations.filter {
                        NativeReservationRequirement($0) == expectedReservation
                    }
                    if exact.isEmpty {
                        try add(.error, .missingNativeReservation, bindingID: binding.id)
                    }
                    if reservations.count != 1 || exact.count != 1 {
                        try add(
                            .error,
                            .nativeReservationMismatch,
                            bindingID: binding.id,
                            occurrenceCount: reservations.count
                        )
                    }
                    let collision = policy.collision(for: binding.policyChord)
                    if collision?.kinds != [.editorFocusReservation]
                        || collision?.commands != [command]
                        || collision?.nativeTextEditingCommands != [expectedReservation.command]
                        || collision?.commandShortcutCount != 1
                        || collision?.nativeReservationCount != 1
                        || collision?.isConditional != true
                    {
                        try add(.error, .collisionMismatch, bindingID: binding.id)
                    }
                } else if !reservations.isEmpty {
                    try add(
                        .error,
                        .unexpectedNativeReservation,
                        bindingID: binding.id,
                        occurrenceCount: reservations.count
                    )
                }
            }

            let expectedCollisionChords = Set(
                Inventory.canonical.bindings.compactMap { binding in
                    binding.focusedEditorReservation == nil ? nil : binding.policyChord
                }
            )
            for collision in policy.collisions
            where collision.commands.contains(where: coveredCommands.contains)
                && !expectedCollisionChords.contains(collision.chord)
            {
                try add(
                    .error,
                    .unexpectedPolicyCollision,
                    discriminator: collision.chord.canonicalDescription
                )
            }

            let applicationBindingsByChord = Dictionary(
                grouping: Inventory.canonical.bindings,
                by: \.policyChord
            )
            var canonicalBindings = Dictionary(
                uniqueKeysWithValues: Inventory.canonical.bindings.map {
                    ($0.id, EvidenceBinding.application($0))
                }
            )
            for binding in Inventory.canonical.nativeBindings {
                canonicalBindings[binding.id] = .native(
                    binding,
                    application: applicationBindingsByChord[binding.policyChord]?.first
                )
            }
            let contexts = Dictionary(uniqueKeysWithValues: requiredContexts.map { ($0.id, $0) })
            for context in requiredContexts {
                for command in coveredCommands {
                    try budget.consume()
                    let expectedEnabled =
                        context.keyboardState.enabledCommands?.contains(command) ?? true
                    if ComparisonCommandState.resolve(command, in: context.commandState).isEnabled
                        != expectedEnabled
                    {
                        try add(
                            .error,
                            .commandStateResolutionMismatch,
                            contextID: context.id,
                            discriminator: command.rawValue
                        )
                    }
                }
            }
            guard shortcutsMatch, reservationsMatch, collisionsMatch else { return }
            for expectation in expectations {
                try budget.consume()
                guard let binding = canonicalBindings[expectation.key.bindingID],
                    let invocationContext = contexts[expectation.key.contextID]
                else {
                    continue
                }
                switch binding {
                case .application(let applicationBinding):
                    guard case .comparison = applicationBinding.command else { continue }
                case .native:
                    break
                }
                let sameChord = shortcutsByChord[binding.policyChord] ?? []
                let sameReservations = reservationsByChord[binding.policyChord] ?? []
                guard sameChord.count <= 1, sameReservations.count <= 1 else {
                    continue
                }
                let resolution: Policy.Resolution
                do {
                    resolution = try policy.resolve(
                        binding.policyChord,
                        in: invocationContext.keyboardState,
                        cancellationCheck: policyCancellationCheck(cancellationCheck)
                    )
                } catch KeyboardShortcutPolicyError.cancelled {
                    throw AuditError.cancelled
                } catch KeyboardShortcutPolicyError.workLimitExceeded(let maximum) {
                    throw AuditError.workLimitExceeded(maximum: UInt64(maximum))
                } catch {
                    throw AuditError.canonicalPolicyUnavailable
                }
                if policyOutcome(for: resolution, binding: binding) != expectation.outcome {
                    try add(
                        .error,
                        .policyResolutionMismatch,
                        bindingID: expectation.key.bindingID,
                        contextID: invocationContext.id
                    )
                }
            }
        }

        private func policyOutcome(
            for resolution: Policy.Resolution,
            binding: EvidenceBinding
        ) -> Outcome {
            switch resolution.route {
            case .applicationCommand(let command):
                return Outcome(
                    owner: .application,
                    command: .application(.comparison(command)),
                    isEnabled: resolution.isEnabled,
                    invocation: resolution.isEnabled ? .invoked : .blocked
                )
            case .nativeTextEditing(let command):
                return Outcome(
                    owner: .nativeTextEditor,
                    command: .nativeTextEditing(command),
                    isEnabled: resolution.isEnabled,
                    invocation: resolution.isEnabled ? .invoked : .blocked
                )
            case .blocked:
                return Outcome(
                    owner: binding.applicationCommand == nil ? .none : .application,
                    command: binding.applicationCommand,
                    isEnabled: false,
                    invocation: .blocked
                )
            case .unhandled:
                return Outcome(owner: .none, command: nil, isEnabled: false, invocation: .unhandled)
            }
        }

        private mutating func comparePolicyShortcutMultisets(
            expected: [Policy.CommandShortcut],
            actual: [Policy.CommandShortcut]
        ) throws -> Bool {
            var expectedCounts: [[String]: Int] = [:]
            var actualCounts: [[String]: Int] = [:]
            for shortcut in expected {
                try budget.consume()
                expectedCounts[shortcutCoveragePolicyIdentity(shortcut), default: 0] += 1
            }
            for shortcut in actual {
                try budget.consume()
                actualCounts[shortcutCoveragePolicyIdentity(shortcut), default: 0] += 1
            }
            let sortBudget = budget
            let identities = try boundedSorted(
                shortcutCoverageHashOrderCanonicalized(
                    Array(Set(expectedCounts.keys).union(actualCounts.keys))
                ) { shortcutCoverageCompareStringArrays($0, $1) < 0 },
                by: {
                    try shortcutCoverageCompareStringArrays($0, $1, budget: sortBudget) < 0
                }
            )
            var matches = true
            for identity in identities {
                let expectedCount = expectedCounts[identity, default: 0]
                let actualCount = actualCounts[identity, default: 0]
                if actualCount < expectedCount {
                    matches = false
                    try add(
                        .error,
                        .missingPolicyBinding,
                        occurrenceCount: expectedCount - actualCount,
                        discriminator: try shortcutCoverageOpaqueID(identity, budget: budget)
                    )
                }
                if actualCount > expectedCount {
                    matches = false
                    try add(
                        .error,
                        .unexpectedPolicyBinding,
                        occurrenceCount: actualCount - expectedCount,
                        discriminator: try shortcutCoverageOpaqueID(identity, budget: budget)
                    )
                }
            }
            return matches
        }

        private mutating func compareReservationMultisets(
            expected: [Policy.NativeTextEditingReservation],
            actual: [Policy.NativeTextEditingReservation]
        ) throws -> Bool {
            var expectedCounts: [[String]: Int] = [:]
            var actualCounts: [[String]: Int] = [:]
            for reservation in expected {
                try budget.consume()
                expectedCounts[shortcutCoverageReservationIdentity(reservation), default: 0] += 1
            }
            for reservation in actual {
                try budget.consume()
                actualCounts[shortcutCoverageReservationIdentity(reservation), default: 0] += 1
            }
            let sortBudget = budget
            let identities = try boundedSorted(
                shortcutCoverageHashOrderCanonicalized(
                    Array(Set(expectedCounts.keys).union(actualCounts.keys))
                ) { shortcutCoverageCompareStringArrays($0, $1) < 0 },
                by: {
                    try shortcutCoverageCompareStringArrays($0, $1, budget: sortBudget) < 0
                }
            )
            var matches = true
            for identity in identities {
                let expectedCount = expectedCounts[identity, default: 0]
                let actualCount = actualCounts[identity, default: 0]
                if actualCount < expectedCount {
                    matches = false
                    try add(
                        .error,
                        .missingNativeReservation,
                        occurrenceCount: expectedCount - actualCount,
                        discriminator: try shortcutCoverageOpaqueID(identity, budget: budget)
                    )
                }
                if actualCount > expectedCount {
                    matches = false
                    try add(
                        .error,
                        .unexpectedNativeReservation,
                        occurrenceCount: actualCount - expectedCount,
                        discriminator: try shortcutCoverageOpaqueID(identity, budget: budget)
                    )
                }
            }
            return matches
        }

        private mutating func compareCollisionMultisets(
            expected: [Policy.Collision],
            actual: [Policy.Collision]
        ) throws -> Bool {
            var expectedCounts: [[String]: Int] = [:]
            var actualCounts: [[String]: Int] = [:]
            for collision in expected {
                try budget.consume()
                expectedCounts[shortcutCoverageCollisionIdentity(collision), default: 0] += 1
            }
            for collision in actual {
                try budget.consume()
                actualCounts[shortcutCoverageCollisionIdentity(collision), default: 0] += 1
            }
            let sortBudget = budget
            let identities = try boundedSorted(
                shortcutCoverageHashOrderCanonicalized(
                    Array(Set(expectedCounts.keys).union(actualCounts.keys))
                ) { shortcutCoverageCompareStringArrays($0, $1) < 0 },
                by: {
                    try shortcutCoverageCompareStringArrays($0, $1, budget: sortBudget) < 0
                }
            )
            var matches = true
            for identity in identities {
                let expectedCount = expectedCounts[identity, default: 0]
                let actualCount = actualCounts[identity, default: 0]
                guard expectedCount != actualCount else { continue }
                matches = false
                try add(
                    .error,
                    actualCount > expectedCount ? .unexpectedPolicyCollision : .collisionMismatch,
                    occurrenceCount: abs(actualCount - expectedCount),
                    discriminator: try shortcutCoverageOpaqueID(identity, budget: budget)
                )
            }
            return matches
        }

        private mutating func inspectEvidence() throws -> Matrix {
            if evidence.inventoryRevision != Inventory.canonical.revision {
                try add(.error, .staleEvidence)
            }
            let expectedByKey = Dictionary(uniqueKeysWithValues: expectations.map { ($0.key, $0) })
            let applicationBindingsByChord = Dictionary(
                grouping: Inventory.canonical.bindings,
                by: \.policyChord
            )
            var canonicalBindings = Dictionary(
                uniqueKeysWithValues: Inventory.canonical.bindings.map {
                    ($0.id, EvidenceBinding.application($0))
                }
            )
            for binding in Inventory.canonical.nativeBindings {
                canonicalBindings[binding.id] = .native(
                    binding,
                    application: applicationBindingsByChord[binding.policyChord]?.first
                )
            }
            let contexts = Dictionary(uniqueKeysWithValues: requiredContexts.map { ($0.id, $0) })
            var observationsByKey: [MatrixKey: [Observation]] = [:]
            var observationsByID: [StableID: [Observation]] = [:]
            for observation in evidence.observations {
                try budget.consume()
                observationsByKey[observation.key, default: []].append(observation)
                observationsByID[observation.id, default: []].append(observation)
            }
            for id in try sortedIDs(Array(observationsByID.keys)) {
                guard let observations = observationsByID[id], observations.count > 1 else {
                    continue
                }
                guard let firstKey = try sortedMatrixKeys(observations.map(\.key)).first else {
                    continue
                }
                try add(
                    .error,
                    .duplicateObservationID,
                    bindingID: firstKey.bindingID,
                    contextID: firstKey.contextID,
                    occurrenceCount: observations.count,
                    discriminator: id.rawValue
                )
            }
            let duplicateIDs = Set(
                observationsByID.compactMap { id, observations in
                    observations.count > 1 ? id : nil
                }
            )
            var cells: [MatrixCell] = []
            cells.reserveCapacity(expectations.count)

            for expectation in expectations {
                try budget.consume()
                let observations = observationsByKey[expectation.key] ?? []
                guard !observations.isEmpty else {
                    try add(
                        .error,
                        .missingObservation,
                        bindingID: expectation.key.bindingID,
                        contextID: expectation.key.contextID
                    )
                    cells.append(
                        MatrixCell(
                            expectation: expectation,
                            observedOutcome: nil,
                            evidenceCount: 0,
                            statuses: [.missing]
                        )
                    )
                    continue
                }
                var statuses: Set<CellStatus> = observations.count > 1 ? [.duplicate] : []
                if observations.contains(where: { duplicateIDs.contains($0.id) }) {
                    statuses.insert(.invalid)
                }
                if observations.count > 1 {
                    try add(
                        .error,
                        .duplicateObservation,
                        bindingID: expectation.key.bindingID,
                        contextID: expectation.key.contextID,
                        occurrenceCount: observations.count
                    )
                }
                var allValid = true
                for observation in observations {
                    try budget.consume()
                    let validation = try validate(
                        observation,
                        expectation: expectation,
                        binding: canonicalBindings[expectation.key.bindingID],
                        context: contexts[expectation.key.contextID],
                        hasDuplicateID: duplicateIDs.contains(observation.id),
                        hasDuplicateCoordinate: observations.count > 1
                    )
                    allValid = allValid && validation.isComplete
                    statuses.formUnion(validation.statuses)
                }
                if statuses.isEmpty { statuses.insert(.complete) }
                cells.append(
                    MatrixCell(
                        expectation: expectation,
                        observedOutcome: allValid ? observations[0].outcome : nil,
                        evidenceCount: observations.count,
                        statuses: statuses
                    )
                )
            }

            for key in try sortedMatrixKeys(Array(observationsByKey.keys)) where expectedByKey[key] == nil {
                try add(
                    .error,
                    .unexpectedObservation,
                    bindingID: key.bindingID,
                    contextID: key.contextID,
                    occurrenceCount: observationsByKey[key]?.count
                )
            }
            return Matrix(cells: cells)
        }

        private struct ObservationValidation {
            var statuses: Set<CellStatus> = []
            var isComplete: Bool { statuses.isEmpty }

            mutating func fail(_ status: CellStatus) {
                statuses.insert(status)
            }
        }

        private mutating func validate(
            _ observation: Observation,
            expectation: Expectation,
            binding: EvidenceBinding?,
            context: InvocationContext?,
            hasDuplicateID: Bool,
            hasDuplicateCoordinate: Bool
        ) throws -> ObservationValidation {
            var result = ObservationValidation()
            if hasDuplicateID { result.fail(.invalid) }
            if hasDuplicateCoordinate { result.fail(.duplicate) }
            if observation.shortcut != binding?.shortcut {
                result.fail(.mismatched)
                try add(
                    .error,
                    .shortcutMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            if observation.context != context {
                result.fail(.mismatched)
                try add(
                    .error,
                    .contextMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            do {
                if try observation.hardwareKeyCapture.canonicalChord() != binding?.policyChord {
                    result.fail(.mismatched)
                    try add(
                        .error,
                        .hardwareKeyMismatch,
                        bindingID: expectation.key.bindingID,
                        contextID: expectation.key.contextID,
                        discriminator: observation.id.rawValue
                    )
                }
            } catch AuditError.cancelled {
                throw AuditError.cancelled
            } catch {
                result.fail(.mismatched)
                try add(
                    .error,
                    .hardwareKeyMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            if !invocationReceiptIsValid(
                observation,
                binding: binding,
                expectedOutcome: expectation.outcome
            ) {
                result.fail(.mismatched)
                try add(
                    .error,
                    .invocationReceiptMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            if !dispatchTraceIsValid(
                observation,
                binding: binding,
                expectedOutcome: expectation.outcome
            ) {
                result.fail(.mismatched)
                try add(
                    .error,
                    .dispatchTraceMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            if observation.outcome != expectation.outcome {
                result.fail(.mismatched)
                try add(
                    .error,
                    .outcomeMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            if !observation.provenance.origin.isMeasured {
                result.fail(.assertionOnly)
                try add(
                    .error,
                    .assertionOnlyEvidence,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            } else {
                try validateMeasuredProvenance(
                    observation,
                    result: &result,
                    expectation: expectation,
                    allowCaptureResolution: result.statuses.isEmpty
                )
            }
            return result
        }

        private func invocationReceiptIsValid(
            _ observation: Observation,
            binding: EvidenceBinding?,
            expectedOutcome: Outcome
        ) -> Bool {
            guard observation.invocationReceipt.source == .keyboardShortcut else { return false }
            switch expectedOutcome.invocation {
            case .invoked:
                guard expectedOutcome.isEnabled,
                    observation.invocationReceipt.targetAction
                        == expectedTargetAction(for: expectedOutcome, binding: binding)
                else {
                    return false
                }
                return observation.invocationReceipt.result
                    == expectedCompletedResult(for: expectedOutcome, binding: binding)
            case .blocked, .unhandled:
                return !expectedOutcome.isEnabled
                    && observation.invocationReceipt.targetAction == nil
                    && observation.invocationReceipt.result == .notInvoked
            case .failed:
                guard expectedOutcome.isEnabled,
                    observation.invocationReceipt.targetAction
                        == expectedTargetAction(for: expectedOutcome, binding: binding)
                else {
                    return false
                }
                guard case .failed(let resultID) = observation.invocationReceipt.result else {
                    return false
                }
                return resultID == expectedResultID(for: expectedOutcome, binding: binding)
            }
        }

        private func dispatchTraceIsValid(
            _ observation: Observation,
            binding: EvidenceBinding?,
            expectedOutcome: Outcome
        ) -> Bool {
            let receiptTargets: [MenuTargetAction]
            if let targetAction = observation.invocationReceipt.targetAction {
                receiptTargets = [targetAction]
            } else {
                receiptTargets = []
            }
            guard let binding,
                observation.dispatchTrace.canonicalChord == binding.policyChord,
                observation.dispatchTrace.targetActions == receiptTargets,
                observation.dispatchTrace.results == [observation.invocationReceipt.result]
            else {
                return false
            }
            let nativeCommand = binding.nativeCommand
            let applicationCommand = binding.applicationCommand
            let expectedDecisions: [OwnershipDecision]
            switch expectedOutcome.owner {
            case .nativeTextEditor:
                guard expectedOutcome.invocation == .invoked else { return false }
                expectedDecisions = [
                    OwnershipDecision(
                        owner: .nativeTextEditor,
                        command: expectedOutcome.command,
                        decision: .claimed
                    ),
                    OwnershipDecision(
                        owner: .application,
                        command: applicationCommand,
                        decision: .declined
                    )
                ]
            case .application:
                let applicationDecision: DispatchDecision
                switch expectedOutcome.invocation {
                case .invoked: applicationDecision = .claimed
                case .blocked, .unhandled: applicationDecision = .blocked
                case .failed: applicationDecision = .failed
                }
                expectedDecisions = [
                    OwnershipDecision(
                        owner: .nativeTextEditor,
                        command: nativeCommand,
                        decision: .declined
                    ),
                    OwnershipDecision(
                        owner: .application,
                        command: applicationCommand,
                        decision: applicationDecision
                    )
                ]
            case .none:
                expectedDecisions = [
                    OwnershipDecision(
                        owner: .nativeTextEditor,
                        command: nativeCommand,
                        decision: .declined
                    ),
                    OwnershipDecision(
                        owner: .application,
                        command: applicationCommand,
                        decision: .declined
                    )
                ]
            }
            return observation.dispatchTrace.ownershipDecisions == expectedDecisions
        }

        private func expectedCompletedResult(
            for outcome: Outcome,
            binding: EvidenceBinding?
        ) -> MenuCommandResult? {
            expectedResultID(for: outcome, binding: binding).map(MenuCommandResult.completed)
        }

        private func expectedResultID(
            for outcome: Outcome,
            binding: EvidenceBinding?
        ) -> MenuValidationResultID? {
            binding?.resultID(for: outcome)
        }

        private func expectedTargetAction(
            for outcome: Outcome,
            binding: EvidenceBinding?
        ) -> MenuTargetAction? {
            binding?.targetAction(for: outcome)
        }

        private mutating func validateMeasuredProvenance(
            _ observation: Observation,
            result: inout ObservationValidation,
            expectation: Expectation,
            allowCaptureResolution: Bool
        ) throws {
            guard isValidMeasuredProvenance(observation.provenance),
                let measurement = observation.provenance.measurement
            else {
                result.fail(.invalid)
                try add(
                    .error,
                    .invalidMeasuredProvenance,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
                return
            }
            guard measurement.captureID == observation.id else {
                result.fail(.invalid)
                try add(
                    .error,
                    .invalidMeasuredProvenance,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
                return
            }
            guard let trust = measurementTrust else {
                result.fail(.invalid)
                try add(
                    .error,
                    .measurementTrustMissing,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
                return
            }
            var evidenceIsTrusted = true
            if measurement.build != trust.build {
                evidenceIsTrusted = false
                result.fail(.invalid)
                try add(
                    .error,
                    .measuredBuildMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            if measurement.executableArtifact != trust.executableArtifact {
                evidenceIsTrusted = false
                result.fail(.invalid)
                try add(
                    .error,
                    .measuredArtifactMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            let trustedCollector = try trustedCollector(for: measurement.collector)
            if trustedCollector == nil {
                evidenceIsTrusted = false
                result.fail(.invalid)
                try add(
                    .error,
                    .untrustedMeasurementCollector,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            let trustedInventoryArtifact = try inventoryDigest()
            if trust.inventoryRevision != Inventory.canonical.revision
                || trust.inventoryArtifact != trustedInventoryArtifact
                || measurement.inventoryRevision != trust.inventoryRevision
                || measurement.inventoryArtifact != trust.inventoryArtifact
            {
                evidenceIsTrusted = false
                result.fail(.invalid)
                try add(
                    .error,
                    .measuredInventoryMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
            guard evidenceIsTrusted else { return }
            let expectedCapture = try ShortcutCoverageAudit.canonicalCaptureData(
                for: observation,
                maximumBytes: limits.maximumCaptureBytes,
                cancellationCheck: cancellationCheck,
                budget: budget
            )
            guard
                try shortcutCoverageDigest(expectedCapture, budget: budget)
                    == measurement.measurementArtifact
            else {
                result.fail(.invalid)
                try add(
                    .error,
                    .measurementCaptureMismatch,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
                return
            }
            if let trustedCollector {
                let signatureData = try authenticationData(for: observation)
                try budget.consume(UInt64(signatureData.count))
                let signatureIsValid =
                    (try? Curve25519.Signing.PublicKey(
                        rawRepresentation: Data(trustedCollector.signingPublicKey)
                    ).isValidSignature(
                        Data(measurement.captureSignature),
                        for: signatureData
                    )) == true
                if !signatureIsValid {
                    evidenceIsTrusted = false
                    result.fail(.invalid)
                    try add(
                        .error,
                        .measurementSignatureMismatch,
                        bindingID: expectation.key.bindingID,
                        contextID: expectation.key.contextID,
                        discriminator: observation.id.rawValue
                    )
                }
            }
            guard evidenceIsTrusted else { return }
            guard allowCaptureResolution else { return }
            guard let captureResolver else {
                result.fail(.invalid)
                try add(
                    .error,
                    .measurementCaptureUnavailable,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
                return
            }
            do {
                try budget.checkCancellation()
                let stream = CaptureStream(
                    expected: expectedCapture,
                    maximumByteCount: expectedCapture.count,
                    cancellationCheck: cancellationCheck,
                    budget: budget
                )
                do {
                    try captureResolver(
                        measurement.measurementArtifact,
                        expectedCapture.count,
                        cancellationCheck,
                        stream
                    )
                } catch {
                    if error is CancellationError || error as? AuditError == .cancelled
                        || cancellationCheck()
                    {
                        throw AuditError.cancelled
                    }
                    if let streamFailure = stream.recordedFailure() {
                        throw streamFailure
                    }
                    throw CaptureResolutionError.unavailable
                }
                let capture = try stream.finish()
                guard capture.matches,
                    capture.digest == measurement.measurementArtifact
                else {
                    throw AuditError.invalidEvidence(field: "measurement.capture")
                }
            } catch let error as AuditError {
                switch error {
                case .invalidEvidence(field: "measurement.capture"), .captureTooLarge:
                    result.fail(.invalid)
                    try add(
                        .error,
                        .measurementCaptureMismatch,
                        bindingID: expectation.key.bindingID,
                        contextID: expectation.key.contextID,
                        discriminator: observation.id.rawValue
                    )
                default:
                    throw error
                }
            } catch is CancellationError {
                throw AuditError.cancelled
            } catch {
                result.fail(.invalid)
                try add(
                    .error,
                    .measurementCaptureUnavailable,
                    bindingID: expectation.key.bindingID,
                    contextID: expectation.key.contextID,
                    discriminator: observation.id.rawValue
                )
            }
        }

        private enum CaptureResolutionError: Error {
            case unavailable
        }

        private func trustedCollector(
            for reference: RevisionReference
        ) throws -> TrustedCollector? {
            var lowerBound = 0
            var upperBound = sortedTrustedCollectors.count
            while lowerBound < upperBound {
                let middle = lowerBound + (upperBound - lowerBound) / 2
                let candidate = sortedTrustedCollectors[middle]
                let comparison = try shortcutCoverageCompareRevisionReferences(
                    candidate.collector,
                    reference,
                    budget: budget
                )
                if comparison < 0 {
                    lowerBound = middle + 1
                } else {
                    upperBound = middle
                }
            }
            guard lowerBound < sortedTrustedCollectors.count else { return nil }
            let candidate = sortedTrustedCollectors[lowerBound]
            return try shortcutCoverageCompareRevisionReferences(
                candidate.collector,
                reference,
                budget: budget
            ) == 0 ? candidate : nil
        }

        private mutating func isValidMeasuredProvenance(
            _ provenance: EvidenceProvenance
        ) -> Bool {
            guard provenance.origin.isMeasured, let measurement = provenance.measurement else {
                return false
            }
            return shortcutCoverageIsValidID(provenance.sourceID.rawValue)
                && shortcutCoverageIsValidID(measurement.captureID.rawValue)
                && shortcutCoverageIsValidID(measurement.collector.id.rawValue)
                && shortcutCoverageIsValidID(measurement.build.id.rawValue)
                && measurement.collector.revision > 0
                && measurement.build.revision > 0
                && measurement.executableArtifact.algorithm == .sha256
                && measurement.executableArtifact.bytes.count == 32
                && measurement.inventoryRevision > 0
                && measurement.inventoryArtifact.algorithm == .sha256
                && measurement.inventoryArtifact.bytes.count == 32
                && measurement.measurementArtifact.algorithm == .sha256
                && measurement.measurementArtifact.bytes.count == 32
                && measurement.capturedAtUnixMilliseconds > 0
                && (16...64).contains(measurement.runNonce.count)
                && measurement.captureSignature.count == 64
        }

        private mutating func inventoryDigest() throws -> ArtifactDigest {
            if let cachedInventoryDigest { return cachedInventoryDigest }
            var hasher = SHA256()
            try shortcutCoverageHashFramed(String(inventory.revision), into: &hasher, budget: budget)
            for binding in try sortedBindings(inventory.bindings) {
                for component in binding.identityComponents {
                    try shortcutCoverageHashFramed(component, into: &hasher, budget: budget)
                }
            }
            for binding in try sortedNativeBindings(inventory.nativeBindings) {
                for component in binding.identityComponents {
                    try shortcutCoverageHashFramed(component, into: &hasher, budget: budget)
                }
            }
            let digest = ArtifactDigest(bytes: Array(hasher.finalize()))
            cachedInventoryDigest = digest
            return digest
        }

        private mutating func authenticationData(for observation: Observation) throws -> Data {
            try ShortcutCoverageAudit.signaturePayload(
                for: observation,
                maximumBytes: limits.maximumCaptureBytes,
                cancellationCheck: cancellationCheck
            )
        }

        private mutating func add(
            _ severity: FindingSeverity,
            _ code: FindingCode,
            bindingID: StableID? = nil,
            contextID: ContextID? = nil,
            occurrenceCount: Int? = nil,
            discriminator: String = ""
        ) throws {
            try budget.consume()
            let findingID = Finding.ID(
                rawValue: try shortcutCoverageOpaqueID(
                    [
                        code.rawValue,
                        bindingID?.rawValue ?? "",
                        contextID?.rawValue ?? "",
                        occurrenceCount.map(String.init) ?? "",
                        discriminator
                    ],
                    budget: budget
                )
            )
            let finding = Finding(
                id: findingID,
                severity: severity,
                code: code,
                bindingID: bindingID,
                contextID: contextID,
                occurrenceCount: occurrenceCount,
                discriminator: discriminator
            )
            guard findingIDs.insert(finding.id).inserted else { return }
            guard findings.count < limits.maximumFindings else {
                throw AuditError.findingLimitExceeded(maximum: limits.maximumFindings)
            }
            findings.append(finding)
        }

        private mutating func sortedFindings() throws -> [Finding] {
            let sortBudget = budget
            return try boundedSorted(findings) { left, right in
                if left.severity != right.severity { return left.severity > right.severity }
                let codeComparison = try shortcutCoverageCompareUTF8(
                    left.code.rawValue,
                    right.code.rawValue,
                    budget: sortBudget
                )
                if codeComparison != 0 { return codeComparison < 0 }
                return try shortcutCoverageCompareUTF8(
                    left.id.rawValue,
                    right.id.rawValue,
                    budget: sortBudget
                ) < 0
            }
        }

        private mutating func sortedIDs(_ values: [StableID]) throws -> [StableID] {
            let sortBudget = budget
            let canonical = shortcutCoverageHashOrderCanonicalized(values) {
                shortcutCoverageCompareUTF8($0.rawValue, $1.rawValue) < 0
            }
            return try boundedSorted(canonical) {
                try shortcutCoverageCompareUTF8($0.rawValue, $1.rawValue, budget: sortBudget) < 0
            }
        }

        private mutating func sortedBindings(_ values: [Binding]) throws -> [Binding] {
            try shortcutCoverageSortedBindings(values, budget: budget)
        }

        private mutating func sortedNativeBindings(
            _ values: [NativeBinding]
        ) throws -> [NativeBinding] {
            try shortcutCoverageSortedNativeBindings(values, budget: budget)
        }

        private mutating func sortedStrings(_ values: [String]) throws -> [String] {
            let sortBudget = budget
            let canonical = shortcutCoverageHashOrderCanonicalized(values) {
                shortcutCoverageCompareUTF8($0, $1) < 0
            }
            return try boundedSorted(canonical) {
                try shortcutCoverageCompareUTF8($0, $1, budget: sortBudget) < 0
            }
        }

        private mutating func sortedMatrixKeys(_ values: [MatrixKey]) throws -> [MatrixKey] {
            let sortBudget = budget
            let canonical = shortcutCoverageHashOrderCanonicalized(values) { left, right in
                let bindingComparison = shortcutCoverageCompareUTF8(
                    left.bindingID.rawValue,
                    right.bindingID.rawValue
                )
                if bindingComparison != 0 { return bindingComparison < 0 }
                return shortcutCoverageCompareUTF8(left.contextID.rawValue, right.contextID.rawValue) < 0
            }
            return try boundedSorted(canonical) { left, right in
                let bindingComparison = try shortcutCoverageCompareUTF8(
                    left.bindingID.rawValue,
                    right.bindingID.rawValue,
                    budget: sortBudget
                )
                if bindingComparison != 0 { return bindingComparison < 0 }
                return try shortcutCoverageCompareUTF8(
                    left.contextID.rawValue,
                    right.contextID.rawValue,
                    budget: sortBudget
                ) < 0
            }
        }

        private func digestPrecedes(_ left: ArtifactDigest, _ right: ArtifactDigest) throws -> Bool {
            try shortcutCoverageCompareBytes(left.bytes, right.bytes, budget: budget) < 0
        }

        private func policyShortcutPrecedes(
            _ left: Policy.CommandShortcut,
            _ right: Policy.CommandShortcut
        ) throws -> Bool {
            try shortcutCoverageCompareStringArrays(
                shortcutCoveragePolicyIdentity(left),
                shortcutCoveragePolicyIdentity(right),
                budget: budget
            ) < 0
        }

        private func reservationPrecedes(
            _ left: Policy.NativeTextEditingReservation,
            _ right: Policy.NativeTextEditingReservation
        ) throws -> Bool {
            try shortcutCoverageCompareStringArrays(
                shortcutCoverageReservationIdentity(left),
                shortcutCoverageReservationIdentity(right),
                budget: budget
            ) < 0
        }

        private func collisionPrecedes(
            _ left: Policy.Collision,
            _ right: Policy.Collision
        ) throws -> Bool {
            try shortcutCoverageCompareStringArrays(
                shortcutCoverageCollisionIdentity(left),
                shortcutCoverageCollisionIdentity(right),
                budget: budget
            ) < 0
        }

        private func trustedCollectorPrecedes(
            _ left: TrustedCollector,
            _ right: TrustedCollector
        ) throws -> Bool {
            let referenceComparison = try shortcutCoverageCompareRevisionReferences(
                left.collector,
                right.collector,
                budget: budget
            )
            if referenceComparison != 0 { return referenceComparison < 0 }
            return try shortcutCoverageCompareBytes(
                left.signingPublicKey,
                right.signingPublicKey,
                budget: budget
            ) < 0
        }

        private mutating func boundedSorted<Element>(
            _ values: [Element],
            by precedes: (Element, Element) throws -> Bool
        ) throws -> [Element] {
            guard values.count > 1 else {
                try budget.consume(UInt64(values.count))
                return values
            }
            var source = values
            var destination: [Element] = []
            destination.reserveCapacity(values.count)
            var width = 1
            while width < source.count {
                destination.removeAll(keepingCapacity: true)
                var lowerBound = 0
                while lowerBound < source.count {
                    let middle = min(lowerBound + width, source.count)
                    let upperBound = min(middle + width, source.count)
                    var left = lowerBound
                    var right = middle
                    while left < middle, right < upperBound {
                        try budget.consume()
                        if try precedes(source[right], source[left]) {
                            destination.append(source[right])
                            right += 1
                        } else {
                            destination.append(source[left])
                            left += 1
                        }
                    }
                    while left < middle {
                        try budget.consume()
                        destination.append(source[left])
                        left += 1
                    }
                    while right < upperBound {
                        try budget.consume()
                        destination.append(source[right])
                        right += 1
                    }
                    lowerBound = upperBound
                }
                swap(&source, &destination)
                if width > source.count / 2 { break }
                width *= 2
            }
            return source
        }
    }

    fileprivate struct FingerprintHasher {
        private var hash: UInt64 = 14_695_981_039_346_656_037

        mutating func append(_ components: [String], budget: inout WorkBudget) throws {
            for component in components {
                try append(component, budget: &budget)
            }
        }

        mutating func append(_ component: String, budget: inout WorkBudget) throws {
            var byteCount = 0
            for _ in component.utf8 {
                try budget.consume()
                byteCount += 1
            }
            for byte in "\(byteCount):".utf8 {
                try budget.consume()
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            for byte in component.utf8 {
                try budget.consume()
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }

        func finalize() -> Fingerprint {
            Fingerprint(rawValue: hash)
        }
    }

    fileprivate final class WorkBudget: @unchecked Sendable {
        let maximum: UInt64
        let cancellationCheckInterval: UInt64
        let cancellationCheck: CancellationCheck
        private let lock = NSLock()
        private var completed: UInt64 = 0
        private var workAtLastCancellationCheck: UInt64 = 0

        init(limits: Limits, cancellationCheck: @escaping CancellationCheck) throws {
            try ShortcutCoverageAudit.validate(limits)
            maximum = limits.maximumWorkUnits
            cancellationCheckInterval = UInt64(limits.cancellationCheckInterval)
            self.cancellationCheck = cancellationCheck
            try checkCancellation()
        }

        func consume(_ amount: UInt64 = 1) throws {
            lock.lock()
            guard amount <= maximum, completed <= maximum - amount else {
                lock.unlock()
                try checkCancellation()
                throw AuditError.workLimitExceeded(maximum: maximum)
            }
            completed += amount
            let shouldCheck = completed - workAtLastCancellationCheck >= cancellationCheckInterval
            if shouldCheck { workAtLastCancellationCheck = completed }
            lock.unlock()
            if shouldCheck {
                try checkCancellation()
            }
        }

        func checkCancellation() throws {
            if cancellationCheck() { throw AuditError.cancelled }
        }

        func finish() throws {
            try checkCancellation()
            lock.lock()
            workAtLastCancellationCheck = completed
            lock.unlock()
        }
    }

    fileprivate static func validate(_ limits: Limits) throws {
        let integerLimits: [(Limit, Int, Int, Int)] = [
            (.bindings, limits.maximumBindings, 0, Limits.hardMaximumBindings),
            (.contexts, limits.maximumContexts, 0, Limits.hardMaximumContexts),
            (
                .trustedCollectors,
                limits.maximumTrustedCollectors,
                0,
                Limits.hardMaximumTrustedCollectors
            ),
            (
                .observations,
                limits.maximumObservations,
                0,
                Limits.hardMaximumObservations
            ),
            (.findings, limits.maximumFindings, 0, Limits.hardMaximumFindings),
            (
                .stringUTF8Bytes,
                limits.maximumStringUTF8Bytes,
                0,
                Limits.hardMaximumStringUTF8Bytes
            ),
            (
                .totalStringUTF8Bytes,
                limits.maximumTotalStringUTF8Bytes,
                0,
                Limits.hardMaximumTotalStringUTF8Bytes
            ),
            (
                .captureBytes,
                limits.maximumCaptureBytes,
                0,
                Limits.hardMaximumCaptureBytes
            ),
            (
                .cancellationCheckInterval,
                limits.cancellationCheckInterval,
                1,
                Limits.hardMaximumCancellationCheckInterval
            )
        ]
        for (limit, value, minimum, maximum) in integerLimits
        where !(minimum...maximum).contains(value) {
            throw AuditError.invalidLimit(limit)
        }
        guard (1...Limits.hardMaximumWorkUnits).contains(limits.maximumWorkUnits) else {
            throw AuditError.invalidLimit(.workUnits)
        }
    }
}

/// Dictionary keys and Set elements iterate in a per-instance seeded order. A metered merge
/// sort over that order charges a different number of comparisons on every run, so the
/// audit's work total (and its minimum passing budget) would drift. Sorting first with an
/// unmetered comparison makes the metered charge depend only on the values. The unmetered
/// pass orders the same elements the metered sort then charges for, so it stays within the
/// same order of work as the metered pass.
private func shortcutCoverageHashOrderCanonicalized<Element>(
    _ values: [Element],
    by areInIncreasingOrder: (Element, Element) -> Bool
) -> [Element] {
    values.sorted(by: areInIncreasingOrder)
}

private func shortcutCoverageCompareUTF8(_ left: String, _ right: String) -> Int {
    let comparison = left.utf8.lexicographicallyPrecedes(right.utf8)
    if comparison { return -1 }
    if right.utf8.lexicographicallyPrecedes(left.utf8) { return 1 }
    return 0
}

private func shortcutCoverageCompareUTF8(
    _ left: String,
    _ right: String,
    budget: ShortcutCoverageAudit.WorkBudget
) throws -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        try budget.consume()
        switch (leftIterator.next(), rightIterator.next()) {
        case (let leftByte?, let rightByte?):
            if leftByte < rightByte { return -1 }
            if leftByte > rightByte { return 1 }
        case (nil, nil):
            return 0
        case (nil, _?):
            return -1
        case (_?, nil):
            return 1
        }
    }
}

private func shortcutCoverageCompareStringArrays(_ left: [String], _ right: [String]) -> Int {
    for (leftValue, rightValue) in zip(left, right) {
        let comparison = shortcutCoverageCompareUTF8(leftValue, rightValue)
        if comparison != 0 { return comparison }
    }
    if left.count < right.count { return -1 }
    if left.count > right.count { return 1 }
    return 0
}

private func shortcutCoverageCompareStringArrays(
    _ left: [String],
    _ right: [String],
    budget: ShortcutCoverageAudit.WorkBudget
) throws -> Int {
    for (leftValue, rightValue) in zip(left, right) {
        let comparison = try shortcutCoverageCompareUTF8(
            leftValue,
            rightValue,
            budget: budget
        )
        if comparison != 0 { return comparison }
    }
    try budget.consume()
    if left.count < right.count { return -1 }
    if left.count > right.count { return 1 }
    return 0
}

private func shortcutCoverageCompareBytes(
    _ left: [UInt8],
    _ right: [UInt8],
    budget: ShortcutCoverageAudit.WorkBudget
) throws -> Int {
    for (leftByte, rightByte) in zip(left, right) {
        try budget.consume()
        if leftByte < rightByte { return -1 }
        if leftByte > rightByte { return 1 }
    }
    try budget.consume()
    if left.count < right.count { return -1 }
    if left.count > right.count { return 1 }
    return 0
}

private func shortcutCoverageCompareRevisionReferences(
    _ left: ShortcutCoverageAudit.RevisionReference,
    _ right: ShortcutCoverageAudit.RevisionReference,
    budget: ShortcutCoverageAudit.WorkBudget
) throws -> Int {
    let idComparison = try shortcutCoverageCompareUTF8(
        left.id.rawValue,
        right.id.rawValue,
        budget: budget
    )
    if idComparison != 0 { return idComparison }
    try budget.consume()
    if left.revision < right.revision { return -1 }
    if left.revision > right.revision { return 1 }
    return 0
}

private func shortcutCoverageSortedBindings(
    _ values: [ShortcutCoverageAudit.Binding],
    budget: ShortcutCoverageAudit.WorkBudget
) throws -> [ShortcutCoverageAudit.Binding] {
    try shortcutCoverageBoundedSorted(values, budget: budget) { left, right in
        let idComparison = try shortcutCoverageCompareUTF8(
            left.id.rawValue,
            right.id.rawValue,
            budget: budget
        )
        if idComparison != 0 { return idComparison < 0 }
        return try shortcutCoverageCompareStringArrays(
            left.identityComponents,
            right.identityComponents,
            budget: budget
        ) < 0
    }
}

private func shortcutCoverageSortedNativeBindings(
    _ values: [ShortcutCoverageAudit.NativeBinding],
    budget: ShortcutCoverageAudit.WorkBudget
) throws -> [ShortcutCoverageAudit.NativeBinding] {
    try shortcutCoverageBoundedSorted(values, budget: budget) { left, right in
        let idComparison = try shortcutCoverageCompareUTF8(
            left.id.rawValue,
            right.id.rawValue,
            budget: budget
        )
        if idComparison != 0 { return idComparison < 0 }
        return try shortcutCoverageCompareStringArrays(
            left.identityComponents,
            right.identityComponents,
            budget: budget
        ) < 0
    }
}

private func shortcutCoverageBoundedSorted<Element>(
    _ values: [Element],
    budget: ShortcutCoverageAudit.WorkBudget,
    by precedes: (Element, Element) throws -> Bool
) throws -> [Element] {
    guard values.count > 1 else {
        try budget.consume(UInt64(values.count))
        return values
    }
    var source = values
    var destination: [Element] = []
    destination.reserveCapacity(values.count)
    var width = 1
    while width < source.count {
        destination.removeAll(keepingCapacity: true)
        var lowerBound = 0
        while lowerBound < source.count {
            let middle = min(lowerBound + width, source.count)
            let upperBound = min(middle + width, source.count)
            var left = lowerBound
            var right = middle
            while left < middle, right < upperBound {
                try budget.consume()
                if try precedes(source[right], source[left]) {
                    destination.append(source[right])
                    right += 1
                } else {
                    destination.append(source[left])
                    left += 1
                }
            }
            while left < middle {
                try budget.consume()
                destination.append(source[left])
                left += 1
            }
            while right < upperBound {
                try budget.consume()
                destination.append(source[right])
                right += 1
            }
            lowerBound = upperBound
        }
        swap(&source, &destination)
        if width > source.count / 2 { break }
        width *= 2
    }
    return source
}

private func shortcutCoverageFrame(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
}

private func shortcutCoverageHardwareKey(
    _ keyCode: UInt16
) -> ShortcutCoverageAudit.Policy.Key? {
    switch keyCode {
    case 36: .special(.return)
    case 76: .special(.return)
    case 48: .special(.tab)
    case 49: .special(.space)
    case 51: .special(.backspace)
    case 53: .special(.escape)
    case 122: .function(1)
    case 120: .function(2)
    case 99: .function(3)
    case 118: .function(4)
    case 96: .function(5)
    case 97: .function(6)
    case 98: .function(7)
    case 100: .function(8)
    case 101: .function(9)
    case 109: .function(10)
    case 103: .function(11)
    case 111: .function(12)
    case 105: .function(13)
    case 107: .function(14)
    case 113: .function(15)
    case 106: .function(16)
    case 64: .function(17)
    case 79: .function(18)
    case 80: .function(19)
    case 90: .function(20)
    case 115: .special(.home)
    case 116: .special(.pageUp)
    case 117: .special(.delete)
    case 119: .special(.end)
    case 121: .special(.pageDown)
    case 123: .special(.leftArrow)
    case 124: .special(.rightArrow)
    case 125: .special(.downArrow)
    case 126: .special(.upArrow)
    default: nil
    }
}

private func shortcutCoverageCharacter(_ value: String) -> Character? {
    var iterator = value.makeIterator()
    guard let character = iterator.next(), iterator.next() == nil else { return nil }
    return character
}

private func shortcutCoverageSpecialCharactersMatch(
    _ keyCode: UInt16,
    _ characters: String
) -> Bool {
    let scalar: UInt32
    switch keyCode {
    case 36: scalar = 0x000D
    case 48: scalar = 0x0009
    case 49: scalar = 0x0020
    case 51: scalar = 0x007F
    case 53: scalar = 0x001B
    case 122: scalar = 0xF704
    case 120: scalar = 0xF705
    case 99: scalar = 0xF706
    case 118: scalar = 0xF707
    case 96: scalar = 0xF708
    case 97: scalar = 0xF709
    case 98: scalar = 0xF70A
    case 100: scalar = 0xF70B
    case 101: scalar = 0xF70C
    case 109: scalar = 0xF70D
    case 103: scalar = 0xF70E
    case 111: scalar = 0xF70F
    case 105: scalar = 0xF710
    case 107: scalar = 0xF711
    case 113: scalar = 0xF712
    case 106: scalar = 0xF713
    case 64: scalar = 0xF714
    case 79: scalar = 0xF715
    case 80: scalar = 0xF716
    case 90: scalar = 0xF717
    case 115: scalar = 0xF729
    case 116: scalar = 0xF72C
    case 117: scalar = 0xF728
    case 76: scalar = 0x0003
    case 119: scalar = 0xF72B
    case 121: scalar = 0xF72D
    case 123: scalar = 0xF702
    case 124: scalar = 0xF703
    case 125: scalar = 0xF701
    case 126: scalar = 0xF700
    default: return false
    }
    return characters.unicodeScalars.count == 1
        && characters.unicodeScalars.first?.value == scalar
}

private func shortcutCoverageModifiers(
    _ rawFlags: UInt64
) -> Set<ShortcutCoverageAudit.Policy.Modifier> {
    // NSEvent.ModifierFlags device-independent bits.
    let masks: [(UInt64, ShortcutCoverageAudit.Policy.Modifier)] = [
        (1 << 17, .shift),
        (1 << 18, .control),
        (1 << 19, .option),
        (1 << 20, .command),
        (1 << 23, .function)
    ]
    return Set(masks.compactMap { rawFlags & $0.0 == 0 ? nil : $0.1 })
}

private func shortcutCoveragePrimaryStatus(
    _ statuses: Set<ShortcutCoverageAudit.CellStatus>
) -> ShortcutCoverageAudit.CellStatus {
    let precedence: [ShortcutCoverageAudit.CellStatus] = [
        .missing,
        .duplicate,
        .invalid,
        .assertionOnly,
        .mismatched,
        .complete
    ]
    return precedence.first(where: statuses.contains) ?? .complete
}

private func shortcutCoverageHashFramed(
    _ value: String,
    into hasher: inout SHA256,
    budget: ShortcutCoverageAudit.WorkBudget
) throws {
    var byteCount = 0
    for _ in value.utf8 {
        try budget.consume()
        byteCount += 1
    }
    let prefix = "\(byteCount):"
    for byte in prefix.utf8 {
        try budget.consume()
        var byte = byte
        withUnsafeBytes(of: &byte) { hasher.update(bufferPointer: $0) }
    }
    for byte in value.utf8 {
        try budget.consume()
        var byte = byte
        withUnsafeBytes(of: &byte) { hasher.update(bufferPointer: $0) }
    }
}

private func shortcutCoverageDigest(
    _ data: Data,
    budget: ShortcutCoverageAudit.WorkBudget
) throws -> ShortcutCoverageAudit.ArtifactDigest {
    var hasher = SHA256()
    let sliceByteCount = max(1, Int(clamping: budget.cancellationCheckInterval))
    var lowerBound = data.startIndex
    while lowerBound < data.endIndex {
        let upperBound = data.index(
            lowerBound,
            offsetBy: min(sliceByteCount, data.distance(from: lowerBound, to: data.endIndex))
        )
        let slice = data[lowerBound..<upperBound]
        try budget.consume(UInt64(slice.count))
        hasher.update(data: slice)
        lowerBound = upperBound
    }
    try budget.checkCancellation()
    return ShortcutCoverageAudit.ArtifactDigest(bytes: Array(hasher.finalize()))
}

private func shortcutCoverageHashFramed(
    _ value: String,
    into hasher: inout SHA256,
    cancellationCheck: ShortcutCoverageAudit.CancellationCheck
) throws {
    var byteCount = 0
    for _ in value.utf8 {
        if byteCount & 0xFFF == 0, cancellationCheck() {
            throw ShortcutCoverageAudit.AuditError.cancelled
        }
        byteCount += 1
    }
    let prefix = "\(byteCount):"
    hasher.update(data: Data(prefix.utf8))
    var chunk = Data()
    chunk.reserveCapacity(4_096)
    for byte in value.utf8 {
        if chunk.count == 4_096 {
            if cancellationCheck() { throw ShortcutCoverageAudit.AuditError.cancelled }
            hasher.update(data: chunk)
            chunk.removeAll(keepingCapacity: true)
        }
        chunk.append(byte)
    }
    if cancellationCheck() { throw ShortcutCoverageAudit.AuditError.cancelled }
    if !chunk.isEmpty { hasher.update(data: chunk) }
}

private func shortcutCoveragePolicyIdentity(
    _ shortcut: KeyboardShortcutPolicy.CommandShortcut
) -> [String] {
    [
        "command-shortcut",
        shortcut.chord.canonicalDescription,
        shortcut.command.rawValue,
        KeyboardShortcutPolicy.LifecycleState.allCases
            .filter(shortcut.enabledLifecycleStates.contains)
            .map(\.rawValue)
            .joined(separator: ","),
        shortcut.requiresDirty ? "dirty" : "any-dirty-state",
        shortcut.requiresSelection ? "selection" : "any-selection-state",
        shortcut.allowsReadOnly ? "read-only-allowed" : "editable-only"
    ]
}

private func shortcutCoverageReservationIdentity(
    _ reservation: KeyboardShortcutPolicy.NativeTextEditingReservation
) -> [String] {
    [
        "native-reservation",
        reservation.chord.canonicalDescription,
        reservation.command.rawValue,
        reservation.applicability.rawValue
    ]
}

private func shortcutCoverageCollisionIdentity(
    _ collision: KeyboardShortcutPolicy.Collision
) -> [String] {
    [
        "collision",
        collision.chord.canonicalDescription,
        KeyboardShortcutPolicy.CollisionKind.allCases
            .filter(collision.kinds.contains)
            .map(\.rawValue)
            .joined(separator: ","),
        collision.commands.map(\.rawValue).joined(separator: ","),
        collision.nativeTextEditingCommands.map(\.rawValue).joined(separator: ","),
        String(collision.commandShortcutCount),
        String(collision.nativeReservationCount),
        collision.isConditional ? "conditional" : "unconditional"
    ]
}

private func shortcutCoverageAppendFramed(
    _ value: String,
    to data: inout Data,
    maximumBytes: Int,
    cancellationCheck: ShortcutCoverageAudit.CancellationCheck,
    budget: ShortcutCoverageAudit.WorkBudget? = nil
) throws {
    var byteCount = 0
    for _ in value.utf8 {
        try budget?.consume()
        if byteCount & 0xFFF == 0, cancellationCheck() {
            throw ShortcutCoverageAudit.AuditError.cancelled
        }
        guard byteCount < maximumBytes else {
            throw ShortcutCoverageAudit.AuditError.captureTooLarge(maximumBytes: maximumBytes)
        }
        byteCount += 1
    }
    let prefix = "\(byteCount):"
    try budget?.consume(UInt64(prefix.utf8.count))
    guard prefix.utf8.count <= maximumBytes,
        data.count <= maximumBytes - prefix.utf8.count,
        byteCount <= maximumBytes - data.count - prefix.utf8.count
    else {
        throw ShortcutCoverageAudit.AuditError.captureTooLarge(maximumBytes: maximumBytes)
    }
    data.append(contentsOf: prefix.utf8)
    var appended = 0
    for byte in value.utf8 {
        try budget?.consume()
        if appended & 0xFFF == 0, cancellationCheck() {
            throw ShortcutCoverageAudit.AuditError.cancelled
        }
        data.append(byte)
        appended += 1
    }
}

private func shortcutCoverageCaptureBinaryInputIsBounded(
    _ observation: ShortcutCoverageAudit.Observation,
    maximumBytes: Int
) -> Bool {
    guard observation.dispatchTrace.ownershipDecisions.count <= 2,
        observation.dispatchTrace.targetActions.count <= 1,
        observation.dispatchTrace.results.count <= 1
    else { return false }
    if let measurement = observation.provenance.measurement {
        guard measurement.executableArtifact.bytes.count <= min(maximumBytes, 64),
            measurement.inventoryArtifact.bytes.count <= min(maximumBytes, 64),
            measurement.measurementArtifact.bytes.count <= min(maximumBytes, 64),
            measurement.runNonce.count <= min(maximumBytes, 64),
            measurement.captureSignature.count <= min(maximumBytes, 128)
        else {
            return false
        }
    }
    return true
}

private func shortcutCoverageShortcutIdentity(_ shortcut: MenuShortcutDescriptor) -> [String] {
    [
        shortcut.platform.rawValue,
        shortcut.key.rawValue,
        shortcut.modifiers.sorted().map(\.rawValue).joined(separator: ",")
    ]
}

private func shortcutCoverageCommandStateIdentity(
    _ context: ComparisonCommandState.Context
) -> [String] {
    var result = [
        shortcutCoveragePaneStateIdentity(context.left),
        shortcutCoveragePaneStateIdentity(context.right),
        shortcutCoverageLifecycleIdentity(context.comparisonLifecycle),
        context.hasSelection ? "selected" : "unselected",
        context.hasSignificantDifferences ? "differences" : "no-differences",
        context.canUndo ? "undo" : "no-undo",
        context.canRedo ? "redo" : "no-redo",
        shortcutCoverageDifferenceNavigationIdentity(context.differenceNavigation),
        shortcutCoverageConflictNavigationIdentity(context.conflictNavigation),
        shortcutCoverageComparedFileNavigationIdentity(context.comparedFileNavigation),
        context.canChangePane ? "change-pane" : "no-change-pane",
        context.canChangePaneBack ? "change-pane-back" : "no-change-pane-back",
        context.isMergeMode ? "merge-mode" : "not-merge-mode",
        context.isSessionLocked ? "session-locked" : "session-unlocked"
    ]
    switch context.layout {
    case .twoPane:
        result.append("two-pane")
    case .threePane(let middle, let destination, let isSupported, let isEligible):
        result.append("three-pane")
        result.append(shortcutCoveragePaneStateIdentity(middle))
        result.append(shortcutCoverageSideIdentity(destination))
        result.append(isSupported ? "automatic-merge-supported" : "automatic-merge-unsupported")
        result.append(isEligible ? "automatic-merge-eligible" : "automatic-merge-ineligible")
    }
    result.append(context.layoutContext.visualOrder.map(shortcutCoverageSideIdentity).joined(separator: ","))
    result.append(shortcutCoverageSideIdentity(context.layoutContext.activePane))
    return result
}

private func shortcutCoveragePaneStateIdentity(
    _ state: ComparisonCommandState.PaneState
) -> String {
    [
        state.isLoaded ? "loaded" : "unloaded",
        state.isEditable ? "editable" : "read-only",
        state.isDirty ? "dirty" : "clean",
        state.isUntitled ? "untitled" : "titled",
        state.hasExternalChange ? "external-change" : "unchanged"
    ].joined(separator: ",")
}

private func shortcutCoverageLifecycleIdentity(
    _ lifecycle: ComparisonCommandState.ComparisonLifecycle
) -> String {
    switch lifecycle {
    case .loading: "loading"
    case .refreshing: "refreshing"
    case .stale: "stale"
    case .failed: "failed"
    case .canceled: "canceled"
    case .currentSuccess: "current-success"
    }
}

private func shortcutCoverageSideIdentity(_ side: MergeCommandPolicy.Side) -> String {
    switch side {
    case .left: "left"
    case .middle: "middle"
    case .right: "right"
    }
}

private func shortcutCoverageDifferenceNavigationIdentity(
    _ state: ComparisonCommandState.DifferenceNavigation
) -> String {
    [
        state.canSelectLineDifference,
        state.canSelectPreviousLineDifference,
        state.canSelectNextDifference,
        state.canSelectPreviousDifference,
        state.canSelectFirstDifference,
        state.canSelectCurrentDifference,
        state.canSelectLastDifference
    ].map { $0 ? "1" : "0" }.joined()
}

private func shortcutCoverageConflictNavigationIdentity(
    _ state: ComparisonCommandState.ConflictNavigationState
) -> String {
    [
        state.isSupported,
        state.hasConflicts,
        state.canSelectFirstConflict,
        state.canSelectNextConflict,
        state.canSelectPreviousConflict,
        state.canSelectCurrentConflict,
        state.canSelectLastConflict
    ].map { $0 ? "1" : "0" }.joined()
}

private func shortcutCoverageComparedFileNavigationIdentity(
    _ state: ComparisonCommandState.ComparedFileNavigation
) -> String {
    [
        state.isSupported,
        state.canSelectFirst,
        state.canSelectPrevious,
        state.canSelectNext,
        state.canSelectLast
    ].map { $0 ? "1" : "0" }.joined()
}

private func shortcutCoverageOpaqueID(_ components: [String]) -> String {
    var hasher = SHA256()
    for component in components {
        hasher.update(data: Data(shortcutCoverageFrame(component).utf8))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func shortcutCoverageOpaqueID(
    _ components: [String],
    budget: ShortcutCoverageAudit.WorkBudget
) throws -> String {
    var hasher = SHA256()
    for component in components {
        try shortcutCoverageHashFramed(component, into: &hasher, budget: budget)
    }
    var result = ""
    result.reserveCapacity(64)
    for byte in hasher.finalize() {
        try budget.consume()
        result.append(String(format: "%02x", byte))
    }
    return result
}

private func shortcutCoveragePolicyTuple(
    _ command: ComparisonCommandState.Identifier,
    _ chord: KeyboardShortcutPolicy.Chord
) -> String {
    shortcutCoverageFrame(command.rawValue) + shortcutCoverageFrame(chord.canonicalDescription)
}

private func shortcutCoverageInvocationSourceIdentity(_ source: MenuInvocationSource) -> String {
    source.rawValue
}

private func shortcutCoverageCommandResultIdentity(_ result: MenuCommandResult) -> String {
    switch result {
    case .completed: "completed"
    case .rejected: "rejected"
    case .failed: "failed"
    case .notInvoked: "notInvoked"
    }
}

private func shortcutCoverageForEachCommandResultComponent(
    _ result: MenuCommandResult,
    _ body: (String) throws -> Void
) rethrows {
    try body(shortcutCoverageCommandResultIdentity(result))
    if let id = shortcutCoverageCommandResultID(result) {
        try body(id.rawValue)
    }
}

private func shortcutCoverageHex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private func shortcutCoverageCommandResultID(
    _ result: MenuCommandResult
) -> MenuValidationResultID? {
    switch result {
    case .completed(let id), .rejected(let id), .failed(let id): id
    case .notInvoked: nil
    }
}

private func shortcutCoverageIsValidID(_ value: String) -> Bool {
    guard !value.isEmpty, value == value.precomposedStringWithCanonicalMapping else {
        return false
    }
    return !value.unicodeScalars.contains { scalar in
        scalar.properties.isWhitespace || scalar.value <= 0x1F
            || (0x7F...0x9F).contains(scalar.value)
            || scalar.properties.generalCategory == .format
            || scalar.properties.isNoncharacterCodePoint
    }
}

private func shortcutCoverageSortWork(_ count: Int) -> UInt64 {
    guard count > 1 else { return UInt64(count) }
    let value = UInt64(count)
    let levels = UInt64(Int.bitWidth - (count - 1).leadingZeroBitCount)
    let (work, overflow) = value.multipliedReportingOverflow(by: levels + 1)
    return overflow ? UInt64.max : work
}

public typealias ShortcutCoverageInventory = ShortcutCoverageAudit.Inventory
public typealias ShortcutCoverageEvidence = ShortcutCoverageAudit.Evidence
public typealias ShortcutCoverageReport = ShortcutCoverageAudit.Report
public typealias ShortcutCoverageReceipt = ShortcutCoverageAudit.Receipt
public typealias ShortcutCoverageAuditError = ShortcutCoverageAudit.AuditError
