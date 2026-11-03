import Foundation
import XCTest
@testable import MacMergeCore

final class EncodingMenuSelectionTests: XCTestCase {
    private typealias EMS = EncodingMenuSelection
    private typealias Policy = EncodingSelectionPolicy
    private typealias Pane = Policy.Pane

    private func canonicalState(
        _ pane: Pane,
        text: String = "hello",
        encoding: TextFileEncoding = .utf8,
        hasBOM: Bool = false
    ) -> Policy.PaneState {
        Policy.PaneState(
            pane: pane,
            text: text,
            persistedText: text,
            persistedData: Data(text.utf8),
            encoding: encoding,
            hasByteOrderMark: hasBOM
        )
    }

    private func snapshot(_ states: [Policy.PaneState], generation: UInt64 = 7) -> EMS.DocumentSnapshot {
        EMS.DocumentSnapshot(identity: UUID(), generation: generation, paneStates: states)
    }

    // MARK: MenuChoice / BOM mapping

    func testMenuChoiceProperties() {
        let load = EMS.MenuChoice.load(.shiftJIS)
        XCTAssertEqual(load.encoding, .shiftJIS)
        XCTAssertFalse(load.isSave)
        XCTAssertNil(load.byteOrderMarkControl)

        let save = EMS.MenuChoice.save(.utf8, byteOrderMark: .include)
        XCTAssertEqual(save.encoding, .utf8)
        XCTAssertTrue(save.isSave)
        XCTAssertEqual(save.byteOrderMarkControl, .include)
    }

    func testByteOrderMarkControlPolicyMapping() {
        XCTAssertNil(EMS.ByteOrderMarkControl.preserve.policy)
        XCTAssertEqual(EMS.ByteOrderMarkControl.include.policy, .include)
        XCTAssertEqual(EMS.ByteOrderMarkControl.omit.policy, .omit)
    }

    func testPolicyChoiceMapping() {
        XCTAssertEqual(
            EMS.MenuChoice.load(.shiftJIS).policyChoice,
            Policy.Choice.load(.shiftJIS)
        )
        XCTAssertEqual(
            EMS.MenuChoice.save(.utf8, byteOrderMark: .preserve).policyChoice,
            Policy.Choice.save(.utf8, byteOrderMark: nil)
        )
        XCTAssertEqual(
            EMS.MenuChoice.save(.utf8, byteOrderMark: .include).policyChoice,
            Policy.Choice.save(.utf8, byteOrderMark: .include)
        )
        XCTAssertEqual(
            EMS.MenuChoice.save(.utf8, byteOrderMark: .omit).policyChoice,
            Policy.Choice.save(.utf8, byteOrderMark: .omit)
        )
    }

    // MARK: Planning happy paths + scope ordering

    func testLoadPlanPermittedAndRequiresReload() throws {
        let snap = snapshot([canonicalState(.left)])
        let plan = try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(
                choice: .load(.utf8),
                scope: Policy.PaneScope([.left])
            )
        ), cancellationCheck: {})
        XCTAssertNotNil(plan.policyResult.plan)
        XCTAssertTrue(plan.requiresReload)
        XCTAssertTrue(plan.requiresRescan)
        XCTAssertEqual(plan.outcomes.map(\.pane), [.left])
        XCTAssertFalse(plan.requiresCanonicalizationWarning)
        XCTAssertEqual(plan.snapshotReference, snap.reference)
    }

    func testOutcomesFollowLeftMiddleRightOrder() throws {
        let snap = snapshot([
            canonicalState(.right), canonicalState(.left), canonicalState(.middle),
        ])
        let plan = try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(
                choice: .save(.utf8, byteOrderMark: .preserve),
                scope: Policy.PaneScope([.right, .left, .middle])
            )
        ), cancellationCheck: {})
        XCTAssertEqual(plan.outcomes.map(\.pane), [.left, .middle, .right])
    }

    func testScopedPaneWithoutStateIsSkipped() throws {
        let snap = snapshot([canonicalState(.left)])
        let plan = try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(
                choice: .save(.utf8, byteOrderMark: .preserve),
                scope: Policy.PaneScope([.left, .right])
            )
        ), cancellationCheck: {})
        // Policy denies missing pane as data; planner skips it in outcomes.
        XCTAssertEqual(plan.policyResult, .denied(.paneUnavailable(.right)))
        XCTAssertEqual(plan.outcomes.map(\.pane), [.left])
    }

    // MARK: Denial as data

    func testDirtyLoadDenialReturnedAsData() throws {
        let state = Policy.PaneState(
            pane: .left, text: "edited", persistedText: "orig",
            persistedData: Data("orig".utf8), encoding: .utf8,
            hasByteOrderMark: false
        )
        let plan = try EMS.plan(EMS.Request(
            snapshot: snapshot([state]),
            selection: EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left]))
        ), cancellationCheck: {})
        XCTAssertEqual(plan.policyResult, .denied(.unsavedChangesPreventReload(.left)))
        XCTAssertNil(plan.policyResult.plan)
    }

    func testBOMUnsupportedDenialReturnedAsData() throws {
        let snap = snapshot([canonicalState(.left, encoding: .shiftJIS)])
        let plan = try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(
                choice: .save(.shiftJIS, byteOrderMark: .include),
                scope: Policy.PaneScope([.left])
            )
        ), cancellationCheck: {})
        XCTAssertEqual(plan.policyResult, .denied(.byteOrderMarkUnsupported(.shiftJIS)))
    }

    func testDirtyNoncanonicalSaveDenialReturnedAsData() throws {
        let state = Policy.PaneState(
            pane: .left, text: "hello!", persistedText: "hello",
            persistedData: Data([0xFF]), encoding: .utf8,
            hasByteOrderMark: false
        )
        XCTAssertFalse(state.hasCanonicalPersistedEncoding)
        let plan = try EMS.plan(EMS.Request(
            snapshot: snapshot([state]),
            selection: EMS.MenuSelection(
                choice: .save(.utf8, byteOrderMark: .preserve),
                scope: Policy.PaneScope([.left])
            )
        ), cancellationCheck: {})
        XCTAssertEqual(plan.policyResult, .denied(.noncanonicalDirtySource(.left, .utf8)))
    }

    // MARK: Canonicalization warning save-only gating

    func testWarningOnlyForSaveOnNoncanonicalPane() throws {
        let noncanonical = Policy.PaneState(
            pane: .left, text: "hello", persistedText: "hello",
            persistedData: Data([0xFF]), encoding: .utf8,
            hasByteOrderMark: false
        )
        XCTAssertFalse(noncanonical.hasCanonicalPersistedEncoding)

        let savePlan = try EMS.plan(EMS.Request(
            snapshot: snapshot([noncanonical]),
            selection: EMS.MenuSelection(
                choice: .save(.utf8, byteOrderMark: .preserve),
                scope: Policy.PaneScope([.left])
            )
        ), cancellationCheck: {})
        XCTAssertTrue(savePlan.requiresCanonicalizationWarning)
        XCTAssertEqual(savePlan.outcome(for: .left)?.canonicalizationWarning, true)

        let loadPlan = try EMS.plan(EMS.Request(
            snapshot: snapshot([noncanonical]),
            selection: EMS.MenuSelection(
                choice: .load(.utf8), scope: Policy.PaneScope([.left])
            )
        ), cancellationCheck: {})
        XCTAssertFalse(loadPlan.requiresCanonicalizationWarning)
        XCTAssertEqual(loadPlan.outcome(for: .left)?.canonicalizationWarning, false)
        XCTAssertNil(loadPlan.outcome(for: .right))
    }

    // MARK: Stale snapshots

    func testExpectingMismatchThrows() {
        let snap = snapshot([canonicalState(.left)])
        let other = EMS.DocumentSnapshotReference(identity: UUID(), generation: snap.generation)
        XCTAssertThrowsError(try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left]))
        ), expecting: other, cancellationCheck: {})) { error in
            XCTAssertEqual(
                error as? EMS.PlanningError,
                .staleSnapshotIdentity(expected: other.identity, actual: snap.identity)
            )
        }
        let staleGen = EMS.DocumentSnapshotReference(identity: snap.identity, generation: 999)
        XCTAssertThrowsError(try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left]))
        ), expecting: staleGen, cancellationCheck: {})) { error in
            guard case let .staleGeneration(expected, actual)? = error as? EMS.PlanningError else {
                XCTFail("expected staleGeneration, got \(String(describing: error))")
                return
            }
            XCTAssertEqual(expected, 999)
            XCTAssertEqual(actual, 7)
            XCTAssertEqual(actual, snap.generation)
        }
    }

    func testRequireCurrentSnapshotAndIsCurrent() throws {
        let snap = snapshot([canonicalState(.left)])
        let plan = try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left]))
        ), cancellationCheck: {})
        XCTAssertNoThrow(try plan.requireCurrentSnapshot(snap))
        XCTAssertTrue(try plan.isCurrent(for: snap))
        let moved = EMS.DocumentSnapshot(
            identity: snap.identity, generation: snap.generation + 1, paneStates: snap.paneStates
        )
        XCTAssertFalse(try plan.isCurrent(for: moved))
        XCTAssertThrowsError(try plan.requireCurrentSnapshot(moved))
    }

    // MARK: Bounds

    func testEmptyScopeThrows() {
        XCTAssertThrowsError(try EMS.plan(EMS.Request(
            snapshot: snapshot([canonicalState(.left)]),
            selection: EMS.MenuSelection(
                choice: .load(.utf8), scope: Policy.PaneScope(Set<Pane>())
            )
        ), cancellationCheck: {})) { error in
            XCTAssertEqual(error as? EMS.PlanningError, .emptyPaneScope)
        }
    }

    func testDuplicatePaneStateThrows() {
        let snap = snapshot([canonicalState(.left), canonicalState(.left)])
        XCTAssertThrowsError(try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left]))
        ), cancellationCheck: {})) { error in
            XCTAssertEqual(error as? EMS.PlanningError, .duplicatePaneState(.left))
        }
    }

    func testTooManyPaneStatesThrows() {
        let snap = snapshot([
            canonicalState(.left), canonicalState(.middle),
            canonicalState(.right), canonicalState(.left),
        ])
        XCTAssertThrowsError(try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left]))
        ), cancellationCheck: {})) { error in
            XCTAssertEqual(
                error as? EMS.PlanningError,
                .tooManyPaneStates(maximum: EMS.Limits.hardMaximumPaneStates)
            )
        }
    }

    func testInvalidLimitsThrow() {
        let snap = snapshot([canonicalState(.left)])
        let sel = EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left]))
        let cases: [(EMS.Limits, EMS.Limit)] = [
            (EMS.Limits(maximumPaneStates: 0), .paneStates),
            (EMS.Limits(maximumPaneStates: 99), .paneStates),
            (EMS.Limits(maximumWorkUnits: EMS.Limits.hardMaximumWorkUnits + 1), .workUnits),
            (EMS.Limits(cancellationCheckInterval: 0), .cancellationCheckInterval),
        ]
        for (limits, expectedLimit) in cases {
            XCTAssertThrowsError(try EMS.plan(
                EMS.Request(snapshot: snap, selection: sel, limits: limits),
                cancellationCheck: {}
            )) { error in
                XCTAssertEqual(error as? EMS.PlanningError, .invalidLimit(expectedLimit))
            }
        }
    }

    func testWorkLimitExceededThrows() {
        let snap = snapshot([canonicalState(.left)])
        let limits = EMS.Limits(maximumWorkUnits: 1)
        XCTAssertThrowsError(try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left])),
            limits: limits
        ), cancellationCheck: {})) { error in
            XCTAssertEqual(error as? EMS.PlanningError, .workLimitExceeded(maximumUnits: 1))
        }
    }

    // MARK: Cancellation

    func testCancellationCheckFailurePropagates() {
        struct Boom: Error {}
        let snap = snapshot([canonicalState(.left)])
        XCTAssertThrowsError(try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left]))
        ), cancellationCheck: { throw Boom() })) { error in
            XCTAssertTrue(error is Boom)
        }
        XCTAssertThrowsError(try EMS.plan(EMS.Request(
            snapshot: snap,
            selection: EMS.MenuSelection(choice: .load(.utf8), scope: Policy.PaneScope([.left]))
        ), cancellationCheck: { throw EMS.PlanningError.cancelled })) { error in
            XCTAssertEqual(error as? EMS.PlanningError, .cancelled)
        }
    }
}
