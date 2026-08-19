import Darwin
import Foundation
import MacMergeCore
import XCTest

final class ASCIILocaleCaseFoldRegressionTests: XCTestCase {
    func testEveryASCIILetterFoldsInBothInputOrdersAcrossNativeOptions() throws {
        let uppercaseBytes = Array(UInt8(0x41)...UInt8(0x5A))
        let lowercaseBytes = Array(UInt8(0x61)...UInt8(0x7A))
        let uppercase = String(decoding: uppercaseBytes, as: UTF8.self)
        let lowercase = String(decoding: lowercaseBytes, as: UTF8.self)

        XCTAssertEqual(Array(uppercase.utf8), uppercaseBytes)
        XCTAssertEqual(Array(lowercase.utf8), lowercaseBytes)
        try assertBehaviorAcrossNativeOptions(uppercase, lowercase, ignoreCase: true, matches: true)
        try assertBehaviorAcrossNativeOptions(uppercase, lowercase, ignoreCase: false, matches: false)
    }

    func testBytesImmediatelyOutsideASCIILetterRangesDoNotFold() throws {
        let boundaryPairs: [(UInt8, UInt8)] = [
            (0x40, 0x60),  // Before A/a: @ and `
            (0x5B, 0x7B)  // After Z/z: [ and {
        ]

        for (uppercaseBoundary, lowercaseBoundary) in boundaryPairs {
            let left = String(decoding: [uppercaseBoundary], as: UTF8.self)
            let right = String(decoding: [lowercaseBoundary], as: UTF8.self)

            XCTAssertEqual(Array(left.utf8), [uppercaseBoundary])
            XCTAssertEqual(Array(right.utf8), [lowercaseBoundary])
            try assertBehaviorAcrossNativeOptions(
                left,
                right,
                ignoreCase: true,
                matches: false,
                fixture: String(format: "bytes 0x%02X/0x%02X", uppercaseBoundary, lowercaseBoundary)
            )
        }
    }

    func testNonASCIIUTF8BytesRemainExactWhileAdjacentASCIIFolds() throws {
        for pair in Self.nonASCIICasePairs {
            let uppercase = String(decoding: pair.uppercaseBytes, as: UTF8.self)
            let lowercase = String(decoding: pair.lowercaseBytes, as: UTF8.self)

            XCTAssertEqual(Array(uppercase.utf8), pair.uppercaseBytes, pair.fixture)
            XCTAssertEqual(Array(lowercase.utf8), pair.lowercaseBytes, pair.fixture)
            try assertBehaviorAcrossNativeOptions(
                uppercase,
                lowercase,
                ignoreCase: true,
                matches: false,
                fixture: pair.fixture
            )
            try assertBehaviorAcrossNativeOptions(
                uppercase + "AZ",
                uppercase + "az",
                ignoreCase: true,
                matches: true,
                fixture: pair.fixture
            )
        }
    }

    func testFreshLegacyCodecEncodePathPreservesASCIIFoldBoundary() throws {
        let uppercaseData = Data([0xC0, 0x41, 0x5A])
        let asciiFoldedData = Data([0xC0, 0x61, 0x7A])
        let nonASCIIFoldedData = Data([0xE0, 0x61, 0x7A])
        let uppercase = try TextFileCodec.decode(uppercaseData, assuming: .windows1252)
        let asciiFolded = try TextFileCodec.decode(asciiFoldedData, assuming: .windows1252)
        let nonASCIIFolded = try TextFileCodec.decode(nonASCIIFoldedData, assuming: .windows1252)

        for (decoded, expectedData) in [
            (uppercase, uppercaseData),
            (asciiFolded, asciiFoldedData),
            (nonASCIIFolded, nonASCIIFoldedData)
        ] {
            let fresh = DecodedTextFile(
                text: decoded.text,
                encoding: decoded.encoding,
                hasByteOrderMark: decoded.hasByteOrderMark
            )
            XCTAssertEqual(try TextFileCodec.encode(fresh), expectedData)
        }

        XCTAssertEqual(uppercase.text, "ÀAZ")
        XCTAssertEqual(asciiFolded.text, "Àaz")
        XCTAssertEqual(nonASCIIFolded.text, "àaz")
        try assertBehaviorAcrossNativeOptions(
            uppercase.text,
            asciiFolded.text,
            ignoreCase: true,
            matches: true
        )
        try assertBehaviorAcrossNativeOptions(
            uppercase.text,
            nonASCIIFolded.text,
            ignoreCase: true,
            matches: false
        )
    }

    func testASCIIFoldingIsLocaleIndependentInIsolatedProcesses() throws {
        let environment = ProcessInfo.processInfo.environment
        if environment[Self.localeChildEnvironment] != nil {
            guard
                let requestedLocale = environment[Self.localeRequestedEnvironment],
                let completionMarkerPath = environment[Self.localeCompletionMarkerEnvironment],
                let skipMarkerPath = environment[Self.localeSkipMarkerEnvironment],
                let markerToken = environment[Self.localeMarkerTokenEnvironment]
            else {
                return XCTFail("Locale child environment is incomplete")
            }
            guard let localePointer = setlocale(LC_CTYPE, "") else {
                try Data(markerToken.utf8).write(
                    to: URL(fileURLWithPath: skipMarkerPath),
                    options: .atomic
                )
                throw XCTSkip("Requested locale is unavailable: \(requestedLocale)")
            }
            let locale = "\(requestedLocale) -> \(String(cString: localePointer))"
            try assertBehaviorAcrossNativeOptions(
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                "abcdefghijklmnopqrstuvwxyz",
                ignoreCase: true,
                matches: true,
                fixture: locale
            )
            try assertBehaviorAcrossNativeOptions(
                "@",
                "`",
                ignoreCase: true,
                matches: false,
                fixture: locale
            )
            try assertBehaviorAcrossNativeOptions(
                "À",
                "à",
                ignoreCase: true,
                matches: false,
                fixture: locale
            )
            for pair in Self.nonASCIICasePairs {
                try assertBehaviorAcrossNativeOptions(
                    String(decoding: pair.uppercaseBytes, as: UTF8.self),
                    String(decoding: pair.lowercaseBytes, as: UTF8.self),
                    ignoreCase: true,
                    matches: false,
                    fixture: "\(locale), \(pair.fixture)"
                )
            }
            try Data(markerToken.utf8).write(
                to: URL(fileURLWithPath: completionMarkerPath),
                options: .atomic
            )
            return
        }

        let deadline = DispatchTime.now() + .seconds(20)
        var unavailableLocales: [String] = []
        for locale in ["C", "en_US.UTF-8", "tr_TR.UTF-8", "tr_TR.ISO8859-9"] {
            guard let result = try assertTestPassesInLocaleSubprocess(locale, deadline: deadline) else {
                return
            }
            if result == .skipped {
                unavailableLocales.append(locale)
            }
        }
        if !unavailableLocales.isEmpty {
            throw XCTSkip("Requested locales are unavailable: \(unavailableLocales.joined(separator: ", "))")
        }
    }

    private func assertBehaviorAcrossNativeOptions(
        _ left: String,
        _ right: String,
        ignoreCase: Bool,
        matches: Bool,
        fixture: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let algorithms: [DiffAlgorithm] = [.default, .minimal, .patience, .histogram, .none]
        let whitespaceModes: [WhitespaceComparison] = [.compareAll, .ignoreChanges, .ignoreAll]

        for algorithm in algorithms {
            for whitespace in whitespaceModes {
                for ignoreLineEndings in [false, true] {
                    let options = LineDiffOptions(
                        algorithm: algorithm,
                        whitespace: whitespace,
                        ignoreCase: ignoreCase,
                        ignoreLineEndings: ignoreLineEndings
                    )
                    for (first, second) in [(left, right), (right, left)] {
                        let rows = try LineDiff.compare(
                            left: first + "\n",
                            right: second + "\n",
                            options: options
                        )
                        let context = [
                            fixture,
                            "algorithm=\(algorithm.rawValue)",
                            "whitespace=\(whitespace.rawValue)",
                            "ignoreCase=\(ignoreCase)",
                            "ignoreLineEndings=\(ignoreLineEndings)",
                            "\(first.debugDescription) versus \(second.debugDescription)"
                        ].filter { !$0.isEmpty }.joined(separator: ", ")

                        XCTAssertEqual(rows.count, 1, context, file: file, line: line)
                        XCTAssertEqual(
                            DiffSummary(rows: rows).differences,
                            matches ? 0 : 1,
                            context,
                            file: file,
                            line: line
                        )
                        XCTAssertEqual(rows.first?.kind, matches ? .unchanged : .modified, context)
                        XCTAssertEqual(rows.first?.left?.text, first, context, file: file, line: line)
                        XCTAssertEqual(rows.first?.right?.text, second, context, file: file, line: line)
                    }
                }
            }
        }
    }

    private func assertTestPassesInLocaleSubprocess(
        _ locale: String,
        deadline: DispatchTime,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> LocaleChildResult? {
        guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else {
            XCTFail("Locale children exceeded overall bounded timeout", file: file, line: line)
            return nil
        }

        let markerToken = UUID().uuidString
        let completionMarker = FileManager.default.temporaryDirectory.appending(
            path: "MacMerge-ASCIILocale-complete-\(markerToken)"
        )
        let skipMarker = FileManager.default.temporaryDirectory.appending(
            path: "MacMerge-ASCIILocale-skip-\(markerToken)"
        )
        defer {
            try? FileManager.default.removeItem(at: completionMarker)
            try? FileManager.default.removeItem(at: skipMarker)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [
            "-XCTest",
            "MacMergeCoreTests.ASCIILocaleCaseFoldRegressionTests/"
                + "testASCIIFoldingIsLocaleIndependentInIsolatedProcesses",
            Bundle(for: Self.self).bundleURL.path
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": locale,
            Self.localeChildEnvironment: "1",
            Self.localeRequestedEnvironment: locale,
            Self.localeCompletionMarkerEnvironment: completionMarker.path,
            Self.localeSkipMarkerEnvironment: skipMarker.path,
            Self.localeMarkerTokenEnvironment: markerToken
        ]) { _, addition in addition }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        guard terminated.wait(timeout: deadline) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            XCTAssertEqual(
                terminated.wait(timeout: .now() + .seconds(1)),
                .success,
                "Locale child did not stop after SIGKILL: \(locale)",
                file: file,
                line: line
            )
            XCTFail("Locale children exceeded overall bounded timeout at \(locale)", file: file, line: line)
            return nil
        }

        let completionToken = try? String(contentsOf: completionMarker, encoding: .utf8)
        let skipToken = try? String(contentsOf: skipMarker, encoding: .utf8)
        let completed = completionToken == markerToken
        let skipped = skipToken == markerToken
        guard completed != skipped else {
            XCTFail(
                "Child must produce exactly one valid completion or locale-skip marker; "
                    + "missing completion can indicate zero tests or a bad filter: \(locale)",
                file: file,
                line: line
            )
            return nil
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            XCTFail(
                "Locale child exited abnormally: \(locale), reason=\(process.terminationReason.rawValue), "
                    + "status=\(process.terminationStatus)",
                file: file,
                line: line
            )
            return nil
        }
        return skipped ? .skipped : .completed
    }

    private enum LocaleChildResult {
        case completed
        case skipped
    }

    private static let nonASCIICasePairs:
        [(
            fixture: String,
            uppercaseBytes: [UInt8],
            lowercaseBytes: [UInt8]
        )] = [
            ("2-byte Latin A with grave", [0xC3, 0x80], [0xC3, 0xA0]),
            ("3-byte fullwidth Latin A", [0xEF, 0xBC, 0xA1], [0xEF, 0xBD, 0x81]),
            ("4-byte Deseret long I", [0xF0, 0x90, 0x90, 0x80], [0xF0, 0x90, 0x90, 0xA8])
        ]

    private static let localeChildEnvironment = "MACMERGE_ASCII_CASE_LOCALE_CHILD"
    private static let localeRequestedEnvironment = "MACMERGE_ASCII_CASE_REQUESTED_LOCALE"
    private static let localeCompletionMarkerEnvironment = "MACMERGE_ASCII_CASE_COMPLETION_MARKER"
    private static let localeSkipMarkerEnvironment = "MACMERGE_ASCII_CASE_SKIP_MARKER"
    private static let localeMarkerTokenEnvironment = "MACMERGE_ASCII_CASE_MARKER_TOKEN"
}
