import Foundation
import MacMergeCore
import XCTest

final class ComparedFileNavigationTests: XCTestCase {
    func testCommandsUseStrictSortedNavigableDestinationsFromSelection() throws {
        let first = pair("a.txt")
        let unavailable = pair("b.txt", status: .pending)
        let middle = pair("c.txt")
        let folder = pair("d", kind: .directory)
        let last = pair("e.txt")
        let rows = [last, folder, middle, unavailable, first]
        let bindings = bindings(for: rows)
        let snapshot = try makeSnapshot(
            rows,
            bindings: bindings,
            selectedIDs: [middle.id]
        )

        XCTAssertEqual(snapshot.items.map(\.resultID), [first.id, unavailable.id, middle.id, folder.id, last.id])
        XCTAssertEqual(snapshot.items.map(\.ordinal), [0, 1, 2, 3, 4])
        XCTAssertEqual(snapshot.navigableItems.map(\.resultID), [first.id, middle.id, last.id])

        let states = try snapshot.commandStates()
        let expectations: [ComparedFileNavigationCommand: (ComparedFileNavigationItemIdentity, ComparedFileNavigationOrigin)] = [
            .first: (identity(for: first, in: bindings), .selection(identity(for: middle, in: bindings))),
            .previous: (identity(for: first, in: bindings), .selection(identity(for: middle, in: bindings))),
            .next: (identity(for: last, in: bindings), .selection(identity(for: middle, in: bindings))),
            .last: (identity(for: last, in: bindings), .selection(identity(for: middle, in: bindings)))
        ]
        for command in ComparedFileNavigationCommand.allCases {
            let expected = try XCTUnwrap(expectations[command])
            let state = states[command]
            XCTAssertEqual(state.command, command)
            XCTAssertTrue(state.isEnabled)
            XCTAssertTrue(state.canExecute)
            XCTAssertEqual(state.targetItemIdentity, expected.0)
            XCTAssertEqual(
                state.availabilityReason,
                .enabled(ComparedFileNavigationEnabledReason(target: expected.0, origin: expected.1))
            )
            XCTAssertTrue(try ComparedFileNavigationPlanner.canExecute(command, in: snapshot))
        }
        XCTAssertEqual(
            states.directoryPairNavigationCommandStates,
            DirectoryPairNavigationCommandStates(first: true, previous: true, next: true, last: true)
        )
    }

    func testFirstPreviousNextAndLastNeverWrapAtBoundaries() throws {
        let first = pair("a.txt")
        let last = pair("z.txt")
        let rows = [first, last]
        let bindings = bindings(for: rows)
        let firstIdentity = identity(for: first, in: bindings)
        let lastIdentity = identity(for: last, in: bindings)
        let firstSnapshot = try makeSnapshot(rows, bindings: bindings, selectedIDs: [first.id])
        let lastSnapshot = try makeSnapshot(rows, bindings: bindings, selectedIDs: [last.id])

        assertDisabled(try ComparedFileNavigation.plan(.first, in: firstSnapshot), .alreadyAtFirst(firstIdentity))
        assertDisabled(try ComparedFileNavigation.plan(.previous, in: firstSnapshot), .noPreviousItem)
        assertDisabled(try ComparedFileNavigation.plan(.next, in: lastSnapshot), .noNextItem)
        assertDisabled(try ComparedFileNavigation.plan(.last, in: lastSnapshot), .alreadyAtLast(lastIdentity))

        XCTAssertEqual(try ComparedFileNavigation.plan(.next, in: firstSnapshot).targetItemIdentity, lastIdentity)
        XCTAssertEqual(try ComparedFileNavigation.plan(.previous, in: lastSnapshot).targetItemIdentity, firstIdentity)
    }

    func testCommandsWithoutSelectionOrCursorUseExactBoundaryOrigins() throws {
        let first = pair("a.txt")
        let last = pair("z.txt")
        let rows = [last, first]
        let bindings = bindings(for: rows)
        let snapshot = try makeSnapshot(rows, bindings: bindings)
        let firstIdentity = identity(for: first, in: bindings)
        let lastIdentity = identity(for: last, in: bindings)
        let expectations: [ComparedFileNavigationCommand: (ComparedFileNavigationItemIdentity, ComparedFileNavigationOrigin)] = [
            .first: (firstIdentity, .startBoundary),
            .previous: (lastIdentity, .endBoundary),
            .next: (firstIdentity, .startBoundary),
            .last: (lastIdentity, .endBoundary)
        ]

        for command in ComparedFileNavigationCommand.allCases {
            let expected = try XCTUnwrap(expectations[command])
            let plan = try ComparedFileNavigation.resolve(command, in: snapshot)
            XCTAssertEqual(plan.targetItemIdentity, expected.0)
            XCTAssertEqual(
                plan.commandState.availabilityReason,
                .enabled(ComparedFileNavigationEnabledReason(target: expected.0, origin: expected.1))
            )
        }
    }

    func testVisibleSelectionPrecedesCursorAndFilteredSelectionFallsBackToCursor() throws {
        let first = pair("a-visible.txt")
        let cursor = pair("b-visible.txt")
        let filtered = pair("c-filtered.txt", status: .identical)
        let rows = [first, cursor, filtered]
        let bindings = bindings(for: rows)
        let cursorIdentity = identity(for: cursor, in: bindings)
        let firstIdentity = identity(for: first, in: bindings)

        let selectionSnapshot = try makeSnapshot(
            rows,
            bindings: bindings,
            selectedIDs: [first.id],
            cursorResultID: cursor.id
        )
        let selectedPlan = try ComparedFileNavigation.plan(.next, in: selectionSnapshot)
        XCTAssertEqual(selectedPlan.targetItemIdentity, cursorIdentity)
        XCTAssertEqual(
            selectedPlan.commandState.availabilityReason,
            .enabled(
                ComparedFileNavigationEnabledReason(
                    target: cursorIdentity,
                    origin: .selection(firstIdentity)
                )
            )
        )

        let cursorSnapshot = try makeSnapshot(
            rows,
            bindings: bindings,
            selectedIDs: [filtered.id],
            cursorResultID: cursor.id,
            filter: DirectoryResultFilter(statuses: [.different])
        )
        XCTAssertEqual(cursorSnapshot.selectedItemIdentities, [identity(for: filtered, in: bindings)])
        let cursorPlan = try ComparedFileNavigation.plan(.previous, in: cursorSnapshot)
        XCTAssertEqual(cursorPlan.targetItemIdentity, firstIdentity)
        XCTAssertEqual(
            cursorPlan.commandState.availabilityReason,
            .enabled(
                ComparedFileNavigationEnabledReason(
                    target: firstIdentity,
                    origin: .cursor(cursorIdentity)
                )
            )
        )
    }

    func testSelectionCursorAndBoundaryFallbacksCoverEveryCommandDeterministically() throws {
        let first = pair("a.txt")
        let selected = pair("b.txt")
        let cursor = pair("c.txt")
        let last = pair("d.txt")
        let filtered = pair("e-filtered.txt", status: .identical)
        let rows = [first, selected, cursor, last, filtered]
        let rowBindings = bindings(for: rows)
        let firstIdentity = identity(for: first, in: rowBindings)
        let selectedIdentity = identity(for: selected, in: rowBindings)
        let cursorIdentity = identity(for: cursor, in: rowBindings)
        let lastIdentity = identity(for: last, in: rowBindings)
        let contexts:
            [(
                snapshot: ComparedFileNavigationSnapshot,
                origin: ComparedFileNavigationOrigin?,
                targets: [ComparedFileNavigationCommand: ComparedFileNavigationItemIdentity?]
            )] = try [
                (
                    makeSnapshot(
                        rows,
                        bindings: rowBindings,
                        selectedIDs: [selected.id],
                        cursorResultID: cursor.id,
                        filter: DirectoryResultFilter(statuses: [.different])
                    ),
                    .selection(selectedIdentity),
                    [.first: firstIdentity, .previous: firstIdentity, .next: cursorIdentity, .last: lastIdentity]
                ),
                (
                    makeSnapshot(
                        rows,
                        bindings: rowBindings,
                        selectedIDs: [filtered.id],
                        cursorResultID: cursor.id,
                        filter: DirectoryResultFilter(statuses: [.different])
                    ),
                    .cursor(cursorIdentity),
                    [.first: firstIdentity, .previous: selectedIdentity, .next: lastIdentity, .last: lastIdentity]
                ),
                (
                    makeSnapshot(
                        rows,
                        bindings: rowBindings,
                        selectedIDs: [filtered.id],
                        filter: DirectoryResultFilter(statuses: [.different])
                    ),
                    nil,
                    [.first: firstIdentity, .previous: lastIdentity, .next: firstIdentity, .last: lastIdentity]
                )
            ]

        for context in contexts {
            for command in ComparedFileNavigationCommand.allCases {
                let plan = try ComparedFileNavigation.plan(command, in: context.snapshot)
                let expectedTarget = context.targets[command]!
                XCTAssertEqual(plan.targetItemIdentity, expectedTarget, "command=\(command)")
                let expectedOrigin =
                    context.origin
                    ?? (command == .previous || command == .last ? .endBoundary : .startBoundary)
                XCTAssertEqual(
                    plan.commandState.availabilityReason,
                    .enabled(
                        ComparedFileNavigationEnabledReason(
                            target: try XCTUnwrap(expectedTarget),
                            origin: expectedOrigin
                        )
                    ),
                    "command=\(command)"
                )
            }
        }
    }

    func testCursorOnUnavailableRowStillDefinesStrictNavigationOrigin() throws {
        let first = pair("a.txt")
        let cursor = pair("b-pending.txt", status: .pending)
        let last = pair("c.txt")
        let rows = [first, cursor, last]
        let rowBindings = bindings(for: rows)
        let snapshot = try makeSnapshot(rows, bindings: rowBindings, cursorResultID: cursor.id)
        let cursorIdentity = identity(for: cursor, in: rowBindings)

        let previous = try ComparedFileNavigation.plan(.previous, in: snapshot)
        let next = try ComparedFileNavigation.plan(.next, in: snapshot)
        XCTAssertEqual(previous.targetItemIdentity, identity(for: first, in: rowBindings))
        XCTAssertEqual(next.targetItemIdentity, identity(for: last, in: rowBindings))
        for plan in [previous, next] {
            guard case .enabled(let reason) = plan.commandState.availabilityReason else {
                return XCTFail("Expected enabled cursor plan")
            }
            XCTAssertEqual(reason.origin, .cursor(cursorIdentity))
        }
    }

    func testResolveAllMatchesIndividualPlansForSelectionCursorBoundaryDisabledAndEmptySnapshots() throws {
        let first = pair("a.txt")
        let middle = pair("b.txt")
        let last = pair("c.txt")
        let rows = [first, middle, last]
        let rowBindings = bindings(for: rows)
        let snapshots = try [
            makeSnapshot(rows, bindings: rowBindings, selectedIDs: [middle.id]),
            makeSnapshot(rows, bindings: rowBindings, cursorResultID: middle.id),
            makeSnapshot(rows, bindings: rowBindings),
            makeSnapshot(rows, bindings: rowBindings, selectedIDs: [first.id]),
            makeSnapshot([pair("pending.txt", status: .pending)]),
            makeSnapshot([], bindings: [], authorities: [], openCapabilities: [])
        ]

        for snapshot in snapshots {
            let all = try ComparedFileNavigation.resolveAll(in: snapshot)
            XCTAssertEqual(all.map(\.command), ComparedFileNavigationCommand.allCases)
            for (offset, command) in ComparedFileNavigationCommand.allCases.enumerated() {
                let individual = try ComparedFileNavigation.resolve(command, in: snapshot)
                XCTAssertEqual(all[offset].commandState, individual.commandState)
                XCTAssertEqual(all[offset].plannedWorkUnits, individual.plannedWorkUnits)
                XCTAssertEqual(all[offset].targetItemIdentity, individual.targetItemIdentity)
                XCTAssertEqual(all[offset].openPairRequest == nil, individual.openPairRequest == nil)
            }
            XCTAssertEqual(
                try snapshot.commandStates().directoryPairNavigationCommandStates,
                DirectoryPairNavigationCommandStates(
                    first: all[0].isEnabled,
                    previous: all[1].isEnabled,
                    next: all[2].isEnabled,
                    last: all[3].isEnabled
                )
            )
        }
    }

    func testEveryFilterDimensionAndPathMatchingBranchDeterminesExactVisibility() throws {
        let leftQuery = DirectoryResult(
            left: metadata("left/CAFÉ.txt"),
            right: metadata("right/no-match.txt"),
            status: .different
        )
        let rightQuery = DirectoryResult(
            left: metadata("left/no-match.txt"),
            right: metadata("right/cafe\u{301}.txt"),
            status: .different
        )
        let directory = pair("directory", kind: .directory)
        let file = pair("file.txt")
        let hidden = pair("nested/.secret.txt")
        let visible = pair("visible.txt")
        let statusMiss = pair("status.txt", status: .identical)

        let cases: [(DirectoryResultFilter, [DirectoryResult], [ComparedFileNavigationVisibility])] = [
            (DirectoryResultFilter(statuses: [.different]), [file, statusMiss], [.visible, .filtered]),
            (DirectoryResultFilter(kinds: [.directory]), [directory, file], [.visible, .filtered]),
            (DirectoryResultFilter(kinds: [.file]), [directory, file], [.filtered, .visible]),
            (DirectoryResultFilter(hidden: .exclude), [hidden, visible], [.hidden, .visible]),
            (DirectoryResultFilter(hidden: .only), [hidden, visible], [.visible, .filtered]),
            (DirectoryResultFilter(pathQuery: "cafe"), [leftQuery, rightQuery], [.visible, .visible]),
            (DirectoryResultFilter(pathQuery: "absent"), [leftQuery, rightQuery], [.filtered, .filtered]),
            (
                DirectoryResultFilter(statuses: [.identical], pathQuery: "cafe", kinds: [.file]),
                [leftQuery],
                [.filtered]
            )
        ]

        for (filter, rows, expected) in cases {
            let snapshot = try makeSnapshot(
                rows,
                bindings: bindings(for: rows),
                filter: filter,
                sortDescriptors: []
            )
            XCTAssertEqual(snapshot.items.map(\.visibility), expected)
        }
    }

    func testEveryKindFilterMatchesEitherSideAndRejectsOtherKinds() throws {
        for kind in DirectoryEntryKind.allCases {
            let matchingPair = pair("pair-\(kind.rawValue)", kind: kind)
            let matchingOneSided = oneSided("one-sided-\(kind.rawValue)", side: .right, kind: kind)
            let otherKind = DirectoryEntryKind.allCases.first { $0 != kind }!
            let nonmatching = pair("other-\(kind.rawValue)", kind: otherKind)
            let mismatch = DirectoryResult(
                left: metadata("mismatch-\(kind.rawValue)", kind: kind),
                right: metadata("mismatch-\(kind.rawValue)", kind: otherKind),
                status: .typeMismatch
            )
            let rows = [matchingPair, matchingOneSided, nonmatching, mismatch]
            let snapshot = try makeSnapshot(
                rows,
                bindings: bindings(for: rows),
                filter: DirectoryResultFilter(kinds: [kind]),
                sortDescriptors: []
            )

            XCTAssertEqual(snapshot.items.map(\.visibility), [.visible, .visible, .filtered, .visible])
        }
    }

    func testHiddenClassificationRequiresHiddenFilterAsSoleExclusion() throws {
        let hiddenDifferent = pair(".different.txt")
        let hiddenIdentical = pair(".identical.txt", status: .identical)
        let rows = [hiddenDifferent, hiddenIdentical]
        let snapshot = try makeSnapshot(
            rows,
            bindings: bindings(for: rows),
            filter: DirectoryResultFilter(statuses: [.different], hidden: .exclude),
            sortDescriptors: []
        )

        XCTAssertEqual(snapshot.items.map(\.visibility), [.hidden, .filtered])
        XCTAssertEqual(snapshot.items.map(\.visibleOrdinal), [nil, nil])
    }

    func testVisibilityComparisonStateAndUnavailabilityMatrix() throws {
        let filtered = pair("drop.txt", status: .identical)
        let hidden = pair(".keep-hidden.txt")
        let pending = pair("keep-pending.txt", status: .pending)
        let directory = pair("keep-directory", kind: .directory)
        let mismatch = typeMismatch("keep-mismatch")
        let skipped = pair("keep-skipped.txt", status: .skipped)
        let failure = pair("keep-error.txt", status: .error)
        let missingLeft = oneSided("keep-missing-left.txt", side: .right)
        let missingRight = oneSided("keep-missing-right.txt", side: .left)
        let available = pair("keep-available.txt")
        let rows = [
            filtered, hidden, pending, directory, mismatch, skipped, failure,
            missingLeft, missingRight, available
        ]
        let snapshot = try makeSnapshot(
            rows,
            bindings: bindings(for: rows),
            filter: DirectoryResultFilter(pathQuery: "keep", hidden: .exclude),
            sortDescriptors: []
        )

        assertItem(snapshot.items[0], state: .identical, visibility: .filtered, reason: .filtered)
        assertItem(snapshot.items[1], state: .different, visibility: .hidden, reason: .hidden)
        assertItem(snapshot.items[2], state: .pending, visibility: .visible, reason: .pending)
        assertItem(snapshot.items[3], state: .different, visibility: .visible, reason: .notRegularFile)
        assertItem(snapshot.items[4], state: .typeMismatch, visibility: .visible, reason: .typeMismatch)
        assertItem(snapshot.items[5], state: .skipped, visibility: .visible, reason: .skipped)
        assertItem(snapshot.items[6], state: .error, visibility: .visible, reason: .comparisonError)
        assertItem(snapshot.items[7], state: .missingLeft, visibility: .visible, capability: .missingLeftRegularFile)
        assertItem(snapshot.items[8], state: .missingRight, visibility: .visible, capability: .missingRightRegularFile)
        assertItem(snapshot.items[9], state: .different, visibility: .visible, capability: .differentRegularFilePair)

        XCTAssertNil(snapshot.items[0].visibleOrdinal)
        XCTAssertNil(snapshot.items[1].visibleOrdinal)
        XCTAssertEqual(snapshot.items.dropFirst(2).compactMap(\.visibleOrdinal), Array(0...7))
        XCTAssertTrue(snapshot.items[1].isHidden)
        XCTAssertFalse(snapshot.items[0].isNavigable)
        XCTAssertTrue(snapshot.items[7].isNavigable)
    }

    func testPairedAvailabilityReportsEachAuthorityFailureForExactReason() throws {
        let row = pair("pair.txt")
        let binding = bindings(for: [row])
        let leftRead = authority(.left, capabilities: [.readRegularFile])
        let rightRead = authority(.right, capabilities: [.readRegularFile])
        let leftEmpty = authority(.left, capabilities: [])
        let rightEmpty = authority(.right, capabilities: [])

        assertUnavailable(
            try makeSnapshot([row], bindings: binding, authorities: [], openCapabilities: []).items[0],
            .missingOpenCapability(.differentRegularFilePair)
        )
        assertUnavailable(
            try makeSnapshot(
                [row], bindings: binding, authorities: [], openCapabilities: [.differentRegularFilePair]
            ).items[0],
            .missingAuthority(.left)
        )
        assertUnavailable(
            try makeSnapshot(
                [row], bindings: binding, authorities: [leftRead], openCapabilities: [.differentRegularFilePair]
            ).items[0],
            .missingAuthority(.right)
        )
        assertUnavailable(
            try makeSnapshot(
                [row], bindings: binding, authorities: [leftEmpty, rightRead], openCapabilities: [.differentRegularFilePair]
            ).items[0],
            .missingAuthorityCapability(side: .left, capability: .readRegularFile)
        )
        assertUnavailable(
            try makeSnapshot(
                [row], bindings: binding, authorities: [leftRead, rightEmpty], openCapabilities: [.differentRegularFilePair]
            ).items[0],
            .missingAuthorityCapability(side: .right, capability: .readRegularFile)
        )
    }

    func testIdenticalPairCapabilityAndAuthorityFailuresMirrorDifferentPairExactly() throws {
        let row = pair("identical.txt", status: .identical)
        let rowBindings = bindings(for: [row])
        let leftRead = authority(.left, capabilities: [.readRegularFile])
        let rightRead = authority(.right, capabilities: [.readRegularFile])
        let leftEmpty = authority(.left, capabilities: [])
        let rightEmpty = authority(.right, capabilities: [])
        let cases:
            [(
                [ComparedFileNavigationRootAuthority],
                Set<ComparedFileNavigationOpenCapability>,
                ComparedFileNavigationItemUnavailabilityReason
            )] = [
                ([], [], .missingOpenCapability(.identicalRegularFilePair)),
                ([], [.identicalRegularFilePair], .missingAuthority(.left)),
                ([leftRead], [.identicalRegularFilePair], .missingAuthority(.right)),
                (
                    [leftEmpty, rightRead],
                    [.identicalRegularFilePair],
                    .missingAuthorityCapability(side: .left, capability: .readRegularFile)
                ),
                (
                    [leftRead, rightEmpty],
                    [.identicalRegularFilePair],
                    .missingAuthorityCapability(side: .right, capability: .readRegularFile)
                )
            ]

        for (authorities, capabilities, reason) in cases {
            assertUnavailable(
                try makeSnapshot(
                    [row],
                    bindings: rowBindings,
                    authorities: authorities,
                    openCapabilities: capabilities
                ).items[0],
                reason
            )
        }
    }

    func testMissingSideAvailabilityRequiresAbsenceValidationAndReadOnExactSides() throws {
        let missingLeft = oneSided("left-absent.txt", side: .right)
        let missingRight = oneSided("right-absent.txt", side: .left)
        let leftRead = authority(.left, capabilities: [.readRegularFile])
        let leftValidate = authority(.left, capabilities: [.validateMissingFile])
        let rightRead = authority(.right, capabilities: [.readRegularFile])
        let rightValidate = authority(.right, capabilities: [.validateMissingFile])

        let missingLeftBindings = bindings(for: [missingLeft])
        assertUnavailable(
            try makeSnapshot(
                [missingLeft],
                bindings: missingLeftBindings,
                authorities: [leftRead, rightRead],
                openCapabilities: [.missingLeftRegularFile]
            ).items[0],
            .missingAuthorityCapability(side: .left, capability: .validateMissingFile)
        )
        assertUnavailable(
            try makeSnapshot(
                [missingLeft],
                bindings: missingLeftBindings,
                authorities: [leftValidate, rightValidate],
                openCapabilities: [.missingLeftRegularFile]
            ).items[0],
            .missingAuthorityCapability(side: .right, capability: .readRegularFile)
        )

        let missingRightBindings = bindings(for: [missingRight])
        assertUnavailable(
            try makeSnapshot(
                [missingRight],
                bindings: missingRightBindings,
                authorities: [leftValidate, rightValidate],
                openCapabilities: [.missingRightRegularFile]
            ).items[0],
            .missingAuthorityCapability(side: .left, capability: .readRegularFile)
        )
        assertUnavailable(
            try makeSnapshot(
                [missingRight],
                bindings: missingRightBindings,
                authorities: [leftRead, rightRead],
                openCapabilities: [.missingRightRegularFile]
            ).items[0],
            .missingAuthorityCapability(side: .right, capability: .validateMissingFile)
        )
    }

    func testMissingSideFailuresCoverAbsentOpenCapabilityAndEachMissingAuthority() throws {
        let cases:
            [(
                DirectoryResult,
                ComparedFileNavigationOpenCapability,
                ComparedFileNavigationSide,
                ComparedFileNavigationSide
            )] = [
                (oneSided("missing-left.txt", side: .right), .missingLeftRegularFile, .left, .right),
                (oneSided("missing-right.txt", side: .left), .missingRightRegularFile, .left, .right)
            ]

        for (row, capability, firstMissing, secondMissing) in cases {
            let rowBindings = bindings(for: [row])
            assertUnavailable(
                try makeSnapshot(
                    [row], bindings: rowBindings, authorities: [], openCapabilities: []
                ).items[0],
                .missingOpenCapability(capability)
            )
            assertUnavailable(
                try makeSnapshot(
                    [row], bindings: rowBindings, authorities: [], openCapabilities: [capability]
                ).items[0],
                .missingAuthority(firstMissing)
            )
            assertUnavailable(
                try makeSnapshot(
                    [row],
                    bindings: rowBindings,
                    authorities: [authority(.left)],
                    openCapabilities: [capability]
                ).items[0],
                .missingAuthority(secondMissing)
            )
        }
    }

    func testMissingSideDirectoriesAndOtherKindsAreNotRegularFiles() throws {
        for side in [Side.left, .right] {
            for kind in [DirectoryEntryKind.directory, .symbolicLink, .other] {
                let row = oneSided("entry-\(kind.rawValue)", side: side, kind: kind)
                let snapshot = try makeSnapshot([row], bindings: bindings(for: [row]))
                assertUnavailable(snapshot.items[0], .notRegularFile)
                XCTAssertEqual(
                    snapshot.items[0].comparisonState,
                    side == .left ? .missingRight : .missingLeft
                )
            }
        }
    }

    func testAuthoritiesAreCanonicalizedAndRejectDuplicateOrInexactMetadata() throws {
        let row = pair("pair.txt")
        let rowBindings = bindings(for: [row])
        let left = authority(.left)
        let right = authority(.right)
        let canonical = try makeSnapshot([row], bindings: rowBindings, authorities: [right, left])
        XCTAssertEqual(canonical.authorities.map(\.side), [.left, .right])
        XCTAssertEqual(canonical.authorities.map(\.identity), [left.identity, right.identity])

        let reusedIdentity = ComparedFileNavigationRootAuthority(
            identity: left.identity,
            side: .right,
            rootURL: rightRoot,
            capabilities: allAuthorityCapabilities
        )
        assertNavigationError(.duplicateAuthorityIdentity(left.identity)) {
            _ = try makeSnapshot([row], bindings: rowBindings, authorities: [left, reusedIdentity])
        }

        let duplicateLeft = ComparedFileNavigationRootAuthority(
            identity: authorityIdentity(9),
            side: .left,
            rootURL: leftRoot,
            capabilities: allAuthorityCapabilities
        )
        assertNavigationError(.duplicateAuthoritySide(.left)) {
            _ = try makeSnapshot([row], bindings: rowBindings, authorities: [left, duplicateLeft])
        }

        let inexactRoot = ComparedFileNavigationRootAuthority(
            identity: authorityIdentity(10),
            side: .left,
            rootURL: URL(string: "file://localhost/left-root")!,
            capabilities: allAuthorityCapabilities
        )
        assertNavigationError(.authorityRootMismatch(.left)) {
            _ = try makeSnapshot([row], bindings: rowBindings, authorities: [inexactRoot])
        }
    }

    func testAlternateRootsAndNondefaultAuthoritiesCopyExactlyIntoSnapshotAndRequest() throws {
        let alternateLeft = URL(string: "file://localhost/Volumes/Left%20Root/")!
        let alternateRight = URL(string: "file:///Volumes/Right%20Root/")!
        let leftAuthority = ComparedFileNavigationRootAuthority(
            identity: authorityIdentity(71),
            side: .left,
            rootURL: alternateLeft,
            capabilities: [.readRegularFile]
        )
        let rightAuthority = ComparedFileNavigationRootAuthority(
            identity: authorityIdentity(72),
            side: .right,
            rootURL: alternateRight,
            capabilities: [.readRegularFile]
        )
        let row = DirectoryResult(
            left: metadata("left/é.txt", byteCount: 7),
            right: metadata("right/e\u{301}.txt", byteCount: 8),
            status: .different
        )
        let snapshot = try makeSnapshot(
            [row],
            bindings: bindings(for: [row]),
            authorities: [rightAuthority, leftAuthority],
            openCapabilities: [.differentRegularFilePair],
            leftRoot: alternateLeft,
            rightRoot: alternateRight
        )
        let request = try XCTUnwrap(ComparedFileNavigation.plan(.next, in: snapshot).openPairRequest)

        assertExactUTF8(snapshot.leftRoot.absoluteString, alternateLeft.absoluteString)
        assertExactUTF8(snapshot.rightRoot.absoluteString, alternateRight.absoluteString)
        XCTAssertEqual(snapshot.authorities, [leftAuthority, rightAuthority])
        XCTAssertEqual(request.left.authorityIdentity, leftAuthority.identity)
        XCTAssertEqual(request.right.authorityIdentity, rightAuthority.identity)
        assertExactUTF8(request.left.rootURL.absoluteString, alternateLeft.absoluteString)
        assertExactUTF8(request.right.rootURL.absoluteString, alternateRight.absoluteString)
        assertExactUTF8(request.left.relativePath, "left/é.txt")
        assertExactUTF8(request.right.relativePath, "right/e\u{301}.txt")
    }

    func testPresentSideMetadataCopiesEveryPublicFieldExactly() throws {
        let leftDate = Date(timeIntervalSinceReferenceDate: -123.25)
        let rightDate = Date(timeIntervalSinceReferenceDate: 456.5)
        let left = metadata(
            "left/e\u{301}.txt",
            byteCount: 111,
            modificationDate: leftDate,
            isHidden: true
        )
        let right = metadata(
            "right/é.txt",
            byteCount: 222,
            modificationDate: rightDate,
            isHidden: false
        )
        let row = DirectoryResult(left: left, right: right, status: .different)
        let item = try makeSnapshot([row], bindings: bindings(for: [row])).items[0]

        assertExactMetadata(item.left, left)
        assertExactMetadata(item.right, right)
        assertExactID(item.resultID, row.id)
        XCTAssertEqual(item.status, .different)
        XCTAssertTrue(item.isHidden)
    }

    func testPairedOpenPlansContainExactSnapshotIdentityAuthorityAndPaths() throws {
        for (offset, status, capability) in [
            (0, DirectoryComparisonStatus.identical, ComparedFileNavigationOpenCapability.identicalRegularFilePair),
            (1, .different, .differentRegularFilePair)
        ] {
            let row = DirectoryResult(
                left: metadata("left-\(offset).txt", byteCount: 10),
                right: metadata("right-\(offset).txt", byteCount: 20),
                status: status
            )
            let rowBindings = bindings(for: [row], startingAt: offset + 1)
            let snapshot = try makeSnapshot(
                [row],
                revision: 31,
                generation: 41,
                bindings: rowBindings,
                openCapabilities: [capability]
            )
            let plan = try ComparedFileNavigation.plan(.next, in: snapshot)
            let request = try XCTUnwrap(plan.openPairRequest)

            XCTAssertEqual(plan.expectedFolderResults, snapshot.reference)
            XCTAssertEqual(request.expectedFolderResults, snapshot.reference)
            XCTAssertEqual(request.itemIdentity, rowBindings[0].identity)
            XCTAssertEqual(request.itemOrdinal, 0)
            assertExactID(request.resultID, row.id)
            XCTAssertEqual(request.comparisonState, status == .identical ? .identical : .different)
            XCTAssertEqual(request.requiredOpenCapability, capability)
            XCTAssertEqual(request.executorContract, .exactSnapshotAuthoritiesAndDescriptorRelativeNoFollow)
            assertOpenSide(
                request.left,
                side: .left,
                presence: .regularFile,
                rootURL: leftRoot,
                path: "left-\(offset).txt",
                authorityIdentity: authorityIdentity(1),
                capability: .readRegularFile
            )
            assertOpenSide(
                request.right,
                side: .right,
                presence: .regularFile,
                rootURL: rightRoot,
                path: "right-\(offset).txt",
                authorityIdentity: authorityIdentity(2),
                capability: .readRegularFile
            )
            XCTAssertTrue(try plan.isCurrent(for: snapshot))
            XCTAssertTrue(try request.isCurrent(for: snapshot))
            XCTAssertNoThrow(try plan.validate(against: snapshot))
            XCTAssertNoThrow(try request.validate(against: snapshot))
        }
    }

    func testMissingSideOpenPlansPreserveNilMetadataAndPlanAbsenceAtCounterpartPath() throws {
        let cases: [(ComparedFileNavigationSide, DirectoryResult, ComparedFileNavigationOpenCapability)] = [
            (.left, oneSided("missing-left.txt", side: .right), .missingLeftRegularFile),
            (.right, oneSided("missing-right.txt", side: .left), .missingRightRegularFile)
        ]

        for (missingSide, row, capability) in cases {
            let rowBindings = bindings(for: [row])
            let snapshot = try makeSnapshot(
                [row],
                bindings: rowBindings,
                openCapabilities: [capability]
            )
            let item = snapshot.items[0]
            let request = try XCTUnwrap(ComparedFileNavigation.plan(.next, in: snapshot).openPairRequest)
            let path = row.id.relativePath

            if missingSide == .left {
                XCTAssertNil(item.left)
                XCTAssertNotNil(item.right)
                assertOpenSide(
                    request.left,
                    side: .left,
                    presence: .missing,
                    rootURL: leftRoot,
                    path: path,
                    authorityIdentity: authorityIdentity(1),
                    capability: .validateMissingFile
                )
                assertOpenSide(
                    request.right,
                    side: .right,
                    presence: .regularFile,
                    rootURL: rightRoot,
                    path: path,
                    authorityIdentity: authorityIdentity(2),
                    capability: .readRegularFile
                )
            } else {
                XCTAssertNotNil(item.left)
                XCTAssertNil(item.right)
                assertOpenSide(
                    request.left,
                    side: .left,
                    presence: .regularFile,
                    rootURL: leftRoot,
                    path: path,
                    authorityIdentity: authorityIdentity(1),
                    capability: .readRegularFile
                )
                assertOpenSide(
                    request.right,
                    side: .right,
                    presence: .missing,
                    rootURL: rightRoot,
                    path: path,
                    authorityIdentity: authorityIdentity(2),
                    capability: .validateMissingFile
                )
            }
        }
    }

    func testFolderReferencesRawValuesAliasesAndComparabilityAreExact() throws {
        let identity = folderIdentity(7)
        let revision = ComparedFileFolderResultsRevision(rawValue: 11)
        let generation = ComparedFileFolderResultsGeneration(rawValue: 13)
        let reference = ComparedFileFolderResultsReference(
            identity: identity,
            revision: revision,
            generation: generation
        )
        let snapshot = try makeSnapshot(
            [pair("pair.txt")],
            identity: identity,
            revision: revision.rawValue,
            generation: generation.rawValue
        )

        XCTAssertEqual(snapshot.reference, reference)
        XCTAssertEqual(snapshot.identity, identity)
        XCTAssertEqual(snapshot.revision.rawValue, 11)
        XCTAssertEqual(snapshot.generation.rawValue, 13)
        XCTAssertLessThan(revision, ComparedFileFolderResultsRevision(rawValue: 12))
        XCTAssertLessThan(generation, ComparedFileFolderResultsGeneration(rawValue: 14))
        XCTAssertEqual(ComparedFileNavigationFolderResultIdentity(rawValue: identity.rawValue), identity)
        XCTAssertEqual(ComparedFileNavigationFolderResultRevision(rawValue: 11), revision)
        XCTAssertEqual(ComparedFileNavigationFolderResultGeneration(rawValue: 13), generation)
        XCTAssertEqual(
            ComparedFileNavigationFolderResultReference(identity: identity, revision: revision, generation: generation),
            reference
        )
    }

    func testExactLookupDistinguishesAliasIDsAndHashCollisions() throws {
        let firstCollision = DirectoryResult(
            left: metadata("a"),
            right: metadata("\u{1}b"),
            status: .different
        )
        let secondCollision = DirectoryResult(
            left: metadata("a\u{1}"),
            right: metadata("b"),
            status: .different
        )
        let alias = pair("same.txt")
        let rows = [firstCollision, secondCollision, alias]
        let rowBindings = [
            ComparedFileNavigationItemBinding(identity: itemIdentity(2), resultID: secondCollision.id),
            ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: firstCollision.id),
            ComparedFileNavigationItemBinding(identity: itemIdentity(3), resultID: alias.id)
        ]
        let leftAlias = DirectoryResult.ID(leftRelativePath: "same.txt", rightRelativePath: nil)
        let rightAlias = DirectoryResult.ID(leftRelativePath: nil, rightRelativePath: "same.txt")
        let snapshot = try makeSnapshot(
            rows,
            bindings: rowBindings,
            selectedIDs: [leftAlias],
            cursorResultID: rightAlias,
            sortDescriptors: []
        )

        XCTAssertNotEqual(firstCollision.id, secondCollision.id)
        XCTAssertEqual(snapshot.item(withResultID: firstCollision.id)?.identity, itemIdentity(1))
        XCTAssertEqual(snapshot.item(withResultID: secondCollision.id)?.identity, itemIdentity(2))
        XCTAssertEqual(snapshot.item(withIdentity: itemIdentity(3))?.resultID, alias.id)
        XCTAssertEqual(leftAlias, alias.id)
        XCTAssertEqual(rightAlias, alias.id)
        XCTAssertNil(snapshot.item(withResultID: leftAlias))
        XCTAssertNil(snapshot.item(withResultID: rightAlias))
        XCTAssertEqual(snapshot.selectedItemIdentities, [itemIdentity(3)])
        XCTAssertEqual(snapshot.cursorItemIdentity, itemIdentity(3))

        let exactBinding = ComparedFileNavigationItemBinding(identity: itemIdentity(3), resultID: alias.id)
        let aliasBinding = ComparedFileNavigationItemBinding(identity: itemIdentity(3), resultID: leftAlias)
        XCTAssertNotEqual(exactBinding, aliasBinding)
        XCTAssertEqual(Set([exactBinding, aliasBinding]).count, 2)
    }

    func testNFCAndNFDResultIDsRemainByteExactAcrossLookupBindingAndItems() throws {
        let nfc = "é.txt"
        let nfd = "e\u{301}.txt"
        XCTAssertEqual(nfc, nfd)
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8))
        let nfcRow = pair(nfc)
        let nfdRow = pair(nfd)
        let nfcBinding = ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: nfcRow.id)
        let nfdBinding = ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: nfdRow.id)
        let nfcSnapshot = try makeSnapshot([nfcRow], bindings: [nfcBinding])
        let nfdSnapshot = try makeSnapshot([nfdRow], bindings: [nfdBinding])

        XCTAssertNil(nfcSnapshot.item(withResultID: nfdRow.id))
        XCTAssertNil(nfdSnapshot.item(withResultID: nfcRow.id))
        XCTAssertNotEqual(nfcBinding, nfdBinding)
        XCTAssertEqual(Set([nfcBinding, nfdBinding]).count, 2)
        XCTAssertNotEqual(nfcSnapshot.items[0], nfdSnapshot.items[0])
        XCTAssertEqual(Set([nfcSnapshot.items[0], nfdSnapshot.items[0]]).count, 2)
        assertExactID(try XCTUnwrap(nfcSnapshot.item(withResultID: nfcRow.id)).resultID, nfcRow.id)
        assertExactID(try XCTUnwrap(nfdSnapshot.item(withResultID: nfdRow.id)).resultID, nfdRow.id)
    }

    func testCollisionCandidatesKeepExactBindingsOrdinalsAndVisibleOrdinals() throws {
        let first = DirectoryResult(
            left: metadata("a"),
            right: metadata("\u{1}b"),
            status: .different
        )
        let second = DirectoryResult(
            left: metadata("a\u{1}"),
            right: metadata("b"),
            status: .different
        )
        let rows = [second, first]
        let rowBindings = [
            ComparedFileNavigationItemBinding(identity: itemIdentity(2), resultID: second.id),
            ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: first.id)
        ]
        let snapshot = try makeSnapshot(
            rows,
            bindings: rowBindings,
            sortDescriptors: []
        )

        XCTAssertEqual(snapshot.items.map(\.identity), [itemIdentity(2), itemIdentity(1)])
        XCTAssertEqual(snapshot.items.map(\.ordinal), [0, 1])
        XCTAssertEqual(snapshot.items.map(\.visibleOrdinal), [0, 1])
        assertExactID(snapshot.items[0].resultID, second.id)
        assertExactID(snapshot.items[1].resultID, first.id)
    }

    func testHashablePublicValuesPreserveByteDistinctStringsURLsAndMetadata() throws {
        let nfc = "é"
        let nfd = "e\u{301}"
        let nfcFilter = ComparedFileNavigationFilterState(DirectoryResultFilter(pathQuery: nfc))
        let nfdFilter = ComparedFileNavigationFilterState(DirectoryResultFilter(pathQuery: nfd))
        XCTAssertNotEqual(nfcFilter, nfdFilter)
        XCTAssertEqual(Set([nfcFilter, nfdFilter]).count, 2)

        let nfcAuthority = ComparedFileNavigationRootAuthority(
            identity: authorityIdentity(80),
            side: .left,
            rootURL: URL(string: "file:///\(nfc)")!,
            capabilities: [.readRegularFile]
        )
        let nfdAuthority = ComparedFileNavigationRootAuthority(
            identity: authorityIdentity(80),
            side: .left,
            rootURL: URL(string: "file:///\(nfd)")!,
            capabilities: [.readRegularFile]
        )
        XCTAssertNotEqual(nfcAuthority, nfdAuthority)
        XCTAssertEqual(Set([nfcAuthority, nfdAuthority]).count, 2)

        let nfcRow = pair("\(nfc).txt")
        let nfdRow = pair("\(nfd).txt")
        let rowIdentity = itemIdentity(81)
        let nfcItem = try makeSnapshot(
            [nfcRow],
            bindings: [ComparedFileNavigationItemBinding(identity: rowIdentity, resultID: nfcRow.id)]
        ).items[0]
        let nfdItem = try makeSnapshot(
            [nfdRow],
            bindings: [ComparedFileNavigationItemBinding(identity: rowIdentity, resultID: nfdRow.id)]
        ).items[0]
        XCTAssertNotEqual(nfcItem, nfdItem)
        XCTAssertEqual(Set([nfcItem, nfdItem]).count, 2)
    }

    func testUnknownSelectedIDIsRemovedBeforeNavigationSnapshotValidation() throws {
        let row = pair("known.txt")
        let unknown = DirectoryResult.ID(
            leftRelativePath: "unknown.txt",
            rightRelativePath: "unknown.txt"
        )
        let results = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: [row],
            sortDescriptors: [DirectoryResultSortDescriptor(key: .path)],
            selectedIDs: [unknown]
        )
        XCTAssertTrue(results.selectedIDs.isEmpty)
        let snapshot = try ComparedFileNavigationSnapshot(
            identity: folderIdentity(1),
            revision: 10,
            generation: 20,
            results: results,
            itemBindings: bindings(for: [row]),
            authorities: fullAuthorities(),
            openCapabilities: allOpenCapabilities
        )
        XCTAssertTrue(snapshot.selectedItemIdentities.isEmpty)
        XCTAssertEqual(
            try ComparedFileNavigation.plan(.next, in: snapshot).commandState.availabilityReason,
            .enabled(
                ComparedFileNavigationEnabledReason(
                    target: snapshot.items[0].identity,
                    origin: .startBoundary
                )
            )
        )
    }

    func testOrderingIsStableDeterministicAndPlansReturnRepeatableReceipts() throws {
        let firstTie = pair("first-tie.txt", byteCount: 20)
        let low = pair("low.txt", byteCount: 10)
        let secondTie = pair("second-tie.txt", byteCount: 20)
        let missingSize = pair("missing-size.txt")
        let rows = [firstTie, missingSize, low, secondTie]
        let rowBindings = bindings(for: rows)
        let snapshot = try makeSnapshot(
            rows,
            bindings: rowBindings,
            selectedIDs: [firstTie.id],
            sortDescriptors: [
                DirectoryResultSortDescriptor(key: .leftSize),
                DirectoryResultSortDescriptor(key: .status, order: .descending)
            ]
        )

        XCTAssertEqual(snapshot.items.map(\.resultID), [low.id, firstTie.id, secondTie.id, missingSize.id])
        let firstReceipts = try ComparedFileNavigation.resolveAll(in: snapshot)
        let secondReceipts = try ComparedFileNavigation.resolveAll(in: snapshot)
        XCTAssertEqual(firstReceipts.map(\.command), ComparedFileNavigationCommand.allCases)
        XCTAssertEqual(firstReceipts.map(\.plannedWorkUnits), secondReceipts.map(\.plannedWorkUnits))
        XCTAssertEqual(firstReceipts.map(\.targetItemIdentity), secondReceipts.map(\.targetItemIdentity))
        XCTAssertEqual(firstReceipts.map(\.plannedWorkUnits), [6, 6, 6, 6])
        XCTAssertTrue(firstReceipts.allSatisfy { $0.plannedWorkUnits > 0 })
    }

    func testExactPlanWorkReceiptsCoverSelectionCursorBoundaryFallbackAndDisabledContexts() throws {
        let rows = [pair("a.txt"), pair("b.txt"), pair("c.txt")]
        let rowBindings = bindings(for: rows)
        let pending = pair("pending.txt", status: .pending)
        let filtered = pair("z-filtered.txt", status: .identical)
        let fallbackRows = rows + [filtered]
        let fallbackBindings = bindings(for: fallbackRows)
        let contexts: [(ComparedFileNavigationSnapshot, [Int])] = try [
            (makeSnapshot(rows, bindings: rowBindings, selectedIDs: [rows[1].id]), [6, 6, 6, 6]),
            (makeSnapshot(rows, bindings: rowBindings, cursorResultID: rows[1].id), [7, 7, 7, 7]),
            (makeSnapshot(rows, bindings: rowBindings), [5, 5, 5, 5]),
            (makeSnapshot(rows, bindings: rowBindings, selectedIDs: [rows[0].id]), [4, 3, 4, 4]),
            (
                makeSnapshot(
                    fallbackRows,
                    bindings: fallbackBindings,
                    selectedIDs: [filtered.id],
                    filter: DirectoryResultFilter(statuses: [.different])
                ),
                [9, 10, 9, 10]
            ),
            (makeSnapshot([pending], bindings: bindings(for: [pending])), [2, 2, 2, 2]),
            (makeSnapshot([], bindings: [], authorities: [], openCapabilities: []), [0, 0, 0, 0])
        ]

        for (snapshot, expected) in contexts {
            let first = try ComparedFileNavigation.resolveAll(in: snapshot)
            let second = try ComparedFileNavigation.resolveAll(in: snapshot)
            XCTAssertEqual(first.map(\.plannedWorkUnits), expected)
            XCTAssertEqual(second.map(\.plannedWorkUnits), expected)
            for (offset, command) in ComparedFileNavigationCommand.allCases.enumerated() {
                XCTAssertEqual(
                    try ComparedFileNavigation.plan(command, in: snapshot).plannedWorkUnits,
                    expected[offset]
                )
            }
        }
    }

    func testEverySortKeyDirectionNilNumericAndUTF8TieHasExactOrder() throws {
        let numeric2 = DirectoryResult(
            left: metadata("file2", byteCount: 20, modificationDate: Date(timeIntervalSinceReferenceDate: 20)),
            right: metadata("right-z", byteCount: nil, modificationDate: nil),
            status: .different
        )
        let numeric10 = DirectoryResult(
            left: metadata("file10", byteCount: nil, modificationDate: nil),
            right: metadata("right-a", byteCount: 10, modificationDate: Date(timeIntervalSinceReferenceDate: 10)),
            status: .identical
        )
        let uppercase = DirectoryResult(
            left: metadata("A", kind: .directory, byteCount: 10, modificationDate: Date(timeIntervalSinceReferenceDate: 10)),
            right: metadata("right-m", kind: .directory, byteCount: 20, modificationDate: Date(timeIntervalSinceReferenceDate: 20)),
            status: .different
        )
        let lowercase = DirectoryResult(
            left: metadata("a", kind: .symbolicLink, byteCount: 30, modificationDate: Date(timeIntervalSinceReferenceDate: 20)),
            right: metadata("right-n", kind: .symbolicLink, byteCount: 30, modificationDate: Date(timeIntervalSinceReferenceDate: 20)),
            status: .different
        )
        let rows = [numeric10, lowercase, numeric2, uppercase]
        let cases: [(DirectoryResultSortKey, [DirectoryResult], [DirectoryResult])] = [
            (.path, [uppercase, lowercase, numeric2, numeric10], [numeric10, numeric2, lowercase, uppercase]),
            (.status, [numeric10, lowercase, numeric2, uppercase], [lowercase, numeric2, uppercase, numeric10]),
            (.kind, [numeric10, numeric2, uppercase, lowercase], [lowercase, uppercase, numeric10, numeric2]),
            (.leftSize, [uppercase, numeric2, lowercase, numeric10], [numeric10, lowercase, numeric2, uppercase]),
            (.rightSize, [numeric10, uppercase, lowercase, numeric2], [numeric2, lowercase, uppercase, numeric10]),
            (
                .leftModificationDate,
                [uppercase, lowercase, numeric2, numeric10],
                [numeric10, lowercase, numeric2, uppercase]
            ),
            (
                .rightModificationDate,
                [numeric10, lowercase, uppercase, numeric2],
                [numeric2, lowercase, uppercase, numeric10]
            )
        ]

        for (key, ascending, descending) in cases {
            let ascendingSnapshot = try makeSnapshot(
                rows,
                bindings: bindings(for: rows),
                sortDescriptors: [DirectoryResultSortDescriptor(key: key)]
            )
            let descendingSnapshot = try makeSnapshot(
                rows,
                bindings: bindings(for: rows),
                sortDescriptors: [DirectoryResultSortDescriptor(key: key, order: .descending)]
            )
            assertExactIDs(ascendingSnapshot.items.map(\.resultID), ascending.map(\.id))
            assertExactIDs(descendingSnapshot.items.map(\.resultID), descending.map(\.id))
        }
    }

    func testPathSortUsesRawUTF8AsDeterministicTieBreaker() throws {
        let uppercase = pair("A.txt")
        let lowercase = pair("a.txt")
        let nfc = pair("é.txt")
        let nfdPair = DirectoryResult(
            left: metadata("e\u{301}.txt"),
            right: metadata("other-e\u{301}.txt"),
            status: .different
        )
        let rows = [lowercase, nfc, uppercase, nfdPair]
        let snapshot = try makeSnapshot(
            rows,
            bindings: bindings(for: rows),
            sortDescriptors: [DirectoryResultSortDescriptor(key: .path)]
        )

        XCTAssertEqual(snapshot.items.map(\.identity), [itemIdentity(3), itemIdentity(1), itemIdentity(4), itemIdentity(2)])
        assertExactUTF8(try XCTUnwrap(snapshot.items[0].left).relativePath, "A.txt")
        assertExactUTF8(try XCTUnwrap(snapshot.items[1].left).relativePath, "a.txt")
        assertExactUTF8(try XCTUnwrap(snapshot.items[2].left).relativePath, "e\u{301}.txt")
        assertExactUTF8(try XCTUnwrap(snapshot.items[3].left).relativePath, "é.txt")
    }

    func testNaNModificationDatesNormalizeStablyAndFiniteDateBitsRemainExact() throws {
        let firstNaN = Double(bitPattern: 0x7FF8_0000_0000_0001)
        let secondNaN = Double(bitPattern: 0x7FF8_0000_0000_0002)
        let firstMetadata = metadata("nan.txt", modificationDate: Date(timeIntervalSinceReferenceDate: firstNaN))
        let secondMetadata = metadata("nan.txt", modificationDate: Date(timeIntervalSinceReferenceDate: secondNaN))
        XCTAssertNil(firstMetadata.modificationDate)
        XCTAssertNil(secondMetadata.modificationDate)

        let nanRows = [
            pair("first.txt", modificationDate: Date(timeIntervalSinceReferenceDate: firstNaN)),
            pair("second.txt", modificationDate: Date(timeIntervalSinceReferenceDate: secondNaN))
        ]
        let nanSnapshot = try makeSnapshot(
            nanRows,
            bindings: bindings(for: nanRows),
            sortDescriptors: [DirectoryResultSortDescriptor(key: .leftModificationDate)]
        )
        XCTAssertEqual(nanSnapshot.items.map(\.resultID), nanRows.map(\.id))

        let negativeZero = pair("zero.txt", modificationDate: Date(timeIntervalSinceReferenceDate: -0.0))
        let positiveZero = pair("zero.txt", modificationDate: Date(timeIntervalSinceReferenceDate: 0.0))
        let rowBindings = bindings(for: [negativeZero])
        let original = try makeSnapshot([negativeZero], bindings: rowBindings)
        let changed = try makeSnapshot([positiveZero], bindings: rowBindings)
        XCTAssertEqual(original.items[0].left?.modificationDate, changed.items[0].left?.modificationDate)
        XCTAssertEqual(original.items[0].left?.modificationDate?.timeIntervalSinceReferenceDate.bitPattern, (-0.0).bitPattern)
        XCTAssertEqual(changed.items[0].left?.modificationDate?.timeIntervalSinceReferenceDate.bitPattern, 0.0.bitPattern)
        XCTAssertNotEqual(original.items[0], changed.items[0])
        assertNavigationError(.staleItemState(rowBindings[0].identity)) {
            try ComparedFileNavigation.plan(.next, in: original).validate(against: changed)
        }
    }

    func testPositiveNegativeQuietAndSignalingNaNsNormalizeWithoutLosingDeterminism() throws {
        let nanPatterns: [UInt64] = [
            0x7FF8_0000_0000_0001,
            0xFFF8_0000_0000_0001,
            0x7FF0_0000_0000_0001,
            0xFFF0_0000_0000_0001
        ]
        var rows: [DirectoryResult] = []
        for (offset, pattern) in nanPatterns.enumerated() {
            let value = Double(bitPattern: pattern)
            XCTAssertTrue(value.isNaN)
            let entry = metadata(
                "nan-\(offset).txt",
                modificationDate: Date(timeIntervalSinceReferenceDate: value)
            )
            XCTAssertNil(entry.modificationDate)
            rows.append(
                pair(
                    "nan-\(offset).txt",
                    modificationDate: Date(timeIntervalSinceReferenceDate: value)
                )
            )
        }
        let ascending = try makeSnapshot(
            rows,
            bindings: bindings(for: rows),
            sortDescriptors: [DirectoryResultSortDescriptor(key: .leftModificationDate)]
        )
        let descending = try makeSnapshot(
            rows,
            bindings: bindings(for: rows),
            sortDescriptors: [
                DirectoryResultSortDescriptor(key: .leftModificationDate, order: .descending)
            ]
        )

        assertExactIDs(ascending.items.map(\.resultID), rows.map(\.id))
        assertExactIDs(descending.items.map(\.resultID), rows.map(\.id))
        XCTAssertTrue(ascending.items.allSatisfy { $0.left?.modificationDate == nil })
    }

    func testLineageChangesProduceExactIdentityRevisionAndGenerationErrors() throws {
        let row = pair("pair.txt")
        let rowBindings = bindings(for: [row])
        let original = try makeSnapshot([row], revision: 10, generation: 20, bindings: rowBindings)
        let plan = try ComparedFileNavigation.plan(.next, in: original)
        let request = try XCTUnwrap(plan.openPairRequest)

        let changedIdentity = try makeSnapshot(
            [row], identity: folderIdentity(99), revision: 10, generation: 20, bindings: rowBindings
        )
        assertNavigationError(
            .folderResultsIdentityChanged(expected: original.identity, actual: changedIdentity.identity)
        ) {
            try plan.validate(against: changedIdentity)
        }
        XCTAssertFalse(try plan.isCurrent(for: changedIdentity))
        XCTAssertFalse(try request.isCurrent(for: changedIdentity))

        let changedRevision = try makeSnapshot([row], revision: 11, generation: 20, bindings: rowBindings)
        assertNavigationError(
            .staleRevision(expected: original.revision, actual: changedRevision.revision)
        ) {
            try request.validate(against: changedRevision)
        }
        XCTAssertFalse(try plan.isCurrent(for: changedRevision))

        let changedGeneration = try makeSnapshot([row], revision: 10, generation: 21, bindings: rowBindings)
        assertNavigationError(
            .staleGeneration(expected: original.generation, actual: changedGeneration.generation)
        ) {
            try plan.validate(against: changedGeneration)
        }
        XCTAssertFalse(try request.isCurrent(for: changedGeneration))
    }

    func testReusedFreshnessRejectsChangedItemIdentityOrderAndStateForExactReasons() throws {
        let first = pair("a.txt", byteCount: 1)
        let last = pair("z.txt", byteCount: 2)
        let rows = [first, last]
        let rowBindings = bindings(for: rows)
        let original = try makeSnapshot(rows, bindings: rowBindings, sortDescriptors: [])
        let plan = try ComparedFileNavigation.plan(.next, in: original)

        let changedBindings = [
            ComparedFileNavigationItemBinding(identity: itemIdentity(99), resultID: first.id),
            rowBindings[1]
        ]
        let changedIdentity = try makeSnapshot(rows, bindings: changedBindings, sortDescriptors: [])
        assertNavigationError(.staleItemIdentity(rowBindings[0].identity)) {
            try plan.validate(against: changedIdentity)
        }

        let changedOrder = try makeSnapshot(
            rows,
            bindings: rowBindings,
            sortDescriptors: [DirectoryResultSortDescriptor(key: .path, order: .descending)]
        )
        assertNavigationError(.staleItemOrder) {
            try plan.validate(against: changedOrder)
        }

        let changedRows = [pair("a.txt", byteCount: 9), last]
        let changedState = try makeSnapshot(changedRows, bindings: rowBindings, sortDescriptors: [])
        assertNavigationError(.staleItemState(rowBindings[0].identity)) {
            try plan.validate(against: changedState)
        }
        XCTAssertFalse(try plan.isCurrent(for: changedIdentity))
        XCTAssertFalse(try plan.isCurrent(for: changedOrder))
        XCTAssertFalse(try plan.isCurrent(for: changedState))
    }

    func testReusedFreshnessRejectsEveryItemFieldIncludingLaterItemAndCount() throws {
        let first = DirectoryResult(
            left: metadata("a.txt", byteCount: 1, modificationDate: Date(timeIntervalSinceReferenceDate: 1)),
            right: metadata("a.txt", byteCount: 1, modificationDate: Date(timeIntervalSinceReferenceDate: 1)),
            status: .different
        )
        let later = DirectoryResult(
            left: metadata("b.txt", byteCount: 2, modificationDate: Date(timeIntervalSinceReferenceDate: 2)),
            right: metadata("b.txt", byteCount: 2, modificationDate: Date(timeIntervalSinceReferenceDate: 2)),
            status: .different
        )
        let rows = [first, later]
        let rowBindings = bindings(for: rows)
        let original = try makeSnapshot(rows, bindings: rowBindings, sortDescriptors: [])
        let plan = try ComparedFileNavigation.plan(.next, in: original)
        let firstIdentity = rowBindings[0].identity
        let laterIdentity = rowBindings[1].identity

        let variants: [([DirectoryResult], ComparedFileNavigationError)] = [
            (
                [
                    DirectoryResult(
                        left: metadata("a.txt", kind: .directory, byteCount: 1),
                        right: metadata("a.txt", kind: .directory, byteCount: 1),
                        status: .different
                    ),
                    later
                ],
                .staleItemState(firstIdentity)
            ),
            (
                [
                    DirectoryResult(
                        left: metadata("a.txt", byteCount: 1),
                        right: metadata("a.txt", byteCount: 1),
                        status: .identical
                    ),
                    later
                ],
                .staleItemState(firstIdentity)
            ),
            (
                [
                    DirectoryResult(
                        left: metadata("a.txt", byteCount: 1, modificationDate: Date(timeIntervalSinceReferenceDate: 9)),
                        right: metadata("a.txt", byteCount: 1, modificationDate: Date(timeIntervalSinceReferenceDate: 1)),
                        status: .different
                    ),
                    later
                ],
                .staleItemState(firstIdentity)
            ),
            (
                [
                    DirectoryResult(
                        left: metadata("a.txt", byteCount: 1, isHidden: true),
                        right: metadata("a.txt", byteCount: 1),
                        status: .different
                    ),
                    later
                ],
                .staleItemState(firstIdentity)
            ),
            (
                [
                    first,
                    DirectoryResult(
                        left: metadata("b.txt", byteCount: 99),
                        right: metadata("b.txt", byteCount: 2),
                        status: .different
                    )
                ],
                .staleItemState(laterIdentity)
            )
        ]

        for (changedRows, expected) in variants {
            let changed = try makeSnapshot(changedRows, bindings: rowBindings, sortDescriptors: [])
            assertNavigationError(expected) {
                try plan.validate(against: changed)
            }
        }

        let changedLaterID = DirectoryResult(
            left: metadata("c.txt", byteCount: 2),
            right: metadata("c.txt", byteCount: 2),
            status: .different
        )
        let changedIDBindings = [
            rowBindings[0],
            ComparedFileNavigationItemBinding(identity: laterIdentity, resultID: changedLaterID.id)
        ]
        let changedIDSnapshot = try makeSnapshot(
            [first, changedLaterID],
            bindings: changedIDBindings,
            sortDescriptors: []
        )
        assertNavigationError(.staleItemState(laterIdentity)) {
            try plan.validate(against: changedIDSnapshot)
        }

        let countSnapshot = try makeSnapshot([first], bindings: [rowBindings[0]], sortDescriptors: [])
        assertNavigationError(.staleSnapshot) {
            try plan.validate(against: countSnapshot)
        }
    }

    func testReusedFreshnessRejectsEveryNonItemFingerprintChangeAsStaleSnapshot() throws {
        let row = pair("pair.txt")
        let rowBindings = bindings(for: [row])
        let original = try makeSnapshot(
            [row],
            bindings: rowBindings,
            authorities: fullAuthorities(),
            openCapabilities: [.differentRegularFilePair]
        )
        let plan = try ComparedFileNavigation.plan(.next, in: original)
        let changedAuthorities = [
            ComparedFileNavigationRootAuthority(
                identity: authorityIdentity(11),
                side: .left,
                rootURL: leftRoot,
                capabilities: [.readRegularFile, .validateMissingFile]
            ),
            authority(.right)
        ]
        let changedAuthorityCapabilities = [
            authority(.left, capabilities: [.readRegularFile]),
            authority(.right)
        ]
        let alternateLeftRoot = URL(string: "file:///alternate-left-root")!
        let changedRootAuthorities = fullAuthorities(leftRoot: alternateLeftRoot)
        let variants = try [
            makeSnapshot([row], bindings: rowBindings, selectedIDs: [row.id], openCapabilities: [.differentRegularFilePair]),
            makeSnapshot([row], bindings: rowBindings, cursorResultID: row.id, openCapabilities: [.differentRegularFilePair]),
            makeSnapshot(
                [row], bindings: rowBindings, filter: DirectoryResultFilter(statuses: [.different]), openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                sortDescriptors: [DirectoryResultSortDescriptor(key: .status)],
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings, authorities: changedAuthorities,
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings, authorities: changedAuthorityCapabilities,
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                openCapabilities: [.differentRegularFilePair, .identicalRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings, openCapabilities: [.differentRegularFilePair],
                limits: limits(maximumWorkUnits: ComparedFileNavigationLimits.default.maximumWorkUnits - 1)
            ),
            makeSnapshot(
                [row], bindings: rowBindings, authorities: changedRootAuthorities,
                openCapabilities: [.differentRegularFilePair], leftRoot: alternateLeftRoot
            )
        ]

        for variant in variants {
            assertNavigationError(.staleSnapshot) {
                try plan.validate(against: variant)
            }
            XCTAssertFalse(try plan.isCurrent(for: variant))
        }
    }

    func testEveryFilterRootSortCapabilityAuthorityAndLimitFingerprintLeafIsExact() throws {
        let row = pair("pair.txt")
        let rowBindings = bindings(for: [row])
        let original = try makeSnapshot(
            [row],
            bindings: rowBindings,
            authorities: fullAuthorities(),
            openCapabilities: [.differentRegularFilePair]
        )
        let plan = try ComparedFileNavigation.plan(.next, in: original)
        let alternateLeft = URL(string: "file:///alternate-left")!
        let alternateRight = URL(string: "file:///alternate-right")!
        let limitVariants = [
            limits(maximumItemCount: ComparedFileNavigationLimits.default.maximumItemCount - 1),
            limits(maximumSortDescriptorCount: ComparedFileNavigationLimits.default.maximumSortDescriptorCount - 1),
            limits(maximumStringUTF8Bytes: ComparedFileNavigationLimits.default.maximumStringUTF8Bytes - 1),
            limits(maximumTotalStringUTF8Bytes: ComparedFileNavigationLimits.default.maximumTotalStringUTF8Bytes - 1),
            limits(maximumWorkUnits: ComparedFileNavigationLimits.default.maximumWorkUnits - 1),
            limits(cancellationCheckInterval: ComparedFileNavigationLimits.default.cancellationCheckInterval - 1)
        ]
        var variants = try [
            makeSnapshot(
                [row], bindings: rowBindings,
                filter: DirectoryResultFilter(statuses: [.different]),
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                filter: DirectoryResultFilter(pathQuery: "pair"),
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                filter: DirectoryResultFilter(kinds: [.file]),
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                filter: DirectoryResultFilter(hidden: .exclude),
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                sortDescriptors: [DirectoryResultSortDescriptor(key: .status)],
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                authorities: fullAuthorities(leftRoot: alternateLeft),
                openCapabilities: [.differentRegularFilePair],
                leftRoot: alternateLeft
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                authorities: fullAuthorities(rightRoot: alternateRight),
                openCapabilities: [.differentRegularFilePair],
                rightRoot: alternateRight
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                authorities: [
                    ComparedFileNavigationRootAuthority(
                        identity: authorityIdentity(91),
                        side: .left,
                        rootURL: leftRoot,
                        capabilities: allAuthorityCapabilities
                    ),
                    authority(.right)
                ],
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                authorities: [
                    authority(.left, capabilities: [.readRegularFile]),
                    authority(.right)
                ],
                openCapabilities: [.differentRegularFilePair]
            ),
            makeSnapshot(
                [row], bindings: rowBindings,
                openCapabilities: [.differentRegularFilePair, .identicalRegularFilePair]
            )
        ]
        for variantLimits in limitVariants {
            variants.append(
                try makeSnapshot(
                    [row],
                    bindings: rowBindings,
                    openCapabilities: [.differentRegularFilePair],
                    limits: variantLimits
                )
            )
        }

        for variant in variants {
            assertNavigationError(.staleSnapshot) {
                try plan.validate(against: variant)
            }
        }
    }

    func testDisabledPlansHaveNoOpenRequestAndValidationReturnsCommandReason() throws {
        let unavailable = pair("pending.txt", status: .pending)
        let noItems = try makeSnapshot([unavailable], bindings: bindings(for: [unavailable]))
        for command in ComparedFileNavigationCommand.allCases {
            let plan = try ComparedFileNavigation.plan(command, in: noItems)
            assertDisabled(plan, .noNavigableItems)
            assertNavigationError(.commandDisabled(.noNavigableItems)) {
                try plan.validate(against: noItems)
            }
            XCTAssertTrue(try plan.isCurrent(for: noItems))
        }
    }

    func testBindingValidationSeparatesMissingUnusedDuplicateIDAndDuplicateIdentity() throws {
        let first = pair("a.txt")
        let second = pair("b.txt")
        assertNavigationError(.missingItemBinding(first.id)) {
            _ = try makeSnapshot([first], bindings: [])
        }

        let unusedID = DirectoryResult.ID(leftRelativePath: "unused.txt", rightRelativePath: "unused.txt")
        assertNavigationError(.unusedItemBinding(unusedID)) {
            _ = try makeSnapshot(
                [first],
                bindings: [ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: unusedID)]
            )
        }

        let duplicateBindings = [
            ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: first.id),
            ComparedFileNavigationItemBinding(identity: itemIdentity(2), resultID: first.id)
        ]
        assertNavigationError(.duplicateResultID(first.id)) {
            _ = try makeSnapshot([first], bindings: duplicateBindings)
        }

        let duplicateIdentityBindings = [
            ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: first.id),
            ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: second.id)
        ]
        assertNavigationError(.duplicateItemIdentity(itemIdentity(1))) {
            _ = try makeSnapshot([first, second], bindings: duplicateIdentityBindings)
        }

        let aliasID = DirectoryResult.ID(leftRelativePath: "a.txt", rightRelativePath: nil)
        assertNavigationError(.unusedItemBinding(aliasID)) {
            _ = try makeSnapshot(
                [first],
                bindings: [ComparedFileNavigationItemBinding(identity: itemIdentity(1), resultID: aliasID)]
            )
        }
        let unknownCursor = DirectoryResult.ID(leftRelativePath: "unknown.txt", rightRelativePath: nil)
        assertNavigationError(.unknownCursorResult(unknownCursor)) {
            _ = try makeSnapshot([first], bindings: bindings(for: [first]), cursorResultID: unknownCursor)
        }
    }

    func testRootAndRelativePathValidationRejectsEachInvalidShapeWithoutFilesystemAccess() throws {
        let row = pair("valid.txt")
        let rowBindings = bindings(for: [row])
        let invalidRoots: [(URL, URL, ComparedFileNavigationError)] = [
            (URL(string: "https://example.test/left")!, rightRoot, .invalidRootURL(.left)),
            (leftRoot, URL(string: "file:relative")!, .invalidRootURL(.right)),
            (URL(string: "file:///left?query=1")!, rightRoot, .invalidRootURL(.left)),
            (leftRoot, URL(string: "file:///right#fragment")!, .invalidRootURL(.right))
        ]
        for (left, right, expected) in invalidRoots {
            assertNavigationError(expected) {
                _ = try makeSnapshot(
                    [row], bindings: rowBindings, authorities: [], leftRoot: left, rightRoot: right
                )
            }
        }

        for path in ["", "/absolute", ".", "..", "a//b", "a/./b", "a/../b", "nul\0path"] {
            let invalid = pair(path)
            assertNavigationError(.invalidRelativePath(item: nil, side: .left)) {
                _ = try makeSnapshot([invalid], bindings: bindings(for: [invalid]), authorities: [])
            }
        }
    }

    func testRootValidationRejectsRemoteHostsNULAndMalformedRightOnlyPaths() throws {
        let row = pair("valid.txt")
        let rowBindings = bindings(for: [row])
        let invalidRoots: [(URL, URL, ComparedFileNavigationError)] = [
            (URL(string: "file://remote.example/left")!, rightRoot, .invalidRootURL(.left)),
            (leftRoot, URL(string: "file://remote.example/right")!, .invalidRootURL(.right))
        ]
        for (left, right, expected) in invalidRoots {
            assertNavigationError(expected) {
                _ = try makeSnapshot(
                    [row], bindings: rowBindings, authorities: [], leftRoot: left, rightRoot: right
                )
            }
        }

        let encodedNULRoots: [(URL, URL, ComparedFileNavigationError)] = [
            (URL(string: "file:///left%00root")!, rightRoot, .invalidRootURL(.left)),
            (leftRoot, URL(string: "file:///right%00root")!, .invalidRootURL(.right))
        ]
        for (left, right, expected) in encodedNULRoots {
            assertNavigationError(expected) {
                _ = try makeSnapshot(
                    [row],
                    bindings: rowBindings,
                    authorities: [],
                    leftRoot: left,
                    rightRoot: right
                )
            }
        }

        for path in ["", "/absolute", ".", "..", "a//b", "a/./b", "a/../b", "nul\0path"] {
            let invalid = oneSided(path, side: .right)
            assertNavigationError(.invalidRelativePath(item: nil, side: .right)) {
                _ = try makeSnapshot([invalid], bindings: bindings(for: [invalid]), authorities: [])
            }
        }
    }

    func testEveryLimitRejectsValuesOutsideItsExactSupportedRange() {
        let hard = ComparedFileNavigationLimits.self
        let invalid: [(ComparedFileNavigationError, ComparedFileNavigationLimits)] = [
            (.invalidLimit(.items, value: -1), limits(maximumItemCount: -1)),
            (
                .invalidLimit(.items, value: hard.hardMaximumItemCount + 1),
                limits(maximumItemCount: hard.hardMaximumItemCount + 1)
            ),
            (.invalidLimit(.sortDescriptors, value: -1), limits(maximumSortDescriptorCount: -1)),
            (
                .invalidLimit(.sortDescriptors, value: hard.hardMaximumSortDescriptorCount + 1),
                limits(maximumSortDescriptorCount: hard.hardMaximumSortDescriptorCount + 1)
            ),
            (.invalidLimit(.stringUTF8Bytes, value: 0), limits(maximumStringUTF8Bytes: 0)),
            (
                .invalidLimit(.stringUTF8Bytes, value: hard.hardMaximumStringUTF8Bytes + 1),
                limits(maximumStringUTF8Bytes: hard.hardMaximumStringUTF8Bytes + 1)
            ),
            (
                .invalidLimit(.totalStringUTF8Bytes, value: 31),
                limits(maximumStringUTF8Bytes: 32, maximumTotalStringUTF8Bytes: 31)
            ),
            (
                .invalidLimit(.totalStringUTF8Bytes, value: hard.hardMaximumTotalStringUTF8Bytes + 1),
                limits(maximumTotalStringUTF8Bytes: hard.hardMaximumTotalStringUTF8Bytes + 1)
            ),
            (.invalidLimit(.workUnits, value: 0), limits(maximumWorkUnits: 0)),
            (
                .invalidLimit(.workUnits, value: hard.hardMaximumWorkUnits + 1),
                limits(maximumWorkUnits: hard.hardMaximumWorkUnits + 1)
            ),
            (
                .invalidLimit(.cancellationCheckInterval, value: 0),
                limits(cancellationCheckInterval: 0)
            ),
            (
                .invalidLimit(
                    .cancellationCheckInterval,
                    value: hard.hardMaximumCancellationCheckInterval + 1
                ),
                limits(cancellationCheckInterval: hard.hardMaximumCancellationCheckInterval + 1)
            )
        ]

        for (expected, value) in invalid {
            assertNavigationError(expected) {
                _ = try makeSnapshot([], bindings: [], authorities: [], limits: value)
            }
        }
    }

    func testHardMaximumLimitsAndExactItemAndSortCountsAreAccepted() throws {
        let hard = ComparedFileNavigationLimits.self
        XCTAssertNoThrow(
            try makeSnapshot(
                [],
                bindings: [],
                sortDescriptors: [],
                authorities: [],
                limits: ComparedFileNavigationLimits(
                    maximumItemCount: hard.hardMaximumItemCount,
                    maximumSortDescriptorCount: hard.hardMaximumSortDescriptorCount,
                    maximumStringUTF8Bytes: hard.hardMaximumStringUTF8Bytes,
                    maximumTotalStringUTF8Bytes: hard.hardMaximumTotalStringUTF8Bytes,
                    maximumWorkUnits: hard.hardMaximumWorkUnits,
                    cancellationCheckInterval: hard.hardMaximumCancellationCheckInterval
                )
            )
        )

        let rows = [pair("a.txt"), pair("b.txt")]
        let descriptors = [
            DirectoryResultSortDescriptor(key: .status),
            DirectoryResultSortDescriptor(key: .path)
        ]
        XCTAssertNoThrow(
            try makeSnapshot(
                rows,
                bindings: bindings(for: rows),
                sortDescriptors: descriptors,
                authorities: [],
                limits: limits(maximumItemCount: 2, maximumSortDescriptorCount: 2)
            )
        )
        assertNavigationError(.tooManyItems(maximum: 1)) {
            _ = try makeSnapshot(
                rows,
                bindings: bindings(for: rows),
                sortDescriptors: descriptors,
                authorities: [],
                limits: limits(maximumItemCount: 1, maximumSortDescriptorCount: 2)
            )
        }
        assertNavigationError(.tooManySortDescriptors(maximum: 1)) {
            _ = try makeSnapshot(
                rows,
                bindings: bindings(for: rows),
                sortDescriptors: descriptors,
                authorities: [],
                limits: limits(maximumItemCount: 2, maximumSortDescriptorCount: 1)
            )
        }
    }

    func testStringAndTotalStringLimitsAcceptExactBytesAndRejectOneMore() throws {
        let rootMaximum = max(leftRoot.absoluteString.utf8.count, rightRoot.absoluteString.utf8.count)
        let exactPath = String(repeating: "x", count: rootMaximum)
        let exactRow = pair(exactPath)
        let exactBindings = bindings(for: [exactRow])
        let exactTotal = leftRoot.absoluteString.utf8.count + rightRoot.absoluteString.utf8.count + 4 * exactPath.utf8.count
        let exactLimits = limits(
            maximumStringUTF8Bytes: rootMaximum,
            maximumTotalStringUTF8Bytes: exactTotal
        )
        XCTAssertNoThrow(
            try makeSnapshot(
                [exactRow], bindings: exactBindings, authorities: [], limits: exactLimits
            )
        )

        let oversizedPath = exactPath + "x"
        let oversizedRow = pair(oversizedPath)
        assertNavigationError(
            .stringTooLarge(item: nil, side: .left, maximumUTF8Bytes: rootMaximum)
        ) {
            _ = try makeSnapshot(
                [oversizedRow],
                bindings: bindings(for: [oversizedRow]),
                authorities: [],
                limits: exactLimits
            )
        }

        assertNavigationError(.totalStringsTooLarge(maximumUTF8Bytes: exactTotal - 1)) {
            _ = try makeSnapshot(
                [exactRow],
                bindings: exactBindings,
                authorities: [],
                limits: limits(
                    maximumStringUTF8Bytes: rootMaximum,
                    maximumTotalStringUTF8Bytes: exactTotal - 1
                )
            )
        }
    }

    func testMultibyteAggregateCountsRootsPathsBindingsFilterAndAuthorityURLsExactly() throws {
        let multibyte = "é😀"
        let row = pair("folder/\(multibyte).txt")
        let rowBindings = bindings(for: [row])
        let filter = DirectoryResultFilter(pathQuery: multibyte)
        let authorities = fullAuthorities()
        let exactTotal =
            [leftRoot.absoluteString, rightRoot.absoluteString]
            .map { $0.utf8.count }
            .reduce(0, +)
            + 4 * row.id.relativePath.utf8.count
            + filter.pathQuery.utf8.count
            + authorities.map { $0.rootURL.absoluteString.utf8.count }.reduce(0, +)
        let maximumSingle = [
            leftRoot.absoluteString,
            rightRoot.absoluteString,
            row.id.relativePath,
            filter.pathQuery
        ].map { $0.utf8.count }.max()!

        XCTAssertNoThrow(
            try makeSnapshot(
                [row],
                bindings: rowBindings,
                filter: filter,
                authorities: authorities,
                limits: limits(
                    maximumStringUTF8Bytes: maximumSingle,
                    maximumTotalStringUTF8Bytes: exactTotal
                )
            )
        )
        assertNavigationError(.totalStringsTooLarge(maximumUTF8Bytes: exactTotal - 1)) {
            _ = try makeSnapshot(
                [row],
                bindings: rowBindings,
                filter: filter,
                authorities: authorities,
                limits: limits(
                    maximumStringUTF8Bytes: maximumSingle,
                    maximumTotalStringUTF8Bytes: exactTotal - 1
                )
            )
        }
        assertNavigationError(
            .stringTooLarge(item: nil, side: .left, maximumUTF8Bytes: row.id.relativePath.utf8.count - 1)
        ) {
            _ = try makeSnapshot(
                [row],
                bindings: rowBindings,
                filter: filter,
                authorities: authorities,
                limits: limits(
                    maximumStringUTF8Bytes: row.id.relativePath.utf8.count - 1,
                    maximumTotalStringUTF8Bytes: exactTotal
                )
            )
        }
    }

    func testPathHashCollisionLookupConsumesBoundedWorkAtExactBoundary() throws {
        let colliding = [
            DirectoryResult(left: metadata("a"), right: metadata("\u{1}b"), status: .different),
            DirectoryResult(left: metadata("a\u{1}"), right: metadata("b"), status: .different)
        ]
        let noncolliding = [
            DirectoryResult(left: metadata("a"), right: metadata("\u{1}b"), status: .different),
            DirectoryResult(left: metadata("a\u{2}"), right: metadata("b"), status: .different)
        ]
        let collisionWork = try minimumConstructionWork(rows: colliding, bindings: bindings(for: colliding))
        let ordinaryWork = try minimumConstructionWork(rows: noncolliding, bindings: bindings(for: noncolliding))

        XCTAssertGreaterThan(collisionWork, ordinaryWork)
        XCTAssertNoThrow(
            try makeSnapshot(
                colliding,
                bindings: bindings(for: colliding),
                sortDescriptors: [],
                authorities: [],
                limits: limits(maximumWorkUnits: collisionWork)
            )
        )
        assertNavigationError(.workLimitExceeded(maximumWorkUnits: collisionWork - 1)) {
            _ = try makeSnapshot(
                colliding,
                bindings: bindings(for: colliding),
                sortDescriptors: [],
                authorities: [],
                limits: limits(maximumWorkUnits: collisionWork - 1)
            )
        }
    }

    func testConstructionSortAndFilterWorkHaveExactIndependentBoundaries() throws {
        let unsortedRows = [
            pair("item20.txt"), pair("item3.txt"), pair("item100.txt"), pair("item1.txt")
        ]
        let rowBindings = bindings(for: unsortedRows)
        let baseWork = try minimumConstructionWork(rows: unsortedRows, bindings: rowBindings)
        let sortDescriptors = [DirectoryResultSortDescriptor(key: .path)]
        let sortWork = try minimumConstructionWork(
            rows: unsortedRows,
            bindings: rowBindings,
            sortDescriptors: sortDescriptors
        )
        let filter = DirectoryResultFilter(pathQuery: "item")
        let filterWork = try minimumConstructionWork(
            rows: unsortedRows,
            bindings: rowBindings,
            filter: filter
        )

        XCTAssertGreaterThan(sortWork, baseWork)
        XCTAssertGreaterThan(filterWork, baseWork)
        assertConstructionBoundary(
            rows: unsortedRows,
            bindings: rowBindings,
            sortDescriptors: sortDescriptors,
            exactWork: sortWork
        )
        assertConstructionBoundary(
            rows: unsortedRows,
            bindings: rowBindings,
            filter: filter,
            exactWork: filterWork
        )
    }

    func testEachPlanResolveAllAndCommandStatesHaveExactEndToEndWorkBoundaries() throws {
        let rows = [pair("a.txt"), pair("b.txt"), pair("c.txt")]
        let rowBindings = bindings(for: rows)

        for command in ComparedFileNavigationCommand.allCases {
            let planWork = try minimumWork { maximumWork in
                let snapshot = try makeSnapshot(
                    rows,
                    bindings: rowBindings,
                    selectedIDs: [rows[1].id],
                    limits: limits(maximumWorkUnits: maximumWork)
                )
                _ = try ComparedFileNavigation.plan(command, in: snapshot)
            }
            let resolveWork = try minimumWork { maximumWork in
                let snapshot = try makeSnapshot(
                    rows,
                    bindings: rowBindings,
                    selectedIDs: [rows[1].id],
                    limits: limits(maximumWorkUnits: maximumWork)
                )
                _ = try ComparedFileNavigation.resolve(command, in: snapshot)
            }
            XCTAssertEqual(planWork, resolveWork)
            assertEndToEndQueryBoundary(rows: rows, command: command, exactWork: planWork)
        }

        let resolveAllWork = try minimumQueryWork { snapshot in
            _ = try ComparedFileNavigation.resolveAll(in: snapshot)
        }
        let statesWork = try minimumQueryWork { snapshot in
            _ = try ComparedFileNavigation.commandStates(in: snapshot)
        }
        XCTAssertEqual(resolveAllWork, statesWork)
        assertQueryBoundary(exactWork: resolveAllWork) {
            _ = try ComparedFileNavigation.resolveAll(in: $0)
        }
        assertQueryBoundary(exactWork: statesWork) {
            _ = try ComparedFileNavigation.commandStates(in: $0)
        }
    }

    func testCurrentPlanRequestAndStaleOrderValidationHaveExactEndToEndWorkBoundaries() throws {
        let rows = [pair("a-long-name.txt"), pair("b-long-name.txt")]
        let currentPlanWork = try minimumCurrentValidationWork(validateRequest: false)
        let currentRequestWork = try minimumCurrentValidationWork(validateRequest: true)
        XCTAssertGreaterThanOrEqual(currentRequestWork, currentPlanWork)
        assertCurrentValidationBoundary(exactWork: currentPlanWork, validateRequest: false)
        assertCurrentValidationBoundary(exactWork: currentRequestWork, validateRequest: true)

        let staleWork = try minimumStaleOrderWork(rows: rows)
        assertStaleOrderBoundary(rows: rows, exactWork: staleWork)
    }

    func testCancellationCheckIntervalOneAndMaximumObservePrecancelAndFinalChecks() async throws {
        let rows = [pair("a.txt"), pair("b.txt")]
        for interval in [1, ComparedFileNavigationLimits.hardMaximumCancellationCheckInterval] {
            let snapshot = try makeSnapshot(
                rows,
                bindings: bindings(for: rows),
                limits: limits(cancellationCheckInterval: interval)
            )
            let errors = await Task.detached {
                withUnsafeCurrentTask { $0?.cancel() }
                return ComparedFileNavigationCommand.allCases.map { command in
                    captureComparedFileNavigationError {
                        _ = try ComparedFileNavigation.plan(command, in: snapshot)
                    }
                }
            }.value
            XCTAssertEqual(errors, Array(repeating: .cancelled, count: 4))
        }
    }

    func testPeriodicCancellationStopsLongConstruction() async {
        let count = 16_384
        let rows = (0..<count).reversed().map { pair("item-\($0).txt") }
        let rowBindings = bindings(for: rows)
        let results = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: rows,
            sortDescriptors: [DirectoryResultSortDescriptor(key: .path)]
        )
        let task = Task.detached {
            do {
                _ = try ComparedFileNavigationSnapshot(
                    identity: ComparedFileFolderResultsIdentity(),
                    revision: 1,
                    generation: 1,
                    results: results,
                    itemBindings: rowBindings,
                    limits: ComparedFileNavigationLimits(
                        maximumItemCount: count,
                        maximumWorkUnits: ComparedFileNavigationLimits.hardMaximumWorkUnits,
                        cancellationCheckInterval: 1
                    )
                )
                return ComparedFileNavigationCancellationOutcome.succeeded
            } catch ComparedFileNavigationError.cancelled {
                return .cancelled
            } catch {
                return .failed(String(describing: error))
            }
        }
        await Task.yield()
        task.cancel()

        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testPreexistingCancellationStopsConstructionPlanningQueriesAndValidation() async throws {
        let rows = [pair("a.txt"), pair("b.txt")]
        let rowBindings = bindings(for: rows)
        let snapshot = try makeSnapshot(rows, bindings: rowBindings)
        let plan = try ComparedFileNavigation.plan(.next, in: snapshot)
        let request = try XCTUnwrap(plan.openPairRequest)
        let constructionResults = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: rows
        )
        let constructionIdentity = folderIdentity(1)
        let constructionAuthorities = fullAuthorities()
        let constructionCapabilities = allOpenCapabilities

        let errors = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var errors: [ComparedFileNavigationError?] = []
            errors.append(
                captureComparedFileNavigationError {
                    _ = try ComparedFileNavigationSnapshot(
                        identity: constructionIdentity,
                        revision: 10,
                        generation: 20,
                        results: constructionResults,
                        itemBindings: rowBindings,
                        authorities: constructionAuthorities,
                        openCapabilities: constructionCapabilities
                    )
                }
            )
            errors.append(captureComparedFileNavigationError { _ = try ComparedFileNavigation.plan(.next, in: snapshot) })
            errors.append(captureComparedFileNavigationError { _ = try ComparedFileNavigation.resolve(.next, in: snapshot) })
            errors.append(captureComparedFileNavigationError { _ = try ComparedFileNavigation.resolveAll(in: snapshot) })
            errors.append(captureComparedFileNavigationError { _ = try ComparedFileNavigation.commandStates(in: snapshot) })
            errors.append(captureComparedFileNavigationError { _ = try ComparedFileNavigation.canExecute(.next, in: snapshot) })
            errors.append(captureComparedFileNavigationError { try plan.validate(against: snapshot) })
            errors.append(captureComparedFileNavigationError { _ = try plan.isCurrent(for: snapshot) })
            errors.append(captureComparedFileNavigationError { try request.validate(against: snapshot) })
            errors.append(captureComparedFileNavigationError { _ = try request.isCurrent(for: snapshot) })
            return errors
        }.value

        XCTAssertEqual(errors, Array(repeating: .cancelled, count: 10))
    }

    private var leftRoot: URL { URL(string: "file:///left-root")! }
    private var rightRoot: URL { URL(string: "file:///right-root")! }

    private var allAuthorityCapabilities: Set<ComparedFileNavigationAuthorityCapability> {
        [.readRegularFile, .validateMissingFile]
    }

    private var allOpenCapabilities: Set<ComparedFileNavigationOpenCapability> {
        Set(ComparedFileNavigationOpenCapability.allCases)
    }

    private enum Side {
        case left
        case right
    }

    private func metadata(
        _ path: String,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64? = nil,
        modificationDate: Date? = nil,
        isHidden: Bool? = nil
    ) -> DirectoryEntryMetadata {
        DirectoryEntryMetadata(
            relativePath: path,
            kind: kind,
            byteCount: byteCount,
            modificationDate: modificationDate,
            isHidden: isHidden
        )
    }

    private func pair(
        _ path: String,
        status: DirectoryComparisonStatus = .different,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64? = nil,
        modificationDate: Date? = nil
    ) -> DirectoryResult {
        DirectoryResult(
            left: metadata(
                path,
                kind: kind,
                byteCount: byteCount,
                modificationDate: modificationDate
            ),
            right: metadata(
                path,
                kind: kind,
                byteCount: byteCount,
                modificationDate: modificationDate
            ),
            status: status
        )
    }

    private func oneSided(
        _ path: String,
        side: Side,
        kind: DirectoryEntryKind = .file
    ) -> DirectoryResult {
        let entry = metadata(path, kind: kind)
        return DirectoryResult(
            left: side == .left ? entry : nil,
            right: side == .right ? entry : nil,
            status: side == .left ? .leftOnly : .rightOnly
        )
    }

    private func typeMismatch(_ path: String) -> DirectoryResult {
        DirectoryResult(
            left: metadata(path, kind: .file),
            right: metadata(path, kind: .directory),
            status: .typeMismatch
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
        in bindings: [ComparedFileNavigationItemBinding]
    ) -> ComparedFileNavigationItemIdentity {
        let binding = bindings.first {
            exactOptionalUTF8($0.resultID.leftRelativePath, row.id.leftRelativePath)
                && exactOptionalUTF8($0.resultID.rightRelativePath, row.id.rightRelativePath)
        }
        guard let binding else {
            XCTFail("Missing exact item binding")
            return itemIdentity(Int.max)
        }
        return binding.identity
    }

    private func makeSnapshot(
        _ rows: [DirectoryResult],
        identity: ComparedFileFolderResultsIdentity = ComparedFileFolderResultsIdentity(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        ),
        revision: UInt64 = 10,
        generation: UInt64 = 20,
        bindings suppliedBindings: [ComparedFileNavigationItemBinding]? = nil,
        selectedIDs: Set<DirectoryResult.ID> = [],
        cursorResultID: DirectoryResult.ID? = nil,
        filter: DirectoryResultFilter = DirectoryResultFilter(),
        sortDescriptors: [DirectoryResultSortDescriptor] = [
            DirectoryResultSortDescriptor(key: .path)
        ],
        authorities: [ComparedFileNavigationRootAuthority]? = nil,
        openCapabilities: Set<ComparedFileNavigationOpenCapability>? = nil,
        limits: ComparedFileNavigationLimits = .default,
        leftRoot: URL? = nil,
        rightRoot: URL? = nil
    ) throws -> ComparedFileNavigationSnapshot {
        let leftRoot = leftRoot ?? self.leftRoot
        let rightRoot = rightRoot ?? self.rightRoot
        let results = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: rows,
            filter: filter,
            sortDescriptors: sortDescriptors,
            selectedIDs: selectedIDs
        )
        return try ComparedFileNavigationSnapshot(
            identity: identity,
            revision: revision,
            generation: generation,
            results: results,
            itemBindings: suppliedBindings ?? bindings(for: rows),
            cursorResultID: cursorResultID,
            authorities: authorities ?? fullAuthorities(leftRoot: leftRoot, rightRoot: rightRoot),
            openCapabilities: openCapabilities ?? allOpenCapabilities,
            limits: limits
        )
    }

    private func authority(
        _ side: ComparedFileNavigationSide,
        capabilities: Set<ComparedFileNavigationAuthorityCapability>? = nil
    ) -> ComparedFileNavigationRootAuthority {
        ComparedFileNavigationRootAuthority(
            identity: authorityIdentity(side == .left ? 1 : 2),
            side: side,
            rootURL: side == .left ? leftRoot : rightRoot,
            capabilities: capabilities ?? allAuthorityCapabilities
        )
    }

    private func fullAuthorities(
        leftRoot: URL? = nil,
        rightRoot: URL? = nil
    ) -> [ComparedFileNavigationRootAuthority] {
        [
            ComparedFileNavigationRootAuthority(
                identity: authorityIdentity(1),
                side: .left,
                rootURL: leftRoot ?? self.leftRoot,
                capabilities: allAuthorityCapabilities
            ),
            ComparedFileNavigationRootAuthority(
                identity: authorityIdentity(2),
                side: .right,
                rootURL: rightRoot ?? self.rightRoot,
                capabilities: allAuthorityCapabilities
            )
        ]
    }

    private func folderIdentity(_ value: Int) -> ComparedFileFolderResultsIdentity {
        ComparedFileFolderResultsIdentity(rawValue: uuid(value))
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

    private func limits(
        maximumItemCount: Int = ComparedFileNavigationLimits.default.maximumItemCount,
        maximumSortDescriptorCount: Int = ComparedFileNavigationLimits.default.maximumSortDescriptorCount,
        maximumStringUTF8Bytes: Int = ComparedFileNavigationLimits.default.maximumStringUTF8Bytes,
        maximumTotalStringUTF8Bytes: Int = ComparedFileNavigationLimits.default.maximumTotalStringUTF8Bytes,
        maximumWorkUnits: Int = ComparedFileNavigationLimits.default.maximumWorkUnits,
        cancellationCheckInterval: Int = ComparedFileNavigationLimits.default.cancellationCheckInterval
    ) -> ComparedFileNavigationLimits {
        ComparedFileNavigationLimits(
            maximumItemCount: maximumItemCount,
            maximumSortDescriptorCount: maximumSortDescriptorCount,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func minimumConstructionWork(
        rows: [DirectoryResult],
        bindings rowBindings: [ComparedFileNavigationItemBinding],
        filter: DirectoryResultFilter = DirectoryResultFilter(),
        sortDescriptors: [DirectoryResultSortDescriptor] = [],
        authorities: [ComparedFileNavigationRootAuthority] = []
    ) throws -> Int {
        var lower = 1
        var upper = 1
        while true {
            do {
                _ = try makeSnapshot(
                    rows,
                    bindings: rowBindings,
                    filter: filter,
                    sortDescriptors: sortDescriptors,
                    authorities: authorities,
                    limits: limits(maximumWorkUnits: upper)
                )
                break
            } catch ComparedFileNavigationError.workLimitExceeded {
                upper *= 2
            }
        }
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            do {
                _ = try makeSnapshot(
                    rows,
                    bindings: rowBindings,
                    filter: filter,
                    sortDescriptors: sortDescriptors,
                    authorities: authorities,
                    limits: limits(maximumWorkUnits: middle)
                )
                upper = middle
            } catch ComparedFileNavigationError.workLimitExceeded {
                lower = middle + 1
            }
        }
        return lower
    }

    private func assertConstructionBoundary(
        rows: [DirectoryResult],
        bindings rowBindings: [ComparedFileNavigationItemBinding],
        filter: DirectoryResultFilter = DirectoryResultFilter(),
        sortDescriptors: [DirectoryResultSortDescriptor] = [],
        exactWork: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNoThrow(
            try makeSnapshot(
                rows,
                bindings: rowBindings,
                filter: filter,
                sortDescriptors: sortDescriptors,
                authorities: [],
                limits: limits(maximumWorkUnits: exactWork)
            ),
            file: file,
            line: line
        )
        assertNavigationError(
            .workLimitExceeded(maximumWorkUnits: exactWork - 1),
            file: file,
            line: line
        ) {
            _ = try makeSnapshot(
                rows,
                bindings: rowBindings,
                filter: filter,
                sortDescriptors: sortDescriptors,
                authorities: [],
                limits: limits(maximumWorkUnits: exactWork - 1)
            )
        }
    }

    private func minimumQueryWork(
        _ operation: (ComparedFileNavigationSnapshot) throws -> Void
    ) throws -> Int {
        let rows = [pair("a.txt"), pair("b.txt"), pair("c.txt")]
        let rowBindings = bindings(for: rows)
        return try minimumWork { maximumWork in
            let snapshot = try makeSnapshot(
                rows,
                bindings: rowBindings,
                selectedIDs: [rows[1].id],
                limits: limits(maximumWorkUnits: maximumWork)
            )
            try operation(snapshot)
        }
    }

    private func assertQueryBoundary(
        exactWork: Int,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: (ComparedFileNavigationSnapshot) throws -> Void
    ) {
        let rows = [pair("a.txt"), pair("b.txt"), pair("c.txt")]
        let rowBindings = bindings(for: rows)
        do {
            let exact = try makeSnapshot(
                rows,
                bindings: rowBindings,
                selectedIDs: [rows[1].id],
                limits: limits(maximumWorkUnits: exactWork)
            )
            XCTAssertNoThrow(try operation(exact), file: file, line: line)
            assertNavigationError(
                .workLimitExceeded(maximumWorkUnits: exactWork - 1),
                file: file,
                line: line
            ) {
                let insufficient = try makeSnapshot(
                    rows,
                    bindings: rowBindings,
                    selectedIDs: [rows[1].id],
                    limits: limits(maximumWorkUnits: exactWork - 1)
                )
                try operation(insufficient)
            }
        } catch {
            XCTFail("Unable to construct query boundary snapshot: \(error)", file: file, line: line)
        }
    }

    private func assertEndToEndQueryBoundary(
        rows: [DirectoryResult],
        command: ComparedFileNavigationCommand,
        exactWork: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rowBindings = bindings(for: rows)
        XCTAssertNoThrow(
            try {
                let snapshot = try makeSnapshot(
                    rows,
                    bindings: rowBindings,
                    selectedIDs: [rows[1].id],
                    limits: limits(maximumWorkUnits: exactWork)
                )
                _ = try ComparedFileNavigation.plan(command, in: snapshot)
                _ = try ComparedFileNavigation.resolve(command, in: snapshot)
            }(),
            file: file,
            line: line
        )
        assertNavigationError(
            .workLimitExceeded(maximumWorkUnits: exactWork - 1),
            file: file,
            line: line
        ) {
            let snapshot = try makeSnapshot(
                rows,
                bindings: rowBindings,
                selectedIDs: [rows[1].id],
                limits: limits(maximumWorkUnits: exactWork - 1)
            )
            _ = try ComparedFileNavigation.plan(command, in: snapshot)
        }
    }

    private func minimumCurrentValidationWork(validateRequest: Bool) throws -> Int {
        let rows = [pair("a-long-name.txt"), pair("b-long-name.txt")]
        let rowBindings = bindings(for: rows)
        return try minimumWork { maximumWork in
            let snapshot = try makeSnapshot(
                rows,
                bindings: rowBindings,
                selectedIDs: [rows[0].id],
                limits: limits(maximumWorkUnits: maximumWork)
            )
            let plan = try ComparedFileNavigation.plan(.next, in: snapshot)
            if validateRequest {
                try XCTUnwrap(plan.openPairRequest).validate(against: snapshot)
            } else {
                try plan.validate(against: snapshot)
            }
        }
    }

    private func assertCurrentValidationBoundary(
        exactWork: Int,
        validateRequest: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rows = [pair("a-long-name.txt"), pair("b-long-name.txt")]
        let rowBindings = bindings(for: rows)
        do {
            let exact = try makeSnapshot(
                rows,
                bindings: rowBindings,
                selectedIDs: [rows[0].id],
                limits: limits(maximumWorkUnits: exactWork)
            )
            let exactPlan = try ComparedFileNavigation.plan(.next, in: exact)
            if validateRequest {
                XCTAssertNoThrow(
                    try XCTUnwrap(exactPlan.openPairRequest).validate(against: exact),
                    file: file,
                    line: line
                )
            } else {
                XCTAssertNoThrow(try exactPlan.validate(against: exact), file: file, line: line)
            }
            assertNavigationError(
                .workLimitExceeded(maximumWorkUnits: exactWork - 1),
                file: file,
                line: line
            ) {
                let insufficient = try makeSnapshot(
                    rows,
                    bindings: rowBindings,
                    selectedIDs: [rows[0].id],
                    limits: limits(maximumWorkUnits: exactWork - 1)
                )
                let insufficientPlan = try ComparedFileNavigation.plan(.next, in: insufficient)
                if validateRequest {
                    try XCTUnwrap(insufficientPlan.openPairRequest).validate(against: insufficient)
                } else {
                    try insufficientPlan.validate(against: insufficient)
                }
            }
        } catch {
            XCTFail("Unable to construct validation boundary snapshot: \(error)", file: file, line: line)
        }
    }

    private func minimumStaleOrderWork(rows: [DirectoryResult]) throws -> Int {
        let rowBindings = bindings(for: rows)
        return try minimumWork { maximumWork in
            let original = try makeSnapshot(
                rows,
                bindings: rowBindings,
                sortDescriptors: [],
                limits: limits(maximumWorkUnits: maximumWork)
            )
            let changed = try makeSnapshot(
                rows,
                bindings: rowBindings,
                sortDescriptors: [DirectoryResultSortDescriptor(key: .path, order: .descending)],
                limits: limits(maximumWorkUnits: maximumWork)
            )
            let plan = try ComparedFileNavigation.plan(.next, in: original)
            do {
                try plan.validate(against: changed)
                XCTFail("Expected stale order")
            } catch ComparedFileNavigationError.staleItemOrder {
                return
            }
        }
    }

    private func assertStaleOrderBoundary(
        rows: [DirectoryResult],
        exactWork: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rowBindings = bindings(for: rows)
        do {
            let exactOriginal = try makeSnapshot(
                rows,
                bindings: rowBindings,
                sortDescriptors: [],
                limits: limits(maximumWorkUnits: exactWork)
            )
            let exactChanged = try makeSnapshot(
                rows,
                bindings: rowBindings,
                sortDescriptors: [DirectoryResultSortDescriptor(key: .path, order: .descending)],
                limits: limits(maximumWorkUnits: exactWork)
            )
            let exactPlan = try ComparedFileNavigation.plan(.next, in: exactOriginal)
            assertNavigationError(.staleItemOrder, file: file, line: line) {
                try exactPlan.validate(against: exactChanged)
            }
            assertNavigationError(
                .workLimitExceeded(maximumWorkUnits: exactWork - 1),
                file: file,
                line: line
            ) {
                let insufficientOriginal = try makeSnapshot(
                    rows,
                    bindings: rowBindings,
                    sortDescriptors: [],
                    limits: limits(maximumWorkUnits: exactWork - 1)
                )
                let insufficientChanged = try makeSnapshot(
                    rows,
                    bindings: rowBindings,
                    sortDescriptors: [
                        DirectoryResultSortDescriptor(key: .path, order: .descending)
                    ],
                    limits: limits(maximumWorkUnits: exactWork - 1)
                )
                try ComparedFileNavigation.plan(.next, in: insufficientOriginal).validate(
                    against: insufficientChanged
                )
            }
        } catch {
            XCTFail("Unable to construct stale boundary snapshots: \(error)", file: file, line: line)
        }
    }

    private func minimumWork(_ operation: (Int) throws -> Void) throws -> Int {
        var lower = 1
        var upper = 1
        while true {
            do {
                try operation(upper)
                break
            } catch ComparedFileNavigationError.workLimitExceeded {
                upper *= 2
            }
        }
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            do {
                try operation(middle)
                upper = middle
            } catch ComparedFileNavigationError.workLimitExceeded {
                lower = middle + 1
            }
        }
        return lower
    }

    private func exactOptionalUTF8(_ left: String?, _ right: String?) -> Bool {
        switch (left, right) {
        case (nil, nil): true
        case (let left?, let right?): left.utf8.elementsEqual(right.utf8)
        default: false
        }
    }

    private func assertItem(
        _ item: ComparedFileNavigationItem,
        state: ComparedFileNavigationComparisonState,
        visibility: ComparedFileNavigationVisibility,
        reason: ComparedFileNavigationItemUnavailabilityReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(item.comparisonState, state, file: file, line: line)
        XCTAssertEqual(item.visibility, visibility, file: file, line: line)
        assertUnavailable(item, reason, file: file, line: line)
    }

    private func assertItem(
        _ item: ComparedFileNavigationItem,
        state: ComparedFileNavigationComparisonState,
        visibility: ComparedFileNavigationVisibility,
        capability: ComparedFileNavigationOpenCapability,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(item.comparisonState, state, file: file, line: line)
        XCTAssertEqual(item.visibility, visibility, file: file, line: line)
        XCTAssertEqual(item.availability, .available(requiredCapability: capability), file: file, line: line)
        XCTAssertTrue(item.availability.isAvailable, file: file, line: line)
        XCTAssertEqual(item.availability.requiredCapability, capability, file: file, line: line)
        XCTAssertNil(item.availability.unavailableReason, file: file, line: line)
    }

    private func assertUnavailable(
        _ item: ComparedFileNavigationItem,
        _ reason: ComparedFileNavigationItemUnavailabilityReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(item.availability, .unavailable(reason), file: file, line: line)
        XCTAssertFalse(item.availability.isAvailable, file: file, line: line)
        XCTAssertNil(item.availability.requiredCapability, file: file, line: line)
        XCTAssertEqual(item.availability.unavailableReason, reason, file: file, line: line)
    }

    private func assertDisabled(
        _ plan: ComparedFileNavigationPlan,
        _ reason: ComparedFileNavigationDisabledReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(plan.isEnabled, file: file, line: line)
        XCTAssertFalse(plan.canExecute, file: file, line: line)
        XCTAssertNil(plan.targetItemIdentity, file: file, line: line)
        XCTAssertEqual(plan.disabledReason, reason, file: file, line: line)
        XCTAssertEqual(plan.commandState.availabilityReason, .disabled(reason), file: file, line: line)
        XCTAssertNil(plan.openPairRequest, file: file, line: line)
    }

    private func assertOpenSide(
        _ request: ComparedFileNavigationOpenSideRequest,
        side: ComparedFileNavigationSide,
        presence: ComparedFileNavigationOpenItemPresence,
        rootURL: URL,
        path: String,
        authorityIdentity: ComparedFileNavigationAuthorityIdentity,
        capability: ComparedFileNavigationAuthorityCapability,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(request.side, side, file: file, line: line)
        XCTAssertEqual(request.presence, presence, file: file, line: line)
        assertExactUTF8(request.rootURL.absoluteString, rootURL.absoluteString, file: file, line: line)
        assertExactUTF8(request.relativePath, path, file: file, line: line)
        XCTAssertEqual(request.authorityIdentity, authorityIdentity, file: file, line: line)
        XCTAssertEqual(request.requiredAuthorityCapability, capability, file: file, line: line)
    }

    private func assertExactID(
        _ actual: DirectoryResult.ID,
        _ expected: DirectoryResult.ID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertExactOptionalUTF8(actual.leftRelativePath, expected.leftRelativePath, file: file, line: line)
        assertExactOptionalUTF8(actual.rightRelativePath, expected.rightRelativePath, file: file, line: line)
    }

    private func assertExactIDs(
        _ actual: [DirectoryResult.ID],
        _ expected: [DirectoryResult.ID],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actual, expected) in zip(actual, expected) {
            assertExactID(actual, expected, file: file, line: line)
        }
    }

    private func assertExactMetadata(
        _ actual: DirectoryEntryMetadata?,
        _ expected: DirectoryEntryMetadata?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (nil, nil):
            break
        case (let actual?, let expected?):
            assertExactUTF8(actual.relativePath, expected.relativePath, file: file, line: line)
            XCTAssertEqual(actual.kind, expected.kind, file: file, line: line)
            XCTAssertEqual(actual.byteCount, expected.byteCount, file: file, line: line)
            XCTAssertEqual(
                actual.modificationDate?.timeIntervalSinceReferenceDate.bitPattern,
                expected.modificationDate?.timeIntervalSinceReferenceDate.bitPattern,
                file: file,
                line: line
            )
            XCTAssertEqual(actual.isHidden, expected.isHidden, file: file, line: line)
        default:
            XCTFail("Metadata optional shape differs", file: file, line: line)
        }
    }

    private func assertExactOptionalUTF8(
        _ actual: String?,
        _ expected: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (nil, nil):
            break
        case (let actual?, let expected?):
            assertExactUTF8(actual, expected, file: file, line: line)
        default:
            XCTFail("String optional shape differs", file: file, line: line)
        }
    }

    private func assertExactUTF8(
        _ actual: String,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Array(actual.utf8), Array(expected.utf8), file: file, line: line)
    }

    private func assertNavigationError(
        _ expected: ComparedFileNavigationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ComparedFileNavigationError, expected, file: file, line: line)
        }
    }

}

private func captureComparedFileNavigationError(
    _ operation: () throws -> Void
) -> ComparedFileNavigationError? {
    do {
        try operation()
        return nil
    } catch {
        return error as? ComparedFileNavigationError
    }
}

private enum ComparedFileNavigationCancellationOutcome: Equatable, Sendable {
    case succeeded
    case cancelled
    case failed(String)
}
