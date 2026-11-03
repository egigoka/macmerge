import Foundation
import XCTest

@testable import MacMergeCore

final class RecentMenusWiringTests: XCTestCase {
    func testHistoryRowsLeadInPinnedMRUOrder() throws {
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/work/a.macmerge"))
        try history.recordProjectFile(URL(filePath: "/work/b.macmerge"))
        try history.recordProjectFile(URL(filePath: "/work/pinned.macmerge"), pinned: true)

        let presentation = try RecentMenusWiring.plan(snapshot(history: history))

        XCTAssertEqual(presentation.generation, RecentMenusWiring.Generation(rawValue: 7))
        XCTAssertEqual(presentation.rows.map(\.kind), [.projectFile, .projectFile, .projectFile])
        XCTAssertEqual(presentation.rows.map(\.isPinned), [true, false, false])
        XCTAssertEqual(presentation.rows.map(\.title), ["pinned.macmerge", "b.macmerge", "a.macmerge"])
        XCTAssertEqual(presentation.rows.map(\.subtitle), Array(repeating: "Project file", count: 3))
        XCTAssertTrue(presentation.rows.allSatisfy(\.isEnabled))
        XCTAssertEqual(presentation.omittedRowCount, 0)
        XCTAssertFalse(presentation.wasTruncated)
    }

    func testPairRowsFollowHistoryWithLeafOnlyLabels() throws {
        var history = RecentWorkspaceHistory()
        try history.recordCommonTask(.compareFiles)
        let filePair = try RecentComparisonPair(
            left: URL(filePath: "/deep/nest/alpha.txt"),
            right: URL(filePath: "/other/nest/beta.txt"),
            kind: .file
        )
        let folderPair = try RecentComparisonPair(
            left: URL(filePath: "/deep/nest/left-dir"),
            right: URL(filePath: "/other/nest/right-dir"),
            kind: .folder
        )
        let pairs = RecentComparisonPairs([filePair, folderPair], capacity: 2)

        let presentation = try RecentMenusWiring.plan(snapshot(history: history, pairs: pairs))

        XCTAssertEqual(presentation.rows.map(\.kind), [.commonTask, .pairFile, .pairFolder])
        XCTAssertEqual(presentation.rows[1].title, "alpha.txt and beta.txt")
        XCTAssertEqual(presentation.rows[1].subtitle, "File comparison")
        XCTAssertEqual(presentation.rows[2].title, "left-dir and right-dir")
        XCTAssertEqual(presentation.rows[2].subtitle, "Folder comparison")
        XCTAssertFalse(presentation.rows[1].isPinned)
        XCTAssertFalse(presentation.rows[2].isPinned)
    }

    func testTraversalAndNonFileURLsFailClosed() throws {
        let traversal = URL(string: "file:///work/../secret.macmerge")!
        let encodedTraversal = URL(string: "file:///work/%2e%2e/secret.macmerge")!
        let remote = URL(string: "https://example.invalid/work/a.macmerge")!
        let benign = URL(filePath: "/work/b.txt")

        XCTAssertThrowsError(try RecentComparisonPair(left: traversal, right: benign)) { error in
            XCTAssertNotNil(error as? RecentComparisonPairError)
        }
        XCTAssertThrowsError(try RecentComparisonPair(left: encodedTraversal, right: benign)) { error in
            XCTAssertNotNil(error as? RecentComparisonPairError)
        }
        XCTAssertThrowsError(try RecentComparisonPair(left: remote, right: benign)) { error in
            XCTAssertNotNil(error as? RecentComparisonPairError)
        }

        var history = RecentWorkspaceHistory()
        XCTAssertThrowsError(try history.recordProjectFile(traversal)) { error in
            XCTAssertEqual(error as? RecentWorkspaceHistoryError, .invalidURL)
        }
        XCTAssertEqual(history.count, 0)
    }

    func testOverLimitPathsFailClosedWithInvalidURL() throws {
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/" + String(repeating: "a", count: 2000) + ".macmerge"))
        let tightTitles = try RecentMenusWiring.Limits(maximumRows: 40, maximumWork: 1_024 * 1_024, maximumTitleBytes: 16)

        XCTAssertThrowsError(try RecentMenusWiring.plan(snapshot(history: history), limits: tightTitles)) { error in
            XCTAssertEqual(error as? RecentMenusWiringError, .invalidURL)
        }
    }

    func testFolderPairsDuplicateHistoryWhileCrossKindRowsCoexist() throws {
        let left = URL(filePath: "/shared/left")
        let right = URL(filePath: "/shared/right")
        var history = RecentWorkspaceHistory()
        try history.recordFolderComparison(left: left, right: right)
        let sameFolder = try RecentComparisonPair(left: left, right: right, kind: .folder)
        let reversedFolder = try RecentComparisonPair(left: right, right: left, kind: .folder)
        let pairs = RecentComparisonPairs([sameFolder, reversedFolder], capacity: 2)

        let presentation = try RecentMenusWiring.plan(snapshot(history: history, pairs: pairs))
        let folderRows = presentation.rows.filter { $0.kind == .folderComparison || $0.kind == .pairFolder }

        XCTAssertEqual(folderRows.map(\.kind), [.folderComparison, .pairFolder])
        XCTAssertEqual(folderRows[1].title, "right and left")

        var fileHistory = RecentWorkspaceHistory()
        try fileHistory.recordProjectFile(URL(filePath: "/work/doc.macmerge"))
        let overlapping = try RecentComparisonPair(
            left: URL(filePath: "/work/doc.macmerge"),
            right: URL(filePath: "/work/other.txt"),
            kind: .file
        )
        let mixed = try RecentMenusWiring.plan(
            snapshot(history: fileHistory, pairs: RecentComparisonPairs([overlapping], capacity: 1))
        )
        XCTAssertEqual(mixed.rows.map(\.kind), [.projectFile, .pairFile])
    }

    func testRowCapReportsOmittedCount() throws {
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/work/a.macmerge"))
        try history.recordProjectFile(URL(filePath: "/work/b.macmerge"))
        let capped = try RecentMenusWiring.Limits(maximumRows: 1)

        let presentation = try RecentMenusWiring.plan(snapshot(history: history), limits: capped)

        XCTAssertEqual(presentation.rows.count, 1)
        XCTAssertEqual(presentation.rows.map(\.title), ["b.macmerge"])
        XCTAssertEqual(presentation.omittedRowCount, 1)
        XCTAssertTrue(presentation.wasTruncated)
        XCTAssertNotNil(presentation.row(for: presentation.rows[0].id))
    }

    func testRestorationIntentRejectsUnknownRows() throws {
        var firstHistory = RecentWorkspaceHistory()
        try firstHistory.recordProjectFile(URL(filePath: "/work/a.macmerge"))
        var secondHistory = RecentWorkspaceHistory()
        try secondHistory.recordProjectFile(URL(filePath: "/work/b.macmerge"))
        let first = try RecentMenusWiring.plan(snapshot(history: firstHistory))
        let second = try RecentMenusWiring.plan(snapshot(history: secondHistory))
        let foreignID = try XCTUnwrap(second.rows.first).id

        XCTAssertNil(first.row(for: foreignID))
        XCTAssertThrowsError(try RecentMenusWiring.restorationIntent(for: foreignID, in: first)) { error in
            XCTAssertEqual(error as? RecentMenusWiringError, .unknownRow)
        }
    }

    func testRestorationIntentRejectsUnavailableRows() throws {
        for availability in [RecentWorkspaceAvailability.missing, .stale] {
            var history = RecentWorkspaceHistory()
            try history.recordProjectFile(URL(filePath: "/work/a.macmerge"), availability: availability)
            let presentation = try RecentMenusWiring.plan(snapshot(history: history))
            let rowID = try XCTUnwrap(presentation.rows.first).id

            XCTAssertFalse(presentation.rows.first!.isEnabled)
            XCTAssertThrowsError(try RecentMenusWiring.restorationIntent(for: rowID, in: presentation)) { error in
                XCTAssertEqual(error as? RecentMenusWiringError, .unavailableRow)
            }
        }
    }

    func testRestorationIntentsCarryCanonicalURLsAndTasks() throws {
        let projectURL = URL(filePath: "/work/doc.macmerge")
        let filePair = try RecentComparisonPair(
            left: URL(filePath: "/work/left.txt"),
            right: URL(filePath: "/work/right.txt"),
            kind: .file
        )
        let folderPair = try RecentComparisonPair(
            left: URL(filePath: "/work/left-dir"),
            right: URL(filePath: "/work/right-dir"),
            kind: .folder
        )
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(projectURL)
        try history.recordFolderComparison(folderPair)
        try history.recordCommonTask(.compareClipboard)
        let pairs = RecentComparisonPairs([filePair], capacity: 1)

        let presentation = try RecentMenusWiring.plan(snapshot(history: history, pairs: pairs))
        XCTAssertEqual(
            presentation.rows.map(\.kind),
            [.commonTask, .folderComparison, .projectFile, .pairFile]
        )

        XCTAssertEqual(
            try RecentMenusWiring.restorationIntent(for: presentation.rows[0].id, in: presentation),
            .performTask(.compareClipboard)
        )
        XCTAssertEqual(
            try RecentMenusWiring.restorationIntent(for: presentation.rows[1].id, in: presentation),
            .compareFolders(left: folderPair.left, right: folderPair.right)
        )
        XCTAssertEqual(
            try RecentMenusWiring.restorationIntent(for: presentation.rows[2].id, in: presentation),
            .openProject(projectURL.standardizedFileURL)
        )
        XCTAssertEqual(
            try RecentMenusWiring.restorationIntent(for: presentation.rows[3].id, in: presentation),
            .compareFiles(left: filePair.left, right: filePair.right)
        )
    }

    func testSecurityScopeFlagCoversFileBackedIntentsOnly() throws {
        let url = URL(filePath: "/work/a.txt")
        XCTAssertTrue(RecentMenusWiring.RestorationIntent.openProject(url).requiresSecurityScopeResolution)
        XCTAssertTrue(
            RecentMenusWiring.RestorationIntent.compareFiles(left: url, right: url).requiresSecurityScopeResolution
        )
        XCTAssertTrue(
            RecentMenusWiring.RestorationIntent.compareFolders(left: url, right: url).requiresSecurityScopeResolution
        )
        XCTAssertFalse(RecentMenusWiring.RestorationIntent.performTask(.compareFiles).requiresSecurityScopeResolution)
    }

    func testStaleGenerationsFailClosed() throws {
        let current = RecentMenusWiring.Generation(rawValue: 7)
        let other = RecentMenusWiring.Generation(rawValue: 8)
        let presentation = try RecentMenusWiring.plan(snapshot(history: history()))

        XCTAssertTrue(presentation.isCurrent(generation: current))
        XCTAssertFalse(presentation.isCurrent(generation: other))
        XCTAssertNoThrow(try presentation.requireCurrent(generation: current))
        XCTAssertThrowsError(try presentation.requireCurrent(generation: other)) { error in
            XCTAssertEqual(error as? RecentMenusWiringError, .staleGeneration(expected: other, actual: current))
        }
        XCTAssertThrowsError(try RecentMenusWiring.plan(snapshot(history: history()), expecting: other)) { error in
            XCTAssertEqual(error as? RecentMenusWiringError, .staleGeneration(expected: other, actual: current))
        }
        let rowID = try XCTUnwrap(presentation.rows.first).id
        XCTAssertThrowsError(
            try RecentMenusWiring.restorationIntent(for: rowID, in: presentation, expecting: other)
        ) { error in
            XCTAssertEqual(error as? RecentMenusWiringError, .staleGeneration(expected: other, actual: current))
        }
        XCTAssertEqual(
            try RecentMenusWiring.restorationIntent(for: rowID, in: presentation, expecting: current),
            .performTask(.compareFiles)
        )
    }

    func testInvalidLimitsThrow() {
        XCTAssertThrowsError(try RecentMenusWiring.Limits(maximumRows: 0)) { error in
            XCTAssertEqual(error as? RecentMenusWiringError, .invalidLimits)
        }
        XCTAssertThrowsError(
            try RecentMenusWiring.Limits(maximumRows: RecentMenusWiring.Limits.hardMaximumRows + 1)
        ) { error in
            XCTAssertEqual(error as? RecentMenusWiringError, .invalidLimits)
        }
        XCTAssertThrowsError(try RecentMenusWiring.Limits(maximumTitleBytes: 15)) { error in
            XCTAssertEqual(error as? RecentMenusWiringError, .invalidLimits)
        }
    }

    func testTinyWorkBudgetFailsClosed() throws {
        let tight = try RecentMenusWiring.Limits(maximumRows: 40, maximumWork: 1, maximumTitleBytes: 16)
        XCTAssertThrowsError(try RecentMenusWiring.plan(snapshot(history: history()), limits: tight)) { error in
            XCTAssertEqual(error as? RecentMenusWiringError, .workLimitExceeded(maximum: 1))
        }
    }

    func testPrecancelledPlanningAndRestorationReturnCancelled() async throws {
        let presentation = try RecentMenusWiring.plan(snapshot(history: history()))
        let rowID = try XCTUnwrap(presentation.rows.first).id
        let planSnapshot = snapshot(history: history())

        let planTask = Task.detached { () throws -> RecentMenusWiring.Presentation in
            withUnsafeCurrentTask { $0?.cancel() }
            return try RecentMenusWiring.plan(planSnapshot)
        }
        do {
            _ = try await planTask.value
            XCTFail("Cancelled planning unexpectedly succeeded")
        } catch let error as RecentMenusWiringError {
            XCTAssertEqual(error, .cancelled)
        }

        let intentTask = Task.detached { () throws -> RecentMenusWiring.RestorationIntent in
            withUnsafeCurrentTask { $0?.cancel() }
            return try RecentMenusWiring.restorationIntent(for: rowID, in: presentation)
        }
        do {
            _ = try await intentTask.value
            XCTFail("Cancelled restoration unexpectedly succeeded")
        } catch let error as RecentMenusWiringError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testAdaptFolderProjectAcceptsTwoSidedFolderProjects() throws {
        let project = try ComparisonProject(
            left: URL(filePath: "/work/left"),
            right: URL(filePath: "/work/right"),
            mode: .folder
        )

        let pair = try RecentMenusWiring.adaptFolderProject(project)
        let expected = try RecentComparisonPair(
            left: URL(filePath: "/work/left"),
            right: URL(filePath: "/work/right"),
            kind: .folder
        )

        XCTAssertEqual(pair, expected)
        XCTAssertEqual(pair.kind, .folder)
        XCTAssertTrue(pair.left.hasDirectoryPath)
        XCTAssertTrue(pair.right.hasDirectoryPath)
    }

    func testAdaptFolderProjectRejectsUnsupportedShapes() throws {
        let left = URL(filePath: "/work/left")
        let middle = URL(filePath: "/work/middle")
        let right = URL(filePath: "/work/right")
        let projects = try [
            ComparisonProject(left: left, right: right, mode: .text),
            ComparisonProject(left: left, right: right, mode: .folder, recursive: true),
            ComparisonProject(left: left, middle: middle, right: right, mode: .folder),
            ComparisonProject(left: left, right: right, leftReadOnly: true, mode: .folder)
        ]

        for project in projects {
            XCTAssertThrowsError(try RecentMenusWiring.adaptFolderProject(project)) { error in
                XCTAssertEqual(error as? RecentMenusWiringError, .invalidFolderProject)
            }
        }
    }

    private func snapshot(
        generation: UInt64 = 7,
        history: RecentWorkspaceHistory = RecentWorkspaceHistory(),
        pairs: RecentComparisonPairs = RecentComparisonPairs()
    ) -> RecentMenusWiring.Snapshot {
        RecentMenusWiring.Snapshot(
            generation: RecentMenusWiring.Generation(rawValue: generation),
            history: history,
            pairs: pairs
        )
    }

    private func history(project: String = "/work/a.macmerge") -> RecentWorkspaceHistory {
        var history = RecentWorkspaceHistory()
        try? history.recordProjectFile(URL(filePath: project))
        try? history.recordCommonTask(.compareFiles)
        return history
    }
}
