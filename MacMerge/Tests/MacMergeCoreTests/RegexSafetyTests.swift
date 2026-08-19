import CXDiff
@testable import MacMergeCore
import XCTest

final class RegexSafetyTests: XCTestCase {
    func testInvalidPatternsAreRejectedByBothRegexEngines() {
        let pattern = "["

        XCTAssertThrowsError(try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: pattern)])
        )) { error in
            XCTAssertEqual(error as? LineDiffError, .invalidRegularExpression(pattern))
        }

        XCTAssertThrowsError(try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: pattern, replacement: "same"),
            ])
        )) { error in
            XCTAssertEqual(error as? LineDiffError, .invalidRegularExpression(pattern))
        }
    }

    func testCABIInvalidPatternReturnsNoPartialOutput() {
        let result = substitute(subject: "subject", pattern: "[", replacement: "replacement")

        XCTAssertEqual(result.status, 1)
        XCTAssertFalse(result.hadOutputPointer)
        XCTAssertEqual(result.reportedSize, 0)
        XCTAssertEqual(result.output, [])
    }

    func testPathologicalBacktrackingStopsAtPCRE2LimitAndRecovers() {
        let subject = String(repeating: "a", count: 21) + "!"
        let pattern = "(*NO_AUTO_POSSESS)(*NO_START_OPT)^(a+)+$"

        let limited = substitute(subject: subject, pattern: pattern, replacement: "match")

        XCTAssertEqual(limited.status, 2)
        XCTAssertFalse(limited.hadOutputPointer)
        XCTAssertEqual(limited.reportedSize, 0)

        XCTAssertThrowsError(try LineDiff.compare(
            left: subject,
            right: "different",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: pattern, replacement: "match"),
            ])
        )) { error in
            XCTAssertEqual(error as? LineDiffError, .substitutionEngineFailure(2))
        }

        let recovered = substitute(subject: "abc", pattern: "a", replacement: "x")
        XCTAssertEqual(recovered.status, 0)
        XCTAssertEqual(recovered.output, Array("xbc".utf8))
    }

    func testPathologicalLineFilterStopsAtPCRE2LimitAndRecovers() throws {
        let subject = String(repeating: "a", count: 21) + "!"
        let pattern = "(*NO_AUTO_POSSESS)(*NO_START_OPT)^(a+)+$"

        XCTAssertThrowsError(try LineDiff.compare(
            left: subject,
            right: "different",
            options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: pattern)])
        )) { error in
            XCTAssertEqual(error as? LineDiffError, .lineFilterEngineFailure(2))
        }

        let rows = try LineDiff.compare(
            left: "CAFÉ",
            right: "café",
            options: LineDiffOptions(lineFilters: [
                LineFilterRule(pattern: "^café$", caseSensitive: false),
            ])
        )
        XCTAssertEqual(DiffSummary(rows: rows).differences, 0)
    }

    func testCancelledLineFilterComparisonThrowsCancellation() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try LineDiff.compare(
                left: "generated-left",
                right: "generated-right",
                options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: "^generated-")])
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

    func testSubjectAndOutputAreBoundedByMaximumSize() {
        let exactSubject = substitute(
            subject: "1234",
            pattern: "z",
            replacement: "x",
            maximumSize: 4
        )
        XCTAssertEqual(exactSubject.status, 0)
        XCTAssertEqual(exactSubject.output, Array("1234".utf8))

        let exactOutput = substitute(
            subject: "aa",
            pattern: "a",
            replacement: "bb",
            maximumSize: 4
        )
        XCTAssertEqual(exactOutput.status, 0)
        XCTAssertEqual(exactOutput.output, Array("bbbb".utf8))

        let oversizedSubject = substitute(
            subject: "12345",
            pattern: ".",
            replacement: "x",
            maximumSize: 4
        )
        XCTAssertEqual(oversizedSubject.status, 4)
        XCTAssertFalse(oversizedSubject.hadOutputPointer)
        XCTAssertEqual(oversizedSubject.reportedSize, 0)

        let expandingOutput = substitute(
            subject: "aaaa",
            pattern: "a",
            replacement: "bbb",
            maximumSize: 8
        )
        XCTAssertEqual(expandingOutput.status, 4)
        XCTAssertFalse(expandingOutput.hadOutputPointer)
        XCTAssertEqual(expandingOutput.reportedSize, 0)
    }

    private func substitute(
        subject: String,
        pattern: String,
        replacement: String,
        maximumSize: Int = Int(MMX_MAX_INPUT_SIZE)
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
