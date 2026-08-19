import XCTest
@testable import MacMergeCore

final class ComparisonSnapshotByteIdentityTests: XCTestCase {
    private let nfc = "caf\u{00E9}"
    private let nfd = "caf\u{0065}\u{0301}"

    func testSnapshotsWithEqualUTF8BytesCompareEqualOnBothSides() {
        let original = "A\u{0000}\u{00E9}\u{1F642}\r\n"
        let rebuilt = String(decoding: Array(original.utf8), as: UTF8.self)

        XCTAssertEqual(Array(original.utf8), Array(rebuilt.utf8))
        for side in Side.allCases {
            let lhs = snapshot(side: side, text: original)
            let rhs = snapshot(side: side, text: rebuilt)

            XCTAssertEqual(lhs, rhs, side.rawValue)
            XCTAssertEqual(rhs, lhs, side.rawValue)
        }
    }

    func testNFCAndNFDCompareUnequalOnBothSides() {
        XCTAssertEqual(nfc, nfd, "Fixture must be canonically equivalent under Swift String equality")
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8))
        XCTAssertNotEqual(nfc.unicodeScalars.map(\.value), nfd.unicodeScalars.map(\.value))

        for side in Side.allCases {
            let composed = snapshot(side: side, text: nfc)
            let decomposed = snapshot(side: side, text: nfd)

            XCTAssertFalse(composed == decomposed, side.rawValue)
            XCTAssertFalse(decomposed == composed, side.rawValue)
        }
    }

    func testDifferentUnicodeScalarsCompareUnequalOnBothSides() {
        let acute = "caf\u{00E9}"
        let circumflex = "caf\u{00EA}"

        XCTAssertEqual(acute.utf8.count, circumflex.utf8.count)
        XCTAssertNotEqual(acute.unicodeScalars.map(\.value), circumflex.unicodeScalars.map(\.value))
        for side in Side.allCases {
            XCTAssertNotEqual(
                snapshot(side: side, text: acute),
                snapshot(side: side, text: circumflex),
                side.rawValue
            )
        }
    }

    func testEqualLengthDistinctUTF8CombiningOrderComparesUnequalOnBothSides() {
        let acuteThenDotBelow = "a\u{0301}\u{0323}"
        let dotBelowThenAcute = "a\u{0323}\u{0301}"

        XCTAssertEqual(acuteThenDotBelow, dotBelowThenAcute, "Fixture must be canonically equivalent")
        XCTAssertEqual(acuteThenDotBelow.utf8.count, dotBelowThenAcute.utf8.count)
        XCTAssertNotEqual(Array(acuteThenDotBelow.utf8), Array(dotBelowThenAcute.utf8))
        for side in Side.allCases {
            let lhs = snapshot(side: side, text: acuteThenDotBelow)
            let rhs = snapshot(side: side, text: dotBelowThenAcute)

            XCTAssertFalse(lhs == rhs, side.rawValue)
            XCTAssertFalse(rhs == lhs, side.rawValue)
        }
    }

    func testExactDuplicateHistoryUpdatesAreNoOpsOnBothSides() throws {
        for side in Side.allCases {
            let initial = snapshot(side: side, text: "same\u{00E9}\n")
            let rebuilt = snapshot(
                side: side,
                text: String(decoding: Array(text(on: side, in: initial).utf8), as: UTF8.self)
            )
            var history = ComparisonHistory(current: snapshot(side: side, text: "before"))

            XCTAssertTrue(history.commit(initial), side.rawValue)
            XCTAssertTrue(history.commit(snapshot(side: side, text: "after")), side.rawValue)
            assertSnapshotBytesEqual(
                try XCTUnwrap(history.undo(), "\(side.rawValue) seed redo"),
                initial,
                "\(side.rawValue) seed redo"
            )
            XCTAssertTrue(history.canUndo, "\(side.rawValue): seeded undo must remain")
            XCTAssertTrue(history.canRedo, "\(side.rawValue): seeded redo must remain")

            XCTAssertFalse(history.commit(rebuilt), side.rawValue)
            XCTAssertFalse(history.replaceCurrent(rebuilt), side.rawValue)
            XCTAssertTrue(history.canUndo, "\(side.rawValue): duplicate updates must preserve undo")
            XCTAssertTrue(history.canRedo, "\(side.rawValue): duplicate updates must preserve redo")
            assertSnapshotBytesEqual(history.current, initial, side.rawValue)
        }
    }

    func testHistoryPreservesNFCAndNFDThroughUndoRedoOnBothSides() throws {
        for side in Side.allCases {
            let composed = snapshot(side: side, text: nfc)
            let decomposed = snapshot(side: side, text: nfd)
            var history = ComparisonHistory(current: composed)

            XCTAssertTrue(history.commit(decomposed), side.rawValue)
            assertSnapshotBytesEqual(history.current, decomposed, "\(side.rawValue) commit")
            XCTAssertTrue(history.canUndo, side.rawValue)
            XCTAssertFalse(history.canRedo, side.rawValue)

            let undone = try XCTUnwrap(history.undo(), "\(side.rawValue) undo")
            assertSnapshotBytesEqual(undone, composed, "\(side.rawValue) undo")
            assertSnapshotBytesEqual(history.current, composed, "\(side.rawValue) current after undo")
            XCTAssertFalse(history.canUndo, side.rawValue)
            XCTAssertTrue(history.canRedo, side.rawValue)

            let redone = try XCTUnwrap(history.redo(), "\(side.rawValue) redo")
            assertSnapshotBytesEqual(redone, decomposed, "\(side.rawValue) redo")
            assertSnapshotBytesEqual(history.current, decomposed, "\(side.rawValue) current after redo")
            XCTAssertTrue(history.canUndo, side.rawValue)
            XCTAssertFalse(history.canRedo, side.rawValue)
        }
    }

    func testRedundantUndoDiscardUsesByteIdentityOnBothSides() throws {
        for side in Side.allCases {
            let composed = snapshot(side: side, text: nfc)
            let decomposed = snapshot(side: side, text: nfd)
            var history = ComparisonHistory(current: composed)

            XCTAssertTrue(history.commit(decomposed), side.rawValue)
            XCTAssertTrue(history.canUndo, "\(side.rawValue): byte-distinct undo must exist before discard")
            history.discardRedundantUndo()
            XCTAssertTrue(history.canUndo, "\(side.rawValue): byte-distinct undo must remain")
            assertSnapshotBytesEqual(
                try XCTUnwrap(history.undo(), "\(side.rawValue) retained undo"),
                composed,
                "\(side.rawValue) retained undo"
            )

            assertSnapshotBytesEqual(
                try XCTUnwrap(history.redo(), "\(side.rawValue) redo before exact discard"),
                decomposed,
                "\(side.rawValue) redo before exact discard"
            )
            XCTAssertTrue(history.replaceCurrent(composed), side.rawValue)
            XCTAssertFalse(history.canUndo, "\(side.rawValue): redundant undo must not be actionable")
            history.discardRedundantUndo()
            XCTAssertFalse(history.canUndo, "\(side.rawValue): byte-identical undo must be discarded")
            XCTAssertNil(history.undo(), side.rawValue)
        }
    }

    private func snapshot(side: Side, text: String) -> ComparisonSnapshot {
        switch side {
        case .left:
            ComparisonSnapshot(left: text, right: "stable-right\u{1F642}")
        case .right:
            ComparisonSnapshot(left: "stable-left\u{1F642}", right: text)
        }
    }

    private func text(on side: Side, in snapshot: ComparisonSnapshot) -> String {
        switch side {
        case .left: snapshot.left
        case .right: snapshot.right
        }
    }

    private func assertSnapshotBytesEqual(
        _ actual: ComparisonSnapshot,
        _ expected: ComparisonSnapshot,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Array(actual.left.utf8), Array(expected.left.utf8), "\(context): left", file: file, line: line)
        XCTAssertEqual(Array(actual.right.utf8), Array(expected.right.utf8), "\(context): right", file: file, line: line)
    }

    private enum Side: String, CaseIterable {
        case left
        case right
    }
}
