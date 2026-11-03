import Foundation
import XCTest

@testable import MacMergeCore

final class ThreePaneSaveMiddleAdoptionTests: XCTestCase {
    private typealias Adoption = ThreePaneSaveMiddleAdoption

    func testAvailabilityCoversLoadedUntitledReadOnlyAndUnloaded() {
        var states = cleanLoadedStates()
        states[.middle] = .unloaded
        XCTAssertEqual(
            Adoption.availability(for: .saveMiddle, in: snapshot(states: states)),
            .disabled(.paneNotLoaded)
        )
        XCTAssertEqual(
            Adoption.availability(for: .saveAsMiddle, in: snapshot(states: states)),
            .disabled(.paneNotLoaded)
        )

        states[.middle] = loadedState(dirty: true)
        XCTAssertEqual(Adoption.availability(for: .saveMiddle, in: snapshot(states: states)), .enabled)
        XCTAssertEqual(Adoption.availability(for: .saveAsMiddle, in: snapshot(states: states)), .enabled)

        states[.middle] = loadedState(dirty: false)
        XCTAssertEqual(
            Adoption.availability(for: .saveMiddle, in: snapshot(states: states)),
            .disabled(.paneNotDirty)
        )
        XCTAssertEqual(Adoption.availability(for: .saveAsMiddle, in: snapshot(states: states)), .enabled)

        states[.middle] = loadedState(dirty: true, readOnly: true)
        XCTAssertEqual(
            Adoption.availability(for: .saveMiddle, in: snapshot(states: states)),
            .disabled(.paneReadOnly)
        )
        XCTAssertEqual(Adoption.availability(for: .saveAsMiddle, in: snapshot(states: states)), .enabled)

        states[.middle] = untitledState(dirty: true)
        XCTAssertEqual(Adoption.availability(for: .saveMiddle, in: snapshot(states: states)), .enabled)

        states[.middle] = untitledState(dirty: false)
        XCTAssertEqual(Adoption.availability(for: .saveMiddle, in: snapshot(states: states)), .enabled)

        states[.middle] = untitledState(dirty: true, readOnly: true)
        XCTAssertEqual(
            Adoption.availability(for: .saveMiddle, in: snapshot(states: states)),
            .disabled(.paneReadOnly)
        )
        XCTAssertEqual(Adoption.availability(for: .saveAsMiddle, in: snapshot(states: states)), .enabled)
    }

    func testSnapshotBindsMiddleContentSourceFileIdentityRevisionEncodingBOM() throws {
        let content = contentRevision(encoding: .utf16LittleEndian, hasBOM: true)
        let binding = fileBinding()
        let identity = snapshotIdentity(generation: 7)
        let snap = snapshot(
            identity: identity,
            middle: .loaded(content: content, file: binding)
        )

        XCTAssertEqual(snap.middleContent, content)
        XCTAssertEqual(snap.middleSourceFile, binding)
        XCTAssertEqual(snap.panes.count, 3)

        let routed = try Adoption.planSaveMiddle(snap)
        XCTAssertEqual(routed.expectedIdentity, identity)
        XCTAssertEqual(routed.command, .saveMiddle)
        let operation = try XCTUnwrap(routed.plan.operations.first)
        XCTAssertEqual(operation.side, .middle)
        XCTAssertEqual(operation.source, content)
        XCTAssertEqual(operation.preservesEncoding, content.encoding)
        XCTAssertTrue(operation.preservesEncoding.hasByteOrderMark)
        XCTAssertEqual(operation.preservesReadOnlyState, content.isReadOnly)
        XCTAssertEqual(operation.executorContract, .required)
    }

    func testSnapshotAccessorsAreNilForUntitledAndUnloaded() {
        var states = cleanLoadedStates()
        states[.middle] = untitledState(dirty: true)
        XCTAssertNotNil(snapshot(states: states).middleContent)
        XCTAssertNil(snapshot(states: states).middleSourceFile)

        states[.middle] = .unloaded
        XCTAssertNil(snapshot(states: states).middleContent)
        XCTAssertNil(snapshot(states: states).middleSourceFile)
    }

    func testPlanSaveMiddleRoutesInPlaceAndSaveAsPreservesFullRevisionCAS() throws {
        let inPlace = try Adoption.planSaveMiddle(snapshot(middle: loadedState(dirty: true)))
        let inPlaceOperation = try XCTUnwrap(inPlace.plan.operations.first)
        XCTAssertEqual(inPlaceOperation.kind, .saveInPlace)
        XCTAssertEqual(inPlaceOperation.source, loadedState(dirty: true).content)
        XCTAssertEqual(inPlaceOperation.destination.state, .existing(fileBinding().revision))

        let untitled = untitledState(dirty: true)
        let vacant = destination()
        let asNew = try Adoption.planSaveAsMiddle(snapshot(middle: untitled), destination: vacant)
        XCTAssertEqual(asNew.command, .saveAsMiddle)
        XCTAssertEqual(asNew.plan.operations.first?.kind, .saveAsNewFile)
        XCTAssertEqual(asNew.plan.operations.first?.destination, vacant.identity)

        let exact = fileRevision(fileID: 42_424, byteCount: 1_234, contentHashByte: 0xA1)
        let replacement = destination(state: .existing(exact))
        let asReplacement = try Adoption.planSaveAsMiddle(
            snapshot(middle: loadedState(dirty: false)),
            destination: replacement
        )
        XCTAssertEqual(asReplacement.plan.operations.first?.kind, .saveAsReplacingFile)
        XCTAssertEqual(asReplacement.plan.operations.first?.destination.state, .existing(exact))
    }

    func testWrongSideAndMissingOrUnexpectedDestinationsRejected() {
        assertPlanningError(.missingDestination(.middle)) {
            try Adoption.planSaveMiddle(self.snapshot(middle: self.untitledState(dirty: true)))
        }
        assertPlanningError(.unexpectedDestination(.middle)) {
            try Adoption.planSaveMiddle(
                self.snapshot(middle: self.loadedState(dirty: true)),
                destination: self.destination()
            )
        }
        assertPlanningError(.wrongDestinationSide(expected: .middle, actual: .left)) {
            try Adoption.planSaveMiddle(
                self.snapshot(middle: self.untitledState(dirty: true)),
                destination: self.destination(side: .left)
            )
        }
        assertPlanningError(.wrongDestinationSide(expected: .middle, actual: .right)) {
            try Adoption.planSaveAsMiddle(
                self.snapshot(middle: self.untitledState(dirty: true)),
                destination: self.destination(side: .right)
            )
        }
        assertPlanningError(.paneReadOnly(.middle)) {
            try Adoption.planSaveMiddle(self.snapshot(middle: self.loadedState(dirty: true, readOnly: true)))
        }
    }

    func testAliasAndCollisionRejected() {
        assertPlanningError(.aliasedPath(side: .middle, kind: .symbolicLink)) {
            try Adoption.planSaveMiddle(
                self.snapshot(middle: self.loadedState(dirty: true, resolvedPathKind: .symbolicLink))
            )
        }
        assertPlanningError(.aliasedPath(side: .middle, kind: .finderAlias)) {
            try Adoption.planSaveAsMiddle(
                self.snapshot(middle: self.untitledState(dirty: true)),
                destination: self.destination(resolvedPathKind: .finderAlias)
            )
        }

        var states = cleanLoadedStates()
        states[.middle] = untitledState(dirty: true)
        guard case .loaded(_, let leftBinding) = states[.left] else {
            return XCTFail("Expected loaded left fixture")
        }
        let aliasing = ThreePaneSaveDestination(
            side: .middle,
            identity: ThreePaneSaveDestinationIdentity(
                canonicalURL: leftBinding.revision.identity.canonicalURL,
                parentIdentity: leftBinding.parentIdentity,
                canonicalLeafIdentity: leftBinding.canonicalLeafIdentity,
                state: .existing(leftBinding.revision)
            )
        )
        assertPlanningError(.destinationAliasesPane(destination: .middle, pane: .left)) {
            try Adoption.planSaveAsMiddle(self.snapshot(states: states), destination: aliasing)
        }

        var collision = cleanLoadedStates()
        collision[.middle] = loadedState(dirty: true, fileID: fileID(for: .left))
        assertPlanningError(.paneFileCollision(first: .left, second: .middle)) {
            try Adoption.planSaveMiddle(self.snapshot(states: collision))
        }
    }

    func testExactlyOneMiddleOperationBound() throws {
        XCTAssertEqual(Adoption.maximumMiddleOperations, 1)

        let inPlace = try Adoption.planSaveMiddle(snapshot(middle: loadedState(dirty: true)))
        XCTAssertEqual(inPlace.plan.operations.count, Adoption.maximumMiddleOperations)
        let asNew = try Adoption.planSaveAsMiddle(
            snapshot(middle: untitledState(dirty: true)),
            destination: destination()
        )
        XCTAssertEqual(asNew.plan.operations.count, Adoption.maximumMiddleOperations)

        let countError = Adoption.AdoptionError.unexpectedOperationCount(2)
        XCTAssertTrue(countError.errorDescription?.contains("exactly one") ?? false)
        XCTAssertNotNil(Adoption.AdoptionError.staleSnapshot(
            expected: snapshotIdentity(generation: 1),
            actual: snapshotIdentity(generation: 2)
        ).errorDescription)
        XCTAssertNotNil(Adoption.AdoptionError.executorContractMismatch(.middle).errorDescription)
    }

    func testCancellationMappingForPlanningAndReceipts() throws {
        assertPlanningError(.cancelled) {
            try Adoption.planSaveMiddle(
                self.snapshot(middle: self.loadedState(dirty: true)),
                cancellationCheck: { throw BoomError() }
            )
        }
        assertPlanningError(.cancelled) {
            try Adoption.planSaveAsMiddle(
                self.snapshot(middle: self.untitledState(dirty: true)),
                destination: self.destination(),
                cancellationCheck: { throw BoomError() }
            )
        }

        let routed = try Adoption.planSaveMiddle(snapshot(middle: loadedState(dirty: true)))
        XCTAssertThrowsError(try Adoption.validateReceipts(
            routed,
            currentSnapshot: snapshot(
                identity: routed.expectedIdentity,
                middle: loadedState(dirty: true)
            ),
            receipts: [],
            cancellationCheck: { throw BoomError() }
        )) { error in
            XCTAssertTrue(error is BoomError, "validateReceipts must propagate caller errors, got \(error)")
        }
    }

    func testStaleSnapshotRejectedBeforeReceiptChecks() throws {
        let routed = try Adoption.planSaveMiddle(snapshot(middle: loadedState(dirty: true)))
        let stale = snapshot(
            identity: snapshotIdentity(generation: routed.expectedIdentity.generation + 1),
            middle: loadedState(dirty: true)
        )
        do {
            _ = try Adoption.validateReceipts(routed, currentSnapshot: stale, receipts: [])
            XCTFail("Expected staleSnapshot")
        } catch let error as Adoption.AdoptionError {
            XCTAssertEqual(error, .staleSnapshot(expected: routed.expectedIdentity, actual: stale.identity))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReceiptValidationDelegatesToPlan() throws {
        let routed = try Adoption.planSaveMiddle(snapshot(middle: loadedState(dirty: true)))
        let operation = try XCTUnwrap(routed.plan.operations.first)
        let current = snapshot(identity: routed.expectedIdentity, middle: loadedState(dirty: true))

        let execution = try Adoption.validateReceipts(
            routed,
            currentSnapshot: current,
            receipts: [ThreePaneSaveOperationReceipt(
                operation: operation,
                outcome: .committed(commitReceipt(for: operation))
            )]
        )
        XCTAssertEqual(execution.committedSides, [.middle])
        XCTAssertFalse(execution.hasCommitUncertainty)

        assertReceiptError(.receiptCountMismatch(expected: 1, actual: 0)) {
            try Adoption.validateReceipts(routed, currentSnapshot: current, receipts: [])
        }
        assertReceiptError(.committedPayloadMismatch(.middle)) {
            try Adoption.validateReceipts(
                routed,
                currentSnapshot: current,
                receipts: [ThreePaneSaveOperationReceipt(
                    operation: operation,
                    outcome: .committed(self.commitReceipt(
                        for: operation,
                        byteCount: operation.source.encodedByteCount + 1
                    ))
                )]
            )
        }
    }

    // MARK: - Fixtures

    private func snapshotIdentity(generation: UInt64) -> Adoption.SnapshotIdentity {
        Adoption.SnapshotIdentity(
            lineage: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            generation: generation
        )
    }

    private func snapshot(
        identity: Adoption.SnapshotIdentity? = nil,
        states: [ThreePaneSaveSide: ThreePaneSavePaneState]? = nil,
        middle: ThreePaneSavePaneState? = nil
    ) -> Adoption.Snapshot {
        var resolved = states ?? cleanLoadedStates()
        if let middle { resolved[.middle] = middle }
        return Adoption.Snapshot(
            identity: identity ?? snapshotIdentity(generation: 1),
            left: resolved[.left]!,
            middle: resolved[.middle]!,
            right: resolved[.right]!
        )
    }

    private func cleanLoadedStates() -> [ThreePaneSaveSide: ThreePaneSavePaneState] {
        Dictionary(uniqueKeysWithValues: ThreePaneSaveSide.allCases.map { ($0, loadedState(side: $0, dirty: false)) })
    }

    private func contentRevision(
        dirty: Bool = true,
        readOnly: Bool = false,
        byteCount: UInt64 = 4,
        hashByte: UInt8 = 0xD1,
        encoding: ThreePaneSaveTextEncoding = .utf8,
        hasBOM: Bool = false
    ) -> ThreePaneSaveContentRevision {
        ThreePaneSaveContentRevision(
            documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            revision: 1_001,
            isDirty: dirty,
            isReadOnly: readOnly,
            encodedByteCount: byteCount,
            encodedContentSHA256: [UInt8](repeating: hashByte, count: 32),
            encoding: ThreePaneSaveEncodingMetadata(encoding: encoding, hasByteOrderMark: hasBOM)
        )
    }

    private func untitledState(dirty: Bool, readOnly: Bool = false) -> ThreePaneSavePaneState {
        .untitled(contentRevision(dirty: dirty, readOnly: readOnly))
    }

    private func loadedState(
        side: ThreePaneSaveSide = .middle,
        dirty: Bool,
        readOnly: Bool = false,
        fileID: UInt64? = nil,
        resolvedPathKind: ThreePaneSaveResolvedPathKind = .direct
    ) -> ThreePaneSavePaneState {
        let binding = fileBinding(side: side, fileID: fileID, resolvedPathKind: resolvedPathKind)
        let content = ThreePaneSaveContentRevision(
            documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            revision: 1_001,
            isDirty: dirty,
            isReadOnly: readOnly,
            encodedByteCount: binding.revision.byteCount,
            encodedContentSHA256: dirty ? [UInt8](repeating: 0xD1, count: 32) : binding.revision.contentSHA256,
            encoding: ThreePaneSaveEncodingMetadata(encoding: ThreePaneSaveTextEncoding.utf8, hasByteOrderMark: false)
        )
        return .loaded(content: content, file: binding)
    }

    private func fileBinding(
        side: ThreePaneSaveSide = .middle,
        fileID: UInt64? = nil,
        resolvedPathKind: ThreePaneSaveResolvedPathKind = .direct
    ) -> ThreePaneSaveFileBinding {
        let leaf = "\(side.rawValue).txt"
        let url = URL(fileURLWithPath: "/tmp/macmerge-three-pane-save/source/\(leaf)", isDirectory: false)
        return ThreePaneSaveFileBinding(
            revision: fileRevision(url: url, fileID: fileID ?? self.fileID(for: side)),
            parentIdentity: ThreePaneSaveCanonicalFileIdentity(
                canonicalURL: URL(fileURLWithPath: "/tmp/macmerge-three-pane-save/source", isDirectory: true),
                kind: .directory,
                volumeID: 1,
                fileID: 500,
                generation: 1
            ),
            canonicalLeafIdentity: leaf,
            resolvedPathKind: resolvedPathKind
        )
    }

    private func destination(
        side: ThreePaneSaveSide = .middle,
        resolvedPathKind: ThreePaneSaveResolvedPathKind = .direct,
        state: ThreePaneSaveDestinationState = .vacant
    ) -> ThreePaneSaveDestination {
        let name = "\(side.rawValue).txt"
        return ThreePaneSaveDestination(
            side: side,
            identity: ThreePaneSaveDestinationIdentity(
                canonicalURL: URL(
                    fileURLWithPath: "/tmp/macmerge-three-pane-save/dest/\(name)",
                    isDirectory: false
                ),
                parentIdentity: ThreePaneSaveCanonicalFileIdentity(
                    canonicalURL: URL(fileURLWithPath: "/tmp/macmerge-three-pane-save/dest", isDirectory: true),
                    kind: .directory,
                    volumeID: 1,
                    fileID: 501,
                    generation: 1
                ),
                canonicalLeafIdentity: name,
                resolvedPathKind: resolvedPathKind,
                state: state
            )
        )
    }

    private func fileRevision(
        url: URL? = nil,
        fileID: UInt64,
        byteCount: UInt64 = 4,
        contentHashByte: UInt8 = 0x44
    ) -> ThreePaneSaveFileRevision {
        ThreePaneSaveFileRevision(
            identity: ThreePaneSaveCanonicalFileIdentity(
                canonicalURL: url ?? URL(
                    fileURLWithPath: "/tmp/macmerge-three-pane-save/dest/middle.txt",
                    isDirectory: false
                ),
                kind: .regularFile,
                volumeID: 1,
                fileID: fileID,
                generation: 1
            ),
            byteCount: byteCount,
            metadataByteCount: 2,
            modificationTimeSeconds: 10,
            modificationTimeNanoseconds: 20,
            statusChangeTimeSeconds: 30,
            statusChangeTimeNanoseconds: 40,
            contentSHA256: [UInt8](repeating: contentHashByte, count: 32),
            metadataSHA256: [UInt8](repeating: 0x55, count: 32)
        )
    }

    private func commitReceipt(
        for operation: ThreePaneSaveOperation,
        byteCount: UInt64? = nil
    ) -> ThreePaneSaveCommitReceipt {
        let revision = ThreePaneSaveFileRevision(
            identity: ThreePaneSaveCanonicalFileIdentity(
                canonicalURL: operation.destination.canonicalURL,
                kind: .regularFile,
                volumeID: 1,
                fileID: 20_001,
                generation: 1
            ),
            byteCount: byteCount ?? operation.source.encodedByteCount,
            metadataByteCount: 0,
            modificationTimeSeconds: 100,
            modificationTimeNanoseconds: 200,
            statusChangeTimeSeconds: 300,
            statusChangeTimeNanoseconds: 400,
            contentSHA256: operation.source.encodedContentSHA256,
            metadataSHA256: [UInt8](repeating: 0xCC, count: 32)
        )
        return ThreePaneSaveCommitReceipt(
            committedParentIdentity: operation.destination.parentIdentity,
            committedRevision: revision,
            encoding: operation.preservesEncoding,
            paneReadOnly: operation.preservesReadOnlyState
        )
    }

    private func fileID(for side: ThreePaneSaveSide) -> UInt64 {
        switch side {
        case .left: 1_000
        case .middle: 1_001
        case .right: 1_002
        }
    }

    private func assertPlanningError<T>(
        _ expected: ThreePaneSavePlanningError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ThreePaneSavePlanningError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertReceiptError<T>(
        _ expected: ThreePaneSaveReceiptError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ThreePaneSaveReceiptError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private struct BoomError: Error {}
