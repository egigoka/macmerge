import Foundation
import MacMergeCore
import Testing

private final class CallsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

struct IntraLineWiringTests {
    private typealias Wiring = IntraLineWiring
    private typealias WorkflowError = IntraLineDifferenceWorkflowError

    private func diff(
        _ b0: Int,
        _ e0: Int,
        _ b1: Int,
        _ e1: Int,
        paneCount: Int = 2
    ) -> WinMergeStringDiffs.Difference {
        WinMergeStringDiffs.Difference(
            begin: [b0, b1, 0],
            end: [e0, e1, 0],
            operation: nil,
            paneCount: paneCount
        )
    }

    private func assertInconsistentPlan(
        differences: [WinMergeStringDiffs.Difference],
        source: String?,
        comparison: String?
    ) {
        do {
            _ = try Wiring.rangePairs(
                differences: differences,
                source: source,
                comparison: comparison,
                expectedGeneration: 7,
                actualGeneration: 7
            )
            Issue.record("expected inconsistentPlan")
        } catch let error as WorkflowError {
            #expect(error == .inconsistentPlan)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func validMapping() throws {
        let pairs = try Wiring.rangePairs(
            differences: [
                diff(1, 1, 1, 1),
                diff(5, 4, 5, 5),
            ],
            source: "hello",
            comparison: "hallo!",
            expectedGeneration: 3,
            actualGeneration: 3
        )
        #expect(pairs.count == 2)
        #expect(pairs[0].ordinal == 0)
        #expect(pairs[0].kind == .replace)
        #expect(pairs[0].sourceUTF16Range == NSRange(location: 1, length: 1))
        #expect(pairs[0].comparisonUTF16Range == NSRange(location: 1, length: 1))
        #expect(pairs[1].ordinal == 1)
        #expect(pairs[1].kind == .insert)
        #expect(pairs[1].sourceUTF16Range == NSRange(location: 5, length: 0))
        #expect(pairs[1].comparisonUTF16Range == NSRange(location: 5, length: 1))
    }

    @Test func staleGeneration() {
        do {
            _ = try Wiring.rangePairs(
                differences: [diff(99, 99, 99, 99)],
                source: "ab",
                comparison: "ab",
                expectedGeneration: 1,
                actualGeneration: 2
            )
            Issue.record("expected staleComparison")
        } catch let error as WorkflowError {
            #expect(error == .staleComparison)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func outOfBoundsFailsClosed() {
        assertInconsistentPlan(
            differences: [diff(0, 5, 0, 0)],
            source: "ab",
            comparison: "ab"
        )
        assertInconsistentPlan(
            differences: [diff(-1, 0, 0, 0)],
            source: "ab",
            comparison: "ab"
        )
        assertInconsistentPlan(
            differences: [diff(0, 0, 0, 9)],
            source: "ab",
            comparison: "ab"
        )
    }

    @Test func overlapFailsClosed() {
        assertInconsistentPlan(
            differences: [diff(0, 2, 0, 2), diff(1, 3, 3, 4)],
            source: "abcdef",
            comparison: "abcdef"
        )
        assertInconsistentPlan(
            differences: [diff(0, 1, 0, 2), diff(2, 3, 1, 3)],
            source: "abcdef",
            comparison: "abcdef"
        )
    }

    @Test func malformedShapeFailsClosed() {
        assertInconsistentPlan(
            differences: [diff(0, 0, 0, 0, paneCount: 3)],
            source: "ab",
            comparison: "ab"
        )
        assertInconsistentPlan(
            differences: [diff(2, 0, 0, 0)],
            source: "ab",
            comparison: "ab"
        )
    }

    @Test func graphemeSplitFailsClosed() {
        // "a" + combining acute is one grapheme covering UTF-16 0..<2.
        let text = "a\u{301}b"
        assertInconsistentPlan(
            differences: [diff(1, 1, 0, 0)],
            source: text,
            comparison: "ab"
        )
        assertInconsistentPlan(
            differences: [diff(0, 0, 1, 1)],
            source: "ab",
            comparison: text
        )
        assertInconsistentPlan(
            differences: [diff(0, 0, 0, 0)],
            source: text,
            comparison: "ab"
        )
    }

    @Test func emptySideInsertionAndDeletion() throws {
        let insert = try Wiring.rangePairs(
            differences: [diff(1, 0, 1, 1)],
            source: "ab",
            comparison: "axb",
            expectedGeneration: 0,
            actualGeneration: 0
        )
        #expect(insert.count == 1)
        #expect(insert[0].kind == .insert)
        #expect(insert[0].sourceUTF16Range == NSRange(location: 1, length: 0))
        #expect(insert[0].comparisonUTF16Range == NSRange(location: 1, length: 1))

        let delete = try Wiring.rangePairs(
            differences: [diff(1, 1, 1, 0)],
            source: "axb",
            comparison: "ab",
            expectedGeneration: 0,
            actualGeneration: 0
        )
        #expect(delete.count == 1)
        #expect(delete[0].kind == .delete)
        #expect(delete[0].sourceUTF16Range == NSRange(location: 1, length: 1))
        #expect(delete[0].comparisonUTF16Range == NSRange(location: 1, length: 0))
    }

    @Test func ghostLineYieldsNilRange() throws {
        let pairs = try Wiring.rangePairs(
            differences: [diff(0, -1, 0, 1)],
            source: nil,
            comparison: "hi",
            expectedGeneration: 0,
            actualGeneration: 0
        )
        #expect(pairs.count == 1)
        #expect(pairs[0].kind == .insert)
        #expect(pairs[0].sourceUTF16Range == nil)
        #expect(pairs[0].comparisonUTF16Range == NSRange(location: 0, length: 2))

        let deleted = try Wiring.rangePairs(
            differences: [diff(0, 1, 0, -1)],
            source: "hi",
            comparison: nil,
            expectedGeneration: 0,
            actualGeneration: 0
        )
        #expect(deleted[0].kind == .delete)
        #expect(deleted[0].comparisonUTF16Range == nil)
    }

    @Test func lengthOverflowFailsClosed() {
        assertInconsistentPlan(
            differences: [diff(0, Int.max, 0, 0)],
            source: "ab",
            comparison: "ab"
        )
        assertInconsistentPlan(
            differences: [diff(Int.max, Int.max, 0, 0)],
            source: "ab",
            comparison: "ab"
        )
    }

    @Test func periodicCancellationAborts() {
        let text = String(repeating: "a", count: 2048)
        let callsBox = CallsBox()
        do {
            _ = try Wiring.rangePairs(
                differences: [diff(0, 0, 0, 0)],
                source: text,
                comparison: text,
                expectedGeneration: 0,
                actualGeneration: 0,
                cancellationCheck: {
                    if callsBox.next() == 2 { throw CancellationError() }
                }
            )
            Issue.record("expected cancelled on periodic check")
        } catch let error as WorkflowError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func cancellationAborts() {
        do {
            _ = try Wiring.rangePairs(
                differences: [diff(0, 0, 0, 0)],
                source: "ab",
                comparison: "ab",
                expectedGeneration: 0,
                actualGeneration: 0,
                cancellationCheck: { throw CancellationError() }
            )
            Issue.record("expected cancelled")
        } catch let error as WorkflowError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("wrong error: \(error)")
        }

        let callsBox = CallsBox()
        do {
            _ = try Wiring.rangePairs(
                differences: [diff(0, 0, 0, 0), diff(1, 1, 1, 1)],
                source: "ab",
                comparison: "ab",
                expectedGeneration: 0,
                actualGeneration: 0,
                cancellationCheck: {
                    if callsBox.next() == 3 { throw CancellationError() }
                }
            )
            Issue.record("expected cancelled on per-difference check")
        } catch let error as WorkflowError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
