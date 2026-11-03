import Foundation
import MacMergeCore
import XCTest

final class ComparedFileNavigationWiringTests: XCTestCase {
    typealias Wiring = ComparedFileNavigationWiring

    func testMakeSnapshotDelegatesToPlanner() throws {
        let rows = [pair("a.txt"), pair("b.txt")]
        let filter = DirectoryResultFilter(
            statuses: [.different],
            pathQuery: "a",
            kinds: [.file],
            hidden: .include
        )
        let sorts = [DirectoryResultSortDescriptor(key: .path, order: .descending)]
        let limits = ComparedFileNavigationLimits(maximumItemCount: 100, maximumSortDescriptorCount: 8)
        let openCapabilities: Set<ComparedFileNavigationOpenCapability> = [.differentRegularFilePair]
        let request = makeRequest(
            rows,
            selectedIDs: [rows[0].id],
            cursorResultID: rows[1].id,
            filter: filter,
            sortDescriptors: sorts,
            openCapabilities: openCapabilities,
            limits: limits
        )
        let wired = try Wiring.makeSnapshot(request)
        let direct = try ComparedFileNavigationSnapshot(
            identity: request.identity,
            revision: request.revision,
            generation: request.generation,
            results: request.results,
            itemBindings: request.itemBindings,
            cursorResultID: request.cursorResultID,
            authorities: request.authorities,
            openCapabilities: request.openCapabilities,
            limits: request.limits
        )
        XCTAssertEqual(wired.items, direct.items)
        XCTAssertEqual(wired.reference, direct.reference)
        XCTAssertEqual(wired.authorities, direct.authorities)
        XCTAssertEqual(wired.filter, direct.filter)
        XCTAssertEqual(wired.sortDescriptors, direct.sortDescriptors)
        XCTAssertEqual(wired.selectedItemIdentities, direct.selectedItemIdentities)
        XCTAssertEqual(wired.cursorItemIdentity, direct.cursorItemIdentity)
        XCTAssertEqual(wired.openCapabilities, direct.openCapabilities)
        XCTAssertEqual(wired.limits, direct.limits)
    }

    func testPlanMatchesPlannerDirectlyForEveryCommand() throws {
        let rows = [pair("a.txt"), pair("b.txt"), pair("c.txt")]
        let request = makeRequest(rows, selectedIDs: [rows[1].id])
        let snapshot = try Wiring.makeSnapshot(request)
        for command in ComparedFileNavigationCommand.allCases {
            let wired = try Wiring.plan(command, request: request)
            let direct = try ComparedFileNavigationPlanner.plan(command, in: snapshot)
            XCTAssertEqual(wired.command, direct.command)
            XCTAssertEqual(wired.commandState, direct.commandState)
            XCTAssertEqual(wired.targetItemIdentity, direct.targetItemIdentity)
            XCTAssertEqual(wired.plannedWorkUnits, direct.plannedWorkUnits)
            assertEqualOpenPairRequests(wired.openPairRequest, direct.openPairRequest)
        }
    }

    func testCommandStatesAndResolveAllDelegate() throws {
        let rows = [pair("a.txt"), pair("b.txt")]
        let request = makeRequest(rows, selectedIDs: [rows[0].id])
        let snapshot = try Wiring.makeSnapshot(request)
        XCTAssertEqual(try Wiring.commandStates(request: request), try snapshot.commandStates())
        let wiredAll = try Wiring.resolveAll(request: request)
        let directAll = try ComparedFileNavigationPlanner.resolveAll(in: snapshot)
        XCTAssertEqual(wiredAll.map(\.command), directAll.map(\.command))
        XCTAssertEqual(wiredAll.map(\.targetItemIdentity), directAll.map(\.targetItemIdentity))
        XCTAssertEqual(wiredAll.map(\.commandState), directAll.map(\.commandState))
        XCTAssertEqual(wiredAll.map(\.plannedWorkUnits), directAll.map(\.plannedWorkUnits))
        XCTAssertEqual(wiredAll.count, directAll.count)
        for (wired, direct) in zip(wiredAll, directAll) {
            assertEqualOpenPairRequests(wired.openPairRequest, direct.openPairRequest)
        }
    }

    func testValidateAndIsCurrentDelegateAndStaleFailsClosed() throws {
        let rows = [pair("a.txt"), pair("b.txt")]
        let request = makeRequest(rows, selectedIDs: [rows[0].id])
        let snapshot = try Wiring.makeSnapshot(request)
        let plan = try Wiring.plan(.next, request: request)
        XCTAssertNoThrow(try Wiring.validate(plan, against: snapshot))
        XCTAssertTrue(try Wiring.isCurrent(plan, for: snapshot))

        let staleRequest = makeRequest(rows, selectedIDs: [rows[0].id], generation: 21)
        let stale = try Wiring.makeSnapshot(staleRequest)
        XCTAssertFalse(try Wiring.isCurrent(plan, for: stale))
        XCTAssertThrowsError(try Wiring.validate(plan, against: stale)) { error in
            XCTAssertEqual(
                error as? ComparedFileNavigationError,
                .staleGeneration(expected: request.generation, actual: staleRequest.generation)
            )
        }
    }

    func testRefreshedBindingsCarriesEachIdentityOnceInResultsOrder() throws {
        let kept = pair("kept.txt")
        let addedFirst = pair("added-first.txt")
        let addedLast = pair("added-last.txt")
        let previous = bindings(for: [kept])
        let refreshed = try Wiring.refreshedBindings(
            previous: previous,
            results: [addedFirst, kept, addedLast]
        )
        XCTAssertEqual(refreshed.bindings, previous)
        XCTAssertEqual(refreshed.addedResultIDs, [addedFirst.id, addedLast.id])

        let repeated = try Wiring.refreshedBindings(previous: previous, results: [kept, kept])
        XCTAssertEqual(repeated.bindings, previous)
        XCTAssertEqual(repeated.addedResultIDs, [kept.id])
    }

    func testRefreshedBindingsDuplicateExactMatchFailsClosed() throws {
        let row = pair("dup.txt")
        let previous = [
            ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: row.id),
            ComparedFileNavigationItemBinding(identity: itemIdentity(2), resultID: row.id)
        ]
        XCTAssertThrowsError(try Wiring.refreshedBindings(previous: previous, results: [row])) {
            error in
            XCTAssertEqual(error as? ComparedFileNavigationError, .duplicateResultID(row.id))
        }
    }

    func testRefreshedBindingsRequiresByteExactIDs() throws {
        let alias = DirectoryResult.ID(leftRelativePath: "same.txt", rightRelativePath: nil)
        let paired = pair("same.txt")
        let aliasBinding = ComparedFileNavigationItemBinding(
            identity: itemIdentity(1),
            resultID: alias
        )
        let aliasRefreshed = try Wiring.refreshedBindings(
            previous: [aliasBinding],
            results: [paired]
        )
        XCTAssertTrue(aliasRefreshed.bindings.isEmpty)
        XCTAssertEqual(aliasRefreshed.addedResultIDs, [paired.id])

        let nfc = pair("caf\u{E9}.txt")
        let nfd = DirectoryResult(
            left: metadata("cafe\u{301}.txt"),
            right: metadata("cafe\u{301}.txt"),
            status: .different
        )
        XCTAssertEqual(nfc.id.relativePath, nfd.id.relativePath)
        let nfcRefreshed = try Wiring.refreshedBindings(
            previous: bindings(for: [nfc]),
            results: [nfd]
        )
        XCTAssertTrue(nfcRefreshed.bindings.isEmpty)
        XCTAssertEqual(nfcRefreshed.addedResultIDs, [nfd.id])
    }

    func testFallbackOrderIsSelectionThenCursorThenBoundary() throws {
        let first = pair("a.txt")
        let selected = pair("b.txt")
        let cursor = pair("c.txt")
        let last = pair("d.txt")
        let rows = [first, selected, cursor, last]
        let rowBindings = bindings(for: rows)
        let selectedIdentity = identity(for: selected, in: rowBindings)
        let cursorIdentity = identity(for: cursor, in: rowBindings)
        let firstIdentity = identity(for: first, in: rowBindings)

        let selectionPlan = try Wiring.plan(
            .previous,
            request: makeRequest(
                rows,
                bindings: rowBindings,
                selectedIDs: [selected.id],
                cursorResultID: cursor.id
            )
        )
        XCTAssertEqual(selectionPlan.targetItemIdentity, firstIdentity)
        XCTAssertEqual(
            selectionPlan.commandState.availabilityReason,
            .enabled(
                ComparedFileNavigationEnabledReason(
                    target: firstIdentity,
                    origin: .selection(selectedIdentity)
                )
            )
        )

        let filtered = pair("z-filtered.txt", status: .identical)
        let fallbackRows = rows + [filtered]
        let fallbackBindings = bindings(for: fallbackRows)
        let cursorPlan = try Wiring.plan(
            .previous,
            request: makeRequest(
                fallbackRows,
                bindings: fallbackBindings,
                selectedIDs: [filtered.id],
                cursorResultID: cursor.id,
                filter: DirectoryResultFilter(statuses: [.different])
            )
        )
        XCTAssertEqual(cursorPlan.targetItemIdentity, identity(for: selected, in: fallbackBindings))
        XCTAssertEqual(
            cursorPlan.commandState.availabilityReason,
            .enabled(
                ComparedFileNavigationEnabledReason(
                    target: identity(for: selected, in: fallbackBindings),
                    origin: .cursor(cursorIdentity)
                )
            )
        )

        let boundaryPlan = try Wiring.plan(
            .next,
            request: makeRequest(rows, bindings: rowBindings)
        )
        XCTAssertEqual(boundaryPlan.targetItemIdentity, firstIdentity)
        XCTAssertEqual(
            boundaryPlan.commandState.availabilityReason,
            .enabled(
                ComparedFileNavigationEnabledReason(
                    target: firstIdentity,
                    origin: .startBoundary
                )
            )
        )

        let lastIdentity = identity(for: last, in: rowBindings)
        let previousBoundaryPlan = try Wiring.plan(
            .previous,
            request: makeRequest(rows, bindings: rowBindings)
        )
        XCTAssertEqual(previousBoundaryPlan.targetItemIdentity, lastIdentity)
        XCTAssertEqual(
            previousBoundaryPlan.commandState.availabilityReason,
            .enabled(
                ComparedFileNavigationEnabledReason(
                    target: lastIdentity,
                    origin: .endBoundary
                )
            )
        )

        let lastBoundaryPlan = try Wiring.plan(
            .last,
            request: makeRequest(rows, bindings: rowBindings)
        )
        XCTAssertEqual(lastBoundaryPlan.targetItemIdentity, lastIdentity)
        XCTAssertEqual(
            lastBoundaryPlan.commandState.availabilityReason,
            .enabled(
                ComparedFileNavigationEnabledReason(
                    target: lastIdentity,
                    origin: .endBoundary
                )
            )
        )
    }

    func testMissingSidePolicyUsesPresentPathAndSplitCapabilities() throws {
        let cases: [(DirectoryResult, ComparedFileNavigationOpenCapability)] = [
            (oneSided("missing-left.txt", side: .right), .missingLeftRegularFile),
            (oneSided("missing-right.txt", side: .left), .missingRightRegularFile)
        ]
        for (row, capability) in cases {
            let request = makeRequest([row], openCapabilities: [capability])
            let plan = try Wiring.plan(.next, request: request)
            let openRequest = try XCTUnwrap(plan.openPairRequest)
            XCTAssertEqual(openRequest.requiredOpenCapability, capability)
            XCTAssertEqual(openRequest.left.relativePath, row.id.relativePath)
            XCTAssertEqual(openRequest.right.relativePath, row.id.relativePath)
            if row.left == nil {
                XCTAssertEqual(openRequest.left.presence, .missing)
                XCTAssertEqual(
                    openRequest.left.requiredAuthorityCapability,
                    .validateMissingFile
                )
                XCTAssertEqual(openRequest.right.presence, .regularFile)
                XCTAssertEqual(
                    openRequest.right.requiredAuthorityCapability,
                    .readRegularFile
                )
            } else {
                XCTAssertEqual(openRequest.left.presence, .regularFile)
                XCTAssertEqual(
                    openRequest.left.requiredAuthorityCapability,
                    .readRegularFile
                )
                XCTAssertEqual(openRequest.right.presence, .missing)
                XCTAssertEqual(
                    openRequest.right.requiredAuthorityCapability,
                    .validateMissingFile
                )
            }
        }
    }

    func testAuthorityRootMismatchFailsClosedAndMissingAuthorityIsUnavailable() throws {
        let row = pair("pair.txt")
        let rowBindings = bindings(for: [row])
        let mismatched = ComparedFileNavigationRootAuthority(
            identity: authorityIdentity(10),
            side: .left,
            rootURL: URL(string: "file://localhost/left-root")!,
            capabilities: [.readRegularFile, .validateMissingFile]
        )
        XCTAssertThrowsError(
            try Wiring.makeSnapshot(makeRequest([row], bindings: rowBindings, authorities: [mismatched]))
        ) { error in
            XCTAssertEqual(error as? ComparedFileNavigationError, .authorityRootMismatch(.left))
        }

        let snapshot = try Wiring.makeSnapshot(
            makeRequest(
                [row],
                bindings: rowBindings,
                authorities: [],
                openCapabilities: [.differentRegularFilePair]
            )
        )
        XCTAssertEqual(
            snapshot.items[0].availability,
            .unavailable(.missingAuthority(.left))
        )
    }

    func testCustomCancellationCheckCancelsMidBuild() throws {
        let rows = [pair("a.txt"), pair("b.txt")]
        let request = makeRequest(rows)
        XCTAssertThrowsError(
            try Wiring.makeSnapshot(request, cancellationCheck: { throw CancellationError() })
        ) { error in
            XCTAssertEqual(error as? ComparedFileNavigationError, .cancelled)
        }

        let gate = CancellationGate(allowCalls: 1)
        XCTAssertThrowsError(
            try Wiring.plan(.next, request: request, cancellationCheck: { try gate.check() })
        ) { error in
            XCTAssertEqual(error as? ComparedFileNavigationError, .cancelled)
        }
        XCTAssertGreaterThanOrEqual(gate.calls, 2)

        XCTAssertThrowsError(
            try Wiring.refreshedBindings(
                previous: bindings(for: rows),
                results: rows,
                cancellationCheck: { throw CancellationError() }
            )
        ) { error in
            XCTAssertEqual(error as? ComparedFileNavigationError, .cancelled)
        }

        XCTAssertThrowsError(
            try Wiring.commandStates(request: request, cancellationCheck: { throw CancellationError() })
        ) { error in
            XCTAssertEqual(error as? ComparedFileNavigationError, .cancelled)
        }
        XCTAssertThrowsError(
            try Wiring.resolveAll(request: request, cancellationCheck: { throw CancellationError() })
        ) { error in
            XCTAssertEqual(error as? ComparedFileNavigationError, .cancelled)
        }
    }

    func testNonCancellationErrorsPropagateUnmapped() {
        struct Probe: Error {}
        let rows = [pair("a.txt")]
        let request = makeRequest(rows)
        XCTAssertThrowsError(
            try Wiring.makeSnapshot(request, cancellationCheck: { throw Probe() })
        ) { error in
            XCTAssertTrue(error is Probe)
        }
        XCTAssertThrowsError(
            try Wiring.plan(.next, request: request, cancellationCheck: { throw Probe() })
        ) { error in
            XCTAssertTrue(error is Probe)
        }
        XCTAssertThrowsError(
            try Wiring.commandStates(request: request, cancellationCheck: { throw Probe() })
        ) { error in
            XCTAssertTrue(error is Probe)
        }
        XCTAssertThrowsError(
            try Wiring.resolveAll(request: request, cancellationCheck: { throw Probe() })
        ) { error in
            XCTAssertTrue(error is Probe)
        }
    }

    // MARK: - Helpers

    private func assertEqualOpenPairRequests(
        _ left: ComparedFileNavigationOpenPairRequest?,
        _ right: ComparedFileNavigationOpenPairRequest?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let left, let right else {
            XCTAssertNil(left, file: file, line: line)
            XCTAssertNil(right, file: file, line: line)
            return
        }
        XCTAssertEqual(left.expectedFolderResults, right.expectedFolderResults, file: file, line: line)
        XCTAssertEqual(left.itemIdentity, right.itemIdentity, file: file, line: line)
        XCTAssertEqual(left.itemOrdinal, right.itemOrdinal, file: file, line: line)
        XCTAssertTrue(exactIDMatches(left.resultID, right.resultID), file: file, line: line)
        XCTAssertEqual(left.comparisonState, right.comparisonState, file: file, line: line)
        XCTAssertEqual(left.requiredOpenCapability, right.requiredOpenCapability, file: file, line: line)
        XCTAssertEqual(left.left, right.left, file: file, line: line)
        XCTAssertEqual(left.right, right.right, file: file, line: line)
        XCTAssertEqual(left.executorContract, right.executorContract, file: file, line: line)
    }

    private func exactIDMatches(_ left: DirectoryResult.ID, _ right: DirectoryResult.ID) -> Bool {
        exactOptionalPath(left.leftRelativePath, right.leftRelativePath)
            && exactOptionalPath(left.rightRelativePath, right.rightRelativePath)
    }

    private func exactOptionalPath(_ left: String?, _ right: String?) -> Bool {
        switch (left, right) {
        case (nil, nil):
            return true
        case (let left?, let right?):
            return left.utf8.elementsEqual(right.utf8)
        default:
            return false
        }
    }

    private var leftRoot: URL { URL(string: "file:///left-root")! }
    private var rightRoot: URL { URL(string: "file:///right-root")! }

    private func metadata(
        _ path: String,
        kind: DirectoryEntryKind = .file
    ) -> DirectoryEntryMetadata {
        DirectoryEntryMetadata(relativePath: path, kind: kind)
    }

    private func pair(
        _ path: String,
        status: DirectoryComparisonStatus = .different
    ) -> DirectoryResult {
        DirectoryResult(left: metadata(path), right: metadata(path), status: status)
    }

    private enum Side {
        case left
        case right
    }

    private func oneSided(_ path: String, side: Side) -> DirectoryResult {
        let entry = metadata(path)
        return DirectoryResult(
            left: side == .left ? entry : nil,
            right: side == .right ? entry : nil,
            status: side == .left ? .leftOnly : .rightOnly
        )
    }

    private func bindings(
        for rows: [DirectoryResult],
        startingAt first: Int = 1
    ) -> [ComparedFileNavigationItemBinding] {
        rows.enumerated().map { offset, row in
            ComparedFileNavigationItemBinding(
                identity: itemIdentity(first + offset),
                resultID: row.id
            )
        }
    }

    private func identity(
        for row: DirectoryResult,
        in rowBindings: [ComparedFileNavigationItemBinding]
    ) -> ComparedFileNavigationItemIdentity {
        let binding = rowBindings.first {
            exactOptionalPath($0.resultID.leftRelativePath, row.id.leftRelativePath)
                && exactOptionalPath($0.resultID.rightRelativePath, row.id.rightRelativePath)
        }
        guard let binding else {
            XCTFail("Missing exact item binding")
            return itemIdentity(Int.max)
        }
        return binding.identity
    }

    private func makeRequest(
        _ rows: [DirectoryResult],
        bindings suppliedBindings: [ComparedFileNavigationItemBinding]? = nil,
        selectedIDs: Set<DirectoryResult.ID> = [],
        cursorResultID: DirectoryResult.ID? = nil,
        filter: DirectoryResultFilter = DirectoryResultFilter(),
        sortDescriptors: [DirectoryResultSortDescriptor] = [DirectoryResultSortDescriptor(key: .path)],
        authorities: [ComparedFileNavigationRootAuthority]? = nil,
        openCapabilities: Set<ComparedFileNavigationOpenCapability> = Set(
            ComparedFileNavigationOpenCapability.allCases
        ),
        limits: ComparedFileNavigationLimits = .default,
        generation: UInt64 = 20
    ) -> Wiring.SnapshotRequest {
        let rowBindings = suppliedBindings ?? bindings(for: rows)
        let results = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: rows,
            filter: filter,
            sortDescriptors: sortDescriptors,
            selectedIDs: selectedIDs
        )
        return Wiring.SnapshotRequest(
            identity: ComparedFileFolderResultsIdentity(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            ),
            revision: ComparedFileFolderResultsRevision(rawValue: 10),
            generation: ComparedFileFolderResultsGeneration(rawValue: generation),
            results: results,
            itemBindings: rowBindings,
            cursorResultID: cursorResultID,
            authorities: authorities ?? fullAuthorities(),
            openCapabilities: openCapabilities,
            limits: limits
        )
    }

    private func fullAuthorities() -> [ComparedFileNavigationRootAuthority] {
        [
            ComparedFileNavigationRootAuthority(
                identity: authorityIdentity(1),
                side: .left,
                rootURL: leftRoot,
                capabilities: [.readRegularFile, .validateMissingFile]
            ),
            ComparedFileNavigationRootAuthority(
                identity: authorityIdentity(2),
                side: .right,
                rootURL: rightRoot,
                capabilities: [.readRegularFile, .validateMissingFile]
            )
        ]
    }

    private func itemIdentity(_ value: Int) -> ComparedFileNavigationItemIdentity {
        ComparedFileNavigationItemIdentity(rawValue: uuid(value))
    }

    private func authorityIdentity(_ value: Int) -> ComparedFileNavigationAuthorityIdentity {
        ComparedFileNavigationAuthorityIdentity(rawValue: uuid(1_000 + value))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private final class CancellationGate: @unchecked Sendable {
    private(set) var calls = 0
    private let allowCalls: Int

    init(allowCalls: Int) {
        self.allowCalls = allowCalls
    }

    func check() throws {
        calls += 1
        if calls > allowCalls {
            throw CancellationError()
        }
    }
}
