import Foundation
import XCTest

@testable import MacMergeCore

final class ThreeWayFolderComparisonTests: XCTestCase {
    func testHappyPathClassifiesEveryResolutionAndBuildsSummary() async throws {
        let left = FolderSnapshot(entries: [
            folderEntry("conflict", size: 2),
            folderEntry("identical", size: 2),
            folderEntry("left", size: 2),
            folderEntry("right", size: 1),
            folderEntry("unchanged", size: 1)
        ])
        let middle = FolderSnapshot(entries: [
            folderEntry("conflict", size: 1),
            folderEntry("identical", size: 1),
            folderEntry("left", size: 1),
            folderEntry("right", size: 1),
            folderEntry("unchanged", size: 1)
        ])
        let right = FolderSnapshot(entries: [
            folderEntry("conflict", size: 3),
            folderEntry("identical", size: 2),
            folderEntry("left", size: 1),
            folderEntry("right", size: 2),
            folderEntry("unchanged", size: 1)
        ])

        let result = try await ThreeWayFolderComparison.compare(
            left: left,
            middle: middle,
            right: right
        )
        let entries = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.normalizedRelativePath, $0) })

        XCTAssertEqual(
            result.entries.map(\.normalizedRelativePath),
            [
                "conflict", "identical", "left", "right", "unchanged"
            ])
        XCTAssertEqual(entries["unchanged"]?.resolution, .unchanged)
        XCTAssertEqual(entries["left"]?.resolution, .left)
        XCTAssertEqual(entries["right"]?.resolution, .right)
        XCTAssertEqual(entries["identical"]?.resolution, .identical)
        XCTAssertEqual(entries["conflict"]?.resolution, .conflict)
        XCTAssertEqual(entries["conflict"]?.conflictKind, .metadataDifference)

        XCTAssertEqual(entries["unchanged"]?.resolution.automaticSource, .middle)
        XCTAssertEqual(entries["left"]?.resolution.automaticSource, .left)
        XCTAssertEqual(entries["right"]?.resolution.automaticSource, .right)
        XCTAssertEqual(entries["identical"]?.resolution.automaticSource, .left)
        XCTAssertNil(entries["conflict"]?.resolution.automaticSource)

        XCTAssertEqual(entries["unchanged"]?.equality.leftEqualsMiddle, true)
        XCTAssertEqual(entries["unchanged"]?.equality.rightEqualsMiddle, true)
        XCTAssertEqual(entries["unchanged"]?.equality.leftEqualsRight, true)
        XCTAssertEqual(entries["left"]?.equality.leftEqualsMiddle, false)
        XCTAssertEqual(entries["left"]?.equality.rightEqualsMiddle, true)
        XCTAssertEqual(entries["right"]?.equality.leftEqualsMiddle, true)
        XCTAssertEqual(entries["right"]?.equality.rightEqualsMiddle, false)
        XCTAssertEqual(entries["identical"]?.equality.leftEqualsRight, true)
        XCTAssertEqual(entries["conflict"]?.equality.leftEqualsMiddle, false)
        XCTAssertEqual(entries["conflict"]?.equality.rightEqualsMiddle, false)
        XCTAssertEqual(entries["conflict"]?.equality.leftEqualsRight, false)

        for entry in result.entries {
            XCTAssertEqual(entry.presence, .all)
            XCTAssertEqual(entry.typeState, .uniform(.regularFile))
            XCTAssertEqual(entry.comparisons.leftAndMiddle.presenceState, .both)
            XCTAssertEqual(entry.comparisons.rightAndMiddle.presenceState, .both)
            XCTAssertEqual(entry.comparisons.leftAndRight.presenceState, .both)
            XCTAssertEqual(entry.comparisons.leftAndMiddle.contentState, .notCompared)
            XCTAssertEqual(entry.comparisons.rightAndMiddle.contentState, .notCompared)
            XCTAssertEqual(entry.comparisons.leftAndRight.contentState, .notCompared)
        }

        XCTAssertEqual(result.summary.leftInputEntryCount, 5)
        XCTAssertEqual(result.summary.middleInputEntryCount, 5)
        XCTAssertEqual(result.summary.rightInputEntryCount, 5)
        XCTAssertEqual(result.summary.entryCount, 5)
        XCTAssertEqual(result.summary.unchangedEntryCount, 1)
        XCTAssertEqual(result.summary.leftChangeEntryCount, 1)
        XCTAssertEqual(result.summary.rightChangeEntryCount, 1)
        XCTAssertEqual(result.summary.identicalChangeEntryCount, 1)
        XCTAssertEqual(result.summary.conflictEntryCount, 1)
        XCTAssertEqual(result.summary.changedEntryCount, 4)
        XCTAssertEqual(result.summary.presenceDifferenceEntryCount, 0)
        XCTAssertEqual(result.summary.typeMismatchEntryCount, 0)
        XCTAssertEqual(result.summary.metadataDifferenceEntryCount, 4)
        XCTAssertEqual(result.summary.contentDifferenceEntryCount, 0)
        XCTAssertEqual(result.summary.unavailableContentEntryCount, 0)
        XCTAssertTrue(result.hasChanges)
        XCTAssertTrue(result.hasConflicts)
        XCTAssertEqual(result.changedEntryIDs.map(\.rawValue), ["conflict", "identical", "left", "right"])
        XCTAssertEqual(result.conflictEntryIDs.map(\.rawValue), ["conflict"])
    }

    func testConflictKindsCoverDivergentInsertionDeletionAndTypeMismatch() async throws {
        let result = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: [
                folderEntry("divergent-insertion", size: 1),
                folderEntry("type-mismatch", kind: .directory)
            ]),
            middle: FolderSnapshot(entries: [
                folderEntry("deletion-versus-change", size: 1),
                folderEntry("type-mismatch")
            ]),
            right: FolderSnapshot(entries: [
                folderEntry("deletion-versus-change", size: 2),
                folderEntry("divergent-insertion", size: 2),
                folderEntry("type-mismatch", kind: .symbolicLink)
            ])
        )
        let entries = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.normalizedRelativePath, $0) })

        XCTAssertEqual(entries["divergent-insertion"]?.presence, .leftAndRight)
        XCTAssertEqual(entries["divergent-insertion"]?.conflictKind, .divergentInsertion)
        XCTAssertEqual(entries["deletion-versus-change"]?.presence, .middleAndRight)
        XCTAssertEqual(entries["deletion-versus-change"]?.conflictKind, .deletionVersusChange)
        XCTAssertEqual(entries["type-mismatch"]?.presence, .all)
        XCTAssertEqual(entries["type-mismatch"]?.typeState, .mixed)
        XCTAssertEqual(entries["type-mismatch"]?.conflictKind, .typeMismatch)
        XCTAssertTrue(result.entries.allSatisfy(\.isConflict))
        XCTAssertEqual(result.summary.conflictEntryCount, 3)
        XCTAssertEqual(result.summary.presenceDifferenceEntryCount, 2)
        XCTAssertEqual(result.summary.typeMismatchEntryCount, 1)
    }

    func testPresenceOnlyChangesResolveAutomaticallyIncludingEqualInsertion() async throws {
        let result = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: [
                folderEntry("left-only"),
                folderEntry("left-and-middle"),
                folderEntry("left-and-right-equal")
            ]),
            middle: FolderSnapshot(entries: [
                folderEntry("middle-only"),
                folderEntry("left-and-middle"),
                folderEntry("middle-and-right")
            ]),
            right: FolderSnapshot(entries: [
                folderEntry("right-only"),
                folderEntry("left-and-right-equal"),
                folderEntry("middle-and-right")
            ])
        )
        let entries = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.normalizedRelativePath, $0) })

        let expected:
            [String: (
                presence: ThreeWayFolderPresence,
                resolution: ThreeWayFolderComparisonResolution,
                equality: (Bool, Bool, Bool)
            )] = [
                "left-only": (.leftOnly, .left, (false, true, false)),
                "middle-only": (.middleOnly, .identical, (false, false, true)),
                "right-only": (.rightOnly, .right, (true, false, false)),
                "left-and-middle": (.leftAndMiddle, .right, (true, false, false)),
                "left-and-right-equal": (.leftAndRight, .identical, (false, false, true)),
                "middle-and-right": (.middleAndRight, .left, (false, true, false))
            ]
        XCTAssertEqual(Set(entries.keys), Set(expected.keys))
        for (path, expectation) in expected {
            let entry = try XCTUnwrap(entries[path])
            XCTAssertEqual(entry.presence, expectation.presence, path)
            XCTAssertEqual(entry.resolution, expectation.resolution, path)
            XCTAssertNil(entry.conflictKind, path)
            XCTAssertEqual(entry.equality.leftEqualsMiddle, expectation.equality.0, path)
            XCTAssertEqual(entry.equality.rightEqualsMiddle, expectation.equality.1, path)
            XCTAssertEqual(entry.equality.leftEqualsRight, expectation.equality.2, path)
        }

        let equalInsertion = try XCTUnwrap(entries["left-and-right-equal"])
        XCTAssertEqual(equalInsertion.comparisons.leftAndMiddle.presenceState, .firstOnly)
        XCTAssertEqual(equalInsertion.comparisons.rightAndMiddle.presenceState, .firstOnly)
        XCTAssertEqual(equalInsertion.comparisons.leftAndRight.presenceState, .both)
        XCTAssertEqual(equalInsertion.comparisons.leftAndRight.contentState, .notCompared)
        XCTAssertEqual(result.summary.leftChangeEntryCount, 2)
        XCTAssertEqual(result.summary.rightChangeEntryCount, 2)
        XCTAssertEqual(result.summary.identicalChangeEntryCount, 2)
        XCTAssertEqual(result.summary.conflictEntryCount, 0)
        XCTAssertEqual(result.summary.presenceDifferenceEntryCount, 6)
        XCTAssertFalse(result.hasConflicts)
    }

    func testNonregularEntriesUseMetadataBranchesWithoutCallingProvider() async throws {
        let recorder = ThreeWayDigestInvocationRecorder()
        let provider = ThreeWayFolderContentDigestProvider { side, entry in
            await recorder.record(side, entry: entry)
            return folderDigest([0xFF])
        }
        let result = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: [
                folderEntry("directory", kind: .directory, size: 1),
                folderEntry("other-identical", kind: .other, size: 2),
                folderEntry("symbolic-link-left", kind: .symbolicLink, size: 2),
                folderEntry("type-mismatch", kind: .directory)
            ]),
            middle: FolderSnapshot(entries: [
                folderEntry("directory", kind: .directory, size: 1),
                folderEntry("other-identical", kind: .other, size: 1),
                folderEntry("symbolic-link-left", kind: .symbolicLink, size: 1),
                folderEntry("type-mismatch", kind: .symbolicLink)
            ]),
            right: FolderSnapshot(entries: [
                folderEntry("directory", kind: .directory, size: 1),
                folderEntry("other-identical", kind: .other, size: 2),
                folderEntry("symbolic-link-left", kind: .symbolicLink, size: 1),
                folderEntry("type-mismatch", kind: .other)
            ]),
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(method: .contentRequired)
            ),
            contentDigestProvider: provider
        )
        let entries = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.normalizedRelativePath, $0) })

        XCTAssertEqual(entries["directory"]?.resolution, .unchanged)
        XCTAssertEqual(entries["other-identical"]?.resolution, .identical)
        XCTAssertEqual(entries["symbolic-link-left"]?.resolution, .left)
        XCTAssertEqual(entries["type-mismatch"]?.resolution, .conflict)
        XCTAssertEqual(entries["type-mismatch"]?.conflictKind, .typeMismatch)
        for entry in result.entries {
            XCTAssertEqual(entry.comparisons.leftAndMiddle.contentState, .notApplicable)
            XCTAssertEqual(entry.comparisons.rightAndMiddle.contentState, .notApplicable)
            XCTAssertEqual(entry.comparisons.leftAndRight.contentState, .notApplicable)
        }
        let recordedInvocations = await recorder.recordedInvocations()
        XCTAssertTrue(recordedInvocations.isEmpty)
    }

    func testMetadataOnlyIgnoresDigestsAndNeverCallsProvider() async throws {
        let recorder = ThreeWayDigestInvocationRecorder()
        let provider = ThreeWayFolderContentDigestProvider { side, entry in
            await recorder.record(side, entry: entry)
            return folderDigest([0xFF])
        }
        let result = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: [folderEntry("file", size: 1, date: 10, digest: folderDigest([0x01]))]),
            middle: FolderSnapshot(entries: [folderEntry("file", size: 1, date: 10, digest: folderDigest([0x02]))]),
            right: FolderSnapshot(entries: [folderEntry("file", size: 1, date: 10, digest: folderDigest([0x03]))]),
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(method: .metadataOnly)
            ),
            contentDigestProvider: provider
        )

        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(entry.resolution, .unchanged)
        XCTAssertEqual(entry.comparisons.leftAndMiddle.contentState, .notCompared)
        XCTAssertEqual(entry.comparisons.rightAndMiddle.contentState, .notCompared)
        XCTAssertEqual(entry.comparisons.leftAndRight.contentState, .notCompared)
        let recordedInvocations = await recorder.recordedInvocations()
        XCTAssertTrue(recordedInvocations.isEmpty)
        XCTAssertEqual(result.summary.unchangedEntryCount, 1)
        XCTAssertFalse(result.hasChanges)
    }

    func testProvenDigestMismatchOverridesUnavailableFallbackAndCreatesConflict() async throws {
        let result = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: [folderEntry("file", size: 1, digest: folderDigest([0x01]))]),
            middle: FolderSnapshot(entries: [folderEntry("file", size: 1)]),
            right: FolderSnapshot(entries: [folderEntry("file", size: 1, digest: folderDigest([0x02]))]),
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(method: .contentIfAvailable)
            )
        )

        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(entry.comparisons.leftAndMiddle.contentState, .unavailable)
        XCTAssertTrue(entry.comparisons.leftAndMiddle.isEquivalent)
        XCTAssertEqual(entry.comparisons.rightAndMiddle.contentState, .unavailable)
        XCTAssertTrue(entry.comparisons.rightAndMiddle.isEquivalent)
        XCTAssertEqual(entry.comparisons.leftAndRight.contentState, .different)
        XCTAssertFalse(entry.comparisons.leftAndRight.isEquivalent)
        XCTAssertEqual(entry.resolution, .conflict)
        XCTAssertEqual(entry.conflictKind, .contentDifference)
        XCTAssertEqual(result.summary.contentDifferenceEntryCount, 1)
        XCTAssertEqual(result.summary.unavailableContentEntryCount, 1)
    }

    func testThreeAlgorithmProviderBridgeSupplementsRatherThanReplacesEmbeddedDigests() async throws {
        let recorder = ThreeWayDigestInvocationRecorder()
        let provider = ThreeWayFolderContentDigestProvider { side, entry in
            await recorder.record(side, entry: entry)
            switch side {
            case .left:
                return folderDigest([0xB2], algorithm: "algorithm-b")
            case .middle:
                return folderDigest([0xC3], algorithm: "algorithm-c")
            case .right:
                return folderDigest([0xA1], algorithm: "algorithm-a")
            }
        }
        let result = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: [
                folderEntry("file", size: 1, digest: folderDigest([0xA1], algorithm: " algorithm-A "))
            ]),
            middle: FolderSnapshot(entries: [
                folderEntry("file", size: 1, digest: folderDigest([0xB2], algorithm: "ALGORITHM-B"))
            ]),
            right: FolderSnapshot(entries: [
                folderEntry("file", size: 1, digest: folderDigest([0xC3], algorithm: "algorithm-c"))
            ]),
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(method: .contentRequired)
            ),
            contentDigestProvider: provider
        )

        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(entry.resolution, .unchanged)
        XCTAssertEqual(entry.comparisons.leftAndMiddle.contentState, .equal)
        XCTAssertEqual(entry.comparisons.rightAndMiddle.contentState, .equal)
        XCTAssertEqual(entry.comparisons.leftAndRight.contentState, .equal)
        let recordedSides = await recorder.recordedSides()
        XCTAssertEqual(recordedSides.count, 3)
        XCTAssertEqual(Set(recordedSides), Set(ThreeWayFolderComparisonSide.allCases))
    }

    func testDigestProviderCallsAreSerialAndEachRequestedSideIsCalledOnce() async throws {
        let recorder = ThreeWayDigestConcurrencyRecorder()
        let provider = ThreeWayFolderContentDigestProvider { side, entry in
            await recorder.begin(side, entry: entry)
            await Task.yield()
            await recorder.end()
            return folderDigest([0x01])
        }

        _ = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: [folderEntry("file")]),
            middle: FolderSnapshot(entries: [folderEntry("file")]),
            right: FolderSnapshot(entries: [folderEntry("file")]),
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(method: .contentRequired)
            ),
            contentDigestProvider: provider
        )

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.maximumConcurrentInvocations, 1)
        XCTAssertEqual(snapshot.invocations.count, 3)
        XCTAssertEqual(Set(snapshot.invocations.map(\.side)), Set(ThreeWayFolderComparisonSide.allCases))
    }

    func testProviderFailuresPreserveTypedNSErrorDiagnosticsWithoutAssumingOrder() async {
        for failingSide in ThreeWayFolderComparisonSide.allCases {
            let recorder = ThreeWayDigestInvocationRecorder()
            let provider = ThreeWayFolderContentDigestProvider { side, entry in
                await recorder.record(side, entry: entry)
                if side == failingSide {
                    throw ThreeWayDigestProviderFixtureError(side: side)
                }
                return folderDigest([0x01])
            }

            await assertComparisonError(
                .contentDigestProviderFailed(
                    side: failingSide,
                    relativePath: "file",
                    errorDomain: ThreeWayDigestProviderFixtureError.errorDomain,
                    errorCode: ThreeWayDigestProviderFixtureError(side: failingSide).errorCode,
                    message: "digest failed on \(failingSide.rawValue)"
                ),
                left: FolderSnapshot(entries: [folderEntry("file")]),
                middle: FolderSnapshot(entries: [folderEntry("file")]),
                right: FolderSnapshot(entries: [folderEntry("file")]),
                options: ThreeWayFolderComparisonOptions(
                    comparison: FolderComparisonOptions(method: .contentRequired)
                ),
                contentDigestProvider: provider
            )
            let recordedSides = await recorder.recordedSides()
            XCTAssertEqual(recordedSides.last, failingSide)
            XCTAssertEqual(recordedSides.filter { $0 == failingSide }.count, 1)
            XCTAssertEqual(Set(recordedSides).count, recordedSides.count)
        }
    }

    func testProviderReturnedDigestValidationAndWorkErrorsStayTyped() async {
        for side in ThreeWayFolderComparisonSide.allCases {
            let oversizedProvider = ThreeWayFolderContentDigestProvider { requestedSide, _ in
                folderDigest(requestedSide == side ? [0x01, 0x02] : [0x01])
            }
            await assertComparisonError(
                .digestTooLarge(side: side, relativePath: "file", maximumBytes: 1),
                left: FolderSnapshot(entries: [folderEntry("file")]),
                middle: FolderSnapshot(entries: [folderEntry("file")]),
                right: FolderSnapshot(entries: [folderEntry("file")]),
                options: ThreeWayFolderComparisonOptions(
                    comparison: FolderComparisonOptions(method: .contentRequired),
                    maximumDigestBytes: 1
                ),
                contentDigestProvider: oversizedProvider
            )

            let longAlgorithmProvider = ThreeWayFolderContentDigestProvider { requestedSide, _ in
                folderDigest([0x01], algorithm: requestedSide == side ? "xx" : "x")
            }
            await assertComparisonError(
                .digestAlgorithmTooLong(side: side, relativePath: "file", maximumUTF8Bytes: 1),
                left: FolderSnapshot(entries: [folderEntry("file")]),
                middle: FolderSnapshot(entries: [folderEntry("file")]),
                right: FolderSnapshot(entries: [folderEntry("file")]),
                options: ThreeWayFolderComparisonOptions(
                    comparison: FolderComparisonOptions(method: .contentRequired),
                    maximumDigestAlgorithmUTF8Bytes: 1
                ),
                contentDigestProvider: longAlgorithmProvider
            )
        }

        let recorder = ThreeWayDigestInvocationRecorder()
        let workLimitedProvider = ThreeWayFolderContentDigestProvider { side, entry in
            await recorder.record(side, entry: entry)
            return folderDigest(Array(repeating: 0x01, count: 8))
        }
        await assertComparisonError(
            .workLimitExceeded(maximumWorkUnits: 100),
            left: FolderSnapshot(entries: [folderEntry("file")]),
            middle: FolderSnapshot(entries: [folderEntry("file")]),
            right: FolderSnapshot(entries: [folderEntry("file")]),
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(method: .contentRequired),
                maximumWorkUnits: 100
            ),
            contentDigestProvider: workLimitedProvider
        )
        let recordedInvocations = await recorder.recordedInvocations()
        XCTAssertEqual(recordedInvocations.count, 1)
    }

    func testCancellationIsPropagatedBeforeWorkAndFromProvider() async {
        let cancelledBeforeWork = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ThreeWayFolderComparison.compare(
                left: FolderSnapshot(entries: [folderEntry("file")]),
                middle: FolderSnapshot(entries: []),
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

        let cancellingProvider = ThreeWayFolderContentDigestProvider { _, _ in
            throw CancellationError()
        }
        do {
            _ = try await ThreeWayFolderComparison.compare(
                left: FolderSnapshot(entries: [folderEntry("file")]),
                middle: FolderSnapshot(entries: [folderEntry("file")]),
                right: FolderSnapshot(entries: [folderEntry("file")]),
                options: ThreeWayFolderComparisonOptions(
                    comparison: FolderComparisonOptions(method: .contentRequired)
                ),
                contentDigestProvider: cancellingProvider
            )
            XCTFail("Expected provider cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected provider cancellation error: \(error)")
        }

        let recorder = ThreeWayDigestInvocationRecorder()
        let cancellationCheckpointProvider = ThreeWayFolderContentDigestProvider { side, entry in
            await recorder.record(side, entry: entry)
            withUnsafeCurrentTask { $0?.cancel() }
            return folderDigest([0x01])
        }
        let cancelledAtPostProviderCheckpoint = Task {
            try await ThreeWayFolderComparison.compare(
                left: FolderSnapshot(entries: [folderEntry("file")]),
                middle: FolderSnapshot(entries: [folderEntry("file")]),
                right: FolderSnapshot(entries: [folderEntry("file")]),
                options: ThreeWayFolderComparisonOptions(
                    comparison: FolderComparisonOptions(method: .contentRequired)
                ),
                contentDigestProvider: cancellationCheckpointProvider
            )
        }
        do {
            _ = try await cancelledAtPostProviderCheckpoint.value
            XCTFail("Expected cancellation after provider returned")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected post-provider cancellation error: \(error)")
        }
        let recordedInvocations = await recorder.recordedInvocations()
        XCTAssertEqual(recordedInvocations.count, 1)
    }

    func testNFCIDsLookupAndNavigationAreSortedAndSafeBeforeFirst() async throws {
        let decomposedPath = "cafe\u{301}"
        let composedPath = "caf\u{E9}"
        let left = FolderSnapshot(entries: [
            folderEntry("a", size: 2),
            folderEntry(decomposedPath, size: 2),
            folderEntry("z", size: 2)
        ])
        let middle = FolderSnapshot(entries: [
            folderEntry("a", size: 1),
            folderEntry(composedPath, size: 1),
            folderEntry("z", size: 1)
        ])
        let right = FolderSnapshot(entries: [
            folderEntry("a", size: 1),
            folderEntry(composedPath, size: 3),
            folderEntry("z", size: 3)
        ])

        let result = try await ThreeWayFolderComparison.compare(left: left, middle: middle, right: right)
        let a = ThreeWayFolderComparisonEntry.ID(rawValue: "a")
        let cafe = ThreeWayFolderComparisonEntry.ID(rawValue: decomposedPath)
        let z = ThreeWayFolderComparisonEntry.ID(rawValue: "z")

        XCTAssertEqual(cafe.rawValue, composedPath)
        XCTAssertEqual(result.entries.map(\.id), [a, cafe, z])
        XCTAssertEqual(result.changedEntryIDs, [a, cafe, z])
        XCTAssertEqual(result.conflictEntryIDs, [cafe, z])
        XCTAssertEqual(result.entry(withID: cafe)?.left?.relativePath, decomposedPath)
        XCTAssertEqual(
            result.entry(withID: ThreeWayFolderComparisonEntry.ID(rawValue: composedPath))?.id,
            cafe
        )
        XCTAssertNil(result.entry(withID: ThreeWayFolderComparisonEntry.ID(rawValue: "missing")))

        XCTAssertEqual(result.nextChangedEntryID(), a)
        XCTAssertEqual(result.nextChangedEntryID(after: a), cafe)
        XCTAssertEqual(result.nextChangedEntryID(after: ThreeWayFolderComparisonEntry.ID(rawValue: "b")), cafe)
        XCTAssertEqual(result.nextChangedEntryID(after: cafe), z)
        XCTAssertNil(result.nextChangedEntryID(after: z))
        XCTAssertEqual(result.previousChangedEntryID(), z)
        XCTAssertEqual(result.previousChangedEntryID(before: z), cafe)
        XCTAssertEqual(result.previousChangedEntryID(before: ThreeWayFolderComparisonEntry.ID(rawValue: "d")), cafe)
        XCTAssertNil(result.previousChangedEntryID(before: a))
        XCTAssertNil(result.previousChangedEntryID(before: ThreeWayFolderComparisonEntry.ID(rawValue: "0")))

        XCTAssertEqual(result.nextConflictEntryID(), cafe)
        XCTAssertEqual(result.nextConflictEntryID(after: cafe), z)
        XCTAssertNil(result.nextConflictEntryID(after: z))
        XCTAssertEqual(result.previousConflictEntryID(), z)
        XCTAssertNil(result.previousConflictEntryID(before: cafe))
        XCTAssertNil(result.previousConflictEntryID(before: ThreeWayFolderComparisonEntry.ID(rawValue: "0")))
    }

    func testValidationAndInputErrorsAreTypedAndDeterministic() async {
        await assertComparisonError(
            .invalidLimits,
            options: ThreeWayFolderComparisonOptions(maximumWorkUnits: -1)
        )

        for side in ThreeWayFolderComparisonSide.allCases {
            let snapshots = snapshots(entries: [folderEntry("file")], on: side)
            await assertComparisonError(
                .tooManyInputEntries(side: side, maximumEntries: 0),
                left: snapshots.left,
                middle: snapshots.middle,
                right: snapshots.right,
                options: ThreeWayFolderComparisonOptions(maximumEntriesPerSnapshot: 0)
            )
        }

        await assertComparisonError(
            .tooManyResultEntries(maximumEntries: 1),
            left: FolderSnapshot(entries: [folderEntry("a")]),
            middle: FolderSnapshot(entries: [folderEntry("b")]),
            options: ThreeWayFolderComparisonOptions(maximumResultEntries: 1)
        )
        await assertComparisonError(
            .relativePathTooLong(side: .right, relativePath: "é", maximumUTF8Bytes: 1),
            right: FolderSnapshot(entries: [folderEntry("é")]),
            options: ThreeWayFolderComparisonOptions(maximumRelativePathUTF8Bytes: 1)
        )

        let invalidPaths: [(String, FolderRelativePathError)] = [
            ("", .empty),
            (".", .empty),
            ("/absolute", .absolute),
            ("../child", .parentTraversal),
            ("child/../sibling", .parentTraversal),
            ("null\0byte", .containsNull)
        ]
        for (path, pathError) in invalidPaths {
            await assertComparisonError(
                .invalidRelativePath(side: .middle, relativePath: path, error: pathError),
                middle: FolderSnapshot(entries: [folderEntry(path)])
            )
        }

        let invalidEntries = [folderEntry("z/.."), folderEntry("/absolute")]
        for entries in [invalidEntries, Array(invalidEntries.reversed())] {
            await assertComparisonError(
                .invalidRelativePath(side: .left, relativePath: "/absolute", error: .absolute),
                left: FolderSnapshot(entries: entries)
            )
        }

        let firstCollision = [folderEntry("CAFÉ"), folderEntry("café"), folderEntry("cafe\u{301}")]
        let laterCollision = [folderEntry("Zulu"), folderEntry("zulu")]
        let collisionPermutations = allThreeWayPermutations(of: firstCollision).flatMap { permutation in
            [permutation + laterCollision, Array(laterCollision.reversed()) + permutation]
        }
        for side in ThreeWayFolderComparisonSide.allCases {
            for entries in collisionPermutations {
                let collisionSnapshots = snapshots(entries: entries, on: side)
                await assertComparisonError(
                    .duplicateNormalizedPath(side: side, normalizedRelativePath: "café", entryCount: 3),
                    left: collisionSnapshots.left,
                    middle: collisionSnapshots.middle,
                    right: collisionSnapshots.right,
                    options: ThreeWayFolderComparisonOptions(
                        comparison: FolderComparisonOptions(pathCaseSensitivity: .insensitive)
                    )
                )
            }
        }
    }

    func testDigestLimitAvailabilityAndCompatibilityErrorsAreExact() async {
        let contentRequired = FolderComparisonOptions(method: .contentRequired)
        await assertComparisonError(
            .digestTooLarge(side: .left, relativePath: "file", maximumBytes: 1),
            left: FolderSnapshot(entries: [folderEntry("file", digest: folderDigest([0x01, 0x02]))]),
            middle: FolderSnapshot(entries: [folderEntry("file", digest: folderDigest([0x01]))]),
            options: ThreeWayFolderComparisonOptions(
                comparison: contentRequired,
                maximumDigestBytes: 1
            )
        )
        await assertComparisonError(
            .digestAlgorithmTooLong(side: .left, relativePath: "file", maximumUTF8Bytes: 1),
            left: FolderSnapshot(entries: [folderEntry("file", digest: folderDigest([0x01], algorithm: "é"))]),
            middle: FolderSnapshot(entries: [folderEntry("file", digest: folderDigest([0x01]))]),
            options: ThreeWayFolderComparisonOptions(
                comparison: contentRequired,
                maximumDigestAlgorithmUTF8Bytes: 1
            )
        )
        await assertComparisonError(
            .contentDigestUnavailable(relativePath: "file", sides: [.left, .middle]),
            left: FolderSnapshot(entries: [folderEntry("file")]),
            middle: FolderSnapshot(entries: [folderEntry("file")]),
            right: FolderSnapshot(entries: [folderEntry("file")]),
            options: ThreeWayFolderComparisonOptions(comparison: contentRequired)
        )
        await assertComparisonError(
            .incompatibleContentDigests(
                relativePath: "file",
                firstSide: .left,
                firstAlgorithm: "sha256",
                secondSide: .middle,
                secondAlgorithm: "md5"
            ),
            left: FolderSnapshot(entries: [folderEntry("file", digest: folderDigest([0x01], algorithm: "sha256"))]),
            middle: FolderSnapshot(entries: [folderEntry("file", digest: folderDigest([0x01], algorithm: "md5"))]),
            right: FolderSnapshot(entries: [folderEntry("file", digest: folderDigest([0x01], algorithm: "md5"))]),
            options: ThreeWayFolderComparisonOptions(comparison: contentRequired)
        )
    }

    func testWorkLimitFixedBoundariesAreInputOrderIndependent() async throws {
        let emptyResult = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: []),
            middle: FolderSnapshot(entries: []),
            right: FolderSnapshot(entries: []),
            options: ThreeWayFolderComparisonOptions(maximumWorkUnits: 0)
        )
        XCTAssertTrue(emptyResult.entries.isEmpty)

        let oneEntry = FolderSnapshot(entries: [folderEntry("a")])
        await assertComparisonError(
            .workLimitExceeded(maximumWorkUnits: 17),
            left: oneEntry,
            options: ThreeWayFolderComparisonOptions(maximumWorkUnits: 17)
        )
        let oneEntryResult = try await ThreeWayFolderComparison.compare(
            left: oneEntry,
            middle: FolderSnapshot(entries: []),
            right: FolderSnapshot(entries: []),
            options: ThreeWayFolderComparisonOptions(maximumWorkUnits: 18)
        )
        XCTAssertEqual(oneEntryResult.entries.map(\.normalizedRelativePath), ["a"])

        let entries = [
            folderEntry("gamma", size: 3),
            folderEntry("alpha", size: 1),
            folderEntry("beta", size: 2)
        ]
        let permutations = allThreeWayPermutations(of: entries)
        let threshold = 209
        for permutation in permutations {
            await assertComparisonError(
                .workLimitExceeded(maximumWorkUnits: threshold - 1),
                left: FolderSnapshot(entries: permutation),
                options: ThreeWayFolderComparisonOptions(maximumWorkUnits: threshold - 1)
            )
            let result = try await ThreeWayFolderComparison.compare(
                left: FolderSnapshot(entries: permutation),
                middle: FolderSnapshot(entries: []),
                right: FolderSnapshot(entries: []),
                options: ThreeWayFolderComparisonOptions(maximumWorkUnits: threshold)
            )
            XCTAssertEqual(result.entries.map(\.normalizedRelativePath), ["alpha", "beta", "gamma"])
        }
    }

    func testSizeGuardSkipsProviderWhenOptionalAndRequiredModeCallsEverySideOnce() async throws {
        let optionalRecorder = ThreeWayDigestInvocationRecorder()
        let optionalProvider = ThreeWayFolderContentDigestProvider { side, entry in
            await optionalRecorder.record(side, entry: entry)
            return folderDigest([0x01])
        }
        let left = FolderSnapshot(entries: [folderEntry("file", size: 1)])
        let middle = FolderSnapshot(entries: [folderEntry("file", size: 2)])
        let right = FolderSnapshot(entries: [folderEntry("file", size: 3)])

        let optionalResult = try await ThreeWayFolderComparison.compare(
            left: left,
            middle: middle,
            right: right,
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(method: .contentIfAvailable)
            ),
            contentDigestProvider: optionalProvider
        )
        let optionalEntry = try XCTUnwrap(optionalResult.entries.first)
        XCTAssertEqual(optionalEntry.resolution, .conflict)
        XCTAssertEqual(optionalEntry.conflictKind, .contentDifference)
        XCTAssertEqual(optionalEntry.comparisons.leftAndMiddle.contentState, .different)
        XCTAssertEqual(optionalEntry.comparisons.rightAndMiddle.contentState, .different)
        XCTAssertEqual(optionalEntry.comparisons.leftAndRight.contentState, .different)
        let optionalInvocations = await optionalRecorder.recordedInvocations()
        XCTAssertTrue(optionalInvocations.isEmpty)

        let requiredRecorder = ThreeWayDigestInvocationRecorder()
        let requiredProvider = ThreeWayFolderContentDigestProvider { side, entry in
            await requiredRecorder.record(side, entry: entry)
            return folderDigest([0x01])
        }
        let requiredResult = try await ThreeWayFolderComparison.compare(
            left: left,
            middle: middle,
            right: right,
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(method: .contentRequired)
            ),
            contentDigestProvider: requiredProvider
        )
        let requiredEntry = try XCTUnwrap(requiredResult.entries.first)
        XCTAssertEqual(requiredEntry.resolution, .conflict)
        XCTAssertEqual(requiredEntry.comparisons.leftAndMiddle.contentState, .different)
        XCTAssertEqual(requiredEntry.comparisons.rightAndMiddle.contentState, .different)
        XCTAssertEqual(requiredEntry.comparisons.leftAndRight.contentState, .different)
        let requiredSides = await requiredRecorder.recordedSides()
        XCTAssertEqual(requiredSides.count, 3)
        XCTAssertEqual(Set(requiredSides), Set(ThreeWayFolderComparisonSide.allCases))
    }

    func testMixedKnownAndNilSizesRetainSecondPassSizeGuard() async throws {
        let recorder = ThreeWayDigestInvocationRecorder()
        let provider = ThreeWayFolderContentDigestProvider { side, entry in
            await recorder.record(side, entry: entry)
            return folderDigest([0x01])
        }
        let result = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: [folderEntry("file", size: 1)]),
            middle: FolderSnapshot(entries: [folderEntry("file", size: 2)]),
            right: FolderSnapshot(entries: [folderEntry("file")]),
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(method: .contentIfAvailable)
            ),
            contentDigestProvider: provider
        )

        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(entry.comparisons.leftAndMiddle.contentState, .different)
        XCTAssertEqual(entry.comparisons.rightAndMiddle.contentState, .equal)
        XCTAssertEqual(entry.comparisons.leftAndRight.contentState, .equal)
        XCTAssertEqual(entry.comparisons.leftAndMiddle.metadataDifferences, [.size])
        XCTAssertEqual(entry.comparisons.rightAndMiddle.metadataDifferences, [.size])
        XCTAssertEqual(entry.comparisons.leftAndRight.metadataDifferences, [.size])
        XCTAssertEqual(entry.resolution, .conflict)
        XCTAssertEqual(entry.conflictKind, .metadataDifference)
        let recordedSides = await recorder.recordedSides()
        XCTAssertEqual(recordedSides.count, 3)
        XCTAssertEqual(Set(recordedSides), Set(ThreeWayFolderComparisonSide.allCases))
    }

    func testNonTransitiveModificationDateToleranceUsesMiddleAsBaseline() async throws {
        let result = try await ThreeWayFolderComparison.compare(
            left: FolderSnapshot(entries: [
                folderEntry("left-change", size: 1, date: 0),
                folderEntry("unchanged-around-baseline", size: 1, date: 0)
            ]),
            middle: FolderSnapshot(entries: [
                folderEntry("left-change", size: 1, date: 2),
                folderEntry("unchanged-around-baseline", size: 1, date: 1)
            ]),
            right: FolderSnapshot(entries: [
                folderEntry("left-change", size: 1, date: 1),
                folderEntry("unchanged-around-baseline", size: 1, date: 2)
            ]),
            options: ThreeWayFolderComparisonOptions(
                comparison: FolderComparisonOptions(
                    method: .metadataOnly,
                    modificationDateTolerance: 1
                )
            )
        )
        let entries = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.normalizedRelativePath, $0) })
        let unchanged = try XCTUnwrap(entries["unchanged-around-baseline"])
        let leftChange = try XCTUnwrap(entries["left-change"])

        XCTAssertTrue(unchanged.equality.leftEqualsMiddle)
        XCTAssertTrue(unchanged.equality.rightEqualsMiddle)
        XCTAssertFalse(unchanged.equality.leftEqualsRight)
        XCTAssertEqual(unchanged.resolution, .unchanged)
        XCTAssertEqual(unchanged.comparisons.leftAndRight.metadataDifferences, [.modificationDate])

        XCTAssertFalse(leftChange.equality.leftEqualsMiddle)
        XCTAssertTrue(leftChange.equality.rightEqualsMiddle)
        XCTAssertTrue(leftChange.equality.leftEqualsRight)
        XCTAssertEqual(leftChange.resolution, .left)
        XCTAssertEqual(result.summary.unchangedEntryCount, 1)
        XCTAssertEqual(result.summary.leftChangeEntryCount, 1)
        XCTAssertEqual(result.summary.metadataDifferenceEntryCount, 2)
    }

    private func assertComparisonError(
        _ expected: ThreeWayFolderComparisonError,
        left: FolderSnapshot = FolderSnapshot(entries: []),
        middle: FolderSnapshot = FolderSnapshot(entries: []),
        right: FolderSnapshot = FolderSnapshot(entries: []),
        options: ThreeWayFolderComparisonOptions = .default,
        contentDigestProvider: ThreeWayFolderContentDigestProvider? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await ThreeWayFolderComparison.compare(
                left: left,
                middle: middle,
                right: right,
                options: options,
                contentDigestProvider: contentDigestProvider
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ThreeWayFolderComparisonError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private func folderEntry(
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

private func folderDigest(
    _ bytes: [UInt8],
    algorithm: String = "sha256"
) -> FolderContentDigest {
    FolderContentDigest(algorithm: algorithm, bytes: Data(bytes))
}

private func snapshots(
    entries: [FolderEntry],
    on side: ThreeWayFolderComparisonSide
) -> (left: FolderSnapshot, middle: FolderSnapshot, right: FolderSnapshot) {
    let empty = FolderSnapshot(entries: [])
    let populated = FolderSnapshot(entries: entries)
    switch side {
    case .left:
        return (populated, empty, empty)
    case .middle:
        return (empty, populated, empty)
    case .right:
        return (empty, empty, populated)
    }
}

private func allThreeWayPermutations<Element>(of values: [Element]) -> [[Element]] {
    guard !values.isEmpty else { return [[]] }
    return values.indices.flatMap { index in
        var remainder = values
        let value = remainder.remove(at: index)
        return allThreeWayPermutations(of: remainder).map { [value] + $0 }
    }
}

private struct ThreeWayDigestInvocation: Equatable, Sendable {
    let side: ThreeWayFolderComparisonSide
    let entry: FolderEntry
}

private actor ThreeWayDigestInvocationRecorder {
    private var invocations: [ThreeWayDigestInvocation] = []

    func record(_ side: ThreeWayFolderComparisonSide, entry: FolderEntry) {
        invocations.append(ThreeWayDigestInvocation(side: side, entry: entry))
    }

    func recordedInvocations() -> [ThreeWayDigestInvocation] {
        invocations
    }

    func recordedSides() -> [ThreeWayFolderComparisonSide] {
        invocations.map(\.side)
    }
}

private actor ThreeWayDigestConcurrencyRecorder {
    private var concurrentInvocations = 0
    private var maximumConcurrentInvocations = 0
    private var invocations: [ThreeWayDigestInvocation] = []

    func begin(_ side: ThreeWayFolderComparisonSide, entry: FolderEntry) {
        concurrentInvocations += 1
        maximumConcurrentInvocations = max(maximumConcurrentInvocations, concurrentInvocations)
        invocations.append(ThreeWayDigestInvocation(side: side, entry: entry))
    }

    func end() {
        concurrentInvocations -= 1
    }

    func snapshot() -> (
        maximumConcurrentInvocations: Int,
        invocations: [ThreeWayDigestInvocation]
    ) {
        (maximumConcurrentInvocations, invocations)
    }
}

private struct ThreeWayDigestProviderFixtureError: Error, CustomNSError, Sendable {
    static let errorDomain = "ThreeWayFolderComparisonTests.DigestProvider"

    let side: ThreeWayFolderComparisonSide

    var errorCode: Int {
        switch side {
        case .left: 41
        case .middle: 42
        case .right: 43
        }
    }

    var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: "digest failed on \(side.rawValue)"]
    }
}
