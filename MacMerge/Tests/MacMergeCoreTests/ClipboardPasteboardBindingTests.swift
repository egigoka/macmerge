import Foundation
import MacMergeCore
import XCTest

final class ClipboardPasteboardBindingTests: XCTestCase {
    func testMenuProjectionIsPinnedFirstMRUAndTruncated() throws {
        var history = ClipboardHistory()
        try history.recordText("alpha", sourceIdentifier: "a", timestamp: date(1))
        try history.recordText("beta", sourceIdentifier: "b", timestamp: date(2))
        try history.recordText("pinned", sourceIdentifier: "p", timestamp: date(3), pinned: true)

        let projection = try ClipboardPasteboardBinding.menuProjection(of: history)
        XCTAssertEqual(projection.items.map(\.sourceIdentifier), ["p", "b", "a"])
        XCTAssertEqual(projection.items.map(\.isPinned), [true, false, false])
        XCTAssertEqual(projection.items.map(\.byteCount), [6, 4, 5])
        XCTAssertEqual(projection.historyRevision, history.revision)
        XCTAssertFalse(projection.isTruncated)
        XCTAssertTrue(projection.items.allSatisfy(\.hasPayload))

        let truncated = try ClipboardPasteboardBinding.menuProjection(
            of: history,
            limits: ClipboardPasteboardBindingLimits(maximumMenuItems: 2)
        )
        XCTAssertEqual(truncated.items.count, 2)
        XCTAssertEqual(truncated.items.map(\.sourceIdentifier), ["p", "b"])
        XCTAssertTrue(truncated.isTruncated)
        XCTAssertEqual(truncated.historyRevision, history.revision)
    }

    func testMenuProjectionRedactsPayloadBytes() throws {
        let secret = "menu-secret-token-9f31"
        var history = ClipboardHistory()
        try history.recordText(secret, sourceIdentifier: "s", timestamp: date(1))

        let projection = try ClipboardPasteboardBinding.menuProjection(of: history)
        XCTAssertEqual(projection.items.count, 1)
        let output = diagnostics(projection) + diagnostics(projection.items)
        XCTAssertFalse(output.contains(secret))
        XCTAssertEqual(
            projection.description,
            "ClipboardPasteboardBindingMenuProjection(itemCount: 1, truncated: false)"
        )
    }

    func testReadPlanRecordsTextAndImageReceipts() throws {
        var history = ClipboardHistory()
        let textPlan = try ClipboardPasteboardBinding.readPlan(
            for: ClipboardPasteboardObservedChange(
                content: .text("hello"),
                sourceIdentifier: "keys",
                timestamp: date(1),
                pasteboardChangeCount: 7,
                pinned: false
            )
        )
        XCTAssertEqual(textPlan.kind, .text)
        XCTAssertEqual(textPlan.byteCount, 5)
        XCTAssertEqual(textPlan.pasteboardChangeCount, 7)

        let receipt = try textPlan.apply(to: &history)
        XCTAssertEqual(receipt.entryID, history.latest?.id)
        XCTAssertEqual(receipt.kind, .text)
        XCTAssertEqual(receipt.byteCount, 5)
        XCTAssertTrue(receipt.didChange)
        XCTAssertLessThan(receipt.historyRevisionBefore, receipt.historyRevisionAfter)
        XCTAssertEqual(receipt.historyRevisionAfter, history.revision)

        let duplicate = try textPlan.apply(to: &history)
        XCTAssertFalse(duplicate.didChange)
        XCTAssertEqual(duplicate.historyRevisionBefore, duplicate.historyRevisionAfter)

        let imagePlan = try ClipboardPasteboardBinding.readPlan(
            for: ClipboardPasteboardObservedChange(
                content: .image(
                    Data([0x01, 0x02]),
                    typeIdentifier: "public.png",
                    pixelWidth: 2,
                    pixelHeight: 1
                ),
                sourceIdentifier: "shot",
                timestamp: date(2)
            )
        )
        XCTAssertEqual(imagePlan.kind, .image)
        XCTAssertEqual(imagePlan.byteCount, 2)
        let imageReceipt = try imagePlan.apply(to: &history)
        XCTAssertTrue(imageReceipt.didChange)
        XCTAssertEqual(imageReceipt.kind, .image)
        XCTAssertEqual(history.count, 2)
        let imageWritePlan = try ClipboardPasteboardBinding.writePlan(for: imageReceipt.entryID, in: history)
        XCTAssertEqual(imageWritePlan.kind, .image)
        XCTAssertEqual(imageWritePlan.imageData, Data([0x01, 0x02]))
        try ClipboardPasteboardBinding.validate(imageWritePlan, in: history)
        let imageWriteReceipt = try imageWritePlan.attestWritten()
        XCTAssertEqual(imageWriteReceipt.entryID, imageReceipt.entryID)
        XCTAssertEqual(imageWriteReceipt.kind, .image)
        XCTAssertEqual(imageWriteReceipt.byteCount, 2)
        XCTAssertEqual(imageWriteReceipt.historyRevision, imageWritePlan.expectedRevision)
        let newerTextPlan = try ClipboardPasteboardBinding.readPlan(
            for: ClipboardPasteboardObservedChange(
                content: .text("hello"),
                sourceIdentifier: "keys",
                timestamp: date(3),
                pasteboardChangeCount: 8,
                pinned: false
            )
        )
        let newerReceipt = try newerTextPlan.apply(to: &history)
        XCTAssertTrue(newerReceipt.didChange)
        XCTAssertEqual(newerReceipt.entryID, history.latest?.id)
        XCTAssertEqual(history.entries.first?.id, newerReceipt.entryID)
        XCTAssertLessThan(newerReceipt.historyRevisionBefore, newerReceipt.historyRevisionAfter)
        XCTAssertEqual(history.count, 2)
    }

    func testReadPlanRejectsInvalidChangeCountTimestampAndOversizePayload() throws {
        assertBindingError(.invalidChangeCount) {
            try ClipboardPasteboardBinding.readPlan(
                for: ClipboardPasteboardObservedChange(
                    content: .text("x"),
                    sourceIdentifier: "s",
                    timestamp: date(1),
                    pasteboardChangeCount: -1
                )
            )
        }
        assertBindingError(.history(.invalidTimestamp)) {
            try ClipboardPasteboardBinding.readPlan(
                for: ClipboardPasteboardObservedChange(
                    content: .text("x"),
                    sourceIdentifier: "s",
                    timestamp: Date(timeIntervalSinceReferenceDate: .infinity)
                )
            )
        }
        assertBindingError(.history(.payloadTooLarge(maximumBytes: 2))) {
            try ClipboardPasteboardBinding.readPlan(
                for: ClipboardPasteboardObservedChange(
                    content: .text("hello"),
                    sourceIdentifier: "s",
                    timestamp: date(1)
                ),
                limits: ClipboardPasteboardBindingLimits(maximumPayloadBytes: 2)
            )
        }
    }

    func testWritePlanRoundTripAttestationAndStaleRevision() throws {
        var history = ClipboardHistory()
        try history.recordText("one", sourceIdentifier: "a", timestamp: date(1))
        try history.recordText("two", sourceIdentifier: "b", timestamp: date(2))
        let targetID = try XCTUnwrap(history.latest?.id)

        let plan = try ClipboardPasteboardBinding.writePlan(for: targetID, in: history)
        XCTAssertEqual(plan.entryID, targetID)
        XCTAssertEqual(plan.expectedRevision, history.revision)
        XCTAssertEqual(plan.kind, .text)
        XCTAssertEqual(plan.text, "two")
        XCTAssertNil(plan.imageData)
        try ClipboardPasteboardBinding.validate(plan, in: history)

        let receipt = try plan.attestWritten()
        XCTAssertEqual(receipt.entryID, targetID)
        XCTAssertEqual(receipt.historyRevision, plan.expectedRevision)
        XCTAssertEqual(receipt.kind, .text)
        XCTAssertEqual(receipt.byteCount, 3)

        try history.recordText("three", sourceIdentifier: "c", timestamp: date(3))
        assertBindingError(
            .staleHistoryRevision(expected: plan.expectedRevision, actual: history.revision)
        ) {
            try ClipboardPasteboardBinding.validate(plan, in: history)
        }
        assertBindingError(.entryNotFound) {
            try ClipboardPasteboardBinding.writePlan(
                for: ClipboardHistoryEntryID(),
                in: history
            )
        }
    }

    func testWritePlanFailsClosedOnMetadataOnlyHistory() throws {
        var history = ClipboardHistory()
        try history.recordText("live", sourceIdentifier: "s", timestamp: date(1))
        let decoded = try ClipboardPasteboardBinding.decode(
            from: try ClipboardPasteboardBinding.encode(history).0
        )
        XCTAssertTrue(decoded.entries.allSatisfy { !$0.hasPayload })
        let targetID = try XCTUnwrap(decoded.entries.first?.id)
        assertBindingError(.payloadUnavailable) {
            try ClipboardPasteboardBinding.writePlan(for: targetID, in: decoded)
        }
    }

    func testMetadataOnlyVersusSecureSnapshotOptIn() throws {
        var history = ClipboardHistory()
        try history.recordText("opt-in-check", sourceIdentifier: "s", timestamp: date(1))

        let (metadata, metadataReceipt) = try ClipboardPasteboardBinding.encode(history)
        XCTAssertEqual(metadataReceipt.policy, .metadataOnly)
        XCTAssertEqual(metadataReceipt.byteCount, metadata.count)
        XCTAssertEqual(metadataReceipt.historyRevision, history.revision)
        XCTAssertFalse(String(decoding: metadata, as: UTF8.self).contains("opt-in-check"))

        let (secure, secureReceipt) = try ClipboardPasteboardBinding.encode(
            history,
            policy: .secureSnapshot
        )
        XCTAssertEqual(secureReceipt.policy, .secureSnapshot)
        XCTAssertEqual(secureReceipt.byteCount, secure.count)
        XCTAssertTrue(String(decoding: secure, as: UTF8.self).contains("opt-in-check"))

        assertBindingError(.secureSnapshotPolicyRequired) {
            try ClipboardPasteboardBinding.decode(from: secure)
        }
        let restored = try ClipboardPasteboardBinding.decode(from: secure, policy: .secureSnapshot)
        XCTAssertEqual(restored, history)
        let targetID = try XCTUnwrap(restored.entries.first?.id)
        XCTAssertEqual(try ClipboardPasteboardBinding.writePlan(for: targetID, in: restored).text, "opt-in-check")

        let metadataDecoded = try ClipboardPasteboardBinding.decode(from: metadata)
        XCTAssertEqual(metadataDecoded.entries.map(\.id), history.entries.map(\.id))
        let secureAsMetadata = try ClipboardPasteboardBinding.decode(
            from: metadata,
            policy: .secureSnapshot
        )
        XCTAssertEqual(secureAsMetadata, metadataDecoded)
    }

    func testComparisonPlanKindsSelectionAndStaleness() throws {
        var history = ClipboardHistory()
        try history.recordText("left", sourceIdentifier: "l", timestamp: date(1))
        let leftID = try XCTUnwrap(history.latest?.id)
        try history.recordText("right", sourceIdentifier: "r", timestamp: date(2))
        let rightID = try XCTUnwrap(history.latest?.id)

        assertBindingError(.selectionRequired) {
            try ClipboardPasteboardBinding.comparisonPlan(in: history)
        }
        try history.setSelection([leftID])
        assertBindingError(.selectionRequired) {
            try ClipboardPasteboardBinding.comparisonPlan(in: history)
        }

        try history.setSelection([leftID, rightID])
        let plan = try ClipboardPasteboardBinding.comparisonPlan(in: history)
        XCTAssertEqual(plan.inputs.kind, .text)
        try ClipboardPasteboardBinding.validateComparison(plan, in: history)

        try history.setPinned(true, for: leftID)
        assertBindingError(.staleComparisonRequest) {
            try ClipboardPasteboardBinding.validateComparison(plan, in: history)
        }
    }

    func testComparisonPlanRejectsMixedKindsAndMetadataOnlyPayloads() throws {
        var mixed = ClipboardHistory()
        try mixed.recordText("text", sourceIdentifier: "t", timestamp: date(1))
        let textID = try XCTUnwrap(mixed.latest?.id)
        try mixed.recordImage(
            Data([0x01]),
            typeIdentifier: "public.png",
            sourceIdentifier: "i",
            timestamp: date(2)
        )
        let imageID = try XCTUnwrap(mixed.latest?.id)
        try mixed.setSelection([textID, imageID])
        assertBindingError(.mixedPayloadKinds) {
            try ClipboardPasteboardBinding.comparisonPlan(in: mixed)
        }

        var pair = ClipboardHistory()
        try pair.recordText("one", sourceIdentifier: "a", timestamp: date(1))
        let firstID = try XCTUnwrap(pair.latest?.id)
        try pair.recordText("two", sourceIdentifier: "b", timestamp: date(2))
        let secondID = try XCTUnwrap(pair.latest?.id)
        try pair.setSelection([firstID, secondID])
        let stripped = try ClipboardPasteboardBinding.decode(
            from: try ClipboardPasteboardBinding.encode(pair).0
        )
        XCTAssertEqual(stripped.selectedIDs, [firstID, secondID])
        assertBindingError(.payloadUnavailable) {
            try ClipboardPasteboardBinding.comparisonPlan(in: stripped)
        }
    }

    func testBindingDescriptionsAndMirrorsRedactPayloadBytes() throws {
        let textSecret = "redact-text-token-41c8"
        let imageBytes = Data("redact-image-token-77d2".utf8)
        let change = ClipboardPasteboardBindingChange.text(textSecret)
        XCTAssertEqual(change.description, "ClipboardPasteboardBindingChange(text, <redacted>)")
        let imageChange = ClipboardPasteboardBindingChange.image(
            imageBytes,
            typeIdentifier: "public.png"
        )
        XCTAssertEqual(imageChange.description, "ClipboardPasteboardBindingChange(image, <redacted>)")

        let observed = ClipboardPasteboardObservedChange(
            content: change,
            sourceIdentifier: "s",
            timestamp: date(1)
        )
        let readPlan = try ClipboardPasteboardBinding.readPlan(for: observed)
        var history = ClipboardHistory()
        let receipt = try readPlan.apply(to: &history)
        let writePlan = try ClipboardPasteboardBinding.writePlan(
            for: receipt.entryID,
            in: history
        )

        let values: [Any] = [change, imageChange, observed, readPlan, writePlan, receipt, history]
        for value in values {
            let output = diagnostics(value)
            XCTAssertFalse(output.contains(textSecret), "Leaked secret in:\n\(output)")
            XCTAssertFalse(output.contains("redact-image-token"), "Leaked secret in:\n\(output)")
        }
        XCTAssertEqual(mirrorString(named: "payload", in: readPlan), "<redacted>")
        XCTAssertEqual(mirrorString(named: "payload", in: writePlan), "<redacted>")
        XCTAssertTrue(diagnostics(readPlan).contains("payload.reflection=\"<redacted>\""))
    }

    func testByteCountAndWorkBudgets() throws {
        var history = ClipboardHistory()
        try history.recordText("aa", sourceIdentifier: "a", timestamp: date(1))
        try history.recordText("bb", sourceIdentifier: "b", timestamp: date(2))

        let tinyWork = ClipboardPasteboardBindingLimits(maximumWorkUnits: 1)
        assertBindingError(.workLimitExceeded(maximumUnits: 1)) {
            try ClipboardPasteboardBinding.menuProjection(of: history, limits: tinyWork)
        }
        assertBindingError(.workLimitExceeded(maximumUnits: 1)) {
            try ClipboardPasteboardBinding.readPlan(
                for: ClipboardPasteboardObservedChange(
                    content: .text("hello"),
                    sourceIdentifier: "s",
                    timestamp: date(1)
                ),
                limits: tinyWork
            )
        }
        let tinyTarget = try XCTUnwrap(history.entries.first?.id)
        assertBindingError(.workLimitExceeded(maximumUnits: 1)) {
            _ = try ClipboardPasteboardBinding.writePlan(for: tinyTarget, in: history, limits: tinyWork)
        }
        try history.setSelection(history.entries.map(\.id))
        assertBindingError(.workLimitExceeded(maximumUnits: 1)) {
            _ = try ClipboardPasteboardBinding.comparisonPlan(in: history, limits: tinyWork)
        }
        assertBindingError(.invalidLimit("menuItems")) {
            try ClipboardPasteboardBinding.menuProjection(
                of: history,
                limits: ClipboardPasteboardBindingLimits(maximumMenuItems: 0)
            )
        }
        assertBindingError(.invalidLimit("payloadBytes")) {
            try ClipboardPasteboardBinding.readPlan(
                for: ClipboardPasteboardObservedChange(
                    content: .text("x"),
                    sourceIdentifier: "s",
                    timestamp: date(1)
                ),
                limits: ClipboardPasteboardBindingLimits(maximumPayloadBytes: 0)
            )
        }
        assertBindingError(.invalidLimit("workUnits")) {
            try ClipboardPasteboardBinding.readPlan(
                for: ClipboardPasteboardObservedChange(
                    content: .text("x"),
                    sourceIdentifier: "s",
                    timestamp: date(1)
                ),
                limits: ClipboardPasteboardBindingLimits(maximumWorkUnits: 0)
            )
        }
        assertBindingError(.invalidLimit("cancellationCheckInterval")) {
            try ClipboardPasteboardBinding.menuProjection(
                of: history,
                limits: ClipboardPasteboardBindingLimits(cancellationCheckInterval: 0)
            )
        }
    }

    func testShouldRecordSemantics() throws {
        XCTAssertTrue(try ClipboardPasteboardBinding.shouldRecord(observedChangeCount: nil, lastSeenChangeCount: nil))
        XCTAssertTrue(try ClipboardPasteboardBinding.shouldRecord(observedChangeCount: nil, lastSeenChangeCount: 3))
        XCTAssertTrue(try ClipboardPasteboardBinding.shouldRecord(observedChangeCount: 4, lastSeenChangeCount: nil))
        XCTAssertTrue(try ClipboardPasteboardBinding.shouldRecord(observedChangeCount: 4, lastSeenChangeCount: 3))
        XCTAssertFalse(try ClipboardPasteboardBinding.shouldRecord(observedChangeCount: 4, lastSeenChangeCount: 4))
        assertBindingError(.invalidChangeCount) {
            try ClipboardPasteboardBinding.shouldRecord(observedChangeCount: -1, lastSeenChangeCount: nil)
        }
    }

    func testShouldRecordCancellationMapsToCancelled() async {
        let error = await cancelledError {
            _ = try ClipboardPasteboardBinding.shouldRecord(
                observedChangeCount: 1,
                lastSeenChangeCount: nil
            )
        }
        XCTAssertEqual(error as? ClipboardPasteboardBindingError, .cancelled)
    }

    func testCancellationMapsToBindingCancelled() async throws {
        var history = ClipboardHistory()
        try history.recordText("left", sourceIdentifier: "l", timestamp: date(1))
        let leftID = try XCTUnwrap(history.latest?.id)
        try history.recordText("right", sourceIdentifier: "r", timestamp: date(2))
        let rightID = try XCTUnwrap(history.latest?.id)
        try history.setSelection([leftID, rightID])
        let snapshot = history
        let writePlan = try ClipboardPasteboardBinding.writePlan(for: leftID, in: snapshot)
        let comparisonPlan = try ClipboardPasteboardBinding.comparisonPlan(in: snapshot)
        let (secure, _) = try ClipboardPasteboardBinding.encode(snapshot, policy: .secureSnapshot)

        let attestError = await cancelledError { _ = try writePlan.attestWritten() }
        XCTAssertEqual(attestError as? ClipboardPasteboardBindingError, .cancelled)

        let validateError = await cancelledError {
            try ClipboardPasteboardBinding.validate(writePlan, in: snapshot)
        }
        XCTAssertEqual(validateError as? ClipboardPasteboardBindingError, .cancelled)

        let comparisonValidateError = await cancelledError {
            try ClipboardPasteboardBinding.validateComparison(comparisonPlan, in: snapshot)
        }
        XCTAssertEqual(comparisonValidateError as? ClipboardPasteboardBindingError, .cancelled)

        let encodeError = await cancelledError {
            _ = try ClipboardPasteboardBinding.encode(snapshot)
        }
        XCTAssertEqual(encodeError as? ClipboardPasteboardBindingError, .cancelled)

        let decodeError = await cancelledError {
            _ = try ClipboardPasteboardBinding.decode(from: secure, policy: .secureSnapshot)
        }
        XCTAssertEqual(decodeError as? ClipboardPasteboardBindingError, .cancelled)

        let stamp = date(1)
        let operations: [@Sendable () throws -> Void] = [
            { _ = try ClipboardPasteboardBinding.menuProjection(of: snapshot) },
            {
                _ = try ClipboardPasteboardBinding.readPlan(
                    for: ClipboardPasteboardObservedChange(
                        content: .text("x"),
                        sourceIdentifier: "s",
                        timestamp: stamp
                    )
                )
            },
            { _ = try ClipboardPasteboardBinding.writePlan(for: leftID, in: snapshot) },
            { _ = try ClipboardPasteboardBinding.comparisonPlan(in: snapshot) }
        ]
        for operation in operations {
            let error = await cancelledError(for: operation)
            XCTAssertEqual(error as? ClipboardPasteboardBindingError, .cancelled)
        }
    }

    private func date(_ interval: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: interval)
    }

    private func assertBindingError(
        _ expected: ClipboardPasteboardBindingError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? ClipboardPasteboardBindingError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func cancelledError(
        for operation: @escaping @Sendable () throws -> Void
    ) async -> Error? {
        await Task<Error?, Never> {
            withUnsafeCurrentTask { task in task?.cancel() }
            do {
                try operation()
                return nil
            } catch {
                return error
            }
        }.value
    }

    private func diagnostics(_ value: Any) -> String {
        var lines: [String] = []
        func append(_ value: Any, label: String?, depth: Int) {
            let prefix = String(repeating: "  ", count: depth) + (label ?? "<root>")
            lines.append("\(prefix).description=\(String(describing: value))")
            lines.append("\(prefix).reflection=\(String(reflecting: value))")
            guard depth < 6 else { return }
            for child in Mirror(reflecting: value).children {
                append(child.value, label: child.label, depth: depth + 1)
            }
        }
        append(value, label: nil, depth: 0)
        return lines.joined(separator: "\n")
    }

    private func mirrorString(named name: String, in value: Any) -> String? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value as? String
    }
}
