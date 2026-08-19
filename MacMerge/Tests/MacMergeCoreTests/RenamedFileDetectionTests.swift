import Foundation
import XCTest
@testable import MacMergeCore

final class RenamedFileDetectionTests: XCTestCase {
    func testMatchesOnlyExactTrustedDigestAndSize() throws {
        let sharedDigest = digest(0x11)
        let matchingLeft = candidate("old/name.txt", size: 10, digest: sharedDigest)
        let wrongSize = candidate("old/size.txt", size: 11, digest: sharedDigest)
        let wrongDigest = candidate("old/digest.txt", size: 10, digest: digest(0x22))
        let matchingRight = candidate("new/name.txt", size: 10, digest: sharedDigest)

        let result = try RenamedFileDetection.detect(
            unmatchedLeft: [wrongSize, matchingLeft, wrongDigest],
            unmatchedRight: [matchingRight]
        )

        XCTAssertEqual(result.matches.map(\.left), [matchingLeft])
        XCTAssertEqual(result.matches.map(\.right), [matchingRight])
        XCTAssertEqual(result.unmatchedLeft, [wrongDigest, wrongSize])
        XCTAssertTrue(result.unmatchedRight.isEmpty)
    }

    func testInvalidAndUntrustedDigestsRemainUnmatched() throws {
        let left = [
            candidate("left/missing", digest: nil),
            candidate("left/untrusted", digest: digest(0x33, algorithm: "md5", count: 16)),
            candidate("left/invalid", digest: digest(0x44, count: 31)),
        ]
        let right = [
            candidate("right/missing", digest: nil),
            candidate("right/untrusted", digest: digest(0x33, algorithm: "md5", count: 16)),
            candidate("right/invalid", digest: digest(0x44, count: 31)),
        ]

        let result = try RenamedFileDetection.detect(
            unmatchedLeft: Array(left.reversed()),
            unmatchedRight: Array(right.reversed())
        )

        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertEqual(result.unmatchedLeft.map(\.relativePath), [
            "left/invalid", "left/missing", "left/untrusted",
        ])
        XCTAssertEqual(result.unmatchedRight.map(\.relativePath), [
            "right/invalid", "right/missing", "right/untrusted",
        ])
    }

    func testAcceptedDigestLabelsAndExactLengthsMatchContract() throws {
        let accepted: [(String, Int)] = [
            ("sha256", 32), (" SHA-256 ", 32),
            ("sha384", 48), ("SHA-384", 48),
            ("sha512", 64), ("SHA-512", 64),
            ("blake3", 32),
        ]
        for (index, fixture) in accepted.enumerated() {
            let shared = digest(UInt8(index), algorithm: fixture.0, count: fixture.1)
            let result = try RenamedFileDetection.detect(
                unmatchedLeft: [candidate("left-\(index)", digest: shared)],
                unmatchedRight: [candidate("right-\(index)", digest: shared)]
            )
            XCTAssertEqual(result.matches.count, 1, fixture.0)
        }

        let rejected: [(String, Int)] = [
            ("sha224", 28), ("sha-224", 28),
            ("sha512/224", 28), ("sha512/256", 32),
            ("sha--256", 32), ("sha-512", 32),
            ("blake3", 64),
        ]
        for (index, fixture) in rejected.enumerated() {
            let shared = digest(UInt8(index), algorithm: fixture.0, count: fixture.1)
            let result = try RenamedFileDetection.detect(
                unmatchedLeft: [candidate("left-\(index)", digest: shared)],
                unmatchedRight: [candidate("right-\(index)", digest: shared)]
            )
            XCTAssertTrue(result.matches.isEmpty, fixture.0)
        }

        let oversizedLabel = String(repeating: "s", count: 65)
        let oversizedDigest = digest(0xFF, algorithm: oversizedLabel, count: 32)
        XCTAssertTrue(try RenamedFileDetection.detect(
            unmatchedLeft: [candidate("left-oversized", digest: oversizedDigest)],
            unmatchedRight: [candidate("right-oversized", digest: oversizedDigest)]
        ).matches.isEmpty)
    }

    func testDigestAliasesCanonicalizeAcrossSides() throws {
        let aliases = [
            (" SHA-256 ", "sha256", 32),
            ("SHA384", "sha-384", 48),
            ("sha-512", " SHA512\n", 64),
            ("BLAKE3", "blake3", 32),
        ]

        for (index, alias) in aliases.enumerated() {
            let byte = UInt8(index + 1)
            let result = try RenamedFileDetection.detect(
                unmatchedLeft: [
                    candidate(
                        "left-\(index)",
                        digest: digest(byte, algorithm: alias.0, count: alias.2)
                    )
                ],
                unmatchedRight: [
                    candidate(
                        "right-\(index)",
                        digest: digest(byte, algorithm: alias.1, count: alias.2)
                    )
                ]
            )
            XCTAssertEqual(result.matches.count, 1, "\(alias.0) -> \(alias.1)")
        }
    }

    func testDuplicateContentAssignmentIsIndependentOfInputOrder() throws {
        let sharedDigest = digest(0x55)
        let left = [candidate("a", digest: sharedDigest), candidate("b", digest: sharedDigest)]
        let right = [candidate("x", digest: sharedDigest), candidate("y", digest: sharedDigest)]

        let forward = try RenamedFileDetection.detect(
            unmatchedLeft: left,
            unmatchedRight: right
        )
        let reversed = try RenamedFileDetection.detect(
            unmatchedLeft: Array(left.reversed()),
            unmatchedRight: Array(right.reversed())
        )

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.matches.map {
            "\($0.left.relativePath)->\($0.right.relativePath)"
        }, ["a->x", "b->y"])
        XCTAssertEqual(forward.matches.map(\.pathSimilarityCost), [1, 1])
    }

    func testTiedDuplicateAssignmentIsSymmetricWhenSidesSwap() throws {
        let sharedDigest = digest(0x56)
        let left = [candidate("a", digest: sharedDigest), candidate("b", digest: sharedDigest)]
        let right = [candidate("cc", digest: sharedDigest), candidate("d", digest: sharedDigest)]

        let forward = try RenamedFileDetection.detect(
            unmatchedLeft: left,
            unmatchedRight: right
        )
        let swapped = try RenamedFileDetection.detect(
            unmatchedLeft: right,
            unmatchedRight: left
        )

        let forwardPairs = forward.matches.map {
            "\($0.left.relativePath)->\($0.right.relativePath)"
        }.sorted()
        let inverseSwappedPairs = swapped.matches.map {
            "\($0.right.relativePath)->\($0.left.relativePath)"
        }.sorted()
        XCTAssertEqual(forwardPairs, ["a->d", "b->cc"])
        XCTAssertEqual(inverseSwappedPairs, forwardPairs)
        XCTAssertEqual(
            forward.matches.reduce(0) { $0 + $1.pathSimilarityCost },
            swapped.matches.reduce(0) { $0 + $1.pathSimilarityCost }
        )
    }

    func testDetectedDistinctRenamePathsConstructStableDistinctDirectoryResultIDs() throws {
        let left = [
            candidate("old/first.txt", digest: digest(0x61)),
            candidate("old/second.txt", digest: digest(0x62)),
        ]
        let right = [
            candidate("new/first.txt", digest: digest(0x61)),
            candidate("new/second.txt", digest: digest(0x62)),
        ]
        let detection = try RenamedFileDetection.detect(
            unmatchedLeft: left,
            unmatchedRight: right
        )

        let results = detection.matches.map { match in
            DirectoryResult(
                left: metadata(match.left.relativePath),
                right: metadata(match.right.relativePath),
                status: .identical
            )
        }
        let rebuiltIDs = detection.matches.map { match in
            DirectoryResult(
                left: metadata(match.left.relativePath),
                right: metadata(match.right.relativePath),
                status: .identical
            ).id
        }

        XCTAssertEqual(results.map(\.id), rebuiltIDs)
        XCTAssertEqual(Set(results.map(\.id)).count, 2)
        XCTAssertEqual(
            results.map(\.id),
            [
                DirectoryResult.ID(
                    leftRelativePath: "old/first.txt",
                    rightRelativePath: "new/first.txt"
                ),
                DirectoryResult.ID(
                    leftRelativePath: "old/second.txt",
                    rightRelativePath: "new/second.txt"
                ),
            ]
        )
    }

    func testRejectsDuplicateNormalizedAndInvalidPaths() {
        let sharedDigest = digest(0x66)

        XCTAssertThrowsError(try RenamedFileDetection.detect(
            unmatchedLeft: [
                candidate("Folder//./cafe\u{301}.txt", digest: sharedDigest),
                candidate("folder/café.txt", digest: sharedDigest),
            ],
            unmatchedRight: [],
            options: RenamedFileDetectionOptions(pathCaseSensitivity: .insensitive)
        )) { error in
            XCTAssertEqual(
                error as? RenamedFileDetectionError,
                .duplicateNormalizedPath(side: .left, normalizedPath: "folder/café.txt")
            )
        }

        XCTAssertThrowsError(try RenamedFileDetection.detect(
            unmatchedLeft: [],
            unmatchedRight: [candidate("../escape", digest: sharedDigest)]
        )) { error in
            XCTAssertEqual(
                error as? RenamedFileDetectionError,
                .invalidRelativePath(side: .right, path: "../escape", error: .parentTraversal)
            )
        }
    }

    func testWorkLimitsAcceptExactBoundsAndRejectSmallerBounds() throws {
        let sharedDigest = digest(0x77)
        let left = [candidate("a", digest: sharedDigest), candidate("b", digest: sharedDigest)]
        let right = [candidate("x", digest: sharedDigest), candidate("y", digest: sharedDigest)]
        let exactLimits = RenamedFileDetectionOptions(
            maximumCostMatrixCells: 4,
            maximumPathCharacterComparisons: 4
        )

        let result = try RenamedFileDetection.detect(
            unmatchedLeft: left,
            unmatchedRight: right,
            options: exactLimits
        )
        XCTAssertEqual(result.matches.count, 2)

        let tooSmallLimits = [
            RenamedFileDetectionOptions(
                maximumCostMatrixCells: 3,
                maximumPathCharacterComparisons: 4
            ),
            RenamedFileDetectionOptions(
                maximumCostMatrixCells: 4,
                maximumPathCharacterComparisons: 3
            ),
        ]
        for options in tooSmallLimits {
            XCTAssertThrowsError(try RenamedFileDetection.detect(
                unmatchedLeft: left,
                unmatchedRight: right,
                options: options
            )) { error in
                XCTAssertEqual(error as? RenamedFileDetectionError, .workLimitExceeded)
            }
        }
    }

    func testWorkLimitsAreAggregatedAcrossDigestBuckets() throws {
        let left = (0..<8).map { index in
            candidate("l\(index)", digest: digest(UInt8(0x90 + index)))
        }
        let right = (0..<8).map { index in
            candidate("r\(index)", digest: digest(UInt8(0x90 + index)))
        }
        let exactLimits = RenamedFileDetectionOptions(
            maximumCostMatrixCells: 8,
            maximumPathCharacterComparisons: 32,
            maximumAssignmentOperations: 8
        )

        let result = try RenamedFileDetection.detect(
            unmatchedLeft: left,
            unmatchedRight: right,
            options: exactLimits
        )
        XCTAssertEqual(result.matches.count, 8)

        let tooSmallLimits = [
            RenamedFileDetectionOptions(
                maximumCostMatrixCells: 7,
                maximumPathCharacterComparisons: 32,
                maximumAssignmentOperations: 8
            ),
            RenamedFileDetectionOptions(
                maximumCostMatrixCells: 8,
                maximumPathCharacterComparisons: 31,
                maximumAssignmentOperations: 8
            ),
            RenamedFileDetectionOptions(
                maximumCostMatrixCells: 8,
                maximumPathCharacterComparisons: 32,
                maximumAssignmentOperations: 7
            ),
        ]
        for options in tooSmallLimits {
            XCTAssertThrowsError(try RenamedFileDetection.detect(
                unmatchedLeft: left,
                unmatchedRight: right,
                options: options
            )) { error in
                XCTAssertEqual(error as? RenamedFileDetectionError, .workLimitExceeded)
            }
        }
    }

    func testPathScalarAndUTF8LimitsRejectSingleGiantCharacter() throws {
        let giantCharacter = "a" + String(repeating: "\u{301}", count: 64)
        XCTAssertEqual(giantCharacter.count, 1)

        XCTAssertThrowsError(try RenamedFileDetection.detect(
            unmatchedLeft: [candidate(giantCharacter, digest: digest(0x87))],
            unmatchedRight: [],
            options: RenamedFileDetectionOptions(
                maximumNormalizedPathScalars: 64,
                maximumNormalizedPathUTF8Bytes: 1_000
            )
        )) { error in
            XCTAssertEqual(error as? RenamedFileDetectionError, .workLimitExceeded)
        }

        XCTAssertThrowsError(try RenamedFileDetection.detect(
            unmatchedLeft: [candidate("😀", digest: digest(0x87))],
            unmatchedRight: [],
            options: RenamedFileDetectionOptions(
                maximumNormalizedPathScalars: 1,
                maximumNormalizedPathUTF8Bytes: 3
            )
        )) { error in
            XCTAssertEqual(error as? RenamedFileDetectionError, .workLimitExceeded)
        }
    }

    func testPathScalarAndEmojiUTF8ExactBoundsAreAccepted() throws {
        let options = RenamedFileDetectionOptions(
            maximumNormalizedPathScalars: 1,
            maximumNormalizedPathUTF8Bytes: 4
        )
        let result = try RenamedFileDetection.detect(
            unmatchedLeft: [candidate("😀", digest: digest(0x87))],
            unmatchedRight: [],
            options: options
        )

        XCTAssertEqual(result.unmatchedLeft.map(\.relativePath), ["😀"])
    }

    func testCancellationAtDigestUnionAndProjectionCheckpoints() async {
        for checkpoint in [
            RenamedFileDetection.Checkpoint.candidatePreparation,
            .candidateBucketing,
            RenamedFileDetection.Checkpoint.digestKeyUnion,
            .costMatrix,
            .assignment,
            .oneSidedProjection,
            .resultOrdering,
        ] {
            let task = Task {
                try RenamedFileDetection.$checkpointObserver.withValue(
                    { observed in
                        if observed == checkpoint {
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                    },
                    operation: {
                        try RenamedFileDetection.detect(
                            unmatchedLeft: [candidate("left", digest: digest(0x88))],
                            unmatchedRight: [candidate("right", digest: digest(0x88))]
                        )
                    }
                )
            }

            do {
                _ = try await task.value
                XCTFail("Expected cancellation at \(checkpoint)")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error at \(checkpoint): \(error)")
            }
        }
    }

    func testCancellationBeforeWorkIsPropagated() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try RenamedFileDetection.detect(
                unmatchedLeft: [candidate("left", digest: digest(0x88))],
                unmatchedRight: []
            )
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationInterruptsSub1024Assignment() async {
        let count = 9
        let sharedDigest = digest(0x89)
        let left = (0..<count).map {
            candidate(privateUsePath(offset: $0), digest: sharedDigest)
        }
        let right = (0..<count).map {
            candidate(privateUsePath(offset: count + $0), digest: sharedDigest)
        }
        let assignmentGate = AssignmentPhaseGate(
            started: expectation(description: "Assignment started")
        )
        let task = Task.detached {
            try RenamedFileDetection.$assignmentObserver.withValue(
                { assignmentGate.observe($0) },
                operation: {
                    try RenamedFileDetection.detect(
                        unmatchedLeft: left,
                        unmatchedRight: right,
                        options: RenamedFileDetectionOptions(
                            maximumCostMatrixCells: count * count,
                            maximumPathCharacterComparisons: count * count,
                            maximumAssignmentOperations: count * count * count
                        )
                    )
                }
            )
        }
        defer {
            task.cancel()
            assignmentGate.release()
        }

        await fulfillment(of: [assignmentGate.started], timeout: 2)
        task.cancel()
        assignmentGate.release()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation during assignment")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(assignmentGate.didComplete)
    }

    func testAssignmentWorkLimitAcceptsExactBoundAndRejectsOneLess() throws {
        let sharedDigest = digest(0x8A)
        let left = [candidate("a", digest: sharedDigest), candidate("b", digest: sharedDigest)]
        let right = [candidate("x", digest: sharedDigest), candidate("y", digest: sharedDigest)]

        XCTAssertEqual(
            try RenamedFileDetection.detect(
                unmatchedLeft: left,
                unmatchedRight: right,
                options: RenamedFileDetectionOptions(
                    maximumCostMatrixCells: 4,
                    maximumPathCharacterComparisons: 4,
                    maximumAssignmentOperations: 8
                )
            ).matches.count,
            2
        )

        XCTAssertThrowsError(
            try RenamedFileDetection.detect(
                unmatchedLeft: left,
                unmatchedRight: right,
                options: RenamedFileDetectionOptions(
                    maximumCostMatrixCells: 4,
                    maximumPathCharacterComparisons: 4,
                    maximumAssignmentOperations: 7
                )
            )
        ) { error in
            XCTAssertEqual(error as? RenamedFileDetectionError, .workLimitExceeded)
        }
    }
}

private func candidate(
    _ relativePath: String,
    size: UInt64 = 1,
    digest: FolderContentDigest?
) -> RenamedFileCandidate {
    RenamedFileCandidate(
        relativePath: relativePath,
        size: size,
        contentDigest: digest
    )
}

private func digest(
    _ byte: UInt8,
    algorithm: String = "sha256",
    count: Int = 32
) -> FolderContentDigest {
    FolderContentDigest(
        algorithm: algorithm,
        bytes: Data(repeating: byte, count: count)
    )
}

private func metadata(_ relativePath: String) -> DirectoryEntryMetadata {
    DirectoryEntryMetadata(relativePath: relativePath, kind: .file)
}

private func privateUsePath(offset: Int) -> String {
    String(UnicodeScalar(0xE000 + offset)!)
}

private final class AssignmentPhaseGate: @unchecked Sendable {
    let started: XCTestExpectation
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var completed = false

    init(started: XCTestExpectation) {
        self.started = started
    }

    var didComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func observe(_ checkpoint: RenamedFileDetection.AssignmentCheckpoint) {
        switch checkpoint {
        case .performedFirstOperation:
            started.fulfill()
            _ = releaseSemaphore.wait(timeout: .now() + .seconds(5))
        case .completed:
            lock.lock()
            completed = true
            lock.unlock()
        }
    }

    func release() {
        releaseSemaphore.signal()
    }
}
