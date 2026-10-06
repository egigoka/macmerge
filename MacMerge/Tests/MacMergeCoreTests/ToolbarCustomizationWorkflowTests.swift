import Foundation
import MacMergeCore
import XCTest

final class ToolbarCustomizationWorkflowTests: XCTestCase {
    private typealias CAS = ToolbarCustomizationWorkflow.ConfigurationCAS
    private typealias Command = ToolbarCustomizationWorkflow.Command
    private typealias Edit = ToolbarCustomizationWorkflow.Edit
    private typealias Item = ToolbarCustomizationWorkflow.Item
    private typealias Limits = ToolbarCustomizationWorkflow.Limits
    private typealias Policy = ToolbarCustomizationWorkflow.Policy
    private typealias Snapshot = ToolbarCustomizationWorkflow.Snapshot
    private typealias Store = ToolbarCustomizationWorkflow.Store
    private typealias Transaction = ToolbarCustomizationWorkflow.Transaction
    private typealias Workflow = ToolbarCustomizationWorkflow
    private typealias WorkflowError = ToolbarCustomizationWorkflowError

    func testVisibilityAndEveryVisibleSizeAreEditable() throws {
        for visibility in ToolbarConfiguration.Visibility.allCases {
            for size in ToolbarConfiguration.Size.allCases {
                let initial = try configuration(
                    visibility: visibility == .visible ? .hidden : .visible,
                    size: size == .small ? .huge : .small,
                    items: [.command(.save)]
                )
                let snapshot = try makeSnapshot(configuration: initial)
                let plan = try makePlan(
                    [.setVisibility(visibility), .setSize(size)],
                    in: snapshot
                )
                let successor = try XCTUnwrap(plan.successor)

                XCTAssertEqual(successor.configuration.visibility, visibility)
                XCTAssertEqual(successor.configuration.size, size)
                XCTAssertEqual(successor.configuration.items, initial.items)
                XCTAssertEqual(plan.receipt.edits.map(\.editIndex), [0, 1])
                XCTAssertEqual(plan.receipt.edits.map(\.resultingItemCount), [1, 1])
            }
        }
    }

    func testEveryEditKindProducesExactOrderedCandidateAndReceipts() throws {
        let initial = try configuration(
            items: [.command(.save), .separator, .command(.undo)]
        )
        let snapshot = try makeSnapshot(configuration: initial)
        let edits: [Edit] = [
            .setVisibility(.hidden),
            .setSize(.huge),
            .addCommand(.openComparison, at: 0),
            .addSeparator(at: 4),
            .moveItem(from: 0, to: 5),
            .removeCommand(.undo),
            .removeCommandAt(0),
            .removeSeparator(at: 0),
            .removeItem(at: 0)
        ]

        let plan = try makePlan(edits, in: snapshot)
        let successor = try XCTUnwrap(plan.successor)

        XCTAssertEqual(successor.configuration.visibility, .hidden)
        XCTAssertEqual(successor.configuration.size, .huge)
        XCTAssertEqual(successor.configuration.items, [.command(.openComparison)])
        XCTAssertEqual(plan.receipt.edits.map(\.edit), edits)
        XCTAssertEqual(plan.receipt.edits.map(\.editIndex), Array(edits.indices))
        XCTAssertEqual(
            plan.receipt.edits.map(\.resultingItemCount),
            [3, 3, 4, 5, 5, 4, 3, 2, 1]
        )
        XCTAssertEqual(plan.receipt.resultingItemCount, 1)
    }

    func testInsertionAndMoveUseOriginalArrayBoundarySemantics() throws {
        let initial = try configuration(
            items: [.command(.save), .command(.undo), .separator]
        )
        let snapshot = try makeSnapshot(configuration: initial)
        let boundaryPlan = try makePlan(
            [
                .addCommand(.openComparison, at: 0),
                .addSeparator(at: 4),
                .moveItem(from: 0, to: 5)
            ],
            in: snapshot
        )

        XCTAssertEqual(
            boundaryPlan.successor?.configuration.items,
            [
                .command(.save), .command(.undo), .separator, .separator,
                .command(.openComparison)
            ]
        )

        for edit in [Edit.moveItem(from: 0, to: 0), .moveItem(from: 0, to: 1)] {
            let unchanged = try makePlan([edit], in: snapshot)
            XCTAssertNil(unchanged.successor)
            XCTAssertEqual(unchanged.receipt.disposition, .unchanged)
            XCTAssertEqual(unchanged.receipt.edits.count, 1)
            XCTAssertEqual(unchanged.receipt.edits.first?.resultingItemCount, 3)
        }

        let movedToStart = try makePlan([.moveItem(from: 2, to: 0)], in: snapshot)
        XCTAssertEqual(
            movedToStart.successor?.configuration.items,
            [.separator, .command(.save), .command(.undo)]
        )
    }

    func testRemovalTypeIndexAndDuplicateFailuresAreExactAndAtomic() throws {
        let initial = try configuration(
            items: [.command(.save), .separator, .command(.undo)]
        )
        let snapshot = try makeSnapshot(configuration: initial)
        let cases: [(Edit, WorkflowError)] = [
            (.addCommand(.save, at: 0), .duplicateCommand(.save)),
            (.addCommand(.openComparison, at: -1), .invalidItemIndex(-1)),
            (.addSeparator(at: 4), .invalidItemIndex(4)),
            (.removeCommand(.redo), .commandNotPresent(.redo)),
            (.removeCommandAt(1), .expectedCommand(at: 1)),
            (.removeCommandAt(3), .invalidItemIndex(3)),
            (.removeSeparator(at: 0), .expectedSeparator(at: 0)),
            (.removeSeparator(at: -1), .invalidItemIndex(-1)),
            (.removeItem(at: 3), .invalidItemIndex(3)),
            (.moveItem(from: -1, to: 0), .invalidItemIndex(-1)),
            (.moveItem(from: 0, to: 4), .invalidItemIndex(4))
        ]

        for (edit, expectedError) in cases {
            assertWorkflowError(expectedError) {
                try self.makePlan([.setSize(.huge), edit], in: snapshot)
            }
            XCTAssertEqual(snapshot.configuration, initial)
        }
    }

    func testRequiredCommandsAreCanonicalUniqueAndCannotBeRemoved() async throws {
        let required: Set<Command> = [.refresh, .save, .newComparison, .save]
        let policy = Policy(requiredCommands: required)
        let snapshot = try makeSnapshot(policy: policy)

        XCTAssertEqual(required.count, 3)
        XCTAssertEqual(policy.canonicalRequiredCommands, [.newComparison, .save, .refresh])
        XCTAssertNoThrow(try Workflow.validate(snapshot.configuration, policy: policy))
        assertWorkflowError(.requiredCommandMissing(.save)) {
            try self.makePlan([.removeCommand(.save)], in: snapshot)
        }

        let store = try Store(
            identity: fixedIdentity,
            configuration: snapshot.configuration,
            policy: policy
        )
        let before = await store.snapshot()
        do {
            _ = try await store.finish(
                Transaction(snapshot: before, edits: [.removeCommand(.save)]),
                decision: .apply
            )
            XCTFail("Expected required-command failure")
        } catch {
            XCTAssertEqual(error as? WorkflowError, .requiredCommandMissing(.save))
        }
        let after = await store.snapshot()
        XCTAssertEqual(after, before)
    }

    func testResetRestoresExactWinMergeVisibilitySizeItemsAndPersistence() throws {
        let custom = try configuration(
            visibility: .hidden,
            size: .huge,
            items: [.command(.refresh), .separator, .command(.save)]
        )
        let snapshot = try makeSnapshot(configuration: custom)
        let plan = try makePlan([.resetToWinMergeDefaults], in: snapshot)
        let successor = try XCTUnwrap(plan.successor)

        XCTAssertEqual(successor.configuration, .winMergeDefault)
        XCTAssertEqual(successor.configuration.visibility, .visible)
        XCTAssertEqual(successor.configuration.size, .small)
        XCTAssertEqual(successor.configuration.items, ToolbarConfiguration.winMergeDefaultItems)
        XCTAssertEqual(successor.configuration.items.count, 39)
        XCTAssertEqual(successor.configuration.commands, Command.allCases)
        XCTAssertEqual(plan.canonicalPersistence?.data, try ToolbarConfiguration.winMergeDefault.encodedData())
        XCTAssertFalse(successor.isCustomized)
    }

    func testItemRequiredAndTransactionCountLimitsAcceptExactBoundaryAndRejectOneMore() throws {
        let sixtyThreeSeparators = Array(repeating: Item.separator, count: 63)
        let itemLimits = makeLimits(maximumItemCount: 64)
        let itemSnapshot = try makeSnapshot(
            configuration: configuration(items: sixtyThreeSeparators),
            limits: itemLimits
        )
        let exactItemPlan = try makePlan([.addSeparator(at: 63)], in: itemSnapshot)
        XCTAssertEqual(exactItemPlan.successor?.configuration.items.count, 64)

        let fullSnapshot = try makeSnapshot(
            configuration: configuration(items: Array(repeating: .separator, count: 64)),
            limits: itemLimits
        )
        assertWorkflowError(.tooManyItems(maximum: 64)) {
            try self.makePlan([.addSeparator(at: 64)], in: fullSnapshot)
        }
        assertWorkflowError(.tooManyItems(maximum: 63)) {
            try self.makeSnapshot(
                configuration: self.configuration(
                    items: Array(repeating: .separator, count: 64)
                ),
                limits: self.makeLimits(maximumItemCount: 63)
            )
        }

        let allRequired = Set(Command.allCases)
        XCTAssertNoThrow(
            try makeSnapshot(
                policy: Policy(requiredCommands: allRequired),
                limits: makeLimits(maximumRequiredCommandCount: allRequired.count)
            )
        )
        assertWorkflowError(.tooManyRequiredCommands(maximum: allRequired.count - 1)) {
            try self.makeSnapshot(
                policy: Policy(requiredCommands: allRequired),
                limits: self.makeLimits(maximumRequiredCommandCount: allRequired.count - 1)
            )
        }

        let editSnapshot = try makeSnapshot(
            configuration: configuration(items: [.command(.save)]),
            limits: makeLimits(maximumTransactionEditCount: 2)
        )
        XCTAssertNoThrow(
            try makePlan([.setSize(.medium), .setVisibility(.hidden)], in: editSnapshot)
        )
        assertWorkflowError(.tooManyTransactionEdits(maximum: 2)) {
            try self.makePlan(
                [.setSize(.medium), .setVisibility(.hidden), .setSize(.huge)],
                in: editSnapshot
            )
        }
    }

    func testPublicLimitsAcceptBothExactBoundsAndRejectFirstOutsideEachRange() {
        let lower = Limits(
            maximumItemCount: 0,
            maximumRequiredCommandCount: 0,
            maximumTransactionEditCount: 0,
            maximumPersistenceBytes: 1,
            maximumWorkUnits: 1,
            cancellationCheckInterval: 1
        )
        let upper = Limits(
            maximumItemCount: Limits.hardMaximumItemCount,
            maximumRequiredCommandCount: Limits.hardMaximumRequiredCommandCount,
            maximumTransactionEditCount: Limits.hardMaximumTransactionEditCount,
            maximumPersistenceBytes: Limits.hardMaximumPersistenceBytes,
            maximumWorkUnits: Limits.hardMaximumWorkUnits,
            cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval
        )

        XCTAssertNoThrow(try lower.validate())
        XCTAssertNoThrow(try upper.validate())
        XCTAssertEqual(Limits.hardMaximumItemCount, ToolbarConfiguration.maximumItemCount)
        XCTAssertEqual(Limits.hardMaximumRequiredCommandCount, Command.allCases.count)
        XCTAssertEqual(Limits.hardMaximumPersistenceBytes, ToolbarConfiguration.maximumEncodedBytes)

        let invalid: [(Limits, Workflow.Limit, Int)] = [
            (makeLimits(maximumItemCount: -1), .items, -1),
            (makeLimits(maximumItemCount: Limits.hardMaximumItemCount + 1), .items, 65),
            (makeLimits(maximumRequiredCommandCount: -1), .requiredCommands, -1),
            (
                makeLimits(
                    maximumRequiredCommandCount: Limits.hardMaximumRequiredCommandCount + 1
                ),
                .requiredCommands,
                Limits.hardMaximumRequiredCommandCount + 1
            ),
            (makeLimits(maximumTransactionEditCount: -1), .transactionEdits, -1),
            (
                makeLimits(
                    maximumTransactionEditCount: Limits.hardMaximumTransactionEditCount + 1
                ),
                .transactionEdits,
                Limits.hardMaximumTransactionEditCount + 1
            ),
            (makeLimits(maximumPersistenceBytes: 0), .persistenceBytes, 0),
            (
                makeLimits(maximumPersistenceBytes: Limits.hardMaximumPersistenceBytes + 1),
                .persistenceBytes,
                Limits.hardMaximumPersistenceBytes + 1
            ),
            (makeLimits(maximumWorkUnits: 0), .workUnits, 0),
            (
                makeLimits(maximumWorkUnits: Limits.hardMaximumWorkUnits + 1),
                .workUnits,
                Limits.hardMaximumWorkUnits + 1
            ),
            (makeLimits(cancellationCheckInterval: 0), .cancellationCheckInterval, 0),
            (
                makeLimits(
                    cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval + 1
                ),
                .cancellationCheckInterval,
                Limits.hardMaximumCancellationCheckInterval + 1
            )
        ]

        for (limits, limit, value) in invalid {
            assertWorkflowError(.invalidLimit(limit, value: value)) {
                try limits.validate()
            }
        }
    }

    func testCanonicalPersistenceHasExactSortedBytesAndRevisionIsOutOfBand() throws {
        let custom = try configuration(
            visibility: .hidden,
            size: .huge,
            items: [.command(.save), .separator, .command(.openComparison)]
        )
        let revision = Workflow.ConfigurationRevision(rawValue: 41)
        let snapshot = try makeSnapshot(configuration: custom, revision: revision)
        let persistence = try snapshot.canonicalPersistence()
        let expected = data(
            #"{"items":["save","separator","openComparison"],"schemaVersion":1,"size":"huge","visibility":"hidden"}"#
        )

        XCTAssertEqual(persistence.reference, snapshot.reference)
        XCTAssertEqual(persistence.data, expected)
        XCTAssertEqual(persistence.data, try custom.encodedData())

        let restoredIdentity = Workflow.ConfigurationIdentity(
            rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        )
        let restoredRevision = Workflow.ConfigurationRevision(rawValue: 900)
        let restored = try Workflow.restoreSnapshot(
            from: expected,
            identity: restoredIdentity,
            revision: restoredRevision
        )
        XCTAssertEqual(restored.configuration, custom)
        XCTAssertEqual(restored.identity, restoredIdentity)
        XCTAssertEqual(restored.revision, restoredRevision)
        XCTAssertEqual(try restored.canonicalPersistence().data, expected)
        XCTAssertNotEqual(restored.reference, snapshot.reference)
    }

    func testCanonicalPersistenceByteLimitAcceptsExactAndRejectsOneLess() throws {
        let custom = try configuration(
            visibility: .hidden,
            size: .medium,
            items: [.command(.save), .separator]
        )
        let bytes = try custom.encodedData()
        let exactLimits = makeLimits(maximumPersistenceBytes: bytes.count)
        let exact = try makeSnapshot(configuration: custom, limits: exactLimits)

        XCTAssertEqual(try exact.canonicalPersistence().data.count, bytes.count)
        XCTAssertEqual(
            try Workflow.restoreSnapshot(
                from: bytes,
                identity: fixedIdentity,
                limits: exactLimits
            ).configuration,
            custom
        )
        assertWorkflowError(.persistenceTooLarge(maximumBytes: bytes.count - 1)) {
            try self.makeSnapshot(
                configuration: custom,
                limits: self.makeLimits(maximumPersistenceBytes: bytes.count - 1)
            )
        }
        assertWorkflowError(.persistenceTooLarge(maximumBytes: bytes.count - 1)) {
            try Workflow.restoreSnapshot(
                from: bytes,
                limits: self.makeLimits(maximumPersistenceBytes: bytes.count - 1)
            )
        }
    }

    func testRestoreRejectsNoncanonicalMalformedAndOversizedPersistence() throws {
        let canonical = try ToolbarConfiguration.winMergeDefault.encodedData()
        var noncanonical = canonical
        noncanonical.append(0x0A)

        assertWorkflowError(.nonCanonicalPersistence) {
            try Workflow.restoreSnapshot(from: noncanonical)
        }
        assertWorkflowError(.malformedPersistence) {
            try Workflow.restoreSnapshot(from: self.data(#"{"items":[]}"#))
        }
        assertWorkflowError(
            .persistenceTooLarge(maximumBytes: Limits.hardMaximumPersistenceBytes)
        ) {
            try Workflow.restoreSnapshot(
                from: Data(repeating: 0x20, count: Limits.hardMaximumPersistenceBytes + 1)
            )
        }
    }

    func testCASRequiresExactIdentityRevisionConfigurationPolicyAndLimits() throws {
        let configuration = try configuration(items: [.command(.save)])
        let policy = Policy(requiredCommands: [.save])
        let limits = makeLimits(cancellationCheckInterval: 17)
        let snapshot = try makeSnapshot(configuration: configuration, policy: policy, limits: limits)
        let cas = snapshot.cas
        let equivalent = try makeSnapshot(
            configuration: configuration,
            policy: policy,
            limits: limits
        )

        XCTAssertTrue(try cas.matches(equivalent))
        XCTAssertNoThrow(try cas.validate(equivalent))

        let changedConfiguration = try makeSnapshot(
            configuration: self.configuration(
                visibility: .hidden,
                items: [.command(.save)]
            ),
            policy: policy,
            limits: limits
        )
        let changedPolicy = try makeSnapshot(
            configuration: configuration,
            policy: .permissive,
            limits: limits
        )
        let changedLimits = try makeSnapshot(
            configuration: configuration,
            policy: policy,
            limits: makeLimits(cancellationCheckInterval: 18)
        )
        for changed in [changedConfiguration, changedPolicy, changedLimits] {
            XCTAssertFalse(try cas.matches(changed))
            assertWorkflowError(.configurationChangedWithoutRevision(snapshot.reference)) {
                try cas.validate(changed)
            }
        }

        let changedRevision = try makeSnapshot(
            configuration: configuration,
            policy: policy,
            limits: limits,
            revision: Workflow.ConfigurationRevision(rawValue: snapshot.revision.rawValue + 1)
        )
        assertStale(cas, expected: snapshot.reference, actual: changedRevision.reference, against: changedRevision)

        let changedIdentity = try Snapshot(
            identity: Workflow.ConfigurationIdentity(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            ),
            revision: snapshot.revision,
            configuration: configuration,
            policy: policy,
            limits: limits
        )
        assertStale(cas, expected: snapshot.reference, actual: changedIdentity.reference, against: changedIdentity)
    }

    func testApplyPlanAdvancesRevisionExactlyOnceWhileNoOpDoesNot() throws {
        let snapshot = try makeSnapshot(
            configuration: configuration(items: [.command(.save)]),
            revision: Workflow.ConfigurationRevision(rawValue: 12)
        )
        let changed = try makePlan([.setSize(.medium)], in: snapshot)
        let unchanged = try makePlan([.setSize(.small)], in: snapshot)

        XCTAssertEqual(changed.receipt.disposition, .replacementPlanned)
        XCTAssertEqual(changed.successor?.revision.rawValue, 13)
        XCTAssertEqual(changed.canonicalPersistence?.reference, changed.successor?.reference)
        XCTAssertEqual(changed.receipt.persistenceByteCount, changed.canonicalPersistence?.data.count)
        XCTAssertEqual(changed.receipt.resultingConfiguration, changed.successor?.reference)

        XCTAssertEqual(unchanged.receipt.disposition, .unchanged)
        XCTAssertEqual(unchanged.receipt.resultingConfiguration, snapshot.reference)
        XCTAssertNil(unchanged.successor)
        XCTAssertNil(unchanged.canonicalPersistence)
        XCTAssertNil(unchanged.receipt.persistenceByteCount)
    }

    func testBeginApplyCancelAndUnchangedTransactionsHaveExactStoreSemantics() async throws {
        let initial = try configuration(items: [.command(.save)])
        let store = try Store(identity: fixedIdentity, revision: .init(rawValue: 20), configuration: initial)
        let begun = await store.snapshot()
        let apply = Transaction(snapshot: begun, edits: [.setSize(.big)])

        XCTAssertEqual(apply.expectedConfiguration.reference, begun.reference)
        XCTAssertEqual(apply.edits, [.setSize(.big)])

        let applied = try await store.finish(apply, decision: .apply)
        let afterApply = await store.snapshot()
        XCTAssertEqual(applied.disposition, .applied)
        XCTAssertEqual(afterApply.configuration.size, .big)
        XCTAssertEqual(afterApply.revision.rawValue, 21)

        let cancel = Transaction(snapshot: afterApply, edits: [.setSize(.huge)])
        let cancelled = try await store.finish(cancel, decision: .cancel)
        XCTAssertEqual(cancelled.disposition, .cancelled)
        XCTAssertEqual(cancelled.receipt.finalConfiguration, afterApply.reference)
        XCTAssertNil(cancelled.receipt.canonicalPersistence)
        let afterCancel = await store.snapshot()
        XCTAssertEqual(afterCancel, afterApply)

        let unchanged = try await store.finish(
            Transaction(snapshot: afterApply, edits: [.setSize(.big)]),
            decision: .apply
        )
        XCTAssertEqual(unchanged.disposition, .unchanged)
        XCTAssertEqual(unchanged.receipt.finalConfiguration, afterApply.reference)
        XCTAssertNil(unchanged.receipt.canonicalPersistence)
        let afterUnchanged = await store.snapshot()
        XCTAssertEqual(afterUnchanged, afterApply)
    }

    func testCancelPlanNeverAuthorizesRollbackAfterAnotherPlanCommits() async throws {
        let store = try Store(
            identity: fixedIdentity,
            configuration: configuration(items: [.command(.save)])
        )
        let initial = await store.snapshot()
        let cancelPlan = try Workflow.plan(
            Transaction(snapshot: initial, edits: [.setSize(.huge)]),
            decision: .cancel,
            in: initial
        )
        let applyPlan = try makePlan([.setSize(.medium)], in: initial)

        let applied = try await store.commit(applyPlan)
        let afterApply = await store.snapshot()
        let cancelled = try await store.commit(cancelPlan)

        XCTAssertEqual(applied.disposition, .applied)
        XCTAssertEqual(cancelPlan.receipt.disposition, .cancelled)
        XCTAssertNil(cancelPlan.successor)
        XCTAssertEqual(cancelled.disposition, .cancelled)
        XCTAssertEqual(cancelled.receipt.finalConfiguration, afterApply.reference)
        let final = await store.snapshot()
        XCTAssertEqual(final, afterApply)
    }

    func testConcurrentPlansAgainstOneSnapshotAllowExactlyOneWinner() async throws {
        let store = try Store(
            identity: fixedIdentity,
            configuration: configuration(items: [.command(.save)])
        )
        let initial = await store.snapshot()
        let sizePlan = try makePlan([.setSize(.medium)], in: initial)
        let visibilityPlan = try makePlan([.setVisibility(.hidden)], in: initial)

        let attempts = await withTaskGroup(of: CommitAttempt.self, returning: [CommitAttempt].self) {
            group in
            group.addTask { await commitAttempt(sizePlan, to: store) }
            group.addTask { await commitAttempt(visibilityPlan, to: store) }
            var values: [CommitAttempt] = []
            for await value in group { values.append(value) }
            return values
        }
        let final = await store.snapshot()

        XCTAssertEqual(attempts.filter { $0 == .applied }.count, 1)
        XCTAssertEqual(attempts.filter { $0 == .stale }.count, 1)
        XCTAssertEqual(final.revision.rawValue, initial.revision.rawValue + 1)
        XCTAssertTrue(
            (final.configuration.size == .medium && final.configuration.visibility == .visible)
                || (final.configuration.size == .small
                    && final.configuration.visibility == .hidden)
        )
    }

    func testPlanningReceiptIsNotProofOfMutationButAppliedReceiptIs() async throws {
        let initialConfiguration = try configuration(items: [.command(.save)])
        let store = try Store(identity: fixedIdentity, configuration: initialConfiguration)
        let initial = await store.snapshot()
        let plan = try makePlan([.setSize(.huge)], in: initial)

        XCTAssertEqual(plan.receipt.disposition, .replacementPlanned)
        let beforeCommit = await store.snapshot()
        XCTAssertEqual(beforeCommit, initial)
        XCTAssertNotEqual(plan.successor?.reference, initial.reference)

        let outcome = try await store.commit(plan)
        let final = await store.snapshot()
        let persisted = await store.canonicalPersistence()

        XCTAssertEqual(outcome.disposition, .applied)
        XCTAssertEqual(outcome.receipt.planningReceipt, plan.receipt)
        XCTAssertEqual(outcome.receipt.finalConfiguration, final.reference)
        XCTAssertEqual(outcome.receipt.canonicalPersistence, plan.canonicalPersistence)
        XCTAssertEqual(outcome.receipt.canonicalPersistence, persisted)
        XCTAssertEqual(final, plan.successor)
        XCTAssertEqual(final.configuration.size, .huge)
    }

    func testActorCommitPointCancellationRaceIsDeterministicAndAtomic() async throws {
        let initialConfiguration = try configuration(items: [.command(.save)])
        let baselineStore = try Store(identity: fixedIdentity, configuration: initialConfiguration)
        let baselineSnapshot = await baselineStore.snapshot()
        let baselinePlan = try makePlan([.setSize(.medium)], in: baselineSnapshot)
        let baselineProbe = CancellationProbe()

        let baselineOutcome = try await baselineStore.commit(
            baselinePlan,
            cancellationCheck: { baselineProbe.check() }
        )
        XCTAssertEqual(baselineOutcome.disposition, .applied)
        XCTAssertEqual(baselineProbe.count, 4)

        let cancelledStore = try Store(identity: fixedIdentity, configuration: initialConfiguration)
        let cancelledSnapshot = await cancelledStore.snapshot()
        let cancelledPlan = try makePlan([.setSize(.medium)], in: cancelledSnapshot)
        let commitPointCancellation = CancellationProbe(cancelOnCheck: baselineProbe.count)
        do {
            _ = try await cancelledStore.commit(
                cancelledPlan,
                cancellationCheck: { commitPointCancellation.check() }
            )
            XCTFail("Expected commit-point cancellation")
        } catch {
            XCTAssertEqual(error as? WorkflowError, .cancelled)
        }
        XCTAssertEqual(commitPointCancellation.count, baselineProbe.count)
        let afterCancellation = await cancelledStore.snapshot()
        let persistenceAfterCancellation = await cancelledStore.canonicalPersistence()
        XCTAssertEqual(afterCancellation, cancelledSnapshot)
        XCTAssertEqual(persistenceAfterCancellation.data, try initialConfiguration.encodedData())

        let postCheckStore = try Store(identity: fixedIdentity, configuration: initialConfiguration)
        let postCheckSnapshot = await postCheckStore.snapshot()
        let postCheckPlan = try makePlan([.setSize(.medium)], in: postCheckSnapshot)
        let cancellationAfterSample = CancellationProbe(
            markCancelledAfterSuccessfulCheck: baselineProbe.count
        )
        let applied = try await postCheckStore.commit(
            postCheckPlan,
            cancellationCheck: { cancellationAfterSample.check() }
        )

        XCTAssertEqual(applied.disposition, .applied)
        XCTAssertEqual(cancellationAfterSample.count, baselineProbe.count)
        XCTAssertTrue(cancellationAfterSample.isCancellationMarked)
        let postCheckFinal = await postCheckStore.snapshot()
        XCTAssertEqual(postCheckFinal, postCheckPlan.successor)
    }

    func testOverflowPreviewPreservesExactFullSplitHiddenPartitionsAndCAS() throws {
        let items: [Item] = [.command(.save), .separator, .command(.undo)]
        let metrics = try ToolbarConfiguration.LayoutMetrics(
            commandWidths: [.save: 10, .undo: 10],
            separatorWidth: 2,
            overflowButtonWidth: 5
        )
        let visibleSnapshot = try makeSnapshot(configuration: configuration(items: items))

        let full = try Workflow.previewOverflow(
            in: visibleSnapshot,
            availableWidth: 22,
            metrics: metrics
        )
        XCTAssertEqual(full.visibleItems, items)
        XCTAssertEqual(full.overflowItems, [])
        XCTAssertFalse(full.showsOverflowControl)
        XCTAssertEqual(full.layout.occupiedWidth, 22)

        let split = try Workflow.previewOverflow(
            in: visibleSnapshot,
            availableWidth: 17,
            metrics: metrics
        )
        XCTAssertEqual(split.visibleItems, [.command(.save)])
        XCTAssertEqual(split.overflowItems, [.separator, .command(.undo)])
        XCTAssertTrue(split.showsOverflowControl)
        XCTAssertEqual(split.layout.occupiedWidth, 15)
        XCTAssertEqual(split.layout.representedItems, items)
        XCTAssertTrue(try split.expectedConfiguration.matches(visibleSnapshot))

        let hiddenSnapshot = try makeSnapshot(
            configuration: configuration(visibility: .hidden, items: items)
        )
        let hidden = try Workflow.previewOverflow(
            in: hiddenSnapshot,
            availableWidth: 0,
            metrics: metrics
        )
        XCTAssertEqual(hidden.visibleItems, [])
        XCTAssertEqual(hidden.overflowItems, items)
        XCTAssertFalse(hidden.showsOverflowControl)
        XCTAssertFalse(hidden.layout.isToolbarVisible)
        XCTAssertEqual(hidden.layout.occupiedWidth, 0)
    }

    func testOverflowPreviewReportsExactWorkAndMapsInvalidWidth() throws {
        let snapshot = try makeSnapshot(
            configuration: configuration(
                items: [.command(.save), .separator, .command(.undo)]
            )
        )
        let metrics = try ToolbarConfiguration.LayoutMetrics(
            commandWidths: [.save: 10, .undo: 10]
        )
        let preview = try Workflow.previewOverflow(
            in: snapshot,
            availableWidth: 100,
            metrics: metrics
        )

        XCTAssertEqual(preview.workPerformed, 5)
        for width in [-1.0, .infinity, -.infinity, .nan] {
            assertWorkflowError(.overflowPreview(.invalidAvailableWidth)) {
                try Workflow.previewOverflow(in: snapshot, availableWidth: width)
            }
        }
    }

    func testPlanningWorkLimitAcceptsExactReceiptAndRejectsOneUnitLess() throws {
        let initial = try configuration(items: [.command(.save)])
        let baselineLimits = makeLimits(
            maximumWorkUnits: Limits.hardMaximumWorkUnits,
            cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval
        )
        let baselineSnapshot = try makeSnapshot(configuration: initial, limits: baselineLimits)
        let baseline = try makePlan([.setSize(.medium)], in: baselineSnapshot)
        let exactWork = baseline.receipt.workPerformed

        let exactSnapshot = try makeSnapshot(
            configuration: initial,
            limits: makeLimits(
                maximumWorkUnits: exactWork,
                cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval
            )
        )
        let exact = try makePlan([.setSize(.medium)], in: exactSnapshot)
        XCTAssertEqual(exact.receipt.workPerformed, exactWork)

        let oneLessSnapshot = try makeSnapshot(
            configuration: initial,
            limits: makeLimits(
                maximumWorkUnits: exactWork - 1,
                cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval
            )
        )
        assertWorkflowError(.workLimitExceeded(maximum: exactWork - 1)) {
            try self.makePlan([.setSize(.medium)], in: oneLessSnapshot)
        }
    }

    func testCancellationChecksExactEntryGroupedIntervalsPrechargeAndFinishCadence() throws {
        let initial = try configuration(items: [.command(.save)])
        let intervalOneSnapshot = try makeSnapshot(
            configuration: initial,
            limits: makeLimits(cancellationCheckInterval: 1)
        )
        let intervalOneProbe = CancellationProbe()
        let intervalOne = try makePlan(
            [.setSize(.medium)],
            in: intervalOneSnapshot,
            cancellationCheck: { intervalOneProbe.check() }
        )
        XCTAssertEqual(intervalOneProbe.count, 8)

        let sparseSnapshot = try makeSnapshot(
            configuration: initial,
            limits: makeLimits(
                cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval
            )
        )
        let sparseProbe = CancellationProbe()
        let sparse = try makePlan(
            [.setSize(.medium)],
            in: sparseSnapshot,
            cancellationCheck: { sparseProbe.check() }
        )
        XCTAssertEqual(sparseProbe.count, 3)
        XCTAssertEqual(intervalOne.receipt.workPerformed, sparse.receipt.workPerformed)

        for check in [1, 2, intervalOneProbe.count] {
            let cancellingProbe = CancellationProbe(cancelOnCheck: check)
            assertWorkflowError(.cancelled) {
                try self.makePlan(
                    [.setSize(.medium)],
                    in: intervalOneSnapshot,
                    cancellationCheck: { cancellingProbe.check() }
                )
            }
            XCTAssertEqual(cancellingProbe.count, check)
        }
    }

    func testRevisionExhaustionRejectsChangeButAllowsNoOpAndCancel() throws {
        let snapshot = try makeSnapshot(
            configuration: configuration(items: [.command(.save)]),
            revision: Workflow.ConfigurationRevision(rawValue: .max)
        )

        assertWorkflowError(.revisionExhausted) {
            try self.makePlan([.setSize(.medium)], in: snapshot)
        }
        XCTAssertEqual(
            try makePlan([.setSize(.small)], in: snapshot).receipt.disposition,
            .unchanged
        )
        XCTAssertEqual(
            try makePlan([.setSize(.medium)], in: snapshot, decision: .cancel).receipt
                .disposition,
            .cancelled
        )
    }

    func testPlansPersistencePreviewsAndCapabilityBindingsAreDeterministic() throws {
        let configuration = try configuration(
            items: [.command(.save), .separator, .command(.undo)]
        )
        let policy = Policy(requiredCommands: [.save])
        let snapshot = try makeSnapshot(configuration: configuration, policy: policy)
        let transaction = Transaction(
            snapshot: snapshot,
            edits: [.setSize(.big), .moveItem(from: 0, to: 3)]
        )
        let context = ComparisonCommandState.Context(canUndo: true)

        let firstPlan = try Workflow.plan(transaction, decision: .apply, in: snapshot)
        let secondPlan = try Workflow.plan(transaction, decision: .apply, in: snapshot)
        XCTAssertEqual(firstPlan, secondPlan)
        XCTAssertEqual(
            try snapshot.canonicalPersistence(),
            try snapshot.canonicalPersistence()
        )
        XCTAssertEqual(
            try Workflow.previewOverflow(in: snapshot, availableWidth: 80),
            try Workflow.previewOverflow(in: snapshot, availableWidth: 80)
        )

        let firstBindings = try Workflow.bindCommandCapabilities(in: snapshot, context: context)
        let secondBindings = try Workflow.bindCommandCapabilities(in: snapshot, context: context)
        XCTAssertEqual(firstBindings, secondBindings)
        XCTAssertEqual(firstBindings.bindings.map(\.command), Command.allCases)
        XCTAssertEqual(firstBindings.binding(for: .save)?.configuredItemIndex, 0)
        XCTAssertEqual(firstBindings.binding(for: .save)?.isRequired, true)
        XCTAssertEqual(firstBindings.binding(for: .undo)?.configuredItemIndex, 2)
        XCTAssertEqual(firstBindings.binding(for: .undo)?.canExecuteSemantically, true)
        XCTAssertNil(firstBindings.binding(for: .redo)?.configuredItemIndex)
    }

    func testDescriptionsDebugDescriptionsAndMirrorsRedactPayloadValues() async throws {
        let initial = try configuration(items: [.command(.openComparison)])
        let snapshot = try makeSnapshot(
            configuration: initial,
            revision: Workflow.ConfigurationRevision(rawValue: 7)
        )
        let edit = Edit.addCommand(.save, at: 1)
        let transaction = Transaction(snapshot: snapshot, edits: [edit])
        let plan = try Workflow.plan(transaction, decision: .apply, in: snapshot)
        let successor = try XCTUnwrap(plan.successor)
        let persistence = try XCTUnwrap(plan.canonicalPersistence)
        guard case .replace(let replacement) = plan.operation else {
            return XCTFail("Expected replacement")
        }
        let preview = try Workflow.previewOverflow(in: snapshot, availableWidth: 0)
        let bindings = try Workflow.bindCommandCapabilities(
            in: snapshot,
            context: ComparisonCommandState.Context()
        )
        let binding = try XCTUnwrap(bindings.binding(for: .openComparison))
        let store = try Store(
            identity: snapshot.identity,
            revision: snapshot.revision,
            configuration: initial
        )
        let outcome = try await store.commit(plan)
        let receipt = outcome.receipt

        let values: [(Any, String)] = [
            (snapshot, "configuration"),
            (snapshot.cas, "contents"),
            (edit, "details"),
            (transaction, "edits"),
            (plan.receipt.edits[0], "details"),
            (plan.receipt, "details"),
            (persistence, "data"),
            (replacement, "configuration"),
            (plan, "operation"),
            (receipt, "details"),
            (outcome, "details"),
            (preview, "items"),
            (binding, "semanticState"),
            (bindings, "semanticState")
        ]
        for (value, mirrorLabel) in values {
            let description = String(describing: value)
            XCTAssertTrue(description.contains("<redacted>"), description)
            XCTAssertEqual(String(reflecting: value), description)
            XCTAssertEqual(mirrorValue(value, label: mirrorLabel) as? String, "<redacted>")
            XCTAssertFalse(description.contains(#"{"items""#), description)
        }

        XCTAssertEqual(
            snapshot.description,
            "ToolbarCustomizationWorkflow.Snapshot(revision: 7, items: 1, configuration: <redacted>)"
        )
        XCTAssertEqual(successor.revision.rawValue, 8)
        XCTAssertEqual(
            persistence.description,
            "ToolbarCustomizationWorkflow.CanonicalPersistence(revision: 8, bytes: \(persistence.data.count), data: <redacted>)"
        )
        XCTAssertEqual(receipt.disposition, .applied)
    }

    func testCapabilitiesAndExecutorContractStateExactPublicScopeWithoutUIOverclaim() throws {
        XCTAssertEqual(Workflow.capabilities, Workflow.Capability.allCases)
        XCTAssertEqual(
            Workflow.capabilities,
            [
                .editAuthoritativeConfiguration,
                .previewAuthoritativeOverflow,
                .bindSemanticCommandState,
                .canonicalConfigurationPersistence,
                .exactConfigurationCompareAndSwap
            ]
        )
        XCTAssertEqual(
            Workflow.capabilityScopeStatement,
            "UI-independent configuration and semantic command-state planning only; no native toolbar customization UI is created or verified."
        )
        XCTAssertEqual(
            Workflow.CommandCapabilityPlan.scopeStatement,
            Workflow.capabilityScopeStatement
        )

        let snapshot = try makeSnapshot(configuration: configuration(items: [.command(.save)]))
        let plan = try makePlan([.setSize(.medium)], in: snapshot)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(
            plan.executorContract.cas,
            .compareExactIdentityRevisionConfigurationPolicyAndLimits
        )
        XCTAssertEqual(
            plan.executorContract.replacement,
            .replaceSuccessorAndCanonicalBytesAtomicallyOnce
        )
        XCTAssertEqual(
            plan.executorContract.cancellation,
            .successfulCancellationCheckImmediatelyBeforeReplacementIsCommitPoint
        )
        XCTAssertEqual(
            plan.executorContract.ui,
            .noNativeToolbarCustomizationUIIsCreatedOrVerified
        )
    }

    private var fixedIdentity: Workflow.ConfigurationIdentity {
        Workflow.ConfigurationIdentity(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
    }

    private func configuration(
        visibility: ToolbarConfiguration.Visibility = .visible,
        size: ToolbarConfiguration.Size = .small,
        items: [Item]
    ) throws -> ToolbarConfiguration {
        try ToolbarConfiguration(visibility: visibility, size: size, items: items)
    }

    private func makeSnapshot(
        configuration: ToolbarConfiguration = .winMergeDefault,
        policy: Policy = .permissive,
        limits: Limits = .default,
        revision: Workflow.ConfigurationRevision = .init(rawValue: 0)
    ) throws -> Snapshot {
        try Snapshot(
            identity: fixedIdentity,
            revision: revision,
            configuration: configuration,
            policy: policy,
            limits: limits
        )
    }

    private func makePlan(
        _ edits: [Edit],
        in snapshot: Snapshot,
        decision: Workflow.Decision = .apply,
        cancellationCheck: @escaping Workflow.CancellationCheck = { false }
    ) throws -> Workflow.Plan {
        try Workflow.plan(
            Transaction(snapshot: snapshot, edits: edits),
            decision: decision,
            in: snapshot,
            cancellationCheck: cancellationCheck
        )
    }

    private func makeLimits(
        maximumItemCount: Int = Limits.default.maximumItemCount,
        maximumRequiredCommandCount: Int = Limits.default.maximumRequiredCommandCount,
        maximumTransactionEditCount: Int = Limits.default.maximumTransactionEditCount,
        maximumPersistenceBytes: Int = Limits.default.maximumPersistenceBytes,
        maximumWorkUnits: Int = Limits.default.maximumWorkUnits,
        cancellationCheckInterval: Int = Limits.default.cancellationCheckInterval
    ) -> Limits {
        Limits(
            maximumItemCount: maximumItemCount,
            maximumRequiredCommandCount: maximumRequiredCommandCount,
            maximumTransactionEditCount: maximumTransactionEditCount,
            maximumPersistenceBytes: maximumPersistenceBytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func assertStale(
        _ cas: CAS,
        expected: Workflow.ConfigurationReference,
        actual: Workflow.ConfigurationReference,
        against snapshot: Snapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertWorkflowError(
            .staleConfiguration(expected: expected, actual: actual),
            file: file,
            line: line
        ) {
            try cas.validate(snapshot)
        }
        XCTAssertFalse(try cas.matches(snapshot), file: file, line: line)
    }

    private func assertWorkflowError<T>(
        _ expected: WorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? WorkflowError, expected, file: file, line: line)
        }
    }

    private func mirrorValue(_ value: Any, label: String) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == label }?.value
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}

private enum CommitAttempt: Equatable, Sendable {
    case applied
    case stale
    case unexpected
}

private func commitAttempt(
    _ plan: ToolbarCustomizationWorkflow.Plan,
    to store: ToolbarCustomizationWorkflow.Store
) async -> CommitAttempt {
    do {
        let outcome = try await store.commit(plan)
        return outcome.disposition == .applied ? .applied : .unexpected
    } catch ToolbarCustomizationWorkflowError.staleConfiguration {
        return .stale
    } catch {
        return .unexpected
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelOnCheck: Int?
    private let markCancelledAfterSuccessfulCheck: Int?
    private var storedCount = 0
    private var cancellationMarked = false

    init(
        cancelOnCheck: Int? = nil,
        markCancelledAfterSuccessfulCheck: Int? = nil
    ) {
        self.cancelOnCheck = cancelOnCheck
        self.markCancelledAfterSuccessfulCheck = markCancelledAfterSuccessfulCheck
    }

    var count: Int {
        lock.withLock { storedCount }
    }

    var isCancellationMarked: Bool {
        lock.withLock { cancellationMarked }
    }

    func check() -> Bool {
        lock.withLock {
            storedCount += 1
            if storedCount == cancelOnCheck { return true }
            let wasCancelled = cancellationMarked
            if storedCount == markCancelledAfterSuccessfulCheck {
                cancellationMarked = true
            }
            return wasCancelled
        }
    }
}
