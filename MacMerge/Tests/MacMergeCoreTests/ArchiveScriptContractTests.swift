import Darwin
import Foundation
import XCTest

final class ArchiveScriptContractTests: XCTestCase {
    private struct ProcessResult {
        let status: Int32
        let standardOutput: String
        let standardError: String
    }

    private struct HermeticHarness {
        let root: URL
        let scriptURL: URL
        let entitlementsURL: URL
        let invocationLogURL: URL
        let securitySentinelURL: URL
    }

    private enum ProcessRunError: Error, CustomStringConvertible {
        case timedOut(executable: String, arguments: [String])
        case pipeDrainTimedOut

        var description: String {
            switch self {
            case .timedOut(let executable, let arguments):
                return "Process timed out: \(([executable] + arguments).joined(separator: " "))"
            case .pipeDrainTimedOut:
                return "Process pipes did not reach EOF after termination"
            }
        }
    }

    private final class PipeCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Data, Error>?

        func drain(_ handle: FileHandle, in group: DispatchGroup) {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let result = Result { try handle.readToEnd() ?? Data() }
                self.lock.lock()
                self.result = result
                self.lock.unlock()
            }
        }

        func data() throws -> Data {
            lock.lock()
            defer { lock.unlock() }
            return try XCTUnwrap(result, "Pipe drain completed without publishing data").get()
        }
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var scriptURL: URL {
        packageRoot.appendingPathComponent("Scripts/archive-app.sh")
    }

    func testShellSyntaxAndStrictHelpArity() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let startupSentinel = temporaryDirectory.appendingPathComponent("shell-startup-ran")
        let startupFile = temporaryDirectory.appendingPathComponent("startup.sh")
        try "#!/bin/bash\n/usr/bin/touch \(shellQuote(startupSentinel.path))\n".write(
            to: startupFile,
            atomically: true,
            encoding: .utf8
        )
        let hostileEnvironment = [
            "BASH_ENV": startupFile.path,
            "ENV": startupFile.path,
            "CDPATH": temporaryDirectory.path,
        ]

        let sanitizedEnvironment = try run(
            "/usr/bin/env",
            arguments: [],
            environment: hostileEnvironment
        )
        for variable in hostileEnvironment.keys {
            XCTAssertFalse(
                sanitizedEnvironment.standardOutput.split(separator: "\n").contains {
                    $0.hasPrefix("\(variable)=")
                },
                "\(variable) escaped minimal process-environment stripping"
            )
        }

        let syntax = try run(
            "/bin/bash",
            arguments: ["-n", scriptURL.path],
            environment: hostileEnvironment
        )
        XCTAssertEqual(syntax.status, 0, syntax.standardError)
        XCTAssertEqual(syntax.standardOutput, "")

        for flag in ["-h", "--help"] {
            let help = try run(
                "/bin/bash",
                arguments: [scriptURL.path, flag],
                environment: hostileEnvironment
            )
            XCTAssertEqual(help.status, 0, "\(flag): \(help.standardError)")
            XCTAssertEqual(
                help.standardOutput.split(separator: "\n", omittingEmptySubsequences: false).first,
                "Usage: archive-app.sh [--check] [--help]"
            )
            XCTAssertEqual(help.standardError, "")

            let extraArgument = try run(
                "/bin/bash",
                arguments: [scriptURL.path, flag, "unexpected"],
                environment: hostileEnvironment
            )
            XCTAssertEqual(extraArgument.status, 2, flag)
            XCTAssertEqual(extraArgument.standardOutput, "", flag)
            XCTAssertEqual(extraArgument.standardError, "archive-app.sh: too many arguments\n", flag)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: startupSentinel.path),
            "BASH_ENV, ENV, or CDPATH escaped minimal process-environment stripping"
        )
    }

    func testEntitlementsRequireTypedBooleanValuesAndExactApprovedKeys() throws {
        let validEntitlements: [String: Any] = [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.files.bookmarks.app-scope": true,
            "com.apple.security.files.user-selected.read-write": true,
        ]
        var missingEntitlement = validEntitlements
        missingEntitlement.removeValue(forKey: "com.apple.security.files.bookmarks.app-scope")
        var cases: [(name: String, entitlements: [String: Any], diagnostic: String)] = [
            (
                "extra key",
                validEntitlements.merging(["com.apple.security.network.client": true]) { _, new in new },
                "entitlements must contain exactly the approved sandbox keys"
            ),
            (
                "missing key",
                missingEntitlement,
                "entitlements must contain exactly the approved sandbox keys"
            ),
        ]
        for entitlement in validEntitlements.keys.sorted() {
            for invalidValue: Any in ["true", false] {
                var invalidEntitlements = validEntitlements
                invalidEntitlements[entitlement] = invalidValue
                cases.append(
                    (
                        "\(entitlement)=\(invalidValue)",
                        invalidEntitlements,
                        "required Boolean entitlement is not enabled: \(entitlement)"
                    )
                )
            }
        }

        for testCase in cases {
            let harness = try makeHermeticHarness()
            defer { try? FileManager.default.removeItem(at: harness.root) }
            try writePropertyList(testCase.entitlements, to: harness.entitlementsURL)

            let result = try runArchive(harness, arguments: ["--check"])

            XCTAssertEqual(result.status, 2, testCase.name)
            XCTAssertEqual(result.standardOutput, "", testCase.name)
            XCTAssertTrue(
                result.standardError.contains(testCase.diagnostic),
                "\(testCase.name): \(result.standardError)"
            )
            XCTAssertFalse(try invocationLog(harness).contains("xcodebuild:"), testCase.name)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: harness.securitySentinelURL.path),
                testCase.name
            )
        }
    }

    func testSchemeDiscoveryAcceptsOnlyReportedJSONRoots() throws {
        let executableOnlyDiagnostic =
            "SwiftPM executable-only archives are unsupported; add an Xcode application target/shared scheme."

        for root in ["package", "workspace", "project"] {
            let harness = try makeHermeticHarness(
                schemeListJSON: #"{"\#(root)":{"schemes":["MacMerge"]}}"#
            )
            defer { try? FileManager.default.removeItem(at: harness.root) }

            let result = try runArchive(harness, arguments: ["--check"])

            XCTAssertEqual(result.status, 2, root)
            XCTAssertTrue(result.standardError.contains(executableOnlyDiagnostic), root)
            let log = try invocationLog(harness)
            XCTAssertTrue(log.contains("xcodebuild:-list -json"), root)
            XCTAssertTrue(log.contains("-showBuildSettings"), root)
            XCTAssertFalse(FileManager.default.fileExists(atPath: harness.securitySentinelURL.path), root)
        }

        let harness = try makeHermeticHarness(
            schemeListJSON: #"{"unreported":{"schemes":["MacMerge"]}}"#
        )
        defer { try? FileManager.default.removeItem(at: harness.root) }

        let result = try runArchive(harness, arguments: ["--check"])

        XCTAssertEqual(result.status, 2)
        XCTAssertEqual(result.standardOutput, "")
        XCTAssertEqual(result.standardError, "archive-app.sh: Xcode did not report package schemes\n")
        XCTAssertFalse(try invocationLog(harness).contains("-showBuildSettings"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.securitySentinelURL.path))
    }

    func testDeveloperIDValidationPinsOIDTeamAndCertificateHashAtCallSites() throws {
        let source = try scriptSource()
        let validator = try sourceSection(
            in: source,
            from: "validate_developer_id_code() {",
            through: "\n}\n\n[[ $# -le 1 ]]"
        )
        assertOrdered(
            [
                #"requirement="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf = H\"$identity_hash\"""#,
                #"codesign --verify --strict --architecture "$architecture" -R="$requirement" "$code""#,
                #"signature=$(codesign --display --architecture "$architecture" --verbose=4 "$code" 2>&1)"#,
                #"[[ "$signature" == *"Runtime Version="* ]]"#,
                #"[[ "$signature" == *"Timestamp="* ]]"#,
                #"[[ "$team" == "$identity_team" ]]"#,
            ],
            in: validator
        )

        let certificateValidation = try sourceSection(
            in: source,
            from: #"security find-certificate -a -c "Developer ID Application:" -p"#,
            through: "development_team=$identity_team"
        )
        assertOrdered(
            [
                "Digest::SHA1.hexdigest(der).upcase == wanted",
                "security verify-cert -q -L -p codeSign",
                "1\\.2\\.840\\.113635\\.100\\.6\\.1\\.13",
                #"[[ "$identity_team" =~ ^[[:alnum:]]{10}$ ]]"#,
                #"[[ -z "$development_team" || "$development_team" == "$identity_team" ]]"#,
            ],
            in: certificateValidation
        )

        let archiveValidation = try sourceSection(
            in: source,
            from: #"codesign --verify --deep --strict --all-architectures --verbose=2 "$app_bundle""#,
            through: #"validate_developer_id_code "$app_bundle" "$architecture" "archived application""#
        )
        assertOrdered(
            [
                #"validate_developer_id_code "$code" "$architecture" "archived code""#,
                #"validate_developer_id_code "$bundle" "$architecture" "archived code bundle""#,
                #"validate_developer_id_code "$app_bundle" "$architecture" "archived application""#,
            ],
            in: archiveValidation
        )
    }

    func testArchiveApplicationPropertiesAreCrossCheckedAtUseSites() throws {
        let source = try scriptSource()
        let metadataValidation = try sourceSection(
            in: source,
            from: #"archive_info="$archive_path/Info.plist""#,
            through: #"[[ "$app_identifier" == "$archive_identifier" ]] || die "archive application identifier metadata does not match app bundle""#
        )
        assertOrdered(
            [
                #"application_path=$(plist_extract ApplicationProperties.ApplicationPath string "$archive_info" || true)"#,
                #"[[ "$application_path" == "Applications/MacMerge.app" ]]"#,
                #"archive_identifier=$(plist_extract ApplicationProperties.CFBundleIdentifier string "$archive_info" || true)"#,
                #"[[ -n "$archive_identifier" ]]"#,
                #"archive_team=$(plist_extract ApplicationProperties.Team string "$archive_info" || true)"#,
                #"[[ "$archive_team" == "$identity_team" ]]"#,
                #"archive_identity=$(plist_extract ApplicationProperties.SigningIdentity string "$archive_info" || true)"#,
                #"[[ "$archive_identity" == "$identity_name" ]]"#,
                #"app_info="$app_bundle/Contents/Info.plist""#,
                #"validate_contained_path "$app_bundle_canonical" "$app_info" "archived application Info.plist""#,
                #"app_identifier=$(plist_extract CFBundleIdentifier string "$app_info" || true)"#,
                #"[[ "$app_identifier" == "$archive_identifier" ]]"#,
            ],
            in: metadataValidation
        )

        let architectureValidation = try sourceSection(
            in: source,
            from: #"app_executable=$(plist_extract CFBundleExecutable string "$app_info" || true)"#,
            through: "archive application architecture metadata does not match app executable"
        )
        assertOrdered(
            [
                #"app_architectures=$(xcrun lipo -archs "$app_executable_path""#,
                #"archive_architectures=$(plist_extract ApplicationProperties.Architectures array "$archive_info" || true)"#,
                #"archive_architecture_array+=("$architecture")"#,
                #"read -r -a app_architecture_array <<<"$app_architectures""#,
                #"printf '%s\n' "${archive_architecture_array[@]}" | sort -u"#,
                #"printf '%s\n' "${app_architecture_array[@]}" | sort -u"#,
                "archive application architecture metadata does not match app executable",
            ],
            in: architectureValidation
        )
    }

    func testNestedBundlesRouteMachOExecutablesThroughDeveloperIDValidation() throws {
        let source = try scriptSource()
        let nestedBundleValidation = try sourceSection(
            in: source,
            from: #"while IFS= read -r -d '' bundle; do"#,
            through: #"done <"$archive_bundles""#
        )
        assertOrdered(
            [
                #"bundle_canonical=$(validate_contained_path "$app_bundle_canonical" "$bundle" "nested code bundle")"#,
                #"if [[ "$bundle" == *.framework ]]"#,
                #"bundle_info="$bundle/Resources/Info.plist""#,
                #"bundle_info="$bundle/Info.plist""#,
                #"bundle_info="$bundle/Contents/Info.plist""#,
                #"[[ -f "$bundle_info" ]] || die "nested code bundle Info.plist is missing: $bundle""#,
                #"validate_contained_path "$bundle_canonical" "$bundle_info" "nested code bundle Info.plist""#,
                #"bundle_executable=$(plist_extract CFBundleExecutable string "$bundle_info" || true)"#,
                #"if [[ -z "$bundle_executable" ]]"#,
                #"[[ "$bundle" == *.bundle ]] || die "nested code bundle CFBundleExecutable is missing: $bundle""#,
                "continue",
                #"validate_bundle_executable_name "$bundle_executable" "$bundle""#,
                #"[[ -f "$bundle_executable_path" ]] || die "nested code bundle executable is missing: $bundle""#,
                #"validate_contained_path "$bundle_canonical" "$bundle_executable_path""#,
                #"validate_executable_mode "$bundle_executable_path" "nested code bundle executable""#,
                #"architectures=$(xcrun lipo -archs "$bundle_executable_path""#,
                #"validate_developer_id_code "$bundle" "$architecture" "archived code bundle""#,
            ],
            in: nestedBundleValidation
        )
        let nestedBundleDiscovery = try sourceSection(
            in: source,
            from: #"find "$app_bundle/Contents" -mindepth 1 -type d"#,
            through: #"die "could not enumerate nested code bundles""#
        )
        for extensionName in ["*.app", "*.appex", "*.framework", "*.plugin", "*.xpc", "*.bundle"] {
            XCTAssertTrue(
                nestedBundleDiscovery.contains("-name '\(extensionName)'"),
                "Nested bundle discovery omitted \(extensionName)"
            )
        }
    }

    func testNestedFrameworkCannotBypassValidationWithoutCFBundleExecutable() throws {
        let source = try scriptSource()
        let nestedBundleValidation = try sourceSection(
            in: source,
            from: #"while IFS= read -r -d '' bundle; do"#,
            through: #"done <"$archive_bundles""#
        )
        let nestedBundleDiscovery = try sourceSection(
            in: source,
            from: #"find "$app_bundle/Contents" -mindepth 1 -type d"#,
            through: #"die "could not enumerate nested code bundles""#
        )
        XCTAssertTrue(nestedBundleDiscovery.contains("-name '*.framework'"))
        XCTAssertFalse(
            nestedBundleValidation.contains(#"[[ -n "$bundle_executable" ]] || continue"#),
            "Discovered code bundles must reject missing CFBundleExecutable instead of bypassing validation"
        )
        XCTAssertTrue(
            nestedBundleValidation.contains(
                #"[[ "$bundle" == *.bundle ]] || die "nested code bundle CFBundleExecutable is missing: $bundle""#
            )
        )
        XCTAssertTrue(nestedBundleValidation.contains(#"bundle_info="$bundle/Resources/Info.plist""#))
        XCTAssertTrue(nestedBundleValidation.contains(#"bundle_executable_path_prefix="$bundle""#))
        XCTAssertTrue(nestedBundleValidation.contains(#"validate_bundle_executable_name "$bundle_executable" "$bundle""#))
        XCTAssertTrue(
            nestedBundleValidation.contains(
                #"validate_contained_path "$bundle_canonical" "$bundle_executable_path""#
            )
        )
    }

    func testExecutableOnlyPackageArchiveIsRejectedBeforeSigning() throws {
        let harness = try makeHermeticHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }

        let result = try runArchive(harness, arguments: ["--check"])

        XCTAssertEqual(result.status, 2)
        XCTAssertEqual(result.standardOutput, "")
        XCTAssertEqual(
            result.standardError,
            "archive-app.sh: Xcode scheme 'MacMerge' does not archive MacMerge as an application. "
                + "SwiftPM executable-only archives are unsupported; add an Xcode application target/shared scheme.\n"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: harness.securitySentinelURL.path),
            "security find-identity ran before executable-only archive rejection"
        )
        let log = try invocationLog(harness)
        XCTAssertTrue(log.contains("xcodebuild:-list -json"))
        XCTAssertTrue(log.contains("CODE_SIGNING_ALLOWED=NO archive"))
        XCTAssertFalse(log.contains("security:"))

        let source = try scriptSource()
        let unsignedPreflight = try sourceSection(
            in: source,
            from: #"if ! xcodebuild \"#,
            through: #"identity_output=$(security find-identity -v -p codesigning 2>&1)"#
        )
        assertOrdered(
            [
                "-showBuildSettings",
                "CODE_SIGNING_ALLOWED=NO",
                #"candidate_type=$(plist_extract "$index.buildSettings.PRODUCT_TYPE" string "$build_settings" || true)"#,
                #""$candidate_type" == "com.apple.product-type.application""#,
                "SwiftPM executable-only archives are unsupported",
                "security find-identity",
            ],
            in: unsignedPreflight
        )

        let signedSettingsValidation = try sourceSection(
            in: source,
            from: "build_overrides=(",
            through: "SwiftPM executable-only archives are unsupported; add an Xcode application target/shared scheme."
        )
        assertOrdered(
            [
                "-showBuildSettings",
                #"candidate_type=$(plist_extract "$index.buildSettings.PRODUCT_TYPE" string "$build_settings" || true)"#,
                #""$candidate_type" == "com.apple.product-type.application""#,
                #"[[ -n "$app_settings_index" ]]"#,
                "SwiftPM executable-only archives are unsupported",
            ],
            in: signedSettingsValidation
        )
    }

    private func makeHermeticHarness(
        schemeListJSON: String = #"{"package":{"schemes":["MacMerge"]}}"#,
        preflightSettingsJSON: String =
            #"[{"buildSettings":{"PRODUCT_NAME":"MacMerge","PRODUCT_TYPE":"com.apple.product-type.tool"}}]"#
    ) throws -> HermeticHarness {
        let root = try makeTemporaryDirectory()
        let scriptsDirectory = root.appendingPathComponent("Scripts", isDirectory: true)
        let packagingDirectory = root.appendingPathComponent("Packaging", isDirectory: true)
        let stubsDirectory = root.appendingPathComponent("stubs", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stubsDirectory, withIntermediateDirectories: true)

        let originalSource = try scriptSource()
        let pathAssignment = "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
        guard originalSource.components(separatedBy: pathAssignment).count == 2 else {
            throw NSError(
                domain: "ArchiveScriptContractTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "archive-app.sh PATH assignment changed"]
            )
        }
        let harnessSource = originalSource.replacingOccurrences(
            of: pathAssignment,
            with: "PATH=\(shellQuote(stubsDirectory.path))"
        )
        let harnessScriptURL = scriptsDirectory.appendingPathComponent("archive-app.sh")
        try harnessSource.write(to: harnessScriptURL, atomically: true, encoding: .utf8)
        try "// Hermetic archive contract fixture\n".write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let entitlementsURL = packagingDirectory.appendingPathComponent("MacMerge.entitlements")
        try writePropertyList(
            [
                "com.apple.security.app-sandbox": true,
                "com.apple.security.files.bookmarks.app-scope": true,
                "com.apple.security.files.user-selected.read-write": true,
            ],
            to: entitlementsURL
        )

        let invocationLogURL = root.appendingPathComponent("invocations.log")
        let securitySentinelURL = root.appendingPathComponent("security-ran")
        for (name, destination) in [
            ("dirname", "/usr/bin/dirname"),
            ("file", "/usr/bin/file"),
            ("find", "/usr/bin/find"),
            ("mktemp", "/usr/bin/mktemp"),
            ("plutil", "/usr/bin/plutil"),
            ("rm", "/bin/rm"),
            ("ruby", "/usr/bin/ruby"),
            ("uname", "/usr/bin/uname"),
        ] {
            try FileManager.default.createSymbolicLink(
                at: stubsDirectory.appendingPathComponent(name),
                withDestinationURL: URL(fileURLWithPath: destination)
            )
        }
        try writeExecutableStub(
            named: "xcrun",
            in: stubsDirectory,
            body: """
                printf '%s\\n' "xcrun:$*" >>\(shellQuote(invocationLogURL.path))
                if (( $# == 7 )) && [[ "$1" == swift && "$2" == package && "$3" == --package-path && \
                    "$4" == \(shellQuote(root.path)) && "$5" == describe && "$6" == --type && "$7" == json ]]; then
                    printf '%s\\n' \(shellQuote(Self.packageDescriptionJSON))
                elif (( $# == 3 )) && [[ "$1" == --sdk && "$2" == macosx && "$3" == --show-sdk-path ]]; then
                    exec /usr/bin/xcrun "$@"
                else
                    exit 97
                fi
                """
        )
        try writeExecutableStub(
            named: "xcodebuild",
            in: stubsDirectory,
            body: """
                printf '%s\\n' "xcodebuild:$*" >>\(shellQuote(invocationLogURL.path))
                if (( $# == 2 )) && [[ "$1" == -list && "$2" == -json ]]; then
                    printf '%s\\n' \(shellQuote(schemeListJSON))
                elif (( $# == 10 )) && [[ "$1" == -scheme && "$2" == MacMerge && \
                    "$3" == -configuration && "$4" == Release && "$5" == -destination && \
                    "$6" == generic/platform=macOS && "$7" == -showBuildSettings && "$8" == -json && \
                    "$9" == CODE_SIGNING_ALLOWED=NO && "${10}" == archive ]]; then
                    printf '%s\\n' \(shellQuote(preflightSettingsJSON))
                else
                    exit 97
                fi
                """
        )
        try writeExecutableStub(
            named: "security",
            in: stubsDirectory,
            body: """
                : >\(shellQuote(securitySentinelURL.path))
                printf '%s\\n' "security:$*" >>\(shellQuote(invocationLogURL.path))
                exit 98
                """
        )
        for command in ["codesign", "openssl", "shasum"] {
            try writeExecutableStub(named: command, in: stubsDirectory, body: "exit 96")
        }

        return HermeticHarness(
            root: root,
            scriptURL: harnessScriptURL,
            entitlementsURL: entitlementsURL,
            invocationLogURL: invocationLogURL,
            securitySentinelURL: securitySentinelURL
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacMergeArchiveScriptTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func writeExecutableStub(named name: String, in directory: URL, body: String) throws {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/bash\nset -euo pipefail\n\(body)\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func writePropertyList(_ value: Any, to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }

    private func runArchive(
        _ harness: HermeticHarness,
        arguments: [String]
    ) throws -> ProcessResult {
        try run(
            "/bin/bash",
            arguments: [harness.scriptURL.path] + arguments,
            environment: [
                "HOME": harness.root.path,
                "TMPDIR": harness.root.path,
                "OSTYPE": "darwin",
                "SIGN_IDENTITY": "Developer ID Application: Archive Contract (ABCDEFGHIJ)",
                "ENTITLEMENTS": harness.entitlementsURL.path,
            ]
        )
    }

    private func invocationLog(_ harness: HermeticHarness) throws -> String {
        guard FileManager.default.fileExists(atPath: harness.invocationLogURL.path) else {
            return ""
        }
        return try String(contentsOf: harness.invocationLogURL, encoding: .utf8)
    }

    private func scriptSource() throws -> String {
        try String(contentsOf: scriptURL, encoding: .utf8)
    }

    private func sourceSection(
        in source: String,
        from startToken: String,
        through endToken: String
    ) throws -> String {
        let start = try XCTUnwrap(
            source.range(of: startToken),
            "archive-app.sh contract start token missing: \(startToken)"
        )
        let end = try XCTUnwrap(
            source.range(of: endToken, range: start.lowerBound..<source.endIndex),
            "archive-app.sh contract end token missing: \(endToken)"
        )
        return String(source[start.lowerBound..<end.upperBound])
    }

    private func assertOrdered(
        _ tokens: [String],
        in source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var remainder = source[...]
        for token in tokens {
            guard let range = remainder.range(of: token) else {
                XCTFail(
                    "archive-app.sh ordered contract token missing: \(token)",
                    file: file,
                    line: line
                )
                return
            }
            remainder = remainder[range.upperBound...]
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func minimalEnvironment(_ additions: [String: String]) -> [String: String] {
        let strippedVariables: Set<String> = ["BASH_ENV", "ENV", "CDPATH"]
        var environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "C",
            "LC_ALL": "C",
        ]
        for (name, value) in additions where !strippedVariables.contains(name) {
            environment[name] = value
        }
        return environment
    }

    private func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        timeout: DispatchTimeInterval = .seconds(10)
    ) throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let outputCapture = PipeCapture()
        let errorCapture = PipeCapture()
        let drains = DispatchGroup()
        let terminated = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            "-MPOSIX",
            "-e",
            "defined(POSIX::setsid()) or die \"setsid failed: $!\"; "
                + "exec {$ARGV[0]} @ARGV; die \"exec failed: $!\";",
            executable,
        ] + arguments
        process.environment = minimalEnvironment(environment)
        process.currentDirectoryURL = packageRoot
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { _ in terminated.signal() }
        outputCapture.drain(standardOutput.fileHandleForReading, in: drains)
        errorCapture.drain(standardError.fileHandleForReading, in: drains)

        do {
            try process.run()
        } catch {
            try? standardOutput.fileHandleForWriting.close()
            try? standardError.fileHandleForWriting.close()
            _ = drains.wait(timeout: .now() + .seconds(1))
            throw error
        }
        try standardOutput.fileHandleForWriting.close()
        try standardError.fileHandleForWriting.close()

        guard terminated.wait(timeout: .now() + timeout) == .success else {
            Darwin.kill(-process.processIdentifier, SIGKILL)
            _ = terminated.wait(timeout: .now() + .seconds(1))
            if drains.wait(timeout: .now() + .seconds(1)) != .success {
                try? standardOutput.fileHandleForReading.close()
                try? standardError.fileHandleForReading.close()
                _ = drains.wait(timeout: .now() + .seconds(1))
            }
            throw ProcessRunError.timedOut(executable: executable, arguments: arguments)
        }
        process.waitUntilExit()
        guard drains.wait(timeout: .now() + .seconds(2)) == .success else {
            Darwin.kill(-process.processIdentifier, SIGKILL)
            try? standardOutput.fileHandleForReading.close()
            try? standardError.fileHandleForReading.close()
            throw ProcessRunError.pipeDrainTimedOut
        }

        return ProcessResult(
            status: process.terminationStatus,
            standardOutput: String(decoding: try outputCapture.data(), as: UTF8.self),
            standardError: String(decoding: try errorCapture.data(), as: UTF8.self)
        )
    }

    private static let packageDescriptionJSON =
        #"{"name":"MacMerge","products":[{"name":"MacMerge","type":{"executable":null}}]}"#
}
