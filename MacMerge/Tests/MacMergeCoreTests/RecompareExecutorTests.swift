import Foundation
import XCTest

@testable import MacMergeCore

final class RecompareExecutorTests: XCTestCase {
    func testPlanDelegatesCapabilityToPlanner() throws {
        let supported = try RecompareExecutor.plan(
            executorRequest(sourceCount: 2, currentMode: .text, targetMode: .text)
        )
        XCTAssertEqual(supported.modePlan.currentMode, .text)
        XCTAssertEqual(supported.modePlan.targetMode, .text)

        assertExecutorError(.planningFailed(.unsupportedSourceCount(mode: .archive, count: 3))) {
            _ = try RecompareExecutor.plan(
                executorRequest(sourceCount: 3, currentMode: .archive, targetMode: .archive)
            )
        }

        let scratchpads = snapshot(
            sourceCount: 2,
            kinds: [.left: .scratchpad, .right: .scratchpad]
        )
        assertExecutorError(
            .planningFailed(
                .unsupportedSourceKind(side: .left, mode: .image, kind: .scratchpad)
            )
        ) {
            _ = try RecompareExecutor.plan(
                RecompareExecutorRequest(
                    request: RecompareModeRequest(
                        sources: scratchpads,
                        currentMode: .text,
                        targetMode: .image,
                        options: options(for: .image),
                        declaredWorkUnits: 1
                    )
                )
            )
        }

        let mismatched = snapshot(
            sourceCount: 2,
            kinds: [.left: .clipboardText, .right: .localFile]
        )
        assertExecutorError(.planningFailed(.clipboardSourcesRequireMatchingPair)) {
            _ = try RecompareExecutor.plan(
                RecompareExecutorRequest(
                    request: RecompareModeRequest(
                        sources: mismatched,
                        currentMode: .text,
                        targetMode: .text,
                        options: options(for: .text),
                        declaredWorkUnits: 1
                    )
                )
            )
        }

        let currentInvalid = snapshot(
            sourceCount: 2,
            kinds: [.left: .scratchpad, .right: .scratchpad]
        )
        assertExecutorError(
            .planningFailed(
                .unsupportedSourceKind(side: .left, mode: .image, kind: .scratchpad)
            )
        ) {
            _ = try RecompareExecutor.plan(
                RecompareExecutorRequest(
                    request: RecompareModeRequest(
                        sources: currentInvalid,
                        currentMode: .image,
                        targetMode: .text,
                        options: options(for: .text),
                        declaredWorkUnits: 1
                    )
                )
            )
        }
    }

    func testPhasesAreFrozenAtFour() throws {
        let plan = try RecompareExecutor.plan(
            executorRequest(sourceCount: 2, currentMode: .text, targetMode: .table)
        )

        XCTAssertEqual(
            plan.phases,
            [
                .validateSources,
                .validateCapabilities(currentMode: .text, targetMode: .table),
                .bindOptions(mode: .table),
                .freezeReceipt
            ]
        )
        XCTAssertEqual(plan.phases.count, 4)
        XCTAssertEqual(plan.receipt.phaseCount, 4)
        XCTAssertEqual(plan.receipt.phaseCount, plan.phases.count)
        XCTAssertEqual(plan.executorContract, .planOnlyNoMenuDocumentExecution)
    }

    func testStaleExpectedReferenceIsRejected() {
        let sources = snapshot(sourceCount: 2)
        let stale = RecompareModeSourceSnapshotReference(
            identity: sources.identity,
            generation: sources.generation + 1
        )

        assertExecutorError(
            .planningFailed(
                .staleSourceGeneration(
                    expected: stale.generation,
                    actual: sources.generation
                )
            )
        ) {
            _ = try RecompareExecutor.plan(
                RecompareExecutorRequest(request: request(sources: sources), expectedSources: stale)
            )
        }
    }

    func testPlanningErrorsWrapAsPlanningFailed() {
        assertExecutorError(
            .planningFailed(.modeOptionsMismatch(expected: .text, actual: .table))
        ) {
            _ = try RecompareExecutor.plan(
                RecompareExecutorRequest(
                    request: RecompareModeRequest(
                        sources: snapshot(sourceCount: 2),
                        currentMode: .text,
                        targetMode: .text,
                        options: options(for: .table),
                        declaredWorkUnits: 1
                    )
                )
            )
        }
    }

    func testPlanCancellationMapsToCancelled() async {
        let request = executorRequest(sourceCount: 2, currentMode: .text, targetMode: .text)
        let (gateStream, gateContinuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gateStream { break }
            return try RecompareExecutor.plan(request)
        }
        task.cancel()
        gateContinuation.finish()

        let result = await task.result
        guard case .failure(let error) = result else {
            return XCTFail("Cancelled planning unexpectedly returned a plan")
        }
        XCTAssertEqual(error as? RecompareExecutorError, .cancelled)
    }

    func testReceiptContentsMirrorModePlan() throws {
        let sources = snapshot(sourceCount: 2)
        let expectedOptions = options(for: .text)
        let modeRequest = RecompareModeRequest(
            sources: sources,
            currentMode: .binary,
            targetMode: .text,
            options: expectedOptions,
            declaredWorkUnits: 73
        )
        let plan = try RecompareExecutor.plan(RecompareExecutorRequest(request: modeRequest))

        XCTAssertEqual(plan.expectedSources, sources)
        XCTAssertEqual(plan.modePlan.receipt.sourceReference, sources.reference)
        XCTAssertEqual(plan.receipt.modeReceipt, plan.modePlan.receipt)
        XCTAssertEqual(plan.receipt.sourceReference, sources.reference)
        XCTAssertEqual(plan.receipt.sources, plan.modePlan.sources)
        XCTAssertEqual(plan.receipt.currentMode, .binary)
        XCTAssertEqual(plan.receipt.targetMode, .text)
        XCTAssertEqual(plan.receipt.options, expectedOptions)
        XCTAssertEqual(plan.receipt.declaredWorkUnits, 73)
        XCTAssertEqual(plan.receipt.planningWorkUnits, plan.modePlan.planningWorkUnits)
        XCTAssertEqual(plan.receipt.limits, modeRequest.limits)
        XCTAssertEqual(plan.receipt.phaseCount, plan.phases.count)
        XCTAssertNoThrow(try plan.requireCurrentSources(sources))
        XCTAssertTrue(try plan.isCurrent(for: sources))
        requireSendable(plan.receipt)
    }

    func testStubExecutorCompletesWithReceipt() async throws {
        let sources = snapshot(sourceCount: 2)
        let plan = try RecompareExecutor.plan(RecompareExecutorRequest(request: request(sources: sources)))

        let outcome = await RecompareStubExecutor().execute(plan, validating: sources)
        XCTAssertEqual(outcome, .completed(plan.receipt))
    }

    func testStubExecutorFailsPlanningFailedOnStaleSourcesNotCancelled() async throws {
        let sources = snapshot(sourceCount: 2)
        let plan = try RecompareExecutor.plan(RecompareExecutorRequest(request: request(sources: sources)))
        let stale = RecompareModeSourceSnapshot(
            identity: sources.identity,
            generation: sources.generation + 1,
            sources: sources.sources
        )
        XCTAssertFalse(try plan.isCurrent(for: stale))

        let outcome = await RecompareStubExecutor().execute(plan, validating: stale)
        XCTAssertEqual(
            outcome,
            .failed(.planningFailed(.staleSourceGeneration(expected: 42, actual: 43)))
        )
        XCTAssertNotEqual(outcome, .cancelled)
    }

    func testValidationFailedIsDistinctFromCancelled() {
        XCTAssertNotEqual(RecompareExecutorError.validationFailed, .cancelled)
        XCTAssertEqual(RecompareExecutorError.cancelled.errorDescription?.isEmpty, false)
        XCTAssertEqual(RecompareExecutorError.validationFailed.errorDescription?.isEmpty, false)
        XCTAssertEqual(
            RecompareExecutorError.planningFailed(.cancelled).errorDescription?.isEmpty,
            false
        )
        requireSendable(RecompareExecutorError.validationFailed)
    }

    func testStubExecutorReturnsCancelledWhenCancelled() async throws {
        let sources = snapshot(sourceCount: 2)
        let plan = try RecompareExecutor.plan(RecompareExecutorRequest(request: request(sources: sources)))
        let (gateStream, gateContinuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gateStream { break }
            return await RecompareStubExecutor().execute(plan, validating: sources)
        }
        task.cancel()
        gateContinuation.finish()

        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }

    private static let sourceSetIdentity = RecompareModeSourceSetIdentity(
        rawValue: uuid("00000000-0000-0000-0000-000000000010")
    )
    private static let leftIdentity = RecompareModeSourceIdentity(
        rawValue: uuid("00000000-0000-0000-0000-000000000011")
    )
    private static let middleIdentity = RecompareModeSourceIdentity(
        rawValue: uuid("00000000-0000-0000-0000-000000000022")
    )
    private static let rightIdentity = RecompareModeSourceIdentity(
        rawValue: uuid("00000000-0000-0000-0000-000000000033")
    )

    private func executorRequest(
        sourceCount: Int,
        currentMode: RecompareMode,
        targetMode: RecompareMode
    ) -> RecompareExecutorRequest {
        RecompareExecutorRequest(request: request(sourceCount: sourceCount, currentMode: currentMode, targetMode: targetMode))
    }

    private func request(
        sourceCount: Int,
        currentMode: RecompareMode,
        targetMode: RecompareMode
    ) -> RecompareModeRequest {
        request(sources: snapshot(sourceCount: sourceCount), currentMode: currentMode, targetMode: targetMode)
    }

    private func request(
        sources: RecompareModeSourceSnapshot,
        currentMode: RecompareMode = .text,
        targetMode: RecompareMode = .text
    ) -> RecompareModeRequest {
        RecompareModeRequest(
            sources: sources,
            currentMode: currentMode,
            targetMode: targetMode,
            options: options(for: targetMode),
            declaredWorkUnits: 1
        )
    }

    private func options(for mode: RecompareMode) -> RecompareModeOptions {
        switch mode {
        case .text:
            .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions())
        case .table:
            .table(parsing: .commaSeparated, twoWay: .default, threeWay: .default)
        case .binary:
            .binary(twoWay: BinaryComparisonOptions(), threeWay: .default)
        case .image:
            .image(loading: .default, comparison: .default)
        case .webpage:
            .webpage(twoWay: .default, threeWay: .default)
        case .archive:
            .archive(limits: .default)
        }
    }

    private func snapshot(
        sourceCount: Int,
        kinds: [ComparisonOpenSidePosition: RecompareModeSourceKind] = [:]
    ) -> RecompareModeSourceSnapshot {
        let sides: [ComparisonOpenSidePosition] =
            sourceCount == 2 ? [.left, .right] : [.left, .middle, .right]
        return RecompareModeSourceSnapshot(
            identity: Self.sourceSetIdentity,
            generation: 42,
            sources: sides.map { source($0, kind: kinds[$0] ?? .localFile) }
        )
    }

    private func source(
        _ side: ComparisonOpenSidePosition,
        kind: RecompareModeSourceKind = .localFile
    ) -> RecompareModeSourceBinding {
        switch side {
        case .left:
            RecompareModeSourceBinding(
                side: side,
                identity: Self.leftIdentity,
                revision: RecompareModeSourceRevision(rawValue: 11),
                kind: kind
            )
        case .middle:
            RecompareModeSourceBinding(
                side: side,
                identity: Self.middleIdentity,
                revision: RecompareModeSourceRevision(rawValue: 22),
                kind: kind
            )
        case .right:
            RecompareModeSourceBinding(
                side: side,
                identity: Self.rightIdentity,
                revision: RecompareModeSourceRevision(rawValue: 33),
                kind: kind
            )
        }
    }

    private func assertExecutorError(
        _ expected: RecompareExecutorError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? RecompareExecutorError, expected, file: file, line: line)
        }
    }

    private func requireSendable<T: Sendable>(_: T) {}

    private static func uuid(_ value: String) -> UUID {
        guard let result = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID")
        }
        return result
    }
}
