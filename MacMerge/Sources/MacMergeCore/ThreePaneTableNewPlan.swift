import Foundation

/// Bounded UI-independent new plan for `ID_FILE_NEW3_TABLE`.
///
/// Planning only. Never reads files, opens pickers, creates documents, or performs I/O.
/// Caller supplies canonical paths, byte sizes, and SHA-256 digests. Host materializes
/// bound revisions, parses via `DelimitedTableParser`, and compares via `TableComparison`
/// or `ThreeWayTableComparison`. All descriptions, debug output, and mirrors are redacted:
/// digests plus counts only, never full paths or cell bytes.
public enum ThreePaneTableNewPane: String, CaseIterable, Hashable, Sendable {
    case left
    case middle
    case right

    public var sortOrder: Int {
        switch self {
        case .left: 0
        case .middle: 1
        case .right: 2
        }
    }
}

/// File URL identity without I/O: canonical path plus byte size plus SHA-256 revision.
public struct ThreePaneTableNewFileIdentity: Equatable, Hashable, Sendable {
    public let canonicalPath: String
    public let byteSize: Int
    public let contentSHA256: [UInt8]

    public init(canonicalPath: String, byteSize: Int, contentSHA256: [UInt8]) {
        self.canonicalPath = canonicalPath
        self.byteSize = byteSize
        self.contentSHA256 = contentSHA256
    }

    public var digestPrefix: String {
        threePaneTableNewDigestPrefix(contentSHA256)
    }
}

extension ThreePaneTableNewFileIdentity: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ThreePaneTableNewFileIdentity(bytes:\(byteSize) digest:\(digestPrefix))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "byteSize": byteSize,
                "digestPrefix": digestPrefix,
                "digestByteCount": contentSHA256.count
            ],
            displayStyle: .struct
        )
    }
}

/// One slot of the three-pane request. Only the middle slot may be empty.
public enum ThreePaneTableNewPaneSource: Equatable, Hashable, Sendable {
    case file(ThreePaneTableNewFileIdentity)
    case empty

    public var isEmpty: Bool {
        if case .empty = self { true } else { false }
    }

    public var fileIdentity: ThreePaneTableNewFileIdentity? {
        if case .file(let identity) = self { identity } else { nil }
    }
}

/// Pane plus source pairing supplied by the caller.
public struct ThreePaneTableNewRequestPane: Equatable, Hashable, Sendable {
    public let pane: ThreePaneTableNewPane
    public let source: ThreePaneTableNewPaneSource

    public init(pane: ThreePaneTableNewPane, source: ThreePaneTableNewPaneSource) {
        self.pane = pane
        self.source = source
    }
}

/// Bounded custom delimiter: raw bytes only, never cell content.
///
/// Intent: single-character UTF-8 delimiters get the authoritative
/// `DelimitedTableParser` check in `validateFormat`. Multi-byte or non-UTF-8
/// raw byte sequences are still accepted here when every byte avoids
/// 0x00/0x0A/0x0D; the host resolves the actual scalar mapping at execution.
/// Only 0x00 (NUL), 0x0A (LF), and 0x0D (CR) bytes are rejected at plan time.
public struct ThreePaneTableNewDelimiter: Equatable, Hashable, Sendable {
    public let bytes: [UInt8]

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public static var comma: ThreePaneTableNewDelimiter {
        ThreePaneTableNewDelimiter(bytes: [0x2C])
    }

    public static var tab: ThreePaneTableNewDelimiter {
        ThreePaneTableNewDelimiter(bytes: [0x09])
    }
}

extension ThreePaneTableNewDelimiter: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ThreePaneTableNewDelimiter(byteCount:\(bytes.count))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["byteCount": bytes.count], displayStyle: .struct)
    }
}

public enum ThreePaneTableNewOrientation: String, CaseIterable, Hashable, Sendable {
    case sideBySide
    case stacked
}

/// Executor feature required for a bound three-pane table plan.
public enum ThreePaneTableNewFeature: String, CaseIterable, Hashable, Sendable {
    case bindPinnedRevisions
    case authoritativeParser
    case deterministicReceipt

    public static var required: Set<ThreePaneTableNewFeature> {
        Set(ThreePaneTableNewFeature.allCases)
    }
}

/// Capability requirement naming the existing table cores. Never redeclares them.
public struct ThreePaneTableNewCapabilityRequirement: Equatable, Hashable, Sendable {
    public let parserCoreName: String
    public let twoWayCoreName: String
    public let threeWayCoreName: String
    public let supportsEmptyMiddle: Bool
    public let features: Set<ThreePaneTableNewFeature>

    public init(
        parserCoreName: String = "DelimitedTableParser",
        twoWayCoreName: String = "TableComparison",
        threeWayCoreName: String = "ThreeWayTableComparison",
        supportsEmptyMiddle: Bool = true,
        features: Set<ThreePaneTableNewFeature> = Set(ThreePaneTableNewFeature.allCases)
    ) {
        self.parserCoreName = parserCoreName
        self.twoWayCoreName = twoWayCoreName
        self.threeWayCoreName = threeWayCoreName
        self.supportsEmptyMiddle = supportsEmptyMiddle
        self.features = features
    }

    public static var authoritativeParserCoreName: String {
        String(describing: DelimitedTableParser.self)
    }

    public static var authoritativeTwoWayCoreName: String {
        String(describing: TableComparison.self)
    }

    public static var authoritativeThreeWayCoreName: String {
        String(describing: ThreeWayTableComparison.self)
    }

    public static var authoritativeCores: [String] {
        [authoritativeParserCoreName, authoritativeTwoWayCoreName, authoritativeThreeWayCoreName]
    }

    public static var twoWayDefaultOptions: TableComparisonOptions {
        .default
    }

    public static var threeWayDefaultOptions: ThreeWayTableComparisonOptions {
        .default
    }

    public func validate(requiredFeatures: Set<ThreePaneTableNewFeature> = ThreePaneTableNewFeature.required) throws {
        guard parserCoreName == Self.authoritativeParserCoreName else {
            throw ThreePaneTableNewError.unsupportedCapability(name: parserCoreName)
        }
        guard twoWayCoreName == Self.authoritativeTwoWayCoreName else {
            throw ThreePaneTableNewError.unsupportedCapability(name: twoWayCoreName)
        }
        guard threeWayCoreName == Self.authoritativeThreeWayCoreName else {
            throw ThreePaneTableNewError.unsupportedCapability(name: threeWayCoreName)
        }
        guard requiredFeatures.isSubset(of: features) else {
            let missing = requiredFeatures.subtracting(features).sorted { $0.rawValue < $1.rawValue }
            throw ThreePaneTableNewError.unsupportedFeature(name: missing.first?.rawValue ?? "unknown")
        }
    }
}

/// Caller-supplied intent: exactly three slots, middle may be empty for two-source creation.
///
/// Authoritative parsing/binding stays with `DelimitedTableParser`, `TableComparison`,
/// and `ThreeWayTableComparison`. This request only carries their settings:
/// delimiter plus quote plus newline handling, header presentation, and selection.
/// It never renders spreadsheets, menus, or executes I/O.
public struct ThreePaneTableNewRequest: Equatable, Hashable, Sendable {
    public let panes: [ThreePaneTableNewRequestPane]
    public let delimiter: ThreePaneTableNewDelimiter
    public let quote: Character?
    public let allowsNewlinesInQuotedCells: Bool
    public let headerVisibility: TableWorkspaceHeaderVisibility
    public let headerLabels: TableWorkspaceHeaderLabels
    public let selection: TableWorkspaceSelection
    public let requiredFeatures: Set<ThreePaneTableNewFeature>
    public let datasetRevision: UInt64
    public let orientation: ThreePaneTableNewOrientation
    public let capability: ThreePaneTableNewCapabilityRequirement
    public let declaredRowCount: Int
    public let declaredCellCount: Int

    public init(
        panes: [ThreePaneTableNewRequestPane],
        delimiter: ThreePaneTableNewDelimiter,
        quote: Character? = "\"",
        allowsNewlinesInQuotedCells: Bool = true,
        headerVisibility: TableWorkspaceHeaderVisibility = .visible,
        headerLabels: TableWorkspaceHeaderLabels = .ordinal,
        selection: TableWorkspaceSelection = .none,
        requiredFeatures: Set<ThreePaneTableNewFeature> = ThreePaneTableNewFeature.required,
        datasetRevision: UInt64 = 0,
        orientation: ThreePaneTableNewOrientation = .sideBySide,
        capability: ThreePaneTableNewCapabilityRequirement = ThreePaneTableNewCapabilityRequirement(),
        declaredRowCount: Int,
        declaredCellCount: Int
    ) {
        self.panes = panes
        self.delimiter = delimiter
        self.quote = quote
        self.allowsNewlinesInQuotedCells = allowsNewlinesInQuotedCells
        self.headerVisibility = headerVisibility
        self.headerLabels = headerLabels
        self.selection = selection
        self.requiredFeatures = requiredFeatures
        self.datasetRevision = datasetRevision
        self.orientation = orientation
        self.capability = capability
        self.declaredRowCount = declaredRowCount
        self.declaredCellCount = declaredCellCount
    }
}

extension ThreePaneTableNewRequest: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ThreePaneTableNewRequest(slots:\(panes.count) rows:\(declaredRowCount) cells:\(declaredCellCount))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "slotCount": panes.count,
                "declaredRowCount": declaredRowCount,
                "declaredCellCount": declaredCellCount,
                "delimiterByteCount": delimiter.bytes.count,
                "headerVisibility": String(describing: headerVisibility),
                "headerLabels": String(describing: headerLabels),
                "selection": "<redacted>",
                "requiredFeatureCount": requiredFeatures.count,
                "datasetRevision": datasetRevision
            ],
            displayStyle: .struct
        )
    }
}

public enum ThreePaneTableNewLimit: String, CaseIterable, Hashable, Sendable {
    case sources
    case sourceBytes
    case combinedSourceBytes
    case pathBytes
    case delimiterBytes
    case rowCount
    case cellCount
    case workUnits
    case cancellationCheckInterval
}

public struct ThreePaneTableNewLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumSources = 3
    public static let hardMaximumSourceBytes = 256 * 1024 * 1024
    public static let hardMaximumCombinedSourceBytes = 768 * 1024 * 1024
    public static let hardMaximumPathUTF8Bytes = 32 * 1024
    public static let hardMaximumDelimiterBytes = 8
    public static let hardMaximumRowCount = 2_097_152
    public static let hardMaximumCellCount = 2_097_152
    public static let hardMaximumWorkUnits = 64 * 1024 * 1024
    public static let hardMaximumCancellationCheckInterval = 4_096
    public static let `default` = ThreePaneTableNewLimits()

    public let maximumSources: Int
    public let maximumSourceBytes: Int
    public let maximumCombinedSourceBytes: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumDelimiterBytes: Int
    public let maximumRowCount: Int
    public let maximumCellCount: Int
    public let maximumWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumSources: Int = 3,
        maximumSourceBytes: Int = 64 * 1024 * 1024,
        maximumPathUTF8Bytes: Int = 4 * 1024,
        maximumCombinedSourceBytes: Int = 192 * 1024 * 1024,
        maximumDelimiterBytes: Int = 4,
        maximumRowCount: Int = 1_048_576,
        maximumCellCount: Int = 1_048_576,
        maximumWorkUnits: Int = 16 * 1024 * 1024,
        cancellationCheckInterval: Int = 1_024
    ) {
        self.maximumSources = maximumSources
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumCombinedSourceBytes = maximumCombinedSourceBytes
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumDelimiterBytes = maximumDelimiterBytes
        self.maximumRowCount = maximumRowCount
        self.maximumCellCount = maximumCellCount
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }

    public func validate() throws {
        guard (2...Self.hardMaximumSources).contains(maximumSources) else {
            throw ThreePaneTableNewError.invalidLimit(.sources, value: maximumSources)
        }
        guard (1...Self.hardMaximumSourceBytes).contains(maximumSourceBytes) else {
            throw ThreePaneTableNewError.invalidLimit(.sourceBytes, value: maximumSourceBytes)
        }
        guard (1...Self.hardMaximumCombinedSourceBytes).contains(maximumCombinedSourceBytes) else {
            throw ThreePaneTableNewError.invalidLimit(.combinedSourceBytes, value: maximumCombinedSourceBytes)
        }
        guard maximumCombinedSourceBytes >= maximumSourceBytes else {
            throw ThreePaneTableNewError.invalidLimit(.combinedSourceBytes, value: maximumCombinedSourceBytes)
        }
        guard (1...Self.hardMaximumPathUTF8Bytes).contains(maximumPathUTF8Bytes) else {
            throw ThreePaneTableNewError.invalidLimit(.pathBytes, value: maximumPathUTF8Bytes)
        }
        guard (1...Self.hardMaximumDelimiterBytes).contains(maximumDelimiterBytes) else {
            throw ThreePaneTableNewError.invalidLimit(.delimiterBytes, value: maximumDelimiterBytes)
        }
        guard (1...Self.hardMaximumRowCount).contains(maximumRowCount) else {
            throw ThreePaneTableNewError.invalidLimit(.rowCount, value: maximumRowCount)
        }
        guard (1...Self.hardMaximumCellCount).contains(maximumCellCount) else {
            throw ThreePaneTableNewError.invalidLimit(.cellCount, value: maximumCellCount)
        }
        guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
            throw ThreePaneTableNewError.invalidLimit(.workUnits, value: maximumWorkUnits)
        }
        guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
            throw ThreePaneTableNewError.invalidLimit(.cancellationCheckInterval, value: cancellationCheckInterval)
        }
    }
}

/// Deterministic receipt: digest prefixes plus counts only, never paths or cell bytes.
/// Binds orientation, headers, quote/newline settings, selection, features, limits,
/// capability cores, and dataset revision so forged plans with drifted settings mismatch.
public struct ThreePaneTableNewReceipt: Equatable, Hashable, Sendable {
    public let identifier: String
    public let leftDigestPrefix: String
    public let middleDigestPrefix: String
    public let rightDigestPrefix: String
    public let declaredRowCount: Int
    public let declaredCellCount: Int
    public let delimiterByteCount: Int
    public let orientation: ThreePaneTableNewOrientation
    public let headerVisibility: TableWorkspaceHeaderVisibility
    public let headerLabels: TableWorkspaceHeaderLabels
    public let allowsNewlinesInQuotedCells: Bool
    public let datasetRevision: UInt64
    public let sourceCount: Int

    public init(
        identifier: String,
        leftDigestPrefix: String,
        middleDigestPrefix: String,
        rightDigestPrefix: String,
        declaredRowCount: Int,
        declaredCellCount: Int,
        delimiterByteCount: Int,
        orientation: ThreePaneTableNewOrientation = .sideBySide,
        headerVisibility: TableWorkspaceHeaderVisibility = .visible,
        headerLabels: TableWorkspaceHeaderLabels = .ordinal,
        allowsNewlinesInQuotedCells: Bool = true,
        datasetRevision: UInt64 = 0,
        sourceCount: Int = 3
    ) {
        self.identifier = identifier
        self.leftDigestPrefix = leftDigestPrefix
        self.middleDigestPrefix = middleDigestPrefix
        self.rightDigestPrefix = rightDigestPrefix
        self.declaredRowCount = declaredRowCount
        self.declaredCellCount = declaredCellCount
        self.delimiterByteCount = delimiterByteCount
        self.orientation = orientation
        self.headerVisibility = headerVisibility
        self.headerLabels = headerLabels
        self.allowsNewlinesInQuotedCells = allowsNewlinesInQuotedCells
        self.datasetRevision = datasetRevision
        self.sourceCount = sourceCount
    }
}

extension ThreePaneTableNewReceipt: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        identifier
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "identifier": identifier,
                "declaredRowCount": declaredRowCount,
                "declaredCellCount": declaredCellCount,
                "delimiterByteCount": delimiterByteCount,
                "orientation": orientation.rawValue,
                "datasetRevision": datasetRevision,
                "sourceCount": sourceCount
            ],
            displayStyle: .struct
        )
    }
}

public enum ThreePaneTableNewExecutorContract: String, CaseIterable, Hashable, Sendable {
    case planOnly

    public var requiredCores: [String] {
        ThreePaneTableNewCapabilityRequirement.authoritativeCores
    }
}

extension ThreePaneTableNewExecutorContract: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "plan-only; host materializes revisions via DelimitedTableParser and TableComparison cores; no I/O"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["contract": rawValue], displayStyle: .enum)
    }
}

/// Bound plan: exact revisions pinned by SHA-256, deterministic receipt, plan-only contract.
/// Host must hold bound revisions immutable during planning and revalidate exact
/// dataset revision compare-and-swap before execution.
public struct ThreePaneTableNewPlan: Equatable, Hashable, Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let commandID = "ID_FILE_NEW3_TABLE"

    public let panes: [ThreePaneTableNewRequestPane]
    public let delimiter: ThreePaneTableNewDelimiter
    public let quote: Character?
    public let allowsNewlinesInQuotedCells: Bool
    public let headerVisibility: TableWorkspaceHeaderVisibility
    public let headerLabels: TableWorkspaceHeaderLabels
    public let selection: TableWorkspaceSelection
    public let requiredFeatures: Set<ThreePaneTableNewFeature>
    public let datasetRevision: UInt64
    public let orientation: ThreePaneTableNewOrientation
    public let capability: ThreePaneTableNewCapabilityRequirement
    public let receipt: ThreePaneTableNewReceipt
    public let executorContract: ThreePaneTableNewExecutorContract
    public let limits: ThreePaneTableNewLimits
    public let workPerformed: Int

    public var isTwoSourceMerge: Bool {
        panes.contains { $0.pane == .middle && $0.source.isEmpty }
    }

    /// Exact CAS: reject forged or drifted receipts.
    public func requireReceipt(_ other: ThreePaneTableNewReceipt) throws {
        guard other == receipt else {
            throw ThreePaneTableNewError.receiptMismatch
        }
    }

    /// Exact CAS: reject stale dataset revisions. Caller must present the same
    /// revision the plan was bound against; any other revision is stale.
    public func requireCurrentDataset(revision: UInt64) throws {
        guard revision == datasetRevision else {
            throw ThreePaneTableNewError.staleDatasetRevision(expected: datasetRevision, actual: revision)
        }
    }

    public static func plan(
        request: ThreePaneTableNewRequest,
        limits: ThreePaneTableNewLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ThreePaneTableNewPlan {
        try make(request: request, limits: limits, cancellationCheck: cancellationCheck)
    }

    public static func make(
        request: ThreePaneTableNewRequest,
        limits: ThreePaneTableNewLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ThreePaneTableNewPlan {
        // Validate limits before meters: constructing work with an invalid
        // cancellationCheckInterval (0) would trap on division. Same for maximumWorkUnits.
        try limits.validate()
        var work = ThreePaneTableNewWork(
            maximum: limits.maximumWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try work.checkCancellation()
        try work.consume()
        // Required-features subset correctly: request must carry the static minimum,
        // and the capability must carry everything the request requires.
        // Reversing either direction accepts forged or under-capable plans.
        guard ThreePaneTableNewFeature.required.isSubset(of: request.requiredFeatures) else {
            let missing = ThreePaneTableNewFeature.required.subtracting(request.requiredFeatures)
                .sorted { $0.rawValue < $1.rawValue }
            throw ThreePaneTableNewError.unsupportedFeature(name: missing.first?.rawValue ?? "unknown")
        }
        try request.capability.validate(requiredFeatures: request.requiredFeatures)
        try work.consume()

        guard request.panes.count == 3 else {
            throw ThreePaneTableNewError.invalidPaneCount(expected: 3, actual: request.panes.count)
        }
        var seen: Set<ThreePaneTableNewPane> = []
        for pane in request.panes {
            try work.consume()
            guard seen.insert(pane.pane).inserted else {
                throw ThreePaneTableNewError.duplicatePane(pane.pane)
            }
        }
        // Defensive completeness check: currently unreachable. With exactly three
        // slots, no duplicates, and a three-case pane enum, three distinct panes
        // must cover left/middle/right (pigeonhole). Any missing pane would have
        // already thrown duplicatePane above. Retained so a future fourth pane
        // cannot silently pass, and so the missingPane case stays API-stable.
        for required in [ThreePaneTableNewPane.left, .middle, .right] as [ThreePaneTableNewPane] {
            guard seen.contains(required) else {
                throw ThreePaneTableNewError.missingPane(required)
            }
        }
        let sorted = request.panes.sorted { $0.pane.sortOrder < $1.pane.sortOrder }
        guard let leftIdentity = sorted[0].source.fileIdentity else {
            throw ThreePaneTableNewError.unexpectedEmptyPane(.left)
        }
        let middleIdentity = sorted[1].source.fileIdentity
        guard let rightIdentity = sorted[2].source.fileIdentity else {
            throw ThreePaneTableNewError.unexpectedEmptyPane(.right)
        }
        if middleIdentity == nil, request.capability.supportsEmptyMiddle == false {
            throw ThreePaneTableNewError.emptyMiddleUnsupported
        }
        // Enforce maximumSources against bound (non-empty) sources, not slots.
        // Two-source creations bind 2, three-file creations bind 3.
        let boundSourceCount = [leftIdentity, middleIdentity, rightIdentity].compactMap { $0 }.count
        guard boundSourceCount <= limits.maximumSources else {
            throw ThreePaneTableNewError.sourceCountExceeded(requested: boundSourceCount, maximum: limits.maximumSources)
        }
        try work.consume()

        guard request.delimiter.bytes.count >= 1 else {
            throw ThreePaneTableNewError.delimiterEmpty
        }
        guard request.delimiter.bytes.count <= limits.maximumDelimiterBytes else {
            throw ThreePaneTableNewError.delimiterTooLarge(maximumBytes: limits.maximumDelimiterBytes)
        }
        for byte in request.delimiter.bytes {
            try work.consume()
            guard byte != 0x00, byte != 0x0A, byte != 0x0D else {
                throw ThreePaneTableNewError.invalidDelimiterByte(value: Int(byte))
            }
        }
        // Authoritative delimiter/quote/newline settings: quote must be a single
        // valid scalar per DelimitedTableParser, must differ from a single-char
        // delimiter, and the trio must survive an authoritative parse probe.
        // Never renders spreadsheets; only validates settings.
        try validateFormat(request: request, work: &work)

        guard (0...limits.maximumRowCount).contains(request.declaredRowCount) else {
            throw ThreePaneTableNewError.rowLimitExceeded(maximumRows: limits.maximumRowCount)
        }
        guard (0...limits.maximumCellCount).contains(request.declaredCellCount) else {
            throw ThreePaneTableNewError.cellLimitExceeded(maximumCells: limits.maximumCellCount)
        }
        // Intentional asymmetry: rows>0 cells==0 passes, rows==0 cells>0 rejected.
        guard request.declaredRowCount > 0 || request.declaredCellCount == 0 else {
            throw ThreePaneTableNewError.inconsistentDeclaredCounts(
                declaredRows: request.declaredRowCount,
                declaredCells: request.declaredCellCount
            )
        }
        try work.consume()

        // Selection validated against declared counts (exact bounds for planning).
        try validateSelection(request.selection, declaredRows: request.declaredRowCount, declaredCells: request.declaredCellCount)
        try work.consume()

        try validateIdentity(leftIdentity, pane: .left, limits: limits, work: &work)
        if let middleIdentity {
            try validateIdentity(middleIdentity, pane: .middle, limits: limits, work: &work)
        }
        try validateIdentity(rightIdentity, pane: .right, limits: limits, work: &work)

        var combined = 0
        for identity in [leftIdentity, middleIdentity, rightIdentity].compactMap({ $0 }) {
            try work.consume()
            let (next, overflow) = combined.addingReportingOverflow(identity.byteSize)
            guard !overflow, next <= limits.maximumCombinedSourceBytes else {
                throw ThreePaneTableNewError.combinedSourcesTooLarge(maximumBytes: limits.maximumCombinedSourceBytes)
            }
            combined = next
        }

        var digests: [String: ThreePaneTableNewPane] = [:]
        for identity in [leftIdentity, middleIdentity, rightIdentity].compactMap({ $0 }) {
            try work.consume(identity.contentSHA256.count)
            let key = identity.contentSHA256.map { String(format: "%02x", Int($0)) }.joined()
            if digests[key] != nil {
                throw ThreePaneTableNewError.duplicateRevision(digestPrefix: threePaneTableNewDigestPrefix(identity.contentSHA256))
            }
            let pane: ThreePaneTableNewPane
            if identity.contentSHA256 == leftIdentity.contentSHA256 {
                pane = .left
            } else if let middle = middleIdentity, identity.contentSHA256 == middle.contentSHA256 {
                pane = .middle
            } else {
                pane = .right
            }
            digests[key] = pane
        }

        try work.checkCancellation()
        let leftPrefix = threePaneTableNewDigestPrefix(leftIdentity.contentSHA256)
        let middlePrefix = middleIdentity.map { threePaneTableNewDigestPrefix($0.contentSHA256) } ?? "empty"
        let rightPrefix = threePaneTableNewDigestPrefix(rightIdentity.contentSHA256)
        let delimiterHex = request.delimiter.bytes.map { String(format: "%02x", Int($0)) }.joined()
        let quoteToken: String
        if let quote = request.quote {
            quoteToken = "quote:\(quote.unicodeScalars.first?.value ?? 0)"
        } else {
            quoteToken = "quote:none"
        }
        let newlineToken = request.allowsNewlinesInQuotedCells ? "newlines:allow" : "newlines:forbid"
        let headerToken = String(
            format: "headers:%@-%@",
            request.headerVisibility == .visible ? "visible" : "hidden",
            request.headerLabels == .ordinal ? "ordinal" : "firstRecord"
        )
        let selectionToken: String
        switch request.selection {
        case .none:
            selectionToken = "selection:none"
        case .column(let index):
            selectionToken = "selection:column\(index)"
        case .cells(let anchor, let focus):
            selectionToken = "selection:cells\(anchor.rowIndex),\(anchor.columnIndex)-\(focus.rowIndex),\(focus.columnIndex)"
        }
        let featureToken = request.requiredFeatures.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: ",")
        let identifier =
            "three-pane-table-new left:\(leftPrefix) middle:\(middlePrefix) right:\(rightPrefix)"
            + " rows:\(request.declaredRowCount) cells:\(request.declaredCellCount) delimiter:\(delimiterHex)"
            + " \(quoteToken) \(newlineToken) \(headerToken) \(selectionToken)"
            + " orientation:\(request.orientation.rawValue) features:\(featureToken)"
            + " revision:\(request.datasetRevision) sources:\(boundSourceCount)"
            + " limits:\(limits.maximumSources)/\(limits.maximumSourceBytes)/\(limits.maximumCombinedSourceBytes)/\(limits.maximumPathUTF8Bytes)/\(limits.maximumDelimiterBytes)/\(limits.maximumRowCount)/\(limits.maximumCellCount)/\(limits.maximumWorkUnits)/\(limits.cancellationCheckInterval)"
            + " cores:\(request.capability.parserCoreName),\(request.capability.twoWayCoreName),\(request.capability.threeWayCoreName)"
        let receipt = ThreePaneTableNewReceipt(
            identifier: identifier,
            leftDigestPrefix: leftPrefix,
            middleDigestPrefix: middlePrefix,
            rightDigestPrefix: rightPrefix,
            declaredRowCount: request.declaredRowCount,
            declaredCellCount: request.declaredCellCount,
            delimiterByteCount: request.delimiter.bytes.count,
            orientation: request.orientation,
            headerVisibility: request.headerVisibility,
            headerLabels: request.headerLabels,
            allowsNewlinesInQuotedCells: request.allowsNewlinesInQuotedCells,
            datasetRevision: request.datasetRevision,
            sourceCount: boundSourceCount
        )
        return ThreePaneTableNewPlan(
            panes: sorted,
            delimiter: request.delimiter,
            quote: request.quote,
            allowsNewlinesInQuotedCells: request.allowsNewlinesInQuotedCells,
            headerVisibility: request.headerVisibility,
            headerLabels: request.headerLabels,
            selection: request.selection,
            requiredFeatures: request.requiredFeatures,
            datasetRevision: request.datasetRevision,
            orientation: request.orientation,
            capability: request.capability,
            receipt: receipt,
            executorContract: .planOnly,
            limits: limits,
            workPerformed: work.completed
        )
    }

    /// Authoritative delimiter/quote/newline validation against DelimitedTableParser rules.
    ///
    /// Quote intent: exactly one Unicode scalar other than NUL/CR/LF, matching
    /// `DelimitedTableParser.validatedScalar`. Delimiter intent: raw bytes that avoid
    /// 0x00/0x0A/0x0D; when those bytes decode as a single UTF-8 character the
    /// delimiter/quote pair must differ and both go through the authoritative probe.
    /// Multi-byte or non-UTF-8 delimiters cannot map to `Character`, so the probe
    /// substitutes comma to still authoritatively check quote/newline handling.
    private static func validateFormat(request: ThreePaneTableNewRequest, work: inout ThreePaneTableNewWork) throws {
        if let quote = request.quote {
            let scalars = quote.unicodeScalars
            guard scalars.count == 1, let scalar = scalars.first,
                scalar != "\0", scalar != "\r", scalar != "\n"
            else {
                throw ThreePaneTableNewError.invalidQuote
            }
            // Delimiter/quote must differ when the delimiter is that same single scalar.
            if let delimiterString = String(bytes: request.delimiter.bytes, encoding: .utf8),
                delimiterString.count == 1, delimiterString.first == quote
            {
                throw ThreePaneTableNewError.quoteMatchesDelimiter
            }
            try work.consume()
            // Authoritative probe: the trio must be accepted by DelimitedTableParser.
            // Multi-byte custom delimiters cannot map to Character; probe with comma
            // so quote/newline alone are still authoritatively checked.
            let delimiterChar: Character
            if let s = String(bytes: request.delimiter.bytes, encoding: .utf8),
                s.count == 1, let first = s.first
            {
                delimiterChar = first
            } else {
                delimiterChar = ","
            }
            let probeOptions = DelimitedTableParsingOptions(
                delimiter: delimiterChar,
                quote: quote,
                allowsNewlinesInQuotedCells: request.allowsNewlinesInQuotedCells,
                limits: .default
            )
            do {
                _ = try DelimitedTableParser.parse("", options: probeOptions)
            } catch let error as DelimitedTableParseError {
                switch error {
                case .invalidDelimiter:
                    throw ThreePaneTableNewError.invalidDelimiterByte(value: -1)
                case .invalidQuote:
                    throw ThreePaneTableNewError.invalidQuote
                case .delimiterMatchesQuote:
                    throw ThreePaneTableNewError.quoteMatchesDelimiter
                default:
                    break
                }
            }
            try work.consume()
        } else {
            try work.consume()
        }
    }

    private static func validateSelection(_ selection: TableWorkspaceSelection, declaredRows: Int, declaredCells: Int) throws {
        switch selection {
        case .none:
            return
        case .column(let index):
            guard index >= 0 else {
                throw ThreePaneTableNewError.selectionOutOfBounds
            }
            // Exact bounds: with zero declared cells no column can be selected;
            // otherwise the column must fall within the declared cell budget.
            if declaredCells == 0 {
                throw ThreePaneTableNewError.selectionOutOfBounds
            }
            guard index < declaredCells else {
                throw ThreePaneTableNewError.selectionOutOfBounds
            }
        case .cells(let anchor, let focus):
            for address in [anchor, focus] {
                guard address.rowIndex >= 0, address.columnIndex >= 0 else {
                    throw ThreePaneTableNewError.selectionOutOfBounds
                }
            }
            if declaredRows == 0 || declaredCells == 0 {
                throw ThreePaneTableNewError.selectionOutOfBounds
            }
            guard anchor.rowIndex < declaredRows, focus.rowIndex < declaredRows,
                anchor.columnIndex < declaredCells, focus.columnIndex < declaredCells
            else {
                throw ThreePaneTableNewError.selectionOutOfBounds
            }
        }
    }

    private static func validateIdentity(
        _ identity: ThreePaneTableNewFileIdentity,
        pane: ThreePaneTableNewPane,
        limits: ThreePaneTableNewLimits,
        work: inout ThreePaneTableNewWork
    ) throws {
        guard !identity.canonicalPath.isEmpty, !identity.canonicalPath.contains("\0") else {
            throw ThreePaneTableNewError.invalidPath(pane)
        }
        // Validate path length before this function's meters: over-long paths throw
        // pathTooLarge rather than consuming path-scaled work first. Earlier stages
        // may still throw workExceeded first under a tiny work budget.
        let pathCount = identity.canonicalPath.utf8.count
        guard pathCount <= limits.maximumPathUTF8Bytes else {
            throw ThreePaneTableNewError.pathTooLarge(pane: pane, maximumUTF8Bytes: limits.maximumPathUTF8Bytes)
        }
        try work.consume(pathCount / 512 + 1)
        guard (0...limits.maximumSourceBytes).contains(identity.byteSize) else {
            throw ThreePaneTableNewError.sourceTooLarge(pane: pane, maximumBytes: limits.maximumSourceBytes)
        }
        guard identity.contentSHA256.count == 32, identity.contentSHA256.contains(where: { $0 != 0 }) else {
            throw ThreePaneTableNewError.invalidDigest(pane: pane, actualByteCount: identity.contentSHA256.count)
        }
        try work.consume()
    }

    private init(
        panes: [ThreePaneTableNewRequestPane],
        delimiter: ThreePaneTableNewDelimiter,
        quote: Character?,
        allowsNewlinesInQuotedCells: Bool,
        headerVisibility: TableWorkspaceHeaderVisibility,
        headerLabels: TableWorkspaceHeaderLabels,
        selection: TableWorkspaceSelection,
        requiredFeatures: Set<ThreePaneTableNewFeature>,
        datasetRevision: UInt64,
        orientation: ThreePaneTableNewOrientation,
        capability: ThreePaneTableNewCapabilityRequirement,
        receipt: ThreePaneTableNewReceipt,
        executorContract: ThreePaneTableNewExecutorContract,
        limits: ThreePaneTableNewLimits,
        workPerformed: Int
    ) {
        self.panes = panes
        self.delimiter = delimiter
        self.quote = quote
        self.allowsNewlinesInQuotedCells = allowsNewlinesInQuotedCells
        self.headerVisibility = headerVisibility
        self.headerLabels = headerLabels
        self.selection = selection
        self.requiredFeatures = requiredFeatures
        self.datasetRevision = datasetRevision
        self.orientation = orientation
        self.capability = capability
        self.receipt = receipt
        self.executorContract = executorContract
        self.limits = limits
        self.workPerformed = workPerformed
    }
}

extension ThreePaneTableNewPlan: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ThreePaneTableNewPlan(\(receipt.identifier) work:\(workPerformed))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "receipt": receipt.identifier,
                "declaredRowCount": receipt.declaredRowCount,
                "declaredCellCount": receipt.declaredCellCount,
                "workPerformed": workPerformed
            ],
            displayStyle: .struct
        )
    }
}

public enum ThreePaneTableNewError: Error, Equatable, Hashable, Sendable {
    case cancelled
    case invalidLimit(ThreePaneTableNewLimit, value: Int)
    case invalidPaneCount(expected: Int, actual: Int)
    case duplicatePane(ThreePaneTableNewPane)
    case missingPane(ThreePaneTableNewPane)
    case unexpectedEmptyPane(ThreePaneTableNewPane)
    case emptyMiddleUnsupported
    case unsupportedCapability(name: String)
    case unsupportedFeature(name: String)
    case sourceCountExceeded(requested: Int, maximum: Int)
    case invalidPath(ThreePaneTableNewPane)
    case pathTooLarge(pane: ThreePaneTableNewPane, maximumUTF8Bytes: Int)
    case sourceTooLarge(pane: ThreePaneTableNewPane, maximumBytes: Int)
    case combinedSourcesTooLarge(maximumBytes: Int)
    case invalidDigest(pane: ThreePaneTableNewPane, actualByteCount: Int)
    case duplicateRevision(digestPrefix: String)
    case delimiterEmpty
    case delimiterTooLarge(maximumBytes: Int)
    case invalidDelimiterByte(value: Int)
    case invalidQuote
    case quoteMatchesDelimiter
    case rowLimitExceeded(maximumRows: Int)
    case cellLimitExceeded(maximumCells: Int)
    case inconsistentDeclaredCounts(declaredRows: Int, declaredCells: Int)
    case selectionOutOfBounds
    case receiptMismatch
    case staleDatasetRevision(expected: UInt64, actual: UInt64)
    case workExceeded(maximumWorkUnits: Int)
}

extension ThreePaneTableNewError: LocalizedError, CustomDebugStringConvertible, CustomReflectable {
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Three-pane table creation planning was cancelled."
        case .invalidLimit(let limit, let value):
            "Invalid three-pane table creation limit \(limit.rawValue): \(value)."
        case .invalidPaneCount(let expected, let actual):
            "Three-pane table creation requires \(expected) slots, not \(actual)."
        case .duplicatePane(let pane):
            "Three-pane table creation repeats the \(pane.rawValue) pane."
        case .missingPane(let pane):
            "Three-pane table creation is missing the \(pane.rawValue) pane."
        case .unexpectedEmptyPane(let pane):
            "Three-pane table creation requires a file in the \(pane.rawValue) pane."
        case .emptyMiddleUnsupported:
            "Three-pane table creation capability forbids an empty middle pane."
        case .unsupportedCapability:
            "Three-pane table creation capability names an unsupported table core."
        case .unsupportedFeature(let name):
            "Three-pane table creation requires unsupported feature \(name)."
        case .sourceCountExceeded(let requested, let maximum):
            "Three-pane table creation binds \(requested) sources, exceeding the \(maximum)-source limit."
        case .invalidPath(let pane):
            "Three-pane table creation \(pane.rawValue) source has an invalid canonical identity."
        case .pathTooLarge(let pane, let maximum):
            "Three-pane table creation \(pane.rawValue) path exceeds \(maximum) UTF-8 bytes."
        case .sourceTooLarge(let pane, let maximum):
            "Three-pane table creation \(pane.rawValue) source exceeds \(maximum) bytes."
        case .combinedSourcesTooLarge(let maximum):
            "Three-pane table creation sources exceed \(maximum) combined bytes."
        case .invalidDigest(let pane, let actual):
            "Three-pane table creation \(pane.rawValue) revision digest has \(actual) bytes, not 32."
        case .duplicateRevision(let digestPrefix):
            "Three-pane table creation revisions collide on digest \(digestPrefix)."
        case .delimiterEmpty:
            "Three-pane table creation delimiter is empty."
        case .delimiterTooLarge(let maximum):
            "Three-pane table creation delimiter exceeds \(maximum) bytes."
        case .invalidDelimiterByte(let value):
            "Three-pane table creation delimiter rejects byte \(value)."
        case .invalidQuote:
            "Three-pane table creation quote must be one Unicode scalar other than NUL, carriage return, or line feed."
        case .quoteMatchesDelimiter:
            "Three-pane table creation delimiter and quote must differ."
        case .rowLimitExceeded(let maximum):
            "Three-pane table creation exceeds the \(maximum)-row limit."
        case .cellLimitExceeded(let maximum):
            "Three-pane table creation exceeds the \(maximum)-cell limit."
        case .inconsistentDeclaredCounts(let rows, let cells):
            "Three-pane table creation declares \(rows) rows with \(cells) cells."
        case .selectionOutOfBounds:
            "Three-pane table creation selection is outside the declared rows and cells."
        case .receiptMismatch:
            "Three-pane table creation receipt does not match the plan."
        case .staleDatasetRevision(let expected, let actual):
            "Three-pane table creation expects dataset revision \(expected), not \(actual)."
        case .workExceeded(let maximum):
            "Three-pane table creation planning exceeds the \(maximum)-unit work limit."
        }
    }

    public var debugDescription: String {
        errorDescription ?? "Three-pane table creation failed."
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["description": debugDescription], displayStyle: .enum)
    }
}

private struct ThreePaneTableNewWork {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: ThreePaneTableNewPlan.CancellationCheck
    private(set) var completed = 0

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0 else {
            try checkCancellation()
            throw ThreePaneTableNewError.workExceeded(maximumWorkUnits: maximum)
        }
        guard amount <= maximum, completed <= maximum - amount else {
            try checkCancellation()
            throw ThreePaneTableNewError.workExceeded(maximumWorkUnits: maximum)
        }
        let previousBucket = completed / cancellationCheckInterval
        completed += amount
        if completed / cancellationCheckInterval != previousBucket {
            try checkCancellation()
        }
    }

    /// Cancellation contract: `CancellationError` (from either `Task.checkCancellation`
    /// or the injected `cancellationCheck`) maps to `.cancelled`. Any other custom
    /// error from `cancellationCheck` propagates unchanged so callers can surface
    /// domain-specific aborts without misreporting them as cancellation.
    func checkCancellation() throws {
        do {
            try Task.checkCancellation()
            try cancellationCheck()
        } catch is CancellationError {
            throw ThreePaneTableNewError.cancelled
        }
    }
}

private func threePaneTableNewDigestPrefix(_ digest: [UInt8]) -> String {
    digest.prefix(8).map { String(format: "%02x", Int($0)) }.joined()
}
