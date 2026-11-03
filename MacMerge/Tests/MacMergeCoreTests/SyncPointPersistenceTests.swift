import Foundation
import XCTest

@testable import MacMergeCore

final class SyncPointPersistenceTests: XCTestCase {
    func testEmptyAndPopulatedStoresRoundTrip() throws {
        let empty = SyncPointPersistence()
        XCTAssertEqual(try SyncPointPersistence.decode(from: empty.encodedData()), empty)

        var store = SyncPointPersistence()
        let firstID = SyncPointComparisonIdentity()
        let secondID = SyncPointComparisonIdentity()
        let firstPoints = try points([(1, 1), (3, 3)])
        let secondPoints = try points([(0, 2)])

        let firstReceipt = try store.set(firstPoints, for: firstID, leftLineCount: 4, rightLineCount: 4)
        let secondReceipt = try store.set(secondPoints, for: secondID, leftLineCount: 2, rightLineCount: 3)

        XCTAssertEqual(firstReceipt.comparisonID, firstID)
        XCTAssertEqual(firstReceipt.anchorCount, 2)
        XCTAssertEqual(firstReceipt.leftLineCount, 4)
        XCTAssertEqual(firstReceipt.rightLineCount, 4)
        XCTAssertEqual(secondReceipt.comparisonID, secondID)
        XCTAssertEqual(secondReceipt.anchorCount, 1)
        XCTAssertEqual(secondReceipt.leftLineCount, 2)
        XCTAssertEqual(secondReceipt.rightLineCount, 3)
        XCTAssertEqual(firstReceipt.schemaVersion, SyncPointPersistence.currentSchemaVersion)
        XCTAssertEqual(secondReceipt.schemaVersion, SyncPointPersistence.currentSchemaVersion)

        let decoded = try SyncPointPersistence.decode(from: store.encodedData())
        XCTAssertEqual(decoded, store)
        XCTAssertEqual(decoded.points(for: firstID), firstPoints)
        XCTAssertEqual(decoded.lineCounts(for: secondID)?.left, 2)
        XCTAssertEqual(decoded.lineCounts(for: secondID)?.right, 3)
    }

    func testSetRejectsOutOfBoundsAnchors() throws {
        var store = SyncPointPersistence()
        let id = SyncPointComparisonIdentity()

        XCTAssertThrowsError(
            try store.set(try points([(2, 3)]), for: id, leftLineCount: 2, rightLineCount: 4)
        ) { error in
            XCTAssertEqual(
                error as? SynchronizationPointsError,
                .leftSourceLineOutOfBounds(line: 2, lineCount: 2)
            )
        }
        XCTAssertTrue(store.isEmpty)
    }

    func testDecodeRejectsNullAndWrongTypes() {
        for payload in [
            #"{"entries":null,"schemaVersion":1}"#,
            #"{"entries":{},"schemaVersion":1}"#,
            #"{"entries":[],"schemaVersion":"1"}"#,
            #"{"entries":[{"comparisonID":"not-a-uuid","leftLineCount":1,"rightLineCount":1,"synchronizationPoints":{"anchors":[]}}],"schemaVersion":1}"#,
            #"{"entries":[{"comparisonID":"00000000-0000-0000-0000-000000000000","leftLineCount":"1","rightLineCount":1,"synchronizationPoints":{"anchors":[]}}],"schemaVersion":1}"#,
            #"{"entries":[{"comparisonID":"00000000-0000-0000-0000-000000000000","leftLineCount":1,"rightLineCount":1,"synchronizationPoints":{"anchors":null}}],"schemaVersion":1}"#,
            #"{"entries":[{"comparisonID":"00000000-0000-0000-0000-000000000000","leftLineCount":1,"rightLineCount":1,"synchronizationPoints":{"anchors":{}}}],"schemaVersion":1}"#
        ] {
            XCTAssertThrowsError(
                try SyncPointPersistence.decode(from: Data(payload.utf8)),
                "Payload unexpectedly decoded: \(payload)"
            )
        }
    }

    func testDecodeRejectsUnknownAndDuplicateKeys() {
        let uuid = UUID().uuidString
        let entry =
            #"{"comparisonID":"\#(uuid)","leftLineCount":1,"rightLineCount":1,"synchronizationPoints":{"anchors":[{"leftSourceLine":0,"rightSourceLine":0}]}}"#
        let payloads = [
            #"{"entries":[],"schemaVersion":1,"extra":1}"#,
            #"{"entries":[],"schemaVersion":1,"schemaVersion":1}"#,
            #"{"entries":[\#(entry),\#(entry)],"schemaVersion":1}"#,
            #"{"entries":[{"comparisonID":"\#(uuid)","leftLineCount":1,"rightLineCount":1,"synchronizationPoints":{"anchors":[{"leftSourceLine":0,"rightSourceLine":0}],"extra":[]}}],"schemaVersion":1}"#
        ]
        for payload in payloads {
            XCTAssertThrowsError(
                try SyncPointPersistence.decode(from: Data(payload.utf8)),
                "Payload unexpectedly decoded: \(payload)"
            )
        }
    }

    func testDecodeRejectsOutOfBoundsAnchors() throws {
        let uuid = UUID().uuidString
        let payload =
            #"{"entries":[{"comparisonID":"\#(uuid)","leftLineCount":2,"rightLineCount":2,"synchronizationPoints":{"anchors":[{"leftSourceLine":5,"rightSourceLine":0}]}}],"schemaVersion":1}"#

        XCTAssertThrowsError(try SyncPointPersistence.decode(from: Data(payload.utf8)))
    }

    func testDecodeRejectsNonCanonicalEncoding() throws {
        var store = SyncPointPersistence()
        let id = SyncPointComparisonIdentity()
        _ = try store.set(try points([(0, 0)]), for: id, leftLineCount: 1, rightLineCount: 1)
        let canonical = try store.encodedData()
        let uuid = id.rawValue.uuidString

        XCTAssertThrowsError(try SyncPointPersistence.decode(from: canonical + Data(" ".utf8)))
        XCTAssertThrowsError(
            try SyncPointPersistence.decode(
                from: Data(
                    #"{"schemaVersion":1,"entries":[{"synchronizationPoints":{"anchors":[{"rightSourceLine":0,"leftSourceLine":0}]},"rightLineCount":1,"leftLineCount":1,"comparisonID":"\#(uuid)"}]}"#.utf8
                )
            )
        )
        let spaced = String(decoding: canonical, as: UTF8.self).replacingOccurrences(of: ",", with: ", ")
        XCTAssertThrowsError(try SyncPointPersistence.decode(from: Data(spaced.utf8)))
    }

    func testDecodeRejectsUnsupportedSchemaVersion() {
        let payload = #"{"entries":[],"schemaVersion":2}"#

        XCTAssertThrowsError(try SyncPointPersistence.decode(from: Data(payload.utf8))) { error in
            XCTAssertEqual(error as? SyncPointPersistenceError, .unsupportedSchemaVersion(2))
        }
    }

    func testDecodeRejectsDeepNesting() {
        let nesting = String(repeating: "[", count: 20) + String(repeating: "]", count: 20)
        let payload = #"{"entries":\#(nesting),"schemaVersion":1}"#

        XCTAssertThrowsError(try SyncPointPersistence.decode(from: Data(payload.utf8))) { error in
            XCTAssertEqual(error as? SyncPointPersistenceError, .jsonNestingTooDeep(maximumDepth: 16))
        }
    }

    func testDecodeRejectsPreflightLimits() {
        let manyElements = String(repeating: "0,", count: 65536) + "0"
        let containerPayload = #"{"entries":[\#(manyElements)],"schemaVersion":1}"#
        XCTAssertThrowsError(try SyncPointPersistence.decode(from: Data(containerPayload.utf8))) { error in
            XCTAssertEqual(error as? SyncPointPersistenceError, .jsonContainerTooLarge(maximumElements: 65536))
        }
        let chunk = String(repeating: "0,", count: 62499) + "0"
        let inner = "[" + chunk + "]"
        let wide = Array(repeating: inner, count: 16).joined(separator: ",")
        let valuesPayload = #"{"entries":[\#(wide)],"schemaVersion":1}"#
        XCTAssertThrowsError(try SyncPointPersistence.decode(from: Data(valuesPayload.utf8))) { error in
            XCTAssertEqual(error as? SyncPointPersistenceError, .tooManyJSONValues(maximumValues: 1000000))
        }
        let longString = String(repeating: "a", count: 129)
        let stringPayload = #"{"entries":[],"schemaVersion":1,"k":"\#(longString)"}"#
        XCTAssertThrowsError(try SyncPointPersistence.decode(from: Data(stringPayload.utf8))) { error in
            XCTAssertEqual(error as? SyncPointPersistenceError, .jsonStringTooLarge(maximumBytes: 128))
        }
        let longNumber = String(repeating: "1", count: 33)
        let numberPayload = #"{"entries":[],"schemaVersion":1,"k":\#(longNumber)}"#
        XCTAssertThrowsError(try SyncPointPersistence.decode(from: Data(numberPayload.utf8))) { error in
            XCTAssertEqual(error as? SyncPointPersistenceError, .jsonNumberTooLarge(maximumBytes: 32))
        }
    }

    func testStoreEnforcesMaximumEntryCount() throws {
        var store = SyncPointPersistence()
        let firstID = SyncPointComparisonIdentity()
        _ = try store.set(
            SynchronizationPoints(),
            for: firstID,
            leftLineCount: 0,
            rightLineCount: 0
        )
        for _ in 1..<SyncPointPersistence.maximumEntries {
            _ = try store.set(
                SynchronizationPoints(),
                for: SyncPointComparisonIdentity(),
                leftLineCount: 0,
                rightLineCount: 0
            )
        }
        XCTAssertEqual(store.count, SyncPointPersistence.maximumEntries)
        let overwriteReceipt = try store.set(
            try points([(0, 0)]),
            for: firstID,
            leftLineCount: 1,
            rightLineCount: 1
        )
        XCTAssertEqual(overwriteReceipt.comparisonID, firstID)
        XCTAssertEqual(store.count, SyncPointPersistence.maximumEntries)

        XCTAssertThrowsError(
            try store.set(
                SynchronizationPoints(),
                for: SyncPointComparisonIdentity(),
                leftLineCount: 0,
                rightLineCount: 0
            )
        ) { error in
            XCTAssertEqual(
                error as? SyncPointPersistenceError,
                .tooManyEntries(maximum: SyncPointPersistence.maximumEntries)
            )
        }
        XCTAssertEqual(store.count, SyncPointPersistence.maximumEntries)
    }

    func testDecodeRejectsTooManyEntries() {
        let uuid = UUID().uuidString
        let entry =
            #"{"comparisonID":"\#(uuid)","leftLineCount":0,"rightLineCount":0,"synchronizationPoints":{"anchors":[]}}"#
        var joined = ""
        joined.reserveCapacity(entry.count * (SyncPointPersistence.maximumEntries + 1))
        for index in 0...SyncPointPersistence.maximumEntries {
            if index > 0 { joined += "," }
            joined += entry
        }
        let payload = #"{"entries":[\#(joined)],"schemaVersion":1}"#

        XCTAssertThrowsError(try SyncPointPersistence.decode(from: Data(payload.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("entry limit"))
        }
    }

    func testDecodeRejectsOversizedInput() {
        let oversized = Data(count: SyncPointPersistence.maximumPersistedBytes + 1)

        XCTAssertThrowsError(try SyncPointPersistence.decode(from: oversized)) { error in
            XCTAssertEqual(
                error as? SyncPointPersistenceError,
                .persistedDataTooLarge(maximumBytes: SyncPointPersistence.maximumPersistedBytes)
            )
        }
    }

    func testEncodeRejectsOversizedStore() throws {
        var store = SyncPointPersistence()
        for _ in 0..<2 {
            let anchors = try fullAnchors(count: SynchronizationPoints.maximumAnchorCount)
            _ = try store.set(
                try SynchronizationPoints(anchors: anchors),
                for: SyncPointComparisonIdentity(),
                leftLineCount: SynchronizationPoints.maximumAnchorCount,
                rightLineCount: SynchronizationPoints.maximumAnchorCount
            )
        }

        XCTAssertThrowsError(try store.encodedData()) { error in
            XCTAssertEqual(
                error as? SyncPointPersistenceError,
                .encodedDataTooLarge(maximumBytes: SyncPointPersistence.maximumEncodedBytes)
            )
        }
    }

    func testRemapRejectsStaleLineCountWithoutMutating() throws {
        var store = SyncPointPersistence()
        let id = SyncPointComparisonIdentity()
        let original = try points([(1, 1), (3, 3), (6, 6)])
        _ = try store.set(original, for: id, leftLineCount: 10, rightLineCount: 10)

        XCTAssertThrowsError(
            try store.remap(
                id,
                afterEditing: .left,
                replacing: 2..<5,
                withLineCount: 1,
                currentLineCount: 9
            )
        ) { error in
            XCTAssertEqual(error as? SyncPointPersistenceError, .staleLineCount(expected: 10, actual: 9))
        }
        XCTAssertEqual(store.points(for: id), original)
        XCTAssertEqual(store.lineCounts(for: id)?.left, 10)
        XCTAssertEqual(store.lineCounts(for: id)?.right, 10)
        XCTAssertThrowsError(
            try store.remap(
                id,
                afterEditing: .right,
                replacing: 2..<5,
                withLineCount: 1,
                currentLineCount: 9
            )
        ) { error in
            XCTAssertEqual(error as? SyncPointPersistenceError, .staleLineCount(expected: 10, actual: 9))
        }
        XCTAssertEqual(store.points(for: id), original)
        XCTAssertEqual(store.lineCounts(for: id)?.left, 10)
        XCTAssertEqual(store.lineCounts(for: id)?.right, 10)

        let receipt = try store.remap(
            id,
            afterEditing: .left,
            replacing: 2..<5,
            withLineCount: 1,
            currentLineCount: 10
        )
        XCTAssertEqual(receipt.comparisonID, id)
        XCTAssertEqual(receipt.anchorCount, 2)
        XCTAssertEqual(receipt.leftLineCount, 8)
        XCTAssertEqual(receipt.rightLineCount, 10)
        XCTAssertEqual(store.points(for: id)?.anchors, try points([(1, 1), (4, 6)]).anchors)
        XCTAssertEqual(store.lineCounts(for: id)?.left, 8)
        XCTAssertEqual(store.lineCounts(for: id)?.right, 10)
    }

    func testRemapRejectsUnknownComparisonIdentity() {
        var store = SyncPointPersistence()
        let unknown = SyncPointComparisonIdentity()

        XCTAssertThrowsError(
            try store.remap(
                unknown,
                afterEditing: .right,
                replacing: 0..<0,
                withLineCount: 0,
                currentLineCount: 0
            )
        ) { error in
            XCTAssertEqual(
                error as? SyncPointPersistenceError,
                .unknownComparisonIdentity(unknown.rawValue.uuidString)
            )
        }
    }

    func testDecodeAndRemapReturnsReceiptsAndDroppedCounts() throws {
        var store = SyncPointPersistence()
        let id = SyncPointComparisonIdentity()
        _ = try store.set(try points([(1, 1), (3, 3), (6, 6)]), for: id, leftLineCount: 10, rightLineCount: 10)
        let data = try store.encodedData()

        let edit = SyncPointPersistenceEdit(
            comparisonID: id,
            side: .left,
            range: 2..<5,
            insertedLineCount: 1,
            currentLineCount: 10
        )
        let result = try SyncPointPersistence.decodeAndRemap(from: data, applying: [edit])

        XCTAssertEqual(result.receipts.count, 1)
        XCTAssertEqual(result.droppedAnchorCount, 1)
        XCTAssertEqual(result.receipts[0].comparisonID, id)
        XCTAssertEqual(result.receipts[0].anchorCount, 2)
        XCTAssertEqual(result.receipts[0].leftLineCount, 8)
        XCTAssertEqual(result.store.points(for: id)?.anchors, try points([(1, 1), (4, 6)]).anchors)
    }

    func testDecodeAndRemapFailurePublishesNothing() throws {
        var store = SyncPointPersistence()
        let id = SyncPointComparisonIdentity()
        _ = try store.set(try points([(1, 1)]), for: id, leftLineCount: 4, rightLineCount: 4)
        let data = try store.encodedData()
        let preEdit = store

        let edits = [
            SyncPointPersistenceEdit(
                comparisonID: id,
                side: .left,
                range: 0..<0,
                insertedLineCount: 0,
                currentLineCount: 4
            ),
            SyncPointPersistenceEdit(
                comparisonID: SyncPointComparisonIdentity(),
                side: .left,
                range: 0..<0,
                insertedLineCount: 0,
                currentLineCount: 0
            )
        ]
        do {
            _ = try SyncPointPersistence.decodeAndRemap(from: data, applying: edits)
            XCTFail("decodeAndRemap unexpectedly succeeded")
        } catch {
            XCTAssertNotNil(error as? SyncPointPersistenceError)
        }
        XCTAssertEqual(try SyncPointPersistence.decode(from: data), preEdit)
    }

    func testRemoveReturnsFinalReceipt() throws {
        var store = SyncPointPersistence()
        let id = SyncPointComparisonIdentity()
        _ = try store.set(try points([(0, 0), (2, 2)]), for: id, leftLineCount: 4, rightLineCount: 5)

        let receipt = store.remove(id)
        XCTAssertEqual(receipt?.comparisonID, id)
        XCTAssertEqual(receipt?.anchorCount, 0)
        XCTAssertEqual(receipt?.leftLineCount, 4)
        XCTAssertEqual(receipt?.rightLineCount, 5)
        XCTAssertNil(store.points(for: id))
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.remove(id))
        XCTAssertNil(store.remove(SyncPointComparisonIdentity()))
    }

    private func points(_ pairs: [(Int, Int)]) throws -> SynchronizationPoints {
        try SynchronizationPoints(
            anchors: pairs.map { try SynchronizationPoint(leftSourceLine: $0.0, rightSourceLine: $0.1) }
        )
    }

    private func fullAnchors(count: Int) throws -> [SynchronizationPoint] {
        var anchors: [SynchronizationPoint] = []
        anchors.reserveCapacity(count)
        for index in 0..<count {
            anchors.append(try SynchronizationPoint(leftSourceLine: index, rightSourceLine: index))
        }
        return anchors
    }
}
