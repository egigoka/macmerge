// Driver for Scripts/check-diff-oracle-coverage.sh. Compiled together with
// Sources/MacMergeCore/DiffOracleFixtureCoverage.swift and Sources/MacMergeCore/DiffOracleManifest.swift;
// keep it free of other dependencies.
import Foundation

func usage() -> Never {
    FileHandle.standardError.write(
        Data(
            "usage: diff-oracle-coverage-gate --repository-root <path> [--lock <path>] [--require-goldens] [--refresh]\n"
                .utf8))
    exit(64)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Diff oracle coverage gate failed: \(message)\n".utf8))
    exit(1)
}

var repositoryRoot: URL?
var lockPath: String?
var requireGoldens = false
var refresh = false
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--repository-root":
        guard let value = arguments.popFirst() else { usage() }
        repositoryRoot = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    case "--lock":
        guard let value = arguments.popFirst() else { usage() }
        lockPath = value
    case "--require-goldens":
        requireGoldens = true
    case "--refresh":
        refresh = true
    default:
        usage()
    }
}
guard let repositoryRoot else { usage() }
let lockURL =
    lockPath.map { URL(fileURLWithPath: $0) }
    ?? repositoryRoot.appendingPathComponent(DiffOracleCoverageLock.defaultRelativePath)

guard let lockData = FileManager.default.contents(atPath: lockURL.path),
    let lockText = String(data: lockData, encoding: .utf8)
else {
    fail("cannot read \(lockURL.path)")
}

/// Runs git in `repositoryRoot` and returns trimmed standard output, or `nil` when git fails.
func gitOutput(_ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", repositoryRoot.path] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

do {
    let lock = try DiffOracleCoverageLock.parse(lockText)
    var snapshot = try DiffOracleCoverageSnapshot.load(repositoryRoot: repositoryRoot, lock: lock)
    // The pinned commit must resolve in a full clone. Only a shallow clone, or a tree that is not a git
    // checkout at all, may skip the check, and then the tree pin is reported unverified, not passed.
    let commit = lock.fixtureWinMergeCommit.rawValue
    let treeStatus: String
    if gitOutput(["cat-file", "-e", "\(commit)^{commit}"]) != nil {
        let treeSpec = "\(commit):\(DiffOracleCoverageLock.windowsXDiffRelativePath)"
        guard let tree = gitOutput(["rev-parse", "--verify", "--quiet", treeSpec]) else {
            fail("fixture-winmerge-commit \(commit) has no \(DiffOracleCoverageLock.windowsXDiffRelativePath) tree")
        }
        snapshot.observedFixtureXDiffTree = tree
        treeStatus = "fixture-winmerge-commit and fixture-xdiff-tree verified against git"
    } else {
        switch gitOutput(["rev-parse", "--is-shallow-repository"]) {
        case "true":
            treeStatus = "fixture-xdiff-tree not verified (shallow checkout lacks fixture-winmerge-commit)"
        case nil:
            treeStatus = "fixture-xdiff-tree not verified (not a git checkout)"
        default:
            fail("fixture-winmerge-commit \(commit) cannot be resolved in this non-shallow checkout")
        }
    }
    var current = lock
    if refresh {
        let header = lockText.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix { $0.hasPrefix("#") }
            .joined(separator: "\n")
        current = lock.refreshed(with: snapshot)
        let text = current.serialized(header: header.isEmpty ? DiffOracleCoverageLock.defaultHeaderComment : header)
        try Data(text.utf8).write(to: lockURL, options: .atomic)
        print("Refreshed \(lockURL.path); review the diff before committing.")
    }
    let report = DiffOracleCoverageAudit.audit(lock: current, snapshot: snapshot, requireGoldens: requireGoldens)
    for finding in report.findings {
        FileHandle.standardError.write(Data("error: \(finding)\n".utf8))
    }
    if !report.passed {
        fail("\(report.findings.count) finding(s)")
    }
    let required = current.requiredSources.count
    print(
        "Diff oracle coverage gate passed: \(required) required fixture sources, "
            + "\(current.goldens.count) golden results, \(report.pendingSources.count) pending WinMerge oracle results; "
            + treeStatus
    )
} catch {
    fail(String(describing: error))
}
