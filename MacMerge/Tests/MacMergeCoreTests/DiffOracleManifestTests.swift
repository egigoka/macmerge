import CryptoKit
import Foundation
import MacMergeCore
import XCTest

private func assertEqualWithoutValues<T: Equatable>(
    _ expression1: @autoclosure () throws -> T,
    _ expression2: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let matches = try expression1() == expression2()
        XCTAssertTrue(matches, message(), file: file, line: line)
    } catch {
        XCTFail("comparison threw an error", file: file, line: line)
    }
}

private func assertNotEqualWithoutValues<T: Equatable>(
    _ expression1: @autoclosure () throws -> T,
    _ expression2: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let differs = try expression1() != expression2()
        XCTAssertTrue(differs, message(), file: file, line: line)
    } catch {
        XCTFail("comparison threw an error", file: file, line: line)
    }
}

final class DiffOracleManifestTests: XCTestCase {
    func testSHA256AndGitObjectIDsRequireExactCanonicalValues() throws {
        let digest = try DiffOracleSHA256(hex: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        assertEqualWithoutValues(digest.bytes, Array(SHA256.hash(data: Data("abc".utf8))))
        assertEqualWithoutValues(digest.hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        assertThrows(.invalidSHA256) { try DiffOracleSHA256(bytes: [0]) }
        assertThrows(.invalidSHA256) { try DiffOracleSHA256(hex: digest.hex.uppercased()) }
        assertThrows(.invalidGitObjectID) { try DiffOracleGitObjectID(String(repeating: "0", count: 40)) }
        assertThrows(.invalidGitObjectID) { try DiffOracleGitObjectID(String(repeating: "A", count: 40)) }
        assertEqualWithoutValues(try DiffOracleGitObjectID(String(repeating: "a", count: 40)).rawValue.count, 40)
    }

    func testProvenanceRetainsEveryExactIdentityAndRejectsZeroDigests() throws {
        let oracle = try makeOracle()
        let golden = oracle.goldenProvenance
        let mac = oracle.macSourceProvenance

        assertEqualWithoutValues(golden.winMergeCommit.rawValue, String(repeating: "1", count: 40))
        assertEqualWithoutValues(golden.windowsXDiffTree.rawValue, String(repeating: "2", count: 40))
        assertEqualWithoutValues(golden.topLevelLibXDiffCommit.rawValue, String(repeating: "3", count: 40))
        assertEqualWithoutValues(golden.topLevelLibXDiffTree.rawValue, String(repeating: "4", count: 40))
        assertEqualWithoutValues(golden.nestedLibXDiffCommit.rawValue, String(repeating: "5", count: 40))
        assertEqualWithoutValues(golden.nestedLibXDiffTree.rawValue, String(repeating: "6", count: 40))
        assertEqualWithoutValues(golden.oracleExecutableSHA256, try digest("oracle-executable"))
        assertEqualWithoutValues(golden.generatorExecutableSHA256, try digest("generator-executable"))
        assertEqualWithoutValues(golden.generatorSchemaSHA256, try digest("generator-schema"))
        assertEqualWithoutValues(golden.generatorConfigurationSHA256, try digest("generator-configuration"))
        assertEqualWithoutValues(golden.generatorVersion.rawValue, "generator-v1")
        assertEqualWithoutValues(golden.architecture.rawValue, "x86_64")
        assertEqualWithoutValues(golden.buildConfiguration.rawValue, "Release")
        assertEqualWithoutValues(mac.macMergeCommit.rawValue, String(repeating: "7", count: 40))
        assertEqualWithoutValues(mac.patchedXDiffContentManifestSHA256, try digest("patched-xdiff-content"))
        assertEqualWithoutValues(mac.cBridgeSourceSHA256, try digest("c-bridge-source"))
        assertEqualWithoutValues(mac.swiftDiffSourceSHA256, try digest("swift-diff-source"))
        assertEqualWithoutValues(mac.trustedExtractorExecutableSHA256, try digest("extractor-executable"))
        assertEqualWithoutValues(mac.trustedExtractorSchemaSHA256, try digest("extractor-schema"))
        assertEqualWithoutValues(mac.trustedExtractorConfigurationSHA256, try digest("extractor-configuration"))
        assertEqualWithoutValues(mac.sourceTreeInventorySHA256, try digest("source-tree-inventory"))
        assertEqualWithoutValues(mac.sourceTreeInventoryEntryCount, 41)
        assertEqualWithoutValues(mac.trustedExtractorVersion.rawValue, "extractor-v1")

        let zero = try zeroDigest()
        let invalidMacValues = [
            makeMacProvenance(patchedXDiff: zero),
            makeMacProvenance(cBridge: zero),
            makeMacProvenance(swiftDiff: zero),
            makeMacProvenance(extractorExecutable: zero),
            makeMacProvenance(extractorSchema: zero),
            makeMacProvenance(extractorConfiguration: zero),
            makeMacProvenance(sourceTree: zero),
            makeMacProvenance(sourceTreeEntryCount: 0)
        ]
        for invalid in invalidMacValues {
            assertInvalidManifest(try makeOracle(macSourceProvenance: invalid).manifest)
        }

        let invalidGoldenValues = [
            makeGoldenProvenance(oracleExecutable: zero),
            makeGoldenProvenance(generatorExecutable: zero),
            makeGoldenProvenance(generatorSchema: zero),
            makeGoldenProvenance(generatorConfiguration: zero)
        ]
        for invalid in invalidGoldenValues {
            assertInvalidManifest(try makeOracle(goldenProvenance: invalid).manifest)
        }

        let multipleFixtures = try makeOracle(fixtureIDs: ["fixture-alpha", "fixture-zeta"])
        let substitutedFixture = copyFixtureEntry(
            multipleFixtures.manifest.fixtures[1],
            goldenProvenance: makeGoldenProvenance(generatorSchema: try digest("substituted-schema"))
        )
        assertInvalidManifest(
            copyManifest(
                multipleFixtures.manifest,
                fixtures: [multipleFixtures.manifest.fixtures[0], substitutedFixture]
            ),
            collection: .fixture,
            canonicalIndex: 1
        )
    }

    func testSourceObservationRequiresExactGoldenAndMacProvenance() throws {
        let oracle = try makeOracle()
        let changedGolden = makeGoldenProvenance(generatorSchema: try digest("different-schema"))
        let changedMac = makeMacProvenance(sourceTree: try digest("different-tree"))

        assertVerificationFailure(code: .changedRecord, collection: .manifest) {
            try DiffOracleManifestVerifier.verify(
                manifest: oracle.manifest,
                sourceObservation: DiffOracleSourceObservation(
                    goldenProvenance: changedGolden,
                    macSourceProvenance: oracle.macSourceProvenance
                ),
                corpusRecords: oracle.corpusRecords,
                fixtureRecords: oracle.fixtureRecords,
                codecValidators: oracle.validators
            )
        }
        assertVerificationFailure(code: .changedRecord, collection: .manifest) {
            try DiffOracleManifestVerifier.verify(
                manifest: oracle.manifest,
                sourceObservation: DiffOracleSourceObservation(
                    goldenProvenance: oracle.goldenProvenance,
                    macSourceProvenance: changedMac
                ),
                corpusRecords: oracle.corpusRecords,
                fixtureRecords: oracle.fixtureRecords,
                codecValidators: oracle.validators
            )
        }
    }

    func testCorpusAndPathIdentifiersAreOpaqueAndRejectRawPathLeakage() throws {
        let sourceDigest = try digest("repository/source/identity")
        let corpusID = try DiffOracleCorpusID(sourceIdentitySHA256: sourceDigest)
        let path = try DiffOracleIdentifier("Testing/Data/folder/private.txt")
        let key = try makePathHMACKey()
        let pathKey = try DiffOraclePathKey(testingDataRelativePath: path, key: key)

        assertNotEqualWithoutValues(corpusID.bytes, sourceDigest.bytes)
        XCTAssertFalse(corpusID.description.contains(sourceDigest.hex))
        XCTAssertFalse(String(reflecting: corpusID).contains("repository"))
        XCTAssertFalse(pathKey.description.contains(path.rawValue))
        XCTAssertFalse(String(reflecting: pathKey).contains("private.txt"))
        assertEqualWithoutValues(corpusID.bytes.count, DiffOracleCorpusID.byteCount)
        assertEqualWithoutValues(pathKey.bytes.count, DiffOraclePathKey.byteCount)
        assertThrows(.invalidCorpusID) {
            try DiffOracleCorpusID(sourceIdentitySHA256: zeroDigest())
        }

        for rejectedPath in [
            "Testing/Data/",
            "Testing/Data/../secret",
            "Testing/Data/./file",
            "Testing/Data//file",
            "Testing\\Data\\file",
            "/Testing/Data/file",
            "Raw/repository/path"
        ] {
            assertThrows(.invalidPathKey) {
                try DiffOraclePathKey(testingDataRelativePath: DiffOracleIdentifier(rejectedPath), key: key)
            }
        }
    }

    func testPathKeyUsesIndependentHMACVectorAndManifestSerializesOnlyOpaqueKey() throws {
        let secret = Data(0..<UInt8(DiffOracleSHA256.byteCount))
        let key = try makePathHMACKey(secret: secret)
        let path = try DiffOracleIdentifier("Testing/Data/folder/private.txt")
        let pathKey = try DiffOraclePathKey(testingDataRelativePath: path, key: key)
        let expected = try DiffOracleSHA256(
            hex: "aadf3a588e7b856ccf9b851862fd7a0ee01e39ceb4c454b58548c05265101ee1"
        )

        XCTAssertTrue(pathKey.bytes == expected.bytes, "HMAC vector mismatch")
        XCTAssertTrue(
            try DiffOraclePathKey(testingDataRelativePath: path, key: makePathHMACKey(secret: Data(1...32)))
                != pathKey,
            "path keys from distinct secrets matched"
        )

        let oracle = try makeOracle()
        let oldCorpus = oracle.manifest.corpus[0]
        let newCorpus = DiffOracleCorpusManifestEntry(
            id: oldCorpus.id,
            revision: oldCorpus.revision,
            origin: .testingData(pathKey: pathKey),
            bytesSHA256: oldCorpus.bytesSHA256,
            disposition: oldCorpus.disposition
        )
        let oldFixture = oracle.manifest.fixtures[0]
        let hashes = try fixtureHashes(oracle.fixtureRecords[0])
        let newFixture = copyFixtureEntry(
            oldFixture,
            derivationBindingSHA256: try derivationBinding(
                fixtureID: oldFixture.id,
                corpusEntries: [newCorpus],
                hashes: hashes,
                codecMetadata: standardCodecMetadata,
                goldenProvenance: oldFixture.goldenProvenance
            )
        )
        let manifest = copyManifest(oracle.manifest, corpus: [newCorpus], fixtures: [newFixture])
        let data = try manifest.canonicalData()
        var encodedOrigin = Data([1])
        encodedOrigin.append(contentsOf: pathKey.bytes)

        XCTAssertNotNil(data.range(of: encodedOrigin), "testing-data origin encoding missing")
        XCTAssertNil(data.range(of: Data(path.rawValue.utf8)), "raw path present in manifest encoding")
    }

    func testIdentifiersRejectNoncanonicalNFCBytesAndControls() throws {
        assertEqualWithoutValues(try DiffOracleIdentifier("caf\u{00e9}").rawValue, "caf\u{00e9}")
        assertThrows(.invalidIdentifier) { try DiffOracleIdentifier("cafe\u{0301}") }
        assertThrows(.invalidIdentifier) { try DiffOracleIdentifier("line\nfeed") }
        assertThrows(.invalidIdentifier) { try DiffOracleIdentifier("delete\u{007f}") }
        assertThrows(.invalidIdentifier) { try DiffOracleIdentifier("control\u{0085}") }
    }

    func testPathHMACKeyOwnsHighEntropyNoCopyBacking() throws {
        let secret = randomBytes(count: DiffOracleSHA256.byteCount)
        let backing = MutableDataBacking(secret)
        let keyIdentifier = try DiffOracleSHA256(bytes: Array(SHA256.hash(data: secret)))
        let attestation = DiffOraclePathKeyStrengthAttestation(
            policyVersion: 3,
            attestedEntropyBits: 256,
            keyIdentifierSHA256: keyIdentifier,
            evidenceSHA256: try digest("hsm-key-generation-evidence")
        )
        let key = try DiffOraclePathHMACKey(
            secretKey: backing.data,
            strengthAttestation: attestation,
            verifyStrengthAttestation: { received in received == attestation }
        )
        let path = try DiffOracleIdentifier("Testing/Data/security/owned-key.txt")
        let before = try DiffOraclePathKey(testingDataRelativePath: path, key: key)

        backing.overwrite(with: 0)
        let after = try DiffOraclePathKey(testingDataRelativePath: path, key: key)

        assertEqualWithoutValues(after, before)
        XCTAssertFalse(key.description.contains(secret.base64EncodedString()))
        assertThrows(.invalidPathKey) {
            try DiffOraclePathHMACKey(
                secretKey: randomBytes(count: 31),
                strengthAttestation: attestation,
                verifyStrengthAttestation: { _ in true }
            )
        }
    }

    func testPathHMACKeyRejectsEachInvalidAttestationAndCancellation() async throws {
        let secret = Data(0..<UInt8(DiffOracleSHA256.byteCount))
        let keyIdentifier = try sha256(secret)
        let evidence = try digest("attestation-evidence")
        let valid = DiffOraclePathKeyStrengthAttestation(
            policyVersion: 1,
            attestedEntropyBits: DiffOraclePathKeyStrengthAttestation.minimumEntropyBits,
            keyIdentifierSHA256: keyIdentifier,
            evidenceSHA256: evidence
        )
        let invalid = [
            DiffOraclePathKeyStrengthAttestation(
                policyVersion: 0,
                attestedEntropyBits: valid.attestedEntropyBits,
                keyIdentifierSHA256: keyIdentifier,
                evidenceSHA256: evidence
            ),
            DiffOraclePathKeyStrengthAttestation(
                policyVersion: 1,
                attestedEntropyBits: valid.attestedEntropyBits - 1,
                keyIdentifierSHA256: keyIdentifier,
                evidenceSHA256: evidence
            ),
            DiffOraclePathKeyStrengthAttestation(
                policyVersion: 1,
                attestedEntropyBits: valid.attestedEntropyBits,
                keyIdentifierSHA256: try digest("different-key"),
                evidenceSHA256: evidence
            ),
            DiffOraclePathKeyStrengthAttestation(
                policyVersion: 1,
                attestedEntropyBits: valid.attestedEntropyBits,
                keyIdentifierSHA256: try zeroDigest(),
                evidenceSHA256: evidence
            ),
            DiffOraclePathKeyStrengthAttestation(
                policyVersion: 1,
                attestedEntropyBits: valid.attestedEntropyBits,
                keyIdentifierSHA256: keyIdentifier,
                evidenceSHA256: try zeroDigest()
            )
        ]
        for attestation in invalid {
            assertThrows(.invalidPathKey) {
                try DiffOraclePathHMACKey(
                    secretKey: secret,
                    strengthAttestation: attestation,
                    verifyStrengthAttestation: { _ in true }
                )
            }
        }
        assertThrows(.invalidPathKey) {
            try DiffOraclePathHMACKey(
                secretKey: secret,
                strengthAttestation: valid,
                verifyStrengthAttestation: { _ in false }
            )
        }
        assertThrows(.cancelled) {
            try DiffOraclePathHMACKey(
                secretKey: secret,
                strengthAttestation: valid,
                verifyStrengthAttestation: { _ in throw CancellationError() }
            )
        }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return Result {
                try DiffOraclePathHMACKey(
                    secretKey: secret,
                    strengthAttestation: valid,
                    verifyStrengthAttestation: { _ in true }
                )
            }
        }
        assertFailure(await task.value, equals: .cancelled)
    }

    func testCanonicalVersionedConfigurationResultAndTranscriptCodecs() throws {
        let probe = LockedArray<CodecCall>()
        let validators = try validators(probe: probe)
        let oracle = try makeOracle(validators: validators)

        _ = try verify(oracle)

        assertEqualWithoutValues(
            probe.values,
            [
                CodecCall(role: "configuration", data: oracle.fixtureRecords[0].canonicalConfiguration),
                CodecCall(role: "result", data: oracle.fixtureRecords[0].canonicalExpectedResult),
                CodecCall(role: "transcript", data: oracle.fixtureRecords[0].canonicalDerivationTranscript)
            ]
        )
        assertEqualWithoutValues(oracle.manifest.configurationCodecVersion, validators.configuration.version)
        assertEqualWithoutValues(oracle.manifest.resultCodecVersion, validators.result.version)
        assertEqualWithoutValues(oracle.manifest.derivationTranscriptCodecVersion, validators.derivationTranscript.version)

        let wrongVersion = try DiffOracleCanonicalCodecValidator(
            version: standardCodecMetadata.configurationVersion + 1,
            maximumInvocationWorkUnits: standardCodecMetadata.configurationWorkUnits,
            canonicalize: { data, _ in data }
        )
        assertThrows(.invalidCanonicalEncoding) {
            try DiffOracleManifestVerifier.verify(
                manifest: oracle.manifest,
                sourceObservation: oracle.sourceObservation,
                corpusRecords: oracle.corpusRecords,
                fixtureRecords: oracle.fixtureRecords,
                codecValidators: DiffOracleCanonicalCodecValidators(
                    configuration: wrongVersion,
                    result: validators.result,
                    derivationTranscript: validators.derivationTranscript
                )
            )
        }

        let noncanonical = try DiffOracleCanonicalCodecValidator(
            version: standardCodecMetadata.configurationVersion,
            maximumInvocationWorkUnits: standardCodecMetadata.configurationWorkUnits,
            canonicalize: { data, _ in data + Data([0]) }
        )
        assertThrows(.invalidCanonicalEncoding) {
            try DiffOracleManifestVerifier.verify(
                manifest: oracle.manifest,
                sourceObservation: oracle.sourceObservation,
                corpusRecords: oracle.corpusRecords,
                fixtureRecords: oracle.fixtureRecords,
                codecValidators: DiffOracleCanonicalCodecValidators(
                    configuration: noncanonical,
                    result: validators.result,
                    derivationTranscript: validators.derivationTranscript
                )
            )
        }
    }

    func testFixtureDerivationBindsCorpusCodecsInputsResultTranscriptAndProvenance() throws {
        let oracle = try makeOracle()
        XCTAssertNoThrow(try verify(oracle))

        let changedTranscript = try replacingFixtureRecord(
            in: oracle,
            canonicalDerivationTranscript: Data("different transcript".utf8)
        )
        assertVerificationFailure(code: .changedRecord, collection: .fixture, canonicalIndex: 0) {
            try verify(changedTranscript)
        }

        let changedCorpus = try replacingCorpusRecord(in: oracle, bytes: Data("different corpus".utf8))
        assertVerificationFailure(code: .changedRecord, collection: .corpus, canonicalIndex: 0) {
            try verify(changedCorpus)
        }

        let wrongBinding = DiffOracleFixtureManifestEntry(
            id: oracle.manifest.fixtures[0].id,
            revision: oracle.manifest.fixtures[0].revision,
            corpusRecordIDs: oracle.manifest.fixtures[0].corpusRecordIDs,
            leftBytesSHA256: oracle.manifest.fixtures[0].leftBytesSHA256,
            rightBytesSHA256: oracle.manifest.fixtures[0].rightBytesSHA256,
            configurationSHA256: oracle.manifest.fixtures[0].configurationSHA256,
            expectedResultSHA256: oracle.manifest.fixtures[0].expectedResultSHA256,
            derivationTranscriptSHA256: oracle.manifest.fixtures[0].derivationTranscriptSHA256,
            derivationBindingSHA256: try digest("wrong-derivation-binding"),
            goldenProvenance: oracle.manifest.fixtures[0].goldenProvenance
        )
        let invalidManifest = copyManifest(oracle.manifest, fixtures: [wrongBinding])
        assertVerificationFailure(code: .changedRecord, collection: .fixture, canonicalIndex: 0) {
            try DiffOracleManifestVerifier.verify(
                manifest: invalidManifest,
                sourceObservation: oracle.sourceObservation,
                corpusRecords: oracle.corpusRecords,
                fixtureRecords: oracle.fixtureRecords,
                codecValidators: oracle.validators
            )
        }
    }

    func testFixtureRelationsMustBeCanonicalBidirectionalAndWithinCaps() throws {
        let oracle = try makeOracle(
            corpusSpecs: [
                CorpusSpec(label: "alpha", revision: 1, bytes: Data("alpha corpus".utf8)),
                CorpusSpec(label: "beta", revision: 1, bytes: Data("beta corpus".utf8))
            ]
        )
        XCTAssertNoThrow(try oracle.manifest.canonicalData())

        let first = oracle.manifest.corpus[0]
        let missingReverse = DiffOracleCorpusManifestEntry(
            id: first.id,
            revision: first.revision,
            origin: first.origin,
            bytesSHA256: first.bytesSHA256,
            disposition: .excluded(reasonID: try DiffOracleIdentifier("not-linked"))
        )
        assertInvalidManifest(
            copyManifest(oracle.manifest, corpus: [missingReverse] + oracle.manifest.corpus.dropFirst()),
            collection: .fixture,
            canonicalIndex: 0
        )

        let limits = try makeLimits(maximumRelationEdges: 1)
        assertThrows(.inputTooLarge) { try oracle.manifest.canonicalData(limits: limits) }
        let byteLimits = try makeLimits(maximumRelationBytes: 32)
        assertThrows(.inputTooLarge) { try oracle.manifest.canonicalData(limits: byteLimits) }

        let duplicateFixtureID = oracle.manifest.fixtures[0].id
        let duplicateAdjacency = DiffOracleCorpusManifestEntry(
            id: first.id,
            revision: first.revision,
            origin: first.origin,
            bytesSHA256: first.bytesSHA256,
            disposition: .required(fixtureIDs: [duplicateFixtureID, duplicateFixtureID])
        )
        assertVerificationFailure(code: .duplicateRecord, collection: .corpus, canonicalIndex: 1) {
            try copyManifest(
                oracle.manifest,
                corpus: [duplicateAdjacency] + oracle.manifest.corpus.dropFirst()
            ).canonicalData()
        }

        let multiFixture = try makeOracle(fixtureIDs: ["fixture-zeta", "fixture-alpha"])
        assertVerificationFailure(code: .nonCanonicalOrder, collection: .fixture, canonicalIndex: 1) {
            try copyManifest(
                multiFixture.manifest,
                fixtures: multiFixture.manifest.fixtures.reversed()
            ).canonicalData()
        }

        let reversedCorpusIDs = oracle.manifest.corpus.map(\.id).reversed()
        let reversedFixture = copyFixtureEntry(
            oracle.manifest.fixtures[0],
            corpusRecordIDs: Array(reversedCorpusIDs)
        )
        assertVerificationFailure(code: .nonCanonicalOrder, collection: .fixture, canonicalIndex: 1) {
            try copyManifest(
                oracle.manifest,
                fixtures: [reversedFixture]
            ).canonicalData()
        }
    }

    func testManifestAndReceiptCanonicalBytesAreDeterministicAndRejectOrderAmbiguity() throws {
        let oracle = try makeOracle(
            corpusSpecs: [
                CorpusSpec(label: "zeta", revision: 1, bytes: Data("zeta corpus".utf8)),
                CorpusSpec(label: "alpha", revision: 1, bytes: Data("alpha corpus".utf8))
            ]
        )
        let reorderedInputOracle = try makeOracle(
            corpusSpecs: [
                CorpusSpec(label: "alpha", revision: 1, bytes: Data("alpha corpus".utf8)),
                CorpusSpec(label: "zeta", revision: 1, bytes: Data("zeta corpus".utf8))
            ]
        )
        let manifestData = try oracle.manifest.canonicalData()
        let firstReceipt = try verify(oracle)
        let secondReceipt = try verify(oracle)

        assertEqualWithoutValues(try oracle.manifest.canonicalData(), manifestData)
        assertEqualWithoutValues(try reorderedInputOracle.manifest.canonicalData(), manifestData)
        assertEqualWithoutValues(try verify(reorderedInputOracle).canonicalData(), try firstReceipt.canonicalData())
        assertEqualWithoutValues(secondReceipt, firstReceipt)
        assertEqualWithoutValues(try secondReceipt.canonicalData(), try firstReceipt.canonicalData())
        assertEqualWithoutValues(firstReceipt.manifestSHA256, try sha256(manifestData))
        assertEqualWithoutValues(firstReceipt.receiptSHA256, secondReceipt.receiptSHA256)
        XCTAssertFalse(firstReceipt.receiptSHA256.bytes.allSatisfy { $0 == 0 })
        assertEqualWithoutValues(try sha256(manifestData).hex, "8649dd9a38648b2f3b42523ba8f20f501dc8f859dcac87758e54ceff7c4b59b0")
        assertEqualWithoutValues(
            try sha256(firstReceipt.canonicalData()).hex,
            "26821199c4548d22340b93799ed84bbf217b249be76dd034191c5588fd877100"
        )

        assertVerificationFailure(code: .nonCanonicalOrder, collection: .corpus, canonicalIndex: 1) {
            try copyManifest(oracle.manifest, corpus: oracle.manifest.corpus.reversed()).canonicalData()
        }
        assertVerificationFailure(code: .nonCanonicalOrder, collection: .corpus, canonicalIndex: 1) {
            try DiffOracleManifestVerifier.verify(
                manifest: oracle.manifest,
                sourceObservation: oracle.sourceObservation,
                corpusRecords: oracle.corpusRecords.reversed(),
                fixtureRecords: oracle.fixtureRecords,
                codecValidators: oracle.validators
            )
        }
    }

    func testSignedAuthorizationBlobPublicExportImportRoundTripAndDomainBoundary() throws {
        let update = try makeUpdateScenario()
        let blob = try update.authorization.canonicalData()
        let imported = try DiffOracleUpdateAuthorization(canonicalData: blob)

        assertEqualWithoutValues(try imported.canonicalData(), blob)
        assertEqualWithoutValues(imported, update.authorization)
        XCTAssertFalse(imported.description.contains(update.evidence.reviewID.rawValue))
        XCTAssertNoThrow(try accept(update, authorization: imported))

        var wrongDomain = blob
        let domain = Data(DiffOracleUpdateAuthorization.serializationDomain.utf8)
        let domainRange = try XCTUnwrap(wrongDomain.range(of: domain))
        wrongDomain[domainRange.lowerBound] ^= 1
        assertThrows(.invalidAuthorizationBlob) {
            try DiffOracleUpdateAuthorization(canonicalData: wrongDomain)
        }

        let canonicalReviewID = Data(update.evidence.reviewID.rawValue.utf8)
        let decomposedReviewID = Data("review-e\u{0301}".utf8)
        let nonNFCBlob = try replacingLengthPrefixedValue(
            canonicalReviewID,
            with: decomposedReviewID,
            in: blob
        )
        assertThrows(.invalidAuthorizationBlob) {
            try DiffOracleUpdateAuthorization(canonicalData: nonNFCBlob)
        }
    }

    func testAuthorizationSignatureAndEverySignedFieldAreIndependentlyBound() throws {
        let update = try makeUpdateScenario()
        let blob = try update.authorization.canonicalData()
        var forgedSignature = blob
        forgedSignature[forgedSignature.index(before: forgedSignature.endIndex)] ^= 1
        let forged = try DiffOracleUpdateAuthorization(canonicalData: forgedSignature)
        assertUpdateNotAuthorized { try accept(update, authorization: forged) }

        let mutatedEvidence = [
            copyEvidence(update.evidence, reviewID: try DiffOracleIdentifier("review-x")),
            copyEvidence(update.evidence, reviewerIdentitySHA256: try digest("other-reviewer")),
            copyEvidence(update.evidence, reviewArtifactSHA256: try digest("other-artifact")),
            copyEvidence(update.evidence, policyVersion: update.evidence.policyVersion + 1),
            copyEvidence(update.evidence, authorizationNonce: try digest("other-nonce")),
            copyEvidence(update.evidence, issuedAtUnixSeconds: update.evidence.issuedAtUnixSeconds - 1),
            copyEvidence(update.evidence, expiresAtUnixSeconds: update.evidence.expiresAtUnixSeconds + 1),
            copyEvidence(update.evidence, baselineReceiptSHA256: try digest("other-baseline")),
            copyEvidence(update.evidence, candidateReceiptSHA256: try digest("other-candidate")),
            copyEvidence(update.evidence, approvedChanges: [.manifest])
        ]
        let signature = Data(blob.suffix(64))
        for evidence in mutatedEvidence {
            let authorization = try DiffOracleUpdateAuthorization(
                canonicalData: independentAuthorizationBlob(
                    authorityID: update.authorizer.authorityID,
                    revocationGeneration: update.authorityState.revocationGeneration,
                    evidence: evidence,
                    signature: signature
                )
            )
            assertUpdateNotAuthorized { try accept(update, authorization: authorization) }
        }
    }

    func testAuthorizationWireFormatHasIndependentVectorAndRejectsMalformedForms() throws {
        let privateKeyData = Data(0..<UInt8(DiffOracleSHA256.byteCount))
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        let issuer = try DiffOracleUpdateAuthorizationIssuer(privateKeyRawRepresentation: privateKeyData)
        let authorizer = try DiffOracleUpdateAuthorizer(publicKeyRawRepresentation: issuer.publicKeyRawRepresentation)
        let update = try makeUpdateScenario(issuer: issuer, authorizer: authorizer)
        let issuedBlob = try update.authorization.canonicalData()
        let issuedSignature = Data(issuedBlob.suffix(64))
        let signatureInput = independentAuthorizationInput(
            authorityID: authorizer.authorityID,
            revocationGeneration: update.authorityState.revocationGeneration,
            evidence: update.evidence
        )
        let signature = Data(0..<64)
        let blob = independentAuthorizationBlob(
            authorityID: authorizer.authorityID,
            revocationGeneration: update.authorityState.revocationGeneration,
            evidence: update.evidence,
            signature: signature
        )
        let parsed = try DiffOracleUpdateAuthorization(canonicalData: blob)

        XCTAssertTrue(privateKey.publicKey.isValidSignature(issuedSignature, for: signatureInput))
        assertEqualWithoutValues(
            try sha256(signatureInput).hex,
            "fbeb55434a702a8be0d39d6953a25b5285a2ebd500fd4296fd24145f8a356d50"
        )
        XCTAssertTrue(try parsed.canonicalData() == blob, "authorization wire round-trip mismatch")
        assertEqualWithoutValues(try sha256(blob).hex, "5655952f9da63a39d2d94635ee7730d6292043f192af47b3cbfa8b48530c2080")

        var wrongVersion = blob
        let versionOffset = 8 + DiffOracleUpdateAuthorization.serializationDomain.utf8.count
        wrongVersion.replaceSubrange(versionOffset..<(versionOffset + 4), with: Data([0, 0, 0, 1]))
        assertThrows(.invalidAuthorizationBlob) { try DiffOracleUpdateAuthorization(canonicalData: wrongVersion) }
        assertThrows(.invalidAuthorizationBlob) { try DiffOracleUpdateAuthorization(canonicalData: blob.dropLast()) }
        assertThrows(.invalidAuthorizationBlob) {
            try DiffOracleUpdateAuthorization(canonicalData: blob + Data([0]))
        }

        let unknownChange = independentAuthorizationBlob(
            authorityID: authorizer.authorityID,
            revocationGeneration: update.authorityState.revocationGeneration,
            evidence: update.evidence,
            signature: signature,
            firstChangeTag: 0xFF
        )
        assertThrows(.invalidAuthorizationBlob) {
            try DiffOracleUpdateAuthorization(canonicalData: unknownChange)
        }

        var shortSignature = Data(blob.dropLast())
        let signatureLengthOffset = shortSignature.count - 63 - 8
        shortSignature.replaceSubrange(
            signatureLengthOffset..<(signatureLengthOffset + 8),
            with: bigEndianData(UInt64(63))
        )
        assertThrows(.invalidAuthorizationBlob) {
            try DiffOracleUpdateAuthorization(canonicalData: shortSignature)
        }
    }

    func testSignatureUsesIndependentRFC8032Vector() throws {
        let privateKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: data(hex: "9d61b19deffd5a60ba844af492ec2cc4" + "4449c5697b326919703bac031cae7f60")
        )
        let expectedPublicKey = try data(
            hex: "d75a980182b10ab7d54bfed3c964073a" + "0ee172f3daa62325af021a68f707511a"
        )
        let expectedSignature = try data(
            hex: "e5564300c360ac729086e2cc806e828a"
                + "84877f1eb8e5d974d873e06522490155"
                + "5fb8821590a33bacc61e39701cf9b46b"
                + "d25bf5f0595bbe24655141438e7a100b"
        )
        XCTAssertTrue(privateKey.publicKey.rawRepresentation == expectedPublicKey, "public-key vector mismatch")
        XCTAssertTrue(privateKey.publicKey.isValidSignature(expectedSignature, for: Data()))
        var tamperedSignature = expectedSignature
        tamperedSignature[0] ^= 1
        XCTAssertFalse(privateKey.publicKey.isValidSignature(tamperedSignature, for: Data()))
    }

    func testPrivateAndPublicAuthorizationKeysOwnNoCopyBacking() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let privateBacking = MutableDataBacking(privateKey.rawRepresentation)
        let issuer = try DiffOracleUpdateAuthorizationIssuer(privateKeyRawRepresentation: privateBacking.data)
        let expectedPublicKey = issuer.publicKeyRawRepresentation
        privateBacking.overwrite(with: 0)

        assertEqualWithoutValues(issuer.publicKeyRawRepresentation, expectedPublicKey)

        let publicBacking = MutableDataBacking(expectedPublicKey)
        let authorizer = try DiffOracleUpdateAuthorizer(publicKeyRawRepresentation: publicBacking.data)
        let expectedAuthorityID = authorizer.authorityID
        publicBacking.overwrite(with: 0)

        assertEqualWithoutValues(authorizer.authorityID, expectedAuthorityID)
        let update = try makeUpdateScenario(issuer: issuer, authorizer: authorizer)
        XCTAssertNoThrow(try accept(update))
    }

    func testAuthorizationBindsRoleManifestRevisionDigestExpiryTrustedTimeAndNonce() throws {
        let update = try makeUpdateScenario()
        XCTAssertNoThrow(try accept(update))

        let wrongKey = Curve25519.Signing.PrivateKey()
        let wrongAuthorizer = try DiffOracleUpdateAuthorizer(
            publicKeyRawRepresentation: wrongKey.publicKey.rawRepresentation
        )
        let wrongRole = try makeUpdateScenario(authorizer: wrongAuthorizer)
        assertUpdateNotAuthorized { try accept(wrongRole) }

        let wrongDigestState = copyAuthorityState(
            update.authorityState,
            currentManifestSHA256: try digest("wrong-current-manifest")
        )
        let wrongDigest = try makeUpdateScenario(authorityState: wrongDigestState)
        assertVerificationFailure(code: .invalidReceipt, collection: .manifest) {
            try accept(wrongDigest)
        }

        let wrongRevisionState = copyAuthorityState(
            update.authorityState,
            currentManifestRevision: update.baseline.manifest.revision + 1
        )
        let wrongRevision = try makeUpdateScenario(authorityState: wrongRevisionState)
        assertVerificationFailure(code: .invalidReceipt, collection: .manifest) {
            try accept(wrongRevision)
        }

        let validBeforeExpiry = try makeUpdateScenario(verificationTimeOffset: 99)
        XCTAssertNoThrow(try accept(validBeforeExpiry))
        let expired = try makeUpdateScenario(verificationTimeOffset: 100)
        assertUpdateNotAuthorized { try accept(expired) }

        let consumedState = copyAuthorityState(
            update.authorityState,
            consumedAuthorizationNonces: [update.evidence.authorizationNonce]
        )
        assertUpdateNotAuthorized {
            try update.issuer.issue(
                evidence: update.evidence,
                authorityState: consumedState,
                trustedTimeSource: TrustedTimeProbe(sourceID: consumedState.trustedTimeSourceID).source()
            )
        }

        let calls = update.timeProbe.calls
        assertEqualWithoutValues(
            calls,
            [
                TrustedTimeCall(
                    minimumUnixSeconds: update.authorityState.trustedTimeFloorUnixSeconds,
                    minimumCounter: update.authorityState.trustedTimeRollbackProtectionCounter,
                    predecessor: update.authorityState.trustedTimeIntegrityTag
                )
            ]
        )
    }

    func testRevocationAndPolicyGenerationsRejectOldAuthorization() throws {
        let update = try makeUpdateScenario()

        let revokedState = copyAuthorityState(
            update.authorityState,
            revocationGeneration: update.authorityState.revocationGeneration + 1
        )
        let revoked = try makeUpdateScenario(
            baseline: update.baseline,
            candidate: update.candidate,
            issuer: update.issuer,
            authorizer: update.authorizer,
            authorityState: revokedState,
            evidence: update.evidence
        )
        assertUpdateNotAuthorized { try accept(revoked, authorization: update.authorization) }

        let changedPolicyState = copyAuthorityState(
            update.authorityState,
            policyVersion: update.authorityState.policyVersion + 1
        )
        let changedPolicy = try makeUpdateScenario(
            baseline: update.baseline,
            candidate: update.candidate,
            issuer: update.issuer,
            authorizer: update.authorizer,
            authorityState: changedPolicyState,
            evidence: copyEvidence(update.evidence, policyVersion: changedPolicyState.policyVersion)
        )
        assertUpdateNotAuthorized { try accept(changedPolicy, authorization: update.authorization) }
    }

    func testConsumedNonceReplayIsRejectedAgainstBaselineValidState() throws {
        let update = try makeUpdateScenario()
        let consumedState = copyAuthorityState(
            update.authorityState,
            consumedAuthorizationNonces: [update.evidence.authorizationNonce]
        )
        let consumedSnapshot = try copyAuthoritySnapshot(update.authoritySnapshot, state: consumedState)
        let consumedStore = AuthorityStoreProbe(snapshot: consumedSnapshot)
        assertUpdateNotAuthorized {
            try accept(update, authorityStateStore: consumedStore.store())
        }
    }

    func testAuthorizationBindsBaselineReceiptIndependentlyOfAuthorityState() throws {
        let update = try makeUpdateScenario()
        let wrongBaselineEvidence = copyEvidence(
            update.evidence,
            baselineReceiptSHA256: try digest("wrong-but-well-formed-baseline-receipt")
        )
        let wrongBaselineAuthorization = try update.issuer.issue(
            evidence: wrongBaselineEvidence,
            authorityState: update.authorityState,
            trustedTimeSource: TrustedTimeProbe(sourceID: update.authorityState.trustedTimeSourceID).source()
        )
        assertUpdateNotAuthorized {
            try accept(update, authorization: wrongBaselineAuthorization)
        }
    }

    func testAcceptedStateAdvancesEverySecurityFloor() throws {
        let update = try makeUpdateScenario()
        let accepted = try accept(update)

        assertEqualWithoutValues(accepted.authorityState.currentManifestRevision, update.candidate.manifest.revision)
        assertEqualWithoutValues(accepted.authorityState.currentManifestSHA256, update.candidateReceipt.manifestSHA256)
        assertEqualWithoutValues(
            accepted.authorityState.trustedTimeFloorUnixSeconds,
            update.authorityState.trustedTimeFloorUnixSeconds + 1
        )
        assertEqualWithoutValues(
            accepted.authorityState.trustedTimeRollbackProtectionCounter,
            update.authorityState.trustedTimeRollbackProtectionCounter + 1
        )
        assertEqualWithoutValues(accepted.authorityState.trustedTimeIntegrityTag, try digest("trusted-time-next-integrity"))
        XCTAssertTrue(accepted.authorityState.consumedAuthorizationNonces.contains(update.evidence.authorizationNonce))
        assertEqualWithoutValues(update.timeProbe.calls.count, 1)
    }

    func testTrustedTimeFailuresStopBeforeCandidatePersistence() throws {
        let update = try makeUpdateScenario()
        let mismatchedConfiguredSource = try DiffOracleTrustedTimeSource(
            sourceID: digest("different-source"),
            readAuthenticatedTime: { _, _, _ in throw DiffOracleManifestError.invalidTrustedTime }
        )
        assertThrows(.invalidTrustedTime) {
            try accept(update, trustedTimeSource: mismatchedConfiguredSource)
        }
        assertEqualWithoutValues(update.store.events, [.load])

        let probes = [
            TrustedTimeProbe(
                sourceID: update.authorityState.trustedTimeSourceID,
                observationSourceID: try digest("different-observation-source")
            ),
            TrustedTimeProbe(
                sourceID: update.authorityState.trustedTimeSourceID,
                unixSecondsAdjustment: -1
            ),
            TrustedTimeProbe(
                sourceID: update.authorityState.trustedTimeSourceID,
                counterIncrement: 0
            ),
            TrustedTimeProbe(
                sourceID: update.authorityState.trustedTimeSourceID,
                predecessorIntegrityTag: try digest("wrong-predecessor")
            )
        ]
        for probe in probes {
            let store = AuthorityStoreProbe(snapshot: update.authoritySnapshot)
            assertThrows(.invalidTrustedTime) {
                try accept(update, authorityStateStore: store.store(), trustedTimeSource: probe.source())
            }
            assertEqualWithoutValues(store.events, [.load])
        }
    }

    func testAuthorizationRejectsCandidateReceiptAndApprovedChangeSubstitution() throws {
        let update = try makeUpdateScenario()
        let wrongReceiptEvidence = copyEvidence(
            update.evidence,
            candidateReceiptSHA256: try digest("substituted-candidate-receipt")
        )
        let wrongReceipt = try makeUpdateScenario(evidence: wrongReceiptEvidence)
        assertUpdateNotAuthorized { try accept(wrongReceipt) }

        let wrongChangesEvidence = copyEvidence(update.evidence, approvedChanges: [.manifest])
        let wrongChanges = try makeUpdateScenario(evidence: wrongChangesEvidence)
        assertUpdateNotAuthorized { try accept(wrongChanges) }
    }

    func testReplayIsRejectedAndConcurrentCASAcceptsAtMostOneUpdate() async throws {
        let update = try makeUpdateScenario()
        _ = try accept(update)
        assertVerificationFailure(code: .invalidManifest, collection: .update) { try accept(update) }

        let concurrent = try makeUpdateScenario()
        concurrent.store.loadBarrier = BlockingCallBarrier(requiredCalls: 2)
        let results = LockedArray<Result<DiffOracleAcceptedUpdate, Error>>()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        results.append(.success(try accept(concurrent)))
                    } catch {
                        results.append(.failure(error))
                    }
                }
            }
        }

        assertEqualWithoutValues(results.values.filter(\.isSuccess).count, 1)
        let failures = results.values.compactMap { result -> DiffOracleManifestError? in
            guard case .failure(let error) = result else { return nil }
            return error as? DiffOracleManifestError
        }
        assertEqualWithoutValues(failures, [.invalidAuthorityState])
        assertEqualWithoutValues(concurrent.store.compareAndSwapAttemptCount, 2)
        assertEqualWithoutValues(concurrent.store.committedTransitionCount, 1)
    }

    func testDurableCandidatePrecedesAuthorityCASAndBindsCanonicalContent() throws {
        let update = try makeUpdateScenario()
        let accepted = try accept(update)

        assertEqualWithoutValues(update.store.events, [.load, .persistCandidate, .compareAndSwap])
        assertEqualWithoutValues(update.store.persistedManifestData, try update.candidate.manifest.canonicalData())
        assertEqualWithoutValues(update.store.persistedReceiptData, try accepted.receipt.canonicalData())
        assertEqualWithoutValues(
            try sha256(try XCTUnwrap(update.store.persistedManifestData)),
            accepted.receipt.manifestSHA256
        )
        assertEqualWithoutValues(
            try sha256(try XCTUnwrap(update.store.persistedReceiptData)),
            try XCTUnwrap(update.store.persistedReceiptContentSHA256)
        )
        let persistedCandidate = try XCTUnwrap(update.store.persistedCandidate)
        let transitionedCandidate = try XCTUnwrap(update.store.transitionedCandidate)
        assertEqualWithoutValues(persistedCandidate, transitionedCandidate)
        assertEqualWithoutValues(persistedCandidate.manifestRevision, update.candidate.manifest.revision)
        assertEqualWithoutValues(persistedCandidate.manifestSHA256, accepted.receipt.manifestSHA256)
        assertEqualWithoutValues(persistedCandidate.receiptSHA256, accepted.receipt.receiptSHA256)
        assertEqualWithoutValues(
            persistedCandidate.receiptContentSHA256,
            try XCTUnwrap(update.store.persistedReceiptContentSHA256)
        )
        XCTAssertFalse(persistedCandidate.durabilityProofSHA256.bytes.allSatisfy { $0 == 0 })
    }

    func testDurableCandidateRejectsEveryReceiptAndManifestIdentitySubstitution() throws {
        let update = try makeUpdateScenario()
        let expected = DurableCandidateValues(
            manifestRevision: update.candidate.manifest.revision,
            manifestSHA256: update.candidateReceipt.manifestSHA256,
            receiptSHA256: update.candidateReceipt.receiptSHA256,
            receiptContentSHA256: try sha256(update.candidateReceipt.canonicalData())
        )
        let substitutions = [
            try DiffOracleDurableCandidate(
                manifestRevision: expected.manifestRevision + 1,
                manifestSHA256: expected.manifestSHA256,
                receiptSHA256: expected.receiptSHA256,
                receiptContentSHA256: expected.receiptContentSHA256,
                durabilityProofSHA256: digest("proof")
            ),
            try DiffOracleDurableCandidate(
                manifestRevision: expected.manifestRevision,
                manifestSHA256: digest("wrong-manifest"),
                receiptSHA256: expected.receiptSHA256,
                receiptContentSHA256: expected.receiptContentSHA256,
                durabilityProofSHA256: digest("proof")
            ),
            try DiffOracleDurableCandidate(
                manifestRevision: expected.manifestRevision,
                manifestSHA256: expected.manifestSHA256,
                receiptSHA256: digest("wrong-receipt"),
                receiptContentSHA256: expected.receiptContentSHA256,
                durabilityProofSHA256: digest("proof")
            ),
            try DiffOracleDurableCandidate(
                manifestRevision: expected.manifestRevision,
                manifestSHA256: expected.manifestSHA256,
                receiptSHA256: expected.receiptSHA256,
                receiptContentSHA256: digest("wrong-receipt-content"),
                durabilityProofSHA256: digest("proof")
            )
        ]
        for substitution in substitutions {
            let store = AuthorityStoreProbe(snapshot: update.authoritySnapshot)
            store.forcedDurableCandidate = substitution
            assertThrows(.invalidAuthorityState) {
                try accept(update, authorityStateStore: store.store())
            }
            XCTAssertFalse(store.events.contains(.compareAndSwap))
        }
    }

    func testIndeterminateAndMalformedAuthorityTransitionsReconcileFailClosed() throws {
        let reconciledUpdate = try makeUpdateScenario()
        reconciledUpdate.store.transitionMode = .indeterminateCommitted
        XCTAssertNoThrow(try accept(reconciledUpdate))
        assertEqualWithoutValues(reconciledUpdate.store.events.suffix(2), [.compareAndSwap, .reconcile])

        let indeterminateUpdate = try makeUpdateScenario()
        indeterminateUpdate.store.transitionMode = .indeterminateNotCommitted
        assertThrows(.indeterminateAuthorityTransition) { try accept(indeterminateUpdate) }

        let malformedCommitUpdate = try makeUpdateScenario()
        malformedCommitUpdate.store.transitionMode = .malformedCommitted
        assertThrows(.indeterminateAuthorityTransition) { try accept(malformedCommitUpdate) }
        assertEqualWithoutValues(malformedCommitUpdate.store.events.suffix(2), [.compareAndSwap, .reconcile])

        let invalidReconciliationUpdate = try makeUpdateScenario()
        invalidReconciliationUpdate.store.transitionMode = .indeterminateInvalidReconciliation
        assertThrows(.indeterminateAuthorityTransition) { try accept(invalidReconciliationUpdate) }
        assertEqualWithoutValues(invalidReconciliationUpdate.store.events.suffix(2), [.compareAndSwap, .reconcile])
    }

    func testStaleCandidateIsRejectedBeforeTrustedCallbacks() throws {
        let update = try makeUpdateScenario(candidateManifestRevision: 1)

        assertVerificationFailure(code: .staleRecord, collection: .update) {
            try accept(update)
        }

        assertEqualWithoutValues(update.store.events, [], "stale metadata must not cross trusted storage boundary")
        assertEqualWithoutValues(update.timeProbe.calls, [], "stale metadata must not invoke trusted clock")
    }

    func testRollbackCounterExhaustionFailsBeforeCandidatePersistence() throws {
        let update = try makeUpdateScenario()
        let exhaustedSnapshot = try copyAuthoritySnapshot(
            update.authoritySnapshot,
            rollbackProtectionCounter: UInt64.max
        )
        let store = AuthorityStoreProbe(snapshot: exhaustedSnapshot)

        assertThrows(.invalidAuthorityState) {
            try accept(update, authorityStateStore: store.store())
        }
        assertEqualWithoutValues(store.events, [.load])
        XCTAssertTrue(store.persistedManifestData == nil)
        XCTAssertTrue(store.persistedReceiptData == nil)
    }

    func testRevisionFloorsPersistTombstonesAndRejectDeleteReaddRollback() throws {
        let baseline = try makeOracle(
            corpusSpecs: [
                CorpusSpec(label: "alpha", revision: 1, bytes: Data("alpha corpus".utf8)),
                CorpusSpec(label: "beta", revision: 4, bytes: Data("beta corpus".utf8))
            ],
            fixtureRevision: 1
        )
        let deletion = try makeOracle(
            manifestRevision: 2,
            corpusSpecs: [CorpusSpec(label: "alpha", revision: 1, bytes: Data("alpha corpus".utf8))],
            fixtureRevision: 2
        )
        let deletionScenario = try makeUpdateScenario(
            baseline: baseline,
            candidate: deletion,
            approvedChanges: [
                .manifest,
                .corpus(try corpusID(label: "beta")),
                .fixture(try DiffOracleIdentifier(fixtureIDValue))
            ]
        )
        let acceptedDeletion = try accept(deletionScenario)
        let tombstone = try XCTUnwrap(
            acceptedDeletion.authorityState.revisionFloors.first {
                $0.record == .corpus(try! corpusID(label: "beta"))
            }
        )
        assertEqualWithoutValues(tombstone.revision, 4)
        XCTAssertTrue(tombstone.isTombstone)

        let readded = try makeOracle(
            manifestRevision: 3,
            corpusSpecs: [
                CorpusSpec(label: "alpha", revision: 1, bytes: Data("alpha corpus".utf8)),
                CorpusSpec(label: "beta", revision: 4, bytes: Data("beta corpus".utf8))
            ],
            fixtureRevision: 3
        )
        let readdScenario = try makeUpdateScenario(
            baseline: deletion,
            candidate: readded,
            authorityState: acceptedDeletion.authorityState,
            authoritySnapshot: acceptedDeletion.authorityStateSnapshot,
            approvedChanges: [
                .manifest,
                .corpus(try corpusID(label: "beta")),
                .fixture(try DiffOracleIdentifier(fixtureIDValue))
            ]
        )
        assertVerificationFailure(code: .staleRecord, collection: .update) {
            try accept(readdScenario)
        }

        let readdedAboveFloor = try makeOracle(
            manifestRevision: 3,
            corpusSpecs: [
                CorpusSpec(label: "alpha", revision: 1, bytes: Data("alpha corpus".utf8)),
                CorpusSpec(label: "beta", revision: 5, bytes: Data("beta corpus v5".utf8))
            ],
            fixtureRevision: 3
        )
        let acceptedReadd = try accept(
            makeUpdateScenario(
                baseline: deletion,
                candidate: readdedAboveFloor,
                authorityState: acceptedDeletion.authorityState,
                authoritySnapshot: acceptedDeletion.authorityStateSnapshot,
                approvedChanges: [
                    .manifest,
                    .corpus(try corpusID(label: "beta")),
                    .fixture(try DiffOracleIdentifier(fixtureIDValue))
                ]
            )
        )
        let restored = try XCTUnwrap(
            acceptedReadd.authorityState.revisionFloors.first {
                $0.record == .corpus(try! corpusID(label: "beta"))
            }
        )
        assertEqualWithoutValues(restored.revision, 5)
        XCTAssertFalse(restored.isTombstone)
    }

    func testFixtureTombstoneSurvivesUnrelatedUpdate() throws {
        let baseline = try makeOracle(fixtureIDs: ["fixture-alpha", "fixture-zeta"])
        let deletion = try makeOracle(
            manifestRevision: 2,
            corpusSpecs: [CorpusSpec(label: "alpha", revision: 2, bytes: Data("alpha v2".utf8))],
            fixtureRevision: 2,
            fixtureIDs: ["fixture-alpha"]
        )
        let deletedFixtureID = try DiffOracleIdentifier("fixture-zeta")
        let deletionScenario = try makeUpdateScenario(
            baseline: baseline,
            candidate: deletion,
            approvedChanges: [
                .manifest,
                .corpus(try corpusID(label: "alpha")),
                .fixture(try DiffOracleIdentifier("fixture-alpha")),
                .fixture(deletedFixtureID)
            ]
        )
        let acceptedDeletion = try accept(deletionScenario)

        let unrelated = try makeOracle(
            manifestRevision: 3,
            corpusSpecs: [CorpusSpec(label: "alpha", revision: 3, bytes: Data("alpha v3".utf8))],
            fixtureRevision: 3,
            fixtureIDs: ["fixture-alpha"]
        )
        let acceptedUnrelated = try accept(
            makeUpdateScenario(
                baseline: deletion,
                candidate: unrelated,
                authorityState: acceptedDeletion.authorityState,
                authoritySnapshot: acceptedDeletion.authorityStateSnapshot,
                approvedChanges: [
                    .manifest,
                    .corpus(try corpusID(label: "alpha")),
                    .fixture(try DiffOracleIdentifier("fixture-alpha"))
                ]
            )
        )
        let tombstone = try XCTUnwrap(
            acceptedUnrelated.authorityState.revisionFloors.first { $0.record == .fixture(deletedFixtureID) }
        )
        assertEqualWithoutValues(tombstone.revision, 1)
        XCTAssertTrue(tombstone.isTombstone)

        let readded = try makeOracle(
            manifestRevision: 4,
            corpusSpecs: [CorpusSpec(label: "alpha", revision: 4, bytes: Data("alpha v4".utf8))],
            fixtureRevision: 4,
            fixtureIDs: ["fixture-alpha", "fixture-zeta"]
        )
        let acceptedReadd = try accept(
            makeUpdateScenario(
                baseline: unrelated,
                candidate: readded,
                authorityState: acceptedUnrelated.authorityState,
                authoritySnapshot: acceptedUnrelated.authorityStateSnapshot,
                approvedChanges: [
                    .manifest,
                    .corpus(try corpusID(label: "alpha")),
                    .fixture(try DiffOracleIdentifier("fixture-alpha")),
                    .fixture(deletedFixtureID)
                ]
            )
        )
        let restored = try XCTUnwrap(
            acceptedReadd.authorityState.revisionFloors.first { $0.record == .fixture(deletedFixtureID) }
        )
        assertEqualWithoutValues(restored.revision, 4)
        XCTAssertFalse(restored.isTombstone)
    }

    func testCountByteRelationCanonicalAndWorkLimitsFailClosed() throws {
        let oracle = try makeOracle(
            corpusSpecs: [
                CorpusSpec(label: "alpha", revision: 1, bytes: Data("alpha corpus".utf8)),
                CorpusSpec(label: "beta", revision: 1, bytes: Data("beta corpus".utf8))
            ]
        )

        assertInvalidManifest(oracle.manifest, limits: try makeLimits(maximumCorpusRecords: 1))
        assertThrows(.inputTooLarge) {
            try verify(oracle, limits: makeLimits(maximumRecordBytes: 8))
        }
        assertThrows(.inputTooLarge) {
            try verify(
                oracle,
                limits: makeLimits(maximumRecordBytes: 32, maximumTotalObservedBytes: 32)
            )
        }
        assertThrows(.canonicalOutputTooLarge) {
            try oracle.manifest.canonicalData(
                limits: makeLimits(maximumCanonicalBytes: 64, maximumAuthorizationBytes: 64)
            )
        }
        assertThrows(.workLimitExceeded) {
            try oracle.manifest.canonicalData(
                limits: makeLimits(maximumWorkUnits: 11, maximumCodecCallbackWorkUnits: 11)
            )
        }
    }

    func testSecurityLimitBoundariesAreIndependent() throws {
        let twoFixtures = try makeOracle(fixtureIDs: ["fixture-alpha", "fixture-zeta"])
        XCTAssertNoThrow(
            try twoFixtures.manifest.canonicalData(limits: makeLimits(maximumFixtureRecords: 2))
        )
        assertInvalidManifest(twoFixtures.manifest, limits: try makeLimits(maximumFixtureRecords: 1))

        let boundaryIdentifierOracle = try makeOracle(fixtureIDs: [String(repeating: "i", count: 256)])
        XCTAssertNoThrow(
            try boundaryIdentifierOracle.manifest.canonicalData(
                limits: makeLimits(maximumIdentifierUTF8Bytes: 256)
            )
        )
        let longIdentifier = String(repeating: "i", count: 257)
        let longIdentifierOracle = try makeOracle(fixtureIDs: [longIdentifier])
        assertThrows(.inputTooLarge) {
            try longIdentifierOracle.manifest.canonicalData(limits: makeLimits(maximumIdentifierUTF8Bytes: 256))
        }

        let update = try makeUpdateScenario()
        let authorizationData = try update.authorization.canonicalData()
        XCTAssertNoThrow(
            try update.authorization.canonicalData(
                limits: makeLimits(maximumAuthorizationBytes: authorizationData.count)
            )
        )
        assertThrows(.canonicalOutputTooLarge) {
            try update.authorization.canonicalData(
                limits: makeLimits(maximumCanonicalBytes: 512, maximumAuthorizationBytes: 128)
            )
        }
        assertThrows(.canonicalOutputTooLarge) {
            try update.authorization.canonicalData(
                limits: makeLimits(maximumAuthorizationBytes: authorizationData.count - 1)
            )
        }

        let oneNonceState = copyAuthorityState(
            update.authorityState,
            consumedAuthorizationNonces: [try digest("nonce-a")]
        )
        XCTAssertNoThrow(
            try oneNonceState.canonicalData(limits: makeLimits(maximumConsumedAuthorizationNonces: 1))
        )
        let twoNoncesState = copyAuthorityState(
            update.authorityState,
            consumedAuthorizationNonces: [try digest("nonce-a"), try digest("nonce-b")].sorted()
        )
        assertInvalidAuthorityState(
            twoNoncesState,
            limits: try makeLimits(maximumConsumedAuthorizationNonces: 1)
        )

        XCTAssertNoThrow(
            try update.authorityState.canonicalData(
                limits: makeLimits(maximumRevisionFloorRecords: update.authorityState.revisionFloors.count)
            )
        )
        assertInvalidAuthorityState(
            update.authorityState,
            limits: try makeLimits(maximumRevisionFloorRecords: 1)
        )

        let longValidityEvidence = copyEvidence(
            update.evidence,
            expiresAtUnixSeconds: update.evidence.issuedAtUnixSeconds + 101
        )
        let longValidityBlob = independentAuthorizationBlob(
            authorityID: update.authorizer.authorityID,
            revocationGeneration: update.authorityState.revocationGeneration,
            evidence: longValidityEvidence,
            signature: Data(repeating: 1, count: 64)
        )
        assertThrows(.invalidAuthorizationBlob) {
            try DiffOracleUpdateAuthorization(
                canonicalData: longValidityBlob,
                limits: makeLimits(maximumAuthorizationValiditySeconds: 100)
            )
        }

        let boundaryValidityEvidence = copyEvidence(
            update.evidence,
            expiresAtUnixSeconds: update.evidence.issuedAtUnixSeconds + 100
        )
        XCTAssertNoThrow(
            try DiffOracleUpdateAuthorization(
                canonicalData: independentAuthorizationBlob(
                    authorityID: update.authorizer.authorityID,
                    revocationGeneration: update.authorityState.revocationGeneration,
                    evidence: boundaryValidityEvidence,
                    signature: Data(repeating: 1, count: 64)
                ),
                limits: makeLimits(maximumAuthorizationValiditySeconds: 100)
            )
        )

        XCTAssertNoThrow(
            try update.candidate.manifest.canonicalData(
                limits: makeLimits(maximumCodecCallbackWorkUnits: 11)
            )
        )
        let callbackLimit = try makeLimits(maximumCodecCallbackWorkUnits: 10)
        assertInvalidManifest(update.candidate.manifest, limits: callbackLimit)
    }

    func testAuthorityStateCanonicalVectorBindsEverySecurityField() throws {
        let update = try makeUpdateScenario()
        let nonce = try digest("state-vector-nonce")
        let corpusFloor = DiffOracleRevisionFloor(
            record: .corpus(update.baseline.manifest.corpus[0].id),
            revision: 9,
            isTombstone: true
        )
        let fixtureFloor = DiffOracleRevisionFloor(
            record: .fixture(update.baseline.manifest.fixtures[0].id),
            revision: 7,
            isTombstone: false
        )
        let state = copyAuthorityState(
            update.authorityState,
            consumedAuthorizationNonces: [nonce],
            revisionFloors: [corpusFloor, fixtureFloor]
        )
        let canonical = try state.canonicalData()

        assertEqualWithoutValues(canonical, independentAuthorityStateData(state))
        assertEqualWithoutValues(try sha256(canonical).hex, "bd3eb74d0392ef143671511bf904634c49f83b95f4888ef065fd39218b43b87d")

        let mutations = [
            copyAuthorityState(state, revocationGeneration: state.revocationGeneration + 1),
            copyAuthorityState(state, policyVersion: state.policyVersion + 1),
            copyAuthorityState(state, currentManifestRevision: state.currentManifestRevision + 1),
            copyAuthorityState(state, currentManifestSHA256: try digest("other-manifest")),
            copyAuthorityState(state, trustedTimeSourceID: try digest("other-time-source")),
            copyAuthorityState(state, trustedTimeFloorUnixSeconds: state.trustedTimeFloorUnixSeconds + 1),
            copyAuthorityState(
                state,
                trustedTimeRollbackProtectionCounter: state.trustedTimeRollbackProtectionCounter + 1
            ),
            copyAuthorityState(state, trustedTimeIntegrityTag: try digest("other-time-integrity")),
            copyAuthorityState(state, consumedAuthorizationNonces: [try digest("other-nonce")]),
            copyAuthorityState(
                state,
                revisionFloors: [
                    DiffOracleRevisionFloor(
                        record: corpusFloor.record,
                        revision: corpusFloor.revision + 1,
                        isTombstone: corpusFloor.isTombstone
                    ),
                    fixtureFloor
                ]
            ),
            copyAuthorityState(
                state,
                revisionFloors: [
                    DiffOracleRevisionFloor(
                        record: corpusFloor.record,
                        revision: corpusFloor.revision,
                        isTombstone: false
                    ),
                    fixtureFloor
                ]
            )
        ]
        for mutation in mutations {
            assertNotEqualWithoutValues(try mutation.canonicalData(), canonical, "authority-state field omitted")
        }
    }

    func testAuthorizationParserRejectsOversizedCountWithoutPreallocation() throws {
        var writer = TestCanonicalWriter()
        writer.append(DiffOracleUpdateAuthorization.serializationDomain)
        writer.append(DiffOracleUpdateAuthorization.currentBlobVersion)
        writer.append(raw: Data(repeating: 1, count: 32))
        writer.append(UInt64(1))
        writer.append("review")
        writer.append(raw: Data(repeating: 2, count: 32))
        writer.append(raw: Data(repeating: 3, count: 32))
        writer.append(UInt64(1))
        writer.append(raw: Data(repeating: 4, count: 32))
        writer.append(UInt64(10))
        writer.append(UInt64(20))
        writer.append(raw: Data(repeating: 5, count: 32))
        writer.append(raw: Data(repeating: 6, count: 32))
        writer.append(UInt64.max)

        assertThrows(.invalidAuthorizationBlob) {
            try DiffOracleUpdateAuthorization(canonicalData: writer.data)
        }
    }

    func testCancellationAndResourceErrorsArePreserved() async throws {
        let oracle = try makeOracle()
        let cancelledValidator = try DiffOracleCanonicalCodecValidator(
            version: standardCodecMetadata.configurationVersion,
            maximumInvocationWorkUnits: standardCodecMetadata.configurationWorkUnits,
            canonicalize: { _, _ in throw CancellationError() }
        )
        assertThrows(.cancelled) {
            try DiffOracleManifestVerifier.verify(
                manifest: oracle.manifest,
                sourceObservation: oracle.sourceObservation,
                corpusRecords: oracle.corpusRecords,
                fixtureRecords: oracle.fixtureRecords,
                codecValidators: DiffOracleCanonicalCodecValidators(
                    configuration: cancelledValidator,
                    result: oracle.validators.result,
                    derivationTranscript: oracle.validators.derivationTranscript
                )
            )
        }

        let exhaustedValidator = try DiffOracleCanonicalCodecValidator(
            version: 1,
            maximumInvocationWorkUnits: 1,
            canonicalize: { data, budget in
                try budget.consume(2)
                return data
            }
        )
        let exhaustedOracle = try makeOracle(
            codecMetadata: CodecMetadata(
                configurationVersion: 1,
                resultVersion: 1,
                transcriptVersion: 1,
                configurationWorkUnits: 1,
                resultWorkUnits: 1,
                transcriptWorkUnits: 1
            ),
            validators: DiffOracleCanonicalCodecValidators(
                configuration: exhaustedValidator,
                result: exhaustedValidator,
                derivationTranscript: exhaustedValidator
            )
        )
        assertThrows(.workLimitExceeded) { try verify(exhaustedOracle) }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return Result { try oracle.manifest.canonicalData() }
        }
        let result = await task.value
        assertFailure(result, equals: .cancelled)
    }

    func testEveryCodecRolePreservesFailureAndResourceSemantics() throws {
        let oracle = try makeOracle()
        for role in CodecRole.allCases {
            let version = role.version(in: standardCodecMetadata)
            let workUnits = role.workUnits(in: standardCodecMetadata)
            let failures: [(DiffOracleManifestError, DiffOracleCanonicalCodecValidator)] = [
                (
                    .invalidCanonicalEncoding,
                    try DiffOracleCanonicalCodecValidator(
                        version: version,
                        maximumInvocationWorkUnits: workUnits,
                        canonicalize: { data, _ in data + Data([0]) }
                    )
                ),
                (
                    .invalidCanonicalEncoding,
                    try DiffOracleCanonicalCodecValidator(
                        version: version,
                        maximumInvocationWorkUnits: workUnits,
                        canonicalize: { _, _ in throw TestCodecError.rejected }
                    )
                ),
                (
                    .cancelled,
                    try DiffOracleCanonicalCodecValidator(
                        version: version,
                        maximumInvocationWorkUnits: workUnits,
                        canonicalize: { _, _ in throw CancellationError() }
                    )
                ),
                (
                    .workLimitExceeded,
                    try DiffOracleCanonicalCodecValidator(
                        version: version,
                        maximumInvocationWorkUnits: workUnits,
                        canonicalize: { data, budget in
                            try budget.consume(workUnits + 1)
                            return data
                        }
                    )
                )
            ]
            for (expected, validator) in failures {
                assertThrows(expected) {
                    try verify(oracle, validators: replacing(role, in: oracle.validators, with: validator))
                }
            }

            let oversized = try DiffOracleCanonicalCodecValidator(
                version: version,
                maximumInvocationWorkUnits: workUnits,
                canonicalize: { _, budget in Data(repeating: 1, count: budget.maximumOutputBytes + 1) }
            )
            assertThrows(.inputTooLarge) {
                try verify(
                    oracle,
                    validators: replacing(role, in: oracle.validators, with: oversized),
                    limits: makeLimits(maximumRecordBytes: 32)
                )
            }

            let wrongVersion = try DiffOracleCanonicalCodecValidator(
                version: version + 1,
                maximumInvocationWorkUnits: workUnits,
                canonicalize: { data, _ in data }
            )
            assertThrows(.invalidCanonicalEncoding) {
                try verify(oracle, validators: replacing(role, in: oracle.validators, with: wrongVersion))
            }
        }
    }

    func testEveryCodecRoleObservesCancellationAfterCallbackReturn() async throws {
        let oracle = try makeOracle()
        for role in CodecRole.allCases {
            let validator = try DiffOracleCanonicalCodecValidator(
                version: role.version(in: standardCodecMetadata),
                maximumInvocationWorkUnits: role.workUnits(in: standardCodecMetadata),
                canonicalize: { data, _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return data
                }
            )
            let validators = replacing(role, in: oracle.validators, with: validator)
            let roleOracle = try makeOracle(validators: validators)
            let task = Task { Result { try verify(roleOracle) } }
            assertFailure(await task.value, equals: .cancelled)
        }
    }

    func testUpdateWorkBudgetIncludesReceiptSerialization() throws {
        let update = try makeUpdateScenario()
        assertThrows(.workLimitExceeded) {
            try accept(
                update,
                limits: makeLimits(maximumWorkUnits: 12_250, maximumCodecCallbackWorkUnits: 11)
            )
        }
        XCTAssertFalse(update.store.events.contains(.persistCandidate))
    }

    func testCancellationAfterCommittedAuthorityTransitionReturnsAcceptedState() async throws {
        let update = try makeUpdateScenario()
        update.store.cancelDuringCompareAndSwap = true
        let task = Task { Result { try accept(update) } }
        let result = await task.value

        switch result {
        case .success(let accepted):
            assertEqualWithoutValues(accepted.authorityState.currentManifestRevision, update.candidate.manifest.revision)
            XCTAssertTrue(accepted.authorityState.consumedAuthorizationNonces.contains(update.evidence.authorizationNonce))
        case .failure:
            XCTFail("committed transition did not return accepted state")
        }
        assertEqualWithoutValues(update.store.committedTransitionCount, 1)
    }

    func testTrustedCallbackCancellationIsNormalized() throws {
        let update = try makeUpdateScenario()
        update.store.loadError = CancellationError()
        assertThrows(.cancelled) { try accept(update) }

        let persistCancelled = try makeUpdateScenario()
        persistCancelled.store.persistError = CancellationError()
        assertThrows(.cancelled) { try accept(persistCancelled) }

        let timeProbe = TrustedTimeProbe(sourceID: update.authorityState.trustedTimeSourceID)
        timeProbe.error = CancellationError()
        let source = try timeProbe.source()
        assertThrows(.cancelled) {
            try update.issuer.issue(
                evidence: update.evidence,
                authorityState: update.authorityState,
                trustedTimeSource: source
            )
        }
    }

    func testDiagnosticsAndReflectionRedactIdentifiersPathsDigestsBytesAndKeys() throws {
        let oracle = try makeOracle()
        let path = try DiffOracleIdentifier("Testing/Data/private/customer.txt")
        let pathSecret = Data(0..<UInt8(DiffOracleSHA256.byteCount))
        let hmacKey = try makePathHMACKey(secret: pathSecret)
        let pathKey = try DiffOraclePathKey(testingDataRelativePath: path, key: hmacKey)
        let update = try makeUpdateScenario()
        let diagnostic = DiffOracleRedactedDiagnostic(
            code: .changedRecord,
            collection: .fixture,
            canonicalIndex: 7
        )
        let secretTokens = [
            oracle.manifest.corpus[0].bytesSHA256.hex,
            oracle.manifest.fixtures[0].id.rawValue,
            path.rawValue,
            update.evidence.reviewID.rawValue,
            update.evidence.authorizationNonce.hex,
            oracle.corpusRecords[0].bytes.base64EncodedString(),
            oracle.fixtureRecords[0].leftBytes.base64EncodedString(),
            oracle.fixtureRecords[0].rightBytes.base64EncodedString(),
            oracle.fixtureRecords[0].canonicalConfiguration.base64EncodedString(),
            oracle.fixtureRecords[0].canonicalExpectedResult.base64EncodedString(),
            oracle.fixtureRecords[0].canonicalDerivationTranscript.base64EncodedString(),
            oracle.goldenProvenance.generatorVersion.rawValue,
            Data(pathKey.bytes).base64EncodedString(),
            pathSecret.base64EncodedString()
        ]
        let renderedValues = [
            String(describing: oracle.manifest.corpus[0].bytesSHA256),
            String(reflecting: oracle.manifest.corpus[0].id),
            String(reflecting: oracle.manifest.fixtures[0].id),
            String(describing: oracle.manifest),
            String(reflecting: oracle.manifest),
            String(describing: oracle.corpusRecords[0]),
            String(reflecting: oracle.fixtureRecords[0]),
            String(reflecting: oracle.goldenProvenance),
            String(reflecting: oracle.macSourceProvenance),
            String(reflecting: pathKey),
            String(reflecting: hmacKey),
            String(reflecting: update.evidence),
            String(reflecting: update.authorization),
            String(reflecting: update.issuer),
            String(reflecting: update.authorizer),
            DiffOracleManifestError.verificationFailed(diagnostic).localizedDescription,
            DiffOracleManifestError.invalidPathKey.localizedDescription,
            DiffOracleManifestError.invalidAuthorizationBlob.localizedDescription
        ]
        for (renderedIndex, rendered) in renderedValues.enumerated() {
            for (tokenIndex, secret) in secretTokens.enumerated() {
                XCTAssertFalse(
                    rendered.contains(secret),
                    "redaction failure: rendering \(renderedIndex), token \(tokenIndex)"
                )
            }
        }
        assertEqualWithoutValues(
            diagnostic.description,
            "Diff oracle verification failed: changedRecord, collection: fixture, canonical index: 7."
        )
        XCTAssertFalse(diagnostic.description.contains(path.rawValue))
    }
}

private let fixtureIDValue = "fixture-main"

private struct CodecMetadata: Sendable {
    let configurationVersion: UInt32
    let resultVersion: UInt32
    let transcriptVersion: UInt32
    let configurationWorkUnits: UInt64
    let resultWorkUnits: UInt64
    let transcriptWorkUnits: UInt64
}

private struct CodecCall: Equatable, Sendable {
    let role: String
    let data: Data
}

private enum CodecRole: CaseIterable, Sendable {
    case configuration
    case result
    case transcript

    func version(in metadata: CodecMetadata) -> UInt32 {
        switch self {
        case .configuration: metadata.configurationVersion
        case .result: metadata.resultVersion
        case .transcript: metadata.transcriptVersion
        }
    }

    func workUnits(in metadata: CodecMetadata) -> UInt64 {
        switch self {
        case .configuration: metadata.configurationWorkUnits
        case .result: metadata.resultWorkUnits
        case .transcript: metadata.transcriptWorkUnits
        }
    }
}

private enum TestCodecError: Error {
    case rejected
}

private let standardCodecMetadata = CodecMetadata(
    configurationVersion: 11,
    resultVersion: 22,
    transcriptVersion: 33,
    configurationWorkUnits: 5,
    resultWorkUnits: 7,
    transcriptWorkUnits: 11
)

private struct CorpusSpec: Sendable {
    let label: String
    let revision: UInt64
    let bytes: Data
}

private struct OracleTestValue: Sendable {
    let manifest: DiffOracleManifest
    let sourceObservation: DiffOracleSourceObservation
    let corpusRecords: [DiffOracleCorpusRecord]
    let fixtureRecords: [DiffOracleFixtureRecord]
    let validators: DiffOracleCanonicalCodecValidators
    let goldenProvenance: DiffOracleGoldenProvenance
    let macSourceProvenance: DiffOracleMacSourceProvenance
}

private struct UpdateScenario: Sendable {
    let baseline: OracleTestValue
    let baselineReceipt: DiffOracleVerificationReceipt
    let candidate: OracleTestValue
    let candidateReceipt: DiffOracleVerificationReceipt
    let evidence: DiffOracleReviewedUpdateEvidence
    let authorization: DiffOracleUpdateAuthorization
    let issuer: DiffOracleUpdateAuthorizationIssuer
    let authorizer: DiffOracleUpdateAuthorizer
    let authorityState: DiffOracleUpdateAuthorityState
    let authoritySnapshot: DiffOracleUpdateAuthorityStateSnapshot
    let store: AuthorityStoreProbe
    let timeProbe: TrustedTimeProbe
    let trustedTimeSource: DiffOracleTrustedTimeSource
}

private struct DurableCandidateValues {
    let manifestRevision: UInt64
    let manifestSHA256: DiffOracleSHA256
    let receiptSHA256: DiffOracleSHA256
    let receiptContentSHA256: DiffOracleSHA256
}

private func makeOracle(
    manifestRevision: UInt64 = 1,
    corpusSpecs: [CorpusSpec] = [CorpusSpec(label: "alpha", revision: 1, bytes: Data("corpus".utf8))],
    fixtureRevision: UInt64 = 1,
    canonicalConfiguration: Data = Data("config-v1".utf8),
    canonicalExpectedResult: Data = Data("result-v1".utf8),
    canonicalDerivationTranscript: Data = Data("transcript-v1".utf8),
    codecMetadata: CodecMetadata = standardCodecMetadata,
    fixtureIDs fixtureIDValues: [String] = [fixtureIDValue],
    validators suppliedValidators: DiffOracleCanonicalCodecValidators? = nil,
    goldenProvenance: DiffOracleGoldenProvenance = makeGoldenProvenance(),
    macSourceProvenance: DiffOracleMacSourceProvenance = makeMacProvenance()
) throws -> OracleTestValue {
    let fixtureIDs = try fixtureIDValues.map(DiffOracleIdentifier.init).sorted()
    var corpusPairs: [(DiffOracleCorpusManifestEntry, DiffOracleCorpusRecord)] = []
    for spec in corpusSpecs {
        let bytesSHA256 = try sha256(spec.bytes)
        let id = try corpusID(label: spec.label)
        let origin = DiffOracleCorpusOrigin.diffWrapper(
            testName: try DiffOracleIdentifier("DiffWrapper.\(spec.label)"),
            caseID: bytesSHA256
        )
        corpusPairs.append(
            (
                DiffOracleCorpusManifestEntry(
                    id: id,
                    revision: spec.revision,
                    origin: origin,
                    bytesSHA256: bytesSHA256,
                    disposition: .required(fixtureIDs: fixtureIDs)
                ),
                try DiffOracleCorpusRecord(
                    id: id,
                    revision: spec.revision,
                    origin: origin,
                    bytes: spec.bytes
                )
            )
        )
    }
    corpusPairs.sort { $0.0.id < $1.0.id }
    let corpusEntries = corpusPairs.map(\.0)
    let corpusRecords = corpusPairs.map(\.1)
    let corpusIDs = corpusEntries.map(\.id)
    let leftBytes = Data("left input".utf8)
    let rightBytes = Data("right input".utf8)
    let hashes = FixtureHashes(
        left: try sha256(leftBytes),
        right: try sha256(rightBytes),
        configuration: try sha256(canonicalConfiguration),
        result: try sha256(canonicalExpectedResult),
        transcript: try sha256(canonicalDerivationTranscript)
    )
    var fixtureEntries: [DiffOracleFixtureManifestEntry] = []
    var fixtureRecords: [DiffOracleFixtureRecord] = []
    for fixtureID in fixtureIDs {
        let binding = try derivationBinding(
            fixtureID: fixtureID,
            corpusEntries: corpusEntries,
            hashes: hashes,
            codecMetadata: codecMetadata,
            goldenProvenance: goldenProvenance
        )
        fixtureEntries.append(
            DiffOracleFixtureManifestEntry(
                id: fixtureID,
                revision: fixtureRevision,
                corpusRecordIDs: corpusIDs,
                leftBytesSHA256: hashes.left,
                rightBytesSHA256: hashes.right,
                configurationSHA256: hashes.configuration,
                expectedResultSHA256: hashes.result,
                derivationTranscriptSHA256: hashes.transcript,
                derivationBindingSHA256: binding,
                goldenProvenance: goldenProvenance
            )
        )
        fixtureRecords.append(
            try DiffOracleFixtureRecord(
                id: fixtureID,
                revision: fixtureRevision,
                corpusRecordIDs: corpusIDs,
                leftBytes: leftBytes,
                rightBytes: rightBytes,
                canonicalConfiguration: canonicalConfiguration,
                canonicalExpectedResult: canonicalExpectedResult,
                canonicalDerivationTranscript: canonicalDerivationTranscript,
                goldenProvenance: goldenProvenance
            )
        )
    }
    let manifest = DiffOracleManifest(
        revision: manifestRevision,
        configurationCodecVersion: codecMetadata.configurationVersion,
        resultCodecVersion: codecMetadata.resultVersion,
        derivationTranscriptCodecVersion: codecMetadata.transcriptVersion,
        configurationCodecMaximumWorkUnits: codecMetadata.configurationWorkUnits,
        resultCodecMaximumWorkUnits: codecMetadata.resultWorkUnits,
        derivationTranscriptCodecMaximumWorkUnits: codecMetadata.transcriptWorkUnits,
        macSourceProvenance: macSourceProvenance,
        corpus: corpusEntries,
        fixtures: fixtureEntries
    )
    let selectedValidators: DiffOracleCanonicalCodecValidators
    if let suppliedValidators {
        selectedValidators = suppliedValidators
    } else {
        selectedValidators = try validators(metadata: codecMetadata)
    }
    return OracleTestValue(
        manifest: manifest,
        sourceObservation: DiffOracleSourceObservation(
            goldenProvenance: goldenProvenance,
            macSourceProvenance: macSourceProvenance
        ),
        corpusRecords: corpusRecords,
        fixtureRecords: fixtureRecords,
        validators: selectedValidators,
        goldenProvenance: goldenProvenance,
        macSourceProvenance: macSourceProvenance
    )
}

private func makeUpdateScenario(
    baseline suppliedBaseline: OracleTestValue? = nil,
    candidate suppliedCandidate: OracleTestValue? = nil,
    candidateManifestRevision: UInt64 = 2,
    issuer suppliedIssuer: DiffOracleUpdateAuthorizationIssuer? = nil,
    authorizer suppliedAuthorizer: DiffOracleUpdateAuthorizer? = nil,
    authorityState suppliedState: DiffOracleUpdateAuthorityState? = nil,
    authoritySnapshot suppliedSnapshot: DiffOracleUpdateAuthorityStateSnapshot? = nil,
    evidence suppliedEvidence: DiffOracleReviewedUpdateEvidence? = nil,
    approvedChanges suppliedChanges: [DiffOracleChangeReference]? = nil,
    verificationTimeOffset: UInt64 = 0
) throws -> UpdateScenario {
    let baseline = try suppliedBaseline ?? makeOracle()
    let candidate =
        try suppliedCandidate
        ?? makeOracle(
            manifestRevision: candidateManifestRevision,
            corpusSpecs: [CorpusSpec(label: "alpha", revision: 2, bytes: Data("changed corpus".utf8))],
            fixtureRevision: 2
        )
    let baselineReceipt = try verify(baseline)
    let candidateReceipt = try verify(candidate)
    let privateKey = Curve25519.Signing.PrivateKey()
    let issuer =
        try suppliedIssuer
        ?? DiffOracleUpdateAuthorizationIssuer(privateKeyRawRepresentation: privateKey.rawRepresentation)
    let authorizer =
        try suppliedAuthorizer
        ?? DiffOracleUpdateAuthorizer(publicKeyRawRepresentation: issuer.publicKeyRawRepresentation)
    let sourceID = try digest("trusted-time-source")
    let defaultState = DiffOracleUpdateAuthorityState(
        revocationGeneration: 1,
        policyVersion: 7,
        currentManifestRevision: baseline.manifest.revision,
        currentManifestSHA256: baselineReceipt.manifestSHA256,
        trustedTimeSourceID: sourceID,
        trustedTimeFloorUnixSeconds: 1_000,
        trustedTimeRollbackProtectionCounter: 10,
        trustedTimeIntegrityTag: try digest("trusted-time-integrity"),
        consumedAuthorizationNonces: [],
        revisionFloors: revisionFloors(for: baseline.manifest)
    )
    let authorityState = suppliedState ?? defaultState
    let defaultSnapshot = try DiffOracleUpdateAuthorityStateSnapshot(
        state: authorityState,
        rollbackProtectionCounter: 20,
        protectionKeyID: try digest("authority-state-protection-key"),
        predecessorIntegrityTag: try digest("authority-state-predecessor"),
        integrityTag: try digest("authority-state-integrity")
    )
    let authoritySnapshot = suppliedSnapshot ?? defaultSnapshot
    let timeProbe = TrustedTimeProbe(
        sourceID: authorityState.trustedTimeSourceID,
        unixSecondsAdjustment: Int64(verificationTimeOffset)
    )
    let trustedTimeSource = try timeProbe.source()
    let changes =
        suppliedChanges
        ?? [
            .manifest,
            .corpus(candidate.manifest.corpus[0].id),
            .fixture(candidate.manifest.fixtures[0].id)
        ]
    let defaultEvidence = DiffOracleReviewedUpdateEvidence(
        reviewID: try DiffOracleIdentifier("review-\u{00e9}"),
        reviewerIdentitySHA256: try digest("reviewer-identity"),
        reviewArtifactSHA256: try digest("review-artifact"),
        policyVersion: authorityState.policyVersion,
        authorizationNonce: try digest("authorization-nonce-\(candidate.manifest.revision)"),
        issuedAtUnixSeconds: authorityState.trustedTimeFloorUnixSeconds,
        expiresAtUnixSeconds: authorityState.trustedTimeFloorUnixSeconds + 101,
        baselineReceiptSHA256: baselineReceipt.receiptSHA256,
        candidateReceiptSHA256: candidateReceipt.receiptSHA256,
        approvedChanges: changes
    )
    let evidence = suppliedEvidence ?? defaultEvidence
    let issuanceTimeProbe = TrustedTimeProbe(sourceID: authorityState.trustedTimeSourceID)
    let authorization = try issuer.issue(
        evidence: evidence,
        authorityState: authorityState,
        trustedTimeSource: issuanceTimeProbe.source()
    )
    let store = AuthorityStoreProbe(snapshot: authoritySnapshot)
    return UpdateScenario(
        baseline: baseline,
        baselineReceipt: baselineReceipt,
        candidate: candidate,
        candidateReceipt: candidateReceipt,
        evidence: evidence,
        authorization: authorization,
        issuer: issuer,
        authorizer: authorizer,
        authorityState: authorityState,
        authoritySnapshot: authoritySnapshot,
        store: store,
        timeProbe: timeProbe,
        trustedTimeSource: trustedTimeSource
    )
}

private func accept(
    _ update: UpdateScenario,
    authorization: DiffOracleUpdateAuthorization? = nil,
    authorityStateStore: DiffOracleUpdateAuthorityStateStore? = nil,
    trustedTimeSource: DiffOracleTrustedTimeSource? = nil,
    limits: DiffOracleVerificationLimits = .default
) throws -> DiffOracleAcceptedUpdate {
    try DiffOracleManifestVerifier.verifyUpdate(
        from: update.baseline.manifest,
        baselineReceipt: update.baselineReceipt,
        to: update.candidate.manifest,
        sourceObservation: update.candidate.sourceObservation,
        corpusRecords: update.candidate.corpusRecords,
        fixtureRecords: update.candidate.fixtureRecords,
        codecValidators: update.candidate.validators,
        authorization: authorization ?? update.authorization,
        authorizer: update.authorizer,
        authorityStateStore: authorityStateStore ?? update.store.store(),
        trustedTimeSource: trustedTimeSource ?? update.trustedTimeSource,
        limits: limits
    )
}

private func verify(
    _ oracle: OracleTestValue,
    validators: DiffOracleCanonicalCodecValidators? = nil,
    limits: DiffOracleVerificationLimits = .default
) throws -> DiffOracleVerificationReceipt {
    try DiffOracleManifestVerifier.verify(
        manifest: oracle.manifest,
        sourceObservation: oracle.sourceObservation,
        corpusRecords: oracle.corpusRecords,
        fixtureRecords: oracle.fixtureRecords,
        codecValidators: validators ?? oracle.validators,
        limits: limits
    )
}

private func replacing(
    _ role: CodecRole,
    in validators: DiffOracleCanonicalCodecValidators,
    with validator: DiffOracleCanonicalCodecValidator
) -> DiffOracleCanonicalCodecValidators {
    switch role {
    case .configuration:
        DiffOracleCanonicalCodecValidators(
            configuration: validator,
            result: validators.result,
            derivationTranscript: validators.derivationTranscript
        )
    case .result:
        DiffOracleCanonicalCodecValidators(
            configuration: validators.configuration,
            result: validator,
            derivationTranscript: validators.derivationTranscript
        )
    case .transcript:
        DiffOracleCanonicalCodecValidators(
            configuration: validators.configuration,
            result: validators.result,
            derivationTranscript: validator
        )
    }
}

private func validators(
    metadata: CodecMetadata = standardCodecMetadata,
    probe: LockedArray<CodecCall>? = nil
) throws -> DiffOracleCanonicalCodecValidators {
    func validator(_ role: String, version: UInt32, workUnits: UInt64) throws -> DiffOracleCanonicalCodecValidator {
        try DiffOracleCanonicalCodecValidator(
            version: version,
            maximumInvocationWorkUnits: workUnits,
            canonicalize: { data, budget in
                probe?.append(CodecCall(role: role, data: data))
                try budget.consume()
                guard data.count <= budget.maximumOutputBytes else {
                    throw DiffOracleManifestError.inputTooLarge
                }
                return data
            }
        )
    }
    return try DiffOracleCanonicalCodecValidators(
        configuration: validator(
            "configuration",
            version: metadata.configurationVersion,
            workUnits: metadata.configurationWorkUnits
        ),
        result: validator("result", version: metadata.resultVersion, workUnits: metadata.resultWorkUnits),
        derivationTranscript: validator(
            "transcript",
            version: metadata.transcriptVersion,
            workUnits: metadata.transcriptWorkUnits
        )
    )
}

private func makeGoldenProvenance(
    oracleExecutable: DiffOracleSHA256? = nil,
    generatorExecutable: DiffOracleSHA256? = nil,
    generatorSchema: DiffOracleSHA256? = nil,
    generatorConfiguration: DiffOracleSHA256? = nil
) -> DiffOracleGoldenProvenance {
    try! DiffOracleGoldenProvenance(
        winMergeCommit: DiffOracleGitObjectID(String(repeating: "1", count: 40)),
        windowsXDiffTree: DiffOracleGitObjectID(String(repeating: "2", count: 40)),
        topLevelLibXDiffCommit: DiffOracleGitObjectID(String(repeating: "3", count: 40)),
        topLevelLibXDiffTree: DiffOracleGitObjectID(String(repeating: "4", count: 40)),
        nestedLibXDiffCommit: DiffOracleGitObjectID(String(repeating: "5", count: 40)),
        nestedLibXDiffTree: DiffOracleGitObjectID(String(repeating: "6", count: 40)),
        oracleExecutableSHA256: oracleExecutable ?? digest("oracle-executable"),
        generatorVersion: DiffOracleIdentifier("generator-v1"),
        generatorExecutableSHA256: generatorExecutable ?? digest("generator-executable"),
        generatorSchemaSHA256: generatorSchema ?? digest("generator-schema"),
        generatorConfigurationSHA256: generatorConfiguration ?? digest("generator-configuration"),
        architecture: DiffOracleIdentifier("x86_64"),
        buildConfiguration: DiffOracleIdentifier("Release")
    )
}

private func makeMacProvenance(
    patchedXDiff: DiffOracleSHA256? = nil,
    cBridge: DiffOracleSHA256? = nil,
    swiftDiff: DiffOracleSHA256? = nil,
    extractorExecutable: DiffOracleSHA256? = nil,
    extractorSchema: DiffOracleSHA256? = nil,
    extractorConfiguration: DiffOracleSHA256? = nil,
    sourceTree: DiffOracleSHA256? = nil,
    sourceTreeEntryCount: UInt64 = 41
) -> DiffOracleMacSourceProvenance {
    try! DiffOracleMacSourceProvenance(
        macMergeCommit: DiffOracleGitObjectID(String(repeating: "7", count: 40)),
        patchedXDiffContentManifestSHA256: patchedXDiff ?? digest("patched-xdiff-content"),
        cBridgeSourceSHA256: cBridge ?? digest("c-bridge-source"),
        swiftDiffSourceSHA256: swiftDiff ?? digest("swift-diff-source"),
        trustedExtractorVersion: DiffOracleIdentifier("extractor-v1"),
        trustedExtractorExecutableSHA256: extractorExecutable ?? digest("extractor-executable"),
        trustedExtractorSchemaSHA256: extractorSchema ?? digest("extractor-schema"),
        trustedExtractorConfigurationSHA256: extractorConfiguration ?? digest("extractor-configuration"),
        sourceTreeInventorySHA256: sourceTree ?? digest("source-tree-inventory"),
        sourceTreeInventoryEntryCount: sourceTreeEntryCount
    )
}

private func makePathHMACKey(
    secret: Data = randomBytes(count: DiffOracleSHA256.byteCount)
) throws -> DiffOraclePathHMACKey {
    let keyIdentifier = try sha256(secret)
    let attestation = DiffOraclePathKeyStrengthAttestation(
        policyVersion: 1,
        attestedEntropyBits: DiffOraclePathKeyStrengthAttestation.minimumEntropyBits,
        keyIdentifierSHA256: keyIdentifier,
        evidenceSHA256: try digest("approved-system-random-generator")
    )
    return try DiffOraclePathHMACKey(
        secretKey: secret,
        strengthAttestation: attestation,
        verifyStrengthAttestation: { $0 == attestation }
    )
}

private func randomBytes(count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
}

private func data(hex: String) throws -> Data {
    guard hex.utf8.count.isMultiple(of: 2) else {
        throw DiffOracleManifestError.invalidSHA256
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(hex.utf8.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else {
            throw DiffOracleManifestError.invalidSHA256
        }
        bytes.append(byte)
        index = next
    }
    return Data(bytes)
}

private func digest(_ value: String) throws -> DiffOracleSHA256 {
    try sha256(Data(value.utf8))
}

private func sha256(_ data: Data) throws -> DiffOracleSHA256 {
    try DiffOracleSHA256(bytes: Array(SHA256.hash(data: data)))
}

private func zeroDigest() throws -> DiffOracleSHA256 {
    try DiffOracleSHA256(bytes: Array(repeating: 0, count: DiffOracleSHA256.byteCount))
}

private func corpusID(label: String) throws -> DiffOracleCorpusID {
    try DiffOracleCorpusID(sourceIdentitySHA256: digest("corpus-source-\(label)"))
}

private struct FixtureHashes {
    let left: DiffOracleSHA256
    let right: DiffOracleSHA256
    let configuration: DiffOracleSHA256
    let result: DiffOracleSHA256
    let transcript: DiffOracleSHA256
}

private func fixtureHashes(_ record: DiffOracleFixtureRecord) throws -> FixtureHashes {
    try FixtureHashes(
        left: sha256(record.leftBytes),
        right: sha256(record.rightBytes),
        configuration: sha256(record.canonicalConfiguration),
        result: sha256(record.canonicalExpectedResult),
        transcript: sha256(record.canonicalDerivationTranscript)
    )
}

private func derivationBinding(
    fixtureID: DiffOracleIdentifier,
    corpusEntries: [DiffOracleCorpusManifestEntry],
    hashes: FixtureHashes,
    codecMetadata: CodecMetadata,
    goldenProvenance: DiffOracleGoldenProvenance
) throws -> DiffOracleSHA256 {
    var writer = TestCanonicalWriter()
    writer.append("com.macmerge.diff-oracle-fixture-derivation.v3")
    writer.append(fixtureID.rawValue)
    writer.append(codecMetadata.configurationVersion)
    writer.append(codecMetadata.resultVersion)
    writer.append(codecMetadata.transcriptVersion)
    writer.append(codecMetadata.configurationWorkUnits)
    writer.append(codecMetadata.resultWorkUnits)
    writer.append(codecMetadata.transcriptWorkUnits)
    writer.append(goldenProvenance)
    writer.append(UInt64(corpusEntries.count))
    for entry in corpusEntries {
        writer.append(raw: Data(entry.id.bytes))
        writer.append(entry.revision)
        switch entry.origin {
        case .diffWrapper(let testName, let caseID):
            writer.append(UInt8(0))
            writer.append(testName.rawValue)
            writer.append(raw: Data(caseID.bytes))
        case .testingData(let pathKey):
            writer.append(UInt8(1))
            writer.append(raw: Data(pathKey.bytes))
        }
        writer.append(raw: Data(entry.bytesSHA256.bytes))
    }
    writer.append(raw: Data(hashes.left.bytes))
    writer.append(raw: Data(hashes.right.bytes))
    writer.append(raw: Data(hashes.configuration.bytes))
    writer.append(raw: Data(hashes.result.bytes))
    writer.append(raw: Data(hashes.transcript.bytes))
    return try sha256(writer.data)
}

private struct TestCanonicalWriter {
    private(set) var data = Data()

    mutating func append(_ value: UInt8) {
        data.append(value)
    }

    mutating func append(_ value: UInt32) {
        appendInteger(value, byteCount: 4)
    }

    mutating func append(_ value: UInt64) {
        appendInteger(value, byteCount: 8)
    }

    mutating func append(_ value: String) {
        let bytes = Data(value.utf8)
        append(UInt64(bytes.count))
        data.append(bytes)
    }

    mutating func append(_ value: Data) {
        append(UInt64(value.count))
        data.append(value)
    }

    mutating func append(_ value: DiffOracleChangeReference) {
        switch value {
        case .manifest:
            append(UInt8(0))
        case .corpus(let id):
            append(UInt8(1))
            append(raw: Data(id.bytes))
        case .fixture(let id):
            append(UInt8(2))
            append(id.rawValue)
        }
    }

    mutating func append(raw bytes: Data) {
        data.append(bytes)
    }

    mutating func append(_ provenance: DiffOracleGoldenProvenance) {
        append(provenance.winMergeCommit.rawValue)
        append(provenance.windowsXDiffTree.rawValue)
        append(provenance.topLevelLibXDiffCommit.rawValue)
        append(provenance.topLevelLibXDiffTree.rawValue)
        append(provenance.nestedLibXDiffCommit.rawValue)
        append(provenance.nestedLibXDiffTree.rawValue)
        append(raw: Data(provenance.oracleExecutableSHA256.bytes))
        append(provenance.generatorVersion.rawValue)
        append(raw: Data(provenance.generatorExecutableSHA256.bytes))
        append(raw: Data(provenance.generatorSchemaSHA256.bytes))
        append(raw: Data(provenance.generatorConfigurationSHA256.bytes))
        append(provenance.architecture.rawValue)
        append(provenance.buildConfiguration.rawValue)
    }

    private mutating func appendInteger<T: FixedWidthInteger>(_ value: T, byteCount: Int) {
        for shift in (0..<byteCount).reversed() {
            data.append(UInt8(truncatingIfNeeded: value >> T(shift * 8)))
        }
    }
}

private func replacingFixtureRecord(
    in oracle: OracleTestValue,
    canonicalDerivationTranscript: Data
) throws -> OracleTestValue {
    let original = oracle.fixtureRecords[0]
    let replacement = try DiffOracleFixtureRecord(
        id: original.id,
        revision: original.revision,
        corpusRecordIDs: original.corpusRecordIDs,
        leftBytes: original.leftBytes,
        rightBytes: original.rightBytes,
        canonicalConfiguration: original.canonicalConfiguration,
        canonicalExpectedResult: original.canonicalExpectedResult,
        canonicalDerivationTranscript: canonicalDerivationTranscript,
        goldenProvenance: original.goldenProvenance
    )
    return OracleTestValue(
        manifest: oracle.manifest,
        sourceObservation: oracle.sourceObservation,
        corpusRecords: oracle.corpusRecords,
        fixtureRecords: [replacement],
        validators: oracle.validators,
        goldenProvenance: oracle.goldenProvenance,
        macSourceProvenance: oracle.macSourceProvenance
    )
}

private func replacingCorpusRecord(in oracle: OracleTestValue, bytes: Data) throws -> OracleTestValue {
    let original = oracle.corpusRecords[0]
    let replacement = try DiffOracleCorpusRecord(
        id: original.id,
        revision: original.revision,
        origin: original.origin,
        bytes: bytes
    )
    return OracleTestValue(
        manifest: oracle.manifest,
        sourceObservation: oracle.sourceObservation,
        corpusRecords: [replacement] + oracle.corpusRecords.dropFirst(),
        fixtureRecords: oracle.fixtureRecords,
        validators: oracle.validators,
        goldenProvenance: oracle.goldenProvenance,
        macSourceProvenance: oracle.macSourceProvenance
    )
}

private func copyManifest(
    _ manifest: DiffOracleManifest,
    corpus: some Sequence<DiffOracleCorpusManifestEntry>,
    fixtures: [DiffOracleFixtureManifestEntry]? = nil
) -> DiffOracleManifest {
    DiffOracleManifest(
        schemaVersion: manifest.schemaVersion,
        revision: manifest.revision,
        configurationCodecVersion: manifest.configurationCodecVersion,
        resultCodecVersion: manifest.resultCodecVersion,
        derivationTranscriptCodecVersion: manifest.derivationTranscriptCodecVersion,
        configurationCodecMaximumWorkUnits: manifest.configurationCodecMaximumWorkUnits,
        resultCodecMaximumWorkUnits: manifest.resultCodecMaximumWorkUnits,
        derivationTranscriptCodecMaximumWorkUnits: manifest.derivationTranscriptCodecMaximumWorkUnits,
        macSourceProvenance: manifest.macSourceProvenance,
        corpus: Array(corpus),
        fixtures: fixtures ?? manifest.fixtures
    )
}

private func copyFixtureEntry(
    _ entry: DiffOracleFixtureManifestEntry,
    corpusRecordIDs: [DiffOracleCorpusID]? = nil,
    derivationBindingSHA256: DiffOracleSHA256? = nil,
    goldenProvenance: DiffOracleGoldenProvenance? = nil
) -> DiffOracleFixtureManifestEntry {
    DiffOracleFixtureManifestEntry(
        id: entry.id,
        revision: entry.revision,
        corpusRecordIDs: corpusRecordIDs ?? entry.corpusRecordIDs,
        leftBytesSHA256: entry.leftBytesSHA256,
        rightBytesSHA256: entry.rightBytesSHA256,
        configurationSHA256: entry.configurationSHA256,
        expectedResultSHA256: entry.expectedResultSHA256,
        derivationTranscriptSHA256: entry.derivationTranscriptSHA256,
        derivationBindingSHA256: derivationBindingSHA256 ?? entry.derivationBindingSHA256,
        goldenProvenance: goldenProvenance ?? entry.goldenProvenance
    )
}

private func copyManifest(
    _ manifest: DiffOracleManifest,
    fixtures: [DiffOracleFixtureManifestEntry]
) -> DiffOracleManifest {
    copyManifest(manifest, corpus: manifest.corpus, fixtures: fixtures)
}

private func revisionFloors(for manifest: DiffOracleManifest) -> [DiffOracleRevisionFloor] {
    let corpus = manifest.corpus.map {
        DiffOracleRevisionFloor(record: .corpus($0.id), revision: $0.revision, isTombstone: false)
    }
    let fixtures = manifest.fixtures.map {
        DiffOracleRevisionFloor(record: .fixture($0.id), revision: $0.revision, isTombstone: false)
    }
    return (corpus + fixtures).sorted { $0.record < $1.record }
}

private func copyAuthoritySnapshot(
    _ snapshot: DiffOracleUpdateAuthorityStateSnapshot,
    state: DiffOracleUpdateAuthorityState? = nil,
    rollbackProtectionCounter: UInt64? = nil,
    predecessorIntegrityTag: DiffOracleSHA256? = nil
) throws -> DiffOracleUpdateAuthorityStateSnapshot {
    try DiffOracleUpdateAuthorityStateSnapshot(
        state: state ?? snapshot.state,
        rollbackProtectionCounter: rollbackProtectionCounter ?? snapshot.rollbackProtectionCounter,
        protectionKeyID: snapshot.protectionKeyID,
        predecessorIntegrityTag: predecessorIntegrityTag ?? snapshot.predecessorIntegrityTag,
        integrityTag: snapshot.integrityTag
    )
}

private func bigEndianData<T: FixedWidthInteger>(_ value: T) -> Data {
    Data((0..<MemoryLayout<T>.size).reversed().map { UInt8(truncatingIfNeeded: value >> T($0 * 8)) })
}

private func independentAuthorizationBlob(
    authorityID: DiffOracleSHA256,
    revocationGeneration: UInt64,
    evidence: DiffOracleReviewedUpdateEvidence,
    signature: Data,
    firstChangeTag: UInt8? = nil
) -> Data {
    var writer = TestCanonicalWriter()
    writer.append(DiffOracleUpdateAuthorization.serializationDomain)
    writer.append(DiffOracleUpdateAuthorization.currentBlobVersion)
    writer.append(raw: Data(authorityID.bytes))
    writer.append(revocationGeneration)
    writer.append(evidence.reviewID.rawValue)
    writer.append(raw: Data(evidence.reviewerIdentitySHA256.bytes))
    writer.append(raw: Data(evidence.reviewArtifactSHA256.bytes))
    writer.append(evidence.policyVersion)
    writer.append(raw: Data(evidence.authorizationNonce.bytes))
    writer.append(evidence.issuedAtUnixSeconds)
    writer.append(evidence.expiresAtUnixSeconds)
    writer.append(raw: Data(evidence.baselineReceiptSHA256.bytes))
    writer.append(raw: Data(evidence.candidateReceiptSHA256.bytes))
    writer.append(UInt64(evidence.approvedChanges.count))
    for (index, change) in evidence.approvedChanges.enumerated() {
        if index == evidence.approvedChanges.startIndex, let firstChangeTag {
            writer.append(firstChangeTag)
        } else {
            writer.append(change)
        }
    }
    writer.append(signature)
    return writer.data
}

private func independentAuthorizationInput(
    authorityID: DiffOracleSHA256,
    revocationGeneration: UInt64,
    evidence: DiffOracleReviewedUpdateEvidence
) -> Data {
    var writer = TestCanonicalWriter()
    writer.append("com.macmerge.diff-oracle-reviewed-update.v3")
    writer.append(raw: Data(authorityID.bytes))
    writer.append(revocationGeneration)
    writer.append(evidence.reviewID.rawValue)
    writer.append(raw: Data(evidence.reviewerIdentitySHA256.bytes))
    writer.append(raw: Data(evidence.reviewArtifactSHA256.bytes))
    writer.append(evidence.policyVersion)
    writer.append(raw: Data(evidence.authorizationNonce.bytes))
    writer.append(evidence.issuedAtUnixSeconds)
    writer.append(evidence.expiresAtUnixSeconds)
    writer.append(raw: Data(evidence.baselineReceiptSHA256.bytes))
    writer.append(raw: Data(evidence.candidateReceiptSHA256.bytes))
    writer.append(UInt64(evidence.approvedChanges.count))
    for change in evidence.approvedChanges {
        writer.append(change)
    }
    return writer.data
}

private func independentAuthorityStateData(_ state: DiffOracleUpdateAuthorityState) -> Data {
    var writer = TestCanonicalWriter()
    writer.append(DiffOracleUpdateAuthorityState.serializationDomain)
    writer.append(state.revocationGeneration)
    writer.append(state.policyVersion)
    writer.append(state.currentManifestRevision)
    writer.append(raw: Data(state.currentManifestSHA256.bytes))
    writer.append(raw: Data(state.trustedTimeSourceID.bytes))
    writer.append(state.trustedTimeFloorUnixSeconds)
    writer.append(state.trustedTimeRollbackProtectionCounter)
    writer.append(raw: Data(state.trustedTimeIntegrityTag.bytes))
    writer.append(UInt64(state.consumedAuthorizationNonces.count))
    for nonce in state.consumedAuthorizationNonces {
        writer.append(raw: Data(nonce.bytes))
    }
    writer.append(UInt64(state.revisionFloors.count))
    for floor in state.revisionFloors {
        writer.append(floor.record)
        writer.append(floor.revision)
        writer.append(floor.isTombstone ? UInt8(1) : UInt8(0))
    }
    return writer.data
}

private func copyAuthorityState(
    _ state: DiffOracleUpdateAuthorityState,
    revocationGeneration: UInt64? = nil,
    policyVersion: UInt64? = nil,
    currentManifestRevision: UInt64? = nil,
    currentManifestSHA256: DiffOracleSHA256? = nil,
    trustedTimeSourceID: DiffOracleSHA256? = nil,
    trustedTimeFloorUnixSeconds: UInt64? = nil,
    trustedTimeRollbackProtectionCounter: UInt64? = nil,
    trustedTimeIntegrityTag: DiffOracleSHA256? = nil,
    consumedAuthorizationNonces: [DiffOracleSHA256]? = nil,
    revisionFloors: [DiffOracleRevisionFloor]? = nil
) -> DiffOracleUpdateAuthorityState {
    DiffOracleUpdateAuthorityState(
        revocationGeneration: revocationGeneration ?? state.revocationGeneration,
        policyVersion: policyVersion ?? state.policyVersion,
        currentManifestRevision: currentManifestRevision ?? state.currentManifestRevision,
        currentManifestSHA256: currentManifestSHA256 ?? state.currentManifestSHA256,
        trustedTimeSourceID: trustedTimeSourceID ?? state.trustedTimeSourceID,
        trustedTimeFloorUnixSeconds: trustedTimeFloorUnixSeconds ?? state.trustedTimeFloorUnixSeconds,
        trustedTimeRollbackProtectionCounter: trustedTimeRollbackProtectionCounter
            ?? state.trustedTimeRollbackProtectionCounter,
        trustedTimeIntegrityTag: trustedTimeIntegrityTag ?? state.trustedTimeIntegrityTag,
        consumedAuthorizationNonces: consumedAuthorizationNonces ?? state.consumedAuthorizationNonces,
        revisionFloors: revisionFloors ?? state.revisionFloors
    )
}

private func copyEvidence(
    _ evidence: DiffOracleReviewedUpdateEvidence,
    reviewID: DiffOracleIdentifier? = nil,
    reviewerIdentitySHA256: DiffOracleSHA256? = nil,
    reviewArtifactSHA256: DiffOracleSHA256? = nil,
    policyVersion: UInt64? = nil,
    authorizationNonce: DiffOracleSHA256? = nil,
    issuedAtUnixSeconds: UInt64? = nil,
    expiresAtUnixSeconds: UInt64? = nil,
    baselineReceiptSHA256: DiffOracleSHA256? = nil,
    candidateReceiptSHA256: DiffOracleSHA256? = nil,
    approvedChanges: [DiffOracleChangeReference]? = nil
) -> DiffOracleReviewedUpdateEvidence {
    DiffOracleReviewedUpdateEvidence(
        reviewID: reviewID ?? evidence.reviewID,
        reviewerIdentitySHA256: reviewerIdentitySHA256 ?? evidence.reviewerIdentitySHA256,
        reviewArtifactSHA256: reviewArtifactSHA256 ?? evidence.reviewArtifactSHA256,
        policyVersion: policyVersion ?? evidence.policyVersion,
        authorizationNonce: authorizationNonce ?? evidence.authorizationNonce,
        issuedAtUnixSeconds: issuedAtUnixSeconds ?? evidence.issuedAtUnixSeconds,
        expiresAtUnixSeconds: expiresAtUnixSeconds ?? evidence.expiresAtUnixSeconds,
        baselineReceiptSHA256: baselineReceiptSHA256 ?? evidence.baselineReceiptSHA256,
        candidateReceiptSHA256: candidateReceiptSHA256 ?? evidence.candidateReceiptSHA256,
        approvedChanges: approvedChanges ?? evidence.approvedChanges
    )
}

private func replacingLengthPrefixedValue(_ old: Data, with new: Data, in data: Data) throws -> Data {
    let oldRange = try XCTUnwrap(data.range(of: old))
    let lengthStart = data.index(oldRange.lowerBound, offsetBy: -8)
    var replacement = Data(data[..<lengthStart])
    var writer = TestCanonicalWriter()
    writer.append(UInt64(new.count))
    replacement.append(writer.data)
    replacement.append(new)
    replacement.append(data[oldRange.upperBound...])
    return replacement
}

private func makeLimits(
    maximumCorpusRecords: Int = 16,
    maximumFixtureRecords: Int = 16,
    maximumRecordBytes: Int = 256,
    maximumTotalObservedBytes: Int = 4_096,
    maximumCanonicalBytes: Int = 16_384,
    maximumIdentifierUTF8Bytes: Int = 256,
    maximumRelationEdges: Int = 256,
    maximumRelationBytes: Int = 4_096,
    maximumAuthorizationBytes: Int = 4_096,
    maximumConsumedAuthorizationNonces: Int = 256,
    maximumRevisionFloorRecords: Int = 256,
    maximumAuthorizationValiditySeconds: UInt64 = 1_000,
    maximumWorkUnits: UInt64 = 1_000_000,
    maximumCodecCallbackWorkUnits: UInt64 = 1_000,
    cancellationCheckInterval: Int = 1
) throws -> DiffOracleVerificationLimits {
    try DiffOracleVerificationLimits(
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
        cancellationCheckInterval: cancellationCheckInterval
    )
}

private func assertInvalidManifest(
    _ manifest: DiffOracleManifest,
    limits: DiffOracleVerificationLimits = .default,
    collection: DiffOracleRedactedDiagnostic.Collection = .manifest,
    canonicalIndex: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertVerificationFailure(
        code: .invalidManifest,
        collection: collection,
        canonicalIndex: canonicalIndex,
        file: file,
        line: line
    ) {
        try manifest.canonicalData(limits: limits)
    }
}

private func assertInvalidAuthorityState(
    _ state: DiffOracleUpdateAuthorityState,
    limits: DiffOracleVerificationLimits = .default,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertVerificationFailure(
        code: .invalidManifest,
        collection: .update,
        file: file,
        line: line
    ) {
        try state.canonicalData(limits: limits)
    }
}

private func assertThrows<T>(
    _ expected: DiffOracleManifestError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () throws -> T
) {
    XCTAssertThrowsError(try operation(), file: file, line: line) { error in
        guard let actual = error as? DiffOracleManifestError else {
            return XCTFail("unexpected error type", file: file, line: line)
        }
        switch (actual, expected) {
        case (
            .verificationFailed(let actualDiagnostic),
            .verificationFailed(let expectedDiagnostic)
        ):
            assertEqualWithoutValues(actualDiagnostic, expectedDiagnostic, file: file, line: line)
        default:
            assertEqualWithoutValues(actual, expected, file: file, line: line)
        }
    }
}

private func assertVerificationFailure<T>(
    code: DiffOracleDiagnosticCode,
    collection: DiffOracleRedactedDiagnostic.Collection,
    canonicalIndex: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () throws -> T
) {
    assertThrows(
        .verificationFailed(
            DiffOracleRedactedDiagnostic(code: code, collection: collection, canonicalIndex: canonicalIndex)
        ),
        file: file,
        line: line,
        operation
    )
}

private func assertUpdateNotAuthorized<T>(
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () throws -> T
) {
    assertVerificationFailure(code: .updateNotAuthorized, collection: .update, file: file, line: line, operation)
}

private func assertFailure<T>(
    _ result: Result<T, Error>,
    equals expected: DiffOracleManifestError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch result {
    case .success:
        XCTFail("expected failure", file: file, line: line)
    case .failure(let error):
        assertEqualWithoutValues(error as? DiffOracleManifestError, expected, file: file, line: line)
    }
}

extension Result {
    fileprivate var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private final class MutableDataBacking: @unchecked Sendable {
    private let storage: UnsafeMutableRawPointer
    private let count: Int
    let data: Data

    init(_ source: Data) {
        count = source.count
        storage = UnsafeMutableRawPointer.allocate(
            byteCount: source.count,
            alignment: MemoryLayout<UInt8>.alignment
        )
        source.copyBytes(to: storage.assumingMemoryBound(to: UInt8.self), count: source.count)
        data = Data(bytesNoCopy: storage, count: source.count, deallocator: .none)
    }

    deinit {
        storage.deallocate()
    }

    func overwrite(with byte: UInt8) {
        storage.initializeMemory(as: UInt8.self, repeating: byte, count: count)
    }
}

private final class LockedArray<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    var values: [Element] {
        lock.withLock { storage }
    }

    func append(_ value: Element) {
        lock.withLock { storage.append(value) }
    }
}

private final class BlockingCallBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private let requiredCalls: Int
    private var calls = 0

    init(requiredCalls: Int) {
        self.requiredCalls = requiredCalls
    }

    func arriveAndWait() {
        condition.lock()
        calls += 1
        if calls >= requiredCalls {
            condition.broadcast()
        } else {
            while calls < requiredCalls {
                condition.wait()
            }
        }
        condition.unlock()
    }
}

private struct TrustedTimeCall: Equatable, Sendable {
    let minimumUnixSeconds: UInt64
    let minimumCounter: UInt64
    let predecessor: DiffOracleSHA256
}

private final class TrustedTimeProbe: @unchecked Sendable {
    let sourceID: DiffOracleSHA256
    let observationSourceID: DiffOracleSHA256
    let unixSecondsAdjustment: Int64
    let counterIncrement: UInt64
    let predecessorIntegrityTag: DiffOracleSHA256?
    private let lock = NSLock()
    private var storedCalls: [TrustedTimeCall] = []
    private var storedError: (any Error)?

    var calls: [TrustedTimeCall] {
        lock.withLock { storedCalls }
    }

    var error: (any Error)? {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }

    init(
        sourceID: DiffOracleSHA256,
        observationSourceID: DiffOracleSHA256? = nil,
        unixSecondsAdjustment: Int64 = 0,
        counterIncrement: UInt64 = 1,
        predecessorIntegrityTag: DiffOracleSHA256? = nil
    ) {
        self.sourceID = sourceID
        self.observationSourceID = observationSourceID ?? sourceID
        self.unixSecondsAdjustment = unixSecondsAdjustment
        self.counterIncrement = counterIncrement
        self.predecessorIntegrityTag = predecessorIntegrityTag
    }

    func source() throws -> DiffOracleTrustedTimeSource {
        try DiffOracleTrustedTimeSource(sourceID: sourceID) { minimumUnixSeconds, minimumCounter, predecessor in
            let error = self.lock.withLock { () -> (any Error)? in
                self.storedCalls.append(
                    TrustedTimeCall(
                        minimumUnixSeconds: minimumUnixSeconds,
                        minimumCounter: minimumCounter,
                        predecessor: predecessor
                    )
                )
                return self.storedError
            }
            if let error { throw error }
            let unixSeconds: UInt64
            if self.unixSecondsAdjustment >= 0 {
                unixSeconds = minimumUnixSeconds + 1 + UInt64(self.unixSecondsAdjustment)
            } else {
                unixSeconds = minimumUnixSeconds - UInt64(-self.unixSecondsAdjustment)
            }
            return try DiffOracleTrustedTimeObservation(
                sourceID: self.observationSourceID,
                unixSeconds: unixSeconds,
                rollbackProtectionCounter: minimumCounter + self.counterIncrement,
                predecessorIntegrityTag: self.predecessorIntegrityTag ?? predecessor,
                integrityTag: digest("trusted-time-next-integrity")
            )
        }
    }
}

private enum StoreEvent: Equatable, Sendable {
    case load
    case persistCandidate
    case compareAndSwap
    case reconcile
}

private enum StoreTransitionMode: Sendable {
    case normal
    case indeterminateCommitted
    case indeterminateNotCommitted
    case malformedCommitted
    case indeterminateInvalidReconciliation
}

private final class AuthorityStoreProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: DiffOracleUpdateAuthorityStateSnapshot
    private var storedEvents: [StoreEvent] = []
    private var storedManifestData: Data?
    private var storedReceiptData: Data?
    private var storedReceiptContentSHA256: DiffOracleSHA256?
    private var storedPersistedCandidate: DiffOracleDurableCandidate?
    private var storedTransitionedCandidate: DiffOracleDurableCandidate?
    private var storedCompareAndSwapAttemptCount = 0
    private var storedCommittedTransitionCount = 0
    private var storedLoadError: (any Error)?
    private var storedPersistError: (any Error)?
    private var storedCancelDuringCompareAndSwap = false
    private var storedLoadBarrier: BlockingCallBarrier?
    private var storedTransitionMode: StoreTransitionMode = .normal
    private var storedForcedDurableCandidate: DiffOracleDurableCandidate?

    var events: [StoreEvent] { lock.withLock { storedEvents } }
    var persistedManifestData: Data? { lock.withLock { storedManifestData } }
    var persistedReceiptData: Data? { lock.withLock { storedReceiptData } }
    var persistedReceiptContentSHA256: DiffOracleSHA256? { lock.withLock { storedReceiptContentSHA256 } }
    var persistedCandidate: DiffOracleDurableCandidate? { lock.withLock { storedPersistedCandidate } }
    var transitionedCandidate: DiffOracleDurableCandidate? { lock.withLock { storedTransitionedCandidate } }
    var compareAndSwapAttemptCount: Int { lock.withLock { storedCompareAndSwapAttemptCount } }
    var committedTransitionCount: Int { lock.withLock { storedCommittedTransitionCount } }

    var loadError: (any Error)? {
        get { lock.withLock { storedLoadError } }
        set { lock.withLock { storedLoadError = newValue } }
    }

    var persistError: (any Error)? {
        get { lock.withLock { storedPersistError } }
        set { lock.withLock { storedPersistError = newValue } }
    }

    var cancelDuringCompareAndSwap: Bool {
        get { lock.withLock { storedCancelDuringCompareAndSwap } }
        set { lock.withLock { storedCancelDuringCompareAndSwap = newValue } }
    }

    var loadBarrier: BlockingCallBarrier? {
        get { lock.withLock { storedLoadBarrier } }
        set { lock.withLock { storedLoadBarrier = newValue } }
    }

    var transitionMode: StoreTransitionMode {
        get { lock.withLock { storedTransitionMode } }
        set { lock.withLock { storedTransitionMode = newValue } }
    }

    var forcedDurableCandidate: DiffOracleDurableCandidate? {
        get { lock.withLock { storedForcedDurableCandidate } }
        set { lock.withLock { storedForcedDurableCandidate = newValue } }
    }

    init(snapshot: DiffOracleUpdateAuthorityStateSnapshot) {
        self.snapshot = snapshot
    }

    func store() -> DiffOracleUpdateAuthorityStateStore {
        DiffOracleUpdateAuthorityStateStore(
            loadValidatedSnapshot: {
                try self.load()
            },
            persistContentAddressedCandidate: {
                revision,
                manifestSHA256,
                manifestData,
                receiptSHA256,
                receiptContentSHA256,
                receiptData in
                try self.persist(
                    revision: revision,
                    manifestSHA256: manifestSHA256,
                    manifestData: manifestData,
                    receiptSHA256: receiptSHA256,
                    receiptContentSHA256: receiptContentSHA256,
                    receiptData: receiptData
                )
            },
            compareAndSwapSnapshot: { expected, durableCandidate, replacement in
                self.compareAndSwap(expected: expected, durableCandidate: durableCandidate, replacement: replacement)
            },
            reconcileIndeterminateSnapshot: { expected, durableCandidate, replacement in
                self.reconcile(expected: expected, durableCandidate: durableCandidate, replacement: replacement)
            }
        )
    }

    private func load() throws -> DiffOracleUpdateAuthorityStateSnapshot {
        let loaded = try lock.withLock { () throws -> (DiffOracleUpdateAuthorityStateSnapshot, BlockingCallBarrier?) in
            storedEvents.append(.load)
            if let storedLoadError { throw storedLoadError }
            return (snapshot, storedLoadBarrier)
        }
        loaded.1?.arriveAndWait()
        return loaded.0
    }

    private func persist(
        revision: UInt64,
        manifestSHA256: DiffOracleSHA256,
        manifestData: Data,
        receiptSHA256: DiffOracleSHA256,
        receiptContentSHA256: DiffOracleSHA256,
        receiptData: Data
    ) throws -> DiffOracleDurableCandidate {
        try lock.withLock {
            storedEvents.append(.persistCandidate)
            if let storedPersistError { throw storedPersistError }
            guard try sha256(manifestData) == manifestSHA256,
                try sha256(receiptData) == receiptContentSHA256
            else {
                throw DiffOracleManifestError.invalidAuthorityState
            }
            storedManifestData = Data(manifestData)
            storedReceiptData = Data(receiptData)
            storedReceiptContentSHA256 = receiptContentSHA256
            if let storedForcedDurableCandidate {
                return storedForcedDurableCandidate
            }
            let candidate = try DiffOracleDurableCandidate(
                manifestRevision: revision,
                manifestSHA256: manifestSHA256,
                receiptSHA256: receiptSHA256,
                receiptContentSHA256: receiptContentSHA256,
                durabilityProofSHA256: digest("durable-readback-proof")
            )
            storedPersistedCandidate = candidate
            return candidate
        }
    }

    private func compareAndSwap(
        expected: DiffOracleUpdateAuthorityStateSnapshot,
        durableCandidate: DiffOracleDurableCandidate,
        replacement: DiffOracleUpdateAuthorityState
    ) -> DiffOracleUpdateAuthorityStateStore.TransitionOutcome {
        let result = lock.withLock { () -> DiffOracleUpdateAuthorityStateStore.TransitionOutcome in
            storedEvents.append(.compareAndSwap)
            storedCompareAndSwapAttemptCount += 1
            storedTransitionedCandidate = durableCandidate
            guard snapshot == expected else { return .notCommitted }
            guard
                let committed = try? DiffOracleUpdateAuthorityStateSnapshot(
                    state: replacement,
                    rollbackProtectionCounter: expected.rollbackProtectionCounter + 1,
                    protectionKeyID: expected.protectionKeyID,
                    predecessorIntegrityTag: expected.integrityTag,
                    integrityTag: digest("committed-authority-integrity")
                )
            else {
                return .indeterminate
            }
            switch storedTransitionMode {
            case .normal:
                snapshot = committed
                storedCommittedTransitionCount += 1
                return .committed(committed)
            case .indeterminateCommitted:
                snapshot = committed
                storedCommittedTransitionCount += 1
                return .indeterminate
            case .indeterminateNotCommitted, .indeterminateInvalidReconciliation:
                return .indeterminate
            case .malformedCommitted:
                let malformed = try? DiffOracleUpdateAuthorityStateSnapshot(
                    state: replacement,
                    rollbackProtectionCounter: expected.rollbackProtectionCounter + 2,
                    protectionKeyID: expected.protectionKeyID,
                    predecessorIntegrityTag: expected.integrityTag,
                    integrityTag: digest("malformed-authority-integrity")
                )
                return malformed.map(DiffOracleUpdateAuthorityStateStore.TransitionOutcome.committed)
                    ?? .indeterminate
            }
        }
        if cancelDuringCompareAndSwap {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return result
    }

    private func reconcile(
        expected: DiffOracleUpdateAuthorityStateSnapshot,
        durableCandidate _: DiffOracleDurableCandidate,
        replacement: DiffOracleUpdateAuthorityState
    ) -> DiffOracleUpdateAuthorityStateSnapshot? {
        lock.withLock {
            storedEvents.append(.reconcile)
            switch storedTransitionMode {
            case .indeterminateCommitted:
                return snapshot
            case .indeterminateInvalidReconciliation:
                return try? DiffOracleUpdateAuthorityStateSnapshot(
                    state: replacement,
                    rollbackProtectionCounter: expected.rollbackProtectionCounter + 2,
                    protectionKeyID: expected.protectionKeyID,
                    predecessorIntegrityTag: expected.integrityTag,
                    integrityTag: digest("invalid-reconciliation-integrity")
                )
            case .normal, .indeterminateNotCommitted, .malformedCommitted:
                return nil
            }
        }
    }
}
