import Foundation
import XCTest

final class WindowsShellScopeContractTests: XCTestCase {
    private struct MatrixRow {
        let topic: String
        let mechanism: String
        let outcome: String
    }

    private let requiredTopics = [
        "Command discovery through `PATH` and **App Paths**",
        "TortoiseCVS, TortoiseGit, and TortoiseSVN integration",
        "WinMerge project association",
        "Finder **Open With** for compared documents",
        "Explorer **WinMerge**, **Compare**, and **Compare As** commands",
        "Shell registration and settings",
        "Shell menus hosted inside comparison panes",
        "Recent comparisons, documents, paths, folders, and projects",
        "Jump List tasks and Dock surfaces",
        "Drag and drop",
        "Windows COM/OLE activation and plugin host",
        "Shell file operations, Recycle Bin, and folder prototype"
    ]

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var documentURL: URL {
        repositoryRoot.appendingPathComponent("MacMerge/WINDOWS_SHELL_SCOPE.md")
    }

    func testRequiredSectionsTopicsAndSourceReferencesExist() throws {
        let document = try contents(of: documentURL)
        for section in [
            "## Decision matrix",
            "## Intentionally unsupported scope",
            "## Rationale and security boundaries",
            "## Revisit criteria",
            "## Evidence index"
        ] {
            XCTAssertTrue(document.contains(section), "Missing required section: \(section)")
        }

        let rows = try decisionMatrixRows(in: document)
        for requiredTopic in requiredTopics {
            XCTAssertTrue(
                rows.contains { $0.topic.hasPrefix(requiredTopic) },
                "Decision matrix is missing required topic: \(requiredTopic)"
            )
        }

        for row in rows {
            let sourceReferences = try markdownLinkDestinations(in: row.topic)
                .filter(isLocalLink)
            XCTAssertFalse(
                sourceReferences.isEmpty,
                "Decision matrix topic lacks a local source reference: \(row.topic)"
            )
        }
    }

    func testMatrixUsesParityLedgerStatusVocabulary() throws {
        let document = try contents(of: documentURL)
        let ledger = try contents(of: repositoryRoot.appendingPathComponent("todo.md"))
        let vocabulary = Set(try captures(#"(?m)^- `([A-Z_/]+)`:"#, in: ledger))
        let expectedVocabulary = Set(["MATCH", "MAC_ADAPTATION", "PARTIAL", "MISSING", "N/A"])
        XCTAssertEqual(vocabulary, expectedVocabulary, "Update this contract when ledger vocabulary changes")

        let statusLikeCodeSpans = Set(try captures(#"`([A-Z][A-Z_/]*)`"#, in: document))
        XCTAssertEqual(
            statusLikeCodeSpans.subtracting(vocabulary).subtracting(["PATH"]),
            [],
            "Document contains code-formatted status-like values outside ledger vocabulary"
        )

        for row in try decisionMatrixRows(in: document) {
            let mechanismStatuses = statusTokens(in: row.mechanism, vocabulary: vocabulary)
            XCTAssertEqual(
                mechanismStatuses.count,
                1,
                "Mechanism must have exactly one classification: \(row.topic)"
            )
            XCTAssertTrue(
                mechanismStatuses.isSubset(of: ["N/A", "MAC_ADAPTATION"]),
                "Mechanism uses a portable-outcome status: \(row.topic)"
            )

            let outcomeStatuses = statusTokens(in: row.outcome, vocabulary: vocabulary)
            XCTAssertFalse(outcomeStatuses.isEmpty, "Portable outcome lacks a status: \(row.topic)")
            XCTAssertFalse(outcomeStatuses.contains("N/A"), "Portable outcome cannot be N/A: \(row.topic)")
        }
    }

    func testAllLocalLinksAndAnchorsResolve() throws {
        let document = try contents(of: documentURL)
        for destination in try markdownLinkDestinations(in: document) where isLocalLink(destination) {
            try assertLocalLinkResolves(destination)
        }
    }

    func testUnsupportedPolicyDoesNotRedefineNA() throws {
        let document = try contents(of: documentURL)
        XCTAssertTrue(
            document.contains(
                "`N/A` means a Windows-only mechanism has no macOS meaning; "
                    + "it does not mean deferred, missing, or rejected."
            ),
            "N/A must retain the parity ledger's platform-mechanism meaning"
        )
        XCTAssertTrue(
            document.contains(
                "\"Intentionally unsupported\" records a product or security decision rather than "
                    + "redefining `N/A`."
            ),
            "Unsupported policy must remain distinct from N/A"
        )

        let conflationPatterns = [
            #"(?i)(?:intentionally\s+)?unsupported\s+(?:means|is equivalent to|maps to|is classified as|is marked as)\s+`?N/A`?"#,
            #"(?i)`?N/A`?\s+(?:means|is equivalent to)\s+(?:intentionally\s+)?unsupported"#,
            #"(?i)(?:unsupported|rejected|deferred|missing)\s*\(\s*`?N/A`?\s*\)"#,
            #"(?i)(?:mark|classify|treat|record)[^.\n]{0,40}(?:unsupported|rejected|deferred|missing)[^.\n]{0,20}\s+as\s+`?N/A`?"#
        ]
        for pattern in conflationPatterns {
            XCTAssertTrue(
                try captures(pattern, in: document, captureGroup: 0).isEmpty,
                "Unsupported, deferred, rejected, or missing work must not be defined as N/A"
            )
        }
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func decisionMatrixRows(in document: String) throws -> [MatrixRow] {
        let start = try XCTUnwrap(document.range(of: "## Decision matrix\n")?.upperBound)
        let remainder = document[start...]
        let end = remainder.range(of: "\n## ")?.lowerBound ?? document.endIndex
        var rows: [MatrixRow] = []

        for line in document[start..<end].split(separator: "\n") where line.hasPrefix("| ") {
            if line.hasPrefix("| ---") || line.hasPrefix("| Surface and evidence") {
                continue
            }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertEqual(cells.count, 6, "Malformed decision matrix row: \(line)")
            guard cells.count == 6 else {
                continue
            }
            rows.append(MatrixRow(topic: cells[1], mechanism: cells[3], outcome: cells[4]))
        }

        XCTAssertFalse(rows.isEmpty, "Decision matrix contains no rows")
        return rows
    }

    private func statusTokens(in text: String, vocabulary: Set<String>) -> Set<String> {
        Set(vocabulary.filter { text.contains("`\($0)`") })
    }

    private func markdownLinkDestinations(in text: String) throws -> [String] {
        try captures(#"(?<!!)\[[^]]+\]\(([^ )]+)(?: \"[^\"]*\")?\)"#, in: text)
    }

    private func isLocalLink(_ destination: String) -> Bool {
        !destination.contains("://") && !destination.hasPrefix("mailto:")
    }

    private func assertLocalLinkResolves(
        _ destination: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let parts = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let encodedPath = String(parts[0])
        let relativePath = encodedPath.removingPercentEncoding ?? encodedPath
        XCTAssertFalse(relativePath.hasPrefix("/"), "Local link must be repository-relative: \(destination)")

        let target =
            relativePath.isEmpty
            ? documentURL
            : documentURL.deletingLastPathComponent().appendingPathComponent(relativePath)
        let standardizedTarget = target.standardizedFileURL
        let repositoryPath = repositoryRoot.standardizedFileURL.path + "/"
        XCTAssertTrue(
            standardizedTarget.path.hasPrefix(repositoryPath),
            "Local link escapes repository: \(destination)",
            file: file,
            line: line
        )

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: standardizedTarget.path, isDirectory: &isDirectory),
            "Missing local link target: \(destination)",
            file: file,
            line: line
        )

        guard parts.count == 2, !parts[1].isEmpty, !isDirectory.boolValue else {
            return
        }
        let encodedAnchor = String(parts[1])
        let anchor = encodedAnchor.removingPercentEncoding ?? encodedAnchor
        let targetDocument = try contents(of: standardizedTarget)
        XCTAssertTrue(
            headingAnchors(in: targetDocument).contains(anchor),
            "Missing local link anchor: \(destination)",
            file: file,
            line: line
        )
    }

    private func headingAnchors(in document: String) -> Set<String> {
        let headings = (try? captures(#"(?m)^#{1,6}[ \t]+(.+?)[ \t]*#*[ \t]*$"#, in: document)) ?? []
        var occurrences: [String: Int] = [:]
        var anchors: Set<String> = []
        for heading in headings {
            let base = githubAnchor(for: heading)
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            anchors.insert(occurrence == 0 ? base : "\(base)-\(occurrence)")
        }
        return anchors
    }

    private func githubAnchor(for heading: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return heading.lowercased().unicodeScalars.compactMap { scalar in
            if allowed.contains(scalar) {
                return String(scalar)
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return "-"
            }
            return nil
        }.joined()
    }

    private func captures(
        _ pattern: String,
        in text: String,
        captureGroup: Int = 1
    ) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard
                match.numberOfRanges > captureGroup,
                let range = Range(match.range(at: captureGroup), in: text)
            else {
                return nil
            }
            return String(text[range])
        }
    }
}
