import MacMergeCore
import XCTest

final class SelectedFilePairOpenWorkflowTests: XCTestCase {
    private typealias Workflow = SelectedFilePairOpenWorkflow

    func testSelectedRegularFilePairsUseVisibleOrderForOneAndManyRows() throws {
        let one = try makeFixture(
            specs: [RowSpec("only.txt", status: .identical)],
            selectedIndices: [0]
        )
        let onePlan = try plan(one)

        XCTAssertEqual(onePlan.actions.count, 1)
        assertAction(onePlan.actions[0], index: 0, visibleOrdinal: 0, spec: one.specs[0])

        let many = try makeFixture(
            specs: [
                RowSpec("z-last.txt"),
                RowSpec("a-first.txt", status: .identical),
                RowSpec("m-middle.txt")
            ],
            selectedIndices: [0, 1, 2]
        )
        let selectedInCallerOrder = [many.itemIdentities[0], many.itemIdentities[2], many.itemIdentities[1]]
        let manyPlan = try plan(many, selectedItemIdentities: selectedInCallerOrder)

        XCTAssertEqual(manyPlan.actions.map(\.index), [0, 1, 2])
        XCTAssertEqual(manyPlan.actions.map(\.visibleOrdinal), [0, 1, 2])
        XCTAssertEqual(
            manyPlan.actions.map(\.itemIdentity),
            [many.itemIdentities[1], many.itemIdentities[2], many.itemIdentities[0]]
        )
        XCTAssertEqual(manyPlan.actions.map(\.left.relativePath), ["a-first.txt", "m-middle.txt", "z-last.txt"])
        XCTAssertEqual(manyPlan.actions.map(\.right.relativePath), ["a-first.txt", "m-middle.txt", "z-last.txt"])
    }

    func testActionsDeclareOnlyReadOnlyTextComparisonAndExactBoundSources() throws {
        let fixture = try makeFixture(
            specs: [RowSpec(left: "old/name.txt", right: "new/name.txt")],
            selectedIndices: [0]
        )
        let action = try XCTUnwrap(plan(fixture).actions.first)

        XCTAssertEqual(action.intent, .readOnlyTextComparison)
        XCTAssertEqual(action.comparisonMode, .text)
        XCTAssertTrue(action.left.readOnly)
        XCTAssertTrue(action.right.readOnly)
        XCTAssertEqual(action.left.side, .left)
        XCTAssertEqual(action.right.side, .right)
        XCTAssertEqual(action.left.root, fixture.roots.left)
        XCTAssertEqual(action.right.root, fixture.roots.right)
        XCTAssertEqual(action.left.revision, fixture.rows[0].revision.left)
        XCTAssertEqual(action.right.revision, fixture.rows[0].revision.right)
        XCTAssertEqual(action.left.authority, fixture.authorityBindings[0])
        XCTAssertEqual(action.right.authority, fixture.authorityBindings[1])
        XCTAssertEqual(action.left.navigationAuthority, fixture.navigationAuthorities[0])
        XCTAssertEqual(action.right.navigationAuthority, fixture.navigationAuthorities[1])
    }

    func testIdenticalAndDifferentRegularPairsAreEligibleButOtherRowsAreNot() throws {
        for status in [DirectoryComparisonStatus.identical, .different] {
            let fixture = try makeFixture(
                specs: [RowSpec("eligible-\(status.rawValue).txt", status: status)],
                selectedIndices: [0]
            )
            XCTAssertNoThrow(try plan(fixture))
        }

        for spec in [
            RowSpec("directory", status: .identical, kind: .directory),
            RowSpec("skipped.txt", status: .skipped)
        ] {
            let fixture = try makeFixture(specs: [spec], selectedIndices: [0])
            assertError(.selectedItemIneligible, itemIdentity: fixture.itemIdentities[0]) {
                try plan(fixture)
            }
        }

        let noOpenCapability = try makeFixture(
            specs: [RowSpec("unsupported.txt")],
            selectedIndices: [0],
            openCapabilities: []
        )
        assertError(.selectedItemIneligible, itemIdentity: noOpenCapability.itemIdentities[0]) {
            try plan(noOpenCapability)
        }
    }

    func testRootEscapesLinksAndTypeMismatchesCannotProduceActions() throws {
        let valid = try makeFixture(specs: [RowSpec("valid.txt")], selectedIndices: [0])
        for path in ["/absolute.txt", "folder/../escape.txt", "nul\0escape.txt"] {
            let malformedRow = makeRow(RowSpec(path), roots: valid.roots, index: 0)
            let malformedSnapshot = folderSnapshot(roots: valid.roots, rows: [malformedRow])
            assertError(.invalidFolderSnapshot) {
                try plan(valid, folderSnapshot: malformedSnapshot)
            }
        }

        let symbolicLink = try makeFixture(
            specs: [RowSpec("link", kind: .symbolicLink)],
            selectedIndices: [0]
        )
        assertError(.selectedItemIneligible, itemIdentity: symbolicLink.itemIdentities[0]) {
            try plan(symbolicLink)
        }

        let typeMismatch = try makeFixture(
            specs: [
                RowSpec(
                    left: "mismatch",
                    right: "mismatch",
                    status: .typeMismatch,
                    leftKind: .file,
                    rightKind: .directory
                )
            ],
            selectedIndices: [0]
        )
        assertError(.selectedItemIneligible, itemIdentity: typeMismatch.itemIdentities[0]) {
            try plan(typeMismatch)
        }
    }

    func testSelectionMustExactlyMatchVisibleNavigationSelection() throws {
        let fixture = try makeFixture(
            specs: [RowSpec("a.txt"), RowSpec("b.txt")],
            selectedIndices: [0]
        )
        assertError(.selectionMismatch) {
            try plan(fixture, selectedItemIdentities: [fixture.itemIdentities[1]])
        }

        let filtered = try makeFixture(
            specs: [RowSpec("visible.txt"), RowSpec("filtered.txt", status: .identical)],
            selectedIndices: [1],
            filter: DirectoryResultFilter(statuses: [.different])
        )
        assertError(.selectedItemNotVisible, itemIdentity: filtered.itemIdentities[1]) {
            try plan(filtered)
        }
    }

    func testExactResultIDComparisonRejectsHashableAliasCrossBinding() throws {
        let folderFixture = try makeFixture(
            specs: [RowSpec("alias.txt")],
            selectedIndices: [0]
        )
        let oneSided = DirectoryResult(
            left: metadata(path: "alias.txt", byteCount: 4),
            right: nil,
            status: .leftOnly
        )
        XCTAssertEqual(oneSided.id, folderFixture.rows[0].result.id)
        let navigation = try navigationSnapshot(
            rows: [oneSided],
            selectedIndices: [0],
            roots: folderFixture.roots,
            itemIdentities: folderFixture.itemIdentities,
            authorities: folderFixture.navigationAuthorities,
            openCapabilities: [.missingRightRegularFile]
        )
        let expectedNavigation = try Workflow.Planner.navigationReference(to: navigation)

        assertError(.invalidResultBinding, itemIdentity: folderFixture.itemIdentities[0]) {
            try plan(
                folderFixture,
                navigationSnapshot: navigation,
                expectedNavigationSnapshot: expectedNavigation
            )
        }
    }

    func testExactNavigationPayloadCrossBindingIsRejected() throws {
        let fixture = try makeFixture(specs: [RowSpec("payload.txt")], selectedIndices: [0])
        let changedResult = DirectoryResult(
            left: metadata(path: "payload.txt", byteCount: 40),
            right: metadata(path: "payload.txt", byteCount: 50),
            status: .different
        )
        let changedNavigation = try navigationSnapshot(
            rows: [changedResult],
            selectedIndices: [0],
            roots: fixture.roots,
            itemIdentities: fixture.itemIdentities,
            authorities: fixture.navigationAuthorities
        )
        let expectedNavigation = try Workflow.Planner.navigationReference(to: changedNavigation)

        assertError(.invalidResultBinding, itemIdentity: fixture.itemIdentities[0]) {
            try plan(
                fixture,
                navigationSnapshot: changedNavigation,
                expectedNavigationSnapshot: expectedNavigation
            )
        }
    }

    func testAuthorityBindingsRequireExactlyOneDistinctAuthorityPerSide() throws {
        let fixture = try makeFixture(specs: [RowSpec("authority.txt")], selectedIndices: [0])
        XCTAssertEqual(try plan(fixture).authorityBindings.map(\.side), [.left, .right])

        assertError(.invalidAuthorityBinding) {
            try plan(fixture, authorityBindings: [fixture.authorityBindings[0]])
        }
        assertError(.duplicateAuthorityBinding, side: .left) {
            try plan(
                fixture,
                authorityBindings: [fixture.authorityBindings[0], fixture.authorityBindings[0]]
            )
        }

        let duplicateNavigationIdentity = Workflow.AuthorityBinding(
            side: .right,
            folderAuthorityIdentity: fixture.roots.right.authority.identity,
            folderAuthorityRevision: fixture.roots.right.authority.revision,
            navigationAuthorityIdentity: fixture.navigationAuthorities[0].identity
        )
        assertError(.duplicateAuthorityBinding, side: .right) {
            try plan(
                fixture,
                authorityBindings: [fixture.authorityBindings[0], duplicateNavigationIdentity]
            )
        }
    }

    func testAuthorityFailuresCarryExactSideWithoutSensitiveDetails() throws {
        let fixture = try makeFixture(specs: [RowSpec("secret-authority.txt")], selectedIndices: [0])
        for side in Workflow.Side.allCases {
            let binding = fixture.authorityBindings[side == .left ? 0 : 1]
            let invalid = Workflow.AuthorityBinding(
                side: side,
                folderAuthorityIdentity: binding.folderAuthorityIdentity,
                folderAuthorityRevision: binding.folderAuthorityRevision + 1,
                navigationAuthorityIdentity: binding.navigationAuthorityIdentity
            )
            var bindings = fixture.authorityBindings
            bindings[side == .left ? 0 : 1] = invalid
            do {
                _ = try plan(fixture, authorityBindings: bindings)
                XCTFail("Expected redacted authority failure")
            } catch let error as Workflow.Error {
                XCTAssertEqual(error.code, .invalidAuthorityBinding)
                XCTAssertEqual(error.side, side)
                assertRedacted(
                    error,
                    secrets: ["secret-authority.txt"]
                        + [
                            fixture.roots.left.requestedURL.absoluteString,
                            fixture.roots.right.requestedURL.absoluteString
                        ]
                        + fixture.authorityBindings.map(\.folderAuthorityIdentity.uuidString)
                        + fixture.authorityBindings.map {
                            $0.navigationAuthorityIdentity.rawValue.uuidString
                        }
                )
            }
        }
    }

    func testPlanningRequiresEveryFolderAndExecutorCapability() throws {
        let fixture = try makeFixture(specs: [RowSpec("capability.txt")], selectedIndices: [0])
        let noFolderFeature = FolderComparisonWorkflowCapabilities(
            identity: fixture.folderCapabilities.identity,
            revision: fixture.folderCapabilities.revision,
            features: []
        )
        assertError(.unsupportedCapability) {
            try plan(fixture, folderCapabilities: noFolderFeature)
        }

        for feature in Workflow.ExecutorFeature.allCases {
            let capabilities = Workflow.ExecutorCapabilities(
                identity: fixture.executorCapabilities.identity,
                revision: fixture.executorCapabilities.revision,
                features: Set(Workflow.ExecutorFeature.allCases).subtracting([feature])
            )
            assertError(.unsupportedCapability) {
                try plan(fixture, executorCapabilities: capabilities)
            }
        }
    }

    func testRequestPlanValidationActionAndPlanningReceiptAreRedactedInReflectionAndDump() throws {
        let fixture = try makeFixture(
            specs: [RowSpec(left: "private/left-secret.txt", right: "private/right-secret.txt")],
            selectedIndices: [0],
            rootPrefix: "/private/selected-secret"
        )
        let request = request(fixture)
        let planned = try Workflow.Planner.plan(request, cancellationCheck: {})
        let validation = executionValidation(fixture)
        let lease = try planned.validateForExecution(validation, cancellationCheck: {})

        assertRedacted(request, secrets: secretFragments(fixture))
        assertRedacted(planned, secrets: secretFragments(fixture))
        assertRedacted(validation, secrets: secretFragments(fixture))
        assertRedacted(lease, secrets: secretFragments(fixture))
        assertRedacted(planned.receipt, secrets: secretFragments(fixture))
        for action in planned.actions {
            assertRedacted(action, secrets: secretFragments(fixture))
            assertRedacted(action.left, secrets: secretFragments(fixture))
            assertRedacted(action.right, secrets: secretFragments(fixture))
        }
    }

    func testStagingExecutionAndOutcomeReceiptsAreRedactedInReflectionAndDump() throws {
        let completedSession = try makeExecutionSession(rootPrefix: "/private/completed-secret")
        let completedEvidence = publicationEvidence(
            plan: completedSession.plan,
            lease: completedSession.publicationLease
        )
        let completed = try Workflow.ExecutionOutcomeFactory.completed(
            plan: completedSession.plan,
            lease: completedSession.publicationLease,
            staging: completedSession.staging,
            publication: completedEvidence
        )

        let failedFixture = try makeFixture(
            specs: [RowSpec("private/failed-secret.txt")],
            selectedIndices: [0],
            rootPrefix: "/private/failed-secret"
        )
        let failedPlan = try plan(failedFixture)
        let failedDiagnostic = Workflow.ExecutionDiagnostic(code: .inputRejected)
        let failed = try Workflow.ExecutionOutcomeFactory.rejectedBeforeStaging(
            plan: failedPlan,
            diagnostic: failedDiagnostic,
            nonPublication: zeroAttemptEvidence(plan: failedPlan)
        )

        let uncertainSession = try makeExecutionSession(rootPrefix: "/private/uncertain-secret")
        let uncertainDiagnostic = Workflow.ExecutionDiagnostic(code: .publicationOutcomeUncertain)
        let uncertain = try Workflow.ExecutionOutcomeFactory.publicationUncertain(
            plan: uncertainSession.plan,
            lease: uncertainSession.publicationLease,
            staging: uncertainSession.staging,
            diagnostic: uncertainDiagnostic,
            publicationAttempt: Workflow.UncertainPublicationEvidence(
                attemptIdentity: uncertainSession.publicationLease.attemptIdentity,
                expectedTarget: uncertainSession.plan.publicationTarget,
                attemptCount: 1,
                actionSHA256s: uncertainSession.plan.actions.map(\.actionSHA256)
            )
        )

        assertRedacted(completedSession.staging, secrets: ["completed-secret"])
        assertRedacted(completed, secrets: ["completed-secret"])
        assertOutcomeReceiptRedacted(completed, secrets: ["completed-secret"])
        assertRedacted(failed, secrets: ["failed-secret"])
        assertOutcomeReceiptRedacted(failed, secrets: ["failed-secret"])
        assertRedacted(uncertain, secrets: ["uncertain-secret"])
        assertOutcomeReceiptRedacted(uncertain, secrets: ["uncertain-secret"])
    }

    func testMalformedDuplicateAndOversizedSelectionPreflightBeforeDelegatedWork() throws {
        let fixture = try makeFixture(
            specs: [RowSpec("first.txt"), RowSpec("second.txt")],
            selectedIndices: [0, 1]
        )

        let emptyProbe = CancellationProbe(cancelOnCall: 2)
        assertError(.emptySelection) {
            try Workflow.Planner.plan(
                request(fixture, selectedItemIdentities: []),
                cancellationCheck: emptyProbe.check
            )
        }
        XCTAssertEqual(emptyProbe.calls, 1)

        let oversizedProbe = CancellationProbe(cancelOnCall: 2)
        assertError(.tooManySelectedItems, limit: .selectedItems, maximum: 1) {
            try Workflow.Planner.plan(
                request(
                    fixture,
                    limits: limits(maximumSelectedItems: 1)
                ),
                cancellationCheck: oversizedProbe.check
            )
        }
        XCTAssertEqual(oversizedProbe.calls, 1)

        let duplicate = fixture.itemIdentities[0]
        let duplicateProbe = CancellationProbe(cancelOnCall: 2)
        assertError(.duplicateSelection, itemIdentity: duplicate) {
            try Workflow.Planner.plan(
                request(fixture, selectedItemIdentities: [duplicate, duplicate]),
                cancellationCheck: duplicateProbe.check
            )
        }
        XCTAssertEqual(duplicateProbe.calls, 1)
    }

    func testSnapshotAndSelectionCountLimitsAcceptBoundaryAndRejectOneUnder() throws {
        let fixture = try makeFixture(
            specs: [RowSpec("one.txt"), RowSpec("two.txt")],
            selectedIndices: [0, 1]
        )
        XCTAssertNoThrow(
            try plan(
                fixture,
                limits: limits(maximumSnapshotItems: 2, maximumSelectedItems: 2)
            )
        )
        assertError(.tooManySnapshotItems, limit: .snapshotItems, maximum: 1) {
            try plan(
                fixture,
                limits: limits(maximumSnapshotItems: 1, maximumSelectedItems: 1)
            )
        }
        assertError(.tooManySelectedItems, limit: .selectedItems, maximum: 1) {
            try plan(
                fixture,
                limits: limits(maximumSnapshotItems: 2, maximumSelectedItems: 1)
            )
        }
    }

    func testAllDeclaredWorkflowLimitGuardsAndHardBoundaries() throws {
        let fixture = try makeFixture(specs: [RowSpec("limits.txt")], selectedIndices: [0])
        let hard = Workflow.Limits(
            maximumSnapshotItems: Workflow.Limits.hardMaximumSnapshotItems,
            maximumSelectedItems: Workflow.Limits.hardMaximumSelectedItems,
            maximumStringUTF8Bytes: Workflow.Limits.hardMaximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: Workflow.Limits.hardMaximumTotalStringUTF8Bytes,
            maximumWorkUnits: Workflow.Limits.hardMaximumWorkUnits,
            cancellationCheckInterval: Workflow.Limits.hardMaximumCancellationCheckInterval
        )
        XCTAssertNoThrow(try plan(fixture, limits: hard))

        let invalid: [(Workflow.Limits, Workflow.Limit)] = [
            (limits(maximumSnapshotItems: 0), .snapshotItems),
            (
                limits(maximumSnapshotItems: Workflow.Limits.hardMaximumSnapshotItems + 1),
                .snapshotItems
            ),
            (limits(maximumSelectedItems: 0), .selectedItems),
            (limits(maximumSnapshotItems: 1, maximumSelectedItems: 2), .selectedItems),
            (limits(maximumStringUTF8Bytes: 0), .stringUTF8Bytes),
            (
                limits(maximumStringUTF8Bytes: Workflow.Limits.hardMaximumStringUTF8Bytes + 1),
                .stringUTF8Bytes
            ),
            (
                limits(maximumStringUTF8Bytes: 2, maximumTotalStringUTF8Bytes: 1),
                .totalStringUTF8Bytes
            ),
            (
                limits(
                    maximumTotalStringUTF8Bytes:
                        Workflow.Limits.hardMaximumTotalStringUTF8Bytes + 1
                ),
                .totalStringUTF8Bytes
            ),
            (limits(maximumWorkUnits: 0), .workUnits),
            (limits(maximumWorkUnits: Workflow.Limits.hardMaximumWorkUnits + 1), .workUnits),
            (limits(cancellationCheckInterval: 0), .cancellationCheckInterval),
            (
                limits(
                    cancellationCheckInterval:
                        Workflow.Limits.hardMaximumCancellationCheckInterval + 1
                ),
                .cancellationCheckInterval
            )
        ]
        for (value, field) in invalid {
            assertError(.invalidLimit, limit: field) {
                try plan(fixture, limits: value)
            }
        }
    }

    func testStringTotalStringAndWorkLimitsUseExactBoundaryAndOneUnder() throws {
        let fixture = try makeFixture(
            specs: [RowSpec(left: "folder/alpha.txt", right: "folder/beta.txt")],
            selectedIndices: [0]
        )
        let exactString = 28
        XCTAssertNoThrow(
            try plan(fixture, limits: limits(maximumStringUTF8Bytes: exactString))
        )
        assertError(.stringLimitExceeded, limit: .stringUTF8Bytes, maximum: UInt64(exactString - 1)) {
            try plan(
                fixture,
                limits: limits(maximumStringUTF8Bytes: exactString - 1)
            )
        }

        let exactTotal = 798
        XCTAssertNoThrow(
            try plan(
                fixture,
                limits: limits(
                    maximumStringUTF8Bytes: exactString,
                    maximumTotalStringUTF8Bytes: exactTotal
                )
            )
        )
        assertError(
            .totalStringLimitExceeded,
            limit: .totalStringUTF8Bytes,
            maximum: UInt64(exactTotal - 1)
        ) {
            try plan(
                fixture,
                limits: limits(
                    maximumStringUTF8Bytes: exactString,
                    maximumTotalStringUTF8Bytes: exactTotal - 1
                )
            )
        }

        let exactWork: UInt64 = 4_067
        let exactPlan = try plan(fixture, limits: limits(maximumWorkUnits: exactWork))
        XCTAssertEqual(exactPlan.receipt.planningWorkUnits, exactWork)
        assertError(.workLimitExceeded, limit: .workUnits, maximum: exactWork - 1) {
            try plan(fixture, limits: limits(maximumWorkUnits: exactWork - 1))
        }
    }

    func testNavigationDeclaredLimitsAreValidatedAndDigestBound() throws {
        let roots = makeRoots()
        let rows = [makeRow(RowSpec("navigation.txt"), roots: roots, index: 0)]
        let identities = [itemIdentity(0)]
        let authorities = navigationAuthorities(roots: roots)
        let exactLimits = navigationLimits(maximumItemCount: 1)
        let exact = try navigationSnapshot(
            rows: rows.map(\.result),
            selectedIndices: [0],
            roots: roots,
            itemIdentities: identities,
            authorities: authorities,
            limits: exactLimits
        )
        let exactReference = try Workflow.Planner.navigationReference(to: exact)
        let mutations: [(String, ComparedFileNavigationLimits)] = [
            ("maximumItemCount", navigationLimits(maximumItemCount: 2)),
            ("maximumSortDescriptorCount", navigationLimits(maximumItemCount: 1, maximumSortDescriptorCount: 65)),
            ("maximumStringUTF8Bytes", navigationLimits(maximumItemCount: 1, maximumStringUTF8Bytes: 16 * 1_024 + 1)),
            ("maximumTotalStringUTF8Bytes", navigationLimits(maximumItemCount: 1, maximumTotalStringUTF8Bytes: 16 * 1_024 * 1_024 + 1)),
            ("maximumWorkUnits", navigationLimits(maximumItemCount: 1, maximumWorkUnits: 64 * 1_024 * 1_024 + 1)),
            ("cancellationCheckInterval", navigationLimits(maximumItemCount: 1, cancellationCheckInterval: 1_025))
        ]
        for (field, mutation) in mutations {
            let snapshot = try navigationSnapshot(
                rows: rows.map(\.result),
                selectedIndices: [0],
                roots: roots,
                itemIdentities: identities,
                authorities: authorities,
                limits: mutation
            )
            let reference = try Workflow.Planner.navigationReference(to: snapshot)
            XCTAssertNotEqual(exactReference.stateSHA256, reference.stateSHA256, field)
        }

        XCTAssertThrowsError(
            try navigationSnapshot(
                rows: rows.map(\.result),
                selectedIndices: [0],
                roots: roots,
                itemIdentities: identities,
                authorities: authorities,
                limits: navigationLimits(maximumItemCount: 0)
            )
        ) { error in
            XCTAssertEqual(error as? ComparedFileNavigationError, .tooManyItems(maximum: 0))
        }

        let empty = try navigationSnapshot(
            rows: [],
            selectedIndices: [],
            roots: roots,
            itemIdentities: [],
            authorities: authorities,
            limits: navigationLimits(maximumItemCount: 0)
        )
        XCTAssertNoThrow(try Workflow.Planner.navigationReference(to: empty))
    }

    func testCustomCancellationPropagatesFromDelegatedFolderHashingDuringPlanAndValidation() throws {
        let fixture = try makeFixture(
            specs: (0..<32).map { RowSpec("delegated-\($0).txt") },
            selectedIndices: [0]
        )
        let planningProbe = CancellationProbe(cancelOnCall: 4, error: ProbeError.custom)
        assertError(.cancelled) {
            try Workflow.Planner.plan(
                request(fixture),
                cancellationCheck: planningProbe.check
            )
        }
        XCTAssertEqual(planningProbe.calls, 4)

        let planned = try plan(fixture)
        let validationProbe = CancellationProbe(cancelOnCall: 4, error: ProbeError.custom)
        assertError(.cancelled) {
            try planned.validateForExecution(
                executionValidation(fixture),
                cancellationCheck: validationProbe.check
            )
        }
        XCTAssertEqual(validationProbe.calls, 4)
    }

    func testSelectionValidationChecksCancellationAtConfiguredIntervals() throws {
        let fixture = try makeFixture(
            specs: [RowSpec("first.txt"), RowSpec("second.txt")],
            selectedIndices: [0, 1]
        )
        let probe = CancellationProbe(cancelOnCall: 2)
        assertError(.cancelled) {
            try Workflow.Planner.plan(
                request(fixture, limits: limits(cancellationCheckInterval: 1)),
                cancellationCheck: probe.check
            )
        }
        XCTAssertEqual(probe.calls, 2)
    }

    func testTaskCancellationAfterWorkStartsPropagatesThroughPlanNavigationHashAndValidation() async throws {
        let fixture = try makeFixture(
            specs: (0..<128).map { RowSpec("cancel-\($0).txt") },
            selectedIndices: [0]
        )
        let request = request(fixture)
        let navigation = fixture.navigationSnapshot
        let planned = try plan(fixture)
        let validation = executionValidation(fixture)

        let planningBarrier = CancellationBarrier(triggerOnCall: 3)
        let planningCode = Task.detached { () -> Workflow.ErrorCode? in
            captureErrorCode {
                try Workflow.Planner.plan(request, cancellationCheck: planningBarrier.check)
            }
        }
        XCTAssertTrue(planningBarrier.waitUntilEntered())
        planningCode.cancel()
        planningBarrier.release()
        let cancelledPlanningCode = await planningCode.value
        XCTAssertEqual(cancelledPlanningCode, .cancelled)

        let navigationBarrier = CancellationBarrier(triggerOnCall: 2)
        let navigationCode = Task.detached { () -> Workflow.ErrorCode? in
            captureErrorCode {
                try Workflow.Planner.navigationReference(
                    to: navigation,
                    cancellationCheck: navigationBarrier.check
                )
            }
        }
        XCTAssertTrue(navigationBarrier.waitUntilEntered())
        navigationCode.cancel()
        navigationBarrier.release()
        let cancelledNavigationCode = await navigationCode.value
        XCTAssertEqual(cancelledNavigationCode, .cancelled)

        let validationBarrier = CancellationBarrier(triggerOnCall: 3)
        let validationCode = Task.detached { () -> Workflow.ErrorCode? in
            captureErrorCode {
                try planned.validateForExecution(
                    validation,
                    cancellationCheck: validationBarrier.check
                )
            }
        }
        XCTAssertTrue(validationBarrier.waitUntilEntered())
        validationCode.cancel()
        validationBarrier.release()
        let cancelledValidationCode = await validationCode.value
        XCTAssertEqual(cancelledValidationCode, .cancelled)
    }

    func testPlanningReceiptsAndActionHashesAreDeterministicAndMutationSensitive() throws {
        let specs = [RowSpec("b.txt"), RowSpec("a.txt", status: .identical)]
        let first = try makeFixture(specs: specs, selectedIndices: [0, 1])
        let second = try makeFixture(specs: specs, selectedIndices: [0, 1])
        let firstPlan = try plan(
            first,
            selectedItemIdentities: [first.itemIdentities[0], first.itemIdentities[1]]
        )
        let secondPlan = try plan(
            second,
            selectedItemIdentities: [second.itemIdentities[1], second.itemIdentities[0]]
        )

        XCTAssertEqual(firstPlan.receipt, secondPlan.receipt)
        XCTAssertEqual(firstPlan.actions.map(\.actionSHA256), secondPlan.actions.map(\.actionSHA256))
        XCTAssertEqual(firstPlan.receipt.actionSHA256s, firstPlan.actions.map(\.actionSHA256))
        XCTAssertEqual(firstPlan.receipt.selectedItemCount, 2)

        let sourceMutation = try makeFixture(
            specs: specs,
            selectedIndices: [0, 1],
            physicalIdentityOffset: 40
        )
        let sourcePlan = try plan(sourceMutation)
        XCTAssertNotEqual(firstPlan.actions.map(\.actionSHA256), sourcePlan.actions.map(\.actionSHA256))
        XCTAssertNotEqual(firstPlan.receipt.planSHA256, sourcePlan.receipt.planSHA256)

        let publicationPlan = try plan(
            first,
            publicationTarget: Workflow.PublicationTarget(
                identity: first.publicationTarget.identity,
                revision: first.publicationTarget.revision + 1
            )
        )
        XCTAssertEqual(firstPlan.actions.map(\.actionSHA256), publicationPlan.actions.map(\.actionSHA256))
        XCTAssertNotEqual(firstPlan.receipt.planSHA256, publicationPlan.receipt.planSHA256)

        let capabilityMutations = [
            try plan(
                first,
                folderCapabilities: FolderComparisonWorkflowCapabilities(
                    identity: uuid(702),
                    revision: first.folderCapabilities.revision,
                    features: first.folderCapabilities.features
                )
            ),
            try plan(
                first,
                folderCapabilities: FolderComparisonWorkflowCapabilities(
                    identity: first.folderCapabilities.identity,
                    revision: first.folderCapabilities.revision + 1,
                    features: first.folderCapabilities.features
                )
            ),
            try plan(
                first,
                executorCapabilities: Workflow.ExecutorCapabilities(
                    identity: uuid(703),
                    revision: first.executorCapabilities.revision,
                    features: first.executorCapabilities.features
                )
            ),
            try plan(
                first,
                executorCapabilities: Workflow.ExecutorCapabilities(
                    identity: first.executorCapabilities.identity,
                    revision: first.executorCapabilities.revision + 1,
                    features: first.executorCapabilities.features
                )
            )
        ]
        for mutation in capabilityMutations {
            XCTAssertEqual(firstPlan.actions.map(\.actionSHA256), mutation.actions.map(\.actionSHA256))
            XCTAssertNotEqual(firstPlan.receipt.planSHA256, mutation.receipt.planSHA256)
        }

        let limitMutations = [
            try plan(first, folderValidationLimits: folderLimits(maximumResultItems: 1_000_001)),
            try plan(first, folderValidationLimits: folderLimits(maximumSelectedItems: 100_001)),
            try plan(first, folderValidationLimits: folderLimits(maximumOperationActions: 200_001)),
            try plan(first, folderValidationLimits: folderLimits(maximumPresentationRows: 999_999)),
            try plan(first, folderValidationLimits: folderLimits(maximumColumns: 9)),
            try plan(first, folderValidationLimits: folderLimits(maximumSortDescriptors: 9)),
            try plan(first, folderValidationLimits: folderLimits(maximumFilterRules: 1_025)),
            try plan(first, folderValidationLimits: folderLimits(maximumStringUTF8Bytes: 16 * 1_024 + 1)),
            try plan(
                first,
                folderValidationLimits: folderLimits(
                    maximumTotalStringUTF8Bytes: 64 * 1_024 * 1_024 + 1
                )
            ),
            try plan(first, folderValidationLimits: folderLimits(maximumMetadataDigestBytes: 1_025)),
            try plan(
                first,
                folderValidationLimits: folderLimits(maximumWorkUnits: 512 * 1_024 * 1_024 + 1)
            ),
            try plan(first, folderValidationLimits: folderLimits(cancellationCheckInterval: 1_025)),
            try plan(first, limits: limits(maximumSnapshotItems: 100_001)),
            try plan(first, limits: limits(maximumSelectedItems: 1_025)),
            try plan(first, limits: limits(maximumStringUTF8Bytes: 16 * 1_024 + 1)),
            try plan(first, limits: limits(maximumTotalStringUTF8Bytes: 16 * 1_024 * 1_024 + 1)),
            try plan(first, limits: limits(maximumWorkUnits: 64 * 1_024 * 1_024 + 1)),
            try plan(first, limits: limits(cancellationCheckInterval: 1_025))
        ]
        for mutation in limitMutations {
            XCTAssertEqual(firstPlan.actions.map(\.actionSHA256), mutation.actions.map(\.actionSHA256))
            XCTAssertNotEqual(firstPlan.receipt.planSHA256, mutation.receipt.planSHA256)
        }
    }

    func testSecurityScopeURLHashingConsumesDeclaredWork() throws {
        let ambient = try makeFixture(
            specs: [RowSpec("scope.txt")],
            selectedIndices: [0],
            rootPrefix: "/selected-scope"
        )
        let scoped = try makeFixture(
            specs: [RowSpec("scope.txt")],
            selectedIndices: [0],
            rootPrefix: "/selected-scope",
            securityScopedRoots: true
        )
        let ambientPlan = try plan(ambient)
        let scopedPlan = try plan(scoped)
        let resourceBytes = Workflow.Side.allCases.reduce(0) { total, side in
            let root = side == .left ? scoped.roots.left : scoped.roots.right
            guard case .securityScoped(let resourceURL, _) = root.authority.acquisition else {
                return total
            }
            return total + resourceURL.absoluteString.utf8.count
        }

        XCTAssertEqual(
            scopedPlan.receipt.planningWorkUnits - ambientPlan.receipt.planningWorkUnits,
            UInt64(resourceBytes * 2)
        )
    }

    func testPlanDeclaresAllOrNoneFailureAndExecutorContracts() throws {
        let fixture = try makeFixture(specs: [RowSpec("contract.txt")], selectedIndices: [0])
        let planned = try plan(fixture)

        XCTAssertEqual(planned.failurePolicy, .stageAllThenPublishAllOrNone)
        XCTAssertEqual(
            planned.executorContract.validation,
            .exactFolderNavigationSelectionCapabilityAuthorityAndPublicationCAS
        )
        XCTAssertEqual(
            planned.executorContract.sourceAccess,
            .acquireBothBoundAuthoritiesAndOpenPinnedDescriptorRelativeRegularFilesWithoutFollowingLinks
        )
        XCTAssertEqual(
            planned.executorContract.staging,
            .stageEveryOrderedPairReadOnlyBeforePublicationAndReportEveryRow
        )
        XCTAssertEqual(
            planned.executorContract.publication,
            .publishCompleteOrderedBatchAtomicallyExactlyOnceOrPublishNothing
        )
        XCTAssertEqual(
            planned.executorContract.cancellation,
            .checkPeriodicallyDuringPlanningAndBeforeEachStageAndImmediatelyBeforePublication
        )
        XCTAssertEqual(planned.executorContract.ui, .noAppKitWindowCreationOrUIParityClaim)
    }

    func testExecutionValidationBindsFolderNavigationCapabilitiesAuthoritiesAndPublicationCAS() throws {
        let fixture = try makeFixture(specs: [RowSpec("cas.txt")], selectedIndices: [0])
        let planned = try plan(fixture)
        XCTAssertNoThrow(
            try planned.validateForExecution(executionValidation(fixture), cancellationCheck: {})
        )

        let staleFolder = folderSnapshot(
            roots: fixture.roots,
            rows: fixture.rows,
            generation: fixture.folderSnapshot.generation + 1,
            ownerRevision: fixture.folderSnapshot.owner.revision + 1
        )
        assertError(.staleFolderSnapshot) {
            try planned.validateForExecution(
                executionValidation(fixture, folderSnapshot: staleFolder),
                cancellationCheck: {}
            )
        }

        let staleNavigation = try navigationSnapshot(
            rows: fixture.rows.map(\.result),
            selectedIndices: [0],
            roots: fixture.roots,
            itemIdentities: fixture.itemIdentities,
            authorities: fixture.navigationAuthorities,
            revision: fixture.navigationSnapshot.revision.rawValue + 1
        )
        assertError(.staleNavigationSnapshot) {
            try planned.validateForExecution(
                executionValidation(fixture, navigationSnapshot: staleNavigation),
                cancellationCheck: {}
            )
        }

        let staleFolderCapabilities = FolderComparisonWorkflowCapabilities(
            identity: fixture.folderCapabilities.identity,
            revision: fixture.folderCapabilities.revision + 1,
            features: fixture.folderCapabilities.features
        )
        assertError(.staleCapabilities) {
            try planned.validateForExecution(
                executionValidation(fixture, folderCapabilities: staleFolderCapabilities),
                cancellationCheck: {}
            )
        }

        let staleExecutorCapabilities = Workflow.ExecutorCapabilities(
            identity: fixture.executorCapabilities.identity,
            revision: fixture.executorCapabilities.revision + 1,
            features: fixture.executorCapabilities.features
        )
        assertError(.staleCapabilities) {
            try planned.validateForExecution(
                executionValidation(fixture, executorCapabilities: staleExecutorCapabilities),
                cancellationCheck: {}
            )
        }

        let stalePublication = Workflow.PublicationTarget(
            identity: fixture.publicationTarget.identity,
            revision: fixture.publicationTarget.revision + 1
        )
        assertError(.stalePublicationTarget) {
            try planned.validateForExecution(
                executionValidation(fixture, publicationTarget: stalePublication),
                cancellationCheck: {}
            )
        }

        XCTAssertNoThrow(
            try planned.validateForExecution(
                executionValidation(
                    fixture,
                    authorityBindings: fixture.authorityBindings.reversed()
                ),
                cancellationCheck: {}
            )
        )
    }

    func testExecutionAndPublicationPermitsAreOneShotUnderContention() async throws {
        let fixture = try makeFixture(specs: [RowSpec("one-shot.txt")], selectedIndices: [0])
        let planned = try plan(fixture)
        let validation = executionValidation(fixture)
        let stagingLease = try planned.validateForExecution(validation, cancellationCheck: {})
        let evidence = stagedEvidence(planned)
        let stagingAttempts = await withTaskGroup(of: Workflow.StagingReceipt?.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try? Workflow.ExecutionOutcomeFactory.staged(
                        plan: planned,
                        lease: stagingLease,
                        itemEvidence: evidence
                    )
                }
            }
            return await group.reduce(into: []) { $0.append($1) }.compactMap { $0 }
        }
        let staging = try XCTUnwrap(stagingAttempts.first)
        XCTAssertEqual(stagingAttempts.count, 1)

        let publicationAttempts = await withTaskGroup(of: Workflow.ExecutionLease?.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try? planned.validateForPublication(
                        validation,
                        staging: staging,
                        cancellationCheck: {}
                    )
                }
            }
            return await group.reduce(into: []) { $0.append($1) }.compactMap { $0 }
        }
        let publicationLease = try XCTUnwrap(publicationAttempts.first)
        XCTAssertEqual(publicationAttempts.count, 1)

        let completionAttempts = await withTaskGroup(of: Workflow.ExecutionOutcome?.self) { group in
            let evidence = publicationEvidence(plan: planned, lease: publicationLease)
            for _ in 0..<16 {
                group.addTask {
                    try? Workflow.ExecutionOutcomeFactory.completed(
                        plan: planned,
                        lease: publicationLease,
                        staging: staging,
                        publication: evidence
                    )
                }
            }
            return await group.reduce(into: []) { $0.append($1) }.compactMap { $0 }
        }
        XCTAssertEqual(completionAttempts.count, 1)
    }

    func testCrossPlanAndCrossExecutionSessionPermitsAreRejected() throws {
        let first = try makeFixture(specs: [RowSpec("first-plan.txt")], selectedIndices: [0])
        let second = try makeFixture(
            specs: [RowSpec("second-plan.txt")],
            selectedIndices: [0],
            physicalIdentityOffset: 40
        )
        let firstPlan = try plan(first)
        let secondPlan = try plan(second)
        let firstLease = try firstPlan.validateForExecution(
            executionValidation(first),
            cancellationCheck: {}
        )
        assertError(.invalidExecutionEvidence) {
            try Workflow.ExecutionOutcomeFactory.staged(
                plan: secondPlan,
                lease: firstLease,
                itemEvidence: stagedEvidence(secondPlan)
            )
        }

        let sharedFixture = try makeFixture(specs: [RowSpec("session.txt")], selectedIndices: [0])
        let sharedPlan = try plan(sharedFixture)
        let validation = executionValidation(sharedFixture)
        let firstStaging = try makeStaging(plan: sharedPlan, validation: validation)
        let secondStaging = try makeStaging(plan: sharedPlan, validation: validation)
        let firstPublicationLease = try sharedPlan.validateForPublication(
            validation,
            staging: firstStaging,
            cancellationCheck: {}
        )
        assertError(.invalidExecutionEvidence) {
            try Workflow.ExecutionOutcomeFactory.completed(
                plan: sharedPlan,
                lease: firstPublicationLease,
                staging: secondStaging,
                publication: publicationEvidence(
                    plan: sharedPlan,
                    lease: firstPublicationLease
                )
            )
        }

        let secondPublicationLease = try sharedPlan.validateForPublication(
            validation,
            staging: secondStaging,
            cancellationCheck: {}
        )
        let publicationFailure = Workflow.ExecutionDiagnostic(code: .publicationFailed)
        assertError(.invalidExecutionEvidence) {
            try Workflow.ExecutionOutcomeFactory.notPublished(
                plan: sharedPlan,
                lease: secondPublicationLease,
                staging: firstStaging,
                diagnostic: publicationFailure,
                nonPublication: oneAttemptEvidence(
                    plan: sharedPlan,
                    lease: secondPublicationLease
                )
            )
        }
    }

    func testCompletedOutcomeRequiresExactSessionNonceBatchAndSuccessorCAS() throws {
        let session = try makeExecutionSession()
        let publication = publicationEvidence(plan: session.plan, lease: session.publicationLease)
        let outcome = try Workflow.ExecutionOutcomeFactory.completed(
            plan: session.plan,
            lease: session.publicationLease,
            staging: session.staging,
            publication: publication
        )
        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected completed outcome")
        }
        XCTAssertEqual(receipt.planningReceipt, session.plan.receipt)
        XCTAssertEqual(receipt.itemEvidence, stagedEvidence(session.plan))
        XCTAssertEqual(receipt.publication, publication)

        for mutation in PublicationMutation.allCases {
            let rejected = try makeExecutionSession()
            let evidence = mutatedPublicationEvidence(
                publicationEvidence(plan: rejected.plan, lease: rejected.publicationLease),
                mutation: mutation
            )
            assertError(.invalidExecutionEvidence, mutation.rawValue) {
                try Workflow.ExecutionOutcomeFactory.completed(
                    plan: rejected.plan,
                    lease: rejected.publicationLease,
                    staging: rejected.staging,
                    publication: evidence
                )
            }
        }
    }

    func testPublicationTransitionsAreMonotonicAndExactlyOneRevisionOnSuccess() throws {
        for successor in [
            Workflow.PublicationTarget(identity: uuid(900), revision: 9),
            Workflow.PublicationTarget(identity: uuid(901), revision: 10),
            Workflow.PublicationTarget(identity: uuid(900), revision: 11),
            Workflow.PublicationTarget(identity: uuid(900), revision: 12)
        ] {
            let session = try makeExecutionSession()
            let evidence = Workflow.PublicationEvidence(
                attemptIdentity: session.publicationLease.attemptIdentity,
                expectedTarget: session.plan.publicationTarget,
                successorTarget: successor,
                publicationCount: 1,
                actionSHA256s: session.plan.actions.map(\.actionSHA256)
            )
            if successor
                == Workflow.PublicationTarget(
                    identity: session.plan.publicationTarget.identity,
                    revision: session.plan.publicationTarget.revision + 1
                )
            {
                XCTAssertNoThrow(
                    try Workflow.ExecutionOutcomeFactory.completed(
                        plan: session.plan,
                        lease: session.publicationLease,
                        staging: session.staging,
                        publication: evidence
                    )
                )
            } else {
                assertError(.invalidExecutionEvidence) {
                    try Workflow.ExecutionOutcomeFactory.completed(
                        plan: session.plan,
                        lease: session.publicationLease,
                        staging: session.staging,
                        publication: evidence
                    )
                }
            }
        }

        let fixture = try makeFixture(specs: [RowSpec("stale-target.txt")], selectedIndices: [0])
        let planned = try plan(fixture)
        let diagnostic = Workflow.ExecutionDiagnostic(code: .stalePublicationTarget)
        let advanced = Workflow.PublicationTarget(
            identity: planned.publicationTarget.identity,
            revision: planned.publicationTarget.revision + 1
        )
        XCTAssertNoThrow(
            try Workflow.ExecutionOutcomeFactory.rejectedBeforeStaging(
                plan: planned,
                diagnostic: diagnostic,
                nonPublication: zeroAttemptEvidence(plan: planned, observedTarget: advanced)
            )
        )
        for observed in [
            Workflow.PublicationTarget(
                identity: planned.publicationTarget.identity,
                revision: planned.publicationTarget.revision - 1
            ),
            Workflow.PublicationTarget(
                identity: uuid(999),
                revision: planned.publicationTarget.revision + 1
            )
        ] {
            assertError(.invalidExecutionEvidence) {
                try Workflow.ExecutionOutcomeFactory.rejectedBeforeStaging(
                    plan: planned,
                    diagnostic: diagnostic,
                    nonPublication: zeroAttemptEvidence(plan: planned, observedTarget: observed)
                )
            }
        }
    }

    func testEveryGlobalRejectionProducesCoherentNotAttemptedEvidence() throws {
        let fixture = try makeFixture(
            specs: [RowSpec("one.txt"), RowSpec("two.txt")],
            selectedIndices: [0, 1]
        )
        let planned = try plan(fixture)
        let globalCodes: [Workflow.ExecutionDiagnosticCode] = [
            .staleFolderSnapshot,
            .staleNavigationSnapshot,
            .staleCapabilities,
            .staleAuthority,
            .cancelledBeforePublication,
            .contractUnsupported,
            .limitExceeded,
            .inputRejected
        ]
        for code in globalCodes {
            let diagnostic = Workflow.ExecutionDiagnostic(code: code)
            let outcome = try Workflow.ExecutionOutcomeFactory.rejectedBeforeStaging(
                plan: planned,
                diagnostic: diagnostic,
                nonPublication: zeroAttemptEvidence(plan: planned)
            )
            guard case .notPublished(let receipt) = outcome else {
                return XCTFail("Expected notPublished for \(code)")
            }
            XCTAssertEqual(receipt.diagnostic, diagnostic)
            XCTAssertEqual(receipt.itemEvidence.count, planned.actions.count)
            for (action, item) in zip(planned.actions, receipt.itemEvidence) {
                XCTAssertEqual(item.actionIndex, action.index)
                XCTAssertEqual(item.actionSHA256, action.actionSHA256)
                XCTAssertEqual(item.disposition, .notAttempted(diagnostic))
            }
        }

        for diagnostic in [
            Workflow.ExecutionDiagnostic(code: .sourceOpenFailed, actionIndex: 0, side: .left),
            Workflow.ExecutionDiagnostic(code: .inputRejected, side: .right),
            Workflow.ExecutionDiagnostic(code: .inputRejected, actionIndex: 0)
        ] {
            assertError(.invalidExecutionEvidence) {
                try Workflow.ExecutionOutcomeFactory.rejectedBeforeStaging(
                    plan: planned,
                    diagnostic: diagnostic,
                    nonPublication: zeroAttemptEvidence(plan: planned)
                )
            }
        }
    }

    func testPartialFailureRequiresMatchingPerRowEvidenceAndTerminalNotAttemptedOrdering() throws {
        let fixture = try makeFixture(
            specs: [RowSpec("a.txt"), RowSpec("b.txt"), RowSpec("c.txt")],
            selectedIndices: [0, 1, 2]
        )
        let planned = try plan(fixture)
        let validation = executionValidation(fixture)
        let lease = try planned.validateForExecution(validation, cancellationCheck: {})
        let failure = Workflow.ExecutionDiagnostic(
            code: .sourceOpenFailed,
            actionIndex: 1,
            side: .right
        )
        let blocked = Workflow.ExecutionDiagnostic(
            code: .blockedByEarlierFailure,
            actionIndex: 2
        )
        let evidence = [
            itemEvidence(planned, index: 0, disposition: .stagedReadOnly),
            itemEvidence(planned, index: 1, disposition: .failed(failure)),
            itemEvidence(planned, index: 2, disposition: .notAttempted(blocked))
        ]
        let outcome = try Workflow.ExecutionOutcomeFactory.notPublished(
            plan: planned,
            lease: lease,
            itemEvidence: evidence,
            diagnostic: failure,
            nonPublication: zeroAttemptEvidence(plan: planned)
        )
        guard case .notPublished(let receipt) = outcome else {
            return XCTFail("Expected partial notPublished outcome")
        }
        XCTAssertEqual(receipt.itemEvidence, evidence)

        let orderingLease = try planned.validateForExecution(validation, cancellationCheck: {})
        let invalidOrdering = [
            itemEvidence(
                planned, index: 0,
                disposition: .failed(
                    Workflow.ExecutionDiagnostic(code: .comparisonStagingFailed, actionIndex: 0)
                )),
            itemEvidence(
                planned, index: 1,
                disposition: .notAttempted(
                    Workflow.ExecutionDiagnostic(code: .blockedByEarlierFailure, actionIndex: 1)
                )),
            itemEvidence(planned, index: 2, disposition: .stagedReadOnly)
        ]
        assertError(.invalidExecutionEvidence) {
            try Workflow.ExecutionOutcomeFactory.notPublished(
                plan: planned,
                lease: orderingLease,
                itemEvidence: invalidOrdering,
                diagnostic: Workflow.ExecutionDiagnostic(
                    code: .comparisonStagingFailed,
                    actionIndex: 0
                ),
                nonPublication: zeroAttemptEvidence(plan: planned)
            )
        }
    }

    func testPerRowDiagnosticsEnforceActionAndSideCoherence() throws {
        let fixture = try makeFixture(specs: [RowSpec("diagnostic.txt")], selectedIndices: [0])
        let planned = try plan(fixture)
        let validation = executionValidation(fixture)
        for code in [
            Workflow.ExecutionDiagnosticCode.sourceChanged,
            .authorityUnavailable,
            .sourceOpenFailed
        ] {
            for side in Workflow.Side.allCases {
                let lease = try planned.validateForExecution(validation, cancellationCheck: {})
                let diagnostic = Workflow.ExecutionDiagnostic(
                    code: code,
                    actionIndex: 0,
                    side: side
                )
                XCTAssertNoThrow(
                    try Workflow.ExecutionOutcomeFactory.notPublished(
                        plan: planned,
                        lease: lease,
                        itemEvidence: [
                            itemEvidence(planned, index: 0, disposition: .failed(diagnostic))
                        ],
                        diagnostic: diagnostic,
                        nonPublication: zeroAttemptEvidence(plan: planned)
                    )
                )
            }
        }

        for diagnostic in [
            Workflow.ExecutionDiagnostic(
                code: .comparisonStagingFailed,
                actionIndex: 0,
                side: .left
            ),
            Workflow.ExecutionDiagnostic(code: .sourceChanged),
            Workflow.ExecutionDiagnostic(code: .sourceOpenFailed, actionIndex: 1),
            Workflow.ExecutionDiagnostic(
                code: .blockedByEarlierFailure,
                actionIndex: 0,
                side: .right
            )
        ] {
            let lease = try planned.validateForExecution(validation, cancellationCheck: {})
            assertError(.invalidExecutionEvidence) {
                try Workflow.ExecutionOutcomeFactory.notPublished(
                    plan: planned,
                    lease: lease,
                    itemEvidence: [
                        itemEvidence(planned, index: 0, disposition: .failed(diagnostic))
                    ],
                    diagnostic: diagnostic,
                    nonPublication: zeroAttemptEvidence(plan: planned)
                )
            }
        }

        for code in [
            Workflow.ExecutionDiagnosticCode.sourceChanged,
            .authorityUnavailable,
            .sourceOpenFailed
        ] {
            let diagnostic = Workflow.ExecutionDiagnostic(code: code, actionIndex: 0)
            let lease = try planned.validateForExecution(validation, cancellationCheck: {})
            assertError(.invalidExecutionEvidence, code.rawValue) {
                try Workflow.ExecutionOutcomeFactory.notPublished(
                    plan: planned,
                    lease: lease,
                    itemEvidence: [
                        itemEvidence(planned, index: 0, disposition: .failed(diagnostic))
                    ],
                    diagnostic: diagnostic,
                    nonPublication: zeroAttemptEvidence(plan: planned)
                )
            }
        }
    }

    func testPublicationFailureRequiresAllRowsStagedOneAttemptAndMatchingNonce() throws {
        let session = try makeExecutionSession(rowCount: 2)
        let diagnostic = Workflow.ExecutionDiagnostic(code: .publicationFailed)
        let evidence = Workflow.NonPublicationEvidence(
            expectedTarget: session.plan.publicationTarget,
            observedTargetAfterFailure: session.plan.publicationTarget,
            publicationAttemptCount: 1,
            attemptIdentity: session.publicationLease.attemptIdentity,
            actionSHA256s: session.plan.actions.map(\.actionSHA256)
        )
        let outcome = try Workflow.ExecutionOutcomeFactory.notPublished(
            plan: session.plan,
            lease: session.publicationLease,
            staging: session.staging,
            diagnostic: diagnostic,
            nonPublication: evidence
        )
        guard case .notPublished(let receipt) = outcome else {
            return XCTFail("Expected failed publication")
        }
        XCTAssertEqual(receipt.nonPublication.publicationAttemptCount, 1)
        XCTAssertEqual(receipt.nonPublication.attemptIdentity, evidence.attemptIdentity)

        for mutation in NonPublicationMutation.allCases {
            let rejected = try makeExecutionSession(rowCount: 2)
            let invalid = mutatedNonPublicationEvidence(
                Workflow.NonPublicationEvidence(
                    expectedTarget: rejected.plan.publicationTarget,
                    observedTargetAfterFailure: rejected.plan.publicationTarget,
                    publicationAttemptCount: 1,
                    attemptIdentity: rejected.publicationLease.attemptIdentity,
                    actionSHA256s: rejected.plan.actions.map(\.actionSHA256)
                ),
                mutation: mutation
            )
            assertError(.invalidExecutionEvidence, mutation.rawValue) {
                try Workflow.ExecutionOutcomeFactory.notPublished(
                    plan: rejected.plan,
                    lease: rejected.publicationLease,
                    staging: rejected.staging,
                    diagnostic: diagnostic,
                    nonPublication: invalid
                )
            }
        }
    }

    func testCancellationAfterPublicationValidationProvesNoAttemptAndConsumesSession() throws {
        let session = try makeExecutionSession(rowCount: 2)
        let diagnostic = Workflow.ExecutionDiagnostic(code: .cancelledBeforePublication)
        let evidence = zeroAttemptEvidence(plan: session.plan)
        let outcome = try Workflow.ExecutionOutcomeFactory.abandonedBeforePublicationAttempt(
            plan: session.plan,
            lease: session.publicationLease,
            staging: session.staging,
            diagnostic: diagnostic,
            nonPublication: evidence
        )
        guard case .notPublished(let receipt) = outcome else {
            return XCTFail("Expected cancelled notPublished outcome")
        }
        XCTAssertEqual(receipt.diagnostic, diagnostic)
        XCTAssertEqual(receipt.nonPublication.publicationAttemptCount, 0)
        XCTAssertNil(receipt.nonPublication.attemptIdentity)

        assertError(.invalidExecutionEvidence) {
            try Workflow.ExecutionOutcomeFactory.abandonedBeforePublicationAttempt(
                plan: session.plan,
                lease: session.publicationLease,
                staging: session.staging,
                diagnostic: diagnostic,
                nonPublication: evidence
            )
        }
    }

    func testPublicationUncertainRequiresOneBoundAttemptAndCannotBecomeNotPublished() throws {
        let session = try makeExecutionSession(rowCount: 2)
        let diagnostic = Workflow.ExecutionDiagnostic(code: .publicationOutcomeUncertain)
        let evidence = Workflow.UncertainPublicationEvidence(
            attemptIdentity: session.publicationLease.attemptIdentity,
            expectedTarget: session.plan.publicationTarget,
            attemptCount: 1,
            actionSHA256s: session.plan.actions.map(\.actionSHA256)
        )
        let outcome = try Workflow.ExecutionOutcomeFactory.publicationUncertain(
            plan: session.plan,
            lease: session.publicationLease,
            staging: session.staging,
            diagnostic: diagnostic,
            publicationAttempt: evidence
        )
        guard case .publicationUncertain(let receipt) = outcome else {
            return XCTFail("Expected publicationUncertain")
        }
        XCTAssertEqual(receipt.publicationAttempt, evidence)
        XCTAssertEqual(receipt.itemEvidence, session.staging.itemEvidence)

        let rejected = try makeExecutionSession(rowCount: 2)
        assertError(.invalidExecutionEvidence) {
            try Workflow.ExecutionOutcomeFactory.notPublished(
                plan: rejected.plan,
                lease: rejected.publicationLease,
                staging: rejected.staging,
                diagnostic: diagnostic,
                nonPublication: Workflow.NonPublicationEvidence(
                    expectedTarget: rejected.plan.publicationTarget,
                    observedTargetAfterFailure: rejected.plan.publicationTarget,
                    publicationAttemptCount: 1,
                    attemptIdentity: rejected.publicationLease.attemptIdentity,
                    actionSHA256s: rejected.plan.actions.map(\.actionSHA256)
                )
            )
        }
    }

    func testStagingReceiptRequiresEveryOrderedDigestExactlyOnce() throws {
        let fixture = try makeFixture(
            specs: [RowSpec("a.txt"), RowSpec("b.txt")],
            selectedIndices: [0, 1]
        )
        let planned = try plan(fixture)
        let validation = executionValidation(fixture)
        let mutations: [[Workflow.ItemExecutionEvidence]] = [
            Array(stagedEvidence(planned).dropLast()),
            stagedEvidence(planned).reversed(),
            [
                Workflow.ItemExecutionEvidence(
                    actionIndex: 0,
                    actionSHA256: Data(repeating: 0xFF, count: 32),
                    disposition: .stagedReadOnly
                ),
                stagedEvidence(planned)[1]
            ],
            [
                itemEvidence(
                    planned,
                    index: 0,
                    disposition: .failed(
                        Workflow.ExecutionDiagnostic(
                            code: .comparisonStagingFailed,
                            actionIndex: 0
                        )
                    )
                ),
                stagedEvidence(planned)[1]
            ]
        ]
        for evidence in mutations {
            let lease = try planned.validateForExecution(validation, cancellationCheck: {})
            assertError(.invalidExecutionEvidence) {
                try Workflow.ExecutionOutcomeFactory.staged(
                    plan: planned,
                    lease: lease,
                    itemEvidence: evidence
                )
            }
        }
    }

    func testPublicationRevisionOverflowIsRejectedBeforeHashing() throws {
        let fixture = try makeFixture(specs: [RowSpec("overflow.txt")], selectedIndices: [0])
        let probe = CancellationProbe(cancelOnCall: 2)
        assertError(.publicationRevisionOverflow) {
            try Workflow.Planner.plan(
                request(
                    fixture,
                    publicationTarget: Workflow.PublicationTarget(
                        identity: fixture.publicationTarget.identity,
                        revision: UInt64.max
                    )
                ),
                cancellationCheck: probe.check
            )
        }
        XCTAssertEqual(probe.calls, 1)

        let boundaryPlan = try plan(
            fixture,
            publicationTarget: Workflow.PublicationTarget(
                identity: fixture.publicationTarget.identity,
                revision: UInt64.max - 1
            )
        )
        let validation = executionValidation(
            fixture,
            publicationTarget: boundaryPlan.publicationTarget
        )
        let staging = try makeStaging(plan: boundaryPlan, validation: validation)
        let publicationLease = try boundaryPlan.validateForPublication(
            validation,
            staging: staging,
            cancellationCheck: {}
        )
        let outcome = try Workflow.ExecutionOutcomeFactory.completed(
            plan: boundaryPlan,
            lease: publicationLease,
            staging: staging,
            publication: publicationEvidence(plan: boundaryPlan, lease: publicationLease)
        )
        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected completed boundary publication")
        }
        XCTAssertEqual(receipt.publication.successorTarget.revision, UInt64.max)
    }

    private struct RowSpec {
        let leftPath: String
        let rightPath: String
        let status: DirectoryComparisonStatus
        let leftKind: DirectoryEntryKind
        let rightKind: DirectoryEntryKind

        init(
            _ path: String,
            status: DirectoryComparisonStatus = .different,
            kind: DirectoryEntryKind = .file
        ) {
            self.init(left: path, right: path, status: status, kind: kind)
        }

        init(
            left: String,
            right: String,
            status: DirectoryComparisonStatus = .different,
            kind: DirectoryEntryKind = .file
        ) {
            self.init(
                left: left,
                right: right,
                status: status,
                leftKind: kind,
                rightKind: kind
            )
        }

        init(
            left: String,
            right: String,
            status: DirectoryComparisonStatus,
            leftKind: DirectoryEntryKind,
            rightKind: DirectoryEntryKind
        ) {
            leftPath = left
            rightPath = right
            self.status = status
            self.leftKind = leftKind
            self.rightKind = rightKind
        }
    }

    private struct RowFixture {
        let result: DirectoryResult
        let revision: FolderComparisonResultRevision
    }

    private struct Fixture {
        let specs: [RowSpec]
        let roots: FolderComparisonRootPair
        let rows: [RowFixture]
        let folderSnapshot: FolderComparisonWorkflowSnapshot
        let expectedFolderSnapshot: FolderComparisonWorkflowSnapshotReference
        let navigationSnapshot: ComparedFileNavigationSnapshot
        let expectedNavigationSnapshot: Workflow.NavigationSnapshotReference
        let itemIdentities: [ComparedFileNavigationItemIdentity]
        let selectedItemIdentities: [ComparedFileNavigationItemIdentity]
        let navigationAuthorities: [ComparedFileNavigationRootAuthority]
        let authorityBindings: [Workflow.AuthorityBinding]
        let folderCapabilities: FolderComparisonWorkflowCapabilities
        let executorCapabilities: Workflow.ExecutorCapabilities
        let publicationTarget: Workflow.PublicationTarget
    }

    private struct ExecutionSession {
        let plan: Workflow.Plan
        let staging: Workflow.StagingReceipt
        let publicationLease: Workflow.ExecutionLease
    }

    private enum PublicationMutation: String, CaseIterable {
        case attemptIdentity
        case expectedIdentity
        case expectedRevision
        case successorIdentity
        case successorSameRevision
        case successorSkippedRevision
        case publicationCount
        case actionDigests
    }

    private enum NonPublicationMutation: String, CaseIterable {
        case expectedTarget
        case observedIdentity
        case observedLowerRevision
        case attemptCount
        case attemptIdentity
        case actionDigests
    }

    private enum ProbeError: Swift.Error {
        case custom
    }

    private final class CancellationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private let cancelOnCall: Int?
        private let error: Swift.Error
        private var callCount = 0

        init(cancelOnCall: Int?, error: Swift.Error = CancellationError()) {
            self.cancelOnCall = cancelOnCall
            self.error = error
        }

        var calls: Int {
            lock.withLock { callCount }
        }

        func check() throws {
            let shouldCancel = lock.withLock {
                callCount += 1
                return callCount == cancelOnCall
            }
            if shouldCancel { throw error }
        }
    }

    private final class CancellationBarrier: @unchecked Sendable {
        private let condition = NSCondition()
        private let triggerOnCall: Int
        private var callCount = 0
        private var isEntered = false
        private var isReleased = false

        init(triggerOnCall: Int) {
            self.triggerOnCall = triggerOnCall
        }

        func check() throws {
            condition.lock()
            callCount += 1
            if callCount == triggerOnCall {
                isEntered = true
                condition.broadcast()
                while !isReleased { condition.wait() }
            }
            condition.unlock()
            try Task.checkCancellation()
        }

        func waitUntilEntered() -> Bool {
            condition.lock()
            defer { condition.unlock() }
            let deadline = Date(timeIntervalSinceNow: 2)
            while !isEntered, condition.wait(until: deadline) {}
            return isEntered
        }

        func release() {
            condition.lock()
            isReleased = true
            condition.broadcast()
            condition.unlock()
        }
    }

    private func makeFixture(
        specs: [RowSpec],
        selectedIndices: [Int],
        filter: DirectoryResultFilter = DirectoryResultFilter(),
        openCapabilities: Set<ComparedFileNavigationOpenCapability> = [
            .identicalRegularFilePair, .differentRegularFilePair
        ],
        rootPrefix: String = "/selected-pair",
        physicalIdentityOffset: UInt64 = 0,
        securityScopedRoots: Bool = false
    ) throws -> Fixture {
        let roots = makeRoots(prefix: rootPrefix, securityScoped: securityScopedRoots)
        let rows = specs.enumerated().map {
            makeRow(
                $0.element,
                roots: roots,
                index: $0.offset,
                physicalIdentityOffset: physicalIdentityOffset
            )
        }
        let itemIdentities = specs.indices.map(itemIdentity)
        let navigationAuthorities = navigationAuthorities(roots: roots)
        let folder = folderSnapshot(roots: roots, rows: rows)
        let navigation = try navigationSnapshot(
            rows: rows.map(\.result),
            selectedIndices: selectedIndices,
            roots: roots,
            itemIdentities: itemIdentities,
            authorities: navigationAuthorities,
            openCapabilities: openCapabilities,
            filter: filter
        )
        let selected = selectedIndices.map { itemIdentities[$0] }
        let bindings = authorityBindings(roots: roots, navigationAuthorities: navigationAuthorities)
        return Fixture(
            specs: specs,
            roots: roots,
            rows: rows,
            folderSnapshot: folder,
            expectedFolderSnapshot: try FolderComparisonWorkflowPlanner.reference(to: folder),
            navigationSnapshot: navigation,
            expectedNavigationSnapshot: try Workflow.Planner.navigationReference(to: navigation),
            itemIdentities: itemIdentities,
            selectedItemIdentities: selected,
            navigationAuthorities: navigationAuthorities,
            authorityBindings: bindings,
            folderCapabilities: FolderComparisonWorkflowCapabilities(
                identity: uuid(700),
                revision: 3,
                features: [.openFilePair]
            ),
            executorCapabilities: Workflow.ExecutorCapabilities(
                identity: uuid(701),
                revision: 4,
                features: Set(Workflow.ExecutorFeature.allCases)
            ),
            publicationTarget: Workflow.PublicationTarget(identity: uuid(900), revision: 10)
        )
    }

    private func plan(
        _ fixture: Fixture,
        folderSnapshot: FolderComparisonWorkflowSnapshot? = nil,
        expectedFolderSnapshot: FolderComparisonWorkflowSnapshotReference? = nil,
        navigationSnapshot: ComparedFileNavigationSnapshot? = nil,
        expectedNavigationSnapshot: Workflow.NavigationSnapshotReference? = nil,
        selectedItemIdentities: [ComparedFileNavigationItemIdentity]? = nil,
        authorityBindings: [Workflow.AuthorityBinding]? = nil,
        folderCapabilities: FolderComparisonWorkflowCapabilities? = nil,
        executorCapabilities: Workflow.ExecutorCapabilities? = nil,
        publicationTarget: Workflow.PublicationTarget? = nil,
        folderValidationLimits: FolderComparisonWorkflowLimits = .default,
        limits: Workflow.Limits = .default
    ) throws -> Workflow.Plan {
        try Workflow.Planner.plan(
            request(
                fixture,
                folderSnapshot: folderSnapshot,
                expectedFolderSnapshot: expectedFolderSnapshot,
                navigationSnapshot: navigationSnapshot,
                expectedNavigationSnapshot: expectedNavigationSnapshot,
                selectedItemIdentities: selectedItemIdentities,
                authorityBindings: authorityBindings,
                folderCapabilities: folderCapabilities,
                executorCapabilities: executorCapabilities,
                publicationTarget: publicationTarget,
                folderValidationLimits: folderValidationLimits,
                limits: limits
            ),
            cancellationCheck: {}
        )
    }

    private func request(
        _ fixture: Fixture,
        folderSnapshot: FolderComparisonWorkflowSnapshot? = nil,
        expectedFolderSnapshot: FolderComparisonWorkflowSnapshotReference? = nil,
        navigationSnapshot: ComparedFileNavigationSnapshot? = nil,
        expectedNavigationSnapshot: Workflow.NavigationSnapshotReference? = nil,
        selectedItemIdentities: [ComparedFileNavigationItemIdentity]? = nil,
        authorityBindings: [Workflow.AuthorityBinding]? = nil,
        folderCapabilities: FolderComparisonWorkflowCapabilities? = nil,
        executorCapabilities: Workflow.ExecutorCapabilities? = nil,
        publicationTarget: Workflow.PublicationTarget? = nil,
        folderValidationLimits: FolderComparisonWorkflowLimits = .default,
        limits: Workflow.Limits = .default
    ) -> Workflow.Request {
        Workflow.Request(
            expectedFolderSnapshot: expectedFolderSnapshot ?? fixture.expectedFolderSnapshot,
            expectedNavigationSnapshot: expectedNavigationSnapshot
                ?? fixture.expectedNavigationSnapshot,
            folderSnapshot: folderSnapshot ?? fixture.folderSnapshot,
            navigationSnapshot: navigationSnapshot ?? fixture.navigationSnapshot,
            selectedItemIdentities: selectedItemIdentities ?? fixture.selectedItemIdentities,
            authorityBindings: authorityBindings ?? fixture.authorityBindings,
            folderCapabilities: folderCapabilities ?? fixture.folderCapabilities,
            executorCapabilities: executorCapabilities ?? fixture.executorCapabilities,
            publicationTarget: publicationTarget ?? fixture.publicationTarget,
            folderValidationLimits: folderValidationLimits,
            limits: limits
        )
    }

    private func executionValidation(
        _ fixture: Fixture,
        folderSnapshot: FolderComparisonWorkflowSnapshot? = nil,
        navigationSnapshot: ComparedFileNavigationSnapshot? = nil,
        authorityBindings: [Workflow.AuthorityBinding]? = nil,
        folderCapabilities: FolderComparisonWorkflowCapabilities? = nil,
        executorCapabilities: Workflow.ExecutorCapabilities? = nil,
        publicationTarget: Workflow.PublicationTarget? = nil
    ) -> Workflow.ExecutionValidation {
        Workflow.ExecutionValidation(
            folderSnapshot: folderSnapshot ?? fixture.folderSnapshot,
            navigationSnapshot: navigationSnapshot ?? fixture.navigationSnapshot,
            authorityBindings: authorityBindings ?? fixture.authorityBindings,
            folderCapabilities: folderCapabilities ?? fixture.folderCapabilities,
            executorCapabilities: executorCapabilities ?? fixture.executorCapabilities,
            publicationTarget: publicationTarget ?? fixture.publicationTarget
        )
    }

    private func makeExecutionSession(
        rowCount: Int = 1,
        rootPrefix: String = "/selected-pair"
    ) throws -> ExecutionSession {
        let fixture = try makeFixture(
            specs: (0..<rowCount).map { RowSpec("row-\($0).txt") },
            selectedIndices: Array(0..<rowCount),
            rootPrefix: rootPrefix
        )
        let planned = try plan(fixture)
        let validation = executionValidation(fixture)
        let staging = try makeStaging(plan: planned, validation: validation)
        let publicationLease = try planned.validateForPublication(
            validation,
            staging: staging,
            cancellationCheck: {}
        )
        return ExecutionSession(
            plan: planned,
            staging: staging,
            publicationLease: publicationLease
        )
    }

    private func makeStaging(
        plan: Workflow.Plan,
        validation: Workflow.ExecutionValidation
    ) throws -> Workflow.StagingReceipt {
        let lease = try plan.validateForExecution(validation, cancellationCheck: {})
        return try Workflow.ExecutionOutcomeFactory.staged(
            plan: plan,
            lease: lease,
            itemEvidence: stagedEvidence(plan)
        )
    }

    private func stagedEvidence(_ plan: Workflow.Plan) -> [Workflow.ItemExecutionEvidence] {
        plan.actions.map {
            Workflow.ItemExecutionEvidence(
                actionIndex: $0.index,
                actionSHA256: $0.actionSHA256,
                disposition: .stagedReadOnly
            )
        }
    }

    private func itemEvidence(
        _ plan: Workflow.Plan,
        index: Int,
        disposition: Workflow.ItemExecutionDisposition
    ) -> Workflow.ItemExecutionEvidence {
        Workflow.ItemExecutionEvidence(
            actionIndex: index,
            actionSHA256: plan.actions[index].actionSHA256,
            disposition: disposition
        )
    }

    private func publicationEvidence(
        plan: Workflow.Plan,
        lease: Workflow.ExecutionLease
    ) -> Workflow.PublicationEvidence {
        Workflow.PublicationEvidence(
            attemptIdentity: lease.attemptIdentity,
            expectedTarget: plan.publicationTarget,
            successorTarget: Workflow.PublicationTarget(
                identity: plan.publicationTarget.identity,
                revision: plan.publicationTarget.revision + 1
            ),
            publicationCount: 1,
            actionSHA256s: plan.actions.map(\.actionSHA256)
        )
    }

    private func zeroAttemptEvidence(
        plan: Workflow.Plan,
        observedTarget: Workflow.PublicationTarget? = nil
    ) -> Workflow.NonPublicationEvidence {
        Workflow.NonPublicationEvidence(
            expectedTarget: plan.publicationTarget,
            observedTargetAfterFailure: observedTarget ?? plan.publicationTarget,
            publicationAttemptCount: 0,
            actionSHA256s: plan.actions.map(\.actionSHA256)
        )
    }

    private func oneAttemptEvidence(
        plan: Workflow.Plan,
        lease: Workflow.ExecutionLease
    ) -> Workflow.NonPublicationEvidence {
        Workflow.NonPublicationEvidence(
            expectedTarget: plan.publicationTarget,
            observedTargetAfterFailure: plan.publicationTarget,
            publicationAttemptCount: 1,
            attemptIdentity: lease.attemptIdentity,
            actionSHA256s: plan.actions.map(\.actionSHA256)
        )
    }

    private func mutatedPublicationEvidence(
        _ evidence: Workflow.PublicationEvidence,
        mutation: PublicationMutation
    ) -> Workflow.PublicationEvidence {
        Workflow.PublicationEvidence(
            attemptIdentity: mutation == .attemptIdentity ? uuid(998) : evidence.attemptIdentity,
            expectedTarget: Workflow.PublicationTarget(
                identity: mutation == .expectedIdentity ? uuid(998) : evidence.expectedTarget.identity,
                revision: mutation == .expectedRevision
                    ? evidence.expectedTarget.revision + 1 : evidence.expectedTarget.revision
            ),
            successorTarget: Workflow.PublicationTarget(
                identity: mutation == .successorIdentity
                    ? uuid(998) : evidence.successorTarget.identity,
                revision: {
                    switch mutation {
                    case .successorSameRevision:
                        evidence.expectedTarget.revision
                    case .successorSkippedRevision:
                        evidence.successorTarget.revision + 1
                    default:
                        evidence.successorTarget.revision
                    }
                }()
            ),
            publicationCount: mutation == .publicationCount ? 2 : evidence.publicationCount,
            actionSHA256s: mutation == .actionDigests
                ? [Data(repeating: 0xFF, count: 32)] : evidence.actionSHA256s
        )
    }

    private func mutatedNonPublicationEvidence(
        _ evidence: Workflow.NonPublicationEvidence,
        mutation: NonPublicationMutation
    ) -> Workflow.NonPublicationEvidence {
        Workflow.NonPublicationEvidence(
            expectedTarget: mutation == .expectedTarget
                ? Workflow.PublicationTarget(
                    identity: evidence.expectedTarget.identity,
                    revision: evidence.expectedTarget.revision + 1
                ) : evidence.expectedTarget,
            observedTargetAfterFailure: Workflow.PublicationTarget(
                identity: mutation == .observedIdentity
                    ? uuid(997) : evidence.observedTargetAfterFailure.identity,
                revision: mutation == .observedLowerRevision
                    ? evidence.observedTargetAfterFailure.revision - 1
                    : evidence.observedTargetAfterFailure.revision
            ),
            publicationAttemptCount: mutation == .attemptCount
                ? 0 : evidence.publicationAttemptCount,
            attemptIdentity: mutation == .attemptIdentity ? uuid(997) : evidence.attemptIdentity,
            actionSHA256s: mutation == .actionDigests
                ? [Data(repeating: 0xFE, count: 32)] : evidence.actionSHA256s
        )
    }

    private func makeRoots(
        prefix: String = "/selected-pair",
        securityScoped: Bool = false
    ) -> FolderComparisonRootPair {
        FolderComparisonRootPair(
            left: root(side: .left, path: "\(prefix)-left", securityScoped: securityScoped),
            right: root(side: .right, path: "\(prefix)-right", securityScoped: securityScoped)
        )
    }

    private func root(
        side: FolderComparisonWorkflowSide,
        path: String,
        securityScoped: Bool = false
    ) -> FolderComparisonRoot {
        let isLeft = side == .left
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)
        let identity = FolderComparisonRootIdentity(
            canonicalURL: rootURL,
            deviceID: isLeft ? 1 : 2,
            fileID: isLeft ? 101 : 202,
            generation: isLeft ? 11 : 22
        )
        let revision = FolderComparisonRootRevision(
            identity: identity,
            linkCount: 2,
            permissions: 0o755,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            modificationTimeSeconds: 100,
            modificationTimeNanoseconds: 123,
            statusChangeTimeSeconds: 101,
            statusChangeTimeNanoseconds: 456,
            metadataSHA256: digest(isLeft ? 1 : 2)
        )
        return FolderComparisonRoot(
            requestedURL: rootURL,
            revision: revision,
            authority: FolderComparisonAccessAuthority(
                identity: uuid(isLeft ? 601 : 602),
                revision: isLeft ? 7 : 8,
                rootIdentity: identity,
                permissions: [.enumerate, .readContent],
                coverage: .directoryTree,
                acquisition: securityScoped
                    ? .securityScoped(
                        resourceURL: rootURL.appending(path: "scope", directoryHint: .isDirectory),
                        coverage: .directoryTree
                    )
                    : .ambient
            ),
            pathCaseSensitivity: .sensitive
        )
    }

    private func makeRow(
        _ spec: RowSpec,
        roots: FolderComparisonRootPair,
        index: Int,
        physicalIdentityOffset: UInt64 = 0
    ) -> RowFixture {
        let identical = spec.status == .identical
        let leftByteCount: UInt64 = 4
        let rightByteCount: UInt64 = identical ? 4 : 5
        let left = metadata(path: spec.leftPath, kind: spec.leftKind, byteCount: leftByteCount)
        let right = metadata(path: spec.rightPath, kind: spec.rightKind, byteCount: rightByteCount)
        let result = DirectoryResult(left: left, right: right, status: spec.status)
        let base = physicalIdentityOffset + UInt64(index * 4)
        return RowFixture(
            result: result,
            revision: FolderComparisonResultRevision(
                id: result.id,
                left: itemRevision(
                    root: roots.left,
                    path: spec.leftPath,
                    kind: spec.leftKind,
                    byteCount: leftByteCount,
                    physicalSeed: base + 1,
                    digestSeed: UInt8(truncatingIfNeeded: base + 10)
                ),
                right: itemRevision(
                    root: roots.right,
                    path: spec.rightPath,
                    kind: spec.rightKind,
                    byteCount: rightByteCount,
                    physicalSeed: base + 2,
                    digestSeed: identical
                        ? UInt8(truncatingIfNeeded: base + 10)
                        : UInt8(truncatingIfNeeded: base + 11)
                )
            )
        )
    }

    private func metadata(
        path: String,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64
    ) -> DirectoryEntryMetadata {
        DirectoryEntryMetadata(
            relativePath: path,
            kind: kind,
            byteCount: byteCount,
            modificationDate: Date(timeIntervalSince1970: 10),
            isHidden: false
        )
    }

    private func itemRevision(
        root: FolderComparisonRoot,
        path: String,
        kind: DirectoryEntryKind,
        byteCount: UInt64,
        physicalSeed: UInt64,
        digestSeed: UInt8
    ) -> FolderComparisonItemRevision {
        FolderComparisonItemRevision(
            identity: FolderComparisonItemIdentity(
                rootIdentity: root.revision.identity,
                relativePath: path,
                deviceID: physicalSeed + 100,
                fileID: physicalSeed + 1_000,
                generation: UInt32(physicalSeed + 1)
            ),
            kind: kind,
            byteCount: byteCount,
            linkCount: 1,
            permissions: 0o644,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            modificationTimeSeconds: 10,
            modificationTimeNanoseconds: 0,
            statusChangeTimeSeconds: 11,
            statusChangeTimeNanoseconds: 0,
            metadataSHA256: digest(digestSeed),
            contentSHA256: kind == .file ? digest(digestSeed) : nil
        )
    }

    private func folderSnapshot(
        roots: FolderComparisonRootPair,
        rows: [RowFixture],
        generation: UInt64 = 5,
        ownerRevision: UInt64 = 6
    ) -> FolderComparisonWorkflowSnapshot {
        FolderComparisonWorkflowSnapshot(
            identity: FolderComparisonWorkflowSnapshotIdentity(rawValue: uuid(500)),
            generation: generation,
            owner: FolderComparisonWorkflowSnapshotOwner(
                identity: uuid(501),
                revision: ownerRevision
            ),
            roots: roots,
            scanIntent: FolderComparisonScanIntent(),
            comparisonSettings: FolderComparisonSettings(method: .metadataOnly),
            isComplete: true,
            results: rows.map(\.result),
            resultRevisions: rows.map(\.revision)
        )
    }

    private func navigationSnapshot(
        rows: [DirectoryResult],
        selectedIndices: [Int],
        roots: FolderComparisonRootPair,
        itemIdentities: [ComparedFileNavigationItemIdentity],
        authorities: [ComparedFileNavigationRootAuthority],
        openCapabilities: Set<ComparedFileNavigationOpenCapability> = [
            .identicalRegularFilePair, .differentRegularFilePair
        ],
        filter: DirectoryResultFilter = DirectoryResultFilter(),
        limits: ComparedFileNavigationLimits = .default,
        revision: UInt64 = 12,
        generation: UInt64 = 13
    ) throws -> ComparedFileNavigationSnapshot {
        let results = DirectoryResults(
            leftRoot: roots.left.requestedURL,
            rightRoot: roots.right.requestedURL,
            results: rows,
            filter: filter,
            sortDescriptors: [DirectoryResultSortDescriptor(key: .path)],
            selectedIDs: Set(selectedIndices.map { rows[$0].id })
        )
        return try ComparedFileNavigationSnapshot(
            identity: ComparedFileFolderResultsIdentity(rawValue: uuid(510)),
            revision: ComparedFileFolderResultsRevision(rawValue: revision),
            generation: ComparedFileFolderResultsGeneration(rawValue: generation),
            results: results,
            itemBindings: zip(itemIdentities, rows).map {
                ComparedFileNavigationItemBinding(identity: $0.0, resultID: $0.1.id)
            },
            authorities: authorities,
            openCapabilities: openCapabilities,
            limits: limits
        )
    }

    private func navigationAuthorities(
        roots: FolderComparisonRootPair
    ) -> [ComparedFileNavigationRootAuthority] {
        [
            ComparedFileNavigationRootAuthority(
                identity: navigationAuthorityIdentity(0),
                side: .left,
                rootURL: roots.left.requestedURL,
                capabilities: [.readRegularFile]
            ),
            ComparedFileNavigationRootAuthority(
                identity: navigationAuthorityIdentity(1),
                side: .right,
                rootURL: roots.right.requestedURL,
                capabilities: [.readRegularFile]
            )
        ]
    }

    private func authorityBindings(
        roots: FolderComparisonRootPair,
        navigationAuthorities: [ComparedFileNavigationRootAuthority]
    ) -> [Workflow.AuthorityBinding] {
        [
            Workflow.AuthorityBinding(
                side: .left,
                folderAuthorityIdentity: roots.left.authority.identity,
                folderAuthorityRevision: roots.left.authority.revision,
                navigationAuthorityIdentity: navigationAuthorities[0].identity
            ),
            Workflow.AuthorityBinding(
                side: .right,
                folderAuthorityIdentity: roots.right.authority.identity,
                folderAuthorityRevision: roots.right.authority.revision,
                navigationAuthorityIdentity: navigationAuthorities[1].identity
            )
        ]
    }

    private func assertAction(
        _ action: Workflow.Action,
        index: Int,
        visibleOrdinal: Int,
        spec: RowSpec,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(action.index, index, file: file, line: line)
        XCTAssertEqual(action.visibleOrdinal, visibleOrdinal, file: file, line: line)
        XCTAssertEqual(action.intent, .readOnlyTextComparison, file: file, line: line)
        XCTAssertEqual(action.comparisonMode, .text, file: file, line: line)
        XCTAssertEqual(action.left.relativePath, spec.leftPath, file: file, line: line)
        XCTAssertEqual(action.right.relativePath, spec.rightPath, file: file, line: line)
        XCTAssertTrue(action.left.readOnly, file: file, line: line)
        XCTAssertTrue(action.right.readOnly, file: file, line: line)
    }

    private func assertError<Result>(
        _ code: Workflow.ErrorCode,
        _ context: String = "",
        itemIdentity: ComparedFileNavigationItemIdentity? = nil,
        side: Workflow.Side? = nil,
        limit: Workflow.Limit? = nil,
        maximum: UInt64? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Result
    ) {
        XCTAssertThrowsError(try operation(), context, file: file, line: line) { error in
            guard let workflowError = error as? Workflow.Error else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            XCTAssertEqual(workflowError.code, code, context, file: file, line: line)
            XCTAssertEqual(
                workflowError.itemIdentity,
                itemIdentity,
                context,
                file: file,
                line: line
            )
            XCTAssertEqual(workflowError.side, side, context, file: file, line: line)
            XCTAssertEqual(workflowError.limit, limit, context, file: file, line: line)
            XCTAssertEqual(workflowError.maximum, maximum, context, file: file, line: line)
        }
    }

    private func assertRedacted<T>(
        _ value: T,
        secrets: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var dumpOutput = ""
        dump(value, to: &dumpOutput)
        let outputs = [
            ("description", String(describing: value)),
            ("reflection", String(reflecting: value)),
            ("dump", dumpOutput)
        ]
        for (representation, output) in outputs {
            XCTAssertTrue(
                output.contains("<redacted>"),
                "Missing redaction marker in \(representation)",
                file: file,
                line: line
            )
            for secret in secrets {
                XCTAssertFalse(
                    output.contains(secret),
                    "Sensitive value exposed in \(representation)",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertOutcomeReceiptRedacted(
        _ outcome: Workflow.ExecutionOutcome,
        secrets: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch outcome {
        case .completed(let receipt):
            assertRedacted(receipt, secrets: secrets, file: file, line: line)
        case .notPublished(let receipt):
            assertRedacted(receipt, secrets: secrets, file: file, line: line)
        case .publicationUncertain(let receipt):
            assertRedacted(receipt, secrets: secrets, file: file, line: line)
        }
    }

    private func secretFragments(_ fixture: Fixture) -> [String] {
        [
            "private/left-secret.txt",
            "private/right-secret.txt",
            "selected-secret-left",
            "selected-secret-right"
        ]
    }

    private func limits(
        maximumSnapshotItems: Int = Workflow.Limits.default.maximumSnapshotItems,
        maximumSelectedItems: Int = Workflow.Limits.default.maximumSelectedItems,
        maximumStringUTF8Bytes: Int = Workflow.Limits.default.maximumStringUTF8Bytes,
        maximumTotalStringUTF8Bytes: Int = Workflow.Limits.default.maximumTotalStringUTF8Bytes,
        maximumWorkUnits: UInt64 = Workflow.Limits.default.maximumWorkUnits,
        cancellationCheckInterval: UInt64 = Workflow.Limits.default.cancellationCheckInterval
    ) -> Workflow.Limits {
        Workflow.Limits(
            maximumSnapshotItems: maximumSnapshotItems,
            maximumSelectedItems: maximumSelectedItems,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func navigationLimits(
        maximumItemCount: Int,
        maximumSortDescriptorCount: Int = ComparedFileNavigationLimits.default.maximumSortDescriptorCount,
        maximumStringUTF8Bytes: Int = ComparedFileNavigationLimits.default.maximumStringUTF8Bytes,
        maximumTotalStringUTF8Bytes: Int = ComparedFileNavigationLimits.default.maximumTotalStringUTF8Bytes,
        maximumWorkUnits: Int = ComparedFileNavigationLimits.default.maximumWorkUnits,
        cancellationCheckInterval: Int = ComparedFileNavigationLimits.default.cancellationCheckInterval
    ) -> ComparedFileNavigationLimits {
        ComparedFileNavigationLimits(
            maximumItemCount: maximumItemCount,
            maximumSortDescriptorCount: maximumSortDescriptorCount,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func folderLimits(
        maximumResultItems: Int = FolderComparisonWorkflowLimits.default.maximumResultItems,
        maximumSelectedItems: Int = FolderComparisonWorkflowLimits.default.maximumSelectedItems,
        maximumOperationActions: Int = FolderComparisonWorkflowLimits.default.maximumOperationActions,
        maximumPresentationRows: Int = FolderComparisonWorkflowLimits.default.maximumPresentationRows,
        maximumColumns: Int = FolderComparisonWorkflowLimits.default.maximumColumns,
        maximumSortDescriptors: Int = FolderComparisonWorkflowLimits.default.maximumSortDescriptors,
        maximumFilterRules: Int = FolderComparisonWorkflowLimits.default.maximumFilterRules,
        maximumStringUTF8Bytes: Int = FolderComparisonWorkflowLimits.default.maximumStringUTF8Bytes,
        maximumTotalStringUTF8Bytes: Int = FolderComparisonWorkflowLimits.default.maximumTotalStringUTF8Bytes,
        maximumMetadataDigestBytes: Int = FolderComparisonWorkflowLimits.default.maximumMetadataDigestBytes,
        maximumWorkUnits: UInt64 = FolderComparisonWorkflowLimits.default.maximumWorkUnits,
        cancellationCheckInterval: Int = FolderComparisonWorkflowLimits.default.cancellationCheckInterval
    ) -> FolderComparisonWorkflowLimits {
        FolderComparisonWorkflowLimits(
            maximumResultItems: maximumResultItems,
            maximumSelectedItems: maximumSelectedItems,
            maximumOperationActions: maximumOperationActions,
            maximumPresentationRows: maximumPresentationRows,
            maximumColumns: maximumColumns,
            maximumSortDescriptors: maximumSortDescriptors,
            maximumFilterRules: maximumFilterRules,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumMetadataDigestBytes: maximumMetadataDigestBytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func digest(_ seed: UInt8) -> [UInt8] {
        Array(repeating: seed, count: 32)
    }

    private func itemIdentity(_ index: Int) -> ComparedFileNavigationItemIdentity {
        ComparedFileNavigationItemIdentity(rawValue: uuid(520 + index))
    }

    private func navigationAuthorityIdentity(
        _ index: Int
    ) -> ComparedFileNavigationAuthorityIdentity {
        ComparedFileNavigationAuthorityIdentity(rawValue: uuid(530 + index))
    }

    private func uuid(_ value: Int) -> UUID {
        let unsigned = UInt64(value)
        return UUID(
            uuid: (
                UInt8(truncatingIfNeeded: unsigned >> 56),
                UInt8(truncatingIfNeeded: unsigned >> 48),
                UInt8(truncatingIfNeeded: unsigned >> 40),
                UInt8(truncatingIfNeeded: unsigned >> 32),
                UInt8(truncatingIfNeeded: unsigned >> 24),
                UInt8(truncatingIfNeeded: unsigned >> 16),
                UInt8(truncatingIfNeeded: unsigned >> 8),
                UInt8(truncatingIfNeeded: unsigned),
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                1
            )
        )
    }
}

private func captureErrorCode<Result>(
    _ operation: () throws -> Result
) -> SelectedFilePairOpenWorkflow.ErrorCode? {
    do {
        _ = try operation()
        return nil
    } catch let error as SelectedFilePairOpenWorkflow.Error {
        return error.code
    } catch {
        return nil
    }
}
