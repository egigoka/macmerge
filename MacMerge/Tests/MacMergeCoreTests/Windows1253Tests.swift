import Foundation
import MacMergeCore
import XCTest

final class Windows1253Tests: XCTestCase {
    private let undefinedBytes: Set<UInt8> = [
        0x81, 0x88, 0x8A, 0x8C, 0x8D, 0x8E, 0x8F, 0x90, 0x98,
        0x9A, 0x9C, 0x9D, 0x9E, 0x9F, 0xAA, 0xD2, 0xFF
    ]

    // Unicode Consortium vendor mapping for Microsoft CP1253, indexed by byte.
    private let scalarOracle: [UInt32?] = [
        0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007,
        0x0008, 0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x000E, 0x000F,
        0x0010, 0x0011, 0x0012, 0x0013, 0x0014, 0x0015, 0x0016, 0x0017,
        0x0018, 0x0019, 0x001A, 0x001B, 0x001C, 0x001D, 0x001E, 0x001F,
        0x0020, 0x0021, 0x0022, 0x0023, 0x0024, 0x0025, 0x0026, 0x0027,
        0x0028, 0x0029, 0x002A, 0x002B, 0x002C, 0x002D, 0x002E, 0x002F,
        0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037,
        0x0038, 0x0039, 0x003A, 0x003B, 0x003C, 0x003D, 0x003E, 0x003F,
        0x0040, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047,
        0x0048, 0x0049, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F,
        0x0050, 0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057,
        0x0058, 0x0059, 0x005A, 0x005B, 0x005C, 0x005D, 0x005E, 0x005F,
        0x0060, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067,
        0x0068, 0x0069, 0x006A, 0x006B, 0x006C, 0x006D, 0x006E, 0x006F,
        0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075, 0x0076, 0x0077,
        0x0078, 0x0079, 0x007A, 0x007B, 0x007C, 0x007D, 0x007E, 0x007F,
        0x20AC, nil, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        nil, 0x2030, nil, 0x2039, nil, nil, nil, nil,
        nil, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        nil, 0x2122, nil, 0x203A, nil, nil, nil, nil,
        0x00A0, 0x0385, 0x0386, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7,
        0x00A8, 0x00A9, nil, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x2015,
        0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x0384, 0x00B5, 0x00B6, 0x00B7,
        0x0388, 0x0389, 0x038A, 0x00BB, 0x038C, 0x00BD, 0x038E, 0x038F,
        0x0390, 0x0391, 0x0392, 0x0393, 0x0394, 0x0395, 0x0396, 0x0397,
        0x0398, 0x0399, 0x039A, 0x039B, 0x039C, 0x039D, 0x039E, 0x039F,
        0x03A0, 0x03A1, nil, 0x03A3, 0x03A4, 0x03A5, 0x03A6, 0x03A7,
        0x03A8, 0x03A9, 0x03AA, 0x03AB, 0x03AC, 0x03AD, 0x03AE, 0x03AF,
        0x03B0, 0x03B1, 0x03B2, 0x03B3, 0x03B4, 0x03B5, 0x03B6, 0x03B7,
        0x03B8, 0x03B9, 0x03BA, 0x03BB, 0x03BC, 0x03BD, 0x03BE, 0x03BF,
        0x03C0, 0x03C1, 0x03C2, 0x03C3, 0x03C4, 0x03C5, 0x03C6, 0x03C7,
        0x03C8, 0x03C9, 0x03CA, 0x03CB, 0x03CC, 0x03CD, 0x03CE, nil
    ]

    func testRepresentativeGreekStreamsRoundTripExactly() throws {
        let fixtures: [(Data, String)] = [
            (Data([0xC5, 0xEB, 0xEB, 0xE7, 0xED, 0xE9, 0xEA, 0xDC, 0x0D, 0x0A]), "Ελληνικά\r\n"),
            (Data([0xA2, 0xEB, 0xF6, 0xE1, 0x20, 0xD9, 0xEC, 0xDD, 0xE3, 0xE1]), "Άλφα Ωμέγα"),
            (Data([0xC0, 0x20, 0xE0, 0x20, 0xF2, 0x20, 0xDA, 0x20, 0xDB, 0x20, 0xFC, 0x20, 0xFD, 0x20, 0xFE]), "ΐ ΰ ς Ϊ Ϋ ό ύ ώ")
        ]

        for (data, text) in fixtures {
            let decoded = try TextFileCodec.decode(data, assuming: .windows1253)
            let fresh = DecodedTextFile(
                text: decoded.text,
                encoding: .windows1253,
                hasByteOrderMark: false
            )

            XCTAssertEqual(decoded.text, text)
            XCTAssertEqual(decoded.encoding, .windows1253)
            XCTAssertFalse(decoded.hasByteOrderMark)
            XCTAssertEqual(try TextFileCodec.encode(decoded), data)
            XCTAssertEqual(try TextFileCodec.encode(fresh), data)
        }
    }

    func testEveryDefinedByteRoundTripsThroughFreshCP1253Text() throws {
        XCTAssertEqual(scalarOracle.count, 256)

        for (value, expectedScalar) in scalarOracle.enumerated() {
            guard let expectedScalar else { continue }
            let byte = UInt8(value)
            let data = Data([byte])
            let decoded = try TextFileCodec.decode(data, assuming: .windows1253)
            let fresh = DecodedTextFile(
                text: String(Unicode.Scalar(expectedScalar)!),
                encoding: .windows1253,
                hasByteOrderMark: false
            )

            XCTAssertEqual(
                decoded.text.unicodeScalars.map(\.value),
                [expectedScalar],
                "byte 0x\(String(byte, radix: 16))"
            )
            XCTAssertEqual(try TextFileCodec.encode(fresh), data, "byte 0x\(String(byte, radix: 16))")
        }
    }

    func testEveryUndefinedByteIsRejected() {
        for byte in undefinedBytes.sorted() {
            XCTAssertThrowsError(try TextFileCodec.decode(Data([byte]), assuming: .windows1253)) { error in
                XCTAssertEqual(
                    error as? TextFileCodecError,
                    .invalidTextEncoding,
                    "byte 0x\(String(byte, radix: 16))"
                )
            }
        }
    }

    func testUnrepresentableDocumentEditsFailWithoutChangingBytes() throws {
        let original = Data([0xC5, 0xEB, 0xEB, 0xE7, 0xED, 0xE9, 0xEA, 0xDC])
        let url = try temporaryFile(data: original)

        for text in ["Ελληνικά Ж", "Ελληνικά 🙂"] {
            var document = try TextFileDocumentIO.load(from: url, assuming: .windows1253)
            document.text = text

            XCTAssertTrue(document.isDirty)
            XCTAssertThrowsError(try TextFileDocumentIO.save(document)) { error in
                XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.windows1253))
            }
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testExplicitDocumentSavePreservesCP1253() throws {
        let original = Data([0xCA, 0xE1, 0xEB, 0xE7, 0xEC, 0xDD, 0xF1, 0xE1, 0x0D, 0x0A])
        let expected = Data([
            0xCA, 0xE1, 0xEB, 0xE7, 0xEC, 0xDD, 0xF1, 0xE1, 0x20,
            0xEA, 0xFC, 0xF3, 0xEC, 0xE5, 0x21, 0x0D, 0x0A
        ])
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url, assuming: .windows1253)
        XCTAssertEqual(document.text, "Καλημέρα\r\n")
        XCTAssertEqual(document.encoding, .windows1253)
        document.text = "Καλημέρα κόσμε!\r\n"

        let result = try TextFileDocumentIO.save(document)
        let reloaded = try TextFileDocumentIO.load(from: url, assuming: .windows1253)

        XCTAssertEqual(try Data(contentsOf: url), expected)
        XCTAssertEqual(result.document.encoding, .windows1253)
        XCTAssertEqual(result.document.persistedData, expected)
        XCTAssertEqual(result.document.persistedText, "Καλημέρα κόσμε!\r\n")
        XCTAssertFalse(result.document.hasByteOrderMark)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertNil(result.warning)
        XCTAssertEqual(reloaded.text, "Καλημέρα κόσμε!\r\n")
        XCTAssertEqual(reloaded.encoding, .windows1253)
    }

    func testUnchangedDocumentSavePreservesExactBytes() throws {
        let original = Data([
            0xA1, 0x20, 0xB4, 0x20, 0xAD, 0x20, 0xC0, 0x20, 0xE0, 0x20, 0xF2, 0x0D, 0x0A
        ])
        let url = try temporaryFile(data: original)
        let document = try TextFileDocumentIO.load(from: url, assuming: .windows1253)

        let result = try TextFileDocumentIO.save(document)

        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(result.document.persistedData, original)
        XCTAssertEqual(result.document.encoding, .windows1253)
        XCTAssertFalse(result.document.isDirty)
    }

    func testAutomaticAmbiguityFailsClosedUntilCP1253IsSelected() throws {
        let data = Data([0xC0])
        let url = try temporaryFile(data: data)

        XCTAssertThrowsError(try TextFileDocumentIO.load(from: url)) { error in
            XCTAssertEqual(
                error as? TextFileCodecError,
                .ambiguousTextEncoding([
                    .shiftJIS, .windows1250, .windows1251, .windows1252, .windows1253, .windows1254
                ])
            )
        }

        let selected = try TextFileDocumentIO.load(from: url, assuming: .windows1253)
        XCTAssertEqual(selected.text, "ΐ")
        XCTAssertEqual(selected.encoding, .windows1253)
        XCTAssertEqual(selected.persistedData, data)
    }

    private func temporaryFile(data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "fixture.txt")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }
}
