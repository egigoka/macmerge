import Darwin
import Foundation
import MacMergeCore
import XCTest

final class OutputPaneWorkflowTests: XCTestCase {
    typealias Workflow = OutputPaneWorkflow
    typealias EntryID = OutputPaneWorkflow.EntryID

    func testVisibilityDefaultsRestoreAndRejectUnsupportedSchema() throws {
        let snapshot = try makeSnapshot()

        XCTAssertEqual(snapshot.visibilityPreference, .default)
        XCTAssertEqual(snapshot.visibilityPreference.visibility, .hidden)
        XCTAssertEqual(snapshot.visibilityPreference.persistence, .sessionOnly)
        XCTAssertFalse(snapshot.isVisible)

        let persisted = Workflow.PersistedVisibilityPreference(visibility: .visible)
        let restored = try Workflow.VisibilityPreference(restoring: persisted)
        XCTAssertEqual(restored.visibility, .visible)
        XCTAssertEqual(restored.persistence, .persisted)
        XCTAssertEqual(persisted.schemaVersion, Workflow.PersistedVisibilityPreference.currentSchemaVersion)

        let unsupported = Workflow.PersistedVisibilityPreference(
            schemaVersion: Workflow.PersistedVisibilityPreference.currentSchemaVersion + 1,
            visibility: .hidden
        )
        assertWorkflowError(.unsupportedPreferenceSchemaVersion(unsupported.schemaVersion)) {
            try Workflow.VisibilityPreference(restoring: unsupported)
        }
    }

    func testVisibilityAndPersistencePlansPublishEffectsBeforeState() throws {
        let snapshot = try makeSnapshot()
        let toggleState = try Workflow.commandState(for: .toggleVisibility, in: snapshot)
        XCTAssertEqual(toggleState.checkedState, .off)
        XCTAssertTrue(toggleState.isEnabled)

        let toggled = try Workflow.plan(.toggleVisibility, in: snapshot)
        let visible = try XCTUnwrap(toggled.successor)
        XCTAssertEqual(
            visible.visibilityPreference,
            Workflow.VisibilityPreference(visibility: .visible, persistence: .sessionOnly)
        )
        XCTAssertEqual(toggled.requiredEffects, [.replaceState(visible.reference)])
        XCTAssertEqual(toggled.receipt.result, .visibility(visible.visibilityPreference))

        let persist = try Workflow.plan(.setVisibilityPersistence(.persisted), in: snapshot)
        let persisted = try XCTUnwrap(persist.successor)
        let hiddenPreference = Workflow.PersistedVisibilityPreference(visibility: .hidden)
        XCTAssertEqual(
            persist.requiredEffects,
            [.storeVisibilityPreference(hiddenPreference), .replaceState(persisted.reference)]
        )
        XCTAssertEqual(persisted.visibilityPreference.persistence, .persisted)

        let showPersisted = try Workflow.plan(.setVisibility(.visible), in: persisted)
        let shown = try XCTUnwrap(showPersisted.successor)
        XCTAssertEqual(
            showPersisted.requiredEffects,
            [
                .storeVisibilityPreference(
                    Workflow.PersistedVisibilityPreference(visibility: .visible)
                ),
                .replaceState(shown.reference)
            ]
        )

        let stopPersisting = try Workflow.plan(
            .setVisibilityPersistence(.sessionOnly),
            in: shown
        )
        let sessionOnly = try XCTUnwrap(stopPersisting.successor)
        XCTAssertEqual(
            stopPersisting.requiredEffects,
            [.removeStoredVisibilityPreference, .replaceState(sessionOnly.reference)]
        )
    }

    func testFilterMatchesSeverityAndPOSIXCaseRulesAndPrunesSelection() throws {
        let (log, ids) = try makeLog(
            [
                message(.info, "Alpha"),
                message(.error, "alpha failure"),
                message(.info, "ALPHA")
            ],
            selectedIndices: [0, 1]
        )
        let snapshot = try makeSnapshot(log: log)
        let filter = Workflow.Filter(severities: .info, text: "alpha", caseSensitive: false)
        let plan = try Workflow.plan(.filter(.set(filter)), in: snapshot)
        let successor = try XCTUnwrap(plan.successor)

        XCTAssertEqual(successor.visibleEntries.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(successor.log.selectedIDs, [ids[0]])
        guard case .filtered(let receipt) = plan.receipt.result else {
            return XCTFail("Expected filter receipt")
        }
        XCTAssertEqual(receipt.filter, filter)
        XCTAssertEqual(receipt.visibleMessageCount, 2)
        XCTAssertEqual(receipt.deselectedMessageCount, 1)

        let caseSensitive = Workflow.Filter(
            severities: .all,
            text: "Alpha",
            caseSensitive: true
        )
        let casePlan = try Workflow.plan(.filter(.set(caseSensitive)), in: snapshot)
        XCTAssertEqual(casePlan.successor?.visibleEntries.map(\.id), [ids[0]])

        let clearPlan = try Workflow.plan(.filter(.clear), in: successor)
        XCTAssertEqual(clearPlan.successor?.filter, .all)
        XCTAssertEqual(clearPlan.successor?.visibleEntries.map(\.id), ids)
    }

    func testSelectionIntentsProduceSortedDeterministicReceipts() throws {
        let (log, ids) = try makeLog([
            message(.info, "one"), message(.warning, "two"), message(.error, "three")
        ])
        var snapshot = try makeSnapshot(log: log)

        let replace = try Workflow.plan(.select(.replace(ids[1])), in: snapshot)
        snapshot = try XCTUnwrap(replace.successor)
        XCTAssertEqual(selectionIDs(in: replace), [ids[1]])

        let extend = try Workflow.plan(.select(.extend(ids[0])), in: snapshot)
        snapshot = try XCTUnwrap(extend.successor)
        XCTAssertEqual(selectionIDs(in: extend), [ids[0], ids[1]])

        let toggle = try Workflow.plan(.select(.toggle(ids[1])), in: snapshot)
        snapshot = try XCTUnwrap(toggle.successor)
        XCTAssertEqual(selectionIDs(in: toggle), [ids[0]])

        let set = try Workflow.plan(.select(.set([ids[2], ids[0]])), in: snapshot)
        snapshot = try XCTUnwrap(set.successor)
        XCTAssertEqual(selectionIDs(in: set), [ids[0], ids[2]])

        let clear = try Workflow.plan(.select(.clear), in: snapshot)
        XCTAssertEqual(selectionIDs(in: clear), [])
        XCTAssertTrue(try XCTUnwrap(clear.successor).log.selectedIDs.isEmpty)
    }

    func testNoOpExtendAndSetAreDisabledWithoutPlans() throws {
        let (log, ids) = try makeLog(
            [message(.info, "one"), message(.info, "two")],
            selectedIndices: [0, 1]
        )
        let snapshot = try makeSnapshot(log: log)

        try assertDisabled(
            .select(.extend(ids[0])),
            in: snapshot,
            reason: .noStateChange
        )
        try assertDisabled(
            .select(.set([ids[1], ids[0]])),
            in: snapshot,
            reason: .noStateChange
        )
    }

    func testSelectionSetPrioritizesSortedUnknownThenSortedHiddenID() throws {
        let (log, ids) = try makeLog([
            message(.info, "visible"),
            message(.error, "hidden-low"),
            message(.error, "hidden-high")
        ])
        let snapshot = try makeSnapshot(
            log: log,
            filter: Workflow.Filter(severities: .info)
        )
        let unknownLow = EntryID(rawValue: 90)
        let unknownHigh = EntryID(rawValue: 99)

        for requested in [
            set(insertionOrder: [ids[2], unknownHigh, ids[1], unknownLow]),
            set(insertionOrder: [unknownLow, ids[1], unknownHigh, ids[2]])
        ] {
            try assertDisabled(
                .select(.set(requested)),
                in: snapshot,
                reason: .unknownMessage(unknownLow)
            )
        }

        for requested in [
            set(insertionOrder: [ids[2], ids[1]]),
            set(insertionOrder: [ids[1], ids[2]])
        ] {
            try assertDisabled(
                .select(.set(requested)),
                in: snapshot,
                reason: .messageFiltered(ids[1])
            )
        }
    }

    func testUnknownSelectionAtStaleRevisionReportsRevisionExhaustionFirst() throws {
        let unknown = EntryID(rawValue: 999)
        let stale = try makeSnapshot(revision: .max)

        try assertDisabled(
            .select(.replace(unknown)),
            in: stale,
            reason: .revisionExhausted
        )
        try assertDisabled(
            .select(.set([unknown])),
            in: stale,
            reason: .revisionExhausted
        )
    }

    func testHighCardinalitySelectionSetSucceedsInSortedOrder() throws {
        let count = 4_096
        let logLimits = OutputPaneLog.Limits(
            maximumEntryCount: count,
            maximumUTF8Bytes: count * 8
        )
        let messages = (0..<count).map { message(.info, "m\($0)") }
        let (log, ids) = try makeLog(messages, logLimits: logLimits)
        let bounded = limits(
            maximumRetainedItemCount: count,
            maximumSelectedItemCount: count,
            maximumAppendUTF8Bytes: count * 8,
            maximumRetainedUTF8Bytes: count * 8
        )
        let snapshot = try makeSnapshot(log: log, limits: bounded)
        let requested = set(insertionOrder: ids.reversed())
        let plan = try Workflow.plan(.select(.set(requested)), in: snapshot)

        XCTAssertEqual(selectionIDs(in: plan), ids)
        XCTAssertEqual(plan.successor?.log.selectedIDs, requested)
    }

    func testHighCardinalityRetainedAndVisibleMessageScansReachTerminalIDs() throws {
        let count = 4_096
        let logLimits = OutputPaneLog.Limits(
            maximumEntryCount: count,
            maximumUTF8Bytes: count * 16
        )
        let messages = (0..<count).map { index in
            message(index.isMultiple(of: 2) ? .info : .error, "entry-\(index)")
        }
        let (log, ids) = try makeLog(messages, logLimits: logLimits)
        let bounded = limits(
            maximumRetainedItemCount: count,
            maximumSelectedItemCount: count,
            maximumAppendUTF8Bytes: count * 16,
            maximumRetainedUTF8Bytes: count * 16
        )
        let snapshot = try makeSnapshot(
            log: log,
            filter: Workflow.Filter(severities: .info),
            limits: bounded
        )
        let lastVisibleID = ids[count - 2]
        let lastHiddenID = ids[count - 1]

        let copy = try Workflow.plan(
            .copy(Workflow.CopyIntent(scope: .message(lastVisibleID))),
            in: snapshot
        )
        XCTAssertEqual(try copyPayload(from: copy).summary.messageIDs, [lastVisibleID])
        try assertDisabled(
            .copy(Workflow.CopyIntent(scope: .message(lastHiddenID))),
            in: snapshot,
            reason: .messageFiltered(lastHiddenID)
        )
    }

    func testSelectAllTargetsVisibleMessagesAndClearAllRemovesEverything() throws {
        let (log, ids) = try makeLog([
            message(.info, "visible one"),
            message(.error, "hidden"),
            message(.info, "visible two")
        ])
        let filter = Workflow.Filter(severities: .info)
        let snapshot = try makeSnapshot(
            log: log,
            filter: filter,
            securitySensitiveMessageIDs: [ids[0]]
        )

        let selectAll = try Workflow.plan(.selectAll, in: snapshot)
        let selected = try XCTUnwrap(selectAll.successor)
        XCTAssertEqual(selectionIDs(in: selectAll), [ids[0], ids[2]])
        XCTAssertEqual(selected.log.selectedIDs, [ids[0], ids[2]])

        let clear = try Workflow.plan(.clearAll, in: selected)
        let cleared = try XCTUnwrap(clear.successor)
        XCTAssertEqual(
            clear.receipt.result,
            .clearedAll(messageCount: 3, utf8ByteCount: log.retainedUTF8ByteCount)
        )
        XCTAssertTrue(cleared.log.entries.isEmpty)
        XCTAssertTrue(cleared.log.selectedIDs.isEmpty)
        XCTAssertTrue(cleared.securitySensitiveMessageIDs.isEmpty)
        XCTAssertTrue(cleared.visibleEntries.isEmpty)
    }

    func testEveryCopyScopeAndDisclosureModeHasExactDistinctIDsTextAndCounts() throws {
        let (log, ids) = try makeLog(
            [
                message(.info, "public"),
                message(.info, "sensitive"),
                message(.info, "selected"),
                message(.error, "hidden")
            ],
            selectedIndices: [1, 2]
        )
        let redacted = try makeSnapshot(
            log: log,
            filter: Workflow.Filter(severities: .info),
            sensitiveCopyPolicy: .redact,
            securitySensitiveMessageIDs: [ids[1]]
        )
        let unredacted = try makeSnapshot(
            log: log,
            filter: Workflow.Filter(severities: .info),
            sensitiveCopyPolicy: .requireExplicitAuthorization,
            securitySensitiveMessageIDs: [ids[1]]
        )
        XCTAssertEqual(redacted.log.selectedIDs, [ids[1], ids[2]])
        XCTAssertEqual(redacted.visibleEntries.map(\.id), [ids[0], ids[1], ids[2]])
        XCTAssertNotEqual(redacted.log.selectedIDs, Set(redacted.visibleEntries.map(\.id)))

        let cases:
            [(
                snapshot: Workflow.Snapshot,
                intent: Workflow.CopyIntent,
                scope: Workflow.CopyScope,
                text: String,
                messageIDs: [EntryID],
                redactedCount: Int,
                disclosedCount: Int
            )] = [
                (
                    redacted,
                    Workflow.CopyIntent(
                        scope: .selection,
                        authorization: .explicitUserApproval
                    ),
                    .selection,
                    "\(Workflow.redactionMarker)\nselected",
                    [ids[1], ids[2]],
                    1,
                    0
                ),
                (
                    redacted,
                    Workflow.CopyIntent(
                        scope: .message(ids[1]),
                        authorization: .explicitUserApproval
                    ),
                    .message(ids[1]),
                    Workflow.redactionMarker,
                    [ids[1]],
                    1,
                    0
                ),
                (
                    redacted,
                    Workflow.CopyIntent(
                        scope: .visibleMessages,
                        authorization: .explicitUserApproval
                    ),
                    .visibleMessages,
                    "public\n\(Workflow.redactionMarker)\nselected",
                    [ids[0], ids[1], ids[2]],
                    1,
                    0
                ),
                (
                    unredacted,
                    Workflow.CopyIntent(
                        scope: .selection,
                        authorization: .explicitUserApproval
                    ),
                    .selection,
                    "sensitive\nselected",
                    [ids[1], ids[2]],
                    0,
                    1
                ),
                (
                    unredacted,
                    Workflow.CopyIntent(
                        scope: .message(ids[1]),
                        authorization: .explicitUserApproval
                    ),
                    .message(ids[1]),
                    "sensitive",
                    [ids[1]],
                    0,
                    1
                ),
                (
                    unredacted,
                    Workflow.CopyIntent(
                        scope: .visibleMessages,
                        authorization: .explicitUserApproval
                    ),
                    .visibleMessages,
                    "public\nsensitive\nselected",
                    [ids[0], ids[1], ids[2]],
                    0,
                    1
                )
            ]

        for testCase in cases {
            let plan = try Workflow.plan(.copy(testCase.intent), in: testCase.snapshot)
            let payload = try copyPayload(from: plan)
            XCTAssertEqual(payload.text, testCase.text)
            XCTAssertEqual(payload.summary.scope, testCase.scope)
            XCTAssertEqual(payload.summary.messageIDs, testCase.messageIDs)
            XCTAssertEqual(payload.summary.utf8ByteCount, testCase.text.utf8.count)
            XCTAssertEqual(payload.summary.redactedMessageCount, testCase.redactedCount)
            XCTAssertEqual(
                payload.summary.disclosedSensitiveMessageCount,
                testCase.disclosedCount
            )
            XCTAssertEqual(plan.receipt.result, .copied(payload.summary))
        }
    }

    func testRedactedCopyNeverDisclosesSensitiveText() throws {
        let secret = "api-token=top-secret"
        let (log, ids) = try makeLog(
            [message(.info, "public"), message(.error, secret)],
            selectedIndices: [0, 1]
        )
        let snapshot = try makeSnapshot(
            log: log,
            sensitiveCopyPolicy: .redact,
            securitySensitiveMessageIDs: [ids[1]]
        )
        let plan = try Workflow.plan(.copy(Workflow.CopyIntent()), in: snapshot)
        let payload = try copyPayload(from: plan)

        XCTAssertEqual(payload.text, "public\n\(Workflow.redactionMarker)")
        XCTAssertFalse(payload.text.contains(secret))
        XCTAssertEqual(payload.summary.redactedMessageCount, 1)
        XCTAssertEqual(payload.summary.disclosedSensitiveMessageCount, 0)
        XCTAssertEqual(payload.summary.utf8ByteCount, payload.text.utf8.count)
        XCTAssertFalse(String(describing: payload).contains(secret))
        XCTAssertFalse(String(describing: plan).contains(secret))
    }

    func testPublicSecretBearingWrappersRedactDescriptionDebugReflectionAndDump() throws {
        let secret = "secret-reflection-canary"
        let (log, ids) = try makeLog([message(.error, secret)], selectedIndices: [0])
        let snapshot = try makeSnapshot(
            log: log,
            securitySensitiveMessageIDs: [ids[0]]
        )
        let append = Workflow.AppendIntent(
            severity: .error,
            timestamp: timestamp,
            text: secret,
            sensitivity: .securitySensitive
        )
        let plan = try Workflow.plan(.copy(Workflow.CopyIntent()), in: snapshot)
        let payload = try copyPayload(from: plan)
        let wrappers: [Any] = [
            snapshot,
            snapshot.cas,
            append,
            Workflow.Intent.append(append),
            payload,
            plan.operation,
            plan
        ]

        for wrapper in wrappers {
            let renderings = [
                String(describing: wrapper),
                String(reflecting: wrapper),
                mirrorRendering(wrapper),
                dumpRendering(wrapper)
            ]
            for rendering in renderings {
                XCTAssertFalse(rendering.contains(secret), rendering)
                XCTAssertTrue(rendering.contains("<redacted>"), rendering)
            }
        }
    }

    func testSensitiveCopyDenyAndExplicitAuthorizationAreFailClosed() throws {
        let secret = "credential"
        let (log, ids) = try makeLog([message(.error, secret)], selectedIndices: [0])
        let deny = try makeSnapshot(
            log: log,
            sensitiveCopyPolicy: .deny,
            securitySensitiveMessageIDs: [ids[0]]
        )
        try assertDisabled(
            .copy(
                Workflow.CopyIntent(
                    authorization: .explicitUserApproval
                )
            ),
            in: deny,
            reason: .securitySensitiveCopyDenied(messageCount: 1)
        )

        let authorizationRequired = try makeSnapshot(
            log: log,
            sensitiveCopyPolicy: .requireExplicitAuthorization,
            securitySensitiveMessageIDs: [ids[0]]
        )
        try assertDisabled(
            .copy(Workflow.CopyIntent()),
            in: authorizationRequired,
            reason: .securitySensitiveCopyRequiresAuthorization(messageCount: 1)
        )

        let approved = try Workflow.plan(
            .copy(
                Workflow.CopyIntent(
                    authorization: .explicitUserApproval
                )
            ),
            in: authorizationRequired
        )
        let payload = try copyPayload(from: approved)
        XCTAssertEqual(payload.text, secret)
        XCTAssertEqual(payload.summary.redactedMessageCount, 0)
        XCTAssertEqual(payload.summary.disclosedSensitiveMessageCount, 1)

        let redact = try makeSnapshot(
            log: log,
            sensitiveCopyPolicy: .redact,
            securitySensitiveMessageIDs: [ids[0]]
        )
        let explicitlyApprovedRedaction = try Workflow.plan(
            .copy(
                Workflow.CopyIntent(
                    authorization: .explicitUserApproval
                )
            ),
            in: redact
        )
        let redactedPayload = try copyPayload(from: explicitlyApprovedRedaction)
        XCTAssertEqual(redactedPayload.text, Workflow.redactionMarker)
        XCTAssertEqual(redactedPayload.summary.redactedMessageCount, 1)
        XCTAssertEqual(redactedPayload.summary.disclosedSensitiveMessageCount, 0)
    }

    func testCopyPlanCommitsSuccessorBeforeExactClipboardPayload() throws {
        let (log, _) = try makeLog([message(.info, "copy")], selectedIndices: [0])
        let snapshot = try makeSnapshot(log: log)
        let plan = try Workflow.plan(.copy(Workflow.CopyIntent()), in: snapshot)
        let successor = try XCTUnwrap(plan.successor)
        let payload = try copyPayload(from: plan)

        XCTAssertEqual(successor.identity, snapshot.identity)
        XCTAssertEqual(successor.revision, snapshot.revision + 1)
        XCTAssertEqual(
            plan.requiredEffects,
            [.replaceState(successor.reference), .replaceClipboard(payload.summary)]
        )
        XCTAssertEqual(plan.receipt.successorSnapshot, successor.reference)
        XCTAssertEqual(plan.receipt.result, .copied(payload.summary))
    }

    func testEmptyLogDisablesCopySelectAllClearAndClearSelection() throws {
        let snapshot = try makeSnapshot()

        try assertDisabled(
            .copy(Workflow.CopyIntent()),
            in: snapshot,
            reason: .noSelection
        )
        try assertDisabled(.selectAll, in: snapshot, reason: .noMessages)
        try assertDisabled(.clearAll, in: snapshot, reason: .noMessages)
        try assertDisabled(.select(.clear), in: snapshot, reason: .noSelection)
    }

    func testFilteredAndUnknownIDsDisableSelectionAndMessageCopy() throws {
        let (log, ids) = try makeLog([
            message(.info, "visible"), message(.error, "filtered")
        ])
        let snapshot = try makeSnapshot(
            log: log,
            filter: Workflow.Filter(severities: .info)
        )
        let unknown = EntryID(rawValue: 999)

        try assertDisabled(
            .select(.replace(unknown)),
            in: snapshot,
            reason: .unknownMessage(unknown)
        )
        try assertDisabled(
            .copy(Workflow.CopyIntent(scope: .message(unknown))),
            in: snapshot,
            reason: .unknownMessage(unknown)
        )
        try assertDisabled(
            .select(.replace(ids[1])),
            in: snapshot,
            reason: .messageFiltered(ids[1])
        )
        try assertDisabled(
            .copy(Workflow.CopyIntent(scope: .message(ids[1]))),
            in: snapshot,
            reason: .messageFiltered(ids[1])
        )
    }

    func testNoStateChangeAllSelectedAndNoVisibleMessagesAreTypedDisabledReasons() throws {
        let (log, ids) = try makeLog([message(.info, "one")], selectedIndices: [0])
        let snapshot = try makeSnapshot(log: log)

        try assertDisabled(
            .setVisibility(.hidden),
            in: snapshot,
            reason: .noStateChange
        )
        try assertDisabled(
            .setVisibilityPersistence(.sessionOnly),
            in: snapshot,
            reason: .noStateChange
        )
        try assertDisabled(.filter(.set(.all)), in: snapshot, reason: .noStateChange)
        try assertDisabled(
            .setSensitiveCopyPolicy(.redact),
            in: snapshot,
            reason: .noStateChange
        )
        try assertDisabled(
            .select(.replace(ids[0])),
            in: snapshot,
            reason: .noStateChange
        )
        try assertDisabled(
            .selectAll,
            in: snapshot,
            reason: .allVisibleMessagesSelected
        )

        var unselectedLog = log
        XCTAssertTrue(unselectedLog.clearSelection())
        let noVisible = try makeSnapshot(
            log: unselectedLog,
            filter: Workflow.Filter(severities: .error)
        )
        try assertDisabled(.selectAll, in: noVisible, reason: .noVisibleMessages)
        try assertDisabled(
            .copy(Workflow.CopyIntent(scope: .visibleMessages)),
            in: noVisible,
            reason: .noVisibleMessages
        )
    }

    func testVisibleCopyDistinguishesEmptyLogFromNonemptyFilteredLogExactly() throws {
        try assertDisabled(
            .copy(Workflow.CopyIntent(scope: .visibleMessages)),
            in: makeSnapshot(),
            reason: .noMessages
        )

        let (log, _) = try makeLog([message(.error, "retained but hidden")])
        let filtered = try makeSnapshot(
            log: log,
            filter: Workflow.Filter(severities: .info)
        )
        try assertDisabled(
            .copy(Workflow.CopyIntent(scope: .visibleMessages)),
            in: filtered,
            reason: .noVisibleMessages
        )
    }

    func testRevisionExhaustionDisablesEveryMutatingCommandBeforeSpecificChecks() throws {
        let snapshot = try makeSnapshot(revision: .max)
        let intents: [Workflow.Intent] = [
            .toggleVisibility,
            .setVisibility(.visible),
            .setVisibilityPersistence(.persisted),
            .select(.clear),
            .copy(Workflow.CopyIntent()),
            .selectAll,
            .clearAll,
            .append(Workflow.AppendIntent(severity: .info, timestamp: timestamp, text: "x")),
            .filter(.clear),
            .setSensitiveCopyPolicy(.deny)
        ]

        for intent in intents {
            try assertDisabled(intent, in: snapshot, reason: .revisionExhausted)
        }
    }

    func testPrimaryCommandStatesHaveStableOrderAndPerCommandWorkReceipts() throws {
        let (log, _) = try makeLog([message(.info, "one")], selectedIndices: [0])
        let snapshot = try makeSnapshot(log: log)
        let states = try Workflow.primaryCommandStates(in: snapshot)

        XCTAssertEqual(states.map(\.command), [.toggleVisibility, .copy, .selectAll, .clearAll])
        XCTAssertTrue(states.allSatisfy { $0.expectedSnapshot == snapshot.reference })
        XCTAssertTrue(states.allSatisfy { $0.plannedWorkUnits > 0 })
        XCTAssertEqual(states[0].checkedState, .off)
        XCTAssertTrue(states[0].canExecute)
        XCTAssertTrue(states[1].canExecute)
        XCTAssertEqual(states[2].disabledReason, .allVisibleMessagesSelected)
        XCTAssertTrue(states[3].canExecute)
    }

    func testAppendReceiptTracksSanitizationEvictionSelectionAndSensitivity() throws {
        let logLimits = OutputPaneLog.Limits(maximumEntryCount: 2, maximumUTF8Bytes: 50)
        let (log, ids) = try makeLog(
            [message(.info, "old1"), message(.warning, "old2")],
            selectedIndices: [0],
            logLimits: logLimits
        )
        let workflowLimits = limits(
            maximumRetainedItemCount: 2,
            maximumSelectedItemCount: 2,
            maximumAppendUTF8Bytes: 50,
            maximumRetainedUTF8Bytes: 50
        )
        let snapshot = try makeSnapshot(
            log: log,
            securitySensitiveMessageIDs: [ids[0]],
            limits: workflowLimits
        )
        let intent = Workflow.AppendIntent(
            severity: .error,
            timestamp: timestamp.addingTimeInterval(10),
            text: "new\nline",
            sensitivity: .securitySensitive
        )
        let plan = try Workflow.plan(.append(intent), in: snapshot)
        let successor = try XCTUnwrap(plan.successor)
        guard case .appended(let receipt) = plan.receipt.result else {
            return XCTFail("Expected append receipt")
        }

        XCTAssertEqual(receipt.appendedMessageID, EntryID(rawValue: 3))
        XCTAssertEqual(receipt.evictedMessageIDs, [ids[0]])
        XCTAssertEqual(receipt.evictedUTF8ByteCount, 4)
        XCTAssertTrue(receipt.wasSanitized)
        XCTAssertEqual(receipt.sensitivity, .securitySensitive)
        XCTAssertEqual(successor.log.entries.map(\.id), [ids[1], receipt.appendedMessageID])
        XCTAssertEqual(successor.entry(withID: receipt.appendedMessageID)?.text, "new\\nline")
        XCTAssertTrue(successor.log.selectedIDs.isEmpty)
        XCTAssertEqual(successor.securitySensitiveMessageIDs, [receipt.appendedMessageID])
        XCTAssertEqual(successor.sensitivity(of: ids[0]), nil)
        XCTAssertEqual(successor.sensitivity(of: receipt.appendedMessageID), .securitySensitive)
    }

    func testSnapshotRejectsSecurityMetadataForNonretainedEntry() throws {
        let unknown = EntryID(rawValue: 41)

        assertWorkflowError(.securityMetadataReferencesUnknownMessage(unknown)) {
            try makeSnapshot(securitySensitiveMessageIDs: [unknown])
        }
    }

    func testSnapshotReportsLowestUnknownSecurityMetadataIDRegardlessOfSetOrder() throws {
        let low = EntryID(rawValue: 40)
        let high = EntryID(rawValue: 41)

        for metadata in [
            set(insertionOrder: [high, low]),
            set(insertionOrder: [low, high])
        ] {
            assertWorkflowError(.securityMetadataReferencesUnknownMessage(low)) {
                try makeSnapshot(securitySensitiveMessageIDs: metadata)
            }
        }
    }

    func testSnapshotRejectsSelectionOutsideVisibleIDs() throws {
        let (log, ids) = try makeLog(
            [message(.info, "visible"), message(.error, "hidden")],
            selectedIndices: [1]
        )

        assertWorkflowError(.selectionReferencesFilteredMessage(ids[1])) {
            try makeSnapshot(
                log: log,
                filter: Workflow.Filter(severities: .info)
            )
        }
    }

    func testSnapshotReportsLowestFilteredSelectionIDRegardlessOfSetOrder() throws {
        let messages = [
            message(.info, "visible"),
            message(.error, "hidden-low"),
            message(.error, "hidden-high")
        ]
        for order in [[2, 1], [1, 2]] {
            let (log, ids) = try makeLog(messages, selectedIndices: Set(order))
            assertWorkflowError(.selectionReferencesFilteredMessage(ids[1])) {
                try makeSnapshot(
                    log: log,
                    filter: Workflow.Filter(severities: .info)
                )
            }
        }
    }

    func testSelectionSetEnforcesSelectedItemLimitBeforeIDValidation() throws {
        let logLimits = OutputPaneLog.Limits(maximumEntryCount: 2, maximumUTF8Bytes: 16)
        let (log, ids) = try makeLog(
            [message(.info, "a"), message(.info, "b")],
            logLimits: logLimits
        )
        let bounded = limits(
            maximumRetainedItemCount: 2,
            maximumSelectedItemCount: 1,
            maximumAppendUTF8Bytes: 16,
            maximumRetainedUTF8Bytes: 16
        )
        let snapshot = try makeSnapshot(log: log, limits: bounded)

        assertWorkflowError(.tooManySelectedItems(maximum: 1)) {
            try Workflow.plan(.select(.set(Set(ids))), in: snapshot)
        }
    }

    func testCASRejectsIdentityAndRevisionChangesAsStale() throws {
        let snapshot = try makeSnapshot(revision: 10)
        let otherIdentity = try makeSnapshot(identity: Workflow.LogIdentity(), revision: 10)
        let otherRevision = try makeSnapshot(identity: snapshot.identity, revision: 11)

        for stale in [otherIdentity, otherRevision] {
            XCTAssertFalse(try snapshot.cas.matches(stale))
            assertWorkflowError(
                .staleLog(expected: snapshot.reference, actual: stale.reference)
            ) {
                try snapshot.cas.validate(stale)
            }
        }
    }

    func testCASSucceedsForSameValueAndIndependentlyRebuiltEquivalentSnapshot() throws {
        let messages = [message(.info, "alpha"), message(.error, "beta")]
        let (log, ids) = try makeLog(messages, selectedIndices: [0])
        let expected = try makeSnapshot(
            revision: 12,
            log: log,
            visibilityPreference: Workflow.VisibilityPreference(
                visibility: .visible,
                persistence: .persisted
            ),
            filter: Workflow.Filter(severities: .all, text: "a", caseSensitive: false),
            sensitiveCopyPolicy: .deny,
            securitySensitiveMessageIDs: [ids[1]]
        )
        let (rebuiltLog, rebuiltIDs) = try makeLog(messages, selectedIndices: [0])
        let rebuilt = try makeSnapshot(
            identity: expected.identity,
            revision: expected.revision,
            log: rebuiltLog,
            visibilityPreference: expected.visibilityPreference,
            filter: expected.filter,
            sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
            securitySensitiveMessageIDs: [rebuiltIDs[1]],
            limits: expected.limits
        )

        XCTAssertTrue(try expected.cas.matches(expected))
        XCTAssertNoThrow(try expected.cas.validate(expected))
        XCTAssertEqual(expected, rebuilt)
        XCTAssertTrue(try expected.cas.matches(rebuilt))
        XCTAssertNoThrow(try expected.cas.validate(rebuilt))
    }

    func testCASBindsEveryPublicSnapshotFieldAtExactReference() throws {
        let (log, ids) = try makeLog(
            [message(.info, "alpha"), message(.error, "beta")],
            selectedIndices: [0]
        )
        let expected = try makeSnapshot(
            revision: 20,
            log: log,
            visibilityPreference: Workflow.VisibilityPreference(
                visibility: .visible,
                persistence: .persisted
            ),
            filter: Workflow.Filter(text: "a"),
            sensitiveCopyPolicy: .redact,
            securitySensitiveMessageIDs: [ids[1]]
        )

        var selectedOther = log
        XCTAssertTrue(selectedOther.setSelection([ids[1]]))
        let differentLimits = limits(cancellationCheckInterval: 1)
        var shiftedTimestampLog = OutputPaneLog()
        let shiftedFirst = try shiftedTimestampLog.append(
            severity: .info,
            timestamp: timestamp.addingTimeInterval(10),
            text: "alpha"
        ).entry.id
        _ = try shiftedTimestampLog.append(
            severity: .error,
            timestamp: timestamp.addingTimeInterval(1),
            text: "beta"
        )
        XCTAssertTrue(shiftedTimestampLog.select(shiftedFirst))
        let rebuiltWithDifferentLogLimits = try makeLog(
            [message(.info, "alpha"), message(.error, "beta")],
            selectedIndices: [0],
            logLimits: OutputPaneLog.Limits(
                maximumEntryCount: 3,
                maximumUTF8Bytes: OutputPaneLog.Limits.defaultMaximumUTF8Bytes
            )
        ).log
        var sanitizedLog = OutputPaneLog()
        _ = try sanitizedLog.append(
            severity: .info,
            timestamp: timestamp,
            text: "alpha\n"
        )
        _ = try sanitizedLog.append(
            severity: .error,
            timestamp: timestamp.addingTimeInterval(1),
            text: "beta"
        )
        XCTAssertTrue(sanitizedLog.select(ids[0]))
        var shiftedIDLog = OutputPaneLog()
        _ = try shiftedIDLog.append(
            severity: .debug,
            timestamp: timestamp.addingTimeInterval(-1),
            text: "discarded"
        )
        XCTAssertTrue(shiftedIDLog.clear())
        let shiftedAlphaID = try shiftedIDLog.append(
            severity: .info,
            timestamp: timestamp,
            text: "alpha"
        ).entry.id
        let shiftedBetaID = try shiftedIDLog.append(
            severity: .error,
            timestamp: timestamp.addingTimeInterval(1),
            text: "beta"
        ).entry.id
        XCTAssertTrue(shiftedIDLog.select(shiftedAlphaID))
        let mutations: [Workflow.Snapshot] = [
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: try makeLog(
                    [message(.warning, "alpha"), message(.error, "beta")],
                    selectedIndices: [0]
                ).log,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: try makeLog(
                    [message(.info, "changed"), message(.error, "beta")],
                    selectedIndices: [0]
                ).log,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: shiftedIDLog,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [shiftedBetaID]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: shiftedTimestampLog,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: sanitizedLog,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: rebuiltWithDifferentLogLimits,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: selectedOther,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: log,
                visibilityPreference: Workflow.VisibilityPreference(
                    visibility: .hidden,
                    persistence: .persisted
                ),
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: log,
                visibilityPreference: Workflow.VisibilityPreference(
                    visibility: .visible,
                    persistence: .sessionOnly
                ),
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: log,
                visibilityPreference: expected.visibilityPreference,
                filter: Workflow.Filter(severities: .info, text: "a"),
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: log,
                visibilityPreference: expected.visibilityPreference,
                filter: Workflow.Filter(text: "A"),
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: log,
                visibilityPreference: expected.visibilityPreference,
                filter: Workflow.Filter(text: "a", caseSensitive: true),
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: log,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: .deny,
                securitySensitiveMessageIDs: [ids[1]]
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: log,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: []
            ),
            try makeSnapshot(
                identity: expected.identity,
                revision: expected.revision,
                log: log,
                visibilityPreference: expected.visibilityPreference,
                filter: expected.filter,
                sensitiveCopyPolicy: expected.sensitiveCopyPolicy,
                securitySensitiveMessageIDs: [ids[1]],
                limits: differentLimits
            )
        ]

        for mutation in mutations {
            XCTAssertFalse(try expected.cas.matches(mutation))
            assertWorkflowError(.logContentsChanged(expected.reference)) {
                try expected.cas.validate(mutation)
            }
        }
    }

    func testCASRejectsChangedContentsAtExactIdentityAndRevision() throws {
        let (expectedLog, _) = try makeLog([message(.info, "alpha")])
        let (changedLog, _) = try makeLog([message(.info, "bravo")])
        let expected = try makeSnapshot(revision: 22, log: expectedLog)
        let changed = try makeSnapshot(
            identity: expected.identity,
            revision: expected.revision,
            log: changedLog
        )

        XCTAssertFalse(try expected.cas.matches(changed))
        assertWorkflowError(.logContentsChanged(expected.reference)) {
            try expected.cas.validate(changed)
        }
    }

    func testCASIncludesPrivateNextIdentifierStateAfterClear() throws {
        var consumedLog = OutputPaneLog()
        _ = try consumedLog.append(severity: .debug, timestamp: timestamp, text: "used")
        XCTAssertTrue(consumedLog.clear())
        let expected = try makeSnapshot(revision: 9, log: consumedLog)
        let sameVisibleState = try makeSnapshot(
            identity: expected.identity,
            revision: expected.revision,
            log: OutputPaneLog()
        )

        XCTAssertEqual(expected.log.entries, sameVisibleState.log.entries)
        XCTAssertEqual(expected.log.selectedIDs, sameVisibleState.log.selectedIDs)
        XCTAssertFalse(try expected.cas.matches(sameVisibleState))
        assertWorkflowError(.logContentsChanged(expected.reference)) {
            try expected.cas.validate(sameVisibleState)
        }
    }

    func testPlansAndReceiptsAreDeterministicForSameSnapshotAndIntent() throws {
        let (log, _) = try makeLog([message(.info, "fixed")], selectedIndices: [0])
        let snapshot = try makeSnapshot(log: log)
        let intent = Workflow.Intent.copy(Workflow.CopyIntent(scope: .selection))
        let firstState = try Workflow.commandState(for: intent, in: snapshot)
        let secondState = try Workflow.commandState(for: intent, in: snapshot)
        let first = try Workflow.plan(intent, in: snapshot)
        let second = try Workflow.plan(intent, in: snapshot)

        XCTAssertEqual(firstState, secondState)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.receipt.plannedWorkUnits, firstState.plannedWorkUnits)
        XCTAssertEqual(Set([first.receipt, second.receipt]).count, 1)
    }

    func testSetInsertionOrderDoesNotChangeSnapshotPlanOrReceipt() throws {
        let messages = [
            message(.info, "one"),
            message(.info, "two"),
            message(.info, "three")
        ]
        let (forwardLog, forwardIDs) = try makeLog(messages)
        let (reverseLog, reverseIDs) = try makeLog(messages)
        let forwardSensitive = set(insertionOrder: [forwardIDs[2], forwardIDs[0]])
        let reverseSensitive = set(insertionOrder: [reverseIDs[0], reverseIDs[2]])
        let forward = try makeSnapshot(
            log: forwardLog,
            securitySensitiveMessageIDs: forwardSensitive
        )
        let reverse = try makeSnapshot(
            log: reverseLog,
            securitySensitiveMessageIDs: reverseSensitive
        )
        let forwardIntent = Workflow.Intent.select(
            .set(set(insertionOrder: [forwardIDs[2], forwardIDs[0]]))
        )
        let reverseIntent = Workflow.Intent.select(
            .set(set(insertionOrder: [reverseIDs[0], reverseIDs[2]]))
        )
        let forwardPlan = try Workflow.plan(forwardIntent, in: forward)
        let reversePlan = try Workflow.plan(reverseIntent, in: reverse)

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.cas, reverse.cas)
        XCTAssertEqual(forwardPlan, reversePlan)
        XCTAssertEqual(forwardPlan.receipt, reversePlan.receipt)
        XCTAssertEqual(selectionIDs(in: forwardPlan), [forwardIDs[0], forwardIDs[2]])
    }

    func testCompletedExecutionOutcomeContainsEveryRequiredEffect() throws {
        let plan = try Workflow.plan(.toggleVisibility, in: makeSnapshot())
        let outcome = Workflow.ExecutionOutcomeFactory.completed(plan: plan)

        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected completed outcome")
        }
        XCTAssertEqual(receipt.planningReceipt, plan.receipt)
        XCTAssertEqual(receipt.completedEffects, plan.requiredEffects)
    }

    func testNotCommittedDefaultIndexAndReasonMatrixAreExact() throws {
        let plan = try Workflow.plan(
            .setVisibilityPersistence(.persisted),
            in: makeSnapshot()
        )
        let outcome = try Workflow.ExecutionOutcomeFactory.notCommitted(
            plan: plan,
            reason: .visibilityPreferenceStorageUnavailable
        )
        guard case .notCommitted(let receipt) = outcome else {
            return XCTFail("Expected not-committed outcome")
        }
        XCTAssertEqual(receipt.blockedEffect, plan.requiredEffects[0])
        XCTAssertEqual(receipt.reason, .visibilityPreferenceStorageUnavailable)
        XCTAssertEqual(receipt.planningReceipt, plan.receipt)

        let universalReasons: [Workflow.ExecutionNonCommitReason] = [
            .cancelled, .staleSnapshot, .contractUnsupported, .rejected
        ]
        for reason in universalReasons {
            XCTAssertNoThrow(
                try Workflow.ExecutionOutcomeFactory.notCommitted(plan: plan, reason: reason)
            )
        }

        let togglePlan = try Workflow.plan(.toggleVisibility, in: makeSnapshot())
        XCTAssertNoThrow(
            try Workflow.ExecutionOutcomeFactory.notCommitted(
                plan: togglePlan,
                reason: .ownerStateUnavailable
            )
        )
        for reason in [
            Workflow.ExecutionNonCommitReason.ownerStateUnavailable,
            .clipboardUnavailable
        ] {
            assertWorkflowError(.invalidExecutionOutcome) {
                try Workflow.ExecutionOutcomeFactory.notCommitted(plan: plan, reason: reason)
            }
        }

        let matrix:
            [(
                plan: Workflow.Plan,
                valid: Set<Workflow.ExecutionNonCommitReason>
            )] = [
                (
                    plan,
                    [
                        .cancelled,
                        .staleSnapshot,
                        .visibilityPreferenceStorageUnavailable,
                        .contractUnsupported,
                        .rejected
                    ]
                ),
                (
                    togglePlan,
                    [
                        .cancelled,
                        .staleSnapshot,
                        .ownerStateUnavailable,
                        .contractUnsupported,
                        .rejected
                    ]
                )
            ]
        for row in matrix {
            for reason in Workflow.ExecutionNonCommitReason.allCases {
                if row.valid.contains(reason) {
                    XCTAssertNoThrow(
                        try Workflow.ExecutionOutcomeFactory.notCommitted(
                            plan: row.plan,
                            reason: reason
                        )
                    )
                } else {
                    assertWorkflowError(.invalidExecutionOutcome) {
                        try Workflow.ExecutionOutcomeFactory.notCommitted(
                            plan: row.plan,
                            reason: reason
                        )
                    }
                }
            }
        }

        assertWorkflowError(.invalidExecutionOutcome) {
            try Workflow.ExecutionOutcomeFactory.notCommitted(
                plan: plan,
                blockedEffectIndex: 1,
                reason: .ownerStateUnavailable
            )
        }
        assertWorkflowError(.invalidExecutionOutcome) {
            try Workflow.ExecutionOutcomeFactory.notCommitted(
                plan: plan,
                reason: .clipboardUnavailable
            )
        }
        for index in [-1, plan.requiredEffects.count, plan.requiredEffects.count + 1] {
            assertWorkflowError(.invalidExecutionOutcome) {
                try Workflow.ExecutionOutcomeFactory.notCommitted(
                    plan: plan,
                    blockedEffectIndex: index,
                    reason: .rejected
                )
            }
        }
    }

    func testFailedOutcomeReportsStableCompletedFailedAndUnattemptedSlices() throws {
        let persistencePlan = try Workflow.plan(
            .setVisibilityPersistence(.persisted),
            in: makeSnapshot()
        )
        let persistenceFailure = try Workflow.ExecutionOutcomeFactory.failed(
            plan: persistencePlan,
            completedEffectCount: 1,
            reason: .ownerStateUnavailable
        )
        guard case .failedAfterEffects(let persistenceReceipt) = persistenceFailure else {
            return XCTFail("Expected failed outcome")
        }
        XCTAssertEqual(persistenceReceipt.completedEffects, [persistencePlan.requiredEffects[0]])
        XCTAssertEqual(persistenceReceipt.failedEffect, persistencePlan.requiredEffects[1])
        XCTAssertEqual(persistenceReceipt.reason, .ownerStateUnavailable)
        XCTAssertTrue(persistenceReceipt.unattemptedEffects.isEmpty)
        XCTAssertEqual(persistenceReceipt.planningReceipt, persistencePlan.receipt)

        let (log, _) = try makeLog([message(.info, "copy")], selectedIndices: [0])
        let copyPlan = try Workflow.plan(
            .copy(Workflow.CopyIntent()),
            in: makeSnapshot(log: log)
        )
        let clipboardFailure = try Workflow.ExecutionOutcomeFactory.failed(
            plan: copyPlan,
            completedEffectCount: 1,
            reason: .clipboardUnavailable
        )
        guard case .failedAfterEffects(let clipboardReceipt) = clipboardFailure else {
            return XCTFail("Expected clipboard failure")
        }
        XCTAssertEqual(clipboardReceipt.failedEffect, copyPlan.requiredEffects[1])
        XCTAssertEqual(clipboardReceipt.reason, .clipboardUnavailable)
        XCTAssertEqual(clipboardReceipt.planningReceipt, copyPlan.receipt)
    }

    func testUncertainOutcomeRequiresContiguousPlanOrderedEffects() throws {
        let (log, _) = try makeLog([message(.info, "copy")], selectedIndices: [0])
        let plan = try Workflow.plan(
            .copy(Workflow.CopyIntent()),
            in: makeSnapshot(log: log)
        )

        let allUncertain = try Workflow.ExecutionOutcomeFactory.effectUncertain(
            plan: plan,
            uncertainEffectIndices: [1, 0]
        )
        guard case .effectUncertain(let allReceipt) = allUncertain else {
            return XCTFail("Expected uncertainty outcome")
        }
        XCTAssertTrue(allReceipt.completedEffects.isEmpty)
        XCTAssertEqual(allReceipt.uncertainEffects, plan.requiredEffects)
        XCTAssertTrue(allReceipt.unattemptedEffects.isEmpty)
        XCTAssertEqual(allReceipt.planningReceipt, plan.receipt)

        let clipboardUncertain = try Workflow.ExecutionOutcomeFactory.effectUncertain(
            plan: plan,
            completedEffectCount: 1,
            uncertainEffectIndices: [1]
        )
        guard case .effectUncertain(let clipboardReceipt) = clipboardUncertain else {
            return XCTFail("Expected clipboard uncertainty")
        }
        XCTAssertEqual(clipboardReceipt.completedEffects, [plan.requiredEffects[0]])
        XCTAssertEqual(clipboardReceipt.uncertainEffects, [plan.requiredEffects[1]])
        XCTAssertTrue(clipboardReceipt.unattemptedEffects.isEmpty)
        XCTAssertEqual(clipboardReceipt.planningReceipt, plan.receipt)
    }

    func testUncertaintyAtIndexZeroLeavesLaterEffectUnattempted() throws {
        let plan = try Workflow.plan(
            .setVisibilityPersistence(.persisted),
            in: makeSnapshot()
        )
        let outcome = try Workflow.ExecutionOutcomeFactory.effectUncertain(
            plan: plan,
            uncertainEffectIndices: [0]
        )
        guard case .effectUncertain(let receipt) = outcome else {
            return XCTFail("Expected uncertainty outcome")
        }

        XCTAssertEqual(receipt.planningReceipt, plan.receipt)
        XCTAssertTrue(receipt.completedEffects.isEmpty)
        XCTAssertEqual(receipt.uncertainEffects, [plan.requiredEffects[0]])
        XCTAssertEqual(receipt.unattemptedEffects, [plan.requiredEffects[1]])
    }

    func testInvalidFailedAndUncertainOutcomeShapesAreTypedErrors() throws {
        let (log, _) = try makeLog([message(.info, "copy")], selectedIndices: [0])
        let plan = try Workflow.plan(
            .copy(Workflow.CopyIntent()),
            in: makeSnapshot(log: log)
        )

        for completedCount in [-1, 0, plan.requiredEffects.count, plan.requiredEffects.count + 1] {
            assertWorkflowError(.invalidExecutionOutcome) {
                try Workflow.ExecutionOutcomeFactory.failed(
                    plan: plan,
                    completedEffectCount: completedCount,
                    reason: .rejected
                )
            }
        }
        assertWorkflowError(.invalidExecutionOutcome) {
            try Workflow.ExecutionOutcomeFactory.failed(
                plan: plan,
                completedEffectCount: 1,
                reason: .ownerStateUnavailable
            )
        }

        let invalidUncertainCases: [(completedCount: Int, indices: [Int])] = [
            (-1, [0]),
            (0, []),
            (0, [-1]),
            (0, [0, 0]),
            (0, [1]),
            (0, [plan.requiredEffects.count]),
            (plan.requiredEffects.count, [plan.requiredEffects.count - 1])
        ]
        for testCase in invalidUncertainCases {
            assertWorkflowError(.invalidExecutionOutcome) {
                try Workflow.ExecutionOutcomeFactory.effectUncertain(
                    plan: plan,
                    completedEffectCount: testCase.completedCount,
                    uncertainEffectIndices: testCase.indices
                )
            }
        }
    }

    func testPublicPlansCannotConstructInRangeNoncontiguousUncertaintyFixture() throws {
        let (log, _) = try makeLog([message(.info, "copy")], selectedIndices: [0])
        let plans = [
            try Workflow.plan(.setVisibilityPersistence(.persisted), in: makeSnapshot()),
            try Workflow.plan(
                .copy(Workflow.CopyIntent()),
                in: makeSnapshot(log: log)
            )
        ]

        XCTAssertEqual(plans.map { $0.requiredEffects.count }, [2, 2])
        XCTAssertTrue(plans.allSatisfy { $0.requiredEffects.indices.count < 3 })
    }

    func testEveryInvalidLimitReportsItsOwnTypedLimit() {
        let invalidCases: [(Workflow.Limit, Workflow.Limits)] = [
            (.retainedItems, limits(maximumRetainedItemCount: 0)),
            (.selectedItems, limits(maximumSelectedItemCount: 0)),
            (.appendText, limits(maximumAppendUTF8Bytes: 0)),
            (
                .retainedText,
                limits(
                    maximumRetainedUTF8Bytes:
                        Workflow.Limits.hardMaximumRetainedUTF8Bytes + 1
                )
            ),
            (
                .filterText,
                limits(maximumFilterUTF8Bytes: Workflow.Limits.hardMaximumFilterUTF8Bytes + 1)
            ),
            (.copyText, limits(maximumCopyUTF8Bytes: 0)),
            (.workUnits, limits(maximumWorkUnits: 0)),
            (
                .aggregateWorkUnits,
                limits(
                    maximumAggregateWorkUnits: Workflow.Limits.default.maximumWorkUnits - 1
                )
            ),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0))
        ]
        XCTAssertEqual(Set(invalidCases.map(\.0)), Set(Workflow.Limit.allCases))

        for (expected, invalidLimits) in invalidCases {
            assertWorkflowError(.invalidLimit(expected)) {
                try makeSnapshot(limits: invalidLimits)
            }
        }
    }

    func testEveryHardMaximumAndCrossLimitRelationshipFailsAtItsOwnBoundary() {
        let hardCases: [(Workflow.Limit, Workflow.Limits)] = [
            (
                .retainedItems,
                limits(
                    maximumRetainedItemCount:
                        Workflow.Limits.hardMaximumRetainedItemCount + 1
                )
            ),
            (
                .selectedItems,
                limits(
                    maximumRetainedItemCount: Workflow.Limits.hardMaximumRetainedItemCount,
                    maximumSelectedItemCount:
                        Workflow.Limits.hardMaximumSelectedItemCount + 1
                )
            ),
            (
                .appendText,
                limits(
                    maximumAppendUTF8Bytes:
                        Workflow.Limits.hardMaximumAppendUTF8Bytes + 1
                )
            ),
            (
                .retainedText,
                limits(
                    maximumRetainedUTF8Bytes:
                        Workflow.Limits.hardMaximumRetainedUTF8Bytes + 1
                )
            ),
            (
                .filterText,
                limits(
                    maximumFilterUTF8Bytes:
                        Workflow.Limits.hardMaximumFilterUTF8Bytes + 1
                )
            ),
            (
                .copyText,
                limits(
                    maximumCopyUTF8Bytes:
                        Workflow.Limits.hardMaximumCopyUTF8Bytes + 1
                )
            ),
            (
                .workUnits,
                limits(maximumWorkUnits: Workflow.Limits.hardMaximumWorkUnits + 1)
            ),
            (
                .aggregateWorkUnits,
                limits(
                    maximumAggregateWorkUnits:
                        Workflow.Limits.hardMaximumWorkUnits + 1
                )
            ),
            (
                .cancellationCheckInterval,
                limits(
                    cancellationCheckInterval:
                        Workflow.Limits.hardMaximumCancellationCheckInterval + 1
                )
            )
        ]
        XCTAssertEqual(Set(hardCases.map(\.0)), Set(Workflow.Limit.allCases))
        for (expected, invalidLimits) in hardCases {
            assertWorkflowError(.invalidLimit(expected)) {
                try makeSnapshot(limits: invalidLimits)
            }
        }

        let crossCases: [(Workflow.Limit, Workflow.Limits)] = [
            (
                .selectedItems,
                limits(maximumRetainedItemCount: 1, maximumSelectedItemCount: 2)
            ),
            (
                .appendText,
                limits(maximumAppendUTF8Bytes: 2, maximumRetainedUTF8Bytes: 1)
            ),
            (
                .aggregateWorkUnits,
                limits(maximumWorkUnits: 2, maximumAggregateWorkUnits: 1)
            )
        ]
        for (expected, invalidLimits) in crossCases {
            assertWorkflowError(.invalidLimit(expected)) {
                try makeSnapshot(limits: invalidLimits)
            }
        }
    }

    func testIncompatibleRetainedItemLogLimitIsIsolated() throws {
        let log = OutputPaneLog(
            limits: OutputPaneLog.Limits(maximumEntryCount: 2, maximumUTF8Bytes: 16)
        )
        let bounded = limits(
            maximumRetainedItemCount: 1,
            maximumSelectedItemCount: 1,
            maximumAppendUTF8Bytes: 16,
            maximumRetainedUTF8Bytes: 16
        )

        assertWorkflowError(.incompatibleLogLimit(.retainedItems)) {
            try makeSnapshot(log: log, limits: bounded)
        }
    }

    func testIncompatibleRetainedTextLogLimitIsIsolated() throws {
        let log = OutputPaneLog(
            limits: OutputPaneLog.Limits(maximumEntryCount: 1, maximumUTF8Bytes: 10)
        )
        let bounded = limits(
            maximumRetainedItemCount: 1,
            maximumSelectedItemCount: 1,
            maximumAppendUTF8Bytes: 9,
            maximumRetainedUTF8Bytes: 9
        )

        assertWorkflowError(.incompatibleLogLimit(.retainedText)) {
            try makeSnapshot(log: log, limits: bounded)
        }
    }

    func testAppendAndFilterStringLimitsAcceptExactUTF8AndRejectOneByteOver() throws {
        let bounded = limits(maximumAppendUTF8Bytes: 4, maximumFilterUTF8Bytes: 4)
        let snapshot = try makeSnapshot(limits: bounded)
        let exact = "éé"
        let over = exact + "a"
        XCTAssertEqual(exact.utf8.count, 4)
        XCTAssertEqual(over.utf8.count, 5)

        XCTAssertNoThrow(
            try Workflow.plan(
                .append(
                    Workflow.AppendIntent(
                        severity: .info,
                        timestamp: timestamp,
                        text: exact
                    )
                ),
                in: snapshot
            )
        )
        assertWorkflowError(.textTooLarge(field: .appendMessage, maximumUTF8Bytes: 4)) {
            try Workflow.plan(
                .append(
                    Workflow.AppendIntent(
                        severity: .info,
                        timestamp: timestamp,
                        text: over
                    )
                ),
                in: snapshot
            )
        }

        XCTAssertNoThrow(
            try Workflow.plan(
                .filter(.set(Workflow.Filter(text: exact))),
                in: snapshot
            )
        )
        assertWorkflowError(.textTooLarge(field: .filter, maximumUTF8Bytes: 4)) {
            try Workflow.plan(
                .filter(.set(Workflow.Filter(text: over))),
                in: snapshot
            )
        }
    }

    func testCopyOutputLimitAcceptsExactUTF8AndRejectsOneByteUnder() throws {
        let logLimits = OutputPaneLog.Limits(maximumEntryCount: 2, maximumUTF8Bytes: 16)
        let (log, _) = try makeLog(
            [message(.info, "one"), message(.info, "two")],
            selectedIndices: [0, 1],
            logLimits: logLimits
        )
        let exactByteCount = "one\ntwo".utf8.count
        let exactLimits = limits(
            maximumRetainedItemCount: 2,
            maximumSelectedItemCount: 2,
            maximumAppendUTF8Bytes: 16,
            maximumRetainedUTF8Bytes: 16,
            maximumCopyUTF8Bytes: exactByteCount
        )
        let exact = try makeSnapshot(log: log, limits: exactLimits)
        let payload = try copyPayload(
            from: Workflow.plan(.copy(Workflow.CopyIntent()), in: exact)
        )
        XCTAssertEqual(payload.summary.utf8ByteCount, exactByteCount)

        let insufficient = try makeSnapshot(
            log: log,
            limits: limits(
                maximumRetainedItemCount: 2,
                maximumSelectedItemCount: 2,
                maximumAppendUTF8Bytes: 16,
                maximumRetainedUTF8Bytes: 16,
                maximumCopyUTF8Bytes: exactByteCount - 1
            )
        )
        assertWorkflowError(.copyTextTooLarge(maximumUTF8Bytes: exactByteCount - 1)) {
            try Workflow.plan(.copy(Workflow.CopyIntent()), in: insufficient)
        }
    }

    func testEveryRedactedScopeAcceptsExactUnicodeOutputAndRejectsOneByteLess() throws {
        let logLimits = OutputPaneLog.Limits(maximumEntryCount: 3, maximumUTF8Bytes: 64)
        let (log, ids) = try makeLog(
            [
                message(.info, "é"),
                message(.error, "秘密"),
                message(.info, "visible")
            ],
            selectedIndices: [0, 1],
            logLimits: logLimits
        )
        let cases: [(scope: Workflow.CopyScope, expected: String)] = [
            (.selection, "é\n\(Workflow.redactionMarker)"),
            (.message(ids[1]), Workflow.redactionMarker),
            (.visibleMessages, "é\n\(Workflow.redactionMarker)\nvisible")
        ]

        for testCase in cases {
            let exactBytes = testCase.expected.utf8.count
            let commonLimits = (
                maximumRetainedItemCount: 3,
                maximumSelectedItemCount: 3,
                maximumAppendUTF8Bytes: 64,
                maximumRetainedUTF8Bytes: 64
            )
            let exact = try makeSnapshot(
                log: log,
                sensitiveCopyPolicy: .redact,
                securitySensitiveMessageIDs: [ids[1]],
                limits: limits(
                    maximumRetainedItemCount: commonLimits.maximumRetainedItemCount,
                    maximumSelectedItemCount: commonLimits.maximumSelectedItemCount,
                    maximumAppendUTF8Bytes: commonLimits.maximumAppendUTF8Bytes,
                    maximumRetainedUTF8Bytes: commonLimits.maximumRetainedUTF8Bytes,
                    maximumCopyUTF8Bytes: exactBytes
                )
            )
            let exactPayload = try copyPayload(
                from: Workflow.plan(
                    .copy(Workflow.CopyIntent(scope: testCase.scope)),
                    in: exact
                )
            )
            XCTAssertEqual(exactPayload.text, testCase.expected)
            XCTAssertEqual(exactPayload.summary.utf8ByteCount, exactBytes)

            let maximum = exactBytes - 1
            let insufficient = try makeSnapshot(
                log: log,
                sensitiveCopyPolicy: .redact,
                securitySensitiveMessageIDs: [ids[1]],
                limits: limits(
                    maximumRetainedItemCount: commonLimits.maximumRetainedItemCount,
                    maximumSelectedItemCount: commonLimits.maximumSelectedItemCount,
                    maximumAppendUTF8Bytes: commonLimits.maximumAppendUTF8Bytes,
                    maximumRetainedUTF8Bytes: commonLimits.maximumRetainedUTF8Bytes,
                    maximumCopyUTF8Bytes: maximum
                )
            )
            assertWorkflowError(.copyTextTooLarge(maximumUTF8Bytes: maximum)) {
                try Workflow.plan(
                    .copy(Workflow.CopyIntent(scope: testCase.scope)),
                    in: insufficient
                )
            }
        }
    }

    func testPerCommandWorkLimitAcceptsExactReceiptAndRejectsOneUnitUnder() throws {
        let intent = Workflow.Intent.filter(.set(Workflow.Filter(text: "x")))
        let required: UInt64 = 3
        let exact = try makeSnapshot(
            limits: limits(
                maximumWorkUnits: required,
                maximumAggregateWorkUnits: 12
            )
        )
        XCTAssertEqual(
            try Workflow.commandState(for: intent, in: exact).plannedWorkUnits,
            required
        )
        XCTAssertEqual(
            try Workflow.plan(intent, in: exact).receipt.plannedWorkUnits,
            required
        )

        let maximum = required - 1
        let insufficient = try makeSnapshot(
            limits: limits(
                maximumWorkUnits: maximum,
                maximumAggregateWorkUnits: 8
            )
        )
        assertWorkflowError(.workLimitExceeded(maximumUnits: maximum)) {
            try Workflow.plan(intent, in: insufficient)
        }
    }

    func testAggregateCommandWorkLimitAcceptsExactSumAndRejectsOneUnitUnder() throws {
        let perCommandMaximum: UInt64 = 1
        let aggregate: UInt64 = 4
        let exact = try makeSnapshot(
            limits: limits(
                maximumWorkUnits: perCommandMaximum,
                maximumAggregateWorkUnits: aggregate
            )
        )
        XCTAssertEqual(try Workflow.primaryCommandStates(in: exact).map(\.plannedWorkUnits), [1, 1, 1, 1])

        let maximumAggregate = aggregate - 1
        let insufficient = try makeSnapshot(
            limits: limits(
                maximumWorkUnits: perCommandMaximum,
                maximumAggregateWorkUnits: maximumAggregate
            )
        )
        assertWorkflowError(.workLimitExceeded(maximumUnits: maximumAggregate)) {
            try Workflow.primaryCommandStates(in: insufficient)
        }
    }

    func testInvalidSeverityMaskIsIsolated() {
        let invalid = Workflow.SeverityMask(rawValue: Workflow.SeverityMask.all.rawValue | 0x80)

        assertWorkflowError(.invalidSeverityMask(invalid.rawValue)) {
            try makeSnapshot(filter: Workflow.Filter(severities: invalid))
        }
    }

    func testInvalidTimestampIsWrappedAsOutputLogError() throws {
        let snapshot = try makeSnapshot()
        let intent = Workflow.AppendIntent(
            severity: .error,
            timestamp: Date(timeIntervalSinceReferenceDate: .infinity),
            text: "invalid"
        )

        assertWorkflowError(.outputLog(.invalidTimestamp)) {
            try Workflow.plan(.append(intent), in: snapshot)
        }
    }

    func testSanitizationExpansionFailureIsWrappedAsOutputLogError() throws {
        let logLimits = OutputPaneLog.Limits(maximumEntryCount: 1, maximumUTF8Bytes: 4)
        let bounded = limits(
            maximumRetainedItemCount: 1,
            maximumSelectedItemCount: 1,
            maximumAppendUTF8Bytes: 4,
            maximumRetainedUTF8Bytes: 4
        )
        let snapshot = try makeSnapshot(
            log: OutputPaneLog(limits: logLimits),
            limits: bounded
        )

        assertWorkflowError(.outputLog(.entryTooLarge(maximumUTF8Bytes: 4))) {
            try Workflow.plan(
                .append(
                    Workflow.AppendIntent(
                        severity: .info,
                        timestamp: timestamp,
                        text: "\0"
                    )
                ),
                in: snapshot
            )
        }
    }

    func testExecutorContractExposesEveryMandatoryBoundary() throws {
        let contract = try Workflow.plan(.toggleVisibility, in: makeSnapshot()).executorContract

        XCTAssertEqual(contract, .required)
        XCTAssertEqual(contract.logCAS, .holdExactIdentityRevisionAndContentsThroughEffects)
        XCTAssertEqual(contract.state, .commitExactPlannedSuccessorWithoutRegeneration)
        XCTAssertEqual(
            contract.persistence,
            .publishExactPreferenceBeforeStateCommitWhileHoldingCASLease
        )
        XCTAssertEqual(
            contract.clipboard,
            .replaceExactPlannedTextAfterSuccessorCommitWhileHoldingCASLease
        )
        XCTAssertEqual(
            contract.security,
            .neverPublishSensitiveTextUnlessPlanExplicitlyAuthorizesIt
        )
        XCTAssertEqual(
            contract.cancellation,
            .cancelBeforeEffectsOrReportCompletedOrUncertainEffects
        )
    }

    func testPreCancellationCoversEveryCancellationAwarePublicThrowingBoundary() async throws {
        let (log, _) = try makeLog([message(.info, "copy")], selectedIndices: [0])
        let snapshot = try makeSnapshot(log: log)
        let copyPlan = try Workflow.plan(.copy(Workflow.CopyIntent()), in: snapshot)
        let boundaries:
            [(
                name: String,
                operation: @Sendable () throws -> Void
            )] = [
                ("Snapshot.init", { _ = try Workflow.Snapshot() }),
                ("SnapshotCAS.matches", { _ = try snapshot.cas.matches(snapshot) }),
                ("SnapshotCAS.validate", { try snapshot.cas.validate(snapshot) }),
                ("Plan.validateCurrentSnapshot", { try copyPlan.validateCurrentSnapshot(snapshot) }),
                (
                    "commandState",
                    { _ = try Workflow.commandState(for: .toggleVisibility, in: snapshot) }
                ),
                ("primaryCommandStates", { _ = try Workflow.primaryCommandStates(in: snapshot) }),
                ("plan", { _ = try Workflow.plan(.toggleVisibility, in: snapshot) })
            ]

        for boundary in boundaries {
            let result = await preCancelledResult(boundary.operation)
            XCTAssertEqual(result, .workflowError(.cancelled), boundary.name)
        }
    }

    func testPreCancellationDoesNotInventCancellationForConstantTimeValidators() async throws {
        let snapshot = try makeSnapshot()
        let persistencePlan = try Workflow.plan(
            .setVisibilityPersistence(.persisted),
            in: snapshot
        )
        let constantTimeBoundaries:
            [(
                name: String,
                operation: @Sendable () throws -> Void
            )] = [
                (
                    "VisibilityPreference.init(restoring:)",
                    {
                        _ = try Workflow.VisibilityPreference(
                            restoring: Workflow.PersistedVisibilityPreference(visibility: .visible)
                        )
                    }
                ),
                (
                    "ExecutionOutcomeFactory.notCommitted",
                    {
                        _ = try Workflow.ExecutionOutcomeFactory.notCommitted(
                            plan: persistencePlan,
                            reason: .rejected
                        )
                    }
                ),
                (
                    "ExecutionOutcomeFactory.failed",
                    {
                        _ = try Workflow.ExecutionOutcomeFactory.failed(
                            plan: persistencePlan,
                            completedEffectCount: 1,
                            reason: .ownerStateUnavailable
                        )
                    }
                ),
                (
                    "ExecutionOutcomeFactory.effectUncertain",
                    {
                        _ = try Workflow.ExecutionOutcomeFactory.effectUncertain(
                            plan: persistencePlan,
                            uncertainEffectIndices: [0]
                        )
                    }
                )
            ]

        for boundary in constantTimeBoundaries {
            let result = await preCancelledResult(boundary.operation)
            XCTAssertEqual(result, .success, boundary.name)
        }
    }

    func testPreCancelledPlanningMapsCancellationBeforeDisabledCommand() async throws {
        let snapshot = try makeSnapshot()
        let result = await Task { @Sendable () -> Workflow.WorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Workflow.plan(.clearAll, in: snapshot)
                return nil
            } catch {
                return error as? Workflow.WorkflowError
            }
        }.value

        XCTAssertEqual(result, .cancelled)
    }

    func testPeriodicCopyCancellationMapsToWorkflowDomain() async throws {
        let byteCount = Workflow.Limits.hardMaximumRetainedUTF8Bytes
        let logLimits = OutputPaneLog.Limits(maximumEntryCount: 1, maximumUTF8Bytes: byteCount)
        var log = OutputPaneLog(limits: logLimits)
        let id = try log.append(
            severity: .info,
            timestamp: timestamp,
            text: String(repeating: "x", count: byteCount)
        ).entry.id
        XCTAssertTrue(log.select(id))
        let bounded = limits(
            maximumRetainedItemCount: 1,
            maximumSelectedItemCount: 1,
            maximumRetainedUTF8Bytes: byteCount,
            cancellationCheckInterval: 1
        )
        let snapshot = try makeSnapshot(log: log, limits: bounded)
        let gate = CancellationStartGate()
        let task = Task.detached { @Sendable () -> Workflow.WorkflowError? in
            await gate.markStarted(thread: pthread_mach_thread_np(pthread_self()))
            do {
                _ = try Workflow.plan(.copy(Workflow.CopyIntent()), in: snapshot)
                return nil
            } catch {
                return error as? Workflow.WorkflowError
            }
        }
        let thread = await gate.waitUntilStarted()
        let baseline = try XCTUnwrap(threadCPUNanoseconds(thread))
        await waitForThreadCPU(
            thread,
            toReach: baseline + 5_000_000
        )
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    func testCancellationPrecedenceIsExplicitAtValidationBoundaries() async throws {
        let invalidLimitsResult = await Task { @Sendable () -> Workflow.WorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Workflow.Snapshot(limits: Workflow.Limits(maximumWorkUnits: 0))
                return nil
            } catch {
                return error as? Workflow.WorkflowError
            }
        }.value
        XCTAssertEqual(invalidLimitsResult, .invalidLimit(.workUnits))

        let expected = try makeSnapshot(revision: 1)
        let stale = try makeSnapshot(identity: expected.identity, revision: 2)
        let staleCASResult = await Task { @Sendable () -> Workflow.WorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try expected.cas.validate(stale)
                return nil
            } catch {
                return error as? Workflow.WorkflowError
            }
        }.value
        XCTAssertEqual(staleCASResult, .cancelled)

        let logLimits = OutputPaneLog.Limits(maximumEntryCount: 1, maximumUTF8Bytes: 8)
        let (log, _) = try makeLog(
            [message(.info, "xx")],
            selectedIndices: [0],
            logLimits: logLimits
        )
        let outputLimited = try makeSnapshot(
            log: log,
            limits: limits(
                maximumRetainedItemCount: 1,
                maximumSelectedItemCount: 1,
                maximumAppendUTF8Bytes: 8,
                maximumRetainedUTF8Bytes: 8,
                maximumCopyUTF8Bytes: 1
            )
        )
        let copyResult = await Task { @Sendable () -> Workflow.WorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Workflow.plan(.copy(Workflow.CopyIntent()), in: outputLimited)
                return nil
            } catch {
                return error as? Workflow.WorkflowError
            }
        }.value
        XCTAssertEqual(copyResult, .cancelled)
    }
}

private actor CancellationStartGate {
    private var thread: mach_port_t?

    func markStarted(thread: mach_port_t) {
        self.thread = thread
    }

    func waitUntilStarted() async -> mach_port_t {
        while thread == nil {
            await Task.yield()
        }
        return thread!
    }
}

extension OutputPaneWorkflowTests {
    private struct Message {
        let severity: OutputPaneLog.Severity
        let text: String
    }

    private var timestamp: Date {
        Date(timeIntervalSinceReferenceDate: 1_000)
    }

    private var identity: Workflow.LogIdentity {
        Workflow.LogIdentity(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        )
    }

    private func message(_ severity: OutputPaneLog.Severity, _ text: String) -> Message {
        Message(severity: severity, text: text)
    }

    private func makeLog(
        _ messages: [Message],
        selectedIndices: Set<Int> = [],
        logLimits: OutputPaneLog.Limits = .default
    ) throws -> (log: OutputPaneLog, ids: [EntryID]) {
        var log = OutputPaneLog(limits: logLimits)
        var ids: [EntryID] = []
        ids.reserveCapacity(messages.count)
        for (index, message) in messages.enumerated() {
            let result = try log.append(
                severity: message.severity,
                timestamp: timestamp.addingTimeInterval(Double(index)),
                text: message.text
            )
            ids.append(result.entry.id)
        }
        let selectedIDs = Set(selectedIndices.map { ids[$0] })
        _ = log.setSelection(selectedIDs)
        return (log, ids)
    }

    private func makeSnapshot(
        identity: Workflow.LogIdentity? = nil,
        revision: UInt64 = 0,
        log: OutputPaneLog = OutputPaneLog(),
        visibilityPreference: Workflow.VisibilityPreference = .default,
        filter: Workflow.Filter = .all,
        sensitiveCopyPolicy: Workflow.SensitiveCopyPolicy = .redact,
        securitySensitiveMessageIDs: Set<EntryID> = [],
        limits: Workflow.Limits = .default
    ) throws -> Workflow.Snapshot {
        try Workflow.Snapshot(
            identity: identity ?? self.identity,
            revision: revision,
            log: log,
            visibilityPreference: visibilityPreference,
            filter: filter,
            sensitiveCopyPolicy: sensitiveCopyPolicy,
            securitySensitiveMessageIDs: securitySensitiveMessageIDs,
            limits: limits
        )
    }

    private func set<Element: Hashable>(insertionOrder elements: some Sequence<Element>) -> Set<Element> {
        var result: Set<Element> = []
        for element in elements {
            result.insert(element)
        }
        return result
    }

    private func mirrorRendering(_ value: Any) -> String {
        Mirror(reflecting: value).children.map { child in
            "\(child.label ?? "_"): \(String(reflecting: child.value))"
        }.joined(separator: "\n")
    }

    private func dumpRendering(_ value: Any) -> String {
        var result = ""
        dump(value, to: &result)
        return result
    }

    private func preCancelledResult(
        _ operation: @escaping @Sendable () throws -> Void
    ) async -> ThrowingBoundaryResult {
        await Task.detached { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try operation()
                return .success
            } catch let error as Workflow.WorkflowError {
                return .workflowError(error)
            } catch {
                return .otherError(String(reflecting: error))
            }
        }.value
    }

    private func threadCPUNanoseconds(_ thread: mach_port_t) -> UInt64? {
        var info = thread_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), rebound, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let seconds = UInt64(info.user_time.seconds + info.system_time.seconds)
        let microseconds = UInt64(info.user_time.microseconds + info.system_time.microseconds)
        return seconds * 1_000_000_000 + microseconds * 1_000
    }

    private func waitForThreadCPU(
        _ thread: mach_port_t,
        toReach target: UInt64
    ) async {
        while (threadCPUNanoseconds(thread) ?? target) < target {
            await Task.yield()
        }
    }

    private func limits(
        maximumRetainedItemCount: Int = OutputPaneLog.Limits.defaultMaximumEntryCount,
        maximumSelectedItemCount: Int = OutputPaneLog.Limits.defaultMaximumEntryCount,
        maximumAppendUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumRetainedUTF8Bytes: Int = OutputPaneLog.Limits.defaultMaximumUTF8Bytes,
        maximumFilterUTF8Bytes: Int = 16 * 1_024,
        maximumCopyUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 256 * 1_024 * 1_024,
        maximumAggregateWorkUnits: UInt64 = 1 * 1_024 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 64 * 1_024
    ) -> Workflow.Limits {
        Workflow.Limits(
            maximumRetainedItemCount: maximumRetainedItemCount,
            maximumSelectedItemCount: maximumSelectedItemCount,
            maximumAppendUTF8Bytes: maximumAppendUTF8Bytes,
            maximumRetainedUTF8Bytes: maximumRetainedUTF8Bytes,
            maximumFilterUTF8Bytes: maximumFilterUTF8Bytes,
            maximumCopyUTF8Bytes: maximumCopyUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits,
            maximumAggregateWorkUnits: maximumAggregateWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func selectionIDs(
        in plan: Workflow.Plan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [EntryID] {
        switch plan.receipt.result {
        case .selection(let receipt), .selectedAll(let receipt):
            return receipt.selectedMessageIDs
        default:
            XCTFail("Expected selection receipt", file: file, line: line)
            return []
        }
    }

    private func copyPayload(
        from plan: Workflow.Plan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Workflow.CopyPayload {
        guard case .replaceStateAndClipboard(_, let payload) = plan.operation else {
            XCTFail("Expected clipboard operation", file: file, line: line)
            throw TestFailure.unexpectedOperation
        }
        return payload
    }

    private func assertDisabled(
        _ intent: Workflow.Intent,
        in snapshot: Workflow.Snapshot,
        reason: Workflow.DisabledReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let state = try Workflow.commandState(for: intent, in: snapshot)
        XCTAssertEqual(state.command, intent.command, file: file, line: line)
        XCTAssertEqual(state.availability, .disabled(reason), file: file, line: line)
        XCTAssertFalse(state.isEnabled, file: file, line: line)
        XCTAssertEqual(state.disabledReason, reason, file: file, line: line)
        assertWorkflowError(
            .commandDisabled(command: intent.command, reason: reason),
            file: file,
            line: line
        ) {
            try Workflow.plan(intent, in: snapshot)
        }
    }

    private func assertWorkflowError<T>(
        _ expected: Workflow.WorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? Workflow.WorkflowError, expected, file: file, line: line)
        }
    }

    private enum TestFailure: Error {
        case unexpectedOperation
    }

    private enum ThrowingBoundaryResult: Equatable, Sendable {
        case success
        case workflowError(Workflow.WorkflowError)
        case otherError(String)
    }
}
