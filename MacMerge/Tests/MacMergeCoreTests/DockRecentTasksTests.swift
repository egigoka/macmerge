import Foundation
import XCTest

@testable import MacMergeCore

final class DockRecentTasksTests: XCTestCase {
    func testDefaultRequestBuildsEveryCommonTaskInDeclaredOrder() throws {
        let plan = try DockRecentTasksPlanner.plan(
            DockRecentTasksRequest(generation: generation(1))
        )

        XCTAssertEqual(plan.sections.map(\.kind), [.tasks])
        XCTAssertEqual(
            plan.items.map(\.label.title),
            ["Compare Files", "Compare Folders", "Compare Clipboard", "Open Project"]
        )
        XCTAssertEqual(plan.items.map(\.label.subtitle), Array(repeating: "Common task", count: 4))
        XCTAssertEqual(plan.items.map(\.kind), [.task, .task, .task, .task])
        XCTAssertEqual(
            plan.items.map(\.availability),
            [
                .unavailable(.missingCapability(.compareFiles)),
                .unavailable(.missingCapability(.compareFolders)),
                .unavailable(.missingCapability(.compareClipboard)),
                .unavailable(.missingCapability(.openProject))
            ]
        )
        XCTAssertEqual(
            plan.items.map(\.intent),
            RecentWorkspaceCommonTask.allCases.map(DockRecentTaskIntent.performTask)
        )
        XCTAssertFalse(plan.wasTruncated)
        XCTAssertEqual(plan.duplicateIdentityCount, 0)
        XCTAssertEqual(plan.omittedItemCount, 0)
    }

    func testProjectFolderFileAndHistoricalTaskPlansPreserveSectionAndSourceOrder() throws {
        let pinnedProject = URL(filePath: "/workspace/pinned/project.macmerge")
        let pinnedFolder = try pair(1, kind: .folder)
        let recentProject = URL(filePath: "/workspace/recent/project.macmerge")
        let recentFolder = try pair(2, kind: .folder)
        let recentFile = try pair(3, kind: .file)
        let secondRecentFolder = try pair(4, kind: .folder)
        var history = RecentWorkspaceHistory()
        try history.recordFolderComparison(pinnedFolder, pinned: true)
        try history.recordProjectFile(pinnedProject, pinned: true)
        try history.recordFolderComparison(recentFolder)
        try history.recordProjectFile(recentProject)
        try history.recordCommonTask(.compareClipboard)

        let plan = try DockRecentTasksPlanner.plan(
            request(
                generation: 9,
                recentComparisons: RecentComparisonPairs(
                    [recentFile, secondRecentFolder],
                    capacity: 2
                ),
                workspaceHistory: history,
                commonTasks: [.openProject],
                capabilities: allCapabilities
            )
        )

        XCTAssertEqual(plan.sections.map(\.kind), [.pinned, .recent, .tasks])
        XCTAssertEqual(plan.sections.map { $0.items.count }, [2, 4, 2])
        XCTAssertEqual(
            plan.items.map(\.kind),
            [.project, .folder, .project, .folder, .file, .folder, .task, .task]
        )
        XCTAssertEqual(
            plan.items.map(\.label.title),
            [
                "project.macmerge",
                "left-1 and right-1",
                "project.macmerge",
                "left-2 and right-2",
                "left-3 and right-3",
                "left-4 and right-4",
                "Compare Clipboard",
                "Open Project"
            ]
        )
        XCTAssertEqual(
            plan.items.map(\.label.subtitle),
            [
                "Project file",
                "Folder comparison",
                "Project file",
                "Folder comparison",
                "File comparison",
                "Folder comparison",
                "Common task",
                "Common task"
            ]
        )
        XCTAssertEqual(plan.items.map(\.isPinned), [true, true, false, false, false, false, false, false])
        XCTAssertTrue(plan.items.allSatisfy { $0.availability == .available })
        XCTAssertEqual(
            plan.items.map(\.requiredCapabilities),
            [
                [.openProject],
                [.compareFolders],
                [.openProject],
                [.compareFolders],
                [.compareFiles],
                [.compareFolders],
                [.compareClipboard],
                [.openProject]
            ]
        )
        assertProjectIntent(plan.items[0], expectedURL: pinnedProject.standardizedFileURL)
        assertFolderIntent(plan.items[1], expectedPair: pinnedFolder)
        assertProjectIntent(plan.items[2], expectedURL: recentProject.standardizedFileURL)
        assertFolderIntent(plan.items[3], expectedPair: recentFolder)
        assertFileIntent(plan.items[4], expectedPair: recentFile)
        assertFolderIntent(plan.items[5], expectedPair: secondRecentFolder)
        XCTAssertEqual(plan.items[6].intent, .performTask(.compareClipboard))
        XCTAssertEqual(plan.items[7].intent, .performTask(.openProject))
    }

    func testPinnedHistoryWinsCrossSourceDuplicatesAndDuplicateAccountingPrecedesCaps() throws {
        let duplicatedFolder = try pair(1, kind: .folder)
        let uniqueFile = try pair(2, kind: .file)
        var history = RecentWorkspaceHistory()
        try history.recordFolderComparison(duplicatedFolder, pinned: true)
        try history.recordCommonTask(.compareFiles, pinned: true)
        let limits = try limits(maximumPinnedItems: 2, maximumRecentItems: 1, maximumTaskItems: 1)

        let plan = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: RecentComparisonPairs(
                    [duplicatedFolder, uniqueFile],
                    capacity: 2
                ),
                workspaceHistory: history,
                commonTasks: [.compareFiles, .openProject],
                capabilities: allCapabilities,
                limits: limits
            )
        )

        XCTAssertEqual(plan.sections.map(\.kind), [.pinned, .recent, .tasks])
        XCTAssertEqual(
            plan.items.map(\.label.title),
            ["Compare Files", "left-1 and right-1", "left-2 and right-2", "Open Project"]
        )
        XCTAssertEqual(plan.items.map(\.isPinned), [true, true, false, false])
        XCTAssertEqual(plan.duplicateIdentityCount, 2)
        XCTAssertEqual(plan.omittedItemCount, 0)
        XCTAssertFalse(plan.wasTruncated)
        XCTAssertEqual(Set(plan.items.map(\.id)).count, plan.items.count)
    }

    func testDuplicateAfterCapOmissionIsDuplicateNotAnotherOmission() throws {
        let includedFolder = try pair(1, kind: .folder)
        let omittedThenDuplicatedFolder = try pair(2, kind: .folder)
        var history = RecentWorkspaceHistory()
        try history.recordFolderComparison(omittedThenDuplicatedFolder)
        try history.recordFolderComparison(includedFolder)

        let plan = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: RecentComparisonPairs(
                    [omittedThenDuplicatedFolder],
                    capacity: 1
                ),
                workspaceHistory: history,
                capabilities: allCapabilities,
                limits: try limits(maximumRecentItems: 1)
            )
        )

        XCTAssertEqual(plan.items.map(\.label.title), ["left-1 and right-1"])
        XCTAssertEqual(plan.duplicateIdentityCount, 1)
        XCTAssertEqual(plan.omittedItemCount, 1)
        XCTAssertTrue(plan.wasTruncated)
    }

    func testSectionCapsCountEveryUniqueOmissionWithoutDisplacingEarlierItems() throws {
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/caps/pinned-1.macmerge"), pinned: true)
        try history.recordProjectFile(URL(filePath: "/caps/pinned-2.macmerge"), pinned: true)
        try history.recordProjectFile(URL(filePath: "/caps/recent-1.macmerge"))
        try history.recordProjectFile(URL(filePath: "/caps/recent-2.macmerge"))
        try history.recordCommonTask(.compareFiles)
        let recentPairs = RecentComparisonPairs(
            [try pair(1), try pair(2)],
            capacity: 2
        )
        let capped = try limits(
            maximumMenuItems: 10,
            maximumPinnedItems: 1,
            maximumRecentItems: 2,
            maximumTaskItems: 1
        )

        let plan = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: recentPairs,
                workspaceHistory: history,
                commonTasks: [.compareFiles, .openProject],
                capabilities: allCapabilities,
                limits: capped
            )
        )

        XCTAssertEqual(plan.sections.map(\.kind), [.pinned, .recent, .tasks])
        XCTAssertEqual(plan.items.map(\.label.title), ["pinned-2.macmerge", "recent-2.macmerge", "recent-1.macmerge", "Compare Files"])
        XCTAssertEqual(plan.duplicateIdentityCount, 1)
        XCTAssertEqual(plan.omittedItemCount, 4)
        XCTAssertTrue(plan.wasTruncated)
    }

    func testGlobalCapPrioritizesPinnedThenRecentThenTasks() throws {
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/global/pinned.macmerge"), pinned: true)
        try history.recordProjectFile(URL(filePath: "/global/recent.macmerge"))
        try history.recordCommonTask(.openProject)
        let globalCap = try limits(
            maximumMenuItems: 2,
            maximumPinnedItems: 10,
            maximumRecentItems: 10,
            maximumTaskItems: 10
        )

        let plan = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: RecentComparisonPairs([try pair(1)], capacity: 1),
                workspaceHistory: history,
                capabilities: allCapabilities,
                limits: globalCap
            )
        )

        XCTAssertEqual(plan.sections.map(\.kind), [.pinned, .recent])
        XCTAssertEqual(plan.items.map(\.label.title), ["pinned.macmerge", "recent.macmerge"])
        XCTAssertEqual(plan.omittedItemCount, 2)
        XCTAssertEqual(plan.duplicateIdentityCount, 0)
    }

    func testZeroSectionCapsProduceNoSectionsAndCountEveryUniqueOmission() throws {
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/zero/pinned.macmerge"), pinned: true)
        try history.recordProjectFile(URL(filePath: "/zero/recent.macmerge"))
        try history.recordCommonTask(.compareFiles)

        let plan = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: RecentComparisonPairs([try pair(1)], capacity: 1),
                workspaceHistory: history,
                commonTasks: [.openProject],
                capabilities: allCapabilities,
                limits: try limits(
                    maximumPinnedItems: 0,
                    maximumRecentItems: 0,
                    maximumTaskItems: 0
                )
            )
        )

        XCTAssertTrue(plan.sections.isEmpty)
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertEqual(plan.duplicateIdentityCount, 0)
        XCTAssertEqual(plan.omittedItemCount, 5)
        XCTAssertTrue(plan.wasTruncated)
    }

    func testLabelsUseOnlySafeBoundedLeafNamesAndPreserveSafeUnicode() throws {
        let secretParent = "DO-NOT-LEAK"
        let unsafeLeaf = "R\u{00E9}sum\u{00E9}-\u{1F600}\n\u{2060}.macmerge"
        var unsafeHistory = RecentWorkspaceHistory()
        try unsafeHistory.recordProjectFile(
            URL(filePath: "/private/\(secretParent)/\(unsafeLeaf)")
        )
        let unsafePlan = try DockRecentTasksPlanner.plan(
            request(workspaceHistory: unsafeHistory, capabilities: [.openProject])
        )

        XCTAssertEqual(unsafePlan.items[0].label.title, "R\u{00E9}sum\u{00E9}-\u{1F600}??.macmerge")
        XCTAssertFalse(unsafePlan.items[0].label.title.contains(secretParent))
        XCTAssertFalse(unsafePlan.items[0].label.title.contains("/private"))

        let longLeaf = String(repeating: "a", count: 40)
        var longHistory = RecentWorkspaceHistory()
        try longHistory.recordProjectFile(URL(filePath: "/private/\(secretParent)/\(longLeaf)"))
        let boundedPlan = try DockRecentTasksPlanner.plan(
            request(
                workspaceHistory: longHistory,
                capabilities: [.openProject],
                limits: try limits(maximumTitleUTF8Bytes: 16)
            )
        )

        XCTAssertEqual(boundedPlan.items[0].label.title, String(repeating: "a", count: 13) + "...")
        XCTAssertEqual(boundedPlan.items[0].label.title.utf8.count, 16)

        var rootHistory = RecentWorkspaceHistory()
        try rootHistory.recordProjectFile(URL(filePath: "/"))
        let rootPlan = try DockRecentTasksPlanner.plan(
            request(workspaceHistory: rootHistory, capabilities: [.openProject])
        )
        XCTAssertEqual(rootPlan.items[0].label.title, "/")
    }

    func testPairLabelsBoundEachComponentWithoutSplittingUTF8Characters() throws {
        let left = URL(filePath: "/labels/\(String(repeating: "\u{1F600}", count: 8))")
        let right = URL(filePath: "/labels/\(String(repeating: "b", count: 20))")
        let comparison = try RecentComparisonPair(left: left, right: right, kind: .file)

        let plan = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: RecentComparisonPairs([comparison], capacity: 1),
                capabilities: [.compareFiles],
                limits: try limits(maximumTitleUTF8Bytes: 16)
            )
        )

        XCTAssertEqual(plan.items[0].label.title, "... and bb...")
        XCTAssertLessThanOrEqual(plan.items[0].label.title.utf8.count, 16)
        XCTAssertFalse(plan.items[0].label.title.contains("\u{FFFD}"))
    }

    func testDescriptionsDebugDescriptionsAndMirrorsRedactSecretCompareFoldersResourcesAndIntents() throws {
        let secret = "DO-NOT-LEAK"
        let project = URL(filePath: "/private/\(secret)/project.macmerge")
        let leftURL = URL(filePath: "/private/\(secret)/left")
        let rightURL = URL(filePath: "/private/\(secret)/right")
        let pair = try RecentComparisonPair(left: leftURL, right: rightURL, kind: .folder)
        let projectBookmark = bookmarkReference(1)
        let leftBookmark = bookmarkReference(2)
        let projectBinding = DockRecentBookmarkBinding(url: project, reference: projectBookmark)
        let leftBinding = DockRecentBookmarkBinding(url: leftURL, reference: leftBookmark)
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(project)
        let request = request(
            generation: 17,
            recentComparisons: RecentComparisonPairs([pair], capacity: 1),
            workspaceHistory: history,
            bookmarkBindings: [projectBinding, leftBinding],
            capabilities: [.compareFolders, .openProject, .resolveBookmarks]
        )
        let plan = try DockRecentTasksPlanner.plan(request)
        let projectItem = plan.items[0]
        let pairItem = plan.items[1]
        guard case .openProject(let projectResource) = projectItem.intent else {
            return XCTFail("Expected project intent")
        }
        guard case .compareFolders(let leftResource, let rightResource) = pairItem.intent else {
            return XCTFail("Expected folder intent")
        }
        let values: [Any] = [
            projectBookmark,
            leftBookmark,
            projectBinding,
            leftBinding,
            projectResource,
            leftResource,
            rightResource,
            projectItem.id,
            pairItem.id,
            projectItem.intent,
            pairItem.intent,
            projectItem,
            pairItem,
            plan.sections[0],
            request,
            plan
        ]
        let diagnostics = values.map(diagnostics).joined(separator: "\n")

        XCTAssertFalse(diagnostics.contains(secret), diagnostics)
        XCTAssertFalse(diagnostics.contains("/private"), diagnostics)
        XCTAssertFalse(diagnostics.contains(projectBookmark.rawValue.uuidString), diagnostics)
        XCTAssertFalse(diagnostics.contains(leftBookmark.rawValue.uuidString), diagnostics)
        XCTAssertEqual(projectBookmark.description, "<bookmark-reference>")
        XCTAssertEqual(projectBinding.description, "DockRecentBookmarkBinding(<redacted>)")
        XCTAssertEqual(projectResource.description, "DockRecentResourceReference(<redacted>)")
        XCTAssertEqual(leftResource.description, "DockRecentResourceReference(<redacted>)")
        XCTAssertEqual(rightResource.description, "DockRecentResourceReference(<redacted>)")
        XCTAssertEqual(projectItem.id.description, "project:<redacted>")
        XCTAssertEqual(pairItem.id.description, "folder:<redacted>")
        XCTAssertEqual(projectItem.intent.description, "project:<redacted>")
        XCTAssertEqual(pairItem.intent.description, "folder:<redacted>")
        XCTAssertEqual(projectItem.description, "DockRecentMenuItem(project:<redacted>)")
        XCTAssertEqual(pairItem.description, "DockRecentMenuItem(folder:<redacted>)")
        XCTAssertEqual(plan.sections[0].description, "DockRecentMenuSection(kind: recent, itemCount: 2)")
        XCTAssertEqual(request.description, "DockRecentTasksRequest(generation: 17, inputCount: 2)")
        XCTAssertEqual(plan.description, "DockRecentTasksPlan(generation: 17, itemCount: 2)")
    }

    func testCanonicalBookmarkBindingsStayOpaqueAndAddResolveCapabilityToIntents() throws {
        let projectURL = URL(filePath: "/bookmarks/project.macmerge")
        let filePair = try RecentComparisonPair(
            left: URL(filePath: "/bookmarks/left.txt"),
            right: URL(filePath: "/bookmarks/right.txt"),
            kind: .file
        )
        let projectBookmark = bookmarkReference(1)
        let leftBookmark = bookmarkReference(2)
        let rightBookmark = bookmarkReference(3)
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(projectURL)
        let request = request(
            recentComparisons: RecentComparisonPairs([filePair], capacity: 1),
            workspaceHistory: history,
            bookmarkBindings: [
                DockRecentBookmarkBinding(
                    url: URL(string: "file://LOCALHOST/bookmarks/./project.macmerge")!,
                    reference: projectBookmark
                ),
                DockRecentBookmarkBinding(
                    url: URL(string: "file://localhost/bookmarks/./left.txt")!,
                    reference: leftBookmark
                ),
                DockRecentBookmarkBinding(
                    url: URL(string: "file://LOCALHOST/bookmarks/./right.txt")!,
                    reference: rightBookmark
                )
            ],
            capabilities: allCapabilities
        )

        let plan = try DockRecentTasksPlanner.plan(request)
        let projectItem = plan.items[0]
        let fileItem = plan.items[1]

        XCTAssertEqual(projectItem.requiredCapabilities, [.openProject, .resolveBookmarks])
        XCTAssertEqual(fileItem.requiredCapabilities, [.compareFiles, .resolveBookmarks])
        XCTAssertEqual(projectItem.availability, .available)
        XCTAssertEqual(fileItem.availability, .available)
        guard case .openProject(let projectResource) = projectItem.intent else {
            return XCTFail("Expected project intent")
        }
        XCTAssertEqual(projectResource.url, projectURL.standardizedFileURL)
        XCTAssertEqual(projectResource.bookmark, projectBookmark)
        guard case .compareFiles(let left, let right) = fileItem.intent else {
            return XCTFail("Expected file intent")
        }
        XCTAssertEqual(left.url, filePair.left)
        XCTAssertEqual(left.bookmark, leftBookmark)
        XCTAssertEqual(right.url, filePair.right)
        XCTAssertEqual(right.bookmark, rightBookmark)
    }

    func testBookmarkForSectionCappedResourceIsValidatedAsUsed() throws {
        let project = URL(filePath: "/bookmarks/capped.macmerge")
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(project, pinned: true)
        let plan = try DockRecentTasksPlanner.plan(
            request(
                workspaceHistory: history,
                bookmarkBindings: [
                    DockRecentBookmarkBinding(url: project, reference: bookmarkReference(1))
                ],
                capabilities: allCapabilities,
                limits: try limits(maximumPinnedItems: 0)
            )
        )

        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertEqual(plan.omittedItemCount, 1)
        XCTAssertEqual(plan.duplicateIdentityCount, 0)
    }

    func testBookmarkForUnmatchedResourceStillFailsWhenAnotherResourceIsCapped() throws {
        let cappedProject = URL(filePath: "/bookmarks/capped.macmerge")
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(cappedProject, pinned: true)

        assertDockError(.unusedBookmarkReference) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    workspaceHistory: history,
                    bookmarkBindings: [
                        DockRecentBookmarkBinding(
                            url: URL(filePath: "/bookmarks/unmatched.macmerge"),
                            reference: self.bookmarkReference(1)
                        )
                    ],
                    capabilities: self.allCapabilities,
                    limits: try self.limits(maximumPinnedItems: 0)
                )
            )
        }
    }

    func testBookmarkValidationRejectsCanonicalDuplicateURLsReusedReferencesAndUnusedBindings() throws {
        let firstURL = URL(filePath: "/bookmarks/first.txt")
        let secondURL = URL(filePath: "/bookmarks/second.txt")
        let comparison = try RecentComparisonPair(left: firstURL, right: secondURL)
        let comparisons = RecentComparisonPairs([comparison], capacity: 1)
        let firstReference = bookmarkReference(1)
        let secondReference = bookmarkReference(2)

        assertDockError(.duplicateBookmarkURL) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    recentComparisons: comparisons,
                    bookmarkBindings: [
                        DockRecentBookmarkBinding(url: firstURL, reference: firstReference),
                        DockRecentBookmarkBinding(
                            url: URL(string: "file://LOCALHOST/bookmarks/./first.txt")!,
                            reference: secondReference
                        )
                    ]
                )
            )
        }
        assertDockError(.duplicateBookmarkReference) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    recentComparisons: comparisons,
                    bookmarkBindings: [
                        DockRecentBookmarkBinding(url: firstURL, reference: firstReference),
                        DockRecentBookmarkBinding(url: secondURL, reference: firstReference)
                    ]
                )
            )
        }
        assertDockError(.unusedBookmarkReference) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    recentComparisons: comparisons,
                    bookmarkBindings: [
                        DockRecentBookmarkBinding(
                            url: URL(filePath: "/bookmarks/unused.txt"),
                            reference: firstReference
                        )
                    ]
                )
            )
        }
    }

    func testBookmarkValidationRejectsUnsupportedResourceURLsAndOversizedPaths() throws {
        let invalidURLs = [
            URL(string: "https://example.invalid/project.macmerge")!,
            URL(string: "file://remote.invalid/project.macmerge")!,
            URL(string: "file://user@localhost/project.macmerge")!,
            URL(string: "file:///project.macmerge?query=value")!,
            URL(string: "file:///bookmarks/../project.macmerge")!,
            URL(
                string: "child.macmerge",
                relativeTo: URL(filePath: "/bookmarks", directoryHint: .isDirectory)
            )!
        ]

        for invalidURL in invalidURLs {
            assertDockError(.invalidResourceURL, invalidURL.absoluteString) {
                try DockRecentTasksPlanner.plan(
                    self.request(
                        bookmarkBindings: [
                            DockRecentBookmarkBinding(
                                url: invalidURL,
                                reference: self.bookmarkReference(1)
                            )
                        ]
                    )
                )
            }
        }

        let oversized = URL(filePath: "/" + String(repeating: "a", count: 16))
        assertDockError(.resourcePathTooLong(maximumUTF8Bytes: 16)) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    bookmarkBindings: [
                        DockRecentBookmarkBinding(
                            url: oversized,
                            reference: self.bookmarkReference(1)
                        )
                    ],
                    limits: try self.limits(maximumPathUTF8Bytes: 16)
                )
            )
        }
    }

    func testCapabilityAbsenceAndCallerMarkersProduceExactUnavailableReasons() throws {
        let folder = try pair(1, kind: .folder)
        let project = URL(filePath: "/availability/project.macmerge")
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(project)
        try history.recordFolderComparison(folder, availability: .missing)
        try history.recordCommonTask(.compareClipboard, availability: .stale)
        let file = try pair(2, kind: .file)

        let plan = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: RecentComparisonPairs([file], capacity: 1),
                workspaceHistory: history
            )
        )

        XCTAssertEqual(plan.items.map(\.kind), [.folder, .project, .file, .task])
        XCTAssertEqual(
            plan.items.map(\.availability),
            [
                .unavailable(.missing),
                .unavailable(.missingCapability(.openProject)),
                .unavailable(.missingCapability(.compareFiles)),
                .unavailable(.stale)
            ]
        )
    }

    func testMissingCapabilitySelectionFollowsDeclaredOrderIncludingBookmarkResolution() throws {
        let comparison = try pair(1)
        let binding = DockRecentBookmarkBinding(
            url: comparison.left,
            reference: bookmarkReference(1)
        )
        let comparisons = RecentComparisonPairs([comparison], capacity: 1)

        let missingBase = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: comparisons,
                bookmarkBindings: [binding]
            )
        )
        XCTAssertEqual(
            missingBase.items[0].availability,
            .unavailable(.missingCapability(.compareFiles))
        )

        let missingBookmarkResolution = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: comparisons,
                bookmarkBindings: [binding],
                capabilities: [.compareFiles]
            )
        )
        XCTAssertEqual(
            missingBookmarkResolution.items[0].availability,
            .unavailable(.missingCapability(.resolveBookmarks))
        )
    }

    func testUnknownCapabilityAndKindWireValuesAreRejected() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                DockRecentTaskCapability.self,
                from: Data(#""futureCapability""#.utf8)
            )
        ) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Unexpected capability decode error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                DockRecentTaskKind.self,
                from: Data(#""futureKind""#.utf8)
            )
        ) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Unexpected kind decode error: \(error)")
            }
        }
    }

    func testIdentityIsDeterministicAcrossPlansGenerationsAndCanonicalURLSpellings() throws {
        let firstPair = try RecentComparisonPair(
            left: URL(string: "file://LOCALHOST/identity/./left")!,
            right: URL(string: "file:///identity/./right")!,
            kind: .file
        )
        let canonicalPair = try RecentComparisonPair(
            left: URL(filePath: "/identity/left"),
            right: URL(filePath: "/identity/right"),
            kind: .file
        )
        let reversedPair = try RecentComparisonPair(
            left: canonicalPair.right,
            right: canonicalPair.left,
            kind: .file
        )
        let folderPair = try RecentComparisonPair(
            left: canonicalPair.left,
            right: canonicalPair.right,
            kind: .folder
        )
        let firstPlan = try DockRecentTasksPlanner.plan(
            request(
                generation: 1,
                recentComparisons: RecentComparisonPairs(
                    [firstPair, reversedPair, folderPair],
                    capacity: 3
                ),
                commonTasks: [.compareFiles],
                capabilities: allCapabilities
            )
        )
        let repeatedPlan = try DockRecentTasksPlanner.plan(
            request(
                generation: 1,
                recentComparisons: RecentComparisonPairs(
                    [canonicalPair, reversedPair, folderPair],
                    capacity: 3
                ),
                commonTasks: [.compareFiles],
                capabilities: allCapabilities
            )
        )
        let nextGenerationPlan = try DockRecentTasksPlanner.plan(
            request(
                generation: 2,
                recentComparisons: RecentComparisonPairs(
                    [canonicalPair, reversedPair, folderPair],
                    capacity: 3
                ),
                commonTasks: [.compareFiles],
                capabilities: allCapabilities
            )
        )

        XCTAssertEqual(firstPlan.items.map(\.id), repeatedPlan.items.map(\.id))
        XCTAssertEqual(repeatedPlan.items.map(\.id), nextGenerationPlan.items.map(\.id))
        XCTAssertEqual(Set(firstPlan.items.map(\.id)).count, 4)
        XCTAssertNotEqual(firstPlan.items[0].id, firstPlan.items[1].id)
        XCTAssertNotEqual(firstPlan.items[0].id, firstPlan.items[2].id)
        XCTAssertEqual(firstPlan, repeatedPlan)
        XCTAssertNotEqual(repeatedPlan, nextGenerationPlan)
    }

    func testPlannerStaleGenerationRejectsBothDirectionsAndAcceptsEqualGeneration() throws {
        let older = generation(40)
        let actual = generation(41)
        let newer = generation(42)

        let plan = try DockRecentTasksPlanner.plan(
            request(generation: actual.rawValue),
            expecting: actual
        )
        XCTAssertEqual(plan.generation, actual)
        assertDockError(.staleGeneration(expected: older, actual: actual)) {
            try DockRecentTasksPlanner.plan(
                self.request(generation: actual.rawValue),
                expecting: older
            )
        }
        assertDockError(.staleGeneration(expected: newer, actual: actual)) {
            try DockRecentTasksPlanner.plan(
                self.request(generation: actual.rawValue),
                expecting: newer
            )
        }
    }

    func testPlanCurrentValidationReportsCallerExpectationAndPlanActualExactly() throws {
        let actual = generation(41)
        let older = generation(40)
        let newer = generation(42)
        let plan = try DockRecentTasksPlanner.plan(request(generation: actual.rawValue))

        XCTAssertTrue(plan.isCurrent(generation: actual))
        XCTAssertFalse(plan.isCurrent(generation: older))
        XCTAssertFalse(plan.isCurrent(generation: newer))
        XCTAssertNoThrow(try plan.requireCurrent(generation: actual))
        assertDockError(.staleGeneration(expected: older, actual: actual)) {
            try plan.requireCurrent(generation: older)
        }
        assertDockError(.staleGeneration(expected: newer, actual: actual)) {
            try plan.requireCurrent(generation: newer)
        }
    }

    func testLimitDefaultsAndHardCapsMatchPublicContractExactly() throws {
        let defaultLimits = DockRecentTasksLimits.default
        let initializedDefaults = try DockRecentTasksLimits()

        XCTAssertEqual(defaultLimits, initializedDefaults)
        XCTAssertEqual(defaultLimits.maximumMenuItems, 36)
        XCTAssertEqual(defaultLimits.maximumPinnedItems, 12)
        XCTAssertEqual(defaultLimits.maximumRecentItems, 20)
        XCTAssertEqual(defaultLimits.maximumTaskItems, 4)
        XCTAssertEqual(defaultLimits.maximumInputItems, 2_004)
        XCTAssertEqual(defaultLimits.maximumBookmarkBindings, 4_096)
        XCTAssertEqual(defaultLimits.maximumPathUTF8Bytes, 16_384)
        XCTAssertEqual(defaultLimits.maximumTitleUTF8Bytes, 512)
        XCTAssertEqual(defaultLimits.maximumWork, 16_777_216)
        XCTAssertEqual(DockRecentTasksLimits.hardMaximumMenuItems, 256)
        XCTAssertEqual(DockRecentTasksLimits.hardMaximumInputItems, 2_004)
        XCTAssertEqual(DockRecentTasksLimits.hardMaximumBookmarkBindings, 4_096)
        XCTAssertEqual(DockRecentTasksLimits.hardMaximumPathUTF8Bytes, 65_536)
        XCTAssertEqual(DockRecentTasksLimits.hardMaximumTitleUTF8Bytes, 1_024)
        XCTAssertEqual(DockRecentTasksLimits.hardMaximumWork, 134_217_728)
    }

    func testLimitsAcceptExactPublicBoundariesAndRejectEveryOutOfRangeDimension() throws {
        _ = try DockRecentTasksLimits(
            maximumMenuItems: 1,
            maximumPinnedItems: 0,
            maximumRecentItems: 0,
            maximumTaskItems: 0,
            maximumInputItems: 1,
            maximumBookmarkBindings: 0,
            maximumPathUTF8Bytes: 1,
            maximumTitleUTF8Bytes: 16,
            maximumWork: 1
        )
        _ = try DockRecentTasksLimits(
            maximumMenuItems: DockRecentTasksLimits.hardMaximumMenuItems,
            maximumPinnedItems: DockRecentTasksLimits.hardMaximumMenuItems,
            maximumRecentItems: DockRecentTasksLimits.hardMaximumMenuItems,
            maximumTaskItems: DockRecentTasksLimits.hardMaximumMenuItems,
            maximumInputItems: DockRecentTasksLimits.hardMaximumInputItems,
            maximumBookmarkBindings: DockRecentTasksLimits.hardMaximumBookmarkBindings,
            maximumPathUTF8Bytes: DockRecentTasksLimits.hardMaximumPathUTF8Bytes,
            maximumTitleUTF8Bytes: DockRecentTasksLimits.hardMaximumTitleUTF8Bytes,
            maximumWork: DockRecentTasksLimits.hardMaximumWork
        )

        let base = (
            menu: 1,
            pinned: 0,
            recent: 0,
            task: 0,
            input: 1,
            bookmarks: 0,
            path: 1,
            title: 16,
            work: 1
        )
        let invalidCases = [
            ("menu zero", 0, base.pinned, base.recent, base.task, base.input, base.bookmarks, base.path, base.title, base.work),
            (
                "menu high", DockRecentTasksLimits.hardMaximumMenuItems + 1, base.pinned, base.recent, base.task, base.input, base.bookmarks, base.path,
                base.title, base.work
            ),
            ("pinned negative", base.menu, -1, base.recent, base.task, base.input, base.bookmarks, base.path, base.title, base.work),
            (
                "pinned high", base.menu, DockRecentTasksLimits.hardMaximumMenuItems + 1, base.recent, base.task, base.input, base.bookmarks, base.path,
                base.title, base.work
            ),
            ("recent negative", base.menu, base.pinned, -1, base.task, base.input, base.bookmarks, base.path, base.title, base.work),
            (
                "recent high", base.menu, base.pinned, DockRecentTasksLimits.hardMaximumMenuItems + 1, base.task, base.input, base.bookmarks, base.path,
                base.title, base.work
            ),
            ("task negative", base.menu, base.pinned, base.recent, -1, base.input, base.bookmarks, base.path, base.title, base.work),
            (
                "task high", base.menu, base.pinned, base.recent, DockRecentTasksLimits.hardMaximumMenuItems + 1, base.input, base.bookmarks, base.path,
                base.title, base.work
            ),
            ("input zero", base.menu, base.pinned, base.recent, base.task, 0, base.bookmarks, base.path, base.title, base.work),
            (
                "input high", base.menu, base.pinned, base.recent, base.task, DockRecentTasksLimits.hardMaximumInputItems + 1, base.bookmarks, base.path,
                base.title, base.work
            ),
            ("bookmarks negative", base.menu, base.pinned, base.recent, base.task, base.input, -1, base.path, base.title, base.work),
            (
                "bookmarks high", base.menu, base.pinned, base.recent, base.task, base.input, DockRecentTasksLimits.hardMaximumBookmarkBindings + 1, base.path,
                base.title, base.work
            ),
            ("path zero", base.menu, base.pinned, base.recent, base.task, base.input, base.bookmarks, 0, base.title, base.work),
            (
                "path high", base.menu, base.pinned, base.recent, base.task, base.input, base.bookmarks, DockRecentTasksLimits.hardMaximumPathUTF8Bytes + 1,
                base.title, base.work
            ),
            ("title low", base.menu, base.pinned, base.recent, base.task, base.input, base.bookmarks, base.path, 15, base.work),
            (
                "title high", base.menu, base.pinned, base.recent, base.task, base.input, base.bookmarks, base.path,
                DockRecentTasksLimits.hardMaximumTitleUTF8Bytes + 1, base.work
            ),
            ("work zero", base.menu, base.pinned, base.recent, base.task, base.input, base.bookmarks, base.path, base.title, 0),
            (
                "work high", base.menu, base.pinned, base.recent, base.task, base.input, base.bookmarks, base.path, base.title,
                DockRecentTasksLimits.hardMaximumWork + 1
            )
        ]

        for invalidCase in invalidCases {
            assertDockError(.invalidLimits, invalidCase.0) {
                try DockRecentTasksLimits(
                    maximumMenuItems: invalidCase.1,
                    maximumPinnedItems: invalidCase.2,
                    maximumRecentItems: invalidCase.3,
                    maximumTaskItems: invalidCase.4,
                    maximumInputItems: invalidCase.5,
                    maximumBookmarkBindings: invalidCase.6,
                    maximumPathUTF8Bytes: invalidCase.7,
                    maximumTitleUTF8Bytes: invalidCase.8,
                    maximumWork: invalidCase.9
                )
            }
        }
    }

    func testInputBookmarkAndPathLimitsAcceptExactBoundaryAndRejectOneMore() throws {
        let exactPath = "/" + String(repeating: "a", count: 15)
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: exactPath))
        let exactLimits = try limits(
            maximumInputItems: 1,
            maximumBookmarkBindings: 1,
            maximumPathUTF8Bytes: 16
        )
        let reference = bookmarkReference(1)
        let exactPlan = try DockRecentTasksPlanner.plan(
            request(
                workspaceHistory: history,
                bookmarkBindings: [
                    DockRecentBookmarkBinding(url: URL(filePath: exactPath), reference: reference)
                ],
                capabilities: [.openProject, .resolveBookmarks],
                limits: exactLimits
            )
        )
        XCTAssertEqual(exactPlan.items.count, 1)

        assertDockError(.inputLimitExceeded(maximum: 1)) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    workspaceHistory: history,
                    commonTasks: [.openProject],
                    limits: exactLimits
                )
            )
        }
        assertDockError(.bookmarkBindingLimitExceeded(maximum: 0)) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    workspaceHistory: history,
                    bookmarkBindings: [
                        DockRecentBookmarkBinding(url: URL(filePath: exactPath), reference: reference)
                    ],
                    limits: try self.limits(maximumBookmarkBindings: 0)
                )
            )
        }

        var oversizedHistory = RecentWorkspaceHistory()
        try oversizedHistory.recordProjectFile(URL(filePath: exactPath + "b"))
        assertDockError(.resourcePathTooLong(maximumUTF8Bytes: 16)) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    workspaceHistory: oversizedHistory,
                    limits: exactLimits
                )
            )
        }
    }

    func testRecentPairCountsAsOneInputRegardlessOfItsTwoResources() throws {
        let comparison = try pair(1)
        let oneInput = try limits(maximumInputItems: 1)

        let plan = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: RecentComparisonPairs([comparison], capacity: 1),
                capabilities: [.compareFiles],
                limits: oneInput
            )
        )

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(
            request(
                recentComparisons: RecentComparisonPairs([comparison], capacity: 1),
                limits: oneInput
            ).description,
            "DockRecentTasksRequest(generation: 1, inputCount: 1)"
        )
        assertDockError(.inputLimitExceeded(maximum: 1)) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    recentComparisons: RecentComparisonPairs([comparison], capacity: 1),
                    commonTasks: [.openProject],
                    limits: oneInput
                )
            )
        }
    }

    func testMultibyteRecentPairPathAcceptsExactUTF8BoundaryAndRejectsOneMoreByte() throws {
        let exactLeft = URL(filePath: "/\(String(repeating: "\u{1F600}", count: 4))")
        let oversizedLeft = URL(filePath: exactLeft.path + "a")
        let exactRight = URL(filePath: "/\(String(repeating: "\u{1F601}", count: 4))")
        let boundaryLimits = try limits(maximumPathUTF8Bytes: 17)
        let exactPair = try RecentComparisonPair(left: exactLeft, right: exactRight)

        let plan = try DockRecentTasksPlanner.plan(
            request(
                recentComparisons: RecentComparisonPairs([exactPair], capacity: 1),
                capabilities: [.compareFiles],
                limits: boundaryLimits
            )
        )

        XCTAssertEqual(exactLeft.path.utf8.count, 17)
        XCTAssertEqual(exactRight.path.utf8.count, 17)
        XCTAssertEqual(plan.items.count, 1)
        let oversizedPair = try RecentComparisonPair(left: oversizedLeft, right: exactRight)
        XCTAssertEqual(oversizedLeft.path.utf8.count, 18)
        assertDockError(.resourcePathTooLong(maximumUTF8Bytes: 17)) {
            try DockRecentTasksPlanner.plan(
                self.request(
                    recentComparisons: RecentComparisonPairs([oversizedPair], capacity: 1),
                    limits: boundaryLimits
                )
            )
        }
    }

    func testValidationPrecedenceIsStaleThenInputThenBookmarkCount() throws {
        let stale = generation(2)
        let inputAndBookmarkLimits = try limits(
            maximumInputItems: 1,
            maximumBookmarkBindings: 0
        )
        let oversizedRequest = request(
            generation: 1,
            commonTasks: [.compareFiles, .compareFolders],
            bookmarkBindings: [
                DockRecentBookmarkBinding(
                    url: URL(filePath: "/precedence/unused"),
                    reference: bookmarkReference(1)
                )
            ],
            limits: inputAndBookmarkLimits
        )

        assertDockError(.staleGeneration(expected: stale, actual: generation(1))) {
            try DockRecentTasksPlanner.plan(oversizedRequest, expecting: stale)
        }
        assertDockError(.inputLimitExceeded(maximum: 1)) {
            try DockRecentTasksPlanner.plan(oversizedRequest)
        }
        let bookmarkOnlyRequest = request(
            commonTasks: [.compareFiles],
            bookmarkBindings: oversizedRequest.bookmarkBindings,
            limits: inputAndBookmarkLimits
        )
        assertDockError(.bookmarkBindingLimitExceeded(maximum: 0)) {
            try DockRecentTasksPlanner.plan(bookmarkOnlyRequest)
        }
    }

    func testResourcePairBookmarkAndTaskWorkBudgetsAcceptExactCostAndRejectOneLess() throws {
        let projectURL = URL(filePath: "/w/p")
        var projectHistory = RecentWorkspaceHistory()
        try projectHistory.recordProjectFile(projectURL)
        try assertExactWork(
            34,
            request: request(
                workspaceHistory: projectHistory,
                capabilities: [.openProject]
            )
        )

        let comparison = try RecentComparisonPair(
            left: URL(filePath: "/w/l"),
            right: URL(filePath: "/w/r")
        )
        try assertExactWork(
            70,
            request: request(
                recentComparisons: RecentComparisonPairs([comparison], capacity: 1),
                capabilities: [.compareFiles]
            )
        )

        try assertExactWork(
            109,
            request: request(
                recentComparisons: RecentComparisonPairs([comparison], capacity: 1),
                bookmarkBindings: [
                    DockRecentBookmarkBinding(
                        url: comparison.right,
                        reference: bookmarkReference(1)
                    )
                ],
                capabilities: [.compareFiles, .resolveBookmarks]
            )
        )

        let exactCost = 25
        try assertExactWork(
            exactCost,
            request: request(
                commonTasks: [.compareFiles],
                capabilities: [.compareFiles]
            )
        )
    }

    func testTwoItemCumulativeWorkBudgetAcceptsExactCostAndRejectsOneLess() throws {
        try assertExactWork(
            52,
            request: request(
                commonTasks: [.compareFiles, .compareFolders],
                capabilities: [.compareFiles, .compareFolders]
            )
        )
    }

    func testMultibyteResourceWorkBudgetAcceptsExactCostAndRejectsOneLess() throws {
        let projectURL = URL(filePath: "/\u{1F600}")
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(projectURL)

        XCTAssertEqual(projectURL.path.utf8.count, 5)
        XCTAssertEqual(projectURL.absoluteString.utf8.count, 20)
        try assertExactWork(
            51,
            request: request(
                workspaceHistory: history,
                capabilities: [.openProject]
            )
        )
    }

    func testPrecancelledPlanningReturnsDomainCancellationBeforeStalenessAndLimits() async throws {
        let constrainedLimits = try limits(
            maximumInputItems: 1,
            maximumBookmarkBindings: 0,
            maximumWork: 1
        )
        let invalidIfReached = request(
            generation: 1,
            commonTasks: [.compareFiles, .compareFolders],
            bookmarkBindings: [
                DockRecentBookmarkBinding(
                    url: URL(string: "https://example.invalid/unused")!,
                    reference: bookmarkReference(1)
                )
            ],
            limits: constrainedLimits
        )
        let task = Task.detached { () throws -> DockRecentTasksPlan in
            withUnsafeCurrentTask { $0?.cancel() }
            return try DockRecentTasksPlanner.plan(
                invalidIfReached,
                expecting: DockRecentTasksGeneration(rawValue: 2)
            )
        }

        await assertCancelled(task)
    }

    private var allCapabilities: Set<DockRecentTaskCapability> {
        Set(DockRecentTaskCapability.allCases)
    }

    private func generation(_ rawValue: UInt64) -> DockRecentTasksGeneration {
        DockRecentTasksGeneration(rawValue: rawValue)
    }

    private func bookmarkReference(_ byte: UInt8) -> DockRecentBookmarkReference {
        DockRecentBookmarkReference(
            rawValue: UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
        )
    }

    private func pair(
        _ index: Int,
        kind: RecentComparisonPair.Kind = .file
    ) throws -> RecentComparisonPair {
        try RecentComparisonPair(
            left: URL(filePath: "/pairs/left-\(index)"),
            right: URL(filePath: "/pairs/right-\(index)"),
            kind: kind
        )
    }

    private func request(
        generation rawGeneration: UInt64 = 1,
        recentComparisons: RecentComparisonPairs = RecentComparisonPairs(),
        workspaceHistory: RecentWorkspaceHistory = RecentWorkspaceHistory(),
        commonTasks: [RecentWorkspaceCommonTask] = [],
        bookmarkBindings: [DockRecentBookmarkBinding] = [],
        capabilities: Set<DockRecentTaskCapability> = [],
        limits: DockRecentTasksLimits = .default
    ) -> DockRecentTasksRequest {
        DockRecentTasksRequest(
            generation: generation(rawGeneration),
            recentComparisons: recentComparisons,
            workspaceHistory: workspaceHistory,
            commonTasks: commonTasks,
            bookmarkBindings: bookmarkBindings,
            capabilities: capabilities,
            limits: limits
        )
    }

    private func limits(
        maximumMenuItems: Int = 36,
        maximumPinnedItems: Int = 12,
        maximumRecentItems: Int = 20,
        maximumTaskItems: Int = RecentWorkspaceCommonTask.allCases.count,
        maximumInputItems: Int = DockRecentTasksLimits.hardMaximumInputItems,
        maximumBookmarkBindings: Int = DockRecentTasksLimits.hardMaximumBookmarkBindings,
        maximumPathUTF8Bytes: Int = RecentWorkspaceHistory.defaultMaximumPathBytes,
        maximumTitleUTF8Bytes: Int = 512,
        maximumWork: Int = 16 * 1_024 * 1_024
    ) throws -> DockRecentTasksLimits {
        try DockRecentTasksLimits(
            maximumMenuItems: maximumMenuItems,
            maximumPinnedItems: maximumPinnedItems,
            maximumRecentItems: maximumRecentItems,
            maximumTaskItems: maximumTaskItems,
            maximumInputItems: maximumInputItems,
            maximumBookmarkBindings: maximumBookmarkBindings,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes,
            maximumTitleUTF8Bytes: maximumTitleUTF8Bytes,
            maximumWork: maximumWork
        )
    }

    private func assertProjectIntent(
        _ item: DockRecentMenuItem,
        expectedURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .openProject(let resource) = item.intent else {
            return XCTFail("Expected project intent", file: file, line: line)
        }
        XCTAssertEqual(resource.url, expectedURL, file: file, line: line)
        XCTAssertNil(resource.bookmark, file: file, line: line)
    }

    private func assertFileIntent(
        _ item: DockRecentMenuItem,
        expectedPair: RecentComparisonPair,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .compareFiles(let left, let right) = item.intent else {
            return XCTFail("Expected file intent", file: file, line: line)
        }
        XCTAssertEqual(left.url, expectedPair.left, file: file, line: line)
        XCTAssertEqual(right.url, expectedPair.right, file: file, line: line)
    }

    private func assertFolderIntent(
        _ item: DockRecentMenuItem,
        expectedPair: RecentComparisonPair,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .compareFolders(let left, let right) = item.intent else {
            return XCTFail("Expected folder intent", file: file, line: line)
        }
        XCTAssertEqual(left.url, expectedPair.left, file: file, line: line)
        XCTAssertEqual(right.url, expectedPair.right, file: file, line: line)
    }

    private func assertDockError<T>(
        _ expected: DockRecentTasksError,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> T
    ) {
        XCTAssertThrowsError(try expression(), message, file: file, line: line) { error in
            XCTAssertEqual(error as? DockRecentTasksError, expected, message, file: file, line: line)
        }
    }

    private func assertExactWork(
        _ exactCost: Int,
        request baseRequest: DockRecentTasksRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        func request(maximumWork: Int) throws -> DockRecentTasksRequest {
            let limits = try DockRecentTasksLimits(
                maximumMenuItems: baseRequest.limits.maximumMenuItems,
                maximumPinnedItems: baseRequest.limits.maximumPinnedItems,
                maximumRecentItems: baseRequest.limits.maximumRecentItems,
                maximumTaskItems: baseRequest.limits.maximumTaskItems,
                maximumInputItems: baseRequest.limits.maximumInputItems,
                maximumBookmarkBindings: baseRequest.limits.maximumBookmarkBindings,
                maximumPathUTF8Bytes: baseRequest.limits.maximumPathUTF8Bytes,
                maximumTitleUTF8Bytes: baseRequest.limits.maximumTitleUTF8Bytes,
                maximumWork: maximumWork
            )
            return DockRecentTasksRequest(
                generation: baseRequest.generation,
                recentComparisons: baseRequest.recentComparisons,
                workspaceHistory: baseRequest.workspaceHistory,
                commonTasks: baseRequest.commonTasks,
                bookmarkBindings: baseRequest.bookmarkBindings,
                capabilities: baseRequest.capabilities,
                limits: limits
            )
        }

        let exactPlan = try DockRecentTasksPlanner.plan(request(maximumWork: exactCost))
        XCTAssertFalse(exactPlan.items.isEmpty, file: file, line: line)
        assertDockError(
            .workLimitExceeded(maximumWork: exactCost - 1),
            file: file,
            line: line
        ) {
            try DockRecentTasksPlanner.plan(request(maximumWork: exactCost - 1))
        }
    }

    private func assertCancelled(
        _ task: Task<DockRecentTasksPlan, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("Cancelled planning unexpectedly succeeded", file: file, line: line)
        } catch let error as DockRecentTasksError {
            XCTAssertEqual(error, .cancelled, file: file, line: line)
        } catch {
            XCTFail("Unexpected cancellation error: \(error)", file: file, line: line)
        }
    }

    private func diagnostics(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        let children = mirror.children.map { child in
            "\(child.label ?? "<nil>")=\(String(reflecting: child.value))"
        }
        return ([String(describing: value), String(reflecting: value)] + children)
            .joined(separator: "\n")
    }
}
