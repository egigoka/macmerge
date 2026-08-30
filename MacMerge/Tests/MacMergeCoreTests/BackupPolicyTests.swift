import Foundation
import MacMergeCore
import XCTest

final class BackupPolicyTests: XCTestCase {
    func testPlanningLimitsAcceptMinimumAndHardMaximumAndRejectEveryAdjacentBoundary() throws {
        let minimums = try BackupPlanningLimits(
            maximumNameCandidates: 1,
            maximumSourceItemCount: 1,
            maximumExistingBackupCount: 0,
            maximumRetentionItemCount: 0,
            maximumPathUTF8Bytes: 1,
            maximumTotalPathUTF8Bytes: 1,
            maximumEstimatedWorkUnits: 1,
            maximumOutputBytes: 1,
            maximumPlanStepCount: 1
        )
        XCTAssertEqual(minimums.maximumNameCandidates, 1)
        XCTAssertEqual(minimums.maximumSourceItemCount, 1)
        XCTAssertEqual(minimums.maximumExistingBackupCount, 0)
        XCTAssertEqual(minimums.maximumRetentionItemCount, 0)
        XCTAssertEqual(minimums.maximumPathUTF8Bytes, 1)
        XCTAssertEqual(minimums.maximumTotalPathUTF8Bytes, 1)
        XCTAssertEqual(minimums.maximumEstimatedWorkUnits, 1)
        XCTAssertEqual(minimums.maximumOutputBytes, 1)
        XCTAssertEqual(minimums.maximumPlanStepCount, 1)

        let cases: [(String, () throws -> Void)] = [
            (
                "name candidates below minimum",
                {
                    _ = try BackupPlanningLimits(maximumNameCandidates: 0)
                }
            ),
            (
                "name candidates above hard maximum",
                {
                    _ = try BackupPlanningLimits(
                        maximumNameCandidates: BackupPlanningLimits.hardMaximumNameCandidates + 1
                    )
                }
            ),
            (
                "source items below minimum",
                {
                    _ = try BackupPlanningLimits(maximumSourceItemCount: 0)
                }
            ),
            (
                "source items above hard maximum",
                {
                    _ = try BackupPlanningLimits(
                        maximumSourceItemCount: BackupPlanningLimits.hardMaximumSourceItemCount + 1
                    )
                }
            ),
            (
                "existing backups below minimum",
                {
                    _ = try BackupPlanningLimits(maximumExistingBackupCount: -1)
                }
            ),
            (
                "existing backups above hard maximum",
                {
                    _ = try BackupPlanningLimits(
                        maximumExistingBackupCount: BackupPlanningLimits.hardMaximumExistingBackupCount + 1
                    )
                }
            ),
            (
                "retention items below minimum",
                {
                    _ = try BackupPlanningLimits(maximumRetentionItemCount: -1)
                }
            ),
            (
                "retention items above hard maximum",
                {
                    _ = try BackupPlanningLimits(
                        maximumRetentionItemCount: BackupPlanningLimits.hardMaximumRetentionItemCount + 1
                    )
                }
            ),
            (
                "path bytes below minimum",
                {
                    _ = try BackupPlanningLimits(maximumPathUTF8Bytes: 0)
                }
            ),
            (
                "path bytes above hard maximum",
                {
                    _ = try BackupPlanningLimits(
                        maximumPathUTF8Bytes: BackupPlanningLimits.hardMaximumPathUTF8Bytes + 1
                    )
                }
            ),
            (
                "aggregate path bytes below per-path bytes",
                {
                    _ = try BackupPlanningLimits(
                        maximumPathUTF8Bytes: 100,
                        maximumTotalPathUTF8Bytes: 99
                    )
                }
            ),
            (
                "aggregate path bytes above hard maximum",
                {
                    _ = try BackupPlanningLimits(
                        maximumTotalPathUTF8Bytes: BackupPlanningLimits.hardMaximumTotalPathUTF8Bytes + 1
                    )
                }
            ),
            (
                "work units below minimum",
                {
                    _ = try BackupPlanningLimits(maximumEstimatedWorkUnits: 0)
                }
            ),
            (
                "work units above hard maximum",
                {
                    _ = try BackupPlanningLimits(
                        maximumEstimatedWorkUnits: BackupPlanningLimits.hardMaximumEstimatedWorkUnits + 1
                    )
                }
            ),
            (
                "output bytes below minimum",
                {
                    _ = try BackupPlanningLimits(maximumOutputBytes: 0)
                }
            ),
            (
                "output bytes above hard maximum",
                {
                    _ = try BackupPlanningLimits(
                        maximumOutputBytes: BackupPlanningLimits.hardMaximumOutputBytes + 1
                    )
                }
            ),
            (
                "plan steps below minimum",
                {
                    _ = try BackupPlanningLimits(maximumPlanStepCount: 0)
                }
            ),
            (
                "plan steps above hard maximum",
                {
                    _ = try BackupPlanningLimits(
                        maximumPlanStepCount: BackupPlanningLimits.hardMaximumPlanStepCount + 1
                    )
                }
            )
        ]

        for (name, operation) in cases {
            XCTAssertThrowsError(try operation(), name) { error in
                guard case .invalidLimit = error as? BackupPolicyError else {
                    return XCTFail("Expected invalidLimit for \(name), got \(error)")
                }
            }
        }

        let hardMaximums = try BackupPlanningLimits(
            maximumNameCandidates: BackupPlanningLimits.hardMaximumNameCandidates,
            maximumSourceItemCount: BackupPlanningLimits.hardMaximumSourceItemCount,
            maximumExistingBackupCount: BackupPlanningLimits.hardMaximumExistingBackupCount,
            maximumRetentionItemCount: BackupPlanningLimits.hardMaximumRetentionItemCount,
            maximumPathUTF8Bytes: BackupPlanningLimits.hardMaximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: BackupPlanningLimits.hardMaximumTotalPathUTF8Bytes,
            maximumEstimatedWorkUnits: BackupPlanningLimits.hardMaximumEstimatedWorkUnits,
            maximumOutputBytes: BackupPlanningLimits.hardMaximumOutputBytes,
            maximumPlanStepCount: BackupPlanningLimits.hardMaximumPlanStepCount
        )
        XCTAssertEqual(hardMaximums.maximumNameCandidates, BackupPlanningLimits.hardMaximumNameCandidates)
        XCTAssertEqual(hardMaximums.maximumSourceItemCount, BackupPlanningLimits.hardMaximumSourceItemCount)
        XCTAssertEqual(hardMaximums.maximumExistingBackupCount, BackupPlanningLimits.hardMaximumExistingBackupCount)
        XCTAssertEqual(hardMaximums.maximumRetentionItemCount, BackupPlanningLimits.hardMaximumRetentionItemCount)
        XCTAssertEqual(hardMaximums.maximumPathUTF8Bytes, BackupPlanningLimits.hardMaximumPathUTF8Bytes)
        XCTAssertEqual(hardMaximums.maximumTotalPathUTF8Bytes, BackupPlanningLimits.hardMaximumTotalPathUTF8Bytes)
        XCTAssertEqual(hardMaximums.maximumEstimatedWorkUnits, BackupPlanningLimits.hardMaximumEstimatedWorkUnits)
        XCTAssertEqual(hardMaximums.maximumOutputBytes, BackupPlanningLimits.hardMaximumOutputBytes)
        XCTAssertEqual(hardMaximums.maximumPlanStepCount, BackupPlanningLimits.hardMaximumPlanStepCount)
    }

    func testPolicyRejectsInvalidComponentsMetadataAndRetention() throws {
        XCTAssertThrowsError(
            try BackupPolicy(enabledTriggers: [.beforeSave, .beforeSave])
        ) { error in
            XCTAssertEqual(error as? BackupPolicyError, .duplicateTrigger)
        }

        for component in ["", ".", "..", "nested/path", "nul\0name", String(repeating: "a", count: 256)] {
            XCTAssertThrowsError(
                try BackupPolicy(destination: .sourceParentSubdirectory(component)),
                component
            ) { error in
                XCTAssertEqual(error as? BackupPolicyError, .invalidDestinationComponent(component))
            }
        }

        for suffix in ["", "bad/suffix", "bad\0suffix", String(repeating: "b", count: 129)] {
            XCTAssertThrowsError(
                try BackupPolicy(naming: BackupNamingPolicy(suffix: suffix)),
                suffix
            ) { error in
                XCTAssertEqual(error as? BackupPolicyError, .invalidNamingSuffix(suffix))
            }
        }

        XCTAssertThrowsError(
            try BackupPolicy(retention: BackupRetentionPolicy(maximumCount: 0))
        ) { error in
            XCTAssertEqual(error as? BackupPolicyError, .invalidRetentionCount(0))
        }
        XCTAssertThrowsError(
            try BackupPolicy(retention: BackupRetentionPolicy(maximumAgeSeconds: 0))
        ) { error in
            XCTAssertEqual(error as? BackupPolicyError, .invalidRetentionAge(0))
        }
        XCTAssertThrowsError(
            try BackupPolicy(metadataRequirements: [])
        ) { error in
            XCTAssertEqual(error as? BackupPolicyError, .invalidMetadataRequirements(0))
        }
        XCTAssertThrowsError(
            try BackupPolicy(metadataRequirements: BackupMetadataRequirements(rawValue: 1 << 15))
        ) { error in
            XCTAssertEqual(error as? BackupPolicyError, .invalidMetadataRequirements(1 << 15))
        }
    }

    func testRelativePathValidationAndUTF8Boundaries() throws {
        let invalidPaths = [
            "",
            "/absolute",
            ".",
            "..",
            "a/./b",
            "a/../b",
            "a//b",
            "a/",
            "a\0b",
            String(repeating: "x", count: 256)
        ]
        for path in invalidPaths {
            XCTAssertThrowsError(try BackupRelativePath(path), path) { error in
                XCTAssertEqual(error as? BackupPolicyError, .invalidRelativePath(path))
            }
        }

        let maximumComponent = String(repeating: "é", count: 127) + "a"
        XCTAssertEqual(maximumComponent.utf8.count, 255)
        let valid = try BackupRelativePath("directory/\(maximumComponent)")
        XCTAssertEqual(valid.components, ["directory", maximumComponent])
        XCTAssertEqual(valid.rawUTF8Bytes, Array(valid.rawValue.utf8))
        XCTAssertEqual(valid.componentUTF8Bytes, valid.components.map { Array($0.utf8) })

        let oversized = String(repeating: "a/", count: BackupRelativePath.maximumComponentCount) + "z"
        XCTAssertThrowsError(try BackupRelativePath(oversized)) { error in
            XCTAssertEqual(error as? BackupPolicyError, .invalidRelativePath(oversized))
        }
    }

    func testCandidateNamesAreDeterministicAndEnforcePathBudgets() throws {
        let limits = try BackupPlanningLimits(
            maximumNameCandidates: 3,
            maximumPathUTF8Bytes: 128,
            maximumTotalPathUTF8Bytes: 128,
            maximumEstimatedWorkUnits: 3
        )
        let policy = try BackupPolicy(
            naming: BackupNamingPolicy(style: .suffixAndTimestamp, suffix: ".backup"),
            collisionBehavior: .useNumberedCandidates,
            retention: .keepAll,
            limits: limits
        )
        let timestamp = try BackupTimestamp(secondsSince1970: -7, nanoseconds: 42)
        XCTAssertEqual(
            try BackupPlanner(policy: policy).candidateNames(
                for: URL(filePath: "/tmp/report.txt"),
                at: timestamp
            ),
            [
                "report.txt.backup.-7.000000042",
                "report.txt.backup.-7.000000042.1",
                "report.txt.backup.-7.000000042.2"
            ]
        )

        let narrowLimits = try BackupPlanningLimits(
            maximumNameCandidates: 1,
            maximumPathUTF8Bytes: 20,
            maximumTotalPathUTF8Bytes: 100
        )
        let narrowPolicy = try BackupPolicy(
            naming: BackupNamingPolicy(style: .suffixOnly, suffix: String(repeating: "x", count: 20)),
            collisionBehavior: .fail,
            retention: .keepAll,
            limits: narrowLimits
        )
        XCTAssertThrowsError(
            try BackupPlanner(policy: narrowPolicy).candidateNames(
                for: URL(filePath: "/tmp/f"),
                at: timestamp
            )
        ) { error in
            guard case .pathTooLarge = error as? BackupPolicyError else {
                return XCTFail("Expected pathTooLarge, got \(error)")
            }
        }
    }

    func testAggregatePathAndWorkBudgetsFailIndependently() throws {
        let timestamp = try BackupTimestamp(secondsSince1970: 0)
        let aggregateLimits = try BackupPlanningLimits(
            maximumNameCandidates: 2,
            maximumPathUTF8Bytes: 7,
            maximumTotalPathUTF8Bytes: 9,
            maximumEstimatedWorkUnits: 2
        )
        let aggregatePolicy = try BackupPolicy(
            naming: BackupNamingPolicy(style: .suffixOnly, suffix: ".b"),
            collisionBehavior: .useNumberedCandidates,
            retention: .keepAll,
            limits: aggregateLimits
        )
        XCTAssertThrowsError(
            try BackupPlanner(policy: aggregatePolicy).candidateNames(
                for: URL(filePath: "/s"),
                at: timestamp
            )
        ) { error in
            XCTAssertEqual(error as? BackupPolicyError, .totalPathsTooLarge(maximumUTF8Bytes: 9))
        }

        let workLimits = try BackupPlanningLimits(
            maximumNameCandidates: 2,
            maximumPathUTF8Bytes: 64,
            maximumTotalPathUTF8Bytes: 64,
            maximumEstimatedWorkUnits: 1
        )
        let workPolicy = try BackupPolicy(
            naming: BackupNamingPolicy(style: .suffixOnly, suffix: ".b"),
            collisionBehavior: .useNumberedCandidates,
            retention: .keepAll,
            limits: workLimits
        )
        XCTAssertThrowsError(
            try BackupPlanner(policy: workPolicy).candidateNames(
                for: URL(filePath: "/s"),
                at: timestamp
            )
        ) { error in
            XCTAssertEqual(error as? BackupPolicyError, .workLimitExceeded(maximumUnits: 1))
        }
    }

    func testMetadataAndSecurityScopeRequirementsAreIndependent() throws {
        let fixture = try makePlanningFixture()
        let metadataPolicy = try basePolicy()
        let partialTree = BackupTreeSnapshot(
            rootIdentity: fixture.sourceTree.rootIdentity,
            metadataRequirements: [.permissions]
        )
        let partialBinding = try authenticatedBinding(
            source: partialTree.rootIdentity.stableNodeIdentity,
            destination: fixture.destinationIdentity.stableNodeIdentity
        )
        let metadataRequest = BackupPlanningRequest(
            trigger: .beforeSave,
            sourceBinding: partialBinding,
            timestamp: fixture.request.timestamp,
            source: BackupSourceObservation(
                sourceURL: fixture.request.source.sourceURL,
                parentDirectoryIdentity: fixture.request.source.parentDirectoryIdentity,
                tree: partialTree,
                accessRequirement: .declaredAmbientAccess
            ),
            destination: fixture.request.destination,
            parentMutationCapability: fixture.request.parentMutationCapability
        )
        assertInvalidObservation(try BackupPlanner(policy: metadataPolicy).plan(metadataRequest))

        let scopedPolicy = try BackupPolicy(
            naming: BackupNamingPolicy(style: .suffixOnly, suffix: ".backup"),
            collisionBehavior: .fail,
            retention: .keepAll,
            sandboxAccessPolicy: .requireSecurityScopedAccess
        )
        XCTAssertThrowsError(try BackupPlanner(policy: scopedPolicy).plan(fixture.request)) { error in
            XCTAssertEqual(
                error as? BackupPolicyError,
                .securityScopedAccessRequired(fixture.request.source.sourceURL.path)
            )
        }

        let sourceURL = fixture.request.source.sourceURL
        let scopedSource = BackupSourceObservation(
            sourceURL: sourceURL,
            parentDirectoryIdentity: nil,
            tree: fixture.sourceTree,
            accessRequirement: .securityScoped(resourceURL: sourceURL)
        )
        let destinationURL = fixture.request.destination.directoryURL
        let scopedDestination = BackupDestinationObservation(
            directoryURL: destinationURL,
            directoryIdentity: fixture.destinationIdentity,
            accessRequirement: .securityScoped(resourceURL: destinationURL),
            nameCandidates: fixture.request.destination.nameCandidates
        )
        let scopedRequest = BackupPlanningRequest(
            trigger: .beforeSave,
            sourceBinding: fixture.sourceBinding,
            timestamp: fixture.request.timestamp,
            source: scopedSource,
            destination: scopedDestination,
            parentMutationCapability: fixture.request.parentMutationCapability
        )
        let scopedPlan = try BackupPlanner(policy: scopedPolicy).plan(scopedRequest)
        guard case .createBackup(let copy) = scopedPlan.steps.first else {
            return XCTFail("Expected create step")
        }
        XCTAssertEqual(copy.source.path, .root)
        XCTAssertEqual(copy.source.root.accessRequirement, .securityScoped(resourceURL: sourceURL))
        XCTAssertEqual(copy.destination.root.accessRequirement, .securityScoped(resourceURL: destinationURL))
    }

    func testParentMutationCapabilityRequiresDestinationBindingButPreservesSupportedSemantics() throws {
        let fixture = try makePlanningFixture()
        let withoutCapability = replacingRequest(fixture.request, parentMutationCapability: nil)
        assertInvalidObservation(try BackupPlanner(policy: fixture.policy).plan(withoutCapability))

        let otherDestination = stableIdentity(
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            inode: fixture.destinationIdentity.inode + 1,
            generation: fixture.destinationIdentity.generation.rawValue
        )
        let mismatched = try BackupParentMutationCapability(
            capabilityIdentifier: bytes(0x75),
            destinationDirectoryIdentity: otherDestination,
            semantics: .executorHeldExclusiveAuthority
        )
        assertInvalidObservation(
            try BackupPlanner(policy: fixture.policy).plan(
                replacingRequest(fixture.request, parentMutationCapability: mismatched)
            )
        )

        for semantics: BackupParentMutationSemantics in [
            .executorHeldExclusiveAuthority,
            .descriptorRelativeIdentityConditional
        ] {
            let capability = try BackupParentMutationCapability(
                capabilityIdentifier: bytes(semantics == .executorHeldExclusiveAuthority ? 0x76 : 0x77),
                destinationDirectoryIdentity: fixture.destinationIdentity.stableNodeIdentity,
                semantics: semantics
            )
            let plan = try BackupPlanner(policy: fixture.policy).plan(
                replacingRequest(fixture.request, parentMutationCapability: capability)
            )
            XCTAssertEqual(plan.parentMutationCapability, capability)
        }
    }

    func testCanonicalPolicyPersistenceHasExactSchemaAndRoundTrips() throws {
        let expected =
            #"{"collisionBehavior":"useNumberedCandidates","destination":{"kind":"alongsideSource","value":null},"enabledTriggers":["beforeSave","beforeFileOperation"],"limits":{"maximumEstimatedWorkUnits":1000000,"maximumExistingBackupCount":4096,"maximumNameCandidates":128,"maximumOutputBytes":4294967296,"maximumPathUTF8Bytes":4096,"maximumPlanStepCount":4096,"maximumRetentionItemCount":100000,"maximumSourceItemCount":100000,"maximumTotalPathUTF8Bytes":16777216},"metadataRequirements":127,"naming":{"style":"suffixAndTimestamp","suffix":".macmerge-backup"},"retention":{"maximumAgeSeconds":null,"maximumCount":20},"sandboxAccessPolicy":"allowDeclaredAmbientAccess","schemaVersion":1}"#
        let data = try BackupPolicy.default.encodedData()

        XCTAssertEqual(String(decoding: data, as: UTF8.self), expected)
        XCTAssertEqual(try BackupPolicy.decode(from: data), .default)
        XCTAssertEqual(BackupPolicyPersistenceFormat.mediaType, "application/vnd.macmerge.backup-policy+json")
        XCTAssertEqual(
            BackupPolicyPersistenceFormat.canonicalEncodingIdentifier,
            "com.macmerge.backup-policy.canonical-json.v1"
        )

        let custom = try BackupPolicy(
            enabledTriggers: [.beforeFileOperation, .beforeSave],
            destination: .customDirectory(URL(filePath: "/tmp/backups")),
            naming: BackupNamingPolicy(style: .suffixOnly, suffix: ".\"\\\t-é"),
            collisionBehavior: .fail,
            retention: .keepAll,
            metadataRequirements: [.permissions, .timestamps],
            sandboxAccessPolicy: .requireSecurityScopedAccess
        )
        XCTAssertEqual(custom.enabledTriggers, [.beforeSave, .beforeFileOperation])
        XCTAssertEqual(try BackupPolicy.decode(from: custom.encodedData()), custom)
        guard case .customDirectory(let url) = custom.destination else {
            return XCTFail("Expected custom destination")
        }
        XCTAssertEqual(url.path, "/tmp/backups")
    }

    func testPersistenceRejectsNoncanonicalMalformedFutureAndOversizedData() throws {
        let canonical = try BackupPolicy.default.encodedData()
        var whitespace = canonical
        whitespace.insert(0x20, at: whitespace.index(before: whitespace.endIndex))
        XCTAssertThrowsError(try BackupPolicy.decode(from: whitespace)) { error in
            XCTAssertEqual(error as? BackupPolicyError, .nonCanonicalPersistence)
        }

        let canonicalText = String(decoding: canonical, as: UTF8.self)
        let firstMember = #""collisionBehavior":"useNumberedCandidates""#
        let secondMember = #""destination":{"kind":"alongsideSource","value":null}"#
        let reordered = Data(
            canonicalText.replacingOccurrences(
                of: "\(firstMember),\(secondMember)",
                with: "\(secondMember),\(firstMember)"
            ).utf8
        )
        XCTAssertThrowsError(try BackupPolicy.decode(from: reordered)) { error in
            XCTAssertEqual(error as? BackupPolicyError, .nonCanonicalPersistence)
        }

        let future = Data(
            String(decoding: canonical, as: UTF8.self)
                .replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":2"#)
                .utf8
        )
        XCTAssertThrowsError(try BackupPolicy.decode(from: future)) { error in
            XCTAssertEqual(error as? BackupPolicyError, .unsupportedSchemaVersion(2))
        }
        XCTAssertThrowsError(try BackupPolicy.decode(from: Data([0xFF]))) { error in
            XCTAssertEqual(error as? BackupPolicyError, .malformedPersistence)
        }
        XCTAssertThrowsError(
            try BackupPolicy.decode(from: Data(repeating: 0x20, count: BackupPolicy.maximumEncodedBytes + 1))
        ) { error in
            XCTAssertEqual(
                error as? BackupPolicyError,
                .persistenceDataTooLarge(maximumBytes: BackupPolicy.maximumEncodedBytes)
            )
        }
    }

    func testSourceBindingAuthenticationBytesMatchIndependentCanonicalFraming() throws {
        let source = BackupStableNodeIdentity(
            persistentVolumeIdentity: try BackupPersistentVolumeIdentity(bytes: [1, 2]),
            inode: 3,
            generation: BackupReliableFileGeneration(reliablyReportedValue: 4)
        )
        let destination = BackupStableNodeIdentity(
            persistentVolumeIdentity: try BackupPersistentVolumeIdentity(bytes: [5, 6, 7]),
            inode: 8,
            generation: BackupReliableFileGeneration(reliablyReportedValue: 9)
        )
        let notBefore = try BackupTimestamp(secondsSince1970: -2, nanoseconds: 3)
        let issued = try BackupTimestamp(secondsSince1970: 10, nanoseconds: 11)
        let expires = try BackupTimestamp(secondsSince1970: 20, nanoseconds: 21)
        let binding = try BackupSourceBinding(
            sourceBindingIdentifier: bytes(0xA1),
            seriesIdentifier: "series_1",
            sourceRootIdentity: source,
            destinationDirectoryIdentity: destination,
            provenanceNotBefore: notBefore,
            issuedAt: issued,
            expiresAt: expires
        )

        var expected = Data(BackupAuthenticationFormat.sourceBindingDomain.utf8)
        expected.append(0)
        appendField(Array("key-1".utf8), to: &expected)
        appendField(uint64Bytes(UInt64(BackupSourceBinding.currentSchemaVersion)), to: &expected)
        appendField(bytes(0xA1), to: &expected)
        appendField(Array("series_1".utf8), to: &expected)
        appendStableIdentity(source, to: &expected)
        appendStableIdentity(destination, to: &expected)
        appendTimestamp(notBefore, to: &expected)
        appendTimestamp(issued, to: &expected)
        appendTimestamp(expires, to: &expected)

        XCTAssertEqual(try binding.authenticationBytes(keyIdentifier: "key-1"), expected)
        XCTAssertNotEqual(
            try binding.authenticationBytes(keyIdentifier: "key-1"),
            try binding.authenticationBytes(keyIdentifier: "key-2")
        )
        XCTAssertEqual(BackupAuthenticationFormat.algorithmIdentifier, "HMAC-SHA256")
        XCTAssertEqual(BackupSourceBinding.currentSchemaVersion, 3)
        XCTAssertEqual(BackupProvenance.currentSchemaVersion, 4)
        XCTAssertEqual(BackupTransactionJournalRecord.currentSchemaVersion, 3)
    }

    func testProvenanceAuthenticationBytesMatchIndependentGoldenFraming() throws {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1, 2])
        let source = try item(volume: volume, inode: 3, size: 4, charge: 4)
        let destination = stableIdentity(volume: volume, inode: 5, generation: 6)
        let tree = BackupTreeSnapshot(rootIdentity: source, metadataRequirements: [.permissions, .timestamps])
        let binding = try sourceBinding(source: source.stableNodeIdentity, destination: destination)
        let provenance = try makeProvenance(
            sourceBinding: binding,
            sourceRootIdentity: source,
            destination: destination,
            name: "golden.backup",
            tree: tree,
            createdAt: try timestamp(1_234),
            transactionByte: 0x44
        )

        var expected = Data(BackupAuthenticationFormat.provenanceDomain.utf8)
        expected.append(0)
        appendField(Array("key-1".utf8), to: &expected)
        appendField(uint64Bytes(UInt64(BackupProvenance.currentSchemaVersion)), to: &expected)
        appendField(bytes(0x44), to: &expected)
        appendField(binding.sourceBindingIdentifier, to: &expected)
        appendField(Array(binding.seriesIdentifier.utf8), to: &expected)
        appendField(Array("golden.backup".utf8), to: &expected)
        appendTimestamp(try timestamp(1_234), to: &expected)
        appendItemIdentity(source, to: &expected)
        appendStableIdentity(destination, to: &expected)
        appendItemIdentity(source, to: &expected)
        appendField(uint16Bytes(tree.metadataRequirements.rawValue), to: &expected)
        appendField(uint64Bytes(0), to: &expected)

        XCTAssertEqual(try provenance.authenticationBytes(keyIdentifier: "key-1"), expected)
    }

    func testAuthenticationBindsVolumeGenerationSourceAndCompleteTree() throws {
        let volumeA = try BackupPersistentVolumeIdentity(bytes: [1])
        let volumeB = try BackupPersistentVolumeIdentity(bytes: [2])
        let sourceA = stableIdentity(volume: volumeA, inode: 10, generation: 1)
        let sourceB = stableIdentity(volume: volumeA, inode: 10, generation: 2)
        let sourceC = stableIdentity(volume: volumeB, inode: 10, generation: 1)
        let destination = stableIdentity(volume: volumeA, inode: 20, generation: 1)
        let first = try sourceBinding(source: sourceA, destination: destination)
        let generationChanged = try sourceBinding(source: sourceB, destination: destination)
        let volumeChanged = try sourceBinding(source: sourceC, destination: destination)

        XCTAssertNotEqual(
            try first.authenticationBytes(keyIdentifier: "key"),
            try generationChanged.authenticationBytes(keyIdentifier: "key")
        )
        XCTAssertNotEqual(
            try first.authenticationBytes(keyIdentifier: "key"),
            try volumeChanged.authenticationBytes(keyIdentifier: "key")
        )

        let root = try item(volume: volumeA, inode: 30, kind: .directory, linkCount: 2, charge: 1)
        let child = try item(volume: volumeA, inode: 31, size: 4, charge: 4)
        let tree = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [BackupObservedTreeEntry(relativePath: try BackupRelativePath("child"), identity: child)]
        )
        let provenance = try makeProvenance(
            sourceBinding: first,
            sourceRootIdentity: root,
            destination: destination,
            name: "backup",
            tree: tree
        )
        let changedChild = replacing(child, contentSeed: 0xE1)
        let changedTree = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("child"), identity: changedChild)
            ]
        )
        let changedProvenance = try makeProvenance(
            sourceBinding: first,
            sourceRootIdentity: root,
            destination: destination,
            name: "backup",
            tree: changedTree
        )
        XCTAssertNotEqual(
            try provenance.authenticationBytes(keyIdentifier: "key"),
            try changedProvenance.authenticationBytes(keyIdentifier: "key")
        )
    }

    func testStreamingProvenanceAndJournalEncodingsMatchMaterializedBytesAndPropagateCancellation() async throws {
        let fixture = try makePlanningFixture()
        let provenance = try makeProvenance(
            sourceBinding: fixture.sourceBinding.binding,
            sourceRootIdentity: fixture.sourceTree.rootIdentity,
            destination: fixture.destinationIdentity.stableNodeIdentity,
            name: fixture.publicationName,
            tree: fixture.sourceTree
        )
        let authenticatedProvenance = try BackupAuthenticatedProvenance(
            provenance: provenance,
            keyIdentifier: "key",
            authenticationTag: bytes(0x91)
        )
        var streamedProvenance = Data()
        try authenticatedProvenance.writeAuthenticationBytes { streamedProvenance.append($0) }
        XCTAssertEqual(streamedProvenance, try authenticatedProvenance.authenticationBytes())

        let prepared = try journalRecord(fixture: fixture, kind: .prepared, sequence: 0, previousTag: nil)
        let authenticatedJournal = try BackupAuthenticatedTransactionJournalRecord(
            record: prepared,
            keyIdentifier: "key",
            authenticationTag: bytes(0x92)
        )
        var streamedJournal = Data()
        try authenticatedJournal.writeEncodedData { streamedJournal.append($0) }
        var expectedJournal = try authenticatedJournal.authenticationBytes()
        appendField(bytes(0x92), to: &expectedJournal)
        XCTAssertEqual(streamedJournal, expectedJournal)
        XCTAssertEqual(try authenticatedJournal.encodedData(), expectedJournal)
        XCTAssertThrowsError(
            try authenticatedJournal.writeEncodedData { _ in throw CancellationError() }
        ) { error in
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }

        let plannerTask = Task {
            while !Task.isCancelled { await Task.yield() }
            return try BackupPlanner(policy: fixture.policy).plan(fixture.request)
        }
        plannerTask.cancel()
        do {
            _ = try await plannerTask.value
            XCTFail("Cancelled planner unexpectedly returned a plan")
        } catch {
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
    }

    func testTreeManifestRequiresCanonicalParentsKindsAndOrder() throws {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let root = try item(volume: volume, inode: 1, kind: .directory, linkCount: 3, charge: 1)
        let directory = try item(volume: volume, inode: 2, kind: .directory, linkCount: 2, charge: 1)
        let file = try item(volume: volume, inode: 3, size: 5, charge: 5)
        let canonical = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("dir"), identity: directory),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("dir/file"), identity: file)
            ]
        )

        let manifest = try BackupStagedConstructionManifest.entries(for: canonical)
        XCTAssertEqual(manifest.map(\.relativePath.rawValue), ["dir", "dir/file"])
        XCTAssertEqual(manifest.map(\.parentRelativePath?.rawValue), [nil, "dir"])
        XCTAssertEqual(manifest.map(\.name), ["dir", "file"])
        XCTAssertEqual(manifest.map(\.expectedKind), [.directory, .regularFile])

        let siblingA = try item(volume: volume, inode: 4, size: 2, charge: 2)
        let siblingB = try item(volume: volume, inode: 5, size: 3, charge: 3)
        let sortedSiblings = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("a"), identity: siblingA),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("b"), identity: siblingB)
            ]
        )
        XCTAssertEqual(
            try BackupStagedConstructionManifest.entries(for: sortedSiblings).map(\.name),
            ["a", "b"]
        )

        let unsortedSiblings = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: sortedSiblings.descendants.reversed()
        )
        assertInvalidObservation(try BackupStagedConstructionManifest.entries(for: unsortedSiblings))

        let missingParent = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("missing/file"), identity: file)
            ]
        )
        assertInvalidObservation(try BackupStagedConstructionManifest.entries(for: missingParent))

        let unsupported = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(
                    relativePath: try BackupRelativePath("link"),
                    identity: replacing(file, kind: .symbolicLink)
                )
            ]
        )
        assertInvalidObservation(try BackupStagedConstructionManifest.entries(for: unsupported))
    }

    func testConstructionManifestRejectsIndependentFieldAndTopologyMutations() throws {
        let sourceTree = try directorySourceTree()
        let manifest = try BackupStagedConstructionManifest.entries(for: sourceTree)
        let entry = try XCTUnwrap(manifest.first)

        assertInvalidObservation(
            try BackupStagedConstructionManifestEntry(
                relativePath: entry.relativePath,
                parentRelativePath: try BackupRelativePath("other"),
                name: entry.name,
                expectedKind: entry.expectedKind,
                sourceNodeIdentity: entry.sourceNodeIdentity
            )
        )
        assertInvalidObservation(
            try BackupStagedConstructionManifestEntry(
                relativePath: entry.relativePath,
                parentRelativePath: entry.parentRelativePath,
                name: "other",
                expectedKind: entry.expectedKind,
                sourceNodeIdentity: entry.sourceNodeIdentity
            )
        )

        let fixture = try makePlanningFixture(sourceTree: sourceTree)
        let stagedRoot = try copiedIdentity(
            sourceTree.rootIdentity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 100
        )
        let mutated = try BackupStagedConstructionManifestEntry(
            relativePath: entry.relativePath,
            parentRelativePath: entry.parentRelativePath,
            name: entry.name,
            expectedKind: entry.expectedKind,
            sourceNodeIdentity: stableIdentity(
                volume: sourceTree.rootIdentity.persistentVolumeIdentity,
                inode: entry.sourceNodeIdentity.inode + 1,
                generation: entry.sourceNodeIdentity.generation.rawValue
            )
        )
        assertInvalidObservation(
            try journalRecord(
                fixture: fixture,
                kind: .stageConstructionIntent,
                sequence: 2,
                previousTag: bytes(0x20),
                stagedConstructionManifest: [mutated],
                stagedConstructionInFlightIndex: 0,
                stagingRootIdentity: stagedRoot.stableNodeIdentity
            )
        )
    }

    func testTreeHardlinksRequireAllAndExactlyInTreeAliases() throws {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let root = try item(volume: volume, inode: 1, kind: .directory, linkCount: 2, charge: 1)
        let hardlink = try item(volume: volume, inode: 2, linkCount: 2, size: 8, charge: 8)
        let exactTree = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("a"), identity: hardlink),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("b"), identity: hardlink)
            ]
        )
        XCTAssertEqual(try BackupStagedConstructionManifest.entries(for: exactTree).count, 2)

        let externalAliasTree = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("a"), identity: hardlink)
            ]
        )
        assertInvalidObservation(try BackupStagedConstructionManifest.entries(for: externalAliasTree))

        let underreported = replacing(hardlink, linkCount: 1)
        let underreportedTree = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("a"), identity: underreported),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("b"), identity: underreported)
            ]
        )
        assertInvalidObservation(try BackupStagedConstructionManifest.entries(for: underreportedTree))

        let overreported = replacing(hardlink, linkCount: 3)
        let overreportedTree = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("a"), identity: overreported),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("b"), identity: overreported)
            ]
        )
        assertInvalidObservation(try BackupStagedConstructionManifest.entries(for: overreportedTree))
    }

    func testTreeHardlinksRejectConflictingContentOrMetadataForStableIdentity() throws {
        let sourceTree = try hardlinkSourceTree()
        let hardlink = sourceTree.descendants[0].identity
        let conflicts = [
            replacing(hardlink, contentSeed: 0xE1),
            replacing(hardlink, requiredMetadataSeed: 0xE2)
        ]

        for conflict in conflicts {
            let tree = BackupTreeSnapshot(
                rootIdentity: sourceTree.rootIdentity,
                metadataRequirements: sourceTree.metadataRequirements,
                descendants: [
                    sourceTree.descendants[0],
                    BackupObservedTreeEntry(relativePath: sourceTree.descendants[1].relativePath, identity: conflict)
                ]
            )
            assertInvalidObservation(try BackupStagedConstructionManifest.entries(for: tree))
        }
    }

    func testPublicationEquivalencePreservesHardlinksAndRejectsSplitOrMergedClasses() throws {
        let hardlinkSource = try hardlinkSourceTree()
        let hardlinkFixture = try makePlanningFixture(sourceTree: hardlinkSource)
        let destination = hardlinkFixture.destinationIdentity
        let preserved = try copiedTree(
            hardlinkSource,
            volume: destination.persistentVolumeIdentity,
            device: destination.device,
            firstInode: 100
        )
        XCTAssertNoThrow(
            try journalRecord(
                fixture: hardlinkFixture,
                kind: .publicationIntent,
                sequence: 4,
                previousTag: bytes(0x20),
                stagedTree: preserved,
                stagingRootIdentity: preserved.rootIdentity.stableNodeIdentity
            )
        )

        let splitRoot = try copiedIdentity(
            hardlinkSource.rootIdentity,
            volume: destination.persistentVolumeIdentity,
            device: destination.device,
            inode: 200
        )
        let sourceHardlink = hardlinkSource.descendants[0].identity
        let splitA = replacing(
            try copiedIdentity(
                sourceHardlink,
                volume: destination.persistentVolumeIdentity,
                device: destination.device,
                inode: 201
            ),
            linkCount: 1
        )
        let splitB = replacing(
            try copiedIdentity(
                sourceHardlink,
                volume: destination.persistentVolumeIdentity,
                device: destination.device,
                inode: 202
            ),
            linkCount: 1
        )
        let split = BackupTreeSnapshot(
            rootIdentity: splitRoot,
            metadataRequirements: hardlinkSource.metadataRequirements,
            descendants: [
                BackupObservedTreeEntry(relativePath: hardlinkSource.descendants[0].relativePath, identity: splitA),
                BackupObservedTreeEntry(relativePath: hardlinkSource.descendants[1].relativePath, identity: splitB)
            ]
        )
        assertInvalidObservation(
            try journalRecord(
                fixture: hardlinkFixture,
                kind: .publicationIntent,
                sequence: 4,
                previousTag: bytes(0x20),
                stagedTree: split,
                stagingRootIdentity: splitRoot.stableNodeIdentity
            )
        )

        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let distinctRoot = try item(volume: volume, inode: 10, kind: .directory, linkCount: 2, charge: 1)
        let distinctA = try item(volume: volume, inode: 11, size: 8, charge: 8)
        let distinctB = replacing(distinctA, inode: 12, generation: 112)
        let distinctSource = BackupTreeSnapshot(
            rootIdentity: distinctRoot,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("a"), identity: distinctA),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("b"), identity: distinctB)
            ]
        )
        let distinctFixture = try makePlanningFixture(sourceTree: distinctSource)
        let mergedRoot = try copiedIdentity(
            distinctRoot,
            volume: distinctFixture.destinationIdentity.persistentVolumeIdentity,
            device: distinctFixture.destinationIdentity.device,
            inode: 300
        )
        let mergedFile = replacing(
            try copiedIdentity(
                distinctA,
                volume: distinctFixture.destinationIdentity.persistentVolumeIdentity,
                device: distinctFixture.destinationIdentity.device,
                inode: 301
            ),
            linkCount: 2
        )
        let merged = BackupTreeSnapshot(
            rootIdentity: mergedRoot,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: distinctSource.descendants[0].relativePath, identity: mergedFile),
                BackupObservedTreeEntry(relativePath: distinctSource.descendants[1].relativePath, identity: mergedFile)
            ]
        )
        assertInvalidObservation(
            try journalRecord(
                fixture: distinctFixture,
                kind: .publicationIntent,
                sequence: 4,
                previousTag: bytes(0x20),
                stagedTree: merged,
                stagingRootIdentity: mergedRoot.stableNodeIdentity
            )
        )
    }

    func testPlannerChargesInTreeHardlinkContentOnce() throws {
        let tree = try hardlinkSourceTree()
        let fixture = try makePlanningFixture(sourceTree: tree)

        XCTAssertEqual(fixture.plan.expectedOutputBytes, 10)
        guard case .createBackup(let instruction) = fixture.plan.steps.first else {
            return XCTFail("Expected create step")
        }
        XCTAssertEqual(instruction.expectedOutputBytes, 10)
        XCTAssertEqual(instruction.expectedSourceTree, tree)
    }

    func testPlannerRejectsVolumeGenerationAndSourceBindingDrift() throws {
        let fixture = try makePlanningFixture()

        let wrongGenerationBinding = try authenticatedBinding(
            source: stableIdentity(
                volume: fixture.sourceTree.rootIdentity.persistentVolumeIdentity,
                inode: fixture.sourceTree.rootIdentity.inode,
                generation: fixture.sourceTree.rootIdentity.generation.rawValue + 1
            ),
            destination: fixture.destinationIdentity.stableNodeIdentity
        )
        let wrongBindingRequest = BackupPlanningRequest(
            trigger: fixture.request.trigger,
            sourceBinding: wrongGenerationBinding,
            timestamp: fixture.request.timestamp,
            source: fixture.request.source,
            destination: fixture.request.destination,
            parentMutationCapability: fixture.request.parentMutationCapability
        )
        assertInvalidObservation(try BackupPlanner(policy: fixture.policy).plan(wrongBindingRequest))

        let otherVolume = try BackupPersistentVolumeIdentity(bytes: [9])
        let wrongVolumeTree = BackupTreeSnapshot(
            rootIdentity: replacing(fixture.sourceTree.rootIdentity, volume: otherVolume),
            metadataRequirements: .all
        )
        let wrongVolumeRequest = BackupPlanningRequest(
            trigger: fixture.request.trigger,
            sourceBinding: fixture.sourceBinding,
            timestamp: fixture.request.timestamp,
            source: BackupSourceObservation(
                sourceURL: fixture.request.source.sourceURL,
                parentDirectoryIdentity: fixture.request.source.parentDirectoryIdentity,
                tree: wrongVolumeTree,
                accessRequirement: fixture.request.source.accessRequirement
            ),
            destination: fixture.request.destination,
            parentMutationCapability: fixture.request.parentMutationCapability
        )
        XCTAssertThrowsError(try BackupPlanner(policy: fixture.policy).plan(wrongVolumeRequest)) { error in
            XCTAssertEqual(
                error as? BackupPolicyError,
                .volumeBoundaryNotAllowed(fixture.request.source.sourceURL.path)
            )
        }

        let overlappingDestination = replacing(
            fixture.destinationIdentity,
            inode: fixture.sourceTree.rootIdentity.inode,
            generation: fixture.sourceTree.rootIdentity.generation.rawValue
        )
        let overlapBinding = try authenticatedBinding(
            source: fixture.sourceTree.rootIdentity.stableNodeIdentity,
            destination: overlappingDestination.stableNodeIdentity
        )
        let overlapCapability = try BackupParentMutationCapability(
            capabilityIdentifier: bytes(0x71),
            destinationDirectoryIdentity: overlappingDestination.stableNodeIdentity,
            semantics: .executorHeldExclusiveAuthority
        )
        let overlapRequest = BackupPlanningRequest(
            trigger: fixture.request.trigger,
            sourceBinding: overlapBinding,
            timestamp: fixture.request.timestamp,
            source: BackupSourceObservation(
                sourceURL: fixture.request.source.sourceURL,
                parentDirectoryIdentity: overlappingDestination,
                tree: fixture.sourceTree,
                accessRequirement: fixture.request.source.accessRequirement
            ),
            destination: BackupDestinationObservation(
                directoryURL: fixture.request.destination.directoryURL,
                directoryIdentity: overlappingDestination,
                accessRequirement: .declaredAmbientAccess,
                nameCandidates: fixture.request.destination.nameCandidates
            ),
            parentMutationCapability: overlapCapability
        )
        XCTAssertThrowsError(try BackupPlanner(policy: fixture.policy).plan(overlapRequest)) { error in
            guard case .sourceDestinationOverlap = error as? BackupPolicyError else {
                return XCTFail("Expected sourceDestinationOverlap, got \(error)")
            }
        }
    }

    func testPlannerProducesDescriptorOnlyExecutorContract() throws {
        let fixture = try makePlanningFixture()
        let plan = fixture.plan

        XCTAssertEqual(plan.contract, .required)
        XCTAssertEqual(plan.contract.pathResolution, .descriptorRelativeNoFollow)
        XCTAssertEqual(
            plan.contract.parentMutation,
            .liveExclusiveCapabilityOrDescriptorRelativeIdentityConditionalMutation
        )
        XCTAssertEqual(plan.contract.publication, .stagedAndSyncedThenExclusiveDurablePublish)
        XCTAssertEqual(plan.contract.sourceValidation, .completeTreeIdentityBeforeAndAfterCopy)
        XCTAssertEqual(plan.contract.metadata, .preserveAndVerifyEveryRequirement)
        XCTAssertEqual(plan.contract.retention, .authenticatedCapabilityQuarantineAndRevalidate)
        XCTAssertEqual(plan.contract.cancellation, .reportDurableOrUncertainOutcomeAfterRename)
        XCTAssertEqual(plan.contract.recovery, .resumeAuthenticatedJournalBeforeNewTransaction)
        XCTAssertEqual(plan.contract.transaction.orderedPhases, BackupTransactionPhase.allCases)
        XCTAssertEqual(plan.steps.count, 1)

        guard case .createBackup(let copy) = plan.steps[0] else {
            return XCTFail("Expected create step")
        }
        guard case .boundExisting(let sourcePath) = copy.source.path else {
            return XCTFail("Expected descriptor-bound source path")
        }
        XCTAssertEqual(sourcePath.relativePath.rawValue, "source")
        guard case .newLeaf(let destinationPath) = copy.destination.path else {
            return XCTFail("Expected exclusive destination leaf")
        }
        XCTAssertEqual(destinationPath.rawValue, fixture.publicationName)
        XCTAssertEqual(copy.provenanceRequest.sourceBinding, fixture.sourceBinding)
        XCTAssertEqual(plan.parentMutationCapability, fixture.request.parentMutationCapability)
    }

    func testRootURLPlansFromRootDescriptorWithoutParentIdentity() throws {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let sourceTree = BackupTreeSnapshot(
            rootIdentity: try item(
                volume: volume,
                device: 7,
                inode: 1,
                kind: .directory,
                linkCount: 2,
                charge: 1
            ),
            metadataRequirements: .all
        )
        let destination = try item(
            volume: volume,
            device: 7,
            inode: 2,
            kind: .directory,
            linkCount: 2,
            charge: 1
        )
        let policy = try basePolicy(destination: .customDirectory(URL(filePath: "/synthetic-backups")))
        let fixture = try makePlanningFixture(
            policy: policy,
            sourceURL: URL(filePath: "/"),
            sourceTree: sourceTree,
            destinationURL: URL(filePath: "/synthetic-backups"),
            destinationIdentity: destination,
            parentDirectoryIdentity: nil
        )

        XCTAssertEqual(fixture.publicationName, "root.backup")
        guard case .createBackup(let copy) = fixture.plan.steps.first else {
            return XCTFail("Expected create step")
        }
        XCTAssertEqual(copy.source.path, .root)
        XCTAssertEqual(copy.source.root.url.path, "/")
    }

    func testPlannerPerformsNoFilesystemWritesOrAccessStartup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source")
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let sourceTree = BackupTreeSnapshot(
            rootIdentity: try item(volume: volume, inode: 1, size: 3, charge: 3),
            metadataRequirements: .all
        )
        let parent = try item(
            volume: volume,
            inode: 2,
            kind: .directory,
            linkCount: 2,
            charge: 1
        )
        let fixture = try makePlanningFixture(
            sourceURL: sourceURL,
            sourceTree: sourceTree,
            destinationURL: directory,
            destinationIdentity: parent,
            parentDirectoryIdentity: parent
        )

        XCTAssertEqual(fixture.plan.steps.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: fixture.publicationName).path))
    }

    func testExistingBackupProvenanceSurvivesRemountButRejectsStableIdentityDrift() throws {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let source = try item(volume: volume, inode: 1, size: 3, charge: 3)
        let destination = try item(
            volume: volume,
            inode: 2,
            kind: .directory,
            linkCount: 2,
            charge: 1
        )
        let binding = try sourceBinding(
            source: source.stableNodeIdentity,
            destination: destination.stableNodeIdentity
        )
        let authenticatedBinding = try BackupAuthenticatedSourceBinding(
            binding: binding,
            keyIdentifier: "key",
            authenticationTag: bytes(0x31)
        )
        let authenticatedTree = BackupTreeSnapshot(rootIdentity: source, metadataRequirements: .all)
        let provenance = try makeAuthenticatedProvenance(
            sourceBinding: authenticatedBinding,
            sourceRootIdentity: source,
            destination: destination.stableNodeIdentity,
            name: "old.backup",
            tree: authenticatedTree
        )
        let remountedRoot = replacing(source, device: 99)
        let remountedTree = BackupTreeSnapshot(rootIdentity: remountedRoot, metadataRequirements: .all)
        let remountedPath = try boundPath(name: "old.backup", identity: remountedRoot)

        XCTAssertNoThrow(
            try BackupExistingBackup(
                boundPath: remountedPath,
                provenanceRecord: provenance,
                tree: remountedTree
            )
        )

        let reusedGeneration = replacing(remountedRoot, generation: remountedRoot.generation.rawValue + 1)
        assertInvalidObservation(
            try BackupExistingBackup(
                boundPath: try boundPath(name: "old.backup", identity: reusedGeneration),
                provenanceRecord: provenance,
                tree: BackupTreeSnapshot(rootIdentity: reusedGeneration, metadataRequirements: .all)
            )
        )
    }

    func testRetentionKeepsForeignProvenanceAndRequiresCanonicalTimeAndNameOrder() throws {
        let base = try makePlanningFixture()
        let source = base.sourceTree.rootIdentity
        let destination = base.destinationIdentity
        let owned = try existingBackup(
            sourceBinding: base.sourceBinding,
            sourceRootIdentity: source,
            destination: destination,
            name: "a-owned.backup",
            inode: 300,
            createdAt: try timestamp(800),
            tagByte: 0xA1
        )
        let foreignSeriesBinding = try BackupAuthenticatedSourceBinding(
            binding: BackupSourceBinding(
                sourceBindingIdentifier: base.sourceBinding.binding.sourceBindingIdentifier,
                seriesIdentifier: "foreign-series",
                sourceRootIdentity: source.stableNodeIdentity,
                destinationDirectoryIdentity: destination.stableNodeIdentity,
                provenanceNotBefore: try timestamp(800),
                issuedAt: try timestamp(900),
                expiresAt: try timestamp(2_000)
            ),
            keyIdentifier: "key",
            authenticationTag: bytes(0x32)
        )
        let foreignSeries = try existingBackup(
            sourceBinding: foreignSeriesBinding,
            sourceRootIdentity: source,
            destination: destination,
            name: "b-foreign-series.backup",
            inode: 301,
            createdAt: try timestamp(800),
            tagByte: 0xA2
        )
        let foreignCapabilityBinding = try BackupAuthenticatedSourceBinding(
            binding: BackupSourceBinding(
                sourceBindingIdentifier: bytes(0x21),
                seriesIdentifier: base.sourceBinding.binding.seriesIdentifier,
                sourceRootIdentity: source.stableNodeIdentity,
                destinationDirectoryIdentity: destination.stableNodeIdentity,
                provenanceNotBefore: try timestamp(800),
                issuedAt: try timestamp(900),
                expiresAt: try timestamp(2_000)
            ),
            keyIdentifier: "key",
            authenticationTag: bytes(0x33)
        )
        let foreignCapability = try existingBackup(
            sourceBinding: foreignCapabilityBinding,
            sourceRootIdentity: source,
            destination: destination,
            name: "c-foreign-capability.backup",
            inode: 302,
            createdAt: try timestamp(800),
            tagByte: 0xA3
        )
        let retentionPolicy = try basePolicy(retention: BackupRetentionPolicy(maximumCount: 1))
        let fixture = try makePlanningFixture(
            policy: retentionPolicy,
            sourceTree: base.sourceTree,
            destinationIdentity: destination,
            parentDirectoryIdentity: destination,
            managedBackups: [owned, foreignSeries, foreignCapability]
        )

        XCTAssertEqual(fixture.plan.retentionValidation.existingBackups.count, 3)
        XCTAssertEqual(fixture.plan.retentionValidation.plannedRemovalNames, [owned.name])
        XCTAssertEqual(fixture.plan.steps.count, 2)

        assertInvalidObservation(
            try BackupPlanner(policy: retentionPolicy).plan(
                replacingRequest(
                    fixture.request,
                    managedBackups: [foreignSeries, owned, foreignCapability]
                )
            )
        )

        let tooOld = try existingBackup(
            sourceBinding: base.sourceBinding,
            sourceRootIdentity: source,
            destination: destination,
            name: "too-old.backup",
            inode: 303,
            createdAt: try timestamp(799),
            tagByte: 0xA4
        )
        assertInvalidObservation(
            try BackupPlanner(policy: retentionPolicy).plan(
                replacingRequest(fixture.request, managedBackups: [tooOld])
            )
        )

        let future = try existingBackup(
            sourceBinding: base.sourceBinding,
            sourceRootIdentity: source,
            destination: destination,
            name: "future.backup",
            inode: 304,
            createdAt: try timestamp(1_001),
            tagByte: 0xA5
        )
        assertInvalidObservation(
            try BackupPlanner(policy: retentionPolicy).plan(
                replacingRequest(fixture.request, managedBackups: [future])
            )
        )
    }

    func testQuarantineRecoveryUsesFreshMountDeviceAndPersistentIdentity() throws {
        let fixture = try makeQuarantineTargetFixture()
        let remountedContainer = replacing(fixture.container, device: 55)
        let remountedRoot = replacing(fixture.postRenameTree.rootIdentity, device: 55)
        let remountedTree = BackupTreeSnapshot(rootIdentity: remountedRoot, metadataRequirements: .all)

        XCTAssertTrue(
            try fixture.quarantinedTarget.matchesAuthenticatedRemainingQuarantineTree(
                remountedTree,
                observedFreshQuarantineContainerIdentity: remountedContainer
            )
        )
        XCTAssertFalse(
            try fixture.quarantinedTarget.matchesAuthenticatedRemainingQuarantineTree(
                BackupTreeSnapshot(
                    rootIdentity: replacing(remountedRoot, device: 56),
                    metadataRequirements: .all
                ),
                observedFreshQuarantineContainerIdentity: remountedContainer
            )
        )
        XCTAssertFalse(
            try fixture.quarantinedTarget.matchesAuthenticatedRemainingQuarantineTree(
                BackupTreeSnapshot(
                    rootIdentity: replacing(
                        remountedRoot,
                        generation: remountedRoot.generation.rawValue + 1
                    ),
                    metadataRequirements: .all
                ),
                observedFreshQuarantineContainerIdentity: remountedContainer
            )
        )
    }

    func testDeletionManifestIsPostorderWithExactDirectoryAndHardlinkCounts() throws {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let root = try item(volume: volume, inode: 1, kind: .directory, linkCount: 3, charge: 1)
        let directory = try item(volume: volume, inode: 2, kind: .directory, linkCount: 2, charge: 1)
        let hardlink = try item(volume: volume, inode: 3, linkCount: 2, size: 4, charge: 4)
        let tree = BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("dir"), identity: directory),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("dir/a"), identity: hardlink),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("dir/b"), identity: hardlink)
            ]
        )
        let context = try makeTargetContext(tree: tree, name: "old.backup")
        let postRenameTree = replacingRootChangeTime(in: tree, with: try timestamp(101))
        let manifest = try deletionManifest(
            tree: postRenameTree,
            rootName: "quarantine",
            rootParent: context.container.stableNodeIdentity
        )
        let target = try BackupTransactionJournalTarget(
            originalPath: try boundPath(name: "old.backup", identity: tree.rootIdentity),
            quarantineName: "quarantine",
            quarantineContainerIdentity: context.container.stableNodeIdentity,
            provenance: context.provenance,
            preRenameTree: tree,
            postRenameTree: postRenameTree,
            deletionManifest: manifest,
            deletedManifestEntryCount: 0
        )

        XCTAssertEqual(target.deletionManifest.map(\.relativePath?.rawValue), ["dir/a", "dir/b", "dir", nil])
        XCTAssertEqual(target.deletionManifest.map(\.expectedLinkCountBeforeDeletion), [2, 1, 2, 2])
        XCTAssertEqual(
            target.deletionManifest.map(\.expectedDirectChildCountBeforeDeletion),
            [nil, nil, 0, 0]
        )
    }

    func testDeletionManifestRejectsIndependentIdentityParentAndTopologyMutations() throws {
        let fixture = try makeQuarantineTargetFixture()
        let original = try XCTUnwrap(fixture.quarantinedTarget.deletionManifest.first)
        let wrongIdentity = try BackupJournalDeletionManifestEntry(
            relativePath: original.relativePath,
            parentRelativePath: original.parentRelativePath,
            name: original.name,
            expectedParentIdentity: original.expectedParentIdentity,
            expectedIdentity: replacing(original.expectedIdentity, contentSeed: 0xEF),
            expectedLinkCountBeforeDeletion: original.expectedLinkCountBeforeDeletion,
            expectedDirectChildCountBeforeDeletion: original.expectedDirectChildCountBeforeDeletion
        )
        assertInvalidObservation(
            try replacingQuarantineTarget(fixture.quarantinedTarget, manifest: [wrongIdentity])
        )

        let wrongParent = try BackupJournalDeletionManifestEntry(
            relativePath: original.relativePath,
            parentRelativePath: original.parentRelativePath,
            name: original.name,
            expectedParentIdentity: stableIdentity(
                volume: fixture.container.persistentVolumeIdentity,
                inode: fixture.container.inode + 1,
                generation: fixture.container.generation.rawValue
            ),
            expectedIdentity: original.expectedIdentity,
            expectedLinkCountBeforeDeletion: original.expectedLinkCountBeforeDeletion,
            expectedDirectChildCountBeforeDeletion: original.expectedDirectChildCountBeforeDeletion
        )
        assertInvalidObservation(
            try replacingQuarantineTarget(fixture.quarantinedTarget, manifest: [wrongParent])
        )

        assertInvalidObservation(
            try replacingQuarantineTarget(fixture.quarantinedTarget, manifest: [])
        )
    }

    func testWriteAheadUnlinkRequiresExactInFlightEntryAndMonotonicSuccessor() throws {
        let fixture = try makeQuarantineTargetFixture()
        let entry = try XCTUnwrap(fixture.quarantinedTarget.deletionManifest.first)
        let parent = fixture.container
        let withoutIntent = try BackupDeletionManifestReplayState(
            authenticatedManifest: fixture.quarantinedTarget.deletionManifest,
            authenticatedDeletedManifestEntryCount: 0,
            authenticatedInFlightManifestEntryIndex: nil
        )
        XCTAssertEqual(
            entry.replayDisposition(
                manifestEntryIndex: 0,
                authenticatedState: withoutIntent,
                observedFreshRootDevice: parent.device,
                observedParentIdentity: parent,
                observedNameUTF8Bytes: entry.nameUTF8Bytes,
                observedIdentity: fixture.postRenameTree.rootIdentity,
                observedDirectChildCount: nil
            ),
            .reject
        )

        let withIntent = try BackupDeletionManifestReplayState(
            authenticatedManifest: fixture.quarantinedTarget.deletionManifest,
            authenticatedDeletedManifestEntryCount: 0,
            authenticatedInFlightManifestEntryIndex: 0
        )
        XCTAssertEqual(
            entry.replayDisposition(
                manifestEntryIndex: 0,
                authenticatedState: withIntent,
                observedFreshRootDevice: parent.device,
                observedParentIdentity: parent,
                observedNameUTF8Bytes: entry.nameUTF8Bytes,
                observedIdentity: fixture.postRenameTree.rootIdentity,
                observedDirectChildCount: nil
            ),
            .unlinkIdentityMatchedEntry
        )
        XCTAssertEqual(
            entry.replayDisposition(
                manifestEntryIndex: 0,
                authenticatedState: withIntent,
                observedFreshRootDevice: parent.device,
                observedParentIdentity: parent,
                observedNameUTF8Bytes: entry.nameUTF8Bytes,
                observedIdentity: nil,
                observedDirectChildCount: nil
            ),
            .advanceDurableProgressForProvenAbsentInFlightEntry
        )
        XCTAssertTrue(
            try BackupDeletionProgressAuthorization.authorizesDurableSuccessor(
                priorManifest: fixture.quarantinedTarget.deletionManifest,
                priorDeletedManifestEntryCount: 0,
                priorInFlightManifestEntryIndex: 0,
                successorManifest: fixture.quarantinedTarget.deletionManifest,
                successorDeletedManifestEntryCount: 1,
                successorInFlightManifestEntryIndex: nil
            )
        )
        XCTAssertFalse(
            try BackupDeletionProgressAuthorization.authorizesDurableSuccessor(
                priorManifest: fixture.quarantinedTarget.deletionManifest,
                priorDeletedManifestEntryCount: 0,
                priorInFlightManifestEntryIndex: nil,
                successorManifest: fixture.quarantinedTarget.deletionManifest,
                successorDeletedManifestEntryCount: 1,
                successorInFlightManifestEntryIndex: nil
            )
        )
    }

    func testHardlinkDeletionReplayRequiresDecrementedCountButAllowsPriorUnlinkCTime() throws {
        let tree = try hardlinkSourceTree()
        let context = try makeTargetContext(tree: tree, name: "old.backup")
        let postRenameTree = replacingRootChangeTime(in: tree, with: try timestamp(101))
        let manifest = try deletionManifest(
            tree: postRenameTree,
            rootName: "quarantine",
            rootParent: context.container.stableNodeIdentity
        )
        let second = manifest[1]
        let replay = try BackupDeletionManifestReplayState(
            authenticatedManifest: manifest,
            authenticatedDeletedManifestEntryCount: 1,
            authenticatedInFlightManifestEntryIndex: 1
        )
        let changedCTime = replacing(
            tree.descendants[1].identity,
            linkCount: 1,
            changeTime: try timestamp(999)
        )

        XCTAssertEqual(
            second.replayDisposition(
                manifestEntryIndex: 1,
                authenticatedState: replay,
                observedFreshRootDevice: postRenameTree.rootIdentity.device,
                observedParentIdentity: postRenameTree.rootIdentity,
                observedNameUTF8Bytes: second.nameUTF8Bytes,
                observedIdentity: changedCTime,
                observedDirectChildCount: nil
            ),
            .unlinkIdentityMatchedEntry
        )
        for wrong in [
            replacing(changedCTime, linkCount: 2),
            replacing(changedCTime, inode: changedCTime.inode + 1, generation: changedCTime.generation.rawValue + 1)
        ] {
            XCTAssertEqual(
                second.replayDisposition(
                    manifestEntryIndex: 1,
                    authenticatedState: replay,
                    observedFreshRootDevice: postRenameTree.rootIdentity.device,
                    observedParentIdentity: postRenameTree.rootIdentity,
                    observedNameUTF8Bytes: second.nameUTF8Bytes,
                    observedIdentity: wrong,
                    observedDirectChildCount: nil
                ),
                .reject
            )
        }
    }

    func testDeletionProgressRequiresSeparateAdvanceAndNextWriteAheadTransitions() throws {
        let tree = try hardlinkSourceTree()
        let context = try makeTargetContext(tree: tree, name: "old.backup")
        let manifest = try deletionManifest(
            tree: replacingRootChangeTime(in: tree, with: try timestamp(101)),
            rootName: "quarantine",
            rootParent: context.container.stableNodeIdentity
        )

        XCTAssertTrue(
            try BackupDeletionProgressAuthorization.authorizesNextWriteAheadEntry(
                priorManifest: manifest,
                priorDeletedManifestEntryCount: 0,
                priorInFlightManifestEntryIndex: nil,
                successorManifest: manifest,
                successorDeletedManifestEntryCount: 0,
                successorInFlightManifestEntryIndex: 0
            )
        )
        XCTAssertFalse(
            try BackupDeletionProgressAuthorization.authorizesNextWriteAheadEntry(
                priorManifest: manifest,
                priorDeletedManifestEntryCount: 0,
                priorInFlightManifestEntryIndex: 0,
                successorManifest: manifest,
                successorDeletedManifestEntryCount: 0,
                successorInFlightManifestEntryIndex: 0
            )
        )
        XCTAssertTrue(
            try BackupDeletionProgressAuthorization.authorizesDurableSuccessor(
                priorManifest: manifest,
                priorDeletedManifestEntryCount: 0,
                priorInFlightManifestEntryIndex: 0,
                successorManifest: manifest,
                successorDeletedManifestEntryCount: 1,
                successorInFlightManifestEntryIndex: nil
            )
        )
        XCTAssertFalse(
            try BackupDeletionProgressAuthorization.authorizesDurableSuccessor(
                priorManifest: manifest,
                priorDeletedManifestEntryCount: 0,
                priorInFlightManifestEntryIndex: 0,
                successorManifest: manifest,
                successorDeletedManifestEntryCount: 1,
                successorInFlightManifestEntryIndex: 1
            )
        )
        XCTAssertTrue(
            try BackupDeletionProgressAuthorization.authorizesNextWriteAheadEntry(
                priorManifest: manifest,
                priorDeletedManifestEntryCount: 1,
                priorInFlightManifestEntryIndex: nil,
                successorManifest: manifest,
                successorDeletedManifestEntryCount: 1,
                successorInFlightManifestEntryIndex: 1
            )
        )
        XCTAssertFalse(
            try BackupDeletionProgressAuthorization.authorizesNextWriteAheadEntry(
                priorManifest: manifest,
                priorDeletedManifestEntryCount: 1,
                priorInFlightManifestEntryIndex: nil,
                successorManifest: manifest,
                successorDeletedManifestEntryCount: 2,
                successorInFlightManifestEntryIndex: 2
            )
        )
    }

    func testManifestUInt64InputsRejectWithoutTrappingOrWrapping() throws {
        let fixture = try makeQuarantineTargetFixture()
        let manifest = fixture.quarantinedTarget.deletionManifest

        XCTAssertThrowsError(
            try BackupDeletionManifestReplayState(
                authenticatedManifest: manifest,
                authenticatedDeletedManifestEntryCount: UInt64.max,
                authenticatedInFlightManifestEntryIndex: UInt64.max
            )
        ) { error in
            guard case .invalidObservation = error as? BackupPolicyError else {
                return XCTFail("Expected invalidObservation, got \(error)")
            }
        }
        XCTAssertFalse(
            try BackupDeletionManifestRecovery.matchesAuthenticatedRemainingTree(
                originalTree: fixture.postRenameTree,
                manifest: manifest,
                deletedManifestEntryCount: UInt64.max,
                inFlightManifestEntryIndex: UInt64.max,
                observedRemainingTree: fixture.postRenameTree
            )
        )
        let replay = try BackupDeletionManifestReplayState(
            authenticatedManifest: manifest,
            authenticatedDeletedManifestEntryCount: 0,
            authenticatedInFlightManifestEntryIndex: 0
        )
        XCTAssertEqual(
            manifest[0].replayDisposition(
                manifestEntryIndex: UInt64.max,
                authenticatedState: replay,
                observedFreshRootDevice: fixture.container.device,
                observedParentIdentity: fixture.container,
                observedNameUTF8Bytes: manifest[0].nameUTF8Bytes,
                observedIdentity: fixture.postRenameTree.rootIdentity,
                observedDirectChildCount: nil
            ),
            .reject
        )
    }

    func testStagedConstructionReplayBindsOnlyExactInFlightSlot() throws {
        let sourceTree = try directorySourceTree()
        let fixture = try makePlanningFixture(sourceTree: sourceTree)
        let stagedRoot = try copiedIdentity(
            sourceTree.rootIdentity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 100
        )
        let manifest = try BackupStagedConstructionManifest.entries(for: sourceTree)
        let record = try journalRecord(
            fixture: fixture,
            kind: .stageConstructionIntent,
            sequence: 2,
            previousTag: bytes(0x20),
            stagedConstructionManifest: manifest,
            stagedConstructionInFlightIndex: 0,
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        let capability = try XCTUnwrap(fixture.request.parentMutationCapability)

        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 0,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedRoot,
                observedNameUTF8Bytes: manifest[0].nameUTF8Bytes,
                observedIdentity: nil
            ),
            .createMissingInFlightEntry
        )
        let observed = try copiedIdentity(
            sourceTree.descendants[0].identity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 101
        )
        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 0,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedRoot,
                observedNameUTF8Bytes: manifest[0].nameUTF8Bytes,
                observedIdentity: observed
            ),
            .bindObservedInFlightEntryIdentity(observed.stableNodeIdentity)
        )
        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 0,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedRoot,
                observedNameUTF8Bytes: manifest[0].nameUTF8Bytes,
                observedIdentity: replacing(observed, device: observed.device + 1)
            ),
            .reject
        )
    }

    func testMultiEntryConstructionReplayRejectsWrongIndexParentAndName() throws {
        let sourceTree = try nestedDirectorySourceTree()
        let fixture = try makePlanningFixture(sourceTree: sourceTree)
        let stagedRoot = try copiedIdentity(
            sourceTree.rootIdentity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 100
        )
        let stagedDirectory = try copiedIdentity(
            sourceTree.descendants[0].identity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 101
        )
        let manifest = try BackupStagedConstructionManifest.entries(for: sourceTree)
        let record = try journalRecord(
            fixture: fixture,
            kind: .stageConstructionIntent,
            sequence: 4,
            previousTag: bytes(0x20),
            stagedConstructionManifest: manifest,
            stagedConstructedNodeIdentities: [stagedDirectory.stableNodeIdentity],
            stagedConstructionInFlightIndex: 1,
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        let capability = try XCTUnwrap(fixture.request.parentMutationCapability)

        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 1,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedDirectory,
                observedNameUTF8Bytes: manifest[1].nameUTF8Bytes,
                observedIdentity: nil
            ),
            .createMissingInFlightEntry
        )
        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 0,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedRoot,
                observedNameUTF8Bytes: manifest[0].nameUTF8Bytes,
                observedIdentity: nil
            ),
            .reject
        )
        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 1,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedRoot,
                observedNameUTF8Bytes: manifest[1].nameUTF8Bytes,
                observedIdentity: nil
            ),
            .reject
        )
        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 1,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedDirectory,
                observedNameUTF8Bytes: manifest[0].nameUTF8Bytes,
                observedIdentity: nil
            ),
            .reject
        )
    }

    func testPreparedReplayBindsOnlyFreshEmptyRootUnderExclusiveCapability() throws {
        let fixture = try makePlanningFixture()
        let prepared = try journalRecord(fixture: fixture, kind: .prepared, sequence: 0, previousTag: nil)
        let capability = try XCTUnwrap(fixture.request.parentMutationCapability)
        let destination = fixture.destinationIdentity

        XCTAssertEqual(
            prepared.stagingRootIntentRecoveryDisposition(
                parentMutationCapability: capability,
                observedFreshDestinationDirectoryIdentity: destination,
                observedStagingNameUTF8Bytes: Array(".stage".utf8),
                observedStagingRootIdentity: nil,
                observedStagingRootDirectChildCount: nil
            ),
            .createMissingRoot
        )
        let emptyRoot = try item(
            volume: destination.persistentVolumeIdentity,
            device: destination.device,
            inode: 100,
            size: 0,
            charge: 0
        )
        XCTAssertEqual(
            prepared.stagingRootIntentRecoveryDisposition(
                parentMutationCapability: capability,
                observedFreshDestinationDirectoryIdentity: destination,
                observedStagingNameUTF8Bytes: Array(".stage".utf8),
                observedStagingRootIdentity: emptyRoot,
                observedStagingRootDirectChildCount: nil
            ),
            .bindObservedRootIdentity(emptyRoot.stableNodeIdentity)
        )
        let conditionalCapability = try BackupParentMutationCapability(
            capabilityIdentifier: bytes(0x78),
            destinationDirectoryIdentity: destination.stableNodeIdentity,
            semantics: .descriptorRelativeIdentityConditional
        )
        XCTAssertEqual(
            prepared.stagingRootIntentRecoveryDisposition(
                parentMutationCapability: conditionalCapability,
                observedFreshDestinationDirectoryIdentity: destination,
                observedStagingNameUTF8Bytes: Array(".stage".utf8),
                observedStagingRootIdentity: nil,
                observedStagingRootDirectChildCount: nil
            ),
            .reject
        )
        XCTAssertEqual(
            prepared.stagingRootIntentRecoveryDisposition(
                parentMutationCapability: capability,
                observedFreshDestinationDirectoryIdentity: destination,
                observedStagingNameUTF8Bytes: Array("other".utf8),
                observedStagingRootIdentity: nil,
                observedStagingRootDirectChildCount: nil
            ),
            .reject
        )
        XCTAssertEqual(
            prepared.stagingRootIntentRecoveryDisposition(
                parentMutationCapability: capability,
                observedFreshDestinationDirectoryIdentity: destination,
                observedStagingNameUTF8Bytes: Array(".stage".utf8),
                observedStagingRootIdentity: replacing(emptyRoot, contentSeed: 0xEE),
                observedStagingRootDirectChildCount: 1
            ),
            .reject
        )
    }

    func testPreparedReplayBindsEmptyDirectoryButRejectsPopulatedDirectory() throws {
        let sourceTree = try directorySourceTree()
        let fixture = try makePlanningFixture(sourceTree: sourceTree)
        let prepared = try journalRecord(fixture: fixture, kind: .prepared, sequence: 0, previousTag: nil)
        let capability = try XCTUnwrap(fixture.request.parentMutationCapability)
        let destination = fixture.destinationIdentity
        let stagingDirectory = try copiedIdentity(
            sourceTree.rootIdentity,
            volume: destination.persistentVolumeIdentity,
            device: destination.device,
            inode: 100
        )

        XCTAssertEqual(
            prepared.stagingRootIntentRecoveryDisposition(
                parentMutationCapability: capability,
                observedFreshDestinationDirectoryIdentity: destination,
                observedStagingNameUTF8Bytes: Array(".stage".utf8),
                observedStagingRootIdentity: stagingDirectory,
                observedStagingRootDirectChildCount: 0
            ),
            .bindObservedRootIdentity(stagingDirectory.stableNodeIdentity)
        )
        XCTAssertEqual(
            prepared.stagingRootIntentRecoveryDisposition(
                parentMutationCapability: capability,
                observedFreshDestinationDirectoryIdentity: destination,
                observedStagingNameUTF8Bytes: Array(".stage".utf8),
                observedStagingRootIdentity: stagingDirectory,
                observedStagingRootDirectChildCount: 1
            ),
            .reject
        )
    }

    func testStagedHardlinkReplayReusesPriorConstructedNodeWithExactLinkCount() throws {
        let sourceTree = try hardlinkSourceTree()
        let fixture = try makePlanningFixture(sourceTree: sourceTree)
        let stagedRoot = try copiedIdentity(
            sourceTree.rootIdentity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 100
        )
        let stagedHardlink = try copiedIdentity(
            sourceTree.descendants[0].identity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 101
        )
        let manifest = try BackupStagedConstructionManifest.entries(for: sourceTree)
        let record = try journalRecord(
            fixture: fixture,
            kind: .stageConstructionIntent,
            sequence: 4,
            previousTag: bytes(0x22),
            stagedConstructionManifest: manifest,
            stagedConstructedNodeIdentities: [stagedHardlink.stableNodeIdentity],
            stagedConstructionInFlightIndex: 1,
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        let capability = try XCTUnwrap(fixture.request.parentMutationCapability)

        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 1,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedRoot,
                observedNameUTF8Bytes: manifest[1].nameUTF8Bytes,
                observedIdentity: nil
            ),
            .createMissingInFlightHardlink(stagedHardlink.stableNodeIdentity)
        )
        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 1,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedRoot,
                observedNameUTF8Bytes: manifest[1].nameUTF8Bytes,
                observedIdentity: replacing(stagedHardlink, linkCount: 2)
            ),
            .bindObservedInFlightEntryIdentity(stagedHardlink.stableNodeIdentity)
        )
        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 1,
                parentMutationCapability: capability,
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedRoot,
                observedNameUTF8Bytes: manifest[1].nameUTF8Bytes,
                observedIdentity: replacing(stagedHardlink, linkCount: 1)
            ),
            .reject
        )
    }

    func testStagedHardlinkReplayRejectsDifferentInodeAtRightLinkCount() throws {
        let sourceTree = try hardlinkSourceTree()
        let fixture = try makePlanningFixture(sourceTree: sourceTree)
        let stagedRoot = try copiedIdentity(
            sourceTree.rootIdentity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 100
        )
        let firstAlias = try copiedIdentity(
            sourceTree.descendants[0].identity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 101
        )
        let differentInode = replacing(firstAlias, inode: 102, generation: 1_102, linkCount: 2)
        let manifest = try BackupStagedConstructionManifest.entries(for: sourceTree)
        let record = try journalRecord(
            fixture: fixture,
            kind: .stageConstructionIntent,
            sequence: 4,
            previousTag: bytes(0x20),
            stagedConstructionManifest: manifest,
            stagedConstructedNodeIdentities: [firstAlias.stableNodeIdentity],
            stagedConstructionInFlightIndex: 1,
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )

        XCTAssertEqual(
            record.stagedConstructionEntryReplayDisposition(
                manifestEntryIndex: 1,
                parentMutationCapability: try XCTUnwrap(fixture.request.parentMutationCapability),
                observedFreshStagingRootIdentity: stagedRoot,
                observedFreshParentIdentity: stagedRoot,
                observedNameUTF8Bytes: manifest[1].nameUTF8Bytes,
                observedIdentity: differentInode
            ),
            .reject
        )
    }

    func testPartialConstructionCleanupRequiresCompleteAuthenticatedPrefixAndWriteAheadManifest() throws {
        let sourceTree = try directorySourceTree()
        let fixture = try makePlanningFixture(sourceTree: sourceTree)
        let stagedRoot = try copiedIdentity(
            sourceTree.rootIdentity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 100
        )
        let stagedChild = try copiedIdentity(
            sourceTree.descendants[0].identity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 101
        )
        let manifest = try BackupStagedConstructionManifest.entries(for: sourceTree)
        let progress = try journalRecord(
            fixture: fixture,
            kind: .stageConstructionProgress,
            sequence: 3,
            previousTag: bytes(0x21),
            stagedConstructionManifest: manifest,
            stagedConstructedNodeIdentities: [stagedChild.stableNodeIdentity],
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        let partialTree = BackupTreeSnapshot(
            rootIdentity: stagedRoot,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(
                    relativePath: sourceTree.descendants[0].relativePath,
                    identity: stagedChild
                )
            ]
        )

        XCTAssertEqual(
            try progress.constructionRecoveryRemovalScope(forObservedStagingTree: partialTree),
            .constructionProgressRequiresWriteAheadManifest
        )
        XCTAssertEqual(
            try progress.constructionRecoveryRemovalScope(
                forObservedStagingTree: BackupTreeSnapshot(
                    rootIdentity: stagedRoot,
                    metadataRequirements: .all
                )
            ),
            .reject
        )

        let deletion = try deletionManifest(
            tree: partialTree,
            rootName: ".stage",
            rootParent: fixture.destinationIdentity.stableNodeIdentity
        )
        let deletionIntent = try journalRecord(
            fixture: fixture,
            kind: .stageDeletionIntent,
            sequence: 4,
            previousTag: bytes(0x22),
            stagedTree: partialTree,
            stagedDeletionManifest: deletion,
            stagedDeletionInFlightIndex: 0,
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        XCTAssertTrue(try progress.authorizesSemanticDirectSuccessor(deletionIntent))
        XCTAssertEqual(
            try deletionIntent.recoveryRemovalScope(forObservedStagingTree: partialTree),
            .authenticatedManifestProgress
        )
    }

    func testPartialConstructionCleanupRejectsSameCountPathKindIdentityDeviceAndSuccessorDrift() throws {
        let sourceTree = try nestedDirectorySourceTree()
        let fixture = try makePlanningFixture(sourceTree: sourceTree)
        let stagedRoot = try copiedIdentity(
            sourceTree.rootIdentity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 100
        )
        let stagedDirectory = try copiedIdentity(
            sourceTree.descendants[0].identity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 101
        )
        let manifest = try BackupStagedConstructionManifest.entries(for: sourceTree)
        let progress = try journalRecord(
            fixture: fixture,
            kind: .stageConstructionProgress,
            sequence: 3,
            previousTag: bytes(0x21),
            stagedConstructionManifest: manifest,
            stagedConstructedNodeIdentities: [stagedDirectory.stableNodeIdentity],
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        let valid = BackupTreeSnapshot(
            rootIdentity: stagedRoot,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: sourceTree.descendants[0].relativePath, identity: stagedDirectory)
            ]
        )
        XCTAssertEqual(
            try progress.constructionRecoveryRemovalScope(forObservedStagingTree: valid),
            .constructionProgressRequiresWriteAheadManifest
        )

        let wrongPath = BackupTreeSnapshot(
            rootIdentity: stagedRoot,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("other"), identity: stagedDirectory)
            ]
        )
        let wrongKindIdentity = replacing(stagedDirectory, kind: .regularFile, linkCount: 1)
        let wrongKind = BackupTreeSnapshot(
            rootIdentity: stagedRoot,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: sourceTree.descendants[0].relativePath, identity: wrongKindIdentity)
            ]
        )
        let wrongIdentityValue = replacing(
            stagedDirectory,
            inode: stagedDirectory.inode + 1,
            generation: stagedDirectory.generation.rawValue + 1
        )
        let wrongIdentity = BackupTreeSnapshot(
            rootIdentity: stagedRoot,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: sourceTree.descendants[0].relativePath, identity: wrongIdentityValue)
            ]
        )
        let wrongDeviceValue = replacing(stagedDirectory, device: stagedDirectory.device + 1)
        let wrongDevice = BackupTreeSnapshot(
            rootIdentity: stagedRoot,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: sourceTree.descendants[0].relativePath, identity: wrongDeviceValue)
            ]
        )
        for drifted in [wrongPath, wrongKind, wrongIdentity] {
            XCTAssertEqual(try progress.constructionRecoveryRemovalScope(forObservedStagingTree: drifted), .reject)
        }
        assertInvalidObservation(try progress.constructionRecoveryRemovalScope(forObservedStagingTree: wrongDevice))

        let deletion = try deletionManifest(
            tree: valid,
            rootName: ".stage",
            rootParent: fixture.destinationIdentity.stableNodeIdentity
        )
        let legal = try journalRecord(
            fixture: fixture,
            kind: .stageDeletionIntent,
            sequence: 4,
            previousTag: bytes(0x22),
            stagedTree: valid,
            stagedDeletionManifest: deletion,
            stagedDeletionInFlightIndex: 0,
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        XCTAssertTrue(try progress.authorizesSemanticDirectSuccessor(legal))

        let illegalTree = BackupTreeSnapshot(
            rootIdentity: stagedRoot,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("other"), identity: stagedDirectory)
            ]
        )
        let illegalDeletion = try deletionManifest(
            tree: illegalTree,
            rootName: ".stage",
            rootParent: fixture.destinationIdentity.stableNodeIdentity
        )
        let illegal = try journalRecord(
            fixture: fixture,
            kind: .stageDeletionIntent,
            sequence: 4,
            previousTag: bytes(0x22),
            stagedTree: illegalTree,
            stagedDeletionManifest: illegalDeletion,
            stagedDeletionInFlightIndex: 0,
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        XCTAssertFalse(try progress.authorizesSemanticDirectSuccessor(illegal))
    }

    func testRollbackAnchorRequiresExactTagChainAndSemanticDirectSuccessor() throws {
        let fixture = try makePlanningFixture()
        let predecessorRecord = try journalRecord(
            fixture: fixture,
            kind: .prepared,
            sequence: 0,
            previousTag: nil
        )
        let stagedRoot = try copiedIdentity(
            fixture.sourceTree.rootIdentity,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            inode: 100
        )
        let predecessorTag = bytes(0x41)
        let successorRecord = try journalRecord(
            fixture: fixture,
            kind: .stageIdentityBound,
            sequence: 1,
            previousTag: predecessorTag,
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        let predecessor = try BackupAuthenticatedTransactionJournalRecord(
            record: predecessorRecord,
            keyIdentifier: "key",
            authenticationTag: predecessorTag
        )
        let successor = try BackupAuthenticatedTransactionJournalRecord(
            record: successorRecord,
            keyIdentifier: "key",
            authenticationTag: bytes(0x42)
        )
        let anchor = try BackupJournalSequenceAnchor(
            sequenceAnchorIdentifier: anchorIdentifier,
            transactionSequenceNumber: 1,
            journalSequenceNumber: 0,
            journalRecordKind: .prepared,
            journalAuthenticationTag: predecessorTag
        )

        XCTAssertEqual(anchor.recoveryDisposition(forAuthenticatedDurableJournal: predecessor), .exactMatch)
        XCTAssertEqual(anchor.recoveryDisposition(forAuthenticatedDurableJournal: successor), .reject)
        XCTAssertEqual(
            anchor.recoveryDisposition(
                forAuthenticatedDurableJournal: successor,
                retainedAuthenticatedPredecessor: predecessor
            ),
            .advanceAtomicallyToSemanticDirectSuccessor
        )
        let advanced = try anchor.advancingToAuthenticatedDurableSemanticDirectSuccessor(
            successor,
            retainedAuthenticatedPredecessor: predecessor
        )
        XCTAssertEqual(advanced.journalSequenceNumber, 1)
        XCTAssertEqual(advanced.journalRecordKind, .stageIdentityBound)
        XCTAssertEqual(advanced.journalAuthenticationTag, successor.authenticationTag)

        let wrongChainRecord = try journalRecord(
            fixture: fixture,
            kind: .stageIdentityBound,
            sequence: 1,
            previousTag: bytes(0x43),
            stagingRootIdentity: stagedRoot.stableNodeIdentity
        )
        let wrongChainSuccessor = try BackupAuthenticatedTransactionJournalRecord(
            record: wrongChainRecord,
            keyIdentifier: "key",
            authenticationTag: bytes(0x42)
        )
        XCTAssertEqual(
            anchor.recoveryDisposition(
                forAuthenticatedDurableJournal: wrongChainSuccessor,
                retainedAuthenticatedPredecessor: predecessor
            ),
            .reject
        )
    }

    func testRollbackAnchorRejectsCorrectlyChainedIllegalSemanticSuccessor() throws {
        let fixture = try makePlanningFixture()
        let predecessorTag = bytes(0x41)
        let predecessorRecord = try journalRecord(
            fixture: fixture,
            kind: .prepared,
            sequence: 0,
            previousTag: nil
        )
        let stagedTree = try copiedTree(
            fixture.sourceTree,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            firstInode: 100
        )
        let illegalRecord = try journalRecord(
            fixture: fixture,
            kind: .publicationIntent,
            sequence: 1,
            previousTag: predecessorTag,
            stagedTree: stagedTree,
            stagingRootIdentity: stagedTree.rootIdentity.stableNodeIdentity
        )
        let predecessor = try BackupAuthenticatedTransactionJournalRecord(
            record: predecessorRecord,
            keyIdentifier: "key",
            authenticationTag: predecessorTag
        )
        let illegal = try BackupAuthenticatedTransactionJournalRecord(
            record: illegalRecord,
            keyIdentifier: "key",
            authenticationTag: bytes(0x42)
        )
        let anchor = try BackupJournalSequenceAnchor(
            sequenceAnchorIdentifier: anchorIdentifier,
            transactionSequenceNumber: 1,
            journalSequenceNumber: 0,
            journalRecordKind: .prepared,
            journalAuthenticationTag: predecessorTag
        )

        XCTAssertEqual(
            anchor.recoveryDisposition(
                forAuthenticatedDurableJournal: illegal,
                retainedAuthenticatedPredecessor: predecessor
            ),
            .reject
        )
        assertInvalidObservation(
            try anchor.advancingToAuthenticatedDurableSemanticDirectSuccessor(
                illegal,
                retainedAuthenticatedPredecessor: predecessor
            )
        )
    }

    func testCommittedAnchorAllowsOnlyImmediatePreparedRolloverAndRejectsOverflow() throws {
        let tag = bytes(0x51)
        let anchor = try BackupJournalSequenceAnchor(
            sequenceAnchorIdentifier: anchorIdentifier,
            transactionSequenceNumber: 7,
            journalSequenceNumber: 12,
            journalRecordKind: .committed,
            journalAuthenticationTag: tag
        )
        XCTAssertEqual(
            anchor.recoveryDisposition(
                recordKind: .prepared,
                sequenceAnchorIdentifier: anchorIdentifier,
                transactionSequenceNumber: 8,
                journalSequenceNumber: 0,
                previousJournalAuthenticationTag: tag,
                journalAuthenticationTag: bytes(0x52)
            ),
            .advanceAtomicallyToPreparedRollover
        )
        XCTAssertEqual(
            anchor.recoveryDisposition(
                recordKind: .prepared,
                sequenceAnchorIdentifier: anchorIdentifier,
                transactionSequenceNumber: 9,
                journalSequenceNumber: 0,
                previousJournalAuthenticationTag: tag,
                journalAuthenticationTag: bytes(0x52)
            ),
            .reject
        )

        let maximumAnchor = try BackupJournalSequenceAnchor(
            sequenceAnchorIdentifier: anchorIdentifier,
            transactionSequenceNumber: UInt64.max,
            journalSequenceNumber: UInt64.max,
            journalRecordKind: .committed,
            journalAuthenticationTag: tag
        )
        XCTAssertFalse(
            maximumAnchor.isDirectSuccessor(
                sequenceAnchorIdentifier: anchorIdentifier,
                transactionSequenceNumber: UInt64.max,
                journalSequenceNumber: 0,
                previousJournalAuthenticationTag: tag
            )
        )
        XCTAssertEqual(
            maximumAnchor.recoveryDisposition(
                recordKind: .prepared,
                sequenceAnchorIdentifier: anchorIdentifier,
                transactionSequenceNumber: 0,
                journalSequenceNumber: 0,
                previousJournalAuthenticationTag: tag,
                journalAuthenticationTag: bytes(0x52)
            ),
            .reject
        )
    }

    func testQuarantineRestoreAcceptsEqualPostRenameCTimeOnlyWithFreshTreeProvenance() throws {
        let fixture = try makeRetentionJournalFixture()
        let published = try journalRecord(
            fixture: fixture.planning,
            kind: .published,
            sequence: 5,
            previousTag: bytes(0x60),
            stagedTree: fixture.stagedTree,
            stagingRootIdentity: fixture.stagedTree.rootIdentity.stableNodeIdentity,
            publicationAuthorizationTime: fixture.publicationTime,
            publicationMonotonicTime: fixture.publicationMonotonic,
            publishedProvenance: fixture.publishedProvenance,
            retentionTargets: [fixture.initialTarget]
        )
        let quarantineIntent = try journalRecord(
            fixture: fixture.planning,
            kind: .quarantineIntent,
            sequence: 6,
            previousTag: bytes(0x61),
            stagedTree: fixture.stagedTree,
            stagingRootIdentity: fixture.stagedTree.rootIdentity.stableNodeIdentity,
            publicationAuthorizationTime: fixture.publicationTime,
            publicationMonotonicTime: fixture.publicationMonotonic,
            publishedProvenance: fixture.publishedProvenance,
            retentionAuthorizationTime: fixture.retentionTime,
            retentionMonotonicTime: fixture.retentionMonotonic,
            retentionTargets: [fixture.intentTarget]
        )
        let quarantined = try journalRecord(
            fixture: fixture.planning,
            kind: .quarantined,
            sequence: 7,
            previousTag: bytes(0x62),
            stagedTree: fixture.stagedTree,
            stagingRootIdentity: fixture.stagedTree.rootIdentity.stableNodeIdentity,
            publicationAuthorizationTime: fixture.publicationTime,
            publicationMonotonicTime: fixture.publicationMonotonic,
            publishedProvenance: fixture.publishedProvenance,
            retentionAuthorizationTime: fixture.retentionTime,
            retentionMonotonicTime: fixture.retentionMonotonic,
            retentionTargets: [fixture.quarantinedTarget]
        )
        let restored = try journalRecord(
            fixture: fixture.planning,
            kind: .committed,
            sequence: 8,
            previousTag: bytes(0x63),
            stagedTree: fixture.stagedTree,
            stagingRootIdentity: fixture.stagedTree.rootIdentity.stableNodeIdentity,
            publicationAuthorizationTime: fixture.publicationTime,
            publicationMonotonicTime: fixture.publicationMonotonic,
            publishedProvenance: fixture.publishedProvenance,
            retentionTargets: [fixture.restoredTarget]
        )

        XCTAssertTrue(try published.authorizesSemanticDirectSuccessor(quarantineIntent))
        XCTAssertTrue(try quarantineIntent.authorizesSemanticDirectSuccessor(quarantined))
        XCTAssertTrue(try quarantined.authorizesSemanticDirectSuccessor(restored))
        XCTAssertEqual(
            fixture.restoredTarget.preRenameTree.rootIdentity.changeTime,
            fixture.quarantinedTarget.postRenameTree?.rootIdentity.changeTime
        )
        XCTAssertNotEqual(
            fixture.restoredTarget.provenance.authenticationTag,
            fixture.quarantinedTarget.provenance.authenticationTag
        )
        XCTAssertEqual(
            fixture.restoredTarget.provenance.provenance.backupTree,
            fixture.restoredTarget.preRenameTree
        )
    }

    func testQuarantineRestoreRejectsProgressStaleProvenanceAndTreeDrift() throws {
        let fixture = try makeRetentionJournalFixture()
        let quarantined = try journalRecord(
            fixture: fixture.planning,
            kind: .quarantined,
            sequence: 7,
            previousTag: bytes(0x62),
            stagedTree: fixture.stagedTree,
            stagingRootIdentity: fixture.stagedTree.rootIdentity.stableNodeIdentity,
            publicationAuthorizationTime: fixture.publicationTime,
            publicationMonotonicTime: fixture.publicationMonotonic,
            publishedProvenance: fixture.publishedProvenance,
            retentionAuthorizationTime: fixture.retentionTime,
            retentionMonotonicTime: fixture.retentionMonotonic,
            retentionTargets: [fixture.quarantinedTarget]
        )
        func committed(_ target: BackupTransactionJournalTarget) throws -> BackupTransactionJournalRecord {
            try journalRecord(
                fixture: fixture.planning,
                kind: .committed,
                sequence: 8,
                previousTag: bytes(0x63),
                stagedTree: fixture.stagedTree,
                stagingRootIdentity: fixture.stagedTree.rootIdentity.stableNodeIdentity,
                publicationAuthorizationTime: fixture.publicationTime,
                publicationMonotonicTime: fixture.publicationMonotonic,
                publishedProvenance: fixture.publishedProvenance,
                retentionTargets: [target]
            )
        }

        let progressedPrior = try replacingQuarantineTarget(
            fixture.quarantinedTarget,
            deletedCount: 0,
            inFlightIndex: 0
        )
        let progressedRecord = try journalRecord(
            fixture: fixture.planning,
            kind: .deletionIntent,
            sequence: 7,
            previousTag: bytes(0x62),
            stagedTree: fixture.stagedTree,
            stagingRootIdentity: fixture.stagedTree.rootIdentity.stableNodeIdentity,
            publicationAuthorizationTime: fixture.publicationTime,
            publicationMonotonicTime: fixture.publicationMonotonic,
            publishedProvenance: fixture.publishedProvenance,
            retentionAuthorizationTime: fixture.retentionTime,
            retentionMonotonicTime: fixture.retentionMonotonic,
            retentionTargets: [progressedPrior]
        )
        XCTAssertFalse(try progressedRecord.authorizesSemanticDirectSuccessor(committed(fixture.restoredTarget)))

        let priorProvenance = fixture.quarantinedTarget.provenance.provenance
        let staleProvenanceRecord = try makeAuthenticatedProvenance(
            sourceBinding: fixture.planning.sourceBinding,
            sourceRootIdentity: priorProvenance.sourceRootIdentity,
            destination: priorProvenance.destinationDirectoryIdentity,
            name: priorProvenance.name,
            tree: fixture.restoredTarget.preRenameTree,
            createdAt: try timestamp(priorProvenance.createdAt.secondsSince1970 - 1),
            transactionByte: priorProvenance.transactionIdentifier[0],
            tagByte: 0xFC
        )
        let staleProvenance = try BackupTransactionJournalTarget(
            originalPath: fixture.restoredTarget.originalPath,
            quarantineName: nil,
            provenance: staleProvenanceRecord,
            preRenameTree: fixture.restoredTarget.preRenameTree,
            postRenameTree: nil,
            deletionManifest: [],
            deletedManifestEntryCount: 0
        )
        XCTAssertFalse(try quarantined.authorizesSemanticDirectSuccessor(committed(staleProvenance)))

        let driftedTree = BackupTreeSnapshot(
            rootIdentity: replacing(fixture.restoredTarget.preRenameTree.rootIdentity, contentSeed: 0xEF),
            metadataRequirements: fixture.restoredTarget.preRenameTree.metadataRequirements,
            descendants: fixture.restoredTarget.preRenameTree.descendants
        )
        let driftedProvenance = try makeAuthenticatedProvenance(
            sourceBinding: fixture.planning.sourceBinding,
            sourceRootIdentity: fixture.restoredTarget.provenance.provenance.sourceRootIdentity,
            destination: fixture.planning.destinationIdentity.stableNodeIdentity,
            name: fixture.restoredTarget.provenance.provenance.name,
            tree: driftedTree,
            createdAt: fixture.restoredTarget.provenance.provenance.createdAt,
            transactionByte: fixture.restoredTarget.provenance.provenance.transactionIdentifier[0],
            tagByte: 0xFD
        )
        let driftedTarget = try BackupTransactionJournalTarget(
            originalPath: try boundPath(name: fixture.restoredTarget.provenance.provenance.name, identity: driftedTree.rootIdentity),
            quarantineName: nil,
            provenance: driftedProvenance,
            preRenameTree: driftedTree,
            postRenameTree: nil,
            deletionManifest: [],
            deletedManifestEntryCount: 0
        )
        XCTAssertFalse(try quarantined.authorizesSemanticDirectSuccessor(committed(driftedTarget)))
    }

    func testTrustedTimeAcceptsExactSkewBoundaryAndRejectsRollbackSessionAndDrift() throws {
        let fixture = try makePlanningFixture(requestTimestamp: try BackupTimestamp(secondsSince1970: 1_000, nanoseconds: 100))
        let stagedTree = try copiedTree(
            fixture.sourceTree,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            firstInode: 100
        )
        let session = bytes(0x70)
        let boundaryTime = try BackupTimestamp(secondsSince1970: 1_300, nanoseconds: 100)
        let valid = try journalRecord(
            fixture: fixture,
            kind: .publicationAuthorized,
            sequence: 4,
            previousTag: bytes(0x71),
            stagedTree: stagedTree,
            stagingRootIdentity: stagedTree.rootIdentity.stableNodeIdentity,
            publicationAuthorizationTime: boundaryTime,
            publicationMonotonicTime: try BackupMonotonicInstant(
                clockSessionIdentifier: session,
                nanoseconds: 10
            )
        )
        XCTAssertEqual(valid.publicationAuthorizationTime, boundaryTime)

        XCTAssertThrowsError(
            try journalRecord(
                fixture: fixture,
                kind: .publicationAuthorized,
                sequence: 4,
                previousTag: bytes(0x71),
                stagedTree: stagedTree,
                stagingRootIdentity: stagedTree.rootIdentity.stableNodeIdentity,
                publicationAuthorizationTime: try BackupTimestamp(
                    secondsSince1970: 1_300,
                    nanoseconds: 101
                ),
                publicationMonotonicTime: try BackupMonotonicInstant(
                    clockSessionIdentifier: session,
                    nanoseconds: 10
                )
            )
        ) { error in
            guard case .invalidObservation = error as? BackupPolicyError else {
                return XCTFail("Expected trusted-time rejection, got \(error)")
            }
        }

        let retention = try makeRetentionJournalFixture()
        XCTAssertThrowsError(
            try journalRecord(
                fixture: retention.planning,
                kind: .quarantineIntent,
                sequence: 6,
                previousTag: bytes(0x72),
                stagedTree: retention.stagedTree,
                stagingRootIdentity: retention.stagedTree.rootIdentity.stableNodeIdentity,
                publicationAuthorizationTime: retention.publicationTime,
                publicationMonotonicTime: retention.publicationMonotonic,
                publishedProvenance: retention.publishedProvenance,
                retentionAuthorizationTime: retention.retentionTime,
                retentionMonotonicTime: try BackupMonotonicInstant(
                    clockSessionIdentifier: bytes(0xFF),
                    nanoseconds: retention.retentionMonotonic.nanoseconds
                ),
                retentionTargets: [retention.intentTarget]
            )
        ) { error in
            guard case .invalidObservation = error as? BackupPolicyError else {
                return XCTFail("Expected clock-session rejection, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try journalRecord(
                fixture: retention.planning,
                kind: .quarantineIntent,
                sequence: 6,
                previousTag: bytes(0x72),
                stagedTree: retention.stagedTree,
                stagingRootIdentity: retention.stagedTree.rootIdentity.stableNodeIdentity,
                publicationAuthorizationTime: retention.publicationTime,
                publicationMonotonicTime: retention.publicationMonotonic,
                publishedProvenance: retention.publishedProvenance,
                retentionAuthorizationTime: retention.publicationTime,
                retentionMonotonicTime: retention.publicationMonotonic,
                retentionTargets: [retention.intentTarget]
            )
        ) { error in
            guard case .invalidObservation = error as? BackupPolicyError else {
                return XCTFail("Expected non-advancing monotonic rejection, got \(error)")
            }
        }

        let exactDriftBoundary = try BackupMonotonicInstant(
            clockSessionIdentifier: retention.publicationMonotonic.clockSessionIdentifier,
            nanoseconds: retention.publicationMonotonic.nanoseconds + 301_000_000_000
        )
        XCTAssertNoThrow(
            try journalRecord(
                fixture: retention.planning,
                kind: .quarantineIntent,
                sequence: 6,
                previousTag: bytes(0x72),
                stagedTree: retention.stagedTree,
                stagingRootIdentity: retention.stagedTree.rootIdentity.stableNodeIdentity,
                publicationAuthorizationTime: retention.publicationTime,
                publicationMonotonicTime: retention.publicationMonotonic,
                publishedProvenance: retention.publishedProvenance,
                retentionAuthorizationTime: retention.retentionTime,
                retentionMonotonicTime: exactDriftBoundary,
                retentionTargets: [retention.intentTarget]
            )
        )
        let excessiveDrift = try BackupMonotonicInstant(
            clockSessionIdentifier: retention.publicationMonotonic.clockSessionIdentifier,
            nanoseconds: exactDriftBoundary.nanoseconds + 1
        )
        assertInvalidObservation(
            try journalRecord(
                fixture: retention.planning,
                kind: .quarantineIntent,
                sequence: 6,
                previousTag: bytes(0x72),
                stagedTree: retention.stagedTree,
                stagingRootIdentity: retention.stagedTree.rootIdentity.stableNodeIdentity,
                publicationAuthorizationTime: retention.publicationTime,
                publicationMonotonicTime: retention.publicationMonotonic,
                publishedProvenance: retention.publishedProvenance,
                retentionAuthorizationTime: retention.retentionTime,
                retentionMonotonicTime: excessiveDrift,
                retentionTargets: [retention.intentTarget]
            )
        )
    }

    func testJournalPublicEncodingAndReservationBoundaries() throws {
        XCTAssertFalse(BackupTransactionJournalFormat.isValidReservationPlan(requiredBytes: 0))
        XCTAssertFalse(BackupTransactionJournalFormat.isValidReservationPlan(requiredBytes: 1))
        XCTAssertTrue(BackupTransactionJournalFormat.isValidReservationPlan(requiredBytes: 2))
        XCTAssertTrue(
            BackupTransactionJournalFormat.isValidReservationPlan(
                requiredBytes: BackupTransactionJournalFormat.maximumReservedBytes
            )
        )
        XCTAssertFalse(
            BackupTransactionJournalFormat.isValidReservationPlan(
                requiredBytes: BackupTransactionJournalFormat.maximumReservedBytes + 2
            )
        )
        XCTAssertTrue(
            BackupTransactionJournalFormat.hasRequiredDurableReservation(
                requiredBytes: 2_048,
                durablyReservedBytes: 2_048
            )
        )
        XCTAssertFalse(
            BackupTransactionJournalFormat.hasRequiredDurableReservation(
                requiredBytes: 2_048,
                durablyReservedBytes: 2_047
            )
        )

        let fixture = try makePlanningFixture(sourceTree: try directorySourceTree())
        XCTAssertTrue(
            BackupTransactionJournalFormat.isValidReservationPlan(
                requiredBytes: fixture.plan.requiredJournalReservationBytes
            )
        )
        XCTAssertTrue(fixture.plan.requiredJournalReservationBytes.isMultiple(of: 2))
        XCTAssertLessThanOrEqual(
            fixture.plan.requiredJournalReservationBytes,
            BackupTransactionJournalFormat.maximumReservedBytes
        )
        let record = try journalRecord(fixture: fixture, kind: .prepared, sequence: 0, previousTag: nil)
        let authenticated = try BackupAuthenticatedTransactionJournalRecord(
            record: record,
            keyIdentifier: "key",
            authenticationTag: bytes(0x92)
        )
        let materialized = try authenticated.encodedData()
        var streamed = Data()
        var largestChunk = 0
        try authenticated.writeEncodedData { chunk in
            largestChunk = max(largestChunk, chunk.count)
            streamed.append(chunk)
        }
        var independentFileBytes = try record.authenticationBytes(keyIdentifier: "key")
        appendField(bytes(0x92), to: &independentFileBytes)
        XCTAssertEqual(streamed, materialized)
        XCTAssertEqual(materialized, independentFileBytes)
        XCTAssertLessThanOrEqual(materialized.count, BackupTransactionJournalFormat.maximumEncodedBytes)
        XCTAssertLessThanOrEqual(materialized.count * 2, fixture.plan.requiredJournalReservationBytes)
        XCTAssertLessThanOrEqual(
            largestChunk,
            BackupTransactionJournalFormat.maximumAuthenticationFieldBytes
        )

        let decoding = BackupTransactionJournalDecodingContract()
        XCTAssertEqual(decoding.maximumEncodedBytes, BackupTransactionJournalFormat.maximumEncodedBytes)
        XCTAssertEqual(
            decoding.maximumFieldBytes,
            BackupTransactionJournalFormat.maximumAuthenticationFieldBytes
        )
        XCTAssertLessThanOrEqual(decoding.requiredReadChunkBytes, decoding.maximumEncodedBytes)
        XCTAssertEqual(
            BackupTransactionJournalFormat.requiredReplacementOrder,
            BackupJournalReplacementPhase.allCases
        )
    }

    func testIndependentJournalGoldenAndAuthenticatedBytesCoverPostPreparedState() throws {
        let fixture = try makePlanningFixture(sourceTree: try directorySourceTree())
        let stagedTree = try copiedTree(
            fixture.sourceTree,
            volume: fixture.destinationIdentity.persistentVolumeIdentity,
            device: fixture.destinationIdentity.device,
            firstInode: 100
        )
        let record = try journalRecord(
            fixture: fixture,
            kind: .publicationAuthorized,
            sequence: 4,
            previousTag: bytes(0x91),
            stagedTree: stagedTree,
            stagingRootIdentity: stagedTree.rootIdentity.stableNodeIdentity,
            publicationAuthorizationTime: try timestamp(1_100),
            publicationMonotonicTime: try BackupMonotonicInstant(
                clockSessionIdentifier: bytes(0x92),
                nanoseconds: 123
            )
        )
        let expectedAuthentication = independentJournalAuthenticationBytes(record, keyIdentifier: "golden-key")
        XCTAssertEqual(try record.authenticationBytes(keyIdentifier: "golden-key"), expectedAuthentication)

        let authenticated = try BackupAuthenticatedTransactionJournalRecord(
            record: record,
            keyIdentifier: "golden-key",
            authenticationTag: bytes(0x93)
        )
        var expectedFile = expectedAuthentication
        appendField(bytes(0x93), to: &expectedFile)
        XCTAssertEqual(try authenticated.authenticationBytes(), expectedAuthentication)
        XCTAssertEqual(try authenticated.encodedData(), expectedFile)
    }

    func testExecutionOutcomeValuesPreserveDurableAndUncertainState() throws {
        let fixture = try makePlanningFixture()
        let backupURL = URL(filePath: "/synthetic/source.backup")
        let result = BackupExecutionResult(
            backupURL: backupURL,
            removedBackupURLs: [URL(filePath: "/synthetic/old")],
            pendingCleanupURLs: [URL(filePath: "/synthetic/quarantine")],
            outputBytes: fixture.plan.expectedOutputBytes
        )
        let uncertainty = try BackupPublicationUncertainty(
            backupURL: backupURL,
            transactionIdentifier: bytes(0x81),
            reason: "sync outcome unknown"
        )
        XCTAssertEqual(
            BackupExecutionOutcome.completed(result),
            BackupExecutionOutcome.completed(result)
        )
        XCTAssertNotEqual(
            BackupExecutionOutcome.failed(.beforePublication(reason: "copy failed")),
            BackupExecutionOutcome.cancelled(.beforePublication(reason: "copy failed"))
        )
        XCTAssertEqual(
            BackupExecutionOutcome.failed(
                .afterPublication(
                    backupURL: backupURL,
                    removedBackupURLs: result.removedBackupURLs,
                    quarantinedBackupURLs: result.pendingCleanupURLs,
                    reason: "cleanup failed"
                )
            ),
            BackupExecutionOutcome.failed(
                .afterPublication(
                    backupURL: backupURL,
                    removedBackupURLs: [URL(filePath: "/synthetic/old")],
                    quarantinedBackupURLs: [URL(filePath: "/synthetic/quarantine")],
                    reason: "cleanup failed"
                )
            )
        )
        XCTAssertEqual(
            BackupExecutionOutcome.publicationUncertain(uncertainty),
            BackupExecutionOutcome.publicationUncertain(uncertainty)
        )
        XCTAssertThrowsError(
            try BackupPublicationUncertainty(
                backupURL: backupURL,
                transactionIdentifier: [1],
                reason: "invalid"
            )
        ) { error in
            guard case .invalidObservation = error as? BackupPolicyError else {
                return XCTFail("Expected invalidObservation, got \(error)")
            }
        }
    }

    private let anchorIdentifier = [UInt8](repeating: 0x30, count: 32)

    private struct PlanningFixture {
        let policy: BackupPolicy
        let request: BackupPlanningRequest
        let plan: BackupExecutionPlan
        let sourceBinding: BackupAuthenticatedSourceBinding
        let sourceTree: BackupTreeSnapshot
        let destinationIdentity: BackupItemIdentity
        let publicationName: String
    }

    private struct QuarantineTargetFixture {
        let container: BackupItemIdentity
        let postRenameTree: BackupTreeSnapshot
        let quarantinedTarget: BackupTransactionJournalTarget
    }

    private struct TargetContext {
        let sourceBinding: BackupAuthenticatedSourceBinding
        let provenance: BackupAuthenticatedProvenance
        let container: BackupItemIdentity
    }

    private struct RetentionJournalFixture {
        let planning: PlanningFixture
        let stagedTree: BackupTreeSnapshot
        let publicationTime: BackupTimestamp
        let publicationMonotonic: BackupMonotonicInstant
        let retentionTime: BackupTimestamp
        let retentionMonotonic: BackupMonotonicInstant
        let publishedProvenance: BackupAuthenticatedProvenance
        let initialTarget: BackupTransactionJournalTarget
        let intentTarget: BackupTransactionJournalTarget
        let quarantinedTarget: BackupTransactionJournalTarget
        let restoredTarget: BackupTransactionJournalTarget
    }

    private enum FixtureError: Error {
        case missingCreateInstruction
    }

    private func basePolicy(
        destination: BackupDestinationStrategy = .alongsideSource,
        retention: BackupRetentionPolicy = .keepAll,
        limits: BackupPlanningLimits = .default
    ) throws -> BackupPolicy {
        try BackupPolicy(
            destination: destination,
            naming: BackupNamingPolicy(style: .suffixOnly, suffix: ".backup"),
            collisionBehavior: .fail,
            retention: retention,
            limits: limits
        )
    }

    private func makePlanningFixture(
        policy: BackupPolicy? = nil,
        sourceURL: URL = URL(filePath: "/synthetic/source"),
        sourceTree: BackupTreeSnapshot? = nil,
        destinationURL: URL? = nil,
        destinationIdentity: BackupItemIdentity? = nil,
        parentDirectoryIdentity: BackupItemIdentity? = nil,
        requestTimestamp: BackupTimestamp? = nil,
        managedBackups: [BackupExistingBackup] = []
    ) throws -> PlanningFixture {
        let policy = try policy ?? basePolicy()
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let sourceTree =
            try sourceTree
            ?? BackupTreeSnapshot(
                rootIdentity: item(volume: volume, inode: 1, size: 3, charge: 3),
                metadataRequirements: .all
            )
        let destinationURL = destinationURL ?? sourceURL.deletingLastPathComponent()
        let destinationIdentity =
            try destinationIdentity
            ?? item(
                volume: sourceTree.rootIdentity.persistentVolumeIdentity,
                device: sourceTree.rootIdentity.device,
                inode: 900,
                kind: .directory,
                linkCount: 2,
                charge: 1
            )
        let parentDirectoryIdentity =
            parentDirectoryIdentity
            ?? (sourceURL.path == "/" ? nil : destinationIdentity)
        let sourceBinding = try authenticatedBinding(
            source: sourceTree.rootIdentity.stableNodeIdentity,
            destination: destinationIdentity.stableNodeIdentity
        )
        let timestamp = try requestTimestamp ?? BackupTimestamp(secondsSince1970: 1_000, nanoseconds: 100)
        let planner = BackupPlanner(policy: policy)
        let names = try planner.candidateNames(for: sourceURL, at: timestamp)
        let request = BackupPlanningRequest(
            trigger: .beforeSave,
            sourceBinding: sourceBinding,
            timestamp: timestamp,
            source: BackupSourceObservation(
                sourceURL: sourceURL,
                parentDirectoryIdentity: parentDirectoryIdentity,
                tree: sourceTree,
                accessRequirement: .declaredAmbientAccess
            ),
            destination: BackupDestinationObservation(
                directoryURL: destinationURL,
                directoryIdentity: destinationIdentity,
                accessRequirement: .declaredAmbientAccess,
                nameCandidates: names.map { BackupNameCandidateObservation(name: $0, isOccupied: false) },
                managedBackups: managedBackups
            ),
            parentMutationCapability: try BackupParentMutationCapability(
                capabilityIdentifier: bytes(0x70),
                destinationDirectoryIdentity: destinationIdentity.stableNodeIdentity,
                semantics: .executorHeldExclusiveAuthority
            )
        )
        let plan = try planner.plan(request)
        guard case .createBackup(let copy) = plan.steps.first else {
            throw FixtureError.missingCreateInstruction
        }
        return PlanningFixture(
            policy: policy,
            request: request,
            plan: plan,
            sourceBinding: sourceBinding,
            sourceTree: sourceTree,
            destinationIdentity: destinationIdentity,
            publicationName: copy.provenanceRequest.name
        )
    }

    private func makeRetentionPlanningFixture() throws -> PlanningFixture {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let sourceTree = BackupTreeSnapshot(
            rootIdentity: try item(volume: volume, inode: 1, size: 3, charge: 3),
            metadataRequirements: .all
        )
        let destination = try item(
            volume: volume,
            inode: 900,
            kind: .directory,
            linkCount: 2,
            charge: 1
        )
        let binding = try authenticatedBinding(
            source: sourceTree.rootIdentity.stableNodeIdentity,
            destination: destination.stableNodeIdentity
        )
        let oldTree = BackupTreeSnapshot(
            rootIdentity: try item(volume: volume, inode: 300, size: 3, charge: 3, changeSecond: 90),
            metadataRequirements: .all
        )
        let oldProvenance = try makeAuthenticatedProvenance(
            sourceBinding: binding,
            sourceRootIdentity: sourceTree.rootIdentity,
            destination: destination.stableNodeIdentity,
            name: "old.backup",
            tree: oldTree,
            createdAt: try timestamp(950),
            tagByte: 0x83
        )
        let existing = try BackupExistingBackup(
            boundPath: try boundPath(name: "old.backup", identity: oldTree.rootIdentity),
            provenanceRecord: oldProvenance,
            tree: oldTree
        )
        let policy = try basePolicy(retention: BackupRetentionPolicy(maximumCount: 1))
        return try makePlanningFixture(
            policy: policy,
            sourceTree: sourceTree,
            destinationIdentity: destination,
            parentDirectoryIdentity: destination,
            managedBackups: [existing]
        )
    }

    private func existingBackup(
        sourceBinding: BackupAuthenticatedSourceBinding,
        sourceRootIdentity: BackupItemIdentity,
        destination: BackupItemIdentity,
        name: String,
        inode: UInt64,
        createdAt: BackupTimestamp,
        tagByte: UInt8
    ) throws -> BackupExistingBackup {
        let tree = BackupTreeSnapshot(
            rootIdentity: try item(
                volume: destination.persistentVolumeIdentity,
                device: destination.device,
                inode: inode,
                size: 3,
                charge: 3,
                changeSecond: createdAt.secondsSince1970
            ),
            metadataRequirements: .all
        )
        let provenance = try makeAuthenticatedProvenance(
            sourceBinding: sourceBinding,
            sourceRootIdentity: sourceRootIdentity,
            destination: destination.stableNodeIdentity,
            name: name,
            tree: tree,
            createdAt: createdAt,
            transactionByte: UInt8(truncatingIfNeeded: inode),
            tagByte: tagByte
        )
        return try BackupExistingBackup(
            boundPath: boundPath(name: name, identity: tree.rootIdentity),
            provenanceRecord: provenance,
            tree: tree
        )
    }

    private func makeRetentionJournalFixture() throws -> RetentionJournalFixture {
        let planning = try makeRetentionPlanningFixture()
        guard planning.plan.steps.count == 2,
            case .removeRetainedBackup(let removal) = planning.plan.steps[1]
        else {
            throw FixtureError.missingCreateInstruction
        }
        let stagedTree = try copiedTree(
            planning.sourceTree,
            volume: planning.destinationIdentity.persistentVolumeIdentity,
            device: planning.destinationIdentity.device,
            firstInode: 100
        )
        let publishedTree = replacingRootChangeTime(in: stagedTree, with: try timestamp(1_100))
        let publicationTime = try timestamp(1_100)
        let session = bytes(0xA0)
        let publicationMonotonic = try BackupMonotonicInstant(
            clockSessionIdentifier: session,
            nanoseconds: 1_000_000_000
        )
        let retentionTime = try timestamp(1_101)
        let retentionMonotonic = try BackupMonotonicInstant(
            clockSessionIdentifier: session,
            nanoseconds: 2_000_000_000
        )
        let publishedProvenance = try makeAuthenticatedProvenance(
            sourceBinding: planning.sourceBinding,
            sourceRootIdentity: planning.sourceTree.rootIdentity,
            destination: planning.destinationIdentity.stableNodeIdentity,
            name: planning.publicationName,
            tree: publishedTree,
            createdAt: publicationTime,
            transactionByte: 0x40,
            tagByte: 0x84
        )
        let initialTarget = try BackupTransactionJournalTarget(
            originalPath: removal.targetBoundPath,
            quarantineName: nil,
            provenance: removal.expectedProvenance,
            preRenameTree: removal.expectedTree,
            postRenameTree: nil,
            deletionManifest: [],
            deletedManifestEntryCount: 0
        )
        let container = try item(
            volume: planning.destinationIdentity.persistentVolumeIdentity,
            device: planning.destinationIdentity.device,
            inode: 700,
            kind: .directory,
            linkCount: 2,
            charge: 1
        )
        let intentTarget = try BackupTransactionJournalTarget(
            originalPath: removal.targetBoundPath,
            quarantineName: "quarantine-old",
            quarantineContainerIdentity: container.stableNodeIdentity,
            provenance: removal.expectedProvenance,
            preRenameTree: removal.expectedTree,
            postRenameTree: nil,
            deletionManifest: [],
            deletedManifestEntryCount: 0
        )
        let postRenameTree = replacingRootChangeTime(in: removal.expectedTree, with: try timestamp(1_102))
        let manifest = try deletionManifest(
            tree: postRenameTree,
            rootName: "quarantine-old",
            rootParent: container.stableNodeIdentity
        )
        let quarantinedTarget = try BackupTransactionJournalTarget(
            originalPath: removal.targetBoundPath,
            quarantineName: "quarantine-old",
            quarantineContainerIdentity: container.stableNodeIdentity,
            provenance: removal.expectedProvenance,
            preRenameTree: removal.expectedTree,
            postRenameTree: postRenameTree,
            deletionManifest: manifest,
            deletedManifestEntryCount: 0
        )
        let restoredTree = postRenameTree
        let restoredProvenance = try makeAuthenticatedProvenance(
            sourceBinding: planning.sourceBinding,
            sourceRootIdentity: removal.expectedProvenance.provenance.sourceRootIdentity,
            destination: planning.destinationIdentity.stableNodeIdentity,
            name: removal.expectedProvenance.provenance.name,
            tree: restoredTree,
            createdAt: removal.expectedProvenance.provenance.createdAt,
            transactionByte: removal.expectedProvenance.provenance.transactionIdentifier[0],
            tagByte: 0xFE
        )
        let restoredTarget = try BackupTransactionJournalTarget(
            originalPath: try boundPath(name: "old.backup", identity: restoredTree.rootIdentity),
            quarantineName: nil,
            provenance: restoredProvenance,
            preRenameTree: restoredTree,
            postRenameTree: nil,
            deletionManifest: [],
            deletedManifestEntryCount: 0
        )
        return RetentionJournalFixture(
            planning: planning,
            stagedTree: stagedTree,
            publicationTime: publicationTime,
            publicationMonotonic: publicationMonotonic,
            retentionTime: retentionTime,
            retentionMonotonic: retentionMonotonic,
            publishedProvenance: publishedProvenance,
            initialTarget: initialTarget,
            intentTarget: intentTarget,
            quarantinedTarget: quarantinedTarget,
            restoredTarget: restoredTarget
        )
    }

    private func journalRecord(
        fixture: PlanningFixture,
        kind: BackupTransactionJournalRecordKind,
        transactionSequence: UInt64 = 1,
        sequence: UInt64,
        previousTag: [UInt8]?,
        stagedConstructionManifest: [BackupStagedConstructionManifestEntry] = [],
        stagedConstructedNodeIdentities: [BackupStableNodeIdentity] = [],
        stagedConstructionInFlightIndex: UInt64? = nil,
        stagedTree: BackupTreeSnapshot? = nil,
        stagedDeletionManifest: [BackupJournalDeletionManifestEntry] = [],
        stagedDeletedManifestEntryCount: UInt64 = 0,
        stagedDeletionInFlightIndex: UInt64? = nil,
        stagingRootIdentity: BackupStableNodeIdentity? = nil,
        publicationAuthorizationTime: BackupTimestamp? = nil,
        publicationMonotonicTime: BackupMonotonicInstant? = nil,
        publishedProvenance: BackupAuthenticatedProvenance? = nil,
        retentionAuthorizationTime: BackupTimestamp? = nil,
        retentionMonotonicTime: BackupMonotonicInstant? = nil,
        retentionTargets: [BackupTransactionJournalTarget] = []
    ) throws -> BackupTransactionJournalRecord {
        try BackupTransactionJournalRecord(
            recordKind: kind,
            transactionSequenceNumber: transactionSequence,
            sequenceNumber: sequence,
            sequenceAnchorIdentifier: anchorIdentifier,
            transactionIdentifier: bytes(0x40),
            previousRecordAuthenticationTag: previousTag,
            sourceBinding: fixture.sourceBinding,
            sourceTree: fixture.sourceTree,
            stagedConstructionManifest: stagedConstructionManifest,
            stagedConstructedNodeIdentities: stagedConstructedNodeIdentities,
            stagedConstructionInFlightManifestEntryIndex: stagedConstructionInFlightIndex,
            stagedTree: stagedTree,
            stagedDeletionManifest: stagedDeletionManifest,
            stagedDeletedManifestEntryCount: stagedDeletedManifestEntryCount,
            stagedDeletionInFlightManifestEntryIndex: stagedDeletionInFlightIndex,
            destinationDirectoryIdentity: fixture.destinationIdentity,
            stagingName: ".stage",
            stagingRootIdentity: stagingRootIdentity,
            publicationName: fixture.publicationName,
            metadataRequirements: fixture.policy.metadataRequirements,
            expectedOutputBytes: fixture.plan.expectedOutputBytes,
            planningLimits: fixture.plan.limits,
            journalReservationBytes: fixture.plan.requiredJournalReservationBytes,
            requestTimestamp: fixture.request.timestamp,
            publicationAuthorizationTime: publicationAuthorizationTime,
            publicationMonotonicTime: publicationMonotonicTime,
            publishedProvenance: publishedProvenance,
            retentionAuthorizationTime: retentionAuthorizationTime,
            retentionMonotonicTime: retentionMonotonicTime,
            retentionPolicy: fixture.policy.retention,
            plannedRemovalNames: fixture.plan.retentionValidation.plannedRemovalNames,
            retentionTargets: retentionTargets
        )
    }

    private func makeQuarantineTargetFixture() throws -> QuarantineTargetFixture {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let tree = BackupTreeSnapshot(
            rootIdentity: try item(volume: volume, inode: 300, size: 3, charge: 3, changeSecond: 90),
            metadataRequirements: .all
        )
        let context = try makeTargetContext(tree: tree, name: "old.backup")
        let postRenameTree = replacingRootChangeTime(in: tree, with: try timestamp(101))
        let manifest = try deletionManifest(
            tree: postRenameTree,
            rootName: "quarantine",
            rootParent: context.container.stableNodeIdentity
        )
        let target = try BackupTransactionJournalTarget(
            originalPath: try boundPath(name: "old.backup", identity: tree.rootIdentity),
            quarantineName: "quarantine",
            quarantineContainerIdentity: context.container.stableNodeIdentity,
            provenance: context.provenance,
            preRenameTree: tree,
            postRenameTree: postRenameTree,
            deletionManifest: manifest,
            deletedManifestEntryCount: 0
        )
        return QuarantineTargetFixture(
            container: context.container,
            postRenameTree: postRenameTree,
            quarantinedTarget: target
        )
    }

    private func replacingQuarantineTarget(
        _ target: BackupTransactionJournalTarget,
        manifest: [BackupJournalDeletionManifestEntry]? = nil,
        deletedCount: UInt64? = nil,
        inFlightIndex: UInt64?? = nil
    ) throws -> BackupTransactionJournalTarget {
        try BackupTransactionJournalTarget(
            originalPath: target.originalPath,
            quarantineName: target.quarantineName,
            quarantineContainerIdentity: target.quarantineContainerIdentity,
            provenance: target.provenance,
            preRenameTree: target.preRenameTree,
            postRenameTree: target.postRenameTree,
            deletionManifest: manifest ?? target.deletionManifest,
            deletedManifestEntryCount: deletedCount ?? target.deletedManifestEntryCount,
            deletionInFlightManifestEntryIndex: inFlightIndex ?? target.deletionInFlightManifestEntryIndex
        )
    }

    private func replacingRequest(
        _ request: BackupPlanningRequest,
        parentMutationCapability: BackupParentMutationCapability?
    ) -> BackupPlanningRequest {
        BackupPlanningRequest(
            trigger: request.trigger,
            sourceBinding: request.sourceBinding,
            timestamp: request.timestamp,
            source: request.source,
            destination: request.destination,
            parentMutationCapability: parentMutationCapability
        )
    }

    private func replacingRequest(
        _ request: BackupPlanningRequest,
        managedBackups: [BackupExistingBackup]
    ) -> BackupPlanningRequest {
        BackupPlanningRequest(
            trigger: request.trigger,
            sourceBinding: request.sourceBinding,
            timestamp: request.timestamp,
            source: request.source,
            destination: BackupDestinationObservation(
                directoryURL: request.destination.directoryURL,
                directoryIdentity: request.destination.directoryIdentity,
                accessRequirement: request.destination.accessRequirement,
                nameCandidates: request.destination.nameCandidates,
                managedBackups: managedBackups
            ),
            parentMutationCapability: request.parentMutationCapability
        )
    }

    private func makeTargetContext(tree: BackupTreeSnapshot, name: String) throws -> TargetContext {
        let volume = tree.rootIdentity.persistentVolumeIdentity
        let source = try item(volume: volume, inode: 10, size: 3, charge: 3)
        let destination = try item(
            volume: volume,
            inode: 20,
            kind: .directory,
            linkCount: 2,
            charge: 1
        )
        let sourceBinding = try authenticatedBinding(
            source: source.stableNodeIdentity,
            destination: destination.stableNodeIdentity
        )
        let provenance = try makeAuthenticatedProvenance(
            sourceBinding: sourceBinding,
            sourceRootIdentity: source,
            destination: destination.stableNodeIdentity,
            name: name,
            tree: tree
        )
        let container = try item(
            volume: volume,
            inode: 21,
            kind: .directory,
            linkCount: 2,
            charge: 1
        )
        return TargetContext(sourceBinding: sourceBinding, provenance: provenance, container: container)
    }

    private func directorySourceTree() throws -> BackupTreeSnapshot {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let root = try item(volume: volume, inode: 1, kind: .directory, linkCount: 2, charge: 1)
        let child = try item(volume: volume, inode: 2, size: 5, charge: 5)
        return BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("file"), identity: child)
            ]
        )
    }

    private func nestedDirectorySourceTree() throws -> BackupTreeSnapshot {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let root = try item(volume: volume, inode: 1, kind: .directory, linkCount: 3, charge: 1)
        let directory = try item(volume: volume, inode: 2, kind: .directory, linkCount: 2, charge: 1)
        let child = try item(volume: volume, inode: 3, size: 5, charge: 5)
        return BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("dir"), identity: directory),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("dir/file"), identity: child)
            ]
        )
    }

    private func hardlinkSourceTree() throws -> BackupTreeSnapshot {
        let volume = try BackupPersistentVolumeIdentity(bytes: [1])
        let root = try item(volume: volume, inode: 1, kind: .directory, linkCount: 2, charge: 2)
        let hardlink = try item(volume: volume, inode: 2, linkCount: 2, size: 8, charge: 8)
        return BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: .all,
            descendants: [
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("a"), identity: hardlink),
                BackupObservedTreeEntry(relativePath: try BackupRelativePath("b"), identity: hardlink)
            ]
        )
    }

    private func copiedTree(
        _ source: BackupTreeSnapshot,
        volume: BackupPersistentVolumeIdentity,
        device: UInt64,
        firstInode: UInt64
    ) throws -> BackupTreeSnapshot {
        var nextInode = firstInode
        var copiedNodes: [BackupStableNodeIdentity: BackupItemIdentity] = [:]
        func copy(_ identity: BackupItemIdentity) throws -> BackupItemIdentity {
            if let existing = copiedNodes[identity.stableNodeIdentity] { return existing }
            let result = try copiedIdentity(
                identity,
                volume: volume,
                device: device,
                inode: nextInode
            )
            nextInode += 1
            copiedNodes[identity.stableNodeIdentity] = result
            return result
        }
        let root = try copy(source.rootIdentity)
        let descendants = try source.descendants.map {
            BackupObservedTreeEntry(relativePath: $0.relativePath, identity: try copy($0.identity))
        }
        return BackupTreeSnapshot(
            rootIdentity: root,
            metadataRequirements: source.metadataRequirements,
            descendants: descendants
        )
    }

    private func copiedIdentity(
        _ source: BackupItemIdentity,
        volume: BackupPersistentVolumeIdentity,
        device: UInt64,
        inode: UInt64
    ) throws -> BackupItemIdentity {
        BackupItemIdentity(
            persistentVolumeIdentity: volume,
            device: device,
            inode: inode,
            generation: BackupReliableFileGeneration(reliablyReportedValue: inode + 1_000),
            kind: source.kind,
            linkCount: source.linkCount,
            size: source.size,
            outputByteCharge: source.outputByteCharge,
            modificationTime: source.modificationTime,
            changeTime: try timestamp(source.changeTime.secondsSince1970 + 1),
            contentDigest: source.contentDigest,
            requiredMetadataDigest: source.requiredMetadataDigest,
            deletionInvariantMetadataDigest: source.deletionInvariantMetadataDigest
        )
    }

    private func replacingRootChangeTime(
        in tree: BackupTreeSnapshot,
        with changeTime: BackupTimestamp
    ) -> BackupTreeSnapshot {
        BackupTreeSnapshot(
            rootIdentity: replacing(tree.rootIdentity, changeTime: changeTime),
            metadataRequirements: tree.metadataRequirements,
            descendants: tree.descendants
        )
    }

    private func deletionManifest(
        tree: BackupTreeSnapshot,
        rootName: String,
        rootParent: BackupStableNodeIdentity
    ) throws -> [BackupJournalDeletionManifestEntry] {
        var identitiesByPath: [String: BackupItemIdentity] = ["": tree.rootIdentity]
        for entry in tree.descendants { identitiesByPath[entry.relativePath.rawValue] = entry.identity }
        var priorHardlinkDeletions: [BackupStableNodeIdentity: UInt64] = [:]
        var entries: [BackupJournalDeletionManifestEntry] = []
        let descendants = tree.descendants.sorted {
            if $0.relativePath.components.count != $1.relativePath.components.count {
                return $0.relativePath.components.count > $1.relativePath.components.count
            }
            return $0.relativePath.rawUTF8Bytes.lexicographicallyPrecedes($1.relativePath.rawUTF8Bytes)
        }
        for observed in descendants {
            let path = observed.relativePath
            let parentPath =
                path.components.count > 1
                ? try BackupRelativePath(path.components.dropLast().joined(separator: "/"))
                : nil
            let parentIdentity = try XCTUnwrap(identitiesByPath[parentPath?.rawValue ?? ""])
            let removedAliases = priorHardlinkDeletions[observed.identity.stableNodeIdentity, default: 0]
            let directDirectories = UInt64(
                tree.descendants.filter {
                    $0.identity.kind == .directory
                        && Array($0.relativePath.components.dropLast()) == path.components
                }.count
            )
            entries.append(
                try BackupJournalDeletionManifestEntry(
                    relativePath: path,
                    parentRelativePath: parentPath,
                    name: try XCTUnwrap(path.components.last),
                    expectedParentIdentity: parentIdentity.stableNodeIdentity,
                    expectedIdentity: observed.identity,
                    expectedLinkCountBeforeDeletion: observed.identity.linkCount - removedAliases
                        - directDirectories,
                    expectedDirectChildCountBeforeDeletion: observed.identity.kind == .directory ? 0 : nil
                )
            )
            if observed.identity.kind == .regularFile {
                priorHardlinkDeletions[observed.identity.stableNodeIdentity] = removedAliases + 1
            }
        }
        let rootDirectories = UInt64(
            tree.descendants.filter {
                $0.identity.kind == .directory && $0.relativePath.components.count == 1
            }.count
        )
        entries.append(
            try BackupJournalDeletionManifestEntry(
                relativePath: nil,
                parentRelativePath: nil,
                name: rootName,
                expectedParentIdentity: rootParent,
                expectedIdentity: tree.rootIdentity,
                expectedLinkCountBeforeDeletion: tree.rootIdentity.linkCount - rootDirectories,
                expectedDirectChildCountBeforeDeletion: tree.rootIdentity.kind == .directory ? 0 : nil
            )
        )
        return entries
    }

    private func authenticatedBinding(
        source: BackupStableNodeIdentity,
        destination: BackupStableNodeIdentity
    ) throws -> BackupAuthenticatedSourceBinding {
        try BackupAuthenticatedSourceBinding(
            binding: sourceBinding(source: source, destination: destination),
            keyIdentifier: "key",
            authenticationTag: bytes(0x30)
        )
    }

    private func sourceBinding(
        source: BackupStableNodeIdentity,
        destination: BackupStableNodeIdentity
    ) throws -> BackupSourceBinding {
        try BackupSourceBinding(
            sourceBindingIdentifier: bytes(0x20),
            seriesIdentifier: "series-1",
            sourceRootIdentity: source,
            destinationDirectoryIdentity: destination,
            provenanceNotBefore: timestamp(800),
            issuedAt: timestamp(900),
            expiresAt: timestamp(2_000)
        )
    }

    private func makeProvenance(
        sourceBinding: BackupSourceBinding,
        sourceRootIdentity: BackupItemIdentity,
        destination: BackupStableNodeIdentity,
        name: String,
        tree: BackupTreeSnapshot,
        createdAt: BackupTimestamp? = nil,
        transactionByte: UInt8 = 0x40
    ) throws -> BackupProvenance {
        try BackupProvenance(
            transactionIdentifier: bytes(transactionByte),
            sourceBindingIdentifier: sourceBinding.sourceBindingIdentifier,
            seriesIdentifier: sourceBinding.seriesIdentifier,
            name: name,
            createdAt: createdAt ?? timestamp(1_000),
            sourceRootIdentity: sourceRootIdentity,
            destinationDirectoryIdentity: destination,
            backupTree: tree
        )
    }

    private func makeAuthenticatedProvenance(
        sourceBinding: BackupAuthenticatedSourceBinding,
        sourceRootIdentity: BackupItemIdentity,
        destination: BackupStableNodeIdentity,
        name: String,
        tree: BackupTreeSnapshot,
        createdAt: BackupTimestamp? = nil,
        transactionByte: UInt8 = 0x40,
        tagByte: UInt8 = 0x80
    ) throws -> BackupAuthenticatedProvenance {
        try BackupAuthenticatedProvenance(
            provenance: makeProvenance(
                sourceBinding: sourceBinding.binding,
                sourceRootIdentity: sourceRootIdentity,
                destination: destination,
                name: name,
                tree: tree,
                createdAt: createdAt,
                transactionByte: transactionByte
            ),
            keyIdentifier: "key",
            authenticationTag: bytes(tagByte)
        )
    }

    private func boundPath(name: String, identity: BackupItemIdentity) throws -> BackupBoundRelativePath {
        try BackupBoundRelativePath(
            relativePath: BackupRelativePath(name),
            components: [BackupBoundPathComponent(name: name, expectedIdentity: identity)]
        )
    }

    private func item(
        volume: BackupPersistentVolumeIdentity,
        device: UInt64 = 7,
        inode: UInt64,
        generation: UInt64? = nil,
        kind: BackupItemKind = .regularFile,
        linkCount: UInt64 = 1,
        size: UInt64 = 0,
        charge: UInt64,
        modificationSecond: Int64 = 50,
        changeSecond: Int64 = 60,
        contentSeed: UInt8? = nil
    ) throws -> BackupItemIdentity {
        BackupItemIdentity(
            persistentVolumeIdentity: volume,
            device: device,
            inode: inode,
            generation: BackupReliableFileGeneration(reliablyReportedValue: generation ?? inode + 100),
            kind: kind,
            linkCount: linkCount,
            size: size,
            outputByteCharge: charge,
            modificationTime: try timestamp(modificationSecond),
            changeTime: try timestamp(changeSecond),
            contentDigest: try digest(contentSeed ?? UInt8(truncatingIfNeeded: inode)),
            requiredMetadataDigest: try digest(0xB0 &+ UInt8(truncatingIfNeeded: inode)),
            deletionInvariantMetadataDigest: try digest(0xD0 &+ UInt8(truncatingIfNeeded: inode))
        )
    }

    private func replacing(
        _ identity: BackupItemIdentity,
        volume: BackupPersistentVolumeIdentity? = nil,
        device: UInt64? = nil,
        inode: UInt64? = nil,
        generation: UInt64? = nil,
        kind: BackupItemKind? = nil,
        linkCount: UInt64? = nil,
        changeTime: BackupTimestamp? = nil,
        contentSeed: UInt8? = nil,
        requiredMetadataSeed: UInt8? = nil
    ) -> BackupItemIdentity {
        BackupItemIdentity(
            persistentVolumeIdentity: volume ?? identity.persistentVolumeIdentity,
            device: device ?? identity.device,
            inode: inode ?? identity.inode,
            generation: BackupReliableFileGeneration(
                reliablyReportedValue: generation ?? identity.generation.rawValue
            ),
            kind: kind ?? identity.kind,
            linkCount: linkCount ?? identity.linkCount,
            size: identity.size,
            outputByteCharge: identity.outputByteCharge,
            modificationTime: identity.modificationTime,
            changeTime: changeTime ?? identity.changeTime,
            contentDigest: contentSeed.flatMap { try? digest($0) } ?? identity.contentDigest,
            requiredMetadataDigest: requiredMetadataSeed.flatMap { try? digest($0) }
                ?? identity.requiredMetadataDigest,
            deletionInvariantMetadataDigest: identity.deletionInvariantMetadataDigest
        )
    }

    private func stableIdentity(
        volume: BackupPersistentVolumeIdentity,
        inode: UInt64,
        generation: UInt64
    ) -> BackupStableNodeIdentity {
        BackupStableNodeIdentity(
            persistentVolumeIdentity: volume,
            inode: inode,
            generation: BackupReliableFileGeneration(reliablyReportedValue: generation)
        )
    }

    private func timestamp(_ seconds: Int64, nanoseconds: UInt32 = 0) throws -> BackupTimestamp {
        try BackupTimestamp(secondsSince1970: seconds, nanoseconds: nanoseconds)
    }

    private func digest(_ byte: UInt8) throws -> BackupIntegrityDigest {
        try BackupIntegrityDigest(bytes: bytes(byte))
    }

    private func bytes(_ byte: UInt8) -> [UInt8] {
        [UInt8](repeating: byte, count: BackupAuthenticationFormat.identifierByteCount)
    }

    private func independentJournalAuthenticationBytes(
        _ record: BackupTransactionJournalRecord,
        keyIdentifier: String
    ) -> Data {
        var data = Data(BackupAuthenticationFormat.transactionJournalDomain.utf8)
        data.append(0)
        appendField(Array(keyIdentifier.utf8), to: &data)
        appendField(uint64Bytes(UInt64(record.schemaVersion)), to: &data)
        appendField(Array(record.recordKind.rawValue.utf8), to: &data)
        appendField(uint64Bytes(record.transactionSequenceNumber), to: &data)
        appendField(uint64Bytes(record.sequenceNumber), to: &data)
        appendField(record.sequenceAnchorIdentifier, to: &data)
        appendField(record.transactionIdentifier, to: &data)
        appendOptional(record.previousRecordAuthenticationTag, to: &data) { appendField($0, to: &$1) }
        appendAuthenticatedSourceBinding(record.sourceBinding, to: &data)
        appendTree(record.sourceTree, to: &data)
        appendArray(record.stagedConstructionManifest, to: &data) { appendConstructionEntry($0, to: &$1) }
        appendArray(record.stagedConstructedNodeIdentities, to: &data) { appendStableIdentity($0, to: &$1) }
        appendOptional(record.stagedConstructionInFlightManifestEntryIndex, to: &data) {
            appendField(uint64Bytes($0), to: &$1)
        }
        appendOptional(record.stagedTree, to: &data) { appendTree($0, to: &$1) }
        appendArray(record.stagedDeletionManifest, to: &data) { appendDeletionEntry($0, to: &$1) }
        appendField(uint64Bytes(record.stagedDeletedManifestEntryCount), to: &data)
        appendOptional(record.stagedDeletionInFlightManifestEntryIndex, to: &data) {
            appendField(uint64Bytes($0), to: &$1)
        }
        appendItemIdentity(record.destinationDirectoryIdentity, to: &data)
        appendField(Array(record.stagingName.utf8), to: &data)
        appendOptional(record.stagingRootIdentity, to: &data) { appendStableIdentity($0, to: &$1) }
        appendField(Array(record.publicationName.utf8), to: &data)
        appendField(uint16Bytes(record.metadataRequirements.rawValue), to: &data)
        appendField(uint64Bytes(record.expectedOutputBytes), to: &data)
        appendPlanningLimits(record.planningLimits, to: &data)
        appendField(uint64Bytes(UInt64(bitPattern: Int64(record.journalReservationBytes))), to: &data)
        appendTimestamp(record.requestTimestamp, to: &data)
        appendOptional(record.publicationAuthorizationTime, to: &data) { appendTimestamp($0, to: &$1) }
        appendOptional(record.publicationMonotonicTime, to: &data) { appendMonotonicInstant($0, to: &$1) }
        appendOptional(record.publishedProvenance, to: &data) { appendAuthenticatedProvenance($0, to: &$1) }
        appendOptional(record.retentionAuthorizationTime, to: &data) { appendTimestamp($0, to: &$1) }
        appendOptional(record.retentionMonotonicTime, to: &data) { appendMonotonicInstant($0, to: &$1) }
        appendOptional(record.retentionPolicy.maximumCount, to: &data) {
            appendField(uint64Bytes(UInt64(bitPattern: Int64($0))), to: &$1)
        }
        appendOptional(record.retentionPolicy.maximumAgeSeconds, to: &data) {
            appendField(uint64Bytes($0), to: &$1)
        }
        appendArray(record.plannedRemovalNames, to: &data) { appendField(Array($0.utf8), to: &$1) }
        appendArray(record.retentionTargets, to: &data) { appendJournalTarget($0, to: &$1) }
        return data
    }

    private func appendAuthenticatedSourceBinding(
        _ authenticated: BackupAuthenticatedSourceBinding,
        to data: inout Data
    ) {
        let binding = authenticated.binding
        appendField(uint64Bytes(UInt64(binding.schemaVersion)), to: &data)
        appendField(binding.sourceBindingIdentifier, to: &data)
        appendField(Array(binding.seriesIdentifier.utf8), to: &data)
        appendStableIdentity(binding.sourceRootIdentity, to: &data)
        appendStableIdentity(binding.destinationDirectoryIdentity, to: &data)
        appendTimestamp(binding.provenanceNotBefore, to: &data)
        appendTimestamp(binding.issuedAt, to: &data)
        appendTimestamp(binding.expiresAt, to: &data)
        appendField(Array(authenticated.keyIdentifier.utf8), to: &data)
        appendField(authenticated.authenticationTag, to: &data)
    }

    private func appendTree(_ tree: BackupTreeSnapshot, to data: inout Data) {
        appendItemIdentity(tree.rootIdentity, to: &data)
        appendField(uint16Bytes(tree.metadataRequirements.rawValue), to: &data)
        appendArray(tree.descendants, to: &data) { entry, bytes in
            appendField(entry.relativePath.rawUTF8Bytes, to: &bytes)
            appendItemIdentity(entry.identity, to: &bytes)
        }
    }

    private func appendConstructionEntry(
        _ entry: BackupStagedConstructionManifestEntry,
        to data: inout Data
    ) {
        appendField(entry.relativePath.rawUTF8Bytes, to: &data)
        appendOptional(entry.parentRelativePath, to: &data) { appendField($0.rawUTF8Bytes, to: &$1) }
        appendField(entry.nameUTF8Bytes, to: &data)
        appendField(Array(entry.expectedKind.rawValue.utf8), to: &data)
        appendStableIdentity(entry.sourceNodeIdentity, to: &data)
    }

    private func appendDeletionEntry(_ entry: BackupJournalDeletionManifestEntry, to data: inout Data) {
        appendOptional(entry.relativePath, to: &data) { appendField($0.rawUTF8Bytes, to: &$1) }
        appendOptional(entry.parentRelativePath, to: &data) { appendField($0.rawUTF8Bytes, to: &$1) }
        appendField(entry.nameUTF8Bytes, to: &data)
        appendStableIdentity(entry.expectedParentIdentity, to: &data)
        appendItemIdentity(entry.expectedIdentity, to: &data)
        appendField(uint64Bytes(entry.expectedLinkCountBeforeDeletion), to: &data)
        appendOptional(entry.expectedDirectChildCountBeforeDeletion, to: &data) {
            appendField(uint64Bytes($0), to: &$1)
        }
    }

    private func appendAuthenticatedProvenance(_ authenticated: BackupAuthenticatedProvenance, to data: inout Data) {
        let provenance = authenticated.provenance
        appendField(uint64Bytes(UInt64(provenance.schemaVersion)), to: &data)
        appendField(provenance.transactionIdentifier, to: &data)
        appendField(provenance.sourceBindingIdentifier, to: &data)
        appendField(Array(provenance.seriesIdentifier.utf8), to: &data)
        appendField(Array(provenance.name.utf8), to: &data)
        appendTimestamp(provenance.createdAt, to: &data)
        appendItemIdentity(provenance.sourceRootIdentity, to: &data)
        appendStableIdentity(provenance.destinationDirectoryIdentity, to: &data)
        appendTree(provenance.backupTree, to: &data)
        appendField(Array(authenticated.keyIdentifier.utf8), to: &data)
        appendField(authenticated.authenticationTag, to: &data)
    }

    private func appendJournalTarget(_ target: BackupTransactionJournalTarget, to data: inout Data) {
        appendField(target.originalPath.relativePath.rawUTF8Bytes, to: &data)
        appendArray(target.originalPath.components, to: &data) { component, bytes in
            appendField(component.nameUTF8Bytes, to: &bytes)
            appendItemIdentity(component.expectedIdentity, to: &bytes)
        }
        appendOptional(target.quarantineName, to: &data) { appendField(Array($0.utf8), to: &$1) }
        appendOptional(target.quarantineContainerIdentity, to: &data) { appendStableIdentity($0, to: &$1) }
        appendAuthenticatedProvenance(target.provenance, to: &data)
        appendTree(target.preRenameTree, to: &data)
        appendOptional(target.postRenameTree, to: &data) { appendTree($0, to: &$1) }
        appendArray(target.deletionManifest, to: &data) { appendDeletionEntry($0, to: &$1) }
        appendField(uint64Bytes(target.deletedManifestEntryCount), to: &data)
        appendOptional(target.deletionInFlightManifestEntryIndex, to: &data) {
            appendField(uint64Bytes($0), to: &$1)
        }
    }

    private func appendPlanningLimits(_ limits: BackupPlanningLimits, to data: inout Data) {
        for value in [
            limits.maximumNameCandidates,
            limits.maximumSourceItemCount,
            limits.maximumExistingBackupCount,
            limits.maximumRetentionItemCount,
            limits.maximumPathUTF8Bytes,
            limits.maximumTotalPathUTF8Bytes,
            Int(limits.maximumEstimatedWorkUnits),
            Int(limits.maximumOutputBytes),
            limits.maximumPlanStepCount
        ] {
            appendField(uint64Bytes(UInt64(bitPattern: Int64(value))), to: &data)
        }
    }

    private func appendMonotonicInstant(_ instant: BackupMonotonicInstant, to data: inout Data) {
        appendField(instant.clockSessionIdentifier, to: &data)
        appendField(uint64Bytes(instant.nanoseconds), to: &data)
    }

    private func appendOptional<Value>(
        _ value: Value?,
        to data: inout Data,
        appendValue: (Value, inout Data) -> Void
    ) {
        guard let value else {
            appendField([0], to: &data)
            return
        }
        appendField([1], to: &data)
        appendValue(value, &data)
    }

    private func appendArray<Value>(
        _ values: [Value],
        to data: inout Data,
        appendValue: (Value, inout Data) -> Void
    ) {
        appendField(uint64Bytes(UInt64(values.count)), to: &data)
        for value in values { appendValue(value, &data) }
    }

    private func appendField(_ bytes: [UInt8], to data: inout Data) {
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(contentsOf: bytes)
    }

    private func appendStableIdentity(_ identity: BackupStableNodeIdentity, to data: inout Data) {
        appendField(identity.persistentVolumeIdentity.bytes, to: &data)
        appendField(uint64Bytes(identity.inode), to: &data)
        appendField(uint64Bytes(identity.generation.rawValue), to: &data)
    }

    private func appendItemIdentity(_ identity: BackupItemIdentity, to data: inout Data) {
        appendField(identity.persistentVolumeIdentity.bytes, to: &data)
        appendField(uint64Bytes(identity.device), to: &data)
        appendField(uint64Bytes(identity.inode), to: &data)
        appendField(uint64Bytes(identity.generation.rawValue), to: &data)
        appendField(Array(identity.kind.rawValue.utf8), to: &data)
        appendField(uint64Bytes(identity.linkCount), to: &data)
        appendField(uint64Bytes(identity.size), to: &data)
        appendField(uint64Bytes(identity.outputByteCharge), to: &data)
        appendTimestamp(identity.modificationTime, to: &data)
        appendTimestamp(identity.changeTime, to: &data)
        appendField(identity.contentDigest.bytes, to: &data)
        appendField(identity.requiredMetadataDigest.bytes, to: &data)
        appendField(identity.deletionInvariantMetadataDigest.bytes, to: &data)
    }

    private func appendTimestamp(_ timestamp: BackupTimestamp, to data: inout Data) {
        appendField(uint64Bytes(UInt64(bitPattern: timestamp.secondsSince1970)), to: &data)
        var nanoseconds = timestamp.nanoseconds.bigEndian
        let bytes = withUnsafeBytes(of: &nanoseconds) { Array($0) }
        appendField(bytes, to: &data)
    }

    private func uint64Bytes(_ value: UInt64) -> [UInt8] {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }

    private func uint16Bytes(_ value: UInt16) -> [UInt8] {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }

    private func assertInvalidObservation<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case .invalidObservation = error as? BackupPolicyError else {
                return XCTFail("Expected invalidObservation, got \(error)", file: file, line: line)
            }
        }
    }
}

extension BackupRemovalInstruction {
    fileprivate var targetBoundPath: BackupBoundRelativePath {
        guard case .boundExisting(let path) = target.path else {
            preconditionFailure("Planner removal target must be bound")
        }
        return path
    }
}
