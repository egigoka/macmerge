import Foundation
import XCTest
import zlib

@testable import MacMergeCore

final class ArchiveSupportTests: XCTestCase {
    func testInventoryAndComparisonUseEntryContents() throws {
        let left = try writeArchive([
            ZIPFixture(path: "same.txt", contents: Data("same".utf8)),
            ZIPFixture(path: "changed.txt", contents: Data("left".utf8)),
            ZIPFixture(path: "removed.txt", contents: Data("removed".utf8))
        ])
        let right = try writeArchive([
            ZIPFixture(path: "same.txt", contents: Data("same".utf8)),
            ZIPFixture(path: "changed.txt", contents: Data("right".utf8)),
            ZIPFixture(path: "added.txt", contents: Data("added".utf8))
        ])

        let comparison = try ArchiveIO.compare(left, right)

        XCTAssertEqual(comparison.left.format, .zip)
        XCTAssertEqual(
            comparison.differences.map(\.path),
            [
                "added.txt", "changed.txt", "removed.txt", "same.txt"
            ])
        XCTAssertEqual(
            comparison.differences.map(\.kind),
            [
                .added, .modified, .removed, .unchanged
            ])
    }

    func testComparisonDoesNotTrustCollidingCRC32() throws {
        let left = try writeArchive([
            ZIPFixture(path: "collision.txt", contents: Data("plumless".utf8))
        ])
        let right = try writeArchive([
            ZIPFixture(path: "collision.txt", contents: Data("buckeroo".utf8))
        ])

        let comparison = try ArchiveIO.compare(left, right)

        XCTAssertEqual(comparison.left.entries[0].crc32, comparison.right.entries[0].crc32)
        XCTAssertEqual(comparison.differences.map(\.kind), [.modified])
    }

    func testComparisonDigestsArchivesSequentiallyWithinConfiguredMemoryBound() throws {
        let payload = Data(repeating: 0x41, count: 4 * 1_024 * 1_024)
        let left = try writeArchive([ZIPFixture(path: "large.bin", contents: payload)])
        let right = try writeArchive([ZIPFixture(path: "large.bin", contents: payload)])
        let limits = ArchiveLimits(maximumArchiveBytes: UInt64(payload.count + 512))

        let comparison = try ArchiveIO.compare(left, right, limits: limits)

        XCTAssertEqual(comparison.differences.map(\.kind), [.unchanged])
    }

    func testEmptyZIPHasEmptyInventory() throws {
        let archive = try writeArchive([])

        let inventory = try ArchiveIO.inventory(of: archive)

        XCTAssertEqual(inventory.entries, [])
        XCTAssertEqual(inventory.totalUncompressedSize, 0)
    }

    func testArchiveHostNameMayContainBackslash() throws {
        let directory = try temporaryDirectory()
        let archive = try writeArchive(
            [ZIPFixture(path: "file.txt", contents: Data("contents".utf8))],
            in: directory,
            name: "fixture\\name.zip"
        )

        let inventory = try ArchiveIO.inventory(of: archive)

        XCTAssertEqual(inventory.entries.map(\.path), ["file.txt"])
    }

    func testPublicOperationsRejectNonLocalRelativeAndNULFileURLs() throws {
        let workspace = try temporaryDirectory()
        let archive = try writeArchive(
            [ZIPFixture(path: "file.txt", contents: Data("contents".utf8))],
            in: workspace
        )
        let source = workspace.appending(path: "source.txt")
        try Data("source".utf8).write(to: source)
        let invalidURLs = try [
            XCTUnwrap(URL(string: "https://example.invalid/archive.zip")),
            XCTUnwrap(URL(string: "file://example.invalid/tmp/archive.zip")),
            XCTUnwrap(URL(string: "file:relative.zip")),
            XCTUnwrap(URL(string: "file:///tmp/archive%00.zip")),
            XCTUnwrap(URL(string: "file:///tmp%00parent/archive.zip"))
        ]

        for invalidURL in invalidURLs {
            assertInvalidFileURL { _ = try ArchiveIO.inventory(of: invalidURL) }
            assertInvalidFileURL { _ = try ArchiveIO.compare(invalidURL, archive) }
            assertInvalidFileURL { _ = try ArchiveIO.compare(archive, invalidURL) }
            assertInvalidFileURL { try ArchiveIO.createZIP(from: invalidURL, at: workspace.appending(path: "new.zip")) }
            assertInvalidFileURL { try ArchiveIO.createZIP(from: source, at: invalidURL) }
            assertInvalidFileURL { try ArchiveIO.extract(invalidURL, to: workspace.appending(path: "new")) }
            assertInvalidFileURL { try ArchiveIO.extract(archive, to: invalidURL) }
        }
    }

    func testFakeEOCDSignatureInCommentDoesNotHideRealDirectory() throws {
        var archive = makeZIP([ZIPFixture(path: "file.txt", contents: Data("contents".utf8))])
        archive[archive.count - 2] = 22
        var fakeEnd = Data()
        fakeEnd.appendLittleEndian(UInt32(0x0605_4B50))
        fakeEnd.append(Data(repeating: 0, count: 18))
        archive.append(fakeEnd)
        let directory = try temporaryDirectory()
        let url = directory.appending(path: "comment.zip")
        try archive.write(to: url)

        let inventory = try ArchiveIO.inventory(of: url)

        XCTAssertEqual(inventory.entries.map(\.path), ["file.txt"])
    }

    func testMalformedSelfConsistentEOCDInCommentDoesNotMakeArchiveAmbiguous() throws {
        var archive = makeZIP([ZIPFixture(path: "file.txt", contents: Data("contents".utf8))])
        archive[archive.count - 2] = 22
        var fakeEnd = Data()
        fakeEnd.appendLittleEndian(UInt32(0x0605_4B50))
        fakeEnd.appendLittleEndian(UInt16(0))
        fakeEnd.appendLittleEndian(UInt16(0))
        fakeEnd.appendLittleEndian(UInt16(1))
        fakeEnd.appendLittleEndian(UInt16(1))
        fakeEnd.appendLittleEndian(UInt32(archive.count))
        fakeEnd.appendLittleEndian(UInt32(0))
        fakeEnd.appendLittleEndian(UInt16(0))
        archive.append(fakeEnd)
        let directory = try temporaryDirectory()
        let url = directory.appending(path: "malformed-comment.zip")
        try archive.write(to: url)

        let inventory = try ArchiveIO.inventory(of: url)

        XCTAssertEqual(inventory.entries.map(\.path), ["file.txt"])
    }

    func testSelfConsistentEOCDInCommentIsRejectedAsAmbiguous() throws {
        var archive = makeZIP([ZIPFixture(path: "file.txt", contents: Data("contents".utf8))])
        archive[archive.count - 2] = 22
        var spoofedEnd = Data()
        spoofedEnd.appendLittleEndian(UInt32(0x0605_4B50))
        spoofedEnd.appendLittleEndian(UInt16(0))
        spoofedEnd.appendLittleEndian(UInt16(0))
        spoofedEnd.appendLittleEndian(UInt16(0))
        spoofedEnd.appendLittleEndian(UInt16(0))
        spoofedEnd.appendLittleEndian(UInt32(0))
        spoofedEnd.appendLittleEndian(UInt32(archive.count))
        spoofedEnd.appendLittleEndian(UInt16(0))
        archive.append(spoofedEnd)
        let directory = try temporaryDirectory()
        let url = directory.appending(path: "ambiguous.zip")
        try archive.write(to: url)

        XCTAssertThrowsError(try ArchiveIO.inventory(of: url)) { error in
            XCTAssertEqual(error as? ArchiveError, .invalidArchive)
        }
    }

    func testCreateAndExtractZIPWithoutShellInterpretation() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "payload; touch PWNED", directoryHint: .isDirectory)
        let nested = source.appending(path: "nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: nested.appending(path: "hello.txt"))
        let archive = workspace.appending(path: "created.zip")
        let destination = workspace.appending(path: "extracted", directoryHint: .isDirectory)

        let inventory = try ArchiveIO.createZIP(from: source, at: archive)
        let extractedInventory = try ArchiveIO.extract(archive, to: destination)

        XCTAssertEqual(inventory.entries, extractedInventory.entries)
        XCTAssertEqual(
            try String(
                contentsOf:
                    destination
                    .appending(path: source.lastPathComponent)
                    .appending(path: "nested/hello.txt"),
                encoding: .utf8
            ),
            "hello"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appending(path: "PWNED").path))
    }

    func testCreationRejectsSymbolicLinksAndLeavesNoArchive() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let target = workspace.appending(path: "target.txt")
        try Data("target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: source.appending(path: "link"),
            withDestinationURL: target
        )
        let archive = workspace.appending(path: "unsafe.zip")

        XCTAssertThrowsError(try ArchiveIO.createZIP(from: source, at: archive)) { error in
            XCTAssertEqual(error as? ArchiveError, .sourceContainsUnsupportedItem("link"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    func testCreationRejectsSymbolicLinkSource() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let link = workspace.appending(path: "source-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let archive = workspace.appending(path: "unsafe.zip")

        XCTAssertThrowsError(try ArchiveIO.createZIP(from: link, at: archive)) { error in
            XCTAssertEqual(error as? ArchiveError, .sourceContainsUnsupportedItem("source-link"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    func testExtractionRejectsParentTraversalBeforeWriting() throws {
        let workspace = try temporaryDirectory()
        let archive = try writeArchive(
            [ZIPFixture(path: "../escape.txt", contents: Data("escaped".utf8))],
            in: workspace
        )
        let destination = workspace.appending(path: "destination", directoryHint: .isDirectory)

        XCTAssertThrowsError(try ArchiveIO.extract(archive, to: destination)) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("../escape.txt"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appending(path: "escape.txt").path))
    }

    func testInventoryRejectsAbsoluteAndBackslashPaths() throws {
        for path in ["/absolute.txt", "..\\escape.txt", "folder//file.txt", "folder/./file.txt"] {
            let archive = try writeArchive([ZIPFixture(path: path, contents: Data())])
            XCTAssertThrowsError(try ArchiveIO.inventory(of: archive), path) { error in
                XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath(path))
            }
        }
    }

    func testInventoryRejectsSymlinkEntry() throws {
        let archive = try writeArchive([
            ZIPFixture(
                path: "link",
                contents: Data("../outside".utf8),
                externalAttributes: UInt32(0o120777) << 16
            )
        ])

        XCTAssertThrowsError(try ArchiveIO.inventory(of: archive)) { error in
            XCTAssertEqual(error as? ArchiveError, .unsupportedEntry("link"))
        }
    }

    func testInventoryRejectsConflictingTypeAttributesNamesAndPayloads() throws {
        let fixtures = [
            ZIPFixture(
                path: "dos-directory",
                contents: Data(),
                externalAttributes: UInt32(0o100644) << 16 | 0x10
            ),
            ZIPFixture(
                path: "unix-regular/",
                contents: Data(),
                externalAttributes: UInt32(0o100644) << 16
            ),
            ZIPFixture(
                path: "nonempty-directory",
                contents: Data("payload".utf8),
                externalAttributes: UInt32(0o040700) << 16
            )
        ]

        for fixture in fixtures {
            let archive = try writeArchive([fixture])
            XCTAssertThrowsError(try ArchiveIO.inventory(of: archive), fixture.path) { error in
                XCTAssertEqual(error as? ArchiveError, .invalidArchive)
            }
        }
    }

    func testInventoryRejectsCaseAndUnicodeNormalizationCollisions() throws {
        for paths in [
            ["Folder/File.txt", "folder/file.txt"],
            ["Folder/a.txt", "folder/b.txt"],
            ["café.txt", "cafe\u{301}.txt"]
        ] {
            let archive = try writeArchive(paths.map { ZIPFixture(path: $0, contents: Data()) })
            XCTAssertThrowsError(try ArchiveIO.inventory(of: archive)) { error in
                guard case .duplicateEntryPath = error as? ArchiveError else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testInventoryRejectsFullCaseFoldingCollisions() throws {
        for (first, second) in [
            ("Σ", "σ"),
            ("Σ", "ς"),
            ("σ", "ς"),
            ("ẞ", "ss"),
            ("ẞ", "ß"),
            ("straße", "STRASSE")
        ] {
            for paths in [
                ["\(first).txt", "\(second).txt"],
                ["\(first)/first.txt", "\(second)/second.txt"]
            ] {
                let archive = try writeArchive(paths.map { ZIPFixture(path: $0, contents: Data()) })
                XCTAssertThrowsError(try ArchiveIO.inventory(of: archive), paths.joined(separator: ", ")) { error in
                    XCTAssertEqual(error as? ArchiveError, .duplicateEntryPath(paths[1]))
                }
            }
        }
    }

    func testInventoryRejectsHFSPlusIgnoredScalarAliases() throws {
        let ignoredScalarValues =
            Array(UInt32(0x200C)...UInt32(0x200F))
            + Array(UInt32(0x202A)...UInt32(0x202E))
            + Array(UInt32(0x206A)...UInt32(0x206F))
            + [UInt32(0xFEFF)]

        for scalarValue in ignoredScalarValues {
            let ignoredScalar = String(try XCTUnwrap(Unicode.Scalar(scalarValue)))
            for paths in [
                ["file.txt", "fi\(ignoredScalar)le.txt"],
                ["folder/first.txt", "fol\(ignoredScalar)der/second.txt"]
            ] {
                let archive = try writeArchive(paths.map { ZIPFixture(path: $0, contents: Data()) })
                XCTAssertThrowsError(try ArchiveIO.inventory(of: archive), "U+\(String(scalarValue, radix: 16))") { error in
                    XCTAssertEqual(error as? ArchiveError, .duplicateEntryPath(paths[1]))
                }
            }
        }
    }

    func testInventoryAcceptsDottedIAsDistinctFromPlainI() throws {
        let paths = ["İ.txt", "i.txt", "İ/first.txt", "i/second.txt"]
        let archive = try writeArchive(paths.map { ZIPFixture(path: $0, contents: Data()) })

        let inventory = try ArchiveIO.inventory(of: archive)

        XCTAssertEqual(inventory.entries.map(\.path), paths.sorted())
    }

    func testInventoryRejectsFileDirectoryHierarchyCollision() throws {
        for fixtures in [
            [
                ZIPFixture(path: "parent", contents: Data()),
                ZIPFixture(path: "parent/child.txt", contents: Data())
            ],
            [
                ZIPFixture(path: "parent/child.txt", contents: Data()),
                ZIPFixture(path: "parent", contents: Data())
            ],
            [
                ZIPFixture(path: "a", contents: Data()),
                ZIPFixture(path: "a-", contents: Data()),
                ZIPFixture(path: "a/child.txt", contents: Data())
            ]
        ] {
            let archive = try writeArchive(fixtures)
            XCTAssertThrowsError(try ArchiveIO.inventory(of: archive)) { error in
                guard case .duplicateEntryPath = error as? ArchiveError else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testInventoryRejectsCentralAndLocalNameMismatch() throws {
        let archive = try writeArchive([
            ZIPFixture(path: "central.txt", localPath: "local__.txt", contents: Data())
        ])

        XCTAssertThrowsError(try ArchiveIO.inventory(of: archive)) { error in
            XCTAssertEqual(error as? ArchiveError, .invalidArchive)
        }
    }

    func testInventoryRejectsExtraFields() throws {
        let url = try writeArchive([
            ZIPFixture(path: "file.txt", contents: Data(), extraField: Data([0x75, 0x70, 0, 0]))
        ])

        XCTAssertThrowsError(try ArchiveIO.inventory(of: url)) { error in
            XCTAssertEqual(error as? ArchiveError, .invalidArchive)
        }
    }

    func testInventoryEnforcesExpandedSizeAndRatioLimits() throws {
        let archive = try writeArchive([
            ZIPFixture(path: "large.txt", contents: Data(repeating: 0, count: 16))
        ])
        let entryLimit = ArchiveLimits(
            maximumEntryUncompressedBytes: 8,
            maximumTotalUncompressedBytes: 32
        )

        XCTAssertThrowsError(try ArchiveIO.inventory(of: archive, limits: entryLimit)) { error in
            XCTAssertEqual(error as? ArchiveError, .entryTooLarge(path: "large.txt", maximumBytes: 8))
        }

        let ratioArchive = try writeArchive([
            ZIPFixture(
                path: "bomb.txt",
                contents: Data([0]),
                method: 8,
                declaredCompressedSize: 1,
                declaredUncompressedSize: 101
            )
        ])
        let ratioLimit = ArchiveLimits(
            maximumEntryUncompressedBytes: 1_000,
            maximumTotalUncompressedBytes: 1_000,
            maximumCompressionRatio: 100
        )
        XCTAssertThrowsError(try ArchiveIO.inventory(of: ratioArchive, limits: ratioLimit)) { error in
            XCTAssertEqual(
                error as? ArchiveError,
                .suspiciousCompressionRatio(path: "bomb.txt", maximumRatio: 100)
            )
        }
    }

    func testInventoryEnforcesDepthAndCumulativeComponentLimits() throws {
        let deepPath = "one/two/three.txt"
        let deepArchive = try writeArchive([ZIPFixture(path: deepPath, contents: Data())])
        let depthLimits = ArchiveLimits(maximumPathDepth: 2)

        XCTAssertThrowsError(try ArchiveIO.inventory(of: deepArchive, limits: depthLimits)) { error in
            XCTAssertEqual(error as? ArchiveError, .entryPathTooDeep(path: deepPath, maximumDepth: 2))
        }

        let componentArchive = try writeArchive([
            ZIPFixture(path: "one/file.txt", contents: Data()),
            ZIPFixture(path: "two/file.txt", contents: Data())
        ])
        let componentLimits = ArchiveLimits(maximumPathDepth: 4, maximumTotalPathComponents: 3)
        XCTAssertThrowsError(try ArchiveIO.inventory(of: componentArchive, limits: componentLimits)) { error in
            XCTAssertEqual(error as? ArchiveError, .tooManyPathComponents(maximum: 3))
        }
    }

    func testInventoryAcceptsExactDepthAndCumulativeComponentLimits() throws {
        let archive = try writeArchive([
            ZIPFixture(path: "one/two/file.txt", contents: Data()),
            ZIPFixture(path: "three/four.txt", contents: Data())
        ])

        let inventory = try ArchiveIO.inventory(
            of: archive,
            limits: ArchiveLimits(maximumPathDepth: 3, maximumTotalPathComponents: 5)
        )

        XCTAssertEqual(inventory.entries.map(\.path), ["one/two/file.txt", "three/four.txt"])
    }

    func testPathComponentCapPrecedesDirectorySpellingBookkeeping() throws {
        let path = "one/two/three/four/five.txt"
        let archive = try writeArchive([ZIPFixture(path: path, contents: Data())])
        let limits = ArchiveLimits(maximumPathDepth: 8, maximumTotalPathComponents: 4)

        XCTAssertThrowsError(try ArchiveIO.inventory(of: archive, limits: limits)) { error in
            XCTAssertEqual(error as? ArchiveError, .tooManyPathComponents(maximum: 4))
        }
    }

    func testCreationEnforcesEntryDepthAndComponentCapsDuringEnumeration() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data().write(to: source.appending(path: "a.txt"))
        try Data().write(to: source.appending(path: "b.txt"))

        let entryDestination = workspace.appending(path: "entry-limit.zip")
        XCTAssertThrowsError(
            try ArchiveIO.createZIP(
                from: source,
                at: entryDestination,
                includeParent: false,
                limits: ArchiveLimits(maximumEntryCount: 1)
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveError, .tooManyEntries(maximum: 1))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: entryDestination.path))

        let componentDestination = workspace.appending(path: "component-limit.zip")
        XCTAssertThrowsError(
            try ArchiveIO.createZIP(
                from: source,
                at: componentDestination,
                includeParent: false,
                limits: ArchiveLimits(maximumTotalPathComponents: 1)
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveError, .tooManyPathComponents(maximum: 1))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: componentDestination.path))

        let nested = source.appending(path: "nested/again", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appending(path: "deep.txt"))
        let depthDestination = workspace.appending(path: "depth-limit.zip")
        XCTAssertThrowsError(
            try ArchiveIO.createZIP(
                from: source,
                at: depthDestination,
                includeParent: false,
                limits: ArchiveLimits(maximumPathDepth: 2)
            )
        ) { error in
            guard case .entryPathTooDeep(_, 2) = error as? ArchiveError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: depthDestination.path))
    }

    func testCancelledPublicOperationsStopBeforeFilesystemWork() async throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "source.txt")
        try Data("source".utf8).write(to: source)
        let archive = try writeArchive(
            [ZIPFixture(path: "file.txt", contents: Data("contents".utf8))],
            in: workspace
        )
        let operations: [@Sendable () throws -> Void] = [
            { _ = try ArchiveIO.inventory(of: archive) },
            { _ = try ArchiveIO.compare(archive, archive) },
            { _ = try ArchiveIO.createZIP(from: source, at: workspace.appending(path: "cancelled.zip")) },
            { _ = try ArchiveIO.extract(archive, to: workspace.appending(path: "cancelled")) }
        ]

        for operation in operations {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try operation()
            }
            do {
                try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {
            } catch {
                XCTFail("Expected CancellationError, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appending(path: "cancelled.zip").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appending(path: "cancelled").path))
    }

    func testCancellationAtPublicationCheckpointLeavesNoDestinationOrStagedItem() async throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "source.txt")
        try Data("source".utf8).write(to: source)
        let inputArchive = try writeArchive(
            [ZIPFixture(path: "file.txt", contents: Data("contents".utf8))],
            in: workspace
        )
        let createdArchive = workspace.appending(path: "cancelled.zip")
        let extractedDirectory = workspace.appending(path: "cancelled", directoryHint: .isDirectory)
        let operations: [(ArchiveIO.PublicationCheckpoint, URL, @Sendable () throws -> Void)] = [
            (.creation, createdArchive, { try ArchiveIO.createZIP(from: source, at: createdArchive) }),
            (.extraction, extractedDirectory, { try ArchiveIO.extract(inputArchive, to: extractedDirectory) })
        ]

        for (expectedCheckpoint, destination, operation) in operations {
            let observations = PublicationObservationRecorder(destination: destination)
            let task = Task {
                try ArchiveIO.$publicationObserver.withValue({ checkpoint in
                    observations.record(checkpoint)
                    guard checkpoint == expectedCheckpoint else { return }
                    withUnsafeCurrentTask { $0?.cancel() }
                }) {
                    try operation()
                }
            }

            do {
                try await task.value
                XCTFail("Expected cancellation at \(expectedCheckpoint)")
            } catch is CancellationError {
            } catch {
                XCTFail("Expected CancellationError, got \(error)")
            }
            XCTAssertEqual(observations.snapshot().map(\.checkpoint), [expectedCheckpoint])
            XCTAssertEqual(observations.snapshot().map(\.destinationExisted), [false])
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(try stagedNames(in: workspace).isEmpty)
        }
    }

    func testExtractsDeflatedZIP() throws {
        let contents = Data(repeating: 0x41, count: 1_024)
        let archive = try writeArchive([
            ZIPFixture(
                path: "file.txt",
                contents: contents,
                method: 8,
                compressedContents: try rawDeflate(contents)
            )
        ])
        let destination = archive.deletingLastPathComponent()
            .appending(path: "destination", directoryHint: .isDirectory)

        let inventory = try ArchiveIO.extract(archive, to: destination)

        XCTAssertTrue(inventory.entries.contains(where: { $0.compressedSize < $0.uncompressedSize }))
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "file.txt")), contents)
    }

    func testCreateAndExtractRefuseExistingDestinations() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "source.txt")
        try Data("source".utf8).write(to: source)
        let archive = workspace.appending(path: "existing.zip")
        try Data("existing".utf8).write(to: archive)

        XCTAssertThrowsError(try ArchiveIO.createZIP(from: source, at: archive)) { error in
            guard case .destinationExists(let path) = error as? ArchiveError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(URL(fileURLWithPath: path).lastPathComponent, archive.lastPathComponent)
        }
        XCTAssertEqual(try Data(contentsOf: archive), Data("existing".utf8))

        let validArchive = try writeArchive(
            [ZIPFixture(path: "file.txt", contents: Data())],
            in: workspace,
            name: "valid.zip"
        )
        let destination = workspace.appending(path: "existing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ArchiveIO.extract(validArchive, to: destination)) { error in
            guard case .destinationExists(let path) = error as? ArchiveError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(URL(fileURLWithPath: path).lastPathComponent, destination.lastPathComponent)
        }
    }

    func testCreationEnforcesArchiveByteLimitBeforePublishing() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "source.txt")
        try Data(repeating: 0x41, count: 128).write(to: source)
        let archive = workspace.appending(path: "limited.zip")
        let limits = ArchiveLimits(
            maximumArchiveBytes: 64,
            maximumEntryUncompressedBytes: 1_024,
            maximumTotalUncompressedBytes: 1_024
        )

        XCTAssertThrowsError(try ArchiveIO.createZIP(from: source, at: archive, limits: limits)) { error in
            XCTAssertEqual(error as? ArchiveError, .archiveTooLarge(maximumBytes: 64))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    func testCreationPreflightsExactStoredZIPSize() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "source.txt")
        let contents = Data("abc".utf8)
        try contents.write(to: source)
        let exactSize = UInt64(22 + 76 + source.lastPathComponent.utf8.count * 2 + contents.count)
        let rejected = workspace.appending(path: "too-small.zip")

        XCTAssertThrowsError(
            try ArchiveIO.createZIP(
                from: source,
                at: rejected,
                limits: ArchiveLimits(maximumArchiveBytes: exactSize - 1)
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveError, .archiveTooLarge(maximumBytes: exactSize - 1))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejected.path))
        XCTAssertFalse(try directoryNames(at: workspace).contains(where: { $0.hasPrefix(".macmerge-") }))

        let accepted = workspace.appending(path: "exact.zip")
        _ = try ArchiveIO.createZIP(
            from: source,
            at: accepted,
            limits: ArchiveLimits(maximumArchiveBytes: exactSize)
        )
        XCTAssertEqual(try Data(contentsOf: accepted).count, Int(exactSize))
    }

    func testCreationAndExtractionSynchronizeStagedItemBeforePublicationAndParentAfterPublication() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let inputArchive = try writeArchive([], in: workspace)
        let operations: [(URL, @Sendable () throws -> Void)] = [
            (
                workspace.appending(path: "created.zip"),
                {
                    try ArchiveIO.createZIP(from: source, at: workspace.appending(path: "created.zip"), includeParent: false)
                }
            ),
            (
                workspace.appending(path: "extracted", directoryHint: .isDirectory),
                {
                    try ArchiveIO.extract(inputArchive, to: workspace.appending(path: "extracted"))
                }
            )
        ]

        for (destination, operation) in operations {
            let observations = SynchronizationObservationRecorder(destination: destination)
            try ArchiveIO.$synchronizeOperation.withValue(
                { descriptor in
                    try observations.synchronize(descriptor)
                },
                operation: operation
            )

            XCTAssertEqual(observations.destinationExistence(), [false, true])
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testCreationAndExtractionSynchronizationFailureBeforePublicationCleansStagedItem() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let inputArchive = try writeArchive([], in: workspace)
        let operations: [(URL, @Sendable () throws -> Void)] = [
            (
                workspace.appending(path: "created.zip"),
                {
                    try ArchiveIO.createZIP(from: source, at: workspace.appending(path: "created.zip"), includeParent: false)
                }
            ),
            (
                workspace.appending(path: "extracted", directoryHint: .isDirectory),
                {
                    try ArchiveIO.extract(inputArchive, to: workspace.appending(path: "extracted"))
                }
            )
        ]

        for (destination, operation) in operations {
            let observations = SynchronizationObservationRecorder(destination: destination, failingCall: 1)
            XCTAssertThrowsError(
                try ArchiveIO.$synchronizeOperation.withValue({ descriptor in
                    try observations.synchronize(descriptor)
                }) {
                    try operation()
                }
            ) { error in
                XCTAssertEqual(error as? ArchiveTestError, .injectedSynchronizationFailure)
            }
            XCTAssertEqual(observations.destinationExistence(), [false, false])
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(try stagedNames(in: workspace).isEmpty)
        }
    }

    func testEmptyZIPPreflightRequiresEOCDBytes() throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let rejected = workspace.appending(path: "empty-21.zip")

        XCTAssertThrowsError(
            try ArchiveIO.createZIP(
                from: source,
                at: rejected,
                includeParent: false,
                limits: ArchiveLimits(maximumArchiveBytes: 21)
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveError, .archiveTooLarge(maximumBytes: 21))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejected.path))

        let accepted = workspace.appending(path: "empty-22.zip")
        _ = try ArchiveIO.createZIP(
            from: source,
            at: accepted,
            includeParent: false,
            limits: ArchiveLimits(maximumArchiveBytes: 22)
        )
        XCTAssertEqual(try Data(contentsOf: accepted).count, 22)
    }

    func testExtractionFailureRemovesStagedTree() throws {
        let workspace = try temporaryDirectory()
        let archive = try writeArchive(
            [ZIPFixture(path: "file.txt", contents: Data("corrupt".utf8), crc32: 0)],
            in: workspace
        )
        let destination = workspace.appending(path: "destination", directoryHint: .isDirectory)

        XCTAssertThrowsError(try ArchiveIO.extract(archive, to: destination)) { error in
            XCTAssertEqual(error as? ArchiveError, .invalidArchive)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(try directoryNames(at: workspace).contains(where: { $0.hasSuffix(".extract") }))
    }

    func testCreationAndExtractionCleanupDoNotDeleteReplacementWithDifferentIdentity() async throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "source.txt")
        try Data("source".utf8).write(to: source)
        let inputArchive = try writeArchive([], in: workspace)
        let workspacePath = workspace.path
        let operations: [(ArchiveIO.PublicationCheckpoint, URL, @Sendable () throws -> Void)] = [
            (
                .creation, workspace.appending(path: "cancelled.zip"),
                {
                    try ArchiveIO.createZIP(from: source, at: workspace.appending(path: "cancelled.zip"))
                }
            ),
            (
                .extraction, workspace.appending(path: "cancelled", directoryHint: .isDirectory),
                {
                    try ArchiveIO.extract(inputArchive, to: workspace.appending(path: "cancelled"))
                }
            )
        ]

        for (expectedCheckpoint, destination, operation) in operations {
            let replacementContents = Data("replacement-\(expectedCheckpoint)".utf8)
            let task = Task {
                try ArchiveIO.$publicationObserver.withValue({ checkpoint in
                    guard checkpoint == expectedCheckpoint else { return }
                    let stagedName = try XCTUnwrap(
                        try FileManager.default.contentsOfDirectory(atPath: workspacePath)
                            .filter { $0.hasPrefix(".macmerge-") }
                            .only
                    )
                    let stagedURL = workspace.appending(path: stagedName)
                    try FileManager.default.removeItem(at: stagedURL)
                    try replacementContents.write(to: stagedURL)
                    withUnsafeCurrentTask { $0?.cancel() }
                }) {
                    try operation()
                }
            }

            do {
                try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {
            } catch {
                XCTFail("Expected CancellationError, got \(error)")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            let replacementName = try XCTUnwrap(try stagedNames(in: workspace).only)
            let replacementURL = workspace.appending(path: replacementName)
            XCTAssertEqual(try Data(contentsOf: replacementURL), replacementContents)
            try FileManager.default.removeItem(at: replacementURL)
        }
    }

    func testCleanupSynchronizationFailureIsReportedFromCreationAndExtraction() async throws {
        let workspace = try temporaryDirectory()
        let source = workspace.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let inputArchive = try writeArchive([], in: workspace)
        let operations: [(ArchiveIO.PublicationCheckpoint, URL, @Sendable () throws -> Void)] = [
            (
                .creation, workspace.appending(path: "cancelled.zip"),
                {
                    try ArchiveIO.createZIP(from: source, at: workspace.appending(path: "cancelled.zip"), includeParent: false)
                }
            ),
            (
                .extraction, workspace.appending(path: "cancelled", directoryHint: .isDirectory),
                {
                    try ArchiveIO.extract(inputArchive, to: workspace.appending(path: "cancelled"))
                }
            )
        ]

        for (expectedCheckpoint, destination, operation) in operations {
            let observations = SynchronizationObservationRecorder(destination: destination, failingCall: 2)
            let task = Task {
                try ArchiveIO.$synchronizeOperation.withValue({ descriptor in
                    try observations.synchronize(descriptor)
                }) {
                    try ArchiveIO.$publicationObserver.withValue({ checkpoint in
                        guard checkpoint == expectedCheckpoint else { return }
                        withUnsafeCurrentTask { $0?.cancel() }
                    }) {
                        try operation()
                    }
                }
            }

            do {
                try await task.value
                XCTFail("Expected cleanup failure")
            } catch {
                XCTAssertEqual(error as? ArchiveError, .cleanupFailed(destination.path))
            }
            XCTAssertEqual(observations.destinationExistence(), [false, false])
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(try stagedNames(in: workspace).isEmpty)
        }
    }

    func testCleanupFailureIsReported() {
        struct CleanupFailure: Error {}

        XCTAssertThrowsError(try ArchiveIO.performCleanup(at: "/tmp/staged") { throw CleanupFailure() }) { error in
            XCTAssertEqual(error as? ArchiveError, .cleanupFailed("/tmp/staged"))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MacMergeArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func assertInvalidFileURL(_ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation()) { error in
            guard case .invalidFileURL = error as? ArchiveError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func directoryNames(at url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path)
    }

    private func stagedNames(in url: URL) throws -> [String] {
        try directoryNames(at: url).filter { $0.hasPrefix(".macmerge-") }
    }

    private func writeArchive(
        _ fixtures: [ZIPFixture],
        in directory: URL? = nil,
        name: String = "fixture-\(UUID().uuidString).zip"
    ) throws -> URL {
        let root = try directory ?? temporaryDirectory()
        let url = root.appending(path: name)
        try makeZIP(fixtures).write(to: url)
        return url
    }

    private func makeZIP(_ fixtures: [ZIPFixture]) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var localOffsets: [UInt32] = []

        for fixture in fixtures {
            localOffsets.append(UInt32(archive.count))
            let localName = Data((fixture.localPath ?? fixture.path).utf8)
            let crc = fixture.crc32 ?? testCRC32(fixture.contents)
            let payload = fixture.compressedContents ?? fixture.contents
            let compressedSize = fixture.declaredCompressedSize ?? UInt32(payload.count)
            let uncompressedSize = fixture.declaredUncompressedSize ?? UInt32(fixture.contents.count)
            archive.appendLittleEndian(UInt32(0x0403_4B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(fixture.flags)
            archive.appendLittleEndian(fixture.method)
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(compressedSize)
            archive.appendLittleEndian(uncompressedSize)
            archive.appendLittleEndian(UInt16(localName.count))
            archive.appendLittleEndian(UInt16(fixture.extraField.count))
            archive.append(localName)
            archive.append(fixture.extraField)
            archive.append(payload)
        }

        for (fixture, localOffset) in zip(fixtures, localOffsets) {
            let name = Data(fixture.path.utf8)
            let crc = fixture.crc32 ?? testCRC32(fixture.contents)
            let payload = fixture.compressedContents ?? fixture.contents
            let compressedSize = fixture.declaredCompressedSize ?? UInt32(payload.count)
            let uncompressedSize = fixture.declaredUncompressedSize ?? UInt32(fixture.contents.count)
            centralDirectory.appendLittleEndian(UInt32(0x0201_4B50))
            centralDirectory.appendLittleEndian(UInt16(3 << 8 | 20))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(fixture.flags)
            centralDirectory.appendLittleEndian(fixture.method)
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(crc)
            centralDirectory.appendLittleEndian(compressedSize)
            centralDirectory.appendLittleEndian(uncompressedSize)
            centralDirectory.appendLittleEndian(UInt16(name.count))
            centralDirectory.appendLittleEndian(UInt16(fixture.extraField.count))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(fixture.externalAttributes)
            centralDirectory.appendLittleEndian(localOffset)
            centralDirectory.append(name)
            centralDirectory.append(fixture.extraField)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(fixtures.count))
        archive.appendLittleEndian(UInt16(fixtures.count))
        archive.appendLittleEndian(UInt32(centralDirectory.count))
        archive.appendLittleEndian(centralOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }
}

private enum ArchiveTestError: Error, Equatable {
    case injectedSynchronizationFailure
}

private struct PublicationObservation {
    let checkpoint: ArchiveIO.PublicationCheckpoint
    let destinationExisted: Bool
}

private final class PublicationObservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private var observations: [PublicationObservation] = []

    init(destination: URL) {
        self.destination = destination
    }

    func record(_ checkpoint: ArchiveIO.PublicationCheckpoint) {
        lock.withLock {
            observations.append(
                PublicationObservation(
                    checkpoint: checkpoint,
                    destinationExisted: FileManager.default.fileExists(atPath: destination.path)
                ))
        }
    }

    func snapshot() -> [PublicationObservation] {
        lock.withLock { observations }
    }
}

private final class SynchronizationObservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let failingCall: Int?
    private var destinationExisted: [Bool] = []

    init(destination: URL, failingCall: Int? = nil) {
        self.destination = destination
        self.failingCall = failingCall
    }

    func synchronize(_: Int32) throws {
        let shouldFail = lock.withLock {
            destinationExisted.append(FileManager.default.fileExists(atPath: destination.path))
            return destinationExisted.count == failingCall
        }
        if shouldFail { throw ArchiveTestError.injectedSynchronizationFailure }
    }

    func destinationExistence() -> [Bool] {
        lock.withLock { destinationExisted }
    }
}

extension Array {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}

private struct ZIPFixture {
    let path: String
    let localPath: String?
    let contents: Data
    let flags: UInt16
    let method: UInt16
    let externalAttributes: UInt32
    let extraField: Data
    let compressedContents: Data?
    let crc32: UInt32?
    let declaredCompressedSize: UInt32?
    let declaredUncompressedSize: UInt32?

    init(
        path: String,
        localPath: String? = nil,
        contents: Data,
        flags: UInt16 = 0x0800,
        method: UInt16 = 0,
        externalAttributes: UInt32 = UInt32(0o100644) << 16,
        extraField: Data = Data(),
        compressedContents: Data? = nil,
        crc32: UInt32? = nil,
        declaredCompressedSize: UInt32? = nil,
        declaredUncompressedSize: UInt32? = nil
    ) {
        self.path = path
        self.localPath = localPath
        self.contents = contents
        self.flags = flags
        self.method = method
        self.externalAttributes = externalAttributes
        self.extraField = extraField
        self.compressedContents = compressedContents
        self.crc32 = crc32
        self.declaredCompressedSize = declaredCompressedSize
        self.declaredUncompressedSize = declaredUncompressedSize
    }
}

extension Data {
    fileprivate mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private func testCRC32(_ data: Data) -> UInt32 {
    var crc = UInt32.max
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320
        }
    }
    return ~crc
}

private func rawDeflate(_ data: Data) throws -> Data {
    var stream = z_stream()
    guard
        deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK
    else {
        throw ArchiveError.toolFailed(exitStatus: -1)
    }
    defer { deflateEnd(&stream) }
    var output = [UInt8](repeating: 0, count: max(64, data.count * 2))
    let count = try data.withUnsafeBytes { input in
        try output.withUnsafeMutableBytes { destination -> Int in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(destination.count)
            guard deflate(&stream, Z_FINISH) == Z_STREAM_END else {
                throw ArchiveError.toolFailed(exitStatus: -1)
            }
            return destination.count - Int(stream.avail_out)
        }
    }
    return Data(output.prefix(count))
}
