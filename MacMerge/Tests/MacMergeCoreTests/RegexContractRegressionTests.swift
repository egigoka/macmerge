import CXDiff
import XCTest

@testable import MacMergeCore

final class RegexContractRegressionTests: XCTestCase {
    func testInvalidLineFilterAndSubstitutionPatternsMapToPublicError() {
        let pattern = "["

        XCTAssertThrowsError(
            try LineDiff.compare(
                left: "left",
                right: "right",
                options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: pattern)])
            )
        ) { error in
            XCTAssertEqual(error as? LineDiffError, .invalidRegularExpression(pattern))
        }

        XCTAssertThrowsError(
            try LineDiff.compare(
                left: "left",
                right: "right",
                options: LineDiffOptions(substitutions: [
                    SubstitutionRule(pattern: pattern, replacement: "replacement")
                ])
            )
        ) { error in
            XCTAssertEqual(error as? LineDiffError, .invalidRegularExpression(pattern))
        }
    }

    func testPCRE2MatchLimitMapsToPublicErrorsAndSubsequentCallsRecover() throws {
        let subject = String(repeating: "a", count: 21) + "!"
        let pattern = "(*LIMIT_MATCH=1000)(*NO_AUTO_POSSESS)(*NO_START_OPT)^(a+)+$"

        XCTAssertThrowsError(
            try LineDiff.compare(
                left: subject,
                right: "different",
                options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: pattern)])
            )
        ) { error in
            XCTAssertEqual(error as? LineDiffError, .lineFilterEngineFailure(2))
        }

        XCTAssertThrowsError(
            try LineDiff.compare(
                left: subject,
                right: "different",
                options: LineDiffOptions(substitutions: [
                    SubstitutionRule(pattern: pattern, replacement: "replacement")
                ])
            )
        ) { error in
            XCTAssertEqual(error as? LineDiffError, .substitutionEngineFailure(2))
        }

        let filteredRows = try LineDiff.compare(
            left: "generated-left",
            right: "generated-right",
            options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: "^generated-")])
        )
        XCTAssertEqual(DiffSummary(rows: filteredRows).differences, 0)

        let substitutedRows = try LineDiff.compare(
            left: "build 1",
            right: "build 2",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "[0-9]", replacement: "0")
            ])
        )
        XCTAssertEqual(DiffSummary(rows: substitutedRows).differences, 0)
    }

    func testConfiguredMaximumAcceptsExactSubjectAndRejectsOneByteMore() {
        let maximumSize = 8

        let exact = substitute(
            subject: "12345678",
            pattern: "z",
            replacement: "x",
            maximumSize: maximumSize
        )
        XCTAssertEqual(exact.status, 0)
        XCTAssertEqual(exact.output, Array("12345678".utf8))
        XCTAssertTrue(exact.hadOutputPointer)
        XCTAssertEqual(exact.reportedSize, maximumSize)

        let oversized = substitute(
            subject: "123456789",
            pattern: "z",
            replacement: "x",
            maximumSize: maximumSize
        )
        XCTAssertEqual(oversized.status, 4)
        XCTAssertEqual(oversized.output, [])
        XCTAssertFalse(oversized.hadOutputPointer)
        XCTAssertEqual(oversized.reportedSize, 0)
    }

    func testConfiguredMaximumAcceptsExactOutputAndRejectsExpansionPastIt() {
        let maximumSize = 8

        let exact = substitute(
            subject: "aaaa",
            pattern: "a",
            replacement: "bb",
            maximumSize: maximumSize
        )
        XCTAssertEqual(exact.status, 0)
        XCTAssertEqual(exact.output, Array("bbbbbbbb".utf8))
        XCTAssertTrue(exact.hadOutputPointer)
        XCTAssertEqual(exact.reportedSize, maximumSize)

        let oversized = substitute(
            subject: "a",
            pattern: "a",
            replacement: "123456789",
            maximumSize: maximumSize
        )
        XCTAssertEqual(oversized.status, 4)
        XCTAssertEqual(oversized.output, [])
        XCTAssertFalse(oversized.hadOutputPointer)
        XCTAssertEqual(oversized.reportedSize, 0)
    }

    func testIndependentPublicRegexCallsAreThreadSafe() async throws {
        let taskCount = 32
        let ready = expectation(description: "All regex calls reached the start gate")
        ready.expectedFulfillmentCount = taskCount
        let startGate = AsyncStartGate()

        let differences = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<taskCount {
                group.addTask {
                    ready.fulfill()
                    await startGate.wait()

                    let rows = try LineDiff.compare(
                        left: "token-\(index)\nignored-left-\(index)",
                        right: "normalized\nignored-right-\(index)",
                        options: LineDiffOptions(
                            lineFilters: [LineFilterRule(pattern: "^ignored-")],
                            substitutions: [
                                SubstitutionRule(pattern: "^token-[0-9]+$", replacement: "normalized")
                            ]
                        )
                    )
                    return DiffSummary(rows: rows).differences
                }
            }

            await fulfillment(of: [ready], timeout: 5)
            await startGate.open()

            var values: [Int] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(differences.count, taskCount)
        XCTAssertTrue(differences.allSatisfy { $0 == 0 })
    }

    private func substitute(
        subject: String,
        pattern: String,
        replacement: String,
        maximumSize: Int
    ) -> (status: Int32, output: [UInt8], hadOutputPointer: Bool, reportedSize: Int) {
        let subjectBytes = Array(subject.utf8)
        let patternBytes = Array(pattern.utf8)
        let replacementBytes = Array(replacement.utf8)
        var nativeResult = mmx_bytes_result(bytes: nil, size: 0)
        let status = subjectBytes.withUnsafeBytes { subjectBuffer in
            patternBytes.withUnsafeBytes { patternBuffer in
                replacementBytes.withUnsafeBytes { replacementBuffer in
                    mmx_regex_substitute(
                        subjectBuffer.baseAddress,
                        subjectBuffer.count,
                        patternBuffer.baseAddress,
                        patternBuffer.count,
                        replacementBuffer.baseAddress,
                        replacementBuffer.count,
                        1,
                        maximumSize,
                        &nativeResult
                    )
                }
            }
        }
        let hadOutputPointer = nativeResult.bytes != nil
        let reportedSize = nativeResult.size
        let output = Array(UnsafeBufferPointer(start: nativeResult.bytes, count: nativeResult.size))
        mmx_bytes_result_free(&nativeResult)
        return (status, output, hadOutputPointer, reportedSize)
    }
}

private actor AsyncStartGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}
