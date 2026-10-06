import CryptoKit
import Foundation

public enum VerificationEvidenceIdentifierDomain {
    public enum RoadmapManifest: Sendable {}
    public enum RoadmapRow: Sendable {}
    public enum Ledger: Sendable {}
    public enum Application: Sendable {}
    public enum Build: Sendable {}
    public enum TestRun: Sendable {}
    public enum Artifact: Sendable {}
    public enum Citation: Sendable {}
    public enum Principal: Sendable {}
}

/// Caller-owned stable identity. Identity is never inferred from roadmap text, position, or a path.
public struct VerificationEvidenceIdentifier<Domain>: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.precomposedStringWithCanonicalMapping
    }

    public static func < (left: Self, right: Self) -> Bool {
        verificationEvidenceCompareUTF8(left.rawValue, right.rawValue) < 0
    }
}

public struct VerificationEvidenceRevision: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}

public struct VerificationEvidenceRevisionReference<Domain>: Comparable, Hashable, Sendable {
    public let id: VerificationEvidenceIdentifier<Domain>
    public let revision: VerificationEvidenceRevision

    public init(
        id: VerificationEvidenceIdentifier<Domain>,
        revision: VerificationEvidenceRevision
    ) {
        self.id = id
        self.revision = revision
    }

    public static func < (left: Self, right: Self) -> Bool {
        if left.id != right.id { return left.id < right.id }
        return left.revision < right.revision
    }
}

public typealias VerificationRoadmapManifestID =
    VerificationEvidenceIdentifier<VerificationEvidenceIdentifierDomain.RoadmapManifest>
public typealias VerificationRoadmapRowID =
    VerificationEvidenceIdentifier<VerificationEvidenceIdentifierDomain.RoadmapRow>
public typealias VerificationEvidenceLedgerID =
    VerificationEvidenceIdentifier<VerificationEvidenceIdentifierDomain.Ledger>
public typealias VerificationEvidenceApplicationID =
    VerificationEvidenceIdentifier<VerificationEvidenceIdentifierDomain.Application>
public typealias VerificationEvidenceBuildID =
    VerificationEvidenceIdentifier<VerificationEvidenceIdentifierDomain.Build>
public typealias VerificationEvidenceTestRunID =
    VerificationEvidenceIdentifier<VerificationEvidenceIdentifierDomain.TestRun>
public typealias VerificationEvidenceArtifactID =
    VerificationEvidenceIdentifier<VerificationEvidenceIdentifierDomain.Artifact>
public typealias VerificationEvidenceCitationID =
    VerificationEvidenceIdentifier<VerificationEvidenceIdentifierDomain.Citation>
public typealias VerificationEvidencePrincipalID =
    VerificationEvidenceIdentifier<VerificationEvidenceIdentifierDomain.Principal>

public typealias VerificationRoadmapManifestReference =
    VerificationEvidenceRevisionReference<VerificationEvidenceIdentifierDomain.RoadmapManifest>
public typealias VerificationRoadmapRowReference =
    VerificationEvidenceRevisionReference<VerificationEvidenceIdentifierDomain.RoadmapRow>
public typealias VerificationEvidenceLedgerReference =
    VerificationEvidenceRevisionReference<VerificationEvidenceIdentifierDomain.Ledger>
public typealias VerificationEvidenceApplicationReference =
    VerificationEvidenceRevisionReference<VerificationEvidenceIdentifierDomain.Application>
public typealias VerificationEvidenceBuildReference =
    VerificationEvidenceRevisionReference<VerificationEvidenceIdentifierDomain.Build>
public typealias VerificationEvidenceTestRunReference =
    VerificationEvidenceRevisionReference<VerificationEvidenceIdentifierDomain.TestRun>

public enum VerificationEvidenceKind: String, CaseIterable, Comparable, Hashable, Sendable {
    case modelOrUnit
    case uiInteraction
    case semanticAccessibility
    case persistence
    case packagedAppSmoke

    public static func < (left: Self, right: Self) -> Bool {
        verificationEvidenceEnumRank(left) < verificationEvidenceEnumRank(right)
    }
}

public enum VerificationRoadmapStatefulness: String, CaseIterable, Hashable, Sendable {
    case stateless
    case stateful
}

public enum VerificationRoadmapApplicability: Hashable, Sendable {
    case applicable(statefulness: VerificationRoadmapStatefulness)
    case notApplicable

    public var requiredEvidenceKinds: Set<VerificationEvidenceKind> {
        switch self {
        case .notApplicable:
            []
        case .applicable(.stateless):
            [.modelOrUnit, .uiInteraction, .semanticAccessibility, .packagedAppSmoke]
        case .applicable(.stateful):
            Set(VerificationEvidenceKind.allCases)
        }
    }
}

/// One roadmap row declaration. `completionClaimed` triggers audit; it does not establish completion.
public struct VerificationRoadmapRowRequirement: Identifiable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public var id: VerificationRoadmapRowID { reference.id }

    public let reference: VerificationRoadmapRowReference
    public let applicability: VerificationRoadmapApplicability
    public let completionClaimed: Bool

    public init(
        reference: VerificationRoadmapRowReference,
        applicability: VerificationRoadmapApplicability,
        completionClaimed: Bool
    ) {
        self.reference = reference
        self.applicability = applicability
        self.completionClaimed = completionClaimed
    }

    public var requiredEvidenceKinds: Set<VerificationEvidenceKind> {
        applicability.requiredEvidenceKinds
    }

    public var description: String {
        "VerificationRoadmapRowRequirement(completionClaimed: \(completionClaimed), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["completionClaimed": completionClaimed, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// Caller-supplied roadmap semantics only. This type never reads or parses a roadmap document.
public struct VerificationRoadmapManifest: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: VerificationRoadmapManifestReference
    public let rows: [VerificationRoadmapRowRequirement]

    public init(
        reference: VerificationRoadmapManifestReference,
        rows: [VerificationRoadmapRowRequirement]
    ) {
        self.reference = reference
        self.rows = rows
    }

    public var description: String {
        "VerificationRoadmapManifest(rows: \(rows.count), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["rowCount": rows.count, "contents": "<redacted>"], displayStyle: .struct)
    }
}

public enum VerificationEvidenceDigestAlgorithm: String, CaseIterable, Hashable, Sendable {
    case sha256
}

public struct VerificationEvidenceDigest: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let algorithm: VerificationEvidenceDigestAlgorithm
    public let bytes: [UInt8]

    public init(
        algorithm: VerificationEvidenceDigestAlgorithm = .sha256,
        bytes: [UInt8]
    ) {
        self.algorithm = algorithm
        self.bytes = bytes
    }

    public var description: String { "VerificationEvidenceDigest(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["digest": "<redacted>"], displayStyle: .struct)
    }
}

public enum VerificationEvidenceArtifactRole: String, CaseIterable, Hashable, Sendable {
    case applicationBundle
    case executable
    case signingIdentity
    case testRunner
    case testBundle
    case testConfiguration
    case evidenceAttachment
}

/// Exact immutable artifact identity. Payload resolution remains outside this UI-independent model.
public struct VerificationEvidenceArtifactReference: Identifiable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let id: VerificationEvidenceArtifactID
    public let role: VerificationEvidenceArtifactRole
    public let mediaType: String
    public let byteCount: UInt64
    public let digest: VerificationEvidenceDigest

    public init(
        id: VerificationEvidenceArtifactID,
        role: VerificationEvidenceArtifactRole,
        mediaType: String,
        byteCount: UInt64,
        digest: VerificationEvidenceDigest
    ) {
        self.id = id
        self.role = role
        self.mediaType = mediaType.precomposedStringWithCanonicalMapping
        self.byteCount = byteCount
        self.digest = digest
    }

    public var description: String {
        "VerificationEvidenceArtifactReference(role: \(role.rawValue), bytes: \(byteCount), metadata: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "role": role,
                "byteCount": byteCount,
                "metadata": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Exact packaged application and executable identity used by every cited run.
public struct VerificationEvidenceAppBuildProvenance: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let application: VerificationEvidenceApplicationReference
    public let build: VerificationEvidenceBuildReference
    public let applicationBundle: VerificationEvidenceArtifactReference
    public let executable: VerificationEvidenceArtifactReference
    /// Canonical signing-information artifact, such as a DER certificate chain.
    public let signingIdentity: VerificationEvidenceArtifactReference

    public init(
        application: VerificationEvidenceApplicationReference,
        build: VerificationEvidenceBuildReference,
        applicationBundle: VerificationEvidenceArtifactReference,
        executable: VerificationEvidenceArtifactReference,
        signingIdentity: VerificationEvidenceArtifactReference
    ) {
        self.application = application
        self.build = build
        self.applicationBundle = applicationBundle
        self.executable = executable
        self.signingIdentity = signingIdentity
    }

    public var description: String {
        "VerificationEvidenceAppBuildProvenance(<redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["provenance": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public enum VerificationEvidenceTestRunOutcome: String, CaseIterable, Hashable, Sendable {
    case passed
    case failed
    case cancelled
    case inconclusive
}

public struct VerificationEvidenceTestRunProvenance: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let reference: VerificationEvidenceTestRunReference
    public let build: VerificationEvidenceAppBuildProvenance
    public let testRunner: VerificationEvidenceArtifactReference
    public let testBundle: VerificationEvidenceArtifactReference
    /// Canonical test invocation/configuration artifact, including arguments and environment policy.
    public let configuration: VerificationEvidenceArtifactReference
    public let startedAtUnixMilliseconds: UInt64
    public let finishedAtUnixMilliseconds: UInt64
    public let outcome: VerificationEvidenceTestRunOutcome

    public init(
        reference: VerificationEvidenceTestRunReference,
        build: VerificationEvidenceAppBuildProvenance,
        testRunner: VerificationEvidenceArtifactReference,
        testBundle: VerificationEvidenceArtifactReference,
        configuration: VerificationEvidenceArtifactReference,
        startedAtUnixMilliseconds: UInt64,
        finishedAtUnixMilliseconds: UInt64,
        outcome: VerificationEvidenceTestRunOutcome
    ) {
        self.reference = reference
        self.build = build
        self.testRunner = testRunner
        self.testBundle = testBundle
        self.configuration = configuration
        self.startedAtUnixMilliseconds = startedAtUnixMilliseconds
        self.finishedAtUnixMilliseconds = finishedAtUnixMilliseconds
        self.outcome = outcome
    }

    public var description: String {
        "VerificationEvidenceTestRunProvenance(outcome: \(outcome.rawValue), details: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["outcome": outcome, "details": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public enum VerificationEvidenceAttachmentKind: String, CaseIterable, Hashable, Sendable {
    case modelOrUnitRecord
    case uiInteractionRecord
    case semanticAccessibilityRecord
    case persistenceRecord
    case packagedAppSmokeRecord
    case screenshot
    case video
    case transcript
    case log
}

public struct VerificationEvidenceAttachmentReference: Identifiable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public var id: VerificationEvidenceArtifactID { artifact.id }

    public let kind: VerificationEvidenceAttachmentKind
    public let artifact: VerificationEvidenceArtifactReference

    public init(
        kind: VerificationEvidenceAttachmentKind,
        artifact: VerificationEvidenceArtifactReference
    ) {
        self.kind = kind
        self.artifact = artifact
    }

    public var description: String {
        "VerificationEvidenceAttachmentReference(kind: \(kind.rawValue), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["kind": kind, "contents": "<redacted>"], displayStyle: .struct)
    }
}

public enum VerificationEvidenceObservationBasis: String, CaseIterable, Hashable, Sendable {
    case measured
    case asserted
}

public enum VerificationEvidenceObservationOutcome: String, CaseIterable, Hashable, Sendable {
    case passed
    case failed
    case inconclusive
}

public struct VerificationEvidenceCollectorAttestation: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let collectorID: VerificationEvidencePrincipalID
    public let attestedAtUnixMilliseconds: UInt64
    /// Ed25519 signature over `VerificationEvidenceAuditor.collectorSigningData(for:)`.
    public let signature: [UInt8]

    public init(
        collectorID: VerificationEvidencePrincipalID,
        attestedAtUnixMilliseconds: UInt64,
        signature: [UInt8]
    ) {
        self.collectorID = collectorID
        self.attestedAtUnixMilliseconds = attestedAtUnixMilliseconds
        self.signature = signature
    }

    public var description: String {
        "VerificationEvidenceCollectorAttestation(<redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["attestation": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public enum VerificationEvidenceReviewVerdict: String, CaseIterable, Hashable, Sendable {
    case accepted
    case rejected
}

public struct VerificationEvidenceReviewAttestation: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let reviewerID: VerificationEvidencePrincipalID
    public let verdict: VerificationEvidenceReviewVerdict
    public let reviewedAtUnixMilliseconds: UInt64
    public let expiresAtUnixMilliseconds: UInt64?
    public let evidenceClaimSHA256: VerificationEvidenceDigest
    /// Ed25519 signature over `VerificationEvidenceAuditor.reviewerSigningData(for:review:)`.
    public let signature: [UInt8]

    public init(
        reviewerID: VerificationEvidencePrincipalID,
        verdict: VerificationEvidenceReviewVerdict,
        reviewedAtUnixMilliseconds: UInt64,
        expiresAtUnixMilliseconds: UInt64? = nil,
        evidenceClaimSHA256: VerificationEvidenceDigest,
        signature: [UInt8]
    ) {
        self.reviewerID = reviewerID
        self.verdict = verdict
        self.reviewedAtUnixMilliseconds = reviewedAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        self.evidenceClaimSHA256 = evidenceClaimSHA256
        self.signature = signature
    }

    public var description: String {
        "VerificationEvidenceReviewAttestation(verdict: \(verdict.rawValue), contents: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["verdict": verdict, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// Auditor statement bound to exact canonical manifest, ledger, and trust-policy bytes.
/// `auditedAtUnixMilliseconds` is signed provenance, not a trusted verification clock.
public struct VerificationEvidenceAuditAttestation: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let auditorID: VerificationEvidencePrincipalID
    /// Submitter identity authenticated by the trusted auditor, not read from submitted ledger data.
    public let submitterID: VerificationEvidencePrincipalID
    public let auditedAtUnixMilliseconds: UInt64
    public let trustedVerificationTimeUnixMilliseconds: UInt64
    public let manifestSHA256: VerificationEvidenceDigest
    public let ledgerSHA256: VerificationEvidenceDigest
    public let trustPolicySHA256: VerificationEvidenceDigest
    public let reportSHA256: VerificationEvidenceDigest
    public let archiveSHA256: VerificationEvidenceDigest
    /// Ed25519 signature over `VerificationEvidenceAuditor.auditSigningData(...)`.
    public let signature: [UInt8]

    public init(
        auditorID: VerificationEvidencePrincipalID,
        submitterID: VerificationEvidencePrincipalID,
        auditedAtUnixMilliseconds: UInt64,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        manifestSHA256: VerificationEvidenceDigest,
        ledgerSHA256: VerificationEvidenceDigest,
        trustPolicySHA256: VerificationEvidenceDigest,
        reportSHA256: VerificationEvidenceDigest,
        archiveSHA256: VerificationEvidenceDigest,
        signature: [UInt8]
    ) {
        self.auditorID = auditorID
        self.submitterID = submitterID
        self.auditedAtUnixMilliseconds = auditedAtUnixMilliseconds
        self.trustedVerificationTimeUnixMilliseconds = trustedVerificationTimeUnixMilliseconds
        self.manifestSHA256 = manifestSHA256
        self.ledgerSHA256 = ledgerSHA256
        self.trustPolicySHA256 = trustPolicySHA256
        self.reportSHA256 = reportSHA256
        self.archiveSHA256 = archiveSHA256
        self.signature = signature
    }

    public var description: String { "VerificationEvidenceAuditAttestation(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["attestation": "<redacted>"], displayStyle: .struct)
    }
}

/// Canonical result envelope. Sign `signingData`, then create its matching attestation.
public struct VerificationEvidenceAuditSigningEnvelope: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let schemaVersion: Int
    public let auditorID: VerificationEvidencePrincipalID
    public let submitterID: VerificationEvidencePrincipalID
    public let auditedAtUnixMilliseconds: UInt64
    public let trustedVerificationTimeUnixMilliseconds: UInt64
    public let manifestSHA256: VerificationEvidenceDigest
    public let ledgerSHA256: VerificationEvidenceDigest
    public let trustPolicySHA256: VerificationEvidenceDigest
    public let reportSHA256: VerificationEvidenceDigest
    public let archiveSHA256: VerificationEvidenceDigest
    public let signingData: Data

    fileprivate init(
        attestation: VerificationEvidenceAuditAttestation,
        signingData: Data
    ) {
        schemaVersion = VerificationEvidenceAuditor.schemaVersion
        auditorID = attestation.auditorID
        submitterID = attestation.submitterID
        auditedAtUnixMilliseconds = attestation.auditedAtUnixMilliseconds
        trustedVerificationTimeUnixMilliseconds =
            attestation.trustedVerificationTimeUnixMilliseconds
        manifestSHA256 = attestation.manifestSHA256
        ledgerSHA256 = attestation.ledgerSHA256
        trustPolicySHA256 = attestation.trustPolicySHA256
        reportSHA256 = attestation.reportSHA256
        archiveSHA256 = attestation.archiveSHA256
        self.signingData = signingData
    }

    public func attestation(signature: [UInt8]) -> VerificationEvidenceAuditAttestation {
        VerificationEvidenceAuditAttestation(
            auditorID: auditorID,
            submitterID: submitterID,
            auditedAtUnixMilliseconds: auditedAtUnixMilliseconds,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            manifestSHA256: manifestSHA256,
            ledgerSHA256: ledgerSHA256,
            trustPolicySHA256: trustPolicySHA256,
            reportSHA256: reportSHA256,
            archiveSHA256: archiveSHA256,
            signature: signature
        )
    }

    public var description: String { "VerificationEvidenceAuditSigningEnvelope(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["envelope": "<redacted>"], displayStyle: .struct)
    }
}

/// One exact row/kind citation. Assertions and unsigned metadata never satisfy a requirement.
public struct VerificationEvidenceCitation: Identifiable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let id: VerificationEvidenceCitationID
    public let row: VerificationRoadmapRowReference
    public let kind: VerificationEvidenceKind
    public let basis: VerificationEvidenceObservationBasis
    public let outcome: VerificationEvidenceObservationOutcome
    public let collectedAtUnixMilliseconds: UInt64
    public let expiresAtUnixMilliseconds: UInt64?
    public let testRun: VerificationEvidenceTestRunProvenance
    public let attachments: [VerificationEvidenceAttachmentReference]
    public let collectorAttestation: VerificationEvidenceCollectorAttestation
    public let reviews: [VerificationEvidenceReviewAttestation]

    public init(
        id: VerificationEvidenceCitationID,
        row: VerificationRoadmapRowReference,
        kind: VerificationEvidenceKind,
        basis: VerificationEvidenceObservationBasis,
        outcome: VerificationEvidenceObservationOutcome,
        collectedAtUnixMilliseconds: UInt64,
        expiresAtUnixMilliseconds: UInt64? = nil,
        testRun: VerificationEvidenceTestRunProvenance,
        attachments: [VerificationEvidenceAttachmentReference],
        collectorAttestation: VerificationEvidenceCollectorAttestation,
        reviews: [VerificationEvidenceReviewAttestation]
    ) {
        self.id = id
        self.row = row
        self.kind = kind
        self.basis = basis
        self.outcome = outcome
        self.collectedAtUnixMilliseconds = collectedAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        self.testRun = testRun
        self.attachments = attachments
        self.collectorAttestation = collectorAttestation
        self.reviews = reviews
    }

    public var description: String {
        "VerificationEvidenceCitation(kind: \(kind.rawValue), evidence: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": kind,
                "basis": basis,
                "outcome": outcome,
                "attachmentCount": attachments.count,
                "reviewCount": reviews.count,
                "evidence": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Caller-supplied citations only. No initializer performs test, UI, AX, filesystem, or network work.
public struct VerificationEvidenceLedger: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reference: VerificationEvidenceLedgerReference
    public let manifest: VerificationRoadmapManifestReference
    public let targetBuild: VerificationEvidenceAppBuildProvenance
    public let citations: [VerificationEvidenceCitation]

    public init(
        reference: VerificationEvidenceLedgerReference,
        manifest: VerificationRoadmapManifestReference,
        targetBuild: VerificationEvidenceAppBuildProvenance,
        citations: [VerificationEvidenceCitation]
    ) {
        self.reference = reference
        self.manifest = manifest
        self.targetBuild = targetBuild
        self.citations = citations
    }

    public var description: String {
        "VerificationEvidenceLedger(citations: \(citations.count), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["citationCount": citations.count, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }

    public func audit(
        against manifest: VerificationRoadmapManifest,
        trustPolicy: VerificationEvidenceTrustPolicy,
        auditAttestation: VerificationEvidenceAuditAttestation,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        limits: VerificationEvidenceLedgerLimits = .default,
        cancellationCheck: @escaping VerificationEvidenceAuditor.CancellationCheck = {
            Task.isCancelled
        }
    ) throws -> VerificationEvidenceAuditResult {
        try VerificationEvidenceAuditor.audit(
            manifest: manifest,
            ledger: self,
            trustPolicy: trustPolicy,
            auditAttestation: auditAttestation,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }
}

public enum VerificationEvidenceTrustRole: String, CaseIterable, Hashable, Sendable {
    case submitter
    case collector
    case reviewer
    case auditor
}

/// Caller-configured Ed25519 trust root. Production callers must source roots outside submitted data.
public struct VerificationEvidenceTrustRoot: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let principalID: VerificationEvidencePrincipalID
    public let roles: Set<VerificationEvidenceTrustRole>
    public let ed25519PublicKey: [UInt8]
    public let validFromUnixMilliseconds: UInt64
    public let validThroughUnixMilliseconds: UInt64
    public let revokedAtUnixMilliseconds: UInt64?

    public init(
        principalID: VerificationEvidencePrincipalID,
        roles: Set<VerificationEvidenceTrustRole>,
        ed25519PublicKey: [UInt8],
        validFromUnixMilliseconds: UInt64,
        validThroughUnixMilliseconds: UInt64,
        revokedAtUnixMilliseconds: UInt64? = nil
    ) {
        self.principalID = principalID
        self.roles = roles
        self.ed25519PublicKey = ed25519PublicKey
        self.validFromUnixMilliseconds = validFromUnixMilliseconds
        self.validThroughUnixMilliseconds = validThroughUnixMilliseconds
        self.revokedAtUnixMilliseconds = revokedAtUnixMilliseconds
    }

    public var description: String {
        "VerificationEvidenceTrustRoot(roles: \(roles.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["roleCount": roles.count, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public struct VerificationEvidenceFreshnessPolicy: Hashable, Sendable {
    public static let dayMilliseconds: UInt64 = 86_400_000
    public static let `default` = VerificationEvidenceFreshnessPolicy()

    public let modelOrUnitMaximumAgeMilliseconds: UInt64
    public let uiInteractionMaximumAgeMilliseconds: UInt64
    public let semanticAccessibilityMaximumAgeMilliseconds: UInt64
    public let persistenceMaximumAgeMilliseconds: UInt64
    public let packagedAppSmokeMaximumAgeMilliseconds: UInt64
    public let maximumCollectionLagMilliseconds: UInt64

    public init(
        modelOrUnitMaximumAgeMilliseconds: UInt64 = 30 * dayMilliseconds,
        uiInteractionMaximumAgeMilliseconds: UInt64 = 14 * dayMilliseconds,
        semanticAccessibilityMaximumAgeMilliseconds: UInt64 = 14 * dayMilliseconds,
        persistenceMaximumAgeMilliseconds: UInt64 = 14 * dayMilliseconds,
        packagedAppSmokeMaximumAgeMilliseconds: UInt64 = 7 * dayMilliseconds,
        maximumCollectionLagMilliseconds: UInt64 = dayMilliseconds
    ) {
        self.modelOrUnitMaximumAgeMilliseconds = modelOrUnitMaximumAgeMilliseconds
        self.uiInteractionMaximumAgeMilliseconds = uiInteractionMaximumAgeMilliseconds
        self.semanticAccessibilityMaximumAgeMilliseconds = semanticAccessibilityMaximumAgeMilliseconds
        self.persistenceMaximumAgeMilliseconds = persistenceMaximumAgeMilliseconds
        self.packagedAppSmokeMaximumAgeMilliseconds = packagedAppSmokeMaximumAgeMilliseconds
        self.maximumCollectionLagMilliseconds = maximumCollectionLagMilliseconds
    }

    public func maximumAgeMilliseconds(for kind: VerificationEvidenceKind) -> UInt64 {
        switch kind {
        case .modelOrUnit: modelOrUnitMaximumAgeMilliseconds
        case .uiInteraction: uiInteractionMaximumAgeMilliseconds
        case .semanticAccessibility: semanticAccessibilityMaximumAgeMilliseconds
        case .persistence: persistenceMaximumAgeMilliseconds
        case .packagedAppSmoke: packagedAppSmokeMaximumAgeMilliseconds
        }
    }
}

public struct VerificationEvidenceTrustPolicy: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let roots: [VerificationEvidenceTrustRoot]
    public let freshness: VerificationEvidenceFreshnessPolicy

    public init(
        roots: [VerificationEvidenceTrustRoot],
        freshness: VerificationEvidenceFreshnessPolicy = .default
    ) {
        self.roots = roots
        self.freshness = freshness
    }

    public var description: String {
        "VerificationEvidenceTrustPolicy(roots: \(roots.count), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["rootCount": roots.count, "contents": "<redacted>"], displayStyle: .struct)
    }
}

public enum VerificationEvidenceLedgerLimit: String, CaseIterable, Hashable, Sendable {
    case rows
    case citations
    case attachments
    case attachmentsPerCitation
    case reviews
    case reviewsPerCitation
    case trustRoots
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case binaryFieldBytes
    case signingPayloadBytes
    case canonicalRecordBytes
    case totalItems
    case workUnits
    case findings
    case archiveBytes
    case cancellationCheckInterval
}

public struct VerificationEvidenceLedgerLimits: Hashable, Sendable {
    public static let hardMaximumCount = 1_000_000
    public static let hardMaximumStringUTF8Bytes = 1 * 1_024 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 128 * 1_024 * 1_024
    public static let hardMaximumBinaryFieldBytes = 4_096
    public static let hardMaximumSigningPayloadBytes = 16 * 1_024 * 1_024
    public static let hardMaximumCanonicalRecordBytes = 64 * 1_024 * 1_024
    public static let hardMaximumTotalItems = 4_000_000
    public static let hardMaximumWorkUnits: UInt64 = 1 << 40
    public static let hardMaximumFindings = 1_000_000
    public static let hardMaximumArchiveBytes = 512 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = VerificationEvidenceLedgerLimits()

    public let maximumRows: Int
    public let maximumCitations: Int
    public let maximumAttachments: Int
    public let maximumAttachmentsPerCitation: Int
    public let maximumReviews: Int
    public let maximumReviewsPerCitation: Int
    public let maximumTrustRoots: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumBinaryFieldBytes: Int
    public let maximumSigningPayloadBytes: Int
    public let maximumCanonicalRecordBytes: Int
    public let maximumTotalItems: Int
    public let maximumWorkUnits: UInt64
    public let maximumFindings: Int
    public let maximumArchiveBytes: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumRows: Int = 100_000,
        maximumCitations: Int = 500_000,
        maximumAttachments: Int = 1_000_000,
        maximumAttachmentsPerCitation: Int = 32,
        maximumReviews: Int = 1_000_000,
        maximumReviewsPerCitation: Int = 8,
        maximumTrustRoots: Int = 10_000,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 32 * 1_024 * 1_024,
        maximumBinaryFieldBytes: Int = 1_024,
        maximumSigningPayloadBytes: Int = 4 * 1_024 * 1_024,
        maximumCanonicalRecordBytes: Int = 16 * 1_024 * 1_024,
        maximumTotalItems: Int = 4_000_000,
        maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
        maximumFindings: Int = 500_000,
        maximumArchiveBytes: Int = 256 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 256
    ) {
        self.maximumRows = maximumRows
        self.maximumCitations = maximumCitations
        self.maximumAttachments = maximumAttachments
        self.maximumAttachmentsPerCitation = maximumAttachmentsPerCitation
        self.maximumReviews = maximumReviews
        self.maximumReviewsPerCitation = maximumReviewsPerCitation
        self.maximumTrustRoots = maximumTrustRoots
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumBinaryFieldBytes = maximumBinaryFieldBytes
        self.maximumSigningPayloadBytes = maximumSigningPayloadBytes
        self.maximumCanonicalRecordBytes = maximumCanonicalRecordBytes
        self.maximumTotalItems = maximumTotalItems
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumFindings = maximumFindings
        self.maximumArchiveBytes = maximumArchiveBytes
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum VerificationEvidenceLedgerError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(VerificationEvidenceLedgerLimit)
    case countLimitExceeded(kind: VerificationEvidenceLedgerLimit, maximum: Int)
    case stringTooLarge(field: String, maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case binaryFieldTooLarge(maximumBytes: Int)
    case signingPayloadTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximum: UInt64)
    case findingLimitExceeded(maximum: Int)
    case archiveTooLarge(maximumBytes: Int)
    case integerOverflow
    case canonicalDigestCollision
    case invalidAuditAttestation
    case receiptMismatch

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Verification evidence audit was cancelled."
        case .invalidLimit(let limit):
            "Verification evidence limit is invalid: \(limit.rawValue)."
        case .countLimitExceeded(let kind, let maximum):
            "Verification evidence exceeds the \(maximum)-\(kind.rawValue) limit."
        case .stringTooLarge(let field, let maximum):
            "Verification evidence field \(field) exceeds \(maximum) UTF-8 bytes; contents are redacted."
        case .totalStringsTooLarge(let maximum):
            "Verification evidence strings exceed \(maximum) UTF-8 bytes; contents are redacted."
        case .binaryFieldTooLarge(let maximum):
            "Verification evidence cryptographic field exceeds \(maximum) bytes; contents are redacted."
        case .signingPayloadTooLarge(let maximum):
            "Verification evidence signing payload exceeds \(maximum) bytes; contents are redacted."
        case .workLimitExceeded(let maximum):
            "Verification evidence processing exceeds \(maximum) work units."
        case .findingLimitExceeded(let maximum):
            "Verification evidence processing exceeds \(maximum) findings."
        case .archiveTooLarge(let maximum):
            "Verification evidence archive exceeds \(maximum) bytes."
        case .integerOverflow:
            "Verification evidence input cannot be represented safely."
        case .canonicalDigestCollision:
            "Distinct canonical verification records produced one digest; audit stopped."
        case .invalidAuditAttestation:
            "Verification evidence audit time or trusted auditor attestation is invalid."
        case .receiptMismatch:
            "Verification evidence receipt no longer matches current canonical inputs."
        }
    }
}

public enum VerificationEvidenceFindingSeverity: String, CaseIterable, Comparable, Hashable, Sendable {
    case advisory
    case warning
    case error

    public static func < (left: Self, right: Self) -> Bool {
        verificationEvidenceEnumRank(left) < verificationEvidenceEnumRank(right)
    }
}

public enum VerificationEvidenceFindingCode: String, CaseIterable, Hashable, Sendable {
    case invalidManifest
    case invalidLedger
    case invalidTrustPolicy
    case manifestMismatch
    case buildMismatch
    case duplicateRoadmapRow
    case duplicateCitationID
    case duplicateEvidenceKind
    case duplicateAttachmentReference
    case duplicateReview
    case missingEvidence
    case unexpectedEvidence
    case unexpectedEvidenceKind
    case rowRevisionMismatch
    case testRunMismatch
    case artifactProvenanceMismatch
    case invalidAttachmentReference
    case requiredAttachmentRecordMissing
    case assertedEvidence
    case unsuccessfulEvidence
    case expiredEvidence
    case staleEvidence
    case futureDatedEvidence
    case invalidCollectorProvenance
    case untrustedCollector
    case invalidCollectorSignature
    case missingReviewer
    case invalidReviewerProvenance
    case untrustedReviewer
    case invalidReviewerSignature
    case reviewDigestMismatch
    case rejectedReview
    case selfAttestation
}

public enum VerificationEvidenceFindingSubject: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    case manifest
    case ledger
    case trustPolicy
    case row(VerificationRoadmapRowID)
    case requirement(rowID: VerificationRoadmapRowID, kind: VerificationEvidenceKind)
    case citation(VerificationEvidenceCitationID)
    case attachment(VerificationEvidenceArtifactID)
    case principal(VerificationEvidencePrincipalID)

    fileprivate var identityComponents: [String] {
        [canonicalTag] + canonicalComponents
    }

    fileprivate var canonicalTag: String {
        switch self {
        case .manifest: "manifest"
        case .ledger: "ledger"
        case .trustPolicy: "trust-policy"
        case .row: "row"
        case .requirement: "requirement"
        case .citation: "citation"
        case .attachment: "attachment"
        case .principal: "principal"
        }
    }

    fileprivate var canonicalComponents: [String] {
        switch self {
        case .manifest, .ledger, .trustPolicy: []
        case .row(let id): [id.rawValue]
        case .requirement(let rowID, let kind): [rowID.rawValue, kind.rawValue]
        case .citation(let id): [id.rawValue]
        case .attachment(let id): [id.rawValue]
        case .principal(let id): [id.rawValue]
        }
    }

    public var description: String { "VerificationEvidenceFindingSubject(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["subject": "<redacted>"], displayStyle: .enum)
    }
}

public struct VerificationEvidenceFinding: Identifiable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue.precomposedStringWithCanonicalMapping
        }

        public static func < (left: Self, right: Self) -> Bool {
            verificationEvidenceCompareUTF8(left.rawValue, right.rawValue) < 0
        }
    }

    public let id: ID
    public let severity: VerificationEvidenceFindingSeverity
    public let code: VerificationEvidenceFindingCode
    public let subject: VerificationEvidenceFindingSubject
    /// Fixed wording. Artifact metadata, signatures, digests, and submitted values remain redacted.
    public let message: String

    fileprivate init(
        id: ID,
        severity: VerificationEvidenceFindingSeverity,
        code: VerificationEvidenceFindingCode,
        subject: VerificationEvidenceFindingSubject
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.subject = subject
        message = verificationEvidenceFindingMessage(code)
    }

    public var description: String {
        "VerificationEvidenceFinding(severity: \(severity.rawValue), code: \(code.rawValue), subject: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["severity": severity, "code": code, "subject": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public enum VerificationEvidenceCompletenessStatus: String, CaseIterable, Hashable, Sendable {
    case complete
    case missing
    case duplicate
    case mismatched
    case asserted
    case unsuccessful
    case stale
    case untrusted
    case invalid
}

public struct VerificationEvidenceCompletenessCell: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let rowID: VerificationRoadmapRowID
    public let kind: VerificationEvidenceKind
    public let evidenceCount: Int
    public let citationIDs: [VerificationEvidenceCitationID]
    public let status: VerificationEvidenceCompletenessStatus

    fileprivate init(
        rowID: VerificationRoadmapRowID,
        kind: VerificationEvidenceKind,
        evidenceCount: Int,
        citationIDs: [VerificationEvidenceCitationID],
        status: VerificationEvidenceCompletenessStatus
    ) {
        self.rowID = rowID
        self.kind = kind
        self.evidenceCount = evidenceCount
        self.citationIDs = citationIDs
        self.status = status
    }

    public var description: String {
        "VerificationEvidenceCompletenessCell(kind: \(kind.rawValue), count: \(evidenceCount), status: \(status.rawValue), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["kind": kind, "evidenceCount": evidenceCount, "status": status, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public enum VerificationEvidenceRowStatus: String, CaseIterable, Hashable, Sendable {
    case notApplicable
    case incomplete
    case complete
    case invalid
}

public struct VerificationEvidenceRowCompleteness: Identifiable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let id: VerificationRoadmapRowID
    public let rowRevision: VerificationEvidenceRevision
    public let completionClaimed: Bool
    public let status: VerificationEvidenceRowStatus
    public let cells: [VerificationEvidenceCompletenessCell]

    fileprivate init(
        id: VerificationRoadmapRowID,
        rowRevision: VerificationEvidenceRevision,
        completionClaimed: Bool,
        status: VerificationEvidenceRowStatus,
        cells: [VerificationEvidenceCompletenessCell]
    ) {
        self.id = id
        self.rowRevision = rowRevision
        self.completionClaimed = completionClaimed
        self.status = status
        self.cells = cells
    }

    public var description: String {
        "VerificationEvidenceRowCompleteness(status: \(status.rawValue), cells: \(cells.count), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["status": status, "cellCount": cells.count, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public struct VerificationEvidenceAuditReport: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let scopeStatement =
        "Deterministic audit of caller-supplied, exact build/test-run/artifact references and caller-configured Ed25519 collector/reviewer trust; not independent execution, UI, AX, filesystem, roadmap, or production compliance verification."

    public let schemaVersion: Int
    public let manifest: VerificationRoadmapManifestReference
    public let ledger: VerificationEvidenceLedgerReference
    public let auditedAtUnixMilliseconds: UInt64
    public let rows: [VerificationEvidenceRowCompleteness]
    public let findings: [VerificationEvidenceFinding]

    public var highestSeverity: VerificationEvidenceFindingSeverity? { findings.first?.severity }
    public var containsErrors: Bool { findings.first?.severity == .error }
    public var validatedCompleteRowIDs: [VerificationRoadmapRowID] {
        guard !containsErrors else { return [] }
        return rows.filter { $0.status == .complete }.map(\.id)
    }
    public var isLedgerCompleteAndValid: Bool {
        !rows.isEmpty && !containsErrors
            && rows.allSatisfy { $0.status == .complete || $0.status == .notApplicable }
    }

    fileprivate init(
        schemaVersion: Int,
        manifest: VerificationRoadmapManifestReference,
        ledger: VerificationEvidenceLedgerReference,
        auditedAtUnixMilliseconds: UInt64,
        rows: [VerificationEvidenceRowCompleteness],
        findings: [VerificationEvidenceFinding]
    ) {
        self.schemaVersion = schemaVersion
        self.manifest = manifest
        self.ledger = ledger
        self.auditedAtUnixMilliseconds = auditedAtUnixMilliseconds
        self.rows = rows
        self.findings = findings
    }

    public var description: String {
        "VerificationEvidenceAuditReport(rows: \(rows.count), findings: \(findings.count), contents: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["rowCount": rows.count, "findingCount": findings.count, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public struct VerificationEvidenceCanonicalArchive: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let data: Data
    public let sha256: VerificationEvidenceDigest

    fileprivate init(data: Data, sha256: VerificationEvidenceDigest) {
        self.data = data
        self.sha256 = sha256
    }

    public var description: String {
        "VerificationEvidenceCanonicalArchive(bytes: \(data.count), contents: <redacted>)"
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

public struct VerificationEvidenceArchiveReceipt: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let schemaVersion: Int
    public let manifest: VerificationRoadmapManifestReference
    public let ledger: VerificationEvidenceLedgerReference
    public let targetBuild: VerificationEvidenceAppBuildProvenance
    public let auditAttestation: VerificationEvidenceAuditAttestation
    public let trustedVerificationTimeUnixMilliseconds: UInt64
    public let manifestSHA256: VerificationEvidenceDigest
    public let ledgerSHA256: VerificationEvidenceDigest
    public let trustPolicySHA256: VerificationEvidenceDigest
    public let reportSHA256: VerificationEvidenceDigest
    public let evaluationSHA256: VerificationEvidenceDigest
    public let archiveSHA256: VerificationEvidenceDigest
    public let completedRowCount: Int
    public let requiredEvidenceCount: Int
    public let completeEvidenceCount: Int
    public let findingCount: Int
    public let archiveByteCount: Int

    fileprivate init(
        schemaVersion: Int,
        manifest: VerificationRoadmapManifestReference,
        ledger: VerificationEvidenceLedgerReference,
        targetBuild: VerificationEvidenceAppBuildProvenance,
        auditAttestation: VerificationEvidenceAuditAttestation,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        manifestSHA256: VerificationEvidenceDigest,
        ledgerSHA256: VerificationEvidenceDigest,
        trustPolicySHA256: VerificationEvidenceDigest,
        reportSHA256: VerificationEvidenceDigest,
        evaluationSHA256: VerificationEvidenceDigest,
        archiveSHA256: VerificationEvidenceDigest,
        completedRowCount: Int,
        requiredEvidenceCount: Int,
        completeEvidenceCount: Int,
        findingCount: Int,
        archiveByteCount: Int
    ) {
        self.schemaVersion = schemaVersion
        self.manifest = manifest
        self.ledger = ledger
        self.targetBuild = targetBuild
        self.auditAttestation = auditAttestation
        self.trustedVerificationTimeUnixMilliseconds = trustedVerificationTimeUnixMilliseconds
        self.manifestSHA256 = manifestSHA256
        self.ledgerSHA256 = ledgerSHA256
        self.trustPolicySHA256 = trustPolicySHA256
        self.reportSHA256 = reportSHA256
        self.evaluationSHA256 = evaluationSHA256
        self.archiveSHA256 = archiveSHA256
        self.completedRowCount = completedRowCount
        self.requiredEvidenceCount = requiredEvidenceCount
        self.completeEvidenceCount = completeEvidenceCount
        self.findingCount = findingCount
        self.archiveByteCount = archiveByteCount
    }

    public var description: String {
        "VerificationEvidenceArchiveReceipt(completedRows: \(completedRowCount), completeEvidence: \(completeEvidenceCount)/\(requiredEvidenceCount), findings: \(findingCount), contents: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "completedRowCount": completedRowCount,
                "requiredEvidenceCount": requiredEvidenceCount,
                "completeEvidenceCount": completeEvidenceCount,
                "findingCount": findingCount,
                "archiveByteCount": archiveByteCount,
                "digests": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public func validateCurrent(
        manifest currentManifest: VerificationRoadmapManifest,
        ledger currentLedger: VerificationEvidenceLedger,
        trustPolicy: VerificationEvidenceTrustPolicy,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        limits: VerificationEvidenceLedgerLimits = .default,
        cancellationCheck: @escaping VerificationEvidenceAuditor.CancellationCheck = {
            Task.isCancelled
        }
    ) throws {
        guard trustedVerificationTimeUnixMilliseconds >= self.trustedVerificationTimeUnixMilliseconds else {
            throw VerificationEvidenceLedgerError.receiptMismatch
        }
        try VerificationEvidencePreflight.validate(limits)
        let budget = try VerificationEvidenceWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try VerificationEvidencePreflight.inspect(
            manifest: currentManifest,
            ledger: currentLedger,
            trustPolicy: trustPolicy,
            limits: limits,
            budget: budget
        )
        let canonicalInputs = try verificationEvidenceMeasureCanonicalInputs(
            manifest: currentManifest,
            ledger: currentLedger,
            trustPolicy: trustPolicy,
            limits: limits,
            budget: budget
        )
        guard canonicalInputs.manifestDigest == manifestSHA256,
            canonicalInputs.ledgerDigest == ledgerSHA256,
            canonicalInputs.trustPolicyDigest == trustPolicySHA256
        else {
            throw VerificationEvidenceLedgerError.receiptMismatch
        }
        var originalArchiveByteCount = 0
        do {
            let originalResult = try VerificationEvidenceAuditor.auditUsingBudget(
                manifest: currentManifest,
                ledger: currentLedger,
                trustPolicy: trustPolicy,
                auditAttestation: auditAttestation,
                trustedVerificationTimeUnixMilliseconds: self.trustedVerificationTimeUnixMilliseconds,
                limits: limits,
                budget: budget,
                preflightedCanonicalInputs: canonicalInputs
            )
            guard originalResult.receipt == self else {
                throw VerificationEvidenceLedgerError.receiptMismatch
            }
            originalArchiveByteCount = originalResult.archive.data.count
        }
        budget.releaseMemory(originalArchiveByteCount)
        guard trustedVerificationTimeUnixMilliseconds != self.trustedVerificationTimeUnixMilliseconds else {
            try budget.finish()
            return
        }
        let currentEvaluationSHA256 = try VerificationEvidenceAuditor.currentEvaluationSHA256UsingBudget(
            manifest: currentManifest,
            ledger: currentLedger,
            trustPolicy: trustPolicy,
            auditAttestation: auditAttestation,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            limits: limits,
            budget: budget
        )
        guard currentEvaluationSHA256 == evaluationSHA256 else {
            throw VerificationEvidenceLedgerError.receiptMismatch
        }
        try budget.finish()
    }
}

public struct VerificationEvidenceAuditResult: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let report: VerificationEvidenceAuditReport
    public let archive: VerificationEvidenceCanonicalArchive
    public let receipt: VerificationEvidenceArchiveReceipt

    fileprivate init(
        report: VerificationEvidenceAuditReport,
        archive: VerificationEvidenceCanonicalArchive,
        receipt: VerificationEvidenceArchiveReceipt
    ) {
        self.report = report
        self.archive = archive
        self.receipt = receipt
    }

    public var description: String { "VerificationEvidenceAuditResult(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["result": "<redacted>"], displayStyle: .struct)
    }
}

/// Pure ledger audit. Trusted collectors, independent reviewers, and auditor authorization sign
/// canonical, domain-separated data. Callers must supply verification time from a trusted clock and
/// source trust roots outside submitted data.
public enum VerificationEvidenceAuditor: Sendable {
    public typealias CancellationCheck = @Sendable () -> Bool

    public static let schemaVersion = 2
    public static let collectorClaimDomain = "org.macmerge.verification-evidence-ledger.collector-claim.v2"
    public static let collectorSignatureDomain = "org.macmerge.verification-evidence-ledger.collector-signature.v2"
    public static let reviewerClaimDomain = "org.macmerge.verification-evidence-ledger.reviewer-claim.v2"
    public static let auditClaimDomain = "org.macmerge.verification-evidence-ledger.audit-claim.v2"
    public static let manifestDomain = "org.macmerge.verification-evidence-ledger.manifest.v2"
    public static let ledgerDomain = "org.macmerge.verification-evidence-ledger.ledger.v2"
    public static let trustPolicyDomain = "org.macmerge.verification-evidence-ledger.trust-policy.v2"
    public static let reportDomain = "org.macmerge.verification-evidence-ledger.report.v2"
    public static let reportEvaluationDomain =
        "org.macmerge.verification-evidence-ledger.report-evaluation.v2"
    public static let archiveDomain = "org.macmerge.verification-evidence-ledger.archive.v2"

    public static func collectorSigningData(
        for citation: VerificationEvidenceCitation,
        limits: VerificationEvidenceLedgerLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try VerificationEvidencePreflight.validate(limits)
        let budget = try VerificationEvidenceWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try VerificationEvidencePreflight.inspect(citation, limits: limits, budget: budget)
        var data = try VerificationEvidenceCanonicalEncoder.collectorClaim(
            citation,
            limits: limits,
            budget: budget
        )
        guard data.count <= limits.maximumSigningPayloadBytes else {
            throw VerificationEvidenceLedgerError.signingPayloadTooLarge(
                maximumBytes: limits.maximumSigningPayloadBytes
            )
        }
        let digest = try verificationEvidenceSHA256(data, budget: budget)
        let dataByteCount = data.count
        data = Data()
        budget.releaseMemory(dataByteCount)
        let signingData = try VerificationEvidenceCanonicalEncoder.collectorSignature(
            claimSHA256: digest,
            limits: limits,
            budget: budget
        )
        try verificationEvidenceValidateSigningPayloadSize(signingData, limits: limits)
        try budget.finish()
        return signingData
    }

    public static func evidenceClaimSHA256(
        for citation: VerificationEvidenceCitation,
        limits: VerificationEvidenceLedgerLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> VerificationEvidenceDigest {
        try VerificationEvidencePreflight.validate(limits)
        let budget = try VerificationEvidenceWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try VerificationEvidencePreflight.inspect(citation, limits: limits, budget: budget)
        let data = try VerificationEvidenceCanonicalEncoder.collectorClaim(
            citation,
            limits: limits,
            budget: budget
        )
        guard data.count <= limits.maximumSigningPayloadBytes else {
            throw VerificationEvidenceLedgerError.signingPayloadTooLarge(
                maximumBytes: limits.maximumSigningPayloadBytes
            )
        }
        let digest = try verificationEvidenceSHA256(data, budget: budget)
        try budget.finish()
        return digest
    }

    public static func reviewerSigningData(
        for citation: VerificationEvidenceCitation,
        review: VerificationEvidenceReviewAttestation,
        limits: VerificationEvidenceLedgerLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try VerificationEvidencePreflight.validate(limits)
        let budget = try VerificationEvidenceWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try VerificationEvidencePreflight.inspect(citation, limits: limits, budget: budget)
        try VerificationEvidencePreflight.inspect(review, limits: limits, budget: budget)
        let data = try VerificationEvidenceCanonicalEncoder.reviewerClaim(
            citationID: citation.id,
            review: review,
            limits: limits,
            budget: budget
        )
        try verificationEvidenceValidateSigningPayloadSize(data, limits: limits)
        try budget.finish()
        return data
    }

    public static func auditSigningData(
        manifest: VerificationRoadmapManifest,
        ledger: VerificationEvidenceLedger,
        trustPolicy: VerificationEvidenceTrustPolicy,
        auditorID: VerificationEvidencePrincipalID,
        submitterID: VerificationEvidencePrincipalID,
        auditedAtUnixMilliseconds: UInt64,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        limits: VerificationEvidenceLedgerLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Data {
        try auditSigningEnvelope(
            manifest: manifest,
            ledger: ledger,
            trustPolicy: trustPolicy,
            auditorID: auditorID,
            submitterID: submitterID,
            auditedAtUnixMilliseconds: auditedAtUnixMilliseconds,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            limits: limits,
            cancellationCheck: cancellationCheck
        ).signingData
    }

    public static func auditSigningEnvelope(
        manifest: VerificationRoadmapManifest,
        ledger: VerificationEvidenceLedger,
        trustPolicy: VerificationEvidenceTrustPolicy,
        auditorID: VerificationEvidencePrincipalID,
        submitterID: VerificationEvidencePrincipalID,
        auditedAtUnixMilliseconds: UInt64,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        limits: VerificationEvidenceLedgerLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> VerificationEvidenceAuditSigningEnvelope {
        try VerificationEvidencePreflight.validate(limits)
        let budget = try VerificationEvidenceWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        try VerificationEvidencePreflight.inspect(
            manifest: manifest,
            ledger: ledger,
            trustPolicy: trustPolicy,
            limits: limits,
            budget: budget
        )
        let trustRootIndex = try VerificationEvidenceTrustRootIndex(
            roots: trustPolicy.roots,
            budget: budget
        )
        try VerificationEvidencePreflight.inspectAuditParties(
            auditorID: auditorID,
            submitterID: submitterID,
            budget: budget
        )
        try verificationEvidenceValidateAuditParties(
            auditorID: auditorID,
            submitterID: submitterID,
            auditedAtUnixMilliseconds: auditedAtUnixMilliseconds,
            ledger: ledger,
            trustRootIndex: trustRootIndex,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            budget: budget
        )
        var prepared = try verificationEvidencePrepareAudit(
            manifest: manifest,
            ledger: ledger,
            trustPolicy: trustPolicy,
            trustRootIndex: trustRootIndex,
            submitterID: submitterID,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            limits: limits,
            budget: budget
        )
        let archiveByteCount = prepared.archiveData.count
        prepared.archiveData = Data()
        budget.releaseMemory(archiveByteCount)
        let attestation = VerificationEvidenceAuditAttestation(
            auditorID: auditorID,
            submitterID: submitterID,
            auditedAtUnixMilliseconds: auditedAtUnixMilliseconds,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            manifestSHA256: prepared.manifestDigest,
            ledgerSHA256: prepared.ledgerDigest,
            trustPolicySHA256: prepared.trustPolicyDigest,
            reportSHA256: prepared.reportDigest,
            archiveSHA256: prepared.archiveDigest,
            signature: []
        )
        try VerificationEvidencePreflight.inspect(attestation, limits: limits, budget: budget)
        let data = try VerificationEvidenceCanonicalEncoder.auditClaim(
            attestation,
            limits: limits,
            budget: budget
        )
        try verificationEvidenceValidateSigningPayloadSize(data, limits: limits)
        try budget.finish()
        return VerificationEvidenceAuditSigningEnvelope(
            attestation: attestation,
            signingData: data
        )
    }

    public static func audit(
        manifest: VerificationRoadmapManifest,
        ledger: VerificationEvidenceLedger,
        trustPolicy: VerificationEvidenceTrustPolicy,
        auditAttestation: VerificationEvidenceAuditAttestation,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        limits: VerificationEvidenceLedgerLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> VerificationEvidenceAuditResult {
        try VerificationEvidencePreflight.validate(limits)
        let budget = try VerificationEvidenceWorkBudget(
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        let result = try auditUsingBudget(
            manifest: manifest,
            ledger: ledger,
            trustPolicy: trustPolicy,
            auditAttestation: auditAttestation,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            limits: limits,
            budget: budget
        )
        try budget.finish()
        return result
    }

    fileprivate static func auditUsingBudget(
        manifest: VerificationRoadmapManifest,
        ledger: VerificationEvidenceLedger,
        trustPolicy: VerificationEvidenceTrustPolicy,
        auditAttestation: VerificationEvidenceAuditAttestation,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget,
        preflightedCanonicalInputs: VerificationEvidenceCanonicalInputs? = nil
    ) throws -> VerificationEvidenceAuditResult {
        if preflightedCanonicalInputs == nil {
            try VerificationEvidencePreflight.inspect(
                manifest: manifest,
                ledger: ledger,
                trustPolicy: trustPolicy,
                limits: limits,
                budget: budget
            )
        }
        try VerificationEvidencePreflight.inspect(auditAttestation, limits: limits, budget: budget)
        let trustRootIndex = try VerificationEvidenceTrustRootIndex(
            roots: trustPolicy.roots,
            budget: budget
        )
        let prepared = try verificationEvidencePrepareAudit(
            manifest: manifest,
            ledger: ledger,
            trustPolicy: trustPolicy,
            trustRootIndex: trustRootIndex,
            submitterID: auditAttestation.submitterID,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            limits: limits,
            budget: budget,
            canonicalInputs: preflightedCanonicalInputs
        )
        try verificationEvidenceValidateAuditAttestation(
            auditAttestation,
            prepared: prepared,
            ledger: ledger,
            trustRootIndex: trustRootIndex,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            limits: limits,
            budget: budget
        )
        var requiredEvidenceCount = 0
        var completeEvidenceCount = 0
        var completedRowCount = 0
        for row in manifest.rows {
            try budget.consume()
            requiredEvidenceCount = try verificationEvidenceCheckedAdd(
                requiredEvidenceCount,
                row.requiredEvidenceKinds.count
            )
        }
        let reportContainsErrors = prepared.report.containsErrors
        for row in prepared.report.rows {
            try budget.consume()
            completeEvidenceCount = try verificationEvidenceCheckedAdd(
                completeEvidenceCount,
                row.cells.count(where: { $0.status == .complete })
            )
            if !reportContainsErrors, row.status == .complete {
                completedRowCount = try verificationEvidenceCheckedAdd(completedRowCount, 1)
            }
        }
        let receipt = VerificationEvidenceArchiveReceipt(
            schemaVersion: schemaVersion,
            manifest: manifest.reference,
            ledger: ledger.reference,
            targetBuild: ledger.targetBuild,
            auditAttestation: auditAttestation,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            manifestSHA256: prepared.manifestDigest,
            ledgerSHA256: prepared.ledgerDigest,
            trustPolicySHA256: prepared.trustPolicyDigest,
            reportSHA256: prepared.reportDigest,
            evaluationSHA256: prepared.evaluationDigest,
            archiveSHA256: prepared.archiveDigest,
            completedRowCount: completedRowCount,
            requiredEvidenceCount: requiredEvidenceCount,
            completeEvidenceCount: completeEvidenceCount,
            findingCount: prepared.report.findings.count,
            archiveByteCount: prepared.archiveData.count
        )
        return VerificationEvidenceAuditResult(
            report: prepared.report,
            archive: VerificationEvidenceCanonicalArchive(
                data: prepared.archiveData,
                sha256: prepared.archiveDigest
            ),
            receipt: receipt
        )
    }

    fileprivate static func currentEvaluationSHA256UsingBudget(
        manifest: VerificationRoadmapManifest,
        ledger: VerificationEvidenceLedger,
        trustPolicy: VerificationEvidenceTrustPolicy,
        auditAttestation: VerificationEvidenceAuditAttestation,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws -> VerificationEvidenceDigest {
        let trustRootIndex = try VerificationEvidenceTrustRootIndex(
            roots: trustPolicy.roots,
            budget: budget
        )
        try verificationEvidenceValidateCurrentAuditAuthority(
            auditAttestation,
            ledger: ledger,
            trustRootIndex: trustRootIndex,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            limits: limits,
            budget: budget
        )
        var prepared = try verificationEvidencePrepareAudit(
            manifest: manifest,
            ledger: ledger,
            trustPolicy: trustPolicy,
            trustRootIndex: trustRootIndex,
            submitterID: auditAttestation.submitterID,
            trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            limits: limits,
            budget: budget
        )
        let archiveByteCount = prepared.archiveData.count
        prepared.archiveData = Data()
        budget.releaseMemory(archiveByteCount)
        return prepared.evaluationDigest
    }
}

private struct VerificationEvidenceRequirementKey: Hashable {
    let rowID: VerificationRoadmapRowID
    let kind: VerificationEvidenceKind
}

private struct VerificationEvidenceIndexedTrustRoot {
    let root: VerificationEvidenceTrustRoot
    let isStructurallyValid: Bool
}

private struct VerificationEvidenceTrustRootIndex {
    let rootsByPrincipal: [VerificationEvidencePrincipalID: [VerificationEvidenceIndexedTrustRoot]]
    let invalidPrincipalIDs: Set<VerificationEvidencePrincipalID>
    let ambiguousPrincipalIDs: Set<VerificationEvidencePrincipalID>

    init(
        roots: [VerificationEvidenceTrustRoot],
        budget: VerificationEvidenceWorkBudget
    ) throws {
        var rootsByPrincipal: [VerificationEvidencePrincipalID: [VerificationEvidenceIndexedTrustRoot]] = [:]
        var invalidPrincipalIDs = Set<VerificationEvidencePrincipalID>()
        var ambiguousPrincipalIDs = Set<VerificationEvidencePrincipalID>()
        for root in roots {
            try budget.consume(
                UInt64(
                    root.principalID.rawValue.utf8.count + root.ed25519PublicKey.count
                        + root.roles.count + 1
                )
            )
            let isStructurallyValid = verificationEvidenceTrustRootIsStructurallyValid(root)
            rootsByPrincipal[root.principalID, default: []].append(
                VerificationEvidenceIndexedTrustRoot(
                    root: root,
                    isStructurallyValid: isStructurallyValid
                )
            )
            if !isStructurallyValid {
                invalidPrincipalIDs.insert(root.principalID)
            }
        }
        for (principalID, indexedRoots) in rootsByPrincipal {
            for role in VerificationEvidenceTrustRole.allCases {
                let roots = try verificationEvidenceStableSorted(
                    indexedRoots.filter {
                        $0.isStructurallyValid && $0.root.roles.contains(role)
                    },
                    budget: budget
                ) { left, right in
                    try budget.consume()
                    if left.root.validFromUnixMilliseconds != right.root.validFromUnixMilliseconds {
                        return left.root.validFromUnixMilliseconds
                            < right.root.validFromUnixMilliseconds
                    }
                    return left.root.validThroughUnixMilliseconds
                        < right.root.validThroughUnixMilliseconds
                }
                var latestValidThrough: UInt64?
                for indexedRoot in roots {
                    try budget.consume()
                    if let latestValidThrough,
                        indexedRoot.root.validFromUnixMilliseconds <= latestValidThrough
                    {
                        ambiguousPrincipalIDs.insert(principalID)
                    }
                    latestValidThrough = max(
                        latestValidThrough ?? 0,
                        indexedRoot.root.validThroughUnixMilliseconds
                    )
                }
            }
        }
        self.rootsByPrincipal = rootsByPrincipal
        self.invalidPrincipalIDs = invalidPrincipalIDs
        self.ambiguousPrincipalIDs = ambiguousPrincipalIDs
    }

    func matchingRoots(
        principalID: VerificationEvidencePrincipalID,
        role: VerificationEvidenceTrustRole,
        signedAt timestamp: UInt64,
        verifiedAt trustedVerificationTimeUnixMilliseconds: UInt64,
        budget: VerificationEvidenceWorkBudget
    ) throws -> [VerificationEvidenceTrustRoot] {
        var roots: [VerificationEvidenceTrustRoot] = []
        try budget.consume(UInt64(principalID.rawValue.utf8.count))
        for indexedRoot in rootsByPrincipal[principalID, default: []] {
            try budget.consume()
            let root = indexedRoot.root
            if indexedRoot.isStructurallyValid,
                root.roles.contains(role),
                root.validFromUnixMilliseconds <= timestamp,
                timestamp <= root.validThroughUnixMilliseconds,
                root.validFromUnixMilliseconds <= trustedVerificationTimeUnixMilliseconds,
                trustedVerificationTimeUnixMilliseconds <= root.validThroughUnixMilliseconds,
                root.revokedAtUnixMilliseconds.map({
                    trustedVerificationTimeUnixMilliseconds < $0
                }) ?? true
            {
                roots.append(root)
            }
        }
        return roots
    }

    func evidenceKeys(
        for principals: Set<VerificationEvidencePrincipalID>,
        budget: VerificationEvidenceWorkBudget
    ) throws -> Set<[UInt8]> {
        var keys = Set<[UInt8]>()
        for principal in principals {
            try budget.consume(UInt64(principal.rawValue.utf8.count))
            for indexedRoot in rootsByPrincipal[principal, default: []] {
                try budget.consume()
                if !indexedRoot.root.roles.isDisjoint(with: [.collector, .reviewer]) {
                    keys.insert(indexedRoot.root.ed25519PublicKey)
                }
            }
        }
        return keys
    }
}

private struct VerificationEvidencePreparedAudit {
    let manifestDigest: VerificationEvidenceDigest
    let ledgerDigest: VerificationEvidenceDigest
    let trustPolicyDigest: VerificationEvidenceDigest
    let report: VerificationEvidenceAuditReport
    let reportDigest: VerificationEvidenceDigest
    let evaluationDigest: VerificationEvidenceDigest
    var archiveData: Data
    let archiveDigest: VerificationEvidenceDigest
}

private struct VerificationEvidenceCanonicalInputs {
    let manifestByteCount: Int
    let manifestDigest: VerificationEvidenceDigest
    let ledgerByteCount: Int
    let ledgerDigest: VerificationEvidenceDigest
    let trustPolicyByteCount: Int
    let trustPolicyDigest: VerificationEvidenceDigest
}

private struct VerificationEvidenceAuditContext {
    let manifest: VerificationRoadmapManifest
    let ledger: VerificationEvidenceLedger
    let trustPolicy: VerificationEvidenceTrustPolicy
    let submitterID: VerificationEvidencePrincipalID
    let trustedVerificationTimeUnixMilliseconds: UInt64
    let limits: VerificationEvidenceLedgerLimits
    let budget: VerificationEvidenceWorkBudget
    let trustRootIndex: VerificationEvidenceTrustRootIndex
    private var findings: [VerificationEvidenceFinding] = []
    private var findingIDs: Set<VerificationEvidenceFinding.ID> = []
    private var trustedSubmitterKeys: Set<[UInt8]> = []

    init(
        manifest: VerificationRoadmapManifest,
        ledger: VerificationEvidenceLedger,
        trustPolicy: VerificationEvidenceTrustPolicy,
        trustRootIndex: VerificationEvidenceTrustRootIndex,
        submitterID: VerificationEvidencePrincipalID,
        trustedVerificationTimeUnixMilliseconds: UInt64,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) {
        self.manifest = manifest
        self.ledger = ledger
        self.trustPolicy = trustPolicy
        self.trustRootIndex = trustRootIndex
        self.submitterID = submitterID
        self.trustedVerificationTimeUnixMilliseconds = trustedVerificationTimeUnixMilliseconds
        self.limits = limits
        self.budget = budget
    }

    mutating func run() throws -> VerificationEvidenceAuditReport {
        try inspectTopLevel()
        try inspectGlobalProvenance()
        let sortedRows = try VerificationEvidenceCanonicalEncoder.sortedRows(
            manifest.rows,
            limits: limits,
            budget: budget
        )
        var rowsByID: [VerificationRoadmapRowID: [VerificationRoadmapRowRequirement]] = [:]
        var invalidRowIDs = Set<VerificationRoadmapRowID>()
        for row in sortedRows {
            try budget.consume()
            rowsByID[row.id, default: []].append(row)
            if !verificationEvidenceIsValidIdentifier(row.id.rawValue) {
                invalidRowIDs.insert(row.id)
                try add(.error, .invalidManifest, subject: .row(row.id))
            }
            if case .notApplicable = row.applicability, row.completionClaimed {
                invalidRowIDs.insert(row.id)
                try add(.error, .invalidManifest, subject: .row(row.id), discriminator: "na-complete")
            }
        }
        for (id, rows) in rowsByID where rows.count > 1 {
            invalidRowIDs.insert(id)
            try add(
                .error,
                .duplicateRoadmapRow,
                subject: .row(id),
                discriminator: String(rows.count)
            )
        }

        let sortedCitations = try VerificationEvidenceCanonicalEncoder.sortedCitations(
            ledger.citations,
            limits: limits,
            budget: budget
        )
        var citationsByID: [VerificationEvidenceCitationID: [VerificationEvidenceCitation]] = [:]
        var citationsByRequirement: [VerificationEvidenceRequirementKey: [VerificationEvidenceCitation]] = [:]
        for citation in sortedCitations {
            try budget.consume()
            citationsByID[citation.id, default: []].append(citation)
            guard let row = rowsByID[citation.row.id]?.first else {
                try add(.error, .unexpectedEvidence, subject: .citation(citation.id))
                continue
            }
            if !row.completionClaimed || row.requiredEvidenceKinds.isEmpty {
                invalidRowIDs.insert(row.id)
                try add(.error, .unexpectedEvidence, subject: .citation(citation.id))
                continue
            }
            guard row.requiredEvidenceKinds.contains(citation.kind) else {
                invalidRowIDs.insert(row.id)
                try add(.error, .unexpectedEvidenceKind, subject: .citation(citation.id))
                continue
            }
            citationsByRequirement[
                VerificationEvidenceRequirementKey(rowID: row.id, kind: citation.kind),
                default: []
            ].append(citation)
        }
        for (_, citations) in citationsByID where citations.count > 1 {
            for citation in citations {
                invalidRowIDs.insert(citation.row.id)
            }
            if let id = citations.first?.id {
                try add(
                    .error,
                    .duplicateCitationID,
                    subject: .citation(id),
                    discriminator: String(citations.count)
                )
            }
        }

        var resultRows: [VerificationEvidenceRowCompleteness] = []
        resultRows.reserveCapacity(rowsByID.count)
        var emittedRowIDs = Set<VerificationRoadmapRowID>()
        for row in sortedRows where emittedRowIDs.insert(row.id).inserted {
            try budget.consume()
            let duplicateRow = rowsByID[row.id, default: []].count > 1
            switch row.applicability {
            case .notApplicable:
                resultRows.append(
                    VerificationEvidenceRowCompleteness(
                        id: row.id,
                        rowRevision: row.reference.revision,
                        completionClaimed: row.completionClaimed,
                        status: duplicateRow || invalidRowIDs.contains(row.id) ? .invalid : .notApplicable,
                        cells: []
                    )
                )
            case .applicable:
                guard row.completionClaimed else {
                    resultRows.append(
                        VerificationEvidenceRowCompleteness(
                            id: row.id,
                            rowRevision: row.reference.revision,
                            completionClaimed: false,
                            status: duplicateRow || invalidRowIDs.contains(row.id) ? .invalid : .incomplete,
                            cells: []
                        )
                    )
                    continue
                }
                var cells: [VerificationEvidenceCompletenessCell] = []
                var rowInvalid = duplicateRow || invalidRowIDs.contains(row.id)
                for kind in VerificationEvidenceKind.allCases where row.requiredEvidenceKinds.contains(kind) {
                    try budget.consume()
                    let key = VerificationEvidenceRequirementKey(rowID: row.id, kind: kind)
                    let citations = citationsByRequirement[key] ?? []
                    let status: VerificationEvidenceCompletenessStatus
                    if citations.isEmpty {
                        status = .missing
                        rowInvalid = true
                        try add(
                            .error,
                            .missingEvidence,
                            subject: .requirement(rowID: row.id, kind: kind)
                        )
                    } else if citations.count > 1 {
                        status = .duplicate
                        rowInvalid = true
                        try add(
                            .error,
                            .duplicateEvidenceKind,
                            subject: .requirement(rowID: row.id, kind: kind),
                            discriminator: String(citations.count)
                        )
                        for citation in citations {
                            _ = try assess(citation, for: row)
                        }
                    } else {
                        status = try assess(citations[0], for: row)
                        if status != .complete { rowInvalid = true }
                    }
                    let citationIDs = try verificationEvidenceStableSorted(
                        citations.map(\.id),
                        budget: budget
                    ) { left, right in
                        try budget.consume(
                            UInt64(left.rawValue.utf8.count + right.rawValue.utf8.count)
                        )
                        return left < right
                    }
                    cells.append(
                        VerificationEvidenceCompletenessCell(
                            rowID: row.id,
                            kind: kind,
                            evidenceCount: citations.count,
                            citationIDs: citationIDs,
                            status: status
                        )
                    )
                }
                resultRows.append(
                    VerificationEvidenceRowCompleteness(
                        id: row.id,
                        rowRevision: row.reference.revision,
                        completionClaimed: true,
                        status: rowInvalid ? .invalid : .complete,
                        cells: cells
                    )
                )
            }
        }

        let sortedFindings = try verificationEvidenceSortedFindings(findings, budget: budget)
        return VerificationEvidenceAuditReport(
            schemaVersion: VerificationEvidenceAuditor.schemaVersion,
            manifest: manifest.reference,
            ledger: ledger.reference,
            auditedAtUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
            rows: resultRows,
            findings: sortedFindings
        )
    }

    private mutating func inspectTopLevel() throws {
        if !verificationEvidenceIsValidIdentifier(manifest.reference.id.rawValue) {
            try add(.error, .invalidManifest, subject: .manifest)
        }
        if !verificationEvidenceIsValidIdentifier(ledger.reference.id.rawValue) {
            try add(.error, .invalidLedger, subject: .ledger)
        }
        if ledger.manifest != manifest.reference {
            try add(.error, .manifestMismatch, subject: .ledger)
        }
        if !verificationEvidenceBuildIsStructurallyValid(ledger.targetBuild) {
            try add(.error, .artifactProvenanceMismatch, subject: .ledger)
        }
        for principal in trustRootIndex.invalidPrincipalIDs {
            try add(.error, .invalidTrustPolicy, subject: .principal(principal))
        }
        for principal in trustRootIndex.ambiguousPrincipalIDs {
            try add(
                .error,
                .invalidTrustPolicy,
                subject: .principal(principal),
                discriminator: "overlapping-authority"
            )
        }
        let submitterRoots = try matchingRoots(
            principalID: submitterID,
            role: .submitter,
            at: trustedVerificationTimeUnixMilliseconds
        )
        if submitterRoots.count != 1 {
            try add(
                .error,
                .invalidTrustPolicy,
                subject: .principal(submitterID),
                discriminator: "submitter"
            )
        } else {
            trustedSubmitterKeys.insert(submitterRoots[0].ed25519PublicKey)
        }
        for kind in VerificationEvidenceKind.allCases
        where trustPolicy.freshness.maximumAgeMilliseconds(for: kind) == 0 {
            try add(
                .error,
                .invalidTrustPolicy,
                subject: .trustPolicy,
                discriminator: kind.rawValue
            )
        }
        if trustPolicy.freshness.maximumCollectionLagMilliseconds == 0 {
            try add(
                .error,
                .invalidTrustPolicy,
                subject: .trustPolicy,
                discriminator: "collection-lag"
            )
        }
    }

    private mutating func inspectGlobalProvenance() throws {
        var artifactsByID: [VerificationEvidenceArtifactID: VerificationEvidenceArtifactReference] = [:]
        try register(ledger.targetBuild.applicationBundle, artifactsByID: &artifactsByID)
        try register(ledger.targetBuild.executable, artifactsByID: &artifactsByID)
        try register(ledger.targetBuild.signingIdentity, artifactsByID: &artifactsByID)
        var runsByReference: [VerificationEvidenceTestRunReference: VerificationEvidenceTestRunProvenance] = [:]
        let citations = try VerificationEvidenceCanonicalEncoder.sortedCitations(
            ledger.citations,
            limits: limits,
            budget: budget
        )
        for citation in citations {
            try budget.consume()
            if let existing = runsByReference[citation.testRun.reference], existing != citation.testRun {
                try add(
                    .error,
                    .testRunMismatch,
                    subject: .citation(citation.id),
                    discriminator: "reference-alias"
                )
            } else {
                runsByReference[citation.testRun.reference] = citation.testRun
            }
            try register(citation.testRun.build.applicationBundle, artifactsByID: &artifactsByID)
            try register(citation.testRun.build.executable, artifactsByID: &artifactsByID)
            try register(citation.testRun.build.signingIdentity, artifactsByID: &artifactsByID)
            try register(citation.testRun.testRunner, artifactsByID: &artifactsByID)
            try register(citation.testRun.testBundle, artifactsByID: &artifactsByID)
            try register(citation.testRun.configuration, artifactsByID: &artifactsByID)
            for attachment in citation.attachments {
                try budget.consume()
                try register(attachment.artifact, artifactsByID: &artifactsByID)
            }
        }
    }

    private mutating func register(
        _ artifact: VerificationEvidenceArtifactReference,
        artifactsByID: inout [VerificationEvidenceArtifactID: VerificationEvidenceArtifactReference]
    ) throws {
        try budget.consume()
        if let existing = artifactsByID[artifact.id], existing != artifact {
            try add(
                .error,
                .artifactProvenanceMismatch,
                subject: .attachment(artifact.id),
                discriminator: "identity-alias"
            )
        } else {
            artifactsByID[artifact.id] = artifact
        }
    }

    private mutating func assess(
        _ citation: VerificationEvidenceCitation,
        for row: VerificationRoadmapRowRequirement
    ) throws -> VerificationEvidenceCompletenessStatus {
        var status = VerificationEvidenceCompletenessStatus.complete
        var hasMismatch = false
        var hasInvalid = false
        var hasUntrusted = false
        var hasStale = false

        if !verificationEvidenceIsValidIdentifier(citation.id.rawValue) {
            hasInvalid = true
            try add(.error, .invalidLedger, subject: .citation(citation.id))
        }
        if citation.row != row.reference {
            hasMismatch = true
            try add(.error, .rowRevisionMismatch, subject: .citation(citation.id))
        }
        if citation.testRun.build != ledger.targetBuild {
            hasMismatch = true
            try add(.error, .buildMismatch, subject: .citation(citation.id))
        }
        if !verificationEvidenceIsValidIdentifier(citation.testRun.reference.id.rawValue)
            || !verificationEvidenceBuildIsStructurallyValid(citation.testRun.build)
            || citation.testRun.testRunner.role != .testRunner
            || citation.testRun.testBundle.role != .testBundle
            || citation.testRun.configuration.role != .testConfiguration
            || !verificationEvidenceArtifactIsStructurallyValid(citation.testRun.testRunner)
            || !verificationEvidenceArtifactIsStructurallyValid(citation.testRun.testBundle)
            || !verificationEvidenceArtifactIsStructurallyValid(citation.testRun.configuration)
        {
            hasInvalid = true
            try add(.error, .artifactProvenanceMismatch, subject: .citation(citation.id))
        }
        if citation.testRun.outcome != .passed
            || citation.testRun.startedAtUnixMilliseconds > citation.testRun.finishedAtUnixMilliseconds
            || citation.testRun.finishedAtUnixMilliseconds > citation.collectedAtUnixMilliseconds
        {
            hasMismatch = true
            try add(.error, .testRunMismatch, subject: .citation(citation.id))
        }
        if citation.testRun.finishedAtUnixMilliseconds <= citation.collectedAtUnixMilliseconds,
            citation.collectedAtUnixMilliseconds - citation.testRun.finishedAtUnixMilliseconds
                > trustPolicy.freshness.maximumCollectionLagMilliseconds
        {
            hasMismatch = true
            try add(.error, .testRunMismatch, subject: .citation(citation.id), discriminator: "collection-lag")
        }
        if citation.basis == .asserted {
            status = .asserted
            try add(.error, .assertedEvidence, subject: .citation(citation.id))
        }
        if citation.outcome != .passed {
            status = .unsuccessful
            try add(.error, .unsuccessfulEvidence, subject: .citation(citation.id))
        }
        if citation.testRun.finishedAtUnixMilliseconds > trustedVerificationTimeUnixMilliseconds
            || citation.collectedAtUnixMilliseconds > trustedVerificationTimeUnixMilliseconds
            || citation.collectorAttestation.attestedAtUnixMilliseconds
                > trustedVerificationTimeUnixMilliseconds
        {
            hasStale = true
            try add(.error, .futureDatedEvidence, subject: .citation(citation.id))
        } else if trustedVerificationTimeUnixMilliseconds
            - citation.testRun.finishedAtUnixMilliseconds
            > trustPolicy.freshness.maximumAgeMilliseconds(for: citation.kind)
        {
            hasStale = true
            try add(.error, .staleEvidence, subject: .citation(citation.id))
        }
        if let expiry = citation.expiresAtUnixMilliseconds,
            expiry <= citation.collectedAtUnixMilliseconds
                || trustedVerificationTimeUnixMilliseconds >= expiry
        {
            hasStale = true
            try add(.error, .expiredEvidence, subject: .citation(citation.id))
        }

        if citation.attachments.isEmpty {
            hasInvalid = true
            try add(.error, .requiredAttachmentRecordMissing, subject: .citation(citation.id))
        }
        var attachmentCounts: [VerificationEvidenceArtifactID: Int] = [:]
        var hasRequiredRecord = false
        for attachment in citation.attachments {
            try budget.consume()
            attachmentCounts[attachment.id, default: 0] += 1
            if attachment.kind == verificationEvidenceRequiredAttachmentKind(citation.kind) {
                hasRequiredRecord = true
            }
            if verificationEvidenceIsPrimaryAttachmentKind(attachment.kind)
                && attachment.kind != verificationEvidenceRequiredAttachmentKind(citation.kind)
            {
                hasInvalid = true
                try add(
                    .error,
                    .invalidAttachmentReference,
                    subject: .attachment(attachment.id),
                    discriminator: "kind"
                )
            }
            if attachment.artifact.role != .evidenceAttachment
                || !verificationEvidenceArtifactIsStructurallyValid(attachment.artifact)
            {
                hasInvalid = true
                try add(
                    .error,
                    .invalidAttachmentReference,
                    subject: .attachment(attachment.id)
                )
            }
        }
        for (id, count) in attachmentCounts where count > 1 {
            hasInvalid = true
            try add(
                .error,
                .duplicateAttachmentReference,
                subject: .attachment(id),
                discriminator: String(count)
            )
        }
        if !hasRequiredRecord {
            hasInvalid = true
            try add(.error, .requiredAttachmentRecordMissing, subject: .citation(citation.id))
        }

        var claimData = try VerificationEvidenceCanonicalEncoder.collectorClaim(
            citation,
            limits: limits,
            budget: budget
        )
        if claimData.count > limits.maximumSigningPayloadBytes {
            hasInvalid = true
            try add(.error, .invalidLedger, subject: .citation(citation.id), discriminator: "claim-size")
        }
        let claimDigest = try verificationEvidenceSHA256(claimData, budget: budget)
        let claimByteCount = claimData.count
        claimData = Data()
        budget.releaseMemory(claimByteCount)
        var collectorSigningData = try VerificationEvidenceCanonicalEncoder.collectorSignature(
            claimSHA256: claimDigest,
            limits: limits,
            budget: budget
        )
        try verificationEvidenceValidateSigningPayloadSize(collectorSigningData, limits: limits)
        let collector = citation.collectorAttestation
        if !verificationEvidenceIsValidIdentifier(collector.collectorID.rawValue) {
            hasInvalid = true
            try add(.error, .invalidCollectorProvenance, subject: .citation(citation.id))
        }
        if collector.attestedAtUnixMilliseconds < citation.collectedAtUnixMilliseconds {
            hasInvalid = true
            try add(.error, .invalidCollectorProvenance, subject: .citation(citation.id))
        }
        let collectorRoots = try matchingRoots(
            principalID: collector.collectorID,
            role: .collector,
            at: collector.attestedAtUnixMilliseconds
        )
        if collectorRoots.count != 1 {
            hasUntrusted = true
            try add(.error, .untrustedCollector, subject: .principal(collector.collectorID))
        } else if try !verify(
            signature: collector.signature,
            data: collectorSigningData,
            root: collectorRoots[0]
        ) {
            hasUntrusted = true
            try add(.error, .invalidCollectorSignature, subject: .citation(citation.id))
        } else if collector.collectorID == submitterID
            || trustedSubmitterKeys.contains(collectorRoots[0].ed25519PublicKey)
        {
            hasUntrusted = true
            try add(.error, .selfAttestation, subject: .citation(citation.id), discriminator: "collector")
        }
        let collectorSigningByteCount = collectorSigningData.count
        collectorSigningData = Data()
        budget.releaseMemory(collectorSigningByteCount)

        if citation.reviews.isEmpty {
            hasUntrusted = true
            try add(.error, .missingReviewer, subject: .citation(citation.id))
        }
        if citation.reviews.count > 1 {
            hasUntrusted = true
            try add(
                .error,
                .duplicateReview,
                subject: .citation(citation.id),
                discriminator: String(citation.reviews.count)
            )
        }
        var reviewerCounts: [VerificationEvidencePrincipalID: Int] = [:]
        for review in citation.reviews {
            try budget.consume()
            reviewerCounts[review.reviewerID, default: 0] += 1
            if !verificationEvidenceIsValidIdentifier(review.reviewerID.rawValue) {
                hasInvalid = true
                try add(.error, .invalidReviewerProvenance, subject: .citation(citation.id))
            }
            if review.reviewerID == collector.collectorID {
                hasUntrusted = true
                try add(
                    .error,
                    .selfAttestation,
                    subject: .citation(citation.id),
                    discriminator: "reviewer"
                )
            }
            if review.verdict != .accepted {
                hasUntrusted = true
                try add(.error, .rejectedReview, subject: .citation(citation.id))
            }
            if review.reviewedAtUnixMilliseconds < collector.attestedAtUnixMilliseconds
                || review.reviewedAtUnixMilliseconds > trustedVerificationTimeUnixMilliseconds
            {
                hasInvalid = true
                try add(.error, .invalidReviewerProvenance, subject: .citation(citation.id))
            }
            if let expiry = review.expiresAtUnixMilliseconds,
                expiry <= review.reviewedAtUnixMilliseconds
                    || trustedVerificationTimeUnixMilliseconds >= expiry
            {
                hasStale = true
                try add(.error, .expiredEvidence, subject: .citation(citation.id), discriminator: "review")
            }
            if review.evidenceClaimSHA256 != claimDigest {
                hasMismatch = true
                try add(.error, .reviewDigestMismatch, subject: .citation(citation.id))
            }
            var reviewData = try VerificationEvidenceCanonicalEncoder.reviewerClaim(
                citationID: citation.id,
                review: review,
                limits: limits,
                budget: budget
            )
            try verificationEvidenceValidateSigningPayloadSize(reviewData, limits: limits)
            let reviewerRoots = try matchingRoots(
                principalID: review.reviewerID,
                role: .reviewer,
                at: review.reviewedAtUnixMilliseconds
            )
            if reviewerRoots.count != 1 {
                hasUntrusted = true
                try add(.error, .untrustedReviewer, subject: .principal(review.reviewerID))
            } else {
                if review.reviewerID == submitterID
                    || trustedSubmitterKeys.contains(reviewerRoots[0].ed25519PublicKey)
                {
                    hasUntrusted = true
                    try add(
                        .error,
                        .selfAttestation,
                        subject: .citation(citation.id),
                        discriminator: "submitter-reviewer"
                    )
                }
                if collectorRoots.count == 1,
                    collectorRoots[0].ed25519PublicKey == reviewerRoots[0].ed25519PublicKey
                {
                    hasUntrusted = true
                    try add(
                        .error,
                        .selfAttestation,
                        subject: .citation(citation.id),
                        discriminator: "shared-key"
                    )
                }
                if try !verify(signature: review.signature, data: reviewData, root: reviewerRoots[0]) {
                    hasUntrusted = true
                    try add(.error, .invalidReviewerSignature, subject: .citation(citation.id))
                }
            }
            let reviewByteCount = reviewData.count
            reviewData = Data()
            budget.releaseMemory(reviewByteCount)
        }
        for (reviewer, count) in reviewerCounts where count > 1 {
            hasUntrusted = true
            try add(
                .error,
                .duplicateReview,
                subject: .principal(reviewer),
                discriminator: String(count)
            )
        }

        if hasInvalid { return .invalid }
        if hasUntrusted { return .untrusted }
        if hasStale { return .stale }
        if hasMismatch { return .mismatched }
        return status
    }

    private func matchingRoots(
        principalID: VerificationEvidencePrincipalID,
        role: VerificationEvidenceTrustRole,
        at timestamp: UInt64
    ) throws -> [VerificationEvidenceTrustRoot] {
        try trustRootIndex.matchingRoots(
            principalID: principalID,
            role: role,
            signedAt: timestamp,
            verifiedAt: trustedVerificationTimeUnixMilliseconds,
            budget: budget
        )
    }

    private func verify(
        signature: [UInt8],
        data: Data,
        root: VerificationEvidenceTrustRoot
    ) throws -> Bool {
        try budget.consume(UInt64(signature.count + root.ed25519PublicKey.count + data.count))
        try budget.checkCancellation()
        guard signature.count == 64,
            let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: Data(root.ed25519PublicKey)
            )
        else { return false }
        let valid = publicKey.isValidSignature(Data(signature), for: data)
        try budget.checkCancellation()
        return valid
    }

    private mutating func add(
        _ severity: VerificationEvidenceFindingSeverity,
        _ code: VerificationEvidenceFindingCode,
        subject: VerificationEvidenceFindingSubject,
        discriminator: String = ""
    ) throws {
        try budget.consume()
        let findingID = try verificationEvidenceFindingID(
            code: code,
            subject: subject,
            discriminator: discriminator,
            budget: budget
        )
        let finding = VerificationEvidenceFinding(
            id: findingID,
            severity: severity,
            code: code,
            subject: subject
        )
        guard findingIDs.insert(finding.id).inserted else { return }
        guard findings.count < limits.maximumFindings else {
            throw VerificationEvidenceLedgerError.findingLimitExceeded(
                maximum: limits.maximumFindings
            )
        }
        findings.append(finding)
    }
}

private enum VerificationEvidencePreflight {
    static func validate(_ limits: VerificationEvidenceLedgerLimits) throws {
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumCount).contains(limits.maximumRows)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.rows) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumCount).contains(limits.maximumCitations)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.citations) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumCount).contains(limits.maximumAttachments)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.attachments) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumCount).contains(limits.maximumAttachmentsPerCitation)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.attachmentsPerCitation) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumCount).contains(limits.maximumReviews)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.reviews) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumCount).contains(limits.maximumReviewsPerCitation)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.reviewsPerCitation) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumCount).contains(limits.maximumTrustRoots)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.trustRoots) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumStringUTF8Bytes).contains(limits.maximumStringUTF8Bytes)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.stringUTF8Bytes) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumTotalStringUTF8Bytes).contains(limits.maximumTotalStringUTF8Bytes),
            limits.maximumTotalStringUTF8Bytes >= limits.maximumStringUTF8Bytes
        else { throw VerificationEvidenceLedgerError.invalidLimit(.totalStringUTF8Bytes) }
        guard (64...VerificationEvidenceLedgerLimits.hardMaximumBinaryFieldBytes).contains(limits.maximumBinaryFieldBytes)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.binaryFieldBytes) }
        guard
            (1...VerificationEvidenceLedgerLimits.hardMaximumSigningPayloadBytes).contains(
                limits.maximumSigningPayloadBytes
            )
        else { throw VerificationEvidenceLedgerError.invalidLimit(.signingPayloadBytes) }
        guard
            (1...VerificationEvidenceLedgerLimits.hardMaximumCanonicalRecordBytes).contains(
                limits.maximumCanonicalRecordBytes
            ), limits.maximumCanonicalRecordBytes <= limits.maximumArchiveBytes
        else { throw VerificationEvidenceLedgerError.invalidLimit(.canonicalRecordBytes) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumTotalItems).contains(limits.maximumTotalItems)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.totalItems) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumWorkUnits).contains(limits.maximumWorkUnits)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.workUnits) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumFindings).contains(limits.maximumFindings)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.findings) }
        guard (1...VerificationEvidenceLedgerLimits.hardMaximumArchiveBytes).contains(limits.maximumArchiveBytes)
        else { throw VerificationEvidenceLedgerError.invalidLimit(.archiveBytes) }
        guard
            (1...VerificationEvidenceLedgerLimits.hardMaximumCancellationCheckInterval).contains(
                limits.cancellationCheckInterval
            )
        else { throw VerificationEvidenceLedgerError.invalidLimit(.cancellationCheckInterval) }
    }

    static func inspect(
        manifest: VerificationRoadmapManifest,
        ledger: VerificationEvidenceLedger,
        trustPolicy: VerificationEvidenceTrustPolicy,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        guard manifest.rows.count <= limits.maximumRows else {
            throw VerificationEvidenceLedgerError.countLimitExceeded(
                kind: .rows,
                maximum: limits.maximumRows
            )
        }
        guard ledger.citations.count <= limits.maximumCitations else {
            throw VerificationEvidenceLedgerError.countLimitExceeded(
                kind: .citations,
                maximum: limits.maximumCitations
            )
        }
        guard trustPolicy.roots.count <= limits.maximumTrustRoots else {
            throw VerificationEvidenceLedgerError.countLimitExceeded(
                kind: .trustRoots,
                maximum: limits.maximumTrustRoots
            )
        }
        var strings = VerificationEvidenceStringBudget(budget: budget)
        var totalItems = try verificationEvidenceCheckedAdd(
            manifest.rows.count,
            ledger.citations.count
        )
        totalItems = try verificationEvidenceCheckedAdd(totalItems, trustPolicy.roots.count)
        try inspect(manifest.reference, strings: &strings, budget: budget)
        for row in manifest.rows {
            try budget.consume()
            try inspect(row.reference, strings: &strings, budget: budget)
        }
        try inspect(ledger.reference, strings: &strings, budget: budget)
        try inspect(ledger.manifest, strings: &strings, budget: budget)
        try inspect(ledger.targetBuild, strings: &strings, limits: limits, budget: budget)
        var attachmentCount = 0
        var reviewCount = 0
        for citation in ledger.citations {
            try budget.consume()
            guard citation.attachments.count <= limits.maximumAttachmentsPerCitation else {
                throw VerificationEvidenceLedgerError.countLimitExceeded(
                    kind: .attachmentsPerCitation,
                    maximum: limits.maximumAttachmentsPerCitation
                )
            }
            guard citation.reviews.count <= limits.maximumReviewsPerCitation else {
                throw VerificationEvidenceLedgerError.countLimitExceeded(
                    kind: .reviewsPerCitation,
                    maximum: limits.maximumReviewsPerCitation
                )
            }
            attachmentCount = try verificationEvidenceCheckedAdd(
                attachmentCount,
                citation.attachments.count
            )
            reviewCount = try verificationEvidenceCheckedAdd(reviewCount, citation.reviews.count)
            guard attachmentCount <= limits.maximumAttachments else {
                throw VerificationEvidenceLedgerError.countLimitExceeded(
                    kind: .attachments,
                    maximum: limits.maximumAttachments
                )
            }
            guard reviewCount <= limits.maximumReviews else {
                throw VerificationEvidenceLedgerError.countLimitExceeded(
                    kind: .reviews,
                    maximum: limits.maximumReviews
                )
            }
            try inspect(citation, strings: &strings, limits: limits, budget: budget)
        }
        totalItems = try verificationEvidenceCheckedAdd(totalItems, attachmentCount)
        totalItems = try verificationEvidenceCheckedAdd(totalItems, reviewCount)
        guard totalItems <= limits.maximumTotalItems else {
            throw VerificationEvidenceLedgerError.countLimitExceeded(
                kind: .totalItems,
                maximum: limits.maximumTotalItems
            )
        }
        for root in trustPolicy.roots {
            try budget.consume()
            try strings.consume(root.principalID.rawValue, field: "trustRoot.principalID")
            try inspectBinary(root.ed25519PublicKey, limits: limits, budget: budget)
        }
    }

    static func inspectAuditParties(
        auditorID: VerificationEvidencePrincipalID,
        submitterID: VerificationEvidencePrincipalID,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try budget.consumeString(auditorID.rawValue, field: "audit.auditorID")
        try budget.consumeString(submitterID.rawValue, field: "audit.submitterID")
    }

    static func inspect(
        _ citation: VerificationEvidenceCitation,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        guard citation.attachments.count <= limits.maximumAttachmentsPerCitation else {
            throw VerificationEvidenceLedgerError.countLimitExceeded(
                kind: .attachmentsPerCitation,
                maximum: limits.maximumAttachmentsPerCitation
            )
        }
        guard citation.reviews.count <= limits.maximumReviewsPerCitation else {
            throw VerificationEvidenceLedgerError.countLimitExceeded(
                kind: .reviewsPerCitation,
                maximum: limits.maximumReviewsPerCitation
            )
        }
        guard citation.attachments.count <= limits.maximumAttachments else {
            throw VerificationEvidenceLedgerError.countLimitExceeded(
                kind: .attachments,
                maximum: limits.maximumAttachments
            )
        }
        guard citation.reviews.count <= limits.maximumReviews else {
            throw VerificationEvidenceLedgerError.countLimitExceeded(
                kind: .reviews,
                maximum: limits.maximumReviews
            )
        }
        var totalItems = try verificationEvidenceCheckedAdd(
            citation.attachments.count,
            citation.reviews.count
        )
        totalItems = try verificationEvidenceCheckedAdd(totalItems, 1)
        guard totalItems <= limits.maximumTotalItems else {
            throw VerificationEvidenceLedgerError.countLimitExceeded(
                kind: .totalItems,
                maximum: limits.maximumTotalItems
            )
        }
        var strings = VerificationEvidenceStringBudget(budget: budget)
        try inspect(citation, strings: &strings, limits: limits, budget: budget)
    }

    static func inspect(
        _ review: VerificationEvidenceReviewAttestation,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try budget.consume()
        try budget.consumeString(review.reviewerID.rawValue, field: "review.reviewerID")
        try inspect(review.evidenceClaimSHA256, limits: limits, budget: budget)
        try inspectBinary(review.signature, limits: limits, budget: budget)
    }

    static func inspect(
        _ attestation: VerificationEvidenceAuditAttestation,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try budget.consume()
        try budget.consumeString(attestation.auditorID.rawValue, field: "audit.auditorID")
        try budget.consumeString(attestation.submitterID.rawValue, field: "audit.submitterID")
        try inspect(attestation.manifestSHA256, limits: limits, budget: budget)
        try inspect(attestation.ledgerSHA256, limits: limits, budget: budget)
        try inspect(attestation.trustPolicySHA256, limits: limits, budget: budget)
        try inspect(attestation.reportSHA256, limits: limits, budget: budget)
        try inspect(attestation.archiveSHA256, limits: limits, budget: budget)
        try inspectBinary(attestation.signature, limits: limits, budget: budget)
    }

    private static func inspect(
        _ citation: VerificationEvidenceCitation,
        strings: inout VerificationEvidenceStringBudget,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try strings.consume(citation.id.rawValue, field: "citation.id")
        try inspect(citation.row, strings: &strings, budget: budget)
        try inspect(citation.testRun, strings: &strings, limits: limits, budget: budget)
        try strings.consume(
            citation.collectorAttestation.collectorID.rawValue,
            field: "citation.collectorID"
        )
        try inspectBinary(citation.collectorAttestation.signature, limits: limits, budget: budget)
        for attachment in citation.attachments {
            try budget.consume()
            try inspect(attachment.artifact, strings: &strings, limits: limits, budget: budget)
        }
        for review in citation.reviews {
            try budget.consume()
            try strings.consume(review.reviewerID.rawValue, field: "review.reviewerID")
            try inspect(review.evidenceClaimSHA256, limits: limits, budget: budget)
            try inspectBinary(review.signature, limits: limits, budget: budget)
        }
    }

    private static func inspect(
        _ run: VerificationEvidenceTestRunProvenance,
        strings: inout VerificationEvidenceStringBudget,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try inspect(run.reference, strings: &strings, budget: budget)
        try inspect(run.build, strings: &strings, limits: limits, budget: budget)
        try inspect(run.testRunner, strings: &strings, limits: limits, budget: budget)
        try inspect(run.testBundle, strings: &strings, limits: limits, budget: budget)
        try inspect(run.configuration, strings: &strings, limits: limits, budget: budget)
    }

    private static func inspect(
        _ build: VerificationEvidenceAppBuildProvenance,
        strings: inout VerificationEvidenceStringBudget,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try inspect(build.application, strings: &strings, budget: budget)
        try inspect(build.build, strings: &strings, budget: budget)
        try inspect(build.applicationBundle, strings: &strings, limits: limits, budget: budget)
        try inspect(build.executable, strings: &strings, limits: limits, budget: budget)
        try inspect(build.signingIdentity, strings: &strings, limits: limits, budget: budget)
    }

    private static func inspect(
        _ artifact: VerificationEvidenceArtifactReference,
        strings: inout VerificationEvidenceStringBudget,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try budget.consume()
        try strings.consume(artifact.id.rawValue, field: "artifact.id")
        try strings.consume(artifact.mediaType, field: "artifact.mediaType")
        try inspect(artifact.digest, limits: limits, budget: budget)
    }

    private static func inspect<Domain>(
        _ reference: VerificationEvidenceRevisionReference<Domain>,
        strings: inout VerificationEvidenceStringBudget,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try budget.consume()
        try strings.consume(reference.id.rawValue, field: "reference.id")
    }

    private static func inspect(
        _ digest: VerificationEvidenceDigest,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try inspectBinary(digest.bytes, limits: limits, budget: budget)
    }

    private static func inspectBinary(
        _ bytes: [UInt8],
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        guard bytes.count <= limits.maximumBinaryFieldBytes else {
            throw VerificationEvidenceLedgerError.binaryFieldTooLarge(
                maximumBytes: limits.maximumBinaryFieldBytes
            )
        }
        try budget.consume(UInt64(bytes.count))
    }
}

private enum VerificationEvidenceCanonicalEncoder {
    static func collectorSignature(
        claimSHA256: VerificationEvidenceDigest,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws -> Data {
        var writer = VerificationEvidenceWriter(
            limits: limits,
            budget: budget,
            capacity: .signingPayload
        )
        try writer.appendString(VerificationEvidenceAuditor.collectorSignatureDomain)
        try writer.appendUInt16(UInt16(VerificationEvidenceAuditor.schemaVersion))
        try writer.appendDigest(claimSHA256)
        return writer.data
    }

    static func collectorClaim(
        _ citation: VerificationEvidenceCitation,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws -> Data {
        var writer = VerificationEvidenceWriter(
            limits: limits,
            budget: budget,
            capacity: .signingPayload
        )
        try writer.appendString(VerificationEvidenceAuditor.collectorClaimDomain)
        try writer.appendUInt16(UInt16(VerificationEvidenceAuditor.schemaVersion))
        try appendCitationClaim(citation, to: &writer)
        return writer.data
    }

    static func reviewerClaim(
        citationID: VerificationEvidenceCitationID,
        review: VerificationEvidenceReviewAttestation,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws -> Data {
        var writer = VerificationEvidenceWriter(
            limits: limits,
            budget: budget,
            capacity: .signingPayload
        )
        try writer.appendString(VerificationEvidenceAuditor.reviewerClaimDomain)
        try writer.appendUInt16(UInt16(VerificationEvidenceAuditor.schemaVersion))
        try writer.appendString(citationID.rawValue)
        try writer.appendString(review.reviewerID.rawValue)
        try writer.appendString(review.verdict.rawValue)
        try writer.appendUInt64(review.reviewedAtUnixMilliseconds)
        try writer.appendOptionalUInt64(review.expiresAtUnixMilliseconds)
        try writer.appendDigest(review.evidenceClaimSHA256)
        return writer.data
    }

    static func auditClaim(
        _ attestation: VerificationEvidenceAuditAttestation,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws -> Data {
        var writer = VerificationEvidenceWriter(
            limits: limits,
            budget: budget,
            capacity: .signingPayload
        )
        try writer.appendString(VerificationEvidenceAuditor.auditClaimDomain)
        try writer.appendUInt16(UInt16(VerificationEvidenceAuditor.schemaVersion))
        try writer.appendString(attestation.auditorID.rawValue)
        try writer.appendString(attestation.submitterID.rawValue)
        try writer.appendUInt64(attestation.auditedAtUnixMilliseconds)
        try writer.appendUInt64(attestation.trustedVerificationTimeUnixMilliseconds)
        try writer.appendDigest(attestation.manifestSHA256)
        try writer.appendDigest(attestation.ledgerSHA256)
        try writer.appendDigest(attestation.trustPolicySHA256)
        try writer.appendDigest(attestation.reportSHA256)
        try writer.appendDigest(attestation.archiveSHA256)
        return writer.data
    }

    static func manifest(
        _ manifest: VerificationRoadmapManifest,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendString(VerificationEvidenceAuditor.manifestDomain)
        try writer.appendUInt16(UInt16(VerificationEvidenceAuditor.schemaVersion))
        try writer.appendReference(manifest.reference)
        let rows = try sortedRows(manifest.rows, limits: limits, budget: budget)
        try writer.appendCount(rows.count)
        for row in rows {
            let recordMaximumBytes = min(
                limits.maximumCanonicalRecordBytes,
                writer.capacity.maximumBytes(for: limits) - writer.count
            )
            var record = VerificationEvidenceWriter(
                limits: limits,
                budget: budget,
                capacity: writer.capacity.limited(to: recordMaximumBytes)
            )
            try appendRow(row, to: &record)
            try validateRecordSize(record.data, limits: limits)
            var recordData = record.transferData()
            try writer.appendTransferredBytes(&recordData)
        }
    }

    static func ledger(
        _ ledger: VerificationEvidenceLedger,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendString(VerificationEvidenceAuditor.ledgerDomain)
        try writer.appendUInt16(UInt16(VerificationEvidenceAuditor.schemaVersion))
        try writer.appendReference(ledger.reference)
        try writer.appendReference(ledger.manifest)
        try appendBuild(ledger.targetBuild, to: &writer)
        let citations = try sortedCitations(ledger.citations, limits: limits, budget: budget)
        try writer.appendCount(citations.count)
        for citation in citations {
            let recordMaximumBytes = min(
                limits.maximumCanonicalRecordBytes,
                writer.capacity.maximumBytes(for: limits) - writer.count
            )
            var record = VerificationEvidenceWriter(
                limits: limits,
                budget: budget,
                capacity: writer.capacity.limited(to: recordMaximumBytes)
            )
            try appendCitation(
                citation,
                to: &record,
                limits: limits,
                budget: budget
            )
            try validateRecordSize(record.data, limits: limits)
            var recordData = record.transferData()
            try writer.appendTransferredBytes(&recordData)
        }
    }

    static func trustPolicy(
        _ policy: VerificationEvidenceTrustPolicy,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendString(VerificationEvidenceAuditor.trustPolicyDomain)
        try writer.appendUInt16(UInt16(VerificationEvidenceAuditor.schemaVersion))
        for kind in VerificationEvidenceKind.allCases {
            try writer.appendString(kind.rawValue)
            try writer.appendUInt64(policy.freshness.maximumAgeMilliseconds(for: kind))
        }
        try writer.appendUInt64(policy.freshness.maximumCollectionLagMilliseconds)
        let roots = try sortedRoots(policy.roots, limits: limits, budget: budget)
        try writer.appendCount(roots.count)
        for root in roots {
            let recordMaximumBytes = min(
                limits.maximumCanonicalRecordBytes,
                writer.capacity.maximumBytes(for: limits) - writer.count
            )
            var record = VerificationEvidenceWriter(
                limits: limits,
                budget: budget,
                capacity: writer.capacity.limited(to: recordMaximumBytes)
            )
            try record.appendString(root.principalID.rawValue)
            let roles = VerificationEvidenceTrustRole.allCases.filter(root.roles.contains)
            try record.appendCount(roles.count)
            for role in roles { try record.appendString(role.rawValue) }
            try record.appendBytes(root.ed25519PublicKey)
            try record.appendUInt64(root.validFromUnixMilliseconds)
            try record.appendUInt64(root.validThroughUnixMilliseconds)
            try record.appendOptionalUInt64(root.revokedAtUnixMilliseconds)
            try validateRecordSize(record.data, limits: limits)
            var recordData = record.transferData()
            try writer.appendTransferredBytes(&recordData)
        }
    }

    static func report(
        _ report: VerificationEvidenceAuditReport,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendString(VerificationEvidenceAuditor.reportDomain)
        try writer.appendUInt16(UInt16(report.schemaVersion))
        try writer.appendReference(report.manifest)
        try writer.appendReference(report.ledger)
        try writer.appendUInt64(report.auditedAtUnixMilliseconds)
        try writer.appendCount(report.rows.count)
        for row in report.rows {
            try writer.appendString(row.id.rawValue)
            try writer.appendUInt64(row.rowRevision.rawValue)
            try writer.appendBool(row.completionClaimed)
            try writer.appendString(row.status.rawValue)
            try writer.appendCount(row.cells.count)
            for cell in row.cells {
                try writer.appendString(cell.kind.rawValue)
                try writer.appendCount(cell.evidenceCount)
                try writer.appendString(cell.status.rawValue)
                try writer.appendCount(cell.citationIDs.count)
                for id in cell.citationIDs { try writer.appendString(id.rawValue) }
            }
        }
        try writer.appendCount(report.findings.count)
        for finding in report.findings {
            try writer.appendString(finding.id.rawValue)
            try writer.appendString(finding.severity.rawValue)
            try writer.appendString(finding.code.rawValue)
            try writer.appendString(finding.subject.canonicalTag)
            try writer.appendCount(finding.subject.canonicalComponents.count)
            for component in finding.subject.canonicalComponents {
                try writer.appendString(component)
            }
        }
    }

    static func reportEvaluation(
        _ report: VerificationEvidenceAuditReport,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendString(VerificationEvidenceAuditor.reportEvaluationDomain)
        try writer.appendUInt16(UInt16(report.schemaVersion))
        try writer.appendReference(report.manifest)
        try writer.appendReference(report.ledger)
        try writer.appendCount(report.rows.count)
        for row in report.rows {
            try writer.appendString(row.id.rawValue)
            try writer.appendUInt64(row.rowRevision.rawValue)
            try writer.appendBool(row.completionClaimed)
            try writer.appendString(row.status.rawValue)
            try writer.appendCount(row.cells.count)
            for cell in row.cells {
                try writer.appendString(cell.kind.rawValue)
                try writer.appendCount(cell.evidenceCount)
                try writer.appendString(cell.status.rawValue)
                try writer.appendCount(cell.citationIDs.count)
                for id in cell.citationIDs { try writer.appendString(id.rawValue) }
            }
        }
        try writer.appendCount(report.findings.count)
        for finding in report.findings {
            try writer.appendString(finding.id.rawValue)
            try writer.appendString(finding.severity.rawValue)
            try writer.appendString(finding.code.rawValue)
            try writer.appendString(finding.subject.canonicalTag)
            try writer.appendCount(finding.subject.canonicalComponents.count)
            for component in finding.subject.canonicalComponents {
                try writer.appendString(component)
            }
        }
    }

    static func archive(
        manifest: VerificationRoadmapManifest,
        ledger: VerificationEvidenceLedger,
        trustPolicy: VerificationEvidenceTrustPolicy,
        report: VerificationEvidenceAuditReport,
        sectionByteCounts: [Int],
        manifestDigest: VerificationEvidenceDigest,
        ledgerDigest: VerificationEvidenceDigest,
        trustPolicyDigest: VerificationEvidenceDigest,
        reportDigest: VerificationEvidenceDigest,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws -> VerificationEvidenceCanonicalArchive {
        guard sectionByteCounts.count == 4 else {
            throw VerificationEvidenceLedgerError.integerOverflow
        }
        var sizingWriter = VerificationEvidenceWriter(
            limits: limits,
            budget: budget,
            storesData: false
        )
        try appendArchiveHeader(
            manifestDigest: manifestDigest,
            ledgerDigest: ledgerDigest,
            trustPolicyDigest: trustPolicyDigest,
            reportDigest: reportDigest,
            to: &sizingWriter
        )
        for byteCount in sectionByteCounts {
            try sizingWriter.appendCount(byteCount)
            try sizingWriter.appendUnwrittenBytes(count: byteCount)
        }
        let archiveDigestHasher = VerificationEvidenceStreamingSHA256()
        try verificationEvidenceStartDomainSHA256(
            archiveDigestHasher,
            domain: VerificationEvidenceAuditor.archiveDomain,
            dataCount: sizingWriter.count,
            limits: limits,
            budget: budget
        )
        var writer = VerificationEvidenceWriter(
            limits: limits,
            budget: budget,
            hashers: [archiveDigestHasher]
        )
        try appendArchiveHeader(
            manifestDigest: manifestDigest,
            ledgerDigest: ledgerDigest,
            trustPolicyDigest: trustPolicyDigest,
            reportDigest: reportDigest,
            to: &writer
        )
        try writer.appendCount(sectionByteCounts[0])
        let manifestStart = writer.count
        try self.manifest(manifest, limits: limits, budget: budget, to: &writer)
        guard writer.count - manifestStart == sectionByteCounts[0] else {
            throw VerificationEvidenceLedgerError.integerOverflow
        }
        try writer.appendCount(sectionByteCounts[1])
        let ledgerStart = writer.count
        try self.ledger(ledger, limits: limits, budget: budget, to: &writer)
        guard writer.count - ledgerStart == sectionByteCounts[1] else {
            throw VerificationEvidenceLedgerError.integerOverflow
        }
        try writer.appendCount(sectionByteCounts[2])
        let trustPolicyStart = writer.count
        try self.trustPolicy(trustPolicy, limits: limits, budget: budget, to: &writer)
        guard writer.count - trustPolicyStart == sectionByteCounts[2] else {
            throw VerificationEvidenceLedgerError.integerOverflow
        }
        try writer.appendCount(sectionByteCounts[3])
        let reportStart = writer.count
        try self.report(report, limits: limits, budget: budget, to: &writer)
        guard writer.count - reportStart == sectionByteCounts[3] else {
            throw VerificationEvidenceLedgerError.integerOverflow
        }
        guard writer.count == sizingWriter.count else {
            throw VerificationEvidenceLedgerError.integerOverflow
        }
        try budget.checkCancellation()
        return VerificationEvidenceCanonicalArchive(
            data: writer.transferData(),
            sha256: archiveDigestHasher.finalize()
        )
    }

    private static func appendArchiveHeader(
        manifestDigest: VerificationEvidenceDigest,
        ledgerDigest: VerificationEvidenceDigest,
        trustPolicyDigest: VerificationEvidenceDigest,
        reportDigest: VerificationEvidenceDigest,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendRaw(Data("MMVEL002".utf8))
        try writer.appendString(VerificationEvidenceAuditor.archiveDomain)
        try writer.appendUInt16(UInt16(VerificationEvidenceAuditor.schemaVersion))
        try writer.appendDigest(manifestDigest)
        try writer.appendDigest(ledgerDigest)
        try writer.appendDigest(trustPolicyDigest)
        try writer.appendDigest(reportDigest)
    }

    static func sortedRows(
        _ rows: [VerificationRoadmapRowRequirement],
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws -> [VerificationRoadmapRowRequirement] {
        var keyed: [(Data, Data, VerificationRoadmapRowRequirement)] = []
        var retainedBytes = 0
        keyed.reserveCapacity(rows.count)
        for row in rows {
            var writer = VerificationEvidenceWriter(limits: limits, budget: budget)
            try appendRow(row, to: &writer)
            try validateRecordSize(writer.data, limits: limits)
            let digest = try verificationEvidenceSHA256(writer.data, budget: budget)
            try budget.retainMemory(digest.bytes.count)
            retainedBytes = try verificationEvidenceCheckedAdd(
                retainedBytes,
                writer.data.count + digest.bytes.count
            )
            keyed.append((Data(digest.bytes), writer.data, row))
        }
        var sorted = try sortedHashed(keyed, budget: budget)
        keyed.removeAll(keepingCapacity: false)
        let result = sorted.map(\.2)
        sorted.removeAll(keepingCapacity: false)
        budget.releaseMemory(retainedBytes)
        return result
    }

    static func sortedCitations(
        _ citations: [VerificationEvidenceCitation],
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws -> [VerificationEvidenceCitation] {
        var keyed: [(Data, Data, VerificationEvidenceCitation)] = []
        var retainedBytes = 0
        keyed.reserveCapacity(citations.count)
        for citation in citations {
            var writer = VerificationEvidenceWriter(limits: limits, budget: budget)
            try appendCitation(
                citation,
                to: &writer,
                limits: limits,
                budget: budget
            )
            try validateRecordSize(writer.data, limits: limits)
            let digest = try verificationEvidenceSHA256(writer.data, budget: budget)
            try budget.retainMemory(digest.bytes.count)
            retainedBytes = try verificationEvidenceCheckedAdd(
                retainedBytes,
                writer.data.count + digest.bytes.count
            )
            keyed.append((Data(digest.bytes), writer.data, citation))
        }
        var sorted = try sortedHashed(keyed, budget: budget)
        keyed.removeAll(keepingCapacity: false)
        let result = sorted.map(\.2)
        sorted.removeAll(keepingCapacity: false)
        budget.releaseMemory(retainedBytes)
        return result
    }

    private static func sortedRoots(
        _ roots: [VerificationEvidenceTrustRoot],
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws -> [VerificationEvidenceTrustRoot] {
        var keyed: [(Data, Data, VerificationEvidenceTrustRoot)] = []
        var retainedBytes = 0
        keyed.reserveCapacity(roots.count)
        for root in roots {
            var writer = VerificationEvidenceWriter(limits: limits, budget: budget)
            try writer.appendString(root.principalID.rawValue)
            let roles = VerificationEvidenceTrustRole.allCases.filter(root.roles.contains)
            try writer.appendCount(roles.count)
            for role in roles { try writer.appendString(role.rawValue) }
            try writer.appendBytes(root.ed25519PublicKey)
            try writer.appendUInt64(root.validFromUnixMilliseconds)
            try writer.appendUInt64(root.validThroughUnixMilliseconds)
            try writer.appendOptionalUInt64(root.revokedAtUnixMilliseconds)
            let digest = try verificationEvidenceSHA256(writer.data, budget: budget)
            try budget.retainMemory(digest.bytes.count)
            retainedBytes = try verificationEvidenceCheckedAdd(
                retainedBytes,
                writer.data.count + digest.bytes.count
            )
            keyed.append((Data(digest.bytes), writer.data, root))
        }
        var sorted = try sortedHashed(keyed, budget: budget)
        keyed.removeAll(keepingCapacity: false)
        let result = sorted.map(\.2)
        sorted.removeAll(keepingCapacity: false)
        budget.releaseMemory(retainedBytes)
        return result
    }

    private static func appendRow(
        _ row: VerificationRoadmapRowRequirement,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendReference(row.reference)
        switch row.applicability {
        case .notApplicable:
            try writer.appendUInt8(0)
        case .applicable(let statefulness):
            try writer.appendUInt8(1)
            try writer.appendString(statefulness.rawValue)
        }
        try writer.appendBool(row.completionClaimed)
        let kinds = VerificationEvidenceKind.allCases.filter(row.requiredEvidenceKinds.contains)
        try writer.appendCount(kinds.count)
        for kind in kinds { try writer.appendString(kind.rawValue) }
    }

    private static func appendCitation(
        _ citation: VerificationEvidenceCitation,
        to writer: inout VerificationEvidenceWriter,
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget
    ) throws {
        try appendCitationClaim(citation, to: &writer)
        try writer.appendBytes(citation.collectorAttestation.signature)
        var reviewRecords: [Data] = []
        reviewRecords.reserveCapacity(citation.reviews.count)
        for review in citation.reviews {
            let recordMaximumBytes = min(
                limits.maximumCanonicalRecordBytes,
                writer.capacity.maximumBytes(for: limits) - writer.count
            )
            var record = VerificationEvidenceWriter(
                limits: limits,
                budget: budget,
                capacity: writer.capacity.limited(to: recordMaximumBytes)
            )
            try record.appendString(review.reviewerID.rawValue)
            try record.appendString(review.verdict.rawValue)
            try record.appendUInt64(review.reviewedAtUnixMilliseconds)
            try record.appendOptionalUInt64(review.expiresAtUnixMilliseconds)
            try record.appendDigest(review.evidenceClaimSHA256)
            try record.appendBytes(review.signature)
            try validateRecordSize(record.data, limits: limits)
            reviewRecords.append(record.transferData())
        }
        var sortedReviewRecords = try sortedRecords(reviewRecords, budget: budget)
        reviewRecords.removeAll(keepingCapacity: false)
        try writer.appendTransferredRecords(&sortedReviewRecords)
    }

    private static func appendCitationClaim(
        _ citation: VerificationEvidenceCitation,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendString(citation.id.rawValue)
        try writer.appendReference(citation.row)
        try writer.appendString(citation.kind.rawValue)
        try writer.appendString(citation.basis.rawValue)
        try writer.appendString(citation.outcome.rawValue)
        try writer.appendUInt64(citation.collectedAtUnixMilliseconds)
        try writer.appendOptionalUInt64(citation.expiresAtUnixMilliseconds)
        try appendTestRun(citation.testRun, to: &writer)
        var attachmentRecords: [Data] = []
        attachmentRecords.reserveCapacity(citation.attachments.count)
        for attachment in citation.attachments {
            let recordMaximumBytes = min(
                writer.limits.maximumCanonicalRecordBytes,
                writer.capacity.maximumBytes(for: writer.limits) - writer.count
            )
            var record = VerificationEvidenceWriter(
                limits: writer.limits,
                budget: writer.budget,
                capacity: writer.capacity.limited(to: recordMaximumBytes)
            )
            try record.appendString(attachment.kind.rawValue)
            try appendArtifact(attachment.artifact, to: &record)
            try validateRecordSize(record.data, limits: writer.limits)
            attachmentRecords.append(record.transferData())
        }
        var sortedAttachmentRecords = try sortedRecords(attachmentRecords, budget: writer.budget)
        attachmentRecords.removeAll(keepingCapacity: false)
        try writer.appendTransferredRecords(&sortedAttachmentRecords)
        try writer.appendString(citation.collectorAttestation.collectorID.rawValue)
        try writer.appendUInt64(citation.collectorAttestation.attestedAtUnixMilliseconds)
    }

    private static func appendTestRun(
        _ run: VerificationEvidenceTestRunProvenance,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendReference(run.reference)
        try appendBuild(run.build, to: &writer)
        try appendArtifact(run.testRunner, to: &writer)
        try appendArtifact(run.testBundle, to: &writer)
        try appendArtifact(run.configuration, to: &writer)
        try writer.appendUInt64(run.startedAtUnixMilliseconds)
        try writer.appendUInt64(run.finishedAtUnixMilliseconds)
        try writer.appendString(run.outcome.rawValue)
    }

    private static func appendBuild(
        _ build: VerificationEvidenceAppBuildProvenance,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendReference(build.application)
        try writer.appendReference(build.build)
        try appendArtifact(build.applicationBundle, to: &writer)
        try appendArtifact(build.executable, to: &writer)
        try appendArtifact(build.signingIdentity, to: &writer)
    }

    private static func appendArtifact(
        _ artifact: VerificationEvidenceArtifactReference,
        to writer: inout VerificationEvidenceWriter
    ) throws {
        try writer.appendString(artifact.id.rawValue)
        try writer.appendString(artifact.role.rawValue)
        try writer.appendString(artifact.mediaType)
        try writer.appendUInt64(artifact.byteCount)
        try writer.appendDigest(artifact.digest)
    }

    private static func sortedRecords(
        _ records: [Data],
        budget: VerificationEvidenceWorkBudget
    ) throws -> [Data] {
        try sortedKeyed(records.map { ($0, $0) }, budget: budget).map(\.1)
    }

    private static func validateRecordSize(
        _ data: Data,
        limits: VerificationEvidenceLedgerLimits
    ) throws {
        guard data.count <= limits.maximumCanonicalRecordBytes else {
            throw VerificationEvidenceLedgerError.archiveTooLarge(
                maximumBytes: limits.maximumCanonicalRecordBytes
            )
        }
    }

    private static func sortedKeyed<Value>(
        _ values: [(Data, Value)],
        budget: VerificationEvidenceWorkBudget
    ) throws -> [(Data, Value)] {
        try verificationEvidenceStableSorted(values, budget: budget) { left, right in
            try verificationEvidenceDataPrecedes(left.0, right.0, budget: budget)
        }
    }

    private static func sortedHashed<Value>(
        _ values: [(Data, Data, Value)],
        budget: VerificationEvidenceWorkBudget
    ) throws -> [(Data, Data, Value)] {
        let result = try verificationEvidenceStableSorted(values, budget: budget) { left, right in
            try verificationEvidenceDataPrecedes(left.0, right.0, budget: budget)
        }
        guard result.count > 1 else { return result }
        for index in 1..<result.count where result[index - 1].0 == result[index].0 {
            try budget.consume()
            guard result[index - 1].1 == result[index].1 else {
                throw VerificationEvidenceLedgerError.canonicalDigestCollision
            }
        }
        return result
    }
}

private enum VerificationEvidenceWriterCapacity {
    case archive(maximumBytes: Int?)
    case signingPayload

    func maximumBytes(for limits: VerificationEvidenceLedgerLimits) -> Int {
        switch self {
        case .archive(let maximumBytes):
            min(maximumBytes ?? limits.maximumArchiveBytes, limits.maximumArchiveBytes)
        case .signingPayload:
            limits.maximumSigningPayloadBytes
        }
    }

    func overflowError(for limits: VerificationEvidenceLedgerLimits) -> VerificationEvidenceLedgerError {
        switch self {
        case .archive:
            .archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
        case .signingPayload:
            .signingPayloadTooLarge(maximumBytes: limits.maximumSigningPayloadBytes)
        }
    }

    func limited(to maximumBytes: Int) -> Self {
        switch self {
        case .archive(let existingMaximumBytes):
            .archive(maximumBytes: min(existingMaximumBytes ?? maximumBytes, maximumBytes))
        case .signingPayload:
            .signingPayload
        }
    }
}

private struct VerificationEvidenceWriter {
    private(set) var data = Data()
    private(set) var count = 0
    let limits: VerificationEvidenceLedgerLimits
    let budget: VerificationEvidenceWorkBudget
    let capacity: VerificationEvidenceWriterCapacity
    let storesData: Bool
    let hashers: [VerificationEvidenceStreamingSHA256]

    init(
        limits: VerificationEvidenceLedgerLimits,
        budget: VerificationEvidenceWorkBudget,
        capacity: VerificationEvidenceWriterCapacity = .archive(maximumBytes: nil),
        storesData: Bool = true,
        hashers: [VerificationEvidenceStreamingSHA256] = []
    ) {
        self.limits = limits
        self.budget = budget
        self.capacity = capacity
        self.storesData = storesData
        self.hashers = hashers
    }

    mutating func appendRaw(_ value: Data) throws {
        try budget.consume(UInt64(value.count))
        let maximumBytes = capacity.maximumBytes(for: limits)
        guard value.count <= maximumBytes,
            count <= maximumBytes - value.count
        else {
            throw capacity.overflowError(for: limits)
        }
        count += value.count
        for hasher in hashers {
            try budget.consume(UInt64(value.count))
            hasher.update(value)
        }
        if storesData {
            try budget.retainMemory(value.count)
            data.append(value)
        }
    }

    mutating func appendUInt8(_ value: UInt8) throws {
        try appendRaw(Data([value]))
    }

    mutating func appendUInt16(_ value: UInt16) throws {
        try appendRaw(Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]))
    }

    mutating func appendUInt32(_ value: UInt32) throws {
        try appendRaw(Data((0..<4).map { UInt8((value >> UInt32($0 * 8)) & 0xff) }))
    }

    mutating func appendUInt64(_ value: UInt64) throws {
        try appendRaw(Data((0..<8).map { UInt8((value >> UInt64($0 * 8)) & 0xff) }))
    }

    mutating func appendBool(_ value: Bool) throws {
        try appendUInt8(value ? 1 : 0)
    }

    mutating func appendCount(_ value: Int) throws {
        guard let count = UInt32(exactly: value) else {
            throw VerificationEvidenceLedgerError.integerOverflow
        }
        try appendUInt32(count)
    }

    mutating func appendString(_ value: String) throws {
        try budget.consumeString(value, field: "canonical.string")
        var bytes = Data(value.utf8)
        guard bytes.count <= limits.maximumStringUTF8Bytes else {
            throw VerificationEvidenceLedgerError.stringTooLarge(
                field: "canonical.string",
                maximumUTF8Bytes: limits.maximumStringUTF8Bytes
            )
        }
        try budget.retainMemory(bytes.count)
        try appendTransferredBytes(&bytes)
    }

    mutating func appendBytes(_ value: [UInt8]) throws {
        var bytes = Data(value)
        try budget.retainMemory(bytes.count)
        try appendTransferredBytes(&bytes)
    }

    mutating func appendBytes(_ value: Data) throws {
        try appendCount(value.count)
        try appendRaw(value)
    }

    mutating func appendOptionalUInt64(_ value: UInt64?) throws {
        guard let value else {
            try appendUInt8(0)
            return
        }
        try appendUInt8(1)
        try appendUInt64(value)
    }

    mutating func appendDigest(_ digest: VerificationEvidenceDigest) throws {
        try appendString(digest.algorithm.rawValue)
        try appendBytes(digest.bytes)
    }

    mutating func appendReference<Domain>(
        _ reference: VerificationEvidenceRevisionReference<Domain>
    ) throws {
        try appendString(reference.id.rawValue)
        try appendUInt64(reference.revision.rawValue)
    }

    mutating func appendTransferredBytes(_ value: inout Data) throws {
        try appendCount(value.count)
        try budget.consume(UInt64(value.count))
        let maximumBytes = capacity.maximumBytes(for: limits)
        guard value.count <= maximumBytes,
            count <= maximumBytes - value.count
        else {
            throw capacity.overflowError(for: limits)
        }
        let transferredByteCount = value.count
        count += transferredByteCount
        for hasher in hashers { hasher.update(value) }
        if storesData {
            try budget.retainMemory(transferredByteCount)
            data.append(value)
            value = Data()
            budget.releaseMemory(transferredByteCount)
        } else {
            value = Data()
            budget.releaseMemory(transferredByteCount)
        }
    }

    mutating func appendTransferredRecords(_ records: inout [Data]) throws {
        try appendCount(records.count)
        for index in records.indices {
            try appendTransferredBytes(&records[index])
        }
    }

    mutating func appendUnwrittenBytes(count byteCount: Int) throws {
        let maximumBytes = capacity.maximumBytes(for: limits)
        guard byteCount <= maximumBytes,
            count <= maximumBytes - byteCount
        else {
            throw capacity.overflowError(for: limits)
        }
        count += byteCount
    }

    mutating func transferData() -> Data {
        let result = data
        data = Data()
        return result
    }
}

private final class VerificationEvidenceStreamingSHA256 {
    private var hasher = SHA256()

    func update(_ data: Data) {
        hasher.update(data: data)
    }

    func finalize() -> VerificationEvidenceDigest {
        VerificationEvidenceDigest(bytes: Array(hasher.finalize()))
    }
}

private final class VerificationEvidenceWorkBudget {
    private let maximum: UInt64
    private let cancellationCheckInterval: UInt64
    private let cancellationCheck: VerificationEvidenceAuditor.CancellationCheck
    private let maximumStringUTF8Bytes: Int
    private let maximumTotalStringUTF8Bytes: Int
    private let maximumRetainedBytes: Int
    private var consumed: UInt64 = 0
    private var workUntilCancellationCheck: UInt64
    private var consumedStringUTF8Bytes = 0
    private var retainedBytes = 0

    init(
        limits: VerificationEvidenceLedgerLimits,
        cancellationCheck: @escaping VerificationEvidenceAuditor.CancellationCheck
    ) throws {
        maximum = limits.maximumWorkUnits
        cancellationCheckInterval = UInt64(limits.cancellationCheckInterval)
        self.cancellationCheck = cancellationCheck
        maximumStringUTF8Bytes = limits.maximumStringUTF8Bytes
        maximumTotalStringUTF8Bytes = limits.maximumTotalStringUTF8Bytes
        maximumRetainedBytes = limits.maximumArchiveBytes
        workUntilCancellationCheck = UInt64(limits.cancellationCheckInterval)
        try checkCancellation()
    }

    func consume(_ amount: UInt64 = 1) throws {
        let (next, overflow) = consumed.addingReportingOverflow(amount)
        guard !overflow, next <= maximum else {
            throw VerificationEvidenceLedgerError.workLimitExceeded(maximum: maximum)
        }
        var remaining = amount
        while remaining >= workUntilCancellationCheck {
            consumed += workUntilCancellationCheck
            remaining -= workUntilCancellationCheck
            try checkCancellation()
            workUntilCancellationCheck = cancellationCheckInterval
        }
        consumed += remaining
        workUntilCancellationCheck -= remaining
    }

    func consumeString(_ value: String, field: String) throws {
        let count = value.utf8.prefix(maximumStringUTF8Bytes + 1).count
        try consume(UInt64(count))
        guard count <= maximumStringUTF8Bytes else {
            throw VerificationEvidenceLedgerError.stringTooLarge(
                field: field,
                maximumUTF8Bytes: maximumStringUTF8Bytes
            )
        }
        guard consumedStringUTF8Bytes <= maximumTotalStringUTF8Bytes - count else {
            throw VerificationEvidenceLedgerError.totalStringsTooLarge(
                maximumUTF8Bytes: maximumTotalStringUTF8Bytes
            )
        }
        consumedStringUTF8Bytes += count
    }

    func retainMemory(_ count: Int) throws {
        guard count <= maximumRetainedBytes,
            retainedBytes <= maximumRetainedBytes - count
        else {
            throw VerificationEvidenceLedgerError.archiveTooLarge(
                maximumBytes: maximumRetainedBytes
            )
        }
        retainedBytes += count
    }

    func releaseMemory(_ count: Int) {
        precondition(count <= retainedBytes)
        retainedBytes -= count
    }

    func checkCancellation() throws {
        if cancellationCheck() { throw VerificationEvidenceLedgerError.cancelled }
    }

    func finish() throws {
        try checkCancellation()
    }
}

private struct VerificationEvidenceStringBudget {
    let budget: VerificationEvidenceWorkBudget

    func consume(_ value: String, field: String) throws {
        try budget.consumeString(value, field: field)
    }
}

private func verificationEvidencePrepareAudit(
    manifest: VerificationRoadmapManifest,
    ledger: VerificationEvidenceLedger,
    trustPolicy: VerificationEvidenceTrustPolicy,
    trustRootIndex: VerificationEvidenceTrustRootIndex,
    submitterID: VerificationEvidencePrincipalID,
    trustedVerificationTimeUnixMilliseconds: UInt64,
    limits: VerificationEvidenceLedgerLimits,
    budget: VerificationEvidenceWorkBudget,
    canonicalInputs: VerificationEvidenceCanonicalInputs? = nil
) throws -> VerificationEvidencePreparedAudit {
    let canonicalInputs =
        try canonicalInputs
        ?? verificationEvidenceMeasureCanonicalInputs(
            manifest: manifest,
            ledger: ledger,
            trustPolicy: trustPolicy,
            limits: limits,
            budget: budget
        )
    var context = VerificationEvidenceAuditContext(
        manifest: manifest,
        ledger: ledger,
        trustPolicy: trustPolicy,
        trustRootIndex: trustRootIndex,
        submitterID: submitterID,
        trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
        limits: limits,
        budget: budget
    )
    let report = try context.run()
    let (reportByteCount, reportDigest) = try verificationEvidenceMeasureCanonicalSection(
        limits: limits,
        budget: budget
    ) { writer in
        try VerificationEvidenceCanonicalEncoder.report(
            report,
            limits: limits,
            budget: budget,
            to: &writer
        )
    }
    let (_, evaluationDigest) = try verificationEvidenceMeasureCanonicalSection(
        limits: limits,
        budget: budget
    ) { writer in
        try VerificationEvidenceCanonicalEncoder.reportEvaluation(
            report,
            limits: limits,
            budget: budget,
            to: &writer
        )
    }
    let archive = try VerificationEvidenceCanonicalEncoder.archive(
        manifest: manifest,
        ledger: ledger,
        trustPolicy: trustPolicy,
        report: report,
        sectionByteCounts: [
            canonicalInputs.manifestByteCount,
            canonicalInputs.ledgerByteCount,
            canonicalInputs.trustPolicyByteCount,
            reportByteCount
        ],
        manifestDigest: canonicalInputs.manifestDigest,
        ledgerDigest: canonicalInputs.ledgerDigest,
        trustPolicyDigest: canonicalInputs.trustPolicyDigest,
        reportDigest: reportDigest,
        limits: limits,
        budget: budget
    )
    return VerificationEvidencePreparedAudit(
        manifestDigest: canonicalInputs.manifestDigest,
        ledgerDigest: canonicalInputs.ledgerDigest,
        trustPolicyDigest: canonicalInputs.trustPolicyDigest,
        report: report,
        reportDigest: reportDigest,
        evaluationDigest: evaluationDigest,
        archiveData: archive.data,
        archiveDigest: archive.sha256
    )
}

private func verificationEvidenceMeasureCanonicalInputs(
    manifest: VerificationRoadmapManifest,
    ledger: VerificationEvidenceLedger,
    trustPolicy: VerificationEvidenceTrustPolicy,
    limits: VerificationEvidenceLedgerLimits,
    budget: VerificationEvidenceWorkBudget
) throws -> VerificationEvidenceCanonicalInputs {
    let (manifestByteCount, manifestDigest) = try verificationEvidenceMeasureCanonicalSection(
        limits: limits,
        budget: budget
    ) { writer in
        try VerificationEvidenceCanonicalEncoder.manifest(
            manifest,
            limits: limits,
            budget: budget,
            to: &writer
        )
    }
    let (ledgerByteCount, ledgerDigest) = try verificationEvidenceMeasureCanonicalSection(
        limits: limits,
        budget: budget
    ) { writer in
        try VerificationEvidenceCanonicalEncoder.ledger(
            ledger,
            limits: limits,
            budget: budget,
            to: &writer
        )
    }
    let (trustPolicyByteCount, trustPolicyDigest) = try verificationEvidenceMeasureCanonicalSection(
        limits: limits,
        budget: budget
    ) { writer in
        try VerificationEvidenceCanonicalEncoder.trustPolicy(
            trustPolicy,
            limits: limits,
            budget: budget,
            to: &writer
        )
    }
    return VerificationEvidenceCanonicalInputs(
        manifestByteCount: manifestByteCount,
        manifestDigest: manifestDigest,
        ledgerByteCount: ledgerByteCount,
        ledgerDigest: ledgerDigest,
        trustPolicyByteCount: trustPolicyByteCount,
        trustPolicyDigest: trustPolicyDigest
    )
}

private func verificationEvidenceValidateAuditAttestation(
    _ attestation: VerificationEvidenceAuditAttestation,
    prepared: VerificationEvidencePreparedAudit,
    ledger: VerificationEvidenceLedger,
    trustRootIndex: VerificationEvidenceTrustRootIndex,
    trustedVerificationTimeUnixMilliseconds: UInt64,
    limits: VerificationEvidenceLedgerLimits,
    budget: VerificationEvidenceWorkBudget
) throws {
    guard
        attestation.trustedVerificationTimeUnixMilliseconds
            == trustedVerificationTimeUnixMilliseconds,
        attestation.manifestSHA256 == prepared.manifestDigest,
        attestation.ledgerSHA256 == prepared.ledgerDigest,
        attestation.trustPolicySHA256 == prepared.trustPolicyDigest,
        attestation.reportSHA256 == prepared.reportDigest,
        attestation.archiveSHA256 == prepared.archiveDigest,
        attestation.signature.count == 64
    else { throw VerificationEvidenceLedgerError.invalidAuditAttestation }
    let auditorRoot = try verificationEvidenceValidateAuditParties(
        auditorID: attestation.auditorID,
        submitterID: attestation.submitterID,
        auditedAtUnixMilliseconds: attestation.auditedAtUnixMilliseconds,
        ledger: ledger,
        trustRootIndex: trustRootIndex,
        trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
        budget: budget
    )
    var signingData = try VerificationEvidenceCanonicalEncoder.auditClaim(
        attestation,
        limits: limits,
        budget: budget
    )
    try verificationEvidenceValidateSigningPayloadSize(signingData, limits: limits)
    try budget.consume(UInt64(signingData.count + attestation.signature.count))
    try budget.checkCancellation()
    guard
        let publicKey = try? Curve25519.Signing.PublicKey(
            rawRepresentation: Data(auditorRoot.ed25519PublicKey)
        ), publicKey.isValidSignature(Data(attestation.signature), for: signingData)
    else {
        throw VerificationEvidenceLedgerError.invalidAuditAttestation
    }
    try budget.checkCancellation()
    let signingByteCount = signingData.count
    signingData = Data()
    budget.releaseMemory(signingByteCount)
}

@discardableResult
private func verificationEvidenceValidateAuditParties(
    auditorID: VerificationEvidencePrincipalID,
    submitterID: VerificationEvidencePrincipalID,
    auditedAtUnixMilliseconds: UInt64,
    ledger: VerificationEvidenceLedger,
    trustRootIndex: VerificationEvidenceTrustRootIndex,
    trustedVerificationTimeUnixMilliseconds: UInt64,
    budget: VerificationEvidenceWorkBudget
) throws -> VerificationEvidenceTrustRoot {
    guard verificationEvidenceIsValidIdentifier(auditorID.rawValue),
        verificationEvidenceIsValidIdentifier(submitterID.rawValue),
        auditorID != submitterID,
        auditedAtUnixMilliseconds <= trustedVerificationTimeUnixMilliseconds
    else { throw VerificationEvidenceLedgerError.invalidAuditAttestation }
    let auditorRoots = try trustRootIndex.matchingRoots(
        principalID: auditorID,
        role: .auditor,
        signedAt: auditedAtUnixMilliseconds,
        verifiedAt: trustedVerificationTimeUnixMilliseconds,
        budget: budget
    )
    let submitterRoots = try trustRootIndex.matchingRoots(
        principalID: submitterID,
        role: .submitter,
        signedAt: auditedAtUnixMilliseconds,
        verifiedAt: trustedVerificationTimeUnixMilliseconds,
        budget: budget
    )
    guard auditorRoots.count == 1,
        submitterRoots.count == 1,
        auditorRoots[0].ed25519PublicKey != submitterRoots[0].ed25519PublicKey
    else { throw VerificationEvidenceLedgerError.invalidAuditAttestation }
    var evidencePrincipals = Set<VerificationEvidencePrincipalID>()
    for citation in ledger.citations {
        try budget.consume()
        evidencePrincipals.insert(citation.collectorAttestation.collectorID)
        for review in citation.reviews {
            try budget.consume()
            evidencePrincipals.insert(review.reviewerID)
        }
    }
    let evidenceKeys = try trustRootIndex.evidenceKeys(for: evidencePrincipals, budget: budget)
    guard !evidencePrincipals.contains(auditorID),
        !evidenceKeys.contains(auditorRoots[0].ed25519PublicKey)
    else { throw VerificationEvidenceLedgerError.invalidAuditAttestation }
    return auditorRoots[0]
}

private func verificationEvidenceValidateCurrentAuditAuthority(
    _ attestation: VerificationEvidenceAuditAttestation,
    ledger: VerificationEvidenceLedger,
    trustRootIndex: VerificationEvidenceTrustRootIndex,
    trustedVerificationTimeUnixMilliseconds: UInt64,
    limits: VerificationEvidenceLedgerLimits,
    budget: VerificationEvidenceWorkBudget
) throws {
    guard
        trustedVerificationTimeUnixMilliseconds
            >= attestation.trustedVerificationTimeUnixMilliseconds,
        attestation.signature.count == 64
    else { throw VerificationEvidenceLedgerError.invalidAuditAttestation }
    let auditorRoot = try verificationEvidenceValidateAuditParties(
        auditorID: attestation.auditorID,
        submitterID: attestation.submitterID,
        auditedAtUnixMilliseconds: attestation.auditedAtUnixMilliseconds,
        ledger: ledger,
        trustRootIndex: trustRootIndex,
        trustedVerificationTimeUnixMilliseconds: trustedVerificationTimeUnixMilliseconds,
        budget: budget
    )
    var signingData = try VerificationEvidenceCanonicalEncoder.auditClaim(
        attestation,
        limits: limits,
        budget: budget
    )
    try verificationEvidenceValidateSigningPayloadSize(signingData, limits: limits)
    try budget.consume(UInt64(signingData.count + attestation.signature.count))
    try budget.checkCancellation()
    guard
        let publicKey = try? Curve25519.Signing.PublicKey(
            rawRepresentation: Data(auditorRoot.ed25519PublicKey)
        ), publicKey.isValidSignature(Data(attestation.signature), for: signingData)
    else {
        throw VerificationEvidenceLedgerError.invalidAuditAttestation
    }
    try budget.checkCancellation()
    let signingByteCount = signingData.count
    signingData = Data()
    budget.releaseMemory(signingByteCount)
}

private func verificationEvidenceValidateSigningPayloadSize(
    _ data: Data,
    limits: VerificationEvidenceLedgerLimits
) throws {
    guard data.count <= limits.maximumSigningPayloadBytes else {
        throw VerificationEvidenceLedgerError.signingPayloadTooLarge(
            maximumBytes: limits.maximumSigningPayloadBytes
        )
    }
}

private func verificationEvidenceSHA256(
    _ data: Data,
    budget: VerificationEvidenceWorkBudget
) throws -> VerificationEvidenceDigest {
    var hasher = SHA256()
    let chunkSize = 64 * 1_024
    var offset = 0
    while offset < data.count {
        let end = min(offset + chunkSize, data.count)
        try budget.consume(UInt64(end - offset))
        hasher.update(data: data[offset..<end])
        offset = end
    }
    try budget.checkCancellation()
    return VerificationEvidenceDigest(bytes: Array(hasher.finalize()))
}

private func verificationEvidenceMeasureCanonicalSection(
    limits: VerificationEvidenceLedgerLimits,
    budget: VerificationEvidenceWorkBudget,
    encode: (inout VerificationEvidenceWriter) throws -> Void
) throws -> (Int, VerificationEvidenceDigest) {
    let hasher = VerificationEvidenceStreamingSHA256()
    var writer = VerificationEvidenceWriter(
        limits: limits,
        budget: budget,
        storesData: false,
        hashers: [hasher]
    )
    try encode(&writer)
    try budget.checkCancellation()
    return (writer.count, hasher.finalize())
}

private func verificationEvidenceDataPrecedes(
    _ left: Data,
    _ right: Data,
    budget: VerificationEvidenceWorkBudget
) throws -> Bool {
    let commonCount = min(left.count, right.count)
    for index in 0..<commonCount {
        try budget.consume()
        let leftByte = left[left.startIndex + index]
        let rightByte = right[right.startIndex + index]
        if leftByte != rightByte { return leftByte < rightByte }
    }
    return left.count < right.count
}

private func verificationEvidenceStartDomainSHA256(
    _ hasher: VerificationEvidenceStreamingSHA256,
    domain: String,
    dataCount: Int,
    limits: VerificationEvidenceLedgerLimits,
    budget: VerificationEvidenceWorkBudget
) throws {
    try budget.consumeString(domain, field: "canonical.string")
    let domainData = Data(domain.utf8)
    guard domainData.count <= limits.maximumStringUTF8Bytes else {
        throw VerificationEvidenceLedgerError.stringTooLarge(
            field: "canonical.string",
            maximumUTF8Bytes: limits.maximumStringUTF8Bytes
        )
    }
    guard let domainCount = UInt32(exactly: domainData.count),
        let framedDataCount = UInt32(exactly: dataCount)
    else { throw VerificationEvidenceLedgerError.integerOverflow }
    let framedByteCount = try verificationEvidenceCheckedAdd(
        try verificationEvidenceCheckedAdd(domainData.count, dataCount),
        8
    )
    guard framedByteCount <= limits.maximumArchiveBytes else {
        throw VerificationEvidenceLedgerError.archiveTooLarge(
            maximumBytes: limits.maximumArchiveBytes
        )
    }
    let domainCountData = verificationEvidenceLittleEndianData(domainCount)
    let dataCountData = verificationEvidenceLittleEndianData(framedDataCount)
    for framing in [domainCountData, domainData, dataCountData] {
        try budget.consume(UInt64(framing.count))
        hasher.update(framing)
    }
}

private func verificationEvidenceLittleEndianData(_ value: UInt32) -> Data {
    Data((0..<4).map { UInt8((value >> UInt32($0 * 8)) & 0xff) })
}

private func verificationEvidenceBuildIsStructurallyValid(
    _ build: VerificationEvidenceAppBuildProvenance
) -> Bool {
    verificationEvidenceIsValidIdentifier(build.application.id.rawValue)
        && verificationEvidenceIsValidIdentifier(build.build.id.rawValue)
        && build.applicationBundle.role == .applicationBundle
        && build.executable.role == .executable
        && build.signingIdentity.role == .signingIdentity
        && verificationEvidenceArtifactIsStructurallyValid(build.applicationBundle)
        && verificationEvidenceArtifactIsStructurallyValid(build.executable)
        && verificationEvidenceArtifactIsStructurallyValid(build.signingIdentity)
}

private func verificationEvidenceArtifactIsStructurallyValid(
    _ artifact: VerificationEvidenceArtifactReference
) -> Bool {
    verificationEvidenceIsValidIdentifier(artifact.id.rawValue)
        && !artifact.mediaType.isEmpty
        && artifact.mediaType == artifact.mediaType.precomposedStringWithCanonicalMapping
        && !artifact.mediaType.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f })
        && artifact.byteCount > 0
        && verificationEvidenceDigestIsValid(artifact.digest)
}

private func verificationEvidenceDigestIsValid(_ digest: VerificationEvidenceDigest) -> Bool {
    digest.algorithm == .sha256 && digest.bytes.count == SHA256.byteCount
}

private func verificationEvidenceTrustRootIsStructurallyValid(
    _ root: VerificationEvidenceTrustRoot
) -> Bool {
    verificationEvidenceIsValidIdentifier(root.principalID.rawValue)
        && !root.roles.isEmpty
        && root.ed25519PublicKey.count == 32
        && root.validFromUnixMilliseconds <= root.validThroughUnixMilliseconds
        && (root.revokedAtUnixMilliseconds.map { $0 >= root.validFromUnixMilliseconds } ?? true)
}

private func verificationEvidenceRequiredAttachmentKind(
    _ kind: VerificationEvidenceKind
) -> VerificationEvidenceAttachmentKind {
    switch kind {
    case .modelOrUnit: .modelOrUnitRecord
    case .uiInteraction: .uiInteractionRecord
    case .semanticAccessibility: .semanticAccessibilityRecord
    case .persistence: .persistenceRecord
    case .packagedAppSmoke: .packagedAppSmokeRecord
    }
}

private func verificationEvidenceIsPrimaryAttachmentKind(
    _ kind: VerificationEvidenceAttachmentKind
) -> Bool {
    switch kind {
    case .modelOrUnitRecord, .uiInteractionRecord, .semanticAccessibilityRecord,
        .persistenceRecord, .packagedAppSmokeRecord:
        true
    case .screenshot, .video, .transcript, .log:
        false
    }
}

private func verificationEvidenceIsValidIdentifier(_ value: String) -> Bool {
    !value.isEmpty
        && value == value.precomposedStringWithCanonicalMapping
        && !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f })
}

private func verificationEvidenceSortedFindings(
    _ findings: [VerificationEvidenceFinding],
    budget: VerificationEvidenceWorkBudget
) throws -> [VerificationEvidenceFinding] {
    try verificationEvidenceStableSorted(findings, budget: budget) { left, right in
        try budget.consume(
            UInt64(left.id.rawValue.utf8.count + right.id.rawValue.utf8.count + 64)
        )
        if left.severity != right.severity {
            return verificationEvidenceEnumRank(left.severity)
                > verificationEvidenceEnumRank(right.severity)
        }
        if left.code != right.code {
            return verificationEvidenceCompareUTF8(left.code.rawValue, right.code.rawValue) < 0
        }
        return left.id < right.id
    }
}

private func verificationEvidenceFindingID(
    code: VerificationEvidenceFindingCode,
    subject: VerificationEvidenceFindingSubject,
    discriminator: String,
    budget: VerificationEvidenceWorkBudget
) throws -> VerificationEvidenceFinding.ID {
    let components = [code.rawValue] + subject.identityComponents + [discriminator]
    var hasher = SHA256()
    for component in components {
        let frame = verificationEvidenceFrame(component)
        var iterator = frame.utf8.makeIterator()
        var chunk: [UInt8] = []
        chunk.reserveCapacity(4_096)
        while let byte = iterator.next() {
            chunk.append(byte)
            if chunk.count == 4_096 {
                try budget.consume(UInt64(chunk.count))
                hasher.update(data: Data(chunk))
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            try budget.consume(UInt64(chunk.count))
            hasher.update(data: Data(chunk))
        }
    }
    try budget.checkCancellation()
    return VerificationEvidenceFinding.ID(
        rawValue: hasher.finalize().map { String(format: "%02x", $0) }.joined()
    )
}

private func verificationEvidenceStableSorted<Value>(
    _ values: [Value],
    budget: VerificationEvidenceWorkBudget,
    by areInIncreasingOrder: (Value, Value) throws -> Bool
) throws -> [Value] {
    guard values.count > 1 else { return values }
    var source = values
    var destination = values
    var width = 1
    while width < source.count {
        var start = 0
        while start < source.count {
            let middle = min(start + width, source.count)
            let end = min(middle + width, source.count)
            var left = start
            var right = middle
            var output = start
            while left < middle, right < end {
                try budget.consume()
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
                try budget.consume()
                destination[output] = source[left]
                left += 1
                output += 1
            }
            while right < end {
                try budget.consume()
                destination[output] = source[right]
                right += 1
                output += 1
            }
            start = end
        }
        swap(&source, &destination)
        let (nextWidth, overflow) = width.multipliedReportingOverflow(by: 2)
        guard !overflow else { throw VerificationEvidenceLedgerError.integerOverflow }
        width = nextWidth
    }
    return source
}

private func verificationEvidenceCheckedAdd(_ left: Int, _ right: Int) throws -> Int {
    let (result, overflow) = left.addingReportingOverflow(right)
    guard !overflow else { throw VerificationEvidenceLedgerError.integerOverflow }
    return result
}

private func verificationEvidenceCompareUTF8(_ left: String, _ right: String) -> Int {
    let leftBytes = Array(left.utf8)
    let rightBytes = Array(right.utf8)
    for index in 0..<min(leftBytes.count, rightBytes.count) {
        if leftBytes[index] != rightBytes[index] {
            return leftBytes[index] < rightBytes[index] ? -1 : 1
        }
    }
    if leftBytes.count == rightBytes.count { return 0 }
    return leftBytes.count < rightBytes.count ? -1 : 1
}

private func verificationEvidenceFrame(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
}

private func verificationEvidenceEnumRank<Value: CaseIterable & Equatable>(_ value: Value) -> Int {
    for (index, candidate) in Value.allCases.enumerated() where candidate == value {
        return index
    }
    return Int.max
}

private func verificationEvidenceFindingMessage(_ code: VerificationEvidenceFindingCode) -> String {
    switch code {
    case .invalidManifest: "Roadmap manifest semantics are invalid; submitted values are redacted."
    case .invalidLedger: "Evidence ledger structure is invalid; submitted values are redacted."
    case .invalidTrustPolicy: "Evidence trust policy is invalid; key material is redacted."
    case .manifestMismatch: "Evidence ledger targets another exact roadmap manifest revision."
    case .buildMismatch: "Evidence targets another exact application or build artifact set."
    case .duplicateRoadmapRow: "Roadmap manifest repeats a stable row identity."
    case .duplicateCitationID: "Evidence ledger repeats a stable citation identity."
    case .duplicateEvidenceKind: "Completed row has more than one citation for one required evidence kind."
    case .duplicateAttachmentReference: "Citation repeats an attachment identity."
    case .duplicateReview: "Citation has duplicate or ambiguous reviewer attestations."
    case .missingEvidence: "Completed row lacks a required evidence kind."
    case .unexpectedEvidence: "Evidence cites an unknown, incomplete, or not-applicable row."
    case .unexpectedEvidenceKind: "Citation supplies evidence not required by row applicability."
    case .rowRevisionMismatch: "Citation targets another exact roadmap row revision."
    case .testRunMismatch: "Citation test-run provenance is unsuccessful or internally inconsistent."
    case .artifactProvenanceMismatch: "Citation artifact provenance is incomplete or inconsistent."
    case .invalidAttachmentReference: "Citation attachment reference or SHA-256 digest is invalid."
    case .requiredAttachmentRecordMissing: "Citation lacks its required kind-specific attachment record."
    case .assertedEvidence: "Caller assertion cannot satisfy measured evidence requirements."
    case .unsuccessfulEvidence: "Citation does not report a passing measured outcome."
    case .expiredEvidence: "Citation or review attestation has expired."
    case .staleEvidence: "Citation exceeds configured evidence freshness."
    case .futureDatedEvidence: "Citation contains a timestamp later than audit time."
    case .invalidCollectorProvenance: "Collector provenance timestamps are invalid."
    case .untrustedCollector: "Citation lacks one currently trusted collector root."
    case .invalidCollectorSignature: "Collector signature does not validate canonical evidence data."
    case .missingReviewer: "Citation lacks independent trusted reviewer provenance."
    case .invalidReviewerProvenance: "Reviewer provenance timestamps are invalid."
    case .untrustedReviewer: "Citation lacks one currently trusted reviewer root."
    case .invalidReviewerSignature: "Reviewer signature does not validate canonical review data."
    case .reviewDigestMismatch: "Review does not bind the exact canonical collector claim digest."
    case .rejectedReview: "Reviewer did not accept the cited evidence."
    case .selfAttestation: "Submitter, collector, and reviewer must be independent principals."
    }
}
