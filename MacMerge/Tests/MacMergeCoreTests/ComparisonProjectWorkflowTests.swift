import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class ComparisonProjectWorkflowTests: XCTestCase {
    func testCanonicalIdentitiesAndRevisionsAreValidatedBeforePersistenceParsing() throws {
        let projectURL = URL(filePath: "/projects/sample.macmerge")
        let validData = try macMergeData(at: projectURL)
        let validRevision = revision(for: validData, at: projectURL)

        XCTAssertEqual(validRevision.identity.canonicalURL, projectURL)
        XCTAssertEqual(validRevision.identity.parent.canonicalURL, projectURL.deletingLastPathComponent())
        XCTAssertEqual(validRevision.byteCount, UInt64(validData.count))
        XCTAssertEqual(validRevision.contentSHA256, sha256(validData))
        XCTAssertEqual(validRevision.contentSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(validRevision.metadataSHA256.count, SHA256.Digest.byteCount)

        let malformedData = Data("{".utf8)
        let invalidRevisionError = ComparisonProjectWorkflowError.invalidFileRevision(projectURL.path)
        for malformed in [
            revision(
                for: malformedData,
                at: projectURL,
                byteCount: UInt64(ComparisonProject.maximumFileSize + 1)
            ),
            revision(for: malformedData, at: projectURL, linkCount: 0),
            revision(for: malformedData, at: projectURL, permissions: 0o10_000),
            revision(for: malformedData, at: projectURL, modificationTimeNanoseconds: -1),
            revision(
                for: malformedData,
                at: projectURL,
                modificationTimeNanoseconds: 1_000_000_000
            ),
            revision(for: malformedData, at: projectURL, statusChangeTimeNanoseconds: -1),
            revision(
                for: malformedData,
                at: projectURL,
                statusChangeTimeNanoseconds: 1_000_000_000
            ),
            revision(for: malformedData, at: projectURL, contentSHA256: [0]),
            revision(for: malformedData, at: projectURL, metadataSHA256: [0])
        ] {
            assertWorkflowError(invalidRevisionError) {
                try ComparisonProjectWorkflowPlanner.planOpen(
                    openRequest(data: malformedData, revision: malformed)
                )
            }
        }

        let wrongParent = canonicalDirectory(at: URL(filePath: "/other"), seed: 90)
        let parentMismatch = revision(for: malformedData, at: projectURL, parent: wrongParent)
        assertWorkflowError(.invalidURL(role: .canonicalParent, issue: .parentMismatch)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(data: malformedData, revision: parentMismatch)
            )
        }

        let noncanonicalURL = URL(filePath: "/projects/../projects/sample.macmerge")
        let noncanonical = revision(for: malformedData, at: noncanonicalURL)
        assertWorkflowError(.invalidURL(role: .canonicalProject, issue: .notCanonical)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: malformedData,
                    revision: noncanonical,
                    requestedURL: projectURL
                )
            )
        }

        let remoteRequestedURL = try XCTUnwrap(URL(string: "https://example.com/sample.macmerge"))
        assertWorkflowError(.invalidURL(role: .requestedProject, issue: .notFileURL)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: malformedData,
                    revision: revision(for: malformedData, at: projectURL),
                    requestedURL: remoteRequestedURL
                )
            )
        }

        assertWorkflowError(
            .snapshotByteCountMismatch(
                expected: UInt64(malformedData.count + 1),
                actual: malformedData.count
            )
        ) {
            let malformed = revision(
                for: malformedData,
                at: projectURL,
                byteCount: UInt64(malformedData.count + 1)
            )
            return try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(data: malformedData, revision: malformed)
            )
        }

        assertWorkflowError(.snapshotDigestMismatch) {
            let malformed = revision(
                for: malformedData,
                at: projectURL,
                contentSHA256: Array(repeating: 0xA5, count: SHA256.Digest.byteCount)
            )
            return try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(data: malformedData, revision: malformed)
            )
        }
    }

    func testMacMergeOpenPlanUsesCanonicalSourceAndPublishesCompleteProject() throws {
        let projectURL = URL(filePath: "/projects/folder.macmerge")
        let filterURL = URL(filePath: "/projects/filters/source.filter")
        let persisted = try ComparisonProject(
            mode: .folder,
            sides: [
                try .init(identity: .right, path: URL(filePath: "/trees/right"), readOnly: true),
                try .init(identity: .left, path: URL(filePath: "/trees/left")),
                try .init(identity: .middle, path: URL(filePath: "/trees/base"))
            ],
            recursive: true,
            filter: .file(filterURL),
            lineDiffOptions: LineDiffOptions(
                algorithm: .histogram,
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: false,
                ignoreBlankLines: true,
                ignoreComments: false,
                ignoreLineEndings: false,
                indentHeuristic: true,
                detectMovedBlocks: false,
                lineFiltersEnabled: false,
                lineFilters: [.init(pattern: "^generated:", caseSensitive: false)],
                substitutionsEnabled: true,
                substitutions: [.init(pattern: "[0-9]+", replacement: "#", caseSensitive: false)]
            )
        )
        let data = try persisted.encodedData(relativeTo: projectURL)
        let sourceRevision = revision(for: data, at: projectURL)
        let customLimits = limits(
            maximumProjectFileBytes: 3 * 1_024 * 1_024,
            maximumPathUTF8Bytes: 12 * 1_024,
            maximumTotalPathUTF8Bytes: 128 * 1_024,
            maximumOptionItemCount: 1_024,
            maximumOptionStringUTF8Bytes: 32 * 1_024,
            maximumTotalOptionStringUTF8Bytes: 512 * 1_024,
            maximumPlanBytes: 8 * 1_024 * 1_024,
            maximumWorkUnits: 32 * 1_024 * 1_024
        )

        let plan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: data,
                revision: sourceRevision,
                access: .ambient,
                replacementPolicy: .discardChangesAndReplace,
                limits: customLimits
            )
        )

        XCTAssertEqual(plan.format, .macMerge)
        XCTAssertEqual(plan.requestedURL, projectURL)
        XCTAssertEqual(plan.sourceRevision, sourceRevision)
        XCTAssertEqual(plan.project.mode, .folder)
        XCTAssertEqual(plan.project.sides.map(\.identity), [.left, .middle, .right])
        XCTAssertEqual(plan.project.sides.map(\.readOnly), [false, false, true])
        XCTAssertTrue(plan.project.recursive)
        XCTAssertEqual(plan.project.filter, .file(filterURL))
        XCTAssertEqual(
            plan.project.lineOptions,
            ComparisonProjectWorkflowLineOptions(
                algorithm: .histogram,
                whitespace: .ignoreChanges,
                ignoreCase: true,
                ignoreNumbers: false,
                ignoreBlankLines: true,
                ignoreComments: false,
                ignoreLineEndings: false,
                indentHeuristic: true,
                detectMovedBlocks: false,
                lineFiltersEnabled: false,
                lineFilters: [.init(pattern: "^generated:", caseSensitive: false)],
                substitutionsEnabled: true,
                substitutions: [
                    .init(pattern: "[0-9]+", replacement: "#", caseSensitive: false)
                ]
            )
        )
        XCTAssertEqual(plan.canonicalProjectData, data)
        XCTAssertEqual(plan.replacementPolicy, .discardChangesAndReplace)
        XCTAssertEqual(plan.limits, customLimits)
        XCTAssertEqual(plan.workspaceReplacement, .noWorkspace)
        XCTAssertNil(plan.expectedWorkspaceCAS)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(plan.receipt.kind, .open)
        XCTAssertEqual(plan.receipt.projectContentSHA256, sha256(plan.canonicalProjectData))
        XCTAssertEqual(plan.receipt.payloadByteCount, plan.canonicalProjectData.count)

        XCTAssertEqual(
            plan.authorityRequirements,
            [
                .init(
                    purpose: .readProjectFile,
                    requestedURL: projectURL,
                    canonicalURL: projectURL,
                    requiredCoverage: .exactFile,
                    access: .ambient
                ),
                .init(
                    purpose: .readComparisonSource(.left),
                    requestedURL: URL(filePath: "/trees/left"),
                    requiredCoverage: .directoryTree,
                    access: .callerManagedWhenRequired
                ),
                .init(
                    purpose: .readComparisonSource(.middle),
                    requestedURL: URL(filePath: "/trees/base"),
                    requiredCoverage: .directoryTree,
                    access: .callerManagedWhenRequired
                ),
                .init(
                    purpose: .readComparisonSource(.right),
                    requestedURL: URL(filePath: "/trees/right"),
                    requiredCoverage: .directoryTree,
                    access: .callerManagedWhenRequired
                ),
                .init(
                    purpose: .readProjectFilter,
                    requestedURL: filterURL,
                    requiredCoverage: .exactFile,
                    access: .callerManagedWhenRequired
                )
            ]
        )

        guard
            case .open(let routed) = try ComparisonProjectWorkflowPlanner.plan(
                .open(
                    openRequest(
                        data: data,
                        revision: sourceRevision,
                        access: .ambient,
                        replacementPolicy: .discardChangesAndReplace,
                        limits: customLimits
                    )
                )
            )
        else {
            return XCTFail("Expected routed open plan")
        }
        XCTAssertEqual(routed, plan)
    }

    func testMacMergeSavePlanProducesCompletePayloadAndCreateReceipt() throws {
        let destinationURL = URL(filePath: "/projects/new.macmerge")
        let workflowLineOptions = ComparisonProjectWorkflowLineOptions(
            algorithm: .minimal,
            whitespace: .ignoreAll,
            ignoreCase: true,
            ignoreNumbers: false,
            ignoreBlankLines: true,
            ignoreComments: false,
            ignoreLineEndings: false,
            indentHeuristic: true,
            detectMovedBlocks: false,
            lineFiltersEnabled: false,
            lineFilters: [.init(pattern: "^metadata$", caseSensitive: false)],
            substitutionsEnabled: true,
            substitutions: [.init(pattern: "old", replacement: "new", caseSensitive: true)]
        )
        let project = workflowProject(
            mode: .folder,
            sides: [
                .init(identity: .right, fileURL: URL(filePath: "/inputs/right"), readOnly: true),
                .init(identity: .left, fileURL: URL(filePath: "/inputs/left")),
                .init(identity: .middle, fileURL: URL(filePath: "/inputs/base"), readOnly: true)
            ],
            recursive: true,
            filter: .named("Images"),
            lineOptions: workflowLineOptions
        )
        let snapshot = workflowSnapshot(project: project, generation: 41, isDirty: true)
        let customLimits = limits(maximumWorkUnits: 63 * 1_024 * 1_024)
        let request = saveRequest(
            snapshot: snapshot,
            destinationURL: destinationURL,
            dirtyPolicy: .requireModified,
            limits: customLimits
        )

        let plan = try ComparisonProjectWorkflowPlanner.planSave(request)

        XCTAssertEqual(plan.snapshotReference, ComparisonProjectWorkflowSnapshotReference(snapshot))
        XCTAssertEqual(plan.snapshotCAS.reference, plan.snapshotReference)
        XCTAssertEqual(plan.snapshotCAS.stateSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(plan.format, .macMerge)
        XCTAssertEqual(plan.destination, request.destination)
        XCTAssertEqual(plan.dirtyPolicy, .requireModified)
        XCTAssertEqual(plan.limits, customLimits)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(plan.receipt.kind, .create)
        XCTAssertEqual(plan.receipt.payloadByteCount, plan.payload.count)
        XCTAssertEqual(plan.receipt.projectContentSHA256, sha256(plan.payload))
        XCTAssertGreaterThan(plan.receipt.estimatedWorkUnits, 0)
        XCTAssertEqual(
            plan.authorityRequirements,
            [
                .init(
                    purpose: .createProjectFile,
                    requestedURL: destinationURL,
                    canonicalURL: destinationURL,
                    requiredCoverage: .exactFile,
                    access: .callerManagedWhenRequired
                )
            ]
        )

        let decoded = try JSONDecoder().decode(ComparisonProject.self, from: plan.payload)
        let expectedPayload = try ComparisonProject(
            mode: .folder,
            sides: [
                try .init(identity: .left, path: URL(filePath: "/inputs/left")),
                try .init(
                    identity: .middle,
                    path: URL(filePath: "/inputs/base"),
                    readOnly: true
                ),
                try .init(
                    identity: .right,
                    path: URL(filePath: "/inputs/right"),
                    readOnly: true
                )
            ],
            recursive: true,
            filter: .named("Images"),
            lineDiffOptions: LineDiffOptions(
                algorithm: .minimal,
                whitespace: .ignoreAll,
                ignoreCase: true,
                ignoreNumbers: false,
                ignoreBlankLines: true,
                ignoreComments: false,
                ignoreLineEndings: false,
                indentHeuristic: true,
                detectMovedBlocks: false,
                lineFiltersEnabled: false,
                lineFilters: [.init(pattern: "^metadata$", caseSensitive: false)],
                substitutionsEnabled: true,
                substitutions: [
                    .init(pattern: "old", replacement: "new", caseSensitive: true)
                ]
            )
        )
        XCTAssertEqual(decoded, expectedPayload)

        guard case .save(let routed) = try ComparisonProjectWorkflowPlanner.plan(.save(request)) else {
            return XCTFail("Expected routed save plan")
        }
        XCTAssertEqual(routed, plan)
    }

    func testWorkflowNativeSideValidationRejectsMalformedSideSets() throws {
        let destinationURL = URL(filePath: "/projects/sides.macmerge")
        let cases: [(ComparisonProjectWorkflowProject, ComparisonProjectWorkflowError)] = [
            (
                workflowProject(
                    sides: [
                        .init(identity: .left, fileURL: URL(filePath: "/inputs/left"))
                    ]
                ),
                .invalidSideCount(1)
            ),
            (
                workflowProject(
                    sides: [
                        .init(identity: .left, fileURL: URL(filePath: "/inputs/left")),
                        .init(identity: .left, fileURL: URL(filePath: "/inputs/other"))
                    ]
                ),
                .duplicateSide(.left)
            ),
            (
                workflowProject(
                    sides: [
                        .init(identity: .left, fileURL: URL(filePath: "/inputs/left")),
                        .init(identity: .middle, fileURL: URL(filePath: "/inputs/base"))
                    ]
                ),
                .invalidSideSet([.left, .middle])
            )
        ]

        for (project, expected) in cases {
            assertWorkflowError(expected) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(
                        snapshot: workflowSnapshot(project: project, isDirty: true),
                        destinationURL: destinationURL
                    )
                )
            }
        }
    }

    func testWinMergeOpenAndReplaceSavePreserveRelativeSpellingAndSerializedPresence() throws {
        let projectURL = URL(filePath: "/workspace/projects/sample.WinMerge")
        let persisted = try WinMergeProjectFile(
            leftPath: "../inputs/./left & one.txt",
            middlePath: "../inputs/base.txt",
            rightPath: "../inputs/right.txt",
            filter: "*.swift f:generated/**",
            includesSubfolders: false,
            leftReadOnly: true,
            middleReadOnly: false,
            rightReadOnly: true,
            options: .init(
                windowType: .text,
                whitespaceHandling: .ignoreChanges,
                ignoreBlankLines: false,
                ignoreCase: true,
                ignoreCarriageReturnDifferences: false,
                ignoreNumbers: true,
                ignoreCommentDifferences: true,
                compareMethod: .fullContents
            )
        )
        let data = try persisted.serializedData()
        let sourceRevision = revision(for: data, at: projectURL)
        let openPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(data: data, revision: sourceRevision, format: .winMerge)
        )

        XCTAssertEqual(openPlan.project.mode, .text)
        XCTAssertFalse(openPlan.project.recursive)
        XCTAssertEqual(openPlan.project.sides.map(\.identity), [.left, .middle, .right])
        XCTAssertEqual(
            openPlan.project.sides.map(\.winMergeRelativePath),
            ["../inputs/./left & one.txt", "../inputs/base.txt", "../inputs/right.txt"]
        )
        XCTAssertEqual(
            openPlan.project.sides[0].fileURL,
            URL(filePath: "/workspace/inputs/left & one.txt")
        )
        XCTAssertEqual(openPlan.project.filter, .winMergeExpression("*.swift f:generated/**"))
        XCTAssertEqual(openPlan.project.lineOptions.whitespace, .ignoreChanges)
        XCTAssertTrue(openPlan.project.lineOptions.ignoreCase)
        XCTAssertFalse(openPlan.project.lineOptions.ignoreLineEndings)
        XCTAssertTrue(openPlan.project.winMergeOptions.preservesSerializedOptionPresence)
        XCTAssertEqual(
            openPlan.project.winMergeOptions,
            ComparisonProjectWorkflowWinMergeOptions(
                preservesSerializedOptionPresence: true,
                windowTypeRawValue: 1,
                includesSubfolders: false,
                whitespaceHandlingRawValue: 1,
                ignoreBlankLines: false,
                ignoreCase: true,
                ignoreCarriageReturnDifferences: false,
                ignoreNumbers: true,
                ignoreCodepageDifferences: nil,
                ignoreCommentDifferences: true,
                ignoreMissingTrailingEndOfLine: nil,
                ignoreLineBreaks: nil,
                compareMethodRawValue: 0
            )
        )

        let snapshot = workflowSnapshot(
            project: openPlan.project,
            generation: 8,
            binding: .file(sourceRevision),
            isDirty: true
        )
        let savePlan = try ComparisonProjectWorkflowPlanner.planSave(
            saveRequest(
                snapshot: snapshot,
                destinationURL: projectURL,
                format: .winMerge,
                intention: .replaceExisting(sourceRevision)
            )
        )
        let roundTrip = try WinMergeProjectFile.parse(savePlan.payload)

        XCTAssertEqual(savePlan.receipt.kind, .replace)
        XCTAssertEqual(roundTrip, persisted)
        XCTAssertEqual(savePlan.payload, data)
        XCTAssertEqual(roundTrip.leftPath, "../inputs/./left & one.txt")
        XCTAssertEqual(roundTrip.includesSubfolders, false)
        XCTAssertEqual(roundTrip.options.windowType, .text)
        XCTAssertEqual(savePlan.authorityRequirements[0].purpose, .replaceProjectFile)
    }

    func testWinMergeSubfoldersZeroSelectsFolderOnlyWithoutExplicitWindowType() throws {
        let projectURL = URL(filePath: "/projects/subfolders.WinMerge")
        let folderData = try WinMergeProjectFile(
            leftPath: "left",
            rightPath: "right",
            includesSubfolders: false
        ).serializedData()
        let folderPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: folderData,
                revision: revision(for: folderData, at: projectURL),
                format: .winMerge
            )
        )

        XCTAssertEqual(folderPlan.project.mode, .folder)
        XCTAssertFalse(folderPlan.project.recursive)
        XCTAssertEqual(
            folderPlan.authorityRequirements,
            expectedOpenAuthorities(
                projectURL: projectURL,
                sideURLs: [
                    (.left, URL(filePath: "/projects/left")),
                    (.right, URL(filePath: "/projects/right"))
                ],
                sideCoverage: .directoryTree
            )
        )

        let textData = try WinMergeProjectFile(
            leftPath: "left",
            rightPath: "right",
            includesSubfolders: false,
            options: .init(windowType: .text)
        ).serializedData()
        let textPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: textData,
                revision: revision(for: textData, at: projectURL),
                format: .winMerge
            )
        )

        XCTAssertEqual(textPlan.project.mode, .text)
        XCTAssertFalse(textPlan.project.recursive)
        XCTAssertEqual(
            textPlan.authorityRequirements,
            expectedOpenAuthorities(
                projectURL: projectURL,
                sideURLs: [
                    (.left, URL(filePath: "/projects/left")),
                    (.right, URL(filePath: "/projects/right"))
                ],
                sideCoverage: .exactFile
            )
        )

        let automaticData = try WinMergeProjectFile(
            leftPath: "left",
            rightPath: "right"
        ).serializedData()
        let automaticPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: automaticData,
                revision: revision(for: automaticData, at: projectURL),
                format: .winMerge
            )
        )
        XCTAssertEqual(automaticPlan.project.mode, .automatic)
        XCTAssertFalse(automaticPlan.project.recursive)
        XCTAssertEqual(
            automaticPlan.authorityRequirements,
            expectedOpenAuthorities(
                projectURL: projectURL,
                sideURLs: [
                    (.left, URL(filePath: "/projects/left")),
                    (.right, URL(filePath: "/projects/right"))
                ],
                sideCoverage: .directoryTree
            )
        )
    }

    func testCrossFormatFiltersAndWinMergeOptionSemanticsFailClosed() throws {
        let destinationURL = URL(filePath: "/projects/project.WinMerge")
        for filter in [
            ComparisonProjectWorkflowFilter.named("Source"),
            .file(URL(filePath: "/filters/source.filter"))
        ] {
            let snapshot = workflowSnapshot(project: workflowProject(filter: filter), isDirty: true)
            assertWorkflowError(.formatCannotRepresentProject(.winMerge)) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(snapshot: snapshot, destinationURL: destinationURL, format: .winMerge)
                )
            }
        }

        let expressionSnapshot = workflowSnapshot(
            project: workflowProject(filter: .winMergeExpression("*.swift")),
            isDirty: true
        )
        assertWorkflowError(.formatCannotRepresentProject(.macMerge)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: expressionSnapshot,
                    destinationURL: URL(filePath: "/projects/project.macmerge")
                )
            )
        }

        let malformedNamedFilter = workflowSnapshot(
            project: workflowProject(filter: .named(" \n")),
            isDirty: true
        )
        assertWorkflowError(.macMergeProject(.invalidFilterReference)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: malformedNamedFilter,
                    destinationURL: URL(filePath: "/projects/project.macmerge")
                )
            )
        }

        let unsupportedLineOptions: [ComparisonProjectWorkflowLineOptions] = [
            .init(algorithm: .patience),
            .init(indentHeuristic: true),
            .init(detectMovedBlocks: true),
            .init(lineFiltersEnabled: false),
            .init(lineFilters: [.init(pattern: "^skip$")]),
            .init(substitutionsEnabled: false),
            .init(substitutions: [.init(pattern: "old", replacement: "new")])
        ]
        for lineOptions in unsupportedLineOptions {
            assertWorkflowError(.formatCannotRepresentProject(.winMerge)) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(
                        snapshot: workflowSnapshot(
                            project: workflowProject(lineOptions: lineOptions),
                            isDirty: true
                        ),
                        destinationURL: destinationURL,
                        format: .winMerge
                    )
                )
            }
        }

        let recursiveNonfolder = workflowSnapshot(
            project: workflowProject(mode: .text, recursive: true),
            isDirty: true
        )
        assertWorkflowError(.formatCannotRepresentProject(.winMerge)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: recursiveNonfolder,
                    destinationURL: destinationURL,
                    format: .winMerge
                )
            )
        }

        for options in [
            WinMergeProjectFile.Options(compareMethod: .quickContents),
            .init(ignoreCodepageDifferences: true),
            .init(ignoreMissingTrailingEndOfLine: true),
            .init(ignoreLineBreaks: true)
        ] {
            let data = try WinMergeProjectFile(
                leftPath: "/left",
                rightPath: "/right",
                options: options
            ).serializedData()
            let request = openRequest(
                data: data,
                revision: revision(for: data, at: destinationURL),
                format: .winMerge
            )
            XCTAssertThrowsError(try ComparisonProjectWorkflowPlanner.planOpen(request)) { error in
                switch options.compareMethod {
                case .quickContents:
                    XCTAssertEqual(
                        error as? ComparisonProjectWorkflowError,
                        .unsupportedWinMergeCompareMethod(1)
                    )
                default:
                    XCTAssertEqual(
                        error as? ComparisonProjectWorkflowError,
                        .unsupportedWinMergeTextSemantics
                    )
                }
            }
        }
    }

    func testForgedUnsafeWinMergeOptionsFailClosedOnSave() throws {
        let destinationURL = URL(filePath: "/projects/unsafe.WinMerge")
        let unsafeFlags: [ComparisonProjectWorkflowWinMergeOptions] = [
            .init(ignoreCodepageDifferences: true),
            .init(ignoreMissingTrailingEndOfLine: true),
            .init(ignoreLineBreaks: true)
        ]
        for unsafe in unsafeFlags {
            let snapshot = workflowSnapshot(
                project: workflowProject(winMergeOptions: unsafe),
                isDirty: true
            )
            assertWorkflowError(.unsupportedWinMergeTextSemantics) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(
                        snapshot: snapshot,
                        destinationURL: destinationURL,
                        format: .winMerge
                    )
                )
            }
            assertWorkflowError(.formatCannotRepresentProject(.macMerge)) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(
                        snapshot: snapshot,
                        destinationURL: URL(filePath: "/projects/unsafe.macmerge")
                    )
                )
            }
        }

        for rawValue in [1, 999] {
            let snapshot = workflowSnapshot(
                project: workflowProject(
                    winMergeOptions: .init(compareMethodRawValue: rawValue)
                ),
                isDirty: true
            )
            assertWorkflowError(.unsupportedWinMergeCompareMethod(rawValue)) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(
                        snapshot: snapshot,
                        destinationURL: destinationURL,
                        format: .winMerge
                    )
                )
            }
            assertWorkflowError(.formatCannotRepresentProject(.macMerge)) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(
                        snapshot: snapshot,
                        destinationURL: URL(filePath: "/projects/unsafe.macmerge")
                    )
                )
            }
        }
    }

    func testWinMergeOpenRejectsWindowsUNCEnvironmentURIAndTildePaths() throws {
        let projectURL = URL(filePath: "/projects/foreign.WinMerge")
        let unsupported = [
            "C:\\Users\\person\\left.txt",
            "\\\\server\\share\\left.txt",
            "//server/share/left.txt",
            "$HOME/left.txt",
            "${HOME}/left.txt",
            "%USERPROFILE%/left.txt",
            "file:///tmp/left.txt",
            "https://example.com/left.txt",
            "C:/Users/person/left.txt",
            "/C:/Users/person/left.txt",
            "~/left.txt"
        ]

        for path in unsupported {
            let data = try WinMergeProjectFile(leftPath: path, rightPath: "/right").serializedData()
            assertWorkflowError(.unsupportedWinMergePath(path)) {
                try ComparisonProjectWorkflowPlanner.planOpen(
                    openRequest(
                        data: data,
                        revision: revision(for: data, at: projectURL),
                        format: .winMerge
                    )
                )
            }
        }
    }

    func testURLValidationReportsExactRoleAndIssue() throws {
        let projectURL = URL(filePath: "/projects/url-matrix.macmerge")
        let data = try macMergeData(at: projectURL)
        let sourceRevision = revision(for: data, at: projectURL)
        let relativeURL = URL(
            fileURLWithPath: "url-matrix.macmerge",
            relativeTo: URL(fileURLWithPath: "/projects", isDirectory: true)
        )
        let requestedCases: [(URL, ComparisonProjectWorkflowURLIssue)] = [
            (try XCTUnwrap(URL(string: "https://example.com/project.macmerge")), .notFileURL),
            (relativeURL, .relativeURL),
            (try XCTUnwrap(URL(string: "file://server/projects/project.macmerge")), .remoteHost),
            (try XCTUnwrap(URL(string: "file://user@/projects/project.macmerge")), .credentialsOrPort),
            (try XCTUnwrap(URL(string: "file:///projects/project.macmerge?query=1")), .queryOrFragment),
            (URL(fileURLWithPath: "/projects/folder", isDirectory: true), .directoryURL),
            (URL(fileURLWithPath: "/", isDirectory: false), .missingFileName)
        ]
        for (url, issue) in requestedCases {
            assertWorkflowError(.invalidURL(role: .requestedProject, issue: issue)) {
                try ComparisonProjectWorkflowPlanner.planOpen(
                    openRequest(
                        data: data,
                        revision: sourceRevision,
                        requestedURL: url
                    )
                )
            }
        }
        let overlongRequestedURL = URL(filePath: "/projects/123456789.macmerge")
        assertWorkflowError(.invalidURL(role: .requestedProject, issue: .pathTooLong)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: sourceRevision,
                    requestedURL: overlongRequestedURL,
                    limits: limits(maximumPathUTF8Bytes: 8)
                )
            )
        }

        let noncanonicalProjectURL = URL(filePath: "/projects/../projects/url-matrix.macmerge")
        assertWorkflowError(.invalidURL(role: .canonicalProject, issue: .notCanonical)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: revision(for: data, at: noncanonicalProjectURL),
                    requestedURL: projectURL
                )
            )
        }
        let remoteCanonicalURL = try XCTUnwrap(
            URL(string: "file://server/projects/url-matrix.macmerge")
        )
        assertWorkflowError(.invalidURL(role: .canonicalProject, issue: .remoteHost)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: revision(for: data, at: remoteCanonicalURL),
                    requestedURL: projectURL
                )
            )
        }

        let noncanonicalParent = canonicalDirectory(
            at: URL(filePath: "/projects/../projects"),
            seed: 72
        )
        assertWorkflowError(.invalidURL(role: .canonicalParent, issue: .notCanonical)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: revision(for: data, at: projectURL, parent: noncanonicalParent)
                )
            )
        }

        let invalidLeft = workflowProject(
            sides: [
                .init(
                    identity: .left,
                    fileURL: try XCTUnwrap(URL(string: "https://example.com/left"))
                ),
                .init(identity: .right, fileURL: URL(filePath: "/inputs/right"))
            ]
        )
        assertWorkflowError(.invalidURL(role: .comparisonSide(.left), issue: .notFileURL)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: invalidLeft, isDirty: true),
                    destinationURL: projectURL
                )
            )
        }
        let invalidMiddle = workflowProject(
            sides: [
                .init(identity: .left, fileURL: URL(filePath: "/inputs/left")),
                .init(
                    identity: .middle,
                    fileURL: try XCTUnwrap(URL(string: "file:///inputs/base#fragment"))
                ),
                .init(identity: .right, fileURL: URL(filePath: "/inputs/right"))
            ]
        )
        assertWorkflowError(.invalidURL(role: .comparisonSide(.middle), issue: .queryOrFragment)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: invalidMiddle, isDirty: true),
                    destinationURL: projectURL
                )
            )
        }
        let invalidRight = workflowProject(
            sides: [
                .init(identity: .left, fileURL: URL(filePath: "/inputs/left")),
                .init(
                    identity: .right,
                    fileURL: try XCTUnwrap(URL(string: "file://server/inputs/right"))
                )
            ]
        )
        assertWorkflowError(.invalidURL(role: .comparisonSide(.right), issue: .remoteHost)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: invalidRight, isDirty: true),
                    destinationURL: projectURL
                )
            )
        }

        let invalidFilter = workflowProject(
            filter: .file(try XCTUnwrap(URL(string: "https://example.com/filter")))
        )
        assertWorkflowError(.invalidURL(role: .filter, issue: .notFileURL)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: invalidFilter, isDirty: true),
                    destinationURL: projectURL
                )
            )
        }

        let invalidScope = ComparisonProjectWorkflowAccess.securityScoped(
            resourceURL: try XCTUnwrap(URL(string: "https://example.com/scope")),
            coverage: .directoryTree
        )
        assertWorkflowError(.invalidURL(role: .securityScope, issue: .notFileURL)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: sourceRevision,
                    access: invalidScope
                )
            )
        }
    }

    func testRequestedURLAliasesRequireExactFileOrLocationAttestation() throws {
        let canonicalURL = URL(filePath: "/projects/canonical.macmerge")
        let aliasURL = URL(filePath: "/aliases/project.macmerge")
        let data = try macMergeData(at: canonicalURL)
        let sourceRevision = revision(for: data, at: canonicalURL)

        assertWorkflowError(.invalidURL(role: .requestedProject, issue: .unattestedAlias)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(data: data, revision: sourceRevision, requestedURL: aliasURL)
            )
        }

        let attestation = ComparisonProjectWorkflowRequestedURLAttestation.file(
            requestedURL: aliasURL,
            identity: sourceRevision.identity
        )
        let openPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: data,
                revision: sourceRevision,
                requestedURL: aliasURL,
                requestedURLAttestation: attestation
            )
        )
        XCTAssertEqual(openPlan.requestedURL, aliasURL)
        XCTAssertEqual(openPlan.sourceRevision.identity.canonicalURL, canonicalURL)

        let location = canonicalLocation(at: canonicalURL, seed: 200)
        let wrongKind = ComparisonProjectWorkflowRequestedURLAttestation.location(
            requestedURL: aliasURL,
            location: location
        )
        assertWorkflowError(.invalidURL(role: .requestedProject, issue: .unattestedAlias)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: sourceRevision,
                    requestedURL: aliasURL,
                    requestedURLAttestation: wrongKind
                )
            )
        }

        let forgedFileAttestations: [ComparisonProjectWorkflowRequestedURLAttestation] = [
            .file(
                requestedURL: URL(filePath: "/aliases/other.macmerge"),
                identity: sourceRevision.identity
            ),
            .file(
                requestedURL: aliasURL,
                identity: revision(
                    for: data,
                    at: canonicalURL,
                    parent: sourceRevision.identity.parent,
                    fileSeed: 99,
                    metadataSHA256: sourceRevision.metadataSHA256
                ).identity
            ),
            .file(
                requestedURL: aliasURL,
                identity: revision(
                    for: data,
                    at: canonicalURL,
                    parent: canonicalDirectory(
                        at: canonicalURL.deletingLastPathComponent(),
                        seed: 404
                    )
                ).identity
            )
        ]
        for forged in forgedFileAttestations {
            assertWorkflowError(.invalidURL(role: .requestedProject, issue: .unattestedAlias)) {
                try ComparisonProjectWorkflowPlanner.planOpen(
                    openRequest(
                        data: data,
                        revision: sourceRevision,
                        requestedURL: aliasURL,
                        requestedURLAttestation: forged
                    )
                )
            }
        }

        let samePathWrongIdentity = ComparisonProjectWorkflowRequestedURLAttestation.file(
            requestedURL: canonicalURL,
            identity: revision(
                for: data,
                at: canonicalURL,
                parent: sourceRevision.identity.parent,
                fileSeed: 100,
                metadataSHA256: sourceRevision.metadataSHA256
            ).identity
        )
        assertWorkflowError(.invalidURL(role: .requestedProject, issue: .unattestedAlias)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: sourceRevision,
                    requestedURLAttestation: samePathWrongIdentity
                )
            )
        }

        let snapshot = workflowSnapshot(project: workflowProject(), isDirty: true)
        let createDestination = ComparisonProjectSaveDestination(
            requestedURL: aliasURL,
            intention: .createNew(location),
            requestedURLAttestation: .location(requestedURL: aliasURL, location: location)
        )
        XCTAssertNoThrow(
            try ComparisonProjectWorkflowPlanner.planSave(
                ComparisonProjectSaveRequest(
                    snapshot: snapshot,
                    format: .macMerge,
                    destination: createDestination
                )
            )
        )

        let forgedLocationAttestations: [ComparisonProjectWorkflowRequestedURLAttestation] = [
            .location(
                requestedURL: URL(filePath: "/aliases/other.macmerge"),
                location: location
            ),
            .location(
                requestedURL: aliasURL,
                location: canonicalLocation(at: canonicalURL, seed: 201)
            ),
            .file(requestedURL: aliasURL, identity: sourceRevision.identity)
        ]
        for forged in forgedLocationAttestations {
            let destination = ComparisonProjectSaveDestination(
                requestedURL: aliasURL,
                intention: .createNew(location),
                requestedURLAttestation: forged
            )
            assertWorkflowError(.invalidURL(role: .requestedProject, issue: .unattestedAlias)) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    .init(snapshot: snapshot, format: .macMerge, destination: destination)
                )
            }
        }

        let samePathWrongKind = ComparisonProjectSaveDestination(
            requestedURL: canonicalURL,
            intention: .createNew(location),
            requestedURLAttestation: .file(
                requestedURL: canonicalURL,
                identity: sourceRevision.identity
            )
        )
        assertWorkflowError(.invalidURL(role: .requestedProject, issue: .unattestedAlias)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                .init(snapshot: snapshot, format: .macMerge, destination: samePathWrongKind)
            )
        }

        let unattestedDestination = ComparisonProjectSaveDestination(
            requestedURL: aliasURL,
            intention: .createNew(location)
        )
        assertWorkflowError(.invalidURL(role: .requestedProject, issue: .unattestedAlias)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                ComparisonProjectSaveRequest(
                    snapshot: snapshot,
                    format: .macMerge,
                    destination: unattestedDestination
                )
            )
        }
    }

    func testSecurityScopedAuthorityMustCoverRequestedOrCanonicalDestination() throws {
        let canonicalURL = URL(filePath: "/projects/secure.macmerge")
        let aliasURL = URL(filePath: "/aliases/secure.macmerge")
        let data = try macMergeData(at: canonicalURL)
        let sourceRevision = revision(for: data, at: canonicalURL)
        let attestation = ComparisonProjectWorkflowRequestedURLAttestation.file(
            requestedURL: aliasURL,
            identity: sourceRevision.identity
        )

        let exactCanonical = ComparisonProjectWorkflowAccess.securityScoped(
            resourceURL: canonicalURL,
            coverage: .exactFile
        )
        let openPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: data,
                revision: sourceRevision,
                requestedURL: aliasURL,
                requestedURLAttestation: attestation,
                access: exactCanonical
            )
        )
        XCTAssertEqual(openPlan.authorityRequirements[0].access, exactCanonical)

        let exactAlias = ComparisonProjectWorkflowAccess.securityScoped(
            resourceURL: aliasURL,
            coverage: .exactFile
        )
        let aliasScopedPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: data,
                revision: sourceRevision,
                requestedURL: aliasURL,
                requestedURLAttestation: attestation,
                access: exactAlias
            )
        )
        XCTAssertEqual(aliasScopedPlan.authorityRequirements[0].access, exactAlias)

        let unrelated = ComparisonProjectWorkflowAccess.securityScoped(
            resourceURL: URL(filePath: "/other/project.macmerge"),
            coverage: .exactFile
        )
        assertWorkflowError(.invalidURL(role: .securityScope, issue: .insufficientAuthorityCoverage)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: sourceRevision,
                    requestedURL: aliasURL,
                    requestedURLAttestation: attestation,
                    access: unrelated
                )
            )
        }

        let snapshot = workflowSnapshot(project: workflowProject(), isDirty: true)
        let parentScope = ComparisonProjectWorkflowAccess.securityScoped(
            resourceURL: canonicalURL.deletingLastPathComponent(),
            coverage: .directoryTree
        )
        let destination = ComparisonProjectSaveDestination(
            requestedURL: canonicalURL,
            intention: .createNew(canonicalLocation(at: canonicalURL)),
            access: parentScope
        )
        let savePlan = try ComparisonProjectWorkflowPlanner.planSave(
            .init(snapshot: snapshot, format: .macMerge, destination: destination)
        )
        XCTAssertEqual(savePlan.authorityRequirements[0].requiredCoverage, .exactFile)
        XCTAssertEqual(savePlan.authorityRequirements[0].access, parentScope)

        let insufficientDestination = ComparisonProjectSaveDestination(
            requestedURL: canonicalURL,
            intention: .createNew(canonicalLocation(at: canonicalURL)),
            access: .securityScoped(
                resourceURL: URL(filePath: "/other"),
                coverage: .directoryTree
            )
        )
        assertWorkflowError(.invalidURL(role: .securityScope, issue: .insufficientAuthorityCoverage)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                .init(snapshot: snapshot, format: .macMerge, destination: insufficientDestination)
            )
        }

        let siblingURL = URL(filePath: "/projects-evil/secure.macmerge")
        let siblingData = try macMergeData(at: siblingURL)
        let siblingRevision = revision(for: siblingData, at: siblingURL)
        let prefixScope = ComparisonProjectWorkflowAccess.securityScoped(
            resourceURL: URL(filePath: "/projects"),
            coverage: .directoryTree
        )
        assertWorkflowError(.invalidURL(role: .securityScope, issue: .insufficientAuthorityCoverage)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: siblingData,
                    revision: siblingRevision,
                    access: prefixScope
                )
            )
        }
    }

    func testSaveDestinationIntentionAndBoundReplacementRevisionMustAgree() throws {
        let destinationURL = URL(filePath: "/projects/bound.macmerge")
        let oldData = Data("old project bytes".utf8)
        let boundRevision = revision(for: oldData, at: destinationURL, fileSeed: 31)
        let snapshot = workflowSnapshot(
            project: workflowProject(),
            binding: .file(boundRevision),
            isDirty: true
        )

        XCTAssertNoThrow(
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: snapshot,
                    destinationURL: destinationURL,
                    intention: .replaceExisting(boundRevision)
                )
            )
        )

        for staleRevision in revisionComponentMutations(
            of: boundRevision,
            includeCanonicalURL: false
        ) {
            assertWorkflowError(.replacementDoesNotMatchBinding) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(
                        snapshot: snapshot,
                        destinationURL: destinationURL,
                        intention: .replaceExisting(staleRevision)
                    )
                )
            }
        }

        let unrelatedURL = URL(filePath: "/exports/unrelated.macmerge")
        let unrelatedData = Data("unrelated bytes".utf8)
        let unrelatedRevision = revision(for: unrelatedData, at: unrelatedURL, fileSeed: 80)
        XCTAssertNoThrow(
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: snapshot,
                    destinationURL: unrelatedURL,
                    intention: .replaceExisting(unrelatedRevision)
                )
            )
        )

        let wrongParent = canonicalDirectory(at: URL(filePath: "/other"), seed: 99)
        let malformedLocation = ComparisonProjectWorkflowCanonicalLocation(
            canonicalURL: destinationURL,
            parent: wrongParent
        )
        assertWorkflowError(.destinationDoesNotMatchIntention) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: workflowProject(), isDirty: true),
                    destinationURL: destinationURL,
                    intention: .createNew(malformedLocation)
                )
            )
        }
    }

    func testSaveSnapshotCASAndPublicationRejectStaleOwnerOrDestinationState() throws {
        let destinationURL = URL(filePath: "/projects/create.macmerge")
        let snapshot = workflowSnapshot(project: workflowProject(), generation: 17, isDirty: true)
        let createPlan = try ComparisonProjectWorkflowPlanner.planSave(
            saveRequest(snapshot: snapshot, destinationURL: destinationURL)
        )

        XCTAssertNoThrow(try createPlan.validateCurrentSnapshot(snapshot))
        XCTAssertNoThrow(
            try createPlan.validateForPublication(
                currentSnapshot: snapshot,
                currentDestinationRevision: nil
            )
        )

        let changedWithoutGeneration = workflowSnapshot(
            identity: snapshot.identity,
            project: workflowProject(
                sides: [
                    .init(identity: .left, fileURL: URL(filePath: "/inputs/changed-left")),
                    .init(identity: .right, fileURL: URL(filePath: "/inputs/right"))
                ]
            ),
            generation: snapshot.generation,
            isDirty: snapshot.isDirty
        )
        assertWorkflowError(.workspaceContentsChanged) {
            try createPlan.validateForPublication(
                currentSnapshot: changedWithoutGeneration,
                currentDestinationRevision: nil
            )
        }

        let advanced = workflowSnapshot(
            identity: snapshot.identity,
            project: snapshot.project,
            generation: snapshot.generation + 1,
            isDirty: snapshot.isDirty
        )
        assertWorkflowError(
            .staleWorkspace(
                expected: createPlan.snapshotReference,
                actual: ComparisonProjectWorkflowSnapshotReference(advanced)
            )
        ) {
            try createPlan.validateForPublication(
                currentSnapshot: advanced,
                currentDestinationRevision: nil
            )
        }

        let boundData = Data("bound bytes".utf8)
        let boundRevision = revision(for: boundData, at: destinationURL, fileSeed: 73)
        let sameReferenceMutations = [
            workflowSnapshot(
                identity: snapshot.identity,
                project: workflowProject(mode: .binary),
                generation: snapshot.generation,
                isDirty: snapshot.isDirty
            ),
            workflowSnapshot(
                identity: snapshot.identity,
                project: workflowProject(filter: .named("Changed")),
                generation: snapshot.generation,
                isDirty: snapshot.isDirty
            ),
            workflowSnapshot(
                identity: snapshot.identity,
                project: workflowProject(lineOptions: .init(ignoreCase: true)),
                generation: snapshot.generation,
                isDirty: snapshot.isDirty
            ),
            workflowSnapshot(
                identity: snapshot.identity,
                project: workflowProject(
                    winMergeOptions: .init(preservesSerializedOptionPresence: true)
                ),
                generation: snapshot.generation,
                isDirty: snapshot.isDirty
            ),
            workflowSnapshot(
                identity: snapshot.identity,
                project: snapshot.project,
                generation: snapshot.generation,
                binding: .file(boundRevision),
                isDirty: snapshot.isDirty
            ),
            workflowSnapshot(
                identity: snapshot.identity,
                project: snapshot.project,
                generation: snapshot.generation,
                isDirty: false
            )
        ]
        for mutation in sameReferenceMutations {
            assertWorkflowError(.workspaceContentsChanged) {
                try createPlan.validateForPublication(
                    currentSnapshot: mutation,
                    currentDestinationRevision: nil
                )
            }
        }

        let unexpectedDestination = revision(
            for: Data("occupied".utf8),
            at: destinationURL,
            fileSeed: 71
        )
        assertWorkflowError(.destinationChanged) {
            try createPlan.validateForPublication(
                currentSnapshot: snapshot,
                currentDestinationRevision: unexpectedDestination
            )
        }

        let replacementSnapshot = workflowSnapshot(
            project: workflowProject(),
            generation: 18,
            binding: .file(unexpectedDestination),
            isDirty: true
        )
        let replacePlan = try ComparisonProjectWorkflowPlanner.planSave(
            saveRequest(
                snapshot: replacementSnapshot,
                destinationURL: destinationURL,
                intention: .replaceExisting(unexpectedDestination)
            )
        )
        XCTAssertNoThrow(
            try replacePlan.validateForPublication(
                currentSnapshot: replacementSnapshot,
                currentDestinationRevision: unexpectedDestination
            )
        )
        assertWorkflowError(.destinationChanged) {
            try replacePlan.validateForPublication(
                currentSnapshot: replacementSnapshot,
                currentDestinationRevision: nil
            )
        }
        for changedDestination in revisionComponentMutations(of: unexpectedDestination) {
            assertWorkflowError(.destinationChanged) {
                try replacePlan.validateForPublication(
                    currentSnapshot: replacementSnapshot,
                    currentDestinationRevision: changedDestination
                )
            }
        }
    }

    func testOpenPublicationRevalidatesSourceAndWorkspaceCAS() throws {
        let projectURL = URL(filePath: "/projects/open.macmerge")
        let data = try macMergeData(at: projectURL)
        let sourceRevision = revision(for: data, at: projectURL)
        let workspace = workflowSnapshot(project: workflowProject(), generation: 5, isDirty: false)
        let plan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: data,
                revision: sourceRevision,
                currentWorkspace: workspace,
                replacementPolicy: .replaceIfClean
            )
        )

        XCTAssertEqual(
            plan.workspaceReplacement,
            .replacedClean(ComparisonProjectWorkflowSnapshotReference(workspace))
        )
        XCTAssertEqual(plan.expectedWorkspaceCAS?.reference, ComparisonProjectWorkflowSnapshotReference(workspace))
        XCTAssertNoThrow(
            try plan.validateForPublication(
                currentSourceRevision: sourceRevision,
                currentWorkspace: workspace
            )
        )

        for changedSource in revisionComponentMutations(of: sourceRevision) {
            assertWorkflowError(.sourceChanged) {
                try plan.validateForPublication(
                    currentSourceRevision: changedSource,
                    currentWorkspace: workspace
                )
            }
        }

        let advancedWorkspace = workflowSnapshot(
            identity: workspace.identity,
            project: workspace.project,
            generation: workspace.generation + 1,
            isDirty: false
        )
        assertWorkflowError(
            .staleWorkspace(
                expected: ComparisonProjectWorkflowSnapshotReference(workspace),
                actual: ComparisonProjectWorkflowSnapshotReference(advancedWorkspace)
            )
        ) {
            try plan.validateForPublication(
                currentSourceRevision: sourceRevision,
                currentWorkspace: advancedWorkspace
            )
        }

        let changedWorkspace = workflowSnapshot(
            identity: workspace.identity,
            project: workflowProject(mode: .binary),
            generation: workspace.generation,
            isDirty: workspace.isDirty
        )
        assertWorkflowError(.workspaceContentsChanged) {
            try plan.validateForPublication(
                currentSourceRevision: sourceRevision,
                currentWorkspace: changedWorkspace
            )
        }
        assertWorkflowError(
            .staleWorkspace(
                expected: ComparisonProjectWorkflowSnapshotReference(workspace),
                actual: nil
            )
        ) {
            try plan.validateForPublication(
                currentSourceRevision: sourceRevision,
                currentWorkspace: nil
            )
        }

        let emptyPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(data: data, revision: sourceRevision)
        )
        assertWorkflowError(
            .staleWorkspace(
                expected: nil,
                actual: ComparisonProjectWorkflowSnapshotReference(workspace)
            )
        ) {
            try emptyPlan.validateForPublication(
                currentSourceRevision: sourceRevision,
                currentWorkspace: workspace
            )
        }
    }

    func testOpenReplacementPoliciesProtectCleanAndDirtyWorkspaceState() throws {
        let projectURL = URL(filePath: "/projects/replacement.macmerge")
        let data = try macMergeData(at: projectURL)
        let sourceRevision = revision(for: data, at: projectURL)
        let clean = workflowSnapshot(project: workflowProject(), generation: 1, isDirty: false)
        let dirty = workflowSnapshot(project: workflowProject(), generation: 2, isDirty: true)

        let emptyPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: data,
                revision: sourceRevision,
                replacementPolicy: .requireEmptyWorkspace
            )
        )
        XCTAssertEqual(emptyPlan.workspaceReplacement, .noWorkspace)

        assertWorkflowError(.workspaceAlreadyOpen) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: sourceRevision,
                    currentWorkspace: clean,
                    replacementPolicy: .requireEmptyWorkspace
                )
            )
        }

        let cleanPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: data,
                revision: sourceRevision,
                currentWorkspace: clean,
                replacementPolicy: .replaceIfClean
            )
        )
        XCTAssertEqual(
            cleanPlan.workspaceReplacement,
            .replacedClean(ComparisonProjectWorkflowSnapshotReference(clean))
        )

        assertWorkflowError(.dirtyWorkspaceRequiresReplacementApproval) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: data,
                    revision: sourceRevision,
                    currentWorkspace: dirty,
                    replacementPolicy: .replaceIfClean
                )
            )
        }

        let discardPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: data,
                revision: sourceRevision,
                currentWorkspace: dirty,
                replacementPolicy: .discardChangesAndReplace
            )
        )
        XCTAssertEqual(
            discardPlan.workspaceReplacement,
            .discardedChanges(ComparisonProjectWorkflowSnapshotReference(dirty))
        )

        let discardCleanPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(
                data: data,
                revision: sourceRevision,
                currentWorkspace: clean,
                replacementPolicy: .discardChangesAndReplace
            )
        )
        XCTAssertEqual(
            discardCleanPlan.workspaceReplacement,
            .replacedClean(ComparisonProjectWorkflowSnapshotReference(clean))
        )
    }

    func testDirtyPolicyLimitsAndRetainedPlanLimitsFailBeforeExecution() throws {
        let destinationURL = URL(filePath: "/projects/limits.macmerge")
        let cleanSnapshot = workflowSnapshot(project: workflowProject(), isDirty: false)
        assertWorkflowError(.projectMustBeModified) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: cleanSnapshot,
                    destinationURL: destinationURL,
                    dirtyPolicy: .requireModified
                )
            )
        }

        let invalidLimits: [(ComparisonProjectWorkflowLimit, ComparisonProjectWorkflowLimits)] = [
            (.projectFileBytes, limits(maximumProjectFileBytes: 0)),
            (.pathUTF8Bytes, limits(maximumPathUTF8Bytes: 0)),
            (.totalPathUTF8Bytes, limits(maximumTotalPathUTF8Bytes: 0)),
            (.optionItemCount, limits(maximumOptionItemCount: 0)),
            (.optionStringUTF8Bytes, limits(maximumOptionStringUTF8Bytes: 0)),
            (.totalOptionStringUTF8Bytes, limits(maximumTotalOptionStringUTF8Bytes: 0)),
            (.planBytes, limits(maximumPlanBytes: 0)),
            (.workUnits, limits(maximumWorkUnits: 0))
        ]
        for (limit, value) in invalidLimits {
            assertWorkflowError(.invalidLimit(limit)) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(
                        snapshot: workflowSnapshot(project: workflowProject(), isDirty: true),
                        destinationURL: destinationURL,
                        limits: value
                    )
                )
            }
        }

        let aboveHardLimits: [(ComparisonProjectWorkflowLimit, ComparisonProjectWorkflowLimits)] = [
            (
                .projectFileBytes,
                limits(
                    maximumProjectFileBytes:
                        ComparisonProjectWorkflowLimits.hardMaximumProjectFileBytes + 1
                )
            ),
            (
                .pathUTF8Bytes,
                limits(
                    maximumPathUTF8Bytes:
                        ComparisonProjectWorkflowLimits.hardMaximumPathUTF8Bytes + 1
                )
            ),
            (
                .totalPathUTF8Bytes,
                limits(
                    maximumTotalPathUTF8Bytes:
                        ComparisonProjectWorkflowLimits.hardMaximumTotalPathUTF8Bytes + 1
                )
            ),
            (
                .optionItemCount,
                limits(
                    maximumOptionItemCount:
                        ComparisonProjectWorkflowLimits.hardMaximumOptionItemCount + 1
                )
            ),
            (
                .optionStringUTF8Bytes,
                limits(
                    maximumOptionStringUTF8Bytes:
                        ComparisonProjectWorkflowLimits.hardMaximumOptionStringUTF8Bytes + 1
                )
            ),
            (
                .totalOptionStringUTF8Bytes,
                limits(
                    maximumTotalOptionStringUTF8Bytes:
                        ComparisonProjectWorkflowLimits.hardMaximumTotalOptionStringUTF8Bytes + 1
                )
            ),
            (
                .planBytes,
                limits(
                    maximumPlanBytes: ComparisonProjectWorkflowLimits.hardMaximumPlanBytes + 1
                )
            ),
            (
                .workUnits,
                limits(
                    maximumWorkUnits: ComparisonProjectWorkflowLimits.hardMaximumWorkUnits + 1
                )
            )
        ]
        let validOpenData = try macMergeData(at: destinationURL)
        let validOpenRevision = revision(for: validOpenData, at: destinationURL)
        for (limit, value) in aboveHardLimits {
            assertWorkflowError(.invalidLimit(limit)) {
                try ComparisonProjectWorkflowPlanner.planSave(
                    saveRequest(
                        snapshot: workflowSnapshot(project: workflowProject(), isDirty: true),
                        destinationURL: destinationURL,
                        limits: value
                    )
                )
            }
            assertWorkflowError(.invalidLimit(limit)) {
                try ComparisonProjectWorkflowPlanner.planOpen(
                    openRequest(
                        data: validOpenData,
                        revision: validOpenRevision,
                        limits: value
                    )
                )
            }
        }

        let tooManyOptions = workflowProject(
            lineOptions: .init(
                lineFilters: [.init(pattern: "a"), .init(pattern: "b")]
            )
        )
        assertWorkflowError(.optionLimitExceeded(.optionItemCount)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: tooManyOptions, isDirty: true),
                    destinationURL: destinationURL,
                    limits: limits(maximumOptionItemCount: 1)
                )
            )
        }

        let longOption = workflowProject(filter: .named("12345"))
        assertWorkflowError(.optionLimitExceeded(.optionStringUTF8Bytes)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: longOption, isDirty: true),
                    destinationURL: destinationURL,
                    limits: limits(maximumOptionStringUTF8Bytes: 4)
                )
            )
        }

        let totalOptions = workflowProject(
            lineOptions: .init(
                lineFilters: [.init(pattern: "abc")],
                substitutions: [.init(pattern: "d", replacement: "ef")]
            )
        )
        assertWorkflowError(.optionLimitExceeded(.totalOptionStringUTF8Bytes)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: totalOptions, isDirty: true),
                    destinationURL: destinationURL,
                    limits: limits(maximumTotalOptionStringUTF8Bytes: 5)
                )
            )
        }

        assertWorkflowError(.optionLimitExceeded(.totalPathUTF8Bytes)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: workflowProject(), isDirty: true),
                    destinationURL: destinationURL,
                    limits: limits(maximumTotalPathUTF8Bytes: 10)
                )
            )
        }

        let atomicRegexCountOverflow = workflowProject(
            lineOptions: .init(
                lineFilters: (0...256).map { .init(pattern: "p\($0)") }
            )
        )
        assertWorkflowError(.optionLimitExceeded(.optionItemCount)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: atomicRegexCountOverflow, isDirty: true),
                    destinationURL: destinationURL,
                    limits: limits(maximumOptionItemCount: 1_000)
                )
            )
        }

        let atomicRegexByteOverflow = workflowProject(
            lineOptions: .init(lineFilters: [.init(pattern: String(repeating: "x", count: 4_097))])
        )
        assertWorkflowError(.optionLimitExceeded(.optionStringUTF8Bytes)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: atomicRegexByteOverflow, isDirty: true),
                    destinationURL: destinationURL,
                    limits: limits(
                        maximumOptionStringUTF8Bytes: 8_192,
                        maximumTotalOptionStringUTF8Bytes: 8_192
                    )
                )
            )
        }

        let retainedSnapshot = workflowSnapshot(project: workflowProject(), isDirty: true)
        let unrestrictedSavePlan = try ComparisonProjectWorkflowPlanner.planSave(
            saveRequest(snapshot: retainedSnapshot, destinationURL: destinationURL)
        )
        let saveRetainedLimit = unrestrictedSavePlan.payload.count + 1
        assertWorkflowError(.planTooLarge(maximumBytes: saveRetainedLimit)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: retainedSnapshot,
                    destinationURL: destinationURL,
                    limits: limits(maximumPlanBytes: saveRetainedLimit)
                )
            )
        }

        let unrestrictedOpenPlan = try ComparisonProjectWorkflowPlanner.planOpen(
            openRequest(data: validOpenData, revision: validOpenRevision)
        )
        let openRetainedLimit = unrestrictedOpenPlan.canonicalProjectData.count + 1
        assertWorkflowError(.planTooLarge(maximumBytes: openRetainedLimit)) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: validOpenData,
                    revision: validOpenRevision,
                    limits: limits(maximumPlanBytes: openRetainedLimit)
                )
            )
        }

        assertWorkflowError(.projectFileTooLarge(maximumBytes: 128)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: workflowProject(), isDirty: true),
                    destinationURL: destinationURL,
                    limits: limits(maximumProjectFileBytes: 128)
                )
            )
        }

        assertWorkflowError(.workLimitExceeded(maximumUnits: 1)) {
            try ComparisonProjectWorkflowPlanner.planSave(
                saveRequest(
                    snapshot: workflowSnapshot(project: workflowProject(), isDirty: true),
                    destinationURL: destinationURL,
                    limits: limits(maximumWorkUnits: 1)
                )
            )
        }
    }

    func testPlanningReceiptsAreDeterministicAndBindPolicyAccessAndDestination() throws {
        let destinationURL = URL(filePath: "/projects/deterministic.macmerge")
        let snapshot = workflowSnapshot(project: workflowProject(), generation: 101, isDirty: true)
        let firstRequest = saveRequest(snapshot: snapshot, destinationURL: destinationURL)
        let first = try ComparisonProjectWorkflowPlanner.planSave(firstRequest)
        let second = try ComparisonProjectWorkflowPlanner.planSave(firstRequest)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.receipt.planSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(first.receipt.projectContentSHA256, sha256(first.payload))
        XCTAssertEqual(first.receipt.payloadByteCount, first.payload.count)
        XCTAssertLessThanOrEqual(first.receipt.estimatedWorkUnits, first.limits.maximumWorkUnits)

        let scopedDestination = ComparisonProjectSaveDestination(
            requestedURL: destinationURL,
            intention: .createNew(canonicalLocation(at: destinationURL)),
            access: .securityScoped(resourceURL: destinationURL, coverage: .exactFile)
        )
        let changedAccess = try ComparisonProjectWorkflowPlanner.planSave(
            .init(snapshot: snapshot, format: .macMerge, destination: scopedDestination)
        )
        XCTAssertEqual(changedAccess.payload, first.payload)
        XCTAssertEqual(
            changedAccess.receipt.projectContentSHA256,
            first.receipt.projectContentSHA256
        )
        XCTAssertNotEqual(changedAccess.receipt.planSHA256, first.receipt.planSHA256)

        let changedDestinationURL = URL(filePath: "/projects/other.macmerge")
        let changedDestination = try ComparisonProjectWorkflowPlanner.planSave(
            saveRequest(snapshot: snapshot, destinationURL: changedDestinationURL)
        )
        XCTAssertNotEqual(changedDestination.receipt.planSHA256, first.receipt.planSHA256)

        let changedPolicy = try ComparisonProjectWorkflowPlanner.planSave(
            saveRequest(
                snapshot: snapshot,
                destinationURL: destinationURL,
                dirtyPolicy: .requireModified
            )
        )
        let changedLimits = try ComparisonProjectWorkflowPlanner.planSave(
            saveRequest(
                snapshot: snapshot,
                destinationURL: destinationURL,
                limits: limits(maximumWorkUnits: 63 * 1_024 * 1_024)
            )
        )
        for changed in [changedAccess, changedDestination, changedPolicy, changedLimits] {
            XCTAssertEqual(changed.payload, first.payload)
            XCTAssertEqual(
                changed.receipt.projectContentSHA256,
                first.receipt.projectContentSHA256
            )
            XCTAssertNotEqual(changed.receipt.planSHA256, first.receipt.planSHA256)
        }

        let projectData = try macMergeData(at: destinationURL)
        let source = revision(for: projectData, at: destinationURL)
        let baselineOpenRequest = openRequest(data: projectData, revision: source)
        let firstOpen = try ComparisonProjectWorkflowPlanner.planOpen(baselineOpenRequest)
        let secondOpen = try ComparisonProjectWorkflowPlanner.planOpen(baselineOpenRequest)
        XCTAssertEqual(firstOpen, secondOpen)
        XCTAssertEqual(firstOpen.receipt, secondOpen.receipt)

        let cleanWorkspace = workflowSnapshot(
            project: workflowProject(),
            generation: 102,
            isDirty: false
        )
        let changedSourceMetadata = revisionCopy(
            source,
            metadataSHA256: Array(repeating: 0x6A, count: SHA256.Digest.byteCount)
        )
        let openVariants = try [
            ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(data: projectData, revision: changedSourceMetadata)
            ),
            ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: projectData,
                    revision: source,
                    requestedURLAttestation: .file(
                        requestedURL: destinationURL,
                        identity: source.identity
                    )
                )
            ),
            ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: projectData,
                    revision: source,
                    access: .ambient
                )
            ),
            ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: projectData,
                    revision: source,
                    currentWorkspace: cleanWorkspace,
                    replacementPolicy: .replaceIfClean
                )
            ),
            ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: projectData,
                    revision: source,
                    replacementPolicy: .discardChangesAndReplace
                )
            ),
            ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: projectData,
                    revision: source,
                    limits: limits(maximumWorkUnits: 63 * 1_024 * 1_024)
                )
            )
        ]
        for changed in openVariants {
            XCTAssertEqual(changed.canonicalProjectData, firstOpen.canonicalProjectData)
            XCTAssertEqual(
                changed.receipt.projectContentSHA256,
                firstOpen.receipt.projectContentSHA256
            )
            XCTAssertNotEqual(changed.receipt.planSHA256, firstOpen.receipt.planSHA256)
        }
        XCTAssertEqual(
            Set(openVariants.map { $0.receipt.planSHA256 }).count,
            openVariants.count
        )
    }

    func testCancellationAndExecutorContractsAreExplicit() async throws {
        let destinationURL = URL(filePath: "/projects/cancel.macmerge")
        let saveRequest = saveRequest(
            snapshot: workflowSnapshot(project: workflowProject(), isDirty: true),
            destinationURL: destinationURL
        )
        let saveTask = Task {
            withUnsafeCurrentTask { current in
                current?.cancel()
            }
            return try ComparisonProjectWorkflowPlanner.planSave(saveRequest)
        }

        do {
            _ = try await saveTask.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ComparisonProjectWorkflowError, .cancelled)
        }

        let openData = try macMergeData(at: destinationURL)
        let sourceRevision = revision(for: openData, at: destinationURL)
        let openRequest = openRequest(data: openData, revision: sourceRevision)
        let openTask = Task {
            withUnsafeCurrentTask { current in
                current?.cancel()
            }
            return try ComparisonProjectWorkflowPlanner.planOpen(openRequest)
        }
        do {
            _ = try await openTask.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ComparisonProjectWorkflowError, .cancelled)
        }

        let snapshot = saveRequest.snapshot
        let savePlan = try ComparisonProjectWorkflowPlanner.planSave(saveRequest)
        let openPlan = try ComparisonProjectWorkflowPlanner.planOpen(openRequest)
        let validationTasks: [Task<Void, Error>] = [
            Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try savePlan.validateCurrentSnapshot(snapshot)
            },
            Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try savePlan.validateForPublication(
                    currentSnapshot: snapshot,
                    currentDestinationRevision: nil
                )
            },
            Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try openPlan.validateCurrentSourceRevision(sourceRevision)
            },
            Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try openPlan.validateCurrentWorkspace(nil)
            },
            Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try openPlan.validateForPublication(
                    currentSourceRevision: sourceRevision,
                    currentWorkspace: nil
                )
            }
        ]
        for validationTask in validationTasks {
            do {
                try await validationTask.value
                XCTFail("Expected cancellation")
            } catch {
                XCTAssertEqual(error as? ComparisonProjectWorkflowError, .cancelled)
            }
        }

        let contract = ComparisonProjectWorkflowExecutorContract.required
        XCTAssertEqual(openPlan.executorContract, contract)
        XCTAssertEqual(savePlan.executorContract, contract)
        XCTAssertEqual(
            contract.pathResolution,
            .descriptorRelativeNoFollowFromPinnedCanonicalParent
        )
        XCTAssertEqual(
            contract.authority,
            .balancedAccessAroundValidationAndMaterialization
        )
        XCTAssertEqual(
            contract.opening,
            .revalidateSourceAndWorkspaceBeforeReplacingState
        )
        XCTAssertEqual(
            contract.saving,
            .privateStageExactBytesThenAtomicSnapshotAndDestinationCASPublishDurably
        )
        XCTAssertEqual(contract.metadata, .preserveAndVerifyCompleteMetadataWhenReplacing)
        XCTAssertEqual(contract.cancellation, .cancellationBeforeEffects)
    }

    func testMalformedMacMergeAndWinMergePersistenceReturnsTypedDiagnostics() throws {
        let macURL = URL(filePath: "/projects/malformed.macmerge")
        for data in [Data("{".utf8), Data("[]".utf8), Data([0xFF, 0xFE])] {
            assertWorkflowError(.invalidMacMergeProject) {
                try ComparisonProjectWorkflowPlanner.planOpen(
                    openRequest(data: data, revision: revision(for: data, at: macURL))
                )
            }
        }

        let unsupportedVersion = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "mode": "text",
            "sides": [
                ["identity": "left", "path": "/left", "readOnly": false],
                ["identity": "right", "path": "/right", "readOnly": false]
            ],
            "recursive": false,
            "lineDiffOptions": [:]
        ])
        assertWorkflowError(.macMergeProject(.unsupportedSchemaVersion(2))) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: unsupportedVersion,
                    revision: revision(for: unsupportedVersion, at: macURL)
                )
            )
        }

        let validObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try macMergeData(at: macURL))
                as? [String: Any]
        )
        var shallowIgnored = validObject
        shallowIgnored["ignored"] = ["safe": [1, 2, 3]]
        let shallowIgnoredData = try JSONSerialization.data(
            withJSONObject: shallowIgnored,
            options: [.sortedKeys]
        )
        XCTAssertNoThrow(
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: shallowIgnoredData,
                    revision: revision(for: shallowIgnoredData, at: macURL)
                )
            )
        )

        var deepIgnoredValue: Any = 0
        for _ in 0...64 {
            deepIgnoredValue = [deepIgnoredValue]
        }
        var deepIgnored = validObject
        deepIgnored["ignored"] = deepIgnoredValue
        let deepIgnoredData = try JSONSerialization.data(withJSONObject: deepIgnored)
        assertWorkflowError(.invalidMacMergeProject) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: deepIgnoredData,
                    revision: revision(for: deepIgnoredData, at: macURL)
                )
            )
        }

        var tokenHeavyIgnored = validObject
        tokenHeavyIgnored["ignored"] = Array(repeating: 0, count: 70_000)
        let tokenHeavyData = try JSONSerialization.data(withJSONObject: tokenHeavyIgnored)
        assertWorkflowError(.invalidMacMergeProject) {
            try ComparisonProjectWorkflowPlanner.planOpen(
                openRequest(
                    data: tokenHeavyData,
                    revision: revision(for: tokenHeavyData, at: macURL)
                )
            )
        }

        let winURL = URL(filePath: "/projects/malformed.WinMerge")
        let malformedWinMergeCases: [(Data, WinMergeProjectFileDiagnostic.Code)] = [
            (Data("<project><paths><left>/left</left>".utf8), .malformedXML),
            (
                Data("<!DOCTYPE project [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><project/>".utf8),
                .unsafeXMLConstruct
            ),
            (
                Data("<project><paths><left>/left</left><right>/right</right><unknown>x</unknown></paths></project>".utf8),
                .unsupportedElement
            ),
            (Data([0xFF, 0xFE]), .invalidUTF8)
        ]
        for (data, code) in malformedWinMergeCases {
            assertWinMergeDiagnostic(code) {
                try ComparisonProjectWorkflowPlanner.planOpen(
                    openRequest(
                        data: data,
                        revision: revision(for: data, at: winURL),
                        format: .winMerge
                    )
                )
            }
        }

        let exactWinMergeDiagnostics: [(Data, WinMergeProjectFileDiagnostic)] = [
            (
                Data("<?xml version=\"1.0\" encoding=\"UTF-16\"?><project/>".utf8),
                .init(code: .unsupportedEncoding)
            ),
            (
                Data("<project><paths><left>/left</left></paths></project>".utf8),
                .init(code: .invalidPathCount)
            ),
            (
                Data(
                    "<project><paths><left>/left</left><right>/right</right><subfolders>2</subfolders></paths></project>".utf8
                ),
                .init(code: .invalidValue, context: "subfolders")
            )
        ]
        for (data, diagnostic) in exactWinMergeDiagnostics {
            assertWorkflowError(.winMergeProject(diagnostic)) {
                try ComparisonProjectWorkflowPlanner.planOpen(
                    openRequest(
                        data: data,
                        revision: revision(for: data, at: winURL),
                        format: .winMerge
                    )
                )
            }
            XCTAssertEqual(
                ComparisonProjectWorkflowError.winMergeProject(diagnostic).errorDescription,
                diagnostic.localizedDescription
            )
        }
    }

    private func workflowProject(
        mode: ComparisonProjectWorkflowMode = .text,
        sides: [ComparisonProjectWorkflowSide] = [
            .init(identity: .left, fileURL: URL(filePath: "/inputs/left")),
            .init(identity: .right, fileURL: URL(filePath: "/inputs/right"))
        ],
        recursive: Bool = false,
        filter: ComparisonProjectWorkflowFilter? = nil,
        lineOptions: ComparisonProjectWorkflowLineOptions = .init(),
        winMergeOptions: ComparisonProjectWorkflowWinMergeOptions = .init()
    ) -> ComparisonProjectWorkflowProject {
        ComparisonProjectWorkflowProject(
            mode: mode,
            sides: sides,
            recursive: recursive,
            filter: filter,
            lineOptions: lineOptions,
            winMergeOptions: winMergeOptions
        )
    }

    private func workflowSnapshot(
        identity: ComparisonProjectWorkflowSnapshotIdentity = .init(
            rawValue: UUID(uuidString: "4C25F33A-EC89-4D90-95E6-A2B68B814515")!
        ),
        project: ComparisonProjectWorkflowProject,
        generation: UInt64 = 1,
        binding: ComparisonProjectWorkflowProjectBinding = .untitled,
        isDirty: Bool
    ) -> ComparisonProjectWorkflowSnapshot {
        ComparisonProjectWorkflowSnapshot(
            identity: identity,
            generation: generation,
            project: project,
            binding: binding,
            isDirty: isDirty
        )
    }

    private func openRequest(
        data: Data,
        revision: ComparisonProjectWorkflowFileRevision,
        requestedURL: URL? = nil,
        format: ComparisonProjectWorkflowFormat = .macMerge,
        requestedURLAttestation: ComparisonProjectWorkflowRequestedURLAttestation? = nil,
        access: ComparisonProjectWorkflowAccess = .callerManagedWhenRequired,
        currentWorkspace: ComparisonProjectWorkflowSnapshot? = nil,
        replacementPolicy: ComparisonProjectOpenReplacementPolicy = .replaceIfClean,
        limits: ComparisonProjectWorkflowLimits = .default
    ) -> ComparisonProjectOpenRequest {
        ComparisonProjectOpenRequest(
            requestedURL: requestedURL ?? revision.identity.canonicalURL,
            format: format,
            source: .init(revision: revision, data: data),
            requestedURLAttestation: requestedURLAttestation,
            access: access,
            currentWorkspace: currentWorkspace,
            replacementPolicy: replacementPolicy,
            limits: limits
        )
    }

    private func saveRequest(
        snapshot: ComparisonProjectWorkflowSnapshot,
        destinationURL: URL,
        format: ComparisonProjectWorkflowFormat = .macMerge,
        intention: ComparisonProjectSaveIntention? = nil,
        dirtyPolicy: ComparisonProjectSaveDirtyPolicy = .allowUnmodified,
        limits: ComparisonProjectWorkflowLimits = .default
    ) -> ComparisonProjectSaveRequest {
        let resolvedIntention = intention ?? .createNew(canonicalLocation(at: destinationURL))
        return ComparisonProjectSaveRequest(
            snapshot: snapshot,
            format: format,
            destination: ComparisonProjectSaveDestination(
                requestedURL: destinationURL,
                intention: resolvedIntention
            ),
            dirtyPolicy: dirtyPolicy,
            limits: limits
        )
    }

    private func canonicalLocation(
        at url: URL,
        seed: UInt64 = 1
    ) -> ComparisonProjectWorkflowCanonicalLocation {
        ComparisonProjectWorkflowCanonicalLocation(
            canonicalURL: url,
            parent: canonicalDirectory(at: url.deletingLastPathComponent(), seed: seed)
        )
    }

    private func canonicalDirectory(
        at url: URL,
        seed: UInt64
    ) -> ComparisonProjectWorkflowCanonicalDirectoryIdentity {
        ComparisonProjectWorkflowCanonicalDirectoryIdentity(
            canonicalURL: url,
            node: node(seed)
        )
    }

    private func node(_ seed: UInt64) -> ComparisonProjectWorkflowNodeIdentity {
        ComparisonProjectWorkflowNodeIdentity(
            deviceID: seed,
            fileID: seed &* 1_009 &+ 7,
            generation: UInt32(truncatingIfNeeded: seed &* 17)
        )
    }

    private func revision(
        for data: Data,
        at url: URL,
        parent: ComparisonProjectWorkflowCanonicalDirectoryIdentity? = nil,
        fileSeed: UInt64 = 2,
        byteCount: UInt64? = nil,
        linkCount: UInt64 = 1,
        permissions: UInt16 = 0o640,
        modificationTimeSeconds: Int64 = 1_700_000_000,
        modificationTimeNanoseconds: Int32 = 123_456_789,
        statusChangeTimeSeconds: Int64 = 1_700_000_001,
        statusChangeTimeNanoseconds: Int32 = 987_654_321,
        contentSHA256: [UInt8]? = nil,
        metadataSHA256: [UInt8]? = nil,
        ownerID: UInt32 = 501,
        groupID: UInt32 = 20,
        flags: UInt32 = 0
    ) -> ComparisonProjectWorkflowFileRevision {
        let identity = ComparisonProjectWorkflowCanonicalFileIdentity(
            canonicalURL: url,
            parent: parent
                ?? canonicalDirectory(
                    at: url.deletingLastPathComponent(),
                    seed: fileSeed &+ 100
                ),
            node: node(fileSeed)
        )
        return ComparisonProjectWorkflowFileRevision(
            identity: identity,
            byteCount: byteCount ?? UInt64(data.count),
            linkCount: linkCount,
            permissions: permissions,
            ownerID: ownerID,
            groupID: groupID,
            flags: flags,
            modificationTimeSeconds: modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds,
            contentSHA256: contentSHA256 ?? sha256(data),
            metadataSHA256: metadataSHA256 ?? sha256(Data("metadata-\(fileSeed)".utf8))
        )
    }

    private func revisionCopy(
        _ revision: ComparisonProjectWorkflowFileRevision,
        identity: ComparisonProjectWorkflowCanonicalFileIdentity? = nil,
        byteCount: UInt64? = nil,
        linkCount: UInt64? = nil,
        permissions: UInt16? = nil,
        ownerID: UInt32? = nil,
        groupID: UInt32? = nil,
        flags: UInt32? = nil,
        modificationTimeSeconds: Int64? = nil,
        modificationTimeNanoseconds: Int32? = nil,
        statusChangeTimeSeconds: Int64? = nil,
        statusChangeTimeNanoseconds: Int32? = nil,
        contentSHA256: [UInt8]? = nil,
        metadataSHA256: [UInt8]? = nil
    ) -> ComparisonProjectWorkflowFileRevision {
        ComparisonProjectWorkflowFileRevision(
            identity: identity ?? revision.identity,
            byteCount: byteCount ?? revision.byteCount,
            linkCount: linkCount ?? revision.linkCount,
            permissions: permissions ?? revision.permissions,
            ownerID: ownerID ?? revision.ownerID,
            groupID: groupID ?? revision.groupID,
            flags: flags ?? revision.flags,
            modificationTimeSeconds: modificationTimeSeconds
                ?? revision.modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds
                ?? revision.modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds
                ?? revision.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds
                ?? revision.statusChangeTimeNanoseconds,
            contentSHA256: contentSHA256 ?? revision.contentSHA256,
            metadataSHA256: metadataSHA256 ?? revision.metadataSHA256
        )
    }

    private func revisionComponentMutations(
        of revision: ComparisonProjectWorkflowFileRevision,
        includeCanonicalURL: Bool = true
    ) -> [ComparisonProjectWorkflowFileRevision] {
        let changedParent = ComparisonProjectWorkflowCanonicalDirectoryIdentity(
            canonicalURL: revision.identity.parent.canonicalURL,
            node: node(8_001)
        )
        let changedNodeIdentity = ComparisonProjectWorkflowCanonicalFileIdentity(
            canonicalURL: revision.identity.canonicalURL,
            parent: revision.identity.parent,
            node: node(8_002)
        )
        let changedParentIdentity = ComparisonProjectWorkflowCanonicalFileIdentity(
            canonicalURL: revision.identity.canonicalURL,
            parent: changedParent,
            node: revision.identity.node
        )
        var mutations = [
            revisionCopy(revision, identity: changedNodeIdentity),
            revisionCopy(revision, identity: changedParentIdentity),
            revisionCopy(revision, byteCount: revision.byteCount + 1),
            revisionCopy(revision, linkCount: revision.linkCount + 1),
            revisionCopy(revision, permissions: revision.permissions ^ 0o100),
            revisionCopy(revision, ownerID: revision.ownerID + 1),
            revisionCopy(revision, groupID: revision.groupID + 1),
            revisionCopy(revision, flags: revision.flags + 1),
            revisionCopy(
                revision,
                modificationTimeSeconds: revision.modificationTimeSeconds + 1
            ),
            revisionCopy(
                revision,
                modificationTimeNanoseconds: revision.modificationTimeNanoseconds + 1
            ),
            revisionCopy(
                revision,
                statusChangeTimeSeconds: revision.statusChangeTimeSeconds + 1
            ),
            revisionCopy(
                revision,
                statusChangeTimeNanoseconds: revision.statusChangeTimeNanoseconds + 1
            ),
            revisionCopy(
                revision,
                contentSHA256: Array(repeating: 0xC1, count: SHA256.Digest.byteCount)
            ),
            revisionCopy(
                revision,
                metadataSHA256: Array(repeating: 0xD2, count: SHA256.Digest.byteCount)
            )
        ]
        if includeCanonicalURL {
            let changedURL = URL(
                filePath: revision.identity.canonicalURL.deletingLastPathComponent()
                    .appending(path: "changed.macmerge").path
            )
            let changedURLIdentity = ComparisonProjectWorkflowCanonicalFileIdentity(
                canonicalURL: changedURL,
                parent: revision.identity.parent,
                node: revision.identity.node
            )
            mutations.insert(revisionCopy(revision, identity: changedURLIdentity), at: 0)
        }
        return mutations
    }

    private func expectedOpenAuthorities(
        projectURL: URL,
        sideURLs: [(ComparisonProjectWorkflowSideIdentity, URL)],
        sideCoverage: ComparisonProjectWorkflowAuthorityCoverage
    ) -> [ComparisonProjectWorkflowAuthorityRequirement] {
        [
            .init(
                purpose: .readProjectFile,
                requestedURL: projectURL,
                canonicalURL: projectURL,
                requiredCoverage: .exactFile,
                access: .callerManagedWhenRequired
            )
        ]
            + sideURLs.map { side, url in
                .init(
                    purpose: .readComparisonSource(side),
                    requestedURL: url,
                    requiredCoverage: sideCoverage,
                    access: .callerManagedWhenRequired
                )
            }
    }

    private func macMergeData(at url: URL) throws -> Data {
        try ComparisonProject(
            left: URL(filePath: "/inputs/left"),
            right: URL(filePath: "/inputs/right"),
            mode: .text
        ).encodedData(relativeTo: url)
    }

    private func sha256(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private func limits(
        maximumProjectFileBytes: Int = ComparisonProject.maximumFileSize,
        maximumPathUTF8Bytes: Int = 16 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 256 * 1_024,
        maximumOptionItemCount: Int = 4_096,
        maximumOptionStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalOptionStringUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumPlanBytes: Int = 12 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 64 * 1_024 * 1_024
    ) -> ComparisonProjectWorkflowLimits {
        ComparisonProjectWorkflowLimits(
            maximumProjectFileBytes: maximumProjectFileBytes,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: maximumTotalPathUTF8Bytes,
            maximumOptionItemCount: maximumOptionItemCount,
            maximumOptionStringUTF8Bytes: maximumOptionStringUTF8Bytes,
            maximumTotalOptionStringUTF8Bytes: maximumTotalOptionStringUTF8Bytes,
            maximumPlanBytes: maximumPlanBytes,
            maximumWorkUnits: maximumWorkUnits
        )
    }

    private func assertWorkflowError<T>(
        _ expected: ComparisonProjectWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? ComparisonProjectWorkflowError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func assertWinMergeDiagnostic<T>(
        _ expectedCode: WinMergeProjectFileDiagnostic.Code,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case .winMergeProject(let diagnostic) = error as? ComparisonProjectWorkflowError else {
                return XCTFail("Expected WinMerge project diagnostic, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(diagnostic.code, expectedCode, file: file, line: line)
        }
    }
}
