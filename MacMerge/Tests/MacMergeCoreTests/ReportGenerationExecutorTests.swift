import Foundation
import XCTest

@testable import MacMergeCore

final class ReportGenerationExecutorTests: XCTestCase {
    func testFileSourceAllAndSelectedScopesNeverPublish() async throws {
        let allSnapshot = makeFileSnapshot(selectedRowIndices: [0, 1])
        let allPlan = try filePlan(snapshot: allSnapshot, scope: .all)
        let partialSnapshot = makeFileSnapshot(selectedRowIndices: [1])
        let selectedPlan = try filePlan(snapshot: partialSnapshot, scope: .selected)

        XCTAssertEqual(selectedPlan.scope, .selected)
        for (plan, snapshot) in [(allPlan, allSnapshot), (selectedPlan, partialSnapshot)] {
            let outcome = await authorizedFileExecutor().execute(
                plan,
                validating: snapshot,
                linkedReports: []
            )
            assertGlobalContractFailure(outcome)
            XCTAssertEqual(plan.outputs.count, 1)
        }
        XCTAssertNotEqual(
            allPlan.primaryOutput.output.data,
            selectedPlan.primaryOutput.output.data
        )
    }

    func testFolderSourceNeverPublishes() async throws {
        let snapshot = makeFolderSnapshot()
        let plan = try filePlan(
            snapshot: snapshot,
            scope: .all,
            format: .csv,
            path: "/tmp/macmerge-executor/folder.csv"
        )

        let outcome = await authorizedFileExecutor().execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertGlobalContractFailure(outcome)
    }

    func testAllFormatsNeverPublish() async throws {
        for format in ComparisonReportFormat.allCases {
            let snapshot = makeFileSnapshot()
            let plan = try plan(
                snapshot: snapshot,
                format: format,
                destination: .clipboard
            )
            let executor = ReportGenerationExecutor(
                authority: ReportGenerationSandboxAuthority(allowsClipboard: true)
            )
            let outcome = await executor.execute(
                plan,
                validating: snapshot,
                linkedReports: []
            )
            assertGlobalContractFailure(outcome)
            XCTAssertEqual(executor.describe(plan).format, format)
            XCTAssertGreaterThan(plan.primaryOutput.outputByteCount, 0)
        }
    }

    func testClipboardOutputAllowedYieldsGlobalContractFailure() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try plan(snapshot: snapshot, destination: .clipboard)
        let executor = ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(allowsClipboard: true)
        )

        let outcome = await executor.execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertGlobalContractFailure(outcome)
    }

    func testClipboardDeniedYieldsClipboardUnavailable() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try plan(snapshot: snapshot, destination: .clipboard)

        let outcome = await ReportGenerationExecutor().execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        guard case .failed(let failure) = outcome else {
            return XCTFail("Expected failure, got \(outcome)")
        }
        XCTAssertEqual(failure.code, .clipboardUnavailable)
        XCTAssertEqual(failure.outputIdentity, .clipboard)
        XCTAssertTrue(failure.completedOutputs.isEmpty)
    }

    func testFileOutputAuthorizedYieldsGlobalContractFailure() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try filePlan(snapshot: snapshot)

        let outcome = await authorizedFileExecutor().execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertGlobalContractFailure(outcome)
    }

    func testLinkedReportsEchoInReceiptAndNeverPublish() async throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let links = [
            ComparisonReportLinkedReport(
                identifier: "child",
                relativeOutputPath: "child.csv",
                report: makeFileReport(),
                snapshot: reference
            )
        ]
        let plan = try filePlan(
            snapshot: snapshot,
            format: .csv,
            path: "/tmp/macmerge-executor/report.csv",
            links: links
        )
        XCTAssertEqual(plan.outputs.count, 2)

        let receipt = authorizedFileExecutor().describe(plan)
        XCTAssertEqual(receipt.outputs.count, 2)
        XCTAssertEqual(receipt.outputs[0].role, .primary)
        XCTAssertEqual(
            receipt.outputs[1].role,
            .linked(identifier: "child", directoryResultID: nil)
        )

        let outcome = await authorizedFileExecutor().execute(
            plan,
            validating: snapshot,
            linkedReports: links
        )
        assertGlobalContractFailure(outcome)
    }

    func testOverwritePoliciesEchoAndFailIfExistsStaysGlobal() async throws {
        let snapshot = makeFileSnapshot()
        let createPlan = try filePlan(snapshot: snapshot, overwritePolicy: .failIfExists)
        let replacePlan = try filePlan(snapshot: snapshot, overwritePolicy: .replaceExisting)

        XCTAssertEqual(
            authorizedFileExecutor().describe(createPlan).outputs.map(\.overwritePolicy),
            [.failIfExists]
        )
        XCTAssertEqual(
            authorizedFileExecutor().describe(replacePlan).outputs.map(\.overwritePolicy),
            [.replaceExisting]
        )

        for plan in [createPlan, replacePlan] {
            let outcome = await authorizedFileExecutor().execute(
                plan,
                validating: snapshot,
                linkedReports: []
            )
            assertGlobalContractFailure(outcome)
        }

        let denied = await ReportGenerationExecutor().execute(
            createPlan,
            validating: snapshot,
            linkedReports: []
        )
        guard case .failed(let failure) = denied else {
            return XCTFail("Expected failure, got \(denied)")
        }
        XCTAssertEqual(failure.code, .contractUnsupported)
        XCTAssertNil(failure.outputIdentity)
        XCTAssertTrue(failure.completedOutputs.isEmpty)
        XCTAssertNotEqual(failure.code, .outputAlreadyExists)
    }

    func testScopedAccessWithoutScopeDeniedEvenWhenParentAllowlisted() async throws {
        let url = URL(fileURLWithPath: "/tmp/macmerge-executor/report.txt")
        let snapshot = makeFileSnapshot()
        let plan = try plan(
            snapshot: snapshot,
            destination: .file(
                ComparisonReportFileDestination(
                    url: url,
                    overwritePolicy: .failIfExists,
                    sandboxAccess: .securityScoped(
                        resourceURL: url,
                        coverage: .exactFile
                    )
                )
            )
        )
        let authority = ReportGenerationSandboxAuthority(
            writableParentPaths: ["/tmp/macmerge-executor"]
        )
        XCTAssertFalse(authority.authorizes(plan))
        XCTAssertNotNil(authority.uncoveredOutputIdentity(plan))

        let outcome = await ReportGenerationExecutor(authority: authority).execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        guard case .failed(let failure) = outcome else {
            return XCTFail("Expected failure, got \(outcome)")
        }
        XCTAssertEqual(failure.code, .securityScopeUnavailable)
        XCTAssertEqual(
            failure.outputIdentity,
            plan.primaryOutput.destination.outputIdentity
        )
        XCTAssertTrue(failure.completedOutputs.isEmpty)
    }

    func testForgedParentDeniedButExactParentAdmitted() throws {
        let snapshot = makeFileSnapshot()
        let plan = try filePlan(snapshot: snapshot)

        XCTAssertNil(
            ReportGenerationSandboxAuthority(
                writableParentPaths: ["/tmp/macmerge-executor"]
            ).uncoveredOutputIdentity(plan)
        )
        XCTAssertNotNil(
            ReportGenerationSandboxAuthority(
                writableParentPaths: ["/tmp/macmerge-other"]
            ).uncoveredOutputIdentity(plan)
        )
        XCTAssertNotNil(
            ReportGenerationSandboxAuthority().uncoveredOutputIdentity(plan)
        )
    }

    func testExtensionMismatchRejectedAtPlan() {
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .extensionMismatch)) {
            try filePlan(
                snapshot: makeFileSnapshot(),
                format: .csv,
                path: "/tmp/macmerge-executor/report.txt"
            )
        }
    }

    func testNonFileURLRejectedAtPlan() {
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .notFileURL)) {
            try plan(
                snapshot: makeFileSnapshot(),
                destination: .file(
                    ComparisonReportFileDestination(
                        url: URL(string: "https://example.com/report.txt")!
                    )
                )
            )
        }
    }

    func testDuplicateLinkedPathsRejectedAtPlan() {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        do {
            _ = try filePlan(
                snapshot: snapshot,
                format: .csv,
                path: "/tmp/macmerge-executor/report.csv",
                links: [
                    makeLink(identifier: "a", path: "dup.csv", snapshot: reference),
                    makeLink(identifier: "b", path: "dup.csv", snapshot: reference)
                ]
            )
            XCTFail("Expected duplicate output identity error")
        } catch let error as ComparisonReportWorkflowError {
            guard case .duplicateOutputIdentity = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOverlappingLinkedPathsRejectedAtPlan() {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        do {
            _ = try filePlan(
                snapshot: snapshot,
                format: .csv,
                path: "/tmp/macmerge-executor/report.csv",
                links: [
                    makeLink(
                        identifier: "nested",
                        path: "report.csv/child.csv",
                        snapshot: reference
                    )
                ]
            )
            XCTFail("Expected overlapping output identities error")
        } catch let error as ComparisonReportWorkflowError {
            guard case .overlappingOutputIdentities = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStaleGenerationFailsSnapshot() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try filePlan(snapshot: snapshot)
        let stale = makeFileSnapshot(generation: snapshot.generation + 1)

        let outcome = await authorizedFileExecutor().execute(
            plan,
            validating: stale,
            linkedReports: []
        )
        assertFailure(outcome, code: .staleSnapshot, identity: nil)
    }

    func testStaleContentsFailsSnapshot() async throws {
        let snapshot = makeFileSnapshot(selectedRowIndices: [0])
        let plan = try filePlan(snapshot: snapshot)
        let changed = makeFileSnapshot(selectedRowIndices: [1])

        let outcome = await authorizedFileExecutor().execute(
            plan,
            validating: changed,
            linkedReports: []
        )
        assertFailure(outcome, code: .staleSnapshot, identity: nil)
    }

    func testInvalidLinkedRelativePathFailsInvalidPlan() async throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let plannedLinks = [
            makeLink(identifier: "child", path: "child.csv", snapshot: reference)
        ]
        let plan = try filePlan(
            snapshot: snapshot,
            format: .csv,
            path: "/tmp/macmerge-executor/report.csv",
            links: plannedLinks
        )
        let forged = [
            makeLink(identifier: "child", path: "../evil.csv", snapshot: reference)
        ]

        let outcome = await authorizedFileExecutor().execute(
            plan,
            validating: snapshot,
            linkedReports: forged
        )
        assertFailure(outcome, code: .invalidPlan, identity: nil)
    }

    func testStaleSourceProbeFailsBeforeDestination() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try plan(snapshot: snapshot, destination: .clipboard)
        let executor = ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(allowsClipboard: true),
            revalidation: ReportGenerationRevalidation(
                sourcesCurrent: { _ in false },
                destinationsCurrent: { _ in false }
            )
        )

        let outcome = await executor.execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertFailure(outcome, code: .staleSnapshot, identity: nil)
    }

    func testStaleDestinationProbeFailsContract() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try plan(snapshot: snapshot, destination: .clipboard)
        let executor = ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(allowsClipboard: true),
            revalidation: ReportGenerationRevalidation(
                sourcesCurrent: { _ in true },
                destinationsCurrent: { _ in false }
            )
        )

        let outcome = await executor.execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertGlobalContractFailure(outcome)
    }

    func testAuthorityCheckedBeforeRevalidation() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try plan(snapshot: snapshot, destination: .clipboard)
        let executor = ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(),
            revalidation: .stale
        )

        let outcome = await executor.execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        guard case .failed(let failure) = outcome else {
            return XCTFail("Expected failure, got \(outcome)")
        }
        XCTAssertEqual(failure.code, .clipboardUnavailable)
    }

    func testCancelledTaskYieldsCancelledReceipt() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try plan(snapshot: snapshot, destination: .clipboard)
        let executor = ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(allowsClipboard: true)
        )
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            return await executor.execute(
                plan,
                validating: snapshot,
                linkedReports: []
            )
        }
        task.cancel()
        continuation.finish()

        let outcome = await task.value
        guard case .cancelled(let cancellation) = outcome else {
            return XCTFail("Expected cancellation, got \(outcome)")
        }
        XCTAssertTrue(cancellation.completedOutputs.isEmpty)
    }

    func testReceiptEchoesPlanExactly() throws {
        let snapshot = makeFileSnapshot(selectedRowIndices: [0])
        let plan = try filePlan(
            snapshot: snapshot,
            scope: .selected,
            path: "/tmp/macmerge-executor/report.txt",
            openAfterGeneration: true
        )
        let receipt = authorizedFileExecutor().describe(plan)

        XCTAssertEqual(receipt.snapshot, plan.snapshotFingerprint.reference)
        XCTAssertEqual(receipt.scope, .selected)
        XCTAssertEqual(receipt.format, .plainText)
        XCTAssertEqual(receipt.outputs.count, plan.outputs.count)
        XCTAssertEqual(
            receipt.outputs.map(\.byteCount),
            plan.outputs.map(\.outputByteCount)
        )
        XCTAssertEqual(
            receipt.outputs.map(\.identity),
            plan.outputs.map(\.destination.outputIdentity)
        )
        XCTAssertEqual(receipt.openAfterGeneration, true)
        XCTAssertEqual(receipt.executorContract, ComparisonReportExecutorContract.required)
    }

    func testClipboardReceiptCarriesNoPolicyOrScope() throws {
        let plan = try plan(snapshot: makeFileSnapshot(), destination: .clipboard)
        let receipt = ReportGenerationExecutor().describe(plan)

        XCTAssertEqual(receipt.outputs.count, 1)
        XCTAssertNil(receipt.outputs[0].overwritePolicy)
        XCTAssertNil(receipt.outputs[0].sandboxAccess)
        XCTAssertEqual(receipt.openAfterGeneration, false)
    }

    func testNeverWritesToFilesystem() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let target = directory.appendingPathComponent("report.txt")
        let snapshot = makeFileSnapshot()
        let plan = try plan(
            snapshot: snapshot,
            destination: .file(
                ComparisonReportFileDestination(url: target)
            )
        )
        let executor = ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(
                writableParentPaths: [directory.path]
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        let outcome = await executor.execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertGlobalContractFailure(outcome)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            []
        )
    }

    func testFolderSelectedScopeNeverPublishes() async throws {
        let result = DirectoryResult(
            left: DirectoryEntryMetadata(
                relativePath: "alpha.txt",
                kind: .file,
                byteCount: 10
            ),
            right: nil,
            status: .leftOnly
        )
        let folderResults = DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/tmp/macmerge-left", isDirectory: true),
            rightRoot: URL(fileURLWithPath: "/tmp/macmerge-right", isDirectory: true),
            results: [result],
            selectedIDs: [result.id]
        )
        let snapshot = ComparisonReportWorkflowSnapshot(
            identity: ComparisonReportWorkflowSnapshotIdentity(
                rawValue: UUID(uuidString: "37D9752D-64B2-4DD7-B8B1-B25DD8686948")!
            ),
            generation: 7,
            source: .folder(
                ComparisonReportFolderSnapshot(
                    rootIdentity: ComparisonReportWorkflowDirectoryRootIdentity(
                        left: .init(deviceID: 1, fileID: 2, generation: 3),
                        right: .init(deviceID: 4, fileID: 5, generation: 6)
                    ),
                    results: folderResults
                )
            )
        )
        let plan = try filePlan(
            snapshot: snapshot,
            scope: .selected,
            format: .csv,
            path: "/tmp/macmerge-executor/folder.csv"
        )
        let outcome = await authorizedFileExecutor().execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertGlobalContractFailure(outcome)
    }

    func testFileHtmlOpenAfterGenerationNeverPublishes() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try filePlan(
            snapshot: snapshot,
            format: .html,
            path: "/tmp/macmerge-executor/report.html",
            openAfterGeneration: true
        )
        XCTAssertTrue(authorizedFileExecutor().describe(plan).openAfterGeneration)
        let outcome = await authorizedFileExecutor().execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertGlobalContractFailure(outcome)
    }

    func testForgedAmbientDeniedYieldsContractUnsupported() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try filePlan(snapshot: snapshot)
        let outcome = await ReportGenerationExecutor().execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertFailure(outcome, code: .contractUnsupported, identity: nil)
    }

    func testIdentityMismatchFailsStaleSnapshot() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try filePlan(snapshot: snapshot)
        let mismatched = ComparisonReportWorkflowSnapshot(
            identity: ComparisonReportWorkflowSnapshotIdentity(rawValue: UUID()),
            generation: snapshot.generation,
            source: snapshot.source
        )
        let outcome = await authorizedFileExecutor().execute(
            plan,
            validating: mismatched,
            linkedReports: []
        )
        assertFailure(outcome, code: .staleSnapshot, identity: nil)
    }

    func testFileDestinationStaleProbeFailsContract() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try filePlan(snapshot: snapshot)
        let executor = ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(
                writableParentPaths: ["/tmp/macmerge-executor"]
            ),
            revalidation: ReportGenerationRevalidation(
                sourcesCurrent: { _ in true },
                destinationsCurrent: { _ in false }
            )
        )
        let outcome = await executor.execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        assertGlobalContractFailure(outcome)
    }

    func testCancellationAfterSourcesCurrentYieldsCancelled() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try plan(snapshot: snapshot, destination: .clipboard)
        let executor = ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(allowsClipboard: true),
            revalidation: ReportGenerationRevalidation(
                sourcesCurrent: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return true
                },
                destinationsCurrent: { _ in true }
            )
        )
        let outcome = await executor.execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        guard case .cancelled(let cancellation) = outcome else {
            return XCTFail("Expected cancellation, got \(outcome)")
        }
        XCTAssertTrue(cancellation.completedOutputs.isEmpty)
    }

    func testCancellationAfterDestinationsCurrentYieldsCancelled() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try plan(snapshot: snapshot, destination: .clipboard)
        let executor = ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(allowsClipboard: true),
            revalidation: ReportGenerationRevalidation(
                sourcesCurrent: { _ in true },
                destinationsCurrent: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return true
                }
            )
        )
        let outcome = await executor.execute(
            plan,
            validating: snapshot,
            linkedReports: []
        )
        guard case .cancelled(let cancellation) = outcome else {
            return XCTFail("Expected cancellation, got \(outcome)")
        }
        XCTAssertTrue(cancellation.completedOutputs.isEmpty)
    }

    func testCancelledTaskPreemptsInvalidPlan() async throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let plannedLinks = [
            makeLink(identifier: "child", path: "child.csv", snapshot: reference)
        ]
        let plan = try filePlan(
            snapshot: snapshot,
            format: .csv,
            path: "/tmp/macmerge-executor/report.csv",
            links: plannedLinks
        )
        let forged = [
            makeLink(identifier: "child", path: "../evil.csv", snapshot: reference)
        ]
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let executor = authorizedFileExecutor()
        let task = Task {
            for await _ in stream { break }
            return await executor.execute(
                plan,
                validating: snapshot,
                linkedReports: forged
            )
        }
        task.cancel()
        continuation.finish()
        let outcome = await task.value
        guard case .cancelled(let cancellation) = outcome else {
            return XCTFail("Expected cancellation, got \(outcome)")
        }
        XCTAssertTrue(cancellation.completedOutputs.isEmpty)
    }

    func testValidationCancelledMapsToCancelled() async throws {
        let snapshot = makeFileSnapshot()
        let plan = try filePlan(snapshot: snapshot)
        let executor = authorizedFileExecutor()
        let validationError: ComparisonReportWorkflowError? = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try plan.validateCurrentSnapshot(snapshot, linkedReports: [])
                return nil
            } catch let error as ComparisonReportWorkflowError {
                return error
            } catch {
                return nil
            }
        }.value
        guard case .cancelled = validationError else {
            return XCTFail("Expected cancelled, got \(String(describing: validationError))")
        }
        let outcome = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await executor.execute(
                plan,
                validating: snapshot,
                linkedReports: []
            )
        }.value
        guard case .cancelled(let cancellation) = outcome else {
            return XCTFail("Expected cancellation, got \(outcome)")
        }
        XCTAssertTrue(cancellation.completedOutputs.isEmpty)
    }

    func testPlannerRejectsMalformedFileURLs() {
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .relativeURL)) {
            try plan(
                snapshot: makeFileSnapshot(),
                destination: .file(
                    ComparisonReportFileDestination(
                        url: URL(
                            string: "report.txt",
                            relativeTo: URL(fileURLWithPath: "/tmp/macmerge-executor/")
                        )!
                    )
                )
            )
        }
        var remoteComponents = URLComponents()
        remoteComponents.scheme = "file"
        remoteComponents.host = "example.com"
        remoteComponents.path = "/tmp/macmerge-executor/report.txt"
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .remoteHost)) {
            try plan(
                snapshot: makeFileSnapshot(),
                destination: .file(
                    ComparisonReportFileDestination(url: remoteComponents.url!)
                )
            )
        }
        var credentialedComponents = URLComponents()
        credentialedComponents.scheme = "file"
        credentialedComponents.user = "user"
        credentialedComponents.host = "localhost"
        credentialedComponents.path = "/tmp/macmerge-executor/report.txt"
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .credentialsOrPort)) {
            try plan(
                snapshot: makeFileSnapshot(),
                destination: .file(
                    ComparisonReportFileDestination(url: credentialedComponents.url!)
                )
            )
        }
        var queryComponents = URLComponents()
        queryComponents.scheme = "file"
        queryComponents.path = "/tmp/macmerge-executor/report.txt"
        queryComponents.query = "x=1"
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .queryOrFragment)) {
            try plan(
                snapshot: makeFileSnapshot(),
                destination: .file(
                    ComparisonReportFileDestination(url: queryComponents.url!)
                )
            )
        }
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .directoryURL)) {
            try plan(
                snapshot: makeFileSnapshot(),
                destination: .file(
                    ComparisonReportFileDestination(
                        url: URL(
                            fileURLWithPath: "/tmp/macmerge-executor/",
                            isDirectory: true
                        )
                    )
                )
            )
        }
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .directoryURL)) {
            try plan(
                snapshot: makeFileSnapshot(),
                destination: .file(
                    ComparisonReportFileDestination(
                        url: URL(fileURLWithPath: "/", isDirectory: false)
                    )
                )
            )
        }
    }

    func testManualPlanUnreachableProvesStructuralChecksDefensive() throws {
        let snapshot = makeFileSnapshot()
        let plan = try filePlan(snapshot: snapshot)
        XCTAssertEqual(
            plan.executorContract,
            ComparisonReportExecutorContract.required,
            "Planner alone constructs plans while init stays fileprivate, so structural and containment rejections stay defensive"
        )
        XCTAssertEqual(plan.outputs.count, 1)
    }

    // MARK: - Helpers

    private func authorizedFileExecutor() -> ReportGenerationExecutor {
        ReportGenerationExecutor(
            authority: ReportGenerationSandboxAuthority(
                writableParentPaths: ["/tmp/macmerge-executor"]
            )
        )
    }

    private func assertGlobalContractFailure(
        _ outcome: ComparisonReportExecutionOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertFailure(outcome, code: .contractUnsupported, identity: nil, file: file, line: line)
    }

    private func assertFailure(
        _ outcome: ComparisonReportExecutionOutcome,
        code: ComparisonReportExecutionFailureCode,
        identity: ComparisonReportOutputIdentity?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failed(let failure) = outcome else {
            return XCTFail("Expected failure, got \(outcome)", file: file, line: line)
        }
        XCTAssertEqual(failure.code, code, file: file, line: line)
        XCTAssertEqual(failure.outputIdentity, identity, file: file, line: line)
        XCTAssertTrue(failure.completedOutputs.isEmpty, file: file, line: line)
    }

    private func assertWorkflowError<T>(
        _ expected: ComparisonReportWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? ComparisonReportWorkflowError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func makeFileReport() -> ComparisonReport {
        ComparisonReport(
            title: "Report",
            columns: ["Path", "Value"],
            rows: [
                ComparisonReportRow(values: ["b.txt", "b"], sortKey: "b"),
                ComparisonReportRow(values: ["a.txt", "a"], sortKey: "a")
            ],
            summary: ComparisonReportSummary(items: [
                ComparisonReportSummaryItem(label: "Items", value: "2")
            ])
        )
    }

    private func makeFileSnapshot(
        generation: UInt64 = 7,
        selectedRowIndices: Set<Int> = []
    ) -> ComparisonReportWorkflowSnapshot {
        ComparisonReportWorkflowSnapshot(
            identity: ComparisonReportWorkflowSnapshotIdentity(
                rawValue: UUID(uuidString: "37D9752D-64B2-4DD7-B8B1-B25DD8686948")!
            ),
            generation: generation,
            source: .file(
                ComparisonReportFileSnapshot(
                    report: makeFileReport(),
                    selectedRowIndices: selectedRowIndices
                )
            )
        )
    }

    private func makeFolderSnapshot() -> ComparisonReportWorkflowSnapshot {
        let result = DirectoryResult(
            left: DirectoryEntryMetadata(
                relativePath: "alpha.txt",
                kind: .file,
                byteCount: 10
            ),
            right: nil,
            status: .leftOnly
        )
        return ComparisonReportWorkflowSnapshot(
            identity: ComparisonReportWorkflowSnapshotIdentity(
                rawValue: UUID(uuidString: "37D9752D-64B2-4DD7-B8B1-B25DD8686948")!
            ),
            generation: 7,
            source: .folder(
                ComparisonReportFolderSnapshot(
                    rootIdentity: ComparisonReportWorkflowDirectoryRootIdentity(
                        left: .init(deviceID: 1, fileID: 2, generation: 3),
                        right: .init(deviceID: 4, fileID: 5, generation: 6)
                    ),
                    results: DirectoryResults(
                        leftRoot: URL(fileURLWithPath: "/tmp/macmerge-left", isDirectory: true),
                        rightRoot: URL(fileURLWithPath: "/tmp/macmerge-right", isDirectory: true),
                        results: [result]
                    )
                )
            )
        )
    }

    private func makeLink(
        identifier: String,
        path: String,
        snapshot: ComparisonReportWorkflowSnapshotReference
    ) -> ComparisonReportLinkedReport {
        ComparisonReportLinkedReport(
            identifier: identifier,
            relativeOutputPath: path,
            report: makeFileReport(),
            snapshot: snapshot
        )
    }

    private func plan(
        snapshot: ComparisonReportWorkflowSnapshot,
        scope: ComparisonReportScope = .all,
        format: ComparisonReportFormat = .plainText,
        destination: ComparisonReportOutputDestination,
        links: [ComparisonReportLinkedReport] = [],
        openAfterGeneration: Bool = false
    ) throws -> ComparisonReportWorkflowPlan {
        try ComparisonReportWorkflowPlanner.plan(
            ComparisonReportWorkflowRequest(
                snapshot: snapshot,
                scope: scope,
                format: format,
                destination: destination,
                linkedReports: links,
                openAfterGeneration: openAfterGeneration
            )
        )
    }

    private func filePlan(
        snapshot: ComparisonReportWorkflowSnapshot,
        scope: ComparisonReportScope = .all,
        format: ComparisonReportFormat = .plainText,
        path: String = "/tmp/macmerge-executor/report.txt",
        overwritePolicy: ComparisonReportOverwritePolicy = .failIfExists,
        links: [ComparisonReportLinkedReport] = [],
        openAfterGeneration: Bool = false
    ) throws -> ComparisonReportWorkflowPlan {
        try plan(
            snapshot: snapshot,
            scope: scope,
            format: format,
            destination: .file(
                ComparisonReportFileDestination(
                    url: URL(fileURLWithPath: path),
                    overwritePolicy: overwritePolicy
                )
            ),
            links: links,
            openAfterGeneration: openAfterGeneration
        )
    }
}
