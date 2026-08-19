import Foundation
import MacMergeCore
import XCTest

final class Windows1253RecoveryTests: XCTestCase {
    private let undefinedBytes: Set<UInt8> = [
        0x81, 0x88, 0x8A, 0x8C, 0x8D, 0x8E, 0x8F, 0x90, 0x98,
        0x9A, 0x9C, 0x9D, 0x9E, 0x9F, 0xAA, 0xD2, 0xFF
    ]

    // Unicode Consortium mapping: Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP1253.TXT
    private let cp1253UpperHalfScalars: [UInt32?] = [
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

    func testExplicitCP1253DecodesGreekBytesAndReportsMetadata() throws {
        let data = Data([0xA2, 0xC1, 0xE1, 0xD9, 0xF9, 0xFE])

        let decoded = try TextFileCodec.decode(data, assuming: .windows1253)

        XCTAssertEqual(decoded.text, "ΆΑαΩωώ")
        XCTAssertEqual(decoded.encoding, .windows1253)
        XCTAssertEqual(decoded.encoding.rawValue, "windows1253")
        XCTAssertEqual(decoded.encoding.displayName, "Greek (CP1253)")
        XCTAssertFalse(decoded.hasByteOrderMark)
    }

    func testEveryDefinedCP1253ByteMatchesAuthoritativeMappingAndRoundTrips() throws {
        let tableUndefinedBytes = Set(cp1253UpperHalfScalars.enumerated().compactMap { offset, scalar in
            scalar == nil ? UInt8(offset + 0x80) : nil
        })
        XCTAssertEqual(cp1253UpperHalfScalars.count, 128)
        XCTAssertEqual(tableUndefinedBytes, undefinedBytes)

        for byte in UInt8.min...UInt8.max where !undefinedBytes.contains(byte) {
            let data = Data([byte])
            let decoded = try TextFileCodec.decode(data, assuming: .windows1253)
            let expectedScalar = byte < 0x80
                ? UInt32(byte)
                : try XCTUnwrap(cp1253UpperHalfScalars[Int(byte) - 0x80])
            let fresh = DecodedTextFile(
                text: decoded.text,
                encoding: .windows1253,
                hasByteOrderMark: false
            )

            XCTAssertEqual(decoded.text.unicodeScalars.map(\.value), [expectedScalar], "decoded byte \(byte)")
            XCTAssertEqual(try TextFileCodec.encode(decoded), data, "decoded byte \(byte)")
            XCTAssertEqual(try TextFileCodec.encode(fresh), data, "fresh byte \(byte)")
        }
    }

    func testCleanCP1253SavePreservesExactBytesAndMetadata() throws {
        let original = Data([0xA2, 0x20, 0xC1, 0xEB, 0xF6, 0xE1, 0x0D, 0x0A])
        let url = try temporaryFile(data: original)
        let document = try TextFileDocumentIO.load(from: url, assuming: .windows1253)

        let result = try TextFileDocumentIO.save(document)

        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(result.document.text, "Ά Αλφα\r\n")
        XCTAssertEqual(result.document.persistedText, "Ά Αλφα\r\n")
        XCTAssertEqual(result.document.persistedData, original)
        XCTAssertEqual(result.document.encoding, .windows1253)
        XCTAssertFalse(result.document.hasByteOrderMark)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertNil(result.warning)
    }

    func testRepresentableCP1253EditSavesAndReloadsInSameEncoding() throws {
        let original = Data([0xC1, 0xEB, 0xF6, 0xE1, 0x0D, 0x0A])
        let expected = Data([
            0xC1, 0xEB, 0xF6, 0xE1, 0x20, 0xD9, 0xEC, 0xDD, 0xE3, 0xE1, 0x21, 0x0D, 0x0A
        ])
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url, assuming: .windows1253)
        document.text = "Αλφα Ωμέγα!\r\n"

        let result = try TextFileDocumentIO.save(document)
        let reloaded = try TextFileDocumentIO.load(from: url, assuming: .windows1253)

        XCTAssertEqual(try Data(contentsOf: url), expected)
        XCTAssertEqual(result.document.text, "Αλφα Ωμέγα!\r\n")
        XCTAssertEqual(result.document.persistedData, expected)
        XCTAssertEqual(result.document.encoding, .windows1253)
        XCTAssertFalse(result.document.hasByteOrderMark)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertNil(result.warning)
        XCTAssertEqual(reloaded.text, "Αλφα Ωμέγα!\r\n")
        XCTAssertEqual(reloaded.persistedData, expected)
        XCTAssertEqual(reloaded.encoding, .windows1253)
        XCTAssertFalse(reloaded.hasByteOrderMark)
        XCTAssertFalse(reloaded.isDirty)
    }

    func testCP1253RejectsUndefinedBytesAndUnrepresentableScalar() throws {
        for byte in undefinedBytes {
            XCTAssertThrowsError(try TextFileCodec.decode(Data([byte]), assuming: .windows1253)) { error in
                XCTAssertEqual(error as? TextFileCodecError, .invalidTextEncoding, "byte \(byte)")
            }
        }

        XCTAssertThrowsError(
            try TextFileCodec.encode(
                DecodedTextFile(
                    text: "🙂",
                    encoding: .windows1253,
                    hasByteOrderMark: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.windows1253))
        }

        let original = Data([0xC1, 0xEB, 0xF6, 0xE1])
        let source = try temporaryFile(data: original)
        let destination = source.deletingLastPathComponent().appending(path: "unrepresentable-copy.txt")
        var document = try TextFileDocumentIO.load(from: source, assuming: .windows1253)
        document.text += "🙂"

        XCTAssertThrowsError(try TextFileDocumentIO.save(document)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.windows1253))
        }
        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(document, to: destination)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.windows1253))
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testAutomaticAmbiguityIncludesCP1253AndExplicitSelectionResolvesIt() throws {
        let data = Data([0x80])

        XCTAssertThrowsError(try TextFileCodec.decode(data)) { error in
            XCTAssertEqual(
                error as? TextFileCodecError,
                .ambiguousTextEncoding([
                    .windows1250, .windows1251, .windows1252, .windows1253, .windows1254
                ])
            )
        }

        let selected = try TextFileCodec.decode(data, assuming: .windows1253)
        XCTAssertEqual(selected.text, "€")
        XCTAssertEqual(selected.encoding, .windows1253)
        XCTAssertEqual(try TextFileCodec.encode(selected), data)
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
