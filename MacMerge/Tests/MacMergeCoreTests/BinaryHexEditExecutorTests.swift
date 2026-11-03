import Foundation
import XCTest

@testable import MacMergeCore

final class BinaryHexEditExecutorTests: XCTestCase {
    private let identity = BinaryHexContentIdentity(
        rawValue: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    )

    func testInsertBytesAtOffsetCommitsWithRevisionBump() async throws {
        let executor = executorFor([0x10, 0x20, 0x30], selection: 1..<1)
        let receipt = try await executor.insert(
            .bytes(Data([0xAA, 0xBB])),
            at: .byteOffset(1),
            for: .left
        )
        XCTAssertEqual(receipt.committedPane.data, Data([0x10, 0xAA, 0xBB, 0x20, 0x30]))
        XCTAssertEqual(receipt.committedPane.version.revision, 2)
        XCTAssertEqual(receipt.committedPane.version.identity, identity)
        XCTAssertEqual(receipt.mutationCount, 1)
        XCTAssertEqual(receipt.sourceVersion.revision, 1)
        let live = await executor.snapshot(of: .left)
        XCTAssertEqual(live, receipt.committedPane)
    }

    func testInsertAtSelectionReplacesRange() async throws {
        let executor = executorFor([0x01, 0x02, 0x03, 0x04], selection: 1..<3)
        let receipt = try await executor.insert(
            .bytes(Data([0xFF])),
            at: .currentSelection,
            for: .left
        )
        XCTAssertEqual(receipt.committedPane.data, Data([0x01, 0xFF, 0x04]))
        XCTAssertEqual(receipt.committedPane.selection.byteRange, 2..<2)
    }

    func testOverwriteAtOffsetAndBeyondEnd() async throws {
        let executor = executorFor([0x01, 0x02, 0x03], selection: 0..<0)
        let receipt = try await executor.overwrite(
            .bytes(Data([0xAA, 0xBB])),
            at: .byteOffset(1),
            for: .left
        )
        XCTAssertEqual(receipt.committedPane.data, Data([0x01, 0xAA, 0xBB]))

        let selector = executorFor([0x01, 0x02, 0x03], selection: 0..<2)
        let selected = try await selector.overwrite(
            .bytes(Data([0xAA, 0xBB])),
            at: .currentSelection,
            for: .left
        )
        XCTAssertEqual(selected.committedPane.data, Data([0xAA, 0xBB, 0x03]))

        await assertAsyncPolicyError(
            .overwriteBeyondEnd(range: 2..<4, byteCount: 3)
        ) {
            try await selector.overwrite(
                .bytes(Data([0xAA, 0xBB])),
                at: .byteOffset(2),
                for: .left
            )
        }
    }

    func testDeleteSelectionMarksDirty() async throws {
        let executor = executorFor([0x01, 0x02, 0x03], selection: 0..<2)
        let receipt = try await executor.delete(for: .left)
        XCTAssertEqual(receipt.committedPane.data, Data([0x03]))
        XCTAssertTrue(receipt.committedPane.isDirty)
        XCTAssertEqual(receipt.committedPane.selection.byteRange, 0..<0)
    }

    func testFindMovesSelectionAndReportsMiss() async throws {
        let executor = executorFor([0x10, 0x20, 0x10, 0x30], selection: 0..<0)
        let found = try await executor.find(
            BinaryHexFindIntent(pattern: .bytes(Data([0x10])), direction: .forward),
            for: .left
        )
        XCTAssertEqual(found.committedPane.selection.byteRange, 0..<1)

        let missed = try await executor.find(
            BinaryHexFindIntent(pattern: .bytes(Data([0xFF])), wraps: true),
            for: .left
        )
        XCTAssertEqual(missed.mutationCount, 0)
        XCTAssertEqual(missed.committedPane.selection, found.committedPane.selection)
        XCTAssertEqual(missed.committedPane.version.revision, found.committedPane.version.revision)
    }

    func testReplaceAllCommitsEveryMatch() async throws {
        let executor = executorFor([0x41, 0x42, 0x41, 0x42], selection: 0..<0)
        let receipt = try await executor.replace(
            BinaryHexReplaceIntent(
                pattern: .bytes(Data([0x41])),
                replacement: .bytes(Data([0x5A])),
                scope: .all
            ),
            for: .left
        )
        XCTAssertEqual(receipt.committedPane.data, Data([0x5A, 0x42, 0x5A, 0x42]))
        XCTAssertEqual(receipt.replacementCount, 2)
        XCTAssertEqual(receipt.mutationCount, 2)
    }

    func testReplaceCurrentSelectionScope() async throws {
        let executor = executorFor([0x41, 0x42], selection: 0..<1)
        let receipt = try await executor.replace(
            BinaryHexReplaceIntent(
                pattern: .bytes(Data([0x41])),
                replacement: .bytes(Data([0x5A])),
                scope: .currentSelection
            ),
            for: .left
        )
        XCTAssertEqual(receipt.committedPane.data, Data([0x5A, 0x42]))
    }

    func testGoToTargets() async throws {
        let executor = executorFor(Array(0..<32).map { UInt8($0) }, selection: 0..<0)
        let offset = try await executor.goTo(BinaryHexGoToIntent(target: .byteOffset(9)), for: .left)
        XCTAssertEqual(offset.committedPane.selection.byteRange, 9..<9)

        let row = try await executor.goTo(
            BinaryHexGoToIntent(target: .row(index: 1, column: 2)),
            for: .left
        )
        XCTAssertEqual(row.committedPane.selection.byteRange, 18..<18)

        let end = try await executor.goTo(BinaryHexGoToIntent(target: .end), for: .left)
        XCTAssertEqual(end.committedPane.selection.byteRange, 32..<32)
    }

    func testSelectSetAndSelectAll() async throws {
        let executor = executorFor([0x10, 0x20, 0x30], selection: 0..<0)
        let set = try await executor.select(
            .set(BinaryHexSelection(byteRange: 1..<3, surface: .characters)),
            for: .left
        )
        XCTAssertEqual(
            set.committedPane.selection,
            BinaryHexSelection(byteRange: 1..<3, surface: .characters)
        )
        XCTAssertEqual(set.committedPane.data, Data([0x10, 0x20, 0x30]))

        let all = try await executor.select(.selectAll(surface: .bytes), for: .left)
        XCTAssertEqual(all.committedPane.selection.byteRange, 0..<3)
    }

    func testCharacterSetsEncodeThroughExecutor() async throws {
        let utf16 = executorFor(
            [0x41],
            selection: 1..<1,
            settings: display(characterSet: .utf16LittleEndian)
        )
        let utf16Receipt = try await utf16.insert(.characters("B"), at: .currentSelection, for: .left)
        XCTAssertEqual(utf16Receipt.committedPane.data, Data([0x41, 0x42, 0x00]))
        XCTAssertEqual(utf16Receipt.committedPane.selection.surface, .characters)

        let win = executorFor(
            [],
            persisted: [],
            selection: 0..<0,
            settings: display(characterSet: .windows1252)
        )
        let winReceipt = try await win.insert(.characters("€"), at: .byteOffset(0), for: .left)
        XCTAssertEqual(winReceipt.committedPane.data, Data([0x80]))

        let ascii = executorFor([], persisted: [], selection: 0..<0)
        await assertAsyncPolicyError(
            .characterNotRepresentable(characterSet: .ascii, scalar: 0xE9)
        ) {
            try await ascii.insert(.characters("é"), at: .byteOffset(0), for: .left)
        }
    }

    func testStatusAndAlignedSelectionProjection() async throws {
        let executor = executorFor([0x10, 0x20, 0x30], selection: 1..<1)
        let status = try await executor.status(for: .left)
        XCTAssertEqual(status.byteCount, 3)
        XCTAssertEqual(status.byteOffset, 1)
        XCTAssertEqual(status.currentByte, 0x20)
        XCTAssertEqual(status.row, 0)
        XCTAssertEqual(status.column, 1)

        let comparison = BinaryComparison.compare(
            left: Data([0x10, 0x20]),
            right: Data([0x10, 0xAA, 0x20])
        )
        let projected = try await executor.selection(
            atAlignedOffset: 1,
            side: .right,
            in: comparison
        )
        XCTAssertEqual(projected, BinaryHexSelection(byteOffset: 1))
    }

    func testReadOnlyPaneRejectsEditsButAllowsNavigation() async throws {
        let executor = executorFor([0x01, 0x02], selection: 0..<0, isReadOnly: true)
        await assertAsyncPolicyError(.readOnlyPane(.left)) {
            try await executor.insert(.bytes(Data([0xFF])), at: .byteOffset(0), for: .left)
        }
        await assertAsyncPolicyError(.readOnlyPane(.left)) {
            try await executor.delete(for: .left)
        }
        await assertAsyncPolicyError(.readOnlyPane(.left)) {
            try await executor.replace(
                BinaryHexReplaceIntent(
                    pattern: .bytes(Data([0x01])),
                    replacement: .bytes(Data([0xFF])),
                    scope: .all
                ),
                for: .left
            )
        }
        let navigated = try await executor.goTo(
            BinaryHexGoToIntent(target: .byteOffset(2)),
            for: .left
        )
        XCTAssertEqual(navigated.committedPane.selection.byteRange, 2..<2)
        let live = await executor.snapshot(of: .left)
        XCTAssertEqual(live?.data, Data([0x01, 0x02]))
    }

    func testByteExactCASRejectsStaleData() async throws {
        let executor = executorFor([0x01, 0x02], selection: 0..<0)
        let plan = try await executor.plan(
            .edit(.insert(payload: .bytes(Data([0xFF])), target: .byteOffset(2))),
            for: .left
        )
        let source = plan.sourcePane
        await executor.setPane(
            BinaryHexPaneSnapshot(
                pane: source.pane,
                version: source.version,
                data: Data([0x01, 0x09]),
                persistedData: source.persistedData,
                maximumByteCount: source.maximumByteCount,
                selection: source.selection,
                displaySettings: source.displaySettings,
                isReadOnly: source.isReadOnly,
                isDirty: true
            )
        )
        let outcome = try await executor.compareAndExecute(plan.transaction)
        guard case .notCommitted(let current) = outcome else {
            return XCTFail("Stale data unexpectedly committed")
        }
        XCTAssertEqual(current.data, Data([0x01, 0x09]))
        let live = await executor.snapshot(of: .left)
        XCTAssertEqual(live?.data, Data([0x01, 0x09]))
    }

    func testCASRejectsRevisionAndSelectionMismatch() async throws {
        let executor = executorFor([0x01, 0x02], selection: 0..<0)
        let plan = try await executor.plan(
            .edit(.delete(selection: BinaryHexSelection(byteRange: 0..<1))),
            for: .left
        )

        await executor.setPane(
            BinaryHexPaneSnapshot(
                pane: .left,
                version: BinaryHexContentVersion(identity: identity, revision: 2),
                data: Data([0x01, 0x02]),
                persistedData: Data([0x01, 0x02]),
                selection: BinaryHexSelection(byteRange: 0..<0),
                isDirty: false
            )
        )
        let revisionOutcome = try await executor.compareAndExecute(plan.transaction)
        guard case .notCommitted = revisionOutcome else {
            return XCTFail("Revision drift unexpectedly committed")
        }

        let source = plan.sourcePane
        await executor.setPane(
            BinaryHexPaneSnapshot(
                pane: source.pane,
                version: source.version,
                data: source.data,
                persistedData: source.persistedData,
                selection: BinaryHexSelection(byteRange: 1..<1),
                isDirty: false
            )
        )
        let selectionOutcome = try await executor.compareAndExecute(plan.transaction)
        guard case .notCommitted(let current) = selectionOutcome else {
            return XCTFail("Selection drift unexpectedly committed")
        }
        XCTAssertEqual(current.selection.byteRange, 1..<1)
    }

    func testNoOpSelectionPreservesRevision() async throws {
        let executor = executorFor([0x01], selection: 0..<0)
        let before = await executor.snapshot(of: .left)
        let receipt = try await executor.select(
            .set(BinaryHexSelection(byteRange: 0..<0)),
            for: .left
        )
        XCTAssertEqual(receipt.mutationCount, 0)
        XCTAssertEqual(receipt.committedPane.version.revision, before?.version.revision)
        XCTAssertEqual(receipt.committedPane, before)
    }

    func testPlanIsPureAndMatchingTransactionCommits() async throws {
        let executor = executorFor([0x01, 0x02], selection: 0..<0)
        let before = await executor.snapshot(of: .left)
        let plan = try await executor.plan(
            .edit(.insert(payload: .bytes(Data([0xFF])), target: .byteOffset(0))),
            for: .left
        )
        let unmoved = await executor.snapshot(of: .left)
        XCTAssertEqual(unmoved, before)

        let outcome = try await executor.compareAndExecute(plan.transaction)
        guard case .committed(let receipt) = outcome else {
            return XCTFail("Matching transaction did not commit")
        }
        XCTAssertEqual(receipt.committedPane.data, Data([0xFF, 0x01, 0x02]))
        XCTAssertEqual(receipt.committedPane.version.revision, (before?.version.revision ?? 0) + 1)
        XCTAssertEqual(receipt.fingerprint, plan.fingerprint)
        XCTAssertEqual(receipt.sourceVersion, plan.sourcePane.version)
        XCTAssertEqual(receipt.mutationCount, plan.mutations.count)
        XCTAssertEqual(receipt.workUnitsConsumed, plan.workUnitsConsumed)
    }

    func testLimitsAreEnforced() async throws {
        let executor = executorFor([0x01, 0x02], selection: 0..<0)
        await assertAsyncPolicyError(.payloadTooLarge(maximumBytes: 1)) {
            try await executor.insert(
                .bytes(Data([0xAA, 0xBB])),
                at: .byteOffset(0),
                for: .left,
                limits: BinaryHexPolicyLimits(maximumPayloadBytes: 1)
            )
        }
        await assertAsyncPolicyError(.outputTooLarge(maximumBytes: 2)) {
            try await executor.insert(
                .bytes(Data([0xAA])),
                at: .byteOffset(0),
                for: .left,
                limits: BinaryHexPolicyLimits(maximumOutputBytes: 2)
            )
        }
        await assertAsyncPolicyError(.patternTooLarge(maximumBytes: 1)) {
            try await executor.find(
                BinaryHexFindIntent(pattern: .bytes(Data([0x01, 0x02]))),
                for: .left,
                limits: BinaryHexPolicyLimits(maximumPatternBytes: 1)
            )
        }
        await assertAsyncPolicyError(.invalidLimits) {
            try await executor.status(
                for: .left,
                limits: BinaryHexPolicyLimits(cancellationCheckInterval: 0)
            )
        }
        let live = await executor.snapshot(of: .left)
        XCTAssertEqual(live?.data, Data([0x01, 0x02]))
    }

    func testPreCancelledExecutionThrowsBeforeCommit() async throws {
        let source = pane([0x01, 0x02], selection: 0..<0)
        let executor = BinaryHexEditExecutor(panes: [.left: source])
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await executor.insert(
                .bytes(Data([0xFF])),
                at: .byteOffset(0),
                for: .left
            )
        }
        do {
            _ = try await task.value
            XCTFail("Pre-cancelled execution unexpectedly succeeded")
        } catch let error as BinaryHexPolicyError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let live = await executor.snapshot(of: .left)
        XCTAssertEqual(live, source)
    }

    func testMissingPaneThrowsInconsistentPlan() async throws {
        let executor = BinaryHexEditExecutor()
        await assertAsyncPolicyError(.inconsistentPlan) {
            try await executor.insert(.bytes(Data([0xFF])), at: .byteOffset(0), for: .left)
        }
        await assertAsyncPolicyError(.inconsistentPlan) {
            try await executor.status(for: .middle)
        }
    }

    func testDisplaySettingsUpdateCommitsWithoutTouchingBytes() async throws {
        let executor = executorFor([0x41, 0x42], selection: 0..<0)
        let updated = BinaryHexDisplaySettings(
            bytesPerRow: 8,
            byteGroupSize: 2,
            characterSet: .utf8,
            offsetRadix: .decimal,
            usesUppercaseHex: false,
            showsOffsetColumn: false,
            showsCharacterColumn: true,
            editMode: .insert
        )
        let receipt = try await executor.updateDisplaySettings(updated, for: .left)
        XCTAssertEqual(receipt.committedPane.displaySettings, updated)
        XCTAssertEqual(receipt.committedPane.data, Data([0x41, 0x42]))
        XCTAssertEqual(receipt.committedPane.version.revision, 2)
    }

    func testSetPaneRoundTripsSnapshot() async throws {
        let executor = BinaryHexEditExecutor()
        let snapshot = pane([0xDE, 0xAD], selection: 2..<2)
        await executor.setPane(snapshot)
        let left = await executor.snapshot(of: .left)
        let right = await executor.snapshot(of: .right)
        XCTAssertEqual(left, snapshot)
        XCTAssertNil(right)
    }

    // MARK: - Helpers

    private func executorFor(
        _ bytes: [UInt8],
        persisted: [UInt8]? = nil,
        selection: Range<Int>,
        settings: BinaryHexDisplaySettings = .default,
        isReadOnly: Bool = false,
        pane: BinaryHexPane = .left
    ) -> BinaryHexEditExecutor {
        BinaryHexEditExecutor(
            panes: [
                pane: self.pane(
                    bytes,
                    persisted: persisted,
                    selection: selection,
                    settings: settings,
                    isReadOnly: isReadOnly,
                    pane: pane
                )
            ]
        )
    }

    private func pane(
        _ bytes: [UInt8],
        persisted: [UInt8]? = nil,
        selection: Range<Int>,
        settings: BinaryHexDisplaySettings = .default,
        isReadOnly: Bool = false,
        pane: BinaryHexPane = .left,
        revision: UInt64 = 1
    ) -> BinaryHexPaneSnapshot {
        let data = Data(bytes)
        let persistedData = Data(persisted ?? bytes)
        return BinaryHexPaneSnapshot(
            pane: pane,
            version: BinaryHexContentVersion(identity: identity, revision: revision),
            data: data,
            persistedData: persistedData,
            selection: BinaryHexSelection(byteRange: selection),
            displaySettings: settings,
            isReadOnly: isReadOnly,
            isDirty: data != persistedData
        )
    }

    private func display(
        characterSet: BinaryHexCharacterSet
    ) -> BinaryHexDisplaySettings {
        BinaryHexDisplaySettings(
            bytesPerRow: 16,
            byteGroupSize: 1,
            characterSet: characterSet,
            offsetRadix: .hexadecimal,
            usesUppercaseHex: true,
            showsOffsetColumn: true,
            showsCharacterColumn: true,
            editMode: .overwrite
        )
    }

    private func assertAsyncPolicyError<T>(
        _ expected: BinaryHexPolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as BinaryHexPolicyError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
