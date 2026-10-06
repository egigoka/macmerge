import CryptoKit
import Foundation

public enum PaneShapePaneCount: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case two = 2
    case three = 3

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }

    public var identities: [PaneIdentity] {
        switch self {
        case .two: [.left, .right]
        case .three: [.left, .middle, .right]
        }
    }

    public init(_ paneCount: PaneLayout.PaneCount) {
        switch paneCount {
        case .two: self = .two
        case .three: self = .three
        }
    }
}

public enum PaneShapeOrientation: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case vertical
    case horizontal

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }

    public init(_ orientation: PaneLayout.Orientation) {
        switch orientation {
        case .vertical: self = .vertical
        case .horizontal: self = .horizontal
        }
    }
}

public struct PaneShapeScenarioID: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

/// One valid coordinate in the canonical pane-shape matrix.
///
/// Two-way scenarios permit only left or right as the active logical owner. `isSwapped` means
/// right/left for two panes and right/middle/left for three panes.
public struct PaneShapeScenario: Identifiable, Comparable, Hashable, Sendable {
    public let id: PaneShapeScenarioID
    public let paneCount: PaneShapePaneCount
    public let activePane: PaneIdentity
    public let isSwapped: Bool
    public let orientation: PaneShapeOrientation

    public init(
        paneCount: PaneShapePaneCount,
        activePane: PaneIdentity,
        isSwapped: Bool,
        orientation: PaneShapeOrientation
    ) throws {
        guard paneCount.identities.contains(activePane) else {
            throw PaneShapeCoverageError.impossibleScenario
        }
        self.init(
            validatedPaneCount: paneCount,
            activePane: activePane,
            isSwapped: isSwapped,
            orientation: orientation
        )
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.id < right.id
    }

    public var expectedVisualOrder: [PaneIdentity] {
        guard isSwapped else { return paneCount.identities }
        return paneCount.identities.reversed()
    }

    public var activeVisualIndex: Int {
        expectedVisualOrder.firstIndex(of: activePane)!
    }

    public func logicalPane(atVisualIndex index: Int) -> PaneIdentity? {
        expectedVisualOrder.indices.contains(index) ? expectedVisualOrder[index] : nil
    }

    public func visualIndex(of pane: PaneIdentity) -> Int? {
        expectedVisualOrder.firstIndex(of: pane)
    }

    fileprivate init(
        validatedPaneCount paneCount: PaneShapePaneCount,
        activePane: PaneIdentity,
        isSwapped: Bool,
        orientation: PaneShapeOrientation
    ) {
        self.paneCount = paneCount
        self.activePane = activePane
        self.isSwapped = isSwapped
        self.orientation = orientation

        let base = paneCount == .two ? 0 : 8
        let activeIndex = paneCount.identities.firstIndex(of: activePane)!
        let swapIndex = isSwapped ? 1 : 0
        id = PaneShapeScenarioID(
            rawValue: UInt16(base + activeIndex * 4 + swapIndex * 2 + Int(orientation.rawValue))
        )
    }
}

public struct PaneShapeStableID: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        paneShapeCompareUTF8(left.rawValue, right.rawValue) < 0
    }
}

/// Exact caller-owned identity and monotonically advancing revision.
public struct PaneShapeRevisionReference: Comparable, Hashable, Sendable {
    public let id: PaneShapeStableID
    public let revision: UInt64

    public init(id: PaneShapeStableID, revision: UInt64) {
        self.id = id
        self.revision = revision
    }

    public static func < (left: Self, right: Self) -> Bool {
        if left.id != right.id { return left.id < right.id }
        return left.revision < right.revision
    }
}

public struct PaneShapeSourceRevisionBinding: Comparable, Hashable, Sendable {
    public let pane: PaneIdentity
    public let source: PaneShapeRevisionReference

    public init(pane: PaneIdentity, source: PaneShapeRevisionReference) {
        self.pane = pane
        self.source = source
    }

    public static func < (left: Self, right: Self) -> Bool {
        let paneComparison = paneShapePaneRank(left.pane) - paneShapePaneRank(right.pane)
        if paneComparison != 0 { return paneComparison < 0 }
        return left.source < right.source
    }
}

/// Exact current comparison, input, result, and source revisions.
public struct PaneShapeComparisonRevisionBinding: Hashable, Sendable {
    public let comparison: PaneShapeRevisionReference
    public let inputs: PaneShapeRevisionReference
    public let result: PaneShapeRevisionReference
    public let sources: [PaneShapeSourceRevisionBinding]

    public init(
        comparison: PaneShapeRevisionReference,
        inputs: PaneShapeRevisionReference,
        result: PaneShapeRevisionReference,
        sources: [PaneShapeSourceRevisionBinding]
    ) throws {
        self.comparison = comparison
        self.inputs = inputs
        self.result = result
        self.sources = try paneShapeCanonicalSources(sources)
    }

    /// Captures only an exact current lifecycle result. Loading, stale, failed, canceled, and
    /// retained-but-not-current results are rejected.
    public init(_ state: ComparisonLifecycleState) throws {
        guard state.phase == .current, state.hasCurrentResult,
            let inputs = state.inputs, let result = state.result, result.inputs == inputs
        else {
            throw PaneShapeCoverageError.comparisonNotCurrent
        }

        let sources = result.inputs.sides.map { binding in
            PaneShapeSourceRevisionBinding(
                pane: paneShapePane(binding.side),
                source: PaneShapeRevisionReference(
                    id: PaneShapeStableID(rawValue: binding.identity.rawValue.uuidString),
                    revision: binding.generation
                )
            )
        }
        try self.init(
            comparison: PaneShapeRevisionReference(
                id: PaneShapeStableID(rawValue: state.identity.rawValue.uuidString),
                revision: state.generation
            ),
            inputs: PaneShapeRevisionReference(
                id: PaneShapeStableID(rawValue: inputs.identity.rawValue.uuidString),
                revision: inputs.generation
            ),
            result: PaneShapeRevisionReference(
                id: PaneShapeStableID(rawValue: result.identity.rawValue.uuidString),
                revision: result.publishedAtGeneration
            ),
            sources: sources
        )
    }
}

/// Exact layout, source, and comparison bindings for one matrix row.
public struct PaneShapeRevisionBindings: Hashable, Sendable {
    public let layout: PaneShapeRevisionReference
    public let sources: [PaneShapeSourceRevisionBinding]
    public let comparison: PaneShapeComparisonRevisionBinding

    public init(
        layout: PaneShapeRevisionReference,
        sources: [PaneShapeSourceRevisionBinding],
        comparison: PaneShapeComparisonRevisionBinding
    ) throws {
        let canonicalSources = try paneShapeCanonicalSources(sources)
        guard canonicalSources == comparison.sources else {
            throw PaneShapeCoverageError.inconsistentRevisionBindings
        }
        self.layout = layout
        self.sources = canonicalSources
        self.comparison = comparison
    }
}

public struct PaneShapeCoverageRequirement: Identifiable, Hashable, Sendable {
    public var id: PaneShapeScenarioID { scenario.id }

    public let scenario: PaneShapeScenario
    public let bindings: PaneShapeRevisionBindings

    public init(scenario: PaneShapeScenario, bindings: PaneShapeRevisionBindings) {
        self.scenario = scenario
        self.bindings = bindings
    }
}

/// Inventory-pinned Ed25519 identity for one production evidence collector.
public struct PaneShapeTrustedCollector: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: PaneShapeRevisionReference
    public let ed25519PublicKey: [UInt8]

    public init(reference: PaneShapeRevisionReference, ed25519PublicKey: [UInt8]) {
        self.reference = reference
        self.ed25519PublicKey = ed25519PublicKey
    }

    public var description: String { "PaneShapeTrustedCollector(key: <redacted>)" }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["reference": "<redacted>", "key": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// Exact production inventory. Audit validation requires one requirement for every canonical row.
public struct PaneShapeCoverageInventory: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: PaneShapeRevisionReference
    public let build: PaneShapeRevisionReference
    public let buildArtifactSHA256: [UInt8]
    public let trustedCollectors: [PaneShapeTrustedCollector]
    public let requirements: [PaneShapeCoverageRequirement]

    public init(
        reference: PaneShapeRevisionReference,
        build: PaneShapeRevisionReference,
        buildArtifactSHA256: [UInt8],
        trustedCollectors: [PaneShapeTrustedCollector],
        requirements: [PaneShapeCoverageRequirement]
    ) {
        self.reference = reference
        self.build = build
        self.buildArtifactSHA256 = buildArtifactSHA256
        self.trustedCollectors = trustedCollectors
        self.requirements = requirements
    }

    public static func canonical(
        reference: PaneShapeRevisionReference,
        build: PaneShapeRevisionReference,
        buildArtifactSHA256: [UInt8],
        trustedCollectors: [PaneShapeTrustedCollector],
        bindingsByScenario: [PaneShapeScenarioID: PaneShapeRevisionBindings]
    ) throws -> Self {
        let requirements = try PaneShapeCoverageMatrix.canonicalScenarios.map { scenario in
            guard let bindings = bindingsByScenario[scenario.id] else {
                throw PaneShapeCoverageError.invalidInventory(field: "requirements")
            }
            return PaneShapeCoverageRequirement(scenario: scenario, bindings: bindings)
        }
        guard bindingsByScenario.count == requirements.count else {
            throw PaneShapeCoverageError.invalidInventory(field: "requirements")
        }
        return Self(
            reference: reference,
            build: build,
            buildArtifactSHA256: buildArtifactSHA256,
            trustedCollectors: trustedCollectors,
            requirements: requirements
        )
    }

    public var description: String {
        "PaneShapeCoverageInventory(requirements: \(requirements.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "trustedCollectorCount": trustedCollectors.count,
                "requirementCount": requirements.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct PaneShapeLayoutObservation: Hashable, Sendable {
    public let paneCount: PaneShapePaneCount
    public let visualOrder: [PaneIdentity]
    public let activePane: PaneIdentity
    public let orientation: PaneShapeOrientation

    public init(
        paneCount: PaneShapePaneCount,
        visualOrder: [PaneIdentity],
        activePane: PaneIdentity,
        orientation: PaneShapeOrientation
    ) throws {
        guard visualOrder.count == Int(paneCount.rawValue),
            Set(visualOrder) == Set(paneCount.identities), visualOrder.contains(activePane)
        else {
            throw PaneShapeCoverageError.invalidObservation(field: "layout")
        }
        self.paneCount = paneCount
        self.visualOrder = visualOrder
        self.activePane = activePane
        self.orientation = orientation
    }

    public init(_ layout: PaneLayout) {
        paneCount = PaneShapePaneCount(layout.paneCount)
        visualOrder = layout.visualOrder
        activePane = layout.activePane
        orientation = PaneShapeOrientation(layout.orientation)
    }
}

/// Shared command-state projection captured independently from the layout observation.
public struct PaneShapeCommandStateObservation: Hashable, Sendable {
    public let visualOrder: [PaneIdentity]
    public let activePane: PaneIdentity

    public init(visualOrder: [PaneIdentity], activePane: PaneIdentity) throws {
        guard visualOrder.count == 2 || visualOrder.count == 3 else {
            throw PaneShapeCoverageError.invalidObservation(field: "commandState")
        }
        let expected: Set<PaneIdentity> =
            visualOrder.count == 2 ? [.left, .right] : [.left, .middle, .right]
        guard Set(visualOrder) == expected, visualOrder.contains(activePane) else {
            throw PaneShapeCoverageError.invalidObservation(field: "commandState")
        }
        self.visualOrder = visualOrder
        self.activePane = activePane
    }

    public init(_ context: ComparisonCommandState.LayoutContext) {
        visualOrder = context.visualOrder.map(PaneIdentity.init)
        activePane = PaneIdentity(context.activePane)
    }
}

public enum PaneShapeEvidenceOrigin: UInt8, CaseIterable, Hashable, Sendable {
    case productionAutomation
    case productionManualReview
    case callerAssertion

    public var isProductionProof: Bool {
        self != .callerAssertion
    }
}

public enum PaneShapeCaptureResolutionError: Error, Equatable, Sendable {
    case exceedsMaximumByteCount
}

/// Provenance for one production observation. Artifact and capture digests are exact SHA-256 bytes.
public struct PaneShapeEvidenceProvenance: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let build: PaneShapeRevisionReference
    public let inventory: PaneShapeRevisionReference
    public let collector: PaneShapeRevisionReference
    public let capturedAtUnixMilliseconds: UInt64
    public let runNonce: [UInt8]
    public let artifactSHA256: [UInt8]
    public let captureSHA256: [UInt8]
    /// Ed25519 signature over `PaneShapeCoverageMatrix.canonicalCaptureData(for:)`.
    public let collectorSignature: [UInt8]
    public let source: String

    public init(
        build: PaneShapeRevisionReference,
        inventory: PaneShapeRevisionReference,
        collector: PaneShapeRevisionReference,
        capturedAtUnixMilliseconds: UInt64,
        runNonce: [UInt8],
        artifactSHA256: [UInt8],
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
        self.captureSHA256 = captureSHA256
        self.collectorSignature = collectorSignature
        self.source = source.precomposedStringWithCanonicalMapping
    }

    public var description: String { "PaneShapeEvidenceProvenance(<redacted>)" }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["provenance": "<redacted>"], displayStyle: .struct)
    }
}

/// Caller-supplied trust boundary for deterministic capture freshness and replay validation.
public struct PaneShapeAuditPolicy: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public struct RunNonceClaimContext: Sendable {
        public let trustedAuditTimeUnixMilliseconds: UInt64
        public let deadlineUnixMilliseconds: UInt64
        public let remainingWorkUnits: Int
        public let cancellationCheck: PaneShapeCoverageMatrix.CancellationCheck

        fileprivate init(
            trustedAuditTimeUnixMilliseconds: UInt64,
            deadlineUnixMilliseconds: UInt64,
            remainingWorkUnits: Int,
            cancellationCheck: @escaping PaneShapeCoverageMatrix.CancellationCheck
        ) {
            self.trustedAuditTimeUnixMilliseconds = trustedAuditTimeUnixMilliseconds
            self.deadlineUnixMilliseconds = deadlineUnixMilliseconds
            self.remainingWorkUnits = remainingWorkUnits
            self.cancellationCheck = cancellationCheck
        }
    }

    public enum RunNonceClaimResult: UInt8, Hashable, Sendable {
        case committed
        case rejectedReplay
        case cancelled
        case deadlineExceeded
        case workLimitExceeded
    }

    public typealias RunNonceClaim =
        @Sendable (
            _ claimPolicy: PaneShapeRevisionReference,
            _ runNonces: [[UInt8]],
            _ context: RunNonceClaimContext
        ) -> RunNonceClaimResult

    public static let dayMilliseconds: UInt64 = 86_400_000

    public let trustedAuditTimeUnixMilliseconds: UInt64
    public let maximumCaptureAgeMilliseconds: UInt64
    public let maximumFutureClockSkewMilliseconds: UInt64
    public let runNonceClaimDeadlineUnixMilliseconds: UInt64
    public let runNonceClaimPolicy: PaneShapeRevisionReference
    private let claimRunNonces: RunNonceClaim

    public init(
        trustedAuditTimeUnixMilliseconds: UInt64,
        maximumCaptureAgeMilliseconds: UInt64 = 7 * dayMilliseconds,
        maximumFutureClockSkewMilliseconds: UInt64 = 5 * 60 * 1_000,
        runNonceClaimDeadlineUnixMilliseconds: UInt64,
        runNonceClaimPolicy: PaneShapeRevisionReference,
        /// Must perform one atomic all-or-none commit. It must honor the supplied cancellation,
        /// deadline, and remaining-work bounds before commit. Only `.committed` may retain any
        /// nonce; every other result must leave claim state unchanged.
        claimRunNonces: @escaping RunNonceClaim
    ) {
        self.trustedAuditTimeUnixMilliseconds = trustedAuditTimeUnixMilliseconds
        self.maximumCaptureAgeMilliseconds = maximumCaptureAgeMilliseconds
        self.maximumFutureClockSkewMilliseconds = maximumFutureClockSkewMilliseconds
        self.runNonceClaimDeadlineUnixMilliseconds = runNonceClaimDeadlineUnixMilliseconds
        self.runNonceClaimPolicy = runNonceClaimPolicy
        self.claimRunNonces = claimRunNonces
    }

    fileprivate func claim(
        _ runNonces: [[UInt8]],
        context: RunNonceClaimContext
    ) -> RunNonceClaimResult {
        claimRunNonces(runNonceClaimPolicy, runNonces, context)
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.trustedAuditTimeUnixMilliseconds == right.trustedAuditTimeUnixMilliseconds
            && left.maximumCaptureAgeMilliseconds == right.maximumCaptureAgeMilliseconds
            && left.maximumFutureClockSkewMilliseconds == right.maximumFutureClockSkewMilliseconds
            && left.runNonceClaimDeadlineUnixMilliseconds
                == right.runNonceClaimDeadlineUnixMilliseconds
            && left.runNonceClaimPolicy == right.runNonceClaimPolicy
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(trustedAuditTimeUnixMilliseconds)
        hasher.combine(maximumCaptureAgeMilliseconds)
        hasher.combine(maximumFutureClockSkewMilliseconds)
        hasher.combine(runNonceClaimDeadlineUnixMilliseconds)
        hasher.combine(runNonceClaimPolicy)
    }

    public var description: String {
        "PaneShapeAuditPolicy(trustedTime: \(trustedAuditTimeUnixMilliseconds), maximumAge: \(maximumCaptureAgeMilliseconds), maximumSkew: \(maximumFutureClockSkewMilliseconds), claimDeadline: \(runNonceClaimDeadlineUnixMilliseconds), claimPolicy: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "trustedAuditTimeUnixMilliseconds": trustedAuditTimeUnixMilliseconds,
                "maximumCaptureAgeMilliseconds": maximumCaptureAgeMilliseconds,
                "maximumFutureClockSkewMilliseconds": maximumFutureClockSkewMilliseconds,
                "runNonceClaimDeadlineUnixMilliseconds": runNonceClaimDeadlineUnixMilliseconds,
                "runNonceClaimPolicy": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// One caller-supplied observation of production layout, shared command state, and lifecycle state.
public struct PaneShapeProductionEvidence: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let scenarioID: PaneShapeScenarioID
    public let bindings: PaneShapeRevisionBindings
    public let layout: PaneShapeLayoutObservation
    public let commandState: PaneShapeCommandStateObservation
    public let comparisonPhase: ComparisonLifecycleState.Phase
    public let hasCurrentComparisonResult: Bool
    public let origin: PaneShapeEvidenceOrigin
    public let provenance: PaneShapeEvidenceProvenance?

    public init(
        scenarioID: PaneShapeScenarioID,
        bindings: PaneShapeRevisionBindings,
        layout: PaneShapeLayoutObservation,
        commandState: PaneShapeCommandStateObservation,
        comparisonPhase: ComparisonLifecycleState.Phase,
        hasCurrentComparisonResult: Bool,
        origin: PaneShapeEvidenceOrigin,
        provenance: PaneShapeEvidenceProvenance?
    ) {
        self.scenarioID = scenarioID
        self.bindings = bindings
        self.layout = layout
        self.commandState = commandState
        self.comparisonPhase = comparisonPhase
        self.hasCurrentComparisonResult = hasCurrentComparisonResult
        self.origin = origin
        self.provenance = provenance
    }

    public init(
        scenarioID: PaneShapeScenarioID,
        layoutReference: PaneShapeRevisionReference,
        layout: PaneLayout,
        commandState: ComparisonCommandState.LayoutContext,
        comparisonState: ComparisonLifecycleState,
        origin: PaneShapeEvidenceOrigin,
        provenance: PaneShapeEvidenceProvenance?
    ) throws {
        let comparison = try PaneShapeComparisonRevisionBinding(comparisonState)
        let bindings = try PaneShapeRevisionBindings(
            layout: layoutReference,
            sources: comparison.sources,
            comparison: comparison
        )
        self.init(
            scenarioID: scenarioID,
            bindings: bindings,
            layout: PaneShapeLayoutObservation(layout),
            commandState: PaneShapeCommandStateObservation(commandState),
            comparisonPhase: comparisonState.phase,
            hasCurrentComparisonResult: comparisonState.hasCurrentResult,
            origin: origin,
            provenance: provenance
        )
    }

    public var description: String {
        "PaneShapeProductionEvidence(scenario: \(scenarioID.rawValue), contents: <redacted>)"
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

public struct PaneShapeEvidenceBundle: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: PaneShapeRevisionReference
    public let inventory: PaneShapeRevisionReference
    public let build: PaneShapeRevisionReference
    public let observations: [PaneShapeProductionEvidence]

    public init(
        reference: PaneShapeRevisionReference,
        inventory: PaneShapeRevisionReference,
        build: PaneShapeRevisionReference,
        observations: [PaneShapeProductionEvidence]
    ) {
        self.reference = reference
        self.inventory = inventory
        self.build = build
        self.observations = observations
    }

    public var description: String {
        "PaneShapeEvidenceBundle(observations: \(observations.count), contents: <redacted>)"
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

public struct PaneShapeCoverageLimits: Hashable, Sendable {
    public static let hardMaximumTrustedCollectors = 1_024
    public static let hardMaximumObservations = 100_000
    public static let hardMaximumStringUTF8Bytes = 1 * 1_024 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 64 * 1_024 * 1_024
    public static let hardMaximumWorkUnits = 100_000_000
    public static let hardMaximumFindings = 100_000
    public static let hardMaximumCanonicalBytes = 64 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = PaneShapeCoverageLimits()

    public let maximumTrustedCollectors: Int
    public let maximumObservations: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumWorkUnits: Int
    public let maximumFindings: Int
    public let maximumCanonicalBytes: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumTrustedCollectors: Int = 64,
        maximumObservations: Int = 4_096,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumWorkUnits: Int = 4 * 1_024 * 1_024,
        maximumFindings: Int = 4_096,
        maximumCanonicalBytes: Int = 8 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) {
        self.maximumTrustedCollectors = maximumTrustedCollectors
        self.maximumObservations = maximumObservations
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumFindings = maximumFindings
        self.maximumCanonicalBytes = maximumCanonicalBytes
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum PaneShapeCoverageLimit: String, CaseIterable, Hashable, Sendable {
    case trustedCollectors
    case observations
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case workUnits
    case findings
    case canonicalBytes
    case cancellationCheckInterval
}

public enum PaneShapeCoverageError: Error, Equatable, LocalizedError, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case cancelled
    case impossibleScenario
    case comparisonNotCurrent
    case inconsistentRevisionBindings
    case invalidLimit(PaneShapeCoverageLimit)
    case observationLimitExceeded(maximum: Int)
    case stringTooLarge(field: String, maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximum: Int)
    case findingLimitExceeded(maximum: Int)
    case canonicalDataTooLarge(maximumBytes: Int)
    case invalidAuditPolicy(field: String)
    case invalidInventory(field: String)
    case invalidEvidence(field: String)
    case invalidObservation(field: String)
    case staleBuild
    case staleInventory
    case staleEvidence
    case receiptMismatch

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Pane-shape coverage audit was cancelled."
        case .impossibleScenario:
            "Pane-shape scenario is impossible."
        case .comparisonNotCurrent:
            "Pane-shape comparison binding requires an exact current lifecycle result."
        case .inconsistentRevisionBindings:
            "Pane-shape source and comparison revision bindings are inconsistent."
        case .invalidLimit(let limit):
            "Pane-shape coverage limit is invalid: \(limit.rawValue)."
        case .observationLimitExceeded(let maximum):
            "Pane-shape evidence exceeds the \(maximum)-observation limit."
        case .stringTooLarge(_, let maximum):
            "Pane-shape field exceeds \(maximum) UTF-8 bytes; field and contents are redacted."
        case .totalStringsTooLarge(let maximum):
            "Pane-shape strings exceed \(maximum) UTF-8 bytes; contents are redacted."
        case .workLimitExceeded(let maximum):
            "Pane-shape audit exceeds \(maximum) work units."
        case .findingLimitExceeded(let maximum):
            "Pane-shape audit exceeds \(maximum) findings."
        case .canonicalDataTooLarge(let maximum):
            "Pane-shape canonical data exceeds \(maximum) bytes."
        case .invalidAuditPolicy:
            "Pane-shape audit policy is invalid; field and contents are redacted."
        case .invalidInventory:
            "Pane-shape inventory is invalid; field and contents are redacted."
        case .invalidEvidence:
            "Pane-shape evidence is invalid; field and contents are redacted."
        case .invalidObservation:
            "Pane-shape observation is invalid; field and contents are redacted."
        case .staleBuild:
            "Pane-shape evidence belongs to another build identity or revision."
        case .staleInventory:
            "Pane-shape evidence belongs to another inventory identity or revision."
        case .staleEvidence:
            "Pane-shape evidence revision changed before receipt validation."
        case .receiptMismatch:
            "Pane-shape receipt no longer matches current canonical contents."
        }
    }

    public var description: String { errorDescription ?? "Pane-shape coverage error." }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["error": description], displayStyle: .enum)
    }
}

public enum PaneShapeFindingSeverity: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case advisory
    case warning
    case error

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

public enum PaneShapeFindingCode: String, CaseIterable, Hashable, Sendable {
    case duplicateScenarioEvidence
    case missingScenarioEvidence
    case unexpectedScenarioEvidence
    case layoutRevisionMismatch
    case sourceRevisionMismatch
    case comparisonRevisionMismatch
    case paneCountMismatch
    case visualOrderMismatch
    case activePaneMismatch
    case orientationMismatch
    case commandVisualOrderMismatch
    case commandActivePaneMismatch
    case comparisonLifecycleMismatch
    case productionProvenanceMissing
    case productionProvenanceInvalid
    case provenanceBuildMismatch
    case provenanceInventoryMismatch
    case provenanceArtifactMismatch
    case untrustedCollector
    case productionCaptureExpired
    case productionCaptureFutureDated
    case productionNonceReplay
    case productionCaptureMismatch
    case assertionOnlyEvidence
}

public enum PaneShapeFindingSubject: Hashable, Sendable {
    case matrix
    case scenario(PaneShapeScenarioID)
}

public struct PaneShapeFinding: Identifiable, Hashable, Sendable {
    public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            paneShapeCompareUTF8(left.rawValue, right.rawValue) < 0
        }
    }

    public let id: ID
    public let severity: PaneShapeFindingSeverity
    public let code: PaneShapeFindingCode
    public let subject: PaneShapeFindingSubject
    /// Fixed wording. Revisions, provenance, sources, nonces, and digests are never interpolated.
    public let message: String

    fileprivate init(
        severity: PaneShapeFindingSeverity,
        code: PaneShapeFindingCode,
        subject: PaneShapeFindingSubject,
        discriminator: Int = 0
    ) {
        self.severity = severity
        self.code = code
        self.subject = subject
        message = paneShapeFindingMessage(code)

        let subjectValue: String
        switch subject {
        case .matrix: subjectValue = "matrix"
        case .scenario(let id): subjectValue = "scenario:\(id.rawValue)"
        }
        id = ID(
            rawValue: [code.rawValue, subjectValue, String(discriminator)]
                .map(paneShapeFrame).joined()
        )
    }
}

public enum PaneShapeCompletenessStatus: UInt8, CaseIterable, Hashable, Sendable {
    case complete
    case missing
    case duplicate
    case mismatched
    case invalid
    case assertionOnly
}

public struct PaneShapeCompletenessCell: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let scenario: PaneShapeScenario
    public let expectedVisualOrder: [PaneIdentity]
    public let expectedActivePane: PaneIdentity
    public let observedLayout: PaneShapeLayoutObservation?
    public let evidenceCount: Int
    public let status: PaneShapeCompletenessStatus

    fileprivate init(
        scenario: PaneShapeScenario,
        observedLayout: PaneShapeLayoutObservation?,
        evidenceCount: Int,
        status: PaneShapeCompletenessStatus
    ) {
        self.scenario = scenario
        expectedVisualOrder = scenario.expectedVisualOrder
        expectedActivePane = scenario.activePane
        self.observedLayout = observedLayout
        self.evidenceCount = evidenceCount
        self.status = status
    }

    public var description: String {
        "PaneShapeCompletenessCell(scenario: \(scenario.id.rawValue), count: \(evidenceCount), status: \(status), values: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "scenarioID": scenario.id,
                "evidenceCount": evidenceCount,
                "status": status,
                "values": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct PaneShapeCompletenessMatrix: Hashable, Sendable {
    public let cells: [PaneShapeCompletenessCell]

    fileprivate init(cells: [PaneShapeCompletenessCell]) {
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

public struct PaneShapeCoverageReport: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let scopeStatement =
        "Deterministic validation of caller-supplied, revision-bound pane-shape production evidence; not independent runtime UI verification."

    public let formatVersion: Int
    public let inventory: PaneShapeRevisionReference
    public let evidence: PaneShapeRevisionReference
    public let trustedAuditTimeUnixMilliseconds: UInt64
    public let maximumCaptureAgeMilliseconds: UInt64
    public let maximumFutureClockSkewMilliseconds: UInt64
    public let runNonceClaimDeadlineUnixMilliseconds: UInt64
    public let runNonceClaimPolicy: PaneShapeRevisionReference
    public let auditPolicySHA256: [UInt8]
    public let matrix: PaneShapeCompletenessMatrix
    public let findings: [PaneShapeFinding]

    public var highestSeverity: PaneShapeFindingSeverity? { findings.first?.severity }
    public var containsErrors: Bool { findings.contains { $0.severity == .error } }
    public var isCompleteAndValid: Bool { matrix.isComplete && findings.isEmpty }

    fileprivate init(
        formatVersion: Int,
        inventory: PaneShapeRevisionReference,
        evidence: PaneShapeRevisionReference,
        auditPolicy: PaneShapeAuditPolicy,
        auditPolicySHA256: [UInt8],
        matrix: PaneShapeCompletenessMatrix,
        findings: [PaneShapeFinding]
    ) {
        self.formatVersion = formatVersion
        self.inventory = inventory
        self.evidence = evidence
        trustedAuditTimeUnixMilliseconds = auditPolicy.trustedAuditTimeUnixMilliseconds
        maximumCaptureAgeMilliseconds = auditPolicy.maximumCaptureAgeMilliseconds
        maximumFutureClockSkewMilliseconds = auditPolicy.maximumFutureClockSkewMilliseconds
        runNonceClaimDeadlineUnixMilliseconds = auditPolicy.runNonceClaimDeadlineUnixMilliseconds
        runNonceClaimPolicy = auditPolicy.runNonceClaimPolicy
        self.auditPolicySHA256 = auditPolicySHA256
        self.matrix = matrix
        self.findings = findings
    }

    public var description: String {
        "PaneShapeCoverageReport(required: \(matrix.requiredCount), complete: \(matrix.completeCount), findings: \(findings.count), contents: <redacted>)"
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
public struct PaneShapeCoverageReceipt: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public enum RunNonceClaimStatus: UInt8, Hashable, Sendable {
        case notRequired
        case committed
        case rejectedReplay
    }

    public let formatVersion: Int
    public let build: PaneShapeRevisionReference
    public let inventory: PaneShapeRevisionReference
    public let evidence: PaneShapeRevisionReference
    public let inventorySHA256: [UInt8]
    public let evidenceSHA256: [UInt8]
    public let reportSHA256: [UInt8]
    public let auditPolicySHA256: [UInt8]
    public let runNonceClaimStatus: RunNonceClaimStatus
    public let requiredScenarioCount: Int
    public let completeScenarioCount: Int
    public let findingCount: Int

    fileprivate init(
        formatVersion: Int,
        build: PaneShapeRevisionReference,
        inventory: PaneShapeRevisionReference,
        evidence: PaneShapeRevisionReference,
        inventorySHA256: [UInt8],
        evidenceSHA256: [UInt8],
        reportSHA256: [UInt8],
        auditPolicySHA256: [UInt8],
        runNonceClaimStatus: RunNonceClaimStatus,
        requiredScenarioCount: Int,
        completeScenarioCount: Int,
        findingCount: Int
    ) {
        self.formatVersion = formatVersion
        self.build = build
        self.inventory = inventory
        self.evidence = evidence
        self.inventorySHA256 = inventorySHA256
        self.evidenceSHA256 = evidenceSHA256
        self.reportSHA256 = reportSHA256
        self.auditPolicySHA256 = auditPolicySHA256
        self.runNonceClaimStatus = runNonceClaimStatus
        self.requiredScenarioCount = requiredScenarioCount
        self.completeScenarioCount = completeScenarioCount
        self.findingCount = findingCount
    }

    public func validateCurrent(
        inventory currentInventory: PaneShapeCoverageInventory,
        evidence currentEvidence: PaneShapeEvidenceBundle,
        limits: PaneShapeCoverageLimits = .default,
        auditPolicy: PaneShapeAuditPolicy? = nil,
        captureResolver: @escaping PaneShapeCoverageMatrix.CaptureResolver,
        cancellationCheck: @escaping PaneShapeCoverageMatrix.CancellationCheck = {
            Task.isCancelled
        }
    ) throws {
        try PaneShapeCoverageMatrix.validate(
            receipt: self,
            inventory: currentInventory,
            evidence: currentEvidence,
            limits: limits,
            auditPolicy: auditPolicy,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck
        )
    }

    public var description: String {
        "PaneShapeCoverageReceipt(required: \(requiredScenarioCount), complete: \(completeScenarioCount), findings: \(findingCount), claimStatus: \(runNonceClaimStatus), digests: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "runNonceClaimStatus": runNonceClaimStatus,
                "requiredScenarioCount": requiredScenarioCount,
                "completeScenarioCount": completeScenarioCount,
                "findingCount": findingCount,
                "digests": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public struct PaneShapeCoverageResult: Hashable, Sendable {
    public let report: PaneShapeCoverageReport
    public let receipt: PaneShapeCoverageReceipt

    fileprivate init(report: PaneShapeCoverageReport, receipt: PaneShapeCoverageReceipt) {
        self.report = report
        self.receipt = receipt
    }
}

/// Bounded UI-independent audit for the complete two/three-pane shape matrix.
public enum PaneShapeCoverageMatrix: Sendable {
    public typealias CancellationCheck = @Sendable () -> Bool
    /// Resolver must stop before returning more than `maximumByteCount` bytes and throw
    /// `PaneShapeCaptureResolutionError.exceedsMaximumByteCount` on overflow.
    public typealias CaptureResolver =
        @Sendable (
            _ captureSHA256: [UInt8],
            _ maximumByteCount: Int,
            _ cancellationCheck: CancellationCheck
        ) throws -> Data
    public static let reportFormatVersion = 5
    public static let canonicalMatrixRevision = 1

    public static let canonicalScenarios: [PaneShapeScenario] = {
        var result: [PaneShapeScenario] = []
        for paneCount in PaneShapePaneCount.allCases {
            for activePane in paneCount.identities {
                for isSwapped in [false, true] {
                    for orientation in PaneShapeOrientation.allCases {
                        result.append(
                            PaneShapeScenario(
                                validatedPaneCount: paneCount,
                                activePane: activePane,
                                isSwapped: isSwapped,
                                orientation: orientation
                            )
                        )
                    }
                }
            }
        }
        return result
    }()

    /// Canonical payload a trusted collector must persist for resolver-backed production proof.
    public static func canonicalCaptureData(
        for observation: PaneShapeProductionEvidence,
        limits: PaneShapeCoverageLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try PaneShapeValidation.validate(limits)
        let budget = PaneShapeWorkBudget(
            maximum: limits.maximumWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try budget.checkCancellation()
        return try paneShapeCanonicalCaptureData(
            observation,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
    }

    public static func audit(
        inventory: PaneShapeCoverageInventory,
        evidence: PaneShapeEvidenceBundle,
        limits: PaneShapeCoverageLimits = .default,
        auditPolicy: PaneShapeAuditPolicy? = nil,
        captureResolver: @escaping CaptureResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> PaneShapeCoverageResult {
        var context = try PaneShapeAuditContext(
            inventory: inventory,
            evidence: evidence,
            limits: limits,
            auditPolicy: auditPolicy,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck,
            expectedReceipt: nil
        )
        let result = try context.run()
        return try context.finalizeAudit(result)
    }

    public static func validate(
        receipt: PaneShapeCoverageReceipt,
        inventory: PaneShapeCoverageInventory,
        evidence: PaneShapeEvidenceBundle,
        limits: PaneShapeCoverageLimits = .default,
        auditPolicy: PaneShapeAuditPolicy? = nil,
        captureResolver: @escaping CaptureResolver,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws {
        var context = try PaneShapeAuditContext(
            inventory: inventory,
            evidence: evidence,
            limits: limits,
            auditPolicy: auditPolicy,
            captureResolver: captureResolver,
            cancellationCheck: cancellationCheck,
            expectedReceipt: receipt
        )
        let current = try context.run()
        guard
            try paneShapeCoverageReceiptsEqual(
                current.receipt,
                receipt,
                budget: context.budget
            )
        else {
            throw PaneShapeCoverageError.receiptMismatch
        }
    }
}

private struct PaneShapeObservationAssessment {
    var assertionOnly = false
    var invalid = false
    var mismatched = false
}

private struct PaneShapeAuditContext {
    let inventory: PaneShapeCoverageInventory
    let evidence: PaneShapeEvidenceBundle
    let limits: PaneShapeCoverageLimits
    let auditPolicy: PaneShapeAuditPolicy
    let captureResolver: PaneShapeCoverageMatrix.CaptureResolver
    let expectedReceipt: PaneShapeCoverageReceipt?
    var budget: PaneShapeWorkBudget
    private var findings: [PaneShapeFinding] = []
    private var findingIDs: Set<PaneShapeFinding.ID> = []
    private var runNoncesToClaim: [[UInt8]] = []

    init(
        inventory: PaneShapeCoverageInventory,
        evidence: PaneShapeEvidenceBundle,
        limits: PaneShapeCoverageLimits,
        auditPolicy: PaneShapeAuditPolicy?,
        captureResolver: @escaping PaneShapeCoverageMatrix.CaptureResolver,
        cancellationCheck: @escaping PaneShapeCoverageMatrix.CancellationCheck,
        expectedReceipt: PaneShapeCoverageReceipt?
    ) throws {
        try PaneShapeValidation.validate(limits)
        guard let auditPolicy else {
            throw PaneShapeCoverageError.invalidAuditPolicy(field: "trustedAuditTime")
        }
        self.inventory = inventory
        self.evidence = evidence
        self.limits = limits
        self.auditPolicy = auditPolicy
        self.captureResolver = captureResolver
        self.expectedReceipt = expectedReceipt
        budget = PaneShapeWorkBudget(
            maximum: limits.maximumWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try budget.checkCancellation()
    }

    mutating func run() throws -> PaneShapeCoverageResult {
        try PaneShapeValidation.preflight(
            inventory: inventory,
            evidence: evidence,
            auditPolicy: auditPolicy,
            limits: limits,
            budget: &budget
        )
        let auditPolicyData = try paneShapeCanonicalAuditPolicyData(
            auditPolicy,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        let auditPolicyDigest = try paneShapeSHA256(auditPolicyData, budget: budget)
        if let expectedReceipt {
            guard try paneShapeRevisionReferencesEqual(inventory.build, expectedReceipt.build, budget: budget) else {
                throw PaneShapeCoverageError.staleBuild
            }
            guard try paneShapeRevisionReferencesEqual(inventory.reference, expectedReceipt.inventory, budget: budget) else {
                throw PaneShapeCoverageError.staleInventory
            }
            guard try paneShapeRevisionReferencesEqual(evidence.reference, expectedReceipt.evidence, budget: budget) else {
                throw PaneShapeCoverageError.staleEvidence
            }
            guard auditPolicyDigest == expectedReceipt.auditPolicySHA256 else {
                throw PaneShapeCoverageError.receiptMismatch
            }
        }
        guard try paneShapeRevisionReferencesEqual(evidence.build, inventory.build, budget: budget) else {
            throw PaneShapeCoverageError.staleBuild
        }
        guard try paneShapeRevisionReferencesEqual(evidence.inventory, inventory.reference, budget: budget) else {
            throw PaneShapeCoverageError.staleInventory
        }

        let inventoryData = try paneShapeCanonicalInventoryData(
            inventory,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        let inventoryDigest = try paneShapeSHA256(inventoryData, budget: budget)
        if let expectedReceipt, inventoryDigest != expectedReceipt.inventorySHA256 {
            throw PaneShapeCoverageError.staleInventory
        }
        let evidenceData = try paneShapeCanonicalEvidenceData(
            evidence,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        let evidenceDigest = try paneShapeSHA256(evidenceData, budget: budget)
        if let expectedReceipt, evidenceDigest != expectedReceipt.evidenceSHA256 {
            throw PaneShapeCoverageError.staleEvidence
        }

        let requirements = Dictionary(uniqueKeysWithValues: inventory.requirements.map { ($0.id, $0) })
        var observations: [PaneShapeScenarioID: [PaneShapeProductionEvidence]] = [:]
        observations.reserveCapacity(evidence.observations.count)
        for observation in evidence.observations {
            try budget.charge()
            observations[observation.scenarioID, default: []].append(observation)
        }
        var sortedScenarioIDs = Array(observations.keys)
        try paneShapeSort(&sortedScenarioIDs) { left, right in
            try budget.charge()
            return left < right
        }
        for scenarioID in sortedScenarioIDs {
            var keyed: [(Data, PaneShapeProductionEvidence)] = []
            let candidates = observations[scenarioID, default: []]
            keyed.reserveCapacity(candidates.count)
            for observation in candidates {
                let key = try paneShapeCanonicalObservationData(
                    observation,
                    maximumBytes: limits.maximumCanonicalBytes,
                    budget: budget
                )
                keyed.append((key, observation))
            }
            try paneShapeSort(&keyed) { left, right in
                try paneShapeDataPrecedes(left.0, right.0, budget: budget)
            }
            observations[scenarioID] = keyed.map(\.1)
        }

        for scenarioID in sortedScenarioIDs where requirements[scenarioID] == nil {
            try add(.error, .unexpectedScenarioEvidence, subject: .scenario(scenarioID))
        }

        var cells: [PaneShapeCompletenessCell] = []
        cells.reserveCapacity(PaneShapeCoverageMatrix.canonicalScenarios.count)
        for scenario in PaneShapeCoverageMatrix.canonicalScenarios {
            try budget.charge()
            let requirement = requirements[scenario.id]!
            let candidates = observations[scenario.id] ?? []
            if candidates.isEmpty {
                try add(.error, .missingScenarioEvidence, subject: .scenario(scenario.id))
                cells.append(
                    PaneShapeCompletenessCell(
                        scenario: scenario,
                        observedLayout: nil,
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

            var combined = PaneShapeObservationAssessment()
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

            let selected = candidates[0]
            let status: PaneShapeCompletenessStatus
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
                PaneShapeCompletenessCell(
                    scenario: scenario,
                    observedLayout: selected.layout,
                    evidenceCount: candidates.count,
                    status: status
                )
            )
        }

        let canClaimRunNonces =
            !runNoncesToClaim.isEmpty
            && !findings.contains(where: { $0.severity == .error })
        if let expectedReceipt {
            switch expectedReceipt.runNonceClaimStatus {
            case .notRequired:
                guard !canClaimRunNonces else { throw PaneShapeCoverageError.receiptMismatch }
            case .committed, .rejectedReplay:
                guard canClaimRunNonces else { throw PaneShapeCoverageError.receiptMismatch }
            }
        }
        if expectedReceipt?.runNonceClaimStatus == .rejectedReplay {
            for scenario in PaneShapeCoverageMatrix.canonicalScenarios {
                try add(.error, .productionNonceReplay, subject: .scenario(scenario.id))
            }
            for index in cells.indices where cells[index].status == .complete {
                let cell = cells[index]
                cells[index] = PaneShapeCompletenessCell(
                    scenario: cell.scenario,
                    observedLayout: cell.observedLayout,
                    evidenceCount: cell.evidenceCount,
                    status: .invalid
                )
            }
        }

        var sortedFindings = findings
        try paneShapeSort(&sortedFindings) { left, right in
            try budget.charge()
            if left.severity != right.severity { return left.severity > right.severity }
            if left.code != right.code {
                return paneShapeCompareUTF8(left.code.rawValue, right.code.rawValue) < 0
            }
            return left.id < right.id
        }
        let report = PaneShapeCoverageReport(
            formatVersion: PaneShapeCoverageMatrix.reportFormatVersion,
            inventory: inventory.reference,
            evidence: evidence.reference,
            auditPolicy: auditPolicy,
            auditPolicySHA256: auditPolicyDigest,
            matrix: PaneShapeCompletenessMatrix(cells: cells),
            findings: sortedFindings
        )
        return try makeResult(
            report: report,
            inventoryDigest: inventoryDigest,
            evidenceDigest: evidenceDigest,
            auditPolicyDigest: auditPolicyDigest,
            runNonceClaimStatus: expectedReceipt?.runNonceClaimStatus ?? .notRequired
        )
    }

    fileprivate mutating func finalizeAudit(
        _ provisional: PaneShapeCoverageResult
    ) throws -> PaneShapeCoverageResult {
        guard !runNoncesToClaim.isEmpty else { return provisional }
        guard !provisional.report.containsErrors else { return provisional }
        for nonce in runNoncesToClaim {
            try budget.charge(nonce.count)
        }
        try budget.checkCancellation()
        let context = PaneShapeAuditPolicy.RunNonceClaimContext(
            trustedAuditTimeUnixMilliseconds: auditPolicy.trustedAuditTimeUnixMilliseconds,
            deadlineUnixMilliseconds: auditPolicy.runNonceClaimDeadlineUnixMilliseconds,
            remainingWorkUnits: budget.remaining,
            cancellationCheck: budget.cancellationCheck
        )
        // Closure owns deadline, cancellation, and work enforcement for its atomic transaction.
        let claimResult = auditPolicy.claim(runNoncesToClaim, context: context)
        switch claimResult {
        case .committed:
            // Atomic claim is now committed; this branch performs only in-memory construction.
            return PaneShapeCoverageResult(
                report: provisional.report,
                receipt: receipt(
                    for: provisional.report,
                    inventorySHA256: provisional.receipt.inventorySHA256,
                    evidenceSHA256: provisional.receipt.evidenceSHA256,
                    auditPolicySHA256: provisional.receipt.auditPolicySHA256,
                    reportSHA256: provisional.receipt.reportSHA256,
                    runNonceClaimStatus: .committed
                )
            )
        case .rejectedReplay:
            var replayFindings = provisional.report.findings
            for scenario in PaneShapeCoverageMatrix.canonicalScenarios {
                let finding = PaneShapeFinding(
                    severity: .error,
                    code: .productionNonceReplay,
                    subject: .scenario(scenario.id)
                )
                guard !replayFindings.contains(where: { $0.id == finding.id }) else { continue }
                guard replayFindings.count < limits.maximumFindings else {
                    throw PaneShapeCoverageError.findingLimitExceeded(
                        maximum: limits.maximumFindings
                    )
                }
                replayFindings.append(finding)
            }
            try paneShapeSort(&replayFindings) { left, right in
                try budget.charge()
                if left.severity != right.severity { return left.severity > right.severity }
                if left.code != right.code {
                    return paneShapeCompareUTF8(left.code.rawValue, right.code.rawValue) < 0
                }
                return left.id < right.id
            }
            var replayCells = provisional.report.matrix.cells
            for index in replayCells.indices where replayCells[index].status == .complete {
                let cell = replayCells[index]
                replayCells[index] = PaneShapeCompletenessCell(
                    scenario: cell.scenario,
                    observedLayout: cell.observedLayout,
                    evidenceCount: cell.evidenceCount,
                    status: .invalid
                )
            }
            let report = PaneShapeCoverageReport(
                formatVersion: provisional.report.formatVersion,
                inventory: provisional.report.inventory,
                evidence: provisional.report.evidence,
                auditPolicy: auditPolicy,
                auditPolicySHA256: provisional.report.auditPolicySHA256,
                matrix: PaneShapeCompletenessMatrix(cells: replayCells),
                findings: replayFindings
            )
            return try makeResult(
                report: report,
                inventoryDigest: provisional.receipt.inventorySHA256,
                evidenceDigest: provisional.receipt.evidenceSHA256,
                auditPolicyDigest: provisional.receipt.auditPolicySHA256,
                runNonceClaimStatus: .rejectedReplay
            )
        case .cancelled:
            throw PaneShapeCoverageError.cancelled
        case .deadlineExceeded:
            throw PaneShapeCoverageError.invalidAuditPolicy(field: "runNonceClaimDeadline")
        case .workLimitExceeded:
            throw PaneShapeCoverageError.workLimitExceeded(maximum: limits.maximumWorkUnits)
        }
    }

    private func makeResult(
        report: PaneShapeCoverageReport,
        inventoryDigest: [UInt8],
        evidenceDigest: [UInt8],
        auditPolicyDigest: [UInt8],
        runNonceClaimStatus: PaneShapeCoverageReceipt.RunNonceClaimStatus
    ) throws -> PaneShapeCoverageResult {
        let reportData = try paneShapeCanonicalReportData(
            report,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        let reportDigest = try paneShapeSHA256(reportData, budget: budget)
        try budget.checkCancellation()
        return PaneShapeCoverageResult(
            report: report,
            receipt: receipt(
                for: report,
                inventorySHA256: inventoryDigest,
                evidenceSHA256: evidenceDigest,
                auditPolicySHA256: auditPolicyDigest,
                reportSHA256: reportDigest,
                runNonceClaimStatus: runNonceClaimStatus
            )
        )
    }

    private func receipt(
        for report: PaneShapeCoverageReport,
        inventorySHA256: [UInt8],
        evidenceSHA256: [UInt8],
        auditPolicySHA256: [UInt8],
        reportSHA256: [UInt8],
        runNonceClaimStatus: PaneShapeCoverageReceipt.RunNonceClaimStatus
    ) -> PaneShapeCoverageReceipt {
        PaneShapeCoverageReceipt(
            formatVersion: PaneShapeCoverageMatrix.reportFormatVersion,
            build: inventory.build,
            inventory: inventory.reference,
            evidence: evidence.reference,
            inventorySHA256: inventorySHA256,
            evidenceSHA256: evidenceSHA256,
            reportSHA256: reportSHA256,
            auditPolicySHA256: auditPolicySHA256,
            runNonceClaimStatus: runNonceClaimStatus,
            requiredScenarioCount: report.matrix.requiredCount,
            completeScenarioCount: report.matrix.completeCount,
            findingCount: report.findings.count
        )
    }

    private mutating func assess(
        _ observation: PaneShapeProductionEvidence,
        requirement: PaneShapeCoverageRequirement,
        discriminator: Int
    ) throws -> PaneShapeObservationAssessment {
        try budget.charge()
        var result = PaneShapeObservationAssessment()
        let scenario = requirement.scenario

        if try !paneShapeRevisionReferencesEqual(
            observation.bindings.layout,
            requirement.bindings.layout,
            budget: budget
        ) {
            result.mismatched = true
            try add(
                .error,
                .layoutRevisionMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        if try !paneShapeSourceBindingsEqual(
            observation.bindings.sources,
            requirement.bindings.sources,
            budget: budget
        ) {
            result.mismatched = true
            try add(
                .error,
                .sourceRevisionMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        if try !paneShapeComparisonBindingsEqual(
            observation.bindings.comparison,
            requirement.bindings.comparison,
            budget: budget
        ) {
            result.mismatched = true
            try add(
                .error,
                .comparisonRevisionMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        if observation.layout.paneCount != scenario.paneCount {
            result.mismatched = true
            try add(
                .error,
                .paneCountMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        if observation.layout.visualOrder != scenario.expectedVisualOrder {
            result.mismatched = true
            try add(
                .error,
                .visualOrderMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        if observation.layout.activePane != scenario.activePane {
            result.mismatched = true
            try add(
                .error,
                .activePaneMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        if observation.layout.orientation != scenario.orientation {
            result.mismatched = true
            try add(
                .error,
                .orientationMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        if observation.commandState.visualOrder != scenario.expectedVisualOrder {
            result.mismatched = true
            try add(
                .error,
                .commandVisualOrderMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        if observation.commandState.activePane != scenario.activePane {
            result.mismatched = true
            try add(
                .error,
                .commandActivePaneMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
        }
        if observation.comparisonPhase != .current || !observation.hasCurrentComparisonResult {
            result.mismatched = true
            try add(
                .error,
                .comparisonLifecycleMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
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
            var captureTrustIsValid = true
            if try !paneShapeRevisionReferencesEqual(provenance.build, inventory.build, budget: budget) {
                result.invalid = true
                captureTrustIsValid = false
                try add(
                    .error,
                    .provenanceBuildMismatch,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if try !paneShapeRevisionReferencesEqual(
                provenance.inventory,
                inventory.reference,
                budget: budget
            ) {
                result.invalid = true
                captureTrustIsValid = false
                try add(
                    .error,
                    .provenanceInventoryMismatch,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if try !PaneShapeValidation.isValid(provenance, budget: budget) {
                result.invalid = true
                captureTrustIsValid = false
                try add(
                    .error,
                    .productionProvenanceInvalid,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if provenance.artifactSHA256 != inventory.buildArtifactSHA256 {
                result.invalid = true
                captureTrustIsValid = false
                try add(
                    .error,
                    .provenanceArtifactMismatch,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if provenance.capturedAtUnixMilliseconds > auditPolicy.trustedAuditTimeUnixMilliseconds {
                let skew =
                    provenance.capturedAtUnixMilliseconds
                    - auditPolicy.trustedAuditTimeUnixMilliseconds
                if skew > auditPolicy.maximumFutureClockSkewMilliseconds {
                    result.invalid = true
                    captureTrustIsValid = false
                    try add(
                        .error,
                        .productionCaptureFutureDated,
                        subject: .scenario(scenario.id),
                        discriminator: discriminator
                    )
                }
            } else {
                let age =
                    auditPolicy.trustedAuditTimeUnixMilliseconds
                    - provenance.capturedAtUnixMilliseconds
                if age > auditPolicy.maximumCaptureAgeMilliseconds {
                    result.invalid = true
                    captureTrustIsValid = false
                    try add(
                        .error,
                        .productionCaptureExpired,
                        subject: .scenario(scenario.id),
                        discriminator: discriminator
                    )
                }
            }
            var trustedCollector: PaneShapeTrustedCollector?
            for candidate in inventory.trustedCollectors {
                try budget.charge()
                if try paneShapeRevisionReferencesEqual(
                    candidate.reference,
                    provenance.collector,
                    budget: budget
                ) {
                    trustedCollector = candidate
                    break
                }
            }
            if trustedCollector == nil {
                result.invalid = true
                captureTrustIsValid = false
                try add(
                    .error,
                    .untrustedCollector,
                    subject: .scenario(scenario.id),
                    discriminator: discriminator
                )
            }
            if let trustedCollector, captureTrustIsValid {
                try validateCapture(
                    observation,
                    provenance: provenance,
                    trustedCollector: trustedCollector,
                    scenario: scenario,
                    discriminator: discriminator,
                    assessment: &result
                )
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

    private mutating func validateCapture(
        _ observation: PaneShapeProductionEvidence,
        provenance: PaneShapeEvidenceProvenance,
        trustedCollector: PaneShapeTrustedCollector,
        scenario: PaneShapeScenario,
        discriminator: Int,
        assessment: inout PaneShapeObservationAssessment
    ) throws {
        let expectedCapture = try paneShapeCanonicalCaptureData(
            observation,
            maximumBytes: limits.maximumCanonicalBytes,
            budget: budget
        )
        let expectedDigest = try paneShapeSHA256(expectedCapture, budget: budget)
        let signatureIsValid = try paneShapeIsValidEd25519Signature(
            provenance.collectorSignature,
            data: expectedCapture,
            publicKey: trustedCollector.ed25519PublicKey,
            budget: budget
        )
        guard signatureIsValid, expectedDigest == provenance.captureSHA256 else {
            assessment.invalid = true
            try add(
                .error,
                .productionCaptureMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
            return
        }

        let capture: Data
        do {
            try budget.checkCancellation()
            capture = try captureResolver(
                provenance.captureSHA256,
                expectedCapture.count,
                budget.cancellationCheck
            )
        } catch PaneShapeCoverageError.cancelled {
            throw PaneShapeCoverageError.cancelled
        } catch is CancellationError {
            throw PaneShapeCoverageError.cancelled
        } catch {
            assessment.invalid = true
            try add(
                .error,
                .productionCaptureMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
            return
        }

        guard capture.count <= expectedCapture.count else {
            assessment.invalid = true
            try add(
                .error,
                .productionCaptureMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
            return
        }
        let contentsMatch = try paneShapeDataEqual(capture, expectedCapture, budget: budget)
        let digestMatches = try paneShapeSHA256(capture, budget: budget) == provenance.captureSHA256
        guard contentsMatch, digestMatches else {
            assessment.invalid = true
            try add(
                .error,
                .productionCaptureMismatch,
                subject: .scenario(scenario.id),
                discriminator: discriminator
            )
            return
        }
        runNoncesToClaim.append(provenance.runNonce)
    }

    private mutating func add(
        _ severity: PaneShapeFindingSeverity,
        _ code: PaneShapeFindingCode,
        subject: PaneShapeFindingSubject,
        discriminator: Int = 0
    ) throws {
        try budget.charge()
        let finding = PaneShapeFinding(
            severity: severity,
            code: code,
            subject: subject,
            discriminator: discriminator
        )
        guard findingIDs.insert(finding.id).inserted else { return }
        guard findings.count < limits.maximumFindings else {
            throw PaneShapeCoverageError.findingLimitExceeded(maximum: limits.maximumFindings)
        }
        findings.append(finding)
    }
}

private enum PaneShapeValidation {
    static func validate(_ limits: PaneShapeCoverageLimits) throws {
        guard
            (1...PaneShapeCoverageLimits.hardMaximumTrustedCollectors).contains(
                limits.maximumTrustedCollectors
            )
        else { throw PaneShapeCoverageError.invalidLimit(.trustedCollectors) }
        guard
            (1...PaneShapeCoverageLimits.hardMaximumObservations).contains(
                limits.maximumObservations
            )
        else { throw PaneShapeCoverageError.invalidLimit(.observations) }
        guard
            (1...PaneShapeCoverageLimits.hardMaximumStringUTF8Bytes).contains(
                limits.maximumStringUTF8Bytes
            )
        else { throw PaneShapeCoverageError.invalidLimit(.stringUTF8Bytes) }
        guard
            (1...PaneShapeCoverageLimits.hardMaximumTotalStringUTF8Bytes).contains(
                limits.maximumTotalStringUTF8Bytes
            ), limits.maximumTotalStringUTF8Bytes >= limits.maximumStringUTF8Bytes
        else {
            throw PaneShapeCoverageError.invalidLimit(.totalStringUTF8Bytes)
        }
        guard
            (1...PaneShapeCoverageLimits.hardMaximumWorkUnits).contains(
                limits.maximumWorkUnits
            )
        else { throw PaneShapeCoverageError.invalidLimit(.workUnits) }
        guard
            (1...PaneShapeCoverageLimits.hardMaximumFindings).contains(
                limits.maximumFindings
            )
        else { throw PaneShapeCoverageError.invalidLimit(.findings) }
        guard
            (1...PaneShapeCoverageLimits.hardMaximumCanonicalBytes).contains(
                limits.maximumCanonicalBytes
            )
        else { throw PaneShapeCoverageError.invalidLimit(.canonicalBytes) }
        guard
            (1...PaneShapeCoverageLimits.hardMaximumCancellationCheckInterval).contains(
                limits.cancellationCheckInterval
            )
        else { throw PaneShapeCoverageError.invalidLimit(.cancellationCheckInterval) }
    }

    static func preflight(
        inventory: PaneShapeCoverageInventory,
        evidence: PaneShapeEvidenceBundle,
        auditPolicy: PaneShapeAuditPolicy,
        limits: PaneShapeCoverageLimits,
        budget: inout PaneShapeWorkBudget
    ) throws {
        guard auditPolicy.trustedAuditTimeUnixMilliseconds > 0,
            auditPolicy.maximumCaptureAgeMilliseconds > 0,
            auditPolicy.runNonceClaimDeadlineUnixMilliseconds
                >= auditPolicy.trustedAuditTimeUnixMilliseconds
        else {
            throw PaneShapeCoverageError.invalidAuditPolicy(field: "freshness")
        }
        guard evidence.observations.count <= limits.maximumObservations else {
            throw PaneShapeCoverageError.observationLimitExceeded(
                maximum: limits.maximumObservations
            )
        }
        guard inventory.requirements.count == PaneShapeCoverageMatrix.canonicalScenarios.count else {
            throw PaneShapeCoverageError.invalidInventory(field: "requirements")
        }
        guard !inventory.trustedCollectors.isEmpty,
            inventory.trustedCollectors.count <= limits.maximumTrustedCollectors,
            paneShapeIsValidDigest(inventory.buildArtifactSHA256)
        else {
            throw PaneShapeCoverageError.invalidInventory(field: "buildProvenance")
        }

        var strings = PaneShapeStringBudget(limits: limits)
        try validate(
            auditPolicy.runNonceClaimPolicy,
            field: "auditPolicy.runNonceClaimPolicy",
            domain: .auditPolicy,
            strings: &strings,
            budget: &budget
        )
        try validate(
            inventory.reference,
            field: "inventory.reference",
            domain: .inventory,
            strings: &strings,
            budget: &budget
        )
        try validate(
            inventory.build,
            field: "inventory.build",
            domain: .inventory,
            strings: &strings,
            budget: &budget
        )
        for collector in inventory.trustedCollectors {
            try budget.charge(collector.ed25519PublicKey.count)
            try budget.checkCancellation()
            do {
                _ = try Curve25519.Signing.PublicKey(
                    rawRepresentation: collector.ed25519PublicKey
                )
            } catch {
                throw PaneShapeCoverageError.invalidInventory(field: "trustedCollectors")
            }
            try budget.checkCancellation()
            try validate(
                collector.reference,
                field: "inventory.trustedCollectors",
                domain: .inventory,
                strings: &strings,
                budget: &budget
            )
        }
        for index in inventory.trustedCollectors.indices {
            for previousIndex in inventory.trustedCollectors.indices where previousIndex < index {
                guard
                    try !paneShapeRevisionReferencesEqual(
                        inventory.trustedCollectors[previousIndex].reference,
                        inventory.trustedCollectors[index].reference,
                        budget: budget
                    )
                else {
                    throw PaneShapeCoverageError.invalidInventory(field: "trustedCollectors")
                }
            }
        }
        try validate(
            evidence.reference,
            field: "evidence.reference",
            domain: .evidence,
            strings: &strings,
            budget: &budget
        )
        try validate(
            evidence.inventory,
            field: "evidence.inventory",
            domain: .evidence,
            strings: &strings,
            budget: &budget
        )
        try validate(
            evidence.build,
            field: "evidence.build",
            domain: .evidence,
            strings: &strings,
            budget: &budget
        )

        let canonicalByID = Dictionary(
            uniqueKeysWithValues: PaneShapeCoverageMatrix.canonicalScenarios.map { ($0.id, $0) }
        )
        var requirementIDs: Set<PaneShapeScenarioID> = []
        var inventoryReferenceContents: [(PaneShapeRevisionReference, Data)] = []
        for requirement in inventory.requirements {
            try budget.charge()
            guard requirementIDs.insert(requirement.id).inserted,
                canonicalByID[requirement.id] == requirement.scenario,
                requirement.bindings.sources.map(\.pane) == requirement.scenario.paneCount.identities
            else {
                throw PaneShapeCoverageError.invalidInventory(field: "requirements")
            }
            try validate(
                requirement.bindings,
                field: "inventory.requirement.bindings",
                domain: .inventory,
                strings: &strings,
                budget: &budget
            )
            try validateReferenceContents(
                requirement.bindings,
                layoutContents: paneShapeCanonicalScenarioData(
                    requirement.scenario,
                    maximumBytes: limits.maximumCanonicalBytes,
                    budget: budget
                ),
                domain: .inventory,
                existing: &inventoryReferenceContents,
                maximumBytes: limits.maximumCanonicalBytes,
                budget: budget
            )
        }
        guard requirementIDs == Set(canonicalByID.keys) else {
            throw PaneShapeCoverageError.invalidInventory(field: "requirements")
        }

        for observation in evidence.observations {
            try budget.charge()
            try validate(
                observation.bindings,
                field: "evidence.observation.bindings",
                domain: .evidence,
                strings: &strings,
                budget: &budget
            )
            try validateReferenceContents(
                observation.bindings,
                layoutContents: paneShapeCanonicalLayoutObservationData(
                    observation.layout,
                    maximumBytes: limits.maximumCanonicalBytes,
                    budget: budget
                ),
                domain: .evidence,
                existing: &inventoryReferenceContents,
                maximumBytes: limits.maximumCanonicalBytes,
                budget: budget
            )
            if let provenance = observation.provenance {
                guard (16...64).contains(provenance.runNonce.count),
                    provenance.artifactSHA256.count == SHA256.byteCount,
                    provenance.captureSHA256.count == SHA256.byteCount,
                    provenance.collectorSignature.count == 64
                else {
                    throw PaneShapeCoverageError.invalidEvidence(field: "provenance")
                }
                try validate(
                    provenance.build,
                    field: "evidence.provenance.build",
                    domain: .evidence,
                    strings: &strings,
                    budget: &budget
                )
                try validate(
                    provenance.inventory,
                    field: "evidence.provenance.inventory",
                    domain: .evidence,
                    strings: &strings,
                    budget: &budget
                )
                try validate(
                    provenance.collector,
                    field: "evidence.provenance.collector",
                    domain: .evidence,
                    strings: &strings,
                    budget: &budget
                )
                try strings.consume(
                    provenance.source,
                    field: "evidence.provenance.source",
                    budget: &budget
                )
                guard try paneShapeIsValidSource(provenance.source, budget: budget) else {
                    throw PaneShapeCoverageError.invalidEvidence(
                        field: "evidence.provenance.source"
                    )
                }
            }
        }
    }

    static func isValid(
        _ provenance: PaneShapeEvidenceProvenance,
        budget: PaneShapeWorkBudget
    ) throws -> Bool {
        try budget.charge()
        guard provenance.capturedAtUnixMilliseconds > 0,
            (16...64).contains(provenance.runNonce.count),
            provenance.collectorSignature.count == 64,
            provenance.runNonce.contains(where: { $0 != 0 }),
            paneShapeIsValidDigest(provenance.artifactSHA256),
            paneShapeIsValidDigest(provenance.captureSHA256),
            try paneShapeIsValidIdentifier(provenance.build.id.rawValue, budget: budget),
            try paneShapeIsValidIdentifier(provenance.inventory.id.rawValue, budget: budget),
            try paneShapeIsValidIdentifier(provenance.collector.id.rawValue, budget: budget),
            try paneShapeIsValidSource(provenance.source, budget: budget)
        else { return false }
        return true
    }

    private static func validate(
        _ bindings: PaneShapeRevisionBindings,
        field: String,
        domain: PaneShapeValidationDomain,
        strings: inout PaneShapeStringBudget,
        budget: inout PaneShapeWorkBudget
    ) throws {
        guard
            try paneShapeSourceBindingsEqual(
                bindings.sources,
                bindings.comparison.sources,
                budget: budget
            )
        else {
            throw invalid(domain, field: field)
        }
        try validate(bindings.layout, field: field, domain: domain, strings: &strings, budget: &budget)
        try validate(
            bindings.comparison.comparison,
            field: field,
            domain: domain,
            strings: &strings,
            budget: &budget
        )
        try validate(
            bindings.comparison.inputs,
            field: field,
            domain: domain,
            strings: &strings,
            budget: &budget
        )
        try validate(
            bindings.comparison.result,
            field: field,
            domain: domain,
            strings: &strings,
            budget: &budget
        )
        for source in bindings.sources {
            try budget.charge()
            try validate(
                source.source,
                field: field,
                domain: domain,
                strings: &strings,
                budget: &budget
            )
        }
    }

    private static func validate(
        _ reference: PaneShapeRevisionReference,
        field: String,
        domain: PaneShapeValidationDomain,
        strings: inout PaneShapeStringBudget,
        budget: inout PaneShapeWorkBudget
    ) throws {
        try strings.consume(reference.id.rawValue, field: field, budget: &budget)
        guard try paneShapeIsValidIdentifier(reference.id.rawValue, budget: budget) else {
            throw invalid(domain, field: field)
        }
    }

    private static func validateReferenceContents(
        _ bindings: PaneShapeRevisionBindings,
        layoutContents: Data,
        domain: PaneShapeValidationDomain,
        existing: inout [(PaneShapeRevisionReference, Data)],
        maximumBytes: Int,
        budget: PaneShapeWorkBudget
    ) throws {
        var pairs: [(PaneShapeRevisionReference, Data)] = [
            (
                bindings.layout,
                try paneShapeCanonicalRevisionContents(
                    role: .layout,
                    contents: layoutContents,
                    maximumBytes: maximumBytes,
                    budget: budget
                )
            ),
            (
                bindings.comparison.comparison,
                try paneShapeCanonicalRevisionContents(
                    role: .comparison,
                    contents: paneShapeCanonicalComparisonBindingData(
                        bindings,
                        maximumBytes: maximumBytes,
                        budget: budget
                    ),
                    maximumBytes: maximumBytes,
                    budget: budget
                )
            ),
            (
                bindings.comparison.inputs,
                try paneShapeCanonicalRevisionContents(
                    role: .inputs,
                    contents: paneShapeCanonicalSourceBindingsData(
                        bindings.sources,
                        maximumBytes: maximumBytes,
                        budget: budget
                    ),
                    maximumBytes: maximumBytes,
                    budget: budget
                )
            ),
            (
                bindings.comparison.result,
                try paneShapeCanonicalRevisionContents(
                    role: .result,
                    contents: paneShapeCanonicalComparisonBindingData(
                        bindings,
                        maximumBytes: maximumBytes,
                        budget: budget
                    ),
                    maximumBytes: maximumBytes,
                    budget: budget
                )
            )
        ]
        for source in bindings.sources {
            pairs.append(
                (
                    source.source,
                    try paneShapeCanonicalRevisionContents(
                        role: .source,
                        contents: Data([UInt8(paneShapePaneRank(source.pane))]),
                        maximumBytes: maximumBytes,
                        budget: budget
                    )
                )
            )
        }
        for (reference, contents) in pairs {
            var matchedReference = false
            for (previousReference, previousContents) in existing {
                if try paneShapeRevisionReferencesEqual(reference, previousReference, budget: budget) {
                    matchedReference = true
                    guard try paneShapeDataEqual(previousContents, contents, budget: budget) else {
                        throw invalid(domain, field: "revisionContents")
                    }
                    break
                }
            }
            if !matchedReference {
                existing.append((reference, contents))
            }
        }
    }

    private static func invalid(
        _ domain: PaneShapeValidationDomain,
        field: String
    ) -> PaneShapeCoverageError {
        switch domain {
        case .auditPolicy: .invalidAuditPolicy(field: field)
        case .inventory: .invalidInventory(field: field)
        case .evidence: .invalidEvidence(field: field)
        }
    }
}

private enum PaneShapeValidationDomain {
    case auditPolicy
    case inventory
    case evidence
}

private enum PaneShapeRevisionContentRole: UInt8 {
    case layout
    case source
    case comparison
    case inputs
    case result
}

private struct PaneShapeStringBudget {
    let limits: PaneShapeCoverageLimits
    var total = 0

    mutating func consume(
        _ value: String,
        field: String,
        budget: inout PaneShapeWorkBudget
    ) throws {
        var count = 0
        for _ in value.utf8 {
            guard count < limits.maximumStringUTF8Bytes else {
                throw PaneShapeCoverageError.stringTooLarge(
                    field: field,
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            guard total <= limits.maximumTotalStringUTF8Bytes - count - 1 else {
                throw PaneShapeCoverageError.totalStringsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
                )
            }
            count += 1
            try budget.charge()
        }
        try budget.charge()
        total += count
    }
}

private final class PaneShapeWorkBudget {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: PaneShapeCoverageMatrix.CancellationCheck
    private(set) var completed = 0
    private var workSinceCancellationCheck = 0

    init(
        maximum: Int,
        cancellationCheckInterval: Int,
        cancellationCheck: @escaping PaneShapeCoverageMatrix.CancellationCheck
    ) {
        self.maximum = maximum
        self.cancellationCheckInterval = cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
    }

    func charge(_ amount: Int = 1) throws {
        guard amount >= 0, amount <= maximum - completed else {
            throw PaneShapeCoverageError.workLimitExceeded(maximum: maximum)
        }
        completed += amount
        workSinceCancellationCheck += amount
        if workSinceCancellationCheck >= cancellationCheckInterval {
            try checkCancellation()
            workSinceCancellationCheck %= cancellationCheckInterval
        }
    }

    var remaining: Int { maximum - completed }

    func checkCancellation() throws {
        if cancellationCheck() { throw PaneShapeCoverageError.cancelled }
    }
}

private struct PaneShapeCanonicalWriter {
    let maximumBytes: Int
    let budget: PaneShapeWorkBudget?
    private(set) var data = Data()

    init(maximumBytes: Int, budget: PaneShapeWorkBudget? = nil) {
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
        try withUnsafeBytes(of: &bigEndian) { bytes in
            try append(bytes)
        }
    }

    mutating func append(_ value: UInt64) throws {
        var bigEndian = value.bigEndian
        try withUnsafeBytes(of: &bigEndian) { bytes in
            try append(bytes)
        }
    }

    mutating func append(count: Int) throws {
        guard let value = UInt64(exactly: count) else {
            throw PaneShapeCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        try append(value)
    }

    mutating func append(_ value: String) throws {
        guard data.count <= maximumBytes - MemoryLayout<UInt64>.size else {
            throw PaneShapeCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        let maximumStringBytes = maximumBytes - data.count - MemoryLayout<UInt64>.size
        var count = 0
        for _ in value.utf8 {
            guard count < maximumStringBytes else {
                throw PaneShapeCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
            }
            count += 1
            try budget?.charge()
        }
        try append(count: count)
        try reserve(count)
        data.append(contentsOf: value.utf8)
    }

    mutating func append(_ bytes: [UInt8]) throws {
        try reserve(bytes.count)
        data.append(contentsOf: bytes)
    }

    mutating func append(_ bytes: Data) throws {
        try reserve(bytes.count)
        data.append(bytes)
    }

    mutating func append(_ bytes: UnsafeRawBufferPointer) throws {
        try reserve(bytes.count)
        data.append(contentsOf: bytes)
    }

    private mutating func reserve(_ count: Int) throws {
        guard count >= 0, data.count <= maximumBytes - count else {
            throw PaneShapeCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        try budget?.charge(count)
    }
}

private func paneShapeCanonicalInventoryData(
    _ inventory: PaneShapeCoverageInventory,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget? = nil
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMPSINV1")
    try writer.append(UInt64(PaneShapeCoverageMatrix.canonicalMatrixRevision))
    try paneShapeAppend(inventory.reference, to: &writer)
    try paneShapeAppend(inventory.build, to: &writer)
    try writer.append(count: inventory.buildArtifactSHA256.count)
    try writer.append(inventory.buildArtifactSHA256)
    var collectorRecords: [Data] = []
    collectorRecords.reserveCapacity(inventory.trustedCollectors.count)
    for collector in inventory.trustedCollectors {
        var collectorWriter = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
        try paneShapeAppend(collector.reference, to: &collectorWriter)
        try collectorWriter.append(count: collector.ed25519PublicKey.count)
        try collectorWriter.append(collector.ed25519PublicKey)
        collectorRecords.append(collectorWriter.data)
    }
    if let budget {
        try paneShapeSort(&collectorRecords) { left, right in
            try paneShapeDataPrecedes(left, right, budget: budget)
        }
    } else {
        collectorRecords.sort { $0.lexicographicallyPrecedes($1) }
    }
    try writer.append(count: collectorRecords.count)
    for collectorRecord in collectorRecords {
        try writer.append(collectorRecord)
    }
    var requirements = inventory.requirements
    if let budget {
        try paneShapeSort(&requirements) { left, right in
            try budget.charge()
            return left.id < right.id
        }
    } else {
        requirements.sort { $0.id < $1.id }
    }
    try writer.append(count: requirements.count)
    for requirement in requirements {
        try paneShapeAppend(requirement.scenario, to: &writer)
        try paneShapeAppend(requirement.bindings, to: &writer)
    }
    return writer.data
}

private func paneShapeCanonicalEvidenceData(
    _ evidence: PaneShapeEvidenceBundle,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMPSEVD2")
    try paneShapeAppend(evidence.reference, to: &writer)
    try paneShapeAppend(evidence.inventory, to: &writer)
    try paneShapeAppend(evidence.build, to: &writer)
    var records: [Data] = []
    records.reserveCapacity(evidence.observations.count)
    var totalRecordBytes = 0
    for observation in evidence.observations {
        let record = try paneShapeCanonicalObservationData(
            observation,
            maximumBytes: maximumBytes,
            budget: budget
        )
        guard totalRecordBytes <= maximumBytes - record.count else {
            throw PaneShapeCoverageError.canonicalDataTooLarge(maximumBytes: maximumBytes)
        }
        totalRecordBytes += record.count
        records.append(record)
    }
    try paneShapeSort(&records) { left, right in
        try paneShapeDataPrecedes(left, right, budget: budget)
    }
    try writer.append(count: records.count)
    for record in records {
        try writer.append(count: record.count)
        try writer.append(record)
    }
    return writer.data
}

private func paneShapeCanonicalObservationData(
    _ observation: PaneShapeProductionEvidence,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget? = nil
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append(observation.scenarioID.rawValue)
    try paneShapeAppend(observation.bindings, to: &writer)
    try writer.append(observation.layout.paneCount.rawValue)
    try paneShapeAppend(observation.layout.visualOrder, to: &writer)
    try writer.append(UInt8(paneShapePaneRank(observation.layout.activePane)))
    try writer.append(observation.layout.orientation.rawValue)
    try paneShapeAppend(observation.commandState.visualOrder, to: &writer)
    try writer.append(UInt8(paneShapePaneRank(observation.commandState.activePane)))
    try writer.append(paneShapeLifecycleRank(observation.comparisonPhase))
    try writer.append(observation.hasCurrentComparisonResult)
    try writer.append(observation.origin.rawValue)
    if let provenance = observation.provenance {
        try writer.append(true)
        try paneShapeAppend(provenance.build, to: &writer)
        try paneShapeAppend(provenance.inventory, to: &writer)
        try paneShapeAppend(provenance.collector, to: &writer)
        try writer.append(provenance.capturedAtUnixMilliseconds)
        try writer.append(count: provenance.runNonce.count)
        try writer.append(provenance.runNonce)
        try writer.append(count: provenance.artifactSHA256.count)
        try writer.append(provenance.artifactSHA256)
        try writer.append(count: provenance.captureSHA256.count)
        try writer.append(provenance.captureSHA256)
        try writer.append(count: provenance.collectorSignature.count)
        try writer.append(provenance.collectorSignature)
        try writer.append(provenance.source)
    } else {
        try writer.append(false)
    }
    return writer.data
}

private func paneShapeCanonicalCaptureData(
    _ observation: PaneShapeProductionEvidence,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget? = nil
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMPSCAP2")
    try writer.append(observation.scenarioID.rawValue)
    try paneShapeAppend(observation.bindings, to: &writer)
    try writer.append(observation.layout.paneCount.rawValue)
    try paneShapeAppend(observation.layout.visualOrder, to: &writer)
    try writer.append(UInt8(paneShapePaneRank(observation.layout.activePane)))
    try writer.append(observation.layout.orientation.rawValue)
    try paneShapeAppend(observation.commandState.visualOrder, to: &writer)
    try writer.append(UInt8(paneShapePaneRank(observation.commandState.activePane)))
    try writer.append(paneShapeLifecycleRank(observation.comparisonPhase))
    try writer.append(observation.hasCurrentComparisonResult)
    try writer.append(observation.origin.rawValue)
    if let provenance = observation.provenance {
        try writer.append(true)
        try paneShapeAppend(provenance.build, to: &writer)
        try paneShapeAppend(provenance.inventory, to: &writer)
        try paneShapeAppend(provenance.collector, to: &writer)
        try writer.append(provenance.capturedAtUnixMilliseconds)
        try writer.append(count: provenance.runNonce.count)
        try writer.append(provenance.runNonce)
        try writer.append(count: provenance.artifactSHA256.count)
        try writer.append(provenance.artifactSHA256)
        try writer.append(provenance.source)
    } else {
        try writer.append(false)
    }
    return writer.data
}

private func paneShapeCanonicalReportData(
    _ report: PaneShapeCoverageReport,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget? = nil
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMPSRPT5")
    try writer.append(UInt64(report.formatVersion))
    try paneShapeAppend(report.inventory, to: &writer)
    try paneShapeAppend(report.evidence, to: &writer)
    try writer.append(report.trustedAuditTimeUnixMilliseconds)
    try writer.append(report.maximumCaptureAgeMilliseconds)
    try writer.append(report.maximumFutureClockSkewMilliseconds)
    try writer.append(report.runNonceClaimDeadlineUnixMilliseconds)
    try paneShapeAppend(report.runNonceClaimPolicy, to: &writer)
    try writer.append(count: report.auditPolicySHA256.count)
    try writer.append(report.auditPolicySHA256)
    try writer.append(report.highestSeverity != nil)
    if let highestSeverity = report.highestSeverity {
        try writer.append(highestSeverity.rawValue)
    }
    try writer.append(report.containsErrors)
    try writer.append(report.isCompleteAndValid)
    try writer.append(count: report.matrix.requiredCount)
    try writer.append(count: report.matrix.completeCount)
    try writer.append(count: report.matrix.missingCount)
    try writer.append(count: report.matrix.duplicateCount)
    try writer.append(count: report.matrix.mismatchedCount)
    try writer.append(count: report.matrix.invalidCount)
    try writer.append(count: report.matrix.assertionOnlyCount)
    try writer.append(report.matrix.isComplete)
    try writer.append(count: report.matrix.cells.count)
    for cell in report.matrix.cells {
        try paneShapeAppend(cell.scenario, to: &writer)
        try paneShapeAppend(cell.expectedVisualOrder, to: &writer)
        try writer.append(UInt8(paneShapePaneRank(cell.expectedActivePane)))
        if let observedLayout = cell.observedLayout {
            try writer.append(true)
            try writer.append(observedLayout.paneCount.rawValue)
            try paneShapeAppend(observedLayout.visualOrder, to: &writer)
            try writer.append(UInt8(paneShapePaneRank(observedLayout.activePane)))
            try writer.append(observedLayout.orientation.rawValue)
        } else {
            try writer.append(false)
        }
        try writer.append(count: cell.evidenceCount)
        try writer.append(cell.status.rawValue)
    }
    try writer.append(count: report.findings.count)
    for finding in report.findings {
        try writer.append(finding.id.rawValue)
        try writer.append(finding.severity.rawValue)
        try writer.append(finding.code.rawValue)
        switch finding.subject {
        case .matrix:
            try writer.append(UInt8(0))
        case .scenario(let scenarioID):
            try writer.append(UInt8(1))
            try writer.append(scenarioID.rawValue)
        }
        try writer.append(finding.message)
    }
    return writer.data
}

private func paneShapeCanonicalScenarioData(
    _ scenario: PaneShapeScenario,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget? = nil
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append(scenario.paneCount.rawValue)
    try paneShapeAppend(scenario.expectedVisualOrder, to: &writer)
    try writer.append(UInt8(paneShapePaneRank(scenario.activePane)))
    try writer.append(scenario.orientation.rawValue)
    return writer.data
}

private func paneShapeCanonicalLayoutObservationData(
    _ observation: PaneShapeLayoutObservation,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget? = nil
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append(observation.paneCount.rawValue)
    try paneShapeAppend(observation.visualOrder, to: &writer)
    try writer.append(UInt8(paneShapePaneRank(observation.activePane)))
    try writer.append(observation.orientation.rawValue)
    return writer.data
}

private func paneShapeCanonicalComparisonBindingData(
    _ bindings: PaneShapeRevisionBindings,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget? = nil
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try paneShapeAppend(bindings.comparison.inputs, to: &writer)
    try paneShapeAppend(bindings.comparison.result, to: &writer)
    try paneShapeAppend(bindings.comparison.sources, to: &writer)
    return writer.data
}

private func paneShapeCanonicalSourceBindingsData(
    _ sources: [PaneShapeSourceRevisionBinding],
    maximumBytes: Int,
    budget: PaneShapeWorkBudget? = nil
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try paneShapeAppend(sources, to: &writer)
    return writer.data
}

private func paneShapeCanonicalRevisionContents(
    role: PaneShapeRevisionContentRole,
    contents: Data,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget? = nil
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMPSREV1")
    try writer.append(role.rawValue)
    try writer.append(count: contents.count)
    try writer.append(contents)
    return writer.data
}

private func paneShapeCanonicalAuditPolicyData(
    _ policy: PaneShapeAuditPolicy,
    maximumBytes: Int,
    budget: PaneShapeWorkBudget
) throws -> Data {
    var writer = PaneShapeCanonicalWriter(maximumBytes: maximumBytes, budget: budget)
    try writer.append("MMPSPOL3")
    try writer.append(policy.trustedAuditTimeUnixMilliseconds)
    try writer.append(policy.maximumCaptureAgeMilliseconds)
    try writer.append(policy.maximumFutureClockSkewMilliseconds)
    try writer.append(policy.runNonceClaimDeadlineUnixMilliseconds)
    try paneShapeAppend(policy.runNonceClaimPolicy, to: &writer)
    return writer.data
}

private func paneShapeAppend(
    _ scenario: PaneShapeScenario,
    to writer: inout PaneShapeCanonicalWriter
) throws {
    try writer.append(scenario.id.rawValue)
    try writer.append(scenario.paneCount.rawValue)
    try writer.append(UInt8(paneShapePaneRank(scenario.activePane)))
    try writer.append(scenario.isSwapped)
    try writer.append(scenario.orientation.rawValue)
}

private func paneShapeAppend(
    _ bindings: PaneShapeRevisionBindings,
    to writer: inout PaneShapeCanonicalWriter
) throws {
    try paneShapeAppend(bindings.layout, to: &writer)
    try paneShapeAppend(bindings.sources, to: &writer)
    try paneShapeAppend(bindings.comparison.comparison, to: &writer)
    try paneShapeAppend(bindings.comparison.inputs, to: &writer)
    try paneShapeAppend(bindings.comparison.result, to: &writer)
    try paneShapeAppend(bindings.comparison.sources, to: &writer)
}

private func paneShapeAppend(
    _ reference: PaneShapeRevisionReference,
    to writer: inout PaneShapeCanonicalWriter
) throws {
    try writer.append(reference.id.rawValue)
    try writer.append(reference.revision)
}

private func paneShapeAppend(
    _ sources: [PaneShapeSourceRevisionBinding],
    to writer: inout PaneShapeCanonicalWriter
) throws {
    try writer.append(count: sources.count)
    for source in sources {
        try writer.append(UInt8(paneShapePaneRank(source.pane)))
        try paneShapeAppend(source.source, to: &writer)
    }
}

private func paneShapeAppend(
    _ panes: [PaneIdentity],
    to writer: inout PaneShapeCanonicalWriter
) throws {
    try writer.append(count: panes.count)
    for pane in panes {
        try writer.append(UInt8(paneShapePaneRank(pane)))
    }
}

private func paneShapeCanonicalSources(
    _ sources: [PaneShapeSourceRevisionBinding]
) throws -> [PaneShapeSourceRevisionBinding] {
    guard sources.count == 2 || sources.count == 3 else {
        throw PaneShapeCoverageError.inconsistentRevisionBindings
    }
    let sorted = sources.sorted()
    let expected: [PaneIdentity] = sources.count == 2 ? [.left, .right] : [.left, .middle, .right]
    guard sorted.map(\.pane) == expected else {
        throw PaneShapeCoverageError.inconsistentRevisionBindings
    }
    return sorted
}

private func paneShapePane(_ side: ComparisonLifecycleState.Side) -> PaneIdentity {
    switch side {
    case .left: .left
    case .middle: .middle
    case .right: .right
    }
}

private func paneShapePaneRank(_ pane: PaneIdentity) -> Int {
    switch pane {
    case .left: 0
    case .middle: 1
    case .right: 2
    }
}

private func paneShapeLifecycleRank(_ phase: ComparisonLifecycleState.Phase) -> UInt8 {
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

private func paneShapeIsValidDigest(_ digest: [UInt8]) -> Bool {
    digest.count == SHA256.byteCount && digest.contains(where: { $0 != 0 })
}

private func paneShapeIsValidIdentifier(
    _ value: String,
    budget: PaneShapeWorkBudget
) throws -> Bool {
    guard !value.isEmpty else { return false }
    try budget.checkCancellation()
    guard value == value.precomposedStringWithCanonicalMapping else { return false }
    try budget.checkCancellation()
    for scalar in value.unicodeScalars {
        try budget.charge()
        guard !CharacterSet.controlCharacters.contains(scalar), !scalar.properties.isWhitespace else {
            return false
        }
    }
    return true
}

private func paneShapeIsValidSource(
    _ value: String,
    budget: PaneShapeWorkBudget
) throws -> Bool {
    guard !value.isEmpty else { return false }
    try budget.checkCancellation()
    guard value == value.precomposedStringWithCanonicalMapping else { return false }
    try budget.checkCancellation()
    var hasNonWhitespace = false
    for scalar in value.unicodeScalars {
        try budget.charge()
        guard !CharacterSet.controlCharacters.contains(scalar) || scalar.value == 0x09 else {
            return false
        }
        if !scalar.properties.isWhitespace { hasNonWhitespace = true }
    }
    return hasNonWhitespace
}

private func paneShapeIsValidEd25519Signature(
    _ signature: [UInt8],
    data: Data,
    publicKey: [UInt8],
    budget: PaneShapeWorkBudget
) throws -> Bool {
    try budget.charge(publicKey.count)
    try budget.charge(signature.count)
    try budget.charge(data.count)
    try budget.checkCancellation()
    let isValid: Bool
    do {
        isValid = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
            .isValidSignature(signature, for: data)
    } catch {
        isValid = false
    }
    try budget.checkCancellation()
    return isValid
}

private func paneShapeCompareUTF8(_ left: String, _ right: String) -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        switch (leftIterator.next(), rightIterator.next()) {
        case (let leftByte?, let rightByte?) where leftByte != rightByte:
            return leftByte < rightByte ? -1 : 1
        case (_?, _?):
            continue
        case (nil, nil):
            return 0
        case (nil, _?):
            return -1
        case (_?, nil):
            return 1
        }
    }
}

private func paneShapeDataPrecedes(
    _ left: Data,
    _ right: Data,
    budget: PaneShapeWorkBudget
) throws -> Bool {
    var leftIterator = left.makeIterator()
    var rightIterator = right.makeIterator()
    while true {
        try budget.charge()
        switch (leftIterator.next(), rightIterator.next()) {
        case (let leftByte?, let rightByte?) where leftByte != rightByte:
            return leftByte < rightByte
        case (_?, _?):
            continue
        case (nil, nil), (_?, nil):
            return false
        case (nil, _?):
            return true
        }
    }
}

private func paneShapeDataEqual(
    _ left: Data,
    _ right: Data,
    budget: PaneShapeWorkBudget
) throws -> Bool {
    guard left.count == right.count else {
        try budget.charge()
        return false
    }
    var leftIndex = left.startIndex
    var rightIndex = right.startIndex
    while leftIndex != left.endIndex {
        try budget.charge()
        guard left[leftIndex] == right[rightIndex] else { return false }
        left.formIndex(after: &leftIndex)
        right.formIndex(after: &rightIndex)
    }
    return true
}

private func paneShapeRevisionReferencesEqual(
    _ left: PaneShapeRevisionReference,
    _ right: PaneShapeRevisionReference,
    budget: PaneShapeWorkBudget
) throws -> Bool {
    try budget.charge()
    guard left.revision == right.revision else { return false }
    return try paneShapeStringsEqual(left.id.rawValue, right.id.rawValue, budget: budget)
}

private func paneShapeSourceBindingsEqual(
    _ left: [PaneShapeSourceRevisionBinding],
    _ right: [PaneShapeSourceRevisionBinding],
    budget: PaneShapeWorkBudget
) throws -> Bool {
    guard left.count == right.count else {
        try budget.charge()
        return false
    }
    for (leftBinding, rightBinding) in zip(left, right) {
        try budget.charge()
        guard leftBinding.pane == rightBinding.pane,
            try paneShapeRevisionReferencesEqual(
                leftBinding.source,
                rightBinding.source,
                budget: budget
            )
        else { return false }
    }
    return true
}

private func paneShapeComparisonBindingsEqual(
    _ left: PaneShapeComparisonRevisionBinding,
    _ right: PaneShapeComparisonRevisionBinding,
    budget: PaneShapeWorkBudget
) throws -> Bool {
    guard
        try paneShapeRevisionReferencesEqual(
            left.comparison,
            right.comparison,
            budget: budget
        ),
        try paneShapeRevisionReferencesEqual(left.inputs, right.inputs, budget: budget),
        try paneShapeRevisionReferencesEqual(left.result, right.result, budget: budget)
    else { return false }
    return try paneShapeSourceBindingsEqual(left.sources, right.sources, budget: budget)
}

private func paneShapeCoverageReceiptsEqual(
    _ left: PaneShapeCoverageReceipt,
    _ right: PaneShapeCoverageReceipt,
    budget: PaneShapeWorkBudget
) throws -> Bool {
    try budget.charge()
    guard left.formatVersion == right.formatVersion,
        try paneShapeRevisionReferencesEqual(left.build, right.build, budget: budget),
        try paneShapeRevisionReferencesEqual(left.inventory, right.inventory, budget: budget),
        try paneShapeRevisionReferencesEqual(left.evidence, right.evidence, budget: budget),
        try paneShapeBytesEqual(left.inventorySHA256, right.inventorySHA256, budget: budget),
        try paneShapeBytesEqual(left.evidenceSHA256, right.evidenceSHA256, budget: budget),
        try paneShapeBytesEqual(left.reportSHA256, right.reportSHA256, budget: budget),
        try paneShapeBytesEqual(left.auditPolicySHA256, right.auditPolicySHA256, budget: budget),
        left.runNonceClaimStatus == right.runNonceClaimStatus
    else { return false }
    try budget.charge()
    return left.requiredScenarioCount == right.requiredScenarioCount
        && left.completeScenarioCount == right.completeScenarioCount
        && left.findingCount == right.findingCount
}

private func paneShapeBytesEqual(
    _ left: [UInt8],
    _ right: [UInt8],
    budget: PaneShapeWorkBudget
) throws -> Bool {
    guard left.count == right.count else {
        try budget.charge()
        return false
    }
    for (leftByte, rightByte) in zip(left, right) {
        try budget.charge()
        guard leftByte == rightByte else { return false }
    }
    return true
}

private func paneShapeStringsEqual(
    _ left: String,
    _ right: String,
    budget: PaneShapeWorkBudget
) throws -> Bool {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        try budget.charge()
        switch (leftIterator.next(), rightIterator.next()) {
        case (let leftByte?, let rightByte?):
            guard leftByte == rightByte else { return false }
        case (nil, nil):
            return true
        case (nil, _?), (_?, nil):
            return false
        }
    }
}

private func paneShapeSHA256(
    _ data: Data,
    budget: PaneShapeWorkBudget
) throws -> [UInt8] {
    var hasher = SHA256()
    var offset = data.startIndex
    let chunkSize = 4_096
    while offset != data.endIndex {
        let end =
            data.index(offset, offsetBy: chunkSize, limitedBy: data.endIndex)
            ?? data.endIndex
        try budget.charge(data.distance(from: offset, to: end))
        hasher.update(data: data[offset..<end])
        offset = end
    }
    try budget.checkCancellation()
    return Array(hasher.finalize())
}

private func paneShapeSort<Element>(
    _ elements: inout [Element],
    precedes: (Element, Element) throws -> Bool
) throws {
    guard elements.count > 1 else { return }
    for index in elements.indices.dropFirst() {
        var insertionIndex = index
        while insertionIndex > elements.startIndex,
            try precedes(elements[insertionIndex], elements[insertionIndex - 1])
        {
            elements.swapAt(insertionIndex, insertionIndex - 1)
            insertionIndex -= 1
        }
    }
}

private func paneShapeFrame(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
}

private func paneShapeFindingMessage(_ code: PaneShapeFindingCode) -> String {
    switch code {
    case .duplicateScenarioEvidence:
        "Pane-shape scenario has duplicate evidence."
    case .missingScenarioEvidence:
        "Pane-shape scenario has no production evidence."
    case .unexpectedScenarioEvidence:
        "Evidence targets a scenario outside the canonical matrix."
    case .layoutRevisionMismatch:
        "Observed layout revision does not match the required binding."
    case .sourceRevisionMismatch:
        "Observed source revisions do not match the required bindings."
    case .comparisonRevisionMismatch:
        "Observed comparison revision does not match the required binding."
    case .paneCountMismatch:
        "Observed pane count does not match the canonical scenario."
    case .visualOrderMismatch:
        "Observed logical-to-visual mapping does not match the canonical scenario."
    case .activePaneMismatch:
        "Observed active pane does not match the canonical scenario."
    case .orientationMismatch:
        "Observed orientation does not match the canonical scenario."
    case .commandVisualOrderMismatch:
        "Shared command state uses another logical-to-visual mapping."
    case .commandActivePaneMismatch:
        "Shared command state uses another active pane."
    case .comparisonLifecycleMismatch:
        "Evidence is not bound to a current comparison lifecycle result."
    case .productionProvenanceMissing:
        "Production evidence is missing capture provenance."
    case .productionProvenanceInvalid:
        "Production evidence has invalid capture provenance; details are redacted."
    case .provenanceBuildMismatch:
        "Production provenance is bound to another build revision."
    case .provenanceInventoryMismatch:
        "Production provenance is bound to another inventory revision."
    case .provenanceArtifactMismatch:
        "Production provenance is bound to another build artifact."
    case .untrustedCollector:
        "Production evidence was not emitted by an inventory-trusted collector."
    case .productionCaptureExpired:
        "Production capture exceeds the trusted maximum age."
    case .productionCaptureFutureDated:
        "Production capture exceeds the trusted future clock-skew allowance."
    case .productionNonceReplay:
        "Production capture reuses a previously accepted run nonce."
    case .productionCaptureMismatch:
        "Resolved production capture does not match its canonical observation and digest."
    case .assertionOnlyEvidence:
        "Caller assertion cannot count as production proof."
    }
}
