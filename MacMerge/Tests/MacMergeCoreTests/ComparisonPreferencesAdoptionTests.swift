import Foundation
import MacMergeCore
import XCTest

final class ComparisonPreferencesAdoptionTests: XCTestCase {
    func testResetTargetsCoverAllModesWithExactEngineOptions() async throws {
        let initial = try snapshot(lineage: 1)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)

        let targets = try ComparisonPreferencesAdoption.targets(for: plan)

        XCTAssertEqual(targets.map(\.mode), ComparisonPreferencesMode.allCases)
        for target in targets {
            XCTAssertEqual(target.expectedRevision, plan.expectedRevision)
            XCTAssertEqual(target.adoptedRevision, plan.resultingRevision)
            XCTAssertEqual(target.expectedSHA256, plan.expectedSHA256)
            XCTAssertEqual(target.preferencesSHA256, plan.resultingSHA256)
            XCTAssertEqual(target.didChange, plan.didChange)
            XCTAssertEqual(
                target.options,
                plan.preferences.settings(for: target.mode).comparisonOpenModeOptions
            )
            if target.mode == .folder {
                XCTAssertEqual(
                    target.filenameFilter,
                    plan.preferences.folder.filenameFilter.comparisonOpenFilter
                )
            } else {
                XCTAssertNil(target.filenameFilter, "Mode: \(target.mode)")
            }
        }
    }

    func testApplyAndDefaultsTargetExactlyOneMode() async throws {
        let initial = try snapshot(lineage: 2)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let binary = try BinaryComparisonPreferences(bytesPerRow: 32)
        let plan = try await workflow.plan(.apply(.binary(binary)), expectedRevision: initial.revision)

        XCTAssertEqual(ComparisonPreferencesAdoption.affectedModes(for: plan), [.binary])
        let targets = try ComparisonPreferencesAdoption.targets(for: plan)
        let target = try XCTUnwrap(targets.only)
        XCTAssertEqual(target.mode, .binary)
        XCTAssertNil(target.filenameFilter)
        XCTAssertEqual(target.options, ComparisonPreferencesModeSettings.binary(binary).comparisonOpenModeOptions)
        XCTAssertTrue(target.didChange)
        XCTAssertEqual(target.adoptedRevision.generation, target.expectedRevision.generation + 1)
        XCTAssertNotEqual(target.preferencesSHA256, target.expectedSHA256)

        let defaultsPlan = try await workflow.plan(.defaults(.text), expectedRevision: initial.revision)
        XCTAssertEqual(ComparisonPreferencesAdoption.affectedModes(for: defaultsPlan), [.text])
    }

    func testDefaultsResetAndIsDefault() throws {
        for mode in ComparisonPreferencesMode.allCases {
            let settings = ComparisonPreferencesModeSettings.defaults(for: mode)
            XCTAssertTrue(ComparisonPreferencesAdoption.isDefault(settings))
            XCTAssertEqual(
                ComparisonPreferencesAdoption.defaultEngineOptions(for: mode),
                ComparisonPreferencesAdoption.engineOptions(for: settings)
            )
            XCTAssertEqual(
                ComparisonPreferencesAdoption.engineOptions(for: mode, in: .default),
                ComparisonPreferencesAdoption.engineOptions(for: settings)
            )
        }
        let custom = ComparisonPreferencesModeSettings.binary(
            try BinaryComparisonPreferences(bytesPerRow: 32)
        )
        XCTAssertFalse(ComparisonPreferencesAdoption.isDefault(custom))
    }

    func testFilenameFilterPathPreservesDescriptor() throws {
        let filter = try FolderFilenameFilterPreferences(
            rules: [.init(.exclude, pattern: .glob("**/*.tmp"), applicability: .files)],
            defaultDecision: .exclude,
            matchSemantics: .firstMatchWins,
            casePolicy: .insensitive
        )
        let preferences = try ComparisonPreferences(
            folder: FolderComparisonPreferences(filenameFilter: filter)
        )

        let descriptor = ComparisonPreferencesAdoption.filenameFilter(in: preferences)
        XCTAssertEqual(descriptor, filter.comparisonOpenFilter)
        XCTAssertEqual(descriptor.rules, filter.rules)
        XCTAssertEqual(descriptor.defaultDecision, .exclude)
        XCTAssertEqual(descriptor.matchSemantics, .firstMatchWins)
        XCTAssertEqual(descriptor.casePolicy, .insensitive)
    }

    func testValidateFreshnessAcceptsCurrentRejectsStale() async throws {
        let initial = try snapshot(lineage: 3)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: initial.revision
        )

        try ComparisonPreferencesAdoption.validateFreshness(plan, against: initial)

        let movedRevision = try ComparisonPreferencesRevision(lineage: 3, generation: 7)
        let moved = try ComparisonPreferencesSnapshot(
            revision: movedRevision,
            preferences: initial.preferences
        )
        assertWorkflowError(
            .staleRevision(expected: plan.expectedRevision, actual: movedRevision)
        ) {
            try ComparisonPreferencesAdoption.validateFreshness(plan, against: moved)
        }

        let diverged = try ComparisonPreferencesSnapshot(
            revision: initial.revision,
            preferences: ComparisonPreferences(
                binary: BinaryComparisonPreferences(bytesPerRow: 64)
            )
        )
        assertWorkflowError(.staleSnapshot) {
            try ComparisonPreferencesAdoption.validateFreshness(plan, against: diverged)
        }
    }

    func testTargetsEnforceWorkflowLimits() async throws {
        let initial = try snapshot(lineage: 4)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)

        XCTAssertEqual(try ComparisonPreferencesAdoption.targets(for: plan).count, 6)
        let tight = try ComparisonPreferencesWorkflowLimits(maximumPersistenceOutputBytes: 1)
        assertWorkflowError(.persistenceOutputTooLarge(maximumBytes: 1)) {
            _ = try ComparisonPreferencesAdoption.targets(for: plan, limits: tight)
        }
    }

    func testAdoptResolvesTargetsUnderWorkflowLimits() async throws {
        let initial = try snapshot(lineage: 12)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)
        let tightWorkflow = try ComparisonPreferencesWorkflow(
            snapshot: initial,
            limits: ComparisonPreferencesWorkflowLimits(maximumPersistenceOutputBytes: 1)
        )
        let tightAdopter = AdoptionTestAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )
        await assertWorkflowErrorAsync(.persistenceOutputTooLarge(maximumBytes: 1)) {
            _ = try await ComparisonPreferencesAdoption.adopt(plan, in: tightWorkflow, using: tightAdopter)
        }
        let tightState = await tightAdopter.state()
        XCTAssertEqual(tightState.compareCount, 0)
        let adopter = AdoptionTestAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )
        let (_, targets) = try await ComparisonPreferencesAdoption.adopt(plan, in: workflow, using: adopter)
        XCTAssertEqual(targets.count, 6)
    }

    func testAdoptionHelpersEnforceTightLimits() async throws {
        let initial = try snapshot(lineage: 13)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)
        let tightOutput = try ComparisonPreferencesWorkflowLimits(maximumPersistenceOutputBytes: 1)
        assertWorkflowError(.persistenceOutputTooLarge(maximumBytes: 1)) {
            try ComparisonPreferencesAdoption.validateFreshness(plan, against: initial, limits: tightOutput)
        }
        assertWorkflowError(.persistenceOutputTooLarge(maximumBytes: 1)) {
            _ = try ComparisonPreferencesAdoption.canonicalData(for: initial, limits: tightOutput)
        }
        let canonical = try ComparisonPreferencesAdoption.canonicalData(for: initial)
        let tightInput = try ComparisonPreferencesWorkflowLimits(maximumPersistenceInputBytes: 1)
        assertWorkflowError(.persistenceInputTooLarge(maximumBytes: 1)) {
            _ = try ComparisonPreferencesAdoption.decodedSnapshot(from: canonical, limits: tightInput)
        }
    }

    func testAdoptIsAtomicAndBindsReceipt() async throws {
        let initial = try snapshot(lineage: 5)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: initial.revision
        )
        let adopter = AdoptionTestAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )

        let (receipt, targets) = try await ComparisonPreferencesAdoption.adopt(
            plan,
            in: workflow,
            using: adopter
        )

        XCTAssertEqual(receipt.intentKind, .apply)
        XCTAssertEqual(receipt.mode, .binary)
        XCTAssertEqual(receipt.previousRevision, plan.expectedRevision)
        XCTAssertEqual(receipt.revision, plan.resultingRevision)
        XCTAssertEqual(receipt.didChange, plan.didChange)
        XCTAssertEqual(receipt.preferencesSHA256, plan.resultingSHA256)
        XCTAssertEqual(receipt.planningWorkUnits, plan.planningWorkUnits)
        XCTAssertEqual(targets.count, 1)
        let committed = try await workflow.snapshot()
        XCTAssertEqual(committed.revision, plan.resultingRevision)
        let state = await adopter.state()
        XCTAssertEqual(state.compareCount, 1)
        XCTAssertEqual(state.commitCount, 1)
    }

    func testAdoptNoOpPlanKeepsRevision() async throws {
        let initial = try snapshot(lineage: 6)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)
        XCTAssertFalse(plan.didChange)
        let adopter = AdoptionTestAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )

        let (receipt, targets) = try await ComparisonPreferencesAdoption.adopt(
            plan,
            in: workflow,
            using: adopter
        )

        XCTAssertFalse(receipt.didChange)
        XCTAssertEqual(receipt.revision, initial.revision)
        XCTAssertEqual(targets.count, 6)
    }

    func testAdoptStalePlanYieldsNoTargetsAndTouchesNoExecutor() async throws {
        let initial = try snapshot(lineage: 7)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let stalePlan = try await workflow.plan(
            .apply(.table(try TableComparisonPreferences())),
            expectedRevision: initial.revision
        )
        let firstPlan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: initial.revision
        )
        let firstAdopter = AdoptionTestAdopter(
            revision: firstPlan.expectedRevision,
            digest: firstPlan.expectedSHA256,
            preferences: initial.preferences
        )
        _ = try await workflow.execute(firstPlan, using: firstAdopter)

        let forbidden = AdoptionTestAdopter(
            revision: stalePlan.expectedRevision,
            digest: stalePlan.expectedSHA256,
            preferences: initial.preferences
        )
        await assertWorkflowErrorAsync(
            .staleRevision(expected: stalePlan.expectedRevision, actual: firstPlan.resultingRevision)
        ) {
            _ = try await ComparisonPreferencesAdoption.adopt(stalePlan, in: workflow, using: forbidden)
        }
        let state = await forbidden.state()
        XCTAssertEqual(state.compareCount, 0)
        XCTAssertEqual(state.commitCount, 0)
    }

    func testAdoptFailureYieldsNoTargetsAndRequiresReload() async throws {
        let initial = try snapshot(lineage: 8)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)
        let adopter = AdoptionTestAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences,
            behavior: .fail(domain: "AdoptionTests.executor", code: 409)
        )

        await assertExecutorFailure {
            _ = try await ComparisonPreferencesAdoption.adopt(plan, in: workflow, using: adopter)
        }
        let state = await adopter.state()
        XCTAssertEqual(state.commitCount, 0)
        await assertWorkflowErrorAsync(.reloadRequired) { _ = try await workflow.snapshot() }
    }

    func testAdoptCancelYieldsNoTargetsAndNoCommit() async throws {
        let initial = try snapshot(lineage: 9)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(
            .apply(.binary(try BinaryComparisonPreferences(bytesPerRow: 32))),
            expectedRevision: initial.revision
        )
        let adopter = AdoptionTestAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences,
            behavior: .cancel
        )

        await assertWorkflowErrorAsync(.cancelled) {
            _ = try await ComparisonPreferencesAdoption.adopt(plan, in: workflow, using: adopter)
        }
        let state = await adopter.state()
        XCTAssertEqual(state.commitCount, 0)
        let current = try await workflow.snapshot()
        XCTAssertEqual(current, initial)
    }

    func testSharedHooksCancelEveryAdoptionEntryPoint() async throws {
        let initial = try snapshot(lineage: 10)
        let workflow = try ComparisonPreferencesWorkflow(snapshot: initial)
        let plan = try await workflow.plan(.reset, expectedRevision: initial.revision)
        let adopter = AdoptionTestAdopter(
            revision: plan.expectedRevision,
            digest: plan.expectedSHA256,
            preferences: initial.preferences
        )
        let cancel: @Sendable () throws -> Void = {
            throw ComparisonPreferencesWorkflowError.cancelled
        }

        assertWorkflowError(.cancelled) {
            try ComparisonPreferencesWorkflowTestHooks.withCancellationCheckpoint(cancel) {
                _ = try ComparisonPreferencesAdoption.targets(for: plan)
            }
        }
        assertWorkflowError(.cancelled) {
            try ComparisonPreferencesWorkflowTestHooks.withCancellationCheckpoint(cancel) {
                try ComparisonPreferencesAdoption.validateFreshness(plan, against: initial)
            }
        }
        assertWorkflowError(.cancelled) {
            try ComparisonPreferencesWorkflowTestHooks.withCancellationCheckpoint(cancel) {
                _ = try ComparisonPreferencesAdoption.canonicalData(for: initial)
            }
        }
        assertWorkflowError(.cancelled) {
            try ComparisonPreferencesWorkflowTestHooks.withCancellationCheckpoint(cancel) {
                _ = try ComparisonPreferencesAdoption.decodedSnapshot(from: initial.encodedData())
            }
        }
        await assertWorkflowErrorAsync(.cancelled) {
            try await ComparisonPreferencesWorkflowTestHooks.withCancellationCheckpoint(cancel) {
                _ = try await ComparisonPreferencesAdoption.adopt(plan, in: workflow, using: adopter)
            }
        }
        let state = await adopter.state()
        XCTAssertEqual(state.compareCount, 0)
    }

    func testCanonicalDataRoundTripsSnapshot() throws {
        let initial = try snapshot(lineage: 11)
        let data = try ComparisonPreferencesAdoption.canonicalData(for: initial)
        XCTAssertEqual(data, try initial.encodedData())
        XCTAssertEqual(try ComparisonPreferencesAdoption.decodedSnapshot(from: data), initial)
    }
}

private extension ComparisonPreferencesAdoptionTests {
    func snapshot(
        lineage: UInt64,
        generation: UInt64 = 0
    ) throws -> ComparisonPreferencesSnapshot {
        try ComparisonPreferencesSnapshot(
            revision: ComparisonPreferencesRevision(lineage: lineage, generation: generation)
        )
    }

    func assertWorkflowError<T>(
        _ expected: ComparisonPreferencesWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ComparisonPreferencesWorkflowError, expected, file: file, line: line)
        }
    }

    func assertWorkflowErrorAsync<T>(
        _ expected: ComparisonPreferencesWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ComparisonPreferencesWorkflowError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func assertExecutorFailure<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected executor failure", file: file, line: line)
        } catch let error as ComparisonPreferencesWorkflowError {
            guard case .executorFailed(let domain, let code) = error else {
                return XCTFail("Unexpected workflow error: \(error)", file: file, line: line)
            }
            XCTAssertTrue(domain.hasPrefix("sha256:"), file: file, line: line)
            XCTAssertEqual(code, 409, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private enum AdoptionTestBehavior: Sendable {
    case adopt
    case cancel
    case fail(domain: String, code: Int)
}

private actor AdoptionTestAdopter: ComparisonPreferencesAdopting {
    private var revision: ComparisonPreferencesRevision
    private var digest: [UInt8]
    private var preferences: ComparisonPreferences
    private let behavior: AdoptionTestBehavior
    private var compareCount = 0
    private var commitCount = 0

    init(
        revision: ComparisonPreferencesRevision,
        digest: [UInt8],
        preferences: ComparisonPreferences,
        behavior: AdoptionTestBehavior = .adopt
    ) {
        self.revision = revision
        self.digest = digest
        self.preferences = preferences
        self.behavior = behavior
    }

    func adoptComparisonPreferences(
        _ contract: ComparisonPreferencesAdoptionContract
    ) async throws -> ComparisonPreferencesExecutorReceipt {
        compareCount += 1
        switch behavior {
        case .cancel:
            throw CancellationError()
        case .fail(let domain, let code):
            throw NSError(domain: domain, code: code)
        case .adopt:
            guard revision == contract.expectedRevision,
                digest == contract.expectedPreferencesSHA256
            else {
                throw NSError(domain: "AdoptionTests.CAS", code: 409)
            }
            revision = contract.adoptedRevision
            digest = contract.preferencesSHA256
            preferences = contract.preferences
            commitCount += 1
            return .adopted(contract)
        }
    }

    func state() -> (compareCount: Int, commitCount: Int) {
        (compareCount, commitCount)
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
