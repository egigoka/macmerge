import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class ReportDeliveryWorkflowTests: XCTestCase {
    func testCreateNewPlansCreatedDispositionWithCASBindings() throws {
        let source = try makeFileSource()
        let target = try fileTarget(source.plan.outputs[0])
        let parent = parentIdentity(for: target.requestedURL)
        let plan = try deliver(
            source.plan,
            expectations: [.file(expectation: .createNew(parent: parent), authority: .ambient)]
        )
        let reportData = source.plan.outputs[0].output.data
        XCTAssertEqual(plan.outputs.count, 1)
        let output = plan.outputs[0]
        XCTAssertEqual(output.role, .primary)
        XCTAssertEqual(output.disposition, .created)
        XCTAssertEqual(output.successorByteCount, reportData.count)
        XCTAssertEqual(output.successorSHA256, sha256Bytes(reportData))
        XCTAssertEqual(output.identity, source.plan.outputs[0].destination.outputIdentity)
        guard case .file(let url, let successor, let operation) = output.effect else {
            return XCTFail("Expected file effect")
        }
        XCTAssertEqual(url, target.requestedURL)
        XCTAssertEqual(successor, reportData)
        XCTAssertEqual(operation, .createNew(parent: parent))
        XCTAssertEqual(plan.receipt.outputCount, 1)
        XCTAssertEqual(plan.receipt.successorByteCount, reportData.count)
        XCTAssertEqual(plan.receipt.snapshot, source.plan.snapshotFingerprint.reference)
        XCTAssertEqual(plan.receipt.planSHA256.count, 32)
        XCTAssertGreaterThan(plan.receipt.estimatedWorkUnits, 0)
        XCTAssertEqual(plan.limits, .default)
    }

    func testReplaceExistingPlansReplacedDisposition() throws {
        let source = try makeFileSource(overwritePolicy: .replaceExisting)
        let target = try fileTarget(source.plan.outputs[0])
        let expected = makeFileRevision(
            canonicalURL: target.identity.fileURL,
            byteCount: 5,
            contentSHA256: sha256Bytes(Data("payload".utf8))
        )
        let parent = parentIdentity(for: target.requestedURL)
        let plan = try deliver(
            source.plan,
            expectations: [.file(expectation: .replaceExisting(parent: parent, expected: expected), authority: .ambient)]
        )
        let reportData = source.plan.outputs[0].output.data
        XCTAssertEqual(plan.outputs[0].disposition, .replaced)
        XCTAssertEqual(plan.outputs[0].successorByteCount, reportData.count)
        XCTAssertEqual(plan.outputs[0].successorSHA256, sha256Bytes(reportData))
        guard case .file(_, let successor, let operation) = plan.outputs[0].effect else {
            return XCTFail("Expected file effect")
        }
        XCTAssertEqual(successor, reportData)
        XCTAssertEqual(operation, .replaceExisting(parent: parent, expected: expected))
    }

    func testAppendExistingConcatenatesWithCASBindings() throws {
        let source = try makeFileSource(overwritePolicy: .replaceExisting)
        let target = try fileTarget(source.plan.outputs[0])
        let prefix = Data("prefix:".utf8)
        let existing = try makeExistingSnapshot(data: prefix, canonicalURL: target.identity.fileURL)
        let parent = parentIdentity(for: target.requestedURL)
        let plan = try deliver(
            source.plan,
            expectations: [.file(expectation: .appendExisting(parent: parent, expected: existing), authority: .ambient)]
        )
        let reportData = source.plan.outputs[0].output.data
        let successor = prefix + reportData
        XCTAssertEqual(plan.outputs[0].disposition, .appended)
        XCTAssertEqual(plan.outputs[0].successorByteCount, successor.count)
        XCTAssertEqual(plan.outputs[0].successorSHA256, sha256Bytes(successor))
        guard case .file(_, let actual, let operation) = plan.outputs[0].effect else {
            return XCTFail("Expected file effect")
        }
        XCTAssertEqual(actual, successor)
        XCTAssertEqual(operation, .appendExisting(parent: parent, expected: existing))
    }

    func testClipboardPlansCopiedToClipboard() throws {
        let source = try makeClipboardSource()
        let revision = clipboardRevision()
        let plan = try deliver(source.plan, expectations: [.clipboard(expectedRevision: revision)])
        let reportData = source.plan.outputs[0].output.data
        let text = String(decoding: reportData, as: UTF8.self)
        XCTAssertEqual(plan.outputs.count, 1)
        XCTAssertEqual(plan.outputs[0].disposition, .copiedToClipboard)
        XCTAssertEqual(plan.outputs[0].identity, .clipboard)
        XCTAssertEqual(plan.outputs[0].successorByteCount, reportData.count)
        XCTAssertEqual(plan.outputs[0].successorSHA256, sha256Bytes(reportData))
        XCTAssertEqual(plan.outputs[0].effect, .clipboard(text: text, expectedRevision: revision))
    }

    func testExpectationCountMismatch() throws {
        let single = try makeFileSource()
        assertDeliveryError(.expectationCountMismatch(expected: 1, actual: 0)) {
            try deliver(single.plan, expectations: [])
        }
        let multi = try makeMultiFileSource()
        assertDeliveryError(.expectationCountMismatch(expected: 3, actual: 1)) {
            try deliver(multi.plan, expectations: [.clipboard(expectedRevision: clipboardRevision())])
        }
    }

    func testSwappedExpectationKindsThrowUnsupported() throws {
        let fileSource = try makeFileSource()
        let fileTargetURL = try fileTarget(fileSource.plan.outputs[0]).requestedURL
        assertDeliveryError(.unsupportedExpectation("clipboard expectation for file output")) {
            try deliver(fileSource.plan, expectations: [.clipboard(expectedRevision: clipboardRevision())])
        }
        XCTAssertEqual(fileTargetURL.path, "/tmp/macmerge-delivery/report.txt")
        let clipboardSource = try makeClipboardSource()
        let parent = parentIdentity(for: URL(fileURLWithPath: "/tmp/macmerge-delivery/report.txt"))
        assertDeliveryError(.unsupportedExpectation("file expectation for clipboard output")) {
            try deliver(
                clipboardSource.plan,
                expectations: [.file(expectation: .createNew(parent: parent), authority: .ambient)]
            )
        }
    }

    func testOverwritePolicyMustMatchExpectationKind() throws {
        let replaceSource = try makeFileSource(overwritePolicy: .replaceExisting)
        let replaceTarget = try fileTarget(replaceSource.plan.outputs[0])
        assertDeliveryError(.unsupportedExpectation("create requires failIfExists plan")) {
            try deliver(
                replaceSource.plan,
                expectations: [.file(expectation: .createNew(parent: parentIdentity(for: replaceTarget.requestedURL)), authority: .ambient)]
            )
        }
        let createSource = try makeFileSource()
        let createTarget = try fileTarget(createSource.plan.outputs[0])
        let parent = parentIdentity(for: createTarget.requestedURL)
        let revision = makeFileRevision(
            canonicalURL: createTarget.identity.fileURL,
            byteCount: 1,
            contentSHA256: Array(repeating: 1, count: 32)
        )
        let existing = try makeExistingSnapshot(data: Data("x".utf8), canonicalURL: createTarget.identity.fileURL)
        assertDeliveryError(.unsupportedExpectation("replace/append requires replaceExisting plan")) {
            try deliver(
                createSource.plan,
                expectations: [.file(expectation: .replaceExisting(parent: parent, expected: revision), authority: .ambient)]
            )
        }
        assertDeliveryError(.unsupportedExpectation("replace/append requires replaceExisting plan")) {
            try deliver(
                createSource.plan,
                expectations: [.file(expectation: .appendExisting(parent: parent, expected: existing), authority: .ambient)]
            )
        }
    }

    func testParentMismatchThrowsDestinationMismatch() throws {
        let source = try makeFileSource()
        let other = ReportDeliveryCanonicalFileIdentity(
            canonicalURL: URL(fileURLWithPath: "/tmp/macmerge-elsewhere", isDirectory: true),
            kind: .directory,
            deviceID: 11,
            fileID: 22,
            generation: 33
        )
        assertDeliveryError(.destinationMismatch("/tmp/macmerge-delivery/report.txt")) {
            try deliver(
                source.plan,
                expectations: [.file(expectation: .createNew(parent: other), authority: .ambient)]
            )
        }
    }

    func testRevisionURLMismatchThrowsDestinationMismatch() throws {
        let source = try makeFileSource(overwritePolicy: .replaceExisting)
        let target = try fileTarget(source.plan.outputs[0])
        let revision = makeFileRevision(
            canonicalURL: URL(fileURLWithPath: "/tmp/macmerge-delivery/other.txt"),
            byteCount: 1,
            contentSHA256: Array(repeating: 2, count: 32)
        )
        assertDeliveryError(.destinationMismatch("/tmp/macmerge-delivery/report.txt")) {
            try deliver(
                source.plan,
                expectations: [.file(expectation: .replaceExisting(parent: parentIdentity(for: target.requestedURL), expected: revision), authority: .ambient)]
            )
        }
    }

    func testAppendByteCountMismatchThrowsSnapshotMismatch() throws {
        let source = try makeFileSource(overwritePolicy: .replaceExisting)
        let target = try fileTarget(source.plan.outputs[0])
        let data = Data("prefix:".utf8)
        let revision = makeFileRevision(
            canonicalURL: target.identity.fileURL,
            byteCount: UInt64(data.count) + 1,
            contentSHA256: sha256Bytes(data)
        )
        let inconsistent = try ReportDeliveryExistingFileSnapshot(revision: revision, data: data)
        assertDeliveryError(.existingSnapshotMismatch("/tmp/macmerge-delivery/report.txt")) {
            try deliver(
                source.plan,
                expectations: [
                    .file(expectation: .appendExisting(parent: parentIdentity(for: target.requestedURL), expected: inconsistent), authority: .ambient)
                ]
            )
        }
    }

    func testAppendContentMismatchThrowsSnapshotMismatch() throws {
        let source = try makeFileSource(overwritePolicy: .replaceExisting)
        let target = try fileTarget(source.plan.outputs[0])
        let data = Data("prefix:".utf8)
        let revision = makeFileRevision(
            canonicalURL: target.identity.fileURL,
            byteCount: UInt64(data.count),
            contentSHA256: Array(repeating: 0, count: 32)
        )
        let tampered = try ReportDeliveryExistingFileSnapshot(revision: revision, data: data)
        assertDeliveryError(.existingSnapshotMismatch("/tmp/macmerge-delivery/report.txt")) {
            try deliver(
                source.plan,
                expectations: [.file(expectation: .appendExisting(parent: parentIdentity(for: target.requestedURL), expected: tampered), authority: .ambient)]
            )
        }
    }

    func testSuccessorTooLargeThrows() throws {
        let source = try makeFileSource()
        let size = source.plan.outputs[0].outputByteCount
        XCTAssertGreaterThan(size, 1)
        let limits = ReportDeliveryLimits(maximumSuccessorBytes: size - 1)
        assertDeliveryError(.successorTooLarge(maximumBytes: size - 1)) {
            try deliver(source.plan, expectations: createExpectations(for: source.plan), limits: limits)
        }
    }

    func testTotalSuccessorTooLargeThrows() throws {
        let source = try makeMultiFileSource()
        let sizes = source.plan.outputs.map(\.outputByteCount)
        let total = sizes.reduce(0, +)
        let largest = sizes.max() ?? 0
        XCTAssertGreaterThan(total, largest)
        XCTAssertGreaterThanOrEqual(total - 1, largest)
        let limits = ReportDeliveryLimits(
            maximumSuccessorBytes: largest,
            maximumTotalSuccessorBytes: total - 1
        )
        assertDeliveryError(.totalSuccessorTooLarge(maximumBytes: total - 1)) {
            try deliver(source.plan, expectations: createExpectations(for: source.plan), limits: limits)
        }
    }

    func testTotalPathsTooLargeThrows() throws {
        let source = try makeMultiFileSource()
        var counts: [Int] = []
        for output in source.plan.outputs {
            let target = try fileTarget(output)
            counts.append(target.requestedURL.path.utf8.count)
            counts.append(target.identity.canonicalPathUTF8Bytes.count)
        }
        let largest = counts.max() ?? 0
        let canonicalTotal = try source.plan.outputs.map { try fileTarget($0).identity.canonicalPathUTF8Bytes.count }.reduce(0, +)
        XCTAssertGreaterThan(canonicalTotal, largest)
        XCTAssertGreaterThanOrEqual(canonicalTotal - 1, largest)
        let limits = ReportDeliveryLimits(
            maximumPathBytes: largest,
            maximumTotalPathBytes: canonicalTotal - 1
        )
        assertDeliveryError(.totalPathsTooLarge(maximumBytes: canonicalTotal - 1)) {
            try deliver(source.plan, expectations: createExpectations(for: source.plan), limits: limits)
        }
    }

    func testInvalidLimitsThrow() throws {
        let source = try makeClipboardSource()
        let hard = ReportDeliveryLimits.self
        let cases: [(ReportDeliveryLimits, ReportDeliveryLimit)] = [
            (ReportDeliveryLimits(maximumOutputs: 0), .outputs),
            (ReportDeliveryLimits(maximumOutputs: hard.hardMaximumOutputCount + 1), .outputs),
            (ReportDeliveryLimits(maximumSuccessorBytes: 0), .successorBytes),
            (ReportDeliveryLimits(maximumSuccessorBytes: hard.hardMaximumSuccessorBytes + 1), .successorBytes),
            (ReportDeliveryLimits(maximumTotalSuccessorBytes: 1), .totalSuccessorBytes),
            (ReportDeliveryLimits(maximumTotalSuccessorBytes: hard.hardMaximumTotalSuccessorBytes + 1), .totalSuccessorBytes),
            (ReportDeliveryLimits(maximumExistingFileBytes: 0), .existingFileBytes),
            (ReportDeliveryLimits(maximumExistingFileBytes: hard.hardMaximumExistingFileBytes + 1), .existingFileBytes),
            (ReportDeliveryLimits(maximumPathBytes: 0), .pathBytes),
            (ReportDeliveryLimits(maximumPathBytes: hard.hardMaximumPathBytes + 1), .pathBytes),
            (ReportDeliveryLimits(maximumTotalPathBytes: 1), .totalPathBytes),
            (ReportDeliveryLimits(maximumTotalPathBytes: hard.hardMaximumTotalPathBytes + 1), .totalPathBytes),
            (ReportDeliveryLimits(maximumWorkUnits: 0), .workUnits),
            (ReportDeliveryLimits(maximumWorkUnits: hard.hardMaximumWorkUnits + 1), .workUnits),
            (ReportDeliveryLimits(cancellationCheckInterval: 0), .cancellationCheckInterval),
            (ReportDeliveryLimits(cancellationCheckInterval: 1_048_576 + 1), .cancellationCheckInterval)
        ]
        for (limits, expected) in cases {
            assertDeliveryError(.invalidLimit(expected)) {
                try deliver(source.plan, expectations: [], limits: limits)
            }
        }
    }

    func testOutputCountAboveMaximumThrowsInvalidLimit() throws {
        let source = try makeMultiFileSource()
        XCTAssertEqual(source.plan.outputs.count, 3)
        assertDeliveryError(.invalidLimit(.outputs)) {
            try deliver(
                source.plan,
                expectations: createExpectations(for: source.plan),
                limits: ReportDeliveryLimits(maximumOutputs: 1)
            )
        }
    }

    func testAmbientAndCallerManagedAuthoritiesPass() throws {
        for authority in [ReportDeliveryAccessAuthority.ambient, .callerManagedWhenRequired] as [ReportDeliveryAccessAuthority] {
            let source = try makeFileSource()
            let target = try fileTarget(source.plan.outputs[0])
            let plan = try deliver(
                source.plan,
                expectations: [.file(expectation: .createNew(parent: parentIdentity(for: target.requestedURL)), authority: authority)]
            )
            XCTAssertEqual(plan.outputs[0].disposition, .created)
        }
    }

    func testSecurityScopedExactItemAndDirectoryTreeCover() throws {
        let source = try makeFileSource()
        let target = try fileTarget(source.plan.outputs[0])
        let exact = ReportDeliveryAccessAuthority.securityScoped(resourceURL: target.identity.fileURL, coverage: .exactItem)
        let exactPlan = try deliver(
            source.plan,
            expectations: [.file(expectation: .createNew(parent: parentIdentity(for: target.requestedURL)), authority: exact)]
        )
        XCTAssertEqual(exactPlan.outputs[0].disposition, .created)
        let tree = ReportDeliveryAccessAuthority.securityScoped(
            resourceURL: target.requestedURL.deletingLastPathComponent(),
            coverage: .directoryTree
        )
        let treePlan = try deliver(
            source.plan,
            expectations: [.file(expectation: .createNew(parent: parentIdentity(for: target.requestedURL)), authority: tree)]
        )
        XCTAssertEqual(treePlan.outputs[0].disposition, .created)
        let root = ReportDeliveryAccessAuthority.securityScoped(
            resourceURL: URL(fileURLWithPath: "/", isDirectory: true),
            coverage: .directoryTree
        )
        let rootPlan = try deliver(
            source.plan,
            expectations: [.file(expectation: .createNew(parent: parentIdentity(for: target.requestedURL)), authority: root)]
        )
        XCTAssertEqual(rootPlan.outputs[0].disposition, .created)
    }

    func testSecurityScopedMismatchAndInvalidAuthorityThrow() throws {
        let source = try makeFileSource()
        let target = try fileTarget(source.plan.outputs[0])
        let sibling = ReportDeliveryAccessAuthority.securityScoped(
            resourceURL: URL(fileURLWithPath: "/tmp/macmerge-elsewhere", isDirectory: true),
            coverage: .directoryTree
        )
        assertDeliveryError(.authorityDoesNotCoverOutput(target.identity.canonicalPath)) {
            try deliver(
                source.plan,
                expectations: [.file(expectation: .createNew(parent: parentIdentity(for: target.requestedURL)), authority: sibling)]
            )
        }
        let wrongFile = ReportDeliveryAccessAuthority.securityScoped(
            resourceURL: URL(fileURLWithPath: "/tmp/macmerge-delivery/other.txt"),
            coverage: .exactItem
        )
        assertDeliveryError(.authorityDoesNotCoverOutput(target.identity.canonicalPath)) {
            try deliver(
                source.plan,
                expectations: [.file(expectation: .createNew(parent: parentIdentity(for: target.requestedURL)), authority: wrongFile)]
            )
        }
        let remote = URL(string: "https://example.com/scope")!
        assertDeliveryError(.invalidAuthority(remote.absoluteString)) {
            try deliver(
                source.plan,
                expectations: [
                    .file(
                        expectation: .createNew(parent: parentIdentity(for: target.requestedURL)),
                        authority: .securityScoped(resourceURL: remote, coverage: .exactItem))
                ]
            )
        }
    }

    func testValidateForPublicationEnforcesCompareAndSwapBindings() throws {
        let createSource = try makeFileSource()
        let createTarget = try fileTarget(createSource.plan.outputs[0])
        let createPlan = try deliver(
            createSource.plan,
            expectations: [.file(expectation: .createNew(parent: parentIdentity(for: createTarget.requestedURL)), authority: .ambient)]
        )
        XCTAssertNoThrow(
            try createPlan.validateForPublication(
                currentSnapshot: createSource.snapshot,
                linkedReports: [],
                currentRevisions: [nil],
                currentClipboardRevision: nil
            )
        )
        assertDeliveryError(.destinationMismatch("/tmp/macmerge-delivery/report.txt")) {
            try createPlan.validateForPublication(
                currentSnapshot: createSource.snapshot,
                linkedReports: [],
                currentRevisions: [makeFileRevision(canonicalURL: createTarget.identity.fileURL, byteCount: 1, contentSHA256: Array(repeating: 4, count: 32))],
                currentClipboardRevision: nil
            )
        }
        let replaceSource = try makeFileSource(overwritePolicy: .replaceExisting)
        let replaceTarget = try fileTarget(replaceSource.plan.outputs[0])
        let expected = makeFileRevision(
            canonicalURL: replaceTarget.identity.fileURL,
            byteCount: 5,
            contentSHA256: sha256Bytes(Data("payload".utf8))
        )
        let replacePlan = try deliver(
            replaceSource.plan,
            expectations: [
                .file(expectation: .replaceExisting(parent: parentIdentity(for: replaceTarget.requestedURL), expected: expected), authority: .ambient)
            ]
        )
        XCTAssertNoThrow(
            try replacePlan.validateForPublication(
                currentSnapshot: replaceSource.snapshot,
                linkedReports: [],
                currentRevisions: [expected],
                currentClipboardRevision: nil
            )
        )
        assertDeliveryError(.destinationMismatch("/tmp/macmerge-delivery/report.txt")) {
            try replacePlan.validateForPublication(
                currentSnapshot: replaceSource.snapshot,
                linkedReports: [],
                currentRevisions: [nil],
                currentClipboardRevision: nil
            )
        }
        let rotated = makeFileRevision(
            canonicalURL: replaceTarget.identity.fileURL,
            byteCount: 5,
            contentSHA256: Array(repeating: 6, count: 32)
        )
        assertDeliveryError(.destinationMismatch("/tmp/macmerge-delivery/report.txt")) {
            try replacePlan.validateForPublication(
                currentSnapshot: replaceSource.snapshot,
                linkedReports: [],
                currentRevisions: [rotated],
                currentClipboardRevision: nil
            )
        }
        let clipboardSource = try makeClipboardSource()
        let revision = clipboardRevision()
        let clipboardPlan = try deliver(clipboardSource.plan, expectations: [.clipboard(expectedRevision: revision)])
        XCTAssertNoThrow(
            try clipboardPlan.validateForPublication(
                currentSnapshot: clipboardSource.snapshot,
                linkedReports: [],
                currentRevisions: [nil],
                currentClipboardRevision: revision
            )
        )
        assertDeliveryError(.destinationMismatch("clipboard")) {
            try clipboardPlan.validateForPublication(
                currentSnapshot: clipboardSource.snapshot,
                linkedReports: [],
                currentRevisions: [nil],
                currentClipboardRevision: clipboardRevision(value: 2)
            )
        }
        assertDeliveryError(.destinationMismatch("clipboard")) {
            try clipboardPlan.validateForPublication(
                currentSnapshot: clipboardSource.snapshot,
                linkedReports: [],
                currentRevisions: [nil],
                currentClipboardRevision: nil
            )
        }
        assertDeliveryError(.expectationCountMismatch(expected: 1, actual: 0)) {
            try clipboardPlan.validateForPublication(
                currentSnapshot: clipboardSource.snapshot,
                linkedReports: [],
                currentRevisions: [],
                currentClipboardRevision: revision
            )
        }
    }

    func testValidateCurrentSnapshotMapsStaleAndChanged() throws {
        let source = try makeFileSource()
        let plan = try deliver(source.plan, expectations: createExpectations(for: source.plan))
        XCTAssertNoThrow(try plan.validateCurrentSnapshot(source.snapshot, linkedReports: []))
        let otherIdentity = ComparisonReportWorkflowSnapshotIdentity(
            rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        )
        let foreign = makeFileSnapshot(identity: otherIdentity, generation: source.snapshot.generation)
        assertDeliveryError(.staleSnapshot) {
            try plan.validateCurrentSnapshot(foreign, linkedReports: [])
        }
        let advanced = makeFileSnapshot(
            identity: source.snapshot.identity,
            generation: source.snapshot.generation + 1
        )
        assertDeliveryError(.staleSnapshot) {
            try plan.validateCurrentSnapshot(advanced, linkedReports: [])
        }
        let mutated = makeFileSnapshot(
            identity: source.snapshot.identity,
            generation: source.snapshot.generation,
            report: makeFileReport(secret: "mutated")
        )
        assertDeliveryError(.snapshotContentsChanged) {
            try plan.validateCurrentSnapshot(mutated, linkedReports: [])
        }
    }

    func testCommittedReceiptMatchesPlanAndRejectsBadEvidence() throws {
        let single = try singleCreatePlan()
        let outcome = ReportDeliveryExecutionOutcomeFactory.committed(plan: single, dispositions: [.created])
        guard case .committed(let receipt) = outcome else {
            return XCTFail("Expected committed outcome")
        }
        XCTAssertEqual(receipt.snapshot, single.receipt.snapshot)
        XCTAssertEqual(receipt.planSHA256, single.receipt.planSHA256)
        XCTAssertEqual(receipt.records.count, 1)
        XCTAssertEqual(receipt.records[0].role, single.outputs[0].role)
        XCTAssertEqual(receipt.records[0].identity, single.outputs[0].identity)
        XCTAssertEqual(receipt.records[0].disposition, .created)
        XCTAssertEqual(receipt.records[0].byteCount, single.outputs[0].successorByteCount)
        let short = ReportDeliveryExecutionOutcomeFactory.committed(plan: single, dispositions: [])
        XCTAssertEqual(short, .notCommitted(.failed("Delivery commit evidence does not match plan.")))
        let wrong = ReportDeliveryExecutionOutcomeFactory.committed(plan: single, dispositions: [.replaced])
        XCTAssertEqual(wrong, .notCommitted(.failed("Delivery commit evidence does not match plan.")))
        let multi = try multiCreatePlan()
        let multiOutcome = ReportDeliveryExecutionOutcomeFactory.committed(
            plan: multi,
            dispositions: [.created, .created, .created]
        )
        guard case .committed(let multiReceipt) = multiOutcome else {
            return XCTFail("Expected committed multi outcome")
        }
        XCTAssertEqual(multiReceipt.records.map(\.disposition), [.created, .created, .created])
        XCTAssertEqual(multiReceipt.records.map(\.byteCount), multi.outputs.map(\.successorByteCount))
    }

    func testNotCommittedRequiresStrictPrefix() throws {
        let single = try singleCreatePlan()
        let reasons: [ReportDeliveryNonCommitReason] = [
            .cancelled,
            .sourceChanged,
            .destinationChanged,
            .securityContractUnavailable,
            .rejected("denied"),
            .failed("boom")
        ]
        for reason in reasons {
            XCTAssertEqual(
                ReportDeliveryExecutionOutcomeFactory.notCommitted(plan: single, completedDispositions: [], reason: reason),
                .notCommitted(reason)
            )
        }
        XCTAssertEqual(
            ReportDeliveryExecutionOutcomeFactory.notCommitted(plan: single, completedDispositions: [.created], reason: .cancelled),
            .notCommitted(.failed("Delivery non-commit evidence does not match plan."))
        )
        XCTAssertEqual(
            ReportDeliveryExecutionOutcomeFactory.notCommitted(plan: single, completedDispositions: [.created, .created], reason: .cancelled),
            .notCommitted(.failed("Delivery non-commit evidence does not match plan."))
        )
        let multi = try multiCreatePlan()
        XCTAssertEqual(
            ReportDeliveryExecutionOutcomeFactory.notCommitted(plan: multi, completedDispositions: [.created, .created], reason: .destinationChanged),
            .notCommitted(.destinationChanged)
        )
        XCTAssertEqual(
            ReportDeliveryExecutionOutcomeFactory.notCommitted(plan: multi, completedDispositions: [.created, .replaced], reason: .destinationChanged),
            .notCommitted(.failed("Delivery non-commit evidence does not match plan."))
        )
    }

    func testUncertainRequiresStrictPrefix() throws {
        let multi = try multiCreatePlan()
        let outcome = ReportDeliveryExecutionOutcomeFactory.uncertain(
            plan: multi,
            completedDispositions: [.created, .created],
            reason: "stage-sync lost"
        )
        guard case .commitUncertain(let uncertainty) = outcome else {
            return XCTFail("Expected uncertain outcome")
        }
        XCTAssertEqual(uncertainty.completedRecords.count, 2)
        XCTAssertEqual(uncertainty.completedRecords.map(\.disposition), [.created, .created])
        XCTAssertEqual(uncertainty.completedRecords.map(\.byteCount), multi.outputs.prefix(2).map(\.successorByteCount))
        XCTAssertEqual(uncertainty.reason, "stage-sync lost")
        let full = ReportDeliveryExecutionOutcomeFactory.uncertain(
            plan: multi,
            completedDispositions: [.created, .created, .created],
            reason: "stage-sync lost"
        )
        guard case .commitUncertain(let fullMismatch) = full else {
            return XCTFail("Expected uncertain mismatch outcome")
        }
        XCTAssertTrue(fullMismatch.completedRecords.isEmpty)
        XCTAssertEqual(fullMismatch.reason, "Delivery uncertainty evidence does not match plan.")
        let over = ReportDeliveryExecutionOutcomeFactory.uncertain(
            plan: multi,
            completedDispositions: [.created, .created, .created, .created],
            reason: "stage-sync lost"
        )
        guard case .commitUncertain(let overMismatch) = over else {
            return XCTFail("Expected uncertain over-count outcome")
        }
        XCTAssertTrue(overMismatch.completedRecords.isEmpty)
        XCTAssertEqual(overMismatch.reason, "Delivery uncertainty evidence does not match plan.")
        let wrongValue = ReportDeliveryExecutionOutcomeFactory.uncertain(
            plan: multi,
            completedDispositions: [.created, .replaced],
            reason: "stage-sync lost"
        )
        guard case .commitUncertain(let valueMismatch) = wrongValue else {
            return XCTFail("Expected uncertain value-mismatch outcome")
        }
        XCTAssertTrue(valueMismatch.completedRecords.isEmpty)
        XCTAssertEqual(valueMismatch.reason, "Delivery uncertainty evidence does not match plan.")
    }

    func testExecutorContractIsRequired() throws {
        let plan = try singleCreatePlan()
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(
            plan.executorContract.pathResolution,
            .descriptorRelativeNoFollowFromPinnedCanonicalParent
        )
        XCTAssertEqual(
            plan.executorContract.publication,
            .privateStageSyncThenAtomicCreateOrExactReplacementInPlanOrder
        )
        XCTAssertEqual(
            plan.executorContract.snapshot,
            .validateExactSnapshotAndDestinationCASBeforeEffects
        )
        XCTAssertEqual(
            plan.executorContract.cancellation,
            .noMutationBeforePublicationThenCommittedCompareMissOrUncertain
        )
    }

    func testWorkLimitExceededThrows() throws {
        let source = try makeFileSource()
        assertDeliveryError(.workLimitExceeded(maximumUnits: 1)) {
            try deliver(
                source.plan,
                expectations: createExpectations(for: source.plan),
                limits: ReportDeliveryLimits(maximumWorkUnits: 1)
            )
        }
    }

    func testCancellationMapsToCancelled() async throws {
        let source = try makeClipboardSource()
        let request = ReportDeliveryRequest(
            plan: source.plan,
            expectations: [.clipboard(expectedRevision: clipboardRevision())]
        )
        let planningError = await Task { () -> ReportDeliveryError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ReportDeliveryWorkflow.plan(request)
                return nil
            } catch let error as ReportDeliveryError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(planningError, .cancelled)
    }

    func testErrorDescriptionsNeverEchoPayloadBytes() throws {
        let secret = "SECRET-9f2c4a-payload"
        let source = try makeFileSource(report: makeFileReport(secret: secret))
        let target = try fileTarget(source.plan.outputs[0])
        XCTAssertTrue(source.plan.outputs[0].output.string.contains(secret))
        XCTAssertThrowsError(
            try deliver(source.plan, expectations: [.clipboard(expectedRevision: clipboardRevision())])
        ) { error in
            let text = (error as? ReportDeliveryError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(text.contains("clipboard expectation for file output"))
            XCTAssertFalse(text.contains(secret), "Leaked payload in: \(text)")
        }
        let other = ReportDeliveryCanonicalFileIdentity(
            canonicalURL: URL(fileURLWithPath: "/tmp/macmerge-elsewhere", isDirectory: true),
            kind: .directory,
            deviceID: 11,
            fileID: 22,
            generation: 33
        )
        XCTAssertThrowsError(
            try deliver(source.plan, expectations: [.file(expectation: .createNew(parent: other), authority: .ambient)])
        ) { error in
            let text = (error as? ReportDeliveryError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(text.contains("/tmp/macmerge-delivery/report.txt"))
            XCTAssertFalse(text.contains(secret), "Leaked payload in: \(text)")
        }
        let revision = makeFileRevision(
            canonicalURL: target.identity.fileURL,
            byteCount: 7,
            contentSHA256: Array(repeating: 0, count: 32)
        )
        let tampered = try ReportDeliveryExistingFileSnapshot(revision: revision, data: Data("prefix:".utf8))
        let replaceSource = try makeFileSource(overwritePolicy: .replaceExisting, report: makeFileReport(secret: secret))
        let replaceTarget = try fileTarget(replaceSource.plan.outputs[0])
        XCTAssertThrowsError(
            try deliver(
                replaceSource.plan,
                expectations: [
                    .file(expectation: .appendExisting(parent: parentIdentity(for: replaceTarget.requestedURL), expected: tampered), authority: .ambient)
                ]
            )
        ) { error in
            let text = (error as? ReportDeliveryError)?.errorDescription ?? String(describing: error)
            XCTAssertFalse(text.contains(secret), "Leaked payload in: \(text)")
        }
        let size = source.plan.outputs[0].outputByteCount
        XCTAssertThrowsError(
            try deliver(
                source.plan,
                expectations: createExpectations(for: source.plan),
                limits: ReportDeliveryLimits(maximumSuccessorBytes: size - 1)
            )
        ) { error in
            let text = (error as? ReportDeliveryError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(text.contains("\(size - 1)"))
            XCTAssertFalse(text.contains(secret), "Leaked payload in: \(text)")
        }
    }

    func testPlanDigestIsDeterministicAndContentBound() throws {
        let first = try singleCreatePlan()
        let second = try singleCreatePlan()
        XCTAssertEqual(first.receipt.planSHA256, second.receipt.planSHA256)
        XCTAssertEqual(first.receipt.planSHA256.count, 32)
        let mutatedSource = try makeFileSource(report: makeFileReport(secret: "mutated"))
        let mutated = try deliver(mutatedSource.plan, expectations: createExpectations(for: mutatedSource.plan))
        XCTAssertNotEqual(first.receipt.planSHA256, mutated.receipt.planSHA256)
        XCTAssertEqual(first.receipt.successorByteCount, first.outputs.map(\.successorByteCount).reduce(0, +))
    }

    private func makeFileReport(secret: String = "alpha") -> ComparisonReport {
        ComparisonReport(
            title: "Delivery Fixture",
            columns: ["Path", "Value"],
            rows: [
                ComparisonReportRow(values: ["a.txt", secret]),
                ComparisonReportRow(values: ["m.txt", "m"])
            ]
        )
    }

    private func snapshotIdentity() -> ComparisonReportWorkflowSnapshotIdentity {
        ComparisonReportWorkflowSnapshotIdentity(
            rawValue: UUID(uuidString: "37D9752D-64B2-4DD7-B8B1-B25DD8686948")!
        )
    }

    private func makeFileSnapshot(
        identity: ComparisonReportWorkflowSnapshotIdentity? = nil,
        generation: UInt64 = 7,
        report: ComparisonReport? = nil
    ) -> ComparisonReportWorkflowSnapshot {
        ComparisonReportWorkflowSnapshot(
            identity: identity ?? snapshotIdentity(),
            generation: generation,
            source: .file(ComparisonReportFileSnapshot(report: report ?? makeFileReport()))
        )
    }

    private func makeFileSource(
        path: String = "/tmp/macmerge-delivery/report.txt",
        overwritePolicy: ComparisonReportOverwritePolicy = .failIfExists,
        report: ComparisonReport? = nil
    ) throws -> (snapshot: ComparisonReportWorkflowSnapshot, plan: ComparisonReportWorkflowPlan) {
        let snapshot = makeFileSnapshot(report: report)
        let request = ComparisonReportWorkflowRequest(
            snapshot: snapshot,
            scope: .all,
            format: .plainText,
            destination: .file(
                ComparisonReportFileDestination(
                    url: URL(fileURLWithPath: path),
                    overwritePolicy: overwritePolicy
                )
            )
        )
        return (snapshot, try ComparisonReportWorkflowPlanner.plan(request))
    }

    private func makeClipboardSource(
        report: ComparisonReport? = nil
    ) throws -> (snapshot: ComparisonReportWorkflowSnapshot, plan: ComparisonReportWorkflowPlan) {
        let snapshot = makeFileSnapshot(report: report)
        let request = ComparisonReportWorkflowRequest(
            snapshot: snapshot,
            scope: .all,
            format: .plainText,
            destination: .clipboard
        )
        return (snapshot, try ComparisonReportWorkflowPlanner.plan(request))
    }

    private func makeMultiFileSource(
        overwritePolicy: ComparisonReportOverwritePolicy = .failIfExists
    ) throws -> (snapshot: ComparisonReportWorkflowSnapshot, plan: ComparisonReportWorkflowPlan) {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let links = [
            ComparisonReportLinkedReport(
                identifier: "second",
                relativeOutputPath: "b.txt",
                report: ComparisonReport(
                    title: "Second",
                    columns: ["Value"],
                    rows: [ComparisonReportRow(values: ["s"])]
                ),
                snapshot: reference
            ),
            ComparisonReportLinkedReport(
                identifier: "first",
                relativeOutputPath: "a.txt",
                report: ComparisonReport(
                    title: "First",
                    columns: ["Value"],
                    rows: [ComparisonReportRow(values: ["f"])]
                ),
                snapshot: reference
            )
        ]
        let request = ComparisonReportWorkflowRequest(
            snapshot: snapshot,
            scope: .all,
            format: .plainText,
            destination: .file(
                ComparisonReportFileDestination(
                    url: URL(fileURLWithPath: "/tmp/macmerge-delivery/report.txt"),
                    overwritePolicy: overwritePolicy
                )
            ),
            linkedReports: links
        )
        return (snapshot, try ComparisonReportWorkflowPlanner.plan(request))
    }

    private func singleCreatePlan() throws -> ReportDeliveryPlan {
        let source = try makeFileSource()
        return try deliver(source.plan, expectations: createExpectations(for: source.plan))
    }

    private func multiCreatePlan() throws -> ReportDeliveryPlan {
        let source = try makeMultiFileSource()
        return try deliver(source.plan, expectations: createExpectations(for: source.plan))
    }

    private func createExpectations(
        for source: ComparisonReportWorkflowPlan
    ) -> [ReportDeliveryDestinationExpectation] {
        source.outputs.map { output in
            switch output.destination {
            case .clipboard:
                .clipboard(expectedRevision: clipboardRevision())
            case .file(let requestedURL, _, _, _):
                .file(expectation: .createNew(parent: parentIdentity(for: requestedURL)), authority: .ambient)
            }
        }
    }

    private func fileTarget(
        _ output: ComparisonReportPlannedOutput
    ) throws -> (requestedURL: URL, identity: ComparisonReportCanonicalOutputIdentity) {
        guard case .file(let requestedURL, let identity, _, _) = output.destination else {
            throw TestError.expectedFileDestination
        }
        return (requestedURL, identity)
    }

    private func parentIdentity(for requestedURL: URL) -> ReportDeliveryCanonicalFileIdentity {
        ReportDeliveryCanonicalFileIdentity(
            canonicalURL: requestedURL.deletingLastPathComponent(),
            kind: .directory,
            deviceID: 11,
            fileID: 22,
            generation: 33
        )
    }

    private func sha256Bytes(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private func makeFileRevision(
        canonicalURL: URL,
        byteCount: UInt64,
        contentSHA256: [UInt8]
    ) -> ReportDeliveryFileRevision {
        ReportDeliveryFileRevision(
            identity: ReportDeliveryCanonicalFileIdentity(
                canonicalURL: canonicalURL,
                kind: .regularFile,
                deviceID: 101,
                fileID: 102,
                generation: 103
            ),
            byteCount: byteCount,
            linkCount: 1,
            permissions: 0o644,
            metadataByteCount: 16,
            contentSHA256: contentSHA256,
            metadataSHA256: Array(repeating: 9, count: 32)
        )
    }

    private func makeExistingSnapshot(
        data: Data,
        canonicalURL: URL
    ) throws -> ReportDeliveryExistingFileSnapshot {
        let revision = makeFileRevision(
            canonicalURL: canonicalURL,
            byteCount: UInt64(data.count),
            contentSHA256: sha256Bytes(data)
        )
        return try ReportDeliveryExistingFileSnapshot(revision: revision, data: data)
    }

    private func clipboardRevision(value: UInt64 = 1) -> ReportDeliveryClipboardRevision {
        ReportDeliveryClipboardRevision(
            brokerIdentifier: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            epoch: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            value: value
        )
    }

    private func deliver(
        _ source: ComparisonReportWorkflowPlan,
        expectations: [ReportDeliveryDestinationExpectation],
        limits: ReportDeliveryLimits = .default
    ) throws -> ReportDeliveryPlan {
        try ReportDeliveryWorkflow.plan(ReportDeliveryRequest(plan: source, expectations: expectations, limits: limits))
    }

    private func assertDeliveryError<T>(
        _ expected: ReportDeliveryError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ReportDeliveryError, expected, file: file, line: line)
        }
    }

    private enum TestError: Error {
        case expectedFileDestination
    }
}
