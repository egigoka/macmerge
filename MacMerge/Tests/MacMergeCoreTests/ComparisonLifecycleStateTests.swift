import Foundation
import MacMergeCore
import XCTest

final class ComparisonLifecycleStateTests: XCTestCase {
    typealias State = ComparisonLifecycleState
    typealias AvailabilityReason = State.AvailabilityReason
    typealias Command = State.Command
    typealias InputBinding = State.InputBinding
    typealias Limits = State.Limits
    typealias Progress = State.Progress
    typealias StateError = State.StateError

    func testPublicCaseInventoriesOrderingAndSendability() throws {
        XCTAssertEqual(State.Side.allCases, [.left, .middle, .right])
        XCTAssertEqual(State.Side.allCases.map(\.rawValue), [0, 1, 2])
        XCTAssertEqual(State.Phase.allCases, [.empty, .oneSideLoaded, .loading, .current, .stale, .refreshing, .failed, .canceled])
        XCTAssertEqual(
            State.Phase.allCases.map(\.rawValue),
            ["empty", "oneSideLoaded", "loading", "current", "stale", "refreshing", "failed", "canceled"]
        )
        XCTAssertEqual(Progress.Stage.allCases, [.preparing, .loadingInputs, .comparing, .publishing])
        XCTAssertEqual(Progress.Stage.allCases.map(\.rawValue), [0, 1, 2, 3])
        XCTAssertEqual(State.Operation.Kind.allCases, [.initialLoad, .refresh])
        XCTAssertEqual(State.Operation.Kind.allCases.map(\.rawValue), ["initialLoad", "refresh"])
        XCTAssertEqual(
            State.FailureKind.allCases,
            [.invalidInput, .inputUnavailable, .readFailed, .comparisonFailed, .unsupported, .resourceLimit, .internalFailure]
        )
        XCTAssertEqual(
            State.FailureKind.allCases.map(\.rawValue),
            ["invalidInput", "inputUnavailable", "readFailed", "comparisonFailed", "unsupported", "resourceLimit", "internalFailure"]
        )
        XCTAssertEqual(
            State.CancellationReason.allCases,
            [.userRequested, .superseded, .sessionClosing, .resourceLimit]
        )
        XCTAssertEqual(
            State.CancellationReason.allCases.map(\.rawValue),
            ["userRequested", "superseded", "sessionClosing", "resourceLimit"]
        )
        XCTAssertEqual(
            Command.allCases,
            [.loadFirstSide, .unloadOnlySide, .beginLoading, .markStale, .beginRefreshing, .updateProgress, .complete, .fail, .cancel, .reset]
        )
        XCTAssertEqual(
            Command.allCases.map(\.rawValue),
            ["loadFirstSide", "unloadOnlySide", "beginLoading", "markStale", "beginRefreshing", "updateProgress", "complete", "fail", "cancel", "reset"]
        )
        XCTAssertEqual(
            State.Limit.allCases,
            [
                .failureCodeUTF8Bytes, .failureMessageUTF8Bytes, .progressDetailUTF8Bytes,
                .cancellationDetailUTF8Bytes, .totalMetadataUTF8Bytes, .progressUnitCount,
                .declaredWorkUnits, .transitionWorkUnits, .cancellationCheckInterval
            ]
        )
        XCTAssertEqual(
            State.Limit.allCases.map(\.rawValue),
            [
                "failureCodeUTF8Bytes", "failureMessageUTF8Bytes", "progressDetailUTF8Bytes",
                "cancellationDetailUTF8Bytes", "totalMetadataUTF8Bytes", "progressUnitCount",
                "declaredWorkUnits", "transitionWorkUnits", "cancellationCheckInterval"
            ]
        )

        let sides: [State.Side] = [.left, .middle, .right]
        let expectedSideOrdering = [
            [false, true, true],
            [false, false, true],
            [false, false, false]
        ]
        for (leftIndex, left) in sides.enumerated() {
            for (rightIndex, right) in sides.enumerated() {
                XCTAssertEqual(left < right, expectedSideOrdering[leftIndex][rightIndex])
            }
        }
        let stages: [Progress.Stage] = [.preparing, .loadingInputs, .comparing, .publishing]
        let expectedStageOrdering = [
            [false, true, true, true],
            [false, false, true, true],
            [false, false, false, true],
            [false, false, false, false]
        ]
        for (leftIndex, left) in stages.enumerated() {
            for (rightIndex, right) in stages.enumerated() {
                XCTAssertEqual(left < right, expectedStageOrdering[leftIndex][rightIndex])
            }
        }
        XCTAssertFalse(State.Phase.empty.hasActiveOperation)
        XCTAssertFalse(State.Phase.oneSideLoaded.hasActiveOperation)
        XCTAssertTrue(State.Phase.loading.hasActiveOperation)
        XCTAssertFalse(State.Phase.current.hasActiveOperation)
        XCTAssertFalse(State.Phase.stale.hasActiveOperation)
        XCTAssertTrue(State.Phase.refreshing.hasActiveOperation)
        XCTAssertFalse(State.Phase.failed.hasActiveOperation)
        XCTAssertFalse(State.Phase.canceled.hasActiveOperation)

        let state = try State(identity: comparisonIdentity(1))
        requireSendable(state)
        requireSendable(state.fingerprint)
        requireSendable(try makeInputs(identity: 2))
        requireSendable(State.StateError.invalidProgressTotal)
    }

    func testInputBindingCanonicalizesSidesAndRejectsEveryInvalidLayout() throws {
        let left = side(.left, identity: 1, generation: 11)
        let middle = side(.middle, identity: 2, generation: 12)
        let right = side(.right, identity: 3, generation: 13)
        for permutation in [[left, right], [right, left]] {
            let twoWay = try InputBinding(
                identity: inputIdentity(4),
                generation: 14,
                sides: permutation
            )
            XCTAssertEqual(twoWay.sides, [left, right])
            XCTAssertFalse(twoWay.isThreeWay)
            XCTAssertEqual(twoWay[.left], left)
            XCTAssertNil(twoWay[.middle])
            XCTAssertEqual(twoWay[.right], right)
        }
        let threeWayPermutations = [
            [left, middle, right], [left, right, middle],
            [middle, left, right], [middle, right, left],
            [right, left, middle], [right, middle, left]
        ]
        for permutation in threeWayPermutations {
            let threeWay = try InputBinding(
                identity: inputIdentity(5),
                generation: 15,
                sides: permutation
            )
            XCTAssertEqual(threeWay.sides, [left, middle, right])
            XCTAssertTrue(threeWay.isThreeWay)
            XCTAssertEqual(threeWay[.left], left)
            XCTAssertEqual(threeWay[.middle], middle)
            XCTAssertEqual(threeWay[.right], right)
        }

        assertStateError(.invalidInputSideCount(0)) {
            try InputBinding(identity: inputIdentity(6), generation: 0, sides: [])
        }
        assertStateError(.invalidInputSideCount(1)) {
            try InputBinding(identity: inputIdentity(6), generation: 0, sides: [left])
        }
        assertStateError(.invalidInputSideCount(4)) {
            try InputBinding(identity: inputIdentity(6), generation: 0, sides: [left, middle, right, left])
        }
        let invalidLayouts: [([State.SideBinding], StateError)] = [
            ([left, left], .duplicateInputSide(.left)),
            ([middle, middle], .duplicateInputSide(.middle)),
            ([right, right], .duplicateInputSide(.right)),
            ([left, middle], .invalidInputSides(hasLeft: true, hasMiddle: true, hasRight: false)),
            ([middle, left], .invalidInputSides(hasLeft: true, hasMiddle: true, hasRight: false)),
            ([middle, right], .invalidInputSides(hasLeft: false, hasMiddle: true, hasRight: true)),
            ([right, middle], .invalidInputSides(hasLeft: false, hasMiddle: true, hasRight: true)),
            ([left, left, left], .duplicateInputSide(.left)),
            ([left, left, middle], .duplicateInputSide(.left)),
            ([left, left, right], .duplicateInputSide(.left)),
            ([left, middle, left], .duplicateInputSide(.left)),
            ([left, middle, middle], .duplicateInputSide(.middle)),
            ([left, right, left], .duplicateInputSide(.left)),
            ([left, right, right], .duplicateInputSide(.right)),
            ([middle, left, left], .duplicateInputSide(.left)),
            ([middle, left, middle], .duplicateInputSide(.middle)),
            ([middle, middle, left], .duplicateInputSide(.middle)),
            ([middle, middle, middle], .duplicateInputSide(.middle)),
            ([middle, middle, right], .duplicateInputSide(.middle)),
            ([middle, right, middle], .duplicateInputSide(.middle)),
            ([middle, right, right], .duplicateInputSide(.right)),
            ([right, left, left], .duplicateInputSide(.left)),
            ([right, left, right], .duplicateInputSide(.right)),
            ([right, middle, middle], .duplicateInputSide(.middle)),
            ([right, middle, right], .duplicateInputSide(.right)),
            ([right, right, left], .duplicateInputSide(.right)),
            ([right, right, middle], .duplicateInputSide(.right)),
            ([right, right, right], .duplicateInputSide(.right))
        ]
        for (index, testCase) in invalidLayouts.enumerated() {
            assertStateError(testCase.1, "layout case \(index)") {
                try InputBinding(identity: inputIdentity(6), generation: 0, sides: testCase.0)
            }
        }
    }

    func testProgressZeroExcessCompletionAndHugeRounding() throws {
        let pending = Progress.pending
        XCTAssertEqual(pending.stage, .preparing)
        XCTAssertEqual(pending.completedUnitCount, 0)
        XCTAssertNil(pending.totalUnitCount)
        XCTAssertNil(pending.detail)
        XCTAssertNil(pending.fractionCompleted)
        XCTAssertFalse(pending.isComplete)

        let zeroOfTen = try Progress(stage: .loadingInputs, completedUnitCount: 0, totalUnitCount: 10)
        XCTAssertEqual(zeroOfTen.fractionCompleted, 0)
        XCTAssertFalse(zeroOfTen.isComplete)

        let quarter = try Progress(stage: .comparing, completedUnitCount: 1, totalUnitCount: 4)
        XCTAssertEqual(quarter.fractionCompleted, 0.25)
        XCTAssertFalse(quarter.isComplete)

        let complete = try Progress(stage: .publishing, completedUnitCount: 10, totalUnitCount: 10)
        XCTAssertEqual(complete.fractionCompleted, 1)
        XCTAssertTrue(complete.isComplete)

        let hugeTotal = Limits.hardMaximumProgressUnitCount
        let incompleteHuge = try Progress(
            stage: .comparing,
            completedUnitCount: hugeTotal - 1,
            totalUnitCount: hugeTotal
        )
        XCTAssertEqual(incompleteHuge.fractionCompleted, Double(1).nextDown)
        XCTAssertLessThan(try XCTUnwrap(incompleteHuge.fractionCompleted), 1)
        XCTAssertFalse(incompleteHuge.isComplete)

        assertStateError(.invalidProgressTotal) {
            try Progress(stage: .preparing, completedUnitCount: 0, totalUnitCount: 0)
        }
        assertStateError(.invalidProgressTotal) {
            try Progress(stage: .preparing, completedUnitCount: 2, totalUnitCount: 1)
        }
        assertStateError(.progressUnitLimitExceeded(maximum: Limits.hardMaximumProgressUnitCount)) {
            try Progress(stage: .preparing, completedUnitCount: Limits.hardMaximumProgressUnitCount + 1)
        }
        assertStateError(.progressUnitLimitExceeded(maximum: Limits.hardMaximumProgressUnitCount)) {
            try Progress(
                stage: .preparing,
                completedUnitCount: 0,
                totalUnitCount: Limits.hardMaximumProgressUnitCount + 1
            )
        }
    }

    func testProgressFailureAndCancellationNormalizeMetadataAndRejectControls() throws {
        let decomposed = "e\u{301}"
        let progress = try Progress(stage: .preparing, completedUnitCount: 0, detail: decomposed)
        let failure = try State.Failure(
            kind: .readFailed,
            code: "READ_1",
            message: decomposed,
            stage: .loadingInputs,
            side: .left,
            isRetryable: true
        )
        let cancellation = try State.Cancellation(
            reason: .userRequested,
            stage: .comparing,
            detail: decomposed
        )
        XCTAssertEqual(Array(try XCTUnwrap(progress.detail).utf8), [0xC3, 0xA9])
        XCTAssertEqual(Array(failure.message.utf8), [0xC3, 0xA9])
        XCTAssertEqual(Array(try XCTUnwrap(cancellation.detail).utf8), [0xC3, 0xA9])

        XCTAssertEqual(
            try Progress(stage: .preparing, completedUnitCount: 0, detail: "").detail,
            ""
        )
        assertStateError(.invalidFailureCode) {
            try makeFailure(code: "")
        }
        assertStateError(.invalidFailureCode) {
            try makeFailure(code: "bad code")
        }
        assertStateError(.invalidFailureCode) {
            try makeFailure(code: "é")
        }
        XCTAssertEqual(try makeFailure(code: "aZ09.-_").code, "aZ09.-_")
        let allowedFailureCodeScalars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_".unicodeScalars)
        for value in 0...127 {
            let scalar = try XCTUnwrap(UnicodeScalar(value))
            let code = String(scalar)
            if allowedFailureCodeScalars.contains(scalar) {
                XCTAssertEqual(try makeFailure(code: code).code, code, "ASCII \(value)")
            } else {
                assertStateError(.invalidFailureCode, "ASCII \(value)") {
                    try makeFailure(code: code)
                }
            }
        }
        XCTAssertEqual(
            try Progress(stage: .preparing, completedUnitCount: 0, detail: "\t\n\r").detail,
            "\t\n\r"
        )
        XCTAssertEqual(try makeFailure(message: "\t\n\r").message, "\t\n\r")
        XCTAssertEqual(
            try State.Cancellation(reason: .userRequested, stage: .preparing, detail: "\t\n\r").detail,
            "\t\n\r"
        )
        for invalidCode in ["", "bad code", "é", "BAD/CODE"] {
            assertStateError(.invalidFailureCode, "code \(invalidCode.debugDescription)") {
                try makeFailure(code: invalidCode)
            }
        }
        assertStateError(.invalidMetadataText(.failureMessage)) {
            try makeFailure(message: "")
        }
        for scalar in ["\u{0}", "\u{1F}", "\u{7F}", "\u{85}", "\u{9F}"] {
            assertStateError(.invalidMetadataText(.progressDetail), "progress scalar \(scalar.debugDescription)") {
                try Progress(stage: .preparing, completedUnitCount: 0, detail: "bad\(scalar)detail")
            }
            assertStateError(.invalidMetadataText(.failureMessage), "failure scalar \(scalar.debugDescription)") {
                try makeFailure(message: "bad\(scalar)message")
            }
            assertStateError(.invalidMetadataText(.cancellationDetail), "cancellation scalar \(scalar.debugDescription)") {
                try State.Cancellation(reason: .userRequested, stage: .preparing, detail: "bad\(scalar)detail")
            }
        }
        assertStateError(.invalidMetadataText(.cancellationDetail)) {
            try State.Cancellation(reason: .userRequested, stage: .preparing, detail: "")
        }
        let controlValues = Array(0...0x1F) + Array(0x7F...0x9F)
        for value in controlValues where value != 0x09 && value != 0x0A && value != 0x0D {
            let control = String(try XCTUnwrap(UnicodeScalar(value)))
            assertStateError(.invalidMetadataText(.progressDetail), "control U+\(String(value, radix: 16))") {
                try Progress(stage: .preparing, completedUnitCount: 0, detail: control)
            }
            assertStateError(.invalidMetadataText(.failureMessage), "control U+\(String(value, radix: 16))") {
                try makeFailure(message: control)
            }
            assertStateError(.invalidMetadataText(.cancellationDetail), "control U+\(String(value, radix: 16))") {
                try State.Cancellation(reason: .userRequested, stage: .preparing, detail: control)
            }
        }
    }

    func testStandaloneMetadataHardLimitsAcceptExactAndRejectExcess() throws {
        let exactCode = String(repeating: "A", count: Limits.hardMaximumFailureCodeUTF8Bytes)
        let exactMessage = String(repeating: "m", count: Limits.hardMaximumFailureMessageUTF8Bytes)
        let exactProgress = String(repeating: "p", count: Limits.hardMaximumProgressDetailUTF8Bytes)
        let exactCancellation = String(repeating: "c", count: Limits.hardMaximumCancellationDetailUTF8Bytes)
        XCTAssertEqual(try makeFailure(code: exactCode).code.utf8.count, exactCode.utf8.count)
        XCTAssertEqual(try makeFailure(message: exactMessage).message.utf8.count, exactMessage.utf8.count)
        XCTAssertEqual(
            try Progress(stage: .preparing, completedUnitCount: 0, detail: exactProgress).detail?.utf8.count,
            exactProgress.utf8.count
        )
        XCTAssertEqual(
            try State.Cancellation(reason: .userRequested, stage: .preparing, detail: exactCancellation).detail?.utf8.count,
            exactCancellation.utf8.count
        )

        assertStateError(.metadataTooLarge(field: .failureCode, maximumBytes: Limits.hardMaximumFailureCodeUTF8Bytes)) {
            try makeFailure(code: exactCode + "A")
        }
        assertStateError(.metadataTooLarge(field: .failureMessage, maximumBytes: Limits.hardMaximumFailureMessageUTF8Bytes)) {
            try makeFailure(message: exactMessage + "m")
        }
        assertStateError(.metadataTooLarge(field: .progressDetail, maximumBytes: Limits.hardMaximumProgressDetailUTF8Bytes)) {
            try Progress(stage: .preparing, completedUnitCount: 0, detail: exactProgress + "p")
        }
        assertStateError(.metadataTooLarge(field: .cancellationDetail, maximumBytes: Limits.hardMaximumCancellationDetailUTF8Bytes)) {
            try State.Cancellation(reason: .userRequested, stage: .preparing, detail: exactCancellation + "c")
        }
    }

    func testMetadataRejectsOversizedRawTextBeforeNormalizationForEveryField() {
        let decomposedUnit = "e\u{301}"
        let rawOversizedFailure = String(
            repeating: decomposedUnit,
            count: Limits.hardMaximumFailureMessageUTF8Bytes / decomposedUnit.utf8.count + 1
        )
        XCTAssertEqual(Limits.hardMaximumFailureMessageUTF8Bytes, 65_536)
        XCTAssertGreaterThan(rawOversizedFailure.utf8.count, 65_536)
        XCTAssertLessThan(
            rawOversizedFailure.precomposedStringWithCanonicalMapping.utf8.count,
            65_536
        )
        assertStateError(.metadataTooLarge(field: .failureMessage, maximumBytes: 65_536)) {
            try makeFailure(message: rawOversizedFailure)
        }

        let rawOversizedDetail = String(repeating: decomposedUnit, count: 5_462)
        XCTAssertEqual(rawOversizedDetail.utf8.count, 16_386)
        XCTAssertEqual(rawOversizedDetail.precomposedStringWithCanonicalMapping.utf8.count, 10_924)
        assertStateError(.metadataTooLarge(field: .progressDetail, maximumBytes: 16_384)) {
            try Progress(stage: .preparing, completedUnitCount: 0, detail: rawOversizedDetail)
        }
        assertStateError(.metadataTooLarge(field: .cancellationDetail, maximumBytes: 16_384)) {
            try State.Cancellation(
                reason: .userRequested,
                stage: .preparing,
                detail: rawOversizedDetail
            )
        }
    }

    func testPublicMetadataConstructionObservesDeterministicPreexistingCancellation() async {
        let oversizedFailure = String(
            repeating: "x",
            count: Limits.hardMaximumFailureMessageUTF8Bytes + 1
        )
        let failureTask = Task { () throws -> State.Failure in
            withUnsafeCurrentTask { $0?.cancel() }
            return try State.Failure(
                kind: .comparisonFailed,
                code: "FAIL",
                message: oversizedFailure,
                stage: .comparing
            )
        }
        do {
            _ = try await failureTask.value
            XCTFail("Canceled failure construction unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .cancelled)
        }

        let oversizedProgress = String(
            repeating: "x",
            count: Limits.hardMaximumProgressDetailUTF8Bytes + 1
        )
        let progressTask = Task { () throws -> Progress in
            withUnsafeCurrentTask { $0?.cancel() }
            return try Progress(
                stage: .preparing,
                completedUnitCount: 0,
                detail: oversizedProgress
            )
        }
        do {
            _ = try await progressTask.value
            XCTFail("Canceled progress construction unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .cancelled)
        }

        let oversizedCancellation = String(
            repeating: "x",
            count: Limits.hardMaximumCancellationDetailUTF8Bytes + 1
        )
        let cancellationTask = Task { () throws -> State.Cancellation in
            withUnsafeCurrentTask { $0?.cancel() }
            return try State.Cancellation(
                reason: .userRequested,
                stage: .preparing,
                detail: oversizedCancellation
            )
        }
        do {
            _ = try await cancellationTask.value
            XCTFail("Canceled cancellation construction unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .cancelled)
        }
    }

    func testInitialStateFingerprintAndAvailabilityProjection() throws {
        let identity = comparisonIdentity(10)
        let state = try State(identity: identity)
        XCTAssertEqual(state.identity, identity)
        XCTAssertEqual(state.generation, 0)
        XCTAssertEqual(state.limits, .default)
        XCTAssertEqual(state.phase, .empty)
        XCTAssertNil(state.loadedSide)
        XCTAssertNil(state.inputs)
        XCTAssertNil(state.operation)
        XCTAssertNil(state.result)
        XCTAssertNil(state.staleness)
        XCTAssertNil(state.failure)
        XCTAssertNil(state.cancellation)
        XCTAssertFalse(state.hasActiveOperation)
        XCTAssertFalse(state.hasCurrentResult)
        XCTAssertFalse(state.hasRetainedResult)
        XCTAssertEqual(state.fingerprint.identity, identity)
        XCTAssertEqual(state.fingerprint.generation, 0)
        XCTAssertTrue(try state.fingerprint.matches(state))
        XCTAssertNoThrow(try state.validate(state.fingerprint))

        let enabled = State.AvailabilityReason.enabled(.firstSideMayLoad)
        XCTAssertEqual(enabled.availability, .enabled)
        XCTAssertTrue(enabled.availability.isEnabled)
        XCTAssertNil(enabled.availability.disabledReason)
        let disabled = State.AvailabilityReason.disabled(.alreadyEmpty)
        XCTAssertEqual(disabled.availability, .disabled(.alreadyEmpty))
        XCTAssertFalse(disabled.availability.isEnabled)
        XCTAssertEqual(disabled.availability.disabledReason, .alreadyEmpty)
    }

    func testEveryEventReportsItsCommand() throws {
        let empty = try State(identity: comparisonIdentity(11))
        let inputs = try makeInputs(identity: 12)
        let loading = try beginLoading(empty, inputs: inputs, operationID: 13)
        let token = try XCTUnwrap(loading.operation?.token)
        let binding = side(.left, identity: 14)
        let events: [State.Event] = [
            .loadFirstSide(expected: empty.fingerprint, binding: binding),
            .unloadOnlySide(expected: empty.fingerprint, binding: binding),
            .beginLoading(expected: empty.fingerprint, inputs: inputs, operationID: operationID(15), declaredWorkUnits: 0),
            .markStale(expected: empty.fingerprint, currentInputs: inputs, reason: .optionsChanged),
            .beginRefreshing(expected: empty.fingerprint, operationID: operationID(16), declaredWorkUnits: 0),
            .updateProgress(expected: loading.fingerprint, operation: token, progress: .pending),
            .complete(expected: loading.fingerprint, operation: token, resultID: resultID(17)),
            .fail(expected: loading.fingerprint, operation: token, failure: try makeFailure()),
            .cancel(
                expected: loading.fingerprint,
                operation: token,
                cancellation: try State.Cancellation(reason: .userRequested, stage: .preparing)
            ),
            .reset(expected: empty.fingerprint)
        ]
        XCTAssertEqual(events.map(\.command), Command.allCases)
    }

    func testEmptyAndOneSideLoadedTransitionsPreserveExactBinding() throws {
        let empty = try State(identity: comparisonIdentity(20))
        let binding = side(.right, identity: 21, generation: 22)
        let oneSide = try empty.applying(.loadFirstSide(expected: empty.fingerprint, binding: binding))
        XCTAssertEqual(oneSide.phase, .oneSideLoaded)
        XCTAssertEqual(oneSide.generation, 1)
        XCTAssertEqual(oneSide.loadedSide, binding)
        XCTAssertNil(oneSide.inputs)
        XCTAssertFalse(oneSide.hasActiveOperation)

        let restoredEmpty = try oneSide.applying(
            .unloadOnlySide(expected: oneSide.fingerprint, binding: binding)
        )
        XCTAssertEqual(restoredEmpty.phase, .empty)
        XCTAssertEqual(restoredEmpty.generation, 2)
        XCTAssertNil(restoredEmpty.loadedSide)

        let wrongBinding = side(.right, identity: 23, generation: 22)
        assertStateError(.sideBindingMismatch(expected: binding, actual: wrongBinding)) {
            try oneSide.applying(
                .unloadOnlySide(expected: oneSide.fingerprint, binding: wrongBinding)
            )
        }

        let matchingInputs = try makeInputs(
            identity: 24,
            generation: 25,
            leftIdentity: 26,
            rightIdentity: 21,
            rightGeneration: 22
        )
        let loading = try beginLoading(oneSide, inputs: matchingInputs, operationID: 27)
        XCTAssertEqual(loading.phase, .loading)
        XCTAssertNil(loading.loadedSide)
        XCTAssertEqual(loading.inputs, matchingInputs)

        let missingInputs = try makeInputs(identity: 28)
        assertStateError(.sideBindingMismatch(expected: binding, actual: missingInputs[.right])) {
            try beginLoading(oneSide, inputs: missingInputs, operationID: 29)
        }

        let changedGenerationInputs = try makeInputs(
            identity: 24,
            generation: 25,
            leftIdentity: 26,
            rightIdentity: 21,
            rightGeneration: 23
        )
        assertStateError(.sideBindingMismatch(expected: binding, actual: changedGenerationInputs[.right])) {
            try beginLoading(oneSide, inputs: changedGenerationInputs, operationID: 30)
        }

        let middleBinding = side(.middle, identity: 31, generation: 32)
        let middleLoaded = try empty.applying(
            .loadFirstSide(expected: empty.fingerprint, binding: middleBinding)
        )
        let threeWayInputs = try makeInputs(
            identity: 33,
            middleIdentity: 31,
            middleGeneration: 32
        )
        let middleLoading = try beginLoading(
            middleLoaded,
            inputs: threeWayInputs,
            operationID: 34
        )
        XCTAssertEqual(middleLoading.phase, .loading)
        XCTAssertNil(middleLoading.loadedSide)
        XCTAssertEqual(middleLoading.inputs, threeWayInputs)
        XCTAssertEqual(middleLoading.operation?.token.inputs[.middle], middleBinding)

        let twoWayInputs = try makeInputs(identity: 33)
        XCTAssertNil(twoWayInputs[.middle])
        assertStateError(.sideBindingMismatch(expected: middleBinding, actual: nil)) {
            try beginLoading(middleLoaded, inputs: twoWayInputs, operationID: 34)
        }
    }

    func testInitialLoadProgressAndCompletionHappyPath() throws {
        let empty = try State(identity: comparisonIdentity(30))
        let inputs = try makeInputs(identity: 31, generation: 32)
        let initialProgress = try Progress(
            stage: .loadingInputs,
            completedUnitCount: 1,
            totalUnitCount: 4,
            detail: "Reading"
        )
        let loading = try beginLoading(
            empty,
            inputs: inputs,
            operationID: 33,
            declaredWorkUnits: 34,
            progress: initialProgress
        )
        let operation = try XCTUnwrap(loading.operation)
        XCTAssertEqual(loading.phase, .loading)
        XCTAssertTrue(loading.hasActiveOperation)
        XCTAssertEqual(operation.kind, .initialLoad)
        XCTAssertEqual(operation.declaredWorkUnits, 34)
        XCTAssertEqual(operation.progress, initialProgress)
        XCTAssertEqual(operation.token.comparisonIdentity, empty.identity)
        XCTAssertEqual(operation.token.operationID, operationID(33))
        XCTAssertEqual(operation.token.startedAtGeneration, 1)
        XCTAssertEqual(operation.token.inputs, inputs)

        let laterProgress = try Progress(
            stage: .comparing,
            completedUnitCount: 3,
            totalUnitCount: 4,
            detail: "Comparing"
        )
        let progressed = try loading.applying(
            .updateProgress(
                expected: loading.fingerprint,
                operation: operation.token,
                progress: laterProgress
            )
        )
        XCTAssertEqual(progressed.phase, .loading)
        XCTAssertEqual(progressed.generation, 2)
        XCTAssertEqual(progressed.operation?.progress, laterProgress)
        XCTAssertEqual(progressed.operation?.token, operation.token)

        let current = try progressed.applying(
            .complete(
                expected: progressed.fingerprint,
                operation: operation.token,
                resultID: resultID(35)
            )
        )
        let result = try XCTUnwrap(current.result)
        XCTAssertEqual(current.phase, .current)
        XCTAssertEqual(current.generation, 3)
        XCTAssertFalse(current.hasActiveOperation)
        XCTAssertTrue(current.hasCurrentResult)
        XCTAssertTrue(current.hasRetainedResult)
        XCTAssertEqual(current.inputs, inputs)
        XCTAssertEqual(result.identity, resultID(35))
        XCTAssertEqual(result.inputs, inputs)
        XCTAssertEqual(result.operation, operation.token)
        XCTAssertEqual(result.publishedAtGeneration, 3)
    }

    func testInitialFailureAndCancellationCanRetryOnlyExactInputs() throws {
        let inputs = try makeInputs(identity: 40)
        let empty = try State(identity: comparisonIdentity(41))
        let loading = try beginLoading(empty, inputs: inputs, operationID: 42)
        let token = try XCTUnwrap(loading.operation?.token)
        let failure = try makeFailure(stage: .preparing, isRetryable: true)
        let failed = try loading.applying(
            .fail(expected: loading.fingerprint, operation: token, failure: failure)
        )
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertNil(failed.operation)
        XCTAssertNil(failed.result)
        XCTAssertEqual(failed.inputs, inputs)
        XCTAssertEqual(failed.failure?.operation, token)
        XCTAssertEqual(failed.failure?.lastProgress, .pending)
        XCTAssertEqual(failed.failure?.failure, failure)
        XCTAssertEqual(failed.failure?.recordedAtGeneration, 2)

        let retry = try beginLoading(failed, inputs: inputs, operationID: 43)
        XCTAssertEqual(retry.phase, .loading)
        XCTAssertEqual(retry.operation?.kind, .initialLoad)
        XCTAssertNil(retry.failure)

        let retryWithSameOperationID = try beginLoading(failed, inputs: inputs, operationID: 42)
        XCTAssertEqual(retryWithSameOperationID.operation?.token.operationID, operationID(42))
        XCTAssertEqual(retryWithSameOperationID.operation?.token.startedAtGeneration, 3)
        XCTAssertNotEqual(retryWithSameOperationID.operation?.token, token)

        let changedInputs = try makeInputs(identity: 44)
        let mismatchedInputs = [
            changedInputs,
            try makeInputs(identity: 40, generation: 1),
            try makeInputs(identity: 40, leftIdentity: 9),
            try makeInputs(identity: 40, leftGeneration: 1),
            try makeInputs(identity: 40, middleIdentity: 8)
        ]
        for (index, candidate) in mismatchedInputs.enumerated() {
            assertStateError(.inputBindingMismatch(expected: inputs, actual: candidate), "failed retry case \(index)") {
                try beginLoading(failed, inputs: candidate, operationID: UInt8(50 + index))
            }
        }

        let secondLoading = try beginLoading(empty, inputs: inputs, operationID: 46)
        let secondToken = try XCTUnwrap(secondLoading.operation?.token)
        let cancellation = try State.Cancellation(
            reason: .superseded,
            stage: .preparing,
            detail: "New request"
        )
        let canceled = try secondLoading.applying(
            .cancel(
                expected: secondLoading.fingerprint,
                operation: secondToken,
                cancellation: cancellation
            )
        )
        XCTAssertEqual(canceled.phase, .canceled)
        XCTAssertNil(canceled.operation)
        XCTAssertNil(canceled.result)
        XCTAssertEqual(canceled.inputs, inputs)
        XCTAssertEqual(canceled.cancellation?.operation, secondToken)
        XCTAssertEqual(canceled.cancellation?.lastProgress, .pending)
        XCTAssertEqual(canceled.cancellation?.cancellation, cancellation)
        XCTAssertEqual(canceled.cancellation?.recordedAtGeneration, 2)
        let canceledRetryProgress = try Progress(
            stage: .loadingInputs,
            completedUnitCount: 2,
            totalUnitCount: 5,
            detail: "Retrying"
        )
        let canceledRetry = try beginLoading(
            canceled,
            inputs: inputs,
            operationID: 47,
            declaredWorkUnits: 48,
            progress: canceledRetryProgress
        )
        let canceledRetryOperation = try XCTUnwrap(canceledRetry.operation)
        XCTAssertEqual(canceledRetry.identity, canceled.identity)
        XCTAssertEqual(canceledRetry.generation, canceled.generation + 1)
        XCTAssertEqual(canceledRetry.limits, canceled.limits)
        XCTAssertEqual(canceledRetry.phase, .loading)
        XCTAssertNil(canceledRetry.loadedSide)
        XCTAssertEqual(canceledRetry.inputs, inputs)
        XCTAssertEqual(canceledRetryOperation.kind, .initialLoad)
        XCTAssertEqual(canceledRetryOperation.token.comparisonIdentity, canceled.identity)
        XCTAssertEqual(canceledRetryOperation.token.operationID, operationID(47))
        XCTAssertEqual(canceledRetryOperation.token.startedAtGeneration, canceled.generation + 1)
        XCTAssertEqual(canceledRetryOperation.token.inputs, inputs)
        XCTAssertEqual(canceledRetryOperation.declaredWorkUnits, 48)
        XCTAssertEqual(canceledRetryOperation.progress, canceledRetryProgress)
        XCTAssertNil(canceledRetry.result)
        XCTAssertNil(canceledRetry.staleness)
        XCTAssertNil(canceledRetry.failure)
        XCTAssertNil(canceledRetry.cancellation)
        XCTAssertTrue(canceledRetry.hasActiveOperation)
        XCTAssertFalse(canceledRetry.hasCurrentResult)
        XCTAssertFalse(canceledRetry.hasRetainedResult)
        let canceledRetryWithSameOperationID = try beginLoading(canceled, inputs: inputs, operationID: 46)
        XCTAssertEqual(canceledRetryWithSameOperationID.operation?.token.operationID, operationID(46))
        XCTAssertEqual(canceledRetryWithSameOperationID.operation?.token.startedAtGeneration, 3)
        XCTAssertNotEqual(canceledRetryWithSameOperationID.operation?.token, secondToken)
        for (index, candidate) in mismatchedInputs.enumerated() {
            assertStateError(.inputBindingMismatch(expected: inputs, actual: candidate), "canceled retry case \(index)") {
                try beginLoading(canceled, inputs: candidate, operationID: UInt8(60 + index))
            }
        }
    }

    func testRefreshCanCompleteFailAndCancelWhileRetainingCorrectResult() throws {
        let fixture = try makeCurrentFixture(comparisonIdentity: 50, inputIdentity: 51, operationID: 52, resultID: 53)
        let changedInputs = try makeInputs(identity: 54, leftIdentity: 55, rightIdentity: 3)
        let stale = try markStale(fixture.state, inputs: changedInputs, reason: .sideChanged(.left))

        let refreshing = try beginRefreshing(stale, operationID: 56, declaredWorkUnits: 57)
        let refreshOperation = try XCTUnwrap(refreshing.operation)
        XCTAssertEqual(refreshing.phase, .refreshing)
        XCTAssertEqual(refreshOperation.kind, .refresh)
        XCTAssertEqual(refreshOperation.token.inputs, changedInputs)
        XCTAssertEqual(refreshOperation.token.startedAtGeneration, stale.generation + 1)
        XCTAssertEqual(refreshing.result, fixture.result)
        XCTAssertEqual(refreshing.staleness, stale.staleness)

        let completed = try refreshing.applying(
            .complete(
                expected: refreshing.fingerprint,
                operation: refreshOperation.token,
                resultID: resultID(58)
            )
        )
        XCTAssertEqual(completed.phase, .current)
        XCTAssertEqual(completed.inputs, changedInputs)
        XCTAssertEqual(completed.result?.identity, resultID(58))
        XCTAssertEqual(completed.result?.inputs, changedInputs)
        XCTAssertEqual(completed.result?.operation, refreshOperation.token)
        XCTAssertNil(completed.staleness)

        let failingRefresh = try beginRefreshing(stale, operationID: 59)
        let failingToken = try XCTUnwrap(failingRefresh.operation?.token)
        let failure = try makeFailure(stage: .comparing, isRetryable: true)
        let failed = try failingRefresh.applying(
            .fail(expected: failingRefresh.fingerprint, operation: failingToken, failure: failure)
        )
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.result, fixture.result)
        XCTAssertEqual(failed.staleness, stale.staleness)
        XCTAssertEqual(failed.failure?.failure, failure)

        let cancelingRefresh = try beginRefreshing(stale, operationID: 60)
        let cancelingToken = try XCTUnwrap(cancelingRefresh.operation?.token)
        let cancellation = try State.Cancellation(reason: .userRequested, stage: .preparing)
        let canceled = try cancelingRefresh.applying(
            .cancel(
                expected: cancelingRefresh.fingerprint,
                operation: cancelingToken,
                cancellation: cancellation
            )
        )
        XCTAssertEqual(canceled.phase, .canceled)
        XCTAssertEqual(canceled.result, fixture.result)
        XCTAssertEqual(canceled.staleness, stale.staleness)
        XCTAssertEqual(canceled.cancellation?.cancellation, cancellation)
    }

    func testCommandAvailabilityAcrossEveryPhase() throws {
        let empty = try State(identity: comparisonIdentity(61))
        let loadedBinding = side(.left, identity: 2)
        let oneSide = try empty.applying(
            .loadFirstSide(expected: empty.fingerprint, binding: loadedBinding)
        )
        let inputs = try makeInputs(identity: 62, leftIdentity: 2)
        let loading = try beginLoading(oneSide, inputs: inputs, operationID: 63)
        let operationID = try XCTUnwrap(loading.operation?.token.operationID)
        let current = try complete(loading, resultID: 64)
        let resultID = try XCTUnwrap(current.result?.identity)
        let staleInputs = try makeInputs(identity: 65, leftIdentity: 6)
        let stale = try markStale(current, inputs: staleInputs, reason: .sideChanged(.left))
        let refreshing = try beginRefreshing(stale, operationID: 66)
        let refreshOperationID = try XCTUnwrap(refreshing.operation?.token.operationID)
        let refreshToken = try XCTUnwrap(refreshing.operation?.token)
        let failed = try refreshing.applying(
            .fail(
                expected: refreshing.fingerprint,
                operation: refreshToken,
                failure: try makeFailure(stage: .preparing, isRetryable: true)
            )
        )
        let anotherRefresh = try beginRefreshing(stale, operationID: 67)
        let anotherToken = try XCTUnwrap(anotherRefresh.operation?.token)
        let canceled = try anotherRefresh.applying(
            .cancel(
                expected: anotherRefresh.fingerprint,
                operation: anotherToken,
                cancellation: try State.Cancellation(reason: .userRequested, stage: .preparing)
            )
        )

        assertAvailability(
            empty,
            [
                .loadFirstSide: .enabled(.firstSideMayLoad),
                .unloadOnlySide: .disabled(.noOnlySideLoaded),
                .beginLoading: .enabled(.initialComparisonMayStart),
                .markStale: .disabled(.noCurrentResult),
                .beginRefreshing: .disabled(.noResultToRefresh),
                .updateProgress: .disabled(.noActiveOperation),
                .complete: .disabled(.noActiveOperation),
                .fail: .disabled(.noActiveOperation),
                .cancel: .disabled(.noActiveOperation),
                .reset: .disabled(.alreadyEmpty)
            ]
        )
        assertAvailability(
            oneSide,
            inactiveAvailability(
                beginLoading: .enabled(.initialComparisonMayStart),
                markStale: .disabled(.noCurrentResult),
                beginRefreshing: .disabled(.noResultToRefresh),
                reset: .enabled(.lifecycleMayReset),
                unload: .enabled(.onlySideMayUnload(.left))
            )
        )
        assertAvailability(loading, activeAvailability(operationID: operationID))
        assertAvailability(
            current,
            inactiveAvailability(
                beginLoading: .disabled(.initialLoadUnavailable(.current)),
                markStale: .enabled(.retainedResultMayBecomeStale(resultID)),
                beginRefreshing: .enabled(.refreshMayStart(resultID)),
                reset: .enabled(.lifecycleMayReset)
            )
        )
        assertAvailability(
            stale,
            inactiveAvailability(
                beginLoading: .disabled(.initialLoadUnavailable(.stale)),
                markStale: .enabled(.retainedResultMayBecomeStale(resultID)),
                beginRefreshing: .enabled(.refreshMayStart(resultID)),
                reset: .enabled(.lifecycleMayReset)
            )
        )
        assertAvailability(refreshing, activeAvailability(operationID: refreshOperationID))
        assertAvailability(
            failed,
            inactiveAvailability(
                beginLoading: .disabled(.initialLoadUnavailable(.failed)),
                markStale: .enabled(.retainedResultMayBecomeStale(resultID)),
                beginRefreshing: .enabled(.refreshMayStart(resultID)),
                reset: .enabled(.lifecycleMayReset)
            )
        )
        assertAvailability(
            canceled,
            inactiveAvailability(
                beginLoading: .disabled(.initialLoadUnavailable(.canceled)),
                markStale: .enabled(.retainedResultMayBecomeStale(resultID)),
                beginRefreshing: .enabled(.refreshMayStart(resultID)),
                reset: .enabled(.lifecycleMayReset)
            )
        )
    }

    func testTerminalAvailabilityCoversInitialRetryAndNonRetryableFailures() throws {
        let inputs = try makeInputs(identity: 70)
        let empty = try State(identity: comparisonIdentity(71))
        let loading = try beginLoading(empty, inputs: inputs, operationID: 72)
        let token = try XCTUnwrap(loading.operation?.token)
        let retryable = try loading.applying(
            .fail(
                expected: loading.fingerprint,
                operation: token,
                failure: try makeFailure(isRetryable: true)
            )
        )
        XCTAssertEqual(
            retryable.availability(for: .beginLoading),
            .enabled(.initialComparisonMayStart)
        )
        XCTAssertEqual(retryable.availability(for: .markStale), .disabled(.noCurrentResult))
        XCTAssertEqual(retryable.availability(for: .beginRefreshing), .disabled(.noResultToRefresh))

        let nonRetryLoading = try beginLoading(empty, inputs: inputs, operationID: 73)
        let nonRetryToken = try XCTUnwrap(nonRetryLoading.operation?.token)
        let nonRetryable = try nonRetryLoading.applying(
            .fail(
                expected: nonRetryLoading.fingerprint,
                operation: nonRetryToken,
                failure: try makeFailure(kind: .unsupported, isRetryable: false)
            )
        )
        XCTAssertEqual(
            nonRetryable.availability(for: .beginLoading),
            .disabled(.failureNotRetryable(.unsupported))
        )
        assertStateError(.commandDisabled(.failureNotRetryable(.unsupported))) {
            try beginLoading(nonRetryable, inputs: inputs, operationID: 74)
        }

        let cancelLoading = try beginLoading(empty, inputs: inputs, operationID: 75)
        let cancelToken = try XCTUnwrap(cancelLoading.operation?.token)
        let canceled = try cancelLoading.applying(
            .cancel(
                expected: cancelLoading.fingerprint,
                operation: cancelToken,
                cancellation: try State.Cancellation(reason: .sessionClosing, stage: .preparing)
            )
        )
        XCTAssertEqual(canceled.availability(for: .beginLoading), .enabled(.initialComparisonMayStart))
    }

    func testFingerprintsBindFullSnapshotNotOnlyIdentityAndGeneration() throws {
        let empty = try State(identity: comparisonIdentity(80))
        let differentlyLimitedEmpty = try State(
            identity: empty.identity,
            limits: Limits(
                maximumProgressUnitCount: Limits.default.maximumProgressUnitCount - 1
            )
        )
        assertFingerprintDifference(empty, differentlyLimitedEmpty, "limits")

        let firstLoaded = try empty.applying(
            .loadFirstSide(
                expected: empty.fingerprint,
                binding: side(.left, identity: 81)
            )
        )
        let secondLoaded = try empty.applying(
            .loadFirstSide(
                expected: empty.fingerprint,
                binding: side(.left, identity: 82)
            )
        )
        assertFingerprintDifference(firstLoaded, secondLoaded, "loaded side")

        let inputs = try makeInputs(identity: 81)
        let loading = try beginLoading(empty, inputs: inputs, operationID: 82)
        XCTAssertTrue(try loading.fingerprint.matches(loading))
        let progressVariants: [(String, Progress)] = [
            (
                "progress stage",
                try Progress(stage: .loadingInputs, completedUnitCount: 0)
            ),
            (
                "progress completed count",
                try Progress(stage: .preparing, completedUnitCount: 1)
            ),
            (
                "progress total count",
                try Progress(stage: .preparing, completedUnitCount: 0, totalUnitCount: 1)
            )
        ]
        for (message, progress) in progressVariants {
            let variant = try beginLoading(
                empty,
                inputs: inputs,
                operationID: 82,
                progress: progress
            )
            assertFingerprintDifference(loading, variant, message)
        }

        let declaredLoading = try beginLoading(
            empty,
            inputs: inputs,
            operationID: 82,
            declaredWorkUnits: 1
        )
        assertFingerprintDifference(loading, declaredLoading, "declared work")

        let token = try XCTUnwrap(loading.operation?.token)
        let firstBranch = try loading.applying(
            .updateProgress(
                expected: loading.fingerprint,
                operation: token,
                progress: try Progress(stage: .preparing, completedUnitCount: 1, detail: "first")
            )
        )
        let secondBranch = try loading.applying(
            .updateProgress(
                expected: loading.fingerprint,
                operation: token,
                progress: try Progress(stage: .preparing, completedUnitCount: 1, detail: "second")
            )
        )
        XCTAssertEqual(firstBranch.identity, secondBranch.identity)
        XCTAssertEqual(firstBranch.generation, secondBranch.generation)
        XCTAssertNotEqual(firstBranch, secondBranch)
        XCTAssertNotEqual(firstBranch.fingerprint, secondBranch.fingerprint)
        XCTAssertFalse(try firstBranch.fingerprint.matches(secondBranch))
        XCTAssertFalse(try secondBranch.fingerprint.matches(firstBranch))
        assertStateError(
            .staleState(expected: firstBranch.fingerprint, actual: secondBranch.fingerprint)
        ) {
            try secondBranch.validate(firstBranch.fingerprint)
        }

        let fingerprints: Set<State.Fingerprint> = [firstBranch.fingerprint, secondBranch.fingerprint]
        XCTAssertEqual(fingerprints.count, 2)

        let firstResult = try complete(loading, resultID: 83)
        let secondResult = try complete(loading, resultID: 84)
        assertFingerprintDifference(firstResult, secondResult, "result identity")

        let currentFixture = try makeCurrentFixture(comparisonIdentity: 85, inputIdentity: 86)
        let changedInputs = try makeInputs(identity: 87, leftIdentity: 88)
        let firstStale = try markStale(
            currentFixture.state,
            inputs: changedInputs,
            reason: .sideChanged(.left)
        )
        let secondStale = try markStale(
            currentFixture.state,
            inputs: changedInputs,
            reason: .externalChange(.left)
        )
        assertFingerprintDifference(firstStale, secondStale, "staleness reason")

        let firstFailure = try loading.applying(
            .fail(
                expected: loading.fingerprint,
                operation: token,
                failure: try makeFailure(code: "FIRST")
            )
        )
        XCTAssertTrue(try firstFailure.fingerprint.matches(firstFailure))
        let secondFailure = try loading.applying(
            .fail(
                expected: loading.fingerprint,
                operation: token,
                failure: try makeFailure(code: "SECOND")
            )
        )
        assertFingerprintDifference(firstFailure, secondFailure, "failure code")
        let failureVariants: [(String, State.Failure)] = [
            ("failure kind", try makeFailure(kind: .readFailed, code: "FIRST")),
            ("failure message", try makeFailure(code: "FIRST", message: "Different failure")),
            ("failure stage", try makeFailure(code: "FIRST", stage: .loadingInputs)),
            ("failure side", try makeFailure(code: "FIRST", side: .left)),
            ("failure retryability", try makeFailure(code: "FIRST", isRetryable: true))
        ]
        for (message, failure) in failureVariants {
            let variant = try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: failure
                )
            )
            assertFingerprintDifference(firstFailure, variant, message)
        }

        let firstCancellation = try loading.applying(
            .cancel(
                expected: loading.fingerprint,
                operation: token,
                cancellation: try State.Cancellation(
                    reason: .userRequested,
                    stage: .preparing,
                    detail: "first"
                )
            )
        )
        XCTAssertTrue(try firstCancellation.fingerprint.matches(firstCancellation))
        let secondCancellation = try loading.applying(
            .cancel(
                expected: loading.fingerprint,
                operation: token,
                cancellation: try State.Cancellation(
                    reason: .userRequested,
                    stage: .preparing,
                    detail: "second"
                )
            )
        )
        assertFingerprintDifference(firstCancellation, secondCancellation, "cancellation record")
        let cancellationVariants: [(String, State.Cancellation)] = [
            (
                "cancellation reason",
                try State.Cancellation(
                    reason: .superseded,
                    stage: .preparing,
                    detail: "first"
                )
            ),
            (
                "cancellation stage",
                try State.Cancellation(
                    reason: .userRequested,
                    stage: .loadingInputs,
                    detail: "first"
                )
            )
        ]
        for (message, cancellation) in cancellationVariants {
            let variant = try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: token,
                    cancellation: cancellation
                )
            )
            assertFingerprintDifference(firstCancellation, variant, message)
        }
    }

    func testGenerationOperationAndResultLineageRemainExact() throws {
        let inputs = try makeInputs(
            identity: 90,
            generation: 91,
            leftIdentity: 92,
            leftGeneration: 93,
            rightIdentity: 94,
            rightGeneration: 95
        )
        let empty = try State(identity: comparisonIdentity(96))
        let loading = try beginLoading(empty, inputs: inputs, operationID: 97)
        let token = try XCTUnwrap(loading.operation?.token)
        XCTAssertEqual(empty.generation, 0)
        XCTAssertEqual(loading.generation, 1)
        XCTAssertEqual(token.comparisonIdentity, empty.identity)
        XCTAssertEqual(token.operationID, operationID(97))
        XCTAssertEqual(token.startedAtGeneration, 1)
        XCTAssertEqual(token.inputs.identity, inputIdentity(90))
        XCTAssertEqual(token.inputs.generation, 91)
        XCTAssertEqual(token.inputs[.left]?.generation, 93)
        XCTAssertEqual(token.inputs[.right]?.generation, 95)

        let current = try complete(loading, resultID: 98)
        let result = try XCTUnwrap(current.result)
        XCTAssertEqual(current.generation, 2)
        XCTAssertEqual(result.identity, resultID(98))
        XCTAssertEqual(result.inputs, inputs)
        XCTAssertEqual(result.operation, token)
        XCTAssertEqual(result.publishedAtGeneration, 2)
        XCTAssertEqual(current.fingerprint.generation, 2)
    }

    func testEveryAcceptedCommandAdvancesGenerationExactlyOnce() throws {
        let empty = try State(identity: comparisonIdentity(99))
        let binding = side(.left, identity: 100)
        let loaded = try empty.applying(
            .loadFirstSide(expected: empty.fingerprint, binding: binding)
        )
        XCTAssertEqual(loaded.generation, empty.generation + 1)
        let unloaded = try loaded.applying(
            .unloadOnlySide(expected: loaded.fingerprint, binding: binding)
        )
        XCTAssertEqual(unloaded.generation, loaded.generation + 1)

        let inputs = try makeInputs(identity: 101)
        let loading = try beginLoading(unloaded, inputs: inputs, operationID: 102)
        XCTAssertEqual(loading.generation, unloaded.generation + 1)
        let token = try XCTUnwrap(loading.operation?.token)
        let progressed = try loading.applying(
            .updateProgress(
                expected: loading.fingerprint,
                operation: token,
                progress: try Progress(stage: .loadingInputs, completedUnitCount: 1)
            )
        )
        XCTAssertEqual(progressed.generation, loading.generation + 1)
        let current = try complete(progressed, resultID: 103)
        XCTAssertEqual(current.generation, progressed.generation + 1)
        let stale = try markStale(
            current,
            inputs: makeInputs(identity: 104, leftIdentity: 105),
            reason: .sideChanged(.left)
        )
        XCTAssertEqual(stale.generation, current.generation + 1)
        let refreshing = try beginRefreshing(stale, operationID: 106)
        XCTAssertEqual(refreshing.generation, stale.generation + 1)
        let refreshToken = try XCTUnwrap(refreshing.operation?.token)
        let failed = try refreshing.applying(
            .fail(
                expected: refreshing.fingerprint,
                operation: refreshToken,
                failure: try makeFailure(stage: .preparing, isRetryable: true)
            )
        )
        XCTAssertEqual(failed.generation, refreshing.generation + 1)
        let canceling = try beginRefreshing(failed, operationID: 107)
        XCTAssertEqual(canceling.generation, failed.generation + 1)
        let cancelToken = try XCTUnwrap(canceling.operation?.token)
        let canceled = try canceling.applying(
            .cancel(
                expected: canceling.fingerprint,
                operation: cancelToken,
                cancellation: try State.Cancellation(reason: .userRequested, stage: .preparing)
            )
        )
        XCTAssertEqual(canceled.generation, canceling.generation + 1)
        let reset = try canceled.applying(.reset(expected: canceled.fingerprint))
        XCTAssertEqual(reset.generation, canceled.generation + 1)
    }

    func testStaleFingerprintAndOperationTokensAreRejectedWithoutMutation() throws {
        let empty = try State(identity: comparisonIdentity(100))
        let inputs = try makeInputs(identity: 101)
        let loading = try beginLoading(empty, inputs: inputs, operationID: 102)
        let token = try XCTUnwrap(loading.operation?.token)
        let staleExpected = empty.fingerprint
        assertStateError(.staleState(expected: staleExpected, actual: loading.fingerprint)) {
            try loading.applying(
                .complete(expected: staleExpected, operation: token, resultID: resultID(103))
            )
        }
        XCTAssertEqual(loading.generation, 1)
        XCTAssertEqual(loading.operation?.token, token)

        let otherEmpty = try State(identity: comparisonIdentity(104))
        let otherLoading = try beginLoading(otherEmpty, inputs: inputs, operationID: 102)
        let otherToken = try XCTUnwrap(otherLoading.operation?.token)
        assertStateError(.staleOperation(expected: otherToken, actual: token)) {
            try loading.applying(
                .complete(
                    expected: loading.fingerprint,
                    operation: otherToken,
                    resultID: resultID(105)
                )
            )
        }

        let differentOperationLoading = try beginLoading(empty, inputs: inputs, operationID: 106)
        let differentOperationToken = try XCTUnwrap(differentOperationLoading.operation?.token)
        let failed = try loading.applying(
            .fail(
                expected: loading.fingerprint,
                operation: token,
                failure: try makeFailure(isRetryable: true)
            )
        )
        let differentGenerationLoading = try beginLoading(failed, inputs: inputs, operationID: 102)
        let differentGenerationToken = try XCTUnwrap(differentGenerationLoading.operation?.token)
        let differentInputsLoading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 107),
            operationID: 102
        )
        let differentInputsToken = try XCTUnwrap(differentInputsLoading.operation?.token)
        let differentInputGenerationLoading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 101, generation: 1),
            operationID: 102
        )
        let differentInputGenerationToken = try XCTUnwrap(
            differentInputGenerationLoading.operation?.token
        )
        let differentSideIdentityLoading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 101, leftIdentity: 108),
            operationID: 102
        )
        let differentSideIdentityToken = try XCTUnwrap(differentSideIdentityLoading.operation?.token)
        let differentSideGenerationLoading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 101, leftGeneration: 1),
            operationID: 102
        )
        let differentSideGenerationToken = try XCTUnwrap(
            differentSideGenerationLoading.operation?.token
        )
        let differentLayoutLoading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 101, middleIdentity: 109),
            operationID: 102
        )
        let differentLayoutToken = try XCTUnwrap(differentLayoutLoading.operation?.token)
        let staleTokens = [
            otherToken,
            differentOperationToken,
            differentGenerationToken,
            differentInputsToken,
            differentInputGenerationToken,
            differentSideIdentityToken,
            differentSideGenerationToken,
            differentLayoutToken
        ]
        XCTAssertNotEqual(otherToken.comparisonIdentity, token.comparisonIdentity)
        XCTAssertNotEqual(differentOperationToken.operationID, token.operationID)
        XCTAssertNotEqual(differentGenerationToken.startedAtGeneration, token.startedAtGeneration)
        XCTAssertNotEqual(differentInputsToken.inputs.identity, token.inputs.identity)
        XCTAssertNotEqual(differentInputGenerationToken.inputs.generation, token.inputs.generation)
        XCTAssertNotEqual(differentSideIdentityToken.inputs[.left]?.identity, token.inputs[.left]?.identity)
        XCTAssertNotEqual(differentSideGenerationToken.inputs[.left]?.generation, token.inputs[.left]?.generation)
        XCTAssertNotEqual(differentLayoutToken.inputs.isThreeWay, token.inputs.isThreeWay)

        for (tokenIndex, staleToken) in staleTokens.enumerated() {
            for command in [Command.updateProgress, .complete, .fail, .cancel] {
                assertStateError(
                    .staleOperation(expected: staleToken, actual: token),
                    "token case \(tokenIndex), command \(command)"
                ) {
                    switch command {
                    case .updateProgress:
                        return try loading.applying(
                            .updateProgress(
                                expected: loading.fingerprint,
                                operation: staleToken,
                                progress: .pending
                            )
                        )
                    case .complete:
                        return try loading.applying(
                            .complete(
                                expected: loading.fingerprint,
                                operation: staleToken,
                                resultID: resultID(108)
                            )
                        )
                    case .fail:
                        return try loading.applying(
                            .fail(
                                expected: loading.fingerprint,
                                operation: staleToken,
                                failure: try makeFailure()
                            )
                        )
                    case .cancel:
                        return try loading.applying(
                            .cancel(
                                expected: loading.fingerprint,
                                operation: staleToken,
                                cancellation: try State.Cancellation(
                                    reason: .userRequested,
                                    stage: .preparing
                                )
                            )
                        )
                    case .loadFirstSide, .unloadOnlySide, .beginLoading, .markStale,
                        .beginRefreshing, .reset:
                        XCTFail("Unexpected command \(command)")
                        return loading
                    }
                }
            }
        }
        XCTAssertEqual(loading.generation, 1)
        XCTAssertEqual(loading.operation?.token, token)
    }

    func testProgressStageAdvanceMatrixIsLiteral() throws {
        let stages: [Progress.Stage] = [.preparing, .loadingInputs, .comparing, .publishing]
        let accepts = [
            [true, true, true, true],
            [false, true, true, true],
            [false, false, true, true],
            [false, false, false, true]
        ]
        for (sourceIndex, source) in stages.enumerated() {
            for (destinationIndex, destination) in stages.enumerated() {
                let empty = try State(identity: comparisonIdentity(UInt8(110 + sourceIndex * 4 + destinationIndex)))
                let loading = try beginLoading(
                    empty,
                    inputs: makeInputs(identity: UInt8(130 + sourceIndex * 4 + destinationIndex)),
                    operationID: UInt8(150 + sourceIndex * 4 + destinationIndex),
                    progress: try Progress(
                        stage: source,
                        completedUnitCount: 2,
                        totalUnitCount: 10,
                        detail: "old"
                    )
                )
                let token = try XCTUnwrap(loading.operation?.token)
                let candidate = try Progress(
                    stage: destination,
                    completedUnitCount: source == destination ? 3 : 2,
                    totalUnitCount: 10,
                    detail: "new"
                )
                if accepts[sourceIndex][destinationIndex] {
                    let progressed = try loading.applying(
                        .updateProgress(
                            expected: loading.fingerprint,
                            operation: token,
                            progress: candidate
                        )
                    )
                    XCTAssertEqual(progressed.operation?.progress, candidate)
                    XCTAssertEqual(progressed.generation, 2)
                } else {
                    assertStateError(.progressRegressed, "\(source) to \(destination)") {
                        try loading.applying(
                            .updateProgress(
                                expected: loading.fingerprint,
                                operation: token,
                                progress: candidate
                            )
                        )
                    }
                }
            }
        }
    }

    func testProgressAdvanceAllowsLateTotalAndDetailButRejectsCountAndTotalRegression() throws {
        let initial = try Progress(stage: .loadingInputs, completedUnitCount: 2, detail: "Loading")
        let empty = try State(identity: comparisonIdentity(110))
        let loading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 111),
            operationID: 112,
            progress: initial
        )
        let token = try XCTUnwrap(loading.operation?.token)
        let withTotal = try Progress(
            stage: .loadingInputs,
            completedUnitCount: 2,
            totalUnitCount: 10,
            detail: "Loading"
        )
        let progressed = try loading.applying(
            .updateProgress(expected: loading.fingerprint, operation: token, progress: withTotal)
        )
        let detailOnly = try progressed.applying(
            .updateProgress(
                expected: progressed.fingerprint,
                operation: token,
                progress: try Progress(
                    stage: .loadingInputs,
                    completedUnitCount: 2,
                    totalUnitCount: 10,
                    detail: "Still loading"
                )
            )
        )
        XCTAssertEqual(detailOnly.operation?.progress.detail, "Still loading")
        let laterStage = try Progress(
            stage: .comparing,
            completedUnitCount: 0,
            totalUnitCount: 2,
            detail: "Comparing"
        )
        let comparing = try progressed.applying(
            .updateProgress(expected: progressed.fingerprint, operation: token, progress: laterStage)
        )
        XCTAssertEqual(comparing.operation?.progress, laterStage)

        assertStateError(.progressRegressed) {
            try progressed.applying(
                .updateProgress(
                    expected: progressed.fingerprint,
                    operation: token,
                    progress: try Progress(
                        stage: .loadingInputs,
                        completedUnitCount: 1,
                        totalUnitCount: 10
                    )
                )
            )
        }
        assertStateError(.progressTotalChanged) {
            try progressed.applying(
                .updateProgress(
                    expected: progressed.fingerprint,
                    operation: token,
                    progress: try Progress(
                        stage: .loadingInputs,
                        completedUnitCount: 4,
                        totalUnitCount: 11
                    )
                )
            )
        }
        assertStateError(.progressTotalChanged) {
            try progressed.applying(
                .updateProgress(
                    expected: progressed.fingerprint,
                    operation: token,
                    progress: try Progress(stage: .loadingInputs, completedUnitCount: 4)
                )
            )
        }
        assertStateError(.progressRegressed) {
            try comparing.applying(
                .updateProgress(
                    expected: comparing.fingerprint,
                    operation: token,
                    progress: try Progress(stage: .loadingInputs, completedUnitCount: 100)
                )
            )
        }
    }

    func testMarkStaleValidatesNamedSideAgainstOriginalResult() throws {
        let fixture = try makeCurrentFixture(comparisonIdentity: 120, inputIdentity: 121)
        let unchangedNamedSide = try makeInputs(
            identity: 122,
            leftIdentity: 2,
            rightIdentity: 123
        )
        assertStateError(.invalidStaleSide(.left)) {
            try markStale(fixture.state, inputs: unchangedNamedSide, reason: .sideChanged(.left))
        }
        assertStateError(.invalidStaleSide(.middle)) {
            try markStale(fixture.state, inputs: unchangedNamedSide, reason: .externalChange(.middle))
        }

        let changedLeft = try makeInputs(identity: 124, leftIdentity: 125, rightIdentity: 3)
        let sideStale = try markStale(
            fixture.state,
            inputs: changedLeft,
            reason: .sideChanged(.left)
        )
        XCTAssertEqual(sideStale.phase, .stale)
        XCTAssertEqual(sideStale.inputs, changedLeft)
        XCTAssertEqual(sideStale.result, fixture.result)
        XCTAssertEqual(sideStale.staleness?.reason, .sideChanged(.left))
        XCTAssertEqual(sideStale.staleness?.invalidatedResult, fixture.result)
        XCTAssertEqual(sideStale.staleness?.currentInputs, changedLeft)
        XCTAssertEqual(sideStale.staleness?.detectedAtGeneration, sideStale.generation)

        let optionsOnly = try makeInputs(
            identity: 126,
            generation: fixture.inputs.generation + 1,
            leftIdentity: 2,
            rightIdentity: 3
        )
        XCTAssertEqual(
            try markStale(fixture.state, inputs: optionsOnly, reason: .optionsChanged).staleness?.reason,
            .optionsChanged
        )
        let inputGenerationOnly = try makeInputs(
            identity: 121,
            generation: fixture.inputs.generation + 1,
            leftIdentity: 2,
            rightIdentity: 3
        )
        XCTAssertEqual(
            try markStale(fixture.state, inputs: inputGenerationOnly, reason: .optionsChanged).inputs,
            inputGenerationOnly
        )
        let sideGenerationOnly = try makeInputs(
            identity: 127,
            leftIdentity: 2,
            leftGeneration: 1,
            rightIdentity: 3
        )
        XCTAssertEqual(
            try markStale(fixture.state, inputs: sideGenerationOnly, reason: .sideChanged(.left))
                .staleness?.reason,
            .sideChanged(.left)
        )
        assertStateError(.unchangedInputs) {
            try markStale(fixture.state, inputs: fixture.inputs, reason: .optionsChanged)
        }
    }

    func testComparisonModeChangedRequiresActualTwoThreeWayChange() throws {
        let fixture = try makeCurrentFixture(comparisonIdentity: 130, inputIdentity: 131)
        let changedTwoWay = try makeInputs(identity: 132, leftIdentity: 133, rightIdentity: 3)
        assertStateError(.unchangedComparisonMode) {
            try markStale(
                fixture.state,
                inputs: changedTwoWay,
                reason: .comparisonModeChanged
            )
        }

        let threeWay = try makeInputs(
            identity: 134,
            leftIdentity: 2,
            middleIdentity: 135,
            rightIdentity: 3
        )
        let stale = try markStale(
            fixture.state,
            inputs: threeWay,
            reason: .comparisonModeChanged
        )
        XCTAssertEqual(stale.phase, .stale)
        XCTAssertEqual(stale.staleness?.reason, .comparisonModeChanged)
        XCTAssertEqual(
            try markStale(fixture.state, inputs: threeWay, reason: .sideChanged(.middle))
                .staleness?.reason,
            .sideChanged(.middle)
        )

        assertStateError(.unchangedComparisonMode) {
            try markStale(stale, inputs: changedTwoWay, reason: .comparisonModeChanged)
        }

        let threeWayFixture = try makeCurrentFixture(
            comparisonIdentity: 136,
            inputs: threeWay,
            operationID: 137,
            resultID: 138
        )
        let backToTwoWay = try markStale(
            threeWayFixture.state,
            inputs: changedTwoWay,
            reason: .comparisonModeChanged
        )
        XCTAssertEqual(backToTwoWay.phase, .stale)
        XCTAssertFalse(try XCTUnwrap(backToTwoWay.inputs).isThreeWay)
        XCTAssertEqual(
            try markStale(
                threeWayFixture.state,
                inputs: changedTwoWay,
                reason: .externalChange(.middle)
            ).staleness?.reason,
            .externalChange(.middle)
        )
    }

    func testRepeatedMarkStaleUsesOriginalResultBaseline() throws {
        let fixture = try makeCurrentFixture(comparisonIdentity: 140, inputIdentity: 141)
        let firstInputs = try makeInputs(identity: 142, leftIdentity: 143, rightIdentity: 3)
        let firstStale = try markStale(
            fixture.state,
            inputs: firstInputs,
            reason: .sideChanged(.left)
        )
        let secondInputs = try makeInputs(identity: 144, leftIdentity: 143, rightIdentity: 145)
        let repeatedStale = try markStale(
            firstStale,
            inputs: secondInputs,
            reason: .sideChanged(.left)
        )

        XCTAssertEqual(repeatedStale.phase, .stale)
        XCTAssertEqual(repeatedStale.generation, firstStale.generation + 1)
        XCTAssertEqual(repeatedStale.inputs, secondInputs)
        XCTAssertEqual(repeatedStale.result, fixture.result)
        XCTAssertEqual(repeatedStale.staleness?.invalidatedResult, fixture.result)
        XCTAssertEqual(repeatedStale.staleness?.currentInputs, secondInputs)
        XCTAssertEqual(repeatedStale.staleness?.reason, .sideChanged(.left))

        let thirdInputs = try makeInputs(identity: 146, leftIdentity: 2, rightIdentity: 145)
        let rightStale = try markStale(
            repeatedStale,
            inputs: thirdInputs,
            reason: .sideChanged(.right)
        )
        XCTAssertEqual(rightStale.phase, .stale)
        XCTAssertEqual(rightStale.staleness?.invalidatedResult, fixture.result)
        XCTAssertEqual(rightStale.staleness?.reason, .sideChanged(.right))
    }

    func testReturningToOriginalResultInputsRestoresExactCurrentResult() throws {
        let fixture = try makeCurrentFixture(comparisonIdentity: 150, inputIdentity: 151)
        let changedInputs = try makeInputs(identity: 152, leftIdentity: 153, rightIdentity: 3)
        let stale = try markStale(
            fixture.state,
            inputs: changedInputs,
            reason: .externalChange(.left)
        )
        let restored = try markStale(
            stale,
            inputs: fixture.inputs,
            reason: .sideChanged(.middle)
        )

        XCTAssertEqual(restored.phase, .current)
        XCTAssertEqual(restored.generation, stale.generation + 1)
        XCTAssertEqual(restored.inputs, fixture.inputs)
        XCTAssertEqual(restored.result, fixture.result)
        XCTAssertEqual(restored.result?.identity, fixture.result.identity)
        XCTAssertEqual(restored.result?.inputs, fixture.result.inputs)
        XCTAssertEqual(restored.result?.operation, fixture.result.operation)
        XCTAssertEqual(
            restored.result?.publishedAtGeneration,
            fixture.result.publishedAtGeneration
        )
        XCTAssertNil(restored.staleness)
        XCTAssertNil(restored.failure)
        XCTAssertNil(restored.cancellation)
        XCTAssertTrue(restored.hasCurrentResult)
    }

    func testUnchangedMarkStalePreservesFailedAndCanceledRefreshStates() throws {
        let fixture = try makeCurrentFixture(comparisonIdentity: 160, inputIdentity: 161)

        let failingRefresh = try beginRefreshing(fixture.state, operationID: 162)
        let failingToken = try XCTUnwrap(failingRefresh.operation?.token)
        let failed = try failingRefresh.applying(
            .fail(
                expected: failingRefresh.fingerprint,
                operation: failingToken,
                failure: try makeFailure(stage: .preparing, isRetryable: true)
            )
        )
        let failedFingerprint = failed.fingerprint
        assertStateError(.unchangedInputs) {
            try markStale(failed, inputs: fixture.inputs, reason: .optionsChanged)
        }
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.fingerprint, failedFingerprint)
        XCTAssertEqual(failed.generation, failedFingerprint.generation)
        XCTAssertNotNil(failed.failure)
        XCTAssertNil(failed.cancellation)

        let cancelingRefresh = try beginRefreshing(fixture.state, operationID: 163)
        let cancelingToken = try XCTUnwrap(cancelingRefresh.operation?.token)
        let canceled = try cancelingRefresh.applying(
            .cancel(
                expected: cancelingRefresh.fingerprint,
                operation: cancelingToken,
                cancellation: try State.Cancellation(reason: .userRequested, stage: .preparing)
            )
        )
        let canceledFingerprint = canceled.fingerprint
        assertStateError(.unchangedInputs) {
            try markStale(canceled, inputs: fixture.inputs, reason: .optionsChanged)
        }
        XCTAssertEqual(canceled.phase, .canceled)
        XCTAssertEqual(canceled.fingerprint, canceledFingerprint)
        XCTAssertEqual(canceled.generation, canceledFingerprint.generation)
        XCTAssertNil(canceled.failure)
        XCTAssertNotNil(canceled.cancellation)
    }

    func testFailedAndCanceledStaleRefreshCanRestoreOriginalResult() throws {
        let fixture = try makeCurrentFixture(comparisonIdentity: 170, inputIdentity: 171)
        let changedInputs = try makeInputs(identity: 172, leftIdentity: 173, rightIdentity: 3)
        let stale = try markStale(fixture.state, inputs: changedInputs, reason: .sideChanged(.left))

        let failingRefresh = try beginRefreshing(stale, operationID: 174)
        let failingToken = try XCTUnwrap(failingRefresh.operation?.token)
        let failed = try failingRefresh.applying(
            .fail(
                expected: failingRefresh.fingerprint,
                operation: failingToken,
                failure: try makeFailure(stage: .preparing, isRetryable: true)
            )
        )
        assertStateError(.unchangedInputs) {
            try markStale(failed, inputs: changedInputs, reason: .optionsChanged)
        }
        let restoredFromFailure = try markStale(
            failed,
            inputs: fixture.inputs,
            reason: .optionsChanged
        )
        XCTAssertEqual(restoredFromFailure.phase, .current)
        XCTAssertEqual(restoredFromFailure.result, fixture.result)
        XCTAssertNil(restoredFromFailure.staleness)
        XCTAssertNil(restoredFromFailure.failure)

        let cancelingRefresh = try beginRefreshing(stale, operationID: 175)
        let cancelingToken = try XCTUnwrap(cancelingRefresh.operation?.token)
        let canceled = try cancelingRefresh.applying(
            .cancel(
                expected: cancelingRefresh.fingerprint,
                operation: cancelingToken,
                cancellation: try State.Cancellation(reason: .userRequested, stage: .preparing)
            )
        )
        assertStateError(.unchangedInputs) {
            try markStale(canceled, inputs: changedInputs, reason: .optionsChanged)
        }
        let restoredFromCancellation = try markStale(
            canceled,
            inputs: fixture.inputs,
            reason: .optionsChanged
        )
        XCTAssertEqual(restoredFromCancellation.phase, .current)
        XCTAssertEqual(restoredFromCancellation.result, fixture.result)
        XCTAssertNil(restoredFromCancellation.staleness)
        XCTAssertNil(restoredFromCancellation.cancellation)
    }

    func testRetainedFailureRetryPolicyStalenessAndCurrency() throws {
        let fixture = try makeCurrentFixture(comparisonIdentity: 180, inputIdentity: 181)
        let refresh = try beginRefreshing(fixture.state, operationID: 182)
        let token = try XCTUnwrap(refresh.operation?.token)
        let failed = try refresh.applying(
            .fail(
                expected: refresh.fingerprint,
                operation: token,
                failure: try makeFailure(kind: .unsupported, isRetryable: false)
            )
        )
        XCTAssertFalse(failed.hasCurrentResult)
        XCTAssertTrue(failed.hasRetainedResult)
        XCTAssertEqual(
            failed.availability(for: .beginRefreshing),
            .disabled(.failureNotRetryable(.unsupported))
        )
        assertStateError(.commandDisabled(.failureNotRetryable(.unsupported))) {
            try beginRefreshing(failed, operationID: 183)
        }

        let changedInputs = try makeInputs(identity: 184, leftIdentity: 185, rightIdentity: 3)
        let stale = try markStale(failed, inputs: changedInputs, reason: .sideChanged(.left))
        XCTAssertEqual(stale.phase, .stale)
        XCTAssertNil(stale.failure)
        XCTAssertFalse(stale.hasCurrentResult)
        XCTAssertTrue(stale.hasRetainedResult)
        XCTAssertEqual(
            stale.availability(for: .beginRefreshing),
            .enabled(.refreshMayStart(fixture.result.identity))
        )
        XCTAssertEqual(try beginRefreshing(stale, operationID: 186).phase, .refreshing)
    }

    func testCurrencyMatrixAcrossEveryPhaseAndTerminalLineage() throws {
        let empty = try State(identity: comparisonIdentity(187))
        let oneSide = try empty.applying(
            .loadFirstSide(expected: empty.fingerprint, binding: side(.left, identity: 188))
        )
        let initialLoading = try beginLoading(empty, inputs: makeInputs(identity: 189), operationID: 190)
        let initialToken = try XCTUnwrap(initialLoading.operation?.token)
        let initialFailed = try initialLoading.applying(
            .fail(
                expected: initialLoading.fingerprint,
                operation: initialToken,
                failure: try makeFailure(isRetryable: true)
            )
        )
        let secondInitialLoading = try beginLoading(empty, inputs: makeInputs(identity: 189), operationID: 191)
        let secondInitialToken = try XCTUnwrap(secondInitialLoading.operation?.token)
        let initialCanceled = try secondInitialLoading.applying(
            .cancel(
                expected: secondInitialLoading.fingerprint,
                operation: secondInitialToken,
                cancellation: try State.Cancellation(reason: .userRequested, stage: .preparing)
            )
        )
        let fixture = try makeCurrentFixture(comparisonIdentity: 190, inputIdentity: 191)
        let changedInputs = try makeInputs(identity: 192, leftIdentity: 193, rightIdentity: 3)
        let stale = try markStale(fixture.state, inputs: changedInputs, reason: .sideChanged(.left))
        let refreshing = try beginRefreshing(stale, operationID: 194)
        let token = try XCTUnwrap(refreshing.operation?.token)
        let failed = try refreshing.applying(
            .fail(
                expected: refreshing.fingerprint,
                operation: token,
                failure: try makeFailure(stage: .preparing, isRetryable: true)
            )
        )
        let canceledRefresh = try beginRefreshing(stale, operationID: 195)
        let canceledToken = try XCTUnwrap(canceledRefresh.operation?.token)
        let canceled = try canceledRefresh.applying(
            .cancel(
                expected: canceledRefresh.fingerprint,
                operation: canceledToken,
                cancellation: try State.Cancellation(reason: .userRequested, stage: .preparing)
            )
        )
        let completedRefresh = try beginRefreshing(stale, operationID: 196)
        let completed = try complete(completedRefresh, resultID: 197)
        let cases: [(String, State, Bool, Bool, Bool)] = [
            ("empty", empty, false, false, false),
            ("oneSideLoaded", oneSide, false, false, false),
            ("initial loading", initialLoading, true, false, false),
            ("current", fixture.state, false, true, true),
            ("stale", stale, false, false, true),
            ("refreshing", refreshing, true, false, true),
            ("initial failed", initialFailed, false, false, false),
            ("refresh failed", failed, false, false, true),
            ("initial canceled", initialCanceled, false, false, false),
            ("refresh canceled", canceled, false, false, true),
            ("completed refresh", completed, false, true, true)
        ]
        for (name, state, active, current, retained) in cases {
            XCTAssertEqual(state.hasActiveOperation, active, name)
            XCTAssertEqual(state.hasCurrentResult, current, name)
            XCTAssertEqual(state.hasRetainedResult, retained, name)
        }
    }

    func testRefreshOperationIDReuseAndValidationPrecedenceMatrix() throws {
        let fixture = try makeCurrentFixture(
            comparisonIdentity: 200,
            inputIdentity: 201,
            operationID: 202,
            resultID: 203
        )
        let limits = Limits(
            maximumProgressDetailUTF8Bytes: 4,
            maximumDeclaredWorkUnits: 5
        )
        let limitedFixture = try makeCurrentFixture(
            comparisonIdentity: 204,
            inputIdentity: 205,
            operationID: 206,
            resultID: 207,
            limits: limits
        )
        assertStateError(.declaredWorkLimitExceeded(maximum: 5)) {
            try beginRefreshing(
                limitedFixture.state,
                operationID: 206,
                declaredWorkUnits: 6,
                progress: try Progress(stage: .preparing, completedUnitCount: 0, detail: "12345")
            )
        }
        assertStateError(.metadataTooLarge(field: .progressDetail, maximumBytes: 4)) {
            try beginRefreshing(
                limitedFixture.state,
                operationID: 206,
                progress: try Progress(stage: .preparing, completedUnitCount: 0, detail: "12345")
            )
        }
        assertStateError(.duplicateOperationID(operationID(202))) {
            try beginRefreshing(fixture.state, operationID: 202)
        }

        let retrySource = try markStale(
            fixture.state,
            inputs: makeInputs(identity: 209, leftIdentity: 210),
            reason: .sideChanged(.left)
        )
        XCTAssertNotNil(retrySource.staleness)
        for terminal in [State.Phase.failed, .canceled] {
            let refreshing = try beginRefreshing(retrySource, operationID: 208)
            let token = try XCTUnwrap(refreshing.operation?.token)
            let terminalState: State
            switch terminal {
            case .failed:
                terminalState = try refreshing.applying(
                    .fail(
                        expected: refreshing.fingerprint,
                        operation: token,
                        failure: try makeFailure(isRetryable: true)
                    )
                )
            case .canceled:
                terminalState = try refreshing.applying(
                    .cancel(
                        expected: refreshing.fingerprint,
                        operation: token,
                        cancellation: try State.Cancellation(
                            reason: .userRequested,
                            stage: .preparing
                        )
                    )
                )
            case .empty, .oneSideLoaded, .loading, .current, .stale, .refreshing:
                XCTFail("Unexpected terminal phase \(terminal)")
                continue
            }
            let retryProgress = try Progress(
                stage: .loadingInputs,
                completedUnitCount: 2,
                totalUnitCount: 5,
                detail: "Retrying"
            )
            let retried = try beginRefreshing(
                terminalState,
                operationID: 208,
                declaredWorkUnits: 9,
                progress: retryProgress
            )
            let retriedOperation = try XCTUnwrap(retried.operation)
            XCTAssertEqual(retried.identity, terminalState.identity)
            XCTAssertEqual(retried.generation, terminalState.generation + 1)
            XCTAssertEqual(retried.limits, terminalState.limits)
            XCTAssertEqual(retried.phase, .refreshing)
            XCTAssertNil(retried.loadedSide)
            XCTAssertEqual(retried.inputs, terminalState.inputs)
            XCTAssertEqual(retriedOperation.kind, .refresh)
            XCTAssertEqual(retriedOperation.token.comparisonIdentity, terminalState.identity)
            XCTAssertEqual(retriedOperation.token.operationID, operationID(208))
            XCTAssertEqual(
                retriedOperation.token.startedAtGeneration,
                terminalState.generation + 1
            )
            XCTAssertEqual(retriedOperation.token.inputs, terminalState.inputs)
            XCTAssertNotEqual(retriedOperation.token, token)
            XCTAssertEqual(retriedOperation.declaredWorkUnits, 9)
            XCTAssertEqual(retriedOperation.progress, retryProgress)
            XCTAssertEqual(retried.result, terminalState.result)
            XCTAssertEqual(retried.staleness, terminalState.staleness)
            XCTAssertNil(retried.failure)
            XCTAssertNil(retried.cancellation)
            XCTAssertTrue(retried.hasActiveOperation)
            XCTAssertFalse(retried.hasCurrentResult)
            XCTAssertTrue(retried.hasRetainedResult)
        }
    }

    func testFailureAndCancellationStageMatricesAndSideValidation() throws {
        let stages: [Progress.Stage] = [.preparing, .loadingInputs, .comparing, .publishing]
        let accepts = [
            [true, true, true, true],
            [false, true, true, true],
            [false, false, true, true],
            [false, false, false, true]
        ]
        for (progressIndex, progressStage) in stages.enumerated() {
            for (terminalIndex, terminalStage) in stages.enumerated() {
                let empty = try State(identity: comparisonIdentity(UInt8(210 + progressIndex * 4 + terminalIndex)))
                let loading = try beginLoading(
                    empty,
                    inputs: makeInputs(identity: UInt8(230 + progressIndex * 4 + terminalIndex)),
                    operationID: UInt8(250 - progressIndex * 4 - terminalIndex),
                    progress: try Progress(stage: progressStage, completedUnitCount: 1)
                )
                let token = try XCTUnwrap(loading.operation?.token)
                if accepts[progressIndex][terminalIndex] {
                    let failed = try loading.applying(
                        .fail(
                            expected: loading.fingerprint,
                            operation: token,
                            failure: try makeFailure(stage: terminalStage, side: .right)
                        )
                    )
                    XCTAssertEqual(failed.failure?.lastProgress.stage, progressStage)
                    XCTAssertEqual(failed.failure?.failure.stage, terminalStage)
                    XCTAssertEqual(failed.failure?.failure.side, .right)
                    let canceled = try loading.applying(
                        .cancel(
                            expected: loading.fingerprint,
                            operation: token,
                            cancellation: try State.Cancellation(
                                reason: .userRequested,
                                stage: terminalStage
                            )
                        )
                    )
                    XCTAssertEqual(canceled.cancellation?.lastProgress.stage, progressStage)
                    XCTAssertEqual(canceled.cancellation?.cancellation.stage, terminalStage)
                } else {
                    assertStateError(.failureStageRegressed, "\(progressStage) to \(terminalStage)") {
                        try loading.applying(
                            .fail(
                                expected: loading.fingerprint,
                                operation: token,
                                failure: try makeFailure(stage: terminalStage)
                            )
                        )
                    }
                    assertStateError(.cancellationStageRegressed, "\(progressStage) to \(terminalStage)") {
                        try loading.applying(
                            .cancel(
                                expected: loading.fingerprint,
                                operation: token,
                                cancellation: try State.Cancellation(
                                    reason: .userRequested,
                                    stage: terminalStage
                                )
                            )
                        )
                    }
                }
            }
        }

        let twoWayLoading = try beginLoading(
            State(identity: comparisonIdentity(209)),
            inputs: makeInputs(identity: 208),
            operationID: 207
        )
        let token = try XCTUnwrap(twoWayLoading.operation?.token)
        let leftFailure = try twoWayLoading.applying(
            .fail(
                expected: twoWayLoading.fingerprint,
                operation: token,
                failure: try makeFailure(side: .left)
            )
        )
        XCTAssertEqual(leftFailure.failure?.failure.side, .left)

        let threeWayLoading = try beginLoading(
            State(identity: comparisonIdentity(208)),
            inputs: makeInputs(identity: 207, middleIdentity: 206),
            operationID: 205
        )
        let threeWayToken = try XCTUnwrap(threeWayLoading.operation?.token)
        let middleFailure = try threeWayLoading.applying(
            .fail(
                expected: threeWayLoading.fingerprint,
                operation: threeWayToken,
                failure: try makeFailure(side: .middle)
            )
        )
        XCTAssertEqual(middleFailure.failure?.failure.side, .middle)

        assertStateError(.invalidFailureSide(.middle)) {
            try twoWayLoading.applying(
                .fail(
                    expected: twoWayLoading.fingerprint,
                    operation: token,
                    failure: try makeFailure(side: .middle)
                )
            )
        }
    }

    func testEveryLimitRejectsZeroOrHardExcessAndHardBoundariesAreAccepted() throws {
        XCTAssertEqual(Limits.hardMaximumFailureCodeUTF8Bytes, 1_024)
        XCTAssertEqual(Limits.hardMaximumFailureMessageUTF8Bytes, 65_536)
        XCTAssertEqual(Limits.hardMaximumProgressDetailUTF8Bytes, 16_384)
        XCTAssertEqual(Limits.hardMaximumCancellationDetailUTF8Bytes, 16_384)
        XCTAssertEqual(Limits.hardMaximumTotalMetadataUTF8Bytes, 131_072)
        XCTAssertEqual(Limits.hardMaximumProgressUnitCount, 4_611_686_018_427_387_903)
        XCTAssertEqual(Limits.hardMaximumDeclaredWorkUnits, 4_611_686_018_427_387_903)
        XCTAssertEqual(Limits.hardMaximumTransitionWorkUnits, 4_194_304)
        XCTAssertEqual(Limits.default.maximumFailureCodeUTF8Bytes, 256)
        XCTAssertEqual(Limits.default.maximumFailureMessageUTF8Bytes, 16_384)
        XCTAssertEqual(Limits.default.maximumProgressDetailUTF8Bytes, 4_096)
        XCTAssertEqual(Limits.default.maximumCancellationDetailUTF8Bytes, 4_096)
        XCTAssertEqual(Limits.default.maximumTotalMetadataUTF8Bytes, 32_768)
        XCTAssertEqual(Limits.default.maximumProgressUnitCount, 1_000_000_000_000)
        XCTAssertEqual(Limits.default.maximumDeclaredWorkUnits, 1_000_000_000_000)
        XCTAssertEqual(Limits.default.maximumTransitionWorkUnits, 262_144)
        XCTAssertEqual(Limits.default.cancellationCheckInterval, 4_096)

        let hardLimits = Limits(
            maximumFailureCodeUTF8Bytes: Limits.hardMaximumFailureCodeUTF8Bytes,
            maximumFailureMessageUTF8Bytes: Limits.hardMaximumFailureMessageUTF8Bytes,
            maximumProgressDetailUTF8Bytes: Limits.hardMaximumProgressDetailUTF8Bytes,
            maximumCancellationDetailUTF8Bytes: Limits.hardMaximumCancellationDetailUTF8Bytes,
            maximumTotalMetadataUTF8Bytes: Limits.hardMaximumTotalMetadataUTF8Bytes,
            maximumProgressUnitCount: Limits.hardMaximumProgressUnitCount,
            maximumDeclaredWorkUnits: Limits.hardMaximumDeclaredWorkUnits,
            maximumTransitionWorkUnits: Limits.hardMaximumTransitionWorkUnits,
            cancellationCheckInterval: Limits.hardMaximumTransitionWorkUnits
        )
        XCTAssertNoThrow(try State(identity: comparisonIdentity(220), limits: hardLimits))

        let invalidCases: [(Limits, State.Limit)] = [
            (Limits(maximumFailureCodeUTF8Bytes: 0), .failureCodeUTF8Bytes),
            (
                Limits(maximumFailureCodeUTF8Bytes: Limits.hardMaximumFailureCodeUTF8Bytes + 1),
                .failureCodeUTF8Bytes
            ),
            (Limits(maximumFailureMessageUTF8Bytes: 0), .failureMessageUTF8Bytes),
            (
                Limits(maximumFailureMessageUTF8Bytes: Limits.hardMaximumFailureMessageUTF8Bytes + 1),
                .failureMessageUTF8Bytes
            ),
            (Limits(maximumProgressDetailUTF8Bytes: 0), .progressDetailUTF8Bytes),
            (
                Limits(maximumProgressDetailUTF8Bytes: Limits.hardMaximumProgressDetailUTF8Bytes + 1),
                .progressDetailUTF8Bytes
            ),
            (Limits(maximumCancellationDetailUTF8Bytes: 0), .cancellationDetailUTF8Bytes),
            (
                Limits(maximumCancellationDetailUTF8Bytes: Limits.hardMaximumCancellationDetailUTF8Bytes + 1),
                .cancellationDetailUTF8Bytes
            ),
            (Limits(maximumTotalMetadataUTF8Bytes: 0), .totalMetadataUTF8Bytes),
            (
                Limits(maximumTotalMetadataUTF8Bytes: Limits.hardMaximumTotalMetadataUTF8Bytes + 1),
                .totalMetadataUTF8Bytes
            ),
            (Limits(maximumTotalMetadataUTF8Bytes: 255), .totalMetadataUTF8Bytes),
            (Limits(maximumProgressUnitCount: 0), .progressUnitCount),
            (
                Limits(maximumProgressUnitCount: Limits.hardMaximumProgressUnitCount + 1),
                .progressUnitCount
            ),
            (Limits(maximumDeclaredWorkUnits: 0), .declaredWorkUnits),
            (
                Limits(maximumDeclaredWorkUnits: Limits.hardMaximumDeclaredWorkUnits + 1),
                .declaredWorkUnits
            ),
            (Limits(maximumTransitionWorkUnits: 0), .transitionWorkUnits),
            (
                Limits(maximumTransitionWorkUnits: Limits.hardMaximumTransitionWorkUnits + 1),
                .transitionWorkUnits
            ),
            (Limits(cancellationCheckInterval: 0), .cancellationCheckInterval),
            (
                Limits(maximumTransitionWorkUnits: 10, cancellationCheckInterval: 11),
                .cancellationCheckInterval
            )
        ]

        for (index, testCase) in invalidCases.enumerated() {
            assertStateError(.invalidLimit(testCase.1), "invalid limit case \(index)") {
                try State(identity: comparisonIdentity(UInt8(221 + index)), limits: testCase.0)
            }
        }

        let totalCoverageCases: [(Limits, Bool)] = [
            (limits(fieldMaximums: [5, 1, 1, 1], total: 4), false),
            (limits(fieldMaximums: [1, 5, 1, 1], total: 4), false),
            (limits(fieldMaximums: [1, 1, 5, 1], total: 4), false),
            (limits(fieldMaximums: [1, 1, 1, 5], total: 4), false),
            (limits(fieldMaximums: [5, 1, 1, 1], total: 5), true),
            (limits(fieldMaximums: [1, 5, 1, 1], total: 5), true),
            (limits(fieldMaximums: [1, 1, 5, 1], total: 5), true),
            (limits(fieldMaximums: [1, 1, 1, 5], total: 5), true)
        ]
        for (index, testCase) in totalCoverageCases.enumerated() {
            if testCase.1 {
                XCTAssertNoThrow(
                    try State(identity: comparisonIdentity(UInt8(100 + index)), limits: testCase.0),
                    "total coverage case \(index)"
                )
            } else {
                assertStateError(.invalidLimit(.totalMetadataUTF8Bytes), "total coverage case \(index)") {
                    try State(identity: comparisonIdentity(UInt8(100 + index)), limits: testCase.0)
                }
            }
        }
    }

    func testConfiguredPerFieldMetadataLimitsAcceptExactAndRejectExcess() throws {
        let limits = Limits(
            maximumFailureCodeUTF8Bytes: 3,
            maximumFailureMessageUTF8Bytes: 4,
            maximumProgressDetailUTF8Bytes: 4,
            maximumCancellationDetailUTF8Bytes: 4,
            maximumTotalMetadataUTF8Bytes: 11
        )
        let inputs = try makeInputs(identity: 30)
        let empty = try State(identity: comparisonIdentity(31), limits: limits)
        let exactProgress = try Progress(
            stage: .preparing,
            completedUnitCount: 0,
            detail: "1234"
        )
        XCTAssertEqual(
            try beginLoading(empty, inputs: inputs, operationID: 32, progress: exactProgress)
                .operation?.progress.detail,
            "1234"
        )
        assertStateError(.metadataTooLarge(field: .progressDetail, maximumBytes: 4)) {
            try beginLoading(
                empty,
                inputs: inputs,
                operationID: 33,
                progress: try Progress(
                    stage: .preparing,
                    completedUnitCount: 0,
                    detail: "12345"
                )
            )
        }
        XCTAssertEqual(
            try beginLoading(
                empty,
                inputs: inputs,
                operationID: 35,
                progress: try Progress(stage: .preparing, completedUnitCount: 0, detail: "éé")
            ).operation?.progress.detail?.utf8.count,
            4
        )
        assertStateError(.metadataTooLarge(field: .progressDetail, maximumBytes: 4)) {
            try beginLoading(
                empty,
                inputs: inputs,
                operationID: 36,
                progress: try Progress(stage: .preparing, completedUnitCount: 0, detail: "ééa")
            )
        }

        let loading = try beginLoading(empty, inputs: inputs, operationID: 34)
        let token = try XCTUnwrap(loading.operation?.token)
        let exactFailure = try makeFailure(code: "ABC", message: "1234")
        XCTAssertEqual(
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: exactFailure
                )
            ).failure?.failure,
            exactFailure
        )
        assertStateError(.metadataTooLarge(field: .failureCode, maximumBytes: 3)) {
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: try makeFailure(code: "ABCD", message: "1")
                )
            )
        }
        assertStateError(.metadataTooLarge(field: .failureMessage, maximumBytes: 4)) {
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: try makeFailure(code: "A", message: "12345")
                )
            )
        }
        XCTAssertEqual(
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: try makeFailure(code: "A", message: "éé")
                )
            ).failure?.failure.message.utf8.count,
            4
        )
        assertStateError(.metadataTooLarge(field: .failureMessage, maximumBytes: 4)) {
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: try makeFailure(code: "A", message: "ééa")
                )
            )
        }

        let exactCancellation = try State.Cancellation(
            reason: .userRequested,
            stage: .preparing,
            detail: "1234"
        )
        XCTAssertEqual(
            try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: token,
                    cancellation: exactCancellation
                )
            ).cancellation?.cancellation,
            exactCancellation
        )
        assertStateError(.metadataTooLarge(field: .cancellationDetail, maximumBytes: 4)) {
            try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: token,
                    cancellation: try State.Cancellation(
                        reason: .userRequested,
                        stage: .preparing,
                        detail: "12345"
                    )
                )
            )
        }
        XCTAssertEqual(
            try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: token,
                    cancellation: try State.Cancellation(
                        reason: .userRequested,
                        stage: .preparing,
                        detail: "éé"
                    )
                )
            ).cancellation?.cancellation.detail?.utf8.count,
            4
        )
        assertStateError(.metadataTooLarge(field: .cancellationDetail, maximumBytes: 4)) {
            try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: token,
                    cancellation: try State.Cancellation(
                        reason: .userRequested,
                        stage: .preparing,
                        detail: "ééa"
                    )
                )
            )
        }
    }

    func testTotalMetadataLimitIncludesExistingProgressForFailureAndCancellation() throws {
        let limits = Limits(
            maximumFailureCodeUTF8Bytes: 3,
            maximumFailureMessageUTF8Bytes: 4,
            maximumProgressDetailUTF8Bytes: 4,
            maximumCancellationDetailUTF8Bytes: 6,
            maximumTotalMetadataUTF8Bytes: 7
        )
        let empty = try State(identity: comparisonIdentity(40), limits: limits)
        let progress = try Progress(stage: .preparing, completedUnitCount: 0, detail: "12")
        let loading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 41),
            operationID: 42,
            progress: progress
        )
        let token = try XCTUnwrap(loading.operation?.token)
        XCTAssertEqual(
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: try makeFailure(code: "AB", message: "123")
                )
            ).phase,
            .failed
        )
        assertStateError(.totalMetadataTooLarge(maximumBytes: 7)) {
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: try makeFailure(code: "ABC", message: "123")
                )
            )
        }
        XCTAssertEqual(
            try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: token,
                    cancellation: try State.Cancellation(
                        reason: .resourceLimit,
                        stage: .preparing,
                        detail: "12345"
                    )
                )
            ).phase,
            .canceled
        )
        assertStateError(.totalMetadataTooLarge(maximumBytes: 7)) {
            try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: token,
                    cancellation: try State.Cancellation(
                        reason: .resourceLimit,
                        stage: .preparing,
                        detail: "123456"
                    )
                )
            )
        }
    }

    func testConfiguredProgressAndDeclaredWorkLimitsUseExactBoundaries() throws {
        let limits = Limits(
            maximumProgressDetailUTF8Bytes: 4,
            maximumProgressUnitCount: 10,
            maximumDeclaredWorkUnits: 20
        )
        let empty = try State(identity: comparisonIdentity(50), limits: limits)
        let inputs = try makeInputs(identity: 51)
        let exact = try beginLoading(
            empty,
            inputs: inputs,
            operationID: 52,
            declaredWorkUnits: 20,
            progress: try Progress(
                stage: .preparing,
                completedUnitCount: 10,
                totalUnitCount: 10
            )
        )
        XCTAssertEqual(exact.operation?.declaredWorkUnits, 20)
        XCTAssertEqual(exact.operation?.progress.completedUnitCount, 10)

        assertStateError(.declaredWorkLimitExceeded(maximum: 20)) {
            try beginLoading(
                empty,
                inputs: inputs,
                operationID: 53,
                declaredWorkUnits: 21
            )
        }
        assertStateError(.progressUnitLimitExceeded(maximum: 10)) {
            try beginLoading(
                empty,
                inputs: inputs,
                operationID: 54,
                progress: try Progress(stage: .preparing, completedUnitCount: 11)
            )
        }
        assertStateError(.progressUnitLimitExceeded(maximum: 10)) {
            try beginLoading(
                empty,
                inputs: inputs,
                operationID: 55,
                progress: try Progress(
                    stage: .preparing,
                    completedUnitCount: 0,
                    totalUnitCount: 11
                )
            )
        }

        let fixture = try makeCurrentFixture(
            comparisonIdentity: 56,
            inputIdentity: 57,
            operationID: 58,
            resultID: 59,
            limits: limits
        )
        let exactRefresh = try beginRefreshing(
            fixture.state,
            operationID: 60,
            declaredWorkUnits: 20,
            progress: try Progress(
                stage: .preparing,
                completedUnitCount: 10,
                totalUnitCount: 10,
                detail: "1234"
            )
        )
        XCTAssertEqual(exactRefresh.operation?.declaredWorkUnits, 20)
        XCTAssertEqual(exactRefresh.operation?.progress.completedUnitCount, 10)
        XCTAssertEqual(exactRefresh.operation?.progress.detail?.utf8.count, 4)
        assertStateError(.declaredWorkLimitExceeded(maximum: 20)) {
            try beginRefreshing(fixture.state, operationID: 61, declaredWorkUnits: 21)
        }
        assertStateError(.progressUnitLimitExceeded(maximum: 10)) {
            try beginRefreshing(
                fixture.state,
                operationID: 62,
                progress: try Progress(stage: .preparing, completedUnitCount: 11)
            )
        }
        assertStateError(.progressUnitLimitExceeded(maximum: 10)) {
            try beginRefreshing(
                fixture.state,
                operationID: 63,
                progress: try Progress(stage: .preparing, completedUnitCount: 0, totalUnitCount: 11)
            )
        }
        assertStateError(.metadataTooLarge(field: .progressDetail, maximumBytes: 4)) {
            try beginRefreshing(
                fixture.state,
                operationID: 64,
                progress: try Progress(stage: .preparing, completedUnitCount: 0, detail: "12345")
            )
        }

        let active = try beginRefreshing(fixture.state, operationID: 65)
        let activeToken = try XCTUnwrap(active.operation?.token)
        assertStateError(.progressUnitLimitExceeded(maximum: 10)) {
            try active.applying(
                .updateProgress(
                    expected: active.fingerprint,
                    operation: activeToken,
                    progress: try Progress(stage: .preparing, completedUnitCount: 11)
                )
            )
        }
        assertStateError(.progressUnitLimitExceeded(maximum: 10)) {
            try active.applying(
                .updateProgress(
                    expected: active.fingerprint,
                    operation: activeToken,
                    progress: try Progress(stage: .preparing, completedUnitCount: 0, totalUnitCount: 11)
                )
            )
        }
        assertStateError(.metadataTooLarge(field: .progressDetail, maximumBytes: 4)) {
            try active.applying(
                .updateProgress(
                    expected: active.fingerprint,
                    operation: activeToken,
                    progress: try Progress(stage: .preparing, completedUnitCount: 0, detail: "12345")
                )
            )
        }
    }

    func testTransitionWorkLimitAcceptsExactAndRejectsOneMore() throws {
        let limits = Limits(maximumTransitionWorkUnits: 4, cancellationCheckInterval: 2)
        let empty = try State(identity: comparisonIdentity(60), limits: limits)
        let loading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 61),
            operationID: 62
        )
        XCTAssertTrue(try loading.fingerprint.matches(loading))
        let token = try XCTUnwrap(loading.operation?.token)

        let exact = try Progress(stage: .preparing, completedUnitCount: 0, detail: "1234")
        XCTAssertEqual(
            try loading.applying(
                .updateProgress(
                    expected: loading.fingerprint,
                    operation: token,
                    progress: exact
                )
            ).operation?.progress.detail,
            "1234"
        )
        assertStateError(.workLimitExceeded(maximum: 4)) {
            try loading.applying(
                .updateProgress(
                    expected: loading.fingerprint,
                    operation: token,
                    progress: try Progress(
                        stage: .preparing,
                        completedUnitCount: 0,
                        detail: "12345"
                    )
                )
            )
        }
    }

    func testTransitionWorkLimitCumulativelyCountsFingerprintAndMultibytePayload() throws {
        let fingerprintDetail = "é"
        let payloadDetail = "界"
        XCTAssertEqual(fingerprintDetail.utf8.count, 2)
        XCTAssertEqual(payloadDetail.utf8.count, 3)

        let exactLimits = Limits(
            maximumTransitionWorkUnits: 5,
            cancellationCheckInterval: 5
        )
        let exactLoading = try beginLoading(
            State(identity: comparisonIdentity(63), limits: exactLimits),
            inputs: makeInputs(identity: 64),
            operationID: 65,
            progress: try Progress(
                stage: .preparing,
                completedUnitCount: 0,
                detail: fingerprintDetail
            )
        )
        let exactProgressed = try exactLoading.applying(
            .updateProgress(
                expected: exactLoading.fingerprint,
                operation: try XCTUnwrap(exactLoading.operation?.token),
                progress: try Progress(
                    stage: .loadingInputs,
                    completedUnitCount: 1,
                    detail: payloadDetail
                )
            )
        )
        XCTAssertEqual(exactProgressed.operation?.progress.detail, payloadDetail)

        let oneLessLimits = Limits(
            maximumTransitionWorkUnits: 4,
            cancellationCheckInterval: 4
        )
        let oneLessLoading = try beginLoading(
            State(identity: comparisonIdentity(66), limits: oneLessLimits),
            inputs: makeInputs(identity: 67),
            operationID: 68,
            progress: try Progress(
                stage: .preparing,
                completedUnitCount: 0,
                detail: fingerprintDetail
            )
        )
        assertStateError(.workLimitExceeded(maximum: 4)) {
            try oneLessLoading.applying(
                .updateProgress(
                    expected: oneLessLoading.fingerprint,
                    operation: try XCTUnwrap(oneLessLoading.operation?.token),
                    progress: try Progress(
                        stage: .loadingInputs,
                        completedUnitCount: 1,
                        detail: payloadDetail
                    )
                )
            )
        }
    }

    func testRecordingCancellationWorksFromCanceledTaskForBothOverloads() async throws {
        let empty = try State(identity: comparisonIdentity(70))
        let loading = try beginLoading(empty, inputs: makeInputs(identity: 71), operationID: 72)
        let token = try XCTUnwrap(loading.operation?.token)
        let prebuiltCancellation = try State.Cancellation(
            reason: .superseded,
            stage: .preparing,
            detail: "Superseded"
        )

        let ordinaryTask = Task { () throws -> State in
            withUnsafeCurrentTask { $0?.cancel() }
            return try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: token,
                    cancellation: prebuiltCancellation
                )
            )
        }
        do {
            _ = try await ordinaryTask.value
            XCTFail("Ordinary cancellation transition unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .cancelled)
        }

        let prebuiltTask = Task { () throws -> State in
            withUnsafeCurrentTask { $0?.cancel() }
            return try loading.recordingCancellation(
                expected: loading.fingerprint,
                operation: token,
                cancellation: prebuiltCancellation
            )
        }
        let prebuiltRecorded = try await prebuiltTask.value
        XCTAssertEqual(prebuiltRecorded.phase, .canceled)
        XCTAssertEqual(prebuiltRecorded.generation, loading.generation + 1)
        XCTAssertEqual(prebuiltRecorded.cancellation?.cancellation, prebuiltCancellation)

        let constructingTask = Task { () throws -> State in
            withUnsafeCurrentTask { $0?.cancel() }
            return try loading.recordingCancellation(
                expected: loading.fingerprint,
                operation: token,
                reason: .sessionClosing,
                stage: .publishing,
                detail: "Closing"
            )
        }
        let constructedRecorded = try await constructingTask.value
        XCTAssertEqual(constructedRecorded.phase, .canceled)
        XCTAssertEqual(constructedRecorded.cancellation?.cancellation.reason, .sessionClosing)
        XCTAssertEqual(constructedRecorded.cancellation?.cancellation.stage, .publishing)
        XCTAssertEqual(constructedRecorded.cancellation?.cancellation.detail, "Closing")
    }

    func testPrecancelledRecordingCancellationEnforcesCumulativeTransitionWork() async throws {
        let progressDetail = "é"
        let cancellationDetail = "界"
        XCTAssertEqual(progressDetail.utf8.count, 2)
        XCTAssertEqual(cancellationDetail.utf8.count, 3)

        let exactLimits = Limits(
            maximumTransitionWorkUnits: 7,
            cancellationCheckInterval: 7
        )
        let exactLoading = try beginLoading(
            State(identity: comparisonIdentity(73), limits: exactLimits),
            inputs: makeInputs(identity: 74),
            operationID: 75,
            progress: try Progress(
                stage: .preparing,
                completedUnitCount: 0,
                detail: progressDetail
            )
        )
        let exactTask = Task { () throws -> State in
            withUnsafeCurrentTask { $0?.cancel() }
            return try exactLoading.recordingCancellation(
                expected: exactLoading.fingerprint,
                operation: try XCTUnwrap(exactLoading.operation?.token),
                reason: .userRequested,
                stage: .preparing,
                detail: cancellationDetail
            )
        }
        let exactRecorded = try await exactTask.value
        XCTAssertEqual(exactRecorded.phase, .canceled)
        XCTAssertEqual(exactRecorded.cancellation?.lastProgress.detail, progressDetail)
        XCTAssertEqual(
            exactRecorded.cancellation?.cancellation.detail,
            cancellationDetail
        )

        let oneLessLimits = Limits(
            maximumTransitionWorkUnits: 6,
            cancellationCheckInterval: 6
        )
        let oneLessLoading = try beginLoading(
            State(identity: comparisonIdentity(76), limits: oneLessLimits),
            inputs: makeInputs(identity: 77),
            operationID: 78,
            progress: try Progress(
                stage: .preparing,
                completedUnitCount: 0,
                detail: progressDetail
            )
        )
        let oneLessTask = Task { () throws -> State in
            withUnsafeCurrentTask { $0?.cancel() }
            return try oneLessLoading.recordingCancellation(
                expected: oneLessLoading.fingerprint,
                operation: try XCTUnwrap(oneLessLoading.operation?.token),
                reason: .userRequested,
                stage: .preparing,
                detail: cancellationDetail
            )
        }
        do {
            _ = try await oneLessTask.value
            XCTFail("One-less transition work unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .workLimitExceeded(maximum: 6))
        }
    }

    func testRecordingCancellationStillValidatesFingerprintTokenStageAndLimits() async throws {
        let limits = Limits(maximumCancellationDetailUTF8Bytes: 4)
        let empty = try State(identity: comparisonIdentity(80), limits: limits)
        let progress = try Progress(stage: .comparing, completedUnitCount: 1)
        let loading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 81),
            operationID: 82,
            progress: progress
        )
        let token = try XCTUnwrap(loading.operation?.token)
        let staleFingerprint = empty.fingerprint
        let task = Task { () throws -> State in
            withUnsafeCurrentTask { $0?.cancel() }
            return try loading.recordingCancellation(
                expected: staleFingerprint,
                operation: token,
                reason: .userRequested,
                stage: .preparing,
                detail: "12345"
            )
        }
        do {
            _ = try await task.value
            XCTFail("Stale recording unexpectedly succeeded")
        } catch {
            XCTAssertEqual(
                error as? StateError,
                .staleState(expected: staleFingerprint, actual: loading.fingerprint)
            )
        }

        assertStateError(.cancellationStageRegressed) {
            try loading.recordingCancellation(
                expected: loading.fingerprint,
                operation: token,
                reason: .userRequested,
                stage: .preparing
            )
        }
        assertStateError(.metadataTooLarge(field: .cancellationDetail, maximumBytes: 4)) {
            try loading.recordingCancellation(
                expected: loading.fingerprint,
                operation: token,
                reason: .userRequested,
                stage: .comparing,
                detail: "12345"
            )
        }

        let otherLoading = try beginLoading(
            State(identity: comparisonIdentity(83), limits: limits),
            inputs: makeInputs(identity: 84),
            operationID: 85,
            progress: progress
        )
        let wrongToken = try XCTUnwrap(otherLoading.operation?.token)
        assertStateError(.staleOperation(expected: wrongToken, actual: token)) {
            try loading.recordingCancellation(
                expected: loading.fingerprint,
                operation: wrongToken,
                reason: .userRequested,
                stage: .comparing
            )
        }
    }

    func testTaskCancellationPrecedesFingerprintAvailabilityAndPayloadErrors() async throws {
        let empty = try State(identity: comparisonIdentity(90))
        let inputs = try makeInputs(identity: 91)
        let loading = try beginLoading(empty, inputs: inputs, operationID: 92)
        let token = try XCTUnwrap(loading.operation?.token)
        let completedResultID = resultID(93)
        let task = Task { () throws -> State in
            withUnsafeCurrentTask { $0?.cancel() }
            return try loading.applying(
                .complete(
                    expected: empty.fingerprint,
                    operation: token,
                    resultID: completedResultID
                )
            )
        }
        do {
            _ = try await task.value
            XCTFail("Canceled malformed transition unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .cancelled)
        }

        let validateTask = Task { () throws -> Void in
            withUnsafeCurrentTask { $0?.cancel() }
            try loading.validate(empty.fingerprint)
        }
        do {
            try await validateTask.value
            XCTFail("Canceled fingerprint validation unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .cancelled)
        }

        let availabilityTask = Task { () throws -> State in
            withUnsafeCurrentTask { $0?.cancel() }
            return try empty.applying(.reset(expected: empty.fingerprint))
        }
        do {
            _ = try await availabilityTask.value
            XCTFail("Canceled disabled command unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .cancelled)
        }

        let invalidFailure = try makeFailure(stage: .comparing, side: .middle)
        let invalidPayloadTask = Task { () throws -> State in
            withUnsafeCurrentTask { $0?.cancel() }
            return try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: invalidFailure
                )
            )
        }
        do {
            _ = try await invalidPayloadTask.value
            XCTFail("Canceled invalid payload unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .cancelled)
        }
    }

    func testFingerprintMatchingObservesTaskCancellation() async throws {
        let progress = try Progress(
            stage: .preparing,
            completedUnitCount: 0,
            detail: String(repeating: "x", count: 4_096)
        )
        let empty = try State(identity: comparisonIdentity(100))
        let loading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 101),
            operationID: 102,
            progress: progress
        )
        let fingerprint = loading.fingerprint
        let task = Task { () throws -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return try fingerprint.matches(loading)
        }
        do {
            _ = try await task.value
            XCTFail("Canceled fingerprint comparison unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? StateError, .cancelled)
        }
    }

    func testValidationErrorPrecedenceIsDeterministic() throws {
        let limits = Limits(
            maximumFailureCodeUTF8Bytes: 3,
            maximumFailureMessageUTF8Bytes: 4,
            maximumProgressDetailUTF8Bytes: 4,
            maximumCancellationDetailUTF8Bytes: 4,
            maximumTotalMetadataUTF8Bytes: 11,
            maximumDeclaredWorkUnits: 5
        )
        let empty = try State(identity: comparisonIdentity(110), limits: limits)
        let inputs = try makeInputs(identity: 111)
        let binding = side(.left, identity: 112)

        assertStateError(.commandDisabled(.noOnlySideLoaded)) {
            try empty.applying(
                .unloadOnlySide(expected: empty.fingerprint, binding: binding)
            )
        }

        let oneSide = try empty.applying(
            .loadFirstSide(expected: empty.fingerprint, binding: binding)
        )
        assertStateError(.declaredWorkLimitExceeded(maximum: 5)) {
            try beginLoading(
                oneSide,
                inputs: try makeInputs(identity: 113, leftIdentity: 112),
                operationID: 114,
                declaredWorkUnits: 6,
                progress: try Progress(
                    stage: .preparing,
                    completedUnitCount: 0,
                    detail: "12345"
                )
            )
        }
        let mismatchedInputs = try makeInputs(identity: 116, leftIdentity: 117)
        assertStateError(.sideBindingMismatch(expected: binding, actual: mismatchedInputs[.left])) {
            try beginLoading(
                oneSide,
                inputs: mismatchedInputs,
                operationID: 118,
                declaredWorkUnits: 6,
                progress: try Progress(
                    stage: .preparing,
                    completedUnitCount: 0,
                    detail: "12345"
                )
            )
        }

        let loading = try beginLoading(
            empty,
            inputs: inputs,
            operationID: 115,
            progress: try Progress(stage: .comparing, completedUnitCount: 1)
        )
        let token = try XCTUnwrap(loading.operation?.token)
        let otherLoading = try beginLoading(
            State(identity: comparisonIdentity(120), limits: limits),
            inputs: inputs,
            operationID: 121
        )
        let staleToken = try XCTUnwrap(otherLoading.operation?.token)
        assertStateError(.staleOperation(expected: staleToken, actual: token)) {
            try loading.applying(
                .updateProgress(
                    expected: loading.fingerprint,
                    operation: staleToken,
                    progress: try Progress(
                        stage: .loadingInputs,
                        completedUnitCount: 0,
                        detail: "12345"
                    )
                )
            )
        }
        assertStateError(.staleOperation(expected: staleToken, actual: token)) {
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: staleToken,
                    failure: try makeFailure(code: "ABCD", message: "12345", stage: .preparing)
                )
            )
        }
        assertStateError(.staleOperation(expected: staleToken, actual: token)) {
            try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: staleToken,
                    cancellation: try State.Cancellation(
                        reason: .userRequested,
                        stage: .preparing,
                        detail: "12345"
                    )
                )
            )
        }
        let current = try complete(loading, resultID: 116)
        assertStateError(.commandDisabled(.initialLoadUnavailable(.current))) {
            try beginLoading(
                current,
                inputs: mismatchedInputs,
                operationID: 119,
                declaredWorkUnits: 6,
                progress: try Progress(
                    stage: .preparing,
                    completedUnitCount: 0,
                    detail: "12345"
                )
            )
        }
        assertStateError(.invalidFailureSide(.middle)) {
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: try makeFailure(
                        code: "ABCD",
                        message: "12345",
                        stage: .preparing,
                        side: .middle
                    )
                )
            )
        }
        assertStateError(.metadataTooLarge(field: .failureMessage, maximumBytes: 4)) {
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: try makeFailure(code: "A", message: "12345", stage: .preparing)
                )
            )
        }
        assertStateError(.metadataTooLarge(field: .failureCode, maximumBytes: 3)) {
            try loading.applying(
                .fail(
                    expected: loading.fingerprint,
                    operation: token,
                    failure: try makeFailure(code: "ABCD", message: "12345", stage: .preparing)
                )
            )
        }
        assertStateError(.metadataTooLarge(field: .cancellationDetail, maximumBytes: 4)) {
            try loading.applying(
                .cancel(
                    expected: loading.fingerprint,
                    operation: token,
                    cancellation: try State.Cancellation(
                        reason: .userRequested,
                        stage: .preparing,
                        detail: "12345"
                    )
                )
            )
        }

        let staleFingerprint = empty.fingerprint
        assertStateError(.staleState(expected: staleFingerprint, actual: loading.fingerprint)) {
            try loading.applying(.reset(expected: staleFingerprint))
        }
    }

    func testCanonicalMetadataUsesExactUTF8AndKeepsFingerprintMatchingAligned() throws {
        let decomposed = "e\u{301}"
        let normalized = "é"
        let empty = try State(identity: comparisonIdentity(120))
        let decomposedLoading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 121),
            operationID: 122,
            progress: try Progress(
                stage: .preparing,
                completedUnitCount: 0,
                detail: decomposed
            )
        )
        let normalizedLoading = try beginLoading(
            empty,
            inputs: makeInputs(identity: 121),
            operationID: 122,
            progress: try Progress(
                stage: .preparing,
                completedUnitCount: 0,
                detail: normalized
            )
        )
        XCTAssertEqual(
            Array(try XCTUnwrap(decomposedLoading.operation?.progress.detail).utf8),
            [0xC3, 0xA9]
        )
        XCTAssertEqual(
            Array(try XCTUnwrap(normalizedLoading.operation?.progress.detail).utf8),
            [0xC3, 0xA9]
        )
        XCTAssertEqual(decomposedLoading, normalizedLoading)
        XCTAssertEqual(decomposedLoading.fingerprint, normalizedLoading.fingerprint)
        XCTAssertTrue(try decomposedLoading.fingerprint.matches(normalizedLoading))
        XCTAssertTrue(try normalizedLoading.fingerprint.matches(decomposedLoading))

        let token = try XCTUnwrap(decomposedLoading.operation?.token)
        let decomposedFailed = try decomposedLoading.applying(
            .fail(
                expected: decomposedLoading.fingerprint,
                operation: token,
                failure: try makeFailure(message: decomposed)
            )
        )
        let normalizedFailed = try normalizedLoading.applying(
            .fail(
                expected: normalizedLoading.fingerprint,
                operation: token,
                failure: try makeFailure(message: normalized)
            )
        )
        XCTAssertEqual(
            Array(try XCTUnwrap(decomposedFailed.failure?.failure.message).utf8),
            [0xC3, 0xA9]
        )
        XCTAssertEqual(
            Array(try XCTUnwrap(normalizedFailed.failure?.failure.message).utf8),
            [0xC3, 0xA9]
        )
        XCTAssertEqual(decomposedFailed.fingerprint, normalizedFailed.fingerprint)
        XCTAssertTrue(try decomposedFailed.fingerprint.matches(normalizedFailed))

        let decomposedCanceled = try decomposedLoading.applying(
            .cancel(
                expected: decomposedLoading.fingerprint,
                operation: token,
                cancellation: try State.Cancellation(
                    reason: .userRequested,
                    stage: .preparing,
                    detail: decomposed
                )
            )
        )
        let normalizedCanceled = try normalizedLoading.applying(
            .cancel(
                expected: normalizedLoading.fingerprint,
                operation: token,
                cancellation: try State.Cancellation(
                    reason: .userRequested,
                    stage: .preparing,
                    detail: normalized
                )
            )
        )
        XCTAssertEqual(
            Array(try XCTUnwrap(decomposedCanceled.cancellation?.cancellation.detail).utf8),
            [0xC3, 0xA9]
        )
        XCTAssertEqual(decomposedCanceled.fingerprint, normalizedCanceled.fingerprint)
        XCTAssertTrue(try decomposedCanceled.fingerprint.matches(normalizedCanceled))
        let distinctCanceled = try normalizedLoading.applying(
            .cancel(
                expected: normalizedLoading.fingerprint,
                operation: token,
                cancellation: try State.Cancellation(
                    reason: .userRequested,
                    stage: .preparing,
                    detail: "different"
                )
            )
        )
        XCTAssertNotEqual(normalizedCanceled.fingerprint, distinctCanceled.fingerprint)
        XCTAssertFalse(try normalizedCanceled.fingerprint.matches(distinctCanceled))
    }

    func testResetMatrixClearsEveryRetainedFieldPreservesIdentityAndLimits() throws {
        let limits = Limits(maximumProgressUnitCount: 10)
        let empty = try State(identity: comparisonIdentity(129), limits: limits)
        assertStateError(.commandDisabled(.alreadyEmpty)) {
            try empty.applying(.reset(expected: empty.fingerprint))
        }
        let loaded = try empty.applying(
            .loadFirstSide(expected: empty.fingerprint, binding: side(.left, identity: 130))
        )
        let resetLoaded = try loaded.applying(.reset(expected: loaded.fingerprint))
        XCTAssertEqual(resetLoaded.identity, empty.identity)
        XCTAssertEqual(resetLoaded.limits, limits)
        XCTAssertEqual(resetLoaded.generation, loaded.generation + 1)
        XCTAssertEqual(resetLoaded.phase, .empty)
        XCTAssertNil(resetLoaded.loadedSide)

        let fixture = try makeCurrentFixture(comparisonIdentity: 130, inputIdentity: 131)
        let stale = try markStale(
            fixture.state,
            inputs: makeInputs(identity: 132, leftIdentity: 133, rightIdentity: 3),
            reason: .sideChanged(.left)
        )
        let refresh = try beginRefreshing(stale, operationID: 134)
        let token = try XCTUnwrap(refresh.operation?.token)
        let failed = try refresh.applying(
            .fail(
                expected: refresh.fingerprint,
                operation: token,
                failure: try makeFailure(stage: .preparing, isRetryable: true)
            )
        )
        let reset = try failed.applying(.reset(expected: failed.fingerprint))
        XCTAssertEqual(reset.identity, fixture.state.identity)
        XCTAssertEqual(reset.generation, failed.generation + 1)
        XCTAssertEqual(reset.phase, .empty)
        XCTAssertNil(reset.loadedSide)
        XCTAssertNil(reset.inputs)
        XCTAssertNil(reset.operation)
        XCTAssertNil(reset.result)
        XCTAssertNil(reset.staleness)
        XCTAssertNil(reset.failure)
        XCTAssertNil(reset.cancellation)
        XCTAssertFalse(reset.hasCurrentResult)
        XCTAssertFalse(reset.hasRetainedResult)
        XCTAssertEqual(reset.availability(for: .reset), .disabled(.alreadyEmpty))

        let initialEmpty = try State(identity: comparisonIdentity(136))
        let initialLoading = try beginLoading(
            initialEmpty,
            inputs: makeInputs(identity: 137),
            operationID: 138
        )
        let initialToken = try XCTUnwrap(initialLoading.operation?.token)
        let initialFailed = try initialLoading.applying(
            .fail(
                expected: initialLoading.fingerprint,
                operation: initialToken,
                failure: try makeFailure(isRetryable: true)
            )
        )
        let secondInitialLoading = try beginLoading(
            initialEmpty,
            inputs: makeInputs(identity: 137),
            operationID: 139
        )
        let secondInitialToken = try XCTUnwrap(secondInitialLoading.operation?.token)
        let initialCanceled = try secondInitialLoading.applying(
            .cancel(
                expected: secondInitialLoading.fingerprint,
                operation: secondInitialToken,
                cancellation: try State.Cancellation(reason: .userRequested, stage: .preparing)
            )
        )
        for source in [fixture.state, stale, initialFailed, initialCanceled] {
            let cleared = try source.applying(.reset(expected: source.fingerprint))
            XCTAssertEqual(cleared.identity, source.identity, "reset from \(source.phase)")
            XCTAssertEqual(cleared.limits, source.limits, "reset from \(source.phase)")
            XCTAssertEqual(cleared.generation, source.generation + 1, "reset from \(source.phase)")
            XCTAssertEqual(cleared.phase, .empty, "reset from \(source.phase)")
            XCTAssertNil(cleared.loadedSide, "reset from \(source.phase)")
            XCTAssertNil(cleared.inputs, "reset from \(source.phase)")
            XCTAssertNil(cleared.operation, "reset from \(source.phase)")
            XCTAssertNil(cleared.result, "reset from \(source.phase)")
            XCTAssertNil(cleared.staleness, "reset from \(source.phase)")
            XCTAssertNil(cleared.failure, "reset from \(source.phase)")
            XCTAssertNil(cleared.cancellation, "reset from \(source.phase)")
        }

        let cancelingRefresh = try beginRefreshing(stale, operationID: 135)
        let cancellationToken = try XCTUnwrap(cancelingRefresh.operation?.token)
        let canceled = try cancelingRefresh.applying(
            .cancel(
                expected: cancelingRefresh.fingerprint,
                operation: cancellationToken,
                cancellation: try State.Cancellation(
                    reason: .sessionClosing,
                    stage: .preparing,
                    detail: "Closing"
                )
            )
        )
        let resetCanceled = try canceled.applying(.reset(expected: canceled.fingerprint))
        XCTAssertEqual(resetCanceled.identity, canceled.identity)
        XCTAssertEqual(resetCanceled.limits, canceled.limits)
        XCTAssertEqual(resetCanceled.generation, canceled.generation + 1)
        XCTAssertEqual(resetCanceled.phase, .empty)
        XCTAssertNil(resetCanceled.loadedSide)
        XCTAssertNil(resetCanceled.inputs)
        XCTAssertNil(resetCanceled.operation)
        XCTAssertNil(resetCanceled.result)
        XCTAssertNil(resetCanceled.staleness)
        XCTAssertNil(resetCanceled.failure)
        XCTAssertNil(resetCanceled.cancellation)

        let activeInitial = try beginLoading(empty, inputs: makeInputs(identity: 136), operationID: 137)
        let activeRefresh = try beginRefreshing(stale, operationID: 138)
        for active in [activeInitial, activeRefresh] {
            let generation = active.generation
            assertStateError(.commandDisabled(.operationInProgress(try XCTUnwrap(active.operation?.token.operationID)))) {
                try active.applying(.reset(expected: active.fingerprint))
            }
            XCTAssertEqual(active.generation, generation)
            XCTAssertNotNil(active.operation)
        }
    }

    func testEveryStateErrorHasExactCustomErrorDescription() throws {
        let empty = try State(identity: comparisonIdentity(140))
        let binding = side(.left, identity: 141)
        let inputs = try makeInputs(identity: 142)
        let loading = try beginLoading(empty, inputs: inputs, operationID: 143)
        let token = try XCTUnwrap(loading.operation?.token)
        let otherLoading = try beginLoading(
            State(identity: comparisonIdentity(144)),
            inputs: inputs,
            operationID: 145
        )
        let otherToken = try XCTUnwrap(otherLoading.operation?.token)
        let cases: [(StateError, String)] = [
            (.cancelled, "Comparison lifecycle work was canceled."),
            (.invalidLimit(.failureCodeUTF8Bytes), "Comparison lifecycle limit is invalid: failureCodeUTF8Bytes."),
            (.invalidInputSideCount(1), "Comparison inputs require two or three sides, not 1."),
            (.duplicateInputSide(.left), "Comparison inputs contain duplicate left sides."),
            (
                .invalidInputSides(hasLeft: true, hasMiddle: true, hasRight: false),
                "Comparison input side layout is invalid (left: true, middle: true, right: false)."
            ),
            (.staleState(expected: empty.fingerprint, actual: loading.fingerprint), "Comparison lifecycle state changed from generation 0 to 1."),
            (.staleOperation(expected: otherToken, actual: token), "Comparison lifecycle operation identity does not match the active operation."),
            (.commandDisabled(.alreadyEmpty), "Comparison lifecycle command is disabled: alreadyEmpty."),
            (.sideBindingMismatch(expected: binding, actual: nil), "Comparison inputs omit the loaded side."),
            (
                .sideBindingMismatch(expected: binding, actual: side(.left, identity: 146)),
                "Comparison side identity or generation does not match the loaded side."
            ),
            (
                .inputBindingMismatch(expected: inputs, actual: try makeInputs(identity: 147)),
                "Comparison input identity or generation does not match current inputs."
            ),
            (.unchangedInputs, "A current comparison cannot become stale without a new input identity or generation."),
            (.unchangedComparisonMode, "Comparison-mode staleness requires a change between two-way and three-way inputs."),
            (.invalidStaleSide(.middle), "Comparison staleness names a side outside the previous and current inputs: middle."),
            (.invalidFailureSide(.middle), "Comparison failure names a side outside the active operation inputs: middle."),
            (.duplicateOperationID(operationID(148)), "A completed operation identity cannot be reused by the retained comparison result."),
            (.generationExhausted, "Comparison lifecycle generation space is exhausted; allocate a new identity."),
            (.invalidProgressTotal, "Comparison progress requires a positive total no smaller than completed work."),
            (.progressUnitLimitExceeded(maximum: 1), "Comparison progress exceeds the 1-unit limit."),
            (.progressRegressed, "Comparison progress stage or completed count moved backward."),
            (.progressTotalChanged, "Comparison progress total changed within one stage."),
            (.invalidFailureCode, "Comparison failure code must be nonempty ASCII letters, digits, period, underscore, or hyphen."),
            (.invalidMetadataText(.failureMessage), "Comparison lifecycle failureMessage contains unsupported control characters."),
            (.metadataTooLarge(field: .failureMessage, maximumBytes: 1), "Comparison lifecycle failureMessage exceeds 1 UTF-8 bytes."),
            (.totalMetadataTooLarge(maximumBytes: 1), "Comparison lifecycle metadata exceeds 1 total UTF-8 bytes."),
            (.failureStageRegressed, "Comparison failure stage precedes the last reported progress stage."),
            (.cancellationStageRegressed, "Comparison cancellation stage precedes the last reported progress stage."),
            (.declaredWorkLimitExceeded(maximum: 1), "Comparison operation exceeds the 1-unit declared work limit."),
            (.workLimitExceeded(maximum: 1), "Comparison lifecycle transition exceeds the 1-unit work limit.")
        ]
        XCTAssertEqual(cases.count, 29)
        for (error, expected) in cases {
            guard let description = error.errorDescription else {
                XCTFail("Missing errorDescription for \(error)")
                continue
            }
            XCTAssertEqual(description, expected, "\(error)")
        }
    }

    private struct CurrentFixture {
        let state: State
        let inputs: InputBinding
        let result: State.ResultBinding
    }

    private func makeCurrentFixture(
        comparisonIdentity comparisonIdentityValue: UInt8,
        inputIdentity inputIdentityValue: UInt8 = 1,
        inputs suppliedInputs: InputBinding? = nil,
        operationID operationIDValue: UInt8 = 4,
        resultID resultIDValue: UInt8 = 5,
        limits: Limits = .default
    ) throws -> CurrentFixture {
        let inputs = try suppliedInputs ?? makeInputs(identity: inputIdentityValue)
        let empty = try State(
            identity: comparisonIdentity(comparisonIdentityValue),
            limits: limits
        )
        let loading = try beginLoading(
            empty,
            inputs: inputs,
            operationID: operationIDValue
        )
        let current = try complete(loading, resultID: resultIDValue)
        return CurrentFixture(
            state: current,
            inputs: inputs,
            result: try XCTUnwrap(current.result)
        )
    }

    private func beginLoading(
        _ state: State,
        inputs: InputBinding,
        operationID operationIDValue: UInt8,
        declaredWorkUnits: UInt64 = 0,
        progress: Progress = .pending
    ) throws -> State {
        try state.applying(
            .beginLoading(
                expected: state.fingerprint,
                inputs: inputs,
                operationID: operationID(operationIDValue),
                declaredWorkUnits: declaredWorkUnits,
                progress: progress
            )
        )
    }

    private func beginRefreshing(
        _ state: State,
        operationID operationIDValue: UInt8,
        declaredWorkUnits: UInt64 = 0,
        progress: Progress = .pending
    ) throws -> State {
        try state.applying(
            .beginRefreshing(
                expected: state.fingerprint,
                operationID: operationID(operationIDValue),
                declaredWorkUnits: declaredWorkUnits,
                progress: progress
            )
        )
    }

    private func complete(_ state: State, resultID resultIDValue: UInt8) throws -> State {
        try state.applying(
            .complete(
                expected: state.fingerprint,
                operation: try XCTUnwrap(state.operation?.token),
                resultID: resultID(resultIDValue)
            )
        )
    }

    private func markStale(
        _ state: State,
        inputs: InputBinding,
        reason: State.StaleReason
    ) throws -> State {
        try state.applying(
            .markStale(
                expected: state.fingerprint,
                currentInputs: inputs,
                reason: reason
            )
        )
    }

    private func makeInputs(
        identity identityValue: UInt8,
        generation: UInt64 = 0,
        leftIdentity: UInt8 = 2,
        leftGeneration: UInt64 = 0,
        middleIdentity: UInt8? = nil,
        middleGeneration: UInt64 = 0,
        rightIdentity: UInt8 = 3,
        rightGeneration: UInt64 = 0
    ) throws -> InputBinding {
        var sides = [
            side(.left, identity: leftIdentity, generation: leftGeneration)
        ]
        if let middleIdentity {
            sides.append(
                side(.middle, identity: middleIdentity, generation: middleGeneration)
            )
        }
        sides.append(side(.right, identity: rightIdentity, generation: rightGeneration))
        return try InputBinding(
            identity: inputIdentity(identityValue),
            generation: generation,
            sides: sides
        )
    }

    private func makeFailure(
        kind: State.FailureKind = .comparisonFailed,
        code: String = "COMPARE_FAILED",
        message: String = "Comparison failed",
        stage: Progress.Stage = .preparing,
        side: State.Side? = nil,
        isRetryable: Bool = false
    ) throws -> State.Failure {
        try State.Failure(
            kind: kind,
            code: code,
            message: message,
            stage: stage,
            side: side,
            isRetryable: isRetryable
        )
    }

    private func limits(fieldMaximums: [Int], total: Int) -> Limits {
        precondition(fieldMaximums.count == 4)
        return Limits(
            maximumFailureCodeUTF8Bytes: fieldMaximums[0],
            maximumFailureMessageUTF8Bytes: fieldMaximums[1],
            maximumProgressDetailUTF8Bytes: fieldMaximums[2],
            maximumCancellationDetailUTF8Bytes: fieldMaximums[3],
            maximumTotalMetadataUTF8Bytes: total
        )
    }

    private func inactiveAvailability(
        beginLoading: AvailabilityReason,
        markStale: AvailabilityReason,
        beginRefreshing: AvailabilityReason,
        reset: AvailabilityReason,
        unload: AvailabilityReason = .disabled(.noOnlySideLoaded)
    ) -> [Command: AvailabilityReason] {
        [
            .loadFirstSide: .disabled(.sideAlreadyLoaded),
            .unloadOnlySide: unload,
            .beginLoading: beginLoading,
            .markStale: markStale,
            .beginRefreshing: beginRefreshing,
            .updateProgress: .disabled(.noActiveOperation),
            .complete: .disabled(.noActiveOperation),
            .fail: .disabled(.noActiveOperation),
            .cancel: .disabled(.noActiveOperation),
            .reset: reset
        ]
    }

    private func activeAvailability(operationID: State.OperationID) -> [Command: AvailabilityReason] {
        [
            .loadFirstSide: .disabled(.operationInProgress(operationID)),
            .unloadOnlySide: .disabled(.operationInProgress(operationID)),
            .beginLoading: .disabled(.operationInProgress(operationID)),
            .markStale: .disabled(.operationInProgress(operationID)),
            .beginRefreshing: .disabled(.operationInProgress(operationID)),
            .updateProgress: .enabled(.operationMayProgress(operationID)),
            .complete: .enabled(.operationMayComplete(operationID)),
            .fail: .enabled(.operationMayFail(operationID)),
            .cancel: .enabled(.operationMayCancel(operationID)),
            .reset: .disabled(.operationInProgress(operationID))
        ]
    }

    private func assertAvailability(
        _ state: State,
        _ expected: [Command: AvailabilityReason],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expected.count, Command.allCases.count, file: file, line: line)
        for command in Command.allCases {
            guard let expectedReason = expected[command] else {
                XCTFail("Missing expected availability for \(command)", file: file, line: line)
                continue
            }
            let actual = state.availability(for: command)
            XCTAssertEqual(actual, expectedReason, "\(state.phase) \(command)", file: file, line: line)
            XCTAssertEqual(actual.availability, expectedReason.availability, file: file, line: line)
        }
    }

    private func assertFingerprintDifference(
        _ left: State,
        _ right: State,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(left.identity, right.identity, message, file: file, line: line)
        XCTAssertEqual(left.generation, right.generation, message, file: file, line: line)
        XCTAssertNotEqual(left, right, message, file: file, line: line)
        XCTAssertNotEqual(left.fingerprint, right.fingerprint, message, file: file, line: line)
        XCTAssertFalse(try left.fingerprint.matches(right), message, file: file, line: line)
        XCTAssertFalse(try right.fingerprint.matches(left), message, file: file, line: line)
    }

    private func assertStateError<T>(
        _ expected: StateError,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> T
    ) {
        do {
            _ = try body()
            XCTFail("Expected \(expected). \(message)", file: file, line: line)
        } catch let error as StateError {
            XCTAssertEqual(error, expected, message, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error). \(message)", file: file, line: line)
        }
    }

    private func side(
        _ side: State.Side,
        identity identityValue: UInt8,
        generation: UInt64 = 0
    ) -> State.SideBinding {
        State.SideBinding(
            side: side,
            identity: sideIdentity(identityValue),
            generation: generation
        )
    }

    private func comparisonIdentity(_ value: UInt8) -> State.Identity {
        State.Identity(rawValue: uuid(value))
    }

    private func inputIdentity(_ value: UInt8) -> State.InputIdentity {
        State.InputIdentity(rawValue: uuid(value))
    }

    private func sideIdentity(_ value: UInt8) -> State.SideIdentity {
        State.SideIdentity(rawValue: uuid(value))
    }

    private func operationID(_ value: UInt8) -> State.OperationID {
        State.OperationID(rawValue: uuid(value))
    }

    private func resultID(_ value: UInt8) -> State.ResultID {
        State.ResultID(rawValue: uuid(value))
    }

    private func uuid(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
