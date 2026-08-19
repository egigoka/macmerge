import Foundation
import XCTest
@testable import MacMergeCore

final class FolderComparatorTests: XCTestCase {
    func testNormalizeCanonicalizesPathsAndRejectsEveryInvalidPathForm() throws {
        XCTAssertEqual(
            try FolderComparator.normalize(relativePath: "folder//./cafe\u{301}"),
            "folder/café"
        )
        XCTAssertEqual(
            try FolderComparator.normalize(
                relativePath: "Folder/FILE.txt",
                caseSensitivity: .insensitive
            ),
            "folder/file.txt"
        )

        let invalidPaths: [(String, FolderRelativePathError)] = [
            ("", .empty),
            (".", .empty),
            ("/absolute", .absolute),
            ("../child", .parentTraversal),
            ("child/../sibling", .parentTraversal),
            ("null\0byte", .containsNull),
        ]
        for (path, expectedError) in invalidPaths {
            XCTAssertThrowsError(try FolderComparator.normalize(relativePath: path)) { error in
                XCTAssertEqual(error as? FolderRelativePathError, expectedError, "Path: \(path)")
            }
        }
    }

    func testMetadataOnlyCoversPresenceTypeAndMetadataStatusesInPathOrder() async throws {
        let left = FolderSnapshot(entries: [
            entry("type", kind: .directory),
            entry("metadata", size: 10, date: 10),
            entry("left", size: 1),
            entry("identical", kind: .symbolicLink, digest: digest([0x01])),
        ])
        let right = FolderSnapshot(entries: [
            entry("right", size: 1),
            entry("identical", kind: .symbolicLink, digest: digest([0x02])),
            entry("metadata", size: 11, date: 12),
            entry("type", kind: .regularFile),
        ])

        let results = try await FolderComparator.compare(
            left: left,
            right: right,
            options: FolderComparisonOptions(method: .metadataOnly)
        )

        XCTAssertEqual(results.map(\.normalizedRelativePath), [
            "identical", "left", "metadata", "right", "type",
        ])
        XCTAssertEqual(results.map(\.status), [
            .identical,
            .leftOnly,
            .metadataDifferent([.size, .modificationDate]),
            .rightOnly,
            .typeMismatch,
        ])
    }

    func testResultOrderingUsesNormalizedKeysBeforeRawPaths() async throws {
        let entries = [entry("./z"), entry("a")]

        for permutation in allPermutations(of: entries) {
            let results = try await FolderComparator.compare(
                left: FolderSnapshot(entries: permutation),
                right: FolderSnapshot(entries: [])
            )

            XCTAssertEqual(results.map(\.normalizedRelativePath), ["a", "z"])
            XCTAssertEqual(results.compactMap(\.left?.relativePath), ["a", "./z"])
        }
    }

    func testContentIfAvailableCoversDigestComparisonFallbackAndFailures() async throws {
        let left = FolderSnapshot(entries: [
            entry("canonical", size: 1, digest: digest([0x01], algorithm: " SHA-256 ")),
            entry("changed", size: 1, digest: digest([0x01])),
            entry("incompatible", size: 1, digest: digest([0x01], algorithm: "sha256")),
            entry("size", size: 1),
            entry("unavailable", size: 1, date: 10),
        ])
        let right = FolderSnapshot(entries: [
            entry("unavailable", size: 1, date: 20),
            entry("size", size: 2),
            entry("incompatible", size: 1, digest: digest([0x01], algorithm: "md5")),
            entry("changed", size: 1, digest: digest([0x02])),
            entry("canonical", size: 1, digest: digest([0x01], algorithm: "sha-256")),
        ])

        let results = try await FolderComparator.compare(
            left: left,
            right: right,
            options: FolderComparisonOptions(method: .contentIfAvailable)
        )

        XCTAssertEqual(results.map(\.normalizedRelativePath), [
            "canonical", "changed", "incompatible", "size", "unavailable",
        ])
        XCTAssertEqual(results.map(\.status), [
            .identical,
            .contentDifferent,
            .comparisonFailure(
                .incompatibleContentDigests(
                    leftAlgorithm: "sha256",
                    rightAlgorithm: "md5"
                )),
            .contentDifferent,
            .metadataDifferent([.modificationDate]),
        ])
    }

    func testContentRequiredReportsUnavailableSidesAndStillHandlesNonfiles() async throws {
        let sharedDigest = digest([0xA5])
        let left = FolderSnapshot(entries: [
            entry("directory", kind: .directory),
            entry("metadata", size: 1, date: 10, digest: sharedDigest),
            entry("missing-both", size: 1),
            entry("missing-left", size: 1),
        ])
        let right = FolderSnapshot(entries: [
            entry("missing-left", size: 1, digest: sharedDigest),
            entry("missing-both", size: 1),
            entry("metadata", size: 1, date: 11, digest: sharedDigest),
            entry("directory", kind: .directory),
        ])

        let results = try await FolderComparator.compare(
            left: left,
            right: right,
            options: FolderComparisonOptions(method: .contentRequired)
        )

        XCTAssertEqual(results.map(\.normalizedRelativePath), [
            "directory", "metadata", "missing-both", "missing-left",
        ])
        XCTAssertEqual(results.map(\.status), [
            .identical,
            .metadataDifferent([.modificationDate]),
            .comparisonFailure(.contentDigestUnavailable(sides: [.left, .right])),
            .comparisonFailure(.contentDigestUnavailable(sides: [.left])),
        ])
    }

    func testContentRequiredRequestsBothDigestsDespiteSizeMismatch() async throws {
        let recorder = DigestInvocationRecorder()
        let provider = FolderContentDigestProvider { side, entry in
            await recorder.record(side, entry: entry)
            return FolderContentDigest(algorithm: "fixture", bytes: Data([0x01]))
        }
        let leftEntry = entry("file", size: 1)
        let rightEntry = entry("file", size: 2)

        let results = try await FolderComparator.compare(
            left: FolderSnapshot(entries: [leftEntry]),
            right: FolderSnapshot(entries: [rightEntry]),
            options: FolderComparisonOptions(method: .contentRequired),
            contentDigestProvider: provider
        )

        XCTAssertEqual(results.map(\.status), [.contentDifferent])
        let invocations = await recorder.recordedInvocations()
        XCTAssertEqual(invocations, [
            DigestInvocation(side: .left, entry: leftEntry),
            DigestInvocation(side: .right, entry: rightEntry),
        ])
    }

    func testNormalizedCollisionRetainsSortedEntriesAndUnambiguousPeer() async throws {
        let first = entry("A//./b", size: 2)
        let second = entry("a/b", size: 1)
        let peer = entry("A/B", size: 3)

        let results = try await FolderComparator.compare(
            left: FolderSnapshot(entries: [second, first, second]),
            right: FolderSnapshot(entries: [peer]),
            options: FolderComparisonOptions(pathCaseSensitivity: .insensitive)
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].normalizedRelativePath, "a/b")
        XCTAssertNil(results[0].left)
        XCTAssertEqual(results[0].right, peer)
        XCTAssertEqual(
            results[0].status,
            .comparisonFailure(
                .duplicateNormalizedPath(
                    leftEntries: [first, second, second],
                    rightEntries: [peer]
                ))
        )
    }

    func testCollisionPathOrderingUsesRawUTF8AcrossEquivalentPathPermutations() async throws {
        let paths = ["caf\u{e9}", "cafe\u{301}", "CAF\u{c9}"]
        let expectedPaths = ["CAF\u{c9}", "cafe\u{301}", "caf\u{e9}"]

        for permutation in threeElementPermutations {
            let results = try await FolderComparator.compare(
                left: FolderSnapshot(entries: permutation.map { entry(paths[$0]) }),
                right: FolderSnapshot(entries: []),
                options: FolderComparisonOptions(pathCaseSensitivity: .insensitive)
            )

            guard case .comparisonFailure(
                .duplicateNormalizedPath(let sortedEntries, let rightEntries)
            ) = results.first?.status else {
                return XCTFail("Expected normalized-path collision for \(permutation)")
            }
            XCTAssertTrue(rightEntries.isEmpty)
            XCTAssertEqual(
                sortedEntries.map { Data($0.relativePath.utf8) },
                expectedPaths.map { Data($0.utf8) },
                "Input: \(permutation)"
            )
        }
    }

    func testNormalizedResultAndCollisionOrderingHandlesCanonicalCaseFoldedKeys() async throws {
        let paths = [
            "\u{00F6}mega", "E\u{0301}clair", "\u{00D6}mega", "\u{00E9}clair",
            "o\u{0308}mega", "\u{00C9}clair", "O\u{0308}mega", "e\u{0301}clair",
        ]
        let inputPermutations = [paths, Array(paths.reversed())]
        let expectedNormalizedPathBytes = [
            Data("\u{00E9}clair".utf8),
            Data("\u{00F6}mega".utf8),
        ]
        let expectedCollisionPathBytes = [
            [
                Data("E\u{0301}clair".utf8),
                Data("e\u{0301}clair".utf8),
                Data("\u{00C9}clair".utf8),
                Data("\u{00E9}clair".utf8),
            ],
            [
                Data("O\u{0308}mega".utf8),
                Data("o\u{0308}mega".utf8),
                Data("\u{00D6}mega".utf8),
                Data("\u{00F6}mega".utf8),
            ],
        ]
        var firstResults: [FolderComparisonEntry]?

        for (index, permutation) in inputPermutations.enumerated() {
            let results = try await FolderComparator.compare(
                left: FolderSnapshot(entries: permutation.map { entry($0) }),
                right: FolderSnapshot(entries: []),
                options: FolderComparisonOptions(pathCaseSensitivity: .insensitive)
            )

            XCTAssertEqual(results.count, 2, "Input permutation: \(index)")
            XCTAssertEqual(
                results.compactMap { $0.normalizedRelativePath.map { Data($0.utf8) } },
                expectedNormalizedPathBytes,
                "Input permutation: \(index)"
            )

            var collisionPathBytes: [[Data]] = []
            for result in results {
                guard case .comparisonFailure(
                    .duplicateNormalizedPath(let leftEntries, let rightEntries)
                ) = result.status else {
                    XCTFail("Expected normalized-path collision for input permutation \(index)")
                    continue
                }
                XCTAssertTrue(rightEntries.isEmpty, "Input permutation: \(index)")
                collisionPathBytes.append(leftEntries.map { Data($0.relativePath.utf8) })
            }
            XCTAssertEqual(
                collisionPathBytes,
                expectedCollisionPathBytes,
                "Input permutation: \(index)"
            )

            if let firstResults {
                XCTAssertEqual(results, firstResults, "Input permutation: \(index)")
            } else {
                firstResults = results
            }
        }
    }

    func testCollisionDigestOrderingUsesRawUTF8AcrossEquivalentAlgorithmPermutations() async throws {
        let algorithms = ["sha-é", "sha-e\u{301}", " SHA-É "]
        let expectedAlgorithms = [" SHA-É ", "sha-e\u{301}", "sha-é"]

        for permutation in threeElementPermutations {
            let entries = permutation.map {
                entry("collision", digest: digest([0x01], algorithm: algorithms[$0]))
            }
            let results = try await FolderComparator.compare(
                left: FolderSnapshot(entries: entries),
                right: FolderSnapshot(entries: [])
            )

            guard case .comparisonFailure(
                .duplicateNormalizedPath(let sortedEntries, let rightEntries)
            ) = results.first?.status else {
                return XCTFail("Expected normalized-path collision for \(permutation)")
            }
            XCTAssertTrue(rightEntries.isEmpty)
            XCTAssertEqual(
                sortedEntries.compactMap { $0.contentDigest.map { Data($0.algorithm.utf8) } },
                expectedAlgorithms.map { Data($0.utf8) },
                "Input: \(permutation)"
            )
        }
    }

    func testCollisionOrderingExhaustsEveryPriorTiedMetadataAndDigestKey() async throws {
        let directory = entry("collision", kind: .directory)
        let other = entry("collision", kind: .other)
        let regularFile = entry("collision", kind: .regularFile)
        let symbolicLink = entry("collision", kind: .symbolicLink)

        let nilSize = entry("collision", size: nil)
        let zeroSize = entry("collision", size: 0)
        let oneSize = entry("collision", size: 1)
        let maximumSize = entry("collision", size: .max)

        let noDigest = entry("collision", size: 1, date: 1, digest: nil)
        let presentDigest = entry("collision", size: 1, date: 1, digest: digest([0x01]))

        let blake3 = entry(
            "collision",
            size: 1,
            date: 1,
            digest: digest([0x01], algorithm: "blake3")
        )
        let md5 = entry(
            "collision",
            size: 1,
            date: 1,
            digest: digest([0x01], algorithm: "md5")
        )
        let sha256 = entry(
            "collision",
            size: 1,
            date: 1,
            digest: digest([0x01], algorithm: "sha256")
        )

        let zeroByte = entry("collision", digest: digest([0x00]))
        let zeroZeroBytes = entry("collision", digest: digest([0x00, 0x00]))
        let zeroMaximumBytes = entry("collision", digest: digest([0x00, 0xFF]))
        let oneByte = entry("collision", digest: digest([0x01]))

        let fixtures: [(name: String, entries: [FolderEntry], expected: [FolderEntry])] = [
            (
                "kind raw value",
                [symbolicLink, regularFile, directory, other],
                [directory, other, regularFile, symbolicLink]
            ),
            (
                "optional size nil first then numeric",
                [maximumSize, oneSize, nilSize, zeroSize],
                [nilSize, zeroSize, oneSize, maximumSize]
            ),
            (
                "optional digest nil first",
                [presentDigest, noDigest],
                [noDigest, presentDigest]
            ),
            (
                "canonical digest algorithm",
                [sha256, blake3, md5],
                [blake3, md5, sha256]
            ),
            (
                "digest bytes lexicographically",
                [oneByte, zeroMaximumBytes, zeroZeroBytes, zeroByte],
                [zeroByte, zeroZeroBytes, zeroMaximumBytes, oneByte]
            ),
        ]

        for fixture in fixtures {
            for permutation in allPermutations(of: fixture.entries) {
                let sortedEntries = try await collisionEntries(from: permutation)

                XCTAssertEqual(
                    sortedEntries,
                    fixture.expected,
                    "Key: \(fixture.name), input: \(permutation)"
                )
            }
        }
    }

    func testResultAndInvalidPathOrderingIsDeterministicAcrossInputOrder() async throws {
        let leftEntries = [
            entry("z"),
            entry("../left-parent"),
            entry(""),
        ]
        let rightEntries = [
            entry("a"),
            entry("/right-absolute"),
            entry("right\0null"),
        ]
        let forward = try await FolderComparator.compare(
            left: FolderSnapshot(entries: leftEntries),
            right: FolderSnapshot(entries: rightEntries)
        )
        let reversed = try await FolderComparator.compare(
            left: FolderSnapshot(entries: leftEntries.reversed()),
            right: FolderSnapshot(entries: rightEntries.reversed())
        )

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.map(\.normalizedRelativePath), ["a", "z", nil, nil, nil, nil])
        XCTAssertEqual(forward.map(\.status), [
            .rightOnly,
            .leftOnly,
            .comparisonFailure(.invalidRelativePath(side: .left, error: .empty)),
            .comparisonFailure(.invalidRelativePath(side: .left, error: .parentTraversal)),
            .comparisonFailure(.invalidRelativePath(side: .right, error: .absolute)),
            .comparisonFailure(.invalidRelativePath(side: .right, error: .containsNull)),
        ])
    }

    func testInvalidResultSidePrecedesConflictingRawPathOrder() async throws {
        let leftEntries = [entry("z\0left"), entry("../left-parent")]
        let rightEntries = [entry("/right-absolute"), entry("")]

        for leftPermutation in allPermutations(of: leftEntries) {
            for rightPermutation in allPermutations(of: rightEntries) {
                let results = try await FolderComparator.compare(
                    left: FolderSnapshot(entries: leftPermutation),
                    right: FolderSnapshot(entries: rightPermutation)
                )

                XCTAssertEqual(
                    results.compactMap { ($0.left ?? $0.right)?.relativePath },
                    ["../left-parent", "z\0left", "", "/right-absolute"]
                )
                XCTAssertEqual(results.map(\.status), [
                    .comparisonFailure(.invalidRelativePath(side: .left, error: .parentTraversal)),
                    .comparisonFailure(.invalidRelativePath(side: .left, error: .containsNull)),
                    .comparisonFailure(.invalidRelativePath(side: .right, error: .empty)),
                    .comparisonFailure(.invalidRelativePath(side: .right, error: .absolute)),
                ])
            }
        }
    }

    func testCollisionDateOrderingUsesTotalOrderForEdgeValues() async throws {
        let negativeNaN = Double(bitPattern: 0xFFF8_0000_0000_0001)
        let positiveNaN = Double(bitPattern: 0x7FF8_0000_0000_0001)
        let dates: [TimeInterval?] = [
            positiveNaN,
            .infinity,
            1,
            0,
            -0.0,
            -1,
            -.infinity,
            negativeNaN,
            nil,
        ]
        let entries = dates.map { value in
            FolderEntry(
                relativePath: "collision",
                kind: .regularFile,
                size: 1,
                modificationDate: value.map(Date.init(timeIntervalSinceReferenceDate:))
            )
        }

        let results = try await FolderComparator.compare(
            left: FolderSnapshot(entries: entries),
            right: FolderSnapshot(entries: [])
        )

        guard case .comparisonFailure(
            .duplicateNormalizedPath(let sortedEntries, let rightEntries)
        ) = results.first?.status else {
            return XCTFail("Expected normalized-path collision")
        }
        XCTAssertTrue(rightEntries.isEmpty)
        XCTAssertEqual(
            sortedEntries.map { $0.modificationDate?.timeIntervalSinceReferenceDate.bitPattern },
            [
                nil,
                negativeNaN.bitPattern,
                (-Double.infinity).bitPattern,
                (-1.0).bitPattern,
                (-0.0).bitPattern,
                0.0.bitPattern,
                1.0.bitPattern,
                Double.infinity.bitPattern,
                positiveNaN.bitPattern,
            ]
        )

        let datePermutations: [[TimeInterval]] = [
            [negativeNaN, -0.0, positiveNaN],
            [negativeNaN, positiveNaN, -0.0],
            [-0.0, negativeNaN, positiveNaN],
            [-0.0, positiveNaN, negativeNaN],
            [positiveNaN, negativeNaN, -0.0],
            [positiveNaN, -0.0, negativeNaN],
        ]
        for permutation in datePermutations {
            let permutationResults = try await FolderComparator.compare(
                left: FolderSnapshot(entries: permutation.map { entry("collision", date: $0) }),
                right: FolderSnapshot(entries: [])
            )
            guard case .comparisonFailure(
                .duplicateNormalizedPath(let permutationEntries, _)
            ) = permutationResults.first?.status else {
                return XCTFail("Expected normalized-path collision for \(permutation)")
            }
            XCTAssertEqual(
                permutationEntries.map {
                    $0.modificationDate?.timeIntervalSinceReferenceDate.bitPattern
                },
                [negativeNaN.bitPattern, (-0.0).bitPattern, positiveNaN.bitPattern],
                "Input: \(permutation)"
            )
        }
    }

    func testCollisionDateTotalOrderDistinguishesSameSignNaNPayloadsAcrossAllPermutations() async throws {
        let negativePayloadOne = Double(bitPattern: 0xFFF8_0000_0000_0001)
        let negativePayloadTwo = Double(bitPattern: 0xFFF8_0000_0000_0002)
        let positivePayloadOne = Double(bitPattern: 0x7FF8_0000_0000_0001)
        let positivePayloadTwo = Double(bitPattern: 0x7FF8_0000_0000_0002)
        let values = [
            positivePayloadTwo,
            negativePayloadOne,
            positivePayloadOne,
            negativePayloadTwo,
        ]
        let expectedBits = [
            negativePayloadTwo.bitPattern,
            negativePayloadOne.bitPattern,
            positivePayloadOne.bitPattern,
            positivePayloadTwo.bitPattern,
        ]

        for permutation in allPermutations(of: values) {
            let sortedEntries = try await collisionEntries(
                from: permutation.map { entry("collision", date: $0) }
            )

            XCTAssertEqual(
                sortedEntries.map { $0.modificationDate!.timeIntervalSinceReferenceDate.bitPattern },
                expectedBits,
                "Input bits: \(permutation.map(\.bitPattern))"
            )
        }
    }

    func testDigestDecoderRejectsEmptyAndWhitespaceAlgorithms() throws {
        for algorithm in ["", " ", "\t\n"] {
            let data = try JSONEncoder().encode(DigestWire(algorithm: algorithm, bytes: Data([0x01])))

            XCTAssertThrowsError(try JSONDecoder().decode(FolderContentDigest.self, from: data)) { error in
                guard case DecodingError.dataCorrupted(let context) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(context.codingPath.last?.stringValue, "algorithm")
                XCTAssertEqual(context.debugDescription, "Digest algorithm must be nonempty")
            }
        }
    }

    func testOptionsDecoderRejectsEveryNonfiniteOrNegativeTolerance() throws {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )

        for tolerance in [-1.0, Double.infinity, -Double.infinity, Double.nan] {
            let data = try encoder.encode(
                OptionsWire(
                    method: .metadataOnly,
                    pathCaseSensitivity: .sensitive,
                    modificationDateTolerance: tolerance
                ))

            XCTAssertThrowsError(try decoder.decode(FolderComparisonOptions.self, from: data)) { error in
                guard case DecodingError.dataCorrupted(let context) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(context.codingPath.last?.stringValue, "modificationDateTolerance")
                XCTAssertEqual(
                    context.debugDescription,
                    "Modification date tolerance must be finite and nonnegative"
                )
            }
        }
    }

    func testOptionsDecoderPreservesFiniteTolerance() throws {
        let data = try JSONEncoder().encode(
            OptionsWire(
                method: .contentRequired,
                pathCaseSensitivity: .insensitive,
                modificationDateTolerance: 0.125
            ))

        let decoded = try JSONDecoder().decode(FolderComparisonOptions.self, from: data)

        XCTAssertEqual(
            decoded,
            FolderComparisonOptions(
                method: .contentRequired,
                pathCaseSensitivity: .insensitive,
                modificationDateTolerance: 0.125
            )
        )
    }

    func testModificationDateToleranceIsInclusiveAndNonfiniteDifferencesDiffer() async throws {
        let left = FolderSnapshot(entries: [
            entry("boundary", date: 10),
            entry("infinite", date: -.infinity),
            entry("nan", date: .nan),
            entry("negative-infinity", date: -.infinity),
            entry("nil", date: nil),
            entry("outside", date: 10),
            entry("positive-infinity", date: .infinity),
        ])
        let right = FolderSnapshot(entries: [
            entry("outside", date: 11.001),
            entry("nil", date: 10),
            entry("negative-infinity", date: -.infinity),
            entry("nan", date: .nan),
            entry("infinite", date: .infinity),
            entry("boundary", date: 11),
            entry("positive-infinity", date: .infinity),
        ])

        let results = try await FolderComparator.compare(
            left: left,
            right: right,
            options: FolderComparisonOptions(modificationDateTolerance: 1)
        )

        let expectedStatuses: [(String, FolderComparisonStatus)] = [
            ("boundary", .identical),
            ("infinite", .metadataDifferent([.modificationDate])),
            ("nan", .metadataDifferent([.modificationDate])),
            ("negative-infinity", .metadataDifferent([.modificationDate])),
            ("nil", .metadataDifferent([.modificationDate])),
            ("outside", .metadataDifferent([.modificationDate])),
            ("positive-infinity", .metadataDifferent([.modificationDate])),
        ]
        XCTAssertEqual(results.count, expectedStatuses.count)
        for (normalizedRelativePath, expectedStatus) in expectedStatuses {
            let result = try XCTUnwrap(
                results.first { $0.normalizedRelativePath == normalizedRelativePath }
            )
            XCTAssertEqual(result.status, expectedStatus, "Path: \(normalizedRelativePath)")
        }
    }

    func testProviderFailuresPreserveSideAndNSErrorDiagnostics() async throws {
        for failingSide in [FolderComparisonSide.left, .right] {
            let recorder = DigestInvocationRecorder()
            let provider = FolderContentDigestProvider { side, entry in
                await recorder.record(side, entry: entry)
                if side == failingSide {
                    throw DigestProviderFixtureError(side: side)
                }
                return FolderContentDigest(algorithm: "fixture", bytes: Data([0x01]))
            }

            let results = try await FolderComparator.compare(
                left: FolderSnapshot(entries: [entry("file")]),
                right: FolderSnapshot(entries: [entry("file")]),
                options: FolderComparisonOptions(method: .contentRequired),
                contentDigestProvider: provider
            )

            XCTAssertEqual(results.map(\.status), [
                .comparisonFailure(
                    .contentDigestProviderFailed(
                        side: failingSide,
                        errorDomain: DigestProviderFixtureError.errorDomain,
                        errorCode: failingSide == .left ? 41 : 42,
                        message: "digest failed on \(failingSide.rawValue)"
                    )),
            ])
            let recordedSides = await recorder.recordedSides()
            XCTAssertEqual(recordedSides, failingSide == .left ? [.left] : [.left, .right])
        }
    }

    func testCancellationAtSortCheckpointsIsPropagated() async {
        let fixtures: [(
            checkpoint: FolderComparator.SortCheckpoint,
            left: FolderSnapshot,
            right: FolderSnapshot
        )] = [
            (
                .resultPaths,
                FolderSnapshot(entries: [entry("b"), entry("a")]),
                FolderSnapshot(entries: [])
            ),
            (
                .collisionEntries,
                FolderSnapshot(entries: [entry("collision", size: 2), entry("collision", size: 1)]),
                FolderSnapshot(entries: [])
            ),
            (
                .invalidPathResults,
                FolderSnapshot(entries: [entry("../invalid"), entry("/invalid")]),
                FolderSnapshot(entries: [])
            ),
        ]

        for fixture in fixtures {
            let sortGate = SortCheckpointSuspension(checkpoint: fixture.checkpoint)
            let comparison = Task {
                try await FolderComparator.$sortCheckpointObserver.withValue({ checkpoint in
                    await sortGate.suspendIfTarget(checkpoint)
                }) {
                    try await FolderComparator.compare(left: fixture.left, right: fixture.right)
                }
            }

            guard await sortGate.waitUntilStarted() else {
                comparison.cancel()
                await sortGate.release()
                _ = try? await comparison.value
                XCTFail("Timed out waiting for \(fixture.checkpoint)")
                continue
            }
            comparison.cancel()
            await sortGate.release()

            do {
                _ = try await comparison.value
                XCTFail("Expected cancellation at \(fixture.checkpoint)")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error at \(fixture.checkpoint): \(error)")
            }
        }
    }

    func testCancellationIsPropagatedBeforeWorkAndFromProvider() async {
        let cancelledBeforeWork = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FolderComparator.compare(
                left: FolderSnapshot(entries: [entry("file")]),
                right: FolderSnapshot(entries: [])
            )
        }

        do {
            _ = try await cancelledBeforeWork.value
            XCTFail("Expected preflight cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected preflight error: \(error)")
        }

        let cancellingProvider = FolderContentDigestProvider { _, _ in
            throw CancellationError()
        }
        do {
            _ = try await FolderComparator.compare(
                left: FolderSnapshot(entries: [entry("file")]),
                right: FolderSnapshot(entries: [entry("file")]),
                options: FolderComparisonOptions(method: .contentRequired),
                contentDigestProvider: cancellingProvider
            )
            XCTFail("Expected provider cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected provider error: \(error)")
        }

        let suspension = DigestProviderSuspension()
        let suspendedProvider = FolderContentDigestProvider { side, _ in
            if side == .right {
                await suspension.suspend()
            }
            return FolderContentDigest(algorithm: "fixture", bytes: Data([0x01]))
        }
        let cancelledDuringProvider = Task {
            try await FolderComparator.compare(
                left: FolderSnapshot(entries: [entry("file")]),
                right: FolderSnapshot(entries: [entry("file")]),
                options: FolderComparisonOptions(method: .contentRequired),
                contentDigestProvider: suspendedProvider
            )
        }
        guard await suspension.waitUntilStarted() else {
            cancelledDuringProvider.cancel()
            await suspension.release()
            _ = try? await cancelledDuringProvider.value
            XCTFail("Timed out waiting for digest provider suspension")
            return
        }
        cancelledDuringProvider.cancel()
        await suspension.release()

        do {
            _ = try await cancelledDuringProvider.value
            XCTFail("Expected cancellation after provider suspension")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected suspended-provider error: \(error)")
        }
    }

}

private let threeElementPermutations = [
    [0, 1, 2],
    [0, 2, 1],
    [1, 0, 2],
    [1, 2, 0],
    [2, 0, 1],
    [2, 1, 0],
]

private func allPermutations<Element>(of values: [Element]) -> [[Element]] {
    guard !values.isEmpty else { return [[]] }

    return values.indices.flatMap { index in
        var remainder = values
        let value = remainder.remove(at: index)
        return allPermutations(of: remainder).map { [value] + $0 }
    }
}

private func collisionEntries(from entries: [FolderEntry]) async throws -> [FolderEntry] {
    let results = try await FolderComparator.compare(
        left: FolderSnapshot(entries: entries),
        right: FolderSnapshot(entries: [])
    )

    guard case .comparisonFailure(
        .duplicateNormalizedPath(let sortedEntries, let rightEntries)
    ) = results.first?.status else {
        XCTFail("Expected normalized-path collision")
        return []
    }
    XCTAssertEqual(results.count, 1)
    XCTAssertTrue(rightEntries.isEmpty)
    return sortedEntries
}

private func entry(
    _ path: String,
    kind: FolderEntryKind = .regularFile,
    size: UInt64? = nil,
    date: TimeInterval? = nil,
    digest: FolderContentDigest? = nil
) -> FolderEntry {
    FolderEntry(
        relativePath: path,
        kind: kind,
        size: size,
        modificationDate: date.map(Date.init(timeIntervalSinceReferenceDate:)),
        contentDigest: digest
    )
}

private func digest(
    _ bytes: [UInt8],
    algorithm: String = "sha256"
) -> FolderContentDigest {
    FolderContentDigest(algorithm: algorithm, bytes: Data(bytes))
}

private struct DigestInvocation: Equatable, Sendable {
    let side: FolderComparisonSide
    let entry: FolderEntry
}

private actor DigestInvocationRecorder {
    private var invocations: [DigestInvocation] = []

    func record(_ side: FolderComparisonSide, entry: FolderEntry) {
        invocations.append(DigestInvocation(side: side, entry: entry))
    }

    func recordedSides() -> [FolderComparisonSide] {
        invocations.map(\.side)
    }

    func recordedInvocations() -> [DigestInvocation] {
        invocations
    }
}

private actor DigestProviderSuspension {
    private var isStarted = false
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        isStarted = true
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted(timeout: Duration = .seconds(5)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isStarted, clock.now < deadline {
            do {
                try await clock.sleep(for: .milliseconds(10))
            } catch {
                return false
            }
        }
        return isStarted
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor SortCheckpointSuspension {
    private let checkpoint: FolderComparator.SortCheckpoint
    private var isStarted = false
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(checkpoint: FolderComparator.SortCheckpoint) {
        self.checkpoint = checkpoint
    }

    func suspendIfTarget(_ checkpoint: FolderComparator.SortCheckpoint) async {
        guard checkpoint == self.checkpoint else { return }
        isStarted = true
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted(timeout: Duration = .seconds(5)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isStarted, clock.now < deadline {
            do {
                try await clock.sleep(for: .milliseconds(10))
            } catch {
                return false
            }
        }
        return isStarted
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private struct DigestProviderFixtureError: Error, CustomNSError, Sendable {
    static let errorDomain = "FolderComparatorTests.DigestProvider"

    let side: FolderComparisonSide

    var errorCode: Int { side == .left ? 41 : 42 }

    var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: "digest failed on \(side.rawValue)"]
    }
}

private struct DigestWire: Encodable {
    let algorithm: String
    let bytes: Data
}

private struct OptionsWire: Encodable {
    let method: FolderComparisonMethod
    let pathCaseSensitivity: FolderPathCaseSensitivity
    let modificationDateTolerance: TimeInterval
}
