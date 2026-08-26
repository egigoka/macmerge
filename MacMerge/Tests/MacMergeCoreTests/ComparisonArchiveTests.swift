import CryptoKit
import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class ComparisonArchiveTests: XCTestCase {
    func testSelectedDirectoryResultsPlanPreservesNonemptyMetadata() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try createDirectory(named: "left", in: workspace)
        let rightRoot = try createDirectory(named: "right", in: workspace)
        let contents = Data("selected metadata".utf8)
        let source = leftRoot.appending(path: "selected.txt")
        try contents.write(to: source)
        try setModificationTime(
            secondsSince1970: 1_700_000_000,
            nanoseconds: 123_456_789,
            at: source
        )
        let modificationDate = try exactModificationDate(at: source)
        let metadata = DirectoryEntryMetadata(
            relativePath: "selected.txt",
            kind: .file,
            byteCount: UInt64(contents.count),
            modificationDate: modificationDate
        )
        let result = DirectoryResult(left: metadata, right: nil, status: .leftOnly)
        let results = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: [result],
            selectedIDs: [result.id]
        )

        let plan = try ComparisonArchivePlanner().plan(selectedResults: results, side: .left)

        XCTAssertEqual(plan.entries.map(\.relativePath), ["selected.txt"])
        XCTAssertEqual(plan.entries.map(\.uncompressedByteCount), [UInt64(contents.count)])
        try assertTimestamp(plan.entries[0].source.snapshot.modificationTime, matches: source)
        XCTAssertNotEqual(plan.entries[0].source.snapshot.modificationTime.nanoseconds, 0)
        XCTAssertEqual(plan.totalUncompressedByteCount, UInt64(contents.count))
    }

    func testSelectedFolderEntriesPlanPreservesSizeModificationDateAndDigest() throws {
        let workspace = try temporaryDirectory()
        let root = try createDirectory(named: "root", in: workspace)
        let contents = Data("folder entry metadata".utf8)
        let source = root.appending(path: "entry.bin")
        try contents.write(to: source)
        try setModificationTime(
            secondsSince1970: 1_700_000_000,
            nanoseconds: 987_654_321,
            at: source
        )
        let digest = sha256(contents)
        let entry = FolderEntry(
            relativePath: "entry.bin",
            kind: .regularFile,
            size: UInt64(contents.count),
            modificationDate: try exactModificationDate(at: source),
            contentDigest: digest
        )
        let selected = FolderComparisonEntry(
            normalizedRelativePath: "entry.bin",
            left: entry,
            right: nil,
            status: .leftOnly
        )

        let plan = try ComparisonArchivePlanner().plan(
            selectedEntries: [selected],
            rootURL: root,
            side: .left
        )

        XCTAssertEqual(plan.entries.map(\.relativePath), ["entry.bin"])
        XCTAssertEqual(plan.entries[0].uncompressedByteCount, UInt64(contents.count))
        try assertTimestamp(plan.entries[0].source.snapshot.modificationTime, matches: source)
        XCTAssertNotEqual(plan.entries[0].source.snapshot.modificationTime.nanoseconds, 0)
        XCTAssertEqual(plan.entries[0].source.snapshot.contentDigest, digest)
    }

    func testDirectoryResultsAdapterUsesAsymmetricRightPathAndRejectsMissingSides() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try createDirectory(named: "left", in: workspace)
        let rightRoot = try createDirectory(named: "right", in: workspace)
        let left = DirectoryEntryMetadata(
            relativePath: "left-name.txt",
            kind: .file,
            byteCount: 4
        )
        let right = DirectoryEntryMetadata(
            relativePath: "right-name.txt",
            kind: .file,
            byteCount: 5
        )
        try Data("left".utf8).write(to: leftRoot.appending(path: left.relativePath))
        try Data("right".utf8).write(to: rightRoot.appending(path: right.relativePath))
        let paired = DirectoryResult(left: left, right: right, status: .different)
        let pairedResults = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: [paired],
            selectedIDs: [paired.id]
        )

        let rightPlan = try ComparisonArchivePlanner().plan(
            selectedResults: pairedResults,
            side: .right
        )

        XCTAssertEqual(rightPlan.entries.map(\.relativePath), ["right-name.txt"])
        XCTAssertEqual(rightPlan.entries[0].source.rootURL, rightRoot)
        XCTAssertEqual(rightPlan.entries[0].source.relativePath, "right-name.txt")

        let leftOnly = DirectoryResult(left: left, right: nil, status: .leftOnly)
        let rightOnly = DirectoryResult(left: nil, right: right, status: .rightOnly)
        for (result, side, path) in [
            (leftOnly, FolderComparisonSide.right, left.relativePath),
            (rightOnly, FolderComparisonSide.left, right.relativePath)
        ] {
            let results = DirectoryResults(
                leftRoot: leftRoot,
                rightRoot: rightRoot,
                results: [result],
                selectedIDs: [result.id]
            )
            assertPlanError(.selectedResultMissingSide(path: path, side: side)) {
                _ = try ComparisonArchivePlanner().plan(selectedResults: results, side: side)
            }
        }
    }

    func testFolderEntriesAdapterUsesAsymmetricRightPathAndRejectsMissingSides() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try createDirectory(named: "left", in: workspace)
        let rightRoot = try createDirectory(named: "right", in: workspace)
        let left = FolderEntry(relativePath: "left-name.txt", kind: .regularFile, size: 4)
        let right = FolderEntry(relativePath: "right-name.txt", kind: .regularFile, size: 5)
        try Data("left".utf8).write(to: leftRoot.appending(path: left.relativePath))
        try Data("right".utf8).write(to: rightRoot.appending(path: right.relativePath))
        let paired = FolderComparisonEntry(
            normalizedRelativePath: "paired.txt",
            left: left,
            right: right,
            status: .metadataDifferent([.size])
        )

        let rightPlan = try ComparisonArchivePlanner().plan(
            selectedEntries: [paired],
            rootURL: rightRoot,
            side: .right
        )

        XCTAssertEqual(rightPlan.entries.map(\.relativePath), ["right-name.txt"])
        XCTAssertEqual(rightPlan.entries[0].source.rootURL, rightRoot)
        XCTAssertEqual(rightPlan.entries[0].source.relativePath, "right-name.txt")

        let leftOnly = FolderComparisonEntry(
            normalizedRelativePath: "left-only.txt",
            left: left,
            right: nil,
            status: .leftOnly
        )
        let rightOnly = FolderComparisonEntry(
            normalizedRelativePath: "right-only.txt",
            left: nil,
            right: right,
            status: .rightOnly
        )
        for (entry, root, side, path) in [
            (leftOnly, rightRoot, FolderComparisonSide.right, "left-only.txt"),
            (rightOnly, leftRoot, FolderComparisonSide.left, "right-only.txt")
        ] {
            assertPlanError(.selectedResultMissingSide(path: path, side: side)) {
                _ = try ComparisonArchivePlanner().plan(
                    selectedEntries: [entry],
                    rootURL: root,
                    side: side
                )
            }
        }
    }

    func testAdaptersPlanOnlyExplicitSelectionsAndAcceptEmptySelections() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try createDirectory(named: "left", in: workspace)
        let rightRoot = try createDirectory(named: "right", in: workspace)
        let selectedMetadata = DirectoryEntryMetadata(
            relativePath: "selected.txt",
            kind: .file,
            byteCount: 8
        )
        let unselectedMetadata = DirectoryEntryMetadata(
            relativePath: "missing-unselected.txt",
            kind: .file,
            byteCount: 1
        )
        try Data("selected".utf8).write(to: leftRoot.appending(path: selectedMetadata.relativePath))
        let selectedResult = DirectoryResult(
            left: selectedMetadata,
            right: nil,
            status: .leftOnly
        )
        let unselectedResult = DirectoryResult(
            left: unselectedMetadata,
            right: nil,
            status: .leftOnly
        )
        let directoryResults = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: [selectedResult, unselectedResult],
            selectedIDs: [selectedResult.id]
        )

        let selectedDirectoryPlan = try ComparisonArchivePlanner().plan(
            selectedResults: directoryResults,
            side: .left
        )
        XCTAssertEqual(selectedDirectoryPlan.entries.map(\.relativePath), ["selected.txt"])

        let emptyDirectoryResults = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: [unselectedResult]
        )
        try assertEmptyPlan(
            ComparisonArchivePlanner().plan(selectedResults: emptyDirectoryResults, side: .left)
        )

        let selectedEntry = FolderComparisonEntry(
            normalizedRelativePath: "selected.txt",
            left: FolderEntry(
                relativePath: "selected.txt",
                kind: .regularFile,
                size: 8
            ),
            right: nil,
            status: .leftOnly
        )
        let selectedFolderPlan = try ComparisonArchivePlanner().plan(
            selectedEntries: [selectedEntry],
            rootURL: leftRoot,
            side: .left
        )
        XCTAssertEqual(selectedFolderPlan.entries.map(\.relativePath), ["selected.txt"])
        try assertEmptyPlan(
            ComparisonArchivePlanner().plan(
                selectedEntries: [],
                rootURL: leftRoot,
                side: .left
            ))
    }

    func testAdaptersRejectStaleSizeAndModificationDate() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try createDirectory(named: "left", in: workspace)
        let rightRoot = try createDirectory(named: "right", in: workspace)
        let source = leftRoot.appending(path: "stale.txt")
        let contents = Data("data".utf8)
        try contents.write(to: source)
        try setModificationTime(
            secondsSince1970: 1_700_000_000,
            nanoseconds: 222_333_444,
            at: source
        )
        let actualDate = try modificationDate(at: source)
        let staleDate = actualDate.addingTimeInterval(-1)

        let staleDirectorySize = DirectoryEntryMetadata(
            relativePath: "stale.txt",
            kind: .file,
            byteCount: UInt64(contents.count + 1),
            modificationDate: actualDate
        )
        let staleDirectoryDate = DirectoryEntryMetadata(
            relativePath: "stale.txt",
            kind: .file,
            byteCount: UInt64(contents.count),
            modificationDate: staleDate
        )
        for (metadata, expectedError) in [
            (
                staleDirectorySize,
                ComparisonArchivePlanError.sourceByteCountChanged(
                    path: "stale.txt",
                    expected: UInt64(contents.count + 1),
                    actual: UInt64(contents.count)
                )
            ),
            (
                staleDirectoryDate,
                ComparisonArchivePlanError.sourceModificationTimeChanged("stale.txt")
            )
        ] {
            let result = DirectoryResult(left: metadata, right: nil, status: .leftOnly)
            let results = DirectoryResults(
                leftRoot: leftRoot,
                rightRoot: rightRoot,
                results: [result],
                selectedIDs: [result.id]
            )
            assertPlanError(expectedError) {
                _ = try ComparisonArchivePlanner().plan(selectedResults: results, side: .left)
            }
        }

        let staleFolderSize = FolderEntry(
            relativePath: "stale.txt",
            kind: .regularFile,
            size: UInt64(contents.count + 1),
            modificationDate: actualDate
        )
        let staleFolderDate = FolderEntry(
            relativePath: "stale.txt",
            kind: .regularFile,
            size: UInt64(contents.count),
            modificationDate: staleDate
        )
        for (entry, expectedError) in [
            (
                staleFolderSize,
                ComparisonArchivePlanError.sourceByteCountChanged(
                    path: "stale.txt",
                    expected: UInt64(contents.count + 1),
                    actual: UInt64(contents.count)
                )
            ),
            (
                staleFolderDate,
                ComparisonArchivePlanError.sourceModificationTimeChanged("stale.txt")
            )
        ] {
            let selected = FolderComparisonEntry(
                normalizedRelativePath: "stale.txt",
                left: entry,
                right: nil,
                status: .leftOnly
            )
            assertPlanError(expectedError) {
                _ = try ComparisonArchivePlanner().plan(
                    selectedEntries: [selected],
                    rootURL: leftRoot,
                    side: .left
                )
            }
        }
    }

    func testOmittedItemsAreRemovedBeforeArchivePathCollisionChecks() throws {
        let root = try temporaryDirectory()
        let file = root.appending(path: "file.txt")
        let link = root.appending(path: "link.txt")
        try Data("included".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let policy = ComparisonArchiveItemPolicy(symbolicLinks: .omit)
        let inputs = [
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "file.txt",
                archiveRelativePath: "shared.txt",
                kind: .regularFile
            ),
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "link.txt",
                archiveRelativePath: "shared.txt",
                kind: .symbolicLink
            )
        ]

        let plan = try ComparisonArchivePlanner(itemPolicy: policy).plan(inputs: inputs)

        XCTAssertEqual(plan.entries.map(\.relativePath), ["shared.txt"])
        XCTAssertEqual(plan.omissions.count, 1)
        XCTAssertEqual(plan.omissions[0].archiveRelativePath, "shared.txt")
        XCTAssertEqual(plan.omissions[0].reason, .symbolicLink)
    }

    func testIncludedArchivePathsRejectExactCaseNFCHierarchyAndDirectoryCollisions() throws {
        let root = try temporaryDirectory()
        for name in ["a", "b"] {
            try Data(name.utf8).write(to: root.appending(path: name))
        }

        func input(source: String, archive: String) -> ComparisonArchiveInput {
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: source,
                archiveRelativePath: archive,
                kind: .regularFile
            )
        }

        assertPlanError(.duplicateArchivePath("same.txt")) {
            _ = try ComparisonArchivePlanner().plan(inputs: [
                input(source: "a", archive: "same.txt"),
                input(source: "b", archive: "same.txt")
            ])
        }
        assertPlanError(.caseFoldedPathConflict(first: "Name.txt", second: "name.txt")) {
            _ = try ComparisonArchivePlanner().plan(inputs: [
                input(source: "a", archive: "Name.txt"),
                input(source: "b", archive: "name.txt")
            ])
        }
        let composed = "caf\u{E9}.txt"
        let decomposed = "cafe\u{301}.txt"
        assertPlanError(.duplicateArchivePath(composed)) {
            _ = try ComparisonArchivePlanner().plan(inputs: [
                input(source: "a", archive: decomposed),
                input(source: "b", archive: composed)
            ])
        }
        assertPlanError(.pathHierarchyConflict(ancestor: "node", descendant: "node/child")) {
            _ = try ComparisonArchivePlanner().plan(inputs: [
                input(source: "a", archive: "node"),
                input(source: "b", archive: "node/child")
            ])
        }
        assertPlanError(.caseFoldedPathConflict(first: "Folder", second: "folder")) {
            _ = try ComparisonArchivePlanner().plan(inputs: [
                input(source: "a", archive: "Folder/a"),
                input(source: "b", archive: "folder/b")
            ])
        }
    }

    func testSecureDefaultRejectsSymbolicLinksAndSpecialFiles() throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "target")
        let link = root.appending(path: "link")
        let fifo = root.appending(path: "fifo")
        try Data("target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(Darwin.mkfifo(fifo.path, 0o600), 0)

        for (path, kind) in [
            ("link", ComparisonArchiveInputKind.symbolicLink),
            ("fifo", ComparisonArchiveInputKind.specialFile)
        ] {
            let input = ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: path,
                kind: kind
            )
            assertPlanError(.unsupportedSourceItem(path: path, kind: kind)) {
                _ = try ComparisonArchivePlanner().plan(inputs: [input])
            }
        }
    }

    func testUnsafeArchivePathsAreRejectedBeforeSourceAccess() throws {
        let root = try temporaryDirectory()
        let cases: [(String, ComparisonArchivePathFailure)] = [
            ("", .empty),
            ("/absolute", .absolute),
            (#"folder\file"#, .containsBackslash),
            ("folder\0file", .containsNull),
            ("folder//file", .emptyComponent),
            ("folder/./file", .currentDirectoryComponent),
            ("folder/../file", .parentTraversal),
            ("C:/Windows/file", .containsColon),
            ("file.txt:stream", .containsColon),
            ("CON.txt", .reservedDOSDeviceName),
            ("folder/lPt1.log", .reservedDOSDeviceName),
            ("trailing.", .trailingDotOrSpace),
            ("trailing ", .trailingDotOrSpace),
            (String(repeating: "a", count: 256), .componentTooLong),
            (String(repeating: "a", count: 4_097), .pathTooLong),
            ("\u{200C}", .emptyCollisionKey)
        ]

        for (path, reason) in cases {
            let input = ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "missing-source",
                archiveRelativePath: path,
                kind: .regularFile
            )
            assertPlanError(.invalidRelativePath(role: .archive, path: path, reason: reason)) {
                _ = try ComparisonArchivePlanner().plan(inputs: [input])
            }
        }
    }

    func testUnsafeSourceTraversalAndIntermediateSymlinkAreRejected() throws {
        let workspace = try temporaryDirectory()
        let root = try createDirectory(named: "root", in: workspace)
        let outside = try createDirectory(named: "outside", in: workspace)
        try Data("outside".utf8).write(to: outside.appending(path: "file"))

        let traversal = ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: "../outside/file",
            archiveRelativePath: "file",
            kind: .regularFile
        )
        assertPlanError(
            .invalidRelativePath(
                role: .source,
                path: "../outside/file",
                reason: .parentTraversal
            )
        ) {
            _ = try ComparisonArchivePlanner().plan(inputs: [traversal])
        }

        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "linked", directoryHint: .isDirectory),
            withDestinationURL: outside
        )
        let linked = ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: "linked/file",
            archiveRelativePath: "file",
            kind: .regularFile
        )
        assertPlanError(.sourceUnavailable(path: "linked/file", errorCode: ENOTDIR)) {
            _ = try ComparisonArchivePlanner().plan(inputs: [linked])
        }
    }

    func testInvalidSourceRootErrorRedactsCredentialsQueryAndFragment() throws {
        let root = try temporaryDirectory()
        var components = try XCTUnwrap(URLComponents(url: root, resolvingAgainstBaseURL: false))
        components.user = "private-user"
        components.password = "private-password"
        components.queryItems = [URLQueryItem(name: "access_token", value: "private-token")]
        components.fragment = "private-fragment"
        let invalidRoot = try XCTUnwrap(components.url)
        let input = ComparisonArchiveInput(
            sourceRootURL: invalidRoot,
            sourceRelativePath: "item",
            kind: .regularFile
        )

        XCTAssertThrowsError(try ComparisonArchivePlanner().plan(inputs: [input])) { error in
            guard let planError = error as? ComparisonArchivePlanError,
                case .invalidSourceRoot(let description) = planError
            else {
                return XCTFail("Expected invalidSourceRoot, got \(error)")
            }
            XCTAssertTrue(description.contains(root.path))
            XCTAssertFalse(description.contains("private-user"))
            XCTAssertFalse(description.contains("private-password"))
            XCTAssertFalse(description.contains("access_token"))
            XCTAssertFalse(description.contains("private-token"))
            XCTAssertFalse(description.contains("private-fragment"))
        }
    }

    func testInvalidSourceRootConditionsAreRejectedIndependently() throws {
        let root = try temporaryDirectory()
        let invalidRoots = try [
            XCTUnwrap(URL(string: "https://example.com/root")),
            XCTUnwrap(URL(string: "file:relative")),
            XCTUnwrap(URL(string: "file://remote.example/private/tmp")),
            URL(fileURLWithPath: "child", relativeTo: root),
            XCTUnwrap(URL(string: "file:////private/tmp")),
            XCTUnwrap(URL(string: "file:///private//tmp")),
            XCTUnwrap(URL(string: "file:///private/./tmp")),
            XCTUnwrap(URL(string: "file:///private/../tmp")),
            rootWithComponent(root, keyPath: \.user, value: "private-user"),
            rootWithComponent(root, keyPath: \.password, value: "private-password"),
            rootWithComponent(root, keyPath: \.port, value: 81),
            rootWithComponent(root, keyPath: \.query, value: "private-query"),
            rootWithComponent(root, keyPath: \.fragment, value: "private-fragment")
        ]

        for invalidRoot in invalidRoots {
            let input = ComparisonArchiveInput(
                sourceRootURL: invalidRoot,
                sourceRelativePath: "missing",
                kind: .regularFile
            )
            XCTAssertThrowsError(try ComparisonArchivePlanner().plan(inputs: [input])) { error in
                guard let planError = error as? ComparisonArchivePlanError,
                    case .invalidSourceRoot = planError
                else {
                    return XCTFail("Expected invalidSourceRoot for \(invalidRoot), got \(error)")
                }
            }
        }
    }

    func testPlannedMetadataRecommendsPrivatePortablePermissionsAndReproducibleTime() throws {
        let root = try temporaryDirectory()
        let file = root.appending(path: "file.txt")
        let directory = root.appending(path: "empty", directoryHint: .isDirectory)
        try Data("private".utf8).write(to: file)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let inputs = [
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "file.txt",
                kind: .regularFile
            ),
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "empty",
                kind: .directory
            )
        ]

        let plan = try ComparisonArchivePlanner().plan(inputs: inputs)
        let metadataByPath = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.relativePath, $0.metadata) })

        XCTAssertEqual(metadataByPath["file.txt"]?.unixPermissions, 0o600)
        XCTAssertEqual(metadataByPath["empty"]?.unixPermissions, 0o700)
        XCTAssertTrue(
            metadataByPath.values.allSatisfy {
                $0.modificationTime == ComparisonArchiveEntryMetadata.reproducibleModificationTime
            }
        )
    }

    func testSameSizeReplacementWithRestoredModificationTimeFailsClosed() throws {
        let root = try temporaryDirectory()
        let source = root.appending(path: "item.bin")
        let replacement = root.appending(path: "replacement.bin")
        let original = Data("AAAA".utf8)
        let changed = Data("BBBB".utf8)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try original.write(to: source)
        try setModificationDate(fixedDate, at: source)
        let capturedDate = try modificationDate(at: source)
        let input = ComparisonArchiveInput(
            sourceRootURL: root,
            entry: FolderEntry(
                relativePath: "item.bin",
                kind: .regularFile,
                size: UInt64(original.count),
                modificationDate: capturedDate,
                contentDigest: sha256(original)
            )
        )
        try changed.write(to: replacement)
        try setModificationDate(capturedDate, at: replacement)
        try replaceItem(at: source, with: replacement)

        XCTAssertEqual(try modificationDate(at: source), capturedDate)
        XCTAssertEqual(try Data(contentsOf: source).count, original.count)
        assertPlanError(.sourceContentDigestChanged("item.bin")) {
            _ = try ComparisonArchivePlanner().plan(inputs: [input])
        }
    }

    func testStaleNanosecondModificationTimeIsRejected() throws {
        let root = try temporaryDirectory()
        let source = root.appending(path: "nanoseconds.bin")
        try Data("time".utf8).write(to: source)
        try setModificationTime(
            secondsSince1970: 1_700_000_000,
            nanoseconds: 111_111_111,
            at: source
        )
        let expectedDate = try modificationDate(at: source)
        try setModificationTime(
            secondsSince1970: 1_700_000_000,
            nanoseconds: 222_222_222,
            at: source
        )

        let input = ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: "nanoseconds.bin",
            kind: .regularFile,
            expectedByteCount: 4,
            expectedModificationDate: expectedDate
        )
        assertPlanError(.sourceModificationTimeChanged("nanoseconds.bin")) {
            _ = try ComparisonArchivePlanner().plan(inputs: [input])
        }
    }

    func testPlanPinsRootAndSourceIdentityAcrossPathReplacement() throws {
        let workspace = try temporaryDirectory()
        let root = try createDirectory(named: "root", in: workspace)
        let movedRoot = workspace.appending(path: "moved-root", directoryHint: .isDirectory)
        let source = root.appending(path: "payload.txt")
        let original = Data("original".utf8)
        try original.write(to: source)
        let plan = try ComparisonArchivePlanner().plan(inputs: [
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "payload.txt",
                kind: .regularFile
            )
        ])
        let plannedSource = try XCTUnwrap(plan.entries.first?.source)

        try FileManager.default.moveItem(at: root, to: movedRoot)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("replaced".utf8).write(to: root.appending(path: "payload.txt"))
        let replacementRootStatus = try status(at: root)

        XCTAssertNotEqual(plannedSource.rootIdentity.fileID, UInt64(replacementRootStatus.st_ino))
        let pinnedContents = try plannedSource.withPinnedRootDescriptor { rootDescriptor -> Data in
            let rootStatus = try descriptorStatus(rootDescriptor)
            XCTAssertEqual(
                plannedSource.rootIdentity.deviceID,
                UInt64(bitPattern: Int64(rootStatus.st_dev))
            )
            XCTAssertEqual(plannedSource.rootIdentity.fileID, UInt64(rootStatus.st_ino))
            XCTAssertEqual(plannedSource.rootIdentity.generation, rootStatus.st_gen)

            let itemDescriptor = "payload.txt".withCString {
                Darwin.openat(rootDescriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard itemDescriptor >= 0 else {
                throw posixError()
            }
            defer { Darwin.close(itemDescriptor) }
            let itemStatus = try descriptorStatus(itemDescriptor)
            XCTAssertEqual(plannedSource.snapshot.identity.fileID, UInt64(itemStatus.st_ino))
            return try readAll(from: itemDescriptor, byteCount: original.count)
        }

        XCTAssertEqual(pinnedContents, original)
    }

    func testExactSHA256DigestIsCanonicalizedAndAccepted() throws {
        let root = try temporaryDirectory()
        let contents = Data("digest exact bytes".utf8)
        let source = root.appending(path: "digest.bin")
        try contents.write(to: source)
        let exactDigest = sha256(contents, algorithm: " SHA-256\n")
        let input = ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: "digest.bin",
            kind: .regularFile,
            expectedByteCount: UInt64(contents.count),
            expectedContentDigest: exactDigest
        )

        let plan = try ComparisonArchivePlanner().plan(inputs: [input])

        XCTAssertEqual(
            plan.entries[0].source.snapshot.contentDigest,
            FolderContentDigest(algorithm: "sha256", bytes: exactDigest.bytes)
        )
    }

    func testDigestVerificationIncludesAppendedBytes() throws {
        let root = try temporaryDirectory()
        let original = Data("prefix".utf8)
        let source = root.appending(path: "append.bin")
        try original.write(to: source)
        let input = ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: "append.bin",
            kind: .regularFile,
            expectedContentDigest: sha256(original)
        )
        var appended = original
        appended.append(Data("-appended".utf8))
        try appended.write(to: source)

        assertPlanError(.sourceContentDigestChanged("append.bin")) {
            _ = try ComparisonArchivePlanner().plan(inputs: [input])
        }
    }

    func testMalformedAndUnsupportedDigestsAreRejected() throws {
        let root = try temporaryDirectory()
        let source = root.appending(path: "digest.bin")
        let contents = Data("digest".utf8)
        try contents.write(to: source)

        for byteCount in [0, SHA256.Digest.byteCount - 1, SHA256.Digest.byteCount + 1] {
            let input = ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "digest.bin",
                kind: .regularFile,
                expectedContentDigest: FolderContentDigest(
                    algorithm: "sha256",
                    bytes: Data(repeating: 0, count: byteCount)
                )
            )
            assertPlanError(.invalidInputMetadata(path: "digest.bin")) {
                _ = try ComparisonArchivePlanner().plan(inputs: [input])
            }
        }

        let unsupported = FolderContentDigest(
            algorithm: " SHA-512\n",
            bytes: Data(repeating: 0, count: SHA256.Digest.byteCount)
        )
        let unsupportedInput = ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: "digest.bin",
            kind: .regularFile,
            expectedContentDigest: unsupported
        )
        assertPlanError(
            .unsupportedSourceDigest(path: "digest.bin", algorithm: unsupported.algorithm)
        ) {
            _ = try ComparisonArchivePlanner().plan(inputs: [unsupportedInput])
        }

        let directory = try createDirectory(named: "directory", in: root)
        let digestOnDirectory = ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: directory.lastPathComponent,
            kind: .directory,
            expectedContentDigest: sha256(Data())
        )
        assertPlanError(.invalidInputMetadata(path: "directory")) {
            _ = try ComparisonArchivePlanner().plan(inputs: [digestOnDirectory])
        }
    }

    func testAggregatePathLimitsFailBeforeMissingSourceAccess() throws {
        let root = try temporaryDirectory()
        let inputs = [
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "missing-a",
                archiveRelativePath: "aaa",
                kind: .regularFile
            ),
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "missing-b",
                archiveRelativePath: "bbb",
                kind: .regularFile
            )
        ]

        assertPlanError(.totalPathSizeTooLarge(maximumBytes: 5)) {
            _ = try ComparisonArchivePlanner(
                limits: ComparisonArchivePlanLimits(maximumTotalPathUTF8Bytes: 5)
            ).plan(inputs: inputs)
        }
        let componentInputs = [
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "missing-a",
                archiveRelativePath: "a/b",
                kind: .regularFile
            ),
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "missing-b",
                archiveRelativePath: "c",
                kind: .regularFile
            )
        ]
        assertPlanError(.tooManyPathComponents(maximum: 2)) {
            _ = try ComparisonArchivePlanner(
                limits: ComparisonArchivePlanLimits(maximumTotalPathComponents: 2)
            ).plan(inputs: componentInputs)
        }
    }

    func testAggregateUncompressedLimitRejectsSelection() throws {
        let root = try temporaryDirectory()
        try Data("aa".utf8).write(to: root.appending(path: "a"))
        try Data("bb".utf8).write(to: root.appending(path: "b"))
        let inputs = ["a", "b"].map {
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: $0,
                kind: .regularFile
            )
        }

        assertPlanError(.totalUncompressedSizeTooLarge(maximumBytes: 3)) {
            _ = try ComparisonArchivePlanner(
                limits: ComparisonArchivePlanLimits(maximumTotalUncompressedBytes: 3)
            ).plan(inputs: inputs)
        }
    }

    func testEveryPlanLimitAcceptsExactBoundaryAndRejectsPlusOne() throws {
        let root = try temporaryDirectory()
        try Data("a".utf8).write(to: root.appending(path: "a"))
        try Data("b".utf8).write(to: root.appending(path: "b"))
        try FileManager.default.createDirectory(
            at: root.appending(path: "d", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )

        let fileA = archiveInput(root: root, source: "a", archive: "a")
        let fileB = archiveInput(root: root, source: "b", archive: "b")
        let nested = archiveInput(root: root, source: "a", archive: "x/a")
        let directory = ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: "d",
            archiveRelativePath: "d",
            kind: .directory
        )
        let oneFileArchiveByteCount = try ComparisonArchivePlanner().plan(inputs: [fileA])
            .estimatedArchiveByteCount

        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumArchiveBytes: oneFileArchiveByteCount),
            plusOneInput: [fileA],
            plusOneLimits: ComparisonArchivePlanLimits(
                maximumArchiveBytes: oneFileArchiveByteCount - 1
            ),
            expected: .archiveTooLarge(maximumBytes: oneFileArchiveByteCount - 1),
            exactInputs: [fileA]
        )
        XCTAssertEqual(
            try ComparisonArchivePlanner().plan(inputs: [directory]).entries.map(\.kind),
            [.directory]
        )
        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumEntryCount: 1),
            plusOneInput: [fileA, fileB],
            plusOneLimits: ComparisonArchivePlanLimits(maximumEntryCount: 1),
            expected: .tooManyEntries(maximum: 1),
            exactInputs: [fileA]
        )
        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumEntryUncompressedBytes: 1),
            plusOneInput: [fileA],
            plusOneLimits: ComparisonArchivePlanLimits(maximumEntryUncompressedBytes: 0),
            expected: .entryTooLarge(path: "a", maximumBytes: 0),
            exactInputs: [fileA]
        )
        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumTotalUncompressedBytes: 1),
            plusOneInput: [fileA, fileB],
            plusOneLimits: ComparisonArchivePlanLimits(maximumTotalUncompressedBytes: 1),
            expected: .totalUncompressedSizeTooLarge(maximumBytes: 1),
            exactInputs: [fileA]
        )
        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumPathDepth: 2),
            plusOneInput: [nested],
            plusOneLimits: ComparisonArchivePlanLimits(maximumPathDepth: 1),
            expected: .pathTooDeep(path: "x/a", maximumDepth: 1),
            exactInputs: [nested]
        )
        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumPathUTF8Bytes: 3),
            plusOneInput: [nested],
            plusOneLimits: ComparisonArchivePlanLimits(maximumPathUTF8Bytes: 2),
            expected: .invalidRelativePath(role: .archive, path: "x/a", reason: .pathTooLong),
            exactInputs: [nested]
        )
        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumTotalPathUTF8Bytes: 3),
            plusOneInput: [nested],
            plusOneLimits: ComparisonArchivePlanLimits(maximumTotalPathUTF8Bytes: 2),
            expected: .totalPathSizeTooLarge(maximumBytes: 2),
            exactInputs: [nested]
        )
        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumTotalPathComponents: 2),
            plusOneInput: [nested],
            plusOneLimits: ComparisonArchivePlanLimits(maximumTotalPathComponents: 1),
            expected: .tooManyPathComponents(maximum: 1),
            exactInputs: [nested]
        )

        let secondRoot = try createDirectory(named: "second", in: root)
        try Data("c".utf8).write(to: secondRoot.appending(path: "c"))
        let secondRootFile = archiveInput(root: secondRoot, source: "c", archive: "c")
        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumSourceRoots: 1),
            plusOneInput: [fileA, secondRootFile],
            plusOneLimits: ComparisonArchivePlanLimits(maximumSourceRoots: 1),
            expected: .tooManySourceRoots(maximum: 1),
            exactInputs: [fileA]
        )
        try assertLimitBoundary(
            exact: ComparisonArchivePlanLimits(maximumOpenFileDescriptors: 3),
            plusOneInput: [fileA],
            plusOneLimits: ComparisonArchivePlanLimits(maximumOpenFileDescriptors: 2),
            expected: .tooManyOpenFileDescriptors(maximum: 2),
            exactInputs: [fileA]
        )
    }

    func testSourceRootAndDescriptorLimitsPrecedeUnavailableRootErrors() throws {
        let workspace = try temporaryDirectory()
        let availableRoot = try createDirectory(named: "available", in: workspace)
        let unavailableRoot = workspace.appending(path: "unavailable", directoryHint: .isDirectory)
        try Data("a".utf8).write(to: availableRoot.appending(path: "a"))
        let twoRootInputs = [
            ComparisonArchiveInput(
                sourceRootURL: availableRoot,
                sourceRelativePath: "a",
                archiveRelativePath: "a",
                kind: .regularFile
            ),
            ComparisonArchiveInput(
                sourceRootURL: unavailableRoot,
                sourceRelativePath: "b",
                archiveRelativePath: "b",
                kind: .regularFile
            )
        ]

        assertPlanError(.tooManySourceRoots(maximum: 1)) {
            _ = try ComparisonArchivePlanner(
                limits: ComparisonArchivePlanLimits(maximumSourceRoots: 1)
            ).plan(inputs: twoRootInputs)
        }
        let unavailableInput = ComparisonArchiveInput(
            sourceRootURL: unavailableRoot,
            sourceRelativePath: "item",
            kind: .regularFile
        )
        assertPlanError(.tooManyOpenFileDescriptors(maximum: 2)) {
            _ = try ComparisonArchivePlanner(
                limits: ComparisonArchivePlanLimits(maximumOpenFileDescriptors: 2)
            ).plan(inputs: [unavailableInput])
        }
    }

    func testPlanningObservesPreexistingCancellation() async {
        let error = await Task { () -> (any Error)? in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            do {
                _ = try ComparisonArchivePlanner().plan(inputs: [])
                return nil
            } catch {
                return error
            }
        }.value

        XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(String(describing: error))")
    }

    func testPlanIsDeterministicAcrossInputOrder() throws {
        let root = try temporaryDirectory()
        try Data("alpha".utf8).write(to: root.appending(path: "alpha.txt"))
        try Data("zeta".utf8).write(to: root.appending(path: "zeta.txt"))
        try FileManager.default.createDirectory(
            at: root.appending(path: "empty", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        let inputs = [
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "zeta.txt",
                kind: .regularFile
            ),
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "empty",
                kind: .directory
            ),
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "alpha.txt",
                kind: .regularFile
            )
        ]

        let forward = try ComparisonArchivePlanner().plan(inputs: inputs)
        let reversed = try ComparisonArchivePlanner().plan(inputs: inputs.reversed())

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.entries.map(\.relativePath), ["alpha.txt", "empty", "zeta.txt"])
        XCTAssertEqual(forward.estimatedArchiveByteCount, 305)
    }

    func testUnsupportedContainerAndCompressionFormatsAreRejected() {
        XCTAssertEqual(ComparisonArchivePlanner.supportedFormats, [.zip])
        XCTAssertEqual(ComparisonArchivePlanner.supportedCompressionFormats, [.store])

        for format in ComparisonArchiveContainerFormat.allCases where format != .zip {
            assertPlanError(.unsupportedContainerFormat(format)) {
                _ = try ComparisonArchivePlanner().plan(inputs: [], format: format)
            }
        }
        for compression in ComparisonArchiveCompressionFormat.allCases where compression != .store {
            assertPlanError(.unsupportedCompressionFormat(compression)) {
                _ = try ComparisonArchivePlanner().plan(inputs: [], compression: compression)
            }
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "MacMergeComparisonArchiveTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func createDirectory(named name: String, in parent: URL) throws -> URL {
        let directory = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func modificationDate(at url: URL) throws -> Date {
        try XCTUnwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    private func exactModificationDate(at url: URL) throws -> Date {
        let modificationTime = try status(at: url).st_mtimespec
        return Date(
            timeIntervalSince1970: Double(modificationTime.tv_sec)
                + Double(modificationTime.tv_nsec) / 1_000_000_000
        )
    }

    private func setModificationDate(_ date: Date, at url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func setModificationTime(
        secondsSince1970: Int64,
        nanoseconds: Int,
        at url: URL
    ) throws {
        var timestamps = [
            timespec(tv_sec: time_t(secondsSince1970), tv_nsec: nanoseconds),
            timespec(tv_sec: time_t(secondsSince1970), tv_nsec: nanoseconds)
        ]
        let result = timestamps.withUnsafeMutableBufferPointer { buffer in
            url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else {
                    errno = EINVAL
                    return -1
                }
                return Darwin.utimensat(AT_FDCWD, path, buffer.baseAddress, 0)
            }
        }
        guard result == 0 else { throw posixError() }
    }

    private func rootWithComponent<Value>(
        _ root: URL,
        keyPath: WritableKeyPath<URLComponents, Value>,
        value: Value
    ) throws -> URL {
        var components = try XCTUnwrap(URLComponents(url: root, resolvingAgainstBaseURL: false))
        components[keyPath: keyPath] = value
        return try XCTUnwrap(components.url)
    }

    private func archiveInput(
        root: URL,
        source: String,
        archive: String
    ) -> ComparisonArchiveInput {
        ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: source,
            archiveRelativePath: archive,
            kind: .regularFile
        )
    }

    private func assertEmptyPlan(
        _ plan: ComparisonArchivePlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(plan.entries.isEmpty, file: file, line: line)
        XCTAssertTrue(plan.omissions.isEmpty, file: file, line: line)
        XCTAssertEqual(plan.totalUncompressedByteCount, 0, file: file, line: line)
        XCTAssertEqual(plan.estimatedArchiveByteCount, 22, file: file, line: line)
    }

    private func assertLimitBoundary(
        exact: ComparisonArchivePlanLimits,
        plusOneInput: [ComparisonArchiveInput],
        plusOneLimits: ComparisonArchivePlanLimits,
        expected: ComparisonArchivePlanError,
        exactInputs: [ComparisonArchiveInput],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let plan = try ComparisonArchivePlanner(limits: exact).plan(inputs: exactInputs)
        XCTAssertEqual(plan.limits, exact, file: file, line: line)
        assertPlanError(expected, file: file, line: line) {
            _ = try ComparisonArchivePlanner(limits: plusOneLimits).plan(inputs: plusOneInput)
        }
    }

    private func sha256(_ data: Data, algorithm: String = "sha256") -> FolderContentDigest {
        FolderContentDigest(algorithm: algorithm, bytes: Data(SHA256.hash(data: data)))
    }

    private func status(at url: URL) throws -> stat {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.lstat(path, &information)
        }
        guard result == 0 else { throw posixError() }
        return information
    }

    private func descriptorStatus(_ descriptor: Int32) throws -> stat {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw posixError() }
        return information
    }

    private func assertTimestamp(
        _ timestamp: ComparisonArchiveTimestamp,
        matches url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let modificationTime = try status(at: url).st_mtimespec
        XCTAssertEqual(timestamp.secondsSince1970, Int64(modificationTime.tv_sec), file: file, line: line)
        XCTAssertEqual(timestamp.nanoseconds, Int32(modificationTime.tv_nsec), file: file, line: line)
    }

    private func replaceItem(at destination: URL, with replacement: URL) throws {
        let result = destination.withUnsafeFileSystemRepresentation { destinationPath -> Int32 in
            replacement.withUnsafeFileSystemRepresentation { replacementPath -> Int32 in
                guard let destinationPath, let replacementPath else {
                    errno = EINVAL
                    return -1
                }
                return Darwin.rename(replacementPath, destinationPath)
            }
        }
        guard result == 0 else { throw posixError() }
    }

    private func readAll(from descriptor: Int32, byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let readCount = bytes.withUnsafeMutableBytes {
            Darwin.pread(descriptor, $0.baseAddress, $0.count, 0)
        }
        guard readCount >= 0 else { throw posixError() }
        return Data(bytes.prefix(readCount))
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private func assertPlanError(
        _ expected: ComparisonArchivePlanError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ComparisonArchivePlanError, expected, file: file, line: line)
        }
    }
}
