import Foundation
import MacMergeCore
import XCTest

final class FolderResultsPresentationTests: XCTestCase {
    func testProjectDelegatesExactWorkflowOrderWithoutResort() throws {
        let roots = makeRoots()
        let rows = makeSortRows(roots: roots)
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        let configuration = FolderComparisonPresentationConfiguration(
            sortDescriptors: [
                FolderComparisonPresentationSortDescriptor(key: .leftSize, order: .descending),
                FolderComparisonPresentationSortDescriptor(key: .path),
            ]
        )
        let request = makeRequest(snapshot: snapshot, configuration: configuration)

        let projected = try FolderResultsPresentationPlanner.project(request)
        let planned = try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(
                snapshot: snapshot,
                configuration: configuration,
                capabilities: request.capabilities,
                limits: request.workflowLimits
            )
        )

        XCTAssertEqual(projected.rows.map(\.id), planned.rows.map(\.id))
        XCTAssertEqual(projected.rows.map(\.relativePath), planned.rows.map(\.relativePath))
        XCTAssertEqual(projected.receipt.inputResultCount, rows.count)
        XCTAssertEqual(projected.receipt.outputRowCount, projected.rows.count)
        XCTAssertEqual(
            projected.receipt.filteredOutResultCount,
            rows.count - projected.rows.count
        )
        XCTAssertGreaterThan(projected.receipt.estimatedWorkUnits, 0)
    }

    func testSelectionRetainsFilteredOutRows() throws {
        let roots = makeRoots()
        let visible = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let filtered = makeOneSidedRow(path: "b.txt", side: .right, roots: roots, seed: 20)
        let snapshot = makeSnapshot(roots: roots, rows: [visible, filtered])
        let configuration = FolderComparisonPresentationConfiguration(
            filter: FolderComparisonPresentationFilter(statuses: [.leftOnly])
        )
        let selected: Set<DirectoryResult.ID> = [visible.result.id, filtered.result.id]
        let projected = try FolderResultsPresentationPlanner.project(
            makeRequest(snapshot: snapshot, configuration: configuration, selected: selected)
        )

        XCTAssertEqual(projected.rows.map(\.id), [visible.result.id])
        XCTAssertEqual(projected.selectedResultIDs, selected)
        XCTAssertEqual(projected.visibleSelectedRows.map(\.id), [visible.result.id])
        XCTAssertEqual(projected.hiddenSelectedResultIDs, [filtered.result.id])
        XCTAssertEqual(projected.filteredOutResultCount, 1)
        XCTAssertTrue(projected.rows[0].isSelected)
    }

    func testUnknownSelectedResultRejected() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        let unknown = DirectoryResult.ID(leftRelativePath: "missing.txt", rightRelativePath: nil)

        XCTAssertThrowsError(
            try FolderResultsPresentationPlanner.project(
                makeRequest(snapshot: snapshot, selected: [unknown])
            )
        ) { error in
            XCTAssertEqual(
                error as? FolderResultsPresentationError,
                .unknownSelectedResult(unknown)
            )
        }
    }

    func testUnknownCursorResultRejected() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        let unknown = DirectoryResult.ID(leftRelativePath: nil, rightRelativePath: "ghost.txt")

        XCTAssertThrowsError(
            try FolderResultsPresentationPlanner.project(
                makeRequest(snapshot: snapshot, cursor: unknown)
            )
        ) { error in
            XCTAssertEqual(error as? FolderResultsPresentationError, .unknownCursorResult(unknown))
        }
    }

    func testCursorFlagsAndVisibleOrdinals() throws {
        let roots = makeRoots()
        let rows = makeSortRows(roots: roots)
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        let cursor = rows[1].result.id
        let projected = try FolderResultsPresentationPlanner.project(
            makeRequest(
                snapshot: snapshot,
                selected: [rows[0].result.id],
                cursor: cursor
            )
        )

        XCTAssertEqual(projected.cursorResultID, cursor)
        for (index, row) in projected.rows.enumerated() {
            XCTAssertEqual(row.visibleOrdinal, index)
            XCTAssertEqual(row.isCursor, row.id == cursor)
            XCTAssertEqual(row.isSelected, row.id == rows[0].result.id)
        }
        XCTAssertEqual(projected.rows.filter(\.isCursor).count, 1)
    }

    func testTableRowsCarryNoTreeParents() throws {
        let roots = makeRoots()
        let rows = makeSortRows(roots: roots)
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        let projected = try FolderResultsPresentationPlanner.project(
            makeRequest(
                snapshot: snapshot,
                configuration: FolderComparisonPresentationConfiguration(mode: .table)
            )
        )

        XCTAssertTrue(projected.rows.allSatisfy { $0.treeParentID == nil && $0.treeDepth == 0 })
        XCTAssertEqual(projected.rootRows.map(\.id), projected.rows.map(\.id))
        for row in projected.rows {
            XCTAssertTrue(projected.children(of: row.id).isEmpty)
            XCTAssertEqual(projected.row(withID: row.id)?.id, row.id)
        }
    }

    func testTreePreorderMapsExposeParentsAndChildren() throws {
        let roots = makeRoots()
        let folder = makePairedRow(path: "folder", kind: .directory, roots: roots, seed: 10)
        let nested = makePairedRow(path: "folder/sub", kind: .directory, roots: roots, seed: 20)
        let child = makePairedRow(path: "folder/sub/child.txt", roots: roots, seed: 30)
        let sibling = makePairedRow(path: "folder/sibling.txt", roots: roots, seed: 40)
        let snapshot = makeSnapshot(roots: roots, rows: [child, sibling, nested, folder])
        let projected = try FolderResultsPresentationPlanner.project(
            makeRequest(
                snapshot: snapshot,
                configuration: FolderComparisonPresentationConfiguration(mode: .tree)
            )
        )

        XCTAssertEqual(projected.rows.count, 4)
        XCTAssertEqual(projected.rootRows.map(\.id), [folder.result.id])
        XCTAssertEqual(
            Set(projected.children(of: folder.result.id).map(\.id)),
            [nested.result.id, sibling.result.id]
        )
        XCTAssertEqual(projected.children(of: nested.result.id).map(\.id), [child.result.id])
        XCTAssertTrue(projected.children(of: child.result.id).isEmpty)
        let nestedRow = try XCTUnwrap(projected.row(withID: nested.result.id))
        XCTAssertEqual(nestedRow.treeParentID, folder.result.id)
        XCTAssertEqual(nestedRow.treeDepth, 1)
        XCTAssertEqual(projected.row(withID: child.result.id)?.treeDepth, 2)
        for (index, row) in projected.rows.enumerated() {
            XCTAssertEqual(row.visibleOrdinal, index)
        }
        for row in projected.rows {
            guard let parentID = row.treeParentID else { continue }
            let parentOrdinal = try XCTUnwrap(projected.row(withID: parentID)?.visibleOrdinal)
            XCTAssertLessThan(parentOrdinal, row.visibleOrdinal)
        }
    }

    func testValidateCurrentPinsIdentityGenerationAndOwner() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        let projected = try FolderResultsPresentationPlanner.project(makeRequest(snapshot: snapshot))

        XCTAssertNoThrow(try projected.validateCurrent(snapshot))
        XCTAssertTrue(projected.isCurrent(for: snapshot))

        let nextGeneration = makeSnapshot(roots: roots, rows: [row], generation: 99)
        XCTAssertThrowsError(try projected.validateCurrent(nextGeneration)) { error in
            XCTAssertEqual(error as? FolderResultsPresentationError, .staleSnapshot)
        }
        XCTAssertFalse(projected.isCurrent(for: nextGeneration))

        let nextOwner = makeSnapshot(
            roots: roots,
            rows: [row],
            owner: FolderComparisonWorkflowSnapshotOwner(
                identity: UUID(uuidString: "00000000-0000-0000-0000-000000000999")!,
                revision: 3
            )
        )
        XCTAssertThrowsError(try projected.validateCurrent(nextOwner)) { error in
            XCTAssertEqual(error as? FolderResultsPresentationError, .staleSnapshot)
        }

        let nextIdentity = makeSnapshot(
            identity: FolderComparisonWorkflowSnapshotIdentity(),
            roots: roots,
            rows: [row]
        )
        XCTAssertThrowsError(try projected.validateCurrent(nextIdentity)) { error in
            XCTAssertEqual(error as? FolderResultsPresentationError, .staleSnapshot)
        }
    }

    func testValidateCurrentRejectsSilentContentChange() throws {
        let roots = makeRoots()
        let first = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let second = makeOneSidedRow(path: "b.txt", side: .left, roots: roots, seed: 20)
        let snapshot = makeSnapshot(roots: roots, rows: [first, second])
        let projected = try FolderResultsPresentationPlanner.project(makeRequest(snapshot: snapshot))

        let tampered = makeSnapshot(roots: roots, rows: [first])
        XCTAssertThrowsError(try projected.validateCurrent(tampered)) { error in
            XCTAssertEqual(error as? FolderResultsPresentationError, .snapshotContentsChanged)
        }
        XCTAssertFalse(projected.isCurrent(for: tampered))
    }

    func testRowLimitEnforced() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        var request = makeRequest(snapshot: snapshot)
        request = FolderResultsPresentationRequest(
            snapshot: snapshot,
            configuration: request.configuration,
            capabilities: request.capabilities,
            workflowLimits: request.workflowLimits,
            presentationLimits: FolderResultsPresentationLimits(maximumRowCount: 0)
        )

        XCTAssertThrowsError(try FolderResultsPresentationPlanner.project(request)) { error in
            XCTAssertEqual(error as? FolderResultsPresentationError, .tooManyRows(maximum: 0))
        }
    }

    func testStringBudgetsEnforced() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "long-name.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])

        var tinyString = makeRequest(snapshot: snapshot, selected: [row.result.id])
        tinyString = FolderResultsPresentationRequest(
            snapshot: snapshot,
            configuration: tinyString.configuration,
            selectedResultIDs: tinyString.selectedResultIDs,
            capabilities: tinyString.capabilities,
            workflowLimits: tinyString.workflowLimits,
            presentationLimits: FolderResultsPresentationLimits(maximumStringUTF8Bytes: 1)
        )
        XCTAssertThrowsError(try FolderResultsPresentationPlanner.project(tinyString)) { error in
            XCTAssertEqual(
                error as? FolderResultsPresentationError,
                .stringTooLarge(maximumUTF8Bytes: 1)
            )
        }

        var tinyTotal = makeRequest(snapshot: snapshot, selected: [row.result.id])
        tinyTotal = FolderResultsPresentationRequest(
            snapshot: snapshot,
            configuration: tinyTotal.configuration,
            selectedResultIDs: tinyTotal.selectedResultIDs,
            capabilities: tinyTotal.capabilities,
            workflowLimits: tinyTotal.workflowLimits,
            presentationLimits: FolderResultsPresentationLimits(maximumTotalStringUTF8Bytes: 1)
        )
        XCTAssertThrowsError(try FolderResultsPresentationPlanner.project(tinyTotal)) { error in
            XCTAssertEqual(
                error as? FolderResultsPresentationError,
                .totalStringsTooLarge(maximumUTF8Bytes: 1)
            )
        }
    }

    func testWorkBudgetEnforced() throws {
        let roots = makeRoots()
        let rows = makeSortRows(roots: roots)
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        var request = makeRequest(snapshot: snapshot)
        request = FolderResultsPresentationRequest(
            snapshot: snapshot,
            configuration: request.configuration,
            capabilities: request.capabilities,
            workflowLimits: request.workflowLimits,
            presentationLimits: FolderResultsPresentationLimits(maximumWorkUnits: 1)
        )

        XCTAssertThrowsError(try FolderResultsPresentationPlanner.project(request)) { error in
            XCTAssertEqual(
                error as? FolderResultsPresentationError,
                .workLimitExceeded(maximumWorkUnits: 1)
            )
        }
    }

    func testInvalidLimitsRejected() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        let cases: [(FolderResultsPresentationLimits, FolderResultsPresentationError)] = [
            (
                FolderResultsPresentationLimits(maximumRowCount: -1),
                .invalidLimit(.rowCount, value: "-1")
            ),
            (
                FolderResultsPresentationLimits(maximumStringUTF8Bytes: 0),
                .invalidLimit(.stringUTF8Bytes, value: "0")
            ),
            (
                FolderResultsPresentationLimits(maximumTotalStringUTF8Bytes: 0),
                .invalidLimit(.totalStringUTF8Bytes, value: "0")
            ),
            (
                FolderResultsPresentationLimits(maximumWorkUnits: 0),
                .invalidLimit(.workUnits, value: "0")
            ),
            (
                FolderResultsPresentationLimits(cancellationCheckInterval: 0),
                .invalidLimit(.cancellationCheckInterval, value: "0")
            ),
        ]
        for (limits, expected) in cases {
            let request = FolderResultsPresentationRequest(
                snapshot: snapshot,
                capabilities: makeCapabilities(),
                presentationLimits: limits
            )
            XCTAssertThrowsError(try FolderResultsPresentationPlanner.project(request)) { error in
                XCTAssertEqual(error as? FolderResultsPresentationError, expected)
            }
        }
    }

    func testCancellationIsCooperative() async {
        let roots = makeRoots()
        let rows = (0..<64).map { index in
            makeOneSidedRow(
                path: "file-\(index).txt",
                side: index.isMultiple(of: 2) ? .left : .right,
                roots: roots,
                seed: UInt8(index + 20)
            )
        }
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        let request = FolderResultsPresentationRequest(
            snapshot: snapshot,
            capabilities: makeCapabilities(),
            presentationLimits: FolderResultsPresentationLimits(cancellationCheckInterval: 1)
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FolderResultsPresentationPlanner.project(request)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? FolderResultsPresentationError, .cancelled)
        }
    }

    // MARK: - Fixtures

    private let snapshotIdentity = FolderComparisonWorkflowSnapshotIdentity(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    )
    private let snapshotOwnerID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    private let capabilityID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!

    private func makeCapabilities() -> FolderComparisonWorkflowCapabilities {
        FolderComparisonWorkflowCapabilities(
            identity: capabilityID,
            revision: 1,
            features: Set(FolderComparisonWorkflowFeature.allCases)
        )
    }

    private func makeRoot(side: FolderComparisonWorkflowSide) -> FolderComparisonRoot {
        let identity = FolderComparisonRootIdentity(
            canonicalURL: URL(filePath: side == .left ? "/left" : "/right"),
            deviceID: side == .left ? 1 : 2,
            fileID: side == .left ? 101 : 202,
            generation: side == .left ? 11 : 22
        )
        return FolderComparisonRoot(
            requestedURL: identity.canonicalURL,
            revision: FolderComparisonRootRevision(
                identity: identity,
                linkCount: 2,
                permissions: 0o755,
                ownerID: 501,
                groupID: 20,
                flags: 0,
                modificationTimeSeconds: 100,
                modificationTimeNanoseconds: 0,
                statusChangeTimeSeconds: 101,
                statusChangeTimeNanoseconds: 0,
                metadataSHA256: Array(repeating: side == .left ? 1 : 2, count: 32)
            ),
            authority: FolderComparisonAccessAuthority(
                identity: UUID(uuidString: "00000000-0000-0000-0000-00000000020\(side == .left ? 4 : 5)")!,
                revision: 1,
                rootIdentity: identity,
                permissions: [.enumerate, .readContent, .mutate],
                coverage: .directoryTree,
                acquisition: .ambient
            ),
            pathCaseSensitivity: .sensitive
        )
    }

    private func makeRoots() -> FolderComparisonRootPair {
        FolderComparisonRootPair(left: makeRoot(side: .left), right: makeRoot(side: .right))
    }

    private func makeMetadata(path: String) -> DirectoryEntryMetadata {
        DirectoryEntryMetadata(
            relativePath: path,
            kind: .file,
            byteCount: 4,
            modificationDate: Date(timeIntervalSince1970: 10),
            isHidden: false
        )
    }

    private struct RowFixture {
        let result: DirectoryResult
        let revision: FolderComparisonResultRevision
    }

    private func makeItemRevision(
        root: FolderComparisonRoot,
        path: String,
        seed: UInt8
    ) -> FolderComparisonItemRevision {
        FolderComparisonItemRevision(
            identity: FolderComparisonItemIdentity(
                rootIdentity: root.revision.identity,
                relativePath: path,
                deviceID: UInt64(seed) + 100,
                fileID: UInt64(seed) + 1_000,
                generation: UInt32(seed) + 1
            ),
            kind: .file,
            byteCount: 4,
            linkCount: 1,
            permissions: 0o644,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            modificationTimeSeconds: 10,
            modificationTimeNanoseconds: 0,
            statusChangeTimeSeconds: 11,
            statusChangeTimeNanoseconds: 0,
            metadataSHA256: Array(repeating: seed, count: 32),
            contentSHA256: Array(repeating: seed, count: 32)
        )
    }

    private func makePairedRow(
        path: String,
        kind: DirectoryEntryKind = .file,
        roots: FolderComparisonRootPair,
        seed: UInt8
    ) -> RowFixture {
        let left = DirectoryEntryMetadata(
            relativePath: path,
            kind: kind,
            byteCount: kind == .file ? 4 : nil,
            modificationDate: Date(timeIntervalSince1970: 10),
            isHidden: false
        )
        let right = DirectoryEntryMetadata(
            relativePath: path,
            kind: kind,
            byteCount: kind == .file ? 4 : nil,
            modificationDate: Date(timeIntervalSince1970: 10),
            isHidden: false
        )
        let result = DirectoryResult(left: left, right: right, status: .identical)
        let directoryRevision = { (root: FolderComparisonRoot, seed: UInt8) in
            FolderComparisonItemRevision(
                identity: FolderComparisonItemIdentity(
                    rootIdentity: root.revision.identity,
                    relativePath: path,
                    deviceID: UInt64(seed) + 100,
                    fileID: UInt64(seed) + 1_000,
                    generation: UInt32(seed) + 1
                ),
                kind: kind,
                byteCount: kind == .file ? 4 : nil,
                linkCount: 1,
                permissions: 0o644,
                ownerID: 501,
                groupID: 20,
                flags: 0,
                modificationTimeSeconds: 10,
                modificationTimeNanoseconds: 0,
                statusChangeTimeSeconds: 11,
                statusChangeTimeNanoseconds: 0,
                metadataSHA256: Array(repeating: seed, count: 32),
                contentSHA256: kind == .file ? Array(repeating: seed, count: 32) : nil
            )
        }
        return RowFixture(
            result: result,
            revision: FolderComparisonResultRevision(
                id: result.id,
                left: directoryRevision(roots.left, seed),
                right: directoryRevision(roots.right, seed &+ 1)
            )
        )
    }

    private func makeOneSidedRow(
        path: String,
        side: FolderComparisonWorkflowSide,
        roots: FolderComparisonRootPair,
        seed: UInt8
    ) -> RowFixture {
        let metadata = makeMetadata(path: path)
        let result = DirectoryResult(
            left: side == .left ? metadata : nil,
            right: side == .right ? metadata : nil,
            status: side == .left ? .leftOnly : .rightOnly
        )
        let revision = makeItemRevision(root: roots[side], path: path, seed: seed)
        return RowFixture(
            result: result,
            revision: FolderComparisonResultRevision(
                id: result.id,
                left: side == .left ? revision : nil,
                right: side == .right ? revision : nil
            )
        )
    }

    private func makeSortRows(roots: FolderComparisonRootPair) -> [RowFixture] {
        [
            makeOneSidedRow(path: "c.txt", side: .left, roots: roots, seed: 30),
            makeOneSidedRow(path: "a.txt", side: .right, roots: roots, seed: 40),
            makeOneSidedRow(path: "b.txt", side: .left, roots: roots, seed: 50),
        ]
    }

    private func makeSnapshot(
        identity: FolderComparisonWorkflowSnapshotIdentity? = nil,
        roots: FolderComparisonRootPair,
        rows: [RowFixture],
        generation: UInt64 = 3,
        owner: FolderComparisonWorkflowSnapshotOwner? = nil
    ) -> FolderComparisonWorkflowSnapshot {
        FolderComparisonWorkflowSnapshot(
            identity: identity ?? snapshotIdentity,
            generation: generation,
            owner: owner
                ?? FolderComparisonWorkflowSnapshotOwner(
                    identity: snapshotOwnerID,
                    revision: generation
                ),
            roots: roots,
            scanIntent: FolderComparisonScanIntent(),
            comparisonSettings: FolderComparisonSettings(),
            isComplete: true,
            results: rows.map(\.result),
            resultRevisions: rows.map(\.revision)
        )
    }

    private func makeRequest(
        snapshot: FolderComparisonWorkflowSnapshot,
        configuration: FolderComparisonPresentationConfiguration = FolderComparisonPresentationConfiguration(),
        selected: Set<DirectoryResult.ID> = [],
        cursor: DirectoryResult.ID? = nil
    ) -> FolderResultsPresentationRequest {
        FolderResultsPresentationRequest(
            snapshot: snapshot,
            configuration: configuration,
            selectedResultIDs: selected,
            cursorResultID: cursor,
            capabilities: makeCapabilities()
        )
    }
}
