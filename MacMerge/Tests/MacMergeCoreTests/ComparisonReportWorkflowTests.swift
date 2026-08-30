import Foundation
import XCTest

@testable import MacMergeCore

final class ComparisonReportWorkflowTests: XCTestCase {
    func testFileReportScopesPreserveFullSummaryAndOmitPartialSummary() throws {
        let snapshot = makeFileSnapshot(selectedRowIndices: [0, 2])

        let allPlan = try plan(snapshot: snapshot, scope: .all, format: .plainText)
        XCTAssertEqual(
            allPlan.primaryOutput.output.string,
            "File Report\n\nSummary\nAlpha: 1\nZulu: 9\n\n"
                + "Path\tValue\na.txt\ta\nm.txt\tm\nz.txt\tz\n"
        )

        let partialPlan = try plan(snapshot: snapshot, scope: .selected, format: .plainText)
        XCTAssertEqual(
            partialPlan.primaryOutput.output.string,
            "File Report\n\nPath\tValue\nm.txt\tm\nz.txt\tz\n"
        )
        XCTAssertFalse(partialPlan.primaryOutput.output.string.contains("Summary"))

        let fullSelection = makeFileSnapshot(selectedRowIndices: [0, 1, 2])
        let fullPlan = try plan(snapshot: fullSelection, scope: .selected, format: .plainText)
        XCTAssertEqual(fullPlan.primaryOutput.output.data, allPlan.primaryOutput.output.data)
    }

    func testFileSelectedScopeRejectsEmptyAndInvalidRowsWhileAllIgnoresEmptySelection() throws {
        let empty = makeFileSnapshot(selectedRowIndices: [])
        XCTAssertNoThrow(try plan(snapshot: empty, scope: .all))
        assertWorkflowError(.emptySelection) {
            try plan(snapshot: empty, scope: .selected)
        }

        let invalidSelections: [(indices: Set<Int>, invalidIndex: Int)] = [
            ([-1], -1),
            ([3], 3)
        ]
        for invalidSelection in invalidSelections {
            let invalid = makeFileSnapshot(selectedRowIndices: invalidSelection.indices)
            for scope in ComparisonReportScope.allCases {
                assertWorkflowError(.invalidSelectedRowIndex(invalidSelection.invalidIndex)) {
                    try plan(snapshot: invalid, scope: scope)
                }
            }
        }
    }

    func testFileRowsAreDeterministicAcrossInputAndSelectionOrder() throws {
        let identity = snapshotIdentity()
        let report = makeFileReport()
        let reversedReport = ComparisonReport(
            title: report.title,
            columns: report.columns,
            rows: report.rows.reversed(),
            summary: report.summary
        )
        let forward = makeFileSnapshot(
            identity: identity,
            report: report,
            selectedRowIndices: [0, 2]
        )
        let reversed = makeFileSnapshot(
            identity: identity,
            report: reversedReport,
            selectedRowIndices: [0, 2]
        )

        let forwardOutput = try plan(snapshot: forward, scope: .all, format: .csv)
            .primaryOutput.output.data
        let reversedOutput = try plan(snapshot: reversed, scope: .all, format: .csv)
            .primaryOutput.output.data

        XCTAssertEqual(forwardOutput, reversedOutput)
        XCTAssertEqual(
            try parseCSV(String(decoding: forwardOutput, as: UTF8.self)),
            [
                ["Path", "Value"],
                ["a.txt", "a"],
                ["m.txt", "m"],
                ["z.txt", "z"]
            ]
        )
    }

    func testFolderReportsAllSelectedFullAndEmptyScopesExactly() throws {
        let results = makeDirectoryResults(selectedIndices: [0])
        let snapshot = makeFolderSnapshot(results: results)

        let allPlan = try plan(snapshot: snapshot, scope: .all, format: .csv)
        XCTAssertEqual(
            try parseCSV(allPlan.primaryOutput.output.string),
            [
                [
                    "Path", "Left Path", "Right Path", "Status", "Kind", "Left Bytes",
                    "Right Bytes"
                ],
                ["alpha.txt", "alpha.txt", "", "Left Only", "File", "10", ""],
                ["zeta.txt", "zeta.txt", "zeta.txt", "Different", "File", "20", "21"]
            ]
        )

        let selectedPlan = try plan(snapshot: snapshot, scope: .selected, format: .plainText)
        XCTAssertEqual(
            selectedPlan.primaryOutput.output.string,
            "Folder Comparison Report\n\nSummary\nDifferent: 1\nItems: 1\n"
                + "Left Root: /tmp/macmerge-left\nRight Root: /tmp/macmerge-right\n\n"
                + "Path\tLeft Path\tRight Path\tStatus\tKind\tLeft Bytes\tRight Bytes\n"
                + "zeta.txt\tzeta.txt\tzeta.txt\tDifferent\tFile\t20\t21\n"
        )

        let fullResults = makeDirectoryResults(selectedIndices: [0, 1])
        let fullSnapshot = makeFolderSnapshot(results: fullResults)
        let selectedFull = try plan(snapshot: fullSnapshot, scope: .selected, format: .csv)
        XCTAssertEqual(selectedFull.primaryOutput.output.data, allPlan.primaryOutput.output.data)

        let emptySnapshot = makeFolderSnapshot(results: makeDirectoryResults(selectedIndices: []))
        assertWorkflowError(.emptySelection) {
            try plan(snapshot: emptySnapshot, scope: .selected)
        }
        XCTAssertNoThrow(try plan(snapshot: emptySnapshot, scope: .all))
    }

    func testFolderRowsIgnorePresentationFilterAndSortButRemainDeterministic() throws {
        var forwardResults = makeDirectoryResults(selectedIndices: [0, 1])
        forwardResults.filter = DirectoryResultFilter(
            statuses: [.different],
            pathQuery: "zeta",
            kinds: [.file],
            hidden: .exclude
        )
        forwardResults.sortDescriptors = [
            DirectoryResultSortDescriptor(key: .path, order: .descending)
        ]
        let reversedResults = DirectoryResults(
            leftRoot: forwardResults.leftRoot,
            rightRoot: forwardResults.rightRoot,
            results: forwardResults.results.reversed(),
            filter: forwardResults.filter,
            sortDescriptors: forwardResults.sortDescriptors,
            selectedIDs: forwardResults.selectedIDs
        )

        let forward = try plan(snapshot: makeFolderSnapshot(results: forwardResults), format: .csv)
        let reversed = try plan(snapshot: makeFolderSnapshot(results: reversedResults), format: .csv)

        XCTAssertEqual(forward.primaryOutput.output.data, reversed.primaryOutput.output.data)
        let records = try parseCSV(forward.primaryOutput.output.string)
        XCTAssertEqual(records.dropFirst().map { $0[0] }, ["alpha.txt", "zeta.txt"])
    }

    func testFolderFingerprintRejectsSameGenerationFilterSortAndResultOrderMutations() throws {
        let identity = snapshotIdentity()
        let roots = rootIdentity()
        let results = makeDirectoryResults(selectedIndices: [0, 1])
        let snapshot = makeFolderSnapshot(
            identity: identity,
            rootIdentity: roots,
            results: results
        )
        let planned = try plan(snapshot: snapshot)

        var changedFilter = results
        changedFilter.filter = DirectoryResultFilter(
            statuses: [.different],
            pathQuery: "zeta",
            kinds: [.file],
            hidden: .exclude
        )
        var changedSort = results
        changedSort.sortDescriptors = [
            DirectoryResultSortDescriptor(key: .status, order: .descending)
        ]
        let changedOrder = DirectoryResults(
            leftRoot: results.leftRoot,
            rightRoot: results.rightRoot,
            results: Array(results.results.reversed()),
            filter: results.filter,
            sortDescriptors: results.sortDescriptors,
            selectedIDs: results.selectedIDs
        )

        XCTAssertTrue(try planned.isCurrent(snapshot, linkedReports: []))
        XCTAssertNoThrow(
            try planned.validateCurrentSnapshot(snapshot, linkedReports: [])
        )

        for mutation in [changedFilter, changedSort, changedOrder] {
            let changedSnapshot = makeFolderSnapshot(
                identity: identity,
                generation: snapshot.generation,
                rootIdentity: roots,
                results: mutation
            )
            XCTAssertFalse(try planned.isCurrent(changedSnapshot, linkedReports: []))
            assertWorkflowError(.snapshotContentsChanged) {
                try planned.validateCurrentSnapshot(changedSnapshot, linkedReports: [])
            }
        }
    }

    func testLinkedReportsAreSortedAndFolderRowsCarryLinkedPaths() throws {
        let snapshot = makeFolderSnapshot(results: makeDirectoryResults(selectedIndices: [0, 1]))
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let results = folderResults(from: snapshot)
        let zetaLink = makeLink(
            identifier: "zeta",
            path: "details/zeta.csv",
            snapshot: reference,
            directoryResultID: results[0].id
        )
        let alphaLink = makeLink(
            identifier: "alpha",
            path: "details/alpha.csv",
            snapshot: reference,
            directoryResultID: results[1].id
        )
        let destination = fileDestination("/tmp/macmerge-workflow/report.csv")

        let planned = try plan(
            snapshot: snapshot,
            format: .csv,
            destination: destination,
            links: [zetaLink, alphaLink]
        )

        XCTAssertEqual(
            planned.outputs.map(\.role),
            [
                .primary,
                .linked(identifier: "alpha", directoryResultID: results[1].id),
                .linked(identifier: "zeta", directoryResultID: results[0].id)
            ]
        )
        let records = try parseCSV(planned.primaryOutput.output.string)
        XCTAssertEqual(records[0].last, "Linked Report")
        XCTAssertEqual(records[1].last, "details/alpha.csv")
        XCTAssertEqual(records[2].last, "details/zeta.csv")
        XCTAssertEqual(planned.estimate.reportCount, 3)
        XCTAssertEqual(planned.estimate.estimatedOutputByteCount, planned.outputs.sum(\.outputByteCount))
        XCTAssertGreaterThan(
            planned.estimate.estimatedWorkUnits,
            planned.outputs.sum(\.estimatedWorkUnits)
        )
        XCTAssertTrue(planned.outputs.allSatisfy { $0.estimatedWorkUnits > 0 })
    }

    func testLinkedFingerprintCanonicalizesOrderAndDetectsReportChanges() throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let first = makeLink(identifier: "first", path: "a.txt", snapshot: reference)
        let second = makeLink(identifier: "second", path: "b.txt", snapshot: reference)
        let destination = fileDestination("/tmp/macmerge-workflow/report.txt")
        let planned = try plan(
            snapshot: snapshot,
            destination: destination,
            links: [second, first]
        )

        XCTAssertTrue(try planned.isCurrent(snapshot, linkedReports: [first, second]))
        XCTAssertNoThrow(
            try planned.validateCurrentSnapshot(snapshot, linkedReports: [second, first])
        )

        let changed = ComparisonReportLinkedReport(
            identifier: first.identifier,
            relativeOutputPath: first.relativeOutputPath,
            report: ComparisonReport(
                title: "Changed",
                columns: first.report.columns,
                rows: first.report.rows
            ),
            snapshot: first.snapshot
        )
        XCTAssertFalse(try planned.isCurrent(snapshot, linkedReports: [changed, second]))
        assertWorkflowError(.snapshotContentsChanged) {
            try planned.validateCurrentSnapshot(snapshot, linkedReports: [changed, second])
        }
    }

    func testFileSummaryMutationInvalidatesFingerprintWhenSelectedOutputOmitsSummary() throws {
        let report = makeFileReport()
        let snapshot = makeFileSnapshot(report: report, selectedRowIndices: [0, 2])
        let planned = try plan(snapshot: snapshot, scope: .selected)
        let changedReport = ComparisonReport(
            title: report.title,
            columns: report.columns,
            rows: report.rows,
            summary: ComparisonReportSummary(items: [
                ComparisonReportSummaryItem(label: "Zulu", value: "10"),
                ComparisonReportSummaryItem(label: "Alpha", value: "1")
            ])
        )
        let changedSnapshot = makeFileSnapshot(
            identity: snapshot.identity,
            generation: snapshot.generation,
            report: changedReport,
            selectedRowIndices: [0, 2]
        )

        XCTAssertEqual(
            try plan(snapshot: changedSnapshot, scope: .selected).primaryOutput.output.data,
            planned.primaryOutput.output.data
        )
        XCTAssertFalse(try planned.isCurrent(changedSnapshot, linkedReports: []))
        assertWorkflowError(.snapshotContentsChanged) {
            try planned.validateCurrentSnapshot(changedSnapshot, linkedReports: [])
        }
    }

    func testFingerprintDetectsIdentityGenerationContentsAndFolderRootIdentity() throws {
        let snapshot = makeFileSnapshot()
        let planned = try plan(snapshot: snapshot)
        let otherIdentity = makeFileSnapshot(identity: ComparisonReportWorkflowSnapshotIdentity())
        assertWorkflowError(
            .snapshotIdentityChanged(
                expected: snapshot.identity,
                actual: otherIdentity.identity
            )
        ) {
            try planned.validateCurrentSnapshot(otherIdentity, linkedReports: [])
        }

        let otherGeneration = makeFileSnapshot(
            identity: snapshot.identity,
            generation: snapshot.generation + 1
        )
        assertWorkflowError(
            .snapshotGenerationChanged(
                expected: snapshot.generation,
                actual: otherGeneration.generation
            )
        ) {
            try planned.validateCurrentSnapshot(otherGeneration, linkedReports: [])
        }

        let changedContents = makeFileSnapshot(
            identity: snapshot.identity,
            report: ComparisonReport(
                title: "Changed",
                columns: ["Path", "Value"],
                rows: makeFileReport().rows,
                summary: makeFileReport().summary
            )
        )
        XCTAssertFalse(try planned.isCurrent(changedContents, linkedReports: []))

        let folder = makeFolderSnapshot(results: makeDirectoryResults())
        let folderPlan = try plan(snapshot: folder)
        let changedRoot = makeFolderSnapshot(
            identity: folder.identity,
            generation: folder.generation,
            rootIdentity: rootIdentity(seed: 100),
            results: folderResultsContainer(from: folder)
        )
        XCTAssertFalse(try folderPlan.isCurrent(changedRoot, linkedReports: []))
        assertWorkflowError(.snapshotContentsChanged) {
            try folderPlan.validateCurrentSnapshot(changedRoot, linkedReports: [])
        }
    }

    func testExpectedSnapshotReferenceIsCheckedBeforePlanning() throws {
        let snapshot = makeFileSnapshot()
        let wrongIdentity = ComparisonReportWorkflowSnapshotReference(
            identity: ComparisonReportWorkflowSnapshotIdentity(),
            generation: snapshot.generation
        )
        assertWorkflowError(
            .snapshotIdentityChanged(expected: wrongIdentity.identity, actual: snapshot.identity)
        ) {
            try ComparisonReportWorkflowPlanner.plan(
                request(snapshot: snapshot),
                expecting: wrongIdentity
            )
        }

        let wrongGeneration = ComparisonReportWorkflowSnapshotReference(
            identity: snapshot.identity,
            generation: snapshot.generation + 1
        )
        assertWorkflowError(
            .snapshotGenerationChanged(
                expected: wrongGeneration.generation,
                actual: snapshot.generation
            )
        ) {
            try ComparisonReportWorkflowPlanner.plan(
                request(snapshot: snapshot),
                expecting: wrongGeneration
            )
        }
    }

    func testClipboardAndFileDestinationRules() throws {
        let snapshot = makeFileSnapshot()
        let clipboard = try plan(snapshot: snapshot, destination: .clipboard)
        XCTAssertEqual(clipboard.outputs.count, 1)
        XCTAssertEqual(clipboard.primaryOutput.destination, .clipboard)

        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let link = makeLink(identifier: "child", path: "child.txt", snapshot: reference)
        assertWorkflowError(.linkedReportsRequireFileDestination) {
            try plan(snapshot: snapshot, destination: .clipboard, links: [link])
        }
        assertWorkflowError(.openAfterGenerationRequiresFileDestination) {
            try plan(snapshot: snapshot, destination: .clipboard, openAfterGeneration: true)
        }

        let file = try plan(
            snapshot: snapshot,
            destination: fileDestination(
                "/tmp/macmerge-workflow/report.txt",
                overwritePolicy: .replaceExisting
            ),
            openAfterGeneration: true
        )
        XCTAssertTrue(file.openAfterGeneration)
        guard
            case .file(_, _, let overwritePolicy, let sandboxAccess) =
                file.primaryOutput.destination
        else {
            return XCTFail("Expected file destination")
        }
        XCTAssertEqual(overwritePolicy, .replaceExisting)
        XCTAssertEqual(sandboxAccess, .ambient)
    }

    func testLocalhostCaseVariantsAreAcceptedAndRemoteHostsAreRejected() throws {
        let snapshot = makeFileSnapshot()
        let accepted = [
            URL(fileURLWithPath: "/tmp/macmerge-workflow/no-host.txt"),
            URL(string: "file://localhost/tmp/macmerge-workflow/lower.txt")!,
            URL(string: "file://LOCALHOST/tmp/macmerge-workflow/upper.txt")!,
            URL(string: "file://LoCaLhOsT/tmp/macmerge-workflow/mixed.txt")!
        ]

        for url in accepted {
            XCTAssertNoThrow(
                try plan(snapshot: snapshot, destination: fileDestination(url)),
                url.absoluteString
            )
        }

        let remote = URL(string: "file://example.com/tmp/macmerge-workflow/report.txt")!
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .remoteHost)) {
            try plan(snapshot: snapshot, destination: fileDestination(remote))
        }
    }

    func testRequestedURLSpellingIsPreservedWhileIdentityIsStandardized() throws {
        let spelling = "file:///tmp/macmerge-workflow/spelled/../Report.txt"
        let requestedURL = URL(string: spelling)!
        let planned = try plan(
            snapshot: makeFileSnapshot(),
            destination: fileDestination(requestedURL)
        )

        guard case .file(let storedURL, let identity, _, _) = planned.primaryOutput.destination
        else {
            return XCTFail("Expected file destination")
        }
        XCTAssertEqual(requestedURL.absoluteString, spelling)
        XCTAssertEqual(storedURL, requestedURL)
        XCTAssertEqual(storedURL.absoluteString, spelling)
        XCTAssertEqual(identity.canonicalPath, "/tmp/macmerge-workflow/Report.txt")
        XCTAssertEqual(identity.canonicalPathUTF8Bytes, Array(identity.canonicalPath.utf8))
        XCTAssertEqual(identity.fileURL.path, identity.canonicalPath)
    }

    func testOutputURLPreflightRejectsEverySupportedHostileComponentShape() throws {
        let snapshot = makeFileSnapshot()
        let relative = URL(
            string: "report.txt",
            relativeTo: URL(fileURLWithPath: "/tmp/macmerge-workflow/", isDirectory: true)
        )!
        let cases: [(URL, ComparisonReportFileURLIssue)] = [
            (URL(string: "https://example.com/report.txt")!, .notFileURL),
            (URL(string: "data:text/plain,report")!, .notFileURL),
            (relative, .relativeURL),
            (URL(string: "file:report.txt")!, .relativeURL),
            (URL(string: "file://127.0.0.1/tmp/report.txt")!, .remoteHost),
            (URL(string: "file://[::1]/tmp/report.txt")!, .remoteHost),
            (URL(string: "file://user:pass@localhost/tmp/report.txt")!, .credentialsOrPort),
            (URL(string: "file://user@localhost/tmp/report.txt")!, .credentialsOrPort),
            (URL(string: "file://localhost:99/tmp/report.txt")!, .credentialsOrPort),
            (URL(string: "file:///tmp/report.txt?download=1")!, .queryOrFragment),
            (URL(string: "file:///tmp/report.txt#section")!, .queryOrFragment),
            (DirectPathURL(path: "/tmp/report\0.txt")! as URL, .nullByte),
            (URL(string: "file:///tmp/report.txt/")!, .directoryURL),
            (URL(string: "file://localhost")!, .relativeURL),
            (URL(fileURLWithPath: "/tmp/report.csv"), .extensionMismatch)
        ]

        for (url, issue) in cases {
            assertWorkflowError(.invalidFileURL(role: .primary, issue: issue)) {
                try plan(snapshot: snapshot, destination: fileDestination(url))
            }
        }
    }

    func testSecurityScopeURLPreflightRejectsEverySupportedHostileComponentShape() throws {
        let snapshot = makeFileSnapshot()
        let outputURL = URL(fileURLWithPath: "/tmp/macmerge-workflow/report.txt")
        let relative = URL(
            string: "scope",
            relativeTo: URL(fileURLWithPath: "/tmp/macmerge-workflow/", isDirectory: true)
        )!
        let cases: [(URL, ComparisonReportFileURLIssue)] = [
            (URL(string: "https://example.com/scope")!, .notFileURL),
            (URL(string: "data:text/plain,scope")!, .notFileURL),
            (relative, .relativeURL),
            (URL(string: "file:scope")!, .relativeURL),
            (URL(string: "file://127.0.0.1/tmp/macmerge-workflow")!, .remoteHost),
            (URL(string: "file://[::1]/tmp/macmerge-workflow")!, .remoteHost),
            (URL(string: "file://user:pass@localhost/tmp/macmerge-workflow")!, .credentialsOrPort),
            (URL(string: "file://user@localhost/tmp/macmerge-workflow")!, .credentialsOrPort),
            (URL(string: "file://localhost:99/tmp/macmerge-workflow")!, .credentialsOrPort),
            (URL(string: "file:///tmp/macmerge-workflow?scope=1")!, .queryOrFragment),
            (URL(string: "file:///tmp/macmerge-workflow#scope")!, .queryOrFragment),
            (DirectPathURL(path: "/tmp/macmerge\0-workflow")! as URL, .nullByte)
        ]

        for (url, issue) in cases {
            assertWorkflowError(.invalidSecurityScopeURL(issue)) {
                try plan(
                    snapshot: snapshot,
                    destination: fileDestination(
                        outputURL,
                        sandboxAccess: .securityScoped(
                            resourceURL: url,
                            coverage: .directoryTree
                        )
                    )
                )
            }
        }
    }

    func testFullURLSpellingBoundWinsBeforeComponentSemantics() throws {
        let snapshot = makeFileSnapshot()
        let value = String(repeating: "x", count: 512)
        let boundedLimits = limits(
            maximumPathUTF8Bytes: 32,
            maximumTotalPathUTF8Bytes: 128
        )
        let urls = [
            componentURL(scheme: "https", host: "example.com", path: "/report.txt", query: value),
            componentURL(scheme: "file", user: value, host: "localhost", path: "/tmp/report.txt"),
            componentURL(scheme: "file", host: "localhost", path: "/tmp/report.txt", query: value),
            componentURL(
                scheme: "file",
                host: "localhost",
                path: "/tmp/report.txt",
                fragment: value
            )
        ]

        for url in urls {
            assertWorkflowError(.invalidFileURL(role: .primary, issue: .pathTooLong)) {
                try plan(
                    snapshot: snapshot,
                    destination: fileDestination(url),
                    limits: boundedLimits
                )
            }
        }

        let destinationURL = URL(fileURLWithPath: "/tmp/report.txt")
        let oversizedScope = componentURL(
            scheme: "file",
            host: "localhost",
            path: "/tmp",
            query: value
        )
        assertWorkflowError(.invalidSecurityScopeURL(.pathTooLong)) {
            try plan(
                snapshot: snapshot,
                destination: fileDestination(
                    destinationURL,
                    sandboxAccess: .securityScoped(
                        resourceURL: oversizedScope,
                        coverage: .directoryTree
                    )
                ),
                limits: boundedLimits
            )
        }
    }

    func testPlannerAppliesLexicalSecurityScopeCoveragePreflight() throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let link = makeLink(identifier: "child", path: "details/child.txt", snapshot: reference)
        let primary = URL(fileURLWithPath: "/tmp/macmerge-workflow/report.txt")

        XCTAssertNoThrow(
            try plan(
                snapshot: snapshot,
                destination: fileDestination(
                    primary,
                    sandboxAccess: .securityScoped(resourceURL: primary, coverage: .exactFile)
                )
            )
        )
        XCTAssertNoThrow(
            try plan(
                snapshot: snapshot,
                destination: fileDestination(
                    primary,
                    sandboxAccess: .securityScoped(
                        resourceURL: URL(
                            fileURLWithPath: "/tmp/macmerge-workflow",
                            isDirectory: true
                        ),
                        coverage: .directoryTree
                    )
                ),
                links: [link]
            )
        )
        XCTAssertNoThrow(
            try plan(
                snapshot: snapshot,
                destination: fileDestination(
                    primary,
                    sandboxAccess: .securityScoped(
                        resourceURL: URL(fileURLWithPath: "/TMP/MACMERGE-WORKFLOW/REPORT.TXT"),
                        coverage: .exactFile
                    )
                )
            )
        )

        assertSecurityScopeCoverageError {
            try plan(
                snapshot: snapshot,
                destination: fileDestination(
                    primary,
                    sandboxAccess: .securityScoped(resourceURL: primary, coverage: .exactFile)
                ),
                links: [link]
            )
        }
        assertSecurityScopeCoverageError {
            try plan(
                snapshot: snapshot,
                destination: fileDestination(
                    primary,
                    sandboxAccess: .securityScoped(
                        resourceURL: URL(fileURLWithPath: "/tmp/elsewhere", isDirectory: true),
                        coverage: .directoryTree
                    )
                )
            )
        }
    }

    func testDuplicateAndAncestorOutputIdentitiesAreRejected() throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let destination = fileDestination("/tmp/macmerge-workflow/report.txt")

        let duplicate = makeLink(identifier: "duplicate", path: "report.txt", snapshot: reference)
        assertOutputIdentityError(isOverlap: false) {
            try plan(snapshot: snapshot, destination: destination, links: [duplicate])
        }

        let descendant = makeLink(
            identifier: "descendant",
            path: "report.txt/child.txt",
            snapshot: reference
        )
        assertOutputIdentityError(isOverlap: true) {
            try plan(snapshot: snapshot, destination: destination, links: [descendant])
        }

        let ancestor = makeLink(identifier: "ancestor", path: "group.txt", snapshot: reference)
        let child = makeLink(
            identifier: "child",
            path: "group.txt/child.txt",
            snapshot: reference
        )
        assertOutputIdentityError(isOverlap: true) {
            try plan(snapshot: snapshot, destination: destination, links: [child, ancestor])
        }
    }

    func testOutputIdentityPrefixWithoutSlashBoundaryIsDistinct() throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let nearPrefix = makeLink(
            identifier: "near-prefix",
            path: "report.txtx/child.txt",
            snapshot: reference
        )

        let planned = try plan(
            snapshot: snapshot,
            destination: fileDestination("/tmp/macmerge-workflow/report.txt"),
            links: [nearPrefix]
        )
        XCTAssertEqual(planned.outputs.count, 2)
    }

    func testLinkedValidationRejectsIdentifiersSnapshotsAndScopeViolations() throws {
        let file = makeFileSnapshot()
        let fileReference = ComparisonReportWorkflowSnapshotReference(file)
        let valid = makeLink(identifier: "child", path: "child.txt", snapshot: fileReference)
        let destination = fileDestination("/tmp/macmerge-workflow/report.txt")

        let invalidIdentifiers = ["", "bad\nidentifier", "bad\0identifier"]
        for identifier in invalidIdentifiers {
            let link = makeLink(identifier: identifier, path: "child.txt", snapshot: fileReference)
            assertWorkflowError(.invalidLinkedIdentifier(identifier)) {
                try plan(snapshot: file, destination: destination, links: [link])
            }
        }

        assertWorkflowError(.duplicateLinkedIdentifier("child")) {
            try plan(snapshot: file, destination: destination, links: [valid, valid])
        }

        let wrongSnapshot = makeLink(
            identifier: "child",
            path: "child.txt",
            snapshot: ComparisonReportWorkflowSnapshotReference(
                identity: file.identity,
                generation: file.generation + 1
            )
        )
        assertWorkflowError(.linkedReportSnapshotMismatch(identifier: "child")) {
            try plan(snapshot: file, destination: destination, links: [wrongSnapshot])
        }

        let folder = makeFolderSnapshot(results: makeDirectoryResults(selectedIndices: [0]))
        let folderReference = ComparisonReportWorkflowSnapshotReference(folder)
        let rows = folderResults(from: folder)
        let outsideSelection = makeLink(
            identifier: "outside",
            path: "outside.txt",
            snapshot: folderReference,
            directoryResultID: rows[1].id
        )
        assertWorkflowError(
            .linkedDirectoryResultNotInScope(identifier: "outside", id: rows[1].id)
        ) {
            try plan(
                snapshot: folder,
                scope: .selected,
                destination: destination,
                links: [outsideSelection]
            )
        }

        let first = makeLink(
            identifier: "first",
            path: "first.txt",
            snapshot: folderReference,
            directoryResultID: rows[0].id
        )
        let second = makeLink(
            identifier: "second",
            path: "second.txt",
            snapshot: folderReference,
            directoryResultID: rows[0].id
        )
        assertWorkflowError(.duplicateLinkedDirectoryResult(rows[0].id)) {
            try plan(snapshot: folder, destination: destination, links: [first, second])
        }
    }

    func testLinkedRelativePathPreflightRejectsEveryTraversalAndEmptyComponentPosition() throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let destination = fileDestination("/tmp/macmerge-workflow/report.txt")
        let invalidPaths = [
            "", "/", "/child.txt", "//child.txt", ".", "..", "./child.txt", "child.txt/.",
            "child.txt/./leaf.txt", "../child.txt", "child.txt/..", "child.txt/../leaf.txt",
            "a//child.txt", "a/", "child\0.txt", "a/child\0.txt"
        ]

        for path in invalidPaths {
            let link = makeLink(identifier: "child", path: path, snapshot: reference)
            assertWorkflowError(.invalidLinkedRelativePath(path)) {
                try plan(snapshot: snapshot, destination: destination, links: [link])
            }
        }
    }

    func testPlanningCreatesNoOutputFilesAndCarriesExactGeneratedBytes() throws {
        let unique = UUID().uuidString
        let outputPath = "/tmp/macmerge-workflow-plan-only-\(unique)/report.txt"
        let childPath = "/tmp/macmerge-workflow-plan-only-\(unique)/child.txt"
        let snapshot = makeFileSnapshot()
        let link = makeLink(
            identifier: "child",
            path: "child.txt",
            snapshot: ComparisonReportWorkflowSnapshotReference(snapshot)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: childPath))

        let planned = try plan(
            snapshot: snapshot,
            destination: fileDestination(outputPath),
            links: [link],
            openAfterGeneration: true
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: childPath))
        XCTAssertEqual(
            planned.outputs.map(\.output.data),
            [
                try makeFileReport().data(format: .plainText),
                try link.report.data(format: .plainText)
            ]
        )
    }

    func testPlanExposesRequiredExecutorContractValues() throws {
        let contract = try plan(snapshot: makeFileSnapshot()).executorContract

        XCTAssertEqual(contract, .required)
        XCTAssertEqual(ComparisonReportExecutorContract(), .required)
        XCTAssertEqual(contract.pathResolution, .canonicalDescriptorRelativeNoFollow)
        XCTAssertEqual(contract.publication, .publishExactPlannedBytesAtomicallyInPlanOrder)
        XCTAssertEqual(
            contract.securityScope,
            .balancedAccessAroundValidationPublicationAndOpen
        )
        XCTAssertEqual(contract.snapshot, .validateExactRootAndLinkedSnapshotsBeforeEffects)
        XCTAssertEqual(
            contract.cancellation,
            .cancelBeforePublicationOrFinishAndReportPublication
        )
        XCTAssertEqual(
            contract.opening,
            .openPrimaryFileOnlyAfterAllOutputsPublishSuccessfully
        )
        XCTAssertEqual(Set([contract, .required, ComparisonReportExecutorContract()]).count, 1)
    }

    func testEveryLimitRejectsIndependentValuesOutsideItsBounds() throws {
        let invalidCases: [(String, Int, ComparisonReportWorkflowLimits)] = [
            ("maximumReportCount", 0, limits(maximumReportCount: 0)),
            (
                "maximumReportCount",
                ComparisonReportWorkflowLimits.hardMaximumReportCount + 1,
                limits(
                    maximumReportCount: ComparisonReportWorkflowLimits.hardMaximumReportCount + 1
                )
            ),
            ("maximumRowCount", 0, limits(maximumRowCount: 0)),
            (
                "maximumRowCount",
                ComparisonReportWorkflowLimits.hardMaximumRowCount + 1,
                limits(maximumRowCount: ComparisonReportWorkflowLimits.hardMaximumRowCount + 1)
            ),
            ("maximumItemCount", 0, limits(maximumItemCount: 0)),
            (
                "maximumItemCount",
                ComparisonReportWorkflowLimits.hardMaximumItemCount + 1,
                limits(maximumItemCount: ComparisonReportWorkflowLimits.hardMaximumItemCount + 1)
            ),
            ("maximumInputUTF8Bytes", 0, limits(maximumInputUTF8Bytes: 0)),
            (
                "maximumInputUTF8Bytes",
                ComparisonReportWorkflowLimits.hardMaximumInputUTF8Bytes + 1,
                limits(
                    maximumInputUTF8Bytes:
                        ComparisonReportWorkflowLimits.hardMaximumInputUTF8Bytes + 1
                )
            ),
            (
                "maximumOutputBytes",
                0,
                limits(maximumOutputBytes: 0, maximumOutputBytesPerReport: 1)
            ),
            (
                "maximumOutputBytes",
                ComparisonReportWorkflowLimits.hardMaximumOutputBytes + 1,
                limits(
                    maximumOutputBytes: ComparisonReportWorkflowLimits.hardMaximumOutputBytes + 1,
                    maximumOutputBytesPerReport: 1
                )
            ),
            ("maximumOutputBytesPerReport", 0, limits(maximumOutputBytesPerReport: 0)),
            (
                "maximumOutputBytesPerReport",
                ComparisonReportWorkflowLimits.hardMaximumOutputBytesPerReport + 1,
                limits(
                    maximumOutputBytes: ComparisonReportWorkflowLimits.hardMaximumOutputBytes,
                    maximumOutputBytesPerReport:
                        ComparisonReportWorkflowLimits.hardMaximumOutputBytesPerReport + 1
                )
            ),
            ("maximumWorkUnits", 0, limits(maximumWorkUnits: 0)),
            (
                "maximumWorkUnits",
                ComparisonReportWorkflowLimits.hardMaximumWorkUnits + 1,
                limits(maximumWorkUnits: ComparisonReportWorkflowLimits.hardMaximumWorkUnits + 1)
            ),
            (
                "maximumPathUTF8Bytes",
                0,
                limits(maximumPathUTF8Bytes: 0, maximumTotalPathUTF8Bytes: 1)
            ),
            (
                "maximumPathUTF8Bytes",
                ComparisonReportWorkflowLimits.hardMaximumPathUTF8Bytes + 1,
                limits(
                    maximumPathUTF8Bytes:
                        ComparisonReportWorkflowLimits.hardMaximumPathUTF8Bytes + 1,
                    maximumTotalPathUTF8Bytes:
                        ComparisonReportWorkflowLimits.hardMaximumPathUTF8Bytes + 1
                )
            ),
            (
                "maximumTotalPathUTF8Bytes",
                0,
                limits(maximumPathUTF8Bytes: 1, maximumTotalPathUTF8Bytes: 0)
            ),
            (
                "maximumTotalPathUTF8Bytes",
                ComparisonReportWorkflowLimits.hardMaximumTotalPathUTF8Bytes + 1,
                limits(
                    maximumPathUTF8Bytes: 1,
                    maximumTotalPathUTF8Bytes:
                        ComparisonReportWorkflowLimits.hardMaximumTotalPathUTF8Bytes + 1
                )
            ),
            ("maximumIdentifierUTF8Bytes", 0, limits(maximumIdentifierUTF8Bytes: 0)),
            (
                "maximumIdentifierUTF8Bytes",
                ComparisonReportWorkflowLimits.hardMaximumIdentifierUTF8Bytes + 1,
                limits(
                    maximumIdentifierUTF8Bytes:
                        ComparisonReportWorkflowLimits.hardMaximumIdentifierUTF8Bytes + 1
                )
            ),
            ("cancellationCheckInterval", 0, limits(cancellationCheckInterval: 0)),
            (
                "cancellationCheckInterval",
                1_048_577,
                limits(cancellationCheckInterval: 1_048_577)
            )
        ]

        for (name, value, invalidLimits) in invalidCases {
            assertWorkflowError(.invalidLimit(name: name, value: value)) {
                try plan(snapshot: makeFileSnapshot(), limits: invalidLimits)
            }
        }
    }

    func testRuntimePathByteBoundariesUseCanonicalOutputLengths() throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let primaryURL = URL(fileURLWithPath: "/tmp/macmerge-workflow-boundary/report.txt")
        let link = makeLink(identifier: "child", path: "details/child.txt", snapshot: reference)
        let baseline = try plan(
            snapshot: snapshot,
            destination: fileDestination(primaryURL),
            links: [link]
        )
        let pathByteCounts = baseline.outputs.map { output -> Int in
            guard case .file(_, let identity, _, _) = output.destination else {
                preconditionFailure("Expected file destination")
            }
            return identity.canonicalPathUTF8Bytes.count
        }
        let maximumPathBytes = pathByteCounts.max()!
        let totalPathBytes = pathByteCounts.reduce(0, +)

        XCTAssertNoThrow(
            try plan(
                snapshot: snapshot,
                destination: fileDestination(primaryURL),
                links: [link],
                limits: limits(
                    maximumPathUTF8Bytes: maximumPathBytes,
                    maximumTotalPathUTF8Bytes: totalPathBytes
                )
            )
        )
        assertWorkflowError(.totalPathsTooLarge(maximumUTF8Bytes: totalPathBytes - 1)) {
            try plan(
                snapshot: snapshot,
                destination: fileDestination(primaryURL),
                links: [link],
                limits: limits(
                    maximumPathUTF8Bytes: maximumPathBytes,
                    maximumTotalPathUTF8Bytes: totalPathBytes - 1
                )
            )
        }

        let oversizedPrimaryURL = URL(
            fileURLWithPath: primaryURL.deletingPathExtension().path + "x.txt"
        )
        assertWorkflowError(.invalidFileURL(role: .primary, issue: .pathTooLong)) {
            try plan(
                snapshot: snapshot,
                destination: fileDestination(oversizedPrimaryURL),
                limits: limits(
                    maximumPathUTF8Bytes: primaryURL.path.utf8.count,
                    maximumTotalPathUTF8Bytes: primaryURL.path.utf8.count
                )
            )
        }
    }

    func testRuntimeIdentifierUTF8ByteBoundaryAcceptsExactAndRejectsOneOver() throws {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        let destination = fileDestination("/tmp/macmerge-workflow/report.txt")
        let exact = "éé"
        let oneOver = exact + "a"
        XCTAssertEqual(exact.utf8.count, 4)
        XCTAssertEqual(oneOver.utf8.count, 5)

        XCTAssertNoThrow(
            try plan(
                snapshot: snapshot,
                destination: destination,
                links: [makeLink(identifier: exact, path: "exact.txt", snapshot: reference)],
                limits: limits(maximumIdentifierUTF8Bytes: 4)
            )
        )
        assertWorkflowError(.invalidLinkedIdentifier(oneOver)) {
            try plan(
                snapshot: snapshot,
                destination: destination,
                links: [makeLink(identifier: oneOver, path: "over.txt", snapshot: reference)],
                limits: limits(maximumIdentifierUTF8Bytes: 4)
            )
        }
    }

    func testEveryFormatAcceptsExactGeneratedByteLimitAndRejectsOneUnder() throws {
        let snapshot = makeFileSnapshot()

        for format in ComparisonReportFormat.allCases {
            let baseline = try plan(snapshot: snapshot, format: format)
            let byteCount = baseline.primaryOutput.outputByteCount
            let exactLimits = limits(
                maximumOutputBytes: byteCount,
                maximumOutputBytesPerReport: byteCount
            )
            let exact = try plan(snapshot: snapshot, format: format, limits: exactLimits)
            XCTAssertEqual(exact.primaryOutput.output.data, baseline.primaryOutput.output.data)
            XCTAssertEqual(exact.primaryOutput.output.format, format)

            assertWorkflowError(
                .reportGeneration(
                    role: .primary,
                    error: .outputTooLarge(maximumBytes: byteCount - 1)
                )
            ) {
                try plan(
                    snapshot: snapshot,
                    format: format,
                    limits: limits(
                        maximumOutputBytes: byteCount - 1,
                        maximumOutputBytesPerReport: byteCount - 1
                    )
                )
            }
        }
    }

    func testDependentLimitRelationshipsAreValidated() throws {
        assertWorkflowError(.invalidLimit(name: "maximumOutputBytesPerReport", value: 2)) {
            try plan(
                snapshot: makeFileSnapshot(),
                limits: limits(maximumOutputBytes: 1, maximumOutputBytesPerReport: 2)
            )
        }
        assertWorkflowError(.invalidLimit(name: "maximumTotalPathUTF8Bytes", value: 31)) {
            try plan(
                snapshot: makeFileSnapshot(),
                limits: limits(maximumPathUTF8Bytes: 32, maximumTotalPathUTF8Bytes: 31)
            )
        }
    }

    func testIndependentLiteralRowsItemsInputOutputAndWorkBoundaries() throws {
        let snapshot = makeFileSnapshot(selectedRowIndices: [0, 2])
        let baseline = try plan(snapshot: snapshot)
        XCTAssertEqual(baseline.estimate.rowCount, 3)
        XCTAssertEqual(baseline.estimate.inputItemCount, 18)
        XCTAssertEqual(baseline.estimate.inputUTF8ByteCount, 52)

        XCTAssertNoThrow(try plan(snapshot: snapshot, limits: limits(maximumRowCount: 3)))
        XCTAssertNoThrow(try plan(snapshot: snapshot, limits: limits(maximumItemCount: 18)))
        XCTAssertNoThrow(
            try plan(snapshot: snapshot, limits: limits(maximumInputUTF8Bytes: 52))
        )
        XCTAssertNoThrow(
            try plan(
                snapshot: snapshot,
                limits: limits(
                    maximumOutputBytes: baseline.estimate.estimatedOutputByteCount,
                    maximumOutputBytesPerReport: baseline.estimate.estimatedOutputByteCount
                )
            )
        )
        XCTAssertNoThrow(
            try plan(
                snapshot: snapshot,
                limits: limits(maximumWorkUnits: baseline.estimate.estimatedWorkUnits)
            )
        )

        assertWorkflowError(.tooManyRows(maximum: 2)) {
            try plan(snapshot: snapshot, limits: limits(maximumRowCount: 2))
        }
        assertWorkflowError(.tooManyItems(maximum: 17)) {
            try plan(snapshot: snapshot, limits: limits(maximumItemCount: 17))
        }
        assertWorkflowError(.inputTooLarge(maximumUTF8Bytes: 51)) {
            try plan(snapshot: snapshot, limits: limits(maximumInputUTF8Bytes: 51))
        }
        assertWorkflowError(
            .reportGeneration(
                role: .primary,
                error: .outputTooLarge(
                    maximumBytes: baseline.estimate.estimatedOutputByteCount - 1
                )
            )
        ) {
            try plan(
                snapshot: snapshot,
                limits: limits(
                    maximumOutputBytes: baseline.estimate.estimatedOutputByteCount - 1,
                    maximumOutputBytesPerReport: baseline.estimate.estimatedOutputByteCount - 1
                )
            )
        }
        assertWorkflowError(
            .workLimitExceeded(maximumWorkUnits: baseline.estimate.estimatedWorkUnits - 1)
        ) {
            try plan(
                snapshot: snapshot,
                limits: limits(maximumWorkUnits: baseline.estimate.estimatedWorkUnits - 1)
            )
        }
    }

    func testLinkedAggregateReportAndOutputLimitBoundaries() throws {
        let snapshot = makeFileSnapshot()
        let link = makeLink(
            identifier: "child",
            path: "child.txt",
            snapshot: ComparisonReportWorkflowSnapshotReference(snapshot)
        )
        let destination = fileDestination("/tmp/macmerge-workflow/report.txt")
        XCTAssertNoThrow(
            try plan(
                snapshot: snapshot,
                destination: destination,
                links: [link],
                limits: limits(maximumReportCount: 2)
            )
        )
        assertWorkflowError(.tooManyReports(maximum: 1)) {
            try plan(
                snapshot: snapshot,
                destination: destination,
                links: [link],
                limits: limits(maximumReportCount: 1)
            )
        }

        let baseline = try plan(snapshot: snapshot, destination: destination, links: [link])
        let maximumPerReport = baseline.outputs.map(\.outputByteCount).max()!
        let aggregateLimit = baseline.estimate.estimatedOutputByteCount - 1
        XCTAssertNoThrow(
            try plan(
                snapshot: snapshot,
                destination: destination,
                links: [link],
                limits: limits(
                    maximumOutputBytes: baseline.estimate.estimatedOutputByteCount,
                    maximumOutputBytesPerReport: maximumPerReport
                )
            )
        )
        assertWorkflowError(.outputTooLarge(maximumBytes: aggregateLimit)) {
            try plan(
                snapshot: snapshot,
                destination: destination,
                links: [link],
                limits: limits(
                    maximumOutputBytes: aggregateLimit,
                    maximumOutputBytesPerReport: maximumPerReport
                )
            )
        }
    }

    func testSynchronousGenerationAboveEightMiBWorkCapFailsBeforeGenerationAndCreatesNoFile() throws {
        XCTAssertEqual(
            ComparisonReportWorkflowLimits.hardMaximumSynchronousGenerationWorkUnits,
            8 * 1_024 * 1_024
        )
        let payload = String(repeating: "x", count: 600_000)
        let report = ComparisonReport(
            title: "Work Cap",
            columns: ["Value"],
            rows: [ComparisonReportRow(values: [payload], sortKey: "")]
        )
        let snapshot = makeFileSnapshot(report: report)
        let outputPath = "/tmp/macmerge-workflow-generation-cap-\(UUID().uuidString).txt"
        let recorder = SortRecorder()

        ComparisonReport.$rowSortObserver.withValue(
            { recorder.record() },
            operation: {
                assertWorkflowError(
                    .workLimitExceeded(
                        maximumWorkUnits:
                            ComparisonReportWorkflowLimits
                            .hardMaximumSynchronousGenerationWorkUnits
                    )
                ) {
                    try plan(
                        snapshot: snapshot,
                        destination: fileDestination(outputPath)
                    )
                }
            }
        )
        XCTAssertEqual(recorder.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputPath))
    }

    func testPlanningAndSnapshotValidationMapCancellationToWorkflowDomain() async throws {
        let snapshot = makeFileSnapshot()
        let request = request(snapshot: snapshot)
        let planningError = await Task { () -> ComparisonReportWorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ComparisonReportWorkflowPlanner.plan(request)
                return nil
            } catch let error as ComparisonReportWorkflowError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(planningError, .cancelled)

        let planned = try ComparisonReportWorkflowPlanner.plan(request)
        let validationError = await Task { () -> ComparisonReportWorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try planned.validateCurrentSnapshot(snapshot, linkedReports: [])
                return nil
            } catch let error as ComparisonReportWorkflowError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(validationError, .cancelled)
    }

    func testCompletedOutcomeFactoryValidatesEveryDispositionAndOpenState() throws {
        let createPlan = try multiOutputPlan(overwritePolicy: .failIfExists)
        let completed = ComparisonReportExecutionOutcomeFactory.completed(
            plan: createPlan,
            dispositions: [.created, .created, .created],
            openOutcome: .notRequested
        )
        guard case .completed(let result) = completed else {
            return XCTFail("Expected completed outcome")
        }
        XCTAssertEqual(result.snapshot, createPlan.snapshotFingerprint.reference)
        XCTAssertEqual(result.outputs.map(\.role), createPlan.outputs.map(\.role))
        XCTAssertEqual(result.outputs.map(\.byteCount), createPlan.outputs.map(\.outputByteCount))
        XCTAssertEqual(result.outputs.map(\.disposition), [.created, .created, .created])
        XCTAssertEqual(result.openOutcome, .notRequested)

        let primaryIdentity = try fileIdentity(createPlan.primaryOutput)
        for openOutcome in [
            ComparisonReportOpenOutcome.opened(primaryIdentity),
            .failed(primaryIdentity)
        ] {
            assertInvalidPlanOutcome(
                ComparisonReportExecutionOutcomeFactory.completed(
                    plan: createPlan,
                    dispositions: [.created, .created, .created],
                    openOutcome: openOutcome
                )
            )
        }

        assertInvalidPlanOutcome(
            ComparisonReportExecutionOutcomeFactory.completed(
                plan: createPlan,
                dispositions: [.created, .replaced, .created],
                openOutcome: .notRequested
            )
        )
        assertInvalidPlanOutcome(
            ComparisonReportExecutionOutcomeFactory.completed(
                plan: createPlan,
                dispositions: [.created, .created, .replaced],
                openOutcome: .notRequested
            )
        )
        assertInvalidPlanOutcome(
            ComparisonReportExecutionOutcomeFactory.completed(
                plan: createPlan,
                dispositions: [.created, .created],
                openOutcome: .notRequested
            )
        )

        let replacePlan = try multiOutputPlan(overwritePolicy: .replaceExisting)
        guard
            case .completed(let replaceResult) =
                ComparisonReportExecutionOutcomeFactory.completed(
                    plan: replacePlan,
                    dispositions: [.created, .replaced, .created],
                    openOutcome: .notRequested
                )
        else {
            return XCTFail("Replace policy should allow created and replaced dispositions")
        }
        XCTAssertEqual(replaceResult.outputs.map(\.disposition), [.created, .replaced, .created])

        let clipboardPlan = try plan(snapshot: makeFileSnapshot(), destination: .clipboard)
        guard
            case .completed(let clipboardResult) =
                ComparisonReportExecutionOutcomeFactory.completed(
                    plan: clipboardPlan,
                    dispositions: [.copiedToClipboard],
                    openOutcome: .notRequested
                )
        else {
            return XCTFail("Expected clipboard completion")
        }
        XCTAssertEqual(clipboardResult.outputs.first?.identity, .clipboard)
        assertInvalidPlanOutcome(
            ComparisonReportExecutionOutcomeFactory.completed(
                plan: clipboardPlan,
                dispositions: [.created],
                openOutcome: .notRequested
            )
        )
    }

    func testFailureOutcomeFactoryRequiresNextOutputAfterCompletedPrefix() throws {
        let planned = try multiOutputPlan(overwritePolicy: .failIfExists)
        let firstIdentity = planned.outputs[0].destination.outputIdentity
        let secondIdentity = planned.outputs[1].destination.outputIdentity
        let thirdIdentity = planned.outputs[2].destination.outputIdentity
        let replacePlan = try multiOutputPlan(overwritePolicy: .replaceExisting)
        let replaceIdentity = replacePlan.outputs[0].destination.outputIdentity

        guard
            case .failed(let before) = ComparisonReportExecutionOutcomeFactory.failed(
                plan: planned,
                code: .outputAlreadyExists,
                outputIdentity: firstIdentity
            )
        else {
            return XCTFail("Expected pre-publication failure")
        }
        XCTAssertEqual(before.code, .outputAlreadyExists)
        XCTAssertEqual(before.outputIdentity, firstIdentity)
        XCTAssertTrue(before.completedOutputs.isEmpty)

        guard
            case .failed(let during) = ComparisonReportExecutionOutcomeFactory.failed(
                plan: planned,
                code: .publicationFailed,
                outputIdentity: secondIdentity,
                completedDispositions: [.created]
            )
        else {
            return XCTFail("Expected in-publication failure")
        }
        XCTAssertEqual(during.completedOutputs.map(\.identity), [firstIdentity])
        XCTAssertEqual(during.outputIdentity, secondIdentity)

        let invalidOutcomes = [
            ComparisonReportExecutionOutcomeFactory.failed(
                plan: planned,
                code: .publicationFailed,
                outputIdentity: firstIdentity,
                completedDispositions: [.created]
            ),
            ComparisonReportExecutionOutcomeFactory.failed(
                plan: planned,
                code: .publicationFailed,
                outputIdentity: thirdIdentity,
                completedDispositions: [.created]
            ),
            ComparisonReportExecutionOutcomeFactory.failed(
                plan: planned,
                code: .staleSnapshot,
                completedDispositions: [.created]
            ),
            ComparisonReportExecutionOutcomeFactory.failed(
                plan: planned,
                code: .clipboardUnavailable,
                outputIdentity: firstIdentity
            ),
            ComparisonReportExecutionOutcomeFactory.failed(
                plan: replacePlan,
                code: .outputAlreadyExists,
                outputIdentity: replaceIdentity
            ),
            ComparisonReportExecutionOutcomeFactory.failed(
                plan: planned,
                code: .securityScopeUnavailable,
                outputIdentity: firstIdentity
            ),
            ComparisonReportExecutionOutcomeFactory.failed(
                plan: planned,
                code: .publicationFailed,
                completedDispositions: [.created, .created, .created]
            )
        ]
        for outcome in invalidOutcomes {
            assertInvalidPlanOutcome(outcome)
        }
    }

    func testCancellationOutcomeFactoryAcceptsOnlyPendingActionPrefixes() throws {
        let planned = try multiOutputPlan(overwritePolicy: .failIfExists)

        guard
            case .cancelled(let before) = ComparisonReportExecutionOutcomeFactory.cancelled(
                plan: planned
            )
        else {
            return XCTFail("Expected cancellation before publication")
        }
        XCTAssertTrue(before.completedOutputs.isEmpty)

        guard
            case .cancelled(let during) = ComparisonReportExecutionOutcomeFactory.cancelled(
                plan: planned,
                completedDispositions: [.created, .created]
            )
        else {
            return XCTFail("Expected cancellation during publication")
        }
        XCTAssertEqual(
            during.completedOutputs.map(\.identity),
            planned.outputs.prefix(2).map(\.destination.outputIdentity)
        )

        assertInvalidPlanOutcome(
            ComparisonReportExecutionOutcomeFactory.cancelled(
                plan: planned,
                completedDispositions: [.created, .created, .created]
            )
        )
        assertInvalidPlanOutcome(
            ComparisonReportExecutionOutcomeFactory.cancelled(
                plan: planned,
                completedDispositions: [.replaced]
            )
        )
    }

    func testOutcomeFactoryAllowsFinalCancellationOnlyWhileRequestedOpenIsPending() throws {
        let planned = try multiOutputPlan(
            overwritePolicy: .failIfExists,
            openAfterGeneration: true
        )
        guard
            case .cancelled(let cancellation) =
                ComparisonReportExecutionOutcomeFactory.cancelled(
                    plan: planned,
                    completedDispositions: [.created, .created, .created]
                )
        else {
            return XCTFail("Expected final cancellation before open")
        }
        XCTAssertEqual(cancellation.completedOutputs.count, planned.outputs.count)

        let primaryIdentity = try fileIdentity(planned.primaryOutput)
        for openOutcome in [
            ComparisonReportOpenOutcome.opened(primaryIdentity),
            .failed(primaryIdentity)
        ] {
            guard
                case .completed(let result) =
                    ComparisonReportExecutionOutcomeFactory.completed(
                        plan: planned,
                        dispositions: [.created, .created, .created],
                        openOutcome: openOutcome
                    )
            else {
                return XCTFail("Expected valid open completion")
            }
            XCTAssertEqual(result.openOutcome, openOutcome)
        }

        assertInvalidPlanOutcome(
            ComparisonReportExecutionOutcomeFactory.completed(
                plan: planned,
                dispositions: [.created, .created, .created],
                openOutcome: .notRequested
            )
        )
        let linkedIdentity = try fileIdentity(planned.outputs[1])
        assertInvalidPlanOutcome(
            ComparisonReportExecutionOutcomeFactory.completed(
                plan: planned,
                dispositions: [.created, .created, .created],
                openOutcome: .opened(linkedIdentity)
            )
        )
    }

    func testPublicationUncertaintyOutcomeFactoryIdentifiesOnlyCurrentOutput() throws {
        let planned = try multiOutputPlan(overwritePolicy: .failIfExists)
        guard
            case .publicationUncertain(let uncertainty) =
                ComparisonReportExecutionOutcomeFactory.publicationUncertain(
                    plan: planned,
                    uncertainOutputIndices: [1],
                    completedDispositions: [.created]
                )
        else {
            return XCTFail("Expected publication uncertainty")
        }
        XCTAssertEqual(
            uncertainty.outputIdentities,
            [planned.outputs[1].destination.outputIdentity]
        )
        XCTAssertEqual(
            uncertainty.completedOutputs.map(\.identity),
            [planned.outputs[0].destination.outputIdentity]
        )

        let invalidOutcomes = [
            ComparisonReportExecutionOutcomeFactory.publicationUncertain(
                plan: planned,
                uncertainOutputIndices: []
            ),
            ComparisonReportExecutionOutcomeFactory.publicationUncertain(
                plan: planned,
                uncertainOutputIndices: [0, 1]
            ),
            ComparisonReportExecutionOutcomeFactory.publicationUncertain(
                plan: planned,
                uncertainOutputIndices: [2],
                completedDispositions: [.created]
            ),
            ComparisonReportExecutionOutcomeFactory.publicationUncertain(
                plan: planned,
                uncertainOutputIndices: [3]
            ),
            ComparisonReportExecutionOutcomeFactory.publicationUncertain(
                plan: planned,
                uncertainOutputIndices: [1],
                completedDispositions: [.replaced]
            )
        ]
        for outcome in invalidOutcomes {
            assertInvalidPlanOutcome(outcome)
        }
    }

    private func makeFileReport() -> ComparisonReport {
        ComparisonReport(
            title: "File Report",
            columns: ["Path", "Value"],
            rows: [
                ComparisonReportRow(values: ["z.txt", "z"], sortKey: "z"),
                ComparisonReportRow(values: ["a.txt", "a"], sortKey: "a"),
                ComparisonReportRow(values: ["m.txt", "m"], sortKey: "m")
            ],
            summary: ComparisonReportSummary(items: [
                ComparisonReportSummaryItem(label: "Zulu", value: "9"),
                ComparisonReportSummaryItem(label: "Alpha", value: "1")
            ])
        )
    }

    private func makeFileSnapshot(
        identity: ComparisonReportWorkflowSnapshotIdentity? = nil,
        generation: UInt64 = 7,
        report: ComparisonReport? = nil,
        selectedRowIndices: Set<Int> = []
    ) -> ComparisonReportWorkflowSnapshot {
        ComparisonReportWorkflowSnapshot(
            identity: identity ?? snapshotIdentity(),
            generation: generation,
            source: .file(
                ComparisonReportFileSnapshot(
                    report: report ?? makeFileReport(),
                    selectedRowIndices: selectedRowIndices
                )
            )
        )
    }

    private func makeDirectoryResults(selectedIndices: Set<Int> = []) -> DirectoryResults {
        let results = [
            DirectoryResult(
                left: DirectoryEntryMetadata(
                    relativePath: "zeta.txt",
                    kind: .file,
                    byteCount: 20
                ),
                right: DirectoryEntryMetadata(
                    relativePath: "zeta.txt",
                    kind: .file,
                    byteCount: 21
                ),
                status: .different
            ),
            DirectoryResult(
                left: DirectoryEntryMetadata(
                    relativePath: "alpha.txt",
                    kind: .file,
                    byteCount: 10
                ),
                right: nil,
                status: .leftOnly
            )
        ]
        return DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/tmp/macmerge-left", isDirectory: true),
            rightRoot: URL(fileURLWithPath: "/tmp/macmerge-right", isDirectory: true),
            results: results,
            selectedIDs: Set(selectedIndices.map { results[$0].id })
        )
    }

    private func makeFolderSnapshot(
        identity: ComparisonReportWorkflowSnapshotIdentity? = nil,
        generation: UInt64 = 7,
        rootIdentity: ComparisonReportWorkflowDirectoryRootIdentity? = nil,
        results: DirectoryResults
    ) -> ComparisonReportWorkflowSnapshot {
        ComparisonReportWorkflowSnapshot(
            identity: identity ?? snapshotIdentity(),
            generation: generation,
            source: .folder(
                ComparisonReportFolderSnapshot(
                    rootIdentity: rootIdentity ?? self.rootIdentity(),
                    results: results
                )
            )
        )
    }

    private func rootIdentity(seed: UInt64 = 1) -> ComparisonReportWorkflowDirectoryRootIdentity {
        ComparisonReportWorkflowDirectoryRootIdentity(
            left: .init(deviceID: seed, fileID: seed + 1, generation: UInt32(seed + 2)),
            right: .init(deviceID: seed + 3, fileID: seed + 4, generation: UInt32(seed + 5))
        )
    }

    private func snapshotIdentity() -> ComparisonReportWorkflowSnapshotIdentity {
        ComparisonReportWorkflowSnapshotIdentity(
            rawValue: UUID(uuidString: "37D9752D-64B2-4DD7-B8B1-B25DD8686948")!
        )
    }

    private func folderResults(
        from snapshot: ComparisonReportWorkflowSnapshot
    ) -> [DirectoryResult] {
        folderResultsContainer(from: snapshot).results
    }

    private func folderResultsContainer(
        from snapshot: ComparisonReportWorkflowSnapshot
    ) -> DirectoryResults {
        guard case .folder(let folder) = snapshot.source else {
            preconditionFailure("Expected folder snapshot")
        }
        return folder.results
    }

    private func makeLink(
        identifier: String,
        path: String,
        snapshot: ComparisonReportWorkflowSnapshotReference,
        directoryResultID: DirectoryResult.ID? = nil
    ) -> ComparisonReportLinkedReport {
        ComparisonReportLinkedReport(
            identifier: identifier,
            relativeOutputPath: path,
            report: ComparisonReport(
                title: "Linked \(identifier)",
                columns: ["Value"],
                rows: [ComparisonReportRow(values: [identifier])]
            ),
            snapshot: snapshot,
            directoryResultID: directoryResultID
        )
    }

    private func request(
        snapshot: ComparisonReportWorkflowSnapshot,
        scope: ComparisonReportScope = .all,
        format: ComparisonReportFormat = .plainText,
        destination: ComparisonReportOutputDestination = .clipboard,
        links: [ComparisonReportLinkedReport] = [],
        openAfterGeneration: Bool = false,
        limits: ComparisonReportWorkflowLimits = .default
    ) -> ComparisonReportWorkflowRequest {
        ComparisonReportWorkflowRequest(
            snapshot: snapshot,
            scope: scope,
            format: format,
            destination: destination,
            linkedReports: links,
            openAfterGeneration: openAfterGeneration,
            limits: limits
        )
    }

    private func plan(
        snapshot: ComparisonReportWorkflowSnapshot,
        scope: ComparisonReportScope = .all,
        format: ComparisonReportFormat = .plainText,
        destination: ComparisonReportOutputDestination = .clipboard,
        links: [ComparisonReportLinkedReport] = [],
        openAfterGeneration: Bool = false,
        limits: ComparisonReportWorkflowLimits = .default
    ) throws -> ComparisonReportWorkflowPlan {
        try ComparisonReportWorkflowPlanner.plan(
            request(
                snapshot: snapshot,
                scope: scope,
                format: format,
                destination: destination,
                links: links,
                openAfterGeneration: openAfterGeneration,
                limits: limits
            )
        )
    }

    private func fileDestination(
        _ path: String,
        overwritePolicy: ComparisonReportOverwritePolicy = .failIfExists,
        sandboxAccess: ComparisonReportSandboxAccess = .ambient
    ) -> ComparisonReportOutputDestination {
        fileDestination(
            URL(fileURLWithPath: path),
            overwritePolicy: overwritePolicy,
            sandboxAccess: sandboxAccess
        )
    }

    private func fileDestination(
        _ url: URL,
        overwritePolicy: ComparisonReportOverwritePolicy = .failIfExists,
        sandboxAccess: ComparisonReportSandboxAccess = .ambient
    ) -> ComparisonReportOutputDestination {
        .file(
            ComparisonReportFileDestination(
                url: url,
                overwritePolicy: overwritePolicy,
                sandboxAccess: sandboxAccess
            )
        )
    }

    private func componentURL(
        scheme: String,
        user: String? = nil,
        host: String,
        path: String,
        query: String? = nil,
        fragment: String? = nil
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.user = user
        components.host = host
        components.path = path
        components.query = query
        components.fragment = fragment
        guard let url = components.url else { preconditionFailure("Invalid test URL") }
        return url
    }

    private func limits(
        maximumReportCount: Int = ComparisonReportWorkflowLimits.default.maximumReportCount,
        maximumRowCount: Int = ComparisonReportWorkflowLimits.default.maximumRowCount,
        maximumItemCount: Int = ComparisonReportWorkflowLimits.default.maximumItemCount,
        maximumInputUTF8Bytes: Int = ComparisonReportWorkflowLimits.default.maximumInputUTF8Bytes,
        maximumOutputBytes: Int = ComparisonReportWorkflowLimits.default.maximumOutputBytes,
        maximumOutputBytesPerReport: Int = ComparisonReportWorkflowLimits.default
            .maximumOutputBytesPerReport,
        maximumWorkUnits: Int = ComparisonReportWorkflowLimits.default.maximumWorkUnits,
        maximumPathUTF8Bytes: Int = ComparisonReportWorkflowLimits.default.maximumPathUTF8Bytes,
        maximumTotalPathUTF8Bytes: Int = ComparisonReportWorkflowLimits.default
            .maximumTotalPathUTF8Bytes,
        maximumIdentifierUTF8Bytes: Int = ComparisonReportWorkflowLimits.default
            .maximumIdentifierUTF8Bytes,
        cancellationCheckInterval: Int = ComparisonReportWorkflowLimits.default
            .cancellationCheckInterval
    ) -> ComparisonReportWorkflowLimits {
        ComparisonReportWorkflowLimits(
            maximumReportCount: maximumReportCount,
            maximumRowCount: maximumRowCount,
            maximumItemCount: maximumItemCount,
            maximumInputUTF8Bytes: maximumInputUTF8Bytes,
            maximumOutputBytes: maximumOutputBytes,
            maximumOutputBytesPerReport: maximumOutputBytesPerReport,
            maximumWorkUnits: maximumWorkUnits,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: maximumTotalPathUTF8Bytes,
            maximumIdentifierUTF8Bytes: maximumIdentifierUTF8Bytes,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func multiOutputPlan(
        overwritePolicy: ComparisonReportOverwritePolicy,
        openAfterGeneration: Bool = false
    ) throws -> ComparisonReportWorkflowPlan {
        let snapshot = makeFileSnapshot()
        let reference = ComparisonReportWorkflowSnapshotReference(snapshot)
        return try plan(
            snapshot: snapshot,
            destination: fileDestination(
                "/tmp/macmerge-workflow/report.txt",
                overwritePolicy: overwritePolicy
            ),
            links: [
                makeLink(identifier: "second", path: "b.txt", snapshot: reference),
                makeLink(identifier: "first", path: "a.txt", snapshot: reference)
            ],
            openAfterGeneration: openAfterGeneration
        )
    }

    private func fileIdentity(
        _ output: ComparisonReportPlannedOutput
    ) throws -> ComparisonReportCanonicalOutputIdentity {
        guard case .file(_, let identity, _, _) = output.destination else {
            throw TestError.expectedFileDestination
        }
        return identity
    }

    private func assertWorkflowError<T>(
        _ expected: ComparisonReportWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ComparisonReportWorkflowError, expected, file: file, line: line)
        }
    }

    private func assertSecurityScopeCoverageError<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case .securityScopeDoesNotCoverOutput = error as? ComparisonReportWorkflowError
            else {
                return XCTFail("Expected security-scope coverage error, got \(error)", file: file, line: line)
            }
        }
    }

    private func assertOutputIdentityError<T>(
        isOverlap: Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard let workflowError = error as? ComparisonReportWorkflowError else {
                return XCTFail("Expected workflow error, got \(error)", file: file, line: line)
            }
            switch (isOverlap, workflowError) {
            case (false, .duplicateOutputIdentity), (true, .overlappingOutputIdentities):
                break
            default:
                XCTFail("Unexpected output identity error: \(workflowError)", file: file, line: line)
            }
        }
    }

    private func assertInvalidPlanOutcome(
        _ outcome: ComparisonReportExecutionOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failed(let failure) = outcome else {
            return XCTFail("Expected invalid-plan failure, got \(outcome)", file: file, line: line)
        }
        XCTAssertEqual(failure.code, .invalidPlan, file: file, line: line)
        XCTAssertNil(failure.outputIdentity, file: file, line: line)
        XCTAssertTrue(failure.completedOutputs.isEmpty, file: file, line: line)
    }

    private func parseCSV(_ input: String) throws -> [[String]] {
        let scalars = Array(input.unicodeScalars)
        var records: [[String]] = []
        var fields: [String] = []
        var field = ""
        var index = 0
        var isQuoted = false

        while index < scalars.count {
            let scalar = scalars[index]
            if isQuoted {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                    } else {
                        isQuoted = false
                        index += 1
                    }
                } else {
                    field.append(contentsOf: String(scalar))
                    index += 1
                }
            } else {
                switch scalar {
                case "\"" where field.isEmpty:
                    isQuoted = true
                    index += 1
                case ",":
                    fields.append(field)
                    field = ""
                    index += 1
                case "\r":
                    guard index + 1 < scalars.count, scalars[index + 1] == "\n" else {
                        throw TestError.invalidCSV
                    }
                    fields.append(field)
                    records.append(fields)
                    fields = []
                    field = ""
                    index += 2
                case "\n":
                    throw TestError.invalidCSV
                default:
                    field.append(contentsOf: String(scalar))
                    index += 1
                }
            }
        }

        guard !isQuoted, fields.isEmpty, field.isEmpty else { throw TestError.invalidCSV }
        return records
    }

    private enum TestError: Error {
        case expectedFileDestination
        case invalidCSV
    }

    private final class SortRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func record() {
            lock.lock()
            storage += 1
            lock.unlock()
        }
    }
}

private final class DirectPathURL: NSURL, @unchecked Sendable {
    private let directPath: String

    override var path: String? { directPath }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init?(
        pasteboardPropertyList propertyList: Any,
        ofType type: NSPasteboard.PasteboardType
    ) {
        fatalError("init(pasteboardPropertyList:ofType:) has not been implemented")
    }

    init?(path: String) {
        directPath = path
        super.init(string: URL(fileURLWithPath: path).absoluteString, relativeTo: nil)
    }
}

extension Sequence {
    fileprivate func sum(_ keyPath: KeyPath<Element, Int>) -> Int {
        reduce(0) { $0 + $1[keyPath: keyPath] }
    }
}
