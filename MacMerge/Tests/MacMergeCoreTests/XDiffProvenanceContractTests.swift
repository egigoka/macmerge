import Foundation
import XCTest

final class XDiffProvenanceContractTests: XCTestCase {
    private let topLevelOrigin = VersionOrigin(
        revision: "611e42a",
        date: "Nov 2, 2018",
        url: "https://github.com/git/git/tree/master/xdiff"
    )
    private let winIMergeOrigin = VersionOrigin(
        revision: "611e42a",
        date: "Nov 2, 2018",
        url: "https://github.com/git/git/tree/master/xdiff"
    )
    private let originalGitCommit = "611e42a5980a3a9f8bb3b1b49c1abde63c7a191e"
    private let originalGitTree = "77abde3699bc6874e10f1c17f4b97c219492542f"
    private let winMergeSnapshot = "7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301"
    private let pinnedSnapshotTree = "bf7ade8ccf4199ab85649c5aac4474b14e44f55f"
    private let patchIntroductionCommit = "40d8b10d0928bc415e6c3febd2dab2f6daff1a5c"
    private let patchedTree = "a2f958abe94a14a95200c911be748cd3f9b7e9f0"
    private let patchedContentHash = "9625ad79f0afe1b596abefd6f7b5180f3895baafd109e007ce7356a9612bbc6e"

    func testPinnedProvenanceAgreesAcrossDependencyLedgerDocumentsAndGitObjects() throws {
        let versions = try contents(of: "Externals/versions.txt")
        let sync = try contents(of: "MacMerge/XDIFF_SYNC.md")
        let decision = try contents(of: "MacMerge/XDIFF_ARCHITECTURE_DECISION.md")
        let declarations = try versionDeclarations(in: versions)

        XCTAssertEqual(
            try uniqueDeclaration(path: ["LibXDiff"], in: declarations).origin,
            topLevelOrigin
        )
        XCTAssertEqual(
            try uniqueDeclaration(path: ["WinIMerge", "LibXDiff"], in: declarations).origin,
            winIMergeOrigin
        )

        XCTAssertEqual(try pinnedValue("Upstream repository", in: sync), "https://github.com/WinMerge/winmerge.git")
        XCTAssertEqual(try pinnedValue("Upstream path", in: sync), "Externals/xdiff")
        XCTAssertEqual(try pinnedValue("Pinned xdiff snapshot", in: sync), winMergeSnapshot)
        XCTAssertEqual(try pinnedValue("Pinned snapshot tree", in: sync), pinnedSnapshotTree)
        XCTAssertEqual(try pinnedValue("Original Git xdiff commit", in: sync), originalGitCommit)
        XCTAssertEqual(try pinnedValue("MacMerge patch base", in: sync), winMergeSnapshot)
        XCTAssertEqual(try pinnedValue("Current patched tree", in: sync), patchedTree)
        XCTAssertEqual(try pinnedValue("Historical patch introduction", in: sync), patchIntroductionCommit)

        let originalIdentity = try uniqueCaptures(
            #"Git resolves that abbreviation to\s+`([0-9a-f]{40})`; its `xdiff` tree is\s+`([0-9a-f]{40})`\."#,
            in: decision,
            field: "original Git xdiff identity",
            captureCount: 2
        )
        XCTAssertEqual(originalIdentity, [originalGitCommit, originalGitTree])

        let snapshotIdentity = try uniqueCaptures(
            #"MacMerge's WinMerge path pin `([0-9a-f]{40})` has\s+`Externals/xdiff` Git tree ID `([0-9a-f]{40})`\."#,
            in: decision,
            field: "WinMerge snapshot identity",
            captureCount: 2
        )
        XCTAssertEqual(snapshotIdentity, [winMergeSnapshot, pinnedSnapshotTree])

        let patchedIdentity = try uniqueCaptures(
            #"Accepted Mac\s+patch-introduction commit `([0-9a-f]{40})` has patched tree\s+`([0-9a-f]{40})` and content-manifest SHA-256\s+`([0-9a-f]{64})`\."#,
            in: decision,
            field: "Mac patched xdiff identity",
            captureCount: 3
        )
        XCTAssertEqual(patchedIdentity, [patchIntroductionCommit, patchedTree, patchedContentHash])

        let xutilsBlobs = try uniqueCaptures(
            #"The pinned `xutils\.c` blob is `([0-9a-f]{40})`;\s+the patched blob is `([0-9a-f]{40})`\."#,
            in: sync,
            field: "xutils blob identities",
            captureCount: 2
        )

        XCTAssertEqual(try gitOutput(["rev-parse", "HEAD:Externals/xdiff"]), patchedTree)
        XCTAssertEqual(try gitOutput(["rev-parse", "HEAD:Externals/xdiff/xutils.c"]), xutilsBlobs[1])
        XCTAssertEqual(try contentManifestHash(at: "HEAD"), patchedContentHash)

        if try gitObjectExists("\(originalGitCommit)^{commit}") {
            XCTAssertEqual(try gitOutput(["rev-parse", "\(originalGitCommit):xdiff"]), originalGitTree)
        }
        if try gitObjectExists("\(winMergeSnapshot)^{commit}") {
            XCTAssertEqual(
                try gitOutput(["rev-parse", "\(winMergeSnapshot):Externals/xdiff"]),
                pinnedSnapshotTree
            )
            XCTAssertEqual(
                try gitOutput(["rev-parse", "\(winMergeSnapshot):Externals/xdiff/xutils.c"]),
                xutilsBlobs[0]
            )
        }
        if try gitObjectExists("\(patchIntroductionCommit)^{commit}") {
            XCTAssertEqual(
                try gitOutput(["rev-parse", "\(patchIntroductionCommit):Externals/xdiff"]),
                patchedTree
            )
            XCTAssertEqual(
                try gitOutput(["rev-parse", "\(patchIntroductionCommit)^:Externals/xdiff"]),
                pinnedSnapshotTree
            )
            XCTAssertEqual(try contentManifestHash(at: patchIntroductionCommit), patchedContentHash)
        }
    }

    func testWindowsManifestSemanticallyMatchesRecursiveVendorCInventory() throws {
        let manifestSources = try manifestCSourcePaths(
            at: repositoryRoot.appendingPathComponent("Externals/xdiff/xdiff.vcxitems")
        )
        let vendorSources = try recursiveCSourcePaths(
            in: repositoryRoot.appendingPathComponent("Externals/xdiff", isDirectory: true)
        )

        XCTAssertFalse(manifestSources.isEmpty)
        XCTAssertEqual(counted(manifestSources), counted(vendorSources))
    }

    func testMacShimsCanonicallyWrapManifestSourcesExceptXMerge() throws {
        let sync = try contents(of: "MacMerge/XDIFF_SYNC.md")
        let manifestSources = try manifestCSourcePaths(
            at: repositoryRoot.appendingPathComponent("Externals/xdiff/xdiff.vcxitems")
        )
        let manifestCounts = counted(manifestSources)
        let documentedMappings = try capturePairs(
            #"(?m)^\| `MacMerge/Sources/CXDiff/([^`]+\.c)` \| `Externals/xdiff/([^`]+\.c)` \|$"#,
            in: sync
        ).map { "\($0.0) -> \($0.1)" }
        let sourceRoot = repositoryRoot.appendingPathComponent("MacMerge/Sources/CXDiff", isDirectory: true)
        let sourcePaths = try recursiveCSourcePaths(in: sourceRoot)
        var actualMappings: [String] = []
        var wrappedSources: [String] = []

        for sourcePath in sourcePaths {
            let source = try String(
                contentsOf: sourceRoot.appendingPathComponent(sourcePath),
                encoding: .utf8
            )
            let isXDiffShim = URL(fileURLWithPath: sourcePath).lastPathComponent.hasPrefix("vendor_x")
            if isXDiffShim {
                let vendorPath = try canonicalShimVendorPath(source, sourcePath: sourcePath)
                actualMappings.append("\(sourcePath) -> \(vendorPath)")
                wrappedSources.append(vendorPath)
            } else {
                XCTAssertTrue(
                    try captures(
                        #"(?m)^\s*#\s*include\s+\"(?:\.\./)+Externals/xdiff/([^\"]+\.c)\"\s*$"#,
                        in: source
                    ).isEmpty,
                    "Only canonical vendor_x shims may include xdiff implementation files: \(sourcePath)"
                )
            }
        }

        XCTAssertEqual(counted(actualMappings), counted(documentedMappings))
        XCTAssertEqual(manifestCounts["xmerge.c"], 1)
        XCTAssertNil(counted(wrappedSources)["xmerge.c"])

        var expectedWrappedCounts = manifestCounts
        expectedWrappedCounts.removeValue(forKey: "xmerge.c")
        XCTAssertEqual(counted(wrappedSources), expectedWrappedCounts)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(of repositoryRelativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(repositoryRelativePath),
            encoding: .utf8
        )
    }

    private func pinnedValue(_ field: String, in document: String) throws -> String {
        let escapedField = NSRegularExpression.escapedPattern(for: field)
        return try uniqueCaptures(
            #"(?m)^\| \#(escapedField) \| `([^`]+)`"#,
            in: document,
            field: field,
            captureCount: 1
        )[0]
    }

    private func versionDeclarations(in text: String) throws -> [VersionDeclaration] {
        let bullet = try NSRegularExpression(pattern: #"^(\s*)-\s+([^:]+):\s*(.*)$"#)
        let origin = try NSRegularExpression(pattern: #"^([0-9a-f]+) on ([^()]+) \((https?://[^)]+)\)$"#)
        var hierarchy: [(indent: Int, label: String)] = []
        var declarations: [VersionDeclaration] = []

        for line in text.components(separatedBy: .newlines) {
            let lineRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard
                let match = bullet.firstMatch(in: line, range: lineRange),
                let indentRange = Range(match.range(at: 1), in: line),
                let labelRange = Range(match.range(at: 2), in: line),
                let valueRange = Range(match.range(at: 3), in: line)
            else {
                continue
            }
            let indent = line[indentRange].utf8.count
            let label = String(line[labelRange])
            let value = String(line[valueRange])

            while hierarchy.last?.indent ?? -1 >= indent {
                hierarchy.removeLast()
            }
            let path = hierarchy.map(\.label) + [label]
            if label == "LibXDiff" {
                let fields = try captures(from: origin, in: value, expectedCount: 3)
                declarations.append(
                    VersionDeclaration(
                        path: path,
                        origin: VersionOrigin(revision: fields[0], date: fields[1], url: fields[2])
                    )
                )
            }
            hierarchy.append((indent, label))
        }
        return declarations
    }

    private func uniqueDeclaration(
        path: [String],
        in declarations: [VersionDeclaration]
    ) throws -> VersionDeclaration {
        let matches = declarations.filter { $0.path == path }
        guard matches.count == 1 else {
            XCTFail("Expected one versions.txt declaration at \(path.joined(separator: " > ")); found \(matches.count)")
            throw ContractError.invalidMatchCount(path.joined(separator: " > "), matches.count)
        }
        return matches[0]
    }

    private func manifestCSourcePaths(at file: URL) throws -> [String] {
        let parser = XMLParser(contentsOf: file)
        let collector = MSBuildCompileCollector()
        parser?.delegate = collector
        parser?.shouldProcessNamespaces = true
        parser?.shouldResolveExternalEntities = false
        guard parser?.parse() == true, collector.validationError == nil, collector.sawProjectRoot else {
            throw ContractError.invalidXML(file, parser?.parserError ?? collector.validationError)
        }

        let prefix = "$(MSBuildThisFileDirectory)"
        return try collector.includes.map { include in
            guard include.hasPrefix(prefix) else {
                throw ContractError.invalidManifestInclude(include)
            }
            let relativePath = String(include.dropFirst(prefix.count))
                .replacingOccurrences(of: "\\", with: "/")
            guard URL(fileURLWithPath: relativePath).pathExtension == "c" else {
                throw ContractError.invalidManifestInclude(include)
            }
            return relativePath
        }
    }

    private func canonicalShimVendorPath(_ source: String, sourcePath: String) throws -> String {
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }
        guard lines.count == 5 else {
            XCTFail("\(sourcePath) must contain exactly the canonical five-line shim")
            throw ContractError.invalidShim(sourcePath)
        }

        XCTAssertEqual(lines[0], "#pragma clang diagnostic push", sourcePath)
        XCTAssertEqual(lines[1], #"#pragma clang diagnostic ignored "-Wshorten-64-to-32""#, sourcePath)
        XCTAssertEqual(lines[2], #"#include "macmerge_xdiff_allocator.h""#, sourcePath)
        XCTAssertEqual(lines[4], "#pragma clang diagnostic pop", sourcePath)
        return try uniqueCaptures(
            #"^#include \"\.\./\.\./\.\./Externals/xdiff/([^\"]+\.c)\"$"#,
            in: lines[3],
            field: "\(sourcePath) vendor include",
            captureCount: 1
        )[0]
    }

    private func counted(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }

    private func captures(_ pattern: String, in text: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges == 2, let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private func uniqueCaptures(
        _ pattern: String,
        in text: String,
        field: String,
        captureCount: Int
    ) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = expression.matches(in: text, range: range)
        guard matches.count == 1 else {
            XCTFail("Expected one \(field); found \(matches.count)")
            throw ContractError.invalidMatchCount(field, matches.count)
        }
        return try captures(from: expression, match: matches[0], in: text, expectedCount: captureCount)
    }

    private func captures(
        from expression: NSRegularExpression,
        in text: String,
        expectedCount: Int
    ) throws -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range) else {
            throw ContractError.invalidMatch(text)
        }
        return try captures(from: expression, match: match, in: text, expectedCount: expectedCount)
    }

    private func captures(
        from expression: NSRegularExpression,
        match: NSTextCheckingResult,
        in text: String,
        expectedCount: Int
    ) throws -> [String] {
        guard match.numberOfRanges == expectedCount + 1 else {
            throw ContractError.invalidCaptureCount(expression.pattern)
        }
        return try (1...expectedCount).map { captureIndex in
            guard let range = Range(match.range(at: captureIndex), in: text) else {
                throw ContractError.invalidMatch(expression.pattern)
            }
            return String(text[range])
        }
    }

    private func capturePairs(_ pattern: String, in text: String) throws -> [(String, String)] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard
                match.numberOfRanges == 3,
                let firstRange = Range(match.range(at: 1), in: text),
                let secondRange = Range(match.range(at: 2), in: text)
            else {
                return nil
            }
            return (String(text[firstRange]), String(text[secondRange]))
        }
    }

    private func recursiveCSourcePaths(in directory: URL) throws -> [String] {
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else {
            throw ContractError.cannotEnumerate(directory)
        }
        let rootPath = directory.standardizedFileURL.path + "/"
        var paths: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "c" {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            let path = fileURL.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else {
                continue
            }
            paths.append(String(path.dropFirst(rootPath.count)))
        }
        if let traversalError {
            throw ContractError.enumerationFailed(directory, traversalError)
        }
        return paths.sorted()
    }

    private func gitOutput(_ arguments: [String]) throws -> String {
        String(decoding: try commandData("/usr/bin/git", arguments: arguments), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func gitObjectExists(_ specification: String) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["cat-file", "-e", specification]
        process.currentDirectoryURL = repositoryRoot
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func contentManifestHash(at commit: String) throws -> String {
        let treeData = try commandData(
            "/usr/bin/git",
            arguments: ["ls-tree", "-r", "-z", commit, "--", "Externals/xdiff"]
        )
        let entries = try treeData.split(separator: 0).map { record -> GitTreeEntry in
            guard
                let separator = record.firstIndex(of: 0x09),
                let metadata = String(data: record[..<separator], encoding: .ascii)
            else {
                throw ContractError.invalidGitTree
            }
            let fields = metadata.split(separator: " ")
            guard fields.count == 3, fields[1] == "blob" else {
                throw ContractError.invalidGitTree
            }
            return GitTreeEntry(objectID: String(fields[2]), path: Data(record[record.index(after: separator)...]))
        }.sorted { left, right in
            left.path.lexicographicallyPrecedes(right.path)
        }
        var manifest = Data()
        for entry in entries {
            let blob = try commandData("/usr/bin/git", arguments: ["cat-file", "blob", entry.objectID])
            manifest.append(Data("\(try sha256Hex(of: blob))  ".utf8))
            manifest.append(entry.path)
            manifest.append(0x0A)
        }
        return try sha256Hex(of: manifest)
    }

    private func sha256Hex(of data: Data) throws -> String {
        let output = try commandData("/usr/bin/shasum", arguments: ["-a", "256"], standardInput: data)
        guard let hash = String(decoding: output, as: UTF8.self).split(separator: " ").first else {
            throw ContractError.invalidHashOutput
        }
        return String(hash)
    }

    private func commandData(
        _ executable: String,
        arguments: [String],
        standardInput: Data? = nil
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot
        process.standardOutput = output
        process.standardError = error

        let input = standardInput.map { data in
            let pipe = Pipe()
            process.standardInput = pipe
            return (pipe, data)
        }
        try process.run()
        if let input {
            try input.0.fileHandleForWriting.write(contentsOf: input.1)
            try input.0.fileHandleForWriting.close()
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ContractError.commandFailed(
                [executable] + arguments,
                String(decoding: errorData, as: UTF8.self)
            )
        }
        return outputData
    }
}

private struct VersionOrigin: Equatable {
    let revision: String
    let date: String
    let url: String
}

private struct VersionDeclaration {
    let path: [String]
    let origin: VersionOrigin
}

private struct GitTreeEntry {
    let objectID: String
    let path: Data
}

private final class MSBuildCompileCollector: NSObject, XMLParserDelegate {
    private let namespace = "http://schemas.microsoft.com/developer/msbuild/2003"
    var includes: [String] = []
    var sawProjectRoot = false
    var validationError: Error?
    private var elements: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard validationError == nil else {
            return
        }
        guard namespaceURI == namespace else {
            validationError = ContractError.invalidMSBuildElement(elementName)
            parser.abortParsing()
            return
        }
        if elements.isEmpty {
            guard elementName == "Project" else {
                validationError = ContractError.invalidMSBuildElement(elementName)
                parser.abortParsing()
                return
            }
            sawProjectRoot = true
        }
        if elementName == "ClCompile", attributeDict["Include"] != nil {
            guard elements == ["Project", "ItemGroup"], let include = attributeDict["Include"] else {
                validationError = ContractError.invalidMSBuildElement(elementName)
                parser.abortParsing()
                return
            }
            includes.append(include)
        }
        elements.append(elementName)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard validationError == nil, elements.popLast() == elementName else {
            return
        }
    }
}

private enum ContractError: Error {
    case cannotEnumerate(URL)
    case commandFailed([String], String)
    case enumerationFailed(URL, Error)
    case invalidCaptureCount(String)
    case invalidGitTree
    case invalidHashOutput
    case invalidManifestInclude(String)
    case invalidMatch(String)
    case invalidMatchCount(String, Int)
    case invalidMSBuildElement(String)
    case invalidShim(String)
    case invalidXML(URL, Error?)
}
