import Foundation
import XCTest

@testable import MacMergeCore

final class ConfigurationReportTests: XCTestCase {
    func testBuildOrdersRecordsDeterministicallyAndProducesExactOutput() throws {
        let limits = [
            ConfigurationReportRecord(name: "Zulu", value: "2"),
            ConfigurationReportRecord(name: "Alpha", value: "9"),
            ConfigurationReportRecord(name: "Alpha", value: "1")
        ]
        let features = [
            ConfigurationReportRecord(name: "beta", value: "on"),
            ConfigurationReportRecord(name: "Alpha", value: "off")
        ]
        let forward = ConfigurationReport(
            appName: "MacMerge",
            appVersion: "1.2",
            buildVersion: "34",
            operatingSystem: "macOS 15.0",
            architecture: "arm64",
            localeIdentifier: "en_US",
            sandboxState: .enabled,
            comparisonLimits: limits,
            features: features
        )
        let reversed = ConfigurationReport(
            appName: "MacMerge",
            appVersion: "1.2",
            buildVersion: "34",
            operatingSystem: "macOS 15.0",
            architecture: "arm64",
            localeIdentifier: "en_US",
            sandboxState: .enabled,
            comparisonLimits: Array(limits.reversed()),
            features: Array(features.reversed())
        )
        let expected = [
            "MacMerge Configuration Report",
            "",
            "Application",
            "Name: MacMerge",
            "Version: 1.2",
            "Build: 34",
            "",
            "System",
            "Operating System: macOS 15.0",
            "Architecture: arm64",
            "Locale: en_US",
            "Sandbox: enabled",
            "",
            "Comparison Limits",
            "Alpha: 1",
            "Alpha: 9",
            "Zulu: 2",
            "",
            "Features",
            "Alpha: off",
            "beta: on",
            ""
        ].joined(separator: "\n")

        XCTAssertEqual(try forward.build(), expected)
        XCTAssertEqual(try reversed.build(), expected)
        XCTAssertEqual(try forward.data(), Data(expected.utf8))
        XCTAssertEqual(try reversed.data(), try forward.data())
    }

    func testEmptySectionsProduceExplicitNoneRows() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .unknown
        )
        let expected = [
            "App Configuration Report",
            "",
            "Application",
            "Name: App",
            "Version: 1",
            "Build: 2",
            "",
            "System",
            "Operating System: macOS",
            "Architecture: arm64",
            "Locale: en",
            "Sandbox: unknown",
            "",
            "Comparison Limits",
            "(none)",
            "",
            "Features",
            "(none)",
            ""
        ].joined(separator: "\n")

        XCTAssertEqual(try report.build(), expected)
    }

    func testExactItemInputAndOutputBoundsPassAndLimitMinusOneReturnsSpecificError() throws {
        let report = ConfigurationReport(
            appName: "A",
            appVersion: "V",
            buildVersion: "B",
            operatingSystem: "O",
            architecture: "R",
            localeIdentifier: "L",
            sandboxState: .disabled,
            comparisonLimits: [ConfigurationReportRecord(name: "N", value: "1")],
            features: [ConfigurationReportRecord(name: "F", value: "Y")],
            redactionRoots: ["/r"],
            usernames: ["u"]
        )
        let complete = try report.build()
        let exactBounds = ConfigurationReportBounds(
            maximumItemCount: 4,
            maximumInputBytes: 13,
            maximumOutputBytes: complete.utf8.count
        )

        XCTAssertEqual(try report.build(bounds: exactBounds), complete)
        XCTAssertEqual(try report.data(bounds: exactBounds), Data(complete.utf8))

        XCTAssertThrowsError(
            try report.build(
                bounds: ConfigurationReportBounds(
                    maximumItemCount: 3,
                    maximumInputBytes: 13,
                    maximumOutputBytes: complete.utf8.count
                ))
        ) {
            XCTAssertEqual($0 as? ConfigurationReportError, .tooManyItems(maximum: 3))
        }
        XCTAssertThrowsError(
            try report.build(
                bounds: ConfigurationReportBounds(
                    maximumItemCount: 4,
                    maximumInputBytes: 12,
                    maximumOutputBytes: complete.utf8.count
                ))
        ) {
            XCTAssertEqual($0 as? ConfigurationReportError, .inputTooLarge(maximumBytes: 12))
        }
        XCTAssertThrowsError(
            try report.build(
                bounds: ConfigurationReportBounds(
                    maximumItemCount: 4,
                    maximumInputBytes: 13,
                    maximumOutputBytes: complete.utf8.count - 1
                ))
        ) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .outputTooLarge(maximumBytes: complete.utf8.count - 1)
            )
        }
    }

    func testInputAndOutputBoundsCountMultibyteUTF8Bytes() throws {
        let report = ConfigurationReport(
            appName: "Aé🙂",
            appVersion: "V",
            buildVersion: "B",
            operatingSystem: "O",
            architecture: "R",
            localeIdentifier: "L",
            sandboxState: .disabled
        )
        let inputByteCount = ["Aé🙂", "V", "B", "O", "R", "L"]
            .reduce(into: 0) { $0 += $1.utf8.count }
        let output = try report.build()

        XCTAssertEqual(
            try report.build(
                bounds: ConfigurationReportBounds(
                    maximumInputBytes: inputByteCount,
                    maximumOutputBytes: output.utf8.count
                )),
            output
        )
        XCTAssertThrowsError(
            try report.build(
                bounds: ConfigurationReportBounds(
                    maximumInputBytes: inputByteCount - 1,
                    maximumOutputBytes: output.utf8.count
                ))
        ) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .inputTooLarge(maximumBytes: inputByteCount - 1)
            )
        }
        XCTAssertThrowsError(
            try report.build(
                bounds: ConfigurationReportBounds(
                    maximumInputBytes: inputByteCount,
                    maximumOutputBytes: output.utf8.count - 1
                ))
        ) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .outputTooLarge(maximumBytes: output.utf8.count - 1)
            )
        }
    }

    func testInputLimitRejectsOversizedInvalidValueBeforeSemanticValidation() {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: [String(repeating: "x", count: 1_000_000) + "\n"]
        )

        XCTAssertThrowsError(
            try report.build(
                bounds: ConfigurationReportBounds(
                    maximumInputBytes: 64
                ))
        ) {
            XCTAssertEqual($0 as? ConfigurationReportError, .inputTooLarge(maximumBytes: 64))
        }
    }

    func testInvalidBoundsReturnTheirSpecificErrors() {
        let report = ConfigurationReport(
            appName: "A",
            appVersion: "V",
            buildVersion: "B",
            operatingSystem: "O",
            architecture: "R",
            localeIdentifier: "L",
            sandboxState: .disabled
        )
        let cases: [(ConfigurationReportBounds, ConfigurationReportError)] = [
            (
                ConfigurationReportBounds(maximumItemCount: -1),
                .invalidMaximumItemCount(-1)
            ),
            (
                ConfigurationReportBounds(maximumInputBytes: 0),
                .invalidMaximumInputBytes(0)
            ),
            (
                ConfigurationReportBounds(maximumOutputBytes: 0),
                .invalidMaximumOutputBytes(0)
            )
        ]

        for (bounds, expectedError) in cases {
            XCTAssertThrowsError(try report.build(bounds: bounds)) {
                XCTAssertEqual($0 as? ConfigurationReportError, expectedError)
            }
        }
    }

    func testControlLineSeparatorAndBidiScalarsAreEscaped() throws {
        let unsafeScalarValues: [UInt32] = [
            0x00, 0x0A, 0x1F, 0x7F, 0x85, 0x9F,
            0x061C, 0x200E, 0x200F,
            0x2028, 0x2029, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
            0x2066, 0x2067, 0x2068, 0x2069
        ]
        let unsafeValue =
            unsafeScalarValues
            .compactMap { UnicodeScalar($0) }
            .map(String.init)
            .joined()
        let escapedValue = unsafeScalarValues.map {
            "\\u{" + String($0, radix: 16, uppercase: true) + "}"
        }.joined()
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            features: [ConfigurationReportRecord(name: "Unsafe", value: unsafeValue)]
        )

        let output = try report.build()

        XCTAssertTrue(output.contains("Unsafe: \(escapedValue)\n"))
        let unsafeSet = Set(unsafeScalarValues.filter { $0 != 0x0A })
        XCTAssertFalse(output.unicodeScalars.contains { unsafeSet.contains($0.value) })
    }

    func testCanonicalEquivalentRootsAndUsernamesAreRedacted() throws {
        let precomposedName = "José"
        let decomposedName = "Jose\u{301}"
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "path=/Users/\(decomposedName)/Work/file owner=\(decomposedName)",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["/Users/\(precomposedName)/Work"],
            usernames: [precomposedName]
        )

        let output = try report.build()

        XCTAssertTrue(output.contains("Operating System: path=<home>/file owner=<user>\n"))
        XCTAssertFalse(output.contains(precomposedName))
        XCTAssertFalse(output.contains(decomposedName))
    }

    func testRedactionCoversEveryReportStringSink() throws {
        let root = "/Users/Alice/Private"
        let privateValue = root + "/value"
        let report = ConfigurationReport(
            appName: privateValue,
            appVersion: privateValue,
            buildVersion: privateValue,
            operatingSystem: privateValue,
            architecture: privateValue,
            localeIdentifier: privateValue,
            sandboxState: .enabled,
            comparisonLimits: [
                ConfigurationReportRecord(name: privateValue, value: privateValue)
            ],
            features: [
                ConfigurationReportRecord(name: privateValue, value: privateValue)
            ],
            redactionRoots: [root]
        )

        let output = try report.build()

        XCTAssertFalse(output.contains(root))
        XCTAssertFalse(output.contains("Alice"))
        XCTAssertEqual(output.components(separatedBy: "<home>/value").count - 1, 11)
    }

    func testCaseUnicodeAndFileURLPathAliasesAreRedactedCanonically() throws {
        let decomposedName = "Jose\u{301}"
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "url=FILE:///users/\(decomposedName)/project%2520space/one "
                + "path=/users/\(decomposedName)/project%20space/two owner=straße",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["file:///Users/JOSÉ/Project%20Space"],
            usernames: ["STRASSE"]
        )

        let output = try report.build()

        XCTAssertTrue(
            output.contains(
                "Operating System: url=<home>/one path=<home>/two owner=<user>\n"
            )
        )
        XCTAssertFalse(output.localizedCaseInsensitiveContains("josé"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("project space"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("straße"))
    }

    func testPercentEncodedPathsAndFileURLRootsAreRedacted() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "one=/Users/Alice/Project%2520Space/a "
                + "two=file:///Volumes/Build%20Disk/Checkout/b "
                + "three=/Volumes/Build%20Disk/Checkout/c",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: [
                "/Users/Alice/Project%20Space",
                "file:///Volumes/Build%20Disk/Checkout"
            ]
        )

        let output = try report.build()

        XCTAssertTrue(
            output.contains(
                "Operating System: one=<home>/a two=<home>/b three=<home>/c\n"
            )
        )
        XCTAssertFalse(output.contains("Project%"))
        XCTAssertFalse(output.contains("Build%"))
        XCTAssertFalse(output.contains("/Volumes/Build Disk/Checkout"))
    }

    func testRawEncodedAndMalformedNeighborVariantsAreAllRedacted() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "raw=/Users/Alice/private/a "
                + "encoded=/Users/Alice%2Fprivate/b%ZZ",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["/Users/Alice/private"]
        )

        let output = try report.build()

        XCTAssertTrue(output.contains("raw=<home>/a encoded=<home>/b%ZZ"))
        XCTAssertFalse(output.contains("Alice"))
    }

    func testExactlyEightPercentDecodingPassesSucceedAndNineFailClosed() throws {
        func encoded(_ value: String, passes: Int) -> String {
            (0..<passes).reduce(value) { result, _ in
                result.replacingOccurrences(of: "%", with: "%25")
                    .replacingOccurrences(of: "/", with: "%2F")
            }
        }

        let root = "/Users/Alice"
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "path=\(encoded(root, passes: 8))/file note=100%25",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: [root]
        )

        let output = try report.build()
        XCTAssertTrue(output.contains("Operating System: path=<home>/file note=100%25\n"))
        XCTAssertFalse(output.contains("Alice"))

        let tooDeep = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: encoded(root, passes: 9),
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: [root]
        )
        XCTAssertThrowsError(try tooDeep.build()) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .redactionDecodingTooDeep(maximumPasses: 8)
            )
        }
    }

    func testRecursivePercentDecodingStopsWhenStableAndHonorsDecodedByteLimit() throws {
        XCTAssertEqual(
            try ConfigurationReport.canonicalizedRedactionResultForTesting(
                "%25252FUsers%25252FAlice",
                maximumDecodedBytes: 64,
                maximumDecodingWork: 1_000,
                maximumDecodingPasses: 8
            ),
            "/Users/Alice"
        )
        XCTAssertEqual(
            try ConfigurationReport.canonicalizedRedactionResultForTesting(
                "malformed=%2G%",
                maximumDecodedBytes: 64,
                maximumDecodingWork: 1_000,
                maximumDecodingPasses: 8
            ),
            "malformed=%2G%"
        )
        XCTAssertThrowsError(
            try ConfigurationReport.canonicalizedRedactionResultForTesting(
                "%25252F",
                maximumDecodedBytes: 4,
                maximumDecodingWork: 1_000,
                maximumDecodingPasses: 8
            )
        ) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .redactionDecodedValueTooLarge(maximumBytes: 4)
            )
        }
    }

    func testRecursivePercentDecodingAcceptsExactWorkBudgetAndExhaustsOnLaterPass() throws {
        let source = "%25252FUsers%25252FAlice"
        let exactWork = 384

        XCTAssertEqual(
            try ConfigurationReport.canonicalizedRedactionResultForTesting(
                source,
                maximumDecodedBytes: 64,
                maximumDecodingWork: exactWork,
                maximumDecodingPasses: 8
            ),
            "/Users/Alice"
        )
        XCTAssertThrowsError(
            try ConfigurationReport.canonicalizedRedactionResultForTesting(
                source,
                maximumDecodedBytes: 64,
                maximumDecodingWork: exactWork - 1,
                maximumDecodingPasses: 8
            )
        ) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .redactionDecodingWorkLimitExceeded(maximumWork: exactWork - 1)
            )
        }
    }

    func testCanonicalSeparatorOnlyRootsAreRejectedBeforeMatching() {
        for root in ["%2F", "%252F", "%255C", "file:///", "file%3A%2F%2F%2F"] {
            let report = ConfigurationReport(
                appName: "App",
                appVersion: "1",
                buildVersion: "2",
                operatingSystem: "macOS /Users/example",
                architecture: "arm64",
                localeIdentifier: "en",
                sandboxState: .enabled,
                redactionRoots: [root]
            )

            XCTAssertThrowsError(try report.build(), root) {
                XCTAssertEqual($0 as? ConfigurationReportError, .invalidRedactionRoot(index: 0))
            }
        }
    }

    func testEncodedFileURLRootsGenerateCanonicalPathAliases() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "url=file:///Users/Alice/Project/a "
                + "path=/Users/Alice/Project/b "
                + "malformedRoot=/Users/Alice/Broken%ZZ/c malformed=%ZZ",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: [
                "file%3A%2F%2F%2FUsers%2FAlice%2FProject",
                "file:///Users/Alice/Broken%ZZ"
            ]
        )

        let output = try report.build()
        XCTAssertTrue(
            output.contains(
                "Operating System: url=<home>/a path=<home>/b "
                    + "malformedRoot=<home>/c malformed=%ZZ\n"
            )
        )
    }

    func testPathRootsGenerateEncodedFileURLAliases() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "raw=/Users/Alice/Project Space/a "
                + "encoded=/Users/Alice/Project%20Space/b "
                + "url=file:///Users/Alice/Project%20Space/c",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["/Users/Alice/Project Space"]
        )

        let output = try report.build()

        XCTAssertTrue(
            output.contains(
                "Operating System: raw=<home>/a encoded=<home>/b url=<home>/c\n"
            )
        )
        XCTAssertFalse(output.contains("Alice"))
    }

    func testEncodedFileURLReservedPathBytesDoNotTruncateRootAliases() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "one=file:///Users/Alice/Project%23Secret/a "
                + "two=/Users/Alice/Project#Secret/b "
                + "three=file:///Users/Alice/Query%3FSecret/c "
                + "four=/Users/Alice/Query?Secret/d "
                + "five=file:/Users/Alice/SingleSlash/e",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: [
                "file:///Users/Alice/Project%23Secret",
                "file:///Users/Alice/Query%3FSecret",
                "file:/Users/Alice/SingleSlash"
            ]
        )

        let output = try report.build()

        XCTAssertTrue(
            output.contains(
                "Operating System: one=<home>/a two=<home>/b "
                    + "three=<home>/c four=<home>/d five=<home>/e\n"
            )
        )
        XCTAssertFalse(output.contains("Alice"))
        XCTAssertFalse(output.contains("Secret"))
    }

    func testLiteralFileURLQueryAndFragmentRemainStructureNotPath() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "one=/Users/Alice/Fragment/file "
                + "two=/Users/Alice/Query/file",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: [
                "file:///Users/Alice/Fragment#mark",
                "file:///Users/Alice/Query?item=1"
            ]
        )

        let output = try report.build()

        XCTAssertTrue(output.contains("Operating System: one=<home>/file two=<home>/file\n"))
        XCTAssertFalse(output.contains("Alice"))
    }

    func testAuthorityOnlyFileURLQueryCannotCreatePathCatchAll() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "private=/Users/Alice/file",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["file://host?item=/Users/Alice"]
        )

        let output = try report.build()

        XCTAssertTrue(output.contains("Operating System: private=/Users/Alice/file\n"))
        XCTAssertFalse(output.contains("<home>"))
    }

    func testRedactionPreservesUnmatchedPercentEscapesExactly() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "note=100%25 path=%2FUsers%2FAlice/file malformed=%ZZ",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["/Users/Alice"]
        )

        let output = try report.build()
        XCTAssertTrue(
            output.contains("Operating System: note=100%25 path=<home>/file malformed=%ZZ\n")
        )
    }

    func testRedactionPreservesDeepUnmatchedEncodingBytesAroundMatch() throws {
        let before = "%2525F0%25259F%252599%252582"
        let encodedRoot = "%25252FUsers%25252FAlice"
        let after = "%252541%ZZ"
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "before=\(before) path=\(encodedRoot)/file after=\(after)",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["/Users/Alice"]
        )

        let output = try report.build()

        XCTAssertTrue(
            output.contains(
                "Operating System: before=\(before) path=<home>/file after=\(after)\n"
            )
        )
    }

    func testMalformedPercentDecodedUTF8DoesNotConsumeFollowingPrivatePath() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "malformed=%E0/Users/Alice/file",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["/Users/Alice"]
        )

        let output = try report.build()
        XCTAssertTrue(output.contains("Operating System: malformed=%E0<home>/file\n"))
        XCTAssertFalse(output.contains("Alice"))
    }

    func testOverlappingRedactionPatternsDoNotLeakSuffixes() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "root=/Users/alice/private/token "
                + "nested=/private/data/secret user=anna",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["/Users/alice", "/private", "/private/data"],
            usernames: ["alice/private", "ann", "anna"]
        )

        let output = try report.build()

        XCTAssertTrue(
            output.contains(
                "Operating System: root=<home>/token nested=<home>/secret user=<user>\n"
            ),
            output
        )
        XCTAssertFalse(output.contains("alice"))
        XCTAssertFalse(output.contains("private"))
        XCTAssertFalse(output.contains("anna"))
    }

    func testOverlappingAndAdjacentRangesMergeWithoutLeakingSuffixes() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "overlap=/Users/alice/private/token "
                + "adjacent=shared/private/token-tail",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["/Users/alice", "shared/private"],
            usernames: ["alice/private", "/token"]
        )

        let output = try report.build()

        XCTAssertTrue(
            output.contains("Operating System: overlap=<home> adjacent=<home>-tail\n")
        )
        for leakedSuffix in ["alice", "private", "token"] {
            XCTAssertFalse(output.contains(leakedSuffix))
        }
    }

    func testAdjacentExactAliasAndEncodedRangesEmitOneDeterministicLabel() throws {
        let cases: [(value: String, roots: [String], usernames: [String])] = [
            ("ABCD", ["AB"], ["CD"]),
            ("abCD", ["AB"], ["CD"]),
            ("%2FA%252FB", ["/A"], ["/B"])
        ]

        for testCase in cases {
            let result = try ConfigurationReport.redactionResultForTesting(
                testCase.value,
                roots: testCase.roots,
                usernames: testCase.usernames
            )
            XCTAssertEqual(result.value, "<home>", testCase.value)
            XCTAssertEqual(result.value.components(separatedBy: "<").count - 1, 1)
        }
    }

    func testFailureNodeOutputsAreInheritedForBothLabels() throws {
        let userFailure = try ConfigurationReport.redactionResultForTesting(
            "she",
            roots: ["sheX"],
            usernames: ["he"]
        )
        let homeFailure = try ConfigurationReport.redactionResultForTesting(
            "she",
            roots: ["he"],
            usernames: ["sheX"]
        )

        XCTAssertEqual(userFailure.value, "s<user>")
        XCTAssertEqual(homeFailure.value, "s<home>")
    }

    func testInvalidRedactionRootsReturnIndexedError() {
        let invalidRoots = ["", "/", "\\", "bad\u{7F}root"]

        for invalidRoot in invalidRoots {
            let report = ConfigurationReport(
                appName: "App",
                appVersion: "1",
                buildVersion: "2",
                operatingSystem: "macOS",
                architecture: "arm64",
                localeIdentifier: "en",
                sandboxState: .enabled,
                redactionRoots: ["/valid", invalidRoot]
            )

            XCTAssertThrowsError(try report.build()) {
                XCTAssertEqual($0 as? ConfigurationReportError, .invalidRedactionRoot(index: 1))
            }
        }
    }

    func testInvalidUsernamesReturnIndexedError() {
        let invalidUsernames = ["", "bad\nname", "bad\u{85}name", "%0A", "%250A"]

        for invalidUsername in invalidUsernames {
            let report = ConfigurationReport(
                appName: "App",
                appVersion: "1",
                buildVersion: "2",
                operatingSystem: "macOS",
                architecture: "arm64",
                localeIdentifier: "en",
                sandboxState: .enabled,
                usernames: ["valid", invalidUsername]
            )

            XCTAssertThrowsError(try report.build()) {
                XCTAssertEqual($0 as? ConfigurationReportError, .invalidUsername(index: 1))
            }
        }
    }

    func testRedactionPatternBoundsAcceptExactLimitsAndReturnSpecificErrors() throws {
        let exactPattern = String(repeating: "a", count: 4_096)
        let exactTotal = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            usernames: Array(repeating: exactPattern, count: 16)
        )
        XCTAssertNoThrow(try exactTotal.build())

        let oversizedPattern = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            usernames: [String(repeating: "a", count: 4_097)]
        )
        XCTAssertThrowsError(try oversizedPattern.build()) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .redactionPatternTooLarge(maximumBytes: 4_096)
            )
        }

        let oversizedTotal = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            usernames: Array(repeating: exactPattern, count: 17)
        )
        XCTAssertThrowsError(try oversizedTotal.build()) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .redactionPatternsTooLarge(maximumBytes: 64 * 1_024)
            )
        }
    }

    func testIndividualPatternCapAppliesBeforeCanonicalAndAliasMatcherGrowth() {
        let patterns = [
            String(repeating: "%41", count: 1_366),
            String(repeating: "İ", count: 2_048),
            String(repeating: "a\u{0344}", count: 1_365)
        ]

        XCTAssertEqual(patterns[2].utf8.count, 4_095)
        XCTAssertGreaterThan(
            patterns[2].precomposedStringWithCanonicalMapping.utf8.count,
            4_096
        )

        for pattern in patterns {
            let report = ConfigurationReport(
                appName: "App",
                appVersion: "1",
                buildVersion: "2",
                operatingSystem: "macOS",
                architecture: "arm64",
                localeIdentifier: "en",
                sandboxState: .enabled,
                usernames: [pattern]
            )

            XCTAssertThrowsError(try report.build()) {
                XCTAssertEqual(
                    $0 as? ConfigurationReportError,
                    .redactionPatternTooLarge(maximumBytes: 4_096)
                )
            }
        }
    }

    func testFoldedAliasAggregateCapIsEnforcedIndependently() throws {
        let expandingPattern =
            String(repeating: "a", count: 3_206)
            + "00"
            + String(repeating: "İ", count: 296)
        XCTAssertEqual(expandingPattern.utf8.count, 3_800)

        let exactAliasTotal = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            usernames: Array(repeating: expandingPattern, count: 16)
        )
        XCTAssertNoThrow(try exactAliasTotal.build())

        let oversizedAliasTotal = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            usernames: Array(repeating: expandingPattern, count: 17)
        )
        XCTAssertThrowsError(try oversizedAliasTotal.build()) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .redactionPatternsTooLarge(maximumBytes: 64 * 1_024)
            )
        }
    }

    func testRedactionLabelPriorityEscapingAndOutputBoundsAreDeterministic() throws {
        let unsafe = "\u{2028}\u{2029}\u{61C}\u{202E}\u{2066}\u{2069}"
        let expectedEscaped = "\\u{2028}\\u{2029}\\u{61C}\\u{202E}\\u{2066}\\u{2069}"
        let exactHomeReport = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "secret\(unsafe)",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["secret"],
            usernames: ["SECRET"]
        )
        let aliasHomeReport = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "secret\(unsafe)",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .enabled,
            redactionRoots: ["SECRET"],
            usernames: ["secret"]
        )

        let output = try exactHomeReport.build()

        XCTAssertEqual(try aliasHomeReport.build(), output)
        XCTAssertTrue(output.contains("Operating System: <home>\(expectedEscaped)\n"))
        XCTAssertFalse(output.unicodeScalars.contains { unsafe.unicodeScalars.contains($0) })

        let exactBounds = ConfigurationReportBounds(maximumOutputBytes: output.utf8.count)
        XCTAssertEqual(try exactHomeReport.build(bounds: exactBounds), output)
        XCTAssertThrowsError(
            try exactHomeReport.build(
                bounds: ConfigurationReportBounds(
                    maximumOutputBytes: output.utf8.count - 1
                ))
        ) {
            XCTAssertEqual(
                $0 as? ConfigurationReportError,
                .outputTooLarge(maximumBytes: output.utf8.count - 1)
            )
        }
    }

    func testCancellationStopsInsideFailureWalkAtObservedWorkBoundary() async {
        let pattern = String(repeating: "a", count: 4_095) + "b"
        let task = Task.detached {
            try ConfigurationReport.redactionResultForTesting(
                String(repeating: "a", count: 4_096) + "c",
                roots: [pattern],
                usernames: [],
                workObserver: { workCount in
                    if workCount == 4_096 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            )
        }

        do {
            _ = try await task.value
            XCTFail("Cancelled redaction unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testRepeatedPrefixRedactionWorkIsLinear() throws {
        let pattern = String(repeating: "a", count: 4_095) + "b"
        let shortValue = String(repeating: "a", count: 50_000) + "c"
        let longValue = String(repeating: "a", count: 100_000) + "c"
        let short = try ConfigurationReport.redactionResultForTesting(
            shortValue,
            roots: [pattern],
            usernames: []
        )
        let long = try ConfigurationReport.redactionResultForTesting(
            longValue,
            roots: [pattern],
            usernames: []
        )

        XCTAssertEqual(short.value, shortValue)
        XCTAssertEqual(long.value, longValue)
        XCTAssertEqual(short.workCount, 4 * 50_000 + 2)
        XCTAssertEqual(long.workCount, 4 * 100_000 + 2)
    }

    func testEmptyMatchersReturnWithoutRedactionWork() throws {
        let value = String(repeating: "x", count: 4 * 1_024 * 1_024 + 1)
        let result = try ConfigurationReport.redactionResultForTesting(
            value,
            roots: [],
            usernames: []
        )

        XCTAssertEqual(result.value, value)
        XCTAssertEqual(result.workCount, 0)
    }

    func testDenseMatchesCoalesceWithoutPerByteRangeStorage() throws {
        let value = String(repeating: "x", count: 100_000)
        let result = try ConfigurationReport.redactionResultForTesting(
            value,
            roots: ["x"],
            usernames: []
        )

        XCTAssertEqual(result.value, "<home>")
        XCTAssertEqual(result.workCount, 4 * value.utf8.count - 2)
    }

    func testDisjointDenseMatchesUseCompactSparseRanges() throws {
        let value = String(repeating: "x_", count: 50_000)
        let result = try ConfigurationReport.redactionResultForTesting(
            value,
            roots: ["x"],
            usernames: []
        )

        XCTAssertEqual(result.value, String(repeating: "<home>_", count: 50_000))
        XCTAssertEqual(result.workCount, 3 * value.utf8.count)
    }

    func testOutputContainsOnlyInjectedValuesAndNoAmbientEnvironment() throws {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "Injected OS",
            architecture: "Injected Arch",
            localeIdentifier: "tr_TR_POSIX",
            sandboxState: .unknown
        )

        let expected = [
            "App Configuration Report",
            "",
            "Application",
            "Name: App",
            "Version: 1",
            "Build: 2",
            "",
            "System",
            "Operating System: Injected OS",
            "Architecture: Injected Arch",
            "Locale: tr_TR_POSIX",
            "Sandbox: unknown",
            "",
            "Comparison Limits",
            "(none)",
            "",
            "Features",
            "(none)",
            ""
        ].joined(separator: "\n")

        XCTAssertEqual(try report.build(), expected)
    }

    func testCurrentPublicValueAPIIsSendable() {
        let report = ConfigurationReport(
            appName: "App",
            appVersion: "1",
            buildVersion: "2",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en",
            sandboxState: .unknown
        )
        let builder: ConfigurationReportBuilder = report

        requireSendable(report)
        requireSendable(ConfigurationReportRecord(name: "Count", value: 3))
        requireSendable(ConfigurationReportBounds.default)
        requireSendable(ConfigurationReportError.outputTooLarge(maximumBytes: 1))
        requireSendable(ConfigurationReportSandboxState.unknown)
        XCTAssertEqual(builder, report)
        XCTAssertEqual(ConfigurationReportRecord(name: "Count", value: 3).value, "3")
        XCTAssertEqual(ConfigurationReportSandboxState(isSandboxed: true), .enabled)
        XCTAssertEqual(ConfigurationReportSandboxState(isSandboxed: false), .disabled)
        XCTAssertEqual(ConfigurationReportSandboxState(isSandboxed: nil), .unknown)
    }

    private func requireSendable<T: Sendable>(_: T) {}
}
