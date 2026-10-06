import CryptoKit
import Foundation

public struct DiffOracleSHA256: Comparable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let byteCount = 32

    public let bytes: [UInt8]

    fileprivate var isZero: Bool { bytes.allSatisfy { $0 == 0 } }

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else {
            throw DiffOracleManifestError.invalidSHA256
        }
        self.bytes = bytes
    }

    public init(hex: String) throws {
        guard hex.utf8.count == Self.byteCount * 2, hex == hex.lowercased() else {
            throw DiffOracleManifestError.invalidSHA256
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Self.byteCount)
        var index = hex.utf8.startIndex
        for _ in 0..<Self.byteCount {
            let next = hex.utf8.index(index, offsetBy: 2)
            let high = hex.utf8[index]
            let low = hex.utf8[hex.utf8.index(after: index)]
            guard let highNibble = Self.hexNibble(high), let lowNibble = Self.hexNibble(low) else {
                throw DiffOracleManifestError.invalidSHA256
            }
            bytes.append(highNibble << 4 | lowNibble)
            index = next
        }
        try self.init(bytes: bytes)
    }

    public var hex: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.bytes.lexicographicallyPrecedes(right.bytes)
    }

    public var description: String { "DiffOracleSHA256(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["digest": "<redacted>"], displayStyle: .struct)
    }

    private static func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 97...102: byte - 87
        default: nil
        }
    }
}

/// Opaque corpus identity. Text and path-shaped corpus identifiers cannot be represented.
public struct DiffOracleCorpusID: Comparable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let byteCount = DiffOracleSHA256.byteCount

    public let bytes: [UInt8]

    /// Derives a domain-separated opaque ID from a nonzero stable source identity.
    public init(sourceIdentitySHA256: DiffOracleSHA256) throws {
        guard !sourceIdentitySHA256.isZero else {
            throw DiffOracleManifestError.invalidCorpusID
        }
        var input = Data("com.macmerge.diff-oracle-corpus-id.v1".utf8)
        input.append(0)
        input.append(contentsOf: sourceIdentitySHA256.bytes)
        try self.init(canonicalBytes: Array(SHA256.hash(data: input)))
    }

    fileprivate init(canonicalBytes: [UInt8]) throws {
        guard canonicalBytes.count == Self.byteCount, !canonicalBytes.allSatisfy({ $0 == 0 }) else {
            throw DiffOracleManifestError.invalidCorpusID
        }
        bytes = canonicalBytes
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.bytes.lexicographicallyPrecedes(right.bytes)
    }

    public var description: String { "DiffOracleCorpusID(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["corpusID": "<redacted>"], displayStyle: .struct)
    }
}

/// Trusted evidence that a path-indexing key was generated under an approved entropy policy.
public struct DiffOraclePathKeyStrengthAttestation: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let minimumEntropyBits: UInt16 = 256

    public let policyVersion: UInt32
    public let attestedEntropyBits: UInt16
    public let keyIdentifierSHA256: DiffOracleSHA256
    public let evidenceSHA256: DiffOracleSHA256

    public init(
        policyVersion: UInt32,
        attestedEntropyBits: UInt16,
        keyIdentifierSHA256: DiffOracleSHA256,
        evidenceSHA256: DiffOracleSHA256
    ) {
        self.policyVersion = policyVersion
        self.attestedEntropyBits = attestedEntropyBits
        self.keyIdentifierSHA256 = keyIdentifierSHA256
        self.evidenceSHA256 = evidenceSHA256
    }

    public var description: String { "DiffOraclePathKeyStrengthAttestation(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["attestation": "<redacted>"], displayStyle: .struct)
    }
}

/// Secret HMAC key admitted only after an external trust boundary verifies key-generation evidence.
public struct DiffOraclePathHMACKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let key: SymmetricKey

    public init(
        secretKey: Data,
        strengthAttestation: DiffOraclePathKeyStrengthAttestation,
        verifyStrengthAttestation: @Sendable (DiffOraclePathKeyStrengthAttestation) throws -> Bool
    ) throws {
        guard secretKey.count == DiffOracleSHA256.byteCount else {
            throw DiffOracleManifestError.invalidPathKey
        }
        let copiedSecret = Array(secretKey)
        let keyIdentifier = try DiffOracleSHA256(bytes: Array(SHA256.hash(data: copiedSecret)))
        guard
            strengthAttestation.policyVersion > 0,
            strengthAttestation.attestedEntropyBits >= DiffOraclePathKeyStrengthAttestation.minimumEntropyBits,
            !strengthAttestation.keyIdentifierSHA256.isZero,
            !strengthAttestation.evidenceSHA256.isZero,
            strengthAttestation.keyIdentifierSHA256 == keyIdentifier
        else {
            throw DiffOracleManifestError.invalidPathKey
        }
        do {
            guard try verifyStrengthAttestation(strengthAttestation) else {
                throw DiffOracleManifestError.invalidPathKey
            }
        } catch DiffOracleManifestError.cancelled {
            throw DiffOracleManifestError.cancelled
        } catch is CancellationError {
            throw DiffOracleManifestError.cancelled
        }
        guard !Task.isCancelled else {
            throw DiffOracleManifestError.cancelled
        }
        key = SymmetricKey(data: copiedSecret)
    }

    fileprivate var symmetricKey: SymmetricKey { key }

    public var description: String { "DiffOraclePathHMACKey(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["key": "<redacted>"], displayStyle: .struct)
    }
}

/// Opaque output of a trusted keyed path-indexing function. Raw repository paths never enter this manifest.
public struct DiffOraclePathKey: Comparable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let byteCount = 32

    public let bytes: [UInt8]

    fileprivate init(canonicalBytes: [UInt8]) throws {
        guard canonicalBytes.count == Self.byteCount, !canonicalBytes.allSatisfy({ $0 == 0 }) else {
            throw DiffOracleManifestError.invalidPathKey
        }
        bytes = canonicalBytes
    }

    public init(testingDataRelativePath: DiffOracleIdentifier, key: DiffOraclePathHMACKey) throws {
        let value = testingDataRelativePath.rawValue
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard value.hasPrefix("Testing/Data/"),
            !value.hasSuffix("/"),
            !value.contains("\\"),
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw DiffOracleManifestError.invalidPathKey
        }
        var input = Data("com.macmerge.diff-oracle-testing-data-path.v1".utf8)
        input.append(0)
        input.append(contentsOf: value.utf8)
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: input,
            using: key.symmetricKey
        )
        try self.init(canonicalBytes: Array(authenticationCode))
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.bytes.lexicographicallyPrecedes(right.bytes)
    }

    public var description: String { "DiffOraclePathKey(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["pathKey": "<redacted>"], displayStyle: .struct)
    }
}

public struct DiffOracleGitObjectID: Comparable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let hexadecimalCharacterCount = 40

    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard rawValue.utf8.count == Self.hexadecimalCharacterCount,
            rawValue == rawValue.lowercased(),
            rawValue.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            rawValue.utf8.contains(where: { $0 != 48 })
        else {
            throw DiffOracleManifestError.invalidGitObjectID
        }
        self.rawValue = rawValue
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }

    public var description: String { "DiffOracleGitObjectID(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["objectID": "<redacted>"], displayStyle: .struct)
    }
}

public struct DiffOracleIdentifier: Comparable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let hardMaximumUTF8ByteCount = 4 * 1_024

    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty,
            rawValue.utf8.count <= Self.hardMaximumUTF8ByteCount,
            rawValue.unicodeScalars.allSatisfy({ $0.value >= 0x20 && !(0x7F...0x9F).contains($0.value) })
        else {
            throw DiffOracleManifestError.invalidIdentifier
        }
        let normalized = rawValue.precomposedStringWithCanonicalMapping
        guard rawValue.utf8.elementsEqual(normalized.utf8) else {
            throw DiffOracleManifestError.invalidIdentifier
        }
        self.rawValue = normalized
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue.utf8.lexicographicallyPrecedes(right.rawValue.utf8)
    }

    public var description: String { "DiffOracleIdentifier(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["identifier": "<redacted>"], displayStyle: .struct)
    }
}

public enum DiffOracleCorpusOrigin: Hashable, Sendable {
    /// One fully expanded `Testing/GoogleTest/DiffWrapper/DiffWrapper_test.cpp` case.
    case diffWrapper(testName: DiffOracleIdentifier, caseID: DiffOracleSHA256)
    /// One `Testing/Data` file, indexed by a trusted secret-keyed, domain-separated path key.
    case testingData(pathKey: DiffOraclePathKey)
}

public enum DiffOracleCorpusDisposition: Hashable, Sendable {
    case required(fixtureIDs: [DiffOracleIdentifier])
    case excluded(reasonID: DiffOracleIdentifier)
}

public struct DiffOracleCorpusManifestEntry: Hashable, Sendable {
    public let id: DiffOracleCorpusID
    public let revision: UInt64
    public let origin: DiffOracleCorpusOrigin
    public let bytesSHA256: DiffOracleSHA256
    public let disposition: DiffOracleCorpusDisposition

    public init(
        id: DiffOracleCorpusID,
        revision: UInt64,
        origin: DiffOracleCorpusOrigin,
        bytesSHA256: DiffOracleSHA256,
        disposition: DiffOracleCorpusDisposition
    ) {
        self.id = id
        self.revision = revision
        self.origin = origin
        self.bytesSHA256 = bytesSHA256
        self.disposition = disposition
    }
}

/// Caller-provided observation. This type performs no file access or repository discovery.
public struct DiffOracleCorpusRecord: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let id: DiffOracleCorpusID
    public let revision: UInt64
    public let origin: DiffOracleCorpusOrigin
    public let bytes: Data

    public init(
        id: DiffOracleCorpusID,
        revision: UInt64,
        origin: DiffOracleCorpusOrigin,
        bytes: Data
    ) throws {
        guard bytes.count <= DiffOracleVerificationLimits.hardMaximumRecordBytes else {
            throw DiffOracleManifestError.inputTooLarge
        }
        self.id = id
        self.revision = revision
        self.origin = origin
        self.bytes = Data(Array(bytes))
    }

    public var description: String { "DiffOracleCorpusRecord(bytes: \(bytes.count), contents: <redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["id": "<redacted>", "revision": revision, "byteCount": bytes.count, "bytes": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// Provenance captured by the Windows oracle for one normalized golden result.
public struct DiffOracleGoldenProvenance: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let winMergeCommit: DiffOracleGitObjectID
    public let windowsXDiffTree: DiffOracleGitObjectID
    public let topLevelLibXDiffCommit: DiffOracleGitObjectID
    public let topLevelLibXDiffTree: DiffOracleGitObjectID
    public let nestedLibXDiffCommit: DiffOracleGitObjectID
    public let nestedLibXDiffTree: DiffOracleGitObjectID
    public let oracleExecutableSHA256: DiffOracleSHA256
    public let generatorVersion: DiffOracleIdentifier
    public let generatorExecutableSHA256: DiffOracleSHA256
    public let generatorSchemaSHA256: DiffOracleSHA256
    public let generatorConfigurationSHA256: DiffOracleSHA256
    public let architecture: DiffOracleIdentifier
    public let buildConfiguration: DiffOracleIdentifier

    public init(
        winMergeCommit: DiffOracleGitObjectID,
        windowsXDiffTree: DiffOracleGitObjectID,
        topLevelLibXDiffCommit: DiffOracleGitObjectID,
        topLevelLibXDiffTree: DiffOracleGitObjectID,
        nestedLibXDiffCommit: DiffOracleGitObjectID,
        nestedLibXDiffTree: DiffOracleGitObjectID,
        oracleExecutableSHA256: DiffOracleSHA256,
        generatorVersion: DiffOracleIdentifier,
        generatorExecutableSHA256: DiffOracleSHA256,
        generatorSchemaSHA256: DiffOracleSHA256,
        generatorConfigurationSHA256: DiffOracleSHA256,
        architecture: DiffOracleIdentifier,
        buildConfiguration: DiffOracleIdentifier
    ) {
        self.winMergeCommit = winMergeCommit
        self.windowsXDiffTree = windowsXDiffTree
        self.topLevelLibXDiffCommit = topLevelLibXDiffCommit
        self.topLevelLibXDiffTree = topLevelLibXDiffTree
        self.nestedLibXDiffCommit = nestedLibXDiffCommit
        self.nestedLibXDiffTree = nestedLibXDiffTree
        self.oracleExecutableSHA256 = oracleExecutableSHA256
        self.generatorVersion = generatorVersion
        self.generatorExecutableSHA256 = generatorExecutableSHA256
        self.generatorSchemaSHA256 = generatorSchemaSHA256
        self.generatorConfigurationSHA256 = generatorConfigurationSHA256
        self.architecture = architecture
        self.buildConfiguration = buildConfiguration
    }

    public var description: String { "DiffOracleGoldenProvenance(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["provenance": "<redacted>"], displayStyle: .struct)
    }
}

/// Clean Mac-side identities supplied by trusted CI observations, never inferred by this module.
public struct DiffOracleMacSourceProvenance: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let macMergeCommit: DiffOracleGitObjectID
    public let patchedXDiffContentManifestSHA256: DiffOracleSHA256
    public let cBridgeSourceSHA256: DiffOracleSHA256
    public let swiftDiffSourceSHA256: DiffOracleSHA256
    public let trustedExtractorVersion: DiffOracleIdentifier
    public let trustedExtractorExecutableSHA256: DiffOracleSHA256
    public let trustedExtractorSchemaSHA256: DiffOracleSHA256
    public let trustedExtractorConfigurationSHA256: DiffOracleSHA256
    public let sourceTreeInventorySHA256: DiffOracleSHA256
    public let sourceTreeInventoryEntryCount: UInt64

    public init(
        macMergeCommit: DiffOracleGitObjectID,
        patchedXDiffContentManifestSHA256: DiffOracleSHA256,
        cBridgeSourceSHA256: DiffOracleSHA256,
        swiftDiffSourceSHA256: DiffOracleSHA256,
        trustedExtractorVersion: DiffOracleIdentifier,
        trustedExtractorExecutableSHA256: DiffOracleSHA256,
        trustedExtractorSchemaSHA256: DiffOracleSHA256,
        trustedExtractorConfigurationSHA256: DiffOracleSHA256,
        sourceTreeInventorySHA256: DiffOracleSHA256,
        sourceTreeInventoryEntryCount: UInt64
    ) {
        self.macMergeCommit = macMergeCommit
        self.patchedXDiffContentManifestSHA256 = patchedXDiffContentManifestSHA256
        self.cBridgeSourceSHA256 = cBridgeSourceSHA256
        self.swiftDiffSourceSHA256 = swiftDiffSourceSHA256
        self.trustedExtractorVersion = trustedExtractorVersion
        self.trustedExtractorExecutableSHA256 = trustedExtractorExecutableSHA256
        self.trustedExtractorSchemaSHA256 = trustedExtractorSchemaSHA256
        self.trustedExtractorConfigurationSHA256 = trustedExtractorConfigurationSHA256
        self.sourceTreeInventorySHA256 = sourceTreeInventorySHA256
        self.sourceTreeInventoryEntryCount = sourceTreeInventoryEntryCount
    }

    public var description: String { "DiffOracleMacSourceProvenance(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["provenance": "<redacted>"], displayStyle: .struct)
    }
}

/// Trusted CI observation of exact Windows-golden and clean Mac source identities.
public struct DiffOracleSourceObservation: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let goldenProvenance: DiffOracleGoldenProvenance
    public let macSourceProvenance: DiffOracleMacSourceProvenance

    public init(
        goldenProvenance: DiffOracleGoldenProvenance,
        macSourceProvenance: DiffOracleMacSourceProvenance
    ) {
        self.goldenProvenance = goldenProvenance
        self.macSourceProvenance = macSourceProvenance
    }

    public var description: String { "DiffOracleSourceObservation(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["provenance": "<redacted>"], displayStyle: .struct)
    }
}

public struct DiffOracleFixtureManifestEntry: Hashable, Sendable {
    public let id: DiffOracleIdentifier
    public let revision: UInt64
    /// Canonically sorted corpus records that generated or supplied this fixture.
    public let corpusRecordIDs: [DiffOracleCorpusID]
    public let leftBytesSHA256: DiffOracleSHA256
    public let rightBytesSHA256: DiffOracleSHA256
    public let configurationSHA256: DiffOracleSHA256
    public let expectedResultSHA256: DiffOracleSHA256
    public let derivationTranscriptSHA256: DiffOracleSHA256
    public let derivationBindingSHA256: DiffOracleSHA256
    /// Kept per result so mixed-checkout golden sets fail validation.
    public let goldenProvenance: DiffOracleGoldenProvenance

    public init(
        id: DiffOracleIdentifier,
        revision: UInt64,
        corpusRecordIDs: [DiffOracleCorpusID],
        leftBytesSHA256: DiffOracleSHA256,
        rightBytesSHA256: DiffOracleSHA256,
        configurationSHA256: DiffOracleSHA256,
        expectedResultSHA256: DiffOracleSHA256,
        derivationTranscriptSHA256: DiffOracleSHA256,
        derivationBindingSHA256: DiffOracleSHA256,
        goldenProvenance: DiffOracleGoldenProvenance
    ) {
        self.id = id
        self.revision = revision
        self.corpusRecordIDs = corpusRecordIDs
        self.leftBytesSHA256 = leftBytesSHA256
        self.rightBytesSHA256 = rightBytesSHA256
        self.configurationSHA256 = configurationSHA256
        self.expectedResultSHA256 = expectedResultSHA256
        self.derivationTranscriptSHA256 = derivationTranscriptSHA256
        self.derivationBindingSHA256 = derivationBindingSHA256
        self.goldenProvenance = goldenProvenance
    }
}

/// Exact bytes and provenance observed by a caller. Configuration and result formats belong to the generator schema.
public struct DiffOracleFixtureRecord: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let id: DiffOracleIdentifier
    public let revision: UInt64
    public let corpusRecordIDs: [DiffOracleCorpusID]
    public let leftBytes: Data
    public let rightBytes: Data
    public let canonicalConfiguration: Data
    public let canonicalExpectedResult: Data
    public let canonicalDerivationTranscript: Data
    public let goldenProvenance: DiffOracleGoldenProvenance

    public init(
        id: DiffOracleIdentifier,
        revision: UInt64,
        corpusRecordIDs: [DiffOracleCorpusID],
        leftBytes: Data,
        rightBytes: Data,
        canonicalConfiguration: Data,
        canonicalExpectedResult: Data,
        canonicalDerivationTranscript: Data,
        goldenProvenance: DiffOracleGoldenProvenance
    ) throws {
        guard leftBytes.count <= DiffOracleVerificationLimits.hardMaximumRecordBytes,
            rightBytes.count <= DiffOracleVerificationLimits.hardMaximumRecordBytes,
            canonicalConfiguration.count <= DiffOracleVerificationLimits.hardMaximumRecordBytes,
            canonicalExpectedResult.count <= DiffOracleVerificationLimits.hardMaximumRecordBytes,
            canonicalDerivationTranscript.count <= DiffOracleVerificationLimits.hardMaximumRecordBytes
        else {
            throw DiffOracleManifestError.inputTooLarge
        }
        self.id = id
        self.revision = revision
        self.corpusRecordIDs = corpusRecordIDs
        self.leftBytes = Data(Array(leftBytes))
        self.rightBytes = Data(Array(rightBytes))
        self.canonicalConfiguration = Data(Array(canonicalConfiguration))
        self.canonicalExpectedResult = Data(Array(canonicalExpectedResult))
        self.canonicalDerivationTranscript = Data(Array(canonicalDerivationTranscript))
        self.goldenProvenance = goldenProvenance
    }

    public var description: String {
        "DiffOracleFixtureRecord(inputBytes: \(leftBytes.count + rightBytes.count), derivation/configuration/result: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "id": "<redacted>",
                "revision": revision,
                "corpusRecordCount": corpusRecordIDs.count,
                "inputByteCount": leftBytes.count + rightBytes.count,
                "derivationTranscript": "<redacted>",
                "configuration": "<redacted>",
                "expectedResult": "<redacted>",
                "provenance": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

private struct DiffOracleFixtureObservationHashes {
    let left: DiffOracleSHA256
    let right: DiffOracleSHA256
    let configuration: DiffOracleSHA256
    let result: DiffOracleSHA256
    let derivationTranscript: DiffOracleSHA256
}

/// Versioned, deterministic expected inventory. Entries and all nested identifier arrays must be sorted by raw UTF-8 bytes.
public struct DiffOracleManifest: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let currentSchemaVersion: UInt32 = 4
    public static let serializationDomain = "com.macmerge.diff-oracle-manifest.v4"

    public let schemaVersion: UInt32
    public let revision: UInt64
    public let configurationCodecVersion: UInt32
    public let resultCodecVersion: UInt32
    public let derivationTranscriptCodecVersion: UInt32
    public let configurationCodecMaximumWorkUnits: UInt64
    public let resultCodecMaximumWorkUnits: UInt64
    public let derivationTranscriptCodecMaximumWorkUnits: UInt64
    public let macSourceProvenance: DiffOracleMacSourceProvenance
    public let corpus: [DiffOracleCorpusManifestEntry]
    public let fixtures: [DiffOracleFixtureManifestEntry]

    public init(
        schemaVersion: UInt32 = Self.currentSchemaVersion,
        revision: UInt64,
        configurationCodecVersion: UInt32,
        resultCodecVersion: UInt32,
        derivationTranscriptCodecVersion: UInt32,
        configurationCodecMaximumWorkUnits: UInt64,
        resultCodecMaximumWorkUnits: UInt64,
        derivationTranscriptCodecMaximumWorkUnits: UInt64,
        macSourceProvenance: DiffOracleMacSourceProvenance,
        corpus: [DiffOracleCorpusManifestEntry],
        fixtures: [DiffOracleFixtureManifestEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.configurationCodecVersion = configurationCodecVersion
        self.resultCodecVersion = resultCodecVersion
        self.derivationTranscriptCodecVersion = derivationTranscriptCodecVersion
        self.configurationCodecMaximumWorkUnits = configurationCodecMaximumWorkUnits
        self.resultCodecMaximumWorkUnits = resultCodecMaximumWorkUnits
        self.derivationTranscriptCodecMaximumWorkUnits = derivationTranscriptCodecMaximumWorkUnits
        self.macSourceProvenance = macSourceProvenance
        self.corpus = corpus
        self.fixtures = fixtures
    }

    public func canonicalData(limits: DiffOracleVerificationLimits = .default) throws -> Data {
        try limits.validate()
        var work = DiffOracleWorkBudget(limits: limits)
        try DiffOracleManifestValidation.validate(self, limits: limits, work: &work)
        return try DiffOracleCanonical.manifestData(self, limits: limits, work: &work)
    }

    public var description: String {
        "DiffOracleManifest(schema: \(schemaVersion), revision: \(revision), corpus: \(corpus.count), fixtures: \(fixtures.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "schemaVersion": schemaVersion,
                "revision": revision,
                "configurationCodecVersion": configurationCodecVersion,
                "resultCodecVersion": resultCodecVersion,
                "derivationTranscriptCodecVersion": derivationTranscriptCodecVersion,
                "configurationCodecMaximumWorkUnits": configurationCodecMaximumWorkUnits,
                "resultCodecMaximumWorkUnits": resultCodecMaximumWorkUnits,
                "derivationTranscriptCodecMaximumWorkUnits": derivationTranscriptCodecMaximumWorkUnits,
                "corpusCount": corpus.count,
                "fixtureCount": fixtures.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Trusted codec adapter. Validation succeeds only when decoding and re-encoding returns byte-identical output.
public struct DiffOracleCodecCallbackBudget: Sendable {
    public let maximumWorkUnits: UInt64
    public let maximumOutputBytes: Int
    public private(set) var usedWorkUnits: UInt64 = 0

    fileprivate init(maximumWorkUnits: UInt64, maximumOutputBytes: Int) {
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumOutputBytes = maximumOutputBytes
    }

    public mutating func consume(_ amount: UInt64 = 1) throws {
        guard amount <= maximumWorkUnits - usedWorkUnits else {
            throw DiffOracleManifestError.workLimitExceeded
        }
        usedWorkUnits += amount
        try checkCancellation()
    }

    public func checkCancellation() throws {
        if Task.isCancelled {
            throw DiffOracleManifestError.cancelled
        }
    }
}

public struct DiffOracleCanonicalCodecValidator: Sendable {
    public let version: UInt32
    public let maximumInvocationWorkUnits: UInt64
    private let canonicalize: @Sendable (Data, inout DiffOracleCodecCallbackBudget) throws -> Data

    public init(
        version: UInt32,
        maximumInvocationWorkUnits: UInt64,
        canonicalize: @escaping @Sendable (Data, inout DiffOracleCodecCallbackBudget) throws -> Data
    ) throws {
        guard version > 0,
            (1...DiffOracleVerificationLimits.hardMaximumCodecCallbackWorkUnits)
                .contains(maximumInvocationWorkUnits)
        else {
            throw DiffOracleManifestError.invalidLimit
        }
        self.version = version
        self.maximumInvocationWorkUnits = maximumInvocationWorkUnits
        self.canonicalize = canonicalize
    }

    fileprivate func validate(
        _ data: Data,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> Bool {
        guard version > 0,
            maximumInvocationWorkUnits <= limits.maximumCodecCallbackWorkUnits,
            data.count <= limits.maximumRecordBytes
        else { return false }
        try work.consume(UInt64(data.count))
        try work.consume(maximumInvocationWorkUnits)
        try work.checkCancellation()
        var callbackBudget = DiffOracleCodecCallbackBudget(
            maximumWorkUnits: maximumInvocationWorkUnits,
            maximumOutputBytes: limits.maximumRecordBytes
        )
        let canonical: Data
        do {
            canonical = try canonicalize(data, &callbackBudget)
        } catch DiffOracleManifestError.cancelled {
            throw DiffOracleManifestError.cancelled
        } catch is CancellationError {
            throw DiffOracleManifestError.cancelled
        } catch DiffOracleManifestError.workLimitExceeded {
            throw DiffOracleManifestError.workLimitExceeded
        } catch {
            throw DiffOracleManifestError.invalidCanonicalEncoding
        }
        try work.checkCancellation()
        guard canonical.count <= limits.maximumRecordBytes else {
            throw DiffOracleManifestError.inputTooLarge
        }
        try work.consume(UInt64(canonical.count))
        let immutableCanonical = Data(Array(canonical))
        return immutableCanonical == data
    }
}

public struct DiffOracleCanonicalCodecValidators: Sendable {
    public let configuration: DiffOracleCanonicalCodecValidator
    public let result: DiffOracleCanonicalCodecValidator
    public let derivationTranscript: DiffOracleCanonicalCodecValidator

    public init(
        configuration: DiffOracleCanonicalCodecValidator,
        result: DiffOracleCanonicalCodecValidator,
        derivationTranscript: DiffOracleCanonicalCodecValidator
    ) {
        self.configuration = configuration
        self.result = result
        self.derivationTranscript = derivationTranscript
    }
}

public struct DiffOracleVerificationLimits: Hashable, Sendable {
    public static let hardMaximumCorpusRecords = 262_144
    public static let hardMaximumFixtureRecords = 262_144
    public static let hardMaximumRecordBytes = 64 * 1_024 * 1_024
    public static let hardMaximumTotalObservedBytes = 1_024 * 1_024 * 1_024
    public static let hardMaximumCanonicalBytes = 256 * 1_024 * 1_024
    public static let hardMaximumRelationEdges = 16 * 1_024 * 1_024
    public static let hardMaximumRelationBytes = 512 * 1_024 * 1_024
    public static let hardMaximumAuthorizationBytes = 16 * 1_024 * 1_024
    public static let hardMaximumConsumedAuthorizationNonces = 1_048_576
    public static let hardMaximumRevisionFloorRecords = 1_048_576
    public static let hardMaximumAuthorizationValiditySeconds: UInt64 = 366 * 24 * 60 * 60
    public static let hardMaximumWorkUnits: UInt64 = 4 * 1_024 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let hardMaximumCodecCallbackWorkUnits: UInt64 = 1_024 * 1_024 * 1_024

    public static let `default` = DiffOracleVerificationLimits(
        maximumCorpusRecords: 65_536,
        maximumFixtureRecords: 65_536,
        maximumRecordBytes: 64 * 1_024 * 1_024,
        maximumTotalObservedBytes: 512 * 1_024 * 1_024,
        maximumCanonicalBytes: 64 * 1_024 * 1_024,
        maximumIdentifierUTF8Bytes: 1_024,
        maximumRelationEdges: 2 * 1_024 * 1_024,
        maximumRelationBytes: 128 * 1_024 * 1_024,
        maximumAuthorizationBytes: 4 * 1_024 * 1_024,
        maximumConsumedAuthorizationNonces: 262_144,
        maximumRevisionFloorRecords: 524_288,
        maximumAuthorizationValiditySeconds: 7 * 24 * 60 * 60,
        maximumWorkUnits: 2 * 1_024 * 1_024 * 1_024,
        maximumCodecCallbackWorkUnits: 256 * 1_024 * 1_024,
        cancellationCheckInterval: 4_096,
        unchecked: ()
    )

    public let maximumCorpusRecords: Int
    public let maximumFixtureRecords: Int
    public let maximumRecordBytes: Int
    public let maximumTotalObservedBytes: Int
    public let maximumCanonicalBytes: Int
    public let maximumIdentifierUTF8Bytes: Int
    public let maximumRelationEdges: Int
    public let maximumRelationBytes: Int
    public let maximumAuthorizationBytes: Int
    public let maximumConsumedAuthorizationNonces: Int
    public let maximumRevisionFloorRecords: Int
    public let maximumAuthorizationValiditySeconds: UInt64
    public let maximumWorkUnits: UInt64
    public let maximumCodecCallbackWorkUnits: UInt64
    public let cancellationCheckInterval: Int

    public init(
        maximumCorpusRecords: Int = 65_536,
        maximumFixtureRecords: Int = 65_536,
        maximumRecordBytes: Int = 64 * 1_024 * 1_024,
        maximumTotalObservedBytes: Int = 512 * 1_024 * 1_024,
        maximumCanonicalBytes: Int = 64 * 1_024 * 1_024,
        maximumIdentifierUTF8Bytes: Int = 1_024,
        maximumRelationEdges: Int = 2 * 1_024 * 1_024,
        maximumRelationBytes: Int = 128 * 1_024 * 1_024,
        maximumAuthorizationBytes: Int = 4 * 1_024 * 1_024,
        maximumConsumedAuthorizationNonces: Int = 262_144,
        maximumRevisionFloorRecords: Int = 524_288,
        maximumAuthorizationValiditySeconds: UInt64 = 7 * 24 * 60 * 60,
        maximumWorkUnits: UInt64 = 2 * 1_024 * 1_024 * 1_024,
        maximumCodecCallbackWorkUnits: UInt64 = 256 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 4_096
    ) throws {
        self.init(
            maximumCorpusRecords: maximumCorpusRecords,
            maximumFixtureRecords: maximumFixtureRecords,
            maximumRecordBytes: maximumRecordBytes,
            maximumTotalObservedBytes: maximumTotalObservedBytes,
            maximumCanonicalBytes: maximumCanonicalBytes,
            maximumIdentifierUTF8Bytes: maximumIdentifierUTF8Bytes,
            maximumRelationEdges: maximumRelationEdges,
            maximumRelationBytes: maximumRelationBytes,
            maximumAuthorizationBytes: maximumAuthorizationBytes,
            maximumConsumedAuthorizationNonces: maximumConsumedAuthorizationNonces,
            maximumRevisionFloorRecords: maximumRevisionFloorRecords,
            maximumAuthorizationValiditySeconds: maximumAuthorizationValiditySeconds,
            maximumWorkUnits: maximumWorkUnits,
            maximumCodecCallbackWorkUnits: maximumCodecCallbackWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval,
            unchecked: ()
        )
        try validate()
    }

    fileprivate func validate() throws {
        guard (1...Self.hardMaximumCorpusRecords).contains(maximumCorpusRecords),
            (1...Self.hardMaximumFixtureRecords).contains(maximumFixtureRecords),
            (1...Self.hardMaximumRecordBytes).contains(maximumRecordBytes),
            (1...Self.hardMaximumTotalObservedBytes).contains(maximumTotalObservedBytes),
            maximumRecordBytes <= maximumTotalObservedBytes,
            (1...Self.hardMaximumCanonicalBytes).contains(maximumCanonicalBytes),
            (1...DiffOracleIdentifier.hardMaximumUTF8ByteCount).contains(maximumIdentifierUTF8Bytes),
            (1...Self.hardMaximumRelationEdges).contains(maximumRelationEdges),
            (1...Self.hardMaximumRelationBytes).contains(maximumRelationBytes),
            (1...Self.hardMaximumAuthorizationBytes).contains(maximumAuthorizationBytes),
            maximumAuthorizationBytes <= maximumCanonicalBytes,
            (1...Self.hardMaximumConsumedAuthorizationNonces).contains(maximumConsumedAuthorizationNonces),
            (1...Self.hardMaximumRevisionFloorRecords).contains(maximumRevisionFloorRecords),
            (1...Self.hardMaximumAuthorizationValiditySeconds).contains(maximumAuthorizationValiditySeconds),
            (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits),
            (1...Self.hardMaximumCodecCallbackWorkUnits).contains(maximumCodecCallbackWorkUnits),
            maximumCodecCallbackWorkUnits <= maximumWorkUnits,
            (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval)
        else {
            throw DiffOracleManifestError.invalidLimit
        }
    }

    private init(
        maximumCorpusRecords: Int,
        maximumFixtureRecords: Int,
        maximumRecordBytes: Int,
        maximumTotalObservedBytes: Int,
        maximumCanonicalBytes: Int,
        maximumIdentifierUTF8Bytes: Int,
        maximumRelationEdges: Int,
        maximumRelationBytes: Int,
        maximumAuthorizationBytes: Int,
        maximumConsumedAuthorizationNonces: Int,
        maximumRevisionFloorRecords: Int,
        maximumAuthorizationValiditySeconds: UInt64,
        maximumWorkUnits: UInt64,
        maximumCodecCallbackWorkUnits: UInt64,
        cancellationCheckInterval: Int,
        unchecked: Void
    ) {
        self.maximumCorpusRecords = maximumCorpusRecords
        self.maximumFixtureRecords = maximumFixtureRecords
        self.maximumRecordBytes = maximumRecordBytes
        self.maximumTotalObservedBytes = maximumTotalObservedBytes
        self.maximumCanonicalBytes = maximumCanonicalBytes
        self.maximumIdentifierUTF8Bytes = maximumIdentifierUTF8Bytes
        self.maximumRelationEdges = maximumRelationEdges
        self.maximumRelationBytes = maximumRelationBytes
        self.maximumAuthorizationBytes = maximumAuthorizationBytes
        self.maximumConsumedAuthorizationNonces = maximumConsumedAuthorizationNonces
        self.maximumRevisionFloorRecords = maximumRevisionFloorRecords
        self.maximumAuthorizationValiditySeconds = maximumAuthorizationValiditySeconds
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumCodecCallbackWorkUnits = maximumCodecCallbackWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum DiffOracleDiagnosticCode: String, Hashable, Sendable {
    case invalidManifest
    case nonCanonicalOrder
    case missingRecord
    case duplicateRecord
    case unexpectedRecord
    case staleRecord
    case changedRecord
    case invalidReceipt
    case updateNotAuthorized
}

/// Safe to log: identifies only collection and canonical position, never IDs, paths, bytes, or digests.
public struct DiffOracleRedactedDiagnostic: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public enum Collection: String, Hashable, Sendable {
        case manifest
        case corpus
        case fixture
        case update
    }

    public let code: DiffOracleDiagnosticCode
    public let collection: Collection
    public let canonicalIndex: Int?

    public init(code: DiffOracleDiagnosticCode, collection: Collection, canonicalIndex: Int? = nil) {
        self.code = code
        self.collection = collection
        self.canonicalIndex = canonicalIndex
    }

    public var description: String {
        "Diff oracle verification failed: \(code.rawValue), collection: \(collection.rawValue), canonical index: \(canonicalIndex.map(String.init) ?? "<redacted>")."
    }

    public var debugDescription: String { description }
}

public enum DiffOracleManifestError: Error, Equatable, Sendable, LocalizedError {
    case invalidSHA256
    case invalidCorpusID
    case invalidPathKey
    case invalidGitObjectID
    case invalidIdentifier
    case invalidLimit
    case inputTooLarge
    case canonicalOutputTooLarge
    case workLimitExceeded
    case cancelled
    case verificationFailed(DiffOracleRedactedDiagnostic)
    case invalidAuthorizationKey
    case invalidAuthorizationBlob
    case invalidCanonicalEncoding
    case invalidAuthorityState
    case invalidTrustedTime
    case indeterminateAuthorityTransition

    public var errorDescription: String? {
        switch self {
        case .invalidSHA256:
            "SHA-256 value must contain exactly 32 bytes or 64 lowercase hexadecimal characters."
        case .invalidCorpusID:
            "Diff oracle corpus ID must be a nonzero, opaque 32-byte value."
        case .invalidPathKey:
            "Diff oracle path key is invalid."
        case .invalidGitObjectID:
            "Git object ID must contain exactly 40 lowercase hexadecimal characters."
        case .invalidIdentifier:
            "Diff oracle identifier is invalid."
        case .invalidLimit:
            "Diff oracle verification limit is invalid."
        case .inputTooLarge:
            "Diff oracle input exceeds a configured bound."
        case .canonicalOutputTooLarge:
            "Diff oracle canonical output exceeds a configured bound."
        case .workLimitExceeded:
            "Diff oracle verification exceeded its work bound."
        case .cancelled:
            "Diff oracle verification was cancelled."
        case .verificationFailed(let diagnostic):
            diagnostic.description
        case .invalidAuthorizationKey:
            "Diff oracle update authorization key is invalid."
        case .invalidAuthorizationBlob:
            "Diff oracle update authorization blob is invalid or noncanonical."
        case .invalidCanonicalEncoding:
            "Diff oracle configuration, result, or derivation encoding is noncanonical."
        case .invalidAuthorityState:
            "Diff oracle authority state failed integrity, rollback, or atomic-transition validation."
        case .invalidTrustedTime:
            "Diff oracle trusted time failed source, integrity, or rollback-floor validation."
        case .indeterminateAuthorityTransition:
            "Diff oracle authority transition outcome is indeterminate; retry is unsafe until trusted storage reconciles it."
        }
    }
}

public struct DiffOracleVerificationReceipt: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let serializationDomain = "com.macmerge.diff-oracle-receipt.v4"

    public let schemaVersion: UInt32
    public let manifestRevision: UInt64
    public let manifestSHA256: DiffOracleSHA256
    public let observationSHA256: DiffOracleSHA256
    public let corpusRecordCount: Int
    public let fixtureRecordCount: Int
    public let observedByteCount: Int
    public let workUnits: UInt64
    public let receiptSHA256: DiffOracleSHA256

    fileprivate init(
        manifestRevision: UInt64,
        manifestSHA256: DiffOracleSHA256,
        observationSHA256: DiffOracleSHA256,
        corpusRecordCount: Int,
        fixtureRecordCount: Int,
        observedByteCount: Int,
        workUnits: UInt64,
        receiptSHA256: DiffOracleSHA256
    ) {
        schemaVersion = DiffOracleManifest.currentSchemaVersion
        self.manifestRevision = manifestRevision
        self.manifestSHA256 = manifestSHA256
        self.observationSHA256 = observationSHA256
        self.corpusRecordCount = corpusRecordCount
        self.fixtureRecordCount = fixtureRecordCount
        self.observedByteCount = observedByteCount
        self.workUnits = workUnits
        self.receiptSHA256 = receiptSHA256
    }

    public func canonicalData(limits: DiffOracleVerificationLimits = .default) throws -> Data {
        try limits.validate()
        var work = DiffOracleWorkBudget(limits: limits)
        return try DiffOracleCanonical.receiptData(self, limits: limits, work: &work)
    }

    public var description: String {
        "DiffOracleVerificationReceipt(revision: \(manifestRevision), corpus: \(corpusRecordCount), fixtures: \(fixtureRecordCount), bindings: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "manifestRevision": manifestRevision,
                "corpusRecordCount": corpusRecordCount,
                "fixtureRecordCount": fixtureRecordCount,
                "observedByteCount": observedByteCount,
                "workUnits": workUnits,
                "bindings": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

public enum DiffOracleChangeReference: Comparable, Hashable, Sendable {
    case manifest
    case corpus(DiffOracleCorpusID)
    case fixture(DiffOracleIdentifier)

    public static func < (left: Self, right: Self) -> Bool {
        switch (left, right) {
        case (.manifest, .manifest): false
        case (.manifest, _): true
        case (_, .manifest): false
        case (.corpus(let leftID), .corpus(let rightID)):
            leftID < rightID
        case (.fixture(let leftID), .fixture(let rightID)):
            leftID < rightID
        case (.corpus, .fixture): true
        case (.fixture, .corpus): false
        }
    }
}

public struct DiffOracleRevisionFloor: Hashable, Sendable {
    public let record: DiffOracleChangeReference
    public let revision: UInt64
    public let isTombstone: Bool

    public init(record: DiffOracleChangeReference, revision: UInt64, isTombstone: Bool) {
        self.record = record
        self.revision = revision
        self.isTombstone = isTombstone
    }

}

/// Authenticated time from a trusted source backed by a rollback-resistant monotonic counter.
public struct DiffOracleTrustedTimeObservation: Hashable, Sendable {
    public let sourceID: DiffOracleSHA256
    public let unixSeconds: UInt64
    public let rollbackProtectionCounter: UInt64
    public let predecessorIntegrityTag: DiffOracleSHA256
    public let integrityTag: DiffOracleSHA256

    public init(
        sourceID: DiffOracleSHA256,
        unixSeconds: UInt64,
        rollbackProtectionCounter: UInt64,
        predecessorIntegrityTag: DiffOracleSHA256,
        integrityTag: DiffOracleSHA256
    ) throws {
        guard !sourceID.isZero,
            unixSeconds > 0,
            rollbackProtectionCounter > 0,
            !predecessorIntegrityTag.isZero,
            !integrityTag.isZero
        else {
            throw DiffOracleManifestError.invalidTrustedTime
        }
        self.sourceID = sourceID
        self.unixSeconds = unixSeconds
        self.rollbackProtectionCounter = rollbackProtectionCounter
        self.predecessorIntegrityTag = predecessorIntegrityTag
        self.integrityTag = integrityTag
    }
}

/// Trusted clock boundary. Callback must authenticate observation and reject rollback against its own durable floor.
public struct DiffOracleTrustedTimeSource: Sendable {
    public let sourceID: DiffOracleSHA256
    private let readAuthenticatedTime:
        @Sendable (
            _ minimumUnixSeconds: UInt64,
            _ minimumRollbackProtectionCounter: UInt64,
            _ predecessorIntegrityTag: DiffOracleSHA256
        ) throws ->
            DiffOracleTrustedTimeObservation

    public init(
        sourceID: DiffOracleSHA256,
        readAuthenticatedTime:
            @escaping @Sendable (
                _ minimumUnixSeconds: UInt64,
                _ minimumRollbackProtectionCounter: UInt64,
                _ predecessorIntegrityTag: DiffOracleSHA256
            ) throws -> DiffOracleTrustedTimeObservation
    ) throws {
        guard !sourceID.isZero else {
            throw DiffOracleManifestError.invalidTrustedTime
        }
        self.sourceID = sourceID
        self.readAuthenticatedTime = readAuthenticatedTime
    }

    fileprivate func read(
        minimumUnixSeconds: UInt64,
        minimumRollbackProtectionCounter: UInt64,
        predecessorIntegrityTag: DiffOracleSHA256
    ) throws -> DiffOracleTrustedTimeObservation {
        guard !Task.isCancelled else {
            throw DiffOracleManifestError.cancelled
        }
        let observation: DiffOracleTrustedTimeObservation
        do {
            observation = try readAuthenticatedTime(
                minimumUnixSeconds,
                minimumRollbackProtectionCounter,
                predecessorIntegrityTag
            )
        } catch DiffOracleManifestError.cancelled {
            throw DiffOracleManifestError.cancelled
        } catch is CancellationError {
            throw DiffOracleManifestError.cancelled
        }
        guard observation.sourceID == sourceID,
            observation.unixSeconds >= minimumUnixSeconds,
            observation.rollbackProtectionCounter > minimumRollbackProtectionCounter,
            observation.predecessorIntegrityTag == predecessorIntegrityTag
        else {
            throw DiffOracleManifestError.invalidTrustedTime
        }
        guard !Task.isCancelled else {
            throw DiffOracleManifestError.cancelled
        }
        return observation
    }
}

public struct DiffOracleUpdateAuthorityState: Hashable, Sendable {
    public static let serializationDomain = "com.macmerge.diff-oracle-authority-state.v2"

    public let revocationGeneration: UInt64
    public let policyVersion: UInt64
    public let currentManifestRevision: UInt64
    public let currentManifestSHA256: DiffOracleSHA256
    public let trustedTimeSourceID: DiffOracleSHA256
    public let trustedTimeFloorUnixSeconds: UInt64
    public let trustedTimeRollbackProtectionCounter: UInt64
    public let trustedTimeIntegrityTag: DiffOracleSHA256
    /// Canonically sorted set of all previously accepted authorization nonces.
    public let consumedAuthorizationNonces: [DiffOracleSHA256]
    /// Canonically sorted persistent floors, including tombstones for removed IDs.
    public let revisionFloors: [DiffOracleRevisionFloor]

    public init(
        revocationGeneration: UInt64,
        policyVersion: UInt64,
        currentManifestRevision: UInt64,
        currentManifestSHA256: DiffOracleSHA256,
        trustedTimeSourceID: DiffOracleSHA256,
        trustedTimeFloorUnixSeconds: UInt64,
        trustedTimeRollbackProtectionCounter: UInt64,
        trustedTimeIntegrityTag: DiffOracleSHA256,
        consumedAuthorizationNonces: [DiffOracleSHA256],
        revisionFloors: [DiffOracleRevisionFloor]
    ) {
        self.revocationGeneration = revocationGeneration
        self.policyVersion = policyVersion
        self.currentManifestRevision = currentManifestRevision
        self.currentManifestSHA256 = currentManifestSHA256
        self.trustedTimeSourceID = trustedTimeSourceID
        self.trustedTimeFloorUnixSeconds = trustedTimeFloorUnixSeconds
        self.trustedTimeRollbackProtectionCounter = trustedTimeRollbackProtectionCounter
        self.trustedTimeIntegrityTag = trustedTimeIntegrityTag
        self.consumedAuthorizationNonces = consumedAuthorizationNonces
        self.revisionFloors = revisionFloors
    }

    /// Canonical bytes that trusted storage must authenticate before persistence.
    public func canonicalData(limits: DiffOracleVerificationLimits = .default) throws -> Data {
        try limits.validate()
        var work = DiffOracleWorkBudget(limits: limits)
        try DiffOracleManifestValidation.validateAuthorityState(self, limits: limits, work: &work)
        return try DiffOracleCanonical.authorityStateData(self, limits: limits, work: &work)
    }
}

/// Read-back proof that candidate manifest and receipt bytes are durably stored under their digests.
public struct DiffOracleDurableCandidate: Hashable, Sendable {
    public let manifestRevision: UInt64
    public let manifestSHA256: DiffOracleSHA256
    public let receiptSHA256: DiffOracleSHA256
    public let receiptContentSHA256: DiffOracleSHA256
    public let durabilityProofSHA256: DiffOracleSHA256

    public init(
        manifestRevision: UInt64,
        manifestSHA256: DiffOracleSHA256,
        receiptSHA256: DiffOracleSHA256,
        receiptContentSHA256: DiffOracleSHA256,
        durabilityProofSHA256: DiffOracleSHA256
    ) throws {
        guard manifestRevision > 0,
            !manifestSHA256.isZero,
            !receiptSHA256.isZero,
            !receiptContentSHA256.isZero,
            !durabilityProofSHA256.isZero
        else {
            throw DiffOracleManifestError.invalidAuthorityState
        }
        self.manifestRevision = manifestRevision
        self.manifestSHA256 = manifestSHA256
        self.receiptSHA256 = receiptSHA256
        self.receiptContentSHA256 = receiptContentSHA256
        self.durabilityProofSHA256 = durabilityProofSHA256
    }
}

/// State returned only after trusted storage authenticates its seal and rollback counter.
public struct DiffOracleUpdateAuthorityStateSnapshot: Hashable, Sendable {
    public let state: DiffOracleUpdateAuthorityState
    public let rollbackProtectionCounter: UInt64
    public let protectionKeyID: DiffOracleSHA256
    public let predecessorIntegrityTag: DiffOracleSHA256
    public let integrityTag: DiffOracleSHA256

    public init(
        state: DiffOracleUpdateAuthorityState,
        rollbackProtectionCounter: UInt64,
        protectionKeyID: DiffOracleSHA256,
        predecessorIntegrityTag: DiffOracleSHA256,
        integrityTag: DiffOracleSHA256
    ) throws {
        guard rollbackProtectionCounter > 0, !protectionKeyID.isZero, !integrityTag.isZero else {
            throw DiffOracleManifestError.invalidAuthorityState
        }
        self.state = state
        self.rollbackProtectionCounter = rollbackProtectionCounter
        self.protectionKeyID = protectionKeyID
        self.predecessorIntegrityTag = predecessorIntegrityTag
        self.integrityTag = integrityTag
    }
}

/// Trusted persistence boundary for authority state.
///
/// `load` must authenticate `state.canonicalData()`, its counter, and predecessor metadata under
/// `protectionKeyID`, then reject counters older than rollback-resistant storage. Candidate
/// persistence must content-address, sync, and read-back-verify both byte strings before returning
/// its proof. `transition` must validate that proof, atomically compare the complete expected
/// snapshot, increment the protected counter, seal and durably persist `replacement`, and return
/// the committed snapshot. `reconcileIndeterminateSnapshot` must atomically prove this exact
/// transition committed; it returns `nil` when proof is unavailable, prohibiting unsafe retry.
public struct DiffOracleUpdateAuthorityStateStore: Sendable {
    public enum TransitionOutcome: Hashable, Sendable {
        case committed(DiffOracleUpdateAuthorityStateSnapshot)
        case notCommitted
        case indeterminate
    }

    private let loadValidatedSnapshot: @Sendable () throws -> DiffOracleUpdateAuthorityStateSnapshot
    private let persistContentAddressedCandidate:
        @Sendable (
            _ manifestRevision: UInt64,
            _ manifestSHA256: DiffOracleSHA256,
            _ canonicalManifestData: Data,
            _ receiptSHA256: DiffOracleSHA256,
            _ receiptContentSHA256: DiffOracleSHA256,
            _ canonicalReceiptData: Data
        ) throws -> DiffOracleDurableCandidate
    private let compareAndSwapSnapshot:
        @Sendable (
            DiffOracleUpdateAuthorityStateSnapshot,
            DiffOracleDurableCandidate,
            DiffOracleUpdateAuthorityState
        ) -> TransitionOutcome
    private let reconcileIndeterminateSnapshot:
        @Sendable (
            DiffOracleUpdateAuthorityStateSnapshot,
            DiffOracleDurableCandidate,
            DiffOracleUpdateAuthorityState
        ) -> DiffOracleUpdateAuthorityStateSnapshot?

    public init(
        loadValidatedSnapshot: @escaping @Sendable () throws -> DiffOracleUpdateAuthorityStateSnapshot,
        persistContentAddressedCandidate:
            @escaping @Sendable (
                _ manifestRevision: UInt64,
                _ manifestSHA256: DiffOracleSHA256,
                _ canonicalManifestData: Data,
                _ receiptSHA256: DiffOracleSHA256,
                _ receiptContentSHA256: DiffOracleSHA256,
                _ canonicalReceiptData: Data
            ) throws -> DiffOracleDurableCandidate,
        compareAndSwapSnapshot:
            @escaping @Sendable (
                DiffOracleUpdateAuthorityStateSnapshot,
                DiffOracleDurableCandidate,
                DiffOracleUpdateAuthorityState
            ) -> TransitionOutcome,
        reconcileIndeterminateSnapshot:
            @escaping @Sendable (
                DiffOracleUpdateAuthorityStateSnapshot,
                DiffOracleDurableCandidate,
                DiffOracleUpdateAuthorityState
            ) -> DiffOracleUpdateAuthorityStateSnapshot?
    ) {
        self.loadValidatedSnapshot = loadValidatedSnapshot
        self.persistContentAddressedCandidate = persistContentAddressedCandidate
        self.compareAndSwapSnapshot = compareAndSwapSnapshot
        self.reconcileIndeterminateSnapshot = reconcileIndeterminateSnapshot
    }

    fileprivate func load() throws -> DiffOracleUpdateAuthorityStateSnapshot {
        try checkCancellation()
        let snapshot: DiffOracleUpdateAuthorityStateSnapshot
        do {
            snapshot = try loadValidatedSnapshot()
        } catch DiffOracleManifestError.cancelled {
            throw DiffOracleManifestError.cancelled
        } catch is CancellationError {
            throw DiffOracleManifestError.cancelled
        }
        try checkCancellation()
        return snapshot
    }

    fileprivate func persistCandidate(
        manifestRevision: UInt64,
        manifestSHA256: DiffOracleSHA256,
        canonicalManifestData: Data,
        receiptSHA256: DiffOracleSHA256,
        receiptContentSHA256: DiffOracleSHA256,
        canonicalReceiptData: Data
    ) throws -> DiffOracleDurableCandidate {
        try checkCancellation()
        let durableCandidate: DiffOracleDurableCandidate
        do {
            durableCandidate = try persistContentAddressedCandidate(
                manifestRevision,
                manifestSHA256,
                canonicalManifestData,
                receiptSHA256,
                receiptContentSHA256,
                canonicalReceiptData
            )
        } catch DiffOracleManifestError.cancelled {
            throw DiffOracleManifestError.cancelled
        } catch is CancellationError {
            throw DiffOracleManifestError.cancelled
        }
        guard durableCandidate.manifestRevision == manifestRevision,
            durableCandidate.manifestSHA256 == manifestSHA256,
            durableCandidate.receiptSHA256 == receiptSHA256,
            durableCandidate.receiptContentSHA256 == receiptContentSHA256
        else {
            throw DiffOracleManifestError.invalidAuthorityState
        }
        try checkCancellation()
        return durableCandidate
    }

    fileprivate func transition(
        from expected: DiffOracleUpdateAuthorityStateSnapshot,
        durableCandidate: DiffOracleDurableCandidate,
        to replacement: DiffOracleUpdateAuthorityState
    ) throws -> TransitionOutcome {
        try checkCancellation()
        let outcome = compareAndSwapSnapshot(expected, durableCandidate, replacement)
        switch outcome {
        case .committed(let snapshot):
            if validatesCommittedSnapshot(snapshot, expected: expected, replacement: replacement) {
                return outcome
            }
        case .notCommitted:
            try checkCancellation()
            return .notCommitted
        case .indeterminate:
            break
        }
        guard let reconciled = reconcileIndeterminateSnapshot(expected, durableCandidate, replacement) else {
            return .indeterminate
        }
        guard validatesCommittedSnapshot(reconciled, expected: expected, replacement: replacement) else {
            return .indeterminate
        }
        return .committed(reconciled)
    }

    private func validatesCommittedSnapshot(
        _ snapshot: DiffOracleUpdateAuthorityStateSnapshot,
        expected: DiffOracleUpdateAuthorityStateSnapshot,
        replacement: DiffOracleUpdateAuthorityState
    ) -> Bool {
        expected.rollbackProtectionCounter < UInt64.max
            && snapshot.state == replacement
            && snapshot.protectionKeyID == expected.protectionKeyID
            && snapshot.predecessorIntegrityTag == expected.integrityTag
            && snapshot.rollbackProtectionCounter == expected.rollbackProtectionCounter + 1
    }

    private func checkCancellation() throws {
        if Task.isCancelled {
            throw DiffOracleManifestError.cancelled
        }
    }
}

public struct DiffOracleAcceptedUpdate: Hashable, Sendable {
    public let receipt: DiffOracleVerificationReceipt
    public let authorityStateSnapshot: DiffOracleUpdateAuthorityStateSnapshot

    public var authorityState: DiffOracleUpdateAuthorityState { authorityStateSnapshot.state }

    fileprivate init(
        receipt: DiffOracleVerificationReceipt,
        authorityStateSnapshot: DiffOracleUpdateAuthorityStateSnapshot
    ) {
        self.receipt = receipt
        self.authorityStateSnapshot = authorityStateSnapshot
    }
}

/// Reviewed evidence is caller-owned metadata. It becomes approval only after a trusted issuer signs it.
public struct DiffOracleReviewedUpdateEvidence: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let reviewID: DiffOracleIdentifier
    public let reviewerIdentitySHA256: DiffOracleSHA256
    public let reviewArtifactSHA256: DiffOracleSHA256
    public let policyVersion: UInt64
    public let authorizationNonce: DiffOracleSHA256
    public let issuedAtUnixSeconds: UInt64
    public let expiresAtUnixSeconds: UInt64
    public let baselineReceiptSHA256: DiffOracleSHA256
    public let candidateReceiptSHA256: DiffOracleSHA256
    public let approvedChanges: [DiffOracleChangeReference]

    public init(
        reviewID: DiffOracleIdentifier,
        reviewerIdentitySHA256: DiffOracleSHA256,
        reviewArtifactSHA256: DiffOracleSHA256,
        policyVersion: UInt64,
        authorizationNonce: DiffOracleSHA256,
        issuedAtUnixSeconds: UInt64,
        expiresAtUnixSeconds: UInt64,
        baselineReceiptSHA256: DiffOracleSHA256,
        candidateReceiptSHA256: DiffOracleSHA256,
        approvedChanges: [DiffOracleChangeReference]
    ) {
        self.reviewID = reviewID
        self.reviewerIdentitySHA256 = reviewerIdentitySHA256
        self.reviewArtifactSHA256 = reviewArtifactSHA256
        self.policyVersion = policyVersion
        self.authorizationNonce = authorizationNonce
        self.issuedAtUnixSeconds = issuedAtUnixSeconds
        self.expiresAtUnixSeconds = expiresAtUnixSeconds
        self.baselineReceiptSHA256 = baselineReceiptSHA256
        self.candidateReceiptSHA256 = candidateReceiptSHA256
        self.approvedChanges = approvedChanges
    }

    public var description: String {
        "DiffOracleReviewedUpdateEvidence(changes: \(approvedChanges.count), evidence: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["changeCount": approvedChanges.count, "evidence": "<redacted>"],
            displayStyle: .struct
        )
    }
}

public struct DiffOracleUpdateAuthorization: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let currentBlobVersion: UInt32 = 2
    public static let serializationDomain = "com.macmerge.diff-oracle-update-authorization.v2"

    fileprivate let authorityID: DiffOracleSHA256
    fileprivate let revocationGeneration: UInt64
    fileprivate let evidence: DiffOracleReviewedUpdateEvidence
    fileprivate let signature: Data

    fileprivate init(
        authorityID: DiffOracleSHA256,
        revocationGeneration: UInt64,
        evidence: DiffOracleReviewedUpdateEvidence,
        signature: Data
    ) {
        self.authorityID = authorityID
        self.revocationGeneration = revocationGeneration
        self.evidence = evidence
        self.signature = Data(Array(signature))
    }

    public func canonicalData(limits: DiffOracleVerificationLimits = .default) throws -> Data {
        try limits.validate()
        var work = DiffOracleWorkBudget(limits: limits)
        try DiffOracleUpdateAuthorizationValidation.validateAuthorization(self, limits: limits, work: &work)
        return try DiffOracleUpdateAuthorizationValidation.blobData(self, limits: limits, work: &work)
    }

    public init(canonicalData: Data, limits: DiffOracleVerificationLimits = .default) throws {
        try limits.validate()
        guard canonicalData.count <= limits.maximumAuthorizationBytes else {
            throw DiffOracleManifestError.inputTooLarge
        }
        var work = DiffOracleWorkBudget(limits: limits)
        try work.consume(UInt64(canonicalData.count))
        let immutableCanonicalData = Data(Array(canonicalData))
        var reader = DiffOracleCanonicalReader(data: immutableCanonicalData, limits: limits, work: work)
        guard try reader.readDomain(Self.serializationDomain),
            try reader.readUInt32() == Self.currentBlobVersion
        else {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
        let authorityID = try reader.readSHA256()
        let revocationGeneration = try reader.readUInt64()
        let evidence = try reader.readReviewedUpdateEvidence()
        let signature = try reader.readData(maximumByteCount: DiffOracleUpdateAuthorizationValidation.signatureByteCount)
        guard signature.count == DiffOracleUpdateAuthorizationValidation.signatureByteCount,
            reader.isAtEnd
        else {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
        work = reader.work
        let authorization = Self(
            authorityID: authorityID,
            revocationGeneration: revocationGeneration,
            evidence: evidence,
            signature: signature
        )
        try DiffOracleUpdateAuthorizationValidation.validateAuthorization(
            authorization,
            limits: limits,
            work: &work
        )
        let encoded = try DiffOracleUpdateAuthorizationValidation.blobData(
            authorization,
            limits: limits,
            work: &work
        )
        guard encoded == immutableCanonicalData else {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
        self = authorization
    }

    public var description: String { "DiffOracleUpdateAuthorization(<opaque>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["authorization": "<opaque>"], displayStyle: .struct)
    }
}

/// Offline or otherwise review-gated signer. Private key material must not enter verification CI.
public struct DiffOracleUpdateAuthorizationIssuer: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    private let privateKey: Curve25519.Signing.PrivateKey
    public let authorityID: DiffOracleSHA256

    public var publicKeyRawRepresentation: Data { Data(privateKey.publicKey.rawRepresentation) }

    public init(privateKeyRawRepresentation: Data) throws {
        guard privateKeyRawRepresentation.count == 32 else {
            throw DiffOracleManifestError.invalidAuthorizationKey
        }
        let parsedPrivateKey: Curve25519.Signing.PrivateKey
        do {
            parsedPrivateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Array(privateKeyRawRepresentation))
        } catch {
            throw DiffOracleManifestError.invalidAuthorizationKey
        }
        privateKey = parsedPrivateKey
        authorityID = try DiffOracleSHA256(bytes: Array(SHA256.hash(data: parsedPrivateKey.publicKey.rawRepresentation)))
    }

    public func issue(
        evidence: DiffOracleReviewedUpdateEvidence,
        authorityState: DiffOracleUpdateAuthorityState,
        trustedTimeSource: DiffOracleTrustedTimeSource,
        limits: DiffOracleVerificationLimits = .default
    ) throws -> DiffOracleUpdateAuthorization {
        try limits.validate()
        var work = DiffOracleWorkBudget(limits: limits)
        try DiffOracleManifestValidation.validateAuthorityState(authorityState, limits: limits, work: &work)
        guard trustedTimeSource.sourceID == authorityState.trustedTimeSourceID else {
            throw DiffOracleManifestError.invalidTrustedTime
        }
        let trustedTime = try trustedTimeSource.read(
            minimumUnixSeconds: authorityState.trustedTimeFloorUnixSeconds,
            minimumRollbackProtectionCounter: authorityState.trustedTimeRollbackProtectionCounter,
            predecessorIntegrityTag: authorityState.trustedTimeIntegrityTag
        )
        try DiffOracleUpdateAuthorizationValidation.validate(
            evidence,
            authorityState: authorityState,
            currentUnixSeconds: trustedTime.unixSeconds,
            limits: limits,
            work: &work
        )
        guard !authorityState.consumedAuthorizationNonces.binarySearch(evidence.authorizationNonce) else {
            throw DiffOracleManifestError.verificationFailed(
                DiffOracleRedactedDiagnostic(code: .updateNotAuthorized, collection: .update)
            )
        }
        _ = try DiffOracleUpdateAuthorizationValidation.blobData(
            DiffOracleUpdateAuthorization(
                authorityID: authorityID,
                revocationGeneration: authorityState.revocationGeneration,
                evidence: evidence,
                signature: Data(repeating: 0, count: DiffOracleUpdateAuthorizationValidation.signatureByteCount)
            ),
            limits: limits,
            work: &work
        )
        let input = try DiffOracleUpdateAuthorizationValidation.authenticationInput(
            authorityID: authorityID,
            revocationGeneration: authorityState.revocationGeneration,
            evidence: evidence,
            limits: limits,
            work: &work
        )
        try work.checkCancellation()
        let signature: Data
        do {
            signature = try privateKey.signature(for: input)
        } catch DiffOracleManifestError.cancelled {
            throw DiffOracleManifestError.cancelled
        } catch is CancellationError {
            throw DiffOracleManifestError.cancelled
        } catch {
            throw error
        }
        try work.checkCancellation()
        return DiffOracleUpdateAuthorization(
            authorityID: authorityID,
            revocationGeneration: authorityState.revocationGeneration,
            evidence: evidence,
            signature: signature
        )
    }

    public var description: String { "DiffOracleUpdateAuthorizationIssuer(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["issuer": "<redacted>"], displayStyle: .struct)
    }
}

/// Verification-only authority pinned to a review public key.
public struct DiffOracleUpdateAuthorizer: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let authorityID: DiffOracleSHA256
    private let publicKey: Curve25519.Signing.PublicKey

    public init(publicKeyRawRepresentation: Data) throws {
        guard publicKeyRawRepresentation.count == 32 else {
            throw DiffOracleManifestError.invalidAuthorizationKey
        }
        let parsedPublicKey: Curve25519.Signing.PublicKey
        do {
            parsedPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Array(publicKeyRawRepresentation))
        } catch {
            throw DiffOracleManifestError.invalidAuthorizationKey
        }
        publicKey = parsedPublicKey
        authorityID = try DiffOracleSHA256(bytes: Array(SHA256.hash(data: parsedPublicKey.rawRepresentation)))
    }

    public var description: String { "DiffOracleUpdateAuthorizer(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["authority": "<redacted>"], displayStyle: .struct)
    }

    fileprivate func verifies(
        _ authorization: DiffOracleUpdateAuthorization,
        baselineReceipt: DiffOracleVerificationReceipt,
        candidateReceipt: DiffOracleVerificationReceipt,
        changes: [DiffOracleChangeReference],
        authorityState: DiffOracleUpdateAuthorityState,
        currentUnixSeconds: UInt64,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> Bool {
        guard authorization.authorityID == authorityID,
            authorization.revocationGeneration == authorityState.revocationGeneration,
            authorization.evidence.policyVersion == authorityState.policyVersion,
            !authorityState.consumedAuthorizationNonces.binarySearch(authorization.evidence.authorizationNonce),
            authorization.evidence.baselineReceiptSHA256 == baselineReceipt.receiptSHA256,
            authorization.evidence.candidateReceiptSHA256 == candidateReceipt.receiptSHA256,
            try DiffOracleUpdateAuthorizationValidation.equalChanges(
                authorization.evidence.approvedChanges,
                changes,
                work: &work
            )
        else {
            return false
        }
        try DiffOracleUpdateAuthorizationValidation.validate(
            authorization.evidence,
            authorityState: authorityState,
            currentUnixSeconds: currentUnixSeconds,
            limits: limits,
            work: &work
        )
        let input = try DiffOracleUpdateAuthorizationValidation.authenticationInput(
            authorityID: authorityID,
            revocationGeneration: authorityState.revocationGeneration,
            evidence: authorization.evidence,
            limits: limits,
            work: &work
        )
        try work.checkCancellation()
        let valid = publicKey.isValidSignature(authorization.signature, for: input)
        try work.checkCancellation()
        return valid
    }
}

private enum DiffOracleUpdateAuthorizationValidation {
    static let authorizationDomain = "com.macmerge.diff-oracle-reviewed-update.v3"
    static let signatureByteCount = 64

    static func validate(
        _ evidence: DiffOracleReviewedUpdateEvidence,
        authorityState: DiffOracleUpdateAuthorityState,
        currentUnixSeconds: UInt64,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        let maximumChanges = 2 * (limits.maximumCorpusRecords + limits.maximumFixtureRecords) + 1
        guard evidence.approvedChanges.count <= maximumChanges,
            evidence.reviewID.rawValue.utf8.count <= limits.maximumIdentifierUTF8Bytes
        else {
            throw DiffOracleManifestError.inputTooLarge
        }
        try work.consume(UInt64(evidence.reviewID.rawValue.utf8.count))
        guard authorityState.revocationGeneration > 0,
            authorityState.policyVersion > 0,
            evidence.policyVersion == authorityState.policyVersion,
            !evidence.authorizationNonce.bytes.allSatisfy({ $0 == 0 }),
            evidence.issuedAtUnixSeconds <= currentUnixSeconds,
            currentUnixSeconds < evidence.expiresAtUnixSeconds,
            evidence.issuedAtUnixSeconds < evidence.expiresAtUnixSeconds,
            evidence.expiresAtUnixSeconds - evidence.issuedAtUnixSeconds <= limits.maximumAuthorizationValiditySeconds,
            evidence.baselineReceiptSHA256 != evidence.candidateReceiptSHA256,
            !evidence.approvedChanges.isEmpty,
            !evidence.reviewerIdentitySHA256.bytes.allSatisfy({ $0 == 0 }),
            !evidence.reviewArtifactSHA256.bytes.allSatisfy({ $0 == 0 })
        else {
            throw unauthorized()
        }
        for index in evidence.approvedChanges.indices {
            try work.consume()
            switch evidence.approvedChanges[index] {
            case .manifest:
                break
            case .corpus:
                try work.consume(UInt64(DiffOracleCorpusID.byteCount))
            case .fixture(let id):
                guard id.rawValue.utf8.count <= limits.maximumIdentifierUTF8Bytes else {
                    throw DiffOracleManifestError.inputTooLarge
                }
                try work.consume(UInt64(id.rawValue.utf8.count))
            }
            if index > evidence.approvedChanges.startIndex,
                !(evidence.approvedChanges[index - 1] < evidence.approvedChanges[index])
            {
                throw unauthorized()
            }
        }
    }

    static func equalChanges(
        _ left: [DiffOracleChangeReference],
        _ right: [DiffOracleChangeReference],
        work: inout DiffOracleWorkBudget
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for index in left.indices {
            try work.consume()
            guard left[index] == right[index] else { return false }
        }
        return true
    }

    static func authenticationInput(
        authorityID: DiffOracleSHA256,
        revocationGeneration: UInt64,
        evidence: DiffOracleReviewedUpdateEvidence,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> Data {
        var writer = DiffOracleCanonicalWriter(
            limits: limits,
            work: work,
            maximumByteCount: limits.maximumAuthorizationBytes
        )
        try writer.append(authorizationDomain)
        try writer.append(authorityID)
        try writer.append(revocationGeneration)
        try writer.append(evidence.reviewID)
        try writer.append(evidence.reviewerIdentitySHA256)
        try writer.append(evidence.reviewArtifactSHA256)
        try writer.append(evidence.policyVersion)
        try writer.append(evidence.authorizationNonce)
        try writer.append(evidence.issuedAtUnixSeconds)
        try writer.append(evidence.expiresAtUnixSeconds)
        try writer.append(evidence.baselineReceiptSHA256)
        try writer.append(evidence.candidateReceiptSHA256)
        try writer.appendCount(evidence.approvedChanges.count)
        for change in evidence.approvedChanges {
            try writer.append(change)
        }
        work = writer.work
        return writer.data
    }

    static func validateAuthorization(
        _ authorization: DiffOracleUpdateAuthorization,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        guard authorization.revocationGeneration > 0,
            authorization.signature.count == signatureByteCount,
            !authorization.evidence.approvedChanges.isEmpty
        else {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
        try validateEvidenceShape(authorization.evidence, limits: limits, work: &work)
    }

    static func blobData(
        _ authorization: DiffOracleUpdateAuthorization,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> Data {
        var writer = DiffOracleCanonicalWriter(
            limits: limits,
            work: work,
            maximumByteCount: limits.maximumAuthorizationBytes
        )
        try writer.append(DiffOracleUpdateAuthorization.serializationDomain)
        try writer.append(DiffOracleUpdateAuthorization.currentBlobVersion)
        try writer.append(authorization.authorityID)
        try writer.append(authorization.revocationGeneration)
        try writer.append(authorization.evidence)
        try writer.append(authorization.signature)
        work = writer.work
        return writer.data
    }

    private static func validateEvidenceShape(
        _ evidence: DiffOracleReviewedUpdateEvidence,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        let maximumChanges = 2 * (limits.maximumCorpusRecords + limits.maximumFixtureRecords) + 1
        guard evidence.policyVersion > 0,
            evidence.approvedChanges.count <= maximumChanges,
            evidence.reviewID.rawValue.utf8.count <= limits.maximumIdentifierUTF8Bytes,
            !evidence.authorizationNonce.bytes.allSatisfy({ $0 == 0 }),
            evidence.issuedAtUnixSeconds < evidence.expiresAtUnixSeconds,
            evidence.expiresAtUnixSeconds - evidence.issuedAtUnixSeconds <= limits.maximumAuthorizationValiditySeconds,
            evidence.baselineReceiptSHA256 != evidence.candidateReceiptSHA256,
            !evidence.reviewerIdentitySHA256.bytes.allSatisfy({ $0 == 0 }),
            !evidence.reviewArtifactSHA256.bytes.allSatisfy({ $0 == 0 })
        else {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
        try work.consume(UInt64(evidence.reviewID.rawValue.utf8.count))
        for index in evidence.approvedChanges.indices {
            try work.consume()
            switch evidence.approvedChanges[index] {
            case .manifest:
                break
            case .corpus:
                try work.consume(UInt64(DiffOracleCorpusID.byteCount))
            case .fixture(let id):
                guard id.rawValue.utf8.count <= limits.maximumIdentifierUTF8Bytes else {
                    throw DiffOracleManifestError.invalidAuthorizationBlob
                }
                try work.consume(UInt64(id.rawValue.utf8.count))
            }
            if index > evidence.approvedChanges.startIndex,
                !(evidence.approvedChanges[index - 1] < evidence.approvedChanges[index])
            {
                throw DiffOracleManifestError.invalidAuthorizationBlob
            }
        }
    }

    private static func unauthorized() -> DiffOracleManifestError {
        .verificationFailed(
            DiffOracleRedactedDiagnostic(code: .updateNotAuthorized, collection: .update)
        )
    }
}

public enum DiffOracleManifestVerifier: Sendable {
    public static func verify(
        manifest: DiffOracleManifest,
        sourceObservation: DiffOracleSourceObservation,
        corpusRecords: [DiffOracleCorpusRecord],
        fixtureRecords: [DiffOracleFixtureRecord],
        codecValidators: DiffOracleCanonicalCodecValidators,
        limits: DiffOracleVerificationLimits = .default
    ) throws -> DiffOracleVerificationReceipt {
        try limits.validate()
        var work = DiffOracleWorkBudget(limits: limits)
        return try verify(
            manifest: manifest,
            sourceObservation: sourceObservation,
            corpusRecords: corpusRecords,
            fixtureRecords: fixtureRecords,
            codecValidators: codecValidators,
            limits: limits,
            work: &work
        )
    }

    /// Verifies candidate observations, then requires exact reviewed authorization for every manifest change.
    public static func verifyUpdate(
        from baselineManifest: DiffOracleManifest,
        baselineReceipt: DiffOracleVerificationReceipt,
        to candidateManifest: DiffOracleManifest,
        sourceObservation: DiffOracleSourceObservation,
        corpusRecords: [DiffOracleCorpusRecord],
        fixtureRecords: [DiffOracleFixtureRecord],
        codecValidators: DiffOracleCanonicalCodecValidators,
        authorization: DiffOracleUpdateAuthorization?,
        authorizer: DiffOracleUpdateAuthorizer?,
        authorityStateStore: DiffOracleUpdateAuthorityStateStore,
        trustedTimeSource: DiffOracleTrustedTimeSource,
        limits: DiffOracleVerificationLimits = .default
    ) throws -> DiffOracleAcceptedUpdate {
        try limits.validate()
        var work = DiffOracleWorkBudget(limits: limits)
        guard candidateManifest.revision > baselineManifest.revision else {
            throw failure(.staleRecord, .update)
        }
        try DiffOracleManifestValidation.validateMonotonicRevisions(
            from: baselineManifest,
            to: candidateManifest,
            work: &work
        )
        let authorityStateSnapshot = try authorityStateStore.load()
        let authorityState = authorityStateSnapshot.state
        try DiffOracleManifestValidation.validate(baselineManifest, limits: limits, work: &work)
        try DiffOracleManifestValidation.validateAuthorityState(
            authorityState,
            baseline: baselineManifest,
            limits: limits,
            work: &work
        )
        guard authorityStateSnapshot.rollbackProtectionCounter < UInt64.max else {
            throw DiffOracleManifestError.invalidAuthorityState
        }
        let baselineData = try DiffOracleCanonical.manifestData(baselineManifest, limits: limits, work: &work)
        let baselineManifestDigest = try digest(baselineData, work: &work)
        guard baselineReceipt.manifestSHA256 == baselineManifestDigest,
            baselineReceipt.manifestRevision == baselineManifest.revision,
            authorityState.currentManifestRevision == baselineManifest.revision,
            authorityState.currentManifestSHA256 == baselineManifestDigest,
            try DiffOracleCanonical.receiptDigest(baselineReceipt, limits: limits, work: &work) == baselineReceipt.receiptSHA256
        else {
            throw failure(.invalidReceipt, .manifest)
        }
        guard trustedTimeSource.sourceID == authorityState.trustedTimeSourceID else {
            throw DiffOracleManifestError.invalidTrustedTime
        }
        let trustedTime = try trustedTimeSource.read(
            minimumUnixSeconds: authorityState.trustedTimeFloorUnixSeconds,
            minimumRollbackProtectionCounter: authorityState.trustedTimeRollbackProtectionCounter,
            predecessorIntegrityTag: authorityState.trustedTimeIntegrityTag
        )

        let candidateReceipt = try verify(
            manifest: candidateManifest,
            sourceObservation: sourceObservation,
            corpusRecords: corpusRecords,
            fixtureRecords: fixtureRecords,
            codecValidators: codecValidators,
            limits: limits,
            work: &work
        )
        let changes = try DiffOracleManifestValidation.changes(
            from: baselineManifest,
            to: candidateManifest,
            work: &work
        )
        guard !changes.isEmpty else {
            throw failure(.updateNotAuthorized, .update)
        }
        try DiffOracleManifestValidation.validateRevisionFloors(
            candidateManifest,
            floors: authorityState.revisionFloors,
            work: &work
        )
        guard let authorization, let authorizer,
            try authorizer.verifies(
                authorization,
                baselineReceipt: baselineReceipt,
                candidateReceipt: candidateReceipt,
                changes: changes,
                authorityState: authorityState,
                currentUnixSeconds: trustedTime.unixSeconds,
                limits: limits,
                work: &work
            )
        else {
            throw failure(.updateNotAuthorized, .update)
        }
        let nextState = try DiffOracleManifestValidation.acceptedAuthorityState(
            previous: authorityState,
            candidate: candidateManifest,
            candidateDigest: candidateReceipt.manifestSHA256,
            consumedNonce: authorization.evidence.authorizationNonce,
            trustedTime: trustedTime,
            limits: limits,
            work: &work
        )
        let candidateManifestData = try DiffOracleCanonical.manifestData(
            candidateManifest,
            limits: limits,
            work: &work
        )
        let candidateReceiptData = try DiffOracleCanonical.receiptData(
            candidateReceipt,
            limits: limits,
            work: &work
        )
        let candidateReceiptContentSHA256 = try digest(candidateReceiptData, work: &work)
        guard try digest(candidateManifestData, work: &work) == candidateReceipt.manifestSHA256 else {
            throw failure(.invalidReceipt, .update)
        }
        let durableCandidate = try authorityStateStore.persistCandidate(
            manifestRevision: candidateManifest.revision,
            manifestSHA256: candidateReceipt.manifestSHA256,
            canonicalManifestData: candidateManifestData,
            receiptSHA256: candidateReceipt.receiptSHA256,
            receiptContentSHA256: candidateReceiptContentSHA256,
            canonicalReceiptData: candidateReceiptData
        )
        let transitionOutcome = try authorityStateStore.transition(
            from: authorityStateSnapshot,
            durableCandidate: durableCandidate,
            to: nextState
        )
        let committedSnapshot: DiffOracleUpdateAuthorityStateSnapshot
        switch transitionOutcome {
        case .committed(let snapshot):
            committedSnapshot = snapshot
        case .notCommitted:
            throw DiffOracleManifestError.invalidAuthorityState
        case .indeterminate:
            throw DiffOracleManifestError.indeterminateAuthorityTransition
        }
        guard committedSnapshot.state == nextState,
            committedSnapshot.protectionKeyID == authorityStateSnapshot.protectionKeyID,
            committedSnapshot.predecessorIntegrityTag == authorityStateSnapshot.integrityTag,
            committedSnapshot.rollbackProtectionCounter == authorityStateSnapshot.rollbackProtectionCounter + 1
        else {
            throw DiffOracleManifestError.invalidAuthorityState
        }
        return DiffOracleAcceptedUpdate(
            receipt: candidateReceipt,
            authorityStateSnapshot: committedSnapshot
        )
    }

    private static func verify(
        manifest: DiffOracleManifest,
        sourceObservation: DiffOracleSourceObservation,
        corpusRecords: [DiffOracleCorpusRecord],
        fixtureRecords: [DiffOracleFixtureRecord],
        codecValidators: DiffOracleCanonicalCodecValidators,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> DiffOracleVerificationReceipt {
        let startingWork = work.used
        try DiffOracleManifestValidation.validate(manifest, limits: limits, work: &work)
        guard codecValidators.configuration.version == manifest.configurationCodecVersion,
            codecValidators.result.version == manifest.resultCodecVersion,
            codecValidators.derivationTranscript.version == manifest.derivationTranscriptCodecVersion,
            codecValidators.configuration.maximumInvocationWorkUnits
                == manifest.configurationCodecMaximumWorkUnits,
            codecValidators.result.maximumInvocationWorkUnits == manifest.resultCodecMaximumWorkUnits,
            codecValidators.derivationTranscript.maximumInvocationWorkUnits
                == manifest.derivationTranscriptCodecMaximumWorkUnits
        else {
            throw DiffOracleManifestError.invalidCanonicalEncoding
        }
        try DiffOracleManifestValidation.validateSourceObservation(
            sourceObservation,
            limits: limits,
            work: &work
        )
        guard sourceObservation.macSourceProvenance == manifest.macSourceProvenance,
            sourceObservation.goldenProvenance == manifest.fixtures[0].goldenProvenance
        else {
            throw failure(.changedRecord, .manifest)
        }
        guard corpusRecords.count <= limits.maximumCorpusRecords,
            fixtureRecords.count <= limits.maximumFixtureRecords
        else {
            throw DiffOracleManifestError.inputTooLarge
        }
        try DiffOracleManifestValidation.validateObservedRecordOrder(
            corpusRecords,
            limits: limits,
            collection: .corpus,
            work: &work
        )
        try DiffOracleManifestValidation.validateObservedRecordOrder(
            fixtureRecords,
            limits: limits,
            collection: .fixture,
            work: &work
        )
        try DiffOracleManifestValidation.validateObservedRecordContents(
            corpusRecords: corpusRecords,
            fixtureRecords: fixtureRecords,
            limits: limits,
            work: &work
        )
        try validateExactIDs(
            expected: manifest.corpus,
            expectedID: \.id,
            observed: corpusRecords,
            observedID: \.id,
            collection: .corpus,
            work: &work
        )
        try validateExactIDs(
            expected: manifest.fixtures,
            expectedID: \.id,
            observed: fixtureRecords,
            observedID: \.id,
            collection: .fixture,
            work: &work
        )

        var totalObservedBytes = 0
        var observedCorpusHashes: [DiffOracleSHA256] = []
        for index in manifest.corpus.indices {
            try work.consume()
            let expected = manifest.corpus[index]
            let observed = corpusRecords[index]
            guard expected.revision == observed.revision else {
                throw failure(.staleRecord, .corpus, index)
            }
            guard expected.origin == observed.origin else {
                throw failure(.changedRecord, .corpus, index)
            }
            try accumulate(observed.bytes.count, total: &totalObservedBytes, limits: limits)
            let hash = try digest(observed.bytes, work: &work)
            guard hash == expected.bytesSHA256 else {
                throw failure(.changedRecord, .corpus, index)
            }
            observedCorpusHashes.append(hash)
        }

        var observedFixtureHashes: [DiffOracleFixtureObservationHashes] = []
        for index in manifest.fixtures.indices {
            try work.consume()
            let expected = manifest.fixtures[index]
            let observed = fixtureRecords[index]
            guard expected.revision == observed.revision else {
                throw failure(.staleRecord, .fixture, index)
            }
            guard
                try DiffOracleManifestValidation.equalValues(
                    expected.corpusRecordIDs,
                    observed.corpusRecordIDs,
                    work: &work
                ), expected.goldenProvenance == observed.goldenProvenance
            else {
                throw failure(.changedRecord, .fixture, index)
            }
            let byteCounts = [
                observed.leftBytes.count,
                observed.rightBytes.count,
                observed.canonicalConfiguration.count,
                observed.canonicalExpectedResult.count,
                observed.canonicalDerivationTranscript.count
            ]
            for byteCount in byteCounts {
                try accumulate(byteCount, total: &totalObservedBytes, limits: limits)
            }
            guard
                try codecValidators.configuration.validate(
                    observed.canonicalConfiguration,
                    limits: limits,
                    work: &work
                ),
                try codecValidators.result.validate(
                    observed.canonicalExpectedResult,
                    limits: limits,
                    work: &work
                ),
                try codecValidators.derivationTranscript.validate(
                    observed.canonicalDerivationTranscript,
                    limits: limits,
                    work: &work
                )
            else {
                throw DiffOracleManifestError.invalidCanonicalEncoding
            }
            let hashes = DiffOracleFixtureObservationHashes(
                left: try digest(observed.leftBytes, work: &work),
                right: try digest(observed.rightBytes, work: &work),
                configuration: try digest(observed.canonicalConfiguration, work: &work),
                result: try digest(observed.canonicalExpectedResult, work: &work),
                derivationTranscript: try digest(observed.canonicalDerivationTranscript, work: &work)
            )
            let derivationBinding = try DiffOracleCanonical.derivationBindingDigest(
                fixtureID: expected.id,
                corpusRecordIDs: expected.corpusRecordIDs,
                corpusByID: manifest.corpus,
                fixtureHashes: hashes,
                manifest: manifest,
                goldenProvenance: expected.goldenProvenance,
                limits: limits,
                work: &work
            )
            guard hashes.left == expected.leftBytesSHA256,
                hashes.right == expected.rightBytesSHA256,
                hashes.configuration == expected.configurationSHA256,
                hashes.result == expected.expectedResultSHA256,
                hashes.derivationTranscript == expected.derivationTranscriptSHA256,
                derivationBinding == expected.derivationBindingSHA256
            else {
                throw failure(.changedRecord, .fixture, index)
            }
            observedFixtureHashes.append(hashes)
        }

        let manifestData = try DiffOracleCanonical.manifestData(manifest, limits: limits, work: &work)
        let manifestHash = try digest(manifestData, work: &work)
        let observationHash = try DiffOracleCanonical.observationDigest(
            manifestRevision: manifest.revision,
            corpusHashes: observedCorpusHashes,
            fixtureHashes: observedFixtureHashes,
            limits: limits,
            work: &work
        )
        let recordedWork = work.used - startingWork
        let provisional = DiffOracleVerificationReceipt(
            manifestRevision: manifest.revision,
            manifestSHA256: manifestHash,
            observationSHA256: observationHash,
            corpusRecordCount: corpusRecords.count,
            fixtureRecordCount: fixtureRecords.count,
            observedByteCount: totalObservedBytes,
            workUnits: recordedWork,
            receiptSHA256: try DiffOracleSHA256(bytes: Array(repeating: 0, count: DiffOracleSHA256.byteCount))
        )
        let receiptHash = try DiffOracleCanonical.receiptDigest(provisional, limits: limits, work: &work)
        return DiffOracleVerificationReceipt(
            manifestRevision: manifest.revision,
            manifestSHA256: manifestHash,
            observationSHA256: observationHash,
            corpusRecordCount: corpusRecords.count,
            fixtureRecordCount: fixtureRecords.count,
            observedByteCount: totalObservedBytes,
            workUnits: recordedWork,
            receiptSHA256: receiptHash
        )
    }

    private static func validateExactIDs<Expected, Observed, ID: Comparable>(
        expected: [Expected],
        expectedID: KeyPath<Expected, ID>,
        observed: [Observed],
        observedID: KeyPath<Observed, ID>,
        collection: DiffOracleRedactedDiagnostic.Collection,
        work: inout DiffOracleWorkBudget
    ) throws {
        var expectedIndex = 0
        var observedIndex = 0
        while expectedIndex < expected.count, observedIndex < observed.count {
            try work.consume()
            let expectedValue = expected[expectedIndex][keyPath: expectedID]
            let observedValue = observed[observedIndex][keyPath: observedID]
            if expectedValue == observedValue {
                expectedIndex += 1
                observedIndex += 1
            } else if expectedValue < observedValue {
                throw failure(.missingRecord, collection, expectedIndex)
            } else {
                throw failure(.unexpectedRecord, collection, observedIndex)
            }
        }
        if expectedIndex < expected.count {
            throw failure(.missingRecord, collection, expectedIndex)
        }
        if observedIndex < observed.count {
            throw failure(.unexpectedRecord, collection, observedIndex)
        }
    }

    private static func accumulate(
        _ byteCount: Int,
        total: inout Int,
        limits: DiffOracleVerificationLimits
    ) throws {
        guard byteCount <= limits.maximumRecordBytes,
            total <= limits.maximumTotalObservedBytes - byteCount
        else {
            throw DiffOracleManifestError.inputTooLarge
        }
        total += byteCount
    }

    private static func digest(_ data: Data, work: inout DiffOracleWorkBudget) throws -> DiffOracleSHA256 {
        try DiffOracleDigest.sha256(data, work: &work)
    }

    private static func failure(
        _ code: DiffOracleDiagnosticCode,
        _ collection: DiffOracleRedactedDiagnostic.Collection,
        _ index: Int? = nil
    ) -> DiffOracleManifestError {
        .verificationFailed(
            DiffOracleRedactedDiagnostic(code: code, collection: collection, canonicalIndex: index)
        )
    }
}

private enum DiffOracleManifestValidation {
    static func validate(
        _ manifest: DiffOracleManifest,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        try work.checkCancellation()
        guard manifest.schemaVersion == DiffOracleManifest.currentSchemaVersion,
            manifest.revision > 0,
            manifest.configurationCodecVersion > 0,
            manifest.resultCodecVersion > 0,
            manifest.derivationTranscriptCodecVersion > 0,
            (1...limits.maximumCodecCallbackWorkUnits).contains(manifest.configurationCodecMaximumWorkUnits),
            (1...limits.maximumCodecCallbackWorkUnits).contains(manifest.resultCodecMaximumWorkUnits),
            (1...limits.maximumCodecCallbackWorkUnits).contains(manifest.derivationTranscriptCodecMaximumWorkUnits),
            manifest.corpus.count <= limits.maximumCorpusRecords,
            manifest.fixtures.count <= limits.maximumFixtureRecords,
            !manifest.corpus.isEmpty,
            !manifest.fixtures.isEmpty
        else {
            throw failure(.invalidManifest, .manifest)
        }
        var corpusByID: [DiffOracleCorpusID: DiffOracleCorpusManifestEntry] = [:]
        var corpusOrigins: Set<DiffOracleCorpusOrigin> = []
        var fixtureReferenceCount: [DiffOracleIdentifier: Int] = [:]
        for fixture in manifest.fixtures {
            try validate(fixture.id, limits: limits, work: &work)
        }
        try validateRecordOrder(manifest.corpus, id: \.id, collection: .corpus, work: &work)
        try validateRecordOrder(manifest.fixtures, id: \.id, collection: .fixture, work: &work)
        try validate(manifest.macSourceProvenance, limits: limits, work: &work)

        var relationEdgeCount = 0
        var relationByteCount = 0
        for (index, entry) in manifest.corpus.enumerated() {
            try work.consume()
            try validate(entry.origin, limits: limits, work: &work)
            guard entry.revision > 0, corpusOrigins.insert(entry.origin).inserted else {
                throw failure(.invalidManifest, .corpus, index)
            }
            if case .diffWrapper(_, let caseID) = entry.origin, caseID != entry.bytesSHA256 {
                throw failure(.invalidManifest, .corpus, index)
            }
            corpusByID[entry.id] = entry
            switch entry.disposition {
            case .required(let requiredFixtureIDs):
                guard !requiredFixtureIDs.isEmpty else {
                    throw failure(.invalidManifest, .corpus, index)
                }
                try validateRelations(
                    requiredFixtureIDs,
                    edgeCount: &relationEdgeCount,
                    byteCount: &relationByteCount,
                    limits: limits,
                    work: &work
                )
                try validateRecordOrder(requiredFixtureIDs, collection: .corpus, work: &work)
                for fixtureID in requiredFixtureIDs {
                    try work.consume()
                    guard manifest.fixtures.binarySearchID(fixtureID) else {
                        throw failure(.invalidManifest, .corpus, index)
                    }
                    fixtureReferenceCount[fixtureID, default: 0] += 1
                }
            case .excluded(let reasonID):
                try validate(reasonID, limits: limits, work: &work)
            }
        }

        let goldenProvenance = manifest.fixtures[0].goldenProvenance
        for (index, fixture) in manifest.fixtures.enumerated() {
            try work.consume()
            guard fixture.revision > 0,
                !fixture.corpusRecordIDs.isEmpty,
                fixtureReferenceCount[fixture.id, default: 0] > 0
            else {
                throw failure(.invalidManifest, .fixture, index)
            }
            try validateCorpusRelations(
                fixture.corpusRecordIDs,
                edgeCount: &relationEdgeCount,
                byteCount: &relationByteCount,
                limits: limits,
                work: &work
            )
            try validateRecordOrder(fixture.corpusRecordIDs, collection: .fixture, work: &work)
            for corpusID in fixture.corpusRecordIDs {
                try work.consume()
                guard let corpusEntry = corpusByID[corpusID],
                    case .required(let fixtureIDs) = corpusEntry.disposition,
                    fixtureIDs.binarySearch(fixture.id)
                else {
                    throw failure(.invalidManifest, .fixture, index)
                }
            }
            guard fixtureReferenceCount[fixture.id] == fixture.corpusRecordIDs.count,
                fixture.goldenProvenance == goldenProvenance,
                !fixture.derivationTranscriptSHA256.bytes.allSatisfy({ $0 == 0 }),
                !fixture.derivationBindingSHA256.bytes.allSatisfy({ $0 == 0 })
            else {
                throw failure(.invalidManifest, .fixture, index)
            }
            try validate(fixture.goldenProvenance, limits: limits, work: &work)
        }
        try work.checkCancellation()
    }

    static func validateObservedRecordOrder(
        _ records: [DiffOracleCorpusRecord],
        limits: DiffOracleVerificationLimits,
        collection: DiffOracleRedactedDiagnostic.Collection,
        work: inout DiffOracleWorkBudget
    ) throws {
        for _ in records {
            try work.consume(UInt64(DiffOracleCorpusID.byteCount))
        }
        try validateRecordOrder(records, id: \.id, collection: collection, work: &work)
    }

    static func validateObservedRecordOrder(
        _ records: [DiffOracleFixtureRecord],
        limits: DiffOracleVerificationLimits,
        collection: DiffOracleRedactedDiagnostic.Collection,
        work: inout DiffOracleWorkBudget
    ) throws {
        for record in records {
            try validate(record.id, limits: limits, work: &work)
        }
        try validateRecordOrder(records, id: \.id, collection: collection, work: &work)
    }

    static func validateSourceObservation(
        _ observation: DiffOracleSourceObservation,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        try validate(observation.macSourceProvenance, limits: limits, work: &work)
        try validate(observation.goldenProvenance, limits: limits, work: &work)
    }

    static func validateObservedRecordContents(
        corpusRecords: [DiffOracleCorpusRecord],
        fixtureRecords: [DiffOracleFixtureRecord],
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        for record in corpusRecords {
            try work.consume(UInt64(DiffOracleCorpusID.byteCount))
            try validate(record.origin, limits: limits, work: &work)
        }
        var relationEdgeCount = 0
        var relationByteCount = 0
        for record in fixtureRecords {
            try validateCorpusRelations(
                record.corpusRecordIDs,
                edgeCount: &relationEdgeCount,
                byteCount: &relationByteCount,
                limits: limits,
                work: &work
            )
            try validate(record.goldenProvenance, limits: limits, work: &work)
        }
    }

    static func validateRecordOrder<ID: Comparable>(
        _ ids: [ID],
        collection: DiffOracleRedactedDiagnostic.Collection,
        work: inout DiffOracleWorkBudget
    ) throws {
        for index in ids.indices {
            try work.consume()
            if index > ids.startIndex {
                if ids[index] == ids[index - 1] {
                    throw failure(.duplicateRecord, collection, index)
                }
                guard ids[index - 1] < ids[index] else {
                    throw failure(.nonCanonicalOrder, collection, index)
                }
            }
        }
    }

    private static func validateRecordOrder<Record, ID: Comparable>(
        _ records: [Record],
        id: KeyPath<Record, ID>,
        collection: DiffOracleRedactedDiagnostic.Collection,
        work: inout DiffOracleWorkBudget
    ) throws {
        for index in records.indices {
            try work.consume()
            guard index > records.startIndex else { continue }
            let previous = records[index - 1][keyPath: id]
            let current = records[index][keyPath: id]
            if current == previous {
                throw failure(.duplicateRecord, collection, index)
            }
            guard previous < current else {
                throw failure(.nonCanonicalOrder, collection, index)
            }
        }
    }

    static func changes(
        from baseline: DiffOracleManifest,
        to candidate: DiffOracleManifest,
        work: inout DiffOracleWorkBudget
    ) throws -> [DiffOracleChangeReference] {
        if baseline.schemaVersion == candidate.schemaVersion,
            baseline.revision == candidate.revision,
            baseline.configurationCodecVersion == candidate.configurationCodecVersion,
            baseline.resultCodecVersion == candidate.resultCodecVersion,
            baseline.derivationTranscriptCodecVersion == candidate.derivationTranscriptCodecVersion,
            baseline.configurationCodecMaximumWorkUnits == candidate.configurationCodecMaximumWorkUnits,
            baseline.resultCodecMaximumWorkUnits == candidate.resultCodecMaximumWorkUnits,
            baseline.derivationTranscriptCodecMaximumWorkUnits
                == candidate.derivationTranscriptCodecMaximumWorkUnits,
            baseline.macSourceProvenance == candidate.macSourceProvenance,
            try equalCorpusEntries(baseline.corpus, candidate.corpus, work: &work),
            try equalFixtureEntries(baseline.fixtures, candidate.fixtures, work: &work)
        {
            return []
        }
        var result: [DiffOracleChangeReference] = [.manifest]
        try appendChanges(
            baseline.corpus,
            candidate.corpus,
            id: \.id,
            equal: equalCorpusEntry,
            reference: DiffOracleChangeReference.corpus,
            result: &result,
            work: &work
        )
        try appendChanges(
            baseline.fixtures,
            candidate.fixtures,
            id: \.id,
            equal: equalFixtureEntry,
            reference: DiffOracleChangeReference.fixture,
            result: &result,
            work: &work
        )
        return result
    }

    static func validateMonotonicRevisions(
        from baseline: DiffOracleManifest,
        to candidate: DiffOracleManifest,
        work: inout DiffOracleWorkBudget
    ) throws {
        try validateMonotonicRevisions(
            baseline.corpus,
            candidate.corpus,
            id: \.id,
            revision: \.revision,
            equal: equalCorpusEntry,
            work: &work
        )
        try validateMonotonicRevisions(
            baseline.fixtures,
            candidate.fixtures,
            id: \.id,
            revision: \.revision,
            equal: equalFixtureEntry,
            work: &work
        )
    }

    static func validateRevisionFloors(
        _ candidate: DiffOracleManifest,
        floors: [DiffOracleRevisionFloor],
        work: inout DiffOracleWorkBudget
    ) throws {
        try validateRevisionFloors(
            candidate.corpus,
            reference: DiffOracleChangeReference.corpus,
            id: \.id,
            revision: \.revision,
            floors: floors,
            work: &work
        )
        try validateRevisionFloors(
            candidate.fixtures,
            reference: DiffOracleChangeReference.fixture,
            id: \.id,
            revision: \.revision,
            floors: floors,
            work: &work
        )
    }

    static func validateAuthorityState(
        _ state: DiffOracleUpdateAuthorityState,
        baseline: DiffOracleManifest? = nil,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        guard state.revocationGeneration > 0,
            state.policyVersion > 0,
            state.currentManifestRevision > 0,
            !state.currentManifestSHA256.bytes.allSatisfy({ $0 == 0 }),
            !state.trustedTimeSourceID.isZero,
            state.trustedTimeFloorUnixSeconds > 0,
            state.trustedTimeRollbackProtectionCounter > 0,
            !state.trustedTimeIntegrityTag.isZero,
            state.consumedAuthorizationNonces.count <= limits.maximumConsumedAuthorizationNonces,
            state.revisionFloors.count <= limits.maximumRevisionFloorRecords
        else {
            throw failure(.invalidManifest, .update)
        }
        for index in state.consumedAuthorizationNonces.indices {
            try work.consume()
            guard !state.consumedAuthorizationNonces[index].bytes.allSatisfy({ $0 == 0 }),
                index == state.consumedAuthorizationNonces.startIndex
                    || state.consumedAuthorizationNonces[index - 1] < state.consumedAuthorizationNonces[index]
            else {
                throw failure(.invalidManifest, .update)
            }
        }
        for index in state.revisionFloors.indices {
            try work.consume()
            let floor = state.revisionFloors[index]
            switch floor.record {
            case .manifest:
                throw failure(.invalidManifest, .update)
            case .corpus:
                try work.consume(UInt64(DiffOracleCorpusID.byteCount))
            case .fixture(let id):
                try validate(id, limits: limits, work: &work)
            }
            guard floor.revision > 0,
                index == state.revisionFloors.startIndex
                    || state.revisionFloors[index - 1].record < floor.record
            else {
                throw failure(.invalidManifest, .update)
            }
        }
        guard let baseline else { return }
        let expectedCount = baseline.corpus.count + baseline.fixtures.count
        var floorIndex = state.revisionFloors.startIndex
        var activeCount = 0
        for entry in baseline.corpus {
            try work.consume()
            while floorIndex < state.revisionFloors.endIndex,
                state.revisionFloors[floorIndex].isTombstone
            {
                try work.consume()
                floorIndex += 1
            }
            guard floorIndex < state.revisionFloors.endIndex,
                state.revisionFloors[floorIndex].record == .corpus(entry.id),
                state.revisionFloors[floorIndex].revision == entry.revision
            else {
                throw failure(.invalidManifest, .update)
            }
            activeCount += 1
            floorIndex += 1
        }
        for entry in baseline.fixtures {
            try work.consume()
            while floorIndex < state.revisionFloors.endIndex,
                state.revisionFloors[floorIndex].isTombstone
            {
                try work.consume()
                floorIndex += 1
            }
            guard floorIndex < state.revisionFloors.endIndex,
                state.revisionFloors[floorIndex].record == .fixture(entry.id),
                state.revisionFloors[floorIndex].revision == entry.revision
            else {
                throw failure(.invalidManifest, .update)
            }
            activeCount += 1
            floorIndex += 1
        }
        while floorIndex < state.revisionFloors.endIndex {
            try work.consume()
            guard state.revisionFloors[floorIndex].isTombstone else {
                throw failure(.invalidManifest, .update)
            }
            floorIndex += 1
        }
        guard activeCount == expectedCount else {
            throw failure(.invalidManifest, .update)
        }
    }

    static func acceptedAuthorityState(
        previous: DiffOracleUpdateAuthorityState,
        candidate: DiffOracleManifest,
        candidateDigest: DiffOracleSHA256,
        consumedNonce: DiffOracleSHA256,
        trustedTime: DiffOracleTrustedTimeObservation,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> DiffOracleUpdateAuthorityState {
        guard previous.consumedAuthorizationNonces.count < limits.maximumConsumedAuthorizationNonces else {
            throw DiffOracleManifestError.inputTooLarge
        }
        try work.consume(UInt64(previous.consumedAuthorizationNonces.count + 1))
        var nonces = previous.consumedAuthorizationNonces
        let nonceIndex = nonces.partitioningIndex { $0 >= consumedNonce }
        guard nonceIndex == nonces.endIndex || nonces[nonceIndex] != consumedNonce else {
            throw failure(.updateNotAuthorized, .update)
        }
        nonces.insert(consumedNonce, at: nonceIndex)

        let floors = try nextRevisionFloors(
            previous: previous.revisionFloors,
            candidate: candidate,
            limits: limits,
            work: &work
        )
        return DiffOracleUpdateAuthorityState(
            revocationGeneration: previous.revocationGeneration,
            policyVersion: previous.policyVersion,
            currentManifestRevision: candidate.revision,
            currentManifestSHA256: candidateDigest,
            trustedTimeSourceID: trustedTime.sourceID,
            trustedTimeFloorUnixSeconds: trustedTime.unixSeconds,
            trustedTimeRollbackProtectionCounter: trustedTime.rollbackProtectionCounter,
            trustedTimeIntegrityTag: trustedTime.integrityTag,
            consumedAuthorizationNonces: nonces,
            revisionFloors: floors
        )
    }

    static func equalValues<Value: Equatable>(
        _ left: [Value],
        _ right: [Value],
        work: inout DiffOracleWorkBudget
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for index in left.indices {
            try work.consume()
            guard left[index] == right[index] else { return false }
        }
        return true
    }

    private static func appendChanges<Entry: Equatable, ID: Comparable>(
        _ baseline: [Entry],
        _ candidate: [Entry],
        id: KeyPath<Entry, ID>,
        equal: (Entry, Entry, inout DiffOracleWorkBudget) throws -> Bool,
        reference: (ID) -> DiffOracleChangeReference,
        result: inout [DiffOracleChangeReference],
        work: inout DiffOracleWorkBudget
    ) throws {
        var baselineIndex = 0
        var candidateIndex = 0
        while baselineIndex < baseline.count || candidateIndex < candidate.count {
            try work.consume()
            guard baselineIndex < baseline.count else {
                result.append(reference(candidate[candidateIndex][keyPath: id]))
                candidateIndex += 1
                continue
            }
            guard candidateIndex < candidate.count else {
                result.append(reference(baseline[baselineIndex][keyPath: id]))
                baselineIndex += 1
                continue
            }
            let baselineID = baseline[baselineIndex][keyPath: id]
            let candidateID = candidate[candidateIndex][keyPath: id]
            if baselineID == candidateID {
                if try !equal(baseline[baselineIndex], candidate[candidateIndex], &work) {
                    result.append(reference(baselineID))
                }
                baselineIndex += 1
                candidateIndex += 1
            } else if baselineID < candidateID {
                result.append(reference(baselineID))
                baselineIndex += 1
            } else {
                result.append(reference(candidateID))
                candidateIndex += 1
            }
        }
    }

    private static func validateRevisionFloors<Entry, ID>(
        _ candidate: [Entry],
        reference: (ID) -> DiffOracleChangeReference,
        id: KeyPath<Entry, ID>,
        revision: KeyPath<Entry, UInt64>,
        floors: [DiffOracleRevisionFloor],
        work: inout DiffOracleWorkBudget
    ) throws {
        for entry in candidate {
            try work.consume()
            let record = reference(entry[keyPath: id])
            let index = floors.partitioningIndex { $0.record >= record }
            guard
                index == floors.endIndex
                    || floors[index].record != record
                    || !floors[index].isTombstone
                    || entry[keyPath: revision] > floors[index].revision
            else {
                throw failure(.staleRecord, .update)
            }
        }
    }

    private static func validateMonotonicRevisions<Entry, ID: Comparable>(
        _ baseline: [Entry],
        _ candidate: [Entry],
        id: KeyPath<Entry, ID>,
        revision: KeyPath<Entry, UInt64>,
        equal: (Entry, Entry, inout DiffOracleWorkBudget) throws -> Bool,
        work: inout DiffOracleWorkBudget
    ) throws {
        var baselineIndex = 0
        var candidateIndex = 0
        while baselineIndex < baseline.count, candidateIndex < candidate.count {
            try work.consume()
            let baselineID = baseline[baselineIndex][keyPath: id]
            let candidateID = candidate[candidateIndex][keyPath: id]
            if baselineID == candidateID {
                if try !equal(baseline[baselineIndex], candidate[candidateIndex], &work),
                    candidate[candidateIndex][keyPath: revision] <= baseline[baselineIndex][keyPath: revision]
                {
                    throw failure(.staleRecord, .update)
                }
                baselineIndex += 1
                candidateIndex += 1
            } else if baselineID < candidateID {
                baselineIndex += 1
            } else {
                candidateIndex += 1
            }
        }
    }

    private static func nextRevisionFloors(
        previous: [DiffOracleRevisionFloor],
        candidate: DiffOracleManifest,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> [DiffOracleRevisionFloor] {
        guard candidate.corpus.count <= limits.maximumRevisionFloorRecords - candidate.fixtures.count else {
            throw DiffOracleManifestError.inputTooLarge
        }
        var current: [DiffOracleRevisionFloor] = []
        for entry in candidate.corpus {
            try work.consume()
            current.append(DiffOracleRevisionFloor(record: .corpus(entry.id), revision: entry.revision, isTombstone: false))
        }
        for entry in candidate.fixtures {
            try work.consume()
            current.append(
                DiffOracleRevisionFloor(record: .fixture(entry.id), revision: entry.revision, isTombstone: false)
            )
        }
        var floors: [DiffOracleRevisionFloor] = []
        var previousIndex = previous.startIndex
        var currentIndex = current.startIndex
        while previousIndex < previous.endIndex || currentIndex < current.endIndex {
            try work.consume()
            let floor: DiffOracleRevisionFloor
            if previousIndex == previous.endIndex {
                floor = current[currentIndex]
                currentIndex += 1
            } else if currentIndex == current.endIndex {
                let previousFloor = previous[previousIndex]
                floor = DiffOracleRevisionFloor(
                    record: previousFloor.record,
                    revision: previousFloor.revision,
                    isTombstone: true
                )
                previousIndex += 1
            } else if previous[previousIndex].record == current[currentIndex].record {
                floor = current[currentIndex]
                previousIndex += 1
                currentIndex += 1
            } else if previous[previousIndex].record < current[currentIndex].record {
                let previousFloor = previous[previousIndex]
                floor = DiffOracleRevisionFloor(
                    record: previousFloor.record,
                    revision: previousFloor.revision,
                    isTombstone: true
                )
                previousIndex += 1
            } else {
                floor = current[currentIndex]
                currentIndex += 1
            }
            guard floors.count < limits.maximumRevisionFloorRecords else {
                throw DiffOracleManifestError.inputTooLarge
            }
            floors.append(floor)
        }
        return floors
    }

    private static func validateRelations(
        _ ids: [DiffOracleIdentifier],
        edgeCount: inout Int,
        byteCount: inout Int,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        guard ids.count <= limits.maximumRelationEdges - edgeCount else {
            throw DiffOracleManifestError.inputTooLarge
        }
        edgeCount += ids.count
        for id in ids {
            let bytes = id.rawValue.utf8.count
            guard bytes <= limits.maximumRelationBytes - byteCount else {
                throw DiffOracleManifestError.inputTooLarge
            }
            byteCount += bytes
            try validate(id, limits: limits, work: &work)
        }
    }

    private static func validateCorpusRelations(
        _ ids: [DiffOracleCorpusID],
        edgeCount: inout Int,
        byteCount: inout Int,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        guard ids.count <= limits.maximumRelationEdges - edgeCount else {
            throw DiffOracleManifestError.inputTooLarge
        }
        edgeCount += ids.count
        for _ in ids {
            guard DiffOracleCorpusID.byteCount <= limits.maximumRelationBytes - byteCount else {
                throw DiffOracleManifestError.inputTooLarge
            }
            byteCount += DiffOracleCorpusID.byteCount
            try work.consume(UInt64(DiffOracleCorpusID.byteCount))
        }
    }

    private static func equalCorpusEntries(
        _ left: [DiffOracleCorpusManifestEntry],
        _ right: [DiffOracleCorpusManifestEntry],
        work: inout DiffOracleWorkBudget
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for index in left.indices {
            guard try equalCorpusEntry(left[index], right[index], work: &work) else { return false }
        }
        return true
    }

    private static func equalFixtureEntries(
        _ left: [DiffOracleFixtureManifestEntry],
        _ right: [DiffOracleFixtureManifestEntry],
        work: inout DiffOracleWorkBudget
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for index in left.indices {
            guard try equalFixtureEntry(left[index], right[index], work: &work) else { return false }
        }
        return true
    }

    private static func equalCorpusEntry(
        _ left: DiffOracleCorpusManifestEntry,
        _ right: DiffOracleCorpusManifestEntry,
        work: inout DiffOracleWorkBudget
    ) throws -> Bool {
        try work.consume()
        guard left.id == right.id,
            left.revision == right.revision,
            left.origin == right.origin,
            left.bytesSHA256 == right.bytesSHA256
        else {
            return false
        }
        switch (left.disposition, right.disposition) {
        case (.required(let leftIDs), .required(let rightIDs)):
            return try equalValues(leftIDs, rightIDs, work: &work)
        case (.excluded(let leftReason), .excluded(let rightReason)):
            return leftReason == rightReason
        default:
            return false
        }
    }

    private static func equalFixtureEntry(
        _ left: DiffOracleFixtureManifestEntry,
        _ right: DiffOracleFixtureManifestEntry,
        work: inout DiffOracleWorkBudget
    ) throws -> Bool {
        try work.consume()
        guard left.id == right.id,
            left.revision == right.revision,
            try equalValues(left.corpusRecordIDs, right.corpusRecordIDs, work: &work)
        else {
            return false
        }
        return left.leftBytesSHA256 == right.leftBytesSHA256
            && left.rightBytesSHA256 == right.rightBytesSHA256
            && left.configurationSHA256 == right.configurationSHA256
            && left.expectedResultSHA256 == right.expectedResultSHA256
            && left.derivationTranscriptSHA256 == right.derivationTranscriptSHA256
            && left.derivationBindingSHA256 == right.derivationBindingSHA256
            && left.goldenProvenance == right.goldenProvenance
    }

    private static func validate(
        _ provenance: DiffOracleMacSourceProvenance,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        guard provenance.sourceTreeInventoryEntryCount > 0,
            !provenance.patchedXDiffContentManifestSHA256.isZero,
            !provenance.cBridgeSourceSHA256.isZero,
            !provenance.swiftDiffSourceSHA256.isZero,
            !provenance.trustedExtractorExecutableSHA256.isZero,
            !provenance.trustedExtractorSchemaSHA256.isZero,
            !provenance.trustedExtractorConfigurationSHA256.isZero,
            !provenance.sourceTreeInventorySHA256.isZero
        else {
            throw failure(.invalidManifest, .manifest)
        }
        try validate(provenance.trustedExtractorVersion, limits: limits, work: &work)
    }

    private static func validate(
        _ provenance: DiffOracleGoldenProvenance,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        guard !provenance.oracleExecutableSHA256.isZero,
            !provenance.generatorExecutableSHA256.isZero,
            !provenance.generatorSchemaSHA256.isZero,
            !provenance.generatorConfigurationSHA256.isZero
        else {
            throw failure(.invalidManifest, .manifest)
        }
        try validate(provenance.generatorVersion, limits: limits, work: &work)
        try validate(provenance.architecture, limits: limits, work: &work)
        try validate(provenance.buildConfiguration, limits: limits, work: &work)
    }

    private static func validate(
        _ origin: DiffOracleCorpusOrigin,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        switch origin {
        case .diffWrapper(let testName, _):
            try validate(testName, limits: limits, work: &work)
        case .testingData:
            try work.consume(UInt64(DiffOraclePathKey.byteCount))
        }
    }

    private static func validate(
        _ identifier: DiffOracleIdentifier,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws {
        try work.consume(UInt64(identifier.rawValue.utf8.count))
        guard identifier.rawValue.utf8.count <= limits.maximumIdentifierUTF8Bytes else {
            throw DiffOracleManifestError.inputTooLarge
        }
    }

    private static func failure(
        _ code: DiffOracleDiagnosticCode,
        _ collection: DiffOracleRedactedDiagnostic.Collection,
        _ index: Int? = nil
    ) -> DiffOracleManifestError {
        .verificationFailed(
            DiffOracleRedactedDiagnostic(code: code, collection: collection, canonicalIndex: index)
        )
    }
}

private enum DiffOracleCanonical {
    static let observationDomain = "com.macmerge.diff-oracle-observation.v4"

    static func manifestData(
        _ manifest: DiffOracleManifest,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> Data {
        var writer = DiffOracleCanonicalWriter(limits: limits, work: work)
        try writer.append(DiffOracleManifest.serializationDomain)
        try writer.append(manifest.schemaVersion)
        try writer.append(manifest.revision)
        try writer.append(manifest.configurationCodecVersion)
        try writer.append(manifest.resultCodecVersion)
        try writer.append(manifest.derivationTranscriptCodecVersion)
        try writer.append(manifest.configurationCodecMaximumWorkUnits)
        try writer.append(manifest.resultCodecMaximumWorkUnits)
        try writer.append(manifest.derivationTranscriptCodecMaximumWorkUnits)
        try writer.append(manifest.macSourceProvenance)
        try writer.appendCount(manifest.corpus.count)
        for entry in manifest.corpus {
            try writer.append(entry)
        }
        try writer.appendCount(manifest.fixtures.count)
        for fixture in manifest.fixtures {
            try writer.append(fixture)
        }
        work = writer.work
        return writer.data
    }

    static func authorityStateData(
        _ state: DiffOracleUpdateAuthorityState,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> Data {
        var writer = DiffOracleCanonicalWriter(limits: limits, work: work)
        try writer.append(DiffOracleUpdateAuthorityState.serializationDomain)
        try writer.append(state.revocationGeneration)
        try writer.append(state.policyVersion)
        try writer.append(state.currentManifestRevision)
        try writer.append(state.currentManifestSHA256)
        try writer.append(state.trustedTimeSourceID)
        try writer.append(state.trustedTimeFloorUnixSeconds)
        try writer.append(state.trustedTimeRollbackProtectionCounter)
        try writer.append(state.trustedTimeIntegrityTag)
        try writer.appendCount(state.consumedAuthorizationNonces.count)
        for nonce in state.consumedAuthorizationNonces {
            try writer.append(nonce)
        }
        try writer.appendCount(state.revisionFloors.count)
        for floor in state.revisionFloors {
            try writer.append(floor.record)
            try writer.append(floor.revision)
            try writer.append(floor.isTombstone ? UInt8(1) : UInt8(0))
        }
        work = writer.work
        return writer.data
    }

    static func observationDigest(
        manifestRevision: UInt64,
        corpusHashes: [DiffOracleSHA256],
        fixtureHashes: [DiffOracleFixtureObservationHashes],
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> DiffOracleSHA256 {
        var writer = DiffOracleCanonicalWriter(limits: limits, work: work)
        try writer.append(observationDomain)
        try writer.append(manifestRevision)
        try writer.appendCount(corpusHashes.count)
        for hash in corpusHashes {
            try writer.append(hash)
        }
        try writer.appendCount(fixtureHashes.count)
        for hashes in fixtureHashes {
            try writer.append(hashes.left)
            try writer.append(hashes.right)
            try writer.append(hashes.configuration)
            try writer.append(hashes.result)
            try writer.append(hashes.derivationTranscript)
        }
        work = writer.work
        return try DiffOracleDigest.sha256(writer.data, work: &work)
    }

    static func derivationBindingDigest(
        fixtureID: DiffOracleIdentifier,
        corpusRecordIDs: [DiffOracleCorpusID],
        corpusByID: [DiffOracleCorpusManifestEntry],
        fixtureHashes: DiffOracleFixtureObservationHashes,
        manifest: DiffOracleManifest,
        goldenProvenance: DiffOracleGoldenProvenance,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> DiffOracleSHA256 {
        var writer = DiffOracleCanonicalWriter(limits: limits, work: work)
        try writer.append("com.macmerge.diff-oracle-fixture-derivation.v3")
        try writer.append(fixtureID)
        try writer.append(manifest.configurationCodecVersion)
        try writer.append(manifest.resultCodecVersion)
        try writer.append(manifest.derivationTranscriptCodecVersion)
        try writer.append(manifest.configurationCodecMaximumWorkUnits)
        try writer.append(manifest.resultCodecMaximumWorkUnits)
        try writer.append(manifest.derivationTranscriptCodecMaximumWorkUnits)
        try writer.append(goldenProvenance)
        try writer.appendCount(corpusRecordIDs.count)
        for corpusID in corpusRecordIDs {
            guard let entry = corpusByID.binarySearchEntry(corpusID) else {
                throw DiffOracleManifestError.verificationFailed(
                    DiffOracleRedactedDiagnostic(code: .invalidManifest, collection: .fixture)
                )
            }
            try writer.appendDerivationCorpusEntry(entry)
        }
        try writer.append(fixtureHashes.left)
        try writer.append(fixtureHashes.right)
        try writer.append(fixtureHashes.configuration)
        try writer.append(fixtureHashes.result)
        try writer.append(fixtureHashes.derivationTranscript)
        work = writer.work
        return try DiffOracleDigest.sha256(writer.data, work: &work)
    }

    static func receiptDigest(
        _ receipt: DiffOracleVerificationReceipt,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> DiffOracleSHA256 {
        var writer = DiffOracleCanonicalWriter(limits: limits, work: work)
        try appendReceiptPayload(receipt, to: &writer)
        work = writer.work
        return try DiffOracleDigest.sha256(writer.data, work: &work)
    }

    static func receiptData(
        _ receipt: DiffOracleVerificationReceipt,
        limits: DiffOracleVerificationLimits,
        work: inout DiffOracleWorkBudget
    ) throws -> Data {
        guard try receiptDigest(receipt, limits: limits, work: &work) == receipt.receiptSHA256 else {
            throw DiffOracleManifestError.verificationFailed(
                DiffOracleRedactedDiagnostic(code: .invalidReceipt, collection: .manifest)
            )
        }
        var writer = DiffOracleCanonicalWriter(limits: limits, work: work)
        try appendReceiptPayload(receipt, to: &writer)
        try writer.append(receipt.receiptSHA256)
        work = writer.work
        return writer.data
    }

    static func appendReceiptPayload(
        _ receipt: DiffOracleVerificationReceipt,
        to writer: inout DiffOracleCanonicalWriter
    ) throws {
        try writer.append(DiffOracleVerificationReceipt.serializationDomain)
        try writer.append(receipt.schemaVersion)
        try writer.append(receipt.manifestRevision)
        try writer.append(receipt.manifestSHA256)
        try writer.append(receipt.observationSHA256)
        try writer.appendCount(receipt.corpusRecordCount)
        try writer.appendCount(receipt.fixtureRecordCount)
        try writer.appendCount(receipt.observedByteCount)
        try writer.append(receipt.workUnits)
    }
}

private enum DiffOracleDigest {
    static let chunkByteCount = 64 * 1_024

    static func sha256(_ data: Data, work: inout DiffOracleWorkBudget) throws -> DiffOracleSHA256 {
        var hasher = SHA256()
        var index = data.startIndex
        while index < data.endIndex {
            let end = data.index(index, offsetBy: min(chunkByteCount, data.distance(from: index, to: data.endIndex)))
            let count = data.distance(from: index, to: end)
            try work.consume(UInt64(count))
            hasher.update(data: data[index..<end])
            index = end
        }
        try work.checkCancellation()
        return try DiffOracleSHA256(bytes: Array(hasher.finalize()))
    }
}

private struct DiffOracleCanonicalWriter {
    let limits: DiffOracleVerificationLimits
    let maximumByteCount: Int
    var work: DiffOracleWorkBudget
    private(set) var data = Data()

    init(
        limits: DiffOracleVerificationLimits,
        work: DiffOracleWorkBudget,
        maximumByteCount: Int? = nil
    ) {
        self.limits = limits
        self.maximumByteCount = maximumByteCount ?? limits.maximumCanonicalBytes
        self.work = work
    }

    mutating func append(_ value: UInt8) throws {
        try appendRaw(Data([value]))
    }

    mutating func append(_ value: UInt32) throws {
        try appendRaw(Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> UInt32($0 * 8)) }))
    }

    mutating func append(_ value: UInt64) throws {
        try appendRaw(Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> UInt64($0 * 8)) }))
    }

    mutating func appendCount(_ value: Int) throws {
        guard value >= 0 else { throw DiffOracleManifestError.inputTooLarge }
        try append(UInt64(value))
    }

    mutating func append(_ value: String) throws {
        let bytes = Data(value.utf8)
        try appendCount(bytes.count)
        try appendRaw(bytes)
    }

    mutating func append(_ value: DiffOracleIdentifier) throws {
        try append(value.rawValue)
    }

    mutating func append(_ value: DiffOracleCorpusID) throws {
        try appendRaw(Data(value.bytes))
    }

    mutating func append(_ value: DiffOracleSHA256) throws {
        try appendRaw(Data(value.bytes))
    }

    mutating func append(_ value: DiffOraclePathKey) throws {
        try appendRaw(Data(value.bytes))
    }

    mutating func append(_ value: Data) throws {
        try appendCount(value.count)
        try appendRaw(value)
    }

    mutating func append(_ value: DiffOracleGitObjectID) throws {
        try append(value.rawValue)
    }

    mutating func append(_ value: DiffOracleMacSourceProvenance) throws {
        try append(value.macMergeCommit)
        try append(value.patchedXDiffContentManifestSHA256)
        try append(value.cBridgeSourceSHA256)
        try append(value.swiftDiffSourceSHA256)
        try append(value.trustedExtractorVersion)
        try append(value.trustedExtractorExecutableSHA256)
        try append(value.trustedExtractorSchemaSHA256)
        try append(value.trustedExtractorConfigurationSHA256)
        try append(value.sourceTreeInventorySHA256)
        try append(value.sourceTreeInventoryEntryCount)
    }

    mutating func append(_ value: DiffOracleCorpusOrigin) throws {
        switch value {
        case .diffWrapper(let testName, let caseID):
            try append(UInt8(0))
            try append(testName)
            try append(caseID)
        case .testingData(let pathKey):
            try append(UInt8(1))
            try append(pathKey)
        }
    }

    mutating func append(_ value: DiffOracleCorpusDisposition) throws {
        switch value {
        case .required(let fixtureIDs):
            try append(UInt8(0))
            try appendCount(fixtureIDs.count)
            for id in fixtureIDs {
                try append(id)
            }
        case .excluded(let reasonID):
            try append(UInt8(1))
            try append(reasonID)
        }
    }

    mutating func append(_ value: DiffOracleCorpusManifestEntry) throws {
        try append(value.id)
        try append(value.revision)
        try append(value.origin)
        try append(value.bytesSHA256)
        try append(value.disposition)
    }

    /// Omits reverse fixture adjacency; serializing it once per forward edge makes dense graphs quadratic.
    mutating func appendDerivationCorpusEntry(_ value: DiffOracleCorpusManifestEntry) throws {
        try append(value.id)
        try append(value.revision)
        try append(value.origin)
        try append(value.bytesSHA256)
    }

    mutating func append(_ value: DiffOracleGoldenProvenance) throws {
        try append(value.winMergeCommit)
        try append(value.windowsXDiffTree)
        try append(value.topLevelLibXDiffCommit)
        try append(value.topLevelLibXDiffTree)
        try append(value.nestedLibXDiffCommit)
        try append(value.nestedLibXDiffTree)
        try append(value.oracleExecutableSHA256)
        try append(value.generatorVersion)
        try append(value.generatorExecutableSHA256)
        try append(value.generatorSchemaSHA256)
        try append(value.generatorConfigurationSHA256)
        try append(value.architecture)
        try append(value.buildConfiguration)
    }

    mutating func append(_ value: DiffOracleFixtureManifestEntry) throws {
        try append(value.id)
        try append(value.revision)
        try appendCount(value.corpusRecordIDs.count)
        for id in value.corpusRecordIDs {
            try append(id)
        }
        try append(value.leftBytesSHA256)
        try append(value.rightBytesSHA256)
        try append(value.configurationSHA256)
        try append(value.expectedResultSHA256)
        try append(value.derivationTranscriptSHA256)
        try append(value.derivationBindingSHA256)
        try append(value.goldenProvenance)
    }

    mutating func append(_ value: DiffOracleChangeReference) throws {
        switch value {
        case .manifest:
            try append(UInt8(0))
        case .corpus(let id):
            try append(UInt8(1))
            try append(id)
        case .fixture(let id):
            try append(UInt8(2))
            try append(id)
        }
    }

    mutating func append(_ value: DiffOracleReviewedUpdateEvidence) throws {
        try append(value.reviewID)
        try append(value.reviewerIdentitySHA256)
        try append(value.reviewArtifactSHA256)
        try append(value.policyVersion)
        try append(value.authorizationNonce)
        try append(value.issuedAtUnixSeconds)
        try append(value.expiresAtUnixSeconds)
        try append(value.baselineReceiptSHA256)
        try append(value.candidateReceiptSHA256)
        try appendCount(value.approvedChanges.count)
        for change in value.approvedChanges {
            try append(change)
        }
    }

    private mutating func appendRaw(_ bytes: Data) throws {
        guard bytes.count <= maximumByteCount - data.count else {
            throw DiffOracleManifestError.canonicalOutputTooLarge
        }
        try work.consume(UInt64(bytes.count))
        data.append(bytes)
    }
}

private struct DiffOracleCanonicalReader {
    let data: Data
    let limits: DiffOracleVerificationLimits
    var work: DiffOracleWorkBudget
    private var offset = 0

    init(data: Data, limits: DiffOracleVerificationLimits, work: DiffOracleWorkBudget) {
        self.data = data
        self.limits = limits
        self.work = work
    }

    var isAtEnd: Bool { offset == data.count }

    mutating func readUInt8() throws -> UInt8 {
        let bytes = try readRaw(count: 1)
        return bytes[bytes.startIndex]
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readRaw(count: 4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try readRaw(count: 8)
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    mutating func readCount(maximum: Int) throws -> Int {
        let value = try readUInt64()
        guard value <= UInt64(maximum), value <= UInt64(Int.max) else {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
        return Int(value)
    }

    mutating func readString() throws -> String {
        let bytes = try readData(maximumByteCount: limits.maximumIdentifierUTF8Bytes)
        guard let decoded = String(data: bytes, encoding: .utf8) else {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
        let normalized = decoded.precomposedStringWithCanonicalMapping
        guard decoded.utf8.elementsEqual(bytes),
            normalized.utf8.elementsEqual(bytes),
            normalized.unicodeScalars.allSatisfy({ $0.value >= 0x20 && !(0x7F...0x9F).contains($0.value) })
        else {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
        return normalized
    }

    mutating func readDomain(_ expected: String) throws -> Bool {
        let expectedBytes = Data(expected.utf8)
        let bytes = try readData(maximumByteCount: expectedBytes.count)
        return bytes == expectedBytes
    }

    mutating func readIdentifier() throws -> DiffOracleIdentifier {
        do {
            return try DiffOracleIdentifier(readString())
        } catch DiffOracleManifestError.invalidIdentifier {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
    }

    mutating func readSHA256() throws -> DiffOracleSHA256 {
        do {
            return try DiffOracleSHA256(bytes: Array(try readRaw(count: DiffOracleSHA256.byteCount)))
        } catch DiffOracleManifestError.invalidSHA256 {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
    }

    mutating func readCorpusID() throws -> DiffOracleCorpusID {
        do {
            return try DiffOracleCorpusID(canonicalBytes: Array(try readRaw(count: DiffOracleCorpusID.byteCount)))
        } catch DiffOracleManifestError.invalidCorpusID {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
    }

    mutating func readData(maximumByteCount: Int) throws -> Data {
        let count = try readCount(maximum: maximumByteCount)
        return try readRaw(count: count)
    }

    mutating func readReviewedUpdateEvidence() throws -> DiffOracleReviewedUpdateEvidence {
        let reviewID = try readIdentifier()
        let reviewerIdentitySHA256 = try readSHA256()
        let reviewArtifactSHA256 = try readSHA256()
        let policyVersion = try readUInt64()
        let authorizationNonce = try readSHA256()
        let issuedAtUnixSeconds = try readUInt64()
        let expiresAtUnixSeconds = try readUInt64()
        let baselineReceiptSHA256 = try readSHA256()
        let candidateReceiptSHA256 = try readSHA256()
        let maximumChanges = 2 * (limits.maximumCorpusRecords + limits.maximumFixtureRecords) + 1
        let count = try readCount(maximum: maximumChanges)
        var approvedChanges: [DiffOracleChangeReference] = []
        for _ in 0..<count {
            approvedChanges.append(try readChangeReference())
        }
        return DiffOracleReviewedUpdateEvidence(
            reviewID: reviewID,
            reviewerIdentitySHA256: reviewerIdentitySHA256,
            reviewArtifactSHA256: reviewArtifactSHA256,
            policyVersion: policyVersion,
            authorizationNonce: authorizationNonce,
            issuedAtUnixSeconds: issuedAtUnixSeconds,
            expiresAtUnixSeconds: expiresAtUnixSeconds,
            baselineReceiptSHA256: baselineReceiptSHA256,
            candidateReceiptSHA256: candidateReceiptSHA256,
            approvedChanges: approvedChanges
        )
    }

    private mutating func readChangeReference() throws -> DiffOracleChangeReference {
        switch try readUInt8() {
        case 0:
            return .manifest
        case 1:
            return .corpus(try readCorpusID())
        case 2:
            return .fixture(try readIdentifier())
        default:
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
    }

    private mutating func readRaw(count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else {
            throw DiffOracleManifestError.invalidAuthorizationBlob
        }
        try work.consume(UInt64(count))
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        offset += count
        return data[start..<end]
    }
}

private struct DiffOracleWorkBudget {
    let maximum: UInt64
    let cancellationCheckInterval: UInt64
    private(set) var used: UInt64 = 0
    private var nextCancellationCheck: UInt64 = 0

    init(limits: DiffOracleVerificationLimits) {
        maximum = limits.maximumWorkUnits
        cancellationCheckInterval = UInt64(limits.cancellationCheckInterval)
    }

    mutating func consume(_ amount: UInt64 = 1) throws {
        guard amount <= maximum - used else {
            throw DiffOracleManifestError.workLimitExceeded
        }
        used += amount
        if used >= nextCancellationCheck {
            try checkCancellation()
            let (next, overflowed) = used.addingReportingOverflow(cancellationCheckInterval)
            nextCancellationCheck = overflowed ? UInt64.max : next
        }
    }

    func checkCancellation() throws {
        if Task.isCancelled {
            throw DiffOracleManifestError.cancelled
        }
    }

}

extension Array where Element == DiffOracleIdentifier {
    fileprivate func binarySearch(_ target: DiffOracleIdentifier) -> Bool {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + distance(from: lowerBound, to: upperBound) / 2
            if self[middle] == target { return true }
            if self[middle] < target {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return false
    }
}

extension Array where Element == DiffOracleCorpusID {
    fileprivate func binarySearch(_ target: DiffOracleCorpusID) -> Bool {
        let index = partitioningIndex { $0 >= target }
        return index != endIndex && self[index] == target
    }
}

extension Array where Element == DiffOracleSHA256 {
    fileprivate func binarySearch(_ target: DiffOracleSHA256) -> Bool {
        let index = partitioningIndex { $0 >= target }
        return index != endIndex && self[index] == target
    }
}

extension Array {
    fileprivate func partitioningIndex(where belongsInSecondPartition: (Element) -> Bool) -> Index {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + distance(from: lowerBound, to: upperBound) / 2
            if belongsInSecondPartition(self[middle]) {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }
        return lowerBound
    }
}

extension Array where Element == DiffOracleCorpusManifestEntry {
    fileprivate func binarySearchEntry(_ target: DiffOracleCorpusID) -> Element? {
        let index = partitioningIndex { $0.id >= target }
        guard index != endIndex, self[index].id == target else { return nil }
        return self[index]
    }
}

extension Array where Element == DiffOracleFixtureManifestEntry {
    fileprivate func binarySearchID(_ target: DiffOracleIdentifier) -> Bool {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + distance(from: lowerBound, to: upperBound) / 2
            if self[middle].id == target { return true }
            if self[middle].id < target {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return false
    }
}
