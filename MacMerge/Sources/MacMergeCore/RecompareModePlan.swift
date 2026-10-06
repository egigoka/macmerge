import CXDiff
import Foundation

/// Explicit modes available to Recompare As. Folder comparison is intentionally excluded.
public enum RecompareMode: String, CaseIterable, Equatable, Hashable, Sendable {
    case text
    case table
    case binary
    case image
    case webpage
    case archive

    public init?(comparisonMode: ComparisonProject.Mode) {
        switch comparisonMode {
        case .text: self = .text
        case .table: self = .table
        case .binary: self = .binary
        case .image: self = .image
        case .webpage: self = .webpage
        case .automatic, .folder: return nil
        }
    }

    public var comparisonMode: ComparisonProject.Mode? {
        switch self {
        case .text: .text
        case .table: .table
        case .binary: .binary
        case .image: .image
        case .webpage: .webpage
        case .archive: nil
        }
    }
}

/// Origin of one already-open source. This is capability metadata, not materialized content.
public enum RecompareModeSourceKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case localFile
    case scratchpad
    case clipboardText
    case clipboardBinary
    case remoteWebPage
}

public struct RecompareModeSourceSetIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct RecompareModeSourceIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct RecompareModeSourceRevision: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// Exact owner-issued identity and revision of one source at one pane position.
///
/// An owner must never reuse a revision for different source content. Pane position is independent
/// of source identity, so swapping panes cannot silently exchange source ownership.
public struct RecompareModeSourceBinding: Equatable, Hashable, Sendable {
    public let side: ComparisonOpenSidePosition
    public let identity: RecompareModeSourceIdentity
    public let revision: RecompareModeSourceRevision
    public let kind: RecompareModeSourceKind

    public init(
        side: ComparisonOpenSidePosition,
        identity: RecompareModeSourceIdentity,
        revision: RecompareModeSourceRevision,
        kind: RecompareModeSourceKind
    ) {
        self.side = side
        self.identity = identity
        self.revision = revision
        self.kind = kind
    }
}

/// Immutable source-set snapshot supplied by the owner that can later revalidate the plan.
/// `generation` must change whenever bindings, source revisions, or source kinds change.
public struct RecompareModeSourceSnapshot: Equatable, Hashable, Sendable {
    public let identity: RecompareModeSourceSetIdentity
    public let generation: UInt64
    public let sources: [RecompareModeSourceBinding]

    public init(
        identity: RecompareModeSourceSetIdentity,
        generation: UInt64,
        sources: [RecompareModeSourceBinding]
    ) {
        self.identity = identity
        self.generation = generation
        self.sources = sources
    }

    public var reference: RecompareModeSourceSnapshotReference {
        RecompareModeSourceSnapshotReference(identity: identity, generation: generation)
    }
}

public struct RecompareModeSourceSnapshotReference: Equatable, Hashable, Sendable {
    public let identity: RecompareModeSourceSetIdentity
    public let generation: UInt64

    public init(identity: RecompareModeSourceSetIdentity, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }

    public init(_ snapshot: RecompareModeSourceSnapshot) {
        identity = snapshot.identity
        generation = snapshot.generation
    }
}

/// Exact engine option family required by each target mode. There is deliberately no untyped or
/// default case: callers choose concrete settings before planning.
public enum RecompareModeOptions: Equatable, Hashable, Sendable {
    case text(twoWay: LineDiffOptions, threeWay: ThreeWayTextMergeOptions)
    case table(
        parsing: DelimitedTableParsingOptions,
        twoWay: TableComparisonOptions,
        threeWay: ThreeWayTableComparisonOptions
    )
    case binary(twoWay: BinaryComparisonOptions, threeWay: ThreeWayBinaryComparisonOptions)
    case image(loading: ImageComparisonLimits, comparison: ImageComparisonOptions)
    case webpage(twoWay: WebPageComparisonOptions, threeWay: ThreeWayWebPageComparisonOptions)
    case archive(limits: ArchiveLimits)

    public var mode: RecompareMode {
        switch self {
        case .text: .text
        case .table: .table
        case .binary: .binary
        case .image: .image
        case .webpage: .webpage
        case .archive: .archive
        }
    }

    /// Engine option models predate `Hashable`. Equality remains exact; mode-discriminated hashing
    /// is intentionally coarse but obeys the `Hashable` contract without lossy option projection.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(mode)
    }
}

private enum RecompareModeEngineCeilings {
    static let maximumTwoWayInputBytes = Int(MMX_MAX_INPUT_SIZE)
    static let maximumLineCount = Int(MMX_MAX_LINE_COUNT)
    static let maximumThreeWayInputBytes = 64 * 1_024 * 1_024
    static let maximumThreeWayOutputBytes = 192 * 1_024 * 1_024
    static let maximumThreeWayOutputLines = 3 * 1_024 * 1_024
    static let maximumThreeWayRegions = maximumThreeWayOutputLines + 1
    static let maximumTableRows = 1_048_576
    static let maximumTableColumnsPerRow = 16_384
    static let maximumTableCells = 1_048_576
    static let maximumTableCellBytes = 16 * 1_024 * 1_024
    static let maximumComparedTableItems = 2_097_152
    static let maximumThreeWayTableItems = 3 * 1_048_576
    static let maximumExactEditDistance = 2_048
    static let maximumTwoWayAlignmentWork = 16 * 1_024 * 1_024
    static let maximumThreeWayAlignmentWork = 32 * 1_024 * 1_024
    static let maximumImageDimension = 16_384
    static let maximumImagePixels = 16 * 1_024 * 1_024
    static let maximumImageDecodedBytes = 128 * 1_024 * 1_024
    static let maximumImageRegions = 250_000
    static let maximumImageQueuedPixels = 262_144
    static let maximumCollectionItems = 16 * 1_024 * 1_024
    static let maximumEngineWorkUnits = 512 * 1_024 * 1_024
    static let maximumRegularExpressionUTF8Bytes = 4_096
}

public enum RecompareModePlanLimit: String, CaseIterable, Equatable, Hashable, Sendable {
    case sourceCount
    case optionItemCount
    case optionStringUTF8Bytes
    case totalOptionStringUTF8Bytes
    case declaredWorkUnits
    case planningWorkUnits
    case cancellationCheckInterval
}

public struct RecompareModePlanLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumSourceCount = 3
    public static let hardMaximumOptionItemCount = 4_096
    public static let hardMaximumOptionStringUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalOptionStringUTF8Bytes = 4 * 1_024 * 1_024
    public static let hardMaximumDeclaredWorkUnits: UInt64 = 2 * 1_024 * 1_024 * 1_024
    public static let hardMaximumPlanningWorkUnits = 16 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = RecompareModePlanLimits()

    public let maximumSourceCount: Int
    public let maximumOptionItemCount: Int
    public let maximumOptionStringUTF8Bytes: Int
    public let maximumTotalOptionStringUTF8Bytes: Int
    public let maximumDeclaredWorkUnits: UInt64
    public let maximumPlanningWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumSourceCount: Int = 3,
        maximumOptionItemCount: Int = 4_096,
        maximumOptionStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalOptionStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumDeclaredWorkUnits: UInt64 = 1_024 * 1_024 * 1_024,
        maximumPlanningWorkUnits: Int = 8 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 4_096
    ) {
        self.maximumSourceCount = maximumSourceCount
        self.maximumOptionItemCount = maximumOptionItemCount
        self.maximumOptionStringUTF8Bytes = maximumOptionStringUTF8Bytes
        self.maximumTotalOptionStringUTF8Bytes = maximumTotalOptionStringUTF8Bytes
        self.maximumDeclaredWorkUnits = maximumDeclaredWorkUnits
        self.maximumPlanningWorkUnits = maximumPlanningWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

/// Mode-level capability. Cross-source constraints, such as clipboard pairing, are enforced by the
/// planner because they cannot be represented as independent kind membership.
public struct RecompareModeCapability: Equatable, Hashable, Sendable {
    public let mode: RecompareMode
    public let supportedSourceCounts: Set<Int>
    public let supportedSourceKinds: Set<RecompareModeSourceKind>

    public init(
        mode: RecompareMode,
        supportedSourceCounts: Set<Int>,
        supportedSourceKinds: Set<RecompareModeSourceKind>
    ) {
        self.mode = mode
        self.supportedSourceCounts = supportedSourceCounts
        self.supportedSourceKinds = supportedSourceKinds
    }

    public func supports(sourceCount: Int, kind: RecompareModeSourceKind) -> Bool {
        guard supportedSourceCounts.contains(sourceCount), supportedSourceKinds.contains(kind) else {
            return false
        }
        if kind == .clipboardText || kind == .clipboardBinary {
            return sourceCount == 2
        }
        return true
    }
}

public struct RecompareModeRequest: Equatable, Hashable, Sendable {
    public let sources: RecompareModeSourceSnapshot
    public let currentMode: RecompareMode
    public let targetMode: RecompareMode
    public let options: RecompareModeOptions
    /// Conservative caller estimate consumed by a future executor, not by this planner.
    public let declaredWorkUnits: UInt64
    public let limits: RecompareModePlanLimits

    public init(
        sources: RecompareModeSourceSnapshot,
        currentMode: RecompareMode,
        targetMode: RecompareMode,
        options: RecompareModeOptions,
        declaredWorkUnits: UInt64,
        limits: RecompareModePlanLimits = .default
    ) {
        self.sources = sources
        self.currentMode = currentMode
        self.targetMode = targetMode
        self.options = options
        self.declaredWorkUnits = declaredWorkUnits
        self.limits = limits
    }
}

/// Deterministic, complete planning receipt. No random identifier, clock, hash seed, filesystem
/// result, or UI state is introduced by planning.
public struct RecompareModePlanReceipt: Equatable, Hashable, Sendable {
    public let sourceReference: RecompareModeSourceSnapshotReference
    public let sources: [RecompareModeSourceBinding]
    public let currentMode: RecompareMode
    public let targetMode: RecompareMode
    public let options: RecompareModeOptions
    public let declaredWorkUnits: UInt64
    public let planningWorkUnits: Int
    public let limits: RecompareModePlanLimits

    fileprivate init(
        sourceReference: RecompareModeSourceSnapshotReference,
        sources: [RecompareModeSourceBinding],
        currentMode: RecompareMode,
        targetMode: RecompareMode,
        options: RecompareModeOptions,
        declaredWorkUnits: UInt64,
        planningWorkUnits: Int,
        limits: RecompareModePlanLimits
    ) {
        self.sourceReference = sourceReference
        self.sources = sources
        self.currentMode = currentMode
        self.targetMode = targetMode
        self.options = options
        self.declaredWorkUnits = declaredWorkUnits
        self.planningWorkUnits = planningWorkUnits
        self.limits = limits
    }

    public var isThreeWay: Bool { sources.count == 3 }

    public func source(_ side: ComparisonOpenSidePosition) -> RecompareModeSourceBinding? {
        sources.first { $0.side == side }
    }

    public func requireCurrentSources(_ snapshot: RecompareModeSourceSnapshot) throws {
        try RecompareModePlanner.validate(snapshot, against: self)
    }

    public func isCurrent(for snapshot: RecompareModeSourceSnapshot) throws -> Bool {
        do {
            try requireCurrentSources(snapshot)
            return true
        } catch RecompareModePlanningError.sourceSetIdentityChanged,
            RecompareModePlanningError.staleSourceGeneration,
            RecompareModePlanningError.sourceCountChanged,
            RecompareModePlanningError.sourceIdentityChanged,
            RecompareModePlanningError.sourceRevisionChanged,
            RecompareModePlanningError.sourceKindChanged
        {
            return false
        }
    }
}

/// UI-independent routing plan. It contains no parser, executor, materialized source, or side effect.
public struct RecompareModePlan: Equatable, Hashable, Sendable {
    public let receipt: RecompareModePlanReceipt

    fileprivate init(receipt: RecompareModePlanReceipt) {
        self.receipt = receipt
    }

    public var sourceReference: RecompareModeSourceSnapshotReference { receipt.sourceReference }
    public var sources: [RecompareModeSourceBinding] { receipt.sources }
    public var currentMode: RecompareMode { receipt.currentMode }
    public var targetMode: RecompareMode { receipt.targetMode }
    public var options: RecompareModeOptions { receipt.options }
    public var declaredWorkUnits: UInt64 { receipt.declaredWorkUnits }
    public var planningWorkUnits: Int { receipt.planningWorkUnits }
    public var limits: RecompareModePlanLimits { receipt.limits }
    public var isThreeWay: Bool { receipt.isThreeWay }

    public func source(_ side: ComparisonOpenSidePosition) -> RecompareModeSourceBinding? {
        receipt.source(side)
    }

    public func requireCurrentSources(_ snapshot: RecompareModeSourceSnapshot) throws {
        try receipt.requireCurrentSources(snapshot)
    }

    public func isCurrent(for snapshot: RecompareModeSourceSnapshot) throws -> Bool {
        try receipt.isCurrent(for: snapshot)
    }
}

public enum RecompareModePlanningError: Error, Equatable, Hashable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(RecompareModePlanLimit)
    case invalidSourceCount(Int)
    case sourceCountLimitExceeded(maximum: Int)
    case duplicateSide(ComparisonOpenSidePosition)
    case invalidSideSet([ComparisonOpenSidePosition])
    case duplicateSourceIdentity(
        RecompareModeSourceIdentity,
        first: ComparisonOpenSidePosition,
        second: ComparisonOpenSidePosition
    )
    case sourceSetIdentityChanged(
        expected: RecompareModeSourceSetIdentity,
        actual: RecompareModeSourceSetIdentity
    )
    case staleSourceGeneration(expected: UInt64, actual: UInt64)
    case sourceCountChanged(expected: Int, actual: Int)
    case sourceIdentityChanged(
        side: ComparisonOpenSidePosition,
        expected: RecompareModeSourceIdentity,
        actual: RecompareModeSourceIdentity
    )
    case sourceRevisionChanged(
        side: ComparisonOpenSidePosition,
        expected: RecompareModeSourceRevision,
        actual: RecompareModeSourceRevision
    )
    case sourceKindChanged(
        side: ComparisonOpenSidePosition,
        expected: RecompareModeSourceKind,
        actual: RecompareModeSourceKind
    )
    case unsupportedSourceCount(mode: RecompareMode, count: Int)
    case unsupportedSourceKind(
        side: ComparisonOpenSidePosition,
        mode: RecompareMode,
        kind: RecompareModeSourceKind
    )
    case clipboardSourcesRequireMatchingPair
    case modeOptionsMismatch(expected: RecompareMode, actual: RecompareMode)
    case invalidOption(mode: RecompareMode, name: String)
    case tooManyOptionItems(maximum: Int)
    case optionStringTooLarge(name: String, maximumUTF8Bytes: Int)
    case totalOptionStringsTooLarge(maximumUTF8Bytes: Int)
    case declaredWorkLimitExceeded(maximumWorkUnits: UInt64)
    case planningWorkLimitExceeded(maximumWorkUnits: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Recompare mode planning was cancelled."
        case .invalidLimit(let limit):
            "Recompare mode plan limit is invalid: \(limit.rawValue)."
        case .invalidSourceCount(let count):
            "Recompare mode planning requires two or three sources, not \(count)."
        case .sourceCountLimitExceeded(let maximum):
            "Recompare mode sources exceed the \(maximum)-source limit."
        case .duplicateSide(let side):
            "Recompare mode sources contain duplicate \(side.rawValue) sides."
        case .invalidSideSet(let sides):
            "Recompare mode source sides are invalid: \(sides.map(\.rawValue).joined(separator: ", "))."
        case .duplicateSourceIdentity(_, let first, let second):
            "Recompare mode source identity is shared by \(first.rawValue) and \(second.rawValue)."
        case .sourceSetIdentityChanged:
            "Recompare mode plan belongs to another source set."
        case .staleSourceGeneration(let expected, let actual):
            "Recompare mode plan expects source generation \(expected), not \(actual)."
        case .sourceCountChanged(let expected, let actual):
            "Recompare mode source count changed from \(expected) to \(actual) without a generation change."
        case .sourceIdentityChanged(let side, _, _):
            "Recompare mode \(side.rawValue) source identity changed without a generation change."
        case .sourceRevisionChanged(let side, _, _):
            "Recompare mode \(side.rawValue) source revision changed without a generation change."
        case .sourceKindChanged(let side, _, _):
            "Recompare mode \(side.rawValue) source kind changed without a generation change."
        case .unsupportedSourceCount(let mode, let count):
            "Recompare as \(mode.rawValue) does not support \(count) sources."
        case .unsupportedSourceKind(let side, let mode, let kind):
            "Recompare as \(mode.rawValue) does not support \(kind.rawValue) on the \(side.rawValue) side."
        case .clipboardSourcesRequireMatchingPair:
            "Clipboard recompare requires exactly two matching clipboard source kinds."
        case .modeOptionsMismatch(let expected, let actual):
            "Recompare as \(expected.rawValue) requires \(expected.rawValue) options, not \(actual.rawValue) options."
        case .invalidOption(let mode, let name):
            "Recompare as \(mode.rawValue) has an invalid option: \(name)."
        case .tooManyOptionItems(let maximum):
            "Recompare mode options exceed the \(maximum)-item limit."
        case .optionStringTooLarge(let name, let maximum):
            "Recompare mode option \(name) exceeds \(maximum) UTF-8 bytes."
        case .totalOptionStringsTooLarge(let maximum):
            "Recompare mode option strings exceed \(maximum) combined UTF-8 bytes."
        case .declaredWorkLimitExceeded(let maximum):
            "Recompare execution estimate exceeds the \(maximum)-unit work limit."
        case .planningWorkLimitExceeded(let maximum):
            "Recompare mode planning exceeds the \(maximum)-unit work limit."
        }
    }
}

public enum RecompareModePlanner: Sendable {
    public static func capability(for mode: RecompareMode) -> RecompareModeCapability {
        let localAndTextual: Set<RecompareModeSourceKind> = [
            .localFile, .scratchpad, .remoteWebPage
        ]
        switch mode {
        case .text:
            return RecompareModeCapability(
                mode: mode,
                supportedSourceCounts: [2, 3],
                supportedSourceKinds: [.localFile, .scratchpad, .clipboardText]
            )
        case .table:
            return RecompareModeCapability(
                mode: mode,
                supportedSourceCounts: [2, 3],
                supportedSourceKinds: [.localFile, .scratchpad]
            )
        case .binary:
            return RecompareModeCapability(
                mode: mode,
                supportedSourceCounts: [2, 3],
                supportedSourceKinds: [.localFile, .clipboardBinary]
            )
        case .image:
            return RecompareModeCapability(
                mode: mode,
                supportedSourceCounts: [2, 3],
                supportedSourceKinds: [.localFile]
            )
        case .webpage:
            return RecompareModeCapability(
                mode: mode,
                supportedSourceCounts: [2, 3],
                supportedSourceKinds: localAndTextual
            )
        case .archive:
            return RecompareModeCapability(
                mode: mode,
                supportedSourceCounts: [2],
                supportedSourceKinds: [.localFile]
            )
        }
    }

    /// Validates immutable metadata and settings only. No source is opened, decoded, parsed, or run.
    public static func plan(
        _ request: RecompareModeRequest,
        expecting expectedSources: RecompareModeSourceSnapshotReference? = nil
    ) throws -> RecompareModePlan {
        do {
            try Task.checkCancellation()
            if let expectedSources {
                try validateReference(request.sources.reference, expected: expectedSources)
            }
            try validate(request.limits)
            var work = RecompareModePlanningWork(limits: request.limits)
            let sources = try canonicalSources(
                request.sources.sources,
                limits: request.limits,
                work: &work
            )
            guard request.declaredWorkUnits <= request.limits.maximumDeclaredWorkUnits else {
                throw RecompareModePlanningError.declaredWorkLimitExceeded(
                    maximumWorkUnits: request.limits.maximumDeclaredWorkUnits
                )
            }
            guard request.options.mode == request.targetMode else {
                throw RecompareModePlanningError.modeOptionsMismatch(
                    expected: request.targetMode,
                    actual: request.options.mode
                )
            }
            try validateCapability(mode: request.currentMode, sources: sources)
            try validateCapability(mode: request.targetMode, sources: sources)
            var optionBudget = RecompareModeOptionBudget(limits: request.limits)
            try validate(
                request.options,
                isThreeWay: sources.count == 3,
                optionBudget: &optionBudget,
                work: &work
            )
            try Task.checkCancellation()

            let receipt = RecompareModePlanReceipt(
                sourceReference: request.sources.reference,
                sources: sources,
                currentMode: request.currentMode,
                targetMode: request.targetMode,
                options: request.options,
                declaredWorkUnits: request.declaredWorkUnits,
                planningWorkUnits: work.consumed,
                limits: request.limits
            )
            return RecompareModePlan(receipt: receipt)
        } catch is CancellationError {
            throw RecompareModePlanningError.cancelled
        }
    }

    public static func validate(
        _ snapshot: RecompareModeSourceSnapshot,
        against receipt: RecompareModePlanReceipt
    ) throws {
        do {
            try Task.checkCancellation()
            try validate(receipt.limits)
            try validateReference(snapshot.reference, expected: receipt.sourceReference)
            guard receipt.sources.count == snapshot.sources.count else {
                throw RecompareModePlanningError.sourceCountChanged(
                    expected: receipt.sources.count,
                    actual: snapshot.sources.count
                )
            }
            var work = RecompareModePlanningWork(limits: receipt.limits)
            let actual = try canonicalSources(
                snapshot.sources,
                limits: receipt.limits,
                work: &work
            )
            for (expectedSource, actualSource) in zip(receipt.sources, actual) {
                guard expectedSource.identity == actualSource.identity else {
                    throw RecompareModePlanningError.sourceIdentityChanged(
                        side: expectedSource.side,
                        expected: expectedSource.identity,
                        actual: actualSource.identity
                    )
                }
                guard expectedSource.revision == actualSource.revision else {
                    throw RecompareModePlanningError.sourceRevisionChanged(
                        side: expectedSource.side,
                        expected: expectedSource.revision,
                        actual: actualSource.revision
                    )
                }
                guard expectedSource.kind == actualSource.kind else {
                    throw RecompareModePlanningError.sourceKindChanged(
                        side: expectedSource.side,
                        expected: expectedSource.kind,
                        actual: actualSource.kind
                    )
                }
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            throw RecompareModePlanningError.cancelled
        }
    }

    private static func validateReference(
        _ actual: RecompareModeSourceSnapshotReference,
        expected: RecompareModeSourceSnapshotReference
    ) throws {
        guard actual.identity == expected.identity else {
            throw RecompareModePlanningError.sourceSetIdentityChanged(
                expected: expected.identity,
                actual: actual.identity
            )
        }
        guard actual.generation == expected.generation else {
            throw RecompareModePlanningError.staleSourceGeneration(
                expected: expected.generation,
                actual: actual.generation
            )
        }
    }

    private static func canonicalSources(
        _ sources: [RecompareModeSourceBinding],
        limits: RecompareModePlanLimits,
        work: inout RecompareModePlanningWork
    ) throws -> [RecompareModeSourceBinding] {
        guard sources.count == 2 || sources.count == 3 else {
            throw RecompareModePlanningError.invalidSourceCount(sources.count)
        }
        guard sources.count <= limits.maximumSourceCount else {
            throw RecompareModePlanningError.sourceCountLimitExceeded(
                maximum: limits.maximumSourceCount
            )
        }

        var bySide: [ComparisonOpenSidePosition: RecompareModeSourceBinding] = [:]
        var sidesByIdentity: [RecompareModeSourceIdentity: ComparisonOpenSidePosition] = [:]
        for source in sources {
            try work.charge(1)
            guard bySide.updateValue(source, forKey: source.side) == nil else {
                throw RecompareModePlanningError.duplicateSide(source.side)
            }
            if let first = sidesByIdentity.updateValue(source.side, forKey: source.identity) {
                throw RecompareModePlanningError.duplicateSourceIdentity(
                    source.identity,
                    first: first,
                    second: source.side
                )
            }
        }

        let order: [ComparisonOpenSidePosition] =
            sources.count == 2 ? [.left, .right] : [.left, .middle, .right]
        guard order.allSatisfy({ bySide[$0] != nil }) else {
            throw RecompareModePlanningError.invalidSideSet(
                sources.map(\.side).sorted { sideOrder($0) < sideOrder($1) }
            )
        }
        return order.compactMap { bySide[$0] }
    }

    private static func sideOrder(_ side: ComparisonOpenSidePosition) -> Int {
        switch side {
        case .left: 0
        case .middle: 1
        case .right: 2
        }
    }

    private static func validateCapability(
        mode: RecompareMode,
        sources: [RecompareModeSourceBinding]
    ) throws {
        let capability = capability(for: mode)
        guard capability.supportedSourceCounts.contains(sources.count) else {
            throw RecompareModePlanningError.unsupportedSourceCount(
                mode: mode,
                count: sources.count
            )
        }

        let clipboardSources = sources.filter {
            $0.kind == .clipboardText || $0.kind == .clipboardBinary
        }
        if !clipboardSources.isEmpty {
            guard sources.count == 2,
                clipboardSources.count == 2,
                clipboardSources[0].kind == clipboardSources[1].kind
            else {
                throw RecompareModePlanningError.clipboardSourcesRequireMatchingPair
            }
        }

        for source in sources where !capability.supportedSourceKinds.contains(source.kind) {
            throw RecompareModePlanningError.unsupportedSourceKind(
                side: source.side,
                mode: mode,
                kind: source.kind
            )
        }
    }

    private static func validate(_ limits: RecompareModePlanLimits) throws {
        guard limits.maximumSourceCount >= 2,
            limits.maximumSourceCount <= RecompareModePlanLimits.hardMaximumSourceCount
        else {
            throw RecompareModePlanningError.invalidLimit(.sourceCount)
        }
        guard limits.maximumOptionItemCount >= 0,
            limits.maximumOptionItemCount <= RecompareModePlanLimits.hardMaximumOptionItemCount
        else {
            throw RecompareModePlanningError.invalidLimit(.optionItemCount)
        }
        guard limits.maximumOptionStringUTF8Bytes >= 0,
            limits.maximumOptionStringUTF8Bytes
                <= RecompareModePlanLimits.hardMaximumOptionStringUTF8Bytes
        else {
            throw RecompareModePlanningError.invalidLimit(.optionStringUTF8Bytes)
        }
        guard limits.maximumTotalOptionStringUTF8Bytes >= 0,
            limits.maximumTotalOptionStringUTF8Bytes
                <= RecompareModePlanLimits.hardMaximumTotalOptionStringUTF8Bytes
        else {
            throw RecompareModePlanningError.invalidLimit(.totalOptionStringUTF8Bytes)
        }
        guard
            limits.maximumDeclaredWorkUnits
                <= RecompareModePlanLimits.hardMaximumDeclaredWorkUnits
        else {
            throw RecompareModePlanningError.invalidLimit(.declaredWorkUnits)
        }
        guard limits.maximumPlanningWorkUnits >= 0,
            limits.maximumPlanningWorkUnits
                <= RecompareModePlanLimits.hardMaximumPlanningWorkUnits
        else {
            throw RecompareModePlanningError.invalidLimit(.planningWorkUnits)
        }
        guard limits.cancellationCheckInterval > 0,
            limits.cancellationCheckInterval
                <= RecompareModePlanLimits.hardMaximumCancellationCheckInterval
        else {
            throw RecompareModePlanningError.invalidLimit(.cancellationCheckInterval)
        }
    }

    private static func validate(
        _ options: RecompareModeOptions,
        isThreeWay: Bool,
        optionBudget: inout RecompareModeOptionBudget,
        work: inout RecompareModePlanningWork
    ) throws {
        switch options {
        case .text(let twoWay, let threeWay):
            try validate(
                twoWay,
                prefix: "text.twoWay",
                compileRegularExpressions: !isThreeWay,
                optionBudget: &optionBudget,
                work: &work
            )
            try validate(threeWay, prefix: "text.threeWay")
        case .table(let parsing, let twoWay, let threeWay):
            try validate(parsing, prefix: "table.parsing", optionBudget: &optionBudget, work: &work)
            try validate(twoWay, prefix: "table.twoWay")
            try validate(threeWay, prefix: "table.threeWay", optionBudget: &optionBudget, work: &work)
        case .binary(let twoWay, let threeWay):
            try requireNonnegative(twoWay.maximumExactEditDistance, mode: .binary, name: "binary.twoWay.maximumExactEditDistance")
            try requireNonnegative(twoWay.maximumAlignmentWork, mode: .binary, name: "binary.twoWay.maximumAlignmentWork")
            try requireMaximum(
                twoWay.maximumExactEditDistance, maximum: RecompareModeEngineCeilings.maximumExactEditDistance, mode: .binary,
                name: "binary.twoWay.maximumExactEditDistance")
            try requireMaximum(
                twoWay.maximumAlignmentWork, maximum: RecompareModeEngineCeilings.maximumTwoWayAlignmentWork, mode: .binary,
                name: "binary.twoWay.maximumAlignmentWork")
            try requireNonnegative(threeWay.maximumInputBytes, mode: .binary, name: "binary.threeWay.maximumInputBytes")
            try requireNonnegative(threeWay.maximumExactEditDistance, mode: .binary, name: "binary.threeWay.maximumExactEditDistance")
            try requireNonnegative(threeWay.maximumAlignmentWork, mode: .binary, name: "binary.threeWay.maximumAlignmentWork")
            try requireNonnegative(threeWay.maximumRegions, mode: .binary, name: "binary.threeWay.maximumRegions")
            try requireNonnegative(threeWay.maximumOutputBytes, mode: .binary, name: "binary.threeWay.maximumOutputBytes")
            try requireMaximum(
                threeWay.maximumInputBytes, maximum: RecompareModeEngineCeilings.maximumThreeWayInputBytes, mode: .binary,
                name: "binary.threeWay.maximumInputBytes")
            try requireMaximum(
                threeWay.maximumExactEditDistance, maximum: RecompareModeEngineCeilings.maximumExactEditDistance, mode: .binary,
                name: "binary.threeWay.maximumExactEditDistance")
            try requireMaximum(
                threeWay.maximumAlignmentWork, maximum: RecompareModeEngineCeilings.maximumThreeWayAlignmentWork, mode: .binary,
                name: "binary.threeWay.maximumAlignmentWork")
            try requireMaximum(
                threeWay.maximumRegions, maximum: RecompareModeEngineCeilings.maximumCollectionItems, mode: .binary, name: "binary.threeWay.maximumRegions")
            try requireMaximum(
                threeWay.maximumOutputBytes, maximum: RecompareModeEngineCeilings.maximumThreeWayOutputBytes, mode: .binary,
                name: "binary.threeWay.maximumOutputBytes")
        case .image(let loading, let comparison):
            try requirePositive(loading.maximumEncodedBytes, mode: .image, name: "image.loading.maximumEncodedBytes")
            try requirePositive(loading.maximumDimension, mode: .image, name: "image.loading.maximumDimension")
            try requirePositive(loading.maximumPixelCount, mode: .image, name: "image.loading.maximumPixelCount")
            try requirePositive(loading.maximumDecodedBytes, mode: .image, name: "image.loading.maximumDecodedBytes")
            try requireMaximum(
                loading.maximumEncodedBytes, maximum: RecompareModeEngineCeilings.maximumTwoWayInputBytes, mode: .image,
                name: "image.loading.maximumEncodedBytes")
            try requireMaximum(
                loading.maximumDimension, maximum: RecompareModeEngineCeilings.maximumImageDimension, mode: .image, name: "image.loading.maximumDimension")
            try requireMaximum(
                loading.maximumPixelCount, maximum: RecompareModeEngineCeilings.maximumImagePixels, mode: .image, name: "image.loading.maximumPixelCount")
            try requireMaximum(
                loading.maximumDecodedBytes, maximum: RecompareModeEngineCeilings.maximumImageDecodedBytes, mode: .image,
                name: "image.loading.maximumDecodedBytes")
            guard !loading.supportedTypeIdentifiers.isEmpty else {
                throw RecompareModePlanningError.invalidOption(
                    mode: .image,
                    name: "image.loading.supportedTypeIdentifiers"
                )
            }
            try optionBudget.addItems(loading.supportedTypeIdentifiers.count)
            let identifiers = Array(loading.supportedTypeIdentifiers)
            for identifier in identifiers {
                try optionBudget.addString(
                    identifier,
                    name: "image.loading.supportedTypeIdentifiers",
                    work: &work
                )
            }
            for identifier in identifiers.sorted() {
                guard ImageComparisonLimits.supportedStaticTypeIdentifiers.contains(identifier) else {
                    throw RecompareModePlanningError.invalidOption(
                        mode: .image,
                        name: "image.loading.supportedTypeIdentifiers"
                    )
                }
            }
            try requirePositive(comparison.maximumCanvasPixels, mode: .image, name: "image.comparison.maximumCanvasPixels")
            try requirePositive(comparison.maximumRegions, mode: .image, name: "image.comparison.maximumRegions")
            try requirePositive(comparison.maximumQueuedPixels, mode: .image, name: "image.comparison.maximumQueuedPixels")
            try requireMaximum(
                comparison.maximumCanvasPixels, maximum: RecompareModeEngineCeilings.maximumImagePixels, mode: .image,
                name: "image.comparison.maximumCanvasPixels")
            try requireMaximum(
                comparison.maximumRegions, maximum: RecompareModeEngineCeilings.maximumImageRegions, mode: .image, name: "image.comparison.maximumRegions")
            try requireMaximum(
                comparison.maximumQueuedPixels, maximum: RecompareModeEngineCeilings.maximumImageQueuedPixels, mode: .image,
                name: "image.comparison.maximumQueuedPixels")
        case .webpage(let twoWay, let threeWay):
            try validate(
                twoWay,
                compileRegularExpressions: !isThreeWay,
                optionBudget: &optionBudget,
                work: &work
            )
            try validate(threeWay, optionBudget: &optionBudget, work: &work)
        case .archive(let limits):
            try validate(limits)
        }
    }

    private static func validate(
        _ options: LineDiffOptions,
        prefix: String,
        compileRegularExpressions: Bool,
        optionBudget: inout RecompareModeOptionBudget,
        work: inout RecompareModePlanningWork
    ) throws {
        let (itemCount, overflow) = options.lineFilters.count.addingReportingOverflow(
            options.substitutions.count
        )
        guard !overflow else {
            throw RecompareModePlanningError.tooManyOptionItems(
                maximum: optionBudget.limits.maximumOptionItemCount
            )
        }
        try optionBudget.addItems(itemCount)
        for (index, rule) in options.lineFilters.enumerated() {
            let name = "\(prefix).lineFilters[\(index)].pattern"
            try optionBudget.addString(
                rule.pattern,
                name: name,
                work: &work
            )
            if compileRegularExpressions, options.lineFiltersEnabled {
                try validateRegularExpression(
                    rule.pattern,
                    name: name,
                    caseSensitive: rule.caseSensitive
                )
            }
        }
        for (index, rule) in options.substitutions.enumerated() {
            let patternName = "\(prefix).substitutions[\(index)].pattern"
            try optionBudget.addString(
                rule.pattern,
                name: patternName,
                work: &work
            )
            try optionBudget.addString(
                rule.replacement,
                name: "\(prefix).substitutions[\(index)].replacement",
                work: &work
            )
            if compileRegularExpressions, options.substitutionsEnabled, !rule.pattern.isEmpty {
                try validateRegularExpression(
                    rule.pattern,
                    name: patternName,
                    caseSensitive: rule.caseSensitive,
                    substitution: true
                )
            }
        }
    }

    private static func validate(
        _ options: ThreeWayTextMergeOptions,
        prefix: String
    ) throws {
        try requireNonnegative(options.maximumInputBytes, mode: .text, name: "\(prefix).maximumInputBytes")
        try requireNonnegative(options.maximumInputLines, mode: .text, name: "\(prefix).maximumInputLines")
        try requireNonnegative(options.maximumOutputBytes, mode: .text, name: "\(prefix).maximumOutputBytes")
        try requireNonnegative(options.maximumOutputLines, mode: .text, name: "\(prefix).maximumOutputLines")
        try requireNonnegative(options.maximumRegions, mode: .text, name: "\(prefix).maximumRegions")
        try requireMaximum(
            options.maximumInputBytes, maximum: RecompareModeEngineCeilings.maximumThreeWayInputBytes, mode: .text, name: "\(prefix).maximumInputBytes")
        try requireMaximum(options.maximumInputLines, maximum: RecompareModeEngineCeilings.maximumLineCount, mode: .text, name: "\(prefix).maximumInputLines")
        try requireMaximum(
            options.maximumOutputBytes, maximum: RecompareModeEngineCeilings.maximumThreeWayOutputBytes, mode: .text, name: "\(prefix).maximumOutputBytes")
        try requireMaximum(
            options.maximumOutputLines, maximum: RecompareModeEngineCeilings.maximumThreeWayOutputLines, mode: .text, name: "\(prefix).maximumOutputLines")
        try requireMaximum(options.maximumRegions, maximum: RecompareModeEngineCeilings.maximumThreeWayRegions, mode: .text, name: "\(prefix).maximumRegions")
    }

    private static func validate(
        _ options: DelimitedTableParsingOptions,
        prefix: String,
        optionBudget: inout RecompareModeOptionBudget,
        work: inout RecompareModePlanningWork
    ) throws {
        try optionBudget.addItems(1 + (options.quote == nil ? 0 : 1))
        let delimiter = String(options.delimiter)
        try optionBudget.addString(delimiter, name: "\(prefix).delimiter", work: &work)
        guard isValidTableCharacter(options.delimiter) else {
            throw RecompareModePlanningError.invalidOption(mode: .table, name: "\(prefix).delimiter")
        }
        if let quote = options.quote {
            try optionBudget.addString(String(quote), name: "\(prefix).quote", work: &work)
            guard isValidTableCharacter(quote), quote != options.delimiter else {
                throw RecompareModePlanningError.invalidOption(mode: .table, name: "\(prefix).quote")
            }
        }
        let limits = options.limits
        try requireNonnegative(limits.maximumInputBytes, mode: .table, name: "\(prefix).limits.maximumInputBytes")
        try requirePositive(limits.maximumRows, mode: .table, name: "\(prefix).limits.maximumRows")
        try requirePositive(limits.maximumColumnsPerRow, mode: .table, name: "\(prefix).limits.maximumColumnsPerRow")
        try requirePositive(limits.maximumTotalCells, mode: .table, name: "\(prefix).limits.maximumTotalCells")
        try requireNonnegative(limits.maximumCellBytes, mode: .table, name: "\(prefix).limits.maximumCellBytes")
        try requireMaximum(
            limits.maximumInputBytes, maximum: RecompareModeEngineCeilings.maximumTwoWayInputBytes, mode: .table, name: "\(prefix).limits.maximumInputBytes")
        try requireMaximum(limits.maximumRows, maximum: RecompareModeEngineCeilings.maximumTableRows, mode: .table, name: "\(prefix).limits.maximumRows")
        try requireMaximum(
            limits.maximumColumnsPerRow, maximum: RecompareModeEngineCeilings.maximumTableColumnsPerRow, mode: .table,
            name: "\(prefix).limits.maximumColumnsPerRow")
        try requireMaximum(
            limits.maximumTotalCells, maximum: RecompareModeEngineCeilings.maximumTableCells, mode: .table, name: "\(prefix).limits.maximumTotalCells")
        try requireMaximum(
            limits.maximumCellBytes, maximum: RecompareModeEngineCeilings.maximumTableCellBytes, mode: .table, name: "\(prefix).limits.maximumCellBytes")
    }

    private static func validate(_ options: TableComparisonOptions, prefix: String) throws {
        try requireNonnegative(options.maximumExactEditDistance, mode: .table, name: "\(prefix).maximumExactEditDistance")
        try requireNonnegative(options.maximumAlignmentWork, mode: .table, name: "\(prefix).maximumAlignmentWork")
        try requireNonnegative(options.maximumComparedRows, mode: .table, name: "\(prefix).maximumComparedRows")
        try requireNonnegative(options.maximumComparedCells, mode: .table, name: "\(prefix).maximumComparedCells")
        try requireMaximum(
            options.maximumExactEditDistance, maximum: RecompareModeEngineCeilings.maximumExactEditDistance, mode: .table,
            name: "\(prefix).maximumExactEditDistance")
        try requireMaximum(
            options.maximumAlignmentWork, maximum: RecompareModeEngineCeilings.maximumTwoWayAlignmentWork, mode: .table, name: "\(prefix).maximumAlignmentWork")
        try requireMaximum(
            options.maximumComparedRows, maximum: RecompareModeEngineCeilings.maximumComparedTableItems, mode: .table, name: "\(prefix).maximumComparedRows")
        try requireMaximum(
            options.maximumComparedCells, maximum: RecompareModeEngineCeilings.maximumComparedTableItems, mode: .table, name: "\(prefix).maximumComparedCells")
    }

    private static func validate(
        _ options: ThreeWayTableComparisonOptions,
        prefix: String,
        optionBudget: inout RecompareModeOptionBudget,
        work: inout RecompareModePlanningWork
    ) throws {
        try validate(
            options.parsingOptions,
            prefix: "\(prefix).parsingOptions",
            optionBudget: &optionBudget,
            work: &work
        )
        try validate(options.comparisonOptions, prefix: "\(prefix).comparisonOptions")
        try requireNonnegative(options.maximumComparedValueBytes, mode: .table, name: "\(prefix).maximumComparedValueBytes")
        try requireNonnegative(options.maximumResultRows, mode: .table, name: "\(prefix).maximumResultRows")
        try requireNonnegative(options.maximumResultCells, mode: .table, name: "\(prefix).maximumResultCells")
        try requireMaximum(
            options.maximumComparedValueBytes, maximum: RecompareModeEngineCeilings.maximumThreeWayOutputBytes, mode: .table,
            name: "\(prefix).maximumComparedValueBytes")
        try requireMaximum(
            options.maximumResultRows, maximum: RecompareModeEngineCeilings.maximumThreeWayTableItems, mode: .table, name: "\(prefix).maximumResultRows")
        try requireMaximum(
            options.maximumResultCells, maximum: RecompareModeEngineCeilings.maximumThreeWayTableItems, mode: .table, name: "\(prefix).maximumResultCells")
    }

    private static func validate(
        _ options: WebPageComparisonOptions,
        compileRegularExpressions: Bool,
        optionBudget: inout RecompareModeOptionBudget,
        work: inout RecompareModePlanningWork
    ) throws {
        try validate(
            options.lineDiffOptions,
            prefix: "webpage.twoWay.lineDiffOptions",
            compileRegularExpressions: compileRegularExpressions,
            optionBudget: &optionBudget,
            work: &work
        )
        let limits = options.limits
        let values: [(String, Int, Int)] = [
            ("maximumInputBytes", limits.maximumInputBytes, RecompareModeEngineCeilings.maximumTwoWayInputBytes),
            ("maximumTokenCount", limits.maximumTokenCount, WebPageComparisonLimits.default.maximumTokenCount),
            ("maximumAttributeCount", limits.maximumAttributeCount, WebPageComparisonLimits.default.maximumAttributeCount),
            ("maximumAttributesPerTag", limits.maximumAttributesPerTag, WebPageComparisonLimits.default.maximumAttributesPerTag),
            ("maximumElementDepth", limits.maximumElementDepth, WebPageComparisonLimits.default.maximumElementDepth),
            ("maximumWorkUnits", limits.maximumWorkUnits, WebPageComparisonLimits.default.maximumWorkUnits),
            ("maximumOutputBytes", limits.maximumOutputBytes, RecompareModeEngineCeilings.maximumTwoWayInputBytes)
        ]
        for (name, value, maximum) in values {
            try requireNonnegative(value, mode: .webpage, name: "webpage.twoWay.limits.\(name)")
            try requireMaximum(value, maximum: maximum, mode: .webpage, name: "webpage.twoWay.limits.\(name)")
        }
    }

    private static func validate(
        _ options: ThreeWayWebPageComparisonOptions,
        optionBudget: inout RecompareModeOptionBudget,
        work: inout RecompareModePlanningWork
    ) throws {
        if let context = options.expectedContext {
            try optionBudget.addItems(1)
            try optionBudget.addString(
                context.identifier,
                name: "webpage.threeWay.expectedContext.identifier",
                work: &work
            )
            guard !context.identifier.isEmpty, !context.identifier.utf8.contains(0) else {
                throw RecompareModePlanningError.invalidOption(
                    mode: .webpage,
                    name: "webpage.threeWay.expectedContext.identifier"
                )
            }
        }
        let limits = options.limits
        let values: [(String, Int, Int)] = [
            ("maximumSourceInputBytesPerSnapshot", limits.maximumSourceInputBytesPerSnapshot, RecompareModeEngineCeilings.maximumThreeWayInputBytes),
            ("maximumNormalizedInputBytesPerSnapshot", limits.maximumNormalizedInputBytesPerSnapshot, RecompareModeEngineCeilings.maximumThreeWayInputBytes),
            ("maximumTokenCountPerSnapshot", limits.maximumTokenCountPerSnapshot, ThreeWayWebPageComparisonLimits.default.maximumTokenCountPerSnapshot),
            (
                "maximumAttributeCountPerSnapshot", limits.maximumAttributeCountPerSnapshot,
                ThreeWayWebPageComparisonLimits.default.maximumAttributeCountPerSnapshot
            ),
            ("maximumTotalNormalizedInputBytes", limits.maximumTotalNormalizedInputBytes, RecompareModeEngineCeilings.maximumThreeWayOutputBytes),
            ("maximumInputLinesPerSnapshot", limits.maximumInputLinesPerSnapshot, RecompareModeEngineCeilings.maximumLineCount),
            (
                "maximumMetadataEntriesPerSnapshot", limits.maximumMetadataEntriesPerSnapshot,
                ThreeWayWebPageComparisonLimits.default.maximumMetadataEntriesPerSnapshot
            ),
            ("maximumMetadataBytes", limits.maximumMetadataBytes, ThreeWayWebPageComparisonLimits.default.maximumMetadataBytes),
            ("maximumWorkUnits", limits.maximumWorkUnits, RecompareModeEngineCeilings.maximumEngineWorkUnits),
            ("maximumResultRegions", limits.maximumResultRegions, RecompareModeEngineCeilings.maximumThreeWayRegions),
            ("maximumMappedSegments", limits.maximumMappedSegments, ThreeWayWebPageComparisonLimits.default.maximumMappedSegments),
            ("maximumOutputBytes", limits.maximumOutputBytes, RecompareModeEngineCeilings.maximumThreeWayOutputBytes),
            ("maximumOutputLines", limits.maximumOutputLines, RecompareModeEngineCeilings.maximumThreeWayOutputLines)
        ]
        for (name, value, maximum) in values {
            try requireNonnegative(value, mode: .webpage, name: "webpage.threeWay.limits.\(name)")
            try requireMaximum(value, maximum: maximum, mode: .webpage, name: "webpage.threeWay.limits.\(name)")
        }
    }

    private static func validate(_ limits: ArchiveLimits) throws {
        guard limits.maximumArchiveBytes > 0 else {
            throw RecompareModePlanningError.invalidOption(mode: .archive, name: "archive.maximumArchiveBytes")
        }
        let values: [(String, Int)] = [
            ("maximumEntryCount", limits.maximumEntryCount),
            ("maximumPathDepth", limits.maximumPathDepth),
            ("maximumTotalPathComponents", limits.maximumTotalPathComponents)
        ]
        for (name, value) in values {
            try requireNonnegative(value, mode: .archive, name: "archive.\(name)")
        }
        guard limits.maximumEntryUncompressedBytes > 0 else {
            throw RecompareModePlanningError.invalidOption(mode: .archive, name: "archive.maximumEntryUncompressedBytes")
        }
        guard limits.maximumTotalUncompressedBytes > 0 else {
            throw RecompareModePlanningError.invalidOption(mode: .archive, name: "archive.maximumTotalUncompressedBytes")
        }
        guard limits.maximumCompressionRatio > 0 else {
            throw RecompareModePlanningError.invalidOption(mode: .archive, name: "archive.maximumCompressionRatio")
        }
        let defaults = ArchiveLimits.default
        guard limits.maximumArchiveBytes <= defaults.maximumArchiveBytes,
            limits.maximumEntryCount <= defaults.maximumEntryCount,
            limits.maximumEntryUncompressedBytes <= defaults.maximumEntryUncompressedBytes,
            limits.maximumTotalUncompressedBytes <= defaults.maximumTotalUncompressedBytes,
            limits.maximumCompressionRatio <= defaults.maximumCompressionRatio,
            limits.maximumPathDepth <= defaults.maximumPathDepth,
            limits.maximumTotalPathComponents <= defaults.maximumTotalPathComponents
        else {
            throw RecompareModePlanningError.invalidOption(mode: .archive, name: "archive.limits")
        }
    }

    private static func isValidTableCharacter(_ value: Character) -> Bool {
        let scalars = value.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return false }
        return scalar.value != 0 && scalar.value != 0x0A && scalar.value != 0x0D
    }

    private static func validateRegularExpression(
        _ pattern: String,
        name: String,
        caseSensitive: Bool,
        substitution: Bool = false
    ) throws {
        guard pattern.utf8.count <= RecompareModeEngineCeilings.maximumRegularExpressionUTF8Bytes else {
            throw RecompareModePlanningError.invalidOption(mode: inferredMode(from: name), name: name)
        }
        try Task.checkCancellation()
        let bytes = Array(pattern.utf8)
        let status: Int32
        if substitution {
            var result = mmx_bytes_result(bytes: nil, size: 0)
            status = bytes.withUnsafeBytes {
                mmx_regex_substitute(
                    nil,
                    0,
                    $0.baseAddress,
                    $0.count,
                    nil,
                    0,
                    caseSensitive ? 1 : 0,
                    0,
                    &result
                )
            }
            mmx_bytes_result_free(&result)
        } else {
            var filter: UnsafeMutableRawPointer?
            status = bytes.withUnsafeBytes {
                mmx_line_filter_create(
                    $0.baseAddress,
                    $0.count,
                    caseSensitive ? 1 : 0,
                    &filter
                )
            }
            if let filter { mmx_line_filter_free(filter) }
        }
        try Task.checkCancellation()
        guard status == 0 else {
            throw RecompareModePlanningError.invalidOption(mode: inferredMode(from: name), name: name)
        }
    }

    private static func inferredMode(from name: String) -> RecompareMode {
        RecompareMode.allCases.first { name.hasPrefix($0.rawValue + ".") } ?? .text
    }

    private static func requirePositive(
        _ value: Int,
        mode: RecompareMode,
        name: String
    ) throws {
        guard value > 0 else {
            throw RecompareModePlanningError.invalidOption(mode: mode, name: name)
        }
    }

    private static func requireNonnegative(
        _ value: Int,
        mode: RecompareMode,
        name: String
    ) throws {
        guard value >= 0 else {
            throw RecompareModePlanningError.invalidOption(mode: mode, name: name)
        }
    }

    private static func requireMaximum(
        _ value: Int,
        maximum: Int,
        mode: RecompareMode,
        name: String
    ) throws {
        guard value <= maximum else {
            throw RecompareModePlanningError.invalidOption(mode: mode, name: name)
        }
    }
}

private struct RecompareModePlanningWork {
    let limits: RecompareModePlanLimits
    private(set) var consumed = 0

    mutating func charge(_ amount: Int) throws {
        guard amount >= 0,
            amount <= limits.maximumPlanningWorkUnits - consumed
        else {
            throw RecompareModePlanningError.planningWorkLimitExceeded(
                maximumWorkUnits: limits.maximumPlanningWorkUnits
            )
        }
        consumed += amount
        if consumed.isMultiple(of: limits.cancellationCheckInterval) {
            try Task.checkCancellation()
        }
    }
}

private struct RecompareModeOptionBudget {
    let limits: RecompareModePlanLimits
    private var itemCount = 0
    private var totalStringBytes = 0

    init(limits: RecompareModePlanLimits) {
        self.limits = limits
    }

    mutating func addItems(_ count: Int) throws {
        let (next, overflow) = itemCount.addingReportingOverflow(count)
        guard count >= 0, !overflow, next <= limits.maximumOptionItemCount else {
            throw RecompareModePlanningError.tooManyOptionItems(
                maximum: limits.maximumOptionItemCount
            )
        }
        itemCount = next
    }

    mutating func addString(
        _ value: String,
        name: String,
        work: inout RecompareModePlanningWork
    ) throws {
        var count = 0
        for byte in value.utf8 {
            try work.charge(1)
            guard count < limits.maximumOptionStringUTF8Bytes else {
                throw RecompareModePlanningError.optionStringTooLarge(
                    name: name,
                    maximumUTF8Bytes: limits.maximumOptionStringUTF8Bytes
                )
            }
            guard byte != 0 else {
                throw RecompareModePlanningError.invalidOption(mode: inferredMode(from: name), name: name)
            }
            count += 1
        }
        let (next, overflow) = totalStringBytes.addingReportingOverflow(count)
        guard !overflow, next <= limits.maximumTotalOptionStringUTF8Bytes else {
            throw RecompareModePlanningError.totalOptionStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalOptionStringUTF8Bytes
            )
        }
        totalStringBytes = next
    }

    private func inferredMode(from name: String) -> RecompareMode {
        RecompareMode.allCases.first { name.hasPrefix($0.rawValue + ".") } ?? .text
    }
}
