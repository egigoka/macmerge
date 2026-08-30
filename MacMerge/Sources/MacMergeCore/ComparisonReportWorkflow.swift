import Foundation

public struct ComparisonReportWorkflowSnapshotIdentity: Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// File-report selection is expressed as zero-based row indices in the immutable report.
public struct ComparisonReportFileSnapshot: Equatable, Sendable {
    public let report: ComparisonReport
    public let selectedRowIndices: Set<Int>

    public init(
        report: ComparisonReport,
        selectedRowIndices: Set<Int> = []
    ) {
        self.report = report
        self.selectedRowIndices = selectedRowIndices
    }
}

/// Caller-captured canonical filesystem identity for one pinned directory-root pair. Planning never
/// resolves either root; executors must compare descriptor identities rather than paths.
public struct ComparisonReportWorkflowDirectoryRootIdentity: Equatable, Hashable, Sendable {
    public struct Node: Equatable, Hashable, Sendable {
        public let deviceID: UInt64
        public let fileID: UInt64
        public let generation: UInt32

        public init(deviceID: UInt64, fileID: UInt64, generation: UInt32) {
            self.deviceID = deviceID
            self.fileID = fileID
            self.generation = generation
        }
    }

    public let left: Node
    public let right: Node

    public init(left: Node, right: Node) {
        self.left = left
        self.right = right
    }
}

public struct ComparisonReportFolderSnapshot: Equatable, Sendable {
    public let rootIdentity: ComparisonReportWorkflowDirectoryRootIdentity
    public let results: DirectoryResults

    public init(
        rootIdentity: ComparisonReportWorkflowDirectoryRootIdentity,
        results: DirectoryResults
    ) {
        self.rootIdentity = rootIdentity
        self.results = results
    }
}

public enum ComparisonReportWorkflowSource: Equatable, Sendable {
    case file(ComparisonReportFileSnapshot)
    case folder(ComparisonReportFolderSnapshot)
}

/// Immutable report input. For one identity, `generation` must be an opaque, never-reused token and
/// must change whenever source report data, directory results, filtering, sorting, or selection changes.
public struct ComparisonReportWorkflowSnapshot: Equatable, Sendable {
    public let identity: ComparisonReportWorkflowSnapshotIdentity
    public let generation: UInt64
    public let source: ComparisonReportWorkflowSource

    public init(
        identity: ComparisonReportWorkflowSnapshotIdentity,
        generation: UInt64,
        source: ComparisonReportWorkflowSource
    ) {
        self.identity = identity
        self.generation = generation
        self.source = source
    }
}

public struct ComparisonReportWorkflowSnapshotReference: Equatable, Hashable, Sendable {
    public let identity: ComparisonReportWorkflowSnapshotIdentity
    public let generation: UInt64

    public init(identity: ComparisonReportWorkflowSnapshotIdentity, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }

    public init(_ snapshot: ComparisonReportWorkflowSnapshot) {
        identity = snapshot.identity
        generation = snapshot.generation
    }
}

public enum ComparisonReportScope: String, CaseIterable, Equatable, Hashable, Sendable {
    case all
    case selected
}

public enum ComparisonReportOverwritePolicy: String, CaseIterable, Equatable, Hashable, Sendable {
    case failIfExists
    case replaceExisting
}

public enum ComparisonReportSecurityScopeCoverage: String, Equatable, Hashable, Sendable {
    case exactFile
    case directoryTree
}

/// Declares authorization already available to a future executor. Planning never starts access.
public enum ComparisonReportSandboxAccess: Equatable, Hashable, Sendable {
    case ambient
    case securityScoped(resourceURL: URL, coverage: ComparisonReportSecurityScopeCoverage)
}

public struct ComparisonReportFileDestination: Equatable, Hashable, Sendable {
    /// Original caller-owned URL. Executors retain it because it may carry sandbox authorization.
    public let url: URL
    public let overwritePolicy: ComparisonReportOverwritePolicy
    public let sandboxAccess: ComparisonReportSandboxAccess

    public init(
        url: URL,
        overwritePolicy: ComparisonReportOverwritePolicy = .failIfExists,
        sandboxAccess: ComparisonReportSandboxAccess = .ambient
    ) {
        self.url = url
        self.overwritePolicy = overwritePolicy
        self.sandboxAccess = sandboxAccess
    }
}

public enum ComparisonReportOutputDestination: Equatable, Hashable, Sendable {
    case file(ComparisonReportFileDestination)
    case clipboard
}

/// One child report published beside the primary file. `relativeOutputPath` is interpreted relative
/// to the primary file's parent directory and may not contain empty, `.` or `..` components.
public struct ComparisonReportLinkedReport: Equatable, Sendable {
    public let identifier: String
    public let relativeOutputPath: String
    public let report: ComparisonReport
    /// Root snapshot from which this child report was captured.
    public let snapshot: ComparisonReportWorkflowSnapshotReference
    /// Optional folder row represented by this child report.
    public let directoryResultID: DirectoryResult.ID?

    public init(
        identifier: String,
        relativeOutputPath: String,
        report: ComparisonReport,
        snapshot: ComparisonReportWorkflowSnapshotReference,
        directoryResultID: DirectoryResult.ID? = nil
    ) {
        self.identifier = identifier
        self.relativeOutputPath = relativeOutputPath
        self.report = report
        self.snapshot = snapshot
        self.directoryResultID = directoryResultID
    }
}

public struct ComparisonReportWorkflowLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumReportCount = 4_096
    public static let hardMaximumRowCount = ComparisonReport.maximumRowCount
    public static let hardMaximumItemCount = ComparisonReport.maximumInputValueCount
    public static let hardMaximumInputUTF8Bytes = 256 * 1_024 * 1_024
    public static let hardMaximumOutputBytes = 512 * 1_024 * 1_024
    public static let hardMaximumOutputBytesPerReport = 256 * 1_024 * 1_024
    public static let hardMaximumWorkUnits = 2 * 1_024 * 1_024 * 1_024
    public static let hardMaximumSynchronousGenerationWorkUnits = 8 * 1_024 * 1_024
    public static let hardMaximumPathUTF8Bytes = 16 * 1_024
    public static let hardMaximumTotalPathUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumIdentifierUTF8Bytes = 4 * 1_024
    public static let `default` = ComparisonReportWorkflowLimits()

    public let maximumReportCount: Int
    public let maximumRowCount: Int
    public let maximumItemCount: Int
    public let maximumInputUTF8Bytes: Int
    public let maximumOutputBytes: Int
    public let maximumOutputBytesPerReport: Int
    /// Bounds all planner scans and allocations. Uninterruptible report generation is also subject to
    /// `hardMaximumSynchronousGenerationWorkUnits` after its conservative cost is charged.
    public let maximumWorkUnits: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumIdentifierUTF8Bytes: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumReportCount: Int = 1_024,
        maximumRowCount: Int = ComparisonReport.maximumRowCount,
        maximumItemCount: Int = ComparisonReport.maximumInputValueCount,
        maximumInputUTF8Bytes: Int = 128 * 1_024 * 1_024,
        maximumOutputBytes: Int = 128 * 1_024 * 1_024,
        maximumOutputBytesPerReport: Int = ComparisonReport.defaultMaximumOutputBytes,
        maximumWorkUnits: Int = 512 * 1_024 * 1_024,
        maximumPathUTF8Bytes: Int = 4 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumIdentifierUTF8Bytes: Int = 1_024,
        cancellationCheckInterval: Int = 1_024
    ) {
        self.maximumReportCount = maximumReportCount
        self.maximumRowCount = maximumRowCount
        self.maximumItemCount = maximumItemCount
        self.maximumInputUTF8Bytes = maximumInputUTF8Bytes
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumOutputBytesPerReport = maximumOutputBytesPerReport
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumIdentifierUTF8Bytes = maximumIdentifierUTF8Bytes
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public struct ComparisonReportWorkflowRequest: Equatable, Sendable {
    public let snapshot: ComparisonReportWorkflowSnapshot
    public let scope: ComparisonReportScope
    public let format: ComparisonReportFormat
    public let destination: ComparisonReportOutputDestination
    public let linkedReports: [ComparisonReportLinkedReport]
    public let openAfterGeneration: Bool
    public let limits: ComparisonReportWorkflowLimits

    public init(
        snapshot: ComparisonReportWorkflowSnapshot,
        scope: ComparisonReportScope = .all,
        format: ComparisonReportFormat,
        destination: ComparisonReportOutputDestination,
        linkedReports: [ComparisonReportLinkedReport] = [],
        openAfterGeneration: Bool = false,
        limits: ComparisonReportWorkflowLimits = .default
    ) {
        self.snapshot = snapshot
        self.scope = scope
        self.format = format
        self.destination = destination
        self.linkedReports = linkedReports
        self.openAfterGeneration = openAfterGeneration
        self.limits = limits
    }
}

public enum ComparisonReportPlannedOutputRole: Equatable, Hashable, Sendable {
    case primary
    case linked(identifier: String, directoryResultID: DirectoryResult.ID?)
}

/// Lexical canonical identity. Executors must additionally resolve and pin filesystem identities;
/// this value alone is not authorization and cannot detect links, aliases, mount changes, or case
/// equivalence on an unknown destination volume.
public struct ComparisonReportCanonicalOutputIdentity: Equatable, Hashable, Sendable {
    public let fileURL: URL
    public let canonicalPath: String
    public let canonicalPathUTF8Bytes: [UInt8]

    fileprivate init(fileURL: URL, canonicalPath: String, canonicalPathUTF8Bytes: [UInt8]) {
        self.fileURL = fileURL
        self.canonicalPath = canonicalPath
        self.canonicalPathUTF8Bytes = canonicalPathUTF8Bytes
    }

    public static func == (
        left: ComparisonReportCanonicalOutputIdentity,
        right: ComparisonReportCanonicalOutputIdentity
    ) -> Bool {
        left.canonicalPathUTF8Bytes == right.canonicalPathUTF8Bytes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(canonicalPathUTF8Bytes)
    }
}

public enum ComparisonReportPlannedDestination: Equatable, Hashable, Sendable {
    case file(
        requestedURL: URL,
        identity: ComparisonReportCanonicalOutputIdentity,
        overwritePolicy: ComparisonReportOverwritePolicy,
        sandboxAccess: ComparisonReportSandboxAccess
    )
    case clipboard

    public var outputIdentity: ComparisonReportOutputIdentity {
        switch self {
        case .file(_, let identity, _, _):
            .file(identity)
        case .clipboard:
            .clipboard
        }
    }
}

public enum ComparisonReportOutputIdentity: Equatable, Hashable, Sendable {
    case file(ComparisonReportCanonicalOutputIdentity)
    case clipboard
}

/// Complete immutable bytes for one output. Executors publish `output.data` byte-for-byte and never
/// regenerate it from mutable application state.
public struct ComparisonReportPlannedOutput: Equatable, Sendable {
    public let role: ComparisonReportPlannedOutputRole
    public let destination: ComparisonReportPlannedDestination
    public let output: ComparisonReportOutput
    public let inputItemCount: Int
    public let inputUTF8ByteCount: Int
    public let estimatedWorkUnits: Int

    public var outputByteCount: Int { output.data.count }

    fileprivate init(
        role: ComparisonReportPlannedOutputRole,
        destination: ComparisonReportPlannedDestination,
        output: ComparisonReportOutput,
        inputItemCount: Int,
        inputUTF8ByteCount: Int,
        estimatedWorkUnits: Int
    ) {
        self.role = role
        self.destination = destination
        self.output = output
        self.inputItemCount = inputItemCount
        self.inputUTF8ByteCount = inputUTF8ByteCount
        self.estimatedWorkUnits = estimatedWorkUnits
    }
}

public struct ComparisonReportWorkflowEstimate: Equatable, Hashable, Sendable {
    public let reportCount: Int
    public let rowCount: Int
    public let inputItemCount: Int
    public let inputUTF8ByteCount: Int
    /// Exact byte count of already-generated planned output, named as an estimate for executor UI.
    public let estimatedOutputByteCount: Int
    /// Deterministic planning estimate. It is not a promise about executor or filesystem cost.
    public let estimatedWorkUnits: Int

    fileprivate init(
        reportCount: Int,
        rowCount: Int,
        inputItemCount: Int,
        inputUTF8ByteCount: Int,
        estimatedOutputByteCount: Int,
        estimatedWorkUnits: Int
    ) {
        self.reportCount = reportCount
        self.rowCount = rowCount
        self.inputItemCount = inputItemCount
        self.inputUTF8ByteCount = inputUTF8ByteCount
        self.estimatedOutputByteCount = estimatedOutputByteCount
        self.estimatedWorkUnits = estimatedWorkUnits
    }
}

public struct ComparisonReportWorkflowSnapshotFingerprint: Equatable, Sendable {
    public let reference: ComparisonReportWorkflowSnapshotReference
    public let sourceItemCount: Int
    public let sourceUTF8ByteCount: Int
    fileprivate let source: ComparisonReportWorkflowFingerprintSource
    fileprivate let linkedReports: [ComparisonReportLinkedReport]
    fileprivate let scope: ComparisonReportScope

    fileprivate init(
        request: ComparisonReportWorkflowRequest,
        linkedReports: [ComparisonReportLinkedReport],
        sourceItemCount: Int,
        sourceUTF8ByteCount: Int
    ) {
        reference = ComparisonReportWorkflowSnapshotReference(request.snapshot)
        self.sourceItemCount = sourceItemCount
        self.sourceUTF8ByteCount = sourceUTF8ByteCount
        self.linkedReports = linkedReports
        scope = request.scope
        source = ComparisonReportWorkflowFingerprintSource(request.snapshot.source)
    }
}

private enum ComparisonReportWorkflowFingerprintSource: Equatable, Sendable {
    case file(report: ComparisonReport, selectedRowIndices: Set<Int>)
    case folder(
        rootIdentity: ComparisonReportWorkflowDirectoryRootIdentity,
        leftRoot: String,
        rightRoot: String,
        results: [DirectoryResult],
        filter: DirectoryResultFilter,
        sortDescriptors: [DirectoryResultSortDescriptor],
        selectedIDs: Set<DirectoryResult.ID>
    )

    init(_ source: ComparisonReportWorkflowSource) {
        switch source {
        case .file(let snapshot):
            self = .file(
                report: snapshot.report,
                selectedRowIndices: snapshot.selectedRowIndices
            )
        case .folder(let snapshot):
            let results = snapshot.results
            self = .folder(
                rootIdentity: snapshot.rootIdentity,
                leftRoot: results.leftRoot.absoluteString,
                rightRoot: results.rightRoot.absoluteString,
                results: results.results,
                filter: results.filter,
                sortDescriptors: results.sortDescriptors,
                selectedIDs: results.selectedIDs
            )
        }
    }
}

public enum ComparisonReportExecutorPathResolutionContract: String, Equatable, Hashable, Sendable {
    case canonicalDescriptorRelativeNoFollow
}

public enum ComparisonReportExecutorPublicationContract: String, Equatable, Hashable, Sendable {
    case publishExactPlannedBytesAtomicallyInPlanOrder
}

public enum ComparisonReportExecutorSecurityScopeContract: String, Equatable, Hashable, Sendable {
    case balancedAccessAroundValidationPublicationAndOpen
}

public enum ComparisonReportExecutorSnapshotContract: String, Equatable, Hashable, Sendable {
    case validateExactRootAndLinkedSnapshotsBeforeEffects
}

public enum ComparisonReportExecutorCancellationContract: String, Equatable, Hashable, Sendable {
    case cancelBeforePublicationOrFinishAndReportPublication
}

public enum ComparisonReportExecutorOpenContract: String, Equatable, Hashable, Sendable {
    case openPrimaryFileOnlyAfterAllOutputsPublishSuccessfully
}

/// Non-negotiable side-effect boundary. A conforming executor resolves every target under a pinned
/// parent without following links, rejects canonical filesystem aliasing between outputs, enforces
/// overwrite policy at atomic publication, holds declared security scope throughout access, replaces
/// clipboard contents only after complete generation, and opens the primary file only after every
/// output publishes successfully. Outputs publish strictly in plan order. Security-scoped access must
/// be stopped on every exit after it is started. Descriptor validation must decide volume-dependent
/// case equivalence and scope coverage. Paths and lexical identities in a plan are display and
/// preflight data, not capabilities.
public struct ComparisonReportExecutorContract: Equatable, Hashable, Sendable {
    public static let required = ComparisonReportExecutorContract()

    public let pathResolution = ComparisonReportExecutorPathResolutionContract.canonicalDescriptorRelativeNoFollow
    public let publication = ComparisonReportExecutorPublicationContract.publishExactPlannedBytesAtomicallyInPlanOrder
    public let securityScope = ComparisonReportExecutorSecurityScopeContract.balancedAccessAroundValidationPublicationAndOpen
    public let snapshot = ComparisonReportExecutorSnapshotContract.validateExactRootAndLinkedSnapshotsBeforeEffects
    public let cancellation = ComparisonReportExecutorCancellationContract.cancelBeforePublicationOrFinishAndReportPublication
    public let opening = ComparisonReportExecutorOpenContract.openPrimaryFileOnlyAfterAllOutputsPublishSuccessfully

    public init() {}
}

/// Plan-only workflow output. Construction performs no filesystem query or write, security-scope
/// access, pasteboard operation, process launch, or UI operation.
public struct ComparisonReportWorkflowPlan: Equatable, Sendable {
    public let snapshotFingerprint: ComparisonReportWorkflowSnapshotFingerprint
    public let scope: ComparisonReportScope
    public let format: ComparisonReportFormat
    public let outputs: [ComparisonReportPlannedOutput]
    public let openAfterGeneration: Bool
    public let estimate: ComparisonReportWorkflowEstimate
    public let limits: ComparisonReportWorkflowLimits
    public let executorContract: ComparisonReportExecutorContract

    public var primaryOutput: ComparisonReportPlannedOutput {
        outputs[0]
    }

    public var linkedOutputs: ArraySlice<ComparisonReportPlannedOutput> {
        outputs.dropFirst()
    }

    fileprivate init(
        snapshotFingerprint: ComparisonReportWorkflowSnapshotFingerprint,
        scope: ComparisonReportScope,
        format: ComparisonReportFormat,
        outputs: [ComparisonReportPlannedOutput],
        openAfterGeneration: Bool,
        estimate: ComparisonReportWorkflowEstimate,
        limits: ComparisonReportWorkflowLimits
    ) {
        precondition(!outputs.isEmpty)
        self.snapshotFingerprint = snapshotFingerprint
        self.scope = scope
        self.format = format
        self.outputs = outputs
        self.openAfterGeneration = openAfterGeneration
        self.estimate = estimate
        self.limits = limits
        executorContract = .required
    }

    public func validateCurrentSnapshot(
        _ snapshot: ComparisonReportWorkflowSnapshot,
        linkedReports: [ComparisonReportLinkedReport]
    ) throws {
        do {
            try ComparisonReportWorkflowPlanner.validate(
                snapshot,
                linkedReports: linkedReports,
                against: snapshotFingerprint,
                limits: limits
            )
        } catch is CancellationError {
            throw ComparisonReportWorkflowError.cancelled
        }
    }

    public func isCurrent(
        _ snapshot: ComparisonReportWorkflowSnapshot,
        linkedReports: [ComparisonReportLinkedReport]
    ) throws -> Bool {
        do {
            try validateCurrentSnapshot(snapshot, linkedReports: linkedReports)
            return true
        } catch ComparisonReportWorkflowError.snapshotIdentityChanged,
            ComparisonReportWorkflowError.snapshotGenerationChanged,
            ComparisonReportWorkflowError.snapshotContentsChanged
        {
            return false
        }
    }
}

public enum ComparisonReportFileURLIssue: String, Equatable, Hashable, Sendable {
    case notFileURL
    case relativeURL
    case remoteHost
    case credentialsOrPort
    case queryOrFragment
    case directoryURL
    case missingFileName
    case nullByte
    case pathTooLong
    case extensionMismatch
}

public enum ComparisonReportWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(name: String, value: Int)
    case snapshotIdentityChanged(
        expected: ComparisonReportWorkflowSnapshotIdentity,
        actual: ComparisonReportWorkflowSnapshotIdentity
    )
    case snapshotGenerationChanged(expected: UInt64, actual: UInt64)
    case snapshotContentsChanged
    case tooManyReports(maximum: Int)
    case tooManyRows(maximum: Int)
    case tooManyItems(maximum: Int)
    case inputTooLarge(maximumUTF8Bytes: Int)
    case outputTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumWorkUnits: Int)
    case invalidSelectedRowIndex(Int)
    case emptySelection
    case invalidFileURL(role: ComparisonReportPlannedOutputRole, issue: ComparisonReportFileURLIssue)
    case invalidSecurityScopeURL(ComparisonReportFileURLIssue)
    case invalidLinkedIdentifier(String)
    case invalidLinkedRelativePath(String)
    case linkedReportsRequireFileDestination
    case openAfterGenerationRequiresFileDestination
    case linkedDirectoryResultRequiresFolderSource(identifier: String)
    case linkedDirectoryResultNotInScope(identifier: String, id: DirectoryResult.ID)
    case duplicateLinkedIdentifier(String)
    case duplicateLinkedDirectoryResult(DirectoryResult.ID)
    case linkedReportSnapshotMismatch(identifier: String)
    case duplicateOutputIdentity(ComparisonReportCanonicalOutputIdentity)
    case overlappingOutputIdentities(
        ancestor: ComparisonReportCanonicalOutputIdentity,
        descendant: ComparisonReportCanonicalOutputIdentity
    )
    case totalPathsTooLarge(maximumUTF8Bytes: Int)
    case securityScopeDoesNotCoverOutput(ComparisonReportCanonicalOutputIdentity)
    case reportGeneration(role: ComparisonReportPlannedOutputRole, error: ComparisonReportError)
    case arithmeticOverflow

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Comparison report planning was cancelled."
        case .invalidLimit(let name, let value):
            "Invalid comparison report workflow limit \(name): \(value)."
        case .snapshotIdentityChanged:
            "Comparison report plan belongs to another snapshot."
        case .snapshotGenerationChanged(let expected, let actual):
            "Comparison report plan expects generation \(expected), not \(actual)."
        case .snapshotContentsChanged:
            "Comparison report snapshot changed without a generation change."
        case .tooManyReports(let maximum):
            "Comparison report workflow exceeds the \(maximum)-report limit."
        case .tooManyRows(let maximum):
            "Comparison report workflow exceeds the \(maximum)-row limit."
        case .tooManyItems(let maximum):
            "Comparison report workflow exceeds the \(maximum)-item limit."
        case .inputTooLarge(let maximum):
            "Comparison report workflow input exceeds \(maximum) UTF-8 bytes."
        case .outputTooLarge(let maximum):
            "Comparison report workflow output exceeds \(maximum) bytes."
        case .workLimitExceeded(let maximum):
            "Comparison report workflow exceeds the \(maximum)-unit work limit."
        case .invalidSelectedRowIndex(let index):
            "Comparison report selection contains invalid row index \(index)."
        case .emptySelection:
            "Comparison report selected scope contains no rows."
        case .invalidFileURL(let role, let issue):
            "Comparison report \(Self.description(of: role)) destination is invalid: \(issue.rawValue)."
        case .invalidSecurityScopeURL(let issue):
            "Comparison report security-scope resource is invalid: \(issue.rawValue)."
        case .invalidLinkedIdentifier(let identifier):
            "Comparison linked-report identifier is invalid: \(identifier)."
        case .invalidLinkedRelativePath(let path):
            "Comparison linked-report path is invalid: \(path)."
        case .linkedReportsRequireFileDestination:
            "Linked comparison reports require a file destination."
        case .openAfterGenerationRequiresFileDestination:
            "Open after generation requires a file destination."
        case .linkedDirectoryResultRequiresFolderSource(let identifier):
            "Linked report \(identifier) identifies a directory row for a non-folder source."
        case .linkedDirectoryResultNotInScope(let identifier, _):
            "Linked report \(identifier) identifies a directory row outside report scope."
        case .duplicateLinkedIdentifier(let identifier):
            "Comparison linked-report identifier is duplicated: \(identifier)."
        case .duplicateLinkedDirectoryResult:
            "A directory row has more than one linked comparison report."
        case .linkedReportSnapshotMismatch(let identifier):
            "Comparison linked report \(identifier) belongs to another root snapshot."
        case .duplicateOutputIdentity(let identity):
            "Comparison report outputs repeat canonical path \(identity.canonicalPath)."
        case .overlappingOutputIdentities(let ancestor, let descendant):
            "Comparison report output \(ancestor.canonicalPath) contains output \(descendant.canonicalPath)."
        case .totalPathsTooLarge(let maximum):
            "Comparison report output paths exceed \(maximum) combined UTF-8 bytes."
        case .securityScopeDoesNotCoverOutput(let identity):
            "Declared security scope does not cover comparison report output \(identity.canonicalPath)."
        case .reportGeneration(let role, let error):
            "Comparison report \(Self.description(of: role)) generation failed: \(error.localizedDescription)"
        case .arithmeticOverflow:
            "Comparison report workflow size calculation overflowed."
        }
    }

    private static func description(of role: ComparisonReportPlannedOutputRole) -> String {
        switch role {
        case .primary:
            "primary"
        case .linked(let identifier, _):
            "linked '\(identifier)'"
        }
    }
}

public enum ComparisonReportExecutionDisposition: String, Equatable, Hashable, Sendable {
    case created
    case replaced
    case copiedToClipboard
}

public struct ComparisonReportExecutionOutput: Equatable, Sendable {
    public let role: ComparisonReportPlannedOutputRole
    public let identity: ComparisonReportOutputIdentity
    public let disposition: ComparisonReportExecutionDisposition
    public let byteCount: Int

    fileprivate init(
        role: ComparisonReportPlannedOutputRole,
        identity: ComparisonReportOutputIdentity,
        disposition: ComparisonReportExecutionDisposition,
        byteCount: Int
    ) {
        self.role = role
        self.identity = identity
        self.disposition = disposition
        self.byteCount = byteCount
    }
}

public enum ComparisonReportOpenOutcome: Equatable, Hashable, Sendable {
    case notRequested
    case opened(ComparisonReportCanonicalOutputIdentity)
    /// Output publication succeeded, but the platform open request failed.
    case failed(ComparisonReportCanonicalOutputIdentity)
}

public struct ComparisonReportExecutionResult: Equatable, Sendable {
    public let snapshot: ComparisonReportWorkflowSnapshotReference
    public let outputs: [ComparisonReportExecutionOutput]
    public let openOutcome: ComparisonReportOpenOutcome

    fileprivate init(
        snapshot: ComparisonReportWorkflowSnapshotReference,
        outputs: [ComparisonReportExecutionOutput],
        openOutcome: ComparisonReportOpenOutcome
    ) {
        self.snapshot = snapshot
        self.outputs = outputs
        self.openOutcome = openOutcome
    }
}

public enum ComparisonReportExecutionFailureCode: String, Equatable, Hashable, Sendable {
    case staleSnapshot
    case invalidPlan
    case canonicalIdentityMismatch
    case outputCollision
    case outputAlreadyExists
    case securityScopeUnavailable
    case publicationFailed
    case clipboardUnavailable
    case contractUnsupported
}

public struct ComparisonReportExecutionFailure: Equatable, Sendable {
    public let code: ComparisonReportExecutionFailureCode
    public let outputIdentity: ComparisonReportOutputIdentity?
    /// Outputs proven complete before failure. Array order follows plan order.
    public let completedOutputs: [ComparisonReportExecutionOutput]

    fileprivate init(
        code: ComparisonReportExecutionFailureCode,
        outputIdentity: ComparisonReportOutputIdentity? = nil,
        completedOutputs: [ComparisonReportExecutionOutput] = []
    ) {
        self.code = code
        self.outputIdentity = outputIdentity
        self.completedOutputs = completedOutputs
    }
}

public struct ComparisonReportExecutionCancellation: Equatable, Sendable {
    /// Conforming executors normally cancel before publication. Nonempty output records identify
    /// publications that became durable before cancellation was observed.
    public let completedOutputs: [ComparisonReportExecutionOutput]

    fileprivate init(completedOutputs: [ComparisonReportExecutionOutput] = []) {
        self.completedOutputs = completedOutputs
    }
}

public struct ComparisonReportPublicationUncertainty: Equatable, Sendable {
    /// Identities whose publication or clipboard replacement could not be proven complete or absent.
    public let outputIdentities: [ComparisonReportOutputIdentity]
    public let completedOutputs: [ComparisonReportExecutionOutput]

    fileprivate init(
        outputIdentities: [ComparisonReportOutputIdentity],
        completedOutputs: [ComparisonReportExecutionOutput] = []
    ) {
        self.outputIdentities = outputIdentities
        self.completedOutputs = completedOutputs
    }
}

public enum ComparisonReportExecutionOutcome: Equatable, Sendable {
    case completed(ComparisonReportExecutionResult)
    case failed(ComparisonReportExecutionFailure)
    case cancelled(ComparisonReportExecutionCancellation)
    case publicationUncertain(ComparisonReportPublicationUncertainty)
}

/// Side-effect implementation supplied by an app/platform layer. It must enforce
/// `ComparisonReportExecutorContract.required` and call `plan.validateCurrentSnapshot` before any
/// effect. Cancellation or failure never implies rollback unless the outcome proves it.
public protocol ComparisonReportPlanExecutor: Sendable {
    func execute(
        _ plan: ComparisonReportWorkflowPlan,
        validating currentSnapshot: ComparisonReportWorkflowSnapshot,
        linkedReports: [ComparisonReportLinkedReport]
    ) async -> ComparisonReportExecutionOutcome
}

/// Validates and constructs executor outcomes so public states cannot contradict one plan.
public enum ComparisonReportExecutionOutcomeFactory: Sendable {
    public static func completed(
        plan: ComparisonReportWorkflowPlan,
        dispositions: [ComparisonReportExecutionDisposition],
        openOutcome: ComparisonReportOpenOutcome
    ) -> ComparisonReportExecutionOutcome {
        guard let outputs = completedOutputs(plan: plan, dispositions: dispositions),
            isValid(openOutcome: openOutcome, for: plan)
        else {
            return invalidPlanFailure()
        }
        return .completed(
            ComparisonReportExecutionResult(
                snapshot: plan.snapshotFingerprint.reference,
                outputs: outputs,
                openOutcome: openOutcome
            )
        )
    }

    public static func failed(
        plan: ComparisonReportWorkflowPlan,
        code: ComparisonReportExecutionFailureCode,
        outputIdentity: ComparisonReportOutputIdentity? = nil,
        completedDispositions: [ComparisonReportExecutionDisposition] = []
    ) -> ComparisonReportExecutionOutcome {
        guard completedDispositions.count < plan.outputs.count else {
            return invalidPlanFailure()
        }
        let identifiesPlannedOutput =
            outputIdentity.map { identity in
                plan.outputs.contains { $0.destination.outputIdentity == identity }
            } ?? true
        let completedIdentities = Set(
            plan.outputs.prefix(completedDispositions.count).map(\.destination.outputIdentity)
        )
        let failingDestination = outputIdentity.flatMap { identity in
            plan.outputs.first { $0.destination.outputIdentity == identity }?.destination
        }
        let nextOutputIdentity = plan.outputs[completedDispositions.count]
            .destination.outputIdentity
        let identifiesPermittedOutput =
            outputIdentity.map { identity in
                completedDispositions.isEmpty || identity == nextOutputIdentity
            } ?? true
        let globalFailureHasNoPublication = outputIdentity != nil || completedDispositions.isEmpty
        guard
            let outputs = completedPrefix(
                plan: plan,
                dispositions: completedDispositions
            ),
            identifiesPlannedOutput,
            outputIdentity.map({ !completedIdentities.contains($0) }) ?? true,
            identifiesPermittedOutput,
            globalFailureHasNoPublication,
            isValid(failureCode: code, for: failingDestination)
        else {
            return invalidPlanFailure()
        }
        return .failed(
            ComparisonReportExecutionFailure(
                code: code,
                outputIdentity: outputIdentity,
                completedOutputs: outputs
            )
        )
    }

    public static func cancelled(
        plan: ComparisonReportWorkflowPlan,
        completedDispositions: [ComparisonReportExecutionDisposition] = []
    ) -> ComparisonReportExecutionOutcome {
        let hasPendingAction =
            completedDispositions.count < plan.outputs.count
            || (completedDispositions.count == plan.outputs.count && plan.openAfterGeneration)
        guard hasPendingAction,
            let outputs = completedPrefix(
                plan: plan,
                dispositions: completedDispositions
            )
        else {
            return invalidPlanFailure()
        }
        return .cancelled(
            ComparisonReportExecutionCancellation(completedOutputs: outputs)
        )
    }

    public static func publicationUncertain(
        plan: ComparisonReportWorkflowPlan,
        uncertainOutputIndices: [Int],
        completedDispositions: [ComparisonReportExecutionDisposition] = []
    ) -> ComparisonReportExecutionOutcome {
        guard !uncertainOutputIndices.isEmpty,
            uncertainOutputIndices.count == 1,
            Set(uncertainOutputIndices).count == uncertainOutputIndices.count,
            uncertainOutputIndices.allSatisfy(plan.outputs.indices.contains),
            completedDispositions.count < plan.outputs.count,
            uncertainOutputIndices[0] == completedDispositions.count,
            let outputs = completedPrefix(
                plan: plan,
                dispositions: completedDispositions
            )
        else {
            return invalidPlanFailure()
        }
        return .publicationUncertain(
            ComparisonReportPublicationUncertainty(
                outputIdentities: uncertainOutputIndices.sorted().map {
                    plan.outputs[$0].destination.outputIdentity
                },
                completedOutputs: outputs
            )
        )
    }

    private static func completedOutputs(
        plan: ComparisonReportWorkflowPlan,
        dispositions: [ComparisonReportExecutionDisposition]
    ) -> [ComparisonReportExecutionOutput]? {
        guard dispositions.count == plan.outputs.count else { return nil }
        return completedPrefix(plan: plan, dispositions: dispositions)
    }

    private static func completedPrefix(
        plan: ComparisonReportWorkflowPlan,
        dispositions: [ComparisonReportExecutionDisposition]
    ) -> [ComparisonReportExecutionOutput]? {
        var outputs: [ComparisonReportExecutionOutput] = []
        outputs.reserveCapacity(dispositions.count)
        for (index, disposition) in dispositions.enumerated() {
            let planned = plan.outputs[index]
            guard isValid(disposition: disposition, for: planned.destination) else { return nil }
            outputs.append(
                ComparisonReportExecutionOutput(
                    role: planned.role,
                    identity: planned.destination.outputIdentity,
                    disposition: disposition,
                    byteCount: planned.outputByteCount
                )
            )
        }
        return outputs
    }

    private static func isValid(
        disposition: ComparisonReportExecutionDisposition,
        for destination: ComparisonReportPlannedDestination
    ) -> Bool {
        switch (destination, disposition) {
        case (.clipboard, .copiedToClipboard),
            (.file(_, _, .failIfExists, _), .created),
            (.file(_, _, .replaceExisting, _), .created),
            (.file(_, _, .replaceExisting, _), .replaced):
            true
        default:
            false
        }
    }

    private static func isValid(
        failureCode: ComparisonReportExecutionFailureCode,
        for destination: ComparisonReportPlannedDestination?
    ) -> Bool {
        switch (failureCode, destination) {
        case (.invalidPlan, nil), (.contractUnsupported, nil), (.staleSnapshot, nil):
            true
        case (.canonicalIdentityMismatch, .file),
            (.outputCollision, .file),
            (.outputAlreadyExists, .file(_, _, .failIfExists, _)),
            (.securityScopeUnavailable, .file(_, _, _, .securityScoped)),
            (.publicationFailed, .file),
            (.clipboardUnavailable, .clipboard):
            true
        default:
            false
        }
    }

    private static func isValid(
        openOutcome: ComparisonReportOpenOutcome,
        for plan: ComparisonReportWorkflowPlan
    ) -> Bool {
        let primaryIdentity: ComparisonReportCanonicalOutputIdentity?
        if case .file(_, let identity, _, _) = plan.primaryOutput.destination {
            primaryIdentity = identity
        } else {
            primaryIdentity = nil
        }
        return switch (plan.openAfterGeneration, openOutcome, primaryIdentity) {
        case (false, .notRequested, _):
            true
        case (true, .opened(let identity), let primary?),
            (true, .failed(let identity), let primary?):
            identity == primary
        default:
            false
        }
    }

    private static func invalidPlanFailure() -> ComparisonReportExecutionOutcome {
        .failed(ComparisonReportExecutionFailure(code: .invalidPlan))
    }
}

public enum ComparisonReportWorkflowPlanner: Sendable {
    public static func plan(
        _ request: ComparisonReportWorkflowRequest,
        expecting expectedSnapshot: ComparisonReportWorkflowSnapshotReference? = nil
    ) throws -> ComparisonReportWorkflowPlan {
        do {
            return try makePlan(request, expecting: expectedSnapshot)
        } catch is CancellationError {
            throw ComparisonReportWorkflowError.cancelled
        }
    }

    fileprivate static func validate(
        _ snapshot: ComparisonReportWorkflowSnapshot,
        linkedReports: [ComparisonReportLinkedReport],
        against fingerprint: ComparisonReportWorkflowSnapshotFingerprint,
        limits: ComparisonReportWorkflowLimits
    ) throws {
        try Task.checkCancellation()
        guard snapshot.identity == fingerprint.reference.identity else {
            throw ComparisonReportWorkflowError.snapshotIdentityChanged(
                expected: fingerprint.reference.identity,
                actual: snapshot.identity
            )
        }
        guard snapshot.generation == fingerprint.reference.generation else {
            throw ComparisonReportWorkflowError.snapshotGenerationChanged(
                expected: fingerprint.reference.generation,
                actual: snapshot.generation
            )
        }

        guard linkedReports.count == fingerprint.linkedReports.count else {
            throw ComparisonReportWorkflowError.snapshotContentsChanged
        }
        var budget = ComparisonReportWorkflowBudget(limits: limits)
        guard try exactlyEqual(fingerprint.source, snapshot.source, budget: &budget) else {
            throw ComparisonReportWorkflowError.snapshotContentsChanged
        }
        let orderedLinks = try validatedLinks(
            linkedReports,
            snapshot: ComparisonReportWorkflowSnapshotReference(snapshot),
            source: snapshot.source,
            scope: fingerprint.scope,
            limits: limits,
            budget: &budget
        )
        guard
            try exactlyEqual(
                fingerprint.linkedReports,
                orderedLinks,
                budget: &budget
            )
        else {
            throw ComparisonReportWorkflowError.snapshotContentsChanged
        }
    }

    private static func makePlan(
        _ request: ComparisonReportWorkflowRequest,
        expecting expectedSnapshot: ComparisonReportWorkflowSnapshotReference?
    ) throws -> ComparisonReportWorkflowPlan {
        try Task.checkCancellation()
        try validate(request.limits)
        if let expectedSnapshot {
            guard expectedSnapshot.identity == request.snapshot.identity else {
                throw ComparisonReportWorkflowError.snapshotIdentityChanged(
                    expected: expectedSnapshot.identity,
                    actual: request.snapshot.identity
                )
            }
            guard expectedSnapshot.generation == request.snapshot.generation else {
                throw ComparisonReportWorkflowError.snapshotGenerationChanged(
                    expected: expectedSnapshot.generation,
                    actual: request.snapshot.generation
                )
            }
        }

        let reportCount = try checkedAdd(request.linkedReports.count, 1)
        guard reportCount <= request.limits.maximumReportCount else {
            throw ComparisonReportWorkflowError.tooManyReports(
                maximum: request.limits.maximumReportCount
            )
        }
        if case .clipboard = request.destination {
            guard request.linkedReports.isEmpty else {
                throw ComparisonReportWorkflowError.linkedReportsRequireFileDestination
            }
            guard !request.openAfterGeneration else {
                throw ComparisonReportWorkflowError.openAfterGenerationRequiresFileDestination
            }
        }

        var budget = ComparisonReportWorkflowBudget(limits: request.limits)
        let sourceMetrics = try measure(
            request.snapshot.source,
            limits: request.limits,
            budget: &budget
        )
        let orderedLinks = try validatedLinks(
            request.linkedReports,
            snapshot: ComparisonReportWorkflowSnapshotReference(request.snapshot),
            source: request.snapshot.source,
            scope: request.scope,
            limits: request.limits,
            budget: &budget
        )
        let destinations = try plannedDestinations(
            destination: request.destination,
            links: orderedLinks,
            format: request.format,
            limits: request.limits,
            budget: &budget
        )
        let primaryReport = try scopedReport(
            from: request.snapshot.source,
            scope: request.scope,
            links: orderedLinks,
            limits: request.limits,
            budget: &budget
        )

        let rolesAndReports: [(ComparisonReportPlannedOutputRole, ComparisonReport)] =
            [
                (.primary, primaryReport)
            ]
            + orderedLinks.map {
                (
                    .linked(identifier: $0.identifier, directoryResultID: $0.directoryResultID),
                    $0.report
                )
            }

        var outputs: [ComparisonReportPlannedOutput] = []
        outputs.reserveCapacity(reportCount)
        var totalRows = 0
        var totalItems = sourceMetrics.itemCount
        var totalInputBytes = sourceMetrics.inputUTF8ByteCount
        var totalOutputBytes = 0

        for (index, roleAndReport) in rolesAndReports.enumerated() {
            try Task.checkCancellation()
            let role = roleAndReport.0
            let report = roleAndReport.1
            let beforeWork = budget.consumed
            do {
                try validateStructure(report, budget: &budget)
            } catch let error as ComparisonReportError {
                throw ComparisonReportWorkflowError.reportGeneration(role: role, error: error)
            }
            let metrics = try measure(report, limits: request.limits, budget: &budget)
            totalRows = try boundedAdd(
                totalRows,
                metrics.rowCount,
                maximum: request.limits.maximumRowCount,
                error: .tooManyRows(maximum: request.limits.maximumRowCount)
            )
            if index > 0 {
                totalItems = try boundedAdd(
                    totalItems,
                    metrics.itemCount,
                    maximum: request.limits.maximumItemCount,
                    error: .tooManyItems(maximum: request.limits.maximumItemCount)
                )
                totalInputBytes = try boundedAdd(
                    totalInputBytes,
                    metrics.inputUTF8ByteCount,
                    maximum: request.limits.maximumInputUTF8Bytes,
                    error: .inputTooLarge(maximumUTF8Bytes: request.limits.maximumInputUTF8Bytes)
                )
            }

            let remainingOutputBytes = request.limits.maximumOutputBytes - totalOutputBytes
            guard remainingOutputBytes > 0 else {
                throw ComparisonReportWorkflowError.outputTooLarge(
                    maximumBytes: request.limits.maximumOutputBytes
                )
            }
            let reportOutputLimit = min(
                request.limits.maximumOutputBytesPerReport,
                remainingOutputBytes
            )
            let output: ComparisonReportOutput
            do {
                let beforeGenerationWork = budget.consumed
                try reserveGenerationWork(
                    for: report,
                    metrics: metrics,
                    format: request.format,
                    maximumOutputBytes: reportOutputLimit,
                    budget: &budget
                )
                let synchronousGenerationWork = budget.consumed - beforeGenerationWork
                guard
                    synchronousGenerationWork
                        <= ComparisonReportWorkflowLimits
                        .hardMaximumSynchronousGenerationWorkUnits
                else {
                    throw ComparisonReportWorkflowError.workLimitExceeded(
                        maximumWorkUnits: ComparisonReportWorkflowLimits
                            .hardMaximumSynchronousGenerationWorkUnits
                    )
                }
                try Task.checkCancellation()
                // ComparisonReport owns format bytes; this call has no internal cancellation points.
                output = try report.generate(
                    format: request.format,
                    maximumOutputBytes: reportOutputLimit
                )
            } catch let error as ComparisonReportError {
                if reportOutputLimit < request.limits.maximumOutputBytesPerReport,
                    case .outputTooLarge = error
                {
                    throw ComparisonReportWorkflowError.outputTooLarge(
                        maximumBytes: request.limits.maximumOutputBytes
                    )
                }
                throw ComparisonReportWorkflowError.reportGeneration(role: role, error: error)
            }
            try Task.checkCancellation()
            totalOutputBytes = try boundedAdd(
                totalOutputBytes,
                output.data.count,
                maximum: request.limits.maximumOutputBytes,
                error: .outputTooLarge(maximumBytes: request.limits.maximumOutputBytes)
            )
            let outputWork = budget.consumed - beforeWork
            outputs.append(
                ComparisonReportPlannedOutput(
                    role: role,
                    destination: destinations[index],
                    output: output,
                    inputItemCount: metrics.itemCount,
                    inputUTF8ByteCount: metrics.inputUTF8ByteCount,
                    estimatedWorkUnits: outputWork
                )
            )
        }

        let fingerprint = ComparisonReportWorkflowSnapshotFingerprint(
            request: request,
            linkedReports: orderedLinks,
            sourceItemCount: sourceMetrics.itemCount,
            sourceUTF8ByteCount: sourceMetrics.inputUTF8ByteCount
        )
        return ComparisonReportWorkflowPlan(
            snapshotFingerprint: fingerprint,
            scope: request.scope,
            format: request.format,
            outputs: outputs,
            openAfterGeneration: request.openAfterGeneration,
            estimate: ComparisonReportWorkflowEstimate(
                reportCount: outputs.count,
                rowCount: totalRows,
                inputItemCount: totalItems,
                inputUTF8ByteCount: totalInputBytes,
                estimatedOutputByteCount: totalOutputBytes,
                estimatedWorkUnits: budget.consumed
            ),
            limits: request.limits
        )
    }

    private static func validate(_ limits: ComparisonReportWorkflowLimits) throws {
        try requireLimit(
            limits.maximumReportCount,
            name: "maximumReportCount",
            range: 1...ComparisonReportWorkflowLimits.hardMaximumReportCount
        )
        try requireLimit(
            limits.maximumRowCount,
            name: "maximumRowCount",
            range: 1...ComparisonReportWorkflowLimits.hardMaximumRowCount
        )
        try requireLimit(
            limits.maximumItemCount,
            name: "maximumItemCount",
            range: 1...ComparisonReportWorkflowLimits.hardMaximumItemCount
        )
        try requireLimit(
            limits.maximumInputUTF8Bytes,
            name: "maximumInputUTF8Bytes",
            range: 1...ComparisonReportWorkflowLimits.hardMaximumInputUTF8Bytes
        )
        try requireLimit(
            limits.maximumOutputBytes,
            name: "maximumOutputBytes",
            range: 1...ComparisonReportWorkflowLimits.hardMaximumOutputBytes
        )
        try requireLimit(
            limits.maximumOutputBytesPerReport,
            name: "maximumOutputBytesPerReport",
            range: 1...ComparisonReportWorkflowLimits.hardMaximumOutputBytesPerReport
        )
        guard limits.maximumOutputBytesPerReport <= limits.maximumOutputBytes else {
            throw ComparisonReportWorkflowError.invalidLimit(
                name: "maximumOutputBytesPerReport",
                value: limits.maximumOutputBytesPerReport
            )
        }
        try requireLimit(
            limits.maximumWorkUnits,
            name: "maximumWorkUnits",
            range: 1...ComparisonReportWorkflowLimits.hardMaximumWorkUnits
        )
        try requireLimit(
            limits.maximumPathUTF8Bytes,
            name: "maximumPathUTF8Bytes",
            range: 1...ComparisonReportWorkflowLimits.hardMaximumPathUTF8Bytes
        )
        try requireLimit(
            limits.maximumTotalPathUTF8Bytes,
            name: "maximumTotalPathUTF8Bytes",
            range: limits
                .maximumPathUTF8Bytes...ComparisonReportWorkflowLimits
                .hardMaximumTotalPathUTF8Bytes
        )
        try requireLimit(
            limits.maximumIdentifierUTF8Bytes,
            name: "maximumIdentifierUTF8Bytes",
            range: 1...ComparisonReportWorkflowLimits.hardMaximumIdentifierUTF8Bytes
        )
        try requireLimit(
            limits.cancellationCheckInterval,
            name: "cancellationCheckInterval",
            range: 1...1_048_576
        )
    }

    private static func requireLimit(
        _ value: Int,
        name: String,
        range: ClosedRange<Int>
    ) throws {
        guard range.contains(value) else {
            throw ComparisonReportWorkflowError.invalidLimit(name: name, value: value)
        }
    }

    private static func validatedLinks(
        _ links: [ComparisonReportLinkedReport],
        snapshot: ComparisonReportWorkflowSnapshotReference,
        source: ComparisonReportWorkflowSource,
        scope: ComparisonReportScope,
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> [ComparisonReportLinkedReport] {
        var identifiers: Set<String> = []
        identifiers.reserveCapacity(links.count)
        var requestedDirectoryIDs: Set<DirectoryResult.ID> = []
        requestedDirectoryIDs.reserveCapacity(links.count)
        for link in links {
            try budget.consume(1)
            if let id = link.directoryResultID {
                try consumeDirectoryResultID(id, limits: limits, budget: &budget)
                requestedDirectoryIDs.insert(id)
            }
        }
        var linkedDirectoryResults: Set<DirectoryResult.ID> = []
        linkedDirectoryResults.reserveCapacity(requestedDirectoryIDs.count)
        var scopedDirectoryIDs: Set<DirectoryResult.ID> = []
        scopedDirectoryIDs.reserveCapacity(requestedDirectoryIDs.count)
        if !requestedDirectoryIDs.isEmpty, case .folder(let snapshot) = source {
            for result in snapshot.results.results {
                try budget.consume(1)
                try consumeDirectoryResultID(result.id, limits: limits, budget: &budget)
                if requestedDirectoryIDs.contains(result.id),
                    scope == .all || snapshot.results.selectedIDs.contains(result.id)
                {
                    scopedDirectoryIDs.insert(result.id)
                }
            }
        }

        for link in links {
            try budget.consume(1)
            guard link.snapshot == snapshot else {
                throw ComparisonReportWorkflowError.linkedReportSnapshotMismatch(
                    identifier: link.identifier
                )
            }
            let identifierByteCount = try boundedUTF8ByteCount(
                link.identifier,
                maximum: limits.maximumIdentifierUTF8Bytes,
                budget: &budget
            )
            try budget.consume(try checkedProduct(identifierByteCount, 2))
            guard identifierByteCount > 0,
                identifierByteCount <= limits.maximumIdentifierUTF8Bytes,
                !link.identifier.utf8.contains(0),
                !link.identifier.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else {
                throw ComparisonReportWorkflowError.invalidLinkedIdentifier(link.identifier)
            }
            guard identifiers.insert(link.identifier).inserted else {
                throw ComparisonReportWorkflowError.duplicateLinkedIdentifier(link.identifier)
            }
            try validateRelativeOutputPath(link.relativeOutputPath, limits: limits, budget: &budget)

            if let id = link.directoryResultID {
                guard case .folder = source else {
                    throw ComparisonReportWorkflowError.linkedDirectoryResultRequiresFolderSource(
                        identifier: link.identifier
                    )
                }
                guard scopedDirectoryIDs.contains(id) else {
                    throw ComparisonReportWorkflowError.linkedDirectoryResultNotInScope(
                        identifier: link.identifier,
                        id: id
                    )
                }
                guard linkedDirectoryResults.insert(id).inserted else {
                    throw ComparisonReportWorkflowError.duplicateLinkedDirectoryResult(id)
                }
            }
        }

        return try cancellableSorted(links, budget: &budget) { left, right, sortBudget in
            let pathOrder = try compareUTF8(
                left.relativeOutputPath,
                right.relativeOutputPath,
                budget: &sortBudget
            )
            if pathOrder != 0 { return pathOrder < 0 }
            return try compareUTF8(left.identifier, right.identifier, budget: &sortBudget) < 0
        }
    }

    private static func validateRelativeOutputPath(
        _ path: String,
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        let byteCount = try boundedUTF8ByteCount(
            path,
            maximum: limits.maximumPathUTF8Bytes,
            budget: &budget
        )
        guard byteCount > 0, byteCount <= limits.maximumPathUTF8Bytes else {
            throw ComparisonReportWorkflowError.invalidLinkedRelativePath(path)
        }
        try budget.consume(try checkedProduct(byteCount, 2))
        guard !path.utf8.contains(0), !path.hasPrefix("/") else {
            throw ComparisonReportWorkflowError.invalidLinkedRelativePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ComparisonReportWorkflowError.invalidLinkedRelativePath(path)
        }
    }

    private static func plannedDestinations(
        destination: ComparisonReportOutputDestination,
        links: [ComparisonReportLinkedReport],
        format: ComparisonReportFormat,
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> [ComparisonReportPlannedDestination] {
        switch destination {
        case .clipboard:
            return [.clipboard]
        case .file(let file):
            let primary = try canonicalOutputIdentity(
                for: file.url,
                role: .primary,
                format: format,
                limits: limits,
                budget: &budget
            )
            let parentURL = primary.fileURL.deletingLastPathComponent()
            var planned: [ComparisonReportPlannedDestination] = [
                .file(
                    requestedURL: file.url,
                    identity: primary,
                    overwritePolicy: file.overwritePolicy,
                    sandboxAccess: file.sandboxAccess
                )
            ]
            planned.reserveCapacity(links.count + 1)
            var identities = [primary]
            identities.reserveCapacity(links.count + 1)
            var totalPathBytes = primary.canonicalPathUTF8Bytes.count
            let parentPath = parentURL.path

            for link in links {
                try Task.checkCancellation()
                let separator = parentPath == "/" ? "" : "/"
                let linkedPath = parentPath + separator + link.relativeOutputPath
                let linkedPathByteCount = try boundedUTF8ByteCount(
                    linkedPath,
                    maximum: limits.maximumPathUTF8Bytes,
                    budget: &budget
                )
                guard linkedPathByteCount <= limits.maximumPathUTF8Bytes else {
                    throw ComparisonReportWorkflowError.invalidFileURL(
                        role: .linked(
                            identifier: link.identifier,
                            directoryResultID: link.directoryResultID
                        ),
                        issue: .pathTooLong
                    )
                }
                try budget.consume(linkedPathByteCount)
                let linkedURL = URL(fileURLWithPath: linkedPath, isDirectory: false)
                let role = ComparisonReportPlannedOutputRole.linked(
                    identifier: link.identifier,
                    directoryResultID: link.directoryResultID
                )
                let identity = try canonicalOutputIdentity(
                    for: linkedURL,
                    role: role,
                    format: format,
                    limits: limits,
                    budget: &budget
                )
                for existing in identities {
                    switch try outputIdentityRelationship(
                        existing,
                        identity,
                        budget: &budget
                    ) {
                    case .distinct:
                        break
                    case .equal:
                        throw ComparisonReportWorkflowError.duplicateOutputIdentity(identity)
                    case .ancestor:
                        throw ComparisonReportWorkflowError.overlappingOutputIdentities(
                            ancestor: existing,
                            descendant: identity
                        )
                    case .descendant:
                        throw ComparisonReportWorkflowError.overlappingOutputIdentities(
                            ancestor: identity,
                            descendant: existing
                        )
                    }
                }
                identities.append(identity)
                totalPathBytes = try boundedAdd(
                    totalPathBytes,
                    identity.canonicalPathUTF8Bytes.count,
                    maximum: limits.maximumTotalPathUTF8Bytes,
                    error: .totalPathsTooLarge(
                        maximumUTF8Bytes: limits.maximumTotalPathUTF8Bytes
                    )
                )
                planned.append(
                    .file(
                        requestedURL: linkedURL,
                        identity: identity,
                        overwritePolicy: file.overwritePolicy,
                        sandboxAccess: file.sandboxAccess
                    )
                )
            }
            try validateSandboxCoverage(
                file.sandboxAccess,
                destinations: planned,
                limits: limits,
                budget: &budget
            )
            return planned
        }
    }

    private static func canonicalOutputIdentity(
        for url: URL,
        role: ComparisonReportPlannedOutputRole,
        format: ComparisonReportFormat,
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> ComparisonReportCanonicalOutputIdentity {
        let maximumURLByteCount = try checkedAdd(
            try checkedProduct(limits.maximumPathUTF8Bytes, 3),
            64
        )
        let requestedURLByteCount = try boundedUTF8ByteCount(
            url.absoluteString,
            maximum: maximumURLByteCount,
            budget: &budget
        )
        guard requestedURLByteCount <= maximumURLByteCount else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .pathTooLong)
        }
        guard url.isFileURL else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .notFileURL)
        }
        guard url.baseURL == nil else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .relativeURL)
        }
        let requestedPath = url.path
        let requestedPathByteCount = try boundedUTF8ByteCount(
            requestedPath,
            maximum: limits.maximumPathUTF8Bytes,
            budget: &budget
        )
        guard requestedPathByteCount <= limits.maximumPathUTF8Bytes else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .pathTooLong)
        }
        try budget.consume(try checkedProduct(requestedPathByteCount, 4))
        guard requestedPath.hasPrefix("/") else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .relativeURL)
        }
        guard isLocalFileHost(url.host) else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .remoteHost)
        }
        guard url.user == nil, url.password == nil, url.port == nil else {
            throw ComparisonReportWorkflowError.invalidFileURL(
                role: role,
                issue: .credentialsOrPort
            )
        }
        guard url.query == nil, url.fragment == nil else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .queryOrFragment)
        }
        guard !url.hasDirectoryPath else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .directoryURL)
        }
        guard !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .missingFileName)
        }
        guard !requestedPath.contains("\0") else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .nullByte)
        }

        let path = url.standardizedFileURL.path
        let pathByteCount = try boundedUTF8ByteCount(
            path,
            maximum: limits.maximumPathUTF8Bytes,
            budget: &budget
        )
        guard pathByteCount <= limits.maximumPathUTF8Bytes else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .pathTooLong)
        }
        try budget.consume(try checkedProduct(pathByteCount, 3))
        let pathBytes = Array(path.utf8)
        guard URL(fileURLWithPath: path, isDirectory: false).pathExtension == format.fileExtension
        else {
            throw ComparisonReportWorkflowError.invalidFileURL(role: role, issue: .extensionMismatch)
        }
        return ComparisonReportCanonicalOutputIdentity(
            fileURL: URL(fileURLWithPath: path, isDirectory: false),
            canonicalPath: path,
            canonicalPathUTF8Bytes: pathBytes
        )
    }

    private static func validateSandboxCoverage(
        _ access: ComparisonReportSandboxAccess,
        destinations: [ComparisonReportPlannedDestination],
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        guard case .securityScoped(let resourceURL, let coverage) = access else { return }
        let scopeIdentity = try canonicalOutputIdentityWithoutExtension(
            for: resourceURL,
            limits: limits,
            budget: &budget
        )
        for destination in destinations {
            guard case .file(_, let identity, _, _) = destination else { continue }
            let isCovered: Bool
            switch coverage {
            case .exactFile:
                let relationship = try outputIdentityRelationship(
                    scopeIdentity,
                    identity,
                    budget: &budget
                )
                if relationship == .equal {
                    isCovered = true
                } else if relationship == .distinct {
                    isCovered =
                        try caseInsensitiveOutputIdentityRelationship(
                            scopeIdentity,
                            identity,
                            budget: &budget
                        ) == .equal
                } else {
                    isCovered = false
                }
            case .directoryTree:
                let relationship = try outputIdentityRelationship(
                    scopeIdentity,
                    identity,
                    budget: &budget
                )
                if relationship == .equal || relationship == .ancestor {
                    isCovered = true
                } else if relationship == .distinct {
                    let deferredRelationship = try caseInsensitiveOutputIdentityRelationship(
                        scopeIdentity,
                        identity,
                        budget: &budget
                    )
                    isCovered =
                        deferredRelationship == .equal
                        || deferredRelationship == .ancestor
                } else {
                    isCovered = false
                }
            }
            guard isCovered else {
                throw ComparisonReportWorkflowError.securityScopeDoesNotCoverOutput(identity)
            }
        }
    }

    private static func canonicalOutputIdentityWithoutExtension(
        for url: URL,
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> ComparisonReportCanonicalOutputIdentity {
        let maximumURLByteCount = try checkedAdd(
            try checkedProduct(limits.maximumPathUTF8Bytes, 3),
            64
        )
        let requestedURLByteCount = try boundedUTF8ByteCount(
            url.absoluteString,
            maximum: maximumURLByteCount,
            budget: &budget
        )
        guard requestedURLByteCount <= maximumURLByteCount else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.pathTooLong)
        }
        guard url.isFileURL else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.notFileURL)
        }
        guard url.baseURL == nil else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.relativeURL)
        }
        let requestedPath = url.path
        let requestedPathByteCount = try boundedUTF8ByteCount(
            requestedPath,
            maximum: limits.maximumPathUTF8Bytes,
            budget: &budget
        )
        guard requestedPathByteCount <= limits.maximumPathUTF8Bytes else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.pathTooLong)
        }
        try budget.consume(try checkedProduct(requestedPathByteCount, 4))
        guard requestedPath.hasPrefix("/") else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.relativeURL)
        }
        guard isLocalFileHost(url.host) else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.remoteHost)
        }
        guard url.user == nil, url.password == nil, url.port == nil else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.credentialsOrPort)
        }
        guard url.query == nil, url.fragment == nil else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.queryOrFragment)
        }
        guard !requestedPath.contains("\0") else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.nullByte)
        }
        let path = url.standardizedFileURL.path
        let byteCount = try boundedUTF8ByteCount(
            path,
            maximum: limits.maximumPathUTF8Bytes,
            budget: &budget
        )
        guard byteCount <= limits.maximumPathUTF8Bytes else {
            throw ComparisonReportWorkflowError.invalidSecurityScopeURL(.pathTooLong)
        }
        try budget.consume(try checkedProduct(byteCount, 2))
        let bytes = Array(path.utf8)
        return ComparisonReportCanonicalOutputIdentity(
            fileURL: URL(fileURLWithPath: path, isDirectory: url.hasDirectoryPath),
            canonicalPath: path,
            canonicalPathUTF8Bytes: bytes
        )
    }

    private static func isLocalFileHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return true }
        let expectedHost = Array("localhost".utf8)
        guard host.utf8.count == expectedHost.count else { return false }
        for (actual, expected) in zip(host.utf8, expectedHost) {
            let folded =
                actual >= UInt8(ascii: "A") && actual <= UInt8(ascii: "Z")
                ? actual + (UInt8(ascii: "a") - UInt8(ascii: "A"))
                : actual
            guard folded == expected else { return false }
        }
        return true
    }

    private static func scopedReport(
        from source: ComparisonReportWorkflowSource,
        scope: ComparisonReportScope,
        links: [ComparisonReportLinkedReport],
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> ComparisonReport {
        switch source {
        case .file(let snapshot):
            guard links.allSatisfy({ $0.directoryResultID == nil }) else {
                let link = links.first { $0.directoryResultID != nil }!
                throw ComparisonReportWorkflowError.linkedDirectoryResultRequiresFolderSource(
                    identifier: link.identifier
                )
            }
            guard scope == .selected else { return snapshot.report }
            guard !snapshot.selectedRowIndices.isEmpty else {
                throw ComparisonReportWorkflowError.emptySelection
            }
            var rows: [ComparisonReportRow] = []
            rows.reserveCapacity(snapshot.selectedRowIndices.count)
            for index in snapshot.report.rows.indices {
                try budget.consume(1)
                if snapshot.selectedRowIndices.contains(index) {
                    rows.append(snapshot.report.rows[index])
                }
            }
            guard rows.count == snapshot.selectedRowIndices.count else {
                throw ComparisonReportWorkflowError.invalidSelectedRowIndex(
                    try minimumInvalidIndex(
                        in: snapshot.selectedRowIndices,
                        validIndices: snapshot.report.rows.indices,
                        budget: &budget
                    )
                )
            }
            return ComparisonReport(
                title: snapshot.report.title,
                columns: snapshot.report.columns,
                rows: rows,
                summary: rows.count == snapshot.report.rows.count ? snapshot.report.summary : nil
            )
        case .folder(let snapshot):
            let results = snapshot.results
            let includesLinkedPath = links.contains { $0.directoryResultID != nil }
            var scopedResultCount = 0
            var statusMask: UInt8 = 0
            for result in results.results {
                try budget.consume(1)
                guard scope == .all || results.selectedIDs.contains(result.id) else { continue }
                scopedResultCount += 1
                statusMask |= statusBit(result.status)
            }
            guard scope == .all || scopedResultCount > 0 else {
                throw ComparisonReportWorkflowError.emptySelection
            }
            guard scopedResultCount <= limits.maximumRowCount else {
                throw ComparisonReportWorkflowError.tooManyRows(maximum: limits.maximumRowCount)
            }
            let columnCount = includesLinkedPath ? 8 : 7
            let rowValueCount = try checkedProduct(
                scopedResultCount,
                try checkedAdd(columnCount, 1)
            )
            let summaryValueCount = try checkedProduct(
                try checkedAdd(3, statusMask.nonzeroBitCount),
                2
            )
            let derivedValueCount = try checkedAdd(
                try checkedAdd(1, columnCount),
                try checkedAdd(rowValueCount, summaryValueCount)
            )
            guard derivedValueCount <= limits.maximumItemCount else {
                throw ComparisonReportWorkflowError.tooManyItems(maximum: limits.maximumItemCount)
            }
            try budget.consume(derivedValueCount)

            var linksByResultID: [DirectoryResult.ID: String] = [:]
            linksByResultID.reserveCapacity(links.count)
            for link in links {
                try budget.consume(1)
                if let id = link.directoryResultID {
                    linksByResultID[id] = link.relativeOutputPath
                }
            }
            var columns = [
                "Path", "Left Path", "Right Path", "Status", "Kind", "Left Bytes", "Right Bytes"
            ]
            if includesLinkedPath { columns.append("Linked Report") }

            var rows: [ComparisonReportRow] = []
            rows.reserveCapacity(scopedResultCount)
            var statusCounts: [DirectoryComparisonStatus: Int] = [:]
            for result in results.results {
                try budget.consume(1)
                guard scope == .all || results.selectedIDs.contains(result.id) else { continue }
                statusCounts[result.status, default: 0] += 1
                var values = [
                    result.relativePath,
                    result.left?.relativePath ?? "",
                    result.right?.relativePath ?? "",
                    description(of: result.status),
                    description(of: result.kind),
                    result.left?.byteCount.map(String.init) ?? "",
                    result.right?.byteCount.map(String.init) ?? ""
                ]
                if includesLinkedPath {
                    values.append(linksByResultID[result.id] ?? "")
                }
                rows.append(ComparisonReportRow(values: values, sortKey: result.relativePath))
            }

            var summaryItems = [
                ComparisonReportSummaryItem(label: "Left Root", value: results.leftRoot.path),
                ComparisonReportSummaryItem(label: "Right Root", value: results.rightRoot.path),
                ComparisonReportSummaryItem(label: "Items", value: String(scopedResultCount))
            ]
            for status in DirectoryComparisonStatus.allCases {
                if let count = statusCounts[status] {
                    summaryItems.append(
                        ComparisonReportSummaryItem(
                            label: description(of: status),
                            value: String(count)
                        )
                    )
                }
            }
            return ComparisonReport(
                title: "Folder Comparison Report",
                columns: columns,
                rows: rows,
                summary: ComparisonReportSummary(items: summaryItems)
            )
        }
    }

    private static func statusBit(_ status: DirectoryComparisonStatus) -> UInt8 {
        switch status {
        case .pending: 1 << 0
        case .identical: 1 << 1
        case .different: 1 << 2
        case .leftOnly: 1 << 3
        case .rightOnly: 1 << 4
        case .typeMismatch: 1 << 5
        case .skipped: 1 << 6
        case .error: 1 << 7
        }
    }

    private static func description(of status: DirectoryComparisonStatus) -> String {
        switch status {
        case .pending: "Pending"
        case .identical: "Identical"
        case .different: "Different"
        case .leftOnly: "Left Only"
        case .rightOnly: "Right Only"
        case .typeMismatch: "Type Mismatch"
        case .skipped: "Skipped"
        case .error: "Error"
        }
    }

    private static func description(of kind: DirectoryEntryKind?) -> String {
        switch kind {
        case .file: "File"
        case .directory: "Directory"
        case .symbolicLink: "Symbolic Link"
        case .other: "Other"
        case nil: "Mixed"
        }
    }

    private struct Metrics {
        var rowCount = 0
        var itemCount = 0
        var inputUTF8ByteCount = 0
        var maximumRowComparisonWork = 0
        var summaryItemCount = 0
        var maximumSummaryComparisonWork = 0
    }

    private static func measure(
        _ source: ComparisonReportWorkflowSource,
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Metrics {
        switch source {
        case .file(let snapshot):
            var metrics = try measure(snapshot.report, limits: limits, budget: &budget)
            guard snapshot.selectedRowIndices.count <= limits.maximumItemCount else {
                throw ComparisonReportWorkflowError.tooManyItems(
                    maximum: limits.maximumItemCount
                )
            }
            guard snapshot.selectedRowIndices.count <= snapshot.report.rows.count else {
                throw ComparisonReportWorkflowError.invalidSelectedRowIndex(
                    try minimumInvalidIndex(
                        in: snapshot.selectedRowIndices,
                        validIndices: snapshot.report.rows.indices,
                        budget: &budget
                    )
                )
            }
            var matchedSelectionCount = 0
            for index in snapshot.report.rows.indices {
                try budget.consume(1)
                if snapshot.selectedRowIndices.contains(index) {
                    matchedSelectionCount += 1
                    metrics.itemCount = try boundedAdd(
                        metrics.itemCount,
                        1,
                        maximum: limits.maximumItemCount,
                        error: .tooManyItems(maximum: limits.maximumItemCount)
                    )
                }
            }
            guard matchedSelectionCount == snapshot.selectedRowIndices.count else {
                throw ComparisonReportWorkflowError.invalidSelectedRowIndex(
                    try minimumInvalidIndex(
                        in: snapshot.selectedRowIndices,
                        validIndices: snapshot.report.rows.indices,
                        budget: &budget
                    )
                )
            }
            return metrics
        case .folder(let snapshot):
            let results = snapshot.results
            guard results.results.count <= limits.maximumRowCount else {
                throw ComparisonReportWorkflowError.tooManyRows(maximum: limits.maximumRowCount)
            }
            var metrics = Metrics(rowCount: results.results.count)
            try addString(results.leftRoot.absoluteString, to: &metrics, limits: limits, budget: &budget)
            try addString(results.rightRoot.absoluteString, to: &metrics, limits: limits, budget: &budget)
            try addString(results.filter.pathQuery, to: &metrics, limits: limits, budget: &budget)
            for selectedID in results.selectedIDs {
                try budget.consume(1)
                try consumeDirectoryResultID(selectedID, limits: limits, budget: &budget)
                metrics.itemCount = try boundedAdd(
                    metrics.itemCount,
                    1,
                    maximum: limits.maximumItemCount,
                    error: .tooManyItems(maximum: limits.maximumItemCount)
                )
            }
            for result in results.results {
                try budget.consume(1)
                try consumeDirectoryResultID(result.id, limits: limits, budget: &budget)
                metrics.itemCount = try boundedAdd(
                    metrics.itemCount,
                    1,
                    maximum: limits.maximumItemCount,
                    error: .tooManyItems(maximum: limits.maximumItemCount)
                )
                if let left = result.left {
                    try addString(left.relativePath, to: &metrics, limits: limits, budget: &budget)
                }
                if let right = result.right {
                    try addString(right.relativePath, to: &metrics, limits: limits, budget: &budget)
                }
            }
            for _ in results.filter.statuses {
                try budget.consume(1)
                metrics.itemCount = try boundedAdd(
                    metrics.itemCount,
                    1,
                    maximum: limits.maximumItemCount,
                    error: .tooManyItems(maximum: limits.maximumItemCount)
                )
            }
            for _ in results.filter.kinds {
                try budget.consume(1)
                metrics.itemCount = try boundedAdd(
                    metrics.itemCount,
                    1,
                    maximum: limits.maximumItemCount,
                    error: .tooManyItems(maximum: limits.maximumItemCount)
                )
            }
            for _ in results.sortDescriptors {
                try budget.consume(1)
                metrics.itemCount = try boundedAdd(
                    metrics.itemCount,
                    1,
                    maximum: limits.maximumItemCount,
                    error: .tooManyItems(maximum: limits.maximumItemCount)
                )
            }
            return metrics
        }
    }

    private static func measure(
        _ report: ComparisonReport,
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Metrics {
        guard report.rows.count <= limits.maximumRowCount else {
            throw ComparisonReportWorkflowError.tooManyRows(maximum: limits.maximumRowCount)
        }
        var metrics = Metrics(rowCount: report.rows.count)
        try addString(report.title, to: &metrics, limits: limits, budget: &budget)
        for column in report.columns {
            try addString(column, to: &metrics, limits: limits, budget: &budget)
        }
        for row in report.rows {
            try budget.consume(1)
            var comparisonWork = try checkedAdd(
                try addString(row.sortKey, to: &metrics, limits: limits, budget: &budget),
                1
            )
            for value in row.values {
                comparisonWork = try checkedAdd(
                    comparisonWork,
                    try checkedAdd(
                        try addString(value, to: &metrics, limits: limits, budget: &budget),
                        1
                    )
                )
            }
            metrics.maximumRowComparisonWork = max(
                metrics.maximumRowComparisonWork,
                comparisonWork
            )
        }
        for item in report.summary?.items ?? [] {
            let comparisonWork = try checkedAdd(
                try checkedAdd(
                    try addString(item.label, to: &metrics, limits: limits, budget: &budget),
                    try addString(item.value, to: &metrics, limits: limits, budget: &budget)
                ),
                2
            )
            metrics.summaryItemCount += 1
            metrics.maximumSummaryComparisonWork = max(
                metrics.maximumSummaryComparisonWork,
                comparisonWork
            )
        }
        let sortWork = try estimatedSortWork(report.rows.count)
        try budget.consume(sortWork)
        return metrics
    }

    private static func reserveGenerationWork(
        for report: ComparisonReport,
        metrics: Metrics,
        format: ComparisonReportFormat,
        maximumOutputBytes: Int,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        guard metrics.itemCount <= ComparisonReport.maximumInputValueCount else {
            throw ComparisonReportError.tooManyInputValues(
                maximum: ComparisonReport.maximumInputValueCount
            )
        }
        guard metrics.inputUTF8ByteCount <= ComparisonReport.maximumInputBytes else {
            throw ComparisonReportError.inputTooLarge(
                maximumBytes: ComparisonReport.maximumInputBytes
            )
        }

        var outputCounter = ComparisonReportWorkflowOutputCounter(
            maximumBytes: maximumOutputBytes
        )
        try outputCounter.render(report, format: format, budget: &budget)

        let rowSortWork = try conservativeSortWork(report.rows.count)
        let summarySortWork = try conservativeSortWork(metrics.summaryItemCount)
        try budget.consume(metrics.itemCount)
        try budget.consume(metrics.inputUTF8ByteCount)
        try budget.consume(
            try checkedProduct(
                rowSortWork,
                metrics.maximumRowComparisonWork
            )
        )
        try budget.consume(
            try checkedProduct(
                summarySortWork,
                metrics.maximumSummaryComparisonWork
            )
        )
        let renderWork = try checkedAdd(
            try checkedProduct(metrics.inputUTF8ByteCount, 4),
            try checkedAdd(outputCounter.byteCount, metrics.itemCount)
        )
        try budget.consume(try checkedProduct(renderWork, 2))
        try budget.consume(try checkedProduct(report.rows.count, 3))
        try budget.consume(try checkedProduct(metrics.summaryItemCount, 2))
        try budget.consume(outputCounter.byteCount)
    }

    private static func validateStructure(
        _ report: ComparisonReport,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        guard !report.columns.isEmpty else { throw ComparisonReportError.noColumns }
        for (index, row) in report.rows.enumerated() {
            try budget.consume(1)
            guard row.values.count == report.columns.count else {
                throw ComparisonReportError.columnCountMismatch(
                    rowIndex: index,
                    expected: report.columns.count,
                    actual: row.values.count
                )
            }
        }
    }

    @discardableResult
    private static func addString(
        _ value: String,
        to metrics: inout Metrics,
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Int {
        let remainingBytes = limits.maximumInputUTF8Bytes - metrics.inputUTF8ByteCount
        let byteCount = try boundedUTF8ByteCount(
            value,
            maximum: remainingBytes,
            budget: &budget
        )
        guard byteCount <= remainingBytes else {
            throw ComparisonReportWorkflowError.inputTooLarge(
                maximumUTF8Bytes: limits.maximumInputUTF8Bytes
            )
        }
        try budget.consume(1)
        metrics.itemCount = try boundedAdd(
            metrics.itemCount,
            1,
            maximum: limits.maximumItemCount,
            error: .tooManyItems(maximum: limits.maximumItemCount)
        )
        metrics.inputUTF8ByteCount = try boundedAdd(
            metrics.inputUTF8ByteCount,
            byteCount,
            maximum: limits.maximumInputUTF8Bytes,
            error: .inputTooLarge(maximumUTF8Bytes: limits.maximumInputUTF8Bytes)
        )
        return byteCount
    }

    private static func estimatedSortWork(_ count: Int) throws -> Int {
        let levels = try sortLevelCount(count)
        let (work, overflow) = count.multipliedReportingOverflow(by: levels)
        guard !overflow else { throw ComparisonReportWorkflowError.arithmeticOverflow }
        return work
    }

    private static func conservativeSortWork(_ count: Int) throws -> Int {
        try checkedProduct(estimatedSortWork(count), 4)
    }

    private static func sortLevelCount(_ count: Int) throws -> Int {
        guard count > 1 else { return count }
        var levels = 0
        var value = count - 1
        while value > 0 {
            levels += 1
            value >>= 1
        }
        return levels
    }

    private static func boundedUTF8ByteCount(
        _ value: String,
        maximum: Int,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Int {
        var count = 0
        for _ in value.utf8 {
            try budget.consume(1)
            guard count < maximum else { return maximum + 1 }
            count += 1
        }
        return count
    }

    private static func minimumInvalidIndex(
        in selectedIndices: Set<Int>,
        validIndices: Range<Int>,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Int {
        var minimum: Int?
        for index in selectedIndices {
            try budget.consume(1)
            if !validIndices.contains(index), minimum.map({ index < $0 }) ?? true {
                minimum = index
            }
        }
        guard let minimum else {
            throw ComparisonReportWorkflowError.snapshotContentsChanged
        }
        return minimum
    }

    private static func consumeDirectoryResultID(
        _ id: DirectoryResult.ID,
        limits: ComparisonReportWorkflowLimits,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        if let leftPath = id.leftRelativePath {
            let count = try boundedUTF8ByteCount(
                leftPath,
                maximum: limits.maximumPathUTF8Bytes,
                budget: &budget
            )
            guard count <= limits.maximumPathUTF8Bytes else {
                throw ComparisonReportWorkflowError.invalidLinkedRelativePath(leftPath)
            }
        }
        if let rightPath = id.rightRelativePath {
            let count = try boundedUTF8ByteCount(
                rightPath,
                maximum: limits.maximumPathUTF8Bytes,
                budget: &budget
            )
            guard count <= limits.maximumPathUTF8Bytes else {
                throw ComparisonReportWorkflowError.invalidLinkedRelativePath(rightPath)
            }
        }
    }

    private static func exactlyEqual(
        _ left: [ComparisonReportLinkedReport],
        _ right: [ComparisonReportLinkedReport],
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for (leftLink, rightLink) in zip(left, right) {
            try budget.consume(1)
            guard leftLink.snapshot == rightLink.snapshot,
                leftLink.directoryResultID == rightLink.directoryResultID,
                try exactlyEqual(leftLink.identifier, rightLink.identifier, budget: &budget),
                try exactlyEqual(
                    leftLink.relativeOutputPath,
                    rightLink.relativeOutputPath,
                    budget: &budget
                ),
                try exactlyEqual(leftLink.report, rightLink.report, budget: &budget)
            else {
                return false
            }
        }
        return true
    }

    private static func exactlyEqual(
        _ left: ComparisonReportWorkflowFingerprintSource,
        _ right: ComparisonReportWorkflowSource,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Bool {
        switch (left, right) {
        case (.file(let leftReport, let leftSelection), .file(let right)):
            guard try exactlyEqual(leftReport, right.report, budget: &budget) else { return false }
            return try exactlyEqual(
                leftSelection,
                right.selectedRowIndices,
                validIndices: leftReport.rows.indices,
                budget: &budget
            )
        case (
            .folder(
                let rootIdentity,
                let leftRoot,
                let rightRoot,
                let results,
                let filter,
                let sortDescriptors,
                let selectedIDs
            ),
            .folder(let rightSnapshot)
        ):
            guard rootIdentity == rightSnapshot.rootIdentity else { return false }
            let right = rightSnapshot.results
            guard
                try exactlyEqual(
                    leftRoot: leftRoot,
                    rightRoot: rightRoot,
                    results: results,
                    filter: filter,
                    sortDescriptors: sortDescriptors,
                    selectedIDs: selectedIDs,
                    to: right,
                    budget: &budget
                )
            else {
                return false
            }
            return true
        default:
            return false
        }
    }

    private static func exactlyEqual(
        _ left: ComparisonReport,
        _ right: ComparisonReport,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Bool {
        guard try exactlyEqual(left.title, right.title, budget: &budget),
            left.columns.count == right.columns.count,
            left.rows.count == right.rows.count,
            left.summary?.items.count == right.summary?.items.count
        else {
            return false
        }
        for (leftColumn, rightColumn) in zip(left.columns, right.columns) {
            guard try exactlyEqual(leftColumn, rightColumn, budget: &budget) else { return false }
        }
        for (leftRow, rightRow) in zip(left.rows, right.rows) {
            try budget.consume(1)
            guard try exactlyEqual(leftRow.sortKey, rightRow.sortKey, budget: &budget),
                leftRow.values.count == rightRow.values.count
            else {
                return false
            }
            for (leftValue, rightValue) in zip(leftRow.values, rightRow.values) {
                guard try exactlyEqual(leftValue, rightValue, budget: &budget) else { return false }
            }
        }
        for (leftItem, rightItem) in zip(left.summary?.items ?? [], right.summary?.items ?? []) {
            guard try exactlyEqual(leftItem.label, rightItem.label, budget: &budget),
                try exactlyEqual(leftItem.value, rightItem.value, budget: &budget)
            else {
                return false
            }
        }
        return true
    }

    private static func exactlyEqual(
        leftRoot: String,
        rightRoot: String,
        results: [DirectoryResult],
        filter: DirectoryResultFilter,
        sortDescriptors: [DirectoryResultSortDescriptor],
        selectedIDs: Set<DirectoryResult.ID>,
        to right: DirectoryResults,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Bool {
        guard try exactlyEqual(leftRoot, right.leftRoot.absoluteString, budget: &budget),
            try exactlyEqual(rightRoot, right.rightRoot.absoluteString, budget: &budget),
            results.count == right.results.count,
            filter.statuses == right.filter.statuses,
            filter.kinds == right.filter.kinds,
            filter.hidden == right.filter.hidden,
            try exactlyEqual(filter.pathQuery, right.filter.pathQuery, budget: &budget),
            sortDescriptors.count == right.sortDescriptors.count,
            selectedIDs.count == right.selectedIDs.count
        else {
            return false
        }
        for (leftDescriptor, rightDescriptor) in zip(
            sortDescriptors,
            right.sortDescriptors
        ) {
            try budget.consume(1)
            guard leftDescriptor == rightDescriptor else { return false }
        }
        var matchedSelectedIDCount = 0
        for (leftResult, rightResult) in zip(results, right.results) {
            try budget.consume(1)
            let leftIsSelected = selectedIDs.contains(leftResult.id)
            let rightIsSelected = right.selectedIDs.contains(rightResult.id)
            guard try exactlyEqual(leftResult.left, rightResult.left, budget: &budget),
                try exactlyEqual(leftResult.right, rightResult.right, budget: &budget),
                leftResult.status == rightResult.status,
                leftIsSelected == rightIsSelected
            else {
                return false
            }
            if leftIsSelected { matchedSelectedIDCount += 1 }
        }
        return matchedSelectedIDCount == selectedIDs.count
    }

    private static func exactlyEqual(
        _ left: Set<Int>,
        _ right: Set<Int>,
        validIndices: Range<Int>,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        var matchedCount = 0
        for index in validIndices {
            try budget.consume(1)
            let leftContains = left.contains(index)
            guard leftContains == right.contains(index) else { return false }
            if leftContains { matchedCount += 1 }
        }
        return matchedCount == left.count
    }

    private static func exactlyEqual(
        _ left: DirectoryEntryMetadata?,
        _ right: DirectoryEntryMetadata?,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Bool {
        switch (left, right) {
        case (nil, nil):
            return true
        case (let left?, let right?):
            return try exactlyEqual(left.relativePath, right.relativePath, budget: &budget)
                && left.kind == right.kind
                && left.byteCount == right.byteCount
                && exactDateEqual(left.modificationDate, right.modificationDate)
                && left.isHidden == right.isHidden
        default:
            return false
        }
    }

    private static func exactDateEqual(_ left: Date?, _ right: Date?) -> Bool {
        switch (left, right) {
        case (nil, nil):
            true
        case (let left?, let right?):
            left.timeIntervalSinceReferenceDate.bitPattern
                == right.timeIntervalSinceReferenceDate.bitPattern
        default:
            false
        }
    }

    private static func exactlyEqual(
        _ left: String,
        _ right: String,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Bool {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        while true {
            try budget.consume(1)
            switch (leftIterator.next(), rightIterator.next()) {
            case (let leftByte?, let rightByte?):
                if leftByte != rightByte { return false }
            case (nil, nil):
                return true
            default:
                return false
            }
        }
    }

    private static func compareUTF8(
        _ left: String,
        _ right: String,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Int {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        while true {
            try budget.consume(1)
            switch (leftIterator.next(), rightIterator.next()) {
            case (let leftByte?, let rightByte?):
                if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
            case (nil, nil):
                return 0
            case (nil, _?):
                return -1
            case (_?, nil):
                return 1
            }
        }
    }

    private enum OutputIdentityRelationship {
        case distinct
        case equal
        case ancestor
        case descendant
    }

    private static func outputIdentityRelationship(
        _ left: ComparisonReportCanonicalOutputIdentity,
        _ right: ComparisonReportCanonicalOutputIdentity,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> OutputIdentityRelationship {
        let leftBytes = left.canonicalPathUTF8Bytes
        let rightBytes = right.canonicalPathUTF8Bytes
        let commonCount = min(leftBytes.count, rightBytes.count)
        for index in 0..<commonCount {
            try budget.consume(1)
            guard leftBytes[index] == rightBytes[index] else { return .distinct }
        }
        if leftBytes.count == rightBytes.count { return .equal }
        if leftBytes.count < rightBytes.count {
            if leftBytes.count == 1, leftBytes[0] == UInt8(ascii: "/") { return .ancestor }
            return rightBytes[leftBytes.count] == UInt8(ascii: "/") ? .ancestor : .distinct
        }
        if rightBytes.count == 1, rightBytes[0] == UInt8(ascii: "/") { return .descendant }
        return leftBytes[rightBytes.count] == UInt8(ascii: "/") ? .descendant : .distinct
    }

    /// Provisional lexical preflight only. Executor must prove case behavior and containment from
    /// pinned descriptors before publishing on the destination volume.
    private static func caseInsensitiveOutputIdentityRelationship(
        _ left: ComparisonReportCanonicalOutputIdentity,
        _ right: ComparisonReportCanonicalOutputIdentity,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> OutputIdentityRelationship {
        try budget.consume(
            try checkedAdd(
                left.canonicalPathUTF8Bytes.count,
                right.canonicalPathUTF8Bytes.count
            )
        )
        let leftComponents = left.canonicalPath.split(separator: "/")
        let rightComponents = right.canonicalPath.split(separator: "/")
        let commonCount = min(leftComponents.count, rightComponents.count)
        let locale = Locale(identifier: "en_US_POSIX")
        for index in 0..<commonCount {
            try budget.consume(1)
            guard
                String(leftComponents[index]).compare(
                    String(rightComponents[index]),
                    options: .caseInsensitive,
                    locale: locale
                ) == .orderedSame
            else {
                return .distinct
            }
        }
        if leftComponents.count == rightComponents.count { return .equal }
        return leftComponents.count < rightComponents.count ? .ancestor : .descendant
    }

    private static func cancellableSorted<Element>(
        _ values: [Element],
        budget: inout ComparisonReportWorkflowBudget,
        by areInIncreasingOrder: (
            Element,
            Element,
            inout ComparisonReportWorkflowBudget
        ) throws -> Bool
    ) throws -> [Element] {
        guard values.count > 1 else {
            try budget.consume(values.count)
            return values
        }
        try budget.consume(try checkedProduct(values.count, 2))
        var source = values
        var destination = values
        var width = 1
        while width < source.count {
            try Task.checkCancellation()
            var lowerBound = 0
            while lowerBound < source.count {
                let middle = min(lowerBound + width, source.count)
                let upperBound = min(middle + width, source.count)
                var left = lowerBound
                var right = middle
                var output = lowerBound
                while left < middle || right < upperBound {
                    try budget.consume(1)
                    let takeLeft: Bool
                    if right == upperBound {
                        takeLeft = true
                    } else if left == middle {
                        takeLeft = false
                    } else {
                        takeLeft = try !areInIncreasingOrder(
                            source[right],
                            source[left],
                            &budget
                        )
                    }
                    if takeLeft {
                        destination[output] = source[left]
                        left += 1
                    } else {
                        destination[output] = source[right]
                        right += 1
                    }
                    output += 1
                }
                lowerBound = upperBound
            }
            swap(&source, &destination)
            if width > source.count / 2 { break }
            width *= 2
        }
        try Task.checkCancellation()
        return source
    }

    private static func checkedAdd(_ left: Int, _ right: Int) throws -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw ComparisonReportWorkflowError.arithmeticOverflow }
        return result
    }

    private static func checkedProduct(_ left: Int, _ right: Int) throws -> Int {
        let (result, overflow) = left.multipliedReportingOverflow(by: right)
        guard !overflow else { throw ComparisonReportWorkflowError.arithmeticOverflow }
        return result
    }

    private static func boundedAdd(
        _ left: Int,
        _ right: Int,
        maximum: Int,
        error: ComparisonReportWorkflowError
    ) throws -> Int {
        guard right >= 0, left >= 0, right <= maximum - left else { throw error }
        return left + right
    }
}

private struct ComparisonReportWorkflowOutputCounter {
    private let maximumBytes: Int
    private(set) var byteCount = 0

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    mutating func render(
        _ report: ComparisonReport,
        format: ComparisonReportFormat,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        switch format {
        case .plainText:
            try appendPlainEscaped(report.title, budget: &budget)
            try append("\n", budget: &budget)
            if let summary = report.summary {
                try append("\nSummary\n", budget: &budget)
                for item in summary.items {
                    try appendPlainEscaped(item.label, budget: &budget)
                    try append(": ", budget: &budget)
                    try appendPlainEscaped(item.value, budget: &budget)
                    try append("\n", budget: &budget)
                }
            }
            try append("\n", budget: &budget)
            try appendPlainRecord(report.columns, budget: &budget)
            for row in report.rows {
                try appendPlainRecord(row.values, budget: &budget)
            }
        case .csv:
            try appendCSVRecord(report.columns, budget: &budget)
            for row in report.rows {
                try appendCSVRecord(row.values, budget: &budget)
            }
        case .html:
            try appendHTML(report, budget: &budget)
        }
    }

    private mutating func appendPlainRecord(
        _ values: [String],
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        for (index, value) in values.enumerated() {
            if index != 0 { try append("\t", budget: &budget) }
            try appendPlainEscaped(value, budget: &budget)
        }
        try append("\n", budget: &budget)
    }

    private mutating func appendCSVRecord(
        _ values: [String],
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        for (index, value) in values.enumerated() {
            if index != 0 { try append(",", budget: &budget) }
            try appendCSVField(value, budget: &budget)
        }
        try append("\r\n", budget: &budget)
    }

    private mutating func appendHTML(
        _ report: ComparisonReport,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        try append(
            """
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>
            """,
            budget: &budget
        )
        try appendHTMLEscaped(report.title, budget: &budget)
        try append(
            """
            </title>
            <style>
            :root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}body{margin:2rem;background:Canvas;color:CanvasText}main{max-width:100%;overflow:auto}h1{font-size:1.5rem}.summary{display:grid;grid-template-columns:max-content minmax(0,1fr);gap:.35rem 1rem}.summary dt{font-weight:600}.summary dd{margin:0}table{border-collapse:collapse;width:100%}th,td{border:1px solid color-mix(in srgb,CanvasText 30%,transparent);padding:.4rem .55rem;text-align:left;vertical-align:top;white-space:pre-wrap;overflow-wrap:anywhere}th{background:color-mix(in srgb,CanvasText 8%,Canvas)}tbody tr:nth-child(even){background:color-mix(in srgb,CanvasText 4%,Canvas)}
            </style>
            </head>
            <body>
            <main>
            <h1>
            """,
            budget: &budget
        )
        try appendHTMLEscaped(report.title, budget: &budget)
        try append("</h1>\n", budget: &budget)
        if let summary = report.summary {
            try append(
                "<section aria-labelledby=\"summary-heading\">\n<h2 id=\"summary-heading\">Summary</h2>\n<dl class=\"summary\">\n",
                budget: &budget
            )
            for item in summary.items {
                try append("<dt>", budget: &budget)
                try appendHTMLEscaped(item.label, budget: &budget)
                try append("</dt><dd>", budget: &budget)
                try appendHTMLEscaped(item.value, budget: &budget)
                try append("</dd>\n", budget: &budget)
            }
            try append("</dl>\n</section>\n", budget: &budget)
        }
        try append("<table>\n<thead><tr>", budget: &budget)
        for column in report.columns {
            try append("<th scope=\"col\">", budget: &budget)
            try appendHTMLEscaped(column, budget: &budget)
            try append("</th>", budget: &budget)
        }
        try append("</tr></thead>\n<tbody>\n", budget: &budget)
        for row in report.rows {
            try append("<tr>", budget: &budget)
            for value in row.values {
                try append("<td>", budget: &budget)
                try appendHTMLEscaped(value, budget: &budget)
                try append("</td>", budget: &budget)
            }
            try append("</tr>\n", budget: &budget)
        }
        try append("</tbody>\n</table>\n</main>\n</body>\n</html>\n", budget: &budget)
    }

    private mutating func appendPlainEscaped(
        _ value: String,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        for scalar in value.unicodeScalars {
            try budget.consume(1)
            switch scalar.value {
            case 0x09, 0x0A, 0x0D, 0x5C:
                try appendByteCount(2)
            case let scalarValue where Self.isUnsupportedControl(scalarValue):
                try appendControlEscape(scalarValue)
            default:
                try appendByteCount(Self.utf8ByteCount(of: scalar.value))
            }
        }
    }

    private mutating func appendCSVField(
        _ value: String,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        var requiresQuotes = false
        for scalar in value.unicodeScalars {
            try budget.consume(1)
            if scalar.value == 0x22 || scalar.value == 0x2C || scalar.value == 0x0A
                || scalar.value == 0x0D
            {
                requiresQuotes = true
            }
        }
        if requiresQuotes { try appendByteCount(1) }
        if try Self.requiresSpreadsheetNeutralization(value, budget: &budget) {
            try appendByteCount(1)
        }
        for scalar in value.unicodeScalars {
            try budget.consume(1)
            if scalar.value == 0x22 { try appendByteCount(1) }
            if Self.isUnsupportedControl(scalar.value) {
                try appendControlEscape(scalar.value)
            } else {
                try appendByteCount(Self.utf8ByteCount(of: scalar.value))
            }
        }
        if requiresQuotes { try appendByteCount(1) }
    }

    private mutating func appendHTMLEscaped(
        _ value: String,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        for scalar in value.unicodeScalars {
            try budget.consume(1)
            switch scalar.value {
            case 0x26: try appendByteCount(5)
            case 0x3C, 0x3E: try appendByteCount(4)
            case 0x22: try appendByteCount(6)
            case 0x27: try appendByteCount(5)
            case let scalarValue where Self.isUnsupportedControl(scalarValue):
                try appendControlEscape(scalarValue)
            default:
                try appendByteCount(Self.utf8ByteCount(of: scalar.value))
            }
        }
    }

    private mutating func append(
        _ value: String,
        budget: inout ComparisonReportWorkflowBudget
    ) throws {
        var count = 0
        for _ in value.utf8 {
            try budget.consume(1)
            count += 1
        }
        try appendByteCount(count)
    }

    private mutating func appendControlEscape(_ value: UInt32) throws {
        var hexadecimalDigits = 1
        var remainder = value
        while remainder >= 16 {
            hexadecimalDigits += 1
            remainder >>= 4
        }
        try appendByteCount(try Self.checkedAdd(hexadecimalDigits, 4))
    }

    private mutating func appendByteCount(_ count: Int) throws {
        guard count >= 0, count <= maximumBytes - byteCount else {
            throw ComparisonReportError.outputTooLarge(maximumBytes: maximumBytes)
        }
        byteCount += count
    }

    private static func requiresSpreadsheetNeutralization(
        _ value: String,
        budget: inout ComparisonReportWorkflowBudget
    ) throws -> Bool {
        var foundStrippedPrefix = false
        for scalar in value.unicodeScalars {
            try budget.consume(1)
            if scalar.value == 0x2B || scalar.value == 0x2D || scalar.value == 0x3D
                || scalar.value == 0x40
            {
                return true
            }
            guard
                scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
                    || scalar.value == 0xFEFF
            else {
                return foundStrippedPrefix
            }
            foundStrippedPrefix = true
        }
        return foundStrippedPrefix
    }

    private static func isUnsupportedControl(_ value: UInt32) -> Bool {
        value <= 0x08 || value == 0x0B || value == 0x0C || (0x0E...0x1F).contains(value)
            || (0x7F...0x9F).contains(value)
    }

    private static func utf8ByteCount(of value: UInt32) -> Int {
        if value <= 0x7F { return 1 }
        if value <= 0x7FF { return 2 }
        if value <= 0xFFFF { return 3 }
        return 4
    }

    private static func checkedAdd(_ left: Int, _ right: Int) throws -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw ComparisonReportWorkflowError.arithmeticOverflow }
        return result
    }
}

private struct ComparisonReportWorkflowBudget {
    private let maximum: Int
    private let cancellationCheckInterval: Int
    private var nextCancellationCheck: Int
    private(set) var consumed = 0

    init(limits: ComparisonReportWorkflowLimits) {
        maximum = limits.maximumWorkUnits
        cancellationCheckInterval = limits.cancellationCheckInterval
        nextCancellationCheck = limits.cancellationCheckInterval
    }

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, consumed <= maximum - amount else {
            throw ComparisonReportWorkflowError.workLimitExceeded(maximumWorkUnits: maximum)
        }
        consumed += amount
        if consumed >= nextCancellationCheck {
            try Task.checkCancellation()
            let (next, overflow) = consumed.addingReportingOverflow(cancellationCheckInterval)
            nextCancellationCheck = overflow ? Int.max : next
        }
    }
}
