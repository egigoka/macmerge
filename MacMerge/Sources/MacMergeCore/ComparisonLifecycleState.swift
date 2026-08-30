import Foundation

/// Immutable, UI-independent lifecycle for one comparison.
///
/// Every transition is bound to an exact fingerprint. Work completion additionally carries an
/// operation token that binds the operation identity, comparison lineage, start generation, and
/// complete input identity. Callers must discard transitions rejected as stale.
public struct ComparisonLifecycleState: Equatable, Hashable, Sendable {
    public struct Identity: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }

    public struct InputIdentity: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }

    public struct SideIdentity: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }

    public struct OperationID: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }

    public struct ResultID: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }

    public enum Side: Int, CaseIterable, Comparable, Equatable, Hashable, Sendable {
        case left
        case middle
        case right

        public static func < (left: Side, right: Side) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    /// Exact identity of materialized content on one side. `generation` must change whenever the
    /// content represented by `identity` changes.
    public struct SideBinding: Equatable, Hashable, Sendable {
        public let side: Side
        public let identity: SideIdentity
        public let generation: UInt64

        public init(side: Side, identity: SideIdentity, generation: UInt64) {
            self.side = side
            self.identity = identity
            self.generation = generation
        }
    }

    /// Canonically ordered two- or three-way comparison inputs.
    public struct InputBinding: Equatable, Hashable, Sendable {
        public let identity: InputIdentity
        public let generation: UInt64
        public let sides: [SideBinding]

        public var isThreeWay: Bool { sides.count == 3 }

        public subscript(side: Side) -> SideBinding? {
            sides.first { $0.side == side }
        }

        public init(
            identity: InputIdentity,
            generation: UInt64,
            sides: [SideBinding]
        ) throws {
            guard sides.count == 2 || sides.count == 3 else {
                throw StateError.invalidInputSideCount(sides.count)
            }

            let orderedSides = sides.sorted { $0.side < $1.side }
            for index in orderedSides.indices.dropFirst() {
                guard orderedSides[index - 1].side != orderedSides[index].side else {
                    throw StateError.duplicateInputSide(orderedSides[index].side)
                }
            }

            let expected: [Side] =
                orderedSides.count == 2 ? [.left, .right] : [.left, .middle, .right]
            let actual = orderedSides.map(\.side)
            guard actual == expected else {
                throw StateError.invalidInputSides(
                    hasLeft: actual.contains(.left),
                    hasMiddle: actual.contains(.middle),
                    hasRight: actual.contains(.right)
                )
            }

            self.identity = identity
            self.generation = generation
            self.sides = orderedSides
        }
    }

    public enum Phase: String, CaseIterable, Equatable, Hashable, Sendable {
        case empty
        case oneSideLoaded
        case loading
        case current
        case stale
        case refreshing
        case failed
        case canceled

        public var hasActiveOperation: Bool {
            self == .loading || self == .refreshing
        }
    }

    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumFailureCodeUTF8Bytes = 1_024
        public static let hardMaximumFailureMessageUTF8Bytes = 64 * 1_024
        public static let hardMaximumProgressDetailUTF8Bytes = 16 * 1_024
        public static let hardMaximumCancellationDetailUTF8Bytes = 16 * 1_024
        public static let hardMaximumTotalMetadataUTF8Bytes = 128 * 1_024
        public static let hardMaximumProgressUnitCount = UInt64.max / 4
        public static let hardMaximumDeclaredWorkUnits = UInt64.max / 4
        public static let hardMaximumTransitionWorkUnits = 4 * 1_024 * 1_024
        public static let `default` = Limits()

        public let maximumFailureCodeUTF8Bytes: Int
        public let maximumFailureMessageUTF8Bytes: Int
        public let maximumProgressDetailUTF8Bytes: Int
        public let maximumCancellationDetailUTF8Bytes: Int
        public let maximumTotalMetadataUTF8Bytes: Int
        public let maximumProgressUnitCount: UInt64
        public let maximumDeclaredWorkUnits: UInt64
        public let maximumTransitionWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumFailureCodeUTF8Bytes: Int = 256,
            maximumFailureMessageUTF8Bytes: Int = 16 * 1_024,
            maximumProgressDetailUTF8Bytes: Int = 4 * 1_024,
            maximumCancellationDetailUTF8Bytes: Int = 4 * 1_024,
            maximumTotalMetadataUTF8Bytes: Int = 32 * 1_024,
            maximumProgressUnitCount: UInt64 = 1_000_000_000_000,
            maximumDeclaredWorkUnits: UInt64 = 1_000_000_000_000,
            maximumTransitionWorkUnits: Int = 256 * 1_024,
            cancellationCheckInterval: Int = 4_096
        ) {
            self.maximumFailureCodeUTF8Bytes = maximumFailureCodeUTF8Bytes
            self.maximumFailureMessageUTF8Bytes = maximumFailureMessageUTF8Bytes
            self.maximumProgressDetailUTF8Bytes = maximumProgressDetailUTF8Bytes
            self.maximumCancellationDetailUTF8Bytes = maximumCancellationDetailUTF8Bytes
            self.maximumTotalMetadataUTF8Bytes = maximumTotalMetadataUTF8Bytes
            self.maximumProgressUnitCount = maximumProgressUnitCount
            self.maximumDeclaredWorkUnits = maximumDeclaredWorkUnits
            self.maximumTransitionWorkUnits = maximumTransitionWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }
    }

    public enum Limit: String, CaseIterable, Equatable, Hashable, Sendable {
        case failureCodeUTF8Bytes
        case failureMessageUTF8Bytes
        case progressDetailUTF8Bytes
        case cancellationDetailUTF8Bytes
        case totalMetadataUTF8Bytes
        case progressUnitCount
        case declaredWorkUnits
        case transitionWorkUnits
        case cancellationCheckInterval
    }

    public struct Progress: Equatable, Hashable, Sendable {
        public enum Stage: Int, CaseIterable, Comparable, Equatable, Hashable, Sendable {
            case preparing
            case loadingInputs
            case comparing
            case publishing

            public static func < (left: Stage, right: Stage) -> Bool {
                left.rawValue < right.rawValue
            }
        }

        public static let pending = Progress(
            validatedStage: .preparing,
            completedUnitCount: 0,
            totalUnitCount: nil,
            detail: nil
        )

        public let stage: Stage
        public let completedUnitCount: UInt64
        public let totalUnitCount: UInt64?
        /// Bounded semantic detail. Presentation layers own localization and formatting.
        public let detail: String?

        public var fractionCompleted: Double? {
            guard let totalUnitCount, totalUnitCount > 0 else { return nil }
            guard completedUnitCount < totalUnitCount else { return 1 }
            return min(
                Double(completedUnitCount) / Double(totalUnitCount),
                Double(1).nextDown
            )
        }

        public var isComplete: Bool {
            guard let totalUnitCount else { return false }
            return completedUnitCount == totalUnitCount
        }

        public init(
            stage: Stage,
            completedUnitCount: UInt64,
            totalUnitCount: UInt64? = nil,
            detail: String? = nil
        ) throws {
            guard completedUnitCount <= Limits.hardMaximumProgressUnitCount else {
                throw StateError.progressUnitLimitExceeded(
                    maximum: Limits.hardMaximumProgressUnitCount
                )
            }
            if let totalUnitCount {
                guard totalUnitCount > 0, completedUnitCount <= totalUnitCount else {
                    throw StateError.invalidProgressTotal
                }
                guard totalUnitCount <= Limits.hardMaximumProgressUnitCount else {
                    throw StateError.progressUnitLimitExceeded(
                        maximum: Limits.hardMaximumProgressUnitCount
                    )
                }
            }

            let normalizedDetail: String?
            if let detail {
                try ComparisonLifecycleState.validateStandaloneText(
                    detail,
                    field: .progressDetail,
                    maximumBytes: Limits.hardMaximumProgressDetailUTF8Bytes,
                    allowsEmpty: true
                )
                normalizedDetail = detail.precomposedStringWithCanonicalMapping
                try ComparisonLifecycleState.validateStandaloneText(
                    normalizedDetail!,
                    field: .progressDetail,
                    maximumBytes: Limits.hardMaximumProgressDetailUTF8Bytes,
                    allowsEmpty: true
                )
            } else {
                normalizedDetail = nil
            }
            self.stage = stage
            self.completedUnitCount = completedUnitCount
            self.totalUnitCount = totalUnitCount
            self.detail = normalizedDetail
        }

        private init(
            validatedStage stage: Stage,
            completedUnitCount: UInt64,
            totalUnitCount: UInt64?,
            detail: String?
        ) {
            self.stage = stage
            self.completedUnitCount = completedUnitCount
            self.totalUnitCount = totalUnitCount
            self.detail = detail
        }
    }

    public enum FailureKind: String, CaseIterable, Equatable, Hashable, Sendable {
        case invalidInput
        case inputUnavailable
        case readFailed
        case comparisonFailed
        case unsupported
        case resourceLimit
        case internalFailure
    }

    /// Bounded, transportable failure metadata. It intentionally does not retain an arbitrary
    /// `Error`, which may be non-Sendable or expose paths and other sensitive input.
    public struct Failure: Equatable, Hashable, Sendable {
        public let kind: FailureKind
        public let code: String
        public let message: String
        public let stage: Progress.Stage
        public let side: Side?
        public let isRetryable: Bool

        public init(
            kind: FailureKind,
            code: String,
            message: String,
            stage: Progress.Stage,
            side: Side? = nil,
            isRetryable: Bool = false
        ) throws {
            try ComparisonLifecycleState.validateStandaloneFailureCode(
                code,
                maximumBytes: Limits.hardMaximumFailureCodeUTF8Bytes
            )
            try ComparisonLifecycleState.validateStandaloneText(
                message,
                field: .failureMessage,
                maximumBytes: Limits.hardMaximumFailureMessageUTF8Bytes,
                allowsEmpty: false
            )
            let normalizedMessage = message.precomposedStringWithCanonicalMapping
            try ComparisonLifecycleState.validateStandaloneText(
                normalizedMessage,
                field: .failureMessage,
                maximumBytes: Limits.hardMaximumFailureMessageUTF8Bytes,
                allowsEmpty: false
            )
            self.kind = kind
            self.code = code
            self.message = normalizedMessage
            self.stage = stage
            self.side = side
            self.isRetryable = isRetryable
        }
    }

    public enum CancellationReason: String, CaseIterable, Equatable, Hashable, Sendable {
        case userRequested
        case superseded
        case sessionClosing
        case resourceLimit
    }

    public struct Cancellation: Equatable, Hashable, Sendable {
        public let reason: CancellationReason
        public let stage: Progress.Stage
        public let detail: String?

        public init(
            reason: CancellationReason,
            stage: Progress.Stage,
            detail: String? = nil
        ) throws {
            try self.init(
                reason: reason,
                stage: stage,
                detail: detail,
                observesTaskCancellation: true
            )
        }

        fileprivate init(
            reason: CancellationReason,
            stage: Progress.Stage,
            detail: String?,
            observesTaskCancellation: Bool
        ) throws {
            let normalizedDetail: String?
            if let detail {
                try ComparisonLifecycleState.validateStandaloneText(
                    detail,
                    field: .cancellationDetail,
                    maximumBytes: Limits.hardMaximumCancellationDetailUTF8Bytes,
                    allowsEmpty: false,
                    observesTaskCancellation: observesTaskCancellation
                )
                normalizedDetail = detail.precomposedStringWithCanonicalMapping
                try ComparisonLifecycleState.validateStandaloneText(
                    normalizedDetail!,
                    field: .cancellationDetail,
                    maximumBytes: Limits.hardMaximumCancellationDetailUTF8Bytes,
                    allowsEmpty: false,
                    observesTaskCancellation: observesTaskCancellation
                )
            } else {
                normalizedDetail = nil
            }
            self.reason = reason
            self.stage = stage
            self.detail = normalizedDetail
        }
    }

    public enum StaleReason: Equatable, Hashable, Sendable {
        case sideChanged(Side)
        case optionsChanged
        case externalChange(Side)
        case comparisonModeChanged
    }

    public struct OperationToken: Equatable, Hashable, Sendable {
        public let comparisonIdentity: Identity
        public let operationID: OperationID
        public let startedAtGeneration: UInt64
        public let inputs: InputBinding

        fileprivate init(
            comparisonIdentity: Identity,
            operationID: OperationID,
            startedAtGeneration: UInt64,
            inputs: InputBinding
        ) {
            self.comparisonIdentity = comparisonIdentity
            self.operationID = operationID
            self.startedAtGeneration = startedAtGeneration
            self.inputs = inputs
        }
    }

    public struct Operation: Equatable, Hashable, Sendable {
        public enum Kind: String, CaseIterable, Equatable, Hashable, Sendable {
            case initialLoad
            case refresh
        }

        public let kind: Kind
        public let token: OperationToken
        /// Caller-declared upper bound for work outside this state machine.
        public let declaredWorkUnits: UInt64
        public let progress: Progress

        fileprivate init(
            kind: Kind,
            token: OperationToken,
            declaredWorkUnits: UInt64,
            progress: Progress
        ) {
            self.kind = kind
            self.token = token
            self.declaredWorkUnits = declaredWorkUnits
            self.progress = progress
        }
    }

    public struct ResultBinding: Equatable, Hashable, Sendable {
        public let identity: ResultID
        public let inputs: InputBinding
        public let operation: OperationToken
        public let publishedAtGeneration: UInt64

        fileprivate init(
            identity: ResultID,
            inputs: InputBinding,
            operation: OperationToken,
            publishedAtGeneration: UInt64
        ) {
            self.identity = identity
            self.inputs = inputs
            self.operation = operation
            self.publishedAtGeneration = publishedAtGeneration
        }
    }

    public struct Staleness: Equatable, Hashable, Sendable {
        public let reason: StaleReason
        public let invalidatedResult: ResultBinding
        public let currentInputs: InputBinding
        public let detectedAtGeneration: UInt64

        fileprivate init(
            reason: StaleReason,
            invalidatedResult: ResultBinding,
            currentInputs: InputBinding,
            detectedAtGeneration: UInt64
        ) {
            self.reason = reason
            self.invalidatedResult = invalidatedResult
            self.currentInputs = currentInputs
            self.detectedAtGeneration = detectedAtGeneration
        }
    }

    public struct FailureRecord: Equatable, Hashable, Sendable {
        public let operation: OperationToken
        public let lastProgress: Progress
        public let failure: Failure
        public let recordedAtGeneration: UInt64

        fileprivate init(
            operation: OperationToken,
            lastProgress: Progress,
            failure: Failure,
            recordedAtGeneration: UInt64
        ) {
            self.operation = operation
            self.lastProgress = lastProgress
            self.failure = failure
            self.recordedAtGeneration = recordedAtGeneration
        }
    }

    public struct CancellationRecord: Equatable, Hashable, Sendable {
        public let operation: OperationToken
        public let lastProgress: Progress
        public let cancellation: Cancellation
        public let recordedAtGeneration: UInt64

        fileprivate init(
            operation: OperationToken,
            lastProgress: Progress,
            cancellation: Cancellation,
            recordedAtGeneration: UInt64
        ) {
            self.operation = operation
            self.lastProgress = lastProgress
            self.cancellation = cancellation
            self.recordedAtGeneration = recordedAtGeneration
        }
    }

    /// Exact structural state identity. Unlike a digest, it cannot collide.
    public struct Fingerprint: Equatable, Hashable, Sendable {
        public let identity: Identity
        public let generation: UInt64
        fileprivate let snapshot: Snapshot

        fileprivate init(snapshot: Snapshot) {
            identity = snapshot.identity
            generation = snapshot.generation
            self.snapshot = snapshot
        }

        public func matches(_ state: ComparisonLifecycleState) throws -> Bool {
            var work = WorkBudget(limits: state.limits)
            let matches = try snapshot.matches(state.snapshot, work: &work)
            try work.finish()
            return matches
        }

        fileprivate func matches(
            _ state: ComparisonLifecycleState,
            work: inout WorkBudget
        ) throws -> Bool {
            try snapshot.matches(state.snapshot, work: &work)
        }
    }

    public enum Command: String, CaseIterable, Equatable, Hashable, Sendable {
        case loadFirstSide
        case unloadOnlySide
        case beginLoading
        case markStale
        case beginRefreshing
        case updateProgress
        case complete
        case fail
        case cancel
        case reset
    }

    public enum EnabledReason: Equatable, Hashable, Sendable {
        case firstSideMayLoad
        case onlySideMayUnload(Side)
        case initialComparisonMayStart
        case retainedResultMayBecomeStale(ResultID)
        case refreshMayStart(ResultID)
        case operationMayProgress(OperationID)
        case operationMayComplete(OperationID)
        case operationMayFail(OperationID)
        case operationMayCancel(OperationID)
        case lifecycleMayReset
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case sideAlreadyLoaded
        case noOnlySideLoaded
        case initialLoadUnavailable(Phase)
        case noCurrentResult
        case noResultToRefresh
        case noActiveOperation
        case operationInProgress(OperationID)
        case failureNotRetryable(FailureKind)
        case alreadyEmpty
    }

    public enum Availability: Equatable, Hashable, Sendable {
        case enabled
        case disabled(DisabledReason)

        public var isEnabled: Bool { self == .enabled }
        public var disabledReason: DisabledReason? {
            guard case .disabled(let reason) = self else { return nil }
            return reason
        }
    }

    public enum AvailabilityReason: Equatable, Hashable, Sendable {
        case enabled(EnabledReason)
        case disabled(DisabledReason)

        public var availability: Availability {
            switch self {
            case .enabled: .enabled
            case .disabled(let reason): .disabled(reason)
            }
        }
    }

    public enum Event: Equatable, Hashable, Sendable {
        case loadFirstSide(expected: Fingerprint, binding: SideBinding)
        case unloadOnlySide(expected: Fingerprint, binding: SideBinding)
        case beginLoading(
            expected: Fingerprint,
            inputs: InputBinding,
            operationID: OperationID,
            declaredWorkUnits: UInt64,
            progress: Progress = .pending
        )
        case markStale(
            expected: Fingerprint,
            currentInputs: InputBinding,
            reason: StaleReason
        )
        case beginRefreshing(
            expected: Fingerprint,
            operationID: OperationID,
            declaredWorkUnits: UInt64,
            progress: Progress = .pending
        )
        case updateProgress(
            expected: Fingerprint,
            operation: OperationToken,
            progress: Progress
        )
        case complete(
            expected: Fingerprint,
            operation: OperationToken,
            resultID: ResultID
        )
        case fail(
            expected: Fingerprint,
            operation: OperationToken,
            failure: Failure
        )
        case cancel(
            expected: Fingerprint,
            operation: OperationToken,
            cancellation: Cancellation
        )
        case reset(expected: Fingerprint)

        public var command: Command {
            switch self {
            case .loadFirstSide: .loadFirstSide
            case .unloadOnlySide: .unloadOnlySide
            case .beginLoading: .beginLoading
            case .markStale: .markStale
            case .beginRefreshing: .beginRefreshing
            case .updateProgress: .updateProgress
            case .complete: .complete
            case .fail: .fail
            case .cancel: .cancel
            case .reset: .reset
            }
        }

        fileprivate var expectedFingerprint: Fingerprint {
            switch self {
            case .loadFirstSide(let expected, _),
                .unloadOnlySide(let expected, _),
                .beginLoading(let expected, _, _, _, _),
                .markStale(let expected, _, _),
                .beginRefreshing(let expected, _, _, _),
                .updateProgress(let expected, _, _),
                .complete(let expected, _, _),
                .fail(let expected, _, _),
                .cancel(let expected, _, _),
                .reset(let expected):
                expected
            }
        }
    }

    public enum MetadataField: String, Equatable, Hashable, Sendable {
        case failureCode
        case failureMessage
        case progressDetail
        case cancellationDetail
    }

    public enum StateError: Error, Equatable, LocalizedError, Sendable {
        case cancelled
        case invalidLimit(Limit)
        case invalidInputSideCount(Int)
        case duplicateInputSide(Side)
        case invalidInputSides(hasLeft: Bool, hasMiddle: Bool, hasRight: Bool)
        case staleState(expected: Fingerprint, actual: Fingerprint)
        case staleOperation(expected: OperationToken, actual: OperationToken)
        case commandDisabled(DisabledReason)
        case sideBindingMismatch(expected: SideBinding, actual: SideBinding?)
        case inputBindingMismatch(expected: InputBinding, actual: InputBinding)
        case unchangedInputs
        case unchangedComparisonMode
        case invalidStaleSide(Side)
        case invalidFailureSide(Side)
        case duplicateOperationID(OperationID)
        case generationExhausted
        case invalidProgressTotal
        case progressUnitLimitExceeded(maximum: UInt64)
        case progressRegressed
        case progressTotalChanged
        case invalidFailureCode
        case invalidMetadataText(MetadataField)
        case metadataTooLarge(field: MetadataField, maximumBytes: Int)
        case totalMetadataTooLarge(maximumBytes: Int)
        case failureStageRegressed
        case cancellationStageRegressed
        case declaredWorkLimitExceeded(maximum: UInt64)
        case workLimitExceeded(maximum: Int)

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                "Comparison lifecycle work was canceled."
            case .invalidLimit(let limit):
                "Comparison lifecycle limit is invalid: \(limit.rawValue)."
            case .invalidInputSideCount(let count):
                "Comparison inputs require two or three sides, not \(count)."
            case .duplicateInputSide(let side):
                "Comparison inputs contain duplicate \(side) sides."
            case .invalidInputSides(let hasLeft, let hasMiddle, let hasRight):
                "Comparison input side layout is invalid (left: \(hasLeft), middle: \(hasMiddle), right: \(hasRight))."
            case .staleState(let expected, let actual):
                "Comparison lifecycle state changed from generation \(expected.generation) to \(actual.generation)."
            case .staleOperation:
                "Comparison lifecycle operation identity does not match the active operation."
            case .commandDisabled(let reason):
                "Comparison lifecycle command is disabled: \(reason)."
            case .sideBindingMismatch(_, let actual):
                actual == nil
                    ? "Comparison inputs omit the loaded side."
                    : "Comparison side identity or generation does not match the loaded side."
            case .inputBindingMismatch:
                "Comparison input identity or generation does not match current inputs."
            case .unchangedInputs:
                "A current comparison cannot become stale without a new input identity or generation."
            case .unchangedComparisonMode:
                "Comparison-mode staleness requires a change between two-way and three-way inputs."
            case .invalidStaleSide(let side):
                "Comparison staleness names a side outside the previous and current inputs: \(side)."
            case .invalidFailureSide(let side):
                "Comparison failure names a side outside the active operation inputs: \(side)."
            case .duplicateOperationID:
                "A completed operation identity cannot be reused by the retained comparison result."
            case .generationExhausted:
                "Comparison lifecycle generation space is exhausted; allocate a new identity."
            case .invalidProgressTotal:
                "Comparison progress requires a positive total no smaller than completed work."
            case .progressUnitLimitExceeded(let maximum):
                "Comparison progress exceeds the \(maximum)-unit limit."
            case .progressRegressed:
                "Comparison progress stage or completed count moved backward."
            case .progressTotalChanged:
                "Comparison progress total changed within one stage."
            case .invalidFailureCode:
                "Comparison failure code must be nonempty ASCII letters, digits, period, underscore, or hyphen."
            case .invalidMetadataText(let field):
                "Comparison lifecycle \(field.rawValue) contains unsupported control characters."
            case .metadataTooLarge(let field, let maximumBytes):
                "Comparison lifecycle \(field.rawValue) exceeds \(maximumBytes) UTF-8 bytes."
            case .totalMetadataTooLarge(let maximumBytes):
                "Comparison lifecycle metadata exceeds \(maximumBytes) total UTF-8 bytes."
            case .failureStageRegressed:
                "Comparison failure stage precedes the last reported progress stage."
            case .cancellationStageRegressed:
                "Comparison cancellation stage precedes the last reported progress stage."
            case .declaredWorkLimitExceeded(let maximum):
                "Comparison operation exceeds the \(maximum)-unit declared work limit."
            case .workLimitExceeded(let maximum):
                "Comparison lifecycle transition exceeds the \(maximum)-unit work limit."
            }
        }
    }

    public let identity: Identity
    public let generation: UInt64
    public let limits: Limits
    public let phase: Phase
    public let loadedSide: SideBinding?
    public let inputs: InputBinding?
    public let operation: Operation?
    public let result: ResultBinding?
    public let staleness: Staleness?
    public let failure: FailureRecord?
    public let cancellation: CancellationRecord?

    private let snapshot: Snapshot

    public var fingerprint: Fingerprint { Fingerprint(snapshot: snapshot) }
    public var hasActiveOperation: Bool { operation != nil }
    public var hasCurrentResult: Bool {
        phase == .current && result?.inputs == inputs
    }
    public var hasRetainedResult: Bool { result != nil }

    public init(
        identity: Identity = Identity(),
        limits: Limits = .default
    ) throws {
        try Self.validate(limits)
        let snapshot = Snapshot(
            identity: identity,
            generation: 0,
            limits: limits,
            phase: .empty,
            loadedSide: nil,
            inputs: nil,
            operation: nil,
            result: nil,
            staleness: nil,
            failure: nil,
            cancellation: nil
        )
        self.init(snapshot: snapshot)
    }

    public func availability(for command: Command) -> AvailabilityReason {
        if let operation {
            switch command {
            case .updateProgress:
                return .enabled(.operationMayProgress(operation.token.operationID))
            case .complete:
                return .enabled(.operationMayComplete(operation.token.operationID))
            case .fail:
                return .enabled(.operationMayFail(operation.token.operationID))
            case .cancel:
                return .enabled(.operationMayCancel(operation.token.operationID))
            case .loadFirstSide, .unloadOnlySide, .beginLoading, .markStale,
                .beginRefreshing, .reset:
                return .disabled(.operationInProgress(operation.token.operationID))
            }
        }

        switch command {
        case .loadFirstSide:
            return phase == .empty
                ? .enabled(.firstSideMayLoad) : .disabled(.sideAlreadyLoaded)
        case .unloadOnlySide:
            guard let loadedSide, phase == .oneSideLoaded else {
                return .disabled(.noOnlySideLoaded)
            }
            return .enabled(.onlySideMayUnload(loadedSide.side))
        case .beginLoading:
            switch phase {
            case .empty, .oneSideLoaded:
                return .enabled(.initialComparisonMayStart)
            case .failed where result == nil, .canceled where result == nil:
                if let failure, !failure.failure.isRetryable {
                    return .disabled(.failureNotRetryable(failure.failure.kind))
                }
                return .enabled(.initialComparisonMayStart)
            case .loading, .current, .stale, .refreshing, .failed, .canceled:
                return .disabled(.initialLoadUnavailable(phase))
            }
        case .markStale:
            guard phase == .current || phase == .stale || phase == .failed || phase == .canceled,
                let result
            else { return .disabled(.noCurrentResult) }
            return .enabled(.retainedResultMayBecomeStale(result.identity))
        case .beginRefreshing:
            switch phase {
            case .current, .stale, .failed, .canceled:
                guard let result else { return .disabled(.noResultToRefresh) }
                if let failure, !failure.failure.isRetryable {
                    return .disabled(.failureNotRetryable(failure.failure.kind))
                }
                return .enabled(.refreshMayStart(result.identity))
            case .empty, .oneSideLoaded, .loading, .refreshing:
                return .disabled(.noResultToRefresh)
            }
        case .updateProgress, .complete, .fail, .cancel:
            return .disabled(.noActiveOperation)
        case .reset:
            return phase == .empty ? .disabled(.alreadyEmpty) : .enabled(.lifecycleMayReset)
        }
    }

    public func applying(_ event: Event) throws -> ComparisonLifecycleState {
        try applying(event, observesTaskCancellation: true)
    }

    /// Records an active operation's cancellation even when the calling task is already canceled.
    /// All other transitions continue to give task cancellation precedence over event validation.
    public func recordingCancellation(
        expected: Fingerprint,
        operation: OperationToken,
        cancellation: Cancellation
    ) throws -> ComparisonLifecycleState {
        try applying(
            .cancel(
                expected: expected,
                operation: operation,
                cancellation: cancellation
            ),
            observesTaskCancellation: false
        )
    }

    /// Builds and records bounded cancellation metadata without observing caller task cancellation.
    public func recordingCancellation(
        expected: Fingerprint,
        operation: OperationToken,
        reason: CancellationReason,
        stage: Progress.Stage,
        detail: String? = nil
    ) throws -> ComparisonLifecycleState {
        let cancellation = try Cancellation(
            reason: reason,
            stage: stage,
            detail: detail,
            observesTaskCancellation: false
        )
        return try recordingCancellation(
            expected: expected,
            operation: operation,
            cancellation: cancellation
        )
    }

    private func applying(
        _ event: Event,
        observesTaskCancellation: Bool
    ) throws -> ComparisonLifecycleState {
        if observesTaskCancellation {
            try Self.checkCancellation()
        }
        var work = WorkBudget(
            limits: limits,
            observesTaskCancellation: observesTaskCancellation
        )
        guard try event.expectedFingerprint.matches(self, work: &work) else {
            throw StateError.staleState(
                expected: event.expectedFingerprint,
                actual: fingerprint
            )
        }
        if case .disabled(let reason) = availability(for: event.command) {
            throw StateError.commandDisabled(reason)
        }

        let nextGeneration = try advancedGeneration()
        let nextSnapshot: Snapshot

        switch event {
        case .loadFirstSide(_, let binding):
            nextSnapshot = replacing(
                generation: nextGeneration,
                phase: .oneSideLoaded,
                loadedSide: .value(binding)
            )
        case .unloadOnlySide(_, let binding):
            guard let loadedSide, loadedSide == binding else {
                throw StateError.sideBindingMismatch(
                    expected: loadedSide ?? binding,
                    actual: .some(binding)
                )
            }
            nextSnapshot = cleared(generation: nextGeneration)
        case .beginLoading(_, let inputs, let operationID, let declaredWorkUnits, let progress):
            try validateInitialInputs(inputs)
            try validateOperationStart(
                operationID: operationID,
                declaredWorkUnits: declaredWorkUnits,
                progress: progress,
                work: &work
            )
            let operation = makeOperation(
                kind: .initialLoad,
                operationID: operationID,
                startedAtGeneration: nextGeneration,
                inputs: inputs,
                declaredWorkUnits: declaredWorkUnits,
                progress: progress
            )
            nextSnapshot = replacing(
                generation: nextGeneration,
                phase: .loading,
                loadedSide: .value(nil),
                inputs: .value(inputs),
                operation: .value(operation),
                result: .value(nil),
                staleness: .value(nil),
                failure: .value(nil),
                cancellation: .value(nil)
            )
        case .markStale(_, let currentInputs, let reason):
            guard let result, let inputs else {
                throw StateError.commandDisabled(.noCurrentResult)
            }
            let resultInputs = result.inputs
            guard currentInputs != inputs else { throw StateError.unchangedInputs }
            if currentInputs == resultInputs {
                nextSnapshot = replacing(
                    generation: nextGeneration,
                    phase: .current,
                    inputs: .value(resultInputs),
                    result: .value(result),
                    staleness: .value(nil),
                    failure: .value(nil),
                    cancellation: .value(nil)
                )
                break
            }
            switch reason {
            case .sideChanged(let side), .externalChange(let side):
                guard resultInputs[side] != currentInputs[side] else {
                    throw StateError.invalidStaleSide(side)
                }
            case .optionsChanged:
                break
            case .comparisonModeChanged:
                guard resultInputs.isThreeWay != currentInputs.isThreeWay else {
                    throw StateError.unchangedComparisonMode
                }
            }
            let staleness = Staleness(
                reason: reason,
                invalidatedResult: result,
                currentInputs: currentInputs,
                detectedAtGeneration: nextGeneration
            )
            nextSnapshot = replacing(
                generation: nextGeneration,
                phase: .stale,
                inputs: .value(currentInputs),
                result: .value(result),
                staleness: .value(staleness),
                failure: .value(nil),
                cancellation: .value(nil)
            )
        case .beginRefreshing(_, let operationID, let declaredWorkUnits, let progress):
            guard let inputs, let result else {
                throw StateError.commandDisabled(.noResultToRefresh)
            }
            try validateOperationStart(
                operationID: operationID,
                declaredWorkUnits: declaredWorkUnits,
                progress: progress,
                work: &work
            )
            guard result.operation.operationID != operationID else {
                throw StateError.duplicateOperationID(operationID)
            }
            let operation = makeOperation(
                kind: .refresh,
                operationID: operationID,
                startedAtGeneration: nextGeneration,
                inputs: inputs,
                declaredWorkUnits: declaredWorkUnits,
                progress: progress
            )
            nextSnapshot = replacing(
                generation: nextGeneration,
                phase: .refreshing,
                operation: .value(operation),
                failure: .value(nil),
                cancellation: .value(nil)
            )
        case .updateProgress(_, let token, let progress):
            let operation = try activeOperation(matching: token)
            try Self.validate(progress, limits: limits, work: &work)
            try Self.validateProgressAdvance(from: operation.progress, to: progress)
            let updatedOperation = Operation(
                kind: operation.kind,
                token: operation.token,
                declaredWorkUnits: operation.declaredWorkUnits,
                progress: progress
            )
            nextSnapshot = replacing(
                generation: nextGeneration,
                operation: .value(updatedOperation)
            )
        case .complete(_, let token, let resultID):
            let operation = try activeOperation(matching: token)
            let result = ResultBinding(
                identity: resultID,
                inputs: operation.token.inputs,
                operation: operation.token,
                publishedAtGeneration: nextGeneration
            )
            nextSnapshot = replacing(
                generation: nextGeneration,
                phase: .current,
                inputs: .value(operation.token.inputs),
                operation: .value(nil),
                result: .value(result),
                staleness: .value(nil),
                failure: .value(nil),
                cancellation: .value(nil)
            )
        case .fail(_, let token, let failure):
            let operation = try activeOperation(matching: token)
            if let side = failure.side, operation.token.inputs[side] == nil {
                throw StateError.invalidFailureSide(side)
            }
            try Self.validate(
                failure,
                existingProgress: operation.progress,
                limits: limits,
                work: &work
            )
            guard failure.stage >= operation.progress.stage else {
                throw StateError.failureStageRegressed
            }
            let record = FailureRecord(
                operation: operation.token,
                lastProgress: operation.progress,
                failure: failure,
                recordedAtGeneration: nextGeneration
            )
            nextSnapshot = replacing(
                generation: nextGeneration,
                phase: .failed,
                operation: .value(nil),
                failure: .value(record),
                cancellation: .value(nil)
            )
        case .cancel(_, let token, let cancellation):
            let operation = try activeOperation(matching: token)
            try Self.validate(
                cancellation,
                existingProgress: operation.progress,
                limits: limits,
                work: &work
            )
            guard cancellation.stage >= operation.progress.stage else {
                throw StateError.cancellationStageRegressed
            }
            let record = CancellationRecord(
                operation: operation.token,
                lastProgress: operation.progress,
                cancellation: cancellation,
                recordedAtGeneration: nextGeneration
            )
            nextSnapshot = replacing(
                generation: nextGeneration,
                phase: .canceled,
                operation: .value(nil),
                failure: .value(nil),
                cancellation: .value(record)
            )
        case .reset:
            nextSnapshot = cleared(generation: nextGeneration)
        }

        try work.finish()
        return ComparisonLifecycleState(snapshot: nextSnapshot)
    }

    public func validate(_ fingerprint: Fingerprint) throws {
        try Self.checkCancellation()
        guard try fingerprint.matches(self) else {
            throw StateError.staleState(expected: fingerprint, actual: self.fingerprint)
        }
    }

    private init(snapshot: Snapshot) {
        identity = snapshot.identity
        generation = snapshot.generation
        limits = snapshot.limits
        phase = snapshot.phase
        loadedSide = snapshot.loadedSide
        inputs = snapshot.inputs
        operation = snapshot.operation
        result = snapshot.result
        staleness = snapshot.staleness
        failure = snapshot.failure
        cancellation = snapshot.cancellation
        self.snapshot = snapshot
    }

    private func replacing(
        generation: UInt64,
        phase: Phase? = nil,
        loadedSide: Replacement<SideBinding> = .preserve,
        inputs: Replacement<InputBinding> = .preserve,
        operation: Replacement<Operation> = .preserve,
        result: Replacement<ResultBinding> = .preserve,
        staleness: Replacement<Staleness> = .preserve,
        failure: Replacement<FailureRecord> = .preserve,
        cancellation: Replacement<CancellationRecord> = .preserve
    ) -> Snapshot {
        Snapshot(
            identity: identity,
            generation: generation,
            limits: limits,
            phase: phase ?? self.phase,
            loadedSide: loadedSide.resolving(self.loadedSide),
            inputs: inputs.resolving(self.inputs),
            operation: operation.resolving(self.operation),
            result: result.resolving(self.result),
            staleness: staleness.resolving(self.staleness),
            failure: failure.resolving(self.failure),
            cancellation: cancellation.resolving(self.cancellation)
        )
    }

    private func cleared(generation: UInt64) -> Snapshot {
        Snapshot(
            identity: identity,
            generation: generation,
            limits: limits,
            phase: .empty,
            loadedSide: nil,
            inputs: nil,
            operation: nil,
            result: nil,
            staleness: nil,
            failure: nil,
            cancellation: nil
        )
    }

    private func advancedGeneration() throws -> UInt64 {
        let (next, overflow) = generation.addingReportingOverflow(1)
        guard !overflow else { throw StateError.generationExhausted }
        return next
    }

    private func validateInitialInputs(_ candidate: InputBinding) throws {
        if phase == .oneSideLoaded, let loadedSide {
            guard candidate[loadedSide.side] == loadedSide else {
                throw StateError.sideBindingMismatch(
                    expected: loadedSide,
                    actual: candidate[loadedSide.side]
                )
            }
        }
        if phase == .failed || phase == .canceled, result == nil, let inputs {
            guard candidate == inputs else {
                throw StateError.inputBindingMismatch(expected: inputs, actual: candidate)
            }
        }
    }

    private func validateOperationStart(
        operationID: OperationID,
        declaredWorkUnits: UInt64,
        progress: Progress,
        work: inout WorkBudget
    ) throws {
        guard declaredWorkUnits <= limits.maximumDeclaredWorkUnits else {
            throw StateError.declaredWorkLimitExceeded(
                maximum: limits.maximumDeclaredWorkUnits
            )
        }
        try Self.validate(progress, limits: limits, work: &work)
    }

    private func makeOperation(
        kind: Operation.Kind,
        operationID: OperationID,
        startedAtGeneration: UInt64,
        inputs: InputBinding,
        declaredWorkUnits: UInt64,
        progress: Progress
    ) -> Operation {
        let token = OperationToken(
            comparisonIdentity: identity,
            operationID: operationID,
            startedAtGeneration: startedAtGeneration,
            inputs: inputs
        )
        return Operation(
            kind: kind,
            token: token,
            declaredWorkUnits: declaredWorkUnits,
            progress: progress
        )
    }

    private func activeOperation(matching token: OperationToken) throws -> Operation {
        guard let operation else {
            throw StateError.commandDisabled(.noActiveOperation)
        }
        guard operation.token == token else {
            throw StateError.staleOperation(expected: token, actual: operation.token)
        }
        return operation
    }

    private static func validate(_ limits: Limits) throws {
        guard limits.maximumFailureCodeUTF8Bytes > 0,
            limits.maximumFailureCodeUTF8Bytes <= Limits.hardMaximumFailureCodeUTF8Bytes
        else { throw StateError.invalidLimit(.failureCodeUTF8Bytes) }
        guard limits.maximumFailureMessageUTF8Bytes > 0,
            limits.maximumFailureMessageUTF8Bytes <= Limits.hardMaximumFailureMessageUTF8Bytes
        else { throw StateError.invalidLimit(.failureMessageUTF8Bytes) }
        guard limits.maximumProgressDetailUTF8Bytes > 0,
            limits.maximumProgressDetailUTF8Bytes <= Limits.hardMaximumProgressDetailUTF8Bytes
        else { throw StateError.invalidLimit(.progressDetailUTF8Bytes) }
        guard limits.maximumCancellationDetailUTF8Bytes > 0,
            limits.maximumCancellationDetailUTF8Bytes
                <= Limits.hardMaximumCancellationDetailUTF8Bytes
        else { throw StateError.invalidLimit(.cancellationDetailUTF8Bytes) }
        guard limits.maximumTotalMetadataUTF8Bytes > 0,
            limits.maximumTotalMetadataUTF8Bytes <= Limits.hardMaximumTotalMetadataUTF8Bytes,
            limits.maximumTotalMetadataUTF8Bytes >= limits.maximumFailureCodeUTF8Bytes,
            limits.maximumTotalMetadataUTF8Bytes >= limits.maximumFailureMessageUTF8Bytes,
            limits.maximumTotalMetadataUTF8Bytes >= limits.maximumProgressDetailUTF8Bytes,
            limits.maximumTotalMetadataUTF8Bytes >= limits.maximumCancellationDetailUTF8Bytes
        else { throw StateError.invalidLimit(.totalMetadataUTF8Bytes) }
        guard limits.maximumProgressUnitCount > 0,
            limits.maximumProgressUnitCount <= Limits.hardMaximumProgressUnitCount
        else { throw StateError.invalidLimit(.progressUnitCount) }
        guard limits.maximumDeclaredWorkUnits > 0,
            limits.maximumDeclaredWorkUnits <= Limits.hardMaximumDeclaredWorkUnits
        else { throw StateError.invalidLimit(.declaredWorkUnits) }
        guard limits.maximumTransitionWorkUnits > 0,
            limits.maximumTransitionWorkUnits <= Limits.hardMaximumTransitionWorkUnits
        else { throw StateError.invalidLimit(.transitionWorkUnits) }
        guard limits.cancellationCheckInterval > 0,
            limits.cancellationCheckInterval <= limits.maximumTransitionWorkUnits
        else { throw StateError.invalidLimit(.cancellationCheckInterval) }
    }

    private static func validate(
        _ progress: Progress,
        limits: Limits,
        work: inout WorkBudget
    ) throws {
        guard progress.completedUnitCount <= limits.maximumProgressUnitCount else {
            throw StateError.progressUnitLimitExceeded(
                maximum: limits.maximumProgressUnitCount
            )
        }
        if let total = progress.totalUnitCount {
            guard total > 0, progress.completedUnitCount <= total else {
                throw StateError.invalidProgressTotal
            }
            guard total <= limits.maximumProgressUnitCount else {
                throw StateError.progressUnitLimitExceeded(
                    maximum: limits.maximumProgressUnitCount
                )
            }
        }
        var totalMetadataBytes = 0
        if let detail = progress.detail {
            try validateText(
                detail,
                field: .progressDetail,
                maximumBytes: limits.maximumProgressDetailUTF8Bytes,
                totalBytes: &totalMetadataBytes,
                limits: limits,
                work: &work
            )
        }
    }

    private static func validateProgressAdvance(from old: Progress, to new: Progress) throws {
        guard new.stage >= old.stage else { throw StateError.progressRegressed }
        guard new.stage == old.stage else { return }
        guard new.completedUnitCount >= old.completedUnitCount else {
            throw StateError.progressRegressed
        }
        guard old.totalUnitCount == nil || old.totalUnitCount == new.totalUnitCount else {
            throw StateError.progressTotalChanged
        }
    }

    private static func validate(
        _ failure: Failure,
        existingProgress: Progress,
        limits: Limits,
        work: inout WorkBudget
    ) throws {
        var totalMetadataBytes = try validatedTextByteCount(
            existingProgress.detail,
            field: .progressDetail,
            maximumBytes: limits.maximumProgressDetailUTF8Bytes,
            limits: limits,
            work: &work
        )
        let codeBytes = try validateFailureCode(
            failure.code,
            maximumBytes: limits.maximumFailureCodeUTF8Bytes,
            work: &work
        )
        try addMetadataBytes(codeBytes, total: &totalMetadataBytes, limits: limits)
        try validateText(
            failure.message,
            field: .failureMessage,
            maximumBytes: limits.maximumFailureMessageUTF8Bytes,
            totalBytes: &totalMetadataBytes,
            limits: limits,
            work: &work
        )
        guard !failure.message.isEmpty else {
            throw StateError.invalidMetadataText(.failureMessage)
        }
    }

    private static func validate(
        _ cancellation: Cancellation,
        existingProgress: Progress,
        limits: Limits,
        work: inout WorkBudget
    ) throws {
        guard let detail = cancellation.detail else { return }
        var totalMetadataBytes = try validatedTextByteCount(
            existingProgress.detail,
            field: .progressDetail,
            maximumBytes: limits.maximumProgressDetailUTF8Bytes,
            limits: limits,
            work: &work
        )
        try validateText(
            detail,
            field: .cancellationDetail,
            maximumBytes: limits.maximumCancellationDetailUTF8Bytes,
            totalBytes: &totalMetadataBytes,
            limits: limits,
            work: &work
        )
        guard !detail.isEmpty else {
            throw StateError.invalidMetadataText(.cancellationDetail)
        }
    }

    private static func validateFailureCode(
        _ value: String,
        maximumBytes: Int,
        work: inout WorkBudget
    ) throws -> Int {
        var count = 0
        for byte in value.utf8 {
            try work.charge()
            guard count < maximumBytes else {
                throw StateError.metadataTooLarge(
                    field: .failureCode,
                    maximumBytes: maximumBytes
                )
            }
            guard
                (0x30...0x39).contains(byte)
                    || (0x41...0x5A).contains(byte)
                    || (0x61...0x7A).contains(byte)
                    || byte == 0x2D || byte == 0x2E || byte == 0x5F
            else { throw StateError.invalidFailureCode }
            count += 1
        }
        guard count > 0 else { throw StateError.invalidFailureCode }
        return count
    }

    private static func validateText(
        _ value: String,
        field: MetadataField,
        maximumBytes: Int,
        totalBytes: inout Int,
        limits: Limits,
        work: inout WorkBudget
    ) throws {
        let count = try validatedTextByteCount(
            value,
            field: field,
            maximumBytes: maximumBytes,
            limits: limits,
            work: &work
        )
        try addMetadataBytes(count, total: &totalBytes, limits: limits)
    }

    private static func validatedTextByteCount(
        _ value: String?,
        field: MetadataField,
        maximumBytes: Int,
        limits: Limits,
        work: inout WorkBudget
    ) throws -> Int {
        guard let value else { return 0 }
        var count = 0
        for scalar in value.unicodeScalars {
            let scalarValue = scalar.value
            guard
                scalarValue == 0x09 || scalarValue == 0x0A || scalarValue == 0x0D
                    || (scalarValue >= 0x20 && !(0x7F...0x9F).contains(scalarValue))
            else { throw StateError.invalidMetadataText(field) }

            let scalarByteCount = scalar.utf8.count
            try work.charge(scalarByteCount)
            guard scalarByteCount <= maximumBytes - count else {
                throw StateError.metadataTooLarge(
                    field: field,
                    maximumBytes: maximumBytes
                )
            }
            count += scalarByteCount
        }
        guard count <= limits.maximumTotalMetadataUTF8Bytes else {
            throw StateError.totalMetadataTooLarge(
                maximumBytes: limits.maximumTotalMetadataUTF8Bytes
            )
        }
        return count
    }

    private static func addMetadataBytes(
        _ count: Int,
        total: inout Int,
        limits: Limits
    ) throws {
        guard count <= limits.maximumTotalMetadataUTF8Bytes - total else {
            throw StateError.totalMetadataTooLarge(
                maximumBytes: limits.maximumTotalMetadataUTF8Bytes
            )
        }
        total += count
    }

    private static func validateStandaloneFailureCode(
        _ value: String,
        maximumBytes: Int
    ) throws {
        try checkCancellation()
        var count = 0
        for byte in value.utf8 {
            guard count < maximumBytes else {
                throw StateError.metadataTooLarge(
                    field: .failureCode,
                    maximumBytes: maximumBytes
                )
            }
            guard
                (0x30...0x39).contains(byte)
                    || (0x41...0x5A).contains(byte)
                    || (0x61...0x7A).contains(byte)
                    || byte == 0x2D || byte == 0x2E || byte == 0x5F
            else { throw StateError.invalidFailureCode }
            count += 1
        }
        guard count > 0 else { throw StateError.invalidFailureCode }
        try checkCancellation()
    }

    private static func validateStandaloneText(
        _ value: String,
        field: MetadataField,
        maximumBytes: Int,
        allowsEmpty: Bool,
        observesTaskCancellation: Bool = true
    ) throws {
        if observesTaskCancellation {
            try checkCancellation()
        }
        var count = 0
        var countAtLastCancellationCheck = 0
        for scalar in value.unicodeScalars {
            let scalarValue = scalar.value
            guard
                scalarValue == 0x09 || scalarValue == 0x0A || scalarValue == 0x0D
                    || (scalarValue >= 0x20 && !(0x7F...0x9F).contains(scalarValue))
            else { throw StateError.invalidMetadataText(field) }

            let scalarByteCount = scalar.utf8.count
            guard scalarByteCount <= maximumBytes - count else {
                throw StateError.metadataTooLarge(
                    field: field,
                    maximumBytes: maximumBytes
                )
            }
            count += scalarByteCount
            if observesTaskCancellation,
                count - countAtLastCancellationCheck >= 4_096
            {
                try checkCancellation()
                countAtLastCancellationCheck = count
            }
        }
        guard allowsEmpty || count > 0 else {
            throw StateError.invalidMetadataText(field)
        }
        if observesTaskCancellation {
            try checkCancellation()
        }
    }

    private static func checkCancellation() throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw StateError.cancelled
        }
    }

    fileprivate struct Snapshot: Equatable, Hashable, Sendable {
        let identity: Identity
        let generation: UInt64
        let limits: Limits
        let phase: Phase
        let loadedSide: SideBinding?
        let inputs: InputBinding?
        let operation: Operation?
        let result: ResultBinding?
        let staleness: Staleness?
        let failure: FailureRecord?
        let cancellation: CancellationRecord?

        fileprivate func matches(_ other: Snapshot, work: inout WorkBudget) throws -> Bool {
            guard identity == other.identity,
                generation == other.generation,
                limits == other.limits,
                phase == other.phase,
                loadedSide == other.loadedSide,
                inputs == other.inputs,
                result == other.result,
                staleness == other.staleness
            else { return false }
            guard try Self.matches(operation, other.operation, work: &work) else {
                return false
            }
            guard try Self.matches(failure, other.failure, work: &work) else {
                return false
            }
            return try Self.matches(cancellation, other.cancellation, work: &work)
        }

        private static func matches(
            _ left: Operation?,
            _ right: Operation?,
            work: inout WorkBudget
        ) throws -> Bool {
            switch (left, right) {
            case (nil, nil):
                return true
            case (.some(let left), .some(let right)):
                guard left.kind == right.kind,
                    left.token == right.token,
                    left.declaredWorkUnits == right.declaredWorkUnits
                else { return false }
                return try matches(left.progress, right.progress, work: &work)
            case (nil, .some), (.some, nil):
                return false
            }
        }

        private static func matches(
            _ left: FailureRecord?,
            _ right: FailureRecord?,
            work: inout WorkBudget
        ) throws -> Bool {
            switch (left, right) {
            case (nil, nil):
                return true
            case (.some(let left), .some(let right)):
                guard left.operation == right.operation,
                    left.recordedAtGeneration == right.recordedAtGeneration,
                    left.failure.kind == right.failure.kind,
                    left.failure.stage == right.failure.stage,
                    left.failure.side == right.failure.side,
                    left.failure.isRetryable == right.failure.isRetryable,
                    try matches(left.lastProgress, right.lastProgress, work: &work),
                    try matches(left.failure.code, right.failure.code, work: &work)
                else { return false }
                return try matches(left.failure.message, right.failure.message, work: &work)
            case (nil, .some), (.some, nil):
                return false
            }
        }

        private static func matches(
            _ left: CancellationRecord?,
            _ right: CancellationRecord?,
            work: inout WorkBudget
        ) throws -> Bool {
            switch (left, right) {
            case (nil, nil):
                return true
            case (.some(let left), .some(let right)):
                guard left.operation == right.operation,
                    left.recordedAtGeneration == right.recordedAtGeneration,
                    left.cancellation.reason == right.cancellation.reason,
                    left.cancellation.stage == right.cancellation.stage,
                    try matches(left.lastProgress, right.lastProgress, work: &work)
                else { return false }
                return try matches(
                    left.cancellation.detail,
                    right.cancellation.detail,
                    work: &work
                )
            case (nil, .some), (.some, nil):
                return false
            }
        }

        private static func matches(
            _ left: Progress,
            _ right: Progress,
            work: inout WorkBudget
        ) throws -> Bool {
            guard left.stage == right.stage,
                left.completedUnitCount == right.completedUnitCount,
                left.totalUnitCount == right.totalUnitCount
            else { return false }
            return try matches(left.detail, right.detail, work: &work)
        }

        private static func matches(
            _ left: String?,
            _ right: String?,
            work: inout WorkBudget
        ) throws -> Bool {
            switch (left, right) {
            case (nil, nil):
                return true
            case (.some(let left), .some(let right)):
                return try matches(left, right, work: &work)
            case (nil, .some), (.some, nil):
                return false
            }
        }

        private static func matches(
            _ left: String,
            _ right: String,
            work: inout WorkBudget
        ) throws -> Bool {
            var leftIterator = left.utf8.makeIterator()
            var rightIterator = right.utf8.makeIterator()
            while true {
                let leftByte = leftIterator.next()
                let rightByte = rightIterator.next()
                guard leftByte != nil || rightByte != nil else { return true }
                try work.charge()
                guard leftByte == rightByte else { return false }
            }
        }
    }

    private enum Replacement<Value> {
        case preserve
        case value(Value?)

        func resolving(_ current: Value?) -> Value? {
            switch self {
            case .preserve: current
            case .value(let value): value
            }
        }
    }

    fileprivate struct WorkBudget {
        let limits: Limits
        let observesTaskCancellation: Bool
        private var completedWork = 0
        private var workAtLastCancellationCheck = 0

        init(limits: Limits, observesTaskCancellation: Bool = true) {
            self.limits = limits
            self.observesTaskCancellation = observesTaskCancellation
        }

        mutating func charge(_ amount: Int = 1) throws {
            guard amount >= 0,
                amount <= limits.maximumTransitionWorkUnits,
                completedWork <= limits.maximumTransitionWorkUnits - amount
            else {
                if observesTaskCancellation {
                    try ComparisonLifecycleState.checkCancellation()
                }
                throw StateError.workLimitExceeded(
                    maximum: limits.maximumTransitionWorkUnits
                )
            }
            completedWork += amount
            if observesTaskCancellation,
                completedWork - workAtLastCancellationCheck >= limits.cancellationCheckInterval
            {
                try ComparisonLifecycleState.checkCancellation()
                workAtLastCancellationCheck = completedWork
            }
        }

        mutating func finish() throws {
            if observesTaskCancellation {
                try ComparisonLifecycleState.checkCancellation()
            }
            workAtLastCancellationCheck = completedWork
        }
    }
}
