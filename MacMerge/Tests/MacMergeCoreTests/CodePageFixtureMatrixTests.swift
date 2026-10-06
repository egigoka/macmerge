import Foundation
import MacMergeCore
import XCTest

final class CodePageFixtureMatrixTests: XCTestCase {
    private typealias Matrix = CodePageFixtureMatrix

    private func makeReference(tag: UInt8, revision: UInt64) -> Matrix.FixtureReference {
        let uuid = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, tag))
        return Matrix.FixtureReference(identity: uuid, revision: revision)
    }

    private func makeInput(
        codePage: Matrix.CodePage,
        tag: UInt8,
        revision: UInt64 = 1,
        editedText: String = "Hello 123",
        oraclePresent: Bool = true,
        requiresVerified: Bool = false,
        detection: Matrix.AutomaticDetection? = nil,
        hasByteOrderMark: Bool = false
    ) -> Matrix.FixtureInput {
        Matrix.FixtureInput(
            reference: makeReference(tag: tag, revision: revision),
            codePage: codePage,
            sourceBytes: Data("Hello 123".utf8),
            hasByteOrderMark: hasByteOrderMark,
            automaticDetection: detection ?? .selected(codePage),
            explicitSelection: codePage,
            editedText: editedText,
            oraclePresent: oraclePresent,
            requiresVerified: requiresVerified
        )
    }

    private func assertThrows(
        _ expected: Matrix.MatrixError,
        _ body: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? Matrix.MatrixError, expected, file: file, line: line)
        }
    }

    func testPlanEmptyInputsProducesEmptyPlan() throws {
        let plan = try Matrix.plan([])
        XCTAssertEqual(plan.inputs.count, 0)
        XCTAssertEqual(plan.stagePlans.count, 0)
        XCTAssertEqual(plan.receipt.fixtureCount, 0)
        XCTAssertEqual(plan.receipt.stageCount, 0)
        XCTAssertEqual(plan.receipt.verifiedCount, 0)
    }

    func testPlanSingleFixtureExpandsToAllStagesInOrder() throws {
        let plan = try Matrix.plan([makeInput(codePage: .cp1252, tag: 1)])
        XCTAssertEqual(plan.stagePlans.count, Matrix.Stage.allCases.count)
        XCTAssertEqual(plan.stagePlans.map(\.stage), Matrix.Stage.allCases)
        XCTAssertEqual(plan.stagePlans.map(\.ordinal), [0, 1, 2, 3, 4, 5])
        XCTAssertTrue(plan.stagePlans.allSatisfy { $0.codePage == .cp1252 })
    }

    func testPlanSortsFixturesByCodePage() throws {
        let high = makeInput(codePage: .cp1252, tag: 2)
        let low = makeInput(codePage: .cp1250, tag: 1)
        let plan = try Matrix.plan([high, low])
        XCTAssertEqual(plan.inputs.map(\.codePage), [.cp1250, .cp1252])
        XCTAssertEqual(plan.stagePlans.first?.codePage, .cp1250)
    }

    func testPlanStageCountMatchesInputCount() throws {
        let inputs = [
            makeInput(codePage: .cp1250, tag: 1),
            makeInput(codePage: .cp1251, tag: 2),
            makeInput(codePage: .cp1252, tag: 3)
        ]
        let plan = try Matrix.plan(inputs)
        XCTAssertEqual(plan.stagePlans.count, inputs.count * Matrix.Stage.allCases.count)
        XCTAssertEqual(plan.receipt.stageCount, plan.stagePlans.count)
        XCTAssertEqual(plan.receipt.fixtureCount, inputs.count)
    }

    func testPlanReceiptCountsVerified() throws {
        let verified = makeInput(codePage: .cp1252, tag: 1, oraclePresent: false)
        let unverified = makeInput(codePage: .cp1255, tag: 2, oraclePresent: false)
        let plan = try Matrix.plan([verified, unverified])
        XCTAssertEqual(plan.receipt.verifiedCount, 1)
    }

    func testIsVerifiedGatesUnverifiedCP1255() {
        XCTAssertFalse(Matrix.isVerified(.cp1255, oraclePresent: false))
        XCTAssertTrue(Matrix.isVerified(.cp1255, oraclePresent: true))
        XCTAssertTrue(Matrix.isVerified(.cp1252, oraclePresent: false))
        XCTAssertTrue(Matrix.isVerified(.cp932, oraclePresent: false))
    }

    func testVerifiedCodePagesFiltersUnverified() {
        let inputs = [
            makeInput(codePage: .cp1252, tag: 1, oraclePresent: false),
            makeInput(codePage: .cp1255, tag: 2, oraclePresent: false),
            makeInput(codePage: .cp1255, tag: 3, oraclePresent: true)
        ]
        XCTAssertEqual(Matrix.verifiedCodePages(from: inputs), [.cp1252, .cp1255])
    }

    func testPlanRequiresVerifiedRejectsUnverifiedCP1255() {
        let input = makeInput(codePage: .cp1255, tag: 1, oraclePresent: false, requiresVerified: true)
        assertThrows(.unverifiedCodePage(.cp1255)) {
            _ = try Matrix.plan([input])
        }
    }

    func testPlanAllowsUnverifiedWhenNotRequiredButMarksReport() throws {
        let input = makeInput(codePage: .cp1255, tag: 1, oraclePresent: false)
        let plan = try Matrix.plan([input])
        let report = try Matrix.run(plan, with: [input])
        XCTAssertEqual(report.fixtures.count, 1)
        XCTAssertFalse(report.fixtures[0].isVerified)
    }

    func testPlanRejectsByteOrderMark() {
        let input = makeInput(codePage: .cp1252, tag: 1, hasByteOrderMark: true)
        assertThrows(.bomNotPermitted(.cp1252)) {
            _ = try Matrix.plan([input])
        }
    }

    func testPlanRejectsExplicitSelectionMismatch() {
        let base = makeInput(codePage: .cp1252, tag: 1)
        let mismatched = Matrix.FixtureInput(
            reference: base.reference,
            codePage: base.codePage,
            sourceBytes: base.sourceBytes,
            hasByteOrderMark: false,
            automaticDetection: .selected(.cp1252),
            explicitSelection: .cp1251,
            editedText: base.editedText,
            oraclePresent: true,
            requiresVerified: false
        )
        assertThrows(.explicitSelectionMismatch(.cp1252)) {
            _ = try Matrix.plan([mismatched])
        }
    }

    func testPlanRejectsAutomaticDetectionRejected() {
        let input = makeInput(codePage: .cp1252, tag: 1, detection: .rejected)
        assertThrows(.automaticDetectionInvalid(.cp1252)) {
            _ = try Matrix.plan([input])
        }
    }

    func testPlanRejectsAmbiguousOrderViolation() {
        let input = makeInput(codePage: .cp1250, tag: 1, detection: .ambiguous([.cp1252, .cp1250]))
        assertThrows(.ambiguousOrderViolation(.cp1250)) {
            _ = try Matrix.plan([input])
        }
    }

    func testPlanAcceptsCanonicalAmbiguousDetection() throws {
        let input = makeInput(
            codePage: .cp1252,
            tag: 1,
            detection: .ambiguous([.cp1250, .cp1252])
        )
        let plan = try Matrix.plan([input])
        XCTAssertEqual(plan.stagePlans.count, Matrix.Stage.allCases.count)
    }

    func testPlanRejectsUnrepresentableEditedText() {
        let input = makeInput(codePage: .cp1252, tag: 1, editedText: "Hello 🎉")
        assertThrows(.textNotRepresentable(.cp1252)) {
            _ = try Matrix.plan([input])
        }
    }

    func testPlanRejectsFixtureLimitExceeded() {
        let inputs = [
            makeInput(codePage: .cp1250, tag: 1),
            makeInput(codePage: .cp1251, tag: 2)
        ]
        let limits = Matrix.Limits(
            maximumFixtures: 1,
            maximumSourceBytes: 1024 * 1024,
            maximumTotalSourceBytes: 8 * 1024 * 1024,
            maximumEditedStringBytes: 1024 * 1024,
            maximumWorkUnits: 4 * 1024 * 1024,
            cancellationCheckInterval: 256
        )
        assertThrows(.fixtureLimitExceeded(maximum: 1)) {
            _ = try Matrix.plan(inputs, limits: limits)
        }
    }

    func testPlanRejectsInvalidLimits() {
        let limits = Matrix.Limits(
            maximumFixtures: 0,
            maximumSourceBytes: 1024 * 1024,
            maximumTotalSourceBytes: 8 * 1024 * 1024,
            maximumEditedStringBytes: 1024 * 1024,
            maximumWorkUnits: 4 * 1024 * 1024,
            cancellationCheckInterval: 256
        )
        assertThrows(.invalidLimit(.fixtures)) {
            _ = try Matrix.plan([makeInput(codePage: .cp1252, tag: 1)], limits: limits)
        }
    }

    func testSaveStageFailureSurfacesAsIncompleteReport() {
        let stages = Matrix.Stage.allCases.map { stage in
            Matrix.StageResult(stage: stage, passed: stage != .save, byteCount: 8)
        }
        let report = Matrix.FixtureReport(
            reference: makeReference(tag: 1, revision: 1),
            codePage: .cp1252,
            stageResults: stages,
            savedByteCount: 8,
            reloadedByteCount: 8,
            savedEqualsReloaded: true,
            oraclePresent: true,
            isVerified: true
        )
        XCTAssertFalse(report.isCompleteAndValid)
        XCTAssertFalse(report.stageResults.first(where: { $0.stage == .save })?.passed ?? true)
    }

    func testByteMismatchSurfacesAsIncompleteReport() {
        let stages = Matrix.Stage.allCases.map { stage in
            Matrix.StageResult(stage: stage, passed: true, byteCount: 8)
        }
        let report = Matrix.FixtureReport(
            reference: makeReference(tag: 1, revision: 1),
            codePage: .cp1252,
            stageResults: stages,
            savedByteCount: 8,
            reloadedByteCount: 9,
            savedEqualsReloaded: false,
            oraclePresent: true,
            isVerified: true
        )
        XCTAssertFalse(report.isCompleteAndValid)
    }

    func testRunHappyPathEncodeLoadSaveReloadConsistent() throws {
        let input = makeInput(codePage: .cp1252, tag: 1)
        let plan = try Matrix.plan([input])
        let report = try Matrix.run(plan, with: [input])
        XCTAssertEqual(report.fixtures.count, 1)
        let fixture = try XCTUnwrap(report.fixtures.first)
        XCTAssertEqual(fixture.stageResults.map(\.stage), Matrix.Stage.allCases)
        XCTAssertTrue(fixture.stageResults.allSatisfy(\.passed))
        XCTAssertTrue(fixture.savedEqualsReloaded)
        XCTAssertTrue(fixture.isCompleteAndValid)
        XCTAssertTrue(report.isCompleteAndValid)
    }

    func testRunSavedByteCountsMatchReloaded() throws {
        let inputs = [
            makeInput(codePage: .cp1250, tag: 1),
            makeInput(codePage: .cp1252, tag: 2)
        ]
        let plan = try Matrix.plan(inputs)
        let report = try Matrix.run(plan, with: inputs)
        for fixture in report.fixtures {
            XCTAssertEqual(fixture.savedByteCount, fixture.reloadedByteCount)
            XCTAssertGreaterThan(fixture.savedByteCount, 0)
        }
        XCTAssertTrue(report.receipt.recordsCompleteCoverage)
        XCTAssertEqual(report.receipt.fixtureCount, inputs.count)
        XCTAssertEqual(report.receipt.stageCount, plan.stagePlans.count)
    }

    func testReceiptDeterminismAcrossRepeatedPlans() throws {
        let inputs = [
            makeInput(codePage: .cp1252, tag: 2),
            makeInput(codePage: .cp1250, tag: 1)
        ]
        let first = try Matrix.plan(inputs)
        let second = try Matrix.plan(inputs)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
    }

    func testRunDeterminismAcrossRepeatedRuns() throws {
        let inputs = [makeInput(codePage: .cp1252, tag: 1)]
        let plan = try Matrix.plan(inputs)
        let first = try Matrix.run(plan, with: inputs)
        let second = try Matrix.run(plan, with: inputs)
        XCTAssertEqual(first, second)
    }

    func testPlanCancellationThrowsCancelled() {
        assertThrows(.cancelled) {
            _ = try Matrix.plan([makeInput(codePage: .cp1252, tag: 1)]) { true }
        }
    }

    func testRunCancellationThrowsCancelled() throws {
        let input = makeInput(codePage: .cp1252, tag: 1)
        let plan = try Matrix.plan([input])
        assertThrows(.cancelled) {
            _ = try Matrix.run(plan, with: [input]) { true }
        }
    }

    func testRunRejectsStaleFixtures() throws {
        let planned = makeInput(codePage: .cp1252, tag: 1, revision: 1)
        let current = makeInput(codePage: .cp1252, tag: 1, revision: 2)
        let plan = try Matrix.plan([planned])
        assertThrows(.staleFixture) {
            _ = try Matrix.run(plan, with: [current])
        }
    }

    func testRedactedDescriptionsLeakNoContents() throws {
        let input = makeInput(codePage: .cp1252, tag: 1)
        let plan = try Matrix.plan([input])
        let report = try Matrix.run(plan, with: [input])
        for text in [
            input.reference.description,
            input.description,
            plan.description,
            plan.receipt.description,
            report.description
        ] as [String] {
            XCTAssertTrue(text.contains("<redacted>"), text)
            XCTAssertFalse(text.contains("Hello 123"), text)
        }
    }
}
