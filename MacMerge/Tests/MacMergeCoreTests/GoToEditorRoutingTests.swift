import Foundation
import XCTest

@testable import MacMergeCore

final class GoToEditorRoutingTests: XCTestCase {
    private let identity = TextGoToDocumentIdentity(
        rawValue: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    )

    func testAllTargetKindsRouteToExpectedSelections() throws {
        let bookmarks = try LineBookmarks(lines: [2])
        let document = makeDocument(
            "one\ntwo\nthree",
            differences: [TextGoToDifference(selectionRange: NSRange(location: 1, length: 1))],
            bookmarks: bookmarks
        )

        let line = try GoToEditorRouting.route(
            TextGoToRequest(document: document, target: .line(TextPosition(line: 2))),
            in: document
        )
        XCTAssertEqual(line.target, .line(requested: TextPosition(line: 2)))
        XCTAssertEqual(line.selectionRange, NSRange(location: 4, length: 0))
        XCTAssertTrue(line.isInsertionPoint)
        XCTAssertEqual(line.position, TextPosition(line: 2))

        let percent = try GoToEditorRouting.route(
            TextGoToRequest(document: document, target: .percent(100)),
            in: document
        )
        XCTAssertEqual(percent.target, .percent(requested: 100, resolvedLine: 3))
        XCTAssertEqual(percent.selectionRange, NSRange(location: 8, length: 0))
        XCTAssertTrue(percent.isInsertionPoint)

        let difference = try GoToEditorRouting.route(
            TextGoToRequest(document: document, target: .difference(1)),
            in: document
        )
        XCTAssertEqual(difference.target, .difference(index: 1))
        XCTAssertEqual(difference.selectionRange, NSRange(location: 1, length: 1))
        XCTAssertFalse(difference.isInsertionPoint)

        let bookmark = try GoToEditorRouting.route(
            TextGoToRequest(document: document, target: .bookmark(line: 2)),
            in: document
        )
        XCTAssertEqual(bookmark.target, .bookmark(line: 2))
        XCTAssertEqual(bookmark.selectionRange, NSRange(location: 4, length: 0))

        let offset = try GoToEditorRouting.route(
            TextGoToRequest(document: document, target: .utf16Offset(1)),
            in: document
        )
        XCTAssertEqual(offset.target, .utf16Offset(1))
        XCTAssertEqual(offset.selectionRange, NSRange(location: 1, length: 0))
        XCTAssertTrue(offset.isInsertionPoint)

        for routed in [line, percent, difference, bookmark, offset] {
            XCTAssertEqual(routed.documentIdentity, identity)
            XCTAssertEqual(routed.documentRevision, 1)
        }
    }

    func testTargetConvenienceOverloadMatchesRequestOverload() throws {
        let document = makeDocument("one\ntwo\nthree")
        let target = TextGoToTarget.line(TextPosition(line: 3))
        let viaTarget = try GoToEditorRouting.route(target: target, in: document)
        let viaRequest = try GoToEditorRouting.route(
            TextGoToRequest(document: document, target: target),
            in: document
        )
        XCTAssertEqual(viaTarget, viaRequest)
    }

    func testEditorRequestMirrorsUnderlyingResolution() throws {
        let document = makeDocument(
            "ab\nc",
            differences: [TextGoToDifference(selectionRange: NSRange(location: 1, length: 1))]
        )
        let request = TextGoToRequest(document: document, target: .difference(1))
        let resolution = try TextGoTo.resolve(request, in: document)
        let routed = try GoToEditorRouting.route(request, in: document)
        XCTAssertEqual(routed, GoToEditorRouting.EditorRequest(resolution: resolution))
        XCTAssertEqual(routed.selectionStart, resolution.selectionStart)
        XCTAssertEqual(routed.selectionEnd, resolution.selectionEnd)
        XCTAssertEqual(routed.workUnitsConsumed, resolution.workUnitsConsumed)
    }

    func testStaleIdentityRejectedBeforeMetadataValidation() throws {
        let otherIdentity = TextGoToDocumentIdentity(
            rawValue: UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!
        )
        let document = makeDocument(
            "text",
            revision: 9,
            differences: [TextGoToDifference(selectionRange: NSRange(location: -1, length: 0))]
        )
        assertRoutingError(
            .goTo(.documentIdentityChanged(expected: otherIdentity, actual: identity))
        ) {
            try GoToEditorRouting.route(
                TextGoToRequest(
                    documentIdentity: otherIdentity,
                    documentRevision: 9,
                    target: .difference(1)
                ),
                in: document
            )
        }
    }

    func testStaleRevisionRejected() throws {
        let document = makeDocument("text", revision: 9)
        assertRoutingError(.goTo(.documentRevisionChanged(expected: 8, actual: 9))) {
            try GoToEditorRouting.route(
                TextGoToRequest(
                    documentIdentity: self.identity,
                    documentRevision: 8,
                    target: .line(TextPosition(line: 1))
                ),
                in: document
            )
        }
    }

    func testGraphemeSplittingOffsetIsWrapped() {
        let document = makeDocument("A🇺🇸e")
        assertRoutingError(.goTo(.navigation(.offsetSplitsCharacter(2)))) {
            try GoToEditorRouting.route(
                TextGoToRequest(document: document, target: .utf16Offset(2)),
                in: document
            )
        }
    }

    func testDifferenceEndpointsMustBeGraphemeBoundaries() {
        let text = "🇺🇸ab"
        let range = NSRange(location: 1, length: 1)
        let document = makeDocument(
            text,
            differences: [TextGoToDifference(selectionRange: range)]
        )
        assertRoutingError(
            .goTo(.invalidDifferenceRange(index: 1, location: 1, length: 1))
        ) {
            try GoToEditorRouting.route(
                TextGoToRequest(document: document, target: .difference(1)),
                in: document
            )
        }
    }

    func testInvalidLimitsAreWrapped() {
        let document = makeDocument("")
        let limits = GoToEditorRouting.Limits(
            goTo: TextGoToLimits(
                navigation: .default,
                maximumDifferences: 100,
                maximumBookmarks: 100,
                maximumGraphemeClusterUTF16Length: 100,
                maximumWork: -1
            )
        )
        assertRoutingError(.goTo(.invalidLimits)) {
            try GoToEditorRouting.route(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                in: document,
                limits: limits
            )
        }
    }

    func testMetadataAndWorkLimitsAreWrapped() throws {
        let bookmarks = try LineBookmarks(lines: [1, 2])
        let document = makeDocument(
            "a\nb",
            differences: [
                TextGoToDifference(selectionRange: NSRange(location: 0, length: 0)),
                TextGoToDifference(selectionRange: NSRange(location: 1, length: 0))
            ],
            bookmarks: bookmarks
        )
        assertRoutingError(.goTo(.tooManyDifferences(maximumDifferences: 1))) {
            try GoToEditorRouting.route(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                in: document,
                limits: routingLimits(maximumDifferences: 1, maximumBookmarks: 2)
            )
        }
        assertRoutingError(.goTo(.tooManyBookmarks(maximumBookmarks: 1))) {
            try GoToEditorRouting.route(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                in: document,
                limits: routingLimits(maximumDifferences: 2, maximumBookmarks: 1)
            )
        }
        assertRoutingError(.goTo(.workLimitExceeded(maximumWork: 0))) {
            try GoToEditorRouting.route(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                in: document,
                limits: routingLimits(maximumWork: 0)
            )
        }
    }

    func testErrorWrappingPreservesUnderlyingError() {
        let underlying = TextGoToError.lineIsNotBookmarked(3)
        let wrapped = GoToEditorRoutingError.goTo(underlying)
        XCTAssertEqual(wrapped.localizedDescription, underlying.localizedDescription)
        XCTAssertEqual(wrapped, GoToEditorRoutingError.goTo(.lineIsNotBookmarked(3)))

        let document = makeDocument("a\nb")
        assertRoutingError(.goTo(.lineIsNotBookmarked(2))) {
            try GoToEditorRouting.route(
                TextGoToRequest(document: document, target: .bookmark(line: 2)),
                in: document
            )
        }
        assertRoutingError(.goTo(.navigation(.invalidLine(9)))) {
            try GoToEditorRouting.route(
                TextGoToRequest(
                    document: document,
                    target: .line(TextPosition(line: 9))
                ),
                in: document
            )
        }
    }

    func testCancellationPropagatesUnwrapped() async {
        let inputLength = 8 * 1_024 * 1_024
        let document = makeDocument(String(repeating: "x", count: inputLength))
        let outcome = GoToRoutingCancellationState()
        let limits = routingLimits(
            maximumWork: .max,
            maximumInputUTF16Length: inputLength,
            maximumLineUTF16Length: inputLength
        )
        let task = Task.detached(priority: .userInitiated) {
            outcome.recordStart()
            do {
                _ = try GoToEditorRouting.route(
                    TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                    in: document,
                    limits: limits
                )
                outcome.recordCompletion(.succeeded)
            } catch is CancellationError {
                outcome.recordCompletion(.cancelled)
            } catch {
                outcome.recordCompletion(.failed(String(describing: error)))
            }
        }

        guard await outcome.waitUntilStarted(timeout: 5) else {
            task.cancel()
            _ = await outcome.waitUntilCompleted(timeout: 5)
            XCTFail("Routing did not start within bounded wait")
            return
        }
        guard outcome.cancelIfRunning({ task.cancel() }) else {
            XCTFail("Routing finished before cancellation could be requested")
            return
        }
        guard await outcome.waitUntilCompleted(timeout: 5) else {
            task.cancel()
            _ = await outcome.waitUntilCompleted(timeout: 5)
            XCTFail("Cancelled routing exceeded bounded wait")
            return
        }
        XCTAssertEqual(outcome.load(), .cancelled)
    }

    private func makeDocument(
        _ text: String,
        revision: UInt64 = 1,
        differences: [TextGoToDifference] = [],
        bookmarks: LineBookmarks = LineBookmarks()
    ) -> TextGoToDocumentSnapshot {
        TextGoToDocumentSnapshot(
            identity: identity,
            revision: revision,
            text: text,
            differences: differences,
            bookmarks: bookmarks
        )
    }

    private func routingLimits(
        maximumDifferences: Int = 100,
        maximumBookmarks: Int = 100,
        maximumWork: Int = 100_000,
        maximumInputUTF16Length: Int = 100_000,
        maximumLineUTF16Length: Int = 100_000
    ) -> GoToEditorRouting.Limits {
        GoToEditorRouting.Limits(
            goTo: TextGoToLimits(
                navigation: TextNavigationLimits(
                    maximumInputUTF16Length: maximumInputUTF16Length,
                    maximumLineCount: 100_000,
                    maximumLineUTF16Length: maximumLineUTF16Length,
                    maximumTokenCount: 100_000,
                    maximumSymbolCount: 100_000,
                    maximumSymbolNameUTF16Length: 100,
                    maximumLookupResults: 100
                ),
                maximumDifferences: maximumDifferences,
                maximumBookmarks: maximumBookmarks,
                maximumGraphemeClusterUTF16Length: 100,
                maximumWork: maximumWork
            )
        )
    }

    private func assertRoutingError(
        _ expected: GoToEditorRoutingError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> GoToEditorRouting.EditorRequest
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? GoToEditorRoutingError, expected, file: file, line: line)
        }
    }
}

private enum GoToRoutingCancellationOutcome: Equatable, Sendable {
    case pending
    case succeeded
    case cancelled
    case failed(String)
}

private final class GoToRoutingCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let completed = DispatchSemaphore(value: 0)
    private var didStart = false
    private var outcome = GoToRoutingCancellationOutcome.pending

    func recordStart() {
        lock.lock()
        didStart = true
        lock.unlock()
        started.signal()
    }

    func recordCompletion(_ outcome: GoToRoutingCancellationOutcome) {
        lock.lock()
        self.outcome = outcome
        lock.unlock()
        completed.signal()
    }

    func cancelIfRunning(_ cancel: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard didStart, outcome == .pending else { return false }
        cancel()
        return true
    }

    func waitUntilStarted(timeout: TimeInterval) async -> Bool {
        await waitForGoToRoutingSemaphore(started, timeout: timeout)
    }

    func waitUntilCompleted(timeout: TimeInterval) async -> Bool {
        await waitForGoToRoutingSemaphore(completed, timeout: timeout)
    }

    func load() -> GoToRoutingCancellationOutcome {
        lock.lock()
        let outcome = outcome
        lock.unlock()
        return outcome
    }
}

private func waitForGoToRoutingSemaphore(
    _ semaphore: DispatchSemaphore,
    timeout: TimeInterval
) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(
                returning: semaphore.wait(timeout: .now() + timeout) == .success
            )
        }
    }
}
