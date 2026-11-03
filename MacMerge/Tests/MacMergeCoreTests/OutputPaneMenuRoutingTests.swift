import Foundation
import MacMergeCore
import XCTest

final class OutputPaneMenuRoutingTests: XCTestCase {
    typealias Routing = OutputPaneMenuRouting
    typealias Workflow = OutputPaneWorkflow
    typealias EntryID = OutputPaneWorkflow.EntryID

    // MARK: - commandState / menuStates

    func testCommandStateEnabledToggleExposesCheckedAndAccessibility() throws {
        let snapshot = try makeSnapshot()
        let state = try Routing.commandState(for: .toggleVisibility, in: snapshot)

        XCTAssertEqual(state.command, .toggleVisibility)
        XCTAssertEqual(state.expectedSnapshot, snapshot.reference)
        XCTAssertTrue(state.isEnabled)
        XCTAssertTrue(state.canExecute)
        XCTAssertNil(state.disabledReason)
        XCTAssertEqual(state.checkedState, .off)
        XCTAssertFalse(state.isChecked)
        XCTAssertGreaterThan(state.plannedWorkUnits, 0)
        XCTAssertFalse(state.accessibilityLabel.isEmpty)
        XCTAssertFalse(state.accessibilityHint.isEmpty)
    }

    func testCommandStateDisabledSelectAllReportsReason() throws {
        let (log, _) = try makeLog([message(.info, "one")], selectedIndices: [0])
        let snapshot = try makeSnapshot(log: log)
        let state = try Routing.commandState(for: .selectAll, in: snapshot)

        XCTAssertEqual(state.command, .selectAll)
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.canExecute)
        XCTAssertEqual(state.disabledReason, .allVisibleMessagesSelected)
        XCTAssertEqual(state.accessibilityHint, "All visible output messages are already selected.")
    }

    func testMenuStatesStableOrderAndSnapshot() throws {
        let (log, _) = try makeLog([message(.info, "one")], selectedIndices: [0])
        let snapshot = try makeSnapshot(log: log)
        let states = try Routing.menuStates(in: snapshot)

        XCTAssertEqual(
            states.map(\.command),
            [.toggleVisibility, .copy, .selectAll, .clearAll]
        )
        XCTAssertTrue(states.allSatisfy { $0.expectedSnapshot == snapshot.reference })
        XCTAssertTrue(states.allSatisfy { !$0.accessibilityLabel.isEmpty })
        XCTAssertTrue(states.allSatisfy { !$0.accessibilityHint.isEmpty })
        XCTAssertTrue(states[0].isEnabled)
        XCTAssertTrue(states[1].isEnabled)
        XCTAssertFalse(states[2].isEnabled)
        XCTAssertTrue(states[3].isEnabled)
    }

    // MARK: - CAS validate

    func testValidateCurrentSnapshotAcceptsExactSnapshot() throws {
        let snapshot = try makeSnapshot()
        let routed = try Routing.plan(.toggleVisibility, in: snapshot)

        XCTAssertNoThrow(try routed.validateCurrentSnapshot(snapshot))
    }

    func testValidateCurrentSnapshotRejectsStaleRevision() throws {
        let snapshot = try makeSnapshot(revision: 7)
        let routed = try Routing.plan(.toggleVisibility, in: snapshot)
        let stale = try makeSnapshot(identity: snapshot.identity, revision: 8)

        XCTAssertThrowsError(try routed.validateCurrentSnapshot(stale)) { error in
            XCTAssertEqual(
                error as? OutputPaneMenuRoutingError,
                .workflow(.staleLog(expected: snapshot.reference, actual: stale.reference))
            )
        }
    }

    func testValidateCurrentSnapshotRejectsChangedContents() throws {
        let (expectedLog, _) = try makeLog([message(.info, "alpha")])
        let (changedLog, _) = try makeLog([message(.info, "bravo")])
        let expected = try makeSnapshot(revision: 3, log: expectedLog)
        let changed = try makeSnapshot(
            identity: expected.identity,
            revision: expected.revision,
            log: changedLog
        )
        let routed = try Routing.plan(.toggleVisibility, in: expected)

        XCTAssertThrowsError(try routed.validateCurrentSnapshot(changed)) { error in
            XCTAssertEqual(
                error as? OutputPaneMenuRoutingError,
                .workflow(.logContentsChanged(expected.reference))
            )
        }
    }

    // MARK: - Effects + contract passthrough

    func testTogglePlanEffectAndContractPassthrough() throws {
        let snapshot = try makeSnapshot()
        let routed = try Routing.plan(.toggleVisibility, in: snapshot)
        let successor = try XCTUnwrap(routed.plan.successor)

        XCTAssertEqual(routed.command, .toggleVisibility)
        XCTAssertEqual(routed.expectedSnapshot, snapshot.reference)
        XCTAssertEqual(routed.successorSnapshot, successor.reference)
        XCTAssertEqual(routed.requiredEffects, [.replaceState(successor.reference)])
        XCTAssertEqual(routed.requiredEffects, routed.plan.requiredEffects)
        XCTAssertEqual(routed.executorContract, .required)
        XCTAssertNil(routed.clipboardText)
        XCTAssertNil(routed.copySummary)
    }

    func testCopyPlanEffectOrderPutsStateBeforeClipboard() throws {
        let (log, _) = try makeLog([message(.info, "copy")], selectedIndices: [0])
        let snapshot = try makeSnapshot(log: log)
        let routed = try Routing.plan(.copy(Workflow.CopyIntent()), in: snapshot)
        let successor = try XCTUnwrap(routed.plan.successor)
        let summary = try XCTUnwrap(routed.copySummary)

        XCTAssertEqual(
            routed.requiredEffects,
            [.replaceState(successor.reference), .replaceClipboard(summary)]
        )
        XCTAssertEqual(routed.executorContract, .required)
        XCTAssertEqual(routed.clipboardText, "copy")
    }

    func testPersistencePlanPublishesPreferenceBeforeState() throws {
        let snapshot = try makeSnapshot()
        let routed = try Routing.plan(.setVisibilityPersistence(.persisted), in: snapshot)
        let successor = try XCTUnwrap(routed.plan.successor)

        XCTAssertEqual(
            routed.requiredEffects,
            [
                .storeVisibilityPreference(
                    Workflow.PersistedVisibilityPreference(visibility: .hidden)
                ),
                .replaceState(successor.reference)
            ]
        )
        XCTAssertEqual(routed.executorContract, .required)
    }

    // MARK: - Copy evidence check

    func testCopyEvidenceByteCountMatchesPayload() throws {
        let (log, _) = try makeLog(
            [message(.info, "caf\u{00E9}"), message(.info, "plain")],
            selectedIndices: [0, 1]
        )
        let snapshot = try makeSnapshot(log: log)
        let routed = try Routing.plan(.copy(Workflow.CopyIntent()), in: snapshot)
        let summary = try XCTUnwrap(routed.copySummary)
        let text = try XCTUnwrap(routed.clipboardText)

        XCTAssertEqual(summary.utf8ByteCount, text.utf8.count)
        XCTAssertEqual(text, "caf\u{00E9}\nplain")
    }

    // MARK: - Redaction / auth

    func testRedactedCopyNeverDisclosesSensitiveText() throws {
        let secret = "routing-redaction-canary"
        let (log, ids) = try makeLog(
            [message(.info, "public"), message(.error, secret)],
            selectedIndices: [0, 1]
        )
        let snapshot = try makeSnapshot(
            log: log,
            sensitiveCopyPolicy: .redact,
            securitySensitiveMessageIDs: [ids[1]]
        )
        let routed = try Routing.plan(.copy(Workflow.CopyIntent()), in: snapshot)
        let text = try XCTUnwrap(routed.clipboardText)
        let summary = try XCTUnwrap(routed.copySummary)

        XCTAssertEqual(text, "public\n\(Workflow.redactionMarker)")
        XCTAssertFalse(text.contains(secret))
        XCTAssertEqual(summary.redactedMessageCount, 1)
        XCTAssertEqual(summary.disclosedSensitiveMessageCount, 0)
        XCTAssertEqual(summary.utf8ByteCount, text.utf8.count)
    }

    func testDenyPolicyBlocksCopyAndAuthorizationGatesDisclosure() throws {
        let secret = "credential"
        let (log, ids) = try makeLog([message(.error, secret)], selectedIndices: [0])

        let deny = try makeSnapshot(
            log: log,
            sensitiveCopyPolicy: .deny,
            securitySensitiveMessageIDs: [ids[0]]
        )
        assertRoutingWorkflowError(
            .commandDisabled(
                command: .copy,
                reason: .securitySensitiveCopyDenied(messageCount: 1)
            )
        ) {
            _ = try Routing.plan(
                .copy(Workflow.CopyIntent(authorization: .explicitUserApproval)),
                in: deny
            )
        }

        let gated = try makeSnapshot(
            log: log,
            sensitiveCopyPolicy: .requireExplicitAuthorization,
            securitySensitiveMessageIDs: [ids[0]]
        )
        assertRoutingWorkflowError(
            .commandDisabled(
                command: .copy,
                reason: .securitySensitiveCopyRequiresAuthorization(messageCount: 1)
            )
        ) {
            _ = try Routing.plan(.copy(Workflow.CopyIntent()), in: gated)
        }

        let approved = try Routing.plan(
            .copy(Workflow.CopyIntent(authorization: .explicitUserApproval)),
            in: gated
        )
        XCTAssertEqual(approved.clipboardText, secret)
        XCTAssertEqual(approved.copySummary?.disclosedSensitiveMessageCount, 1)
        XCTAssertEqual(approved.copySummary?.redactedMessageCount, 0)
    }

    // MARK: - Limits

    func testMenuLimitsRejectOutOfRangeCounts() {
        for invalid in [0, -1, 65, 1_000] {
            XCTAssertThrowsError(try Routing.Limits(maximumMenuCommands: invalid).validate()) {
                error in
                XCTAssertEqual(error as? OutputPaneMenuRoutingError, .invalidLimits)
            }
        }
        XCTAssertNoThrow(try Routing.Limits(maximumMenuCommands: 1).validate())
        XCTAssertNoThrow(try Routing.Limits(maximumMenuCommands: 64).validate())
        XCTAssertEqual(Routing.Limits.default.maximumMenuCommands, 16)
    }

    func testMenuStatesEnforcesMaximumMenuCommands() throws {
        let snapshot = try makeSnapshot()

        XCTAssertEqual(try Routing.menuStates(in: snapshot).count, 4)
        XCTAssertNoThrow(
            try Routing.menuStates(in: snapshot, limits: Routing.Limits(maximumMenuCommands: 4))
        )
        XCTAssertThrowsError(
            try Routing.menuStates(in: snapshot, limits: Routing.Limits(maximumMenuCommands: 3))
        ) { error in
            XCTAssertEqual(error as? OutputPaneMenuRoutingError, .invalidLimits)
        }
    }

    func testDisabledPlanSurfacesTypedWorkflowError() throws {
        let snapshot = try makeSnapshot()

        assertRoutingWorkflowError(
            .commandDisabled(command: .clearAll, reason: .noMessages)
        ) {
            _ = try Routing.plan(.clearAll, in: snapshot)
        }
    }

    // MARK: - Cancel

    func testPreCancelledCommandStateMenuStatesAndPlanMapToCancelled() async throws {
        let (log, _) = try makeLog([message(.info, "copy")], selectedIndices: [0])
        let snapshot = try makeSnapshot(log: log)

        let stateResult = await Task { @Sendable () -> OutputPaneMenuRoutingError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Routing.commandState(for: .toggleVisibility, in: snapshot)
                return nil
            } catch let error as OutputPaneMenuRoutingError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(stateResult, .cancelled)

        let menuResult = await Task { @Sendable () -> OutputPaneMenuRoutingError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Routing.menuStates(in: snapshot)
                return nil
            } catch let error as OutputPaneMenuRoutingError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(menuResult, .cancelled)

        let planResult = await Task { @Sendable () -> OutputPaneMenuRoutingError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Routing.plan(.toggleVisibility, in: snapshot)
                return nil
            } catch let error as OutputPaneMenuRoutingError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(planResult, .cancelled)
    }

    func testPreCancelledValidateMapsToCancelled() async throws {
        let snapshot = try makeSnapshot()
        let routed = try Routing.plan(.toggleVisibility, in: snapshot)

        let result = await Task { @Sendable () -> OutputPaneMenuRoutingError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try routed.validateCurrentSnapshot(snapshot)
                return nil
            } catch let error as OutputPaneMenuRoutingError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(result, .cancelled)
    }
}

extension OutputPaneMenuRoutingTests {
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
        _ messages: [Message] = [],
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
        _ = log.setSelection(Set(selectedIndices.map { ids[$0] }))
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

    private func assertRoutingWorkflowError(
        _ expected: Workflow.WorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? OutputPaneMenuRoutingError,
                .workflow(expected),
                file: file,
                line: line
            )
        }
    }
}
