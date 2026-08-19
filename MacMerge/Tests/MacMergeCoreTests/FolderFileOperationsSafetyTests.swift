import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class FolderFileOperationsSafetyTests: XCTestCase {
    private let unsupportedReason =
        "Descriptor-only staging, durable commit, and identity-checked recovery guarantees are not yet complete."

    func testRelativePathsRejectTraversalAbsoluteAndMalformedInputs() throws {
        let rejected = [
            "",
            "/absolute.txt",
            ".",
            "..",
            "folder/../escape.txt",
            "folder/./file.txt",
            "folder//file.txt",
            "folder/\0file.txt"
        ]

        for path in rejected {
            XCTAssertThrowsError(try FolderRelativePath(path), path) { error in
                XCTAssertEqual(error as? FolderFileOperationError, .invalidRelativePath(path))
            }
        }

        let path = try FolderRelativePath("folder/file.txt")
        XCTAssertEqual(path.rawValue, "folder/file.txt")
        XCTAssertEqual(path.components, ["folder", "file.txt"])
    }

    func testDryRunPlansValidateAllOperationKindsWithoutMutation() async throws {
        let roots = try makeRoots()
        try write("copy", to: roots.source, path: "copy.txt")
        try write("move", to: roots.source, path: "move.txt")
        try write("sync", to: roots.source, path: "sync.txt")
        try write("delete", to: roots.destination, path: "delete.txt")
        try write("sync-delete", to: roots.destination, path: "sync-delete.txt")
        let before = try treeSnapshot(at: roots.workspace)

        let copySource = try FolderRelativePath("copy.txt")
        let copyDestination = try FolderRelativePath("copied.txt")
        let copyResult = try await FolderFileOperations.dryRun(
            .copy(
                FolderCopyPlan(
                    sourceRoot: roots.source,
                    source: copySource,
                    destinationRoot: roots.destination,
                    destination: copyDestination
                )))
        XCTAssertEqual(
            copyResult,
            FolderFileOperationResult(
                mode: .dryRun,
                records: [
                    FolderFileOperationRecord(
                        kind: .copy,
                        source: roots.source.appending(path: copySource.rawValue),
                        destination: roots.destination.appending(path: copyDestination.rawValue),
                        status: .validated
                    )
                ]
            ))
        try assertTreeUnchanged(before, at: roots.workspace)

        let moveSource = try FolderRelativePath("move.txt")
        let moveDestination = try FolderRelativePath("moved.txt")
        let moveResult = try await FolderFileOperations.dryRun(
            .move(
                FolderMovePlan(
                    sourceRoot: roots.source,
                    source: moveSource,
                    destinationRoot: roots.destination,
                    destination: moveDestination
                )))
        XCTAssertEqual(
            moveResult,
            FolderFileOperationResult(
                mode: .dryRun,
                records: [
                    FolderFileOperationRecord(
                        kind: .move,
                        source: roots.source.appending(path: moveSource.rawValue),
                        destination: roots.destination.appending(path: moveDestination.rawValue),
                        status: .validated
                    )
                ]
            ))
        try assertTreeUnchanged(before, at: roots.workspace)

        let deleteTarget = try FolderRelativePath("delete.txt")
        let deleteResult = try await FolderFileOperations.dryRun(
            .delete(
                FolderDeletePlan(
                    root: roots.destination,
                    target: deleteTarget
                )))
        XCTAssertEqual(
            deleteResult,
            FolderFileOperationResult(
                mode: .dryRun,
                records: [
                    FolderFileOperationRecord(
                        kind: .delete,
                        source: nil,
                        destination: roots.destination.appending(path: deleteTarget.rawValue),
                        status: .validated
                    )
                ]
            ))
        try assertTreeUnchanged(before, at: roots.workspace)

        let syncCopySource = try FolderRelativePath("sync.txt")
        let syncCopyDestination = try FolderRelativePath("synced.txt")
        let syncDeleteDestination = try FolderRelativePath("sync-delete.txt")
        let syncResult = try await FolderFileOperations.dryRun(
            .synchronize(
                FolderSynchronizationPlan(
                    sourceRoot: roots.source,
                    destinationRoot: roots.destination,
                    steps: [
                        .copy(
                            source: syncCopySource,
                            destination: syncCopyDestination,
                            collisionPolicy: .fail
                        ),
                        .delete(destination: syncDeleteDestination, deletionPolicy: .moveToBackup)
                    ]
                )))
        XCTAssertEqual(
            syncResult,
            FolderFileOperationResult(
                mode: .dryRun,
                records: [
                    FolderFileOperationRecord(
                        kind: .copy,
                        source: roots.source.appending(path: syncCopySource.rawValue),
                        destination: roots.destination.appending(path: syncCopyDestination.rawValue),
                        status: .validated
                    ),
                    FolderFileOperationRecord(
                        kind: .delete,
                        source: nil,
                        destination: roots.destination.appending(path: syncDeleteDestination.rawValue),
                        status: .validated
                    )
                ]
            ))
        try assertTreeUnchanged(before, at: roots.workspace)
    }

    func testDryRunRejectsInvalidSourceDestinationAndDeleteRootsAcrossPlanMatrixWithoutMutation() async throws {
        let roots = try makeRoots()
        try write("source", to: roots.source, path: "source.txt")
        let rootFile = roots.workspace.appending(path: "not-a-root.txt")
        try Data("root file".utf8).write(to: rootFile)
        let before = try treeSnapshot(at: roots.workspace)
        let source = try FolderRelativePath("source.txt")
        let destination = try FolderRelativePath("destination.txt")
        let relativeFileRoot = try XCTUnwrap(URL(string: "file:relative-root"))
        let nonFileRoot = try XCTUnwrap(URL(string: "https://example.invalid/root"))
        let invalidRoots: [(String, URL, FolderFileOperationError)] = [
            ("relative-file-url", relativeFileRoot, .invalidRoot(relativeFileRoot.absoluteString)),
            ("non-file-url", nonFileRoot, .invalidRoot(nonFileRoot.absoluteString)),
            ("regular-file", rootFile, .rootNotDirectory(rootFile.path))
        ]

        for (rootName, invalidRoot, expectedError) in invalidRoots {
            let plans: [(String, FolderFileOperationPlan)] = [
                (
                    "copy-source-root",
                    .copy(
                        FolderCopyPlan(
                            sourceRoot: invalidRoot,
                            source: source,
                            destinationRoot: roots.destination,
                            destination: destination
                        ))
                ),
                (
                    "move-source-root",
                    .move(
                        FolderMovePlan(
                            sourceRoot: invalidRoot,
                            source: source,
                            destinationRoot: roots.destination,
                            destination: destination
                        ))
                ),
                (
                    "synchronize-source-root",
                    .synchronize(
                        FolderSynchronizationPlan(
                            sourceRoot: invalidRoot,
                            destinationRoot: roots.destination,
                            steps: [
                                .copy(source: source, destination: destination, collisionPolicy: .fail)
                            ]
                        ))
                ),
                (
                    "copy-destination-root",
                    .copy(
                        FolderCopyPlan(
                            sourceRoot: roots.source,
                            source: source,
                            destinationRoot: invalidRoot,
                            destination: destination
                        ))
                ),
                (
                    "move-destination-root",
                    .move(
                        FolderMovePlan(
                            sourceRoot: roots.source,
                            source: source,
                            destinationRoot: invalidRoot,
                            destination: destination
                        ))
                ),
                (
                    "synchronize-destination-root",
                    .synchronize(
                        FolderSynchronizationPlan(
                            sourceRoot: roots.source,
                            destinationRoot: invalidRoot,
                            steps: [
                                .copy(source: source, destination: destination, collisionPolicy: .fail)
                            ]
                        ))
                ),
                (
                    "delete-root",
                    .delete(FolderDeletePlan(root: invalidRoot, target: destination))
                )
            ]

            for (planName, plan) in plans {
                try await assertDryRunError(
                    expectedError,
                    plan: plan,
                    unchanged: before,
                    at: roots.workspace,
                    message: "\(rootName)-\(planName)"
                )
            }
        }
    }

    func testDryRunRejectsUnresolvablePathsWithoutMutation() async throws {
        let roots = try makeRoots()
        try write("source", to: roots.source, path: "source.txt")
        let before = try treeSnapshot(at: roots.workspace)
        let source = try FolderRelativePath("source.txt")
        let destination = try FolderRelativePath("destination.txt")

        let missingSource = try FolderRelativePath("missing.txt")
        try await assertDryRunError(
            .itemNotFound(roots.source.appending(path: missingSource.rawValue).path),
            plan: .copy(
                FolderCopyPlan(
                    sourceRoot: roots.source,
                    source: missingSource,
                    destinationRoot: roots.destination,
                    destination: destination
                )),
            unchanged: before,
            at: roots.workspace
        )

        let nestedDestination = try FolderRelativePath("missing-parent/destination.txt")
        try await assertDryRunError(
            .destinationParentMissing(roots.destination.appending(path: "missing-parent").path),
            plan: .copy(
                FolderCopyPlan(
                    sourceRoot: roots.source,
                    source: source,
                    destinationRoot: roots.destination,
                    destination: nestedDestination
                )),
            unchanged: before,
            at: roots.workspace
        )
    }

    func testDryRunCollisionPoliciesAndOverlappingTreesFailClosed() async throws {
        let roots = try makeRoots()
        try write("source", to: roots.source, path: "source.txt")
        try write("existing", to: roots.destination, path: "existing.txt")
        let tree = roots.source.appending(path: "tree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: tree.appending(path: "child", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try write("tree", to: roots.source, path: "tree/file.txt")
        let before = try treeSnapshot(at: roots.workspace)
        let source = try FolderRelativePath("source.txt")
        let existing = try FolderRelativePath("existing.txt")

        try await assertDryRunError(
            .destinationCollision(roots.destination.appending(path: existing.rawValue).path),
            plan: .copy(
                FolderCopyPlan(
                    sourceRoot: roots.source,
                    source: source,
                    destinationRoot: roots.destination,
                    destination: existing,
                    collisionPolicy: .fail
                )),
            unchanged: before,
            at: roots.workspace
        )

        let skipped = try await FolderFileOperations.dryRun(
            .copy(
                FolderCopyPlan(
                    sourceRoot: roots.source,
                    source: source,
                    destinationRoot: roots.destination,
                    destination: existing,
                    collisionPolicy: .skip
                )))
        XCTAssertEqual(skipped.records.map(\.status), [.skipped])

        let replacing = try await FolderFileOperations.dryRun(
            .copy(
                FolderCopyPlan(
                    sourceRoot: roots.source,
                    source: source,
                    destinationRoot: roots.destination,
                    destination: existing,
                    collisionPolicy: .replaceKeepingBackup
                )))
        XCTAssertEqual(replacing.records.map(\.status), [.validated])

        let overlapSource = try FolderRelativePath("tree")
        let overlapDestination = try FolderRelativePath("tree/child/copied-tree")
        try await assertDryRunError(
            .sourceDestinationOverlap(
                source: roots.source.appending(path: overlapSource.rawValue).path,
                destination: roots.source.appending(path: overlapDestination.rawValue).path
            ),
            plan: .copy(
                FolderCopyPlan(
                    sourceRoot: roots.source,
                    source: overlapSource,
                    destinationRoot: roots.source,
                    destination: overlapDestination
                )),
            unchanged: before,
            at: roots.workspace
        )

        try assertTreeUnchanged(before, at: roots.workspace)
    }

    func testDryRunRejectsHardLinkedSourceDestinationInodeOverlapWithoutMutation() async throws {
        let roots = try makeRoots()
        try write("shared inode", to: roots.source, path: "source.txt")
        let sourceURL = roots.source.appending(path: "source.txt")
        let destinationURL = roots.destination.appending(path: "destination.txt")
        try FileManager.default.linkItem(at: sourceURL, to: destinationURL)
        let before = try treeSnapshot(at: roots.workspace)
        let source = try FolderRelativePath("source.txt")
        let destination = try FolderRelativePath("destination.txt")
        let expected = FolderFileOperationError.sourceDestinationOverlap(
            source: sourceURL.path,
            destination: destinationURL.path
        )
        let plans: [(String, FolderFileOperationPlan)] = [
            (
                "copy",
                .copy(
                    FolderCopyPlan(
                        sourceRoot: roots.source,
                        source: source,
                        destinationRoot: roots.destination,
                        destination: destination,
                        collisionPolicy: .replaceKeepingBackup
                    ))
            ),
            (
                "move",
                .move(
                    FolderMovePlan(
                        sourceRoot: roots.source,
                        source: source,
                        destinationRoot: roots.destination,
                        destination: destination,
                        collisionPolicy: .replaceKeepingBackup
                    ))
            ),
            (
                "synchronize-copy",
                .synchronize(
                    FolderSynchronizationPlan(
                        sourceRoot: roots.source,
                        destinationRoot: roots.destination,
                        steps: [
                            .copy(
                                source: source,
                                destination: destination,
                                collisionPolicy: .replaceKeepingBackup
                            )
                        ]
                    ))
            )
        ]

        for (name, plan) in plans {
            try await assertDryRunError(
                expected,
                plan: plan,
                unchanged: before,
                at: roots.workspace,
                message: name
            )
        }
    }

    func testDryRunRejectsSymlinksAtRootsAncestorsAndInsideTrees() async throws {
        let roots = try makeRoots()
        try write("target", to: roots.source, path: "target.txt")
        let sourceLink = roots.source.appending(path: "source-link")
        try FileManager.default.createSymbolicLink(
            at: sourceLink,
            withDestinationURL: roots.source.appending(path: "target.txt")
        )
        let realDirectory = roots.source.appending(path: "real", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)
        try write("nested", to: roots.source, path: "real/nested.txt")
        let ancestorLink = roots.source.appending(path: "ancestor-link")
        try FileManager.default.createSymbolicLink(at: ancestorLink, withDestinationURL: realDirectory)
        let tree = roots.source.appending(path: "tree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: false)
        let nestedLink = tree.appending(path: "nested-link")
        try FileManager.default.createSymbolicLink(
            at: nestedLink,
            withDestinationURL: roots.source.appending(path: "target.txt")
        )
        let rootLink = roots.workspace.appending(path: "root-link")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: roots.source)
        let listedNestedLink = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: tree, includingPropertiesForKeys: nil).first
        )
        let before = try treeSnapshot(at: roots.workspace)

        try await assertDryRunError(
            .symbolicLinkNotAllowed(sourceLink.path),
            plan: try copyPlan(roots: roots, source: "source-link", destination: "copy.txt"),
            unchanged: before,
            at: roots.workspace
        )
        try await assertDryRunError(
            .symbolicLinkNotAllowed(ancestorLink.path),
            plan: try copyPlan(roots: roots, source: "ancestor-link/nested.txt", destination: "copy.txt"),
            unchanged: before,
            at: roots.workspace
        )
        try await assertDryRunError(
            .symbolicLinkNotAllowed(listedNestedLink.path),
            plan: try copyPlan(roots: roots, source: "tree", destination: "tree-copy"),
            unchanged: before,
            at: roots.workspace
        )
        try await assertDryRunError(
            .symbolicLinkNotAllowed(rootLink.path),
            plan: .copy(
                FolderCopyPlan(
                    sourceRoot: rootLink,
                    source: try FolderRelativePath("target.txt"),
                    destinationRoot: roots.destination,
                    destination: try FolderRelativePath("copy.txt")
                )),
            unchanged: before,
            at: roots.workspace
        )

        try assertTreeUnchanged(before, at: roots.workspace)
    }

    func testDryRunRejectsFinderAliasesAndSpecialFiles() async throws {
        let roots = try makeRoots()
        let target = roots.source.appending(path: "target.txt")
        try Data("target".utf8).write(to: target)
        let alias = roots.source.appending(path: "target alias")
        try createAlias(at: alias, to: target)

        let fifo = roots.source.appending(path: "named-pipe")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, 0o600), 0)
        let before = try treeSnapshot(at: roots.workspace)

        try await assertDryRunError(
            .aliasNotAllowed(alias.path),
            plan: try copyPlan(roots: roots, source: "target alias", destination: "alias-copy"),
            unchanged: before,
            at: roots.workspace
        )
        try await assertDryRunError(
            .unsupportedItem(fifo.path),
            plan: try copyPlan(roots: roots, source: "named-pipe", destination: "fifo-copy"),
            unchanged: before,
            at: roots.workspace
        )

        try assertTreeUnchanged(before, at: roots.workspace)
    }

    func testDryRunRejectsDangerousMutationTargetsAcrossReplacementAndDeletePlansWithoutMutation() async throws {
        let roots = try makeRoots()
        try write("copy", to: roots.source, path: "copy.txt")
        try write("move", to: roots.source, path: "move.txt")
        try write("sync", to: roots.source, path: "sync.txt")
        try write("target", to: roots.destination, path: "target.txt")

        let symlink = roots.destination.appending(path: "danger-symlink")
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: roots.destination.appending(path: "target.txt")
        )
        let alias = roots.destination.appending(path: "danger-alias")
        try createAlias(
            at: alias,
            to: roots.destination.appending(path: "target.txt")
        )
        let fifo = roots.destination.appending(path: "danger-fifo")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, 0o600), 0)

        let dangers: [(String, FolderRelativePath, FolderFileOperationError)] = [
            ("symlink", try FolderRelativePath("danger-symlink"), .symbolicLinkNotAllowed(symlink.path)),
            ("alias", try FolderRelativePath("danger-alias"), .aliasNotAllowed(alias.path)),
            ("fifo", try FolderRelativePath("danger-fifo"), .unsupportedItem(fifo.path))
        ]
        let before = try treeSnapshot(at: roots.workspace)

        for (dangerName, destination, expectedError) in dangers {
            let plans: [(String, FolderFileOperationPlan)] = [
                (
                    "copy-replacement",
                    .copy(
                        FolderCopyPlan(
                            sourceRoot: roots.source,
                            source: try FolderRelativePath("copy.txt"),
                            destinationRoot: roots.destination,
                            destination: destination,
                            collisionPolicy: .replaceKeepingBackup
                        ))
                ),
                (
                    "move-replacement",
                    .move(
                        FolderMovePlan(
                            sourceRoot: roots.source,
                            source: try FolderRelativePath("move.txt"),
                            destinationRoot: roots.destination,
                            destination: destination,
                            collisionPolicy: .replaceKeepingBackup
                        ))
                ),
                (
                    "delete",
                    .delete(FolderDeletePlan(root: roots.destination, target: destination))
                ),
                (
                    "synchronize-replacement",
                    .synchronize(
                        FolderSynchronizationPlan(
                            sourceRoot: roots.source,
                            destinationRoot: roots.destination,
                            steps: [
                                .copy(
                                    source: try FolderRelativePath("sync.txt"),
                                    destination: destination,
                                    collisionPolicy: .replaceKeepingBackup
                                )
                            ]
                        ))
                ),
                (
                    "synchronize-delete",
                    .synchronize(
                        FolderSynchronizationPlan(
                            sourceRoot: roots.source,
                            destinationRoot: roots.destination,
                            steps: [.delete(destination: destination, deletionPolicy: .moveToBackup)]
                        ))
                )
            ]

            for (planName, plan) in plans {
                try await assertDryRunError(
                    expectedError,
                    plan: plan,
                    unchanged: before,
                    at: roots.workspace,
                    message: "\(dangerName)-\(planName)"
                )
            }
        }
    }

    func testDryRunRejectsDangerousMutationAncestorsAcrossDestinationPlansWithoutMutation() async throws {
        let roots = try makeRoots()
        try write("copy", to: roots.source, path: "copy.txt")
        try write("move", to: roots.source, path: "move.txt")
        try write("sync", to: roots.source, path: "sync.txt")
        let realDirectory = roots.destination.appending(path: "real", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)

        let symlink = roots.destination.appending(path: "danger-symlink-ancestor")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realDirectory)
        try write("target", to: roots.destination, path: "target.txt")
        let alias = roots.destination.appending(path: "danger-alias-ancestor")
        try createAlias(
            at: alias,
            to: roots.destination.appending(path: "target.txt")
        )
        let fifo = roots.destination.appending(path: "danger-fifo-ancestor")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, 0o600), 0)

        let dangers: [(String, String, FolderFileOperationError)] = [
            ("symlink", "danger-symlink-ancestor/new.txt", .symbolicLinkNotAllowed(symlink.path)),
            ("alias", "danger-alias-ancestor/new.txt", .aliasNotAllowed(alias.path)),
            ("fifo", "danger-fifo-ancestor/new.txt", .unsupportedItem(fifo.path))
        ]
        let before = try treeSnapshot(at: roots.workspace)

        for (dangerName, destinationPath, expectedError) in dangers {
            let destination = try FolderRelativePath(destinationPath)
            let plans: [(String, FolderFileOperationPlan)] = [
                (
                    "copy-destination",
                    .copy(
                        FolderCopyPlan(
                            sourceRoot: roots.source,
                            source: try FolderRelativePath("copy.txt"),
                            destinationRoot: roots.destination,
                            destination: destination
                        ))
                ),
                (
                    "move-destination",
                    .move(
                        FolderMovePlan(
                            sourceRoot: roots.source,
                            source: try FolderRelativePath("move.txt"),
                            destinationRoot: roots.destination,
                            destination: destination
                        ))
                ),
                (
                    "synchronize-destination",
                    .synchronize(
                        FolderSynchronizationPlan(
                            sourceRoot: roots.source,
                            destinationRoot: roots.destination,
                            steps: [
                                .copy(
                                    source: try FolderRelativePath("sync.txt"),
                                    destination: destination,
                                    collisionPolicy: .fail
                                )
                            ]
                        ))
                ),
                (
                    "delete",
                    .delete(FolderDeletePlan(root: roots.destination, target: destination))
                ),
                (
                    "synchronize-delete",
                    .synchronize(
                        FolderSynchronizationPlan(
                            sourceRoot: roots.source,
                            destinationRoot: roots.destination,
                            steps: [.delete(destination: destination, deletionPolicy: .moveToBackup)]
                        ))
                )
            ]

            for (planName, plan) in plans {
                try await assertDryRunError(
                    expectedError,
                    plan: plan,
                    unchanged: before,
                    at: roots.workspace,
                    message: "\(dangerName)-\(planName)"
                )
            }
        }
    }

    func testMountedVolumeBoundaryCoverageOmittedWithoutSafeControlledMountFixture() {}

    func testSynchronizationRejectsCaseAndUnicodeEquivalentDestinationCollisions() async throws {
        let roots = try makeRoots()
        try write("first", to: roots.source, path: "first.txt")
        try write("second", to: roots.source, path: "second.txt")
        let before = try treeSnapshot(at: roots.workspace)
        let firstSource = try FolderRelativePath("first.txt")
        let secondSource = try FolderRelativePath("second.txt")

        let caseFirst = try FolderRelativePath("Report.txt")
        let caseSecond = try FolderRelativePath("report.TXT")
        let caseConflict = await assertConflictingPlan(
            .synchronize(
                FolderSynchronizationPlan(
                    sourceRoot: roots.source,
                    destinationRoot: roots.destination,
                    steps: [
                        .copy(source: firstSource, destination: caseFirst, collisionPolicy: .fail),
                        .copy(source: secondSource, destination: caseSecond, collisionPolicy: .fail)
                    ]
                )))
        XCTAssertEqual(caseConflict?.0, roots.destination.appending(path: caseFirst.rawValue).path)
        XCTAssertEqual(caseConflict?.1, roots.destination.appending(path: caseSecond.rawValue).path)

        let nfcName = "Caf\u{00E9}.txt"
        let nfdName = "Cafe\u{0301}.txt"
        XCTAssertNotEqual(Data(nfcName.utf8), Data(nfdName.utf8))
        let unicodeFirst = try FolderRelativePath(nfcName)
        let unicodeSecond = try FolderRelativePath(nfdName)
        let unicodeConflict = await assertConflictingPlan(
            .synchronize(
                FolderSynchronizationPlan(
                    sourceRoot: roots.source,
                    destinationRoot: roots.destination,
                    steps: [
                        .copy(source: firstSource, destination: unicodeFirst, collisionPolicy: .fail),
                        .copy(source: secondSource, destination: unicodeSecond, collisionPolicy: .fail)
                    ]
                )))
        XCTAssertEqual(unicodeConflict?.0, roots.destination.appending(path: nfcName).path)
        XCTAssertEqual(unicodeConflict?.1, roots.destination.appending(path: nfdName).path)

        try assertTreeUnchanged(before, at: roots.workspace)
    }

    func testSynchronizationTreatsSkippedDestinationAsReadDependency() async throws {
        let roots = try makeRoots()
        try write("source", to: roots.source, path: "source.txt")
        try write("existing", to: roots.destination, path: "existing.txt")
        let before = try treeSnapshot(at: roots.workspace)
        let existing = try FolderRelativePath("existing.txt")
        let existingPath = roots.destination.appending(path: existing.rawValue).path

        let conflict = await assertConflictingPlan(
            .synchronize(
                FolderSynchronizationPlan(
                    sourceRoot: roots.source,
                    destinationRoot: roots.destination,
                    steps: [
                        .copy(
                            source: try FolderRelativePath("source.txt"),
                            destination: existing,
                            collisionPolicy: .skip
                        ),
                        .delete(destination: existing, deletionPolicy: .moveToBackup)
                    ]
                )))
        XCTAssertEqual(conflict?.0, existingPath)
        XCTAssertEqual(conflict?.1, existingPath)
        try assertTreeUnchanged(before, at: roots.workspace)
    }

    func testPerformAndPublicExecutePerformFullMatrixFailTypedBeforeAccessAndMutation() async throws {
        for scenario in PerformScenario.allCases {
            for entryPoint in PerformEntryPoint.allCases {
                let roots = try makeRoots()
                let expectation = try makePerformExpectation(for: scenario, roots: roots)
                let message = "\(scenario.rawValue)-\(entryPoint.rawValue)"
                let validation = try await FolderFileOperations.dryRun(expectation.plan)
                XCTAssertEqual(validation.records.map(\.status), [.validated], message)
                let before = try treeSnapshot(at: roots.workspace)
                let accessRecorder = AccessRecorder()
                let error: FolderFileOperationError?
                error = await FolderFileOperations.$accessObserver.withValue({
                    accessRecorder.record()
                }) {
                    switch entryPoint {
                    case .perform:
                        return await captureError(
                            { try await FolderFileOperations.perform(expectation.plan) },
                            message
                        )
                    case .executePerform:
                        return await captureError(
                            { try await FolderFileOperations.execute(expectation.plan, mode: .perform) },
                            message
                        )
                    }
                }
                let expected = FolderFileOperationError.safetyRequirementsUnsupported(
                    operation: expectation.operation,
                    path: expectation.path,
                    reason: unsupportedReason
                )
                XCTAssertEqual(error, expected, message)
                XCTAssertEqual(safetyFailureCode(for: error), .safetyUnsupported, message)
                XCTAssertEqual(accessRecorder.count, 0, message)
                try assertTreeUnchanged(before, at: roots.workspace, message: message)
            }
        }
    }

    private enum PerformScenario: String, CaseIterable {
        case copy
        case move
        case delete
        case synchronizeCopyOnly = "synchronize-copy-only"
        case synchronizeDeleteOnly = "synchronize-delete-only"
        case replaceCopy = "replace-copy"
        case replaceMove = "replace-move"
    }

    private enum PerformEntryPoint: String, CaseIterable {
        case perform
        case executePerform = "execute-perform"
    }

    private struct PerformExpectation {
        let plan: FolderFileOperationPlan
        let operation: FolderFileOperationKind
        let path: String
    }

    private func makePerformExpectation(
        for scenario: PerformScenario,
        roots: (workspace: URL, source: URL, destination: URL)
    ) throws -> PerformExpectation {
        switch scenario {
        case .copy:
            try write("copy source", to: roots.source, path: "source.txt")
            let destination = try FolderRelativePath("copied.txt")
            return PerformExpectation(
                plan: .copy(
                    FolderCopyPlan(
                        sourceRoot: roots.source,
                        source: try FolderRelativePath("source.txt"),
                        destinationRoot: roots.destination,
                        destination: destination
                    )),
                operation: .copy,
                path: roots.destination.appending(path: destination.rawValue).path
            )
        case .move:
            try write("move source", to: roots.source, path: "source.txt")
            let destination = try FolderRelativePath("moved.txt")
            return PerformExpectation(
                plan: .move(
                    FolderMovePlan(
                        sourceRoot: roots.source,
                        source: try FolderRelativePath("source.txt"),
                        destinationRoot: roots.destination,
                        destination: destination
                    )),
                operation: .move,
                path: roots.destination.appending(path: destination.rawValue).path
            )
        case .delete:
            try write("delete target", to: roots.destination, path: "target.txt")
            let target = try FolderRelativePath("target.txt")
            return PerformExpectation(
                plan: .delete(FolderDeletePlan(root: roots.destination, target: target)),
                operation: .delete,
                path: roots.destination.appending(path: target.rawValue).path
            )
        case .synchronizeCopyOnly:
            try write("sync copy source", to: roots.source, path: "source.txt")
            return PerformExpectation(
                plan: .synchronize(
                    FolderSynchronizationPlan(
                        sourceRoot: roots.source,
                        destinationRoot: roots.destination,
                        steps: [
                            .copy(
                                source: try FolderRelativePath("source.txt"),
                                destination: try FolderRelativePath("copied.txt"),
                                collisionPolicy: .fail
                            )
                        ]
                    )),
                operation: .copy,
                path: roots.destination.path
            )
        case .synchronizeDeleteOnly:
            try write("sync delete target", to: roots.destination, path: "target.txt")
            return PerformExpectation(
                plan: .synchronize(
                    FolderSynchronizationPlan(
                        sourceRoot: roots.source,
                        destinationRoot: roots.destination,
                        steps: [
                            .delete(
                                destination: try FolderRelativePath("target.txt"),
                                deletionPolicy: .moveToBackup
                            )
                        ]
                    )),
                operation: .copy,
                path: roots.destination.path
            )
        case .replaceCopy:
            try write("replacement copy source", to: roots.source, path: "source.txt")
            try write("existing copy destination", to: roots.destination, path: "existing.txt")
            let destination = try FolderRelativePath("existing.txt")
            return PerformExpectation(
                plan: .copy(
                    FolderCopyPlan(
                        sourceRoot: roots.source,
                        source: try FolderRelativePath("source.txt"),
                        destinationRoot: roots.destination,
                        destination: destination,
                        collisionPolicy: .replaceKeepingBackup
                    )),
                operation: .copy,
                path: roots.destination.appending(path: destination.rawValue).path
            )
        case .replaceMove:
            try write("replacement move source", to: roots.source, path: "source.txt")
            try write("existing move destination", to: roots.destination, path: "existing.txt")
            let destination = try FolderRelativePath("existing.txt")
            return PerformExpectation(
                plan: .move(
                    FolderMovePlan(
                        sourceRoot: roots.source,
                        source: try FolderRelativePath("source.txt"),
                        destinationRoot: roots.destination,
                        destination: destination,
                        collisionPolicy: .replaceKeepingBackup
                    )),
                operation: .move,
                path: roots.destination.appending(path: destination.rawValue).path
            )
        }
    }

    private final class AccessRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func record() {
            lock.lock()
            storage += 1
            lock.unlock()
        }
    }

    private func makeRoots() throws -> (workspace: URL, source: URL, destination: URL) {
        let workspace = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        let canonicalWorkspace = workspace.resolvingSymlinksInPath().standardizedFileURL
        addTeardownBlock { try? FileManager.default.removeItem(at: canonicalWorkspace) }
        let source = canonicalWorkspace.appending(path: "source", directoryHint: .isDirectory)
        let destination = canonicalWorkspace.appending(path: "destination", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        return (canonicalWorkspace, source, destination)
    }

    private func write(_ value: String, to root: URL, path: String) throws {
        try Data(value.utf8).write(to: root.appending(path: path))
    }

    private func createAlias(at alias: URL, to target: URL) throws {
        let bookmark = try target.bookmarkData(
            options: .suitableForBookmarkFile,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(bookmark, to: alias)
        XCTAssertEqual(try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile, true)
    }

    private func copyPlan(
        roots: (workspace: URL, source: URL, destination: URL),
        source: String,
        destination: String
    ) throws -> FolderFileOperationPlan {
        .copy(
            FolderCopyPlan(
                sourceRoot: roots.source,
                source: try FolderRelativePath(source),
                destinationRoot: roots.destination,
                destination: try FolderRelativePath(destination)
            ))
    }

    private func assertDryRunError(
        _ expected: FolderFileOperationError,
        plan: FolderFileOperationPlan,
        unchanged snapshot: [TreeEntry],
        at root: URL,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let error = await captureError(
            { try await FolderFileOperations.dryRun(plan) },
            message.isEmpty ? "Expected dry-run error \(expected)" : message,
            file: file,
            line: line
        )
        XCTAssertEqual(error, expected, message, file: file, line: line)
        try assertTreeUnchanged(snapshot, at: root, message: message, file: file, line: line)
    }

    private func assertConflictingPlan(
        _ plan: FolderFileOperationPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> (String, String)? {
        let error = await captureError(
            { try await FolderFileOperations.dryRun(plan) },
            "Expected conflicting plan",
            file: file,
            line: line
        )
        guard case .conflictingPlan(let first, let second)? = error else {
            return nil
        }
        return (first, second)
    }

    private func captureError(
        _ operation: () async throws -> FolderFileOperationResult,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> FolderFileOperationError? {
        do {
            _ = try await operation()
            XCTFail(message, file: file, line: line)
            return nil
        } catch let error as FolderFileOperationError {
            return error
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
            return nil
        }
    }

    private func safetyFailureCode(
        for error: FolderFileOperationError?
    ) -> FolderFileOperationFailureCode? {
        guard case .safetyRequirementsUnsupported? = error else { return nil }
        return .safetyUnsupported
    }

    private struct TreeEntry: Equatable {
        let path: String
        let metadata: String
        let contents: Data?
        let symbolicLinkDestination: String?
    }

    private func treeSnapshot(at root: URL) throws -> [TreeEntry] {
        var entries: [TreeEntry] = []

        func append(_ url: URL, relativePath: String) throws {
            var information = stat()
            guard Darwin.lstat(url.path, &information) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            let type = information.st_mode & S_IFMT
            let contents = type == S_IFREG ? try Data(contentsOf: url) : nil
            let linkDestination =
                type == S_IFLNK
                ? try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                : nil
            let metadata = [
                String(information.st_dev),
                String(information.st_ino),
                String(information.st_mode),
                String(information.st_size),
                String(information.st_mtimespec.tv_sec),
                String(information.st_mtimespec.tv_nsec),
                String(information.st_ctimespec.tv_sec),
                String(information.st_ctimespec.tv_nsec)
            ].joined(separator: ":")
            entries.append(
                TreeEntry(
                    path: relativePath,
                    metadata: metadata,
                    contents: contents,
                    symbolicLinkDestination: linkDestination
                ))

            guard type == S_IFDIR else { return }
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for child in children {
                let childPath =
                    relativePath.isEmpty
                    ? child.lastPathComponent
                    : relativePath + "/" + child.lastPathComponent
                try append(child, relativePath: childPath)
            }
        }

        try append(root, relativePath: "")
        return entries
    }

    private func assertTreeUnchanged(
        _ expected: [TreeEntry],
        at root: URL,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try treeSnapshot(at: root), expected, message, file: file, line: line)
    }
}
