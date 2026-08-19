import Darwin
import Foundation
import MacMergeCore
import XCTest

final class ClipboardComparisonTests: XCTestCase {
    func testTextSnapshotsPreserveContentAndMetadata() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 123)
        let left = try ClipboardSnapshot(
            text: "left\n",
            sourceLabel: "Editor",
            timestamp: timestamp,
            changeCount: 7,
            stableID: "capture-left"
        )
        let right = try ClipboardSnapshot(text: "right\n", stableID: "capture-right")

        let inputs = try ClipboardComparison.inputs(left: left, right: right)

        XCTAssertEqual(left.content, .text("left\n"))
        XCTAssertEqual(left.byteCount, 5)
        XCTAssertEqual(inputs.kind, .text)
        XCTAssertEqual(inputs.left.text, "left\n")
        XCTAssertEqual(inputs.right.text, "right\n")
        XCTAssertNil(inputs.left.binaryData)
        XCTAssertEqual(inputs.left.sourceLabel, "Editor")
        XCTAssertEqual(inputs.left.timestamp, timestamp)
        XCTAssertEqual(inputs.left.changeCount, 7)
        XCTAssertEqual(inputs.left.stableID, "capture-left")
        XCTAssertEqual(inputs.textValues?.left, "left\n")
        XCTAssertEqual(inputs.textValues?.right, "right\n")
        XCTAssertNil(inputs.binaryValues)
    }

    func testBinarySnapshotsPreserveBytesAndTypeIdentifiers() throws {
        let leftData = Data([0x00, 0x41, 0xFF])
        let rightData = Data([0x00, 0x42, 0xFF])
        let left = try ClipboardSnapshot(data: leftData, typeIdentifier: "public.data")
        let right = try ClipboardSnapshot(data: rightData, typeIdentifier: "public.data")

        let inputs = try ClipboardComparisonInputs(left: left, right: right)

        XCTAssertEqual(left.content, .binary(leftData, typeIdentifier: "public.data"))
        XCTAssertEqual(left.byteCount, 3)
        XCTAssertEqual(inputs.kind, .binary)
        XCTAssertEqual(inputs.left.binaryData, leftData)
        XCTAssertEqual(inputs.right.binaryData, rightData)
        XCTAssertEqual(inputs.left.binaryTypeIdentifier, "public.data")
        XCTAssertNil(inputs.left.text)
        XCTAssertEqual(inputs.binaryValues?.left, leftData)
        XCTAssertEqual(inputs.binaryValues?.right, rightData)
        XCTAssertNil(inputs.textValues)

        let sameBytesAsText = try ClipboardSnapshot(text: String(decoding: leftData, as: UTF8.self))
        XCTAssertNotEqual(left.contentID, sameBytesAsText.contentID)
    }

    func testCanonicallyEquivalentUnicodeHasConsistentEqualityAndIDs() throws {
        let nfc = "caf\u{00E9}"
        let nfd = "caf\u{0065}\u{0301}"
        XCTAssertEqual(nfc, nfd)
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8))

        let composedText = try ClipboardSnapshot(text: nfc)
        let decomposedText = try ClipboardSnapshot(text: nfd)
        XCTAssertEqual(composedText, decomposedText)
        XCTAssertEqual(composedText.contentID, decomposedText.contentID)
        XCTAssertEqual(composedText.id, decomposedText.id)

        let composedBinary = try ClipboardSnapshot(
            data: Data([0x00, 0xFF]),
            typeIdentifier: "public.\(nfc)"
        )
        let decomposedBinary = try ClipboardSnapshot(
            data: Data([0x00, 0xFF]),
            typeIdentifier: "public.\(nfd)"
        )
        XCTAssertEqual(composedBinary, decomposedBinary)
        XCTAssertEqual(composedBinary.contentID, decomposedBinary.contentID)
        XCTAssertEqual(composedBinary.id, decomposedBinary.id)
    }

    func testNULSourceAndStableMetadataIsRejected() throws {
        assertClipboardError(.invalidSourceLabel(nil)) {
            try ClipboardSnapshot(text: "value", sourceLabel: "source\u{0000}tail")
        }
        assertClipboardError(.invalidStableID(nil)) {
            try ClipboardSnapshot(text: "value", stableID: "stable\u{0000}tail")
        }
    }

    func testBinaryContentIDsSeparateExactLegacyNULCollisionPair() throws {
        let first = try ClipboardSnapshot(
            data: Data("c".utf8),
            typeIdentifier: "a\u{0000}b"
        )
        let second = try ClipboardSnapshot(
            data: Data("b\u{0000}c".utf8),
            typeIdentifier: "a"
        )

        let inputs = try ClipboardComparison.inputs(left: first, right: second)

        XCTAssertEqual(inputs.left.binaryTypeIdentifier, "a\u{0000}b")
        XCTAssertEqual(inputs.left.binaryData, Data("c".utf8))
        XCTAssertEqual(inputs.right.binaryTypeIdentifier, "a")
        XCTAssertEqual(inputs.right.binaryData, Data("b\u{0000}c".utf8))
        XCTAssertNotEqual(first.contentID, second.contentID)
    }

    func testEqualSnapshotOnBothSidesHasDistinctInputIDs() throws {
        let snapshot = try ClipboardSnapshot(text: "same", stableID: "capture")

        let inputs = try ClipboardComparison.inputs(left: snapshot, right: snapshot)

        XCTAssertEqual(inputs.left.stableID, inputs.right.stableID)
        XCTAssertEqual(inputs.left.id, "left:capture")
        XCTAssertEqual(inputs.right.id, "right:capture")
        XCTAssertNotEqual(inputs.left.id, inputs.right.id)
    }

    func testGenericTemporalAndCustomLabelsAreCoherent() throws {
        let unlabeledLeft = try ClipboardSnapshot(text: "left")
        let unlabeledRight = try ClipboardSnapshot(text: "right")

        let generic = try ClipboardComparison.inputs(left: unlabeledLeft, right: unlabeledRight)
        XCTAssertEqual(generic.left.sourceLabel, "Clipboard (Left)")
        XCTAssertEqual(generic.right.sourceLabel, "Clipboard (Right)")

        let temporal = try ClipboardComparison.inputs(previous: unlabeledLeft, latest: unlabeledRight)
        XCTAssertEqual(temporal.left.sourceLabel, "Clipboard (Previous)")
        XCTAssertEqual(temporal.right.sourceLabel, "Clipboard (Latest)")

        let customPrevious = try ClipboardSnapshot(text: "before", sourceLabel: "Source A")
        let customLatest = try ClipboardSnapshot(text: "after", sourceLabel: "Source B")
        let custom = try ClipboardComparison.inputs(previous: customPrevious, latest: customLatest)
        XCTAssertEqual(custom.left.sourceLabel, "Source A")
        XCTAssertEqual(custom.right.sourceLabel, "Source B")
    }

    func testEmptySnapshotVariantsReportTheirComparisonSide() throws {
        let empty = try ClipboardSnapshot(content: .empty, maximumBytes: 0)
        let emptyText = try ClipboardSnapshot(text: "", maximumBytes: 0)
        let emptyBinary = try ClipboardSnapshot(data: Data(), maximumBytes: 0)
        let value = try ClipboardSnapshot(text: "value")

        assertClipboardError(.emptySnapshot(.left)) {
            try ClipboardComparison.inputs(left: empty, right: value)
        }
        assertClipboardError(.emptySnapshot(.right)) {
            try ClipboardComparison.inputs(left: value, right: emptyText)
        }
        assertClipboardError(.emptySnapshot(.left)) {
            try ClipboardComparison.inputs(left: emptyBinary, right: value)
        }

        var history = ClipboardSnapshotHistory()
        assertClipboardError(.emptySnapshot(nil)) {
            try history.record(empty)
        }
    }

    func testBinaryKindAndSizeValidationErrorsAreSpecific() throws {
        let text = try ClipboardSnapshot(text: "text")
        let binary = try ClipboardSnapshot(data: Data([0x01]))
        assertClipboardError(.mixedContentKinds) {
            try ClipboardComparison.inputs(left: text, right: binary)
        }

        let binaryDisabled = ClipboardComparisonLimits(
            maximumSnapshotBytes: 10,
            maximumCombinedBytes: 20,
            allowsBinaryContent: false
        )
        assertClipboardError(.binaryContentNotAllowed(.left)) {
            try ClipboardComparison.inputs(left: binary, right: binary, limits: binaryDisabled)
        }

        let threeBytes = try ClipboardSnapshot(text: "abc", maximumBytes: 3)
        let oneByte = try ClipboardSnapshot(text: "x", maximumBytes: 3)
        let perSnapshotLimit = ClipboardComparisonLimits(
            maximumSnapshotBytes: 2,
            maximumCombinedBytes: 10
        )
        assertClipboardError(.snapshotTooLarge(.left, maximumBytes: 2)) {
            try ClipboardComparison.inputs(left: threeBytes, right: oneByte, limits: perSnapshotLimit)
        }
        assertClipboardError(.snapshotTooLarge(.right, maximumBytes: 2)) {
            try ClipboardComparison.inputs(left: oneByte, right: threeBytes, limits: perSnapshotLimit)
        }

        let combinedLimit = ClipboardComparisonLimits(
            maximumSnapshotBytes: 3,
            maximumCombinedBytes: 3
        )
        assertClipboardError(.combinedInputTooLarge(maximumBytes: 3)) {
            try ClipboardComparison.inputs(left: threeBytes, right: oneByte, limits: combinedLimit)
        }
    }

    func testSnapshotSizeBoundsRejectOversizedPublicInputs() throws {
        let multibyte = "\u{00E9}"
        let exactText = try ClipboardSnapshot(text: multibyte, maximumBytes: 2)
        XCTAssertEqual(exactText.byteCount, 2)
        assertClipboardError(.snapshotTooLarge(nil, maximumBytes: 1)) {
            try ClipboardSnapshot(text: multibyte, maximumBytes: 1)
        }

        let oversizedText = String(repeating: "x", count: 1_024 * 1_024)
        assertClipboardError(.snapshotTooLarge(nil, maximumBytes: 8)) {
            try ClipboardSnapshot(text: oversizedText, maximumBytes: 8)
        }

        let oversizedBinary = Data(repeating: 0xAA, count: 1_024 * 1_024)
        assertClipboardError(.snapshotTooLarge(nil, maximumBytes: 8)) {
            try ClipboardSnapshot(data: oversizedBinary, maximumBytes: 8)
        }
    }

    func testOversizedBinaryIsRejectedBeforeContentIDReadsPayload() throws {
        let pageSize = Int(getpagesize())
        guard
            let address = mmap(
                nil,
                pageSize,
                PROT_READ | PROT_WRITE,
                MAP_ANON | MAP_PRIVATE,
                -1,
                0
            ), address != MAP_FAILED
        else {
            XCTFail("Could not reserve test payload")
            return
        }
        let inaccessibleData = Data(
            bytesNoCopy: address,
            count: pageSize,
            deallocator: .custom { pointer, count in
                munmap(pointer, count)
            }
        )
        guard mprotect(address, pageSize, PROT_NONE) == 0 else {
            XCTFail("Could not protect test payload")
            return
        }

        assertClipboardError(.snapshotTooLarge(nil, maximumBytes: pageSize - 1)) {
            try ClipboardSnapshot(data: inaccessibleData, maximumBytes: pageSize - 1)
        }
    }

    func testHistoryMaintainsMRUOrderAndPromotesDuplicates() throws {
        let first = try snapshot("first", stableID: "first")
        let second = try snapshot("second", stableID: "second")
        let third = try snapshot("third", stableID: "third")
        var history = ClipboardSnapshotHistory(capacity: 4, maximumBytes: 100)

        XCTAssertTrue(try history.record(first))
        XCTAssertTrue(try history.record(second))
        XCTAssertTrue(try history.record(third))
        XCTAssertEqual(history.snapshots.map(\.stableID), ["third", "second", "first"])

        XCTAssertTrue(try history.record(first))
        XCTAssertEqual(history.snapshots.map(\.stableID), ["first", "third", "second"])
        XCTAssertFalse(try history.record(first))
        XCTAssertEqual(history.snapshots.map(\.stableID), ["first", "third", "second"])

        let inputs = try XCTUnwrap(history.comparisonInputs())
        XCTAssertEqual(inputs.left.text, "third")
        XCTAssertEqual(inputs.right.text, "first")
        XCTAssertEqual(inputs.left.sourceLabel, "Clipboard (Previous)")
        XCTAssertEqual(inputs.right.sourceLabel, "Clipboard (Latest)")
    }

    func testHistoryRemovesAllStableAndContentIDDedupeMatches() throws {
        let stableCollision = try snapshot("stable collision", stableID: "incoming")
        let unrelated = try snapshot("unrelated", stableID: "unrelated")
        let contentCollision = try snapshot("target", stableID: "old-content")
        let incoming = try snapshot("target", stableID: "incoming")
        var history = ClipboardSnapshotHistory(capacity: 10, maximumBytes: 100)

        try history.record(stableCollision)
        try history.record(unrelated)
        try history.record(contentCollision)
        XCTAssertEqual(
            history.snapshots.map(\.stableID),
            ["old-content", "unrelated", "incoming"]
        )
        XCTAssertEqual(
            history.snapshots.filter {
                $0.stableID == incoming.stableID || $0.contentID == incoming.contentID
            }.map(\.stableID),
            ["old-content", "incoming"]
        )

        XCTAssertTrue(try history.record(incoming))
        XCTAssertEqual(history.snapshots.map(\.stableID), ["incoming", "unrelated"])
        XCTAssertEqual(history.snapshots.filter { $0.stableID == incoming.stableID }.count, 1)
        XCTAssertEqual(history.snapshots.filter { $0.contentID == incoming.contentID }.count, 1)
        XCTAssertEqual(history.retainedByteCount, incoming.byteCount + unrelated.byteCount)
    }

    func testHistoryTrimsByCapacityAndTotalBytes() throws {
        let first = try snapshot("aa", stableID: "first")
        let second = try snapshot("bb", stableID: "second")
        let third = try snapshot("ccc", stableID: "third")

        var capacityBound = ClipboardSnapshotHistory(capacity: 2, maximumBytes: 100)
        try capacityBound.record(first)
        try capacityBound.record(second)
        try capacityBound.record(third)
        XCTAssertEqual(capacityBound.snapshots.map(\.stableID), ["third", "second"])
        XCTAssertEqual(capacityBound.retainedByteCount, 5)

        var byteBound = ClipboardSnapshotHistory(capacity: 10, maximumBytes: 5)
        try byteBound.record(first)
        try byteBound.record(second)
        try byteBound.record(third)
        XCTAssertEqual(byteBound.snapshots.map(\.stableID), ["third", "second"])
        XCTAssertEqual(byteBound.retainedByteCount, 5)

        let fillsBudget = try snapshot("12345", stableID: "budget")
        try byteBound.record(fillsBudget)
        XCTAssertEqual(byteBound.snapshots.map(\.stableID), ["budget"])
        XCTAssertEqual(byteBound.retainedByteCount, 5)

        byteBound.removeAll()
        XCTAssertTrue(byteBound.isEmpty)
        XCTAssertEqual(byteBound.count, 0)
        XCTAssertEqual(byteBound.retainedByteCount, 0)
        XCTAssertNil(byteBound.latest)
        XCTAssertNil(try byteBound.comparisonInputs())
    }

    func testMaximumIntegerLimitsAndByteBudgetBoundariesPreservePublicState() throws {
        let left = try ClipboardSnapshot(text: "left", maximumBytes: Int.max)
        let right = try ClipboardSnapshot(text: "right", maximumBytes: Int.max)
        let unbounded = ClipboardComparisonLimits(
            maximumSnapshotBytes: Int.max,
            maximumCombinedBytes: Int.max
        )
        let inputs = try ClipboardComparison.inputs(left: left, right: right, limits: unbounded)
        XCTAssertEqual(inputs.left.byteCount + inputs.right.byteCount, 9)

        let exactCombined = ClipboardComparisonLimits(
            maximumSnapshotBytes: Int.max,
            maximumCombinedBytes: 9
        )
        XCTAssertNoThrow(
            try ClipboardComparison.inputs(left: left, right: right, limits: exactCombined)
        )
        let oneByteShort = ClipboardComparisonLimits(
            maximumSnapshotBytes: Int.max,
            maximumCombinedBytes: 8
        )
        assertClipboardError(.combinedInputTooLarge(maximumBytes: 8)) {
            try ClipboardComparison.inputs(left: left, right: right, limits: oneByteShort)
        }

        var history = ClipboardSnapshotHistory(capacity: Int.max, maximumBytes: Int.max)
        XCTAssertTrue(try history.record(left))
        XCTAssertTrue(try history.record(right))
        XCTAssertEqual(history.retainedByteCount, 9)

        let tooLarge = try ClipboardSnapshot(text: "four", maximumBytes: Int.max)
        var smallHistory = ClipboardSnapshotHistory(capacity: Int.max, maximumBytes: 3)
        let originalSnapshots = smallHistory.snapshots
        assertClipboardError(.snapshotTooLarge(nil, maximumBytes: 3)) {
            try smallHistory.record(tooLarge)
        }
        XCTAssertEqual(smallHistory.snapshots, originalSnapshots)
        XCTAssertEqual(smallHistory.retainedByteCount, 0)

        var exactHistory = ClipboardSnapshotHistory(capacity: Int.max, maximumBytes: 9)
        try exactHistory.record(left)
        try exactHistory.record(right)
        XCTAssertEqual(exactHistory.snapshots.map(\.content), [.text("right"), .text("left")])
        XCTAssertEqual(exactHistory.retainedByteCount, 9)

        let replacement = try ClipboardSnapshot(text: "123456", maximumBytes: Int.max)
        XCTAssertTrue(try exactHistory.record(replacement))
        XCTAssertEqual(exactHistory.snapshots.map(\.content), [.text("123456")])
        XCTAssertEqual(exactHistory.retainedByteCount, 6)
    }

    private func snapshot(_ text: String, stableID: String) throws -> ClipboardSnapshot {
        try ClipboardSnapshot(text: text, stableID: stableID)
    }

    private func assertClipboardError<T>(
        _ expected: ClipboardComparisonError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ClipboardComparisonError, expected, file: file, line: line)
        }
    }
}
