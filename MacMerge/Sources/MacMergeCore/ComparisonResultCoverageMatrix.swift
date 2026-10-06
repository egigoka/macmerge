import CryptoKit
import Foundation

public enum ComparisonResultScenario: UInt8, CaseIterable, Comparable, Hashable, Sendable,
    Identifiable
{
    case identical
    case differentWithoutSelection
    case firstSelectedAtStart
    case middleSelectedAtStart
    case lastSelectedAtEnd
    case cursorAtDifferenceStart
    case cursorAtDifferenceEnd
    case cursorBeforeFirstDifference
    case cursorAfterLastDifference
    case selectionVisibleWithoutCursor
    case selectionVisibleWithCursorOnOtherDifference
    case selectionVisibleWithCursorOnUnchangedRow
    case selectionOffscreenWithCursorBefore
    case selectionOffscreenWithCursorAfter
    case selectionOffscreenWithoutCursor
    case cursorBetweenDifferences

    public var id: ComparisonResultScenarioID {
        ComparisonResultScenarioID(rawValue: UInt16(rawValue))
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

/// Extensible evidence coordinate. Values outside `ComparisonResultScenario.allCases` are reported
/// as unexpected rather than becoming unrepresentable input.
public struct ComparisonResultScenarioID: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

public struct ComparisonResultStableID: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        comparisonResultCompareUTF8(left.rawValue, right.rawValue) < 0
    }
}

/// Exact identity and monotonically advancing generation.
public struct ComparisonResultRevisionReference: Comparable, Hashable, Sendable {
    public let id: ComparisonResultStableID
    public let generation: UInt64

    public init(id: ComparisonResultStableID, generation: UInt64) {
        self.id = id
        self.generation = generation
    }

    public static func < (left: Self, right: Self) -> Bool {
        if left.id != right.id { return left.id < right.id }
        return left.generation < right.generation
    }
}

public struct ComparisonResultSourceBinding: Comparable, Hashable, Sendable {
    public let side: ComparisonLifecycleState.Side
    public let identity: ComparisonLifecycleState.SideIdentity
    public let generation: UInt64

    public init(
        side: ComparisonLifecycleState.Side,
        identity: ComparisonLifecycleState.SideIdentity,
        generation: UInt64
    ) {
        self.side = side
        self.identity = identity
        self.generation = generation
    }

    public static func < (left: Self, right: Self) -> Bool {
        if left.side != right.side { return left.side < right.side }
        let identityComparison = comparisonResultCompareUUID(left.identity.rawValue, right.identity.rawValue)
        if identityComparison != 0 { return identityComparison < 0 }
        return left.generation < right.generation
    }
}

/// Exact identity of one current lifecycle result and every source that produced it.
public struct ComparisonResultComparisonBinding: Hashable, Sendable {
    public let comparisonIdentity: ComparisonLifecycleState.Identity
    public let comparisonGeneration: UInt64
    public let inputIdentity: ComparisonLifecycleState.InputIdentity
    public let inputGeneration: UInt64
    public let operationID: ComparisonLifecycleState.OperationID
    public let operationStartedAtGeneration: UInt64
    public let resultIdentity: ComparisonLifecycleState.ResultID
    public let resultGeneration: UInt64
    public let sources: [ComparisonResultSourceBinding]

    public init(
        comparisonIdentity: ComparisonLifecycleState.Identity,
        comparisonGeneration: UInt64,
        inputIdentity: ComparisonLifecycleState.InputIdentity,
        inputGeneration: UInt64,
        operationID: ComparisonLifecycleState.OperationID,
        operationStartedAtGeneration: UInt64,
        resultIdentity: ComparisonLifecycleState.ResultID,
        resultGeneration: UInt64,
        sources: [ComparisonResultSourceBinding]
    ) throws {
        self.comparisonIdentity = comparisonIdentity
        self.comparisonGeneration = comparisonGeneration
        self.inputIdentity = inputIdentity
        self.inputGeneration = inputGeneration
        self.operationID = operationID
        self.operationStartedAtGeneration = operationStartedAtGeneration
        self.resultIdentity = resultIdentity
        self.resultGeneration = resultGeneration
        self.sources = try comparisonResultCanonicalSources(sources)
    }

    /// Captures a current result for authentication by `ComparisonResultCoverageAuthorityIssuer`.
    /// This value alone is not authoritative.
    fileprivate init(_ state: ComparisonLifecycleState) throws {
        guard state.phase == .current, state.hasCurrentResult,
            let inputs = state.inputs, let result = state.result, result.inputs == inputs,
            result.operation.comparisonIdentity == state.identity,
            result.operation.inputs == inputs
        else {
            throw ComparisonResultCoverageError.comparisonNotCurrent
        }

        try self.init(
            comparisonIdentity: state.identity,
            comparisonGeneration: state.generation,
            inputIdentity: inputs.identity,
            inputGeneration: inputs.generation,
            operationID: result.operation.operationID,
            operationStartedAtGeneration: result.operation.startedAtGeneration,
            resultIdentity: result.identity,
            resultGeneration: result.publishedAtGeneration,
            sources: inputs.sides.map {
                ComparisonResultSourceBinding(
                    side: $0.side,
                    identity: $0.identity,
                    generation: $0.generation
                )
            }
        )
    }
}

/// Opaque authority-authenticated identity of one current lifecycle result.
public struct ComparisonResultLifecycleIdentityToken: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let binding: ComparisonResultComparisonBinding
    package let authorityID: [UInt8]
    package let signature: [UInt8]

    package init(
        binding: ComparisonResultComparisonBinding,
        authorityID: [UInt8],
        signature: [UInt8]
    ) {
        self.binding = binding
        self.authorityID = authorityID
        self.signature = signature
    }

    public var description: String { "ComparisonResultLifecycleIdentityToken(<opaque>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["token": "<opaque>"], displayStyle: .struct)
    }
}

public enum ComparisonResultOutcome: UInt8, CaseIterable, Hashable, Sendable {
    case identical
    case different
}

public struct ComparisonResultDifference: Identifiable, Hashable, Sendable {
    public let id: ComparisonResultStableID
    /// Zero-based position in deterministic result navigation order.
    public let ordinal: Int
    /// Zero-based, half-open aligned-row range represented by this difference.
    public let rowRange: Range<Int>

    public init(id: ComparisonResultStableID, ordinal: Int, rowRange: Range<Int>) throws {
        guard ordinal >= 0, rowRange.lowerBound >= 0,
            rowRange.lowerBound < rowRange.upperBound,
            rowRange.upperBound <= ComparisonResultCoverageLimits.hardMaximumRows,
            comparisonResultIsValidIdentifier(id.rawValue)
        else {
            throw ComparisonResultCoverageError.invalidSemanticState
        }
        self.id = id
        self.ordinal = ordinal
        self.rowRange = rowRange
    }

    public var firstRow: Int { rowRange.lowerBound }
    public var lastRow: Int { rowRange.upperBound - 1 }
}

public enum ComparisonResultSelectionState: Hashable, Sendable {
    case none
    case difference(ComparisonResultStableID)

    public var differenceID: ComparisonResultStableID? {
        guard case .difference(let id) = self else { return nil }
        return id
    }
}

public enum ComparisonResultCursorState: Hashable, Sendable {
    case none
    /// `differenceID` is nil only when the cursor is on an unchanged aligned row.
    case row(index: Int, differenceID: ComparisonResultStableID?)

    public var rowIndex: Int? {
        guard case .row(let index, _) = self else { return nil }
        return index
    }

    public var differenceID: ComparisonResultStableID? {
        guard case .row(_, let differenceID) = self else { return nil }
        return differenceID
    }
}

public enum ComparisonResultSelectionVisibility: UInt8, CaseIterable, Hashable, Sendable {
    case notApplicable
    case visible
    case offscreen

    public init(_ visibility: ThreeWayDifferenceSelectionVisibility) {
        switch visibility {
        case .visible: self = .visible
        case .offscreen: self = .offscreen
        }
    }
}

/// Captured aligned-row extent and visible half-open row range.
public struct ComparisonResultViewportState: Hashable, Sendable {
    public let alignedRowCount: Int
    public let visibleRows: Range<Int>

    public init(alignedRowCount: Int, visibleRows: Range<Int>) throws {
        guard alignedRowCount >= 0,
            alignedRowCount <= ComparisonResultCoverageLimits.hardMaximumRows,
            visibleRows.lowerBound >= 0,
            visibleRows.lowerBound <= visibleRows.upperBound,
            visibleRows.upperBound <= alignedRowCount
        else {
            throw ComparisonResultCoverageError.invalidSemanticState
        }
        self.alignedRowCount = alignedRowCount
        self.visibleRows = visibleRows
    }
}

public struct ComparisonResultNavigationCommandState: Hashable, Sendable {
    public let first: Bool
    public let current: Bool
    public let previous: Bool
    public let next: Bool
    public let last: Bool

    public init(first: Bool, current: Bool, previous: Bool, next: Bool, last: Bool) {
        self.first = first
        self.current = current
        self.previous = previous
        self.next = next
        self.last = last
    }

    public init(_ navigation: ComparisonCommandState.DifferenceNavigation) {
        first = navigation.canSelectFirstDifference
        current = navigation.canSelectCurrentDifference
        previous = navigation.canSelectPreviousDifference
        next = navigation.canSelectNextDifference
        last = navigation.canSelectLastDifference
    }

    public init(_ states: ThreeWayDifferenceNavigationCommandStates) {
        first = states.first
        current = states.current
        previous = states.previous
        next = states.next
        last = states.last
    }
}

/// Result-related projection of shared command state. `hasResolvableDifference` follows
/// `ComparisonCommandState.Context.hasSelection`: a selection or cursor may satisfy it.
public struct ComparisonResultCommandState: Hashable, Sendable {
    public let hasSignificantDifferences: Bool
    public let hasResolvableDifference: Bool
    public let navigation: ComparisonResultNavigationCommandState

    public init(
        hasSignificantDifferences: Bool,
        hasResolvableDifference: Bool,
        navigation: ComparisonResultNavigationCommandState
    ) {
        self.hasSignificantDifferences = hasSignificantDifferences
        self.hasResolvableDifference = hasResolvableDifference
        self.navigation = navigation
    }

    public init(_ context: ComparisonCommandState.Context) {
        hasSignificantDifferences = context.hasSignificantDifferences
        hasResolvableDifference = context.hasSelection
        navigation = ComparisonResultNavigationCommandState(context.differenceNavigation)
    }
}

/// Semantic result state independent of editors, viewports, AppKit, and accessibility objects.
public struct ComparisonResultSemanticState: Hashable, Sendable {
    public let outcome: ComparisonResultOutcome
    public let differences: [ComparisonResultDifference]
    public let selection: ComparisonResultSelectionState
    public let cursor: ComparisonResultCursorState
    public let viewport: ComparisonResultViewportState
    public let selectionVisibility: ComparisonResultSelectionVisibility
    public let commandState: ComparisonResultCommandState

    public init(
        outcome: ComparisonResultOutcome,
        differences: [ComparisonResultDifference],
        selection: ComparisonResultSelectionState,
        cursor: ComparisonResultCursorState,
        viewport: ComparisonResultViewportState,
        commandState: ComparisonResultCommandState
    ) throws {
        self.outcome = outcome
        self.differences = differences
        self.selection = selection
        self.cursor = cursor
        self.viewport = viewport
        selectionVisibility = comparisonResultSelectionVisibility(
            selection: selection,
            differences: differences,
            viewport: viewport
        )
        self.commandState = commandState
        guard comparisonResultStateIsStructurallyValid(self) else {
            throw ComparisonResultCoverageError.invalidSemanticState
        }
    }

    public var selectedDifference: ComparisonResultDifference? {
        guard let id = selection.differenceID else { return nil }
        return differences.first { $0.id == id }
    }

    public var cursorDifference: ComparisonResultDifference? {
        guard let id = cursor.differenceID else { return nil }
        return differences.first { $0.id == id }
    }
}

/// Opaque externally authenticated accessibility inventory capability.
public struct ComparisonResultAccessibilityInventoryToken: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let receiptFormatVersion: Int
    public let app: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let buildArtifactSHA256: [UInt8]
    public let buildSigningIdentitySHA256: [UInt8]
    public let inventory: AccessibilityEvidenceRevisionReference
    public let evidence: AccessibilityEvidenceRevisionReference
    public let scenario: AccessibilityEvidenceRevisionReference
    public let snapshotID: AccessibilityStableID
    fileprivate let inventorySHA256: [UInt8]
    fileprivate let requiredEvidenceCount: Int
    fileprivate let authorityID: [UInt8]
    fileprivate let signature: [UInt8]

    fileprivate init(
        receiptFormatVersion: Int,
        app: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        buildArtifactSHA256: [UInt8],
        buildSigningIdentitySHA256: [UInt8],
        inventory: AccessibilityEvidenceRevisionReference,
        evidence: AccessibilityEvidenceRevisionReference,
        scenario: AccessibilityEvidenceRevisionReference,
        snapshotID: AccessibilityStableID,
        inventorySHA256: [UInt8],
        requiredEvidenceCount: Int,
        authorityID: [UInt8],
        signature: [UInt8]
    ) {
        self.receiptFormatVersion = receiptFormatVersion
        self.app = app
        self.build = build
        self.buildArtifactSHA256 = buildArtifactSHA256
        self.buildSigningIdentitySHA256 = buildSigningIdentitySHA256
        self.inventory = inventory
        self.evidence = evidence
        self.scenario = scenario
        self.snapshotID = snapshotID
        self.inventorySHA256 = inventorySHA256
        self.requiredEvidenceCount = requiredEvidenceCount
        self.authorityID = authorityID
        self.signature = signature
    }

    public var description: String { "ComparisonResultAccessibilityInventoryToken(<opaque>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["token": "<opaque>"], displayStyle: .struct)
    }
}

/// Opaque externally authenticated accessibility evidence capability.
public struct ComparisonResultAccessibilityEvidenceToken: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let receiptFormatVersion: Int
    public let app: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let buildArtifactSHA256: [UInt8]
    public let buildSigningIdentitySHA256: [UInt8]
    public let inventory: AccessibilityEvidenceRevisionReference
    public let evidence: AccessibilityEvidenceRevisionReference
    public let scenario: AccessibilityEvidenceRevisionReference
    public let snapshotID: AccessibilityStableID
    public let evidenceArchiveSHA256: [UInt8]
    public let requiredEvidenceCount: Int
    public let completeEvidenceCount: Int
    public let findingCount: Int
    public let archiveByteCount: Int
    fileprivate let inventorySHA256: [UInt8]
    fileprivate let authorityID: [UInt8]
    fileprivate let signature: [UInt8]

    fileprivate init(
        receiptFormatVersion: Int,
        app: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        buildArtifactSHA256: [UInt8],
        buildSigningIdentitySHA256: [UInt8],
        inventory: AccessibilityEvidenceRevisionReference,
        evidence: AccessibilityEvidenceRevisionReference,
        scenario: AccessibilityEvidenceRevisionReference,
        snapshotID: AccessibilityStableID,
        evidenceArchiveSHA256: [UInt8],
        inventorySHA256: [UInt8],
        requiredEvidenceCount: Int,
        completeEvidenceCount: Int,
        findingCount: Int,
        archiveByteCount: Int,
        authorityID: [UInt8],
        signature: [UInt8]
    ) {
        self.receiptFormatVersion = receiptFormatVersion
        self.app = app
        self.build = build
        self.buildArtifactSHA256 = buildArtifactSHA256
        self.buildSigningIdentitySHA256 = buildSigningIdentitySHA256
        self.inventory = inventory
        self.evidence = evidence
        self.scenario = scenario
        self.snapshotID = snapshotID
        self.evidenceArchiveSHA256 = evidenceArchiveSHA256
        self.inventorySHA256 = inventorySHA256
        self.requiredEvidenceCount = requiredEvidenceCount
        self.completeEvidenceCount = completeEvidenceCount
        self.findingCount = findingCount
        self.archiveByteCount = archiveByteCount
        self.authorityID = authorityID
        self.signature = signature
    }

    public var recordsCompleteEvidence: Bool {
        completeEvidenceCount == requiredEvidenceCount && findingCount == 0
    }

    public var description: String {
        "ComparisonResultAccessibilityEvidenceToken(<opaque>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["token": "<opaque>"], displayStyle: .struct)
    }
}

/// Link to generic accessibility evidence authenticated outside this audit.
public struct ComparisonResultAccessibilityRequirement: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let token: ComparisonResultAccessibilityInventoryToken

    public init(token: ComparisonResultAccessibilityInventoryToken) {
        self.token = token
    }

    public var description: String { "ComparisonResultAccessibilityRequirement(<opaque>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["requirement": "<opaque>"], displayStyle: .struct)
    }
}

public struct ComparisonResultCoverageRequirement: Identifiable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public var id: ComparisonResultScenarioID { scenario.id }

    public let scenario: ComparisonResultScenario
    public let lifecycle: ComparisonResultLifecycleIdentityToken
    public let expected: ComparisonResultSemanticState
    public let accessibility: ComparisonResultAccessibilityRequirement?

    public init(
        scenario: ComparisonResultScenario,
        lifecycle: ComparisonResultLifecycleIdentityToken,
        expected: ComparisonResultSemanticState,
        accessibility: ComparisonResultAccessibilityRequirement? = nil
    ) throws {
        guard comparisonResultState(expected, matches: scenario),
            expected.commandState == comparisonResultExpectedCommandState(for: expected)
        else {
            throw ComparisonResultCoverageError.invalidScenarioRequirement
        }
        self.scenario = scenario
        self.lifecycle = lifecycle
        self.expected = expected
        self.accessibility = accessibility
    }

    public var binding: ComparisonResultComparisonBinding { lifecycle.binding }
    public var description: String {
        "ComparisonResultCoverageRequirement(scenario: \(scenario), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["requirement": "<redacted>"], displayStyle: .struct)
    }
}

/// Exact build-bound inventory. Every canonical scenario must occur exactly once.
public struct ComparisonResultCoverageInventory: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: ComparisonResultRevisionReference
    public let build: ComparisonResultRevisionReference
    public let buildArtifactSHA256: [UInt8]
    public let requirements: [ComparisonResultCoverageRequirement]

    public init(
        reference: ComparisonResultRevisionReference,
        build: ComparisonResultRevisionReference,
        buildArtifactSHA256: [UInt8],
        requirements: [ComparisonResultCoverageRequirement]
    ) {
        self.reference = reference
        self.build = build
        self.buildArtifactSHA256 = buildArtifactSHA256
        self.requirements = requirements
    }

    public static func canonical(
        reference: ComparisonResultRevisionReference,
        build: ComparisonResultRevisionReference,
        buildArtifactSHA256: [UInt8],
        requirementsByScenario: [ComparisonResultScenario: ComparisonResultCoverageRequirement]
    ) throws -> Self {
        let requirements = try ComparisonResultCoverageMatrix.canonicalScenarios.map { scenario in
            guard let requirement = requirementsByScenario[scenario], requirement.scenario == scenario else {
                throw ComparisonResultCoverageError.invalidInventory(.inventoryRequirements)
            }
            return requirement
        }
        guard requirementsByScenario.count == requirements.count else {
            throw ComparisonResultCoverageError.invalidInventory(.inventoryRequirements)
        }
        return Self(
            reference: reference,
            build: build,
            buildArtifactSHA256: buildArtifactSHA256,
            requirements: requirements
        )
    }

    public var description: String {
        "ComparisonResultCoverageInventory(requirements: \(requirements.count), contents: <redacted>)"
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

/// Externally pinned Ed25519 identity for one production collector.
public struct ComparisonResultTrustedCollector: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: ComparisonResultRevisionReference
    fileprivate let ed25519PublicKey: [UInt8]

    public init(
        reference: ComparisonResultRevisionReference,
        ed25519PublicKey: [UInt8]
    ) throws {
        guard ed25519PublicKey.count == 32,
            (try? Curve25519.Signing.PublicKey(rawRepresentation: Data(ed25519PublicKey))) != nil
        else {
            throw ComparisonResultCoverageError.invalidTrustAnchor
        }
        self.reference = reference
        self.ed25519PublicKey = ed25519PublicKey
    }

    public var description: String { "ComparisonResultTrustedCollector(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["collector": "<redacted>"], displayStyle: .struct)
    }
}

public struct ComparisonResultReplayClaim: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let nonce: [UInt8]

    public init(nonce: [UInt8]) {
        self.nonce = nonce
    }

    public var description: String { "ComparisonResultReplayClaim(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["claim": "<redacted>"], displayStyle: .struct)
    }
}

/// Trusted audit time and atomic replay authority supplied independently from submitted evidence.
public struct ComparisonResultAuditPolicy: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public typealias ReplayClaim =
        @Sendable (
            _ replayPolicy: ComparisonResultRevisionReference,
            _ claims: [ComparisonResultReplayClaim]
        ) -> Bool

    public let trustedAuditTimeUnixMilliseconds: UInt64
    public let maximumCaptureAgeMilliseconds: UInt64
    public let maximumFutureClockSkewMilliseconds: UInt64
    public let replayPolicy: ComparisonResultRevisionReference
    private let claimReplayNonces: ReplayClaim

    public init(
        trustedAuditTimeUnixMilliseconds: UInt64,
        maximumCaptureAgeMilliseconds: UInt64,
        maximumFutureClockSkewMilliseconds: UInt64,
        replayPolicy: ComparisonResultRevisionReference,
        /// Must atomically reject a nonce already claimed under any replay-policy revision.
        claimReplayNonces: @escaping ReplayClaim
    ) {
        self.trustedAuditTimeUnixMilliseconds = trustedAuditTimeUnixMilliseconds
        self.maximumCaptureAgeMilliseconds = maximumCaptureAgeMilliseconds
        self.maximumFutureClockSkewMilliseconds = maximumFutureClockSkewMilliseconds
        self.replayPolicy = replayPolicy
        self.claimReplayNonces = claimReplayNonces
    }

    fileprivate func claim(_ claims: [ComparisonResultReplayClaim]) -> Bool {
        claimReplayNonces(replayPolicy, claims)
    }

    public var description: String { "ComparisonResultAuditPolicy(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["policy": "<redacted>"], displayStyle: .struct)
    }
}

/// Verification-only trust anchors supplied independently from inventory and evidence.
public struct ComparisonResultCoverageVerifier: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    fileprivate let authorityPublicKey: [UInt8]
    fileprivate let authorityID: [UInt8]
    fileprivate let collectors: [ComparisonResultTrustedCollector]

    package init(
        authorityEd25519PublicKey: [UInt8],
        trustedCollectors: [ComparisonResultTrustedCollector]
    ) throws {
        guard authorityEd25519PublicKey.count == 32,
            (try? Curve25519.Signing.PublicKey(
                rawRepresentation: Data(authorityEd25519PublicKey)
            )) != nil,
            !trustedCollectors.isEmpty,
            trustedCollectors.count <= ComparisonResultCoverageLimits.hardMaximumTrustedCollectors,
            Set(trustedCollectors.map(\.reference)).count == trustedCollectors.count
        else {
            throw ComparisonResultCoverageError.invalidTrustAnchor
        }
        authorityPublicKey = authorityEd25519PublicKey
        authorityID = Array(SHA256.hash(data: Data(authorityEd25519PublicKey)))
        collectors = trustedCollectors.sorted { $0.reference < $1.reference }
    }

    fileprivate func verifies(_ token: ComparisonResultLifecycleIdentityToken) throws -> Bool {
        guard token.authorityID == authorityID, token.signature.count == 64 else { return false }
        return try verify(
            signature: token.signature,
            data: comparisonResultLifecycleAuthenticationData(
                binding: token.binding,
                authorityID: token.authorityID,
                maximumBytes: ComparisonResultCoverageLimits.hardMaximumCanonicalBytes
            )
        )
    }

    fileprivate func verifies(
        _ token: ComparisonResultAccessibilityInventoryToken
    ) -> Bool {
        guard token.authorityID == authorityID, token.signature.count == 64,
            let data = try? comparisonResultAccessibilityInventoryAuthenticationData(
                token,
                maximumBytes: ComparisonResultCoverageLimits.hardMaximumCanonicalBytes
            )
        else { return false }
        return (try? verify(signature: token.signature, data: data)) == true
    }

    fileprivate func verifies(_ token: ComparisonResultAccessibilityEvidenceToken) -> Bool {
        guard token.authorityID == authorityID, token.signature.count == 64,
            let data = try? comparisonResultAccessibilityEvidenceAuthenticationData(
                token,
                maximumBytes: ComparisonResultCoverageLimits.hardMaximumCanonicalBytes
            )
        else { return false }
        return (try? verify(signature: token.signature, data: data)) == true
    }

    private func verify(signature: [UInt8], data: Data) throws -> Bool {
        do {
            return try Curve25519.Signing.PublicKey(rawRepresentation: Data(authorityPublicKey))
                .isValidSignature(Data(signature), for: data)
        } catch {
            throw ComparisonResultCoverageError.invalidTrustAnchor
        }
    }

    public var description: String { "ComparisonResultCoverageVerifier(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["verifier": "<redacted>"], displayStyle: .struct)
    }
}

/// Offline signer for lifecycle and accessibility capabilities. Verification environments pin only
/// its public key through `ComparisonResultCoverageVerifier`.
public struct ComparisonResultCoverageAuthorityIssuer: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    private let privateKey: [UInt8]
    public let publicKey: [UInt8]
    public let authorityID: [UInt8]

    public init(privateKeyRawRepresentation: [UInt8]) throws {
        let key: Curve25519.Signing.PrivateKey
        do {
            key = try Curve25519.Signing.PrivateKey(
                rawRepresentation: Data(privateKeyRawRepresentation)
            )
        } catch {
            throw ComparisonResultCoverageError.invalidAuthorityKey
        }
        privateKey = privateKeyRawRepresentation
        publicKey = Array(key.publicKey.rawRepresentation)
        authorityID = Array(SHA256.hash(data: key.publicKey.rawRepresentation))
    }

    public func authenticateCurrentLifecycle(
        _ state: ComparisonLifecycleState
    ) throws -> ComparisonResultLifecycleIdentityToken {
        let binding = try ComparisonResultComparisonBinding(state)
        let input = try comparisonResultLifecycleAuthenticationData(
            binding: binding,
            authorityID: authorityID,
            maximumBytes: ComparisonResultCoverageLimits.hardMaximumCanonicalBytes
        )
        return ComparisonResultLifecycleIdentityToken(
            binding: binding,
            authorityID: authorityID,
            signature: try sign(input)
        )
    }

    public func authenticateAccessibilityInventory(
        receipt: AccessibilityEvidenceReceipt,
        scenario: AccessibilityEvidenceRevisionReference,
        snapshotID: AccessibilityStableID
    ) throws -> ComparisonResultAccessibilityInventoryToken {
        guard comparisonResultIsValidIdentifier(scenario.id.rawValue),
            comparisonResultIsValidIdentifier(snapshotID.rawValue),
            receipt.formatVersion == AccessibilityEvidenceWorkflow.reportFormatVersion,
            receipt.requiredEvidenceCount > 0,
            receipt.completeEvidenceCount == receipt.requiredEvidenceCount,
            receipt.findingCount == 0,
            receipt.archiveByteCount > 0,
            comparisonResultIsValidDigest(receipt.buildBinding.artifactSHA256),
            comparisonResultIsValidDigest(receipt.buildBinding.signingIdentitySHA256),
            comparisonResultIsValidDigest(receipt.inventorySHA256),
            comparisonResultIsValidDigest(receipt.evidenceArchiveSHA256)
        else {
            throw ComparisonResultCoverageError.invalidEvidence(.accessibilityBinding)
        }
        let unsigned = ComparisonResultAccessibilityInventoryToken(
            receiptFormatVersion: receipt.formatVersion,
            app: receipt.app,
            build: receipt.build,
            buildArtifactSHA256: receipt.buildBinding.artifactSHA256,
            buildSigningIdentitySHA256: receipt.buildBinding.signingIdentitySHA256,
            inventory: receipt.inventory,
            evidence: receipt.evidence,
            scenario: scenario,
            snapshotID: snapshotID,
            inventorySHA256: receipt.inventorySHA256,
            requiredEvidenceCount: receipt.requiredEvidenceCount,
            authorityID: authorityID,
            signature: []
        )
        let input = try comparisonResultAccessibilityInventoryAuthenticationData(
            unsigned,
            maximumBytes: ComparisonResultCoverageLimits.hardMaximumCanonicalBytes
        )
        return ComparisonResultAccessibilityInventoryToken(
            receiptFormatVersion: unsigned.receiptFormatVersion,
            app: unsigned.app,
            build: unsigned.build,
            buildArtifactSHA256: unsigned.buildArtifactSHA256,
            buildSigningIdentitySHA256: unsigned.buildSigningIdentitySHA256,
            inventory: unsigned.inventory,
            evidence: unsigned.evidence,
            scenario: unsigned.scenario,
            snapshotID: unsigned.snapshotID,
            inventorySHA256: unsigned.inventorySHA256,
            requiredEvidenceCount: unsigned.requiredEvidenceCount,
            authorityID: authorityID,
            signature: try sign(input)
        )
    }

    public func authenticateAccessibilityEvidence(
        receipt: AccessibilityEvidenceReceipt,
        scenario: AccessibilityEvidenceRevisionReference,
        snapshotID: AccessibilityStableID
    ) throws -> ComparisonResultAccessibilityEvidenceToken {
        guard comparisonResultIsValidIdentifier(scenario.id.rawValue),
            comparisonResultIsValidIdentifier(snapshotID.rawValue),
            receipt.formatVersion == AccessibilityEvidenceWorkflow.reportFormatVersion,
            receipt.requiredEvidenceCount > 0,
            receipt.completeEvidenceCount == receipt.requiredEvidenceCount,
            receipt.findingCount == 0,
            receipt.archiveByteCount > 0,
            comparisonResultIsValidDigest(receipt.buildBinding.artifactSHA256),
            comparisonResultIsValidDigest(receipt.buildBinding.signingIdentitySHA256),
            comparisonResultIsValidDigest(receipt.inventorySHA256),
            comparisonResultIsValidDigest(receipt.evidenceArchiveSHA256)
        else {
            throw ComparisonResultCoverageError.invalidEvidence(.accessibilityBinding)
        }
        let unsigned = ComparisonResultAccessibilityEvidenceToken(
            receiptFormatVersion: receipt.formatVersion,
            app: receipt.app,
            build: receipt.build,
            buildArtifactSHA256: receipt.buildBinding.artifactSHA256,
            buildSigningIdentitySHA256: receipt.buildBinding.signingIdentitySHA256,
            inventory: receipt.inventory,
            evidence: receipt.evidence,
            scenario: scenario,
            snapshotID: snapshotID,
            evidenceArchiveSHA256: receipt.evidenceArchiveSHA256,
            inventorySHA256: receipt.inventorySHA256,
            requiredEvidenceCount: receipt.requiredEvidenceCount,
            completeEvidenceCount: receipt.completeEvidenceCount,
            findingCount: receipt.findingCount,
            archiveByteCount: receipt.archiveByteCount,
            authorityID: authorityID,
            signature: []
        )
        let input = try comparisonResultAccessibilityEvidenceAuthenticationData(
            unsigned,
            maximumBytes: ComparisonResultCoverageLimits.hardMaximumCanonicalBytes
        )
        return ComparisonResultAccessibilityEvidenceToken(
            receiptFormatVersion: unsigned.receiptFormatVersion,
            app: unsigned.app,
            build: unsigned.build,
            buildArtifactSHA256: unsigned.buildArtifactSHA256,
            buildSigningIdentitySHA256: unsigned.buildSigningIdentitySHA256,
            inventory: unsigned.inventory,
            evidence: unsigned.evidence,
            scenario: unsigned.scenario,
            snapshotID: unsigned.snapshotID,
            evidenceArchiveSHA256: unsigned.evidenceArchiveSHA256,
            inventorySHA256: unsigned.inventorySHA256,
            requiredEvidenceCount: unsigned.requiredEvidenceCount,
            completeEvidenceCount: unsigned.completeEvidenceCount,
            findingCount: unsigned.findingCount,
            archiveByteCount: unsigned.archiveByteCount,
            authorityID: authorityID,
            signature: try sign(input)
        )
    }

    private func sign(_ data: Data) throws -> [UInt8] {
        do {
            return Array(
                try Curve25519.Signing.PrivateKey(rawRepresentation: Data(privateKey))
                    .signature(for: data)
            )
        } catch {
            throw ComparisonResultCoverageError.invalidAuthorityKey
        }
    }

    public var description: String { "ComparisonResultCoverageAuthorityIssuer(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["issuer": "<redacted>"], displayStyle: .struct)
    }
}

public enum ComparisonResultEvidenceOrigin: UInt8, CaseIterable, Hashable, Sendable {
    case productionAutomatedMeasurement
    case productionManualMeasurement
    case callerAssertion

    public var isMeasuredProductionEvidence: Bool {
        self != .callerAssertion
    }
}

public struct ComparisonResultEvidenceProvenance: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let build: ComparisonResultRevisionReference
    public let inventory: ComparisonResultRevisionReference
    public let collector: ComparisonResultRevisionReference
    public let capturedAtUnixMilliseconds: UInt64
    public let runNonce: [UInt8]
    public let artifactSHA256: [UInt8]
    public let inventorySHA256: [UInt8]
    public let captureSHA256: [UInt8]
    public let collectorSignature: [UInt8]
    public let source: String

    public init(
        build: ComparisonResultRevisionReference,
        inventory: ComparisonResultRevisionReference,
        collector: ComparisonResultRevisionReference,
        capturedAtUnixMilliseconds: UInt64,
        runNonce: [UInt8],
        artifactSHA256: [UInt8],
        inventorySHA256: [UInt8],
        captureSHA256: [UInt8],
        collectorSignature: [UInt8],
        source: String
    ) {
        self.build = build
        self.inventory = inventory
        self.collector = collector
        self.capturedAtUnixMilliseconds = capturedAtUnixMilliseconds
        self.runNonce = runNonce
        self.artifactSHA256 = artifactSHA256
        self.inventorySHA256 = inventorySHA256
        self.captureSHA256 = captureSHA256
        self.collectorSignature = collectorSignature
        self.source = source.precomposedStringWithCanonicalMapping
    }

    public var description: String { "ComparisonResultEvidenceProvenance(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["provenance": "<redacted>"], displayStyle: .struct)
    }
}

extension ComparisonResultTrustedCollector {
    fileprivate func verifies(signature: [UInt8], data: Data) -> Bool {
        guard signature.count == 64 else { return false }
        return
            (try? Curve25519.Signing.PublicKey(rawRepresentation: Data(ed25519PublicKey))
            .isValidSignature(Data(signature), for: data)) == true
    }
}

/// Caller-supplied result observation. Only measured production origins with valid provenance can
/// complete a matrix cell; assertions remain findings even when values happen to match.
public struct ComparisonResultEvidence: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let scenarioID: ComparisonResultScenarioID
    public let lifecycle: ComparisonResultLifecycleIdentityToken
    public let observed: ComparisonResultSemanticState
    public let origin: ComparisonResultEvidenceOrigin
    public let provenance: ComparisonResultEvidenceProvenance?
    public let accessibility: ComparisonResultAccessibilityEvidenceToken?

    public init(
        scenarioID: ComparisonResultScenarioID,
        lifecycle: ComparisonResultLifecycleIdentityToken,
        observed: ComparisonResultSemanticState,
        origin: ComparisonResultEvidenceOrigin,
        provenance: ComparisonResultEvidenceProvenance?,
        accessibility: ComparisonResultAccessibilityEvidenceToken? = nil
    ) {
        self.scenarioID = scenarioID
        self.lifecycle = lifecycle
        self.observed = observed
        self.origin = origin
        self.provenance = provenance
        self.accessibility = accessibility
    }

    public init(
        scenario: ComparisonResultScenario,
        lifecycle: ComparisonResultLifecycleIdentityToken,
        observed: ComparisonResultSemanticState,
        origin: ComparisonResultEvidenceOrigin,
        provenance: ComparisonResultEvidenceProvenance?,
        accessibility: ComparisonResultAccessibilityEvidenceToken? = nil
    ) {
        self.init(
            scenarioID: scenario.id,
            lifecycle: lifecycle,
            observed: observed,
            origin: origin,
            provenance: provenance,
            accessibility: accessibility
        )
    }

    public var binding: ComparisonResultComparisonBinding { lifecycle.binding }

    public var description: String {
        "ComparisonResultEvidence(scenario: \(scenarioID.rawValue), contents: <redacted>)"
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

public struct ComparisonResultEvidenceBundle: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: ComparisonResultRevisionReference
    public let inventory: ComparisonResultRevisionReference
    public let build: ComparisonResultRevisionReference
    public let observations: [ComparisonResultEvidence]

    public init(
        reference: ComparisonResultRevisionReference,
        inventory: ComparisonResultRevisionReference,
        build: ComparisonResultRevisionReference,
        observations: [ComparisonResultEvidence]
    ) {
        self.reference = reference
        self.inventory = inventory
        self.build = build
        self.observations = observations
    }

    public var description: String {
        "ComparisonResultEvidenceBundle(observations: \(observations.count), contents: <redacted>)"
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

public protocol ComparisonResultCaptureResourceError: Error, Sendable {}

public enum ComparisonResultCaptureResolutionError: Error, Hashable, Sendable {
    case exceedsMaximumByteCount
    case resourceUnavailable
}

public struct ComparisonResultCoverageLimits: Hashable, Sendable {
    public static let hardMaximumTrustedCollectors = 1_024
    public static let hardMaximumObservations = 100_000
    public static let hardMaximumDifferencesPerScenario = 1_048_576
    public static let hardMaximumTotalDifferences = 4 * 1_048_576
    public static let hardMaximumRows = 1_048_576
    public static let hardMaximumStringUTF8Bytes = 1 * 1_024 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 64 * 1_024 * 1_024
    public static let hardMaximumBinaryMetadataBytes = 4_096
    public static let hardMaximumWorkUnits = 256 * 1_048_576
    public static let hardMaximumFindings = 100_000
    public static let hardMaximumCanonicalBytes = 64 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = ComparisonResultCoverageLimits()

    public let maximumTrustedCollectors: Int
    public let maximumObservations: Int
    public let maximumDifferencesPerScenario: Int
    public let maximumTotalDifferences: Int
    public let maximumRows: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumBinaryMetadataBytes: Int
    public let maximumWorkUnits: Int
    public let maximumFindings: Int
    public let maximumCanonicalBytes: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumTrustedCollectors: Int = 64,
        maximumObservations: Int = 4_096,
        maximumDifferencesPerScenario: Int = 65_536,
        maximumTotalDifferences: Int = 262_144,
        maximumRows: Int = 1_048_576,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumBinaryMetadataBytes: Int = 512,
        maximumWorkUnits: Int = 64 * 1_048_576,
        maximumFindings: Int = 4_096,
        maximumCanonicalBytes: Int = 8 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) {
        self.maximumTrustedCollectors = maximumTrustedCollectors
        self.maximumObservations = maximumObservations
        self.maximumDifferencesPerScenario = maximumDifferencesPerScenario
        self.maximumTotalDifferences = maximumTotalDifferences
        self.maximumRows = maximumRows
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumBinaryMetadataBytes = maximumBinaryMetadataBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumFindings = maximumFindings
        self.maximumCanonicalBytes = maximumCanonicalBytes
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum ComparisonResultCoverageLimit: String, CaseIterable, Hashable, Sendable {
    case trustedCollectors
    case observations
    case differencesPerScenario
    case totalDifferences
    case rows
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case binaryMetadataBytes
    case workUnits
    case findings
    case canonicalBytes
    case cancellationCheckInterval
}

public enum ComparisonResultCoverageField: String, CaseIterable, Hashable, Sendable {
    case inventoryReference
    case inventoryBuild
    case inventoryRequirements
    case evidenceReference
    case evidenceInventory
    case evidenceBuild
    case comparisonBinding
    case semanticState
    case accessibilityBinding
    case lifecycleAuthentication
    case provenance
    case provenanceSource
    case auditPolicy
    case receipt
}

public enum ComparisonResultCoverageError: Error, Hashable, LocalizedError, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case cancelled
    case comparisonNotCurrent
    case invalidComparisonBinding
    case invalidSemanticState
    case invalidScenarioRequirement
    case invalidLimit(ComparisonResultCoverageLimit)
    case countLimitExceeded(ComparisonResultCoverageLimit, maximum: Int)
    case stringTooLarge(ComparisonResultCoverageField, maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case binaryMetadataTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximum: Int)
    case findingLimitExceeded(maximum: Int)
    case canonicalDataTooLarge(maximumBytes: Int)
    case invalidTrustAnchor
    case invalidAuthorityKey
    case invalidInventory(ComparisonResultCoverageField)
    case invalidEvidence(ComparisonResultCoverageField)
    case staleBuild
    case staleInventory
    case staleEvidence
    case receiptMismatch
    case replayClaimRejected

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Comparison-result coverage audit was cancelled."
        case .comparisonNotCurrent:
            "Comparison-result binding requires an exact current lifecycle result."
        case .invalidComparisonBinding:
            "Comparison-result identity binding is invalid; contents are redacted."
        case .invalidSemanticState:
            "Comparison-result semantic state is invalid; contents are redacted."
        case .invalidScenarioRequirement:
            "Comparison-result scenario requirement is not canonical."
        case .invalidLimit(let limit):
            "Comparison-result coverage limit is invalid: \(limit.rawValue)."
        case .countLimitExceeded(let limit, let maximum):
            "Comparison-result coverage exceeds the \(maximum)-\(limit.rawValue) limit."
        case .stringTooLarge(let field, let maximum):
            "Comparison-result field \(field.rawValue) exceeds \(maximum) UTF-8 bytes; contents are redacted."
        case .totalStringsTooLarge(let maximum):
            "Comparison-result strings exceed \(maximum) UTF-8 bytes; contents are redacted."
        case .binaryMetadataTooLarge(let maximum):
            "Comparison-result binary metadata exceeds \(maximum) bytes; contents are redacted."
        case .workLimitExceeded(let maximum):
            "Comparison-result coverage audit exceeds \(maximum) work units."
        case .findingLimitExceeded(let maximum):
            "Comparison-result coverage audit exceeds \(maximum) findings."
        case .canonicalDataTooLarge(let maximum):
            "Comparison-result canonical data exceeds \(maximum) bytes."
        case .invalidTrustAnchor:
            "Comparison-result verification trust anchor is invalid; contents are redacted."
        case .invalidAuthorityKey:
            "Comparison-result authentication authority key is invalid; contents are redacted."
        case .invalidInventory(let field):
            "Comparison-result inventory is invalid at \(field.rawValue); contents are redacted."
        case .invalidEvidence(let field):
            "Comparison-result evidence is invalid at \(field.rawValue); contents are redacted."
        case .staleBuild:
            "Comparison-result evidence belongs to another build identity or generation."
        case .staleInventory:
            "Comparison-result evidence belongs to another inventory identity or generation."
        case .staleEvidence:
            "Comparison-result evidence generation changed before receipt validation."
        case .receiptMismatch:
            "Comparison-result receipt no longer matches current canonical contents."
        case .replayClaimRejected:
            "Comparison-result production evidence nonce was already claimed."
        }
    }

    public var description: String { errorDescription ?? "Comparison-result coverage error." }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["error": description], displayStyle: .enum)
    }
}

public enum ComparisonResultFindingSeverity: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case advisory
    case warning
    case error

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

public enum ComparisonResultFindingCode: String, CaseIterable, Hashable, Sendable {
    case duplicateScenarioEvidence
    case missingScenarioEvidence
    case unexpectedScenarioEvidence
    case comparisonIdentityMismatch
    case inputIdentityMismatch
    case resultIdentityMismatch
    case operationIdentityMismatch
    case sourceIdentityMismatch
    case generationMismatch
    case resultStateMismatch
    case selectionStateMismatch
    case cursorStateMismatch
    case viewportStateMismatch
    case selectionVisibilityMismatch
    case commandStateMismatch
    case accessibilityEvidenceMissing
    case accessibilityEvidenceMismatch
    case accessibilityEvidenceIncomplete
    case lifecycleAuthenticationInvalid
    case accessibilityAuthenticationInvalid
    case productionProvenanceMissing
    case productionProvenanceInvalid
    case provenanceBuildMismatch
    case provenanceInventoryMismatch
    case provenanceArtifactMismatch
    case untrustedCollector
    case productionCaptureMismatch
    case assertionOnlyEvidence
}

public enum ComparisonResultFindingSubject: Hashable, Sendable {
    case matrix
    case scenario(ComparisonResultScenarioID)
}

public struct ComparisonResultFinding: Identifiable, Hashable, Sendable {
    public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            comparisonResultCompareUTF8(left.rawValue, right.rawValue) < 0
        }
    }

    public let id: ID
    public let severity: ComparisonResultFindingSeverity
    public let code: ComparisonResultFindingCode
    public let subject: ComparisonResultFindingSubject
    /// Fixed wording. Source identifiers, generations, digests, and observed values are omitted.
    public let message: String

    fileprivate init(
        severity: ComparisonResultFindingSeverity,
        code: ComparisonResultFindingCode,
        subject: ComparisonResultFindingSubject,
        discriminator: Int = 0
    ) {
        self.severity = severity
        self.code = code
        self.subject = subject
        message = comparisonResultFindingMessage(code)
        let subjectValue: String
        switch subject {
        case .matrix: subjectValue = "matrix"
        case .scenario(let id): subjectValue = "scenario:\(id.rawValue)"
        }
        id = ID(
            rawValue: [code.rawValue, subjectValue, String(discriminator)]
                .map(comparisonResultFrame).joined()
        )
    }
}

public enum ComparisonResultCompletenessStatus: UInt8, CaseIterable, Hashable, Sendable {
    case complete
    case missing
    case duplicate
    case mismatched
    case invalid
    case assertionOnly
}

public struct ComparisonResultCompletenessCell: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let scenario: ComparisonResultScenario
    public let expected: ComparisonResultSemanticState
    public let observed: ComparisonResultSemanticState?
    public let evidenceCount: Int
    public let status: ComparisonResultCompletenessStatus

    fileprivate init(
        scenario: ComparisonResultScenario,
        expected: ComparisonResultSemanticState,
        observed: ComparisonResultSemanticState?,
        evidenceCount: Int,
        status: ComparisonResultCompletenessStatus
    ) {
        self.scenario = scenario
        self.expected = expected
        self.observed = observed
        self.evidenceCount = evidenceCount
        self.status = status
    }

    public var description: String {
        "ComparisonResultCompletenessCell(scenario: \(scenario), count: \(evidenceCount), status: \(status), values: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "scenario": scenario,
                "evidenceCount": evidenceCount,
                "status": status,
                "values": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct ComparisonResultCompletenessMatrix: Hashable, Sendable, CustomReflectable {
    public let cells: [ComparisonResultCompletenessCell]

    fileprivate init(cells: [ComparisonResultCompletenessCell]) {
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

public struct ComparisonResultCoverageReport: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let scopeStatement =
        "Deterministic validation of bounded, caller-supplied, build- and generation-bound comparison-result measurements; not independent comparison-engine, UI, AppKit, AX, assistive-technology, or production-runtime verification."

    public let formatVersion: Int
    public let inventory: ComparisonResultRevisionReference
    public let evidence: ComparisonResultRevisionReference
    public let trustedAuditTimeUnixMilliseconds: UInt64
    public let auditPolicySHA256: [UInt8]
    public let matrix: ComparisonResultCompletenessMatrix
    public let findings: [ComparisonResultFinding]

    public var highestSeverity: ComparisonResultFindingSeverity? { findings.first?.severity }
    public var containsErrors: Bool { findings.contains { $0.severity == .error } }
    public var isCompleteAndValid: Bool { matrix.isComplete && findings.isEmpty }

    fileprivate init(
        formatVersion: Int,
        inventory: ComparisonResultRevisionReference,
        evidence: ComparisonResultRevisionReference,
        trustedAuditTimeUnixMilliseconds: UInt64,
        auditPolicySHA256: [UInt8],
        matrix: ComparisonResultCompletenessMatrix,
        findings: [ComparisonResultFinding]
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
        "ComparisonResultCoverageReport(required: \(matrix.requiredCount), complete: \(matrix.completeCount), findings: \(findings.count), contents: <redacted>)"
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

/// Deterministic content receipt. Digests cover canonical inventory, evidence, and report bytes.
public struct ComparisonResultCoverageReceipt: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let formatVersion: Int
    public let build: ComparisonResultRevisionReference
    public let inventory: ComparisonResultRevisionReference
    public let evidence: ComparisonResultRevisionReference
    public let inventorySHA256: [UInt8]
    public let evidenceSHA256: [UInt8]
    public let auditPolicySHA256: [UInt8]
    public let reportSHA256: [UInt8]
    public let requiredScenarioCount: Int
    public let completeScenarioCount: Int
    public let measuredProductionEvidenceCount: Int
    public let callerAssertionCount: Int
    public let findingCount: Int
    public let workUnits: Int

    fileprivate init(
        formatVersion: Int,
        build: ComparisonResultRevisionReference,
        inventory: ComparisonResultRevisionReference,
        evidence: ComparisonResultRevisionReference,
        inventorySHA256: [UInt8],
        evidenceSHA256: [UInt8],
        auditPolicySHA256: [UInt8],
        reportSHA256: [UInt8],
        requiredScenarioCount: Int,
        completeScenarioCount: Int,
        measuredProductionEvidenceCount: Int,
        callerAssertionCount: Int,
        findingCount: Int,
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
        self.requiredScenarioCount = requiredScenarioCount
        self.completeScenarioCount = completeScenarioCount
        self.measuredProductionEvidenceCount = measuredProductionEvidenceCount
        self.callerAssertionCount = callerAssertionCount
        self.findingCount = findingCount
        self.workUnits = workUnits
    }

    public var recordsCompleteProductionCoverage: Bool {
        completeScenarioCount == requiredScenarioCount && findingCount == 0
    }

    public func validateCurrent(
        inventory currentInventory: ComparisonResultCoverageInventory,
        evidence currentEvidence: ComparisonResultEvidenceBundle,
        verifier: ComparisonResultCoverageVerifier,
        auditPolicy: ComparisonResultAuditPolicy,
        limits: ComparisonResultCoverageLimits = .default,
        captureResolver: @escaping ComparisonResultCoverageMatrix.CaptureResolver,
        cancellationCheck: @escaping ComparisonResultCoverageMatrix.CancellationCheck = {
            Task.isCancelled
        }
    ) throws {
        try ComparisonResultCoverageMatrix.validate(
            receipt: self,
            inventory: currentInventory,
            evidence: currentEvidence,
            verifier: verifier,
            auditPolicy: auditPolicy,
            limits: limits,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck
        )
    }

    public var description: String {
        "ComparisonResultCoverageReceipt(required: \(requiredScenarioCount), complete: \(completeScenarioCount), measured: \(measuredProductionEvidenceCount), assertions: \(callerAssertionCount), findings: \(findingCount), digests: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "requiredScenarioCount": requiredScenarioCount,
                "completeScenarioCount": completeScenarioCount,
                "measuredProductionEvidenceCount": measuredProductionEvidenceCount,
                "callerAssertionCount": callerAssertionCount,
                "findingCount": findingCount,
                "workUnits": workUnits,
                "digests": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct ComparisonResultCoverageResult: Hashable, Sendable, CustomReflectable {
    public let report: ComparisonResultCoverageReport
    public let receipt: ComparisonResultCoverageReceipt

    fileprivate init(
        report: ComparisonResultCoverageReport,
        receipt: ComparisonResultCoverageReceipt
    ) {
        self.report = report
        self.receipt = receipt
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["result": "<redacted>"], displayStyle: .struct)
    }
}

/// Bounded, UI-independent audit for canonical comparison-result scenarios.
public enum ComparisonResultCoverageMatrix: Sendable {
    public typealias CancellationCheck = @Sendable () -> Bool
    /// Resolver must stop before returning more than `maximumByteCount` bytes and throw
    /// `ComparisonResultCaptureResolutionError.exceedsMaximumByteCount` on overflow.
    public typealias CaptureResolver =
        @Sendable (
            _ captureSHA256: [UInt8],
            _ maximumByteCount: Int,
            _ cancellationCheck: CancellationCheck
        ) throws -> Data
    public static let reportFormatVersion = 3
    public static let canonicalMatrixRevision = 3
    public static let canonicalScenarios = ComparisonResultScenario.allCases

    /// Canonical measured payload whose SHA-256 is placed in capture provenance.
    public static func canonicalCaptureData(
        for observation: ComparisonResultEvidence,
        maximumBytes: Int = ComparisonResultCoverageLimits.default.maximumCanonicalBytes
    ) throws -> Data {
        guard (1...ComparisonResultCoverageLimits.hardMaximumCanonicalBytes).contains(maximumBytes)
        else { throw ComparisonResultCoverageError.invalidLimit(.canonicalBytes) }
        return try comparisonResultCanonicalCaptureData(
            observation,
            maximumBytes: maximumBytes
        )
    }

    /// Canonical collector-signed envelope. Signature field itself is excluded.
    public static func canonicalCaptureEnvelopeData(
        for observation: ComparisonResultEvidence,
        maximumBytes: Int = ComparisonResultCoverageLimits.default.maximumCanonicalBytes
    ) throws -> Data {
        guard (1...ComparisonResultCoverageLimits.hardMaximumCanonicalBytes).contains(maximumBytes)
        else { throw ComparisonResultCoverageError.invalidLimit(.canonicalBytes) }
        return try comparisonResultCanonicalCaptureEnvelopeData(
            observation,
            maximumBytes: maximumBytes
        )
    }

    public static func audit(
        inventory: ComparisonResultCoverageInventory,
        evidence: ComparisonResultEvidenceBundle,
        verifier: ComparisonResultCoverageVerifier,
        auditPolicy: ComparisonResultAuditPolicy,
        limits: ComparisonResultCoverageLimits = .default,
        captureResolver: @escaping CaptureResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> ComparisonResultCoverageResult {
        var context = try ComparisonResultAuditContext(
            inventory: inventory,
            evidence: evidence,
            verifier: verifier,
            auditPolicy: auditPolicy,
            limits: limits,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck
        )
        let result = try context.run()
        try context.claimReplays(for: result)
        return result
    }

    /// Compare-and-swap validation rejects changed owners, generations, contents, or results.
    public static func validate(
        receipt: ComparisonResultCoverageReceipt,
        inventory: ComparisonResultCoverageInventory,
        evidence: ComparisonResultEvidenceBundle,
        verifier: ComparisonResultCoverageVerifier,
        auditPolicy: ComparisonResultAuditPolicy,
        limits: ComparisonResultCoverageLimits = .default,
        captureResolver: @escaping CaptureResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws {
        guard inventory.build == receipt.build else {
            throw ComparisonResultCoverageError.staleBuild
        }
        guard inventory.reference == receipt.inventory else {
            throw ComparisonResultCoverageError.staleInventory
        }
        guard evidence.reference == receipt.evidence else {
            throw ComparisonResultCoverageError.staleEvidence
        }
        try ComparisonResultValidation.validate(limits)
        try ComparisonResultValidation.preflight(
            receipt: receipt,
            limits: limits
        )
        var context = try ComparisonResultAuditContext(
            inventory: inventory,
            evidence: evidence,
            verifier: verifier,
            auditPolicy: auditPolicy,
            limits: limits,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck
        )
        let current = try context.run(matching: receipt)
        guard current.receipt == receipt else {
            throw ComparisonResultCoverageError.receiptMismatch
        }
    }
}

private struct ComparisonResultObservationAssessment {
    var assertionOnly = false
    var invalid = false
    var mismatched = false

    var isValidMeasuredProductionEvidence: Bool {
        !assertionOnly && !invalid && !mismatched
    }
}

private struct ComparisonResultAuditContext {
    let inventory: ComparisonResultCoverageInventory
    let evidence: ComparisonResultEvidenceBundle
    let verifier: ComparisonResultCoverageVerifier
    let auditPolicy: ComparisonResultAuditPolicy
    let limits: ComparisonResultCoverageLimits
    let captureResolver: ComparisonResultCoverageMatrix.CaptureResolver
    var work: ComparisonResultWorkBudget
    private var findings: [ComparisonResultFinding] = []
    private var findingIDs: Set<ComparisonResultFinding.ID> = []
    private var trustedCollectors: [ComparisonResultRevisionReference: ComparisonResultTrustedCollector] =
        [:]
    private var replayClaims: [ComparisonResultReplayClaim] = []

    init(
        inventory: ComparisonResultCoverageInventory,
        evidence: ComparisonResultEvidenceBundle,
        verifier: ComparisonResultCoverageVerifier,
        auditPolicy: ComparisonResultAuditPolicy,
        limits: ComparisonResultCoverageLimits,
        captureResolver: @escaping ComparisonResultCoverageMatrix.CaptureResolver,
        cancellationCheck: @escaping ComparisonResultCoverageMatrix.CancellationCheck
    ) throws {
        try ComparisonResultValidation.validate(limits)
        self.inventory = inventory
        self.evidence = evidence
        self.verifier = verifier
        self.auditPolicy = auditPolicy
        self.limits = limits
        self.captureResolver = captureResolver
        work = ComparisonResultWorkBudget(
            maximum: limits.maximumWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try work.checkCancellation()
    }

    mutating func run(
        matching expectedReceipt: ComparisonResultCoverageReceipt? = nil
    ) throws -> ComparisonResultCoverageResult {
        try ComparisonResultValidation.preflight(
            inventory: inventory,
            evidence: evidence,
            verifier: verifier,
            auditPolicy: auditPolicy,
            limits: limits,
            work: &work
        )
        guard evidence.build == inventory.build else {
            throw ComparisonResultCoverageError.staleBuild
        }
        guard evidence.inventory == inventory.reference else {
            throw ComparisonResultCoverageError.staleInventory
        }
        trustedCollectors.reserveCapacity(verifier.collectors.count)
        for collector in verifier.collectors {
            try work.charge(collector.reference.id.rawValue.utf8.count + 1)
            trustedCollectors[collector.reference] = collector
        }
        let auditPolicyData = try comparisonResultCanonicalAuditPolicyData(
            auditPolicy,
            verifier: verifier,
            maximumBytes: limits.maximumCanonicalBytes
        )
        try work.charge(auditPolicyData.count)
        let auditPolicyDigest = try hash(auditPolicyData)
        let inventoryData = try comparisonResultCanonicalInventoryData(
            inventory,
            maximumBytes: limits.maximumCanonicalBytes,
            work: &work
        )
        let evidenceData = try comparisonResultCanonicalEvidenceData(
            evidence,
            maximumBytes: limits.maximumCanonicalBytes,
            work: &work
        )
        let inventoryDigest = try hash(inventoryData)
        let evidenceDigest = try hash(evidenceData)
        if let expectedReceipt {
            guard expectedReceipt.inventorySHA256 == inventoryDigest,
                expectedReceipt.evidenceSHA256 == evidenceDigest,
                expectedReceipt.auditPolicySHA256 == auditPolicyDigest
            else {
                throw ComparisonResultCoverageError.receiptMismatch
            }
        }

        let requirements = Dictionary(uniqueKeysWithValues: inventory.requirements.map { ($0.id, $0) })
        var observationsByScenario: [ComparisonResultScenarioID: [ComparisonResultEvidence]] = [:]
        observationsByScenario.reserveCapacity(evidence.observations.count)
        var assertionCount = 0
        for observation in evidence.observations {
            try work.charge()
            observationsByScenario[observation.scenarioID, default: []].append(observation)
            if !observation.origin.isMeasuredProductionEvidence {
                assertionCount += 1
            }
        }

        for scenarioID in observationsByScenario.keys.sorted() where requirements[scenarioID] == nil {
            try add(.error, .unexpectedScenarioEvidence, subject: .scenario(scenarioID))
        }

        var cells: [ComparisonResultCompletenessCell] = []
        var validMeasuredFingerprints: Set<[UInt8]> = []
        cells.reserveCapacity(ComparisonResultCoverageMatrix.canonicalScenarios.count)
        for scenario in ComparisonResultCoverageMatrix.canonicalScenarios {
            try work.charge()
            let requirement = requirements[scenario.id]!
            let unsortedCandidates = observationsByScenario[scenario.id] ?? []
            let candidates = try canonicalObservations(unsortedCandidates)
            guard !candidates.isEmpty else {
                try add(.error, .missingScenarioEvidence, subject: .scenario(scenario.id))
                cells.append(
                    ComparisonResultCompletenessCell(
                        scenario: scenario,
                        expected: requirement.expected,
                        observed: nil,
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

            var combined = ComparisonResultObservationAssessment()
            var soleValidMeasuredFingerprint: [UInt8]?
            for (index, observation) in candidates.enumerated() {
                let assessment = try assess(
                    observation,
                    requirement: requirement,
                    inventorySHA256: inventoryDigest,
                    discriminator: index,
                    resolvesCapture: candidates.count == 1
                )
                combined.assertionOnly = combined.assertionOnly || assessment.assertionOnly
                combined.invalid = combined.invalid || assessment.invalid
                combined.mismatched = combined.mismatched || assessment.mismatched
                if candidates.count == 1, assessment.isValidMeasuredProductionEvidence {
                    let canonical = try comparisonResultCanonicalObservationData(
                        observation,
                        maximumBytes: limits.maximumCanonicalBytes
                    )
                    try work.charge(canonical.count)
                    soleValidMeasuredFingerprint = try hash(canonical)
                }
            }
            if let soleValidMeasuredFingerprint {
                validMeasuredFingerprints.insert(soleValidMeasuredFingerprint)
            }

            let selected = candidates[0]
            let status: ComparisonResultCompletenessStatus
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
                ComparisonResultCompletenessCell(
                    scenario: scenario,
                    expected: requirement.expected,
                    observed: selected.observed,
                    evidenceCount: candidates.count,
                    status: status
                )
            )
        }

        let sortedFindings = try comparisonResultStableMergeSort(
            findings,
            precedes: { left, right, _ in comparisonResultFindingPrecedes(left, right) },
            work: &work
        )
        let report = ComparisonResultCoverageReport(
            formatVersion: ComparisonResultCoverageMatrix.reportFormatVersion,
            inventory: inventory.reference,
            evidence: evidence.reference,
            trustedAuditTimeUnixMilliseconds: auditPolicy.trustedAuditTimeUnixMilliseconds,
            auditPolicySHA256: auditPolicyDigest,
            matrix: ComparisonResultCompletenessMatrix(cells: cells),
            findings: sortedFindings
        )

        let reportData = try comparisonResultCanonicalReportData(
            report,
            maximumBytes: limits.maximumCanonicalBytes,
            work: &work
        )
        try work.checkCancellation()

        let reportDigest = try hash(reportData)
        let deterministicWorkUnits = try comparisonResultDeterministicWorkUnits(
            inventoryByteCount: inventoryData.count,
            evidenceByteCount: evidenceData.count,
            auditPolicyByteCount: auditPolicyData.count,
            reportByteCount: reportData.count,
            observationCount: evidence.observations.count,
            findingCount: report.findings.count,
            maximum: limits.maximumWorkUnits
        )
        let receipt = ComparisonResultCoverageReceipt(
            formatVersion: ComparisonResultCoverageMatrix.reportFormatVersion,
            build: inventory.build,
            inventory: inventory.reference,
            evidence: evidence.reference,
            inventorySHA256: inventoryDigest,
            evidenceSHA256: evidenceDigest,
            auditPolicySHA256: auditPolicyDigest,
            reportSHA256: reportDigest,
            requiredScenarioCount: report.matrix.requiredCount,
            completeScenarioCount: report.matrix.completeCount,
            measuredProductionEvidenceCount: validMeasuredFingerprints.count,
            callerAssertionCount: assertionCount,
            findingCount: report.findings.count,
            workUnits: deterministicWorkUnits
        )
        try work.checkCancellation()
        return ComparisonResultCoverageResult(report: report, receipt: receipt)
    }

    mutating func claimReplays(for result: ComparisonResultCoverageResult) throws {
        guard result.report.isCompleteAndValid else { return }
        guard !replayClaims.isEmpty else { return }
        try work.checkCancellation()
        guard Set(replayClaims).count == replayClaims.count else {
            throw ComparisonResultCoverageError.replayClaimRejected
        }
        guard auditPolicy.claim(replayClaims) else {
            throw ComparisonResultCoverageError.replayClaimRejected
        }
        replayClaims.removeAll(keepingCapacity: false)
    }

    private mutating func assess(
        _ observation: ComparisonResultEvidence,
        requirement: ComparisonResultCoverageRequirement,
        inventorySHA256: [UInt8],
        discriminator: Int,
        resolvesCapture: Bool
    ) throws -> ComparisonResultObservationAssessment {
        try work.charge()
        var result = ComparisonResultObservationAssessment()
        let scenario = requirement.scenario
        let subject = ComparisonResultFindingSubject.scenario(scenario.id)
        let expectedBinding = requirement.binding
        let observedBinding = observation.binding

        let lifecycleIsTrusted =
            try verifier.verifies(observation.lifecycle)
            && verifier.verifies(requirement.lifecycle)
        if !lifecycleIsTrusted {
            result.invalid = true
            try add(
                .error,
                .lifecycleAuthenticationInvalid,
                subject: subject,
                discriminator: discriminator
            )
        }

        if observedBinding.comparisonIdentity != expectedBinding.comparisonIdentity {
            result.mismatched = true
            try add(.error, .comparisonIdentityMismatch, subject: subject, discriminator: discriminator)
        }
        if observedBinding.inputIdentity != expectedBinding.inputIdentity {
            result.mismatched = true
            try add(.error, .inputIdentityMismatch, subject: subject, discriminator: discriminator)
        }
        if observedBinding.resultIdentity != expectedBinding.resultIdentity {
            result.mismatched = true
            try add(.error, .resultIdentityMismatch, subject: subject, discriminator: discriminator)
        }
        if observedBinding.operationID != expectedBinding.operationID {
            result.mismatched = true
            try add(.error, .operationIdentityMismatch, subject: subject, discriminator: discriminator)
        }
        if observedBinding.sources.map(\.identity) != expectedBinding.sources.map(\.identity)
            || observedBinding.sources.map(\.side) != expectedBinding.sources.map(\.side)
        {
            result.mismatched = true
            try add(.error, .sourceIdentityMismatch, subject: subject, discriminator: discriminator)
        }
        if comparisonResultGenerations(in: observedBinding)
            != comparisonResultGenerations(in: expectedBinding)
        {
            result.mismatched = true
            try add(.error, .generationMismatch, subject: subject, discriminator: discriminator)
        }

        let differencesMatch = try differencesEqual(
            observation.observed.differences,
            requirement.expected.differences
        )
        if observation.observed.outcome != requirement.expected.outcome
            || !differencesMatch
        {
            result.mismatched = true
            try add(.error, .resultStateMismatch, subject: subject, discriminator: discriminator)
        }
        if observation.observed.selection != requirement.expected.selection {
            result.mismatched = true
            try add(.error, .selectionStateMismatch, subject: subject, discriminator: discriminator)
        }
        if observation.observed.cursor != requirement.expected.cursor {
            result.mismatched = true
            try add(.error, .cursorStateMismatch, subject: subject, discriminator: discriminator)
        }
        if observation.observed.viewport != requirement.expected.viewport {
            result.mismatched = true
            try add(.error, .viewportStateMismatch, subject: subject, discriminator: discriminator)
        }
        if observation.observed.selectionVisibility != requirement.expected.selectionVisibility {
            result.mismatched = true
            try add(
                .error,
                .selectionVisibilityMismatch,
                subject: subject,
                discriminator: discriminator
            )
        }
        if observation.observed.commandState != requirement.expected.commandState {
            result.mismatched = true
            try add(.error, .commandStateMismatch, subject: subject, discriminator: discriminator)
        }

        if observation.origin == .callerAssertion {
            result.assertionOnly = true
            try add(.error, .assertionOnlyEvidence, subject: subject, discriminator: discriminator)
            return result
        }

        result = try assessAccessibility(
            observation,
            requirement: requirement,
            subject: subject,
            discriminator: discriminator,
            result: result
        )

        if let provenance = observation.provenance {
            var provenanceIsTrusted = lifecycleIsTrusted && !result.invalid && !result.mismatched
            if provenance.build != inventory.build {
                result.invalid = true
                provenanceIsTrusted = false
                try add(.error, .provenanceBuildMismatch, subject: subject, discriminator: discriminator)
            }
            if provenance.inventory != inventory.reference
                || provenance.inventorySHA256 != inventorySHA256
            {
                result.invalid = true
                provenanceIsTrusted = false
                try add(
                    .error,
                    .provenanceInventoryMismatch,
                    subject: subject,
                    discriminator: discriminator
                )
            }
            if !ComparisonResultValidation.isValid(provenance) {
                result.invalid = true
                provenanceIsTrusted = false
                try add(
                    .error,
                    .productionProvenanceInvalid,
                    subject: subject,
                    discriminator: discriminator
                )
            }
            if provenance.artifactSHA256 != inventory.buildArtifactSHA256 {
                result.invalid = true
                provenanceIsTrusted = false
                try add(
                    .error,
                    .provenanceArtifactMismatch,
                    subject: subject,
                    discriminator: discriminator
                )
            }
            if !comparisonResultCaptureTimeIsValid(
                provenance.capturedAtUnixMilliseconds,
                policy: auditPolicy
            ) {
                result.invalid = true
                provenanceIsTrusted = false
                try add(
                    .error,
                    .productionProvenanceInvalid,
                    subject: subject,
                    discriminator: discriminator
                )
            }
            try work.charge(provenance.collector.id.rawValue.utf8.count + 1)
            guard let trustedCollector = trustedCollectors[provenance.collector] else {
                result.invalid = true
                provenanceIsTrusted = false
                try add(.error, .untrustedCollector, subject: subject, discriminator: discriminator)
                return result
            }
            if provenanceIsTrusted {
                let envelope = try comparisonResultCanonicalCaptureEnvelopeData(
                    observation,
                    maximumBytes: limits.maximumCanonicalBytes
                )
                try work.charge(envelope.count)
                guard
                    trustedCollector.verifies(
                        signature: provenance.collectorSignature,
                        data: envelope
                    )
                else {
                    result.invalid = true
                    provenanceIsTrusted = false
                    try add(
                        .error,
                        .productionProvenanceInvalid,
                        subject: subject,
                        discriminator: discriminator
                    )
                    return result
                }
            }
            if provenanceIsTrusted, resolvesCapture {
                try validateCapture(
                    observation,
                    provenance: provenance,
                    subject: subject,
                    discriminator: discriminator,
                    result: &result
                )
                if !result.invalid, !result.mismatched {
                    replayClaims.append(ComparisonResultReplayClaim(nonce: provenance.runNonce))
                }
            }
        } else {
            result.invalid = true
            try add(
                .error,
                .productionProvenanceMissing,
                subject: subject,
                discriminator: discriminator
            )
        }

        return result
    }

    private mutating func assessAccessibility(
        _ observation: ComparisonResultEvidence,
        requirement: ComparisonResultCoverageRequirement,
        subject: ComparisonResultFindingSubject,
        discriminator: Int,
        result originalResult: ComparisonResultObservationAssessment
    ) throws -> ComparisonResultObservationAssessment {
        var result = originalResult
        if let accessibilityRequirement = requirement.accessibility {
            guard let accessibility = observation.accessibility else {
                result.invalid = true
                try add(
                    .error,
                    .accessibilityEvidenceMissing,
                    subject: subject,
                    discriminator: discriminator
                )
                return result
            }
            let requiredToken = accessibilityRequirement.token
            if accessibility.receiptFormatVersion != requiredToken.receiptFormatVersion
                || accessibility.app != requiredToken.app
                || accessibility.build != requiredToken.build
                || accessibility.buildArtifactSHA256 != requiredToken.buildArtifactSHA256
                || accessibility.buildSigningIdentitySHA256
                    != requiredToken.buildSigningIdentitySHA256
                || accessibility.inventory != requiredToken.inventory
                || accessibility.evidence != requiredToken.evidence
                || accessibility.scenario != requiredToken.scenario
                || accessibility.snapshotID != requiredToken.snapshotID
                || accessibility.inventorySHA256 != requiredToken.inventorySHA256
                || accessibility.requiredEvidenceCount != requiredToken.requiredEvidenceCount
            {
                result.mismatched = true
                try add(
                    .error,
                    .accessibilityEvidenceMismatch,
                    subject: subject,
                    discriminator: discriminator
                )
            }
            if !ComparisonResultValidation.isValid(accessibility)
                || !verifier.verifies(requiredToken)
                || !verifier.verifies(accessibility)
            {
                result.invalid = true
                try add(
                    .error,
                    .accessibilityAuthenticationInvalid,
                    subject: subject,
                    discriminator: discriminator
                )
            }
        } else if observation.accessibility != nil {
            result.mismatched = true
            try add(
                .error,
                .accessibilityEvidenceMismatch,
                subject: subject,
                discriminator: discriminator
            )
        }
        return result
    }

    private mutating func canonicalObservations(
        _ observations: [ComparisonResultEvidence]
    ) throws -> [ComparisonResultEvidence] {
        var records: [(data: Data, observation: ComparisonResultEvidence)] = []
        records.reserveCapacity(observations.count)
        for observation in observations {
            let data = try comparisonResultCanonicalObservationData(
                observation,
                maximumBytes: limits.maximumCanonicalBytes
            )
            try work.charge(data.count)
            records.append((data, observation))
        }
        let sorted = try comparisonResultStableMergeSort(
            records,
            precedes: { left, right, work in
                try comparisonResultDataPrecedes(left.data, right.data, work: &work)
            },
            work: &work
        )
        return sorted.map(\.observation)
    }

    private mutating func validateCapture(
        _ observation: ComparisonResultEvidence,
        provenance: ComparisonResultEvidenceProvenance,
        subject: ComparisonResultFindingSubject,
        discriminator: Int,
        result: inout ComparisonResultObservationAssessment
    ) throws {
        let expectedCapture = try comparisonResultCanonicalCaptureData(
            observation,
            maximumBytes: limits.maximumCanonicalBytes
        )
        try work.charge(expectedCapture.count)
        guard try hash(expectedCapture) == provenance.captureSHA256 else {
            result.invalid = true
            try add(.error, .productionCaptureMismatch, subject: subject, discriminator: discriminator)
            return
        }
        let capture: Data
        do {
            try work.checkCancellation()
            capture = try captureResolver(
                provenance.captureSHA256,
                expectedCapture.count,
                work.cancellationCheck
            )
            try work.checkCancellation()
        } catch ComparisonResultCoverageError.cancelled {
            throw ComparisonResultCoverageError.cancelled
        } catch is CancellationError {
            throw ComparisonResultCoverageError.cancelled
        } catch ComparisonResultCaptureResolutionError.resourceUnavailable {
            throw ComparisonResultCaptureResolutionError.resourceUnavailable
        } catch let error as ComparisonResultCaptureResourceError {
            throw error
        } catch {
            result.invalid = true
            try add(.error, .productionCaptureMismatch, subject: subject, discriminator: discriminator)
            return
        }
        guard capture.count <= expectedCapture.count else {
            result.invalid = true
            try add(.error, .productionCaptureMismatch, subject: subject, discriminator: discriminator)
            return
        }
        try work.charge(capture.count)
        guard capture == expectedCapture, try hash(capture) == provenance.captureSHA256 else {
            result.invalid = true
            try add(.error, .productionCaptureMismatch, subject: subject, discriminator: discriminator)
            return
        }
    }

    private mutating func differencesEqual(
        _ left: [ComparisonResultDifference],
        _ right: [ComparisonResultDifference]
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for index in left.indices {
            try work.charge()
            guard left[index] == right[index] else { return false }
        }
        return true
    }

    private mutating func hash(_ data: Data) throws -> [UInt8] {
        try work.charge(data.count)
        try work.checkCancellation()
        return Array(SHA256.hash(data: data))
    }

    private mutating func add(
        _ severity: ComparisonResultFindingSeverity,
        _ code: ComparisonResultFindingCode,
        subject: ComparisonResultFindingSubject,
        discriminator: Int = 0
    ) throws {
        try work.charge()
        let finding = ComparisonResultFinding(
            severity: severity,
            code: code,
            subject: subject,
            discriminator: discriminator
        )
        guard findingIDs.insert(finding.id).inserted else { return }
        guard findings.count < limits.maximumFindings else {
            throw ComparisonResultCoverageError.findingLimitExceeded(maximum: limits.maximumFindings)
        }
        findings.append(finding)
    }
}

private enum ComparisonResultValidation {
    static func validate(_ limits: ComparisonResultCoverageLimits) throws {
        try require(
            limits.maximumTrustedCollectors,
            atMost: ComparisonResultCoverageLimits.hardMaximumTrustedCollectors,
            limit: .trustedCollectors
        )
        try require(
            limits.maximumObservations,
            atMost: ComparisonResultCoverageLimits.hardMaximumObservations,
            limit: .observations
        )
        try require(
            limits.maximumDifferencesPerScenario,
            atMost: ComparisonResultCoverageLimits.hardMaximumDifferencesPerScenario,
            limit: .differencesPerScenario
        )
        try require(
            limits.maximumTotalDifferences,
            atMost: ComparisonResultCoverageLimits.hardMaximumTotalDifferences,
            limit: .totalDifferences
        )
        try require(
            limits.maximumRows,
            atMost: ComparisonResultCoverageLimits.hardMaximumRows,
            limit: .rows
        )
        try require(
            limits.maximumStringUTF8Bytes,
            atMost: ComparisonResultCoverageLimits.hardMaximumStringUTF8Bytes,
            limit: .stringUTF8Bytes
        )
        try require(
            limits.maximumTotalStringUTF8Bytes,
            atMost: ComparisonResultCoverageLimits.hardMaximumTotalStringUTF8Bytes,
            limit: .totalStringUTF8Bytes
        )
        try require(
            limits.maximumBinaryMetadataBytes,
            atMost: ComparisonResultCoverageLimits.hardMaximumBinaryMetadataBytes,
            limit: .binaryMetadataBytes
        )
        try require(
            limits.maximumWorkUnits,
            atMost: ComparisonResultCoverageLimits.hardMaximumWorkUnits,
            limit: .workUnits
        )
        try require(
            limits.maximumFindings,
            atMost: ComparisonResultCoverageLimits.hardMaximumFindings,
            limit: .findings
        )
        try require(
            limits.maximumCanonicalBytes,
            atMost: ComparisonResultCoverageLimits.hardMaximumCanonicalBytes,
            limit: .canonicalBytes
        )
        try require(
            limits.cancellationCheckInterval,
            atMost: ComparisonResultCoverageLimits.hardMaximumCancellationCheckInterval,
            limit: .cancellationCheckInterval
        )
    }

    static func preflight(
        receipt: ComparisonResultCoverageReceipt,
        limits: ComparisonResultCoverageLimits
    ) throws {
        guard receipt.formatVersion == ComparisonResultCoverageMatrix.reportFormatVersion,
            receipt.requiredScenarioCount == ComparisonResultCoverageMatrix.canonicalScenarios.count,
            receipt.completeScenarioCount >= 0,
            receipt.completeScenarioCount <= receipt.requiredScenarioCount,
            receipt.measuredProductionEvidenceCount >= 0,
            receipt.measuredProductionEvidenceCount <= limits.maximumObservations,
            receipt.callerAssertionCount >= 0,
            receipt.callerAssertionCount <= limits.maximumObservations,
            receipt.findingCount >= 0,
            receipt.findingCount <= limits.maximumFindings,
            receipt.workUnits >= 0,
            receipt.workUnits <= limits.maximumWorkUnits,
            comparisonResultIsValidDigest(receipt.inventorySHA256),
            comparisonResultIsValidDigest(receipt.evidenceSHA256),
            comparisonResultIsValidDigest(receipt.auditPolicySHA256),
            comparisonResultIsValidDigest(receipt.reportSHA256)
        else {
            throw ComparisonResultCoverageError.invalidEvidence(.receipt)
        }
    }

    static func preflight(
        inventory: ComparisonResultCoverageInventory,
        evidence: ComparisonResultEvidenceBundle,
        verifier: ComparisonResultCoverageVerifier,
        auditPolicy: ComparisonResultAuditPolicy,
        limits: ComparisonResultCoverageLimits,
        work: inout ComparisonResultWorkBudget
    ) throws {
        guard evidence.observations.count <= limits.maximumObservations else {
            throw ComparisonResultCoverageError.countLimitExceeded(
                .observations,
                maximum: limits.maximumObservations
            )
        }
        guard inventory.requirements.count == ComparisonResultCoverageMatrix.canonicalScenarios.count else {
            throw ComparisonResultCoverageError.invalidInventory(.inventoryRequirements)
        }
        guard verifier.collectors.count <= limits.maximumTrustedCollectors else {
            throw ComparisonResultCoverageError.countLimitExceeded(
                .trustedCollectors,
                maximum: limits.maximumTrustedCollectors
            )
        }
        let minimumTraversalWork =
            inventory.requirements.count + evidence.observations.count + verifier.collectors.count
        guard minimumTraversalWork <= limits.maximumWorkUnits else {
            throw ComparisonResultCoverageError.workLimitExceeded(maximum: limits.maximumWorkUnits)
        }
        guard comparisonResultIsValidDigest(inventory.buildArtifactSHA256),
            auditPolicy.trustedAuditTimeUnixMilliseconds > 0,
            auditPolicy.maximumCaptureAgeMilliseconds > 0,
            comparisonResultIsValidIdentifier(auditPolicy.replayPolicy.id.rawValue),
            auditPolicy.replayPolicy.id.rawValue.utf8.count <= limits.maximumStringUTF8Bytes
        else {
            throw ComparisonResultCoverageError.invalidInventory(.auditPolicy)
        }
        try validateBinaryMetadata(inventory.buildArtifactSHA256.count, limits: limits)

        var preflightTotalDifferences = 0
        for requirement in inventory.requirements {
            try addDifferences(
                requirement.expected.differences.count,
                total: &preflightTotalDifferences,
                limits: limits
            )
        }
        for observation in evidence.observations {
            try addDifferences(
                observation.observed.differences.count,
                total: &preflightTotalDifferences,
                limits: limits
            )
        }

        var strings = ComparisonResultStringBudget(limits: limits)
        try validate(
            inventory.reference,
            field: .inventoryReference,
            strings: &strings,
            work: &work,
            inventory: true
        )
        try validate(
            inventory.build,
            field: .inventoryBuild,
            strings: &strings,
            work: &work,
            inventory: true
        )
        try validate(
            evidence.reference,
            field: .evidenceReference,
            strings: &strings,
            work: &work,
            inventory: false
        )
        try validate(
            evidence.inventory,
            field: .evidenceInventory,
            strings: &strings,
            work: &work,
            inventory: false
        )
        try validate(
            evidence.build,
            field: .evidenceBuild,
            strings: &strings,
            work: &work,
            inventory: false
        )
        try validate(
            auditPolicy.replayPolicy,
            field: .auditPolicy,
            strings: &strings,
            work: &work,
            inventory: true
        )
        for collector in verifier.collectors {
            try work.charge()
            guard collector.reference.id.rawValue.utf8.count <= limits.maximumStringUTF8Bytes,
                comparisonResultIsValidIdentifier(collector.reference.id.rawValue),
                collector.ed25519PublicKey.count == 32
            else {
                throw ComparisonResultCoverageError.invalidInventory(.auditPolicy)
            }
            try validate(
                collector.reference,
                field: .provenance,
                strings: &strings,
                work: &work,
                inventory: false
            )
            try validateBinaryMetadata(collector.ed25519PublicKey.count, limits: limits)
        }
        var verifierBinaryCount = 0
        try addMetadata(
            verifier.authorityPublicKey.count,
            to: &verifierBinaryCount,
            limits: limits
        )
        try addMetadata(verifier.authorityID.count, to: &verifierBinaryCount, limits: limits)

        var requirementScenarios: Set<ComparisonResultScenario> = []
        for requirement in inventory.requirements {
            try work.charge()
            let accessibilityArtifactMatches =
                requirement.accessibility.map {
                    $0.token.buildArtifactSHA256 == inventory.buildArtifactSHA256
                } ?? true
            guard requirementScenarios.insert(requirement.scenario).inserted,
                accessibilityArtifactMatches,
                comparisonResultBindingIsValid(requirement.binding),
                try verifier.verifies(requirement.lifecycle)
            else {
                throw ComparisonResultCoverageError.invalidInventory(.inventoryRequirements)
            }
            try validate(
                requirement.expected,
                limits: limits,
                strings: &strings,
                work: &work,
                inventory: true
            )
            try work.charge(8 * requirement.expected.differences.count + 1)
            guard comparisonResultState(requirement.expected, matches: requirement.scenario),
                requirement.expected.commandState
                    == comparisonResultExpectedCommandState(for: requirement.expected)
            else {
                throw ComparisonResultCoverageError.invalidInventory(.inventoryRequirements)
            }
            if let accessibility = requirement.accessibility {
                try validate(
                    accessibility,
                    limits: limits,
                    strings: &strings,
                    work: &work,
                    inventory: true
                )
                guard verifier.verifies(accessibility.token) else {
                    throw ComparisonResultCoverageError.invalidInventory(.accessibilityBinding)
                }
            }
        }
        guard requirementScenarios == Set(ComparisonResultCoverageMatrix.canonicalScenarios) else {
            throw ComparisonResultCoverageError.invalidInventory(.inventoryRequirements)
        }

        for observation in evidence.observations {
            try work.charge()
            guard comparisonResultBindingIsValid(observation.binding) else {
                throw ComparisonResultCoverageError.invalidEvidence(.comparisonBinding)
            }
            var lifecycleBinaryCount = 0
            try addMetadata(
                observation.lifecycle.authorityID.count,
                to: &lifecycleBinaryCount,
                limits: limits
            )
            try addMetadata(
                observation.lifecycle.signature.count,
                to: &lifecycleBinaryCount,
                limits: limits
            )
            try validate(
                observation.observed,
                limits: limits,
                strings: &strings,
                work: &work,
                inventory: false
            )
            if let provenance = observation.provenance {
                try validate(
                    provenance.build,
                    field: .provenance,
                    strings: &strings,
                    work: &work,
                    inventory: false
                )
                try validate(
                    provenance.inventory,
                    field: .provenance,
                    strings: &strings,
                    work: &work,
                    inventory: false
                )
                try validate(
                    provenance.collector,
                    field: .provenance,
                    strings: &strings,
                    work: &work,
                    inventory: false
                )
                try strings.consume(provenance.source, field: .provenanceSource, work: &work)
                var binaryCount = 0
                try addMetadata(provenance.runNonce.count, to: &binaryCount, limits: limits)
                try addMetadata(provenance.artifactSHA256.count, to: &binaryCount, limits: limits)
                try addMetadata(provenance.inventorySHA256.count, to: &binaryCount, limits: limits)
                try addMetadata(provenance.captureSHA256.count, to: &binaryCount, limits: limits)
                try addMetadata(provenance.collectorSignature.count, to: &binaryCount, limits: limits)
            }
            if let accessibility = observation.accessibility {
                try validate(
                    accessibility,
                    limits: limits,
                    strings: &strings,
                    work: &work
                )
            }
        }
    }

    static func isValid(_ provenance: ComparisonResultEvidenceProvenance) -> Bool {
        provenance.capturedAtUnixMilliseconds > 0
            && (16...64).contains(provenance.runNonce.count)
            && comparisonResultIsValidDigest(provenance.artifactSHA256)
            && comparisonResultIsValidDigest(provenance.inventorySHA256)
            && comparisonResultIsValidDigest(provenance.captureSHA256)
            && provenance.collectorSignature.count == 64
            && comparisonResultIsValidIdentifier(provenance.build.id.rawValue)
            && comparisonResultIsValidIdentifier(provenance.inventory.id.rawValue)
            && comparisonResultIsValidIdentifier(provenance.collector.id.rawValue)
            && comparisonResultIsValidSource(provenance.source)
    }

    static func isValid(_ token: ComparisonResultAccessibilityEvidenceToken) -> Bool {
        token.receiptFormatVersion == AccessibilityEvidenceWorkflow.reportFormatVersion
            && token.requiredEvidenceCount > 0
            && token.completeEvidenceCount == token.requiredEvidenceCount
            && token.findingCount == 0
            && token.archiveByteCount > 0
            && comparisonResultIsValidDigest(token.inventorySHA256)
            && comparisonResultIsValidDigest(token.evidenceArchiveSHA256)
            && comparisonResultIsValidDigest(token.buildArtifactSHA256)
            && comparisonResultIsValidDigest(token.buildSigningIdentitySHA256)
            && comparisonResultIsValidDigest(token.authorityID)
            && token.signature.count == 64
    }

    private static func require(
        _ value: Int,
        atMost maximum: Int,
        limit: ComparisonResultCoverageLimit
    ) throws {
        guard (1...maximum).contains(value) else {
            throw ComparisonResultCoverageError.invalidLimit(limit)
        }
    }

    private static func addDifferences(
        _ count: Int,
        total: inout Int,
        limits: ComparisonResultCoverageLimits
    ) throws {
        guard count >= 0, count <= limits.maximumDifferencesPerScenario else {
            throw ComparisonResultCoverageError.countLimitExceeded(
                .differencesPerScenario,
                maximum: limits.maximumDifferencesPerScenario
            )
        }
        guard count <= limits.maximumTotalDifferences,
            total <= limits.maximumTotalDifferences - count
        else {
            throw ComparisonResultCoverageError.countLimitExceeded(
                .totalDifferences,
                maximum: limits.maximumTotalDifferences
            )
        }
        total += count
    }

    private static func validate(
        _ state: ComparisonResultSemanticState,
        limits: ComparisonResultCoverageLimits,
        strings: inout ComparisonResultStringBudget,
        work: inout ComparisonResultWorkBudget,
        inventory: Bool
    ) throws {
        guard state.differences.count <= limits.maximumDifferencesPerScenario,
            state.viewport.alignedRowCount >= 0,
            state.viewport.alignedRowCount <= limits.maximumRows,
            state.viewport.visibleRows.lowerBound >= 0,
            state.viewport.visibleRows.lowerBound <= state.viewport.visibleRows.upperBound,
            state.viewport.visibleRows.upperBound <= state.viewport.alignedRowCount
        else {
            throw invalid(field: .semanticState, inventory: inventory)
        }
        try work.charge()
        var identifiers: Set<ComparisonResultStableID> = []
        var previousUpperBound = 0
        for difference in state.differences {
            try work.charge()
            guard difference.ordinal == identifiers.count,
                difference.rowRange.lowerBound >= previousUpperBound,
                difference.rowRange.lowerBound < difference.rowRange.upperBound,
                difference.rowRange.upperBound <= limits.maximumRows,
                difference.rowRange.upperBound <= state.viewport.alignedRowCount,
                comparisonResultIsValidIdentifier(difference.id.rawValue),
                identifiers.insert(difference.id).inserted
            else {
                throw invalid(field: .semanticState, inventory: inventory)
            }
            previousUpperBound = difference.rowRange.upperBound
            try strings.consume(difference.id.rawValue, field: .semanticState, work: &work)
        }
        try work.charge(state.differences.count + 1)
        guard (state.outcome == .identical) == state.differences.isEmpty,
            state.selectionVisibility
                == comparisonResultSelectionVisibility(
                    selection: state.selection,
                    differences: state.differences,
                    viewport: state.viewport
                ),
            state.selection.differenceID.map(identifiers.contains) ?? true
        else {
            throw invalid(field: .semanticState, inventory: inventory)
        }
        if state.selection == .none {
            guard state.selectionVisibility == .notApplicable else {
                throw invalid(field: .semanticState, inventory: inventory)
            }
        } else if state.selectionVisibility == .notApplicable {
            throw invalid(field: .semanticState, inventory: inventory)
        }
        if case .row(let row, let differenceID) = state.cursor {
            try work.charge(state.differences.count)
            guard row >= 0, row < state.viewport.alignedRowCount else {
                throw invalid(field: .semanticState, inventory: inventory)
            }
            if let differenceID {
                guard
                    state.differences.contains(where: {
                        $0.id == differenceID && $0.rowRange.contains(row)
                    })
                else {
                    throw invalid(field: .semanticState, inventory: inventory)
                }
            } else if state.differences.contains(where: { $0.rowRange.contains(row) }) {
                throw invalid(field: .semanticState, inventory: inventory)
            }
        }
    }

    private static func validate(
        _ requirement: ComparisonResultAccessibilityRequirement,
        limits: ComparisonResultCoverageLimits,
        strings: inout ComparisonResultStringBudget,
        work: inout ComparisonResultWorkBudget,
        inventory: Bool
    ) throws {
        let requirement = requirement.token
        try validate(
            requirement.app,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: inventory
        )
        try validate(
            requirement.build,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: inventory
        )
        try validate(
            requirement.inventory,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: inventory
        )
        try validate(
            requirement.evidence,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: inventory
        )
        try validate(
            requirement.scenario,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: inventory
        )
        try strings.consume(
            requirement.snapshotID.rawValue,
            field: .accessibilityBinding,
            work: &work
        )
        guard comparisonResultIsValidIdentifier(requirement.snapshotID.rawValue) else {
            throw invalid(field: .accessibilityBinding, inventory: inventory)
        }
        guard requirement.receiptFormatVersion == AccessibilityEvidenceWorkflow.reportFormatVersion,
            requirement.requiredEvidenceCount > 0,
            comparisonResultIsValidDigest(requirement.buildArtifactSHA256),
            comparisonResultIsValidDigest(requirement.buildSigningIdentitySHA256),
            comparisonResultIsValidDigest(requirement.inventorySHA256),
            comparisonResultIsValidDigest(requirement.authorityID),
            requirement.signature.count == 64
        else {
            throw invalid(field: .accessibilityBinding, inventory: inventory)
        }
        var binaryCount = 0
        try addMetadata(requirement.buildArtifactSHA256.count, to: &binaryCount, limits: limits)
        try addMetadata(
            requirement.buildSigningIdentitySHA256.count,
            to: &binaryCount,
            limits: limits
        )
        try addMetadata(requirement.inventorySHA256.count, to: &binaryCount, limits: limits)
        try addMetadata(requirement.authorityID.count, to: &binaryCount, limits: limits)
        try addMetadata(requirement.signature.count, to: &binaryCount, limits: limits)
    }

    private static func validate(
        _ link: ComparisonResultAccessibilityEvidenceToken,
        limits: ComparisonResultCoverageLimits,
        strings: inout ComparisonResultStringBudget,
        work: inout ComparisonResultWorkBudget
    ) throws {
        try validate(
            link.app,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: false
        )
        try validate(
            link.build,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: false
        )
        try validate(
            link.inventory,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: false
        )
        try validate(
            link.evidence,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: false
        )
        try validate(
            link.scenario,
            field: .accessibilityBinding,
            strings: &strings,
            work: &work,
            inventory: false
        )
        try strings.consume(link.snapshotID.rawValue, field: .accessibilityBinding, work: &work)
        guard link.receiptFormatVersion == AccessibilityEvidenceWorkflow.reportFormatVersion,
            comparisonResultIsValidIdentifier(link.snapshotID.rawValue),
            link.requiredEvidenceCount >= 0,
            link.completeEvidenceCount >= 0,
            link.completeEvidenceCount <= link.requiredEvidenceCount,
            link.findingCount >= 0,
            link.archiveByteCount > 0
        else {
            throw ComparisonResultCoverageError.invalidEvidence(.accessibilityBinding)
        }
        var binaryCount = 0
        try addMetadata(link.buildArtifactSHA256.count, to: &binaryCount, limits: limits)
        try addMetadata(link.buildSigningIdentitySHA256.count, to: &binaryCount, limits: limits)
        try addMetadata(link.inventorySHA256.count, to: &binaryCount, limits: limits)
        try addMetadata(link.evidenceArchiveSHA256.count, to: &binaryCount, limits: limits)
        try addMetadata(link.authorityID.count, to: &binaryCount, limits: limits)
        try addMetadata(link.signature.count, to: &binaryCount, limits: limits)
    }

    private static func validate(
        _ reference: ComparisonResultRevisionReference,
        field: ComparisonResultCoverageField,
        strings: inout ComparisonResultStringBudget,
        work: inout ComparisonResultWorkBudget,
        inventory: Bool
    ) throws {
        try strings.consume(reference.id.rawValue, field: field, work: &work)
        guard comparisonResultIsValidIdentifier(reference.id.rawValue) else {
            throw invalid(field: field, inventory: inventory)
        }
    }

    private static func validate(
        _ reference: AccessibilityEvidenceRevisionReference,
        field: ComparisonResultCoverageField,
        strings: inout ComparisonResultStringBudget,
        work: inout ComparisonResultWorkBudget,
        inventory: Bool
    ) throws {
        try strings.consume(reference.id.rawValue, field: field, work: &work)
        guard comparisonResultIsValidIdentifier(reference.id.rawValue) else {
            throw invalid(field: field, inventory: inventory)
        }
    }

    private static func validateBinaryMetadata(
        _ count: Int,
        limits: ComparisonResultCoverageLimits
    ) throws {
        guard count >= 0, count <= limits.maximumBinaryMetadataBytes else {
            throw ComparisonResultCoverageError.binaryMetadataTooLarge(
                maximumBytes: limits.maximumBinaryMetadataBytes
            )
        }
    }

    private static func addMetadata(
        _ count: Int,
        to total: inout Int,
        limits: ComparisonResultCoverageLimits
    ) throws {
        guard count >= 0, count <= limits.maximumBinaryMetadataBytes,
            total <= limits.maximumBinaryMetadataBytes - count
        else {
            throw ComparisonResultCoverageError.binaryMetadataTooLarge(
                maximumBytes: limits.maximumBinaryMetadataBytes
            )
        }
        total += count
    }

    private static func invalid(
        field: ComparisonResultCoverageField,
        inventory: Bool
    ) -> ComparisonResultCoverageError {
        inventory ? .invalidInventory(field) : .invalidEvidence(field)
    }
}

private struct ComparisonResultStringBudget {
    let limits: ComparisonResultCoverageLimits
    var total = 0

    mutating func consume(
        _ value: String,
        field: ComparisonResultCoverageField,
        work: inout ComparisonResultWorkBudget
    ) throws {
        let count = value.utf8.count
        try work.charge(count)
        try work.charge()
        guard count <= limits.maximumStringUTF8Bytes else {
            throw ComparisonResultCoverageError.stringTooLarge(
                field,
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        guard total <= limits.maximumTotalStringUTF8Bytes - count else {
            throw ComparisonResultCoverageError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        total += count
    }
}

private struct ComparisonResultWorkBudget {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: ComparisonResultCoverageMatrix.CancellationCheck
    private(set) var completed = 0
    private var workSinceCancellationCheck = 0

    init(
        maximum: Int,
        cancellationCheckInterval: Int,
        cancellationCheck: @escaping ComparisonResultCoverageMatrix.CancellationCheck
    ) {
        self.maximum = maximum
        self.cancellationCheckInterval = cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
    }

    mutating func charge(_ amount: Int = 1) throws {
        guard amount >= 0, amount <= maximum, completed <= maximum - amount else {
            throw ComparisonResultCoverageError.workLimitExceeded(maximum: maximum)
        }
        completed += amount
        workSinceCancellationCheck += amount
        if workSinceCancellationCheck >= cancellationCheckInterval {
            try checkCancellation()
            workSinceCancellationCheck = 0
        }
    }

    mutating func checkCancellation() throws {
        if cancellationCheck() { throw ComparisonResultCoverageError.cancelled }
    }
}

private struct ComparisonResultCanonicalWriter {
    let maximumBytes: Int
    private(set) var data = Data()

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    mutating func append(_ value: UInt8) throws {
        try reserve(1)
        data.append(value)
    }

    mutating func append(_ value: Bool) throws {
        try append(UInt8(value ? 1 : 0))
    }

    mutating func append(_ value: UInt64) throws {
        var bigEndian = value.bigEndian
        try withUnsafeBytes(of: &bigEndian) { bytes in
            try append(bytes)
        }
    }

    mutating func append(_ value: Int) throws {
        guard let unsigned = UInt64(exactly: value) else {
            throw ComparisonResultCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        try append(unsigned)
    }

    mutating func append(_ value: String) throws {
        let byteCount = value.utf8.count
        try append(byteCount)
        try reserve(byteCount)
        data.append(contentsOf: value.utf8)
    }

    mutating func append(_ bytes: [UInt8]) throws {
        try reserve(bytes.count)
        data.append(contentsOf: bytes)
    }

    mutating func append(_ bytes: UnsafeRawBufferPointer) throws {
        try reserve(bytes.count)
        data.append(contentsOf: bytes)
    }

    private mutating func reserve(_ count: Int) throws {
        guard count >= 0, count <= maximumBytes, data.count <= maximumBytes - count else {
            throw ComparisonResultCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
    }
}

private func comparisonResultCanonicalInventoryData(
    _ inventory: ComparisonResultCoverageInventory,
    maximumBytes: Int,
    work: inout ComparisonResultWorkBudget
) throws -> Data {
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append("MMCRINV3")
    try writer.append(ComparisonResultCoverageMatrix.canonicalMatrixRevision)
    try comparisonResultAppend(inventory.reference, to: &writer)
    try comparisonResultAppend(inventory.build, to: &writer)
    try writer.append(inventory.buildArtifactSHA256.count)
    try writer.append(inventory.buildArtifactSHA256)
    let requirements = inventory.requirements.sorted { $0.scenario < $1.scenario }
    try writer.append(requirements.count)
    for requirement in requirements {
        try comparisonResultAppend(requirement, to: &writer)
    }
    try work.charge(writer.data.count)
    return writer.data
}

private func comparisonResultCanonicalEvidenceData(
    _ evidence: ComparisonResultEvidenceBundle,
    maximumBytes: Int,
    work: inout ComparisonResultWorkBudget
) throws -> Data {
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append("MMCREVD3")
    try comparisonResultAppend(evidence.reference, to: &writer)
    try comparisonResultAppend(evidence.inventory, to: &writer)
    try comparisonResultAppend(evidence.build, to: &writer)
    var records: [Data] = []
    records.reserveCapacity(evidence.observations.count)
    for observation in evidence.observations {
        let record = try comparisonResultCanonicalObservationData(
            observation,
            maximumBytes: maximumBytes
        )
        try work.charge(record.count)
        records.append(record)
    }
    records = try comparisonResultStableMergeSort(
        records,
        precedes: { left, right, work in
            try comparisonResultDataPrecedes(left, right, work: &work)
        },
        work: &work
    )
    try writer.append(records.count)
    for record in records {
        try writer.append(record.count)
        try writer.append(Array(record))
    }
    try work.charge(writer.data.count)
    return writer.data
}

private func comparisonResultCanonicalReportData(
    _ report: ComparisonResultCoverageReport,
    maximumBytes: Int,
    work: inout ComparisonResultWorkBudget
) throws -> Data {
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append("MMCRRPT3")
    try writer.append(report.formatVersion)
    try comparisonResultAppend(report.inventory, to: &writer)
    try comparisonResultAppend(report.evidence, to: &writer)
    try writer.append(report.trustedAuditTimeUnixMilliseconds)
    try writer.append(report.auditPolicySHA256.count)
    try writer.append(report.auditPolicySHA256)
    try writer.append(report.matrix.cells.count)
    for cell in report.matrix.cells {
        try writer.append(cell.scenario.rawValue)
        try writer.append(cell.status.rawValue)
        try writer.append(cell.evidenceCount)
        try comparisonResultAppend(cell.expected, to: &writer)
        if let observed = cell.observed {
            try writer.append(true)
            try comparisonResultAppend(observed, to: &writer)
        } else {
            try writer.append(false)
        }
    }
    try writer.append(report.findings.count)
    for finding in report.findings {
        try writer.append(finding.id.rawValue)
        try writer.append(finding.severity.rawValue)
        try writer.append(finding.code.rawValue)
    }
    try work.charge(writer.data.count)
    return writer.data
}

private func comparisonResultCanonicalObservationData(
    _ observation: ComparisonResultEvidence,
    maximumBytes: Int
) throws -> Data {
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append(UInt64(observation.scenarioID.rawValue))
    try comparisonResultAppend(observation.lifecycle, to: &writer)
    try comparisonResultAppend(observation.observed, to: &writer)
    try writer.append(observation.origin.rawValue)
    if let provenance = observation.provenance {
        try writer.append(true)
        try comparisonResultAppend(provenance.build, to: &writer)
        try comparisonResultAppend(provenance.inventory, to: &writer)
        try comparisonResultAppend(provenance.collector, to: &writer)
        try writer.append(provenance.capturedAtUnixMilliseconds)
        try writer.append(provenance.runNonce.count)
        try writer.append(provenance.runNonce)
        try writer.append(provenance.artifactSHA256.count)
        try writer.append(provenance.artifactSHA256)
        try writer.append(provenance.inventorySHA256.count)
        try writer.append(provenance.inventorySHA256)
        try writer.append(provenance.captureSHA256.count)
        try writer.append(provenance.captureSHA256)
        try writer.append(provenance.collectorSignature.count)
        try writer.append(provenance.collectorSignature)
        try writer.append(provenance.source)
    } else {
        try writer.append(false)
    }
    if let accessibility = observation.accessibility {
        try writer.append(true)
        try comparisonResultAppend(accessibility, to: &writer)
    } else {
        try writer.append(false)
    }
    return writer.data
}

private func comparisonResultCanonicalCaptureData(
    _ observation: ComparisonResultEvidence,
    maximumBytes: Int
) throws -> Data {
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append("MMCRCAP3")
    try writer.append(UInt64(observation.scenarioID.rawValue))
    try comparisonResultAppend(observation.lifecycle, to: &writer)
    try comparisonResultAppend(observation.observed, to: &writer)
    if let accessibility = observation.accessibility {
        try writer.append(true)
        try comparisonResultAppend(accessibility, to: &writer)
    } else {
        try writer.append(false)
    }
    return writer.data
}

private func comparisonResultCanonicalCaptureEnvelopeData(
    _ observation: ComparisonResultEvidence,
    maximumBytes: Int
) throws -> Data {
    guard let provenance = observation.provenance else {
        throw ComparisonResultCoverageError.invalidEvidence(.provenance)
    }
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append("MMCRCEN3")
    try writer.append(observation.origin.rawValue)
    try comparisonResultAppend(provenance.build, to: &writer)
    try comparisonResultAppend(provenance.inventory, to: &writer)
    try writer.append(provenance.artifactSHA256.count)
    try writer.append(provenance.artifactSHA256)
    try writer.append(provenance.inventorySHA256.count)
    try writer.append(provenance.inventorySHA256)
    try comparisonResultAppend(provenance.collector, to: &writer)
    try writer.append(provenance.capturedAtUnixMilliseconds)
    try writer.append(provenance.runNonce.count)
    try writer.append(provenance.runNonce)
    try writer.append(provenance.source)
    try writer.append(provenance.captureSHA256.count)
    try writer.append(provenance.captureSHA256)
    return writer.data
}

private func comparisonResultAppend(
    _ requirement: ComparisonResultCoverageRequirement,
    to writer: inout ComparisonResultCanonicalWriter
) throws {
    try writer.append(requirement.scenario.rawValue)
    try comparisonResultAppend(requirement.lifecycle, to: &writer)
    try comparisonResultAppend(requirement.expected, to: &writer)
    if let accessibility = requirement.accessibility {
        try writer.append(true)
        try comparisonResultAppend(accessibility.token, to: &writer)
    } else {
        try writer.append(false)
    }
}

private func comparisonResultAppend(
    _ token: ComparisonResultLifecycleIdentityToken,
    to writer: inout ComparisonResultCanonicalWriter
) throws {
    try comparisonResultAppend(token.binding, to: &writer)
    try writer.append(token.authorityID.count)
    try writer.append(token.authorityID)
    try writer.append(token.signature.count)
    try writer.append(token.signature)
}

private func comparisonResultAppend(
    _ binding: ComparisonResultComparisonBinding,
    to writer: inout ComparisonResultCanonicalWriter
) throws {
    try writer.append(binding.comparisonIdentity.rawValue.uuidString)
    try writer.append(binding.comparisonGeneration)
    try writer.append(binding.inputIdentity.rawValue.uuidString)
    try writer.append(binding.inputGeneration)
    try writer.append(binding.operationID.rawValue.uuidString)
    try writer.append(binding.operationStartedAtGeneration)
    try writer.append(binding.resultIdentity.rawValue.uuidString)
    try writer.append(binding.resultGeneration)
    try writer.append(binding.sources.count)
    for source in binding.sources {
        try writer.append(UInt8(source.side.rawValue))
        try writer.append(source.identity.rawValue.uuidString)
        try writer.append(source.generation)
    }
}

private func comparisonResultAppend(
    _ state: ComparisonResultSemanticState,
    to writer: inout ComparisonResultCanonicalWriter
) throws {
    try writer.append(state.outcome.rawValue)
    try writer.append(state.differences.count)
    for difference in state.differences {
        try writer.append(difference.id.rawValue)
        try writer.append(difference.ordinal)
        try writer.append(difference.rowRange.lowerBound)
        try writer.append(difference.rowRange.upperBound)
    }
    if let selection = state.selection.differenceID {
        try writer.append(true)
        try writer.append(selection.rawValue)
    } else {
        try writer.append(false)
    }
    switch state.cursor {
    case .none:
        try writer.append(false)
    case .row(let index, let differenceID):
        try writer.append(true)
        try writer.append(index)
        if let differenceID {
            try writer.append(true)
            try writer.append(differenceID.rawValue)
        } else {
            try writer.append(false)
        }
    }
    try writer.append(state.viewport.alignedRowCount)
    try writer.append(state.viewport.visibleRows.lowerBound)
    try writer.append(state.viewport.visibleRows.upperBound)
    try writer.append(state.selectionVisibility.rawValue)
    try writer.append(state.commandState.hasSignificantDifferences)
    try writer.append(state.commandState.hasResolvableDifference)
    try writer.append(state.commandState.navigation.first)
    try writer.append(state.commandState.navigation.current)
    try writer.append(state.commandState.navigation.previous)
    try writer.append(state.commandState.navigation.next)
    try writer.append(state.commandState.navigation.last)
}

private func comparisonResultAppend(
    _ link: ComparisonResultAccessibilityEvidenceToken,
    to writer: inout ComparisonResultCanonicalWriter
) throws {
    try writer.append(link.receiptFormatVersion)
    try comparisonResultAppend(link.app, to: &writer)
    try comparisonResultAppend(link.build, to: &writer)
    try writer.append(link.buildArtifactSHA256.count)
    try writer.append(link.buildArtifactSHA256)
    try writer.append(link.buildSigningIdentitySHA256.count)
    try writer.append(link.buildSigningIdentitySHA256)
    try comparisonResultAppend(link.inventory, to: &writer)
    try comparisonResultAppend(link.evidence, to: &writer)
    try comparisonResultAppend(link.scenario, to: &writer)
    try writer.append(link.snapshotID.rawValue)
    try writer.append(link.inventorySHA256.count)
    try writer.append(link.inventorySHA256)
    try writer.append(link.evidenceArchiveSHA256.count)
    try writer.append(link.evidenceArchiveSHA256)
    try writer.append(link.requiredEvidenceCount)
    try writer.append(link.completeEvidenceCount)
    try writer.append(link.findingCount)
    try writer.append(link.archiveByteCount)
    try writer.append(link.authorityID.count)
    try writer.append(link.authorityID)
    try writer.append(link.signature.count)
    try writer.append(link.signature)
}

private func comparisonResultAppend(
    _ token: ComparisonResultAccessibilityInventoryToken,
    to writer: inout ComparisonResultCanonicalWriter
) throws {
    try writer.append(token.receiptFormatVersion)
    try comparisonResultAppend(token.app, to: &writer)
    try comparisonResultAppend(token.build, to: &writer)
    try writer.append(token.buildArtifactSHA256.count)
    try writer.append(token.buildArtifactSHA256)
    try writer.append(token.buildSigningIdentitySHA256.count)
    try writer.append(token.buildSigningIdentitySHA256)
    try comparisonResultAppend(token.inventory, to: &writer)
    try comparisonResultAppend(token.evidence, to: &writer)
    try comparisonResultAppend(token.scenario, to: &writer)
    try writer.append(token.snapshotID.rawValue)
    try writer.append(token.inventorySHA256.count)
    try writer.append(token.inventorySHA256)
    try writer.append(token.requiredEvidenceCount)
    try writer.append(token.authorityID.count)
    try writer.append(token.authorityID)
    try writer.append(token.signature.count)
    try writer.append(token.signature)
}

private func comparisonResultAppend(
    _ reference: ComparisonResultRevisionReference,
    to writer: inout ComparisonResultCanonicalWriter
) throws {
    try writer.append(reference.id.rawValue)
    try writer.append(reference.generation)
}

private func comparisonResultAppend(
    _ reference: AccessibilityEvidenceRevisionReference,
    to writer: inout ComparisonResultCanonicalWriter
) throws {
    try writer.append(reference.id.rawValue)
    try writer.append(reference.revision.rawValue)
}

private func comparisonResultLifecycleAuthenticationData(
    binding: ComparisonResultComparisonBinding,
    authorityID: [UInt8],
    maximumBytes: Int
) throws -> Data {
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append("MMCRLIF1")
    try writer.append(authorityID.count)
    try writer.append(authorityID)
    try comparisonResultAppend(binding, to: &writer)
    return writer.data
}

private func comparisonResultAccessibilityInventoryAuthenticationData(
    _ token: ComparisonResultAccessibilityInventoryToken,
    maximumBytes: Int
) throws -> Data {
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append("MMCRAXI2")
    try writer.append(token.receiptFormatVersion)
    try comparisonResultAppend(token.app, to: &writer)
    try comparisonResultAppend(token.build, to: &writer)
    try writer.append(token.buildArtifactSHA256.count)
    try writer.append(token.buildArtifactSHA256)
    try writer.append(token.buildSigningIdentitySHA256.count)
    try writer.append(token.buildSigningIdentitySHA256)
    try comparisonResultAppend(token.inventory, to: &writer)
    try comparisonResultAppend(token.evidence, to: &writer)
    try comparisonResultAppend(token.scenario, to: &writer)
    try writer.append(token.snapshotID.rawValue)
    try writer.append(token.inventorySHA256.count)
    try writer.append(token.inventorySHA256)
    try writer.append(token.requiredEvidenceCount)
    try writer.append(token.authorityID.count)
    try writer.append(token.authorityID)
    return writer.data
}

private func comparisonResultAccessibilityEvidenceAuthenticationData(
    _ token: ComparisonResultAccessibilityEvidenceToken,
    maximumBytes: Int
) throws -> Data {
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append("MMCRAXE2")
    try writer.append(token.receiptFormatVersion)
    try comparisonResultAppend(token.app, to: &writer)
    try comparisonResultAppend(token.build, to: &writer)
    try writer.append(token.buildArtifactSHA256.count)
    try writer.append(token.buildArtifactSHA256)
    try writer.append(token.buildSigningIdentitySHA256.count)
    try writer.append(token.buildSigningIdentitySHA256)
    try comparisonResultAppend(token.inventory, to: &writer)
    try comparisonResultAppend(token.evidence, to: &writer)
    try comparisonResultAppend(token.scenario, to: &writer)
    try writer.append(token.snapshotID.rawValue)
    try writer.append(token.inventorySHA256.count)
    try writer.append(token.inventorySHA256)
    try writer.append(token.evidenceArchiveSHA256.count)
    try writer.append(token.evidenceArchiveSHA256)
    try writer.append(token.requiredEvidenceCount)
    try writer.append(token.completeEvidenceCount)
    try writer.append(token.findingCount)
    try writer.append(token.archiveByteCount)
    try writer.append(token.authorityID.count)
    try writer.append(token.authorityID)
    return writer.data
}

private func comparisonResultCanonicalAuditPolicyData(
    _ policy: ComparisonResultAuditPolicy,
    verifier: ComparisonResultCoverageVerifier,
    maximumBytes: Int
) throws -> Data {
    var writer = ComparisonResultCanonicalWriter(maximumBytes: maximumBytes)
    try writer.append("MMCRPOL1")
    try writer.append(policy.trustedAuditTimeUnixMilliseconds)
    try writer.append(policy.maximumCaptureAgeMilliseconds)
    try writer.append(policy.maximumFutureClockSkewMilliseconds)
    try comparisonResultAppend(policy.replayPolicy, to: &writer)
    try writer.append(verifier.authorityID.count)
    try writer.append(verifier.authorityID)
    try writer.append(verifier.collectors.count)
    for collector in verifier.collectors {
        try comparisonResultAppend(collector.reference, to: &writer)
        try writer.append(collector.ed25519PublicKey.count)
        try writer.append(collector.ed25519PublicKey)
    }
    return writer.data
}

private func comparisonResultDeterministicWorkUnits(
    inventoryByteCount: Int,
    evidenceByteCount: Int,
    auditPolicyByteCount: Int,
    reportByteCount: Int,
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
        observationCount,
        findingCount
    ] {
        guard count >= 0, count <= maximum, total <= maximum - count else {
            throw ComparisonResultCoverageError.workLimitExceeded(maximum: maximum)
        }
        total += count
    }
    return total
}

private func comparisonResultExpectedCommandState(
    for state: ComparisonResultSemanticState
) -> ComparisonResultCommandState {
    let hasDifferences = !state.differences.isEmpty
    let selected = state.selectedDifference
    let cursorDifference = state.cursorDifference
    let current = selected ?? cursorDifference
    let adjacentOrigin = state.selectionVisibility == .visible ? selected ?? cursorDifference : cursorDifference

    let previous: Bool
    let next: Bool
    if let adjacentOrigin {
        previous = adjacentOrigin.ordinal > 0
        next = adjacentOrigin.ordinal < state.differences.count - 1
    } else if let cursorRow = state.cursor.rowIndex {
        previous = state.differences.contains { $0.lastRow <= cursorRow }
        next = state.differences.contains { $0.firstRow >= cursorRow }
    } else {
        previous = hasDifferences
        next = hasDifferences
    }

    return ComparisonResultCommandState(
        hasSignificantDifferences: hasDifferences,
        hasResolvableDifference: current != nil,
        navigation: ComparisonResultNavigationCommandState(
            first: hasDifferences,
            current: current != nil,
            previous: previous,
            next: next,
            last: hasDifferences
        )
    )
}

private func comparisonResultState(
    _ state: ComparisonResultSemanticState,
    matches scenario: ComparisonResultScenario
) -> Bool {
    let selected = state.selectedDifference
    let cursorDifference = state.cursorDifference
    let cursorRow = state.cursor.rowIndex
    let cursorIsVisible = cursorRow.map(state.viewport.visibleRows.contains) ?? false
    switch scenario {
    case .identical:
        return state.outcome == .identical && state.differences.isEmpty
            && state.selection == .none && state.cursor == .none
            && state.selectionVisibility == .notApplicable
    case .differentWithoutSelection:
        return state.outcome == .different && !state.differences.isEmpty
            && state.selection == .none && state.cursor == .none
            && state.selectionVisibility == .notApplicable
    case .firstSelectedAtStart:
        return state.outcome == .different && state.differences.count >= 3
            && selected?.ordinal == 0 && cursorDifference?.id == selected?.id
            && cursorRow == selected?.firstRow
            && cursorIsVisible
            && state.selectionVisibility == .visible
    case .middleSelectedAtStart:
        guard state.outcome == .different, state.differences.count >= 3,
            let ordinal = selected?.ordinal
        else { return false }
        return ordinal > 0 && ordinal < state.differences.count - 1
            && cursorDifference?.id == selected?.id && cursorRow == selected?.firstRow
            && cursorIsVisible
            && state.selectionVisibility == .visible
    case .lastSelectedAtEnd:
        return state.outcome == .different && state.differences.count >= 3
            && selected?.ordinal == state.differences.count - 1
            && cursorDifference?.id == selected?.id && cursorRow == selected?.lastRow
            && cursorIsVisible
            && state.selectionVisibility == .visible
    case .cursorAtDifferenceStart:
        return state.outcome == .different && state.selection == .none
            && cursorDifference.map { $0.rowRange.count >= 2 && cursorRow == $0.firstRow } == true
            && cursorIsVisible
            && state.selectionVisibility == .notApplicable
    case .cursorAtDifferenceEnd:
        return state.outcome == .different && state.selection == .none
            && cursorDifference.map { $0.rowRange.count >= 2 && cursorRow == $0.lastRow } == true
            && cursorIsVisible
            && state.selectionVisibility == .notApplicable
    case .cursorBeforeFirstDifference:
        return state.outcome == .different && state.selection == .none
            && state.cursor.differenceID == nil
            && cursorRow.map { row in state.differences.first.map { row < $0.firstRow } == true }
                == true
            && cursorIsVisible
            && state.selectionVisibility == .notApplicable
    case .cursorAfterLastDifference:
        return state.outcome == .different && state.selection == .none
            && state.cursor.differenceID == nil
            && cursorRow.map { row in state.differences.last.map { row > $0.lastRow } == true }
                == true
            && cursorIsVisible
            && state.selectionVisibility == .notApplicable
    case .selectionVisibleWithoutCursor:
        return state.outcome == .different && selected != nil && state.cursor == .none
            && state.selectionVisibility == .visible
    case .selectionVisibleWithCursorOnOtherDifference:
        return state.outcome == .different && state.differences.count >= 2
            && selected != nil && cursorDifference != nil && cursorDifference?.id != selected?.id
            && cursorIsVisible
            && state.selectionVisibility == .visible
    case .selectionVisibleWithCursorOnUnchangedRow:
        return state.outcome == .different && selected != nil && cursorRow != nil
            && state.cursor.differenceID == nil && cursorIsVisible
            && state.selectionVisibility == .visible
    case .selectionOffscreenWithCursorBefore:
        return state.outcome == .different && selected != nil
            && cursorRow.map { $0 < selected!.firstRow } == true
            && cursorIsVisible
            && state.selectionVisibility == .offscreen
    case .selectionOffscreenWithCursorAfter:
        return state.outcome == .different && selected != nil
            && cursorRow.map { $0 > selected!.lastRow } == true
            && cursorIsVisible
            && state.selectionVisibility == .offscreen
    case .selectionOffscreenWithoutCursor:
        return state.outcome == .different && selected != nil && state.cursor == .none
            && state.selectionVisibility == .offscreen
    case .cursorBetweenDifferences:
        guard state.outcome == .different, state.selection == .none,
            state.differences.count >= 2, state.cursor.differenceID == nil,
            let cursorRow
        else { return false }
        return zip(state.differences, state.differences.dropFirst()).contains { before, after in
            before.lastRow < cursorRow && cursorRow < after.firstRow
        } && cursorIsVisible && state.selectionVisibility == .notApplicable
    }
}

private func comparisonResultSelectionVisibility(
    selection: ComparisonResultSelectionState,
    differences: [ComparisonResultDifference],
    viewport: ComparisonResultViewportState
) -> ComparisonResultSelectionVisibility {
    guard let selectionID = selection.differenceID,
        let difference = differences.first(where: { $0.id == selectionID })
    else { return .notApplicable }
    guard !viewport.visibleRows.isEmpty else { return .offscreen }
    return difference.rowRange.overlaps(viewport.visibleRows) ? .visible : .offscreen
}

private func comparisonResultCaptureTimeIsValid(
    _ capturedAt: UInt64,
    policy: ComparisonResultAuditPolicy
) -> Bool {
    let earliest =
        policy.trustedAuditTimeUnixMilliseconds >= policy.maximumCaptureAgeMilliseconds
        ? policy.trustedAuditTimeUnixMilliseconds - policy.maximumCaptureAgeMilliseconds : 0
    let (latest, overflow) = policy.trustedAuditTimeUnixMilliseconds.addingReportingOverflow(
        policy.maximumFutureClockSkewMilliseconds
    )
    return capturedAt >= earliest && (overflow || capturedAt <= latest)
}

private func comparisonResultStateIsStructurallyValid(_ state: ComparisonResultSemanticState) -> Bool {
    guard (state.outcome == .identical) == state.differences.isEmpty,
        state.viewport.alignedRowCount >= 0,
        state.viewport.alignedRowCount <= ComparisonResultCoverageLimits.hardMaximumRows,
        state.viewport.visibleRows.lowerBound >= 0,
        state.viewport.visibleRows.lowerBound <= state.viewport.visibleRows.upperBound,
        state.viewport.visibleRows.upperBound <= state.viewport.alignedRowCount,
        state.selectionVisibility
            == comparisonResultSelectionVisibility(
                selection: state.selection,
                differences: state.differences,
                viewport: state.viewport
            )
    else { return false }
    var identifiers: Set<ComparisonResultStableID> = []
    var previousUpperBound = 0
    for (index, difference) in state.differences.enumerated() {
        guard difference.ordinal == index, difference.rowRange.lowerBound >= previousUpperBound,
            difference.rowRange.lowerBound < difference.rowRange.upperBound,
            difference.rowRange.upperBound <= state.viewport.alignedRowCount,
            comparisonResultIsValidIdentifier(difference.id.rawValue),
            identifiers.insert(difference.id).inserted
        else { return false }
        previousUpperBound = difference.rowRange.upperBound
    }
    if let selectionID = state.selection.differenceID, !identifiers.contains(selectionID) {
        return false
    }
    if state.selection == .none {
        guard state.selectionVisibility == .notApplicable else { return false }
    } else if state.selectionVisibility == .notApplicable {
        return false
    }
    if case .row(let index, let differenceID) = state.cursor {
        guard index >= 0, index < state.viewport.alignedRowCount else { return false }
        if let differenceID {
            guard let difference = state.differences.first(where: { $0.id == differenceID }),
                difference.rowRange.contains(index)
            else { return false }
        } else if state.differences.contains(where: { $0.rowRange.contains(index) }) {
            return false
        }
    }
    return true
}

private func comparisonResultBindingIsValid(_ binding: ComparisonResultComparisonBinding) -> Bool {
    guard binding.sources.count == 2 || binding.sources.count == 3 else { return false }
    let expected: [ComparisonLifecycleState.Side] =
        binding.sources.count == 2 ? [.left, .right] : [.left, .middle, .right]
    return binding.sources.map(\.side) == expected
}

private func comparisonResultCanonicalSources(
    _ sources: [ComparisonResultSourceBinding]
) throws -> [ComparisonResultSourceBinding] {
    guard sources.count == 2 || sources.count == 3 else {
        throw ComparisonResultCoverageError.invalidComparisonBinding
    }
    let sorted = sources.sorted()
    let expected: [ComparisonLifecycleState.Side] =
        sources.count == 2 ? [.left, .right] : [.left, .middle, .right]
    guard sorted.map(\.side) == expected else {
        throw ComparisonResultCoverageError.invalidComparisonBinding
    }
    return sorted
}

private func comparisonResultGenerations(
    in binding: ComparisonResultComparisonBinding
) -> [UInt64] {
    [
        binding.comparisonGeneration,
        binding.inputGeneration,
        binding.operationStartedAtGeneration,
        binding.resultGeneration
    ] + binding.sources.map(\.generation)
}

private func comparisonResultFindingPrecedes(
    _ left: ComparisonResultFinding,
    _ right: ComparisonResultFinding
) -> Bool {
    if left.severity != right.severity { return left.severity > right.severity }
    if left.code != right.code {
        return comparisonResultCompareUTF8(left.code.rawValue, right.code.rawValue) < 0
    }
    return left.id < right.id
}

private func comparisonResultStableMergeSort<Element>(
    _ elements: [Element],
    precedes: (Element, Element, inout ComparisonResultWorkBudget) throws -> Bool,
    work: inout ComparisonResultWorkBudget
) throws -> [Element] {
    guard elements.count > 1 else { return elements }
    var source = elements
    var destination = elements
    var width = 1
    while width < source.count {
        var lowerBound = source.startIndex
        while lowerBound < source.endIndex {
            let middle = min(lowerBound + width, source.endIndex)
            let upperBound = min(middle + width, source.endIndex)
            var left = lowerBound
            var right = middle
            var output = lowerBound
            while left < middle, right < upperBound {
                try work.charge()
                if try precedes(source[right], source[left], &work) {
                    destination[output] = source[right]
                    right += 1
                } else {
                    destination[output] = source[left]
                    left += 1
                }
                output += 1
            }
            while left < middle {
                try work.charge()
                destination[output] = source[left]
                left += 1
                output += 1
            }
            while right < upperBound {
                try work.charge()
                destination[output] = source[right]
                right += 1
                output += 1
            }
            lowerBound = upperBound
        }
        swap(&source, &destination)
        let halfCountRoundedUp = source.count / 2 + source.count % 2
        width = width >= halfCountRoundedUp ? source.count : width * 2
    }
    return source
}

private func comparisonResultDataPrecedes(
    _ left: Data,
    _ right: Data,
    work: inout ComparisonResultWorkBudget
) throws -> Bool {
    for (leftByte, rightByte) in zip(left, right) {
        try work.charge()
        if leftByte != rightByte { return leftByte < rightByte }
    }
    return left.count < right.count
}

private func comparisonResultCompareUUID(_ left: UUID, _ right: UUID) -> Int {
    comparisonResultCompareUTF8(left.uuidString, right.uuidString)
}

private func comparisonResultCompareUTF8(_ left: String, _ right: String) -> Int {
    let leftBytes = Array(left.utf8)
    let rightBytes = Array(right.utf8)
    for (leftByte, rightByte) in zip(leftBytes, rightBytes) where leftByte != rightByte {
        return leftByte < rightByte ? -1 : 1
    }
    if leftBytes.count == rightBytes.count { return 0 }
    return leftBytes.count < rightBytes.count ? -1 : 1
}

private func comparisonResultFrame(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
}

private func comparisonResultIsValidDigest(_ digest: [UInt8]) -> Bool {
    digest.count == SHA256.byteCount && !digest.allSatisfy { $0 == 0 }
}

private func comparisonResultIsValidIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value == value.precomposedStringWithCanonicalMapping else { return false }
    return value.unicodeScalars.allSatisfy {
        !CharacterSet.controlCharacters.contains($0) && !$0.properties.isWhitespace
    }
}

private func comparisonResultIsValidSource(_ value: String) -> Bool {
    guard !value.isEmpty, value == value.precomposedStringWithCanonicalMapping else { return false }
    return value.unicodeScalars.allSatisfy { scalar in
        !CharacterSet.controlCharacters.contains(scalar) || scalar.value == 0x09
    }
}

private func comparisonResultFindingMessage(_ code: ComparisonResultFindingCode) -> String {
    switch code {
    case .duplicateScenarioEvidence:
        "Comparison-result scenario has duplicate evidence."
    case .missingScenarioEvidence:
        "Comparison-result scenario has no measured production evidence."
    case .unexpectedScenarioEvidence:
        "Evidence targets a scenario outside the canonical matrix."
    case .comparisonIdentityMismatch:
        "Observed comparison identity does not match the requirement."
    case .inputIdentityMismatch:
        "Observed input identity does not match the requirement."
    case .resultIdentityMismatch:
        "Observed result identity does not match the requirement."
    case .operationIdentityMismatch:
        "Observed operation identity does not match the requirement."
    case .sourceIdentityMismatch:
        "Observed source identities do not match the requirement."
    case .generationMismatch:
        "Observed comparison, input, operation, result, or source generation is stale."
    case .resultStateMismatch:
        "Observed result or difference set does not match the semantic requirement."
    case .selectionStateMismatch:
        "Observed selection does not match the semantic requirement."
    case .cursorStateMismatch:
        "Observed cursor does not match the semantic requirement."
    case .viewportStateMismatch:
        "Observed viewport does not match the semantic requirement."
    case .selectionVisibilityMismatch:
        "Observed selection visibility does not match the semantic requirement."
    case .commandStateMismatch:
        "Observed difference command state does not match the semantic requirement."
    case .accessibilityEvidenceMissing:
        "Required generic accessibility evidence is missing."
    case .accessibilityEvidenceMismatch:
        "Generic accessibility evidence is bound to another build, inventory, scenario, or snapshot."
    case .accessibilityEvidenceIncomplete:
        "Generic accessibility evidence receipt does not record complete valid evidence."
    case .lifecycleAuthenticationInvalid:
        "Lifecycle identity was not authenticated by the pinned authority."
    case .accessibilityAuthenticationInvalid:
        "Accessibility inventory or evidence was not authenticated by the pinned authority."
    case .productionProvenanceMissing:
        "Measured production evidence is missing capture provenance."
    case .productionProvenanceInvalid:
        "Measured production evidence has invalid capture provenance; details are redacted."
    case .provenanceBuildMismatch:
        "Measured production provenance is bound to another build generation."
    case .provenanceInventoryMismatch:
        "Measured production provenance is bound to another inventory generation."
    case .provenanceArtifactMismatch:
        "Measured production provenance is bound to another build artifact."
    case .untrustedCollector:
        "Measured production evidence was not emitted by an inventory-trusted collector."
    case .productionCaptureMismatch:
        "Resolved production capture does not match its canonical observation and digest."
    case .assertionOnlyEvidence:
        "Caller assertion cannot count as measured production proof."
    }
}
