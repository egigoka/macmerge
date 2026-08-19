import Foundation
import XCTest

@testable import MacMergeCore

final class DirectoryPairNavigationTests: XCTestCase {
    func testUsesFilteredSortedVisibleOrderAndSkipsNonOpenableEntries() {
        let firstPair = pair("a-pair.txt", status: .different)
        let lastPair = pair("z-pair.txt", status: .different)
        let filteredPair = pair("m-filtered.txt", status: .identical)
        let folder = pair("y-folder", status: .different, kind: .directory)
        let leftOnly = oneSided("x-left-only.txt", side: .left)
        let rightOnly = oneSided("w-right-only.txt", side: .right)
        let results = directoryResults(
            [firstPair, folder, filteredPair, rightOnly, lastPair, leftOnly],
            filter: DirectoryResultFilter(statuses: [.different, .leftOnly, .rightOnly]),
            sortDescriptors: [DirectoryResultSortDescriptor(key: .path, order: .descending)],
            selectedIDs: [firstPair.id, lastPair.id]
        )

        XCTAssertEqual(
            results.visibleResults.map(\.id),
            [lastPair.id, folder.id, leftOnly.id, rightOnly.id, firstPair.id]
        )

        var navigator = DirectoryPairNavigator(results: results)

        XCTAssertEqual(navigator.visiblePairIDs, [lastPair.id, firstPair.id])
        XCTAssertEqual(navigator.selectedID, lastPair.id)
        XCTAssertEqual(navigator.selectedResult(in: results), lastPair)
        XCTAssertFalse(navigator.select(folder.id))
        XCTAssertFalse(navigator.select(leftOnly.id))
        XCTAssertFalse(navigator.select(filteredPair.id))
        XCTAssertEqual(navigator.selectedID, lastPair.id)
    }

    func testOpenabilityMatchesEveryValidStatusAndKindCombination() {
        let pairedStatuses: Set<DirectoryComparisonStatus> = [
            .pending, .identical, .different, .skipped, .error
        ]
        var cases: [(result: DirectoryResult, isOpenable: Bool)] = []

        for status in DirectoryComparisonStatus.allCases {
            for kind in DirectoryEntryKind.allCases {
                let result = matrixResult(
                    "\(status.rawValue)-\(kind.rawValue)",
                    status: status,
                    kind: kind
                )
                let isOpenable = pairedStatuses.contains(status) && kind == .file
                cases.append((result, isOpenable))
                XCTAssertEqual(
                    result.isOpenableFilePair,
                    isOpenable,
                    "Status: \(status), kind: \(kind)"
                )
            }
        }

        let results = directoryResults(cases.map(\.result))
        let navigator = DirectoryPairNavigator(results: results)
        let expectedIDs = results.visibleResults.compactMap { result in
            cases.first { $0.result.id == result.id }?.isOpenable == true ? result.id : nil
        }

        XCTAssertEqual(navigator.visiblePairIDs, expectedIDs)
    }

    func testUsesVisibleOrderForArbitrarySortDescriptorLists() {
        let pending = pair("pending.txt", status: .pending, byteCount: 10)
        let identical = pair("identical.txt", status: .identical, byteCount: 60)
        let different = pair("different.txt", status: .different, byteCount: 40)
        let folder = pair(
            "folder",
            status: .different,
            kind: .directory,
            byteCount: 20
        )
        let skipped = pair("skipped.txt", status: .skipped, byteCount: 50)
        let error = pair("error.txt", status: .error, byteCount: 30)
        let input = [skipped, folder, pending, error, identical, different]
        let expectations: [([DirectoryResultSortDescriptor], [DirectoryResult])] = [
            ([], input),
            (
                [
                    DirectoryResultSortDescriptor(key: .status, order: .descending),
                    DirectoryResultSortDescriptor(key: .leftSize)
                ],
                [error, skipped, folder, different, identical, pending]
            ),
            (
                [
                    DirectoryResultSortDescriptor(key: .leftSize),
                    DirectoryResultSortDescriptor(key: .status, order: .descending)
                ],
                [pending, folder, error, different, skipped, identical]
            )
        ]

        for (sortDescriptors, expectedVisibleResults) in expectations {
            let results = directoryResults(input, sortDescriptors: sortDescriptors)
            let navigator = DirectoryPairNavigator(results: results)

            XCTAssertEqual(results.visibleResults, expectedVisibleResults)
            XCTAssertEqual(
                navigator.visiblePairIDs,
                expectedVisibleResults.filter(\.isOpenableFilePair).map(\.id)
            )
        }
    }

    func testNoCurrentSelectionFallsBackToFirstVisibleSelectedID() {
        let selectedLater = pair("selected-later.txt", byteCount: 30)
        let selectedFirst = pair("selected-first.txt", byteCount: 20)
        let unselected = pair("unselected.txt", byteCount: 10)
        var results = directoryResults(
            [selectedLater, selectedFirst, unselected],
            sortDescriptors: [DirectoryResultSortDescriptor(key: .leftSize)],
            selectedIDs: [selectedLater.id, selectedFirst.id]
        )
        var navigator = DirectoryPairNavigator(results: results)

        XCTAssertEqual(navigator.selectedID, selectedFirst.id)
        XCTAssertTrue(navigator.select(nil))
        XCTAssertNil(navigator.selectedID)

        results.sortDescriptors = [
            DirectoryResultSortDescriptor(key: .leftSize, order: .descending)
        ]
        XCTAssertTrue(navigator.update(with: results))
        XCTAssertEqual(navigator.selectedID, selectedLater.id)
    }

    func testCommandsReportEnabledStatesAndExactDestinations() {
        let first = pair("a.txt")
        let middle = pair("b.txt")
        let last = pair("c.txt")
        let results = directoryResults([last, first, middle])
        var navigator = DirectoryPairNavigator(results: results, selectedID: middle.id)

        assertStates(navigator, first: true, previous: true, next: true, last: true)
        XCTAssertEqual(
            navigator.moveToFirst(),
            outcome(.first, from: middle.id, to: first.id)
        )
        assertStates(navigator, first: false, previous: false, next: true, last: true)
        XCTAssertNil(navigator.moveToFirst())
        XCTAssertNil(navigator.moveToPrevious())

        XCTAssertTrue(navigator.select(middle.id))
        XCTAssertEqual(
            navigator.moveToPrevious(),
            outcome(.previous, from: middle.id, to: first.id)
        )

        XCTAssertTrue(navigator.select(middle.id))
        XCTAssertEqual(
            navigator.moveToNext(),
            outcome(.next, from: middle.id, to: last.id)
        )
        assertStates(navigator, first: true, previous: true, next: false, last: false)
        XCTAssertNil(navigator.moveToNext())
        XCTAssertNil(navigator.moveToLast())

        XCTAssertTrue(navigator.select(middle.id))
        XCTAssertEqual(
            navigator.moveToLast(),
            outcome(.last, from: middle.id, to: last.id)
        )
        XCTAssertEqual(navigator.currentID, last.id)
        XCTAssertEqual(navigator.selectedResult(in: results), last)
    }

    func testCommandsWithoutSelectionStartAtExpectedEnds() {
        let first = pair("a.txt")
        let middle = pair("b.txt")
        let last = pair("c.txt")
        let results = directoryResults([middle, last, first])
        let expectations: [(DirectoryPairNavigationCommand, DirectoryResult.ID)] = [
            (.first, first.id),
            (.previous, last.id),
            (.next, first.id),
            (.last, last.id)
        ]

        for (command, expectedID) in expectations {
            var navigator = DirectoryPairNavigator(results: results)

            assertStates(navigator, first: true, previous: true, next: true, last: true)
            XCTAssertEqual(
                navigator.move(command),
                outcome(command, from: nil, to: expectedID),
                "Command: \(command)"
            )
        }
    }

    func testSelectingNilClearsCurrentSelectionAndRestoresNoSelectionBehavior() {
        let first = pair("a.txt")
        let middle = pair("b.txt")
        let last = pair("c.txt")
        let results = directoryResults([middle, last, first])
        var navigator = DirectoryPairNavigator(results: results, selectedID: middle.id)

        XCTAssertTrue(navigator.select(nil))
        XCTAssertNil(navigator.selectedID)
        XCTAssertNil(navigator.currentID)
        XCTAssertNil(navigator.selectedResult(in: results))
        XCTAssertFalse(navigator.select(nil))
        assertStates(navigator, first: true, previous: true, next: true, last: true)
        XCTAssertEqual(
            navigator.moveToPrevious(),
            outcome(.previous, from: nil, to: last.id)
        )
    }

    func testWrapsPreviousAndNextOnlyAcrossMultiResultBoundaries() {
        let first = pair("a.txt")
        let middle = pair("b.txt")
        let last = pair("c.txt")
        let results = directoryResults([last, middle, first])
        var navigator = DirectoryPairNavigator(
            results: results,
            selectedID: first.id,
            wrap: true
        )

        assertStates(navigator, first: false, previous: true, next: true, last: true)
        XCTAssertEqual(
            navigator.moveToPrevious(),
            outcome(.previous, from: first.id, to: last.id, didWrap: true)
        )
        assertStates(navigator, first: true, previous: true, next: true, last: false)
        XCTAssertEqual(
            navigator.moveToNext(),
            outcome(.next, from: last.id, to: first.id, didWrap: true)
        )

        XCTAssertNil(navigator.moveToFirst())
        XCTAssertEqual(
            navigator.moveToLast(),
            outcome(.last, from: first.id, to: last.id, didWrap: false)
        )
        XCTAssertTrue(navigator.select(middle.id))
        XCTAssertEqual(
            navigator.moveToNext(),
            outcome(.next, from: middle.id, to: last.id, didWrap: false)
        )
    }

    func testUpdatePreservesSelectionAcrossReorderAndRemapsAfterFilterAndDeletion() {
        let first = pair("a.txt", status: .identical)
        let middle = pair("b.txt", status: .different)
        let last = pair("c.txt", status: .identical)
        var results = directoryResults([last, first, middle])
        var navigator = DirectoryPairNavigator(results: results, selectedID: middle.id)

        results.sortDescriptors = [
            DirectoryResultSortDescriptor(key: .path, order: .descending)
        ]
        XCTAssertFalse(navigator.update(with: results))
        XCTAssertEqual(navigator.visiblePairIDs, [last.id, middle.id, first.id])
        XCTAssertEqual(navigator.selectedID, middle.id)

        results.filter = DirectoryResultFilter(statuses: [.identical])
        XCTAssertTrue(navigator.update(with: results))
        XCTAssertEqual(navigator.visiblePairIDs, [last.id, first.id])
        XCTAssertEqual(navigator.selectedID, first.id)
        XCTAssertEqual(navigator.selectedResult(in: results), first)

        results.replaceResults([last])
        XCTAssertTrue(navigator.update(with: results))
        XCTAssertEqual(navigator.visiblePairIDs, [last.id])
        XCTAssertEqual(navigator.selectedID, last.id)
        XCTAssertEqual(navigator.selectedResult(in: results), last)
    }

    func testUpdateUsesPriorOrdinalThenNewLastWhenSelectedResultIsDeleted() {
        let first = pair("a.txt")
        let selected = pair("b.txt")
        let successor = pair("c.txt")
        let last = pair("d.txt")
        var results = directoryResults([first, selected, successor, last])
        var navigator = DirectoryPairNavigator(results: results, selectedID: selected.id)

        results.replaceResults([first, successor, last])
        XCTAssertTrue(navigator.update(with: results))
        XCTAssertEqual(navigator.selectedID, successor.id)

        XCTAssertTrue(navigator.select(last.id))
        results.replaceResults([first, successor])
        XCTAssertTrue(navigator.update(with: results))
        XCTAssertEqual(navigator.selectedID, successor.id)
    }

    func testEquivalentPathIDsDoNotDuplicateNavigationOrChangeSelection() {
        let leftID = DirectoryResult.ID(leftRelativePath: "same.txt", rightRelativePath: nil)
        let rightID = DirectoryResult.ID(leftRelativePath: nil, rightRelativePath: "same.txt")
        let pairID = DirectoryResult.ID(
            leftRelativePath: "same.txt",
            rightRelativePath: "same.txt"
        )
        let duplicatePathIDs = [leftID, rightID, pairID]
        let same = pair("same.txt")
        let other = pair("z-other.txt")
        let results = directoryResults([other, same])
        var navigator = DirectoryPairNavigator(results: results, selectedID: leftID)

        XCTAssertEqual(Set(duplicatePathIDs).count, 1)
        XCTAssertEqual(navigator.visiblePairIDs, [same.id, other.id])
        XCTAssertEqual(navigator.selectedID, pairID)
        XCTAssertFalse(navigator.select(rightID))
        XCTAssertEqual(navigator.selectedResult(in: results), same)
        XCTAssertEqual(
            navigator.moveToNext(),
            outcome(.next, from: pairID, to: other.id)
        )
    }

    func testEmptyResultsDisableEveryCommandAndClearSelectionOnUpdate() {
        let unavailableID = pair("missing.txt").id
        let emptyResults = directoryResults([])
        var navigator = DirectoryPairNavigator(results: emptyResults, selectedID: unavailableID)

        XCTAssertTrue(navigator.visiblePairIDs.isEmpty)
        XCTAssertNil(navigator.selectedID)
        assertStates(navigator, first: false, previous: false, next: false, last: false)
        for command in DirectoryPairNavigationCommand.allCases {
            XCTAssertNil(navigator.move(command), "Command: \(command)")
        }
        XCTAssertFalse(navigator.select(unavailableID))
        XCTAssertFalse(navigator.select(nil))
        XCTAssertNil(navigator.selectedResult(in: emptyResults))

        let item = pair("item.txt")
        navigator = DirectoryPairNavigator(
            results: directoryResults([item]),
            selectedID: item.id
        )
        XCTAssertTrue(navigator.update(with: emptyResults))
        XCTAssertNil(navigator.selectedID)
        assertStates(navigator, first: false, previous: false, next: false, last: false)
    }

    func testSingleResultCanBeSelectedByEveryCommandButNeverWrapsToItself() {
        let item = pair("item.txt")
        let results = directoryResults([item])

        for command in DirectoryPairNavigationCommand.allCases {
            var navigator = DirectoryPairNavigator(results: results, wrap: true)

            assertStates(navigator, first: true, previous: true, next: true, last: true)
            XCTAssertEqual(
                navigator.move(command),
                outcome(command, from: nil, to: item.id, didWrap: false),
                "Command: \(command)"
            )
            assertStates(navigator, first: false, previous: false, next: false, last: false)
            XCTAssertNil(navigator.move(command), "Command: \(command)")
        }
    }

    private enum Side {
        case left
        case right
    }

    private func metadata(
        _ path: String,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64? = nil
    ) -> DirectoryEntryMetadata {
        DirectoryEntryMetadata(
            relativePath: path,
            kind: kind,
            byteCount: byteCount
        )
    }

    private func pair(
        _ path: String,
        status: DirectoryComparisonStatus = .different,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64? = nil
    ) -> DirectoryResult {
        DirectoryResult(
            left: metadata(path, kind: kind, byteCount: byteCount),
            right: metadata(path, kind: kind, byteCount: byteCount),
            status: status
        )
    }

    private func oneSided(_ path: String, side: Side) -> DirectoryResult {
        let entry = metadata(path)
        return DirectoryResult(
            left: side == .left ? entry : nil,
            right: side == .right ? entry : nil,
            status: side == .left ? .leftOnly : .rightOnly
        )
    }

    private func matrixResult(
        _ path: String,
        status: DirectoryComparisonStatus,
        kind: DirectoryEntryKind
    ) -> DirectoryResult {
        switch status {
        case .leftOnly:
            DirectoryResult(left: metadata(path, kind: kind), right: nil, status: status)
        case .rightOnly:
            DirectoryResult(left: nil, right: metadata(path, kind: kind), status: status)
        case .typeMismatch:
            DirectoryResult(
                left: metadata(path, kind: kind),
                right: metadata(path, kind: kind == .file ? .directory : .file),
                status: status
            )
        case .pending, .identical, .different, .skipped, .error:
            pair(path, status: status, kind: kind)
        }
    }

    private func directoryResults(
        _ results: [DirectoryResult],
        filter: DirectoryResultFilter = DirectoryResultFilter(),
        sortDescriptors: [DirectoryResultSortDescriptor] = [
            DirectoryResultSortDescriptor(key: .path)
        ],
        selectedIDs: Set<DirectoryResult.ID> = []
    ) -> DirectoryResults {
        DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/left"),
            rightRoot: URL(fileURLWithPath: "/right"),
            results: results,
            filter: filter,
            sortDescriptors: sortDescriptors,
            selectedIDs: selectedIDs
        )
    }

    private func outcome(
        _ command: DirectoryPairNavigationCommand,
        from previousID: DirectoryResult.ID?,
        to selectedID: DirectoryResult.ID,
        didWrap: Bool = false
    ) -> DirectoryPairNavigationOutcome {
        DirectoryPairNavigationOutcome(
            command: command,
            previousID: previousID,
            selectedID: selectedID,
            didWrap: didWrap
        )
    }

    private func assertStates(
        _ navigator: DirectoryPairNavigator,
        first: Bool,
        previous: Bool,
        next: Bool,
        last: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = DirectoryPairNavigationCommandStates(
            first: first,
            previous: previous,
            next: next,
            last: last
        )
        XCTAssertEqual(navigator.commandStates, expected, file: file, line: line)
        XCTAssertEqual(navigator.canMoveToFirst, first, file: file, line: line)
        XCTAssertEqual(navigator.canMoveToPrevious, previous, file: file, line: line)
        XCTAssertEqual(navigator.canMoveToNext, next, file: file, line: line)
        XCTAssertEqual(navigator.canMoveToLast, last, file: file, line: line)
        for command in DirectoryPairNavigationCommand.allCases {
            XCTAssertEqual(
                navigator.isEnabled(command),
                expected[command],
                "Command: \(command)",
                file: file,
                line: line
            )
        }
    }
}
