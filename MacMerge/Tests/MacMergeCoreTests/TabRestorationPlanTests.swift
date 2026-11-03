import Foundation
import MacMergeCore
import XCTest

final class TabRestorationPlanTests: XCTestCase {
    typealias Plan = TabRestorationPlan
    typealias PlanError = TabRestorationPlanError
    typealias Lifecycle = ComparisonTabLifecycle

    func testDefaultEncodeOmitsOptionalKeysAndRoundTrips() throws {
        let snapshot = try snapshot(
            selectedWindow: nil,
            width: .automatic,
            windows: [
                snapshotWindow(
                    1,
                    selected: 1,
                    tabs: [try snapshotTab(1), try snapshotTab(2, title: "Second")]
                )
            ]
        )

        let data = try Plan.encodeSnapshot(snapshot)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("vetoReason"))
        XCTAssertFalse(json.contains("tabbingReason"))
        XCTAssertFalse(json.contains("selectedWindowID"))
        XCTAssertFalse(json.contains("tabWidth"))
        XCTAssertEqual(try Plan.decodeSnapshot(from: data), snapshot)
        let reencoded = try Plan.encodeSnapshot(snapshot)
        let second = try Plan.decodeSnapshot(from: reencoded)
        XCTAssertEqual(second, snapshot)
    }

    func testEmptyTabsReject() throws {
        let empty = snapshotWindow(1, selected: 1, tabs: [])
        let snapshot = try snapshot(selectedWindow: nil, windows: [])
        let badSnapshot = Plan.Snapshot(
            ownerID: snapshot.ownerID,
            expectedEpoch: snapshot.expectedEpoch,
            sessionRevision: snapshot.sessionRevision,
            selectedWindowID: windowID(1),
            windows: [empty]
        )

        XCTAssertThrowsError(try Plan.decodeSnapshot(from: Plan.encodeSnapshot(badSnapshot))) {
            XCTAssertEqual($0 as? PlanError, .malformedPersistence)
        }
        XCTAssertThrowsError(try Plan.plan(badSnapshot)) {
            XCTAssertEqual($0 as? PlanError, .restoration(.emptyWindow(windowID(1))))
        }
    }

    func testTitlePrechecksRunBeforeSessionDecode() throws {
        let badSession = Data([0xFF])
        let emptyTitle = Plan.Snapshot(
            ownerID: ownerID(1),
            expectedEpoch: 0,
            sessionRevision: revision(lineage: 1, generation: 0),
            selectedWindowID: windowID(1),
            windows: [
                Plan.SnapshotWindow(
                    id: windowID(1),
                    generation: 0,
                    selectedTabID: tabID(1),
                    tabs: [Plan.SnapshotTab(id: tabID(1), title: "", session: badSession)]
                )
            ]
        )
        XCTAssertThrowsError(try Plan.plan(emptyTitle)) {
            XCTAssertEqual($0 as? PlanError, .restoration(.invalidTitle))
        }

        let oversized = String(repeating: "x", count: Lifecycle.Limits.hardMaximumTitleUTF8Bytes + 1)
        let bigTitle = Plan.Snapshot(
            ownerID: ownerID(1),
            expectedEpoch: 0,
            sessionRevision: revision(lineage: 1, generation: 0),
            selectedWindowID: windowID(1),
            windows: [
                Plan.SnapshotWindow(
                    id: windowID(1),
                    generation: 0,
                    selectedTabID: tabID(1),
                    tabs: [Plan.SnapshotTab(id: tabID(1), title: oversized, session: badSession)]
                )
            ]
        )
        XCTAssertThrowsError(try Plan.plan(bigTitle)) {
            XCTAssertEqual(
                $0 as? PlanError,
                .restoration(.titleTooLarge(maximumUTF8Bytes: Lifecycle.Limits.hardMaximumTitleUTF8Bytes))
            )
        }
        XCTAssertThrowsError(try Plan.plan(snapshotData: Plan.encodeSnapshot(emptyTitle))) {
            XCTAssertEqual($0 as? PlanError, .restoration(.invalidTitle))
        }
        XCTAssertThrowsError(try Plan.plan(snapshotData: Plan.encodeSnapshot(bigTitle))) {
            XCTAssertEqual(
                $0 as? PlanError,
                .titleTooLarge(maximumUTF8Bytes: Lifecycle.Limits.hardMaximumTitleUTF8Bytes)
            )
        }
    }

    func testDuplicatePrecheckRunsBeforeSessionDecode() throws {
        let snapshot = Plan.Snapshot(
            ownerID: ownerID(1),
            expectedEpoch: 0,
            sessionRevision: revision(lineage: 1, generation: 0),
            selectedWindowID: windowID(1),
            windows: [
                Plan.SnapshotWindow(
                    id: windowID(1),
                    generation: 0,
                    selectedTabID: tabID(1),
                    tabs: [
                        try snapshotTab(1),
                        Plan.SnapshotTab(id: tabID(1), title: "Dupe", session: Data([0xFF]))
                    ]
                )
            ]
        )
        XCTAssertThrowsError(try Plan.plan(snapshot)) {
            XCTAssertEqual($0 as? PlanError, .duplicateTabID(tabID(1)))
        }
    }

    func testVetoOrderingClosePreflightAndLiveRecheck() throws {
        let snapshot = try snapshot(
            selectedWindow: 2,
            windows: [
                snapshotWindow(
                    1,
                    selected: 3,
                    tabs: [
                        try snapshotTab(3, dirty: true, veto: .vetoed(.ownerRejected)),
                        try snapshotTab(1, dirty: true),
                        try snapshotTab(2, veto: .vetoed(.policyRestricted))
                    ]
                ),
                snapshotWindow(
                    2,
                    selected: 5,
                    tabs: [try snapshotTab(5), try snapshotTab(4, veto: .vetoed(.activeOperation))]
                )
            ]
        )
        let reopened = try Plan.plan(snapshot)

        XCTAssertEqual(reopened.intents.map(\.tabID), [tabID(3), tabID(1), tabID(2), tabID(5), tabID(4)])
        XCTAssertEqual(reopened.intents.map(\.ordinal), [0, 1, 2, 3, 4])
        XCTAssertEqual(reopened.closePreflightTabIDs, reopened.intents.map(\.tabID).reversed())
        XCTAssertEqual(reopened.dirtyTabIDs, [tabID(1), tabID(3)])
        XCTAssertEqual(reopened.vetoedTabIDs, [tabID(2), tabID(3), tabID(4)])
        XCTAssertEqual(reopened.requiresConfirmationCount, 2)
        XCTAssertEqual(reopened.vetoedCount, 3)
        XCTAssertFalse(reopened.isEmpty)
        XCTAssertEqual(reopened.intents[0].windowID, windowID(1))
        XCTAssertTrue(reopened.intents[0].isSelectedTab)
        XCTAssertFalse(reopened.intents[0].isSelectedWindow)
        XCTAssertTrue(reopened.intents[3].isSelectedWindow)
        XCTAssertTrue(reopened.intents[3].isSelectedTab)
        XCTAssertTrue(reopened.intents[0].isVetoed)
        XCTAssertFalse(reopened.intents[1].isVetoed)
        XCTAssertTrue(reopened.liveRequiresConfirmation(for: reopened.intents[1], liveDirtyTabIDs: []))
        XCTAssertFalse(reopened.liveRequiresConfirmation(for: reopened.intents[3], liveDirtyTabIDs: []))
        XCTAssertTrue(
            reopened.liveRequiresConfirmation(for: reopened.intents[3], liveDirtyTabIDs: [tabID(5)])
        )
    }

    func testCASAndSessionRevisionRevalidation() throws {
        let snapshot = try snapshot(
            selectedWindow: 1,
            windows: [snapshotWindow(1, selected: 1, tabs: [try snapshotTab(1)])]
        )
        let reopened = try Plan.plan(snapshot)

        XCTAssertNoThrow(try reopened.validate(ownerID: ownerID(1), epoch: 0))
        XCTAssertNoThrow(try reopened.validate(sessionRevision: snapshot.sessionRevision))
        XCTAssertThrowsError(try reopened.validate(ownerID: ownerID(1), epoch: 1)) {
            XCTAssertEqual(
                $0 as? PlanError,
                .restoration(
                    .staleRestorationPublication(
                        expectedOwnerID: ownerID(1),
                        expectedEpoch: 0,
                        actualOwnerID: ownerID(1),
                        actualEpoch: 1
                    )
                )
            )
        }
        XCTAssertThrowsError(try reopened.validate(ownerID: ownerID(2), epoch: 0)) {
            XCTAssertEqual(
                $0 as? PlanError,
                .restoration(
                    .staleRestorationPublication(
                        expectedOwnerID: ownerID(1),
                        expectedEpoch: 0,
                        actualOwnerID: ownerID(2),
                        actualEpoch: 0
                    )
                )
            )
        }
        let other = revision(lineage: 1, generation: 99)
        XCTAssertThrowsError(try reopened.validate(sessionRevision: other)) {
            XCTAssertEqual(
                $0 as? PlanError,
                .staleSessionRevision(expected: snapshot.sessionRevision, actual: other)
            )
        }
    }

    func testEmptySnapshotProducesZeroIntents() throws {
        let snapshot = try snapshot(selectedWindow: nil, windows: [])
        let reopened = try Plan.plan(snapshot)
        let roundTripped = try Plan.plan(snapshotData: Plan.encodeSnapshot(snapshot))

        for plan in [reopened, roundTripped] {
            XCTAssertTrue(plan.intents.isEmpty)
            XCTAssertTrue(plan.isEmpty)
            XCTAssertEqual(plan.closePreflightTabIDs, [])
            XCTAssertEqual(plan.dirtyTabIDs, [])
            XCTAssertEqual(plan.vetoedTabIDs, [])
            XCTAssertEqual(plan.requiresConfirmationCount, 0)
            XCTAssertEqual(plan.vetoedCount, 0)
            XCTAssertNil(plan.selectedWindowID)
            XCTAssertEqual(plan.restoration.materializations, [])
        }
    }

    func testMaxEpochRejectsBeforePlanning() throws {
        let snapshot = Plan.Snapshot(
            ownerID: ownerID(1),
            expectedEpoch: UInt64.max,
            sessionRevision: revision(lineage: 1, generation: 0),
            selectedWindowID: windowID(1),
            windows: [snapshotWindow(1, selected: 1, tabs: [try snapshotTab(1)])]
        )
        XCTAssertThrowsError(try Plan.plan(snapshot)) {
            XCTAssertEqual($0 as? PlanError, .restoration(.restorationPublicationEpochExhausted(ownerID(1))))
        }
        XCTAssertThrowsError(try Plan.plan(snapshotData: Plan.encodeSnapshot(snapshot))) {
            XCTAssertEqual($0 as? PlanError, .restoration(.restorationPublicationEpochExhausted(ownerID(1))))
        }
    }

    func testDanglingSelectedWindowThrows() throws {
        let snapshot = try snapshot(
            selectedWindow: 9,
            windows: [snapshotWindow(1, selected: 1, tabs: [try snapshotTab(1)])]
        )
        XCTAssertThrowsError(try Plan.plan(snapshot)) {
            XCTAssertEqual($0 as? PlanError, .restoration(.selectedWindowNotFound(windowID(9))))
        }
        XCTAssertThrowsError(try Plan.plan(snapshotData: Plan.encodeSnapshot(snapshot))) {
            XCTAssertEqual($0 as? PlanError, .restoration(.selectedWindowNotFound(windowID(9))))
        }
    }

    func testSnapshotDataPassthroughMatchesSnapshotPlan() throws {
        let snapshot = try snapshot(
            selectedWindow: 1,
            windows: [snapshotWindow(1, selected: 1, tabs: [try snapshotTab(1), try snapshotTab(2, title: "Second")])]
        )
        let fromSnapshot = try Plan.plan(snapshot)
        let fromData = try Plan.plan(snapshotData: Plan.encodeSnapshot(snapshot))
        XCTAssertEqual(fromData.intents, fromSnapshot.intents)
        XCTAssertEqual(fromData.closePreflightTabIDs, fromSnapshot.closePreflightTabIDs)
        XCTAssertEqual(fromData.selectedWindowID, fromSnapshot.selectedWindowID)
        XCTAssertEqual(fromData.restoration.materializations, fromSnapshot.restoration.materializations)
    }

    func testCancellationMapsToCancelled() throws {
        let snapshot = try snapshot(
            selectedWindow: 1,
            windows: [snapshotWindow(1, selected: 1, tabs: [try snapshotTab(1)])]
        )
        let data = try Plan.encodeSnapshot(snapshot)
        let cancelled: Lifecycle.CancellationCheck = { throw CancellationError() }

        XCTAssertThrowsError(try Plan.decodeSnapshot(from: data, cancellationCheck: cancelled)) {
            XCTAssertEqual($0 as? PlanError, .cancelled)
        }
        XCTAssertThrowsError(try Plan.plan(snapshotData: data, cancellationCheck: cancelled)) {
            XCTAssertEqual($0 as? PlanError, .cancelled)
        }
        XCTAssertThrowsError(try Plan.plan(snapshot, cancellationCheck: cancelled)) {
            XCTAssertEqual($0 as? PlanError, .cancelled)
        }

        let passthrough: Lifecycle.CancellationCheck = {
            throw PlanError.snapshotTooLarge(maximumBytes: 7)
        }
        XCTAssertThrowsError(try Plan.decodeSnapshot(from: data, cancellationCheck: passthrough)) {
            XCTAssertEqual($0 as? PlanError, .snapshotTooLarge(maximumBytes: 7))
        }
    }

    private func snapshotTab(
        _ rawID: UInt64,
        title: String? = nil,
        dirty: Bool = false,
        veto: Lifecycle.CloseVeto = .none
    ) throws -> Plan.SnapshotTab {
        Plan.SnapshotTab(
            id: tabID(rawID),
            title: title ?? "Tab \(rawID)",
            session: try sessionData("tab-\(rawID)"),
            isDirty: dirty,
            veto: veto
        )
    }

    private func snapshotWindow(
        _ rawID: UInt64,
        generation: UInt64 = 0,
        selected: UInt64,
        tabs: [Plan.SnapshotTab]
    ) -> Plan.SnapshotWindow {
        Plan.SnapshotWindow(
            id: windowID(rawID),
            generation: generation,
            selectedTabID: tabID(selected),
            tabs: tabs
        )
    }

    private func snapshot(
        selectedWindow: UInt64?,
        width: Lifecycle.TabWidthPreference = .automatic,
        windows: [Plan.SnapshotWindow]
    ) throws -> Plan.Snapshot {
        Plan.Snapshot(
            ownerID: ownerID(1),
            expectedEpoch: 0,
            sessionRevision: revision(lineage: 1, generation: 0),
            selectedWindowID: selectedWindow.map(windowID),
            tabWidthPreference: width,
            windows: windows
        )
    }

    private func sessionData(_ tag: String) throws -> Data {
        try ComparisonSessionState(
            left: .scratchpad("left-\(tag)"),
            right: .scratchpad("right-\(tag)"),
            windowFrame: ComparisonSessionState.WindowFrame(x: 10, y: 20, width: 800, height: 600)
        ).encodedData()
    }

    private func windowID(_ rawValue: UInt64) -> Plan.WindowID {
        Plan.WindowID(rawValue: rawValue)
    }

    private func tabID(_ rawValue: UInt64) -> Plan.TabID {
        Plan.TabID(rawValue: rawValue)
    }

    private func ownerID(_ rawValue: UInt64) -> Plan.OwnerID {
        Plan.OwnerID(rawValue: rawValue)
    }

    private func revision(lineage rawLineage: UInt64, generation: UInt64) -> Plan.SessionRevision {
        Plan.SessionRevision(
            lineage: Plan.SessionLineage(rawValue: rawLineage),
            generation: generation
        )
    }
}
