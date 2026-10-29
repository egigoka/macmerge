import CryptoKit
import Foundation

// Differential-oracle fixture coverage gate.
//
// `MacMerge/DiffOracle/coverage.lock` is a reviewed, line-oriented inventory that:
// - pins the WinMerge commit (and its `Externals/xdiff` tree) every golden result must be generated from,
// - digests the whole `Testing/GoogleTest/DiffWrapper` directory, so shared helpers and non-test
//   files cannot change without review,
// - classifies every `Testing/GoogleTest/DiffWrapper` test and every top-level
//   `Testing/Data` entry, recording content digests so fixture edits need review,
// - fingerprints the MacMerge alignment sources so alignment changes need review,
// - lists golden results, each carrying a full `DiffOracleGoldenProvenance`, the alignment
//   fingerprint it was reviewed against, and its own SHA-256.
//
// Provenance and digest values reuse the `DiffOracleManifest.swift` value types
// (`DiffOracleGitObjectID`, `DiffOracleSHA256`, `DiffOracleIdentifier`, `DiffOracleGoldenProvenance`).
// The lock is a coarse, per-test and per-top-level-entry inventory; the manifest's
// `DiffOracleCorpusManifestEntry` records are the per-case and per-file refinement a future
// Windows oracle runner emits for each required lock source.
//
// This file depends only on Foundation, CryptoKit, and `DiffOracleManifest.swift`, so
// `Scripts/check-diff-oracle-coverage.sh` can compile the two files together with a small
// driver without building the package.

public enum DiffOracleCoverageLockError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformedLine(lineNumber: Int, reason: String)
    case missingHeader(String)
    case unsupportedFormat(String)

    public var description: String {
        switch self {
        case .malformedLine(let lineNumber, let reason):
            return "coverage.lock line \(lineNumber): \(reason)"
        case .missingHeader(let name):
            return "coverage.lock is missing required header '\(name)'"
        case .unsupportedFormat(let value):
            return "coverage.lock format '\(value)' is unsupported"
        }
    }
}

/// Content digest of one file or one directory tree.
public struct DiffOracleContentDigest: Hashable, Sendable {
    public let fileCount: Int
    public let sha256: String

    public init(fileCount: Int, sha256: String) {
        self.fileCount = fileCount
        self.sha256 = sha256
    }
}

/// A source of oracle fixtures that golden results attach to.
public enum DiffOracleFixtureSource: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// `Suite.Name` of a GoogleTest test under `Testing/GoogleTest/DiffWrapper`.
    case diffWrapper(String)
    /// Top-level entry name under `Testing/Data`.
    case testingData(String)

    static let diffWrapperPrefix = "diffwrapper:"
    static let testingDataPrefix = "testing-data:"

    public init?(reference: String) {
        if reference.hasPrefix(Self.diffWrapperPrefix) {
            let name = String(reference.dropFirst(Self.diffWrapperPrefix.count))
            guard !name.isEmpty else { return nil }
            self = .diffWrapper(name)
        } else if reference.hasPrefix(Self.testingDataPrefix) {
            let name = String(reference.dropFirst(Self.testingDataPrefix.count))
            guard !name.isEmpty else { return nil }
            self = .testingData(name)
        } else {
            return nil
        }
    }

    public var description: String {
        switch self {
        case .diffWrapper(let name): return Self.diffWrapperPrefix + name
        case .testingData(let name): return Self.testingDataPrefix + name
        }
    }

    public static func < (left: Self, right: Self) -> Bool {
        Array(left.description.utf8).lexicographicallyPrecedes(Array(right.description.utf8))
    }
}

public struct DiffOracleCoverageLock: Hashable, Sendable {
    public static let formatVersion = "1"
    public static let defaultRelativePath = "MacMerge/DiffOracle/coverage.lock"
    public static let diffWrapperRelativePath = "Testing/GoogleTest/DiffWrapper"
    public static let testingDataRelativePath = "Testing/Data"
    public static let windowsXDiffRelativePath = "Externals/xdiff"
    public static let goldenRelativeDirectory = "MacMerge/DiffOracle/goldens"
    /// Label used for paths inside the `diffwrapper-tree` digest.
    static let diffWrapperTreeLabel = "DiffWrapper"

    public struct DiffWrapperTest: Hashable, Sendable {
        public let id: String
        /// Number of `right = WriteToTempFile(` source sites in the test body. This is a source-site
        /// count, not the number of comparisons the test runs: loops over algorithms or EOL styles
        /// multiply the real case count.
        public let rightFileSiteCount: Int
        public let sha256: String

        public init(id: String, rightFileSiteCount: Int, sha256: String) {
            self.id = id
            self.rightFileSiteCount = rightFileSiteCount
            self.sha256 = sha256
        }
    }

    public enum TestingDataDisposition: Hashable, Sendable {
        case required(DiffOracleContentDigest)
        case excluded(reason: String)
    }

    public struct TestingDataEntry: Hashable, Sendable {
        public let name: String
        public let disposition: TestingDataDisposition

        public init(name: String, disposition: TestingDataDisposition) {
            self.name = name
            self.disposition = disposition
        }
    }

    public struct Golden: Hashable, Sendable {
        public let id: String
        public let source: DiffOracleFixtureSource
        /// Windows oracle provenance, field-for-field the manifest's `DiffOracleGoldenProvenance`.
        public let provenance: DiffOracleGoldenProvenance
        /// MacMerge alignment fingerprint this golden was last reviewed against.
        public let alignmentFingerprint: DiffOracleSHA256
        /// Repository-relative path of the normalized golden result.
        public let path: String
        public let sha256: DiffOracleSHA256

        public init(
            id: String,
            source: DiffOracleFixtureSource,
            provenance: DiffOracleGoldenProvenance,
            alignmentFingerprint: DiffOracleSHA256,
            path: String,
            sha256: DiffOracleSHA256
        ) {
            self.id = id
            self.source = source
            self.provenance = provenance
            self.alignmentFingerprint = alignmentFingerprint
            self.path = path
            self.sha256 = sha256
        }
    }

    /// WinMerge commit the checked-in fixtures were taken from; every golden must be generated from it.
    public var fixtureWinMergeCommit: DiffOracleGitObjectID
    /// Git tree ID of `Externals/xdiff` at `fixtureWinMergeCommit`; every golden's Windows xdiff tree must match it.
    public var fixtureXDiffTree: DiffOracleGitObjectID
    /// Digest of every file under `Testing/GoogleTest/DiffWrapper`, including shared helpers outside any `TEST`.
    public var diffWrapperDirectory: DiffOracleContentDigest
    /// Repository-relative files or directories whose bytes determine MacMerge alignment.
    public var alignmentPaths: [String]
    public var alignmentFingerprint: String
    public var diffWrapperTests: [DiffWrapperTest]
    public var testingData: [TestingDataEntry]
    public var goldens: [Golden]

    public init(
        fixtureWinMergeCommit: DiffOracleGitObjectID,
        fixtureXDiffTree: DiffOracleGitObjectID,
        diffWrapperDirectory: DiffOracleContentDigest,
        alignmentPaths: [String],
        alignmentFingerprint: String,
        diffWrapperTests: [DiffWrapperTest],
        testingData: [TestingDataEntry],
        goldens: [Golden]
    ) {
        self.fixtureWinMergeCommit = fixtureWinMergeCommit
        self.fixtureXDiffTree = fixtureXDiffTree
        self.diffWrapperDirectory = diffWrapperDirectory
        self.alignmentPaths = alignmentPaths
        self.alignmentFingerprint = alignmentFingerprint
        self.diffWrapperTests = diffWrapperTests
        self.testingData = testingData
        self.goldens = goldens
    }

    /// Sources that must eventually be backed by at least one golden result.
    public var requiredSources: [DiffOracleFixtureSource] {
        let wrapper = diffWrapperTests.map { DiffOracleFixtureSource.diffWrapper($0.id) }
        let data = testingData.compactMap { entry -> DiffOracleFixtureSource? in
            if case .required = entry.disposition { return .testingData(entry.name) }
            return nil
        }
        return Array(Set(wrapper + data)).sorted()
    }

    // MARK: Parsing

    public static func parse(_ text: String) throws -> DiffOracleCoverageLock {
        var format: String?
        var commit: DiffOracleGitObjectID?
        var xdiffTree: DiffOracleGitObjectID?
        var wrapperDirectory: DiffOracleContentDigest?
        var fingerprint: String?
        var alignmentPaths: [String] = []
        var wrapper: [DiffWrapperTest] = []
        var data: [TestingDataEntry] = []
        var goldens: [Golden] = []
        var seen: Set<String> = []

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            func fail(_ reason: String) -> DiffOracleCoverageLockError {
                .malformedLine(lineNumber: lineNumber, reason: reason)
            }
            func unique(_ key: String) throws {
                guard seen.insert(key).inserted else { throw fail("duplicate entry '\(key)'") }
            }
            func single(_ name: String) throws -> String {
                guard tokens.count == 2 else { throw fail("'\(name)' takes exactly one value") }
                return tokens[1]
            }
            func objectID(_ name: String, _ value: String?) throws -> DiffOracleGitObjectID {
                guard let value, let id = try? DiffOracleGitObjectID(value) else {
                    throw fail("\(name) must be a full 40-digit lowercase git object ID")
                }
                return id
            }
            func digest(_ name: String, _ value: String?) throws -> DiffOracleSHA256 {
                guard let value, let digest = try? DiffOracleSHA256(hex: value) else {
                    throw fail("\(name) must be 64 lowercase hex digits")
                }
                return digest
            }

            switch tokens[0] {
            case "format":
                try unique("format")
                format = try single("format")
            case "fixture-winmerge-commit":
                try unique("fixture-winmerge-commit")
                commit = try objectID("fixture-winmerge-commit", try single("fixture-winmerge-commit"))
            case "fixture-xdiff-tree":
                try unique("fixture-xdiff-tree")
                xdiffTree = try objectID("fixture-xdiff-tree", try single("fixture-xdiff-tree"))
            case "diffwrapper-tree":
                try unique("diffwrapper-tree")
                let fields = try keyValues(Array(tokens.dropFirst()), allowed: ["files", "sha256"], fail: fail)
                guard let filesText = fields["files"], let files = Int(filesText), files >= 0 else {
                    throw fail("diffwrapper-tree needs files=<non-negative integer>")
                }
                guard let sha = fields["sha256"], isSHA256(sha) else { throw fail("diffwrapper-tree needs sha256=<64 hex>") }
                wrapperDirectory = DiffOracleContentDigest(fileCount: files, sha256: sha)
            case "alignment-fingerprint":
                try unique("alignment-fingerprint")
                let value = try single("alignment-fingerprint")
                guard isSHA256(value) else { throw fail("alignment-fingerprint must be 64 lowercase hex digits") }
                fingerprint = value
            case "alignment-path":
                let value = try single("alignment-path")
                guard isSafeRelativePath(value) else { throw fail("alignment-path must be a normalized repository-relative path") }
                try unique("alignment-path \(value)")
                alignmentPaths.append(value)
            case "diffwrapper":
                guard tokens.count >= 2 else { throw fail("diffwrapper needs a test ID") }
                let id = tokens[1]
                guard isTestID(id) else { throw fail("diffwrapper ID must be ASCII Suite.Name") }
                try unique("diffwrapper \(id)")
                let fields = try keyValues(Array(tokens.dropFirst(2)), allowed: ["right-file-sites", "sha256"], fail: fail)
                guard let sitesText = fields["right-file-sites"], let sites = Int(sitesText), sites >= 0 else {
                    throw fail("diffwrapper needs right-file-sites=<non-negative integer>")
                }
                guard let sha = fields["sha256"], isSHA256(sha) else { throw fail("diffwrapper needs sha256=<64 hex>") }
                wrapper.append(DiffWrapperTest(id: id, rightFileSiteCount: sites, sha256: sha))
            case "testing-data":
                guard tokens.count >= 3 else { throw fail("testing-data needs a name and disposition") }
                let name = tokens[1]
                guard isTestingDataName(name) else {
                    throw fail("testing-data name must be one top-level entry without whitespace or '='")
                }
                try unique("testing-data \(name)")
                let rest = Array(tokens.dropFirst(3))
                switch tokens[2] {
                case "required":
                    let fields = try keyValues(rest, allowed: ["files", "sha256"], fail: fail)
                    guard let filesText = fields["files"], let files = Int(filesText), files >= 0 else {
                        throw fail("required testing-data needs files=<non-negative integer>")
                    }
                    guard let sha = fields["sha256"], isSHA256(sha) else {
                        throw fail("required testing-data needs sha256=<64 hex>")
                    }
                    data.append(
                        TestingDataEntry(
                            name: name,
                            disposition: .required(DiffOracleContentDigest(fileCount: files, sha256: sha))
                        ))
                case "excluded":
                    let fields = try keyValues(rest, allowed: ["reason"], fail: fail)
                    guard let reason = fields["reason"], isASCIIComponent(reason, allowing: "-") else {
                        throw fail("excluded testing-data needs reason=<kebab-case-reason>")
                    }
                    data.append(TestingDataEntry(name: name, disposition: .excluded(reason: reason)))
                default:
                    throw fail("testing-data disposition must be 'required' or 'excluded'")
                }
            case "golden":
                guard tokens.count >= 2 else { throw fail("golden needs an ID") }
                let id = tokens[1]
                guard isASCIIComponent(id, allowing: "-_.") else { throw fail("golden ID has invalid characters") }
                try unique("golden \(id)")
                let fields = try keyValues(
                    Array(tokens.dropFirst(2)),
                    allowed: Set(goldenFieldKeys),
                    fail: fail
                )
                func identifier(_ key: String) throws -> DiffOracleIdentifier {
                    guard let value = fields[key], isASCIIComponent(value, allowing: "-_."),
                        let identifier = try? DiffOracleIdentifier(value)
                    else {
                        throw fail("golden needs \(key)=<ASCII identifier>")
                    }
                    return identifier
                }
                guard let sourceText = fields["source"], let source = DiffOracleFixtureSource(reference: sourceText) else {
                    throw fail("golden needs source=diffwrapper:<Suite.Name> or source=testing-data:<name>")
                }
                let provenance = DiffOracleGoldenProvenance(
                    winMergeCommit: try objectID("golden winmerge-commit", fields["winmerge-commit"]),
                    windowsXDiffTree: try objectID("golden xdiff-tree", fields["xdiff-tree"]),
                    topLevelLibXDiffCommit: try objectID("golden libxdiff-commit", fields["libxdiff-commit"]),
                    topLevelLibXDiffTree: try objectID("golden libxdiff-tree", fields["libxdiff-tree"]),
                    nestedLibXDiffCommit: try objectID("golden nested-libxdiff-commit", fields["nested-libxdiff-commit"]),
                    nestedLibXDiffTree: try objectID("golden nested-libxdiff-tree", fields["nested-libxdiff-tree"]),
                    oracleExecutableSHA256: try digest("golden oracle-executable", fields["oracle-executable"]),
                    generatorVersion: try identifier("generator-version"),
                    generatorExecutableSHA256: try digest("golden generator-executable", fields["generator-executable"]),
                    generatorSchemaSHA256: try digest("golden generator-schema", fields["generator-schema"]),
                    generatorConfigurationSHA256: try digest("golden generator-configuration", fields["generator-configuration"]),
                    architecture: try identifier("architecture"),
                    buildConfiguration: try identifier("build-configuration")
                )
                guard let path = fields["path"], isSafeRelativePath(path),
                    path.hasPrefix(goldenRelativeDirectory + "/")
                else {
                    throw fail("golden path must be under \(goldenRelativeDirectory)/")
                }
                goldens.append(
                    Golden(
                        id: id,
                        source: source,
                        provenance: provenance,
                        alignmentFingerprint: try digest("golden alignment", fields["alignment"]),
                        path: path,
                        sha256: try digest("golden sha256", fields["sha256"])
                    ))
            default:
                throw fail("unknown record '\(tokens[0])'")
            }
        }

        guard let format else { throw DiffOracleCoverageLockError.missingHeader("format") }
        guard format == formatVersion else { throw DiffOracleCoverageLockError.unsupportedFormat(format) }
        guard let commit else { throw DiffOracleCoverageLockError.missingHeader("fixture-winmerge-commit") }
        guard let xdiffTree else { throw DiffOracleCoverageLockError.missingHeader("fixture-xdiff-tree") }
        guard let wrapperDirectory else { throw DiffOracleCoverageLockError.missingHeader("diffwrapper-tree") }
        guard let fingerprint else { throw DiffOracleCoverageLockError.missingHeader("alignment-fingerprint") }
        guard !alignmentPaths.isEmpty else { throw DiffOracleCoverageLockError.missingHeader("alignment-path") }

        return DiffOracleCoverageLock(
            fixtureWinMergeCommit: commit,
            fixtureXDiffTree: xdiffTree,
            diffWrapperDirectory: wrapperDirectory,
            alignmentPaths: alignmentPaths,
            alignmentFingerprint: fingerprint,
            diffWrapperTests: wrapper,
            testingData: data,
            goldens: goldens
        )
    }

    /// Golden record keys. Each provenance key maps to the `DiffOracleGoldenProvenance` property of the same position.
    static let goldenFieldKeys = [
        "source",
        "winmerge-commit",  // winMergeCommit
        "xdiff-tree",  // windowsXDiffTree
        "libxdiff-commit",  // topLevelLibXDiffCommit
        "libxdiff-tree",  // topLevelLibXDiffTree
        "nested-libxdiff-commit",  // nestedLibXDiffCommit
        "nested-libxdiff-tree",  // nestedLibXDiffTree
        "oracle-executable",  // oracleExecutableSHA256
        "generator-version",  // generatorVersion
        "generator-executable",  // generatorExecutableSHA256
        "generator-schema",  // generatorSchemaSHA256
        "generator-configuration",  // generatorConfigurationSHA256
        "architecture",  // architecture
        "build-configuration",  // buildConfiguration
        "alignment",
        "path",
        "sha256"
    ]

    // MARK: Serialization

    /// Canonical text form. Entries are sorted by UTF-8 bytes so refreshed locks produce minimal diffs.
    public func serialized(header: String = Self.defaultHeaderComment) -> String {
        var lines: [String] = header.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.append("format \(Self.formatVersion)")
        lines.append("fixture-winmerge-commit \(fixtureWinMergeCommit.rawValue)")
        lines.append("fixture-xdiff-tree \(fixtureXDiffTree.rawValue)")
        lines.append("")
        lines.append(contentsOf: alignmentPaths.sortedByUTF8 { $0 }.map { "alignment-path \($0)" })
        lines.append("alignment-fingerprint \(alignmentFingerprint)")
        lines.append("")
        lines.append("diffwrapper-tree files=\(diffWrapperDirectory.fileCount) sha256=\(diffWrapperDirectory.sha256)")
        lines.append(
            contentsOf: diffWrapperTests.sortedByUTF8 { $0.id }.map {
                "diffwrapper \($0.id) right-file-sites=\($0.rightFileSiteCount) sha256=\($0.sha256)"
            })
        lines.append("")
        lines.append(
            contentsOf: testingData.sortedByUTF8 { $0.name }.map { entry in
                switch entry.disposition {
                case .required(let digest):
                    return "testing-data \(entry.name) required files=\(digest.fileCount) sha256=\(digest.sha256)"
                case .excluded(let reason):
                    return "testing-data \(entry.name) excluded reason=\(reason)"
                }
            })
        if !goldens.isEmpty {
            lines.append("")
            lines.append(contentsOf: goldens.sortedByUTF8 { $0.id }.map(Self.serializedGolden))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func serializedGolden(_ golden: Golden) -> String {
        let provenance = golden.provenance
        let values = [
            golden.source.description,
            provenance.winMergeCommit.rawValue,
            provenance.windowsXDiffTree.rawValue,
            provenance.topLevelLibXDiffCommit.rawValue,
            provenance.topLevelLibXDiffTree.rawValue,
            provenance.nestedLibXDiffCommit.rawValue,
            provenance.nestedLibXDiffTree.rawValue,
            provenance.oracleExecutableSHA256.hex,
            provenance.generatorVersion.rawValue,
            provenance.generatorExecutableSHA256.hex,
            provenance.generatorSchemaSHA256.hex,
            provenance.generatorConfigurationSHA256.hex,
            provenance.architecture.rawValue,
            provenance.buildConfiguration.rawValue,
            golden.alignmentFingerprint.hex,
            golden.path,
            golden.sha256.hex
        ]
        let fields = zip(goldenFieldKeys, values).map { "\($0)=\($1)" }
        return (["golden", golden.id] + fields).joined(separator: " ")
    }

    public static let defaultHeaderComment = """
        # MacMerge differential-oracle coverage lock. Reviewed input; see MacMerge/DiffOracle/README.md.
        # Verified by Scripts/check-diff-oracle-coverage.sh in the CI quality job.
        """

    /// Returns a copy whose recorded digests match `snapshot`.
    ///
    /// Newly discovered DiffWrapper tests are added unless the lock cannot represent their IDs;
    /// newly discovered `Testing/Data` entries are not, because each needs a reviewed
    /// required/excluded decision. Golden records are never changed: a golden whose alignment
    /// fingerprint no longer matches keeps failing until the WinMerge oracle result is regenerated
    /// or re-reviewed.
    public func refreshed(with snapshot: DiffOracleCoverageSnapshot) -> DiffOracleCoverageLock {
        var copy = self
        copy.alignmentFingerprint = snapshot.alignmentFingerprint ?? alignmentFingerprint
        copy.diffWrapperDirectory = snapshot.diffWrapperDirectory
        var seenTests: Set<String> = []
        copy.diffWrapperTests = snapshot.diffWrapperTests.compactMap {
            guard Self.isTestID($0.id), seenTests.insert($0.id).inserted else { return nil }
            return DiffWrapperTest(id: $0.id, rightFileSiteCount: $0.rightFileSiteCount, sha256: $0.sha256)
        }
        copy.testingData = testingData.compactMap { entry in
            guard let current = snapshot.testingDataEntries[entry.name] else { return nil }
            guard case .required = entry.disposition, let digest = current else { return entry }
            return TestingDataEntry(name: entry.name, disposition: .required(digest))
        }
        return copy
    }

    // MARK: Field validation

    static func isSHA256(_ value: String) -> Bool { (try? DiffOracleSHA256(hex: value)) != nil }

    /// ASCII `Suite.Name`, the only DiffWrapper test ID form the lock can record.
    static func isTestID(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { isASCIIComponent(String($0), allowing: "") }
    }

    /// A top-level `Testing/Data` name the lock can record as one whitespace-free token.
    static func isTestingDataName(_ value: String) -> Bool {
        isSafeRelativePath(value) && !value.contains("/")
    }

    static func isASCIIComponent(_ value: String, allowing extra: String) -> Bool {
        !value.isEmpty
            && value.unicodeScalars.allSatisfy {
                ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_"
                    || extra.unicodeScalars.contains($0)
            }
    }

    static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasSuffix("/"), !value.contains("=") else { return false }
        return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
                && !$0.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 0x20 }
        }
    }

    private static func keyValues(
        _ tokens: [String],
        allowed: Set<String>,
        fail: (String) -> DiffOracleCoverageLockError
    ) throws -> [String: String] {
        var result: [String: String] = [:]
        for token in tokens {
            guard let separator = token.firstIndex(of: "=") else { throw fail("expected key=value, found '\(token)'") }
            let key = String(token[..<separator])
            let value = String(token[token.index(after: separator)...])
            guard allowed.contains(key) else { throw fail("unknown field '\(key)'") }
            guard !value.isEmpty else { throw fail("field '\(key)' is empty") }
            guard result.updateValue(value, forKey: key) == nil else { throw fail("duplicate field '\(key)'") }
        }
        return result
    }
}

// MARK: - Discovery

public struct DiffOracleDiscoveredDiffWrapperTest: Hashable, Sendable {
    public let id: String
    /// Number of `right = WriteToTempFile(` source sites; not the number of comparisons run.
    public let rightFileSiteCount: Int
    /// SHA-256 of the test's source text (from its `TEST(` line up to the next test or end of file).
    public let sha256: String

    public init(id: String, rightFileSiteCount: Int, sha256: String) {
        self.id = id
        self.rightFileSiteCount = rightFileSiteCount
        self.sha256 = sha256
    }
}

public enum DiffOracleFixtureDiscovery {
    public enum DiscoveryError: Error, Equatable, Sendable, CustomStringConvertible {
        case unreadable(String)
        case unsupportedFileType(String)
        case duplicateTest(String)

        public var description: String {
            switch self {
            case .unreadable(let path): return "cannot read \(path)"
            case .unsupportedFileType(let path): return "unsupported file type at \(path)"
            case .duplicateTest(let id): return "duplicate GoogleTest ID \(id)"
            }
        }
    }

    /// Extracts `TEST`, `TEST_F`, and `TEST_P` declarations from GoogleTest source.
    ///
    /// Declarations whose names are not ASCII are still returned so the audit can report them
    /// as unrepresentable instead of silently skipping them.
    public static func diffWrapperTests(inSource source: String) -> [DiffOracleDiscoveredDiffWrapperTest] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var starts: [(index: Int, id: String)] = []
        for (index, line) in lines.enumerated() {
            if let id = testID(declaredBy: String(line)) { starts.append((index, id)) }
        }
        return starts.enumerated().map { position, start in
            let end = position + 1 < starts.count ? starts[position + 1].index : lines.count
            let body = lines[start.index..<end].joined(separator: "\n")
            let sites = body.components(separatedBy: "right = WriteToTempFile(").count - 1
            return DiffOracleDiscoveredDiffWrapperTest(id: start.id, rightFileSiteCount: sites, sha256: sha256Hex(Data(body.utf8)))
        }
    }

    static func testID(declaredBy line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.firstIndex(of: "(") else { return nil }
        let macro = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        guard ["TEST", "TEST_F", "TEST_P"].contains(macro), let close = trimmed.firstIndex(of: ")"), open < close else {
            return nil
        }
        let arguments = trimmed[trimmed.index(after: open)..<close].split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard arguments.count == 2, arguments.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } })
        else { return nil }
        return "\(arguments[0]).\(arguments[1])"
    }

    /// Discovers tests in every `.cpp` file directly under `directory`.
    public static func diffWrapperTests(inDirectory directory: URL) throws -> [DiffOracleDiscoveredDiffWrapperTest] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw DiscoveryError.unreadable(directory.path)
        }
        var result: [DiffOracleDiscoveredDiffWrapperTest] = []
        var seen: Set<String> = []
        for name in names.sortedByUTF8({ $0 }) where name.hasSuffix(".cpp") {
            let url = directory.appendingPathComponent(name)
            guard let data = FileManager.default.contents(atPath: url.path) else {
                throw DiscoveryError.unreadable(url.path)
            }
            let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
            for test in diffWrapperTests(inSource: text) {
                guard seen.insert(test.id).inserted else { throw DiscoveryError.duplicateTest(test.id) }
                result.append(test)
            }
        }
        return result.sortedByUTF8 { $0.id }
    }

    /// Visible top-level entry names under `directory`.
    public static func topLevelEntries(in directory: URL) throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { !$0.hasPrefix(".") }
                .map { $0.precomposedStringWithCanonicalMapping }
                .sortedByUTF8 { $0 }
        } catch {
            throw DiscoveryError.unreadable(directory.path)
        }
    }

    /// Digest over every regular file and symbolic link at or below `url`.
    ///
    /// Each entry contributes `<label-relative path>\0<kind>:<sha256 of bytes or link target>\n`,
    /// sorted by UTF-8 bytes of NFC-normalized paths. Hidden `.DS_Store` files are ignored.
    public static func contentDigest(at url: URL, label: String) throws -> DiffOracleContentDigest {
        var entries: [(path: String, value: String)] = []
        try collect(url: url, relativePath: label, into: &entries)
        let sorted = entries.sortedByUTF8 { $0.path }
        var transcript = Data()
        for entry in sorted {
            transcript.append(contentsOf: Array(entry.path.utf8))
            transcript.append(0)
            transcript.append(contentsOf: Array(entry.value.utf8))
            transcript.append(0x0A)
        }
        return DiffOracleContentDigest(fileCount: sorted.count, sha256: sha256Hex(transcript))
    }

    private static func collect(url: URL, relativePath: String, into entries: inout [(path: String, value: String)])
        throws
    {
        let manager = FileManager.default
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: url.path)
        } catch {
            throw DiscoveryError.unreadable(url.path)
        }
        let normalized = relativePath.precomposedStringWithCanonicalMapping
        switch attributes[.type] as? FileAttributeType {
        case .typeDirectory?:
            let children: [String]
            do {
                children = try manager.contentsOfDirectory(atPath: url.path)
            } catch {
                throw DiscoveryError.unreadable(url.path)
            }
            for child in children where child != ".DS_Store" {
                try collect(url: url.appendingPathComponent(child), relativePath: normalized + "/" + child, into: &entries)
            }
        case .typeRegular?:
            guard let data = manager.contents(atPath: url.path) else { throw DiscoveryError.unreadable(url.path) }
            entries.append((normalized, "file:" + sha256Hex(data)))
        case .typeSymbolicLink?:
            let target: String
            do {
                target = try manager.destinationOfSymbolicLink(atPath: url.path)
            } catch {
                throw DiscoveryError.unreadable(url.path)
            }
            entries.append((normalized, "symlink:" + sha256Hex(Data(target.utf8))))
        default:
            throw DiscoveryError.unsupportedFileType(url.path)
        }
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Snapshot

/// Observed repository state relevant to a coverage lock.
public struct DiffOracleCoverageSnapshot: Hashable, Sendable {
    public var diffWrapperTests: [DiffOracleDiscoveredDiffWrapperTest]
    /// Digest of the whole `Testing/GoogleTest/DiffWrapper` directory.
    public var diffWrapperDirectory: DiffOracleContentDigest
    /// Top-level `Testing/Data` entry names. Values are digests for entries the lock marks required.
    public var testingDataEntries: [String: DiffOracleContentDigest?]
    /// `nil` when at least one alignment path is missing.
    public var alignmentFingerprint: String?
    public var missingAlignmentPaths: [String]
    /// SHA-256 of each golden file named by the lock; `nil` when the file is missing.
    public var goldenDigests: [String: String?]
    /// `Externals/xdiff` tree ID at the lock's fixture commit, when a caller could resolve it
    /// (for example with `git rev-parse`). `nil` means not verified, not verified-equal.
    public var observedFixtureXDiffTree: String?

    public init(
        diffWrapperTests: [DiffOracleDiscoveredDiffWrapperTest],
        diffWrapperDirectory: DiffOracleContentDigest,
        testingDataEntries: [String: DiffOracleContentDigest?],
        alignmentFingerprint: String?,
        missingAlignmentPaths: [String],
        goldenDigests: [String: String?],
        observedFixtureXDiffTree: String? = nil
    ) {
        self.diffWrapperTests = diffWrapperTests
        self.diffWrapperDirectory = diffWrapperDirectory
        self.testingDataEntries = testingDataEntries
        self.alignmentFingerprint = alignmentFingerprint
        self.missingAlignmentPaths = missingAlignmentPaths
        self.goldenDigests = goldenDigests
        self.observedFixtureXDiffTree = observedFixtureXDiffTree
    }

    public static func load(repositoryRoot: URL, lock: DiffOracleCoverageLock) throws -> DiffOracleCoverageSnapshot {
        let manager = FileManager.default
        let wrapperRoot = repositoryRoot.appendingPathComponent(DiffOracleCoverageLock.diffWrapperRelativePath)
        let wrapper = try DiffOracleFixtureDiscovery.diffWrapperTests(inDirectory: wrapperRoot)
        let wrapperDirectory = try DiffOracleFixtureDiscovery.contentDigest(
            at: wrapperRoot,
            label: DiffOracleCoverageLock.diffWrapperTreeLabel
        )

        let dataRoot = repositoryRoot.appendingPathComponent(DiffOracleCoverageLock.testingDataRelativePath)
        let required = Set(
            lock.testingData.compactMap { entry -> String? in
                if case .required = entry.disposition { return entry.name }
                return nil
            })
        var data: [String: DiffOracleContentDigest?] = [:]
        for name in try DiffOracleFixtureDiscovery.topLevelEntries(in: dataRoot) {
            data[name] =
                required.contains(name)
                ? try DiffOracleFixtureDiscovery.contentDigest(at: dataRoot.appendingPathComponent(name), label: name)
                : DiffOracleContentDigest?.none
        }

        var missing: [String] = []
        var alignmentTranscript = Data()
        for path in Set(lock.alignmentPaths).sortedByUTF8({ $0 }) {
            let url = repositoryRoot.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                missing.append(path)
                continue
            }
            let digest = try DiffOracleFixtureDiscovery.contentDigest(at: url, label: path)
            alignmentTranscript.append(contentsOf: Array("\(path)\0\(digest.fileCount)\0\(digest.sha256)\n".utf8))
        }
        let fingerprint = missing.isEmpty ? DiffOracleFixtureDiscovery.sha256Hex(alignmentTranscript) : nil

        var goldens: [String: String?] = [:]
        for golden in lock.goldens {
            let url = repositoryRoot.appendingPathComponent(golden.path)
            goldens[golden.id] = manager.contents(atPath: url.path).map(DiffOracleFixtureDiscovery.sha256Hex)
        }

        return DiffOracleCoverageSnapshot(
            diffWrapperTests: wrapper,
            diffWrapperDirectory: wrapperDirectory,
            testingDataEntries: data,
            alignmentFingerprint: fingerprint,
            missingAlignmentPaths: missing,
            goldenDigests: goldens
        )
    }
}

// MARK: - Audit

public enum DiffOracleCoverageFinding: Hashable, Sendable, CustomStringConvertible {
    case duplicateLockEntry(String)
    case duplicateDiscoveredEntry(String)
    case unlistedDiffWrapperTest(String)
    case unrepresentableDiffWrapperTest(String)
    case staleDiffWrapperTest(String)
    case diffWrapperTestChanged(id: String, lockedSites: Int, currentSites: Int)
    case diffWrapperDirectoryChanged(locked: DiffOracleContentDigest, current: DiffOracleContentDigest)
    case unlistedTestingDataEntry(String)
    case unrepresentableTestingDataEntry(String)
    case staleTestingDataEntry(String)
    case testingDataChanged(name: String, locked: DiffOracleContentDigest, current: DiffOracleContentDigest)
    case fixtureXDiffTreeMismatch(locked: String, observed: String)
    case alignmentPathMissing(String)
    case alignmentChanged(locked: String, current: String)
    case goldenUnknownSource(id: String, source: DiffOracleFixtureSource)
    case goldenWinMergeCommitMismatch(id: String, golden: String, fixtures: String)
    case goldenXDiffTreeMismatch(id: String, golden: String, fixtures: String)
    case goldenAlignmentStale(id: String)
    case goldenFileMissing(id: String, path: String)
    case goldenFileChanged(id: String, path: String)
    case missingGolden(DiffOracleFixtureSource)

    public var description: String {
        switch self {
        case .duplicateLockEntry(let key):
            return "coverage.lock lists \(key) more than once"
        case .duplicateDiscoveredEntry(let key):
            return "fixture discovery reported \(key) more than once"
        case .unlistedDiffWrapperTest(let id):
            return "DiffWrapper test \(id) is not in coverage.lock; add it and plan its WinMerge oracle result"
        case .unrepresentableDiffWrapperTest(let id):
            return "DiffWrapper test \(id) cannot be recorded in coverage.lock, which accepts only ASCII Suite.Name IDs; "
                + "rename the test or extend the lock format"
        case .staleDiffWrapperTest(let id):
            return "coverage.lock lists DiffWrapper test \(id), which no longer exists"
        case .diffWrapperTestChanged(let id, let lockedSites, let currentSites):
            return "DiffWrapper test \(id) changed (right-file sites \(lockedSites) -> \(currentSites)); review its oracle results"
        case .diffWrapperDirectoryChanged(let locked, let current):
            return "Testing/GoogleTest/DiffWrapper files changed (files \(locked.fileCount) -> \(current.fileCount), "
                + "sha256 \(current.sha256)); shared helpers affect every DiffWrapper oracle result, review them"
        case .unlistedTestingDataEntry(let name):
            return "Testing/Data/\(name) is not classified in coverage.lock; mark it required or excluded with a reason"
        case .unrepresentableTestingDataEntry(let name):
            return "Testing/Data/\(name) cannot be recorded in coverage.lock, whose names must be single tokens "
                + "without whitespace, control characters, or '='; rename the entry or extend the lock format"
        case .staleTestingDataEntry(let name):
            return "coverage.lock lists Testing/Data/\(name), which no longer exists"
        case .testingDataChanged(let name, let locked, let current):
            return "Testing/Data/\(name) fixtures changed (files \(locked.fileCount) -> \(current.fileCount), "
                + "sha256 \(current.sha256)); review its oracle results"
        case .fixtureXDiffTreeMismatch(let locked, let observed):
            return "fixture-xdiff-tree \(locked) does not match Externals/xdiff tree \(observed) at fixture-winmerge-commit"
        case .alignmentPathMissing(let path):
            return "alignment path \(path) does not exist"
        case .alignmentChanged(let locked, let current):
            return "MacMerge alignment sources changed (fingerprint \(locked) -> \(current)); regenerate or "
                + "re-review WinMerge oracle results, then update coverage.lock"
        case .goldenUnknownSource(let id, let source):
            return "golden \(id) references \(source), which is not a required fixture source"
        case .goldenWinMergeCommitMismatch(let id, let golden, let fixtures):
            return "golden \(id) was generated from WinMerge \(golden), but fixtures are pinned to \(fixtures)"
        case .goldenXDiffTreeMismatch(let id, let golden, let fixtures):
            return "golden \(id) used Windows xdiff tree \(golden), but fixtures are pinned to \(fixtures)"
        case .goldenAlignmentStale(let id):
            return "golden \(id) was reviewed against a different MacMerge alignment fingerprint; "
                + "rerun the WinMerge oracle comparison and update its alignment field"
        case .goldenFileMissing(let id, let path):
            return "golden \(id) file \(path) is missing"
        case .goldenFileChanged(let id, let path):
            return "golden \(id) file \(path) does not match its pinned sha256"
        case .missingGolden(let source):
            return "required fixture source \(source) has no WinMerge golden result"
        }
    }
}

public struct DiffOracleCoverageReport: Hashable, Sendable {
    public let findings: [DiffOracleCoverageFinding]
    /// Required sources without golden results, reported as pending when goldens are not required.
    public let pendingSources: [DiffOracleFixtureSource]

    public var passed: Bool { findings.isEmpty }
}

public enum DiffOracleCoverageAudit {
    /// - Parameter requireGoldens: when true, every required source without a golden is a finding.
    ///   Keep false until the Windows `CDiffWrapper` oracle runner can produce results.
    ///
    /// Safe for any lock or snapshot, including ones built with the public initializers that
    /// contain duplicate IDs: duplicates become findings, and the first occurrence is audited.
    public static func audit(
        lock: DiffOracleCoverageLock,
        snapshot: DiffOracleCoverageSnapshot,
        requireGoldens: Bool = false
    ) -> DiffOracleCoverageReport {
        var findings: [DiffOracleCoverageFinding] = []

        func firstByKey<Element>(
            _ elements: [Element],
            key: (Element) -> String,
            label: String,
            duplicate: (String) -> DiffOracleCoverageFinding
        ) -> [String: Element] {
            var result: [String: Element] = [:]
            for element in elements {
                let name = key(element)
                if result[name] == nil {
                    result[name] = element
                } else {
                    findings.append(duplicate("\(label) \(name)"))
                }
            }
            return result
        }

        let locked = firstByKey(
            lock.diffWrapperTests, key: \.id, label: "diffwrapper", duplicate: DiffOracleCoverageFinding.duplicateLockEntry)
        let current = firstByKey(
            snapshot.diffWrapperTests, key: \.id, label: "diffwrapper", duplicate: DiffOracleCoverageFinding.duplicateDiscoveredEntry)
        let lockedData = firstByKey(
            lock.testingData, key: \.name, label: "testing-data", duplicate: DiffOracleCoverageFinding.duplicateLockEntry)
        _ = firstByKey(lock.goldens, key: \.id, label: "golden", duplicate: DiffOracleCoverageFinding.duplicateLockEntry)

        if snapshot.diffWrapperDirectory != lock.diffWrapperDirectory {
            findings.append(.diffWrapperDirectoryChanged(locked: lock.diffWrapperDirectory, current: snapshot.diffWrapperDirectory))
        }
        for id in current.keys.sortedByUTF8({ $0 }) {
            guard let test = current[id] else { continue }
            guard DiffOracleCoverageLock.isTestID(id) else {
                findings.append(.unrepresentableDiffWrapperTest(id))
                continue
            }
            guard let entry = locked[id] else {
                findings.append(.unlistedDiffWrapperTest(id))
                continue
            }
            if entry.rightFileSiteCount != test.rightFileSiteCount || entry.sha256 != test.sha256 {
                findings.append(
                    .diffWrapperTestChanged(id: id, lockedSites: entry.rightFileSiteCount, currentSites: test.rightFileSiteCount))
            }
        }
        for id in locked.keys.sortedByUTF8({ $0 }) where current[id] == nil {
            findings.append(.staleDiffWrapperTest(id))
        }

        for name in snapshot.testingDataEntries.keys.sortedByUTF8({ $0 }) where lockedData[name] == nil {
            if DiffOracleCoverageLock.isTestingDataName(name) {
                findings.append(.unlistedTestingDataEntry(name))
            } else {
                findings.append(.unrepresentableTestingDataEntry(name))
            }
        }
        for name in lockedData.keys.sortedByUTF8({ $0 }) {
            guard let entry = lockedData[name] else { continue }
            guard let observed = snapshot.testingDataEntries[name] else {
                findings.append(.staleTestingDataEntry(name))
                continue
            }
            if case .required(let digest) = entry.disposition, let observed, observed != digest {
                findings.append(.testingDataChanged(name: name, locked: digest, current: observed))
            }
        }

        if let observed = snapshot.observedFixtureXDiffTree, observed != lock.fixtureXDiffTree.rawValue {
            findings.append(.fixtureXDiffTreeMismatch(locked: lock.fixtureXDiffTree.rawValue, observed: observed))
        }

        for path in snapshot.missingAlignmentPaths {
            findings.append(.alignmentPathMissing(path))
        }
        if let fingerprint = snapshot.alignmentFingerprint, fingerprint != lock.alignmentFingerprint {
            findings.append(.alignmentChanged(locked: lock.alignmentFingerprint, current: fingerprint))
        }

        let required = Set(lock.requiredSources)
        var covered: Set<DiffOracleFixtureSource> = []
        for golden in lock.goldens.sortedByUTF8({ $0.id }) {
            // Only a golden with no findings of its own covers its source; a broken one leaves it pending.
            let findingsBefore = findings.count
            if !required.contains(golden.source) {
                findings.append(.goldenUnknownSource(id: golden.id, source: golden.source))
            }
            if golden.provenance.winMergeCommit != lock.fixtureWinMergeCommit {
                findings.append(
                    .goldenWinMergeCommitMismatch(
                        id: golden.id,
                        golden: golden.provenance.winMergeCommit.rawValue,
                        fixtures: lock.fixtureWinMergeCommit.rawValue
                    ))
            }
            if golden.provenance.windowsXDiffTree != lock.fixtureXDiffTree {
                findings.append(
                    .goldenXDiffTreeMismatch(
                        id: golden.id,
                        golden: golden.provenance.windowsXDiffTree.rawValue,
                        fixtures: lock.fixtureXDiffTree.rawValue
                    ))
            }
            if golden.alignmentFingerprint.hex != (snapshot.alignmentFingerprint ?? lock.alignmentFingerprint) {
                findings.append(.goldenAlignmentStale(id: golden.id))
            }
            switch snapshot.goldenDigests[golden.id] {
            case .some(.some(let digest)) where digest == golden.sha256.hex:
                break
            case .some(.some):
                findings.append(.goldenFileChanged(id: golden.id, path: golden.path))
            case .some(.none), .none:
                findings.append(.goldenFileMissing(id: golden.id, path: golden.path))
            }
            if findings.count == findingsBefore {
                covered.insert(golden.source)
            }
        }

        let pending = lock.requiredSources.filter { !covered.contains($0) }
        if requireGoldens {
            findings.append(contentsOf: pending.map(DiffOracleCoverageFinding.missingGolden))
        }
        return DiffOracleCoverageReport(findings: findings, pendingSources: pending)
    }
}

extension Sequence {
    fileprivate func sortedByUTF8(_ key: (Element) -> String) -> [Element] {
        sorted { Array(key($0).utf8).lexicographicallyPrecedes(Array(key($1).utf8)) }
    }
}
