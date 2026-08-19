import Foundation
import XCTest

final class XDiffSourceManifestTests: XCTestCase {
    func testUpstreamSourcesHaveExactCompiledWrapperCoverage() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = packageRoot.appendingPathComponent("Sources/CXDiff", isDirectory: true)
        let upstreamRoot = packageRoot
            .deletingLastPathComponent()
            .appendingPathComponent("Externals/xdiff", isDirectory: true)
        let expectedUpstreamSources = [
            "xdiffi.c",
            "xemit.c",
            "xhistogram.c",
            "xmerge.c",
            "xnone.c",
            "xpatience.c",
            "xprepare.c",
            "xutils.c",
        ]
        let expectedWrapperIncludes = [
            "vendor_xdiffi.c": ["xdiffi.c"],
            "vendor_xemit.c": ["xemit.c"],
            "vendor_xhistogram.c": ["xhistogram.c"],
            "vendor_xnone.c": ["xnone.c"],
            "vendor_xpatience.c": ["xpatience.c"],
            "vendor_xprepare.c": ["xprepare.c"],
            "vendor_xutils.c": ["xutils.c"],
        ]
        let intentionallyUnwrappedSources = ["xmerge.c"]

        XCTAssertEqual(try cSourceNames(in: upstreamRoot), expectedUpstreamSources)

        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        var actualWrapperIncludes: [String: [String]] = [:]
        for sourceFile in sourceFiles where sourceFile.pathExtension == "c" {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            let includes = upstreamCIncludes(in: source)
            if !includes.isEmpty {
                actualWrapperIncludes[sourceFile.lastPathComponent] = includes.sorted()
            }
        }

        XCTAssertEqual(
            rendered(expectedWrapperIncludes),
            rendered(actualWrapperIncludes),
            "CXDiff wrappers must retain exact direct includes of upstream xdiff translation units"
        )
        XCTAssertEqual(
            (expectedWrapperIncludes.values.flatMap { $0 } + intentionallyUnwrappedSources).sorted(),
            expectedUpstreamSources,
            "Every upstream xdiff C source must be explicitly compiled or intentionally unwrapped"
        )

        for wrapper in expectedWrapperIncludes.keys.sorted() {
            let source = try String(
                contentsOf: sourceRoot.appendingPathComponent(wrapper),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.containsPreprocessorCondition,
                "\(wrapper) must include its upstream translation unit unconditionally"
            )
        }

        let packageManifest = try String(
            contentsOf: packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let cxDiffTarget = try XCTUnwrap(targetDeclaration(named: "CXDiff", in: packageManifest))
        XCTAssertTrue(cxDiffTarget.contains(#"path: "Sources/CXDiff""#))
        XCTAssertNil(
            cxDiffTarget.range(of: #"\b(?:exclude|sources)\s*:"#, options: .regularExpression),
            "CXDiff must use SwiftPM source discovery so every recorded wrapper is compiled"
        )
    }

    private func cSourceNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter { $0.pathExtension == "c" }
        .map(\.lastPathComponent)
        .sorted()
    }

    private func upstreamCIncludes(in source: String) -> [String] {
        let expression = try! NSRegularExpression(
            pattern: #"(?m)^\s*#\s*include\s*"\.\./\.\./\.\./Externals/xdiff/([^"/]+\.c)"\s*$"#
        )
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return String(source[range])
        }
    }

    private func rendered(_ includes: [String: [String]]) -> [String] {
        includes.keys.sorted().flatMap { wrapper in
            includes[wrapper, default: []].sorted().map { "\(wrapper) -> \($0)" }
        }
    }

    private func targetDeclaration(named name: String, in manifest: String) -> String? {
        var searchStart = manifest.startIndex
        while let targetStart = manifest.range(
            of: ".target(",
            range: searchStart..<manifest.endIndex
        )?.lowerBound {
            guard let targetEnd = matchingClosingParenthesis(in: manifest, startingAt: targetStart) else {
                return nil
            }
            let declaration = String(manifest[targetStart...targetEnd])
            if declaration.range(
                of: #"\bname\s*:\s*"\#(name)""#,
                options: .regularExpression
            ) != nil {
                return declaration
            }
            searchStart = manifest.index(after: targetEnd)
        }
        return nil
    }

    private func matchingClosingParenthesis(in text: String, startingAt start: String.Index) -> String.Index? {
        guard let opening = text[start...].firstIndex(of: "(") else {
            return nil
        }
        var depth = 0
        var inString = false
        var escaped = false

        for index in text.indices[opening...] {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return nil
    }
}

private extension String {
    var containsPreprocessorCondition: Bool {
        range(
            of: #"(?m)^\s*#\s*(?:if|ifdef|ifndef|elif|else)\b"#,
            options: .regularExpression
        ) != nil
    }
}
