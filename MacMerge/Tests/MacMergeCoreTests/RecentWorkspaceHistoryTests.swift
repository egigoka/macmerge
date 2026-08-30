import Foundation
import XCTest

@testable import MacMergeCore

final class RecentWorkspaceHistoryTests: XCTestCase {
    func testPinnedFirstMRUPromotesDeduplicatesAndPreservesPinnedEntriesAtCapacity() throws {
        let limits = try RecentWorkspaceHistory.Limits(
            maximumEntries: 4,
            maximumPathBytes: 1_024,
            maximumWork: 1_000_000
        )
        let firstProject = URL(filePath: "/work/first.macmerge")
        let secondProject = URL(filePath: "/work/second.macmerge")
        let left = URL(filePath: "/work/left", directoryHint: .isDirectory)
        let right = URL(filePath: "/work/right", directoryHint: .isDirectory)
        var history = RecentWorkspaceHistory(limits: limits)

        XCTAssertTrue(try history.recordProjectFile(firstProject))
        XCTAssertTrue(try history.recordCommonTask(.compareFiles))
        XCTAssertTrue(try history.recordFolderComparison(left: left, right: right, pinned: true))
        XCTAssertTrue(try history.recordProjectFile(secondProject))
        XCTAssertEqual(history.entries.map(\.kind), [.folderComparison, .projectFile, .commonTask, .projectFile])

        XCTAssertTrue(
            try history.recordProjectFile(URL(string: "file://LOCALHOST/work/./first.macmerge")!)
        )
        XCTAssertEqual(
            history.entries.compactMap(\.projectFileURL),
            [firstProject.standardizedFileURL, secondProject.standardizedFileURL]
        )
        XCTAssertEqual(history.count, 4)

        XCTAssertTrue(try history.recordCommonTask(.compareFiles, pinned: true))
        XCTAssertEqual(history.entries.map(\.kind), [.commonTask, .folderComparison, .projectFile, .projectFile])
        XCTAssertTrue(history.entries[0].isPinned)
        XCTAssertTrue(history.entries[1].isPinned)

        XCTAssertTrue(try history.recordCommonTask(.compareFolders))
        XCTAssertEqual(history.count, 4)
        XCTAssertFalse(history.entries.contains { $0.projectFileURL == secondProject.standardizedFileURL })

        let firstProjectIdentity = try XCTUnwrap(
            history.entries.first { $0.projectFileURL == firstProject.standardizedFileURL }?.id
        )
        let compareFoldersIdentity = try XCTUnwrap(
            history.entries.first { $0.commonTask == .compareFolders }?.id
        )
        XCTAssertTrue(try history.setPinned(true, for: firstProjectIdentity))
        XCTAssertTrue(try history.setPinned(true, for: compareFoldersIdentity))
        XCTAssertTrue(history.entries.allSatisfy(\.isPinned))
        XCTAssertFalse(try history.recordCommonTask(.openProject))
        XCTAssertEqual(history.count, 4)
    }

    func testPinAndUnpinAreIdempotentAndPreservePinnedFirstMRUOrder() throws {
        let first = URL(filePath: "/work/first.macmerge")
        let second = URL(filePath: "/work/second.macmerge")
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(first)
        try history.recordProjectFile(second)
        try history.recordCommonTask(.compareFiles, pinned: true)

        let firstID = try XCTUnwrap(history.entries.first { $0.projectFileURL == first }?.id)
        let secondID = try XCTUnwrap(history.entries.first { $0.projectFileURL == second }?.id)
        let taskID = try XCTUnwrap(history.entries.first { $0.commonTask == .compareFiles }?.id)

        XCTAssertTrue(try history.setPinned(true, for: firstID))
        XCTAssertEqual(history.entries.map(\.id), [firstID, taskID, secondID])
        XCTAssertFalse(try history.setPinned(true, for: firstID))

        XCTAssertTrue(try history.setPinned(false, for: firstID))
        XCTAssertEqual(history.entries.map(\.id), [taskID, firstID, secondID])
        XCTAssertFalse(try history.setPinned(false, for: firstID))

        XCTAssertTrue(try history.setPinned(true, for: secondID))
        XCTAssertEqual(history.entries.map(\.id), [secondID, taskID, firstID])
        XCTAssertTrue(try history.recordProjectFile(first, pinned: true))
        XCTAssertEqual(history.entries.map(\.id), [firstID, secondID, taskID])
        XCTAssertTrue(history.entries.allSatisfy(\.isPinned))
    }

    func testProjectFolderAndTaskAdaptersExposeTypedValuesAndSafeDisplayMetadata() throws {
        let projectURL = URL(filePath: "/workspace/document.macmerge")
        let left = URL(filePath: "/workspace/left", directoryHint: .isDirectory)
        let right = URL(filePath: "/workspace/right", directoryHint: .isDirectory)
        let pair = try RecentComparisonPair(left: left, right: right, kind: .folder)
        let projectLeft = URL(filePath: "/workspace/project-left", directoryHint: .isDirectory)
        let projectRight = URL(filePath: "/workspace/project-right", directoryHint: .isDirectory)
        let project = try ComparisonProject(left: projectLeft, right: projectRight, mode: .folder)
        var history = RecentWorkspaceHistory()

        XCTAssertTrue(try history.recordProjectFile(projectURL, availability: .stale))
        XCTAssertTrue(try history.recordFolderComparison(pair, availability: .missing))
        XCTAssertTrue(try history.recordFolderComparison(from: project, availability: .missing))
        XCTAssertTrue(try history.recordCommonTask(.compareClipboard))

        XCTAssertEqual(history.projectFiles.count, 1)
        XCTAssertEqual(history.folderComparisons.count, 2)
        XCTAssertEqual(history.commonTasks.count, 1)
        XCTAssertEqual(history.projectFiles[0].projectFileURL, projectURL.standardizedFileURL)
        XCTAssertEqual(history.projectFiles[0].availability, .stale)
        XCTAssertEqual(history.projectFiles[0].displayMetadata.title, "document.macmerge")
        XCTAssertEqual(
            history.folderComparisons.map(\.folderComparison),
            [try RecentComparisonPair(left: projectLeft, right: projectRight, kind: .folder), pair]
        )
        XCTAssertEqual(history.folderComparisons[0].availability, .missing)
        XCTAssertEqual(history.folderComparisons[0].displayMetadata.title, "project-left and project-right")
        XCTAssertEqual(history.folderComparisons[1].displayMetadata.title, "left and right")
        XCTAssertEqual(history.commonTasks[0].commonTask, .compareClipboard)
        XCTAssertEqual(history.commonTasks[0].displayMetadata, .init(title: "Compare Clipboard", subtitle: "Common task"))
    }

    func testFolderAdaptersRejectFilePairsAndUnsupportedProjectShapes() throws {
        let left = URL(filePath: "/workspace/left")
        let middle = URL(filePath: "/workspace/middle")
        let right = URL(filePath: "/workspace/right")
        let filePair = try RecentComparisonPair(left: left, right: right, kind: .file)
        let invalidProjects = [
            try ComparisonProject(left: left, right: right, mode: .text),
            try ComparisonProject(left: left, right: right, mode: .folder, recursive: true),
            try ComparisonProject(left: left, right: right, leftReadOnly: true, mode: .folder),
            try ComparisonProject(left: left, right: right, rightReadOnly: true, mode: .folder),
            try ComparisonProject(left: left, right: right, mode: .folder, filter: .named("Swift")),
            try ComparisonProject(
                left: left,
                right: right,
                mode: .folder,
                lineDiffOptions: LineDiffOptions(ignoreCase: true)
            ),
            try ComparisonProject(left: left, middle: middle, right: right, mode: .folder)
        ]
        var history = RecentWorkspaceHistory()

        assertHistoryError(.invalidFolderComparison) {
            try history.recordFolderComparison(filePair)
        }
        for project in invalidProjects {
            assertHistoryError(.invalidFolderComparison) {
                try history.recordFolderComparison(from: project)
            }
        }
        XCTAssertTrue(history.isEmpty)
    }

    func testDescriptionsDebugDescriptionsAndMirrorsRedactPathIdentity() throws {
        let secret = "DO-NOT-LEAK"
        var history = RecentWorkspaceHistory()
        try history.recordProjectFile(URL(filePath: "/private/\(secret)/document.macmerge"))
        let entry = try XCTUnwrap(history.first)
        let diagnostics = [historyDiagnostics(history), historyDiagnostics(entry), historyDiagnostics(entry.id)].joined()

        XCTAssertFalse(diagnostics.contains(secret), diagnostics)
        XCTAssertFalse(diagnostics.contains("/private"), diagnostics)
        XCTAssertEqual(history.description, "RecentWorkspaceHistory(entryCount: 1)")
        XCTAssertEqual(history.debugDescription, history.description)
        XCTAssertEqual(entry.description, "projectFile:<redacted>")
        XCTAssertEqual(entry.debugDescription, entry.description)
        XCTAssertEqual(entry.id.description, "projectFile:<redacted>")
        XCTAssertEqual(Set(Mirror(reflecting: history).children.compactMap(\.label)), ["limits", "entryCount", "entries"])
        XCTAssertEqual(
            Set(Mirror(reflecting: entry).children.compactMap(\.label)),
            ["kind", "isPinned", "availability", "value"]
        )
        XCTAssertEqual(Set(Mirror(reflecting: entry.id).children.compactMap(\.label)), ["kind", "hasSecondary"])
    }

    func testDisplayMetadataPreservesSafeUnicodeAndRedactsUnsafeOrOversizedNames() throws {
        let cases = [
            ("R\u{00E9}sum\u{00E9}-\u{1F600}.macmerge", "R\u{00E9}sum\u{00E9}-\u{1F600}.macmerge"),
            ("line\nfeed.macmerge", "line?feed.macmerge"),
            ("\u{034F}hidden.macmerge", "?hidden.macmerge"),
            (String(repeating: "a", count: 257), String(repeating: "a", count: 256) + "...")
        ]

        for (name, expectedTitle) in cases {
            var history = RecentWorkspaceHistory()
            try history.recordProjectFile(URL(filePath: "/private/DO-NOT-LEAK/\(name)"))
            let metadata = try XCTUnwrap(history.first).displayMetadata
            XCTAssertEqual(metadata.title, expectedTitle, name.debugDescription)
            XCTAssertFalse(metadata.title.contains("DO-NOT-LEAK"), name.debugDescription)
            XCTAssertEqual(metadata.subtitle, "Project file")
        }

        var rootHistory = RecentWorkspaceHistory()
        try rootHistory.recordProjectFile(URL(filePath: "/"))
        XCTAssertEqual(rootHistory.first?.displayMetadata.title, "/")
    }

    func testRejectsTerminalMixedAndEncodedSeparatorParentComponentsAcrossEveryURLPath() throws {
        for invalidURL in [
            URL(string: "file:///workspace/../escape")!,
            URL(string: "file:///workspace/%2e%2e/escape")!,
            URL(string: "file:///workspace/..")!,
            URL(string: "file:///workspace/%2e%2e")!,
            URL(string: "file:///workspace/%2e./escape")!,
            URL(string: "file:///workspace/.%2e/escape")!,
            URL(string: "file:///workspace/%2e%2e%2fescape")!
        ] {
            try assertRejectsEveryHistoryURLPath(invalidURL)
        }
    }

    func testAcceptsLiteralDoubleEncodedTraversalTextAcrossEveryURLPath() throws {
        let encoded = URL(string: "file:///workspace/%252e%252e%252fchild")!
        let canonical = URL(filePath: "/workspace/%2e%2e%2fchild")
        let valid = URL(filePath: "/valid", directoryHint: .isDirectory)
        var history = RecentWorkspaceHistory()

        XCTAssertTrue(try history.recordProjectFile(encoded))
        XCTAssertEqual(history.first?.projectFileURL, canonical.standardizedFileURL)
        XCTAssertTrue(try history.removeProjectFile(encoded))
        XCTAssertTrue(try history.recordFolderComparison(left: encoded, right: valid))
        XCTAssertTrue(try history.removeFolderComparison(left: encoded, right: valid))
        XCTAssertTrue(try history.recordFolderComparison(left: valid, right: encoded))
        XCTAssertTrue(try history.removeFolderComparison(left: valid, right: encoded))

        let project = try ComparisonProject(left: encoded, right: valid, mode: .folder)
        XCTAssertTrue(try history.recordFolderComparison(from: project))
        let persisted = try history.encodedData()
        XCTAssertEqual(try RecentWorkspaceHistory.decode(from: persisted), history)
    }

    func testRejectsParentComponentsAfterRealSymlinkAcrossEveryURLPath() throws {
        let base = FileManager.default.temporaryDirectory.appending(
            path: "RecentWorkspaceHistoryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let root = base.appending(path: "root", directoryHint: .isDirectory)
        let outside = base.appending(path: "outside", directoryHint: .isDirectory)
        let link = root.appending(path: "link", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), outside.path)

        let linkString = link.absoluteString.hasSuffix("/") ? String(link.absoluteString.dropLast()) : link.absoluteString
        for parentComponent in ["..", "%2e%2e"] {
            let invalidURL = try XCTUnwrap(URL(string: "\(linkString)/\(parentComponent)/escape"))
            try assertRejectsEveryHistoryURLPath(invalidURL)
        }
    }

    func testSchemaProbeErrorsPrecedePayloadValidationAndSizeErrorsPrecedeProbe() {
        let unsupportedWithInvalidPayload = Data(
            #"{"entries":"invalid","limits":null,"schemaVersion":7,"unknown":{"deep":true}}"#.utf8
        )
        assertHistoryError(.unsupportedSchemaVersion(7)) {
            try RecentWorkspaceHistory.decode(from: unsupportedWithInvalidPayload)
        }

        let duplicateSchema = Data(
            #"{"schemaVersion":7,"schema\u0056ersion":1}"#.utf8
        )
        assertHistoryError(.duplicatePersistenceKey) {
            try RecentWorkspaceHistory.decode(from: duplicateSchema)
        }

        let oversized = Data(
            repeating: 0x20,
            count: RecentWorkspaceHistory.maximumEncodedBytes + 1
        )
        assertHistoryError(
            .persistenceDataTooLarge(maximumBytes: RecentWorkspaceHistory.maximumEncodedBytes)
        ) {
            try RecentWorkspaceHistory.decode(from: oversized)
        }
    }

    func testPersistenceRejectsUnknownAndDuplicateKeysAtEveryObjectLevel() throws {
        let entry = try projectEntry(path: "file:///strict/project.macmerge")
        let unknownKeyPayloads = [
            Data(
                (#"{"entries":[\#(entry)],"future":true,"limits":{"maximumEntries":20,"maximumPathBytes":16384,"maximumWork":8388608},"schemaVersion":1}"#)
                    .utf8
            ),
            Data(
                (#"{"entries":[\#(entry)],"limits":{"future":true,"maximumEntries":20,"maximumPathBytes":16384,"maximumWork":8388608},"schemaVersion":1}"#)
                    .utf8
            ),
            Data(
                (#"{"entries":[{"availability":"available","future":true,"kind":"projectFile","path":"file:///strict/project.macmerge","pinned":false}],"limits":{"maximumEntries":20,"maximumPathBytes":16384,"maximumWork":8388608},"schemaVersion":1}"#)
                    .utf8
            )
        ]
        for data in unknownKeyPayloads {
            assertHistoryError(.unknownPersistenceKey) {
                try RecentWorkspaceHistory.decode(from: data)
            }
        }

        let duplicateKeyPayloads = [
            Data(
                (#"{"entries":[\#(entry)],"limits":{"maximumEntries":20,"maximumPathBytes":16384,"maximumWork":8388608},"schemaVersion":1,"schema\u0056ersion":1}"#)
                    .utf8
            ),
            Data(
                (#"{"entries":[\#(entry)],"limits":{"maximumEntries":20,"maximum\u0045ntries":20,"maximumPathBytes":16384,"maximumWork":8388608},"schemaVersion":1}"#)
                    .utf8
            ),
            Data(
                (#"{"entries":[{"availability":"available","kind":"projectFile","path":"file:///strict/project.macmerge","p\u0061th":"file:///strict/project.macmerge","pinned":false}],"limits":{"maximumEntries":20,"maximumPathBytes":16384,"maximumWork":8388608},"schemaVersion":1}"#)
                    .utf8
            )
        ]
        for data in duplicateKeyPayloads {
            assertHistoryError(.duplicatePersistenceKey) {
                try RecentWorkspaceHistory.decode(from: data)
            }
        }
    }

    func testPersistenceRejectsEntriesBeyondSmallerPersistedCapacity() throws {
        let entries = [
            try projectEntry(path: "file:///cap/first.macmerge"),
            try projectEntry(path: "file:///cap/second.macmerge")
        ]

        assertHistoryError(.entryLimitExceeded(maximumEntries: 1)) {
            try RecentWorkspaceHistory.decode(
                from: persistenceData(entries: entries, maximumEntries: 1)
            )
        }
    }

    func testPersistenceRejectsDuplicateEntriesAndPinnedEntriesAfterUnpinnedEntries() throws {
        let duplicate = try projectEntry(path: "file:///order/duplicate.macmerge")
        assertHistoryError(.duplicateEntry) {
            try RecentWorkspaceHistory.decode(
                from: persistenceData(entries: [duplicate, duplicate])
            )
        }

        let unpinned = try projectEntry(path: "file:///order/unpinned.macmerge")
        let pinned = try projectEntry(path: "file:///order/pinned.macmerge", pinned: true)
        assertHistoryError(.nonCanonicalPersistence) {
            try RecentWorkspaceHistory.decode(
                from: persistenceData(entries: [unpinned, pinned])
            )
        }
    }

    func testGlobalEntryCapAcceptsExactlyMaximumAndRejectsOneMore() throws {
        let maximum = RecentWorkspaceHistory.maximumSupportedEntries
        let entries = try (0...maximum).map { index in
            try projectEntry(path: "file:///cap/project-\(index).macmerge")
        }
        let exactData = persistenceData(
            entries: Array(entries.prefix(maximum)),
            maximumEntries: maximum,
            maximumPathBytes: RecentWorkspaceHistory.maximumSupportedPathBytes,
            maximumWork: RecentWorkspaceHistory.maximumSupportedWork
        )

        let exactHistory = try RecentWorkspaceHistory.decode(from: exactData)
        XCTAssertEqual(exactHistory.count, maximum)
        XCTAssertEqual(exactHistory.first?.projectFileURL?.lastPathComponent, "project-0.macmerge")
        XCTAssertEqual(exactHistory.last?.projectFileURL?.lastPathComponent, "project-999.macmerge")

        let oversizedData = persistenceData(
            entries: entries,
            maximumEntries: maximum,
            maximumPathBytes: RecentWorkspaceHistory.maximumSupportedPathBytes,
            maximumWork: RecentWorkspaceHistory.maximumSupportedWork
        )
        assertHistoryError(.entryLimitExceeded(maximumEntries: maximum)) {
            try RecentWorkspaceHistory.decode(from: oversizedData)
        }
    }

    func testCanonicalPersistenceIsExactDeterministicRoundTrippableAndStrict() throws {
        let limits = try RecentWorkspaceHistory.Limits(
            maximumEntries: 5,
            maximumPathBytes: 128,
            maximumWork: 100_000
        )
        var history = RecentWorkspaceHistory(limits: limits)
        try history.recordProjectFile(
            URL(filePath: "/canonical/project.macmerge"),
            pinned: true,
            availability: .stale
        )
        try history.recordFolderComparison(
            left: URL(filePath: "/canonical/left"),
            right: URL(filePath: "/canonical/right"),
            availability: .missing
        )
        try history.recordCommonTask(.openProject)

        let expected = Data(
            (#"{"entries":[{"availability":"stale","kind":"projectFile","path":"file:///canonical/project.macmerge","pinned":true},{"availability":"available","kind":"commonTask","pinned":false,"task":"openProject"},{"availability":"missing","kind":"folderComparison","left":"file:///canonical/left/","pinned":false,"right":"file:///canonical/right/"}],"limits":{"maximumEntries":5,"maximumPathBytes":128,"maximumWork":100000},"schemaVersion":1}"#)
                .utf8
        )

        XCTAssertEqual(try history.encodedData(), expected)
        XCTAssertEqual(try history.encodedData(), expected)
        XCTAssertEqual(try RecentWorkspaceHistory.decode(from: expected), history)

        var nonCanonical = expected
        nonCanonical.append(0x0A)
        assertHistoryError(.nonCanonicalPersistence) {
            try RecentWorkspaceHistory.decode(from: nonCanonical)
        }
    }

    func testPathPersistenceAndLimitBoundsAreExact() throws {
        let limits = try RecentWorkspaceHistory.Limits(
            maximumEntries: 1,
            maximumPathBytes: 16,
            maximumWork: 10_000
        )
        let exactPath = "/" + String(repeating: "a", count: 15)
        let oversizedPath = exactPath + "b"
        var history = RecentWorkspaceHistory(limits: limits)

        XCTAssertEqual(exactPath.utf8.count, limits.maximumPathBytes)
        XCTAssertTrue(try history.recordProjectFile(URL(filePath: exactPath)))
        assertHistoryError(.pathTooLong(maximumBytes: limits.maximumPathBytes)) {
            try history.recordProjectFile(URL(filePath: oversizedPath))
        }
        XCTAssertEqual(history.count, 1)

        let exactSizedGarbage = Data(
            repeating: 0,
            count: RecentWorkspaceHistory.maximumEncodedBytes
        )
        assertHistoryError(.malformedPersistence) {
            try RecentWorkspaceHistory.decode(from: exactSizedGarbage)
        }
        assertHistoryError(
            .persistenceDataTooLarge(maximumBytes: RecentWorkspaceHistory.maximumEncodedBytes)
        ) {
            try RecentWorkspaceHistory.decode(from: exactSizedGarbage + [0])
        }

        _ = try RecentWorkspaceHistory.Limits(
            maximumEntries: RecentWorkspaceHistory.maximumSupportedEntries,
            maximumPathBytes: RecentWorkspaceHistory.maximumSupportedPathBytes,
            maximumWork: RecentWorkspaceHistory.maximumSupportedWork
        )
        for invalidLimits in [(0, 1, 1), (1, 0, 1), (1, 1, 0), (1_001, 1, 1), (1, 65_537, 1), (1, 1, 16_777_217)] {
            assertHistoryError(.invalidLimits) {
                try RecentWorkspaceHistory.Limits(
                    maximumEntries: invalidLimits.0,
                    maximumPathBytes: invalidLimits.1,
                    maximumWork: invalidLimits.2
                )
            }
        }
    }

    func testWorkBoundFailuresCoverTaskAndPathOperationsWithoutMutation() throws {
        let limits = try RecentWorkspaceHistory.Limits(
            maximumEntries: 1,
            maximumPathBytes: 128,
            maximumWork: 1
        )
        var history = RecentWorkspaceHistory(limits: limits)

        assertHistoryError(.workLimitExceeded(maximumWork: 1)) {
            try history.recordCommonTask(.compareFiles)
        }
        XCTAssertTrue(history.isEmpty)

        let project = URL(filePath: "/work/project.macmerge")
        let folder = URL(filePath: "/work/folder", directoryHint: .isDirectory)
        assertHistoryError(.workLimitExceeded(maximumWork: 1)) {
            try history.recordProjectFile(project)
        }
        assertHistoryError(.workLimitExceeded(maximumWork: 1)) {
            try history.recordFolderComparison(left: folder, right: folder)
        }
        assertHistoryError(.workLimitExceeded(maximumWork: 1)) {
            try history.removeProjectFile(project)
        }
        assertHistoryError(.workLimitExceeded(maximumWork: 1)) {
            try history.removeFolderComparison(left: folder, right: folder)
        }
        XCTAssertTrue(history.isEmpty)

        assertHistoryError(.workLimitExceeded(maximumWork: 1)) {
            try RecentWorkspaceHistory.decode(
                from: persistenceData(
                    entries: [try projectEntry(path: "file:///work/project.macmerge")],
                    maximumEntries: 1,
                    maximumPathBytes: 128,
                    maximumWork: 1
                )
            )
        }
    }

    func testInFlightMutationEncodingAndDecodingCancellationPathsStop() async throws {
        var source = RecentWorkspaceHistory()
        try source.recordCommonTask(.compareClipboard)
        let encoded = try source.encodedData()
        let sourceHistory = source

        await assertInFlightCancellation {
            var history = RecentWorkspaceHistory()
            _ = try history.recordCommonTask(.compareFiles)
        }
        await assertInFlightCancellation {
            _ = try sourceHistory.encodedData()
        }
        await assertInFlightCancellation {
            _ = try RecentWorkspaceHistory.decode(from: encoded)
        }
    }

    private func assertRejectsEveryHistoryURLPath(
        _ invalidURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let valid = URL(filePath: "/valid", directoryHint: .isDirectory)
        var history = RecentWorkspaceHistory()

        assertHistoryError(.invalidURL, file: file, line: line) {
            try history.recordProjectFile(invalidURL)
        }
        assertHistoryError(.invalidURL, file: file, line: line) {
            try history.recordFolderComparison(left: invalidURL, right: valid)
        }
        assertHistoryError(.invalidURL, file: file, line: line) {
            try history.recordFolderComparison(left: valid, right: invalidURL)
        }
        assertHistoryError(.invalidURL, file: file, line: line) {
            try history.removeProjectFile(invalidURL)
        }
        assertHistoryError(.invalidURL, file: file, line: line) {
            try history.removeFolderComparison(left: invalidURL, right: valid)
        }
        assertHistoryError(.invalidURL, file: file, line: line) {
            try history.removeFolderComparison(left: valid, right: invalidURL)
        }

        let invalidLeftProject = try ComparisonProject(left: invalidURL, right: valid, mode: .folder)
        let invalidRightProject = try ComparisonProject(left: valid, right: invalidURL, mode: .folder)
        assertHistoryError(.invalidURL, file: file, line: line) {
            try history.recordFolderComparison(from: invalidLeftProject)
        }
        assertHistoryError(.invalidURL, file: file, line: line) {
            try history.recordFolderComparison(from: invalidRightProject)
        }

        let invalidValue = invalidURL.absoluteString
        assertHistoryError(.invalidURL, file: file, line: line) {
            try RecentWorkspaceHistory.decode(
                from: persistenceData(entries: [try projectEntry(path: invalidValue)])
            )
        }
        assertHistoryError(.invalidURL, file: file, line: line) {
            try RecentWorkspaceHistory.decode(
                from: persistenceData(entries: [try folderEntry(left: invalidValue, right: valid.absoluteString)])
            )
        }
        assertHistoryError(.invalidURL, file: file, line: line) {
            try RecentWorkspaceHistory.decode(
                from: persistenceData(entries: [try folderEntry(left: valid.absoluteString, right: invalidValue)])
            )
        }
        XCTAssertTrue(history.isEmpty, file: file, line: line)
    }

    private func assertHistoryError<T>(
        _ expected: RecentWorkspaceHistoryError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> T
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? RecentWorkspaceHistoryError, expected, file: file, line: line)
        }
    }

    private func assertInFlightCancellation(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping @Sendable () throws -> Void
    ) async {
        let gate = RecentWorkspaceCancellationGate()
        let task = Task.detached {
            await gate.enterOperationPhase()
            let outcome: RecentWorkspaceCancellationOutcome
            do {
                try operation()
                outcome = .succeeded
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed(String(describing: error))
            }
            await gate.recordCompletion(outcome)
        }
        guard await gate.waitUntilOperationPhase(timeout: .seconds(5)) else {
            task.cancel()
            await gate.releaseOperationPhase()
            _ = await gate.waitUntilCompleted(timeout: .seconds(5))
            XCTFail("Operation did not reach cancellation barrier", file: file, line: line)
            return
        }
        task.cancel()
        await gate.releaseOperationPhase()

        guard let outcome = await gate.waitUntilCompleted(timeout: .seconds(5)) else {
            task.cancel()
            XCTFail("Cancelled operation exceeded bounded wait", file: file, line: line)
            return
        }
        switch outcome {
        case .cancelled:
            break
        case .succeeded:
            XCTFail("In-flight operation unexpectedly succeeded", file: file, line: line)
        case .failed(let description):
            XCTFail("Unexpected cancellation error: \(description)", file: file, line: line)
        }
    }

    private func historyDiagnostics(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        let children = mirror.children.map { child in
            "\(child.label ?? "<nil>")=\(String(reflecting: child.value))"
        }
        return ([String(describing: value), String(reflecting: value)] + children).joined(separator: "\n")
    }

    private func projectEntry(
        path: String,
        pinned: Bool = false,
        availability: RecentWorkspaceHistory.Availability = .available
    ) throws -> String {
        let pathValue = try jsonString(path)
        return #"{"availability":"\#(availability.rawValue)","kind":"projectFile","path":\#(pathValue),"pinned":\#(pinned)}"#
    }

    private func folderEntry(
        left: String,
        right: String,
        pinned: Bool = false,
        availability: RecentWorkspaceHistory.Availability = .available
    ) throws -> String {
        let leftValue = try jsonString(left)
        let rightValue = try jsonString(right)
        return #"{"availability":"\#(availability.rawValue)","kind":"folderComparison","left":\#(leftValue),"pinned":\#(pinned),"right":\#(rightValue)}"#
    }

    private func jsonString(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func persistenceData(
        entries: [String],
        maximumEntries: Int = RecentWorkspaceHistory.defaultMaximumEntries,
        maximumPathBytes: Int = RecentWorkspaceHistory.defaultMaximumPathBytes,
        maximumWork: Int = RecentWorkspaceHistory.defaultMaximumWork
    ) -> Data {
        Data(
            (#"{"entries":[\#(entries.joined(separator: ","))],"limits":{"maximumEntries":\#(maximumEntries),"maximumPathBytes":\#(maximumPathBytes),"maximumWork":\#(maximumWork)},"schemaVersion":1}"#)
                .utf8
        )
    }
}

private enum RecentWorkspaceCancellationOutcome: Sendable {
    case succeeded
    case cancelled
    case failed(String)
}

private actor RecentWorkspaceCancellationGate {
    private var operationPhaseReached = false
    private var operationPhaseReleased = false
    private var completion: RecentWorkspaceCancellationOutcome?

    func enterOperationPhase() async {
        operationPhaseReached = true
        while !operationPhaseReleased {
            await Task.yield()
        }
    }

    func waitUntilOperationPhase(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !operationPhaseReached, clock.now < deadline {
            await Task.yield()
        }
        return operationPhaseReached
    }

    func releaseOperationPhase() {
        operationPhaseReleased = true
    }

    func recordCompletion(_ outcome: RecentWorkspaceCancellationOutcome) {
        completion = outcome
    }

    func waitUntilCompleted(timeout: Duration) async -> RecentWorkspaceCancellationOutcome? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while completion == nil, clock.now < deadline {
            await Task.yield()
        }
        return completion
    }
}
