import Foundation

public enum TableWorkspaceSide: String, CaseIterable, Hashable, Sendable {
    case left
    case right
}

public struct TableWorkspaceDatasetIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct TableWorkspaceSourceIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct TableWorkspaceTableIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct TableWorkspaceDatasetReference: Hashable, Sendable {
    public let identity: TableWorkspaceDatasetIdentity
    public let revision: UInt64

    /// Owners must increase `revision` whenever any bound source, table, or configuration changes.
    public init(identity: TableWorkspaceDatasetIdentity, revision: UInt64) {
        self.identity = identity
        self.revision = revision
    }
}

public struct TableWorkspaceTableShape: Hashable, Sendable {
    public let sourceUTF8ByteCount: Int
    public let rowCount: Int
    public let maximumColumnCount: Int
    public let totalCellCount: Int

    public init(
        sourceUTF8ByteCount: Int,
        rowCount: Int,
        maximumColumnCount: Int,
        totalCellCount: Int
    ) {
        self.sourceUTF8ByteCount = sourceUTF8ByteCount
        self.rowCount = rowCount
        self.maximumColumnCount = maximumColumnCount
        self.totalCellCount = totalCellCount
    }
}

/// Owner-issued binding for one immutable source and its parsed table. Revisions must increase for
/// different bytes, parser settings, or table contents.
public struct TableWorkspaceSourceBinding: Hashable, Sendable {
    public let side: TableWorkspaceSide
    public let sourceIdentity: TableWorkspaceSourceIdentity
    public let sourceRevision: UInt64
    public let tableIdentity: TableWorkspaceTableIdentity
    public let tableRevision: UInt64
    public let shape: TableWorkspaceTableShape
    public let isEditable: Bool

    public init(
        side: TableWorkspaceSide,
        sourceIdentity: TableWorkspaceSourceIdentity,
        sourceRevision: UInt64,
        tableIdentity: TableWorkspaceTableIdentity,
        tableRevision: UInt64,
        shape: TableWorkspaceTableShape,
        isEditable: Bool
    ) {
        self.side = side
        self.sourceIdentity = sourceIdentity
        self.sourceRevision = sourceRevision
        self.tableIdentity = tableIdentity
        self.tableRevision = tableRevision
        self.shape = shape
        self.isEditable = isEditable
    }
}

public struct TableWorkspaceParsingLimits: Hashable, Sendable {
    public static let `default` = TableWorkspaceParsingLimits()

    public let maximumInputBytes: Int
    public let maximumRows: Int
    public let maximumColumnsPerRow: Int
    public let maximumTotalCells: Int
    public let maximumCellBytes: Int

    public init(
        maximumInputBytes: Int = DelimitedTableLimits.default.maximumInputBytes,
        maximumRows: Int = DelimitedTableLimits.default.maximumRows,
        maximumColumnsPerRow: Int = DelimitedTableLimits.default.maximumColumnsPerRow,
        maximumTotalCells: Int = DelimitedTableLimits.default.maximumTotalCells,
        maximumCellBytes: Int = DelimitedTableLimits.default.maximumCellBytes
    ) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumRows = maximumRows
        self.maximumColumnsPerRow = maximumColumnsPerRow
        self.maximumTotalCells = maximumTotalCells
        self.maximumCellBytes = maximumCellBytes
    }

    public var delimitedTableLimits: DelimitedTableLimits {
        DelimitedTableLimits(
            maximumInputBytes: maximumInputBytes,
            maximumRows: maximumRows,
            maximumColumnsPerRow: maximumColumnsPerRow,
            maximumTotalCells: maximumTotalCells,
            maximumCellBytes: maximumCellBytes
        )
    }
}

public struct TableWorkspaceFormatSettings: Hashable, Sendable {
    public static let commaSeparated = TableWorkspaceFormatSettings()
    public static let tabSeparated = TableWorkspaceFormatSettings(delimiter: "\t")

    public let delimiter: Character
    public let quote: Character?
    public let allowsNewlinesInQuotedCells: Bool
    public let limits: TableWorkspaceParsingLimits

    public init(
        delimiter: Character = ",",
        quote: Character? = "\"",
        allowsNewlinesInQuotedCells: Bool = true,
        limits: TableWorkspaceParsingLimits = .default
    ) {
        self.delimiter = delimiter
        self.quote = quote
        self.allowsNewlinesInQuotedCells = allowsNewlinesInQuotedCells
        self.limits = limits
    }

    public var parsingOptions: DelimitedTableParsingOptions {
        DelimitedTableParsingOptions(
            delimiter: delimiter,
            quote: quote,
            allowsNewlinesInQuotedCells: allowsNewlinesInQuotedCells,
            limits: limits.delimitedTableLimits
        )
    }
}

public struct TableWorkspaceComparisonSettings: Hashable, Sendable {
    public static let `default` = TableWorkspaceComparisonSettings()

    public let maximumExactEditDistance: Int
    public let maximumAlignmentWork: Int
    public let maximumComparedRows: Int
    public let maximumComparedCells: Int

    public init(
        maximumExactEditDistance: Int = TableComparisonOptions.default.maximumExactEditDistance,
        maximumAlignmentWork: Int = TableComparisonOptions.default.maximumAlignmentWork,
        maximumComparedRows: Int = TableComparisonOptions.default.maximumComparedRows,
        maximumComparedCells: Int = TableComparisonOptions.default.maximumComparedCells
    ) {
        self.maximumExactEditDistance = maximumExactEditDistance
        self.maximumAlignmentWork = maximumAlignmentWork
        self.maximumComparedRows = maximumComparedRows
        self.maximumComparedCells = maximumComparedCells
    }

    public var comparisonOptions: TableComparisonOptions {
        TableComparisonOptions(
            maximumExactEditDistance: maximumExactEditDistance,
            maximumAlignmentWork: maximumAlignmentWork,
            maximumComparedRows: maximumComparedRows,
            maximumComparedCells: maximumComparedCells
        )
    }
}

/// Exact parser and comparison settings used to create a dataset revision.
public struct TableWorkspaceConfiguration: Hashable, Sendable {
    public static let `default` = TableWorkspaceConfiguration()

    public let format: TableWorkspaceFormatSettings
    public let comparison: TableWorkspaceComparisonSettings

    public init(
        format: TableWorkspaceFormatSettings = .commaSeparated,
        comparison: TableWorkspaceComparisonSettings = .default
    ) {
        self.format = format
        self.comparison = comparison
    }
}

/// Immutable metadata snapshot. `configuration` and every binding revision must change with any
/// source, parser, or table change. The planner separately receives the already-computed result.
public struct TableWorkspaceDatasetSnapshot: Hashable, Sendable {
    public let reference: TableWorkspaceDatasetReference
    public let configuration: TableWorkspaceConfiguration
    public let sources: [TableWorkspaceSourceBinding]

    public init(
        reference: TableWorkspaceDatasetReference,
        configuration: TableWorkspaceConfiguration,
        sources: [TableWorkspaceSourceBinding]
    ) {
        self.reference = reference
        self.configuration = configuration
        self.sources = sources.sorted { $0.side.rawValue < $1.side.rawValue }
    }

    public func source(_ side: TableWorkspaceSide) -> TableWorkspaceSourceBinding? {
        sources.first { $0.side == side }
    }
}

private struct TableWorkspaceParsedSourceArtifact: Equatable, Sendable {
    let binding: TableWorkspaceSourceBinding
    let sourceUTF8Bytes: Data
    let table: DelimitedTable
}

/// Executor-issued result bound to exact source bytes, immutable dataset metadata, and engine settings.
public struct TableWorkspaceComparisonReceipt: Equatable, Sendable {
    public let dataset: TableWorkspaceDatasetSnapshot
    public let result: TableComparisonResult
    public let executorContract: TableWorkspaceExecutorContract
    private let leftArtifact: TableWorkspaceParsedSourceArtifact
    private let rightArtifact: TableWorkspaceParsedSourceArtifact

    fileprivate init(
        dataset: TableWorkspaceDatasetSnapshot,
        result: TableComparisonResult,
        leftArtifact: TableWorkspaceParsedSourceArtifact,
        rightArtifact: TableWorkspaceParsedSourceArtifact
    ) {
        self.dataset = dataset
        self.result = result
        self.leftArtifact = leftArtifact
        self.rightArtifact = rightArtifact
        executorContract = .required
    }

    fileprivate func validateArtifacts() throws {
        guard leftArtifact.binding == dataset.source(.left) else {
            throw TableWorkspacePolicyError.sourceBindingChanged(.left)
        }
        guard rightArtifact.binding == dataset.source(.right) else {
            throw TableWorkspacePolicyError.sourceBindingChanged(.right)
        }
        guard
            leftArtifact.sourceUTF8Bytes.count
                == leftArtifact.binding.shape.sourceUTF8ByteCount
        else {
            throw TableWorkspacePolicyError.invalidComparisonResult(.tableMismatch(.left))
        }
        guard
            rightArtifact.sourceUTF8Bytes.count
                == rightArtifact.binding.shape.sourceUTF8ByteCount
        else {
            throw TableWorkspacePolicyError.invalidComparisonResult(.tableMismatch(.right))
        }
    }

    public func requireCurrentDataset(_ snapshot: TableWorkspaceDatasetSnapshot) throws {
        try TableWorkspacePolicy.validateCurrent(snapshot, expected: dataset)
    }
}

public enum TableWorkspaceHeaderVisibility: UInt8, CaseIterable, Hashable, Sendable {
    case hidden
    case visible
}

public enum TableWorkspaceHeaderLabels: UInt8, CaseIterable, Hashable, Sendable {
    case ordinal
    /// First source records provide labels but remain ordinary compared, selectable, editable rows.
    case firstRecord
}

public struct TableWorkspacePresentationOptions: Hashable, Sendable {
    public static let `default` = TableWorkspacePresentationOptions()

    public let headerVisibility: TableWorkspaceHeaderVisibility
    public let headerLabels: TableWorkspaceHeaderLabels
    public let showsRowNumbers: Bool
    public let wrapsCellText: Bool
    public let synchronizesColumnWidths: Bool
    public let highlightsCellDifferences: Bool

    public init(
        headerVisibility: TableWorkspaceHeaderVisibility = .visible,
        headerLabels: TableWorkspaceHeaderLabels = .ordinal,
        showsRowNumbers: Bool = true,
        wrapsCellText: Bool = false,
        synchronizesColumnWidths: Bool = true,
        highlightsCellDifferences: Bool = true
    ) {
        self.headerVisibility = headerVisibility
        self.headerLabels = headerLabels
        self.showsRowNumbers = showsRowNumbers
        self.wrapsCellText = wrapsCellText
        self.synchronizesColumnWidths = synchronizesColumnWidths
        self.highlightsCellDifferences = highlightsCellDifferences
    }
}

public enum TableWorkspaceComparisonStatus: UInt8, CaseIterable, Hashable, Sendable {
    case equal
    case modified
    case removed
    case added

    fileprivate init(_ status: TableComparisonStatus) {
        switch status {
        case .equal: self = .equal
        case .modified: self = .modified
        case .removed: self = .removed
        case .added: self = .added
        }
    }
}

public enum TableWorkspaceColumnFilterCondition: Hashable, Sendable {
    case status(TableWorkspaceComparisonStatus)
    case valueEquals(side: TableWorkspaceSide, value: String)
    case missing(side: TableWorkspaceSide)
}

public enum TableWorkspaceColumnFilterDisposition: UInt8, CaseIterable, Hashable, Sendable {
    /// A row remains visible only when every include filter matches.
    case includeMatchingRows
    /// A matching exclude filter hides the row.
    case excludeMatchingRows
}

public struct TableWorkspaceColumnFilter: Hashable, Sendable {
    public let identifier: String
    public let columnIndex: Int
    public let condition: TableWorkspaceColumnFilterCondition
    public let disposition: TableWorkspaceColumnFilterDisposition

    public init(
        identifier: String,
        columnIndex: Int,
        condition: TableWorkspaceColumnFilterCondition,
        disposition: TableWorkspaceColumnFilterDisposition = .includeMatchingRows
    ) {
        self.identifier = identifier
        self.columnIndex = columnIndex
        self.condition = condition
        self.disposition = disposition
    }
}

public struct TableWorkspaceCellAddress: Hashable, Sendable {
    public let rowIndex: Int
    public let columnIndex: Int

    public init(rowIndex: Int, columnIndex: Int) {
        self.rowIndex = rowIndex
        self.columnIndex = columnIndex
    }
}

public enum TableWorkspaceSelection: Hashable, Sendable {
    case none
    case cells(anchor: TableWorkspaceCellAddress, focus: TableWorkspaceCellAddress)
    case column(Int)
}

/// Persistable policy state. It is bound to one exact dataset revision and cannot migrate silently.
public struct TableWorkspaceState: Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let datasetReference: TableWorkspaceDatasetReference
    public let sources: [TableWorkspaceSourceBinding]
    public let configuration: TableWorkspaceConfiguration
    public let presentationOptions: TableWorkspacePresentationOptions
    public let columnFilters: [TableWorkspaceColumnFilter]
    public let selection: TableWorkspaceSelection

    public init(
        datasetReference: TableWorkspaceDatasetReference,
        sources: [TableWorkspaceSourceBinding],
        configuration: TableWorkspaceConfiguration,
        presentationOptions: TableWorkspacePresentationOptions = .default,
        columnFilters: [TableWorkspaceColumnFilter] = [],
        selection: TableWorkspaceSelection = .none
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.datasetReference = datasetReference
        self.sources = sources.sorted { $0.side.rawValue < $1.side.rawValue }
        self.configuration = configuration
        self.presentationOptions = presentationOptions
        self.columnFilters = columnFilters
        self.selection = selection
    }

    public func encoded(
        limits: TableWorkspacePolicyLimits = .default,
        cancellationCheck: @escaping @Sendable () throws -> Void = TableWorkspacePolicy.checkCancellation
    ) throws -> TableWorkspacePersistenceReceipt {
        try TableWorkspacePersistence.encode(
            self,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    public static func decode(
        from data: Data,
        limits: TableWorkspacePolicyLimits = .default,
        cancellationCheck: @escaping @Sendable () throws -> Void = TableWorkspacePolicy.checkCancellation
    ) throws -> TableWorkspacePersistenceReceipt {
        try TableWorkspacePersistence.decode(
            data,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    public func source(_ side: TableWorkspaceSide) -> TableWorkspaceSourceBinding? {
        sources.first { $0.side == side }
    }
}

public struct TableWorkspacePresentedValue: Hashable, Sendable {
    public let side: TableWorkspaceSide
    public let sourceRowIndex: Int
    public let sourceColumnIndex: Int
    public let value: String
    public let sourceUTF8Range: Range<Int>
    public let sourceLine: Int
    public let sourceColumn: Int
    public let wasQuoted: Bool

    fileprivate init(
        side: TableWorkspaceSide,
        row: DelimitedTableRow,
        cell: DelimitedTableCell
    ) {
        self.side = side
        sourceRowIndex = row.index
        sourceColumnIndex = cell.index
        value = cell.value
        sourceUTF8Range = cell.sourceUTF8Range
        sourceLine = cell.sourceLocation.line
        sourceColumn = cell.sourceLocation.column
        wasQuoted = cell.wasQuoted
    }
}

public struct TableWorkspaceCellPresentation: Hashable, Sendable {
    public let address: TableWorkspaceCellAddress
    public let status: TableWorkspaceComparisonStatus
    public let left: TableWorkspacePresentedValue?
    public let right: TableWorkspacePresentedValue?

    fileprivate init(
        address: TableWorkspaceCellAddress,
        status: TableWorkspaceComparisonStatus,
        left: TableWorkspacePresentedValue?,
        right: TableWorkspacePresentedValue?
    ) {
        self.address = address
        self.status = status
        self.left = left
        self.right = right
    }
}

public struct TableWorkspaceRowPresentation: Hashable, Sendable {
    public let index: Int
    public let leftSourceRowIndex: Int?
    public let rightSourceRowIndex: Int?
    public let status: TableWorkspaceComparisonStatus
    public let cells: [TableWorkspaceCellPresentation]
    public let isVisible: Bool

    fileprivate init(
        index: Int,
        leftSourceRowIndex: Int?,
        rightSourceRowIndex: Int?,
        status: TableWorkspaceComparisonStatus,
        cells: [TableWorkspaceCellPresentation],
        isVisible: Bool
    ) {
        self.index = index
        self.leftSourceRowIndex = leftSourceRowIndex
        self.rightSourceRowIndex = rightSourceRowIndex
        self.status = status
        self.cells = cells
        self.isVisible = isVisible
    }
}

public enum TableWorkspaceColumnLabel: Hashable, Sendable {
    case ordinal(Int)
    case firstRecord(left: String?, right: String?)
}

public struct TableWorkspaceColumnPresentation: Hashable, Sendable {
    public let index: Int
    public let label: TableWorkspaceColumnLabel
    public let filters: [TableWorkspaceColumnFilter]

    fileprivate init(
        index: Int,
        label: TableWorkspaceColumnLabel,
        filters: [TableWorkspaceColumnFilter]
    ) {
        self.index = index
        self.label = label
        self.filters = filters
    }
}

public struct TableWorkspacePresentation: Hashable, Sendable {
    public let datasetReference: TableWorkspaceDatasetReference
    public let options: TableWorkspacePresentationOptions
    public let selection: TableWorkspaceSelection
    public let columns: [TableWorkspaceColumnPresentation]
    public let rows: [TableWorkspaceRowPresentation]
    public let visibleRowCount: Int
    public let presentedUTF8ByteCount: Int
    public let comparisonAlignment: TableComparisonAlignment

    fileprivate init(
        datasetReference: TableWorkspaceDatasetReference,
        options: TableWorkspacePresentationOptions,
        selection: TableWorkspaceSelection,
        columns: [TableWorkspaceColumnPresentation],
        rows: [TableWorkspaceRowPresentation],
        visibleRowCount: Int,
        presentedUTF8ByteCount: Int,
        comparisonAlignment: TableComparisonAlignment
    ) {
        self.datasetReference = datasetReference
        self.options = options
        self.selection = selection
        self.columns = columns
        self.rows = rows
        self.visibleRowCount = visibleRowCount
        self.presentedUTF8ByteCount = presentedUTF8ByteCount
        self.comparisonAlignment = comparisonAlignment
    }
}

public struct TableWorkspaceEditRequest: Hashable, Sendable {
    public let side: TableWorkspaceSide
    public let address: TableWorkspaceCellAddress
    public let expectedPresentedValue: String
    public let replacementPresentedValue: String

    public init(
        side: TableWorkspaceSide,
        address: TableWorkspaceCellAddress,
        expectedPresentedValue: String,
        replacementPresentedValue: String
    ) {
        self.side = side
        self.address = address
        self.expectedPresentedValue = expectedPresentedValue
        self.replacementPresentedValue = replacementPresentedValue
    }
}

/// Planned edit only. It does not define quoting or serialization. The executor must use its
/// authoritative lossless table editor and produce a new source, table, and dataset revision.
public struct TableWorkspaceEditIntent: Hashable, Sendable {
    public let datasetReference: TableWorkspaceDatasetReference
    public let source: TableWorkspaceSourceBinding
    public let presentationAddress: TableWorkspaceCellAddress
    public let sourceRowIndex: Int
    public let sourceColumnIndex: Int
    public let sourceUTF8Range: Range<Int>
    public let expectedPresentedValue: String
    public let replacementPresentedValue: String

    fileprivate init(
        datasetReference: TableWorkspaceDatasetReference,
        source: TableWorkspaceSourceBinding,
        presentationAddress: TableWorkspaceCellAddress,
        presentedValue: TableWorkspacePresentedValue,
        replacementPresentedValue: String
    ) {
        self.datasetReference = datasetReference
        self.source = source
        self.presentationAddress = presentationAddress
        sourceRowIndex = presentedValue.sourceRowIndex
        sourceColumnIndex = presentedValue.sourceColumnIndex
        sourceUTF8Range = presentedValue.sourceUTF8Range
        expectedPresentedValue = presentedValue.value
        self.replacementPresentedValue = replacementPresentedValue
    }
}

public enum TableWorkspaceDatasetLeaseContract: String, Hashable, Sendable {
    case immutableExactSourceAndTableRevisionsHeldDuringPlanningAndRevalidatedBeforeExecution
}

public enum TableWorkspaceComparisonExecutionContract: String, Hashable, Sendable {
    case authoritativeDelimitedTableParserAndTableComparisonOnly
}

public enum TableWorkspaceEditExecutionContract: String, Hashable, Sendable {
    case losslessAuthoritativeEditorReparsesAndPublishesNewRevisionsOrMakesNoChange
}

public enum TableWorkspaceCancellationContract: String, Hashable, Sendable {
    case cancellableBeforeCommitWithExactOutcomeRequiredAfterCommitStarts
}

public enum TableWorkspaceReceiptContract: String, Hashable, Sendable {
    case applyOnlyWithAtomicExactDatasetRevisionCompareAndSwap
}

public struct TableWorkspaceExecutorContract: Hashable, Sendable {
    public static let required = TableWorkspaceExecutorContract()

    public let datasetLease =
        TableWorkspaceDatasetLeaseContract
        .immutableExactSourceAndTableRevisionsHeldDuringPlanningAndRevalidatedBeforeExecution
    public let comparisonExecution =
        TableWorkspaceComparisonExecutionContract.authoritativeDelimitedTableParserAndTableComparisonOnly
    public let editExecution =
        TableWorkspaceEditExecutionContract
        .losslessAuthoritativeEditorReparsesAndPublishesNewRevisionsOrMakesNoChange
    public let cancellation =
        TableWorkspaceCancellationContract
        .cancellableBeforeCommitWithExactOutcomeRequiredAfterCommitStarts
    public let receipts =
        TableWorkspaceReceiptContract.applyOnlyWithAtomicExactDatasetRevisionCompareAndSwap

    public init() {}
}

public struct TableWorkspacePlanReceipt: Hashable, Sendable {
    public let dataset: TableWorkspaceDatasetSnapshot
    public let state: TableWorkspaceState
    public let editIntent: TableWorkspaceEditIntent?
    public let resultRowCount: Int
    public let resultCellCount: Int
    public let visibleRowCount: Int
    public let presentedUTF8ByteCount: Int
    public let planningWorkUnits: Int
    public let limits: TableWorkspacePolicyLimits
    public let executorContract: TableWorkspaceExecutorContract

    fileprivate init(
        dataset: TableWorkspaceDatasetSnapshot,
        state: TableWorkspaceState,
        editIntent: TableWorkspaceEditIntent?,
        resultRowCount: Int,
        resultCellCount: Int,
        visibleRowCount: Int,
        presentedUTF8ByteCount: Int,
        planningWorkUnits: Int,
        limits: TableWorkspacePolicyLimits
    ) {
        self.dataset = dataset
        self.state = state
        self.editIntent = editIntent
        self.resultRowCount = resultRowCount
        self.resultCellCount = resultCellCount
        self.visibleRowCount = visibleRowCount
        self.presentedUTF8ByteCount = presentedUTF8ByteCount
        self.planningWorkUnits = planningWorkUnits
        self.limits = limits
        executorContract = .required
    }

    public func requireCurrentDataset(_ snapshot: TableWorkspaceDatasetSnapshot) throws {
        try TableWorkspacePolicy.validateCurrent(snapshot, expected: dataset)
    }
}

public struct TableWorkspacePlan: Hashable, Sendable {
    public let presentation: TableWorkspacePresentation
    public let receipt: TableWorkspacePlanReceipt

    fileprivate init(
        presentation: TableWorkspacePresentation,
        receipt: TableWorkspacePlanReceipt
    ) {
        self.presentation = presentation
        self.receipt = receipt
    }

    public var editIntent: TableWorkspaceEditIntent? { receipt.editIntent }
    public var executorContract: TableWorkspaceExecutorContract { receipt.executorContract }

    public func requireCurrentDataset(_ snapshot: TableWorkspaceDatasetSnapshot) throws {
        try receipt.requireCurrentDataset(snapshot)
    }

    public func validate(
        _ executionReceipt: TableWorkspaceEditExecutionReceipt
    ) throws -> TableWorkspaceDatasetSnapshot {
        try TableWorkspacePolicy.validate(executionReceipt, for: receipt)
    }
}

public struct TableWorkspaceEditExecutionReceipt: Hashable, Sendable {
    public let intent: TableWorkspaceEditIntent
    public let resultingDataset: TableWorkspaceDatasetSnapshot

    fileprivate init(
        intent: TableWorkspaceEditIntent,
        resultingDataset: TableWorkspaceDatasetSnapshot
    ) {
        self.intent = intent
        self.resultingDataset = resultingDataset
    }
}

/// Side-effect boundary. Implementations own exact source bytes, lossless editing, and publication.
package protocol TableWorkspaceExecutor: Sendable {
    func sourceUTF8Bytes(
        for source: TableWorkspaceSourceBinding,
        in dataset: TableWorkspaceDatasetSnapshot
    ) async throws -> Data

    func publish(_ intent: TableWorkspaceEditIntent) async throws -> TableWorkspaceDatasetSnapshot
}

extension TableWorkspaceExecutor {
    package func compare(
        dataset: TableWorkspaceDatasetSnapshot
    ) async throws -> TableWorkspaceComparisonReceipt {
        let sources = try TableWorkspacePolicy.canonicalSources(dataset.sources)
        try TableWorkspacePolicy.validateConfiguration(dataset.configuration)
        let leftArtifact = try await TableWorkspacePolicy.parseArtifact(
            source: sources[0],
            sourceUTF8Bytes: sourceUTF8Bytes(for: sources[0], in: dataset),
            configuration: dataset.configuration
        )
        let rightArtifact = try await TableWorkspacePolicy.parseArtifact(
            source: sources[1],
            sourceUTF8Bytes: sourceUTF8Bytes(for: sources[1], in: dataset),
            configuration: dataset.configuration
        )
        let result = try TableComparison.compare(
            left: leftArtifact.table,
            right: rightArtifact.table,
            options: dataset.configuration.comparison.comparisonOptions
        )
        return TableWorkspaceComparisonReceipt(
            dataset: dataset,
            result: result,
            leftArtifact: leftArtifact,
            rightArtifact: rightArtifact
        )
    }

    package func execute(
        _ intent: TableWorkspaceEditIntent
    ) async throws -> TableWorkspaceEditExecutionReceipt {
        TableWorkspaceEditExecutionReceipt(
            intent: intent,
            resultingDataset: try await publish(intent)
        )
    }
}

public struct TableWorkspaceRequest: Equatable, Sendable {
    public let comparisonReceipt: TableWorkspaceComparisonReceipt
    public let state: TableWorkspaceState
    public let editRequest: TableWorkspaceEditRequest?
    public let limits: TableWorkspacePolicyLimits

    public var dataset: TableWorkspaceDatasetSnapshot { comparisonReceipt.dataset }
    public var comparisonResult: TableComparisonResult { comparisonReceipt.result }

    public init(
        comparisonReceipt: TableWorkspaceComparisonReceipt,
        state: TableWorkspaceState,
        editRequest: TableWorkspaceEditRequest? = nil,
        limits: TableWorkspacePolicyLimits = .default
    ) {
        self.comparisonReceipt = comparisonReceipt
        self.state = state
        self.editRequest = editRequest
        self.limits = limits
    }
}

public enum TableWorkspacePolicyLimit: String, CaseIterable, Hashable, Sendable {
    case sourceCount
    case rows
    case columns
    case cells
    case presentedUTF8Bytes
    case columnFilters
    case filterIdentifierUTF8Bytes
    case filterValueUTF8Bytes
    case totalFilterUTF8Bytes
    case editValueUTF8Bytes
    case persistedBytes
    case planningWorkUnits
    case cancellationCheckInterval
}

public struct TableWorkspacePolicyLimits: Hashable, Sendable {
    public static let hardMaximumSourceCount = 2
    public static let hardMaximumRows = 2_097_152
    public static let hardMaximumColumns = 16_384
    public static let hardMaximumCells = 2_097_152
    public static let hardMaximumPresentedUTF8Bytes = 192 * 1_024 * 1_024
    public static let hardMaximumColumnFilters = 4_096
    public static let hardMaximumFilterIdentifierUTF8Bytes = 1_024
    public static let hardMaximumFilterValueUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumTotalFilterUTF8Bytes = 64 * 1_024 * 1_024
    public static let hardMaximumEditValueUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumPersistedBytes = 64 * 1_024 * 1_024
    public static let hardMaximumPlanningWorkUnits = 512 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = TableWorkspacePolicyLimits()

    public let maximumSourceCount: Int
    public let maximumRows: Int
    public let maximumColumns: Int
    public let maximumCells: Int
    public let maximumPresentedUTF8Bytes: Int
    public let maximumColumnFilters: Int
    public let maximumFilterIdentifierUTF8Bytes: Int
    public let maximumFilterValueUTF8Bytes: Int
    public let maximumTotalFilterUTF8Bytes: Int
    public let maximumEditValueUTF8Bytes: Int
    public let maximumPersistedBytes: Int
    public let maximumPlanningWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumSourceCount: Int = 2,
        maximumRows: Int = 2_097_152,
        maximumColumns: Int = 16_384,
        maximumCells: Int = 2_097_152,
        maximumPresentedUTF8Bytes: Int = 192 * 1_024 * 1_024,
        maximumColumnFilters: Int = 4_096,
        maximumFilterIdentifierUTF8Bytes: Int = 1_024,
        maximumFilterValueUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumTotalFilterUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumEditValueUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumPersistedBytes: Int = 64 * 1_024 * 1_024,
        maximumPlanningWorkUnits: Int = 512 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 4_096
    ) {
        self.maximumSourceCount = maximumSourceCount
        self.maximumRows = maximumRows
        self.maximumColumns = maximumColumns
        self.maximumCells = maximumCells
        self.maximumPresentedUTF8Bytes = maximumPresentedUTF8Bytes
        self.maximumColumnFilters = maximumColumnFilters
        self.maximumFilterIdentifierUTF8Bytes = maximumFilterIdentifierUTF8Bytes
        self.maximumFilterValueUTF8Bytes = maximumFilterValueUTF8Bytes
        self.maximumTotalFilterUTF8Bytes = maximumTotalFilterUTF8Bytes
        self.maximumEditValueUTF8Bytes = maximumEditValueUTF8Bytes
        self.maximumPersistedBytes = maximumPersistedBytes
        self.maximumPlanningWorkUnits = maximumPlanningWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum TableWorkspaceTableValidationIssue: Hashable, Sendable {
    case negativeSourceByteCount
    case invalidDelimiter
    case invalidQuote
    case delimiterMatchesQuote
    case invalidRowIndex(expected: Int, actual: Int)
    case emptyRow(Int)
    case invalidRowRange(Int)
    case invalidRowSourceLine(Int)
    case invalidCellIndex(row: Int, expected: Int, actual: Int)
    case invalidCellRange(row: Int, column: Int)
    case invalidCellLocation(row: Int, column: Int)
    case cellValueTooLarge(row: Int, column: Int, maximumUTF8Bytes: Int)
    case totalCellCountMismatch(expected: Int, actual: Int)
}

public enum TableWorkspaceResultValidationIssue: Hashable, Sendable {
    case tableMismatch(TableWorkspaceSide)
    case invalidRowIndex(expected: Int, actual: Int)
    case invalidRowMapping(row: Int, side: TableWorkspaceSide)
    case nonMonotonicRowMapping(row: Int, side: TableWorkspaceSide)
    case incompleteRowMapping(side: TableWorkspaceSide)
    case invalidRowStatus(Int)
    case invalidCellIndex(row: Int, expected: Int, actual: Int)
    case invalidCellMapping(row: Int, column: Int, side: TableWorkspaceSide)
    case invalidCellStatus(row: Int, column: Int)
    case summaryMismatch
}

public enum TableWorkspacePolicyError: Error, LocalizedError, Hashable, Sendable {
    case cancelled
    case invalidLimit(TableWorkspacePolicyLimit)
    case unsupportedSchemaVersion(Int)
    case datasetIdentityChanged
    case staleDatasetRevision(expected: UInt64, actual: UInt64)
    case sourceCountInvalid(Int)
    case duplicateSide(TableWorkspaceSide)
    case missingSide(TableWorkspaceSide)
    case sourceBindingChanged(TableWorkspaceSide)
    case configurationChanged
    case invalidFormat(String)
    case invalidComparisonSetting(String)
    case shapeMismatch(TableWorkspaceSide)
    case invalidTable(side: TableWorkspaceSide, issue: TableWorkspaceTableValidationIssue)
    case invalidComparisonResult(TableWorkspaceResultValidationIssue)
    case tooManyRows(maximum: Int)
    case tooManyColumns(maximum: Int)
    case tooManyCells(maximum: Int)
    case presentedValuesTooLarge(maximumUTF8Bytes: Int)
    case tooManyColumnFilters(maximum: Int)
    case duplicateFilterIdentifier(String)
    case invalidFilterIdentifier(String)
    case filterIdentifierTooLarge(maximumUTF8Bytes: Int)
    case filterValueTooLarge(identifier: String, maximumUTF8Bytes: Int)
    case totalFilterValuesTooLarge(maximumUTF8Bytes: Int)
    case filterColumnOutOfBounds(identifier: String, columnIndex: Int)
    case selectionOutOfBounds
    case editTargetOutOfBounds
    case editTargetMissing(TableWorkspaceSide)
    case editTargetReadOnly(TableWorkspaceSide)
    case editExpectedValueChanged
    case editWouldNotChangeValue
    case editValueTooLarge(maximumUTF8Bytes: Int)
    case unexpectedExecutionReceipt
    case executionIntentMismatch
    case resultingDatasetIdentityChanged
    case resultingDatasetRevisionUnchanged
    case resultingSourceIdentityChanged(TableWorkspaceSide)
    case resultingSourceRevisionUnchanged(TableWorkspaceSide)
    case resultingTableIdentityChanged(TableWorkspaceSide)
    case resultingTableRevisionUnchanged(TableWorkspaceSide)
    case unrelatedSourceChanged(TableWorkspaceSide)
    case resultingTableShapeChanged(TableWorkspaceSide)
    case planningWorkLimitExceeded(maximum: Int)
    case persistenceDataTooLarge(maximumBytes: Int)
    case nonCanonicalPersistenceString(String)
    case malformedPersistence
    case trailingPersistenceData

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Table workspace planning was cancelled."
        case .invalidLimit(let limit):
            "Table workspace limit is invalid: \(limit.rawValue)."
        case .unsupportedSchemaVersion(let version):
            "Table workspace schema version \(version) is unsupported."
        case .datasetIdentityChanged:
            "Table workspace belongs to another dataset."
        case .staleDatasetRevision(let expected, let actual):
            "Table workspace expects dataset revision \(expected), not \(actual)."
        case .sourceCountInvalid(let count):
            "Table workspace requires exactly two sources, not \(count)."
        case .duplicateSide(let side):
            "Table workspace contains duplicate \(side.rawValue) source bindings."
        case .missingSide(let side):
            "Table workspace is missing its \(side.rawValue) source binding."
        case .sourceBindingChanged(let side):
            "Table workspace \(side.rawValue) source or table binding changed."
        case .configurationChanged:
            "Table workspace parser or comparison configuration changed."
        case .invalidFormat(let name):
            "Table workspace format setting is invalid: \(name)."
        case .invalidComparisonSetting(let name):
            "Table workspace comparison setting is invalid: \(name)."
        case .shapeMismatch(let side):
            "Table workspace \(side.rawValue) table shape does not match its binding."
        case .invalidTable(let side, _):
            "Table workspace \(side.rawValue) table is structurally invalid."
        case .invalidComparisonResult:
            "Table workspace comparison result is structurally invalid."
        case .tooManyRows(let maximum):
            "Table workspace exceeds the \(maximum)-row limit."
        case .tooManyColumns(let maximum):
            "Table workspace exceeds the \(maximum)-column limit."
        case .tooManyCells(let maximum):
            "Table workspace exceeds the \(maximum)-cell limit."
        case .presentedValuesTooLarge(let maximum):
            "Table workspace values exceed \(maximum) UTF-8 bytes."
        case .tooManyColumnFilters(let maximum):
            "Table workspace exceeds the \(maximum)-filter limit."
        case .duplicateFilterIdentifier(let identifier):
            "Table workspace filter identifier is duplicated: \(identifier)."
        case .invalidFilterIdentifier(let identifier):
            "Table workspace filter identifier is invalid: \(identifier)."
        case .filterIdentifierTooLarge(let maximum):
            "Table workspace filter identifier exceeds \(maximum) UTF-8 bytes."
        case .filterValueTooLarge(let identifier, let maximum):
            "Table workspace filter \(identifier) value exceeds \(maximum) UTF-8 bytes."
        case .totalFilterValuesTooLarge(let maximum):
            "Table workspace filters exceed \(maximum) combined UTF-8 bytes."
        case .filterColumnOutOfBounds(let identifier, let columnIndex):
            "Table workspace filter \(identifier) targets missing column \(columnIndex)."
        case .selectionOutOfBounds:
            "Table workspace selection is outside the dataset."
        case .editTargetOutOfBounds:
            "Table workspace edit target is outside the dataset."
        case .editTargetMissing(let side):
            "Table workspace edit target has no \(side.rawValue) cell."
        case .editTargetReadOnly(let side):
            "Table workspace \(side.rawValue) source is read-only."
        case .editExpectedValueChanged:
            "Table workspace edit target no longer contains the expected value."
        case .editWouldNotChangeValue:
            "Table workspace edit replacement equals the current value."
        case .editValueTooLarge(let maximum):
            "Table workspace edit value exceeds \(maximum) UTF-8 bytes."
        case .unexpectedExecutionReceipt:
            "Table workspace plan contains no edit for this execution receipt."
        case .executionIntentMismatch:
            "Table workspace execution receipt belongs to another edit intent."
        case .resultingDatasetIdentityChanged:
            "Table workspace execution returned another dataset identity."
        case .resultingDatasetRevisionUnchanged:
            "Table workspace execution did not issue a new dataset revision."
        case .resultingSourceIdentityChanged(let side):
            "Table workspace execution changed the \(side.rawValue) source identity."
        case .resultingSourceRevisionUnchanged(let side):
            "Table workspace execution did not revise the \(side.rawValue) source."
        case .resultingTableIdentityChanged(let side):
            "Table workspace execution changed the \(side.rawValue) table identity."
        case .resultingTableRevisionUnchanged(let side):
            "Table workspace execution did not revise the \(side.rawValue) table."
        case .unrelatedSourceChanged(let side):
            "Table workspace execution changed unrelated \(side.rawValue) source state."
        case .resultingTableShapeChanged(let side):
            "Table workspace edit changed \(side.rawValue) row or cell boundaries."
        case .planningWorkLimitExceeded(let maximum):
            "Table workspace planning exceeds the \(maximum)-unit work limit."
        case .persistenceDataTooLarge(let maximum):
            "Table workspace persistence exceeds \(maximum) bytes."
        case .nonCanonicalPersistenceString(let name):
            "Table workspace persistence string is not canonical UTF-8: \(name)."
        case .malformedPersistence:
            "Table workspace persistence is malformed."
        case .trailingPersistenceData:
            "Table workspace persistence contains trailing data."
        }
    }
}

public enum TableWorkspacePolicy: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    /// Builds presentation from an existing comparison. It never parses, compares, edits, or does I/O.
    public static func plan(
        _ request: TableWorkspaceRequest,
        cancellationCheck: @escaping CancellationCheck = checkCancellation
    ) throws -> TableWorkspacePlan {
        do {
            try performCancellationCheck(cancellationCheck)
            try validate(request.limits)
            guard request.comparisonReceipt.executorContract == .required else {
                throw TableWorkspacePolicyError.executionIntentMismatch
            }
            try request.comparisonReceipt.validateArtifacts()
            try validateConfiguration(request.dataset.configuration)
            try validateCurrentState(request.state, dataset: request.dataset)

            var work = TableWorkspacePlanningWork(
                limits: request.limits,
                cancellationCheck: cancellationCheck
            )
            let sources = try canonicalSources(request.dataset.sources, work: &work)
            let leftShape = try validate(
                request.comparisonResult.left,
                side: .left,
                limits: request.limits,
                formatLimits: request.dataset.configuration.format.limits,
                work: &work
            )
            let rightShape = try validate(
                request.comparisonResult.right,
                side: .right,
                limits: request.limits,
                formatLimits: request.dataset.configuration.format.limits,
                work: &work
            )
            guard leftShape == sources[0].shape else {
                throw TableWorkspacePolicyError.shapeMismatch(.left)
            }
            guard rightShape == sources[1].shape else {
                throw TableWorkspacePolicyError.shapeMismatch(.right)
            }
            let format = request.dataset.configuration.format
            guard request.comparisonResult.left.delimiter == format.delimiter,
                request.comparisonResult.right.delimiter == format.delimiter,
                request.comparisonResult.left.quote == format.quote,
                request.comparisonResult.right.quote == format.quote
            else {
                throw TableWorkspacePolicyError.configurationChanged
            }

            let resultCellCount = try validate(
                request.comparisonResult,
                limits: request.limits,
                comparisonSettings: request.dataset.configuration.comparison,
                work: &work
            )
            let maximumColumnCount = max(leftShape.maximumColumnCount, rightShape.maximumColumnCount)
            let filters = try validate(
                request.state.columnFilters,
                maximumColumnCount: maximumColumnCount,
                exactSourceShapes: nil,
                limits: request.limits,
                work: &work
            )
            try validate(
                request.state.selection,
                result: request.comparisonResult,
                maximumColumnCount: maximumColumnCount
            )

            var rows: [TableWorkspaceRowPresentation] = []
            rows.reserveCapacity(request.comparisonResult.rows.count)
            var visibleRowCount = 0
            var presentedUTF8ByteCount = 0
            for row in request.comparisonResult.rows {
                try work.charge(1)
                var cells: [TableWorkspaceCellPresentation] = []
                cells.reserveCapacity(row.cells.count)
                for cell in row.cells {
                    try work.charge(1)
                    let left = try presentedValue(
                        side: .left,
                        row: row.left,
                        cell: cell.left,
                        byteCount: &presentedUTF8ByteCount,
                        limits: request.limits,
                        work: &work
                    )
                    let right = try presentedValue(
                        side: .right,
                        row: row.right,
                        cell: cell.right,
                        byteCount: &presentedUTF8ByteCount,
                        limits: request.limits,
                        work: &work
                    )
                    cells.append(
                        TableWorkspaceCellPresentation(
                            address: TableWorkspaceCellAddress(
                                rowIndex: row.index,
                                columnIndex: cell.index
                            ),
                            status: TableWorkspaceComparisonStatus(cell.status),
                            left: left,
                            right: right
                        )
                    )
                }
                let isVisible = try rowIsVisible(
                    cells: cells,
                    filters: filters,
                    work: &work
                )
                if isVisible { visibleRowCount += 1 }
                rows.append(
                    TableWorkspaceRowPresentation(
                        index: row.index,
                        leftSourceRowIndex: row.leftIndex,
                        rightSourceRowIndex: row.rightIndex,
                        status: TableWorkspaceComparisonStatus(row.status),
                        cells: cells,
                        isVisible: isVisible
                    )
                )
            }

            var columns: [TableWorkspaceColumnPresentation] = []
            columns.reserveCapacity(maximumColumnCount)
            var filtersByColumn: [Int: [TableWorkspaceColumnFilter]] = [:]
            filtersByColumn.reserveCapacity(min(filters.count, maximumColumnCount))
            for filter in filters {
                try work.charge(1)
                filtersByColumn[filter.columnIndex, default: []].append(filter)
            }
            for columnIndex in 0..<maximumColumnCount {
                try work.charge(1)
                let label: TableWorkspaceColumnLabel
                switch request.state.presentationOptions.headerLabels {
                case .ordinal:
                    label = .ordinal(columnIndex + 1)
                case .firstRecord:
                    label = .firstRecord(
                        left: value(request.comparisonResult.left.rows.first, at: columnIndex),
                        right: value(request.comparisonResult.right.rows.first, at: columnIndex)
                    )
                }
                columns.append(
                    TableWorkspaceColumnPresentation(
                        index: columnIndex,
                        label: label,
                        filters: filtersByColumn[columnIndex] ?? []
                    )
                )
            }

            let presentation = TableWorkspacePresentation(
                datasetReference: request.dataset.reference,
                options: request.state.presentationOptions,
                selection: request.state.selection,
                columns: columns,
                rows: rows,
                visibleRowCount: visibleRowCount,
                presentedUTF8ByteCount: presentedUTF8ByteCount,
                comparisonAlignment: request.comparisonResult.alignment
            )
            let editIntent = try request.editRequest.map {
                try makeEditIntent(
                    $0,
                    dataset: request.dataset,
                    sources: sources,
                    presentation: presentation,
                    limits: request.limits,
                    work: &work
                )
            }
            try performCancellationCheck(cancellationCheck)
            let receipt = TableWorkspacePlanReceipt(
                dataset: request.dataset,
                state: request.state,
                editIntent: editIntent,
                resultRowCount: rows.count,
                resultCellCount: resultCellCount,
                visibleRowCount: visibleRowCount,
                presentedUTF8ByteCount: presentedUTF8ByteCount,
                planningWorkUnits: work.consumed,
                limits: request.limits
            )
            return TableWorkspacePlan(presentation: presentation, receipt: receipt)
        } catch is CancellationError {
            throw TableWorkspacePolicyError.cancelled
        }
    }

    public static func validateCurrent(
        _ actual: TableWorkspaceDatasetSnapshot,
        expected: TableWorkspaceDatasetSnapshot
    ) throws {
        try validateCurrentReference(actual.reference, expected: expected.reference)
        guard actual.configuration == expected.configuration else {
            throw TableWorkspacePolicyError.configurationChanged
        }
        let actualSources = try canonicalSources(actual.sources)
        let expectedSources = try canonicalSources(expected.sources)
        for (index, side) in TableWorkspaceSide.allCases.enumerated() {
            guard actualSources[index] == expectedSources[index] else {
                throw TableWorkspacePolicyError.sourceBindingChanged(side)
            }
        }
    }

    public static func validate(
        _ executionReceipt: TableWorkspaceEditExecutionReceipt,
        for planReceipt: TableWorkspacePlanReceipt
    ) throws -> TableWorkspaceDatasetSnapshot {
        guard let intent = planReceipt.editIntent else {
            throw TableWorkspacePolicyError.unexpectedExecutionReceipt
        }
        guard executionReceipt.intent == intent else {
            throw TableWorkspacePolicyError.executionIntentMismatch
        }
        let before = planReceipt.dataset
        let after = executionReceipt.resultingDataset
        guard after.reference.identity == before.reference.identity else {
            throw TableWorkspacePolicyError.resultingDatasetIdentityChanged
        }
        guard after.reference.revision > before.reference.revision else {
            throw TableWorkspacePolicyError.resultingDatasetRevisionUnchanged
        }
        guard after.configuration == before.configuration else {
            throw TableWorkspacePolicyError.configurationChanged
        }
        let oldSources = try canonicalSources(before.sources)
        let newSources = try canonicalSources(after.sources)
        for (index, side) in TableWorkspaceSide.allCases.enumerated() {
            let oldSource = oldSources[index]
            let newSource = newSources[index]
            if side != intent.source.side {
                guard newSource == oldSource else {
                    throw TableWorkspacePolicyError.unrelatedSourceChanged(side)
                }
                continue
            }
            guard newSource.sourceIdentity == oldSource.sourceIdentity else {
                throw TableWorkspacePolicyError.resultingSourceIdentityChanged(side)
            }
            guard newSource.sourceRevision > oldSource.sourceRevision else {
                throw TableWorkspacePolicyError.resultingSourceRevisionUnchanged(side)
            }
            guard newSource.tableIdentity == oldSource.tableIdentity else {
                throw TableWorkspacePolicyError.resultingTableIdentityChanged(side)
            }
            guard newSource.tableRevision > oldSource.tableRevision else {
                throw TableWorkspacePolicyError.resultingTableRevisionUnchanged(side)
            }
            guard newSource.shape.rowCount == oldSource.shape.rowCount,
                newSource.shape.maximumColumnCount == oldSource.shape.maximumColumnCount,
                newSource.shape.totalCellCount == oldSource.shape.totalCellCount
            else {
                throw TableWorkspacePolicyError.resultingTableShapeChanged(side)
            }
            guard newSource.shape.sourceUTF8ByteCount >= 0,
                newSource.shape.sourceUTF8ByteCount
                    <= after.configuration.format.limits.maximumInputBytes
            else {
                throw TableWorkspacePolicyError.shapeMismatch(side)
            }
        }
        return after
    }

    public static func checkCancellation() throws {
        do {
            try Task<Never, Never>.checkCancellation()
        } catch {
            throw TableWorkspacePolicyError.cancelled
        }
    }

    fileprivate static func performCancellationCheck(
        _ cancellationCheck: CancellationCheck
    ) throws {
        do {
            try cancellationCheck()
        } catch {
            throw TableWorkspacePolicyError.cancelled
        }
    }

    fileprivate static func validate(_ limits: TableWorkspacePolicyLimits) throws {
        let checks: [(Bool, TableWorkspacePolicyLimit)] = [
            (limits.maximumSourceCount == 2, .sourceCount),
            ((0...TableWorkspacePolicyLimits.hardMaximumRows).contains(limits.maximumRows), .rows),
            ((0...TableWorkspacePolicyLimits.hardMaximumColumns).contains(limits.maximumColumns), .columns),
            ((0...TableWorkspacePolicyLimits.hardMaximumCells).contains(limits.maximumCells), .cells),
            (
                (0...TableWorkspacePolicyLimits.hardMaximumPresentedUTF8Bytes)
                    .contains(limits.maximumPresentedUTF8Bytes),
                .presentedUTF8Bytes
            ),
            (
                (0...TableWorkspacePolicyLimits.hardMaximumColumnFilters)
                    .contains(limits.maximumColumnFilters),
                .columnFilters
            ),
            (
                (1...TableWorkspacePolicyLimits.hardMaximumFilterIdentifierUTF8Bytes)
                    .contains(limits.maximumFilterIdentifierUTF8Bytes),
                .filterIdentifierUTF8Bytes
            ),
            (
                (0...TableWorkspacePolicyLimits.hardMaximumFilterValueUTF8Bytes)
                    .contains(limits.maximumFilterValueUTF8Bytes),
                .filterValueUTF8Bytes
            ),
            (
                (0...TableWorkspacePolicyLimits.hardMaximumTotalFilterUTF8Bytes)
                    .contains(limits.maximumTotalFilterUTF8Bytes),
                .totalFilterUTF8Bytes
            ),
            (
                (0...TableWorkspacePolicyLimits.hardMaximumEditValueUTF8Bytes)
                    .contains(limits.maximumEditValueUTF8Bytes),
                .editValueUTF8Bytes
            ),
            (
                (1...TableWorkspacePolicyLimits.hardMaximumPersistedBytes)
                    .contains(limits.maximumPersistedBytes),
                .persistedBytes
            ),
            (
                (1...TableWorkspacePolicyLimits.hardMaximumPlanningWorkUnits)
                    .contains(limits.maximumPlanningWorkUnits),
                .planningWorkUnits
            ),
            (
                (1...TableWorkspacePolicyLimits.hardMaximumCancellationCheckInterval)
                    .contains(limits.cancellationCheckInterval),
                .cancellationCheckInterval
            )
        ]
        if let failed = checks.first(where: { !$0.0 }) {
            throw TableWorkspacePolicyError.invalidLimit(failed.1)
        }
    }

    fileprivate static func validateConfiguration(
        _ configuration: TableWorkspaceConfiguration
    ) throws {
        let format = configuration.format
        guard validStructuralCharacter(format.delimiter) else {
            throw TableWorkspacePolicyError.invalidFormat("delimiter")
        }
        guard isCanonical(String(format.delimiter)) else {
            throw TableWorkspacePolicyError.invalidFormat("delimiterCanonicalForm")
        }
        if let quote = format.quote {
            guard validStructuralCharacter(quote) else {
                throw TableWorkspacePolicyError.invalidFormat("quote")
            }
            guard quote != format.delimiter else {
                throw TableWorkspacePolicyError.invalidFormat("delimiterMatchesQuote")
            }
            guard isCanonical(String(quote)) else {
                throw TableWorkspacePolicyError.invalidFormat("quoteCanonicalForm")
            }
        }
        let parsing = format.limits
        guard parsing.maximumInputBytes >= 0,
            parsing.maximumInputBytes <= DelimitedTableLimits.default.maximumInputBytes
        else {
            throw TableWorkspacePolicyError.invalidFormat("maximumInputBytes")
        }
        guard parsing.maximumRows > 0,
            parsing.maximumRows <= DelimitedTableLimits.default.maximumRows
        else {
            throw TableWorkspacePolicyError.invalidFormat("maximumRows")
        }
        guard parsing.maximumColumnsPerRow > 0,
            parsing.maximumColumnsPerRow <= DelimitedTableLimits.default.maximumColumnsPerRow
        else {
            throw TableWorkspacePolicyError.invalidFormat("maximumColumnsPerRow")
        }
        guard parsing.maximumTotalCells > 0,
            parsing.maximumTotalCells <= DelimitedTableLimits.default.maximumTotalCells
        else {
            throw TableWorkspacePolicyError.invalidFormat("maximumTotalCells")
        }
        guard parsing.maximumCellBytes >= 0,
            parsing.maximumCellBytes <= DelimitedTableLimits.default.maximumCellBytes
        else {
            throw TableWorkspacePolicyError.invalidFormat("maximumCellBytes")
        }
        let comparison = configuration.comparison
        let values: [(String, Int, Int)] = [
            (
                "maximumExactEditDistance",
                comparison.maximumExactEditDistance,
                TableComparisonOptions.default.maximumExactEditDistance
            ),
            (
                "maximumAlignmentWork",
                comparison.maximumAlignmentWork,
                TableComparisonOptions.default.maximumAlignmentWork
            ),
            (
                "maximumComparedRows",
                comparison.maximumComparedRows,
                TableComparisonOptions.default.maximumComparedRows
            ),
            (
                "maximumComparedCells",
                comparison.maximumComparedCells,
                TableComparisonOptions.default.maximumComparedCells
            )
        ]
        if let invalid = values.first(where: { $0.1 < 0 || $0.1 > $0.2 }) {
            throw TableWorkspacePolicyError.invalidComparisonSetting(invalid.0)
        }
    }

    fileprivate static func validateStateStructure(
        _ state: TableWorkspaceState,
        limits: TableWorkspacePolicyLimits,
        work: inout TableWorkspacePlanningWork
    ) throws {
        guard state.schemaVersion == TableWorkspaceState.currentSchemaVersion else {
            throw TableWorkspacePolicyError.unsupportedSchemaVersion(state.schemaVersion)
        }
        try validateConfiguration(state.configuration)
        let sources = try canonicalSources(state.sources, work: &work)
        for source in sources {
            try validateBinding(source, configuration: state.configuration, limits: limits)
        }
        let exactSourceShapes = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.side, $0.shape) }
        )
        _ = try validate(
            state.columnFilters,
            maximumColumnCount: sources.map(\.shape.maximumColumnCount).max() ?? 0,
            exactSourceShapes: exactSourceShapes,
            limits: limits,
            work: &work
        )
        try validatePersistedSelection(
            state.selection,
            maximumColumnCount: sources.map(\.shape.maximumColumnCount).max() ?? 0
        )
    }

    private static func validateCurrentState(
        _ state: TableWorkspaceState,
        dataset: TableWorkspaceDatasetSnapshot
    ) throws {
        guard state.schemaVersion == TableWorkspaceState.currentSchemaVersion else {
            throw TableWorkspacePolicyError.unsupportedSchemaVersion(state.schemaVersion)
        }
        try validateCurrentReference(state.datasetReference, expected: dataset.reference)
        let stateSources = try canonicalSources(state.sources)
        let datasetSources = try canonicalSources(dataset.sources)
        for (index, side) in TableWorkspaceSide.allCases.enumerated() {
            guard stateSources[index] == datasetSources[index] else {
                throw TableWorkspacePolicyError.sourceBindingChanged(side)
            }
        }
        guard state.configuration == dataset.configuration else {
            throw TableWorkspacePolicyError.configurationChanged
        }
    }

    private static func validateCurrentReference(
        _ actual: TableWorkspaceDatasetReference,
        expected: TableWorkspaceDatasetReference
    ) throws {
        guard actual.identity == expected.identity else {
            throw TableWorkspacePolicyError.datasetIdentityChanged
        }
        guard actual.revision == expected.revision else {
            throw TableWorkspacePolicyError.staleDatasetRevision(
                expected: expected.revision,
                actual: actual.revision
            )
        }
    }

    private static func canonicalSources(
        _ sources: [TableWorkspaceSourceBinding],
        work: inout TableWorkspacePlanningWork
    ) throws -> [TableWorkspaceSourceBinding] {
        guard sources.count == 2 else {
            throw TableWorkspacePolicyError.sourceCountInvalid(sources.count)
        }
        var bySide: [TableWorkspaceSide: TableWorkspaceSourceBinding] = [:]
        for source in sources {
            try work.charge(1)
            guard bySide.updateValue(source, forKey: source.side) == nil else {
                throw TableWorkspacePolicyError.duplicateSide(source.side)
            }
        }
        return try TableWorkspaceSide.allCases.map { side in
            guard let source = bySide[side] else {
                throw TableWorkspacePolicyError.missingSide(side)
            }
            return source
        }
    }

    fileprivate static func canonicalSources(
        _ sources: [TableWorkspaceSourceBinding]
    ) throws -> [TableWorkspaceSourceBinding] {
        guard sources.count == 2 else {
            throw TableWorkspacePolicyError.sourceCountInvalid(sources.count)
        }
        var bySide: [TableWorkspaceSide: TableWorkspaceSourceBinding] = [:]
        for source in sources {
            guard bySide.updateValue(source, forKey: source.side) == nil else {
                throw TableWorkspacePolicyError.duplicateSide(source.side)
            }
        }
        return try TableWorkspaceSide.allCases.map { side in
            guard let source = bySide[side] else {
                throw TableWorkspacePolicyError.missingSide(side)
            }
            return source
        }
    }

    fileprivate static func parseArtifact(
        source: TableWorkspaceSourceBinding,
        sourceUTF8Bytes: Data,
        configuration: TableWorkspaceConfiguration
    ) throws -> TableWorkspaceParsedSourceArtifact {
        guard sourceUTF8Bytes.count == source.shape.sourceUTF8ByteCount,
            let sourceText = String(data: sourceUTF8Bytes, encoding: .utf8)
        else {
            throw TableWorkspacePolicyError.shapeMismatch(source.side)
        }
        let table = try DelimitedTableParser.parse(
            sourceText,
            options: configuration.format.parsingOptions
        )
        let shape = TableWorkspaceTableShape(
            sourceUTF8ByteCount: table.sourceUTF8ByteCount,
            rowCount: table.rows.count,
            maximumColumnCount: table.rows.map(\.cells.count).max() ?? 0,
            totalCellCount: table.totalCellCount
        )
        guard shape == source.shape else {
            throw TableWorkspacePolicyError.shapeMismatch(source.side)
        }
        return TableWorkspaceParsedSourceArtifact(
            binding: source,
            sourceUTF8Bytes: sourceUTF8Bytes,
            table: table
        )
    }

    private static func validateBinding(
        _ source: TableWorkspaceSourceBinding,
        configuration: TableWorkspaceConfiguration,
        limits: TableWorkspacePolicyLimits
    ) throws {
        let shape = source.shape
        let parsing = configuration.format.limits
        guard shape.sourceUTF8ByteCount >= 0,
            shape.sourceUTF8ByteCount <= parsing.maximumInputBytes,
            shape.rowCount >= 0,
            shape.rowCount <= parsing.maximumRows,
            shape.rowCount <= limits.maximumRows,
            shape.maximumColumnCount >= 0,
            shape.maximumColumnCount <= parsing.maximumColumnsPerRow,
            shape.maximumColumnCount <= limits.maximumColumns,
            shape.totalCellCount >= 0,
            shape.totalCellCount <= parsing.maximumTotalCells,
            shape.totalCellCount <= limits.maximumCells
        else {
            throw TableWorkspacePolicyError.shapeMismatch(source.side)
        }
        let minimumCells =
            shape.rowCount == 0
            ? 0
            : try checkedAdd(shape.rowCount, shape.maximumColumnCount - 1) {
                TableWorkspacePolicyError.shapeMismatch(source.side)
            }
        let (maximumCells, multiplicationOverflow) = shape.rowCount.multipliedReportingOverflow(
            by: shape.maximumColumnCount
        )
        guard !multiplicationOverflow,
            (shape.rowCount == 0)
                ? shape.maximumColumnCount == 0 && shape.totalCellCount == 0
                : shape.maximumColumnCount > 0
                    && shape.totalCellCount >= minimumCells
                    && shape.totalCellCount <= maximumCells
        else {
            throw TableWorkspacePolicyError.shapeMismatch(source.side)
        }
    }

    private static func validate(
        _ table: DelimitedTable,
        side: TableWorkspaceSide,
        limits: TableWorkspacePolicyLimits,
        formatLimits: TableWorkspaceParsingLimits,
        work: inout TableWorkspacePlanningWork
    ) throws -> TableWorkspaceTableShape {
        guard table.sourceUTF8ByteCount >= 0 else {
            throw invalidTable(side, .negativeSourceByteCount)
        }
        guard validStructuralCharacter(table.delimiter) else {
            throw invalidTable(side, .invalidDelimiter)
        }
        if let quote = table.quote {
            guard validStructuralCharacter(quote) else {
                throw invalidTable(side, .invalidQuote)
            }
            guard quote != table.delimiter else {
                throw invalidTable(side, .delimiterMatchesQuote)
            }
        }
        guard table.sourceUTF8ByteCount <= formatLimits.maximumInputBytes else {
            throw TableWorkspacePolicyError.shapeMismatch(side)
        }
        guard table.rows.count <= limits.maximumRows,
            table.rows.count <= formatLimits.maximumRows
        else {
            throw TableWorkspacePolicyError.tooManyRows(
                maximum: min(limits.maximumRows, formatLimits.maximumRows)
            )
        }

        var maximumColumnCount = 0
        var totalCellCount = 0
        var previousRowEnd = 0
        var previousSourceLine = 1
        for (rowIndex, row) in table.rows.enumerated() {
            try work.charge(1)
            guard row.index == rowIndex else {
                throw invalidTable(
                    side,
                    .invalidRowIndex(expected: rowIndex, actual: row.index)
                )
            }
            guard !row.cells.isEmpty else { throw invalidTable(side, .emptyRow(rowIndex)) }
            guard row.sourceUTF8Range.lowerBound >= previousRowEnd,
                row.sourceUTF8Range.upperBound <= table.sourceUTF8ByteCount
            else {
                throw invalidTable(side, .invalidRowRange(rowIndex))
            }
            guard row.sourceLine >= previousSourceLine, row.sourceLine > 0 else {
                throw invalidTable(side, .invalidRowSourceLine(rowIndex))
            }
            guard row.cells.count <= limits.maximumColumns,
                row.cells.count <= formatLimits.maximumColumnsPerRow
            else {
                throw TableWorkspacePolicyError.tooManyColumns(
                    maximum: min(limits.maximumColumns, formatLimits.maximumColumnsPerRow)
                )
            }
            maximumColumnCount = max(maximumColumnCount, row.cells.count)
            guard row.cells.count <= limits.maximumCells - totalCellCount,
                row.cells.count <= formatLimits.maximumTotalCells - totalCellCount
            else {
                throw TableWorkspacePolicyError.tooManyCells(
                    maximum: min(limits.maximumCells, formatLimits.maximumTotalCells)
                )
            }
            totalCellCount += row.cells.count

            var previousCellEnd = row.sourceUTF8Range.lowerBound
            for (columnIndex, cell) in row.cells.enumerated() {
                try work.charge(1)
                guard cell.index == columnIndex else {
                    throw invalidTable(
                        side,
                        .invalidCellIndex(
                            row: rowIndex,
                            expected: columnIndex,
                            actual: cell.index
                        )
                    )
                }
                guard cell.sourceUTF8Range.lowerBound >= previousCellEnd,
                    cell.sourceUTF8Range.upperBound <= row.sourceUTF8Range.upperBound
                else {
                    throw invalidTable(
                        side,
                        .invalidCellRange(row: rowIndex, column: columnIndex)
                    )
                }
                let location = cell.sourceLocation
                guard location.line >= row.sourceLine,
                    location.column > 0,
                    location.utf8Offset == cell.sourceUTF8Range.lowerBound
                else {
                    throw invalidTable(
                        side,
                        .invalidCellLocation(row: rowIndex, column: columnIndex)
                    )
                }
                let valueBytes = cell.value.utf8.count
                guard valueBytes <= formatLimits.maximumCellBytes else {
                    throw TableWorkspacePolicyError.invalidTable(
                        side: side,
                        issue: .cellValueTooLarge(
                            row: rowIndex,
                            column: columnIndex,
                            maximumUTF8Bytes: formatLimits.maximumCellBytes
                        )
                    )
                }
                try work.charge(valueBytes)
                previousCellEnd = cell.sourceUTF8Range.upperBound
            }
            previousRowEnd = row.sourceUTF8Range.upperBound
            previousSourceLine = row.sourceLine
        }
        guard totalCellCount == table.totalCellCount else {
            throw invalidTable(
                side,
                .totalCellCountMismatch(expected: totalCellCount, actual: table.totalCellCount)
            )
        }
        return TableWorkspaceTableShape(
            sourceUTF8ByteCount: table.sourceUTF8ByteCount,
            rowCount: table.rows.count,
            maximumColumnCount: maximumColumnCount,
            totalCellCount: totalCellCount
        )
    }

    private static func validate(
        _ result: TableComparisonResult,
        limits: TableWorkspacePolicyLimits,
        comparisonSettings: TableWorkspaceComparisonSettings,
        work: inout TableWorkspacePlanningWork
    ) throws -> Int {
        let inputRowCount = try checkedAdd(result.left.rows.count, result.right.rows.count) {
            TableWorkspacePolicyError.tooManyRows(maximum: comparisonSettings.maximumComparedRows)
        }
        guard inputRowCount <= comparisonSettings.maximumComparedRows else {
            throw TableWorkspacePolicyError.tooManyRows(
                maximum: comparisonSettings.maximumComparedRows
            )
        }
        let inputCellCount = try checkedAdd(
            result.left.totalCellCount,
            result.right.totalCellCount
        ) {
            TableWorkspacePolicyError.tooManyCells(
                maximum: comparisonSettings.maximumComparedCells
            )
        }
        guard inputCellCount <= comparisonSettings.maximumComparedCells else {
            throw TableWorkspacePolicyError.tooManyCells(
                maximum: comparisonSettings.maximumComparedCells
            )
        }
        guard result.rows.count <= limits.maximumRows else {
            throw TableWorkspacePolicyError.tooManyRows(maximum: limits.maximumRows)
        }
        var nextLeftRow = 0
        var nextRightRow = 0
        var resultCellCount = 0
        var summary = [TableWorkspaceComparisonStatus: Int]()

        for (rowIndex, row) in result.rows.enumerated() {
            try work.charge(1)
            guard row.index == rowIndex else {
                throw invalidResult(.invalidRowIndex(expected: rowIndex, actual: row.index))
            }
            try validateRowMapping(
                row: row,
                rowIndex: rowIndex,
                side: .left,
                table: result.left,
                nextIndex: &nextLeftRow
            )
            try validateRowMapping(
                row: row,
                rowIndex: rowIndex,
                side: .right,
                table: result.right,
                nextIndex: &nextRightRow
            )
            guard try validRowStatus(row, work: &work) else {
                throw invalidResult(.invalidRowStatus(rowIndex))
            }
            let expectedCellCount = max(row.left?.cells.count ?? 0, row.right?.cells.count ?? 0)
            guard row.cells.count == expectedCellCount else {
                throw invalidResult(
                    .invalidCellIndex(
                        row: rowIndex,
                        expected: expectedCellCount,
                        actual: row.cells.count
                    )
                )
            }
            summary[TableWorkspaceComparisonStatus(row.status), default: 0] += 1
            guard row.cells.count <= limits.maximumCells - resultCellCount else {
                throw TableWorkspacePolicyError.tooManyCells(maximum: limits.maximumCells)
            }
            resultCellCount += row.cells.count
            for (columnIndex, cell) in row.cells.enumerated() {
                try work.charge(1)
                guard cell.index == columnIndex else {
                    throw invalidResult(
                        .invalidCellIndex(
                            row: rowIndex,
                            expected: columnIndex,
                            actual: cell.index
                        )
                    )
                }
                try validateCellMapping(
                    cell: cell,
                    row: row,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    side: .left
                )
                try validateCellMapping(
                    cell: cell,
                    row: row,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    side: .right
                )
                guard try validCellStatus(cell, work: &work) else {
                    throw invalidResult(
                        .invalidCellStatus(row: rowIndex, column: columnIndex)
                    )
                }
            }
        }
        guard nextLeftRow == result.left.rows.count else {
            throw invalidResult(.incompleteRowMapping(side: .left))
        }
        guard nextRightRow == result.right.rows.count else {
            throw invalidResult(.incompleteRowMapping(side: .right))
        }
        guard summary[.equal, default: 0] == result.summary.equal,
            summary[.modified, default: 0] == result.summary.modified,
            summary[.removed, default: 0] == result.summary.removed,
            summary[.added, default: 0] == result.summary.added
        else {
            throw invalidResult(.summaryMismatch)
        }
        return resultCellCount
    }

    private static func validateRowMapping(
        row: TableRowComparison,
        rowIndex: Int,
        side: TableWorkspaceSide,
        table: DelimitedTable,
        nextIndex: inout Int
    ) throws {
        let index = side == .left ? row.leftIndex : row.rightIndex
        let mappedRow = side == .left ? row.left : row.right
        switch (index, mappedRow) {
        case (.none, .none):
            return
        case (.some(let index), .some(let mappedRow)):
            guard index == nextIndex else {
                throw invalidResult(
                    .nonMonotonicRowMapping(row: rowIndex, side: side)
                )
            }
            guard index < table.rows.count, mappedRow == table.rows[index] else {
                throw invalidResult(.invalidRowMapping(row: rowIndex, side: side))
            }
            nextIndex += 1
        default:
            throw invalidResult(.invalidRowMapping(row: rowIndex, side: side))
        }
    }

    private static func validateCellMapping(
        cell: TableCellComparison,
        row: TableRowComparison,
        rowIndex: Int,
        columnIndex: Int,
        side: TableWorkspaceSide
    ) throws {
        let index = side == .left ? cell.leftIndex : cell.rightIndex
        let mappedCell = side == .left ? cell.left : cell.right
        let mappedRow = side == .left ? row.left : row.right
        if let rowCell = mappedRow.flatMap({ columnIndex < $0.cells.count ? $0.cells[columnIndex] : nil }) {
            guard index == columnIndex, mappedCell == rowCell else {
                throw invalidResult(
                    .invalidCellMapping(row: rowIndex, column: columnIndex, side: side)
                )
            }
        } else if index != nil || mappedCell != nil {
            throw invalidResult(
                .invalidCellMapping(row: rowIndex, column: columnIndex, side: side)
            )
        }
    }

    private static func validRowStatus(
        _ row: TableRowComparison,
        work: inout TableWorkspacePlanningWork
    ) throws -> Bool {
        switch row.status {
        case .equal:
            guard let left = row.left, let right = row.right else { return false }
            return try rowValuesEqual(left, right, work: &work)
        case .modified:
            guard let left = row.left, let right = row.right else { return false }
            return try !rowValuesEqual(left, right, work: &work)
        case .removed:
            return row.left != nil && row.right == nil
        case .added:
            return row.left == nil && row.right != nil
        }
    }

    private static func rowValuesEqual(
        _ left: DelimitedTableRow,
        _ right: DelimitedTableRow,
        work: inout TableWorkspacePlanningWork
    ) throws -> Bool {
        guard left.cells.count == right.cells.count else { return false }
        for (leftCell, rightCell) in zip(left.cells, right.cells) {
            try work.charge(max(leftCell.value.utf8.count, rightCell.value.utf8.count))
            guard leftCell.value == rightCell.value else { return false }
        }
        return true
    }

    private static func validCellStatus(
        _ cell: TableCellComparison,
        work: inout TableWorkspacePlanningWork
    ) throws -> Bool {
        switch cell.status {
        case .equal:
            guard let left = cell.left, let right = cell.right else { return false }
            try work.charge(max(left.value.utf8.count, right.value.utf8.count))
            return left.value == right.value
        case .modified:
            guard let left = cell.left, let right = cell.right else { return false }
            try work.charge(max(left.value.utf8.count, right.value.utf8.count))
            return left.value != right.value
        case .removed:
            return cell.left != nil && cell.right == nil
        case .added:
            return cell.left == nil && cell.right != nil
        }
    }

    @discardableResult
    private static func validate(
        _ filters: [TableWorkspaceColumnFilter],
        maximumColumnCount: Int,
        exactSourceShapes: [TableWorkspaceSide: TableWorkspaceTableShape]?,
        limits: TableWorkspacePolicyLimits,
        work: inout TableWorkspacePlanningWork
    ) throws -> [TableWorkspaceColumnFilter] {
        guard filters.count <= limits.maximumColumnFilters else {
            throw TableWorkspacePolicyError.tooManyColumnFilters(
                maximum: limits.maximumColumnFilters
            )
        }
        var identifiers: Set<String> = []
        var totalBytes = 0
        for filter in filters {
            try work.charge(1)
            guard !filter.identifier.isEmpty else {
                throw TableWorkspacePolicyError.invalidFilterIdentifier(filter.identifier)
            }
            let identifierBytes = filter.identifier.utf8.count
            guard identifierBytes <= limits.maximumFilterIdentifierUTF8Bytes else {
                throw TableWorkspacePolicyError.filterIdentifierTooLarge(
                    maximumUTF8Bytes: limits.maximumFilterIdentifierUTF8Bytes
                )
            }
            try work.charge(identifierBytes)
            guard !filter.identifier.utf8.contains(0) else {
                throw TableWorkspacePolicyError.invalidFilterIdentifier(filter.identifier)
            }
            guard isCanonical(filter.identifier) else {
                throw TableWorkspacePolicyError.nonCanonicalPersistenceString(
                    "columnFilters.identifier"
                )
            }
            guard identifiers.insert(filter.identifier).inserted else {
                throw TableWorkspacePolicyError.duplicateFilterIdentifier(filter.identifier)
            }
            guard filter.columnIndex >= 0 else {
                throw TableWorkspacePolicyError.filterColumnOutOfBounds(
                    identifier: filter.identifier,
                    columnIndex: filter.columnIndex
                )
            }
            let side: TableWorkspaceSide?
            switch filter.condition {
            case .status:
                side = nil
            case .valueEquals(let filterSide, _), .missing(let filterSide):
                side = filterSide
            }
            let filterMaximumColumnCount =
                side.flatMap { exactSourceShapes?[$0] }?
                .maximumColumnCount ?? maximumColumnCount
            if filter.columnIndex >= filterMaximumColumnCount {
                throw TableWorkspacePolicyError.filterColumnOutOfBounds(
                    identifier: filter.identifier,
                    columnIndex: filter.columnIndex
                )
            }
            var addedBytes = identifierBytes
            if case .valueEquals(_, let value) = filter.condition {
                let valueBytes = value.utf8.count
                guard valueBytes <= limits.maximumFilterValueUTF8Bytes else {
                    throw TableWorkspacePolicyError.filterValueTooLarge(
                        identifier: filter.identifier,
                        maximumUTF8Bytes: limits.maximumFilterValueUTF8Bytes
                    )
                }
                try work.charge(valueBytes)
                guard isCanonical(value) else {
                    throw TableWorkspacePolicyError.nonCanonicalPersistenceString(
                        "columnFilters.value"
                    )
                }
                addedBytes = try checkedAdd(addedBytes, valueBytes) {
                    TableWorkspacePolicyError.totalFilterValuesTooLarge(
                        maximumUTF8Bytes: limits.maximumTotalFilterUTF8Bytes
                    )
                }
            }
            guard addedBytes <= limits.maximumTotalFilterUTF8Bytes - totalBytes else {
                throw TableWorkspacePolicyError.totalFilterValuesTooLarge(
                    maximumUTF8Bytes: limits.maximumTotalFilterUTF8Bytes
                )
            }
            totalBytes += addedBytes
        }
        return filters
    }

    private static func validate(
        _ selection: TableWorkspaceSelection,
        result: TableComparisonResult,
        maximumColumnCount: Int
    ) throws {
        switch selection {
        case .none:
            return
        case .column(let index):
            guard index >= 0, index < maximumColumnCount else {
                throw TableWorkspacePolicyError.selectionOutOfBounds
            }
        case .cells(let anchor, let focus):
            guard cellExists(anchor, in: result), cellExists(focus, in: result) else {
                throw TableWorkspacePolicyError.selectionOutOfBounds
            }
        }
    }

    private static func validatePersistedSelection(
        _ selection: TableWorkspaceSelection,
        maximumColumnCount: Int
    ) throws {
        switch selection {
        case .none:
            return
        case .column(let index):
            guard index >= 0, index < maximumColumnCount else {
                throw TableWorkspacePolicyError.selectionOutOfBounds
            }
        case .cells(let anchor, let focus):
            guard anchor.rowIndex >= 0, anchor.columnIndex >= 0,
                anchor.columnIndex < maximumColumnCount,
                focus.rowIndex >= 0, focus.columnIndex >= 0,
                focus.columnIndex < maximumColumnCount
            else {
                throw TableWorkspacePolicyError.selectionOutOfBounds
            }
        }
    }

    private static func cellExists(
        _ address: TableWorkspaceCellAddress,
        in result: TableComparisonResult
    ) -> Bool {
        guard address.rowIndex >= 0, address.rowIndex < result.rows.count else { return false }
        let row = result.rows[address.rowIndex]
        return address.columnIndex >= 0 && address.columnIndex < row.cells.count
    }

    private static func presentedValue(
        side: TableWorkspaceSide,
        row: DelimitedTableRow?,
        cell: DelimitedTableCell?,
        byteCount: inout Int,
        limits: TableWorkspacePolicyLimits,
        work: inout TableWorkspacePlanningWork
    ) throws -> TableWorkspacePresentedValue? {
        guard let row, let cell else { return nil }
        let count = cell.value.utf8.count
        guard count <= limits.maximumPresentedUTF8Bytes - byteCount else {
            throw TableWorkspacePolicyError.presentedValuesTooLarge(
                maximumUTF8Bytes: limits.maximumPresentedUTF8Bytes
            )
        }
        byteCount += count
        try work.charge(count)
        return TableWorkspacePresentedValue(side: side, row: row, cell: cell)
    }

    private static func rowIsVisible(
        cells: [TableWorkspaceCellPresentation],
        filters: [TableWorkspaceColumnFilter],
        work: inout TableWorkspacePlanningWork
    ) throws -> Bool {
        for filter in filters {
            try work.charge(1)
            let cell = filter.columnIndex < cells.count ? cells[filter.columnIndex] : nil
            let matches = try filterMatches(filter.condition, cell: cell, work: &work)
            switch filter.disposition {
            case .includeMatchingRows where !matches:
                return false
            case .excludeMatchingRows where matches:
                return false
            default:
                continue
            }
        }
        return true
    }

    private static func filterMatches(
        _ condition: TableWorkspaceColumnFilterCondition,
        cell: TableWorkspaceCellPresentation?,
        work: inout TableWorkspacePlanningWork
    ) throws -> Bool {
        switch condition {
        case .status(let status):
            return cell?.status == status
        case .valueEquals(let side, let value):
            let actual = side == .left ? cell?.left?.value : cell?.right?.value
            if let actual {
                try work.charge(max(actual.utf8.count, value.utf8.count))
            }
            return actual == value
        case .missing(let side):
            return side == .left ? cell?.left == nil : cell?.right == nil
        }
    }

    private static func makeEditIntent(
        _ request: TableWorkspaceEditRequest,
        dataset: TableWorkspaceDatasetSnapshot,
        sources: [TableWorkspaceSourceBinding],
        presentation: TableWorkspacePresentation,
        limits: TableWorkspacePolicyLimits,
        work: inout TableWorkspacePlanningWork
    ) throws -> TableWorkspaceEditIntent {
        try work.charge(1)
        guard request.address.rowIndex >= 0,
            request.address.rowIndex < presentation.rows.count
        else {
            throw TableWorkspacePolicyError.editTargetOutOfBounds
        }
        let row = presentation.rows[request.address.rowIndex]
        guard request.address.columnIndex >= 0,
            request.address.columnIndex < row.cells.count
        else {
            throw TableWorkspacePolicyError.editTargetOutOfBounds
        }
        let source = sources[request.side == .left ? 0 : 1]
        guard source.isEditable else {
            throw TableWorkspacePolicyError.editTargetReadOnly(request.side)
        }
        let cell = row.cells[request.address.columnIndex]
        let presentedValue = request.side == .left ? cell.left : cell.right
        guard let presentedValue else {
            throw TableWorkspacePolicyError.editTargetMissing(request.side)
        }
        let expectedBytes = request.expectedPresentedValue.utf8.count
        let replacementBytes = request.replacementPresentedValue.utf8.count
        let maximumEditValueUTF8Bytes = min(
            limits.maximumEditValueUTF8Bytes,
            dataset.configuration.format.limits.maximumCellBytes
        )
        guard expectedBytes <= maximumEditValueUTF8Bytes,
            replacementBytes <= maximumEditValueUTF8Bytes
        else {
            throw TableWorkspacePolicyError.editValueTooLarge(
                maximumUTF8Bytes: maximumEditValueUTF8Bytes
            )
        }
        try work.charge(
            try checkedAdd(expectedBytes, replacementBytes) {
                TableWorkspacePolicyError.planningWorkLimitExceeded(
                    maximum: limits.maximumPlanningWorkUnits
                )
            })
        guard request.expectedPresentedValue == presentedValue.value else {
            throw TableWorkspacePolicyError.editExpectedValueChanged
        }
        guard request.replacementPresentedValue != presentedValue.value else {
            throw TableWorkspacePolicyError.editWouldNotChangeValue
        }
        return TableWorkspaceEditIntent(
            datasetReference: dataset.reference,
            source: source,
            presentationAddress: request.address,
            presentedValue: presentedValue,
            replacementPresentedValue: request.replacementPresentedValue
        )
    }

    private static func value(_ row: DelimitedTableRow?, at columnIndex: Int) -> String? {
        guard let row, columnIndex < row.cells.count else { return nil }
        return row.cells[columnIndex].value
    }

    private static func validStructuralCharacter(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return false }
        return scalar != "\0" && scalar != "\r" && scalar != "\n"
    }

    private static func isCanonical(_ string: String) -> Bool {
        Array(string.utf8) == Array(string.precomposedStringWithCanonicalMapping.utf8)
    }

    private static func invalidTable(
        _ side: TableWorkspaceSide,
        _ issue: TableWorkspaceTableValidationIssue
    ) -> TableWorkspacePolicyError {
        .invalidTable(side: side, issue: issue)
    }

    private static func invalidResult(
        _ issue: TableWorkspaceResultValidationIssue
    ) -> TableWorkspacePolicyError {
        .invalidComparisonResult(issue)
    }

    fileprivate static func checkedAdd(
        _ left: Int,
        _ right: Int,
        error: () -> TableWorkspacePolicyError
    ) throws -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw error() }
        return result
    }
}

private struct TableWorkspacePlanningWork {
    let limits: TableWorkspacePolicyLimits
    let cancellationCheck: TableWorkspacePolicy.CancellationCheck
    private(set) var consumed = 0
    private var sinceCancellationCheck = 0

    init(
        limits: TableWorkspacePolicyLimits,
        cancellationCheck: @escaping TableWorkspacePolicy.CancellationCheck
    ) {
        self.limits = limits
        self.cancellationCheck = cancellationCheck
    }

    mutating func charge(_ amount: Int) throws {
        guard amount >= 0, amount <= limits.maximumPlanningWorkUnits - consumed else {
            throw TableWorkspacePolicyError.planningWorkLimitExceeded(
                maximum: limits.maximumPlanningWorkUnits
            )
        }
        consumed += amount
        var remaining = amount
        if sinceCancellationCheck > 0 {
            let untilCheck = limits.cancellationCheckInterval - sinceCancellationCheck
            guard remaining >= untilCheck else {
                sinceCancellationCheck += remaining
                return
            }
            remaining -= untilCheck
            try TableWorkspacePolicy.performCancellationCheck(cancellationCheck)
            sinceCancellationCheck = 0
        }
        while remaining >= limits.cancellationCheckInterval {
            remaining -= limits.cancellationCheckInterval
            try TableWorkspacePolicy.performCancellationCheck(cancellationCheck)
        }
        sinceCancellationCheck = remaining
    }
}

public struct TableWorkspacePersistenceReceipt: Hashable, Sendable {
    public let state: TableWorkspaceState
    public let data: Data
    public let formatVersion: Int

    fileprivate init(state: TableWorkspaceState, data: Data) {
        self.state = state
        self.data = data
        formatVersion = TableWorkspaceState.currentSchemaVersion
    }
}

private enum TableWorkspacePersistence {
    private static let magic: [UInt8] = [0x4D, 0x4D, 0x54, 0x57]

    static func encode(
        _ state: TableWorkspaceState,
        limits: TableWorkspacePolicyLimits,
        cancellationCheck: @escaping TableWorkspacePolicy.CancellationCheck
    ) throws -> TableWorkspacePersistenceReceipt {
        do {
            try TableWorkspacePolicy.performCancellationCheck(cancellationCheck)
            try TableWorkspacePolicy.validate(limits)
            var work = TableWorkspacePlanningWork(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            try TableWorkspacePolicy.validateStateStructure(state, limits: limits, work: &work)
            var writer = TableWorkspaceBinaryWriter(maximumBytes: limits.maximumPersistedBytes)
            try writer.append(bytes: magic)
            try writer.append(UInt8(TableWorkspaceState.currentSchemaVersion))
            try writer.append(state.datasetReference.identity.rawValue)
            try writer.append(state.datasetReference.revision)
            try writer.append(UInt8(state.sources.count))
            for source in state.sources.sorted(by: { $0.side.rawValue < $1.side.rawValue }) {
                try writer.append(source: source)
            }
            try writer.append(configuration: state.configuration)
            try writer.append(presentationOptions: state.presentationOptions)
            try writer.append(UInt32(exactly: state.columnFilters.count))
            for filter in state.columnFilters {
                try work.charge(1)
                try writer.append(filter: filter)
            }
            try writer.append(selection: state.selection)
            try TableWorkspacePolicy.performCancellationCheck(cancellationCheck)
            return TableWorkspacePersistenceReceipt(state: state, data: writer.data)
        } catch is CancellationError {
            throw TableWorkspacePolicyError.cancelled
        }
    }

    static func decode(
        _ data: Data,
        limits: TableWorkspacePolicyLimits,
        cancellationCheck: @escaping TableWorkspacePolicy.CancellationCheck
    ) throws -> TableWorkspacePersistenceReceipt {
        do {
            try TableWorkspacePolicy.performCancellationCheck(cancellationCheck)
            try TableWorkspacePolicy.validate(limits)
            guard data.count <= limits.maximumPersistedBytes else {
                throw TableWorkspacePolicyError.persistenceDataTooLarge(
                    maximumBytes: limits.maximumPersistedBytes
                )
            }
            let snapshot = data.withUnsafeBytes { bytes -> Data in
                guard let base = bytes.baseAddress else { return Data() }
                return Data(bytes: base, count: bytes.count)
            }
            var reader = TableWorkspaceBinaryReader(data: snapshot)
            guard try reader.readBytes(count: magic.count) == magic else {
                throw TableWorkspacePolicyError.malformedPersistence
            }
            let version = Int(try reader.readUInt8())
            guard version == TableWorkspaceState.currentSchemaVersion else {
                throw TableWorkspacePolicyError.unsupportedSchemaVersion(version)
            }
            let reference = TableWorkspaceDatasetReference(
                identity: TableWorkspaceDatasetIdentity(rawValue: try reader.readUUID()),
                revision: try reader.readUInt64()
            )
            let sourceCount = Int(try reader.readUInt8())
            guard sourceCount == limits.maximumSourceCount else {
                throw TableWorkspacePolicyError.sourceCountInvalid(sourceCount)
            }
            var sources: [TableWorkspaceSourceBinding] = []
            sources.reserveCapacity(sourceCount)
            for _ in 0..<sourceCount { sources.append(try reader.readSourceBinding()) }
            guard sources.map(\.side) == TableWorkspaceSide.allCases else {
                throw TableWorkspacePolicyError.malformedPersistence
            }
            let configuration = try reader.readConfiguration()
            let presentationOptions = try reader.readPresentationOptions()
            let filterCount = Int(try reader.readUInt32())
            guard filterCount <= limits.maximumColumnFilters else {
                throw TableWorkspacePolicyError.tooManyColumnFilters(
                    maximum: limits.maximumColumnFilters
                )
            }
            var filters: [TableWorkspaceColumnFilter] = []
            filters.reserveCapacity(filterCount)
            for _ in 0..<filterCount {
                try TableWorkspacePolicy.performCancellationCheck(cancellationCheck)
                filters.append(try reader.readFilter(limits: limits))
            }
            let selection = try reader.readSelection()
            guard reader.isAtEnd else {
                throw TableWorkspacePolicyError.trailingPersistenceData
            }
            let state = TableWorkspaceState(
                datasetReference: reference,
                sources: sources,
                configuration: configuration,
                presentationOptions: presentationOptions,
                columnFilters: filters,
                selection: selection
            )
            var work = TableWorkspacePlanningWork(
                limits: limits,
                cancellationCheck: cancellationCheck
            )
            try TableWorkspacePolicy.validateStateStructure(state, limits: limits, work: &work)
            try TableWorkspacePolicy.performCancellationCheck(cancellationCheck)
            return TableWorkspacePersistenceReceipt(state: state, data: snapshot)
        } catch let error as TableWorkspacePolicyError {
            throw error
        } catch is CancellationError {
            throw TableWorkspacePolicyError.cancelled
        } catch {
            throw TableWorkspacePolicyError.malformedPersistence
        }
    }
}

private struct TableWorkspaceBinaryWriter {
    private(set) var data = Data()
    let maximumBytes: Int

    mutating func append(_ value: UInt8) throws {
        try reserve(1)
        data.append(value)
    }

    mutating func append(_ value: Bool) throws {
        try append(value ? UInt8(1) : UInt8(0))
    }

    mutating func append(_ value: UInt32?) throws {
        guard let value else { throw TableWorkspacePolicyError.malformedPersistence }
        try append(value)
    }

    mutating func append(_ value: UInt32) throws {
        try append(bytes: [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ])
    }

    mutating func append(_ value: UInt64) throws {
        try append(
            bytes: (0..<8).map { shift in
                UInt8((value >> UInt64((7 - shift) * 8)) & 0xFF)
            })
    }

    mutating func append(_ value: Int) throws {
        guard value >= 0 else { throw TableWorkspacePolicyError.malformedPersistence }
        try append(UInt64(value))
    }

    mutating func append(_ value: UUID) throws {
        var tuple = value.uuid
        let bytes = withUnsafeBytes(of: &tuple) { Array($0) }
        try append(bytes: bytes)
    }

    mutating func append(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard let count = UInt32(exactly: bytes.count) else {
            throw TableWorkspacePolicyError.persistenceDataTooLarge(maximumBytes: maximumBytes)
        }
        try append(count)
        try append(bytes: bytes)
    }

    mutating func append(bytes: [UInt8]) throws {
        try reserve(bytes.count)
        data.append(contentsOf: bytes)
    }

    mutating func append(configuration: TableWorkspaceConfiguration) throws {
        try append(String(configuration.format.delimiter))
        try append(configuration.format.quote != nil)
        if let quote = configuration.format.quote { try append(String(quote)) }
        try append(configuration.format.allowsNewlinesInQuotedCells)
        let parsing = configuration.format.limits
        try append(parsing.maximumInputBytes)
        try append(parsing.maximumRows)
        try append(parsing.maximumColumnsPerRow)
        try append(parsing.maximumTotalCells)
        try append(parsing.maximumCellBytes)
        let comparison = configuration.comparison
        try append(comparison.maximumExactEditDistance)
        try append(comparison.maximumAlignmentWork)
        try append(comparison.maximumComparedRows)
        try append(comparison.maximumComparedCells)
    }

    mutating func append(source: TableWorkspaceSourceBinding) throws {
        try append(source.side == .left ? UInt8(0) : UInt8(1))
        try append(source.sourceIdentity.rawValue)
        try append(source.sourceRevision)
        try append(source.tableIdentity.rawValue)
        try append(source.tableRevision)
        try append(source.shape.sourceUTF8ByteCount)
        try append(source.shape.rowCount)
        try append(source.shape.maximumColumnCount)
        try append(source.shape.totalCellCount)
        try append(source.isEditable)
    }

    mutating func append(presentationOptions: TableWorkspacePresentationOptions) throws {
        try append(presentationOptions.headerVisibility.rawValue)
        try append(presentationOptions.headerLabels.rawValue)
        try append(presentationOptions.showsRowNumbers)
        try append(presentationOptions.wrapsCellText)
        try append(presentationOptions.synchronizesColumnWidths)
        try append(presentationOptions.highlightsCellDifferences)
    }

    mutating func append(filter: TableWorkspaceColumnFilter) throws {
        try append(filter.identifier)
        try append(filter.columnIndex)
        switch filter.condition {
        case .status(let status):
            try append(UInt8(0))
            try append(status.rawValue)
        case .valueEquals(let side, let value):
            try append(UInt8(1))
            try append(side == .left ? UInt8(0) : UInt8(1))
            try append(value)
        case .missing(let side):
            try append(UInt8(2))
            try append(side == .left ? UInt8(0) : UInt8(1))
        }
        try append(filter.disposition.rawValue)
    }

    mutating func append(selection: TableWorkspaceSelection) throws {
        switch selection {
        case .none:
            try append(UInt8(0))
        case .cells(let anchor, let focus):
            try append(UInt8(1))
            try append(anchor.rowIndex)
            try append(anchor.columnIndex)
            try append(focus.rowIndex)
            try append(focus.columnIndex)
        case .column(let index):
            try append(UInt8(2))
            try append(index)
        }
    }

    private mutating func reserve(_ count: Int) throws {
        guard count >= 0, count <= maximumBytes - data.count else {
            throw TableWorkspacePolicyError.persistenceDataTooLarge(maximumBytes: maximumBytes)
        }
    }
}

private struct TableWorkspaceBinaryReader {
    let data: Data
    private var offset = 0

    var isAtEnd: Bool { offset == data.count }

    init(data: Data) {
        self.data = data
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw TableWorkspacePolicyError.malformedPersistence }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readBool() throws -> Bool {
        switch try readUInt8() {
        case 0: false
        case 1: true
        default: throw TableWorkspacePolicyError.malformedPersistence
        }
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try readBytes(count: 8)
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func readInt() throws -> Int {
        let value = try readUInt64()
        guard let result = Int(exactly: value) else {
            throw TableWorkspacePolicyError.malformedPersistence
        }
        return result
    }

    mutating func readUUID() throws -> UUID {
        let bytes = try readBytes(count: 16)
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }

    mutating func readString(maximumUTF8Bytes: Int) throws -> String {
        let count = Int(try readUInt32())
        guard count <= maximumUTF8Bytes else {
            throw TableWorkspacePolicyError.malformedPersistence
        }
        let bytes = try readBytes(count: count)
        guard let value = String(bytes: bytes, encoding: .utf8) else {
            throw TableWorkspacePolicyError.malformedPersistence
        }
        return value
    }

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, count <= data.count - offset else {
            throw TableWorkspacePolicyError.malformedPersistence
        }
        defer { offset += count }
        return Array(data[offset..<(offset + count)])
    }

    mutating func readConfiguration() throws -> TableWorkspaceConfiguration {
        let delimiter = try readStructuralCharacter()
        let hasQuote = try readBool()
        let quote = hasQuote ? try readStructuralCharacter() : nil
        let allowsNewlines = try readBool()
        let parsing = TableWorkspaceParsingLimits(
            maximumInputBytes: try readInt(),
            maximumRows: try readInt(),
            maximumColumnsPerRow: try readInt(),
            maximumTotalCells: try readInt(),
            maximumCellBytes: try readInt()
        )
        let comparison = TableWorkspaceComparisonSettings(
            maximumExactEditDistance: try readInt(),
            maximumAlignmentWork: try readInt(),
            maximumComparedRows: try readInt(),
            maximumComparedCells: try readInt()
        )
        return TableWorkspaceConfiguration(
            format: TableWorkspaceFormatSettings(
                delimiter: delimiter,
                quote: quote,
                allowsNewlinesInQuotedCells: allowsNewlines,
                limits: parsing
            ),
            comparison: comparison
        )
    }

    mutating func readSourceBinding() throws -> TableWorkspaceSourceBinding {
        let side = try readSide()
        return TableWorkspaceSourceBinding(
            side: side,
            sourceIdentity: TableWorkspaceSourceIdentity(rawValue: try readUUID()),
            sourceRevision: try readUInt64(),
            tableIdentity: TableWorkspaceTableIdentity(rawValue: try readUUID()),
            tableRevision: try readUInt64(),
            shape: TableWorkspaceTableShape(
                sourceUTF8ByteCount: try readInt(),
                rowCount: try readInt(),
                maximumColumnCount: try readInt(),
                totalCellCount: try readInt()
            ),
            isEditable: try readBool()
        )
    }

    mutating func readPresentationOptions() throws -> TableWorkspacePresentationOptions {
        guard let headerVisibility = TableWorkspaceHeaderVisibility(rawValue: try readUInt8()),
            let headerLabels = TableWorkspaceHeaderLabels(rawValue: try readUInt8())
        else {
            throw TableWorkspacePolicyError.malformedPersistence
        }
        return TableWorkspacePresentationOptions(
            headerVisibility: headerVisibility,
            headerLabels: headerLabels,
            showsRowNumbers: try readBool(),
            wrapsCellText: try readBool(),
            synchronizesColumnWidths: try readBool(),
            highlightsCellDifferences: try readBool()
        )
    }

    mutating func readFilter(
        limits: TableWorkspacePolicyLimits
    ) throws -> TableWorkspaceColumnFilter {
        let identifier = try readString(
            maximumUTF8Bytes: limits.maximumFilterIdentifierUTF8Bytes
        )
        let columnIndex = try readInt()
        let condition: TableWorkspaceColumnFilterCondition
        switch try readUInt8() {
        case 0:
            guard let status = TableWorkspaceComparisonStatus(rawValue: try readUInt8()) else {
                throw TableWorkspacePolicyError.malformedPersistence
            }
            condition = .status(status)
        case 1:
            condition = .valueEquals(
                side: try readSide(),
                value: try readString(maximumUTF8Bytes: limits.maximumFilterValueUTF8Bytes)
            )
        case 2:
            condition = .missing(side: try readSide())
        default:
            throw TableWorkspacePolicyError.malformedPersistence
        }
        guard
            let disposition = TableWorkspaceColumnFilterDisposition(
                rawValue: try readUInt8()
            )
        else {
            throw TableWorkspacePolicyError.malformedPersistence
        }
        return TableWorkspaceColumnFilter(
            identifier: identifier,
            columnIndex: columnIndex,
            condition: condition,
            disposition: disposition
        )
    }

    mutating func readSelection() throws -> TableWorkspaceSelection {
        switch try readUInt8() {
        case 0:
            return .none
        case 1:
            return .cells(
                anchor: TableWorkspaceCellAddress(
                    rowIndex: try readInt(),
                    columnIndex: try readInt()
                ),
                focus: TableWorkspaceCellAddress(
                    rowIndex: try readInt(),
                    columnIndex: try readInt()
                )
            )
        case 2:
            return .column(try readInt())
        default:
            throw TableWorkspacePolicyError.malformedPersistence
        }
    }

    private mutating func readSide() throws -> TableWorkspaceSide {
        switch try readUInt8() {
        case 0: .left
        case 1: .right
        default: throw TableWorkspacePolicyError.malformedPersistence
        }
    }

    private mutating func readStructuralCharacter() throws -> Character {
        let value = try readString(maximumUTF8Bytes: 4)
        guard value.unicodeScalars.count == 1, let character = value.first,
            String(character) == value
        else {
            throw TableWorkspacePolicyError.malformedPersistence
        }
        return character
    }
}
