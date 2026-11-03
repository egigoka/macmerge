import CryptoKit
import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class PatchExecutorStubTests: XCTestCase {
    private static let stubMessage =
        "Stub executor performs no filesystem, pasteboard, or UI mutation."

    func testClipboardAllowedIsNeverCommittedRejected() async throws {
        let plan = try clipboardPlan()
        let executor = PatchGenerationStubExecutor(
            authority: PatchGenerationStubSandboxAuthority(allowsClipboard: true)
        )

        let outcome = await PatchGenerationWorkflow.execute(plan, with: executor)

        guard case .notCommitted(let reason) = outcome.state else {
            return XCTFail("Stub must never commit, got \(outcome.state)")
        }
        XCTAssertEqual(reason, .rejected(Self.stubMessage))
    }

    func testClipboardDeniedBySandbox() async throws {
        let plan = try clipboardPlan()

        let outcome = await PatchGenerationWorkflow.execute(
            plan,
            with: PatchGenerationStubExecutor()
        )

        guard case .notCommitted(let reason) = outcome.state else {
            return XCTFail("Expected non-commit, got \(outcome.state)")
        }
        XCTAssertEqual(reason, .securityContractUnavailable)
    }

    func testFileAllowListAdmitsBoundParentOnly() async throws {
        let directory = try makeTemporaryDirectory()
        let parent = try canonicalIdentity(directory, kind: .directory)
        let allowedParent = parent.canonicalURL.path(percentEncoded: false)
        let plan = try createPlan(directory: directory, destinationLeaf: "output.patch")

        let admitted = await PatchGenerationWorkflow.execute(
            plan,
            with: PatchGenerationStubExecutor(
                authority: PatchGenerationStubSandboxAuthority(
                    writableParentPaths: [allowedParent]
                )
            )
        )
        guard case .notCommitted(let admittedReason) = admitted.state else {
            return XCTFail("Expected non-commit, got \(admitted.state)")
        }
        XCTAssertEqual(admittedReason, .rejected(Self.stubMessage))

        let denied = await PatchGenerationWorkflow.execute(
            plan,
            with: PatchGenerationStubExecutor()
        )
        guard case .notCommitted(let deniedReason) = denied.state else {
            return XCTFail("Expected non-commit, got \(denied.state)")
        }
        XCTAssertEqual(deniedReason, .securityContractUnavailable)

        let authority = PatchGenerationStubSandboxAuthority(
            writableParentPaths: [allowedParent]
        )
        XCTAssertTrue(authority.authorizes(plan.mutation))
        XCTAssertFalse(
            PatchGenerationStubSandboxAuthority().authorizes(plan.mutation)
        )
    }

    func testStaleSourceProbeRejectsBeforeDestination() async throws {
        let plan = try clipboardPlan()
        let executor = PatchGenerationStubExecutor(
            authority: PatchGenerationStubSandboxAuthority(allowsClipboard: true),
            revalidation: PatchGenerationStubRevalidation(
                sourcesCurrent: { _ in false },
                destinationCurrent: { _ in false }
            )
        )

        let outcome = await PatchGenerationWorkflow.execute(plan, with: executor)

        guard case .notCommitted(let reason) = outcome.state else {
            return XCTFail("Expected non-commit, got \(outcome.state)")
        }
        XCTAssertEqual(reason, .sourceChanged)
    }

    func testStaleDestinationProbeRejects() async throws {
        let plan = try clipboardPlan()
        let executor = PatchGenerationStubExecutor(
            authority: PatchGenerationStubSandboxAuthority(allowsClipboard: true),
            revalidation: PatchGenerationStubRevalidation(
                sourcesCurrent: { _ in true },
                destinationCurrent: { _ in false }
            )
        )

        let outcome = await PatchGenerationWorkflow.execute(plan, with: executor)

        guard case .notCommitted(let reason) = outcome.state else {
            return XCTFail("Expected non-commit, got \(outcome.state)")
        }
        XCTAssertEqual(reason, .destinationChanged)
    }

    func testAuthorityCheckedBeforeStaleProbes() async throws {
        let plan = try clipboardPlan()
        let executor = PatchGenerationStubExecutor(
            authority: PatchGenerationStubSandboxAuthority(),
            revalidation: .stale
        )

        let outcome = await PatchGenerationWorkflow.execute(plan, with: executor)

        guard case .notCommitted(let reason) = outcome.state else {
            return XCTFail("Expected non-commit, got \(outcome.state)")
        }
        XCTAssertEqual(reason, .securityContractUnavailable)
    }

    func testBoundOverwriteAndAppendPassRevisionBinding() async throws {
        let directory = try makeTemporaryDirectory()
        let parent = try canonicalIdentity(directory, kind: .directory)
        let allowedParent = parent.canonicalURL.path(percentEncoded: false)
        let authority = PatchGenerationStubSandboxAuthority(
            writableParentPaths: [allowedParent]
        )

        for plan in [try overwritePlan(directory: directory), try appendPlan(directory: directory)] {
            let outcome = await PatchGenerationWorkflow.execute(
                plan,
                with: PatchGenerationStubExecutor(authority: authority)
            )
            guard case .notCommitted(let reason) = outcome.state else {
                return XCTFail("Expected non-commit, got \(outcome.state)")
            }
            XCTAssertEqual(reason, .rejected(Self.stubMessage))
        }
    }

    func testReceiptEchoesBoundPlan() async throws {
        let clipboard = try clipboardPlan(direction: .reverse)
        let clipboardReceipt = PatchGenerationStubExecutor().describe(clipboard.mutation)
        XCTAssertEqual(clipboardReceipt.sourceIDs, clipboard.sources.map(\.id))
        XCTAssertEqual(clipboardReceipt.style, .unified)
        XCTAssertEqual(clipboardReceipt.contextLines, 1)
        XCTAssertEqual(clipboardReceipt.direction, .reverse)
        XCTAssertEqual(clipboardReceipt.destination, .clipboard)
        XCTAssertEqual(
            clipboardReceipt.payloadByteCount,
            clipboard.generatedPatch.utf8.count
        )
        XCTAssertEqual(clipboardReceipt.planSHA256, clipboard.mutation.planSHA256)
        XCTAssertEqual(
            clipboardReceipt.executorContract,
            PatchGenerationExecutorContract.required
        )

        let directory = try makeTemporaryDirectory()
        let expectations: [(PatchGenerationPlan, PatchGenerationStubDestinationSummary)] = [
            (try createPlan(directory: directory, destinationLeaf: "create.patch"), .createNew),
            (try overwritePlan(directory: directory), .overwrite),
            (try appendPlan(directory: directory), .append)
        ]
        for (plan, summary) in expectations {
            guard case .file(let destination) = plan.destination else {
                return XCTFail("Expected file destination")
            }
            let receipt = PatchGenerationStubExecutor().describe(plan.mutation)
            XCTAssertEqual(receipt.destination, summary)
            XCTAssertEqual(receipt.payloadByteCount, destination.payload.count)
            XCTAssertEqual(receipt.planSHA256, plan.mutation.planSHA256)
            XCTAssertEqual(
                receipt.executorContract,
                PatchGenerationExecutorContract.required
            )
        }
    }

    func testCancellationIsDefinitiveNonCommit() async throws {
        let plan = try clipboardPlan()
        let task = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return await PatchGenerationWorkflow.execute(
                plan,
                with: PatchGenerationStubExecutor(
                    authority: PatchGenerationStubSandboxAuthority(allowsClipboard: true)
                )
            )
        }

        let outcome = await task.value
        guard case .notCommitted(let reason) = outcome.state else {
            return XCTFail("Expected non-commit, got \(outcome.state)")
        }
        XCTAssertEqual(reason, .cancelled)
    }

    private func clipboardPlan(
        direction: PatchGenerationDirection = .forward
    ) throws -> PatchGenerationPlan {
        let source = PatchGenerationSource(
            id: PatchGenerationSourceID(rawValue: "source"),
            oldSnapshot: PatchGenerationTextSnapshot(
                identity: .document(UUID()),
                revision: 1,
                text: "old\n"
            ),
            newSnapshot: PatchGenerationTextSnapshot(
                identity: .document(UUID()),
                revision: 1,
                text: "new\n"
            ),
            oldPath: "old.txt",
            newPath: "new.txt"
        )
        return try PatchGenerationWorkflow.plan(
            PatchGenerationRequest(
                sources: [source],
                style: .unified,
                contextLines: direction == .reverse ? 1 : 0,
                direction: direction,
                destination: .clipboard(
                    PatchGenerationClipboardDestination(
                        expectedRevision: PatchGenerationClipboardRevision(
                            brokerIdentifier: PatchGenerationClipboardBrokerIdentifier(
                                rawValue: UUID()
                            ),
                            epoch: PatchGenerationClipboardBrokerEpoch(rawValue: UUID()),
                            value: 0
                        )
                    )
                )
            )
        )
    }

    private func createPlan(
        directory: URL,
        destinationLeaf: String
    ) throws -> PatchGenerationPlan {
        let parent = try canonicalIdentity(directory, kind: .directory)
        return try PatchGenerationWorkflow.plan(
            PatchGenerationRequest(
                sources: [
                    PatchGenerationSource(
                        id: PatchGenerationSourceID(rawValue: "source"),
                        oldSnapshot: PatchGenerationTextSnapshot(
                            identity: .document(UUID()),
                            revision: 1,
                            text: "old\n"
                        ),
                        newSnapshot: PatchGenerationTextSnapshot(
                            identity: .document(UUID()),
                            revision: 1,
                            text: "new\n"
                        ),
                        oldPath: "old.txt",
                        newPath: "new.txt"
                    )
                ],
                style: .unified,
                contextLines: 0,
                destination: .file(
                    PatchGenerationFileDestination(
                        url: directory.appending(path: destinationLeaf),
                        disposition: .createNew(parentIdentity: parent)
                    )
                )
            )
        )
    }

    private func overwritePlan(directory: URL) throws -> PatchGenerationPlan {
        let parent = try canonicalIdentity(directory, kind: .directory)
        let url = directory.appending(path: "overwrite.patch")
        let identity = try canonicalIdentity(url, kind: .regularFile)
        return try PatchGenerationWorkflow.plan(
            PatchGenerationRequest(
                sources: [
                    PatchGenerationSource(
                        id: PatchGenerationSourceID(rawValue: "source"),
                        oldSnapshot: PatchGenerationTextSnapshot(
                            identity: .document(UUID()),
                            revision: 1,
                            text: "old\n"
                        ),
                        newSnapshot: PatchGenerationTextSnapshot(
                            identity: .document(UUID()),
                            revision: 1,
                            text: "new\n"
                        ),
                        oldPath: "old.txt",
                        newPath: "new.txt"
                    )
                ],
                style: .unified,
                contextLines: 0,
                destination: .file(
                    PatchGenerationFileDestination(
                        url: url,
                        disposition: .overwrite(
                            expectedParent: parent,
                            expected: PatchGenerationFileRevision(
                                identity: identity,
                                byteCount: 8,
                                linkCount: 1,
                                permissions: 0o644,
                                ownerID: 0,
                                groupID: 0,
                                flags: 0,
                                metadataByteCount: 64,
                                modificationTimeSeconds: 0,
                                modificationTimeNanoseconds: 0,
                                statusChangeTimeSeconds: 0,
                                statusChangeTimeNanoseconds: 0,
                                contentSHA256: [UInt8](repeating: 0, count: 32),
                                metadataSHA256: [UInt8](repeating: 0, count: 32)
                            )
                        )
                    )
                )
            )
        )
    }

    private func appendPlan(directory: URL) throws -> PatchGenerationPlan {
        let parent = try canonicalIdentity(directory, kind: .directory)
        let url = directory.appending(path: "append.patch")
        let existing = Data("existing\n".utf8)
        try existing.write(to: url)
        let identity = try canonicalIdentity(url, kind: .regularFile)
        let revision = PatchGenerationFileRevision(
            identity: identity,
            byteCount: UInt64(existing.count),
            linkCount: 1,
            permissions: 0o644,
            ownerID: 0,
            groupID: 0,
            flags: 0,
            metadataByteCount: 64,
            modificationTimeSeconds: 0,
            modificationTimeNanoseconds: 0,
            statusChangeTimeSeconds: 0,
            statusChangeTimeNanoseconds: 0,
            contentSHA256: Array(SHA256.hash(data: existing)),
            metadataSHA256: [UInt8](repeating: 0, count: 32)
        )
        return try PatchGenerationWorkflow.plan(
            PatchGenerationRequest(
                sources: [
                    PatchGenerationSource(
                        id: PatchGenerationSourceID(rawValue: "source"),
                        oldSnapshot: PatchGenerationTextSnapshot(
                            identity: .document(UUID()),
                            revision: 1,
                            text: "old\n"
                        ),
                        newSnapshot: PatchGenerationTextSnapshot(
                            identity: .document(UUID()),
                            revision: 1,
                            text: "new\n"
                        ),
                        oldPath: "old.txt",
                        newPath: "new.txt"
                    )
                ],
                style: .unified,
                contextLines: 0,
                destination: .file(
                    PatchGenerationFileDestination(
                        url: url,
                        disposition: .append(
                            expectedParent: parent,
                            expected: try PatchGenerationExistingFileSnapshot(
                                revision: revision,
                                data: existing
                            ),
                            lineEnding: .lf
                        )
                    )
                )
            )
        )
    }

    private func canonicalIdentity(
        _ url: URL,
        kind: PatchGenerationCanonicalItemKind
    ) throws -> PatchGenerationCanonicalFileIdentity {
        if kind == .regularFile, !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw posixError() }
        return PatchGenerationCanonicalFileIdentity(
            canonicalURL: URL(
                fileURLWithPath: url.standardizedFileURL.path,
                isDirectory: kind == .directory
            ),
            kind: kind,
            deviceID: UInt64(information.st_dev),
            fileID: UInt64(information.st_ino),
            generation: UInt32(information.st_gen)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PatchExecutorStubTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
