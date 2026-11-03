import CryptoKit
import Foundation
import XCTest

@testable import MacMergeCore

final class PluginExecutionStubTests: XCTestCase {
    func testPlanBindsReceiptAndExecutorReturnsNotExecutedWithoutLoading() async throws {
        let fixture = try makeFixture()
        let item = try XCTUnwrap(fixture.items.first { $0.capability == .unpacker })
        let selection = PluginManagementSelectionRequest(
            filter: try PluginCatalogFilter(identifier: item.id),
            mode: .manual
        )
        let plan = try PluginExecutionStub.plan(
            PluginExecutionStubRequest(
                snapshot: fixture.snapshot,
                selection: selection,
                authorizations: fixture.authorizations
            )
        )

        XCTAssertEqual(plan.receipt.revision, fixture.snapshot.revision)
        XCTAssertEqual(plan.receipt.identifier, item.id)
        XCTAssertEqual(plan.receipt.capability, .unpacker)
        XCTAssertEqual(plan.receipt.lane, .unpacker)
        XCTAssertEqual(plan.receipt.mode, .manual)
        XCTAssertEqual(plan.executorContract, .planOnlyNoPluginLoading)
        XCTAssertEqual(plan.expectedSnapshot.revision, fixture.snapshot.revision)
        XCTAssertNoThrow(
            try plan.validateCurrentSnapshot(
                fixture.snapshot,
                authorizations: fixture.authorizations
            )
        )

        let outcome = await PluginExecutionStubExecutor().execute(
            plan,
            validating: fixture.snapshot,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(outcome, .notExecuted(plan.receipt))
    }

    func testExecutableLanesPlanAndTransformHasNoBackend() async throws {
        let fixture = try makeFixture()
        XCTAssertEqual(
            Set(PluginExecutionStubLane.allCases),
            Set([.unpacker, .prediffer, .editor, .copy])
        )
        let lanes: [(PluginCapability, PluginExecutionStubLane)] = [
            (.unpacker, .unpacker),
            (.prediffer, .prediffer),
            (.editor, .editor),
            (.copy, .copy)
        ]
        for (capability, lane) in lanes {
            let item = try XCTUnwrap(fixture.items.first { $0.capability == capability })
            let plan = try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(
                        filter: try PluginCatalogFilter(identifier: item.id),
                        mode: .manual
                    ),
                    authorizations: fixture.authorizations
                )
            )
            XCTAssertEqual(plan.receipt.lane, lane)
            let outcome = await PluginExecutionStubExecutor().execute(
                plan,
                validating: fixture.snapshot,
                authorizations: fixture.authorizations
            )
            XCTAssertEqual(outcome, .notExecuted(plan.receipt))
        }

        // Transform names no external-tool capability, so catalog select yields
        // noMatch/unsupported and plan maps to selectionNotExecutable.
        // backendUnavailable stays dead via plan path; lane keeps it as defense.
        assertStubError(.selectionNotExecutable) {
            try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(
                        filter: try PluginCatalogFilter(identifier: fixture.transformItem.id),
                        mode: .manual
                    ),
                    authorizations: fixture.authorizations
                )
            )
        }
    }

    func testMissingUntrustedAndAmbiguousSelectionsAreNotExecutable() throws {
        let fixture = try makeFixture()
        let item = try XCTUnwrap(fixture.items.first { $0.capability == .unpacker })
        let request = PluginExecutionStubRequest(
            snapshot: fixture.snapshot,
            selection: PluginManagementSelectionRequest(
                filter: try PluginCatalogFilter(identifier: item.id),
                mode: .manual
            )
        )

        assertStubError(.selectionNotExecutable) {
            try PluginExecutionStub.plan(request)
        }

        let untrusted = try makeFixture(trust: .untrusted)
        assertStubError(.selectionNotExecutable) {
            try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: untrusted.snapshot,
                    selection: PluginManagementSelectionRequest(
                        filter: try PluginCatalogFilter(
                            identifier: untrusted.items.first { $0.capability == .unpacker }!.id
                        ),
                        mode: .manual
                    ),
                    authorizations: untrusted.authorizations
                )
            )
        }

        assertStubError(.selectionNotExecutable) {
            try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(mode: .manual),
                    authorizations: fixture.authorizations
                )
            )
        }
    }

    func testExecuteConsumesOneShotLease() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let executor = PluginExecutionStubExecutor()
        let first = await executor.execute(
            plan,
            validating: fixture.snapshot,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(first, .notExecuted(plan.receipt))
        let second = await executor.execute(
            plan,
            validating: fixture.snapshot,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(second, .failed(.leaseAlreadyConsumed))
    }

    func testCancelledExecuteDoesNotConsumeLease() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let executor = PluginExecutionStubExecutor()
        let cancelled = await Task.detached { [plan, fixture] in
            withUnsafeCurrentTask { $0?.cancel() }
            return await PluginExecutionStubExecutor().execute(
                plan,
                validating: fixture.snapshot,
                authorizations: fixture.authorizations
            )
        }.value
        XCTAssertEqual(cancelled, .cancelled)
        let retry = await executor.execute(
            plan,
            validating: fixture.snapshot,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(retry, .notExecuted(plan.receipt))
    }

    func testStaleSnapshotFailsClosed() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let staleRevision = PluginManagementRevision(
            lineage: fixture.snapshot.revision.lineage,
            generation: fixture.snapshot.revision.generation + 1
        )
        let stale = try PluginManagementSnapshot(
            revision: staleRevision,
            catalog: fixture.catalog,
            preferences: fixture.preferences,
            externalToolPolicy: fixture.policy
        )
        let expected = PluginExecutionStubError.staleSnapshot(
            expected: fixture.snapshot.revision,
            actual: staleRevision
        )
        assertStubError(expected) {
            try plan.validateCurrentSnapshot(stale, authorizations: fixture.authorizations)
        }
        let staleOutcome = await PluginExecutionStubExecutor().execute(
            plan,
            validating: stale,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(staleOutcome, .failed(expected))
    }

    func testSameRevisionContentChangeFailsClosed() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let changedPreferences = try PluginCatalogPreferences(catalog: fixture.catalog)
        let changed = try PluginManagementSnapshot(
            revision: fixture.snapshot.revision,
            catalog: fixture.catalog,
            preferences: changedPreferences,
            externalToolPolicy: fixture.policy
        )
        let expected = PluginExecutionStubError.snapshotContentsChanged(
            revision: fixture.snapshot.revision
        )
        assertStubError(expected) {
            try plan.validateCurrentSnapshot(changed, authorizations: fixture.authorizations)
        }
        let changedOutcome = await PluginExecutionStubExecutor().execute(
            plan,
            validating: changed,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(changedOutcome, .failed(expected))
    }

    func testAuthorizationDriftFailsClosed() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        assertStubError(.authorizationChanged) {
            try plan.validateCurrentSnapshot(fixture.snapshot, authorizations: [:])
        }
        let driftedOutcome = await PluginExecutionStubExecutor().execute(
            plan,
            validating: fixture.snapshot,
            authorizations: [:]
        )
        XCTAssertEqual(driftedOutcome, .failed(.authorizationChanged))

        fixture.authority.set(now: fixture.referenceDate, generation: 2)
        assertStubError(.authorizationChanged) {
            try plan.validateCurrentSnapshot(
                fixture.snapshot,
                authorizations: fixture.authorizations
            )
        }
    }

    func testReloadAndInProcessLoadingStayFailClosedUnavailable() async throws {
        let fixture = try makeFixture()
        // ExternalToolPolicy hard-unsupports reload/inProcess by design, so
        // reloadUnsupported/inProcessLoadingUnsupported executor branches stay
        // unreachable; stub always falls through to notExecuted.
        let reload = fixture.snapshot.catalog.reloadOutcome(
            externalToolPolicy: fixture.snapshot.externalToolPolicy
        )
        let inProcess = fixture.snapshot.catalog.inProcessLoadingOutcome(
            externalToolPolicy: fixture.snapshot.externalToolPolicy
        )
        XCTAssertFalse(reload.isSupported)
        XCTAssertFalse(inProcess.isSupported)
        XCTAssertEqual(reload.reason, .pluginReloadUnsupported)
        XCTAssertEqual(inProcess.reason, .inProcessExtensionsUnsupported)

        let request = try PluginManagementWorkflow().reloadRequest(snapshot: fixture.snapshot)
        let result = try PluginManagementWorkflow().reloadResult(
            for: request,
            currentSnapshot: fixture.snapshot
        )
        XCTAssertEqual(result.disposition, .unavailable(reload))

        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let reloadOutcome = await PluginExecutionStubExecutor().execute(
            plan,
            validating: fixture.snapshot,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(reloadOutcome, .notExecuted(plan.receipt))
    }

    func testLimitsRejectInvalidAndEnforceResultAndWorkBoundaries() throws {
        XCTAssertEqual(PluginExecutionStubLimits.hardMaximumResultCount, PluginManagementWorkflowLimits.hardMaximumListedItemCount)
        XCTAssertEqual(PluginExecutionStubLimits.hardMaximumWorkUnits, PluginManagementWorkflowLimits.hardMaximumWorkUnits)
        XCTAssertEqual(PluginExecutionStubLimits.hardMaximumCancellationCheckInterval, PluginManagementWorkflowLimits.hardMaximumCancellationCheckInterval)
        XCTAssertEqual(PluginExecutionStubLimits.default.maximumResultCount, 1_024)
        XCTAssertEqual(PluginExecutionStubLimits.default.maximumWorkUnits, 8 * 1_024 * 1_024)
        XCTAssertEqual(PluginExecutionStubLimits.default.cancellationCheckInterval, 64)
        XCTAssertNoThrow(
            try PluginExecutionStubLimits(
                maximumResultCount: PluginExecutionStubLimits.hardMaximumResultCount,
                maximumWorkUnits: PluginExecutionStubLimits.hardMaximumWorkUnits,
                cancellationCheckInterval: PluginExecutionStubLimits.hardMaximumCancellationCheckInterval
            )
        )
        for makeInvalid in [
            { try PluginExecutionStubLimits(maximumResultCount: 0) },
            { try PluginExecutionStubLimits(maximumResultCount: PluginExecutionStubLimits.hardMaximumResultCount + 1) },
            { try PluginExecutionStubLimits(maximumWorkUnits: 0) },
            { try PluginExecutionStubLimits(maximumWorkUnits: PluginExecutionStubLimits.hardMaximumWorkUnits + 1) },
            { try PluginExecutionStubLimits(cancellationCheckInterval: 0) },
            { try PluginExecutionStubLimits(cancellationCheckInterval: PluginExecutionStubLimits.hardMaximumCancellationCheckInterval + 1) }
        ] {
            assertStubError(.invalidLimits, makeInvalid)
        }

        let fixture = try makeFixture()
        assertStubError(.workflow(.resultLimitExceeded(maximum: 1))) {
            try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(mode: .manual),
                    authorizations: fixture.authorizations,
                    limits: try PluginExecutionStubLimits(maximumResultCount: 1)
                )
            )
        }
        assertStubError(.workLimitExceeded(maximum: 1)) {
            try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(
                        filter: try PluginCatalogFilter(
                            identifier: fixture.items.first { $0.capability == .unpacker }!.id
                        ),
                        mode: .manual
                    ),
                    authorizations: fixture.authorizations,
                    limits: try PluginExecutionStubLimits(maximumWorkUnits: 1)
                )
            )
        }
    }

    func testCancellationFailsClosed() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let selection = PluginManagementSelectionRequest(
            filter: try PluginCatalogFilter(
                identifier: fixture.items.first { $0.capability == .unpacker }!.id
            ),
            mode: .manual
        )
        let planError = await preCancelledStubError {
            _ = try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: selection,
                    authorizations: fixture.authorizations
                )
            )
        }
        XCTAssertEqual(planError, .cancelled)
        let validateError = await preCancelledStubError {
            try plan.validateCurrentSnapshot(
                fixture.snapshot,
                authorizations: fixture.authorizations
            )
        }
        XCTAssertEqual(validateError, .cancelled)
    }

    func testFailedValidateConsumesLeaseSecondExecuteMasksOriginal() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let executor = PluginExecutionStubExecutor()
        let staleRevision = PluginManagementRevision(
            lineage: fixture.snapshot.revision.lineage,
            generation: fixture.snapshot.revision.generation + 1
        )
        let stale = try PluginManagementSnapshot(
            revision: staleRevision,
            catalog: fixture.catalog,
            preferences: fixture.preferences,
            externalToolPolicy: fixture.policy
        )
        let expected = PluginExecutionStubError.staleSnapshot(
            expected: fixture.snapshot.revision,
            actual: staleRevision
        )
        let first = await executor.execute(
            plan,
            validating: stale,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(first, .failed(expected))
        let second = await executor.execute(
            plan,
            validating: fixture.snapshot,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(second, .failed(.leaseAlreadyConsumed))
    }

    func testMidValidateCancelRetrySucceeds() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let cancelled = await preCancelledStubError {
            try plan.validateCurrentSnapshot(
                fixture.snapshot,
                authorizations: fixture.authorizations
            )
        }
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertNoThrow(
            try plan.validateCurrentSnapshot(
                fixture.snapshot,
                authorizations: fixture.authorizations
            )
        )
    }

    func testLineageChangeFailsClosed() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let lineageStale = try PluginManagementSnapshot(
            revision: PluginManagementRevision(
                lineage: fixture.snapshot.revision.lineage + 1,
                generation: fixture.snapshot.revision.generation
            ),
            catalog: fixture.catalog,
            preferences: fixture.preferences,
            externalToolPolicy: fixture.policy
        )
        let expected = PluginExecutionStubError.staleSnapshot(
            expected: fixture.snapshot.revision,
            actual: lineageStale.revision
        )
        assertStubError(expected) {
            try plan.validateCurrentSnapshot(
                lineageStale,
                authorizations: fixture.authorizations
            )
        }
        let outcome = await PluginExecutionStubExecutor().execute(
            plan,
            validating: lineageStale,
            authorizations: fixture.authorizations
        )
        XCTAssertEqual(outcome, .failed(expected))
    }

    func testExpiryTrustApprovalDowngradeDriftFailsClosed() throws {
        let fixture = try makeFixture()
        let item = try XCTUnwrap(fixture.items.first { $0.capability == .unpacker })
        let verifier = try PluginAuthorizationVerifier(
            authenticationKey: Data(repeating: 0x21, count: PluginAuthorizationVerifier.authenticationKeyByteCount),
            authorityDomainIdentifier: Data(repeating: 0x31, count: 32),
            authorityStateProvider: fixture.authority
        )
        let expiry = fixture.referenceDate.addingTimeInterval(3_600)
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        fixture.authority.set(now: expiry.addingTimeInterval(1), generation: 1)
        assertStubError(.authorizationChanged) {
            try plan.validateCurrentSnapshot(
                fixture.snapshot,
                authorizations: fixture.authorizations
            )
        }
        fixture.authority.set(now: fixture.referenceDate, generation: 1)
        let untrusted = try verifier.issue(
            for: item,
            trust: .untrusted,
            approval: .manual,
            externalToolPolicy: fixture.policy,
            expiresAt: expiry
        )
        var downgraded = fixture.authorizations
        downgraded[item.id] = untrusted
        assertStubError(.authorizationChanged) {
            try plan.validateCurrentSnapshot(fixture.snapshot, authorizations: downgraded)
        }
        let notApproved = try verifier.issue(
            for: item,
            trust: .bundled,
            approval: .notApproved,
            externalToolPolicy: fixture.policy,
            expiresAt: expiry
        )
        downgraded[item.id] = notApproved
        assertStubError(.authorizationChanged) {
            try plan.validateCurrentSnapshot(fixture.snapshot, authorizations: downgraded)
        }
    }

    func testAmbiguousOverLimitAndIntervalCancel() async throws {
        let fixture = try makeFixture()
        assertStubError(.selectionNotExecutable) {
            try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(mode: .manual),
                    authorizations: fixture.authorizations
                )
            )
        }
        assertStubError(.workflow(.resultLimitExceeded(maximum: 1))) {
            try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(mode: .manual),
                    authorizations: fixture.authorizations,
                    limits: try PluginExecutionStubLimits(maximumResultCount: 1)
                )
            )
        }
        let intervalLimits = try PluginExecutionStubLimits(cancellationCheckInterval: 1)
        let planError = await preCancelledStubError {
            _ = try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(
                        filter: try PluginCatalogFilter(
                            identifier: fixture.items.first { $0.capability == .unpacker }!.id
                        ),
                        mode: .manual
                    ),
                    authorizations: fixture.authorizations,
                    limits: intervalLimits
                )
            )
        }
        XCTAssertEqual(planError, .cancelled)
    }

    func testMidOperationBudgetSelectCheckpointCancel() async throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture: fixture, capability: .unpacker)
        let validateCancelled = await preCancelledStubError {
            try plan.validateCurrentSnapshot(
                fixture.snapshot,
                authorizations: fixture.authorizations
            )
        }
        XCTAssertEqual(validateCancelled, .cancelled)
        let selectCancelled = await preCancelledStubError {
            _ = try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(mode: .manual),
                    authorizations: fixture.authorizations,
                    limits: try PluginExecutionStubLimits(cancellationCheckInterval: 1)
                )
            )
        }
        XCTAssertEqual(selectCancelled, .cancelled)
        assertStubError(.workLimitExceeded(maximum: 1)) {
            try PluginExecutionStub.plan(
                PluginExecutionStubRequest(
                    snapshot: fixture.snapshot,
                    selection: PluginManagementSelectionRequest(
                        filter: try PluginCatalogFilter(
                            identifier: fixture.items.first { $0.capability == .unpacker }!.id
                        ),
                        mode: .manual
                    ),
                    authorizations: fixture.authorizations,
                    limits: try PluginExecutionStubLimits(maximumWorkUnits: 1)
                )
            )
        }
    }

    private func makePlan(fixture: StubFixture, capability: PluginCapability) throws -> PluginExecutionStubPlan {
        let item = try XCTUnwrap(fixture.items.first { $0.capability == capability })
        return try PluginExecutionStub.plan(
            PluginExecutionStubRequest(
                snapshot: fixture.snapshot,
                selection: PluginManagementSelectionRequest(
                    filter: try PluginCatalogFilter(identifier: item.id),
                    mode: .manual
                ),
                authorizations: fixture.authorizations
            )
        )
    }

    private func makeFixture(
        trust: PluginTrustState = .bundled,
        approval: PluginApprovalState = .manual
    ) throws -> StubFixture {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let expiryDate = referenceDate.addingTimeInterval(3_600)
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(
            path: "MacMergePluginExecutionStubTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let executableData = Data("reviewed-plugin-execution-stub".utf8)
        let executableURL = root.appending(path: "reviewed-tool")
        try executableData.write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executableURL.path
        )
        let digest = Array(SHA256.hash(data: executableData))
        let lanes: [(PluginCapability, ExternalToolCapability, String)] = [
            (.unpacker, .unpacker, "unpacker"),
            (.prediffer, .prediffer, "prediffer"),
            (.editor, .editorScript, "editor"),
            (.copy, .copyingScript, "copy")
        ]
        let rules = lanes.map { (_, tool, name) in
            ExternalToolExecutableRule(
                identifier: "stub-rule-\(name)",
                capability: tool,
                executableURL: executableURL,
                approvedExecutableSHA256: digest,
                permittedWorkingDirectories: [ExternalToolPathScope(url: root, kind: .exactItem)],
                permittedReadScopes: [ExternalToolPathScope(url: root, kind: .directoryTree)]
            )
        }
        let policy = try ExternalToolPolicy(externalExecutableRules: rules)
        let authority = StubAuthorityState(now: referenceDate, generation: 1)
        let verifier = try PluginAuthorizationVerifier(
            authenticationKey: Data(repeating: 0x21, count: PluginAuthorizationVerifier.authenticationKeyByteCount),
            authorityDomainIdentifier: Data(repeating: 0x31, count: 32),
            authorityStateProvider: authority
        )
        var items: [PluginCatalogItem] = try lanes.map { (plugin, _, name) in
            try PluginCatalogItem(
                id: PluginIdentifier("plugin.stub.\(name)"),
                displayName: "Stub \(name)",
                version: "1",
                capability: plugin,
                externalToolRuleIdentifier: "stub-rule-\(name)"
            )
        }
        let transformItem = try PluginCatalogItem(
            id: PluginIdentifier("plugin.stub.transform"),
            displayName: "Stub transform",
            version: "1",
            capability: .transform
        )
        items.append(transformItem)
        let catalog = try PluginCatalog(items: items, authorizationVerifier: verifier)
        let preferences = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: Set(items.map(\.id))
        )
        var authorizations: [PluginIdentifier: PluginAuthorization] = [:]
        for item in items where item.capability != .transform {
            authorizations[item.id] = try verifier.issue(
                for: item,
                trust: trust,
                approval: approval,
                externalToolPolicy: policy,
                expiresAt: expiryDate
            )
        }
        let snapshot = try PluginManagementSnapshot(
            revision: PluginManagementRevision(lineage: 91, generation: 3),
            catalog: catalog,
            preferences: preferences,
            externalToolPolicy: policy
        )
        return StubFixture(
            catalog: catalog,
            preferences: preferences,
            policy: policy,
            snapshot: snapshot,
            items: items.filter { $0.capability != .transform },
            transformItem: transformItem,
            authorizations: authorizations,
            authority: authority,
            referenceDate: referenceDate
        )
    }

    private func assertStubError<Value>(
        _ expected: PluginExecutionStubError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> Value
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? PluginExecutionStubError, expected, file: file, line: line)
        }
    }
}

private struct StubFixture: Sendable {
    let catalog: PluginCatalog
    let preferences: PluginCatalogPreferences
    let policy: ExternalToolPolicy
    let snapshot: PluginManagementSnapshot
    let items: [PluginCatalogItem]
    let transformItem: PluginCatalogItem
    let authorizations: [PluginIdentifier: PluginAuthorization]
    let authority: StubAuthorityState
    let referenceDate: Date
}

private final class StubAuthorityState: PluginAuthorizationAuthorityStateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var state: PluginAuthorizationAuthorityState

    init(now: Date, generation: UInt64) {
        state = PluginAuthorizationAuthorityState(revocationGeneration: generation, currentTime: now)
    }

    func currentPluginAuthorizationAuthorityState() -> PluginAuthorizationAuthorityState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func set(now: Date, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        state = PluginAuthorizationAuthorityState(revocationGeneration: generation, currentTime: now)
    }
}

private func preCancelledStubError(
    _ operation: @escaping @Sendable () throws -> Void
) async -> PluginExecutionStubError? {
    await Task.detached {
        withUnsafeCurrentTask { $0?.cancel() }
        do {
            try operation()
            return nil
        } catch let error as PluginExecutionStubError {
            return error
        } catch {
            return nil
        }
    }.value
}
