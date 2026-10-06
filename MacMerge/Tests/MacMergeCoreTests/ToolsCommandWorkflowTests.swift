import Foundation
import MacMergeCore
import XCTest

final class ToolsCommandWorkflowTests: XCTestCase {
    typealias Workflow = ToolsCommandWorkflow

    func testCommandsAndDefaultConfigurationStatesRouteEveryToolsCommand() throws {
        XCTAssertEqual(
            Workflow.Command.allCases,
            [.filters, .generatePatch, .generateReport, .generateArchive]
        )
        XCTAssertEqual(Workflow.IntentKind.allCases, [.configuration, .execution])

        let fixture = try makeFixture()
        let states = Workflow.commandStates(in: fixture.context)

        XCTAssertEqual(states.map(\.command), Workflow.Command.allCases)
        XCTAssertEqual(states.map(\.intentKind), Array(repeating: .configuration, count: 4))
        XCTAssertTrue(states.allSatisfy(\.isEnabled))
        XCTAssertTrue(states.allSatisfy(\.canExecute))
        XCTAssertTrue(states.allSatisfy { $0.availability == .enabled })
        XCTAssertTrue(states.allSatisfy { $0.disabledReason == nil })
        for state in states {
            XCTAssertTrue(try state.expectedContext.matches(fixture.context))
        }
    }

    func testCommandStatePrecedenceCoversLifecycleCapabilityAndExecutionBinding() throws {
        let fixture = try makeFixture()
        let noWorkspace = try currentState(lifecycle: .noComparison)
        let workspaceOnly = try currentState(
            workspace: fixture.target.workspace,
            lifecycle: .noComparison
        )
        XCTAssertEqual(
            Workflow.commandState(
                for: .filters,
                in: context(state: noWorkspace)
            ).availability,
            .disabled(.noWorkspace)
        )
        XCTAssertEqual(
            Workflow.commandState(
                for: .filters,
                in: context(state: workspaceOnly)
            ).availability,
            .disabled(.noComparison)
        )

        let lifecycleReasons: [(Workflow.ComparisonLifecycle, Workflow.DisabledReason)] = [
            (.loading, .comparisonLoading),
            (.refreshing, .comparisonRefreshing),
            (.stale, .comparisonStale),
            (.failed, .comparisonFailed),
            (.cancelled, .comparisonCancelled)
        ]
        for (lifecycle, reason) in lifecycleReasons {
            let state = try currentState(
                target: fixture.target,
                lifecycle: lifecycle
            )
            XCTAssertEqual(
                Workflow.commandState(for: .generateReport, in: context(state: state)).availability,
                .disabled(reason)
            )
        }

        let locked = try currentState(
            target: fixture.target,
            lifecycle: .failed,
            isSessionLocked: true
        )
        XCTAssertEqual(
            Workflow.commandState(for: .generateArchive, in: context(state: locked)).availability,
            .disabled(.sessionLocked)
        )

        let unavailable = capabilities(
            report: Workflow.CommandCapability(
                configuration: .unavailable(.configurationUnavailable),
                execution: .unavailable(.executorUnavailable)
            )
        )
        XCTAssertEqual(
            Workflow.commandState(
                for: .generateReport,
                in: context(capabilities: unavailable, state: fixture.state)
            ).availability,
            .disabled(.capabilityUnavailable(.configuration, .configurationUnavailable))
        )
        XCTAssertEqual(
            Workflow.commandState(
                for: .generateReport,
                intentKind: .execution,
                in: context(capabilities: unavailable, state: fixture.state)
            ).availability,
            .disabled(.capabilityUnavailable(.execution, .executorUnavailable))
        )
        XCTAssertEqual(
            Workflow.commandState(
                for: .generatePatch,
                intentKind: .execution,
                in: fixture.context
            ).availability,
            .disabled(.executionBindingUnavailable(.generatePatch))
        )
    }

    func testConfigurationPayloadsRemainExactAndRouteOnlyToBoundTarget() throws {
        let fixture = try makeFixture()
        let filters = filtersConfiguration()
        let intents: [Workflow.ConfigurationIntent] = [
            .filters(filters),
            .patch(patchRequest()),
            .report(reportRequest()),
            .archive(archiveRequest())
        ]

        for configuration in intents {
            let invocation = Workflow.Invocation(
                target: fixture.target,
                intent: .configuration(configuration)
            )
            let state = try Workflow.commandState(for: invocation, in: fixture.context)
            let plan = try Workflow.plan(invocation, in: fixture.context)

            XCTAssertTrue(state.isEnabled, "Command \(configuration.command)")
            XCTAssertEqual(plan.invocation, invocation)
            XCTAssertEqual(plan.receipt.command, configuration.command)
            XCTAssertEqual(plan.receipt.intentKind, .configuration)
            XCTAssertEqual(plan.receipt.target, fixture.target)
            XCTAssertEqual(
                plan.requiredEffects,
                [
                    .validateCurrentContext,
                    .routeConfiguration(configuration)
                ])
            XCTAssertEqual(plan.receipt.requiredEffectCount, 2)
            XCTAssertEqual(plan.authorityRequirements.count, 1)
            guard case .ownerStateLease(let cas) = plan.authorityRequirements[0] else {
                return XCTFail("Configuration route lacks owner-state lease")
            }
            XCTAssertTrue(try cas.matches(fixture.context))
        }

        let changedTarget = try target(
            workspaceRevision: fixture.target.workspace.revision,
            comparisonRevision: fixture.target.comparison.revision + 1,
            sourceRevisions: fixture.target.sources.map(\.revision)
        )
        let changedState = try currentState(target: changedTarget, lifecycle: .current)
        let changedContext = context(state: changedState)
        let invocation = Workflow.Invocation(
            target: fixture.target,
            intent: .configuration(.filters(filters))
        )
        XCTAssertEqual(
            try Workflow.commandState(for: invocation, in: changedContext).availability,
            .disabled(.commandTargetChanged)
        )
        assertWorkflowError(.commandTargetChanged) {
            try Workflow.plan(invocation, in: changedContext)
        }
    }

    func testExecutionIntentFactoriesBindExactPayloadOwnerAndCommand() throws {
        let owner = bindingReference(seed: 20, revision: 7)
        let filterCondition = validFilterCondition()
        let patch = patchRequest()
        let report = reportRequest()
        let archive = archiveRequest()
        let issued = [
            Workflow.ExecutionIntentFactory.filters(
                ownerBinding: owner,
                condition: filterCondition,
                limits: FilterTestLimits.default
            ),
            Workflow.ExecutionIntentFactory.patch(ownerBinding: owner, request: patch),
            Workflow.ExecutionIntentFactory.report(
                ownerBinding: owner,
                request: report,
                expectedSnapshot: ComparisonReportWorkflowSnapshotReference(report.snapshot)
            ),
            Workflow.ExecutionIntentFactory.archive(
                ownerBinding: owner,
                request: archive,
                expectedSnapshot: ArchiveGenerationSnapshotReference(archive.snapshot)
            )
        ]

        XCTAssertEqual(issued.map { $0.intent.command }, Workflow.Command.allCases)
        for pair in issued {
            XCTAssertEqual(pair.binding.owner, owner)
            XCTAssertEqual(pair.intent.ownerBinding, owner)
            XCTAssertEqual(pair.binding.payload, pair.intent.payloadIdentity)
            XCTAssertNotEqual(
                pair.binding.payload,
                Workflow.ExecutionIntentFactory.filters(
                    ownerBinding: owner,
                    condition: filterCondition
                ).binding.payload
            )
        }

        guard case .filters(let filterRequest) = issued[0].intent,
            case .patch(let patchRequest) = issued[1].intent,
            case .report(let reportRequest) = issued[2].intent,
            case .archive(let archiveRequest) = issued[3].intent
        else {
            return XCTFail("Execution intent factory returned wrong cases")
        }
        XCTAssertEqual(filterRequest.condition, filterCondition)
        XCTAssertEqual(filterRequest.limits, .default)
        XCTAssertEqual(patchRequest.request, patch)
        XCTAssertEqual(reportRequest.request, report)
        XCTAssertEqual(
            reportRequest.expectedSnapshot,
            ComparisonReportWorkflowSnapshotReference(report.snapshot)
        )
        XCTAssertEqual(archiveRequest.request, archive)
        XCTAssertEqual(
            archiveRequest.expectedSnapshot,
            ArchiveGenerationSnapshotReference(archive.snapshot)
        )
    }

    func testExecutionPlansExposeExactEffectsAuthoritiesAndDelegatedContracts() throws {
        let fixture = try makeFixture()
        let invocations = try executionInvocations(target: fixture.target)

        for item in invocations {
            let plan = try Workflow.plan(item.invocation, in: item.context)

            XCTAssertEqual(plan.invocation, item.invocation)
            XCTAssertEqual(plan.requiredEffects, item.effects)
            XCTAssertEqual(plan.receipt.requiredEffectCount, item.effects.count)
            XCTAssertEqual(plan.receipt.command, item.invocation.intent.command)
            XCTAssertEqual(plan.receipt.target.sources, fixture.target.sources)
            XCTAssertEqual(plan.executorContract, .required)
            XCTAssertEqual(
                plan.executorContract.stateValidation,
                .exactCapabilityWorkspaceComparisonAndOrderedSourceCASBeforeRoutingAndExecution
            )
            XCTAssertEqual(
                plan.executorContract.requestBinding,
                .preserveExactRequestsReferencesLimitsAndConfigurationWithoutRegeneration
            )
            XCTAssertEqual(
                plan.executorContract.authority,
                .enforceDelegatedContractAndPlanAuthorityWithinOwnerStateLease
            )
            XCTAssertEqual(
                plan.executorContract.effectOrder,
                .executeEveryRequiredEffectOnceInOrderUsingImmediateDelegatedPlan
            )

            guard case .ownerStateLease(let cas) = plan.authorityRequirements[0] else {
                return XCTFail("Execution route lacks owner-state lease")
            }
            XCTAssertTrue(try cas.matches(item.context))
            switch item.invocation.intent.command {
            case .filters:
                XCTAssertEqual(plan.authorityRequirements.count, 1)
            case .generatePatch:
                XCTAssertEqual(
                    plan.authorityRequirements,
                    [
                        .ownerStateLease(Workflow.ContextCAS(item.context)),
                        .patch(.required)
                    ])
            case .generateReport:
                XCTAssertEqual(
                    plan.authorityRequirements,
                    [
                        .ownerStateLease(Workflow.ContextCAS(item.context)),
                        .report(.required)
                    ])
            case .generateArchive:
                XCTAssertEqual(
                    plan.authorityRequirements,
                    [
                        .ownerStateLease(Workflow.ContextCAS(item.context)),
                        .archive(.required)
                    ])
            }
        }
    }

    func testContextCASRejectsEveryExactCapabilityWorkspaceComparisonSourceAndStateChange() throws {
        let fixture = try makeFixture(sourceRevisions: [3, 5])
        let cas = Workflow.ContextCAS(fixture.context)
        let changedCapabilities = context(
            capabilities: capabilities(
                filters: Workflow.CommandCapability(
                    configuration: .supported,
                    execution: .unavailable(.executorUnavailable)
                )
            ),
            state: fixture.state
        )
        let changedWorkspaceTarget = try target(
            workspaceRevision: fixture.target.workspace.revision + 1,
            comparisonRevision: fixture.target.comparison.revision,
            sourceRevisions: fixture.target.sources.map(\.revision)
        )
        let changedWorkspace = context(
            state: try currentState(target: changedWorkspaceTarget, lifecycle: .current)
        )
        let changedComparisonTarget = try target(
            workspaceRevision: fixture.target.workspace.revision,
            comparisonRevision: fixture.target.comparison.revision + 1,
            sourceRevisions: fixture.target.sources.map(\.revision)
        )
        let changedComparison = context(
            state: try currentState(target: changedComparisonTarget, lifecycle: .current)
        )
        let changedSourceTarget = try target(
            workspaceRevision: fixture.target.workspace.revision,
            comparisonRevision: fixture.target.comparison.revision,
            sourceRevisions: [3, 6]
        )
        let changedSource = context(
            state: try currentState(target: changedSourceTarget, lifecycle: .current)
        )
        let reorderedTarget = try Workflow.CommandTarget(
            workspace: fixture.target.workspace,
            comparison: fixture.target.comparison,
            sources: Array(fixture.target.sources.reversed())
        )
        let reordered = context(
            state: try currentState(target: reorderedTarget, lifecycle: .current)
        )
        let refreshing = context(
            state: try currentState(target: fixture.target, lifecycle: .refreshing)
        )
        let locked = context(
            state: try currentState(
                target: fixture.target,
                lifecycle: .current,
                isSessionLocked: true
            )
        )

        let cases: [(Workflow.Context, Workflow.WorkflowError)] = [
            (changedCapabilities, .capabilitiesChanged),
            (
                changedWorkspace,
                .staleWorkspace(
                    expected: fixture.target.workspace,
                    actual: changedWorkspaceTarget.workspace
                )
            ),
            (
                changedComparison,
                .staleComparison(
                    expected: fixture.target.comparison,
                    actual: changedComparisonTarget.comparison
                )
            ),
            (changedSource, .sourceReferencesChanged),
            (reordered, .sourceReferencesChanged),
            (refreshing, .currentStateChanged),
            (locked, .currentStateChanged)
        ]
        XCTAssertTrue(try cas.matches(fixture.context))
        XCTAssertNoThrow(try cas.validate(fixture.context))
        for (actual, expected) in cases {
            XCTAssertFalse(try cas.matches(actual))
            assertWorkflowError(expected) { try cas.validate(actual) }
        }
        assertWorkflowError(.tooManySourceReferences(maximum: 1)) {
            try cas.validate(fixture.context, limits: limits(maximumSourceReferences: 1))
        }
    }

    func testStaleExecutionPayloadBindingsDisableStateAndRejectPlanning() throws {
        let fixture = try makeFixture()
        let owner = bindingReference(seed: 30, revision: 1)
        let issued = Workflow.ExecutionIntentFactory.patch(
            ownerBinding: owner,
            request: patchRequest()
        )
        let invocation = Workflow.Invocation(
            target: fixture.target,
            intent: .execution(issued.intent)
        )
        let missing = fixture.context
        XCTAssertEqual(
            try Workflow.commandState(for: invocation, in: missing).availability,
            .disabled(.executionBindingChanged(.generatePatch))
        )
        assertWorkflowError(.executionBindingChanged(.generatePatch)) {
            try Workflow.plan(invocation, in: missing)
        }

        let otherPayload = Workflow.ExecutionIntentFactory.patch(
            ownerBinding: owner,
            request: patchRequest()
        ).binding
        let staleContext = try context(
            target: fixture.target,
            bindings: Workflow.ExecutionBindings(patch: otherPayload)
        )
        XCTAssertEqual(
            try Workflow.commandState(for: invocation, in: staleContext).availability,
            .disabled(.executionBindingChanged(.generatePatch))
        )
        assertWorkflowError(.executionBindingChanged(.generatePatch)) {
            try Workflow.plan(invocation, in: staleContext)
        }

        let otherOwner = bindingReference(seed: 31, revision: owner.revision)
        let ownerChanged = Workflow.ExecutionIntentFactory.patch(
            ownerBinding: otherOwner,
            request: patchRequest()
        )
        let ownerChangedContext = try context(
            target: fixture.target,
            bindings: Workflow.ExecutionBindings(patch: ownerChanged.binding)
        )
        let ownerChangedInvocation = Workflow.Invocation(
            target: fixture.target,
            intent: .execution(ownerChanged.intent)
        )
        XCTAssertNoThrow(try Workflow.plan(ownerChangedInvocation, in: ownerChangedContext))
        assertWorkflowError(.executionBindingChanged(.generatePatch)) {
            try Workflow.plan(invocation, in: ownerChangedContext)
        }
    }

    func testDelegatedSnapshotReferenceMismatchesFailBeforeReportAndArchivePlanning() throws {
        let fixture = try makeFixture()
        let owner = bindingReference(seed: 40, revision: 2)
        let report = reportRequest()
        let wrongReportReference = ComparisonReportWorkflowSnapshotReference(
            identity: report.snapshot.identity,
            generation: report.snapshot.generation + 1
        )
        let reportIssued = Workflow.ExecutionIntentFactory.report(
            ownerBinding: owner,
            request: report,
            expectedSnapshot: wrongReportReference
        )
        let reportContext = try context(
            target: fixture.target,
            bindings: Workflow.ExecutionBindings(report: reportIssued.binding)
        )
        assertWorkflowError(.delegatedReferenceMismatch(.generateReport)) {
            try Workflow.plan(
                Workflow.Invocation(
                    target: fixture.target,
                    intent: .execution(reportIssued.intent)
                ),
                in: reportContext
            )
        }

        let archive = archiveRequest()
        let wrongArchiveReference = ArchiveGenerationSnapshotReference(
            identity: archive.snapshot.identity,
            generation: archive.snapshot.generation + 1
        )
        let archiveIssued = Workflow.ExecutionIntentFactory.archive(
            ownerBinding: owner,
            request: archive,
            expectedSnapshot: wrongArchiveReference
        )
        let archiveContext = try context(
            target: fixture.target,
            bindings: Workflow.ExecutionBindings(archive: archiveIssued.binding)
        )
        assertWorkflowError(.delegatedReferenceMismatch(.generateArchive)) {
            try Workflow.plan(
                Workflow.Invocation(
                    target: fixture.target,
                    intent: .execution(archiveIssued.intent)
                ),
                in: archiveContext
            )
        }
    }

    func testInvalidCurrentStateAndDuplicateSourceIdentityFailClosed() throws {
        let fixture = try makeFixture()
        XCTAssertThrowsError(
            try Workflow.CurrentState(
                workspace: fixture.target.workspace,
                target: nil,
                lifecycle: .current
            )
        ) { error in
            XCTAssertEqual(error as? Workflow.WorkflowError, .invalidCurrentState)
        }
        XCTAssertThrowsError(
            try Workflow.CurrentState(
                workspace: nil,
                target: fixture.target,
                lifecycle: .current
            )
        ) { error in
            XCTAssertEqual(error as? Workflow.WorkflowError, .invalidCurrentState)
        }

        let duplicate = sourceReference(seed: 50, revision: 1)
        XCTAssertThrowsError(
            try Workflow.CommandTarget(
                workspace: fixture.target.workspace,
                comparison: fixture.target.comparison,
                sources: [duplicate, duplicate]
            )
        ) { error in
            XCTAssertEqual(
                error as? Workflow.WorkflowError,
                .duplicateSourceIdentity(duplicate.identity)
            )
        }
    }

    func testPlansAndPlanningReceiptsHaveFreshIdentityWithExactPublicMetadata() throws {
        let fixture = try makeFixture()
        let invocation = Workflow.Invocation(
            target: fixture.target,
            intent: .configuration(.filters(filtersConfiguration()))
        )
        let first = try Workflow.plan(invocation, in: fixture.context)
        let second = try Workflow.plan(invocation, in: fixture.context)

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.invocation, second.invocation)
        XCTAssertEqual(first.requiredEffects, second.requiredEffects)
        XCTAssertEqual(first.authorityRequirements, second.authorityRequirements)
        XCTAssertEqual(first.receipt.command, second.receipt.command)
        XCTAssertEqual(first.receipt.intentKind, second.receipt.intentKind)
        XCTAssertEqual(first.receipt.target, second.receipt.target)
        XCTAssertEqual(first.receipt.requiredEffectCount, second.receipt.requiredEffectCount)
        XCTAssertEqual(first.receipt.plannedWorkUnits, second.receipt.plannedWorkUnits)
    }

    func testConfigurationAndFilterExecutionCompleteWithExactResultBindings() async throws {
        let fixture = try makeFixture()
        let configurationPlan = try Workflow.plan(
            Workflow.Invocation(
                target: fixture.target,
                intent: .configuration(.filters(filtersConfiguration()))
            ),
            in: fixture.context
        )
        let configurationOutcome = await Workflow.execute(
            configurationPlan,
            with: CompletingExecutor(),
            currentContext: { fixture.context }
        )
        guard case .completed(let configurationReceipt) = configurationOutcome,
            case .configuration(let configurationResult) = configurationReceipt.result
        else {
            return XCTFail("Expected completed configuration")
        }
        XCTAssertEqual(configurationReceipt.planningReceipt, configurationPlan.receipt)
        XCTAssertEqual(configurationReceipt.completedEffects, configurationPlan.requiredEffects)
        XCTAssertEqual(configurationResult.command, .filters)
        XCTAssertEqual(configurationResult.target, fixture.target)
        XCTAssertEqual(configurationResult.expectedContext, configurationPlan.expectedContext)
        XCTAssertEqual(configurationResult.intent, .filters(filtersConfiguration()))

        let filterItem = try executionInvocations(target: fixture.target)[0]
        let filterPlan = try Workflow.plan(filterItem.invocation, in: filterItem.context)
        let filterOutcome = await Workflow.execute(
            filterPlan,
            with: CompletingExecutor(),
            currentContext: { filterItem.context }
        )
        guard case .completed(let filterReceipt) = filterOutcome,
            case .filters(let result) = filterReceipt.result,
            case .execution(.filters(let request)) = filterPlan.invocation.intent
        else {
            return XCTFail("Expected completed filter evaluation")
        }
        XCTAssertEqual(filterReceipt.completedEffects, filterPlan.requiredEffects)
        XCTAssertEqual(result.request, request)
        XCTAssertEqual(
            result.evaluation,
            try FilterTestEvaluator.evaluate(request.condition, limits: request.limits)
        )
    }

    func testFilterCompletionRejectsUnboundEvaluationAndReportsUncertainEffect() async throws {
        let fixture = try makeFixture()
        let item = try executionInvocations(target: fixture.target)[0]
        let plan = try Workflow.plan(item.invocation, in: item.context)
        let probe = WorkflowProbe()
        let outcome = await Workflow.execute(
            plan,
            with: InvalidFilterEvaluationExecutor(probe: probe),
            currentContext: { item.context }
        )

        let errors = await probe.errors()
        XCTAssertEqual(errors, [.invalidExecutionOutcome])
        guard case .effectUncertain(let receipt) = outcome else {
            return XCTFail("Expected uncertain filter effect")
        }
        XCTAssertEqual(receipt.completedEffects, [.validateCurrentContext])
        XCTAssertEqual(receipt.uncertainEffects, [plan.requiredEffects[1]])
        XCTAssertEqual(receipt.unattemptedEffects, [])
    }

    func testPatchReportAndArchiveExecutionsBindImmediateDelegatedPlansAndNestedOutcomes() async throws {
        let fixture = try makeFixture()
        let items = try executionInvocations(target: fixture.target).dropFirst()

        for item in items {
            let plan = try Workflow.plan(item.invocation, in: item.context)
            let outcome = await Workflow.execute(
                plan,
                with: CompletingExecutor(),
                currentContext: { item.context }
            )
            guard case .completed(let receipt) = outcome else {
                return XCTFail("Expected completed \(item.invocation.intent.command) execution")
            }
            XCTAssertEqual(receipt.completedEffects, plan.requiredEffects)
            XCTAssertEqual(receipt.planningReceipt, plan.receipt)
            switch receipt.result {
            case .patch(let result):
                guard case .execution(.patch(let request)) = plan.invocation.intent else {
                    return XCTFail("Patch result bound to wrong intent")
                }
                XCTAssertEqual(result.request, request)
                XCTAssertEqual(result.delegatedPlan, try PatchGenerationWorkflow.plan(request.request))
                XCTAssertEqual(result.outcome.state, .notCommitted(.rejected("nested-patch")))
            case .report(let result):
                guard case .execution(.report(let request)) = plan.invocation.intent else {
                    return XCTFail("Report result bound to wrong intent")
                }
                XCTAssertEqual(result.request, request)
                XCTAssertEqual(
                    result.delegatedPlan,
                    try ComparisonReportWorkflowPlanner.plan(
                        request.request,
                        expecting: request.expectedSnapshot
                    )
                )
                guard case .completed(let nested) = result.outcome else {
                    return XCTFail("Expected nested report completion")
                }
                XCTAssertEqual(nested.snapshot, request.expectedSnapshot)
                XCTAssertEqual(nested.outputs.map(\.disposition), [.copiedToClipboard])
            case .archive(let result):
                guard case .execution(.archive(let request)) = plan.invocation.intent else {
                    return XCTFail("Archive result bound to wrong intent")
                }
                XCTAssertEqual(result.request, request)
                XCTAssertEqual(result.delegatedPlan, try ArchiveGenerationWorkflow.plan(request.request))
                guard case .completed(let nested) = result.outcome else {
                    return XCTFail("Expected nested archive completion")
                }
                XCTAssertEqual(nested.planSHA256, result.delegatedPlan.receipt.planSHA256)
                XCTAssertEqual(nested.archivedItemCount, result.delegatedPlan.manifest.entries.count)
            default:
                XCTFail("Unexpected result case for delegated execution")
            }
        }
    }

    func testForeignNestedReportAndArchiveOutcomesAreRejected() async throws {
        let fixture = try makeFixture()
        let items = try Array(executionInvocations(target: fixture.target).suffix(2))
        let foreignReportPlan = try ComparisonReportWorkflowPlanner.plan(
            reportRequest(identitySeed: 91)
        )
        let foreignArchivePlan = try ArchiveGenerationWorkflow.plan(
            archiveRequest(identitySeed: 92, destinationLeaf: "foreign.zip")
        )

        for item in items {
            let plan = try Workflow.plan(item.invocation, in: item.context)
            let probe = WorkflowProbe()
            let executor = ForeignNestedOutcomeExecutor(
                foreignReportPlan: foreignReportPlan,
                foreignArchivePlan: foreignArchivePlan,
                probe: probe
            )
            let outcome = await Workflow.execute(
                plan,
                with: executor,
                currentContext: { item.context }
            )

            let errors = await probe.errors()
            XCTAssertEqual(errors, [.invalidExecutionOutcome])
            guard case .effectUncertain(let receipt) = outcome else {
                return XCTFail("Expected uncertainty for foreign nested outcome")
            }
            XCTAssertEqual(receipt.completedEffects, Array(plan.requiredEffects.prefix(3)))
            XCTAssertEqual(receipt.uncertainEffects, [plan.requiredEffects[3]])
            XCTAssertEqual(receipt.unattemptedEffects, [])
        }
    }

    func testTerminalReceiptsExposeExactCompletedFailedCancelledAndUncertainPrefixes() async throws {
        let fixture = try makeFixture()
        let item = try executionInvocations(target: fixture.target)[1]
        let plan = try Workflow.plan(item.invocation, in: item.context)

        let notCommitted = await Workflow.execute(
            plan,
            with: PrefixOutcomeExecutor(mode: .authorityUnavailable),
            currentContext: { item.context }
        )
        guard case .notCommitted(let blocked) = notCommitted else {
            return XCTFail("Expected zero-effect authority failure")
        }
        XCTAssertEqual(blocked.blockedEffect, plan.requiredEffects[0])
        XCTAssertEqual(blocked.reason, .authorityUnavailable)
        XCTAssertEqual(blocked.unattemptedEffects, Array(plan.requiredEffects.dropFirst()))

        let failed = await Workflow.execute(
            plan,
            with: PrefixOutcomeExecutor(mode: .failPlanning),
            currentContext: { item.context }
        )
        guard case .failedAfterEffects(let failure) = failed else {
            return XCTFail("Expected failed-after-effects receipt")
        }
        XCTAssertEqual(failure.completedEffects, [.validateCurrentContext])
        XCTAssertEqual(failure.failedEffect, plan.requiredEffects[1])
        XCTAssertEqual(failure.reason, .delegatedPlanningFailed)
        XCTAssertEqual(failure.unattemptedEffects, Array(plan.requiredEffects.dropFirst(2)))

        let cancelled = await Workflow.execute(
            plan,
            with: PrefixOutcomeExecutor(mode: .cancelAfterValidation),
            currentContext: { item.context }
        )
        guard case .cancelled(let cancellation) = cancelled else {
            return XCTFail("Expected cancellation receipt")
        }
        XCTAssertEqual(cancellation.completedEffects, [.validateCurrentContext])
        XCTAssertEqual(cancellation.unattemptedEffects, Array(plan.requiredEffects.dropFirst()))

        let uncertain = await Workflow.execute(
            plan,
            with: PrefixOutcomeExecutor(mode: .uncertainPlanning),
            currentContext: { item.context }
        )
        guard case .effectUncertain(let uncertainty) = uncertain else {
            return XCTFail("Expected uncertainty receipt")
        }
        XCTAssertEqual(uncertainty.completedEffects, [.validateCurrentContext])
        XCTAssertEqual(uncertainty.uncertainEffects, [plan.requiredEffects[1]])
        XCTAssertEqual(uncertainty.unattemptedEffects, Array(plan.requiredEffects.dropFirst(2)))
    }

    func testSessionAndPlanIdentityRejectCrossPlanCrossSessionAndReplayedOutcomes() async throws {
        let fixture = try makeFixture()
        let invocation = Workflow.Invocation(
            target: fixture.target,
            intent: .configuration(.filters(filtersConfiguration()))
        )
        let firstPlan = try Workflow.plan(invocation, in: fixture.context)
        let secondPlan = try Workflow.plan(invocation, in: fixture.context)
        let capture = SessionCapture()
        let firstOutcome = await Workflow.execute(
            firstPlan,
            with: CapturingUncertainExecutor(capture: capture),
            currentContext: { fixture.context }
        )
        guard case .effectUncertain = firstOutcome,
            let captured = await capture.value()
        else {
            return XCTFail("Expected captured first session")
        }

        let probe = WorkflowProbe()
        let secondOutcome = await Workflow.execute(
            secondPlan,
            with: CrossIdentityExecutor(captured: captured, probe: probe),
            currentContext: { fixture.context }
        )
        let errors = await probe.errors()
        XCTAssertEqual(
            errors,
            [.invalidExecutionOutcome, .invalidExecutionOutcome, .invalidExecutionOutcome]
        )
        guard case .notCommitted(let receipt) = secondOutcome else {
            return XCTFail("Expected authenticated second-session noncommit")
        }
        XCTAssertEqual(receipt.reason, .authorityUnavailable)

        let replayProbe = WorkflowProbe()
        let normalized = await Workflow.execute(
            secondPlan,
            with: ReplayedOutcomeExecutor(outcome: firstOutcome, probe: replayProbe),
            currentContext: { fixture.context }
        )
        let replayErrors = await replayProbe.errors()
        XCTAssertEqual(replayErrors, [])
        guard case .effectUncertain(let normalizedReceipt) = normalized else {
            return XCTFail("Foreign outcome should normalize to current uncertainty")
        }
        XCTAssertEqual(normalizedReceipt.completedEffects, [])
        XCTAssertEqual(normalizedReceipt.uncertainEffects, secondPlan.requiredEffects)
        XCTAssertEqual(normalizedReceipt.unattemptedEffects, [])
        XCTAssertNotEqual(normalized, firstOutcome)
    }

    func testEveryLimitRejectsValuesOutsideHardEnvelope() throws {
        let fixture = try makeFixture()
        let invocation = Workflow.Invocation(
            target: fixture.target,
            intent: .configuration(.filters(Workflow.FiltersConfiguration()))
        )
        let cases: [(Workflow.Limit, Workflow.Limits)] = [
            (
                .sourceReferences,
                limits(maximumSourceReferences: Workflow.Limits.hardMaximumSourceReferences + 1)
            ),
            (
                .boundItems,
                limits(maximumBoundItems: Workflow.Limits.hardMaximumBoundItems + 1)
            ),
            (
                .filterConditions,
                limits(maximumFilterConditions: Workflow.Limits.hardMaximumFilterConditions + 1)
            ),
            (.filterConditionDepth, limits(maximumFilterConditionDepth: 0)),
            (
                .filterRules,
                limits(maximumFilterRules: Workflow.Limits.hardMaximumFilterRules + 1)
            ),
            (.requiredEffects, limits(maximumRequiredEffects: 0)),
            (
                .workUnits,
                limits(maximumWorkUnits: Workflow.Limits.hardMaximumWorkUnits + 1)
            ),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0))
        ]
        XCTAssertEqual(Set(cases.map(\.0)), Set(Workflow.Limit.allCases))
        for (limit, invalidLimits) in cases {
            assertWorkflowError(.invalidLimit(limit)) {
                try Workflow.plan(invocation, in: fixture.context, limits: invalidLimits)
            }
            assertWorkflowError(.invalidLimit(limit)) {
                try Workflow.commandState(
                    for: invocation,
                    in: fixture.context,
                    limits: invalidLimits
                )
            }
        }
    }

    func testRuntimeSourceBoundFilterEffectAndDelegatedItemLimitsFailExactly() throws {
        let fixture = try makeFixture(sourceRevisions: [1, 2])
        let configuration = Workflow.Invocation(
            target: fixture.target,
            intent: .configuration(.filters(filtersConfiguration()))
        )
        assertWorkflowError(.tooManySourceReferences(maximum: 1)) {
            try Workflow.plan(
                configuration,
                in: fixture.context,
                limits: limits(maximumSourceReferences: 1)
            )
        }

        let patchItem = try executionInvocations(target: fixture.target)[1]
        assertWorkflowError(.boundItemLimitExceeded(maximum: 0)) {
            try Workflow.plan(
                patchItem.invocation,
                in: patchItem.context,
                limits: limits(maximumBoundItems: 0)
            )
        }
        assertWorkflowError(.requiredEffectLimitExceeded(maximum: 3)) {
            try Workflow.plan(
                patchItem.invocation,
                in: patchItem.context,
                limits: limits(maximumRequiredEffects: 3)
            )
        }

        let owner = bindingReference(seed: 61, revision: 1)
        let leaf = validFilterCondition()
        let nested = Workflow.ExecutionIntentFactory.filters(
            ownerBinding: owner,
            condition: .not(.not(leaf))
        )
        let nestedContext = try context(
            target: fixture.target,
            bindings: Workflow.ExecutionBindings(filters: nested.binding)
        )
        let nestedInvocation = Workflow.Invocation(
            target: fixture.target,
            intent: .execution(nested.intent)
        )
        assertWorkflowError(.filterConditionDepthExceeded(maximum: 2)) {
            try Workflow.plan(
                nestedInvocation,
                in: nestedContext,
                limits: limits(maximumFilterConditionDepth: 2)
            )
        }

        let broad = Workflow.ExecutionIntentFactory.filters(
            ownerBinding: owner,
            condition: .all([leaf, leaf])
        )
        let broadContext = try context(
            target: fixture.target,
            bindings: Workflow.ExecutionBindings(filters: broad.binding)
        )
        let broadInvocation = Workflow.Invocation(
            target: fixture.target,
            intent: .execution(broad.intent)
        )
        assertWorkflowError(.filterConditionLimitExceeded(maximum: 2)) {
            try Workflow.plan(
                broadInvocation,
                in: broadContext,
                limits: limits(maximumFilterConditions: 2)
            )
        }
        assertWorkflowError(.filterRuleLimitExceeded(maximum: 1)) {
            try Workflow.plan(
                broadInvocation,
                in: broadContext,
                limits: limits(maximumFilterRules: 1)
            )
        }

        let oversizedFilterLimits = FilterTestLimits(
            maximumCaseCount: FilterTestLimits.default.maximumCaseCount + 1
        )
        let invalid = Workflow.ExecutionIntentFactory.filters(
            ownerBinding: owner,
            condition: leaf,
            limits: oversizedFilterLimits
        )
        let invalidContext = try context(
            target: fixture.target,
            bindings: Workflow.ExecutionBindings(filters: invalid.binding)
        )
        assertWorkflowError(.invalidFilterTestLimits) {
            try Workflow.plan(
                Workflow.Invocation(
                    target: fixture.target,
                    intent: .execution(invalid.intent)
                ),
                in: invalidContext
            )
        }
    }

    func testWorkBudgetAcceptsExactPlanCostAndRejectsOneUnitLess() throws {
        let fixture = try makeFixture(sourceRevisions: [2, 4])
        let invocation = Workflow.Invocation(
            target: fixture.target,
            intent: .configuration(.filters(filtersConfiguration()))
        )
        let baseline = try Workflow.plan(invocation, in: fixture.context)
        XCTAssertGreaterThan(baseline.receipt.plannedWorkUnits, 0)

        let exact = try Workflow.plan(
            invocation,
            in: fixture.context,
            limits: limits(maximumWorkUnits: baseline.receipt.plannedWorkUnits)
        )
        XCTAssertEqual(exact.receipt.plannedWorkUnits, baseline.receipt.plannedWorkUnits)
        assertWorkflowError(
            .workLimitExceeded(maximumUnits: baseline.receipt.plannedWorkUnits - 1)
        ) {
            try Workflow.plan(
                invocation,
                in: fixture.context,
                limits: limits(maximumWorkUnits: baseline.receipt.plannedWorkUnits - 1)
            )
        }
    }

    func testPreCancelledConstructionPlanningValidationAndExecutionStopInDomain() async throws {
        let fixture = try makeFixture()
        let invocation = Workflow.Invocation(
            target: fixture.target,
            intent: .configuration(.filters(filtersConfiguration()))
        )
        let plan = try Workflow.plan(invocation, in: fixture.context)
        let operations: [@Sendable () throws -> Void] = [
            { _ = try Workflow.commandState(for: invocation, in: fixture.context) },
            { _ = try Workflow.plan(invocation, in: fixture.context) },
            { try plan.validateCurrentContext(fixture.context) },
            { try plan.expectedContext.validate(fixture.context) },
            { _ = try plan.expectedContext.matches(fixture.context) },
            {
                _ = try Workflow.CommandTarget(
                    workspace: fixture.target.workspace,
                    comparison: fixture.target.comparison,
                    sources: fixture.target.sources
                )
            }
        ]
        for (index, operation) in operations.enumerated() {
            let error = await Task { () -> Workflow.WorkflowError? in
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    try operation()
                    return nil
                } catch {
                    return error as? Workflow.WorkflowError
                }
            }.value
            XCTAssertEqual(error, .cancelled, "Operation \(index)")
        }

        let probe = WorkflowProbe()
        let outcome = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await Workflow.execute(
                plan,
                with: InvocationCountingExecutor(probe: probe),
                currentContext: { fixture.context }
            )
        }.value
        let invocationCount = await probe.invocationCount()
        XCTAssertEqual(invocationCount, 0)
        guard case .cancelled(let receipt) = outcome else {
            return XCTFail("Pre-cancelled execution must return cancellation receipt")
        }
        XCTAssertEqual(receipt.completedEffects, [])
        XCTAssertEqual(receipt.unattemptedEffects, plan.requiredEffects)
    }

    func testDiagnosticsAreDeterministicAndRedactPayloadIdentityPathAndSnapshotValues() throws {
        let fixture = try makeFixture()
        let secret = "SECRET-tools-command-value"
        let secretFilters = Workflow.FiltersConfiguration(
            filename: Workflow.FilenameFilterConfiguration(
                rules: [FilenameFilterRule(.exclude, pattern: .glob(secret))]
            ),
            lineFilters: [LineFilterRule(pattern: secret)],
            substitutions: [SubstitutionRule(pattern: secret, replacement: secret)]
        )
        let invocation = Workflow.Invocation(
            target: fixture.target,
            intent: .configuration(.filters(secretFilters))
        )
        let plan = try Workflow.plan(invocation, in: fixture.context)
        let values: [Any] = [
            fixture.target.workspace.identity,
            fixture.target.workspace,
            fixture.target.comparison.identity,
            fixture.target.comparison,
            fixture.target.sources[0].identity,
            fixture.target.sources[0],
            fixture.target,
            fixture.state,
            Workflow.ContextCAS(fixture.context),
            secretFilters.filename as Any,
            secretFilters,
            Workflow.ConfigurationIntent.filters(secretFilters),
            Workflow.Intent.configuration(.filters(secretFilters)),
            invocation,
            plan,
            plan.receipt,
            plan.authorityRequirements,
            plan.requiredEffects
        ]
        let forbidden = [
            secret,
            fixture.target.workspace.identity.rawValue.uuidString,
            fixture.target.comparison.identity.rawValue.uuidString,
            fixture.target.sources[0].identity.rawValue.uuidString
        ]
        for value in values {
            let first = diagnosticText(value)
            let second = diagnosticText(value)
            XCTAssertEqual(first, second)
            for sentinel in forbidden {
                XCTAssertFalse(first.contains(sentinel), "Leaked \(sentinel) from \(first)")
            }
        }

        XCTAssertEqual(
            fixture.target.description,
            "ToolsCommandWorkflow.CommandTarget(workspace:<opaque>, comparison:<opaque>, sources:1)"
        )
        XCTAssertEqual(
            invocation.description,
            "ToolsCommandWorkflow.Invocation(command:filters, kind:configuration, target:<opaque>, value:<redacted>)"
        )
        XCTAssertEqual(
            plan.requiredEffects.map(\.description),
            [
                "validateCurrentContext",
                "routeConfiguration(command:filters, value:<redacted>)"
            ]
        )
        XCTAssertEqual(
            Workflow.WorkflowError.duplicateSourceIdentity(
                fixture.target.sources[0].identity
            ).localizedDescription,
            "Tools command state repeats an opaque source identity."
        )
    }

    func testInvalidFilterDiagnosticsRemainDeterministicAndPayloadRedactedThroughResult() async throws {
        let fixture = try makeFixture()
        let secret = "SECRET-invalid-["
        let condition = FilterTestCondition.test(
            .line(
                LineFilterTestCase(
                    rule: LineFilterRule(pattern: secret),
                    input: "SECRET-invalid-input"
                )
            )
        )
        let issued = Workflow.ExecutionIntentFactory.filters(
            ownerBinding: bindingReference(seed: 75, revision: 1),
            condition: condition
        )
        let executionContext = try context(
            target: fixture.target,
            bindings: Workflow.ExecutionBindings(filters: issued.binding)
        )
        let plan = try Workflow.plan(
            Workflow.Invocation(
                target: fixture.target,
                intent: .execution(issued.intent)
            ),
            in: executionContext
        )
        let outcome = await Workflow.execute(
            plan,
            with: CompletingExecutor(),
            currentContext: { executionContext }
        )
        guard case .completed(let receipt) = outcome,
            case .filters(let result) = receipt.result
        else {
            return XCTFail("Expected completed invalid filter evaluation")
        }
        XCTAssertEqual(result.evaluation.outcome, .invalid)
        XCTAssertFalse(result.evaluation.diagnostics.isEmpty)
        XCTAssertEqual(
            result.evaluation.diagnostics.map(\.description),
            result.evaluation.diagnostics.map(\.description)
        )
        let text = diagnosticText(result)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("SECRET-invalid-input"))
        XCTAssertTrue(text.contains("<redacted>"))
    }
}

extension ToolsCommandWorkflowTests {
    fileprivate struct Fixture {
        let target: Workflow.CommandTarget
        let state: Workflow.CurrentState
        let context: Workflow.Context
    }

    fileprivate struct ExecutionItem {
        let invocation: Workflow.Invocation
        let context: Workflow.Context
        let effects: [Workflow.RequiredEffect]
    }

    fileprivate func makeFixture(sourceRevisions: [UInt64] = [3]) throws -> Fixture {
        let target = try target(sourceRevisions: sourceRevisions)
        let state = try currentState(target: target, lifecycle: .current)
        return Fixture(target: target, state: state, context: context(state: state))
    }

    fileprivate func target(
        workspaceRevision: UInt64 = 11,
        comparisonRevision: UInt64 = 13,
        sourceRevisions: [UInt64] = [3]
    ) throws -> Workflow.CommandTarget {
        try Workflow.CommandTarget(
            workspace: Workflow.WorkspaceReference(
                identity: Workflow.WorkspaceIdentity(rawValue: uuid(1)),
                revision: workspaceRevision
            ),
            comparison: Workflow.ComparisonReference(
                identity: Workflow.ComparisonIdentity(rawValue: uuid(2)),
                revision: comparisonRevision
            ),
            sources: sourceRevisions.enumerated().map { index, revision in
                sourceReference(seed: UInt64(index + 3), revision: revision)
            }
        )
    }

    fileprivate func sourceReference(seed: UInt64, revision: UInt64) -> Workflow.SourceReference {
        Workflow.SourceReference(
            identity: Workflow.SourceIdentity(rawValue: uuid(seed)),
            revision: revision
        )
    }

    fileprivate func bindingReference(seed: UInt64, revision: UInt64) -> Workflow.ExecutionBindingReference {
        Workflow.ExecutionBindingReference(
            identity: Workflow.ExecutionBindingIdentity(rawValue: uuid(seed)),
            revision: revision
        )
    }

    fileprivate func currentState(
        workspace: Workflow.WorkspaceReference? = nil,
        target: Workflow.CommandTarget? = nil,
        bindings: Workflow.ExecutionBindings = Workflow.ExecutionBindings(),
        lifecycle: Workflow.ComparisonLifecycle,
        isSessionLocked: Bool = false
    ) throws -> Workflow.CurrentState {
        try Workflow.CurrentState(
            workspace: workspace ?? target?.workspace,
            target: target,
            executionBindings: bindings,
            lifecycle: lifecycle,
            isSessionLocked: isSessionLocked
        )
    }

    fileprivate func context(
        capabilities: Workflow.Capabilities? = nil,
        state: Workflow.CurrentState
    ) -> Workflow.Context {
        Workflow.Context(
            capabilities: capabilities ?? self.capabilities(),
            currentState: state
        )
    }

    fileprivate func context(
        target: Workflow.CommandTarget,
        bindings: Workflow.ExecutionBindings
    ) throws -> Workflow.Context {
        context(
            state: try currentState(
                target: target,
                bindings: bindings,
                lifecycle: .current
            )
        )
    }

    fileprivate func capabilities(
        filters: Workflow.CommandCapability = supportedCapability(),
        patch: Workflow.CommandCapability = supportedCapability(),
        report: Workflow.CommandCapability = supportedCapability(),
        archive: Workflow.CommandCapability = supportedCapability()
    ) -> Workflow.Capabilities {
        Workflow.Capabilities(
            filters: filters,
            patch: patch,
            report: report,
            archive: archive
        )
    }

    fileprivate func filtersConfiguration() -> Workflow.FiltersConfiguration {
        Workflow.FiltersConfiguration(
            filename: Workflow.FilenameFilterConfiguration(
                rules: [FilenameFilterRule(.exclude, pattern: .glob("*.tmp"))]
            ),
            lineFilters: [LineFilterRule(pattern: "^generated")],
            substitutions: [
                SubstitutionRule(pattern: "version=[0-9]+", replacement: "version=<n>")
            ]
        )
    }

    fileprivate func validFilterCondition() -> FilterTestCondition {
        .test(
            .filename(
                FilenameFilterTestCase(
                    rules: [FilenameFilterRule(.exclude, pattern: .glob("*.tmp"))],
                    relativePath: "build/cache.tmp"
                )
            )
        )
    }

    fileprivate func patchRequest() -> PatchGenerationRequest {
        let source = PatchGenerationSource(
            id: PatchGenerationSourceID(rawValue: "tools-source"),
            oldSnapshot: PatchGenerationTextSnapshot(
                identity: .document(uuid(101)),
                revision: 3,
                text: "before\n"
            ),
            newSnapshot: PatchGenerationTextSnapshot(
                identity: .document(uuid(102)),
                revision: 5,
                text: "after\n"
            ),
            oldPath: "before.txt",
            newPath: "after.txt"
        )
        let revision = PatchGenerationClipboardRevision(
            brokerIdentifier: PatchGenerationClipboardBrokerIdentifier(rawValue: uuid(103)),
            epoch: PatchGenerationClipboardBrokerEpoch(rawValue: uuid(104)),
            value: 9
        )
        return PatchGenerationRequest(
            sources: [source],
            contextLines: 1,
            destination: .clipboard(
                PatchGenerationClipboardDestination(expectedRevision: revision)
            )
        )
    }

    fileprivate func reportRequest(identitySeed: UInt64 = 110) -> ComparisonReportWorkflowRequest {
        let report = ComparisonReport(
            title: "Tools Report",
            columns: ["Path", "Status"],
            rows: [ComparisonReportRow(values: ["file.txt", "different"])]
        )
        let snapshot = ComparisonReportWorkflowSnapshot(
            identity: ComparisonReportWorkflowSnapshotIdentity(rawValue: uuid(identitySeed)),
            generation: 17,
            source: .file(ComparisonReportFileSnapshot(report: report))
        )
        return ComparisonReportWorkflowRequest(
            snapshot: snapshot,
            format: .plainText,
            destination: .clipboard
        )
    }

    fileprivate func archiveRequest(
        identitySeed: UInt64 = 120,
        destinationLeaf: String = "archive.zip"
    ) -> ArchiveGenerationRequest {
        let sourceRoot = archiveRoot(path: "/tmp/macmerge-tools-source", seed: 121)
        let sourceURL = sourceRoot.canonicalURL.appending(path: "file.txt")
        let sourceIdentity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: sourceURL,
            root: sourceRoot,
            relativePath: "file.txt",
            kind: .regularFile,
            node: archiveNode(122)
        )
        let revision = ArchiveGenerationSourceRevision(
            identity: sourceIdentity,
            byteCount: 4,
            directoryChildCount: 0,
            directoryChildNameUTF8ByteCount: 0,
            linkCount: 1,
            permissions: 0o640,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            metadataByteCount: 4,
            modificationTimeSeconds: 1,
            modificationTimeNanoseconds: 2,
            statusChangeTimeSeconds: 3,
            statusChangeTimeNanoseconds: 4,
            contentSHA256: bytes(0x11),
            metadataSHA256: bytes(0x22)
        )
        let source = ArchiveGenerationSourceItem(
            requestedURL: sourceURL,
            revision: revision,
            accessAuthority: .ambient
        )
        let entry = ArchiveGenerationComparisonEntry(
            id: ArchiveGenerationEntryID(rawValue: "file"),
            relativePath: "file.txt",
            status: .leftOnly,
            left: source,
            right: nil
        )
        let snapshot = ArchiveGenerationComparisonSnapshot(
            identity: ArchiveGenerationSnapshotIdentity(rawValue: uuid(identitySeed)),
            generation: 19,
            comparisonKind: .folder,
            entries: [entry]
        )
        let destinationRoot = archiveRoot(path: "/tmp/macmerge-tools-output", seed: 123)
        let destinationURL = destinationRoot.canonicalURL.appending(path: destinationLeaf)
        let destination = ArchiveGenerationDestination(
            requestedURL: destinationURL,
            intent: .createNew(
                ArchiveGenerationCanonicalDestinationLocation(
                    canonicalURL: destinationURL,
                    parent: destinationRoot
                )
            ),
            accessAuthority: .ambient
        )
        return ArchiveGenerationRequest(
            snapshot: snapshot,
            selection: .all(side: .left),
            destination: destination
        )
    }

    fileprivate func archiveRoot(
        path: String,
        seed: UInt64
    ) -> ArchiveGenerationCanonicalDirectoryIdentity {
        ArchiveGenerationCanonicalDirectoryIdentity(
            canonicalURL: URL(filePath: path, directoryHint: .isDirectory),
            node: archiveNode(seed)
        )
    }

    fileprivate func archiveNode(_ seed: UInt64) -> ArchiveGenerationNodeIdentity {
        ArchiveGenerationNodeIdentity(
            deviceID: seed,
            fileID: seed + 1,
            generation: UInt32(truncatingIfNeeded: seed + 2)
        )
    }

    fileprivate func executionInvocations(target: Workflow.CommandTarget) throws -> [ExecutionItem] {
        let filter = Workflow.ExecutionIntentFactory.filters(
            ownerBinding: bindingReference(seed: 201, revision: 1),
            condition: validFilterCondition()
        )
        let patch = Workflow.ExecutionIntentFactory.patch(
            ownerBinding: bindingReference(seed: 202, revision: 2),
            request: patchRequest()
        )
        let reportRequest = reportRequest()
        let report = Workflow.ExecutionIntentFactory.report(
            ownerBinding: bindingReference(seed: 203, revision: 3),
            request: reportRequest,
            expectedSnapshot: ComparisonReportWorkflowSnapshotReference(reportRequest.snapshot)
        )
        let archiveRequest = archiveRequest()
        let archive = Workflow.ExecutionIntentFactory.archive(
            ownerBinding: bindingReference(seed: 204, revision: 4),
            request: archiveRequest,
            expectedSnapshot: ArchiveGenerationSnapshotReference(archiveRequest.snapshot)
        )
        let issued = [filter, patch, report, archive]
        return try issued.map { pair in
            let bindings: Workflow.ExecutionBindings
            switch pair.intent.command {
            case .filters:
                bindings = Workflow.ExecutionBindings(filters: pair.binding)
            case .generatePatch:
                bindings = Workflow.ExecutionBindings(patch: pair.binding)
            case .generateReport:
                bindings = Workflow.ExecutionBindings(report: pair.binding)
            case .generateArchive:
                bindings = Workflow.ExecutionBindings(archive: pair.binding)
            }
            let invocation = Workflow.Invocation(
                target: target,
                intent: .execution(pair.intent)
            )
            let effects: [Workflow.RequiredEffect]
            switch pair.intent {
            case .filters(let request):
                effects = [.validateCurrentContext, .evaluateFilters(request)]
            case .patch(let request):
                effects = [
                    .validateCurrentContext,
                    .planPatch(request),
                    .revalidateCurrentContext,
                    .executePatchPlan
                ]
            case .report(let request):
                effects = [
                    .validateCurrentContext,
                    .planReport(request),
                    .revalidateCurrentContext,
                    .executeReportPlan
                ]
            case .archive(let request):
                effects = [
                    .validateCurrentContext,
                    .planArchive(request),
                    .revalidateCurrentContext,
                    .executeArchivePlan
                ]
            }
            return ExecutionItem(
                invocation: invocation,
                context: try context(target: target, bindings: bindings),
                effects: effects
            )
        }
    }

    fileprivate func limits(
        maximumSourceReferences: Int = Workflow.Limits.default.maximumSourceReferences,
        maximumBoundItems: Int = Workflow.Limits.default.maximumBoundItems,
        maximumFilterConditions: Int = Workflow.Limits.default.maximumFilterConditions,
        maximumFilterConditionDepth: Int = Workflow.Limits.default.maximumFilterConditionDepth,
        maximumFilterRules: Int = Workflow.Limits.default.maximumFilterRules,
        maximumRequiredEffects: Int = Workflow.Limits.default.maximumRequiredEffects,
        maximumWorkUnits: UInt64 = Workflow.Limits.default.maximumWorkUnits,
        cancellationCheckInterval: Int = Workflow.Limits.default.cancellationCheckInterval
    ) -> Workflow.Limits {
        Workflow.Limits(
            maximumSourceReferences: maximumSourceReferences,
            maximumBoundItems: maximumBoundItems,
            maximumFilterConditions: maximumFilterConditions,
            maximumFilterConditionDepth: maximumFilterConditionDepth,
            maximumFilterRules: maximumFilterRules,
            maximumRequiredEffects: maximumRequiredEffects,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    fileprivate func assertWorkflowError<T>(
        _ expected: Workflow.WorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? Workflow.WorkflowError, expected, file: file, line: line)
        }
    }
}

private func supportedCapability() -> ToolsCommandWorkflow.CommandCapability {
    ToolsCommandWorkflow.CommandCapability(configuration: .supported, execution: .supported)
}

private func uuid(_ value: UInt64) -> UUID {
    let suffix = String(format: "%012llX", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}

private func bytes(_ value: UInt8) -> [UInt8] {
    [UInt8](repeating: value, count: 32)
}

private func diagnosticText(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    let children = mirror.children.map { child in
        "\(child.label ?? "_")=\(String(describing: child.value))"
    }.joined(separator: ",")
    return "\(String(describing: value))|\(String(reflecting: value))|\(children)"
}

private actor WorkflowProbe {
    private var recordedErrors: [ToolsCommandWorkflow.WorkflowError] = []
    private var count = 0

    func record(_ error: Error) {
        if let workflowError = error as? ToolsCommandWorkflow.WorkflowError {
            recordedErrors.append(workflowError)
        }
    }

    func recordInvocation() {
        count += 1
    }

    func errors() -> [ToolsCommandWorkflow.WorkflowError] {
        recordedErrors
    }

    func invocationCount() -> Int {
        count
    }
}

private struct CompletingExecutor: ToolsCommandWorkflow.PlanExecutor {
    func execute(
        _ plan: ToolsCommandWorkflow.Plan,
        session: ToolsCommandWorkflow.ExecutionSession,
        currentContext: @escaping @Sendable () async throws -> ToolsCommandWorkflow.Context
    ) async -> ToolsCommandWorkflow.ExecutionOutcome {
        do {
            var completedCount = 0
            let first = try session.beginNextEffect(plan: plan)
            try session.completeContextValidation(
                plan: plan,
                permit: first,
                currentContext: try await currentContext()
            )
            completedCount += 1

            let completed: ToolsCommandWorkflow.CompletedEffectsReceipt
            switch plan.invocation.intent {
            case .configuration:
                let preparation = try session.prepareConfigurationEffects(plan: plan)
                let permit = try session.beginNextEffect(plan: plan)
                completed = try session.completeConfigurationEffects(
                    plan: plan,
                    preparation: preparation,
                    permit: permit
                )
            case .execution(.filters(let request)):
                let preparation = try session.prepareFilterEffects(plan: plan)
                let permit = try session.beginNextEffect(plan: plan)
                completed = try session.completeFilterEffects(
                    plan: plan,
                    preparation: preparation,
                    permit: permit,
                    evaluation: try FilterTestEvaluator.evaluate(
                        request.condition,
                        limits: request.limits
                    )
                )
            case .execution(.patch):
                let planningPermit = try session.beginNextEffect(plan: plan)
                let preparation = try session.preparePatchEffects(
                    plan: plan,
                    permit: planningPermit
                )
                completedCount += 1
                let validationPermit = try session.beginNextEffect(plan: plan)
                try session.completeContextValidation(
                    plan: plan,
                    permit: validationPermit,
                    currentContext: try await currentContext()
                )
                completedCount += 1
                completed = try await session.executePatchEffects(
                    plan: plan,
                    preparation: preparation,
                    with: NestedPatchExecutor()
                )
            case .execution(.report):
                let planningPermit = try session.beginNextEffect(plan: plan)
                let preparation = try session.prepareReportEffects(
                    plan: plan,
                    permit: planningPermit
                )
                completedCount += 1
                let validationPermit = try session.beginNextEffect(plan: plan)
                try session.completeContextValidation(
                    plan: plan,
                    permit: validationPermit,
                    currentContext: try await currentContext()
                )
                completedCount += 1
                completed = try await session.executeReportEffects(
                    plan: plan,
                    preparation: preparation,
                    with: NestedReportExecutor()
                )
            case .execution(.archive(let request)):
                let planningPermit = try session.beginNextEffect(plan: plan)
                let preparation = try session.prepareArchiveEffects(
                    plan: plan,
                    permit: planningPermit
                )
                completedCount += 1
                let validationPermit = try session.beginNextEffect(plan: plan)
                try session.completeContextValidation(
                    plan: plan,
                    permit: validationPermit,
                    currentContext: try await currentContext()
                )
                completedCount += 1
                completed = try await session.executeArchiveEffects(
                    plan: plan,
                    preparation: preparation,
                    currentSnapshot: { request.request.snapshot },
                    with: NestedArchiveExecutor()
                )
            }
            return try ToolsCommandWorkflow.ExecutionOutcomeFactory.completed(
                plan: plan,
                session: session,
                receipt: completed
            )
        } catch {
            preconditionFailure("Unexpected completing-executor error: \(error)")
        }
    }
}

private struct NestedPatchExecutor: PatchGenerationPlanExecutor {
    func execute(
        _: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
            session: session,
            reason: .rejected("nested-patch")
        )
    }
}

private struct NestedReportExecutor: ComparisonReportPlanExecutor {
    func execute(
        _ plan: ComparisonReportWorkflowPlan,
        validating _: ComparisonReportWorkflowSnapshot,
        linkedReports _: [ComparisonReportLinkedReport]
    ) async -> ComparisonReportExecutionOutcome {
        ComparisonReportExecutionOutcomeFactory.completed(
            plan: plan,
            dispositions: [.copiedToClipboard],
            openOutcome: .notRequested
        )
    }
}

private struct NestedArchiveExecutor: ArchiveGenerationPlanExecutor {
    func execute(
        _ plan: ArchiveGenerationPlan,
        currentSnapshot _: @escaping @Sendable () async throws -> ArchiveGenerationComparisonSnapshot
    ) async -> ArchiveGenerationExecutionOutcome {
        let digest = bytes(0xA5)
        let parent = plan.destination.intent.canonicalParent
        let destinationURL = plan.destination.intent.canonicalURL
        let identity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: destinationURL,
            root: parent,
            relativePath: destinationURL.lastPathComponent,
            kind: .regularFile,
            node: ArchiveGenerationNodeIdentity(deviceID: 900, fileID: 901, generation: 902)
        )
        let revision = ArchiveGenerationSourceRevision(
            identity: identity,
            byteCount: min(1, plan.manifest.planningArchiveByteEnvelope),
            directoryChildCount: 0,
            directoryChildNameUTF8ByteCount: 0,
            linkCount: 1,
            permissions: plan.manifest.options.destinationPermissions,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            metadataByteCount: 0,
            modificationTimeSeconds: 1,
            modificationTimeNanoseconds: 0,
            statusChangeTimeSeconds: 1,
            statusChangeTimeNanoseconds: 0,
            contentSHA256: digest,
            metadataSHA256: bytes(0x5A)
        )
        return ArchiveGenerationExecutionOutcomeFactory.completed(
            plan: plan,
            committedRevision: revision,
            archiveContentSHA256: digest
        )
    }
}

private struct InvalidFilterEvaluationExecutor: ToolsCommandWorkflow.PlanExecutor {
    let probe: WorkflowProbe

    func execute(
        _ plan: ToolsCommandWorkflow.Plan,
        session: ToolsCommandWorkflow.ExecutionSession,
        currentContext: @escaping @Sendable () async throws -> ToolsCommandWorkflow.Context
    ) async -> ToolsCommandWorkflow.ExecutionOutcome {
        do {
            let validation = try session.beginNextEffect(plan: plan)
            try session.completeContextValidation(
                plan: plan,
                permit: validation,
                currentContext: try await currentContext()
            )
            let preparation = try session.prepareFilterEffects(plan: plan)
            let evaluation = try session.beginNextEffect(plan: plan)
            do {
                _ = try session.completeFilterEffects(
                    plan: plan,
                    preparation: preparation,
                    permit: evaluation,
                    evaluation: FilterTestEvaluation(outcome: .failed, results: [], work: 0)
                )
            } catch {
                await probe.record(error)
            }
            return try ToolsCommandWorkflow.ExecutionOutcomeFactory.effectUncertain(
                plan: plan,
                session: session,
                completedEffectCount: 1,
                uncertainEffectIndices: [1]
            )
        } catch {
            preconditionFailure("Unexpected invalid-filter executor error: \(error)")
        }
    }
}

private struct ForeignNestedOutcomeExecutor: ToolsCommandWorkflow.PlanExecutor {
    let foreignReportPlan: ComparisonReportWorkflowPlan
    let foreignArchivePlan: ArchiveGenerationPlan
    let probe: WorkflowProbe

    func execute(
        _ plan: ToolsCommandWorkflow.Plan,
        session: ToolsCommandWorkflow.ExecutionSession,
        currentContext: @escaping @Sendable () async throws -> ToolsCommandWorkflow.Context
    ) async -> ToolsCommandWorkflow.ExecutionOutcome {
        do {
            let first = try session.beginNextEffect(plan: plan)
            try session.completeContextValidation(
                plan: plan,
                permit: first,
                currentContext: try await currentContext()
            )
            let preparation: ToolsCommandWorkflow.PreparedEffectsReceipt
            switch plan.invocation.intent {
            case .execution(.report):
                let permit = try session.beginNextEffect(plan: plan)
                preparation = try session.prepareReportEffects(plan: plan, permit: permit)
            case .execution(.archive):
                let permit = try session.beginNextEffect(plan: plan)
                preparation = try session.prepareArchiveEffects(plan: plan, permit: permit)
            default:
                preconditionFailure("Foreign nested executor requires report or archive")
            }
            let validation = try session.beginNextEffect(plan: plan)
            try session.completeContextValidation(
                plan: plan,
                permit: validation,
                currentContext: try await currentContext()
            )
            do {
                switch plan.invocation.intent {
                case .execution(.report):
                    _ = try await session.executeReportEffects(
                        plan: plan,
                        preparation: preparation,
                        with: ForeignReportExecutor(plan: foreignReportPlan)
                    )
                case .execution(.archive(let request)):
                    _ = try await session.executeArchiveEffects(
                        plan: plan,
                        preparation: preparation,
                        currentSnapshot: { request.request.snapshot },
                        with: ForeignArchiveExecutor(plan: foreignArchivePlan)
                    )
                default:
                    preconditionFailure("Foreign nested executor requires report or archive")
                }
            } catch {
                await probe.record(error)
            }
            return try ToolsCommandWorkflow.ExecutionOutcomeFactory.effectUncertain(
                plan: plan,
                session: session,
                completedEffectCount: 3,
                uncertainEffectIndices: [3]
            )
        } catch {
            preconditionFailure("Unexpected foreign nested executor error: \(error)")
        }
    }
}

private struct ForeignReportExecutor: ComparisonReportPlanExecutor {
    let plan: ComparisonReportWorkflowPlan

    func execute(
        _: ComparisonReportWorkflowPlan,
        validating _: ComparisonReportWorkflowSnapshot,
        linkedReports _: [ComparisonReportLinkedReport]
    ) async -> ComparisonReportExecutionOutcome {
        ComparisonReportExecutionOutcomeFactory.completed(
            plan: plan,
            dispositions: [.copiedToClipboard],
            openOutcome: .notRequested
        )
    }
}

private struct ForeignArchiveExecutor: ArchiveGenerationPlanExecutor {
    let plan: ArchiveGenerationPlan

    func execute(
        _: ArchiveGenerationPlan,
        currentSnapshot _: @escaping @Sendable () async throws -> ArchiveGenerationComparisonSnapshot
    ) async -> ArchiveGenerationExecutionOutcome {
        ArchiveGenerationExecutionOutcomeFactory.failed(plan: plan, code: .publicationFailed)
    }
}

private struct PrefixOutcomeExecutor: ToolsCommandWorkflow.PlanExecutor {
    enum Mode: Sendable {
        case authorityUnavailable
        case failPlanning
        case cancelAfterValidation
        case uncertainPlanning
    }

    let mode: Mode

    func execute(
        _ plan: ToolsCommandWorkflow.Plan,
        session: ToolsCommandWorkflow.ExecutionSession,
        currentContext: @escaping @Sendable () async throws -> ToolsCommandWorkflow.Context
    ) async -> ToolsCommandWorkflow.ExecutionOutcome {
        do {
            if mode == .authorityUnavailable {
                return try ToolsCommandWorkflow.ExecutionOutcomeFactory.notCommitted(
                    plan: plan,
                    session: session,
                    reason: .authorityUnavailable
                )
            }
            let validation = try session.beginNextEffect(plan: plan)
            try session.completeContextValidation(
                plan: plan,
                permit: validation,
                currentContext: try await currentContext()
            )
            switch mode {
            case .authorityUnavailable:
                preconditionFailure("Handled before validation")
            case .cancelAfterValidation:
                return try ToolsCommandWorkflow.ExecutionOutcomeFactory.cancelled(
                    plan: plan,
                    session: session,
                    completedEffectCount: 1
                )
            case .failPlanning:
                _ = try session.beginNextEffect(plan: plan)
                return try ToolsCommandWorkflow.ExecutionOutcomeFactory.failed(
                    plan: plan,
                    session: session,
                    completedEffectCount: 1,
                    reason: .delegatedPlanningFailed
                )
            case .uncertainPlanning:
                _ = try session.beginNextEffect(plan: plan)
                return try ToolsCommandWorkflow.ExecutionOutcomeFactory.effectUncertain(
                    plan: plan,
                    session: session,
                    completedEffectCount: 1,
                    uncertainEffectIndices: [1]
                )
            }
        } catch {
            preconditionFailure("Unexpected prefix-outcome executor error: \(error)")
        }
    }
}

private actor SessionCapture {
    struct Value: Sendable {
        let plan: ToolsCommandWorkflow.Plan
        let session: ToolsCommandWorkflow.ExecutionSession
        let permit: ToolsCommandWorkflow.EffectPermit
    }

    private var captured: Value?

    func store(
        plan: ToolsCommandWorkflow.Plan,
        session: ToolsCommandWorkflow.ExecutionSession,
        permit: ToolsCommandWorkflow.EffectPermit
    ) {
        captured = Value(plan: plan, session: session, permit: permit)
    }

    func value() -> Value? {
        captured
    }
}

private struct CapturingUncertainExecutor: ToolsCommandWorkflow.PlanExecutor {
    let capture: SessionCapture

    func execute(
        _ plan: ToolsCommandWorkflow.Plan,
        session: ToolsCommandWorkflow.ExecutionSession,
        currentContext _: @escaping @Sendable () async throws -> ToolsCommandWorkflow.Context
    ) async -> ToolsCommandWorkflow.ExecutionOutcome {
        do {
            let permit = try session.beginNextEffect(plan: plan)
            await capture.store(plan: plan, session: session, permit: permit)
            return try ToolsCommandWorkflow.ExecutionOutcomeFactory.effectUncertain(
                plan: plan,
                session: session,
                uncertainEffectIndices: [0]
            )
        } catch {
            preconditionFailure("Unexpected capture executor error: \(error)")
        }
    }
}

private struct CrossIdentityExecutor: ToolsCommandWorkflow.PlanExecutor {
    let captured: SessionCapture.Value
    let probe: WorkflowProbe

    func execute(
        _ plan: ToolsCommandWorkflow.Plan,
        session: ToolsCommandWorkflow.ExecutionSession,
        currentContext: @escaping @Sendable () async throws -> ToolsCommandWorkflow.Context
    ) async -> ToolsCommandWorkflow.ExecutionOutcome {
        do {
            do {
                _ = try session.beginNextEffect(plan: captured.plan)
            } catch {
                await probe.record(error)
            }
            do {
                try session.completeContextValidation(
                    plan: plan,
                    permit: captured.permit,
                    currentContext: try await currentContext()
                )
            } catch {
                await probe.record(error)
            }
            do {
                _ = try captured.session.beginNextEffect(plan: plan)
            } catch {
                await probe.record(error)
            }
            return try ToolsCommandWorkflow.ExecutionOutcomeFactory.notCommitted(
                plan: plan,
                session: session,
                reason: .authorityUnavailable
            )
        } catch {
            preconditionFailure("Unexpected cross-identity executor error: \(error)")
        }
    }
}

private struct ReplayedOutcomeExecutor: ToolsCommandWorkflow.PlanExecutor {
    let outcome: ToolsCommandWorkflow.ExecutionOutcome
    let probe: WorkflowProbe

    func execute(
        _: ToolsCommandWorkflow.Plan,
        session _: ToolsCommandWorkflow.ExecutionSession,
        currentContext _: @escaping @Sendable () async throws -> ToolsCommandWorkflow.Context
    ) async -> ToolsCommandWorkflow.ExecutionOutcome {
        await probe.recordInvocation()
        return outcome
    }
}

private struct InvocationCountingExecutor: ToolsCommandWorkflow.PlanExecutor {
    let probe: WorkflowProbe

    func execute(
        _ plan: ToolsCommandWorkflow.Plan,
        session: ToolsCommandWorkflow.ExecutionSession,
        currentContext _: @escaping @Sendable () async throws -> ToolsCommandWorkflow.Context
    ) async -> ToolsCommandWorkflow.ExecutionOutcome {
        await probe.recordInvocation()
        do {
            return try ToolsCommandWorkflow.ExecutionOutcomeFactory.notCommitted(
                plan: plan,
                session: session,
                reason: .authorityUnavailable
            )
        } catch {
            preconditionFailure("Unexpected counting-executor error: \(error)")
        }
    }
}
