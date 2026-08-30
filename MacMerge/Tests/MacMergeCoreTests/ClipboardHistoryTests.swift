import Foundation
import MacMergeCore
import XCTest

final class ClipboardHistoryTests: XCTestCase {
    func testTextAndImagePayloadsPreserveExactContentAndSeparateIdentityDomains() throws {
        let text = try ClipboardHistoryPayload.text("caf\u{00E9}\n")
        let bytes = Data("caf\u{00E9}\n".utf8)
        let image = try ClipboardHistoryPayload.image(
            bytes,
            typeIdentifier: "public.png",
            pixelWidth: 640,
            pixelHeight: 480
        )

        XCTAssertEqual(text.kind, .text)
        XCTAssertEqual(text.text, "caf\u{00E9}\n")
        XCTAssertNil(text.imageData)
        XCTAssertEqual(text.byteCount, bytes.count)
        XCTAssertNil(text.imageMetadata)
        XCTAssertEqual(image.kind, .image)
        XCTAssertNil(image.text)
        XCTAssertEqual(image.imageData, bytes)
        XCTAssertEqual(image.byteCount, bytes.count)
        XCTAssertEqual(image.imageMetadata?.typeIdentifier, "public.png")
        XCTAssertEqual(image.imageMetadata?.pixelWidth, 640)
        XCTAssertEqual(image.imageMetadata?.pixelHeight, 480)
        XCTAssertEqual(image.imageMetadata?.description, "public.png, 640x480")
        XCTAssertNotEqual(text.digest, image.digest)
        XCTAssertNotEqual(text, image)

        XCTAssertEqual(text.digest.rawValue.utf8.count, 71)
        XCTAssertTrue(text.digest.rawValue.hasPrefix("sha256:"))
        XCTAssertEqual(ClipboardHistoryDigest(rawValue: text.digest.rawValue), text.digest)
        XCTAssertNil(ClipboardHistoryDigest(rawValue: text.digest.rawValue.uppercased()))
        XCTAssertNil(ClipboardHistoryDigest(rawValue: "sha256:00"))
        assertHistoryError(.invalidDigest) {
            try ClipboardHistoryDigest(validating: "sha256:not-a-digest")
        }
    }

    func testImageTypeAndDimensionsArePartOfContentIdentityAndDedupe() throws {
        let bytes = Data([0x00, 0x01, 0xFE, 0xFF])
        let original = try ClipboardHistoryPayload.image(
            bytes,
            typeIdentifier: "public.png",
            pixelWidth: 20,
            pixelHeight: 10
        )
        let identical = try ClipboardHistoryPayload.image(
            bytes,
            typeIdentifier: "public.png",
            pixelWidth: 20,
            pixelHeight: 10
        )
        let differentType = try ClipboardHistoryPayload.image(
            bytes,
            typeIdentifier: "public.jpeg",
            pixelWidth: 20,
            pixelHeight: 10
        )
        let differentWidth = try ClipboardHistoryPayload.image(
            bytes,
            typeIdentifier: "public.png",
            pixelWidth: 21,
            pixelHeight: 10
        )
        let differentHeight = try ClipboardHistoryPayload.image(
            bytes,
            typeIdentifier: "public.png",
            pixelWidth: 20,
            pixelHeight: 11
        )
        let unknownDimensions = try ClipboardHistoryPayload.image(
            bytes,
            typeIdentifier: "public.png"
        )

        XCTAssertEqual(original, identical)
        XCTAssertEqual(original.digest, identical.digest)
        XCTAssertNotEqual(original.digest, differentType.digest)
        XCTAssertNotEqual(original.digest, differentWidth.digest)
        XCTAssertNotEqual(original.digest, differentHeight.digest)
        XCTAssertNotEqual(original.digest, unknownDimensions.digest)

        var history = ClipboardHistory()
        try history.record(original, sourceIdentifier: "first", timestamp: date(1))
        let originalID = try XCTUnwrap(history.latest?.id)
        try history.record(identical, sourceIdentifier: "duplicate", timestamp: date(2))
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.latest?.id, originalID)
        try history.record(differentType, sourceIdentifier: "type", timestamp: date(3))
        try history.record(differentWidth, sourceIdentifier: "width", timestamp: date(4))
        try history.record(differentHeight, sourceIdentifier: "height", timestamp: date(5))
        try history.record(unknownDimensions, sourceIdentifier: "dimensions", timestamp: date(6))
        XCTAssertEqual(history.count, 5)
        XCTAssertEqual(history.latest?.payload, unknownDimensions)
    }

    func testPayloadValidationUsesExactByteAndImageMetadataBounds() throws {
        let multibyte = "\u{00E9}"
        XCTAssertEqual(try ClipboardHistoryPayload.text(multibyte, maximumBytes: 2).byteCount, 2)
        assertHistoryError(.payloadTooLarge(maximumBytes: 1)) {
            try ClipboardHistoryPayload.text(multibyte, maximumBytes: 1)
        }
        assertHistoryError(.emptyPayload) {
            try ClipboardHistoryPayload.text("")
        }
        assertHistoryError(.emptyPayload) {
            try ClipboardHistoryPayload.image(Data(), typeIdentifier: "public.png")
        }
        assertHistoryError(.payloadTooLarge(maximumBytes: 1)) {
            try ClipboardHistoryPayload.image(
                Data([0, 1]),
                typeIdentifier: "public.png",
                maximumBytes: 1
            )
        }
        XCTAssertNoThrow(
            try ClipboardHistoryPayload.image(
                Data([0, 1]),
                typeIdentifier: "public.png",
                maximumBytes: 2
            )
        )

        let maximumType = String(
            repeating: "a",
            count: ClipboardHistory.maximumSupportedTypeIdentifierBytes
        )
        XCTAssertNoThrow(
            try ClipboardHistoryPayload.image(Data([0]), typeIdentifier: maximumType)
        )
        for invalidType in [
            "",
            "public image",
            "public.png\n",
            String(repeating: "a", count: maximumType.utf8.count + 1)
        ] {
            assertHistoryError(.invalidImageTypeIdentifier) {
                try ClipboardHistoryPayload.image(Data([0]), typeIdentifier: invalidType)
            }
        }

        XCTAssertNoThrow(
            try ClipboardHistoryPayload.image(
                Data([0]),
                typeIdentifier: "public.png",
                pixelWidth: ClipboardHistory.maximumImageDimension,
                pixelHeight: 1
            )
        )
        XCTAssertNoThrow(
            try ClipboardHistoryPayload.image(
                Data([0]),
                typeIdentifier: "public.png",
                pixelWidth: 1_000_000,
                pixelHeight: 1_000
            )
        )
        for dimensions in [
            (nil, 1),
            (1, nil),
            (0, 1),
            (1, 0),
            (ClipboardHistory.maximumImageDimension + 1, 1),
            (1_000_000, 1_001)
        ] as [(Int?, Int?)] {
            assertHistoryError(.invalidImageDimensions) {
                try ClipboardHistoryPayload.image(
                    Data([0]),
                    typeIdentifier: "public.png",
                    pixelWidth: dimensions.0,
                    pixelHeight: dimensions.1
                )
            }
        }
    }

    func testEntryIDsAreOpaqueUniqueCanonicalAndStableAcrossPersistence() throws {
        var history = ClipboardHistory()
        try history.recordText("alpha", sourceIdentifier: "source", timestamp: date(1))
        try history.recordText("beta", sourceIdentifier: "source", timestamp: date(2))
        let ids = history.entries.map(\.id)

        XCTAssertEqual(Set(ids).count, 2)
        for entry in history {
            XCTAssertEqual(entry.id.rawValue.utf8.count, 36)
            XCTAssertEqual(entry.id.rawValue, entry.id.rawValue.lowercased())
            XCTAssertEqual(ClipboardHistoryEntryID(rawValue: entry.id.rawValue), entry.id)
            XCTAssertNotEqual(entry.id.rawValue, entry.payload?.digest.rawValue)
        }
        XCTAssertNil(ClipboardHistoryEntryID(rawValue: "not-an-id"))

        let fixedID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        XCTAssertNotNil(ClipboardHistoryEntryID(rawValue: fixedID))
        XCTAssertNil(ClipboardHistoryEntryID(rawValue: fixedID.uppercased()))

        var independent = ClipboardHistory()
        try independent.recordText("alpha", sourceIdentifier: "source", timestamp: date(1))
        XCTAssertNotEqual(independent.latest?.id, ids.last)

        let persisted = try history.encodedData()
        let decoded = try ClipboardHistory.decode(from: persisted)
        XCTAssertEqual(decoded.entries.map(\.id), ids)
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("sha256:"))
    }

    func testDescriptionsAndReflectionRedactEveryTextImageAndDigestSentinel() throws {
        let textSecrets = ["left-private-token-5f9400", "right-private-token-a1879e"]
        let imageSecrets = ["left-image-token-6b2181", "right-image-token-c3d947"]
        let textPayloads = try textSecrets.map { try ClipboardHistoryPayload.text($0) }
        let imagePayloads = try imageSecrets.map {
            try ClipboardHistoryPayload.image(Data($0.utf8), typeIdentifier: "public.data")
        }

        var textHistory = ClipboardHistory()
        for (index, payload) in textPayloads.enumerated() {
            try textHistory.record(
                payload,
                sourceIdentifier: "text-\(index)",
                timestamp: date(TimeInterval(index + 1))
            )
        }
        try textHistory.setSelection(textHistory.entries.map(\.id).reversed())
        let textRequest = try textHistory.comparisonRequest()

        var imageHistory = ClipboardHistory()
        for (index, payload) in imagePayloads.enumerated() {
            try imageHistory.record(
                payload,
                sourceIdentifier: "image-\(index)",
                timestamp: date(TimeInterval(index + 3))
            )
        }
        try imageHistory.setSelection(imageHistory.entries.map(\.id).reversed())
        let imageRequest = try imageHistory.comparisonRequest()

        let payloads = textPayloads + imagePayloads
        let sentinels =
            textSecrets + imageSecrets
            + imageSecrets.map { Data($0.utf8).base64EncodedString() }
            + imageSecrets.map { secret in
                Data(secret.utf8).map { String(format: "%02x", $0) }.joined()
            }
            + payloads.map(\.digest.rawValue)
        var values: [Any] = payloads.flatMap { [$0.digest, $0] }
        values.append(contentsOf: textHistory.entries)
        values.append(contentsOf: imageHistory.entries)
        values.append(contentsOf: [
            textHistory,
            imageHistory,
            textRequest.left,
            textRequest.right,
            textRequest,
            imageRequest.left,
            imageRequest.right,
            imageRequest
        ])

        for value in values {
            let output = diagnostics(value)
            for sentinel in sentinels {
                XCTAssertFalse(output.contains(sentinel), "Leaked \(sentinel) in:\n\(output)")
            }
        }
        XCTAssertEqual(textPayloads[0].digest.description, "ClipboardHistoryDigest(<redacted>)")
        XCTAssertEqual(
            textPayloads[0].description,
            "ClipboardHistoryPayload(kind: text, byteCount: \(textSecrets[0].utf8.count))"
        )
        XCTAssertEqual(mirrorString(named: "payload", in: imagePayloads[0]), "<redacted>")
        XCTAssertEqual(mirrorString(named: "payload", in: imageHistory.entries[0]), "<redacted>")
        XCTAssertTrue(diagnostics(textPayloads[0]).contains("payload.reflection=\"<redacted>\""))
        XCTAssertTrue(diagnostics(textHistory).contains("entries.reflection=\"<redacted>\""))
        XCTAssertTrue(diagnostics(imageRequest).contains("payloads.reflection=\"<redacted>\""))
    }

    func testPinnedAndUnpinnedPartitionsMaintainIndependentMRUOrdering() throws {
        var history = ClipboardHistory()
        try history.recordText("old", sourceIdentifier: "old", timestamp: date(300))
        let oldID = try XCTUnwrap(history.latest?.id)
        try history.recordText(
            "pinned",
            sourceIdentifier: "pinned",
            timestamp: date(200),
            pinned: true
        )
        let pinnedID = try XCTUnwrap(history.latest?.id)
        try history.recordText("new", sourceIdentifier: "new", timestamp: date(100))
        let newID = try XCTUnwrap(history.latest?.id)

        XCTAssertEqual(history.entries.map(\.id), [pinnedID, newID, oldID])
        XCTAssertEqual(history.entries.map(\.isPinned), [true, false, false])
        XCTAssertEqual(history.latest?.id, newID)
        XCTAssertEqual(history.latest?.timestamp, date(100))

        XCTAssertTrue(try history.setPinned(true, for: oldID))
        XCTAssertEqual(history.entries.map(\.id), [pinnedID, oldID, newID])
        XCTAssertEqual(history.latest?.id, newID)
        XCTAssertTrue(try history.setPinned(true, for: newID))
        XCTAssertEqual(history.entries.map(\.id), [newID, pinnedID, oldID])
        XCTAssertTrue(try history.setPinned(false, for: newID))
        XCTAssertEqual(history.entries.map(\.id), [pinnedID, oldID, newID])
        XCTAssertEqual(history.latest?.id, newID)

        let persisted = try history.encodedData(policy: .secureSnapshot)
        let decoded = try ClipboardHistory.decode(from: persisted, policy: .secureSnapshot)
        XCTAssertEqual(decoded, history)
        XCTAssertEqual(decoded.entries.map(\.id), [pinnedID, oldID, newID])
        XCTAssertEqual(decoded.entries.map(\.isPinned), [true, true, false])
    }

    func testDedupePromotesExactContentWhileRetainingIDAndPin() throws {
        var history = ClipboardHistory()
        try history.recordText(
            "same",
            sourceIdentifier: "first",
            timestamp: date(1),
            pinned: true
        )
        let id = try XCTUnwrap(history.latest?.id)
        try history.recordText(
            "pinned-peer",
            sourceIdentifier: "peer",
            timestamp: date(2),
            pinned: true
        )
        let peerID = try XCTUnwrap(history.latest?.id)
        try history.recordText("other", sourceIdentifier: "other", timestamp: date(2))
        let otherID = try XCTUnwrap(history.latest?.id)
        XCTAssertEqual(history.entries.map(\.id), [peerID, id, otherID])

        XCTAssertTrue(
            try history.recordText(
                "same",
                sourceIdentifier: "replacement",
                timestamp: date(3)
            )
        )
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.entries.first?.id, id)
        XCTAssertEqual(history.entries.map(\.id), [id, peerID, otherID])
        XCTAssertEqual(history.entries.first?.sourceIdentifier, "replacement")
        XCTAssertEqual(history.entries.first?.timestamp, date(3))
        XCTAssertEqual(history.entries.first?.isPinned, true)
        XCTAssertEqual(history.latest?.id, id)

        let revision = history.revision
        XCTAssertFalse(
            try history.recordText(
                "same",
                sourceIdentifier: "replacement",
                timestamp: date(3)
            )
        )
        XCTAssertEqual(history.revision, revision)
        XCTAssertEqual(history.entries.first?.id, id)

        var unpinned = ClipboardHistory()
        try unpinned.recordText("same", sourceIdentifier: "first", timestamp: date(1))
        let sameID = try XCTUnwrap(unpinned.latest?.id)
        try unpinned.recordText("peer", sourceIdentifier: "peer", timestamp: date(2))
        let unpinnedPeerID = try XCTUnwrap(unpinned.latest?.id)
        XCTAssertEqual(unpinned.entries.map(\.id), [unpinnedPeerID, sameID])
        try unpinned.recordText("same", sourceIdentifier: "promoted", timestamp: date(3))
        XCTAssertEqual(unpinned.entries.map(\.id), [sameID, unpinnedPeerID])
        XCTAssertEqual(unpinned.latest?.id, sameID)
    }

    func testEntryCapEvictsOnlyOldestUnpinnedEntryAndItsSelection() throws {
        let limits = try makeLimits(
            maximumEntries: 3,
            maximumPayloadBytes: 8,
            maximumRetainedPayloadBytes: 24
        )
        var history = ClipboardHistory(limits: limits)
        try history.recordText("p", sourceIdentifier: "pin", timestamp: date(1), pinned: true)
        let pinnedID = try XCTUnwrap(history.latest?.id)
        try history.recordText("a", sourceIdentifier: "a", timestamp: date(2))
        let oldestUnpinnedID = try XCTUnwrap(history.latest?.id)
        try history.recordText("b", sourceIdentifier: "b", timestamp: date(3))
        let retainedSelectionID = try XCTUnwrap(history.latest?.id)
        try history.setSelection([oldestUnpinnedID, retainedSelectionID])

        try history.recordText("c", sourceIdentifier: "c", timestamp: date(4))
        XCTAssertEqual(history.entries.map(\.payload?.text), ["p", "c", "b"])
        XCTAssertEqual(history.entries.map(\.id).first, pinnedID)
        XCTAssertFalse(history.entries.map(\.id).contains(oldestUnpinnedID))
        XCTAssertEqual(history.selectedIDs, [retainedSelectionID])
        XCTAssertEqual(history.retainedPayloadByteCount, 3)
        XCTAssertLessThan(history.retainedPayloadByteCount, limits.maximumRetainedPayloadBytes)
    }

    func testAggregateRetainedByteCapEvictsUntilNewEntryFits() throws {
        let limits = try makeLimits(
            maximumEntries: 5,
            maximumPayloadBytes: 4,
            maximumRetainedPayloadBytes: 6
        )
        var history = ClipboardHistory(limits: limits)
        try history.recordText("aa", sourceIdentifier: "a", timestamp: date(1), pinned: true)
        try history.recordText("bb", sourceIdentifier: "b", timestamp: date(2))
        try history.recordText("cc", sourceIdentifier: "c", timestamp: date(3))

        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.retainedPayloadByteCount, limits.maximumRetainedPayloadBytes)
        try history.recordText("ddd", sourceIdentifier: "d", timestamp: date(4))

        XCTAssertEqual(history.entries.map(\.payload?.text), ["aa", "ddd"])
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.retainedPayloadByteCount, 5)
        XCTAssertLessThan(history.count, limits.maximumEntries)
    }

    func testPinnedEntriesMakeRetainedByteFailureAtomic() throws {
        let limits = try makeLimits(
            maximumEntries: 3,
            maximumPayloadBytes: 8,
            maximumRetainedPayloadBytes: 8
        )
        var history = ClipboardHistory(limits: limits)
        try history.recordText("aa", sourceIdentifier: "a", timestamp: date(1), pinned: true)
        try history.recordText("bb", sourceIdentifier: "b", timestamp: date(2), pinned: true)
        let selectedID = try XCTUnwrap(history.latest?.id)
        try history.setSelection([selectedID])

        let original = history
        assertHistoryError(.pinnedEntriesPreventEviction) {
            try history.recordText("12345678", sourceIdentifier: "large", timestamp: date(5))
        }
        XCTAssertEqual(history, original)
    }

    func testSelectionAndComparisonRequestsPreserveOrderPayloadsAndStaleness() throws {
        var history = ClipboardHistory()
        try history.recordText("left", sourceIdentifier: "left-source", timestamp: date(1))
        let leftID = try XCTUnwrap(history.latest?.id)
        try history.recordText("right", sourceIdentifier: "right-source", timestamp: date(2))
        let rightID = try XCTUnwrap(history.latest?.id)
        try history.recordText("third", sourceIdentifier: "third-source", timestamp: date(3))
        let thirdID = try XCTUnwrap(history.latest?.id)

        assertHistoryError(.comparisonSelectionRequired) {
            try history.comparisonRequest()
        }
        XCTAssertTrue(try history.select(leftID))
        XCTAssertTrue(try history.select(rightID, extendingSelection: true))
        XCTAssertEqual(history.selectedEntries.map(\.id), [leftID, rightID])
        assertHistoryError(.selectionLimitExceeded(maximumCount: 2)) {
            try history.select(thirdID, extendingSelection: true)
        }
        assertHistoryError(.duplicateSelection) {
            try history.setSelection([leftID, leftID])
        }
        assertHistoryError(.entryNotFound) {
            try history.select(ClipboardHistoryEntryID())
        }

        let request = try history.comparisonRequest()
        XCTAssertEqual(request.kind, .text)
        XCTAssertEqual(request.left.id, leftID)
        XCTAssertEqual(request.right.id, rightID)
        XCTAssertEqual(request.left.payload.text, "left")
        XCTAssertEqual(request.right.payload.text, "right")
        XCTAssertEqual(request.left.sourceIdentifier, "left-source")
        XCTAssertEqual(request.right.sourceIdentifier, "right-source")
        XCTAssertTrue(try history.isCurrent(request))
        XCTAssertFalse(try request.isStale(in: history))
        XCTAssertNoThrow(try history.validate(request))

        XCTAssertFalse(try history.setSelection([leftID, rightID]))
        XCTAssertTrue(try history.isCurrent(request))
        XCTAssertTrue(try history.setPinned(true, for: leftID))
        XCTAssertFalse(try history.isCurrent(request))
        XCTAssertTrue(try request.isStale(in: history))
        assertHistoryError(.staleComparisonRequest) {
            try history.validate(request)
        }
        XCTAssertEqual(request.left.payload.text, "left")
    }

    func testComparisonRequestRejectsMixedKindsAndSupportsImagePayloads() throws {
        var mixed = ClipboardHistory()
        try mixed.recordText("text", sourceIdentifier: "text", timestamp: date(1))
        let textID = try XCTUnwrap(mixed.latest?.id)
        try mixed.recordImage(
            Data([1]),
            typeIdentifier: "public.png",
            sourceIdentifier: "image",
            timestamp: date(2)
        )
        let imageID = try XCTUnwrap(mixed.latest?.id)
        try mixed.setSelection([textID, imageID])
        assertHistoryError(.mixedPayloadKinds) {
            try mixed.comparisonRequest()
        }

        var images = ClipboardHistory()
        try images.recordImage(
            Data([1, 2]),
            typeIdentifier: "public.png",
            pixelWidth: 2,
            pixelHeight: 1,
            sourceIdentifier: "left",
            timestamp: date(1)
        )
        let leftID = try XCTUnwrap(images.latest?.id)
        try images.recordImage(
            Data([1, 3]),
            typeIdentifier: "public.png",
            pixelWidth: 2,
            pixelHeight: 1,
            sourceIdentifier: "right",
            timestamp: date(2)
        )
        let rightID = try XCTUnwrap(images.latest?.id)
        try images.setSelection([leftID, rightID])
        let request = try images.comparisonRequest()
        XCTAssertEqual(request.kind, .image)
        XCTAssertEqual(request.left.payload.imageData, Data([1, 2]))
        XCTAssertEqual(request.right.payload.imageData, Data([1, 3]))
        XCTAssertEqual(request.left.payload.imageMetadata?.pixelWidth, 2)
    }

    func testRemoveClearAndClearUnpinnedMaintainBytesSelectionAndRevision() throws {
        var history = ClipboardHistory()
        try history.recordText("pin", sourceIdentifier: "pin", timestamp: date(1), pinned: true)
        let pinnedID = try XCTUnwrap(history.latest?.id)
        try history.recordText("free", sourceIdentifier: "free", timestamp: date(2))
        let unpinnedID = try XCTUnwrap(history.latest?.id)
        try history.setSelection([pinnedID, unpinnedID])

        let revision = history.revision
        XCTAssertEqual(try history.clearUnpinned(), 1)
        XCTAssertEqual(history.entries.map(\.id), [pinnedID])
        XCTAssertEqual(history.selectedIDs, [pinnedID])
        XCTAssertEqual(history.retainedPayloadByteCount, 3)
        XCTAssertGreaterThan(history.revision, revision)
        XCTAssertEqual(try history.clearUnpinned(), 0)
        XCTAssertFalse(try history.remove(ClipboardHistoryEntryID()))
        XCTAssertTrue(try history.remove(pinnedID))
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(history.retainedPayloadByteCount, 0)
        XCTAssertFalse(try history.clear())

        try history.recordText("again", sourceIdentifier: "source", timestamp: date(3), pinned: true)
        XCTAssertTrue(try history.clear())
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertTrue(history.selectedIDs.isEmpty)
        XCTAssertEqual(history.retainedPayloadByteCount, 0)
    }

    func testRecordValidationAndWorkCapFailuresAreAtomic() throws {
        let limits = try makeLimits(
            maximumPayloadBytes: 4,
            maximumRetainedPayloadBytes: 8,
            maximumSourceIdentifierBytes: 4,
            maximumTypeIdentifierBytes: 4
        )
        var history = ClipboardHistory(limits: limits)
        try history.recordText("seed", sourceIdentifier: "seed", timestamp: date(0), pinned: true)
        let selectedID = try XCTUnwrap(history.latest?.id)
        try history.setSelection([selectedID])
        let original = history
        for source in ["", "   ", "nul\0tail", "line\nfeed", "format\u{200B}"] {
            assertHistoryError(.invalidSourceIdentifier) {
                try history.recordText("x", sourceIdentifier: source, timestamp: date(1))
            }
            XCTAssertEqual(history, original)
        }
        assertHistoryError(.invalidTimestamp) {
            try history.recordText(
                "x",
                sourceIdentifier: "safe",
                timestamp: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        }
        XCTAssertEqual(history, original)
        assertHistoryError(.payloadTooLarge(maximumBytes: limits.maximumPayloadBytes)) {
            let externalPayload = try ClipboardHistoryPayload.text("12345")
            try history.record(externalPayload, sourceIdentifier: "safe", timestamp: date(1))
        }
        XCTAssertEqual(history, original)
        assertHistoryError(.invalidImageTypeIdentifier) {
            let externalImage = try ClipboardHistoryPayload.image(
                Data([0]),
                typeIdentifier: "abcde"
            )
            try history.record(externalImage, sourceIdentifier: "safe", timestamp: date(1))
        }
        XCTAssertEqual(history, original)

        assertHistoryError(.invalidSourceIdentifier) {
            try history.recordText("b", sourceIdentifier: "12345", timestamp: date(2))
        }
        XCTAssertEqual(history, original)

        let workLimits = try makeLimits(
            maximumEntries: 2,
            maximumPayloadBytes: 8,
            maximumRetainedPayloadBytes: 8,
            maximumSourceIdentifierBytes: 8,
            maximumTypeIdentifierBytes: 8,
            maximumWork: 8,
            maximumPersistenceBytes: 1
        )
        var workBound = ClipboardHistory(limits: workLimits)
        try workBound.recordText("a", sourceIdentifier: "s", timestamp: date(1))
        let workBoundOriginal = workBound
        assertHistoryError(.workLimitExceeded(maximumWork: 8)) {
            try workBound.recordText("12345678", sourceIdentifier: "s", timestamp: date(2))
        }
        XCTAssertEqual(workBound, workBoundOriginal)

        let entryLimits = try makeLimits(
            maximumEntries: 1,
            maximumPayloadBytes: 2,
            maximumRetainedPayloadBytes: 4
        )
        var entryBound = ClipboardHistory(limits: entryLimits)
        try entryBound.recordText("a", sourceIdentifier: "a", timestamp: date(1), pinned: true)
        let entryBoundOriginal = entryBound
        assertHistoryError(.pinnedEntriesPreventEviction) {
            try entryBound.recordText("b", sourceIdentifier: "b", timestamp: date(2))
        }
        XCTAssertEqual(entryBound, entryBoundOriginal)

        let evictionWorkLimits = try makeLimits(
            maximumEntries: 2,
            maximumPayloadBytes: 2,
            maximumRetainedPayloadBytes: 4,
            maximumSourceIdentifierBytes: 1,
            maximumTypeIdentifierBytes: 1,
            maximumWork: 10,
            maximumPersistenceBytes: 1
        )
        var evictionWorkBound = ClipboardHistory(limits: evictionWorkLimits)
        try evictionWorkBound.recordText("a", sourceIdentifier: "a", timestamp: date(1))
        try evictionWorkBound.recordText("b", sourceIdentifier: "b", timestamp: date(2))
        let evictionWorkOriginal = evictionWorkBound
        assertHistoryError(.workLimitExceeded(maximumWork: 10)) {
            try evictionWorkBound.recordText("c", sourceIdentifier: "c", timestamp: date(3))
        }
        XCTAssertEqual(evictionWorkBound, evictionWorkOriginal)
    }

    func testMetadataOnlyPersistenceRedactsPayloadsAndRestoresMetadataSelection() throws {
        let limits = try makeLimits()
        var history = ClipboardHistory(limits: limits)
        let secret = "metadata-private-token"
        try history.recordText(secret, sourceIdentifier: "text-source", timestamp: date(1))
        let textID = try XCTUnwrap(history.latest?.id)
        try history.recordText("comparison", sourceIdentifier: "second-text", timestamp: date(2))
        let secondTextID = try XCTUnwrap(history.latest?.id)
        let imageBytes = Data("image-private-token".utf8)
        try history.recordImage(
            imageBytes,
            typeIdentifier: "public.png",
            pixelWidth: 4,
            pixelHeight: 5,
            sourceIdentifier: "image-source",
            timestamp: date(3),
            pinned: true
        )
        let imageID = try XCTUnwrap(history.latest?.id)
        try history.setSelection([textID, secondTextID])

        let encoded = try history.encodedData()
        let string = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(string.contains(secret))
        XCTAssertFalse(string.contains(imageBytes.base64EncodedString()))
        XCTAssertFalse(string.contains("\"payload\""))
        XCTAssertFalse(string.contains("sha256:"))

        let decoded = try ClipboardHistory.decode(from: encoded)
        XCTAssertEqual(decoded.limits, limits)
        XCTAssertEqual(decoded.entries.map(\.id), history.entries.map(\.id))
        XCTAssertEqual(decoded.entries.map(\.kind), history.entries.map(\.kind))
        XCTAssertEqual(decoded.entries.map(\.byteCount), history.entries.map(\.byteCount))
        XCTAssertEqual(decoded.entries.map(\.imageMetadata), history.entries.map(\.imageMetadata))
        XCTAssertEqual(decoded.entries.map(\.sourceIdentifier), history.entries.map(\.sourceIdentifier))
        XCTAssertEqual(decoded.entries.map(\.timestamp), history.entries.map(\.timestamp))
        XCTAssertEqual(decoded.entries.map(\.isPinned), history.entries.map(\.isPinned))
        XCTAssertEqual(decoded.entries.map(\.isPinned), [true, false, false])
        XCTAssertTrue(decoded.entries.allSatisfy { !$0.hasPayload && $0.payload == nil })
        XCTAssertEqual(decoded.selectedIDs, [textID, secondTextID])
        XCTAssertEqual(decoded.retainedPayloadByteCount, 0)
        assertHistoryError(.payloadUnavailable) {
            try decoded.comparisonRequest()
        }
        XCTAssertEqual(
            try ClipboardHistory.decode(from: encoded, policy: .secureSnapshot),
            decoded
        )

        var restored = decoded
        XCTAssertEqual(try restored.clearUnpinned(), 2)
        XCTAssertEqual(restored.entries.map(\.id), [imageID])
        XCTAssertEqual(restored.entries.map(\.isPinned), [true])
    }

    func testSecureSnapshotRequiresOptInBeforeImageParsingAndRoundTripsPayloads() throws {
        var history = ClipboardHistory(limits: try makeLimits())
        try history.recordText(
            "secure text\n\"quoted\"",
            sourceIdentifier: "text",
            timestamp: date(1)
        )
        let textID = try XCTUnwrap(history.latest?.id)
        try history.recordImage(
            Data([0x00, 0x01, 0xFE, 0xFF]),
            typeIdentifier: "public.png",
            pixelWidth: 2,
            pixelHeight: 2,
            sourceIdentifier: "image",
            timestamp: date(2),
            pinned: true
        )
        let imageID = try XCTUnwrap(history.latest?.id)
        try history.setSelection([imageID, textID])

        let encoded = try history.encodedData(policy: .secureSnapshot)
        let string = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(string.contains("\"persistencePolicy\":\"secureSnapshot\""))
        XCTAssertTrue(string.contains("secure text\\n\\\"quoted\\\""))
        XCTAssertTrue(string.contains("AAH+/w=="))
        assertHistoryError(.secureSnapshotPolicyRequired) {
            try ClipboardHistory.decode(from: encoded)
        }
        let parserPoisonedImage = replacing(
            string,
            target: "\"payload\":\"AAH+/w==\"",
            replacement: "\"payload\":\"!!!!!!!!\""
        )
        assertHistoryError(.secureSnapshotPolicyRequired) {
            try ClipboardHistory.decode(from: parserPoisonedImage)
        }
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(from: parserPoisonedImage, policy: .secureSnapshot)
        }

        let decoded = try ClipboardHistory.decode(from: encoded, policy: .secureSnapshot)
        XCTAssertEqual(decoded, history)
        XCTAssertEqual(try decoded.encodedData(policy: .secureSnapshot), encoded)

        let metadata = try history.encodedData()
        let metadataHistory = try ClipboardHistory.decode(from: metadata)
        assertHistoryError(.payloadUnavailable) {
            try metadataHistory.encodedData(policy: .secureSnapshot)
        }
    }

    func testPayloadBearingPersistenceCannotDowngradePolicyToMetadataOnly() throws {
        var history = ClipboardHistory(limits: try makeLimits())
        try history.recordText("private", sourceIdentifier: "source", timestamp: date(1))
        let secureSnapshot = String(
            decoding: try history.encodedData(policy: .secureSnapshot),
            as: UTF8.self
        )
        let downgraded = replacing(
            secureSnapshot,
            target: "\"persistencePolicy\":\"secureSnapshot\"",
            replacement: "\"persistencePolicy\":\"metadataOnly\""
        )

        assertHistoryError(.nonCanonicalPersistence) {
            try ClipboardHistory.decode(from: downgraded)
        }
        assertHistoryError(.nonCanonicalPersistence) {
            try ClipboardHistory.decode(from: downgraded, policy: .secureSnapshot)
        }
    }

    func testSchemaV2CanonicalEncodingIsExactDeterministicAndCompact() throws {
        let limits = try makeLimits(
            maximumEntries: 3,
            maximumPayloadBytes: 64,
            maximumRetainedPayloadBytes: 128,
            maximumSourceIdentifierBytes: 32,
            maximumTypeIdentifierBytes: 32,
            maximumWork: 100_000,
            maximumPersistenceBytes: 10_000
        )
        var history = ClipboardHistory(limits: limits)
        try history.recordText("value", sourceIdentifier: "source", timestamp: date(0))
        let id = try XCTUnwrap(history.latest?.id.rawValue)
        let expected = Data(
            ("{\"entries\":[{\"byteCount\":5,\"id\":\"\(id)\",\"kind\":\"text\","
                + "\"pinned\":false,\"recency\":1,\"sourceIdentifier\":\"source\","
                + "\"timestamp\":\"0000000000000000\"}],\"limits\":{\"maximumEntries\":3,"
                + "\"maximumPayloadBytes\":64,\"maximumPersistenceBytes\":10000,"
                + "\"maximumRetainedPayloadBytes\":128,\"maximumSourceIdentifierBytes\":32,"
                + "\"maximumTypeIdentifierBytes\":32,\"maximumWork\":100000},"
                + "\"persistencePolicy\":\"metadataOnly\",\"revision\":1,"
                + "\"schemaVersion\":2,\"selection\":[]}").utf8
        )

        XCTAssertEqual(ClipboardHistory.currentSchemaVersion, 2)
        XCTAssertEqual(try history.encodedData(), expected)
        XCTAssertEqual(try history.encodedData(), expected)
        let decoded = try ClipboardHistory.decode(from: expected)
        XCTAssertEqual(try decoded.encodedData(), expected)
        XCTAssertFalse(expected.contains(0x0A))
        XCTAssertFalse(expected.contains(0x20))
    }

    func testStrictPersistenceRejectsUnsupportedMalformedDuplicateAndNoncanonicalData() throws {
        let limits = try makeLimits(
            maximumPayloadBytes: 32 * 1_024,
            maximumRetainedPayloadBytes: 32 * 1_024,
            maximumWork: 1_000_000,
            maximumPersistenceBytes: 100_000
        )
        var history = ClipboardHistory(limits: limits)
        let text = String(repeating: "x", count: 20 * 1_024) + "/tail"
        try history.recordText(text, sourceIdentifier: "source", timestamp: date(1))
        let canonical = try history.encodedData(policy: .secureSnapshot)
        let canonicalString = String(decoding: canonical, as: UTF8.self)

        assertHistoryError(.unsupportedSchemaVersion(3)) {
            try ClipboardHistory.decode(
                from: replacing(
                    canonicalString,
                    target: "\"schemaVersion\":2",
                    replacement: "\"schemaVersion\":3"
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.duplicatePersistenceKey) {
            try ClipboardHistory.decode(
                from: replacing(
                    canonicalString,
                    target: "\"schemaVersion\":2",
                    replacement: "\"schemaVersion\":2,\"schemaVersion\":2"
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(from: Data(" \(canonicalString)".utf8), policy: .secureSnapshot)
        }
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(from: canonical + [0x0A], policy: .secureSnapshot)
        }

        let escapedSlash = replacing(
            canonicalString,
            target: "/tail",
            replacement: "\\/tail"
        )
        XCTAssertNotEqual(escapedSlash, canonical)
        assertHistoryError(.nonCanonicalPersistence) {
            try ClipboardHistory.decode(from: escapedSlash, policy: .secureSnapshot)
        }

        let withoutRevision = canonicalString.replacingOccurrences(
            of: ",\"revision\":1",
            with: ""
        )
        let reorderedRoot = replacing(
            withoutRevision,
            target: "{\"entries\":",
            replacement: "{\"revision\":1,\"entries\":"
        )
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(from: reorderedRoot, policy: .secureSnapshot)
        }
    }

    func testUnknownRootLimitsTextAndImageKeysReturnExactError() throws {
        var textHistory = ClipboardHistory(limits: try makeLimits())
        try textHistory.recordText("text", sourceIdentifier: "source", timestamp: date(1))
        let text = String(
            decoding: try textHistory.encodedData(policy: .secureSnapshot),
            as: UTF8.self
        )
        let metadata = String(decoding: try textHistory.encodedData(), as: UTF8.self)
        var imageHistory = ClipboardHistory(limits: try makeLimits())
        try imageHistory.recordImage(
            Data([1]),
            typeIdentifier: "public.png",
            sourceIdentifier: "source",
            timestamp: date(1)
        )
        let image = String(
            decoding: try imageHistory.encodedData(policy: .secureSnapshot),
            as: UTF8.self
        )
        let imageMetadata = String(decoding: try imageHistory.encodedData(), as: UTF8.self)

        let unknownCases: [(Data, ClipboardHistory.PersistencePolicy)] = [
            (
                replacing(
                    metadata,
                    target: "\"selection\":[]}",
                    replacement: "\"selection\":[],\"future\":true}"
                ),
                .metadataOnly
            ),
            (
                replacing(
                    metadata,
                    target: "\"maximumWork\":100000}",
                    replacement: "\"maximumWork\":100000,\"future\":true}"
                ),
                .metadataOnly
            ),
            (
                replacing(
                    metadata,
                    target: "\"kind\":\"text\"",
                    replacement: "\"future\":true,\"kind\":\"text\""
                ),
                .metadataOnly
            ),
            (
                replacing(
                    metadata,
                    target: "\"kind\":\"text\"",
                    replacement: "\"kind\":\"text\",\"pixelWidth\":null"
                ),
                .metadataOnly
            ),
            (
                replacing(
                    imageMetadata,
                    target: "\"kind\":\"image\"",
                    replacement: "\"future\":true,\"kind\":\"image\""
                ),
                .metadataOnly
            ),
            (
                replacing(
                    text,
                    target: "\"selection\":[]}",
                    replacement: "\"selection\":[],\"future\":true}"
                ),
                .secureSnapshot
            ),
            (
                replacing(
                    text,
                    target: "\"maximumWork\":100000}",
                    replacement: "\"maximumWork\":100000,\"future\":true}"
                ),
                .secureSnapshot
            ),
            (
                replacing(
                    text,
                    target: "\"kind\":\"text\"",
                    replacement: "\"future\":true,\"kind\":\"text\""
                ),
                .secureSnapshot
            ),
            (
                replacing(
                    text,
                    target: "\"kind\":\"text\"",
                    replacement: "\"kind\":\"text\",\"typeIdentifier\":\"public.png\""
                ),
                .secureSnapshot
            ),
            (
                replacing(
                    image,
                    target: "\"kind\":\"image\"",
                    replacement: "\"future\":true,\"kind\":\"image\""
                ),
                .secureSnapshot
            )
        ]
        for (data, policy) in unknownCases {
            assertHistoryError(.unknownPersistenceKey) {
                try ClipboardHistory.decode(from: data, policy: policy)
            }
        }
    }

    func testDuplicateKeysAtEveryObjectLevelReturnExactError() throws {
        var history = ClipboardHistory(limits: try makeLimits())
        try history.recordText("text", sourceIdentifier: "source", timestamp: date(1))
        let canonical = String(
            decoding: try history.encodedData(policy: .secureSnapshot),
            as: UTF8.self
        )
        let duplicateCases = [
            replacing(
                canonical,
                target: "\"selection\":[]}",
                replacement: "\"selection\":[],\"selection\":[]}"
            ),
            replacing(
                canonical,
                target: "\"maximumEntries\":5",
                replacement: "\"maximumEntries\":5,\"maximumEntries\":5"
            ),
            replacing(
                canonical,
                target: "\"kind\":\"text\"",
                replacement: "\"kind\":\"text\",\"kind\":\"text\""
            )
        ]
        for data in duplicateCases {
            assertHistoryError(.duplicatePersistenceKey) {
                try ClipboardHistory.decode(from: data, policy: .secureSnapshot)
            }
        }
    }

    func testPersistenceRejectsNoncanonicalEntryOrderRecencyDuplicatesAndSelection() throws {
        let limits = try makeLimits()
        let firstID = "00000000-0000-0000-0000-000000000001"
        let secondID = "00000000-0000-0000-0000-000000000002"
        let missingID = "00000000-0000-0000-0000-000000000003"
        let first = try textEntry(id: firstID, text: "a", pinned: false, recency: 2)
        let second = try textEntry(id: secondID, text: "b", pinned: false, recency: 1)

        assertHistoryError(.duplicateEntry) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [first, first],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.nonCanonicalPersistence) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [
                        try textEntry(id: firstID, text: "a", pinned: false, recency: 1),
                        try textEntry(id: secondID, text: "b", pinned: false, recency: 1)
                    ],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 1
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.duplicateEntry) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [
                        try textEntry(id: firstID, text: "same", pinned: false, recency: 2),
                        try textEntry(id: secondID, text: "same", pinned: false, recency: 1)
                    ],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.nonCanonicalPersistence) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [
                        first,
                        try textEntry(id: secondID, text: "b", pinned: true, recency: 1)
                    ],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.nonCanonicalPersistence) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [
                        try textEntry(id: firstID, text: "a", pinned: false, recency: 1),
                        try textEntry(id: secondID, text: "b", pinned: false, recency: 2)
                    ],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.nonCanonicalPersistence) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [
                        try textEntry(id: firstID, text: "a", pinned: true, recency: 1),
                        try textEntry(id: secondID, text: "b", pinned: true, recency: 2)
                    ],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.duplicateSelection) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [first, second],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2,
                    selection: [firstID, firstID]
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.entryNotFound) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [first, second],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2,
                    selection: [missingID]
                ),
                policy: .secureSnapshot
            )
        }
    }

    func testStoredUniqueEntryCapRejectsSecondDistinctEntryDuringParsing() throws {
        let limits = try makeLimits(
            maximumEntries: 1,
            maximumPayloadBytes: 8,
            maximumRetainedPayloadBytes: 16
        )
        let first = try textEntry(
            id: "00000000-0000-0000-0000-000000000001",
            text: "first",
            pinned: false,
            recency: 2
        )
        let second = try textEntry(
            id: "00000000-0000-0000-0000-000000000002",
            text: "second",
            pinned: false,
            recency: 1
        ).replacingOccurrences(of: "\"byteCount\":6", with: "\"byteCount\":9")
        XCTAssertNotEqual(first, second)

        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [first, second],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2
                ),
                policy: .secureSnapshot
            )
        }

        let uncappedLimits = try makeLimits(
            maximumEntries: 2,
            maximumPayloadBytes: 8,
            maximumRetainedPayloadBytes: 16
        )
        assertHistoryError(.payloadTooLarge(maximumBytes: 8)) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [first, second],
                    limits: uncappedLimits,
                    policy: .secureSnapshot,
                    revision: 2
                ),
                policy: .secureSnapshot
            )
        }
    }

    func testDecodedAggregateRetainedImageBytesRejectBeforeSecondPayloadDecode() throws {
        let limits = try makeLimits(
            maximumEntries: 2,
            maximumPayloadBytes: 4,
            maximumRetainedPayloadBytes: 6
        )
        let first = try imageEntry(
            id: "00000000-0000-0000-0000-000000000001",
            base64: Data([1, 2, 3, 4]).base64EncodedString(),
            byteCount: 4,
            typeIdentifier: "public.data",
            recency: 2
        )
        let second = try imageEntry(
            id: "00000000-0000-0000-0000-000000000002",
            base64: "!!!!",
            byteCount: 4,
            typeIdentifier: "public.data",
            recency: 1
        )

        assertHistoryError(.retainedPayloadLimitExceeded(maximumBytes: 6)) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [first, second],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2
                ),
                policy: .secureSnapshot
            )
        }

        let exactFirst = try imageEntry(
            id: "00000000-0000-0000-0000-000000000001",
            base64: Data([1, 2, 3]).base64EncodedString(),
            byteCount: 3,
            typeIdentifier: "public.data",
            recency: 2
        )
        let exactSecond = try imageEntry(
            id: "00000000-0000-0000-0000-000000000002",
            base64: Data([4, 5, 6]).base64EncodedString(),
            byteCount: 3,
            typeIdentifier: "public.data",
            recency: 1
        )
        let exact = try ClipboardHistory.decode(
            from: persistenceData(
                entries: [exactFirst, exactSecond],
                limits: limits,
                policy: .secureSnapshot,
                revision: 2
            ),
            policy: .secureSnapshot
        )
        XCTAssertEqual(exact.retainedPayloadByteCount, limits.maximumRetainedPayloadBytes)
        XCTAssertEqual(exact.entries.compactMap(\.payload?.imageData), [Data([1, 2, 3]), Data([4, 5, 6])])
    }

    func testDecodedAggregateRetainedTextBytesAcceptExactAndRejectOneMore() throws {
        let limits = try makeLimits(
            maximumEntries: 2,
            maximumPayloadBytes: 4,
            maximumRetainedPayloadBytes: 6
        )
        let first = try textEntry(
            id: "00000000-0000-0000-0000-000000000001",
            text: "abc",
            pinned: false,
            recency: 2
        )
        let exactSecond = try textEntry(
            id: "00000000-0000-0000-0000-000000000002",
            text: "def",
            pinned: false,
            recency: 1
        )
        let exact = try ClipboardHistory.decode(
            from: persistenceData(
                entries: [first, exactSecond],
                limits: limits,
                policy: .secureSnapshot,
                revision: 2
            ),
            policy: .secureSnapshot
        )
        XCTAssertEqual(exact.retainedPayloadByteCount, limits.maximumRetainedPayloadBytes)
        XCTAssertEqual(exact.entries.compactMap(\.payload?.text), ["abc", "def"])

        let oneMore = try textEntry(
            id: "00000000-0000-0000-0000-000000000002",
            text: "defg",
            pinned: false,
            recency: 1
        )
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [first, oneMore],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 2
                ),
                policy: .secureSnapshot
            )
        }
    }

    func testDecodedIntegerOverflowIsRejectedAndMaximumRevisionCannotAdvance() throws {
        let limits = try makeLimits()
        var history = ClipboardHistory(limits: limits)
        try history.recordText("value", sourceIdentifier: "source", timestamp: date(1))
        let canonical = String(
            decoding: try history.encodedData(policy: .secureSnapshot),
            as: UTF8.self
        )
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(
                from: replacing(
                    canonical,
                    target: "\"revision\":1",
                    replacement: "\"revision\":18446744073709551616"
                ),
                policy: .secureSnapshot
            )
        }

        var imageHistory = ClipboardHistory(limits: limits)
        try imageHistory.recordImage(
            Data([1]),
            typeIdentifier: "public.data",
            sourceIdentifier: "source",
            timestamp: date(1)
        )
        let imageCanonical = String(
            decoding: try imageHistory.encodedData(policy: .secureSnapshot),
            as: UTF8.self
        )
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(
                from: replacing(
                    imageCanonical,
                    target: "\"pixelWidth\":null",
                    replacement: "\"pixelWidth\":9223372036854775808"
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(
                from: replacing(
                    canonical,
                    target: "\"byteCount\":5",
                    replacement: "\"byteCount\":9223372036854775808"
                ),
                policy: .secureSnapshot
            )
        }
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(
                from: replacing(
                    canonical,
                    target: "\"maximumEntries\":5",
                    replacement: "\"maximumEntries\":9223372036854775808"
                ),
                policy: .secureSnapshot
            )
        }

        let maximumRevision =
            canonical
            .replacingOccurrences(
                of: "\"pinned\":false,\"recency\":1",
                with: "\"pinned\":false,\"recency\":18446744073709551615"
            )
            .replacingOccurrences(
                of: "\"revision\":1",
                with: "\"revision\":18446744073709551615"
            )
        XCTAssertNotEqual(maximumRevision, canonical)
        var decoded = try ClipboardHistory.decode(
            from: Data(maximumRevision.utf8),
            policy: .secureSnapshot
        )
        let original = decoded
        let id = try XCTUnwrap(decoded.latest?.id)
        assertHistoryError(.revisionSpaceExhausted) {
            try decoded.setPinned(true, for: id)
        }
        XCTAssertEqual(decoded, original)
    }

    func testCallerDecodeCapsAreAuthoritativeOverStoredLimits() throws {
        let storedLimits = try makeLimits()
        let encoded = try ClipboardHistory(limits: storedLimits).encodedData()
        let exact = try ClipboardHistory.decode(from: encoded, limits: storedLimits)
        XCTAssertEqual(exact.limits, storedLimits)

        let lowerCaps = try [
            makeLimits(maximumEntries: storedLimits.maximumEntries - 1),
            makeLimits(
                maximumPayloadBytes: storedLimits.maximumPayloadBytes - 1,
                maximumRetainedPayloadBytes: storedLimits.maximumRetainedPayloadBytes
            ),
            makeLimits(
                maximumRetainedPayloadBytes: storedLimits.maximumRetainedPayloadBytes - 1
            ),
            makeLimits(
                maximumSourceIdentifierBytes: storedLimits.maximumSourceIdentifierBytes - 1
            ),
            makeLimits(
                maximumTypeIdentifierBytes: storedLimits.maximumTypeIdentifierBytes - 1
            ),
            makeLimits(maximumWork: storedLimits.maximumWork - 1),
            makeLimits(maximumPersistenceBytes: storedLimits.maximumPersistenceBytes - 1)
        ]
        for callerLimits in lowerCaps {
            assertHistoryError(.decodedLimitsExceedCallerLimits) {
                try ClipboardHistory.decode(from: encoded, limits: callerLimits)
            }
        }

        let parserPoisonedImage = try imageEntry(
            id: "00000000-0000-0000-0000-000000000001",
            base64: "!!!!",
            byteCount: 1,
            typeIdentifier: "public.data",
            recency: 1
        )
        let parserPoisonedData = try persistenceData(
            entries: [parserPoisonedImage],
            limits: storedLimits,
            policy: .secureSnapshot,
            revision: 1
        )
        let lowerEntryCap = try makeLimits(
            maximumEntries: storedLimits.maximumEntries - 1
        )
        assertHistoryError(.decodedLimitsExceedCallerLimits) {
            try ClipboardHistory.decode(
                from: parserPoisonedData,
                policy: .secureSnapshot,
                limits: lowerEntryCap
            )
        }
        assertHistoryError(.malformedPersistence) {
            try ClipboardHistory.decode(
                from: parserPoisonedData,
                policy: .secureSnapshot,
                limits: storedLimits
            )
        }

        let tooSmallForData = try makeLimits(
            maximumWork: encoded.count * 8,
            maximumPersistenceBytes: encoded.count - 1
        )
        assertHistoryError(.persistenceDataTooLarge(maximumBytes: encoded.count - 1)) {
            try ClipboardHistory.decode(from: encoded, limits: tooSmallForData)
        }
    }

    func testTinyImageWireRejectsForgedMaximumByteCountAndCompletesDecodeOperation() throws {
        let boundary = ClipboardHistory.maximumSupportedPayloadBytes
        let limits = try makeLimits(
            maximumEntries: 1,
            maximumPayloadBytes: boundary,
            maximumRetainedPayloadBytes: boundary,
            maximumSourceIdentifierBytes: 32,
            maximumTypeIdentifierBytes: 32,
            maximumWork: 100_000,
            maximumPersistenceBytes: 10_000
        )
        let id = "00000000-0000-0000-0000-000000000001"
        let forged = try imageEntry(
            id: id,
            base64: "AA==",
            byteCount: boundary,
            typeIdentifier: "public.png",
            recency: 1
        )

        let forgedData = try persistenceData(
            entries: [forged],
            limits: limits,
            policy: .secureSnapshot,
            revision: 1
        )
        XCTAssertLessThan(forgedData.count, 1_024)
        var decodeOperationCompleted = false
        assertHistoryError(.nonCanonicalPersistence) {
            defer { decodeOperationCompleted = true }
            _ = try ClipboardHistory.decode(
                from: forgedData,
                policy: .secureSnapshot,
                limits: limits
            )
        }
        XCTAssertTrue(
            decodeOperationCompleted,
            "Tiny payload decode did not return from forged maximum byte count"
        )

        let overBoundary = try imageEntry(
            id: id,
            base64: "AA==",
            byteCount: boundary + 1,
            typeIdentifier: "public.png",
            recency: 1
        )
        assertHistoryError(.payloadTooLarge(maximumBytes: boundary)) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [overBoundary],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 1
                ),
                policy: .secureSnapshot,
                limits: limits
            )
        }
    }

    func testImageBase64RejectsNoncanonicalPaddingIncompleteAndTrailingQuartets() throws {
        let limits = try makeLimits()
        let id = "00000000-0000-0000-0000-000000000001"
        for base64 in ["AB==", "AAA", "AA==AAAA"] {
            let entry = try imageEntry(
                id: id,
                base64: base64,
                byteCount: 1,
                typeIdentifier: "public.png",
                recency: 1
            )
            assertHistoryError(.malformedPersistence) {
                try ClipboardHistory.decode(
                    from: persistenceData(
                        entries: [entry],
                        limits: limits,
                        policy: .secureSnapshot,
                        revision: 1
                    ),
                    policy: .secureSnapshot
                )
            }
        }

        let decodedOverflow = try imageEntry(
            id: id,
            base64: "AAAA",
            byteCount: 1,
            typeIdentifier: "public.png",
            recency: 1
        )
        assertHistoryError(.payloadTooLarge(maximumBytes: 1)) {
            try ClipboardHistory.decode(
                from: persistenceData(
                    entries: [decodedOverflow],
                    limits: limits,
                    policy: .secureSnapshot,
                    revision: 1
                ),
                policy: .secureSnapshot
            )
        }
    }

    func testImageBase64ChunkBoundariesRoundTripCanonically() throws {
        let limits = try makeLimits(
            maximumPayloadBytes: 13_000,
            maximumRetainedPayloadBytes: 13_000,
            maximumWork: 500_000,
            maximumPersistenceBytes: 30_000
        )
        for byteCount in [1, 2, 3, 4, 4_095, 4_096, 4_097, 12_287, 12_288, 12_289] {
            let bytes = Data((0..<byteCount).map { UInt8(truncatingIfNeeded: $0) })
            var history = ClipboardHistory(limits: limits)
            try history.recordImage(
                bytes,
                typeIdentifier: "public.data",
                sourceIdentifier: "boundary",
                timestamp: date(1)
            )

            let encoded = try history.encodedData(policy: .secureSnapshot)
            let decoded = try ClipboardHistory.decode(
                from: encoded,
                policy: .secureSnapshot,
                limits: limits
            )
            XCTAssertEqual(decoded, history, "byteCount=\(byteCount)")
            XCTAssertEqual(
                try decoded.encodedData(policy: .secureSnapshot),
                encoded,
                "byteCount=\(byteCount)"
            )
        }
    }

    func testChunkedTextRecordingObservesPreexistingCancellation() async {
        let outcome = await Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            do {
                var history = ClipboardHistory()
                try history.recordText(
                    String(repeating: "x", count: 64 * 1_024),
                    sourceIdentifier: "source",
                    timestamp: Date(timeIntervalSinceReferenceDate: 1)
                )
                return ClipboardHistoryCancellationOutcome.succeeded
            } catch is CancellationError {
                return ClipboardHistoryCancellationOutcome.cancelled
            } catch {
                return ClipboardHistoryCancellationOutcome.failed(String(describing: error))
            }
        }.value

        switch outcome {
        case .cancelled:
            break
        case .succeeded:
            XCTFail("Cancelled chunked fingerprint unexpectedly succeeded")
        case .failed(let description):
            XCTFail("Unexpected cancellation error: \(description)")
        }
    }

    func testMaximumLimitConfigurationSupportsRepresentativeHistoryOperations() throws {
        let hard = try ClipboardHistory.Limits(
            maximumEntries: ClipboardHistory.maximumSupportedEntries,
            maximumPayloadBytes: ClipboardHistory.maximumSupportedPayloadBytes,
            maximumRetainedPayloadBytes: ClipboardHistory.maximumSupportedRetainedPayloadBytes,
            maximumSourceIdentifierBytes: ClipboardHistory.maximumSupportedSourceIdentifierBytes,
            maximumTypeIdentifierBytes: ClipboardHistory.maximumSupportedTypeIdentifierBytes,
            maximumWork: ClipboardHistory.maximumSupportedWork,
            maximumPersistenceBytes: ClipboardHistory.maximumSupportedPersistenceBytes
        )
        XCTAssertEqual(hard.maximumPayloadBytes, 128 * 1_024 * 1_024)
        XCTAssertEqual(hard.maximumRetainedPayloadBytes, 256 * 1_024 * 1_024)
        XCTAssertEqual(hard.maximumPersistenceBytes, 384 * 1_024 * 1_024)

        var history = ClipboardHistory(limits: hard)
        try history.recordText("left", sourceIdentifier: "text-left", timestamp: date(1))
        let leftID = try XCTUnwrap(history.latest?.id)
        try history.recordText("right", sourceIdentifier: "text-right", timestamp: date(2))
        let rightID = try XCTUnwrap(history.latest?.id)
        try history.recordImage(
            Data([0, 1, 2]),
            typeIdentifier: "public.data",
            sourceIdentifier: "image",
            timestamp: date(3)
        )
        let imageID = try XCTUnwrap(history.latest?.id)
        XCTAssertTrue(try history.setPinned(true, for: imageID))
        XCTAssertTrue(try history.setSelection([leftID, rightID]))
        XCTAssertEqual(try history.comparisonRequest().kind, .text)

        let metadata = try history.encodedData()
        let secureSnapshot = try history.encodedData(policy: .secureSnapshot)
        let decodedMetadata = try ClipboardHistory.decode(from: metadata, limits: hard)
        let decodedSecureSnapshot = try ClipboardHistory.decode(
            from: secureSnapshot,
            policy: .secureSnapshot,
            limits: hard
        )
        XCTAssertEqual(decodedMetadata.entries.map(\.isPinned), [true, false, false])
        XCTAssertEqual(decodedMetadata.retainedPayloadByteCount, 0)
        XCTAssertEqual(decodedSecureSnapshot, history)
    }

    func testLimitsRejectEveryOutOfRangeField() throws {

        let invalid: [() throws -> Void] = [
            { _ = try ClipboardHistory.Limits(maximumEntries: 0) },
            {
                _ = try ClipboardHistory.Limits(
                    maximumEntries: ClipboardHistory.maximumSupportedEntries + 1
                )
            },
            { _ = try ClipboardHistory.Limits(maximumPayloadBytes: 0) },
            {
                _ = try ClipboardHistory.Limits(
                    maximumPayloadBytes: ClipboardHistory.maximumSupportedPayloadBytes + 1,
                    maximumRetainedPayloadBytes: ClipboardHistory.maximumSupportedRetainedPayloadBytes
                )
            },
            {
                _ = try ClipboardHistory.Limits(
                    maximumPayloadBytes: 2,
                    maximumRetainedPayloadBytes: 1
                )
            },
            {
                _ = try ClipboardHistory.Limits(
                    maximumRetainedPayloadBytes:
                        ClipboardHistory.maximumSupportedRetainedPayloadBytes + 1
                )
            },
            { _ = try ClipboardHistory.Limits(maximumSourceIdentifierBytes: 0) },
            {
                _ = try ClipboardHistory.Limits(
                    maximumSourceIdentifierBytes:
                        ClipboardHistory.maximumSupportedSourceIdentifierBytes + 1
                )
            },
            { _ = try ClipboardHistory.Limits(maximumTypeIdentifierBytes: 0) },
            {
                _ = try ClipboardHistory.Limits(
                    maximumTypeIdentifierBytes:
                        ClipboardHistory.maximumSupportedTypeIdentifierBytes + 1
                )
            },
            { _ = try ClipboardHistory.Limits(maximumWork: 0) },
            {
                _ = try ClipboardHistory.Limits(
                    maximumWork: ClipboardHistory.maximumSupportedWork + 1
                )
            },
            { _ = try ClipboardHistory.Limits(maximumPersistenceBytes: 0) },
            {
                _ = try ClipboardHistory.Limits(
                    maximumPersistenceBytes:
                        ClipboardHistory.maximumSupportedPersistenceBytes + 1
                )
            },
            {
                _ = try ClipboardHistory.Limits(
                    maximumWork: 80,
                    maximumPersistenceBytes: 11
                )
            }
        ]
        for operation in invalid {
            assertHistoryError(.invalidLimits, operation)
        }

        XCTAssertNoThrow(
            try ClipboardHistoryPayload.text(
                "x",
                maximumBytes: ClipboardHistory.maximumSupportedPayloadBytes
            )
        )
        assertHistoryError(.invalidLimits) {
            try ClipboardHistoryPayload.text(
                "x",
                maximumBytes: ClipboardHistory.maximumSupportedPayloadBytes + 1
            )
        }
    }

    func testPersistenceByteLimitAcceptsExactBoundaryAndRejectsOneMore() throws {
        var maximumPersistenceBytes = 512
        var exactData = emptyPersistence(maximumPersistenceBytes: maximumPersistenceBytes)
        for _ in 0..<8 {
            let next = exactData.count
            if next == maximumPersistenceBytes { break }
            maximumPersistenceBytes = next
            exactData = emptyPersistence(maximumPersistenceBytes: maximumPersistenceBytes)
        }
        XCTAssertEqual(exactData.count, maximumPersistenceBytes)

        let exactLimits = try makeLimits(
            maximumEntries: 1,
            maximumPayloadBytes: 1,
            maximumRetainedPayloadBytes: 1,
            maximumSourceIdentifierBytes: 1,
            maximumTypeIdentifierBytes: 1,
            maximumWork: 10_000,
            maximumPersistenceBytes: maximumPersistenceBytes
        )
        let exactHistory = ClipboardHistory(limits: exactLimits)
        XCTAssertEqual(try exactHistory.encodedData(), exactData)
        XCTAssertEqual(try ClipboardHistory.decode(from: exactData), exactHistory)

        let oneShort = maximumPersistenceBytes - 1
        let oneShortLimits = try makeLimits(
            maximumEntries: 1,
            maximumPayloadBytes: 1,
            maximumRetainedPayloadBytes: 1,
            maximumSourceIdentifierBytes: 1,
            maximumTypeIdentifierBytes: 1,
            maximumWork: 10_000,
            maximumPersistenceBytes: oneShort
        )
        assertHistoryError(.persistenceDataTooLarge(maximumBytes: oneShort)) {
            try ClipboardHistory(limits: oneShortLimits).encodedData()
        }
        assertHistoryError(.persistenceDataTooLarge(maximumBytes: maximumPersistenceBytes)) {
            try ClipboardHistory.decode(from: exactData + [0x0A])
        }
    }

    private func date(_ interval: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: interval)
    }

    private func makeLimits(
        maximumEntries: Int = 5,
        maximumPayloadBytes: Int = 64,
        maximumRetainedPayloadBytes: Int = 128,
        maximumSourceIdentifierBytes: Int = 32,
        maximumTypeIdentifierBytes: Int = 32,
        maximumWork: Int = 100_000,
        maximumPersistenceBytes: Int = 10_000
    ) throws -> ClipboardHistory.Limits {
        try ClipboardHistory.Limits(
            maximumEntries: maximumEntries,
            maximumPayloadBytes: maximumPayloadBytes,
            maximumRetainedPayloadBytes: maximumRetainedPayloadBytes,
            maximumSourceIdentifierBytes: maximumSourceIdentifierBytes,
            maximumTypeIdentifierBytes: maximumTypeIdentifierBytes,
            maximumWork: maximumWork,
            maximumPersistenceBytes: maximumPersistenceBytes
        )
    }

    private func assertHistoryError<T>(
        _ expected: ClipboardHistoryError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ClipboardHistoryError, expected, file: file, line: line)
        }
    }

    private func diagnostics(_ value: Any) -> String {
        var lines: [String] = []
        func append(_ value: Any, label: String?, depth: Int) {
            let prefix = String(repeating: "  ", count: depth) + (label ?? "<root>")
            lines.append("\(prefix).description=\(String(describing: value))")
            lines.append("\(prefix).reflection=\(String(reflecting: value))")
            guard depth < 8 else { return }
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

    private func replacing(
        _ source: String,
        target: String,
        replacement: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Data {
        let result = source.replacingOccurrences(of: target, with: replacement)
        XCTAssertNotEqual(result, source, "Mutation target was absent", file: file, line: line)
        return Data(result.utf8)
    }

    private func textEntry(
        id: String,
        text: String,
        pinned: Bool,
        recency: UInt64
    ) throws -> String {
        "{\"byteCount\":\(text.utf8.count),\"id\":\(try jsonString(id)),\"kind\":\"text\","
            + "\"payload\":\(try jsonString(text)),\"pinned\":\(pinned),\"recency\":\(recency),"
            + "\"sourceIdentifier\":\"s\",\"timestamp\":\"0000000000000000\"}"
    }

    private func imageEntry(
        id: String,
        base64: String,
        byteCount: Int,
        typeIdentifier: String,
        recency: UInt64
    ) throws -> String {
        "{\"byteCount\":\(byteCount),\"id\":\(try jsonString(id)),\"kind\":\"image\","
            + "\"payload\":\(try jsonString(base64)),\"pixelHeight\":null,\"pixelWidth\":null,"
            + "\"pinned\":false,\"recency\":\(recency),\"sourceIdentifier\":\"s\","
            + "\"timestamp\":\"0000000000000000\",\"typeIdentifier\":"
            + "\(try jsonString(typeIdentifier))}"
    }

    private func jsonString(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func persistenceData(
        entries: [String],
        limits: ClipboardHistory.Limits,
        policy: ClipboardHistory.PersistencePolicy,
        revision: UInt64,
        selection: [String] = []
    ) throws -> Data {
        let selected = try selection.map(jsonString).joined(separator: ",")

        let joinedEntries = entries.joined(separator: ",")
        let string =
            "{\"entries\":[\(joinedEntries)],\"limits\":{"
            + "\"maximumEntries\":\(limits.maximumEntries),"
            + "\"maximumPayloadBytes\":\(limits.maximumPayloadBytes),"
            + "\"maximumPersistenceBytes\":\(limits.maximumPersistenceBytes),"
            + "\"maximumRetainedPayloadBytes\":\(limits.maximumRetainedPayloadBytes),"
            + "\"maximumSourceIdentifierBytes\":\(limits.maximumSourceIdentifierBytes),"
            + "\"maximumTypeIdentifierBytes\":\(limits.maximumTypeIdentifierBytes),"
            + "\"maximumWork\":\(limits.maximumWork)},"
            + "\"persistencePolicy\":\"\(policy.rawValue)\",\"revision\":\(revision),"
            + "\"schemaVersion\":2,\"selection\":[\(selected)]}"
        return Data(string.utf8)
    }

    private func emptyPersistence(maximumPersistenceBytes: Int) -> Data {
        Data(
            ("{\"entries\":[],\"limits\":{\"maximumEntries\":1,\"maximumPayloadBytes\":1,"
                + "\"maximumPersistenceBytes\":\(maximumPersistenceBytes),"
                + "\"maximumRetainedPayloadBytes\":1,\"maximumSourceIdentifierBytes\":1,"
                + "\"maximumTypeIdentifierBytes\":1,\"maximumWork\":10000},"
                + "\"persistencePolicy\":\"metadataOnly\",\"revision\":0,"
                + "\"schemaVersion\":2,\"selection\":[]}").utf8
        )
    }
}

private enum ClipboardHistoryCancellationOutcome: Sendable {
    case succeeded
    case cancelled
    case failed(String)
}
