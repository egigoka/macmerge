import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class RecentComparisonPairsTests: XCTestCase {
    private static let trapScenarioEnvironment = "MACMERGE_RECENT_PAIRS_TRAP_SCENARIO"

    func testPairCanonicalizesStandardizedAbsoluteFileURLs() throws {
        let pair = try RecentComparisonPair(
            left: URL(string: "file:///inputs/./nested/../left.txt")!,
            right: URL(string: "file:///inputs/right/../right.txt")!,
            kind: .file
        )

        XCTAssertEqual(pair.left, canonicalURL("/inputs/left.txt", kind: .file))
        XCTAssertEqual(pair.right, canonicalURL("/inputs/right.txt", kind: .file))
        XCTAssertFalse(pair.left.hasDirectoryPath)
        XCTAssertFalse(pair.right.hasDirectoryPath)
    }

    func testPairCanonicalizesEveryLocalhostCaseVariant() throws {
        let variants = [
            "file://localhost/inputs/./left",
            "file://LOCALHOST/inputs/./left",
            "FiLe://LoCaLhOsT/inputs/./left"
        ]

        for variant in variants {
            let pair = try RecentComparisonPair(
                left: URL(string: variant)!,
                right: URL(string: variant.replacingOccurrences(of: "left", with: "right"))!,
                kind: .file
            )

            XCTAssertEqual(pair.left, canonicalURL("/inputs/left", kind: .file), variant)
            XCTAssertEqual(pair.right, canonicalURL("/inputs/right", kind: .file), variant)
            XCTAssertNil(pair.left.host, variant)
            XCTAssertNil(pair.right.host, variant)
        }
    }

    func testKindsPreserveDirectorySemanticsAndRemainDistinct() throws {
        let left = URL(filePath: "/inputs/left")
        let right = URL(filePath: "/inputs/right")
        let filePair = try RecentComparisonPair(left: left, right: right, kind: .file)
        let folderPair = try RecentComparisonPair(left: left, right: right, kind: .folder)

        XCTAssertEqual(RecentComparisonPair.Kind.allCases.map(\.rawValue), ["file", "folder"])
        XCTAssertEqual(filePair.kind, .file)
        XCTAssertFalse(filePair.left.hasDirectoryPath)
        XCTAssertFalse(filePair.right.hasDirectoryPath)
        XCTAssertEqual(folderPair.kind, .folder)
        XCTAssertTrue(folderPair.left.hasDirectoryPath)
        XCTAssertTrue(folderPair.right.hasDirectoryPath)
        XCTAssertNotEqual(filePair, folderPair)
    }

    func testPairOrderIsIdentityAndHistoryOrderIsMostRecentFirst() throws {
        let forward = try pair(0)
        let reversed = try RecentComparisonPair(
            left: forward.right,
            right: forward.left,
            kind: forward.kind
        )
        var history = RecentComparisonPairs(capacity: 2)

        XCTAssertNotEqual(forward, reversed)
        XCTAssertTrue(history.record(forward))
        XCTAssertTrue(history.record(reversed))
        XCTAssertEqual(Array(history), [reversed, forward])
        XCTAssertEqual(history.startIndex, 0)
        XCTAssertEqual(history.endIndex, 2)
        XCTAssertEqual(history[0], reversed)
    }

    func testInitializerDeduplicatesInInputOrderAndTrimsToCapacity() throws {
        let first = try pair(0)
        let second = try pair(1)
        let third = try pair(2)
        let fourth = try pair(3)

        let history = RecentComparisonPairs(
            [first, second, first, third, second, fourth],
            capacity: 3
        )

        XCTAssertEqual(history.pairs, [first, second, third])
        XCTAssertEqual(history.capacity, 3)
    }

    func testRecordPromotesDeduplicatesAndEvictsLeastRecentPair() throws {
        let first = try pair(0)
        let second = try pair(1)
        let third = try pair(2)
        let fourth = try pair(3)
        var history = RecentComparisonPairs([first, second, third], capacity: 3)

        XCTAssertFalse(history.record(first))
        XCTAssertEqual(history.pairs, [first, second, third])

        XCTAssertTrue(history.record(third))
        XCTAssertEqual(history.pairs, [third, first, second])

        XCTAssertTrue(history.record(fourth))
        XCTAssertEqual(history.pairs, [fourth, third, first])
        XCTAssertFalse(history.record(fourth))
    }

    func testConvenienceRecordAndRemoveCanonicalizeBeforeMatching() throws {
        let canonical = try RecentComparisonPair(
            left: URL(filePath: "/inputs/left.txt"),
            right: URL(filePath: "/inputs/right.txt"),
            kind: .file
        )
        var history = RecentComparisonPairs(capacity: 2)

        XCTAssertTrue(
            try history.record(
                left: URL(string: "file://LOCALHOST/inputs/./left.txt")!,
                right: URL(string: "file:///inputs/nested/../right.txt")!,
                kind: .file
            )
        )
        XCTAssertEqual(history.pairs, [canonical])
        XCTAssertFalse(
            try history.record(
                left: URL(filePath: "/inputs/left.txt"),
                right: URL(filePath: "/inputs/right.txt"),
                kind: .file
            )
        )

        XCTAssertTrue(
            try history.remove(
                left: URL(string: "file://localhost/inputs/left.txt")!,
                right: URL(string: "file:///inputs/./right.txt")!,
                kind: .file
            )
        )
        XCTAssertTrue(history.isEmpty)
        XCTAssertFalse(history.remove(canonical))
    }

    func testRemoveAndClearPreserveCapacityAndAllowReuse() throws {
        let first = try pair(0)
        let second = try pair(1)
        let third = try pair(2)
        var history = RecentComparisonPairs([first, second, third], capacity: 3)

        XCTAssertTrue(history.remove(second))
        XCTAssertEqual(history.pairs, [first, third])
        XCTAssertFalse(history.remove(second))

        history.removeAll(keepingCapacity: true)
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(history.capacity, 3)
        XCTAssertTrue(history.record(second))

        history.removeAll()
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(history.capacity, 3)
    }

    func testMaximumCapacityAcceptsMaximumEntriesAndEvictsBeyondIt() throws {
        let maximum = RecentComparisonPairs.maximumCapacity
        let pairs = try (0...maximum).map { try pair($0) }
        var history = RecentComparisonPairs(Array(pairs.prefix(maximum)), capacity: maximum)

        XCTAssertEqual(maximum, 1_000)
        XCTAssertEqual(history.capacity, maximum)
        XCTAssertEqual(history.count, maximum)
        XCTAssertEqual(history.first, pairs[0])
        XCTAssertEqual(history.last, pairs[maximum - 1])

        XCTAssertTrue(history.record(pairs[maximum]))
        XCTAssertEqual(history.count, maximum)
        XCTAssertEqual(history.first, pairs[maximum])
        XCTAssertEqual(Array(history.dropFirst()), Array(pairs[0..<(maximum - 1)]))
        XCTAssertFalse(history.contains(pairs[maximum - 1]))
    }

    func testCapacityInitializersTrapForInvalidValues() throws {
        if let scenario = Self.trapScenario {
            switch scenario {
            case "empty-negative":
                _ = RecentComparisonPairs(capacity: -1)
            case "pairs-negative":
                _ = RecentComparisonPairs([try pair(0)], capacity: -1)
            case "empty-zero":
                _ = RecentComparisonPairs(capacity: 0)
            case "pairs-zero":
                _ = RecentComparisonPairs([try pair(0)], capacity: 0)
            case "empty-too-large":
                _ = RecentComparisonPairs(capacity: RecentComparisonPairs.maximumCapacity + 1)
            case "pairs-too-large":
                _ = RecentComparisonPairs(
                    [try pair(0)],
                    capacity: RecentComparisonPairs.maximumCapacity + 1
                )
            default:
                XCTFail("Unknown trap scenario: \(scenario)")
            }
            XCTFail("Invalid capacity did not trigger its precondition")
            return
        }

        for scenario in [
            "empty-negative",
            "pairs-negative",
            "empty-zero",
            "pairs-zero",
            "empty-too-large",
            "pairs-too-large"
        ] {
            try assertCapacityPreconditionTrap(scenario: scenario)
        }
    }

    func testPairAndHistoryCodableRoundTrips() throws {
        let filePair = try pair(0, kind: .file)
        let folderPair = try pair(1, kind: .folder)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(RecentComparisonPair.self, from: encoder.encode(filePair)),
            filePair
        )
        XCTAssertEqual(
            try decoder.decode(RecentComparisonPair.self, from: encoder.encode(folderPair)),
            folderPair
        )

        let history = RecentComparisonPairs([folderPair, filePair], capacity: 7)
        let decoded = try decoder.decode(
            RecentComparisonPairs.self,
            from: encoder.encode(history)
        )
        XCTAssertEqual(decoded, history)
        XCTAssertEqual(decoded.capacity, 7)
        XCTAssertEqual(decoded.pairs, [folderPair, filePair])
    }

    func testPairRejectsHostileURLsAtInitializationAndDecode() throws {
        let valid = URL(filePath: "/inputs/valid")
        let serializableInvalidURLs = [
            URL(string: "https://example.invalid/input")!,
            URL(string: "file:relative/input")!,
            URL(string: "file://example.invalid/input")!,
            URL(string: "file://user@localhost/input")!,
            URL(string: "file://:password@localhost/input")!,
            URL(string: "file://user:password@localhost/input")!,
            URL(string: "file://localhost:9/input")!,
            URL(string: "file:///input?query=value")!,
            URL(string: "file:///input#fragment")!
        ]
        let relativeURL = URL(
            string: "child",
            relativeTo: URL(filePath: "/inputs/base", directoryHint: .isDirectory)
        )!

        for invalidURL in serializableInvalidURLs + [relativeURL] {
            assertInvalidPairURL(invalidURL, valid: valid)
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for invalidURL in serializableInvalidURLs {
            let data = try encoder.encode(
                PairWire(left: invalidURL, right: valid, kind: .file)
            )
            assertDataCorrupted(
                try decoder.decode(RecentComparisonPair.self, from: data),
                descriptionContaining: "Invalid recent comparison URL: \(invalidURL.absoluteString).",
                context: invalidURL.absoluteString
            )
        }

        let invalidRight = URL(string: "file://remote.invalid/right")!
        assertInvalidPairURL(invalidRight, valid: valid, invalidOnRight: true)
        let invalidRightData = try encoder.encode(
            PairWire(left: valid, right: invalidRight, kind: .folder)
        )
        assertDataCorrupted(
            try decoder.decode(RecentComparisonPair.self, from: invalidRightData),
            descriptionContaining: "Invalid recent comparison URL: \(invalidRight.absoluteString).",
            context: invalidRight.absoluteString
        )
    }

    func testPairRejectsDecodedNULButAcceptsLiteralPercentZeroZeroAtInitializationAndDecode()
        throws
    {
        let valid = URL(filePath: "/inputs/valid")
        let decodedNUL = URL(string: "file:///inputs/%00name")!
        let encodedLiteral = URL(string: "file:///inputs/%2500name")!
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        assertInvalidPairURL(decodedNUL, valid: valid)
        assertDataCorrupted(
            try decoder.decode(
                RecentComparisonPair.self,
                from: encoder.encode(PairWire(left: decodedNUL, right: valid, kind: .file))
            ),
            descriptionContaining: "Invalid recent comparison URL: \(decodedNUL.absoluteString)."
        )

        let initialized = try RecentComparisonPair(
            left: encodedLiteral,
            right: valid,
            kind: .file
        )
        XCTAssertEqual(initialized.left.absoluteString, "file:///inputs/%2500name")
        XCTAssertEqual(
            try decoder.decode(
                RecentComparisonPair.self,
                from: encoder.encode(PairWire(left: encodedLiteral, right: valid, kind: .file))
            ),
            initialized
        )
    }

    func testDecodeRejectsInvalidCapacities() throws {
        let validPair = PairWire(try pair(0))
        let invalidCapacities = [
            -1,
            0,
            RecentComparisonPairs.maximumCapacity + 1,
            Int.max
        ]

        for capacity in invalidCapacities {
            let data = try JSONEncoder().encode(
                HistoryWire(capacity: capacity, pairs: [validPair])
            )
            assertDataCorrupted(
                try JSONDecoder().decode(RecentComparisonPairs.self, from: data),
                codingKey: "capacity",
                descriptionContaining: "Recent comparison capacity must be between 1 and 1000."
            )
        }
    }

    func testDecodeAcceptsMaximumPairArrayAndRejectsOversizedArray() throws {
        let maximum = RecentComparisonPairs.maximumCapacity
        let pairs = (0...maximum).map { index in
            PairWire(
                left: URL(filePath: "/decode/left-\(index)"),
                right: URL(filePath: "/decode/right-\(index)"),
                kind: index.isMultiple(of: 2) ? .file : .folder
            )
        }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let maximumData = try encoder.encode(
            HistoryWire(capacity: maximum, pairs: Array(pairs.prefix(maximum)))
        )
        let maximumHistory = try decoder.decode(RecentComparisonPairs.self, from: maximumData)
        XCTAssertEqual(maximumHistory.count, maximum)
        XCTAssertEqual(maximumHistory.first, try pair(0, root: "/decode"))

        let oversizedData = try encoder.encode(
            HistoryWire(capacity: maximum, pairs: pairs)
        )
        assertDataCorrupted(
            try decoder.decode(RecentComparisonPairs.self, from: oversizedData),
            codingKey: "pairs",
            descriptionContaining: "Recent comparison history cannot exceed 1000 entries."
        )
    }

    func testDecodeRejectsOneThousandOneDuplicateEntriesBeforeDeduplication() throws {
        let duplicate = PairWire(try pair(0, root: "/duplicates"))
        let data = try JSONEncoder().encode(
            HistoryWire(
                capacity: 1,
                pairs: Array(
                    repeating: duplicate,
                    count: RecentComparisonPairs.maximumCapacity + 1
                )
            )
        )

        assertDataCorrupted(
            try JSONDecoder().decode(RecentComparisonPairs.self, from: data),
            codingKey: "pairs",
            descriptionContaining: "Recent comparison history cannot exceed 1000 entries."
        )
    }

    func testDecodeRejectsHostileTrailingPairAfterCapacityIsFilled() throws {
        let valid = PairWire(try pair(0, root: "/capacity-one"))
        let hostileURL = URL(string: "file://remote.invalid/trailing")!
        let data = try JSONEncoder().encode(
            HistoryWire(
                capacity: 1,
                pairs: [
                    valid,
                    PairWire(left: hostileURL, right: URL(filePath: "/valid"), kind: .file)
                ]
            )
        )

        assertDataCorrupted(
            try JSONDecoder().decode(RecentComparisonPairs.self, from: data),
            descriptionContaining: "Invalid recent comparison URL: \(hostileURL.absoluteString)."
        )
    }

    func testDecodeCanonicalizesThenDeduplicatesInEncodedOrder() throws {
        let first = PairWire(
            left: URL(string: "file:///history/left-0")!,
            right: URL(string: "file:///history/right-0")!,
            kind: .file
        )
        let equivalentFirst = PairWire(
            left: URL(string: "file://LOCALHOST/history/nested/../left-0")!,
            right: URL(string: "file:///history/./right-0")!,
            kind: .file
        )
        let second = PairWire(try pair(1, root: "/history"))
        let third = PairWire(try pair(2, root: "/history"))
        let fourth = PairWire(try pair(3, root: "/history"))
        let data = try JSONEncoder().encode(
            HistoryWire(
                capacity: 3,
                pairs: [first, second, equivalentFirst, third, second, fourth]
            )
        )

        let history = try JSONDecoder().decode(RecentComparisonPairs.self, from: data)

        XCTAssertEqual(
            history.pairs,
            [
                try pair(0, root: "/history"),
                try pair(1, root: "/history"),
                try pair(2, root: "/history")
            ]
        )
    }

    private static var trapScenario: String? {
        guard let sentinel = ProcessInfo.processInfo.environment[trapScenarioEnvironment] else {
            return nil
        }
        let components = sentinel.split(separator: ":", maxSplits: 2)
        guard components.count == 3,
            Int32(components[1]) == Darwin.getppid(),
            UUID(uuidString: String(components[2])) != nil
        else {
            return nil
        }
        return String(components[0])
    }

    private func assertCapacityPreconditionTrap(
        scenario: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let diagnosticsURL = FileManager.default.temporaryDirectory.appending(
            path: "MacMergeRecentPairsTrap-\(UUID().uuidString).log"
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: diagnosticsURL.path, contents: nil))
        let diagnostics = try FileHandle(forUpdating: diagnosticsURL)
        defer {
            try? diagnostics.close()
            try? FileManager.default.removeItem(at: diagnosticsURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [
            "-XCTest",
            "MacMergeCoreTests.RecentComparisonPairsTests/testCapacityInitializersTrapForInvalidValues",
            Bundle(for: Self.self).bundleURL.path
        ]
        var environment = ProcessInfo.processInfo.environment
        environment[Self.trapScenarioEnvironment] =
            "\(scenario):\(Darwin.getpid()):\(UUID().uuidString)"
        process.environment = environment
        process.standardOutput = diagnostics
        process.standardError = diagnostics
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        guard terminated.wait(timeout: .now() + .seconds(5)) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            XCTFail("Capacity trap child exceeded bounded timeout: \(scenario)", file: file, line: line)
            return
        }
        process.waitUntilExit()
        try diagnostics.synchronize()
        try diagnostics.seek(toOffset: 0)
        let output = try diagnostics.readToEnd() ?? Data()
        let diagnostic = String(decoding: output, as: UTF8.self)

        XCTAssertEqual(process.terminationReason, .uncaughtSignal, diagnostic, file: file, line: line)
        XCTAssertTrue(
            [SIGABRT, SIGILL, SIGTRAP].contains(process.terminationStatus),
            "Unexpected trap signal \(process.terminationStatus): \(diagnostic)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            diagnostic.contains("Recent comparison capacity must be between 1 and 1000"),
            diagnostic,
            file: file,
            line: line
        )
    }

    private func assertInvalidPairURL(
        _ invalidURL: URL,
        valid: URL,
        invalidOnRight: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let left = invalidOnRight ? valid : invalidURL
        let right = invalidOnRight ? invalidURL : valid
        XCTAssertThrowsError(
            try RecentComparisonPair(left: left, right: right, kind: .file),
            invalidURL.absoluteString,
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? RecentComparisonPairError,
                .invalidURL(invalidURL.absoluteString),
                file: file,
                line: line
            )
        }
    }

    private func assertDataCorrupted<T>(
        _ expression: @autoclosure () throws -> T,
        codingKey: String? = nil,
        descriptionContaining expectedDescription: String,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), context, file: file, line: line) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            if let codingKey {
                XCTAssertEqual(context.codingPath.last?.stringValue, codingKey, file: file, line: line)
            }
            XCTAssertTrue(
                context.debugDescription.contains(expectedDescription),
                context.debugDescription,
                file: file,
                line: line
            )
        }
    }

    private func pair(
        _ index: Int,
        kind: RecentComparisonPair.Kind = .file,
        root: String = "/pairs"
    ) throws -> RecentComparisonPair {
        try RecentComparisonPair(
            left: URL(filePath: "\(root)/left-\(index)"),
            right: URL(filePath: "\(root)/right-\(index)"),
            kind: kind
        )
    }

    private func canonicalURL(_ path: String, kind: RecentComparisonPair.Kind) -> URL {
        URL(fileURLWithPath: path, isDirectory: kind == .folder).standardizedFileURL
    }
}

private struct PairWire: Encodable {
    let left: URL
    let right: URL
    let kind: RecentComparisonPair.Kind

    init(left: URL, right: URL, kind: RecentComparisonPair.Kind) {
        self.left = left
        self.right = right
        self.kind = kind
    }

    init(_ pair: RecentComparisonPair) {
        self.init(left: pair.left, right: pair.right, kind: pair.kind)
    }
}

private struct HistoryWire: Encodable {
    let capacity: Int
    let pairs: [PairWire]
}
