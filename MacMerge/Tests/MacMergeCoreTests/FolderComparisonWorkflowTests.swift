import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class FolderComparisonWorkflowTests: XCTestCase {
    func testComparePlanPreservesRootsScanSettingsContractsAndRoutedPlan() throws {
        let roots = makeRoots()
        let filter = FolderComparisonScanFilter(
            rules: [
                FilenameFilterRule(
                    .exclude,
                    pattern: .glob("**/*.tmp"),
                    applicability: .files
                )
            ],
            defaultDecision: .include,
            matchSemantics: .firstMatchWins,
            casePolicy: .insensitive,
            limits: FilenameFilterLimits(
                maximumRuleCount: 4,
                maximumPatternUTF8Bytes: 64,
                maximumTotalPatternUTF8Bytes: 128,
                maximumRelativePathUTF8Bytes: 64,
                maximumCompiledStateCount: 256,
                maximumMatchWork: 16,
                maximumRegularExpressionNestingDepth: 8,
                maximumRegularExpressionRepetition: 16
            )
        )
        let scan = makeScanIntent(recursive: true, maximumExaminedEntries: 16, filter: filter)
        let settings = FolderComparisonSettings(
            method: .contentRequired,
            pathCaseSensitivity: .insensitive,
            modificationDateTolerance: 0.25
        )
        let target = FolderComparisonWorkflowSnapshotTarget(
            identity: snapshotIdentity,
            generation: 0,
            owner: FolderComparisonWorkflowSnapshotOwner(identity: snapshotOwnerID, revision: 0)
        )
        let request = FolderComparisonCompareRequest(
            target: target,
            roots: roots,
            scanIntent: scan,
            comparisonSettings: settings,
            capabilities: capabilities
        )

        let plan = try FolderComparisonWorkflowPlanner.planComparison(request)

        XCTAssertEqual(plan.target, target)
        XCTAssertNil(plan.replacing)
        XCTAssertEqual(plan.roots, roots)
        XCTAssertEqual(plan.scanIntent, scan)
        XCTAssertEqual(plan.comparisonSettings, settings)
        XCTAssertEqual(plan.capabilities, capabilities)
        XCTAssertEqual(plan.limits, .default)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(plan.receipt.planSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(plan.receipt.inputItemCount, 0)
        XCTAssertEqual(plan.receipt.outputItemCount, 2)
        XCTAssertGreaterThan(plan.receipt.estimatedWorkUnits, 0)
        XCTAssertNoThrow(try plan.validateCurrentRoots(roots))
        XCTAssertNoThrow(try plan.validateCurrentCapabilities(capabilities))

        guard case .compare(let routed) = try FolderComparisonWorkflowPlanner.plan(.compare(request)) else {
            return XCTFail("Expected routed compare plan")
        }
        XCTAssertEqual(routed, plan)
        XCTAssertEqual(settings.comparatorOptions.method, .contentRequired)
        XCTAssertEqual(settings.comparatorOptions.pathCaseSensitivity, .insensitive)
    }

    func testComparePlanRequiresScanComparisonCapabilitiesAndContentAuthority() throws {
        let target = initialTarget()
        let roots = makeRoots()
        let nonrecursive = FolderComparisonCompareRequest(
            target: target,
            roots: roots,
            scanIntent: makeScanIntent(recursive: false),
            comparisonSettings: FolderComparisonSettings(),
            capabilities: makeCapabilities(features: [.metadataComparison])
        )
        assertWorkflowError(.unsupportedCapability(.nonrecursiveScan)) {
            try FolderComparisonWorkflowPlanner.planComparison(nonrecursive)
        }

        let noMetadata = FolderComparisonCompareRequest(
            target: target,
            roots: roots,
            scanIntent: makeScanIntent(),
            comparisonSettings: FolderComparisonSettings(),
            capabilities: makeCapabilities(features: [.recursiveScan])
        )
        assertWorkflowError(.unsupportedCapability(.metadataComparison)) {
            try FolderComparisonWorkflowPlanner.planComparison(noMetadata)
        }

        let noContent = FolderComparisonCompareRequest(
            target: target,
            roots: roots,
            scanIntent: makeScanIntent(),
            comparisonSettings: FolderComparisonSettings(method: .contentIfAvailable),
            capabilities: makeCapabilities(features: [.recursiveScan, .metadataComparison])
        )
        assertWorkflowError(.unsupportedCapability(.contentComparison)) {
            try FolderComparisonWorkflowPlanner.planComparison(noContent)
        }

        let noLeftRead = replacingRoot(
            roots,
            side: .left,
            permissions: [.enumerate, .mutate]
        )
        let contentRequest = FolderComparisonCompareRequest(
            target: target,
            roots: noLeftRead,
            scanIntent: makeScanIntent(),
            comparisonSettings: FolderComparisonSettings(method: .contentRequired),
            capabilities: capabilities
        )
        assertWorkflowError(.authorityPermissionMissing(side: .left, permission: .readContent)) {
            try FolderComparisonWorkflowPlanner.planComparison(contentRequest)
        }
    }

    func testRootsRequireCanonicalDistinctPhysicalDirectoriesAndTreeAuthority() throws {
        let base = makeRoots()
        let target = initialTarget()

        let samePhysicalRightIdentity = FolderComparisonRootIdentity(
            canonicalURL: URL(filePath: "/right-alias"),
            deviceID: base.left.revision.identity.deviceID,
            fileID: base.left.revision.identity.fileID,
            generation: base.left.revision.identity.generation
        )
        let duplicateRoots = FolderComparisonRootPair(
            left: base.left,
            right: makeRoot(side: .right, identity: samePhysicalRightIdentity)
        )
        assertCompareError(.duplicateRootIdentity, roots: duplicateRoots, target: target)

        let mismatchedAuthority = replacingRoot(
            base,
            side: .left,
            authorityRootIdentity: base.right.revision.identity
        )
        assertCompareError(.authorityRootMismatch(.left), roots: mismatchedAuthority, target: target)

        let noEnumerate = replacingRoot(base, side: .left, permissions: [.readContent, .mutate])
        assertCompareError(
            .authorityPermissionMissing(side: .left, permission: .enumerate),
            roots: noEnumerate,
            target: target
        )

        let exactRoot = replacingRoot(base, side: .right, coverage: .exactRoot)
        assertCompareError(
            .invalidURL(role: .requestedRoot(.right), issue: .insufficientCoverage),
            roots: exactRoot,
            target: target
        )

        let insufficientScoped = replacingRoot(
            base,
            side: .left,
            coverage: .directoryTree,
            acquisition: .securityScoped(
                resourceURL: URL(filePath: "/left"),
                coverage: .exactRoot
            )
        )
        assertCompareError(
            .invalidURL(role: .securityScope(.left), issue: .insufficientCoverage),
            roots: insufficientScoped,
            target: target
        )

        let validAliasMetadata = FolderComparisonRootPair(
            left: makeRoot(
                side: .left,
                requestedURL: URL(filePath: "/caller-alias/left"),
                identity: base.left.revision.identity
            ),
            right: base.right
        )
        XCTAssertNoThrow(
            try FolderComparisonWorkflowPlanner.planComparison(
                compareRequest(roots: validAliasMetadata, target: target)
            )
        )
    }

    func testRootURLValidationReportsExactRoleAndIssue() throws {
        let roots = makeRoots()
        let target = initialTarget()
        let requestedCases: [(URL, FolderComparisonWorkflowURLIssue)] = [
            (try XCTUnwrap(URL(string: "https://example.invalid/left")), .notFileURL),
            (try XCTUnwrap(URL(string: "file:left")), .relativeURL),
            (try XCTUnwrap(URL(string: "file://server/left")), .remoteHost),
            (try XCTUnwrap(URL(string: "file://user@localhost/left")), .credentialsOrPort),
            (try XCTUnwrap(URL(string: "file:///left?query=1")), .queryOrFragment)
        ]
        for (url, issue) in requestedCases {
            let changed = replacingRoot(roots, side: .left, requestedURL: url)
            assertCompareError(.invalidURL(role: .requestedRoot(.left), issue: issue), roots: changed, target: target)
        }

        let noncanonicalIdentity = FolderComparisonRootIdentity(
            canonicalURL: URL(filePath: "/left/../left"),
            deviceID: roots.left.revision.identity.deviceID,
            fileID: roots.left.revision.identity.fileID,
            generation: roots.left.revision.identity.generation
        )
        let noncanonical = replacingRoot(roots, side: .left, identity: noncanonicalIdentity)
        assertCompareError(
            .invalidURL(role: .canonicalRoot(.left), issue: .notCanonical),
            roots: noncanonical,
            target: target
        )

        let shortLimits = makeLimits(maximumStringUTF8Bytes: 8)
        let overlong = replacingRoot(
            roots,
            side: .left,
            requestedURL: URL(filePath: "/123456789")
        )
        assertWorkflowError(.invalidURL(role: .requestedRoot(.left), issue: .pathTooLong)) {
            try FolderComparisonWorkflowPlanner.planComparison(
                compareRequest(roots: overlong, target: target, limits: shortLimits)
            )
        }
    }

    func testRootRevisionGuardsAndCurrentRootCASUseEveryExactField() throws {
        let roots = makeRoots()
        let target = initialTarget()
        let revision = roots.left.revision
        let malformed = [
            makeRootRevision(identity: revision.identity, linkCount: 0),
            makeRootRevision(identity: revision.identity, modificationTimeNanoseconds: -1),
            makeRootRevision(identity: revision.identity, modificationTimeNanoseconds: 1_000_000_000),
            makeRootRevision(identity: revision.identity, statusChangeTimeNanoseconds: -1),
            makeRootRevision(identity: revision.identity, statusChangeTimeNanoseconds: 1_000_000_000),
            makeRootRevision(identity: revision.identity, metadataSHA256: [0])
        ]
        for invalid in malformed {
            assertCompareError(
                .invalidRootRevision(.left),
                roots: replacingRoot(roots, side: .left, revision: invalid),
                target: target
            )
        }

        let plan = try FolderComparisonWorkflowPlanner.planComparison(
            compareRequest(roots: roots, target: target)
        )
        let exactMutations = [
            makeRootRevision(identity: revision.identity, linkCount: revision.linkCount + 1),
            makeRootRevision(identity: revision.identity, permissions: revision.permissions ^ 0o001),
            makeRootRevision(identity: revision.identity, ownerID: revision.ownerID + 1),
            makeRootRevision(identity: revision.identity, groupID: revision.groupID + 1),
            makeRootRevision(identity: revision.identity, flags: revision.flags + 1),
            makeRootRevision(
                identity: revision.identity,
                modificationTimeSeconds: revision.modificationTimeSeconds + 1
            ),
            makeRootRevision(
                identity: revision.identity,
                statusChangeTimeSeconds: revision.statusChangeTimeSeconds + 1
            ),
            makeRootRevision(identity: revision.identity, metadataSHA256: digest(99))
        ]
        for changedRevision in exactMutations {
            assertWorkflowError(.staleSnapshot) {
                try plan.validateCurrentRoots(
                    replacingRoot(roots, side: .left, revision: changedRevision)
                )
            }
        }
    }

    func testScanSettingsFiltersAndLimitsFailClosedAtExactGuards() throws {
        let target = initialTarget()
        let roots = makeRoots()
        let invalidTolerance = [Double.nan, .infinity, -0.001]
        for tolerance in invalidTolerance {
            assertWorkflowError(.invalidComparisonSettings) {
                try FolderComparisonWorkflowPlanner.planComparison(
                    compareRequest(
                        roots: roots,
                        target: target,
                        settings: FolderComparisonSettings(modificationDateTolerance: tolerance)
                    )
                )
            }
        }

        let tooManyEntries = makeScanIntent(maximumEntries: 2)
        assertWorkflowError(.invalidScanOptions) {
            try FolderComparisonWorkflowPlanner.planComparison(
                compareRequest(
                    roots: roots,
                    target: target,
                    scanIntent: tooManyEntries,
                    limits: makeLimits(
                        maximumResultItems: 1,
                        maximumSelectedItems: 1,
                        maximumPresentationRows: 1
                    )
                )
            )
        }

        let emptyPattern = FolderComparisonScanFilter(
            rules: [FilenameFilterRule(.exclude, pattern: .glob(""))],
            limits: FilenameFilterLimits(
                maximumCompiledStateCount: 16,
                maximumMatchWork: 1
            )
        )
        assertWorkflowError(
            .invalidFilenameFilter(
                FilenameFilterDiagnostic(ruleIndex: 0, reason: .emptyPattern)
            )
        ) {
            try FolderComparisonWorkflowPlanner.planComparison(
                compareRequest(
                    roots: roots,
                    target: target,
                    scanIntent: makeScanIntent(
                        maximumExaminedEntries: 1,
                        filter: emptyPattern
                    )
                )
            )
        }

        let filter = FolderComparisonScanFilter(
            rules: [FilenameFilterRule(.include, pattern: .glob("*.swift"))],
            limits: FilenameFilterLimits(
                maximumRuleCount: 1,
                maximumPatternUTF8Bytes: 16,
                maximumTotalPatternUTF8Bytes: 16,
                maximumRelativePathUTF8Bytes: 16,
                maximumCompiledStateCount: 16,
                maximumMatchWork: 10
            )
        )
        assertWorkflowError(.workLimitExceeded(maximumUnits: 100)) {
            try FolderComparisonWorkflowPlanner.planComparison(
                compareRequest(
                    roots: roots,
                    target: target,
                    scanIntent: makeScanIntent(maximumExaminedEntries: 6, filter: filter),
                    limits: makeLimits(maximumWorkUnits: 100)
                )
            )
        }

        let twoRules = FolderComparisonScanFilter(
            rules: [
                FilenameFilterRule(.include, pattern: .glob("a")),
                FilenameFilterRule(.exclude, pattern: .glob("b"))
            ],
            limits: FilenameFilterLimits(maximumRuleCount: 2, maximumMatchWork: 1)
        )
        assertWorkflowError(.invalidLimit(.filterRules, value: "2")) {
            try FolderComparisonWorkflowPlanner.planComparison(
                compareRequest(
                    roots: roots,
                    target: target,
                    scanIntent: makeScanIntent(maximumExaminedEntries: 1, filter: twoRules),
                    limits: makeLimits(maximumFilterRules: 1)
                )
            )
        }
    }

    func testSnapshotReferencePreservesRootsSettingsAndExactResultRevisions() throws {
        let roots = makeRoots()
        let rows = [
            makePairedRow(path: "same.txt", roots: roots, seed: 10),
            makeOneSidedRow(path: "left.txt", side: .left, roots: roots, seed: 20),
            makeOneSidedRow(path: "right.txt", side: .right, roots: roots, seed: 30)
        ]
        let snapshot = makeSnapshot(roots: roots, rows: rows)

        let reference = try FolderComparisonWorkflowPlanner.reference(to: snapshot)

        XCTAssertEqual(reference.identity, snapshot.identity)
        XCTAssertEqual(reference.generation, snapshot.generation)
        XCTAssertEqual(reference.owner, snapshot.owner)
        XCTAssertEqual(reference.roots, roots)
        XCTAssertEqual(reference.scanIntent, snapshot.scanIntent)
        XCTAssertEqual(reference.comparisonSettings, snapshot.comparisonSettings)
        XCTAssertEqual(reference.contentSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(snapshot.results, rows.map(\.result))
        XCTAssertEqual(snapshot.resultRevisions, rows.map(\.revision))
        XCTAssertEqual(snapshot.roots[.left], roots.left)
        XCTAssertEqual(snapshot.roots[.right], roots.right)
        XCTAssertEqual(snapshot.resultRevisions[0][.left], rows[0].revision.left)
        XCTAssertEqual(snapshot.resultRevisions[0][.right], rows[0].revision.right)
    }

    func testSnapshotRejectsIncompleteMismatchedAndPendingResults() throws {
        let roots = makeRoots()
        let row = makePairedRow(path: "same.txt", roots: roots, seed: 10)
        let incomplete = makeSnapshot(roots: roots, rows: [row], isComplete: false)
        assertWorkflowError(.invalidResultRevision(row.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(to: incomplete)
        }

        let missingRevision = FolderComparisonWorkflowSnapshot(
            identity: snapshotIdentity,
            generation: 3,
            owner: FolderComparisonWorkflowSnapshotOwner(identity: snapshotOwnerID, revision: 3),
            roots: roots,
            scanIntent: makeScanIntent(),
            comparisonSettings: FolderComparisonSettings(),
            isComplete: true,
            results: [row.result],
            resultRevisions: []
        )
        assertWorkflowError(.invalidResultRevision(row.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(to: missingRevision)
        }

        let pendingMetadata = makeMetadata(path: "pending.txt", byteCount: 1, seconds: 50)
        let pendingResult = DirectoryResult(
            left: pendingMetadata,
            right: pendingMetadata,
            status: .pending
        )
        let pendingRevision = FolderComparisonResultRevision(
            id: pendingResult.id,
            left: makeItemRevision(
                root: roots.left,
                path: "pending.txt",
                byteCount: 1,
                seconds: 50,
                seed: 51
            ),
            right: makeItemRevision(
                root: roots.right,
                path: "pending.txt",
                byteCount: 1,
                seconds: 50,
                seed: 52
            )
        )
        let pending = makeSnapshot(
            roots: roots,
            results: [pendingResult],
            revisions: [pendingRevision]
        )
        assertWorkflowError(.invalidResultRevision(pendingResult.id)) {
            try FolderComparisonWorkflowPlanner.reference(to: pending)
        }
    }

    func testItemRevisionRequiresExactIdentityMetadataTimestampAndDigests() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "item.txt", side: .left, roots: roots, seed: 10)
        let revision = try XCTUnwrap(row.revision.left)
        let wrongRoot = makeItemRevision(
            root: roots.right,
            path: "item.txt",
            byteCount: revision.byteCount,
            seconds: revision.modificationTimeSeconds,
            seed: 10
        )
        let malformed: [FolderComparisonItemRevision] = [
            wrongRoot,
            replacingItemRevision(revision, relativePath: "other.txt"),
            replacingItemRevision(revision, kind: .directory),
            replacingItemRevision(revision, byteCount: 999),
            replacingItemRevision(revision, linkCount: 0),
            replacingItemRevision(revision, modificationTimeSeconds: revision.modificationTimeSeconds + 1),
            replacingItemRevision(revision, modificationTimeNanoseconds: -1),
            replacingItemRevision(revision, modificationTimeNanoseconds: 1_000_000_000),
            replacingItemRevision(revision, statusChangeTimeNanoseconds: -1),
            replacingItemRevision(revision, statusChangeTimeNanoseconds: 1_000_000_000),
            replacingItemRevision(revision, metadataSHA256: [0]),
            replacingItemRevision(revision, contentSHA256: [0])
        ]
        for invalid in malformed {
            let changed = FolderComparisonResultRevision(id: row.result.id, left: invalid, right: nil)
            assertWorkflowError(.invalidResultRevision(row.result.id)) {
                try FolderComparisonWorkflowPlanner.reference(
                    to: makeSnapshot(roots: roots, results: [row.result], revisions: [changed])
                )
            }
        }

        let absentRevision = FolderComparisonResultRevision(id: row.result.id, left: nil, right: nil)
        assertWorkflowError(.invalidResultRevision(row.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(roots: roots, results: [row.result], revisions: [absentRevision])
            )
        }
    }

    func testSnapshotRejectsDuplicateIDsSidePathsCaseFoldCollisionsAndPhysicalAliases() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "same.txt", side: .left, roots: roots, seed: 10)
        assertWorkflowError(.duplicateResultID(row.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(roots: roots, rows: [row, row])
            )
        }

        let first = makePairedRow(
            leftPath: "A.txt",
            rightPath: "x.txt",
            status: .different,
            roots: roots,
            leftByteCount: 1,
            rightByteCount: 2,
            seed: 20
        )
        let second = makePairedRow(
            leftPath: "A.txt",
            rightPath: "y.txt",
            status: .different,
            roots: roots,
            leftByteCount: 3,
            rightByteCount: 4,
            seed: 30
        )
        assertWorkflowError(.duplicateResultPath(side: .left, relativePath: "A.txt")) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(roots: roots, rows: [first, second])
            )
        }

        let insensitiveRoots = FolderComparisonRootPair(
            left: replacingRoot(roots.left, caseSensitivity: .insensitive),
            right: roots.right
        )
        let caseFirst = makePairedRow(
            leftPath: "Report.txt",
            rightPath: "one.txt",
            status: .different,
            roots: insensitiveRoots,
            leftByteCount: 1,
            rightByteCount: 2,
            seed: 40
        )
        let caseSecond = makePairedRow(
            leftPath: "report.TXT",
            rightPath: "two.txt",
            status: .different,
            roots: insensitiveRoots,
            leftByteCount: 3,
            rightByteCount: 4,
            seed: 50
        )
        assertWorkflowError(.duplicateResultPath(side: .left, relativePath: "report.TXT")) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(roots: insensitiveRoots, rows: [caseFirst, caseSecond])
            )
        }

        let leftCase = makeOneSidedRow(path: "Case.txt", side: .left, roots: roots, seed: 60)
        let rightCase = makeOneSidedRow(path: "case.TXT", side: .right, roots: roots, seed: 70)
        let comparisonInsensitive = makeSnapshot(
            roots: roots,
            rows: [leftCase, rightCase],
            settings: FolderComparisonSettings(pathCaseSensitivity: .insensitive)
        )
        assertWorkflowError(.duplicateResultID(rightCase.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(to: comparisonInsensitive)
        }

        let aliasFirst = makePairedRow(
            leftPath: "physical-a.txt",
            rightPath: "physical-right-a.txt",
            status: .different,
            roots: roots,
            leftByteCount: 1,
            rightByteCount: 2,
            seed: 80
        )
        let aliasSecond = makePairedRow(
            leftPath: "physical-b.txt",
            rightPath: "physical-right-b.txt",
            status: .different,
            roots: roots,
            leftByteCount: 3,
            rightByteCount: 4,
            seed: 90
        )
        let aliasRevision = replacingItemRevision(
            try XCTUnwrap(aliasSecond.revision.left),
            deviceID: try XCTUnwrap(aliasFirst.revision.left).identity.deviceID,
            fileID: try XCTUnwrap(aliasFirst.revision.left).identity.fileID,
            generation: try XCTUnwrap(aliasFirst.revision.left).identity.generation
        )
        let aliasedSecondRevision = FolderComparisonResultRevision(
            id: aliasSecond.result.id,
            left: aliasRevision,
            right: aliasSecond.revision.right
        )
        assertWorkflowError(.duplicateItemIdentity(aliasSecond.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(
                    roots: roots,
                    results: [aliasFirst.result, aliasSecond.result],
                    revisions: [aliasFirst.revision, aliasedSecondRevision]
                )
            )
        }

        let rootAliasRevision = replacingItemRevision(
            try XCTUnwrap(row.revision.left),
            deviceID: roots.left.revision.identity.deviceID,
            fileID: roots.left.revision.identity.fileID,
            generation: roots.left.revision.identity.generation
        )
        assertWorkflowError(.duplicateItemIdentity(row.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(
                    roots: roots,
                    results: [row.result],
                    revisions: [
                        FolderComparisonResultRevision(
                            id: row.result.id,
                            left: rootAliasRevision,
                            right: nil
                        )
                    ]
                )
            )
        }
    }

    func testSnapshotStatusValidationHonorsMethodsContentAndTimestampTolerance() throws {
        let roots = makeRoots()
        let left = makeMetadata(path: "value.txt", byteCount: 4, seconds: 100)
        let right = makeMetadata(path: "value.txt", byteCount: 4, seconds: 101)
        let different = DirectoryResult(left: left, right: right, status: .different)
        let leftRevision = makeItemRevision(
            root: roots.left,
            path: "value.txt",
            byteCount: 4,
            seconds: 100,
            contentSeed: 1,
            seed: 80
        )
        let rightRevision = makeItemRevision(
            root: roots.right,
            path: "value.txt",
            byteCount: 4,
            seconds: 101,
            contentSeed: 1,
            seed: 81
        )
        let revision = FolderComparisonResultRevision(
            id: different.id,
            left: leftRevision,
            right: rightRevision
        )
        XCTAssertNoThrow(
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(
                    roots: roots,
                    results: [different],
                    revisions: [revision],
                    settings: FolderComparisonSettings(
                        method: .contentRequired,
                        modificationDateTolerance: 0.5
                    )
                )
            )
        )

        let identical = DirectoryResult(left: left, right: right, status: .identical)
        let identicalRevision = FolderComparisonResultRevision(
            id: identical.id,
            left: leftRevision,
            right: rightRevision
        )
        XCTAssertNoThrow(
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(
                    roots: roots,
                    results: [identical],
                    revisions: [identicalRevision],
                    settings: FolderComparisonSettings(
                        method: .contentRequired,
                        modificationDateTolerance: 1
                    )
                )
            )
        )

        let missingContent = makeItemRevision(
            root: roots.right,
            path: "value.txt",
            byteCount: 4,
            seconds: 101,
            contentSeed: nil,
            seed: 81
        )
        assertWorkflowError(.invalidResultRevision(identical.id)) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(
                    roots: roots,
                    results: [identical],
                    revisions: [
                        FolderComparisonResultRevision(
                            id: identical.id,
                            left: leftRevision,
                            right: missingContent
                        )
                    ],
                    settings: FolderComparisonSettings(
                        method: .contentRequired,
                        modificationDateTolerance: 1
                    )
                )
            )
        }
    }

    func testSnapshotCASDistinguishesStaleEnvelopeFromChangedContents() throws {
        let roots = makeRoots()
        let first = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let second = makeOneSidedRow(path: "b.txt", side: .right, roots: roots, seed: 20)
        let snapshot = makeSnapshot(roots: roots, rows: [first, second])
        let plan = try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(snapshot: snapshot, capabilities: capabilities)
        )

        XCTAssertNoThrow(try plan.validateCurrentSnapshot(snapshot))
        for stale in [
            makeSnapshot(
                identity: FolderComparisonWorkflowSnapshotIdentity(rawValue: uuid(90)),
                roots: roots,
                rows: [first, second]
            ),
            makeSnapshot(roots: roots, rows: [first, second], generation: snapshot.generation + 1),
            makeSnapshot(
                roots: roots,
                rows: [first, second],
                owner: FolderComparisonWorkflowSnapshotOwner(
                    identity: snapshot.owner.identity,
                    revision: snapshot.owner.revision + 1
                )
            ),
            makeSnapshot(
                roots: replacingRoot(
                    roots,
                    side: .left,
                    revision: makeRootRevision(
                        identity: roots.left.revision.identity,
                        ownerID: roots.left.revision.ownerID + 1
                    )
                ),
                rows: [first, second]
            )
        ] {
            assertWorkflowError(.staleSnapshot) {
                try plan.validateCurrentSnapshot(stale)
            }
        }

        let reordered = makeSnapshot(roots: roots, rows: [second, first])
        assertWorkflowError(.snapshotContentsChanged) {
            try plan.validateCurrentSnapshot(reordered)
        }
        let changedScan = makeSnapshot(
            roots: roots,
            rows: [first, second],
            scanIntent: makeScanIntent(recursive: false)
        )
        assertWorkflowError(.snapshotContentsChanged) {
            try plan.validateCurrentSnapshot(changedScan)
        }
        let changedSettings = makeSnapshot(
            roots: roots,
            rows: [first, second],
            settings: FolderComparisonSettings(modificationDateTolerance: 1)
        )
        assertWorkflowError(.snapshotContentsChanged) {
            try plan.validateCurrentSnapshot(changedSettings)
        }
    }

    func testCompareReplacementRequiresChainedGenerationAndOwnerCAS() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let existing = makeSnapshot(roots: roots, rows: [row], generation: 7)
        let validTarget = FolderComparisonWorkflowSnapshotTarget(
            identity: existing.identity,
            generation: 8,
            owner: FolderComparisonWorkflowSnapshotOwner(
                identity: existing.owner.identity,
                revision: existing.owner.revision + 1
            )
        )
        let plan = try FolderComparisonWorkflowPlanner.planComparison(
            FolderComparisonCompareRequest(
                target: validTarget,
                replacing: existing,
                roots: roots,
                scanIntent: existing.scanIntent,
                comparisonSettings: existing.comparisonSettings,
                capabilities: capabilities
            )
        )
        XCTAssertEqual(plan.replacing, try FolderComparisonWorkflowPlanner.reference(to: existing))
        XCTAssertEqual(plan.receipt.inputItemCount, 1)

        let invalidTargets = [
            FolderComparisonWorkflowSnapshotTarget(
                identity: existing.identity,
                generation: existing.generation,
                owner: validTarget.owner
            ),
            FolderComparisonWorkflowSnapshotTarget(
                identity: FolderComparisonWorkflowSnapshotIdentity(rawValue: uuid(99)),
                generation: validTarget.generation,
                owner: validTarget.owner
            ),
            FolderComparisonWorkflowSnapshotTarget(
                identity: existing.identity,
                generation: validTarget.generation,
                owner: FolderComparisonWorkflowSnapshotOwner(
                    identity: existing.owner.identity,
                    revision: existing.owner.revision
                )
            ),
            FolderComparisonWorkflowSnapshotTarget(
                identity: existing.identity,
                generation: validTarget.generation,
                owner: FolderComparisonWorkflowSnapshotOwner(
                    identity: uuid(98),
                    revision: validTarget.owner.revision
                )
            )
        ]
        for target in invalidTargets {
            XCTAssertThrowsError(
                try FolderComparisonWorkflowPlanner.planComparison(
                    FolderComparisonCompareRequest(
                        target: target,
                        replacing: existing,
                        roots: roots,
                        scanIntent: existing.scanIntent,
                        comparisonSettings: existing.comparisonSettings,
                        capabilities: capabilities
                    )
                )
            ) { error in
                guard case .invalidSnapshotGeneration = error as? FolderComparisonWorkflowError else {
                    return XCTFail("Expected snapshot-generation error, got \(error)")
                }
            }
        }

        let exhausted = makeSnapshot(
            roots: roots,
            rows: [row],
            generation: UInt64.max,
            owner: FolderComparisonWorkflowSnapshotOwner(
                identity: snapshotOwnerID,
                revision: UInt64.max
            )
        )
        assertWorkflowError(.invalidSnapshotGeneration(expected: 0, actual: 0)) {
            try FolderComparisonWorkflowPlanner.planComparison(
                FolderComparisonCompareRequest(
                    target: initialTarget(),
                    replacing: exhausted,
                    roots: roots,
                    scanIntent: exhausted.scanIntent,
                    comparisonSettings: exhausted.comparisonSettings,
                    capabilities: capabilities
                )
            )
        }
    }

    func testTablePresentationFiltersSortsStablyAndExposesOneSidedValues() throws {
        let roots = makeRoots()
        let hidden = makeOneSidedRow(
            path: ".cache/Hidden.swift",
            side: .left,
            roots: roots,
            seed: 10,
            isHidden: true
        )
        let visible = makeOneSidedRow(path: "Visible.swift", side: .left, roots: roots, seed: 20)
        let right = makeOneSidedRow(path: "Right.swift", side: .right, roots: roots, seed: 30)
        let snapshot = makeSnapshot(roots: roots, rows: [visible, right, hidden])
        let configuration = FolderComparisonPresentationConfiguration(
            mode: .table,
            columns: [.stateIcon, .relativePath, .status, .kind, .leftSize, .rightSize],
            filter: FolderComparisonPresentationFilter(
                statuses: [.leftOnly],
                kinds: [.file],
                hidden: .only,
                pathQuery: "HIDDEN.SWIFT"
            ),
            sortDescriptors: [
                FolderComparisonPresentationSortDescriptor(key: .leftSize, order: .descending),
                FolderComparisonPresentationSortDescriptor(key: .path)
            ]
        )
        let request = FolderComparisonPresentationRequest(
            snapshot: snapshot,
            configuration: configuration,
            capabilities: capabilities
        )

        let plan = try FolderComparisonWorkflowPlanner.planPresentation(request)

        XCTAssertEqual(plan.configuration, configuration)
        XCTAssertEqual(plan.rows.map(\.id), [hidden.result.id])
        let row = try XCTUnwrap(plan.rows.first)
        XCTAssertEqual(row.relativePath, ".cache/Hidden.swift")
        XCTAssertEqual(row.stateIcon, .leftOnly)
        XCTAssertEqual(row.status, .leftOnly)
        XCTAssertEqual(row.kind, .file)
        XCTAssertEqual(row.left?.relativePath, ".cache/Hidden.swift")
        XCTAssertTrue(row.left?.isHidden == true)
        XCTAssertNil(row.right)
        XCTAssertNil(row.treeParentID)
        XCTAssertNil(row.treeParentRelativePath)
        XCTAssertEqual(row.treeDepth, 0)
        XCTAssertEqual(plan.receipt.inputItemCount, 3)
        XCTAssertEqual(plan.receipt.outputItemCount, 1)
        XCTAssertEqual(plan.executorContract.presentation, .consumeExactOrderedRowsWithoutFilesystemOrWorkflowMutation)

        guard case .presentation(let routed) = try FolderComparisonWorkflowPlanner.plan(.present(request)) else {
            return XCTFail("Expected routed presentation plan")
        }
        XCTAssertEqual(routed, plan)

        let stableConfiguration = FolderComparisonPresentationConfiguration(
            sortDescriptors: [FolderComparisonPresentationSortDescriptor(key: .kind)]
        )
        let stable = try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(
                snapshot: snapshot,
                configuration: stableConfiguration,
                capabilities: capabilities
            )
        )
        XCTAssertEqual(stable.rows.map(\.id), snapshot.results.map(\.id))
    }

    func testPresentationValidatesColumnsSortsFiltersCapabilitiesAndRowBounds() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "a.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])

        assertPresentationError(
            .unsupportedCapability(.tablePresentation),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(),
            capabilities: makeCapabilities(features: [])
        )
        assertPresentationError(
            .tooManyColumns(maximum: 1),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(),
            limits: makeLimits(maximumColumns: 1)
        )
        assertPresentationError(
            .duplicateColumn(.stateIcon),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(
                columns: [.stateIcon, .stateIcon, .relativePath]
            )
        )
        assertPresentationError(
            .missingRequiredColumn(.stateIcon),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(columns: [.relativePath])
        )
        assertPresentationError(
            .missingRequiredColumn(.relativePath),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(columns: [.stateIcon])
        )
        assertPresentationError(
            .tooManySortDescriptors(maximum: 1),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(
                sortDescriptors: [
                    FolderComparisonPresentationSortDescriptor(key: .path),
                    FolderComparisonPresentationSortDescriptor(key: .status)
                ]
            ),
            limits: makeLimits(maximumSortDescriptors: 1)
        )
        assertPresentationError(
            .duplicateSortKey(.path),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(
                sortDescriptors: [
                    FolderComparisonPresentationSortDescriptor(key: .path),
                    FolderComparisonPresentationSortDescriptor(key: .path, order: .descending)
                ]
            )
        )
        assertPresentationError(
            .invalidLimit(.sortDescriptors, value: "0"),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(sortDescriptors: [])
        )
        assertPresentationError(
            .tooManyPresentationRows(maximum: 0),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(),
            limits: makeLimits(maximumPresentationRows: 0)
        )
        let shortPathSnapshot = makeSnapshot(
            roots: roots,
            rows: [row],
            scanIntent: makeScanIntent(maximumRelativePathUTF8Bytes: 6)
        )
        assertPresentationError(
            .stringTooLarge(maximumUTF8Bytes: 6),
            snapshot: shortPathSnapshot,
            configuration: FolderComparisonPresentationConfiguration(
                filter: FolderComparisonPresentationFilter(pathQuery: "1234567")
            ),
            limits: makeLimits(maximumStringUTF8Bytes: 6)
        )
        let nullQuery = FolderComparisonPresentationConfiguration(
            filter: FolderComparisonPresentationFilter(pathQuery: "a\0b")
        )
        XCTAssertThrowsError(
            try FolderComparisonWorkflowPlanner.planPresentation(
                FolderComparisonPresentationRequest(
                    snapshot: snapshot,
                    configuration: nullQuery,
                    capabilities: capabilities
                )
            )
        ) { error in
            guard case .invalidResultPath = error as? FolderComparisonWorkflowError else {
                return XCTFail("Expected invalid path, got \(error)")
            }
        }
    }

    func testTreePresentationBuildsNearestAdmittedParentsAndPreorder() throws {
        let roots = makeRoots()
        let rootDirectory = makePairedRow(
            path: "folder",
            kind: .directory,
            byteCount: nil,
            roots: roots,
            seed: 10
        )
        let nestedDirectory = makePairedRow(
            path: "folder/omitted",
            kind: .directory,
            byteCount: nil,
            roots: roots,
            seed: 20
        )
        let child = makePairedRow(path: "folder/omitted/child.txt", roots: roots, seed: 30)
        let sibling = makePairedRow(path: "folder/sibling.txt", roots: roots, seed: 40)
        let snapshot = makeSnapshot(
            roots: roots,
            rows: [child, sibling, nestedDirectory, rootDirectory]
        )
        let configuration = FolderComparisonPresentationConfiguration(
            mode: .tree,
            filter: FolderComparisonPresentationFilter(
                statuses: [.identical],
                kinds: [.file, .directory],
                pathQuery: ""
            ),
            sortDescriptors: [FolderComparisonPresentationSortDescriptor(key: .path)]
        )

        let plan = try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(
                snapshot: snapshot,
                configuration: configuration,
                capabilities: capabilities
            )
        )

        XCTAssertEqual(
            plan.rows.map(\.relativePath),
            ["folder", "folder/omitted", "folder/omitted/child.txt", "folder/sibling.txt"]
        )
        XCTAssertEqual(plan.rows.map(\.treeDepth), [0, 1, 2, 1])
        XCTAssertEqual(plan.rows[1].treeParentID, rootDirectory.result.id)
        XCTAssertEqual(plan.rows[1].treeParentRelativePath, "folder")
        XCTAssertEqual(plan.rows[2].treeParentID, nestedDirectory.result.id)
        XCTAssertEqual(plan.rows[2].treeParentRelativePath, "folder/omitted")

        let filesOnly = FolderComparisonPresentationConfiguration(
            mode: .tree,
            filter: FolderComparisonPresentationFilter(kinds: [.file]),
            sortDescriptors: [FolderComparisonPresentationSortDescriptor(key: .path)]
        )
        let withoutDirectories = try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(
                snapshot: snapshot,
                configuration: filesOnly,
                capabilities: capabilities
            )
        )
        XCTAssertEqual(
            withoutDirectories.rows.map(\.relativePath),
            ["folder/omitted/child.txt", "folder/sibling.txt"]
        )
        XCTAssertEqual(withoutDirectories.rows.map(\.treeDepth), [0, 0])
        XCTAssertTrue(withoutDirectories.rows.allSatisfy { $0.treeParentID == nil })
    }

    func testTreePresentationRejectsSortSubstitutionAndMissingCapability() throws {
        let roots = makeRoots()
        let row = makePairedRow(path: "same.txt", roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        assertPresentationError(
            .unsupportedTreeSort,
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(
                mode: .tree,
                sortDescriptors: [
                    FolderComparisonPresentationSortDescriptor(key: .path, order: .descending)
                ]
            )
        )
        assertPresentationError(
            .unsupportedCapability(.treePresentation),
            snapshot: snapshot,
            configuration: FolderComparisonPresentationConfiguration(mode: .tree),
            capabilities: makeCapabilities(features: [.tablePresentation])
        )

        let substitution = makePairedRow(
            leftPath: "old.txt",
            rightPath: "new.txt",
            status: .identical,
            roots: roots,
            leftByteCount: 1,
            rightByteCount: 1,
            seed: 20
        )
        let substitutionSnapshot = makeSnapshot(roots: roots, rows: [substitution])
        assertPresentationError(
            .unsupportedTreeResult(substitution.result.id),
            snapshot: substitutionSnapshot,
            configuration: FolderComparisonPresentationConfiguration(mode: .tree)
        )
    }

    func testCopyCreatePlanCarriesExactRootAndDirectoryAbsenceWitnesses() throws {
        let roots = makeRoots()
        let rootSource = makeOneSidedRow(path: "root.txt", side: .left, roots: roots, seed: 10)
        let rootSnapshot = makeSnapshot(roots: roots, rows: [rootSource])
        let rootPlan = try planOperation(
            snapshot: rootSnapshot,
            selection: .copy(ids: [rootSource.result.id], from: .left, collision: .fail)
        )
        let rootAction = try XCTUnwrap(rootPlan.actions.first)
        XCTAssertEqual(rootAction.kind, .copy)
        XCTAssertEqual(rootAction.sourceSide, .left)
        XCTAssertEqual(rootAction.destinationSide, .right)
        XCTAssertEqual(rootAction.source, rootSource.result.left)
        XCTAssertEqual(rootAction.sourceRevision, rootSource.revision.left)
        XCTAssertEqual(rootAction.sourceRoot?.identity, roots.left.revision.identity)
        XCTAssertEqual(rootAction.destinationRoot.preEffectRevision, roots.right.revision)
        XCTAssertEqual(rootAction.destinationRelativePath, "root.txt")
        XCTAssertEqual(rootAction.collision, .fail)
        XCTAssertNil(rootAction.destination)
        XCTAssertNil(rootAction.replacementOwner)
        guard case .absent(let rootWitness) = rootAction.destinationPrecondition else {
            return XCTFail("Expected root absence witness")
        }
        XCTAssertEqual(rootWitness.relativePath, "root.txt")
        XCTAssertEqual(rootWitness.normalizedRelativePath, "root.txt")
        guard case .root(let parentRevision) = rootWitness.parent else {
            return XCTFail("Expected root parent revision")
        }
        XCTAssertEqual(parentRevision, roots.right.revision)

        let parent = makeOneSidedRow(
            path: "folder",
            side: .right,
            kind: .directory,
            byteCount: nil,
            roots: roots,
            seed: 20
        )
        let nestedSource = makeOneSidedRow(
            path: "folder/new.txt",
            side: .left,
            roots: roots,
            seed: 30
        )
        let nestedSnapshot = makeSnapshot(roots: roots, rows: [parent, nestedSource])
        let nestedPlan = try planOperation(
            snapshot: nestedSnapshot,
            selection: .copy(ids: [nestedSource.result.id], from: .left, collision: .fail)
        )
        guard case .absent(let witness) = try XCTUnwrap(nestedPlan.actions.first).destinationPrecondition else {
            return XCTFail("Expected directory absence witness")
        }
        guard case .directory(let directoryRevision) = witness.parent else {
            return XCTFail("Expected directory parent revision")
        }
        XCTAssertEqual(directoryRevision, parent.revision.right)
        XCTAssertEqual(witness.relativePath, "folder/new.txt")
        XCTAssertEqual(witness.normalizedRelativePath, "folder/new.txt")
        XCTAssertEqual(nestedPlan.preEffectResults, nestedSnapshot.results)
        XCTAssertEqual(nestedPlan.preEffectResultRevisions, nestedSnapshot.resultRevisions)

        let noParentSnapshot = makeSnapshot(roots: roots, rows: [nestedSource])
        assertOperationError(
            .missingDestinationParent(side: .right, relativePath: "folder/new.txt"),
            snapshot: noParentSnapshot,
            selection: .copy(ids: [nestedSource.result.id], from: .left, collision: .fail)
        )
    }

    func testCopyReplaceAndSkipPlansFailClosedOnCollisionAndOwnerCAS() throws {
        let roots = makeRoots()
        let pair = makePairedRow(
            leftPath: "item.txt",
            rightPath: "item.txt",
            status: .different,
            roots: roots,
            leftByteCount: 4,
            rightByteCount: 8,
            seed: 10
        )
        let snapshot = makeSnapshot(roots: roots, rows: [pair])
        assertOperationError(
            .destinationCollision(side: .right, relativePath: "item.txt"),
            snapshot: snapshot,
            selection: .copy(ids: [pair.result.id], from: .left, collision: .fail)
        )

        let skip = try planOperation(
            snapshot: snapshot,
            selection: .copy(ids: [pair.result.id], from: .left, collision: .skip)
        )
        XCTAssertEqual(skip.actions.first?.collision, .skip)
        guard case .existing(let skipExisting) = try XCTUnwrap(skip.actions.first).destinationPrecondition else {
            return XCTFail("Expected existing destination")
        }
        XCTAssertEqual(skipExisting, pair.revision.right)
        XCTAssertNil(skip.actions.first?.replacementOwner)

        assertOperationError(
            .replacementOwnerRequired,
            snapshot: snapshot,
            selection: .copy(
                ids: [pair.result.id],
                from: .left,
                collision: .replaceKeepingBackup
            )
        )
        let owner = FolderComparisonReplacementOwner(identity: replacementOwnerID, revision: 4)
        let replace = try planOperation(
            snapshot: snapshot,
            selection: .copy(
                ids: [pair.result.id],
                from: .left,
                collision: .replaceKeepingBackup
            ),
            replacementOwner: owner
        )
        XCTAssertEqual(replace.replacementOwner, owner)
        XCTAssertEqual(replace.actions.first?.replacementOwner, owner)
        XCTAssertNoThrow(try replace.validateCurrentReplacementOwner(owner))
        assertWorkflowError(.staleReplacementOwner) {
            try replace.validateCurrentReplacementOwner(
                FolderComparisonReplacementOwner(identity: owner.identity, revision: owner.revision + 1)
            )
        }
        assertWorkflowError(.staleReplacementOwner) {
            try replace.validateCurrentReplacementOwner(nil)
        }
    }

    func testMoveDeleteSynchronizeAndSubtreeManifestRestrictions() throws {
        let roots = makeRoots()
        let source = makeOneSidedRow(path: "move.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [source])
        let move = try planOperation(
            snapshot: snapshot,
            selection: .move(ids: [source.result.id], from: .left, collision: .fail)
        )
        XCTAssertEqual(move.actions.first?.kind, .move)
        XCTAssertEqual(move.actions.first?.sourceSide, .left)

        let noSourceMutation = replacingRoot(
            roots,
            side: .left,
            permissions: [.enumerate, .readContent]
        )
        let noSourceMutationSnapshot = makeSnapshot(
            roots: noSourceMutation,
            rows: [
                makeOneSidedRow(path: "move.txt", side: .left, roots: noSourceMutation, seed: 11)
            ])
        assertOperationError(
            .authorityPermissionMissing(side: .left, permission: .mutate),
            snapshot: noSourceMutationSnapshot,
            selection: .move(
                ids: [noSourceMutationSnapshot.results[0].id],
                from: .left,
                collision: .fail
            )
        )

        assertOperationError(
            .replacementOwnerRequired,
            snapshot: snapshot,
            selection: .delete(ids: [source.result.id], side: .left)
        )
        let owner = FolderComparisonReplacementOwner(identity: replacementOwnerID, revision: 1)
        let delete = try planOperation(
            snapshot: snapshot,
            selection: .delete(ids: [source.result.id], side: .left),
            replacementOwner: owner
        )
        XCTAssertEqual(delete.actions.first?.kind, .delete)
        XCTAssertNil(delete.actions.first?.sourceSide)
        XCTAssertEqual(delete.actions.first?.destinationSide, .left)
        XCTAssertEqual(delete.actions.first?.replacementOwner, owner)

        let extraneous = makeOneSidedRow(path: "extra.txt", side: .right, roots: roots, seed: 20)
        let syncSnapshot = makeSnapshot(roots: roots, rows: [extraneous])
        assertOperationError(
            .unsupportedOperationBatch,
            snapshot: syncSnapshot,
            selection: .synchronize(
                ids: [extraneous.result.id],
                from: .left,
                collision: .fail,
                deleteExtraneous: false
            )
        )
        assertOperationError(
            .replacementOwnerRequired,
            snapshot: syncSnapshot,
            selection: .synchronize(
                ids: [extraneous.result.id],
                from: .left,
                collision: .fail,
                deleteExtraneous: true
            )
        )

        let directory = makeOneSidedRow(
            path: "tree",
            side: .left,
            kind: .directory,
            byteCount: nil,
            roots: roots,
            seed: 30
        )
        let directorySnapshot = makeSnapshot(roots: roots, rows: [directory])
        assertOperationError(
            .unsupportedResultItem(directory.result.id),
            snapshot: directorySnapshot,
            selection: .copy(ids: [directory.result.id], from: .left, collision: .fail)
        )

        let second = makeOneSidedRow(path: "second.txt", side: .left, roots: roots, seed: 40)
        let batchSnapshot = makeSnapshot(roots: roots, rows: [source, second])
        assertOperationError(
            .unsupportedOperationBatch,
            snapshot: batchSnapshot,
            selection: .copy(
                ids: [source.result.id, second.result.id],
                from: .left,
                collision: .fail
            )
        )
    }

    func testOperationSelectionsRejectEmptyDuplicateUnknownMissingSourceAndCapability() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "item.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        assertOperationError(
            .emptySelection,
            snapshot: snapshot,
            selection: .copy(ids: [], from: .left, collision: .fail)
        )
        assertOperationError(
            .tooManySelectedItems(maximum: 0),
            snapshot: snapshot,
            selection: .copy(ids: [row.result.id], from: .left, collision: .fail),
            limits: makeLimits(maximumSelectedItems: 0)
        )
        assertOperationError(
            .duplicateSelectedResult(row.result.id),
            snapshot: snapshot,
            selection: .copy(
                ids: [row.result.id, row.result.id],
                from: .left,
                collision: .fail
            )
        )
        let unknown = DirectoryResult.ID(leftRelativePath: "unknown.txt", rightRelativePath: nil)
        assertOperationError(
            .unknownResult(unknown),
            snapshot: snapshot,
            selection: .copy(ids: [unknown], from: .left, collision: .fail)
        )
        assertOperationError(
            .missingOperationSource(id: row.result.id, side: .right),
            snapshot: snapshot,
            selection: .copy(ids: [row.result.id], from: .right, collision: .fail)
        )
        assertOperationError(
            .unsupportedCapability(.copyItems),
            snapshot: snapshot,
            selection: .copy(ids: [row.result.id], from: .left, collision: .fail),
            capabilities: makeCapabilities(features: [])
        )

        let noContentRevision = replacingItemRevision(
            try XCTUnwrap(row.revision.left),
            contentSHA256: .some(nil)
        )
        let noContentSnapshot = makeSnapshot(
            roots: roots,
            results: [row.result],
            revisions: [
                FolderComparisonResultRevision(
                    id: row.result.id,
                    left: noContentRevision,
                    right: nil
                )
            ]
        )
        assertOperationError(
            .invalidResultRevision(row.result.id),
            snapshot: noContentSnapshot,
            selection: .copy(ids: [row.result.id], from: .left, collision: .fail)
        )
    }

    func testOperationPlanSnapshotCapabilityAndReplacementCASAreExact() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "item.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        let plan = try planOperation(
            snapshot: snapshot,
            selection: .copy(ids: [row.result.id], from: .left, collision: .fail)
        )
        XCTAssertNoThrow(try plan.validateCurrentSnapshot(snapshot))
        XCTAssertNoThrow(try plan.validateCurrentCapabilities(capabilities))
        XCTAssertNoThrow(try plan.validateCurrentReplacementOwner(nil))

        let changedSnapshot = makeSnapshot(
            roots: roots,
            rows: [row],
            generation: snapshot.generation + 1
        )
        assertWorkflowError(.staleSnapshot) {
            try plan.validateCurrentSnapshot(changedSnapshot)
        }
        let changedCapabilities = makeCapabilities(
            revision: capabilities.revision + 1,
            features: capabilities.features
        )
        assertWorkflowError(.staleCapabilityRevision) {
            try plan.validateCurrentCapabilities(changedCapabilities)
        }
        assertWorkflowError(.staleReplacementOwner) {
            try plan.validateCurrentReplacementOwner(
                FolderComparisonReplacementOwner(identity: replacementOwnerID, revision: 0)
            )
        }
    }

    func testOpenPairPlanPinsPathsRevisionsSnapshotAndAuthority() throws {
        let roots = makeRoots()
        let pair = makePairedRow(path: "pair.txt", roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [pair])
        let request = FolderComparisonOpenFilePairRequest(
            snapshot: snapshot,
            id: pair.result.id,
            capabilities: capabilities
        )
        let plan = try FolderComparisonWorkflowPlanner.planOpenFilePair(request)

        XCTAssertEqual(plan.snapshot, try FolderComparisonWorkflowPlanner.reference(to: snapshot))
        XCTAssertEqual(plan.resultID, pair.result.id)
        XCTAssertEqual(plan.leftRelativePath, "pair.txt")
        XCTAssertEqual(plan.rightRelativePath, "pair.txt")
        XCTAssertEqual(plan.leftRevision, pair.revision.left)
        XCTAssertEqual(plan.rightRevision, pair.revision.right)
        XCTAssertEqual(plan.receipt.inputItemCount, 1)
        XCTAssertEqual(plan.receipt.outputItemCount, 1)
        XCTAssertEqual(plan.executorContract.opening, .openRegularPairByDescriptorWithoutFollowingLinksAndHoldRevisionsThroughDispatch)
        XCTAssertNoThrow(try plan.validateCurrentSnapshot(snapshot))
        XCTAssertNoThrow(try plan.validateCurrentCapabilities(capabilities))

        guard case .openFilePair(let routed) = try FolderComparisonWorkflowPlanner.plan(.openFilePair(request)) else {
            return XCTFail("Expected routed open-pair plan")
        }
        XCTAssertEqual(routed, plan)

        let noRead = replacingRoot(
            roots,
            side: .right,
            permissions: [.enumerate, .mutate]
        )
        let noReadPair = makePairedRow(path: "pair.txt", roots: noRead, seed: 20)
        let noReadSnapshot = makeSnapshot(roots: noRead, rows: [noReadPair])
        assertWorkflowError(.authorityPermissionMissing(side: .right, permission: .readContent)) {
            try FolderComparisonWorkflowPlanner.planOpenFilePair(
                FolderComparisonOpenFilePairRequest(
                    snapshot: noReadSnapshot,
                    id: noReadPair.result.id,
                    capabilities: capabilities
                )
            )
        }
    }

    func testOpenPairRejectsUnknownOneSidedDirectoryAndMissingCapability() throws {
        let roots = makeRoots()
        let oneSided = makeOneSidedRow(path: "left.txt", side: .left, roots: roots, seed: 10)
        let directory = makePairedRow(
            path: "folder",
            kind: .directory,
            byteCount: nil,
            roots: roots,
            seed: 20
        )
        let snapshot = makeSnapshot(roots: roots, rows: [oneSided, directory])
        let unknown = DirectoryResult.ID(leftRelativePath: "unknown.txt", rightRelativePath: nil)
        for id in [unknown, oneSided.result.id, directory.result.id] {
            assertWorkflowError(.filePairUnavailable(id)) {
                try FolderComparisonWorkflowPlanner.planOpenFilePair(
                    FolderComparisonOpenFilePairRequest(
                        snapshot: snapshot,
                        id: id,
                        capabilities: capabilities
                    )
                )
            }
        }
        assertWorkflowError(.unsupportedCapability(.openFilePair)) {
            try FolderComparisonWorkflowPlanner.planOpenFilePair(
                FolderComparisonOpenFilePairRequest(
                    snapshot: snapshot,
                    id: directory.result.id,
                    capabilities: makeCapabilities(features: [])
                )
            )
        }
    }

    func testActivityControlPlansExactLegalSuccessorsAndReceipts() throws {
        let progress = FolderComparisonActivityProgress(
            completedUnits: 5,
            totalUnits: 10,
            completedItems: 1,
            totalItems: 2,
            currentRelativePath: "current.txt"
        )
        let running = FolderComparisonActivitySnapshot(
            identity: activityID,
            revision: 7,
            kind: .scanning,
            state: .running,
            supportedControls: [.pause, .cancel],
            progress: progress
        )
        let pause = try FolderComparisonWorkflowPlanner.planActivityControl(
            FolderComparisonActivityControlRequest(
                activity: running,
                control: .pause,
                capabilities: capabilities
            )
        )
        XCTAssertEqual(pause.expectedSuccessorRevision, 8)
        XCTAssertEqual(pause.expectedSuccessorState, .paused)
        XCTAssertEqual(pause.expectedSuccessorSupportedControls, [.resume, .cancel])
        XCTAssertNoThrow(try pause.validateCurrentActivity(running))
        XCTAssertNoThrow(try pause.validateCurrentCapabilities(capabilities))
        let paused = FolderComparisonActivitySnapshot(
            identity: running.identity,
            revision: pause.expectedSuccessorRevision,
            kind: running.kind,
            state: pause.expectedSuccessorState,
            supportedControls: pause.expectedSuccessorSupportedControls,
            progress: progress
        )
        guard
            case .completed(let pauseReceipt) =
                try FolderComparisonExecutionReceiptFactory
                .completedActivityControl(plan: pause, activity: paused)
        else {
            return XCTFail("Expected completed pause receipt")
        }
        XCTAssertEqual(pauseReceipt.planSHA256, pause.receipt.planSHA256)
        XCTAssertEqual(pauseReceipt.activity, paused)

        let resume = try FolderComparisonWorkflowPlanner.planActivityControl(
            FolderComparisonActivityControlRequest(
                activity: paused,
                control: .resume,
                capabilities: capabilities
            )
        )
        XCTAssertEqual(resume.expectedSuccessorState, .running)
        XCTAssertEqual(resume.expectedSuccessorSupportedControls, [.pause, .cancel])

        let cancel = try FolderComparisonWorkflowPlanner.planActivityControl(
            FolderComparisonActivityControlRequest(
                activity: running,
                control: .cancel,
                capabilities: capabilities
            )
        )
        XCTAssertEqual(cancel.expectedSuccessorState, .cancelling)
        XCTAssertTrue(cancel.expectedSuccessorSupportedControls.isEmpty)

        guard
            case .activityControl(let routed) = try FolderComparisonWorkflowPlanner.plan(
                .controlActivity(
                    FolderComparisonActivityControlRequest(
                        activity: running,
                        control: .pause,
                        capabilities: capabilities
                    )
                )
            )
        else {
            return XCTFail("Expected routed activity plan")
        }
        XCTAssertEqual(routed, pause)
    }

    func testActivityControlsRejectProgressTransitionsCapabilitiesAndStaleCAS() throws {
        let invalidProgress = FolderComparisonActivitySnapshot(
            identity: activityID,
            revision: 1,
            kind: .comparing,
            state: .running,
            supportedControls: [.pause],
            progress: FolderComparisonActivityProgress(
                completedUnits: 2,
                totalUnits: 1,
                completedItems: 0
            )
        )
        assertActivityError(.invalidActivityProgress, activity: invalidProgress, control: .pause)

        let running = makeActivity(state: .running, controls: [.pause])
        assertActivityError(.unsupportedActivityControl(.resume), activity: running, control: .resume)
        let invalidPause = makeActivity(state: .paused, controls: [.pause])
        assertActivityError(
            .invalidActivityTransition(state: .paused, control: .pause),
            activity: invalidPause,
            control: .pause
        )
        assertActivityError(
            .unsupportedCapability(.pause),
            activity: running,
            control: .pause,
            capabilities: makeCapabilities(features: [.progressReporting])
        )

        let plan = try FolderComparisonWorkflowPlanner.planActivityControl(
            FolderComparisonActivityControlRequest(
                activity: running,
                control: .pause,
                capabilities: capabilities
            )
        )
        let stale = FolderComparisonActivitySnapshot(
            identity: running.identity,
            revision: running.revision + 1,
            kind: running.kind,
            state: running.state,
            supportedControls: running.supportedControls,
            progress: running.progress
        )
        assertWorkflowError(.staleActivity) {
            try plan.validateCurrentActivity(stale)
        }
        assertWorkflowError(.staleCapabilityRevision) {
            try plan.validateCurrentCapabilities(
                makeCapabilities(revision: capabilities.revision + 1, features: capabilities.features)
            )
        }

        let regressed = FolderComparisonActivitySnapshot(
            identity: running.identity,
            revision: plan.expectedSuccessorRevision,
            kind: running.kind,
            state: plan.expectedSuccessorState,
            supportedControls: plan.expectedSuccessorSupportedControls,
            progress: FolderComparisonActivityProgress(
                completedUnits: 0,
                totalUnits: running.progress.totalUnits,
                completedItems: 0,
                totalItems: running.progress.totalItems
            )
        )
        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.completedActivityControl(
                plan: plan,
                activity: regressed
            )
        }
    }

    func testComparisonAndOpenReceiptFactoriesPreservePrePostSnapshots() throws {
        let roots = makeRoots()
        let comparePlan = try FolderComparisonWorkflowPlanner.planComparison(
            compareRequest(roots: roots, target: initialTarget())
        )
        let row = makePairedRow(path: "pair.txt", roots: roots, seed: 10)
        let completedSnapshot = makeSnapshot(
            identity: comparePlan.target.identity,
            roots: roots,
            rows: [row],
            generation: comparePlan.target.generation,
            owner: comparePlan.target.owner,
            scanIntent: comparePlan.scanIntent,
            settings: comparePlan.comparisonSettings
        )
        guard
            case .completed(let comparisonReceipt) =
                try FolderComparisonExecutionReceiptFactory
                .completedComparison(plan: comparePlan, snapshot: completedSnapshot)
        else {
            return XCTFail("Expected completed comparison")
        }
        XCTAssertNil(comparisonReceipt.preEffectSnapshot)
        XCTAssertEqual(
            comparisonReceipt.postEffectSnapshot,
            try FolderComparisonWorkflowPlanner.reference(to: completedSnapshot)
        )

        let openPlan = try FolderComparisonWorkflowPlanner.planOpenFilePair(
            FolderComparisonOpenFilePairRequest(
                snapshot: completedSnapshot,
                id: row.result.id,
                capabilities: capabilities
            )
        )
        guard
            case .completed(let openReceipt) = FolderComparisonExecutionReceiptFactory.completedOpen(
                plan: openPlan
            )
        else {
            return XCTFail("Expected completed open")
        }
        XCTAssertEqual(openReceipt.preEffectSnapshot, openPlan.snapshot)
        XCTAssertNil(openReceipt.postEffectSnapshot)
        XCTAssertEqual(openReceipt.openedResultID, row.result.id)

        let incomplete = makeSnapshot(
            identity: comparePlan.target.identity,
            roots: roots,
            rows: [row],
            generation: comparePlan.target.generation,
            owner: comparePlan.target.owner,
            scanIntent: comparePlan.scanIntent,
            settings: comparePlan.comparisonSettings,
            isComplete: false
        )
        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.completedComparison(
                plan: comparePlan,
                snapshot: incomplete
            )
        }
    }

    func testFailureCancellationAndUncertainOutcomesAcceptOnlyLegalPlanStates() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "item.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        let operation = try planOperation(
            snapshot: snapshot,
            selection: .copy(ids: [row.result.id], from: .left, collision: .fail)
        )
        let workflowPlan = FolderComparisonWorkflowPlan.fileOperation(operation)

        guard
            case .failed(let failure) = try FolderComparisonExecutionReceiptFactory.failed(
                plan: workflowPlan,
                code: .fileOperationFailed
            )
        else {
            return XCTFail("Expected failed outcome")
        }
        XCTAssertEqual(failure.planSHA256, operation.receipt.planSHA256)
        XCTAssertEqual(failure.completedActionCount, 0)
        XCTAssertTrue(failure.actionReceipts.isEmpty)

        guard
            case .cancelled(let cancellation) = try FolderComparisonExecutionReceiptFactory.cancelled(
                plan: workflowPlan
            )
        else {
            return XCTFail("Expected cancelled outcome")
        }
        XCTAssertEqual(cancellation.preEffectSnapshot, operation.snapshot)
        XCTAssertEqual(cancellation.completedActionCount, 0)

        guard
            case .uncertain(let uncertainty) = try FolderComparisonExecutionReceiptFactory.uncertain(
                plan: workflowPlan
            )
        else {
            return XCTFail("Expected uncertain outcome")
        }
        XCTAssertEqual(uncertainty.code, .outcomeUncertain)

        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.failed(
                plan: workflowPlan,
                code: .openFailed
            )
        }

        let presentation = try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(snapshot: snapshot, capabilities: capabilities)
        )
        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.uncertain(
                plan: .presentation(presentation)
            )
        }
    }

    func testCompletedCreateCopyReceiptRequiresExactActionAndChainedPostSnapshot() throws {
        let roots = makeRoots()
        let source = makeOneSidedRow(path: "copy.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [source])
        let plan = try planOperation(
            snapshot: snapshot,
            selection: .copy(ids: [source.result.id], from: .left, collision: .fail)
        )
        let action = try XCTUnwrap(plan.actions.first)
        let sourceRevision = try XCTUnwrap(action.sourceRevision)
        let destinationRevision = makeItemRevision(
            root: roots.right,
            path: action.destinationRelativePath,
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds,
            contentSeed: 10,
            seed: 50
        )
        let rightRootPost = replacingRootRevision(roots.right.revision, metadataSHA256: digest(51))
        let actionReceipt = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: actionSHA256(action),
            disposition: .completed,
            destinationPostRevision: destinationRevision,
            sourcePostRevision: sourceRevision,
            sourceRootPostRevision: roots.left.revision,
            destinationRootPostRevision: rightRootPost
        )
        let postResult = DirectoryResult(
            left: source.result.left,
            right: makeMetadata(
                path: action.destinationRelativePath,
                byteCount: sourceRevision.byteCount,
                seconds: sourceRevision.modificationTimeSeconds
            ),
            status: .identical
        )
        let postRevision = FolderComparisonResultRevision(
            id: postResult.id,
            left: sourceRevision,
            right: destinationRevision
        )
        let postSnapshot = makePostOperationSnapshot(
            from: snapshot,
            roots: replacingRoot(roots, side: .right, revision: rightRootPost),
            results: [postResult],
            revisions: [postRevision]
        )

        guard
            case .completed(let receipt) =
                try FolderComparisonExecutionReceiptFactory
                .completedFileOperation(
                    plan: plan,
                    actionReceipts: [actionReceipt],
                    postEffectSnapshot: postSnapshot
                )
        else {
            return XCTFail("Expected completed copy")
        }
        XCTAssertEqual(receipt.planSHA256, plan.receipt.planSHA256)
        XCTAssertEqual(receipt.preEffectSnapshot, plan.snapshot)
        XCTAssertEqual(
            receipt.postEffectSnapshot,
            try FolderComparisonWorkflowPlanner.reference(to: postSnapshot)
        )
        XCTAssertEqual(receipt.completedActionCount, 1)
        XCTAssertEqual(receipt.actionReceipts, [actionReceipt])

        let wrongDigest = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: digest(0),
            disposition: .completed,
            destinationPostRevision: destinationRevision,
            sourcePostRevision: sourceRevision,
            sourceRootPostRevision: roots.left.revision,
            destinationRootPostRevision: rightRootPost
        )
        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: plan,
                actionReceipts: [wrongDigest],
                postEffectSnapshot: postSnapshot
            )
        }
    }

    func testCompletedMoveDeleteReplaceAndSkipReceiptsEnforcePostStates() throws {
        try assertCompletedMoveReceipt()
        try assertCompletedDeleteReceipt()
        try assertCompletedReplaceReceipt()
        try assertCompletedSkipReceipt()
    }

    func testReceiptFactoryRejectsWrongCountsRevisionsRootsAndReplacementOwner() throws {
        let roots = makeRoots()
        let source = makeOneSidedRow(path: "copy.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [source])
        let plan = try planOperation(
            snapshot: snapshot,
            selection: .copy(ids: [source.result.id], from: .left, collision: .fail)
        )
        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: plan,
                actionReceipts: [],
                postEffectSnapshot: snapshot
            )
        }

        let action = try XCTUnwrap(plan.actions.first)
        let sourceRevision = try XCTUnwrap(action.sourceRevision)
        let destinationRevision = makeItemRevision(
            root: roots.right,
            path: "copy.txt",
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds,
            contentSeed: 10,
            seed: 60
        )
        let receipt = FolderComparisonFileActionReceipt(
            actionIndex: 1,
            actionSHA256: actionSHA256(action),
            disposition: .completed,
            destinationPostRevision: destinationRevision,
            sourcePostRevision: sourceRevision,
            sourceRootPostRevision: roots.left.revision,
            destinationRootPostRevision: roots.right.revision
        )
        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: plan,
                actionReceipts: [receipt],
                postEffectSnapshot: snapshot
            )
        }

        let validIndex = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: actionSHA256(action),
            disposition: .completed,
            destinationPostRevision: destinationRevision,
            sourcePostRevision: sourceRevision,
            sourceRootPostRevision: roots.left.revision,
            destinationRootPostRevision: roots.right.revision,
            replacementOwnerRevision: 1
        )
        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: plan,
                actionReceipts: [validIndex],
                postEffectSnapshot: snapshot
            )
        }
    }

    func testPlanDigestIncludesEveryWorkflowLimitAndIsDeterministic() throws {
        let roots = makeRoots()
        let base = makeLimits()
        let scanIntent = makeScanIntent(maximumRelativePathUTF8Bytes: 512)
        let variants = [
            makeLimits(maximumResultItems: base.maximumResultItems - 1),
            makeLimits(maximumSelectedItems: base.maximumSelectedItems - 1),
            makeLimits(maximumOperationActions: base.maximumOperationActions - 1),
            makeLimits(maximumPresentationRows: base.maximumPresentationRows - 1),
            makeLimits(maximumColumns: base.maximumColumns - 1),
            makeLimits(maximumSortDescriptors: base.maximumSortDescriptors - 1),
            makeLimits(maximumFilterRules: base.maximumFilterRules - 1),
            makeLimits(maximumStringUTF8Bytes: base.maximumStringUTF8Bytes - 1),
            makeLimits(maximumTotalStringUTF8Bytes: base.maximumTotalStringUTF8Bytes - 1),
            makeLimits(maximumMetadataDigestBytes: base.maximumMetadataDigestBytes - 1),
            makeLimits(maximumWorkUnits: base.maximumWorkUnits - 1),
            makeLimits(cancellationCheckInterval: base.cancellationCheckInterval - 1)
        ]
        let basePlan = try FolderComparisonWorkflowPlanner.planComparison(
            compareRequest(
                roots: roots,
                target: initialTarget(),
                scanIntent: scanIntent,
                limits: base
            )
        )
        let repeated = try FolderComparisonWorkflowPlanner.planComparison(
            compareRequest(
                roots: roots,
                target: initialTarget(),
                scanIntent: scanIntent,
                limits: base
            )
        )
        XCTAssertEqual(basePlan.receipt.planSHA256, repeated.receipt.planSHA256)
        for limits in variants {
            let changed = try FolderComparisonWorkflowPlanner.planComparison(
                compareRequest(
                    roots: roots,
                    target: initialTarget(),
                    scanIntent: scanIntent,
                    limits: limits
                )
            )
            XCTAssertNotEqual(changed.receipt.planSHA256, basePlan.receipt.planSHA256)
        }
    }

    func testLimitValidationCoversEveryHardBoundaryAndRelationalGuard() throws {
        let roots = makeRoots()
        let target = initialTarget()
        let invalid: [(FolderComparisonWorkflowLimits, FolderComparisonWorkflowError)] = [
            (
                makeLimits(maximumResultItems: -1),
                .invalidLimit(.resultItems, value: "-1")
            ),
            (
                makeLimits(maximumSelectedItems: -1),
                .invalidLimit(.selectedItems, value: "-1")
            ),
            (
                makeLimits(maximumOperationActions: -1),
                .invalidLimit(.operationActions, value: "-1")
            ),
            (
                makeLimits(maximumPresentationRows: -1),
                .invalidLimit(.presentationRows, value: "-1")
            ),
            (
                makeLimits(maximumColumns: 0),
                .invalidLimit(.columns, value: "0")
            ),
            (
                makeLimits(maximumSortDescriptors: 0),
                .invalidLimit(.sortDescriptors, value: "0")
            ),
            (
                makeLimits(maximumFilterRules: -1),
                .invalidLimit(.filterRules, value: "-1")
            ),
            (
                makeLimits(maximumStringUTF8Bytes: 0),
                .invalidLimit(.stringUTF8Bytes, value: "0")
            ),
            (
                makeLimits(maximumTotalStringUTF8Bytes: 0),
                .invalidLimit(.totalStringUTF8Bytes, value: "0")
            ),
            (
                makeLimits(maximumMetadataDigestBytes: 31),
                .invalidLimit(.metadataDigestBytes, value: "31")
            ),
            (
                makeLimits(maximumWorkUnits: 0),
                .invalidLimit(.workUnits, value: "0")
            ),
            (
                makeLimits(cancellationCheckInterval: 0),
                .invalidLimit(.cancellationCheckInterval, value: "0")
            ),
            (
                makeLimits(
                    maximumResultItems: 1,
                    maximumSelectedItems: 2,
                    maximumPresentationRows: 1
                ),
                .invalidLimit(.selectedItems, value: "2")
            ),
            (
                makeLimits(
                    maximumResultItems: 1,
                    maximumSelectedItems: 1,
                    maximumPresentationRows: 2
                ),
                .invalidLimit(.presentationRows, value: "2")
            )
        ]
        for (limits, error) in invalid {
            assertWorkflowError(error) {
                try FolderComparisonWorkflowPlanner.planComparison(
                    compareRequest(roots: roots, target: target, limits: limits)
                )
            }
        }
    }

    func testStringResultAndMetadataDigestBoundariesAreExact() throws {
        let roots = makeRoots()
        let eight = makeOneSidedRow(path: "12345678", side: .left, roots: roots, seed: 10)
        let exactLimits = makeLimits(maximumStringUTF8Bytes: 8)
        let exactScan = makeScanIntent(maximumRelativePathUTF8Bytes: 8)
        XCTAssertNoThrow(
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(roots: roots, rows: [eight], scanIntent: exactScan),
                limits: exactLimits
            )
        )
        let nine = makeOneSidedRow(path: "123456789", side: .left, roots: roots, seed: 20)
        assertWorkflowError(.invalidResultPath(nine.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(roots: roots, rows: [nine], scanIntent: exactScan),
                limits: exactLimits
            )
        }

        let paths = ["", "/absolute", ".", "..", "a/../b", "a/./b", "a//b", "a\0b"]
        for path in paths {
            let malformed = makeOneSidedRow(path: path, side: .left, roots: roots, seed: 40)
            assertWorkflowError(.invalidResultPath(malformed.result.id)) {
                try FolderComparisonWorkflowPlanner.reference(
                    to: makeSnapshot(roots: roots, rows: [malformed])
                )
            }
        }
    }

    func testWorkBoundCoversSortLookupsAndPathBytes() throws {
        let roots = makeRoots()
        let rows = (0..<8).map { index in
            makeOneSidedRow(
                path: String(repeating: "x", count: 32) + String(format: "%02d", index),
                side: index.isMultiple(of: 2) ? .left : .right,
                roots: roots,
                seed: UInt8(10 + index)
            )
        }
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        let lowLimits = makeLimits(maximumWorkUnits: 600)
        assertWorkflowError(.workLimitExceeded(maximumUnits: 600)) {
            try FolderComparisonWorkflowPlanner.planPresentation(
                FolderComparisonPresentationRequest(
                    snapshot: snapshot,
                    configuration: FolderComparisonPresentationConfiguration(
                        filter: FolderComparisonPresentationFilter(pathQuery: "x"),
                        sortDescriptors: [
                            FolderComparisonPresentationSortDescriptor(key: .path),
                            FolderComparisonPresentationSortDescriptor(key: .status)
                        ]
                    ),
                    capabilities: capabilities,
                    limits: lowLimits
                )
            )
        }

        let target = rows.last!.result.id
        assertWorkflowError(.workLimitExceeded(maximumUnits: 600)) {
            try FolderComparisonWorkflowPlanner.planOpenFilePair(
                FolderComparisonOpenFilePairRequest(
                    snapshot: snapshot,
                    id: target,
                    capabilities: capabilities,
                    limits: lowLimits
                )
            )
        }
    }

    func testCancellationIsCooperativeAtConfiguredInterval() async throws {
        let roots = makeRoots()
        let rows = (0..<64).map { index in
            makeOneSidedRow(
                path: "folder/" + String(repeating: "x", count: 128) + "\(index)",
                side: index.isMultiple(of: 2) ? .left : .right,
                roots: roots,
                seed: UInt8(index % 200 + 20)
            )
        }
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        let limits = makeLimits(cancellationCheckInterval: 1)
        let currentCapabilities = capabilities
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FolderComparisonWorkflowPlanner.planPresentation(
                FolderComparisonPresentationRequest(
                    snapshot: snapshot,
                    capabilities: currentCapabilities,
                    limits: limits
                )
            )
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? FolderComparisonWorkflowError, .cancelled)
        }
    }

    func testExecutorContractAndPublicEnumMappingsAreComplete() {
        let contract = FolderComparisonWorkflowExecutorContract.required
        XCTAssertEqual(contract.pathResolution, .descriptorRelativeNoFollowFromPinnedCanonicalRoots)
        XCTAssertEqual(contract.scanning, .boundedEnumerationWithExactRootRevisionHeldBeforeDuringAndAfterScan)
        XCTAssertEqual(contract.comparison, .immutableSnapshotsAndBoundedDigestProviderWithExactResultGenerationPublish)
        XCTAssertEqual(contract.authority, .balancedAuthorityAcquisitionAroundValidationAndEffects)
        XCTAssertEqual(contract.fileOperations, .executeExactOrderedActionsWithRootAndItemCASAndDurableBackedUpMutation)
        XCTAssertEqual(contract.progress, .monotonicRevisionedProgressWithAcknowledgedPauseResumeAndCancel)
        XCTAssertEqual(contract.opening, .openRegularPairByDescriptorWithoutFollowingLinksAndHoldRevisionsThroughDispatch)
        XCTAssertEqual(contract.presentation, .consumeExactOrderedRowsWithoutFilesystemOrWorkflowMutation)
        XCTAssertEqual(contract.cancellation, .cooperativeBeforeEffectsAndCompletedFailedCancelledOrUncertainAfterEffectsStart)

        XCTAssertEqual(FolderComparisonMethodSelection.metadataOnly.comparatorMethod, .metadataOnly)
        XCTAssertEqual(FolderComparisonMethodSelection.contentIfAvailable.comparatorMethod, .contentIfAvailable)
        XCTAssertEqual(FolderComparisonMethodSelection.contentRequired.comparatorMethod, .contentRequired)
        XCTAssertEqual(FolderPathCaseSensitivitySelection.sensitive.comparatorValue, .sensitive)
        XCTAssertEqual(FolderPathCaseSensitivitySelection.insensitive.comparatorValue, .insensitive)
        XCTAssertEqual(FolderComparisonFileCollisionSelection.fail.operationPolicy, .fail)
        XCTAssertEqual(FolderComparisonFileCollisionSelection.skip.operationPolicy, .skip)
        XCTAssertEqual(FolderComparisonFileCollisionSelection.replaceKeepingBackup.operationPolicy, .replaceKeepingBackup)
        for status in DirectoryComparisonStatus.allCases {
            XCTAssertEqual(FolderComparisonStateIcon(status: status).rawValue, statusName(status))
        }
    }

    func testCompareRootCASRejectsEveryIdentityRevisionURLAuthorityAndCaseMutation() throws {
        let roots = makeRoots()
        let plan = try FolderComparisonWorkflowPlanner.planComparison(
            compareRequest(roots: roots, target: initialTarget())
        )
        let left = roots.left
        let identity = left.revision.identity
        let revision = left.revision
        let identityMutations = [
            FolderComparisonRootIdentity(
                canonicalURL: URL(filePath: "/left-other"),
                deviceID: identity.deviceID,
                fileID: identity.fileID,
                generation: identity.generation
            ),
            FolderComparisonRootIdentity(
                canonicalURL: identity.canonicalURL,
                deviceID: identity.deviceID + 1,
                fileID: identity.fileID,
                generation: identity.generation
            ),
            FolderComparisonRootIdentity(
                canonicalURL: identity.canonicalURL,
                deviceID: identity.deviceID,
                fileID: identity.fileID + 1,
                generation: identity.generation
            ),
            FolderComparisonRootIdentity(
                canonicalURL: identity.canonicalURL,
                deviceID: identity.deviceID,
                fileID: identity.fileID,
                generation: identity.generation + 1
            )
        ]
        var mutations = identityMutations.map {
            replacingRoot(roots, side: .left, revision: replacingRootRevision(revision, identity: $0))
        }
        let revisionMutations = [
            replacingRootRevision(revision, linkCount: revision.linkCount + 1),
            replacingRootRevision(revision, permissions: revision.permissions ^ 0o001),
            replacingRootRevision(revision, ownerID: revision.ownerID + 1),
            replacingRootRevision(revision, groupID: revision.groupID + 1),
            replacingRootRevision(revision, flags: revision.flags + 1),
            replacingRootRevision(
                revision,
                modificationTimeSeconds: revision.modificationTimeSeconds + 1
            ),
            replacingRootRevision(
                revision,
                modificationTimeNanoseconds: revision.modificationTimeNanoseconds + 1
            ),
            replacingRootRevision(
                revision,
                statusChangeTimeSeconds: revision.statusChangeTimeSeconds + 1
            ),
            replacingRootRevision(
                revision,
                statusChangeTimeNanoseconds: revision.statusChangeTimeNanoseconds + 1
            ),
            replacingRootRevision(revision, metadataSHA256: digest(201))
        ]
        mutations += revisionMutations.map { replacingRoot(roots, side: .left, revision: $0) }
        mutations += [
            replacingRoot(roots, side: .left, requestedURL: URL(filePath: "/left-alias")),
            replacingRoot(roots, side: .left, authorityIdentity: uuid(201)),
            replacingRoot(roots, side: .left, authorityRevision: left.authority.revision + 1),
            replacingRoot(
                roots,
                side: .left,
                permissions: left.authority.permissions.subtracting([.mutate])
            ),
            replacingRoot(roots, side: .left, acquisition: .callerManagedWhenRequired),
            replacingRoot(
                roots,
                side: .left,
                acquisition: .securityScoped(
                    resourceURL: URL(filePath: "/left"),
                    coverage: .directoryTree
                )
            ),
            replacingRoot(roots, side: .left, caseSensitivity: .insensitive)
        ]

        for mutation in mutations {
            assertWorkflowError(.staleSnapshot) {
                try plan.validateCurrentRoots(mutation)
            }
        }
    }

    func testSnapshotRejectsEqualCountWrongResultRevisionID() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "item.txt", side: .left, roots: roots, seed: 10)
        let wrongID = DirectoryResult.ID(leftRelativePath: "other.txt", rightRelativePath: nil)
        let wrongRevision = FolderComparisonResultRevision(
            id: wrongID,
            left: row.revision.left,
            right: nil
        )

        assertWorkflowError(.invalidResultRevision(row.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(
                    roots: roots,
                    results: [row.result],
                    revisions: [wrongRevision]
                )
            )
        }
    }

    func testContentRequiredTruthTableForFilesDirectoriesAndStatuses() throws {
        let roots = makeRoots()
        let cases: [ContentRequiredCase] = [
            .init(name: "file equal", kind: .file, metadataEqual: true, content: .equal, status: .identical, valid: true),
            .init(name: "file equal marked different", kind: .file, metadataEqual: true, content: .equal, status: .different, valid: false),
            .init(name: "file content differs", kind: .file, metadataEqual: true, content: .different, status: .different, valid: true),
            .init(name: "file content differs marked identical", kind: .file, metadataEqual: true, content: .different, status: .identical, valid: false),
            .init(name: "file metadata differs", kind: .file, metadataEqual: false, content: .equal, status: .different, valid: true),
            .init(name: "file metadata differs marked identical", kind: .file, metadataEqual: false, content: .equal, status: .identical, valid: false),
            .init(name: "file left digest missing", kind: .file, metadataEqual: true, content: .leftMissing, status: .different, valid: false),
            .init(name: "file right digest missing", kind: .file, metadataEqual: true, content: .rightMissing, status: .identical, valid: false),
            .init(name: "file both digests missing", kind: .file, metadataEqual: true, content: .bothMissing, status: .different, valid: false),
            .init(name: "directory equal", kind: .directory, metadataEqual: true, content: .bothMissing, status: .identical, valid: true),
            .init(name: "directory equal marked different", kind: .directory, metadataEqual: true, content: .bothMissing, status: .different, valid: false),
            .init(name: "directory differs", kind: .directory, metadataEqual: false, content: .bothMissing, status: .different, valid: true),
            .init(name: "directory differs marked identical", kind: .directory, metadataEqual: false, content: .bothMissing, status: .identical, valid: false)
        ]
        for (offset, testCase) in cases.enumerated() {
            let path = "truth-\(offset)"
            let leftSize: UInt64? = testCase.kind == .file ? 4 : nil
            let rightSize: UInt64? = testCase.metadataEqual ? leftSize : (testCase.kind == .file ? 5 : nil)
            let rightSeconds: Int64 = testCase.metadataEqual ? 10 : 11
            let left = makeMetadata(path: path, kind: testCase.kind, byteCount: leftSize, seconds: 10)
            let right = makeMetadata(
                path: path,
                kind: testCase.kind,
                byteCount: rightSize,
                seconds: rightSeconds
            )
            let result = DirectoryResult(left: left, right: right, status: testCase.status)
            let leftContent = testCase.content.leftSeed
            let rightContent = testCase.content.rightSeed
            let revision = FolderComparisonResultRevision(
                id: result.id,
                left: makeItemRevision(
                    root: roots.left,
                    path: path,
                    kind: testCase.kind,
                    byteCount: leftSize,
                    contentSeed: leftContent,
                    seed: UInt8(100 + offset * 2)
                ),
                right: makeItemRevision(
                    root: roots.right,
                    path: path,
                    kind: testCase.kind,
                    byteCount: rightSize,
                    seconds: rightSeconds,
                    contentSeed: rightContent,
                    seed: UInt8(101 + offset * 2)
                )
            )
            let snapshot = makeSnapshot(
                roots: roots,
                results: [result],
                revisions: [revision],
                settings: FolderComparisonSettings(method: .contentRequired)
            )
            if testCase.valid {
                XCTAssertNoThrow(
                    try FolderComparisonWorkflowPlanner.reference(to: snapshot),
                    testCase.name
                )
            } else {
                assertWorkflowError(.invalidResultRevision(result.id)) {
                    try FolderComparisonWorkflowPlanner.reference(to: snapshot)
                }
            }
        }
    }

    func testSnapshotCASRejectsInPlaceResultMetadataPhysicalAndRevisionMutations() throws {
        let roots = makeRoots()
        let row = makePairedRow(path: "item.txt", roots: roots, seed: 10)
        let snapshot = makeSnapshot(
            roots: roots,
            rows: [row],
            settings: FolderComparisonSettings(method: .contentRequired)
        )
        let plan = try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(snapshot: snapshot, capabilities: capabilities)
        )
        let left = try XCTUnwrap(row.result.left)
        let right = try XCTUnwrap(row.result.right)
        let leftRevision = try XCTUnwrap(row.revision.left)
        let rightRevision = try XCTUnwrap(row.revision.right)
        let differentResult = DirectoryResult(left: left, right: right, status: .different)
        let differentRevision = FolderComparisonResultRevision(
            id: differentResult.id,
            left: leftRevision,
            right: replacingItemRevision(rightRevision, contentSHA256: .some(digest(220)))
        )
        let hiddenResult = DirectoryResult(
            left: makeMetadata(
                path: left.relativePath,
                byteCount: left.byteCount,
                seconds: 10,
                isHidden: true
            ),
            right: right,
            status: .identical
        )
        let resultMutations = [
            (result: differentResult, revision: differentRevision),
            (result: hiddenResult, revision: row.revision)
        ]
        for mutation in resultMutations {
            assertWorkflowError(.snapshotContentsChanged) {
                try plan.validateCurrentSnapshot(
                    makeSnapshot(
                        roots: roots,
                        results: [mutation.result],
                        revisions: [mutation.revision],
                        settings: snapshot.comparisonSettings
                    )
                )
            }
        }

        let revisionMutations = [
            (replacingItemRevision(leftRevision, deviceID: leftRevision.identity.deviceID + 1), rightRevision),
            (replacingItemRevision(leftRevision, fileID: leftRevision.identity.fileID + 1), rightRevision),
            (replacingItemRevision(leftRevision, generation: leftRevision.identity.generation + 1), rightRevision),
            (replacingItemRevision(leftRevision, permissions: leftRevision.permissions ^ 0o001), rightRevision),
            (replacingItemRevision(leftRevision, ownerID: leftRevision.ownerID + 1), rightRevision),
            (replacingItemRevision(leftRevision, groupID: leftRevision.groupID + 1), rightRevision),
            (replacingItemRevision(leftRevision, flags: leftRevision.flags + 1), rightRevision),
            (
                replacingItemRevision(
                    leftRevision,
                    statusChangeTimeSeconds: leftRevision.statusChangeTimeSeconds + 1
                ),
                rightRevision
            ),
            (replacingItemRevision(leftRevision, metadataSHA256: digest(221)), rightRevision),
            (
                replacingItemRevision(leftRevision, contentSHA256: .some(digest(222))),
                replacingItemRevision(rightRevision, contentSHA256: .some(digest(222)))
            )
        ]
        for mutation in revisionMutations {
            let changedRevision = FolderComparisonResultRevision(
                id: row.result.id,
                left: mutation.0,
                right: mutation.1
            )
            assertWorkflowError(.snapshotContentsChanged) {
                try plan.validateCurrentSnapshot(
                    makeSnapshot(
                        roots: roots,
                        results: [row.result],
                        revisions: [changedRevision],
                        settings: snapshot.comparisonSettings
                    )
                )
            }
        }
    }

    func testPresentationSortMatrixCoversEveryKeyDirectionNilAndStableTies() throws {
        let roots = makeRoots()
        let rows = makeSortRows(roots: roots)
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        let expectations: [(FolderComparisonPresentationSortKey, ascending: [Int], descending: [Int])] = [
            (.path, ascending: [1, 2, 0], descending: [0, 2, 1]),
            (.status, ascending: [0, 2, 1], descending: [1, 2, 0]),
            (.kind, ascending: [0, 1, 2], descending: [0, 1, 2]),
            (.leftSize, ascending: [0, 2, 1], descending: [1, 2, 0]),
            (.rightSize, ascending: [1, 0, 2], descending: [2, 0, 1]),
            (.leftModificationDate, ascending: [0, 2, 1], descending: [1, 2, 0]),
            (.rightModificationDate, ascending: [1, 0, 2], descending: [2, 0, 1])
        ]
        for expectation in expectations {
            for order in FolderComparisonPresentationSortOrder.allCases {
                let plan = try FolderComparisonWorkflowPlanner.planPresentation(
                    FolderComparisonPresentationRequest(
                        snapshot: snapshot,
                        configuration: FolderComparisonPresentationConfiguration(
                            sortDescriptors: [
                                FolderComparisonPresentationSortDescriptor(
                                    key: expectation.0,
                                    order: order
                                )
                            ]
                        ),
                        capabilities: capabilities
                    )
                )
                let expectedOffsets =
                    order == .ascending
                    ? expectation.ascending
                    : expectation.descending
                XCTAssertEqual(
                    plan.rows.map(\.id),
                    expectedOffsets.map { rows[$0].result.id },
                    "\(expectation.0.rawValue)-\(order.rawValue)"
                )
            }
        }

        let tieSnapshot = makeSnapshot(roots: roots, rows: [rows[0], rows[2]])
        for order in FolderComparisonPresentationSortOrder.allCases {
            let plan = try FolderComparisonWorkflowPlanner.planPresentation(
                FolderComparisonPresentationRequest(
                    snapshot: tieSnapshot,
                    configuration: FolderComparisonPresentationConfiguration(
                        sortDescriptors: [
                            FolderComparisonPresentationSortDescriptor(key: .kind, order: order)
                        ]
                    ),
                    capabilities: capabilities
                )
            )
            XCTAssertEqual(plan.rows.map(\.id), tieSnapshot.results.map(\.id))
        }
    }

    func testOperationActionBindsSourceDestinationRootsAuthoritiesAndPreRevisionsIndependently() throws {
        let roots = makeRoots()
        let pair = makePairedRow(
            leftPath: "item.txt",
            rightPath: "item.txt",
            status: .different,
            roots: roots,
            leftByteCount: 4,
            rightByteCount: 8,
            seed: 10
        )
        let plan = try planOperation(
            snapshot: makeSnapshot(roots: roots, rows: [pair]),
            selection: .copy(ids: [pair.result.id], from: .left, collision: .skip)
        )
        let action = try XCTUnwrap(plan.actions.first)
        let sourceRoot = try XCTUnwrap(action.sourceRoot)

        XCTAssertEqual(sourceRoot.identity, roots.left.revision.identity)
        XCTAssertEqual(sourceRoot.preEffectRevision, roots.left.revision)
        XCTAssertEqual(sourceRoot.authorityIdentity, roots.left.authority.identity)
        XCTAssertEqual(sourceRoot.authorityRevision, roots.left.authority.revision)
        XCTAssertEqual(action.source, pair.result.left)
        XCTAssertEqual(action.sourceRevision, pair.revision.left)
        XCTAssertEqual(action.destinationRoot.identity, roots.right.revision.identity)
        XCTAssertEqual(action.destinationRoot.preEffectRevision, roots.right.revision)
        XCTAssertEqual(action.destinationRoot.authorityIdentity, roots.right.authority.identity)
        XCTAssertEqual(action.destinationRoot.authorityRevision, roots.right.authority.revision)
        XCTAssertEqual(action.destination, pair.result.right)
        guard case .existing(let destinationRevision) = action.destinationPrecondition else {
            return XCTFail("Expected existing destination precondition")
        }
        XCTAssertEqual(destinationRevision, pair.revision.right)
    }

    func testCaseFoldedOccupiedSlotCannotProduceAbsenceWitness() throws {
        let base = makeRoots()
        let roots = FolderComparisonRootPair(
            left: base.left,
            right: replacingRoot(base.right, caseSensitivity: .insensitive)
        )
        let source = makeOneSidedRow(path: "Report.txt", side: .left, roots: roots, seed: 10)
        let occupied = makeOneSidedRow(path: "report.TXT", side: .right, roots: roots, seed: 20)
        let snapshot = makeSnapshot(roots: roots, rows: [source, occupied])

        assertOperationError(
            .absenceNotProvable(side: .right, relativePath: "Report.txt"),
            snapshot: snapshot,
            selection: .copy(ids: [source.result.id], from: .left, collision: .fail)
        )
    }

    func testSynchronizeCopyAndDeletePlansCarryExactActionsCASAndReceipts() throws {
        let roots = makeRoots()
        let source = makeOneSidedRow(path: "sync-copy.txt", side: .left, roots: roots, seed: 10)
        let copySnapshot = makeSnapshot(roots: roots, rows: [source])
        let copyPlan = try planOperation(
            snapshot: copySnapshot,
            selection: .synchronize(
                ids: [source.result.id],
                from: .left,
                collision: .fail,
                deleteExtraneous: false
            )
        )
        let copyAction = try XCTUnwrap(copyPlan.actions.first)
        XCTAssertEqual(copyAction.kind, .copy)
        XCTAssertEqual(copyAction.sourceSide, .left)
        XCTAssertEqual(copyAction.destinationSide, .right)
        XCTAssertEqual(copyAction.sourceRevision, source.revision.left)
        guard case .absent(let copyWitness) = copyAction.destinationPrecondition else {
            return XCTFail("Expected synchronize-copy absence witness")
        }
        guard case .root(let copyParent) = copyWitness.parent else {
            return XCTFail("Expected synchronize-copy root witness")
        }
        XCTAssertEqual(copyParent, roots.right.revision)
        XCTAssertNoThrow(try completeCreateOperation(plan: copyPlan, snapshot: copySnapshot, seed: 150))

        let extraneous = makeOneSidedRow(path: "sync-delete.txt", side: .right, roots: roots, seed: 20)
        let deleteSnapshot = makeSnapshot(roots: roots, rows: [extraneous])
        let owner = FolderComparisonReplacementOwner(identity: replacementOwnerID, revision: 12)
        let deletePlan = try planOperation(
            snapshot: deleteSnapshot,
            selection: .synchronize(
                ids: [extraneous.result.id],
                from: .left,
                collision: .fail,
                deleteExtraneous: true
            ),
            replacementOwner: owner
        )
        let deleteAction = try XCTUnwrap(deletePlan.actions.first)
        XCTAssertEqual(deleteAction.kind, .delete)
        XCTAssertNil(deleteAction.sourceSide)
        XCTAssertEqual(deleteAction.destinationSide, .right)
        XCTAssertEqual(deleteAction.destination, extraneous.result.right)
        XCTAssertEqual(deleteAction.replacementOwner, owner)
        guard case .existing(let deletePrecondition) = deleteAction.destinationPrecondition else {
            return XCTFail("Expected synchronize-delete existing precondition")
        }
        XCTAssertEqual(deletePrecondition, extraneous.revision.right)
        XCTAssertNoThrow(
            try completeDeleteOperation(
                plan: deletePlan,
                snapshot: deleteSnapshot,
                owner: owner,
                seed: 160
            )
        )
    }

    func testCapabilityAndReplacementOwnerCASRejectSameRevisionIdentityAndFeatureMutations() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "item.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [row])
        let owner = FolderComparisonReplacementOwner(identity: replacementOwnerID, revision: 5)
        let plan = try planOperation(
            snapshot: snapshot,
            selection: .delete(ids: [row.result.id], side: .left),
            replacementOwner: owner
        )
        let sameRevisionIdentity = FolderComparisonWorkflowCapabilities(
            identity: uuid(230),
            revision: capabilities.revision,
            features: capabilities.features
        )
        let sameRevisionFeatures = FolderComparisonWorkflowCapabilities(
            identity: capabilities.identity,
            revision: capabilities.revision,
            features: capabilities.features.subtracting([.deleteItems])
        )
        for mutation in [sameRevisionIdentity, sameRevisionFeatures] {
            assertWorkflowError(.staleCapabilityRevision) {
                try plan.validateCurrentCapabilities(mutation)
            }
        }
        assertWorkflowError(.staleReplacementOwner) {
            try plan.validateCurrentReplacementOwner(
                FolderComparisonReplacementOwner(identity: uuid(231), revision: owner.revision)
            )
        }
    }

    func testAllActivityControlsProduceReceiptsAndRejectEverySuccessorInvariantMutation() throws {
        let running = makeActivity(
            state: .running,
            controls: [.pause, .cancel],
            revision: 7,
            completedUnits: 3,
            completedItems: 2
        )
        let pausePlan = try controlPlan(activity: running, control: .pause)
        let paused = activitySuccessor(for: pausePlan, progress: running.progress)
        XCTAssertNoThrow(
            try FolderComparisonExecutionReceiptFactory.completedActivityControl(
                plan: pausePlan,
                activity: paused
            )
        )

        let resumePlan = try controlPlan(activity: paused, control: .resume)
        let resumed = activitySuccessor(for: resumePlan, progress: paused.progress)
        XCTAssertNoThrow(
            try FolderComparisonExecutionReceiptFactory.completedActivityControl(
                plan: resumePlan,
                activity: resumed
            )
        )

        let cancelPlan = try controlPlan(activity: running, control: .cancel)
        let cancelling = activitySuccessor(for: cancelPlan, progress: running.progress)
        XCTAssertNoThrow(
            try FolderComparisonExecutionReceiptFactory.completedActivityControl(
                plan: cancelPlan,
                activity: cancelling
            )
        )

        let progress = paused.progress
        let invalidSuccessors = [
            FolderComparisonActivitySnapshot(
                identity: uuid(240),
                revision: paused.revision,
                kind: paused.kind,
                state: paused.state,
                supportedControls: paused.supportedControls,
                progress: progress
            ),
            FolderComparisonActivitySnapshot(
                identity: paused.identity,
                revision: paused.revision + 1,
                kind: paused.kind,
                state: paused.state,
                supportedControls: paused.supportedControls,
                progress: progress
            ),
            FolderComparisonActivitySnapshot(
                identity: paused.identity,
                revision: paused.revision,
                kind: .fileOperation,
                state: paused.state,
                supportedControls: paused.supportedControls,
                progress: progress
            ),
            FolderComparisonActivitySnapshot(
                identity: paused.identity,
                revision: paused.revision,
                kind: paused.kind,
                state: .running,
                supportedControls: paused.supportedControls,
                progress: progress
            ),
            FolderComparisonActivitySnapshot(
                identity: paused.identity,
                revision: paused.revision,
                kind: paused.kind,
                state: paused.state,
                supportedControls: [.pause, .cancel],
                progress: progress
            ),
            activitySuccessor(
                for: pausePlan,
                progress: replacingProgress(progress, completedUnits: progress.completedUnits - 1)
            ),
            activitySuccessor(
                for: pausePlan,
                progress: replacingProgress(progress, completedItems: progress.completedItems - 1)
            ),
            activitySuccessor(
                for: pausePlan,
                progress: replacingProgress(progress, totalUnits: .some((progress.totalUnits ?? 0) + 1))
            ),
            activitySuccessor(
                for: pausePlan,
                progress: replacingProgress(progress, totalItems: .some((progress.totalItems ?? 0) + 1))
            )
        ]
        for successor in invalidSuccessors {
            assertWorkflowError(.invalidExecutionReceipt) {
                try FolderComparisonExecutionReceiptFactory.completedActivityControl(
                    plan: pausePlan,
                    activity: successor
                )
            }
        }
    }

    func testReplacementComparisonCompletionGuardsEveryTargetAndPlanBinding() throws {
        let roots = makeRoots()
        let oldRow = makeOneSidedRow(path: "old.txt", side: .left, roots: roots, seed: 10)
        let replacing = makeSnapshot(roots: roots, rows: [oldRow], generation: 4)
        let target = FolderComparisonWorkflowSnapshotTarget(
            identity: replacing.identity,
            generation: replacing.generation + 1,
            owner: FolderComparisonWorkflowSnapshotOwner(
                identity: replacing.owner.identity,
                revision: replacing.owner.revision + 1
            )
        )
        let request = FolderComparisonCompareRequest(
            target: target,
            replacing: replacing,
            roots: roots,
            scanIntent: replacing.scanIntent,
            comparisonSettings: replacing.comparisonSettings,
            capabilities: capabilities
        )
        let plan = try FolderComparisonWorkflowPlanner.planComparison(request)
        let row = makePairedRow(path: "new.txt", roots: roots, seed: 20)
        let valid = makeSnapshot(
            identity: target.identity,
            roots: roots,
            rows: [row],
            generation: target.generation,
            owner: target.owner,
            scanIntent: plan.scanIntent,
            settings: plan.comparisonSettings
        )
        guard
            case .completed(let receipt) = try FolderComparisonExecutionReceiptFactory.completedComparison(
                plan: plan,
                snapshot: valid
            )
        else {
            return XCTFail("Expected replacement comparison receipt")
        }
        XCTAssertEqual(receipt.preEffectSnapshot, plan.replacing)

        let mutations = [
            makeSnapshot(
                identity: FolderComparisonWorkflowSnapshotIdentity(rawValue: uuid(241)),
                roots: roots,
                rows: [row],
                generation: target.generation,
                owner: target.owner,
                scanIntent: plan.scanIntent,
                settings: plan.comparisonSettings
            ),
            makeSnapshot(
                identity: target.identity,
                roots: roots,
                rows: [row],
                generation: target.generation + 1,
                owner: target.owner,
                scanIntent: plan.scanIntent,
                settings: plan.comparisonSettings
            ),
            makeSnapshot(
                identity: target.identity,
                roots: roots,
                rows: [row],
                generation: target.generation,
                owner: FolderComparisonWorkflowSnapshotOwner(
                    identity: uuid(242),
                    revision: target.owner.revision
                ),
                scanIntent: plan.scanIntent,
                settings: plan.comparisonSettings
            ),
            makeSnapshot(
                identity: target.identity,
                roots: roots,
                rows: [row],
                generation: target.generation,
                owner: FolderComparisonWorkflowSnapshotOwner(
                    identity: target.owner.identity,
                    revision: target.owner.revision + 1
                ),
                scanIntent: plan.scanIntent,
                settings: plan.comparisonSettings
            ),
            makeSnapshot(
                identity: target.identity,
                roots: replacingRoot(roots, side: .left, caseSensitivity: .insensitive),
                rows: [
                    makePairedRow(
                        path: "new.txt",
                        roots: replacingRoot(roots, side: .left, caseSensitivity: .insensitive),
                        seed: 30
                    )
                ],
                generation: target.generation,
                owner: target.owner,
                scanIntent: plan.scanIntent,
                settings: plan.comparisonSettings
            ),
            makeSnapshot(
                identity: target.identity,
                roots: roots,
                rows: [row],
                generation: target.generation,
                owner: target.owner,
                scanIntent: makeScanIntent(recursive: false),
                settings: plan.comparisonSettings
            ),
            makeSnapshot(
                identity: target.identity,
                roots: roots,
                rows: [row],
                generation: target.generation,
                owner: target.owner,
                scanIntent: plan.scanIntent,
                settings: FolderComparisonSettings(modificationDateTolerance: 1)
            )
        ]
        for mutation in mutations {
            assertWorkflowError(.invalidExecutionReceipt) {
                try FolderComparisonExecutionReceiptFactory.completedComparison(
                    plan: plan,
                    snapshot: mutation
                )
            }
        }
    }

    func testOperationReceiptPreservesUntouchedRowsAndRejectsAlteredGrouping() throws {
        let roots = makeRoots()
        let source = makeOneSidedRow(path: "copy.txt", side: .left, roots: roots, seed: 10)
        let untouched = makePairedRow(
            leftPath: "untouched-left.txt",
            rightPath: "untouched-right.txt",
            status: .identical,
            roots: roots,
            leftByteCount: 4,
            rightByteCount: 4,
            seed: 20
        )
        let snapshot = makeSnapshot(roots: roots, rows: [source, untouched])
        let context = try makeCompletedCreateContext(
            snapshot: snapshot,
            source: source,
            selection: .copy(ids: [source.result.id], from: .left, collision: .fail),
            seed: 170
        )
        let copiedResult = DirectoryResult(
            left: source.result.left,
            right: context.destinationMetadata,
            status: .identical
        )
        let copiedRevision = FolderComparisonResultRevision(
            id: copiedResult.id,
            left: source.revision.left,
            right: context.destinationRevision
        )
        let valid = makePostOperationSnapshot(
            from: snapshot,
            roots: context.postRoots,
            results: [copiedResult, untouched.result],
            revisions: [copiedRevision, untouched.revision]
        )
        XCTAssertNoThrow(
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: context.plan,
                actionReceipts: [context.receipt],
                postEffectSnapshot: valid
            )
        )

        let regroupedUntouchedResults = [
            DirectoryResult(
                left: untouched.result.left,
                right: nil,
                status: .leftOnly
            ),
            DirectoryResult(
                left: nil,
                right: untouched.result.right,
                status: .rightOnly
            )
        ]
        let regroupedUntouchedRevisions = [
            FolderComparisonResultRevision(
                id: regroupedUntouchedResults[0].id,
                left: untouched.revision.left,
                right: nil
            ),
            FolderComparisonResultRevision(
                id: regroupedUntouchedResults[1].id,
                left: nil,
                right: untouched.revision.right
            )
        ]
        let alteredGrouping = makePostOperationSnapshot(
            from: snapshot,
            roots: context.postRoots,
            results: [copiedResult] + regroupedUntouchedResults,
            revisions: [copiedRevision] + regroupedUntouchedRevisions
        )
        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: context.plan,
                actionReceipts: [context.receipt],
                postEffectSnapshot: alteredGrouping
            )
        }
    }

    func testOperationReceiptRejectsUntouchedIsHiddenMutation() throws {
        let roots = makeRoots()
        let source = makeOneSidedRow(path: "copy.txt", side: .left, roots: roots, seed: 10)
        let untouched = makeOneSidedRow(path: "plain.txt", side: .left, roots: roots, seed: 20)
        let snapshot = makeSnapshot(roots: roots, rows: [source, untouched])
        let context = try makeCompletedCreateContext(
            snapshot: snapshot,
            source: source,
            selection: .copy(ids: [source.result.id], from: .left, collision: .fail),
            seed: 180
        )
        let copiedResult = DirectoryResult(
            left: source.result.left,
            right: context.destinationMetadata,
            status: .identical
        )
        let copiedRevision = FolderComparisonResultRevision(
            id: copiedResult.id,
            left: source.revision.left,
            right: context.destinationRevision
        )
        let changedUntouchedMetadata = makeMetadata(
            path: "plain.txt",
            byteCount: untouched.result.left?.byteCount,
            isHidden: true
        )
        let changedUntouched = DirectoryResult(
            left: changedUntouchedMetadata,
            right: nil,
            status: .leftOnly
        )
        let post = makePostOperationSnapshot(
            from: snapshot,
            roots: context.postRoots,
            results: [copiedResult, changedUntouched],
            revisions: [copiedRevision, untouched.revision]
        )
        assertWorkflowError(.invalidExecutionReceipt) {
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: context.plan,
                actionReceipts: [context.receipt],
                postEffectSnapshot: post
            )
        }
    }

    func testActionReceiptRejectsEachSourceDestinationAndRootPostRevisionMutation() throws {
        let roots = makeRoots()
        let source = makeOneSidedRow(path: "copy.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [source])
        let context = try makeCompletedCreateContext(
            snapshot: snapshot,
            source: source,
            selection: .copy(ids: [source.result.id], from: .left, collision: .fail),
            seed: 190
        )
        let sourceRevision = try XCTUnwrap(source.revision.left)
        let destinationRevision = context.destinationRevision
        let rightRootPost = context.postRoots.right.revision
        let mutations = [
            FolderComparisonFileActionReceipt(
                actionIndex: 0,
                actionSHA256: context.receipt.actionSHA256,
                disposition: .completed,
                destinationPostRevision: replacingItemRevision(
                    destinationRevision,
                    relativePath: "other.txt"
                ),
                sourcePostRevision: sourceRevision,
                sourceRootPostRevision: roots.left.revision,
                destinationRootPostRevision: rightRootPost
            ),
            FolderComparisonFileActionReceipt(
                actionIndex: 0,
                actionSHA256: context.receipt.actionSHA256,
                disposition: .completed,
                destinationPostRevision: replacingItemRevision(
                    destinationRevision,
                    contentSHA256: .some(digest(191))
                ),
                sourcePostRevision: sourceRevision,
                sourceRootPostRevision: roots.left.revision,
                destinationRootPostRevision: rightRootPost
            ),
            FolderComparisonFileActionReceipt(
                actionIndex: 0,
                actionSHA256: context.receipt.actionSHA256,
                disposition: .completed,
                destinationPostRevision: destinationRevision,
                sourcePostRevision: replacingItemRevision(
                    sourceRevision,
                    metadataSHA256: digest(192)
                ),
                sourceRootPostRevision: roots.left.revision,
                destinationRootPostRevision: rightRootPost
            ),
            FolderComparisonFileActionReceipt(
                actionIndex: 0,
                actionSHA256: context.receipt.actionSHA256,
                disposition: .completed,
                destinationPostRevision: destinationRevision,
                sourcePostRevision: sourceRevision,
                sourceRootPostRevision: replacingRootRevision(
                    roots.left.revision,
                    metadataSHA256: digest(193)
                ),
                destinationRootPostRevision: rightRootPost
            ),
            FolderComparisonFileActionReceipt(
                actionIndex: 0,
                actionSHA256: context.receipt.actionSHA256,
                disposition: .completed,
                destinationPostRevision: destinationRevision,
                sourcePostRevision: sourceRevision,
                sourceRootPostRevision: roots.left.revision,
                destinationRootPostRevision: replacingRootRevision(
                    rightRootPost,
                    metadataSHA256: digest(194)
                )
            )
        ]
        for receipt in mutations {
            assertWorkflowError(.invalidExecutionReceipt) {
                try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                    plan: context.plan,
                    actionReceipts: [receipt],
                    postEffectSnapshot: context.postSnapshot
                )
            }
        }
    }

    func testMetadataDigestLimitFailureIsIsolatedFromExactSHA256Shape() throws {
        let roots = makeRoots()
        let row = makeOneSidedRow(path: "a", side: .left, roots: roots, seed: 10)
        let limits = makeLimits(maximumMetadataDigestBytes: 32)
        XCTAssertNoThrow(
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(roots: roots, rows: [row]),
                limits: limits
            )
        )

        let invalidDigest = replacingItemRevision(
            try XCTUnwrap(row.revision.left),
            metadataSHA256: Array(repeating: 1, count: 33)
        )
        assertWorkflowError(.invalidResultRevision(row.result.id)) {
            try FolderComparisonWorkflowPlanner.reference(
                to: makeSnapshot(
                    roots: roots,
                    results: [row.result],
                    revisions: [
                        FolderComparisonResultRevision(
                            id: row.result.id,
                            left: invalidDigest,
                            right: nil
                        )
                    ]
                ),
                limits: makeLimits(maximumMetadataDigestBytes: 1_024)
            )
        }
    }

    func testSortAndOpenLookupWorkBoundsAreIndependentlyIsolated() throws {
        let roots = makeRoots()
        let rows = makePairedWorkRows(roots: roots, count: 16, pathBytes: 64)
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        let baseConfiguration = FolderComparisonPresentationConfiguration(
            sortDescriptors: [FolderComparisonPresentationSortDescriptor(key: .status)]
        )
        let pathConfiguration = FolderComparisonPresentationConfiguration(
            sortDescriptors: [FolderComparisonPresentationSortDescriptor(key: .path)]
        )
        let baseline = try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(
                snapshot: snapshot,
                configuration: baseConfiguration,
                capabilities: capabilities
            )
        ).receipt.estimatedWorkUnits
        let pathSort = try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(
                snapshot: snapshot,
                configuration: pathConfiguration,
                capabilities: capabilities
            )
        ).receipt.estimatedWorkUnits
        XCTAssertGreaterThan(pathSort, baseline)
        assertWorkflowError(.workLimitExceeded(maximumUnits: pathSort - 1)) {
            try FolderComparisonWorkflowPlanner.planPresentation(
                FolderComparisonPresentationRequest(
                    snapshot: snapshot,
                    configuration: pathConfiguration,
                    capabilities: capabilities,
                    limits: makeLimits(maximumWorkUnits: pathSort - 1)
                )
            )
        }

        let firstOpen = try FolderComparisonWorkflowPlanner.planOpenFilePair(
            FolderComparisonOpenFilePairRequest(
                snapshot: snapshot,
                id: rows.first!.result.id,
                capabilities: capabilities
            )
        ).receipt.estimatedWorkUnits
        let lastOpen = try FolderComparisonWorkflowPlanner.planOpenFilePair(
            FolderComparisonOpenFilePairRequest(
                snapshot: snapshot,
                id: rows.last!.result.id,
                capabilities: capabilities
            )
        ).receipt.estimatedWorkUnits
        XCTAssertGreaterThan(lastOpen, firstOpen)
        assertWorkflowError(.workLimitExceeded(maximumUnits: lastOpen - 1)) {
            try FolderComparisonWorkflowPlanner.planOpenFilePair(
                FolderComparisonOpenFilePairRequest(
                    snapshot: snapshot,
                    id: rows.last!.result.id,
                    capabilities: capabilities,
                    limits: makeLimits(maximumWorkUnits: lastOpen - 1)
                )
            )
        }
    }

    func testCancellationTripsDeterministicallyForSortAndOpenLookupWorkloads() async {
        let roots = makeRoots()
        let rows = makePairedWorkRows(roots: roots, count: 128, pathBytes: 128)
        let snapshot = makeSnapshot(roots: roots, rows: rows)
        let currentCapabilities = capabilities
        let limits = makeLimits(cancellationCheckInterval: 1)
        let sortTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FolderComparisonWorkflowPlanner.planPresentation(
                FolderComparisonPresentationRequest(
                    snapshot: snapshot,
                    configuration: FolderComparisonPresentationConfiguration(
                        sortDescriptors: [FolderComparisonPresentationSortDescriptor(key: .path)]
                    ),
                    capabilities: currentCapabilities,
                    limits: limits
                )
            )
        }
        await assertCancelled(task: sortTask)

        let lookupTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FolderComparisonWorkflowPlanner.planOpenFilePair(
                FolderComparisonOpenFilePairRequest(
                    snapshot: snapshot,
                    id: rows.last!.result.id,
                    capabilities: currentCapabilities,
                    limits: limits
                )
            )
        }
        await assertCancelled(task: lookupTask)
    }

    private let snapshotIdentity = FolderComparisonWorkflowSnapshotIdentity(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    )
    private let snapshotOwnerID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private let capabilityID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    private let replacementOwnerID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
    private let activityID = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!

    private enum ContentFixture {
        case equal
        case different
        case leftMissing
        case rightMissing
        case bothMissing

        var leftSeed: UInt8? {
            switch self {
            case .equal, .different, .rightMissing: 1
            case .leftMissing, .bothMissing: nil
            }
        }

        var rightSeed: UInt8? {
            switch self {
            case .equal, .leftMissing: 1
            case .different: 2
            case .rightMissing, .bothMissing: nil
            }
        }
    }

    private struct ContentRequiredCase {
        let name: String
        let kind: DirectoryEntryKind
        let metadataEqual: Bool
        let content: ContentFixture
        let status: DirectoryComparisonStatus
        let valid: Bool
    }

    private var capabilities: FolderComparisonWorkflowCapabilities {
        makeCapabilities(features: Set(FolderComparisonWorkflowFeature.allCases))
    }

    private func uuid(_ seed: UInt8) -> UUID {
        UUID(
            uuid: (
                seed, 0, 0, 0,
                0, 0, 0, 0,
                0, 0, 0, 0,
                0, 0, 0, 1
            )
        )
    }

    private func digest(_ seed: UInt8, count: Int = SHA256.Digest.byteCount) -> [UInt8] {
        Array(repeating: seed, count: count)
    }

    private func makeCapabilities(
        revision: UInt64 = 1,
        features: Set<FolderComparisonWorkflowFeature>
    ) -> FolderComparisonWorkflowCapabilities {
        FolderComparisonWorkflowCapabilities(
            identity: capabilityID,
            revision: revision,
            features: features
        )
    }

    private func makeRootIdentity(side: FolderComparisonWorkflowSide) -> FolderComparisonRootIdentity {
        FolderComparisonRootIdentity(
            canonicalURL: URL(filePath: side == .left ? "/left" : "/right"),
            deviceID: side == .left ? 1 : 2,
            fileID: side == .left ? 101 : 202,
            generation: side == .left ? 11 : 22
        )
    }

    private func makeRootRevision(
        identity: FolderComparisonRootIdentity,
        linkCount: UInt64 = 2,
        permissions: UInt16 = 0o755,
        ownerID: UInt32 = 501,
        groupID: UInt32 = 20,
        flags: UInt32 = 0,
        modificationTimeSeconds: Int64 = 100,
        modificationTimeNanoseconds: Int32 = 123_456_789,
        statusChangeTimeSeconds: Int64 = 101,
        statusChangeTimeNanoseconds: Int32 = 987_654_321,
        metadataSHA256: [UInt8] = Array(repeating: 1, count: SHA256.Digest.byteCount)
    ) -> FolderComparisonRootRevision {
        FolderComparisonRootRevision(
            identity: identity,
            linkCount: linkCount,
            permissions: permissions,
            ownerID: ownerID,
            groupID: groupID,
            flags: flags,
            modificationTimeSeconds: modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds,
            metadataSHA256: metadataSHA256
        )
    }

    private func replacingRootRevision(
        _ revision: FolderComparisonRootRevision,
        identity: FolderComparisonRootIdentity? = nil,
        linkCount: UInt64? = nil,
        permissions: UInt16? = nil,
        ownerID: UInt32? = nil,
        groupID: UInt32? = nil,
        flags: UInt32? = nil,
        modificationTimeSeconds: Int64? = nil,
        modificationTimeNanoseconds: Int32? = nil,
        statusChangeTimeSeconds: Int64? = nil,
        statusChangeTimeNanoseconds: Int32? = nil,
        metadataSHA256: [UInt8]? = nil
    ) -> FolderComparisonRootRevision {
        makeRootRevision(
            identity: identity ?? revision.identity,
            linkCount: linkCount ?? revision.linkCount,
            permissions: permissions ?? revision.permissions,
            ownerID: ownerID ?? revision.ownerID,
            groupID: groupID ?? revision.groupID,
            flags: flags ?? revision.flags,
            modificationTimeSeconds: modificationTimeSeconds ?? revision.modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds ?? revision.modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds ?? revision.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds ?? revision.statusChangeTimeNanoseconds,
            metadataSHA256: metadataSHA256 ?? revision.metadataSHA256
        )
    }

    private func makeRoot(
        side: FolderComparisonWorkflowSide,
        requestedURL: URL? = nil,
        identity: FolderComparisonRootIdentity? = nil,
        revision: FolderComparisonRootRevision? = nil,
        authorityRootIdentity: FolderComparisonRootIdentity? = nil,
        permissions: Set<FolderComparisonAuthorityPermission> = [.enumerate, .readContent, .mutate],
        coverage: FolderComparisonAuthorityCoverage = .directoryTree,
        acquisition: FolderComparisonAuthorityAcquisition = .ambient,
        caseSensitivity: FolderPathCaseSensitivitySelection = .sensitive
    ) -> FolderComparisonRoot {
        let rootIdentity = identity ?? makeRootIdentity(side: side)
        let rootRevision =
            revision
            ?? makeRootRevision(
                identity: rootIdentity,
                metadataSHA256: digest(side == .left ? 1 : 2)
            )
        return FolderComparisonRoot(
            requestedURL: requestedURL ?? rootIdentity.canonicalURL,
            revision: rootRevision,
            authority: FolderComparisonAccessAuthority(
                identity: uuid(side == .left ? 1 : 2),
                revision: 1,
                rootIdentity: authorityRootIdentity ?? rootRevision.identity,
                permissions: permissions,
                coverage: coverage,
                acquisition: acquisition
            ),
            pathCaseSensitivity: caseSensitivity
        )
    }

    private func makeRoots() -> FolderComparisonRootPair {
        FolderComparisonRootPair(left: makeRoot(side: .left), right: makeRoot(side: .right))
    }

    private func replacingRoot(
        _ roots: FolderComparisonRootPair,
        side: FolderComparisonWorkflowSide,
        requestedURL: URL? = nil,
        identity: FolderComparisonRootIdentity? = nil,
        revision: FolderComparisonRootRevision? = nil,
        authorityRootIdentity: FolderComparisonRootIdentity? = nil,
        authorityIdentity: UUID? = nil,
        authorityRevision: UInt64? = nil,
        permissions: Set<FolderComparisonAuthorityPermission>? = nil,
        coverage: FolderComparisonAuthorityCoverage? = nil,
        acquisition: FolderComparisonAuthorityAcquisition? = nil,
        caseSensitivity: FolderPathCaseSensitivitySelection? = nil
    ) -> FolderComparisonRootPair {
        let old = roots[side]
        let newIdentity = identity ?? revision?.identity ?? old.revision.identity
        let root = FolderComparisonRoot(
            requestedURL: requestedURL ?? old.requestedURL,
            revision: revision
                ?? makeRootRevision(
                    identity: newIdentity,
                    linkCount: old.revision.linkCount,
                    permissions: old.revision.permissions,
                    ownerID: old.revision.ownerID,
                    groupID: old.revision.groupID,
                    flags: old.revision.flags,
                    modificationTimeSeconds: old.revision.modificationTimeSeconds,
                    modificationTimeNanoseconds: old.revision.modificationTimeNanoseconds,
                    statusChangeTimeSeconds: old.revision.statusChangeTimeSeconds,
                    statusChangeTimeNanoseconds: old.revision.statusChangeTimeNanoseconds,
                    metadataSHA256: old.revision.metadataSHA256
                ),
            authority: FolderComparisonAccessAuthority(
                identity: authorityIdentity ?? old.authority.identity,
                revision: authorityRevision ?? old.authority.revision,
                rootIdentity: authorityRootIdentity ?? newIdentity,
                permissions: permissions ?? old.authority.permissions,
                coverage: coverage ?? old.authority.coverage,
                acquisition: acquisition ?? old.authority.acquisition
            ),
            pathCaseSensitivity: caseSensitivity ?? old.pathCaseSensitivity
        )
        return side == .left
            ? FolderComparisonRootPair(left: root, right: roots.right)
            : FolderComparisonRootPair(left: roots.left, right: root)
    }

    private func replacingRoot(
        _ root: FolderComparisonRoot,
        revision: FolderComparisonRootRevision? = nil,
        caseSensitivity: FolderPathCaseSensitivitySelection
    ) -> FolderComparisonRoot {
        FolderComparisonRoot(
            requestedURL: root.requestedURL,
            revision: revision ?? root.revision,
            authority: root.authority,
            pathCaseSensitivity: caseSensitivity
        )
    }

    private func makeScanIntent(
        recursive: Bool = true,
        maximumEntries: Int = 1_000,
        maximumExaminedEntries: Int = 1,
        maximumRelativePathUTF8Bytes: Int = 1_024,
        filter: FolderComparisonScanFilter? = nil
    ) -> FolderComparisonScanIntent {
        FolderComparisonScanIntent(
            recursive: recursive,
            options: FolderScanOptions(
                limits: FolderScanLimits(
                    maximumDepth: 32,
                    maximumEntries: maximumEntries,
                    maximumIssues: 16,
                    maximumRelativePathUTF8Bytes: maximumRelativePathUTF8Bytes,
                    maximumTotalAccountedBytes: 1_000_000,
                    maximumExaminedEntries: maximumExaminedEntries,
                    maximumOpenDirectoryDescriptors: 16,
                    maximumPendingEntryNames: 1_000
                )
            ),
            filenameFilter: filter
        )
    }

    private func initialTarget() -> FolderComparisonWorkflowSnapshotTarget {
        FolderComparisonWorkflowSnapshotTarget(
            identity: snapshotIdentity,
            generation: 0,
            owner: FolderComparisonWorkflowSnapshotOwner(identity: snapshotOwnerID, revision: 0)
        )
    }

    private func compareRequest(
        roots: FolderComparisonRootPair,
        target: FolderComparisonWorkflowSnapshotTarget,
        scanIntent: FolderComparisonScanIntent? = nil,
        settings: FolderComparisonSettings = FolderComparisonSettings(),
        limits: FolderComparisonWorkflowLimits = .default
    ) -> FolderComparisonCompareRequest {
        FolderComparisonCompareRequest(
            target: target,
            roots: roots,
            scanIntent: scanIntent ?? makeScanIntent(),
            comparisonSettings: settings,
            capabilities: capabilities,
            limits: limits
        )
    }

    private func makeMetadata(
        path: String,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64? = 4,
        seconds: Int64 = 10,
        nanoseconds: Int32 = 0,
        isHidden: Bool = false
    ) -> DirectoryEntryMetadata {
        DirectoryEntryMetadata(
            relativePath: path,
            kind: kind,
            byteCount: byteCount,
            modificationDate: Date(
                timeIntervalSince1970: Double(seconds) + Double(nanoseconds) / 1_000_000_000
            ),
            isHidden: isHidden
        )
    }

    private func makeItemRevision(
        root: FolderComparisonRoot,
        path: String,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64? = 4,
        seconds: Int64 = 10,
        nanoseconds: Int32 = 0,
        contentSeed: UInt8? = 10,
        metadataSHA256: [UInt8]? = nil,
        seed: UInt8
    ) -> FolderComparisonItemRevision {
        FolderComparisonItemRevision(
            identity: FolderComparisonItemIdentity(
                rootIdentity: root.revision.identity,
                relativePath: path,
                deviceID: UInt64(seed) + 100,
                fileID: UInt64(seed) + 1_000,
                generation: UInt32(seed) + 1
            ),
            kind: kind,
            byteCount: byteCount,
            linkCount: 1,
            permissions: 0o644,
            ownerID: 501,
            groupID: 20,
            flags: 0,
            modificationTimeSeconds: seconds,
            modificationTimeNanoseconds: nanoseconds,
            statusChangeTimeSeconds: seconds + 1,
            statusChangeTimeNanoseconds: nanoseconds,
            metadataSHA256: metadataSHA256 ?? digest(seed),
            contentSHA256: contentSeed.map { digest($0) }
        )
    }

    private func replacingItemRevision(
        _ revision: FolderComparisonItemRevision,
        rootIdentity: FolderComparisonRootIdentity? = nil,
        relativePath: String? = nil,
        deviceID: UInt64? = nil,
        fileID: UInt64? = nil,
        generation: UInt32? = nil,
        kind: DirectoryEntryKind? = nil,
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
        metadataSHA256: [UInt8]? = nil,
        contentSHA256: [UInt8]?? = nil
    ) -> FolderComparisonItemRevision {
        FolderComparisonItemRevision(
            identity: FolderComparisonItemIdentity(
                rootIdentity: rootIdentity ?? revision.identity.rootIdentity,
                relativePath: relativePath ?? revision.identity.relativePath,
                deviceID: deviceID ?? revision.identity.deviceID,
                fileID: fileID ?? revision.identity.fileID,
                generation: generation ?? revision.identity.generation
            ),
            kind: kind ?? revision.kind,
            byteCount: byteCount ?? revision.byteCount,
            linkCount: linkCount ?? revision.linkCount,
            permissions: permissions ?? revision.permissions,
            ownerID: ownerID ?? revision.ownerID,
            groupID: groupID ?? revision.groupID,
            flags: flags ?? revision.flags,
            modificationTimeSeconds: modificationTimeSeconds ?? revision.modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds ?? revision.modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds ?? revision.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds ?? revision.statusChangeTimeNanoseconds,
            metadataSHA256: metadataSHA256 ?? revision.metadataSHA256,
            contentSHA256: contentSHA256 ?? revision.contentSHA256
        )
    }

    private struct RowFixture {
        let result: DirectoryResult
        let revision: FolderComparisonResultRevision
    }

    private func makePairedRow(
        path: String,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64? = 4,
        roots: FolderComparisonRootPair,
        seed: UInt8
    ) -> RowFixture {
        makePairedRow(
            leftPath: path,
            rightPath: path,
            status: .identical,
            kind: kind,
            roots: roots,
            leftByteCount: byteCount,
            rightByteCount: byteCount,
            seed: seed
        )
    }

    private func makePairedRow(
        leftPath: String,
        rightPath: String,
        status: DirectoryComparisonStatus,
        kind: DirectoryEntryKind = .file,
        roots: FolderComparisonRootPair,
        leftByteCount: UInt64?,
        rightByteCount: UInt64?,
        seed: UInt8
    ) -> RowFixture {
        let seconds: Int64 = 10
        let left = makeMetadata(
            path: leftPath,
            kind: kind,
            byteCount: leftByteCount,
            seconds: seconds
        )
        let right = makeMetadata(
            path: rightPath,
            kind: kind,
            byteCount: rightByteCount,
            seconds: seconds
        )
        let result = DirectoryResult(left: left, right: right, status: status)
        return RowFixture(
            result: result,
            revision: FolderComparisonResultRevision(
                id: result.id,
                left: makeItemRevision(
                    root: roots.left,
                    path: leftPath,
                    kind: kind,
                    byteCount: leftByteCount,
                    seconds: seconds,
                    contentSeed: seed,
                    seed: seed
                ),
                right: makeItemRevision(
                    root: roots.right,
                    path: rightPath,
                    kind: kind,
                    byteCount: rightByteCount,
                    seconds: seconds,
                    contentSeed: status == .identical ? seed : seed &+ 1,
                    seed: seed &+ 1
                )
            )
        )
    }

    private func makeOneSidedRow(
        path: String,
        side: FolderComparisonWorkflowSide,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64? = 4,
        roots: FolderComparisonRootPair,
        seed: UInt8,
        isHidden: Bool = false
    ) -> RowFixture {
        let metadata = makeMetadata(
            path: path,
            kind: kind,
            byteCount: byteCount,
            seconds: 10,
            isHidden: isHidden
        )
        let result = DirectoryResult(
            left: side == .left ? metadata : nil,
            right: side == .right ? metadata : nil,
            status: side == .left ? .leftOnly : .rightOnly
        )
        let revision = makeItemRevision(
            root: roots[side],
            path: path,
            kind: kind,
            byteCount: byteCount,
            seconds: 10,
            contentSeed: seed,
            seed: seed
        )
        return RowFixture(
            result: result,
            revision: FolderComparisonResultRevision(
                id: result.id,
                left: side == .left ? revision : nil,
                right: side == .right ? revision : nil
            )
        )
    }

    private func makeSortRows(roots: FolderComparisonRootPair) -> [RowFixture] {
        let pairedMetadataLeft = makeMetadata(path: "c.txt", byteCount: 2, seconds: 20)
        let pairedMetadataRight = makeMetadata(path: "c.txt", byteCount: 8, seconds: 40)
        let pairedResult = DirectoryResult(
            left: pairedMetadataLeft,
            right: pairedMetadataRight,
            status: .different
        )
        let pairedRevision = FolderComparisonResultRevision(
            id: pairedResult.id,
            left: makeItemRevision(
                root: roots.left,
                path: "c.txt",
                byteCount: 2,
                seconds: 20,
                contentSeed: 1,
                seed: 40
            ),
            right: makeItemRevision(
                root: roots.right,
                path: "c.txt",
                byteCount: 8,
                seconds: 40,
                contentSeed: 2,
                seed: 41
            )
        )
        let rightOnlyMetadata = makeMetadata(path: "a.txt", byteCount: 4, seconds: 10)
        let rightOnlyResult = DirectoryResult(
            left: nil,
            right: rightOnlyMetadata,
            status: .rightOnly
        )
        let rightOnlyRevision = FolderComparisonResultRevision(
            id: rightOnlyResult.id,
            left: nil,
            right: makeItemRevision(
                root: roots.right,
                path: "a.txt",
                byteCount: 4,
                seconds: 10,
                seed: 42
            )
        )
        let leftOnlyMetadata = makeMetadata(path: "b.txt", byteCount: 6, seconds: 30)
        let leftOnlyResult = DirectoryResult(
            left: leftOnlyMetadata,
            right: nil,
            status: .leftOnly
        )
        let leftOnlyRevision = FolderComparisonResultRevision(
            id: leftOnlyResult.id,
            left: makeItemRevision(
                root: roots.left,
                path: "b.txt",
                byteCount: 6,
                seconds: 30,
                seed: 43
            ),
            right: nil
        )
        return [
            RowFixture(result: pairedResult, revision: pairedRevision),
            RowFixture(result: rightOnlyResult, revision: rightOnlyRevision),
            RowFixture(result: leftOnlyResult, revision: leftOnlyRevision)
        ]
    }

    private func makePairedWorkRows(
        roots: FolderComparisonRootPair,
        count: Int,
        pathBytes: Int
    ) -> [RowFixture] {
        (0..<count).map { index in
            let suffix = String(format: "%04d", count - index)
            let path = String(repeating: "x", count: pathBytes - suffix.utf8.count) + suffix
            return makePairedRow(path: path, roots: roots, seed: UInt8(index * 2))
        }
    }

    private func makeSnapshot(
        identity: FolderComparisonWorkflowSnapshotIdentity? = nil,
        roots: FolderComparisonRootPair,
        rows: [RowFixture],
        generation: UInt64 = 3,
        owner: FolderComparisonWorkflowSnapshotOwner? = nil,
        scanIntent: FolderComparisonScanIntent? = nil,
        settings: FolderComparisonSettings = FolderComparisonSettings(),
        isComplete: Bool = true
    ) -> FolderComparisonWorkflowSnapshot {
        makeSnapshot(
            identity: identity,
            roots: roots,
            results: rows.map(\.result),
            revisions: rows.map(\.revision),
            generation: generation,
            owner: owner,
            scanIntent: scanIntent,
            settings: settings,
            isComplete: isComplete
        )
    }

    private func makeSnapshot(
        identity: FolderComparisonWorkflowSnapshotIdentity? = nil,
        roots: FolderComparisonRootPair,
        results: [DirectoryResult],
        revisions: [FolderComparisonResultRevision],
        generation: UInt64 = 3,
        owner: FolderComparisonWorkflowSnapshotOwner? = nil,
        scanIntent: FolderComparisonScanIntent? = nil,
        settings: FolderComparisonSettings = FolderComparisonSettings(),
        isComplete: Bool = true
    ) -> FolderComparisonWorkflowSnapshot {
        FolderComparisonWorkflowSnapshot(
            identity: identity ?? snapshotIdentity,
            generation: generation,
            owner: owner
                ?? FolderComparisonWorkflowSnapshotOwner(
                    identity: snapshotOwnerID,
                    revision: generation
                ),
            roots: roots,
            scanIntent: scanIntent ?? makeScanIntent(),
            comparisonSettings: settings,
            isComplete: isComplete,
            results: results,
            resultRevisions: revisions
        )
    }

    private func makePostOperationSnapshot(
        from snapshot: FolderComparisonWorkflowSnapshot,
        roots: FolderComparisonRootPair,
        results: [DirectoryResult],
        revisions: [FolderComparisonResultRevision]
    ) -> FolderComparisonWorkflowSnapshot {
        makeSnapshot(
            identity: snapshot.identity,
            roots: roots,
            results: results,
            revisions: revisions,
            generation: snapshot.generation + 1,
            owner: FolderComparisonWorkflowSnapshotOwner(
                identity: snapshot.owner.identity,
                revision: snapshot.owner.revision + 1
            ),
            scanIntent: snapshot.scanIntent,
            settings: snapshot.comparisonSettings
        )
    }

    private func makeLimits(
        maximumResultItems: Int = 2_000,
        maximumSelectedItems: Int = 100,
        maximumOperationActions: Int = 200,
        maximumPresentationRows: Int = 1_000,
        maximumColumns: Int = FolderComparisonPresentationColumn.allCases.count,
        maximumSortDescriptors: Int = 8,
        maximumFilterRules: Int = 100,
        maximumStringUTF8Bytes: Int = 1_024,
        maximumTotalStringUTF8Bytes: Int = 1_000_000,
        maximumMetadataDigestBytes: Int = 1_024,
        maximumWorkUnits: UInt64 = 1_000_000,
        cancellationCheckInterval: Int = 64
    ) -> FolderComparisonWorkflowLimits {
        FolderComparisonWorkflowLimits(
            maximumResultItems: maximumResultItems,
            maximumSelectedItems: maximumSelectedItems,
            maximumOperationActions: maximumOperationActions,
            maximumPresentationRows: maximumPresentationRows,
            maximumColumns: maximumColumns,
            maximumSortDescriptors: maximumSortDescriptors,
            maximumFilterRules: maximumFilterRules,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumMetadataDigestBytes: maximumMetadataDigestBytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func planOperation(
        snapshot: FolderComparisonWorkflowSnapshot,
        selection: FolderComparisonFileOperationSelection,
        replacementOwner: FolderComparisonReplacementOwner? = nil,
        capabilities: FolderComparisonWorkflowCapabilities? = nil,
        limits: FolderComparisonWorkflowLimits = .default
    ) throws -> FolderComparisonFileOperationPlan {
        try FolderComparisonWorkflowPlanner.planFileOperation(
            FolderComparisonFileOperationRequest(
                snapshot: snapshot,
                selection: selection,
                replacementOwner: replacementOwner,
                capabilities: capabilities ?? self.capabilities,
                limits: limits
            )
        )
    }

    private func makeActivity(
        state: FolderComparisonActivityState,
        controls: Set<FolderComparisonActivityControl>,
        revision: UInt64 = 1,
        completedUnits: UInt64 = 1,
        completedItems: Int = 1
    ) -> FolderComparisonActivitySnapshot {
        FolderComparisonActivitySnapshot(
            identity: activityID,
            revision: revision,
            kind: .comparing,
            state: state,
            supportedControls: controls,
            progress: FolderComparisonActivityProgress(
                completedUnits: completedUnits,
                totalUnits: 10,
                completedItems: completedItems,
                totalItems: 10
            )
        )
    }

    private func controlPlan(
        activity: FolderComparisonActivitySnapshot,
        control: FolderComparisonActivityControl
    ) throws -> FolderComparisonActivityControlPlan {
        try FolderComparisonWorkflowPlanner.planActivityControl(
            FolderComparisonActivityControlRequest(
                activity: activity,
                control: control,
                capabilities: capabilities
            )
        )
    }

    private func activitySuccessor(
        for plan: FolderComparisonActivityControlPlan,
        progress: FolderComparisonActivityProgress
    ) -> FolderComparisonActivitySnapshot {
        FolderComparisonActivitySnapshot(
            identity: plan.expectedActivity.identity,
            revision: plan.expectedSuccessorRevision,
            kind: plan.expectedActivity.kind,
            state: plan.expectedSuccessorState,
            supportedControls: plan.expectedSuccessorSupportedControls,
            progress: progress
        )
    }

    private func replacingProgress(
        _ progress: FolderComparisonActivityProgress,
        completedUnits: UInt64? = nil,
        totalUnits: UInt64?? = nil,
        completedItems: Int? = nil,
        totalItems: Int?? = nil
    ) -> FolderComparisonActivityProgress {
        FolderComparisonActivityProgress(
            completedUnits: completedUnits ?? progress.completedUnits,
            totalUnits: totalUnits ?? progress.totalUnits,
            completedItems: completedItems ?? progress.completedItems,
            totalItems: totalItems ?? progress.totalItems,
            currentRelativePath: progress.currentRelativePath
        )
    }

    private func assertCompareError(
        _ expected: FolderComparisonWorkflowError,
        roots: FolderComparisonRootPair,
        target: FolderComparisonWorkflowSnapshotTarget,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertWorkflowError(expected, file: file, line: line) {
            try FolderComparisonWorkflowPlanner.planComparison(
                compareRequest(roots: roots, target: target)
            )
        }
    }

    private func assertPresentationError(
        _ expected: FolderComparisonWorkflowError,
        snapshot: FolderComparisonWorkflowSnapshot,
        configuration: FolderComparisonPresentationConfiguration,
        capabilities: FolderComparisonWorkflowCapabilities? = nil,
        limits: FolderComparisonWorkflowLimits = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertWorkflowError(expected, file: file, line: line) {
            try FolderComparisonWorkflowPlanner.planPresentation(
                FolderComparisonPresentationRequest(
                    snapshot: snapshot,
                    configuration: configuration,
                    capabilities: capabilities ?? self.capabilities,
                    limits: limits
                )
            )
        }
    }

    private func assertOperationError(
        _ expected: FolderComparisonWorkflowError,
        snapshot: FolderComparisonWorkflowSnapshot,
        selection: FolderComparisonFileOperationSelection,
        replacementOwner: FolderComparisonReplacementOwner? = nil,
        capabilities: FolderComparisonWorkflowCapabilities? = nil,
        limits: FolderComparisonWorkflowLimits = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertWorkflowError(expected, file: file, line: line) {
            try planOperation(
                snapshot: snapshot,
                selection: selection,
                replacementOwner: replacementOwner,
                capabilities: capabilities,
                limits: limits
            )
        }
    }

    private func assertActivityError(
        _ expected: FolderComparisonWorkflowError,
        activity: FolderComparisonActivitySnapshot,
        control: FolderComparisonActivityControl,
        capabilities: FolderComparisonWorkflowCapabilities? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertWorkflowError(expected, file: file, line: line) {
            try FolderComparisonWorkflowPlanner.planActivityControl(
                FolderComparisonActivityControlRequest(
                    activity: activity,
                    control: control,
                    capabilities: capabilities ?? self.capabilities
                )
            )
        }
    }

    private func assertWorkflowError<T>(
        _ expected: FolderComparisonWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? FolderComparisonWorkflowError, expected, file: file, line: line)
        }
    }

    private func assertCancelled<Success: Sendable>(task: Task<Success, Error>) async {
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? FolderComparisonWorkflowError, .cancelled)
        }
    }

    private func statusName(_ status: DirectoryComparisonStatus) -> String {
        switch status {
        case .pending: "pending"
        case .identical: "identical"
        case .different: "different"
        case .leftOnly: "leftOnly"
        case .rightOnly: "rightOnly"
        case .typeMismatch: "typeMismatch"
        case .skipped: "skipped"
        case .error: "error"
        }
    }

    private struct CompletedCreateContext {
        let plan: FolderComparisonFileOperationPlan
        let receipt: FolderComparisonFileActionReceipt
        let destinationMetadata: DirectoryEntryMetadata
        let destinationRevision: FolderComparisonItemRevision
        let postRoots: FolderComparisonRootPair
        let postSnapshot: FolderComparisonWorkflowSnapshot
    }

    private func makeCompletedCreateContext(
        snapshot: FolderComparisonWorkflowSnapshot,
        source: RowFixture,
        selection: FolderComparisonFileOperationSelection,
        seed: UInt8
    ) throws -> CompletedCreateContext {
        let plan = try planOperation(snapshot: snapshot, selection: selection)
        let action = try XCTUnwrap(plan.actions.first)
        let sourceRevision = try XCTUnwrap(action.sourceRevision)
        let destinationRoot = snapshot.roots[action.destinationSide]
        let destinationRevision = makeItemRevision(
            root: destinationRoot,
            path: action.destinationRelativePath,
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds,
            contentSeed: sourceRevision.contentSHA256?.first,
            seed: seed
        )
        let destinationMetadata = makeMetadata(
            path: action.destinationRelativePath,
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds
        )
        let destinationRootPost = replacingRootRevision(
            destinationRoot.revision,
            metadataSHA256: digest(seed &+ 1)
        )
        let postRoots = replacingRoot(
            snapshot.roots,
            side: action.destinationSide,
            revision: destinationRootPost
        )
        let receipt = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: actionSHA256(action),
            disposition: .completed,
            destinationPostRevision: destinationRevision,
            sourcePostRevision: sourceRevision,
            sourceRootPostRevision: action.sourceRoot?.preEffectRevision,
            destinationRootPostRevision: destinationRootPost
        )
        let copiedResult = DirectoryResult(
            left: action.sourceSide == .left ? source.result.left : destinationMetadata,
            right: action.sourceSide == .right ? source.result.right : destinationMetadata,
            status: .identical
        )
        let copiedRevision = FolderComparisonResultRevision(
            id: copiedResult.id,
            left: action.sourceSide == .left ? sourceRevision : destinationRevision,
            right: action.sourceSide == .right ? sourceRevision : destinationRevision
        )
        let untouched = snapshot.results.indices.filter { snapshot.results[$0].id != source.result.id }
        let postSnapshot = makePostOperationSnapshot(
            from: snapshot,
            roots: postRoots,
            results: [copiedResult] + untouched.map { snapshot.results[$0] },
            revisions: [copiedRevision] + untouched.map { snapshot.resultRevisions[$0] }
        )
        return CompletedCreateContext(
            plan: plan,
            receipt: receipt,
            destinationMetadata: destinationMetadata,
            destinationRevision: destinationRevision,
            postRoots: postRoots,
            postSnapshot: postSnapshot
        )
    }

    private func completeCreateOperation(
        plan: FolderComparisonFileOperationPlan,
        snapshot: FolderComparisonWorkflowSnapshot,
        seed: UInt8
    ) throws -> FolderComparisonExecutionOutcome {
        let action = try XCTUnwrap(plan.actions.first)
        let sourceRevision = try XCTUnwrap(action.sourceRevision)
        let destinationRevision = makeItemRevision(
            root: snapshot.roots[action.destinationSide],
            path: action.destinationRelativePath,
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds,
            contentSeed: sourceRevision.contentSHA256?.first,
            seed: seed
        )
        let destinationRootPost = replacingRootRevision(
            snapshot.roots[action.destinationSide].revision,
            metadataSHA256: digest(seed &+ 1)
        )
        let receipt = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: actionSHA256(action),
            disposition: .completed,
            destinationPostRevision: destinationRevision,
            sourcePostRevision: sourceRevision,
            sourceRootPostRevision: action.sourceRoot?.preEffectRevision,
            destinationRootPostRevision: destinationRootPost
        )
        let sourceMetadata = try XCTUnwrap(action.source)
        let destinationMetadata = makeMetadata(
            path: action.destinationRelativePath,
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds
        )
        let result = DirectoryResult(
            left: action.sourceSide == .left ? sourceMetadata : destinationMetadata,
            right: action.sourceSide == .right ? sourceMetadata : destinationMetadata,
            status: .identical
        )
        let revision = FolderComparisonResultRevision(
            id: result.id,
            left: action.sourceSide == .left ? sourceRevision : destinationRevision,
            right: action.sourceSide == .right ? sourceRevision : destinationRevision
        )
        let post = makePostOperationSnapshot(
            from: snapshot,
            roots: replacingRoot(
                snapshot.roots,
                side: action.destinationSide,
                revision: destinationRootPost
            ),
            results: [result],
            revisions: [revision]
        )
        return try FolderComparisonExecutionReceiptFactory.completedFileOperation(
            plan: plan,
            actionReceipts: [receipt],
            postEffectSnapshot: post
        )
    }

    private func completeDeleteOperation(
        plan: FolderComparisonFileOperationPlan,
        snapshot: FolderComparisonWorkflowSnapshot,
        owner: FolderComparisonReplacementOwner,
        seed: UInt8
    ) throws -> FolderComparisonExecutionOutcome {
        let action = try XCTUnwrap(plan.actions.first)
        let destinationRootPost = replacingRootRevision(
            snapshot.roots[action.destinationSide].revision,
            metadataSHA256: digest(seed)
        )
        let receipt = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: actionSHA256(action),
            disposition: .completed,
            destinationPostRevision: nil,
            sourcePostRevision: nil,
            sourceRootPostRevision: nil,
            destinationRootPostRevision: destinationRootPost,
            replacementOwnerRevision: owner.revision + 1
        )
        let post = makePostOperationSnapshot(
            from: snapshot,
            roots: replacingRoot(
                snapshot.roots,
                side: action.destinationSide,
                revision: destinationRootPost
            ),
            results: [],
            revisions: []
        )
        return try FolderComparisonExecutionReceiptFactory.completedFileOperation(
            plan: plan,
            actionReceipts: [receipt],
            postEffectSnapshot: post
        )
    }

    private func assertCompletedMoveReceipt() throws {
        let roots = makeRoots()
        let source = makeOneSidedRow(path: "move.txt", side: .left, roots: roots, seed: 10)
        let snapshot = makeSnapshot(roots: roots, rows: [source])
        let plan = try planOperation(
            snapshot: snapshot,
            selection: .move(ids: [source.result.id], from: .left, collision: .fail)
        )
        let action = try XCTUnwrap(plan.actions.first)
        let sourceRevision = try XCTUnwrap(action.sourceRevision)
        let destinationRevision = makeItemRevision(
            root: roots.right,
            path: "move.txt",
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds,
            contentSeed: 10,
            seed: 60
        )
        let leftPost = replacingRootRevision(roots.left.revision, metadataSHA256: digest(61))
        let rightPost = replacingRootRevision(roots.right.revision, metadataSHA256: digest(62))
        let receipt = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: actionSHA256(action),
            disposition: .completed,
            destinationPostRevision: destinationRevision,
            sourcePostRevision: nil,
            sourceRootPostRevision: leftPost,
            destinationRootPostRevision: rightPost
        )
        let metadata = makeMetadata(
            path: "move.txt",
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds
        )
        let result = DirectoryResult(left: nil, right: metadata, status: .rightOnly)
        let revision = FolderComparisonResultRevision(
            id: result.id,
            left: nil,
            right: destinationRevision
        )
        let postRoots = replacingRoot(
            replacingRoot(roots, side: .left, revision: leftPost),
            side: .right,
            revision: rightPost
        )
        let post = makePostOperationSnapshot(
            from: snapshot,
            roots: postRoots,
            results: [result],
            revisions: [revision]
        )
        XCTAssertNoThrow(
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: plan,
                actionReceipts: [receipt],
                postEffectSnapshot: post
            )
        )
    }

    private func assertCompletedDeleteReceipt() throws {
        let roots = makeRoots()
        let target = makeOneSidedRow(path: "delete.txt", side: .left, roots: roots, seed: 20)
        let snapshot = makeSnapshot(roots: roots, rows: [target])
        let owner = FolderComparisonReplacementOwner(identity: replacementOwnerID, revision: 7)
        let plan = try planOperation(
            snapshot: snapshot,
            selection: .delete(ids: [target.result.id], side: .left),
            replacementOwner: owner
        )
        let action = try XCTUnwrap(plan.actions.first)
        let leftPost = replacingRootRevision(roots.left.revision, metadataSHA256: digest(70))
        let receipt = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: actionSHA256(action),
            disposition: .completed,
            destinationPostRevision: nil,
            sourcePostRevision: nil,
            sourceRootPostRevision: nil,
            destinationRootPostRevision: leftPost,
            replacementOwnerRevision: owner.revision + 1
        )
        let post = makePostOperationSnapshot(
            from: snapshot,
            roots: replacingRoot(roots, side: .left, revision: leftPost),
            results: [],
            revisions: []
        )
        XCTAssertNoThrow(
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: plan,
                actionReceipts: [receipt],
                postEffectSnapshot: post
            )
        )
    }

    private func assertCompletedReplaceReceipt() throws {
        let roots = makeRoots()
        let pair = makePairedRow(
            leftPath: "replace.txt",
            rightPath: "replace.txt",
            status: .different,
            roots: roots,
            leftByteCount: 4,
            rightByteCount: 8,
            seed: 30
        )
        let snapshot = makeSnapshot(roots: roots, rows: [pair])
        let owner = FolderComparisonReplacementOwner(identity: replacementOwnerID, revision: 9)
        let plan = try planOperation(
            snapshot: snapshot,
            selection: .copy(
                ids: [pair.result.id],
                from: .left,
                collision: .replaceKeepingBackup
            ),
            replacementOwner: owner
        )
        let action = try XCTUnwrap(plan.actions.first)
        let sourceRevision = try XCTUnwrap(action.sourceRevision)
        let destinationRevision = makeItemRevision(
            root: roots.right,
            path: "replace.txt",
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds,
            contentSeed: 30,
            seed: 80
        )
        let rightPost = replacingRootRevision(roots.right.revision, metadataSHA256: digest(81))
        let receipt = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: actionSHA256(action),
            disposition: .completed,
            destinationPostRevision: destinationRevision,
            sourcePostRevision: sourceRevision,
            sourceRootPostRevision: roots.left.revision,
            destinationRootPostRevision: rightPost,
            replacementOwnerRevision: owner.revision + 1
        )
        let rightMetadata = makeMetadata(
            path: "replace.txt",
            byteCount: sourceRevision.byteCount,
            seconds: sourceRevision.modificationTimeSeconds
        )
        let result = DirectoryResult(left: pair.result.left, right: rightMetadata, status: .identical)
        let revision = FolderComparisonResultRevision(
            id: result.id,
            left: sourceRevision,
            right: destinationRevision
        )
        let post = makePostOperationSnapshot(
            from: snapshot,
            roots: replacingRoot(roots, side: .right, revision: rightPost),
            results: [result],
            revisions: [revision]
        )
        XCTAssertNoThrow(
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: plan,
                actionReceipts: [receipt],
                postEffectSnapshot: post
            )
        )
    }

    private func assertCompletedSkipReceipt() throws {
        let roots = makeRoots()
        let pair = makePairedRow(
            leftPath: "skip.txt",
            rightPath: "skip.txt",
            status: .different,
            roots: roots,
            leftByteCount: 4,
            rightByteCount: 8,
            seed: 40
        )
        let snapshot = makeSnapshot(roots: roots, rows: [pair])
        let plan = try planOperation(
            snapshot: snapshot,
            selection: .copy(ids: [pair.result.id], from: .left, collision: .skip)
        )
        let action = try XCTUnwrap(plan.actions.first)
        let receipt = FolderComparisonFileActionReceipt(
            actionIndex: 0,
            actionSHA256: actionSHA256(action),
            disposition: .skipped,
            destinationPostRevision: pair.revision.right,
            sourcePostRevision: pair.revision.left,
            sourceRootPostRevision: roots.left.revision,
            destinationRootPostRevision: roots.right.revision
        )
        let post = makePostOperationSnapshot(
            from: snapshot,
            roots: roots,
            results: snapshot.results,
            revisions: snapshot.resultRevisions
        )
        XCTAssertNoThrow(
            try FolderComparisonExecutionReceiptFactory.completedFileOperation(
                plan: plan,
                actionReceipts: [receipt],
                postEffectSnapshot: post
            )
        )
    }

    private func actionSHA256(_ action: FolderComparisonPlannedFileAction) -> [UInt8] {
        var encoder = CanonicalEncoder()
        encoder.append(action.resultID)
        encoder.append(action.kind.rawValue)
        encoder.appendOptional(action.sourceSide?.rawValue)
        encoder.append(action.sourceRoot)
        encoder.append(action.source)
        encoder.append(action.sourceRevision)
        encoder.append(action.destinationSide.rawValue)
        encoder.append(action.destinationRoot)
        encoder.append(action.destination)
        encoder.append(action.destinationPrecondition)
        encoder.append(action.destinationRelativePath)
        encoder.appendOptional(action.collision?.rawValue)
        encoder.append(action.replacementOwner)
        return encoder.finalize()
    }

    private struct CanonicalEncoder {
        private var hash = SHA256()

        mutating func append(_ value: Bool) {
            var byte: UInt8 = value ? 1 : 0
            withUnsafeBytes(of: &byte) { hash.update(bufferPointer: $0) }
        }

        mutating func append(_ value: Int) {
            append(Int64(value))
        }

        mutating func append(_ value: UInt32) {
            append(UInt64(value))
        }

        mutating func append(_ value: UInt64) {
            var value = value.bigEndian
            withUnsafeBytes(of: &value) { hash.update(bufferPointer: $0) }
        }

        mutating func append(_ value: Int64) {
            append(UInt64(bitPattern: value))
        }

        mutating func append(_ value: UUID) {
            var value = value.uuid
            withUnsafeBytes(of: &value) { hash.update(bufferPointer: $0) }
        }

        mutating func append(_ value: String) {
            let bytes = Array(value.utf8)
            append(UInt64(bytes.count))
            hash.update(data: Data(bytes))
        }

        mutating func append(_ value: [UInt8]) {
            append(UInt64(value.count))
            hash.update(data: Data(value))
        }

        mutating func appendOptional(_ value: String?) {
            append(value != nil)
            if let value { append(value) }
        }

        mutating func appendOptional(_ value: UInt64?) {
            append(value != nil)
            if let value { append(value) }
        }

        mutating func appendOptional(_ value: Date?) {
            append(value != nil)
            if let value { append(value.timeIntervalSinceReferenceDate.bitPattern) }
        }

        mutating func append(_ id: DirectoryResult.ID) {
            appendOptional(id.leftRelativePath)
            appendOptional(id.rightRelativePath)
        }

        mutating func append(_ identity: FolderComparisonRootIdentity) {
            append(identity.canonicalURL.absoluteString)
            append(identity.deviceID)
            append(identity.fileID)
            append(identity.generation)
        }

        mutating func append(_ revision: FolderComparisonRootRevision) {
            append(revision.identity)
            append(revision.linkCount)
            append(UInt64(revision.permissions))
            append(UInt64(revision.ownerID))
            append(UInt64(revision.groupID))
            append(UInt64(revision.flags))
            append(revision.modificationTimeSeconds)
            append(Int64(revision.modificationTimeNanoseconds))
            append(revision.statusChangeTimeSeconds)
            append(Int64(revision.statusChangeTimeNanoseconds))
            append(revision.metadataSHA256)
        }

        mutating func append(_ revision: FolderComparisonItemRevision) {
            append(revision.identity.rootIdentity)
            append(revision.identity.relativePath)
            append(revision.identity.deviceID)
            append(revision.identity.fileID)
            append(revision.identity.generation)
            append(UInt64(revision.kind.rawValue))
            appendOptional(revision.byteCount)
            append(revision.linkCount)
            append(UInt64(revision.permissions))
            append(UInt64(revision.ownerID))
            append(UInt64(revision.groupID))
            append(UInt64(revision.flags))
            append(revision.modificationTimeSeconds)
            append(Int64(revision.modificationTimeNanoseconds))
            append(revision.statusChangeTimeSeconds)
            append(Int64(revision.statusChangeTimeNanoseconds))
            append(revision.metadataSHA256)
            append(revision.contentSHA256 != nil)
            if let content = revision.contentSHA256 { append(content) }
        }

        mutating func append(_ revision: FolderComparisonItemRevision?) {
            append(revision != nil)
            if let revision { append(revision) }
        }

        mutating func append(_ metadata: DirectoryEntryMetadata?) {
            append(metadata != nil)
            guard let metadata else { return }
            append(metadata.relativePath)
            append(UInt64(metadata.kind.rawValue))
            appendOptional(metadata.byteCount)
            appendOptional(metadata.modificationDate)
            append(metadata.isHidden)
        }

        mutating func append(_ binding: FolderComparisonActionRootBinding) {
            append(binding.identity)
            append(binding.preEffectRevision)
            append(binding.authorityIdentity)
            append(binding.authorityRevision)
        }

        mutating func append(_ binding: FolderComparisonActionRootBinding?) {
            append(binding != nil)
            if let binding { append(binding) }
        }

        mutating func append(_ precondition: FolderComparisonDestinationPrecondition) {
            switch precondition {
            case .existing(let revision):
                append("existing")
                append(revision)
            case .absent(let witness):
                append("absent")
                switch witness.parent {
                case .root(let revision):
                    append("root")
                    append(revision)
                case .directory(let revision):
                    append("directory")
                    append(revision)
                }
                append(witness.relativePath)
                append(witness.normalizedRelativePath)
            }
        }

        mutating func append(_ owner: FolderComparisonReplacementOwner?) {
            append(owner != nil)
            guard let owner else { return }
            append(owner.identity)
            append(owner.revision)
        }

        mutating func finalize() -> [UInt8] {
            Array(hash.finalize())
        }
    }
}
