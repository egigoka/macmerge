import Foundation
import MacMergeCore
import XCTest

final class BinaryLookingTextTests: XCTestCase {
    func testUTF16BOMOverridesNULBasedBinaryDetection() throws {
        let data = Data([0xFF, 0xFE, 0x41, 0x00, 0x0A, 0x00, 0x42, 0x00])

        let decoded = try TextFileCodec.decode(data)

        XCTAssertEqual(decoded.encoding, .utf16LittleEndian)
        XCTAssertEqual(decoded.text, "A\nB")
        XCTAssertEqual(try TextFileCodec.encode(decoded), data)
    }

    func testNULFreeControlBytesRemainTextLikeWinMergePolicy() throws {
        let data = Data([0x01, 0x02, 0x03])

        let decoded = try TextFileCodec.decode(data)

        XCTAssertEqual(decoded.encoding, .utf8)
        XCTAssertEqual(Array(decoded.text.utf8), Array(data))
        XCTAssertEqual(try TextFileCodec.encode(decoded), data)
    }

    func testUndecodableBinaryLookingStreamFailsClosed() {
        let data = Data([0x81, 0x98, 0x80])

        XCTAssertThrowsError(try TextFileCodec.decode(data)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .invalidTextEncoding)
        }
    }

    func testForcedTextComparisonDoesNotTruncateAtEmbeddedNUL() throws {
        let rows = try LineDiff.compare(
            left: "prefix\0left\nsame",
            right: "prefix\0right\nsame"
        )

        XCTAssertEqual(rows.map(\.kind), [.modified, .unchanged])
        XCTAssertEqual(rows[0].left?.text, "prefix\0left")
        XCTAssertEqual(rows[0].right?.text, "prefix\0right")
        XCTAssertEqual(rows[1].left?.text, "same")
        XCTAssertEqual(rows[1].right?.text, "same")
    }
}
