import CryptoKit
import Darwin
import Foundation
import MacMergeCore
import XCTest

final class ExternalToolPolicyTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let executableURL: URL
        let executableData: Data
    }

    func testDefaultPolicyDeniesExecutablesAndReportsUnsupportedExtensionCapabilities() {
        let policy = ExternalToolPolicy.default
        let planner = ExternalToolRequestPlanner(policy: policy)
        let executableCapabilities: Set<ExternalToolCapability> = [
            .unpacker,
            .prediffer,
            .editorScript,
            .copyingScript
        ]
        let unsupportedCapabilities: [ExternalToolCapability: ExternalToolCapabilityReason] = [
            .pluginReload: .pluginReloadUnsupported,
            .inProcessExtensions: .inProcessExtensionsUnsupported
        ]

        XCTAssertEqual(policy.externalExecutableRules, [])
        XCTAssertTrue(executableCapabilities.isDisjoint(with: unsupportedCapabilities.keys))
        XCTAssertEqual(
            executableCapabilities.union(unsupportedCapabilities.keys),
            Set(ExternalToolCapability.allCases)
        )
        for capability in executableCapabilities {
            XCTAssertEqual(
                policy.decision(for: capability),
                ExternalToolCapabilityDecision(
                    capability: capability,
                    status: .disabled,
                    reason: .explicitExternalExecutableRuleRequired
                )
            )
            assertPolicyError(.externalExecutableRuleRequired(capability)) {
                try planner.plan(request(capability: capability))
            }
        }

        for (capability, reason) in unsupportedCapabilities {
            XCTAssertEqual(
                policy.decision(for: capability),
                ExternalToolCapabilityDecision(
                    capability: capability,
                    status: .unsupported,
                    reason: reason
                )
            )
            assertPolicyError(.unsupportedCapability(capability, reason: reason)) {
                try planner.plan(request(capability: capability))
            }
        }
        XCTAssertEqual(policy.decisions.count, ExternalToolCapability.allCases.count)
    }

    func testMissingDuplicateAndCapabilityMismatchedRulesAreRejectedExactly() throws {
        let fixture = try makeFixture()
        let unpackerRule = makeRule(fixture)
        let predifferRule = makeRule(
            fixture,
            identifier: "reviewed-prediffer",
            capability: .prediffer
        )

        assertPolicyError(.duplicateRuleIdentifier("reviewed-tool")) {
            try ExternalToolPolicy(externalExecutableRules: [unpackerRule, unpackerRule])
        }

        let policy = try ExternalToolPolicy(externalExecutableRules: [unpackerRule, predifferRule])
        let planner = ExternalToolRequestPlanner(policy: policy)
        assertPolicyError(.ruleNotFound("missing-rule")) {
            try planner.plan(request(in: fixture, ruleIdentifier: "missing-rule"))
        }
        assertPolicyError(
            .ruleCapabilityMismatch(
                rule: "reviewed-tool",
                requested: .prediffer,
                configured: .unpacker
            )
        ) {
            try planner.plan(request(in: fixture, capability: .prediffer))
        }
    }

    func testExplicitCanonicalExecutablePathAndSHAApprovalProducePinnedDirectPlan() throws {
        let fixture = try makeFixture()
        let aliasURL = fixture.root.appending(path: "reviewed-tool-alias")
        try FileManager.default.createSymbolicLink(
            at: aliasURL,
            withDestinationURL: fixture.executableURL
        )
        let policy = try ExternalToolPolicy(
            externalExecutableRules: [makeRule(fixture, executableURL: aliasURL)]
        )
        let configuredRule = try XCTUnwrap(policy.externalExecutableRules.first)
        let canonicalExecutableURL = fixture.executableURL.resolvingSymlinksInPath().standardizedFileURL

        XCTAssertEqual(configuredRule.executableURL, canonicalExecutableURL)
        XCTAssertEqual(configuredRule.approvedExecutableSHA256, digest(fixture.executableData))
        XCTAssertEqual(
            policy.decision(for: .unpacker),
            ExternalToolCapabilityDecision(
                capability: .unpacker,
                status: .supported,
                reason: .explicitExternalExecutableRuleConfigured
            )
        )

        let plan = try ExternalToolRequestPlanner(policy: policy).plan(request(in: fixture))
        XCTAssertEqual(plan.ruleIdentifier, "reviewed-tool")
        XCTAssertEqual(plan.capability, .unpacker)
        XCTAssertEqual(plan.invocationMethod, .directExecutable)
        XCTAssertEqual(plan.executableURL, canonicalExecutableURL)
        XCTAssertEqual(plan.executablePin.sourceURL, canonicalExecutableURL)
        XCTAssertEqual(plan.executablePin.identity.sha256, digest(fixture.executableData))
        XCTAssertEqual(plan.workingDirectoryURL, fixture.root.standardizedFileURL)
        XCTAssertEqual(plan.readScopes, [tree(fixture.root)])
        XCTAssertEqual(plan.writeScopes, [])
    }

    func testDigestMismatchMutationAndShebangAreRejected() throws {
        let mismatchFixture = try makeFixture()
        let mismatchedRule = makeRule(
            mismatchFixture,
            approvedExecutableSHA256: [UInt8](repeating: 0xA5, count: SHA256.Digest.byteCount)
        )
        assertPolicyError(
            .executableDoesNotMatchApprovedIdentity(mismatchFixture.executableURL.path)
        ) {
            try ExternalToolPolicy(externalExecutableRules: [mismatchedRule])
        }

        let mutationFixture = try makeFixture(data: Data("trusted!".utf8))
        let policy = try ExternalToolPolicy(
            externalExecutableRules: [makeRule(mutationFixture)]
        )
        _ = try ExternalToolRequestPlanner(policy: policy).plan(request(in: mutationFixture))
        let handle = try FileHandle(forWritingTo: mutationFixture.executableURL)
        try handle.write(contentsOf: Data("altered!".utf8))
        try handle.synchronize()
        try handle.close()
        assertPolicyError(.executableIdentityChanged(mutationFixture.executableURL.path)) {
            try ExternalToolRequestPlanner(policy: policy).plan(request(in: mutationFixture))
        }

        let scriptData = Data("#!/bin/sh\nexit 0\n".utf8)
        let scriptFixture = try makeFixture(data: scriptData)
        assertPolicyError(.executableScriptNotAllowed(scriptFixture.executableURL.path)) {
            try ExternalToolPolicy(externalExecutableRules: [makeRule(scriptFixture)])
        }
    }

    func testDigestMutationWithRestoredIdentityMetadataIsRejectedWhenSupported() throws {
        let fixture = try makeFixture(data: Data("trusted!".utf8))
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let planner = ExternalToolRequestPlanner(policy: policy)
        let originalPlan = try planner.plan(request(in: fixture))
        let identity = originalPlan.executablePin.identity
        let mutatedData = Data("altered!".utf8)
        XCTAssertEqual(mutatedData.count, fixture.executableData.count)
        XCTAssertNotEqual(digest(mutatedData), identity.sha256)

        let handle = try FileHandle(forWritingTo: fixture.executableURL)
        try handle.write(contentsOf: mutatedData)
        try handle.synchronize()
        try handle.close()
        guard restoreIdentityTimes(identity, on: fixture.executableURL) else {
            throw XCTSkip("Temporary filesystem cannot restore executable change-time metadata.")
        }

        let restored = try fileInformation(at: fixture.executableURL)
        guard metadata(of: restored, matches: identity) else {
            throw XCTSkip("Temporary filesystem did not preserve restored executable metadata.")
        }
        XCTAssertEqual(try Data(contentsOf: fixture.executableURL), mutatedData)
        assertPolicyError(.executableIdentityChanged(fixture.executableURL.path)) {
            try planner.plan(request(in: fixture))
        }
    }

    func testTrustedOwnershipUnsafeModesAndHardLinkWriteCombination() throws {
        let userFixture = try makeFixture()
        var userInformation = stat()
        XCTAssertEqual(
            userFixture.executableURL.path.withCString { Darwin.lstat($0, &userInformation) },
            0
        )
        XCTAssertEqual(userInformation.st_uid, Darwin.geteuid())
        _ = try ExternalToolPolicy(externalExecutableRules: [makeRule(userFixture)])

        let rootFixture = try makeFixture()
        let rootExecutableURL = URL(fileURLWithPath: "/bin/echo").resolvingSymlinksInPath()
        var rootInformation = stat()
        XCTAssertEqual(
            rootExecutableURL.path.withCString { Darwin.lstat($0, &rootInformation) },
            0
        )
        XCTAssertEqual(rootInformation.st_uid, 0)
        let rootRule = makeRule(
            rootFixture,
            executableURL: rootExecutableURL,
            approvedExecutableSHA256: try digest(of: rootExecutableURL)
        )
        _ = try ExternalToolPolicy(externalExecutableRules: [rootRule])

        let unsafeModeFixture = try makeFixture()
        try setPermissions(0o770, on: unsafeModeFixture.executableURL)
        assertPolicyError(.executableUnsafeMode(unsafeModeFixture.executableURL.path)) {
            try ExternalToolPolicy(externalExecutableRules: [makeRule(unsafeModeFixture)])
        }

        let unsafeAncestorFixture = try makeFixture()
        let unsafeDirectory = unsafeAncestorFixture.root.appending(
            path: "unsafe-ancestor",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: unsafeDirectory, withIntermediateDirectories: false)
        try setPermissions(0o770, on: unsafeDirectory)
        let nestedExecutable = unsafeDirectory.appending(path: "tool")
        try writeExecutable(unsafeAncestorFixture.executableData, to: nestedExecutable)
        let unsafeAncestorRule = makeRule(
            unsafeAncestorFixture,
            executableURL: nestedExecutable,
            approvedExecutableSHA256: digest(unsafeAncestorFixture.executableData)
        )
        assertPolicyError(.executableUntrustedAncestor(unsafeDirectory.path)) {
            try ExternalToolPolicy(externalExecutableRules: [unsafeAncestorRule])
        }

        let linkedFixture = try makeFixture()
        let secondLink = linkedFixture.root.appending(path: "second-link")
        try FileManager.default.linkItem(at: linkedFixture.executableURL, to: secondLink)
        _ = try ExternalToolPolicy(externalExecutableRules: [makeRule(linkedFixture)])
        let writeDirectory = linkedFixture.root.appending(
            path: "write-output",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: writeDirectory, withIntermediateDirectories: false)
        let linkedWriteRule = makeRule(
            linkedFixture,
            permittedWriteScopes: [tree(writeDirectory)]
        )
        assertPolicyError(.executableHasMultipleLinks(linkedFixture.executableURL.path)) {
            try ExternalToolPolicy(externalExecutableRules: [linkedWriteRule])
        }
    }

    func testMutatingExecutableAndAncestorACLsAreRejectedWhenSupported() throws {
        let executableFixture = try makeFixture()
        try addMutatingAllowACL(to: executableFixture.executableURL)
        assertPolicyError(.executableUnsafeACL(executableFixture.executableURL.path)) {
            try ExternalToolPolicy(externalExecutableRules: [makeRule(executableFixture)])
        }

        let ancestorFixture = try makeFixture()
        let ancestor = ancestorFixture.root.appending(
            path: "acl-ancestor",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: ancestor, withIntermediateDirectories: false)
        try setPermissions(0o700, on: ancestor)
        let nestedExecutable = ancestor.appending(path: "tool")
        try writeExecutable(ancestorFixture.executableData, to: nestedExecutable)
        try addMutatingAllowACL(to: ancestor)
        assertPolicyError(.executableUnsafeACL(ancestor.path)) {
            try ExternalToolPolicy(
                externalExecutableRules: [
                    makeRule(
                        ancestorFixture,
                        executableURL: nestedExecutable,
                        approvedExecutableSHA256: digest(ancestorFixture.executableData)
                    )
                ]
            )
        }
    }

    func testSingleLinkExecutableCannotOverlapPermittedWriteScope() throws {
        let fixture = try makeFixture()
        let information = try fileInformation(at: fixture.executableURL)
        XCTAssertEqual(information.st_nlink, 1)
        let overlappingRule = makeRule(
            fixture,
            permittedWriteScopes: [tree(fixture.root)]
        )

        assertPolicyError(.executableCoveredByWriteScope(fixture.executableURL.path)) {
            try ExternalToolPolicy(externalExecutableRules: [overlappingRule])
        }
    }

    func testExecutionPlanRequiresLibraryValidationIsolationAndProcessGroupContracts() throws {
        let fixture = try makeFixture()
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let plan = try ExternalToolRequestPlanner(policy: policy).plan(request(in: fixture))

        XCTAssertEqual(plan.executableLaunchPolicy, .privateImmutableCopyFromPinnedDescriptor)
        XCTAssertEqual(plan.libraryValidationPolicy, .required)
        XCTAssertEqual(plan.dynamicLoadPolicy, .defaultDeny)
        XCTAssertEqual(plan.isolationPolicy, .default)
        XCTAssertEqual(plan.isolationPolicy.network, .denied)
        XCTAssertEqual(plan.isolationPolicy.childProcesses, .denied)
        XCTAssertEqual(plan.isolationPolicy.interprocessCommunication, .denied)
        XCTAssertEqual(plan.standardInputPolicy, .nullDevice)
        XCTAssertEqual(plan.inheritedDescriptorPolicy, .closeAllExceptStandardStreams)
        XCTAssertEqual(plan.processGroupPolicy, .dedicatedProcessGroup)
        XCTAssertEqual(plan.terminationPolicy, .terminateThenKillProcessGroup)
        XCTAssertEqual(plan.outputDrainPolicy, .concurrentlyUntilEndOfFile)
    }

    func testExplicitAmbientAccessAndResourceBoundsArePropagatedWithoutWeakeningFixedContracts() throws {
        let fixture = try makeFixture()
        let isolation = ExternalToolIsolationPolicy(
            network: .allowed,
            childProcesses: .allowed,
            interprocessCommunication: .allowed
        )
        let limits = try ExternalToolInvocationLimits(
            timeoutSeconds: 0.25,
            standardOutputLimitBytes: 11,
            standardErrorLimitBytes: 13,
            combinedOutputLimitBytes: 17
        )
        let rule = makeRule(fixture, isolationPolicy: isolation, limits: limits)
        let policy = try ExternalToolPolicy(externalExecutableRules: [rule])
        let plan = try ExternalToolRequestPlanner(policy: policy).plan(request(in: fixture))

        XCTAssertEqual(plan.isolationPolicy, isolation)
        XCTAssertEqual(plan.timeoutSeconds, 0.25)
        XCTAssertEqual(plan.standardOutputLimitBytes, 11)
        XCTAssertEqual(plan.standardErrorLimitBytes, 13)
        XCTAssertEqual(plan.combinedOutputLimitBytes, 17)
        XCTAssertEqual(plan.libraryValidationPolicy, .required)
        XCTAssertEqual(plan.dynamicLoadPolicy, .defaultDeny)
        XCTAssertEqual(plan.processGroupPolicy, .dedicatedProcessGroup)

        assertInvalidLimit(named: "timeoutSeconds") {
            try ExternalToolInvocationLimits(timeoutSeconds: 0)
        }
        assertInvalidLimit(named: "timeoutSeconds") {
            try ExternalToolInvocationLimits(
                timeoutSeconds: ExternalToolInvocationLimits.hardMaximumTimeoutSeconds + 1
            )
        }
        assertInvalidLimit(named: "standardOutputLimitBytes") {
            try ExternalToolInvocationLimits(
                standardOutputLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes + 1
            )
        }
        assertInvalidLimit(named: "combinedOutputLimitBytes") {
            try ExternalToolInvocationLimits(
                standardOutputLimitBytes: 11,
                standardErrorLimitBytes: 13,
                combinedOutputLimitBytes: 12
            )
        }
        XCTAssertNoThrow(
            try ExternalToolInvocationLimits(
                timeoutSeconds: ExternalToolInvocationLimits.hardMaximumTimeoutSeconds,
                standardOutputLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes,
                standardErrorLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes,
                combinedOutputLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes
            )
        )
    }

    func testEachAmbientCapabilityRequiresItsOwnOptIn() throws {
        let fixture = try makeFixture()
        let oneHotPolicies = [
            ExternalToolIsolationPolicy(network: .allowed),
            ExternalToolIsolationPolicy(childProcesses: .allowed),
            ExternalToolIsolationPolicy(interprocessCommunication: .allowed)
        ]

        for isolationPolicy in oneHotPolicies {
            let policy = try ExternalToolPolicy(
                externalExecutableRules: [
                    makeRule(fixture, isolationPolicy: isolationPolicy)
                ]
            )
            let plan = try ExternalToolRequestPlanner(policy: policy).plan(request(in: fixture))
            XCTAssertEqual(plan.isolationPolicy, isolationPolicy)
            XCTAssertEqual(
                [
                    plan.isolationPolicy.network,
                    plan.isolationPolicy.childProcesses,
                    plan.isolationPolicy.interprocessCommunication
                ].filter { $0 == .allowed }.count,
                1
            )
        }
    }

    func testEveryInvocationLimitAcceptsBoundariesAndRejectsOutsideValues() throws {
        XCTAssertNoThrow(
            try ExternalToolInvocationLimits(
                maximumArgumentCount: 0,
                maximumArgumentUTF8Bytes: 1,
                maximumTotalArgumentUTF8Bytes: 1,
                maximumEnvironmentEntryCount: 0,
                maximumEnvironmentKeyUTF8Bytes: 1,
                maximumEnvironmentValueUTF8Bytes: 0,
                maximumTotalEnvironmentUTF8Bytes: 0,
                maximumScopeCount: 1,
                maximumPathUTF8Bytes: 1,
                maximumTotalPathUTF8Bytes: 1,
                timeoutSeconds: .leastNonzeroMagnitude,
                standardOutputLimitBytes: 0,
                standardErrorLimitBytes: 0,
                combinedOutputLimitBytes: 0
            )
        )
        XCTAssertNoThrow(
            try ExternalToolInvocationLimits(
                maximumArgumentCount: ExternalToolInvocationLimits.hardMaximumArgumentCount,
                maximumArgumentUTF8Bytes: ExternalToolInvocationLimits.hardMaximumArgumentUTF8Bytes,
                maximumTotalArgumentUTF8Bytes: ExternalToolInvocationLimits.hardMaximumTotalArgumentUTF8Bytes,
                maximumEnvironmentEntryCount: ExternalToolInvocationLimits.hardMaximumEnvironmentEntryCount,
                maximumEnvironmentKeyUTF8Bytes: 256,
                maximumEnvironmentValueUTF8Bytes: ExternalToolInvocationLimits.hardMaximumEnvironmentValueUTF8Bytes,
                maximumTotalEnvironmentUTF8Bytes: ExternalToolInvocationLimits.hardMaximumTotalEnvironmentUTF8Bytes,
                maximumScopeCount: ExternalToolInvocationLimits.hardMaximumScopeCount,
                maximumPathUTF8Bytes: ExternalToolInvocationLimits.hardMaximumPathUTF8Bytes,
                maximumTotalPathUTF8Bytes: ExternalToolInvocationLimits.hardMaximumTotalPathUTF8Bytes,
                timeoutSeconds: ExternalToolInvocationLimits.hardMaximumTimeoutSeconds,
                standardOutputLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes,
                standardErrorLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes,
                combinedOutputLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes
            )
        )

        assertInvalidLimit(named: "maximumArgumentCount") {
            try ExternalToolInvocationLimits(maximumArgumentCount: -1)
        }
        assertInvalidLimit(named: "maximumArgumentCount") {
            try ExternalToolInvocationLimits(
                maximumArgumentCount: ExternalToolInvocationLimits.hardMaximumArgumentCount + 1
            )
        }
        assertInvalidLimit(named: "maximumArgumentUTF8Bytes") {
            try ExternalToolInvocationLimits(maximumArgumentUTF8Bytes: 0)
        }
        assertInvalidLimit(named: "maximumArgumentUTF8Bytes") {
            try ExternalToolInvocationLimits(
                maximumArgumentUTF8Bytes: ExternalToolInvocationLimits.hardMaximumArgumentUTF8Bytes + 1,
                maximumTotalArgumentUTF8Bytes: ExternalToolInvocationLimits.hardMaximumTotalArgumentUTF8Bytes
            )
        }
        assertInvalidLimit(named: "maximumTotalArgumentUTF8Bytes") {
            try ExternalToolInvocationLimits(
                maximumArgumentUTF8Bytes: 2,
                maximumTotalArgumentUTF8Bytes: 1
            )
        }
        assertInvalidLimit(named: "maximumTotalArgumentUTF8Bytes") {
            try ExternalToolInvocationLimits(
                maximumTotalArgumentUTF8Bytes: ExternalToolInvocationLimits.hardMaximumTotalArgumentUTF8Bytes + 1
            )
        }
        assertInvalidLimit(named: "maximumEnvironmentEntryCount") {
            try ExternalToolInvocationLimits(maximumEnvironmentEntryCount: -1)
        }
        assertInvalidLimit(named: "maximumEnvironmentEntryCount") {
            try ExternalToolInvocationLimits(
                maximumEnvironmentEntryCount: ExternalToolInvocationLimits.hardMaximumEnvironmentEntryCount + 1
            )
        }
        assertInvalidLimit(named: "maximumEnvironmentKeyUTF8Bytes") {
            try ExternalToolInvocationLimits(maximumEnvironmentKeyUTF8Bytes: 0)
        }
        assertInvalidLimit(named: "maximumEnvironmentKeyUTF8Bytes") {
            try ExternalToolInvocationLimits(maximumEnvironmentKeyUTF8Bytes: 257)
        }
        assertInvalidLimit(named: "maximumEnvironmentValueUTF8Bytes") {
            try ExternalToolInvocationLimits(maximumEnvironmentValueUTF8Bytes: -1)
        }
        assertInvalidLimit(named: "maximumEnvironmentValueUTF8Bytes") {
            try ExternalToolInvocationLimits(
                maximumEnvironmentValueUTF8Bytes: ExternalToolInvocationLimits.hardMaximumEnvironmentValueUTF8Bytes + 1
            )
        }
        assertInvalidLimit(named: "maximumTotalEnvironmentUTF8Bytes") {
            try ExternalToolInvocationLimits(maximumTotalEnvironmentUTF8Bytes: -1)
        }
        assertInvalidLimit(named: "maximumTotalEnvironmentUTF8Bytes") {
            try ExternalToolInvocationLimits(
                maximumTotalEnvironmentUTF8Bytes: ExternalToolInvocationLimits.hardMaximumTotalEnvironmentUTF8Bytes + 1
            )
        }
        assertInvalidLimit(named: "maximumScopeCount") {
            try ExternalToolInvocationLimits(maximumScopeCount: 0)
        }
        assertInvalidLimit(named: "maximumScopeCount") {
            try ExternalToolInvocationLimits(
                maximumScopeCount: ExternalToolInvocationLimits.hardMaximumScopeCount + 1
            )
        }
        assertInvalidLimit(named: "maximumPathUTF8Bytes") {
            try ExternalToolInvocationLimits(maximumPathUTF8Bytes: 0)
        }
        assertInvalidLimit(named: "maximumPathUTF8Bytes") {
            try ExternalToolInvocationLimits(
                maximumPathUTF8Bytes: ExternalToolInvocationLimits.hardMaximumPathUTF8Bytes + 1,
                maximumTotalPathUTF8Bytes: ExternalToolInvocationLimits.hardMaximumTotalPathUTF8Bytes
            )
        }
        assertInvalidLimit(named: "maximumTotalPathUTF8Bytes") {
            try ExternalToolInvocationLimits(
                maximumPathUTF8Bytes: 2,
                maximumTotalPathUTF8Bytes: 1
            )
        }
        assertInvalidLimit(named: "maximumTotalPathUTF8Bytes") {
            try ExternalToolInvocationLimits(
                maximumTotalPathUTF8Bytes: ExternalToolInvocationLimits.hardMaximumTotalPathUTF8Bytes + 1
            )
        }
        for invalidTimeout in [0, -1, .infinity, .nan] {
            assertInvalidLimit(named: "timeoutSeconds") {
                try ExternalToolInvocationLimits(timeoutSeconds: invalidTimeout)
            }
        }
        assertInvalidLimit(named: "standardOutputLimitBytes") {
            try ExternalToolInvocationLimits(standardOutputLimitBytes: -1)
        }
        assertInvalidLimit(named: "standardOutputLimitBytes") {
            try ExternalToolInvocationLimits(
                standardOutputLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes + 1
            )
        }
        assertInvalidLimit(named: "standardErrorLimitBytes") {
            try ExternalToolInvocationLimits(standardErrorLimitBytes: -1)
        }
        assertInvalidLimit(named: "standardErrorLimitBytes") {
            try ExternalToolInvocationLimits(
                standardErrorLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes + 1
            )
        }
        assertInvalidLimit(named: "combinedOutputLimitBytes") {
            try ExternalToolInvocationLimits(
                standardOutputLimitBytes: 1,
                combinedOutputLimitBytes: 0
            )
        }
        assertInvalidLimit(named: "combinedOutputLimitBytes") {
            try ExternalToolInvocationLimits(
                combinedOutputLimitBytes: ExternalToolInvocationLimits.hardMaximumOutputBytes + 1
            )
        }
    }

    func testRequestResourceLimitsAcceptExactBoundariesAndRejectOneByteOrEntryOver() throws {
        let fixture = try makeFixture()

        let argumentLimits = try ExternalToolInvocationLimits(
            maximumArgumentCount: 2,
            maximumArgumentUTF8Bytes: 3,
            maximumTotalArgumentUTF8Bytes: 5
        )
        let argumentPlanner = try planner(
            fixture,
            argumentConstraints: [.value, .value],
            limits: argumentLimits
        )
        XCTAssertNoThrow(
            try argumentPlanner.plan(request(in: fixture, arguments: ["abc", "de"]))
        )
        assertPolicyError(.tooManyArguments(maximum: 2)) {
            try argumentPlanner.plan(request(in: fixture, arguments: ["a", "b", "c"]))
        }
        assertPolicyError(.argumentTooLarge(index: 0, maximumUTF8Bytes: 3)) {
            try argumentPlanner.plan(request(in: fixture, arguments: ["abcd", "e"]))
        }
        assertPolicyError(.totalArgumentsTooLarge(maximumUTF8Bytes: 5)) {
            try argumentPlanner.plan(request(in: fixture, arguments: ["abc", "def"]))
        }

        let environmentLimits = try ExternalToolInvocationLimits(
            maximumEnvironmentEntryCount: 2,
            maximumEnvironmentKeyUTF8Bytes: 3,
            maximumEnvironmentValueUTF8Bytes: 3,
            maximumTotalEnvironmentUTF8Bytes: 11
        )
        let environmentPlanner = try planner(
            fixture,
            allowedEnvironmentKeys: ["A", "BBB"],
            limits: environmentLimits
        )
        XCTAssertNoThrow(
            try environmentPlanner.plan(
                request(in: fixture, environment: ["A": "abc", "BBB": ""])
            )
        )
        assertPolicyError(.tooManyEnvironmentEntries(maximum: 2)) {
            try environmentPlanner.plan(
                request(in: fixture, environment: ["A": "a", "BBB": "b", "C": "c"])
            )
        }
        assertPolicyError(.environmentValueTooLarge(key: "A", maximumUTF8Bytes: 3)) {
            try environmentPlanner.plan(request(in: fixture, environment: ["A": "abcd"]))
        }
        assertPolicyError(.totalEnvironmentTooLarge(maximumUTF8Bytes: 11)) {
            try environmentPlanner.plan(
                request(in: fixture, environment: ["A": "abc", "BBB": "d"])
            )
        }
        let oversizedKeyRule = makeRule(
            fixture,
            allowedEnvironmentKeys: ["FOUR"],
            limits: environmentLimits
        )
        assertPolicyError(.environmentKeyTooLarge("FOUR", maximumUTF8Bytes: 3)) {
            try ExternalToolPolicy(externalExecutableRules: [oversizedKeyRule])
        }

        let writeDirectory = fixture.root.appending(
            path: "scope-output",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: writeDirectory, withIntermediateDirectories: false)
        let scopeLimits = try ExternalToolInvocationLimits(maximumScopeCount: 3)
        let scopePlanner = try planner(
            fixture,
            permittedWriteScopes: [exact(writeDirectory)],
            limits: scopeLimits
        )
        XCTAssertNoThrow(
            try scopePlanner.plan(
                request(
                    in: fixture,
                    readScopes: [tree(fixture.root), exact(fixture.root)],
                    writeScopes: [exact(writeDirectory)]
                )
            )
        )
        assertPolicyError(.tooManyScopes(maximum: 3)) {
            try scopePlanner.plan(
                request(
                    in: fixture,
                    readScopes: [tree(fixture.root), exact(fixture.root), exact(writeDirectory)],
                    writeScopes: [exact(writeDirectory)]
                )
            )
        }

        let boundaryURLs = [fixture.executableURL, fixture.root]
        let boundaryPathBytes = boundaryURLs.map(maximumSuppliedOrResolvedPathBytes).max()!
        let boundaryAggregateBytes =
            boundaryURLs.reduce(0) {
                $0 + maximumSuppliedOrResolvedPathBytes($1)
            } * 2
        let pathLimits = try ExternalToolInvocationLimits(
            maximumPathUTF8Bytes: boundaryPathBytes,
            maximumTotalPathUTF8Bytes: boundaryAggregateBytes
        )
        let pathPlanner = try planner(fixture, limits: pathLimits)
        XCTAssertNoThrow(try pathPlanner.plan(request(in: fixture)))
        let oversizedPath = fixture.root.appending(
            path: String(repeating: "x", count: boundaryPathBytes + 1)
        )
        assertPolicyError(.pathTooLarge(purpose: .readScope, maximumUTF8Bytes: boundaryPathBytes)) {
            try pathPlanner.plan(
                request(in: fixture, readScopes: [tree(fixture.root), exact(oversizedPath)])
            )
        }
    }

    func testLexicalTraversalAndPathByteDerivedAggregateBudgetsAreRejectedBeforeExpansion() throws {
        let fixture = try makeFixture()
        let allowedDirectory = fixture.root.appending(
            path: "allowed",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: allowedDirectory,
            withIntermediateDirectories: false
        )
        let outsideURL = fixture.root.appending(path: "outside.txt")
        try Data("outside".utf8).write(to: outsideURL)
        let escapingURL = URL(fileURLWithPath: allowedDirectory.path + "/../outside.txt")
        let scopedRule = makeRule(
            fixture,
            permittedWorkingDirectories: [exact(allowedDirectory)],
            permittedReadScopes: [tree(allowedDirectory)]
        )
        let scopedPolicy = try ExternalToolPolicy(externalExecutableRules: [scopedRule])
        let scopedPlanner = ExternalToolRequestPlanner(policy: scopedPolicy)
        let escapingScopeRequest = ExternalToolRequest(
            ruleIdentifier: "reviewed-tool",
            capability: .unpacker,
            workingDirectoryURL: allowedDirectory,
            readScopes: [exact(allowedDirectory), exact(escapingURL)]
        )
        assertPolicyError(.readScopeNotPermitted(escapingURL.path)) {
            try scopedPlanner.plan(escapingScopeRequest)
        }

        let argumentRule = makeRule(
            fixture,
            permittedWorkingDirectories: [exact(allowedDirectory)],
            permittedReadScopes: [tree(allowedDirectory)],
            argumentConstraints: [.readPath]
        )
        let argumentPolicy = try ExternalToolPolicy(externalExecutableRules: [argumentRule])
        let traversalArgumentRequest = ExternalToolRequest(
            ruleIdentifier: "reviewed-tool",
            capability: .unpacker,
            workingDirectoryURL: allowedDirectory,
            arguments: [allowedDirectory.path + "/../outside.txt"],
            readScopes: [tree(allowedDirectory)]
        )
        assertPolicyError(.argumentConstraintViolation(index: 0)) {
            try ExternalToolRequestPlanner(policy: argumentPolicy).plan(traversalArgumentRequest)
        }

        let rulePaths = [fixture.executableURL, fixture.root, fixture.root]
        let exactAggregateBytes = rulePaths.reduce(0) { $0 + $1.path.utf8.count }
        let maximumPathBytes = rulePaths.map(maximumSuppliedOrResolvedPathBytes).max()!
        let exactAggregateLimits = try ExternalToolInvocationLimits(
            maximumPathUTF8Bytes: maximumPathBytes,
            maximumTotalPathUTF8Bytes: exactAggregateBytes
        )
        XCTAssertNoThrow(
            try ExternalToolPolicy(
                externalExecutableRules: [makeRule(fixture, limits: exactAggregateLimits)]
            )
        )
        let overAggregateLimits = try ExternalToolInvocationLimits(
            maximumPathUTF8Bytes: maximumPathBytes,
            maximumTotalPathUTF8Bytes: exactAggregateBytes - 1
        )
        assertPolicyError(.totalPathsTooLarge(maximumUTF8Bytes: exactAggregateBytes - 1)) {
            try ExternalToolPolicy(
                externalExecutableRules: [makeRule(fixture, limits: overAggregateLimits)]
            )
        }

        let nonexistentURL = fixture.root.appending(path: "nonexistent-request-scope")
        let requestAggregateBytes =
            fixture.executableURL.path.utf8.count
            + fixture.root.path.utf8.count * 2
            + nonexistentURL.path.utf8.count
        XCTAssertGreaterThanOrEqual(requestAggregateBytes - 1, exactAggregateBytes)
        let nonexistentLimits = try ExternalToolInvocationLimits(
            maximumPathUTF8Bytes: max(maximumPathBytes, nonexistentURL.path.utf8.count),
            maximumTotalPathUTF8Bytes: requestAggregateBytes - 1
        )
        let nonexistentPolicy = try ExternalToolPolicy(
            externalExecutableRules: [makeRule(fixture, limits: nonexistentLimits)]
        )
        let nonexistentRequest = request(
            in: fixture,
            readScopes: [tree(fixture.root), exact(nonexistentURL)]
        )
        assertPolicyError(.totalPathsTooLarge(maximumUTF8Bytes: requestAggregateBytes - 1)) {
            try ExternalToolRequestPlanner(policy: nonexistentPolicy).plan(nonexistentRequest)
        }
    }

    func testSymlinkTreeExactAndRootScopeNegativesFailClosed() throws {
        let symlinkFixture = try makeFixture()
        let allowedDirectory = symlinkFixture.root.appending(
            path: "allowed",
            directoryHint: .isDirectory
        )
        let outsideDirectory = symlinkFixture.root.appending(
            path: "outside",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: allowedDirectory, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: false)
        let outsideFile = outsideDirectory.appending(path: "secret")
        try Data("secret".utf8).write(to: outsideFile)
        let link = allowedDirectory.appending(path: "escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)
        let symlinkRule = makeRule(
            symlinkFixture,
            permittedWorkingDirectories: [exact(allowedDirectory)],
            permittedReadScopes: [tree(allowedDirectory)]
        )
        let symlinkPolicy = try ExternalToolPolicy(externalExecutableRules: [symlinkRule])
        let symlinkRequest = ExternalToolRequest(
            ruleIdentifier: "reviewed-tool",
            capability: .unpacker,
            workingDirectoryURL: allowedDirectory,
            readScopes: [tree(allowedDirectory), exact(link)]
        )
        assertPolicyError(.readScopeNotPermitted(outsideFile.path)) {
            try ExternalToolRequestPlanner(policy: symlinkPolicy).plan(symlinkRequest)
        }

        let treeFixture = try makeFixture()
        let fileURL = treeFixture.root.appending(path: "ordinary-file")
        try Data("file".utf8).write(to: fileURL)
        assertPolicyError(.directoryTreeScopeNotDirectory(fileURL.path)) {
            try ExternalToolPolicy(
                externalExecutableRules: [
                    makeRule(treeFixture, permittedReadScopes: [tree(fileURL)])
                ]
            )
        }

        let exactFixture = try makeFixture()
        let exactDirectory = exactFixture.root.appending(
            path: "exact",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: exactDirectory, withIntermediateDirectories: false)
        let descendant = exactDirectory.appending(path: "descendant")
        try Data("descendant".utf8).write(to: descendant)
        let exactRule = makeRule(
            exactFixture,
            permittedWorkingDirectories: [exact(exactDirectory)],
            permittedReadScopes: [exact(exactDirectory)]
        )
        let exactPolicy = try ExternalToolPolicy(externalExecutableRules: [exactRule])
        let exactRequest = ExternalToolRequest(
            ruleIdentifier: "reviewed-tool",
            capability: .unpacker,
            workingDirectoryURL: exactDirectory,
            readScopes: [exact(exactDirectory), exact(descendant)]
        )
        assertPolicyError(.readScopeNotPermitted(descendant.path)) {
            try ExternalToolRequestPlanner(policy: exactPolicy).plan(exactRequest)
        }

        let rootFixture = try makeFixture()
        assertPolicyError(.rootDirectoryTreeNotAllowed) {
            try ExternalToolPolicy(
                externalExecutableRules: [
                    makeRule(rootFixture, permittedReadScopes: [tree(URL(fileURLWithPath: "/"))])
                ]
            )
        }
    }

    func testDYLDEnvironmentKeysArePermanentlyDeniedInRulesAndRequests() throws {
        let fixture = try makeFixture()
        let deniedRule = makeRule(fixture, allowedEnvironmentKeys: ["dyld_library_path"])
        assertPolicyError(.environmentKeyPermanentlyDenied("dyld_library_path")) {
            try ExternalToolPolicy(externalExecutableRules: [deniedRule])
        }

        let safeRule = makeRule(fixture, allowedEnvironmentKeys: ["SAFE_VALUE"])
        let policy = try ExternalToolPolicy(externalExecutableRules: [safeRule])
        let deniedRequest = request(
            in: fixture,
            environment: ["DYLD_INSERT_LIBRARIES": "/tmp/injected.dylib"]
        )
        assertPolicyError(.environmentKeyPermanentlyDenied("DYLD_INSERT_LIBRARIES")) {
            try ExternalToolRequestPlanner(policy: policy).plan(deniedRequest)
        }
    }

    func testUnknownEnvironmentKeyAndEnvironmentNULAreRejectedExactly() throws {
        let fixture = try makeFixture()
        let policy = try ExternalToolPolicy(
            externalExecutableRules: [
                makeRule(fixture, allowedEnvironmentKeys: ["KNOWN_KEY"])
            ]
        )
        let planner = ExternalToolRequestPlanner(policy: policy)

        assertPolicyError(.environmentKeyNotAllowed("UNKNOWN_KEY")) {
            try planner.plan(request(in: fixture, environment: ["UNKNOWN_KEY": "value"]))
        }
        assertPolicyError(.environmentValueContainsNull(key: "KNOWN_KEY")) {
            try planner.plan(request(in: fixture, environment: ["KNOWN_KEY": "left\0right"]))
        }
    }

    func testOpaqueValueAllowsEmbeddedEqualsButRejectsOptionsAndResponseFiles() throws {
        let fixture = try makeFixture()
        let rule = makeRule(
            fixture,
            allowedEnvironmentKeys: ["SAFE_VALUE"],
            argumentConstraints: [.value, .exact("--policy-authored"), .oneOf(["fast", "safe"])]
        )
        let policy = try ExternalToolPolicy(externalExecutableRules: [rule])
        let planner = ExternalToolRequestPlanner(policy: policy)
        let acceptedRequest = request(
            in: fixture,
            arguments: ["name=value", "--policy-authored", "safe"],
            environment: ["SAFE_VALUE": "left=right"]
        )
        let plan = try planner.plan(acceptedRequest)

        XCTAssertEqual(plan.arguments, acceptedRequest.arguments)
        XCTAssertEqual(plan.environmentDictionary, ["SAFE_VALUE": "left=right"])

        for deniedValue in ["-untrusted-option", "@response-file", "-"] {
            let deniedRequest = request(
                in: fixture,
                arguments: [deniedValue, "--policy-authored", "fast"],
                environment: ["SAFE_VALUE": "allowed"]
            )
            assertPolicyError(.argumentConstraintViolation(index: 0)) {
                try planner.plan(deniedRequest)
            }
        }
    }

    func testExactAndOneOfWrongValuesAndArgumentNULAreRejectedExactly() throws {
        let fixture = try makeFixture()
        let rule = makeRule(
            fixture,
            argumentConstraints: [.exact("--reviewed"), .oneOf(["fast", "safe"]), .value]
        )
        let planner = ExternalToolRequestPlanner(
            policy: try ExternalToolPolicy(externalExecutableRules: [rule])
        )
        let invalidCases: [([String], ExternalToolPolicyError)] = [
            (["--wrong", "fast", "value"], .argumentConstraintViolation(index: 0)),
            (["--reviewed", "unsafe", "value"], .argumentConstraintViolation(index: 1)),
            (["--reviewed", "safe", "left\0right"], .argumentContainsNull(index: 2))
        ]

        for (arguments, expectedError) in invalidCases {
            assertPolicyError(expectedError) {
                try planner.plan(request(in: fixture, arguments: arguments))
            }
        }
    }

    func testARGMAXRejectsCombinedProcessInputBelowPolicyTotals() throws {
        let configuredMaximum = Darwin.sysconf(_SC_ARG_MAX)
        guard configuredMaximum > 8_192 else {
            throw XCTSkip("ARG_MAX is unavailable or too small for deterministic process-input coverage.")
        }
        let maximum = Int(configuredMaximum) - min(4_096, Int(configuredMaximum))
        let fixture = try makeFixture()
        let executableBytes = fixture.executableURL.path.utf8.count + 1
        let maximumArgumentBytes = ExternalToolInvocationLimits.hardMaximumArgumentUTF8Bytes
        let argumentCount = max(1, (maximum - executableBytes) / maximumArgumentBytes + 1)
        let pointerBytes = (argumentCount + 3) * MemoryLayout<UnsafeRawPointer?>.stride
        let totalArgumentBytes = maximum - executableBytes - pointerBytes - argumentCount + 1
        guard argumentCount <= ExternalToolInvocationLimits.hardMaximumArgumentCount,
            totalArgumentBytes > 0,
            totalArgumentBytes <= ExternalToolInvocationLimits.hardMaximumTotalArgumentUTF8Bytes,
            totalArgumentBytes <= argumentCount * maximumArgumentBytes
        else {
            throw XCTSkip("ARG_MAX cannot be reached within policy hard argument bounds.")
        }
        var remainingBytes = totalArgumentBytes
        let arguments = (0..<argumentCount).map { _ -> String in
            let byteCount = min(maximumArgumentBytes, remainingBytes)
            remainingBytes -= byteCount
            return String(repeating: "a", count: byteCount)
        }
        XCTAssertEqual(remainingBytes, 0)
        let limits = try ExternalToolInvocationLimits(
            maximumArgumentCount: argumentCount,
            maximumArgumentUTF8Bytes: maximumArgumentBytes,
            maximumTotalArgumentUTF8Bytes: totalArgumentBytes
        )
        let policy = try ExternalToolPolicy(
            externalExecutableRules: [
                makeRule(
                    fixture,
                    argumentConstraints: [ExternalToolArgumentConstraint](
                        repeating: .value,
                        count: argumentCount
                    ),
                    limits: limits
                )
            ]
        )

        assertPolicyError(.processInputTooLarge(maximumBytes: maximum)) {
            try ExternalToolRequestPlanner(policy: policy).plan(
                request(in: fixture, arguments: arguments)
            )
        }
    }

    func testRuleCountHardCapIsEnforcedBeforeRuleValidation() throws {
        let fixture = try makeFixture()
        let rule = makeRule(fixture, identifier: "invalid identifier")
        let rules = [ExternalToolExecutableRule](
            repeating: rule,
            count: ExternalToolExecutableRule.maximumRuleCount + 1
        )

        assertPolicyError(
            .tooManyRules(maximum: ExternalToolExecutableRule.maximumRuleCount)
        ) {
            try ExternalToolPolicy(externalExecutableRules: rules)
        }
    }

    func testPathReplacementLeavesPinnedDescriptorOnOriginalBytes() throws {
        let fixture = try makeFixture(data: Data("original!".utf8))
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let originalPlan = try ExternalToolRequestPlanner(policy: policy).plan(request(in: fixture))
        let replacementData = Data("replaced!".utf8)
        XCTAssertEqual(replacementData.count, fixture.executableData.count)
        let replacementURL = fixture.root.appending(path: "replacement")
        try writeExecutable(replacementData, to: replacementURL)
        XCTAssertEqual(
            replacementURL.path.withCString { replacementPath in
                fixture.executableURL.path.withCString { executablePath in
                    Darwin.rename(replacementPath, executablePath)
                }
            },
            0
        )
        XCTAssertEqual(try Data(contentsOf: fixture.executableURL), replacementData)

        let descriptor = try originalPlan.executablePin.duplicateReadOnlyFileDescriptor()
        defer { Darwin.close(descriptor) }
        XCTAssertEqual(try readAll(from: descriptor), fixture.executableData)
        assertPolicyError(.executableIdentityChanged(fixture.executableURL.path)) {
            try ExternalToolRequestPlanner(policy: policy).plan(request(in: fixture))
        }
    }

    func testPinnedDescriptorHashesAndExposesExactlyTheStatSize() throws {
        let byteCount = 64 * 1_024 + 17
        let executableData = Data((0..<byteCount).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let fixture = try makeFixture(data: executableData)
        let approvedDigest = digest(executableData)
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let plan = try ExternalToolRequestPlanner(policy: policy).plan(request(in: fixture))

        XCTAssertEqual(plan.executablePin.identity.size, Int64(byteCount))
        XCTAssertEqual(plan.executablePin.identity.sha256, approvedDigest)
        let descriptor = try plan.executablePin.duplicateReadOnlyFileDescriptor()
        defer { Darwin.close(descriptor) }
        XCTAssertNotEqual(Darwin.fcntl(descriptor, F_GETFD) & FD_CLOEXEC, 0)
        XCTAssertEqual(Darwin.fcntl(descriptor, F_GETFL) & O_ACCMODE, O_RDONLY)
        let pinnedData = try readAll(from: descriptor)
        XCTAssertEqual(pinnedData.count, byteCount)
        XCTAssertEqual(pinnedData, executableData)
        XCTAssertEqual(digest(pinnedData), approvedDigest)
    }

    private func makeFixture(data: Data = Data([0x7F, 0x4D, 0x41, 0x43, 0x4D, 0x45, 0x52, 0x47, 0x45])) throws -> Fixture {
        let temporaryDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        try requireTrustedTemporaryDirectoryAncestors(temporaryDirectory)
        let root = temporaryDirectory.appending(
            path: "MacMergeExternalToolPolicyTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try setPermissions(0o700, on: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let executableURL = root.appending(path: "reviewed-tool")
        try writeExecutable(data, to: executableURL)
        return Fixture(root: root, executableURL: executableURL, executableData: data)
    }

    private func writeExecutable(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        try setPermissions(0o700, on: url)
    }

    private func setPermissions(_ permissions: Int, on url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }

    private func makeRule(
        _ fixture: Fixture,
        identifier: String = "reviewed-tool",
        capability: ExternalToolCapability = .unpacker,
        executableURL: URL? = nil,
        approvedExecutableSHA256: [UInt8]? = nil,
        permittedWorkingDirectories: [ExternalToolPathScope]? = nil,
        permittedReadScopes: [ExternalToolPathScope]? = nil,
        permittedWriteScopes: [ExternalToolPathScope] = [],
        allowedEnvironmentKeys: [String] = [],
        argumentConstraints: [ExternalToolArgumentConstraint] = [],
        isolationPolicy: ExternalToolIsolationPolicy = .default,
        limits: ExternalToolInvocationLimits = .default
    ) -> ExternalToolExecutableRule {
        ExternalToolExecutableRule(
            identifier: identifier,
            capability: capability,
            executableURL: executableURL ?? fixture.executableURL,
            approvedExecutableSHA256: approvedExecutableSHA256 ?? digest(fixture.executableData),
            permittedWorkingDirectories: permittedWorkingDirectories ?? [exact(fixture.root)],
            permittedReadScopes: permittedReadScopes ?? [tree(fixture.root)],
            permittedWriteScopes: permittedWriteScopes,
            allowedEnvironmentKeys: allowedEnvironmentKeys,
            argumentConstraints: argumentConstraints,
            isolationPolicy: isolationPolicy,
            limits: limits
        )
    }

    private func request(
        in fixture: Fixture,
        ruleIdentifier: String = "reviewed-tool",
        capability: ExternalToolCapability = .unpacker,
        arguments: [String] = [],
        environment: [String: String] = [:],
        readScopes: [ExternalToolPathScope]? = nil,
        writeScopes: [ExternalToolPathScope] = []
    ) -> ExternalToolRequest {
        ExternalToolRequest(
            ruleIdentifier: ruleIdentifier,
            capability: capability,
            workingDirectoryURL: fixture.root,
            arguments: arguments,
            environment: environment,
            readScopes: readScopes ?? [tree(fixture.root)],
            writeScopes: writeScopes
        )
    }

    private func request(capability: ExternalToolCapability) -> ExternalToolRequest {
        ExternalToolRequest(
            ruleIdentifier: "missing-rule",
            capability: capability,
            workingDirectoryURL: URL(fileURLWithPath: "/"),
            readScopes: []
        )
    }

    private func exact(_ url: URL) -> ExternalToolPathScope {
        ExternalToolPathScope(url: url, kind: .exactItem)
    }

    private func tree(_ url: URL) -> ExternalToolPathScope {
        ExternalToolPathScope(url: url, kind: .directoryTree)
    }

    private func maximumSuppliedOrResolvedPathBytes(_ url: URL) -> Int {
        let suppliedCount = url.path.utf8.count
        guard let pointer = url.path.withCString({ Darwin.realpath($0, nil) }) else {
            return suppliedCount
        }
        defer { Darwin.free(pointer) }
        return max(suppliedCount, String(cString: pointer).utf8.count)
    }

    private func planner(
        _ fixture: Fixture,
        permittedWriteScopes: [ExternalToolPathScope] = [],
        allowedEnvironmentKeys: [String] = [],
        argumentConstraints: [ExternalToolArgumentConstraint] = [],
        limits: ExternalToolInvocationLimits
    ) throws -> ExternalToolRequestPlanner {
        let rule = makeRule(
            fixture,
            permittedWriteScopes: permittedWriteScopes,
            allowedEnvironmentKeys: allowedEnvironmentKeys,
            argumentConstraints: argumentConstraints,
            limits: limits
        )
        return ExternalToolRequestPlanner(
            policy: try ExternalToolPolicy(externalExecutableRules: [rule])
        )
    }

    private func digest(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private func digest(of url: URL) throws -> [UInt8] {
        digest(try Data(contentsOf: url))
    }

    private func fileInformation(at url: URL) throws -> stat {
        var information = stat()
        guard url.path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return information
    }

    private func metadata(
        of information: stat,
        matches identity: ExternalToolExecutableIdentity
    ) -> Bool {
        UInt64(information.st_dev) == identity.device
            && UInt64(information.st_ino) == identity.inode
            && information.st_gen == identity.generation
            && information.st_size == identity.size
            && Int64(information.st_mtimespec.tv_sec) == identity.modificationTimeSeconds
            && Int64(information.st_mtimespec.tv_nsec) == identity.modificationTimeNanoseconds
            && Int64(information.st_ctimespec.tv_sec) == identity.changeTimeSeconds
            && Int64(information.st_ctimespec.tv_nsec) == identity.changeTimeNanoseconds
    }

    private func restoreIdentityTimes(
        _ identity: ExternalToolExecutableIdentity,
        on url: URL
    ) -> Bool {
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = UInt32(ATTR_CMN_MODTIME | ATTR_CMN_CHGTIME)
        var times = [
            timespec(
                tv_sec: Int(identity.modificationTimeSeconds),
                tv_nsec: Int(identity.modificationTimeNanoseconds)
            ),
            timespec(
                tv_sec: Int(identity.changeTimeSeconds),
                tv_nsec: Int(identity.changeTimeNanoseconds)
            )
        ]
        return url.path.withCString { path in
            Darwin.setattrlist(path, &attributes, &times, MemoryLayout<timespec>.stride * times.count, 0) == 0
        }
    }

    private func addMutatingAllowACL(to url: URL) throws {
        guard let initialACL = Darwin.acl_init(1) else {
            throw XCTSkip("Temporary filesystem does not support extended ACL creation.")
        }
        var acl: acl_t? = initialACL
        defer {
            if let acl {
                Darwin.acl_free(UnsafeMutableRawPointer(acl))
            }
        }
        var entry: acl_entry_t?
        guard Darwin.acl_create_entry(&acl, &entry) == 0, let entry else {
            throw XCTSkip("Temporary filesystem does not support extended ACL entries.")
        }
        var qualifier: uuid_t = (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
        guard Darwin.acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) == 0,
            Darwin.acl_set_qualifier(entry, &qualifier) == 0
        else {
            throw XCTSkip("Temporary filesystem does not accept extended ACL qualifiers.")
        }
        var permissions: acl_permset_t?
        guard Darwin.acl_get_permset(entry, &permissions) == 0,
            let permissions,
            Darwin.acl_clear_perms(permissions) == 0,
            Darwin.acl_add_perm(permissions, ACL_WRITE_DATA) == 0,
            Darwin.acl_set_permset(entry, permissions) == 0,
            let acl,
            url.path.withCString({ Darwin.acl_set_file($0, ACL_TYPE_EXTENDED, acl) }) == 0
        else {
            throw XCTSkip("Temporary filesystem does not support mutating extended ACLs.")
        }
    }

    private func requireTrustedTemporaryDirectoryAncestors(_ directory: URL) throws {
        var ancestor = directory.standardizedFileURL
        let currentUser = Darwin.geteuid()
        while true {
            let information = try fileInformation(at: ancestor)
            guard information.st_uid == 0 || information.st_uid == currentUser,
                information.st_mode & S_IWGRP == 0,
                information.st_mode & S_IWOTH == 0,
                try !hasMutatingAllowACL(at: ancestor)
            else {
                throw XCTSkip("Temporary directory ancestry is not trusted by external-tool policy.")
            }
            if ancestor.path == "/" { return }
            ancestor.deleteLastPathComponent()
        }
    }

    private func hasMutatingAllowACL(at url: URL) throws -> Bool {
        errno = 0
        guard let acl = url.path.withCString({ Darwin.acl_get_file($0, ACL_TYPE_EXTENDED) }) else {
            if errno == ENOENT { return false }
            throw XCTSkip("Temporary directory ACLs cannot be inspected deterministically.")
        }
        defer { Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        var entryID = ACL_FIRST_ENTRY.rawValue
        while Darwin.acl_get_entry(acl, entryID, &entry) == 0 {
            entryID = ACL_NEXT_ENTRY.rawValue
            guard let entry else { continue }
            var tag = ACL_UNDEFINED_TAG
            guard Darwin.acl_get_tag_type(entry, &tag) == 0 else {
                throw XCTSkip("Temporary directory ACL tags cannot be inspected deterministically.")
            }
            guard tag == ACL_EXTENDED_ALLOW else { continue }
            var permissions: acl_permset_t?
            guard Darwin.acl_get_permset(entry, &permissions) == 0, let permissions else {
                throw XCTSkip("Temporary directory ACL permissions cannot be inspected deterministically.")
            }
            let mutatingPermissions = [
                ACL_WRITE_DATA,
                ACL_DELETE,
                ACL_APPEND_DATA,
                ACL_DELETE_CHILD,
                ACL_WRITE_ATTRIBUTES,
                ACL_WRITE_EXTATTRIBUTES,
                ACL_WRITE_SECURITY,
                ACL_CHANGE_OWNER
            ]
            if mutatingPermissions.contains(where: { Darwin.acl_get_perm_np(permissions, $0) == 1 }) {
                return true
            }
        }
        guard errno == 0 || errno == EINVAL else {
            throw XCTSkip("Temporary directory ACLs cannot be inspected deterministically.")
        }
        return false
    }

    private func readAll(from descriptor: Int32) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { return result }
            if count < 0 {
                if errno == EINTR { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private func assertPolicyError<T>(
        _ expected: ExternalToolPolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected policy error: \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ExternalToolPolicyError, expected, file: file, line: line)
        }
    }

    private func assertInvalidLimit<T>(
        named expectedName: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected invalid limit: \(expectedName)", file: file, line: line)
        } catch ExternalToolPolicyError.invalidLimit(let name, _) {
            XCTAssertEqual(name, expectedName, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
