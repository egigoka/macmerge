import Foundation
import XCTest

@testable import MacMergeCore

final class PrintExecutorStubTests: XCTestCase {
    func testPlanBindsPreviewPhasesAndReceipt() throws {
        let snapshot = try makeSnapshot(rowCount: 3)
        let plan = try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))

        let direct = try ComparisonPrintPlanner.planPreview(
            document: snapshot.document,
            pageSetup: snapshot.pageSetup,
            layout: snapshot.layout,
            headerFooter: snapshot.headerFooter,
            pageRange: snapshot.pageRange,
            limits: snapshot.limits
        )
        XCTAssertEqual(plan.preview, direct)
        XCTAssertEqual(
            plan.phases,
            [
                .validateInputs,
                .planPreview(totalPageCount: direct.totalPageCount),
                .bindSelection(
                    firstPage: direct.selectedPageRange.firstPage,
                    lastPage: direct.selectedPageRange.lastPage
                )
            ])
        XCTAssertEqual(plan.receipt.totalPageCount, direct.totalPageCount)
        XCTAssertEqual(plan.receipt.firstPage, direct.selectedPageRange.firstPage)
        XCTAssertEqual(plan.receipt.lastPage, direct.selectedPageRange.lastPage)
        XCTAssertEqual(plan.receipt.phaseCount, plan.phases.count)
        XCTAssertEqual(plan.receipt.snapshot, ComparisonPrintExecutorSnapshotReference(snapshot))
        requireSendable(plan)
        requireSendable(plan.receipt)
    }

    func testPlanPreservesExpectedSnapshotAndReference() throws {
        let snapshot = try makeSnapshot(rowCount: 1)
        let plan = try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))

        XCTAssertEqual(plan.expectedSnapshot, snapshot)
        XCTAssertEqual(plan.receipt.snapshot.identity, snapshot.identity)
        XCTAssertEqual(plan.receipt.snapshot.generation, snapshot.generation)
        XCTAssertTrue(plan.isCurrent(snapshot))
        XCTAssertNoThrow(try plan.validateCurrentSnapshot(snapshot))
    }

    func testPlanAppliesPageRangeSelection() throws {
        let tinyNoChrome = ComparisonPrintHeaderFooter(header: nil, footer: nil, bandHeight: 0)
        let full = try makeSnapshot(
            rowCount: 10, setup: smallPageSetup(), layout: tinyLayout(), headerFooter: tinyNoChrome)
        let fullPlan = try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: full))
        XCTAssertGreaterThanOrEqual(fullPlan.preview.totalPageCount, 2)

        let range = try ComparisonPrintPageRange(firstPage: 2, lastPage: 2)
        let snapshot = try makeSnapshot(
            rowCount: 10, setup: smallPageSetup(), layout: tinyLayout(), headerFooter: tinyNoChrome,
            pageRange: range)
        let plan = try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))

        XCTAssertEqual(plan.preview.totalPageCount, fullPlan.preview.totalPageCount)
        XCTAssertEqual(plan.preview.selectedPageRange, range)
        XCTAssertEqual(plan.preview.pages.map(\.pageNumber), [2])
        XCTAssertEqual(plan.receipt.firstPage, 2)
        XCTAssertEqual(plan.receipt.lastPage, 2)
        XCTAssertEqual(plan.phases.last, .bindSelection(firstPage: 2, lastPage: 2))
    }

    func testPlanRejectsOutOfBoundsPageRange() throws {
        let probe = try ComparisonPrintExecutor.plan(
            ComparisonPrintExecutorRequest(snapshot: makeSnapshot(rowCount: 2)))
        let pageCount = probe.preview.totalPageCount
        let range = try ComparisonPrintPageRange(firstPage: pageCount + 1, lastPage: pageCount + 2)
        let snapshot = try makeSnapshot(rowCount: 2, pageRange: range)

        assertExecutorError(
            .planningFailed(
                .pageRangeOutOfBounds(
                    firstPage: range.firstPage, lastPage: range.lastPage, pageCount: pageCount
                ))
        ) {
            try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))
        }
    }

    func testPlanRejectsUnsupportedPaneCount() throws {
        var snapshot = try makeSnapshot(rowCount: 1)
        snapshot = ComparisonPrintExecutorSnapshot(
            identity: snapshot.identity,
            generation: snapshot.generation,
            document: ComparisonPrintDocument(
                title: "Single", paneTitles: ["Only"],
                rows: [ComparisonPrintRow(cells: [ComparisonPrintCell(text: "x")])]),
            pageSetup: snapshot.pageSetup
        )

        assertExecutorError(.planningFailed(.unsupportedPaneCount(1))) {
            try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))
        }
    }

    func testPlanRejectsInvalidLimits() throws {
        let snapshot = try makeSnapshot(
            rowCount: 1, limits: ComparisonPrintLimits(maximumRows: 0))

        assertExecutorError(.planningFailed(.invalidLimit(name: "maximumRows", value: 0))) {
            try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))
        }
    }

    func testPlanRejectsTooManyPagesLimit() throws {
        let snapshot = try makeSnapshot(
            rowCount: 10,
            setup: smallPageSetup(),
            layout: tinyLayout(),
            headerFooter: ComparisonPrintHeaderFooter(header: nil, footer: nil, bandHeight: 0),
            limits: ComparisonPrintLimits(maximumPages: 1))

        assertExecutorError(.planningFailed(.tooManyPages(maximum: 1))) {
            try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))
        }
    }

    func testPlanRejectsStaleExpectedIdentity() throws {
        let snapshot = try makeSnapshot(rowCount: 1)
        let stale = ComparisonPrintExecutorSnapshotReference(
            identity: UUID(), generation: snapshot.generation)

        assertExecutorError(.staleIdentity(expected: stale.identity, actual: snapshot.identity)) {
            try ComparisonPrintExecutor.plan(
                ComparisonPrintExecutorRequest(snapshot: snapshot, expectedSnapshot: stale))
        }
    }

    func testPlanRejectsStaleExpectedGeneration() throws {
        let snapshot = try makeSnapshot(rowCount: 1, generation: 7)
        let stale = ComparisonPrintExecutorSnapshotReference(
            identity: snapshot.identity, generation: 8)

        assertExecutorError(.staleGeneration(expected: 8, actual: 7)) {
            try ComparisonPrintExecutor.plan(
                ComparisonPrintExecutorRequest(snapshot: snapshot, expectedSnapshot: stale))
        }
    }

    func testPlanAcceptsMatchingExpectedSnapshot() throws {
        let snapshot = try makeSnapshot(rowCount: 1)
        let plan = try ComparisonPrintExecutor.plan(
            ComparisonPrintExecutorRequest(
                snapshot: snapshot,
                expectedSnapshot: ComparisonPrintExecutorSnapshotReference(snapshot)))

        XCTAssertEqual(plan.expectedSnapshot, snapshot)
    }

    func testPlanValidationDetectsStaleIdentityGenerationAndContents() throws {
        let snapshot = try makeSnapshot(rowCount: 1, generation: 3)
        let plan = try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))

        let otherIdentity = ComparisonPrintExecutorSnapshot(
            identity: UUID(),
            generation: 3,
            document: snapshot.document,
            pageSetup: snapshot.pageSetup
        )
        XCTAssertThrowsError(try plan.validateCurrentSnapshot(otherIdentity)) { error in
            XCTAssertEqual(
                error as? ComparisonPrintExecutorError,
                .staleIdentity(expected: snapshot.identity, actual: otherIdentity.identity))
        }
        XCTAssertFalse(plan.isCurrent(otherIdentity))

        let otherGeneration = ComparisonPrintExecutorSnapshot(
            identity: snapshot.identity,
            generation: 4,
            document: snapshot.document,
            pageSetup: snapshot.pageSetup
        )
        XCTAssertThrowsError(try plan.validateCurrentSnapshot(otherGeneration)) { error in
            XCTAssertEqual(error as? ComparisonPrintExecutorError, .staleGeneration(expected: 3, actual: 4))
        }
        XCTAssertFalse(plan.isCurrent(otherGeneration))

        let changedContents = ComparisonPrintExecutorSnapshot(
            identity: snapshot.identity,
            generation: 3,
            document: ComparisonPrintDocument(
                title: "Renamed", paneTitles: snapshot.document.paneTitles,
                rows: snapshot.document.rows),
            pageSetup: snapshot.pageSetup
        )
        XCTAssertThrowsError(try plan.validateCurrentSnapshot(changedContents)) { error in
            XCTAssertEqual(error as? ComparisonPrintExecutorError, .snapshotContentsChanged)
        }
        XCTAssertFalse(plan.isCurrent(changedContents))
    }

    func testPlanMapsCancellationToCancelledError() async throws {
        let snapshot = try makeSnapshot(rowCount: 2)
        let request = ComparisonPrintExecutorRequest(snapshot: snapshot)
        let (gateStream, gateContinuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gateStream { break }
            return try ComparisonPrintExecutor.plan(request)
        }
        task.cancel()
        gateContinuation.finish()

        let result = await task.result
        guard case .failure(let error) = result else {
            return XCTFail("Expected cancelled plan, got \(result)")
        }
        XCTAssertEqual(error as? ComparisonPrintExecutorError, .cancelled)
    }

    func testStubExecutorCompletesWithReceipt() async throws {
        let snapshot = try makeSnapshot(rowCount: 2)
        let plan = try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))

        let outcome = await ComparisonPrintStubExecutor().execute(plan, validating: snapshot)
        XCTAssertEqual(outcome, .completed(plan.receipt))
    }

    func testStubExecutorFailsOnStaleSnapshot() async throws {
        let snapshot = try makeSnapshot(rowCount: 1, generation: 5)
        let plan = try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))
        let executor = ComparisonPrintStubExecutor()

        let otherIdentity = ComparisonPrintExecutorSnapshot(
            identity: UUID(), generation: 5, document: snapshot.document,
            pageSetup: snapshot.pageSetup)
        let identityOutcome = await executor.execute(plan, validating: otherIdentity)
        XCTAssertEqual(
            identityOutcome,
            .failed(.staleIdentity(expected: snapshot.identity, actual: otherIdentity.identity)))

        let otherGeneration = ComparisonPrintExecutorSnapshot(
            identity: snapshot.identity, generation: 6, document: snapshot.document,
            pageSetup: snapshot.pageSetup)
        let generationOutcome = await executor.execute(plan, validating: otherGeneration)
        XCTAssertEqual(
            generationOutcome,
            .failed(.staleGeneration(expected: 5, actual: 6)))

        let changedContents = ComparisonPrintExecutorSnapshot(
            identity: snapshot.identity, generation: 5,
            document: ComparisonPrintDocument(
                title: "Renamed", paneTitles: snapshot.document.paneTitles,
                rows: snapshot.document.rows),
            pageSetup: snapshot.pageSetup)
        let contentsOutcome = await executor.execute(plan, validating: changedContents)
        XCTAssertEqual(
            contentsOutcome,
            .failed(.snapshotContentsChanged))
    }

    func testStubExecutorReturnsCancelledWhenCancelled() async throws {
        let snapshot = try makeSnapshot(rowCount: 1)
        let plan = try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))
        let (gateStream, gateContinuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gateStream { break }
            return await ComparisonPrintStubExecutor().execute(plan, validating: snapshot)
        }
        task.cancel()
        gateContinuation.finish()

        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testPlanOnlyContractHoldsNoAppKitSideEffects() async throws {
        let snapshot = try makeSnapshot(rowCount: 2)
        let plan = try ComparisonPrintExecutor.plan(ComparisonPrintExecutorRequest(snapshot: snapshot))

        XCTAssertEqual(plan.executorContract, .planOnlyNoAppKitPrinting)
        XCTAssertEqual(plan.executorContract.rawValue, "planOnlyNoAppKitPrinting")
        XCTAssertFalse(plan.preview.pages.isEmpty)

        let first = await ComparisonPrintStubExecutor().execute(plan, validating: snapshot)
        let second = await ComparisonPrintStubExecutor().execute(plan, validating: snapshot)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, .completed(plan.receipt))
        requireSendable(ComparisonPrintExecutorError.cancelled)
    }

    private func makeSnapshot(
        rowCount: Int,
        generation: UInt64 = 1,
        setup: ComparisonPrintPageSetup? = nil,
        layout: ComparisonPrintLayout = .default,
        headerFooter: ComparisonPrintHeaderFooter = .default,
        pageRange: ComparisonPrintPageRange? = nil,
        limits: ComparisonPrintLimits = .default
    ) throws -> ComparisonPrintExecutorSnapshot {
        ComparisonPrintExecutorSnapshot(
            generation: generation,
            document: twoPaneDocument(rowCount: rowCount),
            pageSetup: try setup ?? letterSetup(),
            layout: layout,
            headerFooter: headerFooter,
            pageRange: pageRange,
            limits: limits
        )
    }

    private func letterSetup() throws -> ComparisonPrintPageSetup {
        let bounds = ComparisonPrintRect(x: 0, y: 0, width: 612, height: 792)
        return try ComparisonPrintPageSetup(
            paperBounds: bounds,
            imageableBounds: bounds,
            margins: ComparisonPrintMargins(36)
        )
    }

    private func smallPageSetup() throws -> ComparisonPrintPageSetup {
        let bounds = ComparisonPrintRect(x: 0, y: 0, width: 30, height: 30)
        return try ComparisonPrintPageSetup(
            paperBounds: bounds,
            imageableBounds: bounds,
            margins: ComparisonPrintMargins(0)
        )
    }

    private func tinyLayout() -> ComparisonPrintLayout {
        ComparisonPrintLayout(
            characterWidth: 1,
            lineHeight: 10,
            horizontalCellPadding: 0,
            verticalCellPadding: 0,
            paneSpacing: 0,
            lineNumberColumnWidth: 0,
            paneTitleHeight: 0
        )
    }

    private func twoPaneDocument(title: String = "Document", rowCount: Int) -> ComparisonPrintDocument {
        ComparisonPrintDocument(
            title: title,
            paneTitles: ["Left", "Right"],
            rows: (0..<rowCount).map { row in
                ComparisonPrintRow(
                    left: ComparisonPrintCell(lineNumber: row + 1, text: "left \(row)"),
                    right: ComparisonPrintCell(lineNumber: row + 1, text: "right \(row)")
                )
            }
        )
    }

    private func assertExecutorError(
        _ expected: ComparisonPrintExecutorError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> ComparisonPrintExecutorPlan
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ComparisonPrintExecutorError, expected, file: file, line: line)
        }
    }

    private func requireSendable<T: Sendable>(_: T) {}
}
