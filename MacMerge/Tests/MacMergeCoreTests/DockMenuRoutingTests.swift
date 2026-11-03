import Foundation
import XCTest

@testable import MacMergeCore

final class DockMenuRoutingTests: XCTestCase {
    func testSectionsFollowFileFolderProjectTaskOrderWithEmptyGroupsOmitted() throws {
        let file = try pair(1, kind: .file)
        let folder = try pair(2, kind: .folder)
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/grouping/project.macmerge"))
        try history.recordCommonTask(.compareClipboard)
        let presentation = try DockMenuRouting.plan(
            snapshot(
                recentComparisons: RecentComparisonPairs([file, folder], capacity: 2),
                workspaceHistory: history,
                commonTasks: []
            )
        )

        XCTAssertEqual(
            presentation.sections.map(\.kind),
            [.file, .folder, .project, .task]
        )
        XCTAssertEqual(presentation.section(for: .file)?.rows.count, 1)
        XCTAssertEqual(presentation.section(for: .folder)?.rows.count, 1)
        XCTAssertEqual(presentation.section(for: .project)?.rows.count, 1)
        XCTAssertEqual(presentation.section(for: .task)?.rows.count, 1)
        XCTAssertNil(
            try DockMenuRouting.plan(snapshot(commonTasks: [])).section(for: .file)
        )
    }

    func testOriginsTrackPlannerPinnedRecentAndTasksSections() throws {
        let pinnedFolder = try pair(1, kind: .folder)
        let recentFile = try pair(2, kind: .file)
        var history = RecentWorkspaceHistory()
        try history.recordFolderComparison(pinnedFolder, pinned: true)
        try history.recordProjectFile(URL(filePath: "/origins/recent.macmerge"))
        let presentation = try DockMenuRouting.plan(
            snapshot(
                recentComparisons: RecentComparisonPairs([recentFile], capacity: 1),
                workspaceHistory: history,
                commonTasks: [.compareFiles]
            )
        )

        XCTAssertEqual(
            origin(of: .folder, in: presentation),
            [.pinned]
        )
        XCTAssertEqual(
            origin(of: .project, in: presentation),
            [.recent]
        )
        XCTAssertEqual(
            origin(of: .file, in: presentation),
            [.recent]
        )
        XCTAssertEqual(
            origin(of: .task, in: presentation),
            [.tasks]
        )
    }

    func testShortcutIndicesFollowPlanOrderAndSkipUnavailableRows() throws {
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/shortcuts/first.macmerge"))
        try history.recordProjectFile(URL(filePath: "/shortcuts/second.macmerge"))
        try history.recordProjectFile(
            URL(filePath: "/shortcuts/missing.macmerge"),
            availability: .missing
        )
        let presentation = try DockMenuRouting.plan(
            snapshot(workspaceHistory: history, commonTasks: [])
        )

        XCTAssertEqual(presentation.rows.count, 3)
        let unavailable = try XCTUnwrap(presentation.rows.first(where: { !$0.isEnabled }))
        XCTAssertNil(unavailable.shortcutIndex)
        XCTAssertEqual(
            presentation.rows.filter(\.isEnabled).compactMap(\.shortcutIndex),
            [1, 2]
        )
        XCTAssertEqual(presentation.rows.compactMap(\.shortcutIndex), [1, 2])
    }

    func testShortcutBudgetCapsAtNineAndHonoursCustomLimit() throws {
        XCTAssertEqual(DockMenuRouting.Limits.hardMaximumShortcutItems, 9)
        var history = RecentWorkspaceHistory()
        for index in 0..<12 {
            try history.recordProjectFile(URL(filePath: "/budget/p\(index).macmerge"))
        }
        let full = try DockMenuRouting.plan(
            snapshot(workspaceHistory: history, commonTasks: [])
        )
        XCTAssertEqual(full.rows.compactMap(\.shortcutIndex), Array(1...9))
        XCTAssertNil(full.rows[9].shortcutIndex)

        let capped = try DockMenuRouting.plan(
            snapshot(workspaceHistory: history, commonTasks: []),
            limits: DockMenuRouting.Limits(maximumShortcutItems: 2)
        )
        XCTAssertEqual(capped.rows.compactMap(\.shortcutIndex), [1, 2])

        let none = try DockMenuRouting.plan(
            snapshot(workspaceHistory: history, commonTasks: []),
            limits: DockMenuRouting.Limits(maximumShortcutItems: 0)
        )
        XCTAssertTrue(none.rows.allSatisfy { $0.shortcutIndex == nil })
    }

    func testInvalidRoutingLimitsThrow() {
        XCTAssertThrowsError(
            try DockMenuRouting.plan(
                snapshot(),
                limits: DockMenuRouting.Limits(maximumShortcutItems: 10)
            )
        ) { error in
            XCTAssertEqual(error as? DockMenuRoutingError, .invalidLimits)
        }
        XCTAssertThrowsError(
            try DockMenuRouting.plan(
                snapshot(),
                limits: DockMenuRouting.Limits(maximumShortcutItems: -1)
            )
        ) { error in
            XCTAssertEqual(error as? DockMenuRoutingError, .invalidLimits)
        }
    }

    func testShortcutResolverReturnsRowAndRejectsUnknown() throws {
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/resolve/first.macmerge"))
        let presentation = try DockMenuRouting.plan(
            snapshot(workspaceHistory: history, commonTasks: [])
        )

        let row = try DockMenuRouting.shortcut(1, in: presentation)
        XCTAssertEqual(row.shortcutIndex, 1)
        XCTAssertEqual(row, presentation.row(for: row.id))
        XCTAssertThrowsError(try DockMenuRouting.shortcut(9, in: presentation)) { error in
            XCTAssertEqual(error as? DockMenuRoutingError, .unknownShortcut(9))
        }
    }

    func testAppRouteReturnsIntentAndRejectsUnknownAndUnavailable() throws {
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/approute/ok.macmerge"))
        try history.recordProjectFile(
            URL(filePath: "/approute/gone.macmerge"),
            availability: .missing
        )
        let presentation = try DockMenuRouting.plan(
            snapshot(workspaceHistory: history, commonTasks: [])
        )
        let enabled = try XCTUnwrap(presentation.rows.first(where: \.isEnabled))
        let disabled = try XCTUnwrap(presentation.rows.first(where: { !$0.isEnabled }))

        let intent = try DockMenuRouting.appRoute(for: enabled.id, in: presentation)
        XCTAssertEqual(intent, enabled.intent)
        guard case .openProject = intent else {
            return XCTFail("Expected project intent")
        }
        XCTAssertThrowsError(try DockMenuRouting.appRoute(for: disabled.id, in: presentation)) {
            error in
            XCTAssertEqual(error as? DockMenuRoutingError, .unavailableItem(disabled.id))
        }
        XCTAssertThrowsError(
            try DockMenuRouting.appRoute(for: enabled.id, in: try DockMenuRouting.plan(snapshot()))
        ) { error in
            XCTAssertEqual(error as? DockMenuRoutingError, .unknownItem)
        }
    }

    func testStaleGenerationRejectedBothDirections() throws {
        let actual = DockRecentTasksGeneration(rawValue: 7)
        let presentation = try DockMenuRouting.plan(snapshot(generation: 7))

        XCTAssertTrue(presentation.isCurrent(generation: actual))
        XCTAssertNoThrow(try presentation.requireCurrent(generation: actual))
        XCTAssertThrowsError(
            try DockMenuRouting.plan(
                snapshot(generation: 7),
                expecting: DockRecentTasksGeneration(rawValue: 8)
            )
        ) { error in
            XCTAssertEqual(
                error as? DockMenuRoutingError,
                .staleGeneration(
                    expected: DockRecentTasksGeneration(rawValue: 8),
                    actual: actual
                )
            )
        }
        XCTAssertThrowsError(
            try presentation.requireCurrent(
                generation: DockRecentTasksGeneration(rawValue: 6)
            )
        ) { error in
            XCTAssertEqual(
                error as? DockMenuRoutingError,
                .staleGeneration(
                    expected: DockRecentTasksGeneration(rawValue: 6),
                    actual: actual
                )
            )
        }
    }

    func testPlannerErrorsSurfaceAsRoutingCoreErrors() {
        XCTAssertThrowsError(
            try DockMenuRouting.plan(
                DockMenuRouting.Snapshot(
                    generation: DockRecentTasksGeneration(rawValue: 1),
                    bookmarkBindings: [
                        DockRecentBookmarkBinding(
                            url: URL(filePath: "/unused/binding.macmerge"),
                            reference: DockRecentBookmarkReference(
                                rawValue: UUID(uuid: (9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9))
                            )
                        )
                    ],
                    capabilities: Set(DockRecentTaskCapability.allCases)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? DockMenuRoutingError,
                .core(.unusedBookmarkReference)
            )
        }
    }

    func testRedactionKeepsPathsAndBookmarksOutOfRowsAndDiagnostics() throws {
        let secret = "DO-NOT-LEAK"
        let reference = DockRecentBookmarkReference(
            rawValue: UUID(uuid: (3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
        )
        let secretURL = URL(filePath: "/private/\(secret)/bound.macmerge")
        var boundHistory = RecentWorkspaceHistory()
        try boundHistory.recordProjectFile(secretURL)
        let presentation = try DockMenuRouting.plan(
            snapshot(
                workspaceHistory: boundHistory,
                commonTasks: [],
                bookmarkBindings: [
                    DockRecentBookmarkBinding(url: secretURL, reference: reference)
                ]
            )
        )
        let row = try XCTUnwrap(presentation.rows.first)

        XCTAssertTrue(row.hasBookmarkReference)
        XCTAssertEqual(row.label.title, "bound.macmerge")
        XCTAssertFalse(row.label.title.contains(secret))
        XCTAssertFalse(row.label.title.contains("/private"))
        XCTAssertEqual(row.description, "DockMenuRouting.Row(project:<redacted>)")
        XCTAssertEqual(
            presentation.description,
            "DockMenuRouting.Presentation(generation: 1, rowCount: 1)"
        )
        let diagnostics = [
            String(describing: row),
            String(reflecting: row),
            String(describing: presentation.sections[0]),
            String(reflecting: presentation)
        ].joined(separator: "\n")
        XCTAssertFalse(diagnostics.contains(secret))
        XCTAssertFalse(diagnostics.contains("/private"))
        XCTAssertFalse(diagnostics.contains(reference.rawValue.uuidString))
        let mirrorKeys = Set(
            Mirror(reflecting: row).children.compactMap(\.label)
        )
        XCTAssertFalse(mirrorKeys.contains("item"))
        XCTAssertFalse(mirrorKeys.contains("label"))
    }

    func testPrecancelledPlanMapsToCancelled() async {
        let snap = snapshot()
        let task = Task.detached { () -> DockMenuRouting.Presentation in
            withUnsafeCurrentTask { $0?.cancel() }
            return try DockMenuRouting.plan(snap)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled routing unexpectedly succeeded")
        } catch let error as DockMenuRoutingError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }

    func testPrecancelledResolversMapCheckCancellationToCancelled() async throws {
        let presentation = try DockMenuRouting.plan(snapshot())
        let row = try XCTUnwrap(presentation.rows.first)

        let shortcutTask = Task.detached { () -> DockMenuRouting.Row in
            withUnsafeCurrentTask { $0?.cancel() }
            return try DockMenuRouting.shortcut(1, in: presentation)
        }
        do {
            _ = try await shortcutTask.value
            XCTFail("Cancelled shortcut unexpectedly succeeded")
        } catch let error as DockMenuRoutingError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }

        let routeTask = Task.detached { () -> DockRecentTaskIntent in
            withUnsafeCurrentTask { $0?.cancel() }
            return try DockMenuRouting.appRoute(for: row.id, in: presentation)
        }
        do {
            _ = try await routeTask.value
            XCTFail("Cancelled app route unexpectedly succeeded")
        } catch let error as DockMenuRoutingError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }

    private func origin(
        of kind: DockMenuRouting.Kind,
        in presentation: DockMenuRouting.Presentation
    ) -> [DockMenuRouting.OriginSection] {
        presentation.section(for: kind).map { $0.rows.map(\.origin) } ?? []
    }

    private func snapshot(
        generation: UInt64 = 1,
        recentComparisons: RecentComparisonPairs = RecentComparisonPairs(),
        workspaceHistory: RecentWorkspaceHistory = RecentWorkspaceHistory(),
        commonTasks: [RecentWorkspaceCommonTask] = RecentWorkspaceCommonTask.allCases,
        bookmarkBindings: [DockRecentBookmarkBinding] = [],
        capabilities: Set<DockMenuRouting.Capability> = Set(
            DockRecentTaskCapability.allCases
        )
    ) -> DockMenuRouting.Snapshot {
        DockMenuRouting.Snapshot(
            generation: DockRecentTasksGeneration(rawValue: generation),
            recentComparisons: recentComparisons,
            workspaceHistory: workspaceHistory,
            commonTasks: commonTasks,
            bookmarkBindings: bookmarkBindings,
            capabilities: capabilities
        )
    }

    private func pair(
        _ index: Int,
        kind: RecentComparisonPair.Kind = .file
    ) throws -> RecentComparisonPair {
        try RecentComparisonPair(
            left: URL(filePath: "/routing/left-\(index)"),
            right: URL(filePath: "/routing/right-\(index)"),
            kind: kind
        )
    }
}
