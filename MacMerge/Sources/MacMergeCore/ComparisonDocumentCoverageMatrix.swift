import CryptoKit
import Foundation

public enum ComparisonDocumentSide: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case left
    case right

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

public enum ComparisonDocumentSourceShape: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case bothFiles
    case leftFileRightScratchpad
    case leftScratchpadRightFile
    case bothScratchpads

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }

    public func kind(on side: ComparisonDocumentSide) -> ComparisonDocumentSourceKind {
        switch (self, side) {
        case (.bothFiles, _), (.leftFileRightScratchpad, .left),
            (.leftScratchpadRightFile, .right):
            .file
        case (.bothScratchpads, _), (.leftFileRightScratchpad, .right),
            (.leftScratchpadRightFile, .left):
            .scratchpad
        }
    }
}

public enum ComparisonDocumentSourceKind: UInt8, CaseIterable, Hashable, Sendable {
    case file
    case scratchpad
}

public enum ComparisonDocumentDirtyState: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case neither
    case left
    case right
    case both

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }

    public func contains(_ side: ComparisonDocumentSide) -> Bool {
        switch (self, side) {
        case (.left, .left), (.right, .right), (.both, _): true
        case (.neither, _), (.left, .right), (.right, .left): false
        }
    }
}

public enum ComparisonDocumentSideIncident: UInt8, CaseIterable, Hashable, Sendable {
    case none
    case externalChange
    case replacement
    case missingDiskFile
}

/// Independent disk incidents for both sides. A row may represent simultaneous incidents.
public struct ComparisonDocumentIncident: Comparable, Hashable, Sendable {
    public static let none = ComparisonDocumentIncident(left: .none, right: .none)

    public let left: ComparisonDocumentSideIncident
    public let right: ComparisonDocumentSideIncident

    public init(
        left: ComparisonDocumentSideIncident,
        right: ComparisonDocumentSideIncident
    ) {
        self.left = left
        self.right = right
    }

    public static func externalChange(_ side: ComparisonDocumentSide) -> Self {
        side == .left
            ? Self(left: .externalChange, right: .none)
            : Self(left: .none, right: .externalChange)
    }

    public static func missingDiskFile(_ side: ComparisonDocumentSide) -> Self {
        side == .left
            ? Self(left: .missingDiskFile, right: .none)
            : Self(left: .none, right: .missingDiskFile)
    }

    public static func replacement(_ side: ComparisonDocumentSide) -> Self {
        side == .left
            ? Self(left: .replacement, right: .none)
            : Self(left: .none, right: .replacement)
    }

    public subscript(side: ComparisonDocumentSide) -> ComparisonDocumentSideIncident {
        side == .left ? left : right
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rank < right.rank
    }

    fileprivate var rank: UInt8 { left.rawValue * 4 + right.rawValue }
    fileprivate var affectedSides: [ComparisonDocumentSide] {
        ComparisonDocumentSide.allCases.filter { self[$0] != .none }
    }
}

public enum ComparisonDocumentSideSaveOutcome: Hashable, Sendable {
    case notAttempted
    case failed(ThreePaneSaveNonCommitReason)
    case uncertain(ThreePaneSaveCommitUncertainty)
    case committed(ComparisonDocumentPaneUpdateOutcome)

    fileprivate var isAttempted: Bool { self != .notAttempted }
    fileprivate var isCommitted: Bool {
        if case .committed = self { return true }
        return false
    }
    fileprivate var paneUpdateWasApplied: Bool {
        if case .committed(.applied) = self { return true }
        return false
    }
    fileprivate var rank: UInt8 {
        switch self {
        case .notAttempted:
            0
        case .failed(let reason):
            UInt8(1 + comparisonDocumentSaveFailureRank(reason))
        case .uncertain(let reason):
            UInt8(6 + comparisonDocumentSaveUncertaintyRank(reason))
        case .committed(let paneUpdate):
            UInt8(10 + paneUpdate.rank)
        }
    }
}

public enum ComparisonDocumentPaneUpdateRejection: UInt8, CaseIterable, Hashable, Sendable {
    case planAlreadyConsumed
    case ownerRevisionChanged
    case bindingChanged
}

/// Result of consuming the save plan after durable publication. Rejection preserves dirty/untitled
/// pane state even though destination publication committed.
public enum ComparisonDocumentPaneUpdateOutcome: Hashable, Sendable {
    case applied
    case rejected(ComparisonDocumentPaneUpdateRejection)

    fileprivate var rank: UInt8 {
        switch self {
        case .applied: 0
        case .rejected(let reason): 1 + reason.rawValue
        }
    }
}

public enum ComparisonDocumentSaveExecution: Hashable, Sendable {
    case notAttempted
    case single(ComparisonDocumentSide)
    case batch
}

public enum ComparisonDocumentSideSaveOperation: UInt8, CaseIterable, Hashable, Sendable {
    case notAttempted
    case saveInPlace
    case saveAsNewFile
    case saveAsReplacingFile

    fileprivate var isAttempted: Bool { self != .notAttempted }
}

/// Exact execution shape and exact outcome for each side.
public struct ComparisonDocumentSaveState: Comparable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let notAttempted = try! ComparisonDocumentSaveState(
        execution: .notAttempted,
        leftOperation: .notAttempted,
        left: .notAttempted,
        rightOperation: .notAttempted,
        right: .notAttempted
    )

    public let execution: ComparisonDocumentSaveExecution
    public let leftOperation: ComparisonDocumentSideSaveOperation
    public let left: ComparisonDocumentSideSaveOutcome
    public let rightOperation: ComparisonDocumentSideSaveOperation
    public let right: ComparisonDocumentSideSaveOutcome

    public init(
        execution: ComparisonDocumentSaveExecution,
        leftOperation: ComparisonDocumentSideSaveOperation,
        left: ComparisonDocumentSideSaveOutcome,
        rightOperation: ComparisonDocumentSideSaveOperation,
        right: ComparisonDocumentSideSaveOutcome
    ) throws {
        guard leftOperation.isAttempted == left.isAttempted,
            rightOperation.isAttempted == right.isAttempted
        else {
            throw ComparisonDocumentCoverageError.impossibleScenario
        }
        switch execution {
        case .notAttempted:
            guard left == .notAttempted, right == .notAttempted else {
                throw ComparisonDocumentCoverageError.impossibleScenario
            }
        case .single(.left):
            guard left.isAttempted, right == .notAttempted else {
                throw ComparisonDocumentCoverageError.impossibleScenario
            }
        case .single(.right):
            guard left == .notAttempted, right.isAttempted else {
                throw ComparisonDocumentCoverageError.impossibleScenario
            }
        case .batch:
            guard left.isAttempted, right.isAttempted,
                comparisonDocumentIsValidBatchSave(left: left, right: right)
            else {
                throw ComparisonDocumentCoverageError.impossibleScenario
            }
        }
        self.execution = execution
        self.leftOperation = leftOperation
        self.left = left
        self.rightOperation = rightOperation
        self.right = right
    }

    public subscript(side: ComparisonDocumentSide) -> ComparisonDocumentSideSaveOutcome {
        side == .left ? left : right
    }

    public func operation(on side: ComparisonDocumentSide) -> ComparisonDocumentSideSaveOperation {
        side == .left ? leftOperation : rightOperation
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rank < right.rank
    }

    public var description: String { "ComparisonDocumentSaveState(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["save": "<redacted>"], displayStyle: .struct)
    }

    fileprivate var attemptedSides: [ComparisonDocumentSide] {
        ComparisonDocumentSide.allCases.filter { self[$0].isAttempted }
    }

    fileprivate var committedSides: [ComparisonDocumentSide] {
        ComparisonDocumentSide.allCases.filter { self[$0].isCommitted }
    }

    fileprivate var rank: UInt16 {
        switch execution {
        case .notAttempted:
            0
        case .single(.left):
            UInt16(comparisonDocumentSideSaveRank(operation: leftOperation, outcome: left))
        case .single(.right):
            UInt16(
                comparisonDocumentMaximumSideSaveRank
                    + comparisonDocumentSideSaveRank(operation: rightOperation, outcome: right)
            )
        case .batch:
            UInt16(
                comparisonDocumentMaximumSideSaveRank * 2
                    + (comparisonDocumentSideSaveRank(operation: leftOperation, outcome: left) - 1)
                    * comparisonDocumentMaximumSideSaveRank
                    + comparisonDocumentSideSaveRank(operation: rightOperation, outcome: right)
            )
        }
    }
}

public struct ComparisonDocumentScenarioID: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

/// One valid row in the canonical two-document state matrix.
public struct ComparisonDocumentScenario: Identifiable, Comparable, Hashable, Sendable {
    public let id: ComparisonDocumentScenarioID
    public let sourceShape: ComparisonDocumentSourceShape
    public let dirtyState: ComparisonDocumentDirtyState
    public let incident: ComparisonDocumentIncident
    public let save: ComparisonDocumentSaveState
    public let backup: ComparisonDocumentBackupState

    public init(
        sourceShape: ComparisonDocumentSourceShape,
        dirtyState: ComparisonDocumentDirtyState,
        incident: ComparisonDocumentIncident,
        save: ComparisonDocumentSaveState = .notAttempted,
        backup: ComparisonDocumentBackupState = .notApplicable
    ) throws {
        guard
            Self.isPossible(
                sourceShape: sourceShape,
                dirtyState: dirtyState,
                incident: incident,
                save: save,
                backup: backup
            )
        else {
            throw ComparisonDocumentCoverageError.impossibleScenario
        }
        self.init(
            validatedSourceShape: sourceShape,
            dirtyState: dirtyState,
            incident: incident,
            save: save,
            backup: backup
        )
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.id < right.id
    }

    public func sourceKind(on side: ComparisonDocumentSide) -> ComparisonDocumentSourceKind {
        sourceShape.kind(on: side)
    }

    public func isDirty(_ side: ComparisonDocumentSide) -> Bool {
        dirtyState.contains(side) && !save[side].paneUpdateWasApplied
    }

    public var expectedLifecyclePhase: ComparisonLifecycleState.Phase {
        expectedChangedSides.isEmpty ? .current : .stale
    }

    fileprivate var expectedChangedSides: [ComparisonDocumentSide] {
        ComparisonDocumentSide.allCases.filter {
            dirtyState.contains($0) || incident[$0] != .none || saveChangesLifecycleSource(on: $0)
        }
    }

    fileprivate func saveChangesLifecycleSource(on side: ComparisonDocumentSide) -> Bool {
        switch save[side] {
        case .failed(.sourceRevisionChanged):
            return true
        case .uncertain:
            return save.operation(on: side) == .saveInPlace
        case .committed(.applied):
            return true
        case .committed(.rejected(.bindingChanged)):
            return true
        case .committed(.rejected):
            return save.operation(on: side) == .saveInPlace
        case .notAttempted, .failed:
            return false
        }
    }

    /// Lifecycle carries one triggering reason, so simultaneous changes permit either exact side.
    public var expectedStaleReasons: [ComparisonLifecycleState.StaleReason] {
        var reasons: [ComparisonLifecycleState.StaleReason] = []
        for side in ComparisonDocumentSide.allCases {
            if incident[side] != .none {
                reasons.append(.externalChange(side.lifecycleSide))
            }
            if dirtyState.contains(side) || saveChangesLifecycleSource(on: side) {
                reasons.append(.sideChanged(side.lifecycleSide))
            }
        }
        return reasons
    }

    public func expectedDiskState(
        on side: ComparisonDocumentSide
    ) -> ComparisonDocumentDiskState {
        if save[side].paneUpdateWasApplied,
            save.operation(on: side) == .saveAsNewFile
                || save.operation(on: side) == .saveAsReplacingFile
        {
            return .present
        }
        switch incident[side] {
        case .externalChange:
            return .externallyChanged
        case .replacement:
            return .replaced
        case .missingDiskFile:
            return .missing
        case .none:
            switch save[side] {
            case .committed(.applied):
                return .present
            case .committed(.rejected):
                return sourceKind(on: side) == .file ? .present : .notApplicable
            case .uncertain:
                return save.operation(on: side) == .saveInPlace
                    ? .commitUncertain
                    : (sourceKind(on: side) == .file ? .present : .notApplicable)
            case .notAttempted, .failed:
                return sourceKind(on: side) == .file ? .present : .notApplicable
            }
        }
    }

    public func expectedSourceKind(
        on side: ComparisonDocumentSide
    ) -> ComparisonDocumentSourceKind {
        if sourceKind(on: side) == .scratchpad, save[side].paneUpdateWasApplied {
            return .file
        }
        return sourceKind(on: side)
    }

    fileprivate init(
        validatedSourceShape sourceShape: ComparisonDocumentSourceShape,
        dirtyState: ComparisonDocumentDirtyState,
        incident: ComparisonDocumentIncident,
        save: ComparisonDocumentSaveState,
        backup: ComparisonDocumentBackupState
    ) {
        self.sourceShape = sourceShape
        self.dirtyState = dirtyState
        self.incident = incident
        self.save = save
        self.backup = backup
        let sourceAndDirty = Int(sourceShape.rawValue) * 4 + Int(dirtyState.rawValue)
        let incidentOffset = sourceAndDirty * 16 + Int(incident.rank)
        let saveOffset = incidentOffset * comparisonDocumentSaveStateRadix + Int(save.rank)
        let rawID = saveOffset * comparisonDocumentBackupStateRadix + Int(backup.rank)
        guard let exactID = UInt32(exactly: rawID) else {
            preconditionFailure("Canonical comparison-document scenario ID overflowed UInt32.")
        }
        id = ComparisonDocumentScenarioID(rawValue: exactID)
    }

    fileprivate static func isPossible(
        sourceShape: ComparisonDocumentSourceShape,
        dirtyState: ComparisonDocumentDirtyState,
        incident: ComparisonDocumentIncident,
        save: ComparisonDocumentSaveState,
        backup: ComparisonDocumentBackupState
    ) -> Bool {
        for side in ComparisonDocumentSide.allCases {
            if incident[side] != .none, sourceShape.kind(on: side) != .file { return false }
            if save[side].isAttempted, !dirtyState.contains(side) {
                guard case .single(side) = save.execution,
                    save.operation(on: side) == .saveAsNewFile
                        || save.operation(on: side) == .saveAsReplacingFile
                else { return false }
            }
            if !comparisonDocumentSaveOperationIsValid(
                save.operation(on: side),
                sourceKind: sourceShape.kind(on: side)
            ) {
                return false
            }
            if !comparisonDocumentBackupIsValid(
                backup[side],
                operation: save.operation(on: side),
                outcome: save[side],
                incident: incident[side]
            ) {
                return false
            }
            if !comparisonDocumentIncidentSaveRaceIsValid(
                incident: incident[side],
                operation: save.operation(on: side),
                outcome: save[side]
            ) {
                return false
            }
        }
        return true
    }
}

public struct ComparisonDocumentStableID: RawRepresentable, Comparable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        comparisonDocumentCompareUTF8(left.rawValue, right.rawValue) < 0
    }

    public var description: String { "ComparisonDocumentStableID(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["identity": "<redacted>"], displayStyle: .struct)
    }
}

/// Exact caller-owned identity and monotonically advancing revision.
public struct ComparisonDocumentRevisionReference: Comparable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let id: ComparisonDocumentStableID
    public let revision: UInt64

    public init(id: ComparisonDocumentStableID, revision: UInt64) {
        self.id = id
        self.revision = revision
    }

    public static func < (left: Self, right: Self) -> Bool {
        if left.id != right.id { return left.id < right.id }
        return left.revision < right.revision
    }

    public var description: String { "ComparisonDocumentRevisionReference(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["reference": "<redacted>"], displayStyle: .struct)
    }
}

/// Stable filesystem identity. Location digest binds canonical location without exposing it.
public struct ComparisonDocumentLocationIdentity: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let keyReference: ComparisonDocumentStableID
    public let hmacSHA256: [UInt8]

    /// `hmacSHA256` must be HMAC-SHA256 over the canonical descriptor-relative location.
    public init(keyReference: ComparisonDocumentStableID, hmacSHA256: [UInt8]) {
        self.keyReference = keyReference
        self.hmacSHA256 = hmacSHA256
    }

    public var description: String { "ComparisonDocumentLocationIdentity(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["location": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonDocumentFileIdentity: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let volumeID: UInt64
    public let fileID: UInt64
    public let generation: UInt64
    public let location: ComparisonDocumentLocationIdentity

    public init(
        volumeID: UInt64,
        fileID: UInt64,
        generation: UInt64,
        location: ComparisonDocumentLocationIdentity
    ) {
        self.volumeID = volumeID
        self.fileID = fileID
        self.generation = generation
        self.location = location
    }

    public var description: String { "ComparisonDocumentFileIdentity(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["identity": "<redacted>"], displayStyle: .struct)
    }
}

/// Exact regular-file revision captured by production before audit.
public struct ComparisonDocumentFileRevision: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let identity: ComparisonDocumentFileIdentity
    public let revision: UInt64
    public let byteCount: UInt64
    public let metadataByteCount: UInt64
    public let modificationTimeSeconds: Int64
    public let modificationTimeNanoseconds: UInt32
    public let statusChangeTimeSeconds: Int64
    public let statusChangeTimeNanoseconds: UInt32
    public let contentSHA256: [UInt8]
    public let metadataSHA256: [UInt8]
    public let contentAndMetadataSHA256: [UInt8]
    public let encoding: ThreePaneSaveEncodingMetadata
    public let isReadOnly: Bool

    public init(
        identity: ComparisonDocumentFileIdentity,
        revision: UInt64,
        byteCount: UInt64,
        metadataByteCount: UInt64,
        modificationTimeSeconds: Int64,
        modificationTimeNanoseconds: UInt32,
        statusChangeTimeSeconds: Int64,
        statusChangeTimeNanoseconds: UInt32,
        contentSHA256: [UInt8],
        metadataSHA256: [UInt8],
        contentAndMetadataSHA256: [UInt8],
        encoding: ThreePaneSaveEncodingMetadata,
        isReadOnly: Bool
    ) {
        self.identity = identity
        self.revision = revision
        self.byteCount = byteCount
        self.metadataByteCount = metadataByteCount
        self.modificationTimeSeconds = modificationTimeSeconds
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.statusChangeTimeSeconds = statusChangeTimeSeconds
        self.statusChangeTimeNanoseconds = statusChangeTimeNanoseconds
        self.contentSHA256 = contentSHA256
        self.metadataSHA256 = metadataSHA256
        self.contentAndMetadataSHA256 = contentAndMetadataSHA256
        self.encoding = encoding
        self.isReadOnly = isReadOnly
    }

    public var description: String { "ComparisonDocumentFileRevision(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["revision": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonDocumentScratchpadRevision: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let identity: UUID
    public let generation: UInt64
    public let encodedByteCount: UInt64
    public let metadataByteCount: UInt64
    public let encodedContentSHA256: [UInt8]
    public let metadataSHA256: [UInt8]
    public let contentAndMetadataSHA256: [UInt8]
    public let encoding: ThreePaneSaveEncodingMetadata
    public let isReadOnly: Bool

    public init(
        identity: UUID,
        generation: UInt64,
        encodedByteCount: UInt64,
        metadataByteCount: UInt64,
        encodedContentSHA256: [UInt8],
        metadataSHA256: [UInt8],
        contentAndMetadataSHA256: [UInt8],
        encoding: ThreePaneSaveEncodingMetadata,
        isReadOnly: Bool
    ) {
        self.identity = identity
        self.generation = generation
        self.encodedByteCount = encodedByteCount
        self.metadataByteCount = metadataByteCount
        self.encodedContentSHA256 = encodedContentSHA256
        self.metadataSHA256 = metadataSHA256
        self.contentAndMetadataSHA256 = contentAndMetadataSHA256
        self.encoding = encoding
        self.isReadOnly = isReadOnly
    }

    public var description: String { "ComparisonDocumentScratchpadRevision(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["revision": "<redacted>"], displayStyle: .struct)
    }
}

public enum ComparisonDocumentSourceRevision: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case file(ComparisonDocumentFileRevision)
    case scratchpad(ComparisonDocumentScratchpadRevision)

    public var kind: ComparisonDocumentSourceKind {
        switch self {
        case .file: .file
        case .scratchpad: .scratchpad
        }
    }

    public var description: String {
        "ComparisonDocumentSourceRevision(kind: \(kind), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["kind": kind, "revision": "<redacted>"], displayStyle: .enum)
    }
}

/// Exact editable document revision. Digest covers complete current encoded content and metadata.
public struct ComparisonDocumentContentRevision: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let identity: UUID
    public let generation: UInt64
    public let encodedByteCount: UInt64
    public let metadataByteCount: UInt64
    public let encodedContentSHA256: [UInt8]
    public let metadataSHA256: [UInt8]
    public let contentAndMetadataSHA256: [UInt8]
    public let encoding: ThreePaneSaveEncodingMetadata
    public let isReadOnly: Bool

    public init(
        identity: UUID,
        generation: UInt64,
        encodedByteCount: UInt64,
        metadataByteCount: UInt64,
        encodedContentSHA256: [UInt8],
        metadataSHA256: [UInt8],
        contentAndMetadataSHA256: [UInt8],
        encoding: ThreePaneSaveEncodingMetadata,
        isReadOnly: Bool
    ) {
        self.identity = identity
        self.generation = generation
        self.encodedByteCount = encodedByteCount
        self.metadataByteCount = metadataByteCount
        self.encodedContentSHA256 = encodedContentSHA256
        self.metadataSHA256 = metadataSHA256
        self.contentAndMetadataSHA256 = contentAndMetadataSHA256
        self.encoding = encoding
        self.isReadOnly = isReadOnly
    }

    public var description: String { "ComparisonDocumentContentRevision(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["revision": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonDocumentDirectoryRevision: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let identity: ComparisonDocumentFileIdentity
    public let revision: UInt64
    public let metadataByteCount: UInt64
    public let metadataSHA256: [UInt8]

    public init(
        identity: ComparisonDocumentFileIdentity,
        revision: UInt64,
        metadataByteCount: UInt64,
        metadataSHA256: [UInt8]
    ) {
        self.identity = identity
        self.revision = revision
        self.metadataByteCount = metadataByteCount
        self.metadataSHA256 = metadataSHA256
    }

    public var description: String { "ComparisonDocumentDirectoryRevision(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["revision": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonDocumentDestinationSlotRevision: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let location: ComparisonDocumentLocationIdentity
    public let revision: UInt64

    public init(location: ComparisonDocumentLocationIdentity, revision: UInt64) {
        self.location = location
        self.revision = revision
    }

    public var description: String { "ComparisonDocumentDestinationSlotRevision(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["slot": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonDocumentSaveDestinationSnapshot: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let parent: ComparisonDocumentDirectoryRevision
    public let slot: ComparisonDocumentDestinationSlotRevision
    public let target: ComparisonDocumentFileRevision?

    public init(
        parent: ComparisonDocumentDirectoryRevision,
        slot: ComparisonDocumentDestinationSlotRevision,
        target: ComparisonDocumentFileRevision?
    ) {
        self.parent = parent
        self.slot = slot
        self.target = target
    }

    public var description: String { "ComparisonDocumentSaveDestinationSnapshot(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["snapshot": "<redacted>"], displayStyle: .struct)
    }
}

/// Expected destination CAS state, state pinned immediately before publication, and exact observed
/// post-state. Uncertain publication intentionally has no asserted post-state.
public struct ComparisonDocumentSaveDestinationTransition: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let expected: ComparisonDocumentSaveDestinationSnapshot
    public let observedBeforePublication: ComparisonDocumentSaveDestinationSnapshot
    public let observedAfterExecution: ComparisonDocumentSaveDestinationSnapshot?

    public init(
        expected: ComparisonDocumentSaveDestinationSnapshot,
        observedBeforePublication: ComparisonDocumentSaveDestinationSnapshot,
        observedAfterExecution: ComparisonDocumentSaveDestinationSnapshot?
    ) {
        self.expected = expected
        self.observedBeforePublication = observedBeforePublication
        self.observedAfterExecution = observedAfterExecution
    }

    public var description: String { "ComparisonDocumentSaveDestinationTransition(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["transition": "<redacted>"], displayStyle: .struct)
    }
}

public enum ComparisonDocumentSaveDestinationBinding: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case notApplicable
    case transition(ComparisonDocumentSaveDestinationTransition)

    public var description: String { "ComparisonDocumentSaveDestinationBinding(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["destination": "<redacted>"], displayStyle: .enum)
    }
}

public struct ComparisonDocumentSaveOperationBinding: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let planID: UUID
    public let sourceDocument: ComparisonDocumentContentRevision
    public let sourceFile: ComparisonDocumentFileRevision?
    public let limits: ThreePaneSavePlanningLimits
    public let destinationPathUTF8ByteCount: Int
    public let parentPathUTF8ByteCount: Int
    public let canonicalLeafIdentityUTF8ByteCount: Int
    public let plannedOperationCount: Int
    public let totalPathUTF8ByteCount: Int
    public let estimatedWorkUnits: UInt64
    public let committedPayload: ComparisonDocumentFileRevision?
    public let paneUpdateObservedDocument: ComparisonDocumentContentRevision?
    public let paneUpdateObservedSource: ComparisonDocumentSourceRevision?
    public let paneUpdateObservedPlanID: UUID?
    public let planWasConsumedBeforePaneUpdate: Bool

    public init(
        planID: UUID,
        sourceDocument: ComparisonDocumentContentRevision,
        sourceFile: ComparisonDocumentFileRevision?,
        limits: ThreePaneSavePlanningLimits,
        destinationPathUTF8ByteCount: Int,
        parentPathUTF8ByteCount: Int,
        canonicalLeafIdentityUTF8ByteCount: Int,
        plannedOperationCount: Int,
        totalPathUTF8ByteCount: Int,
        estimatedWorkUnits: UInt64,
        committedPayload: ComparisonDocumentFileRevision?,
        paneUpdateObservedDocument: ComparisonDocumentContentRevision?,
        paneUpdateObservedSource: ComparisonDocumentSourceRevision?,
        paneUpdateObservedPlanID: UUID?,
        planWasConsumedBeforePaneUpdate: Bool
    ) {
        self.planID = planID
        self.sourceDocument = sourceDocument
        self.sourceFile = sourceFile
        self.limits = limits
        self.destinationPathUTF8ByteCount = destinationPathUTF8ByteCount
        self.parentPathUTF8ByteCount = parentPathUTF8ByteCount
        self.canonicalLeafIdentityUTF8ByteCount = canonicalLeafIdentityUTF8ByteCount
        self.plannedOperationCount = plannedOperationCount
        self.totalPathUTF8ByteCount = totalPathUTF8ByteCount
        self.estimatedWorkUnits = estimatedWorkUnits
        self.committedPayload = committedPayload
        self.paneUpdateObservedDocument = paneUpdateObservedDocument
        self.paneUpdateObservedSource = paneUpdateObservedSource
        self.paneUpdateObservedPlanID = paneUpdateObservedPlanID
        self.planWasConsumedBeforePaneUpdate = planWasConsumedBeforePaneUpdate
    }

    public var description: String { "ComparisonDocumentSaveOperationBinding(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["operation": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonDocumentLifecycleSourceBinding: Comparable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let side: ComparisonDocumentSide
    public let source: ComparisonDocumentRevisionReference

    public init(side: ComparisonDocumentSide, source: ComparisonDocumentRevisionReference) {
        self.side = side
        self.source = source
    }

    public static func < (left: Self, right: Self) -> Bool {
        if left.side != right.side { return left.side < right.side }
        return left.source < right.source
    }

    public var description: String {
        "ComparisonDocumentLifecycleSourceBinding(side: \(side), source: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["side": side, "source": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonDocumentLifecycleOperationBinding: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let comparison: ComparisonDocumentRevisionReference
    public let operationID: UUID
    public let startedAtGeneration: UInt64
    public let inputs: ComparisonDocumentRevisionReference
    public let sources: [ComparisonDocumentLifecycleSourceBinding]

    public init(
        comparison: ComparisonDocumentRevisionReference,
        operationID: UUID,
        startedAtGeneration: UInt64,
        inputs: ComparisonDocumentRevisionReference,
        sources: [ComparisonDocumentLifecycleSourceBinding]
    ) throws {
        self.comparison = comparison
        self.operationID = operationID
        self.startedAtGeneration = startedAtGeneration
        self.inputs = inputs
        self.sources = try comparisonDocumentCanonicalLifecycleSources(sources)
    }

    public var description: String { "ComparisonDocumentLifecycleOperationBinding(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["operation": "<redacted>"], displayStyle: .struct)
    }
}

/// Exact open request, comparison lineage, input, result, and lifecycle source revisions.
public struct ComparisonDocumentComparisonRevisionBinding: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let openRequest: ComparisonOpenRequestIdentity
    public let comparison: ComparisonDocumentRevisionReference
    public let operation: ComparisonDocumentLifecycleOperationBinding
    public let inputs: ComparisonDocumentRevisionReference
    public let result: ComparisonDocumentRevisionReference
    public let resultInputs: ComparisonDocumentRevisionReference
    public let sources: [ComparisonDocumentLifecycleSourceBinding]
    public let resultSources: [ComparisonDocumentLifecycleSourceBinding]

    public init(
        openRequest: ComparisonOpenRequestIdentity,
        comparison: ComparisonDocumentRevisionReference,
        operation: ComparisonDocumentLifecycleOperationBinding,
        inputs: ComparisonDocumentRevisionReference,
        result: ComparisonDocumentRevisionReference,
        resultInputs: ComparisonDocumentRevisionReference,
        sources: [ComparisonDocumentLifecycleSourceBinding],
        resultSources: [ComparisonDocumentLifecycleSourceBinding]
    ) throws {
        self.openRequest = openRequest
        self.comparison = comparison
        self.operation = operation
        self.inputs = inputs
        self.result = result
        self.resultInputs = resultInputs
        self.sources = try comparisonDocumentCanonicalLifecycleSources(sources)
        self.resultSources = try comparisonDocumentCanonicalLifecycleSources(resultSources)
    }

    public var description: String { "ComparisonDocumentComparisonRevisionBinding(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["binding": "<redacted>"], displayStyle: .struct)
    }

    /// Captures a current or retained result and its exact input lineage.
    public init(
        openRequest: ComparisonOpenRequestIdentity,
        lifecycle state: ComparisonLifecycleState
    ) throws {
        guard let inputs = state.inputs, let result = state.result else {
            throw ComparisonDocumentCoverageError.comparisonResultUnavailable
        }
        let sources = try inputs.sides.map { binding in
            guard let side = ComparisonDocumentSide(binding.side) else {
                throw ComparisonDocumentCoverageError.inconsistentRevisionBindings
            }
            return ComparisonDocumentLifecycleSourceBinding(
                side: side,
                source: ComparisonDocumentRevisionReference(
                    id: ComparisonDocumentStableID(rawValue: binding.identity.rawValue.uuidString),
                    revision: binding.generation
                )
            )
        }
        let resultSources = try result.inputs.sides.map { binding in
            guard let side = ComparisonDocumentSide(binding.side) else {
                throw ComparisonDocumentCoverageError.inconsistentRevisionBindings
            }
            return ComparisonDocumentLifecycleSourceBinding(
                side: side,
                source: ComparisonDocumentRevisionReference(
                    id: ComparisonDocumentStableID(rawValue: binding.identity.rawValue.uuidString),
                    revision: binding.generation
                )
            )
        }
        let operationSources = try result.operation.inputs.sides.map { binding in
            guard let side = ComparisonDocumentSide(binding.side) else {
                throw ComparisonDocumentCoverageError.inconsistentRevisionBindings
            }
            return ComparisonDocumentLifecycleSourceBinding(
                side: side,
                source: ComparisonDocumentRevisionReference(
                    id: ComparisonDocumentStableID(rawValue: binding.identity.rawValue.uuidString),
                    revision: binding.generation
                )
            )
        }
        let comparisonReference = ComparisonDocumentRevisionReference(
            id: ComparisonDocumentStableID(rawValue: state.identity.rawValue.uuidString),
            revision: state.generation
        )
        let operation = try ComparisonDocumentLifecycleOperationBinding(
            comparison: ComparisonDocumentRevisionReference(
                id: ComparisonDocumentStableID(
                    rawValue: result.operation.comparisonIdentity.rawValue.uuidString
                ),
                revision: result.operation.startedAtGeneration
            ),
            operationID: result.operation.operationID.rawValue,
            startedAtGeneration: result.operation.startedAtGeneration,
            inputs: ComparisonDocumentRevisionReference(
                id: ComparisonDocumentStableID(
                    rawValue: result.operation.inputs.identity.rawValue.uuidString
                ),
                revision: result.operation.inputs.generation
            ),
            sources: operationSources
        )
        try self.init(
            openRequest: openRequest,
            comparison: comparisonReference,
            operation: operation,
            inputs: ComparisonDocumentRevisionReference(
                id: ComparisonDocumentStableID(rawValue: inputs.identity.rawValue.uuidString),
                revision: inputs.generation
            ),
            result: ComparisonDocumentRevisionReference(
                id: ComparisonDocumentStableID(rawValue: result.identity.rawValue.uuidString),
                revision: result.publishedAtGeneration
            ),
            resultInputs: ComparisonDocumentRevisionReference(
                id: ComparisonDocumentStableID(rawValue: result.inputs.identity.rawValue.uuidString),
                revision: result.inputs.generation
            ),
            sources: sources,
            resultSources: resultSources
        )
    }
}

public struct ComparisonDocumentSideRevisionBinding: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let side: ComparisonDocumentSide
    public let document: ComparisonDocumentContentRevision
    public let resultDocument: ComparisonDocumentContentRevision
    public let lifecycleSource: ComparisonDocumentRevisionReference
    public let resultLifecycleSource: ComparisonDocumentRevisionReference
    public let openedSource: ComparisonDocumentSourceRevision
    public let saveOperation: ComparisonDocumentSaveOperationBinding?
    public let saveDestination: ComparisonDocumentSaveDestinationBinding
    public let completedBackup: ComparisonDocumentCompletedBackupEvidence?
    /// Exact backing-source observation after any external incident. Missing file has no revision.
    public let incidentSource: ComparisonDocumentSourceRevision?
    /// Exact source currently bound to pane after save and pane-update CAS.
    public let currentSource: ComparisonDocumentSourceRevision?
    public let resultSource: ComparisonDocumentSourceRevision

    public init(
        side: ComparisonDocumentSide,
        document: ComparisonDocumentContentRevision,
        resultDocument: ComparisonDocumentContentRevision,
        lifecycleSource: ComparisonDocumentRevisionReference,
        resultLifecycleSource: ComparisonDocumentRevisionReference,
        openedSource: ComparisonDocumentSourceRevision,
        saveOperation: ComparisonDocumentSaveOperationBinding?,
        saveDestination: ComparisonDocumentSaveDestinationBinding,
        completedBackup: ComparisonDocumentCompletedBackupEvidence?,
        incidentSource: ComparisonDocumentSourceRevision?,
        currentSource: ComparisonDocumentSourceRevision?,
        resultSource: ComparisonDocumentSourceRevision
    ) {
        self.side = side
        self.document = document
        self.resultDocument = resultDocument
        self.lifecycleSource = lifecycleSource
        self.resultLifecycleSource = resultLifecycleSource
        self.openedSource = openedSource
        self.saveOperation = saveOperation
        self.saveDestination = saveDestination
        self.completedBackup = completedBackup
        self.incidentSource = incidentSource
        self.currentSource = currentSource
        self.resultSource = resultSource
    }

    public var description: String {
        "ComparisonDocumentSideRevisionBinding(side: \(side), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["side": side, "bindings": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonDocumentRevisionBindings: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let comparison: ComparisonDocumentComparisonRevisionBinding
    public let sides: [ComparisonDocumentSideRevisionBinding]

    public init(
        comparison: ComparisonDocumentComparisonRevisionBinding,
        sides: [ComparisonDocumentSideRevisionBinding]
    ) throws {
        let canonicalSides = try comparisonDocumentCanonicalSideBindings(sides)
        guard canonicalSides.map(\.lifecycleSource) == comparison.sources.map(\.source),
            canonicalSides.map(\.resultLifecycleSource) == comparison.resultSources.map(\.source)
        else {
            throw ComparisonDocumentCoverageError.inconsistentRevisionBindings
        }
        self.comparison = comparison
        self.sides = canonicalSides
    }

    public subscript(side: ComparisonDocumentSide) -> ComparisonDocumentSideRevisionBinding {
        sides[Int(side.rawValue)]
    }

    public var description: String { "ComparisonDocumentRevisionBindings(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["bindings": "<redacted>"], displayStyle: .struct)
    }
}

public enum ComparisonDocumentDiskState: UInt8, CaseIterable, Hashable, Sendable {
    case notApplicable
    case present
    case externallyChanged
    case replaced
    case missing
    case commitUncertain
}

public enum ComparisonDocumentBackupExecutionOutcome: UInt8, CaseIterable, Hashable, Sendable {
    case notStarted
    case completed
    case failedBeforePublication
    case failedAfterPublication
    case cancelledBeforePublication
    case cancelledAfterPublication
    case publicationUncertain
}

public enum ComparisonDocumentSideBackupState: Hashable, Sendable {
    case notApplicable
    case required(
        trigger: BackupTrigger,
        contract: BackupExecutorContract,
        outcome: ComparisonDocumentBackupExecutionOutcome
    )

    fileprivate var rank: UInt8 {
        switch self {
        case .notApplicable: return 0
        case .required(let trigger, let contract, let outcome):
            guard trigger == .beforeSave, contract == .required else {
                preconditionFailure("Noncanonical comparison-document backup state cannot be ranked.")
            }
            return 1 + outcome.rawValue
        }
    }
}

public struct ComparisonDocumentBackupState: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let notApplicable = ComparisonDocumentBackupState(
        left: .notApplicable,
        right: .notApplicable
    )

    public let left: ComparisonDocumentSideBackupState
    public let right: ComparisonDocumentSideBackupState

    public init(
        left: ComparisonDocumentSideBackupState,
        right: ComparisonDocumentSideBackupState
    ) {
        self.left = left
        self.right = right
    }

    public subscript(side: ComparisonDocumentSide) -> ComparisonDocumentSideBackupState {
        side == .left ? left : right
    }

    public var description: String { "ComparisonDocumentBackupState(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["backup": "<redacted>"], displayStyle: .struct)
    }

    fileprivate var rank: UInt8 {
        left.rank * comparisonDocumentSideBackupStateRadix + right.rank
    }
}

/// Exact completed backup publication. Source is the occupied save destination revision copied
/// before save publication; destination is the independent backup slot and committed copy.
public struct ComparisonDocumentCompletedBackupEvidence: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let sourceRevision: ComparisonDocumentFileRevision
    public let destination: ComparisonDocumentSaveDestinationTransition
    public let committedPayload: ComparisonDocumentFileRevision

    public init(
        sourceRevision: ComparisonDocumentFileRevision,
        destination: ComparisonDocumentSaveDestinationTransition,
        committedPayload: ComparisonDocumentFileRevision
    ) {
        self.sourceRevision = sourceRevision
        self.destination = destination
        self.committedPayload = committedPayload
    }

    public var description: String { "ComparisonDocumentCompletedBackupEvidence(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["evidence": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonDocumentExpectedPaneState: Hashable, Sendable {
    public let sourceKind: ComparisonDocumentSourceKind
    public let isLoaded: Bool
    public let isEditable: Bool
    public let isDirty: Bool
    public let isUntitled: Bool
    public let diskState: ComparisonDocumentDiskState

    fileprivate init(scenario: ComparisonDocumentScenario, side: ComparisonDocumentSide) {
        sourceKind = scenario.expectedSourceKind(on: side)
        isLoaded = true
        isEditable = true
        isDirty = scenario.isDirty(side)
        isUntitled = sourceKind == .scratchpad
        diskState = scenario.expectedDiskState(on: side)
    }
}

public struct ComparisonDocumentExpectedState: Hashable, Sendable {
    public let lifecyclePhase: ComparisonLifecycleState.Phase
    public let hasRetainedComparisonResult: Bool
    public let permittedStaleReasons: [ComparisonLifecycleState.StaleReason]
    public let left: ComparisonDocumentExpectedPaneState
    public let right: ComparisonDocumentExpectedPaneState
    public let save: ComparisonDocumentSaveState
    public let saveExecutorContract: ThreePaneSaveExecutorContract?
    public let backup: ComparisonDocumentBackupState

    fileprivate init(scenario: ComparisonDocumentScenario) {
        lifecyclePhase = scenario.expectedLifecyclePhase
        hasRetainedComparisonResult = true
        permittedStaleReasons = scenario.expectedStaleReasons
        left = ComparisonDocumentExpectedPaneState(scenario: scenario, side: .left)
        right = ComparisonDocumentExpectedPaneState(scenario: scenario, side: .right)
        save = scenario.save
        if !scenario.save.attemptedSides.isEmpty {
            saveExecutorContract = .required
            backup = scenario.backup
        } else {
            saveExecutorContract = nil
            backup = .notApplicable
        }
    }

    public func pane(_ side: ComparisonDocumentSide) -> ComparisonDocumentExpectedPaneState {
        switch side {
        case .left: left
        case .right: right
        }
    }
}

public struct ComparisonDocumentCoverageRequirement: Identifiable, Hashable, Sendable {
    public var id: ComparisonDocumentScenarioID { scenario.id }
    public let scenario: ComparisonDocumentScenario
    public let bindings: ComparisonDocumentRevisionBindings
    public let expected: ComparisonDocumentExpectedState

    fileprivate init(
        scenario: ComparisonDocumentScenario,
        bindings: ComparisonDocumentRevisionBindings
    ) {
        self.scenario = scenario
        self.bindings = bindings
        expected = ComparisonDocumentExpectedState(scenario: scenario)
    }
}

/// Exact build-bound inventory. `canonical` is the only constructor that can create requirements.
public struct ComparisonDocumentCoverageInventory: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let reference: ComparisonDocumentRevisionReference
    public let build: ComparisonDocumentRevisionReference
    public let buildArtifactSHA256: [UInt8]
    public let requirements: [ComparisonDocumentCoverageRequirement]

    private init(
        reference: ComparisonDocumentRevisionReference,
        build: ComparisonDocumentRevisionReference,
        buildArtifactSHA256: [UInt8],
        requirements: [ComparisonDocumentCoverageRequirement]
    ) {
        self.reference = reference
        self.build = build
        self.buildArtifactSHA256 = buildArtifactSHA256
        self.requirements = requirements
    }

    public static func canonical(
        reference: ComparisonDocumentRevisionReference,
        build: ComparisonDocumentRevisionReference,
        buildArtifactSHA256: [UInt8],
        bindingsByScenario: [ComparisonDocumentScenarioID: ComparisonDocumentRevisionBindings]
    ) throws -> Self {
        let requirements = try ComparisonDocumentCoverageMatrix.canonicalScenarios.map { scenario in
            guard let bindings = bindingsByScenario[scenario.id] else {
                throw ComparisonDocumentCoverageError.invalidInventory(field: "requirements")
            }
            return ComparisonDocumentCoverageRequirement(scenario: scenario, bindings: bindings)
        }
        guard bindingsByScenario.count == requirements.count else {
            throw ComparisonDocumentCoverageError.invalidInventory(field: "requirements")
        }
        return Self(
            reference: reference,
            build: build,
            buildArtifactSHA256: buildArtifactSHA256,
            requirements: requirements
        )
    }

    public var description: String {
        "ComparisonDocumentCoverageInventory(requirements: \(requirements.count), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "requirementCount": requirements.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct ComparisonDocumentPaneObservation: Hashable, Sendable {
    public let sourceKind: ComparisonDocumentSourceKind
    public let isLoaded: Bool
    public let isEditable: Bool
    public let isDirty: Bool
    public let isUntitled: Bool
    public let diskState: ComparisonDocumentDiskState

    public init(
        sourceKind: ComparisonDocumentSourceKind,
        isLoaded: Bool,
        isEditable: Bool,
        isDirty: Bool,
        isUntitled: Bool,
        diskState: ComparisonDocumentDiskState
    ) {
        self.sourceKind = sourceKind
        self.isLoaded = isLoaded
        self.isEditable = isEditable
        self.isDirty = isDirty
        self.isUntitled = isUntitled
        self.diskState = diskState
    }

    public init(
        _ state: ComparisonCommandState.PaneState,
        sourceKind: ComparisonDocumentSourceKind,
        diskState: ComparisonDocumentDiskState
    ) {
        self.init(
            sourceKind: sourceKind,
            isLoaded: state.isLoaded,
            isEditable: state.isEditable,
            isDirty: state.isDirty,
            isUntitled: state.isUntitled,
            diskState: diskState
        )
    }
}

public struct ComparisonDocumentLifecycleObservation: Hashable, Sendable {
    public let phase: ComparisonLifecycleState.Phase
    public let hasCurrentResult: Bool
    public let hasRetainedResult: Bool
    public let staleReason: ComparisonLifecycleState.StaleReason?

    public init(
        phase: ComparisonLifecycleState.Phase,
        hasCurrentResult: Bool,
        hasRetainedResult: Bool,
        staleReason: ComparisonLifecycleState.StaleReason?
    ) {
        self.phase = phase
        self.hasCurrentResult = hasCurrentResult
        self.hasRetainedResult = hasRetainedResult
        self.staleReason = staleReason
    }

    public init(_ state: ComparisonLifecycleState) {
        self.init(
            phase: state.phase,
            hasCurrentResult: state.hasCurrentResult,
            hasRetainedResult: state.hasRetainedResult,
            staleReason: state.staleness?.reason
        )
    }
}

public enum ComparisonDocumentEvidenceOrigin: UInt8, CaseIterable, Hashable, Sendable {
    case productionAutomation
    case productionManualMeasurement
    case callerAssertion

    public var isProductionMeasurement: Bool { self != .callerAssertion }
}

public enum ComparisonDocumentCaptureResolutionError: Error, Equatable, Sendable {
    case exceedsMaximumByteCount
    case declaredByteCountMismatch
}

/// Sink enforces declared resolver bound while bytes are produced, not after allocation.
public final class ComparisonDocumentCaptureSink: @unchecked Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let maximumByteCount: Int
    private let lock = NSLock()
    private let expected: Data
    private var hasher = SHA256()
    private var matchesExpected = true
    private var byteCount = 0
    private var finished = false
    private var appending = false
    private let budget: ComparisonDocumentWorkBudget?

    fileprivate init(
        maximumByteCount: Int,
        budget: ComparisonDocumentWorkBudget,
        expected: Data
    ) {
        self.maximumByteCount = maximumByteCount
        self.budget = budget
        self.expected = expected
    }

    init(maximumByteCount: Int, expected: Data) {
        self.maximumByteCount = maximumByteCount
        budget = nil
        self.expected = expected
    }

    public func append(_ chunk: Data) throws {
        guard
            lock.withLock({
                guard !finished, !appending else { return false }
                appending = true
                return true
            })
        else {
            throw ComparisonDocumentCaptureResolutionError.declaredByteCountMismatch
        }
        defer { lock.withLock { appending = false } }
        let startingByteCount = lock.withLock { byteCount }
        guard maximumByteCount >= 0, startingByteCount <= maximumByteCount,
            chunk.count <= maximumByteCount - startingByteCount
        else {
            throw ComparisonDocumentCaptureResolutionError.exceedsMaximumByteCount
        }
        let sliceByteCount = max(1, budget?.cancellationCheckInterval ?? 64 * 1_024)
        var lowerBound = chunk.startIndex
        while lowerBound < chunk.endIndex {
            let upperBound = chunk.index(
                lowerBound,
                offsetBy: min(sliceByteCount, chunk.distance(from: lowerBound, to: chunk.endIndex))
            )
            let slice = chunk[lowerBound..<upperBound]
            try budget?.charge(slice.count)
            lock.withLock {
                hasher.update(data: slice)
                for byte in slice {
                    if byteCount >= expected.count || expected[byteCount] != byte {
                        matchesExpected = false
                    }
                    byteCount += 1
                }
            }
            lowerBound = upperBound
        }
    }

    public var description: String {
        lock.withLock {
            "ComparisonDocumentCaptureSink(bytes: \(byteCount), contents: <redacted>)"
        }
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["capture": "<redacted>"], displayStyle: .class)
    }

    func finish() throws -> (byteCount: Int, sha256: [UInt8], matchesExpected: Bool) {
        try lock.withLock {
            guard !finished, !appending else {
                throw ComparisonDocumentCaptureResolutionError.declaredByteCountMismatch
            }
            finished = true
            return (
                byteCount,
                Array(hasher.finalize()),
                matchesExpected && byteCount == expected.count
            )
        }
    }
}

/// External trust anchor. Never derive this from submitted inventory or evidence.
public struct ComparisonDocumentTrustedCollector: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let reference: ComparisonDocumentRevisionReference
    public let ed25519PublicKey: [UInt8]

    public init(reference: ComparisonDocumentRevisionReference, ed25519PublicKey: [UInt8]) {
        self.reference = reference
        self.ed25519PublicKey = ed25519PublicKey
    }

    public var description: String { "ComparisonDocumentTrustedCollector(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["collector": "<redacted>"], displayStyle: .struct)
    }
}

public enum ComparisonDocumentProvenanceSource: UInt8, CaseIterable, Hashable, Sendable {
    case automatedHarness
    case manualProductionReview
}

public struct ComparisonDocumentReplayClaim: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let run: ComparisonDocumentRevisionReference
    public let nonce: [UInt8]

    public init(run: ComparisonDocumentRevisionReference, nonce: [UInt8]) {
        self.run = run
        self.nonce = nonce
    }

    public var description: String { "ComparisonDocumentReplayClaim(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["claim": "<redacted>"], displayStyle: .struct)
    }
}

/// Trusted audit time and replay authority supplied independently from evidence.
public struct ComparisonDocumentAuditPolicy: Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public struct ReplayClaimContext: Sendable {
        public let trustedAuditTimeUnixMilliseconds: UInt64
        public let deadlineUnixMilliseconds: UInt64
        public let remainingWorkUnits: Int
        public let cancellationCheck: ComparisonDocumentCoverageMatrix.CancellationCheck

        fileprivate init(
            trustedAuditTimeUnixMilliseconds: UInt64,
            deadlineUnixMilliseconds: UInt64,
            remainingWorkUnits: Int,
            cancellationCheck: @escaping ComparisonDocumentCoverageMatrix.CancellationCheck
        ) {
            self.trustedAuditTimeUnixMilliseconds = trustedAuditTimeUnixMilliseconds
            self.deadlineUnixMilliseconds = deadlineUnixMilliseconds
            self.remainingWorkUnits = remainingWorkUnits
            self.cancellationCheck = cancellationCheck
        }
    }

    public enum ReplayClaimResult: UInt8, Hashable, Sendable {
        case committed
        case rejectedReplay
        case cancelled
        case deadlineExceeded
        case workLimitExceeded
    }

    public typealias ReplayClaim =
        @Sendable (
            _ replayPolicy: ComparisonDocumentRevisionReference,
            _ evidence: ComparisonDocumentRevisionReference,
            _ archiveSHA256: [UInt8],
            _ claims: [ComparisonDocumentReplayClaim],
            _ context: ReplayClaimContext
        ) -> ReplayClaimResult

    public let trustedCollectors: [ComparisonDocumentTrustedCollector]
    public let trustedLocationKeyReferences: Set<ComparisonDocumentStableID>
    public let trustedAuditTimeUnixMilliseconds: UInt64
    public let maximumCaptureAgeMilliseconds: UInt64
    public let maximumFutureClockSkewMilliseconds: UInt64
    public let replayClaimDeadlineUnixMilliseconds: UInt64
    public let replayPolicy: ComparisonDocumentRevisionReference
    private let claimReplayNonce: ReplayClaim

    public init(
        trustedCollectors: [ComparisonDocumentTrustedCollector],
        trustedLocationKeyReferences: Set<ComparisonDocumentStableID>,
        trustedAuditTimeUnixMilliseconds: UInt64,
        maximumCaptureAgeMilliseconds: UInt64,
        maximumFutureClockSkewMilliseconds: UInt64,
        replayClaimDeadlineUnixMilliseconds: UInt64,
        replayPolicy: ComparisonDocumentRevisionReference,
        /// Must perform one atomic all-or-none commit. It must honor supplied cancellation, deadline,
        /// and remaining-work bounds before commit. Only `.committed` may retain claims. Revalidating
        /// exact same evidence reference and archive digest may succeed idempotently.
        claimReplayNonces: @escaping ReplayClaim
    ) {
        self.trustedCollectors = trustedCollectors
        self.trustedLocationKeyReferences = trustedLocationKeyReferences
        self.trustedAuditTimeUnixMilliseconds = trustedAuditTimeUnixMilliseconds
        self.maximumCaptureAgeMilliseconds = maximumCaptureAgeMilliseconds
        self.maximumFutureClockSkewMilliseconds = maximumFutureClockSkewMilliseconds
        self.replayClaimDeadlineUnixMilliseconds = replayClaimDeadlineUnixMilliseconds
        self.replayPolicy = replayPolicy
        claimReplayNonce = claimReplayNonces
    }

    fileprivate func claim(
        evidence: ComparisonDocumentRevisionReference,
        archiveSHA256: [UInt8],
        claims: [ComparisonDocumentReplayClaim],
        context: ReplayClaimContext
    ) -> ReplayClaimResult {
        claimReplayNonce(replayPolicy, evidence, archiveSHA256, claims, context)
    }

    public var description: String { "ComparisonDocumentAuditPolicy(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["policy": "<redacted>"], displayStyle: .struct)
    }
}

/// Provenance for one production measurement. Sensitive capture details remain digest-bound.
public struct ComparisonDocumentEvidenceProvenance: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let build: ComparisonDocumentRevisionReference
    public let inventory: ComparisonDocumentRevisionReference
    public let evidence: ComparisonDocumentRevisionReference
    public let collector: ComparisonDocumentRevisionReference
    public let run: ComparisonDocumentRevisionReference
    public let capturedAtUnixMilliseconds: UInt64
    public let runNonce: [UInt8]
    public let artifactSHA256: [UInt8]
    public let captureSHA256: [UInt8]
    public let captureByteCount: Int
    /// Ed25519 signature over `ComparisonDocumentCoverageMatrix.canonicalCaptureData(for:)`.
    public let collectorSignature: [UInt8]
    public let source: ComparisonDocumentProvenanceSource

    public init(
        build: ComparisonDocumentRevisionReference,
        inventory: ComparisonDocumentRevisionReference,
        evidence: ComparisonDocumentRevisionReference,
        collector: ComparisonDocumentRevisionReference,
        run: ComparisonDocumentRevisionReference,
        capturedAtUnixMilliseconds: UInt64,
        runNonce: [UInt8],
        artifactSHA256: [UInt8],
        captureSHA256: [UInt8],
        captureByteCount: Int,
        collectorSignature: [UInt8],
        source: ComparisonDocumentProvenanceSource
    ) {
        self.build = build
        self.inventory = inventory
        self.evidence = evidence
        self.collector = collector
        self.run = run
        self.capturedAtUnixMilliseconds = capturedAtUnixMilliseconds
        self.runNonce = runNonce
        self.artifactSHA256 = artifactSHA256
        self.captureSHA256 = captureSHA256
        self.captureByteCount = captureByteCount
        self.collectorSignature = collectorSignature
        self.source = source
    }

    public var description: String { "ComparisonDocumentEvidenceProvenance(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["provenance": "<redacted>"], displayStyle: .struct)
    }
}

/// Caller-supplied production observation. Presence alone never proves production behavior.
public struct ComparisonDocumentProductionObservation: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let scenarioID: ComparisonDocumentScenarioID
    public let bindings: ComparisonDocumentRevisionBindings
    public let lifecycle: ComparisonDocumentLifecycleObservation
    public let left: ComparisonDocumentPaneObservation
    public let right: ComparisonDocumentPaneObservation
    public let save: ComparisonDocumentSaveState
    public let saveExecutorContract: ThreePaneSaveExecutorContract?
    public let backup: ComparisonDocumentBackupState
    public let origin: ComparisonDocumentEvidenceOrigin
    public let provenance: ComparisonDocumentEvidenceProvenance?

    public init(
        scenarioID: ComparisonDocumentScenarioID,
        bindings: ComparisonDocumentRevisionBindings,
        lifecycle: ComparisonDocumentLifecycleObservation,
        left: ComparisonDocumentPaneObservation,
        right: ComparisonDocumentPaneObservation,
        save: ComparisonDocumentSaveState,
        saveExecutorContract: ThreePaneSaveExecutorContract?,
        backup: ComparisonDocumentBackupState,
        origin: ComparisonDocumentEvidenceOrigin,
        provenance: ComparisonDocumentEvidenceProvenance?
    ) {
        self.scenarioID = scenarioID
        self.bindings = bindings
        self.lifecycle = lifecycle
        self.left = left
        self.right = right
        self.save = save
        self.saveExecutorContract = saveExecutorContract
        self.backup = backup
        self.origin = origin
        self.provenance = provenance
    }

    public func pane(_ side: ComparisonDocumentSide) -> ComparisonDocumentPaneObservation {
        switch side {
        case .left: left
        case .right: right
        }
    }

    public var description: String {
        "ComparisonDocumentProductionObservation(scenario: \(scenarioID.rawValue), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["scenarioID": scenarioID, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public struct ComparisonDocumentEvidenceBundle: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let reference: ComparisonDocumentRevisionReference
    public let inventory: ComparisonDocumentRevisionReference
    public let build: ComparisonDocumentRevisionReference
    public let observations: [ComparisonDocumentProductionObservation]

    public init(
        reference: ComparisonDocumentRevisionReference,
        inventory: ComparisonDocumentRevisionReference,
        build: ComparisonDocumentRevisionReference,
        observations: [ComparisonDocumentProductionObservation]
    ) {
        self.reference = reference
        self.inventory = inventory
        self.build = build
        self.observations = observations
    }

    public var description: String {
        "ComparisonDocumentEvidenceBundle(observations: \(observations.count), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["observationCount": observations.count, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public struct ComparisonDocumentCoverageLimits: Hashable, Sendable {
    public static let hardMaximumObservations = 100_000
    public static let hardMaximumTrustedCollectors = 100_000
    public static let hardMaximumStringUTF8Bytes = 1 * 1_024 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 128 * 1_024 * 1_024
    public static let hardMaximumWorkUnits = 8 * 1_024 * 1_024 * 1_024
    public static let hardMaximumFindings = 100_000
    public static let hardMaximumCanonicalBytes = 512 * 1_024 * 1_024
    public static let hardMaximumArchiveBytes = 768 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = ComparisonDocumentCoverageLimits()

    public let maximumObservations: Int
    public let maximumTrustedCollectors: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumWorkUnits: Int
    public let maximumFindings: Int
    public let maximumCanonicalBytes: Int
    public let maximumArchiveBytes: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumObservations: Int = 32_768,
        maximumTrustedCollectors: Int = 1_024,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumWorkUnits: Int = Self.hardMaximumWorkUnits,
        maximumFindings: Int = 32 * 1_024,
        maximumCanonicalBytes: Int = Self.hardMaximumCanonicalBytes,
        maximumArchiveBytes: Int = Self.hardMaximumArchiveBytes,
        cancellationCheckInterval: Int = 64
    ) {
        self.maximumObservations = maximumObservations
        self.maximumTrustedCollectors = maximumTrustedCollectors
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumFindings = maximumFindings
        self.maximumCanonicalBytes = maximumCanonicalBytes
        self.maximumArchiveBytes = maximumArchiveBytes
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum ComparisonDocumentCoverageLimit: String, CaseIterable, Hashable, Sendable {
    case observations
    case trustedCollectors
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case workUnits
    case findings
    case canonicalBytes
    case archiveBytes
    case cancellationCheckInterval
}

public enum ComparisonDocumentCoverageError: Error, Equatable, LocalizedError, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case cancelled
    case impossibleScenario
    case comparisonResultUnavailable
    case inconsistentRevisionBindings
    case invalidLimit(ComparisonDocumentCoverageLimit)
    case observationLimitExceeded(maximum: Int)
    case stringTooLarge(field: String, maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximum: Int)
    case findingLimitExceeded(maximum: Int)
    case canonicalDataTooLarge(maximumBytes: Int)
    case archiveTooLarge(maximumBytes: Int)
    case invalidInventory(field: String)
    case invalidEvidence(field: String)
    case staleBuild
    case staleInventory
    case staleEvidence
    case invalidArchive
    case nonCanonicalArchive
    case receiptMismatch
    case replayClaimRejected
    case replayClaimDeadlineExceeded

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Comparison-document coverage audit was cancelled."
        case .impossibleScenario:
            "Comparison-document scenario is impossible."
        case .comparisonResultUnavailable:
            "Comparison-document binding requires a current or retained comparison result."
        case .inconsistentRevisionBindings:
            "Comparison-document revision bindings are inconsistent."
        case .invalidLimit(let limit):
            "Comparison-document coverage limit is invalid: \(limit.rawValue)."
        case .observationLimitExceeded(let maximum):
            "Comparison-document evidence exceeds the \(maximum)-observation limit."
        case .stringTooLarge(_, let maximum):
            "Comparison-document field <redacted> exceeds \(maximum) UTF-8 bytes; contents are redacted."
        case .totalStringsTooLarge(let maximum):
            "Comparison-document strings exceed \(maximum) UTF-8 bytes; contents are redacted."
        case .workLimitExceeded(let maximum):
            "Comparison-document audit exceeds \(maximum) work units."
        case .findingLimitExceeded(let maximum):
            "Comparison-document audit exceeds \(maximum) findings."
        case .canonicalDataTooLarge(let maximum):
            "Comparison-document canonical data exceeds \(maximum) bytes."
        case .archiveTooLarge(let maximum):
            "Comparison-document archive exceeds \(maximum) bytes."
        case .invalidInventory:
            "Comparison-document inventory is invalid at <redacted>; contents are redacted."
        case .invalidEvidence:
            "Comparison-document evidence is invalid at <redacted>; contents are redacted."
        case .staleBuild:
            "Comparison-document evidence belongs to another build identity or revision."
        case .staleInventory:
            "Comparison-document evidence belongs to another inventory identity or revision."
        case .staleEvidence:
            "Comparison-document evidence revision changed before receipt validation."
        case .invalidArchive:
            "Comparison-document archive has invalid framing or digest data."
        case .nonCanonicalArchive:
            "Comparison-document archive is valid but not canonical for current contents."
        case .receiptMismatch:
            "Comparison-document receipt no longer matches current canonical contents."
        case .replayClaimRejected:
            "Comparison-document production evidence run or nonce was already claimed."
        case .replayClaimDeadlineExceeded:
            "Comparison-document replay claim deadline was exceeded."
        }
    }

    public var description: String { errorDescription ?? "Comparison-document coverage error." }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["error": description], displayStyle: .enum)
    }
}

public enum ComparisonDocumentFindingSeverity: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case advisory
    case warning
    case error

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

public enum ComparisonDocumentFindingCode: String, CaseIterable, Hashable, Sendable {
    case duplicateScenarioEvidence
    case missingScenarioEvidence
    case unexpectedScenarioEvidence
    case revisionBindingMismatch
    case sourceShapeMismatch
    case documentDirtyStateMismatch
    case sourceAvailabilityMismatch
    case lifecycleMismatch
    case staleReasonMismatch
    case saveStateMismatch
    case saveContractMismatch
    case backupContractMismatch
    case productionProvenanceMissing
    case productionProvenanceInvalid
    case provenanceBuildMismatch
    case provenanceArtifactMismatch
    case untrustedCollector
    case productionCaptureMismatch
    case assertionOnlyEvidence
}

public enum ComparisonDocumentFindingSubject: Hashable, Sendable {
    case matrix
    case scenario(ComparisonDocumentScenarioID)
}

public struct ComparisonDocumentFinding: Identifiable, Hashable, Sendable {
    public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            comparisonDocumentCompareUTF8(left.rawValue, right.rawValue) < 0
        }
    }

    public let id: ID
    public let severity: ComparisonDocumentFindingSeverity
    public let code: ComparisonDocumentFindingCode
    public let subject: ComparisonDocumentFindingSubject
    /// Fixed wording. Document data, locations, identities, revisions, and provenance stay redacted.
    public let message: String

    fileprivate init(
        severity: ComparisonDocumentFindingSeverity,
        code: ComparisonDocumentFindingCode,
        subject: ComparisonDocumentFindingSubject,
        discriminator: Int = 0
    ) {
        self.severity = severity
        self.code = code
        self.subject = subject
        message = comparisonDocumentFindingMessage(code)
        let subjectValue: String
        switch subject {
        case .matrix: subjectValue = "matrix"
        case .scenario(let id): subjectValue = "scenario:\(id.rawValue)"
        }
        id = ID(
            rawValue: [code.rawValue, subjectValue, String(discriminator)]
                .map(comparisonDocumentFrame).joined()
        )
    }
}

public enum ComparisonDocumentCompletenessStatus: UInt8, CaseIterable, Hashable, Sendable {
    case complete
    case missing
    case duplicate
    case mismatched
    case invalid
    case assertionOnly
}

public struct ComparisonDocumentCompletenessCell: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public let scenario: ComparisonDocumentScenario
    public let expected: ComparisonDocumentExpectedState
    public let evidenceCount: Int
    public let status: ComparisonDocumentCompletenessStatus

    fileprivate init(
        requirement: ComparisonDocumentCoverageRequirement,
        evidenceCount: Int,
        status: ComparisonDocumentCompletenessStatus
    ) {
        scenario = requirement.scenario
        expected = requirement.expected
        self.evidenceCount = evidenceCount
        self.status = status
    }

    public var description: String {
        "ComparisonDocumentCompletenessCell(scenario: \(scenario.id.rawValue), count: \(evidenceCount), status: \(status), values: <redacted>)"
    }
    public var debugDescription: String { description }
}

public struct ComparisonDocumentCompletenessMatrix: Hashable, Sendable {
    public let cells: [ComparisonDocumentCompletenessCell]

    fileprivate init(cells: [ComparisonDocumentCompletenessCell]) {
        self.cells = cells
    }

    public var requiredCount: Int { cells.count }
    public var completeCount: Int { cells.count(where: { $0.status == .complete }) }
    public var missingCount: Int { cells.count(where: { $0.status == .missing }) }
    public var duplicateCount: Int { cells.count(where: { $0.status == .duplicate }) }
    public var mismatchedCount: Int { cells.count(where: { $0.status == .mismatched }) }
    public var invalidCount: Int { cells.count(where: { $0.status == .invalid }) }
    public var assertionOnlyCount: Int { cells.count(where: { $0.status == .assertionOnly }) }
    public var isComplete: Bool { completeCount == requiredCount }
}

public struct ComparisonDocumentCoverageReport: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let scopeStatement =
        "Deterministic validation of caller-supplied, revision-bound production measurements for the canonical two-document lifecycle matrix; not independent UI, filesystem, save-executor, backup-executor, or app-integration verification."

    public let formatVersion: Int
    public let inventory: ComparisonDocumentRevisionReference
    public let evidence: ComparisonDocumentRevisionReference
    public let trustedAuditTimeUnixMilliseconds: UInt64
    public let auditPolicySHA256: [UInt8]
    public let matrix: ComparisonDocumentCompletenessMatrix
    public let findings: [ComparisonDocumentFinding]

    public var highestSeverity: ComparisonDocumentFindingSeverity? { findings.first?.severity }
    public var containsErrors: Bool { findings.contains { $0.severity == .error } }
    public var isCompleteAndValid: Bool { matrix.isComplete && findings.isEmpty }

    fileprivate init(
        formatVersion: Int,
        inventory: ComparisonDocumentRevisionReference,
        evidence: ComparisonDocumentRevisionReference,
        trustedAuditTimeUnixMilliseconds: UInt64,
        auditPolicySHA256: [UInt8],
        matrix: ComparisonDocumentCompletenessMatrix,
        findings: [ComparisonDocumentFinding]
    ) {
        self.formatVersion = formatVersion
        self.inventory = inventory
        self.evidence = evidence
        self.trustedAuditTimeUnixMilliseconds = trustedAuditTimeUnixMilliseconds
        self.auditPolicySHA256 = auditPolicySHA256
        self.matrix = matrix
        self.findings = findings
    }

    public var description: String {
        "ComparisonDocumentCoverageReport(required: \(matrix.requiredCount), complete: \(matrix.completeCount), findings: \(findings.count), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "requiredCount": matrix.requiredCount,
                "completeCount": matrix.completeCount,
                "findingCount": findings.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct ComparisonDocumentCoverageArchive: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let data: Data
    public let sha256: [UInt8]

    fileprivate init(data: Data, sha256: [UInt8]) {
        self.data = data
        self.sha256 = sha256
    }

    public var description: String {
        "ComparisonDocumentCoverageArchive(bytes: \(data.count), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["byteCount": data.count, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// Deterministic receipt over canonical inventory, evidence, report, and archive bytes.
public struct ComparisonDocumentCoverageReceipt: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let formatVersion: Int
    public let build: ComparisonDocumentRevisionReference
    public let inventory: ComparisonDocumentRevisionReference
    public let evidence: ComparisonDocumentRevisionReference
    public let inventorySHA256: [UInt8]
    public let evidenceSHA256: [UInt8]
    public let auditPolicySHA256: [UInt8]
    public let reportSHA256: [UInt8]
    public let archiveSHA256: [UInt8]
    public let requiredScenarioCount: Int
    public let completeScenarioCount: Int
    public let findingCount: Int
    public let archiveByteCount: Int
    public let workUnits: Int

    fileprivate init(
        formatVersion: Int,
        build: ComparisonDocumentRevisionReference,
        inventory: ComparisonDocumentRevisionReference,
        evidence: ComparisonDocumentRevisionReference,
        inventorySHA256: [UInt8],
        evidenceSHA256: [UInt8],
        auditPolicySHA256: [UInt8],
        reportSHA256: [UInt8],
        archiveSHA256: [UInt8],
        requiredScenarioCount: Int,
        completeScenarioCount: Int,
        findingCount: Int,
        archiveByteCount: Int,
        workUnits: Int
    ) {
        self.formatVersion = formatVersion
        self.build = build
        self.inventory = inventory
        self.evidence = evidence
        self.inventorySHA256 = inventorySHA256
        self.evidenceSHA256 = evidenceSHA256
        self.auditPolicySHA256 = auditPolicySHA256
        self.reportSHA256 = reportSHA256
        self.archiveSHA256 = archiveSHA256
        self.requiredScenarioCount = requiredScenarioCount
        self.completeScenarioCount = completeScenarioCount
        self.findingCount = findingCount
        self.archiveByteCount = archiveByteCount
        self.workUnits = workUnits
    }

    public func validateCurrent(
        inventory currentInventory: ComparisonDocumentCoverageInventory,
        evidence currentEvidence: ComparisonDocumentEvidenceBundle,
        auditPolicy: ComparisonDocumentAuditPolicy,
        archive currentArchive: Data,
        limits: ComparisonDocumentCoverageLimits = .default,
        captureResolver: @escaping ComparisonDocumentCoverageMatrix.CaptureResolver,
        cancellationCheck: @escaping ComparisonDocumentCoverageMatrix.CancellationCheck = {
            Task.isCancelled
        }
    ) throws {
        try ComparisonDocumentCoverageMatrix.validate(
            receipt: self,
            archive: currentArchive,
            inventory: currentInventory,
            evidence: currentEvidence,
            auditPolicy: auditPolicy,
            limits: limits,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck
        )
    }

    public var description: String {
        "ComparisonDocumentCoverageReceipt(required: \(requiredScenarioCount), complete: \(completeScenarioCount), findings: \(findingCount), digests: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "requiredScenarioCount": requiredScenarioCount,
                "completeScenarioCount": completeScenarioCount,
                "findingCount": findingCount,
                "archiveByteCount": archiveByteCount,
                "workUnits": workUnits,
                "digests": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct ComparisonDocumentCoverageResult: Hashable, Sendable {
    public let report: ComparisonDocumentCoverageReport
    public let archive: ComparisonDocumentCoverageArchive
    public let receipt: ComparisonDocumentCoverageReceipt

    fileprivate init(
        report: ComparisonDocumentCoverageReport,
        archive: ComparisonDocumentCoverageArchive,
        receipt: ComparisonDocumentCoverageReceipt
    ) {
        self.report = report
        self.archive = archive
        self.receipt = receipt
    }
}

/// Bounded, UI-independent evidence audit for the unfinished two-document matrix.
public enum ComparisonDocumentCoverageMatrix: Sendable {
    public typealias CancellationCheck = @Sendable () -> Bool
    /// Resolver must cooperatively check cancellation and stream exactly `declaredByteCount` bytes.
    public typealias CaptureResolver =
        @Sendable (
            _ captureSHA256: [UInt8],
            _ declaredByteCount: Int,
            _ sink: ComparisonDocumentCaptureSink,
            _ cancellationCheck: CancellationCheck
        ) throws -> Void
    public static let reportFormatVersion = 4
    public static let archiveFormatVersion = 4
    public static let canonicalMatrixRevision = 4

    public static let canonicalScenarios: [ComparisonDocumentScenario] = {
        var scenarios: [ComparisonDocumentScenario] = []
        for sourceShape in ComparisonDocumentSourceShape.allCases {
            for dirtyState in ComparisonDocumentDirtyState.allCases {
                for leftIncident in ComparisonDocumentSideIncident.allCases {
                    for rightIncident in ComparisonDocumentSideIncident.allCases {
                        let incident = ComparisonDocumentIncident(
                            left: leftIncident,
                            right: rightIncident
                        )
                        for save in comparisonDocumentCanonicalSaveStates {
                            for backup in comparisonDocumentCanonicalBackupStates(
                                for: save,
                                incident: incident
                            ) {
                                if ComparisonDocumentScenario.isPossible(
                                    sourceShape: sourceShape,
                                    dirtyState: dirtyState,
                                    incident: incident,
                                    save: save,
                                    backup: backup
                                ) {
                                    scenarios.append(
                                        ComparisonDocumentScenario(
                                            validatedSourceShape: sourceShape,
                                            dirtyState: dirtyState,
                                            incident: incident,
                                            save: save,
                                            backup: backup
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        return scenarios.sorted()
    }()

    /// Canonical payload a trusted collector must persist for resolver-backed production proof.
    public static func canonicalCaptureData(
        for observation: ComparisonDocumentProductionObservation,
        limits: ComparisonDocumentCoverageLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try ComparisonDocumentValidation.validate(limits)
        let budget = ComparisonDocumentWorkBudget(
            maximum: limits.maximumWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try ComparisonDocumentValidation.preflightCapture(
            observation,
            limits: limits,
            budget: budget
        )
        return try comparisonDocumentCanonicalCaptureData(
            observation,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
    }

    public static func audit(
        inventory: ComparisonDocumentCoverageInventory,
        evidence: ComparisonDocumentEvidenceBundle,
        auditPolicy: ComparisonDocumentAuditPolicy,
        limits: ComparisonDocumentCoverageLimits = .default,
        captureResolver: @escaping CaptureResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> ComparisonDocumentCoverageResult {
        var context = try ComparisonDocumentAuditContext(
            inventory: inventory,
            evidence: evidence,
            auditPolicy: auditPolicy,
            limits: limits,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck,
            claimsReplayNonces: true
        )
        return try context.run()
    }

    /// Validates archive framing, checksum, canonical bytes, and exact inventory/evidence binding.
    public static func validate(
        archive: Data,
        inventory: ComparisonDocumentCoverageInventory,
        evidence: ComparisonDocumentEvidenceBundle,
        auditPolicy: ComparisonDocumentAuditPolicy,
        limits: ComparisonDocumentCoverageLimits = .default,
        captureResolver: @escaping CaptureResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws {
        let budget = try ComparisonDocumentValidation.makeBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try comparisonDocumentValidateArchive(
            archive,
            limits: limits,
            budget: budget
        )
        var context = try ComparisonDocumentAuditContext(
            inventory: inventory,
            evidence: evidence,
            auditPolicy: auditPolicy,
            limits: limits,
            captureResolver: captureResolver,
            budget: budget,
            claimsReplayNonces: false
        )
        let result = try context.run()
        guard try comparisonDocumentDataEquals(archive, result.archive.data, budget: budget) else {
            throw ComparisonDocumentCoverageError.nonCanonicalArchive
        }
        try context.claimReplays()
    }

    /// Exact compare-and-swap validation for references and canonical contents.
    public static func validate(
        receipt: ComparisonDocumentCoverageReceipt,
        archive: Data,
        inventory: ComparisonDocumentCoverageInventory,
        evidence: ComparisonDocumentEvidenceBundle,
        auditPolicy: ComparisonDocumentAuditPolicy,
        limits: ComparisonDocumentCoverageLimits = .default,
        captureResolver: @escaping CaptureResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws {
        let budget = try ComparisonDocumentValidation.makeBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        var strings = ComparisonDocumentStringBudget(limits: limits)
        for (reference, field) in [
            (inventory.build, "inventory.build"),
            (receipt.build, "receipt.build"),
            (inventory.reference, "inventory.reference"),
            (receipt.inventory, "receipt.inventory"),
            (evidence.reference, "evidence.reference"),
            (receipt.evidence, "receipt.evidence")
        ] {
            try ComparisonDocumentValidation.validateReference(
                reference,
                field: field,
                strings: &strings,
                budget: budget
            )
        }
        guard inventory.build == receipt.build else {
            throw ComparisonDocumentCoverageError.staleBuild
        }
        guard inventory.reference == receipt.inventory else {
            throw ComparisonDocumentCoverageError.staleInventory
        }
        guard evidence.reference == receipt.evidence else {
            throw ComparisonDocumentCoverageError.staleEvidence
        }
        try ComparisonDocumentValidation.validateReceipt(receipt, limits: limits, budget: budget)
        try comparisonDocumentValidateArchive(
            archive,
            limits: limits,
            budget: budget
        )
        var context = try ComparisonDocumentAuditContext(
            inventory: inventory,
            evidence: evidence,
            auditPolicy: auditPolicy,
            limits: limits,
            captureResolver: captureResolver,
            budget: budget,
            claimsReplayNonces: false
        )
        let result = try context.run()
        guard try comparisonDocumentDataEquals(archive, result.archive.data, budget: budget) else {
            throw ComparisonDocumentCoverageError.nonCanonicalArchive
        }
        guard result.receipt == receipt else {
            throw ComparisonDocumentCoverageError.receiptMismatch
        }
        try context.claimReplays()
    }
}

private struct ComparisonDocumentAssessment {
    var assertionOnly = false
    var invalid = false
    var mismatched = false
}

private struct ComparisonDocumentAuditContext {
    let inventory: ComparisonDocumentCoverageInventory
    let evidence: ComparisonDocumentEvidenceBundle
    let auditPolicy: ComparisonDocumentAuditPolicy
    let limits: ComparisonDocumentCoverageLimits
    let captureResolver: ComparisonDocumentCoverageMatrix.CaptureResolver
    let claimsReplayNonces: Bool
    var budget: ComparisonDocumentWorkBudget
    private var findings: [ComparisonDocumentFinding] = []
    private var findingIDs: Set<ComparisonDocumentFinding.ID> = []
    private var trustedCollectors: [ComparisonDocumentRevisionReference: ComparisonDocumentTrustedCollector] =
        [:]
    private var runByNonce: [[UInt8]: ComparisonDocumentRevisionReference] = [:]
    private var nonceByRun: [ComparisonDocumentRevisionReference: [UInt8]] = [:]
    private var replayClaims: Set<ComparisonDocumentReplayClaim> = []
    private var replayClaimsAreEligible = false
    private var replayArchiveSHA256: [UInt8]?

    init(
        inventory: ComparisonDocumentCoverageInventory,
        evidence: ComparisonDocumentEvidenceBundle,
        auditPolicy: ComparisonDocumentAuditPolicy,
        limits: ComparisonDocumentCoverageLimits,
        captureResolver: @escaping ComparisonDocumentCoverageMatrix.CaptureResolver,
        cancellationCheck: @escaping ComparisonDocumentCoverageMatrix.CancellationCheck,
        claimsReplayNonces: Bool
    ) throws {
        try ComparisonDocumentValidation.validate(limits)
        self.inventory = inventory
        self.evidence = evidence
        self.auditPolicy = auditPolicy
        self.limits = limits
        self.captureResolver = captureResolver
        self.claimsReplayNonces = claimsReplayNonces
        budget = ComparisonDocumentWorkBudget(
            maximum: limits.maximumWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try self.budget.checkCancellation()
    }

    init(
        inventory: ComparisonDocumentCoverageInventory,
        evidence: ComparisonDocumentEvidenceBundle,
        auditPolicy: ComparisonDocumentAuditPolicy,
        limits: ComparisonDocumentCoverageLimits,
        captureResolver: @escaping ComparisonDocumentCoverageMatrix.CaptureResolver,
        budget: ComparisonDocumentWorkBudget,
        claimsReplayNonces: Bool
    ) throws {
        try ComparisonDocumentValidation.validate(limits)
        self.inventory = inventory
        self.evidence = evidence
        self.auditPolicy = auditPolicy
        self.limits = limits
        self.captureResolver = captureResolver
        self.claimsReplayNonces = claimsReplayNonces
        self.budget = budget
        try self.budget.checkCancellation()
    }

    mutating func run() throws -> ComparisonDocumentCoverageResult {
        try ComparisonDocumentValidation.preflightTopLevelReferences(
            inventory: inventory,
            evidence: evidence,
            limits: limits,
            budget: budget
        )
        guard evidence.build == inventory.build else {
            throw ComparisonDocumentCoverageError.staleBuild
        }
        guard evidence.inventory == inventory.reference else {
            throw ComparisonDocumentCoverageError.staleInventory
        }
        try ComparisonDocumentValidation.preflight(
            inventory: inventory,
            evidence: evidence,
            auditPolicy: auditPolicy,
            limits: limits,
            budget: &budget
        )
        trustedCollectors = Dictionary(
            uniqueKeysWithValues: auditPolicy.trustedCollectors.map { ($0.reference, $0) }
        )

        let auditPolicyData = try comparisonDocumentCanonicalAuditPolicyData(
            auditPolicy,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        let auditPolicyDigest = try comparisonDocumentSHA256(auditPolicyData, budget: budget)

        let requirements = Dictionary(uniqueKeysWithValues: inventory.requirements.map { ($0.id, $0) })
        var observations: [ComparisonDocumentScenarioID: [ComparisonDocumentProductionObservation]] = [:]
        for observation in evidence.observations {
            try budget.charge()
            observations[observation.scenarioID, default: []].append(observation)
        }
        var unexpectedScenarioIDs = observations.keys.filter { requirements[$0] == nil }
        try comparisonDocumentSort(&unexpectedScenarioIDs) { left, right in
            try budget.charge()
            return left < right
        }
        for scenarioID in unexpectedScenarioIDs {
            try add(.error, .unexpectedScenarioEvidence, subject: .scenario(scenarioID))
        }

        var cells: [ComparisonDocumentCompletenessCell] = []
        cells.reserveCapacity(ComparisonDocumentCoverageMatrix.canonicalScenarios.count)
        for scenario in ComparisonDocumentCoverageMatrix.canonicalScenarios {
            try budget.charge()
            guard let requirement = requirements[scenario.id] else {
                throw ComparisonDocumentCoverageError.invalidInventory(field: "requirements")
            }
            let candidates = try canonicalObservations(observations[scenario.id] ?? [])
            if candidates.isEmpty {
                try add(.error, .missingScenarioEvidence, subject: .scenario(scenario.id))
                cells.append(
                    ComparisonDocumentCompletenessCell(
                        requirement: requirement,
                        evidenceCount: 0,
                        status: .missing
                    )
                )
                continue
            }
            if candidates.count > 1 {
                try add(
                    .error,
                    .duplicateScenarioEvidence,
                    subject: .scenario(scenario.id),
                    discriminator: candidates.count
                )
            }

            var combined = ComparisonDocumentAssessment()
            for (index, observation) in candidates.enumerated() {
                let assessment = try assess(
                    observation,
                    requirement: requirement,
                    discriminator: index
                )
                combined.assertionOnly = combined.assertionOnly || assessment.assertionOnly
                combined.invalid = combined.invalid || assessment.invalid
                combined.mismatched = combined.mismatched || assessment.mismatched
            }
            let status: ComparisonDocumentCompletenessStatus
            if candidates.count > 1 {
                status = .duplicate
            } else if combined.invalid {
                status = .invalid
            } else if combined.assertionOnly {
                status = .assertionOnly
            } else if combined.mismatched {
                status = .mismatched
            } else {
                status = .complete
            }
            cells.append(
                ComparisonDocumentCompletenessCell(
                    requirement: requirement,
                    evidenceCount: candidates.count,
                    status: status
                )
            )
        }

        var sortedFindings = findings
        try comparisonDocumentSort(&sortedFindings) { left, right in
            try budget.charge()
            if left.severity != right.severity { return left.severity > right.severity }
            if left.code != right.code {
                return try comparisonDocumentCompareUTF8(
                    left.code.rawValue,
                    right.code.rawValue,
                    budget: budget
                ) < 0
            }
            return try comparisonDocumentCompareUTF8(
                left.id.rawValue,
                right.id.rawValue,
                budget: budget
            ) < 0
        }
        let report = ComparisonDocumentCoverageReport(
            formatVersion: ComparisonDocumentCoverageMatrix.reportFormatVersion,
            inventory: inventory.reference,
            evidence: evidence.reference,
            trustedAuditTimeUnixMilliseconds: auditPolicy.trustedAuditTimeUnixMilliseconds,
            auditPolicySHA256: auditPolicyDigest,
            matrix: ComparisonDocumentCompletenessMatrix(cells: cells),
            findings: sortedFindings
        )
        let inventoryData = try comparisonDocumentCanonicalInventoryData(
            inventory,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        let evidenceData = try comparisonDocumentCanonicalEvidenceData(
            evidence,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        let reportData = try comparisonDocumentCanonicalReportData(
            report,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        let archiveData = try comparisonDocumentCanonicalArchiveData(
            inventoryData: inventoryData,
            evidenceData: evidenceData,
            reportData: reportData,
            maximumBytes: limits.maximumArchiveBytes,
            budget: budget
        )
        try budget.checkCancellation()

        let archiveDigest = try comparisonDocumentSHA256(archiveData, budget: budget)
        let archive = ComparisonDocumentCoverageArchive(data: archiveData, sha256: archiveDigest)
        let deterministicWorkUnits = try comparisonDocumentDeterministicWorkUnits(
            inventoryByteCount: inventoryData.count,
            evidenceByteCount: evidenceData.count,
            auditPolicyByteCount: auditPolicyData.count,
            reportByteCount: reportData.count,
            archiveByteCount: archiveData.count,
            observationCount: evidence.observations.count,
            findingCount: report.findings.count,
            maximum: limits.maximumWorkUnits
        )
        let receipt = ComparisonDocumentCoverageReceipt(
            formatVersion: ComparisonDocumentCoverageMatrix.reportFormatVersion,
            build: inventory.build,
            inventory: inventory.reference,
            evidence: evidence.reference,
            inventorySHA256: try comparisonDocumentSHA256(inventoryData, budget: budget),
            evidenceSHA256: try comparisonDocumentSHA256(evidenceData, budget: budget),
            auditPolicySHA256: auditPolicyDigest,
            reportSHA256: try comparisonDocumentSHA256(reportData, budget: budget),
            archiveSHA256: archiveDigest,
            requiredScenarioCount: report.matrix.requiredCount,
            completeScenarioCount: report.matrix.completeCount,
            findingCount: report.findings.count,
            archiveByteCount: archiveData.count,
            workUnits: deterministicWorkUnits
        )
        replayClaimsAreEligible = report.isCompleteAndValid
        replayArchiveSHA256 = archiveDigest
        if claimsReplayNonces {
            try claimReplays()
        }
        return ComparisonDocumentCoverageResult(report: report, archive: archive, receipt: receipt)
    }

    mutating func claimReplays() throws {
        guard replayClaimsAreEligible, !replayClaims.isEmpty,
            let replayArchiveSHA256
        else { return }
        var claims = Array(replayClaims)
        try comparisonDocumentSort(&claims) { left, right in
            if left.run != right.run {
                let idOrder = try comparisonDocumentCompareUTF8(
                    left.run.id.rawValue,
                    right.run.id.rawValue,
                    budget: budget
                )
                return idOrder == 0 ? left.run.revision < right.run.revision : idOrder < 0
            }
            return try comparisonDocumentBytesPrecede(left.nonce, right.nonce, budget: budget)
        }
        for claim in claims {
            try budget.charge(claim.nonce.count + 1)
        }
        try budget.checkCancellation()
        let context = ComparisonDocumentAuditPolicy.ReplayClaimContext(
            trustedAuditTimeUnixMilliseconds: auditPolicy.trustedAuditTimeUnixMilliseconds,
            deadlineUnixMilliseconds: auditPolicy.replayClaimDeadlineUnixMilliseconds,
            remainingWorkUnits: budget.remaining,
            cancellationCheck: budget.cancellationCheck
        )
        switch auditPolicy.claim(
            evidence: evidence.reference,
            archiveSHA256: replayArchiveSHA256,
            claims: claims,
            context: context
        ) {
        case .committed:
            replayClaims.removeAll(keepingCapacity: false)
            replayClaimsAreEligible = false
            self.replayArchiveSHA256 = nil
        case let result:
            throw comparisonDocumentReplayClaimError(
                result,
                maximumWorkUnits: limits.maximumWorkUnits
            )!
        }
    }

    private mutating func assess(
        _ observation: ComparisonDocumentProductionObservation,
        requirement: ComparisonDocumentCoverageRequirement,
        discriminator: Int
    ) throws -> ComparisonDocumentAssessment {
        try budget.charge()
        var result = ComparisonDocumentAssessment()
        let scenario = requirement.scenario
        for mismatch in comparisonDocumentMismatchFindings(observation, requirement: requirement) {
            result.mismatched = true
            try add(
                .error,
                mismatch.code,
                subject: .scenario(scenario.id),
                discriminator: comparisonDocumentMismatchDiscriminator(
                    base: discriminator,
                    side: mismatch.side
                )
            )
        }
        if observation.origin == .callerAssertion {
            result.assertionOnly = true
            try add(
                .error,
                .assertionOnlyEvidence,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        } else if let provenance = observation.provenance {
            let hasValidStructure = ComparisonDocumentValidation.isValid(provenance)
            let hasExpectedBuild = provenance.build == inventory.build
            let hasExpectedInventory = provenance.inventory == inventory.reference
            let hasExpectedEvidence = provenance.evidence == evidence.reference
            let hasExpectedArtifact = provenance.artifactSHA256 == inventory.buildArtifactSHA256
            let trustedCollector = trustedCollectors[provenance.collector]
            let hasTrustedCollector = trustedCollector != nil
            let hasFreshTime = comparisonDocumentCaptureTimeIsValid(
                provenance.capturedAtUnixMilliseconds,
                policy: auditPolicy
            )
            let sourceMatchesOrigin = comparisonDocumentProvenanceSourceMatchesOrigin(
                provenance.source,
                origin: observation.origin
            )
            let registeredRun = runByNonce[provenance.runNonce]
            let registeredNonce = nonceByRun[provenance.run]
            let nonceMatchesRun =
                (registeredRun == nil || registeredRun == provenance.run)
                && (registeredNonce == nil || registeredNonce == provenance.runNonce)
            if !hasExpectedBuild {
                result.invalid = true
                try add(
                    .error,
                    .provenanceBuildMismatch,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if !hasValidStructure {
                result.invalid = true
                try add(
                    .error,
                    .productionProvenanceInvalid,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if !hasExpectedInventory || !hasExpectedEvidence || !hasFreshTime
                || !sourceMatchesOrigin || !nonceMatchesRun
            {
                result.invalid = true
                try add(
                    .error,
                    .productionProvenanceInvalid,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if !hasExpectedArtifact {
                result.invalid = true
                try add(
                    .error,
                    .provenanceArtifactMismatch,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if !hasTrustedCollector {
                result.invalid = true
                try add(
                    .error,
                    .untrustedCollector,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if hasValidStructure && hasExpectedBuild && hasExpectedInventory && hasExpectedEvidence
                && hasExpectedArtifact && hasTrustedCollector && hasFreshTime && sourceMatchesOrigin
                && nonceMatchesRun
            {
                guard let trustedCollector else {
                    throw ComparisonDocumentCoverageError.invalidEvidence(
                        field: "provenance.collector"
                    )
                }
                let captureMatches = try captureMatches(
                    observation,
                    provenance: provenance,
                    trustedCollector: trustedCollector
                )
                if !captureMatches {
                    result.invalid = true
                    try add(
                        .error,
                        .productionCaptureMismatch,
                        subject: .scenario(scenario.id),
                        discriminator: discriminator
                    )
                } else {
                    runByNonce[provenance.runNonce] = provenance.run
                    nonceByRun[provenance.run] = provenance.runNonce
                    replayClaims.insert(
                        ComparisonDocumentReplayClaim(
                            run: provenance.run,
                            nonce: provenance.runNonce
                        )
                    )
                }
            }
        } else {
            result.invalid = true
            try add(
                .error,
                .productionProvenanceMissing,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        return result
    }

    private mutating func canonicalObservations(
        _ observations: [ComparisonDocumentProductionObservation]
    ) throws -> [ComparisonDocumentProductionObservation] {
        var totalBytes = 0
        var records: [(data: Data, observation: ComparisonDocumentProductionObservation)] = []
        records.reserveCapacity(observations.count)
        for observation in observations {
            let data = try comparisonDocumentCanonicalObservationData(
                observation,
                maximumBytes: limits.maximumCanonicalBytes,
                budget: budget
            )
            guard data.count <= limits.maximumCanonicalBytes - totalBytes else {
                throw ComparisonDocumentCoverageError.canonicalDataTooLarge(
                    maximumBytes: limits.maximumCanonicalBytes
                )
            }
            totalBytes += data.count
            try budget.charge()
            records.append((data, observation))
        }
        try comparisonDocumentSort(&records) { left, right in
            try comparisonDocumentDataPrecedes(left.data, right.data, budget: budget)
        }
        return records.map(\.observation)
    }

    private mutating func captureMatches(
        _ observation: ComparisonDocumentProductionObservation,
        provenance: ComparisonDocumentEvidenceProvenance,
        trustedCollector: ComparisonDocumentTrustedCollector
    ) throws -> Bool {
        let expectedCapture = try comparisonDocumentCanonicalCaptureData(
            observation,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        guard provenance.captureByteCount == expectedCapture.count,
            try comparisonDocumentSHA256(expectedCapture, budget: budget) == provenance.captureSHA256
        else { return false }
        let signatureIsValid: Bool
        do {
            signatureIsValid = try Curve25519.Signing.PublicKey(
                rawRepresentation: trustedCollector.ed25519PublicKey
            ).isValidSignature(provenance.collectorSignature, for: expectedCapture)
        } catch {
            signatureIsValid = false
        }
        guard signatureIsValid else { return false }

        let sink = ComparisonDocumentCaptureSink(
            maximumByteCount: provenance.captureByteCount,
            budget: budget,
            expected: expectedCapture
        )
        try budget.checkCancellation()
        return try comparisonDocumentResolveCapture(
            captureResolver,
            digest: provenance.captureSHA256,
            declaredByteCount: provenance.captureByteCount,
            sink: sink,
            cancellationCheck: budget.cancellationCheck
        )
    }

    private mutating func add(
        _ severity: ComparisonDocumentFindingSeverity,
        _ code: ComparisonDocumentFindingCode,
        subject: ComparisonDocumentFindingSubject,
        discriminator: Int = 0
    ) throws {
        try budget.charge()
        let finding = ComparisonDocumentFinding(
            severity: severity,
            code: code,
            subject: subject,
            discriminator: discriminator
        )
        guard findingIDs.insert(finding.id).inserted else { return }
        guard findings.count < limits.maximumFindings else {
            throw ComparisonDocumentCoverageError.findingLimitExceeded(maximum: limits.maximumFindings)
        }
        findings.append(finding)
    }
}

private func comparisonDocumentMismatchFindings(
    _ observation: ComparisonDocumentProductionObservation,
    requirement: ComparisonDocumentCoverageRequirement
) -> [(code: ComparisonDocumentFindingCode, side: ComparisonDocumentSide?)] {
    var findings: [(ComparisonDocumentFindingCode, ComparisonDocumentSide?)] = []
    if observation.bindings != requirement.bindings {
        findings.append((.revisionBindingMismatch, nil))
    }
    for side in ComparisonDocumentSide.allCases {
        let observed = observation.pane(side)
        let expected = requirement.expected.pane(side)
        if observed.sourceKind != expected.sourceKind || observed.isLoaded != expected.isLoaded
            || observed.isEditable != expected.isEditable || observed.isUntitled != expected.isUntitled
        {
            findings.append((.sourceShapeMismatch, side))
        }
        if observed.isDirty != expected.isDirty {
            findings.append((.documentDirtyStateMismatch, side))
        }
        if observed.diskState != expected.diskState {
            findings.append((.sourceAvailabilityMismatch, side))
        }
    }
    if observation.lifecycle.phase != requirement.expected.lifecyclePhase
        || !observation.lifecycle.hasRetainedResult
        || (requirement.expected.lifecyclePhase == .current && !observation.lifecycle.hasCurrentResult)
        || (requirement.expected.lifecyclePhase == .stale && observation.lifecycle.hasCurrentResult)
    {
        findings.append((.lifecycleMismatch, nil))
    }
    let staleReasonMatches =
        requirement.expected.lifecyclePhase == .current
        ? observation.lifecycle.staleReason == nil
        : observation.lifecycle.staleReason.map {
            requirement.expected.permittedStaleReasons.contains($0)
        } ?? false
    if !staleReasonMatches {
        findings.append((.staleReasonMismatch, nil))
    }
    if observation.save != requirement.expected.save {
        findings.append((.saveStateMismatch, nil))
    }
    if observation.saveExecutorContract != requirement.expected.saveExecutorContract {
        findings.append((.saveContractMismatch, nil))
    }
    if observation.backup != requirement.expected.backup {
        findings.append((.backupContractMismatch, nil))
    }
    return findings
}

private func comparisonDocumentMismatchDiscriminator(
    base: Int,
    side: ComparisonDocumentSide?
) -> Int {
    side.map { base * 2 + Int($0.rawValue) } ?? base
}

func comparisonDocumentResolveCapture(
    _ resolver: ComparisonDocumentCoverageMatrix.CaptureResolver,
    digest: [UInt8],
    declaredByteCount: Int,
    sink: ComparisonDocumentCaptureSink,
    cancellationCheck: @escaping ComparisonDocumentCoverageMatrix.CancellationCheck
) throws -> Bool {
    do {
        try resolver(digest, declaredByteCount, sink, cancellationCheck)
    } catch ComparisonDocumentCoverageError.cancelled {
        throw ComparisonDocumentCoverageError.cancelled
    } catch let error as ComparisonDocumentCoverageError {
        switch error {
        case .cancelled, .workLimitExceeded:
            throw error
        default:
            return false
        }
    } catch is CancellationError {
        throw ComparisonDocumentCoverageError.cancelled
    } catch {
        return false
    }
    let capture: (byteCount: Int, sha256: [UInt8], matchesExpected: Bool)
    do {
        capture = try sink.finish()
    } catch {
        return false
    }
    return capture.byteCount == declaredByteCount
        && capture.sha256 == digest
        && capture.matchesExpected
}

func comparisonDocumentReplayClaimError(
    _ result: ComparisonDocumentAuditPolicy.ReplayClaimResult,
    maximumWorkUnits: Int
) -> ComparisonDocumentCoverageError? {
    switch result {
    case .committed: nil
    case .rejectedReplay: .replayClaimRejected
    case .cancelled: .cancelled
    case .deadlineExceeded: .replayClaimDeadlineExceeded
    case .workLimitExceeded: .workLimitExceeded(maximum: maximumWorkUnits)
    }
}

func comparisonDocumentRegisterLineageForTesting(
    _ bindings: [ComparisonDocumentRevisionBindings]
) throws {
    var registry = ComparisonDocumentLineageRegistry()
    for value in bindings { try registry.register(value) }
}

func comparisonDocumentCanonicalInventoryDataForTesting(
    _ inventory: ComparisonDocumentCoverageInventory,
    limits: ComparisonDocumentCoverageLimits = .default
) throws -> Data {
    let budget = try comparisonDocumentTestingBudget(limits)
    return try comparisonDocumentCanonicalInventoryData(
        inventory,
        maximumBytes: limits.maximumCanonicalBytes,
        budget: budget
    )
}

func comparisonDocumentCanonicalEvidenceDataForTesting(
    _ evidence: ComparisonDocumentEvidenceBundle,
    limits: ComparisonDocumentCoverageLimits = .default
) throws -> Data {
    let budget = try comparisonDocumentTestingBudget(limits)
    return try comparisonDocumentCanonicalEvidenceData(
        evidence,
        maximumBytes: limits.maximumCanonicalBytes,
        budget: budget
    )
}

func comparisonDocumentCanonicalAuditPolicyDataForTesting(
    _ policy: ComparisonDocumentAuditPolicy,
    limits: ComparisonDocumentCoverageLimits = .default
) throws -> Data {
    let budget = try comparisonDocumentTestingBudget(limits)
    return try comparisonDocumentCanonicalAuditPolicyData(
        policy,
        maximumBytes: limits.maximumCanonicalBytes,
        budget: budget
    )
}

func comparisonDocumentCanonicalDataCopyForTesting(
    _ value: Data,
    limits: ComparisonDocumentCoverageLimits = .default,
    cancellationCheck: @escaping ComparisonDocumentCoverageMatrix.CancellationCheck = { false }
) throws -> Data {
    let budget = try ComparisonDocumentValidation.makeBudget(
        limits: limits,
        cancellationCheck: cancellationCheck
    )
    var writer = ComparisonDocumentCanonicalWriter(
        maximumBytes: limits.maximumCanonicalBytes,
        budget: budget
    )
    try writer.append(value)
    return writer.data
}

func comparisonDocumentMismatchAssessmentForTesting(
    _ observation: ComparisonDocumentProductionObservation,
    scenario: ComparisonDocumentScenario,
    bindings: ComparisonDocumentRevisionBindings,
    discriminator: Int = 0
) -> (
    status: ComparisonDocumentCompletenessStatus,
    findingCodes: Set<ComparisonDocumentFindingCode>,
    findingIDs: Set<ComparisonDocumentFinding.ID>
) {
    let requirement = ComparisonDocumentCoverageRequirement(scenario: scenario, bindings: bindings)
    let mismatches = comparisonDocumentMismatchFindings(observation, requirement: requirement)
    let findings = mismatches.map { mismatch in
        ComparisonDocumentFinding(
            severity: .error,
            code: mismatch.code,
            subject: .scenario(scenario.id),
            discriminator: comparisonDocumentMismatchDiscriminator(
                base: discriminator,
                side: mismatch.side
            )
        )
    }
    return (
        mismatches.isEmpty ? .complete : .mismatched,
        Set(findings.map(\.code)),
        Set(findings.map(\.id))
    )
}

func comparisonDocumentProvenanceIsValidForTesting(
    _ provenance: ComparisonDocumentEvidenceProvenance
) -> Bool {
    ComparisonDocumentValidation.isValid(provenance)
}

private func comparisonDocumentTestingBudget(
    _ limits: ComparisonDocumentCoverageLimits
) throws -> ComparisonDocumentWorkBudget {
    try ComparisonDocumentValidation.makeBudget(limits: limits, cancellationCheck: { false })
}

private enum ComparisonDocumentValidation {
    static func makeBudget(
        limits: ComparisonDocumentCoverageLimits,
        cancellationCheck: @escaping ComparisonDocumentCoverageMatrix.CancellationCheck
    ) throws -> ComparisonDocumentWorkBudget {
        try validate(limits)
        let budget = ComparisonDocumentWorkBudget(
            maximum: limits.maximumWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try budget.checkCancellation()
        return budget
    }

    static func validate(_ limits: ComparisonDocumentCoverageLimits) throws {
        guard
            (1...ComparisonDocumentCoverageLimits.hardMaximumObservations).contains(
                limits.maximumObservations
            )
        else { throw ComparisonDocumentCoverageError.invalidLimit(.observations) }
        guard
            (1...ComparisonDocumentCoverageLimits.hardMaximumTrustedCollectors).contains(
                limits.maximumTrustedCollectors
            )
        else { throw ComparisonDocumentCoverageError.invalidLimit(.trustedCollectors) }
        guard
            (1...ComparisonDocumentCoverageLimits.hardMaximumStringUTF8Bytes).contains(
                limits.maximumStringUTF8Bytes
            )
        else { throw ComparisonDocumentCoverageError.invalidLimit(.stringUTF8Bytes) }
        guard
            (1...ComparisonDocumentCoverageLimits.hardMaximumTotalStringUTF8Bytes).contains(
                limits.maximumTotalStringUTF8Bytes
            ), limits.maximumTotalStringUTF8Bytes >= limits.maximumStringUTF8Bytes
        else {
            throw ComparisonDocumentCoverageError.invalidLimit(.totalStringUTF8Bytes)
        }
        guard
            (1...ComparisonDocumentCoverageLimits.hardMaximumWorkUnits).contains(
                limits.maximumWorkUnits
            )
        else { throw ComparisonDocumentCoverageError.invalidLimit(.workUnits) }
        guard
            (1...ComparisonDocumentCoverageLimits.hardMaximumFindings).contains(
                limits.maximumFindings
            )
        else { throw ComparisonDocumentCoverageError.invalidLimit(.findings) }
        guard
            (1...ComparisonDocumentCoverageLimits.hardMaximumCanonicalBytes).contains(
                limits.maximumCanonicalBytes
            )
        else { throw ComparisonDocumentCoverageError.invalidLimit(.canonicalBytes) }
        guard
            (1...ComparisonDocumentCoverageLimits.hardMaximumArchiveBytes).contains(
                limits.maximumArchiveBytes
            ), limits.maximumArchiveBytes >= limits.maximumCanonicalBytes
        else {
            throw ComparisonDocumentCoverageError.invalidLimit(.archiveBytes)
        }
        guard
            (1...ComparisonDocumentCoverageLimits.hardMaximumCancellationCheckInterval).contains(
                limits.cancellationCheckInterval
            )
        else { throw ComparisonDocumentCoverageError.invalidLimit(.cancellationCheckInterval) }
    }

    static func validateReference(
        _ reference: ComparisonDocumentRevisionReference,
        field: String,
        strings: inout ComparisonDocumentStringBudget,
        budget: ComparisonDocumentWorkBudget
    ) throws {
        var budget = budget
        try validate(
            reference,
            field: field,
            strings: &strings,
            budget: &budget,
            inventory: false
        )
    }

    static func validateReceipt(
        _ receipt: ComparisonDocumentCoverageReceipt,
        limits: ComparisonDocumentCoverageLimits,
        budget: ComparisonDocumentWorkBudget
    ) throws {
        try budget.charge()
        guard receipt.formatVersion == ComparisonDocumentCoverageMatrix.reportFormatVersion,
            comparisonDocumentIsValidDigest(receipt.inventorySHA256),
            comparisonDocumentIsValidDigest(receipt.evidenceSHA256),
            comparisonDocumentIsValidDigest(receipt.auditPolicySHA256),
            comparisonDocumentIsValidDigest(receipt.reportSHA256),
            comparisonDocumentIsValidDigest(receipt.archiveSHA256),
            receipt.requiredScenarioCount == ComparisonDocumentCoverageMatrix.canonicalScenarios.count,
            (0...receipt.requiredScenarioCount).contains(receipt.completeScenarioCount),
            (0...limits.maximumFindings).contains(receipt.findingCount),
            (0...limits.maximumArchiveBytes).contains(receipt.archiveByteCount),
            (0...limits.maximumWorkUnits).contains(receipt.workUnits)
        else {
            throw ComparisonDocumentCoverageError.receiptMismatch
        }
    }

    static func preflightTopLevelReferences(
        inventory: ComparisonDocumentCoverageInventory,
        evidence: ComparisonDocumentEvidenceBundle,
        limits: ComparisonDocumentCoverageLimits,
        budget: ComparisonDocumentWorkBudget
    ) throws {
        var budget = budget
        var strings = ComparisonDocumentStringBudget(limits: limits)
        for (reference, field, inventoryField) in [
            (inventory.reference, "inventory.reference", true),
            (inventory.build, "inventory.build", true),
            (evidence.reference, "evidence.reference", false),
            (evidence.inventory, "evidence.inventory", false),
            (evidence.build, "evidence.build", false)
        ] {
            try validate(
                reference,
                field: field,
                strings: &strings,
                budget: &budget,
                inventory: inventoryField
            )
        }
    }

    static func preflight(
        inventory: ComparisonDocumentCoverageInventory,
        evidence: ComparisonDocumentEvidenceBundle,
        auditPolicy: ComparisonDocumentAuditPolicy,
        limits: ComparisonDocumentCoverageLimits,
        budget: inout ComparisonDocumentWorkBudget
    ) throws {
        guard evidence.observations.count <= limits.maximumObservations else {
            throw ComparisonDocumentCoverageError.observationLimitExceeded(
                maximum: limits.maximumObservations
            )
        }
        guard
            inventory.requirements.count
                == ComparisonDocumentCoverageMatrix.canonicalScenarios.count
        else {
            throw ComparisonDocumentCoverageError.invalidInventory(field: "requirements")
        }
        var strings = ComparisonDocumentStringBudget(limits: limits)
        try validate(
            inventory.reference,
            field: "inventory.reference",
            strings: &strings,
            budget: &budget,
            inventory: true
        )
        try validate(
            inventory.build,
            field: "inventory.build",
            strings: &strings,
            budget: &budget,
            inventory: true
        )
        guard comparisonDocumentIsValidDigest(inventory.buildArtifactSHA256),
            !auditPolicy.trustedCollectors.isEmpty,
            auditPolicy.trustedCollectors.count <= limits.maximumTrustedCollectors,
            !auditPolicy.trustedLocationKeyReferences.isEmpty,
            auditPolicy.trustedAuditTimeUnixMilliseconds > 0,
            auditPolicy.maximumCaptureAgeMilliseconds > 0,
            auditPolicy.replayClaimDeadlineUnixMilliseconds
                >= auditPolicy.trustedAuditTimeUnixMilliseconds
        else {
            throw ComparisonDocumentCoverageError.invalidInventory(field: "provenanceRoots")
        }
        try validate(
            auditPolicy.replayPolicy,
            field: "auditPolicy.replayPolicy",
            strings: &strings,
            budget: &budget,
            inventory: true
        )
        var collectors: Set<ComparisonDocumentRevisionReference> = []
        for collector in auditPolicy.trustedCollectors {
            try validate(
                collector.reference,
                field: "auditPolicy.trustedCollectors",
                strings: &strings,
                budget: &budget,
                inventory: true
            )
            guard collector.ed25519PublicKey.count == 32,
                collectors.insert(collector.reference).inserted
            else {
                throw ComparisonDocumentCoverageError.invalidInventory(field: "auditPolicy.trustedCollectors")
            }
        }
        for keyReference in auditPolicy.trustedLocationKeyReferences {
            try strings.consume(
                keyReference.rawValue,
                field: "auditPolicy.trustedLocationKeyReferences",
                budget: &budget
            )
            guard comparisonDocumentIsValidIdentifier(keyReference.rawValue) else {
                throw ComparisonDocumentCoverageError.invalidInventory(
                    field: "auditPolicy.trustedLocationKeyReferences"
                )
            }
        }
        try validate(
            evidence.reference,
            field: "evidence.reference",
            strings: &strings,
            budget: &budget,
            inventory: false
        )
        try validate(
            evidence.inventory,
            field: "evidence.inventory",
            strings: &strings,
            budget: &budget,
            inventory: false
        )
        try validate(
            evidence.build,
            field: "evidence.build",
            strings: &strings,
            budget: &budget,
            inventory: false
        )

        let canonicalByID = Dictionary(
            uniqueKeysWithValues: ComparisonDocumentCoverageMatrix.canonicalScenarios.map { ($0.id, $0) }
        )
        var requirementIDs: Set<ComparisonDocumentScenarioID> = []
        var lineage = ComparisonDocumentLineageRegistry()
        for requirement in inventory.requirements {
            try budget.charge()
            guard requirementIDs.insert(requirement.id).inserted,
                canonicalByID[requirement.id] == requirement.scenario,
                requirement.expected == ComparisonDocumentExpectedState(scenario: requirement.scenario)
            else {
                throw ComparisonDocumentCoverageError.invalidInventory(field: "requirements")
            }
            try validate(
                requirement.bindings,
                scenario: requirement.scenario,
                trustedLocationKeyReferences: auditPolicy.trustedLocationKeyReferences,
                field: "inventory.requirement.bindings",
                strings: &strings,
                budget: &budget,
                inventory: true
            )
            try lineage.register(requirement.bindings)
        }
        guard requirementIDs == Set(canonicalByID.keys) else {
            throw ComparisonDocumentCoverageError.invalidInventory(field: "requirements")
        }
        for observation in evidence.observations {
            try budget.charge()
            try validate(
                observation.bindings,
                scenario: canonicalByID[observation.scenarioID],
                trustedLocationKeyReferences: auditPolicy.trustedLocationKeyReferences,
                field: "evidence.observation.bindings",
                strings: &strings,
                budget: &budget,
                inventory: false
            )
            if let provenance = observation.provenance {
                try validate(
                    provenance.build,
                    field: "evidence.provenance.build",
                    strings: &strings,
                    budget: &budget,
                    inventory: false
                )
                try validate(
                    provenance.inventory,
                    field: "evidence.provenance.inventory",
                    strings: &strings,
                    budget: &budget,
                    inventory: false
                )
                try validate(
                    provenance.evidence,
                    field: "evidence.provenance.evidence",
                    strings: &strings,
                    budget: &budget,
                    inventory: false
                )
                try validate(
                    provenance.collector,
                    field: "evidence.provenance.collector",
                    strings: &strings,
                    budget: &budget,
                    inventory: false
                )
                try validate(
                    provenance.run,
                    field: "evidence.provenance.run",
                    strings: &strings,
                    budget: &budget,
                    inventory: false
                )
            }
        }
    }

    static func isValid(_ provenance: ComparisonDocumentEvidenceProvenance) -> Bool {
        provenance.capturedAtUnixMilliseconds > 0
            && (16...64).contains(provenance.runNonce.count)
            && comparisonDocumentIsValidDigest(provenance.artifactSHA256)
            && comparisonDocumentIsValidDigest(provenance.captureSHA256)
            && provenance.captureByteCount > 0
            && provenance.collectorSignature.count == 64
            && comparisonDocumentIsValidIdentifier(provenance.build.id.rawValue)
            && comparisonDocumentIsValidIdentifier(provenance.inventory.id.rawValue)
            && comparisonDocumentIsValidIdentifier(provenance.evidence.id.rawValue)
            && comparisonDocumentIsValidIdentifier(provenance.collector.id.rawValue)
            && comparisonDocumentIsValidIdentifier(provenance.run.id.rawValue)
    }

    static func preflightCapture(
        _ observation: ComparisonDocumentProductionObservation,
        limits: ComparisonDocumentCoverageLimits,
        budget: ComparisonDocumentWorkBudget
    ) throws {
        var budget = budget
        var strings = ComparisonDocumentStringBudget(limits: limits)
        try budget.charge()
        let scenario = comparisonDocumentCanonicalScenariosByID[observation.scenarioID]
        guard scenario != nil else {
            throw ComparisonDocumentCoverageError.invalidEvidence(field: "capture.scenario")
        }
        try validate(
            observation.bindings,
            scenario: scenario,
            trustedLocationKeyReferences: nil,
            field: "capture.bindings",
            strings: &strings,
            budget: &budget,
            inventory: false
        )
        if let provenance = observation.provenance {
            try validate(
                provenance.build,
                field: "capture.provenance.build",
                strings: &strings,
                budget: &budget,
                inventory: false
            )
            try validate(
                provenance.inventory,
                field: "capture.provenance.inventory",
                strings: &strings,
                budget: &budget,
                inventory: false
            )
            try validate(
                provenance.evidence,
                field: "capture.provenance.evidence",
                strings: &strings,
                budget: &budget,
                inventory: false
            )
            try validate(
                provenance.collector,
                field: "capture.provenance.collector",
                strings: &strings,
                budget: &budget,
                inventory: false
            )
            try validate(
                provenance.run,
                field: "capture.provenance.run",
                strings: &strings,
                budget: &budget,
                inventory: false
            )
        }
        try budget.checkCancellation()
    }

    private static func validate(
        _ bindings: ComparisonDocumentRevisionBindings,
        scenario: ComparisonDocumentScenario?,
        trustedLocationKeyReferences: Set<ComparisonDocumentStableID>?,
        field: String,
        strings: inout ComparisonDocumentStringBudget,
        budget: inout ComparisonDocumentWorkBudget,
        inventory: Bool
    ) throws {
        guard bindings.sides.count == 2,
            bindings.comparison.sources.count == 2,
            bindings.comparison.resultSources.count == 2,
            bindings.comparison.operation.sources.count == 2,
            comparisonDocumentIsValidUUID(bindings.comparison.openRequest.rawValue),
            comparisonDocumentIsValidUUID(bindings.comparison.operation.operationID)
        else {
            throw invalid(field: field, inventory: inventory)
        }
        for reference in [
            bindings.comparison.comparison,
            bindings.comparison.inputs,
            bindings.comparison.result,
            bindings.comparison.resultInputs,
            bindings.comparison.operation.comparison,
            bindings.comparison.operation.inputs
        ] {
            try validate(
                reference,
                field: field,
                strings: &strings,
                budget: &budget,
                inventory: inventory
            )
        }
        for source in bindings.comparison.sources + bindings.comparison.resultSources
            + bindings.comparison.operation.sources
        {
            try validate(
                source.source,
                field: field,
                strings: &strings,
                budget: &budget,
                inventory: inventory
            )
        }
        for side in bindings.sides {
            try validate(
                side.lifecycleSource,
                field: field,
                strings: &strings,
                budget: &budget,
                inventory: inventory
            )
            try validate(
                side.resultLifecycleSource,
                field: field,
                strings: &strings,
                budget: &budget,
                inventory: inventory
            )
            try consumeLocationReferences(side, field: field, strings: &strings, budget: &budget)
        }
        guard bindings.sides.map(\.lifecycleSource) == bindings.comparison.sources.map(\.source),
            bindings.sides.map(\.resultLifecycleSource)
                == bindings.comparison.resultSources.map(\.source),
            bindings.comparison.operation.comparison.id == bindings.comparison.comparison.id,
            bindings.comparison.operation.comparison.revision
                == bindings.comparison.operation.startedAtGeneration,
            bindings.comparison.operation.inputs == bindings.comparison.resultInputs,
            bindings.comparison.operation.sources == bindings.comparison.resultSources,
            bindings.comparison.result.revision
                > bindings.comparison.operation.startedAtGeneration
        else {
            throw invalid(field: field, inventory: inventory)
        }
        if let scenario {
            switch scenario.expectedLifecyclePhase {
            case .current:
                let sourceRevisionsAreCurrent = bindings.sides.allSatisfy { side in
                    side.resultSource == side.openedSource && side.currentSource == side.resultSource
                }
                guard bindings.comparison.resultInputs == bindings.comparison.inputs,
                    bindings.comparison.resultSources == bindings.comparison.sources,
                    bindings.comparison.comparison.revision
                        >= bindings.comparison.result.revision,
                    sourceRevisionsAreCurrent
                else {
                    throw invalid(field: field, inventory: inventory)
                }
            case .stale:
                let changedSides = scenario.expectedChangedSides
                let actualChangedSides = zip(
                    bindings.comparison.resultSources,
                    bindings.comparison.sources
                ).compactMap { result, current in
                    result.source == current.source ? nil : current.side
                }
                let sourceReferencesAdvancedExactly = ComparisonDocumentSide.allCases.allSatisfy(
                    { side in
                        let current = bindings.comparison.sources[Int(side.rawValue)].source
                        let result = bindings.comparison.resultSources[Int(side.rawValue)].source
                        return changedSides.contains(side)
                            ? comparisonDocumentRevisionAdvanced(current, from: result)
                            : current == result
                    }
                )
                guard bindings.comparison.resultInputs != bindings.comparison.inputs,
                    actualChangedSides == changedSides,
                    comparisonDocumentRevisionAdvanced(
                        bindings.comparison.inputs,
                        from: bindings.comparison.resultInputs
                    ),
                    sourceReferencesAdvancedExactly,
                    bindings.comparison.comparison.revision
                        > bindings.comparison.result.revision
                else {
                    throw invalid(field: field, inventory: inventory)
                }
            case .empty, .oneSideLoaded, .loading, .refreshing, .failed, .canceled:
                throw invalid(field: field, inventory: inventory)
            }
        }
        for side in bindings.sides {
            try budget.charge()
            let incidentSourceIsValid =
                side.incidentSource.map {
                    comparisonDocumentIsValidSourceRevision(
                        $0,
                        trustedLocationKeyReferences: trustedLocationKeyReferences
                    )
                } ?? true
            let currentSourceIsValid =
                side.currentSource.map {
                    comparisonDocumentIsValidSourceRevision(
                        $0,
                        trustedLocationKeyReferences: trustedLocationKeyReferences
                    )
                } ?? true
            let paneUpdateSourceIsValid =
                side.saveOperation?.paneUpdateObservedSource.map {
                    comparisonDocumentIsValidSourceRevision(
                        $0,
                        trustedLocationKeyReferences: trustedLocationKeyReferences
                    )
                } ?? true
            let completedBackupIsValid =
                side.completedBackup.map {
                    comparisonDocumentIsValidCompletedBackup(
                        $0,
                        trustedLocationKeyReferences: trustedLocationKeyReferences
                    )
                } ?? true
            guard comparisonDocumentIsValidDigest(side.document.contentAndMetadataSHA256),
                comparisonDocumentIsValidUUID(side.document.identity),
                comparisonDocumentIsValidDigest(side.document.encodedContentSHA256),
                comparisonDocumentIsValidDigest(side.document.metadataSHA256),
                comparisonDocumentIsValidDigest(side.resultDocument.contentAndMetadataSHA256),
                comparisonDocumentIsValidUUID(side.resultDocument.identity),
                comparisonDocumentIsValidDigest(side.resultDocument.encodedContentSHA256),
                comparisonDocumentIsValidDigest(side.resultDocument.metadataSHA256),
                comparisonDocumentEncodingIsValid(side.document),
                comparisonDocumentEncodingIsValid(side.resultDocument),
                side.saveOperation?.paneUpdateObservedDocument.map(
                    comparisonDocumentIsValidContentRevision
                ) ?? true,
                paneUpdateSourceIsValid,
                completedBackupIsValid,
                comparisonDocumentIsValidSourceRevision(
                    side.openedSource,
                    trustedLocationKeyReferences: trustedLocationKeyReferences
                ),
                comparisonDocumentIsValidSaveDestination(
                    side.saveDestination,
                    trustedLocationKeyReferences: trustedLocationKeyReferences
                ),
                incidentSourceIsValid,
                currentSourceIsValid,
                comparisonDocumentIsValidSourceRevision(
                    side.resultSource,
                    trustedLocationKeyReferences: trustedLocationKeyReferences
                )
            else {
                throw invalid(field: field, inventory: inventory)
            }
            if let scenario {
                guard side.openedSource.kind == scenario.sourceKind(on: side.side),
                    side.resultSource == side.openedSource,
                    !side.document.isReadOnly,
                    !side.resultDocument.isReadOnly,
                    comparisonDocumentResultPayloadIsValid(side),
                    comparisonDocumentSaveOperationIsValid(side, scenario: scenario),
                    comparisonDocumentDocumentRevisionsAreValid(side, scenario: scenario),
                    comparisonDocumentSaveDestinationIsValid(side, scenario: scenario),
                    comparisonDocumentBackupEvidenceIsValid(side, scenario: scenario),
                    comparisonDocumentCurrentSourceIsValid(side, scenario: scenario),
                    comparisonDocumentIncidentSourceIsValid(side, scenario: scenario)
                else {
                    throw invalid(field: field, inventory: inventory)
                }
            }
        }
        if let scenario, scenario.save.execution == .batch {
            guard let leftSave = bindings[.left].saveOperation,
                let rightSave = bindings[.right].saveOperation
            else {
                throw invalid(field: field, inventory: inventory)
            }
            let expectedWorkUnits = comparisonDocumentExpectedSaveWorkUnits(
                totalPathUTF8ByteCount: leftSave.totalPathUTF8ByteCount,
                operations: [leftSave, rightSave]
            )
            guard let expectedWorkUnits,
                leftSave.limits.maximumOperations >= 2,
                leftSave.plannedOperationCount == 2,
                rightSave.plannedOperationCount == 2,
                leftSave.planID == rightSave.planID,
                leftSave.limits == rightSave.limits,
                leftSave.totalPathUTF8ByteCount == rightSave.totalPathUTF8ByteCount,
                leftSave.totalPathUTF8ByteCount
                    == leftSave.destinationPathUTF8ByteCount
                    + leftSave.parentPathUTF8ByteCount
                    + rightSave.destinationPathUTF8ByteCount
                    + rightSave.parentPathUTF8ByteCount,
                leftSave.estimatedWorkUnits == rightSave.estimatedWorkUnits,
                leftSave.estimatedWorkUnits == expectedWorkUnits
            else {
                throw invalid(field: field, inventory: inventory)
            }
        }
        guard comparisonDocumentSidesDoNotCollide(bindings.sides) else {
            throw invalid(field: field, inventory: inventory)
        }
        guard comparisonDocumentCommittedSaveAsTargetsDoNotAliasSources(bindings.sides) else {
            throw invalid(field: field, inventory: inventory)
        }
        let locationKeyReferences = Set(
            bindings.sides.flatMap(comparisonDocumentLocationKeyReferences)
        )
        guard locationKeyReferences.count <= 1 else {
            throw invalid(field: field, inventory: inventory)
        }
    }

    private static func consumeLocationReferences(
        _ side: ComparisonDocumentSideRevisionBinding,
        field: String,
        strings: inout ComparisonDocumentStringBudget,
        budget: inout ComparisonDocumentWorkBudget
    ) throws {
        for file in comparisonDocumentFiles(in: side) {
            try strings.consume(
                file.identity.location.keyReference.rawValue,
                field: field,
                budget: &budget
            )
        }
        if case .transition(let transition) = side.saveDestination {
            for snapshot in [
                transition.expected,
                transition.observedBeforePublication,
                transition.observedAfterExecution
            ].compactMap({ $0 }) {
                try strings.consume(
                    snapshot.parent.identity.location.keyReference.rawValue,
                    field: field,
                    budget: &budget
                )
                try strings.consume(
                    snapshot.slot.location.keyReference.rawValue,
                    field: field,
                    budget: &budget
                )
            }
        }
        if let backup = side.completedBackup {
            for snapshot in [
                backup.destination.expected,
                backup.destination.observedBeforePublication,
                backup.destination.observedAfterExecution
            ].compactMap({ $0 }) {
                try strings.consume(
                    snapshot.parent.identity.location.keyReference.rawValue,
                    field: field,
                    budget: &budget
                )
                try strings.consume(
                    snapshot.slot.location.keyReference.rawValue,
                    field: field,
                    budget: &budget
                )
            }
        }
    }

    private static func validate(
        _ reference: ComparisonDocumentRevisionReference,
        field: String,
        strings: inout ComparisonDocumentStringBudget,
        budget: inout ComparisonDocumentWorkBudget,
        inventory: Bool
    ) throws {
        try strings.consume(reference.id.rawValue, field: field, budget: &budget)
        guard comparisonDocumentIsValidIdentifier(reference.id.rawValue), reference.revision > 0 else {
            throw invalid(field: field, inventory: inventory)
        }
    }

    private static func invalid(
        field: String,
        inventory: Bool
    ) -> ComparisonDocumentCoverageError {
        inventory ? .invalidInventory(field: field) : .invalidEvidence(field: field)
    }
}

private struct ComparisonDocumentStringBudget {
    let limits: ComparisonDocumentCoverageLimits
    private var total = 0

    init(limits: ComparisonDocumentCoverageLimits) {
        self.limits = limits
    }

    mutating func consume(
        _ value: String,
        field: String,
        budget: inout ComparisonDocumentWorkBudget
    ) throws {
        let count = value.utf8.count
        try budget.charge(count + 1)
        guard count <= limits.maximumStringUTF8Bytes else {
            throw ComparisonDocumentCoverageError.stringTooLarge(
                field: field,
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        guard total <= limits.maximumTotalStringUTF8Bytes - count else {
            throw ComparisonDocumentCoverageError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        total += count
    }
}

private struct ComparisonDocumentLineageRegistry {
    private struct DocumentKey: Hashable {
        let identity: UUID
        let generation: UInt64
    }

    private struct ScratchpadKey: Hashable {
        let identity: UUID
        let generation: UInt64
    }

    private struct FileKey: Hashable {
        let volumeID: UInt64
        let fileID: UInt64
        let generation: UInt64
        let revision: UInt64
    }

    private struct DirectoryKey: Hashable {
        let volumeID: UInt64
        let fileID: UInt64
        let generation: UInt64
        let revision: UInt64
    }

    private struct SlotKey: Hashable {
        let location: ComparisonDocumentLocationIdentity
        let revision: UInt64
    }

    private struct PhysicalKey: Hashable {
        let volumeID: UInt64
        let fileID: UInt64
        let generation: UInt64
    }

    private enum PhysicalRole: Equatable {
        case regularFile
        case directory
    }

    private struct LifecycleRevisionLineage: Equatable {
        let document: ComparisonDocumentContentRevision
        let source: ComparisonDocumentSourceRevision?
    }

    private struct SlotLineage: Equatable {
        let slot: ComparisonDocumentDestinationSlotRevision
        let target: ComparisonDocumentFileRevision?
    }

    private struct ResultLineage: Equatable {
        let inputs: ComparisonDocumentRevisionReference
        let operation: ComparisonDocumentLifecycleOperationBinding
    }

    private struct PlanLineage: Equatable {
        let execution: ComparisonDocumentSaveExecution
        let operations: [ComparisonDocumentSideSavePlanLineage]
    }

    private struct ComparisonDocumentSideSavePlanLineage: Equatable {
        let side: ComparisonDocumentSide
        let operation: ComparisonDocumentSaveOperationBinding
        let destination: ComparisonDocumentSaveDestinationSnapshot
    }

    private var comparisonByOpenRequest: [ComparisonOpenRequestIdentity: ComparisonDocumentStableID] =
        [:]
    private var openRequestByComparison: [ComparisonDocumentStableID: ComparisonOpenRequestIdentity] =
        [:]
    private var comparisons: [ComparisonDocumentRevisionReference: ComparisonDocumentComparisonRevisionBinding] = [:]
    private var operationsByID: [UUID: ComparisonDocumentLifecycleOperationBinding] = [:]
    private var operationsByComparison: [ComparisonDocumentRevisionReference: ComparisonDocumentLifecycleOperationBinding] = [:]
    private var inputs: [ComparisonDocumentRevisionReference: [ComparisonDocumentLifecycleSourceBinding]] =
        [:]
    private var results: [ComparisonDocumentRevisionReference: ResultLineage] = [:]
    private var resultByOperationID: [UUID: ComparisonDocumentRevisionReference] = [:]
    private var operationIDByResult: [ComparisonDocumentRevisionReference: UUID] = [:]
    private var lifecycleRevisions: [ComparisonDocumentRevisionReference: LifecycleRevisionLineage] =
        [:]
    private var documentRevisions: [DocumentKey: ComparisonDocumentContentRevision] = [:]
    private var scratchpadRevisions: [ScratchpadKey: ComparisonDocumentScratchpadRevision] = [:]
    private var fileRevisions: [FileKey: ComparisonDocumentFileRevision] = [:]
    private var directoryRevisions: [DirectoryKey: ComparisonDocumentDirectoryRevision] = [:]
    private var slotRevisions: [SlotKey: SlotLineage] = [:]
    private var physicalRoles: [PhysicalKey: PhysicalRole] = [:]
    private var savePlans: [UUID: PlanLineage] = [:]

    mutating func register(_ bindings: ComparisonDocumentRevisionBindings) throws {
        try Self.register(
            bindings.comparison.openRequest,
            value: bindings.comparison.comparison.id,
            in: &comparisonByOpenRequest
        )
        try Self.register(
            bindings.comparison.comparison.id,
            value: bindings.comparison.openRequest,
            in: &openRequestByComparison
        )
        try Self.register(
            bindings.comparison.comparison,
            value: bindings.comparison,
            in: &comparisons
        )
        try Self.register(
            bindings.comparison.operation.operationID,
            value: bindings.comparison.operation,
            in: &operationsByID
        )
        try Self.register(
            bindings.comparison.operation.comparison,
            value: bindings.comparison.operation,
            in: &operationsByComparison
        )
        try Self.register(
            bindings.comparison.inputs,
            value: bindings.comparison.sources,
            in: &inputs
        )
        try Self.register(
            bindings.comparison.resultInputs,
            value: bindings.comparison.resultSources,
            in: &inputs
        )
        try Self.register(
            bindings.comparison.result,
            value: ResultLineage(
                inputs: bindings.comparison.resultInputs,
                operation: bindings.comparison.operation
            ),
            in: &results
        )
        try Self.register(
            bindings.comparison.operation.operationID,
            value: bindings.comparison.result,
            in: &resultByOperationID
        )
        try Self.register(
            bindings.comparison.result,
            value: bindings.comparison.operation.operationID,
            in: &operationIDByResult
        )
        for side in bindings.sides {
            try Self.register(
                side.lifecycleSource,
                value: LifecycleRevisionLineage(
                    document: side.document,
                    source: side.currentSource
                ),
                in: &lifecycleRevisions
            )
            try Self.register(
                side.resultLifecycleSource,
                value: LifecycleRevisionLineage(
                    document: side.resultDocument,
                    source: side.resultSource
                ),
                in: &lifecycleRevisions
            )
            try registerDocument(side.document)
            try registerDocument(side.resultDocument)
            try registerSource(side.openedSource)
            if let incidentSource = side.incidentSource {
                try registerSource(incidentSource)
            }
            if let currentSource = side.currentSource {
                try registerSource(currentSource)
            }
            if case .transition(let transition) = side.saveDestination {
                for snapshot in [
                    transition.expected,
                    transition.observedBeforePublication,
                    transition.observedAfterExecution
                ].compactMap({ $0 }) {
                    try registerDestination(snapshot)
                }
            }
            if let save = side.saveOperation {
                try registerDocument(save.sourceDocument)
                if let sourceFile = save.sourceFile { try registerSource(.file(sourceFile)) }
                if let committedPayload = save.committedPayload {
                    try registerSource(.file(committedPayload))
                }
                if let observedDocument = save.paneUpdateObservedDocument {
                    try registerDocument(observedDocument)
                }
                if let observedSource = save.paneUpdateObservedSource {
                    try registerSource(observedSource)
                }
            }
            if let backup = side.completedBackup {
                try registerSource(.file(backup.sourceRevision))
                try registerDestination(backup.destination.expected)
                try registerDestination(backup.destination.observedBeforePublication)
                if let after = backup.destination.observedAfterExecution {
                    try registerDestination(after)
                }
                try registerSource(.file(backup.committedPayload))
            }
            try registerSource(side.resultSource)
        }
        let saveOperations = bindings.sides.compactMap { side in
            side.saveOperation.map { (side.side, $0) }
        }
        if let first = saveOperations.first {
            let execution: ComparisonDocumentSaveExecution =
                saveOperations.count == 2 ? .batch : .single(first.0)
            let operations = saveOperations.compactMap { side, operation -> ComparisonDocumentSideSavePlanLineage? in
                guard case .transition(let transition) = bindings[side].saveDestination else {
                    return nil
                }
                return ComparisonDocumentSideSavePlanLineage(
                    side: side,
                    operation: operation,
                    destination: transition.expected
                )
            }
            guard operations.count == saveOperations.count else {
                throw ComparisonDocumentCoverageError.invalidInventory(field: "requirements.lineage")
            }
            try Self.register(
                first.1.planID,
                value: PlanLineage(
                    execution: execution,
                    operations: operations
                ),
                in: &savePlans
            )
        }
    }

    private mutating func registerDocument(
        _ revision: ComparisonDocumentContentRevision
    ) throws {
        try Self.register(
            DocumentKey(identity: revision.identity, generation: revision.generation),
            value: revision,
            in: &documentRevisions
        )
    }

    private mutating func registerDestination(
        _ snapshot: ComparisonDocumentSaveDestinationSnapshot
    ) throws {
        try registerPhysicalRole(snapshot.parent.identity, role: .directory)
        try Self.register(
            DirectoryKey(
                volumeID: snapshot.parent.identity.volumeID,
                fileID: snapshot.parent.identity.fileID,
                generation: snapshot.parent.identity.generation,
                revision: snapshot.parent.revision
            ),
            value: snapshot.parent,
            in: &directoryRevisions
        )
        try Self.register(
            SlotKey(location: snapshot.slot.location, revision: snapshot.slot.revision),
            value: SlotLineage(slot: snapshot.slot, target: snapshot.target),
            in: &slotRevisions
        )
        if let target = snapshot.target { try registerSource(.file(target)) }
    }

    private mutating func registerSource(
        _ revision: ComparisonDocumentSourceRevision
    ) throws {
        switch revision {
        case .file(let file):
            try registerPhysicalRole(file.identity, role: .regularFile)
            try Self.register(
                FileKey(
                    volumeID: file.identity.volumeID,
                    fileID: file.identity.fileID,
                    generation: file.identity.generation,
                    revision: file.revision
                ),
                value: file,
                in: &fileRevisions
            )
        case .scratchpad(let scratchpad):
            try Self.register(
                ScratchpadKey(identity: scratchpad.identity, generation: scratchpad.generation),
                value: scratchpad,
                in: &scratchpadRevisions
            )
        }
    }

    private mutating func registerPhysicalRole(
        _ identity: ComparisonDocumentFileIdentity,
        role: PhysicalRole
    ) throws {
        try Self.register(
            PhysicalKey(
                volumeID: identity.volumeID,
                fileID: identity.fileID,
                generation: identity.generation
            ),
            value: role,
            in: &physicalRoles
        )
    }

    private static func register<Key: Hashable, Value: Equatable>(
        _ reference: Key,
        value: Value,
        in registry: inout [Key: Value]
    ) throws {
        if let existing = registry[reference], existing != value {
            throw ComparisonDocumentCoverageError.invalidInventory(field: "requirements.lineage")
        }
        registry[reference] = value
    }
}

private final class ComparisonDocumentWorkBudget: @unchecked Sendable {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: ComparisonDocumentCoverageMatrix.CancellationCheck
    private let lock = NSLock()
    private var completedValue = 0
    private var workSinceCancellationCheck = 0

    var completed: Int {
        lock.withLock { completedValue }
    }

    var remaining: Int {
        lock.withLock { maximum - completedValue }
    }

    init(
        maximum: Int,
        cancellationCheckInterval: Int,
        cancellationCheck: @escaping ComparisonDocumentCoverageMatrix.CancellationCheck
    ) {
        self.maximum = maximum
        self.cancellationCheckInterval = cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
    }

    func charge(_ amount: Int = 1) throws {
        let shouldCheckCancellation: Bool = try lock.withLock {
            guard amount >= 0, amount <= maximum, completedValue <= maximum - amount else {
                throw ComparisonDocumentCoverageError.workLimitExceeded(maximum: maximum)
            }
            completedValue += amount
            let (next, overflow) = workSinceCancellationCheck.addingReportingOverflow(amount)
            workSinceCancellationCheck = overflow ? cancellationCheckInterval : next
            guard workSinceCancellationCheck >= cancellationCheckInterval else { return false }
            workSinceCancellationCheck = 0
            return true
        }
        if shouldCheckCancellation { try checkCancellation() }
    }

    func checkCancellation() throws {
        if cancellationCheck() { throw ComparisonDocumentCoverageError.cancelled }
    }
}

private struct ComparisonDocumentCanonicalWriter {
    let maximumBytes: Int
    let budget: ComparisonDocumentWorkBudget?
    private(set) var data = Data()

    init(maximumBytes: Int, budget: ComparisonDocumentWorkBudget? = nil) {
        self.maximumBytes = maximumBytes
        self.budget = budget
    }

    mutating func append(_ value: UInt8) throws {
        try reserve(1)
        data.append(value)
    }

    mutating func append(_ value: Bool) throws {
        try append(UInt8(value ? 1 : 0))
    }

    mutating func append(_ value: UInt16) throws {
        var bigEndian = value.bigEndian
        try withUnsafeBytes(of: &bigEndian) { try append($0) }
    }

    mutating func append(_ value: UInt32) throws {
        var bigEndian = value.bigEndian
        try withUnsafeBytes(of: &bigEndian) { try append($0) }
    }

    mutating func append(_ value: UInt64) throws {
        var bigEndian = value.bigEndian
        try withUnsafeBytes(of: &bigEndian) { try append($0) }
    }

    mutating func append(_ value: Int64) throws {
        try append(UInt64(bitPattern: value))
    }

    mutating func append(count: Int) throws {
        guard let value = UInt64(exactly: count) else {
            throw ComparisonDocumentCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        try append(value)
    }

    mutating func append(_ value: String) throws {
        let normalized = value.precomposedStringWithCanonicalMapping
        guard data.count <= maximumBytes - MemoryLayout<UInt64>.size else {
            throw ComparisonDocumentCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        let maximumStringBytes = maximumBytes - data.count - MemoryLayout<UInt64>.size
        var count = 0
        for _ in normalized.utf8 {
            guard count < maximumStringBytes else {
                throw ComparisonDocumentCoverageError.canonicalDataTooLarge(
                    maximumBytes: maximumBytes
                )
            }
            count += 1
            try budget?.charge()
        }
        try append(count: count)
        try reserve(count)
        data.append(contentsOf: normalized.utf8)
    }

    mutating func append(_ bytes: [UInt8]) throws {
        try reserve(bytes.count)
        data.append(contentsOf: bytes)
    }

    mutating func appendFramed(_ bytes: [UInt8]) throws {
        try append(count: bytes.count)
        try append(bytes)
    }

    mutating func append(_ bytes: UnsafeRawBufferPointer) throws {
        try reserve(bytes.count)
        data.append(contentsOf: bytes)
    }

    mutating func append(_ value: Data) throws {
        try append(count: value.count)
        guard value.count <= maximumBytes, data.count <= maximumBytes - value.count else {
            throw ComparisonDocumentCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        let chunkSize = max(1, budget?.cancellationCheckInterval ?? value.count)
        var offset = value.startIndex
        while offset < value.endIndex {
            let end =
                value.index(offset, offsetBy: chunkSize, limitedBy: value.endIndex)
                ?? value.endIndex
            let count = value.distance(from: offset, to: end)
            try reserve(count)
            data.append(value[offset..<end])
            offset = end
        }
    }

    private mutating func reserve(_ count: Int) throws {
        guard count >= 0, count <= maximumBytes, data.count <= maximumBytes - count else {
            throw ComparisonDocumentCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        try budget?.charge(count)
    }
}

private func comparisonDocumentCanonicalInventoryData(
    _ inventory: ComparisonDocumentCoverageInventory,
    maximumBytes: Int,
    budget: ComparisonDocumentWorkBudget
) throws -> Data {
    var writer = ComparisonDocumentCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMCDINV4")
    try writer.append(UInt64(ComparisonDocumentCoverageMatrix.canonicalMatrixRevision))
    try comparisonDocumentAppend(inventory.reference, to: &writer)
    try comparisonDocumentAppend(inventory.build, to: &writer)
    try writer.appendFramed(inventory.buildArtifactSHA256)
    var requirements = inventory.requirements
    try comparisonDocumentSort(&requirements) { left, right in
        try budget.charge()
        return left.id < right.id
    }
    try writer.append(count: requirements.count)
    for requirement in requirements {
        try comparisonDocumentAppend(requirement.scenario, to: &writer)
        try comparisonDocumentAppend(requirement.bindings, to: &writer)
    }
    return writer.data
}

private func comparisonDocumentCanonicalCaptureData(
    _ observation: ComparisonDocumentProductionObservation,
    maximumBytes: Int,
    budget: ComparisonDocumentWorkBudget
) throws -> Data {
    var writer = ComparisonDocumentCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMCDCAP4")
    try writer.append(observation.scenarioID.rawValue)
    try comparisonDocumentAppend(observation.bindings, to: &writer)
    try writer.append(comparisonDocumentLifecycleRank(observation.lifecycle.phase))
    try writer.append(observation.lifecycle.hasCurrentResult)
    try writer.append(observation.lifecycle.hasRetainedResult)
    try comparisonDocumentAppend(observation.lifecycle.staleReason, to: &writer)
    try comparisonDocumentAppend(observation.left, to: &writer)
    try comparisonDocumentAppend(observation.right, to: &writer)
    try comparisonDocumentAppend(observation.save, to: &writer)
    try comparisonDocumentAppend(observation.saveExecutorContract, to: &writer)
    try comparisonDocumentAppend(observation.backup, to: &writer)
    try writer.append(observation.origin.rawValue)
    if let provenance = observation.provenance {
        try writer.append(true)
        try comparisonDocumentAppend(provenance.build, to: &writer)
        try comparisonDocumentAppend(provenance.inventory, to: &writer)
        try comparisonDocumentAppend(provenance.evidence, to: &writer)
        try comparisonDocumentAppend(provenance.collector, to: &writer)
        try comparisonDocumentAppend(provenance.run, to: &writer)
        try writer.append(provenance.capturedAtUnixMilliseconds)
        try writer.appendFramed(provenance.runNonce)
        try writer.appendFramed(provenance.artifactSHA256)
        try writer.append(count: provenance.captureByteCount)
        try writer.append(provenance.source.rawValue)
    } else {
        try writer.append(false)
    }
    return writer.data
}

private func comparisonDocumentCanonicalEvidenceData(
    _ evidence: ComparisonDocumentEvidenceBundle,
    maximumBytes: Int,
    budget: ComparisonDocumentWorkBudget
) throws -> Data {
    var writer = ComparisonDocumentCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMCDEVD4")
    try comparisonDocumentAppend(evidence.reference, to: &writer)
    try comparisonDocumentAppend(evidence.inventory, to: &writer)
    try comparisonDocumentAppend(evidence.build, to: &writer)
    var totalRecordBytes = 0
    var records: [Data] = []
    records.reserveCapacity(evidence.observations.count)
    for observation in evidence.observations {
        let record = try comparisonDocumentCanonicalObservationData(
            observation,
            maximumBytes: maximumBytes,
            budget: budget
        )
        guard record.count <= maximumBytes - totalRecordBytes else {
            throw ComparisonDocumentCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        totalRecordBytes += record.count
        records.append(record)
    }
    try comparisonDocumentSort(&records) { left, right in
        try comparisonDocumentDataPrecedes(left, right, budget: budget)
    }
    try writer.append(count: records.count)
    for record in records { try writer.append(record) }
    return writer.data
}

private func comparisonDocumentCanonicalObservationData(
    _ observation: ComparisonDocumentProductionObservation,
    maximumBytes: Int,
    budget: ComparisonDocumentWorkBudget
) throws -> Data {
    var writer = ComparisonDocumentCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append(observation.scenarioID.rawValue)
    try comparisonDocumentAppend(observation.bindings, to: &writer)
    try writer.append(comparisonDocumentLifecycleRank(observation.lifecycle.phase))
    try writer.append(observation.lifecycle.hasCurrentResult)
    try writer.append(observation.lifecycle.hasRetainedResult)
    try comparisonDocumentAppend(observation.lifecycle.staleReason, to: &writer)
    try comparisonDocumentAppend(observation.left, to: &writer)
    try comparisonDocumentAppend(observation.right, to: &writer)
    try comparisonDocumentAppend(observation.save, to: &writer)
    try comparisonDocumentAppend(observation.saveExecutorContract, to: &writer)
    try comparisonDocumentAppend(observation.backup, to: &writer)
    try writer.append(observation.origin.rawValue)
    if let provenance = observation.provenance {
        try writer.append(true)
        try comparisonDocumentAppend(provenance.build, to: &writer)
        try comparisonDocumentAppend(provenance.inventory, to: &writer)
        try comparisonDocumentAppend(provenance.evidence, to: &writer)
        try comparisonDocumentAppend(provenance.collector, to: &writer)
        try comparisonDocumentAppend(provenance.run, to: &writer)
        try writer.append(provenance.capturedAtUnixMilliseconds)
        try writer.appendFramed(provenance.runNonce)
        try writer.appendFramed(provenance.artifactSHA256)
        try writer.appendFramed(provenance.captureSHA256)
        try writer.append(count: provenance.captureByteCount)
        try writer.appendFramed(provenance.collectorSignature)
        try writer.append(provenance.source.rawValue)
    } else {
        try writer.append(false)
    }
    return writer.data
}

private func comparisonDocumentCanonicalReportData(
    _ report: ComparisonDocumentCoverageReport,
    maximumBytes: Int,
    budget: ComparisonDocumentWorkBudget
) throws -> Data {
    var writer = ComparisonDocumentCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMCDRPT4")
    try writer.append(UInt64(report.formatVersion))
    try comparisonDocumentAppend(report.inventory, to: &writer)
    try comparisonDocumentAppend(report.evidence, to: &writer)
    try writer.append(report.trustedAuditTimeUnixMilliseconds)
    try writer.appendFramed(report.auditPolicySHA256)
    try writer.append(count: report.matrix.cells.count)
    for cell in report.matrix.cells {
        try writer.append(cell.scenario.id.rawValue)
        try writer.append(cell.status.rawValue)
        try writer.append(count: cell.evidenceCount)
    }
    try writer.append(count: report.findings.count)
    for finding in report.findings {
        try writer.append(finding.id.rawValue)
        try writer.append(finding.severity.rawValue)
        try writer.append(finding.code.rawValue)
    }
    return writer.data
}

private func comparisonDocumentCanonicalArchiveData(
    inventoryData: Data,
    evidenceData: Data,
    reportData: Data,
    maximumBytes: Int,
    budget: ComparisonDocumentWorkBudget
) throws -> Data {
    do {
        var writer = ComparisonDocumentCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
        try writer.append("MMCDARC4")
        try writer.append(UInt64(ComparisonDocumentCoverageMatrix.archiveFormatVersion))
        try writer.append(try comparisonDocumentSHA256(inventoryData, budget: budget))
        try writer.append(try comparisonDocumentSHA256(evidenceData, budget: budget))
        try writer.append(try comparisonDocumentSHA256(reportData, budget: budget))
        try writer.append(inventoryData)
        try writer.append(evidenceData)
        try writer.append(reportData)
        let payloadDigest = try comparisonDocumentSHA256(writer.data, budget: budget)
        try writer.append(payloadDigest)
        return writer.data
    } catch ComparisonDocumentCoverageError.canonicalDataTooLarge {
        throw ComparisonDocumentCoverageError.archiveTooLarge(maximumBytes: maximumBytes)
    }
}

private func comparisonDocumentCanonicalAuditPolicyData(
    _ policy: ComparisonDocumentAuditPolicy,
    maximumBytes: Int,
    budget: ComparisonDocumentWorkBudget
) throws -> Data {
    var writer = ComparisonDocumentCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMCDPOL4")
    var collectors = policy.trustedCollectors
    try comparisonDocumentSort(&collectors) { left, right in
        let idOrder = try comparisonDocumentCompareUTF8(
            left.reference.id.rawValue,
            right.reference.id.rawValue,
            budget: budget
        )
        return idOrder == 0
            ? left.reference.revision < right.reference.revision : idOrder < 0
    }
    try writer.append(count: collectors.count)
    for collector in collectors {
        try comparisonDocumentAppend(collector.reference, to: &writer)
        try writer.appendFramed(collector.ed25519PublicKey)
    }
    var locationKeys = Array(policy.trustedLocationKeyReferences)
    try comparisonDocumentSort(&locationKeys) { left, right in
        try comparisonDocumentCompareUTF8(left.rawValue, right.rawValue, budget: budget) < 0
    }
    try writer.append(count: locationKeys.count)
    for locationKey in locationKeys { try writer.append(locationKey.rawValue) }
    try writer.append(policy.trustedAuditTimeUnixMilliseconds)
    try writer.append(policy.maximumCaptureAgeMilliseconds)
    try writer.append(policy.maximumFutureClockSkewMilliseconds)
    try writer.append(policy.replayClaimDeadlineUnixMilliseconds)
    try comparisonDocumentAppend(policy.replayPolicy, to: &writer)
    return writer.data
}

private func comparisonDocumentValidateArchive(
    _ archive: Data,
    limits: ComparisonDocumentCoverageLimits,
    budget: ComparisonDocumentWorkBudget
) throws {
    try budget.checkCancellation()
    guard archive.count <= limits.maximumArchiveBytes else {
        throw ComparisonDocumentCoverageError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
    }
    guard archive.count >= 8 + 8 + 8 + 96 + 24 + 32 else {
        throw ComparisonDocumentCoverageError.invalidArchive
    }
    let payload = archive.dropLast(SHA256.byteCount)
    let digest = archive.suffix(SHA256.byteCount)
    guard digest.elementsEqual(try comparisonDocumentSHA256(payload, budget: budget)) else {
        throw ComparisonDocumentCoverageError.invalidArchive
    }
    var reader = ComparisonDocumentCanonicalReader(data: payload)
    guard try reader.readFramedData(maximumBytes: 8) == Data("MMCDARC4".utf8),
        try reader.readUInt64() == UInt64(ComparisonDocumentCoverageMatrix.archiveFormatVersion)
    else {
        throw ComparisonDocumentCoverageError.invalidArchive
    }
    let inventorySHA256 = try reader.readData(count: SHA256.byteCount)
    let evidenceSHA256 = try reader.readData(count: SHA256.byteCount)
    let reportSHA256 = try reader.readData(count: SHA256.byteCount)
    let inventory = try reader.readFramedData(maximumBytes: limits.maximumCanonicalBytes)
    let evidence = try reader.readFramedData(maximumBytes: limits.maximumCanonicalBytes)
    let report = try reader.readFramedData(maximumBytes: limits.maximumCanonicalBytes)
    guard reader.isAtEnd,
        inventorySHA256 == Data(try comparisonDocumentSHA256(inventory, budget: budget)),
        evidenceSHA256 == Data(try comparisonDocumentSHA256(evidence, budget: budget)),
        reportSHA256 == Data(try comparisonDocumentSHA256(report, budget: budget))
    else {
        throw ComparisonDocumentCoverageError.invalidArchive
    }
    try budget.checkCancellation()
}

private struct ComparisonDocumentCanonicalReader {
    let data: Data
    private var offset: Data.Index

    init(data: Data) {
        self.data = data
        offset = data.startIndex
    }

    var isAtEnd: Bool { offset == data.endIndex }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try readData(count: 8)
        return bytes.reduce(into: UInt64(0)) { result, byte in
            result = (result << 8) | UInt64(byte)
        }
    }

    mutating func readFramedData(maximumBytes: Int) throws -> Data {
        let count = try readUInt64()
        guard count <= UInt64(maximumBytes), let exactCount = Int(exactly: count) else {
            throw ComparisonDocumentCoverageError.invalidArchive
        }
        return try readData(count: exactCount)
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, count <= data.distance(from: offset, to: data.endIndex) else {
            throw ComparisonDocumentCoverageError.invalidArchive
        }
        let end = data.index(offset, offsetBy: count)
        defer { offset = end }
        return data[offset..<end]
    }
}

private func comparisonDocumentAppend(
    _ scenario: ComparisonDocumentScenario,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    try writer.append(scenario.id.rawValue)
    try writer.append(scenario.sourceShape.rawValue)
    try writer.append(scenario.dirtyState.rawValue)
    try writer.append(scenario.incident.rank)
    try comparisonDocumentAppend(scenario.save, to: &writer)
    try comparisonDocumentAppend(scenario.backup, to: &writer)
}

private func comparisonDocumentAppend(
    _ bindings: ComparisonDocumentRevisionBindings,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    try writer.append(bindings.comparison.openRequest.rawValue.uuidString)
    try comparisonDocumentAppend(bindings.comparison.comparison, to: &writer)
    try comparisonDocumentAppend(bindings.comparison.operation.comparison, to: &writer)
    try writer.append(bindings.comparison.operation.operationID.uuidString)
    try writer.append(bindings.comparison.operation.startedAtGeneration)
    try comparisonDocumentAppend(bindings.comparison.operation.inputs, to: &writer)
    try writer.append(count: bindings.comparison.operation.sources.count)
    for source in bindings.comparison.operation.sources {
        try writer.append(source.side.rawValue)
        try comparisonDocumentAppend(source.source, to: &writer)
    }
    try comparisonDocumentAppend(bindings.comparison.inputs, to: &writer)
    try comparisonDocumentAppend(bindings.comparison.result, to: &writer)
    try comparisonDocumentAppend(bindings.comparison.resultInputs, to: &writer)
    try writer.append(count: bindings.comparison.resultSources.count)
    for source in bindings.comparison.resultSources {
        try writer.append(source.side.rawValue)
        try comparisonDocumentAppend(source.source, to: &writer)
    }
    try writer.append(count: bindings.sides.count)
    for side in bindings.sides {
        try writer.append(side.side.rawValue)
        try comparisonDocumentAppend(side.document, to: &writer)
        try comparisonDocumentAppend(side.resultDocument, to: &writer)
        try comparisonDocumentAppend(side.lifecycleSource, to: &writer)
        try comparisonDocumentAppend(side.resultLifecycleSource, to: &writer)
        try comparisonDocumentAppend(side.openedSource, to: &writer)
        try comparisonDocumentAppend(side.saveOperation, to: &writer)
        try comparisonDocumentAppend(side.saveDestination, to: &writer)
        try comparisonDocumentAppend(side.completedBackup, to: &writer)
        if let incidentSource = side.incidentSource {
            try writer.append(true)
            try comparisonDocumentAppend(incidentSource, to: &writer)
        } else {
            try writer.append(false)
        }
        if let currentSource = side.currentSource {
            try writer.append(true)
            try comparisonDocumentAppend(currentSource, to: &writer)
        } else {
            try writer.append(false)
        }
        try comparisonDocumentAppend(side.resultSource, to: &writer)
    }
}

private func comparisonDocumentAppend(
    _ destination: ComparisonDocumentSaveDestinationBinding,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    switch destination {
    case .notApplicable:
        try writer.append(UInt8(0))
    case .transition(let transition):
        try writer.append(UInt8(1))
        try comparisonDocumentAppend(transition.expected, to: &writer)
        try comparisonDocumentAppend(transition.observedBeforePublication, to: &writer)
        if let observedAfterExecution = transition.observedAfterExecution {
            try writer.append(true)
            try comparisonDocumentAppend(observedAfterExecution, to: &writer)
        } else {
            try writer.append(false)
        }
    }
}

private func comparisonDocumentAppend(
    _ snapshot: ComparisonDocumentSaveDestinationSnapshot,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    try writer.append(snapshot.parent.identity.volumeID)
    try writer.append(snapshot.parent.identity.fileID)
    try writer.append(snapshot.parent.identity.generation)
    try comparisonDocumentAppend(snapshot.parent.identity.location, to: &writer)
    try writer.append(snapshot.parent.revision)
    try writer.append(snapshot.parent.metadataByteCount)
    try writer.appendFramed(snapshot.parent.metadataSHA256)
    try comparisonDocumentAppend(snapshot.slot.location, to: &writer)
    try writer.append(snapshot.slot.revision)
    if let target = snapshot.target {
        try writer.append(true)
        try comparisonDocumentAppend(.file(target), to: &writer)
    } else {
        try writer.append(false)
    }
}

private func comparisonDocumentAppend(
    _ backup: ComparisonDocumentCompletedBackupEvidence?,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    guard let backup else {
        try writer.append(false)
        return
    }
    try writer.append(true)
    try comparisonDocumentAppend(.file(backup.sourceRevision), to: &writer)
    try comparisonDocumentAppend(backup.destination.expected, to: &writer)
    try comparisonDocumentAppend(backup.destination.observedBeforePublication, to: &writer)
    if let after = backup.destination.observedAfterExecution {
        try writer.append(true)
        try comparisonDocumentAppend(after, to: &writer)
    } else {
        try writer.append(false)
    }
    try comparisonDocumentAppend(.file(backup.committedPayload), to: &writer)
}

private func comparisonDocumentAppend(
    _ location: ComparisonDocumentLocationIdentity,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    try writer.append(location.keyReference.rawValue)
    try writer.appendFramed(location.hmacSHA256)
}

private func comparisonDocumentAppend(
    _ reference: ComparisonDocumentRevisionReference,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    try writer.append(reference.id.rawValue)
    try writer.append(reference.revision)
}

private func comparisonDocumentAppend(
    _ revision: ComparisonDocumentContentRevision,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    try writer.append(revision.identity.uuidString)
    try writer.append(revision.generation)
    try writer.append(revision.encodedByteCount)
    try writer.append(revision.metadataByteCount)
    try writer.appendFramed(revision.encodedContentSHA256)
    try writer.appendFramed(revision.metadataSHA256)
    try writer.appendFramed(revision.contentAndMetadataSHA256)
    try writer.append(revision.encoding.encoding.rawValue)
    try writer.append(revision.encoding.hasByteOrderMark)
    try writer.append(revision.isReadOnly)
}

private func comparisonDocumentAppend(
    _ operation: ComparisonDocumentSaveOperationBinding?,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    guard let operation else {
        try writer.append(false)
        return
    }
    try writer.append(true)
    try writer.append(operation.planID.uuidString)
    try comparisonDocumentAppend(operation.sourceDocument, to: &writer)
    if let sourceFile = operation.sourceFile {
        try writer.append(true)
        try comparisonDocumentAppend(.file(sourceFile), to: &writer)
    } else {
        try writer.append(false)
    }
    try comparisonDocumentAppend(operation.limits, to: &writer)
    try writer.append(count: operation.destinationPathUTF8ByteCount)
    try writer.append(count: operation.parentPathUTF8ByteCount)
    try writer.append(count: operation.canonicalLeafIdentityUTF8ByteCount)
    try writer.append(count: operation.plannedOperationCount)
    try writer.append(count: operation.totalPathUTF8ByteCount)
    try writer.append(operation.estimatedWorkUnits)
    if let committedPayload = operation.committedPayload {
        try writer.append(true)
        try comparisonDocumentAppend(.file(committedPayload), to: &writer)
    } else {
        try writer.append(false)
    }
    if let paneUpdateObservedDocument = operation.paneUpdateObservedDocument {
        try writer.append(true)
        try comparisonDocumentAppend(paneUpdateObservedDocument, to: &writer)
    } else {
        try writer.append(false)
    }
    if let paneUpdateObservedSource = operation.paneUpdateObservedSource {
        try writer.append(true)
        try comparisonDocumentAppend(paneUpdateObservedSource, to: &writer)
    } else {
        try writer.append(false)
    }
    if let paneUpdateObservedPlanID = operation.paneUpdateObservedPlanID {
        try writer.append(true)
        try writer.append(paneUpdateObservedPlanID.uuidString)
    } else {
        try writer.append(false)
    }
    try writer.append(operation.planWasConsumedBeforePaneUpdate)
}

private func comparisonDocumentAppend(
    _ limits: ThreePaneSavePlanningLimits,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    try writer.append(count: limits.maximumOperations)
    try writer.append(count: limits.maximumPathUTF8Bytes)
    try writer.append(count: limits.maximumTotalPathUTF8Bytes)
    try writer.append(count: limits.maximumCanonicalLeafIdentityUTF8Bytes)
    try writer.append(limits.maximumEncodedFileBytes)
    try writer.append(limits.maximumMetadataBytes)
    try writer.append(limits.maximumWorkUnits)
}

private func comparisonDocumentAppend(
    _ revision: ComparisonDocumentSourceRevision,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    switch revision {
    case .file(let file):
        try writer.append(UInt8(0))
        try writer.append(file.identity.volumeID)
        try writer.append(file.identity.fileID)
        try writer.append(file.identity.generation)
        try writer.append(file.identity.location.keyReference.rawValue)
        try writer.appendFramed(file.identity.location.hmacSHA256)
        try writer.append(file.revision)
        try writer.append(file.byteCount)
        try writer.append(file.metadataByteCount)
        try writer.append(file.modificationTimeSeconds)
        try writer.append(file.modificationTimeNanoseconds)
        try writer.append(file.statusChangeTimeSeconds)
        try writer.append(file.statusChangeTimeNanoseconds)
        try writer.appendFramed(file.contentSHA256)
        try writer.appendFramed(file.metadataSHA256)
        try writer.appendFramed(file.contentAndMetadataSHA256)
        try writer.append(file.encoding.encoding.rawValue)
        try writer.append(file.encoding.hasByteOrderMark)
        try writer.append(file.isReadOnly)
    case .scratchpad(let scratchpad):
        try writer.append(UInt8(1))
        try writer.append(scratchpad.identity.uuidString)
        try writer.append(scratchpad.generation)
        try writer.append(scratchpad.encodedByteCount)
        try writer.append(scratchpad.metadataByteCount)
        try writer.appendFramed(scratchpad.encodedContentSHA256)
        try writer.appendFramed(scratchpad.metadataSHA256)
        try writer.appendFramed(scratchpad.contentAndMetadataSHA256)
        try writer.append(scratchpad.encoding.encoding.rawValue)
        try writer.append(scratchpad.encoding.hasByteOrderMark)
        try writer.append(scratchpad.isReadOnly)
    }
}

private func comparisonDocumentAppend(
    _ pane: ComparisonDocumentPaneObservation,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    try writer.append(pane.sourceKind.rawValue)
    try writer.append(pane.isLoaded)
    try writer.append(pane.isEditable)
    try writer.append(pane.isDirty)
    try writer.append(pane.isUntitled)
    try writer.append(pane.diskState.rawValue)
}

private func comparisonDocumentAppend(
    _ save: ComparisonDocumentSaveState,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    switch save.execution {
    case .notAttempted:
        try writer.append(UInt8(0))
    case .single(.left):
        try writer.append(UInt8(1))
    case .single(.right):
        try writer.append(UInt8(2))
    case .batch:
        try writer.append(UInt8(3))
    }
    try writer.append(save.leftOperation.rawValue)
    try comparisonDocumentAppend(save.left, to: &writer)
    try writer.append(save.rightOperation.rawValue)
    try comparisonDocumentAppend(save.right, to: &writer)
}

private func comparisonDocumentAppend(
    _ outcome: ComparisonDocumentSideSaveOutcome,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    switch outcome {
    case .notAttempted:
        try writer.append(UInt8(0))
    case .failed(let reason):
        try writer.append(UInt8(1))
        try writer.append(UInt8(comparisonDocumentSaveFailureRank(reason)))
    case .uncertain(let reason):
        try writer.append(UInt8(2))
        try writer.append(UInt8(comparisonDocumentSaveUncertaintyRank(reason)))
    case .committed(let paneUpdate):
        try writer.append(UInt8(3))
        switch paneUpdate {
        case .applied:
            try writer.append(UInt8(0))
        case .rejected(let reason):
            try writer.append(UInt8(1))
            try writer.append(reason.rawValue)
        }
    }
}

private func comparisonDocumentAppend(
    _ contract: ThreePaneSaveExecutorContract?,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    guard let contract else {
        try writer.append(false)
        return
    }
    try writer.append(true)
    try writer.append(contract.sourceRevision.rawValue)
    try writer.append(contract.destinationCAS.rawValue)
    try writer.append(contract.pathResolution.rawValue)
    try writer.append(contract.publication.rawValue)
    try writer.append(contract.cancellation.rawValue)
    try writer.append(contract.paneUpdate.rawValue)
    try writer.append(contract.batchPreflight.rawValue)
    try writer.append(contract.batchOutcome.rawValue)
}

private func comparisonDocumentAppend(
    _ backup: ComparisonDocumentBackupState,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    try comparisonDocumentAppend(backup.left, to: &writer)
    try comparisonDocumentAppend(backup.right, to: &writer)
}

private func comparisonDocumentAppend(
    _ backup: ComparisonDocumentSideBackupState,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    switch backup {
    case .notApplicable:
        try writer.append(UInt8(0))
    case .required(let trigger, let contract, let outcome):
        try writer.append(UInt8(1))
        try writer.append(trigger.rawValue)
        try writer.append(contract.pathResolution.rawValue)
        try writer.append(contract.parentMutation.rawValue)
        try writer.append(contract.publication.rawValue)
        try writer.append(contract.sourceValidation.rawValue)
        try writer.append(contract.metadata.rawValue)
        try writer.append(contract.retention.rawValue)
        try writer.append(contract.cancellation.rawValue)
        try writer.append(contract.trustedTime.maximumRequestSkewSeconds)
        try writer.append(contract.trustedTime.provenanceTimeSource)
        try writer.append(contract.trustedTime.retentionTimeSource)
        try writer.append(contract.trustedTime.monotonicRequirement)
        try writer.append(count: contract.transaction.orderedPhases.count)
        for phase in contract.transaction.orderedPhases { try writer.append(phase.rawValue) }
        try writer.append(contract.transaction.journalFormat.canonicalEncodingIdentifier)
        try writer.append(count: contract.transaction.journalFormat.replacementOrder.count)
        for phase in contract.transaction.journalFormat.replacementOrder {
            try writer.append(phase.rawValue)
        }
        try writer.append(count: contract.transaction.journalFormat.reservedRecordCount)
        try writer.append(count: contract.transaction.journalFormat.maximumReservedBytes)
        let sequenceAnchor = contract.transaction.journalFormat.sequenceAnchor
        try writer.append(sequenceAnchor.storageRequirement)
        try writer.append(sequenceAnchor.boundState)
        try writer.append(sequenceAnchor.mutationRequirement)
        try writer.append(sequenceAnchor.committedRecoveryRelation)
        try writer.append(sequenceAnchor.committedRecoveryAction)
        try writer.append(sequenceAnchor.preparedRolloverRelation)
        try writer.append(sequenceAnchor.preparedRolloverAction)
        try writer.append(sequenceAnchor.recoveryOrderingRequirement)
        let decoding = contract.transaction.journalDecoding
        try writer.append(count: decoding.maximumEncodedBytes)
        try writer.append(count: decoding.maximumFieldBytes)
        try writer.append(count: decoding.requiredReadChunkBytes)
        try writer.append(decoding.authenticationRequirement)
        try writer.append(decoding.canonicalityRequirement)
        try writer.append(contract.recovery.rawValue)
        try writer.append(outcome.rawValue)
    }
}

private func comparisonDocumentAppend(
    _ reason: ComparisonLifecycleState.StaleReason?,
    to writer: inout ComparisonDocumentCanonicalWriter
) throws {
    guard let reason else {
        try writer.append(UInt8(0))
        return
    }
    switch reason {
    case .sideChanged(let side):
        try writer.append(UInt8(1))
        try writer.append(comparisonDocumentLifecycleSideRank(side))
    case .optionsChanged:
        try writer.append(UInt8(2))
    case .externalChange(let side):
        try writer.append(UInt8(3))
        try writer.append(comparisonDocumentLifecycleSideRank(side))
    case .comparisonModeChanged:
        try writer.append(UInt8(4))
    }
}

private func comparisonDocumentCanonicalLifecycleSources(
    _ sources: [ComparisonDocumentLifecycleSourceBinding]
) throws -> [ComparisonDocumentLifecycleSourceBinding] {
    guard sources.count == 2 else {
        throw ComparisonDocumentCoverageError.inconsistentRevisionBindings
    }
    let sorted = sources.sorted()
    guard sorted.map(\.side) == ComparisonDocumentSide.allCases else {
        throw ComparisonDocumentCoverageError.inconsistentRevisionBindings
    }
    return sorted
}

private func comparisonDocumentCanonicalSideBindings(
    _ sides: [ComparisonDocumentSideRevisionBinding]
) throws -> [ComparisonDocumentSideRevisionBinding] {
    guard sides.count == 2 else {
        throw ComparisonDocumentCoverageError.inconsistentRevisionBindings
    }
    let sorted = sides.sorted { $0.side < $1.side }
    guard sorted.map(\.side) == ComparisonDocumentSide.allCases else {
        throw ComparisonDocumentCoverageError.inconsistentRevisionBindings
    }
    return sorted
}

private func comparisonDocumentCurrentSourceIsValid(
    _ binding: ComparisonDocumentSideRevisionBinding,
    scenario: ComparisonDocumentScenario
) -> Bool {
    switch scenario.incident[binding.side] {
    case .externalChange:
        guard case .file(let opened) = binding.openedSource,
            case .file(let incident)? = binding.incidentSource
        else { return false }
        guard incident.identity.location == opened.identity.location,
            comparisonDocumentSamePhysicalFile(incident.identity, opened.identity),
            incident.revision > opened.revision
        else { return false }
    case .replacement:
        guard case .file(let opened) = binding.openedSource,
            case .file(let incident)? = binding.incidentSource
        else { return false }
        guard incident.identity.location == opened.identity.location,
            !comparisonDocumentSamePhysicalFile(incident.identity, opened.identity)
        else { return false }
    case .missingDiskFile:
        guard binding.incidentSource == nil else { return false }
    case .none:
        guard binding.incidentSource == binding.openedSource else { return false }
    }

    let operation = scenario.save.operation(on: binding.side)
    switch scenario.save[binding.side] {
    case .notAttempted:
        return binding.currentSource == binding.openedSource
    case .failed:
        return binding.currentSource == binding.openedSource
    case .committed(let paneUpdate):
        switch (operation, paneUpdate) {
        case (.saveInPlace, .applied):
            guard case .file(let current)? = binding.currentSource,
                let committed = binding.saveOperation?.committedPayload
            else { return false }
            return current == committed
        case (_, .rejected(.bindingChanged)):
            guard let observedSource = binding.saveOperation?.paneUpdateObservedSource else {
                return false
            }
            return binding.currentSource == observedSource
        case (.saveInPlace, .rejected):
            return binding.currentSource == binding.openedSource
        case (.saveAsNewFile, .applied), (.saveAsReplacingFile, .applied):
            guard case .file(let current)? = binding.currentSource,
                let committed = binding.saveOperation?.committedPayload
            else { return false }
            return current == committed
        case (.saveAsNewFile, .rejected), (.saveAsReplacingFile, .rejected):
            return binding.currentSource == binding.openedSource
        case (.notAttempted, _):
            return false
        }
    case .uncertain:
        switch operation {
        case .saveInPlace:
            return binding.currentSource == binding.openedSource
        case .saveAsNewFile, .saveAsReplacingFile:
            return binding.currentSource == binding.openedSource
        case .notAttempted:
            return false
        }
    }
}

private func comparisonDocumentIncidentSourceIsValid(
    _ binding: ComparisonDocumentSideRevisionBinding,
    scenario: ComparisonDocumentScenario
) -> Bool {
    switch scenario.incident[binding.side] {
    case .none:
        return binding.incidentSource == binding.openedSource
    case .externalChange:
        guard case .file(let opened) = binding.openedSource,
            case .file(let incident)? = binding.incidentSource
        else { return false }
        return incident.identity.location == opened.identity.location
            && comparisonDocumentSamePhysicalFile(incident.identity, opened.identity)
            && incident.revision > opened.revision
    case .replacement:
        guard case .file(let opened) = binding.openedSource,
            case .file(let incident)? = binding.incidentSource
        else { return false }
        return incident.identity.location == opened.identity.location
            && !comparisonDocumentSamePhysicalFile(incident.identity, opened.identity)
    case .missingDiskFile:
        return binding.incidentSource == nil
    }
}

private func comparisonDocumentSaveDestinationIsValid(
    _ binding: ComparisonDocumentSideRevisionBinding,
    scenario: ComparisonDocumentScenario
) -> Bool {
    let operation = scenario.save.operation(on: binding.side)
    let outcome = scenario.save[binding.side]
    switch (operation, binding.openedSource, binding.saveDestination) {
    case (.notAttempted, _, .notApplicable):
        return true
    case (.saveInPlace, .file(let opened), .transition(let transition)):
        guard transition.expected.target == opened,
            transition.expected.slot.location == opened.identity.location
        else { return false }
        return comparisonDocumentDestinationTransitionIsValid(transition, outcome: outcome)
            && comparisonDocumentIncidentMatchesDestination(
                incidentSource: binding.incidentSource,
                transition: transition
            )
    case (.saveAsNewFile, let opened, .transition(let transition)):
        guard transition.expected.target == nil else { return false }
        if case .file(let openedFile) = opened,
            openedFile.identity.location == transition.expected.slot.location
        {
            return false
        }
        return comparisonDocumentDestinationTransitionIsValid(transition, outcome: outcome)
    case (.saveAsReplacingFile, let opened, .transition(let transition)):
        guard let destination = transition.expected.target else { return false }
        if case .file(let openedFile) = opened,
            openedFile.identity.location == destination.identity.location
                || comparisonDocumentSamePhysicalFile(openedFile.identity, destination.identity)
        {
            return false
        }
        guard comparisonDocumentDestinationTransitionIsValid(transition, outcome: outcome) else {
            return false
        }
        if case .committed = outcome {
            guard let committed = transition.observedAfterExecution?.target else { return false }
            return !comparisonDocumentSamePhysicalFile(committed.identity, destination.identity)
        }
        return true
    case (.notAttempted, _, _), (.saveInPlace, _, _), (.saveAsNewFile, _, _),
        (.saveAsReplacingFile, _, _):
        return false
    }
}

private func comparisonDocumentBackupEvidenceIsValid(
    _ binding: ComparisonDocumentSideRevisionBinding,
    scenario: ComparisonDocumentScenario
) -> Bool {
    guard case .required(_, _, let outcome) = scenario.backup[binding.side] else {
        return binding.completedBackup == nil
    }
    guard outcome == .completed else { return binding.completedBackup == nil }
    guard let backup = binding.completedBackup,
        case .transition(let saveDestination) = binding.saveDestination,
        let occupiedSource = saveDestination.observedBeforePublication.target,
        backup.sourceRevision == occupiedSource,
        backup.destination.expected.target == nil,
        comparisonDocumentDestinationTransitionIsValid(
            backup.destination,
            outcome: .committed(.applied)
        ),
        backup.destination.observedAfterExecution?.target == backup.committedPayload,
        comparisonDocumentFilePayloadMatches(
            backup.committedPayload,
            backup.sourceRevision
        ),
        backup.destination.expected.slot.location != saveDestination.expected.slot.location,
        !comparisonDocumentSamePhysicalFile(
            backup.committedPayload.identity,
            backup.sourceRevision.identity
        )
    else { return false }
    return true
}

private func comparisonDocumentDestinationTransitionIsValid(
    _ transition: ComparisonDocumentSaveDestinationTransition,
    outcome: ComparisonDocumentSideSaveOutcome
) -> Bool {
    let expected = transition.expected
    let observed = transition.observedBeforePublication
    guard expected.parent.identity.location == observed.parent.identity.location,
        expected.slot.location == observed.slot.location
    else { return false }
    if let after = transition.observedAfterExecution {
        guard after.parent.identity.location == expected.parent.identity.location,
            after.slot.location == expected.slot.location
        else { return false }
    }
    switch outcome {
    case .failed(.destinationCompareFailed):
        return expected != observed && transition.observedAfterExecution == observed
    case .failed:
        return expected == observed && transition.observedAfterExecution == observed
    case .uncertain:
        return expected == observed && transition.observedAfterExecution == nil
    case .committed:
        guard expected == observed, let after = transition.observedAfterExecution,
            comparisonDocumentPublishedDestinationIsValid(after, replacing: expected)
        else { return false }
        return true
    case .notAttempted:
        return false
    }
}

private func comparisonDocumentPublishedDestinationIsValid(
    _ after: ComparisonDocumentSaveDestinationSnapshot,
    replacing before: ComparisonDocumentSaveDestinationSnapshot
) -> Bool {
    guard after.parent.identity == before.parent.identity,
        after.parent.revision > before.parent.revision,
        after.slot.location == before.slot.location,
        after.slot.revision > before.slot.revision,
        let target = after.target
    else { return false }
    guard let previousTarget = before.target else { return true }
    if comparisonDocumentSamePhysicalFile(target.identity, previousTarget.identity) {
        return target.revision > previousTarget.revision
    }
    return true
}

private func comparisonDocumentIncidentMatchesDestination(
    incidentSource: ComparisonDocumentSourceRevision?,
    transition: ComparisonDocumentSaveDestinationTransition
) -> Bool {
    let target: ComparisonDocumentFileRevision?
    switch incidentSource {
    case .file(let file): target = file
    case .scratchpad, nil: target = nil
    }
    return transition.observedBeforePublication.target == target
}

private func comparisonDocumentDocumentRevisionsAreValid(
    _ binding: ComparisonDocumentSideRevisionBinding,
    scenario: ComparisonDocumentScenario
) -> Bool {
    guard binding.document.identity == binding.resultDocument.identity else { return false }
    if scenario.dirtyState.contains(binding.side) {
        return binding.document.generation > binding.resultDocument.generation
    }
    return binding.document == binding.resultDocument
}

private func comparisonDocumentResultPayloadIsValid(
    _ binding: ComparisonDocumentSideRevisionBinding
) -> Bool {
    switch binding.resultSource {
    case .file(let file):
        return comparisonDocumentCommittedPayloadMatches(file, source: binding.resultDocument)
    case .scratchpad(let scratchpad):
        return binding.resultDocument.encodedByteCount == scratchpad.encodedByteCount
            && binding.resultDocument.metadataByteCount == scratchpad.metadataByteCount
            && binding.resultDocument.encodedContentSHA256 == scratchpad.encodedContentSHA256
            && binding.resultDocument.metadataSHA256 == scratchpad.metadataSHA256
            && binding.resultDocument.contentAndMetadataSHA256
                == scratchpad.contentAndMetadataSHA256
            && binding.resultDocument.encoding == scratchpad.encoding
            && binding.resultDocument.isReadOnly == scratchpad.isReadOnly
    }
}

private func comparisonDocumentIsValidSourceRevision(
    _ revision: ComparisonDocumentSourceRevision,
    trustedLocationKeyReferences: Set<ComparisonDocumentStableID>?
) -> Bool {
    switch revision {
    case .file(let file):
        file.identity.volumeID != 0 && file.identity.fileID != 0
            && file.revision > 0
            && comparisonDocumentIsValidIdentifier(file.identity.location.keyReference.rawValue)
            && comparisonDocumentIsValidDigest(file.identity.location.hmacSHA256)
            && (trustedLocationKeyReferences?.contains(file.identity.location.keyReference) ?? true)
            && file.modificationTimeNanoseconds < 1_000_000_000
            && file.statusChangeTimeNanoseconds < 1_000_000_000
            && comparisonDocumentIsValidDigest(file.contentSHA256)
            && comparisonDocumentIsValidDigest(file.metadataSHA256)
            && comparisonDocumentIsValidDigest(file.contentAndMetadataSHA256)
            && comparisonDocumentEncodingIsValid(file)
    case .scratchpad(let scratchpad):
        comparisonDocumentIsValidUUID(scratchpad.identity)
            && comparisonDocumentIsValidDigest(scratchpad.encodedContentSHA256)
            && comparisonDocumentIsValidDigest(scratchpad.metadataSHA256)
            && comparisonDocumentIsValidDigest(scratchpad.contentAndMetadataSHA256)
            && comparisonDocumentEncodingIsValid(
                scratchpad.encoding,
                encodedByteCount: scratchpad.encodedByteCount
            )
    }
}

private func comparisonDocumentIsValidSaveDestination(
    _ destination: ComparisonDocumentSaveDestinationBinding,
    trustedLocationKeyReferences: Set<ComparisonDocumentStableID>?
) -> Bool {
    switch destination {
    case .notApplicable:
        true
    case .transition(let transition):
        [transition.expected, transition.observedBeforePublication]
            .allSatisfy {
                comparisonDocumentIsValidDestinationSnapshot(
                    $0,
                    trustedLocationKeyReferences: trustedLocationKeyReferences
                )
            }
            && (transition.observedAfterExecution.map {
                comparisonDocumentIsValidDestinationSnapshot(
                    $0,
                    trustedLocationKeyReferences: trustedLocationKeyReferences
                )
            } ?? true)
    }
}

private func comparisonDocumentIsValidCompletedBackup(
    _ backup: ComparisonDocumentCompletedBackupEvidence,
    trustedLocationKeyReferences: Set<ComparisonDocumentStableID>?
) -> Bool {
    comparisonDocumentIsValidSourceRevision(
        .file(backup.sourceRevision),
        trustedLocationKeyReferences: trustedLocationKeyReferences
    )
        && comparisonDocumentIsValidSaveDestination(
            .transition(backup.destination),
            trustedLocationKeyReferences: trustedLocationKeyReferences
        )
        && comparisonDocumentIsValidSourceRevision(
            .file(backup.committedPayload),
            trustedLocationKeyReferences: trustedLocationKeyReferences
        )
}

private func comparisonDocumentIsValidDestinationSnapshot(
    _ snapshot: ComparisonDocumentSaveDestinationSnapshot,
    trustedLocationKeyReferences: Set<ComparisonDocumentStableID>?
) -> Bool {
    guard snapshot.parent.identity.volumeID != 0,
        snapshot.parent.identity.fileID != 0,
        snapshot.parent.revision > 0,
        comparisonDocumentIsValidLocation(
            snapshot.parent.identity.location,
            trustedLocationKeyReferences: trustedLocationKeyReferences
        ),
        comparisonDocumentIsValidDigest(snapshot.parent.metadataSHA256),
        snapshot.slot.revision > 0,
        snapshot.parent.identity.location != snapshot.slot.location,
        comparisonDocumentIsValidLocation(
            snapshot.slot.location,
            trustedLocationKeyReferences: trustedLocationKeyReferences
        )
    else { return false }
    guard let target = snapshot.target else { return true }
    return target.identity.location == snapshot.slot.location
        && !comparisonDocumentSamePhysicalFile(target.identity, snapshot.parent.identity)
        && comparisonDocumentIsValidSourceRevision(
            .file(target),
            trustedLocationKeyReferences: trustedLocationKeyReferences
        )
}

private func comparisonDocumentIsValidLocation(
    _ location: ComparisonDocumentLocationIdentity,
    trustedLocationKeyReferences: Set<ComparisonDocumentStableID>?
) -> Bool {
    comparisonDocumentIsValidIdentifier(location.keyReference.rawValue)
        && comparisonDocumentIsValidDigest(location.hmacSHA256)
        && (trustedLocationKeyReferences?.contains(location.keyReference) ?? true)
}

private func comparisonDocumentSaveOperationIsValid(
    _ binding: ComparisonDocumentSideRevisionBinding,
    scenario: ComparisonDocumentScenario
) -> Bool {
    let operation = scenario.save.operation(on: binding.side)
    let outcome = scenario.save[binding.side]
    guard operation.isAttempted else {
        return binding.saveOperation == nil && binding.saveDestination == .notApplicable
    }
    guard let save = binding.saveOperation,
        comparisonDocumentIsValidUUID(save.planID),
        comparisonDocumentIsValidContentRevision(save.sourceDocument),
        comparisonDocumentSaveLimitsAreValid(save.limits),
        save.destinationPathUTF8ByteCount > 0,
        save.destinationPathUTF8ByteCount <= save.limits.maximumPathUTF8Bytes,
        save.parentPathUTF8ByteCount > 0,
        save.parentPathUTF8ByteCount <= save.limits.maximumPathUTF8Bytes,
        save.destinationPathUTF8ByteCount
            <= save.limits.maximumTotalPathUTF8Bytes - save.parentPathUTF8ByteCount,
        save.canonicalLeafIdentityUTF8ByteCount > 0,
        save.canonicalLeafIdentityUTF8ByteCount
            <= save.limits.maximumCanonicalLeafIdentityUTF8Bytes,
        save.plannedOperationCount == (scenario.save.execution == .batch ? 2 : 1),
        save.totalPathUTF8ByteCount
            >= save.destinationPathUTF8ByteCount + save.parentPathUTF8ByteCount,
        save.totalPathUTF8ByteCount <= save.limits.maximumTotalPathUTF8Bytes,
        scenario.save.execution == .batch
            || save.totalPathUTF8ByteCount
                == save.destinationPathUTF8ByteCount + save.parentPathUTF8ByteCount,
        save.estimatedWorkUnits <= save.limits.maximumWorkUnits,
        save.sourceDocument.encodedByteCount <= save.limits.maximumEncodedFileBytes,
        save.sourceDocument.metadataByteCount <= save.limits.maximumMetadataBytes
    else { return false }
    if scenario.save.execution != .batch {
        guard
            let expectedWorkUnits = comparisonDocumentExpectedSaveWorkUnits(
                totalPathUTF8ByteCount: save.totalPathUTF8ByteCount,
                operations: [save]
            ), save.estimatedWorkUnits == expectedWorkUnits
        else { return false }
    }
    switch outcome {
    case .failed(.sourceRevisionChanged), .committed(.rejected(.ownerRevisionChanged)):
        guard save.sourceDocument.identity == binding.document.identity,
            save.sourceDocument.generation < binding.document.generation
        else { return false }
    case .notAttempted, .failed, .uncertain, .committed:
        guard save.sourceDocument == binding.document else { return false }
    }
    switch (operation, binding.openedSource, save.sourceFile) {
    case (.saveInPlace, .file(let opened), .some(let sourceFile)):
        guard sourceFile == opened,
            comparisonDocumentFileFitsLimits(sourceFile, limits: save.limits)
        else { return false }
    case (.saveAsNewFile, .file(let opened), .some(let sourceFile)),
        (.saveAsReplacingFile, .file(let opened), .some(let sourceFile)):
        guard sourceFile == opened,
            comparisonDocumentFileFitsLimits(sourceFile, limits: save.limits)
        else { return false }
    case (.saveAsNewFile, .scratchpad, nil), (.saveAsReplacingFile, .scratchpad, nil):
        break
    case (.notAttempted, _, _), (.saveInPlace, _, _), (.saveAsNewFile, _, _),
        (.saveAsReplacingFile, _, _):
        return false
    }
    if case .transition(let transition) = binding.saveDestination {
        for file in [
            transition.expected.target,
            transition.observedBeforePublication.target,
            transition.observedAfterExecution?.target
        ].compactMap({ $0 }) where !comparisonDocumentFileFitsLimits(file, limits: save.limits) {
            return false
        }
    }
    switch outcome {
    case .committed(let paneUpdate):
        guard let committed = save.committedPayload,
            comparisonDocumentCommittedPayloadMatches(committed, source: save.sourceDocument),
            case .transition(let transition) = binding.saveDestination,
            transition.observedAfterExecution?.target == committed
        else { return false }
        switch paneUpdate {
        case .applied:
            return !save.planWasConsumedBeforePaneUpdate
                && save.paneUpdateObservedPlanID == save.planID
                && save.paneUpdateObservedDocument == save.sourceDocument
                && save.paneUpdateObservedSource == binding.openedSource
        case .rejected(.planAlreadyConsumed):
            return save.planWasConsumedBeforePaneUpdate
                && save.paneUpdateObservedPlanID == save.planID
                && (save.paneUpdateObservedDocument.map { $0 == save.sourceDocument } ?? true)
                && (save.paneUpdateObservedSource.map { $0 == binding.openedSource } ?? true)
        case .rejected(.ownerRevisionChanged):
            guard let observedDocument = save.paneUpdateObservedDocument else { return false }
            return !save.planWasConsumedBeforePaneUpdate
                && save.paneUpdateObservedPlanID == save.planID
                && observedDocument.identity == save.sourceDocument.identity
                && observedDocument.generation > save.sourceDocument.generation
                && observedDocument == binding.document
                && (save.paneUpdateObservedSource.map { $0 == binding.openedSource } ?? true)
        case .rejected(.bindingChanged):
            guard let observedDocument = save.paneUpdateObservedDocument,
                let observedSource = save.paneUpdateObservedSource
            else { return false }
            return !save.planWasConsumedBeforePaneUpdate
                && save.paneUpdateObservedPlanID == save.planID
                && observedDocument == save.sourceDocument
                && comparisonDocumentSourceRebindingIsValid(
                    observedSource,
                    replacing: binding.openedSource
                )
        }
    case .notAttempted, .failed, .uncertain:
        return save.committedPayload == nil && save.paneUpdateObservedDocument == nil
            && save.paneUpdateObservedSource == nil && save.paneUpdateObservedPlanID == nil
            && !save.planWasConsumedBeforePaneUpdate
    }
}

private func comparisonDocumentIsValidContentRevision(
    _ revision: ComparisonDocumentContentRevision
) -> Bool {
    comparisonDocumentIsValidUUID(revision.identity)
        && comparisonDocumentIsValidDigest(revision.encodedContentSHA256)
        && comparisonDocumentIsValidDigest(revision.metadataSHA256)
        && comparisonDocumentIsValidDigest(revision.contentAndMetadataSHA256)
        && comparisonDocumentEncodingIsValid(revision)
}

private func comparisonDocumentFileFitsLimits(
    _ file: ComparisonDocumentFileRevision,
    limits: ThreePaneSavePlanningLimits
) -> Bool {
    file.byteCount <= limits.maximumEncodedFileBytes
        && file.metadataByteCount <= limits.maximumMetadataBytes
}

private func comparisonDocumentCommittedPayloadMatches(
    _ committed: ComparisonDocumentFileRevision,
    source: ComparisonDocumentContentRevision
) -> Bool {
    committed.byteCount == source.encodedByteCount
        && committed.metadataByteCount == source.metadataByteCount
        && committed.contentSHA256 == source.encodedContentSHA256
        && committed.metadataSHA256 == source.metadataSHA256
        && committed.contentAndMetadataSHA256 == source.contentAndMetadataSHA256
        && committed.encoding == source.encoding
        && committed.isReadOnly == source.isReadOnly
}

private func comparisonDocumentFilePayloadMatches(
    _ copy: ComparisonDocumentFileRevision,
    _ source: ComparisonDocumentFileRevision
) -> Bool {
    copy.byteCount == source.byteCount
        && copy.metadataByteCount == source.metadataByteCount
        && copy.contentSHA256 == source.contentSHA256
        && copy.metadataSHA256 == source.metadataSHA256
        && copy.contentAndMetadataSHA256 == source.contentAndMetadataSHA256
        && copy.encoding == source.encoding
        && copy.isReadOnly == source.isReadOnly
}

private func comparisonDocumentSaveLimitsAreValid(_ limits: ThreePaneSavePlanningLimits) -> Bool {
    (1...ThreePaneSavePlanningLimits.hardMaximumOperations).contains(limits.maximumOperations)
        && (1...ThreePaneSavePlanningLimits.hardMaximumPathUTF8Bytes).contains(
            limits.maximumPathUTF8Bytes
        )
        && limits.maximumTotalPathUTF8Bytes >= limits.maximumPathUTF8Bytes
        && limits.maximumTotalPathUTF8Bytes
            <= ThreePaneSavePlanningLimits.hardMaximumTotalPathUTF8Bytes
        && (1...ThreePaneSavePlanningLimits.hardMaximumCanonicalLeafIdentityUTF8Bytes)
            .contains(limits.maximumCanonicalLeafIdentityUTF8Bytes)
        && limits.maximumEncodedFileBytes > 0
        && limits.maximumEncodedFileBytes <= ThreePaneSavePlanningLimits.hardMaximumEncodedFileBytes
        && limits.maximumMetadataBytes <= ThreePaneSavePlanningLimits.hardMaximumMetadataBytes
        && limits.maximumWorkUnits > 0
        && limits.maximumWorkUnits <= ThreePaneSavePlanningLimits.hardMaximumWorkUnits
}

private func comparisonDocumentExpectedSaveWorkUnits(
    totalPathUTF8ByteCount: Int,
    operations: [ComparisonDocumentSaveOperationBinding]
) -> UInt64? {
    guard let totalPath = UInt64(exactly: totalPathUTF8ByteCount),
        let operationCount = UInt64(exactly: operations.count)
    else { return nil }
    var result = totalPath
    for operation in operations {
        guard let leafBytes = UInt64(exactly: operation.canonicalLeafIdentityUTF8ByteCount) else {
            return nil
        }
        let addition = result.addingReportingOverflow(leafBytes)
        guard !addition.overflow else { return nil }
        result = addition.partialValue
    }
    let addition = result.addingReportingOverflow(operationCount)
    return addition.overflow ? nil : addition.partialValue
}

private func comparisonDocumentEncodingIsValid(
    _ document: ComparisonDocumentContentRevision
) -> Bool {
    comparisonDocumentEncodingIsValid(
        document.encoding,
        encodedByteCount: document.encodedByteCount
    )
}

private func comparisonDocumentEncodingIsValid(_ file: ComparisonDocumentFileRevision) -> Bool {
    comparisonDocumentEncodingIsValid(file.encoding, encodedByteCount: file.byteCount)
}

private func comparisonDocumentEncodingIsValid(
    _ encoding: ThreePaneSaveEncodingMetadata,
    encodedByteCount: UInt64
) -> Bool {
    switch encoding.encoding {
    case .utf8:
        return !encoding.hasByteOrderMark || encodedByteCount >= 3
    case .utf16LittleEndian, .utf16BigEndian:
        return encodedByteCount.isMultiple(of: 2)
            && (!encoding.hasByteOrderMark || encodedByteCount >= 2)
    case .shiftJIS, .japaneseEUC, .iso2022JP, .windows1250, .windows1251,
        .windows1252, .windows1253, .windows1254, .windows1255:
        return !encoding.hasByteOrderMark
    }
}

private func comparisonDocumentSidesDoNotCollide(
    _ sides: [ComparisonDocumentSideRevisionBinding]
) -> Bool {
    guard sides.count == 2 else { return false }
    let left = sides[0]
    let right = sides[1]
    guard left.document.identity != right.document.identity else { return false }
    let leftSources = comparisonDocumentFiles(in: left)
    let rightSources = comparisonDocumentFiles(in: right)
    for leftFile in leftSources {
        for rightFile in rightSources
        where comparisonDocumentSamePhysicalFile(leftFile.identity, rightFile.identity)
            || leftFile.identity.location == rightFile.identity.location
        {
            return false
        }
    }
    let leftDestination = comparisonDocumentDestinationLocation(left.saveDestination)
    let rightDestination = comparisonDocumentDestinationLocation(right.saveDestination)
    guard leftDestination == nil || rightDestination == nil || leftDestination != rightDestination else {
        return false
    }
    for (destination, oppositeFiles) in [
        (leftDestination, rightSources),
        (rightDestination, leftSources)
    ] {
        guard let destination else { continue }
        if oppositeFiles.contains(where: { $0.identity.location == destination }) { return false }
    }
    let destinationLocations = sides.flatMap(comparisonDocumentDestinationLocations)
    guard Set(destinationLocations).count == destinationLocations.count else { return false }
    let nonBackupFiles = sides.flatMap(comparisonDocumentNonBackupFiles)
    for binding in sides {
        if let backupDestination = binding.completedBackup?.destination.expected.slot.location,
            nonBackupFiles.contains(where: { $0.identity.location == backupDestination })
        {
            return false
        }
        if let backupPayload = binding.completedBackup?.committedPayload,
            nonBackupFiles.contains(where: {
                comparisonDocumentSamePhysicalFile(backupPayload.identity, $0.identity)
            })
        {
            return false
        }
    }
    for parent in sides.flatMap(comparisonDocumentDestinationParents) {
        if (leftSources + rightSources).contains(where: {
            comparisonDocumentSamePhysicalFile(parent.identity, $0.identity)
                || parent.identity.location == $0.identity.location
        }) {
            return false
        }
        if destinationLocations.contains(parent.identity.location) { return false }
    }
    return true
}

private func comparisonDocumentCommittedSaveAsTargetsDoNotAliasSources(
    _ sides: [ComparisonDocumentSideRevisionBinding]
) -> Bool {
    let sourceFiles = sides.flatMap { binding -> [ComparisonDocumentFileRevision] in
        var files: [ComparisonDocumentFileRevision] = []
        for source in [
            binding.openedSource,
            binding.saveOperation?.sourceFile.map(ComparisonDocumentSourceRevision.file)
        ].compactMap({ $0 }) {
            if case .file(let file) = source { files.append(file) }
        }
        return files
    }
    for binding in sides {
        guard let save = binding.saveOperation,
            let committed = save.committedPayload,
            case .transition(let transition) = binding.saveDestination,
            transition.observedAfterExecution?.target == committed
        else { continue }
        if transition.expected.target == save.sourceFile {
            continue
        }
        if sourceFiles.contains(where: {
            comparisonDocumentSamePhysicalFile(committed.identity, $0.identity)
        }) {
            return false
        }
    }
    return true
}

private func comparisonDocumentDestinationLocation(
    _ destination: ComparisonDocumentSaveDestinationBinding
) -> ComparisonDocumentLocationIdentity? {
    if case .transition(let transition) = destination { transition.expected.slot.location } else { nil }
}

private func comparisonDocumentDestinationParents(
    in binding: ComparisonDocumentSideRevisionBinding
) -> [ComparisonDocumentDirectoryRevision] {
    var parents: [ComparisonDocumentDirectoryRevision] = []
    if case .transition(let transition) = binding.saveDestination {
        parents.append(contentsOf: [
            transition.expected.parent,
            transition.observedBeforePublication.parent
        ])
        if let after = transition.observedAfterExecution?.parent { parents.append(after) }
    }
    if let transition = binding.completedBackup?.destination {
        parents.append(contentsOf: [
            transition.expected.parent,
            transition.observedBeforePublication.parent
        ])
        if let after = transition.observedAfterExecution?.parent { parents.append(after) }
    }
    return parents
}

private func comparisonDocumentDestinationLocations(
    in binding: ComparisonDocumentSideRevisionBinding
) -> [ComparisonDocumentLocationIdentity] {
    var locations: [ComparisonDocumentLocationIdentity] = []
    if let save = comparisonDocumentDestinationLocation(binding.saveDestination) {
        locations.append(save)
    }
    if let backup = binding.completedBackup?.destination.expected.slot.location {
        locations.append(backup)
    }
    return locations
}

private func comparisonDocumentNonBackupFiles(
    in binding: ComparisonDocumentSideRevisionBinding
) -> [ComparisonDocumentFileRevision] {
    var files: [ComparisonDocumentFileRevision] = []
    for source in [
        binding.openedSource,
        binding.incidentSource,
        binding.currentSource,
        binding.resultSource,
        binding.saveOperation?.paneUpdateObservedSource
    ].compactMap({ $0 }) {
        if case .file(let file) = source { files.append(file) }
    }
    if let source = binding.saveOperation?.sourceFile { files.append(source) }
    if let committed = binding.saveOperation?.committedPayload { files.append(committed) }
    if case .transition(let transition) = binding.saveDestination {
        for snapshot in [
            transition.expected,
            transition.observedBeforePublication,
            transition.observedAfterExecution
        ].compactMap({ $0 }) {
            if let target = snapshot.target { files.append(target) }
        }
    }
    if let backupSource = binding.completedBackup?.sourceRevision { files.append(backupSource) }
    return files
}

private func comparisonDocumentFiles(
    in binding: ComparisonDocumentSideRevisionBinding
) -> [ComparisonDocumentFileRevision] {
    var files: [ComparisonDocumentFileRevision] = []
    for source in [
        binding.openedSource,
        binding.incidentSource,
        binding.currentSource,
        binding.resultSource,
        binding.saveOperation?.paneUpdateObservedSource
    ].compactMap({ $0 }) {
        if case .file(let file) = source { files.append(file) }
    }
    if let sourceFile = binding.saveOperation?.sourceFile { files.append(sourceFile) }
    if let committedPayload = binding.saveOperation?.committedPayload { files.append(committedPayload) }
    if case .transition(let transition) = binding.saveDestination {
        for snapshot in [
            transition.expected,
            transition.observedBeforePublication,
            transition.observedAfterExecution
        ].compactMap({ $0 }) {
            if let target = snapshot.target { files.append(target) }
        }
    }
    if let backup = binding.completedBackup {
        files.append(backup.sourceRevision)
        files.append(backup.committedPayload)
        for snapshot in [
            backup.destination.expected,
            backup.destination.observedBeforePublication,
            backup.destination.observedAfterExecution
        ].compactMap({ $0 }) {
            if let target = snapshot.target { files.append(target) }
        }
    }
    return files
}

private func comparisonDocumentLocationKeyReferences(
    in binding: ComparisonDocumentSideRevisionBinding
) -> [ComparisonDocumentStableID] {
    var references = comparisonDocumentFiles(in: binding).map(\.identity.location.keyReference)
    if case .transition(let transition) = binding.saveDestination {
        for snapshot in [
            transition.expected,
            transition.observedBeforePublication,
            transition.observedAfterExecution
        ].compactMap({ $0 }) {
            references.append(snapshot.parent.identity.location.keyReference)
            references.append(snapshot.slot.location.keyReference)
        }
    }
    if let backup = binding.completedBackup {
        for snapshot in [
            backup.destination.expected,
            backup.destination.observedBeforePublication,
            backup.destination.observedAfterExecution
        ].compactMap({ $0 }) {
            references.append(snapshot.parent.identity.location.keyReference)
            references.append(snapshot.slot.location.keyReference)
        }
    }
    return references
}

private func comparisonDocumentRevisionAdvanced(
    _ current: ComparisonDocumentRevisionReference,
    from previous: ComparisonDocumentRevisionReference
) -> Bool {
    current.id == previous.id && current.revision > previous.revision
}

private let comparisonDocumentSaveFailureCases: [ThreePaneSaveNonCommitReason] = [
    .cancelled,
    .sourceRevisionChanged,
    .destinationCompareFailed,
    .safetyContractUnavailable,
    .publicationFailedBeforeMutation
]

private let comparisonDocumentSaveUncertaintyCases: [ThreePaneSaveCommitUncertainty] = [
    .publicationStateUnknown,
    .committedBytesUnverified,
    .durabilityUnverified,
    .recoveryStateUnknown
]

private let comparisonDocumentAttemptedSaveOutcomes: [ComparisonDocumentSideSaveOutcome] =
    comparisonDocumentSaveFailureCases.map(ComparisonDocumentSideSaveOutcome.failed)
    + comparisonDocumentSaveUncertaintyCases.map(ComparisonDocumentSideSaveOutcome.uncertain)
    + [ComparisonDocumentSideSaveOutcome.committed(.applied)]
    + ComparisonDocumentPaneUpdateRejection.allCases.map {
        ComparisonDocumentSideSaveOutcome.committed(.rejected($0))
    }

private let comparisonDocumentSideSaveOutcomeCount = comparisonDocumentAttemptedSaveOutcomes.count
private let comparisonDocumentMaximumSideSaveRank =
    ComparisonDocumentSideSaveOperation.allCases.filter(\.isAttempted).count
    * comparisonDocumentSideSaveOutcomeCount
private let comparisonDocumentSaveStateRadix =
    comparisonDocumentMaximumSideSaveRank * 2
    + (comparisonDocumentMaximumSideSaveRank - 1) * comparisonDocumentMaximumSideSaveRank
    + comparisonDocumentMaximumSideSaveRank + 1
private let comparisonDocumentSideBackupStateRadix = UInt8(
    ComparisonDocumentBackupExecutionOutcome.allCases.count + 1
)
private let comparisonDocumentBackupStateRadix =
    Int(comparisonDocumentSideBackupStateRadix)
    * Int(comparisonDocumentSideBackupStateRadix)

private let comparisonDocumentCanonicalSaveStates: [ComparisonDocumentSaveState] = {
    var states: [ComparisonDocumentSaveState] = [.notAttempted]
    let operations = ComparisonDocumentSideSaveOperation.allCases.filter(\.isAttempted)
    for operation in operations {
        for outcome in comparisonDocumentAttemptedSaveOutcomes {
            states.append(
                try! ComparisonDocumentSaveState(
                    execution: .single(.left),
                    leftOperation: operation,
                    left: outcome,
                    rightOperation: .notAttempted,
                    right: .notAttempted
                )
            )
            states.append(
                try! ComparisonDocumentSaveState(
                    execution: .single(.right),
                    leftOperation: .notAttempted,
                    left: .notAttempted,
                    rightOperation: operation,
                    right: outcome
                )
            )
        }
    }
    for leftOperation in operations {
        for rightOperation in operations {
            for left in comparisonDocumentAttemptedSaveOutcomes {
                for right in comparisonDocumentAttemptedSaveOutcomes
                where comparisonDocumentIsValidBatchSave(left: left, right: right) {
                    states.append(
                        try! ComparisonDocumentSaveState(
                            execution: .batch,
                            leftOperation: leftOperation,
                            left: left,
                            rightOperation: rightOperation,
                            right: right
                        )
                    )
                }
            }
        }
    }
    return states
}()

private func comparisonDocumentCanonicalBackupStates(
    for save: ComparisonDocumentSaveState,
    incident: ComparisonDocumentIncident
) -> [ComparisonDocumentBackupState] {
    func sideStates(_ side: ComparisonDocumentSide) -> [ComparisonDocumentSideBackupState] {
        switch save.operation(on: side) {
        case .notAttempted, .saveAsNewFile:
            return [.notApplicable]
        case .saveInPlace, .saveAsReplacingFile:
            if save[side] == .failed(.safetyContractUnavailable) {
                return ComparisonDocumentBackupExecutionOutcome.allCases.map {
                    .required(trigger: .beforeSave, contract: .required, outcome: $0)
                }
            }
            if save.operation(on: side) == .saveInPlace,
                incident[side] == .missingDiskFile
            {
                return [.required(trigger: .beforeSave, contract: .required, outcome: .notStarted)]
            }
            return [.required(trigger: .beforeSave, contract: .required, outcome: .completed)]
        }
    }
    return sideStates(.left).flatMap { left in
        sideStates(.right).map { right in
            ComparisonDocumentBackupState(left: left, right: right)
        }
    }
}

private let comparisonDocumentCanonicalScenariosByID = Dictionary(
    uniqueKeysWithValues: ComparisonDocumentCoverageMatrix.canonicalScenarios.map { ($0.id, $0) }
)

private func comparisonDocumentSideSaveRank(
    operation: ComparisonDocumentSideSaveOperation,
    outcome: ComparisonDocumentSideSaveOutcome
) -> Int {
    Int(operation.rawValue - 1) * comparisonDocumentSideSaveOutcomeCount + Int(outcome.rank)
}

private func comparisonDocumentSaveOperationIsValid(
    _ operation: ComparisonDocumentSideSaveOperation,
    sourceKind: ComparisonDocumentSourceKind
) -> Bool {
    switch (operation, sourceKind) {
    case (.notAttempted, _), (.saveInPlace, .file), (.saveAsNewFile, _),
        (.saveAsReplacingFile, _):
        true
    case (.saveInPlace, .scratchpad):
        false
    }
}

private func comparisonDocumentBackupIsValid(
    _ backup: ComparisonDocumentSideBackupState,
    operation: ComparisonDocumentSideSaveOperation,
    outcome: ComparisonDocumentSideSaveOutcome,
    incident: ComparisonDocumentSideIncident
) -> Bool {
    switch (operation, backup) {
    case (.notAttempted, .notApplicable), (.saveAsNewFile, .notApplicable):
        return true
    case (.saveInPlace, .required(let trigger, let contract, let backupOutcome)),
        (.saveAsReplacingFile, .required(let trigger, let contract, let backupOutcome)):
        guard trigger == .beforeSave, contract == .required else { return false }
        if operation == .saveInPlace, incident == .missingDiskFile {
            return backupOutcome == .notStarted
        }
        if backupOutcome == .completed { return true }
        return outcome == .failed(.safetyContractUnavailable)
    case (.notAttempted, .required), (.saveAsNewFile, .required),
        (.saveInPlace, .notApplicable), (.saveAsReplacingFile, .notApplicable):
        return false
    }
}

private func comparisonDocumentIncidentSaveRaceIsValid(
    incident: ComparisonDocumentSideIncident,
    operation: ComparisonDocumentSideSaveOperation,
    outcome: ComparisonDocumentSideSaveOutcome
) -> Bool {
    guard incident != .none, operation.isAttempted else { return true }
    if operation == .saveInPlace { return outcome == .failed(.destinationCompareFailed) }
    return operation == .saveAsNewFile || operation == .saveAsReplacingFile
}

private func comparisonDocumentIsValidBatchSave(
    left: ComparisonDocumentSideSaveOutcome,
    right: ComparisonDocumentSideSaveOutcome
) -> Bool {
    let preflightReasons: Set<ThreePaneSaveNonCommitReason> = [
        .cancelled, .sourceRevisionChanged, .destinationCompareFailed, .safetyContractUnavailable
    ]
    let hasPreflightFailure = [left, right].contains { outcome in
        if case .failed(let reason) = outcome { preflightReasons.contains(reason) } else { false }
    }
    guard hasPreflightFailure else { return true }
    return [left, right].allSatisfy { outcome in
        if case .failed(let reason) = outcome { preflightReasons.contains(reason) } else { false }
    }
}

private func comparisonDocumentSaveFailureRank(_ reason: ThreePaneSaveNonCommitReason) -> Int {
    switch reason {
    case .cancelled: 0
    case .sourceRevisionChanged: 1
    case .destinationCompareFailed: 2
    case .safetyContractUnavailable: 3
    case .publicationFailedBeforeMutation: 4
    }
}

private func comparisonDocumentSaveUncertaintyRank(_ reason: ThreePaneSaveCommitUncertainty) -> Int {
    switch reason {
    case .publicationStateUnknown: 0
    case .committedBytesUnverified: 1
    case .durabilityUnverified: 2
    case .recoveryStateUnknown: 3
    }
}

private func comparisonDocumentCaptureTimeIsValid(
    _ capturedAt: UInt64,
    policy: ComparisonDocumentAuditPolicy
) -> Bool {
    let earliest =
        policy.trustedAuditTimeUnixMilliseconds >= policy.maximumCaptureAgeMilliseconds
        ? policy.trustedAuditTimeUnixMilliseconds - policy.maximumCaptureAgeMilliseconds : 0
    let (latest, overflow) = policy.trustedAuditTimeUnixMilliseconds.addingReportingOverflow(
        policy.maximumFutureClockSkewMilliseconds
    )
    return capturedAt >= earliest && (overflow || capturedAt <= latest)
}

private func comparisonDocumentProvenanceSourceMatchesOrigin(
    _ source: ComparisonDocumentProvenanceSource,
    origin: ComparisonDocumentEvidenceOrigin
) -> Bool {
    switch (source, origin) {
    case (.automatedHarness, .productionAutomation),
        (.manualProductionReview, .productionManualMeasurement):
        true
    case (.automatedHarness, .productionManualMeasurement),
        (.automatedHarness, .callerAssertion),
        (.manualProductionReview, .productionAutomation),
        (.manualProductionReview, .callerAssertion):
        false
    }
}

private func comparisonDocumentSHA256(
    _ data: Data,
    budget: ComparisonDocumentWorkBudget
) throws -> [UInt8] {
    var hasher = SHA256()
    let chunkSize = max(1, min(64 * 1_024, budget.cancellationCheckInterval))
    var offset = data.startIndex
    while offset < data.endIndex {
        let end = data.index(offset, offsetBy: chunkSize, limitedBy: data.endIndex) ?? data.endIndex
        try budget.charge(data.distance(from: offset, to: end))
        hasher.update(data: data[offset..<end])
        offset = end
    }
    try budget.checkCancellation()
    return Array(hasher.finalize())
}

private func comparisonDocumentDataPrecedes(
    _ left: Data,
    _ right: Data,
    budget: ComparisonDocumentWorkBudget
) throws -> Bool {
    let commonCount = min(left.count, right.count)
    for index in 0..<commonCount {
        try budget.charge()
        if left[index] != right[index] { return left[index] < right[index] }
    }
    return left.count < right.count
}

private func comparisonDocumentBytesPrecede(
    _ left: [UInt8],
    _ right: [UInt8],
    budget: ComparisonDocumentWorkBudget
) throws -> Bool {
    for index in 0..<min(left.count, right.count) {
        try budget.charge()
        if left[index] != right[index] { return left[index] < right[index] }
    }
    return left.count < right.count
}

private func comparisonDocumentDataEquals(
    _ left: Data,
    _ right: Data,
    budget: ComparisonDocumentWorkBudget
) throws -> Bool {
    guard left.count == right.count else { return false }
    for (leftByte, rightByte) in zip(left, right) {
        try budget.charge()
        if leftByte != rightByte { return false }
    }
    return true
}

private func comparisonDocumentDeterministicWorkUnits(
    inventoryByteCount: Int,
    evidenceByteCount: Int,
    auditPolicyByteCount: Int,
    reportByteCount: Int,
    archiveByteCount: Int,
    observationCount: Int,
    findingCount: Int,
    maximum: Int
) throws -> Int {
    var total = 0
    for count in [
        inventoryByteCount,
        evidenceByteCount,
        auditPolicyByteCount,
        reportByteCount,
        archiveByteCount,
        observationCount,
        findingCount
    ] {
        guard count >= 0, count <= maximum, total <= maximum - count else {
            throw ComparisonDocumentCoverageError.workLimitExceeded(maximum: maximum)
        }
        total += count
    }
    return total
}

private func comparisonDocumentSort<Element>(
    _ values: inout [Element],
    by areInIncreasingOrder: (Element, Element) throws -> Bool
) throws {
    guard values.count > 1 else { return }
    var width = 1
    var source = values
    var destination = values
    while width < values.count {
        var start = 0
        while start < values.count {
            let middle = min(start + width, values.count)
            let end = min(start + width * 2, values.count)
            var left = start
            var right = middle
            var output = start
            while left < middle && right < end {
                if try areInIncreasingOrder(source[right], source[left]) {
                    destination[output] = source[right]
                    right += 1
                } else {
                    destination[output] = source[left]
                    left += 1
                }
                output += 1
            }
            while left < middle {
                destination[output] = source[left]
                left += 1
                output += 1
            }
            while right < end {
                destination[output] = source[right]
                right += 1
                output += 1
            }
            start = end
        }
        swap(&source, &destination)
        guard width <= values.count / 2 else { break }
        width *= 2
    }
    values = source
}

private func comparisonDocumentSamePhysicalFile(
    _ left: ComparisonDocumentFileIdentity,
    _ right: ComparisonDocumentFileIdentity
) -> Bool {
    left.volumeID == right.volumeID && left.fileID == right.fileID
        && left.generation == right.generation
}

private func comparisonDocumentSourceRebindingIsValid(
    _ current: ComparisonDocumentSourceRevision,
    replacing previous: ComparisonDocumentSourceRevision
) -> Bool {
    switch (current, previous) {
    case (.file(let current), .file(let previous)):
        guard current != previous else { return false }
        return !comparisonDocumentSamePhysicalFile(current.identity, previous.identity)
            || current.revision > previous.revision
    case (.scratchpad(let current), .scratchpad(let previous)):
        guard current != previous else { return false }
        return current.identity != previous.identity || current.generation > previous.generation
    case (.file, .scratchpad), (.scratchpad, .file):
        return false
    }
}

private func comparisonDocumentIsValidDigest(_ digest: [UInt8]) -> Bool {
    digest.count == SHA256.byteCount && digest.contains(where: { $0 != 0 })
}

private func comparisonDocumentIsValidIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value == value.precomposedStringWithCanonicalMapping else { return false }
    return value.unicodeScalars.allSatisfy {
        !CharacterSet.controlCharacters.contains($0) && !$0.properties.isWhitespace
    }
}

private func comparisonDocumentIsValidUUID(_ value: UUID) -> Bool {
    value.uuidString != "00000000-0000-0000-0000-000000000000"
}

private func comparisonDocumentCompareUTF8(_ left: String, _ right: String) -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        switch (leftIterator.next(), rightIterator.next()) {
        case (nil, nil): return 0
        case (nil, .some): return -1
        case (.some, nil): return 1
        case (.some(let leftByte), .some(let rightByte)):
            if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
        }
    }
}

private func comparisonDocumentCompareUTF8(
    _ left: String,
    _ right: String,
    budget: ComparisonDocumentWorkBudget
) throws -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        try budget.charge()
        switch (leftIterator.next(), rightIterator.next()) {
        case (nil, nil): return 0
        case (nil, .some): return -1
        case (.some, nil): return 1
        case (.some(let leftByte), .some(let rightByte)):
            if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
        }
    }
}

private func comparisonDocumentFrame(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
}

private func comparisonDocumentLifecycleRank(_ phase: ComparisonLifecycleState.Phase) -> UInt8 {
    switch phase {
    case .empty: 0
    case .oneSideLoaded: 1
    case .loading: 2
    case .current: 3
    case .stale: 4
    case .refreshing: 5
    case .failed: 6
    case .canceled: 7
    }
}

private func comparisonDocumentLifecycleSideRank(_ side: ComparisonLifecycleState.Side) -> UInt8 {
    switch side {
    case .left: 0
    case .middle: 1
    case .right: 2
    }
}

private func comparisonDocumentFindingMessage(_ code: ComparisonDocumentFindingCode) -> String {
    switch code {
    case .duplicateScenarioEvidence:
        "Comparison-document scenario has duplicate evidence."
    case .missingScenarioEvidence:
        "Comparison-document scenario has no production measurement."
    case .unexpectedScenarioEvidence:
        "Evidence targets a scenario outside the canonical document matrix."
    case .revisionBindingMismatch:
        "Observed open, comparison, document, or source revision binding is stale."
    case .sourceShapeMismatch:
        "Observed file and scratchpad identities do not match the canonical scenario."
    case .documentDirtyStateMismatch:
        "Observed independent dirty state does not match the canonical scenario."
    case .sourceAvailabilityMismatch:
        "Observed external or missing-file state does not match the canonical scenario."
    case .lifecycleMismatch:
        "Observed comparison lifecycle does not match the canonical scenario."
    case .staleReasonMismatch:
        "Observed lifecycle staleness reason does not match the source incident."
    case .saveStateMismatch:
        "Observed save outcome does not match the canonical scenario."
    case .saveContractMismatch:
        "Observed save planning contract is absent or incomplete."
    case .backupContractMismatch:
        "Observed before-save backup contract is absent or incomplete."
    case .productionProvenanceMissing:
        "Production measurement is missing capture provenance."
    case .productionProvenanceInvalid:
        "Production measurement has invalid capture provenance; details are redacted."
    case .provenanceBuildMismatch:
        "Production provenance is bound to another build revision."
    case .provenanceArtifactMismatch:
        "Production provenance is bound to another build artifact."
    case .untrustedCollector:
        "Production provenance names a collector outside the trusted inventory."
    case .productionCaptureMismatch:
        "Production capture cannot be resolved or does not match measured state."
    case .assertionOnlyEvidence:
        "Caller assertion cannot count as production-measured evidence."
    }
}

extension ComparisonDocumentSide {
    fileprivate init?(_ side: ComparisonLifecycleState.Side) {
        switch side {
        case .left: self = .left
        case .right: self = .right
        case .middle: return nil
        }
    }

    fileprivate var lifecycleSide: ComparisonLifecycleState.Side {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}
