import Foundation
import MacMergeCore
import XCTest

final class TableWorkspaceAdoptionTests: XCTestCase {
    func testSnapshotBindsComparisonReceiptAndState() async throws {
        let fixture = try await makeFixture()
        let snapshot = TableWorkspaceAdoption.Snapshot(
            comparisonReceipt: fixture.receipt,
            state: fixture.state
        )

        XCTAssertEqual(snapshot.comparisonReceipt, fixture.receipt)
        XCTAssertEqual(snapshot.state, fixture.state)
        XCTAssertEqual(snapshot.dataset, fixture.dataset)
        XCTAssertEqual(snapshot.result, fixture.receipt.result)
    }

    func testPlanBindsSnapshotRevisionsAndRequiresContract() async throws {
        let fixture = try await makeFixture()
        let snapshot = fixture.snapshot()
        let routed = try TableWorkspaceAdoption.plan(snapshot)

        XCTAssertEqual(routed.expectedDataset, fixture.dataset)
        XCTAssertEqual(routed.expectedState, fixture.state)
        XCTAssertEqual(routed.plan.executorContract, .required)
        XCTAssertEqual(routed.presentation, routed.plan.presentation)
        XCTAssertNil(routed.editIntent)
        XCTAssertEqual(routed.presentation.datasetReference, fixture.dataset.reference)
    }

    func testPlanProjectsHeadersFiltersSettingsAndSelection() async throws {
        let fixture = try await makeFixture()
        let options = TableWorkspacePresentationOptions(
            headerVisibility: .hidden,
            headerLabels: .firstRecord,
            showsRowNumbers: false,
            wrapsCellText: true,
            synchronizesColumnWidths: false,
            highlightsCellDifferences: false
        )
        let selection = TableWorkspaceSelection.cells(anchor: address(0, 0), focus: address(0, 1))
        let include = TableWorkspaceColumnFilter(
            identifier: "removed",
            columnIndex: 0,
            condition: .status(.removed)
        )
        let state = makeState(
            dataset: fixture.dataset,
            options: options,
            filters: [include],
            selection: selection
        )
        let routed = try TableWorkspaceAdoption.plan(fixture.snapshot(state: state))

        XCTAssertEqual(routed.presentation.options, options)
        XCTAssertEqual(routed.presentation.selection, selection)
        XCTAssertEqual(
            routed.presentation.columns.map(\.label),
            [
                .firstRecord(left: "name", right: "name"),
                .firstRecord(left: "value", right: "value"),
                .firstRecord(left: nil, right: nil)
            ]
        )
        XCTAssertEqual(
            routed.presentation.rows.map(\.isVisible),
            [false, true, false, false, false, false, false]
        )
        XCTAssertEqual(routed.presentation.visibleRowCount, 1)
        XCTAssertEqual(routed.presentation.columns[0].filters, [include])
    }

    func testPlanHonorsNondefaultDelimiterSettings() async throws {
        let fixture = try await makeFixture(
            left: "a|b",
            right: "a|c",
            configuration: pipeConfiguration()
        )
        let routed = try TableWorkspaceAdoption.plan(fixture.snapshot())

        XCTAssertEqual(routed.presentation.rows.count, 1)
        XCTAssertEqual(routed.presentation.rows[0].cells.map(\.status), [.equal, .modified])
    }

    func testEditRequestProducesExactCASIntent() async throws {
        let fixture = try await makeFixture()
        let edit = editRequest(
            side: .left,
            row: 3,
            column: 0,
            expected: "old",
            replacement: "newer"
        )
        let routed = try TableWorkspaceAdoption.plan(
            fixture.snapshot(),
            editRequest: edit
        )
        let intent = try XCTUnwrap(routed.editIntent)
        let sourceCell = fixture.receipt.result.left.rows[3].cells[0]

        XCTAssertEqual(intent.datasetReference, fixture.dataset.reference)
        XCTAssertEqual(intent.source, fixture.dataset.source(.left))
        XCTAssertEqual(intent.presentationAddress, address(3, 0))
        XCTAssertEqual(intent.sourceRowIndex, 3)
        XCTAssertEqual(intent.sourceColumnIndex, 0)
        XCTAssertEqual(intent.sourceUTF8Range, sourceCell.sourceUTF8Range)
        XCTAssertEqual(intent.expectedPresentedValue, "old")
        XCTAssertEqual(intent.replacementPresentedValue, "newer")
    }

    func testEditRequestRejectsStaleExpectedAndNoChangeValue() async throws {
        let fixture = try await makeFixture()

        assertAdoptionError(.policy(.editExpectedValueChanged)) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(),
                editRequest: editRequest(
                    side: .left,
                    row: 3,
                    column: 0,
                    expected: "stale",
                    replacement: "new"
                )
            )
        }
        assertAdoptionError(.policy(.editWouldNotChangeValue)) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(),
                editRequest: editRequest(
                    side: .left,
                    row: 3,
                    column: 0,
                    expected: "old",
                    replacement: "old"
                )
            )
        }
    }

    func testRequireCurrentAcceptsFreshAndRejectsStaleState() async throws {
        let fixture = try await makeFixture()
        let snapshot = fixture.snapshot()
        let routed = try TableWorkspaceAdoption.plan(snapshot)

        XCTAssertNoThrow(try TableWorkspaceAdoption.requireCurrent(routed, currentSnapshot: snapshot))

        let reselected = makeState(dataset: fixture.dataset, selection: .column(0))
        assertAdoptionError(.staleState) {
            try TableWorkspaceAdoption.requireCurrent(
                routed,
                currentSnapshot: fixture.snapshot(state: reselected)
            )
        }

        let refiltered = makeState(
            dataset: fixture.dataset,
            filters: [statusFilter(identifier: "late")]
        )
        assertAdoptionError(.staleState) {
            try TableWorkspaceAdoption.requireCurrent(
                routed,
                currentSnapshot: fixture.snapshot(state: refiltered)
            )
        }
    }

    func testRequireCurrentRejectsStaleDatasetRevision() async throws {
        let fixture = try await makeFixture()
        let routed = try TableWorkspaceAdoption.plan(fixture.snapshot())
        let advanced = copyDataset(
            fixture.dataset,
            reference: TableWorkspaceDatasetReference(
                identity: fixture.dataset.reference.identity,
                revision: fixture.dataset.reference.revision + 1
            )
        )
        let advancedReceipt = try await AdoptionExecutor(
            sourceData: [.left: Data(fixture.left.utf8), .right: Data(fixture.right.utf8)]
        ).compare(dataset: advanced)
        let current = TableWorkspaceAdoption.Snapshot(
            comparisonReceipt: advancedReceipt,
            state: makeState(dataset: advanced)
        )

        assertAdoptionError(
            .staleSnapshot(expected: fixture.dataset.reference, actual: advanced.reference)
        ) {
            try TableWorkspaceAdoption.requireCurrent(routed, currentSnapshot: current)
        }
    }

    func testValidateAcceptsAtomicRevisionAdvanceWithCurrentSnapshot() async throws {
        let fixture = try await makeFixture()
        let snapshot = fixture.snapshot()
        let edit = editRequest(
            side: .left,
            row: 3,
            column: 0,
            expected: "old",
            replacement: "newer"
        )
        let routed = try TableWorkspaceAdoption.plan(snapshot, editRequest: edit)
        let intent = try XCTUnwrap(routed.editIntent)
        let result = validResultingDataset(from: fixture.dataset, editedSide: .left)
        let receipt = try await AdoptionExecutor(sourceData: [:], publication: result)
            .execute(intent)

        XCTAssertEqual(
            try TableWorkspaceAdoption.validate(receipt, for: routed, currentSnapshot: snapshot),
            result
        )
    }

    func testValidateRejectsStaleCurrentBeforeReceiptChecks() async throws {
        let fixture = try await makeFixture()
        let snapshot = fixture.snapshot()
        let edit = editRequest(
            side: .left,
            row: 3,
            column: 0,
            expected: "old",
            replacement: "newer"
        )
        let routed = try TableWorkspaceAdoption.plan(snapshot, editRequest: edit)
        let intent = try XCTUnwrap(routed.editIntent)
        let result = validResultingDataset(from: fixture.dataset, editedSide: .left)
        let receipt = try await AdoptionExecutor(sourceData: [:], publication: result)
            .execute(intent)

        let reselected = makeState(dataset: fixture.dataset, selection: .column(0))
        assertAdoptionError(.staleState) {
            _ = try TableWorkspaceAdoption.validate(
                receipt,
                for: routed,
                currentSnapshot: fixture.snapshot(state: reselected)
            )
        }

        let advanced = copyDataset(
            fixture.dataset,
            reference: TableWorkspaceDatasetReference(
                identity: fixture.dataset.reference.identity,
                revision: fixture.dataset.reference.revision + 1
            )
        )
        let advancedReceipt = try await AdoptionExecutor(
            sourceData: [.left: Data(fixture.left.utf8), .right: Data(fixture.right.utf8)]
        ).compare(dataset: advanced)
        let advancedCurrent = TableWorkspaceAdoption.Snapshot(
            comparisonReceipt: advancedReceipt,
            state: makeState(dataset: advanced)
        )
        assertAdoptionError(
            .staleSnapshot(expected: fixture.dataset.reference, actual: advanced.reference)
        ) {
            _ = try TableWorkspaceAdoption.validate(
                receipt,
                for: routed,
                currentSnapshot: advancedCurrent
            )
        }
    }

    func testPersistenceRoundTripsStateThroughAdoption() throws {
        let dataset = try makeDataset(left: "a,b,c", right: "x,y,z")
        let options = TableWorkspacePresentationOptions(
            headerVisibility: .hidden,
            headerLabels: .firstRecord,
            showsRowNumbers: false,
            wrapsCellText: true,
            synchronizesColumnWidths: false,
            highlightsCellDifferences: false
        )
        let filters = [
            TableWorkspaceColumnFilter(
                identifier: "status",
                columnIndex: 0,
                condition: .status(.modified)
            ),
            TableWorkspaceColumnFilter(
                identifier: "value",
                columnIndex: 1,
                condition: .valueEquals(side: .right, value: "y"),
                disposition: .excludeMatchingRows
            )
        ]
        let selection = TableWorkspaceSelection.cells(anchor: address(0, 0), focus: address(0, 2))
        let state = makeState(
            dataset: dataset,
            options: options,
            filters: filters,
            selection: selection
        )

        let encoded = try TableWorkspaceAdoption.encode(state)
        let decoded = try TableWorkspaceAdoption.decode(encoded.data)

        XCTAssertEqual(encoded.state, state)
        XCTAssertEqual(decoded.state, state)
        XCTAssertEqual(decoded.data, encoded.data)
        XCTAssertEqual(decoded.formatVersion, TableWorkspaceState.currentSchemaVersion)
    }

    func testEncodeDecodeEnforcesLimitsCancellationAndMalformedData() throws {
        let dataset = try makeDataset(left: "a,b", right: "x,y")
        let state = makeState(dataset: dataset, selection: .column(1))
        let data = try TableWorkspaceAdoption.encode(state).data
        let small = policyLimits(maximumPersistedBytes: data.count - 1)

        assertAdoptionError(.policy(.persistenceDataTooLarge(maximumBytes: data.count - 1))) {
            _ = try TableWorkspaceAdoption.encode(state, limits: small)
        }
        assertAdoptionError(.policy(.persistenceDataTooLarge(maximumBytes: data.count - 1))) {
            _ = try TableWorkspaceAdoption.decode(data, limits: small)
        }

        let cancellation: @Sendable () throws -> Void = { throw CancellationError() }
        assertAdoptionError(.cancelled) {
            _ = try TableWorkspaceAdoption.encode(state, cancellationCheck: cancellation)
        }
        assertAdoptionError(.cancelled) {
            _ = try TableWorkspaceAdoption.decode(data, cancellationCheck: cancellation)
        }
        assertAdoptionError(.policy(.malformedPersistence)) {
            _ = try TableWorkspaceAdoption.decode(Data([0x00]))
        }
    }

    func testPlanEnforcesLimitsAndCancellation() async throws {
        let fixture = try await makeFixture()

        assertAdoptionError(.policy(.tooManyRows(maximum: 1))) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(),
                limits: policyLimits(maximumRows: 1)
            )
        }
        assertAdoptionError(.policy(.invalidLimit(.rows))) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(),
                limits: policyLimits(maximumRows: -1)
            )
        }

        let cancellation: @Sendable () throws -> Void = { throw CancellationError() }
        assertAdoptionError(.cancelled) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(),
                cancellationCheck: cancellation
            )
        }
    }

    func testAvailabilityReadyAndRejectsIdentityRevisionBindingConfiguration() async throws {
        let fixture = try await makeFixture()
        XCTAssertEqual(TableWorkspaceAdoption.availability(in: fixture.snapshot()), .ready)

        let foreignReference = TableWorkspaceDatasetReference(
            identity: datasetIdentity(99),
            revision: fixture.dataset.reference.revision
        )
        XCTAssertEqual(
            TableWorkspaceAdoption.availability(
                in: fixture.snapshot(
                    state: makeState(dataset: fixture.dataset, reference: foreignReference)
                )
            ),
            .disabled(.stateForAnotherDataset)
        )
        assertAdoptionError(
            .staleSnapshot(expected: fixture.dataset.reference, actual: foreignReference)
        ) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(
                    state: makeState(dataset: fixture.dataset, reference: foreignReference)
                )
            )
        }

        let staleReference = TableWorkspaceDatasetReference(
            identity: fixture.dataset.reference.identity,
            revision: fixture.dataset.reference.revision - 1
        )
        XCTAssertEqual(
            TableWorkspaceAdoption.availability(
                in: fixture.snapshot(
                    state: makeState(dataset: fixture.dataset, reference: staleReference)
                )
            ),
            .disabled(
                .staleState(
                    expectedRevision: fixture.dataset.reference.revision,
                    actualRevision: staleReference.revision
                )
            )
        )
        assertAdoptionError(
            .staleSnapshot(expected: fixture.dataset.reference, actual: staleReference)
        ) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(
                    state: makeState(dataset: fixture.dataset, reference: staleReference)
                )
            )
        }

        let changedLeft = copyBinding(
            try XCTUnwrap(fixture.dataset.source(.left)),
            sourceRevision: 99
        )
        XCTAssertEqual(
            TableWorkspaceAdoption.availability(
                in: fixture.snapshot(
                    state: makeState(
                        dataset: fixture.dataset,
                        sources: [changedLeft, try XCTUnwrap(fixture.dataset.source(.right))]
                    )
                )
            ),
            .disabled(.sourceBindingChanged(.left))
        )
        assertAdoptionError(.policy(.sourceBindingChanged(.left))) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(
                    state: makeState(
                        dataset: fixture.dataset,
                        sources: [changedLeft, try XCTUnwrap(fixture.dataset.source(.right))]
                    )
                )
            )
        }

        let changedConfiguration = pipeConfiguration()
        XCTAssertEqual(
            TableWorkspaceAdoption.availability(
                in: fixture.snapshot(
                    state: makeState(
                        dataset: fixture.dataset,
                        configuration: changedConfiguration
                    )
                )
            ),
            .disabled(.configurationChanged)
        )
        assertAdoptionError(.policy(.configurationChanged)) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(
                    state: makeState(
                        dataset: fixture.dataset,
                        configuration: changedConfiguration
                    )
                )
            )
        }
    }

    func testAvailabilityRejectsCanonicalSourceCountsAndDuplicates() async throws {
        let fixture = try await makeFixture()
        let left = try XCTUnwrap(fixture.dataset.source(.left))

        XCTAssertEqual(
            TableWorkspaceAdoption.availability(
                in: fixture.snapshot(state: makeState(dataset: fixture.dataset, sources: [left]))
            ),
            .disabled(.sourceCountInvalid(1))
        )
        assertAdoptionError(.policy(.sourceCountInvalid(1))) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(state: makeState(dataset: fixture.dataset, sources: [left]))
            )
        }

        let duplicate = [left, copyBinding(left, sourceRevision: 2)]
        XCTAssertEqual(
            TableWorkspaceAdoption.availability(
                in: fixture.snapshot(
                    state: makeState(dataset: fixture.dataset, sources: duplicate)
                )
            ),
            .disabled(.duplicateSide(.left))
        )
        assertAdoptionError(.policy(.duplicateSide(.left))) {
            _ = try TableWorkspaceAdoption.plan(
                fixture.snapshot(state: makeState(dataset: fixture.dataset, sources: duplicate))
            )
        }
    }

    func testAvailabilityForEditRejectsReadOnlyAfterCoherence() async throws {
        let fixture = try await makeFixture()
        XCTAssertEqual(
            TableWorkspaceAdoption.availabilityForEdit(.left, in: fixture.snapshot()),
            .ready
        )

        let readOnly = try await makeFixture(leftEditable: false)
        XCTAssertEqual(TableWorkspaceAdoption.availability(in: readOnly.snapshot()), .ready)
        XCTAssertEqual(
            TableWorkspaceAdoption.availabilityForEdit(.left, in: readOnly.snapshot()),
            .disabled(.readOnly(.left))
        )
        XCTAssertEqual(
            TableWorkspaceAdoption.availabilityForEdit(.right, in: readOnly.snapshot()),
            .ready
        )

        let stale = makeState(
            dataset: readOnly.dataset,
            reference: TableWorkspaceDatasetReference(
                identity: readOnly.dataset.reference.identity,
                revision: readOnly.dataset.reference.revision - 1
            )
        )
        XCTAssertEqual(
            TableWorkspaceAdoption.availabilityForEdit(.left, in: readOnly.snapshot(state: stale)),
            .disabled(
                .staleState(
                    expectedRevision: readOnly.dataset.reference.revision,
                    actualRevision: stale.datasetReference.revision
                )
            )
        )
    }

    func testAdoptionErrorsAreHashableAndDescribeGuards() async throws {
        let fixture = try await makeFixture()
        let reference = fixture.dataset.reference
        let errors: [TableWorkspaceAdoptionError] = [
            .cancelled,
            .staleSnapshot(expected: reference, actual: reference),
            .staleState,
            .executorContractMismatch,
            .policy(.cancelled),
            .policy(.sourceBindingChanged(.left))
        ]

        XCTAssertEqual(Set(errors).count, errors.count)
        XCTAssertTrue(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
        requireAdoptionSendable(errors)
    }

    private struct Fixture: Sendable {
        let left: String
        let right: String
        let dataset: TableWorkspaceDatasetSnapshot
        let state: TableWorkspaceState
        let receipt: TableWorkspaceComparisonReceipt

        func snapshot(state: TableWorkspaceState? = nil) -> TableWorkspaceAdoption.Snapshot {
            TableWorkspaceAdoption.Snapshot(
                comparisonReceipt: receipt,
                state: state ?? self.state
            )
        }
    }

    private func makeFixture(
        left: String = "name,value\nremove,left\nanchor,one\nold,keep\nanchor,two\ntail,end",
        right: String = "name,value\nanchor,one\nnew,keep,extra\nanchor,two\nadd,right\ntail,end",
        configuration: TableWorkspaceConfiguration = .default,
        leftEditable: Bool = true,
        rightEditable: Bool = true
    ) async throws -> Fixture {
        let dataset = try makeDataset(
            left: left,
            right: right,
            configuration: configuration,
            leftEditable: leftEditable,
            rightEditable: rightEditable
        )
        let executor = AdoptionExecutor(
            sourceData: [.left: Data(left.utf8), .right: Data(right.utf8)]
        )
        return Fixture(
            left: left,
            right: right,
            dataset: dataset,
            state: makeState(dataset: dataset),
            receipt: try await executor.compare(dataset: dataset)
        )
    }

    private func makeDataset(
        left: String,
        right: String,
        configuration: TableWorkspaceConfiguration = .default,
        leftEditable: Bool = true,
        rightEditable: Bool = true
    ) throws -> TableWorkspaceDatasetSnapshot {
        makeDataset(
            sources: [
                try makeBinding(
                    side: .left,
                    input: left,
                    configuration: configuration,
                    isEditable: leftEditable,
                    identitySeed: 1
                ),
                try makeBinding(
                    side: .right,
                    input: right,
                    configuration: configuration,
                    isEditable: rightEditable,
                    identitySeed: 2
                )
            ],
            configuration: configuration
        )
    }

    private func makeDataset(
        sources: [TableWorkspaceSourceBinding],
        configuration: TableWorkspaceConfiguration = .default,
        reference: TableWorkspaceDatasetReference = makeReference()
    ) -> TableWorkspaceDatasetSnapshot {
        TableWorkspaceDatasetSnapshot(
            reference: reference,
            configuration: configuration,
            sources: sources
        )
    }

    private func makeBinding(
        side: TableWorkspaceSide,
        input: String,
        configuration: TableWorkspaceConfiguration = .default,
        isEditable: Bool = true,
        revision: UInt64 = 1,
        identitySeed: UInt8 = 1
    ) throws -> TableWorkspaceSourceBinding {
        let table = try DelimitedTableParser.parse(
            input,
            options: configuration.format.parsingOptions
        )
        return TableWorkspaceSourceBinding(
            side: side,
            sourceIdentity: sourceIdentity(identitySeed),
            sourceRevision: revision,
            tableIdentity: tableIdentity(identitySeed),
            tableRevision: revision,
            shape: TableWorkspaceTableShape(
                sourceUTF8ByteCount: table.sourceUTF8ByteCount,
                rowCount: table.rows.count,
                maximumColumnCount: table.rows.map(\.cells.count).max() ?? 0,
                totalCellCount: table.totalCellCount
            ),
            isEditable: isEditable
        )
    }

    private func makeState(
        dataset: TableWorkspaceDatasetSnapshot,
        reference: TableWorkspaceDatasetReference? = nil,
        sources: [TableWorkspaceSourceBinding]? = nil,
        configuration: TableWorkspaceConfiguration? = nil,
        options: TableWorkspacePresentationOptions = .default,
        filters: [TableWorkspaceColumnFilter] = [],
        selection: TableWorkspaceSelection = .none
    ) -> TableWorkspaceState {
        TableWorkspaceState(
            datasetReference: reference ?? dataset.reference,
            sources: sources ?? dataset.sources,
            configuration: configuration ?? dataset.configuration,
            presentationOptions: options,
            columnFilters: filters,
            selection: selection
        )
    }

    private func copyDataset(
        _ dataset: TableWorkspaceDatasetSnapshot,
        reference: TableWorkspaceDatasetReference? = nil,
        configuration: TableWorkspaceConfiguration? = nil,
        sources: [TableWorkspaceSourceBinding]? = nil
    ) -> TableWorkspaceDatasetSnapshot {
        TableWorkspaceDatasetSnapshot(
            reference: reference ?? dataset.reference,
            configuration: configuration ?? dataset.configuration,
            sources: sources ?? dataset.sources
        )
    }

    private func copyBinding(
        _ binding: TableWorkspaceSourceBinding,
        sourceRevision: UInt64? = nil
    ) -> TableWorkspaceSourceBinding {
        TableWorkspaceSourceBinding(
            side: binding.side,
            sourceIdentity: binding.sourceIdentity,
            sourceRevision: sourceRevision ?? binding.sourceRevision,
            tableIdentity: binding.tableIdentity,
            tableRevision: binding.tableRevision,
            shape: binding.shape,
            isEditable: binding.isEditable
        )
    }

    private func validResultingDataset(
        from dataset: TableWorkspaceDatasetSnapshot,
        editedSide: TableWorkspaceSide
    ) -> TableWorkspaceDatasetSnapshot {
        let sources = dataset.sources.map { binding in
            guard binding.side == editedSide else { return binding }
            return TableWorkspaceSourceBinding(
                side: binding.side,
                sourceIdentity: binding.sourceIdentity,
                sourceRevision: binding.sourceRevision + 1,
                tableIdentity: binding.tableIdentity,
                tableRevision: binding.tableRevision + 1,
                shape: TableWorkspaceTableShape(
                    sourceUTF8ByteCount: binding.shape.sourceUTF8ByteCount + 1,
                    rowCount: binding.shape.rowCount,
                    maximumColumnCount: binding.shape.maximumColumnCount,
                    totalCellCount: binding.shape.totalCellCount
                ),
                isEditable: binding.isEditable
            )
        }
        return copyDataset(
            dataset,
            reference: TableWorkspaceDatasetReference(
                identity: dataset.reference.identity,
                revision: dataset.reference.revision + 1
            ),
            sources: sources
        )
    }

    private func pipeConfiguration() -> TableWorkspaceConfiguration {
        TableWorkspaceConfiguration(format: TableWorkspaceFormatSettings(delimiter: "|"))
    }

    private func policyLimits(
        maximumRows: Int = 2_097_152,
        maximumPersistedBytes: Int = 64 * 1_024 * 1_024
    ) -> TableWorkspacePolicyLimits {
        TableWorkspacePolicyLimits(
            maximumRows: maximumRows,
            maximumPersistedBytes: maximumPersistedBytes
        )
    }

    private func statusFilter(identifier: String) -> TableWorkspaceColumnFilter {
        TableWorkspaceColumnFilter(
            identifier: identifier,
            columnIndex: 0,
            condition: .status(.equal)
        )
    }

    private func editRequest(
        side: TableWorkspaceSide,
        row: Int,
        column: Int,
        expected: String,
        replacement: String
    ) -> TableWorkspaceEditRequest {
        TableWorkspaceEditRequest(
            side: side,
            address: address(row, column),
            expectedPresentedValue: expected,
            replacementPresentedValue: replacement
        )
    }

    private func assertAdoptionError(
        _ expected: TableWorkspaceAdoptionError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? TableWorkspaceAdoptionError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func requireAdoptionSendable<T: Sendable>(_: T) {}
}

private struct AdoptionExecutor: TableWorkspaceExecutor, Sendable {
    let sourceData: [TableWorkspaceSide: Data]
    let publication: TableWorkspaceDatasetSnapshot?

    init(
        sourceData: [TableWorkspaceSide: Data],
        publication: TableWorkspaceDatasetSnapshot? = nil
    ) {
        self.sourceData = sourceData
        self.publication = publication
    }

    func sourceUTF8Bytes(
        for source: TableWorkspaceSourceBinding,
        in _: TableWorkspaceDatasetSnapshot
    ) async throws -> Data {
        guard let data = sourceData[source.side] else { throw AdoptionExecutorError.missingSource }
        return data
    }

    func publish(_: TableWorkspaceEditIntent) async throws -> TableWorkspaceDatasetSnapshot {
        guard let publication else { throw AdoptionExecutorError.missingPublication }
        return publication
    }
}

private enum AdoptionExecutorError: Error {
    case missingSource
    case missingPublication
}

private func address(_ row: Int, _ column: Int) -> TableWorkspaceCellAddress {
    TableWorkspaceCellAddress(rowIndex: row, columnIndex: column)
}

private func makeReference(
    identitySeed: UInt8 = 1,
    revision: UInt64 = 7
) -> TableWorkspaceDatasetReference {
    TableWorkspaceDatasetReference(identity: datasetIdentity(identitySeed), revision: revision)
}

private func datasetIdentity(_ seed: UInt8) -> TableWorkspaceDatasetIdentity {
    TableWorkspaceDatasetIdentity(rawValue: seededUUID(seed))
}

private func sourceIdentity(_ seed: UInt8) -> TableWorkspaceSourceIdentity {
    TableWorkspaceSourceIdentity(rawValue: seededUUID(seed &+ 64))
}

private func tableIdentity(_ seed: UInt8) -> TableWorkspaceTableIdentity {
    TableWorkspaceTableIdentity(rawValue: seededUUID(seed &+ 128))
}

private func seededUUID(_ seed: UInt8) -> UUID {
    UUID(uuid: (seed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, seed))
}
