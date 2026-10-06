import Foundation
import MacMergeCore
import XCTest

final class FolderOperationCommitWorkflowTests: XCTestCase {
    private let sourcePath = "/commit-src"
    private let destinationPath = "/commit-dst"
    private let metadataA: [UInt8] = [UInt8](repeating: 0xA1, count: 32)
    private let metadataB: [UInt8] = [UInt8](repeating: 0xB2, count: 32)
    private let contentA: [UInt8] = [UInt8](repeating: 0x11, count: 32)
    private let contentB: [UInt8] = [UInt8](repeating: 0x22, count: 32)

    func testCopyCommitBindsCASRevisionsAndProducesRemoveRollback() throws {
        let (operation, snapshot) = try copyWorld()
        let bundle = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)

        let step = try XCTUnwrap(bundle.commit.steps.first)
        XCTAssertEqual(bundle.commit.steps.count, 1)
        XCTAssertEqual(step.kind, .copy)
        XCTAssertEqual(step.sourceExpected?.contentSHA256, contentA)
        XCTAssertEqual(step.sourceExpected?.metadataSHA256, metadataA)
        XCTAssertNil(step.destinationPrior)
        XCTAssertEqual(step.collisionPolicy, .fail)
        XCTAssertFalse(step.replacesExisting)
        XCTAssertFalse(step.skipsExisting)

        let rollback = try XCTUnwrap(bundle.rollback.steps.first)
        XCTAssertEqual(bundle.rollback.steps.count, 1)
        XCTAssertEqual(rollback.action, .removePublishedDestination)
        XCTAssertEqual(rollback.commitIndex, 0)
        XCTAssertEqual(rollback.rollbackOrder, 0)
        XCTAssertNil(rollback.restored)
        XCTAssertEqual(rollback.publishedContentSHA256, contentA)

        XCTAssertEqual(bundle.receipt.stepCount, 1)
        XCTAssertEqual(bundle.receipt.skippedStepCount, 0)
        XCTAssertEqual(bundle.receipt.rollbackStepCount, 1)
        XCTAssertEqual(bundle.receipt.planDigestSHA256.count, 32)
        XCTAssertEqual(bundle.receipt.stepDigestsSHA256.count, 1)
        XCTAssertEqual(bundle.receipt.stepDigestsSHA256.first?.count, 32)
    }

    func testMoveCommitEmitsDestinationAndSourceRestoreRollback() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let sourceFile = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [sourceFile])
        let operation = try moveOperation(source: "a.txt", destination: "moved.txt")
        let bundle = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)

        XCTAssertEqual(bundle.commit.steps.count, 1)
        XCTAssertEqual(bundle.commit.steps.first?.kind, .move)
        XCTAssertEqual(bundle.rollback.steps.count, 2)

        let removal = bundle.rollback.steps[0]
        XCTAssertEqual(removal.action, .removePublishedDestination)
        XCTAssertEqual(removal.commitIndex, 0)
        XCTAssertEqual(removal.rollbackOrder, 0)
        XCTAssertEqual(removal.publishedContentSHA256, contentA)

        let restore = bundle.rollback.steps[1]
        XCTAssertEqual(restore.action, .restoreMovedSource)
        XCTAssertEqual(restore.commitIndex, 0)
        XCTAssertEqual(restore.rollbackOrder, 1)
        XCTAssertEqual(restore.relativePath, "a.txt")
        XCTAssertEqual(restore.restored, sourceFile)
        XCTAssertNil(restore.publishedContentSHA256)
        XCTAssertEqual(bundle.receipt.rollbackStepCount, 2)
    }

    func testDeleteCommitRestoresDeletedTargetOnRollback() throws {
        let destinationRoot = makePinnedRoot(
            path: destinationPath,
            device: 22,
            file: 202,
            generation: 7,
            metadata: metadataB)
        let parent = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let target = makeFileItem(
            root: destinationRoot.revision.identity,
            path: "docs/gone.txt",
            device: 1003,
            file: 2003,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [destinationRoot],
            items: [parent, target])
        let operation = try deleteOperation(target: "docs/gone.txt")
        let bundle = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)

        let step = try XCTUnwrap(bundle.commit.steps.first)
        XCTAssertEqual(step.kind, .delete)
        XCTAssertNil(step.sourceRoot)
        XCTAssertEqual(step.destinationPrior, target)
        XCTAssertNil(step.collisionPolicy)
        XCTAssertEqual(step.deletionPolicy, .moveToBackup)

        let rollback = try XCTUnwrap(bundle.rollback.steps.first)
        XCTAssertEqual(rollback.action, .restoreDeletedTarget)
        XCTAssertEqual(rollback.restored, target)
        XCTAssertNil(rollback.publishedContentSHA256)
    }

    func testCollisionSkipMarksSkippedAndOmitsRollback() throws {
        let (operation, snapshot, _) = try existingDestinationWorld(collision: .skip)
        let bundle = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)

        let step = try XCTUnwrap(bundle.commit.steps.first)
        XCTAssertTrue(step.skipsExisting)
        XCTAssertFalse(step.replacesExisting)
        XCTAssertTrue(bundle.rollback.steps.isEmpty)
        XCTAssertEqual(bundle.receipt.skippedStepCount, 1)
        XCTAssertEqual(bundle.receipt.stepCount, 1)
        XCTAssertEqual(bundle.receipt.rollbackStepCount, 0)
    }

    func testCollisionReplaceRestoresPriorOnRollback() throws {
        let (operation, snapshot, prior) = try existingDestinationWorld(
            collision: .replaceKeepingBackup)
        let bundle = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)

        let step = try XCTUnwrap(bundle.commit.steps.first)
        XCTAssertTrue(step.replacesExisting)
        XCTAssertFalse(step.skipsExisting)
        XCTAssertEqual(step.destinationPrior, prior)

        let rollback = try XCTUnwrap(bundle.rollback.steps.first)
        XCTAssertEqual(rollback.action, .restoreReplacedDestination)
        XCTAssertEqual(rollback.restored, prior)
        XCTAssertEqual(rollback.publishedContentSHA256, contentA)
    }

    func testFileItemRequiresContentDigestAndByteCount() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let parent = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let operation = try copyOperation(source: "a.txt", destination: "docs/b.txt")

        let missingDigest = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: nil,
            bytes: 8)
        assertCommitThrows(
            .invalidItemRevision,
            operation: operation,
            snapshot: FolderOperationCommitSnapshot(
                roots: [sourceRoot, destinationRoot],
                items: [missingDigest, parent]))

        let missingBytes = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: nil)
        assertCommitThrows(
            .invalidItemRevision,
            operation: operation,
            snapshot: FolderOperationCommitSnapshot(
                roots: [sourceRoot, destinationRoot],
                items: [missingBytes, parent]))
    }

    func testDirectoryItemRejectsContentDigestAndByteCount() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let sourceFile = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let operation = try copyOperation(source: "a.txt", destination: "docs/b.txt")

        let withContent = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB,
            content: contentB)
        assertCommitThrows(
            .invalidItemRevision,
            operation: operation,
            snapshot: FolderOperationCommitSnapshot(
                roots: [sourceRoot, destinationRoot],
                items: [sourceFile, withContent]))

        let withBytes = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB,
            bytes: 9)
        assertCommitThrows(
            .invalidItemRevision,
            operation: operation,
            snapshot: FolderOperationCommitSnapshot(
                roots: [sourceRoot, destinationRoot],
                items: [sourceFile, withBytes]))
    }

    func testMetadataDigestMustBe32Bytes() throws {
        let short = [UInt8](repeating: 0, count: 16)
        let badRoot = makePinnedRoot(
            path: sourcePath,
            device: 11,
            file: 101,
            generation: 5,
            metadata: short)
        let (_, destinationRoot) = pinnedSourceAndDestination()
        let parent = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let operation = try copyOperation(source: "a.txt", destination: "docs/b.txt")
        assertCommitThrows(
            .invalidItemRevision,
            operation: operation,
            snapshot: FolderOperationCommitSnapshot(
                roots: [badRoot, destinationRoot],
                items: [parent]))

        let (sourceRoot, _) = pinnedSourceAndDestination()
        let badItem = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: [UInt8](repeating: 0, count: 31),
            content: contentA,
            bytes: 8)
        assertCommitThrows(
            .invalidItemRevision,
            operation: operation,
            snapshot: FolderOperationCommitSnapshot(
                roots: [sourceRoot, destinationRoot],
                items: [badItem, parent]))
    }

    func testItemRootMismatchRejected() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let parent = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let foreignRoot = makeRootIdentity(path: "/commit-foreign", device: 99, file: 999)
        let foreign = makeFileItem(
            root: foreignRoot,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let operation = try copyOperation(source: "a.txt", destination: "docs/b.txt")
        assertCommitThrows(
            .itemRevisionMismatch,
            operation: operation,
            snapshot: FolderOperationCommitSnapshot(
                roots: [sourceRoot, destinationRoot],
                items: [foreign, parent]))
    }

    func testDuplicateSlotWithDifferentGenerationCollides() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let parent = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let identity = sourceRoot.revision.identity
        let first = makeFileItem(
            root: identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            generation: 1,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let second = makeFileItem(
            root: identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            generation: 2,
            metadata: metadataA,
            content: contentB,
            bytes: 9)
        let operation = try copyOperation(source: "a.txt", destination: "docs/b.txt")
        assertCommitThrows(
            .itemRevisionMismatch,
            operation: operation,
            snapshot: FolderOperationCommitSnapshot(
                roots: [sourceRoot, destinationRoot],
                items: [first, second, parent]))
    }

    func testReceiptDigestsBindContentAndAreDeterministic() throws {
        let (operation, snapshot) = try copyWorld()
        let first = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)
        let second = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)
        XCTAssertEqual(first.receipt, second.receipt)

        var mutated = contentA
        mutated[mutated.count - 1] ^= 0xFF
        let (_, mutatedSnapshot) = try copySnapshot(sourceContent: mutated)
        let third = try FolderOperationCommitWorkflow.plan(operation, snapshot: mutatedSnapshot)
        XCTAssertNotEqual(first.receipt.planDigestSHA256, third.receipt.planDigestSHA256)
        XCTAssertNotEqual(first.receipt.stepDigestsSHA256, third.receipt.stepDigestsSHA256)
    }

    func testSourceSlotReadsBlockLaterWrites() throws {
        let sourceRoot = makePinnedRoot(
            path: sourcePath,
            device: 11,
            file: 101,
            generation: 5,
            metadata: metadataA)
        let identity = sourceRoot.revision.identity
        let first = makeFileItem(
            root: identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let other = makeFileItem(
            root: identity,
            path: "c.txt",
            device: 1003,
            file: 2003,
            metadata: metadataA,
            content: contentB,
            bytes: 9)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot],
            items: [first, other])
        let operation = FolderFileOperationPlan.synchronize(
            FolderSynchronizationPlan(
                sourceRoot: rootURL(sourcePath),
                destinationRoot: rootURL(sourcePath),
                steps: [
                    .copy(
                        source: try FolderRelativePath("a.txt"),
                        destination: try FolderRelativePath("b.txt"),
                        collisionPolicy: .fail),
                    .copy(
                        source: try FolderRelativePath("c.txt"),
                        destination: try FolderRelativePath("a.txt"),
                        collisionPolicy: .replaceKeepingBackup)
                ]))
        assertCommitThrows(
            .readDependencyViolation(firstStep: 0, secondStep: 1),
            operation: operation,
            snapshot: snapshot)
    }

    func testOverlappingDestinationWritesConflict() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let identity = sourceRoot.revision.identity
        let first = makeFileItem(
            root: identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let other = makeFileItem(
            root: identity,
            path: "c.txt",
            device: 1003,
            file: 2003,
            metadata: metadataA,
            content: contentB,
            bytes: 9)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [first, other])
        let operation = FolderFileOperationPlan.synchronize(
            FolderSynchronizationPlan(
                sourceRoot: rootURL(sourcePath),
                destinationRoot: rootURL(destinationPath),
                steps: [
                    .copy(
                        source: try FolderRelativePath("a.txt"),
                        destination: try FolderRelativePath("fresh.txt"),
                        collisionPolicy: .fail),
                    .copy(
                        source: try FolderRelativePath("c.txt"),
                        destination: try FolderRelativePath("fresh.txt"),
                        collisionPolicy: .fail)
                ]))
        assertCommitThrows(
            .conflictingPlan(firstStep: 0, secondStep: 1),
            operation: operation,
            snapshot: snapshot)
    }

    func testParentDeleteAndChildWriteConflict() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let sourceFile = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let identity = destinationRoot.revision.identity
        let parent = makeDirectoryItem(
            root: identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let child = makeFileItem(
            root: identity,
            path: "docs/kid.txt",
            device: 1004,
            file: 2004,
            metadata: metadataB,
            content: contentB,
            bytes: 9)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [sourceFile, parent, child])
        let operation = FolderFileOperationPlan.synchronize(
            FolderSynchronizationPlan(
                sourceRoot: rootURL(sourcePath),
                destinationRoot: rootURL(destinationPath),
                steps: [
                    .delete(
                        destination: try FolderRelativePath("docs"),
                        deletionPolicy: .moveToBackup),
                    .copy(
                        source: try FolderRelativePath("a.txt"),
                        destination: try FolderRelativePath("docs/file.txt"),
                        collisionPolicy: .fail)
                ]))
        assertCommitThrows(
            .conflictingPlan(firstStep: 0, secondStep: 1),
            operation: operation,
            snapshot: snapshot)
    }

    func testSkipReadsDoNotConflict() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let identity = sourceRoot.revision.identity
        let first = makeFileItem(
            root: identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let other = makeFileItem(
            root: identity,
            path: "c.txt",
            device: 1003,
            file: 2003,
            metadata: metadataA,
            content: contentB,
            bytes: 9)
        let existing = makeFileItem(
            root: destinationRoot.revision.identity,
            path: "e.txt",
            device: 1004,
            file: 2004,
            metadata: metadataB,
            content: contentB,
            bytes: 9)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [first, other, existing])
        let operation = FolderFileOperationPlan.synchronize(
            FolderSynchronizationPlan(
                sourceRoot: rootURL(sourcePath),
                destinationRoot: rootURL(destinationPath),
                steps: [
                    .copy(
                        source: try FolderRelativePath("a.txt"),
                        destination: try FolderRelativePath("e.txt"),
                        collisionPolicy: .skip),
                    .copy(
                        source: try FolderRelativePath("c.txt"),
                        destination: try FolderRelativePath("e.txt"),
                        collisionPolicy: .skip)
                ]))
        let bundle = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)
        XCTAssertEqual(bundle.receipt.skippedStepCount, 2)
        XCTAssertTrue(bundle.rollback.steps.isEmpty)
    }

    func testCopyIntoOwnSubdirectoryRejected() throws {
        let sourceRoot = makePinnedRoot(
            path: sourcePath,
            device: 11,
            file: 101,
            generation: 5,
            metadata: metadataA)
        let identity = sourceRoot.revision.identity
        let parent = makeDirectoryItem(
            root: identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataA)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot],
            items: [parent])
        let operation = FolderFileOperationPlan.copy(
            FolderCopyPlan(
                sourceRoot: rootURL(sourcePath),
                source: try FolderRelativePath("docs"),
                destinationRoot: rootURL(sourcePath),
                destination: try FolderRelativePath("docs/nested.txt")))
        assertCommitThrows(
            .sourceDestinationOverlap(step: 0),
            operation: operation,
            snapshot: snapshot)
    }

    func testDestinationCollisionWithFailPolicy() throws {
        let (operation, snapshot, _) = try existingDestinationWorld(collision: .fail)
        assertCommitThrows(
            .destinationCollision(step: 0),
            operation: operation,
            snapshot: snapshot)
    }

    func testMissingSourceRevision() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let parent = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [parent])
        let operation = try copyOperation(source: "ghost.txt", destination: "docs/b.txt")
        assertCommitThrows(
            .missingSourceRevision(step: 0),
            operation: operation,
            snapshot: snapshot)
    }

    func testMissingDestinationParent() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let sourceFile = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [sourceFile])
        let missing = try copyOperation(source: "a.txt", destination: "ghost/kid.txt")
        assertCommitThrows(
            .missingDestinationParent(step: 0),
            operation: missing,
            snapshot: snapshot)

        let blocker = makeFileItem(
            root: destinationRoot.revision.identity,
            path: "f.txt",
            device: 1004,
            file: 2004,
            metadata: metadataB,
            content: contentB,
            bytes: 9)
        let blockedSnapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [sourceFile, blocker])
        let blocked = try copyOperation(source: "a.txt", destination: "f.txt/kid.txt")
        assertCommitThrows(
            .missingDestinationParent(step: 0),
            operation: blocked,
            snapshot: blockedSnapshot)
    }

    func testUnresolvableAndInvalidRootsRejected() throws {
        let (sourceRoot, _) = pinnedSourceAndDestination()
        let sourceFile = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot],
            items: [sourceFile])
        let unknown = try copyOperation(
            source: "a.txt",
            destination: "b.txt",
            destinationRoot: "/commit-elsewhere")
        assertCommitThrows(.unknownRoot, operation: unknown, snapshot: snapshot)

        let remote = try XCTUnwrap(URL(string: "https://example.com/commit-src"))
        let remoteIdentity = FolderOperationCommitRootIdentity(
            canonicalURL: remote,
            deviceID: 11,
            fileID: 101,
            generation: 5)
        let remotePinned = FolderOperationCommitPinnedRoot(
            requestedURL: rootURL(sourcePath),
            revision: makeRootRevision(remoteIdentity, metadata: metadataA))
        let remoteSnapshot = FolderOperationCommitSnapshot(
            roots: [remotePinned],
            items: [])
        let operation = try copyOperation(source: "a.txt", destination: "b.txt")
        assertCommitThrows(.invalidRootURL, operation: operation, snapshot: remoteSnapshot)
    }

    func testConflictingRootIdentityRejected() throws {
        let first = makePinnedRoot(
            path: sourcePath,
            device: 11,
            file: 101,
            generation: 5,
            metadata: metadataA)
        let second = makePinnedRoot(
            path: sourcePath,
            device: 12,
            file: 102,
            generation: 5,
            metadata: metadataA)
        let snapshot = FolderOperationCommitSnapshot(roots: [first, second], items: [])
        let operation = try copyOperation(source: "a.txt", destination: "b.txt")
        assertCommitThrows(.conflictingRootIdentity, operation: operation, snapshot: snapshot)
    }

    func testNonEmptyDirectoryDeletePlansWithRestoreRollback() throws {
        let destinationRoot = makePinnedRoot(
            path: destinationPath,
            device: 22,
            file: 202,
            generation: 7,
            metadata: metadataB)
        let identity = destinationRoot.revision.identity
        let parent = makeDirectoryItem(
            root: identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let child = makeFileItem(
            root: identity,
            path: "docs/kid.txt",
            device: 1004,
            file: 2004,
            metadata: metadataB,
            content: contentB,
            bytes: 9)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [destinationRoot],
            items: [parent, child])
        let operation = try deleteOperation(target: "docs")
        let bundle = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)
        XCTAssertEqual(bundle.commit.steps.count, 1)
        XCTAssertEqual(bundle.commit.steps.first?.destinationPrior, parent)
        let rollback = try XCTUnwrap(bundle.rollback.steps.first)
        XCTAssertEqual(rollback.action, .restoreDeletedTarget)
        XCTAssertEqual(rollback.restored, parent)
    }

    func testEmptySynchronizeRejected() throws {
        let operation = FolderFileOperationPlan.synchronize(
            FolderSynchronizationPlan(
                sourceRoot: rootURL(sourcePath),
                destinationRoot: rootURL(destinationPath),
                steps: []))
        let (_, snapshot) = try copyWorld()
        assertCommitThrows(.emptyPlan, operation: operation, snapshot: snapshot)
    }

    func testStepLimitBoundary() throws {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let identity = sourceRoot.revision.identity
        let first = makeFileItem(
            root: identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let second = makeFileItem(
            root: identity,
            path: "b.txt",
            device: 1002,
            file: 2002,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let third = makeFileItem(
            root: identity,
            path: "c.txt",
            device: 1003,
            file: 2003,
            metadata: metadataA,
            content: contentB,
            bytes: 9)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [first, second, third])
        let limits = makeLimits(maximumSteps: 2)

        let allowed = FolderFileOperationPlan.synchronize(
            FolderSynchronizationPlan(
                sourceRoot: rootURL(sourcePath),
                destinationRoot: rootURL(destinationPath),
                steps: [
                    .copy(
                        source: try FolderRelativePath("a.txt"),
                        destination: try FolderRelativePath("o1.txt"),
                        collisionPolicy: .fail),
                    .copy(
                        source: try FolderRelativePath("b.txt"),
                        destination: try FolderRelativePath("o2.txt"),
                        collisionPolicy: .fail)
                ]))
        let bundle = try FolderOperationCommitWorkflow.plan(
            allowed,
            snapshot: snapshot,
            limits: limits)
        XCTAssertEqual(bundle.commit.steps.count, 2)
        XCTAssertEqual(bundle.rollback.steps.map(\.commitIndex), [1, 0])
        XCTAssertEqual(bundle.rollback.steps.map(\.rollbackOrder), [0, 1])

        let denied = FolderFileOperationPlan.synchronize(
            FolderSynchronizationPlan(
                sourceRoot: rootURL(sourcePath),
                destinationRoot: rootURL(destinationPath),
                steps: [
                    .copy(
                        source: try FolderRelativePath("a.txt"),
                        destination: try FolderRelativePath("o1.txt"),
                        collisionPolicy: .fail),
                    .copy(
                        source: try FolderRelativePath("b.txt"),
                        destination: try FolderRelativePath("o2.txt"),
                        collisionPolicy: .fail),
                    .copy(
                        source: try FolderRelativePath("c.txt"),
                        destination: try FolderRelativePath("o3.txt"),
                        collisionPolicy: .fail)
                ]))
        assertCommitThrows(
            .tooManySteps(maximum: 2),
            operation: denied,
            snapshot: snapshot,
            limits: limits)
    }

    func testInvalidLimitsRejected() throws {
        let (operation, snapshot) = try copyWorld()
        let cases: [(FolderOperationCommitLimits, FolderOperationCommitLimit)] = [
            (makeLimits(maximumSteps: -1), .steps),
            (makeLimits(maximumSteps: FolderOperationCommitLimits.hardMaximumSteps + 1), .steps),
            (makeLimits(maximumPinnedItems: -1), .pinnedItems),
            (makeLimits(maximumPathUTF8Bytes: -1), .pathBytes),
            (makeLimits(maximumTotalPathUTF8Bytes: -1), .totalPathBytes),
            (makeLimits(maximumPlanOutputBytes: -1), .planOutputBytes),
            (
                makeLimits(
                    maximumWorkUnits: FolderOperationCommitLimits.hardMaximumWorkUnits + 1),
                .workUnits
            )
        ]
        for (limits, limit) in cases {
            assertCommitThrows(
                .invalidLimit(limit),
                operation: operation,
                snapshot: snapshot,
                limits: limits)
        }
    }

    func testExhaustedBudgetsRejected() throws {
        let (operation, snapshot) = try copyWorld()
        assertCommitThrows(
            .workLimitExceeded(maximumUnits: 0),
            operation: operation,
            snapshot: snapshot,
            limits: makeLimits(maximumWorkUnits: 0))
        assertCommitThrows(
            .planOutputTooLarge(maximumBytes: 0),
            operation: operation,
            snapshot: snapshot,
            limits: makeLimits(maximumPlanOutputBytes: 0))
    }

    func testPathByteLimitsEnforced() throws {
        let sourceRoot = makePinnedRoot(
            path: "/s",
            device: 11,
            file: 101,
            generation: 5,
            metadata: metadataA)
        let destinationRoot = makePinnedRoot(
            path: "/d",
            device: 22,
            file: 202,
            generation: 7,
            metadata: metadataB)
        let sourceFile = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [sourceFile])
        let operation = FolderFileOperationPlan.copy(
            FolderCopyPlan(
                sourceRoot: rootURL("/s"),
                source: try FolderRelativePath("a.txt"),
                destinationRoot: rootURL("/d"),
                destination: try FolderRelativePath("b.txt")))

        assertCommitThrows(
            .pathTooLarge(maximumBytes: 4),
            operation: operation,
            snapshot: snapshot,
            limits: makeLimits(maximumPathUTF8Bytes: 4))
        assertCommitThrows(
            .totalPathsTooLarge(maximumBytes: 70),
            operation: operation,
            snapshot: snapshot,
            limits: makeLimits(maximumTotalPathUTF8Bytes: 70))
    }

    func testCancelledPlanThrowsCancelled() async throws {
        let (operation, snapshot) = try copyWorld()
        let task = Task.detached {
            try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)
        }
        task.cancel()
        let result = await task.result
        switch result {
        case .success:
            XCTFail("Cancelled plan unexpectedly succeeded")
        case .failure(let error):
            XCTAssertEqual(error as? FolderOperationCommitError, .cancelled)
        }
    }

    func testFailureAndPlanDescriptionsRedactPaths() throws {
        let (sourceRoot, _) = pinnedSourceAndDestination()
        let sourceFile = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let thin = FolderOperationCommitSnapshot(roots: [sourceRoot], items: [sourceFile])
        let unknown = try copyOperation(
            source: "a.txt",
            destination: "b.txt",
            destinationRoot: "/secret-root-abc")
        do {
            _ = try FolderOperationCommitWorkflow.plan(unknown, snapshot: thin)
            XCTFail("Expected unknownRoot")
        } catch let error as FolderOperationCommitError {
            XCTAssertEqual(error, .unknownRoot)
            assertRedacted(error, secrets: ["secret-root-abc"])
        }

        let (_, secretSnapshot, _) = try existingDestinationWorld(collision: .fail)
        let collision = try copyOperation(
            source: "a.txt",
            destination: "docs/b.txt",
            collision: .fail)
        do {
            _ = try FolderOperationCommitWorkflow.plan(collision, snapshot: secretSnapshot)
            XCTFail("Expected destinationCollision")
        } catch let error as FolderOperationCommitError {
            XCTAssertEqual(error, .destinationCollision(step: 0))
            assertRedacted(error, secrets: ["docs/b.txt", "commit-src", "commit-dst"])
        }

        let (operation, snapshot) = try copyWorld()
        let bundle = try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot)
        for rendered in [
            bundle.commit.description,
            bundle.commit.debugDescription,
            bundle.rollback.description,
            bundle.rollback.debugDescription,
            bundle.receipt.description,
            bundle.receipt.debugDescription
        ] {
            XCTAssertTrue(rendered.contains("<redacted>"))
            XCTAssertFalse(rendered.contains("a.txt"))
        }
    }

    // MARK: - Fixtures

    private func rootURL(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private func makeRootIdentity(
        path: String,
        device: UInt64,
        file: UInt64,
        generation: UInt32 = 1
    ) -> FolderOperationCommitRootIdentity {
        FolderOperationCommitRootIdentity(
            canonicalURL: rootURL(path),
            deviceID: device,
            fileID: file,
            generation: generation)
    }

    private func makeRootRevision(
        _ identity: FolderOperationCommitRootIdentity,
        metadata: [UInt8]
    ) -> FolderOperationCommitRootRevision {
        FolderOperationCommitRootRevision(
            identity: identity,
            linkCount: 2,
            permissions: 0o755,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            modificationTimeSeconds: 1_700_000_000,
            modificationTimeNanoseconds: 0,
            statusChangeTimeSeconds: 1_700_000_000,
            statusChangeTimeNanoseconds: 0,
            metadataSHA256: metadata)
    }

    private func makePinnedRoot(
        path: String,
        device: UInt64,
        file: UInt64,
        generation: UInt32 = 1,
        metadata: [UInt8]
    ) -> FolderOperationCommitPinnedRoot {
        let identity = makeRootIdentity(
            path: path,
            device: device,
            file: file,
            generation: generation)
        return FolderOperationCommitPinnedRoot(
            requestedURL: rootURL(path),
            revision: makeRootRevision(identity, metadata: metadata))
    }

    private func makeFileItem(
        root: FolderOperationCommitRootIdentity,
        path: String,
        device: UInt64,
        file: UInt64,
        generation: UInt32 = 1,
        metadata: [UInt8],
        content: [UInt8]?,
        bytes: UInt64?
    ) -> FolderOperationCommitItemRevision {
        FolderOperationCommitItemRevision(
            identity: FolderOperationCommitItemIdentity(
                rootIdentity: root,
                relativePath: path,
                deviceID: device,
                fileID: file,
                generation: generation),
            kind: .file,
            byteCount: bytes,
            linkCount: 1,
            permissions: 0o644,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            modificationTimeSeconds: 1_700_000_001,
            modificationTimeNanoseconds: 0,
            statusChangeTimeSeconds: 1_700_000_001,
            statusChangeTimeNanoseconds: 0,
            metadataSHA256: metadata,
            contentSHA256: content)
    }

    private func makeDirectoryItem(
        root: FolderOperationCommitRootIdentity,
        path: String,
        device: UInt64,
        file: UInt64,
        generation: UInt32 = 1,
        metadata: [UInt8],
        content: [UInt8]? = nil,
        bytes: UInt64? = nil
    ) -> FolderOperationCommitItemRevision {
        FolderOperationCommitItemRevision(
            identity: FolderOperationCommitItemIdentity(
                rootIdentity: root,
                relativePath: path,
                deviceID: device,
                fileID: file,
                generation: generation),
            kind: .directory,
            byteCount: bytes,
            linkCount: 2,
            permissions: 0o755,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            modificationTimeSeconds: 1_700_000_002,
            modificationTimeNanoseconds: 0,
            statusChangeTimeSeconds: 1_700_000_002,
            statusChangeTimeNanoseconds: 0,
            metadataSHA256: metadata,
            contentSHA256: content)
    }

    private func makeLimits(
        maximumSteps: Int? = nil,
        maximumPinnedItems: Int? = nil,
        maximumPathUTF8Bytes: Int? = nil,
        maximumTotalPathUTF8Bytes: Int? = nil,
        maximumWorkUnits: UInt64? = nil,
        maximumPlanOutputBytes: Int? = nil
    ) -> FolderOperationCommitLimits {
        FolderOperationCommitLimits(
            maximumSteps: maximumSteps ?? 256,
            maximumPinnedItems: maximumPinnedItems ?? 8192,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes ?? 16384,
            maximumTotalPathUTF8Bytes: maximumTotalPathUTF8Bytes ?? 1_048_576,
            maximumWorkUnits: maximumWorkUnits ?? 67_108_864,
            maximumPlanOutputBytes: maximumPlanOutputBytes ?? 4_194_304)
    }

    private func pinnedSourceAndDestination() -> (
        FolderOperationCommitPinnedRoot, FolderOperationCommitPinnedRoot
    ) {
        (
            makePinnedRoot(
                path: sourcePath,
                device: 11,
                file: 101,
                generation: 5,
                metadata: metadataA),
            makePinnedRoot(
                path: destinationPath,
                device: 22,
                file: 202,
                generation: 7,
                metadata: metadataB)
        )
    }

    private func copyOperation(
        source: String,
        destination: String,
        sourceRoot: String? = nil,
        destinationRoot: String? = nil,
        collision: FolderFileCollisionPolicy = .fail
    ) throws -> FolderFileOperationPlan {
        .copy(
            FolderCopyPlan(
                sourceRoot: rootURL(sourceRoot ?? sourcePath),
                source: try FolderRelativePath(source),
                destinationRoot: rootURL(destinationRoot ?? destinationPath),
                destination: try FolderRelativePath(destination),
                collisionPolicy: collision))
    }

    private func moveOperation(source: String, destination: String) throws -> FolderFileOperationPlan {
        .move(
            FolderMovePlan(
                sourceRoot: rootURL(sourcePath),
                source: try FolderRelativePath(source),
                destinationRoot: rootURL(destinationPath),
                destination: try FolderRelativePath(destination)))
    }

    private func deleteOperation(target: String) throws -> FolderFileOperationPlan {
        .delete(
            FolderDeletePlan(
                root: rootURL(destinationPath),
                target: try FolderRelativePath(target)))
    }

    private func copySnapshot(sourceContent: [UInt8]) throws -> (
        FolderFileOperationPlan, FolderOperationCommitSnapshot
    ) {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let sourceFile = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: sourceContent,
            bytes: 8)
        let parent = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [sourceFile, parent])
        let operation = try copyOperation(source: "a.txt", destination: "docs/b.txt")
        return (operation, snapshot)
    }

    private func copyWorld() throws -> (
        FolderFileOperationPlan, FolderOperationCommitSnapshot
    ) {
        try copySnapshot(sourceContent: contentA)
    }

    private func existingDestinationWorld(collision: FolderFileCollisionPolicy) throws -> (
        FolderFileOperationPlan, FolderOperationCommitSnapshot, FolderOperationCommitItemRevision
    ) {
        let (sourceRoot, destinationRoot) = pinnedSourceAndDestination()
        let sourceFile = makeFileItem(
            root: sourceRoot.revision.identity,
            path: "a.txt",
            device: 1001,
            file: 2001,
            metadata: metadataA,
            content: contentA,
            bytes: 8)
        let parent = makeDirectoryItem(
            root: destinationRoot.revision.identity,
            path: "docs",
            device: 1002,
            file: 2002,
            metadata: metadataB)
        let prior = makeFileItem(
            root: destinationRoot.revision.identity,
            path: "docs/b.txt",
            device: 1004,
            file: 2004,
            metadata: metadataB,
            content: contentB,
            bytes: 9)
        let snapshot = FolderOperationCommitSnapshot(
            roots: [sourceRoot, destinationRoot],
            items: [sourceFile, parent, prior])
        let operation = try copyOperation(
            source: "a.txt",
            destination: "docs/b.txt",
            collision: collision)
        return (operation, snapshot, prior)
    }

    private func assertCommitThrows(
        _ expected: FolderOperationCommitError,
        operation: FolderFileOperationPlan,
        snapshot: FolderOperationCommitSnapshot,
        limits: FolderOperationCommitLimits = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try FolderOperationCommitWorkflow.plan(operation, snapshot: snapshot, limits: limits),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? FolderOperationCommitError, expected, file: file, line: line)
        }
    }

    private func assertRedacted(
        _ error: FolderOperationCommitError,
        secrets: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("<redacted>"), file: file, line: line)
        for secret in secrets {
            XCTAssertFalse(description.contains(secret), file: file, line: line)
        }
    }
}
