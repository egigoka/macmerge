import Foundation
import MacMergeCore
import XCTest

/// Focused contract tests for the UI-independent Close All (Command-Option-W) plan:
/// reverse-cycle ordering, window bound, dirty/veto handling with fail-closed live
/// recheck, the required `FileLifecycleMenuCapture.verify()` hook item, and the
/// empty/dirty/cancel paths.
final class CloseAllWindowsPlanTests: XCTestCase {
    typealias Plan = CloseAllWindowsPlan
    typealias PlanError = CloseAllWindowsPlanError
    typealias Item = FileLifecycleShortcuts.ObservedMenuItem

    func testCloseAllChordAndMenuConstants() throws {
        let expected = try Plan.Policy.Chord(.character("w"), modifiers: [.command, .option])
        XCTAssertEqual(Plan.closeAllChord, expected)
        XCTAssertEqual(Plan.menuTitle, "Close All")
        XCTAssertEqual(Plan.helpText, "Command-Option-W")
        XCTAssertEqual(Plan.maximumWindowCount, ComparisonTabLifecycle.Limits.default.maximumWindowCount)
        XCTAssertEqual(Plan.VerifyCallPlan.required.hook, .fileLifecycleMenuCaptureVerify)
        XCTAssertTrue(Plan.VerifyCallPlan.required.runAfterCloseWiring)
        XCTAssertTrue(Plan.VerifyCallPlan.required.passesWhenNoFindings)
    }

    func testPlanReversesWindowCycleOrder() throws {
        let plan = try Plan.plan(request(open: [1, 2, 3], generation: 7))
        XCTAssertEqual(plan.generation, 7)
        XCTAssertEqual(plan.steps.map(\.windowID), [windowID(3), windowID(2), windowID(1)])
        XCTAssertEqual(plan.steps.map(\.ordinal), [0, 1, 2])
        XCTAssertEqual(plan.workPerformed, 3)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertEqual(plan.dirtyCount, 0)
        XCTAssertEqual(plan.vetoedCount, 0)
        XCTAssertEqual(plan.vetoedWindowIDs, [])
        XCTAssertEqual(plan.verifyAfterCloseWiring, .required)
    }

    func testEmptyPlanHasNoStepsOrWork() throws {
        let plan = try Plan.plan(request(open: [], generation: 0))
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.steps, [])
        XCTAssertEqual(plan.workPerformed, 0)
        XCTAssertEqual(plan.dirtyCount, 0)
        XCTAssertEqual(plan.vetoedCount, 0)
        XCTAssertEqual(plan.requiresConfirmationCount, 0)
    }

    func testPlanMarksDirtyStepsAndCounts() throws {
        let plan = try Plan.plan(request(open: [1, 2, 3], dirty: [2], generation: 0))
        XCTAssertEqual(plan.dirtyCount, 1)
        XCTAssertEqual(plan.requiresConfirmationCount, 1)
        let byWindow = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.windowID, $0) })
        XCTAssertEqual(byWindow[windowID(2)]?.requiresConfirmation, true)
        XCTAssertEqual(byWindow[windowID(1)]?.requiresConfirmation, false)
        XCTAssertEqual(byWindow[windowID(3)]?.requiresConfirmation, false)
    }

    func testLiveDirtyRecheckIsFailClosed() throws {
        let plan = try Plan.plan(request(open: [1, 2], generation: 0))
        let clean = try XCTUnwrap(plan.steps.first(where: { $0.windowID == windowID(1) }))
        XCTAssertFalse(clean.requiresConfirmation)
        // Snapshot says clean but the window got dirty afterwards: still confirm.
        XCTAssertTrue(clean.liveRequiresConfirmation(liveDirtyWindowIDs: [windowID(1)]))
        XCTAssertTrue(plan.liveRequiresConfirmation(for: clean, liveDirtyWindowIDs: [windowID(1)]))
        XCTAssertFalse(
            plan.liveRequiresConfirmation(for: clean, liveDirtyWindowIDs: [windowID(2)]))
        XCTAssertFalse(plan.liveRequiresConfirmation(for: clean, liveDirtyWindowIDs: []))
    }

    func testDirtySnapshotStaysConfirmedWhenLiveSetOmitsIt() throws {
        let plan = try Plan.plan(request(open: [1], dirty: [1], generation: 0))
        let dirty = try XCTUnwrap(plan.steps.first)
        XCTAssertTrue(dirty.requiresConfirmation)
        XCTAssertTrue(plan.liveRequiresConfirmation(for: dirty, liveDirtyWindowIDs: []))
    }

    func testVetoedStepsAreMarkedNotSkipped() throws {
        let plan = try Plan.plan(
            request(
                open: [1, 2, 3],
                vetoes: [
                    windowID(3): .vetoed(.activeOperation),
                    windowID(1): .vetoed(.ownerRejected)
                ],
                generation: 0
            ))
        // All three windows still get a step in reverse-cycle order.
        XCTAssertEqual(plan.steps.map(\.windowID), [windowID(3), windowID(2), windowID(1)])
        XCTAssertTrue(plan.steps[0].isVetoed)
        XCTAssertFalse(plan.steps[1].isVetoed)
        XCTAssertTrue(plan.steps[2].isVetoed)
        XCTAssertEqual(plan.vetoedCount, 2)
        // Sorted ascending for stable diagnostics, not in close order.
        XCTAssertEqual(plan.vetoedWindowIDs, [windowID(1), windowID(3)])
    }

    func testVerifyHookPassedNeedsEmptyFindingsAndCloseAllItem() throws {
        let plan = try Plan.plan(request(open: [1], generation: 0))
        XCTAssertTrue(plan.verifyHookPassed([], observedMenuItems: [closeAllItem()]))
        XCTAssertFalse(
            plan.verifyHookPassed(
                [.catalogMissingCommand(.new)], observedMenuItems: [closeAllItem()]))
        XCTAssertFalse(plan.verifyHookPassed([], observedMenuItems: []))
        XCTAssertFalse(plan.verifyHookPassed([], observedMenuItems: [closeItem()]))
        XCTAssertFalse(
            plan.verifyHookPassed(
                [], observedMenuItems: [closeAllTitleWrongChordItem()]))
        XCTAssertFalse(
            plan.verifyHookPassed(
                [], observedMenuItems: [closeAllChordWrongTitleItem()]))
    }

    func testPlanRejectsMoreThanMaximumWindowCount() throws {
        let maxIDs = (0..<UInt64(Plan.maximumWindowCount)).map { windowID($0) }
        let maxPlan = try Plan.plan(Plan.Request(openWindowIDs: maxIDs, generation: 0))
        XCTAssertEqual(maxPlan.steps.count, Plan.maximumWindowCount)
        let ids = (0..<UInt64(Plan.maximumWindowCount + 1)).map { windowID($0) }
        assertPlanError(
            .tooManyWindows(maximum: Plan.maximumWindowCount),
            request: Plan.Request(openWindowIDs: ids, generation: 0)
        )
    }

    func testPlanRejectsDuplicateUnknownAndExhaustedGeneration() {
        assertPlanError(
            .duplicateWindowID(windowID(1)),
            request: request(open: [1, 1], generation: 0)
        )
        assertPlanError(
            .unknownDirtyWindowID(windowID(9)),
            request: request(open: [1], dirty: [9], generation: 0)
        )
        assertPlanError(
            .unknownVetoWindowID(windowID(9)),
            request: request(
                open: [1], vetoes: [windowID(9): .vetoed(.policyRestricted)], generation: 0)
        )
        assertPlanError(
            .generationExhausted,
            request: request(open: [1], generation: .max)
        )
    }

    func testPlanMapsCancellationToCancelled() {
        struct TestCancellation: Error, Sendable {}
        assertPlanError(
            .cancelled,
            request: request(open: [1], generation: 0),
            cancellationCheck: { throw TestCancellation() }
        )
        // A pass-through plan error is not rewritten.
        assertPlanError(
            .generationExhausted,
            request: request(open: [1], generation: 0),
            cancellationCheck: { throw PlanError.generationExhausted }
        )
    }

    // MARK: - Helpers

    private func windowID(_ rawValue: UInt64) -> Plan.WindowID {
        Plan.WindowID(rawValue: rawValue)
    }

    private func request(
        open: [UInt64],
        dirty: Set<UInt64> = [],
        vetoes: [Plan.WindowID: Plan.CloseVeto] = [:],
        generation: UInt64
    ) -> Plan.Request {
        Plan.Request(
            openWindowIDs: open.map(windowID),
            dirtyWindowIDs: Set(dirty.map(windowID)),
            vetoes: vetoes,
            generation: generation
        )
    }

    private func closeAllItem() -> Item {
        Item(
            title: Plan.menuTitle,
            keyEquivalent: "w",
            modifiers: [.command, .option],
            actionSelector: "closeAll:",
            location: .fileMenu
        )
    }

    private func closeItem() -> Item {
        Item(
            title: "Close",
            keyEquivalent: "w",
            modifiers: [.command],
            actionSelector: "performClose:",
            location: .fileMenu
        )
    }

    private func closeAllTitleWrongChordItem() -> Item {
        Item(
            title: Plan.menuTitle,
            keyEquivalent: "w",
            modifiers: [.command],
            actionSelector: "closeAll:",
            location: .fileMenu
        )
    }

    private func closeAllChordWrongTitleItem() -> Item {
        Item(
            title: "Close",
            keyEquivalent: "w",
            modifiers: [.command, .option],
            actionSelector: "performClose:",
            location: .fileMenu
        )
    }

    private func assertPlanError(
        _ expected: PlanError,
        request: Plan.Request,
        cancellationCheck: @escaping Plan.CancellationCheck = { try Task.checkCancellation() },
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try Plan.plan(request, cancellationCheck: cancellationCheck), file: file, line: line) {
            XCTAssertEqual($0 as? PlanError, expected, file: file, line: line)
        }
    }
}
