import Foundation
import XCTest

@testable import MacMergeCore

final class ComparisonOpenExecutorTests: XCTestCase {
    func testScratchpadExecutesWithoutScopeAndValidatesCleanly() throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .scratchpad(text: "left"),
                right: .scratchpad(text: "right")
            )
        )

        let intent = try ComparisonOpenExecutor.execute(
            plan,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )

        XCTAssertEqual(intent.mode, .text)
        XCTAssertTrue(intent.conflictCapable)
        XCTAssertTrue(intent.clipboardSides.isEmpty)
        XCTAssertTrue(intent.materializationRequirements.isEmpty)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(intent, against: plan))
    }

    func testLocalReadsRequireExactReadableScope() throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: file("left.txt"),
                right: file("right.txt"),
                modeSelection: .explicit(.text)
            )
        )

        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(
                plan,
                sandboxScope: ComparisonOpenExecutor.SandboxScope()
            )
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .sandboxScopeMissing)
            XCTAssertFalse(error.localizedDescription.contains("/inputs"))
        }

        let parentOnly = ComparisonOpenExecutor.SandboxScope(
            readableNormalizedPaths: ["/inputs"]
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(plan, sandboxScope: parentOnly)
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .sandboxScopeMissing)
        }

        let intent = try ComparisonOpenExecutor.execute(plan, sandboxScope: scope(for: plan))
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(intent, against: plan))
    }

    func testReadWriteScopesAreNotInterchangeable() throws {
        let destination = URL(filePath: "/projects/a.macmerge")
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: file("left.txt"),
                right: file("right.txt"),
                projectSaveIntent: ComparisonOpenProjectSaveIntent(destinationURL: destination)
            )
        )

        let readOnly = ComparisonOpenExecutor.SandboxScope(
            readableNormalizedPaths: ["/inputs/left.txt", "/inputs/right.txt", "/projects/a.macmerge"]
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(plan, sandboxScope: readOnly)
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .sandboxScopeMissing)
        }

        let swapped = ComparisonOpenExecutor.SandboxScope(
            readableNormalizedPaths: ["/projects/a.macmerge"],
            writableNormalizedPaths: ["/inputs/left.txt", "/inputs/right.txt"]
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(plan, sandboxScope: swapped)
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .sandboxScopeMissing)
        }

        let intent = try ComparisonOpenExecutor.execute(plan, sandboxScope: scope(for: plan))
        XCTAssertEqual(intent.normalizedProjectDestinationPath, "/projects/a.macmerge")
        XCTAssertTrue(intent.hasProjectPayload)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(intent, against: plan))
    }

    func testCoveredPathsLimitCountsReadsAndWrites() throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: .scratchpad(text: "l"), right: .scratchpad(text: "r"))
        )
        let scope = ComparisonOpenExecutor.SandboxScope(
            readableNormalizedPaths: ["/a", "/b"],
            writableNormalizedPaths: ["/c"]
        )

        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(
                plan,
                sandboxScope: scope,
                limits: ComparisonOpenExecutor.Limits(maximumCoveredPaths: 2)
            )
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.tooManyOptionItems(maximum: 2))
            )
        }

        XCTAssertNoThrow(
            try ComparisonOpenExecutor.execute(
                plan,
                sandboxScope: scope,
                limits: ComparisonOpenExecutor.Limits(maximumCoveredPaths: 3)
            )
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(
                plan,
                sandboxScope: ComparisonOpenExecutor.SandboxScope(),
                limits: ComparisonOpenExecutor.Limits(maximumWorkUnits: 0)
            )
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.planningWorkExceeded(maximumWorkUnits: 0))
            )
        }
    }

    func testExpectingIdentityAndCurrentRequestRejectStalePlans() throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: .scratchpad(text: "l"), right: .scratchpad(text: "r"))
        )
        let other = ComparisonOpenRequestIdentity(
            rawValue: UUID(uuid: (9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )

        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(plan, expecting: other, sandboxScope: scope(for: plan))
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.staleRequest(expected: other, actual: plan.requestIdentity))
            )
        }

        let replacement = ComparisonOpenRequest(
            identity: other,
            left: .scratchpad(text: "changed"),
            right: .scratchpad(text: "r")
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(
                plan,
                currentRequest: replacement,
                sandboxScope: scope(for: plan)
            )
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.staleRequest(expected: plan.requestIdentity, actual: other))
            )
        }

        let intent = try ComparisonOpenExecutor.execute(
            plan,
            currentRequest: plan.sourceRequest,
            expecting: plan.requestIdentity,
            sandboxScope: scope(for: plan)
        )
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(intent, against: plan))
    }

    func testSwapReplansWithFreshIdentityAndForwardsFreshnessTokens() throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: file("left.txt"), right: file("right.txt"))
        )
        let intent = try ComparisonOpenExecutor.execute(plan, sandboxScope: scope(for: plan))

        let swapped = try ComparisonOpenExecutor.executeSwapped(
            plan,
            .left,
            .right,
            sandboxScope: ComparisonOpenExecutor.SandboxScope(
                readableNormalizedPaths: ["/inputs/left.txt", "/inputs/right.txt"]
            )
        )
        XCTAssertNotEqual(swapped.requestIdentity, intent.requestIdentity)
        XCTAssertEqual(swapped.sides.map(\.position), [.left, .right])
        XCTAssertEqual(swapped.sides.first { $0.position == .left }?.source, file("right.txt"))
        XCTAssertEqual(swapped.sides.first { $0.position == .right }?.source, file("left.txt"))

        let swappedRequest = try plan.sourceRequest.swapping(.left, .right)
        XCTAssertNotEqual(swappedRequest.identity, plan.requestIdentity)
        let freshPlan = try ComparisonOpenRequestPlanner.plan(swappedRequest)
        XCTAssertEqual(freshPlan.sides.map(\.position), [.left, .right])
        XCTAssertEqual(freshPlan.leftSide?.source, file("right.txt"))
        XCTAssertEqual(freshPlan.rightSide?.source, file("left.txt"))
        XCTAssertThrowsError(try ComparisonOpenExecutor.validate(intent, against: freshPlan)) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.staleRequest(expected: freshPlan.requestIdentity, actual: intent.requestIdentity))
            )
        }
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(swapped, against: freshPlan)
        ) { error in
            guard case .request(.staleRequest) = error as? ComparisonOpenExecutor.Error else {
                return XCTFail("Expected staleRequest for independently swapped plan, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(swapped, against: plan)
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.staleRequest(expected: plan.requestIdentity, actual: swapped.requestIdentity))
            )
        }

        XCTAssertThrowsError(
            try ComparisonOpenExecutor.executeSwapped(
                plan,
                .left,
                .right,
                expecting: plan.requestIdentity,
                sandboxScope: scope(for: plan)
            )
        ) { error in
            guard case .request(.staleRequest) = error as? ComparisonOpenExecutor.Error else {
                return XCTFail("Expected forwarded staleRequest, got \(error)")
            }
        }

        let unrelated = ComparisonOpenRequest(left: .scratchpad(text: "x"), right: .scratchpad(text: "y"))
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.executeSwapped(
                plan,
                .left,
                .right,
                currentRequest: unrelated,
                sandboxScope: scope(for: plan)
            )
        ) { error in
            guard case .request(.staleRequest) = error as? ComparisonOpenExecutor.Error else {
                return XCTFail("Expected forwarded staleRequest, got \(error)")
            }
        }
    }

    func testPerModeRoutingBindsIntentAndReceipt() throws {
        let cases: [(ComparisonProject.Mode, ComparisonOpenRequest, Bool)] = [
            (
                .text,
                ComparisonOpenRequest(
                    left: file("left.txt"),
                    right: file("right.txt"),
                    modeSelection: .explicit(.text),
                    modeOptions: .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions())
                ),
                true
            ),
            (
                .table,
                ComparisonOpenRequest(
                    left: file("left.csv"),
                    right: file("right.csv"),
                    modeSelection: .explicit(.table),
                    modeOptions: .table(parsing: .commaSeparated, twoWay: .default, threeWay: .default)
                ),
                false
            ),
            (
                .binary,
                ComparisonOpenRequest(
                    left: file("left.bin"),
                    right: file("right.bin"),
                    modeSelection: .explicit(.binary),
                    modeOptions: .binary(twoWay: BinaryComparisonOptions(), threeWay: .default)
                ),
                false
            ),
            (
                .image,
                ComparisonOpenRequest(
                    left: file("left.png"),
                    right: file("right.png"),
                    modeSelection: .explicit(.image),
                    modeOptions: .image(loading: .default, comparison: .default)
                ),
                false
            ),
            (
                .webpage,
                ComparisonOpenRequest(
                    left: .remoteWebPage(URL(string: "https://example.test/left")!),
                    right: .remoteWebPage(URL(string: "https://example.test/right")!)
                ),
                false
            ),
            (
                .folder,
                ComparisonOpenRequest(
                    left: folder("left"),
                    right: folder("right"),
                    modeSelection: .explicit(.folder),
                    modeOptions: .folder(
                        scanning: FolderScanOptions(),
                        twoWay: FolderComparisonOptions(),
                        threeWay: .default
                    )
                ),
                false
            )
        ]

        for (mode, request, conflictCapable) in cases {
            let plan = try ComparisonOpenRequestPlanner.plan(request)
            XCTAssertEqual(plan.modeResolution.mode, mode, "\(mode)")
            let intent = try ComparisonOpenExecutor.execute(plan, sandboxScope: scope(for: plan))
            XCTAssertEqual(intent.mode, mode, "\(mode)")
            XCTAssertEqual(intent.receipt.mode, mode, "\(mode)")
            XCTAssertEqual(intent.conflictCapable, conflictCapable, "\(mode)")
            XCTAssertTrue(intent.clipboardSides.isEmpty, "\(mode)")
            XCTAssertNoThrow(try ComparisonOpenExecutor.validate(intent, against: plan), "\(mode)")
        }

        let threeWay = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .scratchpad(text: "l"),
                middle: .scratchpad(text: "b"),
                right: .scratchpad(text: "r"),
                modeSelection: .explicit(.text)
            )
        )
        let threeWayIntent = try ComparisonOpenExecutor.execute(
            threeWay,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        XCTAssertTrue(threeWayIntent.isThreeWay)
    }

    func testModeOptionsMismatchRejectedAtExecute() throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: file("left.txt"),
                right: file("right.txt"),
                modeSelection: .explicit(.text)
            )
        )
        let mismatched = remade(
            plan,
            modeOptions: .table(parsing: .commaSeparated, twoWay: .default, threeWay: .default)
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(mismatched, sandboxScope: scope(for: plan))
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.modeOptionsMismatch(expected: .text, actual: .table))
            )
        }
    }

    func testClipboardEvidenceMatchingStaleAndMixedKinds() throws {
        let left = try ClipboardSnapshot(text: "left", stableID: "left-id")
        let right = try ClipboardSnapshot(text: "right", stableID: "right-id")
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: .clipboard(left), right: .clipboard(right))
        )

        let untouched = try ComparisonOpenExecutor.execute(
            plan,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        XCTAssertEqual(untouched.clipboardSides, [.left, .right])
        XCTAssertTrue(
            untouched.materializationRequirements.contains(.clipboardPairValidation)
        )

        let matching = try ClipboardComparisonInputs(left: left, right: right)
        XCTAssertNoThrow(
            try ComparisonOpenExecutor.execute(
                plan,
                sandboxScope: ComparisonOpenExecutor.SandboxScope(),
                clipboardInputs: matching
            )
        )

        let staleLeft = try ClipboardSnapshot(text: "left", stableID: "other-id")
        let stale = try ClipboardComparisonInputs(left: staleLeft, right: right)
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(
                plan,
                sandboxScope: ComparisonOpenExecutor.SandboxScope(),
                clipboardInputs: stale
            )
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .staleClipboardEvidence)
        }

        let binaryLeft = try ClipboardSnapshot(data: Data([0x01]), stableID: "left-id")
        let binaryRight = try ClipboardSnapshot(data: Data([0x02]), stableID: "right-id")
        let mixed = try ClipboardComparisonInputs(left: binaryLeft, right: binaryRight)
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(
                plan,
                sandboxScope: ComparisonOpenExecutor.SandboxScope(),
                clipboardInputs: mixed
            )
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.invalidClipboard(.mixedContentKinds))
            )
        }
    }

    func testReceiptDigestCoversEveryIntentField() throws {
        let request = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.text),
            modeOptions: .text(
                twoWay: LineDiffOptions(ignoreCase: true),
                threeWay: ThreeWayTextMergeOptions()
            ),
            transforms: ComparisonOpenTransforms(
                unpacker: .init(ruleIdentifier: "archive-v1"),
                prediffer: .init(ruleIdentifier: "normalize-v1")
            )
        )
        let plan = try ComparisonOpenRequestPlanner.plan(request)
        let intent = try ComparisonOpenExecutor.execute(plan, sandboxScope: scope(for: plan))
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(intent, against: plan))

        let projectRequest = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.text),
            projectSaveIntent: ComparisonOpenProjectSaveIntent(
                destinationURL: URL(filePath: "/projects/a.macmerge"),
                existingFilePolicy: .createNew
            )
        )
        let projectPlan = try ComparisonOpenRequestPlanner.plan(projectRequest)
        let projectIntent = try ComparisonOpenExecutor.execute(
            projectPlan,
            sandboxScope: scope(for: projectPlan)
        )
        let replacedPolicy = ComparisonOpenProjectSaveIntent(
            destinationURL: URL(filePath: "/projects/a.macmerge"),
            existingFilePolicy: .replaceExisting
        )
        var renamedLeft = plan.sides
        renamedLeft[0] = ComparisonOpenPlannedSide(
            position: renamedLeft[0].position,
            source: file("other.txt"),
            normalizedPath: renamedLeft[0].normalizedPath,
            effectiveReadOnly: renamedLeft[0].effectiveReadOnly
        )
        var relocatedLeft = plan.sides
        relocatedLeft[0] = ComparisonOpenPlannedSide(
            position: relocatedLeft[0].position,
            source: relocatedLeft[0].source,
            normalizedPath: "/inputs/relocated.txt",
            effectiveReadOnly: relocatedLeft[0].effectiveReadOnly
        )
        var lockedLeft = plan.sides
        lockedLeft[0] = ComparisonOpenPlannedSide(
            position: lockedLeft[0].position,
            source: lockedLeft[0].source,
            normalizedPath: lockedLeft[0].normalizedPath,
            effectiveReadOnly: !lockedLeft[0].effectiveReadOnly
        )
        let mutants: [(String, ComparisonOpenPlan)] = [
            ("mode", remade(plan, mode: .binary)),
            (
                "modeOptions",
                remade(
                    plan,
                    modeOptions: .text(
                        twoWay: LineDiffOptions(ignoreCase: false),
                        threeWay: ThreeWayTextMergeOptions()
                    )
                )
            ),
            ("sideSource", remade(plan, sides: renamedLeft)),
            ("normalizedPath", remade(plan, sides: relocatedLeft)),
            ("effectiveReadOnly", remade(plan, sides: lockedLeft)),
            (
                "threeWay",
                remade(
                    plan,
                    sides: plan.sides + [
                        ComparisonOpenPlannedSide(
                            position: .middle,
                            source: file("base.txt"),
                            normalizedPath: "/inputs/base.txt",
                            effectiveReadOnly: false
                        )
                    ]
                )
            ),
            ("recursive", remade(plan, recursive: !plan.recursive)),
            (
                "unpacker",
                remade(
                    plan,
                    transforms: ComparisonOpenTransforms(
                        unpacker: .init(ruleIdentifier: "archive-v2"),
                        prediffer: .init(ruleIdentifier: "normalize-v1")
                    )
                )
            ),
            (
                "predifferRemoved",
                remade(
                    plan,
                    transforms: ComparisonOpenTransforms(
                        unpacker: .init(ruleIdentifier: "archive-v1")
                    )
                )
            ),
            (
                "materializationRequirements",
                remade(plan, requirements: Array(plan.materializationRequirements.dropLast()))
            ),
            ("unsupportedFeatures", remade(plan, unsupported: [.remoteWebPageLoading]))
        ]
        for (name, mutant) in mutants {
            XCTAssertThrowsError(
                try ComparisonOpenExecutor.validate(intent, against: mutant),
                name
            ) { error in
                XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch, name)
            }
        }
        for (name, mutant) in [
            ("projectSaveIntent", remade(projectPlan, saveIntent: .some(.some(replacedPolicy)))),
            (
                "projectDestinationPath",
                remade(projectPlan, destinationPath: .some(.some("/projects/b.macmerge")))
            ),
            (
                "projectPayload",
                remade(projectPlan, payload: .some(.some(.macMerge(Data([0x00])))))
            )
        ] {
            XCTAssertThrowsError(
                try ComparisonOpenExecutor.validate(projectIntent, against: mutant),
                name
            ) { error in
                XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch, name)
            }
        }

        let relabeled = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .scratchpad(text: "l", label: "L"),
                right: .scratchpad(text: "r")
            )
        )
        let relabeledIntent = try ComparisonOpenExecutor.execute(
            relabeled,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        var unlabeledSides = relabeled.sides
        unlabeledSides[0] = ComparisonOpenPlannedSide(
            position: unlabeledSides[0].position,
            source: .scratchpad(text: "l"),
            effectiveReadOnly: unlabeledSides[0].effectiveReadOnly
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(
                relabeledIntent,
                against: remade(relabeled, sides: unlabeledSides)
            )
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }

        let webpage = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .remoteWebPage(URL(string: "https://example.test/left")!),
                right: .remoteWebPage(URL(string: "https://example.test/right")!)
            )
        )
        let webpageIntent = try ComparisonOpenExecutor.execute(
            webpage,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        var movedWebpageSides = webpage.sides
        movedWebpageSides[0] = ComparisonOpenPlannedSide(
            position: movedWebpageSides[0].position,
            source: .remoteWebPage(URL(string: "https://example.test/moved")!),
            effectiveReadOnly: movedWebpageSides[0].effectiveReadOnly
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(
                webpageIntent,
                against: remade(webpage, sides: movedWebpageSides)
            )
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }

        let clipboardLeft = try ClipboardSnapshot(text: "left", stableID: "left-id")
        let clipboardRight = try ClipboardSnapshot(text: "right", stableID: "right-id")
        let clipboard = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .clipboard(clipboardLeft),
                right: .clipboard(clipboardRight)
            )
        )
        let clipboardIntent = try ComparisonOpenExecutor.execute(
            clipboard,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        var restabledSides = clipboard.sides
        restabledSides[0] = ComparisonOpenPlannedSide(
            position: restabledSides[0].position,
            source: .clipboard(try ClipboardSnapshot(text: "left", stableID: "changed-id")),
            effectiveReadOnly: restabledSides[0].effectiveReadOnly
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(
                clipboardIntent,
                against: remade(clipboard, sides: restabledSides)
            )
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }

        let folderFilter = ComparisonOpenFilenameFilter(
            rules: [.init(.exclude, pattern: .glob("*.tmp"))]
        )
        let folder = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: folder("left"),
                right: folder("right"),
                recursive: true,
                filenameFilter: folderFilter
            )
        )
        let folderIntent = try ComparisonOpenExecutor.execute(
            folder,
            sandboxScope: scope(for: folder)
        )
        for (name, mutant) in [
            ("folderRecursive", remade(folder, recursive: false)),
            (
                "filenameFilter",
                remade(
                    folder,
                    filter: .some(
                        .some(
                            ComparisonOpenFilenameFilter(
                                rules: [.init(.exclude, pattern: .glob("*.bak"))],
                                defaultDecision: .exclude
                            )
                        ))
                )
            )
        ] {
            XCTAssertThrowsError(
                try ComparisonOpenExecutor.validate(folderIntent, against: mutant),
                name
            ) { error in
                XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch, name)
            }
        }

        let rotatedIdentity = ComparisonOpenRequestIdentity()
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(
                intent,
                against: remade(plan, identity: rotatedIdentity)
            )
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.staleRequest(expected: rotatedIdentity, actual: intent.requestIdentity))
            )
        }
    }

    func testSideOrderIsIndependent() throws {
        let shared = ComparisonOpenRequestIdentity()
        let leftSide = ComparisonOpenSide(
            position: .left,
            source: file("left.txt")
        )
        let rightSide = ComparisonOpenSide(
            position: .right,
            source: file("right.txt")
        )
        let forward = ComparisonOpenRequest(
            identity: shared,
            sides: [leftSide, rightSide],
            modeSelection: .explicit(.text)
        )
        let reversed = ComparisonOpenRequest(
            identity: shared,
            sides: [rightSide, leftSide],
            modeSelection: .explicit(.text)
        )

        let forwardPlan = try ComparisonOpenRequestPlanner.plan(forward)
        let reversedPlan = try ComparisonOpenRequestPlanner.plan(reversed)
        XCTAssertEqual(forwardPlan.sides, reversedPlan.sides)
        XCTAssertEqual(forwardPlan.materializationRequirements, reversedPlan.materializationRequirements)

        let forwardIntent = try ComparisonOpenExecutor.execute(
            forwardPlan,
            sandboxScope: scope(for: forwardPlan)
        )
        let reversedIntent = try ComparisonOpenExecutor.execute(
            reversedPlan,
            sandboxScope: scope(for: reversedPlan)
        )
        XCTAssertEqual(forwardIntent.receipt, reversedIntent.receipt)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(forwardIntent, against: reversedPlan))
    }

    func testCancellationAbortsExecute() async throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: .scratchpad(text: "l"), right: .scratchpad(text: "r"))
        )
        let error = await Task<ComparisonOpenExecutor.Error?, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ComparisonOpenExecutor.execute(
                    plan,
                    sandboxScope: ComparisonOpenExecutor.SandboxScope()
                )
                return nil
            } catch let executorError as ComparisonOpenExecutor.Error {
                return executorError
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(error, .request(.cancelled))
    }

    func testWorkLimitExactBoundary() throws {
        let scratch = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: .scratchpad(text: "l"), right: .scratchpad(text: "r"))
        )
        XCTAssertNoThrow(
            try ComparisonOpenExecutor.execute(
                scratch,
                sandboxScope: ComparisonOpenExecutor.SandboxScope(),
                limits: ComparisonOpenExecutor.Limits(maximumWorkUnits: 5)
            )
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(
                scratch,
                sandboxScope: ComparisonOpenExecutor.SandboxScope(),
                limits: ComparisonOpenExecutor.Limits(maximumWorkUnits: 4)
            )
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.planningWorkExceeded(maximumWorkUnits: 4))
            )
        }
        let files = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: file("left.txt"), right: file("right.txt"))
        )
        XCTAssertNoThrow(
            try ComparisonOpenExecutor.execute(
                files,
                sandboxScope: scope(for: files),
                limits: ComparisonOpenExecutor.Limits(maximumWorkUnits: 11)
            )
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.execute(
                files,
                sandboxScope: scope(for: files),
                limits: ComparisonOpenExecutor.Limits(maximumWorkUnits: 10)
            )
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.planningWorkExceeded(maximumWorkUnits: 10))
            )
        }
    }

    func testSwapSamePositionRotatesIdentity() throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: file("left.txt"), right: file("right.txt"))
        )
        let swapped = try ComparisonOpenExecutor.executeSwapped(
            plan,
            .left,
            .left,
            sandboxScope: scope(for: plan)
        )
        XCTAssertNotEqual(swapped.requestIdentity, plan.requestIdentity)
        XCTAssertEqual(swapped.sides.map(\.position), [.left, .right])
        XCTAssertEqual(swapped.sides.first { $0.position == .left }?.source, file("left.txt"))
        XCTAssertEqual(swapped.sides.first { $0.position == .right }?.source, file("right.txt"))
        XCTAssertThrowsError(try ComparisonOpenExecutor.validate(swapped, against: plan)) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.staleRequest(expected: plan.requestIdentity, actual: swapped.requestIdentity))
            )
        }
    }

    func testSwapMissingSideThrows() throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: file("left.txt"), right: file("right.txt"))
        )
        XCTAssertThrowsError(try plan.sourceRequest.swapping(.left, .middle)) { error in
            XCTAssertEqual(error as? ComparisonOpenRequestError, .missingSide(.middle))
        }
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.executeSwapped(
                plan,
                .left,
                .middle,
                sandboxScope: scope(for: plan)
            )
        ) { error in
            XCTAssertEqual(
                error as? ComparisonOpenExecutor.Error,
                .request(.missingSide(.middle))
            )
        }
    }

    func testSwapForwardsClipboardInputs() throws {
        let left = try ClipboardSnapshot(text: "left", stableID: "left-id")
        let right = try ClipboardSnapshot(text: "right", stableID: "right-id")
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: .clipboard(left), right: .clipboard(right))
        )
        let matching = try ClipboardComparisonInputs(left: left, right: right)
        let swapped = try ComparisonOpenExecutor.executeSwapped(
            plan,
            .left,
            .left,
            sandboxScope: ComparisonOpenExecutor.SandboxScope(),
            clipboardInputs: matching
        )
        XCTAssertNotEqual(swapped.requestIdentity, plan.requestIdentity)
        let staleLeft = try ClipboardSnapshot(text: "left", stableID: "other-id")
        let stale = try ClipboardComparisonInputs(left: staleLeft, right: right)
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.executeSwapped(
                plan,
                .left,
                .left,
                sandboxScope: ComparisonOpenExecutor.SandboxScope(),
                clipboardInputs: stale
            )
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .staleClipboardEvidence)
        }
    }

    func testThreeWayPerModePlans() throws {
        let text = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .scratchpad(text: "l"),
                middle: .scratchpad(text: "m"),
                right: .scratchpad(text: "r"),
                modeSelection: .explicit(.text),
                modeOptions: .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions())
            )
        )
        let textIntent = try ComparisonOpenExecutor.execute(
            text,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        XCTAssertEqual(textIntent.mode, .text)
        XCTAssertTrue(textIntent.isThreeWay)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(textIntent, against: text))
        let table = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: file("left.csv"),
                middle: file("middle.csv"),
                right: file("right.csv"),
                modeSelection: .explicit(.table),
                modeOptions: .table(parsing: .commaSeparated, twoWay: .default, threeWay: .default)
            )
        )
        let tableIntent = try ComparisonOpenExecutor.execute(table, sandboxScope: scope(for: table))
        XCTAssertEqual(tableIntent.mode, .table)
        XCTAssertTrue(tableIntent.isThreeWay)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(tableIntent, against: table))
        let binary = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: file("left.bin"),
                middle: file("middle.bin"),
                right: file("right.bin"),
                modeSelection: .explicit(.binary),
                modeOptions: .binary(twoWay: BinaryComparisonOptions(), threeWay: .default)
            )
        )
        let binaryIntent = try ComparisonOpenExecutor.execute(binary, sandboxScope: scope(for: binary))
        XCTAssertEqual(binaryIntent.mode, .binary)
        XCTAssertTrue(binaryIntent.isThreeWay)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(binaryIntent, against: binary))
        let image = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: file("left.png"),
                middle: file("middle.png"),
                right: file("right.png"),
                modeSelection: .explicit(.image),
                modeOptions: .image(loading: .default, comparison: .default)
            )
        )
        let imageIntent = try ComparisonOpenExecutor.execute(image, sandboxScope: scope(for: image))
        XCTAssertEqual(imageIntent.mode, .image)
        XCTAssertTrue(imageIntent.isThreeWay)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(imageIntent, against: image))
        let folder = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: folder("left"),
                middle: folder("middle"),
                right: folder("right"),
                modeSelection: .explicit(.folder),
                modeOptions: .folder(
                    scanning: FolderScanOptions(),
                    twoWay: FolderComparisonOptions(),
                    threeWay: .default
                )
            )
        )
        let folderIntent = try ComparisonOpenExecutor.execute(folder, sandboxScope: scope(for: folder))
        XCTAssertEqual(folderIntent.mode, .folder)
        XCTAssertTrue(folderIntent.isThreeWay)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(folderIntent, against: folder))
        let webpage = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .remoteWebPage(URL(string: "https://example.test/left")!),
                middle: .remoteWebPage(URL(string: "https://example.test/middle")!),
                right: .remoteWebPage(URL(string: "https://example.test/right")!),
                modeSelection: .explicit(.webpage),
                modeOptions: .webpage(twoWay: .default, threeWay: .default)
            )
        )
        let webpageIntent = try ComparisonOpenExecutor.execute(
            webpage,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        XCTAssertEqual(webpageIntent.mode, .webpage)
        XCTAssertTrue(webpageIntent.isThreeWay)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(webpageIntent, against: webpage))
        let cLeft = try ClipboardSnapshot(text: "l", stableID: "l-id")
        let cMiddle = try ClipboardSnapshot(text: "m", stableID: "m-id")
        let cRight = try ClipboardSnapshot(text: "r", stableID: "r-id")
        XCTAssertThrowsError(
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(left: .clipboard(cLeft), middle: .clipboard(cMiddle), right: .clipboard(cRight))
            )
        ) { error in
            guard case .incompatibleSource(_, _, let reason) = error as? ComparisonOpenRequestError else {
                return XCTFail("expected incompatibleSource, got \(error)")
            }
            XCTAssertEqual(reason, .clipboardRequiresTwoSnapshots)
        }
    }

    func testMixedClipboardAndFileRejected() throws {
        let snap = try ClipboardSnapshot(text: "left", stableID: "left-id")
        XCTAssertThrowsError(
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(left: .clipboard(snap), right: file("right.txt"))
            )
        ) { error in
            guard case .incompatibleSource(_, _, let reason) = error as? ComparisonOpenRequestError else {
                return XCTFail("expected incompatibleSource, got \(error)")
            }
            XCTAssertEqual(reason, .clipboardRequiresTwoSnapshots)
        }
    }

    func testPerFamilyOptionMutantsInvalidateReceipt() throws {
        let tablePlan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: file("left.csv"),
                right: file("right.csv"),
                modeSelection: .explicit(.table),
                modeOptions: .table(parsing: .commaSeparated, twoWay: .default, threeWay: .default)
            )
        )
        let tableIntent = try ComparisonOpenExecutor.execute(tablePlan, sandboxScope: scope(for: tablePlan))
        let tableMutant = remade(
            tablePlan,
            modeOptions: .table(parsing: .tabSeparated, twoWay: .default, threeWay: .default)
        )
        XCTAssertThrowsError(try ComparisonOpenExecutor.validate(tableIntent, against: tableMutant)) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
        let binaryPlan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: file("left.bin"),
                right: file("right.bin"),
                modeSelection: .explicit(.binary),
                modeOptions: .binary(twoWay: BinaryComparisonOptions(), threeWay: .default)
            )
        )
        let binaryIntent = try ComparisonOpenExecutor.execute(binaryPlan, sandboxScope: scope(for: binaryPlan))
        let binaryMutant = remade(
            binaryPlan,
            modeOptions: .binary(
                twoWay: BinaryComparisonOptions(maximumExactEditDistance: 1),
                threeWay: .default
            )
        )
        XCTAssertThrowsError(try ComparisonOpenExecutor.validate(binaryIntent, against: binaryMutant)) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
        let binaryThreeMutant = remade(
            binaryPlan,
            modeOptions: .binary(
                twoWay: BinaryComparisonOptions(),
                threeWay: ThreeWayBinaryComparisonOptions(maximumOutputBytes: 1)
            )
        )
        XCTAssertThrowsError(try ComparisonOpenExecutor.validate(binaryIntent, against: binaryThreeMutant)) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
        let imagePlan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: file("left.png"),
                right: file("right.png"),
                modeSelection: .explicit(.image),
                modeOptions: .image(loading: .default, comparison: .default)
            )
        )
        let imageIntent = try ComparisonOpenExecutor.execute(imagePlan, sandboxScope: scope(for: imagePlan))
        let imageMutant = remade(
            imagePlan,
            modeOptions: .image(loading: .default, comparison: ImageComparisonOptions(channelTolerance: 1))
        )
        XCTAssertThrowsError(try ComparisonOpenExecutor.validate(imageIntent, against: imageMutant)) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
        let folderPlan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: folder("left"),
                right: folder("right"),
                modeSelection: .explicit(.folder),
                modeOptions: .folder(
                    scanning: FolderScanOptions(),
                    twoWay: FolderComparisonOptions(),
                    threeWay: .default
                )
            )
        )
        let folderIntent = try ComparisonOpenExecutor.execute(folderPlan, sandboxScope: scope(for: folderPlan))
        let folderMutant = remade(
            folderPlan,
            modeOptions: .folder(
                scanning: FolderScanOptions(hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets),
                twoWay: FolderComparisonOptions(),
                threeWay: .default
            )
        )
        XCTAssertThrowsError(try ComparisonOpenExecutor.validate(folderIntent, against: folderMutant)) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
        let webpagePlan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .remoteWebPage(URL(string: "https://example.test/left")!),
                right: .remoteWebPage(URL(string: "https://example.test/right")!),
                modeSelection: .explicit(.webpage),
                modeOptions: .webpage(twoWay: .default, threeWay: .default)
            )
        )
        let webpageIntent = try ComparisonOpenExecutor.execute(
            webpagePlan,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        let webpageMutant = remade(
            webpagePlan,
            modeOptions: .webpage(
                twoWay: WebPageComparisonOptions(mode: .renderedText),
                threeWay: .default
            )
        )
        XCTAssertThrowsError(try ComparisonOpenExecutor.validate(webpageIntent, against: webpageMutant)) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
        let threePlan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .scratchpad(text: "l"),
                middle: .scratchpad(text: "m"),
                right: .scratchpad(text: "r"),
                modeSelection: .explicit(.text),
                modeOptions: .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions())
            )
        )
        let threeIntent = try ComparisonOpenExecutor.execute(
            threePlan,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        let threeMutant = remade(
            threePlan,
            modeOptions: .text(
                twoWay: LineDiffOptions(),
                threeWay: ThreeWayTextMergeOptions(maximumRegions: 1)
            )
        )
        XCTAssertThrowsError(try ComparisonOpenExecutor.validate(threeIntent, against: threeMutant)) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
    }

    func testProjectPayloadFormatSwapInvalidatesReceipt() throws {
        let request = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.text),
            projectSaveIntent: ComparisonOpenProjectSaveIntent(
                destinationURL: URL(filePath: "/projects/a.macmerge")
            )
        )
        let base = try ComparisonOpenRequestPlanner.plan(request)
        let intent = try ComparisonOpenExecutor.execute(base, sandboxScope: scope(for: base))
        guard let payload = base.projectPayload else {
            return XCTFail("missing project payload")
        }
        let swapped: ComparisonOpenProjectPayload
        if case .macMerge(let data) = payload {
            swapped = .winMerge(data)
        } else if case .winMerge(let data) = payload {
            swapped = .macMerge(data)
        } else {
            return XCTFail("unknown payload case")
        }
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(intent, against: remade(base, payload: .some(.some(swapped))))
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
    }

    func testScratchpadTextChangeInvalidatesReceipt() throws {
        let base = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: .scratchpad(text: "l"), right: .scratchpad(text: "r"))
        )
        let intent = try ComparisonOpenExecutor.execute(
            base,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        var sides = base.sides
        sides[0] = ComparisonOpenPlannedSide(
            position: sides[0].position,
            source: .scratchpad(text: "changed"),
            normalizedPath: sides[0].normalizedPath,
            effectiveReadOnly: sides[0].effectiveReadOnly
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(intent, against: remade(base, sides: sides))
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
    }

    func testFilenameFilterSubfieldsInvalidateReceipt() throws {
        let baseFilter = ComparisonOpenFilenameFilter(
            rules: [.init(.exclude, pattern: .glob("*.tmp"))]
        )
        let base = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: folder("left"),
                right: folder("right"),
                recursive: true,
                filenameFilter: baseFilter
            )
        )
        let intent = try ComparisonOpenExecutor.execute(base, sandboxScope: scope(for: base))
        let semanticsMutant = ComparisonOpenFilenameFilter(
            rules: [.init(.exclude, pattern: .glob("*.tmp"))],
            matchSemantics: .firstMatchWins
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(intent, against: remade(base, filter: .some(.some(semanticsMutant))))
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
        let caseMutant = ComparisonOpenFilenameFilter(
            rules: [.init(.exclude, pattern: .glob("*.tmp"))],
            casePolicy: .insensitive
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(intent, against: remade(base, filter: .some(.some(caseMutant))))
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
        let limitsMutant = ComparisonOpenFilenameFilter(
            rules: [.init(.exclude, pattern: .glob("*.tmp"))],
            limits: FilenameFilterLimits(maximumRuleCount: 1)
        )
        XCTAssertThrowsError(
            try ComparisonOpenExecutor.validate(intent, against: remade(base, filter: .some(.some(limitsMutant))))
        ) { error in
            XCTAssertEqual(error as? ComparisonOpenExecutor.Error, .receiptMismatch)
        }
    }

    func testThreeWaySideOrderIndependent() throws {
        let shared = ComparisonOpenRequestIdentity()
        let leftSide = ComparisonOpenSide(position: .left, source: file("left.txt"))
        let middleSide = ComparisonOpenSide(position: .middle, source: file("middle.txt"))
        let rightSide = ComparisonOpenSide(position: .right, source: file("right.txt"))
        let forward = ComparisonOpenRequest(
            identity: shared,
            sides: [leftSide, middleSide, rightSide],
            modeSelection: .explicit(.text)
        )
        let shuffled = ComparisonOpenRequest(
            identity: shared,
            sides: [rightSide, leftSide, middleSide],
            modeSelection: .explicit(.text)
        )
        let forwardPlan = try ComparisonOpenRequestPlanner.plan(forward)
        let shuffledPlan = try ComparisonOpenRequestPlanner.plan(shuffled)
        XCTAssertEqual(forwardPlan.sides, shuffledPlan.sides)
        XCTAssertEqual(forwardPlan.materializationRequirements, shuffledPlan.materializationRequirements)
        let forwardIntent = try ComparisonOpenExecutor.execute(
            forwardPlan,
            sandboxScope: scope(for: forwardPlan)
        )
        let shuffledIntent = try ComparisonOpenExecutor.execute(
            shuffledPlan,
            sandboxScope: scope(for: shuffledPlan)
        )
        XCTAssertEqual(forwardIntent.receipt, shuffledIntent.receipt)
        XCTAssertNoThrow(try ComparisonOpenExecutor.validate(forwardIntent, against: shuffledPlan))
    }

    func testCancellationAbortsValidateAndExecuteSwapped() async throws {
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: .scratchpad(text: "l"), right: .scratchpad(text: "r"))
        )
        let intent = try ComparisonOpenExecutor.execute(
            plan,
            sandboxScope: ComparisonOpenExecutor.SandboxScope()
        )
        let validateError = await Task<ComparisonOpenExecutor.Error?, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try ComparisonOpenExecutor.validate(intent, against: plan)
                return nil
            } catch let executorError as ComparisonOpenExecutor.Error {
                return executorError
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(validateError, .request(.cancelled))
        let swappedError = await Task<ComparisonOpenExecutor.Error?, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ComparisonOpenExecutor.executeSwapped(
                    plan,
                    .left,
                    .right,
                    sandboxScope: ComparisonOpenExecutor.SandboxScope()
                )
                return nil
            } catch let executorError as ComparisonOpenExecutor.Error {
                return executorError
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(swappedError, .request(.cancelled))
    }

    func testSameStableIDDifferentTextAccepted() throws {
        let left = try ClipboardSnapshot(text: "left", stableID: "left-id")
        let right = try ClipboardSnapshot(text: "right", stableID: "right-id")
        let plan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(left: .clipboard(left), right: .clipboard(right))
        )
        let changedLeft = try ClipboardSnapshot(text: "changed", stableID: "left-id")
        XCTAssertNotEqual(left.contentID, changedLeft.contentID)
        let inputs = try ClipboardComparisonInputs(left: changedLeft, right: right)
        XCTAssertNoThrow(
            try ComparisonOpenExecutor.execute(
                plan,
                sandboxScope: ComparisonOpenExecutor.SandboxScope(),
                clipboardInputs: inputs
            )
        )
    }

    private func file(_ name: String) -> ComparisonOpenSource {
        .localFile(URL(filePath: "/inputs/\(name)"))
    }

    private func folder(_ name: String) -> ComparisonOpenSource {
        .localFolder(URL(filePath: "/inputs/\(name)", directoryHint: .isDirectory))
    }

    private func scope(for plan: ComparisonOpenPlan) -> ComparisonOpenExecutor.SandboxScope {
        var readable = Set<String>()
        var writable = Set<String>()
        for requirement in plan.materializationRequirements {
            guard case .localAccess(let access) = requirement else { continue }
            switch access.purpose {
            case .readRegularFile, .readDirectoryTree:
                readable.insert(access.normalizedPath)
            case .writeProjectFile:
                writable.insert(access.normalizedPath)
            }
        }
        if let destination = plan.normalizedProjectDestinationPath {
            writable.insert(destination)
        }
        return ComparisonOpenExecutor.SandboxScope(
            readableNormalizedPaths: readable,
            writableNormalizedPaths: writable
        )
    }

    /// Rebuilds a plan with isolated field overrides. Double-optionals mean
    /// nil keeps the base value, `.some(nil)` clears it, `.some(.some(v))` sets it.
    private func remade(
        _ base: ComparisonOpenPlan,
        identity: ComparisonOpenRequestIdentity? = nil,
        sides: [ComparisonOpenPlannedSide]? = nil,
        mode: ComparisonProject.Mode? = nil,
        modeOptions: ComparisonOpenModeOptions? = nil,
        recursive: Bool? = nil,
        filter: ComparisonOpenFilenameFilter?? = nil,
        transforms: ComparisonOpenTransforms? = nil,
        saveIntent: ComparisonOpenProjectSaveIntent?? = nil,
        destinationPath: String?? = nil,
        payload: ComparisonOpenProjectPayload?? = nil,
        requirements: [ComparisonOpenMaterializationRequirement]? = nil,
        unsupported: [ComparisonOpenUnsupportedFeature]? = nil
    ) -> ComparisonOpenPlan {
        ComparisonOpenPlan(
            requestIdentity: identity ?? base.requestIdentity,
            sourceRequest: base.sourceRequest,
            sides: sides ?? base.sides,
            modeResolution: mode.map {
                ComparisonOpenModeResolution(mode: $0, basis: base.modeResolution.basis)
            } ?? base.modeResolution,
            modeOptions: modeOptions ?? base.modeOptions,
            recursive: recursive ?? base.recursive,
            filenameFilter: filter ?? base.filenameFilter,
            transforms: transforms ?? base.transforms,
            projectSaveIntent: saveIntent ?? base.projectSaveIntent,
            normalizedProjectDestinationPath: destinationPath ?? base.normalizedProjectDestinationPath,
            projectPayload: payload ?? base.projectPayload,
            materializationRequirements: requirements ?? base.materializationRequirements,
            unsupportedFeatures: unsupported ?? base.unsupportedFeatures
        )
    }
}
