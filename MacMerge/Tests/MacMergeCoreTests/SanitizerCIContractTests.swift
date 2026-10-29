import Foundation
import XCTest

final class SanitizerCIContractTests: XCTestCase {
    private struct ProcessResult {
        let status: Int32
        let output: String
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var scriptURL: URL {
        packageRoot.appendingPathComponent("Scripts/run-sanitizers.sh")
    }

    private var workflowURL: URL {
        packageRoot.deletingLastPathComponent().appendingPathComponent(".github/workflows/macmerge.yml")
    }

    func testUnsupportedSanitizersExitWithUsageStatusBeforeBuilding() throws {
        let stub = try makeSwiftStub()
        defer { try? FileManager.default.removeItem(at: stub.root) }

        let cases: [(arguments: [String], diagnostic: String)] = [
            (["address"], "address sanitizer runs as its own CI step"),
            (["memory"], "usage:"),
            (["leak"], "usage:"),
            (["scudo"], "usage:"),
            (["fuzzer"], "usage:"),
            (["undefined", "address"], "address sanitizer runs as its own CI step"),
            (["thread", "bogus"], "usage:")
        ]
        for testCase in cases {
            let result = try runScript(testCase.arguments, stub: stub)
            let name = testCase.arguments.joined(separator: " ")
            XCTAssertEqual(result.status, 64, "\(name): \(result.output)")
            XCTAssertTrue(result.output.contains(testCase.diagnostic), "\(name): \(result.output)")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: stub.log.path),
                "\(name) started swift test before rejecting the sanitizer list"
            )
        }
    }

    func testSupportedSanitizersRunSwiftTestWithIsolatedScratchAndHaltingOptions() throws {
        let stub = try makeSwiftStub()
        defer { try? FileManager.default.removeItem(at: stub.root) }
        let scratchRoot = stub.root.appendingPathComponent("scratch").path

        let result = try runScript(
            [],
            stub: stub,
            environment: [
                "SANITIZER_SCRATCH_ROOT": scratchRoot,
                "SANITIZER_TEST_FILTER": "MacMergeCoreTests\\.(LineDiffTests)/",
                "SANITIZER_TEST_SKIP": "LineDiffTests/testSkipped"
            ]
        )
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Sanitizer runs passed: undefined thread"), result.output)

        let invocations = try String(contentsOf: stub.log, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(invocations.count, 2, invocations.joined(separator: "\n"))
        for (sanitizer, invocation) in zip(["undefined", "thread"], invocations) {
            XCTAssertTrue(invocation.contains("args=test --package-path "), invocation)
            XCTAssertTrue(invocation.contains("--scratch-path \(scratchRoot)/\(sanitizer) "), invocation)
            XCTAssertTrue(invocation.contains("--sanitize \(sanitizer) "), invocation)
            XCTAssertTrue(invocation.contains("-Xswiftc -warnings-as-errors"), invocation)
            XCTAssertTrue(invocation.contains("--filter MacMergeCoreTests\\.(LineDiffTests)/"), invocation)
            XCTAssertTrue(invocation.contains("--skip LineDiffTests/testSkipped"), invocation)
        }
        XCTAssertTrue(invocations[0].contains("ubsan=print_stacktrace=1:report_error_type=1:halt_on_error=1 "), invocations[0])
        XCTAssertTrue(invocations[1].hasSuffix("tsan=second_deadlock_stack=1:halt_on_error=1"), invocations[1])
        // strip_env=0 would leak the TSan runtime into every child process the tests spawn.
        XCTAssertFalse(invocations[1].contains("strip_env=0"), invocations[1])
    }

    func testDefaultsUsePackageScratchAndOmitFilterAndSkip() throws {
        let stub = try makeSwiftStub()
        defer { try? FileManager.default.removeItem(at: stub.root) }

        let result = try runScript(["undefined"], stub: stub)
        XCTAssertEqual(result.status, 0, result.output)

        let invocation = try String(contentsOf: stub.log, encoding: .utf8)
        let scratch = packageRoot.appendingPathComponent(".build/sanitizers/undefined").path
        XCTAssertTrue(invocation.contains("--scratch-path \(scratch) "), invocation)
        // An empty --filter or --skip would not mean "every test", so unset variables must omit the flag.
        XCTAssertFalse(invocation.contains("--filter"), invocation)
        XCTAssertFalse(invocation.contains("--skip"), invocation)
    }

    func testCallerOptionsAreKeptButCannotDisableHalting() throws {
        let stub = try makeSwiftStub()
        defer { try? FileManager.default.removeItem(at: stub.root) }

        let result = try runScript(
            [],
            stub: stub,
            environment: [
                "SANITIZER_SCRATCH_ROOT": stub.root.appendingPathComponent("scratch").path,
                "UBSAN_OPTIONS": "halt_on_error=0:verbosity=1",
                "TSAN_OPTIONS": "halt_on_error=0:history_size=7"
            ]
        )
        XCTAssertEqual(result.status, 0, result.output)
        let invocations = try String(contentsOf: stub.log, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(invocations.count, 2, invocations.joined(separator: "\n"))
        // The sanitizer runtimes apply keys left to right, so the trailing halt_on_error=1 wins.
        XCTAssertTrue(
            invocations[0].contains(
                "ubsan=print_stacktrace=1:report_error_type=1:halt_on_error=0:verbosity=1:halt_on_error=1 "
            ),
            invocations[0]
        )
        XCTAssertTrue(
            invocations[1].hasSuffix("tsan=second_deadlock_stack=1:halt_on_error=0:history_size=7:halt_on_error=1"),
            invocations[1]
        )
    }

    func testFailingSanitizerRunFailsScriptAndStopsLaterSanitizers() throws {
        let stub = try makeSwiftStub()
        defer { try? FileManager.default.removeItem(at: stub.root) }

        let result = try runScript(
            [],
            stub: stub,
            environment: [
                "SANITIZER_SCRATCH_ROOT": stub.root.appendingPathComponent("scratch").path,
                "SWIFT_STUB_EXIT_STATUS": "1"
            ]
        )
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(result.output.contains("Sanitizer runs passed"), result.output)
        let invocations = try String(contentsOf: stub.log, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(invocations.count, 1, invocations.joined(separator: "\n"))
        XCTAssertTrue(invocations.first?.contains("--sanitize undefined ") ?? false, invocations.joined())
    }

    // Doc pin only: it detects removed or reworded notes, not wrong ones. The rejection
    // behavior itself is covered by testUnsupportedSanitizersExitWithUsageStatusBeforeBuilding.
    func testScriptDocumentsUnsupportedCombinations() throws {
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        for phrase in [
            "thread cannot be combined with address",
            "no memory or leak sanitizer on any platform",
            "Linux-only",
            "fuzzer is out of scope",
            "instruments the CXDiff C target"
        ] {
            XCTAssertTrue(script.contains(phrase), "run-sanitizers.sh no longer documents: \(phrase)")
        }
    }

    func testWorkflowSanitizerFiltersNameExistingTests() throws {
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)
        let testSources = try coreTestSources()
        let testClasses = captures(of: #"final class (\w+): XCTestCase"#, in: testSources)
        let testMethods = captures(of: #"func (test\w+)\("#, in: testSources)

        for sanitizer in ["undefined", "thread"] {
            let job = try XCTUnwrap(jobBody(named: "sanitize-\(sanitizer)", in: workflow), sanitizer)
            XCTAssertTrue(job.contains("run: Scripts/run-sanitizers.sh \(sanitizer)"), sanitizer)
            XCTAssertTrue(job.contains("timeout-minutes:"), sanitizer)
            let filter = try XCTUnwrap(foldedValue(of: "SANITIZER_TEST_FILTER", in: job), sanitizer)
            // A typo in the prefix or suffix makes swift test match nothing and still pass.
            XCTAssertTrue(filter.hasPrefix(#"MacMergeCoreTests\.("#), "\(sanitizer) filter: \(filter)")
            XCTAssertTrue(filter.hasSuffix(")/"), "\(sanitizer) filter: \(filter)")
            let filterRegex = try NSRegularExpression(pattern: filter)
            let classes = try XCTUnwrap(alternatives(in: filter), "\(sanitizer) filter: \(filter)")
            XCTAssertFalse(classes.isEmpty, sanitizer)
            for name in classes {
                // An unmatched filter makes swift test pass without running anything.
                XCTAssertTrue(testClasses.contains(name), "sanitize-\(sanitizer) filter names missing test class \(name)")
                XCTAssertTrue(
                    matches(filterRegex, "MacMergeCoreTests.\(name)/testExample"),
                    "sanitize-\(sanitizer) filter does not match tests in \(name)"
                )
            }

            let skip = foldedValue(of: "SANITIZER_TEST_SKIP", in: job)
            guard sanitizer == "thread" else {
                XCTAssertNil(skip, "sanitize-\(sanitizer) skips tests: \(skip ?? "")")
                continue
            }
            // Without the skip, TSan aborts in the re-launched xctest child.
            let threadSkip = try XCTUnwrap(skip, "sanitize-thread must skip the xctest re-launch tests")
            XCTAssertTrue(threadSkip.hasSuffix(")$"), "skip must be anchored: \(threadSkip)")
            let skipClass = try XCTUnwrap(threadSkip.split(separator: "/").first.map(String.init), threadSkip)
            XCTAssertTrue(classes.contains(skipClass), "skip \(threadSkip) is outside the thread filter")
            let skippedMethods = try XCTUnwrap(alternatives(in: threadSkip), threadSkip)
            XCTAssertEqual(
                Set(skippedMethods),
                ["testFollowPolicyStopsDirectoryCycleAndReportsIssue", "testFollowPolicyBoundsSymbolicLinkResolutionCycle"]
            )
            for method in skippedMethods {
                XCTAssertTrue(testMethods.contains(method), "skip names missing test \(method)")
            }
            let skipRegex = try NSRegularExpression(pattern: threadSkip)
            XCTAssertTrue(matches(skipRegex, "MacMergeCoreTests.FolderScannerTests/\(skippedMethods[0])"))
            XCTAssertFalse(matches(skipRegex, "MacMergeCoreTests.FolderScannerTests/\(skippedMethods[0])Extra"))
        }
    }

    // MARK: - Helpers

    private func makeSwiftStub() throws -> (root: URL, log: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SanitizerCIContractTests-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("swift.log")
        let stub = bin.appendingPathComponent("swift")
        try """
        #!/bin/bash
        echo "args=$* ubsan=${UBSAN_OPTIONS:-} tsan=${TSAN_OPTIONS:-}" >> \(shellQuote(log.path))
        exit "${SWIFT_STUB_EXIT_STATUS:-0}"
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        return (root, log)
    }

    private func runScript(
        _ arguments: [String],
        stub: (root: URL, log: URL),
        environment: [String: String] = [:]
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path] + arguments
        var processEnvironment = [
            "PATH": "\(stub.root.appendingPathComponent("bin").path):/usr/bin:/bin",
            "HOME": stub.root.path
        ]
        processEnvironment.merge(environment) { _, new in new }
        process.environment = processEnvironment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    private func coreTestSources() throws -> String {
        let directory = packageRoot.appendingPathComponent("Tests/MacMergeCoreTests")
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private func jobBody(named name: String, in workflow: String) -> String? {
        let lines = workflow.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "  \(name):") else {
            return nil
        }
        let body = lines[(start + 1)...].prefix { line in
            line.isEmpty || line.hasPrefix("   ")
        }
        return body.joined(separator: "\n")
    }

    /// Reads a `key: >-` folded scalar, joining every deeper-indented line with a space.
    private func foldedValue(of key: String, in job: String) -> String? {
        let lines = job.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "\(key): >-" }) else {
            return nil
        }
        let keyIndent = indent(of: lines[index])
        let valueLines = lines[(index + 1)...]
            .prefix { !$0.trimmingCharacters(in: .whitespaces).isEmpty && indent(of: $0) > keyIndent }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return valueLines.isEmpty ? nil : valueLines.joined(separator: " ")
    }

    private func indent(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private func captures(of pattern: String, in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return Set(
            regex.matches(in: text, range: range).compactMap { match in
                Range(match.range(at: 1), in: text).map { String(text[$0]) }
            }
        )
    }

    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func alternatives(in pattern: String) -> [String]? {
        guard let open = pattern.firstIndex(of: "("), let close = pattern.lastIndex(of: ")"), open < close else {
            return nil
        }
        return pattern[pattern.index(after: open)..<close].split(separator: "|").map(String.init)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
