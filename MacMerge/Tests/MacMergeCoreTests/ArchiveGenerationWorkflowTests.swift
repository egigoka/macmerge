import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class ArchiveGenerationWorkflowTests: XCTestCase {
    func testPlanExposesCanonicalSelectionOptionsDestinationAuthoritiesAndContracts() throws {
        let left = source(path: "left.txt", seed: 1, byteCount: 4, authority: .ambient)
        let right = source(path: "right.txt", seed: 2, byteCount: 5)
        let entries = [
            entry(id: "right", path: "right.txt", status: .rightOnly, right: right),
            entry(id: "left", path: "left.txt", status: .leftOnly, left: left)
        ]
        let options = ArchiveGenerationOutputOptions(
            format: .zip,
            compression: .deflate,
            compressionLevel: 7,
            metadataPolicy: .preserveSource,
            pathPrefix: "bundle",
            archiveComment: "owned comment",
            destinationPermissions: 0o640
        )
        let capabilities = ArchiveGenerationExecutorCapabilities(
            identifier: "test.executor",
            revision: 17,
            codecs: [ArchiveGenerationCodec(format: .zip, compression: .deflate)]
        )
        let request = makeRequest(
            entries: entries,
            selection: .only([
                ArchiveGenerationSelectedEntry(
                    id: ArchiveGenerationEntryID(rawValue: "right"),
                    side: .right,
                    archiveRelativePath: "renamed/right.txt"
                ),
                ArchiveGenerationSelectedEntry(
                    id: ArchiveGenerationEntryID(rawValue: "left"),
                    side: .left
                )
            ]),
            options: options,
            capabilities: capabilities
        )

        let plan = try ArchiveGenerationWorkflow.plan(request)

        XCTAssertEqual(plan.pathPolicy, .required)
        XCTAssertEqual(plan.directoryRevisionPolicy, .required)
        XCTAssertEqual(plan.manifest.pathPolicy, .required)
        XCTAssertEqual(plan.manifest.options, options)
        XCTAssertEqual(plan.manifest.entries.map(\.archiveRelativePath), ["bundle/left.txt", "bundle/renamed/right.txt"])
        XCTAssertEqual(plan.manifest.entries.map(\.selection.side), [.left, .right])
        XCTAssertEqual(plan.manifest.totalUncompressedByteCount, 9)
        XCTAssertEqual(plan.manifest.totalMetadataByteCount, 14)
        XCTAssertEqual(plan.manifest.totalPathUTF8ByteCount, 39)
        XCTAssertEqual(plan.manifest.totalPathComponentCount, 5)
        XCTAssertEqual(plan.destination, request.destination)
        XCTAssertEqual(plan.executorCapabilities, capabilities)
        XCTAssertEqual(plan.authorityRequirements.count, 3)
        XCTAssertEqual(plan.authorityRequirements.map(\.requiredCoverage), [.exactItem, .exactItem, .directoryTree])
        XCTAssertEqual(plan.authorityRequirements[0].purpose, .readSource(ArchiveGenerationEntryID(rawValue: "left"), .left))
        XCTAssertEqual(plan.authorityRequirements[2].purpose, .createDestination)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(plan.executorContract.sourceAccess, .balancedAuthorityThenPinnedRootDescriptorRelativeNoFollow)
        XCTAssertEqual(
            plan.executorContract.sourceRevision,
            .exactIdentityContentMetadataAndBoundedDirectoryRevisionHeldOrRevalidatedThroughEncoding
        )
        XCTAssertEqual(plan.executorContract.destination, .exactParentVacancyOrFullExistingRevisionCompareAndSwapRejectingSourceAliases)
        XCTAssertEqual(plan.executorContract.overwrite, .privateStageThenAtomicCreateOrExactReplacementNeverInPlace)
        XCTAssertEqual(plan.executorContract.sandbox, .balanceEveryDeclaredScopeAroundValidationEncodingAndPublication)
        XCTAssertEqual(plan.executorContract.codec, .exactCapabilityRevisionDeterministicDescriptorInputAndBoundedOutputWithoutShell)
        XCTAssertEqual(plan.executorContract.paths, .bytePreservingASCIIPortableV1ManifestNamesAndDescriptorPathsNeverURLWritePaths)
        XCTAssertEqual(plan.executorContract.cancellation, .noPublicationBeforeImmediateFinalCheckThenCommittedCompareMissOrUncertain)
        XCTAssertEqual(plan.executorContract.planUse, .consumePlanDigestOnceAfterSnapshotSourceAndDestinationCAS)
        XCTAssertEqual(plan.executorContract.staging, .private0700Directory0600LeafBoundedSyncThenPublishAndSyncParent)
        XCTAssertEqual(ArchiveGenerationExecutorContract.stagingDirectoryPermissions, 0o700)
        XCTAssertEqual(ArchiveGenerationExecutorContract.stagingFilePermissions, 0o600)
    }

    func testAllSelectionUsesRequestedSideAndMissingSideDispositionIsIsolated() throws {
        let entries = [
            entry(id: "left", path: "left.txt", status: .leftOnly, left: source(path: "left.txt", seed: 1)),
            entry(id: "right", path: "right.txt", status: .rightOnly, right: source(path: "right.txt", seed: 2))
        ]

        assertPlanningError(.missingSide(ArchiveGenerationEntryID(rawValue: "right"), .left)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: entries, selection: .all(side: .left)))
        }

        let inclusion = ArchiveGenerationInclusionPolicy(missingSide: .omit)
        let plan = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: entries, selection: .all(side: .left), inclusion: inclusion)
        )
        XCTAssertEqual(plan.manifest.entries.map(\.archiveRelativePath), ["left.txt"])
        XCTAssertEqual(plan.omissions.map(\.id.rawValue), ["right"])
        XCTAssertEqual(plan.omissions.map(\.side), [.left])
        XCTAssertEqual(plan.omissions.map(\.relativePath), ["right.txt"])
        XCTAssertEqual(plan.omissions.map(\.reason), [.missingSide])
        XCTAssertEqual(plan.receipt.includedItemCount, 1)
        XCTAssertEqual(plan.receipt.omittedItemCount, 1)
    }

    func testExplicitSelectionRejectsEmptyUnknownDuplicateAndConflictingDescendantMapping() throws {
        let file = entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 1))
        assertPlanningError(.emptySelection) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], selection: .only([])))
        }
        assertPlanningError(.unknownEntryIdentifier(ArchiveGenerationEntryID(rawValue: "unknown"))) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [file],
                    selection: .only([ArchiveGenerationSelectedEntry(id: ArchiveGenerationEntryID(rawValue: "unknown"), side: .left)])
                )
            )
        }
        let selected = ArchiveGenerationSelectedEntry(id: file.id, side: .left)
        assertPlanningError(.duplicateSelection(file.id, .left)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], selection: .only([selected, selected])))
        }

        let directoryRoot = root(path: "/source-tree", seed: 20)
        let children: [(String, ArchiveGenerationItemKind)] = [("child.txt", .regularFile)]
        let directory = entry(
            id: "directory",
            path: "directory",
            status: .leftOnly,
            left: source(path: "directory", kind: .directory, seed: 21, root: directoryRoot, children: children)
        )
        let child = entry(
            id: "child",
            path: "directory/child.txt",
            status: .leftOnly,
            left: source(path: "directory/child.txt", seed: 22, root: directoryRoot)
        )
        let inclusion = ArchiveGenerationInclusionPolicy(directorySelection: .includeSnapshotDescendants)
        assertPlanningError(.ambiguousSelection(child.id, .left)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [directory, child],
                    selection: .only([
                        ArchiveGenerationSelectedEntry(id: child.id, side: .left, archiveRelativePath: "other.txt"),
                        ArchiveGenerationSelectedEntry(id: directory.id, side: .left, archiveRelativePath: "mapped")
                    ]),
                    inclusion: inclusion
                )
            )
        }
    }

    func testDirectorySelectionIncludesOnlySnapshotDescendantsAndMapsTheirSuffixes() throws {
        let sourceRoot = root(path: "/source-tree", seed: 30)
        let directory = entry(
            id: "directory",
            path: "directory",
            status: .leftOnly,
            left: source(
                path: "directory",
                kind: .directory,
                seed: 31,
                root: sourceRoot,
                children: [("child.txt", .regularFile), ("nested", .directory)]
            )
        )
        let child = entry(
            id: "child",
            path: "directory/child.txt",
            status: .leftOnly,
            left: source(path: "directory/child.txt", seed: 32, root: sourceRoot)
        )
        let nested = entry(
            id: "nested",
            path: "directory/nested",
            status: .leftOnly,
            left: source(
                path: "directory/nested",
                kind: .directory,
                seed: 33,
                root: sourceRoot,
                children: [("leaf.txt", .regularFile)]
            )
        )
        let leaf = entry(
            id: "leaf",
            path: "directory/nested/leaf.txt",
            status: .leftOnly,
            left: source(path: "directory/nested/leaf.txt", seed: 34, root: sourceRoot)
        )
        let unrelated = entry(
            id: "unrelated",
            path: "unrelated.txt",
            status: .leftOnly,
            left: source(path: "unrelated.txt", seed: 35, root: sourceRoot)
        )
        let selection = ArchiveGenerationSelection.only([
            ArchiveGenerationSelectedEntry(id: directory.id, side: .left, archiveRelativePath: "mapped")
        ])
        let inclusion = ArchiveGenerationInclusionPolicy(directorySelection: .includeSnapshotDescendants)

        let plan = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [leaf, unrelated, directory, nested, child], selection: selection, inclusion: inclusion)
        )

        XCTAssertEqual(
            plan.manifest.entries.map(\.archiveRelativePath),
            ["mapped", "mapped/child.txt", "mapped/nested", "mapped/nested/leaf.txt"]
        )
        XCTAssertFalse(plan.manifest.entries.map(\.archiveRelativePath).contains("unrelated.txt"))
    }

    func testDescendantExpansionAcceptsExactSelectedEntryMaximumAndRejectsOneMore() throws {
        let sourceRoot = root(path: "/selected-limit", seed: 36)
        let directory = entry(
            id: "directory",
            path: "directory",
            status: .leftOnly,
            left: source(
                path: "directory",
                kind: .directory,
                seed: 37,
                root: sourceRoot,
                children: [("a", .regularFile), ("b", .regularFile)]
            )
        )
        let entries = [
            directory,
            entry(
                id: "a",
                path: "directory/a",
                status: .leftOnly,
                left: source(path: "directory/a", seed: 38, root: sourceRoot)
            ),
            entry(
                id: "b",
                path: "directory/b",
                status: .leftOnly,
                left: source(path: "directory/b", seed: 39, root: sourceRoot)
            )
        ]
        let selection = ArchiveGenerationSelection.only([
            ArchiveGenerationSelectedEntry(id: directory.id, side: .left)
        ])
        let inclusion = ArchiveGenerationInclusionPolicy(
            directorySelection: .includeSnapshotDescendants
        )

        let exact = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: entries,
                selection: selection,
                inclusion: inclusion,
                limits: limits(maximumSnapshotEntries: 3, maximumSelectedEntries: 3)
            )
        )
        XCTAssertEqual(exact.manifest.entries.count, 3)

        assertPlanningError(.tooManySelectedEntries(maximum: 2)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: entries,
                    selection: selection,
                    inclusion: inclusion,
                    limits: limits(maximumSnapshotEntries: 3, maximumSelectedEntries: 2)
                )
            )
        }
    }

    func testFilteringBindsStatusKindHiddenAndOrderedPathRules() throws {
        let entries = [
            entry(id: "keep", path: "Keep.TXT", status: .leftOnly, left: source(path: "Keep.TXT", seed: 41), hidden: true),
            entry(id: "status", path: "status.txt", status: .skipped, left: source(path: "status.txt", seed: 42), hidden: true),
            entry(id: "kind", path: "kind", status: .leftOnly, left: source(path: "kind", kind: .directory, seed: 43), hidden: true),
            entry(id: "visible", path: "visible.txt", status: .leftOnly, left: source(path: "visible.txt", seed: 44))
        ]
        let filter = ArchiveGenerationFilterPolicy(
            statuses: [.leftOnly],
            kinds: [.regularFile],
            hidden: .only,
            defaultPathAction: .exclude,
            pathRules: [
                ArchiveGenerationPathRule(action: .include, match: .subtree("keep.txt")),
                ArchiveGenerationPathRule(action: .exclude, match: .pathExtension("txt")),
                ArchiveGenerationPathRule(action: .include, match: .exact("keep.txt"))
            ],
            pathComparison: .portableCaseInsensitive
        )
        let inclusion = ArchiveGenerationInclusionPolicy(filter: filter, missingSide: .omit)

        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(entries: entries, inclusion: inclusion))

        XCTAssertEqual(plan.manifest.entries.map(\.archiveRelativePath), ["Keep.TXT"])
        XCTAssertEqual(plan.omissions.map(\.id.rawValue), ["kind", "status", "visible"])
        XCTAssertTrue(plan.omissions.allSatisfy { $0.reason == .filtered })
    }

    func testUnsupportedKindsRejectOrProduceExactOmissions() throws {
        let link = entry(
            id: "link",
            path: "link",
            status: .leftOnly,
            left: source(path: "link", kind: .symbolicLink, seed: 51)
        )
        let special = entry(
            id: "special",
            path: "special",
            status: .leftOnly,
            left: source(path: "special", kind: .specialFile, seed: 52)
        )
        let regular = entry(id: "regular", path: "regular", status: .leftOnly, left: source(path: "regular", seed: 53))

        assertPlanningError(.unsupportedItem(path: "link", kind: .symbolicLink)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [regular, link]))
        }
        let omitLinks = ArchiveGenerationInclusionPolicy(symbolicLinks: .omit)
        assertPlanningError(.unsupportedItem(path: "special", kind: .specialFile)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [regular, link, special], inclusion: omitLinks))
        }
        let omitBoth = ArchiveGenerationInclusionPolicy(symbolicLinks: .omit, specialFiles: .omit)
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [special, regular, link], inclusion: omitBoth))
        XCTAssertEqual(plan.manifest.entries.map(\.archiveRelativePath), ["regular"])
        XCTAssertEqual(plan.omissions.map(\.reason), [.symbolicLink, .specialFile])
    }

    func testComparisonAndArchivePathsRejectTraversalSeparatorsAndNoncanonicalComponents() throws {
        let invalidCases: [(String, ArchiveGenerationPathIssue)] = [
            ("", .empty), ("/absolute", .absolute), ("a\\b", .containsBackslash),
            ("a\0b", .containsNull), ("a//b", .emptyComponent), ("a/./b", .currentDirectoryComponent),
            ("a/../b", .parentTraversal)
        ]
        for (path, issue) in invalidCases {
            let invalid = entry(id: "invalid", path: path, status: .leftOnly, left: source(path: path, seed: 61))
            assertPlanningError(.invalidPath(role: .comparison, path: path, issue: issue)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(entries: [invalid]))
            }
        }

        let valid = entry(id: "valid", path: "valid.txt", status: .leftOnly, left: source(path: "valid.txt", seed: 62))
        for (path, issue) in invalidCases {
            let selected = ArchiveGenerationSelectedEntry(id: valid.id, side: .left, archiveRelativePath: path)
            assertPlanningError(.invalidPath(role: .archive, path: path, issue: issue)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(entries: [valid], selection: .only([selected])))
            }
        }
    }

    func testHostileSourcePathAndPrefixFailuresReportTheirOwnRoles() throws {
        let base = source(path: "file.txt", seed: 63)
        for (path, issue, maximumDepth) in [
            ("a/../b", ArchiveGenerationPathIssue.parentTraversal, 128),
            ("a/b/c", ArchiveGenerationPathIssue.tooDeep, 2)
        ] {
            let identity = ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: base.revision.identity.canonicalURL,
                root: base.revision.identity.root,
                relativePath: path,
                kind: .regularFile,
                node: base.revision.identity.node
            )
            let hostile = ArchiveGenerationSourceItem(
                requestedURL: base.requestedURL,
                revision: revisionCopy(base.revision, identity: identity)
            )
            assertPlanningError(.invalidPath(role: .source, path: path, issue: issue)) {
                try ArchiveGenerationWorkflow.plan(
                    makeRequest(
                        entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: hostile)],
                        limits: limits(maximumPathDepth: maximumDepth)
                    )
                )
            }
        }

        let file = entry(id: "file", path: "file.txt", status: .leftOnly, left: base)
        for (prefix, issue, maximumDepth) in [
            ("a/../b", ArchiveGenerationPathIssue.parentTraversal, 128),
            ("é", ArchiveGenerationPathIssue.unsupportedNonASCII, 128),
            ("a/b/c", ArchiveGenerationPathIssue.tooDeep, 2)
        ] {
            assertPlanningError(.invalidPath(role: .prefix, path: prefix, issue: issue)) {
                try ArchiveGenerationWorkflow.plan(
                    makeRequest(
                        entries: [file],
                        options: ArchiveGenerationOutputOptions(pathPrefix: prefix),
                        limits: limits(maximumPathDepth: maximumDepth)
                    )
                )
            }
        }
    }

    func testPortableArchiveNamesRejectEveryPinnedHostileShape() throws {
        let valid = entry(id: "valid", path: "valid.txt", status: .leftOnly, left: source(path: "valid.txt", seed: 70))
        let cases: [(String, ArchiveGenerationPathIssue)] = [
            ("é.txt", .unsupportedNonASCII),
            ("name:stream", .containsColon),
            ("name?.txt", .containsPortableForbiddenCharacter),
            ("name.", .trailingDotOrSpace),
            ("name ", .trailingDotOrSpace),
            ("CON", .reservedDeviceName),
            ("lPt9.txt", .reservedDeviceName),
            ("control\u{1F}.txt", .containsPortableForbiddenCharacter)
        ]
        for (path, issue) in cases {
            let selected = ArchiveGenerationSelectedEntry(id: valid.id, side: .left, archiveRelativePath: path)
            assertPlanningError(.invalidPath(role: .archive, path: path, issue: issue)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(entries: [valid], selection: .only([selected])))
            }
        }
    }

    func testDuplicatePortableCollisionAndHierarchyGuardsAreIndependent() throws {
        let first = entry(id: "first", path: "first", status: .leftOnly, left: source(path: "first", seed: 81))
        let second = entry(id: "second", path: "second", status: .leftOnly, left: source(path: "second", seed: 82))

        assertPlanningError(.duplicateArchivePath("same.txt")) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [first, second],
                    selection: .only([
                        ArchiveGenerationSelectedEntry(id: first.id, side: .left, archiveRelativePath: "same.txt"),
                        ArchiveGenerationSelectedEntry(id: second.id, side: .left, archiveRelativePath: "same.txt")
                    ])
                )
            )
        }
        assertPlanningError(.portablePathCollision(first: "Case", second: "case")) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [first, second],
                    selection: .only([
                        ArchiveGenerationSelectedEntry(id: first.id, side: .left, archiveRelativePath: "Case/a"),
                        ArchiveGenerationSelectedEntry(id: second.id, side: .left, archiveRelativePath: "case/b")
                    ])
                )
            )
        }
        assertPlanningError(.pathHierarchyConflict(ancestor: "parent", descendant: "parent/child")) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [first, second],
                    selection: .only([
                        ArchiveGenerationSelectedEntry(id: first.id, side: .left, archiveRelativePath: "parent"),
                        ArchiveGenerationSelectedEntry(id: second.id, side: .left, archiveRelativePath: "parent/child")
                    ])
                )
            )
        }
    }

    func testSourceURLCanonicalIdentityAndRevisionGuardsAreIsolated() throws {
        let validRoot = root(path: "/sources", seed: 90)
        let valid = source(path: "file.txt", seed: 91, root: validRoot)
        let id = ArchiveGenerationEntryID(rawValue: "file")

        let remote = ArchiveGenerationSourceItem(
            requestedURL: URL(string: "https://example.com/file.txt")!,
            revision: valid.revision
        )
        assertPlanningError(.invalidURL(role: .requestedSource(id, .left), issue: .notFileURL)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: remote)]))
        }

        let wrongCanonicalIdentity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: URL(filePath: "/elsewhere/file.txt"),
            root: validRoot,
            relativePath: "file.txt",
            kind: .regularFile,
            node: valid.revision.identity.node
        )
        let wrongCanonical = ArchiveGenerationSourceItem(
            requestedURL: valid.requestedURL,
            revision: revision(identity: wrongCanonicalIdentity)
        )
        assertPlanningError(.invalidURL(role: .canonicalSource(id, .left), issue: .rootMismatch)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: wrongCanonical)]))
        }

        let invalidRevisions = [
            revisionCopy(valid.revision, linkCount: 0),
            revisionCopy(valid.revision, permissions: 0xF000),
            revisionCopy(valid.revision, modificationTimeNanoseconds: -1),
            revisionCopy(valid.revision, modificationTimeNanoseconds: 1_000_000_000),
            revisionCopy(valid.revision, statusChangeTimeNanoseconds: -1),
            revisionCopy(valid.revision, statusChangeTimeNanoseconds: 1_000_000_000),
            revisionCopy(valid.revision, contentSHA256: [0]),
            revisionCopy(valid.revision, metadataSHA256: [0]),
            revisionCopy(valid.revision, directoryChildCount: 1),
            revisionCopy(valid.revision, directoryChildNameUTF8ByteCount: 1)
        ]
        for invalidRevision in invalidRevisions {
            let invalid = ArchiveGenerationSourceItem(requestedURL: valid.requestedURL, revision: invalidRevision)
            assertPlanningError(.invalidRevision(path: valid.revision.identity.canonicalURL.path)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: invalid)]))
            }
        }
    }

    func testConflictingRevisionForExactSourceIdentityIsRejected() throws {
        let shared = source(path: "shared.txt", seed: 100)
        let changed = ArchiveGenerationSourceItem(
            requestedURL: shared.requestedURL,
            revision: revisionCopy(shared.revision, metadataSHA256: digest("changed metadata"))
        )
        assertPlanningError(.conflictingSourceRevision(path: shared.revision.identity.canonicalURL.path)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: [entry(id: "shared", path: "shared.txt", status: .identical, left: shared, right: changed)])
            )
        }
    }

    func testSourceSecurityScopeRequiresExactCanonicalCoverage() throws {
        let sourceRoot = root(path: "/secure", seed: 110)
        let base = source(path: "file.txt", seed: 111, root: sourceRoot)
        let exact = ArchiveGenerationSourceItem(
            requestedURL: base.requestedURL,
            revision: base.revision,
            accessAuthority: .securityScoped(resourceURL: base.requestedURL, coverage: .exactItem)
        )
        XCTAssertNoThrow(
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: exact)])
            )
        )

        let tree = ArchiveGenerationSourceItem(
            requestedURL: base.requestedURL,
            revision: base.revision,
            accessAuthority: .securityScoped(resourceURL: sourceRoot.canonicalURL, coverage: .directoryTree)
        )
        XCTAssertNoThrow(
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: tree)])
            )
        )

        let uncovered = ArchiveGenerationSourceItem(
            requestedURL: base.requestedURL,
            revision: base.revision,
            accessAuthority: .securityScoped(resourceURL: URL(filePath: "/other"), coverage: .directoryTree)
        )
        assertPlanningError(.invalidURL(role: .requestedSource(ArchiveGenerationEntryID(rawValue: "file"), .left), issue: .insufficientAuthorityCoverage)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: uncovered)])
            )
        }
    }

    func testCreateDestinationBindsExactParentLeafAndTreeAuthority() throws {
        let file = entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 120))
        let parent = root(path: "/output", seed: 121)
        let canonical = URL(filePath: "/output/archive.zip")
        let valid = ArchiveGenerationDestination(
            requestedURL: canonical,
            intent: .createNew(ArchiveGenerationCanonicalDestinationLocation(canonicalURL: canonical, parent: parent)),
            accessAuthority: .securityScoped(resourceURL: parent.canonicalURL, coverage: .directoryTree)
        )
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], destination: valid))
        XCTAssertEqual(plan.destination.intent.canonicalURL, canonical)
        XCTAssertEqual(plan.destination.intent.canonicalParent, parent)
        XCTAssertEqual(plan.authorityRequirements.last?.purpose, .createDestination)

        let wrongParent = root(path: "/other", seed: 122)
        let mismatched = ArchiveGenerationDestination(
            requestedURL: canonical,
            intent: .createNew(ArchiveGenerationCanonicalDestinationLocation(canonicalURL: canonical, parent: wrongParent))
        )
        assertPlanningError(.invalidURL(role: .canonicalDestination, issue: .parentMismatch)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], destination: mismatched))
        }

        let insufficient = ArchiveGenerationDestination(
            requestedURL: canonical,
            intent: .createNew(ArchiveGenerationCanonicalDestinationLocation(canonicalURL: canonical, parent: parent)),
            accessAuthority: .securityScoped(resourceURL: canonical, coverage: .exactItem)
        )
        assertPlanningError(.invalidURL(role: .requestedDestination, issue: .insufficientAuthorityCoverage)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], destination: insufficient))
        }
    }

    func testReplaceDestinationRequiresExactRegularFileRevisionAndDoesNotAliasSource() throws {
        let selectedSource = source(path: "file.txt", seed: 130)
        let file = entry(id: "file", path: "file.txt", status: .leftOnly, left: selectedSource)
        let destinationParent = root(path: "/output", seed: 131)
        let expected = replacementRevision(parent: destinationParent, seed: 132)
        let destination = ArchiveGenerationDestination(
            requestedURL: expected.identity.canonicalURL,
            intent: .replaceExisting(expected),
            accessAuthority: .ambient
        )
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], destination: destination))
        XCTAssertEqual(plan.authorityRequirements.last?.purpose, .replaceDestination)
        XCTAssertEqual(plan.destination.intent.canonicalURL, expected.identity.canonicalURL)

        let invalid = revisionCopy(expected, directoryChildCount: 1)
        assertPlanningError(.destinationDoesNotMatchIntent) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [file],
                    destination: ArchiveGenerationDestination(
                        requestedURL: invalid.identity.canonicalURL,
                        intent: .replaceExisting(invalid)
                    )
                )
            )
        }

        let aliasIdentity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: expected.identity.canonicalURL,
            root: destinationParent,
            relativePath: "archive.zip",
            kind: .regularFile,
            node: selectedSource.revision.identity.node
        )
        let alias = revisionCopy(expected, identity: aliasIdentity)
        assertPlanningError(.destinationMatchesSource(expected.identity.canonicalURL.path)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [file],
                    destination: ArchiveGenerationDestination(
                        requestedURL: alias.identity.canonicalURL,
                        intent: .replaceExisting(alias)
                    )
                )
            )
        }
    }

    func testDestinationCannotMatchOrDescendFromSelectedSourceDirectory() throws {
        let sourceRoot = root(path: "/tree", seed: 140)
        let directorySource = source(path: "folder", kind: .directory, seed: 141, root: sourceRoot)
        let directory = entry(id: "folder", path: "folder", status: .leftOnly, left: directorySource)

        let sameParent = directorySource.revision.identity.root
        let sameLocation = ArchiveGenerationCanonicalDestinationLocation(
            canonicalURL: directorySource.revision.identity.canonicalURL,
            parent: sameParent
        )
        assertPlanningError(.destinationMatchesSource(directorySource.revision.identity.canonicalURL.path)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [directory],
                    destination: ArchiveGenerationDestination(
                        requestedURL: sameLocation.canonicalURL,
                        intent: .createNew(sameLocation)
                    )
                )
            )
        }

        let insideParent = ArchiveGenerationCanonicalDirectoryIdentity(
            canonicalURL: directorySource.revision.identity.canonicalURL,
            node: directorySource.revision.identity.node
        )
        let insideURL = URL(filePath: "/tree/folder/archive.zip")
        let inside = ArchiveGenerationCanonicalDestinationLocation(canonicalURL: insideURL, parent: insideParent)
        assertPlanningError(.destinationInsideSource(insideURL.path)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [directory],
                    destination: ArchiveGenerationDestination(requestedURL: insideURL, intent: .createNew(inside))
                )
            )
        }
    }

    func testDirectoryRevisionUsesExactSortedVersionedChildDigestAndBounds() throws {
        let sourceRoot = root(path: "/directory-tree", seed: 150)
        let children: [(String, ArchiveGenerationItemKind)] = [
            ("z.txt", .regularFile), ("A", .directory), ("link", .symbolicLink)
        ]
        let directorySource = source(
            path: "folder",
            kind: .directory,
            seed: 151,
            root: sourceRoot,
            children: children
        )
        let entries = [
            entry(id: "folder", path: "folder", status: .leftOnly, left: directorySource),
            entry(id: "z", path: "folder/z.txt", status: .leftOnly, left: source(path: "folder/z.txt", seed: 152, root: sourceRoot)),
            entry(
                id: "A",
                path: "folder/A",
                status: .leftOnly,
                left: source(path: "folder/A", kind: .directory, seed: 153, root: sourceRoot)
            ),
            entry(
                id: "link",
                path: "folder/link",
                status: .leftOnly,
                left: source(path: "folder/link", kind: .symbolicLink, seed: 154, root: sourceRoot)
            )
        ]
        let inclusion = ArchiveGenerationInclusionPolicy(symbolicLinks: .omit)
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(entries: entries, inclusion: inclusion))

        XCTAssertEqual(ArchiveGenerationDirectoryRevisionPolicy.required.rawValue, "sortedLengthPrefixedUTF8NameAndFixedKindV1")
        XCTAssertEqual(directorySource.revision.directoryChildCount, 3)
        XCTAssertEqual(directorySource.revision.directoryChildNameUTF8ByteCount, 10)
        XCTAssertEqual(directorySource.revision.contentSHA256, directoryDigest(children))
        XCTAssertEqual(plan.manifest.entries.count, 3)

        for invalidRevision in [
            revisionCopy(directorySource.revision, directoryChildCount: 2),
            revisionCopy(directorySource.revision, directoryChildNameUTF8ByteCount: 9),
            revisionCopy(directorySource.revision, contentSHA256: digest("wrong directory digest"))
        ] {
            let invalidDirectory = ArchiveGenerationSourceItem(requestedURL: directorySource.requestedURL, revision: invalidRevision)
            let invalidEntries = [entry(id: "folder", path: "folder", status: .leftOnly, left: invalidDirectory)] + entries.dropFirst()
            assertPlanningError(.invalidRevision(path: directorySource.revision.identity.canonicalURL.path)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(entries: Array(invalidEntries), inclusion: inclusion))
            }
        }
    }

    func testDirectoryChildCountAndNameByteCapsRejectBeforeEnumerationMismatch() throws {
        let sourceRoot = root(path: "/bounded-tree", seed: 160)
        let childName = "child.txt"
        let directorySource = source(
            path: "folder",
            kind: .directory,
            seed: 161,
            root: sourceRoot,
            children: [(childName, .regularFile)]
        )
        let child = source(path: "folder/child.txt", seed: 162, root: sourceRoot)
        let entries = [
            entry(id: "folder", path: "folder", status: .leftOnly, left: directorySource),
            entry(id: "child", path: "folder/child.txt", status: .leftOnly, left: child)
        ]
        XCTAssertNoThrow(
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: entries,
                    selection: .only([ArchiveGenerationSelectedEntry(id: ArchiveGenerationEntryID(rawValue: "folder"), side: .left)]),
                    limits: limits(maximumSnapshotEntries: 2, maximumTotalPathUTF8Bytes: childName.utf8.count)
                )
            )
        )

        let excessiveCountChildren: [(String, ArchiveGenerationItemKind)] = [
            ("a", .regularFile), ("b", .regularFile), ("c", .regularFile)
        ]
        let excessiveCount = revisionCopy(
            directorySource.revision,
            directoryChildCount: 3,
            directoryChildNameUTF8ByteCount: 3,
            contentSHA256: directoryDigest(excessiveCountChildren)
        )
        assertPlanningError(.invalidRevision(path: directorySource.revision.identity.canonicalURL.path)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [entry(id: "folder", path: "folder", status: .leftOnly, left: item(excessiveCount))],
                    limits: limits(maximumSnapshotEntries: 2)
                )
            )
        }
        let excessiveNameChildren: [(String, ArchiveGenerationItemKind)] = [
            (String(repeating: "n", count: 10), .regularFile)
        ]
        let excessiveNames = revisionCopy(
            directorySource.revision,
            directoryChildNameUTF8ByteCount: 10,
            contentSHA256: directoryDigest(excessiveNameChildren)
        )
        assertPlanningError(.invalidRevision(path: directorySource.revision.identity.canonicalURL.path)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [entry(id: "folder", path: "folder", status: .leftOnly, left: item(excessiveNames))],
                    limits: limits(maximumTotalPathUTF8Bytes: 9)
                )
            )
        }
    }

    func testComparisonRowsBindPathStatusSideAndKindExactly() throws {
        let left = source(path: "row.txt", seed: 170, byteCount: 3, contentSHA256: digest("left"))
        let right = source(path: "row.txt", seed: 171, byteCount: 4, contentSHA256: digest("right"))
        let coherent = entry(id: "row", path: "row.txt", status: .different, left: left, right: right)
        XCTAssertEqual(coherent.item(on: .left), left)
        XCTAssertEqual(coherent.item(on: .right), right)
        XCTAssertNoThrow(try ArchiveGenerationWorkflow.plan(makeRequest(entries: [coherent])))

        let invalidRows = [
            entry(id: "row", path: "other.txt", status: .different, left: left, right: right),
            entry(id: "row", path: "row.txt", status: .leftOnly, left: left, right: right),
            entry(id: "row", path: "row.txt", status: .rightOnly, left: left, right: right),
            entry(id: "row", path: "row.txt", status: .identical, left: left, right: right),
            entry(id: "row", path: "row.txt", status: .typeMismatch, left: left, right: right),
            entry(id: "row", path: "row.txt", status: .skipped)
        ]
        for invalid in invalidRows {
            assertPlanningError(.invalidComparisonEntry(invalid.id)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(entries: [invalid]))
            }
        }

        let directory = source(path: "row.txt", kind: .directory, seed: 172)
        let fileSnapshot = ArchiveGenerationComparisonSnapshot(
            identity: snapshotIdentity,
            generation: 7,
            comparisonKind: .file,
            entries: [entry(id: "row", path: "row.txt", status: .leftOnly, left: directory)]
        )
        assertPlanningError(.invalidComparisonEntry(ArchiveGenerationEntryID(rawValue: "row"))) {
            try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: fileSnapshot))
        }
    }

    func testIdenticalTypeMismatchSkippedAndErrorStatusContracts() throws {
        let left = source(path: "row", seed: 180, byteCount: 3, contentSHA256: digest("same"))
        let identicalRight = source(path: "row", seed: 181, byteCount: 3, contentSHA256: digest("same"))
        let differentKind = source(path: "row", kind: .directory, seed: 182)
        let rows = [
            entry(id: "identical", path: "row", status: .identical, left: left, right: identicalRight),
            entry(id: "mismatch", path: "row", status: .typeMismatch, left: left, right: differentKind),
            entry(id: "skipped", path: "row", status: .skipped, left: left, right: identicalRight),
            entry(id: "error", path: "row", status: .error, left: left, right: identicalRight)
        ]
        for row in rows {
            XCTAssertNoThrow(
                try ArchiveGenerationWorkflow.plan(
                    makeRequest(entries: [row], selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: .left)]))
                )
            )
        }
    }

    func testEveryComparisonStatusAcceptsOnlyCoherentSideAndKindShapes() throws {
        let sameLeft = source(path: "row", seed: 183, byteCount: 3, contentSHA256: digest("same"))
        let sameRight = source(path: "row", seed: 184, byteCount: 3, contentSHA256: digest("same"))
        let changedRight = source(path: "row", seed: 185, byteCount: 4, contentSHA256: digest("changed"))
        let directoryRight = source(path: "row", kind: .directory, seed: 186)
        let valid = [
            entry(id: "left", path: "row", status: .leftOnly, left: sameLeft),
            entry(id: "right", path: "row", status: .rightOnly, right: sameRight),
            entry(id: "identical", path: "row", status: .identical, left: sameLeft, right: sameRight),
            entry(id: "different", path: "row", status: .different, left: sameLeft, right: changedRight),
            entry(id: "mismatch", path: "row", status: .typeMismatch, left: sameLeft, right: directoryRight),
            entry(id: "skipped", path: "row", status: .skipped, left: sameLeft),
            entry(id: "error", path: "row", status: .error, right: sameRight)
        ]
        for row in valid {
            let side: ArchiveGenerationSide = row.left == nil ? .right : .left
            XCTAssertNoThrow(
                try ArchiveGenerationWorkflow.plan(
                    makeRequest(
                        entries: [row],
                        selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: side)])
                    )
                ),
                row.status.rawValue
            )
        }

        let invalid = [
            entry(id: "left-missing", path: "row", status: .leftOnly),
            entry(id: "left-both", path: "row", status: .leftOnly, left: sameLeft, right: sameRight),
            entry(id: "right-missing", path: "row", status: .rightOnly),
            entry(id: "right-both", path: "row", status: .rightOnly, left: sameLeft, right: sameRight),
            entry(id: "identical-missing", path: "row", status: .identical, left: sameLeft),
            entry(id: "identical-changed", path: "row", status: .identical, left: sameLeft, right: changedRight),
            entry(id: "different-equal", path: "row", status: .different, left: sameLeft, right: sameRight),
            entry(id: "different-kind", path: "row", status: .different, left: sameLeft, right: directoryRight),
            entry(id: "mismatch-equal", path: "row", status: .typeMismatch, left: sameLeft, right: sameRight),
            entry(id: "mismatch-missing", path: "row", status: .typeMismatch, left: sameLeft),
            entry(id: "skipped-empty", path: "row", status: .skipped),
            entry(id: "skipped-kind", path: "row", status: .skipped, left: sameLeft, right: directoryRight),
            entry(id: "error-empty", path: "row", status: .error),
            entry(id: "error-kind", path: "row", status: .error, left: sameLeft, right: directoryRight)
        ]
        for row in invalid {
            assertPlanningError(.invalidComparisonEntry(row.id)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(entries: [row]))
            }
        }

        for (kind, seed) in [
            (ArchiveGenerationItemKind.directory, UInt64(187)),
            (.symbolicLink, UInt64(188)),
            (.specialFile, UInt64(189))
        ] {
            let item = source(path: "row", kind: kind, seed: seed)
            let row = entry(id: kind.rawValue, path: "row", status: .leftOnly, left: item)
            let fileSnapshot = makeSnapshot(kind: .file, entries: [row])
            assertPlanningError(.invalidComparisonEntry(row.id)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: fileSnapshot))
            }
        }
    }

    func testCanonicalSortingMakesManifestOmissionsCASAndReceiptsOrderIndependent() throws {
        let a = entry(id: "z-id", path: "a.txt", status: .leftOnly, left: source(path: "a.txt", seed: 190))
        let b = entry(id: "a-id", path: "z.txt", status: .leftOnly, left: source(path: "z.txt", seed: 191))
        let link = entry(
            id: "m-id",
            path: "m-link",
            status: .leftOnly,
            left: source(path: "m-link", kind: .symbolicLink, seed: 192)
        )
        let inclusion = ArchiveGenerationInclusionPolicy(symbolicLinks: .omit)
        let forward = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [a, b, link], inclusion: inclusion))
        let reverse = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [link, b, a], inclusion: inclusion))

        XCTAssertEqual(forward.manifest.entries.map(\.archiveRelativePath), ["a.txt", "z.txt"])
        XCTAssertEqual(forward.omissions.map(\.id.rawValue), ["m-id"])
        XCTAssertEqual(forward.snapshotCAS, reverse.snapshotCAS)
        XCTAssertEqual(forward.manifest.manifestSHA256, reverse.manifest.manifestSHA256)
        XCTAssertEqual(forward.receipt, reverse.receipt)
        XCTAssertEqual(forward.receipt.snapshotCAS, forward.snapshotCAS)
        XCTAssertEqual(forward.receipt.manifestSHA256, forward.manifest.manifestSHA256)
        XCTAssertEqual(forward.receipt.includedItemCount, forward.manifest.entries.count)
        XCTAssertEqual(forward.receipt.omittedItemCount, forward.omissions.count)
        XCTAssertEqual(forward.receipt.sourceByteCount, forward.manifest.totalUncompressedByteCount)
        XCTAssertEqual(forward.receipt.planningArchiveByteEnvelope, forward.manifest.planningArchiveByteEnvelope)
        XCTAssertEqual(forward.snapshotCAS.stateSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(forward.manifest.manifestSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(forward.receipt.planSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(ArchiveGenerationManifest.version, 2)
        XCTAssertEqual(ArchiveGenerationPlanningReceipt.version, 2)
    }

    func testReceiptsBindSnapshotSourceOptionsDestinationCapabilityAndLimits() throws {
        let baseEntry = entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 200))
        let base = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [baseEntry]))
        let changedSource = item(revisionCopy(baseEntry.left!.revision, metadataSHA256: digest("changed")))
        let sourcePlan = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: changedSource)])
        )
        let optionPlan = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [baseEntry], options: ArchiveGenerationOutputOptions(archiveComment: "comment"))
        )
        let destinationPlan = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [baseEntry], destination: createDestination(parentSeed: 201, leaf: "other.zip"))
        )
        let capabilityPlan = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [baseEntry],
                capabilities: ArchiveGenerationExecutorCapabilities(
                    identifier: "other.executor",
                    revision: 1,
                    codecs: [ArchiveGenerationCodec(format: .zip, compression: .store)]
                )
            )
        )
        let limitPlan = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [baseEntry], limits: limits(maximumItemBytes: ArchiveGenerationLimits.default.maximumItemBytes - 1))
        )

        XCTAssertNotEqual(base.snapshotCAS.stateSHA256, sourcePlan.snapshotCAS.stateSHA256)
        XCTAssertNotEqual(base.manifest.manifestSHA256, sourcePlan.manifest.manifestSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, sourcePlan.receipt.planSHA256)
        XCTAssertNotEqual(base.manifest.manifestSHA256, optionPlan.manifest.manifestSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, destinationPlan.receipt.planSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, capabilityPlan.receipt.planSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, limitPlan.receipt.planSHA256)
    }

    func testDigestLayersBindOneLeafPolicyOmissionAuthorityCapabilityCodecStatusHiddenAndIdentityMutations() throws {
        let left = source(path: "row.txt", seed: 205, contentSHA256: digest("left"), authority: .ambient)
        let right = source(path: "row.txt", seed: 206, contentSHA256: digest("right"))
        let row = entry(id: "row", path: "row.txt", status: .different, left: left, right: right)
        let base = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [row],
                selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: .left)])
            )
        )

        let policyMutation = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [row],
                selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: .left)]),
                inclusion: ArchiveGenerationInclusionPolicy(
                    directorySelection: .includeSnapshotDescendants
                )
            )
        )
        XCTAssertEqual(base.snapshotCAS, policyMutation.snapshotCAS)
        XCTAssertEqual(base.manifest.manifestSHA256, policyMutation.manifest.manifestSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, policyMutation.receipt.planSHA256)

        let callerManaged = ArchiveGenerationSourceItem(
            requestedURL: left.requestedURL,
            revision: left.revision,
            accessAuthority: .callerManagedWhenRequired
        )
        let authorityMutation = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [entry(id: "row", path: "row.txt", status: .different, left: callerManaged, right: right)],
                selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: .left)])
            )
        )
        XCTAssertNotEqual(base.snapshotCAS.stateSHA256, authorityMutation.snapshotCAS.stateSHA256)
        XCTAssertNotEqual(base.manifest.manifestSHA256, authorityMutation.manifest.manifestSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, authorityMutation.receipt.planSHA256)

        let statusMutation = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [entry(id: "row", path: "row.txt", status: .skipped, left: left, right: right)],
                selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: .left)])
            )
        )
        XCTAssertNotEqual(base.snapshotCAS.stateSHA256, statusMutation.snapshotCAS.stateSHA256)
        XCTAssertEqual(base.manifest.manifestSHA256, statusMutation.manifest.manifestSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, statusMutation.receipt.planSHA256)

        let hiddenMutation = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [entry(id: "row", path: "row.txt", status: .different, left: left, right: right, hidden: true)],
                selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: .left)])
            )
        )
        XCTAssertNotEqual(base.snapshotCAS.stateSHA256, hiddenMutation.snapshotCAS.stateSHA256)
        XCTAssertEqual(base.manifest.manifestSHA256, hiddenMutation.manifest.manifestSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, hiddenMutation.receipt.planSHA256)

        let changedIdentity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: left.revision.identity.canonicalURL,
            root: left.revision.identity.root,
            relativePath: left.revision.identity.relativePath,
            kind: left.revision.identity.kind,
            node: node(207)
        )
        let identityMutation = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [
                    entry(
                        id: "row",
                        path: "row.txt",
                        status: .different,
                        left: item(revisionCopy(left.revision, identity: changedIdentity)),
                        right: right
                    )
                ],
                selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: .left)])
            )
        )
        XCTAssertNotEqual(base.snapshotCAS.stateSHA256, identityMutation.snapshotCAS.stateSHA256)
        XCTAssertNotEqual(base.manifest.manifestSHA256, identityMutation.manifest.manifestSHA256)

        let capabilityRevisionMutation = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [row],
                selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: .left)]),
                capabilities: ArchiveGenerationExecutorCapabilities(
                    identifier: ArchiveGenerationExecutorCapabilities.portableBaseline.identifier,
                    revision: ArchiveGenerationExecutorCapabilities.portableBaseline.revision + 1,
                    codecs: ArchiveGenerationExecutorCapabilities.portableBaseline.codecs
                )
            )
        )
        XCTAssertEqual(base.manifest.manifestSHA256, capabilityRevisionMutation.manifest.manifestSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, capabilityRevisionMutation.receipt.planSHA256)

        var codecs = ArchiveGenerationExecutorCapabilities.portableBaseline.codecs
        codecs.insert(ArchiveGenerationCodec(format: .tar, compression: .deflate))
        let codecMutation = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [row],
                selection: .only([ArchiveGenerationSelectedEntry(id: row.id, side: .left)]),
                capabilities: ArchiveGenerationExecutorCapabilities(
                    identifier: ArchiveGenerationExecutorCapabilities.portableBaseline.identifier,
                    revision: ArchiveGenerationExecutorCapabilities.portableBaseline.revision,
                    codecs: codecs
                )
            )
        )
        XCTAssertEqual(base.manifest.manifestSHA256, codecMutation.manifest.manifestSHA256)
        XCTAssertNotEqual(base.receipt.planSHA256, codecMutation.receipt.planSHA256)

        let link = entry(
            id: "omitted",
            path: "omitted",
            status: .leftOnly,
            left: source(path: "omitted", kind: .symbolicLink, seed: 208)
        )
        let special = entry(
            id: "omitted",
            path: "omitted",
            status: .leftOnly,
            left: source(path: "omitted", kind: .specialFile, seed: 208)
        )
        let omissionPolicy = ArchiveGenerationInclusionPolicy(
            symbolicLinks: .omit,
            specialFiles: .omit
        )
        let linkPlan = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [row, link], inclusion: omissionPolicy)
        )
        let specialPlan = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [row, special], inclusion: omissionPolicy)
        )
        XCTAssertEqual(linkPlan.omissions.map(\.reason), [.symbolicLink])
        XCTAssertEqual(specialPlan.omissions.map(\.reason), [.specialFile])
        XCTAssertNotEqual(linkPlan.snapshotCAS.stateSHA256, specialPlan.snapshotCAS.stateSHA256)
        XCTAssertEqual(linkPlan.manifest.manifestSHA256, specialPlan.manifest.manifestSHA256)
        XCTAssertNotEqual(linkPlan.receipt.planSHA256, specialPlan.receipt.planSHA256)
    }

    func testPortableCasePolicyUsesASCIIFoldingOnlyAndNonASCIIFailsClosed() throws {
        let upper = entry(id: "upper", path: "File.TXT", status: .leftOnly, left: source(path: "File.TXT", seed: 210))
        let asciiFilter = ArchiveGenerationFilterPolicy(
            defaultPathAction: .exclude,
            pathRules: [ArchiveGenerationPathRule(action: .include, match: .exact("file.txt"))]
        )
        let included = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [upper], inclusion: ArchiveGenerationInclusionPolicy(filter: asciiFilter))
        )
        XCTAssertEqual(included.manifest.entries.map(\.archiveRelativePath), ["File.TXT"])

        let nonASCII = entry(id: "non-ascii", path: "café.txt", status: .leftOnly, left: source(path: "café.txt", seed: 211))
        let mapped = try ArchiveGenerationWorkflow.plan(
            makeRequest(
                entries: [nonASCII],
                selection: .only([
                    ArchiveGenerationSelectedEntry(
                        id: nonASCII.id,
                        side: .left,
                        archiveRelativePath: "cafe.txt"
                    )
                ]),
                inclusion: ArchiveGenerationInclusionPolicy(
                    filter: ArchiveGenerationFilterPolicy(pathComparison: .caseSensitive)
                )
            )
        )
        XCTAssertEqual(mapped.manifest.entries[0].source.revision.identity.relativePath, "café.txt")
        XCTAssertEqual(mapped.manifest.entries[0].archiveRelativePath, "cafe.txt")

        assertPlanningError(.invalidPath(role: .filter, path: "café.txt", issue: .unsupportedNonASCII)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: [nonASCII], inclusion: ArchiveGenerationInclusionPolicy(filter: asciiFilter))
            )
        }
        let nonASCIIRule = ArchiveGenerationFilterPolicy(
            pathRules: [ArchiveGenerationPathRule(action: .include, match: .exact("café.txt"))]
        )
        assertPlanningError(.invalidPath(role: .filter, path: "café.txt", issue: .unsupportedNonASCII)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: [upper], inclusion: ArchiveGenerationInclusionPolicy(filter: nonASCIIRule))
            )
        }
        let caseSensitive = ArchiveGenerationFilterPolicy(
            defaultPathAction: .exclude,
            pathRules: [ArchiveGenerationPathRule(action: .include, match: .exact("café.txt"))],
            pathComparison: .caseSensitive
        )
        assertPlanningError(.invalidPath(role: .archive, path: "café.txt", issue: .unsupportedNonASCII)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: [nonASCII], inclusion: ArchiveGenerationInclusionPolicy(filter: caseSensitive))
            )
        }
    }

    func testOutputCodecCompressionCommentPermissionsAndMetadataPolicies() throws {
        let fileSource = source(path: "file.txt", seed: 220, permissions: 0o654, modificationTimeSeconds: 123, modificationTimeNanoseconds: 456)
        let file = entry(id: "file", path: "file.txt", status: .leftOnly, left: fileSource)
        let preserved = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [file], options: ArchiveGenerationOutputOptions(metadataPolicy: .preserveSource))
        )
        XCTAssertEqual(preserved.manifest.entries[0].metadata.permissions, 0o654)
        XCTAssertEqual(preserved.manifest.entries[0].metadata.modificationTimeSeconds, 123)
        XCTAssertEqual(preserved.manifest.entries[0].metadata.modificationTimeNanoseconds, 456)

        let reproducible = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file]))
        XCTAssertEqual(reproducible.manifest.entries[0].metadata.permissions, 0o600)
        XCTAssertEqual(reproducible.manifest.entries[0].metadata.modificationTimeSeconds, 315_532_800)
        XCTAssertEqual(reproducible.manifest.entries[0].metadata.modificationTimeNanoseconds, 0)

        assertPlanningError(.unsupportedCodec(ArchiveGenerationCodec(format: .sevenZip, compression: .lzma))) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: [file], options: ArchiveGenerationOutputOptions(format: .sevenZip, compression: .lzma, compressionLevel: 5))
            )
        }
        let allCapabilities = ArchiveGenerationExecutorCapabilities(
            identifier: "all-codecs",
            revision: 1,
            codecs: Set(
                ArchiveGenerationContainerFormat.allCases.flatMap { format in
                    ArchiveGenerationCompressionMethod.allCases.map {
                        ArchiveGenerationCodec(format: format, compression: $0)
                    }
                }
            )
        )
        let invalidCompressionCases = [
            ArchiveGenerationOutputOptions(compression: .store, compressionLevel: 0),
            ArchiveGenerationOutputOptions(compression: .deflate),
            ArchiveGenerationOutputOptions(compression: .deflate, compressionLevel: -1),
            ArchiveGenerationOutputOptions(compression: .deflate, compressionLevel: 10),
            ArchiveGenerationOutputOptions(compression: .bzip2),
            ArchiveGenerationOutputOptions(compression: .bzip2, compressionLevel: -1),
            ArchiveGenerationOutputOptions(compression: .bzip2, compressionLevel: 10),
            ArchiveGenerationOutputOptions(compression: .lzma),
            ArchiveGenerationOutputOptions(compression: .lzma, compressionLevel: -1),
            ArchiveGenerationOutputOptions(compression: .lzma, compressionLevel: 10),
            ArchiveGenerationOutputOptions(compression: .zstandard),
            ArchiveGenerationOutputOptions(compression: .zstandard, compressionLevel: 0),
            ArchiveGenerationOutputOptions(compression: .zstandard, compressionLevel: 23)
        ]
        for options in invalidCompressionCases {
            assertPlanningError(.invalidCompressionLevel) {
                try ArchiveGenerationWorkflow.plan(
                    makeRequest(entries: [file], options: options, capabilities: allCapabilities)
                )
            }
        }
        for options in [
            ArchiveGenerationOutputOptions(compression: .store),
            ArchiveGenerationOutputOptions(compression: .deflate, compressionLevel: 0),
            ArchiveGenerationOutputOptions(compression: .deflate, compressionLevel: 9),
            ArchiveGenerationOutputOptions(compression: .bzip2, compressionLevel: 0),
            ArchiveGenerationOutputOptions(compression: .bzip2, compressionLevel: 9),
            ArchiveGenerationOutputOptions(compression: .lzma, compressionLevel: 0),
            ArchiveGenerationOutputOptions(compression: .lzma, compressionLevel: 9),
            ArchiveGenerationOutputOptions(compression: .zstandard, compressionLevel: 1),
            ArchiveGenerationOutputOptions(compression: .zstandard, compressionLevel: 22)
        ] {
            XCTAssertNoThrow(
                try ArchiveGenerationWorkflow.plan(
                    makeRequest(entries: [file], options: options, capabilities: allCapabilities)
                )
            )
        }
        for permissions in [UInt16(0x1000), 0x8000, 0xF000] {
            assertPlanningError(.invalidPermissions(permissions)) {
                try ArchiveGenerationWorkflow.plan(
                    makeRequest(
                        entries: [file],
                        options: ArchiveGenerationOutputOptions(destinationPermissions: permissions)
                    )
                )
            }
        }
        assertPlanningError(.invalidArchiveComment) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: [file], options: ArchiveGenerationOutputOptions(archiveComment: "bad\0comment"))
            )
        }
    }

    func testEveryConfiguredLimitRejectsZeroOrHardMaximumOverflow() throws {
        let zeroCases: [(ArchiveGenerationLimit, ArchiveGenerationLimits)] = [
            (.snapshotEntries, limits(maximumSnapshotEntries: 0)),
            (.selectedEntries, limits(maximumSelectedEntries: 0)),
            (.filterRules, limits(maximumFilterRules: 0)),
            (.identifierUTF8Bytes, limits(maximumIdentifierUTF8Bytes: 0)),
            (.pathUTF8Bytes, limits(maximumPathUTF8Bytes: 0)),
            (.pathDepth, limits(maximumPathDepth: 0)),
            (.totalPathUTF8Bytes, limits(maximumTotalPathUTF8Bytes: 0)),
            (.totalPathComponents, limits(maximumTotalPathComponents: 0)),
            (.itemBytes, limits(maximumItemBytes: 0)),
            (.totalSourceBytes, limits(maximumTotalSourceBytes: 0)),
            (.metadataBytes, limits(maximumMetadataBytes: 0)),
            (.archiveBytes, limits(maximumArchiveBytes: 0)),
            (.optionUTF8Bytes, limits(maximumOptionUTF8Bytes: 0)),
            (.retainedPlanBytes, limits(maximumRetainedPlanBytes: 0)),
            (.workUnits, limits(maximumWorkUnits: 0)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0))
        ]
        let overflowCases: [(ArchiveGenerationLimit, ArchiveGenerationLimits)] = [
            (.snapshotEntries, limits(maximumSnapshotEntries: ArchiveGenerationLimits.hardMaximumSnapshotEntries + 1)),
            (.selectedEntries, limits(maximumSelectedEntries: ArchiveGenerationLimits.hardMaximumSelectedEntries + 1)),
            (.filterRules, limits(maximumFilterRules: ArchiveGenerationLimits.hardMaximumFilterRules + 1)),
            (.identifierUTF8Bytes, limits(maximumIdentifierUTF8Bytes: ArchiveGenerationLimits.hardMaximumIdentifierUTF8Bytes + 1)),
            (.pathUTF8Bytes, limits(maximumPathUTF8Bytes: ArchiveGenerationLimits.hardMaximumPathUTF8Bytes + 1)),
            (.pathDepth, limits(maximumPathDepth: ArchiveGenerationLimits.hardMaximumPathDepth + 1)),
            (.totalPathUTF8Bytes, limits(maximumTotalPathUTF8Bytes: ArchiveGenerationLimits.hardMaximumTotalPathUTF8Bytes + 1)),
            (.totalPathComponents, limits(maximumTotalPathComponents: ArchiveGenerationLimits.hardMaximumTotalPathComponents + 1)),
            (.itemBytes, limits(maximumItemBytes: ArchiveGenerationLimits.hardMaximumItemBytes + 1)),
            (.totalSourceBytes, limits(maximumTotalSourceBytes: ArchiveGenerationLimits.hardMaximumTotalSourceBytes + 1)),
            (.metadataBytes, limits(maximumMetadataBytes: ArchiveGenerationLimits.hardMaximumMetadataBytes + 1)),
            (.archiveBytes, limits(maximumArchiveBytes: ArchiveGenerationLimits.hardMaximumArchiveBytes + 1)),
            (.optionUTF8Bytes, limits(maximumOptionUTF8Bytes: ArchiveGenerationLimits.hardMaximumOptionUTF8Bytes + 1)),
            (.retainedPlanBytes, limits(maximumRetainedPlanBytes: ArchiveGenerationLimits.hardMaximumRetainedPlanBytes + 1)),
            (.workUnits, limits(maximumWorkUnits: ArchiveGenerationLimits.hardMaximumWorkUnits + 1)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 65_537))
        ]
        XCTAssertEqual(Set(zeroCases.map(\.0)), Set(ArchiveGenerationLimit.allCases))
        XCTAssertEqual(Set(overflowCases.map(\.0)), Set(ArchiveGenerationLimit.allCases))
        for (limit, invalidLimits) in zeroCases + overflowCases {
            assertPlanningError(.invalidLimit(limit)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(limits: invalidLimits))
            }
        }
    }

    func testEveryConfiguredLimitAcceptsItsHardMaximum() throws {
        let maximumCases: [ArchiveGenerationLimits] = [
            limits(maximumSnapshotEntries: ArchiveGenerationLimits.hardMaximumSnapshotEntries),
            limits(maximumSelectedEntries: ArchiveGenerationLimits.hardMaximumSelectedEntries),
            limits(maximumFilterRules: ArchiveGenerationLimits.hardMaximumFilterRules),
            limits(maximumIdentifierUTF8Bytes: ArchiveGenerationLimits.hardMaximumIdentifierUTF8Bytes),
            limits(maximumPathUTF8Bytes: ArchiveGenerationLimits.hardMaximumPathUTF8Bytes),
            limits(maximumPathDepth: ArchiveGenerationLimits.hardMaximumPathDepth),
            limits(maximumTotalPathUTF8Bytes: ArchiveGenerationLimits.hardMaximumTotalPathUTF8Bytes),
            limits(maximumTotalPathComponents: ArchiveGenerationLimits.hardMaximumTotalPathComponents),
            limits(maximumItemBytes: ArchiveGenerationLimits.hardMaximumItemBytes),
            limits(maximumTotalSourceBytes: ArchiveGenerationLimits.hardMaximumTotalSourceBytes),
            limits(maximumMetadataBytes: ArchiveGenerationLimits.hardMaximumMetadataBytes),
            limits(maximumArchiveBytes: ArchiveGenerationLimits.hardMaximumArchiveBytes),
            limits(maximumOptionUTF8Bytes: ArchiveGenerationLimits.hardMaximumOptionUTF8Bytes),
            limits(maximumRetainedPlanBytes: ArchiveGenerationLimits.hardMaximumRetainedPlanBytes),
            limits(maximumWorkUnits: ArchiveGenerationLimits.hardMaximumWorkUnits),
            limits(cancellationCheckInterval: 65_536)
        ]
        XCTAssertEqual(maximumCases.count, ArchiveGenerationLimit.allCases.count)
        for maximumLimits in maximumCases {
            XCTAssertNoThrow(try ArchiveGenerationWorkflow.plan(makeRequest(limits: maximumLimits)))
        }
    }

    func testExactIdentifierPathOptionAndFilterRuleBoundaries() throws {
        let exactID = String(repeating: "i", count: 8)
        let exactPath = String(repeating: "p", count: 12)
        let exactComment = String(repeating: "c", count: 10)
        let file = entry(id: exactID, path: exactPath, status: .leftOnly, left: source(path: exactPath, seed: 230))
        let exactLimits = limits(
            maximumFilterRules: 1,
            maximumIdentifierUTF8Bytes: 8,
            maximumPathUTF8Bytes: 64,
            maximumOptionUTF8Bytes: 10
        )
        let capabilities = ArchiveGenerationExecutorCapabilities(
            identifier: "x",
            revision: 1,
            codecs: [ArchiveGenerationCodec(format: .zip, compression: .store)]
        )
        let filter = ArchiveGenerationFilterPolicy(
            pathRules: [ArchiveGenerationPathRule(action: .include, match: .exact(exactPath))],
            pathComparison: .caseSensitive
        )
        XCTAssertNoThrow(
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [file],
                    inclusion: ArchiveGenerationInclusionPolicy(filter: filter),
                    options: ArchiveGenerationOutputOptions(archiveComment: exactComment),
                    capabilities: capabilities,
                    limits: exactLimits
                )
            )
        )

        let overID = exactID + "x"
        assertPlanningError(.invalidEntryIdentifier(overID)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [entry(id: overID, path: exactPath, status: .leftOnly, left: source(path: exactPath, seed: 231))],
                    limits: exactLimits
                )
            )
        }
        let overPath = String(repeating: "p", count: 65)
        let exactArchivePath = String(repeating: "p", count: 64)
        XCTAssertNoThrow(
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [file],
                    selection: .only([
                        ArchiveGenerationSelectedEntry(
                            id: file.id,
                            side: .left,
                            archiveRelativePath: exactArchivePath
                        )
                    ]),
                    capabilities: capabilities,
                    limits: exactLimits
                )
            )
        )
        assertPlanningError(.invalidPath(role: .archive, path: overPath, issue: .pathTooLong)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [file],
                    selection: .only([
                        ArchiveGenerationSelectedEntry(
                            id: file.id,
                            side: .left,
                            archiveRelativePath: overPath
                        )
                    ]),
                    capabilities: capabilities,
                    limits: exactLimits
                )
            )
        }
        assertPlanningError(.invalidArchiveComment) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [file],
                    options: ArchiveGenerationOutputOptions(archiveComment: exactComment + "x"),
                    capabilities: capabilities,
                    limits: exactLimits
                )
            )
        }
        let twoRules = filter.pathRules + [ArchiveGenerationPathRule(action: .exclude, match: .exact(exactPath))]
        assertPlanningError(.tooManyFilterRules(maximum: 1)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(
                    entries: [file],
                    inclusion: ArchiveGenerationInclusionPolicy(filter: ArchiveGenerationFilterPolicy(pathRules: twoRules)),
                    capabilities: capabilities,
                    limits: exactLimits
                )
            )
        }
    }

    func testExactItemAggregateMetadataPathAndComponentBoundaries() throws {
        let first = entry(id: "first", path: "a-one", status: .leftOnly, left: source(path: "a-one", seed: 240, byteCount: 4, metadataByteCount: 3))
        let second = entry(id: "second", path: "b-two", status: .leftOnly, left: source(path: "b-two", seed: 241, byteCount: 5, metadataByteCount: 4))
        let exact = limits(
            maximumTotalPathUTF8Bytes: 10,
            maximumTotalPathComponents: 2,
            maximumItemBytes: 5,
            maximumTotalSourceBytes: 9,
            maximumMetadataBytes: 7
        )
        XCTAssertNoThrow(try ArchiveGenerationWorkflow.plan(makeRequest(entries: [first, second], limits: exact)))

        assertPlanningError(.itemTooLarge(path: "b-two", maximumBytes: 4)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [first, second], limits: limits(maximumItemBytes: 4)))
        }
        assertPlanningError(.sourceBytesTooLarge(maximumBytes: 8)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [first, second], limits: limits(maximumTotalSourceBytes: 8)))
        }
        assertPlanningError(.metadataTooLarge(maximumBytes: 6)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [first, second], limits: limits(maximumMetadataBytes: 6)))
        }
        assertPlanningError(.totalPathsTooLarge(maximumBytes: 9)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [first, second], limits: limits(maximumTotalPathUTF8Bytes: 9)))
        }
        assertPlanningError(.tooManyPathComponents(maximum: 1)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [first, second], limits: limits(maximumTotalPathComponents: 1)))
        }
    }

    func testStoredZIPPlanningEnvelopeHasExactOutputBoundary() throws {
        let file = entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 250, byteCount: 3))
        let baseline = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file]))
        let exact = baseline.manifest.planningArchiveByteEnvelope
        XCTAssertEqual(exact, 3 + UInt64("file.txt".utf8.count * 2) + 1_024 + 1_048_576)
        XCTAssertNoThrow(
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], limits: limits(maximumArchiveBytes: exact)))
        )
        assertPlanningError(.archiveSizeLimitExceeded(maximumBytes: exact - 1)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], limits: limits(maximumArchiveBytes: exact - 1)))
        }

        let compressedOptions = ArchiveGenerationOutputOptions(compression: .deflate, compressionLevel: 6)
        let compressed = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [file], options: compressedOptions, limits: limits(maximumArchiveBytes: 2_000_000))
        )
        XCTAssertEqual(compressed.manifest.planningArchiveByteEnvelope, 2_000_000)
    }

    func testWorkAndRetainedPlanBoundariesAcceptExactAndRejectOneBelow() throws {
        let file = entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 260))
        let baseline = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file]))
        let work = baseline.receipt.estimatedWorkUnits
        XCTAssertNoThrow(
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], limits: limits(maximumWorkUnits: work)))
        )
        assertPlanningError(.workLimitExceeded(maximumUnits: work - 1)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], limits: limits(maximumWorkUnits: work - 1)))
        }

        var low = 1
        var high = ArchiveGenerationLimits.default.maximumRetainedPlanBytes
        while low < high {
            let middle = low + (high - low) / 2
            do {
                _ = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], limits: limits(maximumRetainedPlanBytes: middle)))
                high = middle
            } catch let error as ArchiveGenerationPlanningError {
                guard error == .planTooLarge(maximumBytes: middle) else { throw error }
                low = middle + 1
            }
        }
        XCTAssertNoThrow(
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], limits: limits(maximumRetainedPlanBytes: low)))
        )
        assertPlanningError(.planTooLarge(maximumBytes: low - 1)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], limits: limits(maximumRetainedPlanBytes: low - 1)))
        }
    }

    func testMultiItemNLogNSortWorkAcceptsExactBoundaryAndRejectsOneBelow() throws {
        let entries = (0..<9).map { index in
            let path = String(format: "%02d.txt", 8 - index)
            return entry(
                id: "id-\(index)",
                path: path,
                status: .leftOnly,
                left: source(path: path, seed: 265 + UInt64(index))
            )
        }
        let baseline = try ArchiveGenerationWorkflow.plan(makeRequest(entries: entries))
        let exactWork = baseline.receipt.estimatedWorkUnits
        XCTAssertEqual(baseline.manifest.entries.map(\.archiveRelativePath), entries.map(\.relativePath).sorted())
        XCTAssertNoThrow(
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: entries, limits: limits(maximumWorkUnits: exactWork))
            )
        )
        assertPlanningError(.workLimitExceeded(maximumUnits: exactWork - 1)) {
            try ArchiveGenerationWorkflow.plan(
                makeRequest(entries: entries, limits: limits(maximumWorkUnits: exactWork - 1))
            )
        }
    }

    func testPlanningIsPureAndPrecancelledPlanningWinsBeforeInvalidInputs() async {
        let destinationURL = URL(filePath: "/tmp/archive-workflow-\(UUID().uuidString)/archive.zip")
        let request = makeRequest(
            entries: [],
            destination: createDestination(url: destinationURL, parentSeed: 270),
            limits: limits(maximumSnapshotEntries: 0)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        let task = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ArchiveGenerationWorkflow.plan(request)
        }
        do {
            _ = try await task.value
            XCTFail("Precancelled planning unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? ArchiveGenerationPlanningError, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testSnapshotCASRejectsStaleReferenceAndSameGenerationContentMutation() throws {
        let originalEntry = entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 280))
        let snapshot = makeSnapshot(entries: [originalEntry])
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: snapshot))
        XCTAssertNoThrow(try plan.validateCurrentSnapshot(snapshot))

        let otherIdentity = ArchiveGenerationComparisonSnapshot(
            identity: ArchiveGenerationSnapshotIdentity(rawValue: UUID()),
            generation: snapshot.generation,
            comparisonKind: snapshot.comparisonKind,
            entries: snapshot.entries
        )
        assertPlanningError(
            .staleSnapshot(expected: plan.snapshotCAS.reference, actual: ArchiveGenerationSnapshotReference(otherIdentity))
        ) {
            try plan.validateCurrentSnapshot(otherIdentity)
        }
        let otherGeneration = ArchiveGenerationComparisonSnapshot(
            identity: snapshot.identity,
            generation: snapshot.generation + 1,
            comparisonKind: snapshot.comparisonKind,
            entries: snapshot.entries
        )
        assertPlanningError(
            .staleSnapshot(expected: plan.snapshotCAS.reference, actual: ArchiveGenerationSnapshotReference(otherGeneration))
        ) {
            try plan.validateCurrentSnapshot(otherGeneration)
        }
        let changed = makeSnapshot(
            identity: snapshot.identity,
            generation: snapshot.generation,
            entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 281))]
        )
        assertPlanningError(.snapshotContentsChanged) {
            try plan.validateCurrentSnapshot(changed)
        }
    }

    func testValidateForPublicationRoutesThroughSnapshotCASValidation() throws {
        let original = entry(
            id: "file",
            path: "file.txt",
            status: .leftOnly,
            left: source(path: "file.txt", seed: 285)
        )
        let snapshot = makeSnapshot(entries: [original])
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: snapshot))
        let sources = plan.manifest.entries.map(\.source.revision)
        let parent = plan.destination.intent.canonicalParent
        let stale = makeSnapshot(
            identity: snapshot.identity,
            generation: snapshot.generation + 1,
            entries: snapshot.entries
        )
        assertPlanningError(
            .staleSnapshot(
                expected: plan.snapshotCAS.reference,
                actual: ArchiveGenerationSnapshotReference(stale)
            )
        ) {
            try plan.validateForPublication(
                currentSnapshot: stale,
                currentSources: sources,
                currentDestinationParent: parent,
                currentDestinationRevision: nil
            )
        }

        let changed = makeSnapshot(
            identity: snapshot.identity,
            generation: snapshot.generation,
            entries: [
                entry(
                    id: "file",
                    path: "file.txt",
                    status: .leftOnly,
                    left: source(path: "file.txt", seed: 286)
                )
            ]
        )
        assertPlanningError(.snapshotContentsChanged) {
            try plan.validateForPublication(
                currentSnapshot: changed,
                currentSources: sources,
                currentDestinationParent: parent,
                currentDestinationRevision: nil
            )
        }
    }

    func testPublicationValidationRequiresExactUniqueSourceSetAndRevision() throws {
        let first = source(path: "first.txt", seed: 290)
        let second = source(path: "second.txt", seed: 291)
        let snapshot = makeSnapshot(entries: [
            entry(id: "first", path: "first.txt", status: .leftOnly, left: first),
            entry(id: "second", path: "second.txt", status: .leftOnly, left: second)
        ])
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: snapshot))
        let parent = plan.destination.intent.canonicalParent

        XCTAssertNoThrow(
            try plan.validateForPublication(
                currentSnapshot: snapshot,
                currentSources: [second.revision, first.revision],
                currentDestinationParent: parent,
                currentDestinationRevision: nil
            )
        )
        assertPlanningError(.sourceSetChanged) {
            try plan.validateForPublication(
                currentSnapshot: snapshot,
                currentSources: [first.revision],
                currentDestinationParent: parent,
                currentDestinationRevision: nil
            )
        }
        assertPlanningError(.sourceSetChanged) {
            try plan.validateForPublication(
                currentSnapshot: snapshot,
                currentSources: [first.revision, first.revision],
                currentDestinationParent: parent,
                currentDestinationRevision: nil
            )
        }
        assertPlanningError(.sourceRevisionChanged(first.revision.identity.canonicalURL.path)) {
            try plan.validateForPublication(
                currentSnapshot: snapshot,
                currentSources: [revisionCopy(first.revision, flags: 1), second.revision],
                currentDestinationParent: parent,
                currentDestinationRevision: nil
            )
        }
    }

    func testPublicationSourceCASBindsEveryRevisionAndIdentityField() throws {
        let selected = source(path: "file.txt", seed: 295)
        let snapshot = makeSnapshot(entries: [
            entry(id: "file", path: "file.txt", status: .leftOnly, left: selected)
        ])
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: snapshot))
        let parent = plan.destination.intent.canonicalParent

        for mutation in scalarRevisionMutations(selected.revision) {
            assertPlanningError(.sourceRevisionChanged(selected.revision.identity.canonicalURL.path)) {
                try plan.validateForPublication(
                    currentSnapshot: snapshot,
                    currentSources: [mutation],
                    currentDestinationParent: parent,
                    currentDestinationRevision: nil
                )
            }
        }
        for mutation in identityRevisionMutations(selected.revision) {
            assertPlanningError(.sourceSetChanged) {
                try plan.validateForPublication(
                    currentSnapshot: snapshot,
                    currentSources: [mutation],
                    currentDestinationParent: parent,
                    currentDestinationRevision: nil
                )
            }
        }
    }

    func testPublicationValidationChecksCreateDestinationParentAndVacancy() throws {
        let snapshot = makeSnapshot(entries: [
            entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 300))
        ])
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: snapshot))
        let sourceRevisions = plan.manifest.entries.map(\.source.revision)
        let parent = plan.destination.intent.canonicalParent

        let changedParent = ArchiveGenerationCanonicalDirectoryIdentity(
            canonicalURL: parent.canonicalURL,
            node: node(301)
        )
        assertPlanningError(.destinationParentChanged) {
            try plan.validateForPublication(
                currentSnapshot: snapshot,
                currentSources: sourceRevisions,
                currentDestinationParent: changedParent,
                currentDestinationRevision: nil
            )
        }
        assertPlanningError(.destinationChanged) {
            try plan.validateForPublication(
                currentSnapshot: snapshot,
                currentSources: sourceRevisions,
                currentDestinationParent: parent,
                currentDestinationRevision: replacementRevision(parent: parent, seed: 302)
            )
        }
    }

    func testPublicationValidationChecksReplaceDestinationFullCASAndAlias() throws {
        let selected = source(path: "file.txt", seed: 310)
        let snapshot = makeSnapshot(entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: selected)])
        let parent = root(path: "/output", seed: 311)
        let expected = replacementRevision(parent: parent, seed: 312)
        let destination = ArchiveGenerationDestination(requestedURL: expected.identity.canonicalURL, intent: .replaceExisting(expected))
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: snapshot, destination: destination))

        XCTAssertNoThrow(
            try plan.validateForPublication(
                currentSnapshot: snapshot,
                currentSources: [selected.revision],
                currentDestinationParent: parent,
                currentDestinationRevision: expected
            )
        )
        for current in [nil, revisionCopy(expected, metadataSHA256: digest("changed"))] {
            assertPlanningError(.destinationChanged) {
                try plan.validateForPublication(
                    currentSnapshot: snapshot,
                    currentSources: [selected.revision],
                    currentDestinationParent: parent,
                    currentDestinationRevision: current
                )
            }
        }

        let aliasIdentity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: expected.identity.canonicalURL,
            root: parent,
            relativePath: expected.identity.relativePath,
            kind: .regularFile,
            node: selected.revision.identity.node
        )
        let aliasExpected = revisionCopy(expected, identity: aliasIdentity)
        let aliasDestination = ArchiveGenerationDestination(
            requestedURL: aliasExpected.identity.canonicalURL,
            intent: .replaceExisting(aliasExpected)
        )
        assertPlanningError(.destinationMatchesSource(aliasExpected.identity.canonicalURL.path)) {
            try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: snapshot, destination: aliasDestination))
        }

        let currentAliasIdentity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: expected.identity.canonicalURL,
            root: expected.identity.root,
            relativePath: expected.identity.relativePath,
            kind: expected.identity.kind,
            node: selected.revision.identity.node
        )
        assertPlanningError(.destinationChanged) {
            try plan.validateForPublication(
                currentSnapshot: snapshot,
                currentSources: [selected.revision],
                currentDestinationParent: parent,
                currentDestinationRevision: revisionCopy(expected, identity: currentAliasIdentity)
            )
        }
    }

    func testPublicationReplaceDestinationCASBindsEveryRevisionAndIdentityField() throws {
        let selected = source(path: "file.txt", seed: 314)
        let snapshot = makeSnapshot(entries: [
            entry(id: "file", path: "file.txt", status: .leftOnly, left: selected)
        ])
        let parent = root(path: "/output", seed: 315)
        let expected = replacementRevision(parent: parent, seed: 316)
        let destination = ArchiveGenerationDestination(
            requestedURL: expected.identity.canonicalURL,
            intent: .replaceExisting(expected)
        )
        let plan = try ArchiveGenerationWorkflow.plan(
            makeRequest(snapshot: snapshot, destination: destination)
        )

        for mutation in scalarRevisionMutations(expected) + identityRevisionMutations(expected) {
            assertPlanningError(.destinationChanged) {
                try plan.validateForPublication(
                    currentSnapshot: snapshot,
                    currentSources: [selected.revision],
                    currentDestinationParent: parent,
                    currentDestinationRevision: mutation
                )
            }
        }
    }

    func testPrepublicationCancellationMapsToDomainBeforeAnyCommitProof() async throws {
        let snapshot = makeSnapshot(entries: [
            entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 320))
        ])
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(snapshot: snapshot))
        let sources = plan.manifest.entries.map(\.source.revision)
        let parent = plan.destination.intent.canonicalParent
        try plan.validateCurrentSnapshot(snapshot)
        let task = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            try plan.validateForPublication(
                currentSnapshot: snapshot,
                currentSources: sources,
                currentDestinationParent: parent,
                currentDestinationRevision: nil
            )
        }
        do {
            try await task.value
            XCTFail("Prepublication cancellation unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? ArchiveGenerationPlanningError, .cancelled)
        }
    }

    func testExecutionOutcomeFactoriesBindPlanAndExposeCancellationFailureAndUncertainty() throws {
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest())
        let failed = ArchiveGenerationExecutionOutcomeFactory.failed(plan: plan, code: .publicationFailed)
        guard case .failed(let failure) = failed else { return XCTFail("Expected failure") }
        XCTAssertEqual(failure.code, .publicationFailed)
        XCTAssertEqual(failure.destinationURL, plan.destination.intent.canonicalURL)

        let cancelled = ArchiveGenerationExecutionOutcomeFactory.cancelled(plan: plan)
        guard case .cancelled(let cancellation) = cancelled else { return XCTFail("Expected cancellation") }
        XCTAssertFalse(cancellation.publicationStarted)

        let uncertain = ArchiveGenerationExecutionOutcomeFactory.publicationUncertain(plan: plan)
        guard case .publicationUncertain(let proof) = uncertain else { return XCTFail("Expected uncertainty") }
        XCTAssertEqual(proof.destinationURL, plan.destination.intent.canonicalURL)
        XCTAssertEqual(proof.planSHA256, plan.receipt.planSHA256)
    }

    func testCompletedOutcomeValidatesExactCommittedRevisionAndReceipt() throws {
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest())
        let content = digest("archive bytes")
        let committed = committedRevision(plan: plan, seed: 330, byteCount: 123, contentSHA256: content)
        let outcome = ArchiveGenerationExecutionOutcomeFactory.completed(
            plan: plan,
            committedRevision: committed,
            archiveContentSHA256: content
        )
        guard case .completed(let receipt) = outcome else { return XCTFail("Expected completed outcome") }
        XCTAssertEqual(receipt.planSHA256, plan.receipt.planSHA256)
        XCTAssertEqual(receipt.disposition, .created)
        XCTAssertEqual(receipt.committedByteCount, 123)
        XCTAssertEqual(receipt.archiveContentSHA256, content)
        XCTAssertEqual(receipt.archivedItemCount, plan.manifest.entries.count)
        XCTAssertEqual(receipt.archivedSourceByteCount, plan.manifest.totalUncompressedByteCount)
        XCTAssertEqual(ArchiveGenerationExecutionReceipt.version, 2)

        let parent = root(path: "/replace", seed: 331)
        let expected = replacementRevision(parent: parent, seed: 332, leaf: "archive.zip")
        let replacePlan = try ArchiveGenerationWorkflow.plan(
            makeRequest(destination: ArchiveGenerationDestination(requestedURL: expected.identity.canonicalURL, intent: .replaceExisting(expected)))
        )
        let replaceCommitted = committedRevision(plan: replacePlan, seed: 333, byteCount: 100, contentSHA256: content)
        guard
            case .completed(let replaceReceipt) = ArchiveGenerationExecutionOutcomeFactory.completed(
                plan: replacePlan,
                committedRevision: replaceCommitted,
                archiveContentSHA256: content
            )
        else { return XCTFail("Expected replacement completion") }
        XCTAssertEqual(replaceReceipt.disposition, .replaced)
    }

    func testCompletedOutcomeFailsClosedToPublicationUncertaintyForEveryProofMismatch() throws {
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest())
        let content = digest("archive")
        let valid = committedRevision(plan: plan, seed: 340, byteCount: 100, contentSHA256: content)
        let wrongRoot = root(path: "/other", seed: 341)
        let wrongIdentity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: valid.identity.canonicalURL,
            root: wrongRoot,
            relativePath: valid.identity.relativePath,
            kind: .regularFile,
            node: valid.identity.node
        )
        let invalid = [
            revisionCopy(valid, identity: wrongIdentity),
            revisionCopy(valid, linkCount: 0),
            revisionCopy(valid, permissions: 0o644),
            revisionCopy(valid, byteCount: plan.manifest.planningArchiveByteEnvelope + 1),
            revisionCopy(valid, contentSHA256: digest("other")),
            revisionCopy(valid, metadataSHA256: [0])
        ]
        for revision in invalid {
            let outcome = ArchiveGenerationExecutionOutcomeFactory.completed(
                plan: plan,
                committedRevision: revision,
                archiveContentSHA256: content
            )
            guard case .publicationUncertain(let proof) = outcome else {
                XCTFail("Invalid committed proof did not become uncertainty")
                continue
            }
            XCTAssertEqual(proof.planSHA256, plan.receipt.planSHA256)
            XCTAssertEqual(proof.destinationURL, plan.destination.intent.canonicalURL)
        }
        guard
            case .publicationUncertain = ArchiveGenerationExecutionOutcomeFactory.completed(
                plan: plan,
                committedRevision: valid,
                archiveContentSHA256: [0]
            )
        else { return XCTFail("Invalid content digest did not become uncertainty") }
    }

    func testCompletedOutcomeRequiresExactDestinationRootPathNodeAndUnequalValidDigestFailsClosed() throws {
        let sourceItem = source(path: "file.txt", seed: 345)
        let plan = try ArchiveGenerationWorkflow.plan(
            makeRequest(entries: [entry(id: "file", path: "file.txt", status: .leftOnly, left: sourceItem)])
        )
        let archiveDigest = digest("archive-a")
        let valid = committedRevision(
            plan: plan,
            seed: 346,
            byteCount: 100,
            contentSHA256: archiveDigest
        )
        let destination = plan.destination.intent.canonicalURL
        let parent = plan.destination.intent.canonicalParent
        let wrongRootNode = ArchiveGenerationCanonicalDirectoryIdentity(
            canonicalURL: parent.canonicalURL,
            node: ArchiveGenerationNodeIdentity(
                deviceID: parent.node.deviceID + 1,
                fileID: parent.node.fileID,
                generation: parent.node.generation
            )
        )
        let wrongRootPath = ArchiveGenerationCanonicalDirectoryIdentity(
            canonicalURL: URL(filePath: "/other"),
            node: parent.node
        )
        let identities = [
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: URL(filePath: "/output/other.zip"),
                root: parent,
                relativePath: "other.zip",
                kind: .regularFile,
                node: valid.identity.node
            ),
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: destination,
                root: wrongRootNode,
                relativePath: destination.lastPathComponent,
                kind: .regularFile,
                node: valid.identity.node
            ),
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: destination,
                root: wrongRootPath,
                relativePath: destination.lastPathComponent,
                kind: .regularFile,
                node: valid.identity.node
            ),
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: destination,
                root: parent,
                relativePath: "other.zip",
                kind: .regularFile,
                node: valid.identity.node
            ),
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: destination,
                root: parent,
                relativePath: destination.lastPathComponent,
                kind: .directory,
                node: valid.identity.node
            ),
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: destination,
                root: parent,
                relativePath: destination.lastPathComponent,
                kind: .regularFile,
                node: sourceItem.revision.identity.node
            )
        ]
        for identity in identities {
            assertPublicationUncertain(
                ArchiveGenerationExecutionOutcomeFactory.completed(
                    plan: plan,
                    committedRevision: revisionCopy(valid, identity: identity),
                    archiveContentSHA256: archiveDigest
                ),
                plan: plan
            )
        }
        let unequalValidDigest = digest("archive-b")
        XCTAssertEqual(unequalValidDigest.count, SHA256.Digest.byteCount)
        XCTAssertNotEqual(unequalValidDigest, archiveDigest)
        assertPublicationUncertain(
            ArchiveGenerationExecutionOutcomeFactory.completed(
                plan: plan,
                committedRevision: valid,
                archiveContentSHA256: unequalValidDigest
            ),
            plan: plan
        )
    }

    func testManifestComputedTotalsAndEntryKindsUseExactPublicBoundaries() throws {
        let directory = entry(
            id: "directory",
            path: "directory",
            status: .leftOnly,
            left: source(path: "directory", kind: .directory, seed: 350)
        )
        let file = entry(id: "file", path: "file", status: .leftOnly, left: source(path: "file", seed: 351, byteCount: 8, metadataByteCount: 9))
        let plan = try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file, directory]))
        let byPath = Dictionary(uniqueKeysWithValues: plan.manifest.entries.map { ($0.archiveRelativePath, $0) })

        XCTAssertEqual(byPath["directory"]?.kind, .directory)
        XCTAssertEqual(byPath["directory"]?.uncompressedByteCount, 0)
        XCTAssertEqual(byPath["file"]?.kind, .regularFile)
        XCTAssertEqual(byPath["file"]?.uncompressedByteCount, 8)
        XCTAssertEqual(plan.manifest.totalUncompressedByteCount, 8)
        XCTAssertEqual(plan.manifest.totalMetadataByteCount, 16)
        XCTAssertEqual(plan.receipt.sourceByteCount, 8)
        XCTAssertGreaterThan(plan.receipt.estimatedWorkUnits, 0)
    }

    func testFileURLPreflightRejectsHostCredentialsQueryCanonicalAndRootConfusion() throws {
        let file = entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 360))
        let parent = root(path: "/output", seed: 361)
        let cases: [(URL, ArchiveGenerationURLIssue)] = [
            (URL(string: "https://example.com/archive.zip")!, .notFileURL),
            (URL(string: "file:archive.zip")!, .relativeURL),
            (URL(string: "file://example.com/output/archive.zip")!, .remoteHost),
            (URL(string: "file://user@localhost/output/archive.zip")!, .credentialsOrPort),
            (URL(string: "file:///output/archive.zip?x=1")!, .queryOrFragment),
            (URL(filePath: "/output/../output/archive.zip"), .notCanonical)
        ]
        for (url, issue) in cases {
            let destination = ArchiveGenerationDestination(
                requestedURL: URL(filePath: "/output/archive.zip"),
                intent: .createNew(ArchiveGenerationCanonicalDestinationLocation(canonicalURL: url, parent: parent))
            )
            assertPlanningError(.invalidURL(role: .canonicalDestination, issue: issue)) {
                try ArchiveGenerationWorkflow.plan(makeRequest(entries: [file], destination: destination))
            }
        }
    }

    private let snapshotIdentity = ArchiveGenerationSnapshotIdentity(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )

    private func makeRequest(
        snapshot: ArchiveGenerationComparisonSnapshot? = nil,
        entries: [ArchiveGenerationComparisonEntry]? = nil,
        selection: ArchiveGenerationSelection = .all(side: .left),
        inclusion: ArchiveGenerationInclusionPolicy = .secureDefault,
        options: ArchiveGenerationOutputOptions = ArchiveGenerationOutputOptions(),
        destination: ArchiveGenerationDestination? = nil,
        capabilities: ArchiveGenerationExecutorCapabilities = .portableBaseline,
        limits: ArchiveGenerationLimits = .default
    ) -> ArchiveGenerationRequest {
        let resolvedSnapshot =
            snapshot
            ?? makeSnapshot(
                entries: entries ?? [
                    entry(id: "file", path: "file.txt", status: .leftOnly, left: source(path: "file.txt", seed: 900))
                ])
        return ArchiveGenerationRequest(
            snapshot: resolvedSnapshot,
            selection: selection,
            inclusionPolicy: inclusion,
            outputOptions: options,
            destination: destination ?? createDestination(),
            executorCapabilities: capabilities,
            limits: limits
        )
    }

    private func makeSnapshot(
        identity: ArchiveGenerationSnapshotIdentity? = nil,
        generation: UInt64 = 7,
        kind: ArchiveGenerationComparisonKind = .folder,
        entries: [ArchiveGenerationComparisonEntry]
    ) -> ArchiveGenerationComparisonSnapshot {
        ArchiveGenerationComparisonSnapshot(
            identity: identity ?? snapshotIdentity,
            generation: generation,
            comparisonKind: kind,
            entries: entries
        )
    }

    private func entry(
        id: String,
        path: String,
        status: ArchiveGenerationComparisonStatus,
        left: ArchiveGenerationSourceItem? = nil,
        right: ArchiveGenerationSourceItem? = nil,
        hidden: Bool = false
    ) -> ArchiveGenerationComparisonEntry {
        ArchiveGenerationComparisonEntry(
            id: ArchiveGenerationEntryID(rawValue: id),
            relativePath: path,
            status: status,
            isHidden: hidden,
            left: left,
            right: right
        )
    }

    private func source(
        path: String,
        kind: ArchiveGenerationItemKind = .regularFile,
        seed: UInt64,
        root: ArchiveGenerationCanonicalDirectoryIdentity? = nil,
        children: [(String, ArchiveGenerationItemKind)] = [],
        byteCount: UInt64? = nil,
        metadataByteCount: UInt64 = 7,
        permissions: UInt16 = 0o640,
        modificationTimeSeconds: Int64 = 100,
        modificationTimeNanoseconds: Int32 = 200,
        contentSHA256: [UInt8]? = nil,
        authority: ArchiveGenerationAccessAuthority = .callerManagedWhenRequired
    ) -> ArchiveGenerationSourceItem {
        let sourceRoot = root ?? self.root(path: "/sources", seed: 800)
        let canonicalPath = sourceRoot.canonicalURL.path + "/" + path
        let encodedPath = canonicalPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let canonicalURL = URL(string: "file://" + encodedPath)!
        let identity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: canonicalURL,
            root: sourceRoot,
            relativePath: path,
            kind: kind,
            node: node(seed)
        )
        let isDirectory = kind == .directory
        let revision = ArchiveGenerationSourceRevision(
            identity: identity,
            byteCount: byteCount ?? (isDirectory ? 0 : 3),
            directoryChildCount: isDirectory ? UInt64(children.count) : 0,
            directoryChildNameUTF8ByteCount: isDirectory ? UInt64(children.reduce(0) { $0 + $1.0.utf8.count }) : 0,
            linkCount: 1,
            permissions: permissions,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            metadataByteCount: metadataByteCount,
            modificationTimeSeconds: modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds,
            statusChangeTimeSeconds: 300,
            statusChangeTimeNanoseconds: 400,
            contentSHA256: contentSHA256 ?? (isDirectory ? directoryDigest(children) : digest("content-\(seed)")),
            metadataSHA256: digest("metadata-\(seed)")
        )
        return ArchiveGenerationSourceItem(requestedURL: canonicalURL, revision: revision, accessAuthority: authority)
    }

    private func root(path: String, seed: UInt64) -> ArchiveGenerationCanonicalDirectoryIdentity {
        ArchiveGenerationCanonicalDirectoryIdentity(canonicalURL: URL(filePath: path), node: node(seed))
    }

    private func node(_ seed: UInt64) -> ArchiveGenerationNodeIdentity {
        ArchiveGenerationNodeIdentity(deviceID: seed + 1, fileID: seed + 2, generation: UInt32(truncatingIfNeeded: seed + 3))
    }

    private func createDestination(
        url: URL = URL(filePath: "/output/archive.zip"),
        parentSeed: UInt64 = 700,
        leaf: String? = nil
    ) -> ArchiveGenerationDestination {
        let resolvedURL = leaf.map { URL(filePath: "/output/\($0)") } ?? url
        let parent = root(path: resolvedURL.deletingLastPathComponent().path, seed: parentSeed)
        return ArchiveGenerationDestination(
            requestedURL: resolvedURL,
            intent: .createNew(ArchiveGenerationCanonicalDestinationLocation(canonicalURL: resolvedURL, parent: parent))
        )
    }

    private func replacementRevision(
        parent: ArchiveGenerationCanonicalDirectoryIdentity,
        seed: UInt64,
        leaf: String = "archive.zip"
    ) -> ArchiveGenerationSourceRevision {
        let identity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: URL(filePath: parent.canonicalURL.path + "/" + leaf),
            root: parent,
            relativePath: leaf,
            kind: .regularFile,
            node: node(seed)
        )
        return revision(identity: identity, byteCount: 12, contentSHA256: digest("old archive"))
    }

    private func committedRevision(
        plan: ArchiveGenerationPlan,
        seed: UInt64,
        byteCount: UInt64,
        contentSHA256: [UInt8]
    ) -> ArchiveGenerationSourceRevision {
        let parent = plan.destination.intent.canonicalParent
        let canonicalURL = plan.destination.intent.canonicalURL
        let identity = ArchiveGenerationCanonicalItemIdentity(
            canonicalURL: canonicalURL,
            root: parent,
            relativePath: canonicalURL.lastPathComponent,
            kind: .regularFile,
            node: node(seed)
        )
        return revision(
            identity: identity,
            byteCount: byteCount,
            permissions: plan.manifest.options.destinationPermissions,
            contentSHA256: contentSHA256
        )
    }

    private func revision(
        identity: ArchiveGenerationCanonicalItemIdentity,
        byteCount: UInt64 = 3,
        directoryChildCount: UInt64 = 0,
        directoryChildNameUTF8ByteCount: UInt64 = 0,
        linkCount: UInt64 = 1,
        permissions: UInt16 = 0o640,
        ownerID: UInt32 = 501,
        groupID: UInt32 = 20,
        flags: UInt32 = 0,
        metadataByteCount: UInt64 = 7,
        modificationTimeSeconds: Int64 = 100,
        modificationTimeNanoseconds: Int32 = 200,
        statusChangeTimeSeconds: Int64 = 300,
        statusChangeTimeNanoseconds: Int32 = 400,
        contentSHA256: [UInt8]? = nil,
        metadataSHA256: [UInt8]? = nil
    ) -> ArchiveGenerationSourceRevision {
        ArchiveGenerationSourceRevision(
            identity: identity,
            byteCount: byteCount,
            directoryChildCount: directoryChildCount,
            directoryChildNameUTF8ByteCount: directoryChildNameUTF8ByteCount,
            linkCount: linkCount,
            permissions: permissions,
            ownerID: ownerID,
            groupID: groupID,
            flags: flags,
            metadataByteCount: metadataByteCount,
            modificationTimeSeconds: modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds,
            contentSHA256: contentSHA256 ?? digest("content"),
            metadataSHA256: metadataSHA256 ?? digest("metadata")
        )
    }

    private func revisionCopy(
        _ value: ArchiveGenerationSourceRevision,
        identity: ArchiveGenerationCanonicalItemIdentity? = nil,
        byteCount: UInt64? = nil,
        directoryChildCount: UInt64? = nil,
        directoryChildNameUTF8ByteCount: UInt64? = nil,
        linkCount: UInt64? = nil,
        permissions: UInt16? = nil,
        ownerID: UInt32? = nil,
        groupID: UInt32? = nil,
        flags: UInt32? = nil,
        metadataByteCount: UInt64? = nil,
        modificationTimeSeconds: Int64? = nil,
        modificationTimeNanoseconds: Int32? = nil,
        statusChangeTimeSeconds: Int64? = nil,
        statusChangeTimeNanoseconds: Int32? = nil,
        contentSHA256: [UInt8]? = nil,
        metadataSHA256: [UInt8]? = nil
    ) -> ArchiveGenerationSourceRevision {
        revision(
            identity: identity ?? value.identity,
            byteCount: byteCount ?? value.byteCount,
            directoryChildCount: directoryChildCount ?? value.directoryChildCount,
            directoryChildNameUTF8ByteCount: directoryChildNameUTF8ByteCount ?? value.directoryChildNameUTF8ByteCount,
            linkCount: linkCount ?? value.linkCount,
            permissions: permissions ?? value.permissions,
            ownerID: ownerID ?? value.ownerID,
            groupID: groupID ?? value.groupID,
            flags: flags ?? value.flags,
            metadataByteCount: metadataByteCount ?? value.metadataByteCount,
            modificationTimeSeconds: modificationTimeSeconds ?? value.modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds ?? value.modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds ?? value.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds ?? value.statusChangeTimeNanoseconds,
            contentSHA256: contentSHA256 ?? value.contentSHA256,
            metadataSHA256: metadataSHA256 ?? value.metadataSHA256
        )
    }

    private func scalarRevisionMutations(
        _ value: ArchiveGenerationSourceRevision
    ) -> [ArchiveGenerationSourceRevision] {
        [
            revisionCopy(value, byteCount: value.byteCount + 1),
            revisionCopy(value, directoryChildCount: value.directoryChildCount + 1),
            revisionCopy(
                value,
                directoryChildNameUTF8ByteCount: value.directoryChildNameUTF8ByteCount + 1
            ),
            revisionCopy(value, linkCount: value.linkCount + 1),
            revisionCopy(value, permissions: value.permissions ^ 0o001),
            revisionCopy(value, ownerID: value.ownerID + 1),
            revisionCopy(value, groupID: value.groupID + 1),
            revisionCopy(value, flags: value.flags + 1),
            revisionCopy(value, metadataByteCount: value.metadataByteCount + 1),
            revisionCopy(value, modificationTimeSeconds: value.modificationTimeSeconds + 1),
            revisionCopy(
                value,
                modificationTimeNanoseconds: value.modificationTimeNanoseconds + 1
            ),
            revisionCopy(value, statusChangeTimeSeconds: value.statusChangeTimeSeconds + 1),
            revisionCopy(
                value,
                statusChangeTimeNanoseconds: value.statusChangeTimeNanoseconds + 1
            ),
            revisionCopy(value, contentSHA256: digest("changed content")),
            revisionCopy(value, metadataSHA256: digest("changed metadata"))
        ]
    }

    private func identityRevisionMutations(
        _ value: ArchiveGenerationSourceRevision
    ) -> [ArchiveGenerationSourceRevision] {
        let identity = value.identity
        let root = identity.root
        let rootURL = ArchiveGenerationCanonicalDirectoryIdentity(
            canonicalURL: URL(filePath: root.canonicalURL.path + "-changed"),
            node: root.node
        )
        let rootNodes = [
            ArchiveGenerationNodeIdentity(
                deviceID: root.node.deviceID + 1,
                fileID: root.node.fileID,
                generation: root.node.generation
            ),
            ArchiveGenerationNodeIdentity(
                deviceID: root.node.deviceID,
                fileID: root.node.fileID + 1,
                generation: root.node.generation
            ),
            ArchiveGenerationNodeIdentity(
                deviceID: root.node.deviceID,
                fileID: root.node.fileID,
                generation: root.node.generation + 1
            )
        ]
        let itemNodes = [
            ArchiveGenerationNodeIdentity(
                deviceID: identity.node.deviceID + 1,
                fileID: identity.node.fileID,
                generation: identity.node.generation
            ),
            ArchiveGenerationNodeIdentity(
                deviceID: identity.node.deviceID,
                fileID: identity.node.fileID + 1,
                generation: identity.node.generation
            ),
            ArchiveGenerationNodeIdentity(
                deviceID: identity.node.deviceID,
                fileID: identity.node.fileID,
                generation: identity.node.generation + 1
            )
        ]
        var identities = [
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: URL(filePath: identity.canonicalURL.path + "-changed"),
                root: root,
                relativePath: identity.relativePath,
                kind: identity.kind,
                node: identity.node
            ),
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: identity.canonicalURL,
                root: rootURL,
                relativePath: identity.relativePath,
                kind: identity.kind,
                node: identity.node
            ),
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: identity.canonicalURL,
                root: root,
                relativePath: identity.relativePath + "-changed",
                kind: identity.kind,
                node: identity.node
            ),
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: identity.canonicalURL,
                root: root,
                relativePath: identity.relativePath,
                kind: .symbolicLink,
                node: identity.node
            )
        ]
        identities += rootNodes.map {
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: identity.canonicalURL,
                root: ArchiveGenerationCanonicalDirectoryIdentity(
                    canonicalURL: root.canonicalURL,
                    node: $0
                ),
                relativePath: identity.relativePath,
                kind: identity.kind,
                node: identity.node
            )
        }
        identities += itemNodes.map {
            ArchiveGenerationCanonicalItemIdentity(
                canonicalURL: identity.canonicalURL,
                root: root,
                relativePath: identity.relativePath,
                kind: identity.kind,
                node: $0
            )
        }
        return identities.map { revisionCopy(value, identity: $0) }
    }

    private func item(_ revision: ArchiveGenerationSourceRevision) -> ArchiveGenerationSourceItem {
        ArchiveGenerationSourceItem(requestedURL: revision.identity.canonicalURL, revision: revision)
    }

    private func digest(_ value: String) -> [UInt8] {
        Array(SHA256.hash(data: Data(value.utf8)))
    }

    private func directoryDigest<S: Sequence>(_ children: S) -> [UInt8]
    where S.Element == (String, ArchiveGenerationItemKind) {
        let children = Array(children)
        var hasher = SHA256()
        appendFramed(Array("ArchiveGenerationDirectoryChildren/v1".utf8), to: &hasher)
        appendFramed(bigEndianBytes(UInt64(children.count)), to: &hasher)
        let sorted = children.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
        for (name, kind) in sorted {
            appendFramed(Array(name.utf8), to: &hasher)
            let tag: UInt8
            switch kind {
            case .regularFile: tag = 0
            case .directory: tag = 1
            case .symbolicLink: tag = 2
            case .specialFile: tag = 3
            }
            appendFramed([tag], to: &hasher)
        }
        return Array(hasher.finalize())
    }

    private func appendFramed(_ bytes: [UInt8], to hasher: inout SHA256) {
        hasher.update(data: Data(bigEndianBytes(UInt64(bytes.count))))
        hasher.update(data: Data(bytes))
    }

    private func bigEndianBytes(_ value: UInt64) -> [UInt8] {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value, Array.init)
    }

    private func limits(
        maximumSnapshotEntries: Int = ArchiveGenerationLimits.default.maximumSnapshotEntries,
        maximumSelectedEntries: Int = ArchiveGenerationLimits.default.maximumSelectedEntries,
        maximumFilterRules: Int = ArchiveGenerationLimits.default.maximumFilterRules,
        maximumIdentifierUTF8Bytes: Int = ArchiveGenerationLimits.default.maximumIdentifierUTF8Bytes,
        maximumPathUTF8Bytes: Int = ArchiveGenerationLimits.default.maximumPathUTF8Bytes,
        maximumPathDepth: Int = ArchiveGenerationLimits.default.maximumPathDepth,
        maximumTotalPathUTF8Bytes: Int = ArchiveGenerationLimits.default.maximumTotalPathUTF8Bytes,
        maximumTotalPathComponents: UInt64 = ArchiveGenerationLimits.default.maximumTotalPathComponents,
        maximumItemBytes: UInt64 = ArchiveGenerationLimits.default.maximumItemBytes,
        maximumTotalSourceBytes: UInt64 = ArchiveGenerationLimits.default.maximumTotalSourceBytes,
        maximumMetadataBytes: UInt64 = ArchiveGenerationLimits.default.maximumMetadataBytes,
        maximumArchiveBytes: UInt64 = ArchiveGenerationLimits.default.maximumArchiveBytes,
        maximumOptionUTF8Bytes: Int = ArchiveGenerationLimits.default.maximumOptionUTF8Bytes,
        maximumRetainedPlanBytes: Int = ArchiveGenerationLimits.default.maximumRetainedPlanBytes,
        maximumWorkUnits: UInt64 = ArchiveGenerationLimits.default.maximumWorkUnits,
        cancellationCheckInterval: Int = ArchiveGenerationLimits.default.cancellationCheckInterval
    ) -> ArchiveGenerationLimits {
        ArchiveGenerationLimits(
            maximumSnapshotEntries: maximumSnapshotEntries,
            maximumSelectedEntries: maximumSelectedEntries,
            maximumFilterRules: maximumFilterRules,
            maximumIdentifierUTF8Bytes: maximumIdentifierUTF8Bytes,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes,
            maximumPathDepth: maximumPathDepth,
            maximumTotalPathUTF8Bytes: maximumTotalPathUTF8Bytes,
            maximumTotalPathComponents: maximumTotalPathComponents,
            maximumItemBytes: maximumItemBytes,
            maximumTotalSourceBytes: maximumTotalSourceBytes,
            maximumMetadataBytes: maximumMetadataBytes,
            maximumArchiveBytes: maximumArchiveBytes,
            maximumOptionUTF8Bytes: maximumOptionUTF8Bytes,
            maximumRetainedPlanBytes: maximumRetainedPlanBytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func assertPlanningError<T>(
        _ expected: ArchiveGenerationPlanningError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ArchiveGenerationPlanningError, expected, file: file, line: line)
        }
    }

    private func assertPlanningErrorMatching<T>(
        _ matches: (ArchiveGenerationPlanningError) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard let planningError = error as? ArchiveGenerationPlanningError else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            XCTAssertTrue(matches(planningError), "Unexpected error: \(planningError)", file: file, line: line)
        }
    }

    private func assertPublicationUncertain(
        _ outcome: ArchiveGenerationExecutionOutcome,
        plan: ArchiveGenerationPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .publicationUncertain(let proof) = outcome else {
            return XCTFail("Expected publication uncertainty", file: file, line: line)
        }
        XCTAssertEqual(proof.destinationURL, plan.destination.intent.canonicalURL, file: file, line: line)
        XCTAssertEqual(proof.planSHA256, plan.receipt.planSHA256, file: file, line: line)
    }
}
