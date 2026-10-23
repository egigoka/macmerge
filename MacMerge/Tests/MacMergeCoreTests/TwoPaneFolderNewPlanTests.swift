import MacMergeCore
import XCTest

final class TwoPaneFolderNewPlanTests: XCTestCase {
    private struct CheckFailed: Error {}

    private func makeCapabilities(
        features: Set<FolderComparisonWorkflowFeature> = [.recursiveScan, .metadataComparison]
    ) -> FolderComparisonWorkflowCapabilities {
        FolderComparisonWorkflowCapabilities(
            identity: UUID(uuidString: "E3B0C442-98FC-4A2E-A2E4-000000000001")!,
            revision: 7,
            features: features
        )
    }

    private func makeFilter(ruleCount: Int = 0, digestByte: UInt8 = 0) -> TwoPaneFolderNewNameFilterReference {
        TwoPaneFolderNewNameFilterReference(ruleCount: ruleCount, rulesSHA256: Data(repeating: digestByte, count: 32))
    }

    private func makeRequest(
        leftPath: String = "/tmp/two-pane-left",
        rightPath: String = "/tmp/two-pane-right",
        leftGeneration: UInt32 = 1,
        rightGeneration: UInt32 = 2,
        leftIsDirectory: Bool = true,
        rightIsDirectory: Bool = true,
        leftDeviceID: UInt64 = 11,
        leftFileID: UInt64 = 1001,
        rightDeviceID: UInt64 = 11,
        rightFileID: UInt64 = 1002,
        depth: Int = 1,
        filter: TwoPaneFolderNewNameFilterReference? = nil,
        showFlags: Set<TwoPaneFolderNewShowFlag> = [.identical],
        capabilities: FolderComparisonWorkflowCapabilities? = nil,
        required: Set<FolderComparisonWorkflowFeature>? = nil,
        limits: TwoPaneFolderNewLimits = .default
    ) -> TwoPaneFolderNewRequest {
        TwoPaneFolderNewRequest(
            leftRoot: TwoPaneFolderNewRootIdentity(
                canonicalPath: leftPath,
                generation: leftGeneration,
                isDirectory: leftIsDirectory,
                deviceID: leftDeviceID,
                fileID: leftFileID
            ),
            rightRoot: TwoPaneFolderNewRootIdentity(
                canonicalPath: rightPath,
                generation: rightGeneration,
                isDirectory: rightIsDirectory,
                deviceID: rightDeviceID,
                fileID: rightFileID
            ),
            recursionDepth: depth,
            nameFilter: filter ?? makeFilter(),
            showFlags: showFlags,
            folderCapabilities: capabilities ?? makeCapabilities(),
            requiredFolderFeatures: required ?? TwoPaneFolderNewPlanner.requiredFolderFeatures,
            limits: limits
        )
    }

    private func assertPlanThrows(
        _ request: TwoPaneFolderNewRequest,
        code: TwoPaneFolderNewErrorCode,
        limit: TwoPaneFolderNewLimit? = nil,
        side: TwoPaneFolderNewSide? = nil,
        check: @escaping TwoPaneFolderNewCancellationCheck = { try Task.checkCancellation() },
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try TwoPaneFolderNewPlanner.plan(request, cancellationCheck: check), file: file, line: line) { error in
            guard let newError = error as? TwoPaneFolderNewError else {
                return XCTFail("Expected TwoPaneFolderNewError, got \(type(of: error))", file: file, line: line)
            }
            XCTAssertEqual(newError.code, code, file: file, line: line)
            XCTAssertEqual(newError.limit, limit, file: file, line: line)
            XCTAssertEqual(newError.side, side, file: file, line: line)
        }
    }

    func testCommandIDTargetsFileNewFolder() {
        XCTAssertEqual(TwoPaneFolderNewPlanner.commandID, "ID_FILE_NEW_FOLDER")
    }

    func testHappyPathBindsRevisionsReceiptAndContracts() throws {
        let request = makeRequest()
        let plan = try TwoPaneFolderNewPlanner.plan(request)

        XCTAssertEqual(plan.leftRevision.identity.canonicalPath, "/tmp/two-pane-left")
        XCTAssertEqual(plan.rightRevision.identity.canonicalPath, "/tmp/two-pane-right")
        XCTAssertEqual(plan.leftRevision.revisionSHA256.count, 32)
        XCTAssertEqual(plan.rightRevision.revisionSHA256.count, 32)
        XCTAssertNotEqual(plan.leftRevision.revisionSHA256, plan.rightRevision.revisionSHA256)
        XCTAssertEqual(plan.receipt.planSHA256.count, 32)
        XCTAssertEqual(plan.receipt.leftRevisionSHA256, plan.leftRevision.revisionSHA256)
        XCTAssertEqual(plan.receipt.rightRevisionSHA256, plan.rightRevision.revisionSHA256)
        XCTAssertEqual(plan.receipt.showFlagCount, 1)
        XCTAssertGreaterThan(plan.receipt.planningWorkUnits, 0)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(plan.limits, .default)
        XCTAssertNoThrow(try plan.validateReceipt())
        XCTAssertNoThrow(try plan.requireReceipt(plan.receipt))
        XCTAssertNoThrow(try plan.requireCurrentGenerations(leftGeneration: 1, rightGeneration: 2))
    }

    func testRequiredFeaturesMatchWorkflowMinimum() {
        XCTAssertEqual(TwoPaneFolderNewPlanner.requiredFolderFeatures, [.recursiveScan, .metadataComparison])
    }

    func testDuplicateCheckIgnoresCase() {
        assertPlanThrows(makeRequest(leftPath: "/tmp/Folder-Left", rightPath: "/tmp/folder-left"), code: .duplicateRoot)
    }

    func testDuplicateCheckNormalizesTrailingSlash() {
        assertPlanThrows(makeRequest(leftPath: "/tmp/dup-root/", rightPath: "/tmp/dup-root"), code: .duplicateRoot)
    }

    func testDuplicateCheckNormalizesDotComponents() {
        assertPlanThrows(makeRequest(leftPath: "/tmp/merge/../merge-left", rightPath: "/tmp/merge-left"), code: .duplicateRoot)
    }

    func testDistinctRootsPlanSuccessfully() throws {
        let plan = try TwoPaneFolderNewPlanner.plan(makeRequest(leftPath: "/tmp/alpha", rightPath: "/tmp/beta"))
        XCTAssertEqual(plan.leftRevision.identity.canonicalPath, "/tmp/alpha")
        XCTAssertEqual(plan.rightRevision.identity.canonicalPath, "/tmp/beta")
    }

    func testRuleCountBoundRejectsNegativeHugeAndOverflowValues() {
        assertPlanThrows(makeRequest(filter: makeFilter(ruleCount: -1)), code: .invalidNameFilter)
        assertPlanThrows(makeRequest(filter: makeFilter(ruleCount: Int(TwoPaneFolderNewLimits.hardMaximumWorkUnits) + 1)), code: .invalidNameFilter)
        assertPlanThrows(makeRequest(filter: makeFilter(ruleCount: Int.max)), code: .invalidNameFilter)
    }

    func testEmptyRequiredFeaturesFailsSubsetEnforcement() {
        assertPlanThrows(makeRequest(required: []), code: .unsupportedCapability)
    }

    func testRequiredFeaturesMustContainWorkflowMinimum() {
        assertPlanThrows(makeRequest(required: [.recursiveScan]), code: .unsupportedCapability)
        assertPlanThrows(makeRequest(required: [.metadataComparison]), code: .unsupportedCapability)
    }

    func testCapabilitiesMustCoverRequiredFeatures() {
        let thin = makeCapabilities(features: [.recursiveScan])
        assertPlanThrows(makeRequest(capabilities: thin), code: .unsupportedCapability)
        assertPlanThrows(makeRequest(capabilities: makeCapabilities(features: [])), code: .unsupportedCapability)
    }

    func testCapabilitiesSupersetPlansSuccessfully() throws {
        let wide = makeCapabilities(features: [.recursiveScan, .metadataComparison, .contentComparison, .cancel])
        let plan = try TwoPaneFolderNewPlanner.plan(makeRequest(capabilities: wide))
        XCTAssertEqual(plan.folderCapabilities, wide)
        XCTAssertNoThrow(try plan.validateReceipt())
    }

    func testRevisionDigestBindsPathAndGeneration() throws {
        let base = try TwoPaneFolderNewPlanner.plan(makeRequest())
        let otherPath = try TwoPaneFolderNewPlanner.plan(makeRequest(rightPath: "/tmp/two-pane-other"))
        XCTAssertNotEqual(base.rightRevision.revisionSHA256, otherPath.rightRevision.revisionSHA256)

        let otherGeneration = try TwoPaneFolderNewPlanner.plan(makeRequest(rightGeneration: 99))
        XCTAssertNotEqual(base.rightRevision.revisionSHA256, otherGeneration.rightRevision.revisionSHA256)

        let otherDevice = try TwoPaneFolderNewPlanner.plan(makeRequest(rightDeviceID: 99))
        XCTAssertNotEqual(base.rightRevision.revisionSHA256, otherDevice.rightRevision.revisionSHA256)

        let otherFileID = try TwoPaneFolderNewPlanner.plan(makeRequest(rightFileID: 9999))
        XCTAssertNotEqual(base.rightRevision.revisionSHA256, otherFileID.rightRevision.revisionSHA256)

        let identical = try TwoPaneFolderNewPlanner.plan(makeRequest())
        XCTAssertEqual(base.leftRevision.revisionSHA256, identical.leftRevision.revisionSHA256)
        XCTAssertEqual(base.rightRevision.revisionSHA256, identical.rightRevision.revisionSHA256)
    }

    func testCancellationErrorMapsToCancelled() {
        assertPlanThrows(makeRequest(), code: .cancelled, check: { throw CancellationError() })
    }

    func testNonCancellationCheckErrorStillCancels() {
        assertPlanThrows(makeRequest(), code: .cancelled, check: { throw CheckFailed() })
    }

    func testDomainErrorsAreNotRemappedToCancelled() {
        assertPlanThrows(makeRequest(leftPath: ""), code: .invalidRoot, side: .left)
    }

    func testInvalidLimitRoots() {
        assertPlanThrows(makeRequest(limits: TwoPaneFolderNewLimits(maximumRoots: 1)), code: .invalidLimit, limit: .roots)
        assertPlanThrows(makeRequest(limits: TwoPaneFolderNewLimits(maximumRoots: 3)), code: .invalidLimit, limit: .roots)
    }

    func testInvalidLimitPathUTF8BytesBounds() {
        assertPlanThrows(makeRequest(limits: TwoPaneFolderNewLimits(maximumPathUTF8Bytes: 0)), code: .invalidLimit, limit: .pathUTF8Bytes)
        let over = TwoPaneFolderNewLimits(maximumPathUTF8Bytes: TwoPaneFolderNewLimits.hardMaximumPathUTF8Bytes + 1)
        assertPlanThrows(makeRequest(limits: over), code: .invalidLimit, limit: .pathUTF8Bytes)
    }

    func testInvalidLimitTotalPathUTF8BytesBounds() {
        let belowPerPath = TwoPaneFolderNewLimits(maximumPathUTF8Bytes: 16, maximumTotalPathUTF8Bytes: 8)
        assertPlanThrows(makeRequest(limits: belowPerPath), code: .invalidLimit, limit: .totalPathUTF8Bytes)
        let overHard = TwoPaneFolderNewLimits(
            maximumPathUTF8Bytes: 16, maximumTotalPathUTF8Bytes: TwoPaneFolderNewLimits.hardMaximumTotalPathUTF8Bytes + 1)
        assertPlanThrows(makeRequest(limits: overHard), code: .invalidLimit, limit: .totalPathUTF8Bytes)
    }

    func testInvalidLimitDepthWorkUnitsAndCheckInterval() {
        assertPlanThrows(makeRequest(limits: TwoPaneFolderNewLimits(maximumDepth: 257)), code: .invalidLimit, limit: .depth)
        assertPlanThrows(makeRequest(limits: TwoPaneFolderNewLimits(maximumWorkUnits: 0)), code: .invalidLimit, limit: .workUnits)
        assertPlanThrows(makeRequest(limits: TwoPaneFolderNewLimits(cancellationCheckInterval: 0)), code: .invalidLimit, limit: .cancellationCheckInterval)
        let overInterval = TwoPaneFolderNewLimits(cancellationCheckInterval: TwoPaneFolderNewLimits.hardMaximumCancellationCheckInterval + 1)
        assertPlanThrows(makeRequest(limits: overInterval), code: .invalidLimit, limit: .cancellationCheckInterval)
    }

    func testTinyWorkBudgetExceedsWorkLimit() {
        assertPlanThrows(makeRequest(limits: TwoPaneFolderNewLimits(maximumWorkUnits: 1)), code: .workLimitExceeded, limit: .workUnits)
    }

    func testPathTooLargeAndExactBoundaryPasses() throws {
        let limits = TwoPaneFolderNewLimits(maximumPathUTF8Bytes: 4, maximumTotalPathUTF8Bytes: 64)
        assertPlanThrows(makeRequest(leftPath: "/left", limits: limits), code: .pathTooLarge, limit: .pathUTF8Bytes)

        let boundary = try TwoPaneFolderNewPlanner.plan(makeRequest(leftPath: "/abc", rightPath: "/abd", limits: limits))
        XCTAssertEqual(boundary.leftRevision.identity.canonicalPath, "/abc")
    }

    func testTotalPathsTooLarge() {
        let limits = TwoPaneFolderNewLimits(maximumPathUTF8Bytes: 16, maximumTotalPathUTF8Bytes: 20)
        let request = makeRequest(leftPath: "/aaaaaaaaaaaaaaa", rightPath: "/bbbbbbbbbbbbbbb", limits: limits)
        assertPlanThrows(request, code: .totalPathsTooLarge, limit: .totalPathUTF8Bytes)
    }

    func testEmptyRootPathFailsWithSide() {
        assertPlanThrows(makeRequest(leftPath: ""), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(rightPath: ""), code: .invalidRoot, side: .right)
    }

    func testNonDirectoryRootFailsWithSide() {
        assertPlanThrows(makeRequest(leftIsDirectory: false), code: .rootNotDirectory, side: .left)
        assertPlanThrows(makeRequest(rightIsDirectory: false), code: .rootNotDirectory, side: .right)
    }

    func testRecursionDepthBoundsAndBoundaries() throws {
        assertPlanThrows(makeRequest(depth: -1), code: .invalidDepth, limit: .depth)
        assertPlanThrows(makeRequest(depth: 65), code: .invalidDepth, limit: .depth)

        XCTAssertNoThrow(try TwoPaneFolderNewPlanner.plan(makeRequest(depth: 0)))
        let atMax = try TwoPaneFolderNewPlanner.plan(makeRequest(depth: 64))
        XCTAssertEqual(atMax.recursionDepth, 64)
    }

    func testShowFlagsRequireAtLeastOne() throws {
        assertPlanThrows(makeRequest(showFlags: []), code: .invalidShowFlags)

        let all = try TwoPaneFolderNewPlanner.plan(makeRequest(showFlags: Set(TwoPaneFolderNewShowFlag.allCases)))
        XCTAssertEqual(all.showFlags.count, TwoPaneFolderNewShowFlag.allCases.count)
        XCTAssertEqual(all.receipt.showFlagCount, TwoPaneFolderNewShowFlag.allCases.count)
    }

    func testNameFilterRejectsBadDigestAndNegativeCount() {
        let short = TwoPaneFolderNewNameFilterReference(ruleCount: 0, rulesSHA256: Data(repeating: 0, count: 31))
        assertPlanThrows(makeRequest(filter: short), code: .invalidNameFilter)
        let long = TwoPaneFolderNewNameFilterReference(ruleCount: 0, rulesSHA256: Data(repeating: 0, count: 33))
        assertPlanThrows(makeRequest(filter: long), code: .invalidNameFilter)
        assertPlanThrows(makeRequest(filter: makeFilter(ruleCount: -5)), code: .invalidNameFilter)
    }

    func testReceiptDeterminismAndFlagOrderIndependence() throws {
        let first = try TwoPaneFolderNewPlanner.plan(makeRequest())
        let second = try TwoPaneFolderNewPlanner.plan(makeRequest())
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first, second)

        let orderedA = try TwoPaneFolderNewPlanner.plan(makeRequest(showFlags: [.identical, .different]))
        let orderedB = try TwoPaneFolderNewPlanner.plan(makeRequest(showFlags: [.different, .identical]))
        XCTAssertEqual(orderedA.receipt.planSHA256, orderedB.receipt.planSHA256)
    }

    func testReceiptMismatchOnForgedReceipt() throws {
        let plan = try TwoPaneFolderNewPlanner.plan(makeRequest())
        let forged = TwoPaneFolderNewPlanningReceipt(
            planSHA256: Data(repeating: 9, count: 32),
            leftRevisionSHA256: plan.receipt.leftRevisionSHA256,
            rightRevisionSHA256: plan.receipt.rightRevisionSHA256,
            showFlagCount: plan.receipt.showFlagCount,
            planningWorkUnits: plan.receipt.planningWorkUnits
        )
        XCTAssertThrowsError(try plan.requireReceipt(forged)) { error in
            guard let newError = error as? TwoPaneFolderNewError else {
                return XCTFail("Expected TwoPaneFolderNewError")
            }
            XCTAssertEqual(newError.code, .receiptMismatch)
        }
    }

    func testStaleGenerationRejectsDriftedExecutorState() throws {
        let plan = try TwoPaneFolderNewPlanner.plan(makeRequest(leftGeneration: 3, rightGeneration: 4))
        XCTAssertNoThrow(try plan.requireCurrentGenerations(leftGeneration: 3, rightGeneration: 4))
        do {
            try plan.requireCurrentGenerations(leftGeneration: 30, rightGeneration: 4)
            XCTFail("Expected staleGeneration")
        } catch let error as TwoPaneFolderNewError {
            XCTAssertEqual(error.code, .staleGeneration)
            XCTAssertEqual(error.side, .left)
            XCTAssertEqual(error.expectedGeneration, 3)
            XCTAssertEqual(error.actualGeneration, 30)
        }
        do {
            try plan.requireCurrentGenerations(leftGeneration: 3, rightGeneration: 40)
            XCTFail("Expected staleGeneration")
        } catch let error as TwoPaneFolderNewError {
            XCTAssertEqual(error.code, .staleGeneration)
            XCTAssertEqual(error.side, .right)
            XCTAssertEqual(error.expectedGeneration, 4)
            XCTAssertEqual(error.actualGeneration, 40)
        }
    }

    func testRedactionAcrossDescriptions() throws {
        let secret = "/tmp/secret-vault-left"
        let request = makeRequest(leftPath: secret, rightPath: "/tmp/secret-vault-right")
        let plan = try TwoPaneFolderNewPlanner.plan(request)

        for rendered in [request.description, request.debugDescription, plan.description, plan.debugDescription] {
            XCTAssertTrue(rendered.contains("<redacted>"))
            XCTAssertFalse(rendered.contains(secret))
        }
        for rendered in [plan.leftRevision.description, plan.nameFilter.description, String(describing: plan.leftRevision.identity)] {
            XCTAssertTrue(rendered.contains("<redacted>"))
            XCTAssertFalse(rendered.contains(secret))
        }
        XCTAssertEqual(Array(plan.leftRevision.identity.customMirror.children.map { $0.label }), ["isDirectory", "details"])

        do {
            _ = try TwoPaneFolderNewPlanner.plan(makeRequest(leftPath: ""))
            XCTFail("Expected invalidRoot")
        } catch let newError as TwoPaneFolderNewError {
            XCTAssertTrue(newError.description.contains("invalidRoot"))
            XCTAssertTrue(newError.description.contains("<redacted>"))
            XCTAssertEqual(newError.errorDescription, "Two-pane folder creation received an invalid directory root.")
            XCTAssertEqual(Array(newError.customMirror.children.map { $0.label }), ["code", "details"])
        }
        XCTAssertTrue(TwoPaneFolderNewErrorCode.allCases.contains(.invalidRoot))
        XCTAssertEqual(TwoPaneFolderNewLimit.allCases.count, 6)
        XCTAssertTrue(TwoPaneFolderNewErrorCode.allCases.contains(.receiptMismatch))
        XCTAssertTrue(TwoPaneFolderNewErrorCode.allCases.contains(.staleGeneration))
    }

    func testHardMaximumLimitsPlanSucceeds() throws {
        let limits = TwoPaneFolderNewLimits(
            maximumRoots: 2,
            maximumPathUTF8Bytes: TwoPaneFolderNewLimits.hardMaximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: TwoPaneFolderNewLimits.hardMaximumTotalPathUTF8Bytes,
            maximumDepth: TwoPaneFolderNewLimits.hardMaximumDepth,
            maximumWorkUnits: TwoPaneFolderNewLimits.hardMaximumWorkUnits,
            cancellationCheckInterval: TwoPaneFolderNewLimits.hardMaximumCancellationCheckInterval
        )
        let plan = try TwoPaneFolderNewPlanner.plan(makeRequest(depth: 256, limits: limits))
        XCTAssertEqual(plan.recursionDepth, 256)
        XCTAssertNoThrow(try plan.validateReceipt())
    }

    func testZeroIDsFailClosedWithSide() {
        assertPlanThrows(makeRequest(leftDeviceID: 0), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(leftFileID: 0), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(rightDeviceID: 0), code: .invalidRoot, side: .right)
        assertPlanThrows(makeRequest(rightFileID: 0), code: .invalidRoot, side: .right)
        assertPlanThrows(
            makeRequest(leftDeviceID: 0, leftFileID: 0, rightDeviceID: 0, rightFileID: 0),
            code: .invalidRoot,
            side: .left
        )
    }

    func testDefaultZeroCompatIdentityRejectsAtPlan() {
        let identity = TwoPaneFolderNewRootIdentity(canonicalPath: "/tmp/compat", generation: 1, isDirectory: true)
        XCTAssertEqual(identity.deviceID, 0)
        XCTAssertEqual(identity.fileID, 0)
        assertPlanThrows(makeRequest(leftPath: "/tmp/compat", leftDeviceID: 0, leftFileID: 0), code: .invalidRoot, side: .left)
    }

    func testCanonicalPathGateRejectsNonCanonicalRoots() {
        assertPlanThrows(makeRequest(leftPath: "//tmp/double-slash"), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(rightPath: "//tmp/double-slash"), code: .invalidRoot, side: .right)
        assertPlanThrows(makeRequest(leftPath: "relative/path"), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(leftPath: "/tmp/bad\0path"), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(rightPath: "/tmp/bad\0path"), code: .invalidRoot, side: .right)
    }

    func testFoldedDuplicateRejectsUnicodeNormalization() {
        assertPlanThrows(
            makeRequest(leftPath: "/tmp/caf\u{00E9}x", rightPath: "/tmp/cafe\u{0301}x"),
            code: .duplicateRoot
        )
    }

    func testAncestorContainmentRejectsNestedRoots() {
        assertPlanThrows(
            makeRequest(leftPath: "/tmp/parent", rightPath: "/tmp/parent/child"),
            code: .duplicateRoot
        )
        assertPlanThrows(
            makeRequest(leftPath: "/tmp/parent/child", rightPath: "/tmp/parent"),
            code: .duplicateRoot
        )
    }

    func testAncestorBoundaryIsSeparatorAware() throws {
        let plan = try TwoPaneFolderNewPlanner.plan(
            makeRequest(leftPath: "/tmp/abc", rightPath: "/tmp/abcd")
        )
        XCTAssertEqual(plan.leftRevision.identity.canonicalPath, "/tmp/abc")
        XCTAssertEqual(plan.rightRevision.identity.canonicalPath, "/tmp/abcd")
    }

    func testRootSlashIsAncestorOfAllRoots() {
        assertPlanThrows(
            makeRequest(leftPath: "/", rightPath: "/tmp/leaf"),
            code: .duplicateRoot
        )
    }

    func testSwapDetectionRevisionDigestChangesOnRecreate() throws {
        let base = try TwoPaneFolderNewPlanner.plan(makeRequest())
        let recreated = try TwoPaneFolderNewPlanner.plan(makeRequest(rightFileID: 7777))
        XCTAssertNotEqual(base.rightRevision.revisionSHA256, recreated.rightRevision.revisionSHA256)
        let movedDevice = try TwoPaneFolderNewPlanner.plan(makeRequest(rightDeviceID: 12))
        XCTAssertNotEqual(base.rightRevision.revisionSHA256, movedDevice.rightRevision.revisionSHA256)
    }

    func testSwappedRootsChangePlanDigest() throws {
        let base = try TwoPaneFolderNewPlanner.plan(makeRequest())
        let swapped = try TwoPaneFolderNewPlanner.plan(
            makeRequest(
                leftPath: "/tmp/two-pane-right",
                rightPath: "/tmp/two-pane-left",
                leftGeneration: 2,
                rightGeneration: 1,
                leftDeviceID: 11,
                leftFileID: 1002,
                rightDeviceID: 11,
                rightFileID: 1001
            )
        )
        XCTAssertEqual(swapped.leftRevision.revisionSHA256, base.rightRevision.revisionSHA256)
        XCTAssertEqual(swapped.rightRevision.revisionSHA256, base.leftRevision.revisionSHA256)
        XCTAssertNotEqual(swapped.receipt.planSHA256, base.receipt.planSHA256)
    }

    func testIsDirectoryFlagBoundIntoRevision() {
        assertPlanThrows(makeRequest(leftIsDirectory: false), code: .rootNotDirectory, side: .left)
        assertPlanThrows(makeRequest(rightIsDirectory: false), code: .rootNotDirectory, side: .right)
    }

    func testPlanningWorkUnitsRecheckedAgainstLimits() throws {
        let plan = try TwoPaneFolderNewPlanner.plan(makeRequest())
        XCTAssertGreaterThan(plan.receipt.planningWorkUnits, 0)
        XCTAssertLessThanOrEqual(plan.receipt.planningWorkUnits, TwoPaneFolderNewLimits.default.maximumWorkUnits)
        let identical = try TwoPaneFolderNewPlanner.plan(makeRequest())
        XCTAssertEqual(plan.receipt.planningWorkUnits, identical.receipt.planningWorkUnits)
        XCTAssertNoThrow(try plan.validateReceipt())
    }

    func testCheckCancellationRethrowsDomainErrorUnchanged() {
        var captured: Error?
        XCTAssertThrowsError(try TwoPaneFolderNewPlanner.plan(makeRequest(leftPath: ""))) { captured = $0 }
        guard let domainError = captured as? TwoPaneFolderNewError else {
            return XCTFail("Expected TwoPaneFolderNewError capture")
        }
        XCTAssertEqual(domainError.code, .invalidRoot)
        assertPlanThrows(
            makeRequest(),
            code: domainError.code,
            side: domainError.side,
            check: { throw domainError }
        )
    }

    func testCoarsePerKBBilling() throws {
        let short = try TwoPaneFolderNewPlanner.plan(makeRequest(leftPath: "/tmp/a", rightPath: "/tmp/b"))
        let longComponent = String(repeating: "a", count: 1500)
        let long = try TwoPaneFolderNewPlanner.plan(
            makeRequest(leftPath: "/" + longComponent, rightPath: "/tmp/b")
        )
        let byteDelta = ("/" + longComponent).utf8.count - "/tmp/a".utf8.count
        XCTAssertGreaterThan(byteDelta, 1_400)
        let workDelta: UInt64
        if long.receipt.planningWorkUnits > short.receipt.planningWorkUnits {
            workDelta = long.receipt.planningWorkUnits - short.receipt.planningWorkUnits
        } else {
            workDelta = short.receipt.planningWorkUnits - long.receipt.planningWorkUnits
        }
        XCTAssertLessThan(workDelta, 8)
    }

    func testGenerationZeroFailsClosed() {
        assertPlanThrows(makeRequest(leftGeneration: 0), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(rightGeneration: 0), code: .invalidRoot, side: .right)
        assertPlanThrows(makeRequest(leftGeneration: 0, rightGeneration: 0), code: .invalidRoot, side: .left)
    }

    func testStrictGateRejectsNonCanonicalDistinctRoots() {
        assertPlanThrows(makeRequest(leftPath: "/tmp//distinct-a", rightPath: "/tmp/distinct-b"), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(leftPath: "/tmp/a/./b", rightPath: "/tmp/other"), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(leftPath: "/tmp/a/../b", rightPath: "/tmp/other"), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(leftPath: "/tmp/trailing/", rightPath: "/tmp/other"), code: .invalidRoot, side: .left)
        assertPlanThrows(makeRequest(leftPath: "/tmp/other", rightPath: "/tmp//distinct"), code: .invalidRoot, side: .right)
        assertPlanThrows(makeRequest(leftPath: "/tmp/other", rightPath: "/tmp/a/./b"), code: .invalidRoot, side: .right)
        assertPlanThrows(makeRequest(leftPath: "/tmp/other", rightPath: "/tmp/a/../b"), code: .invalidRoot, side: .right)
        assertPlanThrows(makeRequest(leftPath: "/tmp/other", rightPath: "/tmp/trailing/"), code: .invalidRoot, side: .right)
    }

    func testNormalizedDuplicatesPreserveDuplicateRootForStrictForms() {
        assertPlanThrows(makeRequest(leftPath: "/tmp/dup-a/./b", rightPath: "/tmp/dup-a/b"), code: .duplicateRoot)
        assertPlanThrows(makeRequest(leftPath: "/tmp/dup-b/../dup-b", rightPath: "/tmp/dup-b"), code: .duplicateRoot)
        assertPlanThrows(makeRequest(leftPath: "/tmp//dup-c", rightPath: "/tmp/dup-c"), code: .duplicateRoot)
        assertPlanThrows(makeRequest(leftPath: "/tmp/dup-d/", rightPath: "/tmp/dup-d"), code: .duplicateRoot)
    }

    func testPlanningWorkUnitsUpperBoundOnlyTolerance() throws {
        // planningWorkUnits is accounting telemetry, not executor authority:
        // validateReceipt checks upper-bound only, requireReceipt checks exact equality.
        let plan = try TwoPaneFolderNewPlanner.plan(makeRequest())
        XCTAssertLessThan(plan.receipt.planningWorkUnits, plan.limits.maximumWorkUnits)
        XCTAssertNoThrow(try plan.validateReceipt())
        let understated = TwoPaneFolderNewPlanningReceipt(
            planSHA256: plan.receipt.planSHA256,
            leftRevisionSHA256: plan.receipt.leftRevisionSHA256,
            rightRevisionSHA256: plan.receipt.rightRevisionSHA256,
            showFlagCount: plan.receipt.showFlagCount,
            planningWorkUnits: 0
        )
        XCTAssertThrowsError(try plan.requireReceipt(understated)) { error in
            XCTAssertEqual((error as? TwoPaneFolderNewError)?.code, .receiptMismatch)
        }
        let overstated = TwoPaneFolderNewPlanningReceipt(
            planSHA256: plan.receipt.planSHA256,
            leftRevisionSHA256: plan.receipt.leftRevisionSHA256,
            rightRevisionSHA256: plan.receipt.rightRevisionSHA256,
            showFlagCount: plan.receipt.showFlagCount,
            planningWorkUnits: plan.limits.maximumWorkUnits + 1
        )
        XCTAssertThrowsError(try plan.requireReceipt(overstated)) { error in
            XCTAssertEqual((error as? TwoPaneFolderNewError)?.code, .receiptMismatch)
        }
        let exactLimits = TwoPaneFolderNewLimits(maximumWorkUnits: plan.receipt.planningWorkUnits)
        XCTAssertNoThrow(try TwoPaneFolderNewPlanner.plan(makeRequest(limits: exactLimits)))
        let shortLimits = TwoPaneFolderNewLimits(maximumWorkUnits: plan.receipt.planningWorkUnits - 1)
        assertPlanThrows(makeRequest(limits: shortLimits), code: .workLimitExceeded, limit: .workUnits)
    }

    func testRequireCurrentIdentitiesCatchesSwap() throws {
        let plan = try TwoPaneFolderNewPlanner.plan(makeRequest(
            leftGeneration: 5, rightGeneration: 6,
            leftDeviceID: 11, leftFileID: 1001,
            rightDeviceID: 11, rightFileID: 1002
        ))
        XCTAssertNoThrow(try plan.requireCurrentIdentities(
            leftDeviceID: 11, leftFileID: 1001, leftGeneration: 5,
            rightDeviceID: 11, rightFileID: 1002, rightGeneration: 6
        ))
        // Generation-only check passes when generations match, proving it alone misses swap.
        XCTAssertNoThrow(try plan.requireCurrentGenerations(leftGeneration: 5, rightGeneration: 6))
        do {
            try plan.requireCurrentIdentities(
                leftDeviceID: 99, leftFileID: 1001, leftGeneration: 5,
                rightDeviceID: 11, rightFileID: 1002, rightGeneration: 6
            )
            XCTFail("Expected staleGeneration for left device drift")
        } catch let error as TwoPaneFolderNewError {
            XCTAssertEqual(error.code, .staleGeneration)
            XCTAssertEqual(error.side, .left)
            XCTAssertEqual(error.expectedGeneration, 5)
            XCTAssertEqual(error.actualGeneration, 5)
        }
        do {
            try plan.requireCurrentIdentities(
                leftDeviceID: 11, leftFileID: 9999, leftGeneration: 5,
                rightDeviceID: 11, rightFileID: 1002, rightGeneration: 6
            )
            XCTFail("Expected staleGeneration for left fileID drift")
        } catch let error as TwoPaneFolderNewError {
            XCTAssertEqual(error.code, .staleGeneration)
            XCTAssertEqual(error.side, .left)
            XCTAssertEqual(error.expectedGeneration, 5)
            XCTAssertEqual(error.actualGeneration, 5)
        }
        do {
            try plan.requireCurrentIdentities(
                leftDeviceID: 11, leftFileID: 1001, leftGeneration: 5,
                rightDeviceID: 12, rightFileID: 1002, rightGeneration: 6
            )
            XCTFail("Expected staleGeneration for right device drift")
        } catch let error as TwoPaneFolderNewError {
            XCTAssertEqual(error.code, .staleGeneration)
            XCTAssertEqual(error.side, .right)
            XCTAssertEqual(error.expectedGeneration, 6)
            XCTAssertEqual(error.actualGeneration, 6)
        }
        do {
            try plan.requireCurrentIdentities(
                leftDeviceID: 11, leftFileID: 1001, leftGeneration: 5,
                rightDeviceID: 11, rightFileID: 7777, rightGeneration: 6
            )
            XCTFail("Expected staleGeneration for right fileID drift")
        } catch let error as TwoPaneFolderNewError {
            XCTAssertEqual(error.code, .staleGeneration)
            XCTAssertEqual(error.side, .right)
            XCTAssertEqual(error.expectedGeneration, 6)
            XCTAssertEqual(error.actualGeneration, 6)
        }
    }

    func testHugePathFailsFastWithoutWorkBurn() {
        let huge = "/" + String(repeating: "a", count: 1_000_000)
        let tiny = TwoPaneFolderNewLimits(
            maximumPathUTF8Bytes: 64,
            maximumTotalPathUTF8Bytes: 256 * 1_024,
            maximumWorkUnits: 32
        )
        assertPlanThrows(makeRequest(leftPath: huge, limits: tiny), code: .pathTooLarge, limit: .pathUTF8Bytes)
        assertPlanThrows(makeRequest(rightPath: huge, limits: tiny), code: .pathTooLarge, limit: .pathUTF8Bytes)
    }

    func testTotalBeforeConsumeWithoutWorkBurn() {
        let left = "/" + String(repeating: "a", count: 15)
        let right = "/" + String(repeating: "b", count: 15)
        XCTAssertEqual(left.utf8.count, 16)
        XCTAssertEqual(right.utf8.count, 16)
        let limits = TwoPaneFolderNewLimits(
            maximumPathUTF8Bytes: 16,
            maximumTotalPathUTF8Bytes: 20,
            maximumWorkUnits: 18
        )
        assertPlanThrows(
            makeRequest(leftPath: left, rightPath: right, limits: limits),
            code: .totalPathsTooLarge,
            limit: .totalPathUTF8Bytes
        )
    }
}
