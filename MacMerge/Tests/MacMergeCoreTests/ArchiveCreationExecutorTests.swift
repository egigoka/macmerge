import CryptoKit
import Foundation
import XCTest

@testable import MacMergeCore

final class ArchiveCreationExecutorTests: XCTestCase {
    func testDescribeReceiptEchoesCountsTotalsAndContract() throws {
        let fixture = try planSingleFile(contents: Data("receipt".utf8))
        let supplement = ComparisonArchiveSupplement(
            kind: .report,
            archiveRelativePath: "report.md",
            bytes: Data("supplement".utf8)
        )
        let destination = fileDestination(in: fixture.workspace)
        let request = ComparisonArchiveCreationRequest(
            plan: fixture.plan,
            supplements: [supplement],
            destination: .file(destination)
        )
        let executor = authorizedExecutor(for: destination)

        let receipt = executor.describe(request)

        XCTAssertEqual(receipt.manifestVersion, ComparisonArchivePlan.manifestVersion)
        XCTAssertEqual(receipt.entryCount, fixture.plan.entries.count)
        XCTAssertEqual(receipt.supplementCount, 1)
        XCTAssertEqual(
            receipt.totalSourceByteCount,
            fixture.plan.totalUncompressedByteCount + UInt64(supplement.bytes.count)
        )
        // Describe echoes the plan estimate; supplements are validated, not estimated.
        XCTAssertEqual(receipt.estimatedArchiveByteCount, fixture.plan.estimatedArchiveByteCount)
        XCTAssertEqual(receipt.destination, .file)
        XCTAssertEqual(receipt.executorContract, ComparisonArchiveCreationExecutorContract.required)
    }

    func testExecuteValidRequestIsNonCommitWithoutMutation() async throws {
        let root = try temporaryWorkspace()
        try Data("hello".utf8).write(to: root.appending(path: "a.txt"))
        try FileManager.default.createDirectory(
            at: root.appending(path: "empty", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        let plan = try ComparisonArchivePlanner().plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "a.txt", kind: .regularFile),
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "empty", kind: .directory)
        ])
        let destination = fileDestination(in: root)
        let supplement = ComparisonArchiveSupplement(
            kind: .report,
            archiveRelativePath: "report.md",
            bytes: Data("report".utf8)
        )
        let request = ComparisonArchiveCreationRequest(
            plan: plan,
            supplements: [supplement],
            destination: .file(destination)
        )
        let executor = authorizedExecutor(for: destination)

        let outcome = await executor.execute(request)

        let notExecuted = try XCTUnwrap(notExecuted(outcome))
        XCTAssertEqual(notExecuted.receipt, executor.describe(request))
        guard case .rejected(let message) = notExecuted.reason else {
            return XCTFail("Expected stub rejection, got \(notExecuted.reason)")
        }
        XCTAssertTrue(message.contains("no archive"), "Unexpected message: \(message)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testPlannerCodecSupportIsZipStoreOnly() throws {
        XCTAssertEqual(ComparisonArchivePlanner.supportedFormats, [.zip])
        XCTAssertEqual(ComparisonArchivePlanner.supportedCompressionFormats, [.store])
        let fixture = try planSingleFile()
        XCTAssertEqual(fixture.plan.format, .zip)
        XCTAssertEqual(fixture.plan.compression, .store)
    }

    func testExecutorAcceptsBoundedSHA256DigestAndPortableMetadata() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let contents = Data("digest bounded".utf8)
        try contents.write(to: root.appending(path: "digest.bin"))
        let entry = FolderEntry(
            relativePath: "digest.bin",
            kind: .regularFile,
            size: UInt64(contents.count),
            contentDigest: sha256(contents)
        )
        let plan = try ComparisonArchivePlanner().plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, entry: entry)
        ])
        XCTAssertEqual(plan.entries[0].metadata.unixPermissions, 0o600)
        let destination = fileDestination(in: workspace)
        let request = ComparisonArchiveCreationRequest(plan: plan, destination: .file(destination))

        let outcome = await authorizedExecutor(for: destination).execute(request)

        let notExecuted = try XCTUnwrap(notExecuted(outcome))
        guard case .rejected(let message) = notExecuted.reason else {
            return XCTFail("Expected stub rejection, got \(notExecuted.reason)")
        }
        XCTAssertTrue(message.contains("no archive"), "Unexpected message: \(message)")
    }

    func testExecuteRejectsUnauthorizedFileAndClipboard() async throws {
        let fixture = try planSingleFile()
        let destination = fileDestination(in: fixture.workspace)
        let fileRequest = ComparisonArchiveCreationRequest(plan: fixture.plan, destination: .file(destination))
        let clipboardRequest = ComparisonArchiveCreationRequest(plan: fixture.plan, destination: .clipboard)

        let fileOutcome = await ComparisonArchiveCreationStubExecutor().execute(fileRequest)
        XCTAssertEqual(notExecuted(fileOutcome)?.reason, .securityContractUnavailable)

        let clipboardOutcome = await ComparisonArchiveCreationStubExecutor().execute(clipboardRequest)
        XCTAssertEqual(notExecuted(clipboardOutcome)?.reason, .securityContractUnavailable)
    }

    func testExecuteAllowsAuthorizedClipboard() async throws {
        let fixture = try planSingleFile()
        let request = ComparisonArchiveCreationRequest(plan: fixture.plan, destination: .clipboard)
        let executor = ComparisonArchiveCreationStubExecutor(
            authority: ComparisonArchiveCreationSandboxAuthority(allowsClipboard: true)
        )

        let outcome = await executor.execute(request)

        let notExecuted = try XCTUnwrap(notExecuted(outcome))
        XCTAssertEqual(notExecuted.receipt.destination, .clipboard)
        guard case .rejected = notExecuted.reason else {
            return XCTFail("Expected stub rejection, got \(notExecuted.reason)")
        }
    }

    func testExecuteRejectsLeafBindingViolations() async throws {
        let fixture = try planSingleFile()
        let executor = ComparisonArchiveCreationStubExecutor(
            authority: ComparisonArchiveCreationSandboxAuthority(
                writableParentPaths: [fixture.workspace.path(percentEncoded: false)]
            )
        )
        let directoryURL = fixture.workspace.appending(path: "dir", directoryHint: .isDirectory)
        let remoteURL = try XCTUnwrap(URL(string: "https://example.invalid/out.zip"))

        for destination in [directoryURL, remoteURL] {
            let outcome = await executor.execute(
                ComparisonArchiveCreationRequest(plan: fixture.plan, destination: .file(destination))
            )
            guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
                return XCTFail("Expected binding rejection for \(destination)")
            }
            XCTAssertTrue(
                message.contains("URL") || message.contains("destination"),
                "Unexpected message: \(message)"
            )
        }
    }

    func testExecuteRejectsInvalidSupplementPath() async throws {
        let fixture = try planSingleFile()
        let destination = fileDestination(in: fixture.workspace)
        let executor = authorizedExecutor(for: destination)

        for badPath in ["/absolute.txt", "a\\b.txt"] {
            let request = ComparisonArchiveCreationRequest(
                plan: fixture.plan,
                supplements: [
                    ComparisonArchiveSupplement(kind: .patch, archiveRelativePath: badPath, bytes: Data())
                ],
                destination: .file(destination)
            )
            let outcome = await executor.execute(request)
            guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
                return XCTFail("Expected supplement path rejection for \(badPath)")
            }
            XCTAssertTrue(message.contains("invalid supplement path"), "Unexpected: \(message)")
        }
    }

    func testEntryPlusSupplementCapIncludesSupplements() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("a".utf8).write(to: root.appending(path: "a"))
        let limits = ComparisonArchivePlanLimits(maximumEntryCount: 1)
        let plan = try ComparisonArchivePlanner(limits: limits).plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "a", archiveRelativePath: "a", kind: .regularFile)
        ])
        let destination = fileDestination(in: workspace)
        let request = ComparisonArchiveCreationRequest(
            plan: plan,
            supplements: [
                ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "s.txt", bytes: Data("s".utf8))
            ],
            destination: .file(destination)
        )

        let outcome = await authorizedExecutor(for: destination).execute(request)

        guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
            return XCTFail("Expected entry+supplement cap rejection")
        }
        XCTAssertTrue(message.contains("entries and supplements"), "Unexpected: \(message)")
    }

    func testSupplementCountCapAccepts64AndRejects65() async throws {
        let fixture = try planSingleFile()
        let destination = fileDestination(in: fixture.workspace)
        let executor = authorizedExecutor(for: destination)
        let sixtyFour = (0..<64).map {
            ComparisonArchiveSupplement(
                kind: .report,
                archiveRelativePath: "supplement-\($0).txt",
                bytes: Data("x".utf8)
            )
        }

        let accepted = await executor.execute(
            ComparisonArchiveCreationRequest(
                plan: fixture.plan,
                supplements: sixtyFour,
                destination: .file(destination)
            )
        )
        guard case .rejected(let message)? = notExecuted(accepted)?.reason else {
            return XCTFail("Expected stub rejection for 64 supplements")
        }
        XCTAssertTrue(message.contains("no archive"), "Unexpected: \(message)")

        let rejected = await executor.execute(
            ComparisonArchiveCreationRequest(
                plan: fixture.plan,
                supplements: sixtyFour + [
                    ComparisonArchiveSupplement(
                        kind: .report,
                        archiveRelativePath: "one-more.txt",
                        bytes: Data("x".utf8)
                    )
                ],
                destination: .file(destination)
            )
        )
        guard case .rejected(let overflow)? = notExecuted(rejected)?.reason else {
            return XCTFail("Expected 65-supplement rejection")
        }
        XCTAssertTrue(overflow.contains("64-payload"), "Unexpected: \(overflow)")
    }

    func testCombinedPathTotalsIncludeSupplements() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("a".utf8).write(to: root.appending(path: "a"))
        let byteLimits = ComparisonArchivePlanLimits(maximumTotalPathUTF8Bytes: 3)
        let bytePlan = try ComparisonArchivePlanner(limits: byteLimits).plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "a", archiveRelativePath: "a", kind: .regularFile)
        ])
        let componentLimits = ComparisonArchivePlanLimits(maximumTotalPathComponents: 1)
        let componentPlan = try ComparisonArchivePlanner(limits: componentLimits).plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "a", archiveRelativePath: "a", kind: .regularFile)
        ])
        let destination = fileDestination(in: workspace)

        let byteOutcome = await authorizedExecutor(for: destination).execute(
            ComparisonArchiveCreationRequest(
                plan: bytePlan,
                supplements: [
                    ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "bcd", bytes: Data())
                ],
                destination: .file(destination)
            )
        )
        guard case .rejected(let byteMessage)? = notExecuted(byteOutcome)?.reason else {
            return XCTFail("Expected path size rejection")
        }
        XCTAssertTrue(byteMessage.contains("total path size"), "Unexpected: \(byteMessage)")

        let componentOutcome = await authorizedExecutor(for: destination).execute(
            ComparisonArchiveCreationRequest(
                plan: componentPlan,
                supplements: [
                    ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "b", bytes: Data())
                ],
                destination: .file(destination)
            )
        )
        guard case .rejected(let componentMessage)? = notExecuted(componentOutcome)?.reason else {
            return XCTFail("Expected component rejection")
        }
        XCTAssertTrue(componentMessage.contains("total component"), "Unexpected: \(componentMessage)")
    }

    func testCombinedTotalUncompressedIncludesSupplements() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("a".utf8).write(to: root.appending(path: "a"))
        let limits = ComparisonArchivePlanLimits(maximumTotalUncompressedBytes: 2)
        let plan = try ComparisonArchivePlanner(limits: limits).plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "a", archiveRelativePath: "a", kind: .regularFile)
        ])
        let destination = fileDestination(in: workspace)

        let outcome = await authorizedExecutor(for: destination).execute(
            ComparisonArchiveCreationRequest(
                plan: plan,
                supplements: [
                    ComparisonArchiveSupplement(
                        kind: .report,
                        archiveRelativePath: "s.txt",
                        bytes: Data(repeating: 0, count: 2)
                    )
                ],
                destination: .file(destination)
            )
        )

        guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
            return XCTFail("Expected combined total rejection")
        }
        XCTAssertTrue(message.contains("combined sources"), "Unexpected: \(message)")
    }

    func testEstimateIncludesSupplementsAgainstArchiveLimit() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("a".utf8).write(to: root.appending(path: "a"))
        let input = ComparisonArchiveInput(
            sourceRootURL: root,
            sourceRelativePath: "a",
            archiveRelativePath: "a",
            kind: .regularFile
        )
        let baseline = try ComparisonArchivePlanner().plan(inputs: [input])
        let tight = try ComparisonArchivePlanner(
            limits: ComparisonArchivePlanLimits(maximumArchiveBytes: baseline.estimatedArchiveByteCount)
        ).plan(inputs: [input])
        XCTAssertEqual(tight.estimatedArchiveByteCount, baseline.estimatedArchiveByteCount)
        let destination = fileDestination(in: workspace)

        let outcome = await authorizedExecutor(for: destination).execute(
            ComparisonArchiveCreationRequest(
                plan: tight,
                supplements: [
                    ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "s", bytes: Data("x".utf8))
                ],
                destination: .file(destination)
            )
        )

        guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
            return XCTFail("Expected estimate rejection")
        }
        XCTAssertTrue(message.contains("archive estimate"), "Unexpected: \(message)")
    }

    func testSupplementPerEntrySizeEnforced() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("a".utf8).write(to: root.appending(path: "a"))
        let limits = ComparisonArchivePlanLimits(maximumEntryUncompressedBytes: 1)
        let plan = try ComparisonArchivePlanner(limits: limits).plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "a", archiveRelativePath: "a", kind: .regularFile)
        ])
        let destination = fileDestination(in: workspace)

        let outcome = await authorizedExecutor(for: destination).execute(
            ComparisonArchiveCreationRequest(
                plan: plan,
                supplements: [
                    ComparisonArchiveSupplement(
                        kind: .report,
                        archiveRelativePath: "big.txt",
                        bytes: Data(repeating: 0, count: 2)
                    )
                ],
                destination: .file(destination)
            )
        )

        guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
            return XCTFail("Expected per-entry rejection")
        }
        XCTAssertTrue(message.contains("per-entry limit"), "Unexpected: \(message)")
    }

    func testSupplementShadowingEarlierSupplementRejectedBothDirections() async throws {
        let fixture = try planSingleFile()
        let destination = fileDestination(in: fixture.workspace)
        let executor = authorizedExecutor(for: destination)

        for paths in [["a", "a/b"], ["a/b", "a"]] {
            let request = ComparisonArchiveCreationRequest(
                plan: fixture.plan,
                supplements: paths.map {
                    ComparisonArchiveSupplement(kind: .report, archiveRelativePath: $0, bytes: Data())
                },
                destination: .file(destination)
            )
            let outcome = await executor.execute(request)
            guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
                return XCTFail("Expected shadowing rejection for \(paths)")
            }
            XCTAssertTrue(message.contains("supplement"), "Unexpected: \(message)")
        }
    }

    func testSupplementHierarchyAgainstPlannedFileAndDirectory() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("src".utf8).write(to: root.appending(path: "src.txt"))
        let plan = try ComparisonArchivePlanner().plan(inputs: [
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "src.txt",
                archiveRelativePath: "dir/child.txt",
                kind: .regularFile
            )
        ])
        let destination = fileDestination(in: workspace)
        let executor = authorizedExecutor(for: destination)

        let insideFile = await executor.execute(
            ComparisonArchiveCreationRequest(
                plan: plan,
                supplements: [
                    ComparisonArchiveSupplement(
                        kind: .report,
                        archiveRelativePath: "dir/child.txt/grandchild.txt",
                        bytes: Data()
                    )
                ],
                destination: .file(destination)
            )
        )
        guard case .rejected(let insideMessage)? = notExecuted(insideFile)?.reason else {
            return XCTFail("Expected inside-planned-file rejection")
        }
        XCTAssertTrue(insideMessage.contains("inside a planned file"), "Unexpected: \(insideMessage)")

        let shadowing = await executor.execute(
            ComparisonArchiveCreationRequest(
                plan: plan,
                supplements: [
                    ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "dir", bytes: Data())
                ],
                destination: .file(destination)
            )
        )
        guard case .rejected(let shadowMessage)? = notExecuted(shadowing)?.reason else {
            return XCTFail("Expected shadowing-planned-path rejection")
        }
        XCTAssertTrue(shadowMessage.contains("shadows a planned path"), "Unexpected: \(shadowMessage)")
    }

    func testHFSIgnorableAndCaseCollisionWithPlannedPath() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("body".utf8).write(to: root.appending(path: "body.txt"))
        let plan = try ComparisonArchivePlanner().plan(inputs: [
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "body.txt",
                archiveRelativePath: "file.txt",
                kind: .regularFile
            )
        ])
        let destination = fileDestination(in: workspace)
        let executor = authorizedExecutor(for: destination)

        for colliding in ["FILE.txt", "fi\u{200C}le.txt"] {
            let outcome = await executor.execute(
                ComparisonArchiveCreationRequest(
                    plan: plan,
                    supplements: [
                        ComparisonArchiveSupplement(
                            kind: .report,
                            archiveRelativePath: colliding,
                            bytes: Data()
                        )
                    ],
                    destination: .file(destination)
                )
            )
            guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
                return XCTFail("Expected collision rejection for \(colliding)")
            }
            XCTAssertTrue(message.contains("colliding"), "Unexpected: \(message)")
        }
    }

    func testStaleSourcesAndDestinationsReportChanged() async throws {
        let fixture = try planSingleFile()
        let destination = fileDestination(in: fixture.workspace)
        let staleSources = ComparisonArchiveCreationStubExecutor(
            authority: ComparisonArchiveCreationSandboxAuthority(
                writableParentPaths: [destination.deletingLastPathComponent().path(percentEncoded: false)]
            ),
            revalidation: ComparisonArchiveCreationRevalidation(
                sourcesCurrent: { _ in false },
                destinationCurrent: { _ in true }
            )
        )
        let staleDestination = ComparisonArchiveCreationStubExecutor(
            authority: ComparisonArchiveCreationSandboxAuthority(
                writableParentPaths: [destination.deletingLastPathComponent().path(percentEncoded: false)]
            ),
            revalidation: ComparisonArchiveCreationRevalidation(
                sourcesCurrent: { _ in true },
                destinationCurrent: { _ in false }
            )
        )

        let sourceOutcome = await staleSources.execute(
            ComparisonArchiveCreationRequest(plan: fixture.plan, destination: .file(destination))
        )
        XCTAssertEqual(notExecuted(sourceOutcome)?.reason, .sourceChanged)

        let destinationOutcome = await staleDestination.execute(
            ComparisonArchiveCreationRequest(plan: fixture.plan, destination: .file(destination))
        )
        XCTAssertEqual(notExecuted(destinationOutcome)?.reason, .destinationChanged)
    }

    func testDescriptorSwapStaleDetectedOnlyThroughRevalidation() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appending(path: "payload.txt")
        let original = Data("original".utf8)
        try original.write(to: source)
        let plan = try ComparisonArchivePlanner().plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "payload.txt", kind: .regularFile)
        ])
        let replacement = root.appending(path: "replacement.bin")
        try Data("swapped!".utf8).write(to: replacement)
        try FileManager.default.removeItem(at: source)
        try FileManager.default.moveItem(at: replacement, to: source)
        let destination = fileDestination(in: workspace)
        let authority = ComparisonArchiveCreationSandboxAuthority(
            writableParentPaths: [destination.deletingLastPathComponent().path(percentEncoded: false)]
        )

        // Plan-only executor never re-reads leaf bytes, so the swap alone is not flagged.
        let pinned = await ComparisonArchiveCreationStubExecutor(authority: authority).execute(
            ComparisonArchiveCreationRequest(plan: plan, destination: .file(destination))
        )
        guard case .rejected? = notExecuted(pinned)?.reason else {
            return XCTFail("Expected stub rejection, got \(String(describing: notExecuted(pinned)?.reason))")
        }

        let detecting = ComparisonArchiveCreationStubExecutor(
            authority: authority,
            revalidation: ComparisonArchiveCreationRevalidation(
                sourcesCurrent: { _ in (try? Data(contentsOf: source)) == original },
                destinationCurrent: { _ in true }
            )
        )
        let stale = await detecting.execute(
            ComparisonArchiveCreationRequest(plan: plan, destination: .file(destination))
        )
        XCTAssertEqual(notExecuted(stale)?.reason, .sourceChanged)
    }

    func testCancellationPreemptsExecution() async throws {
        let fixture = try planSingleFile()
        let destination = fileDestination(in: fixture.workspace)
        let executor = authorizedExecutor(for: destination)
        let invalid = ComparisonArchiveCreationRequest(
            plan: fixture.plan,
            supplements: [
                ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "/absolute.txt", bytes: Data())
            ],
            destination: .file(destination)
        )

        for request in [
            ComparisonArchiveCreationRequest(plan: fixture.plan, destination: .file(destination)),
            invalid
        ] {
            let outcome = await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await executor.execute(request)
            }.value
            XCTAssertEqual(notExecuted(outcome)?.reason, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testHierarchyCaseInsensitiveBypassRejected() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("src".utf8).write(to: root.appending(path: "src.txt"))
        let plan = try ComparisonArchivePlanner().plan(inputs: [
            ComparisonArchiveInput(
                sourceRootURL: root,
                sourceRelativePath: "src.txt",
                archiveRelativePath: "dir/child.txt",
                kind: .regularFile
            )
        ])
        let destination = fileDestination(in: workspace)
        let executor = authorizedExecutor(for: destination)

        for supplementPath in ["DIR", "Dir", "dir\u{200C}"] {
            let outcome = await executor.execute(
                ComparisonArchiveCreationRequest(
                    plan: plan,
                    supplements: [
                        ComparisonArchiveSupplement(kind: .report, archiveRelativePath: supplementPath, bytes: Data())
                    ],
                    destination: .file(destination)
                )
            )
            guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
                return XCTFail("Expected shadowing rejection for \(supplementPath)")
            }
            XCTAssertTrue(message.contains("shadows a planned path"), "Unexpected: \(message)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }

        for supplementPath in ["DIR/CHILD.TXT/grandchild.txt", "dir/child.txt\u{200C}/x"] {
            let outcome = await executor.execute(
                ComparisonArchiveCreationRequest(
                    plan: plan,
                    supplements: [
                        ComparisonArchiveSupplement(kind: .report, archiveRelativePath: supplementPath, bytes: Data())
                    ],
                    destination: .file(destination)
                )
            )
            guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
                return XCTFail("Expected inside-file rejection for \(supplementPath)")
            }
            XCTAssertTrue(message.contains("inside a planned file"), "Unexpected: \(message)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }

        for paths in [["a", "A/b"], ["a", "a\u{200C}/b"]] {
            let request = ComparisonArchiveCreationRequest(
                plan: plan,
                supplements: paths.map {
                    ComparisonArchiveSupplement(kind: .report, archiveRelativePath: $0, bytes: Data())
                },
                destination: .file(destination)
            )
            let outcome = await executor.execute(request)
            guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
                return XCTFail("Expected supplement hierarchy rejection for \(paths)")
            }
            XCTAssertTrue(message.contains("supplement"), "Unexpected: \(message)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testSupplementDuplicateCollisionReportsEarlierSupplement() async throws {
        let fixture = try planSingleFile()
        let destination = fileDestination(in: fixture.workspace)
        let executor = authorizedExecutor(for: destination)

        let duplicate = await executor.execute(
            ComparisonArchiveCreationRequest(
                plan: fixture.plan,
                supplements: [
                    ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "dup.txt", bytes: Data()),
                    ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "DUP.txt", bytes: Data())
                ],
                destination: .file(destination)
            )
        )
        guard case .rejected(let duplicateMessage)? = notExecuted(duplicate)?.reason else {
            return XCTFail("Expected duplicate supplement rejection")
        }
        XCTAssertTrue(duplicateMessage.contains("earlier supplement"), "Unexpected: \(duplicateMessage)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let planned = await executor.execute(
            ComparisonArchiveCreationRequest(
                plan: fixture.plan,
                supplements: [
                    ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "A.TXT", bytes: Data())
                ],
                destination: .file(destination)
            )
        )
        guard case .rejected(let plannedMessage)? = notExecuted(planned)?.reason else {
            return XCTFail("Expected planned-path collision rejection")
        }
        XCTAssertTrue(plannedMessage.contains("planned path"), "Unexpected: \(plannedMessage)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testTamperedCodecDigestPermissionsRejected() async throws {
        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("payload".utf8).write(to: root.appending(path: "payload.txt"))
        let input = ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "payload.txt", kind: .regularFile)

        XCTAssertThrowsError(try ComparisonArchivePlanner().plan(inputs: [input], format: .tar)) { error in
            XCTAssertEqual(error as? ComparisonArchivePlanError, .unsupportedContainerFormat(.tar))
        }
        XCTAssertThrowsError(try ComparisonArchivePlanner().plan(inputs: [input], compression: .deflate)) { error in
            XCTAssertEqual(error as? ComparisonArchivePlanError, .unsupportedCompressionFormat(.deflate))
        }

        let unsupportedDigest = FolderContentDigest(
            algorithm: "md5",
            bytes: Data(repeating: 0, count: 32)
        )
        XCTAssertThrowsError(
            try ComparisonArchivePlanner().plan(inputs: [
                ComparisonArchiveInput(
                    sourceRootURL: root,
                    sourceRelativePath: "payload.txt",
                    kind: .regularFile,
                    expectedContentDigest: unsupportedDigest
                )
            ])
        ) { error in
            XCTAssertEqual(
                error as? ComparisonArchivePlanError,
                .unsupportedSourceDigest(path: "payload.txt", algorithm: "md5")
            )
        }

        let badLengthDigest = FolderContentDigest(algorithm: "sha256", bytes: Data(repeating: 0, count: 31))
        XCTAssertThrowsError(
            try ComparisonArchivePlanner().plan(inputs: [
                ComparisonArchiveInput(
                    sourceRootURL: root,
                    sourceRelativePath: "payload.txt",
                    kind: .regularFile,
                    expectedContentDigest: badLengthDigest
                )
            ])
        ) { error in
            XCTAssertEqual(error as? ComparisonArchivePlanError, .invalidInputMetadata(path: "payload.txt"))
        }

        try FileManager.default.createDirectory(
            at: root.appending(path: "empty", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        let plan = try ComparisonArchivePlanner().plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "payload.txt", kind: .regularFile),
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "empty", kind: .directory)
        ])
        let fileEntry = try XCTUnwrap(plan.entries.first(where: { $0.relativePath == "payload.txt" }))
        let dirEntry = try XCTUnwrap(plan.entries.first(where: { $0.relativePath == "empty" }))
        XCTAssertEqual(fileEntry.metadata.unixPermissions, 0o600)
        XCTAssertEqual(dirEntry.metadata.unixPermissions, 0o700)
        let destination = fileDestination(in: workspace)
        let outcome = await authorizedExecutor(for: destination).execute(
            ComparisonArchiveCreationRequest(plan: plan, destination: .file(destination))
        )
        guard case .rejected(let message)? = notExecuted(outcome)?.reason else {
            return XCTFail("Expected stub rejection for valid permissions plan")
        }
        XCTAssertTrue(message.contains("no archive"), "Unexpected: \(message)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRejectionsLeaveNoFile() async throws {
        let fixture = try planSingleFile()
        let cases: [[ComparisonArchiveSupplement]] = [
            [ComparisonArchiveSupplement(kind: .patch, archiveRelativePath: "/absolute.txt", bytes: Data())],
            [ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "a.txt/child.txt", bytes: Data())],
            [ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "dup.txt", bytes: Data()),
             ComparisonArchiveSupplement(kind: .report, archiveRelativePath: "DUP.txt", bytes: Data())]
        ]
        for supplements in cases {
            let workspace = try temporaryWorkspace()
            let destination = fileDestination(in: workspace)
            let scoped = authorizedExecutor(for: destination)
            let outcome = await scoped.execute(
                ComparisonArchiveCreationRequest(
                    plan: fixture.plan,
                    supplements: supplements,
                    destination: .file(destination)
                )
            )
            guard case .rejected = notExecuted(outcome)?.reason else {
                return XCTFail("Expected rejection for \(supplements.map(\.archiveRelativePath))")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testMidLoopAndRevalidationCancellation() async throws {
        let fixture = try planSingleFile()
        let destination = fileDestination(in: fixture.workspace)
        let request = ComparisonArchiveCreationRequest(plan: fixture.plan, destination: .file(destination))

        let cancellingSources = ComparisonArchiveCreationStubExecutor(
            authority: ComparisonArchiveCreationSandboxAuthority(
                writableParentPaths: [destination.deletingLastPathComponent().path(percentEncoded: false)]
            ),
            revalidation: ComparisonArchiveCreationRevalidation(
                sourcesCurrent: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return true
                },
                destinationCurrent: { _ in true }
            )
        )
        let sourceOutcome = await Task { await cancellingSources.execute(request) }.value
        XCTAssertEqual(notExecuted(sourceOutcome)?.reason, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let cancellingDestination = ComparisonArchiveCreationStubExecutor(
            authority: ComparisonArchiveCreationSandboxAuthority(
                writableParentPaths: [destination.deletingLastPathComponent().path(percentEncoded: false)]
            ),
            revalidation: ComparisonArchiveCreationRevalidation(
                sourcesCurrent: { _ in true },
                destinationCurrent: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return true
                }
            )
        )
        let destinationOutcome = await Task { await cancellingDestination.execute(request) }.value
        XCTAssertEqual(notExecuted(destinationOutcome)?.reason, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let workspace = try temporaryWorkspace()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        var manyInputs: [ComparisonArchiveInput] = []
        for index in 0..<200 {
            let name = "file-\(index).txt"
            try Data("x".utf8).write(to: root.appending(path: name))
            manyInputs.append(ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: name, kind: .regularFile))
        }
        let manyPlan = try ComparisonArchivePlanner().plan(inputs: manyInputs)
        let manyDestination = fileDestination(in: workspace)
        let manyExecutor = authorizedExecutor(for: manyDestination)
        let manyRequest = ComparisonArchiveCreationRequest(plan: manyPlan, destination: .file(manyDestination))
        let task = Task { await manyExecutor.execute(manyRequest) }
        task.cancel()
        let manyOutcome = await task.value
        XCTAssertEqual(notExecuted(manyOutcome)?.reason, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manyDestination.path))
    }

    // MARK: - Helpers

    private func planSingleFile(
        contents: Data = Data("x".utf8),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (workspace: URL, plan: ComparisonArchivePlan) {
        let workspace = try temporaryWorkspace(file: file, line: line)
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try contents.write(to: root.appending(path: "a.txt"))
        let plan = try ComparisonArchivePlanner().plan(inputs: [
            ComparisonArchiveInput(sourceRootURL: root, sourceRelativePath: "a.txt", kind: .regularFile)
        ])
        return (workspace, plan)
    }

    private func temporaryWorkspace(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "MacMergeArchiveCreationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fileDestination(in workspace: URL) -> URL {
        workspace.appending(path: "output-\(UUID().uuidString).zip")
    }

    private func authorizedExecutor(
        for destination: URL,
        revalidation: ComparisonArchiveCreationRevalidation = .assumeCurrent
    ) -> ComparisonArchiveCreationStubExecutor {
        ComparisonArchiveCreationStubExecutor(
            authority: ComparisonArchiveCreationSandboxAuthority(
                writableParentPaths: [destination.deletingLastPathComponent().path(percentEncoded: false)]
            ),
            revalidation: revalidation
        )
    }

    private func notExecuted(
        _ outcome: ComparisonArchiveCreationExecutionOutcome
    ) -> ComparisonArchiveCreationNotExecuted? {
        guard case .notExecuted(let notExecuted) = outcome else { return nil }
        return notExecuted
    }

    private func sha256(_ data: Data) -> FolderContentDigest {
        FolderContentDigest(algorithm: "sha256", bytes: Data(SHA256.hash(data: data)))
    }
}
