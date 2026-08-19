import Foundation
import XCTest

final class WebTableParityDocumentationContractTests: XCTestCase {
    func testDecisionsPreserveGoAndNoGoBoundaries() throws {
        let document = try contents(of: "MacMerge/WEB_TABLE_PARITY_EVALUATION.md")
        let executiveDecision = try section(
            "## Executive decision",
            before: "## Parity definition",
            in: document
        )
        assertContains(
            [
                "| Two-pane table comparison for CSV, TSV, and custom single-character DSV | **GO, phased** |",
                "| Full WinMerge table parity | **NO-GO as one milestone item** |",
                "| Port or reuse `WinWebDiffLib.dll` | **NO-GO** |",
                "| Full dynamic webpage comparison parity | **NO-GO now** |",
                "| Native webpage research prototype | **CONDITIONAL GO after prerequisites** |",
                "Do not ship remote URL loading until a product decision accepts the network/privacy change"
            ],
            in: executiveDecision
        )

        let conclusions = try section(
            "## Explicit conclusions",
            before: "## Evidence index",
            in: document
        )
        assertContains(
            [
                "**GO: build native two-pane table comparison using an original-byte-provenance record model",
                "**NO-GO: do not call plain delimiter coloring, physical-line CSV comparison",
                "**NO-GO: do not port or bundle WinWebDiff/WebView2/Chromium.**",
                "**NO-GO now: do not implement or advertise full remote webpage parity",
                "**CONDITIONAL GO later: run a bounded offline-local-fixture `WKWebView` spike",
                "does not authorize remote shipping",
                "**NO-GO for an unqualified parity claim:**"
            ],
            in: conclusions
        )
        XCTAssertEqual(try captures(#"(?m)^(\d+)\. \*\*"#, in: conclusions).count, 6)
    }

    func testTableGateRequiresByteProvenanceAndLogicalRecordMerges() throws {
        let document = try contents(of: "MacMerge/WEB_TABLE_PARITY_EVALUATION.md")
        let implementation = try section(
            "#### Option T1: Lossless Swift record parser plus existing xdiff and AppKit",
            before: "#### Option T2: Apple's TabularData `DataFrame`",
            in: document
        )
        assertContains(
            [
                "indexes both original-byte and decoded-text ranges",
                "Each editable record must retain an original byte span plus codec state",
                "table editing is read-only for that encoding",
                "unedited save still reuses the original persisted bytes",
                "Feed xdiff logical records, never original physical lines",
                "add a record-span adapter at the xdiff record-classification boundary"
            ],
            in: implementation
        )

        let tableRisks = try section(
            "### Table security and correctness",
            before: "### Webpage security and privacy",
            in: document
        )
        assertContains(
            [
                "Preserve original byte and decoded ranges",
                "serialize only changed records through proven codec-local splices",
                "no physical-line fallback when quoted-newline mode is enabled",
                "table-specific record/cell edit and merge primitives operate raw record spans",
                "WinMerge-compatible replacement copies source serialized record content and source terminator"
            ],
            in: tableRisks
        )

        let phaseTwo = try section(
            "### Phase 2: Table editing and merge",
            before: "### Phase 3: Table hardening and release",
            in: document
        )
        XCTAssertTrue(phaseTwo.contains("never invoke physical-line `LineMerge` for table content"))

        let tableGate = try section(
            "### Two-pane table release gate",
            before: "### Remote experimental webpage gate",
            in: document
        )
        assertContains(
            [
                "concatenating original byte record spans and terminators reproduces input bytes exactly",
                "Opening and saving an unedited supported file reproduces original bytes exactly",
                "Quoted newlines produce one diff row",
                "No fallback silently treats malformed quoted data as ordinary physical lines"
            ],
            in: tableGate
        )
    }

    func testTableGateCoversSerializationHeadersFormulaSafetyAndCaps() throws {
        let document = try contents(of: "MacMerge/WEB_TABLE_PARITY_EVALUATION.md")
        let tableGate = try section(
            "### Two-pane table release gate",
            before: "### Remote experimental webpage gate",
            in: document
        )
        assertContains(
            [
                "optional empty quote to disable enclosure handling",
                "distinct, non-NUL, non-CR/LF, and representable in target encoding",
                "Editing one cell replaces its raw serialized field slice exactly as displayed",
                "reparsing must preserve field count/boundaries",
                "Edits that create a delimiter boundary, unmatched quote state, or disallowed quoted newline fail closed",
                "Header mode is non-consuming: record one still participates in comparison, editing, merge, navigation, and save",
                "Every spreadsheet-oriented export or clipboard test, including one-cell copy, requires a warning",
                "100,000 records by 20 fields",
                "1,000,000 records by 3 fields",
                "near-16,384-column and near-10,000,000-cell two-pane cases",
                "5,000 ms load, 5,000 ms comparison, 1,500 ms first render, 1,500 ms bottom scroll, and 900 MiB resident budget"
            ],
            in: tableGate
        )

        let tableRisks = try section(
            "### Table security and correctness",
            before: "### Webpage security and privacy",
            in: document
        )
        assertContains(
            [
                "initial hard caps of 1,048,576 records, 16,384 fields per record, and 10,000,000 total cells",
                "warn before every spreadsheet-targeted clipboard/export path containing formula-leading values, including one cell",
                "reparse the full record and require unchanged field count/boundaries plus exact edited raw slice"
            ],
            in: tableRisks
        )
    }

    func testWebGateRequiresNoEgressIsolationAndCompleteFrameScope() throws {
        let document = try contents(of: "MacMerge/WEB_TABLE_PARITY_EVALUATION.md")
        let webRisks = try section(
            "### Webpage security and privacy",
            before: "### Dependency and maintenance",
            in: document
        )
        assertContains(
            [
                "Threat model must explicitly accept broad egress or remote mode remains NO-GO",
                "Separate nonpersistent store per pane by default",
                "Offline-local mode only, with release signature lacking `network.client`",
                "Remote mode never accepts local-file input",
                "never log DOM, URL query strings, cookies, headers, or form values",
                "Accept only system-valid server trust; no trust exceptions or client certificates",
                "mark result incomplete and prohibit an equality claim"
            ],
            in: webRisks
        )

        let webGate = try section(
            "### Remote experimental webpage gate",
            before: "## Explicit conclusions",
            in: document
        )
        assertContains(
            [
                "Remote mode uses exactly two panes, separate nonpersistent stores, `https` only",
                "Offline-local mode uses selected files/minimum read scope under a no-egress release signature",
                "top-level, frame, script, form, redirect, and subresource access to public, private, and loopback destinations",
                "Every request fails under the actual no-`network.client` release signature",
                "No compared DOM, text, screenshot, URL userinfo/query/fragment, cookie, header, form value, or resource body",
                "Frame fixtures cover main-frame, same-origin, cross-origin, sandboxed, and late-added frames",
                "any inaccessible, sandboxed, cross-origin, or late-mutating frame marks result incomplete and blocks equality",
                "Captures above 50 megapixels, extraction above 64 MiB, or observed-resource lists above 100,000 entries fail"
            ],
            in: webGate
        )
    }

    func testReleaseGatesRequireSupportedRuntimeMatrixAndRetainedReports() throws {
        let document = try contents(of: "MacMerge/WEB_TABLE_PARITY_EVALUATION.md")
        assertContains(
            [
                "Current CI uses only `macos-15`; release requires retained packaged test/benchmark reports from explicit macOS 14 and current supported-version jobs",
                "CI runs fixture parity and packaged UI/performance gates on macOS 14 and current supported macOS jobs",
                "macOS 14 and current supported-version jobs record OS build, WebKit/runtime version, viewport, user agent, sanitized origin"
            ],
            in: document
        )

        let packageManifest = try contents(of: "MacMerge/Package.swift")
        XCTAssertTrue(packageManifest.contains(".macOS(.v14)"))

        let workflow = try contents(of: ".github/workflows/macmerge.yml")
        let runners = Set(try captures(#"(?m)^\s*runs-on:\s*([^\s]+)\s*$"#, in: workflow))
        XCTAssertEqual(runners, ["macos-15"], "Update evaluation when current CI runtime coverage changes")
        assertContains(
            [
                "run: swift test -Xswiftc -warnings-as-errors",
                "run: Scripts/run-performance-budgets.sh",
                "performance-dense-report.json",
                "uses: actions/upload-artifact@v4"
            ],
            in: workflow
        )
    }

    func testEvidenceLabelsAreDefinedAndRepositoryCitationsResolve() throws {
        let document = try contents(of: "MacMerge/WEB_TABLE_PARITY_EVALUATION.md")
        let evidenceMarker = try XCTUnwrap(document.range(of: "## Evidence index"))
        let body = String(document[..<evidenceMarker.lowerBound])
        let evidence = String(document[evidenceMarker.lowerBound...])
        let referencedLabels = Set(try captures(#"\[([A-Z][A-Z0-9-]+)\]"#, in: body))
        let definitionGroups = try captureGroups(
            #"(?m)^- \*\*\[([A-Z][A-Z0-9-]+)\]\*\* (.+)$"#,
            in: evidence
        )
        var definitions: [String: String] = [:]
        for groups in definitionGroups {
            XCTAssertNil(definitions.updateValue(groups[1], forKey: groups[0]), "Duplicate evidence label \(groups[0])")
        }

        XCTAssertEqual(
            referencedLabels,
            Set(definitions.keys),
            "Every claim label must have one used evidence-index definition"
        )

        for label in referencedLabels.sorted() {
            let source = try XCTUnwrap(definitions[label])
            XCTAssertTrue(
                source.contains("https://") || source.contains("`"),
                "Evidence \(label) has no source citation"
            )
            if label.hasPrefix("W-") || label.hasPrefix("M-") {
                XCTAssertFalse(
                    try repositoryCitations(in: source).isEmpty,
                    "Repository evidence \(label) must cite a path and line range"
                )
            }
        }

        let citations = try repositoryCitations(in: evidence)
        XCTAssertGreaterThan(citations.count, 40, "Evidence parser found unexpectedly few repository citations")
        for citation in citations {
            let source = repositoryRoot.appendingPathComponent(citation.path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Missing cited source \(citation.path)")
            let sourceText = try String(contentsOf: source, encoding: .utf8)
            var sourceLineCount = 0
            sourceText.enumerateLines { _, _ in
                sourceLineCount += 1
            }
            let citedLines = try captures(#"([0-9]+)"#, in: citation.ranges).compactMap(Int.init)
            XCTAssertFalse(citedLines.isEmpty, "Citation has no line numbers: \(citation.path):\(citation.ranges)")
            XCTAssertLessThanOrEqual(
                citedLines.max() ?? 0,
                sourceLineCount,
                "Citation exceeds \(citation.path)'s \(sourceLineCount) lines: \(citation.ranges)"
            )
        }
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

    private func section(_ heading: String, before nextHeading: String, in document: String) throws -> String {
        let start = try XCTUnwrap(document.range(of: heading)?.lowerBound, "Missing heading \(heading)")
        let end = try XCTUnwrap(
            document.range(of: nextHeading, range: start..<document.endIndex)?.lowerBound,
            "Missing heading \(nextHeading) after \(heading)"
        )
        return String(document[start..<end])
    }

    private func assertContains(
        _ fragments: [String],
        in text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for fragment in fragments {
            XCTAssertTrue(text.contains(fragment), "Documentation contract missing: \(fragment)", file: file, line: line)
        }
    }

    private func captures(_ pattern: String, in text: String) throws -> [String] {
        try captureGroups(pattern, in: text).compactMap(\.first)
    }

    private func captureGroups(_ pattern: String, in text: String) throws -> [[String]] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else {
                return nil
            }
            return (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }

    private func repositoryCitations(in text: String) throws -> [(path: String, ranges: String)] {
        let citations = try captureGroups(
            #"`((?:\.github/|Docs/|DownloadDeps\.cmd|Externals/|MacMerge/|Src/|Testing/|todo\.md)[^`:]*):([0-9][0-9,-]*)`"#,
            in: text
        ).compactMap { groups -> (path: String, ranges: String)? in
            guard groups.count == 2 else {
                return nil
            }
            return (groups[0], groups[1])
        }
        return citations.flatMap { citation in
            guard let openingBrace = citation.path.firstIndex(of: "{") else {
                return [citation]
            }
            guard
                let closingBrace = citation.path[openingBrace...].firstIndex(of: "}"),
                closingBrace < citation.path.endIndex
            else {
                return [citation]
            }
            let prefix = citation.path[..<openingBrace]
            let suffix = citation.path[citation.path.index(after: closingBrace)...]
            return citation.path[openingBrace...closingBrace]
                .dropFirst()
                .dropLast()
                .split(separator: ",")
                .map { ("\(prefix)\($0)\(suffix)", citation.ranges) }
        }
    }
}
