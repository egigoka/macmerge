import Foundation
import XCTest

@testable import MacMergeCore

// Lane 7: differential-oracle fixture coverage lock, discovery, audit, and CI gate wiring.
final class DiffOracleFixtureCoverageTests: XCTestCase {
    // MARK: Helpers

    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let repositoryRoot = packageRoot.deletingLastPathComponent()

    private func hex(_ character: Character) -> String { String(repeating: character, count: 64) }
    private func oidText(_ character: Character) -> String { String(repeating: character, count: 40) }
    private func oid(_ character: Character) -> DiffOracleGitObjectID { try! DiffOracleGitObjectID(oidText(character)) }
    private func sha(_ character: Character) -> DiffOracleSHA256 { try! DiffOracleSHA256(hex: hex(character)) }

    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for url in temporaryDirectories { try? FileManager.default.removeItem(at: url) }
        temporaryDirectories = []
        super.tearDown()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiffOracleFixtureCoverageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let url = Self.repositoryRoot.appendingPathComponent(relativePath)
        return try XCTUnwrap(String(data: try Data(contentsOf: url), encoding: .utf8), relativePath)
    }

    private func headerLines(
        format: String? = "1",
        commit: String? = nil,
        tree: String? = nil,
        wrapperTree: String? = nil,
        alignmentPath: String? = "MacMerge/Sources/MacMergeCore/LineDiff.swift",
        fingerprint: String? = nil
    ) -> [String] {
        var lines: [String] = []
        if let format { lines.append("format \(format)") }
        lines.append("fixture-winmerge-commit \(commit ?? oidText("1"))")
        lines.append("fixture-xdiff-tree \(tree ?? oidText("2"))")
        lines.append(wrapperTree ?? "diffwrapper-tree files=1 sha256=\(hex("3"))")
        if let alignmentPath { lines.append("alignment-path \(alignmentPath)") }
        lines.append("alignment-fingerprint \(fingerprint ?? hex("4"))")
        return lines
    }

    private func lockText(_ extra: [String] = [], header: [String]? = nil) -> String {
        ((header ?? headerLines()) + extra).joined(separator: "\n") + "\n"
    }

    private func goldenFields(
        source: String = "diffwrapper:DiffWrapper.A",
        commit: String? = nil,
        path: String = "MacMerge/DiffOracle/goldens/a.json"
    ) -> [String: String] {
        [
            "source": source,
            "winmerge-commit": commit ?? oidText("1"),
            "xdiff-tree": oidText("2"),
            "libxdiff-commit": oidText("5"),
            "libxdiff-tree": oidText("6"),
            "nested-libxdiff-commit": oidText("7"),
            "nested-libxdiff-tree": oidText("8"),
            "oracle-executable": hex("9"),
            "generator-version": "gen-1.0",
            "generator-executable": hex("a"),
            "generator-schema": hex("b"),
            "generator-configuration": hex("c"),
            "architecture": "x86_64",
            "build-configuration": "Release",
            "alignment": hex("4"),
            "path": path,
            "sha256": hex("d")
        ]
    }

    private func goldenLine(id: String = "g1", fields: [String: String]) -> String {
        let ordered = DiffOracleCoverageLock.goldenFieldKeys.compactMap { key in fields[key].map { "\(key)=\($0)" } }
        return (["golden", id] + ordered).joined(separator: " ")
    }

    private func assertMalformed(
        _ text: String,
        line expectedLine: Int? = nil,
        containing fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try DiffOracleCoverageLock.parse(text), file: file, line: line) { error in
            guard case .malformedLine(let lineNumber, let reason)? = error as? DiffOracleCoverageLockError else {
                return XCTFail("expected malformedLine, got \(error)", file: file, line: line)
            }
            if let expectedLine { XCTAssertEqual(lineNumber, expectedLine, file: file, line: line) }
            XCTAssertTrue(reason.contains(fragment), "reason '\(reason)' lacks '\(fragment)'", file: file, line: line)
        }
    }

    private func provenance(commit: Character = "1", tree: Character = "2") -> DiffOracleGoldenProvenance {
        DiffOracleGoldenProvenance(
            winMergeCommit: oid(commit),
            windowsXDiffTree: oid(tree),
            topLevelLibXDiffCommit: oid("5"),
            topLevelLibXDiffTree: oid("6"),
            nestedLibXDiffCommit: oid("7"),
            nestedLibXDiffTree: oid("8"),
            oracleExecutableSHA256: sha("9"),
            generatorVersion: try! DiffOracleIdentifier("gen-1.0"),
            generatorExecutableSHA256: sha("a"),
            generatorSchemaSHA256: sha("b"),
            generatorConfigurationSHA256: sha("c"),
            architecture: try! DiffOracleIdentifier("x86_64"),
            buildConfiguration: try! DiffOracleIdentifier("Release")
        )
    }

    private func golden(
        id: String = "g1",
        source: DiffOracleFixtureSource = .diffWrapper("DiffWrapper.A"),
        commit: Character = "1",
        tree: Character = "2",
        alignment: Character = "4",
        sha256: Character = "d"
    ) -> DiffOracleCoverageLock.Golden {
        DiffOracleCoverageLock.Golden(
            id: id,
            source: source,
            provenance: provenance(commit: commit, tree: tree),
            alignmentFingerprint: sha(alignment),
            path: "MacMerge/DiffOracle/goldens/\(id).json",
            sha256: sha(sha256)
        )
    }

    private let wrapperDigest = DiffOracleContentDigest(fileCount: 1, sha256: String(repeating: "3", count: 64))

    private func memoryLock(
        tests: [DiffOracleCoverageLock.DiffWrapperTest]? = nil,
        data: [DiffOracleCoverageLock.TestingDataEntry]? = nil,
        goldens: [DiffOracleCoverageLock.Golden] = []
    ) -> DiffOracleCoverageLock {
        DiffOracleCoverageLock(
            fixtureWinMergeCommit: oid("1"),
            fixtureXDiffTree: oid("2"),
            diffWrapperDirectory: wrapperDigest,
            alignmentPaths: ["MacMerge/Sources/MacMergeCore/LineDiff.swift"],
            alignmentFingerprint: hex("4"),
            diffWrapperTests: tests ?? [.init(id: "DiffWrapper.A", rightFileSiteCount: 2, sha256: hex("e"))],
            testingData: data ?? [
                .init(name: "Req", disposition: .required(DiffOracleContentDigest(fileCount: 2, sha256: hex("f")))),
                .init(name: "Skip", disposition: .excluded(reason: "not-diff-input"))
            ],
            goldens: goldens
        )
    }

    private func memorySnapshot(
        tests: [DiffOracleDiscoveredDiffWrapperTest]? = nil,
        data: [String: DiffOracleContentDigest?]? = nil,
        fingerprint: String?? = nil,
        missing: [String] = [],
        goldens: [String: String?] = [:],
        observedTree: String? = nil
    ) -> DiffOracleCoverageSnapshot {
        DiffOracleCoverageSnapshot(
            diffWrapperTests: tests ?? [.init(id: "DiffWrapper.A", rightFileSiteCount: 2, sha256: hex("e"))],
            diffWrapperDirectory: wrapperDigest,
            testingDataEntries: data ?? [
                "Req": DiffOracleContentDigest(fileCount: 2, sha256: hex("f")),
                "Skip": DiffOracleContentDigest?.none
            ],
            alignmentFingerprint: fingerprint ?? hex("4"),
            missingAlignmentPaths: missing,
            goldenDigests: goldens,
            observedFixtureXDiffTree: observedTree
        )
    }

    // MARK: Fixture source references

    func testFixtureSourceReferenceRoundTripsAndRejectsUnknownOrEmpty() {
        XCTAssertEqual(DiffOracleFixtureSource(reference: "diffwrapper:DiffWrapper.A"), .diffWrapper("DiffWrapper.A"))
        XCTAssertEqual(DiffOracleFixtureSource(reference: "testing-data:Unicode"), .testingData("Unicode"))
        XCTAssertNil(DiffOracleFixtureSource(reference: "diffwrapper:"))
        XCTAssertNil(DiffOracleFixtureSource(reference: "testing-data:"))
        XCTAssertNil(DiffOracleFixtureSource(reference: "golden:x"))
        XCTAssertNil(DiffOracleFixtureSource(reference: ""))
        for source in [DiffOracleFixtureSource.diffWrapper("S.N"), .testingData("Compare")] {
            XCTAssertEqual(DiffOracleFixtureSource(reference: source.description), source)
        }
        XCTAssertLessThan(DiffOracleFixtureSource.diffWrapper("Z.Z"), .testingData("A"))
        XCTAssertLessThan(DiffOracleFixtureSource.testingData("B"), .testingData("a"))
    }

    // MARK: Parsing: headers and records

    func testMinimalLockParsesIgnoringCommentsBlankLinesAndTabs() throws {
        let text = "# comment\n\n   # indented comment\n" + lockText(["diffwrapper\tDiffWrapper.A\tright-file-sites=0\tsha256=\(hex("e"))"])
        let lock = try DiffOracleCoverageLock.parse(text)
        XCTAssertEqual(lock.fixtureWinMergeCommit, oid("1"))
        XCTAssertEqual(lock.fixtureXDiffTree, oid("2"))
        XCTAssertEqual(lock.diffWrapperDirectory, DiffOracleContentDigest(fileCount: 1, sha256: hex("3")))
        XCTAssertEqual(lock.alignmentFingerprint, hex("4"))
        XCTAssertEqual(lock.diffWrapperTests, [.init(id: "DiffWrapper.A", rightFileSiteCount: 0, sha256: hex("e"))])
        XCTAssertTrue(lock.goldens.isEmpty)
    }

    func testEachRequiredHeaderIsReportedWhenMissing() {
        func dropping(_ prefix: String) -> String {
            lockText().split(separator: "\n").filter { !$0.hasPrefix(prefix + " ") }.joined(separator: "\n")
        }
        for header in [
            "format", "fixture-winmerge-commit", "fixture-xdiff-tree", "diffwrapper-tree", "alignment-fingerprint",
            "alignment-path"
        ] {
            XCTAssertThrowsError(try DiffOracleCoverageLock.parse(dropping(header)), header) { error in
                XCTAssertEqual(error as? DiffOracleCoverageLockError, .missingHeader(header))
                XCTAssertTrue(String(describing: error).contains("'\(header)'"))
            }
        }
    }

    func testUnsupportedFormatIsRejected() {
        XCTAssertThrowsError(try DiffOracleCoverageLock.parse(lockText(header: headerLines(format: "2")))) { error in
            XCTAssertEqual(error as? DiffOracleCoverageLockError, .unsupportedFormat("2"))
        }
    }

    func testMalformedLineReportsOneBasedLineNumber() {
        assertMalformed("# c\nformat 1\nbogus-record x\n", line: 3, containing: "unknown record 'bogus-record'")
        XCTAssertEqual(
            DiffOracleCoverageLockError.malformedLine(lineNumber: 7, reason: "r").description, "coverage.lock line 7: r")
    }

    func testDuplicateHeadersAndEntriesAreRejected() {
        assertMalformed(lockText(["format 1"]), containing: "duplicate entry 'format'")
        assertMalformed(
            lockText(["fixture-xdiff-tree \(oidText("2"))"]), containing: "duplicate entry 'fixture-xdiff-tree'")
        assertMalformed(
            lockText(["alignment-path MacMerge/Sources/MacMergeCore/LineDiff.swift"]), containing: "duplicate entry")
        let test = "diffwrapper DiffWrapper.A right-file-sites=1 sha256=\(hex("e"))"
        assertMalformed(lockText([test, test]), containing: "duplicate entry 'diffwrapper DiffWrapper.A'")
        let data = "testing-data X excluded reason=r"
        assertMalformed(lockText([data, data]), containing: "duplicate entry 'testing-data X'")
        let golden = goldenLine(fields: goldenFields())
        assertMalformed(lockText([golden, golden]), containing: "duplicate entry 'golden g1'")
    }

    func testSingleValueHeadersRejectExtraTokens() {
        assertMalformed(lockText(header: ["format 1 2"]), containing: "'format' takes exactly one value")
        assertMalformed(lockText(header: ["alignment-fingerprint"]), containing: "takes exactly one value")
    }

    func testGitObjectIDsMustBeFullLowercaseNonZero() {
        for bad in [String(repeating: "A", count: 40), String(repeating: "1", count: 39), String(repeating: "0", count: 40), "xyz"] {
            assertMalformed(lockText(header: headerLines(commit: bad)), containing: "40-digit lowercase git object ID")
        }
    }

    func testSHA256FieldsMustBe64LowercaseHex() {
        assertMalformed(lockText(header: headerLines(fingerprint: hex("A"))), containing: "64 lowercase hex")
        assertMalformed(lockText(header: headerLines(fingerprint: String(repeating: "1", count: 63))), containing: "64 lowercase hex")
        assertMalformed(
            lockText(header: headerLines(wrapperTree: "diffwrapper-tree files=1 sha256=zz")), containing: "sha256=<64 hex>")
        assertMalformed(
            lockText(header: headerLines(wrapperTree: "diffwrapper-tree files=-1 sha256=\(hex("3"))")),
            containing: "files=<non-negative integer>")
        assertMalformed(
            lockText(header: headerLines(wrapperTree: "diffwrapper-tree sha256=\(hex("3"))")),
            containing: "files=<non-negative integer>")
    }

    func testKeyValueFieldsRejectUnknownEmptyDuplicateAndBareTokens() {
        assertMalformed(lockText(["diffwrapper S.N right-file-sites=1 sha256=\(hex("e")) extra=1"]), containing: "unknown field 'extra'")
        assertMalformed(lockText(["diffwrapper S.N right-file-sites= sha256=\(hex("e"))"]), containing: "field 'right-file-sites' is empty")
        assertMalformed(
            lockText(["diffwrapper S.N right-file-sites=1 right-file-sites=2 sha256=\(hex("e"))"]),
            containing: "duplicate field 'right-file-sites'")
        assertMalformed(lockText(["diffwrapper S.N bare sha256=\(hex("e"))"]), containing: "expected key=value, found 'bare'")
    }

    // Finding: the lock must not call the source-site count a case count.
    func testDiffWrapperRecordUsesRightFileSitesNotCases() {
        assertMalformed(lockText(["diffwrapper S.N cases=6 sha256=\(hex("e"))"]), containing: "unknown field 'cases'")
        assertMalformed(lockText(["diffwrapper S.N sha256=\(hex("e"))"]), containing: "right-file-sites=<non-negative integer>")
        assertMalformed(lockText(["diffwrapper S.N right-file-sites=-2 sha256=\(hex("e"))"]), containing: "non-negative")
        assertMalformed(lockText(["diffwrapper S.N right-file-sites=1"]), containing: "sha256=<64 hex>")
        assertMalformed(lockText(["diffwrapper"]), containing: "needs a test ID")
    }

    // Finding: discovery and the parser must agree on the ID alphabet; the parser is ASCII-only.
    func testDiffWrapperIDMustBeASCIISuiteDotName() {
        for bad in ["NoDot", "A.B.C", ".Name", "Suite.", "Sü.Name", "Suite.Näme", "S-1.N"] {
            assertMalformed(lockText(["diffwrapper \(bad) right-file-sites=1 sha256=\(hex("e"))"]), containing: "ASCII Suite.Name")
        }
        XCTAssertTrue(DiffOracleCoverageLock.isTestID("Diff_Wrapper9.Run_File"))
        XCTAssertFalse(DiffOracleCoverageLock.isTestID("Sü.N"))
        XCTAssertFalse(DiffOracleCoverageLock.isTestID("S.N\u{0661}"))
    }

    func testTestingDataRecords() throws {
        let lock = try DiffOracleCoverageLock.parse(
            lockText([
                "testing-data Req required files=3 sha256=\(hex("f"))",
                "testing-data Dir2.WinMerge excluded reason=project-file-not-diff-input"
            ]))
        XCTAssertEqual(
            lock.testingData,
            [
                .init(name: "Req", disposition: .required(DiffOracleContentDigest(fileCount: 3, sha256: hex("f")))),
                .init(name: "Dir2.WinMerge", disposition: .excluded(reason: "project-file-not-diff-input"))
            ])
        XCTAssertEqual(lock.requiredSources, [.testingData("Req")])

        assertMalformed(lockText(["testing-data Req"]), containing: "needs a name and disposition")
        assertMalformed(lockText(["testing-data Req maybe"]), containing: "'required' or 'excluded'")
        assertMalformed(lockText(["testing-data Req required sha256=\(hex("f"))"]), containing: "files=<non-negative integer>")
        assertMalformed(lockText(["testing-data Req required files=1"]), containing: "sha256=<64 hex>")
        assertMalformed(lockText(["testing-data X excluded"]), containing: "reason=<kebab-case-reason>")
        assertMalformed(lockText(["testing-data X excluded reason=bad!reason"]), containing: "kebab-case")
        assertMalformed(lockText(["testing-data a=b excluded reason=r"]), containing: "without whitespace or '='")
        assertMalformed(lockText(["testing-data a/b excluded reason=r"]), containing: "one top-level entry")
        assertMalformed(lockText(["testing-data .. excluded reason=r"]), containing: "one top-level entry")
    }

    func testAlignmentPathsMustBeNormalizedRepositoryRelative() {
        for bad in ["/abs/path", "a/../b", "./a", "a//b", "a/", "..", "a=b"] {
            assertMalformed(lockText(header: headerLines(alignmentPath: bad)), containing: "normalized repository-relative")
        }
        XCTAssertTrue(DiffOracleCoverageLock.isSafeRelativePath("Externals/poco/dependencies/pcre2/src"))
        XCTAssertFalse(DiffOracleCoverageLock.isSafeRelativePath("a/\u{1}b"))
        XCTAssertFalse(DiffOracleCoverageLock.isSafeRelativePath(""))
    }

    // MARK: Parsing: goldens reuse DiffOracleGoldenProvenance

    func testGoldenRecordMapsEveryFieldToManifestProvenance() throws {
        let lock = try DiffOracleCoverageLock.parse(
            lockText([goldenLine(id: "a", fields: goldenFields(path: "MacMerge/DiffOracle/goldens/a.json"))]))
        let parsed = try XCTUnwrap(lock.goldens.first)
        XCTAssertEqual(parsed, golden(id: "a"))
        XCTAssertEqual(parsed.source, .diffWrapper("DiffWrapper.A"))
        XCTAssertEqual(parsed.provenance, provenance())
        XCTAssertEqual(parsed.provenance.topLevelLibXDiffCommit, oid("5"))
        XCTAssertEqual(parsed.provenance.nestedLibXDiffTree, oid("8"))
        XCTAssertEqual(parsed.provenance.generatorVersion.rawValue, "gen-1.0")
        XCTAssertEqual(parsed.path, "MacMerge/DiffOracle/goldens/a.json")
        XCTAssertEqual(parsed.sha256, sha("d"))
        XCTAssertEqual(parsed.alignmentFingerprint, sha("4"))
    }

    // Each golden key must reach the parsed record: changing only that key must change the parsed Golden.
    func testEveryGoldenFieldKeyChangesTheParsedGolden() throws {
        let alternatives: [String: String] = [
            "source": "testing-data:Req",
            "winmerge-commit": oidText("e"),
            "xdiff-tree": oidText("e"),
            "libxdiff-commit": oidText("e"),
            "libxdiff-tree": oidText("e"),
            "nested-libxdiff-commit": oidText("e"),
            "nested-libxdiff-tree": oidText("e"),
            "oracle-executable": hex("e"),
            "generator-version": "gen-2.0",
            "generator-executable": hex("e"),
            "generator-schema": hex("e"),
            "generator-configuration": hex("e"),
            "architecture": "arm64",
            "build-configuration": "Debug",
            "alignment": hex("e"),
            "path": "MacMerge/DiffOracle/goldens/other.json",
            "sha256": hex("e")
        ]
        XCTAssertEqual(Set(alternatives.keys), Set(DiffOracleCoverageLock.goldenFieldKeys))
        XCTAssertEqual(DiffOracleCoverageLock.goldenFieldKeys.count, alternatives.count, "duplicate golden field key")
        let baseline = try XCTUnwrap(try DiffOracleCoverageLock.parse(lockText([goldenLine(fields: goldenFields())])).goldens.first)
        for key in DiffOracleCoverageLock.goldenFieldKeys {
            var fields = goldenFields()
            fields[key] = try XCTUnwrap(alternatives[key], key)
            let parsed = try XCTUnwrap(try DiffOracleCoverageLock.parse(lockText([goldenLine(fields: fields)])).goldens.first, key)
            XCTAssertNotEqual(parsed, baseline, "golden key \(key) does not reach the parsed record")
        }
    }

    func testGoldenRejectsEachMissingField() {
        for key in DiffOracleCoverageLock.goldenFieldKeys {
            var fields = goldenFields()
            fields[key] = nil
            XCTAssertThrowsError(try DiffOracleCoverageLock.parse(lockText([goldenLine(fields: fields)])), key) { error in
                guard case .malformedLine = error as? DiffOracleCoverageLockError else {
                    return XCTFail("missing \(key) gave \(error)")
                }
            }
        }
    }

    func testGoldenRejectsBadSourcePathIdentifierAndID() {
        assertMalformed(lockText([goldenLine(fields: goldenFields(source: "elsewhere:x"))]), containing: "source=diffwrapper")
        assertMalformed(
            lockText([goldenLine(fields: goldenFields(path: "MacMerge/DiffOracle/a.json"))]), containing: "golden path must be under")
        assertMalformed(
            lockText([goldenLine(fields: goldenFields(path: "MacMerge/DiffOracle/goldens/../x.json"))]),
            containing: "golden path must be under")
        var fields = goldenFields()
        fields["architecture"] = "x86/64"
        assertMalformed(lockText([goldenLine(fields: fields)]), containing: "architecture=<ASCII identifier>")
        assertMalformed(lockText([goldenLine(id: "bad/id", fields: goldenFields())]), containing: "golden ID has invalid characters")
        assertMalformed(lockText(["golden"]), containing: "golden needs an ID")
        fields = goldenFields()
        fields["xdiff-tree"] = String(repeating: "0", count: 40)
        assertMalformed(lockText([goldenLine(fields: fields)]), containing: "golden xdiff-tree must be a full 40-digit")
    }

    // MARK: Serialization

    func testSerializedLockIsSortedAndRoundTrips() throws {
        var lock = memoryLock(
            tests: [
                .init(id: "b.Z", rightFileSiteCount: 1, sha256: hex("1")),
                .init(id: "B.a", rightFileSiteCount: 0, sha256: hex("2"))
            ],
            goldens: [golden(id: "z"), golden(id: "a", source: .testingData("Req"))]
        )
        lock.alignmentPaths = ["b", "A", "a"]
        let text = lock.serialized()
        XCTAssertTrue(text.hasPrefix(DiffOracleCoverageLock.defaultHeaderComment + "\nformat 1\n"))
        XCTAssertTrue(text.hasSuffix("\n"))
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.filter { $0.hasPrefix("alignment-path ") }, ["alignment-path A", "alignment-path a", "alignment-path b"])
        XCTAssertEqual(lines.filter { $0.hasPrefix("diffwrapper ") }.map { $0.split(separator: " ")[1] }, ["B.a", "b.Z"])
        XCTAssertEqual(lines.filter { $0.hasPrefix("golden ") }.map { $0.split(separator: " ")[1] }, ["a", "z"])
        XCTAssertFalse(text.contains("cases="))

        let reparsed = try DiffOracleCoverageLock.parse(text)
        XCTAssertEqual(reparsed.serialized(), text)
        XCTAssertEqual(Set(reparsed.goldens), Set(lock.goldens))
        XCTAssertEqual(Set(reparsed.diffWrapperTests), Set(lock.diffWrapperTests))
        XCTAssertEqual(Set(reparsed.testingData), Set(lock.testingData))
    }

    func testSerializationOmitsGoldenSectionWhenEmptyAndHonorsCustomHeader() {
        let text = memoryLock().serialized(header: "# custom")
        XCTAssertTrue(text.hasPrefix("# custom\nformat 1\n"))
        XCTAssertFalse(text.contains("golden "))
    }

    func testRequiredSourcesAreSortedDedupedAndSkipExcluded() {
        let lock = memoryLock(
            tests: [
                .init(id: "S.B", rightFileSiteCount: 0, sha256: hex("1")),
                .init(id: "S.A", rightFileSiteCount: 0, sha256: hex("1")),
                .init(id: "S.A", rightFileSiteCount: 0, sha256: hex("1"))
            ])
        XCTAssertEqual(lock.requiredSources, [.diffWrapper("S.A"), .diffWrapper("S.B"), .testingData("Req")])
    }

    // MARK: Discovery

    func testTestIDRecognizesGoogleTestMacrosOnly() {
        XCTAssertEqual(DiffOracleFixtureDiscovery.testID(declaredBy: "TEST(DiffWrapper, RunFileDiff_NoEol)"), "DiffWrapper.RunFileDiff_NoEol")
        XCTAssertEqual(DiffOracleFixtureDiscovery.testID(declaredBy: "  TEST_F( Fixture , Case1 ) {"), "Fixture.Case1")
        XCTAssertEqual(DiffOracleFixtureDiscovery.testID(declaredBy: "\tTEST_P(P, Q)"), "P.Q")
        XCTAssertNil(DiffOracleFixtureDiscovery.testID(declaredBy: "TYPED_TEST(A, B)"))
        XCTAssertNil(DiffOracleFixtureDiscovery.testID(declaredBy: "TEST(A, B, C)"))
        XCTAssertNil(DiffOracleFixtureDiscovery.testID(declaredBy: "TEST(A)"))
        XCTAssertNil(DiffOracleFixtureDiscovery.testID(declaredBy: "TEST(A, )"))
        XCTAssertNil(DiffOracleFixtureDiscovery.testID(declaredBy: "TEST(A, B-C)"))
        XCTAssertNil(DiffOracleFixtureDiscovery.testID(declaredBy: "// no macro here"))
        XCTAssertNil(DiffOracleFixtureDiscovery.testID(declaredBy: "TEST"))
        XCTAssertNil(DiffOracleFixtureDiscovery.testID(declaredBy: "TEST)(A, B"))
    }

    func testSourceDiscoveryCountsRightFileSitesAndBoundsBodies() {
        let source = """
            #include "x.h"
            const TempFile WriteToTempFile(const String& text) { return {}; }
            TEST(S, One)
            {
                TempFile right = WriteToTempFile(_T("a"));
                for (const auto& eol : { _T("\\n"), _T("\\r") })
                {
                    TempFile right = WriteToTempFile(_T("b") + String(eol));
                }
            }
            TEST(S, Two)
            {
                TempFile left = WriteToTempFile(_T("a"));
            }
            """
        let tests = DiffOracleFixtureDiscovery.diffWrapperTests(inSource: source)
        XCTAssertEqual(tests.map(\.id), ["S.One", "S.Two"])
        // A source site inside an EOL loop still counts once: right-file-sites is not a case count.
        XCTAssertEqual(tests.map(\.rightFileSiteCount), [2, 0])
        XCTAssertNotEqual(tests[0].sha256, tests[1].sha256)
        XCTAssertTrue(DiffOracleFixtureDiscovery.diffWrapperTests(inSource: "int x;\n").isEmpty)
    }

    // Finding: the preamble (includes, WriteToTempFile) is outside every per-test digest, so the
    // directory digest must catch it.
    func testPreambleChangeLeavesPerTestDigestsUnchanged() {
        let body = "TEST(S, A)\n{\n    TempFile right = WriteToTempFile(_T(\"a\"));\n}\n"
        let first = DiffOracleFixtureDiscovery.diffWrapperTests(inSource: "helper v1\n" + body)
        let second = DiffOracleFixtureDiscovery.diffWrapperTests(inSource: "helper v2 changed\n" + body)
        XCTAssertEqual(first, second)
    }

    func testDiscoveredUnicodeIDIsReturnedForAuditButRejectedByLock() {
        let tests = DiffOracleFixtureDiscovery.diffWrapperTests(inSource: "TEST(Suite, Näme)\n{}\n")
        XCTAssertEqual(tests.map(\.id), ["Suite.Näme"])
        XCTAssertFalse(DiffOracleCoverageLock.isTestID(tests[0].id))
    }

    func testDirectoryDiscoveryReadsOnlyCppNormalizesCRLFAndRejectsDuplicates() throws {
        let root = try makeTemporaryDirectory()
        try write("TEST(S, B)\r\n{\r\n    TempFile right = WriteToTempFile(_T(\"a\"));\r\n}\r\n", to: root.appendingPathComponent("b.cpp"))
        try write("TEST(S, A)\n{\n}\n", to: root.appendingPathComponent("a.cpp"))
        try write("TEST(S, Hidden)\n", to: root.appendingPathComponent("notes.h"))
        let tests = try DiffOracleFixtureDiscovery.diffWrapperTests(inDirectory: root)
        XCTAssertEqual(tests.map(\.id), ["S.A", "S.B"])
        let lf = DiffOracleFixtureDiscovery.diffWrapperTests(
            inSource: "TEST(S, B)\n{\n    TempFile right = WriteToTempFile(_T(\"a\"));\n}\n")
        XCTAssertEqual(tests[1], lf[0])

        try write("TEST(S, A)\n", to: root.appendingPathComponent("c.cpp"))
        XCTAssertThrowsError(try DiffOracleFixtureDiscovery.diffWrapperTests(inDirectory: root)) { error in
            XCTAssertEqual(error as? DiffOracleFixtureDiscovery.DiscoveryError, .duplicateTest("S.A"))
        }
    }

    func testDiscoveryReportsUnreadableDirectories() throws {
        let missing = try makeTemporaryDirectory().appendingPathComponent("absent")
        XCTAssertThrowsError(try DiffOracleFixtureDiscovery.diffWrapperTests(inDirectory: missing)) { error in
            XCTAssertEqual(error as? DiffOracleFixtureDiscovery.DiscoveryError, .unreadable(missing.path))
        }
        XCTAssertThrowsError(try DiffOracleFixtureDiscovery.topLevelEntries(in: missing))
        XCTAssertThrowsError(try DiffOracleFixtureDiscovery.contentDigest(at: missing, label: "x")) { error in
            XCTAssertEqual(error as? DiffOracleFixtureDiscovery.DiscoveryError, .unreadable(missing.path))
        }
        XCTAssertEqual(DiffOracleFixtureDiscovery.DiscoveryError.duplicateTest("S.A").description, "duplicate GoogleTest ID S.A")
    }

    func testTopLevelEntriesHideDotFilesAndSortByUTF8() throws {
        let root = try makeTemporaryDirectory()
        for name in ["b", "C", ".hidden", "a b", "a=b"] {
            try write("x", to: root.appendingPathComponent(name))
        }
        XCTAssertEqual(try DiffOracleFixtureDiscovery.topLevelEntries(in: root), ["C", "a b", "a=b", "b"])
    }

    func testContentDigestTracksBytesNamesLabelsAndSymlinks() throws {
        let root = try makeTemporaryDirectory()
        let tree = root.appendingPathComponent("tree")
        try write("one", to: tree.appendingPathComponent("a.txt"))
        try write("two", to: tree.appendingPathComponent("sub/b.txt"))
        let base = try DiffOracleFixtureDiscovery.contentDigest(at: tree, label: "T")
        XCTAssertEqual(base.fileCount, 2)
        XCTAssertEqual(base.sha256.count, 64)
        XCTAssertEqual(try DiffOracleFixtureDiscovery.contentDigest(at: tree, label: "T"), base)
        XCTAssertNotEqual(try DiffOracleFixtureDiscovery.contentDigest(at: tree, label: "U").sha256, base.sha256)

        try write("junk", to: tree.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(try DiffOracleFixtureDiscovery.contentDigest(at: tree, label: "T"), base)

        try write("one!", to: tree.appendingPathComponent("a.txt"))
        let edited = try DiffOracleFixtureDiscovery.contentDigest(at: tree, label: "T")
        XCTAssertEqual(edited.fileCount, 2)
        XCTAssertNotEqual(edited.sha256, base.sha256)
        try write("one", to: tree.appendingPathComponent("a.txt"))

        try FileManager.default.moveItem(at: tree.appendingPathComponent("a.txt"), to: tree.appendingPathComponent("c.txt"))
        XCTAssertNotEqual(try DiffOracleFixtureDiscovery.contentDigest(at: tree, label: "T").sha256, base.sha256)
        try FileManager.default.moveItem(at: tree.appendingPathComponent("c.txt"), to: tree.appendingPathComponent("a.txt"))
        XCTAssertEqual(try DiffOracleFixtureDiscovery.contentDigest(at: tree, label: "T"), base)

        try FileManager.default.createSymbolicLink(atPath: tree.appendingPathComponent("link").path, withDestinationPath: "a.txt")
        let linked = try DiffOracleFixtureDiscovery.contentDigest(at: tree, label: "T")
        XCTAssertEqual(linked.fileCount, 3)
        try FileManager.default.removeItem(at: tree.appendingPathComponent("link"))
        try FileManager.default.createSymbolicLink(atPath: tree.appendingPathComponent("link").path, withDestinationPath: "sub/b.txt")
        XCTAssertNotEqual(try DiffOracleFixtureDiscovery.contentDigest(at: tree, label: "T").sha256, linked.sha256)

        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertEqual(try DiffOracleFixtureDiscovery.contentDigest(at: empty, label: "E").fileCount, 0)

        let single = try DiffOracleFixtureDiscovery.contentDigest(at: tree.appendingPathComponent("a.txt"), label: "a.txt")
        XCTAssertEqual(single.fileCount, 1)
    }

    // NFD and NFC spellings of the same file name must digest identically.
    func testContentDigestNormalizesFileNamesToNFC() throws {
        let decomposed = try makeTemporaryDirectory()
        let precomposed = try makeTemporaryDirectory()
        try write("same", to: decomposed.appendingPathComponent("tree/e\u{301}.txt"))
        try write("same", to: precomposed.appendingPathComponent("tree/\u{e9}.txt"))
        let nfd = try DiffOracleFixtureDiscovery.contentDigest(at: decomposed.appendingPathComponent("tree"), label: "T")
        let nfc = try DiffOracleFixtureDiscovery.contentDigest(at: precomposed.appendingPathComponent("tree"), label: "T")
        XCTAssertEqual(nfd, nfc)
        XCTAssertEqual(nfd.fileCount, 1)
    }

    func testSHA256HexMatchesKnownVector() {
        XCTAssertEqual(
            DiffOracleFixtureDiscovery.sha256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: Snapshot + audit against a synthetic repository

    private struct SyntheticRepository {
        let root: URL
        var wrapper: URL { root.appendingPathComponent("Testing/GoogleTest/DiffWrapper") }
        var data: URL { root.appendingPathComponent("Testing/Data") }
    }

    private func makeRepository() throws -> (SyntheticRepository, DiffOracleCoverageLock) {
        let repo = SyntheticRepository(root: try makeTemporaryDirectory())
        try write(
            "#include \"pch.h\"\nTempFile WriteToTempFile(const String& t) { return {}; }\n"
                + "TEST(DiffWrapper, A)\n{\n    TempFile right = WriteToTempFile(_T(\"a\"));\n}\n"
                + "TEST(DiffWrapper, B)\n{\n}\n",
            to: repo.wrapper.appendingPathComponent("DiffWrapper_test.cpp"))
        try write("a\n", to: repo.data.appendingPathComponent("Req/left.txt"))
        try write("b\n", to: repo.data.appendingPathComponent("Req/right.txt"))
        try write("x", to: repo.data.appendingPathComponent("Skip/x.bin"))
        try write("align v1", to: repo.root.appendingPathComponent("Src/Align.swift"))

        let seed = DiffOracleCoverageLock(
            fixtureWinMergeCommit: oid("1"),
            fixtureXDiffTree: oid("2"),
            diffWrapperDirectory: DiffOracleContentDigest(fileCount: 0, sha256: hex("0")),
            alignmentPaths: ["Src/Align.swift"],
            alignmentFingerprint: hex("0"),
            diffWrapperTests: [],
            testingData: [
                .init(name: "Req", disposition: .required(DiffOracleContentDigest(fileCount: 0, sha256: hex("0")))),
                .init(name: "Skip", disposition: .excluded(reason: "not-diff-input"))
            ],
            goldens: []
        )
        let snapshot = try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: seed)
        return (repo, seed.refreshed(with: snapshot))
    }

    private func audit(_ repo: SyntheticRepository, _ lock: DiffOracleCoverageLock, requireGoldens: Bool = false) throws
        -> DiffOracleCoverageReport
    {
        DiffOracleCoverageAudit.audit(
            lock: lock,
            snapshot: try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: lock),
            requireGoldens: requireGoldens)
    }

    func testRefreshedSyntheticLockPassesAndSurvivesTextRoundTrip() throws {
        let (repo, lock) = try makeRepository()
        XCTAssertEqual(lock.diffWrapperTests.map(\.id), ["DiffWrapper.A", "DiffWrapper.B"])
        XCTAssertEqual(lock.diffWrapperTests.map(\.rightFileSiteCount), [1, 0])
        XCTAssertEqual(lock.diffWrapperDirectory.fileCount, 1)
        let report = try audit(repo, lock)
        XCTAssertTrue(report.passed, "\(report.findings)")
        XCTAssertEqual(report.pendingSources, [.diffWrapper("DiffWrapper.A"), .diffWrapper("DiffWrapper.B"), .testingData("Req")])

        let reparsed = try DiffOracleCoverageLock.parse(lock.serialized())
        XCTAssertTrue(try audit(repo, reparsed).passed)

        let strict = try audit(repo, lock, requireGoldens: true)
        XCTAssertEqual(strict.findings, report.pendingSources.map(DiffOracleCoverageFinding.missingGolden))
        XCTAssertFalse(strict.passed)
    }

    // Finding: a helper change before the first TEST must fail even though no TEST body changed.
    func testSharedHelperChangeFailsThroughDirectoryDigest() throws {
        let (repo, lock) = try makeRepository()
        let file = repo.wrapper.appendingPathComponent("DiffWrapper_test.cpp")
        let original = try String(contentsOf: file, encoding: .utf8)
        try write(original.replacingOccurrences(of: "return {};", with: "return { t };"), to: file)
        let findings = try audit(repo, lock).findings
        XCTAssertEqual(findings.count, 1)
        guard case .diffWrapperDirectoryChanged(let locked, let current)? = findings.first else {
            return XCTFail("\(findings)")
        }
        XCTAssertEqual(locked, lock.diffWrapperDirectory)
        XCTAssertEqual(current.fileCount, 1)
        XCTAssertTrue(findings[0].description.contains("shared helpers"))
    }

    func testNonCppFileInDiffWrapperFailsThroughDirectoryDigest() throws {
        let (repo, lock) = try makeRepository()
        try write("#pragma once\n", to: repo.wrapper.appendingPathComponent("helper.h"))
        let findings = try audit(repo, lock).findings
        XCTAssertEqual(findings.count, 1)
        guard case .diffWrapperDirectoryChanged(_, let current)? = findings.first else { return XCTFail("\(findings)") }
        XCTAssertEqual(current.fileCount, 2)
    }

    func testDiffWrapperTestAddedRemovedAndChanged() throws {
        let (repo, lock) = try makeRepository()
        try write(
            "#include \"pch.h\"\nTempFile WriteToTempFile(const String& t) { return {}; }\n"
                + "TEST(DiffWrapper, A)\n{\n    TempFile right = WriteToTempFile(_T(\"a\"));\n    TempFile right = WriteToTempFile(_T(\"b\"));\n}\n"
                + "TEST(DiffWrapper, C)\n{\n}\n",
            to: repo.wrapper.appendingPathComponent("DiffWrapper_test.cpp"))
        let findings = try audit(repo, lock).findings
        XCTAssertTrue(findings.contains(.diffWrapperTestChanged(id: "DiffWrapper.A", lockedSites: 1, currentSites: 2)))
        XCTAssertTrue(findings.contains(.unlistedDiffWrapperTest("DiffWrapper.C")))
        XCTAssertTrue(findings.contains(.staleDiffWrapperTest("DiffWrapper.B")))
        XCTAssertTrue(findings.contains { if case .diffWrapperDirectoryChanged = $0 { return true } else { return false } })
    }

    func testBodyOnlyChangeWithSameSiteCountStillFails() throws {
        let (repo, lock) = try makeRepository()
        let file = repo.wrapper.appendingPathComponent("DiffWrapper_test.cpp")
        let original = try String(contentsOf: file, encoding: .utf8)
        try write(original.replacingOccurrences(of: "_T(\"a\")", with: "_T(\"z\")"), to: file)
        let findings = try audit(repo, lock).findings
        XCTAssertTrue(findings.contains(.diffWrapperTestChanged(id: "DiffWrapper.A", lockedSites: 1, currentSites: 1)))
    }

    // Finding: non-ASCII discovered IDs are an explicit "cannot be recorded" error, not "unlisted".
    func testUnicodeDiffWrapperTestIsReportedAsUnrepresentable() throws {
        let (repo, lock) = try makeRepository()
        try write("TEST(DiffWrapper, Ünicode)\n{\n}\n", to: repo.wrapper.appendingPathComponent("Extra_test.cpp"))
        let findings = try audit(repo, lock).findings
        XCTAssertTrue(findings.contains(.unrepresentableDiffWrapperTest("DiffWrapper.Ünicode")))
        XCTAssertFalse(findings.contains(.unlistedDiffWrapperTest("DiffWrapper.Ünicode")))
        XCTAssertTrue(
            DiffOracleCoverageFinding.unrepresentableDiffWrapperTest("X.Ü").description.contains("cannot be recorded"))

        // --refresh must not write an ID the parser would reject.
        let snapshot = try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: lock)
        let refreshed = lock.refreshed(with: snapshot)
        XCTAssertFalse(refreshed.diffWrapperTests.contains { $0.id == "DiffWrapper.Ünicode" })
        XCTAssertNoThrow(try DiffOracleCoverageLock.parse(refreshed.serialized()))
        XCTAssertTrue(
            DiffOracleCoverageAudit.audit(lock: refreshed, snapshot: snapshot).findings
                == [.unrepresentableDiffWrapperTest("DiffWrapper.Ünicode")])
    }

    func testTestingDataEntriesAddedRemovedChangedAndUnrepresentable() throws {
        let (repo, lock) = try makeRepository()
        try write("new", to: repo.data.appendingPathComponent("NewFixture/a.txt"))
        try write("space", to: repo.data.appendingPathComponent("Has Space/a.txt"))
        try write("eq", to: repo.data.appendingPathComponent("k=v"))
        try write("changed\n", to: repo.data.appendingPathComponent("Req/left.txt"))
        try write("ignored", to: repo.data.appendingPathComponent("Skip/y.bin"))
        var findings = try audit(repo, lock).findings
        XCTAssertTrue(findings.contains(.unlistedTestingDataEntry("NewFixture")))
        XCTAssertTrue(findings.contains(.unrepresentableTestingDataEntry("Has Space")))
        XCTAssertTrue(findings.contains(.unrepresentableTestingDataEntry("k=v")))
        XCTAssertFalse(findings.contains(.unlistedTestingDataEntry("Has Space")))
        XCTAssertTrue(
            findings.contains {
                if case .testingDataChanged(let name, let locked, let current) = $0 {
                    return name == "Req" && locked.fileCount == 2 && current.fileCount == 2 && locked != current
                }
                return false
            })
        // Excluded entries are not digested, so their content may change freely.
        XCTAssertFalse(findings.contains { $0.description.contains("Testing/Data/Skip") })
        XCTAssertEqual(findings.count, 4)

        try FileManager.default.removeItem(at: repo.data.appendingPathComponent("Skip"))
        findings = try audit(repo, lock).findings
        XCTAssertTrue(findings.contains(.staleTestingDataEntry("Skip")))
    }

    func testRefreshNeverClassifiesNewTestingDataAndDropsStaleEntries() throws {
        let (repo, lock) = try makeRepository()
        try write("new", to: repo.data.appendingPathComponent("NewFixture/a.txt"))
        try FileManager.default.removeItem(at: repo.data.appendingPathComponent("Skip"))
        try write("changed\n", to: repo.data.appendingPathComponent("Req/left.txt"))
        let snapshot = try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: lock)
        let refreshed = lock.refreshed(with: snapshot)
        XCTAssertEqual(refreshed.testingData.map(\.name), ["Req"])
        XCTAssertEqual(
            DiffOracleCoverageAudit.audit(lock: refreshed, snapshot: snapshot).findings, [.unlistedTestingDataEntry("NewFixture")])
        XCTAssertEqual(refreshed.fixtureWinMergeCommit, lock.fixtureWinMergeCommit)
        XCTAssertEqual(refreshed.fixtureXDiffTree, lock.fixtureXDiffTree)
        XCTAssertEqual(refreshed.alignmentPaths, lock.alignmentPaths)
    }

    func testAlignmentChangeFailsUntilFingerprintIsAcknowledged() throws {
        let (repo, lock) = try makeRepository()
        try write("align v2", to: repo.root.appendingPathComponent("Src/Align.swift"))
        let snapshot = try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: lock)
        let findings = DiffOracleCoverageAudit.audit(lock: lock, snapshot: snapshot).findings
        XCTAssertEqual(findings, [.alignmentChanged(locked: lock.alignmentFingerprint, current: snapshot.alignmentFingerprint!)])
        XCTAssertTrue(findings[0].description.contains("MacMerge alignment sources changed"))
        // With no goldens, refreshing alone satisfies the gate: review is fingerprint acknowledgement only.
        XCTAssertTrue(DiffOracleCoverageAudit.audit(lock: lock.refreshed(with: snapshot), snapshot: snapshot).passed)
    }

    func testAlignmentPathOrderDoesNotAffectFingerprintButContentsDo() throws {
        let (repo, lock) = try makeRepository()
        try write("c", to: repo.root.appendingPathComponent("Lib/a.c"))
        var withDirectory = lock
        withDirectory.alignmentPaths = ["Lib", "Src/Align.swift"]
        let first = try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: withDirectory).alignmentFingerprint
        var reordered = withDirectory
        reordered.alignmentPaths = ["Src/Align.swift", "Lib", "Lib"]
        XCTAssertEqual(try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: reordered).alignmentFingerprint, first)
        XCTAssertNotEqual(first, lock.alignmentFingerprint)
        try write("c2", to: repo.root.appendingPathComponent("Lib/nested/b.c"))
        let added = try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: withDirectory).alignmentFingerprint
        XCTAssertNotEqual(added, first)

        // Rename only: same bytes, different path.
        try FileManager.default.moveItem(
            at: repo.root.appendingPathComponent("Lib/nested/b.c"), to: repo.root.appendingPathComponent("Lib/nested/renamed.c"))
        let renamed = try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: withDirectory).alignmentFingerprint
        XCTAssertNotEqual(renamed, added)
        XCTAssertNotEqual(renamed, first)

        // Delete: removing the extra file restores the original fingerprint, so deletion is tracked.
        try FileManager.default.removeItem(at: repo.root.appendingPathComponent("Lib/nested"))
        XCTAssertEqual(try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: withDirectory).alignmentFingerprint, first)
        try FileManager.default.removeItem(at: repo.root.appendingPathComponent("Lib/a.c"))
        XCTAssertNotEqual(try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: withDirectory).alignmentFingerprint, first)
    }

    func testMissingAlignmentPathIsReportedWithoutBogusFingerprintChange() throws {
        let (repo, lock) = try makeRepository()
        var broken = lock
        broken.alignmentPaths.append("Src/Gone.swift")
        let snapshot = try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: broken)
        XCTAssertNil(snapshot.alignmentFingerprint)
        XCTAssertEqual(snapshot.missingAlignmentPaths, ["Src/Gone.swift"])
        XCTAssertEqual(DiffOracleCoverageAudit.audit(lock: broken, snapshot: snapshot).findings, [.alignmentPathMissing("Src/Gone.swift")])
        // Refresh keeps the recorded fingerprint rather than erasing it.
        XCTAssertEqual(broken.refreshed(with: snapshot).alignmentFingerprint, broken.alignmentFingerprint)
    }

    func testGoldenFilesAreDigestedFromDisk() throws {
        let (repo, base) = try makeRepository()
        let content = Data("golden".utf8)
        try write("golden", to: repo.root.appendingPathComponent("MacMerge/DiffOracle/goldens/g1.json"))
        var lock = base
        let digest = try DiffOracleSHA256(hex: DiffOracleFixtureDiscovery.sha256Hex(content))
        lock.goldens = [
            DiffOracleCoverageLock.Golden(
                id: "g1", source: .diffWrapper("DiffWrapper.A"), provenance: provenance(),
                alignmentFingerprint: try DiffOracleSHA256(hex: base.alignmentFingerprint),
                path: "MacMerge/DiffOracle/goldens/g1.json", sha256: digest),
            DiffOracleCoverageLock.Golden(
                id: "g2", source: .testingData("Req"), provenance: provenance(),
                alignmentFingerprint: try DiffOracleSHA256(hex: base.alignmentFingerprint),
                path: "MacMerge/DiffOracle/goldens/g2.json", sha256: digest)
        ]
        var report = try audit(repo, lock)
        XCTAssertEqual(report.findings, [.goldenFileMissing(id: "g2", path: "MacMerge/DiffOracle/goldens/g2.json")])
        // A golden with a missing file does not count as coverage.
        XCTAssertEqual(report.pendingSources, [.diffWrapper("DiffWrapper.B"), .testingData("Req")])

        try write("tampered", to: repo.root.appendingPathComponent("MacMerge/DiffOracle/goldens/g1.json"))
        try write("golden", to: repo.root.appendingPathComponent("MacMerge/DiffOracle/goldens/g2.json"))
        report = try audit(repo, lock)
        XCTAssertEqual(report.findings, [.goldenFileChanged(id: "g1", path: "MacMerge/DiffOracle/goldens/g1.json")])
        XCTAssertEqual(report.pendingSources, [.diffWrapper("DiffWrapper.A"), .diffWrapper("DiffWrapper.B")])

        try write("golden", to: repo.root.appendingPathComponent("MacMerge/DiffOracle/goldens/g1.json"))
        report = try audit(repo, lock)
        XCTAssertTrue(report.passed, "\(report.findings)")
        XCTAssertEqual(report.pendingSources, [.diffWrapper("DiffWrapper.B")])

        // Refresh never rewrites goldens, so an alignment change keeps them stale.
        try write("golden", to: repo.root.appendingPathComponent("MacMerge/DiffOracle/goldens/g1.json"))
        try write("align v2", to: repo.root.appendingPathComponent("Src/Align.swift"))
        let snapshot = try DiffOracleCoverageSnapshot.load(repositoryRoot: repo.root, lock: lock)
        let refreshed = lock.refreshed(with: snapshot)
        XCTAssertEqual(refreshed.goldens, lock.goldens)
        XCTAssertEqual(
            DiffOracleCoverageAudit.audit(lock: refreshed, snapshot: snapshot).findings,
            [.goldenAlignmentStale(id: "g1"), .goldenAlignmentStale(id: "g2")])
    }

    // MARK: Audit on in-memory values

    // Finding: public initializers can carry duplicates; audit must report, not trap.
    func testAuditReportsDuplicatesFromPublicInitializersWithoutTrapping() {
        let test = DiffOracleCoverageLock.DiffWrapperTest(id: "DiffWrapper.A", rightFileSiteCount: 2, sha256: hex("e"))
        let data = DiffOracleCoverageLock.TestingDataEntry(
            name: "Req", disposition: .required(DiffOracleContentDigest(fileCount: 2, sha256: hex("f"))))
        let lock = memoryLock(
            tests: [test, test],
            data: [data, data, .init(name: "Skip", disposition: .excluded(reason: "r"))],
            goldens: [golden(), golden()])
        let discovered = DiffOracleDiscoveredDiffWrapperTest(id: "DiffWrapper.A", rightFileSiteCount: 2, sha256: hex("e"))
        let snapshot = memorySnapshot(tests: [discovered, discovered], goldens: ["g1": hex("d")])
        let findings = DiffOracleCoverageAudit.audit(lock: lock, snapshot: snapshot).findings
        XCTAssertTrue(findings.contains(.duplicateLockEntry("diffwrapper DiffWrapper.A")))
        XCTAssertTrue(findings.contains(.duplicateDiscoveredEntry("diffwrapper DiffWrapper.A")))
        XCTAssertTrue(findings.contains(.duplicateLockEntry("testing-data Req")))
        XCTAssertTrue(findings.contains(.duplicateLockEntry("golden g1")))
        XCTAssertEqual(findings.count, 4, "\(findings)")
        XCTAssertTrue(DiffOracleCoverageFinding.duplicateLockEntry("k").description.contains("more than once"))
    }

    func testCleanInMemoryAuditPassesWithPendingSources() {
        let report = DiffOracleCoverageAudit.audit(lock: memoryLock(), snapshot: memorySnapshot())
        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.pendingSources, [.diffWrapper("DiffWrapper.A"), .testingData("Req")])
    }

    // Finding: fixture-xdiff-tree is checked against git when the commit is resolvable.
    func testFixtureXDiffTreeIsVerifiedOnlyWhenObserved() {
        XCTAssertTrue(DiffOracleCoverageAudit.audit(lock: memoryLock(), snapshot: memorySnapshot(observedTree: nil)).passed)
        XCTAssertTrue(DiffOracleCoverageAudit.audit(lock: memoryLock(), snapshot: memorySnapshot(observedTree: oidText("2"))).passed)
        let findings = DiffOracleCoverageAudit.audit(lock: memoryLock(), snapshot: memorySnapshot(observedTree: oidText("9"))).findings
        XCTAssertEqual(findings, [.fixtureXDiffTreeMismatch(locked: oidText("2"), observed: oidText("9"))])
    }

    // Finding: a golden's xdiff tree must match the lock's fixture-xdiff-tree pin.
    func testGoldenProvenanceMustMatchFixturePins() {
        let goldens = [golden(id: "commit", commit: "9"), golden(id: "tree", tree: "9")]
        let snapshot = memorySnapshot(goldens: ["commit": hex("d"), "tree": hex("d")])
        let findings = DiffOracleCoverageAudit.audit(lock: memoryLock(goldens: goldens), snapshot: snapshot).findings
        XCTAssertEqual(
            findings,
            [
                .goldenWinMergeCommitMismatch(id: "commit", golden: oidText("9"), fixtures: oidText("1")),
                .goldenXDiffTreeMismatch(id: "tree", golden: oidText("9"), fixtures: oidText("2"))
            ])
    }

    func testGoldenSourceAlignmentAndFileStates() {
        let goldens = [
            golden(id: "a-unknown", source: .testingData("Skip")),
            golden(id: "b-stale", alignment: "7"),
            golden(id: "c-missing"),
            golden(id: "d-unlisted"),
            golden(id: "e-changed")
        ]
        let snapshot = memorySnapshot(goldens: [
            "a-unknown": hex("d"), "b-stale": hex("d"), "c-missing": String?.none, "e-changed": hex("0")
        ])
        let report = DiffOracleCoverageAudit.audit(lock: memoryLock(goldens: goldens), snapshot: snapshot)
        XCTAssertEqual(
            report.findings,
            [
                .goldenUnknownSource(id: "a-unknown", source: .testingData("Skip")),
                .goldenAlignmentStale(id: "b-stale"),
                .goldenFileMissing(id: "c-missing", path: "MacMerge/DiffOracle/goldens/c-missing.json"),
                .goldenFileMissing(id: "d-unlisted", path: "MacMerge/DiffOracle/goldens/d-unlisted.json"),
                .goldenFileChanged(id: "e-changed", path: "MacMerge/DiffOracle/goldens/e-changed.json")
            ])
        // Every golden here has a finding, so none covers DiffWrapper.A.
        XCTAssertEqual(report.pendingSources, [.diffWrapper("DiffWrapper.A"), .testingData("Req")])
    }

    func testGoldenWithPinMismatchDoesNotCoverItsSource() {
        let report = DiffOracleCoverageAudit.audit(
            lock: memoryLock(goldens: [golden(tree: "9")]), snapshot: memorySnapshot(goldens: ["g1": hex("d")]))
        XCTAssertFalse(report.passed)
        XCTAssertEqual(report.pendingSources, [.diffWrapper("DiffWrapper.A"), .testingData("Req")])
    }

    func testGoldenAlignmentComparesAgainstLockWhenFingerprintUnavailable() {
        let snapshot = memorySnapshot(fingerprint: .some(nil), missing: ["x"], goldens: ["g1": hex("d")])
        let findings = DiffOracleCoverageAudit.audit(lock: memoryLock(goldens: [golden()]), snapshot: snapshot).findings
        XCTAssertEqual(findings, [.alignmentPathMissing("x")])
    }

    func testRequireGoldensTurnsPendingIntoFindings() {
        let report = DiffOracleCoverageAudit.audit(
            lock: memoryLock(goldens: [golden()]), snapshot: memorySnapshot(goldens: ["g1": hex("d")]), requireGoldens: true)
        XCTAssertEqual(report.findings, [.missingGolden(.testingData("Req"))])
        XCTAssertEqual(report.pendingSources, [.testingData("Req")])
        XCTAssertEqual(
            DiffOracleCoverageFinding.missingGolden(.testingData("Req")).description,
            "required fixture source testing-data:Req has no WinMerge golden result")
    }

    // MARK: Checked-in lock and CI wiring

    func testCheckedInLockParsesRoundTripsAndPinsFixtureCommit() throws {
        let text = try readRepositoryFile(DiffOracleCoverageLock.defaultRelativePath)
        let lock = try DiffOracleCoverageLock.parse(text)
        let header = text.split(separator: "\n", omittingEmptySubsequences: false).prefix { $0.hasPrefix("#") }.joined(separator: "\n")
        XCTAssertEqual(lock.serialized(header: header), text, "coverage.lock is not in canonical serialized form")
        XCTAssertFalse(text.contains("cases="))
        XCTAssertEqual(lock.fixtureWinMergeCommit.rawValue, Self.pinnedWinMergeCommit)
        XCTAssertEqual(lock.fixtureXDiffTree.rawValue, Self.pinnedXDiffTree)
        XCTAssertTrue(lock.goldens.allSatisfy { $0.provenance.winMergeCommit == lock.fixtureWinMergeCommit })
        XCTAssertTrue(lock.goldens.allSatisfy { $0.provenance.windowsXDiffTree == lock.fixtureXDiffTree })

        let eol = try XCTUnwrap(lock.diffWrapperTests.first { $0.id == "DiffWrapper.RunFileDiff_IgnoreMissingTrailingEol" })
        // Six source sites; the EOL loops make the real comparison count larger.
        XCTAssertEqual(eol.rightFileSiteCount, 6)
        for name in ["Codepages", "Compare", "Unicode", "LastLineEOL", "Patch"] {
            XCTAssertTrue(lock.requiredSources.contains(.testingData(name)), name)
        }
    }

    // Last upstream WinMerge commit before the fork, and its Externals/xdiff tree.
    private static let pinnedWinMergeCommit = "7dbede986c2229d5a6273140facc14ae81461a8a"
    private static let pinnedXDiffTree = "bf7ade8ccf4199ab85649c5aac4474b14e44f55f"

    private struct GitResult {
        let status: Int32
        let output: String
    }

    private static func git(_ arguments: [String], in directory: URL = repositoryRoot) throws -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return GitResult(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Resolves the pinned commit's Externals/xdiff tree in the real checkout. Skips only in a shallow clone,
    /// which legitimately lacks history; a full clone that cannot resolve the commit fails.
    private func resolvedPinnedXDiffTree() throws -> String {
        let shallow = try Self.git(["rev-parse", "--is-shallow-repository"])
        XCTAssertEqual(shallow.status, 0, "tests must run inside the git checkout")
        let commit = try Self.git(["cat-file", "-e", "\(Self.pinnedWinMergeCommit)^{commit}"])
        if commit.status != 0 {
            if shallow.output == "true" {
                throw XCTSkip("shallow clone lacks fixture-winmerge-commit \(Self.pinnedWinMergeCommit); the full-history CI gate verifies it")
            }
            XCTFail("fixture-winmerge-commit \(Self.pinnedWinMergeCommit) does not resolve in this non-shallow checkout")
            throw XCTSkip("cannot continue without the fixture commit")
        }
        let tree = try Self.git(["rev-parse", "--verify", "--quiet", "\(Self.pinnedWinMergeCommit):Externals/xdiff"])
        XCTAssertEqual(tree.status, 0)
        return tree.output
    }

    // Finding: the pinned commit and xdiff tree are verified against the real repository.
    func testPinnedFixtureCommitAndXDiffTreeResolveInRepository() throws {
        XCTAssertEqual(try resolvedPinnedXDiffTree(), Self.pinnedXDiffTree)
        let lock = try DiffOracleCoverageLock.parse(try readRepositoryFile(DiffOracleCoverageLock.defaultRelativePath))
        var snapshot = try DiffOracleCoverageSnapshot.load(repositoryRoot: Self.repositoryRoot, lock: lock)
        snapshot.observedFixtureXDiffTree = try resolvedPinnedXDiffTree()
        XCTAssertFalse(
            DiffOracleCoverageAudit.audit(lock: lock, snapshot: snapshot).findings.contains {
                if case .fixtureXDiffTreeMismatch = $0 { return true } else { return false }
            })
    }

    // Finding: alignment paths must include pcre2 and text decoding/splitting code.
    func testCheckedInAlignmentPathsCoverRegexAndTextDecoding() throws {
        let lock = try DiffOracleCoverageLock.parse(try readRepositoryFile(DiffOracleCoverageLock.defaultRelativePath))
        for path in [
            "Externals/xdiff",
            "Externals/poco/dependencies/pcre2/src",
            "MacMerge/Sources/CXDiff",
            "MacMerge/Sources/MacMergeCore/LineDiff.swift",
            "MacMerge/Sources/MacMergeCore/TextFileCodec.swift",
            "MacMerge/Sources/MacMergeCore/TextFileDocument.swift"
        ] {
            XCTAssertTrue(lock.alignmentPaths.contains(path), path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: Self.repositoryRoot.appendingPathComponent(path).path), path)
        }
        let vendor = try readRepositoryFile("MacMerge/Sources/CXDiff/vendor_pcre2.c")
        XCTAssertTrue(vendor.contains("Externals/poco/dependencies/pcre2/src/"))
    }

    // Integration: the checked-in lock matches the checked-in fixtures. Locally, alignment fingerprint
    // drift is tolerated because work in progress edits alignment sources and the lock is refreshed with
    // `Scripts/check-diff-oracle-coverage.sh --refresh` before committing. In CI (CI=true) the committed
    // lock must match exactly, so a stale fingerprint fails here as well as in the gate step.
    func testCheckedInLockMatchesCheckedInFixtures() throws {
        let lock = try DiffOracleCoverageLock.parse(try readRepositoryFile(DiffOracleCoverageLock.defaultRelativePath))
        let snapshot = try DiffOracleCoverageSnapshot.load(repositoryRoot: Self.repositoryRoot, lock: lock)
        XCTAssertTrue(snapshot.missingAlignmentPaths.isEmpty, "\(snapshot.missingAlignmentPaths)")
        let enforceFingerprint = ProcessInfo.processInfo.environment["CI"] == "true"
        let findings = DiffOracleCoverageAudit.audit(lock: lock, snapshot: snapshot).findings.filter {
            if case .alignmentChanged = $0 { return enforceFingerprint }
            return true
        }
        XCTAssertEqual(findings, [], findings.map(\.description).joined(separator: "\n"))

        // Counts come from the real DiffWrapper sources, not the lock.
        XCTAssertEqual(snapshot.diffWrapperTests.count, 6)
        XCTAssertEqual(snapshot.diffWrapperTests.reduce(0) { $0 + $1.rightFileSiteCount }, 22)
        let eol = try XCTUnwrap(snapshot.diffWrapperTests.first { $0.id == "DiffWrapper.RunFileDiff_IgnoreMissingTrailingEol" })
        XCTAssertEqual(eol.rightFileSiteCount, 6)
    }

    private func workflowSection(_ text: String, from start: String, to end: String) throws -> Substring {
        let lower = try XCTUnwrap(text.range(of: start))
        let upper = try XCTUnwrap(text.range(of: end, range: lower.upperBound..<text.endIndex))
        return text[lower.upperBound..<upper.lowerBound]
    }

    // Finding: fixture-only changes must trigger the workflow.
    func testWorkflowPathFiltersIncludeFixtureDirectories() throws {
        let workflow = try readRepositoryFile(".github/workflows/macmerge.yml")
        let push = try workflowSection(workflow, from: "\n  push:", to: "\n  pull_request:")
        let pullRequest = try workflowSection(workflow, from: "\n  pull_request:", to: "\npermissions:")
        for section in [push, pullRequest] {
            for path in [
                "Testing/GoogleTest/DiffWrapper/**", "Testing/Data/**", "MacMerge/**", "Externals/xdiff/**",
                "Externals/poco/dependencies/pcre2/**"
            ] {
                XCTAssertTrue(section.contains("- \"\(path)\""), "missing \(path) in \(section)")
            }
        }
    }

    /// Splits a job's steps into key/value maps, ignoring indentation. Good enough for flat step keys.
    private func workflowSteps(_ workflow: String, job: String) throws -> [[String: String]] {
        let lines = workflow.components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "\(job):" }, job)
        let jobIndent = lines[start].prefix { $0 == " " }.count
        var steps: [[String: String]] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if line.prefix(while: { $0 == " " }).count <= jobIndent { break }
            var entry = Substring(trimmed)
            if entry.hasPrefix("- ") {
                steps.append([:])
                entry = entry.dropFirst(2)
            }
            guard !steps.isEmpty, let colon = entry.firstIndex(of: ":") else { continue }
            let key = entry[..<colon].trimmingCharacters(in: .whitespaces)
            let value = entry[entry.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            steps[steps.count - 1][key] = value
        }
        return steps
    }

    // Finding: the gate runs as its own named step with full history, and the CI self-test enforces both.
    func testWorkflowRunsGateAsNamedStepAndSelfTestRequiresIt() throws {
        let workflow = try readRepositoryFile(".github/workflows/macmerge.yml")
        let steps = try workflowSteps(workflow, job: "quality")
        XCTAssertTrue(
            steps.contains { $0["name"] == "Check diff oracle coverage" && $0["run"] == "Scripts/check-diff-oracle-coverage.sh" },
            "quality job lacks the 'Check diff oracle coverage' step")
        let checkout = try XCTUnwrap(steps.first { $0["uses"]?.hasPrefix("actions/checkout@") == true })
        XCTAssertEqual(checkout["fetch-depth"], "0", "quality checkout must fetch full history to resolve the pinned commit")

        let selfTest = try readRepositoryFile("MacMerge/Scripts/test-ci-quality.sh")
        XCTAssertTrue(selfTest.contains("\"Testing/GoogleTest/DiffWrapper/**\","))
        XCTAssertTrue(selfTest.contains("\"Testing/Data/**\","))
        XCTAssertTrue(selfTest.contains("step[\"name\"] == \"Check diff oracle coverage\""))
        XCTAssertTrue(selfTest.contains("diff oracle gate accepted an unreviewed alignment change"))
        XCTAssertTrue(selfTest.contains("MacMerge alignment sources changed (fingerprint $zero_fingerprint ->"))
        XCTAssertTrue(selfTest.contains("cmp -s"))
        XCTAssertTrue(selfTest.contains("fetch-depth"))
        // Only the negative self-test runs here; the positive gate is the workflow step.
        let invocation = try NSRegularExpression(pattern: #"check-diff-oracle-coverage\.sh"?\s+--lock\b"#)
        let anyInvocation = try NSRegularExpression(pattern: #""\$package_root/Scripts/check-diff-oracle-coverage\.sh""#)
        let range = NSRange(selfTest.startIndex..., in: selfTest)
        XCTAssertEqual(invocation.numberOfMatches(in: selfTest, range: range), 1)
        XCTAssertEqual(anyInvocation.numberOfMatches(in: selfTest, range: range), 1)
    }

    func testGateScriptCompilesLaneSourcesAndForwardsOptions() throws {
        let script = try readRepositoryFile("MacMerge/Scripts/check-diff-oracle-coverage.sh")
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("-warnings-as-errors"))
        XCTAssertTrue(script.contains("Sources/MacMergeCore/DiffOracleManifest.swift"))
        XCTAssertTrue(script.contains("Sources/MacMergeCore/DiffOracleFixtureCoverage.swift"))
        XCTAssertTrue(script.contains("Scripts/DiffOracleCoverageGate/main.swift"))
        XCTAssertTrue(script.contains("DIFF_ORACLE_REQUIRE_GOLDENS"))
        XCTAssertTrue(script.contains("--require-goldens"))
        XCTAssertTrue(script.contains("\"$@\""))

        let driver = try readRepositoryFile("MacMerge/Scripts/DiffOracleCoverageGate/main.swift")
        for option in ["--repository-root", "--lock", "--require-goldens", "--refresh"] {
            XCTAssertTrue(driver.contains("\"\(option)\""), option)
        }
        XCTAssertTrue(driver.contains("rev-parse"))
        XCTAssertTrue(driver.contains("not verified"))
        XCTAssertFalse(driver.contains("import MacMergeCore"))
    }

    // MARK: Gate executable against synthetic repositories

    private struct GateRun {
        let status: Int32
        let output: String
    }

    private func run(_ executable: URL, _ arguments: [String], environment: [String: String] = [:]) throws -> GateRun {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return GateRun(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// A synthetic repository with a refreshed lock holding one valid golden, laid out like the real one.
    private func makeGateRepository() throws -> (SyntheticRepository, URL, String) {
        let (repo, base) = try makeRepository()
        try write("golden", to: repo.root.appendingPathComponent("MacMerge/DiffOracle/goldens/g1.json"))
        var lock = base
        lock.goldens = [
            DiffOracleCoverageLock.Golden(
                id: "g1", source: .diffWrapper("DiffWrapper.A"), provenance: provenance(),
                alignmentFingerprint: try DiffOracleSHA256(hex: base.alignmentFingerprint),
                path: "MacMerge/DiffOracle/goldens/g1.json",
                sha256: try DiffOracleSHA256(hex: DiffOracleFixtureDiscovery.sha256Hex(Data("golden".utf8))))
        ]
        let lockURL = repo.root.appendingPathComponent(DiffOracleCoverageLock.defaultRelativePath)
        try write(lock.serialized(), to: lockURL)
        let goldenLine = try XCTUnwrap(lock.serialized().split(separator: "\n").first { $0.hasPrefix("golden ") })
        return (repo, lockURL, String(goldenLine))
    }

    // Finding: exercise the real gate binary and wrapper script, not just their text.
    func testGateExecutableOnSyntheticRepositories() throws {
        let build = try makeTemporaryDirectory()
        let gate = build.appendingPathComponent("diff-oracle-coverage-gate")
        let compile = try run(
            URL(fileURLWithPath: "/usr/bin/xcrun"),
            [
                "swiftc", "-warnings-as-errors", "-module-name", "DiffOracleCoverageGate",
                Self.packageRoot.appendingPathComponent("Sources/MacMergeCore/DiffOracleManifest.swift").path,
                Self.packageRoot.appendingPathComponent("Sources/MacMergeCore/DiffOracleFixtureCoverage.swift").path,
                Self.packageRoot.appendingPathComponent("Scripts/DiffOracleCoverageGate/main.swift").path,
                "-o", gate.path
            ])
        XCTAssertEqual(compile.status, 0, compile.output)
        guard compile.status == 0 else { return }

        // Not a git checkout: passes, and says the tree pin was not verified.
        let (repo, lockURL, goldenLine) = try makeGateRepository()
        var result = try run(gate, ["--repository-root", repo.root.path])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("1 golden results"), result.output)
        XCTAssertTrue(result.output.contains("fixture-xdiff-tree not verified (not a git checkout)"), result.output)

        result = try run(gate, ["--repository-root", repo.root.path, "--require-goldens"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("testing-data:Req has no WinMerge golden result"), result.output)

        // --refresh rewrites digests but leaves the golden record byte-identical.
        try write("align v2", to: repo.root.appendingPathComponent("Src/Align.swift"))
        result = try run(gate, ["--repository-root", repo.root.path, "--refresh"])
        XCTAssertNotEqual(result.status, 0, "refresh must not hide a stale golden: \(result.output)")
        XCTAssertTrue(result.output.contains("golden g1"), result.output)
        let refreshed = try String(contentsOf: lockURL, encoding: .utf8)
        XCTAssertTrue(refreshed.split(separator: "\n").contains { $0 == goldenLine }, refreshed)

        // A full (non-shallow) clone that cannot resolve the pinned commit must fail.
        let (gitRepo, _, _) = try makeGateRepository()
        XCTAssertEqual(try Self.git(["init", "--quiet"], in: gitRepo.root).status, 0)
        result = try run(gate, ["--repository-root", gitRepo.root.path])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("cannot be resolved in this non-shallow checkout"), result.output)
    }

    // The wrapper script compiles the gate and forwards DIFF_ORACLE_REQUIRE_GOLDENS and extra options.
    func testGateScriptForwardsRequireGoldensEnvironment() throws {
        let (repo, lockURL, _) = try makeGateRepository()
        let script = Self.packageRoot.appendingPathComponent("Scripts/check-diff-oracle-coverage.sh")
        // The script derives the repository root from its own location, so point --repository-root and
        // --lock at the synthetic repository explicitly; the later argument wins.
        let arguments = ["--repository-root", repo.root.path, "--lock", lockURL.path]
        var result = try run(script, arguments)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("not verified"), result.output)
        result = try run(script, arguments, environment: ["DIFF_ORACLE_REQUIRE_GOLDENS": "1"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("has no WinMerge golden result"), result.output)
    }

    func testReadmeStatesLimitsHonestly() throws {
        let readme = try readRepositoryFile("MacMerge/DiffOracle/README.md")
        XCTAssertTrue(readme.contains("right-file-sites"))
        XCTAssertTrue(readme.contains("**not** the number of comparisons"))
        XCTAssertTrue(readme.contains("fingerprint acknowledgement only"))
        XCTAssertTrue(readme.contains("does not prove WinMerge parity"))
        XCTAssertTrue(readme.contains("Check diff oracle coverage"))
        XCTAssertTrue(readme.contains("`DiffOracleGoldenProvenance`"))
        XCTAssertFalse(readme.contains("case count"))
    }
}
