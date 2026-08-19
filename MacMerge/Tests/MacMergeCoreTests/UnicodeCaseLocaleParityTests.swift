import Darwin
import Foundation
import MacMergeCore
import XCTest

final class UnicodeCaseLocaleParityTests: XCTestCase {
    func testIgnoreCaseFoldsASCIIBytesOnly() throws {
        let left = "ASCII: ALPHA-ZULU 0123 !?"
        let right = "ascii: alpha-zulu 0123 !?"

        XCTAssertEqual(
            DiffSummary(rows: try LineDiff.compare(left: left, right: right)).differences,
            1
        )
        try assertNativeCaseMatch(left, right)
    }

    func testAccentedLatinBytesRemainCaseSensitive() throws {
        try assertNativeCaseDifference("CAFÉ ÅNGSTRÖM", "café ångström")
    }

    func testTurkishIVariantsDoNotUseLocaleAwareFolding() throws {
        try assertNativeCaseMatch("I", "i")
        try assertNativeCaseDifference("I", "ı")
        try assertNativeCaseDifference("İ", "i")
        try assertNativeCaseDifference("İ", "ı")
    }

    func testASCIICaseFoldingIsLocaleIndependent() throws {
        if ProcessInfo.processInfo.environment[Self.localeChildEnvironment] != nil {
            guard let activatedLocale = setlocale(LC_CTYPE, "") else {
                throw XCTSkip("Requested locale is unavailable")
            }

            try assertNativeCaseMatch("I FILE INDEX", "i file index")
            try assertNativeCaseDifference("CAFÉ", "café", context: String(cString: activatedLocale))
            return
        }

        for locale in ["tr_TR.UTF-8", "tr_TR.ISO8859-9"] {
            try assertTestPassesInLocaleSubprocess(locale)
        }
    }

    func testGreekSigmaVariantsRemainDistinctBytes() throws {
        try assertNativeCaseDifference("Σ", "σ")
        try assertNativeCaseDifference("Σ", "ς")
        try assertNativeCaseDifference("σ", "ς")
    }

    func testGermanSharpSDoesNotExpandOrFold() throws {
        try assertNativeCaseDifference("straße", "STRASSE")
        try assertNativeCaseDifference("ẞ", "ß")
    }

    func testCanonicallyEquivalentComposedAndDecomposedFormsRemainDistinctBytes() throws {
        let composed = "café"
        let decomposed = "cafe\u{301}"

        XCTAssertFalse(composed.utf8.elementsEqual(decomposed.utf8))
        try assertNativeCaseDifference(composed, decomposed)
    }

    func testLegacyCodePageTextUsesDecodedUTF8BytesForIgnoreCase() throws {
        let fixtures: [(Data, Data, TextFileEncoding, String, String, Bool)] = [
            (
                Data([0x43, 0x41, 0x46, 0xC9]),
                Data([0x63, 0x61, 0x66, 0xE9]),
                .windows1252,
                "CAFÉ",
                "café",
                false
            ),
            (
                Data([0xC1, 0xCB, 0xD6, 0xC1]),
                Data([0xE1, 0xEB, 0xF6, 0xE1]),
                .windows1253,
                "ΑΛΦΑ",
                "αλφα",
                false
            ),
            (
                Data([0xDD, 0xDE, 0x49]),
                Data([0x69, 0xFE, 0xFD]),
                .windows1254,
                "İŞI",
                "işı",
                false
            ),
            (
                Data([0x54, 0x45, 0x53, 0x54, 0x83, 0x65, 0x83, 0x58, 0x83, 0x67]),
                Data([0x74, 0x65, 0x73, 0x74, 0x83, 0x65, 0x83, 0x58, 0x83, 0x67]),
                .shiftJIS,
                "TESTテスト",
                "testテスト",
                true
            )
        ]

        for (leftData, rightData, encoding, expectedLeft, expectedRight, matches) in fixtures {
            let left = try TextFileCodec.decode(leftData, assuming: encoding)
            let right = try TextFileCodec.decode(rightData, assuming: encoding)
            let context = encoding.displayName

            XCTAssertEqual(left.text, expectedLeft, context)
            XCTAssertEqual(right.text, expectedRight, context)
            XCTAssertEqual(
                try TextFileCodec.encode(
                    DecodedTextFile(
                        text: left.text,
                        encoding: left.encoding,
                        hasByteOrderMark: left.hasByteOrderMark
                    )
                ),
                leftData,
                context
            )
            XCTAssertEqual(
                try TextFileCodec.encode(
                    DecodedTextFile(
                        text: right.text,
                        encoding: right.encoding,
                        hasByteOrderMark: right.hasByteOrderMark
                    )
                ),
                rightData,
                context
            )
            try assertNativeCaseBehavior(left.text, right.text, matches: matches, context: context)
        }
    }

    private func assertNativeCaseMatch(
        _ left: String,
        _ right: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try assertNativeCaseBehavior(left, right, matches: true, file: file, line: line)
    }

    private func assertNativeCaseDifference(
        _ left: String,
        _ right: String,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try assertNativeCaseBehavior(
            left,
            right,
            matches: false,
            context: context,
            file: file,
            line: line
        )
    }

    private func assertNativeCaseBehavior(
        _ left: String,
        _ right: String,
        matches: Bool,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // WinMerge converts ignore-case inputs to UTF-8, then xdiff folds only bytes below 0x80.
        for (first, second) in [(left, right), (right, left)] {
            let rows = try LineDiff.compare(
                left: first + "\n",
                right: second + "\n",
                options: LineDiffOptions(ignoreCase: true)
            )

            XCTAssertEqual(
                DiffSummary(rows: rows).differences,
                matches ? 0 : 1,
                context.isEmpty
                    ? "\(first.debugDescription) versus \(second.debugDescription)"
                    : "\(context): \(first.debugDescription) versus \(second.debugDescription)",
                file: file,
                line: line
            )
        }
    }

    private func assertTestPassesInLocaleSubprocess(
        _ locale: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [
            "-XCTest",
            "MacMergeCoreTests.UnicodeCaseLocaleParityTests/testASCIICaseFoldingIsLocaleIndependent",
            Bundle(for: Self.self).bundleURL.path
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": locale,
            Self.localeChildEnvironment: "1"
        ]) { _, addition in addition }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        guard terminated.wait(timeout: .now() + .seconds(5)) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            XCTFail("Locale child exceeded bounded timeout: \(locale)", file: file, line: line)
            return
        }
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit, locale, file: file, line: line)
        XCTAssertEqual(process.terminationStatus, 0, locale, file: file, line: line)
    }

    private static let localeChildEnvironment = "MACMERGE_UNICODE_CASE_LOCALE_CHILD"
}
