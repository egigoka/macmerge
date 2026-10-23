import MacMergeCore
import XCTest

final class ThreePaneTableNewPlanTests: XCTestCase {
    private func digest(_ seed: UInt8) -> [UInt8] {
        Array(repeating: seed, count: 32)
    }

    private func fullHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", Int($0)) }.joined()
    }

    private func identity(path: String = "/left.csv", byteSize: Int = 100, seed: UInt8 = 0x11) -> ThreePaneTableNewFileIdentity {
        ThreePaneTableNewFileIdentity(canonicalPath: path, byteSize: byteSize, contentSHA256: digest(seed))
    }

    private func filePane(_ pane: ThreePaneTableNewPane, path: String, seed: UInt8, byteSize: Int = 100) -> ThreePaneTableNewRequestPane {
        ThreePaneTableNewRequestPane(pane: pane, source: .file(identity(path: path, byteSize: byteSize, seed: seed)))
    }

    private func threeFileRequest(
        delimiter: ThreePaneTableNewDelimiter = .comma,
        rows: Int = 10,
        cells: Int = 20,
        orientation: ThreePaneTableNewOrientation = .sideBySide,
        capability: ThreePaneTableNewCapabilityRequirement = ThreePaneTableNewCapabilityRequirement()
    ) -> ThreePaneTableNewRequest {
        ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: delimiter,
            orientation: orientation,
            capability: capability,
            declaredRowCount: rows,
            declaredCellCount: cells
        )
    }

    private func assertPlanError(_ expected: ThreePaneTableNewError, request: ThreePaneTableNewRequest, limits: ThreePaneTableNewLimits = .default) {
        XCTAssertThrowsError(try ThreePaneTableNewPlan.plan(request: request, limits: limits)) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, expected)
        }
    }

    func testCommandIDMatchesTodoEntry() {
        XCTAssertEqual(ThreePaneTableNewPlan.commandID, "ID_FILE_NEW3_TABLE")
    }

    func testHappyPathThreeFilesPlansSortedReceipt() throws {
        let request = threeFileRequest()
        let plan = try ThreePaneTableNewPlan.plan(request: request)
        XCTAssertEqual(plan.panes.map { $0.pane }, [.left, .middle, .right])
        XCTAssertEqual(plan.delimiter, .comma)
        XCTAssertEqual(plan.orientation, .sideBySide)
        XCTAssertEqual(plan.executorContract, .planOnly)
        XCTAssertFalse(plan.isTwoSourceMerge)
        XCTAssertGreaterThan(plan.workPerformed, 0)
        XCTAssertEqual(plan.receipt.declaredRowCount, 10)
        XCTAssertEqual(plan.receipt.declaredCellCount, 20)
        XCTAssertEqual(plan.receipt.delimiterByteCount, 1)
        XCTAssertEqual(plan.receipt.leftDigestPrefix, identity(seed: 0x11).digestPrefix)
        XCTAssertEqual(plan.receipt.middleDigestPrefix, identity(seed: 0x22).digestPrefix)
        XCTAssertEqual(plan.receipt.rightDigestPrefix, identity(seed: 0x33).digestPrefix)
        XCTAssertTrue(plan.receipt.identifier.contains("rows:10"))
        XCTAssertTrue(plan.receipt.identifier.contains("cells:20"))
        XCTAssertTrue(plan.receipt.identifier.hasPrefix("three-pane-table-new "))
    }

    func testHappyPathEmptyMiddleIsTwoSourceMerge() throws {
        let request = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                ThreePaneTableNewRequestPane(pane: .middle, source: .empty),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .tab,
            declaredRowCount: 4,
            declaredCellCount: 8
        )
        let plan = try ThreePaneTableNewPlan.plan(request: request)
        XCTAssertTrue(plan.isTwoSourceMerge)
        XCTAssertEqual(plan.receipt.middleDigestPrefix, "empty")
        XCTAssertTrue(plan.receipt.identifier.contains("middle:empty"))
        XCTAssertEqual(plan.receipt.sourceCount, 2)
        XCTAssertEqual(plan.orientation, .sideBySide)
    }

    func testPlanAndMakeAgreeDeterministic() throws {
        let request = threeFileRequest()
        let viaPlan = try ThreePaneTableNewPlan.plan(request: request)
        let viaMake = try ThreePaneTableNewPlan.make(request: request)
        XCTAssertEqual(viaPlan.receipt, viaMake.receipt)
        XCTAssertEqual(viaPlan, viaMake)
    }

    func testZeroRowsZeroCellsAccepted() throws {
        let plan = try ThreePaneTableNewPlan.plan(request: threeFileRequest(rows: 0, cells: 0))
        XCTAssertEqual(plan.receipt.declaredRowCount, 0)
        XCTAssertEqual(plan.receipt.declaredCellCount, 0)
    }

    func testPositiveRowsZeroCellsAccepted() throws {
        let plan = try ThreePaneTableNewPlan.plan(request: threeFileRequest(rows: 5, cells: 0))
        XCTAssertEqual(plan.receipt.declaredRowCount, 5)
    }

    func testZeroRowsPositiveCellsRejected() {
        assertPlanError(
            .inconsistentDeclaredCounts(declaredRows: 0, declaredCells: 3),
            request: threeFileRequest(rows: 0, cells: 3)
        )
    }

    func testRowCountBoundaryAcceptMaxRejectOver() throws {
        let limits = ThreePaneTableNewLimits(maximumRowCount: 5)
        let accepted = try ThreePaneTableNewPlan.plan(request: threeFileRequest(rows: 5, cells: 1), limits: limits)
        XCTAssertEqual(accepted.receipt.declaredRowCount, 5)
        assertPlanError(.rowLimitExceeded(maximumRows: 5), request: threeFileRequest(rows: 6, cells: 1), limits: limits)
    }

    func testCellCountBoundaryAcceptMaxRejectOver() throws {
        let limits = ThreePaneTableNewLimits(maximumCellCount: 7)
        let accepted = try ThreePaneTableNewPlan.plan(request: threeFileRequest(rows: 1, cells: 7), limits: limits)
        XCTAssertEqual(accepted.receipt.declaredCellCount, 7)
        assertPlanError(.cellLimitExceeded(maximumCells: 7), request: threeFileRequest(rows: 1, cells: 8), limits: limits)
    }

    func testInvalidPaneCountTwoAndFourRejected() {
        let two = ThreePaneTableNewRequest(
            panes: [filePane(.left, path: "/left.csv", seed: 0x11), filePane(.right, path: "/right.csv", seed: 0x33)],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.invalidPaneCount(expected: 3, actual: 2), request: two)
        let four = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33),
                filePane(.left, path: "/extra.csv", seed: 0x44)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.invalidPaneCount(expected: 3, actual: 4), request: four)
    }

    func testDuplicatePaneRejected() {
        let request = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                filePane(.left, path: "/other.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.duplicatePane(.left), request: request)
    }

    func testMissingPaneCaseExistsWithDescription() {
        // Defensive-only: with three slots, no duplicates, and a three-case pane
        // enum, a missing pane is unreachable via plan() (pigeonhole: any missing
        // pane forces a duplicate, which throws first). Case retained for
        // API stability and future panes.
        let error = ThreePaneTableNewError.missingPane(.middle)
        XCTAssertEqual(error, ThreePaneTableNewError.missingPane(.middle))
        XCTAssertTrue(error.debugDescription.contains("middle"))
    }

    func testMissingPaneUnreachableDuplicateFiresFirst() {
        // Any three-slot shape missing a pane repeats another pane, so the
        // duplicate check fires before the defensive missing-pane check.
        let missingMiddle = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                filePane(.left, path: "/other.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.duplicatePane(.left), request: missingMiddle)
        let missingRight = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.middle, path: "/other.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.duplicatePane(.middle), request: missingRight)
    }

    func testUnexpectedEmptyLeftAndRightRejected() {
        let leftEmpty = ThreePaneTableNewRequest(
            panes: [
                ThreePaneTableNewRequestPane(pane: .left, source: .empty),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.unexpectedEmptyPane(.left), request: leftEmpty)
        let rightEmpty = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                ThreePaneTableNewRequestPane(pane: .right, source: .empty)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.unexpectedEmptyPane(.right), request: rightEmpty)
    }

    func testEmptyMiddleUnsupportedWhenCapabilityForbids() {
        let capability = ThreePaneTableNewCapabilityRequirement(supportsEmptyMiddle: false)
        let request = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                ThreePaneTableNewRequestPane(pane: .middle, source: .empty),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            capability: capability,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.emptyMiddleUnsupported, request: request)
    }

    func testUnsupportedCapabilityNamesRejected() {
        let badParser = ThreePaneTableNewCapabilityRequirement(parserCoreName: "Nope")
        assertPlanError(.unsupportedCapability(name: "Nope"), request: threeFileRequest(capability: badParser))
        let badTwoWay = ThreePaneTableNewCapabilityRequirement(twoWayCoreName: "Nope")
        assertPlanError(.unsupportedCapability(name: "Nope"), request: threeFileRequest(capability: badTwoWay))
        let badThreeWay = ThreePaneTableNewCapabilityRequirement(threeWayCoreName: "Nope")
        assertPlanError(.unsupportedCapability(name: "Nope"), request: threeFileRequest(capability: badThreeWay))
    }

    func testAuthoritativeCapabilityValidates() throws {
        let capability = ThreePaneTableNewCapabilityRequirement()
        XCTAssertNoThrow(try capability.validate())
        XCTAssertEqual(ThreePaneTableNewCapabilityRequirement.authoritativeCores.count, 3)
        XCTAssertEqual(ThreePaneTableNewExecutorContract.planOnly.requiredCores, ThreePaneTableNewCapabilityRequirement.authoritativeCores)
        XCTAssertTrue(ThreePaneTableNewCapabilityRequirement.authoritativeCores.contains("DelimitedTableParser"))
    }

    func testUnsupportedFeatureRejected() {
        var request = threeFileRequest()
        request = ThreePaneTableNewRequest(
            panes: request.panes,
            delimiter: request.delimiter,
            quote: request.quote,
            allowsNewlinesInQuotedCells: request.allowsNewlinesInQuotedCells,
            headerVisibility: request.headerVisibility,
            headerLabels: request.headerLabels,
            selection: request.selection,
            requiredFeatures: [],
            datasetRevision: request.datasetRevision,
            orientation: request.orientation,
            capability: request.capability,
            declaredRowCount: request.declaredRowCount,
            declaredCellCount: request.declaredCellCount
        )
        XCTAssertThrowsError(try ThreePaneTableNewPlan.plan(request: request)) { error in
            guard case .unsupportedFeature = error as? ThreePaneTableNewError else {
                return XCTFail("Expected unsupportedFeature got \(error)")
            }
        }
    }

    func testInvalidPathEmptyAndNulRejected() {
        let empty = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "", seed: 0x11),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.invalidPath(.left), request: empty)
        let nul = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/a\0b.csv", seed: 0x11),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.invalidPath(.left), request: nul)
    }

    func testPathBoundaryAcceptMaxRejectOver() throws {
        let limits = ThreePaneTableNewLimits(maximumPathUTF8Bytes: 4)
        let accepted = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/abc", seed: 0x11),
                filePane(.middle, path: "/mid", seed: 0x22),
                filePane(.right, path: "/rgt", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        XCTAssertNoThrow(try ThreePaneTableNewPlan.plan(request: accepted, limits: limits))
        let rejected = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/abcd", seed: 0x11),
                filePane(.middle, path: "/mid", seed: 0x22),
                filePane(.right, path: "/rgt", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.pathTooLarge(pane: .left, maximumUTF8Bytes: 4), request: rejected, limits: limits)
    }

    func testPathGuardBeforeConsume() {
        let limits = ThreePaneTableNewLimits(maximumPathUTF8Bytes: 4)
        let rejected = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/way-too-long-path.csv", seed: 0x11),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        XCTAssertThrowsError(try ThreePaneTableNewPlan.plan(request: rejected, limits: limits)) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, .pathTooLarge(pane: .left, maximumUTF8Bytes: 4))
        }
    }

    func testSourceBytesBoundaryAcceptMaxRejectOver() throws {
        let limits = ThreePaneTableNewLimits(maximumSourceBytes: 10)
        let accepted = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11, byteSize: 10),
                filePane(.middle, path: "/middle.csv", seed: 0x22, byteSize: 10),
                filePane(.right, path: "/right.csv", seed: 0x33, byteSize: 10)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        XCTAssertNoThrow(try ThreePaneTableNewPlan.plan(request: accepted, limits: limits))
        let rejected = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11, byteSize: 11),
                filePane(.middle, path: "/middle.csv", seed: 0x22, byteSize: 10),
                filePane(.right, path: "/right.csv", seed: 0x33, byteSize: 10)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.sourceTooLarge(pane: .left, maximumBytes: 10), request: rejected, limits: limits)
    }

    func testCombinedSourcesBoundaryAcceptMaxRejectOver() throws {
        let acceptedLimits = ThreePaneTableNewLimits(maximumSourceBytes: 16, maximumCombinedSourceBytes: 30)
        let accepted = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11, byteSize: 10),
                filePane(.middle, path: "/middle.csv", seed: 0x22, byteSize: 10),
                filePane(.right, path: "/right.csv", seed: 0x33, byteSize: 10)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        XCTAssertNoThrow(try ThreePaneTableNewPlan.plan(request: accepted, limits: acceptedLimits))
        let rejectedLimits = ThreePaneTableNewLimits(maximumSourceBytes: 16, maximumCombinedSourceBytes: 29)
        assertPlanError(.combinedSourcesTooLarge(maximumBytes: 29), request: accepted, limits: rejectedLimits)
    }

    func testInvalidDigestByteCountAndAllZeroRejected() {
        let short = ThreePaneTableNewFileIdentity(canonicalPath: "/left.csv", byteSize: 10, contentSHA256: Array(repeating: 0x01, count: 16))
        let shortRequest = ThreePaneTableNewRequest(
            panes: [
                ThreePaneTableNewRequestPane(pane: .left, source: .file(short)),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.invalidDigest(pane: .left, actualByteCount: 16), request: shortRequest)
        let zeros = ThreePaneTableNewFileIdentity(canonicalPath: "/left.csv", byteSize: 10, contentSHA256: Array(repeating: 0, count: 32))
        let zerosRequest = ThreePaneTableNewRequest(
            panes: [
                ThreePaneTableNewRequestPane(pane: .left, source: .file(zeros)),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.invalidDigest(pane: .left, actualByteCount: 32), request: zerosRequest)
    }

    func testDuplicateRevisionRejected() {
        let request = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                filePane(.middle, path: "/middle.csv", seed: 0x11),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        XCTAssertThrowsError(try ThreePaneTableNewPlan.plan(request: request)) { error in
            guard case .duplicateRevision = error as? ThreePaneTableNewError else {
                return XCTFail("Expected duplicateRevision got \(error)")
            }
        }
    }

    func testDelimiterEmptyTooLargeInvalidBytesRejected() {
        let empty = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: []))
        assertPlanError(.delimiterEmpty, request: empty)
        let tooLargeLimits = ThreePaneTableNewLimits(maximumDelimiterBytes: 2)
        let tooLarge = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: [0x2C, 0x3B, 0x7C]))
        assertPlanError(.delimiterTooLarge(maximumBytes: 2), request: tooLarge, limits: tooLargeLimits)
        for byte in [0x00, 0x0A, 0x0D] {
            let bad = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: [UInt8(byte)]))
            assertPlanError(.invalidDelimiterByte(value: byte), request: bad)
        }
    }

    func testDelimiterByteBoundaryAcceptMaxRejectOver() throws {
        let limits = ThreePaneTableNewLimits(maximumDelimiterBytes: 2)
        let accepted = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: [0x2C, 0x3B]))
        let acceptedPlan = try ThreePaneTableNewPlan.plan(request: accepted, limits: limits)
        XCTAssertEqual(acceptedPlan.receipt.delimiterByteCount, 2)
        let rejected = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: [0x2C, 0x3B, 0x7C]))
        assertPlanError(.delimiterTooLarge(maximumBytes: 2), request: rejected, limits: limits)
    }

    func testQuoteValidation() throws {
        let nilQuote = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            quote: nil,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        XCTAssertNoThrow(try ThreePaneTableNewPlan.plan(request: nilQuote))
        XCTAssertNil(try ThreePaneTableNewPlan.plan(request: nilQuote).quote)
        let matches = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            quote: ",",
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.quoteMatchesDelimiter, request: matches)
        for bad in ["\n", "\r", "\0"] {
            let request = ThreePaneTableNewRequest(
                panes: threeFileRequest().panes,
                delimiter: .comma,
                quote: Character(bad),
                declaredRowCount: 1,
                declaredCellCount: 1
            )
            assertPlanError(.invalidQuote, request: request)
        }
        // Single-Character multi-scalar quotes (e.g. base + combining mark) are
        // one Character but not one Unicode scalar, so they stay invalid.
        let multiScalarQuote = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            quote: Character("e\u{301}"),
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.invalidQuote, request: multiScalarQuote)
    }

    func testDelimiterRawBytesAcceptBeyondForbiddenTrio() throws {
        // Raw-bytes intent: any byte except 0x00/0x0A/0x0D plans, including
        // multi-byte UTF-8 and non-UTF-8 sequences. Single-char UTF-8 still gets
        // the authoritative parser probe; others probe via comma fallback.
        let multiByte = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: [0xC2, 0xA6]))
        XCTAssertNoThrow(try ThreePaneTableNewPlan.plan(request: multiByte))
        let nonUTF8 = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: [0xFF]))
        XCTAssertNoThrow(try ThreePaneTableNewPlan.plan(request: nonUTF8))
    }

    func testAllowsNewlinesAndHeaderBindingDriftReceipt() throws {
        let baseline = try ThreePaneTableNewPlan.plan(request: threeFileRequest()).receipt.identifier
        let noNewlines = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            quote: "\"",
            allowsNewlinesInQuotedCells: false,
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        XCTAssertNotEqual(try ThreePaneTableNewPlan.plan(request: noNewlines).receipt.identifier, baseline)
        let hidden = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            headerVisibility: .hidden,
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        XCTAssertNotEqual(try ThreePaneTableNewPlan.plan(request: hidden).receipt.identifier, baseline)
        let firstRecord = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            headerLabels: .firstRecord,
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        XCTAssertNotEqual(try ThreePaneTableNewPlan.plan(request: firstRecord).receipt.identifier, baseline)
        let stacked = threeFileRequest(orientation: .stacked)
        XCTAssertNotEqual(try ThreePaneTableNewPlan.plan(request: stacked).receipt.identifier, baseline)
        let quoted = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            quote: "'",
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        XCTAssertNotEqual(try ThreePaneTableNewPlan.plan(request: quoted).receipt.identifier, baseline)
        XCTAssertTrue(try ThreePaneTableNewPlan.plan(request: quoted).receipt.identifier.contains("quote:39"))
        let selected = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            selection: .column(3),
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        XCTAssertNotEqual(try ThreePaneTableNewPlan.plan(request: selected).receipt.identifier, baseline)
        XCTAssertTrue(try ThreePaneTableNewPlan.plan(request: selected).receipt.identifier.contains("selection:column3"))
        let piped = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: [0x7C]))
        XCTAssertNotEqual(try ThreePaneTableNewPlan.plan(request: piped).receipt.identifier, baseline)
        XCTAssertTrue(try ThreePaneTableNewPlan.plan(request: piped).receipt.identifier.contains("delimiter:7c"))
    }

    func testSelectionValidation() throws {
        let column = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            selection: .column(3),
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        XCTAssertNoThrow(try ThreePaneTableNewPlan.plan(request: column))
        let columnOverflow = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            selection: .column(20),
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        assertPlanError(.selectionOutOfBounds, request: columnOverflow)
        let negative = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            selection: .column(-1),
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        assertPlanError(.selectionOutOfBounds, request: negative)
        let cells = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            selection: .cells(
                anchor: TableWorkspaceCellAddress(rowIndex: 1, columnIndex: 2),
                focus: TableWorkspaceCellAddress(rowIndex: 3, columnIndex: 4)
            ),
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        XCTAssertNoThrow(try ThreePaneTableNewPlan.plan(request: cells))
        let cellsOverflow = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            selection: .cells(
                anchor: TableWorkspaceCellAddress(rowIndex: 1, columnIndex: 2),
                focus: TableWorkspaceCellAddress(rowIndex: 10, columnIndex: 2)
            ),
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        assertPlanError(.selectionOutOfBounds, request: cellsOverflow)
        let columnNoCells = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            selection: .column(0),
            declaredRowCount: 5,
            declaredCellCount: 0
        )
        assertPlanError(.selectionOutOfBounds, request: columnNoCells)
    }

    func testInvalidLimitEveryKindRejected() {
        let cases: [(ThreePaneTableNewLimits, ThreePaneTableNewLimit, Int)] = [
            (ThreePaneTableNewLimits(maximumSources: 0), .sources, 0),
            (ThreePaneTableNewLimits(maximumSources: 1), .sources, 1),
            (ThreePaneTableNewLimits(maximumSources: 4), .sources, 4),
            (ThreePaneTableNewLimits(maximumSourceBytes: 0), .sourceBytes, 0),
            (ThreePaneTableNewLimits(maximumSourceBytes: ThreePaneTableNewLimits.hardMaximumSourceBytes + 1), .sourceBytes, ThreePaneTableNewLimits.hardMaximumSourceBytes + 1),
            (ThreePaneTableNewLimits(maximumCombinedSourceBytes: 0), .combinedSourceBytes, 0),
            (ThreePaneTableNewLimits(maximumCombinedSourceBytes: ThreePaneTableNewLimits.hardMaximumCombinedSourceBytes + 1), .combinedSourceBytes, ThreePaneTableNewLimits.hardMaximumCombinedSourceBytes + 1),
            (ThreePaneTableNewLimits(maximumPathUTF8Bytes: 0), .pathBytes, 0),
            (ThreePaneTableNewLimits(maximumPathUTF8Bytes: ThreePaneTableNewLimits.hardMaximumPathUTF8Bytes + 1), .pathBytes, ThreePaneTableNewLimits.hardMaximumPathUTF8Bytes + 1),
            (ThreePaneTableNewLimits(maximumDelimiterBytes: 0), .delimiterBytes, 0),
            (ThreePaneTableNewLimits(maximumRowCount: 0), .rowCount, 0),
            (ThreePaneTableNewLimits(maximumCellCount: 0), .cellCount, 0),
            (ThreePaneTableNewLimits(maximumCellCount: ThreePaneTableNewLimits.hardMaximumCellCount + 1), .cellCount, ThreePaneTableNewLimits.hardMaximumCellCount + 1),
            (ThreePaneTableNewLimits(maximumWorkUnits: 0), .workUnits, 0),
            (ThreePaneTableNewLimits(maximumWorkUnits: ThreePaneTableNewLimits.hardMaximumWorkUnits + 1), .workUnits, ThreePaneTableNewLimits.hardMaximumWorkUnits + 1),
            (ThreePaneTableNewLimits(cancellationCheckInterval: 0), .cancellationCheckInterval, 0),
            (ThreePaneTableNewLimits(cancellationCheckInterval: ThreePaneTableNewLimits.hardMaximumCancellationCheckInterval + 1), .cancellationCheckInterval, ThreePaneTableNewLimits.hardMaximumCancellationCheckInterval + 1)
        ]
        for (limits, kind, value) in cases {
            XCTAssertThrowsError(try limits.validate()) { error in
                XCTAssertEqual(error as? ThreePaneTableNewError, .invalidLimit(kind, value: value))
            }
        }
        XCTAssertThrowsError(try ThreePaneTableNewLimits(maximumRowCount: ThreePaneTableNewLimits.hardMaximumRowCount + 1).validate()) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, .invalidLimit(.rowCount, value: ThreePaneTableNewLimits.hardMaximumRowCount + 1))
        }
        XCTAssertThrowsError(try ThreePaneTableNewLimits(maximumDelimiterBytes: ThreePaneTableNewLimits.hardMaximumDelimiterBytes + 1).validate()) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, .invalidLimit(.delimiterBytes, value: ThreePaneTableNewLimits.hardMaximumDelimiterBytes + 1))
        }
    }

    func testInvalidLimitCombinedLessThanSourceRejected() {
        let limits = ThreePaneTableNewLimits(maximumSourceBytes: 100, maximumCombinedSourceBytes: 50)
        XCTAssertThrowsError(try limits.validate()) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, .invalidLimit(.combinedSourceBytes, value: 50))
        }
    }

    func testLimitsBeforeMeterInvalidLimitsBeatCancellation() {
        let limits = ThreePaneTableNewLimits(cancellationCheckInterval: 0)
        let request = threeFileRequest()
        let check: ThreePaneTableNewPlan.CancellationCheck = { throw CancellationError() }
        XCTAssertThrowsError(try ThreePaneTableNewPlan.plan(request: request, limits: limits, cancellationCheck: check)) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, .invalidLimit(.cancellationCheckInterval, value: 0))
        }
    }

    func testInvalidLimitSourcesZeroAndOneRejectPlan() {
        for value in [0, 1] {
            let limits = ThreePaneTableNewLimits(maximumSources: value)
            XCTAssertThrowsError(try ThreePaneTableNewPlan.plan(request: threeFileRequest(), limits: limits)) { error in
                XCTAssertEqual(error as? ThreePaneTableNewError, .invalidLimit(.sources, value: value))
            }
            XCTAssertThrowsError(try limits.validate()) { error in
                XCTAssertEqual(error as? ThreePaneTableNewError, .invalidLimit(.sources, value: value))
            }
        }
    }

    func testThreeSourcesExceedTwoSourceLimitRejected() {
        let limits = ThreePaneTableNewLimits(maximumSources: 2)
        XCTAssertNoThrow(try limits.validate())
        assertPlanError(.sourceCountExceeded(requested: 3, maximum: 2), request: threeFileRequest(), limits: limits)
    }

    func testTwoSourcesFitTwoSourceLimit() throws {
        let limits = ThreePaneTableNewLimits(maximumSources: 2)
        let request = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                ThreePaneTableNewRequestPane(pane: .middle, source: .empty),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        let plan = try ThreePaneTableNewPlan.plan(request: request, limits: limits)
        XCTAssertEqual(plan.receipt.sourceCount, 2)
    }

    func testCancellationMapsToCancelled() {
        XCTAssertThrowsError(
            try ThreePaneTableNewPlan.plan(request: threeFileRequest(), cancellationCheck: { throw CancellationError() })
        ) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, .cancelled)
        }
    }

    func testCancellationCustomErrorPropagatesUnchanged() {
        struct ProbeAbort: Error, Equatable {}
        XCTAssertThrowsError(
            try ThreePaneTableNewPlan.plan(request: threeFileRequest(), cancellationCheck: { throw ProbeAbort() })
        ) { error in
            XCTAssertTrue(error is ProbeAbort, "custom abort must not map to .cancelled, got \(error)")
        }
    }

    func testTinyWorkBudgetThrowsWorkExceeded() {
        let limits = ThreePaneTableNewLimits(maximumWorkUnits: 1)
        XCTAssertThrowsError(try ThreePaneTableNewPlan.plan(request: threeFileRequest(), limits: limits)) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, .workExceeded(maximumWorkUnits: 1))
        }
    }

    func testReceiptDeterministicAcrossPaneOrder() throws {
        let shuffled = ThreePaneTableNewRequest(
            panes: [
                filePane(.right, path: "/right.csv", seed: 0x33),
                filePane(.left, path: "/left.csv", seed: 0x11),
                filePane(.middle, path: "/middle.csv", seed: 0x22)
            ],
            delimiter: .comma,
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        let first = try ThreePaneTableNewPlan.plan(request: threeFileRequest())
        let second = try ThreePaneTableNewPlan.plan(request: shuffled)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.receipt.identifier, second.receipt.identifier)
        XCTAssertEqual(second.panes.map { $0.pane }, [.left, .middle, .right])
    }

    func testRequireReceiptAndDatasetCAS() throws {
        let plan = try ThreePaneTableNewPlan.plan(request: threeFileRequest())
        XCTAssertNoThrow(try plan.requireReceipt(plan.receipt))
        XCTAssertNoThrow(try plan.requireCurrentDataset(revision: plan.datasetRevision))
        var forged = plan.receipt
        forged = ThreePaneTableNewReceipt(
            identifier: forged.identifier + "-forged",
            leftDigestPrefix: forged.leftDigestPrefix,
            middleDigestPrefix: forged.middleDigestPrefix,
            rightDigestPrefix: forged.rightDigestPrefix,
            declaredRowCount: forged.declaredRowCount,
            declaredCellCount: forged.declaredCellCount,
            delimiterByteCount: forged.delimiterByteCount,
            orientation: forged.orientation,
            headerVisibility: forged.headerVisibility,
            headerLabels: forged.headerLabels,
            allowsNewlinesInQuotedCells: forged.allowsNewlinesInQuotedCells,
            datasetRevision: forged.datasetRevision,
            sourceCount: forged.sourceCount
        )
        XCTAssertThrowsError(try plan.requireReceipt(forged)) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, .receiptMismatch)
        }
        XCTAssertThrowsError(try plan.requireCurrentDataset(revision: plan.datasetRevision &+ 1)) { error in
            XCTAssertEqual(error as? ThreePaneTableNewError, .staleDatasetRevision(expected: plan.datasetRevision, actual: plan.datasetRevision &+ 1))
        }
    }

    func testIdentifierBindsAllNineLimitsAndDrifts() throws {
        func limitTokens(_ identifier: String) -> [String]? {
            let parts = identifier.components(separatedBy: "limits:")
            guard parts.count == 2 else { return nil }
            let section = parts[1].components(separatedBy: " ").first ?? ""
            guard !section.isEmpty else { return nil }
            return section.components(separatedBy: "/")
        }
        let baseline = try ThreePaneTableNewPlan.plan(request: threeFileRequest())
        guard let tokens = limitTokens(baseline.receipt.identifier) else {
            XCTFail("identifier missing limits section: \(baseline.receipt.identifier)")
            return
        }
        XCTAssertEqual(tokens.count, ThreePaneTableNewLimit.allCases.count)
        let defaults = ThreePaneTableNewLimits.default
        let expected = [
            "\(defaults.maximumSources)",
            "\(defaults.maximumSourceBytes)",
            "\(defaults.maximumCombinedSourceBytes)",
            "\(defaults.maximumPathUTF8Bytes)",
            "\(defaults.maximumDelimiterBytes)",
            "\(defaults.maximumRowCount)",
            "\(defaults.maximumCellCount)",
            "\(defaults.maximumWorkUnits)",
            "\(defaults.cancellationCheckInterval)"
        ]
        XCTAssertEqual(tokens, expected)
        let variants: [(ThreePaneTableNewLimits, Int)] = [
            (ThreePaneTableNewLimits(maximumSourceBytes: 64 * 1024 * 1024 + 1), 1),
            (ThreePaneTableNewLimits(maximumCombinedSourceBytes: 192 * 1024 * 1024 + 1), 2),
            (ThreePaneTableNewLimits(maximumPathUTF8Bytes: 4 * 1024 + 1), 3),
            (ThreePaneTableNewLimits(maximumDelimiterBytes: 5), 4),
            (ThreePaneTableNewLimits(maximumRowCount: 1_048_577), 5),
            (ThreePaneTableNewLimits(maximumCellCount: 1_048_577), 6),
            (ThreePaneTableNewLimits(maximumWorkUnits: 16 * 1024 * 1024 + 1), 7),
            (ThreePaneTableNewLimits(cancellationCheckInterval: 1_025), 8)
        ]
        for (limits, changedIndex) in variants {
            let other = try ThreePaneTableNewPlan.plan(request: threeFileRequest(), limits: limits).receipt.identifier
            XCTAssertNotEqual(other, baseline.receipt.identifier)
            guard let otherTokens = limitTokens(other) else {
                XCTFail("identifier missing limits section: \(other)")
                continue
            }
            XCTAssertEqual(otherTokens.count, ThreePaneTableNewLimit.allCases.count)
            for index in 0..<tokens.count {
                if index == changedIndex {
                    XCTAssertNotEqual(otherTokens[index], tokens[index], "limit index \(index) should drift")
                } else {
                    XCTAssertEqual(otherTokens[index], tokens[index], "limit index \(index) should stay")
                }
            }
        }
        let twoSource = ThreePaneTableNewRequest(
            panes: [
                filePane(.left, path: "/left.csv", seed: 0x11),
                ThreePaneTableNewRequestPane(pane: .middle, source: .empty),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        let twoSourceBaseline = try ThreePaneTableNewPlan.plan(request: twoSource).receipt.identifier
        let twoSourceNarrowed = try ThreePaneTableNewPlan.plan(
            request: twoSource,
            limits: ThreePaneTableNewLimits(maximumSources: 2)
        ).receipt.identifier
        XCTAssertNotEqual(twoSourceNarrowed, twoSourceBaseline)
        guard let twoSourceBaselineTokens = limitTokens(twoSourceBaseline),
              let twoSourceNarrowedTokens = limitTokens(twoSourceNarrowed) else {
            XCTFail("identifier missing limits section: \(twoSourceBaseline) / \(twoSourceNarrowed)")
            return
        }
        XCTAssertEqual(twoSourceBaselineTokens.count, ThreePaneTableNewLimit.allCases.count)
        XCTAssertEqual(twoSourceNarrowedTokens.count, ThreePaneTableNewLimit.allCases.count)
        for index in 0..<twoSourceBaselineTokens.count {
            if index == 0 {
                XCTAssertNotEqual(twoSourceNarrowedTokens[index], twoSourceBaselineTokens[index], "limit index 0 should drift")
            } else {
                XCTAssertEqual(twoSourceNarrowedTokens[index], twoSourceBaselineTokens[index], "limit index \(index) should stay")
            }
        }
    }

    func testDescriptionsAndMirrorsRedactPathsAndDigests() throws {
        let secretPath = "/super/secret/path-left.csv"
        let secretBytes = digest(0xAB)
        let secretFullHex = fullHex(secretBytes)
        let secretIdentity = ThreePaneTableNewFileIdentity(canonicalPath: secretPath, byteSize: 100, contentSHA256: secretBytes)
        let request = ThreePaneTableNewRequest(
            panes: [
                ThreePaneTableNewRequestPane(pane: .left, source: .file(secretIdentity)),
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33)
            ],
            delimiter: .comma,
            declaredRowCount: 3,
            declaredCellCount: 6
        )
        let plan = try ThreePaneTableNewPlan.plan(request: request)
        XCTAssertFalse(secretIdentity.description.contains(secretPath))
        XCTAssertFalse(secretIdentity.debugDescription.contains(secretPath))
        XCTAssertFalse(request.description.contains(secretPath))
        XCTAssertFalse(plan.description.contains(secretPath))
        XCTAssertFalse(plan.receipt.identifier.contains(secretPath))
        XCTAssertFalse(plan.receipt.description.contains(secretPath))
        XCTAssertFalse(secretIdentity.description.contains(secretFullHex))
        XCTAssertFalse(plan.receipt.identifier.contains(secretFullHex))
        XCTAssertTrue(plan.receipt.identifier.contains(secretIdentity.digestPrefix))
        for child in secretIdentity.customMirror.children {
            XCTAssertFalse(String(describing: child.value).contains(secretPath))
        }
        for child in request.customMirror.children {
            XCTAssertFalse(String(describing: child.value).contains(secretPath))
        }
        for child in plan.customMirror.children {
            XCTAssertFalse(String(describing: child.value).contains(secretPath))
        }
        for child in plan.receipt.customMirror.children {
            XCTAssertFalse(String(describing: child.value).contains(secretPath))
        }
        XCTAssertFalse(ThreePaneTableNewDelimiter(bytes: [0x2C]).description.contains(","))
        XCTAssertTrue(ThreePaneTableNewError.invalidPath(.left).debugDescription.contains("left"))
    }

    func testMissingPaneLeftLegUnreachableDuplicateFiresFirst() {
        // Third leg: missing left repeats another pane, so duplicate fires first.
        let missingLeft = ThreePaneTableNewRequest(
            panes: [
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.middle, path: "/other.csv", seed: 0x33),
                filePane(.right, path: "/right.csv", seed: 0x44)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.duplicatePane(.middle), request: missingLeft)
        let missingLeftRightDup = ThreePaneTableNewRequest(
            panes: [
                filePane(.middle, path: "/middle.csv", seed: 0x22),
                filePane(.right, path: "/right.csv", seed: 0x33),
                filePane(.right, path: "/other.csv", seed: 0x44)
            ],
            delimiter: .comma,
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        assertPlanError(.duplicatePane(.right), request: missingLeftRightDup)
    }

    func testMultiScalarQuoteRejectsSingleCharacter() {
        // e + combining acute is one Character but two scalars, still invalid.
        let composed = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            quote: Character("e\u{301}"),
            declaredRowCount: 1,
            declaredCellCount: 1
        )
        XCTAssertEqual(composed.quote?.unicodeScalars.count, 2)
        assertPlanError(.invalidQuote, request: composed)
    }

    func testMultiByteDelimiterBindsLowercaseHex() throws {
        let request = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: [0xC2, 0xA6]))
        let plan = try ThreePaneTableNewPlan.plan(request: request)
        XCTAssertEqual(plan.receipt.delimiterByteCount, 2)
        XCTAssertTrue(plan.receipt.identifier.contains("delimiter:c2a6"))
    }

    func testNonUTF8DelimiterBindsLowercaseHex() throws {
        let request = threeFileRequest(delimiter: ThreePaneTableNewDelimiter(bytes: [0xFF]))
        let plan = try ThreePaneTableNewPlan.plan(request: request)
        XCTAssertEqual(plan.receipt.delimiterByteCount, 1)
        XCTAssertTrue(plan.receipt.identifier.contains("delimiter:ff"))
    }

    func testQuoteNoneDriftsFromQuotedBaseline() throws {
        let baseline = try ThreePaneTableNewPlan.plan(request: threeFileRequest()).receipt.identifier
        XCTAssertTrue(baseline.contains("quote:34"))
        let none = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            quote: nil,
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        let noneID = try ThreePaneTableNewPlan.plan(request: none).receipt.identifier
        XCTAssertTrue(noneID.contains("quote:none"))
        XCTAssertNotEqual(noneID, baseline)
        let single = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            quote: "'",
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        let singleID = try ThreePaneTableNewPlan.plan(request: single).receipt.identifier
        XCTAssertTrue(singleID.contains("quote:39"))
        XCTAssertNotEqual(singleID, baseline)
        XCTAssertNotEqual(singleID, noneID)
    }

    func testSelectionCellsBindsTokenAndDrifts() throws {
        let baseline = try ThreePaneTableNewPlan.plan(request: threeFileRequest()).receipt.identifier
        XCTAssertTrue(baseline.contains("selection:none"))
        let cells = ThreePaneTableNewRequest(
            panes: threeFileRequest().panes,
            delimiter: .comma,
            selection: .cells(
                anchor: TableWorkspaceCellAddress(rowIndex: 1, columnIndex: 2),
                focus: TableWorkspaceCellAddress(rowIndex: 3, columnIndex: 4)
            ),
            declaredRowCount: 10,
            declaredCellCount: 20
        )
        let cellsID = try ThreePaneTableNewPlan.plan(request: cells).receipt.identifier
        XCTAssertTrue(cellsID.contains("selection:cells1,2-3,4"))
        XCTAssertNotEqual(cellsID, baseline)
    }

    func testCancellationOnlyCancellationErrorMaps() {
        struct ProbeString: Error {}
        XCTAssertThrowsError(
            try ThreePaneTableNewPlan.plan(request: threeFileRequest(), cancellationCheck: { throw ProbeString() })
        ) { error in
            XCTAssertFalse(error is ThreePaneTableNewError, "custom error must propagate unchanged, got \(error)")
        }
        XCTAssertThrowsError(
            try ThreePaneTableNewPlan.plan(
                request: threeFileRequest(),
                cancellationCheck: { throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil) }
            )
        ) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSCocoaErrorDomain)
            XCTAssertEqual(nsError.code, NSUserCancelledError)
            XCTAssertNotEqual(error as? ThreePaneTableNewError, .cancelled)
        }
    }
}
