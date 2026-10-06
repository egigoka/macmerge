import CryptoKit
import Foundation

public enum ReportDeliveryItemKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case regularFile
    case directory
}

public struct ReportDeliveryCanonicalFileIdentity: Equatable, Hashable, Sendable {
    public let canonicalURL: URL
    public let kind: ReportDeliveryItemKind
    public let deviceID: UInt64
    public let fileID: UInt64
    public let generation: UInt32

    public init(canonicalURL: URL, kind: ReportDeliveryItemKind, deviceID: UInt64, fileID: UInt64, generation: UInt32) {
        self.canonicalURL = canonicalURL
        self.kind = kind
        self.deviceID = deviceID
        self.fileID = fileID
        self.generation = generation
    }
}

public enum ReportDeliveryAuthorityCoverage: String, CaseIterable, Equatable, Hashable, Sendable {
    case exactItem
    case directoryTree
}

public enum ReportDeliveryAccessAuthority: Equatable, Hashable, Sendable {
    case ambient
    case callerManagedWhenRequired
    case securityScoped(resourceURL: URL, coverage: ReportDeliveryAuthorityCoverage)
}

public struct ReportDeliveryFileRevision: Equatable, Hashable, Sendable {
    public let identity: ReportDeliveryCanonicalFileIdentity
    public let byteCount: UInt64
    public let linkCount: UInt64
    public let permissions: UInt16
    public let metadataByteCount: UInt64
    public let contentSHA256: [UInt8]
    public let metadataSHA256: [UInt8]

    public init(
        identity: ReportDeliveryCanonicalFileIdentity, byteCount: UInt64, linkCount: UInt64, permissions: UInt16, metadataByteCount: UInt64,
        contentSHA256: [UInt8], metadataSHA256: [UInt8]
    ) {
        self.identity = identity
        self.byteCount = byteCount
        self.linkCount = linkCount
        self.permissions = permissions
        self.metadataByteCount = metadataByteCount
        self.contentSHA256 = contentSHA256
        self.metadataSHA256 = metadataSHA256
    }
}

public struct ReportDeliveryExistingFileSnapshot: Equatable, Sendable {
    public let revision: ReportDeliveryFileRevision
    public let data: Data

    public init(revision: ReportDeliveryFileRevision, data: Data) throws {
        guard data.count <= ReportDeliveryLimits.hardMaximumExistingFileBytes else {
            throw ReportDeliveryError.existingFileTooLarge(maximumBytes: ReportDeliveryLimits.hardMaximumExistingFileBytes)
        }
        self.revision = revision
        self.data = Data(data)
    }
}

public struct ReportDeliveryClipboardRevision: Equatable, Hashable, Sendable {
    public let brokerIdentifier: UUID
    public let epoch: UUID
    public let value: UInt64

    public init(brokerIdentifier: UUID, epoch: UUID, value: UInt64) {
        self.brokerIdentifier = brokerIdentifier
        self.epoch = epoch
        self.value = value
    }
}

public enum ReportDeliveryFileExpectation: Equatable, Sendable {
    case createNew(parent: ReportDeliveryCanonicalFileIdentity)
    case replaceExisting(parent: ReportDeliveryCanonicalFileIdentity, expected: ReportDeliveryFileRevision)
    case appendExisting(parent: ReportDeliveryCanonicalFileIdentity, expected: ReportDeliveryExistingFileSnapshot)
}

public enum ReportDeliveryDestinationExpectation: Equatable, Sendable {
    case file(expectation: ReportDeliveryFileExpectation, authority: ReportDeliveryAccessAuthority)
    case clipboard(expectedRevision: ReportDeliveryClipboardRevision)
}

public enum ReportDeliveryLimit: String, CaseIterable, Equatable, Hashable, Sendable {
    case outputs
    case successorBytes
    case totalSuccessorBytes
    case existingFileBytes
    case pathBytes
    case totalPathBytes
    case workUnits
    case cancellationCheckInterval
}

public struct ReportDeliveryLimits: Equatable, Sendable {
    public static let hardMaximumOutputCount = 4_096
    public static let hardMaximumSuccessorBytes = 512 * 1_024 * 1_024
    public static let hardMaximumTotalSuccessorBytes = 768 * 1_024 * 1_024
    public static let hardMaximumExistingFileBytes = 256 * 1_024 * 1_024
    public static let hardMaximumPathBytes = 16 * 1_024
    public static let hardMaximumTotalPathBytes = 16 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 40
    public static let `default` = ReportDeliveryLimits()

    public let maximumOutputs: Int
    public let maximumSuccessorBytes: Int
    public let maximumTotalSuccessorBytes: Int
    public let maximumExistingFileBytes: Int
    public let maximumPathBytes: Int
    public let maximumTotalPathBytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: Int

    public init(
        maximumOutputs: Int = 1_024, maximumSuccessorBytes: Int = 128 * 1_024 * 1_024, maximumTotalSuccessorBytes: Int = 192 * 1_024 * 1_024,
        maximumExistingFileBytes: Int = 64 * 1_024 * 1_024, maximumPathBytes: Int = 4 * 1_024, maximumTotalPathBytes: Int = 4 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 2 * 1_024 * 1_024 * 1_024, cancellationCheckInterval: Int = 256
    ) {
        self.maximumOutputs = maximumOutputs
        self.maximumSuccessorBytes = maximumSuccessorBytes
        self.maximumTotalSuccessorBytes = maximumTotalSuccessorBytes
        self.maximumExistingFileBytes = maximumExistingFileBytes
        self.maximumPathBytes = maximumPathBytes
        self.maximumTotalPathBytes = maximumTotalPathBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public struct ReportDeliveryRequest: Equatable, Sendable {
    public let plan: ComparisonReportWorkflowPlan
    public let expectations: [ReportDeliveryDestinationExpectation]
    public let limits: ReportDeliveryLimits

    public init(plan: ComparisonReportWorkflowPlan, expectations: [ReportDeliveryDestinationExpectation], limits: ReportDeliveryLimits = .default) {
        self.plan = plan
        self.expectations = expectations
        self.limits = limits
    }
}

public enum ReportDeliveryError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(ReportDeliveryLimit)
    case expectationCountMismatch(expected: Int, actual: Int)
    case unsupportedExpectation(String)
    case destinationMismatch(String)
    case invalidFileURL(String)
    case invalidCanonicalIdentity(String)
    case invalidFileRevision(String)
    case existingFileTooLarge(maximumBytes: Int)
    case existingSnapshotMismatch(String)
    case successorTooLarge(maximumBytes: Int)
    case totalSuccessorTooLarge(maximumBytes: Int)
    case totalPathsTooLarge(maximumBytes: Int)
    case invalidAuthority(String)
    case authorityDoesNotCoverOutput(String)
    case workLimitExceeded(maximumUnits: UInt64)
    case staleSnapshot
    case snapshotContentsChanged
    case arithmeticOverflow

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Report delivery planning was cancelled."
        case .invalidLimit(let limit):
            "Invalid report-delivery limit: \(limit.rawValue)."
        case .expectationCountMismatch(let expected, let actual):
            "Report delivery expects \(expected) expectations, not \(actual)."
        case .unsupportedExpectation(let detail):
            "Unsupported report delivery expectation: \(detail)."
        case .destinationMismatch(let path):
            "Report delivery destination does not match expectation: \(path)."
        case .invalidFileURL(let value):
            "Report delivery destination is not a strict absolute local file URL: \(value)."
        case .invalidCanonicalIdentity(let path):
            "Report delivery file identity is not canonical: \(path)."
        case .invalidFileRevision(let path):
            "Report delivery file revision is invalid: \(path)."
        case .existingFileTooLarge(let maximum):
            "Existing report delivery file exceeds \(maximum) bytes."
        case .existingSnapshotMismatch(let path):
            "Existing report delivery bytes do not match revision: \(path)."
        case .successorTooLarge(let maximum):
            "Report delivery successor exceeds \(maximum) bytes."
        case .totalSuccessorTooLarge(let maximum):
            "Report delivery successors exceed \(maximum) bytes."
        case .totalPathsTooLarge(let maximum):
            "Report delivery paths exceed \(maximum) total UTF-8 bytes."
        case .invalidAuthority(let detail):
            "Report delivery authority is invalid: \(detail)."
        case .authorityDoesNotCoverOutput(let path):
            "Report delivery authority does not cover output: \(path)."
        case .workLimitExceeded(let maximum):
            "Report delivery exceeds the \(maximum)-unit work limit."
        case .staleSnapshot:
            "Report delivery plan belongs to a stale snapshot."
        case .snapshotContentsChanged:
            "Report snapshot changed without advancing generation."
        case .arithmeticOverflow:
            "Report delivery size calculation overflowed."
        }
    }
}

public enum ReportDeliveryDisposition: String, Equatable, Hashable, Sendable {
    case created
    case replaced
    case appended
    case copiedToClipboard
}

public enum ReportDeliveryPlannedEffect: Equatable, Sendable {
    case file(url: URL, successor: Data, operation: ReportDeliveryFileExpectation)
    case clipboard(text: String, expectedRevision: ReportDeliveryClipboardRevision)
}

public struct ReportDeliveryPlannedOutput: Equatable, Sendable {
    public let role: ComparisonReportPlannedOutputRole
    public let identity: ComparisonReportOutputIdentity
    public let effect: ReportDeliveryPlannedEffect
    public let disposition: ReportDeliveryDisposition
    public let successorByteCount: Int
    public let successorSHA256: [UInt8]

    fileprivate init(
        role: ComparisonReportPlannedOutputRole, identity: ComparisonReportOutputIdentity, effect: ReportDeliveryPlannedEffect,
        disposition: ReportDeliveryDisposition, successorByteCount: Int, successorSHA256: [UInt8]
    ) {
        self.role = role
        self.identity = identity
        self.effect = effect
        self.disposition = disposition
        self.successorByteCount = successorByteCount
        self.successorSHA256 = successorSHA256
    }
}

public struct ReportDeliveryPlanningReceipt: Equatable, Sendable {
    public let snapshot: ComparisonReportWorkflowSnapshotReference
    public let outputCount: Int
    public let successorByteCount: Int
    public let planSHA256: [UInt8]
    public let estimatedWorkUnits: UInt64

    fileprivate init(
        snapshot: ComparisonReportWorkflowSnapshotReference, outputCount: Int, successorByteCount: Int, planSHA256: [UInt8], estimatedWorkUnits: UInt64
    ) {
        self.snapshot = snapshot
        self.outputCount = outputCount
        self.successorByteCount = successorByteCount
        self.planSHA256 = planSHA256
        self.estimatedWorkUnits = estimatedWorkUnits
    }
}

public enum ReportDeliveryPathResolutionContract: String, Equatable, Hashable, Sendable {
    case descriptorRelativeNoFollowFromPinnedCanonicalParent
}

public enum ReportDeliveryPublicationContract: String, Equatable, Hashable, Sendable {
    case privateStageSyncThenAtomicCreateOrExactReplacementInPlanOrder
}

public enum ReportDeliverySnapshotContract: String, Equatable, Hashable, Sendable {
    case validateExactSnapshotAndDestinationCASBeforeEffects
}

public enum ReportDeliveryCancellationContract: String, Equatable, Hashable, Sendable {
    case noMutationBeforePublicationThenCommittedCompareMissOrUncertain
}

public struct ReportDeliveryExecutorContract: Equatable, Hashable, Sendable {
    public static let required = ReportDeliveryExecutorContract()
    public let pathResolution = ReportDeliveryPathResolutionContract.descriptorRelativeNoFollowFromPinnedCanonicalParent
    public let publication = ReportDeliveryPublicationContract.privateStageSyncThenAtomicCreateOrExactReplacementInPlanOrder
    public let snapshot = ReportDeliverySnapshotContract.validateExactSnapshotAndDestinationCASBeforeEffects
    public let cancellation = ReportDeliveryCancellationContract.noMutationBeforePublicationThenCommittedCompareMissOrUncertain

    public init() {}
}

public struct ReportDeliveryPlan: Equatable, Sendable {
    public let source: ComparisonReportWorkflowPlan
    public let outputs: [ReportDeliveryPlannedOutput]
    public let receipt: ReportDeliveryPlanningReceipt
    public let limits: ReportDeliveryLimits
    public let executorContract: ReportDeliveryExecutorContract

    fileprivate init(
        source: ComparisonReportWorkflowPlan, outputs: [ReportDeliveryPlannedOutput], receipt: ReportDeliveryPlanningReceipt, limits: ReportDeliveryLimits
    ) {
        self.source = source
        self.outputs = outputs
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public func validateCurrentSnapshot(_ snapshot: ComparisonReportWorkflowSnapshot, linkedReports: [ComparisonReportLinkedReport]) throws {
        do {
            try source.validateCurrentSnapshot(snapshot, linkedReports: linkedReports)
        } catch let error as ComparisonReportWorkflowError {
            switch error {
            case .snapshotIdentityChanged, .snapshotGenerationChanged:
                throw ReportDeliveryError.staleSnapshot
            case .cancelled:
                throw ReportDeliveryError.cancelled
            default:
                throw ReportDeliveryError.snapshotContentsChanged
            }
        }
    }

    public func validateForPublication(
        currentSnapshot: ComparisonReportWorkflowSnapshot, linkedReports: [ComparisonReportLinkedReport], currentRevisions: [ReportDeliveryFileRevision?],
        currentClipboardRevision: ReportDeliveryClipboardRevision?
    ) throws {
        try validateCurrentSnapshot(currentSnapshot, linkedReports: linkedReports)
        try Task.checkCancellation()
        guard currentRevisions.count == outputs.count else {
            throw ReportDeliveryError.expectationCountMismatch(expected: outputs.count, actual: currentRevisions.count)
        }
        for (index, planned) in outputs.enumerated() {
            switch planned.effect {
            case .file(_, _, let operation):
                switch operation {
                case .createNew:
                    guard currentRevisions[index] == nil else {
                        throw ReportDeliveryError.destinationMismatch(planned.identity.displayPath)
                    }
                case .replaceExisting(_, let expected):
                    guard currentRevisions[index] == expected else {
                        throw ReportDeliveryError.destinationMismatch(planned.identity.displayPath)
                    }
                case .appendExisting(_, let existing):
                    guard currentRevisions[index] == existing.revision else {
                        throw ReportDeliveryError.destinationMismatch(planned.identity.displayPath)
                    }
                }
            case .clipboard(_, let expected):
                guard currentClipboardRevision == expected else {
                    throw ReportDeliveryError.destinationMismatch("clipboard")
                }
            }
        }
    }
}

public enum ReportDeliveryWorkflow: Sendable {
    public static func plan(_ request: ReportDeliveryRequest) throws -> ReportDeliveryPlan {
        do {
            return try makePlan(request)
        } catch is CancellationError {
            throw ReportDeliveryError.cancelled
        }
    }

    fileprivate static func makePlan(_ request: ReportDeliveryRequest) throws -> ReportDeliveryPlan {
        try Task.checkCancellation()
        try validate(request.limits)
        let planned = request.plan.outputs
        guard planned.count <= request.limits.maximumOutputs else {
            throw ReportDeliveryError.invalidLimit(.outputs)
        }
        guard request.expectations.count == planned.count else {
            throw ReportDeliveryError.expectationCountMismatch(expected: planned.count, actual: request.expectations.count)
        }
        var work = ReportDeliveryWorkBudget(limits: request.limits)
        var delivered: [ReportDeliveryPlannedOutput] = []
        delivered.reserveCapacity(planned.count)
        var totalSuccessorBytes = 0
        var totalPathBytes = 0
        for (index, output) in planned.enumerated() {
            try work.checkpoint()
            let built = try deliver(
                output: output, expectation: request.expectations[index], limits: request.limits, work: &work, totalPathBytes: &totalPathBytes)
            totalSuccessorBytes = try boundedAdd(
                built.successorByteCount, to: totalSuccessorBytes, maximum: request.limits.maximumTotalSuccessorBytes,
                error: .totalSuccessorTooLarge(maximumBytes: request.limits.maximumTotalSuccessorBytes))
            delivered.append(built)
        }
        try Task.checkCancellation()
        let snapshot = request.plan.snapshotFingerprint.reference
        let digest = try deliveryDigest(outputs: delivered, snapshot: snapshot, work: &work)
        return ReportDeliveryPlan(
            source: request.plan, outputs: delivered,
            receipt: ReportDeliveryPlanningReceipt(
                snapshot: snapshot, outputCount: delivered.count, successorByteCount: totalSuccessorBytes, planSHA256: digest, estimatedWorkUnits: work.consumed
            ), limits: request.limits)
    }
}

public struct ReportDeliveryCommitRecord: Equatable, Sendable {
    public let role: ComparisonReportPlannedOutputRole
    public let identity: ComparisonReportOutputIdentity
    public let disposition: ReportDeliveryDisposition
    public let byteCount: Int

    fileprivate init(role: ComparisonReportPlannedOutputRole, identity: ComparisonReportOutputIdentity, disposition: ReportDeliveryDisposition, byteCount: Int)
    {
        self.role = role
        self.identity = identity
        self.disposition = disposition
        self.byteCount = byteCount
    }
}

public struct ReportDeliveryCommitReceipt: Equatable, Sendable {
    public let snapshot: ComparisonReportWorkflowSnapshotReference
    public let records: [ReportDeliveryCommitRecord]
    public let planSHA256: [UInt8]

    fileprivate init(snapshot: ComparisonReportWorkflowSnapshotReference, records: [ReportDeliveryCommitRecord], planSHA256: [UInt8]) {
        self.snapshot = snapshot
        self.records = records
        self.planSHA256 = planSHA256
    }
}

public enum ReportDeliveryNonCommitReason: Equatable, Sendable {
    case cancelled
    case sourceChanged
    case destinationChanged
    case securityContractUnavailable
    case rejected(String)
    case failed(String)
}

public struct ReportDeliveryUncertainty: Equatable, Sendable {
    public let completedRecords: [ReportDeliveryCommitRecord]
    public let reason: String

    fileprivate init(completedRecords: [ReportDeliveryCommitRecord], reason: String) {
        self.completedRecords = completedRecords
        self.reason = reason
    }
}

public enum ReportDeliveryExecutionOutcome: Equatable, Sendable {
    case committed(ReportDeliveryCommitReceipt)
    case notCommitted(ReportDeliveryNonCommitReason)
    case commitUncertain(ReportDeliveryUncertainty)
}

public protocol ReportDeliveryPlanExecutor: Sendable {
    func execute(_ plan: ReportDeliveryPlan, validating currentSnapshot: ComparisonReportWorkflowSnapshot, linkedReports: [ComparisonReportLinkedReport]) async
        -> ReportDeliveryExecutionOutcome
}

public enum ReportDeliveryExecutionOutcomeFactory: Sendable {
    public static func committed(plan: ReportDeliveryPlan, dispositions: [ReportDeliveryDisposition]) -> ReportDeliveryExecutionOutcome {
        guard let records = commitRecords(plan: plan, dispositions: dispositions) else {
            return .notCommitted(.failed("Delivery commit evidence does not match plan."))
        }
        return .committed(ReportDeliveryCommitReceipt(snapshot: plan.receipt.snapshot, records: records, planSHA256: plan.receipt.planSHA256))
    }

    public static func notCommitted(plan: ReportDeliveryPlan, completedDispositions: [ReportDeliveryDisposition], reason: ReportDeliveryNonCommitReason)
        -> ReportDeliveryExecutionOutcome
    {
        guard let records = commitPrefix(plan: plan, dispositions: completedDispositions), completedDispositions.count < plan.outputs.count else {
            return .notCommitted(.failed("Delivery non-commit evidence does not match plan."))
        }
        _ = records
        return .notCommitted(reason)
    }

    public static func uncertain(plan: ReportDeliveryPlan, completedDispositions: [ReportDeliveryDisposition], reason: String) -> ReportDeliveryExecutionOutcome
    {
        guard let records = commitPrefix(plan: plan, dispositions: completedDispositions), completedDispositions.count < plan.outputs.count else {
            return .commitUncertain(ReportDeliveryUncertainty(completedRecords: [], reason: "Delivery uncertainty evidence does not match plan."))
        }
        return .commitUncertain(ReportDeliveryUncertainty(completedRecords: records, reason: reason))
    }

    fileprivate static func commitRecords(plan: ReportDeliveryPlan, dispositions: [ReportDeliveryDisposition]) -> [ReportDeliveryCommitRecord]? {
        guard dispositions.count == plan.outputs.count else { return nil }
        return commitPrefix(plan: plan, dispositions: dispositions)
    }

    fileprivate static func commitPrefix(plan: ReportDeliveryPlan, dispositions: [ReportDeliveryDisposition]) -> [ReportDeliveryCommitRecord]? {
        guard dispositions.count <= plan.outputs.count else { return nil }
        var records: [ReportDeliveryCommitRecord] = []
        records.reserveCapacity(dispositions.count)
        for (index, disposition) in dispositions.enumerated() {
            let planned = plan.outputs[index]
            guard disposition == planned.disposition else { return nil }
            records.append(
                ReportDeliveryCommitRecord(role: planned.role, identity: planned.identity, disposition: disposition, byteCount: planned.successorByteCount))
        }
        return records
    }
}

extension ComparisonReportOutputIdentity {
    fileprivate var displayPath: String {
        switch self {
        case .file(let identity):
            identity.canonicalPath
        case .clipboard:
            "clipboard"
        }
    }
}

extension ReportDeliveryWorkflow {
    fileprivate static func deliver(
        output: ComparisonReportPlannedOutput, expectation: ReportDeliveryDestinationExpectation, limits: ReportDeliveryLimits,
        work: inout ReportDeliveryWorkBudget, totalPathBytes: inout Int
    ) throws -> ReportDeliveryPlannedOutput {
        switch output.destination {
        case .clipboard:
            switch expectation {
            case .clipboard(let expectedRevision):
                let text = String(decoding: output.output.data, as: UTF8.self)
                try work.consume(UInt64(output.outputByteCount) + 64)
                return ReportDeliveryPlannedOutput(
                    role: output.role, identity: .clipboard, effect: .clipboard(text: text, expectedRevision: expectedRevision),
                    disposition: .copiedToClipboard, successorByteCount: output.outputByteCount, successorSHA256: sha256(output.output.data))
            case .file:
                throw ReportDeliveryError.unsupportedExpectation("file expectation for clipboard output")
            }
        case .file(let requestedURL, let identity, let overwritePolicy, _):
            switch expectation {
            case .clipboard:
                throw ReportDeliveryError.unsupportedExpectation("clipboard expectation for file output")
            case .file(let fileExpectation, let authority):
                return try deliverFile(
                    output: output, requestedURL: requestedURL, identity: identity, overwritePolicy: overwritePolicy, fileExpectation: fileExpectation,
                    authority: authority, limits: limits, work: &work, totalPathBytes: &totalPathBytes)
            }
        }
    }

    fileprivate static func deliverFile(
        output: ComparisonReportPlannedOutput, requestedURL: URL, identity: ComparisonReportCanonicalOutputIdentity,
        overwritePolicy: ComparisonReportOverwritePolicy, fileExpectation: ReportDeliveryFileExpectation, authority: ReportDeliveryAccessAuthority,
        limits: ReportDeliveryLimits, work: inout ReportDeliveryWorkBudget, totalPathBytes: inout Int
    ) throws -> ReportDeliveryPlannedOutput {
        try validateFileURL(requestedURL, maximumPathBytes: limits.maximumPathBytes)
        let parent = expectationParent(fileExpectation)
        try validateCanonicalIdentity(parent, maximumPathBytes: limits.maximumPathBytes)
        guard isExactParent(requestedURL: requestedURL, parent: parent) else {
            throw ReportDeliveryError.destinationMismatch(requestedURL.path)
        }
        switch fileExpectation {
        case .createNew:
            guard overwritePolicy == .failIfExists else {
                throw ReportDeliveryError.unsupportedExpectation("create requires failIfExists plan")
            }
        case .replaceExisting, .appendExisting:
            guard overwritePolicy == .replaceExisting else {
                throw ReportDeliveryError.unsupportedExpectation("replace/append requires replaceExisting plan")
            }
        }
        if let expected = expectationRevision(fileExpectation) {
            try validateFileRevision(expected, maximumPathBytes: limits.maximumPathBytes)
            guard exactURL(expected.identity.canonicalURL, identity.fileURL) else {
                throw ReportDeliveryError.destinationMismatch(requestedURL.path)
            }
        }
        let successor: Data
        let disposition: ReportDeliveryDisposition
        switch fileExpectation {
        case .createNew:
            successor = output.output.data
            disposition = .created
        case .replaceExisting:
            successor = output.output.data
            disposition = .replaced
        case .appendExisting(_, let existing):
            successor = try appendSuccessor(existing: existing, report: output.output.data, limits: limits, work: &work)
            disposition = .appended
        }
        guard successor.count <= limits.maximumSuccessorBytes else {
            throw ReportDeliveryError.successorTooLarge(maximumBytes: limits.maximumSuccessorBytes)
        }
        try work.consume(UInt64(successor.count) + 64)
        totalPathBytes = try boundedAdd(
            identity.canonicalPathUTF8Bytes.count, to: totalPathBytes, maximum: limits.maximumTotalPathBytes,
            error: .totalPathsTooLarge(maximumBytes: limits.maximumTotalPathBytes))
        try validateAuthorityCovers(authority, identity: identity, limits: limits, work: &work)
        return ReportDeliveryPlannedOutput(
            role: output.role, identity: output.destination.outputIdentity, effect: .file(url: requestedURL, successor: successor, operation: fileExpectation),
            disposition: disposition, successorByteCount: successor.count, successorSHA256: sha256(successor))
    }

    fileprivate static func appendSuccessor(
        existing: ReportDeliveryExistingFileSnapshot, report: Data, limits: ReportDeliveryLimits, work: inout ReportDeliveryWorkBudget
    ) throws -> Data {
        guard existing.data.count <= limits.maximumExistingFileBytes else {
            throw ReportDeliveryError.existingFileTooLarge(maximumBytes: limits.maximumExistingFileBytes)
        }
        guard UInt64(existing.data.count) == existing.revision.byteCount else {
            throw ReportDeliveryError.existingSnapshotMismatch(existing.revision.identity.canonicalURL.path)
        }
        guard constantTimeEqual(sha256(existing.data), existing.revision.contentSHA256) else {
            throw ReportDeliveryError.existingSnapshotMismatch(existing.revision.identity.canonicalURL.path)
        }
        let total = try checkedAdd(existing.data.count, report.count)
        guard total <= limits.maximumSuccessorBytes else {
            throw ReportDeliveryError.successorTooLarge(maximumBytes: limits.maximumSuccessorBytes)
        }
        try work.consume(UInt64(total) + 64)
        var successor = Data()
        successor.reserveCapacity(total)
        successor.append(existing.data)
        successor.append(report)
        return successor
    }

    fileprivate static func expectationParent(_ expectation: ReportDeliveryFileExpectation) -> ReportDeliveryCanonicalFileIdentity {
        switch expectation {
        case .createNew(let parent):
            return parent
        case .replaceExisting(let parent, _):
            return parent
        case .appendExisting(let parent, _):
            return parent
        }
    }

    fileprivate static func expectationRevision(_ expectation: ReportDeliveryFileExpectation) -> ReportDeliveryFileRevision? {
        switch expectation {
        case .createNew:
            return nil
        case .replaceExisting(_, let expected):
            return expected
        case .appendExisting(_, let existing):
            return existing.revision
        }
    }

    fileprivate static func validate(_ limits: ReportDeliveryLimits) throws {
        guard limits.maximumOutputs >= 1, limits.maximumOutputs <= ReportDeliveryLimits.hardMaximumOutputCount else {
            throw ReportDeliveryError.invalidLimit(.outputs)
        }
        guard limits.maximumSuccessorBytes >= 1, limits.maximumSuccessorBytes <= ReportDeliveryLimits.hardMaximumSuccessorBytes else {
            throw ReportDeliveryError.invalidLimit(.successorBytes)
        }
        guard limits.maximumTotalSuccessorBytes >= limits.maximumSuccessorBytes,
            limits.maximumTotalSuccessorBytes <= ReportDeliveryLimits.hardMaximumTotalSuccessorBytes
        else {
            throw ReportDeliveryError.invalidLimit(.totalSuccessorBytes)
        }
        guard limits.maximumExistingFileBytes >= 1, limits.maximumExistingFileBytes <= ReportDeliveryLimits.hardMaximumExistingFileBytes else {
            throw ReportDeliveryError.invalidLimit(.existingFileBytes)
        }
        guard limits.maximumPathBytes >= 1, limits.maximumPathBytes <= ReportDeliveryLimits.hardMaximumPathBytes else {
            throw ReportDeliveryError.invalidLimit(.pathBytes)
        }
        guard limits.maximumTotalPathBytes >= limits.maximumPathBytes, limits.maximumTotalPathBytes <= ReportDeliveryLimits.hardMaximumTotalPathBytes else {
            throw ReportDeliveryError.invalidLimit(.totalPathBytes)
        }
        guard limits.maximumWorkUnits >= 1, limits.maximumWorkUnits <= ReportDeliveryLimits.hardMaximumWorkUnits else {
            throw ReportDeliveryError.invalidLimit(.workUnits)
        }
        guard limits.cancellationCheckInterval >= 1, limits.cancellationCheckInterval <= 1_048_576 else {
            throw ReportDeliveryError.invalidLimit(.cancellationCheckInterval)
        }
    }

    fileprivate static func validateFileURL(_ url: URL, maximumPathBytes: Int) throws {
        guard url.isFileURL, url.baseURL == nil, isLocalHost(url.host) else {
            throw ReportDeliveryError.invalidFileURL(url.absoluteString)
        }
        guard url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else {
            throw ReportDeliveryError.invalidFileURL(url.absoluteString)
        }
        guard !url.hasDirectoryPath, !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" else {
            throw ReportDeliveryError.invalidFileURL(url.absoluteString)
        }
        guard !url.path.contains("\0"), url.path.hasPrefix("/"), url.path.utf8.count <= maximumPathBytes else {
            throw ReportDeliveryError.invalidFileURL(url.absoluteString)
        }
    }

    fileprivate static func validateCanonicalIdentity(_ identity: ReportDeliveryCanonicalFileIdentity, maximumPathBytes: Int) throws {
        let url = identity.canonicalURL
        guard url.isFileURL, url.baseURL == nil, isLocalHost(url.host) else {
            throw ReportDeliveryError.invalidCanonicalIdentity(url.absoluteString)
        }
        guard url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else {
            throw ReportDeliveryError.invalidCanonicalIdentity(url.absoluteString)
        }
        guard !url.path.contains("\0"), url.path.hasPrefix("/"), url.path.utf8.count <= maximumPathBytes else {
            throw ReportDeliveryError.invalidCanonicalIdentity(url.absoluteString)
        }
        guard url.path == url.standardizedFileURL.path, identity.kind == .directory else {
            throw ReportDeliveryError.invalidCanonicalIdentity(url.absoluteString)
        }
    }

    fileprivate static func validateFileRevision(_ revision: ReportDeliveryFileRevision, maximumPathBytes: Int) throws {
        guard revision.identity.kind == .regularFile else {
            throw ReportDeliveryError.invalidFileRevision(revision.identity.canonicalURL.absoluteString)
        }
        let url = revision.identity.canonicalURL
        guard url.path == url.standardizedFileURL.path, url.path.utf8.count <= maximumPathBytes else {
            throw ReportDeliveryError.invalidFileRevision(url.absoluteString)
        }
        guard revision.linkCount >= 1, revision.contentSHA256.count == 32, revision.metadataSHA256.count == 32 else {
            throw ReportDeliveryError.invalidFileRevision(url.absoluteString)
        }
    }

    fileprivate static func validateAuthorityCovers(
        _ authority: ReportDeliveryAccessAuthority, identity: ComparisonReportCanonicalOutputIdentity, limits: ReportDeliveryLimits,
        work: inout ReportDeliveryWorkBudget
    ) throws {
        switch authority {
        case .ambient, .callerManagedWhenRequired:
            return
        case .securityScoped(let resourceURL, let coverage):
            guard resourceURL.isFileURL, resourceURL.baseURL == nil, isLocalHost(resourceURL.host) else {
                throw ReportDeliveryError.invalidAuthority(resourceURL.absoluteString)
            }
            guard resourceURL.user == nil, resourceURL.password == nil, resourceURL.port == nil, resourceURL.query == nil, resourceURL.fragment == nil else {
                throw ReportDeliveryError.invalidAuthority(resourceURL.absoluteString)
            }
            let scopePath = resourceURL.standardizedFileURL.path
            guard scopePath.hasPrefix("/"), scopePath.utf8.count <= limits.maximumPathBytes, !scopePath.contains("\0") else {
                throw ReportDeliveryError.invalidAuthority(resourceURL.absoluteString)
            }
            try work.consume(UInt64(scopePath.utf8.count + identity.canonicalPathUTF8Bytes.count))
            switch coverage {
            case .exactItem:
                guard scopePath == identity.canonicalPath else {
                    throw ReportDeliveryError.authorityDoesNotCoverOutput(identity.canonicalPath)
                }
            case .directoryTree:
                guard isAncestorOrEqual(scopePath: scopePath, path: identity.canonicalPath) else {
                    throw ReportDeliveryError.authorityDoesNotCoverOutput(identity.canonicalPath)
                }
            }
        }
    }

    fileprivate static func isAncestorOrEqual(scopePath: String, path: String) -> Bool {
        if scopePath == path { return true }
        if scopePath == "/" { return path.hasPrefix("/") }
        return path.hasPrefix(scopePath + "/")
    }

    fileprivate static func isExactParent(requestedURL: URL, parent: ReportDeliveryCanonicalFileIdentity) -> Bool {
        exactURL(requestedURL.deletingLastPathComponent(), parent.canonicalURL)
    }

    fileprivate static func exactURL(_ left: URL, _ right: URL) -> Bool {
        left.standardizedFileURL.path == right.standardizedFileURL.path
    }

    fileprivate static func isLocalHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return true }
        return host.lowercased() == "localhost"
    }

    fileprivate static func deliveryDigest(
        outputs: [ReportDeliveryPlannedOutput], snapshot: ComparisonReportWorkflowSnapshotReference, work: inout ReportDeliveryWorkBudget
    ) throws -> [UInt8] {
        var hasher = SHA256()
        func update(_ bytes: [UInt8], work: inout ReportDeliveryWorkBudget) throws {
            try work.consume(UInt64(bytes.count) + 8)
            var length = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
            bytes.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }
        try update(Array("ReportDeliveryPlan/v1".utf8), work: &work)
        try update(Array(snapshot.identity.rawValue.uuidString.utf8), work: &work)
        var generation = snapshot.generation.bigEndian
        withUnsafeBytes(of: &generation) { hasher.update(bufferPointer: $0) }
        try work.consume(8)
        for output in outputs {
            try update(Array(output.identity.displayPath.utf8), work: &work)
            try update(Array(output.disposition.rawValue.utf8), work: &work)
            try update(output.successorSHA256, work: &work)
        }
        return Array(hasher.finalize())
    }

    fileprivate static func sha256(_ data: Data) -> [UInt8] {
        var hasher = SHA256()
        data.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        return Array(hasher.finalize())
    }

    fileprivate static func checkedAdd(_ left: Int, _ right: Int) throws -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw ReportDeliveryError.arithmeticOverflow }
        return result
    }

    fileprivate static func boundedAdd(_ left: Int, to right: Int, maximum: Int, error: ReportDeliveryError) throws -> Int {
        guard left >= 0, right >= 0, left <= maximum - right else { throw error }
        return left + right
    }
}

private struct ReportDeliveryWorkBudget {
    private let maximum: UInt64
    private let checkInterval: Int
    private var stepsSinceCheck = 0
    private(set) var consumed: UInt64 = 0

    init(limits: ReportDeliveryLimits) {
        maximum = limits.maximumWorkUnits
        checkInterval = limits.cancellationCheckInterval
    }

    mutating func consume(_ amount: UInt64) throws {
        guard amount <= maximum - consumed else {
            throw ReportDeliveryError.workLimitExceeded(maximumUnits: maximum)
        }
        consumed += amount
        stepsSinceCheck += 1
        if stepsSinceCheck >= checkInterval {
            stepsSinceCheck = 0
            try Task.checkCancellation()
        }
    }

    mutating func checkpoint() throws {
        stepsSinceCheck += 1
        if stepsSinceCheck >= checkInterval {
            stepsSinceCheck = 0
            try Task.checkCancellation()
        }
    }
}

private func constantTimeEqual(_ left: [UInt8], _ right: [UInt8]) -> Bool {
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for (leftByte, rightByte) in zip(left, right) {
        difference |= leftByte ^ rightByte
    }
    return difference == 0
}
