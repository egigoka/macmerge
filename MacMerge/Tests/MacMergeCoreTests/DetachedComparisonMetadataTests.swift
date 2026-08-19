import MacMergeCore
import XCTest

private struct CompactDetachedMetadata: Equatable, Sendable {
    let differenceRowIndices: [UInt32]
    let movedLineStorageBytes: Int
}

private struct DetachedComparisonSnapshot: Equatable, Sendable {
    let compareResult: LineDiffResult
    let summary: DiffSummary
    let rowIDs: [DiffRow.ID]
    let leftToRightMovedPairs: [MovedLinePair]
    let rightToLeftMovedPairs: [MovedLinePair]
    let compactMetadata: CompactDetachedMetadata
}

private actor DetachedComparisonStartGate {
    struct Evidence: Sendable {
        let arrivalCount: Int
        let maximumActiveCount: Int
        let activeCount: Int
    }

    private let participantCount: Int
    private var arrivalCount = 0
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func enter() async {
        arrivalCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)

        if arrivalCount == participantCount {
            let waitingTasks = waiters
            waiters.removeAll()
            for waiter in waitingTasks {
                waiter.resume()
            }
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func leave() {
        activeCount -= 1
    }

    func evidence() -> Evidence {
        Evidence(
            arrivalCount: arrivalCount,
            maximumActiveCount: maximumActiveCount,
            activeCount: activeCount
        )
    }
}

private enum DetachedComparisonFixture: Sendable {
    case moved
    case ordinary

    func inputs(token: String, unchangedPrefixCount: Int) -> (left: String, right: String) {
        let bodies: (left: String, right: String) = switch self {
        case .moved:
            (
                "scope:\(token)\nduplicate\nunique moved seed\nduplicate\nstable one\nstable two\nstable three\ntail",
                "scope:\(token)\nstable one\nstable two\nstable three\nduplicate\nunique moved seed\nduplicate\ntail"
            )
        case .ordinary:
            (
                "scope:\(token)\ncenter\nsouth",
                "scope:\(token)\nCENTER\nsouth\nextra"
            )
        }

        let prefix = (0..<unchangedPrefixCount)
            .map { "metadata:\(token):\($0)" }
            .joined(separator: "\n")
        guard !prefix.isEmpty else {
            return bodies
        }
        return ("\(prefix)\n\(bodies.left)", "\(prefix)\n\(bodies.right)")
    }
}

private enum DetachedComparisonMetadataError: Error, Sendable {
    case nondeterministic
}

@MainActor
final class DetachedComparisonMetadataTests: XCTestCase {
    func testConcurrentDetachedComparisonsKeepMetadataDeterministicAndIsolated() async throws {
        let taskCount = 32
        let startGate = DetachedComparisonStartGate(participantCount: taskCount)
        let snapshots = try await withThrowingTaskGroup(
            of: (Int, DetachedComparisonSnapshot).self,
            returning: [DetachedComparisonSnapshot].self
        ) { group in
            for index in 0..<taskCount {
                let fixture: DetachedComparisonFixture = index.isMultiple(of: 2) ? .moved : .ordinary
                let token = "detached-\(index)"
                let operation: @Sendable () async throws -> (Int, DetachedComparisonSnapshot) = {
                    await startGate.enter()
                    do {
                        let baseline = try Self.snapshot(
                            fixture: fixture,
                            token: token,
                            unchangedPrefixCount: index
                        )
                        for _ in 1..<8 {
                            guard try Self.snapshot(
                                fixture: fixture,
                                token: token,
                                unchangedPrefixCount: index
                            ) == baseline else {
                                throw DetachedComparisonMetadataError.nondeterministic
                            }
                        }
                        await startGate.leave()
                        return (index, baseline)
                    } catch {
                        await startGate.leave()
                        throw error
                    }
                }
                group.addTask {
                    try await Task.detached(operation: operation).value
                }
            }

            var indexedSnapshots: [(Int, DetachedComparisonSnapshot)] = []
            indexedSnapshots.reserveCapacity(taskCount)
            for try await snapshot in group {
                indexedSnapshots.append(snapshot)
            }
            return indexedSnapshots.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let overlapEvidence = await startGate.evidence()
        XCTAssertEqual(overlapEvidence.arrivalCount, taskCount)
        XCTAssertEqual(overlapEvidence.maximumActiveCount, taskCount)
        XCTAssertEqual(overlapEvidence.activeCount, 0)

        for (index, snapshot) in snapshots.enumerated() {
            let token = "detached-\(index)"
            let scopedTexts = Set(
                snapshot.compareResult.rows
                    .flatMap { [$0.left?.text, $0.right?.text] }
                    .compactMap { $0 }
                    .filter { $0.hasPrefix("scope:") }
            )
            XCTAssertEqual(scopedTexts, ["scope:\(token)"], "task \(index) read another task's input")
            XCTAssertEqual(snapshot.compareResult.rows.map(\.id), snapshot.rowIDs)
            XCTAssertEqual(snapshot.summary, DiffSummary(rows: snapshot.compareResult.rows))

            if index.isMultiple(of: 2) {
                assertMovedFixture(snapshot, taskIndex: index)
            } else {
                assertOrdinaryFixture(snapshot, taskIndex: index)
            }
        }
    }

    private nonisolated static func snapshot(
        fixture: DetachedComparisonFixture,
        token: String,
        unchangedPrefixCount: Int
    ) throws -> DetachedComparisonSnapshot {
        let inputs = fixture.inputs(token: token, unchangedPrefixCount: unchangedPrefixCount)
        let compareResult = try LineDiff.compareResult(
            left: inputs.left,
            right: inputs.right,
            options: LineDiffOptions(detectMovedBlocks: true)
        )
        let rows = compareResult.rows
        let movedLines = compareResult.movedLines
        let differenceRowIndices = rows.indices.compactMap { index -> UInt32? in
            rows[index].kind == .unchanged ? nil : UInt32(exactly: index)
        }

        return DetachedComparisonSnapshot(
            compareResult: compareResult,
            summary: DiffSummary(rows: rows),
            rowIDs: rows.map(\.id),
            leftToRightMovedPairs: (0..<movedLines.leftToRightCount).map {
                movedLines.leftToRightPair(at: $0)
            },
            rightToLeftMovedPairs: (0..<movedLines.rightToLeftCount).map {
                movedLines.rightToLeftPair(at: $0)
            },
            compactMetadata: CompactDetachedMetadata(
                differenceRowIndices: differenceRowIndices,
                movedLineStorageBytes: movedLines.shallowStorageBytes
            )
        )
    }

    private func assertMovedFixture(
        _ snapshot: DetachedComparisonSnapshot,
        taskIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let prefixIDs = (0..<taskIndex).map { id($0 + 1, $0 + 1) }
        XCTAssertEqual(
            snapshot.rowIDs,
            prefixIDs + [
                id(taskIndex + 1, taskIndex + 1),
                id(taskIndex + 2, nil),
                id(taskIndex + 3, nil),
                id(taskIndex + 4, nil),
                id(taskIndex + 5, taskIndex + 2),
                id(taskIndex + 6, taskIndex + 3),
                id(taskIndex + 7, taskIndex + 4),
                id(nil, taskIndex + 5),
                id(nil, taskIndex + 6),
                id(nil, taskIndex + 7),
                id(taskIndex + 8, taskIndex + 8)
            ],
            "task \(taskIndex)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.compareResult.rows.map(\.kind),
            Array(repeating: DiffKind.unchanged, count: taskIndex) + [
                .unchanged, .removed, .removed, .removed, .unchanged, .unchanged,
                .unchanged, .added, .added, .added, .unchanged
            ],
            "task \(taskIndex)",
            file: file,
            line: line
        )
        assertSummary(
            snapshot.summary,
            unchanged: taskIndex + 5,
            modified: 0,
            removed: 3,
            added: 3,
            taskIndex: taskIndex,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.leftToRightMovedPairs.map(\.leftLine),
            [taskIndex + 2, taskIndex + 3, taskIndex + 4],
            "task \(taskIndex)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.leftToRightMovedPairs.map(\.rightLine),
            [taskIndex + 5, taskIndex + 6, taskIndex + 7],
            "task \(taskIndex)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.rightToLeftMovedPairs,
            snapshot.leftToRightMovedPairs,
            "task \(taskIndex)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.compactMetadata,
            CompactDetachedMetadata(
                differenceRowIndices: [1, 2, 3, 7, 8, 9].map { UInt32(taskIndex) + $0 },
                movedLineStorageBytes: 48
            ),
            "task \(taskIndex)",
            file: file,
            line: line
        )
    }

    private func assertOrdinaryFixture(
        _ snapshot: DetachedComparisonSnapshot,
        taskIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let prefixIDs = (0..<taskIndex).map { id($0 + 1, $0 + 1) }
        XCTAssertEqual(
            snapshot.rowIDs,
            prefixIDs + [
                id(taskIndex + 1, taskIndex + 1),
                id(taskIndex + 2, taskIndex + 2),
                id(taskIndex + 3, taskIndex + 3),
                id(nil, taskIndex + 4)
            ],
            "task \(taskIndex)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.compareResult.rows.map(\.kind),
            Array(repeating: DiffKind.unchanged, count: taskIndex)
                + [.unchanged, .modified, .unchanged, .added],
            "task \(taskIndex)",
            file: file,
            line: line
        )
        assertSummary(
            snapshot.summary,
            unchanged: taskIndex + 2,
            modified: 1,
            removed: 0,
            added: 1,
            taskIndex: taskIndex,
            file: file,
            line: line
        )
        XCTAssertTrue(snapshot.leftToRightMovedPairs.isEmpty, "task \(taskIndex)", file: file, line: line)
        XCTAssertTrue(snapshot.rightToLeftMovedPairs.isEmpty, "task \(taskIndex)", file: file, line: line)
        XCTAssertEqual(
            snapshot.compactMetadata,
            CompactDetachedMetadata(
                differenceRowIndices: [1, 3].map { UInt32(taskIndex) + $0 },
                movedLineStorageBytes: 0
            ),
            "task \(taskIndex)",
            file: file,
            line: line
        )
    }

    private func id(_ left: Int?, _ right: Int?) -> DiffRow.ID {
        DiffRow.ID(leftNumber: left, rightNumber: right)
    }

    private func assertSummary(
        _ summary: DiffSummary,
        unchanged: Int,
        modified: Int,
        removed: Int,
        added: Int,
        taskIndex: Int,
        file: StaticString,
        line: UInt
    ) {
        let context = "task \(taskIndex)"
        XCTAssertEqual(summary.unchanged, unchanged, context, file: file, line: line)
        XCTAssertEqual(summary.modified, modified, context, file: file, line: line)
        XCTAssertEqual(summary.removed, removed, context, file: file, line: line)
        XCTAssertEqual(summary.added, added, context, file: file, line: line)
        XCTAssertEqual(summary.differences, modified + removed + added, context, file: file, line: line)
    }
}
