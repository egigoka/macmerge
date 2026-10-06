import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// Revisioned layout contents used by toolbar presentation evidence.
public struct ToolbarPresentationLayout: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: AccessibilityEvidenceRevisionReference
    public let configurationReference: ToolbarCustomizationWorkflow.ConfigurationReference
    public let configuration: ToolbarConfiguration
    public let manifestRevision: ToolbarAuditRevision

    public init(
        reference: AccessibilityEvidenceRevisionReference,
        configurationReference: ToolbarCustomizationWorkflow.ConfigurationReference,
        configuration: ToolbarConfiguration,
        manifestRevision: ToolbarAuditRevision
    ) {
        self.reference = reference
        self.configurationReference = configurationReference
        self.configuration = configuration
        self.manifestRevision = manifestRevision
    }

    public var items: [ToolbarAuditItem] { configuration.items }

    public var description: String {
        "ToolbarPresentationLayout(items: \(configuration.items.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "reference": reference,
                "configurationReference": configurationReference,
                "itemCount": configuration.items.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Primary toolbar availability derived from shared command policy in stable command order.
public struct ToolbarPresentationCommandState: Equatable, Hashable, Sendable {
    public struct Binding: Equatable, Hashable, Sendable {
        public let command: ComparisonCommandState.Identifier
        public let isEnabled: Bool

        fileprivate init(command: ComparisonCommandState.Identifier, isEnabled: Bool) {
            self.command = command
            self.isEnabled = isEnabled
        }
    }

    public let bindings: [Binding]

    fileprivate init(context: ComparisonCommandState.Context) {
        bindings = ComparisonCommandState.Identifier.allCases.map { command in
            Binding(
                command: command,
                isEnabled: ComparisonCommandState.resolve(command, in: context).isEnabled
            )
        }
    }

    public func binding(for command: ComparisonCommandState.Identifier) -> Binding? {
        bindings.first { $0.command == command }
    }
}

/// Maps every primary and secondary toolbar action to shared command semantics.
public struct ToolbarPresentationSemanticActionBinding: Equatable, Hashable, Sendable {
    public let actionID: ToolbarAuditStableID
    public let command: ComparisonCommandState.Identifier

    public init(actionID: ToolbarAuditStableID, command: ComparisonCommandState.Identifier) {
        self.actionID = actionID
        self.command = command
    }
}

public struct ToolbarPresentationLifecycleRequirement: Equatable, Hashable, Sendable {
    public let scenario: ToolbarAuditLifecycleScenario
    public let reference: AccessibilityEvidenceRevisionReference
    /// Authoritative semantic input for this lifecycle row. Enabled state is resolved through
    /// `ComparisonCommandState`; the audit contract cannot declare a conflicting primary state.
    public let commandState: ToolbarPresentationCommandState

    public init(
        scenario: ToolbarAuditLifecycleScenario,
        reference: AccessibilityEvidenceRevisionReference,
        commandState: ComparisonCommandState.Context
    ) {
        self.scenario = scenario
        self.reference = reference
        self.commandState = ToolbarPresentationCommandState(context: commandState)
    }
}

public struct ToolbarPresentationWindowRequirement: Equatable, Hashable, Sendable {
    public let context: ToolbarAuditScreenshotContext
    public let reference: AccessibilityEvidenceRevisionReference
    public let lifecycleScenario: ToolbarAuditLifecycleScenario

    public init(
        context: ToolbarAuditScreenshotContext,
        reference: AccessibilityEvidenceRevisionReference,
        lifecycleScenario: ToolbarAuditLifecycleScenario
    ) {
        self.context = context
        self.reference = reference
        self.lifecycleScenario = lifecycleScenario
    }
}

/// Exact production requirement set. Text remains explicit caller input from the WinMerge audit.
public struct ToolbarPresentationEvidenceInventory: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let app: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let buildBinding: AccessibilityEvidenceBuildBinding
    public let reference: AccessibilityEvidenceRevisionReference
    public let manifestReference: AccessibilityEvidenceRevisionReference
    public let layout: ToolbarPresentationLayout
    public let auditContract: ToolbarAuditContract
    public let semanticActionBindings: [ToolbarPresentationSemanticActionBinding]
    public let lifecycleRequirements: [ToolbarPresentationLifecycleRequirement]
    public let windowRequirements: [ToolbarPresentationWindowRequirement]

    public init(
        app: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        buildBinding: AccessibilityEvidenceBuildBinding,
        reference: AccessibilityEvidenceRevisionReference,
        manifestReference: AccessibilityEvidenceRevisionReference,
        layout: ToolbarPresentationLayout,
        auditContract: ToolbarAuditContract,
        semanticActionBindings: [ToolbarPresentationSemanticActionBinding],
        lifecycleRequirements: [ToolbarPresentationLifecycleRequirement],
        windowRequirements: [ToolbarPresentationWindowRequirement]
    ) {
        self.app = app
        self.build = build
        self.buildBinding = buildBinding
        self.reference = reference
        self.manifestReference = manifestReference
        self.layout = layout
        self.auditContract = auditContract
        self.semanticActionBindings = semanticActionBindings
        self.lifecycleRequirements = lifecycleRequirements
        self.windowRequirements = windowRequirements
    }

    public var description: String {
        "ToolbarPresentationEvidenceInventory(controls: \(auditContract.controls.count), scenarios: \(lifecycleRequirements.count + windowRequirements.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "app": app,
                "build": build,
                "reference": reference,
                "manifestReference": manifestReference,
                "layoutReference": layout.reference,
                "controlCount": auditContract.controls.count,
                "semanticActionBindingCount": semanticActionBindings.count,
                "lifecycleScenarioCount": lifecycleRequirements.count,
                "windowScenarioCount": windowRequirements.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum ToolbarPresentationEvidenceAttachmentKind: String, CaseIterable, Hashable, Sendable {
    case screenshot
    case accessibilitySnapshot
}

public struct ToolbarPresentationEvidenceRect: Equatable, Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ToolbarPresentationCaptureGeometry: Equatable, Hashable, Sendable {
    public let window: ToolbarPresentationEvidenceRect
    public let toolbar: ToolbarPresentationEvidenceRect
    /// Display scale multiplied by 1,000.
    public let backingScaleThousandths: Int

    public init(
        window: ToolbarPresentationEvidenceRect,
        toolbar: ToolbarPresentationEvidenceRect,
        backingScaleThousandths: Int
    ) {
        self.window = window
        self.toolbar = toolbar
        self.backingScaleThousandths = backingScaleThousandths
    }
}

public struct ToolbarPresentationCapturedWindowState: Equatable, Hashable, Sendable {
    public let isVisible: Bool
    public let isKeyWindow: Bool
    public let isMainWindow: Bool
    public let isMiniaturized: Bool
    public let isFullScreen: Bool

    public init(
        isVisible: Bool,
        isKeyWindow: Bool,
        isMainWindow: Bool,
        isMiniaturized: Bool,
        isFullScreen: Bool
    ) {
        self.isVisible = isVisible
        self.isKeyWindow = isKeyWindow
        self.isMainWindow = isMainWindow
        self.isMiniaturized = isMiniaturized
        self.isFullScreen = isFullScreen
    }
}

public enum ToolbarPresentationCaptureContext: Equatable, Hashable, Sendable {
    case lifecycle(ToolbarAuditLifecycleScenario)
    case window(ToolbarAuditScreenshotContext, lifecycle: ToolbarAuditLifecycleScenario)
}

/// One node from collector's complete toolbar AX subtree. `elementIdentity` is runtime identity,
/// distinct from app-provided accessibility identifier.
public struct ToolbarPresentationAXElementObservation: Equatable, Hashable, Sendable {
    public let elementIdentity: AccessibilityStableID
    public let parentIdentity: AccessibilityStableID?
    /// Zero-based position among the parent's AX children.
    public let siblingIndex: Int
    public let frame: ToolbarPresentationEvidenceRect
    public let accessibility: ToolbarAuditAXMetadata

    public init(
        elementIdentity: AccessibilityStableID,
        parentIdentity: AccessibilityStableID?,
        siblingIndex: Int,
        frame: ToolbarPresentationEvidenceRect,
        accessibility: ToolbarAuditAXMetadata
    ) {
        self.elementIdentity = elementIdentity
        self.parentIdentity = parentIdentity
        self.siblingIndex = siblingIndex
        self.frame = frame
        self.accessibility = accessibility
    }
}

public enum ToolbarPresentationFocusTraversal: String, CaseIterable, Hashable, Sendable {
    case tabForward
    case tabBackward
    case menuNext
    case menuPrevious
}

/// Observed focus transition. Both identities are required so focusability cannot be asserted
/// without proving movement to one exact runtime AX element.
public struct ToolbarPresentationFocusMovement: Equatable, Hashable, Sendable {
    public let controlID: ToolbarAuditStableID
    public let fromElementIdentity: AccessibilityStableID
    public let toElementIdentity: AccessibilityStableID
    public let traversal: ToolbarPresentationFocusTraversal

    public init(
        controlID: ToolbarAuditStableID,
        fromElementIdentity: AccessibilityStableID,
        toElementIdentity: AccessibilityStableID,
        traversal: ToolbarPresentationFocusTraversal
    ) {
        self.controlID = controlID
        self.fromElementIdentity = fromElementIdentity
        self.toElementIdentity = toElementIdentity
        self.traversal = traversal
    }
}

/// Measured interaction result included in signed capture state.
public struct ToolbarPresentationInteractionCapture: Equatable, Hashable, Sendable {
    public let scenario: ToolbarAuditLifecycleScenario
    public let controlID: ToolbarAuditStableID
    /// Runtime AX identity of the exact control that received the invocation.
    public let elementIdentity: AccessibilityStableID
    public let actionID: ToolbarAuditStableID
    public let invocation: ToolbarAuditInvocationKind
    public let outcome: ToolbarAuditInteractionOutcome
    public let source: String

    public init(
        scenario: ToolbarAuditLifecycleScenario,
        controlID: ToolbarAuditStableID,
        elementIdentity: AccessibilityStableID,
        actionID: ToolbarAuditStableID,
        invocation: ToolbarAuditInvocationKind,
        outcome: ToolbarAuditInteractionOutcome,
        source: String
    ) {
        self.scenario = scenario
        self.controlID = controlID
        self.elementIdentity = elementIdentity
        self.actionID = actionID
        self.invocation = invocation
        self.outcome = outcome
        self.source = source
    }
}

/// Collector-authenticated manifest for one exact capture. Authentication is verified over
/// canonical bytes for every field except `authentication` itself.
public struct ToolbarPresentationCaptureManifest: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let formatVersion: Int
    public let collector: AccessibilityEvidenceRevisionReference
    public let capture: AccessibilityEvidenceRevisionReference
    public let origin: AccessibilityEvidenceOrigin
    public let app: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let buildBinding: AccessibilityEvidenceBuildBinding
    public let inventory: AccessibilityEvidenceRevisionReference
    public let manifest: AccessibilityEvidenceRevisionReference
    public let layout: AccessibilityEvidenceRevisionReference
    public let configuration: ToolbarCustomizationWorkflow.ConfigurationReference
    public let contractRevision: ToolbarAuditRevision
    public let manifestRevision: ToolbarAuditRevision
    public let context: ToolbarPresentationCaptureContext
    public let geometry: ToolbarPresentationCaptureGeometry
    public let windowState: ToolbarPresentationCapturedWindowState
    public let stateSHA256: [UInt8]
    public let accessibilityTreeSHA256: [UInt8]
    public let screenshotPixelSHA256: [UInt8]?
    public let accessibilityTreeIsComplete: Bool
    /// Stable verifier-approved decoder, color-management, and renderer implementation.
    public let renderingPipeline: AccessibilityEvidenceRevisionReference
    public let renderingImplementation: String
    /// Canonical screenshot attachment metadata, authenticated with this manifest.
    public let screenshotAttachmentID: AccessibilityStableID?
    public let screenshotMediaType: String?
    public let screenshotSource: String?
    public let screenshotEncodedSHA256: [UInt8]?
    public let authentication: [UInt8]

    public init(
        formatVersion: Int = 4,
        collector: AccessibilityEvidenceRevisionReference,
        capture: AccessibilityEvidenceRevisionReference,
        origin: AccessibilityEvidenceOrigin,
        app: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        buildBinding: AccessibilityEvidenceBuildBinding,
        inventory: AccessibilityEvidenceRevisionReference,
        manifest: AccessibilityEvidenceRevisionReference,
        layout: AccessibilityEvidenceRevisionReference,
        configuration: ToolbarCustomizationWorkflow.ConfigurationReference,
        contractRevision: ToolbarAuditRevision,
        manifestRevision: ToolbarAuditRevision,
        context: ToolbarPresentationCaptureContext,
        geometry: ToolbarPresentationCaptureGeometry,
        windowState: ToolbarPresentationCapturedWindowState,
        stateSHA256: [UInt8],
        accessibilityTreeSHA256: [UInt8],
        screenshotPixelSHA256: [UInt8]?,
        accessibilityTreeIsComplete: Bool,
        renderingPipeline: AccessibilityEvidenceRevisionReference,
        renderingImplementation: String = ToolbarPresentationEvidenceWorkflow
            .canonicalRenderingImplementation,
        screenshotAttachmentID: AccessibilityStableID? = nil,
        screenshotMediaType: String? = nil,
        screenshotSource: String? = nil,
        screenshotEncodedSHA256: [UInt8]? = nil,
        authentication: [UInt8]
    ) {
        self.formatVersion = formatVersion
        self.collector = collector
        self.capture = capture
        self.origin = origin
        self.app = app
        self.build = build
        self.buildBinding = buildBinding
        self.inventory = inventory
        self.manifest = manifest
        self.layout = layout
        self.configuration = configuration
        self.contractRevision = contractRevision
        self.manifestRevision = manifestRevision
        self.context = context
        self.geometry = geometry
        self.windowState = windowState
        self.stateSHA256 = stateSHA256
        self.accessibilityTreeSHA256 = accessibilityTreeSHA256
        self.screenshotPixelSHA256 = screenshotPixelSHA256
        self.accessibilityTreeIsComplete = accessibilityTreeIsComplete
        self.renderingPipeline = renderingPipeline
        self.renderingImplementation = renderingImplementation
        self.screenshotAttachmentID = screenshotAttachmentID
        self.screenshotMediaType = screenshotMediaType
        self.screenshotSource = screenshotSource
        self.screenshotEncodedSHA256 = screenshotEncodedSHA256
        self.authentication = authentication
    }

    public var description: String {
        "ToolbarPresentationCaptureManifest(context: \(context), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "formatVersion": formatVersion,
                "collector": collector,
                "capture": capture,
                "context": context,
                "renderingPipeline": renderingPipeline,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum ToolbarPresentationEvidenceAttachmentResolutionError: Error, Equatable, Sendable {
    case exceedsDeclaredByteCount
    case chunkTooLarge(maximumBytes: Int)
}

/// Bounded payload writer. Resolver appends chunks; writer rejects bytes beyond declaration before
/// retaining them. This bounds sink retention, not allocations made independently by resolver.
public struct ToolbarPresentationEvidenceAttachmentSink: ~Copyable, Sendable {
    private let declaredByteCount: Int
    private let maximumChunkBytes: Int
    private let budget: ToolbarPresentationWorkBudget
    private var data: Data
    private var appendedByteCount = 0
    private var retainedByteCharge = 0

    fileprivate init(
        declaredByteCount: Int,
        maximumChunkBytes: Int,
        budget: ToolbarPresentationWorkBudget
    ) {
        self.declaredByteCount = declaredByteCount
        self.maximumChunkBytes = maximumChunkBytes
        self.budget = budget
        data = Data()
    }

    public mutating func append(_ bytes: Data) throws {
        try checkpoint()
        guard bytes.count <= maximumChunkBytes else {
            throw ToolbarPresentationEvidenceAttachmentResolutionError.chunkTooLarge(
                maximumBytes: maximumChunkBytes
            )
        }
        guard appendedByteCount <= declaredByteCount,
            bytes.count <= declaredByteCount - appendedByteCount
        else {
            throw ToolbarPresentationEvidenceAttachmentResolutionError.exceedsDeclaredByteCount
        }
        try budget.consumeMemory(UInt64(bytes.count))
        retainedByteCharge += bytes.count
        try budget.consume(UInt64(bytes.count))
        appendedByteCount += bytes.count
        bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            data.append(baseAddress.assumingMemoryBound(to: UInt8.self), count: buffer.count)
        }
        try checkpoint()
    }

    /// Cooperative checkpoint for resolver work performed between bounded `append` calls.
    /// Work that does not call `append` or `checkpoint` cannot be metered or preempted here.
    public func checkpoint(workUnits: UInt64 = 1) throws {
        try budget.consume(workUnits)
        try budget.checkCancellation()
    }

    fileprivate var resolvedData: Data { data }

    fileprivate mutating func releaseRetainedByteCharge() {
        budget.releaseMemory(UInt64(retainedByteCharge))
        retainedByteCharge = 0
    }
}

/// Caller-owned payload metadata, bound to one exact capture and verified through the resolver.
public struct ToolbarPresentationEvidenceAttachment: Identifiable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let id: AccessibilityStableID
    public let kind: ToolbarPresentationEvidenceAttachmentKind
    public let scenario: AccessibilityEvidenceRevisionReference
    public let manifest: AccessibilityEvidenceRevisionReference
    public let layout: AccessibilityEvidenceRevisionReference
    public let provenance: AccessibilityEvidenceCaptureProvenance
    public let mediaType: String
    public let byteCount: Int
    /// SHA-256 of resolver bytes. For screenshots, metadata-bearing source bytes remain distinct
    /// from canonical rendered content.
    public let sha256: [UInt8]
    /// SHA-256 of canonical AX bytes or normalized sRGB premultiplied RGBA bytes.
    public let contentSHA256: [UInt8]
    /// SHA-256 of authenticated capture manifest, including authentication bytes.
    public let captureManifestSHA256: [UInt8]
    public let source: String

    public init(
        id: AccessibilityStableID,
        kind: ToolbarPresentationEvidenceAttachmentKind,
        scenario: AccessibilityEvidenceRevisionReference,
        manifest: AccessibilityEvidenceRevisionReference,
        layout: AccessibilityEvidenceRevisionReference,
        provenance: AccessibilityEvidenceCaptureProvenance,
        mediaType: String,
        byteCount: Int,
        sha256: [UInt8],
        contentSHA256: [UInt8],
        captureManifestSHA256: [UInt8],
        source: String
    ) {
        self.id = id
        self.kind = kind
        self.scenario = scenario
        self.manifest = manifest
        self.layout = layout
        self.provenance = provenance
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.contentSHA256 = contentSHA256
        self.captureManifestSHA256 = captureManifestSHA256
        self.source = source
    }

    public var description: String {
        "ToolbarPresentationEvidenceAttachment(kind: \(kind.rawValue), bytes: \(byteCount), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "id": id,
                "kind": kind,
                "scenario": scenario,
                "byteCount": byteCount,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// AX measurement for one lifecycle matrix row.
public struct ToolbarPresentationLifecycleCapture: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let scenario: ToolbarAuditLifecycleScenario
    public let reference: AccessibilityEvidenceRevisionReference
    public let manifest: AccessibilityEvidenceRevisionReference
    public let layout: AccessibilityEvidenceRevisionReference
    public let provenance: AccessibilityEvidenceCaptureProvenance
    public let origin: AccessibilityEvidenceOrigin
    public let items: [ToolbarAuditItem]
    public let controls: [ToolbarAuditControlObservation]
    public let interactions: [ToolbarPresentationInteractionCapture]
    public let accessibilityTree: [ToolbarPresentationAXElementObservation]
    public let focusMovements: [ToolbarPresentationFocusMovement]
    public let captureManifest: ToolbarPresentationCaptureManifest
    public let accessibilityAttachmentID: AccessibilityStableID
    public let source: String

    public init(
        scenario: ToolbarAuditLifecycleScenario,
        reference: AccessibilityEvidenceRevisionReference,
        manifest: AccessibilityEvidenceRevisionReference,
        layout: AccessibilityEvidenceRevisionReference,
        provenance: AccessibilityEvidenceCaptureProvenance,
        origin: AccessibilityEvidenceOrigin,
        items: [ToolbarAuditItem],
        controls: [ToolbarAuditControlObservation],
        interactions: [ToolbarPresentationInteractionCapture],
        accessibilityTree: [ToolbarPresentationAXElementObservation],
        focusMovements: [ToolbarPresentationFocusMovement],
        captureManifest: ToolbarPresentationCaptureManifest,
        accessibilityAttachmentID: AccessibilityStableID,
        source: String
    ) {
        self.scenario = scenario
        self.reference = reference
        self.manifest = manifest
        self.layout = layout
        self.provenance = provenance
        self.origin = origin
        self.items = items
        self.controls = controls
        self.interactions = interactions
        self.accessibilityTree = accessibilityTree
        self.focusMovements = focusMovements
        self.captureManifest = captureManifest
        self.accessibilityAttachmentID = accessibilityAttachmentID
        self.source = source
    }

    public var description: String {
        "ToolbarPresentationLifecycleCapture(scenario: \(scenario.rawValue), controls: \(controls.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "scenario": scenario,
                "reference": reference,
                "origin": origin,
                "controlCount": controls.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Screenshot and AX measurement for a fresh or loaded production window.
public struct ToolbarPresentationWindowCapture: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let context: ToolbarAuditScreenshotContext
    public let reference: AccessibilityEvidenceRevisionReference
    public let lifecycleScenario: ToolbarAuditLifecycleScenario
    public let manifest: AccessibilityEvidenceRevisionReference
    public let layout: AccessibilityEvidenceRevisionReference
    public let provenance: AccessibilityEvidenceCaptureProvenance
    public let origin: AccessibilityEvidenceOrigin
    public let items: [ToolbarAuditItem]
    public let controls: [ToolbarAuditControlObservation]
    public let interactions: [ToolbarPresentationInteractionCapture]
    public let accessibilityTree: [ToolbarPresentationAXElementObservation]
    public let focusMovements: [ToolbarPresentationFocusMovement]
    public let captureManifest: ToolbarPresentationCaptureManifest
    public let screenshotAttachmentID: AccessibilityStableID
    public let accessibilityAttachmentID: AccessibilityStableID
    public let source: String

    public init(
        context: ToolbarAuditScreenshotContext,
        reference: AccessibilityEvidenceRevisionReference,
        lifecycleScenario: ToolbarAuditLifecycleScenario,
        manifest: AccessibilityEvidenceRevisionReference,
        layout: AccessibilityEvidenceRevisionReference,
        provenance: AccessibilityEvidenceCaptureProvenance,
        origin: AccessibilityEvidenceOrigin,
        items: [ToolbarAuditItem],
        controls: [ToolbarAuditControlObservation],
        interactions: [ToolbarPresentationInteractionCapture],
        accessibilityTree: [ToolbarPresentationAXElementObservation],
        focusMovements: [ToolbarPresentationFocusMovement],
        captureManifest: ToolbarPresentationCaptureManifest,
        screenshotAttachmentID: AccessibilityStableID,
        accessibilityAttachmentID: AccessibilityStableID,
        source: String
    ) {
        self.context = context
        self.reference = reference
        self.lifecycleScenario = lifecycleScenario
        self.manifest = manifest
        self.layout = layout
        self.provenance = provenance
        self.origin = origin
        self.items = items
        self.controls = controls
        self.interactions = interactions
        self.accessibilityTree = accessibilityTree
        self.focusMovements = focusMovements
        self.captureManifest = captureManifest
        self.screenshotAttachmentID = screenshotAttachmentID
        self.accessibilityAttachmentID = accessibilityAttachmentID
        self.source = source
    }

    public var description: String {
        "ToolbarPresentationWindowCapture(context: \(context.rawValue), controls: \(controls.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "context": context,
                "reference": reference,
                "lifecycleScenario": lifecycleScenario,
                "origin": origin,
                "controlCount": controls.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Caller-supplied values only. This type performs no capture, UI, AX, or filesystem work.
public struct ToolbarPresentationEvidenceBundle: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let reference: AccessibilityEvidenceRevisionReference
    public let app: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let buildBinding: AccessibilityEvidenceBuildBinding
    public let inventory: AccessibilityEvidenceRevisionReference
    public let manifest: AccessibilityEvidenceRevisionReference
    public let layout: AccessibilityEvidenceRevisionReference
    public let lifecycleCaptures: [ToolbarPresentationLifecycleCapture]
    public let windowCaptures: [ToolbarPresentationWindowCapture]
    public let attachments: [ToolbarPresentationEvidenceAttachment]

    public init(
        reference: AccessibilityEvidenceRevisionReference,
        app: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        buildBinding: AccessibilityEvidenceBuildBinding,
        inventory: AccessibilityEvidenceRevisionReference,
        manifest: AccessibilityEvidenceRevisionReference,
        layout: AccessibilityEvidenceRevisionReference,
        lifecycleCaptures: [ToolbarPresentationLifecycleCapture],
        windowCaptures: [ToolbarPresentationWindowCapture],
        attachments: [ToolbarPresentationEvidenceAttachment]
    ) {
        self.reference = reference
        self.app = app
        self.build = build
        self.buildBinding = buildBinding
        self.inventory = inventory
        self.manifest = manifest
        self.layout = layout
        self.lifecycleCaptures = lifecycleCaptures
        self.windowCaptures = windowCaptures
        self.attachments = attachments
    }

    public var description: String {
        "ToolbarPresentationEvidenceBundle(lifecycleCaptures: \(lifecycleCaptures.count), windowCaptures: \(windowCaptures.count), attachments: \(attachments.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "reference": reference,
                "app": app,
                "build": build,
                "inventory": inventory,
                "manifest": manifest,
                "layout": layout,
                "lifecycleCaptureCount": lifecycleCaptures.count,
                "windowCaptureCount": windowCaptures.count,
                "attachmentCount": attachments.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum ToolbarPresentationEvidenceLimit: String, CaseIterable, Hashable, Sendable {
    case lifecycleCaptures
    case windowCaptures
    case controls
    case secondaryActions
    case interactions
    case accessibilityElements
    case focusMovements
    case attachments
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case attachmentBytes
    case attachmentChunkBytes
    case totalAttachmentBytes
    case aggregateMemoryBytes
    case archiveBytes
    case workUnits
    case findings
    case cancellationCheckInterval
}

public struct ToolbarPresentationEvidenceLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumCaptureCount = 1_024
    public static let hardMaximumControlCount = 4_096
    public static let hardMaximumInteractionCount = ToolbarAuditLimits.hardMaximumInteractionRecords
    public static let hardMaximumAccessibilityElementCount = 65_536
    public static let hardMaximumFocusMovementCount = 65_536
    public static let hardMaximumSecondaryActionCount = ToolbarAuditLimits.hardMaximumSecondaryActions
    public static let hardMaximumAttachmentCount = 4_096
    public static let hardMaximumStringUTF8Bytes = 1 * 1_024 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 64 * 1_024 * 1_024
    public static let hardMaximumAttachmentBytes = 1 * 1_024 * 1_024 * 1_024
    public static let hardMaximumAttachmentChunkBytes = 4 * 1_024 * 1_024
    public static let hardMaximumTotalAttachmentBytes: UInt64 = 1 << 40
    public static let hardMaximumAggregateMemoryBytes: UInt64 = 1 << 40
    public static let hardMaximumArchiveBytes = 256 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 40
    public static let hardMaximumFindingCount = 100_000
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = ToolbarPresentationEvidenceLimits()

    public let maximumLifecycleCaptures: Int
    public let maximumWindowCaptures: Int
    public let maximumControlsPerCapture: Int
    public let maximumSecondaryActionsPerCapture: Int
    public let maximumInteractionsPerCapture: Int
    public let maximumAccessibilityElementsPerCapture: Int
    public let maximumFocusMovementsPerCapture: Int
    public let maximumAttachments: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumAttachmentBytes: Int
    public let maximumAttachmentChunkBytes: Int
    public let maximumTotalAttachmentBytes: UInt64
    public let maximumAggregateMemoryBytes: UInt64
    public let maximumArchiveBytes: Int
    public let maximumWorkUnits: UInt64
    public let maximumFindings: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumLifecycleCaptures: Int = 32,
        maximumWindowCaptures: Int = 8,
        maximumControlsPerCapture: Int = ToolbarConfiguration.Command.allCases.count,
        maximumSecondaryActionsPerCapture: Int = 256,
        maximumInteractionsPerCapture: Int = 4_096,
        maximumAccessibilityElementsPerCapture: Int = 16_384,
        maximumFocusMovementsPerCapture: Int = 4_096,
        maximumAttachments: Int = 64,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 8 * 1_024 * 1_024,
        maximumAttachmentBytes: Int = 256 * 1_024 * 1_024,
        maximumAttachmentChunkBytes: Int = 256 * 1_024,
        maximumTotalAttachmentBytes: UInt64 = 512 * 1_024 * 1_024,
        maximumAggregateMemoryBytes: UInt64 = 512 * 1_024 * 1_024,
        maximumArchiveBytes: Int = 16 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 64 * 1_024 * 1_024,
        maximumFindings: Int = 16_384,
        cancellationCheckInterval: Int = 64
    ) {
        self.maximumLifecycleCaptures = maximumLifecycleCaptures
        self.maximumWindowCaptures = maximumWindowCaptures
        self.maximumControlsPerCapture = maximumControlsPerCapture
        self.maximumSecondaryActionsPerCapture = maximumSecondaryActionsPerCapture
        self.maximumInteractionsPerCapture = maximumInteractionsPerCapture
        self.maximumAccessibilityElementsPerCapture = maximumAccessibilityElementsPerCapture
        self.maximumFocusMovementsPerCapture = maximumFocusMovementsPerCapture
        self.maximumAttachments = maximumAttachments
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumAttachmentBytes = maximumAttachmentBytes
        self.maximumAttachmentChunkBytes = maximumAttachmentChunkBytes
        self.maximumTotalAttachmentBytes = maximumTotalAttachmentBytes
        self.maximumAggregateMemoryBytes = maximumAggregateMemoryBytes
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumFindings = maximumFindings
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum ToolbarPresentationEvidenceField: String, CaseIterable, Hashable, Sendable {
    case reference
    case buildBinding
    case manifest
    case layout
    case contract
    case lifecycleRequirements
    case windowRequirements
    case lifecycleCaptures
    case windowCaptures
    case control
    case secondaryAction
    case interaction
    case accessibilityTree
    case focusMovement
    case captureManifest
    case screenshot
    case attachment
    case attachmentPayload
    case provenance
    case source
    case receipt
}

public enum ToolbarPresentationEvidenceWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(ToolbarPresentationEvidenceLimit)
    case countLimitExceeded(ToolbarPresentationEvidenceLimit, maximum: Int)
    case stringTooLarge(maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case attachmentTooLarge(maximumBytes: Int)
    case totalAttachmentsTooLarge(maximumBytes: UInt64)
    case aggregateMemoryExceeded(maximumBytes: UInt64)
    case archiveTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximum: UInt64)
    case findingLimitExceeded(maximum: Int)
    case invalidInventory(ToolbarPresentationEvidenceField)
    case invalidEvidence(ToolbarPresentationEvidenceField)
    case staleApp
    case staleBuild
    case staleInventory
    case staleManifest
    case staleLayout
    case staleScenario
    case inventoryContentsChanged
    case evidenceContentsChanged
    case nonCanonicalArchive

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Toolbar presentation evidence processing was cancelled."
        case .invalidLimit(let limit):
            "Toolbar presentation evidence limit is invalid: \(limit.rawValue)."
        case .countLimitExceeded(let limit, let maximum):
            "Toolbar presentation evidence exceeds the \(maximum)-\(limit.rawValue) limit."
        case .stringTooLarge(let maximum):
            "A redacted toolbar presentation field exceeds \(maximum) UTF-8 bytes."
        case .totalStringsTooLarge(let maximum):
            "Redacted toolbar presentation fields exceed \(maximum) UTF-8 bytes."
        case .attachmentTooLarge(let maximum):
            "A toolbar presentation attachment exceeds \(maximum) declared bytes."
        case .totalAttachmentsTooLarge(let maximum):
            "Toolbar presentation attachments exceed \(maximum) declared bytes."
        case .aggregateMemoryExceeded(let maximum):
            "Toolbar presentation evidence processing exceeds \(maximum) aggregate bytes."
        case .archiveTooLarge(let maximum):
            "Toolbar presentation evidence archive exceeds \(maximum) bytes."
        case .workLimitExceeded(let maximum):
            "Toolbar presentation evidence processing exceeds \(maximum) work units."
        case .findingLimitExceeded(let maximum):
            "Toolbar presentation evidence processing exceeds \(maximum) findings."
        case .invalidInventory(let field):
            "Toolbar presentation inventory is invalid at \(field.rawValue); contents are redacted."
        case .invalidEvidence(let field):
            "Toolbar presentation evidence is invalid at \(field.rawValue); contents are redacted."
        case .staleApp:
            "Toolbar presentation evidence belongs to another app identity or revision."
        case .staleBuild:
            "Toolbar presentation evidence belongs to another build identity, revision, or artifact."
        case .staleInventory:
            "Toolbar presentation evidence belongs to another inventory identity or revision."
        case .staleManifest:
            "Toolbar presentation evidence belongs to another toolbar manifest revision."
        case .staleLayout:
            "Toolbar presentation evidence belongs to another toolbar layout revision."
        case .staleScenario:
            "Toolbar presentation evidence belongs to another scenario identity or revision."
        case .inventoryContentsChanged:
            "Toolbar presentation inventory contents changed without a revision change."
        case .evidenceContentsChanged:
            "Toolbar presentation evidence contents changed without a revision change."
        case .nonCanonicalArchive:
            "Toolbar presentation evidence archive differs from canonical bytes."
        }
    }
}

public enum ToolbarPresentationEvidenceFindingSeverity: String, CaseIterable, Comparable, Hashable,
    Sendable
{
    case advisory
    case warning
    case error

    public static func < (left: Self, right: Self) -> Bool {
        toolbarPresentationSeverityRank(left) < toolbarPresentationSeverityRank(right)
    }
}

public enum ToolbarPresentationEvidenceFindingCode: String, CaseIterable, Hashable, Sendable {
    case missingLifecycleCapture
    case duplicateLifecycleCapture
    case unexpectedLifecycleCapture
    case missingWindowCapture
    case duplicateWindowCapture
    case unexpectedWindowCapture
    case assertionOnlyEvidence
    case commandOrderMismatch
    case commandGroupingMismatch
    case missingControl
    case unexpectedControl
    case controlIdentityMismatch
    case controlBehaviorMismatch
    case tooltipMismatch
    case shortcutMismatch
    case accessibilityIdentifierMismatch
    case accessibilityRoleMismatch
    case accessibilityLabelMismatch
    case accessibilityValueMismatch
    case accessibilityHintMismatch
    case accessibilityEnabledStateMismatch
    case accessibilityFocusMismatch
    case accessibilityStateMismatch
    case accessibilityActionsMismatch
    case availabilityMismatch
    case missingInteractionCapture
    case duplicateInteractionCapture
    case unexpectedInteractionCapture
    case interactionOutcomeMismatch
    case interactionIdentityMismatch
    case duplicateAccessibilityIdentifier
    case duplicateAccessibilityLabel
    case incompleteAccessibilityTree
    case focusMovementMissing
    case focusIdentityMismatch
    case missingAccessibilityAttachment
    case missingScreenshotAttachment
    case attachmentKindMismatch
    case attachmentProvenanceMismatch
    case reusedAttachment
    case reusedAttachmentDigest
    case screenshotContextMismatch
    case orphanAttachment
}

public enum ToolbarPresentationEvidenceFindingSubject: Hashable, Sendable {
    case inventory
    case lifecycle(ToolbarAuditLifecycleScenario)
    case window(ToolbarAuditScreenshotContext)
    case command(ToolbarAuditCommand, lifecycle: ToolbarAuditLifecycleScenario?)
    case attachment(AccessibilityStableID)

    fileprivate var components: [String] {
        switch self {
        case .inventory:
            ["inventory"]
        case .lifecycle(let scenario):
            ["lifecycle", scenario.rawValue]
        case .window(let context):
            ["window", context.rawValue]
        case .command(let command, let lifecycle):
            ["command", command.rawValue, lifecycle?.rawValue ?? ""]
        case .attachment(let id):
            ["attachment", id.rawValue]
        }
    }
}

public struct ToolbarPresentationEvidenceFinding: Identifiable, Equatable, Hashable, Sendable {
    public struct ID: RawRepresentable, Comparable, Equatable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            toolbarPresentationCompareUTF8(left.rawValue, right.rawValue) < 0
        }
    }

    public let id: ID
    public let severity: ToolbarPresentationEvidenceFindingSeverity
    public let code: ToolbarPresentationEvidenceFindingCode
    public let subject: ToolbarPresentationEvidenceFindingSubject
    /// Fixed wording only. Tooltips, labels, values, hints, paths, and sources stay redacted.
    public let message: String

    fileprivate init(
        severity: ToolbarPresentationEvidenceFindingSeverity,
        code: ToolbarPresentationEvidenceFindingCode,
        subject: ToolbarPresentationEvidenceFindingSubject,
        discriminator: String = "",
        budget: ToolbarPresentationWorkBudget
    ) throws {
        self.severity = severity
        self.code = code
        self.subject = subject
        message = toolbarPresentationFindingMessage(code)
        id = ID(
            rawValue: try toolbarPresentationOpaqueID(
                [code.rawValue] + subject.components + [discriminator],
                budget: budget
            )
        )
    }
}

public struct ToolbarPresentationEvidenceReport: Equatable, Sendable {
    public static let scopeStatement =
        "Deterministic validation of caller-supplied, exact-build toolbar presentation measurements and verified screenshot/AX attachments; not independent UI capture, VoiceOver automation, or production conformance."

    public let formatVersion: Int
    public let inventory: AccessibilityEvidenceRevisionReference
    public let evidence: AccessibilityEvidenceRevisionReference
    public let findings: [ToolbarPresentationEvidenceFinding]
    public let requiredLifecycleCaptureCount: Int
    public let completeLifecycleCaptureCount: Int
    public let requiredWindowCaptureCount: Int
    public let completeWindowCaptureCount: Int
    public let requiredInteractionCaptureCount: Int
    public let completeInteractionCaptureCount: Int

    public var highestSeverity: ToolbarPresentationEvidenceFindingSeverity? { findings.first?.severity }
    public var containsErrors: Bool { findings.contains { $0.severity == .error } }
    public var isEvidenceCompleteAndValid: Bool {
        completeLifecycleCaptureCount == requiredLifecycleCaptureCount
            && completeWindowCaptureCount == requiredWindowCaptureCount
            && completeInteractionCaptureCount == requiredInteractionCaptureCount
            && findings.isEmpty
    }

    fileprivate init(
        formatVersion: Int,
        inventory: AccessibilityEvidenceRevisionReference,
        evidence: AccessibilityEvidenceRevisionReference,
        findings: [ToolbarPresentationEvidenceFinding],
        requiredLifecycleCaptureCount: Int,
        completeLifecycleCaptureCount: Int,
        requiredWindowCaptureCount: Int,
        completeWindowCaptureCount: Int,
        requiredInteractionCaptureCount: Int,
        completeInteractionCaptureCount: Int
    ) {
        self.formatVersion = formatVersion
        self.inventory = inventory
        self.evidence = evidence
        self.findings = findings
        self.requiredLifecycleCaptureCount = requiredLifecycleCaptureCount
        self.completeLifecycleCaptureCount = completeLifecycleCaptureCount
        self.requiredWindowCaptureCount = requiredWindowCaptureCount
        self.completeWindowCaptureCount = completeWindowCaptureCount
        self.requiredInteractionCaptureCount = requiredInteractionCaptureCount
        self.completeInteractionCaptureCount = completeInteractionCaptureCount
    }
}

public struct ToolbarPresentationEvidenceCanonicalArchive: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let data: Data
    public let sha256: [UInt8]

    fileprivate init(data: Data, sha256: [UInt8]) {
        self.data = data
        self.sha256 = sha256
    }

    public var description: String {
        "ToolbarPresentationEvidenceCanonicalArchive(bytes: \(data.count), contents: <redacted>)"
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

public struct ToolbarPresentationEvidenceReceipt: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let formatVersion: Int
    public let app: AccessibilityEvidenceRevisionReference
    public let build: AccessibilityEvidenceRevisionReference
    public let inventory: AccessibilityEvidenceRevisionReference
    public let evidence: AccessibilityEvidenceRevisionReference
    public let manifest: AccessibilityEvidenceRevisionReference
    public let layout: AccessibilityEvidenceRevisionReference
    public let configuration: ToolbarCustomizationWorkflow.ConfigurationReference
    public let buildBinding: AccessibilityEvidenceBuildBinding
    public let inventorySHA256: [UInt8]
    public let evidenceArchiveSHA256: [UInt8]
    public let verifiedAttachmentCount: Int
    public let verifiedAttachmentByteCount: UInt64
    public let findingCount: Int
    public let archiveByteCount: Int

    fileprivate init(
        formatVersion: Int,
        app: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        inventory: AccessibilityEvidenceRevisionReference,
        evidence: AccessibilityEvidenceRevisionReference,
        manifest: AccessibilityEvidenceRevisionReference,
        layout: AccessibilityEvidenceRevisionReference,
        configuration: ToolbarCustomizationWorkflow.ConfigurationReference,
        buildBinding: AccessibilityEvidenceBuildBinding,
        inventorySHA256: [UInt8],
        evidenceArchiveSHA256: [UInt8],
        verifiedAttachmentCount: Int,
        verifiedAttachmentByteCount: UInt64,
        findingCount: Int,
        archiveByteCount: Int
    ) {
        self.formatVersion = formatVersion
        self.app = app
        self.build = build
        self.inventory = inventory
        self.evidence = evidence
        self.manifest = manifest
        self.layout = layout
        self.configuration = configuration
        self.buildBinding = buildBinding
        self.inventorySHA256 = inventorySHA256
        self.evidenceArchiveSHA256 = evidenceArchiveSHA256
        self.verifiedAttachmentCount = verifiedAttachmentCount
        self.verifiedAttachmentByteCount = verifiedAttachmentByteCount
        self.findingCount = findingCount
        self.archiveByteCount = archiveByteCount
    }

    public var description: String {
        "ToolbarPresentationEvidenceReceipt(attachments: \(verifiedAttachmentCount), findings: \(findingCount), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "formatVersion": formatVersion,
                "app": app,
                "build": build,
                "inventory": inventory,
                "evidence": evidence,
                "manifest": manifest,
                "layout": layout,
                "configuration": configuration,
                "verifiedAttachmentCount": verifiedAttachmentCount,
                "verifiedAttachmentByteCount": verifiedAttachmentByteCount,
                "findingCount": findingCount,
                "archiveByteCount": archiveByteCount,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public func validateCurrent(
        inventory currentInventory: ToolbarPresentationEvidenceInventory,
        evidence currentEvidence: ToolbarPresentationEvidenceBundle,
        limits: ToolbarPresentationEvidenceLimits = .default,
        attachmentResolver: ToolbarPresentationEvidenceWorkflow.AttachmentResolver,
        captureManifestAuthenticator: ToolbarPresentationEvidenceWorkflow.CaptureManifestAuthenticator,
        cancellationCheck: @escaping ToolbarPresentationEvidenceWorkflow.CancellationCheck = {
            Task.isCancelled
        }
    ) throws {
        try ToolbarPresentationEvidenceWorkflow.validate(
            receipt: self,
            inventory: currentInventory,
            evidence: currentEvidence,
            limits: limits,
            attachmentResolver: attachmentResolver,
            captureManifestAuthenticator: captureManifestAuthenticator,
            cancellationCheck: cancellationCheck
        )
    }
}

public struct ToolbarPresentationEvidenceWorkflowResult: Equatable, Sendable {
    public let report: ToolbarPresentationEvidenceReport
    public let archive: ToolbarPresentationEvidenceCanonicalArchive
    public let receipt: ToolbarPresentationEvidenceReceipt

    fileprivate init(
        report: ToolbarPresentationEvidenceReport,
        archive: ToolbarPresentationEvidenceCanonicalArchive,
        receipt: ToolbarPresentationEvidenceReceipt
    ) {
        self.report = report
        self.archive = archive
        self.receipt = receipt
    }
}

/// UI-independent validation and canonical persistence. No API here captures UI or accesses disk.
public enum ToolbarPresentationEvidenceWorkflow: Sendable {
    public typealias CancellationCheck = @Sendable () -> Bool
    /// Authenticator must bound internal work and call `checkpoint` during processing.
    public typealias CaptureManifestAuthenticator =
        @Sendable (
            _ collector: AccessibilityEvidenceRevisionReference,
            _ canonicalManifest: Data,
            _ authentication: [UInt8],
            _ checkpoint: @Sendable (_ workUnits: UInt64) throws -> Void
        ) throws -> Bool
    /// Resolver must stream bounded chunks through `sink` and call `sink.checkpoint()` during
    /// cooperative work between appends. Work outside those checkpoints cannot be bounded here.
    public typealias AttachmentResolver =
        @Sendable (
            _ id: AccessibilityStableID,
            _ declaredByteCount: Int,
            _ sink: inout ToolbarPresentationEvidenceAttachmentSink
        ) throws -> Void

    public static let reportFormatVersion = 3
    public static let archiveFormatVersion = 5
    public static let captureManifestFormatVersion = 4
    public static let accessibilityAttachmentMediaType =
        "application/vnd.macmerge.toolbar-ax-v4"
    public static let accessibilityAttachmentSource =
        "MacMerge canonical toolbar AX sidecar v4"
    public static let canonicalRenderingPipeline = AccessibilityEvidenceRevisionReference(
        id: AccessibilityStableID(rawValue: "macmerge.toolbar.imageio-srgb-rgba"),
        revision: AccessibilityEvidenceRevision(rawValue: 2)
    )
    public static let canonicalRenderingImplementation =
        "ImageIO/CoreGraphics macOS 26; sRGB; 8-bit premultiplied-last big-endian; no interpolation"
    private static let archiveMagic = Data("MMTBPEV5".utf8)

    /// Canonical semantic sidecar bytes for one lifecycle AX capture.
    public static func canonicalAccessibilityAttachmentData(
        for capture: ToolbarPresentationLifecycleCapture,
        limits: ToolbarPresentationEvidenceLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try ToolbarPresentationValidation.validateLimits(limits)
        let budget = try ToolbarPresentationWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        let strings = ToolbarPresentationStringBudget(limits: limits, work: budget)
        try ToolbarPresentationValidation.preflightAccessibilityAttachment(
            capture,
            limits: limits,
            strings: strings,
            budget: budget
        )
        let data = try ToolbarPresentationCanonicalEncoder.encodeAccessibilityAttachment(
            capture,
            limits: limits,
            budget: budget
        )
        guard data.data.count <= limits.maximumAttachmentBytes else {
            throw ToolbarPresentationEvidenceWorkflowError.attachmentTooLarge(
                maximumBytes: limits.maximumAttachmentBytes
            )
        }
        try budget.finish()
        return data.transfer()
    }

    /// Canonical bytes authenticated by trusted collector implementation.
    public static func canonicalCaptureManifestAuthenticationData(
        for manifest: ToolbarPresentationCaptureManifest,
        limits: ToolbarPresentationEvidenceLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try ToolbarPresentationValidation.validateLimits(limits)
        let budget = try ToolbarPresentationWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        let strings = ToolbarPresentationStringBudget(limits: limits, work: budget)
        try ToolbarPresentationValidation.preflightCaptureManifest(
            manifest,
            requiresAuthentication: false,
            limits: limits,
            strings: strings,
            budget: budget
        )
        let data = try ToolbarPresentationCanonicalEncoder.encodeCaptureManifest(
            manifest,
            includeAuthentication: false,
            limits: limits,
            budget: budget
        )
        try budget.finish()
        return data.transfer()
    }

    /// Decodes and emits normalized sRGB premultiplied RGBA bytes with canonical dimensions.
    /// Original encoded-byte digest remains separate from this deterministic content digest.
    public static func canonicalScreenshotAttachmentData(
        for data: Data,
        mediaType: String,
        limits: ToolbarPresentationEvidenceLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try ToolbarPresentationValidation.validateLimits(limits)
        guard data.count <= limits.maximumAttachmentBytes else {
            throw ToolbarPresentationEvidenceWorkflowError.attachmentTooLarge(
                maximumBytes: limits.maximumAttachmentBytes
            )
        }
        let budget = try ToolbarPresentationWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try budget.consumeMemory(UInt64(data.count))
        defer { budget.releaseMemory(UInt64(data.count)) }
        let canonical = try toolbarPresentationCanonicalScreenshot(
            data,
            expectedMediaType: mediaType,
            limits: limits,
            budget: budget
        )
        try budget.finish()
        return canonical.transfer()
    }

    /// Canonical semantic sidecar bytes for one fresh or loaded window AX capture.
    public static func canonicalAccessibilityAttachmentData(
        for capture: ToolbarPresentationWindowCapture,
        limits: ToolbarPresentationEvidenceLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try ToolbarPresentationValidation.validateLimits(limits)
        let budget = try ToolbarPresentationWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        let strings = ToolbarPresentationStringBudget(limits: limits, work: budget)
        try ToolbarPresentationValidation.preflightAccessibilityAttachment(
            capture,
            limits: limits,
            strings: strings,
            budget: budget
        )
        let data = try ToolbarPresentationCanonicalEncoder.encodeAccessibilityAttachment(
            capture,
            limits: limits,
            budget: budget
        )
        guard data.data.count <= limits.maximumAttachmentBytes else {
            throw ToolbarPresentationEvidenceWorkflowError.attachmentTooLarge(
                maximumBytes: limits.maximumAttachmentBytes
            )
        }
        try budget.finish()
        return data.transfer()
    }

    public static func evaluate(
        inventory: ToolbarPresentationEvidenceInventory,
        evidence: ToolbarPresentationEvidenceBundle,
        limits: ToolbarPresentationEvidenceLimits = .default,
        attachmentResolver: AttachmentResolver,
        captureManifestAuthenticator: CaptureManifestAuthenticator,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> ToolbarPresentationEvidenceWorkflowResult {
        try ToolbarPresentationValidation.validateLimits(limits)
        let budget = try ToolbarPresentationWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        let strings = ToolbarPresentationStringBudget(limits: limits, work: budget)
        try budget.checkCancellation()
        try ToolbarPresentationValidation.validateInventory(
            inventory,
            limits: limits,
            cancellationCheck: cancellationCheck,
            strings: strings,
            budget: budget
        )
        try ToolbarPresentationValidation.validateBinding(
            inventory: inventory,
            evidence: evidence,
            budget: budget
        )
        try ToolbarPresentationValidation.validateEvidence(
            evidence,
            inventory: inventory,
            limits: limits,
            attachmentResolver: attachmentResolver,
            captureManifestAuthenticator: captureManifestAuthenticator,
            cancellationCheck: cancellationCheck,
            strings: strings,
            budget: budget
        )

        var context = ToolbarPresentationEvaluationContext(
            inventory: inventory,
            evidence: evidence,
            limits: limits,
            budget: budget
        )
        let report = try context.run()
        let inventoryData = try ToolbarPresentationCanonicalEncoder.encodeInventory(
            inventory,
            limits: limits,
            budget: budget
        )
        let inventoryDigest = try toolbarPresentationSHA256(inventoryData.data, budget: budget)
        let archive = try canonicalArchive(
            inventoryDigest: inventoryDigest,
            evidence: evidence,
            limits: limits,
            budget: budget
        )
        var attachmentBytes: UInt64 = 0
        for attachment in evidence.attachments {
            try budget.consume()
            attachmentBytes += UInt64(attachment.byteCount)
        }
        let receipt = ToolbarPresentationEvidenceReceipt(
            formatVersion: reportFormatVersion,
            app: inventory.app,
            build: inventory.build,
            inventory: inventory.reference,
            evidence: evidence.reference,
            manifest: inventory.manifestReference,
            layout: inventory.layout.reference,
            configuration: inventory.layout.configurationReference,
            buildBinding: inventory.buildBinding,
            inventorySHA256: inventoryDigest,
            evidenceArchiveSHA256: archive.sha256,
            verifiedAttachmentCount: evidence.attachments.count,
            verifiedAttachmentByteCount: attachmentBytes,
            findingCount: report.findings.count,
            archiveByteCount: archive.data.count
        )
        try budget.finish()
        return ToolbarPresentationEvidenceWorkflowResult(
            report: report,
            archive: archive,
            receipt: receipt
        )
    }

    public static func canonicalArchive(
        for evidence: ToolbarPresentationEvidenceBundle,
        boundTo inventory: ToolbarPresentationEvidenceInventory,
        limits: ToolbarPresentationEvidenceLimits = .default,
        attachmentResolver: AttachmentResolver,
        captureManifestAuthenticator: CaptureManifestAuthenticator,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> ToolbarPresentationEvidenceCanonicalArchive {
        try evaluate(
            inventory: inventory,
            evidence: evidence,
            limits: limits,
            attachmentResolver: attachmentResolver,
            captureManifestAuthenticator: captureManifestAuthenticator,
            cancellationCheck: cancellationCheck
        ).archive
    }

    public static func validate(
        archive: Data,
        for evidence: ToolbarPresentationEvidenceBundle,
        boundTo inventory: ToolbarPresentationEvidenceInventory,
        limits: ToolbarPresentationEvidenceLimits = .default,
        attachmentResolver: AttachmentResolver,
        captureManifestAuthenticator: CaptureManifestAuthenticator,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws {
        try ToolbarPresentationValidation.validateLimits(limits)
        guard archive.count <= limits.maximumArchiveBytes else {
            throw ToolbarPresentationEvidenceWorkflowError.archiveTooLarge(
                maximumBytes: limits.maximumArchiveBytes
            )
        }
        let budget = try ToolbarPresentationWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try budget.consumeMemory(UInt64(archive.count))
        defer { budget.releaseMemory(UInt64(archive.count)) }
        let strings = ToolbarPresentationStringBudget(limits: limits, work: budget)
        try ToolbarPresentationValidation.validateInventory(
            inventory,
            limits: limits,
            cancellationCheck: cancellationCheck,
            strings: strings,
            budget: budget
        )
        try ToolbarPresentationValidation.validateBinding(
            inventory: inventory,
            evidence: evidence,
            budget: budget
        )
        try ToolbarPresentationValidation.validateEvidence(
            evidence,
            inventory: inventory,
            limits: limits,
            attachmentResolver: attachmentResolver,
            captureManifestAuthenticator: captureManifestAuthenticator,
            cancellationCheck: cancellationCheck,
            strings: strings,
            budget: budget
        )
        let inventoryData = try ToolbarPresentationCanonicalEncoder.encodeInventory(
            inventory,
            limits: limits,
            budget: budget
        )
        let inventoryDigest = try toolbarPresentationSHA256(inventoryData.data, budget: budget)
        let canonical = try canonicalArchive(
            inventoryDigest: inventoryDigest,
            evidence: evidence,
            limits: limits,
            budget: budget
        )
        guard try toolbarPresentationDataEqual(archive, canonical.data, budget: budget) else {
            throw ToolbarPresentationEvidenceWorkflowError.nonCanonicalArchive
        }
        try budget.finish()
    }

    public static func validate(
        receipt: ToolbarPresentationEvidenceReceipt,
        inventory: ToolbarPresentationEvidenceInventory,
        evidence: ToolbarPresentationEvidenceBundle,
        limits: ToolbarPresentationEvidenceLimits = .default,
        attachmentResolver: AttachmentResolver,
        captureManifestAuthenticator: CaptureManifestAuthenticator,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws {
        guard receipt.formatVersion == reportFormatVersion,
            receipt.inventorySHA256.count == SHA256.Digest.byteCount,
            receipt.evidenceArchiveSHA256.count == SHA256.Digest.byteCount,
            receipt.verifiedAttachmentCount >= 0,
            receipt.findingCount >= 0,
            receipt.archiveByteCount >= 0
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.receipt)
        }
        guard receipt.app == inventory.app else {
            throw ToolbarPresentationEvidenceWorkflowError.staleApp
        }
        guard receipt.build == inventory.build,
            receipt.buildBinding == inventory.buildBinding
        else {
            throw ToolbarPresentationEvidenceWorkflowError.staleBuild
        }
        guard receipt.inventory == inventory.reference else {
            throw ToolbarPresentationEvidenceWorkflowError.staleInventory
        }
        guard receipt.manifest == inventory.manifestReference else {
            throw ToolbarPresentationEvidenceWorkflowError.staleManifest
        }
        guard receipt.layout == inventory.layout.reference,
            receipt.configuration == inventory.layout.configurationReference
        else {
            throw ToolbarPresentationEvidenceWorkflowError.staleLayout
        }
        guard receipt.evidence == evidence.reference else {
            throw ToolbarPresentationEvidenceWorkflowError.evidenceContentsChanged
        }

        let current = try evaluate(
            inventory: inventory,
            evidence: evidence,
            limits: limits,
            attachmentResolver: attachmentResolver,
            captureManifestAuthenticator: captureManifestAuthenticator,
            cancellationCheck: cancellationCheck
        )
        guard current.receipt.inventorySHA256 == receipt.inventorySHA256 else {
            throw ToolbarPresentationEvidenceWorkflowError.inventoryContentsChanged
        }
        guard current.receipt.evidenceArchiveSHA256 == receipt.evidenceArchiveSHA256,
            current.receipt.verifiedAttachmentCount == receipt.verifiedAttachmentCount,
            current.receipt.verifiedAttachmentByteCount == receipt.verifiedAttachmentByteCount,
            current.receipt.findingCount == receipt.findingCount,
            current.receipt.archiveByteCount == receipt.archiveByteCount
        else {
            throw ToolbarPresentationEvidenceWorkflowError.evidenceContentsChanged
        }
    }

    private static func canonicalArchive(
        inventoryDigest: [UInt8],
        evidence: ToolbarPresentationEvidenceBundle,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws -> ToolbarPresentationEvidenceCanonicalArchive {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendRaw(archiveMagic)
        try writer.appendUInt16(UInt16(archiveFormatVersion))
        try writer.appendUInt16(0)
        try writer.appendRaw(inventoryDigest)
        try ToolbarPresentationCanonicalEncoder.appendEvidence(evidence, to: writer)
        let encoded = writer.finish()
        let digest = try toolbarPresentationSHA256(encoded.data, budget: budget)
        return ToolbarPresentationEvidenceCanonicalArchive(data: encoded.transfer(), sha256: digest)
    }

}

private enum ToolbarPresentationValidation {
    static func validateLimits(_ limits: ToolbarPresentationEvidenceLimits) throws {
        let integerLimits: [(ToolbarPresentationEvidenceLimit, Int, Int)] = [
            (.lifecycleCaptures, limits.maximumLifecycleCaptures, ToolbarPresentationEvidenceLimits.hardMaximumCaptureCount),
            (.windowCaptures, limits.maximumWindowCaptures, ToolbarPresentationEvidenceLimits.hardMaximumCaptureCount),
            (.controls, limits.maximumControlsPerCapture, ToolbarPresentationEvidenceLimits.hardMaximumControlCount),
            (
                .interactions,
                limits.maximumInteractionsPerCapture,
                ToolbarPresentationEvidenceLimits.hardMaximumInteractionCount
            ),
            (
                .accessibilityElements,
                limits.maximumAccessibilityElementsPerCapture,
                ToolbarPresentationEvidenceLimits.hardMaximumAccessibilityElementCount
            ),
            (
                .focusMovements,
                limits.maximumFocusMovementsPerCapture,
                ToolbarPresentationEvidenceLimits.hardMaximumFocusMovementCount
            ),
            (
                .secondaryActions,
                limits.maximumSecondaryActionsPerCapture,
                ToolbarPresentationEvidenceLimits.hardMaximumSecondaryActionCount
            ),
            (.attachments, limits.maximumAttachments, ToolbarPresentationEvidenceLimits.hardMaximumAttachmentCount),
            (.stringUTF8Bytes, limits.maximumStringUTF8Bytes, ToolbarPresentationEvidenceLimits.hardMaximumStringUTF8Bytes),
            (
                .totalStringUTF8Bytes,
                limits.maximumTotalStringUTF8Bytes,
                ToolbarPresentationEvidenceLimits.hardMaximumTotalStringUTF8Bytes
            ),
            (.attachmentBytes, limits.maximumAttachmentBytes, ToolbarPresentationEvidenceLimits.hardMaximumAttachmentBytes),
            (
                .attachmentChunkBytes,
                limits.maximumAttachmentChunkBytes,
                ToolbarPresentationEvidenceLimits.hardMaximumAttachmentChunkBytes
            ),
            (.archiveBytes, limits.maximumArchiveBytes, ToolbarPresentationEvidenceLimits.hardMaximumArchiveBytes),
            (.findings, limits.maximumFindings, ToolbarPresentationEvidenceLimits.hardMaximumFindingCount),
            (
                .cancellationCheckInterval,
                limits.cancellationCheckInterval,
                ToolbarPresentationEvidenceLimits.hardMaximumCancellationCheckInterval
            )
        ]
        for (limit, value, maximum) in integerLimits where value <= 0 || value > maximum {
            throw ToolbarPresentationEvidenceWorkflowError.invalidLimit(limit)
        }
        guard limits.maximumTotalAttachmentBytes > 0,
            limits.maximumTotalAttachmentBytes
                <= ToolbarPresentationEvidenceLimits.hardMaximumTotalAttachmentBytes
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidLimit(.totalAttachmentBytes)
        }
        guard limits.maximumAggregateMemoryBytes > 0,
            limits.maximumAggregateMemoryBytes
                <= ToolbarPresentationEvidenceLimits.hardMaximumAggregateMemoryBytes
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidLimit(.aggregateMemoryBytes)
        }
        guard limits.maximumWorkUnits > 0,
            limits.maximumWorkUnits <= ToolbarPresentationEvidenceLimits.hardMaximumWorkUnits
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidLimit(.workUnits)
        }
    }

    static func preflightAccessibilityAttachment(
        _ capture: ToolbarPresentationLifecycleCapture,
        limits: ToolbarPresentationEvidenceLimits,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        try requireCount(1, maximum: limits.maximumLifecycleCaptures, limit: .lifecycleCaptures)
        try preflightAccessibilityAttachment(
            scenario: capture.scenario,
            reference: capture.reference,
            manifest: capture.manifest,
            layout: capture.layout,
            provenance: capture.provenance,
            origin: capture.origin,
            items: capture.items,
            controls: capture.controls,
            interactions: capture.interactions,
            accessibilityTree: capture.accessibilityTree,
            focusMovements: capture.focusMovements,
            captureManifest: capture.captureManifest,
            attachmentIDs: [capture.accessibilityAttachmentID],
            source: capture.source,
            limits: limits,
            strings: strings,
            budget: budget
        )
    }

    static func preflightAccessibilityAttachment(
        _ capture: ToolbarPresentationWindowCapture,
        limits: ToolbarPresentationEvidenceLimits,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        try requireCount(1, maximum: limits.maximumWindowCaptures, limit: .windowCaptures)
        guard capture.screenshotAttachmentID != capture.accessibilityAttachmentID else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.windowCaptures)
        }
        try preflightAccessibilityAttachment(
            scenario: capture.lifecycleScenario,
            reference: capture.reference,
            manifest: capture.manifest,
            layout: capture.layout,
            provenance: capture.provenance,
            origin: capture.origin,
            items: capture.items,
            controls: capture.controls,
            interactions: capture.interactions,
            accessibilityTree: capture.accessibilityTree,
            focusMovements: capture.focusMovements,
            captureManifest: capture.captureManifest,
            attachmentIDs: [capture.screenshotAttachmentID, capture.accessibilityAttachmentID],
            source: capture.source,
            limits: limits,
            strings: strings,
            budget: budget
        )
    }

    private static func preflightAccessibilityAttachment(
        scenario: ToolbarAuditLifecycleScenario,
        reference: AccessibilityEvidenceRevisionReference,
        manifest: AccessibilityEvidenceRevisionReference,
        layout: AccessibilityEvidenceRevisionReference,
        provenance: AccessibilityEvidenceCaptureProvenance,
        origin: AccessibilityEvidenceOrigin,
        items: [ToolbarAuditItem],
        controls: [ToolbarAuditControlObservation],
        interactions: [ToolbarPresentationInteractionCapture],
        accessibilityTree: [ToolbarPresentationAXElementObservation],
        focusMovements: [ToolbarPresentationFocusMovement],
        captureManifest: ToolbarPresentationCaptureManifest,
        attachmentIDs: [AccessibilityStableID],
        source: String,
        limits: ToolbarPresentationEvidenceLimits,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        try requireCount(controls.count, maximum: limits.maximumControlsPerCapture, limit: .controls)
        try requireCount(
            interactions.count,
            maximum: limits.maximumInteractionsPerCapture,
            limit: .interactions
        )
        try requireCount(
            accessibilityTree.count,
            maximum: limits.maximumAccessibilityElementsPerCapture,
            limit: .accessibilityElements
        )
        try requireCount(
            focusMovements.count,
            maximum: limits.maximumFocusMovementsPerCapture,
            limit: .focusMovements
        )
        for value in [reference, manifest, layout] {
            try validateReference(value, field: .reference, budget: budget)
            try strings.identifier(value.id, field: .reference)
        }
        guard
            origin == .automatedMeasurement || origin == .manualMeasurement
                || origin == .callerAssertion
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.provenance)
        }
        try validateProvenance(provenance, strings: strings, budget: budget)
        try strings.nonblank(source)
        try validateItems(items, field: .accessibilityTree, budget: budget)
        try validateControls(controls, limits: limits, strings: strings, budget: budget)
        try validateAccessibilityTree(
            accessibilityTree,
            focusMovements: focusMovements,
            controls: controls,
            interactions: interactions,
            items: items,
            geometry: captureManifest.geometry,
            strings: strings,
            budget: budget
        )
        try validateInteractions(
            interactions,
            scenario: scenario,
            controls: controls,
            accessibilityTree: accessibilityTree,
            limits: limits,
            strings: strings,
            budget: budget
        )
        for id in attachmentIDs { try strings.identifier(id, field: .attachment) }
        try preflightCaptureManifest(
            captureManifest,
            requiresAuthentication: true,
            limits: limits,
            strings: strings,
            budget: budget
        )
    }

    static func preflightCaptureManifest(
        _ manifest: ToolbarPresentationCaptureManifest,
        requiresAuthentication: Bool,
        limits: ToolbarPresentationEvidenceLimits,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        let references = [
            manifest.collector, manifest.capture, manifest.app, manifest.build, manifest.inventory,
            manifest.manifest, manifest.layout, manifest.renderingPipeline
        ]
        for reference in references {
            try validateReference(reference, field: .captureManifest, budget: budget)
            try strings.identifier(reference.id, field: .captureManifest)
        }
        try validateBuildBinding(manifest.buildBinding, field: .captureManifest)
        guard manifest.formatVersion == ToolbarPresentationEvidenceWorkflow.captureManifestFormatVersion,
            manifest.renderingPipeline == ToolbarPresentationEvidenceWorkflow.canonicalRenderingPipeline,
            manifest.renderingImplementation
                == ToolbarPresentationEvidenceWorkflow.canonicalRenderingImplementation,
            manifest.stateSHA256.count == SHA256.Digest.byteCount,
            manifest.accessibilityTreeSHA256.count == SHA256.Digest.byteCount,
            manifest.screenshotPixelSHA256?.count == nil
                || manifest.screenshotPixelSHA256?.count == SHA256.Digest.byteCount,
            manifest.screenshotEncodedSHA256?.count == nil
                || manifest.screenshotEncodedSHA256?.count == SHA256.Digest.byteCount,
            (manifest.screenshotAttachmentID != nil) == (manifest.screenshotPixelSHA256 != nil),
            (manifest.screenshotMediaType != nil) == (manifest.screenshotPixelSHA256 != nil),
            (manifest.screenshotSource != nil) == (manifest.screenshotPixelSHA256 != nil),
            (manifest.screenshotEncodedSHA256 != nil) == (manifest.screenshotPixelSHA256 != nil),
            !requiresAuthentication || !manifest.authentication.isEmpty,
            !requiresAuthentication
                || manifest.authentication.count <= limits.maximumStringUTF8Bytes,
            manifest.accessibilityTreeIsComplete,
            manifest.screenshotMediaType == nil
                || manifest.screenshotMediaType == "image/png"
                || manifest.screenshotMediaType == "image/jpeg",
            toolbarPresentationValidCaptureGeometry(manifest.geometry),
            manifest.windowState.isVisible,
            manifest.windowState.isKeyWindow,
            manifest.windowState.isMainWindow,
            !manifest.windowState.isMiniaturized
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.captureManifest)
        }
        try strings.nonblank(manifest.renderingImplementation, field: .captureManifest)
        if requiresAuthentication {
            try budget.consume(UInt64(manifest.authentication.count) + 1)
        }
        if let id = manifest.screenshotAttachmentID {
            try strings.identifier(id, field: .captureManifest)
        }
        if let mediaType = manifest.screenshotMediaType {
            try strings.nonblank(mediaType, field: .captureManifest)
        }
        if let source = manifest.screenshotSource {
            try strings.nonblank(source, field: .captureManifest)
        }
    }

    static func validateInventory(
        _ inventory: ToolbarPresentationEvidenceInventory,
        limits: ToolbarPresentationEvidenceLimits,
        cancellationCheck: @escaping ToolbarPresentationEvidenceWorkflow.CancellationCheck,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        try validateReference(inventory.app, field: .reference, budget: budget)
        try validateReference(inventory.build, field: .reference, budget: budget)
        try validateReference(inventory.reference, field: .reference, budget: budget)
        try validateReference(inventory.manifestReference, field: .manifest, budget: budget)
        try validateReference(inventory.layout.reference, field: .layout, budget: budget)
        try validateBuildBinding(inventory.buildBinding, field: .buildBinding)
        for reference in [
            inventory.app, inventory.build, inventory.reference, inventory.manifestReference,
            inventory.layout.reference
        ] {
            try strings.identifier(reference.id, field: .reference)
        }
        guard
            inventory.manifestReference.revision.rawValue
                == inventory.auditContract.manifest.revision.rawValue,
            inventory.layout.manifestRevision == inventory.auditContract.manifest.revision,
            inventory.auditContract.manifest == .canonical,
            inventory.layout.configuration.items == inventory.auditContract.manifest.items,
            inventory.layout.configuration.items == ToolbarConfiguration.winMergeDefaultItems
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.manifest)
        }
        do {
            try inventory.layout.configuration.validate()
        } catch {
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.layout)
        }
        guard
            inventory.layout.configurationReference.revision.rawValue
                == inventory.layout.reference.revision.rawValue
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.layout)
        }

        try requireCount(
            inventory.lifecycleRequirements.count,
            maximum: limits.maximumLifecycleCaptures,
            limit: .lifecycleCaptures
        )
        try requireCount(
            inventory.windowRequirements.count,
            maximum: limits.maximumWindowCaptures,
            limit: .windowCaptures
        )
        let auditLimits = toolbarPresentationAuditLimits(limits)
        guard inventory.auditContract.controls.count <= auditLimits.maximumControls,
            inventory.auditContract.lifecycleExpectations.count
                <= auditLimits.maximumLifecycleExpectations,
            inventory.auditContract.interactionExpectations.count
                <= auditLimits.maximumInteractionRecords,
            inventory.auditContract.screenshotExpectations.count
                <= auditLimits.maximumScreenshots
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
        }
        var lifecycleScenarios: Set<ToolbarAuditLifecycleScenario> = []
        var scenarioReferences: Set<AccessibilityEvidenceRevisionReference> = []
        var lifecycleAvailability: [ToolbarPresentationLifecycleKey: Bool] = [:]
        var controlByCommand: [ToolbarAuditCommand: ToolbarAuditControlRequirement] = [:]
        var semanticActionCommands: [ToolbarAuditStableID: ComparisonCommandState.Identifier] = [:]
        controlByCommand.reserveCapacity(inventory.auditContract.controls.count)
        for control in inventory.auditContract.controls {
            try budget.consume()
            guard controlByCommand.updateValue(control, forKey: control.command) == nil else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
            }
        }
        var requiredActionIDs: Set<ToolbarAuditStableID> = []
        var actionOwners: [ToolbarAuditStableID: ToolbarAuditCommand] = [:]
        var secondaryActionCount = 0
        for control in inventory.auditContract.controls {
            try strings.identifier(
                AccessibilityStableID(rawValue: control.id.rawValue),
                field: .contract
            )
            try strings.identifier(
                AccessibilityStableID(rawValue: control.behavior.primaryActionID.rawValue),
                field: .contract
            )
            try strings.nonblank(control.tooltip, field: .contract)
            if let shortcut = control.shortcut {
                try strings.nonblank(shortcut.key, field: .contract)
                try strings.nonblank(shortcut.display, field: .contract)
            }
            try validateAX(control.accessibility, strings: strings, field: .contract)
            let secondaryCount = control.behavior.secondary.actionIDs.count
            guard
                secondaryCount
                    <= limits.maximumSecondaryActionsPerCapture - secondaryActionCount
            else {
                throw ToolbarPresentationEvidenceWorkflowError.countLimitExceeded(
                    .secondaryActions,
                    maximum: limits.maximumSecondaryActionsPerCapture
                )
            }
            secondaryActionCount += secondaryCount
            for actionID in control.behavior.allActionIDs {
                try budget.consume()
                try strings.identifier(
                    AccessibilityStableID(rawValue: actionID.rawValue),
                    field: .contract
                )
                requiredActionIDs.insert(actionID)
                actionOwners[actionID] = control.command
            }
            if case .menu(let actions) = control.behavior.secondary {
                for action in actions {
                    try validateAX(action.accessibility, strings: strings, field: .contract)
                }
            }
        }
        for binding in inventory.semanticActionBindings {
            try budget.consume()
            guard requiredActionIDs.contains(binding.actionID),
                semanticActionCommands.updateValue(
                    binding.command,
                    forKey: binding.actionID
                ) == nil
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
            }
        }
        guard Set(semanticActionCommands.keys) == requiredActionIDs else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
        }
        for control in inventory.auditContract.controls {
            guard
                semanticActionCommands[control.behavior.primaryActionID]
                    == ComparisonCommandState.Identifier(control.command)
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
            }
        }
        for requirement in inventory.lifecycleRequirements {
            try budget.consume()
            guard lifecycleScenarios.insert(requirement.scenario).inserted,
                scenarioReferences.insert(requirement.reference).inserted
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(
                    .lifecycleRequirements
                )
            }
            try validateReference(requirement.reference, field: .lifecycleRequirements, budget: budget)
            try strings.identifier(requirement.reference.id, field: .lifecycleRequirements)
            guard
                requirement.commandState.bindings.map(\.command)
                    == ComparisonCommandState.Identifier.allCases
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(
                    .lifecycleRequirements
                )
            }
            var availabilityByCommand: [ComparisonCommandState.Identifier: Bool] = [:]
            for resolution in requirement.commandState.bindings {
                try budget.consume()
                guard
                    availabilityByCommand.updateValue(
                        resolution.isEnabled,
                        forKey: resolution.command
                    ) == nil
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(
                        .lifecycleRequirements
                    )
                }
            }
            for (actionID, semanticCommand) in semanticActionCommands {
                try budget.consume()
                guard let command = actionOwners[actionID],
                    let isEnabled = availabilityByCommand[semanticCommand],
                    lifecycleAvailability.updateValue(
                        isEnabled,
                        forKey: ToolbarPresentationLifecycleKey(
                            scenario: requirement.scenario,
                            command: command,
                            actionID: actionID
                        )
                    ) == nil
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(
                        .lifecycleRequirements
                    )
                }
            }
        }
        guard lifecycleScenarios == Set(ToolbarAuditLifecycleScenario.allCases) else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.lifecycleRequirements)
        }
        var windowContexts: Set<ToolbarAuditScreenshotContext> = []
        let lifecycleReferences = Dictionary(
            uniqueKeysWithValues: inventory.lifecycleRequirements.map {
                ($0.scenario, $0.reference)
            }
        )
        for requirement in inventory.windowRequirements {
            try budget.consume()
            guard windowContexts.insert(requirement.context).inserted,
                scenarioReferences.insert(requirement.reference).inserted,
                lifecycleReferences[requirement.lifecycleScenario] != nil
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.windowRequirements)
            }
            try validateReference(requirement.reference, field: .windowRequirements, budget: budget)
            try strings.identifier(requirement.reference.id, field: .windowRequirements)
        }
        guard windowContexts == Set(ToolbarAuditScreenshotContext.allCases) else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.windowRequirements)
        }

        for expectation in inventory.auditContract.lifecycleExpectations {
            try budget.consume()
            guard let control = controlByCommand[expectation.command] else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
            }
            guard control.behavior.allActionIDs.contains(expectation.actionID),
                lifecycleAvailability[ToolbarPresentationLifecycleKey(expectation)]
                    == expectation.availability.isEnabled
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
            }
            if case .disabled(let reason) = expectation.availability {
                try strings.identifier(
                    AccessibilityStableID(rawValue: reason.rawValue),
                    field: .contract
                )
            }
        }

        for expectation in inventory.auditContract.interactionExpectations {
            try strings.identifier(
                AccessibilityStableID(rawValue: expectation.controlID.rawValue),
                field: .contract
            )
            try strings.identifier(
                AccessibilityStableID(rawValue: expectation.actionID.rawValue),
                field: .contract
            )
            try validateOutcome(
                expectation.outcome,
                maximumActionIDs: limits.maximumSecondaryActionsPerCapture,
                strings: strings,
                budget: budget
            )
        }
        let auditEvidence = try toolbarPresentationConformingAuditEvidence(
            inventory.auditContract,
            budget: budget
        )
        try toolbarPresentationDebitNestedAuditStrings(
            contract: inventory.auditContract,
            auditEvidence,
            strings: strings,
            budget: budget
        )
        let nestedMemoryCharge = toolbarPresentationNestedAuditCollectionCharge(
            contract: inventory.auditContract,
            evidence: auditEvidence
        )
        try budget.consumeMemory(nestedMemoryCharge)
        defer { budget.releaseMemory(nestedMemoryCharge) }
        let nestedWork = ToolbarPresentationNestedWorkCounter()
        let nestedLimits = toolbarPresentationAuditLimits(
            limits,
            maximumWorkUnits: max(
                1,
                min(Int(clamping: budget.remainingWorkUnits), auditLimits.maximumWorkUnits)
            ),
            cancellationCheckInterval: 1
        )
        let auditReport: ToolbarAuditReport
        do {
            auditReport = try inventory.auditContract.audit(
                evidence: auditEvidence,
                limits: nestedLimits,
                cancellationCheck: {
                    try nestedWork.increment()
                    if cancellationCheck() { throw CancellationError() }
                }
            )
        } catch ToolbarAuditError.cancelled {
            try budget.consume(nestedWork.value)
            throw ToolbarPresentationEvidenceWorkflowError.cancelled
        } catch {
            try budget.consume(nestedWork.value)
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
        }
        try budget.consume(nestedWork.value)
        guard auditReport.passed else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
        }
    }

    static func validateEvidence(
        _ evidence: ToolbarPresentationEvidenceBundle,
        inventory: ToolbarPresentationEvidenceInventory,
        limits: ToolbarPresentationEvidenceLimits,
        attachmentResolver: ToolbarPresentationEvidenceWorkflow.AttachmentResolver,
        captureManifestAuthenticator: ToolbarPresentationEvidenceWorkflow.CaptureManifestAuthenticator,
        cancellationCheck: @escaping ToolbarPresentationEvidenceWorkflow.CancellationCheck,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        for reference in [
            evidence.reference, evidence.app, evidence.build, evidence.inventory,
            evidence.manifest, evidence.layout
        ] {
            try validateReference(reference, field: .reference, budget: budget)
        }
        try validateBuildBinding(evidence.buildBinding, field: .buildBinding)
        try requireCount(
            evidence.lifecycleCaptures.count,
            maximum: limits.maximumLifecycleCaptures,
            limit: .lifecycleCaptures
        )
        try requireCount(
            evidence.windowCaptures.count,
            maximum: limits.maximumWindowCaptures,
            limit: .windowCaptures
        )
        try requireCount(
            evidence.attachments.count,
            maximum: limits.maximumAttachments,
            limit: .attachments
        )

        for reference in [
            evidence.reference, evidence.app, evidence.build, evidence.inventory,
            evidence.manifest, evidence.layout
        ] {
            try strings.identifier(reference.id, field: .reference)
        }
        let lifecycleCaptures = try toolbarPresentationCanonicalLifecycleCaptures(
            evidence.lifecycleCaptures,
            limits: limits,
            budget: budget
        )
        for capture in lifecycleCaptures {
            try budget.consume()
            try requireCount(
                capture.controls.count,
                maximum: limits.maximumControlsPerCapture,
                limit: .controls
            )
            try requireCount(
                capture.interactions.count,
                maximum: limits.maximumInteractionsPerCapture,
                limit: .interactions
            )
            try requireCount(
                capture.accessibilityTree.count,
                maximum: limits.maximumAccessibilityElementsPerCapture,
                limit: .accessibilityElements
            )
            try requireCount(
                capture.focusMovements.count,
                maximum: limits.maximumFocusMovementsPerCapture,
                limit: .focusMovements
            )
            try validateReference(capture.reference, field: .lifecycleCaptures, budget: budget)
            try strings.identifier(capture.reference.id, field: .lifecycleCaptures)
            try validateCaptureBinding(
                reference: capture.reference,
                manifest: capture.manifest,
                layout: capture.layout,
                provenance: capture.provenance,
                origin: capture.origin,
                source: capture.source,
                evidence: evidence,
                strings: strings,
                budget: budget
            )
            try validateItems(capture.items, field: .lifecycleCaptures, budget: budget)
            try validateControls(
                capture.controls,
                limits: limits,
                strings: strings,
                budget: budget
            )
            try validateAccessibilityTree(
                capture.accessibilityTree,
                focusMovements: capture.focusMovements,
                controls: capture.controls,
                interactions: capture.interactions,
                items: capture.items,
                geometry: capture.captureManifest.geometry,
                strings: strings,
                budget: budget
            )
            try validateInteractions(
                capture.interactions,
                scenario: capture.scenario,
                controls: capture.controls,
                accessibilityTree: capture.accessibilityTree,
                limits: limits,
                strings: strings,
                budget: budget
            )
            try validateCaptureManifest(
                capture.captureManifest,
                expectedContext: .lifecycle(capture.scenario),
                reference: capture.reference,
                provenance: capture.provenance,
                origin: capture.origin,
                inventory: inventory,
                evidence: evidence,
                stateData: ToolbarPresentationCanonicalEncoder.encodeCaptureState(
                    capture,
                    limits: limits,
                    budget: budget
                ),
                accessibilityTree: capture.accessibilityTree,
                requiresScreenshot: false,
                authenticator: captureManifestAuthenticator,
                strings: strings,
                limits: limits,
                budget: budget
            )
            try strings.identifier(capture.accessibilityAttachmentID, field: .attachment)
        }
        let windowCaptures = try toolbarPresentationCanonicalWindowCaptures(
            evidence.windowCaptures,
            limits: limits,
            budget: budget
        )
        for capture in windowCaptures {
            try budget.consume()
            try requireCount(
                capture.controls.count,
                maximum: limits.maximumControlsPerCapture,
                limit: .controls
            )
            try requireCount(
                capture.interactions.count,
                maximum: limits.maximumInteractionsPerCapture,
                limit: .interactions
            )
            try requireCount(
                capture.accessibilityTree.count,
                maximum: limits.maximumAccessibilityElementsPerCapture,
                limit: .accessibilityElements
            )
            try requireCount(
                capture.focusMovements.count,
                maximum: limits.maximumFocusMovementsPerCapture,
                limit: .focusMovements
            )
            try validateReference(capture.reference, field: .windowCaptures, budget: budget)
            guard capture.screenshotAttachmentID != capture.accessibilityAttachmentID
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.windowCaptures)
            }
            try strings.identifier(capture.reference.id, field: .windowCaptures)
            try validateCaptureBinding(
                reference: capture.reference,
                manifest: capture.manifest,
                layout: capture.layout,
                provenance: capture.provenance,
                origin: capture.origin,
                source: capture.source,
                evidence: evidence,
                strings: strings,
                budget: budget
            )
            try validateItems(capture.items, field: .windowCaptures, budget: budget)
            try validateControls(
                capture.controls,
                limits: limits,
                strings: strings,
                budget: budget
            )
            try validateAccessibilityTree(
                capture.accessibilityTree,
                focusMovements: capture.focusMovements,
                controls: capture.controls,
                interactions: capture.interactions,
                items: capture.items,
                geometry: capture.captureManifest.geometry,
                strings: strings,
                budget: budget
            )
            try validateInteractions(
                capture.interactions,
                scenario: capture.lifecycleScenario,
                controls: capture.controls,
                accessibilityTree: capture.accessibilityTree,
                limits: limits,
                strings: strings,
                budget: budget
            )
            try validateCaptureManifest(
                capture.captureManifest,
                expectedContext: .window(
                    capture.context,
                    lifecycle: capture.lifecycleScenario
                ),
                reference: capture.reference,
                provenance: capture.provenance,
                origin: capture.origin,
                inventory: inventory,
                evidence: evidence,
                stateData: ToolbarPresentationCanonicalEncoder.encodeCaptureState(
                    capture,
                    limits: limits,
                    budget: budget
                ),
                accessibilityTree: capture.accessibilityTree,
                requiresScreenshot: true,
                authenticator: captureManifestAuthenticator,
                strings: strings,
                limits: limits,
                budget: budget
            )
            try strings.identifier(capture.screenshotAttachmentID, field: .attachment)
            try strings.identifier(capture.accessibilityAttachmentID, field: .attachment)
        }

        var attachmentIDs: Set<AccessibilityStableID> = []
        for attachment in evidence.attachments {
            try strings.identifier(attachment.id, field: .attachment)
            guard attachmentIDs.insert(attachment.id).inserted else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.attachment)
            }
        }
        let attachments = try toolbarPresentationSorted(
            evidence.attachments,
            by: { left, right in
                try toolbarPresentationStringsCompare(
                    left.id.rawValue,
                    right.id.rawValue,
                    budget: budget
                ) < 0
            },
            budget: budget
        )
        var totalAttachmentBytes: UInt64 = 0
        let screenshotCacheCharge = toolbarPresentationCollectionCharge(
            count: attachments.count,
            stride: MemoryLayout<(AccessibilityStableID, ToolbarPresentationCanonicalScreenshot)>.stride
        )
        try budget.consumeMemory(screenshotCacheCharge)
        defer { budget.releaseMemory(screenshotCacheCharge) }
        var canonicalScreenshots: [AccessibilityStableID: ToolbarPresentationCanonicalScreenshot] = [:]
        for attachment in attachments {
            try budget.consume()
            try strings.identifier(attachment.scenario.id, field: .attachment)
            try strings.identifier(attachment.manifest.id, field: .attachment)
            try strings.identifier(attachment.layout.id, field: .attachment)
            try validateReference(attachment.scenario, field: .attachment, budget: budget)
            try validateReference(attachment.manifest, field: .attachment, budget: budget)
            try validateReference(attachment.layout, field: .attachment, budget: budget)
            try validateProvenance(attachment.provenance, strings: strings, budget: budget)
            try strings.nonblank(attachment.mediaType)
            try strings.nonblank(attachment.source)
            if attachment.kind == .accessibilitySnapshot {
                guard
                    attachment.source
                        == ToolbarPresentationEvidenceWorkflow.accessibilityAttachmentSource
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.attachment)
                }
            }
            guard toolbarPresentationValidMediaType(attachment) else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.attachment)
            }
            guard attachment.byteCount > 0,
                attachment.byteCount <= limits.maximumAttachmentBytes,
                attachment.sha256.count == SHA256.Digest.byteCount,
                attachment.contentSHA256.count == SHA256.Digest.byteCount,
                attachment.captureManifestSHA256.count == SHA256.Digest.byteCount
            else {
                if attachment.byteCount > limits.maximumAttachmentBytes {
                    throw ToolbarPresentationEvidenceWorkflowError.attachmentTooLarge(
                        maximumBytes: limits.maximumAttachmentBytes
                    )
                }
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.attachment)
            }
            let (nextTotal, overflow) = totalAttachmentBytes.addingReportingOverflow(
                UInt64(attachment.byteCount)
            )
            guard !overflow, nextTotal <= limits.maximumTotalAttachmentBytes else {
                throw ToolbarPresentationEvidenceWorkflowError.totalAttachmentsTooLarge(
                    maximumBytes: limits.maximumTotalAttachmentBytes
                )
            }
            totalAttachmentBytes = nextTotal
            var sink = ToolbarPresentationEvidenceAttachmentSink(
                declaredByteCount: attachment.byteCount,
                maximumChunkBytes: limits.maximumAttachmentChunkBytes,
                budget: budget
            )
            defer { sink.releaseRetainedByteCharge() }
            do {
                try attachmentResolver(
                    attachment.id,
                    attachment.byteCount,
                    &sink
                )
                try sink.checkpoint()
            } catch is CancellationError {
                throw ToolbarPresentationEvidenceWorkflowError.cancelled
            } catch is ToolbarPresentationEvidenceAttachmentResolutionError {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.attachmentPayload)
            } catch {
                throw error
            }
            let bytes = sink.resolvedData
            guard bytes.count == attachment.byteCount else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.attachmentPayload)
            }
            let digest = try toolbarPresentationSHA256(bytes, budget: budget)
            guard digest == attachment.sha256 else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.attachmentPayload)
            }
            if attachment.kind == .screenshot {
                let canonical = try toolbarPresentationCanonicalScreenshot(
                    bytes,
                    expectedMediaType: attachment.mediaType,
                    limits: limits,
                    budget: budget
                )
                canonicalScreenshots[attachment.id] = canonical
                guard
                    try toolbarPresentationSHA256(canonical.data, budget: budget)
                        == attachment.contentSHA256
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
                }
            } else {
                guard attachment.contentSHA256 == attachment.sha256 else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.attachmentPayload)
                }
            }
        }

        var attachmentsByID: [AccessibilityStableID: ToolbarPresentationEvidenceAttachment] = [:]
        try budget.consumeMemory(
            toolbarPresentationCollectionCharge(
                count: attachments.count,
                stride: MemoryLayout<(AccessibilityStableID, ToolbarPresentationEvidenceAttachment)>.stride
            )
        )
        defer {
            budget.releaseMemory(
                toolbarPresentationCollectionCharge(
                    count: attachments.count,
                    stride: MemoryLayout<(AccessibilityStableID, ToolbarPresentationEvidenceAttachment)>.stride
                )
            )
        }
        for attachment in attachments {
            try budget.consume()
            attachmentsByID[attachment.id] = attachment
        }
        for capture in lifecycleCaptures {
            guard let attachment = attachmentsByID[capture.accessibilityAttachmentID] else { continue }
            try validateAttachmentManifestBinding(
                attachment,
                manifest: capture.captureManifest,
                limits: limits,
                budget: budget
            )
        }
        for capture in windowCaptures {
            if let screenshot = attachmentsByID[capture.screenshotAttachmentID] {
                guard let canonicalScreenshot = canonicalScreenshots[capture.screenshotAttachmentID],
                    let expectedDimensions = toolbarPresentationGeometryPixelDimensions(
                        capture.captureManifest.geometry
                    ),
                    canonicalScreenshot.dimensions == expectedDimensions,
                    capture.captureManifest.screenshotAttachmentID == screenshot.id,
                    capture.captureManifest.screenshotMediaType == screenshot.mediaType,
                    capture.captureManifest.screenshotSource == screenshot.source,
                    capture.captureManifest.screenshotEncodedSHA256 == screenshot.sha256,
                    capture.captureManifest.screenshotPixelSHA256 == screenshot.contentSHA256
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
                }
                try validateAttachmentManifestBinding(
                    screenshot,
                    manifest: capture.captureManifest,
                    limits: limits,
                    budget: budget
                )
                guard
                    try toolbarPresentationScreenshotHasMeaningfulToolbarPixels(
                        canonicalScreenshot,
                        geometry: capture.captureManifest.geometry,
                        accessibilityTree: capture.accessibilityTree,
                        budget: budget
                    ),
                    try toolbarPresentationScreenshotMatchesContext(
                        canonicalScreenshot,
                        context: capture.context,
                        geometry: capture.captureManifest.geometry,
                        budget: budget
                    )
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
                }
            }
            if let accessibility = attachmentsByID[capture.accessibilityAttachmentID] {
                try validateAttachmentManifestBinding(
                    accessibility,
                    manifest: capture.captureManifest,
                    limits: limits,
                    budget: budget
                )
            }
        }
    }

    static func validateBinding(
        inventory: ToolbarPresentationEvidenceInventory,
        evidence: ToolbarPresentationEvidenceBundle,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        try budget.consume()
        guard evidence.app == inventory.app else {
            throw ToolbarPresentationEvidenceWorkflowError.staleApp
        }
        guard evidence.build == inventory.build,
            evidence.buildBinding == inventory.buildBinding
        else {
            throw ToolbarPresentationEvidenceWorkflowError.staleBuild
        }
        guard evidence.inventory == inventory.reference else {
            throw ToolbarPresentationEvidenceWorkflowError.staleInventory
        }
        guard evidence.manifest == inventory.manifestReference else {
            throw ToolbarPresentationEvidenceWorkflowError.staleManifest
        }
        guard evidence.layout == inventory.layout.reference else {
            throw ToolbarPresentationEvidenceWorkflowError.staleLayout
        }
        let lifecycleReferences = Dictionary(
            uniqueKeysWithValues: inventory.lifecycleRequirements.map {
                ($0.scenario, $0.reference)
            }
        )
        for capture in evidence.lifecycleCaptures {
            guard let reference = lifecycleReferences[capture.scenario],
                capture.reference == reference
            else {
                throw ToolbarPresentationEvidenceWorkflowError.staleScenario
            }
        }
        let windowReferences = Dictionary(
            uniqueKeysWithValues: inventory.windowRequirements.map {
                ($0.context, $0)
            }
        )
        for capture in evidence.windowCaptures {
            guard let requirement = windowReferences[capture.context],
                capture.reference == requirement.reference,
                capture.lifecycleScenario == requirement.lifecycleScenario
            else {
                throw ToolbarPresentationEvidenceWorkflowError.staleScenario
            }
        }
    }

    private static func validateCaptureBinding(
        reference: AccessibilityEvidenceRevisionReference,
        manifest: AccessibilityEvidenceRevisionReference,
        layout: AccessibilityEvidenceRevisionReference,
        provenance: AccessibilityEvidenceCaptureProvenance,
        origin: AccessibilityEvidenceOrigin,
        source: String,
        evidence: ToolbarPresentationEvidenceBundle,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        guard manifest == evidence.manifest else {
            throw ToolbarPresentationEvidenceWorkflowError.staleManifest
        }
        guard layout == evidence.layout else {
            throw ToolbarPresentationEvidenceWorkflowError.staleLayout
        }
        guard provenance.build == evidence.build,
            provenance.buildBinding == evidence.buildBinding
        else {
            throw ToolbarPresentationEvidenceWorkflowError.staleBuild
        }
        guard
            origin == .automatedMeasurement || origin == .manualMeasurement
                || origin == .callerAssertion
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.provenance)
        }
        try validateProvenance(provenance, strings: strings, budget: budget)
        try strings.nonblank(source)
        try budget.consume(UInt64(reference.id.rawValue.utf8.count) + 1)
    }

    private static func validateControls(
        _ controls: [ToolbarAuditControlObservation],
        limits: ToolbarPresentationEvidenceLimits,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        var commands: Set<ToolbarAuditCommand> = []
        var ids: Set<ToolbarAuditStableID> = []
        var secondaryActionCount = 0
        for control in controls {
            try budget.consume()
            guard commands.insert(control.command).inserted,
                ids.insert(control.id).inserted,
                control.accessibility.isEnabled != nil
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.control)
            }
            try strings.identifier(
                AccessibilityStableID(rawValue: control.id.rawValue),
                field: .control
            )
            try strings.identifier(
                AccessibilityStableID(rawValue: control.behavior.primaryActionID.rawValue),
                field: .control
            )
            if let tooltip = control.tooltip { try strings.nonblank(tooltip) }
            if let shortcut = control.shortcut {
                try strings.nonblank(shortcut.key)
                try strings.nonblank(shortcut.display)
            }
            try validateAX(control.accessibility, strings: strings)
            switch control.behavior.secondary {
            case .none:
                break
            case .menu(let actions):
                guard !actions.isEmpty else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.secondaryAction)
                }
                guard actions.count <= limits.maximumSecondaryActionsPerCapture,
                    secondaryActionCount <= limits.maximumSecondaryActionsPerCapture - actions.count
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.countLimitExceeded(
                        .secondaryActions,
                        maximum: limits.maximumSecondaryActionsPerCapture
                    )
                }
                secondaryActionCount += actions.count
                var actionIDs: Set<ToolbarAuditStableID> = []
                for action in actions {
                    try budget.consume()
                    guard actionIDs.insert(action.id).inserted else {
                        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.secondaryAction)
                    }
                    try strings.identifier(
                        AccessibilityStableID(rawValue: action.id.rawValue),
                        field: .secondaryAction
                    )
                    try validateAX(action.accessibility, strings: strings, field: .secondaryAction)
                    guard action.accessibility.isEnabled != nil else {
                        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.secondaryAction)
                    }
                }
            }
            if case .disabled(let reason) = control.availability {
                try strings.identifier(
                    AccessibilityStableID(rawValue: reason.rawValue),
                    field: .control
                )
            }
        }
    }

    private static func validateInteractions(
        _ interactions: [ToolbarPresentationInteractionCapture],
        scenario: ToolbarAuditLifecycleScenario,
        controls: [ToolbarAuditControlObservation],
        accessibilityTree: [ToolbarPresentationAXElementObservation],
        limits: ToolbarPresentationEvidenceLimits,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        let controlsByID = Dictionary(uniqueKeysWithValues: controls.map { ($0.id, $0) })
        var requiredMenuActionOwners: [ToolbarAuditStableID: ToolbarAuditStableID] = [:]
        for interaction in interactions {
            try budget.consume()
            guard let control = controlsByID[interaction.controlID] else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
            }
            if case .menu(let actions) = control.behavior.secondary,
                actions.contains(where: { $0.id == interaction.actionID })
            {
                if let owner = requiredMenuActionOwners[interaction.actionID],
                    owner != interaction.controlID
                {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
                }
                requiredMenuActionOwners[interaction.actionID] = interaction.controlID
            }
            switch interaction.outcome {
            case .menuPresented(let ids):
                guard interaction.invocation == .menuArrowClick,
                    control.behavior.secondary.actionIDs == ids
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
                }
                for id in ids {
                    if let owner = requiredMenuActionOwners[id], owner != interaction.controlID {
                        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
                    }
                    requiredMenuActionOwners[id] = interaction.controlID
                }
            case .invoked, .blocked, .noOp, .failed:
                break
            }
        }
        let accessibilityIndexCharge = toolbarPresentationCollectionCharge(
            count: accessibilityTree.count,
            stride: MemoryLayout<(AccessibilityStableID, ToolbarPresentationAXElementObservation)>.stride
        )
        try budget.consumeMemory(accessibilityIndexCharge)
        defer { budget.releaseMemory(accessibilityIndexCharge) }
        let accessibilityElementsByIdentity = Dictionary(
            uniqueKeysWithValues: accessibilityTree.map { ($0.elementIdentity, $0) }
        )
        var controlElementIdentities: [ToolbarAuditStableID: AccessibilityStableID] = [:]
        var actionElementIdentities: [ToolbarAuditStableID: AccessibilityStableID] = [:]
        for control in controls {
            try budget.consume()
            var match: ToolbarPresentationAXElementObservation?
            for element in accessibilityTree {
                guard
                    try toolbarPresentationStringsEqual(
                        element.accessibility.identifier.rawValue,
                        control.accessibility.identifier.rawValue,
                        budget: budget
                    )
                else { continue }
                guard match == nil else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
                }
                match = element
            }
            guard let match,
                try toolbarPresentationAXMatches(
                    match.accessibility,
                    expected: control.accessibility,
                    expectedEnabled: control.accessibility.isEnabled,
                    budget: budget
                )
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
            }
            controlElementIdentities[control.id] = match.elementIdentity
            guard case .menu(let actions) = control.behavior.secondary else { continue }
            for action in actions where requiredMenuActionOwners[action.id] == control.id {
                try budget.consume()
                var actionMatch: ToolbarPresentationAXElementObservation?
                for element in accessibilityTree {
                    guard
                        try toolbarPresentationStringsEqual(
                            element.accessibility.identifier.rawValue,
                            action.accessibility.identifier.rawValue,
                            budget: budget
                        )
                    else { continue }
                    guard actionMatch == nil else {
                        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
                    }
                    actionMatch = element
                }
                guard let actionMatch,
                    try toolbarPresentationAXMatches(
                        actionMatch.accessibility,
                        expected: action.accessibility,
                        expectedEnabled: action.accessibility.isEnabled,
                        budget: budget
                    ),
                    actionMatch.accessibility.role == .menuItem,
                    try toolbarPresentationOwnedMenuIdentity(
                        of: actionMatch.elementIdentity,
                        elementsByIdentity: accessibilityElementsByIdentity,
                        expectedControl: match.elementIdentity,
                        budget: budget
                    ) != nil,
                    actionElementIdentities.updateValue(
                        actionMatch.elementIdentity,
                        forKey: action.id
                    ) == nil
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
                }
            }
        }
        var keys: Set<ToolbarPresentationInteractionKey> = []
        for interaction in interactions {
            try budget.consume()
            guard let control = controlsByID[interaction.controlID],
                interaction.scenario == scenario,
                control.behavior.allActionIDs.contains(interaction.actionID),
                interaction.elementIdentity
                    == (requiredMenuActionOwners[interaction.actionID] == control.id
                        ? actionElementIdentities[interaction.actionID]
                        : controlElementIdentities[control.id]),
                keys.insert(ToolbarPresentationInteractionKey(interaction)).inserted
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
            }
            try strings.identifier(
                AccessibilityStableID(rawValue: interaction.controlID.rawValue),
                field: .interaction
            )
            try strings.identifier(interaction.elementIdentity, field: .interaction)
            try strings.identifier(
                AccessibilityStableID(rawValue: interaction.actionID.rawValue),
                field: .interaction
            )
            try strings.nonblank(interaction.source, field: .interaction)
            try validateOutcome(
                interaction.outcome,
                maximumActionIDs: limits.maximumSecondaryActionsPerCapture,
                strings: strings,
                budget: budget
            )
        }
    }

    private static func validateOutcome(
        _ outcome: ToolbarAuditInteractionOutcome,
        maximumActionIDs: Int,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        switch outcome {
        case .invoked(let id), .failed(let id):
            try strings.identifier(AccessibilityStableID(rawValue: id.rawValue), field: .interaction)
        case .menuPresented(let ids):
            guard !ids.isEmpty, ids.count <= maximumActionIDs, Set(ids).count == ids.count else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.interaction)
            }
            for id in ids {
                try budget.consume()
                try strings.identifier(
                    AccessibilityStableID(rawValue: id.rawValue),
                    field: .interaction
                )
            }
        case .blocked, .noOp:
            break
        }
    }

    private static func validateAccessibilityTree(
        _ tree: [ToolbarPresentationAXElementObservation],
        focusMovements: [ToolbarPresentationFocusMovement],
        controls: [ToolbarAuditControlObservation],
        interactions: [ToolbarPresentationInteractionCapture],
        items: [ToolbarAuditItem],
        geometry: ToolbarPresentationCaptureGeometry,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        guard !tree.isEmpty else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
        }
        let treeIndexCharge = toolbarPresentationCollectionCharge(
            count: tree.count,
            stride: MemoryLayout<(AccessibilityStableID, ToolbarPresentationAXElementObservation)>.stride
        )
        try budget.consumeMemory(treeIndexCharge)
        defer { budget.releaseMemory(treeIndexCharge) }
        var byIdentity: [AccessibilityStableID: ToolbarPresentationAXElementObservation] = [:]
        var root: ToolbarPresentationAXElementObservation?
        for element in tree {
            try budget.consume()
            guard byIdentity.updateValue(element, forKey: element.elementIdentity) == nil,
                toolbarPresentationValidRect(element.frame),
                element.siblingIndex >= 0
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
            try strings.identifier(element.elementIdentity, field: .accessibilityTree)
            if let parent = element.parentIdentity {
                try strings.identifier(parent, field: .accessibilityTree)
                guard parent != element.elementIdentity else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
                }
            } else {
                guard root == nil else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(
                        .accessibilityTree
                    )
                }
                root = element
            }
            try validateAX(
                element.accessibility,
                strings: strings,
                field: .accessibilityTree
            )
        }
        guard let root, root.accessibility.role == .toolbar, root.frame == geometry.toolbar,
            root.siblingIndex == 0
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
        }
        var childrenByParent: [AccessibilityStableID: [ToolbarPresentationAXElementObservation]] = [:]
        for element in tree {
            if let parent = element.parentIdentity {
                guard byIdentity[parent] != nil else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
                }
                childrenByParent[parent, default: []].append(element)
            }
            var ancestors: Set<AccessibilityStableID> = []
            var current = element.parentIdentity
            while let identity = current {
                try budget.consume()
                guard ancestors.insert(identity).inserted else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
                }
                current = byIdentity[identity]?.parentIdentity
            }
        }
        for children in childrenByParent.values {
            try budget.consume(UInt64(children.count) + 1)
            guard Set(children.map(\.siblingIndex)) == Set(0..<children.count) else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
        }
        var controlElementIdentities: [ToolbarAuditStableID: AccessibilityStableID] = [:]
        var mappedElementIdentities: Set<AccessibilityStableID> = []
        for control in controls {
            try budget.consume()
            var match: ToolbarPresentationAXElementObservation?
            for element in tree {
                guard
                    try toolbarPresentationStringsEqual(
                        element.accessibility.identifier.rawValue,
                        control.accessibility.identifier.rawValue,
                        budget: budget
                    )
                else { continue }
                guard match == nil else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(
                        .accessibilityTree
                    )
                }
                match = element
            }
            guard let match,
                try toolbarPresentationAXMatches(
                    match.accessibility,
                    expected: control.accessibility,
                    expectedEnabled: control.accessibility.isEnabled,
                    budget: budget
                ),
                mappedElementIdentities.insert(match.elementIdentity).inserted
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(
                    .accessibilityTree
                )
            }
            controlElementIdentities[control.id] = match.elementIdentity
        }
        guard controlElementIdentities.count == controls.count else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
        }
        let controlsByID = Dictionary(uniqueKeysWithValues: controls.map { ($0.id, $0) })
        var secondaryActionOwners: [ToolbarAuditStableID: ToolbarAuditStableID] = [:]
        for control in controls {
            for actionID in control.behavior.secondary.actionIDs {
                secondaryActionOwners[actionID] = control.id
            }
        }
        var presentedActionOwners: [ToolbarAuditStableID: ToolbarAuditStableID] = [:]
        for interaction in interactions {
            if secondaryActionOwners[interaction.actionID] == interaction.controlID {
                presentedActionOwners[interaction.actionID] = interaction.controlID
            }
            switch interaction.outcome {
            case .menuPresented(let ids):
                for id in ids { presentedActionOwners[id] = interaction.controlID }
            default:
                break
            }
        }
        var permittedMenuRoots: Set<AccessibilityStableID> = []
        var permittedMenuFrames: [AccessibilityStableID: ToolbarPresentationEvidenceRect] = [:]
        var permittedMenuItems: Set<AccessibilityStableID> = []
        var menuActionIdentities: [ToolbarAuditStableID: AccessibilityStableID] = [:]
        var focusableMenuActions: [[ToolbarAuditSecondaryAction]] = []
        let presentedControlIDs = Set(presentedActionOwners.values)
        for controlID in presentedControlIDs {
            try budget.consume()
            guard let control = controlsByID[controlID],
                let ownerIdentity = controlElementIdentities[controlID],
                case .menu(let actions) = control.behavior.secondary
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
            let menus = (childrenByParent[ownerIdentity] ?? []).filter {
                $0.accessibility.role == .menu
            }
            guard menus.count == 1, let menu = menus.first,
                menu.accessibility.isEnabled == true,
                menu.siblingIndex == 0,
                toolbarPresentationRectIntersects(menu.frame, geometry.window)
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
            let menuItems = try toolbarPresentationSorted(
                childrenByParent[menu.elementIdentity] ?? [],
                by: { $0.siblingIndex < $1.siblingIndex },
                budget: budget
            )
            guard menuItems.count == actions.count,
                menuItems.map(\.siblingIndex) == Array(0..<actions.count)
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
            var previousFrame: ToolbarPresentationEvidenceRect?
            for (action, menuItem) in zip(actions, menuItems) {
                try budget.consume()
                guard menuItem.accessibility.role == .menuItem,
                    try toolbarPresentationAXMatches(
                        menuItem.accessibility,
                        expected: action.accessibility,
                        expectedEnabled: action.accessibility.isEnabled,
                        budget: budget
                    ),
                    toolbarPresentationRectContains(menu.frame, menuItem.frame),
                    previousFrame.map({ toolbarPresentationStrictlyPrecedes($0, menuItem.frame) })
                        ?? true
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
                }
                previousFrame = menuItem.frame
                mappedElementIdentities.insert(menuItem.elementIdentity)
                permittedMenuItems.insert(menuItem.elementIdentity)
                menuActionIdentities[action.id] = menuItem.elementIdentity
            }
            focusableMenuActions.append(
                actions.filter {
                    $0.accessibility.isKeyboardFocusable && $0.accessibility.isEnabled == true
                }
            )
            permittedMenuRoots.insert(menu.elementIdentity)
            permittedMenuFrames[menu.elementIdentity] = menu.frame
        }
        let observedMenus = tree.filter { $0.accessibility.role == .menu }
        guard observedMenus.count == presentedControlIDs.count,
            Set(observedMenus.map(\.elementIdentity)) == permittedMenuRoots
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
        }
        for element in tree {
            try budget.consume()
            let owningMenu = try toolbarPresentationAncestor(
                of: element.elementIdentity,
                in: permittedMenuRoots,
                elementsByIdentity: byIdentity,
                budget: budget
            )
            let permittedMenuElement = owningMenu != nil
            if let owningMenu, let menuFrame = permittedMenuFrames[owningMenu],
                !toolbarPresentationRectContains(menuFrame, element.frame)
            {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
            let contained = toolbarPresentationRectContains(geometry.toolbar, element.frame)
            if !contained, !permittedMenuElement {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
            let isActive =
                element.accessibility.isKeyboardFocusable
                || !element.accessibility.actions.isEmpty
            if isActive,
                element.elementIdentity != root.elementIdentity,
                !mappedElementIdentities.contains(element.elementIdentity),
                !permittedMenuItems.contains(element.elementIdentity)
            {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
        }
        try toolbarPresentationValidateObservedLayout(
            tree: tree,
            rootIdentity: root.elementIdentity,
            controls: controls,
            controlElementIdentities: controlElementIdentities,
            items: items,
            budget: budget
        )

        let controlsByCommand = Dictionary(uniqueKeysWithValues: controls.map { ($0.command, $0) })
        var focusableControls: [ToolbarAuditControlObservation] = []
        for item in items {
            try budget.consume()
            guard case .command(let command) = item,
                let control = controlsByCommand[command],
                control.accessibility.isKeyboardFocusable,
                control.accessibility.isEnabled == true
            else { continue }
            focusableControls.append(control)
        }
        guard !focusableControls.isEmpty else {
            guard focusMovements.isEmpty else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.focusMovement)
            }
            return
        }
        var focusByControlAndTraversal: [ToolbarPresentationFocusKey: ToolbarPresentationFocusMovement] = [:]
        for movement in focusMovements {
            try budget.consume()
            guard byIdentity[movement.fromElementIdentity] != nil,
                byIdentity[movement.toElementIdentity] != nil,
                focusByControlAndTraversal.updateValue(
                    movement,
                    forKey: ToolbarPresentationFocusKey(movement)
                ) == nil
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.focusMovement)
            }
            try strings.identifier(
                AccessibilityStableID(rawValue: movement.controlID.rawValue),
                field: .focusMovement
            )
            try strings.identifier(movement.fromElementIdentity, field: .focusMovement)
            try strings.identifier(movement.toElementIdentity, field: .focusMovement)
        }
        let expectedFocusMovementCount =
            focusableControls.count * 2 + focusableMenuActions.reduce(0) { $0 + $1.count * 2 }
        guard focusMovements.count == expectedFocusMovementCount else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.focusMovement)
        }
        for (index, control) in focusableControls.enumerated() {
            try budget.consume()
            guard let target = controlElementIdentities[control.id],
                let previous = focusableControls.count == 1
                    ? root.elementIdentity
                    : controlElementIdentities[
                        focusableControls[
                            (index + focusableControls.count - 1) % focusableControls.count
                        ].id
                    ],
                let next = focusableControls.count == 1
                    ? root.elementIdentity
                    : controlElementIdentities[
                        focusableControls[(index + 1) % focusableControls.count].id
                    ],
                previous != target,
                next != target,
                focusByControlAndTraversal[
                    ToolbarPresentationFocusKey(
                        controlID: control.id,
                        traversal: .tabForward
                    )
                ]
                    == ToolbarPresentationFocusMovement(
                        controlID: control.id,
                        fromElementIdentity: previous,
                        toElementIdentity: target,
                        traversal: .tabForward
                    ),
                focusByControlAndTraversal[
                    ToolbarPresentationFocusKey(
                        controlID: control.id,
                        traversal: .tabBackward
                    )
                ]
                    == ToolbarPresentationFocusMovement(
                        controlID: control.id,
                        fromElementIdentity: next,
                        toElementIdentity: target,
                        traversal: .tabBackward
                    )
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.focusMovement)
            }
        }
        for actions in focusableMenuActions {
            guard !actions.isEmpty else { continue }
            for (index, action) in actions.enumerated() {
                try budget.consume()
                guard let target = menuActionIdentities[action.id],
                    let parent = byIdentity[target]?.parentIdentity,
                    let previous = actions.count == 1
                        ? parent
                        : menuActionIdentities[actions[(index + actions.count - 1) % actions.count].id],
                    let next = actions.count == 1
                        ? parent
                        : menuActionIdentities[actions[(index + 1) % actions.count].id],
                    previous != target,
                    next != target,
                    focusByControlAndTraversal[
                        ToolbarPresentationFocusKey(controlID: action.id, traversal: .menuNext)
                    ]
                        == ToolbarPresentationFocusMovement(
                            controlID: action.id,
                            fromElementIdentity: previous,
                            toElementIdentity: target,
                            traversal: .menuNext
                        ),
                    focusByControlAndTraversal[
                        ToolbarPresentationFocusKey(controlID: action.id, traversal: .menuPrevious)
                    ]
                        == ToolbarPresentationFocusMovement(
                            controlID: action.id,
                            fromElementIdentity: next,
                            toElementIdentity: target,
                            traversal: .menuPrevious
                        )
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.focusMovement)
                }
            }
        }
    }

    private static func validateCaptureManifest(
        _ manifest: ToolbarPresentationCaptureManifest,
        expectedContext: ToolbarPresentationCaptureContext,
        reference: AccessibilityEvidenceRevisionReference,
        provenance: AccessibilityEvidenceCaptureProvenance,
        origin: AccessibilityEvidenceOrigin,
        inventory: ToolbarPresentationEvidenceInventory,
        evidence: ToolbarPresentationEvidenceBundle,
        stateData: ToolbarPresentationRetainedData,
        accessibilityTree: [ToolbarPresentationAXElementObservation],
        requiresScreenshot: Bool,
        authenticator: ToolbarPresentationEvidenceWorkflow.CaptureManifestAuthenticator,
        strings: ToolbarPresentationStringBudget,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        guard
            manifest.formatVersion
                == ToolbarPresentationEvidenceWorkflow.captureManifestFormatVersion,
            manifest.collector == provenance.collector,
            manifest.capture == reference,
            manifest.origin == origin,
            manifest.app == inventory.app,
            manifest.build == inventory.build,
            manifest.buildBinding == inventory.buildBinding,
            manifest.inventory == inventory.reference,
            manifest.manifest == inventory.manifestReference,
            manifest.layout == inventory.layout.reference,
            manifest.configuration == inventory.layout.configurationReference,
            manifest.contractRevision == inventory.auditContract.revision,
            manifest.manifestRevision == inventory.auditContract.manifest.revision,
            manifest.context == expectedContext,
            manifest.renderingPipeline
                == ToolbarPresentationEvidenceWorkflow.canonicalRenderingPipeline,
            manifest.renderingImplementation
                == ToolbarPresentationEvidenceWorkflow.canonicalRenderingImplementation,
            manifest.accessibilityTreeIsComplete,
            manifest.screenshotMediaType == nil
                || manifest.screenshotMediaType == "image/png"
                || manifest.screenshotMediaType == "image/jpeg",
            (manifest.screenshotPixelSHA256 != nil) == requiresScreenshot,
            manifest.screenshotPixelSHA256?.count == nil
                || manifest.screenshotPixelSHA256?.count == SHA256.Digest.byteCount,
            manifest.screenshotEncodedSHA256?.count == nil
                || manifest.screenshotEncodedSHA256?.count == SHA256.Digest.byteCount,
            (manifest.screenshotAttachmentID != nil) == requiresScreenshot,
            (manifest.screenshotMediaType != nil) == requiresScreenshot,
            (manifest.screenshotSource != nil) == requiresScreenshot,
            (manifest.screenshotEncodedSHA256 != nil) == requiresScreenshot,
            manifest.stateSHA256.count == SHA256.Digest.byteCount,
            manifest.accessibilityTreeSHA256.count == SHA256.Digest.byteCount,
            !manifest.authentication.isEmpty,
            manifest.authentication.count <= limits.maximumStringUTF8Bytes,
            toolbarPresentationValidCaptureGeometry(manifest.geometry),
            manifest.windowState.isVisible,
            manifest.windowState.isKeyWindow,
            manifest.windowState.isMainWindow,
            !manifest.windowState.isMiniaturized
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.captureManifest)
        }
        try strings.identifier(manifest.collector.id, field: .captureManifest)
        try strings.identifier(manifest.capture.id, field: .captureManifest)
        for reference in [
            manifest.app, manifest.build, manifest.inventory, manifest.manifest, manifest.layout
        ] {
            try strings.identifier(reference.id, field: .captureManifest)
        }
        try validateReference(
            manifest.renderingPipeline,
            field: .captureManifest,
            budget: budget
        )
        try strings.identifier(manifest.renderingPipeline.id, field: .captureManifest)
        try strings.nonblank(manifest.renderingImplementation, field: .captureManifest)
        if let id = manifest.screenshotAttachmentID {
            try strings.identifier(id, field: .captureManifest)
        }
        if let mediaType = manifest.screenshotMediaType {
            try strings.nonblank(mediaType, field: .captureManifest)
        }
        if let source = manifest.screenshotSource {
            try strings.nonblank(source, field: .captureManifest)
        }
        let stateDigest = try toolbarPresentationSHA256(stateData.data, budget: budget)
        let treeData = try ToolbarPresentationCanonicalEncoder.encodeAccessibilityTree(
            accessibilityTree,
            limits: limits,
            budget: budget
        )
        let treeDigest = try toolbarPresentationSHA256(treeData.data, budget: budget)
        guard stateDigest == manifest.stateSHA256,
            treeDigest == manifest.accessibilityTreeSHA256
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.captureManifest)
        }
        let canonical = try ToolbarPresentationCanonicalEncoder.encodeCaptureManifest(
            manifest,
            includeAuthentication: false,
            limits: limits,
            budget: budget
        )
        try budget.consume(UInt64(canonical.data.count + manifest.authentication.count) + 1)
        try budget.checkCancellation()
        do {
            guard
                try authenticator(
                    manifest.collector,
                    canonical.data,
                    manifest.authentication,
                    { try budget.consume($0) }
                )
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.captureManifest)
            }
        } catch is CancellationError {
            throw ToolbarPresentationEvidenceWorkflowError.cancelled
        }
        try budget.checkCancellation()
    }

    private static func validateAttachmentManifestBinding(
        _ attachment: ToolbarPresentationEvidenceAttachment,
        manifest: ToolbarPresentationCaptureManifest,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        let manifestData = try ToolbarPresentationCanonicalEncoder.encodeCaptureManifest(
            manifest,
            includeAuthentication: true,
            limits: limits,
            budget: budget
        )
        guard
            try toolbarPresentationSHA256(manifestData.data, budget: budget)
                == attachment.captureManifestSHA256
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.attachment)
        }
    }

    private static func validateAX(
        _ metadata: ToolbarAuditAXMetadata,
        strings: ToolbarPresentationStringBudget,
        field: ToolbarPresentationEvidenceField = .control
    ) throws {
        try strings.identifier(
            AccessibilityStableID(rawValue: metadata.identifier.rawValue),
            field: field
        )
        try strings.text(metadata.label, field: field)
        if let value = metadata.value { try strings.text(value, field: field) }
        try strings.text(metadata.hint, field: field)
        guard toolbarPresentationMetadataMatchesRole(metadata) else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(field)
        }
    }

    private static func validateItems(
        _ items: [ToolbarAuditItem],
        field: ToolbarPresentationEvidenceField,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        guard items.count <= ToolbarConfiguration.maximumItemCount else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(field)
        }
        var commands: Set<ToolbarAuditCommand> = []
        for item in items {
            try budget.consume()
            if case .command(let command) = item, !commands.insert(command).inserted {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(field)
            }
        }
    }

    private static func validateProvenance(
        _ provenance: AccessibilityEvidenceCaptureProvenance,
        strings: ToolbarPresentationStringBudget,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        guard provenance.capturedAtUnixMilliseconds > 0,
            (16...64).contains(provenance.runNonce.count),
            provenance.runNonce.contains(where: { $0 != 0 })
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.provenance)
        }
        try validateReference(provenance.collector, field: .provenance, budget: budget)
        try validateReference(provenance.build, field: .provenance, budget: budget)
        try validateBuildBinding(provenance.buildBinding, field: .provenance)
        try strings.identifier(provenance.collector.id, field: .provenance)
        try strings.identifier(provenance.build.id, field: .provenance)
        try budget.consume(UInt64(provenance.runNonce.count) + 1)
    }

    private static func validateReference(
        _ reference: AccessibilityEvidenceRevisionReference,
        field: ToolbarPresentationEvidenceField,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        try validateID(reference.id, field: field, budget: budget)
    }

    private static func validateID(
        _ id: AccessibilityStableID,
        field: ToolbarPresentationEvidenceField,
        budget: ToolbarPresentationWorkBudget
    ) throws {
        let value = id.rawValue
        let byteCount = toolbarPresentationBoundedUTF8Count(
            value,
            maximum: ToolbarPresentationEvidenceLimits.hardMaximumStringUTF8Bytes
        )
        guard byteCount > 0 else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(field)
        }
        guard byteCount <= ToolbarPresentationEvidenceLimits.hardMaximumStringUTF8Bytes else {
            throw ToolbarPresentationEvidenceWorkflowError.stringTooLarge(
                maximumUTF8Bytes: ToolbarPresentationEvidenceLimits.hardMaximumStringUTF8Bytes
            )
        }
        try budget.consume(UInt64(byteCount) + 1)
        guard !toolbarPresentationIsBlank(value),
            value == value.precomposedStringWithCanonicalMapping,
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(field)
        }
    }

    private static func validateBuildBinding(
        _ binding: AccessibilityEvidenceBuildBinding,
        field: ToolbarPresentationEvidenceField
    ) throws {
        guard binding.artifactSHA256.count == SHA256.Digest.byteCount,
            binding.signingIdentitySHA256.count == SHA256.Digest.byteCount,
            binding.artifactSHA256.contains(where: { $0 != 0 }),
            binding.signingIdentitySHA256.contains(where: { $0 != 0 })
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(field)
        }
    }

    private static func requireCount(
        _ count: Int,
        maximum: Int,
        limit: ToolbarPresentationEvidenceLimit
    ) throws {
        guard count <= maximum else {
            throw ToolbarPresentationEvidenceWorkflowError.countLimitExceeded(
                limit,
                maximum: maximum
            )
        }
    }
}

private struct ToolbarPresentationEvaluationContext {
    private static let findingStorageStride =
        MemoryLayout<ToolbarPresentationEvidenceFinding>.stride
        + MemoryLayout<ToolbarPresentationEvidenceFinding.ID>.stride

    let inventory: ToolbarPresentationEvidenceInventory
    let evidence: ToolbarPresentationEvidenceBundle
    let limits: ToolbarPresentationEvidenceLimits
    let budget: ToolbarPresentationWorkBudget
    private var findings: [ToolbarPresentationEvidenceFinding] = []
    private var findingIDs: Set<ToolbarPresentationEvidenceFinding.ID> = []
    private var findingStorageCharge: UInt64 = 0
    private let lifecycleByKey: [ToolbarPresentationLifecycleKey: ToolbarAuditLifecycleExpectation]
    private let requirementsByCommand: [ToolbarAuditCommand: ToolbarAuditControlRequirement]
    private let manifestCommands: Set<ToolbarAuditCommand>

    init(
        inventory: ToolbarPresentationEvidenceInventory,
        evidence: ToolbarPresentationEvidenceBundle,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) {
        self.inventory = inventory
        self.evidence = evidence
        self.limits = limits
        self.budget = budget
        var lifecycleByKey: [ToolbarPresentationLifecycleKey: ToolbarAuditLifecycleExpectation] = [:]
        lifecycleByKey.reserveCapacity(inventory.auditContract.lifecycleExpectations.count)
        for expectation in inventory.auditContract.lifecycleExpectations {
            lifecycleByKey[ToolbarPresentationLifecycleKey(expectation)] = expectation
        }
        self.lifecycleByKey = lifecycleByKey
        requirementsByCommand = Dictionary(
            uniqueKeysWithValues: inventory.auditContract.controls.map { ($0.command, $0) }
        )
        manifestCommands = Set(inventory.auditContract.manifest.commands)
    }

    mutating func run() throws -> ToolbarPresentationEvidenceReport {
        defer { budget.releaseMemory(findingStorageCharge) }
        var lifecycleCaptures: [ToolbarAuditLifecycleScenario: [ToolbarPresentationLifecycleCapture]] = [:]
        for capture in evidence.lifecycleCaptures {
            try budget.consume()
            lifecycleCaptures[capture.scenario, default: []].append(capture)
        }
        var windowCaptures: [ToolbarAuditScreenshotContext: [ToolbarPresentationWindowCapture]] = [:]
        for capture in evidence.windowCaptures {
            try budget.consume()
            windowCaptures[capture.context, default: []].append(capture)
        }
        let expectedLifecycle = Set(inventory.lifecycleRequirements.map(\.scenario))
        let expectedWindows = Set(inventory.windowRequirements.map(\.context))
        var completeLifecycleCount = 0
        var completeWindowCount = 0
        var interactionCaptures: [ToolbarPresentationInteractionKey: [ToolbarPresentationInteractionCapture]] = [:]
        for capture in evidence.lifecycleCaptures {
            for interaction in capture.interactions {
                try budget.consume()
                interactionCaptures[ToolbarPresentationInteractionKey(interaction), default: []]
                    .append(interaction)
            }
        }
        for capture in evidence.windowCaptures {
            for interaction in capture.interactions {
                try budget.consume()
                interactionCaptures[ToolbarPresentationInteractionKey(interaction), default: []]
                    .append(interaction)
            }
        }
        let expectedInteractionKeys = Set(
            inventory.auditContract.interactionExpectations.map(ToolbarPresentationInteractionKey.init)
        )
        var completeInteractionCount = 0

        for requirement in try toolbarPresentationSorted(
            inventory.lifecycleRequirements,
            by: { toolbarPresentationEnumRank($0.scenario) < toolbarPresentationEnumRank($1.scenario) },
            budget: budget
        ) {
            let captures = lifecycleCaptures[requirement.scenario] ?? []
            if captures.isEmpty {
                try add(.error, .missingLifecycleCapture, subject: .lifecycle(requirement.scenario))
            } else if captures.count > 1 {
                try add(
                    .error,
                    .duplicateLifecycleCapture,
                    subject: .lifecycle(requirement.scenario),
                    discriminator: String(captures.count)
                )
            }
            if captures.count == 1,
                try inspectLifecycleCapture(captures[0])
            {
                completeLifecycleCount += 1
            }
        }
        for scenario in ToolbarAuditLifecycleScenario.allCases
        where lifecycleCaptures[scenario] != nil && !expectedLifecycle.contains(scenario) {
            try add(.warning, .unexpectedLifecycleCapture, subject: .lifecycle(scenario))
        }

        for requirement in try toolbarPresentationSorted(
            inventory.windowRequirements,
            by: { toolbarPresentationEnumRank($0.context) < toolbarPresentationEnumRank($1.context) },
            budget: budget
        ) {
            let captures = windowCaptures[requirement.context] ?? []
            if captures.isEmpty {
                try add(.error, .missingWindowCapture, subject: .window(requirement.context))
            } else if captures.count > 1 {
                try add(
                    .error,
                    .duplicateWindowCapture,
                    subject: .window(requirement.context),
                    discriminator: String(captures.count)
                )
            }
            if captures.count == 1,
                try inspectWindowCapture(captures[0])
            {
                completeWindowCount += 1
            }
        }
        for context in ToolbarAuditScreenshotContext.allCases
        where windowCaptures[context] != nil && !expectedWindows.contains(context) {
            try add(.warning, .unexpectedWindowCapture, subject: .window(context))
        }

        for expectation in inventory.auditContract.interactionExpectations {
            try budget.consume()
            let captures = interactionCaptures[ToolbarPresentationInteractionKey(expectation)] ?? []
            let subject = ToolbarPresentationEvidenceFindingSubject.lifecycle(expectation.scenario)
            if captures.isEmpty {
                try add(
                    .error,
                    .missingInteractionCapture,
                    subject: subject,
                    discriminator: expectation.actionID.rawValue
                )
            } else if captures.count > 1 {
                try add(
                    .error,
                    .duplicateInteractionCapture,
                    subject: subject,
                    discriminator: expectation.actionID.rawValue
                )
            } else if captures[0].controlID != expectation.controlID
                || captures[0].actionID != expectation.actionID
            {
                try add(
                    .error,
                    .interactionIdentityMismatch,
                    subject: subject,
                    discriminator: expectation.actionID.rawValue
                )
            } else if captures[0].outcome != expectation.outcome {
                try add(
                    .error,
                    .interactionOutcomeMismatch,
                    subject: subject,
                    discriminator: expectation.actionID.rawValue
                )
            } else {
                completeInteractionCount += 1
            }
        }
        for (key, captures) in interactionCaptures where !expectedInteractionKeys.contains(key) {
            try budget.consume(UInt64(captures.count) + 1)
            try add(
                .error,
                .unexpectedInteractionCapture,
                subject: .lifecycle(key.scenario),
                discriminator: key.actionID.rawValue
            )
        }

        try inspectAttachmentUse()
        let sortedFindings = try toolbarPresentationSorted(
            findings,
            by: { left, right in
                try toolbarPresentationFindingLess(left, right, budget: budget)
            },
            budget: budget
        ).transfer()
        return ToolbarPresentationEvidenceReport(
            formatVersion: ToolbarPresentationEvidenceWorkflow.reportFormatVersion,
            inventory: inventory.reference,
            evidence: evidence.reference,
            findings: sortedFindings,
            requiredLifecycleCaptureCount: inventory.lifecycleRequirements.count,
            completeLifecycleCaptureCount: completeLifecycleCount,
            requiredWindowCaptureCount: inventory.windowRequirements.count,
            completeWindowCaptureCount: completeWindowCount,
            requiredInteractionCaptureCount: inventory.auditContract.interactionExpectations.count,
            completeInteractionCaptureCount: completeInteractionCount
        )
    }

    private mutating func inspectLifecycleCapture(
        _ capture: ToolbarPresentationLifecycleCapture
    ) throws -> Bool {
        var valid = true
        if capture.origin == .callerAssertion {
            valid = false
            try add(.error, .assertionOnlyEvidence, subject: .lifecycle(capture.scenario))
        }
        if try !inspectItems(capture.items, subject: .lifecycle(capture.scenario)) {
            valid = false
        }
        if try !inspectControls(
            capture.controls,
            scenario: capture.scenario,
            subject: .lifecycle(capture.scenario)
        ) {
            valid = false
        }
        if try !inspectCompleteAccessibilityTree(
            capture.accessibilityTree,
            subject: .lifecycle(capture.scenario)
        ) {
            valid = false
        }
        if try !inspectFocusMovements(
            capture.focusMovements,
            tree: capture.accessibilityTree,
            controls: capture.controls,
            scenario: capture.scenario
        ) {
            valid = false
        }
        if try !inspectAttachment(
            id: capture.accessibilityAttachmentID,
            kind: .accessibilitySnapshot,
            scenario: capture.reference,
            provenance: capture.provenance,
            missingCode: .missingAccessibilityAttachment,
            subject: .lifecycle(capture.scenario)
        ) {
            valid = false
        }
        if try !inspectAccessibilityAttachmentPayload(
            id: capture.accessibilityAttachmentID,
            payload: ToolbarPresentationCanonicalEncoder.encodeAccessibilityAttachment(
                capture,
                limits: limits,
                budget: budget
            ),
            subject: .lifecycle(capture.scenario)
        ) {
            valid = false
        }
        return valid
    }

    private mutating func inspectWindowCapture(
        _ capture: ToolbarPresentationWindowCapture
    ) throws -> Bool {
        var valid = true
        if capture.origin == .callerAssertion {
            valid = false
            try add(.error, .assertionOnlyEvidence, subject: .window(capture.context))
        }
        if try !inspectItems(capture.items, subject: .window(capture.context)) {
            valid = false
        }
        if try !inspectControls(
            capture.controls,
            scenario: capture.lifecycleScenario,
            subject: .window(capture.context)
        ) {
            valid = false
        }
        if try !inspectCompleteAccessibilityTree(
            capture.accessibilityTree,
            subject: .window(capture.context)
        ) {
            valid = false
        }
        if try !inspectFocusMovements(
            capture.focusMovements,
            tree: capture.accessibilityTree,
            controls: capture.controls,
            scenario: capture.lifecycleScenario
        ) {
            valid = false
        }
        if try !inspectAttachment(
            id: capture.screenshotAttachmentID,
            kind: .screenshot,
            scenario: capture.reference,
            provenance: capture.provenance,
            missingCode: .missingScreenshotAttachment,
            subject: .window(capture.context)
        ) {
            valid = false
        }
        if try !inspectAttachment(
            id: capture.accessibilityAttachmentID,
            kind: .accessibilitySnapshot,
            scenario: capture.reference,
            provenance: capture.provenance,
            missingCode: .missingAccessibilityAttachment,
            subject: .window(capture.context)
        ) {
            valid = false
        }
        if try !inspectAccessibilityAttachmentPayload(
            id: capture.accessibilityAttachmentID,
            payload: ToolbarPresentationCanonicalEncoder.encodeAccessibilityAttachment(
                capture,
                limits: limits,
                budget: budget
            ),
            subject: .window(capture.context)
        ) {
            valid = false
        }
        return valid
    }

    private mutating func inspectItems(
        _ items: [ToolbarAuditItem],
        subject: ToolbarPresentationEvidenceFindingSubject
    ) throws -> Bool {
        let expected = inventory.auditContract.manifest.items
        guard items != expected else { return true }
        var valid = true
        if items.compactMap(\.command) != expected.compactMap(\.command) {
            valid = false
            try add(.error, .commandOrderMismatch, subject: subject)
        }
        if toolbarPresentationSeparatorBoundaries(items)
            != toolbarPresentationSeparatorBoundaries(expected)
        {
            valid = false
            try add(.error, .commandGroupingMismatch, subject: subject)
        }
        return valid
    }

    private mutating func inspectControls(
        _ controls: [ToolbarAuditControlObservation],
        scenario: ToolbarAuditLifecycleScenario,
        subject: ToolbarPresentationEvidenceFindingSubject
    ) throws -> Bool {
        var valid = true
        var observed: [ToolbarAuditCommand: [ToolbarAuditControlObservation]] = [:]
        for control in controls {
            try budget.consume()
            observed[control.command, default: []].append(control)
        }
        for command in inventory.auditContract.manifest.commands {
            try budget.consume()
            guard let requirement = requirementsByCommand[command] else { continue }
            let values = observed[command] ?? []
            guard values.count == 1 else {
                valid = false
                try add(
                    .error,
                    .missingControl,
                    subject: .command(command, lifecycle: scenario),
                    discriminator: String(values.count)
                )
                continue
            }
            if try !inspectControl(values[0], requirement: requirement, scenario: scenario) {
                valid = false
            }
        }
        for control in controls where !manifestCommands.contains(control.command) {
            valid = false
            try add(
                .error,
                .unexpectedControl,
                subject: .command(control.command, lifecycle: scenario)
            )
        }
        return valid
    }

    private mutating func inspectControl(
        _ observed: ToolbarAuditControlObservation,
        requirement: ToolbarAuditControlRequirement,
        scenario: ToolbarAuditLifecycleScenario
    ) throws -> Bool {
        var valid = true
        let subject = ToolbarPresentationEvidenceFindingSubject.command(
            requirement.command,
            lifecycle: scenario
        )
        if observed.id != requirement.id {
            valid = false
            try add(.error, .controlIdentityMismatch, subject: subject)
        }
        if observed.behavior.primaryActionID != requirement.behavior.primaryActionID
            || observed.behavior.secondary.actionIDs != requirement.behavior.secondary.actionIDs
        {
            valid = false
            try add(.error, .controlBehaviorMismatch, subject: subject)
        }
        if observed.tooltip != requirement.tooltip {
            valid = false
            try add(.error, .tooltipMismatch, subject: subject)
        }
        if observed.shortcut != requirement.shortcut {
            valid = false
            try add(.error, .shortcutMismatch, subject: subject)
        }
        let expectedAX = requirement.accessibility
        let observedAX = observed.accessibility
        if observedAX.identifier != expectedAX.identifier {
            valid = false
            try add(.error, .accessibilityIdentifierMismatch, subject: subject)
        }
        if observedAX.role != expectedAX.role {
            valid = false
            try add(.error, .accessibilityRoleMismatch, subject: subject)
        }
        if observedAX.label != expectedAX.label {
            valid = false
            try add(.error, .accessibilityLabelMismatch, subject: subject)
        }
        if observedAX.value != expectedAX.value {
            valid = false
            try add(.error, .accessibilityValueMismatch, subject: subject)
        }
        if observedAX.hint != expectedAX.hint {
            valid = false
            try add(.error, .accessibilityHintMismatch, subject: subject)
        }
        if observedAX.isKeyboardFocusable != expectedAX.isKeyboardFocusable {
            valid = false
            try add(.error, .accessibilityFocusMismatch, subject: subject)
        }
        if observedAX.checkedState != expectedAX.checkedState
            || observedAX.selectedState != expectedAX.selectedState
        {
            valid = false
            try add(.error, .accessibilityStateMismatch, subject: subject)
        }
        if observedAX.actions != expectedAX.actions {
            valid = false
            try add(.error, .accessibilityActionsMismatch, subject: subject)
        }
        let lifecycle = lifecycleByKey[
            ToolbarPresentationLifecycleKey(
                scenario: scenario,
                command: requirement.command,
                actionID: requirement.behavior.primaryActionID
            )
        ]
        if let lifecycle {
            if observed.availability != lifecycle.availability {
                valid = false
                try add(.error, .availabilityMismatch, subject: subject)
            }
            if observedAX.isEnabled != lifecycle.availability.isEnabled {
                valid = false
                try add(.error, .accessibilityEnabledStateMismatch, subject: subject)
            }
        }
        if try !inspectSecondaryActions(
            observed.behavior.secondary,
            requirement: requirement,
            scenario: scenario,
            subject: subject
        ) {
            valid = false
        }
        return valid
    }

    private mutating func inspectSecondaryActions(
        _ observed: ToolbarAuditSecondaryBehavior,
        requirement: ToolbarAuditControlRequirement,
        scenario: ToolbarAuditLifecycleScenario,
        subject: ToolbarPresentationEvidenceFindingSubject
    ) throws -> Bool {
        guard case .menu(let expectedActions) = requirement.behavior.secondary else {
            return observed.actionIDs.isEmpty
        }
        guard case .menu(let observedActions) = observed else { return false }
        var observedByID: [ToolbarAuditStableID: ToolbarAuditSecondaryAction] = [:]
        for action in observedActions {
            try budget.consume()
            guard observedByID.updateValue(action, forKey: action.id) == nil else {
                try add(.error, .controlBehaviorMismatch, subject: subject)
                return false
            }
        }
        var valid = true
        for expected in expectedActions {
            try budget.consume()
            guard let actual = observedByID[expected.id] else {
                valid = false
                continue
            }
            let lifecycle = lifecycleByKey[
                ToolbarPresentationLifecycleKey(
                    scenario: scenario,
                    command: requirement.command,
                    actionID: expected.id
                )
            ]
            if try !toolbarPresentationAXMatches(
                actual.accessibility,
                expected: expected.accessibility,
                expectedEnabled: lifecycle?.availability.isEnabled,
                budget: budget
            ) {
                valid = false
                try add(.error, .controlBehaviorMismatch, subject: subject)
            }
        }
        return valid
    }

    private mutating func inspectCompleteAccessibilityTree(
        _ tree: [ToolbarPresentationAXElementObservation],
        subject: ToolbarPresentationEvidenceFindingSubject
    ) throws -> Bool {
        var root: ToolbarPresentationAXElementObservation?
        for element in tree where element.parentIdentity == nil {
            try budget.consume()
            guard root == nil else {
                try add(.error, .incompleteAccessibilityTree, subject: subject)
                return false
            }
            root = element
        }
        guard root?.accessibility.role == .toolbar else {
            try add(.error, .incompleteAccessibilityTree, subject: subject)
            return false
        }
        var identifierCounts: [ToolbarAuditStableID: Int] = [:]
        var labelCounts: [String: Int] = [:]
        for element in tree {
            try budget.consume()
            identifierCounts[element.accessibility.identifier, default: 0] += 1
            if toolbarPresentationRoleRequiresUniqueLabel(element.accessibility.role) {
                labelCounts[element.accessibility.label, default: 0] += 1
            }
        }
        var valid = true
        if identifierCounts.values.contains(where: { $0 > 1 }) {
            valid = false
            try add(.error, .duplicateAccessibilityIdentifier, subject: subject)
        }
        if labelCounts.values.contains(where: { $0 > 1 }) {
            valid = false
            try add(.error, .duplicateAccessibilityLabel, subject: subject)
        }
        return valid
    }

    private mutating func inspectFocusMovements(
        _ movements: [ToolbarPresentationFocusMovement],
        tree: [ToolbarPresentationAXElementObservation],
        controls: [ToolbarAuditControlObservation],
        scenario: ToolbarAuditLifecycleScenario
    ) throws -> Bool {
        let elementsByIdentity = Dictionary(
            uniqueKeysWithValues: tree.map {
                ($0.elementIdentity, $0)
            })
        let movementsByControlAndTraversal = Dictionary(
            uniqueKeysWithValues: movements.map {
                (ToolbarPresentationFocusKey($0), $0)
            })
        let controlsByCommand = Dictionary(uniqueKeysWithValues: controls.map { ($0.command, $0) })
        var focusableControls: [ToolbarAuditControlObservation] = []
        for command in inventory.auditContract.manifest.commands {
            try budget.consume()
            guard let control = controlsByCommand[command],
                control.accessibility.isKeyboardFocusable,
                control.accessibility.isEnabled == true
            else { continue }
            focusableControls.append(control)
        }
        var valid = true
        let rootIdentity = tree.first(where: { $0.parentIdentity == nil })?.elementIdentity
        for (index, control) in focusableControls.enumerated() {
            let subject = ToolbarPresentationEvidenceFindingSubject.command(
                control.command,
                lifecycle: scenario
            )
            let movements: [ToolbarPresentationFocusMovement] = [
                ToolbarPresentationFocusTraversal.tabForward, .tabBackward
            ].compactMap {
                movementsByControlAndTraversal[
                    ToolbarPresentationFocusKey(controlID: control.id, traversal: $0)
                ]
            }
            guard movements.count == 2 else {
                valid = false
                try add(.error, .focusMovementMissing, subject: subject)
                continue
            }
            let expectedPrevious: AccessibilityStableID?
            let expectedNext: AccessibilityStableID?
            if focusableControls.count == 1 {
                expectedPrevious = rootIdentity
                expectedNext = rootIdentity
            } else {
                expectedPrevious = try toolbarPresentationElementIdentity(
                    matching: focusableControls[
                        (index + focusableControls.count - 1) % focusableControls.count
                    ].accessibility.identifier,
                    in: tree,
                    budget: budget
                )
                expectedNext = try toolbarPresentationElementIdentity(
                    matching: focusableControls[(index + 1) % focusableControls.count]
                        .accessibility.identifier,
                    in: tree,
                    budget: budget
                )
            }
            guard let target = elementsByIdentity[movements[0].toElementIdentity],
                try toolbarPresentationStringsEqual(
                    target.accessibility.identifier.rawValue,
                    control.accessibility.identifier.rawValue,
                    budget: budget
                ),
                target.accessibility.isKeyboardFocusable,
                target.accessibility.isEnabled == true,
                movements.allSatisfy({ $0.toElementIdentity == target.elementIdentity }),
                movements.allSatisfy({ $0.fromElementIdentity != target.elementIdentity }),
                movementsByControlAndTraversal[
                    ToolbarPresentationFocusKey(
                        controlID: control.id,
                        traversal: .tabForward
                    )
                ]?.fromElementIdentity == expectedPrevious,
                movementsByControlAndTraversal[
                    ToolbarPresentationFocusKey(
                        controlID: control.id,
                        traversal: .tabBackward
                    )
                ]?.fromElementIdentity == expectedNext
            else {
                valid = false
                try add(.error, .focusIdentityMismatch, subject: subject)
                continue
            }
        }
        let toolbarMovementCount = movements.lazy.filter {
            $0.traversal == .tabForward || $0.traversal == .tabBackward
        }.count
        if toolbarMovementCount != focusableControls.count * 2 { valid = false }
        return valid
    }

    private mutating func inspectAttachment(
        id: AccessibilityStableID,
        kind: ToolbarPresentationEvidenceAttachmentKind,
        scenario: AccessibilityEvidenceRevisionReference,
        provenance: AccessibilityEvidenceCaptureProvenance,
        missingCode: ToolbarPresentationEvidenceFindingCode,
        subject: ToolbarPresentationEvidenceFindingSubject
    ) throws -> Bool {
        var attachments: [ToolbarPresentationEvidenceAttachment] = []
        for attachment in evidence.attachments {
            try budget.consume()
            if attachment.id == id { attachments.append(attachment) }
        }
        guard attachments.count == 1 else {
            try add(.error, missingCode, subject: subject, discriminator: id.rawValue)
            return false
        }
        let attachment = attachments[0]
        var valid = true
        if attachment.kind != kind {
            valid = false
            try add(.error, .attachmentKindMismatch, subject: subject, discriminator: id.rawValue)
        }
        if attachment.scenario != scenario
            || attachment.manifest != evidence.manifest
            || attachment.layout != evidence.layout
            || attachment.provenance != provenance
        {
            valid = false
            try add(
                .error,
                .attachmentProvenanceMismatch,
                subject: subject,
                discriminator: id.rawValue
            )
        }
        return valid
    }

    private mutating func inspectAttachmentUse() throws {
        var counts: [AccessibilityStableID: Int] = [:]
        var contentDigests: [[UInt8]: [AccessibilityStableID]] = [:]
        for capture in evidence.lifecycleCaptures {
            try budget.consume()
            counts[capture.accessibilityAttachmentID, default: 0] += 1
        }
        for capture in evidence.windowCaptures {
            try budget.consume()
            counts[capture.screenshotAttachmentID, default: 0] += 1
            counts[capture.accessibilityAttachmentID, default: 0] += 1
        }
        for attachment in evidence.attachments {
            try budget.consume()
            contentDigests[attachment.contentSHA256, default: []].append(attachment.id)
            let count = counts[attachment.id, default: 0]
            if count == 0 {
                try add(.warning, .orphanAttachment, subject: .attachment(attachment.id))
            } else if count > 1 {
                try add(
                    .error,
                    .reusedAttachment,
                    subject: .attachment(attachment.id),
                    discriminator: String(count)
                )
            }
        }
        for ids in contentDigests.values where ids.count > 1 {
            for id in ids {
                try add(
                    .error,
                    .reusedAttachmentDigest,
                    subject: .attachment(id),
                    discriminator: String(ids.count)
                )
            }
        }
        var screenshotDigestsByContext: [ToolbarAuditScreenshotContext: [UInt8]] = [:]
        for capture in evidence.windowCaptures where screenshotDigestsByContext[capture.context] == nil {
            try budget.consume()
            screenshotDigestsByContext[capture.context] =
                evidence.attachments.first {
                    $0.id == capture.screenshotAttachmentID
                }?.contentSHA256
        }
        if screenshotDigestsByContext.count == ToolbarAuditScreenshotContext.allCases.count,
            Set(screenshotDigestsByContext.values).count != screenshotDigestsByContext.count
        {
            for context in ToolbarAuditScreenshotContext.allCases {
                try add(.error, .screenshotContextMismatch, subject: .window(context))
            }
        }
    }

    private mutating func inspectAccessibilityAttachmentPayload(
        id: AccessibilityStableID,
        payload: ToolbarPresentationRetainedData,
        subject: ToolbarPresentationEvidenceFindingSubject
    ) throws -> Bool {
        var attachment: ToolbarPresentationEvidenceAttachment?
        for candidate in evidence.attachments {
            try budget.consume()
            if candidate.id == id { attachment = candidate }
        }
        guard let attachment, attachment.kind == .accessibilitySnapshot else { return false }
        let digest = try toolbarPresentationSHA256(payload.data, budget: budget)
        guard attachment.byteCount == payload.data.count, attachment.sha256 == digest else {
            try add(
                .error,
                .attachmentProvenanceMismatch,
                subject: subject,
                discriminator: id.rawValue
            )
            return false
        }
        return true
    }

    private mutating func add(
        _ severity: ToolbarPresentationEvidenceFindingSeverity,
        _ code: ToolbarPresentationEvidenceFindingCode,
        subject: ToolbarPresentationEvidenceFindingSubject,
        discriminator: String = ""
    ) throws {
        try budget.consume()
        let finding = try ToolbarPresentationEvidenceFinding(
            severity: severity,
            code: code,
            subject: subject,
            discriminator: discriminator,
            budget: budget
        )
        guard findingIDs.insert(finding.id).inserted else { return }
        guard findings.count < limits.maximumFindings else {
            throw ToolbarPresentationEvidenceWorkflowError.findingLimitExceeded(
                maximum: limits.maximumFindings
            )
        }
        try budget.consumeMemory(UInt64(Self.findingStorageStride))
        findingStorageCharge += UInt64(Self.findingStorageStride)
        findings.append(finding)
    }
}

private enum ToolbarPresentationCanonicalEncoder {
    static func encodeAccessibilityAttachment(
        _ capture: ToolbarPresentationLifecycleCapture,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws -> ToolbarPresentationRetainedData {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendString("lifecycle-v4")
        try writer.appendString(capture.scenario.rawValue)
        try writer.appendReference(capture.reference)
        try writer.appendReference(capture.manifest)
        try writer.appendReference(capture.layout)
        try writer.appendProvenance(capture.provenance)
        try writer.appendString(capture.origin.rawValue)
        try writer.appendItems(capture.items)
        try writer.appendCanonicalControls(capture.controls)
        try writer.appendCanonicalInteractions(capture.interactions)
        try writer.appendCanonicalAccessibilityTree(capture.accessibilityTree)
        try writer.appendCanonicalFocusMovements(capture.focusMovements)
        try writer.appendCaptureManifest(capture.captureManifest, includeAuthentication: true)
        return writer.finish()
    }

    static func encodeAccessibilityAttachment(
        _ capture: ToolbarPresentationWindowCapture,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws -> ToolbarPresentationRetainedData {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendString("window-v4")
        try writer.appendString(capture.context.rawValue)
        try writer.appendReference(capture.reference)
        try writer.appendString(capture.lifecycleScenario.rawValue)
        try writer.appendReference(capture.manifest)
        try writer.appendReference(capture.layout)
        try writer.appendProvenance(capture.provenance)
        try writer.appendString(capture.origin.rawValue)
        try writer.appendItems(capture.items)
        try writer.appendCanonicalControls(capture.controls)
        try writer.appendCanonicalInteractions(capture.interactions)
        try writer.appendCanonicalAccessibilityTree(capture.accessibilityTree)
        try writer.appendCanonicalFocusMovements(capture.focusMovements)
        try writer.appendCaptureManifest(capture.captureManifest, includeAuthentication: true)
        return writer.finish()
    }

    static func encodeCaptureState(
        _ capture: ToolbarPresentationLifecycleCapture,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws -> ToolbarPresentationRetainedData {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendString("lifecycle-state-v4")
        try writer.appendString(capture.scenario.rawValue)
        try writer.appendReference(capture.reference)
        try writer.appendReference(capture.manifest)
        try writer.appendReference(capture.layout)
        try writer.appendProvenance(capture.provenance)
        try writer.appendString(capture.origin.rawValue)
        try writer.appendItems(capture.items)
        try writer.appendCanonicalControls(capture.controls)
        try writer.appendCanonicalInteractions(capture.interactions)
        try writer.appendCanonicalFocusMovements(capture.focusMovements)
        try writer.appendString(capture.accessibilityAttachmentID.rawValue)
        try writer.appendString(capture.source)
        return writer.finish()
    }

    static func encodeCaptureState(
        _ capture: ToolbarPresentationWindowCapture,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws -> ToolbarPresentationRetainedData {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendString("window-state-v4")
        try writer.appendString(capture.context.rawValue)
        try writer.appendReference(capture.reference)
        try writer.appendString(capture.lifecycleScenario.rawValue)
        try writer.appendReference(capture.manifest)
        try writer.appendReference(capture.layout)
        try writer.appendProvenance(capture.provenance)
        try writer.appendString(capture.origin.rawValue)
        try writer.appendItems(capture.items)
        try writer.appendCanonicalControls(capture.controls)
        try writer.appendCanonicalInteractions(capture.interactions)
        try writer.appendCanonicalFocusMovements(capture.focusMovements)
        try writer.appendString(capture.screenshotAttachmentID.rawValue)
        try writer.appendString(capture.accessibilityAttachmentID.rawValue)
        try writer.appendString(capture.source)
        return writer.finish()
    }

    static func encodeAccessibilityTree(
        _ tree: [ToolbarPresentationAXElementObservation],
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws -> ToolbarPresentationRetainedData {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendString("toolbar-ax-tree-v4")
        try writer.appendCanonicalAccessibilityTree(tree)
        return writer.finish()
    }

    static func encodeCaptureManifest(
        _ manifest: ToolbarPresentationCaptureManifest,
        includeAuthentication: Bool,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws -> ToolbarPresentationRetainedData {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendCaptureManifest(
            manifest,
            includeAuthentication: includeAuthentication
        )
        return writer.finish()
    }

    static func encodeInventory(
        _ inventory: ToolbarPresentationEvidenceInventory,
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) throws -> ToolbarPresentationRetainedData {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendReference(inventory.app)
        try writer.appendReference(inventory.build)
        try writer.appendBuildBinding(inventory.buildBinding)
        try writer.appendReference(inventory.reference)
        try writer.appendReference(inventory.manifestReference)
        try writer.appendReference(inventory.layout.reference)
        try writer.appendConfigurationReference(inventory.layout.configurationReference)
        try writer.appendUInt64(inventory.layout.manifestRevision.rawValue)
        try writer.appendConfiguration(inventory.layout.configuration)
        try writer.appendUInt64(inventory.auditContract.revision.rawValue)
        try writer.appendManifest(inventory.auditContract.manifest)

        let controls = try toolbarPresentationSorted(
            inventory.auditContract.controls,
            by: { toolbarPresentationEnumRank($0.command) < toolbarPresentationEnumRank($1.command) },
            budget: budget
        )
        try writer.appendCount(controls.count)
        for control in controls { try writer.appendRequirement(control) }

        let lifecycle = try toolbarPresentationSorted(
            inventory.auditContract.lifecycleExpectations,
            by: { left, right in
                try toolbarPresentationLifecycleLess(left, right, budget: budget)
            },
            budget: budget
        )
        try writer.appendCount(lifecycle.count)
        for expectation in lifecycle { try writer.appendLifecycleExpectation(expectation) }

        let interactions = try toolbarPresentationSorted(
            inventory.auditContract.interactionExpectations,
            by: { left, right in
                try toolbarPresentationInteractionLess(left, right, budget: budget)
            },
            budget: budget
        )
        try writer.appendCount(interactions.count)
        for expectation in interactions { try writer.appendInteractionExpectation(expectation) }

        let screenshots = try toolbarPresentationSorted(
            inventory.auditContract.screenshotExpectations,
            by: { toolbarPresentationEnumRank($0.context) < toolbarPresentationEnumRank($1.context) },
            budget: budget
        )
        try writer.appendCount(screenshots.count)
        for expectation in screenshots {
            try writer.appendString(expectation.context.rawValue)
            try writer.appendBool(expectation.requiresAccessibilitySidecar)
        }

        let semanticActions = try toolbarPresentationSorted(
            inventory.semanticActionBindings,
            by: { left, right in
                try toolbarPresentationStringsCompare(
                    left.actionID.rawValue,
                    right.actionID.rawValue,
                    budget: budget
                ) < 0
            },
            budget: budget
        )
        try writer.appendCount(semanticActions.count)
        for binding in semanticActions {
            try writer.appendString(binding.actionID.rawValue)
            try writer.appendString(binding.command.rawValue)
        }

        let lifecycleRequirements = try toolbarPresentationSorted(
            inventory.lifecycleRequirements,
            by: { toolbarPresentationEnumRank($0.scenario) < toolbarPresentationEnumRank($1.scenario) },
            budget: budget
        )
        try writer.appendCount(lifecycleRequirements.count)
        for requirement in lifecycleRequirements {
            try writer.appendString(requirement.scenario.rawValue)
            try writer.appendReference(requirement.reference)
            try writer.appendCount(requirement.commandState.bindings.count)
            for binding in requirement.commandState.bindings {
                try writer.appendString(binding.command.rawValue)
                try writer.appendBool(binding.isEnabled)
            }
        }
        let windowRequirements = try toolbarPresentationSorted(
            inventory.windowRequirements,
            by: { toolbarPresentationEnumRank($0.context) < toolbarPresentationEnumRank($1.context) },
            budget: budget
        )
        try writer.appendCount(windowRequirements.count)
        for requirement in windowRequirements {
            try writer.appendString(requirement.context.rawValue)
            try writer.appendReference(requirement.reference)
            try writer.appendString(requirement.lifecycleScenario.rawValue)
        }
        return writer.finish()
    }

    static func appendEvidence(
        _ evidence: ToolbarPresentationEvidenceBundle,
        to writer: ToolbarPresentationWriter
    ) throws {
        try writer.appendReference(evidence.reference)
        try writer.appendReference(evidence.app)
        try writer.appendReference(evidence.build)
        try writer.appendBuildBinding(evidence.buildBinding)
        try writer.appendReference(evidence.inventory)
        try writer.appendReference(evidence.manifest)
        try writer.appendReference(evidence.layout)

        let lifecycleCaptures = try toolbarPresentationCanonicalLifecycleCaptures(
            evidence.lifecycleCaptures,
            limits: writer.limits,
            budget: writer.budget
        )
        try writer.appendCount(lifecycleCaptures.count)
        for capture in lifecycleCaptures { try writer.appendLifecycleCapture(capture) }

        let windowCaptures = try toolbarPresentationCanonicalWindowCaptures(
            evidence.windowCaptures,
            limits: writer.limits,
            budget: writer.budget
        )
        try writer.appendCount(windowCaptures.count)
        for capture in windowCaptures { try writer.appendWindowCapture(capture) }

        let attachments = try toolbarPresentationSorted(
            evidence.attachments,
            by: { left, right in
                try toolbarPresentationStringsCompare(
                    left.id.rawValue,
                    right.id.rawValue,
                    budget: writer.budget
                ) < 0
            },
            budget: writer.budget
        )
        try writer.appendCount(attachments.count)
        for attachment in attachments { try writer.appendAttachment(attachment) }
    }
}

private final class ToolbarPresentationWriter {
    fileprivate let limits: ToolbarPresentationEvidenceLimits
    fileprivate let budget: ToolbarPresentationWorkBudget
    private(set) var data = Data()
    private var retainedByteCharge: UInt64 = 0

    init(
        limits: ToolbarPresentationEvidenceLimits,
        budget: ToolbarPresentationWorkBudget
    ) {
        self.limits = limits
        self.budget = budget
    }

    deinit { budget.releaseMemory(retainedByteCharge) }

    func appendRaw(_ value: Data) throws {
        guard value.count <= limits.maximumArchiveBytes - data.count else {
            throw ToolbarPresentationEvidenceWorkflowError.archiveTooLarge(
                maximumBytes: limits.maximumArchiveBytes
            )
        }
        try budget.consume(UInt64(value.count) + 1)
        try budget.consumeMemory(UInt64(value.count))
        retainedByteCharge += UInt64(value.count)
        data.append(value)
    }

    func appendRaw(_ value: [UInt8]) throws {
        guard value.count <= limits.maximumArchiveBytes - data.count else {
            throw ToolbarPresentationEvidenceWorkflowError.archiveTooLarge(
                maximumBytes: limits.maximumArchiveBytes
            )
        }
        try budget.consume(UInt64(value.count) + 1)
        try budget.consumeMemory(UInt64(value.count))
        retainedByteCharge += UInt64(value.count)
        data.append(contentsOf: value)
    }

    func appendUInt8(_ value: UInt8) throws {
        try appendRaw(Data([value]))
    }

    func appendUInt16(_ value: UInt16) throws {
        let bigEndian = value.bigEndian
        try appendRaw(withUnsafeBytes(of: bigEndian) { Data($0) })
    }

    func appendUInt64(_ value: UInt64) throws {
        let bigEndian = value.bigEndian
        try appendRaw(withUnsafeBytes(of: bigEndian) { Data($0) })
    }

    func appendBool(_ value: Bool) throws {
        try appendUInt8(value ? 1 : 0)
    }

    func appendCount(_ value: Int) throws {
        guard value >= 0 else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.reference)
        }
        try appendUInt64(UInt64(value))
    }

    func appendString(_ value: String) throws {
        let count = toolbarPresentationBoundedUTF8Count(
            value,
            maximum: limits.maximumStringUTF8Bytes
        )
        guard count <= limits.maximumStringUTF8Bytes else {
            throw ToolbarPresentationEvidenceWorkflowError.stringTooLarge(
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        try appendCount(count)
        guard count <= limits.maximumArchiveBytes - data.count else {
            throw ToolbarPresentationEvidenceWorkflowError.archiveTooLarge(
                maximumBytes: limits.maximumArchiveBytes
            )
        }
        try budget.consume(UInt64(count) + 1)
        try budget.consumeMemory(UInt64(count))
        retainedByteCharge += UInt64(count)
        data.append(contentsOf: value.utf8)
    }

    func appendOptionalString(_ value: String?) throws {
        guard let value else {
            try appendBool(false)
            return
        }
        try appendBool(true)
        try appendString(value)
    }

    func appendReference(_ value: AccessibilityEvidenceRevisionReference) throws {
        try appendString(value.id.rawValue)
        try appendUInt64(value.revision.rawValue)
    }

    func appendBuildBinding(_ value: AccessibilityEvidenceBuildBinding) throws {
        try appendRaw(value.artifactSHA256)
        try appendRaw(value.signingIdentitySHA256)
    }

    func appendConfigurationReference(
        _ value: ToolbarCustomizationWorkflow.ConfigurationReference
    ) throws {
        try appendString(value.identity.rawValue.uuidString.lowercased())
        try appendUInt64(value.revision.rawValue)
    }

    func appendConfiguration(_ value: ToolbarConfiguration) throws {
        try appendUInt64(UInt64(value.schemaVersion))
        try appendString(value.visibility.rawValue)
        try appendString(value.size.rawValue)
        try appendItems(value.items)
    }

    func appendManifest(_ value: ToolbarAuditManifest) throws {
        try appendUInt64(value.revision.rawValue)
        try appendItems(value.items)
    }

    func appendItems(_ values: [ToolbarAuditItem]) throws {
        try appendCount(values.count)
        for value in values {
            switch value {
            case .command(let command):
                try appendUInt8(0)
                try appendString(command.rawValue)
            case .separator:
                try appendUInt8(1)
            }
        }
    }

    func appendRequirement(_ value: ToolbarAuditControlRequirement) throws {
        try appendString(value.id.rawValue)
        try appendString(value.command.rawValue)
        try appendBehavior(value.behavior)
        try appendString(value.tooltip)
        try appendShortcut(value.shortcut)
        try appendAX(value.accessibility)
    }

    func appendObservation(_ value: ToolbarAuditControlObservation) throws {
        try appendString(value.id.rawValue)
        try appendString(value.command.rawValue)
        try appendBehavior(value.behavior)
        try appendOptionalString(value.tooltip)
        try appendShortcut(value.shortcut)
        try appendAX(value.accessibility)
        try appendAvailability(value.availability)
    }

    func appendCanonicalControls(
        _ values: [ToolbarAuditControlObservation]
    ) throws {
        let controls = try toolbarPresentationSorted(
            values,
            by: { toolbarPresentationEnumRank($0.command) < toolbarPresentationEnumRank($1.command) },
            budget: budget
        )
        try appendCount(controls.count)
        for control in controls { try appendObservation(control) }
    }

    func appendInteraction(_ value: ToolbarPresentationInteractionCapture) throws {
        try appendString(value.scenario.rawValue)
        try appendString(value.controlID.rawValue)
        try appendString(value.elementIdentity.rawValue)
        try appendString(value.actionID.rawValue)
        try appendString(value.invocation.rawValue)
        try appendOutcome(value.outcome)
        try appendString(value.source)
    }

    func appendCanonicalInteractions(
        _ values: [ToolbarPresentationInteractionCapture]
    ) throws {
        let interactions = try toolbarPresentationSorted(
            values,
            by: { left, right in
                try toolbarPresentationInteractionCaptureLess(left, right, budget: budget)
            },
            budget: budget
        )
        try appendCount(interactions.count)
        for interaction in interactions { try appendInteraction(interaction) }
    }

    func appendRect(_ value: ToolbarPresentationEvidenceRect) throws {
        try appendInt64(Int64(value.x))
        try appendInt64(Int64(value.y))
        try appendInt64(Int64(value.width))
        try appendInt64(Int64(value.height))
    }

    func appendAXElement(_ value: ToolbarPresentationAXElementObservation) throws {
        try appendString(value.elementIdentity.rawValue)
        try appendOptionalString(value.parentIdentity?.rawValue)
        try appendCount(value.siblingIndex)
        try appendRect(value.frame)
        try appendAX(value.accessibility)
    }

    func appendCanonicalAccessibilityTree(
        _ values: [ToolbarPresentationAXElementObservation]
    ) throws {
        let elements = try toolbarPresentationSorted(
            values,
            by: { left, right in
                try toolbarPresentationStringsCompare(
                    left.elementIdentity.rawValue,
                    right.elementIdentity.rawValue,
                    budget: budget
                ) < 0
            },
            budget: budget
        )
        try appendCount(elements.count)
        for element in elements { try appendAXElement(element) }
    }

    func appendFocusMovement(_ value: ToolbarPresentationFocusMovement) throws {
        try appendString(value.controlID.rawValue)
        try appendString(value.fromElementIdentity.rawValue)
        try appendString(value.toElementIdentity.rawValue)
        try appendString(value.traversal.rawValue)
    }

    func appendCanonicalFocusMovements(
        _ values: [ToolbarPresentationFocusMovement]
    ) throws {
        let movements = try toolbarPresentationSorted(
            values,
            by: { left, right in
                try toolbarPresentationFocusMovementLess(left, right, budget: budget)
            },
            budget: budget
        )
        try appendCount(movements.count)
        for movement in movements { try appendFocusMovement(movement) }
    }

    func appendCaptureContext(_ value: ToolbarPresentationCaptureContext) throws {
        switch value {
        case .lifecycle(let scenario):
            try appendUInt8(0)
            try appendString(scenario.rawValue)
        case .window(let context, let lifecycle):
            try appendUInt8(1)
            try appendString(context.rawValue)
            try appendString(lifecycle.rawValue)
        }
    }

    func appendCaptureManifest(
        _ value: ToolbarPresentationCaptureManifest,
        includeAuthentication: Bool
    ) throws {
        try appendString("toolbar-capture-manifest-v4")
        try appendCount(value.formatVersion)
        try appendReference(value.collector)
        try appendReference(value.capture)
        try appendString(value.origin.rawValue)
        try appendReference(value.app)
        try appendReference(value.build)
        try appendBuildBinding(value.buildBinding)
        try appendReference(value.inventory)
        try appendReference(value.manifest)
        try appendReference(value.layout)
        try appendConfigurationReference(value.configuration)
        try appendUInt64(value.contractRevision.rawValue)
        try appendUInt64(value.manifestRevision.rawValue)
        try appendCaptureContext(value.context)
        try appendRect(value.geometry.window)
        try appendRect(value.geometry.toolbar)
        try appendInt64(Int64(value.geometry.backingScaleThousandths))
        try appendBool(value.windowState.isVisible)
        try appendBool(value.windowState.isKeyWindow)
        try appendBool(value.windowState.isMainWindow)
        try appendBool(value.windowState.isMiniaturized)
        try appendBool(value.windowState.isFullScreen)
        try appendRaw(value.stateSHA256)
        try appendRaw(value.accessibilityTreeSHA256)
        if let screenshot = value.screenshotPixelSHA256 {
            try appendBool(true)
            try appendRaw(screenshot)
        } else {
            try appendBool(false)
        }
        try appendBool(value.accessibilityTreeIsComplete)
        try appendReference(value.renderingPipeline)
        try appendString(value.renderingImplementation)
        try appendOptionalString(value.screenshotAttachmentID?.rawValue)
        try appendOptionalString(value.screenshotMediaType)
        try appendOptionalString(value.screenshotSource)
        if let digest = value.screenshotEncodedSHA256 {
            try appendBool(true)
            try appendRaw(digest)
        } else {
            try appendBool(false)
        }
        if includeAuthentication {
            try appendCount(value.authentication.count)
            try appendRaw(value.authentication)
        }
    }

    func appendBehavior(_ value: ToolbarAuditControlBehavior) throws {
        try appendString(value.primaryActionID.rawValue)
        switch value.secondary {
        case .none:
            try appendUInt8(0)
        case .menu(let actions):
            try appendUInt8(1)
            try appendCount(actions.count)
            for action in actions {
                try appendString(action.id.rawValue)
                try appendAX(action.accessibility)
            }
        }
    }

    func appendShortcut(_ value: ToolbarAuditShortcut?) throws {
        guard let value else {
            try appendBool(false)
            return
        }
        try appendBool(true)
        try appendString(value.key)
        let modifiers = AccessibilityKeyboardModifier.allCases.filter(value.modifiers.contains)
        try appendCount(modifiers.count)
        for modifier in modifiers { try appendString(modifier.rawValue) }
        try appendString(value.display)
    }

    func appendAX(_ value: ToolbarAuditAXMetadata) throws {
        try appendString(value.identifier.rawValue)
        try appendString(value.role.rawValue)
        try appendString(value.label)
        try appendOptionalString(value.value)
        try appendString(value.hint)
        if let isEnabled = value.isEnabled {
            try appendUInt8(isEnabled ? 2 : 1)
        } else {
            try appendUInt8(0)
        }
        try appendString(value.checkedState.rawValue)
        try appendString(value.selectedState.rawValue)
        try appendBool(value.isKeyboardFocusable)
        let actions = AccessibilitySemanticActionKind.allCases.filter(value.actions.contains)
        try appendCount(actions.count)
        for action in actions { try appendString(action.rawValue) }
    }

    func appendAvailability(_ value: ToolbarAuditAvailability) throws {
        switch value {
        case .enabled:
            try appendUInt8(0)
        case .disabled(let reason):
            try appendUInt8(1)
            try appendString(reason.rawValue)
        }
    }

    func appendLifecycleExpectation(
        _ value: ToolbarAuditLifecycleExpectation
    ) throws {
        try appendString(value.scenario.rawValue)
        try appendString(value.command.rawValue)
        try appendString(value.actionID.rawValue)
        try appendAvailability(value.availability)
    }

    func appendInteractionExpectation(
        _ value: ToolbarAuditInteractionExpectation
    ) throws {
        try appendString(value.scenario.rawValue)
        try appendString(value.controlID.rawValue)
        try appendString(value.actionID.rawValue)
        try appendString(value.invocation.rawValue)
        try appendOutcome(value.outcome)
    }

    func appendOutcome(_ value: ToolbarAuditInteractionOutcome) throws {
        switch value {
        case .invoked(let actionID):
            try appendUInt8(0)
            try appendString(actionID.rawValue)
        case .menuPresented(let actionIDs):
            try appendUInt8(1)
            try appendCount(actionIDs.count)
            for id in actionIDs { try appendString(id.rawValue) }
        case .blocked:
            try appendUInt8(2)
        case .noOp:
            try appendUInt8(3)
        case .failed(let code):
            try appendUInt8(4)
            try appendString(code.rawValue)
        }
    }

    func appendProvenance(_ value: AccessibilityEvidenceCaptureProvenance) throws {
        try appendUInt64(value.capturedAtUnixMilliseconds)
        try appendCount(value.runNonce.count)
        try appendRaw(value.runNonce)
        try appendReference(value.collector)
        try appendReference(value.build)
        try appendBuildBinding(value.buildBinding)
    }

    func appendLifecycleCapture(_ value: ToolbarPresentationLifecycleCapture) throws {
        try appendString(value.scenario.rawValue)
        try appendReference(value.reference)
        try appendReference(value.manifest)
        try appendReference(value.layout)
        try appendProvenance(value.provenance)
        try appendString(value.origin.rawValue)
        try appendItems(value.items)
        try appendCanonicalControls(value.controls)
        try appendCanonicalInteractions(value.interactions)
        try appendCanonicalAccessibilityTree(value.accessibilityTree)
        try appendCanonicalFocusMovements(value.focusMovements)
        try appendCaptureManifest(value.captureManifest, includeAuthentication: true)
        try appendString(value.accessibilityAttachmentID.rawValue)
        try appendString(value.source)
    }

    func appendWindowCapture(_ value: ToolbarPresentationWindowCapture) throws {
        try appendString(value.context.rawValue)
        try appendReference(value.reference)
        try appendString(value.lifecycleScenario.rawValue)
        try appendReference(value.manifest)
        try appendReference(value.layout)
        try appendProvenance(value.provenance)
        try appendString(value.origin.rawValue)
        try appendItems(value.items)
        try appendCanonicalControls(value.controls)
        try appendCanonicalInteractions(value.interactions)
        try appendCanonicalAccessibilityTree(value.accessibilityTree)
        try appendCanonicalFocusMovements(value.focusMovements)
        try appendCaptureManifest(value.captureManifest, includeAuthentication: true)
        try appendString(value.screenshotAttachmentID.rawValue)
        try appendString(value.accessibilityAttachmentID.rawValue)
        try appendString(value.source)
    }

    func appendAttachment(_ value: ToolbarPresentationEvidenceAttachment) throws {
        try appendString(value.id.rawValue)
        try appendString(value.kind.rawValue)
        try appendReference(value.scenario)
        try appendReference(value.manifest)
        try appendReference(value.layout)
        try appendProvenance(value.provenance)
        try appendString(value.mediaType)
        try appendCount(value.byteCount)
        try appendRaw(value.sha256)
        try appendRaw(value.contentSHA256)
        try appendRaw(value.captureManifestSHA256)
        try appendString(value.source)
    }

    func appendInt64(_ value: Int64) throws {
        try appendUInt64(UInt64(bitPattern: value))
    }

    func finish() -> ToolbarPresentationRetainedData {
        let result = ToolbarPresentationRetainedData(
            data: data,
            retainedByteCharge: retainedByteCharge,
            budget: budget
        )
        data = Data()
        retainedByteCharge = 0
        return result
    }
}

private final class ToolbarPresentationRetainedData {
    let data: Data
    private let budget: ToolbarPresentationWorkBudget
    private var retainedByteCharge: UInt64

    init(
        data: Data,
        retainedByteCharge: UInt64,
        budget: ToolbarPresentationWorkBudget
    ) {
        self.data = data
        self.retainedByteCharge = retainedByteCharge
        self.budget = budget
    }

    deinit { budget.releaseMemory(retainedByteCharge) }

    func transfer() -> Data {
        retainedByteCharge = 0
        return data
    }
}

private final class ToolbarPresentationRetainedArray<Element>: RandomAccessCollection {
    typealias Index = Int

    let values: [Element]
    private let budget: ToolbarPresentationWorkBudget
    private var retainedByteCharge: UInt64

    init(
        values: [Element],
        retainedByteCharge: UInt64,
        budget: ToolbarPresentationWorkBudget
    ) {
        self.values = values
        self.retainedByteCharge = retainedByteCharge
        self.budget = budget
    }

    deinit { budget.releaseMemory(retainedByteCharge) }

    var startIndex: Int { values.startIndex }
    var endIndex: Int { values.endIndex }
    subscript(position: Int) -> Element { values[position] }

    func transfer() -> [Element] {
        retainedByteCharge = 0
        return values
    }
}

private final class ToolbarPresentationWorkBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let maximum: UInt64
    private let maximumMemory: UInt64
    private let interval: UInt64
    private let cancellationCheck: ToolbarPresentationEvidenceWorkflow.CancellationCheck
    fileprivate let maximumStringUTF8Bytes: Int
    fileprivate let maximumTotalStringUTF8Bytes: Int
    private var consumed: UInt64 = 0
    private var consumedMemory: UInt64 = 0
    private var sinceCancellationCheck: UInt64 = 0

    init(
        limits: ToolbarPresentationEvidenceLimits,
        cancellationCheck: @escaping ToolbarPresentationEvidenceWorkflow.CancellationCheck
    ) throws {
        maximum = limits.maximumWorkUnits
        maximumMemory = limits.maximumAggregateMemoryBytes
        interval = UInt64(limits.cancellationCheckInterval)
        maximumStringUTF8Bytes = limits.maximumStringUTF8Bytes
        maximumTotalStringUTF8Bytes = limits.maximumTotalStringUTF8Bytes
        self.cancellationCheck = cancellationCheck
    }

    func consume(_ amount: UInt64 = 1) throws {
        lock.lock()
        let (next, overflow) = consumed.addingReportingOverflow(amount)
        guard !overflow, next <= maximum else {
            lock.unlock()
            throw ToolbarPresentationEvidenceWorkflowError.workLimitExceeded(maximum: maximum)
        }
        consumed = next
        let (nextInterval, intervalOverflow) = sinceCancellationCheck.addingReportingOverflow(amount)
        sinceCancellationCheck = intervalOverflow ? interval : nextInterval
        let shouldCheckCancellation = sinceCancellationCheck >= interval
        if shouldCheckCancellation {
            sinceCancellationCheck = 0
        }
        lock.unlock()
        if shouldCheckCancellation { try checkCancellation() }
    }

    var remainingWorkUnits: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return maximum - consumed
    }

    func checkCancellation() throws {
        if cancellationCheck() { throw ToolbarPresentationEvidenceWorkflowError.cancelled }
    }

    func consumeMemory(_ amount: UInt64) throws {
        lock.lock()
        defer { lock.unlock() }
        let (next, overflow) = consumedMemory.addingReportingOverflow(amount)
        guard !overflow, next <= maximumMemory else {
            throw ToolbarPresentationEvidenceWorkflowError.aggregateMemoryExceeded(
                maximumBytes: maximumMemory
            )
        }
        consumedMemory = next
    }

    func releaseMemory(_ amount: UInt64) {
        lock.lock()
        consumedMemory = amount > consumedMemory ? 0 : consumedMemory - amount
        lock.unlock()
    }

    func finish() throws { try checkCancellation() }
}

private final class ToolbarPresentationNestedWorkCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: UInt64 = 0

    var value: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() throws {
        lock.lock()
        let (next, overflow) = count.addingReportingOverflow(1)
        guard !overflow else {
            lock.unlock()
            throw ToolbarPresentationEvidenceWorkflowError.workLimitExceeded(maximum: UInt64.max)
        }
        count = next
        lock.unlock()
    }
}

private final class ToolbarPresentationStringBudget {
    let limits: ToolbarPresentationEvidenceLimits
    let work: ToolbarPresentationWorkBudget
    private var total = 0

    init(limits: ToolbarPresentationEvidenceLimits, work: ToolbarPresentationWorkBudget) {
        self.limits = limits
        self.work = work
    }

    func nonblank(
        _ value: String,
        field: ToolbarPresentationEvidenceField = .source
    ) throws {
        try text(value, field: field, requiresNonblank: true)
    }

    func text(
        _ value: String,
        field: ToolbarPresentationEvidenceField,
        requiresNonblank: Bool = false
    ) throws {
        let count = toolbarPresentationBoundedUTF8Count(
            value,
            maximum: limits.maximumStringUTF8Bytes
        )
        guard count <= limits.maximumStringUTF8Bytes else {
            throw ToolbarPresentationEvidenceWorkflowError.stringTooLarge(
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        guard count <= limits.maximumTotalStringUTF8Bytes - total else {
            throw ToolbarPresentationEvidenceWorkflowError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        try work.consume(UInt64(count) + 1)
        guard !requiresNonblank || count > 0 && !toolbarPresentationIsBlank(value),
            value == value.precomposedStringWithCanonicalMapping,
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(field)
        }
        total += count
    }

    func identifier(
        _ id: AccessibilityStableID,
        field: ToolbarPresentationEvidenceField
    ) throws {
        let value = id.rawValue
        let count = toolbarPresentationBoundedUTF8Count(
            value,
            maximum: limits.maximumStringUTF8Bytes
        )
        guard count <= limits.maximumStringUTF8Bytes else {
            throw ToolbarPresentationEvidenceWorkflowError.stringTooLarge(
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        guard count <= limits.maximumTotalStringUTF8Bytes - total else {
            throw ToolbarPresentationEvidenceWorkflowError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        try work.consume(UInt64(count) + 1)
        guard count > 0, !toolbarPresentationIsBlank(value),
            value == value.precomposedStringWithCanonicalMapping,
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(field)
        }
        total += count
    }
}

private func toolbarPresentationConformingAuditEvidence(
    _ contract: ToolbarAuditContract,
    budget: ToolbarPresentationWorkBudget
) throws -> ToolbarAuditEvidence {
    var lifecycleByKey: [ToolbarPresentationLifecycleKey: ToolbarAuditLifecycleExpectation] = [:]
    lifecycleByKey.reserveCapacity(contract.lifecycleExpectations.count)
    for expectation in contract.lifecycleExpectations {
        try budget.consume()
        guard
            lifecycleByKey.updateValue(
                expectation,
                forKey: ToolbarPresentationLifecycleKey(expectation)
            ) == nil
        else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
        }
    }
    let surfaces = try ToolbarAuditLifecycleScenario.allCases.map { scenario in
        try budget.consume()
        return ToolbarAuditSurfaceEvidence(
            scenario: scenario,
            manifestRevision: contract.manifest.revision,
            items: contract.manifest.items,
            controls: try contract.controls.map { requirement in
                try budget.consume()
                guard
                    let primary = lifecycleByKey[
                        ToolbarPresentationLifecycleKey(
                            scenario: scenario,
                            command: requirement.command,
                            actionID: requirement.behavior.primaryActionID
                        )
                    ]?.availability
                else {
                    throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(.contract)
                }
                let behavior: ToolbarAuditControlBehavior
                switch requirement.behavior.secondary {
                case .none:
                    behavior = requirement.behavior
                case .menu(let actions):
                    behavior = ToolbarAuditControlBehavior(
                        primaryActionID: requirement.behavior.primaryActionID,
                        secondary: .menu(
                            actions: try actions.map { action in
                                try budget.consume()
                                guard
                                    let enabled = lifecycleByKey[
                                        ToolbarPresentationLifecycleKey(
                                            scenario: scenario,
                                            command: requirement.command,
                                            actionID: action.id
                                        )
                                    ]?.availability.isEnabled
                                else {
                                    throw ToolbarPresentationEvidenceWorkflowError.invalidInventory(
                                        .contract
                                    )
                                }
                                return ToolbarAuditSecondaryAction(
                                    id: action.id,
                                    accessibility: toolbarPresentationConcreteAX(
                                        action.accessibility,
                                        isEnabled: enabled
                                    )
                                )
                            }
                        )
                    )
                }
                return ToolbarAuditControlObservation(
                    id: requirement.id,
                    command: requirement.command,
                    behavior: behavior,
                    tooltip: requirement.tooltip,
                    shortcut: requirement.shortcut,
                    accessibility: toolbarPresentationConcreteAX(
                        requirement.accessibility,
                        isEnabled: primary.isEnabled
                    ),
                    availability: primary
                )
            },
            source: "inventory-validation"
        )
    }
    let interactions = try contract.interactionExpectations.map { expectation in
        try budget.consume()
        return ToolbarAuditInteractionEvidence(
            scenario: expectation.scenario,
            controlID: expectation.controlID,
            actionID: expectation.actionID,
            invocation: expectation.invocation,
            outcome: expectation.outcome,
            source: "inventory-validation"
        )
    }
    let digest = ToolbarAuditArtifactDigest(lowercaseHex: String(repeating: "0", count: 64))
    let screenshots = try contract.screenshotExpectations.map { expectation in
        try budget.consume()
        return ToolbarAuditScreenshotEvidence(
            context: expectation.context,
            manifestRevision: contract.manifest.revision,
            items: contract.manifest.items,
            screenshotDigest: digest,
            accessibilitySidecarDigest: expectation.requiresAccessibilitySidecar ? digest : nil,
            source: "inventory-validation"
        )
    }
    return ToolbarAuditEvidence(
        contractRevision: contract.revision,
        surfaces: surfaces,
        interactions: interactions,
        screenshots: screenshots
    )
}

private func toolbarPresentationNestedAuditCollectionCharge(
    contract: ToolbarAuditContract,
    evidence: ToolbarAuditEvidence
) -> UInt64 {
    let countsAndStrides: [(Int, Int)] = [
        (contract.controls.count, MemoryLayout<ToolbarAuditControlRequirement>.stride),
        (
            contract.lifecycleExpectations.count,
            MemoryLayout<ToolbarAuditLifecycleExpectation>.stride
        ),
        (
            contract.interactionExpectations.count,
            MemoryLayout<ToolbarAuditInteractionExpectation>.stride
        ),
        (
            contract.screenshotExpectations.count,
            MemoryLayout<ToolbarAuditScreenshotExpectation>.stride
        ),
        (evidence.surfaces.count, MemoryLayout<ToolbarAuditSurfaceEvidence>.stride),
        (evidence.interactions.count, MemoryLayout<ToolbarAuditInteractionEvidence>.stride),
        (evidence.screenshots.count, MemoryLayout<ToolbarAuditScreenshotEvidence>.stride)
    ]
    var charge: UInt64 = 0
    for (count, stride) in countsAndStrides {
        let (next, overflow) = charge.addingReportingOverflow(
            toolbarPresentationCollectionCharge(count: count, stride: stride)
        )
        if overflow { return UInt64.max }
        charge = next
    }
    return charge
}

private func toolbarPresentationDebitNestedAuditStrings(
    contract: ToolbarAuditContract,
    _ evidence: ToolbarAuditEvidence,
    strings: ToolbarPresentationStringBudget,
    budget: ToolbarPresentationWorkBudget
) throws {
    for control in contract.controls {
        try strings.text(control.id.rawValue, field: .contract)
        try strings.text(control.behavior.primaryActionID.rawValue, field: .contract)
        try strings.text(control.tooltip, field: .contract)
        if let shortcut = control.shortcut {
            try strings.text(shortcut.key, field: .contract)
            try strings.text(shortcut.display, field: .contract)
        }
        try toolbarPresentationDebitNestedAuditAX(control.accessibility, strings: strings)
        if case .menu(let actions) = control.behavior.secondary {
            for action in actions {
                try budget.consume()
                try strings.text(action.id.rawValue, field: .contract)
                try toolbarPresentationDebitNestedAuditAX(action.accessibility, strings: strings)
            }
        }
    }
    for expectation in contract.lifecycleExpectations {
        try budget.consume()
        try toolbarPresentationDebitNestedAuditAvailability(expectation.availability, strings: strings)
    }
    for expectation in contract.interactionExpectations {
        try budget.consume()
        try strings.text(expectation.controlID.rawValue, field: .contract)
        try strings.text(expectation.actionID.rawValue, field: .contract)
        try toolbarPresentationDebitNestedAuditOutcome(expectation.outcome, strings: strings)
    }
    for surface in evidence.surfaces {
        try budget.consume()
        try strings.text(surface.source, field: .contract)
        for control in surface.controls {
            try strings.text(control.id.rawValue, field: .contract)
            try strings.text(control.behavior.primaryActionID.rawValue, field: .contract)
            if let tooltip = control.tooltip { try strings.text(tooltip, field: .contract) }
            if let shortcut = control.shortcut {
                try strings.text(shortcut.key, field: .contract)
                try strings.text(shortcut.display, field: .contract)
            }
            try toolbarPresentationDebitNestedAuditAX(control.accessibility, strings: strings)
            try toolbarPresentationDebitNestedAuditAvailability(control.availability, strings: strings)
            if case .menu(let actions) = control.behavior.secondary {
                for action in actions {
                    try budget.consume()
                    try strings.text(action.id.rawValue, field: .contract)
                    try toolbarPresentationDebitNestedAuditAX(action.accessibility, strings: strings)
                }
            }
        }
    }
    for interaction in evidence.interactions {
        try budget.consume()
        try strings.text(interaction.controlID.rawValue, field: .contract)
        try strings.text(interaction.actionID.rawValue, field: .contract)
        try strings.text(interaction.source, field: .contract)
        try toolbarPresentationDebitNestedAuditOutcome(interaction.outcome, strings: strings)
    }
    for screenshot in evidence.screenshots {
        try budget.consume()
        try strings.text(screenshot.screenshotDigest.lowercaseHex, field: .contract)
        if let sidecar = screenshot.accessibilitySidecarDigest {
            try strings.text(sidecar.lowercaseHex, field: .contract)
        }
        try strings.text(screenshot.source, field: .contract)
    }
}

private func toolbarPresentationDebitNestedAuditAX(
    _ metadata: ToolbarAuditAXMetadata,
    strings: ToolbarPresentationStringBudget
) throws {
    try strings.text(metadata.identifier.rawValue, field: .contract)
    try strings.text(metadata.label, field: .contract)
    if let value = metadata.value { try strings.text(value, field: .contract) }
    try strings.text(metadata.hint, field: .contract)
}

private func toolbarPresentationDebitNestedAuditAvailability(
    _ availability: ToolbarAuditAvailability,
    strings: ToolbarPresentationStringBudget
) throws {
    guard case .disabled(let reason) = availability else { return }
    try strings.text(reason.rawValue, field: .contract)
}

private func toolbarPresentationDebitNestedAuditOutcome(
    _ outcome: ToolbarAuditInteractionOutcome,
    strings: ToolbarPresentationStringBudget
) throws {
    switch outcome {
    case .invoked(let id), .failed(let id):
        try strings.text(id.rawValue, field: .contract)
    case .menuPresented(let ids):
        for id in ids { try strings.text(id.rawValue, field: .contract) }
    case .blocked, .noOp:
        break
    }
}

private struct ToolbarPresentationLifecycleKey: Hashable {
    let scenario: ToolbarAuditLifecycleScenario
    let command: ToolbarAuditCommand
    let actionID: ToolbarAuditStableID

    init(
        scenario: ToolbarAuditLifecycleScenario,
        command: ToolbarAuditCommand,
        actionID: ToolbarAuditStableID
    ) {
        self.scenario = scenario
        self.command = command
        self.actionID = actionID
    }

    init(_ value: ToolbarAuditLifecycleExpectation) {
        self.init(
            scenario: value.scenario,
            command: value.command,
            actionID: value.actionID
        )
    }
}

private struct ToolbarPresentationInteractionKey: Hashable {
    let scenario: ToolbarAuditLifecycleScenario
    let controlID: ToolbarAuditStableID
    let actionID: ToolbarAuditStableID
    let invocation: ToolbarAuditInvocationKind

    init(_ value: ToolbarPresentationInteractionCapture) {
        scenario = value.scenario
        controlID = value.controlID
        actionID = value.actionID
        invocation = value.invocation
    }

    init(_ value: ToolbarAuditInteractionExpectation) {
        scenario = value.scenario
        controlID = value.controlID
        actionID = value.actionID
        invocation = value.invocation
    }
}

private struct ToolbarPresentationFocusKey: Hashable {
    let controlID: ToolbarAuditStableID
    let traversal: ToolbarPresentationFocusTraversal

    init(controlID: ToolbarAuditStableID, traversal: ToolbarPresentationFocusTraversal) {
        self.controlID = controlID
        self.traversal = traversal
    }

    init(_ value: ToolbarPresentationFocusMovement) {
        self.init(controlID: value.controlID, traversal: value.traversal)
    }
}

private func toolbarPresentationConcreteAX(
    _ value: ToolbarAuditAXMetadata,
    isEnabled: Bool
) -> ToolbarAuditAXMetadata {
    ToolbarAuditAXMetadata(
        identifier: value.identifier,
        role: value.role,
        label: value.label,
        value: value.value,
        hint: value.hint,
        isEnabled: isEnabled,
        checkedState: value.checkedState,
        selectedState: value.selectedState,
        isKeyboardFocusable: value.isKeyboardFocusable,
        actions: value.actions
    )
}

private func toolbarPresentationAuditLimits(
    _ limits: ToolbarPresentationEvidenceLimits,
    maximumWorkUnits: Int? = nil,
    cancellationCheckInterval: Int? = nil
) -> ToolbarAuditLimits {
    ToolbarAuditLimits(
        maximumManifestItems: ToolbarConfiguration.maximumItemCount,
        maximumControls: ToolbarConfiguration.Command.allCases.count,
        maximumSecondaryActions: min(
            limits.maximumSecondaryActionsPerCapture,
            ToolbarAuditLimits.hardMaximumSecondaryActions
        ),
        maximumLifecycleExpectations: ToolbarAuditLimits.hardMaximumLifecycleExpectations,
        maximumInteractionRecords: ToolbarAuditLimits.hardMaximumInteractionRecords,
        maximumScreenshots: ToolbarAuditLimits.hardMaximumScreenshots,
        maximumStringUTF8Bytes: min(
            limits.maximumStringUTF8Bytes,
            ToolbarAuditLimits.hardMaximumStringUTF8Bytes
        ),
        maximumTotalStringUTF8Bytes: min(
            limits.maximumTotalStringUTF8Bytes,
            ToolbarAuditLimits.hardMaximumTotalStringUTF8Bytes
        ),
        maximumWorkUnits: min(
            maximumWorkUnits ?? Int(clamping: limits.maximumWorkUnits),
            ToolbarAuditLimits.hardMaximumWorkUnits
        ),
        maximumFindings: min(limits.maximumFindings, ToolbarAuditLimits.hardMaximumFindings),
        maximumArchiveBytes: min(
            limits.maximumArchiveBytes,
            ToolbarAuditLimits.hardMaximumArchiveBytes
        ),
        cancellationCheckInterval: min(
            cancellationCheckInterval ?? limits.cancellationCheckInterval,
            ToolbarAuditLimits.hardMaximumCancellationCheckInterval
        )
    )
}

private func toolbarPresentationAXMatches(
    _ actual: ToolbarAuditAXMetadata,
    expected: ToolbarAuditAXMetadata,
    expectedEnabled: Bool?,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    try toolbarPresentationStringsEqual(
        actual.identifier.rawValue,
        expected.identifier.rawValue,
        budget: budget
    )
        && toolbarPresentationStringsEqual(actual.label, expected.label, budget: budget)
        && toolbarPresentationOptionalStringsEqual(actual.value, expected.value, budget: budget)
        && toolbarPresentationStringsEqual(actual.hint, expected.hint, budget: budget)
        && actual.role == expected.role
        && actual.isEnabled == expectedEnabled
        && actual.checkedState == expected.checkedState
        && actual.selectedState == expected.selectedState
        && actual.isKeyboardFocusable == expected.isKeyboardFocusable
        && actual.actions == expected.actions
}

private func toolbarPresentationOptionalStringsEqual(
    _ left: String?,
    _ right: String?,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    switch (left, right) {
    case (nil, nil): true
    case (let left?, let right?):
        try toolbarPresentationStringsEqual(left, right, budget: budget)
    default: false
    }
}

private func toolbarPresentationStringsEqual(
    _ left: String,
    _ right: String,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        let leftByte = leftIterator.next()
        let rightByte = rightIterator.next()
        if leftByte != nil || rightByte != nil { try budget.consume() }
        guard leftByte == rightByte else { return false }
        if leftByte == nil { return true }
    }
}

private func toolbarPresentationStringsCompare(
    _ left: String,
    _ right: String,
    budget: ToolbarPresentationWorkBudget
) throws -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        let leftByte = leftIterator.next()
        let rightByte = rightIterator.next()
        if leftByte != nil || rightByte != nil { try budget.consume() }
        switch (leftByte, rightByte) {
        case (nil, nil):
            return 0
        case (nil, _?):
            return -1
        case (_?, nil):
            return 1
        case (let leftByte?, let rightByte?):
            if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
        }
    }
}

private func toolbarPresentationElementIdentity(
    matching identifier: ToolbarAuditStableID,
    in elements: [ToolbarPresentationAXElementObservation],
    budget: ToolbarPresentationWorkBudget
) throws -> AccessibilityStableID? {
    for element in elements {
        if try toolbarPresentationStringsEqual(
            element.accessibility.identifier.rawValue,
            identifier.rawValue,
            budget: budget
        ) {
            return element.elementIdentity
        }
    }
    return nil
}

private func toolbarPresentationOwnedMenuIdentity(
    of identity: AccessibilityStableID,
    elementsByIdentity: [AccessibilityStableID: ToolbarPresentationAXElementObservation],
    expectedControl: AccessibilityStableID,
    budget: ToolbarPresentationWorkBudget
) throws -> AccessibilityStableID? {
    var current = elementsByIdentity[identity]?.parentIdentity
    var menuIdentity: AccessibilityStableID?
    var ancestors: Set<AccessibilityStableID> = []
    while let currentIdentity = current {
        try budget.consume()
        guard ancestors.insert(currentIdentity).inserted,
            let element = elementsByIdentity[currentIdentity]
        else { return nil }
        if element.accessibility.role == .menu {
            guard menuIdentity == nil else { return nil }
            menuIdentity = currentIdentity
        }
        if currentIdentity == expectedControl { return menuIdentity }
        current = element.parentIdentity
    }
    return nil
}

private func toolbarPresentationAncestor(
    of identity: AccessibilityStableID,
    in roots: Set<AccessibilityStableID>,
    elementsByIdentity: [AccessibilityStableID: ToolbarPresentationAXElementObservation],
    budget: ToolbarPresentationWorkBudget
) throws -> AccessibilityStableID? {
    var current: AccessibilityStableID? = identity
    var ancestors: Set<AccessibilityStableID> = []
    while let currentIdentity = current {
        try budget.consume()
        if roots.contains(currentIdentity) { return currentIdentity }
        guard ancestors.insert(currentIdentity).inserted,
            let element = elementsByIdentity[currentIdentity]
        else { return nil }
        current = element.parentIdentity
    }
    return nil
}

private func toolbarPresentationValidateObservedLayout(
    tree: [ToolbarPresentationAXElementObservation],
    rootIdentity: AccessibilityStableID,
    controls: [ToolbarAuditControlObservation],
    controlElementIdentities: [ToolbarAuditStableID: AccessibilityStableID],
    items: [ToolbarAuditItem],
    budget: ToolbarPresentationWorkBudget
) throws {
    let controlsByCommand = Dictionary(uniqueKeysWithValues: controls.map { ($0.command, $0) })
    let children = try toolbarPresentationSorted(
        tree.filter { $0.parentIdentity == rootIdentity },
        by: { $0.siblingIndex < $1.siblingIndex },
        budget: budget
    )
    guard children.count == items.count,
        children.map(\.siblingIndex) == Array(0..<items.count)
    else {
        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
    }
    var previousFrame: ToolbarPresentationEvidenceRect?
    for (item, element) in zip(items, children) {
        try budget.consume()
        switch item {
        case .command(let command):
            guard let control = controlsByCommand[command],
                controlElementIdentities[control.id] == element.elementIdentity
            else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
        case .separator:
            guard element.accessibility.role == .separator else {
                throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
            }
        }
        if let previousFrame,
            !toolbarPresentationHorizontallyPrecedes(previousFrame, element.frame)
        {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.accessibilityTree)
        }
        previousFrame = element.frame
    }
}

private func toolbarPresentationMetadataMatchesRole(_ metadata: ToolbarAuditAXMetadata) -> Bool {
    let roleAllowsFocus: Bool
    let allowedActions: Set<AccessibilitySemanticActionKind>
    let requiredActions: Set<AccessibilitySemanticActionKind>
    let requiresLabel: Bool
    switch metadata.role {
    case .button, .link, .tab, .command:
        roleAllowsFocus = true
        allowedActions = [.activate, .custom]
        requiredActions = [.activate]
        requiresLabel = true
    case .listItem, .row, .cell, .treeItem:
        roleAllowsFocus = true
        allowedActions = [.activate, .custom]
        requiredActions = []
        requiresLabel = true
    case .toggle, .checkBox, .radioButton:
        roleAllowsFocus = true
        allowedActions = [.toggle, .custom]
        requiredActions = [.toggle]
        requiresLabel = true
    case .textField, .searchField:
        roleAllowsFocus = true
        allowedActions = [.setValue, .custom]
        requiredActions = [.setValue]
        requiresLabel = true
    case .comboBox:
        roleAllowsFocus = true
        allowedActions = [.setValue, .showMenu, .custom]
        requiredActions = [.setValue, .showMenu]
        requiresLabel = true
    case .menu:
        roleAllowsFocus = true
        allowedActions = [.showMenu, .dismiss, .custom]
        requiredActions = []
        requiresLabel = false
    case .menuItem:
        roleAllowsFocus = true
        allowedActions = [.activate, .toggle, .showMenu, .custom]
        requiredActions = metadata.checkedState == .notApplicable ? [.activate] : [.toggle]
        requiresLabel = true
    case .slider:
        roleAllowsFocus = true
        allowedActions = [.increment, .decrement, .setValue, .custom]
        requiredActions = [.increment, .decrement, .setValue]
        requiresLabel = true
    case .stepper:
        roleAllowsFocus = true
        allowedActions = [.increment, .decrement, .custom]
        requiredActions = [.increment, .decrement]
        requiresLabel = true
    case .list, .table, .tree:
        roleAllowsFocus = true
        allowedActions = [.custom]
        requiredActions = []
        requiresLabel = false
    case .customControl:
        roleAllowsFocus = true
        allowedActions = Set(AccessibilitySemanticActionKind.allCases)
        requiredActions = []
        requiresLabel = true
    case .window, .dialog, .alert:
        roleAllowsFocus = false
        allowedActions = [.dismiss, .custom]
        requiredActions = []
        requiresLabel = false
    case .application, .group, .toolbar, .tabList, .progressIndicator, .image, .staticText,
        .heading:
        roleAllowsFocus = false
        allowedActions = [.custom]
        requiredActions = []
        requiresLabel = metadata.role == .image || !metadata.actions.isEmpty
    case .separator, .presentation:
        roleAllowsFocus = false
        allowedActions = []
        requiredActions = []
        requiresLabel = false
    }
    guard !metadata.isKeyboardFocusable || roleAllowsFocus,
        metadata.actions.isSubset(of: allowedActions),
        requiredActions.isSubset(of: metadata.actions),
        metadata.role != .customControl || !metadata.actions.isEmpty,
        !requiresLabel || !toolbarPresentationIsBlank(metadata.label)
    else { return false }

    let supportsCheckedState =
        metadata.role == .toggle || metadata.role == .checkBox
        || metadata.role == .radioButton || metadata.role == .menuItem
    let requiresCheckedState =
        metadata.role == .toggle || metadata.role == .checkBox
        || metadata.role == .radioButton
    guard metadata.checkedState == .notApplicable || supportsCheckedState,
        !requiresCheckedState || metadata.checkedState != .notApplicable,
        !(metadata.role == .radioButton && metadata.checkedState == .mixed)
    else { return false }

    let supportsSelectedState =
        metadata.role == .radioButton || metadata.role == .menuItem
        || metadata.role == .tab || metadata.role == .listItem || metadata.role == .row
        || metadata.role == .cell || metadata.role == .treeItem
    guard metadata.selectedState == .notApplicable || supportsSelectedState,
        metadata.role != .tab || metadata.selectedState != .notApplicable
    else { return false }

    let permitsValue = [
        AccessibilitySemanticRole.listItem, .row, .cell, .treeItem, .staticText, .heading,
        .progressIndicator, .textField, .searchField, .comboBox, .slider, .stepper,
        .customControl
    ].contains(metadata.role)
    let permitsHint = [
        AccessibilitySemanticRole.button, .link, .menuItem, .tab, .image, .command, .listItem,
        .row, .cell, .treeItem, .staticText, .heading, .progressIndicator, .toggle, .checkBox,
        .radioButton, .textField, .searchField, .comboBox, .slider, .stepper, .customControl
    ].contains(metadata.role)
    let permitsLabel = metadata.role != .presentation
    return (metadata.label.isEmpty || permitsLabel)
        && (metadata.value == nil || permitsValue) && (metadata.hint.isEmpty || permitsHint)
}

private func toolbarPresentationRoleRequiresUniqueLabel(
    _ role: AccessibilitySemanticRole
) -> Bool {
    switch role {
    case .button, .toggle, .checkBox, .radioButton, .link, .textField, .searchField, .comboBox,
        .menuItem, .tab, .listItem, .row, .cell, .treeItem, .slider, .stepper, .image, .command,
        .customControl:
        true
    default:
        false
    }
}

private func toolbarPresentationSeparatorBoundaries(_ items: [ToolbarAuditItem]) -> [Int] {
    var commands = 0
    var boundaries: [Int] = []
    for item in items {
        switch item {
        case .command:
            commands += 1
        case .separator:
            boundaries.append(commands)
        }
    }
    return boundaries
}

private func toolbarPresentationLifecycleLess(
    _ left: ToolbarAuditLifecycleExpectation,
    _ right: ToolbarAuditLifecycleExpectation,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    if left.scenario != right.scenario {
        return toolbarPresentationEnumRank(left.scenario) < toolbarPresentationEnumRank(right.scenario)
    }
    if left.command != right.command {
        return toolbarPresentationEnumRank(left.command) < toolbarPresentationEnumRank(right.command)
    }
    return try toolbarPresentationStringsCompare(
        left.actionID.rawValue,
        right.actionID.rawValue,
        budget: budget
    ) < 0
}

private func toolbarPresentationInteractionLess(
    _ left: ToolbarAuditInteractionExpectation,
    _ right: ToolbarAuditInteractionExpectation,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    if left.scenario != right.scenario {
        return toolbarPresentationEnumRank(left.scenario) < toolbarPresentationEnumRank(right.scenario)
    }
    if left.controlID != right.controlID {
        return try toolbarPresentationStringsCompare(
            left.controlID.rawValue,
            right.controlID.rawValue,
            budget: budget
        ) < 0
    }
    if left.actionID != right.actionID {
        return try toolbarPresentationStringsCompare(
            left.actionID.rawValue,
            right.actionID.rawValue,
            budget: budget
        ) < 0
    }
    return toolbarPresentationEnumRank(left.invocation)
        < toolbarPresentationEnumRank(right.invocation)
}

private func toolbarPresentationInteractionCaptureLess(
    _ left: ToolbarPresentationInteractionCapture,
    _ right: ToolbarPresentationInteractionCapture,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    if left.scenario != right.scenario {
        return toolbarPresentationEnumRank(left.scenario) < toolbarPresentationEnumRank(right.scenario)
    }
    if left.controlID != right.controlID {
        return try toolbarPresentationStringsCompare(
            left.controlID.rawValue,
            right.controlID.rawValue,
            budget: budget
        ) < 0
    }
    if left.elementIdentity != right.elementIdentity {
        return try toolbarPresentationStringsCompare(
            left.elementIdentity.rawValue,
            right.elementIdentity.rawValue,
            budget: budget
        ) < 0
    }
    if left.actionID != right.actionID {
        return try toolbarPresentationStringsCompare(
            left.actionID.rawValue,
            right.actionID.rawValue,
            budget: budget
        ) < 0
    }
    if left.invocation != right.invocation {
        return toolbarPresentationEnumRank(left.invocation)
            < toolbarPresentationEnumRank(right.invocation)
    }
    return try toolbarPresentationStringsCompare(
        toolbarPresentationOutcomeSortKey(left.outcome),
        toolbarPresentationOutcomeSortKey(right.outcome),
        budget: budget
    ) < 0
}

private func toolbarPresentationFocusMovementLess(
    _ left: ToolbarPresentationFocusMovement,
    _ right: ToolbarPresentationFocusMovement,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    if left.controlID != right.controlID {
        return try toolbarPresentationStringsCompare(
            left.controlID.rawValue,
            right.controlID.rawValue,
            budget: budget
        ) < 0
    }
    if left.fromElementIdentity != right.fromElementIdentity {
        return try toolbarPresentationStringsCompare(
            left.fromElementIdentity.rawValue,
            right.fromElementIdentity.rawValue,
            budget: budget
        ) < 0
    }
    if left.toElementIdentity != right.toElementIdentity {
        return try toolbarPresentationStringsCompare(
            left.toElementIdentity.rawValue,
            right.toElementIdentity.rawValue,
            budget: budget
        ) < 0
    }
    return toolbarPresentationEnumRank(left.traversal)
        < toolbarPresentationEnumRank(right.traversal)
}

private func toolbarPresentationOutcomeSortKey(_ outcome: ToolbarAuditInteractionOutcome) -> String {
    switch outcome {
    case .invoked(let id): "0:\(id.rawValue)"
    case .menuPresented(let ids): "1:\(ids.map(\.rawValue).joined(separator: "\u{0}"))"
    case .blocked: "2"
    case .noOp: "3"
    case .failed(let id): "4:\(id.rawValue)"
    }
}

private func toolbarPresentationLifecycleCaptureLess(
    _ left: ToolbarPresentationLifecycleCapture,
    _ right: ToolbarPresentationLifecycleCapture,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    if left.scenario != right.scenario {
        return toolbarPresentationEnumRank(left.scenario) < toolbarPresentationEnumRank(right.scenario)
    }
    let idComparison = try toolbarPresentationStringsCompare(
        left.reference.id.rawValue,
        right.reference.id.rawValue,
        budget: budget
    )
    return idComparison == 0
        ? left.reference.revision < right.reference.revision
        : idComparison < 0
}

private func toolbarPresentationWindowCaptureLess(
    _ left: ToolbarPresentationWindowCapture,
    _ right: ToolbarPresentationWindowCapture,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    if left.context != right.context {
        return toolbarPresentationEnumRank(left.context) < toolbarPresentationEnumRank(right.context)
    }
    let idComparison = try toolbarPresentationStringsCompare(
        left.reference.id.rawValue,
        right.reference.id.rawValue,
        budget: budget
    )
    return idComparison == 0
        ? left.reference.revision < right.reference.revision
        : idComparison < 0
}

private func toolbarPresentationCanonicalLifecycleCaptures(
    _ values: [ToolbarPresentationLifecycleCapture],
    limits: ToolbarPresentationEvidenceLimits,
    budget: ToolbarPresentationWorkBudget
) throws -> ToolbarPresentationRetainedArray<ToolbarPresentationLifecycleCapture> {
    var keyed: [(ToolbarPresentationLifecycleCapture, Data)] = []
    keyed.reserveCapacity(values.count)
    var retainedBytes = toolbarPresentationCollectionCharge(
        count: values.count,
        stride: MemoryLayout<(ToolbarPresentationLifecycleCapture, Data)>.stride
    )
    try budget.consumeMemory(retainedBytes)
    defer { budget.releaseMemory(retainedBytes) }
    for value in values {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendLifecycleCapture(value)
        let encoded = writer.finish()
        let (nextRetained, overflow) = retainedBytes.addingReportingOverflow(UInt64(encoded.data.count))
        guard !overflow else {
            throw ToolbarPresentationEvidenceWorkflowError.aggregateMemoryExceeded(
                maximumBytes: limits.maximumAggregateMemoryBytes
            )
        }
        retainedBytes = nextRetained
        keyed.append((value, encoded.transfer()))
    }
    let sortedKeyed = try toolbarPresentationSorted(
        keyed,
        by: { left, right in
            if try toolbarPresentationLifecycleCaptureLess(left.0, right.0, budget: budget) {
                return true
            }
            if try toolbarPresentationLifecycleCaptureLess(right.0, left.0, budget: budget) {
                return false
            }
            return try toolbarPresentationCompareData(left.1, right.1, budget: budget) < 0
        },
        budget: budget
    )
    let outputCharge = toolbarPresentationCollectionCharge(
        count: values.count,
        stride: MemoryLayout<ToolbarPresentationLifecycleCapture>.stride
    )
    try budget.consumeMemory(outputCharge)
    var retainsOutput = false
    defer {
        if !retainsOutput { budget.releaseMemory(outputCharge) }
    }
    let sorted = sortedKeyed.map(\.0)
    retainsOutput = true
    return ToolbarPresentationRetainedArray(
        values: sorted,
        retainedByteCharge: outputCharge,
        budget: budget
    )
}

private func toolbarPresentationCanonicalWindowCaptures(
    _ values: [ToolbarPresentationWindowCapture],
    limits: ToolbarPresentationEvidenceLimits,
    budget: ToolbarPresentationWorkBudget
) throws -> ToolbarPresentationRetainedArray<ToolbarPresentationWindowCapture> {
    var keyed: [(ToolbarPresentationWindowCapture, Data)] = []
    keyed.reserveCapacity(values.count)
    var retainedBytes = toolbarPresentationCollectionCharge(
        count: values.count,
        stride: MemoryLayout<(ToolbarPresentationWindowCapture, Data)>.stride
    )
    try budget.consumeMemory(retainedBytes)
    defer { budget.releaseMemory(retainedBytes) }
    for value in values {
        let writer = ToolbarPresentationWriter(limits: limits, budget: budget)
        try writer.appendWindowCapture(value)
        let encoded = writer.finish()
        let (nextRetained, overflow) = retainedBytes.addingReportingOverflow(UInt64(encoded.data.count))
        guard !overflow else {
            throw ToolbarPresentationEvidenceWorkflowError.aggregateMemoryExceeded(
                maximumBytes: limits.maximumAggregateMemoryBytes
            )
        }
        retainedBytes = nextRetained
        keyed.append((value, encoded.transfer()))
    }
    let sortedKeyed = try toolbarPresentationSorted(
        keyed,
        by: { left, right in
            if try toolbarPresentationWindowCaptureLess(left.0, right.0, budget: budget) {
                return true
            }
            if try toolbarPresentationWindowCaptureLess(right.0, left.0, budget: budget) {
                return false
            }
            return try toolbarPresentationCompareData(left.1, right.1, budget: budget) < 0
        },
        budget: budget
    )
    let outputCharge = toolbarPresentationCollectionCharge(
        count: values.count,
        stride: MemoryLayout<ToolbarPresentationWindowCapture>.stride
    )
    try budget.consumeMemory(outputCharge)
    var retainsOutput = false
    defer {
        if !retainsOutput { budget.releaseMemory(outputCharge) }
    }
    let sorted = sortedKeyed.map(\.0)
    retainsOutput = true
    return ToolbarPresentationRetainedArray(
        values: sorted,
        retainedByteCharge: outputCharge,
        budget: budget
    )
}

private func toolbarPresentationValidMediaType(
    _ attachment: ToolbarPresentationEvidenceAttachment
) -> Bool {
    switch attachment.kind {
    case .screenshot:
        attachment.mediaType == "image/png" || attachment.mediaType == "image/jpeg"
    case .accessibilitySnapshot:
        attachment.mediaType
            == ToolbarPresentationEvidenceWorkflow.accessibilityAttachmentMediaType
    }
}

private final class ToolbarPresentationCanonicalScreenshot {
    let data: Data
    let dimensions: (width: Int, height: Int)
    private let budget: ToolbarPresentationWorkBudget
    private var retainedByteCharge: UInt64

    init(
        data: Data,
        dimensions: (width: Int, height: Int),
        retainedByteCharge: UInt64,
        budget: ToolbarPresentationWorkBudget
    ) {
        self.data = data
        self.dimensions = dimensions
        self.retainedByteCharge = retainedByteCharge
        self.budget = budget
    }

    deinit { budget.releaseMemory(retainedByteCharge) }

    func transfer() -> Data {
        retainedByteCharge = 0
        return data
    }
}

private func toolbarPresentationScreenshotHasMeaningfulToolbarPixels(
    _ screenshot: ToolbarPresentationCanonicalScreenshot,
    geometry: ToolbarPresentationCaptureGeometry,
    accessibilityTree: [ToolbarPresentationAXElementObservation],
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    let headerBytes = 8 + MemoryLayout<UInt64>.size * 2
    let scale = geometry.backingScaleThousandths
    let relativeX = geometry.toolbar.x - geometry.window.x
    let relativeY = geometry.toolbar.y - geometry.window.y
    var pixels = (x: 0, y: 0, width: 0, height: 0)
    for (index, value) in [
        relativeX, relativeY, geometry.toolbar.width, geometry.toolbar.height
    ].enumerated() {
        let (scaled, overflow) = value.multipliedReportingOverflow(by: scale)
        guard !overflow, scaled.isMultiple(of: 1_000) else {
            throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
        }
        switch index {
        case 0: pixels.x = scaled / 1_000
        case 1: pixels.y = scaled / 1_000
        case 2: pixels.width = scaled / 1_000
        default: pixels.height = scaled / 1_000
        }
    }
    let x = pixels.x
    let y = screenshot.dimensions.height - pixels.y - pixels.height
    let width = pixels.width
    let height = pixels.height
    guard x >= 0, y >= 0, width > 0, height > 0,
        x <= screenshot.dimensions.width - width,
        y <= screenshot.dimensions.height - height
    else {
        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
    }
    var substantialOpacity = 0
    var firstOpaquePixel: (UInt8, UInt8, UInt8)?
    var meaningfullyDifferent = 0
    for row in y..<(y + height) {
        for column in x..<(x + width) {
            try budget.consume(4)
            let offset = headerBytes + (row * screenshot.dimensions.width + column) * 4
            let pixel = (
                screenshot.data[offset], screenshot.data[offset + 1],
                screenshot.data[offset + 2], screenshot.data[offset + 3]
            )
            guard pixel.3 >= 0xC0 else { continue }
            substantialOpacity += 1
            if let firstOpaquePixel {
                let difference =
                    abs(Int(pixel.0) - Int(firstOpaquePixel.0))
                    + abs(Int(pixel.1) - Int(firstOpaquePixel.1))
                    + abs(Int(pixel.2) - Int(firstOpaquePixel.2))
                if difference >= 24 { meaningfullyDifferent += 1 }
            } else {
                firstOpaquePixel = (pixel.0, pixel.1, pixel.2)
            }
        }
    }
    let pixelCount = width * height
    guard substantialOpacity >= pixelCount - pixelCount / 10,
        meaningfullyDifferent >= max(2, pixelCount / 16)
    else { return false }

    for element in accessibilityTree
    where element.parentIdentity != nil
        && element.accessibility.role != .separator && element.accessibility.role != .menu
    {
        guard toolbarPresentationRectContains(geometry.toolbar, element.frame) else { continue }
        let relativeElementX = element.frame.x - geometry.window.x
        let relativeElementY = element.frame.y - geometry.window.y
        let values = [relativeElementX, relativeElementY, element.frame.width, element.frame.height]
        var elementPixels = (x: 0, y: 0, width: 0, height: 0)
        for (index, value) in values.enumerated() {
            let (scaled, overflow) = value.multipliedReportingOverflow(by: scale)
            guard !overflow, scaled.isMultiple(of: 1_000) else { return false }
            switch index {
            case 0: elementPixels.x = scaled / 1_000
            case 1: elementPixels.y = scaled / 1_000
            case 2: elementPixels.width = scaled / 1_000
            default: elementPixels.height = scaled / 1_000
            }
        }
        let elementY = screenshot.dimensions.height - elementPixels.y - elementPixels.height
        var opaque = 0
        for row in elementY..<(elementY + elementPixels.height) {
            for column in elementPixels.x..<(elementPixels.x + elementPixels.width) {
                try budget.consume()
                let offset = headerBytes + (row * screenshot.dimensions.width + column) * 4
                if screenshot.data[offset + 3] >= 0xC0 { opaque += 1 }
            }
        }
        let elementPixelCount = elementPixels.width * elementPixels.height
        guard elementPixelCount > 0, opaque >= elementPixelCount - elementPixelCount / 4 else {
            return false
        }
    }
    return true
}

private func toolbarPresentationScreenshotMatchesContext(
    _ screenshot: ToolbarPresentationCanonicalScreenshot,
    context: ToolbarAuditScreenshotContext,
    geometry: ToolbarPresentationCaptureGeometry,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    guard
        let toolbar = toolbarPresentationPixelRect(
            geometry.toolbar,
            in: geometry,
            dimensions: screenshot.dimensions
        )
    else { return false }
    let headerBytes = 24
    var transitions = 0
    var previous: (UInt8, UInt8, UInt8)?
    for row in 0..<screenshot.dimensions.height {
        for column in 0..<screenshot.dimensions.width
        where !toolbarPresentationPixelRectContains(toolbar, x: column, y: row) {
            try budget.consume(4)
            let offset = headerBytes + (row * screenshot.dimensions.width + column) * 4
            let pixel = (
                screenshot.data[offset], screenshot.data[offset + 1], screenshot.data[offset + 2]
            )
            if let previous, toolbarPresentationColorDifference(previous, pixel) >= 24 {
                transitions += 1
            }
            previous = pixel
        }
    }
    let bodyPixelCount =
        screenshot.dimensions.width * screenshot.dimensions.height
        - toolbar.width * toolbar.height
    guard bodyPixelCount > 0 else { return false }
    switch context {
    case .freshWindow:
        return transitions <= max(1, bodyPixelCount / 32)
    case .loadedComparison:
        return transitions >= max(2, bodyPixelCount / 16)
    }
}

private func toolbarPresentationColorDifference(
    _ left: (UInt8, UInt8, UInt8),
    _ right: (UInt8, UInt8, UInt8)
) -> Int {
    abs(Int(left.0) - Int(right.0))
        + abs(Int(left.1) - Int(right.1))
        + abs(Int(left.2) - Int(right.2))
}

private func toolbarPresentationCanonicalScreenshot(
    _ data: Data,
    expectedMediaType: String,
    limits: ToolbarPresentationEvidenceLimits,
    budget: ToolbarPresentationWorkBudget
) throws -> ToolbarPresentationCanonicalScreenshot {
    try budget.consume(UInt64(data.count) + 1)
    try budget.checkCancellation()
    let expectedType: String
    switch expectedMediaType {
    case "image/png":
        expectedType = "public.png"
    case "image/jpeg":
        expectedType = "public.jpeg"
    default:
        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
    }
    let dimensions: (width: Int, height: Int)?
    switch expectedMediaType {
    case "image/png":
        dimensions = try toolbarPresentationPNGDimensions(data, budget: budget)
    case "image/jpeg":
        dimensions = try toolbarPresentationJPEGDimensions(data, budget: budget)
    default:
        dimensions = nil
    }
    guard let dimensions,
        toolbarPresentationValidImageDimensions(
            width: dimensions.width,
            height: dimensions.height
        )
    else {
        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
    }
    try toolbarPresentationRequireUprightSingleImage(
        data,
        expectedType: expectedType,
        budget: budget
    )
    return try toolbarPresentationNormalizedRGBA(
        data,
        expectedType: expectedType,
        dimensions: dimensions,
        limits: limits,
        budget: budget
    )
}

private func toolbarPresentationRequireUprightSingleImage(
    _ data: Data,
    expectedType: String,
    budget: ToolbarPresentationWorkBudget
) throws {
    try budget.checkCancellation()
    let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
        CGImageSourceGetCount(source) == 1,
        (CGImageSourceGetType(source) as String?) == expectedType
    else {
        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
    }
    try budget.checkCancellation()
}

private func toolbarPresentationPNGDimensions(
    _ data: Data,
    budget: ToolbarPresentationWorkBudget
) throws -> (width: Int, height: Int)? {
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    guard data.count >= 45,
        data.prefix(signature.count).elementsEqual(signature)
    else { return nil }
    var offset = signature.count
    var sawHeader = false
    var sawData = false
    var dataByteCount = 0
    var dataEnded = false
    var sawPalette = false
    var metadataByteCount = 0
    var colorType: UInt8?
    var dimensions: (width: Int, height: Int)?
    while offset <= data.count - 12 {
        try budget.consume()
        let length = Int(toolbarPresentationUInt32(data, at: offset))
        guard length <= data.count - offset - 12 else { return nil }
        let type = toolbarPresentationUInt32(data, at: offset + 4)
        guard toolbarPresentationValidPNGChunkType(data, at: offset + 4) else { return nil }
        let isCritical = toolbarPresentationByte(data, at: offset + 4) & 0x20 == 0
        let storedCRC = toolbarPresentationUInt32(data, at: offset + 8 + length)
        let actualCRC = try toolbarPresentationCRC32(
            data,
            range: (offset + 4)..<(offset + 8 + length),
            budget: budget
        )
        guard storedCRC == actualCRC else { return nil }
        if !sawHeader {
            guard type == 0x4948_4452, length == 13 else { return nil }
            let width = Int(toolbarPresentationUInt32(data, at: offset + 8))
            let height = Int(toolbarPresentationUInt32(data, at: offset + 12))
            let bitDepth = toolbarPresentationByte(data, at: offset + 16)
            let parsedColorType = toolbarPresentationByte(data, at: offset + 17)
            let compression = toolbarPresentationByte(data, at: offset + 18)
            let filter = toolbarPresentationByte(data, at: offset + 19)
            let interlace = toolbarPresentationByte(data, at: offset + 20)
            guard toolbarPresentationValidPNGBitDepth(bitDepth, colorType: parsedColorType),
                compression == 0, filter == 0, interlace <= 1,
                toolbarPresentationValidImageDimensions(width: width, height: height)
            else { return nil }
            dimensions = (width, height)
            colorType = parsedColorType
            sawHeader = true
        } else if type == 0x4948_4452 {
            return nil
        } else if type == 0x504C_5445 {
            guard !sawPalette, !sawData, length > 0, length <= 768, length.isMultiple(of: 3),
                colorType != 0 && colorType != 4
            else { return nil }
            sawPalette = true
        } else if type == 0x4944_4154 {
            guard !dataEnded, colorType != 3 || sawPalette else { return nil }
            let (nextDataByteCount, overflow) = dataByteCount.addingReportingOverflow(length)
            guard !overflow else { return nil }
            dataByteCount = nextDataByteCount
            sawData = true
        } else if type == 0x4945_4E44 {
            guard sawData, dataByteCount > 0, length == 0, offset + 12 == data.count else {
                return nil
            }
            return dimensions
        } else {
            if sawData { dataEnded = true }
            guard !isCritical,
                let nextMetadataByteCount = toolbarPresentationAddingImageMetadata(
                    length,
                    to: metadataByteCount
                ),
                toolbarPresentationValidPNGAncillaryChunk(
                    type: type,
                    data: data,
                    payloadOffset: offset + 8,
                    length: length
                )
            else { return nil }
            metadataByteCount = nextMetadataByteCount
        }
        offset += length + 12
    }
    return nil
}

private func toolbarPresentationJPEGDimensions(
    _ data: Data,
    budget: ToolbarPresentationWorkBudget
) throws -> (width: Int, height: Int)? {
    guard data.count >= 10,
        data.prefix(3).elementsEqual([0xFF, 0xD8, 0xFF])
    else {
        return nil
    }
    var offset = 2
    var dimensions: (width: Int, height: Int)?
    var metadataByteCount = 0
    var sawStartOfScan = false
    while offset < data.count {
        try budget.consume()
        guard toolbarPresentationByte(data, at: offset) == 0xFF else { return nil }
        while offset < data.count, toolbarPresentationByte(data, at: offset) == 0xFF {
            try budget.consume()
            offset += 1
        }
        guard offset < data.count else { return nil }
        let marker = toolbarPresentationByte(data, at: offset)
        offset += 1
        if marker == 0xD9 {
            return sawStartOfScan && offset == data.count ? dimensions : nil
        }
        if marker == 0xDA {
            guard dimensions != nil, offset <= data.count - 2 else { return nil }
            let length = toolbarPresentationUInt16(data, at: offset)
            guard length >= 6, length <= data.count - offset else { return nil }
            sawStartOfScan = true
            offset += length
            guard
                let markerOffset = try toolbarPresentationNextJPEGMarker(
                    data,
                    from: offset,
                    budget: budget
                )
            else { return nil }
            offset = markerOffset
            continue
        }
        if marker == 0x01 || (0xD0...0xD8).contains(marker) { continue }
        guard offset <= data.count - 2 else { return nil }
        let length = toolbarPresentationUInt16(data, at: offset)
        guard length >= 2, length <= data.count - offset else { return nil }
        if (0xE0...0xEF).contains(marker) || marker == 0xFE {
            guard
                marker != 0xE1
                    || toolbarPresentationValidJPEGAPP1(
                        data,
                        payloadOffset: offset + 2,
                        length: length - 2
                    ),
                let nextMetadataByteCount = toolbarPresentationAddingImageMetadata(
                    length,
                    to: metadataByteCount
                )
            else { return nil }
            metadataByteCount = nextMetadataByteCount
        }
        if toolbarPresentationIsJPEGStartOfFrame(marker) {
            guard dimensions == nil, length >= 11 else { return nil }
            let height = toolbarPresentationUInt16(data, at: offset + 3)
            let width = toolbarPresentationUInt16(data, at: offset + 5)
            let components = Int(toolbarPresentationByte(data, at: offset + 7))
            guard components > 0, components <= 4,
                length == 8 + 3 * components,
                toolbarPresentationValidImageDimensions(width: width, height: height)
            else { return nil }
            dimensions = (width, height)
        }
        offset += length
    }
    return nil
}

private func toolbarPresentationNormalizedRGBA(
    _ data: Data,
    expectedType: String,
    dimensions: (width: Int, height: Int),
    limits: ToolbarPresentationEvidenceLimits,
    budget: ToolbarPresentationWorkBudget
) throws -> ToolbarPresentationCanonicalScreenshot {
    let (pixelCount, pixelOverflow) = dimensions.width.multipliedReportingOverflow(
        by: dimensions.height
    )
    let (decodedBytes, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
    guard !pixelOverflow, !byteOverflow else {
        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
    }
    guard UInt64(decodedBytes) <= limits.maximumAggregateMemoryBytes else {
        throw ToolbarPresentationEvidenceWorkflowError.aggregateMemoryExceeded(
            maximumBytes: limits.maximumAggregateMemoryBytes
        )
    }
    guard UInt64(decodedBytes) <= limits.maximumWorkUnits else {
        throw ToolbarPresentationEvidenceWorkflowError.workLimitExceeded(
            maximum: limits.maximumWorkUnits
        )
    }
    let headerBytes = 8 + MemoryLayout<UInt64>.size * 2
    let (canonicalBytes, canonicalOverflow) = headerBytes.addingReportingOverflow(decodedBytes)
    guard !canonicalOverflow, canonicalBytes <= limits.maximumAttachmentBytes else {
        throw ToolbarPresentationEvidenceWorkflowError.attachmentTooLarge(
            maximumBytes: limits.maximumAttachmentBytes
        )
    }
    let outputCharge = UInt64(canonicalBytes)
    let decoderCharge = UInt64(decodedBytes)
    let renderScratchCharge = UInt64(decodedBytes)
    let (workingCharge, workingOverflow) = decoderCharge.addingReportingOverflow(renderScratchCharge)
    guard !workingOverflow else {
        throw ToolbarPresentationEvidenceWorkflowError.aggregateMemoryExceeded(
            maximumBytes: limits.maximumAggregateMemoryBytes
        )
    }
    let (totalCharge, totalOverflow) = workingCharge.addingReportingOverflow(outputCharge)
    guard !totalOverflow, totalCharge <= limits.maximumAggregateMemoryBytes else {
        throw ToolbarPresentationEvidenceWorkflowError.aggregateMemoryExceeded(
            maximumBytes: limits.maximumAggregateMemoryBytes
        )
    }
    try budget.consumeMemory(workingCharge)
    defer { budget.releaseMemory(workingCharge) }
    try budget.consumeMemory(outputCharge)
    var retainCanonicalCharge = false
    defer {
        if !retainCanonicalCharge { budget.releaseMemory(outputCharge) }
    }
    try budget.consume(UInt64(canonicalBytes))
    try budget.checkCancellation()
    let sourceOptions: [CFString: Any] = [
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
        CGImageSourceGetCount(source) == 1,
        (CGImageSourceGetType(source) as String?) == expectedType,
        let image = CGImageSourceCreateImageAtIndex(
            source,
            0,
            [
                kCGImageSourceShouldAllowFloat: false,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
        )
    else {
        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
    }
    try budget.checkCancellation()
    guard image.width == dimensions.width, image.height == dimensions.height,
        image.dataProvider?.data != nil
    else {
        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
    }
    var canonical = Data(count: canonicalBytes)
    let rendered = canonical.withUnsafeMutableBytes { buffer -> Bool in
        guard let baseAddress = buffer.baseAddress,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: baseAddress.advanced(by: headerBytes),
                width: dimensions.width,
                height: dimensions.height,
                bitsPerComponent: 8,
                bytesPerRow: dimensions.width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return false }
        let header = Array("MMRGBA2\0".utf8)
        for (offset, byte) in header.enumerated() { buffer[offset] = byte }
        var width = UInt64(dimensions.width).bigEndian
        var height = UInt64(dimensions.height).bigEndian
        withUnsafeBytes(of: &width) { bytes in
            buffer[8..<(8 + bytes.count)].copyBytes(from: bytes)
        }
        withUnsafeBytes(of: &height) { bytes in
            buffer[(8 + MemoryLayout<UInt64>.size)..<headerBytes].copyBytes(from: bytes)
        }
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
        )
        return true
    }
    guard rendered else {
        throw ToolbarPresentationEvidenceWorkflowError.invalidEvidence(.screenshot)
    }
    try budget.checkCancellation()
    retainCanonicalCharge = true
    return ToolbarPresentationCanonicalScreenshot(
        data: canonical,
        dimensions: dimensions,
        retainedByteCharge: outputCharge,
        budget: budget
    )
}

private func toolbarPresentationValidImageDimensions(width: Int, height: Int) -> Bool {
    let maximumDimension = 16_384
    let maximumPixels = 64 * 1_024 * 1_024
    guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension,
        width <= maximumPixels / height
    else { return false }
    return true
}

private func toolbarPresentationValidPNGBitDepth(_ bitDepth: UInt8, colorType: UInt8) -> Bool {
    switch colorType {
    case 0: [1, 2, 4, 8, 16].contains(bitDepth)
    case 2, 4, 6: [8, 16].contains(bitDepth)
    case 3: [1, 2, 4, 8].contains(bitDepth)
    default: false
    }
}

private func toolbarPresentationValidPNGChunkType(_ data: Data, at offset: Int) -> Bool {
    for index in 0..<4 {
        let byte = toolbarPresentationByte(data, at: offset + index)
        guard (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) else { return false }
    }
    return toolbarPresentationByte(data, at: offset + 2) & 0x20 == 0
}

private func toolbarPresentationAddingImageMetadata(_ length: Int, to total: Int) -> Int? {
    let maximumMetadataBytes = 1 * 1_024 * 1_024
    let perEntryOverhead = 64
    let (withPayload, payloadOverflow) = total.addingReportingOverflow(length)
    let (next, overheadOverflow) = withPayload.addingReportingOverflow(perEntryOverhead)
    guard !payloadOverflow, !overheadOverflow, next <= maximumMetadataBytes else { return nil }
    return next
}

private func toolbarPresentationValidJPEGAPP1(
    _ data: Data,
    payloadOffset: Int,
    length: Int
) -> Bool {
    let exifHeader: [UInt8] = [0x45, 0x78, 0x69, 0x66, 0, 0]
    guard length >= exifHeader.count + 8,
        exifHeader.enumerated().allSatisfy({ index, byte in
            toolbarPresentationByte(data, at: payloadOffset + index) == byte
        })
    else { return false }
    return toolbarPresentationValidTIFFOrientation(
        data,
        payloadOffset: payloadOffset + exifHeader.count,
        length: length - exifHeader.count
    )
}

private func toolbarPresentationValidTIFFOrientation(
    _ data: Data,
    payloadOffset: Int,
    length: Int
) -> Bool {
    guard payloadOffset >= 0, length >= 8, payloadOffset <= data.count - length else {
        return false
    }
    let tiffOffset = payloadOffset
    let payloadEnd = payloadOffset + length
    let littleEndian: Bool
    switch (
        toolbarPresentationByte(data, at: tiffOffset),
        toolbarPresentationByte(data, at: tiffOffset + 1)
    ) {
    case (0x49, 0x49):
        littleEndian = true
    case (0x4D, 0x4D):
        littleEndian = false
    default:
        return false
    }
    guard
        toolbarPresentationJPEGEXIFUInt16(data, at: tiffOffset + 2, littleEndian: littleEndian)
            == 42
    else { return false }
    let directoryRelativeOffset = Int(
        toolbarPresentationJPEGEXIFUInt32(
            data,
            at: tiffOffset + 4,
            littleEndian: littleEndian
        )
    )
    guard directoryRelativeOffset >= 8,
        directoryRelativeOffset <= payloadEnd - tiffOffset - 6
    else { return false }
    let directoryOffset = tiffOffset + directoryRelativeOffset
    let entryCount = Int(
        toolbarPresentationJPEGEXIFUInt16(
            data,
            at: directoryOffset,
            littleEndian: littleEndian
        )
    )
    guard entryCount <= (payloadEnd - directoryOffset - 6) / 12 else { return false }
    var sawOrientation = false
    for index in 0..<entryCount {
        let entryOffset = directoryOffset + 2 + index * 12
        guard
            toolbarPresentationJPEGEXIFUInt16(
                data,
                at: entryOffset,
                littleEndian: littleEndian
            ) == 0x0112
        else { continue }
        guard !sawOrientation,
            toolbarPresentationJPEGEXIFUInt16(
                data,
                at: entryOffset + 2,
                littleEndian: littleEndian
            ) == 3,
            toolbarPresentationJPEGEXIFUInt32(
                data,
                at: entryOffset + 4,
                littleEndian: littleEndian
            ) == 1
        else { return false }
        guard
            toolbarPresentationJPEGEXIFUInt16(
                data,
                at: entryOffset + 8,
                littleEndian: littleEndian
            ) == 1
        else { return false }
        sawOrientation = true
    }
    return true
}

private func toolbarPresentationJPEGEXIFUInt16(
    _ data: Data,
    at offset: Int,
    littleEndian: Bool
) -> UInt16 {
    let first = UInt16(toolbarPresentationByte(data, at: offset))
    let second = UInt16(toolbarPresentationByte(data, at: offset + 1))
    return littleEndian ? first | second << 8 : first << 8 | second
}

private func toolbarPresentationJPEGEXIFUInt32(
    _ data: Data,
    at offset: Int,
    littleEndian: Bool
) -> UInt32 {
    let first = UInt32(toolbarPresentationJPEGEXIFUInt16(data, at: offset, littleEndian: littleEndian))
    let second = UInt32(
        toolbarPresentationJPEGEXIFUInt16(data, at: offset + 2, littleEndian: littleEndian)
    )
    return littleEndian ? first | second << 16 : first << 16 | second
}

private func toolbarPresentationValidPNGAncillaryChunk(
    type: UInt32,
    data: Data,
    payloadOffset: Int,
    length: Int
) -> Bool {
    let maximumMetadataBytes = 1 * 1_024 * 1_024
    guard length <= maximumMetadataBytes else { return false }
    switch type {
    case 0x7A54_5874, 0x6943_4350:  // zTXt, iCCP
        return false
    case 0x6558_4966:  // eXIf
        return toolbarPresentationValidTIFFOrientation(
            data,
            payloadOffset: payloadOffset,
            length: length
        )
    case 0x6954_5874:  // iTXt
        guard length >= 3 else { return false }
        var keywordEnd = payloadOffset
        let payloadEnd = payloadOffset + length
        while keywordEnd < payloadEnd, toolbarPresentationByte(data, at: keywordEnd) != 0 {
            keywordEnd += 1
        }
        guard keywordEnd + 2 < payloadEnd else { return false }
        return toolbarPresentationByte(data, at: keywordEnd + 1) == 0
    default:
        return true
    }
}

private func toolbarPresentationNextJPEGMarker(
    _ data: Data,
    from start: Int,
    budget: ToolbarPresentationWorkBudget
) throws -> Int? {
    var offset = start
    var charged = 0
    while offset < data.count {
        charged += 1
        if charged == 4_096 {
            try budget.consume(UInt64(charged))
            charged = 0
        }
        guard toolbarPresentationByte(data, at: offset) == 0xFF else {
            offset += 1
            continue
        }
        let markerOffset = offset
        while offset < data.count, toolbarPresentationByte(data, at: offset) == 0xFF {
            charged += 1
            if charged == 4_096 {
                try budget.consume(UInt64(charged))
                charged = 0
            }
            offset += 1
        }
        guard offset < data.count else {
            if charged > 0 { try budget.consume(UInt64(charged)) }
            return nil
        }
        let marker = toolbarPresentationByte(data, at: offset)
        if marker == 0x00 || (0xD0...0xD7).contains(marker) {
            offset += 1
            continue
        }
        if charged > 0 { try budget.consume(UInt64(charged)) }
        return markerOffset
    }
    if charged > 0 { try budget.consume(UInt64(charged)) }
    return nil
}

private func toolbarPresentationIsJPEGStartOfFrame(_ marker: UInt8) -> Bool {
    [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]
        .contains(marker)
}

private func toolbarPresentationCRC32(
    _ data: Data,
    range: Range<Int>,
    budget: ToolbarPresentationWorkBudget
) throws -> UInt32 {
    var crc = UInt32.max
    var charged = 0
    for offset in range {
        crc ^= UInt32(toolbarPresentationByte(data, at: offset))
        for _ in 0..<8 {
            crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xEDB8_8320)
        }
        charged += 1
        if charged == 4_096 {
            try budget.consume(UInt64(charged))
            charged = 0
        }
    }
    if charged > 0 { try budget.consume(UInt64(charged)) }
    return crc ^ UInt32.max
}

private func toolbarPresentationUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(toolbarPresentationByte(data, at: offset)) << 24
        | UInt32(toolbarPresentationByte(data, at: offset + 1)) << 16
        | UInt32(toolbarPresentationByte(data, at: offset + 2)) << 8
        | UInt32(toolbarPresentationByte(data, at: offset + 3))
}

private func toolbarPresentationUInt16(_ data: Data, at offset: Int) -> Int {
    Int(toolbarPresentationByte(data, at: offset)) << 8
        | Int(toolbarPresentationByte(data, at: offset + 1))
}

private func toolbarPresentationByte(_ data: Data, at offset: Int) -> UInt8 {
    data[data.index(data.startIndex, offsetBy: offset)]
}

private func toolbarPresentationFindingLess(
    _ left: ToolbarPresentationEvidenceFinding,
    _ right: ToolbarPresentationEvidenceFinding,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    if left.severity != right.severity {
        return toolbarPresentationSeverityRank(left.severity)
            > toolbarPresentationSeverityRank(right.severity)
    }
    if left.code != right.code {
        return try toolbarPresentationStringsCompare(
            left.code.rawValue,
            right.code.rawValue,
            budget: budget
        ) < 0
    }
    return try toolbarPresentationStringsCompare(
        left.id.rawValue,
        right.id.rawValue,
        budget: budget
    ) < 0
}

private func toolbarPresentationFindingMessage(
    _ code: ToolbarPresentationEvidenceFindingCode
) -> String {
    switch code {
    case .missingLifecycleCapture: "Required lifecycle row has no measured AX capture."
    case .duplicateLifecycleCapture: "Lifecycle row has multiple captures."
    case .unexpectedLifecycleCapture: "Lifecycle capture has no matching requirement."
    case .missingWindowCapture: "Required fresh or loaded window capture is missing."
    case .duplicateWindowCapture: "Window scenario has multiple captures."
    case .unexpectedWindowCapture: "Window capture has no matching requirement."
    case .assertionOnlyEvidence: "Caller assertion is not measured toolbar evidence."
    case .commandOrderMismatch: "Measured command order differs from manifest order."
    case .commandGroupingMismatch: "Measured separator grouping differs from manifest grouping."
    case .missingControl: "Required toolbar control is missing."
    case .unexpectedControl: "Measured toolbar control is not in the manifest."
    case .controlIdentityMismatch: "Measured toolbar control identity differs from requirement."
    case .controlBehaviorMismatch: "Measured toolbar behavior differs from requirement."
    case .tooltipMismatch: "Measured tooltip differs from exact WinMerge-equivalent text."
    case .shortcutMismatch: "Measured shortcut chord or display differs from requirement."
    case .accessibilityIdentifierMismatch: "Measured accessibility identifier differs from requirement."
    case .accessibilityRoleMismatch: "Measured accessibility role differs from requirement."
    case .accessibilityLabelMismatch: "Measured VoiceOver label differs from requirement."
    case .accessibilityValueMismatch: "Measured VoiceOver value differs from requirement."
    case .accessibilityHintMismatch: "Measured VoiceOver hint differs from requirement."
    case .accessibilityEnabledStateMismatch: "Measured accessibility enabled state differs from lifecycle state."
    case .accessibilityFocusMismatch: "Measured keyboard focus behavior differs from requirement."
    case .accessibilityStateMismatch: "Measured checked or selected state differs from requirement."
    case .accessibilityActionsMismatch: "Measured accessibility actions differ from requirement."
    case .availabilityMismatch: "Measured command availability differs from lifecycle state."
    case .missingInteractionCapture: "Required interaction has no measured outcome."
    case .duplicateInteractionCapture: "Required interaction has multiple measured outcomes."
    case .unexpectedInteractionCapture: "Measured interaction has no matching requirement."
    case .interactionOutcomeMismatch: "Measured interaction outcome differs from requirement."
    case .interactionIdentityMismatch: "Measured interaction identity differs from requirement."
    case .duplicateAccessibilityIdentifier: "Accessibility identifiers are not unique in this toolbar."
    case .duplicateAccessibilityLabel: "VoiceOver labels are not unique in this toolbar."
    case .incompleteAccessibilityTree: "Capture does not contain one complete toolbar AX tree."
    case .focusMovementMissing: "Focusable control has no measured focus transition."
    case .focusIdentityMismatch: "Measured focus target does not identify the required control."
    case .missingAccessibilityAttachment: "Capture has no matching verified AX attachment."
    case .missingScreenshotAttachment: "Window capture has no matching verified screenshot attachment."
    case .attachmentKindMismatch: "Attachment kind differs from capture requirement."
    case .attachmentProvenanceMismatch: "Attachment provenance differs from exact capture provenance."
    case .reusedAttachment: "Attachment is reused by multiple captures."
    case .reusedAttachmentDigest: "Attachment content digest is reused by multiple captures."
    case .screenshotContextMismatch: "Screenshot pixels do not match authenticated capture context."
    case .orphanAttachment: "Verified attachment is not referenced by any capture."
    }
}

private func toolbarPresentationSeverityRank(
    _ value: ToolbarPresentationEvidenceFindingSeverity
) -> Int {
    switch value {
    case .advisory: 0
    case .warning: 1
    case .error: 2
    }
}

private func toolbarPresentationEnumRank<T: CaseIterable & Equatable>(_ value: T) -> Int {
    Array(T.allCases).firstIndex(of: value) ?? Int.max
}

private func toolbarPresentationCompareUTF8(_ left: String, _ right: String) -> Int {
    left.utf8.lexicographicallyPrecedes(right.utf8)
        ? -1
        : (right.utf8.lexicographicallyPrecedes(left.utf8) ? 1 : 0)
}

private func toolbarPresentationBoundedUTF8Count(_ value: String, maximum: Int) -> Int {
    var count = 0
    for _ in value.utf8.prefix(maximum + 1) { count += 1 }
    return count
}

private func toolbarPresentationOpaqueID(
    _ components: [String],
    budget: ToolbarPresentationWorkBudget
) throws -> String {
    let maximumComponentBytes = budget.maximumStringUTF8Bytes
    let maximumTotalBytes = budget.maximumTotalStringUTF8Bytes
    var totalBytes = 0
    var hasher = SHA256()
    let domain = Data("toolbar-presentation-finding-v1".utf8)
    try budget.consume(UInt64(domain.count) + 1)
    hasher.update(data: domain)
    for component in components {
        try budget.checkCancellation()
        let byteCount = toolbarPresentationBoundedUTF8Count(
            component,
            maximum: maximumComponentBytes
        )
        guard byteCount <= maximumComponentBytes else {
            throw ToolbarPresentationEvidenceWorkflowError.stringTooLarge(
                maximumUTF8Bytes: maximumComponentBytes
            )
        }
        let (nextTotal, overflow) = totalBytes.addingReportingOverflow(byteCount)
        guard !overflow, nextTotal <= maximumTotalBytes else {
            throw ToolbarPresentationEvidenceWorkflowError.totalStringsTooLarge(
                maximumUTF8Bytes: maximumTotalBytes
            )
        }
        var length = UInt64(byteCount).bigEndian
        try budget.consume(UInt64(MemoryLayout<UInt64>.size) + 1)
        withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
        var bytes = component.utf8.makeIterator()
        var chunk = [UInt8]()
        chunk.reserveCapacity(4_096)
        while let byte = bytes.next() {
            chunk.append(byte)
            guard chunk.count == 4_096 else { continue }
            try budget.consume(UInt64(chunk.count))
            hasher.update(data: Data(chunk))
            chunk.removeAll(keepingCapacity: true)
        }
        if !chunk.isEmpty {
            try budget.consume(UInt64(chunk.count))
            hasher.update(data: Data(chunk))
        }
        totalBytes = nextTotal
    }
    try budget.checkCancellation()
    let hexadecimal = Array("0123456789abcdef".utf8)
    var bytes = [UInt8]()
    bytes.reserveCapacity(SHA256.Digest.byteCount * 2)
    for byte in hasher.finalize() {
        try budget.consume(2)
        bytes.append(hexadecimal[Int(byte >> 4)])
        bytes.append(hexadecimal[Int(byte & 0x0F)])
    }
    return String(decoding: bytes, as: UTF8.self)
}

private func toolbarPresentationGeometryPixelDimensions(
    _ geometry: ToolbarPresentationCaptureGeometry
) -> (width: Int, height: Int)? {
    guard toolbarPresentationValidCaptureGeometry(geometry) else { return nil }
    let scale = geometry.backingScaleThousandths
    let (scaledWidth, widthOverflow) = geometry.window.width.multipliedReportingOverflow(by: scale)
    let (scaledHeight, heightOverflow) = geometry.window.height.multipliedReportingOverflow(by: scale)
    guard !widthOverflow, !heightOverflow,
        scaledWidth.isMultiple(of: 1_000),
        scaledHeight.isMultiple(of: 1_000)
    else { return nil }
    let width = scaledWidth / 1_000
    let height = scaledHeight / 1_000
    guard toolbarPresentationValidImageDimensions(width: width, height: height) else { return nil }
    return (width, height)
}

private func toolbarPresentationValidRect(_ rect: ToolbarPresentationEvidenceRect) -> Bool {
    guard rect.width > 0, rect.height > 0 else { return false }
    let (_, xOverflow) = rect.x.addingReportingOverflow(rect.width)
    let (_, yOverflow) = rect.y.addingReportingOverflow(rect.height)
    return !xOverflow && !yOverflow
}

private func toolbarPresentationRectContains(
    _ outer: ToolbarPresentationEvidenceRect,
    _ inner: ToolbarPresentationEvidenceRect
) -> Bool {
    guard toolbarPresentationValidRect(outer), toolbarPresentationValidRect(inner) else {
        return false
    }
    let (outerMaximumX, outerXOverflow) = outer.x.addingReportingOverflow(outer.width)
    let (outerMaximumY, outerYOverflow) = outer.y.addingReportingOverflow(outer.height)
    let (innerMaximumX, innerXOverflow) = inner.x.addingReportingOverflow(inner.width)
    let (innerMaximumY, innerYOverflow) = inner.y.addingReportingOverflow(inner.height)
    guard !outerXOverflow, !outerYOverflow, !innerXOverflow, !innerYOverflow else {
        return false
    }
    return inner.x >= outer.x && inner.y >= outer.y
        && innerMaximumX <= outerMaximumX && innerMaximumY <= outerMaximumY
}

private func toolbarPresentationRectIntersects(
    _ left: ToolbarPresentationEvidenceRect,
    _ right: ToolbarPresentationEvidenceRect
) -> Bool {
    let (leftMaximumX, leftXOverflow) = left.x.addingReportingOverflow(left.width)
    let (leftMaximumY, leftYOverflow) = left.y.addingReportingOverflow(left.height)
    let (rightMaximumX, rightXOverflow) = right.x.addingReportingOverflow(right.width)
    let (rightMaximumY, rightYOverflow) = right.y.addingReportingOverflow(right.height)
    guard !leftXOverflow, !leftYOverflow, !rightXOverflow, !rightYOverflow else { return false }
    return left.x < rightMaximumX && right.x < leftMaximumX
        && left.y < rightMaximumY && right.y < leftMaximumY
}

private func toolbarPresentationHorizontallyPrecedes(
    _ left: ToolbarPresentationEvidenceRect,
    _ right: ToolbarPresentationEvidenceRect
) -> Bool {
    guard toolbarPresentationValidRect(left), toolbarPresentationValidRect(right) else { return false }
    let (leftMaximumX, overflow) = left.x.addingReportingOverflow(left.width)
    return !overflow && leftMaximumX <= right.x
}

private func toolbarPresentationStrictlyPrecedes(
    _ upper: ToolbarPresentationEvidenceRect,
    _ lower: ToolbarPresentationEvidenceRect
) -> Bool {
    guard toolbarPresentationValidRect(upper), toolbarPresentationValidRect(lower) else { return false }
    let (upperMaximumY, overflow) = upper.y.addingReportingOverflow(upper.height)
    return !overflow && upperMaximumY <= lower.y
}

private func toolbarPresentationPixelRect(
    _ rect: ToolbarPresentationEvidenceRect,
    in geometry: ToolbarPresentationCaptureGeometry,
    dimensions: (width: Int, height: Int)
) -> (x: Int, y: Int, width: Int, height: Int)? {
    let values = [
        rect.x - geometry.window.x, rect.y - geometry.window.y, rect.width, rect.height
    ]
    var scaledValues: [Int] = []
    scaledValues.reserveCapacity(values.count)
    for value in values {
        let (scaled, overflow) = value.multipliedReportingOverflow(
            by: geometry.backingScaleThousandths
        )
        guard !overflow, scaled.isMultiple(of: 1_000) else { return nil }
        scaledValues.append(scaled / 1_000)
    }
    let result = (
        x: scaledValues[0],
        y: dimensions.height - scaledValues[1] - scaledValues[3],
        width: scaledValues[2],
        height: scaledValues[3]
    )
    guard result.x >= 0, result.y >= 0, result.width > 0, result.height > 0,
        result.x <= dimensions.width - result.width,
        result.y <= dimensions.height - result.height
    else { return nil }
    return result
}

private func toolbarPresentationPixelRectContains(
    _ rect: (x: Int, y: Int, width: Int, height: Int),
    x: Int,
    y: Int
) -> Bool {
    x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height
}

private func toolbarPresentationValidCaptureGeometry(
    _ geometry: ToolbarPresentationCaptureGeometry
) -> Bool {
    let maximumLogicalDimension = 16_384
    let maximumCoordinateMagnitude = 1_000_000
    guard toolbarPresentationValidRect(geometry.window),
        toolbarPresentationValidRect(geometry.toolbar),
        toolbarPresentationRectContains(geometry.window, geometry.toolbar),
        geometry.window.width <= maximumLogicalDimension,
        geometry.window.height <= maximumLogicalDimension,
        geometry.toolbar.width <= maximumLogicalDimension,
        geometry.toolbar.height <= maximumLogicalDimension,
        geometry.window.x >= -maximumCoordinateMagnitude,
        geometry.window.y >= -maximumCoordinateMagnitude,
        geometry.window.x <= maximumCoordinateMagnitude,
        geometry.window.y <= maximumCoordinateMagnitude,
        (1_000...8_000).contains(geometry.backingScaleThousandths)
    else { return false }
    let scale = geometry.backingScaleThousandths
    let (_, widthOverflow) = geometry.window.width.multipliedReportingOverflow(by: scale)
    let (_, heightOverflow) = geometry.window.height.multipliedReportingOverflow(by: scale)
    return !widthOverflow && !heightOverflow
}

private func toolbarPresentationIsBlank(_ value: String) -> Bool {
    value.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
}

private func toolbarPresentationSHA256(
    _ data: Data,
    budget: ToolbarPresentationWorkBudget
) throws -> [UInt8] {
    var hasher = SHA256()
    let chunkSize = 64 * 1_024
    var index = data.startIndex
    while index < data.endIndex {
        try budget.checkCancellation()
        let end = data.index(index, offsetBy: chunkSize, limitedBy: data.endIndex) ?? data.endIndex
        hasher.update(data: data[index..<end])
        try budget.consume(UInt64(data.distance(from: index, to: end)) + 1)
        index = end
    }
    return Array(hasher.finalize())
}

private func toolbarPresentationSorted<Element>(
    _ values: [Element],
    by areInIncreasingOrder: (Element, Element) throws -> Bool,
    budget: ToolbarPresentationWorkBudget
) throws -> ToolbarPresentationRetainedArray<Element> {
    guard values.count > 1 else {
        try budget.consume(UInt64(values.count) + 1)
        let retainedByteCharge = toolbarPresentationCollectionCharge(
            count: values.count,
            stride: MemoryLayout<Element>.stride
        )
        try budget.consumeMemory(retainedByteCharge)
        return ToolbarPresentationRetainedArray(
            values: values,
            retainedByteCharge: retainedByteCharge,
            budget: budget
        )
    }
    let oneBufferCharge = toolbarPresentationCollectionCharge(
        count: values.count,
        stride: MemoryLayout<Element>.stride
    )
    let (bufferCharge, overflow) = oneBufferCharge.multipliedReportingOverflow(by: 2)
    guard !overflow else {
        throw ToolbarPresentationEvidenceWorkflowError.aggregateMemoryExceeded(
            maximumBytes: ToolbarPresentationEvidenceLimits.hardMaximumAggregateMemoryBytes
        )
    }
    try budget.consumeMemory(bufferCharge)
    var retainsResult = false
    defer { budget.releaseMemory(retainsResult ? oneBufferCharge : bufferCharge) }
    var source = values
    var destination = values
    var width = 1
    while width < values.count {
        var start = 0
        while start < values.count {
            let middle = min(start + width, values.count)
            let end = min(middle + width, values.count)
            var left = start
            var right = middle
            var output = start
            while left < middle || right < end {
                try budget.consume()
                let takeLeft: Bool
                if right >= end {
                    takeLeft = true
                } else if left >= middle {
                    takeLeft = false
                } else {
                    takeLeft = try !areInIncreasingOrder(source[right], source[left])
                }
                if takeLeft {
                    destination[output] = source[left]
                    left += 1
                } else {
                    destination[output] = source[right]
                    right += 1
                }
                output += 1
            }
            start = end
        }
        swap(&source, &destination)
        let (nextWidth, widthOverflow) = width.multipliedReportingOverflow(by: 2)
        width = widthOverflow ? values.count : min(nextWidth, values.count)
    }
    retainsResult = true
    return ToolbarPresentationRetainedArray(
        values: source,
        retainedByteCharge: oneBufferCharge,
        budget: budget
    )
}

private func toolbarPresentationCollectionCharge(count: Int, stride: Int) -> UInt64 {
    let (bytes, overflow) = count.multipliedReportingOverflow(by: stride)
    return overflow ? UInt64.max : UInt64(bytes)
}

private func toolbarPresentationCompareData(
    _ left: Data,
    _ right: Data,
    budget: ToolbarPresentationWorkBudget
) throws -> Int {
    var leftIndex = left.startIndex
    var rightIndex = right.startIndex
    while leftIndex < left.endIndex, rightIndex < right.endIndex {
        try budget.consume()
        let leftByte = left[leftIndex]
        let rightByte = right[rightIndex]
        if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
        left.formIndex(after: &leftIndex)
        right.formIndex(after: &rightIndex)
    }
    if leftIndex == left.endIndex, rightIndex == right.endIndex { return 0 }
    return leftIndex == left.endIndex ? -1 : 1
}

private func toolbarPresentationDataEqual(
    _ left: Data,
    _ right: Data,
    budget: ToolbarPresentationWorkBudget
) throws -> Bool {
    guard left.count == right.count else { return false }
    let chunkSize = 64 * 1_024
    var leftIndex = left.startIndex
    var rightIndex = right.startIndex
    while leftIndex < left.endIndex {
        let leftEnd =
            left.index(leftIndex, offsetBy: chunkSize, limitedBy: left.endIndex) ?? left.endIndex
        let distance = left.distance(from: leftIndex, to: leftEnd)
        let rightEnd = right.index(rightIndex, offsetBy: distance)
        try budget.consume(UInt64(distance) + 1)
        guard left[leftIndex..<leftEnd].elementsEqual(right[rightIndex..<rightEnd]) else {
            return false
        }
        leftIndex = leftEnd
        rightIndex = rightEnd
    }
    return true
}
