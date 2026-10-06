import Foundation

public enum CodePageFixtureMatrix: Sendable {
    public typealias CancellationCheck = @Sendable () -> Bool

    public enum CodePage: Int, CaseIterable, Comparable, Hashable, Sendable {
        case cp932 = 932
        case cp1250 = 1250
        case cp1251 = 1251
        case cp1252 = 1252
        case cp1253 = 1253
        case cp1254 = 1254
        case cp1255 = 1255
        case cp50220 = 50220
        case cp51932 = 51932

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue < right.rawValue
        }

        public var textFileEncoding: TextFileEncoding {
            switch self {
            case .cp932: .shiftJIS
            case .cp1250: .windows1250
            case .cp1251: .windows1251
            case .cp1252: .windows1252
            case .cp1253: .windows1253
            case .cp1254: .windows1254
            case .cp1255: .windows1255
            case .cp50220: .iso2022JP
            case .cp51932: .japaneseEUC
            }
        }

        public var auditID: CodePageLifecycleAudit.CodePageID {
            CodePageLifecycleAudit.CodePageID(rawValue: rawValue)
        }

        public var auditPage: CodePageLifecycleAudit.SupportedCodePage? {
            CodePageLifecycleAudit.SupportedCodePage(rawValue: rawValue)
        }

        public static var canonicalAmbiguityOrder: [CodePage] {
            [.cp932, .cp51932, .cp1250, .cp1251, .cp1252, .cp1253, .cp1254, .cp1255]
        }
    }

    public enum BOMPolicy: String, CaseIterable, Hashable, Sendable {
        case omit

        public static func policy(for _: CodePage) -> BOMPolicy {
            .omit
        }

        public static func isValid(hasByteOrderMark: Bool, for _: CodePage) -> Bool {
            !hasByteOrderMark
        }
    }

    public enum Stage: Int, CaseIterable, Comparable, Hashable, Sendable {
        case load
        case compare
        case edit
        case save
        case reload
        case byteComparison

        public static func < (left: Self, right: Self) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public struct FixtureReference: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let identity: UUID
        public let revision: UInt64

        public init(identity: UUID, revision: UInt64) {
            self.identity = identity
            self.revision = revision
        }

        public var description: String {
            "CodePageFixtureMatrix.FixtureReference(revision: \(revision), identity: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["revision": revision, "identity": "<redacted>"], displayStyle: .struct)
        }
    }

    public enum AutomaticDetection: Hashable, Sendable {
        case selected(CodePage)
        case ambiguous([CodePage])
        case rejected
    }

    public struct FixtureInput: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let reference: FixtureReference
        public let codePage: CodePage
        public let sourceBytes: Data
        public let hasByteOrderMark: Bool
        public let automaticDetection: AutomaticDetection
        public let explicitSelection: CodePage
        public let editedText: String
        public let oraclePresent: Bool
        public let requiresVerified: Bool

        public init(
            reference: FixtureReference,
            codePage: CodePage,
            sourceBytes: Data,
            hasByteOrderMark: Bool,
            automaticDetection: AutomaticDetection,
            explicitSelection: CodePage,
            editedText: String,
            oraclePresent: Bool,
            requiresVerified: Bool
        ) {
            self.reference = reference
            self.codePage = codePage
            self.sourceBytes = sourceBytes
            self.hasByteOrderMark = hasByteOrderMark
            self.automaticDetection = automaticDetection
            self.explicitSelection = explicitSelection
            self.editedText = editedText
            self.oraclePresent = oraclePresent
            self.requiresVerified = requiresVerified
        }

        public var description: String {
            "CodePageFixtureMatrix.FixtureInput(codePage: \(codePage.rawValue), bytes: \(sourceBytes.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "reference": reference,
                    "codePage": codePage.rawValue,
                    "byteCount": sourceBytes.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case fixtures
        case sourceBytes
        case totalSourceBytes
        case editedStringBytes
        case workUnits
        case cancellationCheckInterval
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumFixtures = 1024
        public static let hardMaximumSourceBytes = 4 * 1024 * 1024
        public static let hardMaximumTotalSourceBytes = 64 * 1024 * 1024
        public static let hardMaximumEditedStringBytes = 4 * 1024 * 1024
        public static let hardMaximumWorkUnits = 64 * 1024 * 1024
        public static let hardMaximumCancellationCheckInterval = 65536
        public static let `default` = Limits()

        public let maximumFixtures: Int
        public let maximumSourceBytes: Int
        public let maximumTotalSourceBytes: Int
        public let maximumEditedStringBytes: Int
        public let maximumWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumFixtures: Int = 64,
            maximumSourceBytes: Int = 1024 * 1024,
            maximumTotalSourceBytes: Int = 8 * 1024 * 1024,
            maximumEditedStringBytes: Int = 1024 * 1024,
            maximumWorkUnits: Int = 4 * 1024 * 1024,
            cancellationCheckInterval: Int = 256
        ) {
            self.maximumFixtures = maximumFixtures
            self.maximumSourceBytes = maximumSourceBytes
            self.maximumTotalSourceBytes = maximumTotalSourceBytes
            self.maximumEditedStringBytes = maximumEditedStringBytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            guard (1...Self.hardMaximumFixtures).contains(maximumFixtures) else {
                throw MatrixError.invalidLimit(.fixtures)
            }
            guard (1...Self.hardMaximumSourceBytes).contains(maximumSourceBytes) else {
                throw MatrixError.invalidLimit(.sourceBytes)
            }
            guard (1...Self.hardMaximumTotalSourceBytes).contains(maximumTotalSourceBytes) else {
                throw MatrixError.invalidLimit(.totalSourceBytes)
            }
            guard maximumTotalSourceBytes >= maximumSourceBytes else {
                throw MatrixError.invalidLimit(.totalSourceBytes)
            }
            guard (1...Self.hardMaximumEditedStringBytes).contains(maximumEditedStringBytes) else {
                throw MatrixError.invalidLimit(.editedStringBytes)
            }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
                throw MatrixError.invalidLimit(.workUnits)
            }
            guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
                throw MatrixError.invalidLimit(.cancellationCheckInterval)
            }
        }
    }

    public enum MatrixError: Error, Equatable, Hashable, Sendable {
        case cancelled
        case invalidLimit(Limit)
        case fixtureLimitExceeded(maximum: Int)
        case sourceByteLimitExceeded(maximum: Int)
        case totalSourceByteLimitExceeded(maximum: Int)
        case editedStringTooLarge(maximum: Int)
        case workLimitExceeded(maximum: Int)
        case staleFixture
        case bomNotPermitted(CodePage)
        case ambiguousOrderViolation(CodePage)
        case automaticDetectionInvalid(CodePage)
        case explicitSelectionMismatch(CodePage)
        case textNotRepresentable(CodePage)
        case unverifiedCodePage(CodePage)
        case loadFailed(CodePage)
        case saveFailed(CodePage)
        case reloadMismatch(CodePage)
        case byteMismatch(CodePage)
    }

    public struct StagePlan: Hashable, Sendable {
        public let ordinal: Int
        public let reference: FixtureReference
        public let codePage: CodePage
        public let stage: Stage

        public init(ordinal: Int, reference: FixtureReference, codePage: CodePage, stage: Stage) {
            self.ordinal = ordinal
            self.reference = reference
            self.codePage = codePage
            self.stage = stage
        }
    }

    public struct PlanningReceipt: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let fixtureCount: Int
        public let stageCount: Int
        public let verifiedCount: Int
        public let workPerformed: Int

        public init(fixtureCount: Int, stageCount: Int, verifiedCount: Int, workPerformed: Int) {
            self.fixtureCount = fixtureCount
            self.stageCount = stageCount
            self.verifiedCount = verifiedCount
            self.workPerformed = workPerformed
        }

        public var description: String {
            "CodePageFixtureMatrix.PlanningReceipt(fixtures: \(fixtureCount), stages: \(stageCount), verified: \(verifiedCount), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "fixtureCount": fixtureCount,
                    "stageCount": stageCount,
                    "verifiedCount": verifiedCount,
                    "workPerformed": workPerformed,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Plan: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let inputs: [FixtureInput]
        public let stagePlans: [StagePlan]
        public let receipt: PlanningReceipt

        public init(inputs: [FixtureInput], stagePlans: [StagePlan], receipt: PlanningReceipt) {
            self.inputs = inputs
            self.stagePlans = stagePlans
            self.receipt = receipt
        }

        public var description: String {
            "CodePageFixtureMatrix.Plan(fixtures: \(inputs.count), stages: \(stagePlans.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "fixtureCount": inputs.count,
                    "stageCount": stagePlans.count,
                    "receipt": receipt,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct StageResult: Hashable, Sendable {
        public let stage: Stage
        public let passed: Bool
        public let byteCount: Int

        public init(stage: Stage, passed: Bool, byteCount: Int) {
            self.stage = stage
            self.passed = passed
            self.byteCount = byteCount
        }
    }

    public struct FixtureReport: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let reference: FixtureReference
        public let codePage: CodePage
        public let stageResults: [StageResult]
        public let savedByteCount: Int
        public let reloadedByteCount: Int
        public let savedEqualsReloaded: Bool
        public let oraclePresent: Bool
        public let isVerified: Bool

        public init(
            reference: FixtureReference,
            codePage: CodePage,
            stageResults: [StageResult],
            savedByteCount: Int,
            reloadedByteCount: Int,
            savedEqualsReloaded: Bool,
            oraclePresent: Bool,
            isVerified: Bool
        ) {
            self.reference = reference
            self.codePage = codePage
            self.stageResults = stageResults
            self.savedByteCount = savedByteCount
            self.reloadedByteCount = reloadedByteCount
            self.savedEqualsReloaded = savedEqualsReloaded
            self.oraclePresent = oraclePresent
            self.isVerified = isVerified
        }

        public var isCompleteAndValid: Bool {
            stageResults.count == Stage.allCases.count && stageResults.allSatisfy(\.passed) && savedEqualsReloaded
        }

        public var description: String {
            "CodePageFixtureMatrix.FixtureReport(codePage: \(codePage.rawValue), stages: \(stageResults.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "codePage": codePage.rawValue,
                    "stageCount": stageResults.count,
                    "savedByteCount": savedByteCount,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct ExecutionReceipt: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let fixtureCount: Int
        public let stageCount: Int
        public let completeCount: Int
        public let workPerformed: Int

        public init(fixtureCount: Int, stageCount: Int, completeCount: Int, workPerformed: Int) {
            self.fixtureCount = fixtureCount
            self.stageCount = stageCount
            self.completeCount = completeCount
            self.workPerformed = workPerformed
        }

        public var recordsCompleteCoverage: Bool {
            completeCount == stageCount && fixtureCount > 0
        }

        public var description: String {
            "CodePageFixtureMatrix.ExecutionReceipt(fixtures: \(fixtureCount), complete: \(completeCount), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "fixtureCount": fixtureCount,
                    "stageCount": stageCount,
                    "completeCount": completeCount,
                    "workPerformed": workPerformed,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Report: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let fixtures: [FixtureReport]
        public let receipt: ExecutionReceipt

        public init(fixtures: [FixtureReport], receipt: ExecutionReceipt) {
            self.fixtures = fixtures
            self.receipt = receipt
        }

        public var isCompleteAndValid: Bool {
            fixtures.allSatisfy(\.isCompleteAndValid) && receipt.recordsCompleteCoverage
        }

        public var description: String {
            "CodePageFixtureMatrix.Report(fixtures: \(fixtures.count), complete: \(receipt.completeCount), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "fixtureCount": fixtures.count,
                    "completeCount": receipt.completeCount,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public static func isVerified(_ codePage: CodePage, oraclePresent: Bool) -> Bool {
        codePage != .cp1255 || oraclePresent
    }

    public static func verifiedCodePages(from inputs: [FixtureInput]) -> [CodePage] {
        inputs.filter { isVerified($0.codePage, oraclePresent: $0.oraclePresent) }.map(\.codePage).sorted()
    }

    public static func isCanonicalAmbiguity(_ pages: [CodePage]) -> Bool {
        let order = CodePage.canonicalAmbiguityOrder
        guard pages.count > 1, pages.count <= order.count else { return false }
        guard Set(pages).count == pages.count else { return false }
        var lastIndex = -1
        for page in pages {
            guard let index = order.firstIndex(of: page), index > lastIndex else { return false }
            lastIndex = index
        }
        return true
    }

    public static func canonicalAmbiguityOrder(_ pages: [CodePage]) -> [CodePage] {
        let order = CodePage.canonicalAmbiguityOrder
        return pages.sorted {
            order.firstIndex(of: $0) ?? Int.max < order.firstIndex(of: $1) ?? Int.max
        }
    }

    public static func plan(
        _ inputs: [FixtureInput],
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Plan {
        try limits.validate()
        var budget = try WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        guard inputs.count <= limits.maximumFixtures else {
            throw MatrixError.fixtureLimitExceeded(maximum: limits.maximumFixtures)
        }
        var totalBytes = 0
        for input in inputs {
            try budget.consume()
            guard input.sourceBytes.count <= limits.maximumSourceBytes else {
                throw MatrixError.sourceByteLimitExceeded(maximum: limits.maximumSourceBytes)
            }
            let (accumulated, overflow) = totalBytes.addingReportingOverflow(input.sourceBytes.count)
            guard !overflow, accumulated <= limits.maximumTotalSourceBytes else {
                throw MatrixError.totalSourceByteLimitExceeded(maximum: limits.maximumTotalSourceBytes)
            }
            totalBytes = accumulated
            guard input.editedText.utf8.count <= limits.maximumEditedStringBytes else {
                throw MatrixError.editedStringTooLarge(maximum: limits.maximumEditedStringBytes)
            }
            try budget.consume(input.sourceBytes.count / 1024 + 1)
        }
        let ordered = inputs.sorted {
            if $0.codePage != $1.codePage { return $0.codePage < $1.codePage }
            if $0.reference.revision != $1.reference.revision { return $0.reference.revision < $1.reference.revision }
            return $0.reference.identity.uuidString < $1.reference.identity.uuidString
        }
        for input in ordered {
            try budget.consume()
            guard BOMPolicy.isValid(hasByteOrderMark: input.hasByteOrderMark, for: input.codePage) else {
                throw MatrixError.bomNotPermitted(input.codePage)
            }
            guard input.explicitSelection == input.codePage else {
                throw MatrixError.explicitSelectionMismatch(input.codePage)
            }
            switch input.automaticDetection {
            case .selected(let detected):
                guard detected == input.codePage else {
                    throw MatrixError.explicitSelectionMismatch(input.codePage)
                }
            case .ambiguous(let pages):
                guard isCanonicalAmbiguity(pages), pages.contains(input.codePage) else {
                    throw MatrixError.ambiguousOrderViolation(input.codePage)
                }
            case .rejected:
                throw MatrixError.automaticDetectionInvalid(input.codePage)
            }
            if input.requiresVerified, !isVerified(input.codePage, oraclePresent: input.oraclePresent) {
                throw MatrixError.unverifiedCodePage(input.codePage)
            }
            guard canEncodeLosslessly(input.editedText, as: input.codePage) else {
                throw MatrixError.textNotRepresentable(input.codePage)
            }
            guard (try? TextFileCodec.decode(input.sourceBytes, assuming: input.codePage.textFileEncoding)) != nil else {
                throw MatrixError.loadFailed(input.codePage)
            }
        }
        var stagePlans: [StagePlan] = []
        stagePlans.reserveCapacity(ordered.count * Stage.allCases.count)
        var ordinal = 0
        for input in ordered {
            for stage in Stage.allCases {
                try budget.consume()
                stagePlans.append(StagePlan(ordinal: ordinal, reference: input.reference, codePage: input.codePage, stage: stage))
                ordinal += 1
            }
        }
        try budget.finish()
        let verified = ordered.filter { isVerified($0.codePage, oraclePresent: $0.oraclePresent) }.count
        let receipt = PlanningReceipt(
            fixtureCount: ordered.count,
            stageCount: stagePlans.count,
            verifiedCount: verified,
            workPerformed: budget.consumed
        )
        return Plan(inputs: ordered, stagePlans: stagePlans, receipt: receipt)
    }

    public static func run(
        _ plan: Plan,
        with current: [FixtureInput],
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { Task.isCancelled }
    ) throws -> Report {
        try limits.validate()
        var budget = try WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        let orderedCurrent = current.sorted {
            if $0.codePage != $1.codePage { return $0.codePage < $1.codePage }
            if $0.reference.revision != $1.reference.revision { return $0.reference.revision < $1.reference.revision }
            return $0.reference.identity.uuidString < $1.reference.identity.uuidString
        }
        guard orderedCurrent.map(\.reference) == plan.inputs.map(\.reference) else {
            throw MatrixError.staleFixture
        }
        guard orderedCurrent == plan.inputs else {
            throw MatrixError.staleFixture
        }
        var reports: [FixtureReport] = []
        reports.reserveCapacity(orderedCurrent.count)
        var completeStages = 0
        for input in orderedCurrent {
            try budget.consume()
            let report = try executeFixture(input, budget: &budget)
            completeStages += report.stageResults.filter(\.passed).count
            reports.append(report)
        }
        try budget.finish()
        let receipt = ExecutionReceipt(
            fixtureCount: reports.count,
            stageCount: plan.stagePlans.count,
            completeCount: completeStages,
            workPerformed: budget.consumed
        )
        return Report(fixtures: reports, receipt: receipt)
    }

    static func canEncodeLosslessly(_ text: String, as codePage: CodePage) -> Bool {
        guard let data = try? TextFileCodec.encode(DecodedTextFile(text: text, encoding: codePage.textFileEncoding, hasByteOrderMark: false)) else {
            return false
        }
        guard let decoded = try? TextFileCodec.decode(data, assuming: codePage.textFileEncoding) else {
            return false
        }
        return decoded.text.unicodeScalars.elementsEqual(text.unicodeScalars)
    }

    static func executeFixture(_ input: FixtureInput, budget: inout WorkBudget) throws -> FixtureReport {
        let encoding = input.codePage.textFileEncoding
        guard let loaded = try? TextFileCodec.decode(input.sourceBytes, assuming: encoding) else {
            throw MatrixError.loadFailed(input.codePage)
        }
        try budget.consume(loaded.text.utf8.count / 1024 + 1)
        guard !loaded.hasByteOrderMark, BOMPolicy.isValid(hasByteOrderMark: loaded.hasByteOrderMark, for: input.codePage) else {
            throw MatrixError.bomNotPermitted(input.codePage)
        }
        let loadPassed = loaded.encoding == encoding
        let loadResult = StageResult(stage: .load, passed: loadPassed, byteCount: input.sourceBytes.count)
        guard let reloadedForCompare = try? TextFileCodec.decode(input.sourceBytes, assuming: encoding) else {
            throw MatrixError.loadFailed(input.codePage)
        }
        try budget.consume()
        let comparePassed = loaded.text.unicodeScalars.elementsEqual(reloadedForCompare.text.unicodeScalars)
        let compareResult = StageResult(stage: .compare, passed: comparePassed, byteCount: input.sourceBytes.count)
        guard let editedData = try? TextFileCodec.encode(DecodedTextFile(text: input.editedText, encoding: encoding, hasByteOrderMark: false)) else {
            let failed = Stage.allCases.map { StageResult(stage: $0, passed: false, byteCount: 0) }
            return FixtureReport(
                reference: input.reference,
                codePage: input.codePage,
                stageResults: failed,
                savedByteCount: 0,
                reloadedByteCount: 0,
                savedEqualsReloaded: false,
                oraclePresent: input.oraclePresent,
                isVerified: isVerified(input.codePage, oraclePresent: input.oraclePresent)
            )
        }
        try budget.consume(editedData.count / 1024 + 1)
        let editPassed =
            (try? TextFileCodec.decode(editedData, assuming: encoding)).map {
                $0.text.unicodeScalars.elementsEqual(input.editedText.unicodeScalars)
            } ?? false
        let editResult = StageResult(stage: .edit, passed: editPassed, byteCount: editedData.count)
        let savedBytes = editedData
        let saveResult = StageResult(stage: .save, passed: editPassed, byteCount: savedBytes.count)
        guard let reloaded = try? TextFileCodec.decode(savedBytes, assuming: encoding) else {
            throw MatrixError.reloadMismatch(input.codePage)
        }
        try budget.consume(savedBytes.count / 1024 + 1)
        let reloadPassed = reloaded.text.unicodeScalars.elementsEqual(input.editedText.unicodeScalars)
        let reloadResult = StageResult(stage: .reload, passed: reloadPassed, byteCount: savedBytes.count)
        guard let resaved = try? TextFileCodec.encode(DecodedTextFile(text: reloaded.text, encoding: encoding, hasByteOrderMark: false)) else {
            throw MatrixError.saveFailed(input.codePage)
        }
        try budget.consume()
        let byteExact = resaved == savedBytes
        let byteResult = StageResult(stage: .byteComparison, passed: byteExact && reloadPassed, byteCount: savedBytes.count)
        let results = [loadResult, compareResult, editResult, saveResult, reloadResult, byteResult]
        return FixtureReport(
            reference: input.reference,
            codePage: input.codePage,
            stageResults: results,
            savedByteCount: savedBytes.count,
            reloadedByteCount: resaved.count,
            savedEqualsReloaded: byteExact,
            oraclePresent: input.oraclePresent,
            isVerified: isVerified(input.codePage, oraclePresent: input.oraclePresent)
        )
    }

    struct WorkBudget {
        let maximum: Int
        let interval: Int
        let check: CancellationCheck
        private(set) var consumed = 0
        private var nextCheck = 0

        init(limits: Limits, cancellationCheck: @escaping CancellationCheck) throws {
            try limits.validate()
            maximum = limits.maximumWorkUnits
            interval = limits.cancellationCheckInterval
            check = cancellationCheck
            nextCheck = limits.cancellationCheckInterval
            guard !check() else { throw MatrixError.cancelled }
        }

        mutating func consume(_ units: Int = 1) throws {
            guard units >= 0 else { throw MatrixError.workLimitExceeded(maximum: maximum) }
            let (value, overflow) = consumed.addingReportingOverflow(units)
            guard !overflow, value <= maximum else {
                throw MatrixError.workLimitExceeded(maximum: maximum)
            }
            consumed = value
            if value >= nextCheck {
                guard !check() else { throw MatrixError.cancelled }
                let (next, nextOverflow) = value.addingReportingOverflow(interval)
                nextCheck = nextOverflow ? Int.max : next
            }
        }

        mutating func finish() throws {
            guard !check() else { throw MatrixError.cancelled }
        }
    }
}
