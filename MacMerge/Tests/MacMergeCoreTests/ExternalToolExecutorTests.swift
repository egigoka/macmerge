import CryptoKit
import Darwin
import Foundation
import MacMergeCore
import XCTest

final class ExternalToolExecutorTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let executableURL: URL
        let data: Data
    }

    // MARK: Limits and fixed contract

    func testExecutorLimitsRejectInvalidBoundsAndAcceptEdges() throws {
        assertInvalidExecutorLimits(maximumVerificationBytes: 0, cancellationCheckInterval: 64)
        assertInvalidExecutorLimits(maximumVerificationBytes: -1, cancellationCheckInterval: 64)
        assertInvalidExecutorLimits(
            maximumVerificationBytes: ExternalToolExecutorLimits.hardMaximumVerificationBytes + 1,
            cancellationCheckInterval: 64
        )
        assertInvalidExecutorLimits(maximumVerificationBytes: 64, cancellationCheckInterval: 0)
        assertInvalidExecutorLimits(maximumVerificationBytes: 64, cancellationCheckInterval: -1)
        assertInvalidExecutorLimits(
            maximumVerificationBytes: 64,
            cancellationCheckInterval: ExternalToolExecutorLimits.hardMaximumCancellationCheckInterval + 1
        )

        XCTAssertEqual(ExternalToolExecutorLimits.default.maximumVerificationBytes, 64 * 1_024 * 1_024)
        XCTAssertEqual(ExternalToolExecutorLimits.default.cancellationCheckInterval, 64)
        XCTAssertNoThrow(
            try ExternalToolExecutorLimits(
                maximumVerificationBytes: ExternalToolExecutorLimits.hardMaximumVerificationBytes,
                cancellationCheckInterval: ExternalToolExecutorLimits.hardMaximumCancellationCheckInterval
            )
        )
        XCTAssertNoThrow(try ExternalToolExecutorLimits(maximumVerificationBytes: 1, cancellationCheckInterval: 1))
    }

    func testExecutorContractIsFixedAndNeverSpawns() {
        let contract = ExternalToolExecutorContract.required
        XCTAssertEqual(contract.launchPolicy, .privateImmutableCopyFromPinnedDescriptor)
        XCTAssertEqual(contract.libraryValidation, .required)
        XCTAssertEqual(contract.dynamicLoad, .defaultDeny)
        XCTAssertEqual(contract.standardInput, .nullDevice)
        XCTAssertEqual(contract.inheritedDescriptors, .closeAllExceptStandardStreams)
        XCTAssertEqual(contract.processGroup, .dedicatedProcessGroup)
        XCTAssertEqual(contract.termination, .terminateThenKillProcessGroup)
        XCTAssertEqual(contract.outputDrain, .concurrentlyUntilEndOfFile)
        XCTAssertEqual(contract.invocationMethod, .directExecutable)
        XCTAssertEqual(contract.ambientCapabilities, .defaultDeny)
        XCTAssertEqual(contract.processSpawning, .stubValidatesOnlyNeverSpawns)

        XCTAssertEqual(ExternalToolExecutorNonLaunchReason.allCases.count, 8)
        let errors: [ExternalToolExecutorError] = [
            .invalidLimits,
            .cancelled,
            .workLimitExceeded(maximum: 16),
            .staleExecutable("/tool"),
            .verificationFailed("/tool")
        ]
        for error in errors {
            XCTAssertEqual(error.errorDescription?.isEmpty, false)
        }
    }

    func testUnsupportedRejectionIsFailClosedForAllCapabilities() {
        let executor = ExternalToolStubExecutor()
        XCTAssertEqual(
            executor.unsupportedRejection(for: .pluginReload),
            .notLaunched(
                reason: .unsupportedCapability,
                detail: "Plugin reload is explicitly unsupported and can never produce a launch receipt."
            )
        )
        XCTAssertEqual(
            executor.unsupportedRejection(for: .inProcessExtensions),
            .notLaunched(
                reason: .unsupportedCapability,
                detail: "In-process extensions are explicitly unsupported and can never produce a launch receipt."
            )
        )
        for capability in [ExternalToolCapability.unpacker, .prediffer, .editorScript, .copyingScript] {
            XCTAssertEqual(
                executor.unsupportedRejection(for: capability),
                .notLaunched(
                    reason: .rejected,
                    detail: "Capability \(capability.rawValue) requires a validated direct-executable plan; "
                        + "plan with ExternalToolRequestPlanner, then execute the resulting plan."
                )
            )
        }
    }

    // MARK: Sandbox authority and scope coverage

    func testDenyAllAuthorityRejectsValidPlanBeforeProbes() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let executableProbe = ExternalToolExecutorProbeFlag()
        let scopesProbe = ExternalToolExecutorProbeFlag()
        let executor = ExternalToolStubExecutor(
            authority: ExternalToolExecutorSandboxAuthority(),
            revalidation: ExternalToolExecutorRevalidation(
                executableCurrent: { _ in
                    executableProbe.set()
                    return true
                },
                scopesCurrent: { _ in
                    scopesProbe.set()
                    return true
                }
            )
        )

        XCTAssertFalse(executor.authority.authorizes(plan))
        let outcome = await executor.execute(plan)
        XCTAssertEqual(
            outcome,
            .notLaunched(reason: .authorityDenied, detail: "Plan scopes exceed the host sandbox authority.")
        )
        XCTAssertFalse(executableProbe.get())
        XCTAssertFalse(scopesProbe.get())
    }

    func testAuthorityEnforcesScopeBoundariesAndSlashConfusion() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let canonicalRoot = plan.workingDirectoryURL.path
        XCTAssertEqual(canonicalRoot, plan.readScopes.map(\.url.path).first)

        XCTAssertTrue(
            ExternalToolExecutorSandboxAuthority(readableRootPaths: [canonicalRoot]).authorizes(plan)
        )
        XCTAssertFalse(
            ExternalToolExecutorSandboxAuthority(readableRootPaths: [canonicalRoot + "-sibling"]).authorizes(plan)
        )
        let child = fixture.root.appending(path: "child", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        XCTAssertFalse(
            ExternalToolExecutorSandboxAuthority(readableRootPaths: [child.path]).authorizes(plan)
        )

        let evilURL = URL(fileURLWithPath: fixture.root.path + "-evil", isDirectory: true)
        try FileManager.default.createDirectory(at: evilURL, withIntermediateDirectories: false)
        try setPermissions(0o700, on: evilURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: evilURL) }
        let evilFixture = Fixture(
            root: evilURL,
            executableURL: evilURL.appending(path: "reviewed-tool"),
            data: Data([0x7F, 0x4D, 0x41, 0x43, 0x4D, 0x45, 0x52, 0x47, 0x45])
        )
        try writeExecutable(evilFixture.data, to: evilFixture.executableURL)
        let evilPlan = try planFor(evilFixture)
        XCTAssertTrue(
            ExternalToolExecutorSandboxAuthority(readableRootPaths: [evilURL.path]).authorizes(evilPlan)
        )
        XCTAssertFalse(
            ExternalToolExecutorSandboxAuthority(readableRootPaths: [canonicalRoot]).authorizes(evilPlan)
        )
    }

    func testWriteScopesRequireWritableRoots() async throws {
        let fixture = try makeFixture()
        let writeDirectory = fixture.root.appending(path: "scope-output", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: writeDirectory, withIntermediateDirectories: false)
        let plan = try planFor(
            fixture,
            permittedWriteScopes: [exact(writeDirectory)],
            requestWriteScopes: [exact(writeDirectory)]
        )
        XCTAssertEqual(plan.writeScopes.map(\.url.path), [writeDirectory.path])

        let writable = ExternalToolExecutorSandboxAuthority(
            readableRootPaths: [plan.workingDirectoryURL.path],
            writableRootPaths: [fixture.root.path]
        )
        XCTAssertTrue(writable.authorizes(plan))
        let writableExecutor = ExternalToolStubExecutor(authority: writable)
        let writableOutcome = await writableExecutor.execute(plan)
        XCTAssertEqual(writableOutcome.isReady, true)

        let readOnly = ExternalToolExecutorSandboxAuthority(
            readableRootPaths: [plan.workingDirectoryURL.path]
        )
        XCTAssertFalse(readOnly.authorizes(plan))
        let readOnlyOutcome = await ExternalToolStubExecutor(authority: readOnly).execute(plan)
        XCTAssertEqual(
            readOnlyOutcome,
            .notLaunched(reason: .authorityDenied, detail: "Plan scopes exceed the host sandbox authority.")
        )
    }

    func testWorkingDirectoryMustSitInsideReadScopesAndAuthorityRoots() async throws {
        let fixture = try makeFixture()
        let input = fixture.root.appending(path: "input.txt")
        try Data("input".utf8).write(to: input)
        let policy = try ExternalToolPolicy(externalExecutableRules: [makeRule(fixture)])
        let planner = ExternalToolRequestPlanner(policy: policy)
        do {
            _ = try planner.plan(
                ExternalToolRequest(
                    ruleIdentifier: "reviewed-tool",
                    capability: .unpacker,
                    workingDirectoryURL: fixture.root,
                    readScopes: [exact(input)]
                )
            )
            XCTFail("Expected workingDirectoryNotDeclaredReadable")
        } catch {
            XCTAssertEqual(
                error as? ExternalToolPolicyError,
                .workingDirectoryNotDeclaredReadable(fixture.root.path)
            )
        }

        let plan = try planFor(fixture)
        let workingDirectoryOutsideRoots = ExternalToolExecutorSandboxAuthority(
            readableRootPaths: [input.path]
        )
        XCTAssertFalse(workingDirectoryOutsideRoots.authorizes(plan))
    }

    // MARK: Typed arguments and loader environment re-assertion

    func testTypedArgumentsAndSafeEnvironmentPassReassertionWhileDYLDDenied() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(
            fixture,
            arguments: ["--mode", "fast", "key=value", fixture.root.appending(path: "input").path],
            environment: ["SAFE_KEY": "left=right"],
            argumentConstraints: [.exact("--mode"), .oneOf(["fast", "safe"]), .value, .readPath],
            allowedEnvironmentKeys: ["SAFE_KEY"]
        )
        let typedOutcome = await authorizedExecutor(for: plan).execute(plan)
        let typedReceipt = try XCTUnwrap(typedOutcome.receipt)
        XCTAssertEqual(typedReceipt.argumentCount, 4)
        XCTAssertEqual(typedReceipt.environmentEntryCount, 1)

        let policy = try ExternalToolPolicy(
            externalExecutableRules: [makeRule(fixture, allowedEnvironmentKeys: ["SAFE_KEY"])]
        )
        do {
            _ = try ExternalToolRequestPlanner(policy: policy).plan(
                request(in: fixture, environment: ["DYLD_INSERT_LIBRARIES": "/tmp/injected.dylib"])
            )
            XCTFail("Expected permanently-denied loader key rejection")
        } catch {
            XCTAssertEqual(
                error as? ExternalToolPolicyError,
                .environmentKeyPermanentlyDenied("DYLD_INSERT_LIBRARIES")
            )
        }
    }

    // MARK: Revalidation probes

    func testStaleExecutableProbeRejectsWithoutConsultingScopes() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let scopesProbe = ExternalToolExecutorProbeFlag()
        let executor = authorizedExecutor(
            for: plan,
            revalidation: ExternalToolExecutorRevalidation(
                executableCurrent: { _ in false },
                scopesCurrent: { _ in
                    scopesProbe.set()
                    return true
                }
            )
        )

        let staleExecutableOutcome = await executor.execute(plan)
        XCTAssertEqual(
            staleExecutableOutcome,
            .notLaunched(
                reason: .staleExecutable,
                detail: "Executable inputs changed after pinned verification."
            )
        )
        XCTAssertFalse(scopesProbe.get())
    }

    func testStaleScopesProbeRejectsAfterExecutableProbe() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let executor = authorizedExecutor(
            for: plan,
            revalidation: ExternalToolExecutorRevalidation(
                executableCurrent: { _ in true },
                scopesCurrent: { _ in false }
            )
        )

        let staleScopesOutcome = await executor.execute(plan)
        XCTAssertEqual(
            staleScopesOutcome,
            .notLaunched(
                reason: .staleScopes,
                detail: "Filesystem scopes changed after pinned verification."
            )
        )
    }

    func testAuthorityDeniedBeforeStaleProbes() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let executableProbe = ExternalToolExecutorProbeFlag()
        let scopesProbe = ExternalToolExecutorProbeFlag()
        let executor = ExternalToolStubExecutor(
            revalidation: ExternalToolExecutorRevalidation(
                executableCurrent: { _ in
                    executableProbe.set()
                    return false
                },
                scopesCurrent: { _ in
                    scopesProbe.set()
                    return false
                }
            )
        )

        let authorityOutcome = await executor.execute(plan)
        XCTAssertEqual(
            authorityOutcome,
            .notLaunched(reason: .authorityDenied, detail: "Plan scopes exceed the host sandbox authority.")
        )
        XCTAssertFalse(executableProbe.get())
        XCTAssertFalse(scopesProbe.get())
    }

    // MARK: Pinned SHA-256 re-verification

    func testPinnedVerificationSucceedsAcrossChunksAndEchoesSHA256() async throws {
        let byteCount = 200_000
        let data = patternData(byteCount: byteCount)
        let fixture = try makeFixture(data: data)
        let plan = try planFor(fixture)
        XCTAssertEqual(plan.executablePin.identity.size, Int64(byteCount))

        let verifiedOutcome = await authorizedExecutor(for: plan).execute(plan)
        let verifiedReceipt = try XCTUnwrap(verifiedOutcome.receipt)
        XCTAssertEqual(verifiedReceipt.executableSHA256, digest(data))
        XCTAssertEqual(verifiedReceipt, authorizedExecutor(for: plan).describe(plan))
    }

    func testSameSizeMutationFailsClosed() async throws {
        let fixture = try makeFixture(data: Data("trusted!".utf8))
        let plan = try planFor(fixture)
        let handle = try FileHandle(forWritingTo: fixture.executableURL)
        try handle.write(contentsOf: Data("altered!".utf8))
        try handle.synchronize()
        try handle.close()

        let staleOutcome = await authorizedExecutor(for: plan).execute(plan)
        XCTAssertEqual(
            staleOutcome,
            .notLaunched(
                reason: .staleExecutable,
                detail: "Executable no longer matches its pinned identity: \(plan.executableURL.path)."
            )
        )
    }

    func testRestoredMetadataMutationDetectedByDigestMismatch() async throws {
        let fixture = try makeFixture(data: Data("trusted!".utf8))
        let plan = try planFor(fixture)
        let identity = plan.executablePin.identity
        let handle = try FileHandle(forWritingTo: fixture.executableURL)
        try handle.write(contentsOf: Data("altered!".utf8))
        try handle.synchronize()
        try handle.close()
        guard restoreIdentityTimes(identity, on: fixture.executableURL) else {
            throw XCTSkip("Temporary filesystem cannot restore executable change-time metadata.")
        }
        let restored = try fileInformation(at: fixture.executableURL)
        guard metadata(of: restored, matches: identity) else {
            throw XCTSkip("Temporary filesystem did not preserve restored executable metadata.")
        }
        XCTAssertEqual(try Data(contentsOf: fixture.executableURL), Data("altered!".utf8))

        let staleOutcome = await authorizedExecutor(for: plan).execute(plan)
        XCTAssertEqual(
            staleOutcome,
            .notLaunched(
                reason: .staleExecutable,
                detail: "Executable no longer matches its pinned identity: \(plan.executableURL.path)."
            )
        )
    }

    func testTruncationFailsClosedAsStale() async throws {
        let fixture = try makeFixture(data: patternData(byteCount: 1_024))
        let plan = try planFor(fixture)
        try truncate(fixture.executableURL, to: 512)

        let staleOutcome = await authorizedExecutor(for: plan).execute(plan)
        XCTAssertEqual(
            staleOutcome,
            .notLaunched(
                reason: .staleExecutable,
                detail: "Executable no longer matches its pinned identity: \(plan.executableURL.path)."
            )
        )
    }

    func testReplacementFailsClosedAsStale() async throws {
        let fixture = try makeFixture(data: Data("original!".utf8))
        let plan = try planFor(fixture)
        let replacementData = Data("replaced!".utf8)
        XCTAssertEqual(replacementData.count, fixture.data.count)
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

        let staleOutcome = await authorizedExecutor(for: plan).execute(plan)
        XCTAssertEqual(
            staleOutcome,
            .notLaunched(
                reason: .staleExecutable,
                detail: "Executable no longer matches its pinned identity: \(plan.executableURL.path)."
            )
        )
    }

    func testConcurrentTruncationDuringVerificationFailsClosed() async throws {
        let fixture = try makeFixture(data: patternData(byteCount: 8 * 1_024 * 1_024))
        let plan = try planFor(fixture)
        let executor = authorizedExecutor(for: plan)
        let task = Task { await executor.execute(plan) }
        try truncate(fixture.executableURL, to: fixture.data.count / 2)

        let raceOutcome = await task.value
        XCTAssertEqual(
            raceOutcome,
            .notLaunched(
                reason: .staleExecutable,
                detail: "Executable no longer matches its pinned identity: \(plan.executableURL.path)."
            )
        )
    }

    func testInterruptedReadsAreRetried() async throws {
        let data = patternData(byteCount: 4 * 1_024 * 1_024)
        let fixture = try makeFixture(data: data)
        let plan = try planFor(fixture)
        let executor = authorizedExecutor(for: plan)

        var interruptAction = sigaction()
        interruptAction.__sigaction_u.__sa_handler = externalToolExecutorInterruptHandler
        interruptAction.sa_mask = 0
        interruptAction.sa_flags = 0
        var previousAction = sigaction()
        // The sigaction C function is shadowed by its struct in Swift; reach it via dlsym.
        // Flags stay zero so interrupted pread fails with EINTR instead of restarting.
        typealias SigactionFunction =
            @convention(c) (
                Int32,
                UnsafePointer<sigaction>?,
                UnsafeMutablePointer<sigaction>?
            ) -> Int32
        guard let library = Darwin.dlopen(nil, RTLD_NOW),
            let symbol = Darwin.dlsym(library, "sigaction")
        else {
            throw XCTSkip("sigaction symbol is unavailable; cannot test EINTR retry.")
        }
        let install = unsafeBitCast(symbol, to: SigactionFunction.self)
        guard install(SIGUSR1, &interruptAction, &previousAction) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = install(SIGUSR1, &previousAction, nil) }

        let pid = Darwin.getpid()
        let bombardment = Task {
            for _ in 0..<60 {
                Darwin.kill(pid, SIGUSR1)
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        let outcome = await executor.execute(plan)
        await bombardment.value

        XCTAssertEqual(outcome.receipt?.executableSHA256, digest(data))
    }

    func testWorkLimitExceededAndSmallBoundSucceeds() async throws {
        let fixture = try makeFixture(data: patternData(byteCount: 200_000))
        let plan = try planFor(fixture)
        let bounded = try ExternalToolExecutorLimits(maximumVerificationBytes: 16, cancellationCheckInterval: 64)
        let boundedOutcome = await authorizedExecutor(for: plan, limits: bounded).execute(plan)
        XCTAssertEqual(
            boundedOutcome,
            .notLaunched(reason: .workLimitExceeded, detail: "Executable exceeds the 16-byte verification bound.")
        )

        let small = try makeFixture()
        let smallPlan = try planFor(small)
        let generous = try ExternalToolExecutorLimits(maximumVerificationBytes: 1_024, cancellationCheckInterval: 1)
        let smallOutcome = await authorizedExecutor(for: smallPlan, limits: generous).execute(smallPlan)
        XCTAssertEqual(smallOutcome.isReady, true)
    }

    // MARK: Cancellation checkpoints

    func testCancellationBeforeValidation() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let executableProbe = ExternalToolExecutorProbeFlag()
        let scopesProbe = ExternalToolExecutorProbeFlag()
        let executor = authorizedExecutor(
            for: plan,
            revalidation: ExternalToolExecutorRevalidation(
                executableCurrent: { _ in
                    executableProbe.set()
                    return true
                },
                scopesCurrent: { _ in
                    scopesProbe.set()
                    return true
                }
            )
        )
        let (gateStream, gateContinuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gateStream { break }
            return await executor.execute(plan)
        }
        task.cancel()
        gateContinuation.finish()

        let gateOutcome = await task.value
        XCTAssertEqual(
            gateOutcome,
            .notLaunched(reason: .cancelled, detail: "Cancelled before external-tool validation.")
        )
        XCTAssertFalse(executableProbe.get())
        XCTAssertFalse(scopesProbe.get())
    }

    func testCancellationDuringPinnedVerification() async throws {
        let fixture = try makeFixture(data: patternData(byteCount: 48 * 1_024 * 1_024))
        let plan = try planFor(fixture)
        let limits = try ExternalToolExecutorLimits(
            maximumVerificationBytes: 64 * 1_024 * 1_024,
            cancellationCheckInterval: 1
        )
        let executor = authorizedExecutor(for: plan, limits: limits)
        let expected = ExternalToolExecutorOutcome.notLaunched(
            reason: .cancelled,
            detail: "Cancelled during pinned verification."
        )
        var last: ExternalToolExecutorOutcome?
        for _ in 0..<12 {
            let task = Task { await executor.execute(plan) }
            try? await Task.sleep(for: .milliseconds(2))
            task.cancel()
            last = await task.value
            if last == expected {
                return
            }
        }
        XCTFail("Cancellation did not land inside pinned verification; last outcome: \(String(describing: last))")
    }

    func testCancellationAfterPinnedVerification() async throws {
        let fixture = try makeFixture(data: patternData(byteCount: 48 * 1_024 * 1_024))
        let plan = try planFor(fixture)
        let limits = try ExternalToolExecutorLimits(
            maximumVerificationBytes: 64 * 1_024 * 1_024,
            cancellationCheckInterval: ExternalToolExecutorLimits.hardMaximumCancellationCheckInterval
        )
        let executor = authorizedExecutor(for: plan, limits: limits)
        let expected = ExternalToolExecutorOutcome.notLaunched(
            reason: .cancelled,
            detail: "Cancelled after pinned verification."
        )
        var last: ExternalToolExecutorOutcome?
        for _ in 0..<12 {
            let task = Task { await executor.execute(plan) }
            try? await Task.sleep(for: .milliseconds(5))
            task.cancel()
            last = await task.value
            if last == expected {
                return
            }
        }
        XCTFail("Cancellation did not land after pinned verification; last outcome: \(String(describing: last))")
    }

    func testCancellationAfterExecutableRevalidation() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let scopesProbe = ExternalToolExecutorProbeFlag()
        let executor = authorizedExecutor(
            for: plan,
            revalidation: ExternalToolExecutorRevalidation(
                executableCurrent: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return true
                },
                scopesCurrent: { _ in
                    scopesProbe.set()
                    return true
                }
            )
        )

        let afterExecutableOutcome = await executor.execute(plan)
        XCTAssertEqual(
            afterExecutableOutcome,
            .notLaunched(reason: .cancelled, detail: "Cancelled after executable revalidation.")
        )
        XCTAssertFalse(scopesProbe.get())
    }

    func testCancellationAfterScopeRevalidation() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let executor = authorizedExecutor(
            for: plan,
            revalidation: ExternalToolExecutorRevalidation(
                executableCurrent: { _ in true },
                scopesCurrent: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return true
                }
            )
        )

        let afterScopesOutcome = await executor.execute(plan)
        XCTAssertEqual(
            afterScopesOutcome,
            .notLaunched(reason: .cancelled, detail: "Cancelled after scope revalidation.")
        )
    }

    func testCancelledPreemptsStaleProbes() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let executor = authorizedExecutor(for: plan, revalidation: .stale)
        let (gateStream, gateContinuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gateStream { break }
            return await executor.execute(plan)
        }
        task.cancel()
        gateContinuation.finish()

        let gateOutcome = await task.value
        XCTAssertEqual(
            gateOutcome,
            .notLaunched(reason: .cancelled, detail: "Cancelled before external-tool validation.")
        )
    }

    // MARK: Receipts and never-spawns

    func testReceiptEchoesValidatedPlan() async throws {
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
        let plan = try planFor(
            fixture,
            arguments: ["--mode", "fast"],
            environment: ["SAFE_KEY": "value"],
            argumentConstraints: [.exact("--mode"), .oneOf(["fast", "safe"])],
            allowedEnvironmentKeys: ["SAFE_KEY"],
            isolationPolicy: isolation,
            limits: limits
        )
        let executor = authorizedExecutor(for: plan)
        let verifiedOutcome = await executor.execute(plan)
        let verifiedReceipt = try XCTUnwrap(verifiedOutcome.receipt)

        XCTAssertEqual(verifiedReceipt, executor.describe(plan))
        XCTAssertEqual(verifiedReceipt.ruleIdentifier, "reviewed-tool")
        XCTAssertEqual(verifiedReceipt.capability, .unpacker)
        XCTAssertEqual(verifiedReceipt.invocationMethod, .directExecutable)
        XCTAssertEqual(verifiedReceipt.executablePath, plan.executableURL.path)
        XCTAssertEqual(verifiedReceipt.executableSHA256, digest(fixture.data))
        XCTAssertEqual(verifiedReceipt.workingDirectoryPath, plan.workingDirectoryURL.path)
        XCTAssertEqual(verifiedReceipt.argumentCount, 2)
        XCTAssertEqual(verifiedReceipt.environmentEntryCount, 1)
        XCTAssertEqual(verifiedReceipt.readScopeCount, 1)
        XCTAssertEqual(verifiedReceipt.writeScopeCount, 0)
        XCTAssertEqual(verifiedReceipt.timeoutSeconds, 0.25)
        XCTAssertEqual(verifiedReceipt.standardOutputLimitBytes, 11)
        XCTAssertEqual(verifiedReceipt.standardErrorLimitBytes, 13)
        XCTAssertEqual(verifiedReceipt.combinedOutputLimitBytes, 17)
        XCTAssertEqual(verifiedReceipt.isolationPolicy, isolation)
        XCTAssertEqual(verifiedReceipt.executorContract, .required)
    }

    func testExecutorNeverSpawnsOrMutates() async throws {
        let fixture = try makeFixture()
        let plan = try planFor(fixture)
        let executor = authorizedExecutor(for: plan)
        let beforeListing = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
        let beforeBytes = try Data(contentsOf: fixture.executableURL)

        let first = await executor.execute(plan)
        let second = await executor.execute(plan)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, executor.describe(plan))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted(),
            beforeListing
        )
        XCTAssertEqual(try Data(contentsOf: fixture.executableURL), beforeBytes)
    }

    // MARK: Helpers

    private func makeFixture(data: Data? = nil) throws -> Fixture {
        let resolvedData =
            data ?? Data([0x7F, 0x4D, 0x41, 0x43, 0x4D, 0x45, 0x52, 0x47, 0x45])
        let temporaryDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        try requireTrustedTemporaryDirectoryAncestors(temporaryDirectory)
        let root = temporaryDirectory.appending(
            path: "MacMergeExternalToolExecutorTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try setPermissions(0o700, on: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let executableURL = root.appending(path: "reviewed-tool")
        try writeExecutable(resolvedData, to: executableURL)
        return Fixture(root: root, executableURL: executableURL, data: resolvedData)
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

    private func truncate(_ url: URL, to byteCount: Int) throws {
        let descriptor = Darwin.open(url.path, O_WRONLY)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.ftruncate(descriptor, off_t(byteCount)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func patternData(byteCount: Int) -> Data {
        Data((0..<byteCount).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    }

    private func makeRule(
        _ fixture: Fixture,
        identifier: String = "reviewed-tool",
        capability: ExternalToolCapability = .unpacker,
        permittedWriteScopes: [ExternalToolPathScope] = [],
        allowedEnvironmentKeys: [String] = [],
        argumentConstraints: [ExternalToolArgumentConstraint] = [],
        isolationPolicy: ExternalToolIsolationPolicy = .default,
        limits: ExternalToolInvocationLimits = .default
    ) -> ExternalToolExecutableRule {
        ExternalToolExecutableRule(
            identifier: identifier,
            capability: capability,
            executableURL: fixture.executableURL,
            approvedExecutableSHA256: digest(fixture.data),
            permittedWorkingDirectories: [exact(fixture.root)],
            permittedReadScopes: [tree(fixture.root)],
            permittedWriteScopes: permittedWriteScopes,
            allowedEnvironmentKeys: allowedEnvironmentKeys,
            argumentConstraints: argumentConstraints,
            isolationPolicy: isolationPolicy,
            limits: limits
        )
    }

    private func planFor(
        _ fixture: Fixture,
        arguments: [String] = [],
        environment: [String: String] = [:],
        argumentConstraints: [ExternalToolArgumentConstraint] = [],
        allowedEnvironmentKeys: [String] = [],
        permittedWriteScopes: [ExternalToolPathScope] = [],
        requestWriteScopes: [ExternalToolPathScope] = [],
        isolationPolicy: ExternalToolIsolationPolicy = .default,
        limits: ExternalToolInvocationLimits = .default
    ) throws -> ExternalToolExecutionPlan {
        let policy = try ExternalToolPolicy(
            externalExecutableRules: [
                makeRule(
                    fixture,
                    permittedWriteScopes: permittedWriteScopes,
                    allowedEnvironmentKeys: allowedEnvironmentKeys,
                    argumentConstraints: argumentConstraints,
                    isolationPolicy: isolationPolicy,
                    limits: limits
                )
            ]
        )
        return try ExternalToolRequestPlanner(policy: policy).plan(
            ExternalToolRequest(
                ruleIdentifier: "reviewed-tool",
                capability: .unpacker,
                workingDirectoryURL: fixture.root,
                arguments: arguments,
                environment: environment,
                readScopes: [tree(fixture.root)],
                writeScopes: requestWriteScopes
            )
        )
    }

    private func request(
        in fixture: Fixture,
        environment: [String: String] = [:]
    ) -> ExternalToolRequest {
        ExternalToolRequest(
            ruleIdentifier: "reviewed-tool",
            capability: .unpacker,
            workingDirectoryURL: fixture.root,
            environment: environment,
            readScopes: [tree(fixture.root)]
        )
    }

    private func authorizedExecutor(
        for plan: ExternalToolExecutionPlan,
        revalidation: ExternalToolExecutorRevalidation = .assumeCurrent,
        limits: ExternalToolExecutorLimits = .default
    ) -> ExternalToolStubExecutor {
        ExternalToolStubExecutor(
            authority: ExternalToolExecutorSandboxAuthority(
                readableRootPaths: [plan.workingDirectoryURL.path]
            ),
            revalidation: revalidation,
            limits: limits
        )
    }

    private func exact(_ url: URL) -> ExternalToolPathScope {
        ExternalToolPathScope(url: url, kind: .exactItem)
    }

    private func tree(_ url: URL) -> ExternalToolPathScope {
        ExternalToolPathScope(url: url, kind: .directoryTree)
    }

    private func digest(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private func assertInvalidExecutorLimits(
        maximumVerificationBytes: Int,
        cancellationCheckInterval: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ExternalToolExecutorLimits(
                maximumVerificationBytes: maximumVerificationBytes,
                cancellationCheckInterval: cancellationCheckInterval
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? ExternalToolExecutorError, .invalidLimits, file: file, line: line)
        }
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
}

private final class ExternalToolExecutorProbeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.withLock { value = true }
    }

    func get() -> Bool {
        lock.withLock { value }
    }
}

private func externalToolExecutorInterruptHandler(_: Int32) {}

extension ExternalToolExecutorOutcome {
    fileprivate var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    fileprivate var receipt: ExternalToolStubExecutorReceipt? {
        if case .ready(let receipt) = self { return receipt }
        return nil
    }
}
