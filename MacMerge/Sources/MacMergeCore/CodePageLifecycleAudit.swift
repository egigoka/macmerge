import CryptoKit
import Foundation

/// Bounded, UI-independent planning and evidence audit for legacy code-page lifecycles.
///
/// This type never invokes `TextFileCodec`, comparison engines, or filesystem APIs. Executors run
/// the requested lifecycle elsewhere and return signed measurements. Caller assertions and
/// unverifiable mapping tables remain findings, never measured coverage.
public enum CodePageLifecycleAudit: Sendable {
    public typealias CancellationCheck = @Sendable () -> Bool

    public static let reportFormatVersion = 4
    public static let maximumIdentifierUTF8Bytes = 256
    /// UTF-8 can appear in automatic detection outcomes but is not a legacy lifecycle code page.
    public static let utf8DetectionCodePage = CodePageID(rawValue: 65_001)
    public static let unicodeHashContract =
        "SHA-256 over Unicode scalar values encoded as unsigned 32-bit big-endian integers"
    public static let unicodeScalarEditContract =
        "Maximal unchanged scalar prefix, removed scalars, inserted scalars, and maximal unchanged scalar suffix; each sequence is count-framed and each scalar is unsigned 32-bit big-endian"
    public static let signingPrehashContract =
        "Curve25519.Signing signature over a 32-byte SHA-256 digest of domain-separated canonical V3 payload bytes"
    public static let executionBuildHashContract =
        "ExecutionLineage.buildSHA256 is SHA-256 over the exact executor build artifact containing the ComparisonSessionState implementation used for measurement"

    public struct StableID: RawRepresentable, Comparable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            compareUTF8(left.rawValue, right.rawValue) < 0
        }

        public static func == (left: Self, right: Self) -> Bool {
            byteExactStringEqual(left.rawValue, right.rawValue)
        }

        public func hash(into hasher: inout Hasher) {
            for byte in rawValue.utf8 { hasher.combine(byte) }
            hasher.combine(rawValue.utf8.count)
        }

        public var description: String { "CodePageLifecycleAudit.StableID(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["rawValue": "<redacted>"], displayStyle: .struct)
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

        public var description: String {
            "CodePageLifecycleAudit.RevisionReference(revision: \(revision), id: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["revision": revision, "id": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public struct SHA256Digest: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public static let byteCount = SHA256.Digest.byteCount
        public let bytes: [UInt8]

        public init(bytes: [UInt8]) throws {
            guard bytes.count == Self.byteCount else {
                throw AuditError.invalidDigestLength
            }
            self.bytes = bytes
        }

        fileprivate init(validatedBytes: [UInt8]) {
            bytes = validatedBytes
        }

        public var description: String { "CodePageLifecycleAudit.SHA256Digest(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["bytes": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct CodePageID: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    /// Legacy encodings currently represented by both `TextFileCodec` and session encoding state.
    public enum SupportedCodePage: Int, CaseIterable, Comparable, Hashable, Sendable {
        case cp932 = 932
        case cp1250 = 1250
        case cp1251 = 1251
        case cp1252 = 1252
        case cp1253 = 1253
        case cp1254 = 1254
        case cp1255 = 1255
        case cp50220 = 50220
        case cp51932 = 51932

        public var id: CodePageID { CodePageID(rawValue: rawValue) }

        public var textFileEncoding: TextFileEncoding {
            switch self {
            case .cp932: .shiftJIS
            case .cp1250: .windows1250
            case .cp1251: .windows1251
            case .cp1252: .windows1252
            case .cp1253: .windows1253
            case .cp1254: .windows1254
            case .cp1255: .windows1255
            case .cp50220: .iso2022JP
            case .cp51932: .japaneseEUC
            }
        }

        public var sessionEncoding: ComparisonSessionState.FileEncoding {
            switch self {
            case .cp932: .shiftJIS
            case .cp1250: .windows1250
            case .cp1251: .windows1251
            case .cp1252: .windows1252
            case .cp1253: .windows1253
            case .cp1254: .windows1254
            case .cp1255: .windows1255
            case .cp50220: .iso2022JP
            case .cp51932: .japaneseEUC
            }
        }

        /// Number of defined source-sequence-to-Unicode mappings in this codec's canonical table.
        public var expectedMappingCardinality: Int {
            switch self {
            case .cp932: 7_915
            case .cp1250: 251
            case .cp1251: 255
            case .cp1252: 251
            case .cp1253: 239
            case .cp1254: 249
            case .cp1255: 233
            case .cp50220: 7_007
            case .cp51932: 7_070
            }
        }

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public struct CodecSessionMapping: Comparable, Hashable, Sendable {
        public let codePage: CodePageID
        public let codecEncodingIdentifier: String
        public let sessionEncodingIdentifier: String

        public init(
            codePage: CodePageID,
            codecEncodingIdentifier: String,
            sessionEncodingIdentifier: String
        ) {
            self.codePage = codePage
            self.codecEncodingIdentifier = codecEncodingIdentifier
            self.sessionEncodingIdentifier = sessionEncodingIdentifier
        }

        public static func < (left: Self, right: Self) -> Bool {
            if left.codePage != right.codePage { return left.codePage < right.codePage }
            let codecOrder = compareUTF8(
                left.codecEncodingIdentifier,
                right.codecEncodingIdentifier
            )
            if codecOrder != 0 { return codecOrder < 0 }
            return compareUTF8(
                left.sessionEncodingIdentifier,
                right.sessionEncodingIdentifier
            ) < 0
        }

        public static func == (left: Self, right: Self) -> Bool {
            left.codePage == right.codePage
                && byteExactStringEqual(
                    left.codecEncodingIdentifier,
                    right.codecEncodingIdentifier
                )
                && byteExactStringEqual(
                    left.sessionEncodingIdentifier,
                    right.sessionEncodingIdentifier
                )
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(codePage)
            for byte in codecEncodingIdentifier.utf8 { hasher.combine(byte) }
            hasher.combine(codecEncodingIdentifier.utf8.count)
            for byte in sessionEncodingIdentifier.utf8 { hasher.combine(byte) }
            hasher.combine(sessionEncodingIdentifier.utf8.count)
        }
    }

    public static let canonicalCodecSessionMappings = SupportedCodePage.allCases.map {
        CodecSessionMapping(
            codePage: $0.id,
            codecEncodingIdentifier: $0.textFileEncoding.rawValue,
            sessionEncodingIdentifier: $0.sessionEncoding.rawValue
        )
    }

    public struct ByteHash: Hashable, Sendable {
        public let byteCount: Int
        public let sha256: SHA256Digest

        public init(byteCount: Int, sha256: SHA256Digest) {
            self.byteCount = byteCount
            self.sha256 = sha256
        }
    }

    public struct UnicodeHash: Hashable, Sendable {
        public let scalarCount: Int
        public let sha256: SHA256Digest

        public init(scalarCount: Int, sha256: SHA256Digest) {
            self.scalarCount = scalarCount
            self.sha256 = sha256
        }
    }

    /// Canonical preimage for one contiguous Unicode scalar edit.
    public struct UnicodeScalarEdit: Hashable, Sendable {
        public let unchangedPrefix: [UInt32]
        public let removedScalars: [UInt32]
        public let insertedScalars: [UInt32]
        public let unchangedSuffix: [UInt32]

        public init(
            unchangedPrefix: [UInt32],
            removedScalars: [UInt32],
            insertedScalars: [UInt32],
            unchangedSuffix: [UInt32]
        ) {
            self.unchangedPrefix = unchangedPrefix
            self.removedScalars = removedScalars
            self.insertedScalars = insertedScalars
            self.unchangedSuffix = unchangedSuffix
        }
    }

    /// Exact bytes and exact Unicode scalar sequence for one lifecycle materialization.
    public struct ContentHash: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let bytes: ByteHash
        public let unicode: UnicodeHash

        public init(bytes: ByteHash, unicode: UnicodeHash) {
            self.bytes = bytes
            self.unicode = unicode
        }

        public var description: String {
            "CodePageLifecycleAudit.ContentHash(bytes: \(bytes.byteCount), scalars: \(unicode.scalarCount), digests: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "byteCount": bytes.byteCount,
                    "scalarCount": unicode.scalarCount,
                    "digests": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum DetectionOutcome: Hashable, Sendable {
        case selected(CodePageID)
        case ambiguous([CodePageID])
        case rejected
    }

    public struct SelectionExpectation: Hashable, Sendable {
        public let automaticDetection: DetectionOutcome
        public let explicitSelection: CodePageID

        public init(
            automaticDetection: DetectionOutcome,
            explicitSelection: CodePageID
        ) {
            self.automaticDetection = automaticDetection
            self.explicitSelection = explicitSelection
        }

        public var requiresExplicitSelection: Bool {
            if case .ambiguous = automaticDetection { true } else { false }
        }
    }

    public struct FixtureExpectation: Hashable, Sendable {
        public let original: ContentHash
        public let edited: ContentHash
        public let saved: ContentHash
        public let reloaded: ContentHash
        public let selection: SelectionExpectation
        public let intendedEdit: UnicodeScalarEdit

        public init(
            original: ContentHash,
            edited: ContentHash,
            saved: ContentHash,
            reloaded: ContentHash,
            selection: SelectionExpectation,
            intendedEdit: UnicodeScalarEdit
        ) {
            self.original = original
            self.edited = edited
            self.saved = saved
            self.reloaded = reloaded
            self.selection = selection
            self.intendedEdit = intendedEdit
        }
    }

    public struct FixtureScalarCommitments: Hashable, Sendable {
        public let original: UnicodeHash
        public let edited: UnicodeHash
        public let saved: UnicodeHash
        public let reloaded: UnicodeHash

        public init(
            original: UnicodeHash,
            edited: UnicodeHash,
            saved: UnicodeHash,
            reloaded: UnicodeHash
        ) {
            self.original = original
            self.edited = edited
            self.saved = saved
            self.reloaded = reloaded
        }

        public init(expectation: FixtureExpectation) {
            original = expectation.original.unicode
            edited = expectation.edited.unicode
            saved = expectation.saved.unicode
            reloaded = expectation.reloaded.unicode
        }
    }

    public struct Signature: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let signerID: StableID
        public let bytes: [UInt8]

        public init(signerID: StableID, bytes: [UInt8]) {
            self.signerID = signerID
            self.bytes = bytes
        }

        public var description: String {
            "CodePageLifecycleAudit.Signature(signer: <redacted>, bytes: \(bytes.count))"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["signer": "<redacted>", "byteCount": bytes.count],
                displayStyle: .struct
            )
        }
    }

    /// Independent mapping-table provenance. Signature also covers the bound fixture artifact and
    /// complete expectation, including byte outputs, scalar commitments, selection, and edit.
    public struct MappingOracle: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let reference: RevisionReference
        public let codePage: CodePageID
        public let sourceIdentifier: String
        public let sourceArtifactSHA256: SHA256Digest
        public let mappingTableSHA256: SHA256Digest
        public let mappingCardinality: Int
        public let fixtureScalarCommitments: FixtureScalarCommitments
        public let signature: Signature

        public init(
            reference: RevisionReference,
            codePage: CodePageID,
            sourceIdentifier: String,
            sourceArtifactSHA256: SHA256Digest,
            mappingTableSHA256: SHA256Digest,
            mappingCardinality: Int,
            fixtureScalarCommitments: FixtureScalarCommitments,
            signature: Signature
        ) {
            self.reference = reference
            self.codePage = codePage
            self.sourceIdentifier = sourceIdentifier
            self.sourceArtifactSHA256 = sourceArtifactSHA256
            self.mappingTableSHA256 = mappingTableSHA256
            self.mappingCardinality = mappingCardinality
            self.fixtureScalarCommitments = fixtureScalarCommitments
            self.signature = signature
        }

        public var description: String {
            "CodePageLifecycleAudit.MappingOracle(codePage: \(codePage.rawValue), provenance: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["codePage": codePage.rawValue, "provenance": "<redacted>"],
                displayStyle: .struct
            )
        }

        public static func == (left: Self, right: Self) -> Bool {
            left.reference == right.reference
                && left.codePage == right.codePage
                && byteExactStringEqual(left.sourceIdentifier, right.sourceIdentifier)
                && left.sourceArtifactSHA256 == right.sourceArtifactSHA256
                && left.mappingTableSHA256 == right.mappingTableSHA256
                && left.mappingCardinality == right.mappingCardinality
                && left.fixtureScalarCommitments == right.fixtureScalarCommitments
                && left.signature == right.signature
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(reference)
            hasher.combine(codePage)
            for byte in sourceIdentifier.utf8 { hasher.combine(byte) }
            hasher.combine(sourceIdentifier.utf8.count)
            hasher.combine(sourceArtifactSHA256)
            hasher.combine(mappingTableSHA256)
            hasher.combine(mappingCardinality)
            hasher.combine(fixtureScalarCommitments)
            hasher.combine(signature)
        }
    }

    public struct Fixture: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let reference: RevisionReference
        public let codePage: CodePageID
        public let fixtureArtifactSHA256: SHA256Digest
        public let mappingOracle: MappingOracle
        public let expectation: FixtureExpectation

        public init(
            reference: RevisionReference,
            codePage: CodePageID,
            fixtureArtifactSHA256: SHA256Digest,
            mappingOracle: MappingOracle,
            expectation: FixtureExpectation
        ) {
            self.reference = reference
            self.codePage = codePage
            self.fixtureArtifactSHA256 = fixtureArtifactSHA256
            self.mappingOracle = mappingOracle
            self.expectation = expectation
        }

        public var description: String {
            "CodePageLifecycleAudit.Fixture(codePage: \(codePage.rawValue), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["codePage": codePage.rawValue, "contents": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    /// Manifest binds codec/session support claims, fixtures, expectations, and mapping oracles.
    public struct Manifest: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let reference: RevisionReference
        public let codec: RevisionReference
        public let codecArtifactSHA256: SHA256Digest
        public let sessionEncodingSchemaVersion: Int
        public let declaredSupportedCodePages: [CodePageID]
        public let codecSessionMappings: [CodecSessionMapping]
        public let approvedExecutionLineages: [ExecutionLineage]
        public let fixtures: [Fixture]

        public init(
            reference: RevisionReference,
            codec: RevisionReference,
            codecArtifactSHA256: SHA256Digest,
            sessionEncodingSchemaVersion: Int = ComparisonSessionState.currentSchemaVersion,
            declaredSupportedCodePages: [CodePageID] = SupportedCodePage.allCases.map(\.id),
            codecSessionMappings: [CodecSessionMapping] = canonicalCodecSessionMappings,
            approvedExecutionLineages: [ExecutionLineage],
            fixtures: [Fixture]
        ) {
            self.reference = reference
            self.codec = codec
            self.codecArtifactSHA256 = codecArtifactSHA256
            self.sessionEncodingSchemaVersion = sessionEncodingSchemaVersion
            self.declaredSupportedCodePages = declaredSupportedCodePages
            self.codecSessionMappings = codecSessionMappings
            self.approvedExecutionLineages = approvedExecutionLineages
            self.fixtures = fixtures
        }

        public var description: String {
            "CodePageLifecycleAudit.Manifest(revision: \(reference.revision), fixtures: \(fixtures.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "revision": reference.revision,
                    "fixtureCount": fixtures.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct TrustedSigner: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let id: StableID
        /// Curve25519 signing public key raw representation.
        public let publicKey: [UInt8]

        public init(id: StableID, publicKey: [UInt8]) {
            self.id = id
            self.publicKey = publicKey
        }

        public var description: String { "CodePageLifecycleAudit.TrustedSigner(<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["signer": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct CodecArtifactIdentity: Hashable, Sendable {
        public let codec: RevisionReference
        public let artifactSHA256: SHA256Digest

        public init(codec: RevisionReference, artifactSHA256: SHA256Digest) {
            self.codec = codec
            self.artifactSHA256 = artifactSHA256
        }
    }

    public struct TrustPolicy: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let approvedCodecArtifact: CodecArtifactIdentity
        public let mappingOracleSigners: [TrustedSigner]
        public let measurementSigners: [TrustedSigner]

        public init(
            approvedCodecArtifact: CodecArtifactIdentity,
            mappingOracleSigners: [TrustedSigner],
            measurementSigners: [TrustedSigner]
        ) {
            self.approvedCodecArtifact = approvedCodecArtifact
            self.mappingOracleSigners = mappingOracleSigners
            self.measurementSigners = measurementSigners
        }

        public var description: String {
            "CodePageLifecycleAudit.TrustPolicy(oracleSigners: \(mappingOracleSigners.count), measurementSigners: \(measurementSigners.count), keys: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "oracleSignerCount": mappingOracleSigners.count,
                    "measurementSignerCount": measurementSigners.count,
                    "keys": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct ExecutionLineage: Comparable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let executor: RevisionReference
        /// Digest of the exact build artifact containing the session implementation used by the run.
        public let buildSHA256: SHA256Digest
        public let signerID: StableID

        public init(
            executor: RevisionReference,
            buildSHA256: SHA256Digest,
            signerID: StableID
        ) {
            self.executor = executor
            self.buildSHA256 = buildSHA256
            self.signerID = signerID
        }

        public var description: String {
            "CodePageLifecycleAudit.ExecutionLineage(executorRevision: \(executor.revision), identity: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["executorRevision": executor.revision, "identity": "<redacted>"],
                displayStyle: .struct
            )
        }

        public static func < (left: Self, right: Self) -> Bool {
            if left.executor != right.executor { return left.executor < right.executor }
            let buildOrder = compareBytes(left.buildSHA256.bytes, right.buildSHA256.bytes)
            if buildOrder != 0 { return buildOrder < 0 }
            return left.signerID < right.signerID
        }
    }

    public enum Stage: Int, CaseIterable, Comparable, Hashable, Sendable {
        case load
        case compare
        case edit
        case save
        case reload
        case byteComparison

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public struct StageRequest: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let ordinal: Int
        public let fixture: RevisionReference
        public let codePage: CodePageID
        public let stage: Stage
        public let manifest: RevisionReference
        public let manifestSHA256: SHA256Digest
        public let fixtureSHA256: SHA256Digest
        public let mappingOracleSHA256: SHA256Digest
        public let requestSHA256: SHA256Digest

        fileprivate init(
            ordinal: Int,
            fixture: RevisionReference,
            codePage: CodePageID,
            stage: Stage,
            manifest: RevisionReference,
            manifestSHA256: SHA256Digest,
            fixtureSHA256: SHA256Digest,
            mappingOracleSHA256: SHA256Digest,
            requestSHA256: SHA256Digest
        ) {
            self.ordinal = ordinal
            self.fixture = fixture
            self.codePage = codePage
            self.stage = stage
            self.manifest = manifest
            self.manifestSHA256 = manifestSHA256
            self.fixtureSHA256 = fixtureSHA256
            self.mappingOracleSHA256 = mappingOracleSHA256
            self.requestSHA256 = requestSHA256
        }

        public var description: String {
            "CodePageLifecycleAudit.StageRequest(ordinal: \(ordinal), codePage: \(codePage.rawValue), stage: \(stage), bindings: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "ordinal": ordinal,
                    "codePage": codePage.rawValue,
                    "stage": stage,
                    "bindings": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct FixtureVerification: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let fixture: RevisionReference
        public let codePage: CodePageID
        public let mappingOracleSHA256: SHA256Digest
        public let isSupported: Bool
        public let isMappingOracleVerified: Bool
        public let isFixtureValid: Bool

        fileprivate init(
            fixture: RevisionReference,
            codePage: CodePageID,
            mappingOracleSHA256: SHA256Digest,
            isSupported: Bool,
            isMappingOracleVerified: Bool,
            isFixtureValid: Bool
        ) {
            self.fixture = fixture
            self.codePage = codePage
            self.mappingOracleSHA256 = mappingOracleSHA256
            self.isSupported = isSupported
            self.isMappingOracleVerified = isMappingOracleVerified
            self.isFixtureValid = isFixtureValid
        }

        public var description: String {
            "CodePageLifecycleAudit.FixtureVerification(codePage: \(codePage.rawValue), supported: \(isSupported), oracleVerified: \(isMappingOracleVerified), fixtureValid: \(isFixtureValid), bindings: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "codePage": codePage.rawValue,
                    "isSupported": isSupported,
                    "isMappingOracleVerified": isMappingOracleVerified,
                    "isFixtureValid": isFixtureValid,
                    "bindings": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct PlanningReceipt: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let formatVersion: Int
        public let manifest: RevisionReference
        public let manifestSHA256: SHA256Digest
        public let requestSetSHA256: SHA256Digest
        public let trustPolicySHA256: SHA256Digest
        public let requestCount: Int

        fileprivate init(
            manifest: RevisionReference,
            manifestSHA256: SHA256Digest,
            requestSetSHA256: SHA256Digest,
            trustPolicySHA256: SHA256Digest,
            requestCount: Int
        ) {
            formatVersion = reportFormatVersion
            self.manifest = manifest
            self.manifestSHA256 = manifestSHA256
            self.requestSetSHA256 = requestSetSHA256
            self.trustPolicySHA256 = trustPolicySHA256
            self.requestCount = requestCount
        }

        public var description: String {
            "CodePageLifecycleAudit.PlanningReceipt(requests: \(requestCount), digests: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["requestCount": requestCount, "digests": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public struct Plan: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let manifest: Manifest
        public let manifestSHA256: SHA256Digest
        public let requests: [StageRequest]
        public let fixtureVerifications: [FixtureVerification]
        public let preflightFindings: [Finding]
        public let receipt: PlanningReceipt
        public let workPerformed: UInt64
        public let stringUTF8BytesProcessed: Int

        fileprivate init(
            manifest: Manifest,
            manifestSHA256: SHA256Digest,
            requests: [StageRequest],
            fixtureVerifications: [FixtureVerification],
            preflightFindings: [Finding],
            receipt: PlanningReceipt,
            workPerformed: UInt64,
            stringUTF8BytesProcessed: Int
        ) {
            self.manifest = manifest
            self.manifestSHA256 = manifestSHA256
            self.requests = requests
            self.fixtureVerifications = fixtureVerifications
            self.preflightFindings = preflightFindings
            self.receipt = receipt
            self.workPerformed = workPerformed
            self.stringUTF8BytesProcessed = stringUTF8BytesProcessed
        }

        public var description: String {
            "CodePageLifecycleAudit.Plan(requests: \(requests.count), findings: \(preflightFindings.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "requestCount": requests.count,
                    "findingCount": preflightFindings.count,
                    "workPerformed": workPerformed,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct LoadObservation: Hashable, Sendable {
        public let automaticDetection: DetectionOutcome
        public let explicitlySelectedEncoding: CodePageID
        public let source: ContentHash
        public let loaded: ContentHash

        public init(
            automaticDetection: DetectionOutcome,
            explicitlySelectedEncoding: CodePageID,
            source: ContentHash,
            loaded: ContentHash
        ) {
            self.automaticDetection = automaticDetection
            self.explicitlySelectedEncoding = explicitlySelectedEncoding
            self.source = source
            self.loaded = loaded
        }
    }

    public struct CompareObservation: Hashable, Sendable {
        public let left: ContentHash
        public let right: ContentHash
        public let unicodeEqual: Bool
        public let differenceCount: Int

        public init(
            left: ContentHash,
            right: ContentHash,
            unicodeEqual: Bool,
            differenceCount: Int
        ) {
            self.left = left
            self.right = right
            self.unicodeEqual = unicodeEqual
            self.differenceCount = differenceCount
        }
    }

    public struct EditObservation: Hashable, Sendable {
        public let before: ContentHash
        public let after: ContentHash
        public let mutationApplied: Bool
        public let unicodeScalarDelta: UnicodeScalarEdit

        public init(
            before: ContentHash,
            after: ContentHash,
            mutationApplied: Bool,
            unicodeScalarDelta: UnicodeScalarEdit
        ) {
            self.before = before
            self.after = after
            self.mutationApplied = mutationApplied
            self.unicodeScalarDelta = unicodeScalarDelta
        }
    }

    public struct SaveObservation: Hashable, Sendable {
        public let edited: ContentHash
        public let saved: ContentHash
        public let selectedEncoding: CodePageID

        public init(edited: ContentHash, saved: ContentHash, selectedEncoding: CodePageID) {
            self.edited = edited
            self.saved = saved
            self.selectedEncoding = selectedEncoding
        }
    }

    public struct ReloadObservation: Hashable, Sendable {
        public let saved: ContentHash
        public let reloaded: ContentHash
        public let selectedEncoding: CodePageID

        public init(saved: ContentHash, reloaded: ContentHash, selectedEncoding: CodePageID) {
            self.saved = saved
            self.reloaded = reloaded
            self.selectedEncoding = selectedEncoding
        }
    }

    public struct ByteComparisonObservation: Hashable, Sendable {
        public let saved: ContentHash
        public let reloaded: ContentHash
        public let bytesEqual: Bool

        public init(saved: ContentHash, reloaded: ContentHash, bytesEqual: Bool) {
            self.saved = saved
            self.reloaded = reloaded
            self.bytesEqual = bytesEqual
        }
    }

    public enum Observation: Hashable, Sendable {
        case load(LoadObservation)
        case compare(CompareObservation)
        case edit(EditObservation)
        case save(SaveObservation)
        case reload(ReloadObservation)
        case byteComparison(ByteComparisonObservation)

        public var stage: Stage {
            switch self {
            case .load: .load
            case .compare: .compare
            case .edit: .edit
            case .save: .save
            case .reload: .reload
            case .byteComparison: .byteComparison
            }
        }
    }

    public enum EvidenceOrigin: String, CaseIterable, Hashable, Sendable {
        case callerAssertion
        case automatedMeasurement
        case manualMeasurement

        public var isMeasured: Bool { self != .callerAssertion }
    }

    public struct ExecutionRun: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let lineage: ExecutionLineage
        public let runSHA256: SHA256Digest

        public init(
            lineage: ExecutionLineage,
            runSHA256: SHA256Digest
        ) {
            self.lineage = lineage
            self.runSHA256 = runSHA256
        }

        public var description: String {
            "CodePageLifecycleAudit.ExecutionRun(executorRevision: \(lineage.executor.revision), identity: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["executorRevision": lineage.executor.revision, "identity": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    /// Signature binds request, observation, provenance, monotonic order, and prior evidence hash.
    public struct ExecutionAttestation: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let execution: ExecutionRun
        public let monotonicSequence: UInt64
        public let previousEvidenceSHA256: SHA256Digest?
        public let signature: Signature

        public init(
            execution: ExecutionRun,
            monotonicSequence: UInt64,
            previousEvidenceSHA256: SHA256Digest?,
            signature: Signature
        ) {
            self.execution = execution
            self.monotonicSequence = monotonicSequence
            self.previousEvidenceSHA256 = previousEvidenceSHA256
            self.signature = signature
        }

        public var description: String {
            "CodePageLifecycleAudit.ExecutionAttestation(sequence: \(monotonicSequence), provenance: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["sequence": monotonicSequence, "provenance": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    public struct StageEvidence: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let bundle: RevisionReference
        public let bundleManifestSHA256: SHA256Digest
        public let fixture: RevisionReference
        public let codePage: CodePageID
        public let requestedStage: Stage
        public let requestSHA256: SHA256Digest
        public let observation: Observation
        public let origin: EvidenceOrigin
        public let attestation: ExecutionAttestation?

        public init(
            bundle: RevisionReference,
            bundleManifestSHA256: SHA256Digest,
            fixture: RevisionReference,
            codePage: CodePageID,
            requestedStage: Stage,
            requestSHA256: SHA256Digest,
            observation: Observation,
            origin: EvidenceOrigin,
            attestation: ExecutionAttestation?
        ) {
            self.bundle = bundle
            self.bundleManifestSHA256 = bundleManifestSHA256
            self.fixture = fixture
            self.codePage = codePage
            self.requestedStage = requestedStage
            self.requestSHA256 = requestSHA256
            self.observation = observation
            self.origin = origin
            self.attestation = attestation
        }

        public var description: String {
            "CodePageLifecycleAudit.StageEvidence(codePage: \(codePage.rawValue), stage: \(requestedStage), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "codePage": codePage.rawValue,
                    "stage": requestedStage,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct EvidenceBundle: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let reference: RevisionReference
        public let manifest: RevisionReference
        public let manifestSHA256: SHA256Digest
        public let stages: [StageEvidence]

        public init(
            reference: RevisionReference,
            manifest: RevisionReference,
            manifestSHA256: SHA256Digest,
            stages: [StageEvidence]
        ) {
            self.reference = reference
            self.manifest = manifest
            self.manifestSHA256 = manifestSHA256
            self.stages = stages
        }

        public var description: String {
            "CodePageLifecycleAudit.EvidenceBundle(revision: \(reference.revision), stages: \(stages.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "revision": reference.revision,
                    "stageCount": stages.count,
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
        case invalidManifest
        case supportedEncodingManifestMismatch
        case missingFixture
        case duplicateFixture
        case unexpectedFixture
        case staleFixture
        case mappingOracleCodePageMismatch
        case unverifiedMappingOracle
        case invalidFixtureExpectation
        case staleEvidenceBundle
        case missingEvidence
        case duplicateEvidence
        case unexpectedEvidence
        case staleEvidence
        case wrongStageEvidence
        case unorderedStageEvidence
        case mixedExecutionLineage
        case executionRunMismatch
        case unapprovedExecutionLineage
        case signerIdentityMismatch
        case unstableLineageSigner
        case callerAssertionEvidence
        case missingMeasurementAttestation
        case unverifiedMeasurementAttestation
        case ambiguityExpectationMismatch
        case automaticDetectionMismatch
        case explicitSelectionMismatch
        case originalHashMismatch
        case editedHashMismatch
        case editMutationMismatch
        case savedHashMismatch
        case reloadedHashMismatch
        case comparisonMismatch
        case byteComparisonMismatch
    }

    public enum FindingSubject: Hashable, Sendable {
        case manifest
        case codePage(CodePageID)
        case fixture(CodePageID)
        case stage(CodePageID, Stage)

        fileprivate var orderingComponents: [String] {
            switch self {
            case .manifest:
                ["manifest"]
            case .codePage(let codePage):
                ["codePage", String(codePage.rawValue)]
            case .fixture(let codePage):
                ["fixture", String(codePage.rawValue)]
            case .stage(let codePage, let stage):
                ["stage", String(codePage.rawValue), String(stage.rawValue)]
            }
        }
    }

    public struct Finding: Identifiable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue.precomposedStringWithCanonicalMapping
            }

            public static func < (left: Self, right: Self) -> Bool {
                compareUTF8(left.rawValue, right.rawValue) < 0
            }
        }

        public let id: ID
        public let severity: FindingSeverity
        public let code: FindingCode
        public let subject: FindingSubject
        /// Fixed wording; fixture identifiers, hashes, paths, and provenance are omitted.
        public let message: String

        fileprivate init(
            severity: FindingSeverity = .error,
            code: FindingCode,
            subject: FindingSubject,
            discriminator: String = ""
        ) {
            self.severity = severity
            self.code = code
            self.subject = subject
            message = findingMessage(code)
            let identityData = Data(
                ([code.rawValue] + subject.orderingComponents + [discriminator])
                    .map(frame).joined().utf8
            )
            id = ID(rawValue: hex(Array(SHA256.hash(data: identityData))))
        }

        public var description: String {
            "CodePageLifecycleAudit.Finding(severity: \(severity.rawValue), code: \(code.rawValue), subject: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "severity": severity,
                    "code": code,
                    "subject": "<redacted>",
                    "message": message
                ],
                displayStyle: .struct
            )
        }
    }

    public enum CompletenessStatus: String, CaseIterable, Hashable, Sendable {
        case complete
        case missing
        case duplicate
        case unexpected
        case stale
        case wrongStage
        case invalid
        case unsupported
        case unverifiedMapping
        case assertionOnly
    }

    public struct CompletenessCell: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let codePage: SupportedCodePage
        public let fixture: RevisionReference?
        public let stage: Stage
        public let evidenceCount: Int
        public let status: CompletenessStatus

        public var description: String {
            "CodePageLifecycleAudit.CompletenessCell(codePage: \(codePage.rawValue), stage: \(stage), evidence: \(evidenceCount), status: \(status.rawValue), fixture: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "codePage": codePage.rawValue,
                    "stage": stage,
                    "evidenceCount": evidenceCount,
                    "status": status,
                    "fixture": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct CompletenessMatrix: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let cells: [CompletenessCell]

        fileprivate init(cells: [CompletenessCell]) {
            self.cells = cells
        }

        public var requiredCount: Int { cells.count }
        public var completeCount: Int { cells.count(where: { $0.status == .complete }) }
        public var isComplete: Bool { completeCount == requiredCount }
        public var description: String {
            "CodePageLifecycleAudit.CompletenessMatrix(required: \(requiredCount), complete: \(completeCount), contents: <redacted>)"
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

    public struct Report: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public static let scopeStatement =
            "Deterministic validation of bounded, caller-supplied, cryptographically bound code-page lifecycle measurements; not codec, filesystem, comparison-engine, or UI execution."

        public let formatVersion: Int
        public let manifest: RevisionReference
        public let evidence: RevisionReference
        public let completeness: CompletenessMatrix
        public let findings: [Finding]

        public var containsErrors: Bool { findings.contains { $0.severity == .error } }
        public var highestSeverity: FindingSeverity? { findings.first?.severity }
        public var isCompleteAndValid: Bool {
            completeness.isComplete && findings.isEmpty
        }

        fileprivate init(
            manifest: RevisionReference,
            evidence: RevisionReference,
            completeness: CompletenessMatrix,
            findings: [Finding]
        ) {
            formatVersion = reportFormatVersion
            self.manifest = manifest
            self.evidence = evidence
            self.completeness = completeness
            self.findings = findings
        }

        public var description: String {
            "CodePageLifecycleAudit.Report(required: \(completeness.requiredCount), complete: \(completeness.completeCount), findings: \(findings.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "requiredCount": completeness.requiredCount,
                    "completeCount": completeness.completeCount,
                    "findingCount": findings.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Receipt: Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let formatVersion: Int
        public let manifest: RevisionReference
        public let evidence: RevisionReference
        public let manifestSHA256: SHA256Digest
        public let evidenceSHA256: SHA256Digest
        public let requestSetSHA256: SHA256Digest
        public let oracleSetSHA256: SHA256Digest
        public let trustPolicySHA256: SHA256Digest
        public let requiredStageCount: Int
        public let completeStageCount: Int
        public let findingCount: Int

        public var recordsCompleteCoverage: Bool {
            completeStageCount == requiredStageCount && findingCount == 0
        }

        fileprivate init(
            manifest: RevisionReference,
            evidence: RevisionReference,
            manifestSHA256: SHA256Digest,
            evidenceSHA256: SHA256Digest,
            requestSetSHA256: SHA256Digest,
            oracleSetSHA256: SHA256Digest,
            trustPolicySHA256: SHA256Digest,
            requiredStageCount: Int,
            completeStageCount: Int,
            findingCount: Int
        ) {
            formatVersion = reportFormatVersion
            self.manifest = manifest
            self.evidence = evidence
            self.manifestSHA256 = manifestSHA256
            self.evidenceSHA256 = evidenceSHA256
            self.requestSetSHA256 = requestSetSHA256
            self.oracleSetSHA256 = oracleSetSHA256
            self.trustPolicySHA256 = trustPolicySHA256
            self.requiredStageCount = requiredStageCount
            self.completeStageCount = completeStageCount
            self.findingCount = findingCount
        }

        public var description: String {
            "CodePageLifecycleAudit.Receipt(required: \(requiredStageCount), complete: \(completeStageCount), findings: \(findingCount), digests: <redacted>)"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "requiredStageCount": requiredStageCount,
                    "completeStageCount": completeStageCount,
                    "findingCount": findingCount,
                    "digests": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Result: Hashable, Sendable {
        public let plan: Plan
        public let report: Report
        public let receipt: Receipt

        fileprivate init(plan: Plan, report: Report, receipt: Receipt) {
            self.plan = plan
            self.report = report
            self.receipt = receipt
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case fixtures
        case evidence
        case trustedSigners
        case findings
        case stringUTF8Bytes
        case totalStringUTF8Bytes
        case contentBytes
        case unicodeScalars
        case canonicalBytes
        case workUnits
        case cancellationCheckInterval
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumFixtures = 4_096
        public static let hardMaximumEvidence = hardMaximumFixtures * Stage.allCases.count * 2
        public static let hardMaximumTrustedSigners = 4_096
        public static let hardMaximumFindings = 1_000_000
        public static let hardMaximumStringUTF8Bytes = 1 * 1_024 * 1_024
        public static let hardMaximumTotalStringUTF8Bytes = 128 * 1_024 * 1_024
        public static let hardMaximumContentBytes = 1 << 40
        public static let hardMaximumUnicodeScalars = 1_000_000_000
        public static let hardMaximumCanonicalBytes = 256 * 1_024 * 1_024
        public static let hardMaximumWorkUnits: UInt64 = 1 << 40
        public static let hardMaximumCancellationCheckInterval = 65_536
        public static let `default` = Limits()

        public let maximumFixtures: Int
        public let maximumEvidence: Int
        public let maximumTrustedSigners: Int
        public let maximumFindings: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumContentBytes: Int
        public let maximumUnicodeScalars: Int
        public let maximumCanonicalBytes: Int
        public let maximumWorkUnits: UInt64
        public let cancellationCheckInterval: Int

        public init(
            maximumFixtures: Int = 256,
            maximumEvidence: Int = 4_096,
            maximumTrustedSigners: Int = 256,
            maximumFindings: Int = 100_000,
            maximumStringUTF8Bytes: Int = 64 * 1_024,
            maximumTotalStringUTF8Bytes: Int = 8 * 1_024 * 1_024,
            maximumContentBytes: Int = 1 * 1_024 * 1_024 * 1_024,
            maximumUnicodeScalars: Int = 256 * 1_024 * 1_024,
            maximumCanonicalBytes: Int = 32 * 1_024 * 1_024,
            maximumWorkUnits: UInt64 = 256 * 1_024 * 1_024,
            cancellationCheckInterval: Int = 256
        ) {
            self.maximumFixtures = maximumFixtures
            self.maximumEvidence = maximumEvidence
            self.maximumTrustedSigners = maximumTrustedSigners
            self.maximumFindings = maximumFindings
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumContentBytes = maximumContentBytes
            self.maximumUnicodeScalars = maximumUnicodeScalars
            self.maximumCanonicalBytes = maximumCanonicalBytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }
    }

    public enum AuditError: Error, Equatable, LocalizedError, Sendable {
        case cancelled
        case invalidDigestLength
        case invalidLimit(Limit)
        case countLimitExceeded(Limit, maximum: Int)
        case stringTooLarge(maximumUTF8Bytes: Int)
        case totalStringsTooLarge(maximumUTF8Bytes: Int)
        case canonicalDataTooLarge(maximumBytes: Int)
        case workLimitExceeded(maximum: UInt64)
        case findingLimitExceeded(maximum: Int)
        case invalidSigningInput

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                "Code-page lifecycle audit was cancelled."
            case .invalidDigestLength:
                "Code-page lifecycle audit requires 32-byte SHA-256 digests."
            case .invalidLimit(let limit):
                "Code-page lifecycle audit limit is invalid: \(limit.rawValue)."
            case .countLimitExceeded(let limit, let maximum):
                "Code-page lifecycle audit exceeds the \(maximum)-\(limit.rawValue) limit."
            case .stringTooLarge(let maximum):
                "Code-page lifecycle audit metadata exceeds \(maximum) UTF-8 bytes; contents are redacted."
            case .totalStringsTooLarge(let maximum):
                "Code-page lifecycle audit metadata exceeds \(maximum) total UTF-8 bytes; contents are redacted."
            case .canonicalDataTooLarge(let maximum):
                "Code-page lifecycle audit canonical data exceeds \(maximum) bytes."
            case .workLimitExceeded(let maximum):
                "Code-page lifecycle audit exceeds \(maximum) work units."
            case .findingLimitExceeded(let maximum):
                "Code-page lifecycle audit exceeds \(maximum) findings."
            case .invalidSigningInput:
                "Code-page lifecycle signing input is invalid; contents are redacted."
            }
        }
    }

    /// Returns the SHA-256 prehash an independent oracle signs. Signature bytes are excluded;
    /// fixture artifact and complete lifecycle expectation are included.
    public static func mappingOracleSigningPrehash(
        _ fixture: Fixture,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> SHA256Digest {
        var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
        try validate(fixture: fixture, limits: limits, work: &work)
        let data = try encodeMappingOracleSigningPayload(fixture, work: &work)
        let digest = try sha256(data, work: &work)
        try work.finish()
        return digest
    }

    /// Returns the SHA-256 prehash a measurement executor signs. Signature bytes are excluded.
    public static func executionSigningPrehash(
        _ evidence: StageEvidence,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> SHA256Digest {
        guard evidence.attestation != nil else { throw AuditError.invalidSigningInput }
        var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
        try validate(stageEvidence: evidence, limits: limits, work: &work)
        let data = try encodeStageEvidence(evidence, includeSignature: false, work: &work)
        let digest = try sha256(data, work: &work)
        try work.finish()
        return digest
    }

    /// Digest used by the next stage's hash-chain link. Attestation signature is included.
    public static func stageEvidenceSHA256(
        _ evidence: StageEvidence,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> SHA256Digest {
        var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
        try validate(stageEvidence: evidence, limits: limits, work: &work)
        let data = try encodeStageEvidence(evidence, includeSignature: true, work: &work)
        let digest = try sha256(data, work: &work)
        try work.finish()
        return digest
    }

    public static func manifestSHA256(
        _ manifest: Manifest,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> SHA256Digest {
        var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
        try preflight(manifest: manifest, limits: limits, work: &work)
        let data = try encodeManifest(manifest, work: &work)
        let digest = try sha256(data, work: &work)
        try work.finish()
        return digest
    }

    public static func prepare(
        manifest: Manifest,
        trustPolicy: TrustPolicy,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Plan {
        var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
        try preflight(
            manifest: manifest,
            evidence: nil,
            trustPolicy: trustPolicy,
            limits: limits,
            work: &work
        )
        let manifestData = try encodeManifest(manifest, work: &work)
        let manifestDigest = try sha256(manifestData, work: &work)
        var findings: [Finding] = []
        var verifications: [FixtureVerification] = []
        try auditManifest(
            manifest,
            trustPolicy: trustPolicy,
            limits: limits,
            findings: &findings,
            verifications: &verifications,
            work: &work
        )

        let requests = try makeRequests(
            manifest: manifest,
            manifestDigest: manifestDigest,
            work: &work
        )
        let requestSetData = try encodeRequests(requests, work: &work)
        let requestSetDigest = try sha256(requestSetData, work: &work)
        let trustPolicyData = try encodeTrustPolicy(trustPolicy, work: &work)
        let trustPolicyDigest = try sha256(trustPolicyData, work: &work)
        findings = try sortedFindings(findings, limits: limits, work: &work)
        try work.finish()
        let receipt = PlanningReceipt(
            manifest: manifest.reference,
            manifestSHA256: manifestDigest,
            requestSetSHA256: requestSetDigest,
            trustPolicySHA256: trustPolicyDigest,
            requestCount: requests.count
        )
        return Plan(
            manifest: manifest,
            manifestSHA256: manifestDigest,
            requests: requests,
            fixtureVerifications: verifications,
            preflightFindings: findings,
            receipt: receipt,
            workPerformed: work.completed,
            stringUTF8BytesProcessed: work.totalStringBytes
        )
    }

    public static func evaluate(
        manifest: Manifest,
        evidence: EvidenceBundle,
        trustPolicy: TrustPolicy,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Result {
        let plan = try prepare(
            manifest: manifest,
            trustPolicy: trustPolicy,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
        return try evaluate(
            plan: plan,
            evidence: evidence,
            trustPolicy: trustPolicy,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    public static func evaluate(
        plan: Plan,
        evidence: EvidenceBundle,
        trustPolicy: TrustPolicy,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Result {
        var work = try Work(
            limits: limits,
            cancellationCheck: cancellationCheck,
            completed: plan.workPerformed,
            totalStringBytes: plan.stringUTF8BytesProcessed
        )
        try preflight(
            manifest: plan.manifest,
            evidence: evidence,
            trustPolicy: trustPolicy,
            limits: limits,
            work: &work
        )
        let trustPolicyData = try encodeTrustPolicy(trustPolicy, work: &work)
        let trustPolicyDigest = try sha256(trustPolicyData, work: &work)
        guard trustPolicyDigest == plan.receipt.trustPolicySHA256 else {
            throw AuditError.invalidSigningInput
        }
        let currentManifestData = try encodeManifest(plan.manifest, work: &work)
        let currentManifestDigest = try sha256(currentManifestData, work: &work)
        let rebuiltRequests = try makeRequests(
            manifest: plan.manifest,
            manifestDigest: currentManifestDigest,
            work: &work
        )
        let currentRequestSetData = try encodeRequests(plan.requests, work: &work)
        let currentRequestSetDigest = try sha256(currentRequestSetData, work: &work)
        guard currentManifestDigest == plan.manifestSHA256,
            currentManifestDigest == plan.receipt.manifestSHA256,
            plan.receipt.manifest == plan.manifest.reference,
            plan.receipt.requestCount == plan.requests.count,
            rebuiltRequests == plan.requests,
            currentRequestSetDigest == plan.receipt.requestSetSHA256
        else {
            throw AuditError.invalidSigningInput
        }
        var findings: [Finding] = []
        var currentVerifications: [FixtureVerification] = []
        try auditManifest(
            plan.manifest,
            trustPolicy: trustPolicy,
            limits: limits,
            findings: &findings,
            verifications: &currentVerifications,
            work: &work
        )
        var cellStates: [CellKey: CellState] = [:]
        try initializeCells(plan: plan, states: &cellStates, work: &work)

        let bundleIsCurrent =
            evidence.manifest == plan.manifest.reference
            && evidence.manifestSHA256 == plan.manifestSHA256
        if !bundleIsCurrent {
            try appendFinding(
                Finding(code: .staleEvidenceBundle, subject: .manifest),
                to: &findings,
                limits: limits
            )
        }

        var requestsByCoordinate: [Coordinate: [StageRequest]] = [:]
        for request in plan.requests {
            let coordinate = Coordinate(
                fixtureDigest: try identityDigest(request.fixture, work: &work),
                codePage: request.codePage,
                stage: request.stage
            )
            requestsByCoordinate[coordinate, default: []].append(request)
        }
        var exactRequestCountByCoordinate: [Coordinate: Int] = [:]
        for (coordinate, requests) in requestsByCoordinate {
            try work.consume(requests.count + 1)
            exactRequestCountByCoordinate[coordinate] = requests.count
        }
        var fixturesByKey: [FixtureKey: [Fixture]] = [:]
        for fixture in plan.manifest.fixtures {
            let key = FixtureKey(
                fixtureDigest: try identityDigest(fixture.reference, work: &work),
                codePage: fixture.codePage
            )
            fixturesByKey[key, default: []].append(fixture)
        }
        var verificationsByKey: [FixtureKey: [FixtureVerification]] = [:]
        for verification in currentVerifications {
            let key = FixtureKey(
                fixtureDigest: try identityDigest(verification.fixture, work: &work),
                codePage: verification.codePage
            )
            verificationsByKey[key, default: []].append(verification)
        }
        let measurementSigners = try signerMap(
            trustPolicy.measurementSigners,
            work: &work
        )
        var approvedLineagesByIdentity: [SHA256Digest: ExecutionLineage] = [:]
        approvedLineagesByIdentity.reserveCapacity(plan.manifest.approvedExecutionLineages.count)
        for lineage in plan.manifest.approvedExecutionLineages {
            let identity = try executionLineageIdentityDigest(lineage, work: &work)
            approvedLineagesByIdentity[identity] = lineage
        }
        var evidenceByCoordinate: [Coordinate: [StageEvidence]] = [:]
        for item in evidence.stages {
            try work.consume()
            let coordinate = Coordinate(
                fixtureDigest: try identityDigest(item.fixture, work: &work),
                codePage: item.codePage,
                stage: item.requestedStage
            )
            guard exactRequestCountByCoordinate[coordinate] == 1 else {
                try appendFinding(
                    Finding(
                        code: .unexpectedEvidence,
                        subject: .stage(item.codePage, item.requestedStage)
                    ),
                    to: &findings,
                    limits: limits
                )
                continue
            }
            evidenceByCoordinate[coordinate, default: []].append(item)
        }

        for request in plan.requests {
            try work.consume()
            let coordinate = Coordinate(
                fixtureDigest: try identityDigest(request.fixture, work: &work),
                codePage: request.codePage,
                stage: request.stage
            )
            guard exactRequestCountByCoordinate[coordinate] == 1 else { continue }
            let matching = (evidenceByCoordinate[coordinate] ?? []).filter {
                $0.fixture == request.fixture && $0.codePage == request.codePage
                    && $0.requestedStage == request.stage
            }
            let subject = FindingSubject.stage(request.codePage, request.stage)
            guard matching.count == 1 else {
                let code: FindingCode = matching.isEmpty ? .missingEvidence : .duplicateEvidence
                try appendFinding(Finding(code: code, subject: subject), to: &findings, limits: limits)
                setCellStatus(
                    codePage: request.codePage,
                    fixture: request.fixture,
                    stage: request.stage,
                    count: matching.count,
                    status: matching.isEmpty ? .missing : .duplicate,
                    states: &cellStates
                )
                continue
            }
            let fixtureKey = FixtureKey(
                fixtureDigest: try identityDigest(request.fixture, work: &work),
                codePage: request.codePage
            )
            let fixtures = (fixturesByKey[fixtureKey] ?? []).filter {
                $0.reference == request.fixture && $0.codePage == request.codePage
            }
            guard fixtures.count == 1 else {
                setCellStatus(
                    codePage: request.codePage,
                    fixture: request.fixture,
                    stage: request.stage,
                    count: 1,
                    status: .invalid,
                    states: &cellStates
                )
                continue
            }
            let fixture = fixtures[0]
            let item = matching[0]
            let verifications = (verificationsByKey[fixtureKey] ?? []).filter {
                $0.fixture == request.fixture && $0.codePage == request.codePage
            }
            let verification = verifications.count == 1 ? verifications[0] : nil
            if verification?.isSupported != true {
                setCellStatus(
                    codePage: request.codePage,
                    fixture: request.fixture,
                    stage: request.stage,
                    count: 1,
                    status: .unsupported,
                    states: &cellStates
                )
                continue
            }
            if verification?.isMappingOracleVerified != true {
                setCellStatus(
                    codePage: request.codePage,
                    fixture: request.fixture,
                    stage: request.stage,
                    count: 1,
                    status: .unverifiedMapping,
                    states: &cellStates
                )
                continue
            }
            if verification?.isFixtureValid != true {
                setCellStatus(
                    codePage: request.codePage,
                    fixture: request.fixture,
                    stage: request.stage,
                    count: 1,
                    status: .invalid,
                    states: &cellStates
                )
                continue
            }
            let status = try audit(
                item,
                request: request,
                fixture: fixture,
                bundleIsCurrent: bundleIsCurrent,
                evidenceBundle: evidence.reference,
                trustedMeasurementSigners: measurementSigners,
                approvedLineagesByIdentity: approvedLineagesByIdentity,
                limits: limits,
                findings: &findings,
                work: &work
            )
            setCellStatus(
                codePage: request.codePage,
                fixture: request.fixture,
                stage: request.stage,
                count: 1,
                status: status,
                states: &cellStates
            )
        }

        try auditEvidenceOrder(
            plan: plan,
            evidenceByCoordinate: evidenceByCoordinate,
            cellStates: &cellStates,
            findings: &findings,
            limits: limits,
            work: &work
        )
        findings = try sortedFindings(findings, limits: limits, work: &work)
        let cells = cellStates.values.sorted { left, right in
            if left.cell.codePage != right.cell.codePage {
                return left.cell.codePage < right.cell.codePage
            }
            return left.cell.stage < right.cell.stage
        }.map(\.cell)
        let matrix = CompletenessMatrix(cells: cells)
        let report = Report(
            manifest: plan.manifest.reference,
            evidence: evidence.reference,
            completeness: matrix,
            findings: findings
        )
        let evidenceData = try encodeEvidenceBundle(evidence, work: &work)
        let evidenceDigest = try sha256(evidenceData, work: &work)
        let oracleSetData = try encodeOracleSet(plan.manifest.fixtures, work: &work)
        let oracleSetDigest = try sha256(oracleSetData, work: &work)
        try work.finish()
        let receipt = Receipt(
            manifest: plan.manifest.reference,
            evidence: evidence.reference,
            manifestSHA256: plan.manifestSHA256,
            evidenceSHA256: evidenceDigest,
            requestSetSHA256: plan.receipt.requestSetSHA256,
            oracleSetSHA256: oracleSetDigest,
            trustPolicySHA256: trustPolicyDigest,
            requiredStageCount: matrix.requiredCount,
            completeStageCount: matrix.completeCount,
            findingCount: findings.count
        )
        return Result(plan: plan, report: report, receipt: receipt)
    }
}

extension CodePageLifecycleAudit {
    fileprivate struct UnsignedStageRequest {
        let ordinal: Int
        let fixture: RevisionReference
        let codePage: CodePageID
        let stage: Stage
        let manifest: RevisionReference
        let manifestSHA256: SHA256Digest
        let fixtureSHA256: SHA256Digest
        let mappingOracleSHA256: SHA256Digest
    }

    fileprivate struct Coordinate: Hashable {
        let fixtureDigest: SHA256Digest
        let codePage: CodePageID
        let stage: Stage
    }

    fileprivate struct FixtureKey: Hashable {
        let fixtureDigest: SHA256Digest
        let codePage: CodePageID
    }

    fileprivate struct ExactFixtureKey: Hashable {
        let fixtureDigest: SHA256Digest
        let codePage: CodePageID
    }

    fileprivate struct CellKey: Hashable {
        let codePage: SupportedCodePage
        let stage: Stage
    }

    fileprivate struct CellState {
        var cell: CompletenessCell
    }

    fileprivate struct Work {
        let limits: Limits
        let cancellationCheck: CancellationCheck
        var completed: UInt64 = 0
        var nextCancellationCheck: UInt64 = 0
        var totalStringBytes = 0

        init(
            limits: Limits,
            cancellationCheck: @escaping CancellationCheck,
            completed: UInt64 = 0,
            totalStringBytes: Int = 0
        ) throws {
            try validate(limits)
            guard completed <= limits.maximumWorkUnits else {
                throw AuditError.workLimitExceeded(maximum: limits.maximumWorkUnits)
            }
            guard (0...limits.maximumTotalStringUTF8Bytes).contains(totalStringBytes) else {
                throw AuditError.totalStringsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
                )
            }
            self.limits = limits
            self.cancellationCheck = cancellationCheck
            self.completed = completed
            self.totalStringBytes = totalStringBytes
            try checkCancellation()
        }

        mutating func consume(_ units: Int = 1) throws {
            guard units >= 0, let amount = UInt64(exactly: units) else {
                throw AuditError.workLimitExceeded(maximum: limits.maximumWorkUnits)
            }
            guard amount <= limits.maximumWorkUnits,
                completed <= limits.maximumWorkUnits - amount
            else {
                throw AuditError.workLimitExceeded(maximum: limits.maximumWorkUnits)
            }
            var remaining = amount
            while remaining > 0 {
                if completed >= nextCancellationCheck {
                    try checkCancellation()
                }
                let untilCheck = nextCancellationCheck - completed
                let consumed = min(remaining, untilCheck)
                completed += consumed
                remaining -= consumed
            }
        }

        mutating func string(_ value: String) throws {
            _ = try stringData(value)
        }

        mutating func stringData(_ value: String) throws -> Data {
            var data = Data()
            data.reserveCapacity(min(limits.maximumStringUTF8Bytes, 256))
            for byte in value.utf8 {
                if data.count == limits.maximumStringUTF8Bytes {
                    throw AuditError.stringTooLarge(
                        maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                    )
                }
                data.append(byte)
                try consume(2)
            }
            let count = data.count
            guard totalStringBytes <= limits.maximumTotalStringUTF8Bytes - count else {
                throw AuditError.totalStringsTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
                )
            }
            totalStringBytes += count
            try consume()
            return data
        }

        mutating func finish() throws {
            try checkCancellation()
        }

        private mutating func checkCancellation() throws {
            guard !cancellationCheck() else { throw AuditError.cancelled }
            let interval = UInt64(limits.cancellationCheckInterval)
            let (next, overflow) = completed.addingReportingOverflow(interval)
            nextCancellationCheck = overflow ? UInt64.max : next
        }
    }

    fileprivate struct Writer {
        var data = Data()
        var work: Work

        init(work: Work) {
            self.work = work
        }

        mutating func appendDomain(_ value: String) throws {
            try appendString(value)
        }

        mutating func appendString(_ value: String) throws {
            let data = try work.stringData(value)
            try appendUInt64(UInt64(data.count))
            try appendData(data)
        }

        mutating func appendReference(_ value: RevisionReference) throws {
            try appendString(value.id.rawValue)
            try appendUInt64(value.revision)
        }

        mutating func appendDigest(_ value: SHA256Digest) throws {
            try appendRaw(value.bytes)
        }

        mutating func appendContent(_ value: ContentHash) throws {
            try appendInt(value.bytes.byteCount)
            try appendDigest(value.bytes.sha256)
            try appendUnicode(value.unicode)
        }

        mutating func appendUnicode(_ value: UnicodeHash) throws {
            try appendInt(value.scalarCount)
            try appendDigest(value.sha256)
        }

        mutating func appendScalarEdit(_ value: UnicodeScalarEdit) throws {
            try appendScalarSequence(value.unchangedPrefix)
            try appendScalarSequence(value.removedScalars)
            try appendScalarSequence(value.insertedScalars)
            try appendScalarSequence(value.unchangedSuffix)
        }

        mutating func appendScalarSequence(_ values: [UInt32]) throws {
            try appendCount(values.count)
            for scalar in values { try appendUInt32(scalar) }
        }

        mutating func appendDetection(_ value: DetectionOutcome) throws {
            switch value {
            case .selected(let codePage):
                try appendUInt8(0)
                try appendInt(codePage.rawValue)
            case .ambiguous(let codePages):
                try appendUInt8(1)
                try appendCount(codePages.count)
                for codePage in codePages { try appendInt(codePage.rawValue) }
            case .rejected:
                try appendUInt8(2)
            }
        }

        mutating func appendOptionalDigest(_ value: SHA256Digest?) throws {
            if let value {
                try appendUInt8(1)
                try appendDigest(value)
            } else {
                try appendUInt8(0)
            }
        }

        mutating func appendBool(_ value: Bool) throws {
            try appendUInt8(value ? 1 : 0)
        }

        mutating func appendCount(_ value: Int) throws {
            try appendInt(value)
        }

        mutating func appendInt(_ value: Int) throws {
            guard let wire = Int64(exactly: value) else { throw AuditError.invalidSigningInput }
            try appendUInt64(UInt64(bitPattern: wire))
        }

        mutating func appendUInt8(_ value: UInt8) throws {
            try appendRaw([value])
        }

        mutating func appendUInt32(_ value: UInt32) throws {
            try appendRaw([
                UInt8(truncatingIfNeeded: value >> 24),
                UInt8(truncatingIfNeeded: value >> 16),
                UInt8(truncatingIfNeeded: value >> 8),
                UInt8(truncatingIfNeeded: value)
            ])
        }

        mutating func appendUInt64(_ value: UInt64) throws {
            try appendRaw([
                UInt8(truncatingIfNeeded: value >> 56),
                UInt8(truncatingIfNeeded: value >> 48),
                UInt8(truncatingIfNeeded: value >> 40),
                UInt8(truncatingIfNeeded: value >> 32),
                UInt8(truncatingIfNeeded: value >> 24),
                UInt8(truncatingIfNeeded: value >> 16),
                UInt8(truncatingIfNeeded: value >> 8),
                UInt8(truncatingIfNeeded: value)
            ])
        }

        mutating func appendRaw(_ bytes: [UInt8]) throws {
            try appendData(Data(bytes))
        }

        mutating func appendData(_ value: Data) throws {
            guard value.count <= work.limits.maximumCanonicalBytes,
                data.count <= work.limits.maximumCanonicalBytes - value.count
            else {
                throw AuditError.canonicalDataTooLarge(
                    maximumBytes: work.limits.maximumCanonicalBytes
                )
            }
            var offset = 0
            while offset < value.count {
                let end = min(offset + work.limits.cancellationCheckInterval, value.count)
                try work.consume(end - offset + 1)
                data.append(value[offset..<end])
                offset = end
            }
        }
    }

    fileprivate static func validate(_ limits: Limits) throws {
        guard (1...Limits.hardMaximumFixtures).contains(limits.maximumFixtures) else {
            throw AuditError.invalidLimit(.fixtures)
        }
        guard (1...Limits.hardMaximumEvidence).contains(limits.maximumEvidence) else {
            throw AuditError.invalidLimit(.evidence)
        }
        guard (1...Limits.hardMaximumTrustedSigners).contains(limits.maximumTrustedSigners) else {
            throw AuditError.invalidLimit(.trustedSigners)
        }
        guard (1...Limits.hardMaximumFindings).contains(limits.maximumFindings) else {
            throw AuditError.invalidLimit(.findings)
        }
        guard (1...Limits.hardMaximumStringUTF8Bytes).contains(limits.maximumStringUTF8Bytes) else {
            throw AuditError.invalidLimit(.stringUTF8Bytes)
        }
        guard
            (1...Limits.hardMaximumTotalStringUTF8Bytes).contains(
                limits.maximumTotalStringUTF8Bytes
            ), limits.maximumTotalStringUTF8Bytes >= limits.maximumStringUTF8Bytes
        else {
            throw AuditError.invalidLimit(.totalStringUTF8Bytes)
        }
        guard (1...Limits.hardMaximumContentBytes).contains(limits.maximumContentBytes) else {
            throw AuditError.invalidLimit(.contentBytes)
        }
        guard (1...Limits.hardMaximumUnicodeScalars).contains(limits.maximumUnicodeScalars) else {
            throw AuditError.invalidLimit(.unicodeScalars)
        }
        guard (1...Limits.hardMaximumCanonicalBytes).contains(limits.maximumCanonicalBytes) else {
            throw AuditError.invalidLimit(.canonicalBytes)
        }
        guard (1...Limits.hardMaximumWorkUnits).contains(limits.maximumWorkUnits) else {
            throw AuditError.invalidLimit(.workUnits)
        }
        guard
            (1...Limits.hardMaximumCancellationCheckInterval).contains(
                limits.cancellationCheckInterval
            )
        else {
            throw AuditError.invalidLimit(.cancellationCheckInterval)
        }
    }

    fileprivate static func preflight(
        manifest: Manifest,
        evidence: EvidenceBundle? = nil,
        trustPolicy: TrustPolicy? = nil,
        limits: Limits,
        work: inout Work
    ) throws {
        guard manifest.fixtures.count <= limits.maximumFixtures else {
            throw AuditError.countLimitExceeded(.fixtures, maximum: limits.maximumFixtures)
        }
        let stagesPerFixture = Stage.allCases.count
        guard stagesPerFixture > 0,
            manifest.fixtures.count <= limits.maximumEvidence / stagesPerFixture
        else {
            throw AuditError.countLimitExceeded(.evidence, maximum: limits.maximumEvidence)
        }
        if let evidence, evidence.stages.count > limits.maximumEvidence {
            throw AuditError.countLimitExceeded(.evidence, maximum: limits.maximumEvidence)
        }
        if let trustPolicy {
            let signerCounts = trustPolicy.mappingOracleSigners.count.addingReportingOverflow(
                trustPolicy.measurementSigners.count
            )
            guard !signerCounts.overflow,
                signerCounts.partialValue <= limits.maximumTrustedSigners
            else {
                throw AuditError.countLimitExceeded(
                    .trustedSigners,
                    maximum: limits.maximumTrustedSigners
                )
            }
        }
        try validate(reference: manifest.reference, work: &work)
        try validate(reference: manifest.codec, work: &work)
        guard !isZeroDigest(manifest.codecArtifactSHA256) else {
            throw AuditError.invalidSigningInput
        }
        guard manifest.approvedExecutionLineages.count <= limits.maximumTrustedSigners else {
            throw AuditError.countLimitExceeded(
                .trustedSigners,
                maximum: limits.maximumTrustedSigners
            )
        }
        guard manifest.declaredSupportedCodePages.count <= limits.maximumFixtures else {
            throw AuditError.countLimitExceeded(.fixtures, maximum: limits.maximumFixtures)
        }
        guard manifest.codecSessionMappings.count <= SupportedCodePage.allCases.count else {
            throw AuditError.invalidSigningInput
        }
        for mapping in manifest.codecSessionMappings {
            try work.consume()
            try work.string(mapping.codecEncodingIdentifier)
            try work.string(mapping.sessionEncodingIdentifier)
        }
        for fixture in manifest.fixtures {
            try work.consume()
            try validate(fixture: fixture, limits: limits, work: &work)
        }
        var lineageSignerByIdentity: [SHA256Digest: StableID] = [:]
        for lineage in manifest.approvedExecutionLineages {
            try work.consume()
            try validate(lineage: lineage, work: &work)
            let lineageIdentity = try executionLineageIdentityDigest(lineage, work: &work)
            guard lineageSignerByIdentity[lineageIdentity] == nil else {
                throw AuditError.invalidSigningInput
            }
            lineageSignerByIdentity[lineageIdentity] = lineage.signerID
        }
        if let evidence {
            try validate(reference: evidence.reference, work: &work)
            try validate(reference: evidence.manifest, work: &work)
            for item in evidence.stages {
                try work.consume()
                try validate(stageEvidence: item, limits: limits, work: &work)
            }
        }
        if let trustPolicy {
            try validate(reference: trustPolicy.approvedCodecArtifact.codec, work: &work)
            guard !isZeroDigest(trustPolicy.approvedCodecArtifact.artifactSHA256) else {
                throw AuditError.invalidSigningInput
            }
            var oracleIDs: Set<StableID> = []
            var oracleKeys: Set<[UInt8]> = []
            for signer in trustPolicy.mappingOracleSigners + trustPolicy.measurementSigners {
                try work.consume()
                try validate(id: signer.id, work: &work)
                guard signer.publicKey.count == 32 else {
                    throw AuditError.invalidSigningInput
                }
            }
            for signer in trustPolicy.mappingOracleSigners {
                try work.consume(signer.publicKey.count + 1)
                guard oracleIDs.insert(signer.id).inserted,
                    oracleKeys.insert(signer.publicKey).inserted
                else { throw AuditError.invalidSigningInput }
            }
            var measurementIDs: Set<StableID> = []
            var measurementKeys: Set<[UInt8]> = []
            for signer in trustPolicy.measurementSigners {
                try work.consume(signer.publicKey.count + 1)
                guard measurementIDs.insert(signer.id).inserted,
                    measurementKeys.insert(signer.publicKey).inserted,
                    !oracleIDs.contains(signer.id),
                    !oracleKeys.contains(signer.publicKey)
                else { throw AuditError.invalidSigningInput }
            }
        }
    }

    fileprivate static func validate(fixture: Fixture, limits: Limits, work: inout Work) throws {
        try validate(reference: fixture.reference, work: &work)
        guard !isZeroDigest(fixture.fixtureArtifactSHA256) else {
            throw AuditError.invalidSigningInput
        }
        try validate(oracle: fixture.mappingOracle, limits: limits, work: &work)
        try validate(content: fixture.expectation.original, limits: limits, work: &work)
        try validate(content: fixture.expectation.edited, limits: limits, work: &work)
        try validate(content: fixture.expectation.saved, limits: limits, work: &work)
        try validate(content: fixture.expectation.reloaded, limits: limits, work: &work)
        try validate(
            edit: fixture.expectation.intendedEdit,
            from: fixture.expectation.original.unicode,
            to: fixture.expectation.edited.unicode,
            limits: limits,
            work: &work
        )
        try validate(
            detection: fixture.expectation.selection.automaticDetection,
            work: &work
        )
        guard
            SupportedCodePage(rawValue: fixture.expectation.selection.explicitSelection.rawValue)
                != nil
        else { throw AuditError.invalidSigningInput }
    }

    fileprivate static func validate(oracle: MappingOracle, limits: Limits, work: inout Work) throws {
        try validate(reference: oracle.reference, work: &work)
        let sourceBytes = try work.stringData(oracle.sourceIdentifier)
        guard !sourceBytes.isEmpty,
            sourceBytes.elementsEqual(oracle.sourceIdentifier.utf8),
            !isZeroDigest(oracle.sourceArtifactSHA256),
            !isZeroDigest(oracle.mappingTableSHA256)
        else {
            throw AuditError.invalidSigningInput
        }
        try validate(id: oracle.signature.signerID, work: &work)
        guard oracle.signature.bytes.count <= 256,
            let codePage = SupportedCodePage(rawValue: oracle.codePage.rawValue),
            oracle.mappingCardinality == codePage.expectedMappingCardinality
        else {
            throw AuditError.invalidSigningInput
        }
        try validate(
            scalarCommitments: oracle.fixtureScalarCommitments,
            limits: limits,
            work: &work
        )
        try work.consume(oracle.signature.bytes.count + 1)
    }

    fileprivate static func validate(stageEvidence: StageEvidence, limits: Limits, work: inout Work) throws {
        try validate(reference: stageEvidence.bundle, work: &work)
        try validate(reference: stageEvidence.fixture, work: &work)
        switch stageEvidence.observation {
        case .load(let value):
            try validate(detection: value.automaticDetection, work: &work)
            try validate(content: value.source, limits: limits, work: &work)
            try validate(content: value.loaded, limits: limits, work: &work)
        case .compare(let value):
            try validate(content: value.left, limits: limits, work: &work)
            try validate(content: value.right, limits: limits, work: &work)
        case .edit(let value):
            try validate(content: value.before, limits: limits, work: &work)
            try validate(content: value.after, limits: limits, work: &work)
            try validate(
                edit: value.unicodeScalarDelta,
                from: value.before.unicode,
                to: value.after.unicode,
                limits: limits,
                work: &work
            )
        case .save(let value):
            try validate(content: value.edited, limits: limits, work: &work)
            try validate(content: value.saved, limits: limits, work: &work)
        case .reload(let value):
            try validate(content: value.saved, limits: limits, work: &work)
            try validate(content: value.reloaded, limits: limits, work: &work)
        case .byteComparison(let value):
            try validate(content: value.saved, limits: limits, work: &work)
            try validate(content: value.reloaded, limits: limits, work: &work)
        }
        if let attestation = stageEvidence.attestation {
            try validate(lineage: attestation.execution.lineage, work: &work)
            guard !isZeroDigest(attestation.execution.runSHA256) else {
                throw AuditError.invalidSigningInput
            }
            try validate(id: attestation.signature.signerID, work: &work)
            guard attestation.signature.bytes.count <= 256 else {
                throw AuditError.invalidSigningInput
            }
            try work.consume(attestation.signature.bytes.count + 1)
        }
    }

    fileprivate static func validate(content: ContentHash, limits: Limits, work: inout Work) throws {
        guard (0...limits.maximumContentBytes).contains(content.bytes.byteCount) else {
            throw AuditError.countLimitExceeded(.contentBytes, maximum: limits.maximumContentBytes)
        }
        guard (0...limits.maximumUnicodeScalars).contains(content.unicode.scalarCount) else {
            throw AuditError.countLimitExceeded(
                .unicodeScalars,
                maximum: limits.maximumUnicodeScalars
            )
        }
        guard !isZeroDigest(content.bytes.sha256), !isZeroDigest(content.unicode.sha256) else {
            throw AuditError.invalidSigningInput
        }
        try work.consume(2)
    }

    fileprivate static func validate(
        scalarCommitments: FixtureScalarCommitments,
        limits: Limits,
        work: inout Work
    ) throws {
        for commitment in [
            scalarCommitments.original,
            scalarCommitments.edited,
            scalarCommitments.saved,
            scalarCommitments.reloaded
        ] {
            guard (0...limits.maximumUnicodeScalars).contains(commitment.scalarCount) else {
                throw AuditError.countLimitExceeded(
                    .unicodeScalars,
                    maximum: limits.maximumUnicodeScalars
                )
            }
            guard !isZeroDigest(commitment.sha256) else {
                throw AuditError.invalidSigningInput
            }
            try work.consume()
        }
    }

    fileprivate static func validate(
        edit: UnicodeScalarEdit,
        from before: UnicodeHash,
        to after: UnicodeHash,
        limits: Limits,
        work: inout Work
    ) throws {
        let sequences = [
            edit.unchangedPrefix,
            edit.removedScalars,
            edit.insertedScalars,
            edit.unchangedSuffix
        ]
        for sequence in sequences {
            guard sequence.count <= limits.maximumUnicodeScalars else {
                throw AuditError.countLimitExceeded(
                    .unicodeScalars,
                    maximum: limits.maximumUnicodeScalars
                )
            }
        }
        guard edit.unchangedPrefix.count <= before.scalarCount,
            edit.removedScalars.count <= before.scalarCount - edit.unchangedPrefix.count,
            edit.unchangedSuffix.count
                == before.scalarCount - edit.unchangedPrefix.count - edit.removedScalars.count,
            edit.unchangedPrefix.count <= after.scalarCount,
            edit.insertedScalars.count <= after.scalarCount - edit.unchangedPrefix.count,
            edit.unchangedSuffix.count
                == after.scalarCount - edit.unchangedPrefix.count - edit.insertedScalars.count
        else {
            throw AuditError.invalidSigningInput
        }
        guard !edit.removedScalars.isEmpty || !edit.insertedScalars.isEmpty else {
            throw AuditError.invalidSigningInput
        }
        let firstBeforeChange = edit.removedScalars.first ?? edit.unchangedSuffix.first
        let firstAfterChange = edit.insertedScalars.first ?? edit.unchangedSuffix.first
        guard firstBeforeChange != firstAfterChange else {
            throw AuditError.invalidSigningInput
        }
        if let lastRemoved = edit.removedScalars.last,
            let lastInserted = edit.insertedScalars.last,
            lastRemoved == lastInserted
        {
            throw AuditError.invalidSigningInput
        }
        for sequence in sequences {
            for scalar in sequence {
                guard scalar <= 0x10_FFFF, !(0xD800...0xDFFF).contains(scalar) else {
                    throw AuditError.invalidSigningInput
                }
                try work.consume()
            }
        }
        let beforeDigest = try scalarDigest(
            edit.unchangedPrefix,
            edit.removedScalars,
            edit.unchangedSuffix,
            work: &work
        )
        let afterDigest = try scalarDigest(
            edit.unchangedPrefix,
            edit.insertedScalars,
            edit.unchangedSuffix,
            work: &work
        )
        guard beforeDigest == before.sha256, afterDigest == after.sha256 else {
            throw AuditError.invalidSigningInput
        }
    }

    fileprivate static func scalarDigest(
        _ prefix: [UInt32],
        _ changed: [UInt32],
        _ suffix: [UInt32],
        work: inout Work
    ) throws -> SHA256Digest {
        var hasher = SHA256()
        for sequence in [prefix, changed, suffix] {
            for scalar in sequence {
                var bigEndian = scalar.bigEndian
                withUnsafeBytes(of: &bigEndian) { bytes in
                    hasher.update(bufferPointer: bytes)
                }
                try work.consume()
            }
        }
        return SHA256Digest(validatedBytes: Array(hasher.finalize()))
    }

    fileprivate static func validate(detection: DetectionOutcome, work: inout Work) throws {
        switch detection {
        case .selected(let codePage):
            guard
                codePage == utf8DetectionCodePage
                    || SupportedCodePage(rawValue: codePage.rawValue) != nil
            else {
                throw AuditError.invalidSigningInput
            }
        case .ambiguous(let codePages):
            guard isCanonicalAmbiguity(codePages) else {
                throw AuditError.invalidSigningInput
            }
        case .rejected:
            break
        }
        try work.consume()
    }

    fileprivate static func validate(lineage: ExecutionLineage, work: inout Work) throws {
        try validate(reference: lineage.executor, work: &work)
        try validate(id: lineage.signerID, work: &work)
        guard !isZeroDigest(lineage.buildSHA256) else { throw AuditError.invalidSigningInput }
    }

    fileprivate static func validate(reference: RevisionReference, work: inout Work) throws {
        try validate(id: reference.id, work: &work)
    }

    fileprivate static func validate(id: StableID, work: inout Work) throws {
        let bytes = try work.stringData(id.rawValue)
        guard !bytes.isEmpty, bytes.count <= maximumIdentifierUTF8Bytes,
            bytes.allSatisfy({ byte in
                (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte)
                    || (0x61...0x7A).contains(byte) || byte == 0x2D || byte == 0x2E
                    || byte == 0x3A || byte == 0x5F
            })
        else { throw AuditError.invalidSigningInput }
    }

    fileprivate static func auditManifest(
        _ manifest: Manifest,
        trustPolicy: TrustPolicy,
        limits: Limits,
        findings: inout [Finding],
        verifications: inout [FixtureVerification],
        work: inout Work
    ) throws {
        let expected = SupportedCodePage.allCases.map(\.id)
        if manifest.sessionEncodingSchemaVersion != ComparisonSessionState.currentSchemaVersion
            || manifest.declaredSupportedCodePages != expected
            || manifest.codecSessionMappings != canonicalCodecSessionMappings
            || trustPolicy.approvedCodecArtifact.codec != manifest.codec
            || trustPolicy.approvedCodecArtifact.artifactSHA256 != manifest.codecArtifactSHA256
            || isZeroDigest(manifest.codecArtifactSHA256)
        {
            try appendFinding(
                Finding(code: .supportedEncodingManifestMismatch, subject: .manifest),
                to: &findings,
                limits: limits
            )
        }
        let grouped = Dictionary(grouping: manifest.fixtures, by: \.codePage)
        for supported in SupportedCodePage.allCases {
            try work.consume()
            let fixtures = grouped[supported.id] ?? []
            if fixtures.isEmpty {
                try appendFinding(
                    Finding(code: .missingFixture, subject: .codePage(supported.id)),
                    to: &findings,
                    limits: limits
                )
            } else if fixtures.count > 1 {
                try appendFinding(
                    Finding(code: .duplicateFixture, subject: .codePage(supported.id)),
                    to: &findings,
                    limits: limits
                )
            }
        }
        let trustedOracleSigners = try signerMap(
            trustPolicy.mappingOracleSigners,
            work: &work
        )
        for fixture in manifest.fixtures {
            try work.consume()
            let supported = SupportedCodePage(rawValue: fixture.codePage.rawValue) != nil
            let subject = FindingSubject.fixture(fixture.codePage)
            if !supported {
                try appendFinding(
                    Finding(code: .unexpectedFixture, subject: subject),
                    to: &findings,
                    limits: limits
                )
            }
            if fixture.mappingOracle.codePage != fixture.codePage {
                try appendFinding(
                    Finding(code: .mappingOracleCodePageMismatch, subject: subject),
                    to: &findings,
                    limits: limits
                )
            }
            let oracleData = try encodeMappingOracle(
                fixture.mappingOracle,
                includeSignature: true,
                work: &work
            )
            let oracleDigest = try sha256(oracleData, work: &work)
            let oracleSigningData = try encodeMappingOracleSigningPayload(fixture, work: &work)
            let oracleSigningDigest = try sha256(oracleSigningData, work: &work)
            let mappingVerified =
                fixture.mappingOracle.codePage == fixture.codePage
                && fixture.mappingOracle.fixtureScalarCommitments
                    == FixtureScalarCommitments(expectation: fixture.expectation)
                && verify(
                    signature: fixture.mappingOracle.signature,
                    prehash: oracleSigningDigest,
                    trustedSigners: trustedOracleSigners
                )
            if !mappingVerified {
                try appendFinding(
                    Finding(code: .unverifiedMappingOracle, subject: subject),
                    to: &findings,
                    limits: limits
                )
            }
            if !validExpectation(fixture) {
                try appendFinding(
                    Finding(code: .invalidFixtureExpectation, subject: subject),
                    to: &findings,
                    limits: limits
                )
            }
            verifications.append(
                FixtureVerification(
                    fixture: fixture.reference,
                    codePage: fixture.codePage,
                    mappingOracleSHA256: oracleDigest,
                    isSupported: supported,
                    isMappingOracleVerified: mappingVerified,
                    isFixtureValid: validExpectation(fixture)
                ))
        }
    }

    fileprivate static func initializeCells(
        plan: Plan,
        states: inout [CellKey: CellState],
        work: inout Work
    ) throws {
        let grouped = Dictionary(grouping: plan.manifest.fixtures, by: \.codePage)
        for codePage in SupportedCodePage.allCases {
            let fixtures = grouped[codePage.id] ?? []
            for stage in Stage.allCases {
                try work.consume()
                let fixture = fixtures.count == 1 ? fixtures[0].reference : nil
                let status: CompletenessStatus = fixtures.isEmpty ? .missing : fixtures.count > 1 ? .duplicate : .missing
                states[CellKey(codePage: codePage, stage: stage)] = CellState(
                    cell: CompletenessCell(
                        codePage: codePage,
                        fixture: fixture,
                        stage: stage,
                        evidenceCount: 0,
                        status: status
                    )
                )
            }
        }
    }

    fileprivate static func setCellStatus(
        codePage: CodePageID,
        fixture: RevisionReference,
        stage: Stage,
        count: Int,
        status: CompletenessStatus,
        states: inout [CellKey: CellState]
    ) {
        guard let supported = SupportedCodePage(rawValue: codePage.rawValue) else { return }
        let key = CellKey(codePage: supported, stage: stage)
        guard states[key]?.cell.fixture == fixture else { return }
        states[key] = CellState(
            cell: CompletenessCell(
                codePage: supported,
                fixture: fixture,
                stage: stage,
                evidenceCount: count,
                status: status
            ))
    }

    fileprivate static func audit(
        _ evidence: StageEvidence,
        request: StageRequest,
        fixture: Fixture,
        bundleIsCurrent: Bool,
        evidenceBundle: RevisionReference,
        trustedMeasurementSigners: [StableID: [UInt8]],
        approvedLineagesByIdentity: [SHA256Digest: ExecutionLineage],
        limits: Limits,
        findings: inout [Finding],
        work: inout Work
    ) throws -> CompletenessStatus {
        let subject = FindingSubject.stage(request.codePage, request.stage)
        var status = CompletenessStatus.complete
        if !bundleIsCurrent || evidence.bundle != evidenceBundle
            || evidence.bundleManifestSHA256 != request.manifestSHA256
            || evidence.requestSHA256 != request.requestSHA256
            || evidence.fixture != request.fixture || evidence.codePage != request.codePage
        {
            try appendFinding(
                Finding(code: .staleEvidence, subject: subject),
                to: &findings,
                limits: limits
            )
            status = .stale
        }
        if evidence.requestedStage != evidence.observation.stage
            || evidence.requestedStage != request.stage
        {
            try appendFinding(
                Finding(code: .wrongStageEvidence, subject: subject),
                to: &findings,
                limits: limits
            )
            return .wrongStage
        }
        if !evidence.origin.isMeasured {
            try appendFinding(
                Finding(code: .callerAssertionEvidence, subject: subject),
                to: &findings,
                limits: limits
            )
            return .assertionOnly
        }
        guard let attestation = evidence.attestation else {
            try appendFinding(
                Finding(code: .missingMeasurementAttestation, subject: subject),
                to: &findings,
                limits: limits
            )
            return .invalid
        }
        let lineageIdentity = try executionLineageIdentityDigest(
            attestation.execution.lineage,
            work: &work
        )
        let lineageApproved =
            approvedLineagesByIdentity[lineageIdentity] == attestation.execution.lineage
        if !lineageApproved {
            try appendFinding(
                Finding(code: .unapprovedExecutionLineage, subject: subject),
                to: &findings,
                limits: limits
            )
            status = .invalid
        }
        if attestation.execution.lineage.signerID != attestation.signature.signerID {
            try appendFinding(
                Finding(code: .signerIdentityMismatch, subject: subject),
                to: &findings,
                limits: limits
            )
            status = .invalid
        }
        let signingData = try encodeStageEvidence(evidence, includeSignature: false, work: &work)
        let signingDigest = try sha256(signingData, work: &work)
        if !verify(
            signature: attestation.signature,
            prehash: signingDigest,
            trustedSigners: trustedMeasurementSigners
        ) {
            try appendFinding(
                Finding(code: .unverifiedMeasurementAttestation, subject: subject),
                to: &findings,
                limits: limits
            )
            status = .invalid
        }
        let observationCodes = try mismatchCodes(
            evidence.observation,
            fixture: fixture,
            work: &work
        )
        for code in observationCodes {
            try appendFinding(Finding(code: code, subject: subject), to: &findings, limits: limits)
            status = .invalid
        }
        return status
    }

    fileprivate static func mismatchCodes(
        _ observation: Observation,
        fixture: Fixture,
        work: inout Work
    ) throws -> [FindingCode] {
        let expected = fixture.expectation
        switch observation {
        case .load(let value):
            var result: [FindingCode] = []
            if value.automaticDetection != expected.selection.automaticDetection {
                switch (value.automaticDetection, expected.selection.automaticDetection) {
                case (.ambiguous, _), (_, .ambiguous):
                    result.append(.ambiguityExpectationMismatch)
                default:
                    result.append(.automaticDetectionMismatch)
                }
            }
            if value.explicitlySelectedEncoding != expected.selection.explicitSelection
                || value.explicitlySelectedEncoding != fixture.codePage
            {
                result.append(.explicitSelectionMismatch)
            }
            if value.source != expected.original || value.loaded != expected.original {
                result.append(.originalHashMismatch)
            }
            return result
        case .compare(let value):
            return value.left == expected.original && value.right == expected.original
                && value.unicodeEqual && value.differenceCount == 0
                ? [] : [.comparisonMismatch]
        case .edit(let value):
            var result: [FindingCode] = []
            if value.before != expected.original { result.append(.originalHashMismatch) }
            let editMatches = try scalarEditsEqual(
                value.unicodeScalarDelta,
                expected.intendedEdit,
                work: &work
            )
            if value.after != expected.edited { result.append(.editedHashMismatch) }
            if !value.mutationApplied || !editMatches { result.append(.editMutationMismatch) }
            return result
        case .save(let value):
            var result: [FindingCode] = []
            if value.edited != expected.edited { result.append(.editedHashMismatch) }
            if value.saved != expected.saved { result.append(.savedHashMismatch) }
            if value.selectedEncoding != fixture.codePage { result.append(.explicitSelectionMismatch) }
            return result
        case .reload(let value):
            var result: [FindingCode] = []
            if value.saved != expected.saved { result.append(.savedHashMismatch) }
            if value.reloaded != expected.reloaded { result.append(.reloadedHashMismatch) }
            if value.selectedEncoding != fixture.codePage { result.append(.explicitSelectionMismatch) }
            return result
        case .byteComparison(let value):
            return value.saved == expected.saved && value.reloaded == expected.reloaded
                && value.saved.bytes == value.reloaded.bytes && value.bytesEqual
                ? [] : [.byteComparisonMismatch]
        }
    }

    fileprivate static func auditEvidenceOrder(
        plan: Plan,
        evidenceByCoordinate: [Coordinate: [StageEvidence]],
        cellStates: inout [CellKey: CellState],
        findings: inout [Finding],
        limits: Limits,
        work: inout Work
    ) throws {
        var auditedFixtures: Set<ExactFixtureKey> = []
        auditedFixtures.reserveCapacity(plan.manifest.fixtures.count)
        for fixture in plan.manifest.fixtures {
            try work.consume()
            let fixtureDigest = try identityDigest(fixture.reference, work: &work)
            let fixtureKey = ExactFixtureKey(
                fixtureDigest: fixtureDigest,
                codePage: fixture.codePage
            )
            guard auditedFixtures.insert(fixtureKey).inserted else { continue }
            var previous: StageEvidence?
            var previousDigest: SHA256Digest?
            var chainIsComplete = true
            for stage in Stage.allCases {
                try work.consume()
                let coordinate = Coordinate(
                    fixtureDigest: fixtureDigest,
                    codePage: fixture.codePage,
                    stage: stage
                )
                var items: [StageEvidence] = []
                if let candidates = evidenceByCoordinate[coordinate] {
                    items.reserveCapacity(candidates.count)
                    for item in candidates {
                        try work.consume()
                        if item.fixture == fixture.reference && item.codePage == fixture.codePage
                            && item.requestedStage == stage
                        {
                            items.append(item)
                        }
                    }
                }
                guard items.count == 1, let attestation = items[0].attestation
                else {
                    chainIsComplete = false
                    previous = nil
                    previousDigest = nil
                    continue
                }
                let item = items[0]
                var ordered = chainIsComplete
                if stage == .load {
                    ordered =
                        attestation.previousEvidenceSHA256 == nil
                        && ordered
                } else if let previous, let priorAttestation = previous.attestation {
                    ordered =
                        ordered
                        && attestation.execution.lineage
                            == priorAttestation.execution.lineage
                        && attestation.execution.runSHA256
                            == priorAttestation.execution.runSHA256
                        && attestation.signature.signerID
                            == priorAttestation.signature.signerID
                        && attestation.monotonicSequence > priorAttestation.monotonicSequence
                        && attestation.previousEvidenceSHA256 == previousDigest
                    if attestation.execution.lineage != priorAttestation.execution.lineage {
                        try appendFinding(
                            Finding(
                                code: .mixedExecutionLineage,
                                subject: .stage(fixture.codePage, stage)
                            ),
                            to: &findings,
                            limits: limits
                        )
                    }
                    if attestation.execution.runSHA256 != priorAttestation.execution.runSHA256 {
                        try appendFinding(
                            Finding(
                                code: .executionRunMismatch,
                                subject: .stage(fixture.codePage, stage)
                            ),
                            to: &findings,
                            limits: limits
                        )
                    }
                    if attestation.signature.signerID != priorAttestation.signature.signerID {
                        try appendFinding(
                            Finding(
                                code: .unstableLineageSigner,
                                subject: .stage(fixture.codePage, stage)
                            ),
                            to: &findings,
                            limits: limits
                        )
                    }
                } else {
                    ordered = false
                }
                if !ordered {
                    try appendFinding(
                        Finding(
                            code: .unorderedStageEvidence,
                            subject: .stage(fixture.codePage, stage)
                        ),
                        to: &findings,
                        limits: limits
                    )
                    if let supported = SupportedCodePage(rawValue: fixture.codePage.rawValue) {
                        let key = CellKey(codePage: supported, stage: stage)
                        if let cell = cellStates[key]?.cell,
                            cell.fixture == fixture.reference,
                            cell.status == .complete
                        {
                            cellStates[key] = CellState(
                                cell: CompletenessCell(
                                    codePage: supported,
                                    fixture: fixture.reference,
                                    stage: stage,
                                    evidenceCount: cell.evidenceCount,
                                    status: .invalid
                                ))
                        }
                    }
                }
                chainIsComplete = ordered
                previous = item
                let encoded = try encodeStageEvidence(item, includeSignature: true, work: &work)
                previousDigest = try sha256(encoded, work: &work)
            }
        }
    }

    fileprivate static func validExpectation(_ fixture: Fixture) -> Bool {
        let selection = fixture.expectation.selection
        guard selection.explicitSelection == fixture.codePage else { return false }
        switch selection.automaticDetection {
        case .ambiguous(let candidates):
            guard isCanonicalAmbiguity(candidates), candidates.contains(fixture.codePage)
            else { return false }
        case .selected(let codePage):
            guard codePage == fixture.codePage else { return false }
        case .rejected:
            return false
        }
        let expectation = fixture.expectation
        return fixture.fixtureArtifactSHA256 == expectation.original.bytes.sha256
            && fixture.mappingOracle.fixtureScalarCommitments
                == FixtureScalarCommitments(expectation: expectation)
            && expectation.original.unicode != expectation.edited.unicode
            && expectation.original != expectation.edited
            && fixture.expectation.edited == fixture.expectation.saved
            && fixture.expectation.saved == fixture.expectation.reloaded
    }

    fileprivate static func isCanonicalAmbiguity(_ codePages: [CodePageID]) -> Bool {
        if codePages == [utf8DetectionCodePage, SupportedCodePage.cp50220.id] { return true }
        let detectionOrder = [
            SupportedCodePage.cp932.id,
            SupportedCodePage.cp51932.id,
            SupportedCodePage.cp1250.id,
            SupportedCodePage.cp1251.id,
            SupportedCodePage.cp1252.id,
            SupportedCodePage.cp1253.id,
            SupportedCodePage.cp1254.id,
            SupportedCodePage.cp1255.id
        ]
        guard codePages.count > 1, codePages.count <= detectionOrder.count else { return false }
        var candidateIndex = codePages.startIndex
        for codePage in detectionOrder where candidateIndex < codePages.endIndex {
            if codePages[candidateIndex] == codePage {
                codePages.formIndex(after: &candidateIndex)
            }
        }
        return candidateIndex == codePages.endIndex
    }

    fileprivate static func scalarEditsEqual(
        _ left: UnicodeScalarEdit,
        _ right: UnicodeScalarEdit,
        work: inout Work
    ) throws -> Bool {
        for (leftSequence, rightSequence) in [
            (left.unchangedPrefix, right.unchangedPrefix),
            (left.removedScalars, right.removedScalars),
            (left.insertedScalars, right.insertedScalars),
            (left.unchangedSuffix, right.unchangedSuffix)
        ] {
            guard leftSequence.count == rightSequence.count else { return false }
            for (leftScalar, rightScalar) in zip(leftSequence, rightSequence) {
                try work.consume()
                if leftScalar != rightScalar { return false }
            }
        }
        return true
    }

    fileprivate static func signerMap(
        _ signers: [TrustedSigner],
        work: inout Work
    ) throws -> [StableID: [UInt8]] {
        var result: [StableID: [UInt8]] = [:]
        var duplicates: Set<StableID> = []
        for signer in signers {
            try work.consume(signer.publicKey.count + 1)
            if result.updateValue(signer.publicKey, forKey: signer.id) != nil {
                duplicates.insert(signer.id)
            }
        }
        for duplicate in duplicates {
            try work.consume()
            result.removeValue(forKey: duplicate)
        }
        return result
    }

    fileprivate static func verify(
        signature: Signature,
        prehash: SHA256Digest,
        trustedSigners: [StableID: [UInt8]]
    ) -> Bool {
        guard signature.bytes.count == 64,
            let rawKey = trustedSigners[signature.signerID], rawKey.count == 32,
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: Data(rawKey))
        else { return false }
        return key.isValidSignature(Data(signature.bytes), for: Data(prehash.bytes))
    }

    fileprivate static func encodeManifest(_ manifest: Manifest, work: inout Work) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-LIFECYCLE-MANIFEST-V3")
        try writer.appendReference(manifest.reference)
        try writer.appendReference(manifest.codec)
        try writer.appendDigest(manifest.codecArtifactSHA256)
        try writer.appendInt(manifest.sessionEncodingSchemaVersion)
        try writer.appendCount(manifest.declaredSupportedCodePages.count)
        for codePage in manifest.declaredSupportedCodePages {
            try writer.appendInt(codePage.rawValue)
        }
        try writer.appendCount(manifest.codecSessionMappings.count)
        for mapping in manifest.codecSessionMappings {
            try writer.appendInt(mapping.codePage.rawValue)
            try writer.appendString(mapping.codecEncodingIdentifier)
            try writer.appendString(mapping.sessionEncodingIdentifier)
        }
        try writer.appendCount(manifest.approvedExecutionLineages.count)
        for lineage in manifest.approvedExecutionLineages {
            try appendExecutionLineage(lineage, to: &writer)
        }
        try writer.appendCount(manifest.fixtures.count)
        for fixture in manifest.fixtures {
            let data = try encodeFixture(fixture, work: &writer.work)
            try writer.appendUInt64(UInt64(data.count))
            try writer.appendData(data)
        }
        work = writer.work
        return writer.data
    }

    fileprivate static func makeRequests(
        manifest: Manifest,
        manifestDigest: SHA256Digest,
        work: inout Work
    ) throws -> [StageRequest] {
        let stagesPerFixture = Stage.allCases.count
        guard stagesPerFixture > 0,
            manifest.fixtures.count <= work.limits.maximumEvidence / stagesPerFixture
        else {
            throw AuditError.countLimitExceeded(
                .evidence,
                maximum: work.limits.maximumEvidence
            )
        }
        var requests: [StageRequest] = []
        requests.reserveCapacity(manifest.fixtures.count * stagesPerFixture)
        for fixture in manifest.fixtures {
            try work.consume()
            let fixtureData = try encodeFixture(fixture, work: &work)
            let fixtureDigest = try sha256(fixtureData, work: &work)
            let oracleData = try encodeMappingOracle(
                fixture.mappingOracle,
                includeSignature: true,
                work: &work
            )
            let oracleDigest = try sha256(oracleData, work: &work)
            for stage in Stage.allCases {
                try work.consume()
                let ordinal = requests.count
                let unsigned = UnsignedStageRequest(
                    ordinal: ordinal,
                    fixture: fixture.reference,
                    codePage: fixture.codePage,
                    stage: stage,
                    manifest: manifest.reference,
                    manifestSHA256: manifestDigest,
                    fixtureSHA256: fixtureDigest,
                    mappingOracleSHA256: oracleDigest
                )
                let requestData = try encodeStageRequest(unsigned, work: &work)
                requests.append(
                    StageRequest(
                        ordinal: ordinal,
                        fixture: fixture.reference,
                        codePage: fixture.codePage,
                        stage: stage,
                        manifest: manifest.reference,
                        manifestSHA256: manifestDigest,
                        fixtureSHA256: fixtureDigest,
                        mappingOracleSHA256: oracleDigest,
                        requestSHA256: try sha256(requestData, work: &work)
                    ))
            }
        }
        return requests
    }

    fileprivate static func encodeFixture(_ fixture: Fixture, work: inout Work) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-FIXTURE-V3")
        try writer.appendReference(fixture.reference)
        try writer.appendInt(fixture.codePage.rawValue)
        try writer.appendDigest(fixture.fixtureArtifactSHA256)
        let oracle = try encodeMappingOracle(
            fixture.mappingOracle,
            includeSignature: true,
            work: &writer.work
        )
        try writer.appendUInt64(UInt64(oracle.count))
        try writer.appendData(oracle)
        try appendFixtureExpectation(fixture.expectation, to: &writer)
        work = writer.work
        return writer.data
    }

    fileprivate static func encodeMappingOracleSigningPayload(
        _ fixture: Fixture,
        work: inout Work
    ) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-MAPPING-ORACLE-SIGNING-PAYLOAD-V3")
        let oracle = try encodeMappingOracle(
            fixture.mappingOracle,
            includeSignature: false,
            work: &writer.work
        )
        try writer.appendUInt64(UInt64(oracle.count))
        try writer.appendData(oracle)
        try writer.appendReference(fixture.reference)
        try writer.appendInt(fixture.codePage.rawValue)
        try writer.appendDigest(fixture.fixtureArtifactSHA256)
        try appendFixtureExpectation(fixture.expectation, to: &writer)
        work = writer.work
        return writer.data
    }

    fileprivate static func appendFixtureExpectation(
        _ expectation: FixtureExpectation,
        to writer: inout Writer
    ) throws {
        try writer.appendContent(expectation.original)
        try writer.appendContent(expectation.edited)
        try writer.appendContent(expectation.saved)
        try writer.appendContent(expectation.reloaded)
        try writer.appendDetection(expectation.selection.automaticDetection)
        try writer.appendInt(expectation.selection.explicitSelection.rawValue)
        try writer.appendScalarEdit(expectation.intendedEdit)
    }

    fileprivate static func encodeMappingOracle(
        _ oracle: MappingOracle,
        includeSignature: Bool,
        work: inout Work
    ) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-MAPPING-ORACLE-V3")
        try writer.appendReference(oracle.reference)
        try writer.appendInt(oracle.codePage.rawValue)
        try writer.appendString(oracle.sourceIdentifier)
        try writer.appendDigest(oracle.sourceArtifactSHA256)
        try writer.appendDigest(oracle.mappingTableSHA256)
        try writer.appendInt(oracle.mappingCardinality)
        try writer.appendUnicode(oracle.fixtureScalarCommitments.original)
        try writer.appendUnicode(oracle.fixtureScalarCommitments.edited)
        try writer.appendUnicode(oracle.fixtureScalarCommitments.saved)
        try writer.appendUnicode(oracle.fixtureScalarCommitments.reloaded)
        try writer.appendString(oracle.signature.signerID.rawValue)
        if includeSignature {
            try writer.appendUInt64(UInt64(oracle.signature.bytes.count))
            try writer.appendRaw(oracle.signature.bytes)
        }
        work = writer.work
        return writer.data
    }

    fileprivate static func encodeStageRequest(_ request: UnsignedStageRequest, work: inout Work) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-STAGE-REQUEST-V3")
        try writer.appendInt(request.ordinal)
        try writer.appendReference(request.fixture)
        try writer.appendInt(request.codePage.rawValue)
        try writer.appendInt(request.stage.rawValue)
        try writer.appendReference(request.manifest)
        try writer.appendDigest(request.manifestSHA256)
        try writer.appendDigest(request.fixtureSHA256)
        try writer.appendDigest(request.mappingOracleSHA256)
        work = writer.work
        return writer.data
    }

    fileprivate static func encodeRequests(_ requests: [StageRequest], work: inout Work) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-REQUEST-SET-V3")
        try writer.appendCount(requests.count)
        for request in requests {
            try writer.appendInt(request.ordinal)
            try writer.appendDigest(request.requestSHA256)
        }
        work = writer.work
        return writer.data
    }

    fileprivate static func encodeTrustPolicy(
        _ trustPolicy: TrustPolicy,
        work: inout Work
    ) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-TRUST-POLICY-V3")
        try writer.appendReference(trustPolicy.approvedCodecArtifact.codec)
        try writer.appendDigest(trustPolicy.approvedCodecArtifact.artifactSHA256)
        for signers in [trustPolicy.mappingOracleSigners, trustPolicy.measurementSigners] {
            var records: [Data] = []
            records.reserveCapacity(signers.count)
            for signer in signers {
                var record = Writer(work: writer.work)
                try record.appendString(signer.id.rawValue)
                try record.appendUInt64(UInt64(signer.publicKey.count))
                try record.appendRaw(signer.publicKey)
                writer.work = record.work
                records.append(record.data)
            }
            records = try stableSorted(records, work: &writer.work, by: dataLess)
            try writer.appendCount(records.count)
            for record in records {
                try writer.appendUInt64(UInt64(record.count))
                try writer.appendData(record)
            }
        }
        work = writer.work
        return writer.data
    }

    fileprivate static func encodeStageEvidence(
        _ evidence: StageEvidence,
        includeSignature: Bool,
        work: inout Work
    ) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-STAGE-EVIDENCE-V3")
        try writer.appendReference(evidence.bundle)
        try writer.appendDigest(evidence.bundleManifestSHA256)
        try writer.appendReference(evidence.fixture)
        try writer.appendInt(evidence.codePage.rawValue)
        try writer.appendInt(evidence.requestedStage.rawValue)
        try writer.appendDigest(evidence.requestSHA256)
        try appendObservation(evidence.observation, to: &writer)
        try writer.appendString(evidence.origin.rawValue)
        if let attestation = evidence.attestation {
            try writer.appendUInt8(1)
            try appendExecutionLineage(attestation.execution.lineage, to: &writer)
            try writer.appendDigest(attestation.execution.runSHA256)
            try writer.appendUInt64(attestation.monotonicSequence)
            try writer.appendOptionalDigest(attestation.previousEvidenceSHA256)
            try writer.appendString(attestation.signature.signerID.rawValue)
            if includeSignature {
                try writer.appendUInt64(UInt64(attestation.signature.bytes.count))
                try writer.appendRaw(attestation.signature.bytes)
            }
        } else {
            try writer.appendUInt8(0)
        }
        work = writer.work
        return writer.data
    }

    fileprivate static func appendExecutionLineage(
        _ lineage: ExecutionLineage,
        to writer: inout Writer
    ) throws {
        try writer.appendReference(lineage.executor)
        try writer.appendDigest(lineage.buildSHA256)
        try writer.appendString(lineage.signerID.rawValue)
    }

    fileprivate static func appendObservation(_ observation: Observation, to writer: inout Writer) throws {
        try writer.appendInt(observation.stage.rawValue)
        switch observation {
        case .load(let value):
            try writer.appendDetection(value.automaticDetection)
            try writer.appendInt(value.explicitlySelectedEncoding.rawValue)
            try writer.appendContent(value.source)
            try writer.appendContent(value.loaded)
        case .compare(let value):
            try writer.appendContent(value.left)
            try writer.appendContent(value.right)
            try writer.appendBool(value.unicodeEqual)
            try writer.appendInt(value.differenceCount)
        case .edit(let value):
            try writer.appendContent(value.before)
            try writer.appendContent(value.after)
            try writer.appendBool(value.mutationApplied)
            try writer.appendScalarEdit(value.unicodeScalarDelta)
        case .save(let value):
            try writer.appendContent(value.edited)
            try writer.appendContent(value.saved)
            try writer.appendInt(value.selectedEncoding.rawValue)
        case .reload(let value):
            try writer.appendContent(value.saved)
            try writer.appendContent(value.reloaded)
            try writer.appendInt(value.selectedEncoding.rawValue)
        case .byteComparison(let value):
            try writer.appendContent(value.saved)
            try writer.appendContent(value.reloaded)
            try writer.appendBool(value.bytesEqual)
        }
    }

    fileprivate static func encodeEvidenceBundle(_ evidence: EvidenceBundle, work: inout Work) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-EVIDENCE-BUNDLE-V3")
        try writer.appendReference(evidence.reference)
        try writer.appendReference(evidence.manifest)
        try writer.appendDigest(evidence.manifestSHA256)
        var records: [Data] = []
        records.reserveCapacity(evidence.stages.count)
        var framedByteCount = writer.data.count
        guard framedByteCount <= writer.work.limits.maximumCanonicalBytes - 8 else {
            throw AuditError.canonicalDataTooLarge(
                maximumBytes: writer.work.limits.maximumCanonicalBytes
            )
        }
        framedByteCount += 8
        for item in evidence.stages {
            let data = try encodeStageEvidence(item, includeSignature: true, work: &writer.work)
            guard data.count <= writer.work.limits.maximumCanonicalBytes,
                records.count < writer.work.limits.maximumEvidence,
                framedByteCount <= writer.work.limits.maximumCanonicalBytes - 8,
                data.count <= writer.work.limits.maximumCanonicalBytes - framedByteCount - 8
            else {
                throw AuditError.canonicalDataTooLarge(
                    maximumBytes: writer.work.limits.maximumCanonicalBytes
                )
            }
            framedByteCount += 8 + data.count
            records.append(data)
        }
        records = try stableSorted(records, work: &writer.work, by: dataLess)
        try writer.appendCount(records.count)
        for data in records {
            try writer.appendUInt64(UInt64(data.count))
            try writer.appendData(data)
        }
        work = writer.work
        return writer.data
    }

    fileprivate static func encodeOracleSet(_ fixtures: [Fixture], work: inout Work) throws -> Data {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-CODE-PAGE-ORACLE-SET-V3")
        var records: [Data] = []
        records.reserveCapacity(fixtures.count)
        var framedByteCount = writer.data.count
        guard framedByteCount <= writer.work.limits.maximumCanonicalBytes - 8 else {
            throw AuditError.canonicalDataTooLarge(
                maximumBytes: writer.work.limits.maximumCanonicalBytes
            )
        }
        framedByteCount += 8
        for fixture in fixtures {
            let data = try encodeMappingOracle(
                fixture.mappingOracle,
                includeSignature: true,
                work: &writer.work
            )
            guard data.count <= writer.work.limits.maximumCanonicalBytes,
                records.count < writer.work.limits.maximumFixtures,
                framedByteCount <= writer.work.limits.maximumCanonicalBytes - 8,
                data.count <= writer.work.limits.maximumCanonicalBytes - framedByteCount - 8
            else {
                throw AuditError.canonicalDataTooLarge(
                    maximumBytes: writer.work.limits.maximumCanonicalBytes
                )
            }
            framedByteCount += 8 + data.count
            records.append(data)
        }
        records = try stableSorted(records, work: &writer.work, by: dataLess)
        try writer.appendCount(records.count)
        for data in records {
            try writer.appendUInt64(UInt64(data.count))
            try writer.appendData(data)
        }
        work = writer.work
        return writer.data
    }

    fileprivate static func sha256(_ data: Data, work: inout Work) throws -> SHA256Digest {
        var hasher = SHA256()
        var offset = 0
        while offset < data.count {
            let end = min(offset + work.limits.cancellationCheckInterval, data.count)
            try work.consume(end - offset + 1)
            hasher.update(data: data[offset..<end])
            offset = end
        }
        return SHA256Digest(validatedBytes: Array(hasher.finalize()))
    }

    fileprivate static func dataLess(
        _ left: Data,
        _ right: Data,
        work: inout Work
    ) throws -> Bool {
        let count = min(left.count, right.count)
        return try left.withUnsafeBytes { leftBytes in
            try right.withUnsafeBytes { rightBytes in
                let leftBuffer = leftBytes.bindMemory(to: UInt8.self)
                let rightBuffer = rightBytes.bindMemory(to: UInt8.self)
                var offset = 0
                while offset < count {
                    let end = min(offset + work.limits.cancellationCheckInterval, count)
                    try work.consume(end - offset + 1)
                    for index in offset..<end where leftBuffer[index] != rightBuffer[index] {
                        return leftBuffer[index] < rightBuffer[index]
                    }
                    offset = end
                }
                return left.count < right.count
            }
        }
    }

    fileprivate static func appendFinding(
        _ finding: Finding,
        to findings: inout [Finding],
        limits: Limits
    ) throws {
        guard findings.count < limits.maximumFindings else {
            throw AuditError.findingLimitExceeded(maximum: limits.maximumFindings)
        }
        findings.append(finding)
    }

    fileprivate static func sortedFindings(
        _ findings: [Finding],
        limits: Limits,
        work: inout Work
    ) throws -> [Finding] {
        guard findings.count <= limits.maximumFindings else {
            throw AuditError.findingLimitExceeded(maximum: limits.maximumFindings)
        }
        var uniqueIDs: Set<Finding.ID> = []
        var unique: [Finding] = []
        unique.reserveCapacity(findings.count)
        for finding in findings {
            try work.consume(finding.id.rawValue.utf8.count + 1)
            if uniqueIDs.insert(finding.id).inserted {
                unique.append(finding)
            }
        }
        return try stableSorted(unique, work: &work) { left, right, work in
            try work.consume(65)
            if left.severity != right.severity { return left.severity > right.severity }
            if left.code != right.code {
                return compareUTF8(left.code.rawValue, right.code.rawValue) < 0
            }
            return left.id < right.id
        }
    }

    fileprivate static func findingMessage(_ code: FindingCode) -> String {
        switch code {
        case .invalidManifest: "Manifest identity or structure is invalid; contents are redacted."
        case .supportedEncodingManifestMismatch:
            "Manifest does not exactly bind current codec and session code-page support."
        case .missingFixture: "Supported code page has no fixture."
        case .duplicateFixture: "Supported code page has duplicate fixtures."
        case .unexpectedFixture: "Fixture names a code page outside current supported inventory."
        case .staleFixture: "Fixture revision or content binding is stale."
        case .mappingOracleCodePageMismatch: "Mapping oracle names another code page."
        case .unverifiedMappingOracle: "Mapping oracle signature is absent, untrusted, or invalid."
        case .invalidFixtureExpectation: "Fixture lifecycle expectation is inconsistent."
        case .staleEvidenceBundle: "Evidence bundle does not bind exact manifest revision and digest."
        case .missingEvidence: "Required lifecycle stage has no evidence."
        case .duplicateEvidence: "Required lifecycle stage has duplicate evidence."
        case .unexpectedEvidence: "Evidence does not match a requested lifecycle coordinate."
        case .staleEvidence: "Evidence does not bind exact current stage request."
        case .wrongStageEvidence: "Evidence payload belongs to another lifecycle stage."
        case .unorderedStageEvidence: "Evidence does not continue strict signed lifecycle order."
        case .mixedExecutionLineage: "Lifecycle stages were measured by different execution lineages."
        case .executionRunMismatch: "Lifecycle stage execution run differs from the preceding stage."
        case .unapprovedExecutionLineage:
            "Executor revision, build artifact, and signer lineage is not approved by manifest."
        case .signerIdentityMismatch:
            "Measurement attestation signer identity differs from its execution lineage signer."
        case .unstableLineageSigner:
            "Execution lineage changed measurement signer within one lifecycle."
        case .callerAssertionEvidence: "Caller assertion cannot establish measured execution."
        case .missingMeasurementAttestation: "Measured evidence lacks executor attestation."
        case .unverifiedMeasurementAttestation:
            "Executor attestation signature is absent, untrusted, or invalid."
        case .ambiguityExpectationMismatch: "Automatic ambiguity result differs from fixture expectation."
        case .automaticDetectionMismatch: "Automatic detection result differs from fixture expectation."
        case .explicitSelectionMismatch: "Explicit selected code page differs from fixture expectation."
        case .originalHashMismatch: "Original byte or Unicode hash differs from fixture expectation."
        case .editedHashMismatch: "Edited byte or Unicode hash differs from fixture expectation."
        case .editMutationMismatch:
            "Edit mutation state or Unicode scalar delta differs from fixture expectation."
        case .savedHashMismatch: "Saved byte or Unicode hash differs from fixture expectation."
        case .reloadedHashMismatch: "Reloaded byte or Unicode hash differs from fixture expectation."
        case .comparisonMismatch: "Comparison result or measured inputs differ from expectation."
        case .byteComparisonMismatch: "Saved and reloaded bytes are not exactly equal as expected."
        }
    }

    fileprivate static func frame(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }

    fileprivate static func hex(_ bytes: [UInt8]) -> String {
        let alphabet = Array("0123456789abcdef".utf8)
        var result = [UInt8]()
        result.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            result.append(alphabet[Int(byte >> 4)])
            result.append(alphabet[Int(byte & 0x0F)])
        }
        return String(decoding: result, as: UTF8.self)
    }

    fileprivate static func stableSorted<Element>(
        _ values: [Element],
        work: inout Work,
        by areInIncreasingOrder: (Element, Element, inout Work) throws -> Bool
    ) throws -> [Element] {
        guard values.count > 1 else { return values }
        var source = values
        var width = 1
        while width < source.count {
            try work.consume()
            var destination: [Element] = []
            destination.reserveCapacity(source.count)
            var start = 0
            while start < source.count {
                try work.consume()
                let middle = min(start + width, source.count)
                let end = min(middle + width, source.count)
                var left = start
                var right = middle
                while left < middle && right < end {
                    try work.consume()
                    if try areInIncreasingOrder(source[right], source[left], &work) {
                        destination.append(source[right])
                        right += 1
                    } else {
                        destination.append(source[left])
                        left += 1
                    }
                }
                while left < middle {
                    try work.consume()
                    destination.append(source[left])
                    left += 1
                }
                while right < end {
                    try work.consume()
                    destination.append(source[right])
                    right += 1
                }
                start = end
            }
            source = destination
            guard width <= source.count / 2 else { break }
            width *= 2
        }
        return source
    }

    fileprivate static func compareUTF8(_ left: String, _ right: String) -> Int {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        while true {
            switch (leftIterator.next(), rightIterator.next()) {
            case (let leftByte?, let rightByte?):
                if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
            case (.none, .none):
                return 0
            case (.none, .some):
                return -1
            case (.some, .none):
                return 1
            }
        }
    }

    fileprivate static func byteExactStringEqual(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }

    fileprivate static func identityDigest(
        _ reference: RevisionReference,
        work: inout Work
    ) throws -> SHA256Digest {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-REVISION-IDENTITY-V2")
        try writer.appendReference(reference)
        work = writer.work
        return try sha256(writer.data, work: &work)
    }

    fileprivate static func executionLineageIdentityDigest(
        _ lineage: ExecutionLineage,
        work: inout Work
    ) throws -> SHA256Digest {
        var writer = Writer(work: work)
        try writer.appendDomain("MACMERGE-EXECUTION-LINEAGE-IDENTITY-V2")
        try writer.appendReference(lineage.executor)
        try writer.appendDigest(lineage.buildSHA256)
        work = writer.work
        return try sha256(writer.data, work: &work)
    }

    fileprivate static func isZeroDigest(_ digest: SHA256Digest) -> Bool {
        digest.bytes.allSatisfy { $0 == 0 }
    }

    fileprivate static func compareBytes(_ left: [UInt8], _ right: [UInt8]) -> Int {
        for (leftByte, rightByte) in zip(left, right) where leftByte != rightByte {
            return leftByte < rightByte ? -1 : 1
        }
        if left.count == right.count { return 0 }
        return left.count < right.count ? -1 : 1
    }

}
