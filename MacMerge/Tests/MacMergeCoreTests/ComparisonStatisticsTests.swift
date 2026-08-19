import XCTest
@testable import MacMergeCore

final class ComparisonStatisticsTests: XCTestCase {
    func testCountsEveryRowKindAndPresentSourceSide() {
        let rows = [
            row(1, "same", 1, "same", .unchanged),
            row(2, "ignored-left", 2, "ignored-right", .unchanged),
            row(3, "left", 3, "right", .modified),
            row(nil, nil, 4, "added", .added),
            row(4, "removed", nil, nil, .removed),
            row(5, "ignored-only", nil, nil, .unchanged)
        ]

        let statistics = ComparisonStatistics(rows: rows, selectedSignificantIndex: 1)

        XCTAssertEqual(statistics.equalRowCount, 1)
        XCTAssertEqual(statistics.modifiedRowCount, 1)
        XCTAssertEqual(statistics.addedRowCount, 1)
        XCTAssertEqual(statistics.removedRowCount, 1)
        XCTAssertEqual(statistics.significantRowCount, 3)
        XCTAssertEqual(statistics.trivialRowCount, 2)
        XCTAssertEqual(statistics.leftSourceLineCount, 5)
        XCTAssertEqual(statistics.rightSourceLineCount, 4)
        XCTAssertNil(statistics.movedSourceLineCount)
        XCTAssertNil(statistics.movedDestinationLineCount)
        XCTAssertEqual(statistics.movedLineAnalysisStatus, .notRequested)
        XCTAssertEqual(statistics.selectedSignificantDifference?.index, 1)
        XCTAssertEqual(statistics.selectedSignificantDifference?.position, 2)
        XCTAssertEqual(statistics.selectedSignificantDifference?.totalCount, 3)
        requireSendable(statistics)
    }

    func testSelectedDifferenceRejectsOutOfRangeIndicesAndSaturatesPosition() {
        let rows = [row(1, "left", 1, "right", .modified)]

        XCTAssertNil(
            ComparisonStatistics(rows: rows, selectedSignificantIndex: -1)
                .selectedSignificantDifference
        )
        XCTAssertNil(
            ComparisonStatistics(rows: rows, selectedSignificantIndex: 1)
                .selectedSignificantDifference
        )
        XCTAssertEqual(
            ComparisonStatistics.SelectedSignificantDifference(index: .max, totalCount: .max).position,
            .max
        )
    }

    func testExactRowsRemainEqualAndCanonicalByteDifferencesAreTrivial() {
        let exact = row(1, "é", 1, "é", .unchanged)
        let canonicallyEquivalent = row(2, "é", 2, "e\u{301}", .unchanged)
        let unusualExact = row(Int.max, "same", -1, "same", .unchanged)

        let statistics = ComparisonStatistics(rows: [exact, canonicallyEquivalent, unusualExact])

        XCTAssertEqual(statistics.equalRowCount, 2)
        XCTAssertEqual(statistics.trivialRowCount, 1)
    }

    func testIgnoredLineEndingsAndFinalNewlineAreTrivial() throws {
        let result = try LineDiff.compareResult(
            left: "same\r\nfinal\n",
            right: "same\nfinal"
        )

        XCTAssertEqual(result.rows.map(\.kind), [.unchanged, .unchanged])
        let statistics = ComparisonStatistics(result: result)
        XCTAssertEqual(statistics.equalRowCount, 0)
        XCTAssertEqual(statistics.trivialRowCount, 2)
        XCTAssertEqual(statistics.significantRowCount, 0)
    }

    func testStrictLineEndingDifferenceIsSignificant() throws {
        let result = try LineDiff.compareResult(
            left: "same\r\n",
            right: "same\n",
            options: LineDiffOptions(ignoreLineEndings: false)
        )

        let statistics = ComparisonStatistics(result: result)
        XCTAssertEqual(statistics.equalRowCount, 0)
        XCTAssertEqual(statistics.trivialRowCount, 0)
        XCTAssertEqual(statistics.significantRowCount, 1)
    }

    func testStrictAndIgnoredEOLModesProduceSignificantVersusTrivialCounts() throws {
        let left = "equal\nstyle\r\nfinal\n"
        let right = "equal\nstyle\nfinal"
        let ignored = try LineDiff.compareResult(left: left, right: right)
        let strict = try LineDiff.compareResult(
            left: left,
            right: right,
            options: LineDiffOptions(ignoreLineEndings: false)
        )

        XCTAssertEqual(ignored.rows.map(\.kind), [.unchanged, .unchanged, .unchanged])
        let ignoredStatistics = ComparisonStatistics(result: ignored)
        XCTAssertEqual(ignoredStatistics.equalRowCount, 1)
        XCTAssertEqual(ignoredStatistics.trivialRowCount, 2)
        XCTAssertEqual(ignoredStatistics.significantRowCount, 0)

        XCTAssertEqual(strict.rows.map(\.kind), [.unchanged, .modified, .modified])
        let strictStatistics = ComparisonStatistics(result: strict)
        XCTAssertEqual(strictStatistics.equalRowCount, 1)
        XCTAssertEqual(strictStatistics.trivialRowCount, 0)
        XCTAssertEqual(strictStatistics.modifiedRowCount, 2)
        XCTAssertEqual(strictStatistics.significantRowCount, 2)
    }

    func testIgnoredContentAndMissingSidesAreTrivial() throws {
        let caseResult = try LineDiff.compareResult(
            left: "Alpha\n",
            right: "alpha\n",
            options: LineDiffOptions(ignoreCase: true)
        )
        let filteredResult = try LineDiff.compareResult(
            left: "head\n# ignored\ntail",
            right: "head\ntail",
            options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: #"^# "#)])
        )

        XCTAssertEqual(ComparisonStatistics(result: caseResult).trivialRowCount, 1)
        let filtered = ComparisonStatistics(result: filteredResult)
        XCTAssertEqual(filtered.equalRowCount, 2)
        XCTAssertEqual(filtered.trivialRowCount, 1)
        XCTAssertEqual(filtered.leftSourceLineCount, 3)
        XCTAssertEqual(filtered.rightSourceLineCount, 2)
    }

    func testMovedCountsComeFromDirectionalMetadata() throws {
        let result = try LineDiff.compareResult(
            left: "root\nA\nX\nB\nstable 1\nstable 2\nstable 3\nstable 4\nstable 5\nstable 6\nstable 7\ntail",
            right: "root\nstable 1\nstable 2\nstable 3\nA\nX\nstable 4\nstable 5\nstable 6\nX\nB\nstable 7\ntail",
            options: LineDiffOptions(detectMovedBlocks: true)
        )

        let statistics = ComparisonStatistics(result: result)
        XCTAssertEqual(statistics.movedSourceLineCount, 3)
        XCTAssertEqual(statistics.movedDestinationLineCount, 4)
        XCTAssertEqual(statistics.movedLineAnalysisStatus, .available)
        XCTAssertEqual(statistics, ComparisonStatistics(result: result))
    }

    func testMovedCountsDistinguishUnavailableAnalysisFromCompletedZero() {
        let unavailable = ComparisonStatistics(
            result: LineDiffResult(
                rows: [],
                movedLines: MovedLines(),
                movedLineAnalysisStatus: .unavailableWithinResourceLimits
            )
        )
        let completed = ComparisonStatistics(
            result: LineDiffResult(
                rows: [],
                movedLines: MovedLines(),
                movedLineAnalysisStatus: .available
            )
        )

        XCTAssertEqual(unavailable.movedLineAnalysisStatus, .unavailableWithinResourceLimits)
        XCTAssertNil(unavailable.movedSourceLineCount)
        XCTAssertNil(unavailable.movedDestinationLineCount)
        XCTAssertEqual(completed.movedLineAnalysisStatus, .available)
        XCTAssertEqual(completed.movedSourceLineCount, 0)
        XCTAssertEqual(completed.movedDestinationLineCount, 0)
    }

    func testCalculateThrowsCancellationForPreCancelledLargeRows() async {
        let rows = Array(repeating: row(1, "same", 1, "same", .unchanged), count: 8_193)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ComparisonStatistics.calculate(rows: rows)
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCalculateChecksCancellationPeriodicallyInFlight() async {
        let rows = Array(repeating: row(1, "same", 1, "same", .unchanged), count: 8_193)
        let observer = CancellationCheckObserver(cancelAt: 4_096)
        let task = Task.detached {
            try ComparisonStatistics.calculate(
                rows: rows,
                cancellationCheckObserver: { observer.observe(at: $0) }
            )
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(observer.indices, [0, 4_096])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnchangedSourceBackedRowsUseByteIdentityForClassification() throws {
        let result = try LineDiff.compareResult(
            left: "é\nstable",
            right: "e\u{301}\nstable",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "^é$", replacement: "same"),
                SubstitutionRule(pattern: "^e\u{301}$", replacement: "same")
            ])
        )

        XCTAssertEqual(result.rows.map(\.kind), [.unchanged, .unchanged])
        XCTAssertTrue(result.rows.allSatisfy(\.usesSourceTextStorage))
        XCTAssertEqual(result.rows[0].left?.text, result.rows[0].right?.text)
        XCTAssertNotEqual(
            Array(result.rows[0].left?.text.utf8 ?? "".utf8),
            Array(result.rows[0].right?.text.utf8 ?? "".utf8)
        )

        let statistics = ComparisonStatistics(result: result)
        XCTAssertEqual(statistics.equalRowCount, 1)
        XCTAssertEqual(statistics.trivialRowCount, 1)
        XCTAssertEqual(statistics.significantRowCount, 0)
    }

    func testEqualRowsCarryExactRecordSemanticsWhenDetached() async throws {
        let sourceRows = try LineDiff.compareResult(
            left: "same\r\nexact\n",
            right: "same\nexact\n"
        ).rows
        let detachedRows = await Task.detached { sourceRows }.value

        XCTAssertEqual(detachedRows, sourceRows)
        XCTAssertEqual(Set(detachedRows), Set(sourceRows))
        XCTAssertFalse(detachedRows[0].hasEqualSourceRecords)
        XCTAssertTrue(detachedRows[1].hasEqualSourceRecords)
        XCTAssertEqual(
            ComparisonStatistics(rows: detachedRows),
            ComparisonStatistics(rows: sourceRows)
        )

        let reconstructed = DiffRow(
            left: sourceRows[0].left,
            right: sourceRows[0].right,
            kind: sourceRows[0].kind
        )
        XCTAssertNotEqual(reconstructed, sourceRows[0])
        XCTAssertNotEqual(Set([reconstructed]), Set([sourceRows[0]]))
    }

    private func row(
        _ leftNumber: Int?,
        _ leftText: String?,
        _ rightNumber: Int?,
        _ rightText: String?,
        _ kind: DiffKind
    ) -> DiffRow {
        DiffRow(
            left: line(number: leftNumber, text: leftText),
            right: line(number: rightNumber, text: rightText),
            kind: kind
        )
    }

    private func line(number: Int?, text: String?) -> DiffLine? {
        guard let number, let text else { return nil }
        return DiffLine(number: number, text: text)
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }

}

private final class CancellationCheckObserver: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAt: Int
    private var observedIndices: [Int] = []

    init(cancelAt: Int) {
        self.cancelAt = cancelAt
    }

    var indices: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return observedIndices
    }

    func observe(at index: Int) {
        lock.lock()
        observedIndices.append(index)
        lock.unlock()
        if index == cancelAt {
            withUnsafeCurrentTask { $0?.cancel() }
        }
    }
}
