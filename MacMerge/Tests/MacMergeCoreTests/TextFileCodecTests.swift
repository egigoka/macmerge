import Foundation
import MacMergeCore
import XCTest

final class TextFileCodecTests: XCTestCase {
    func testUTF8WithoutBOMRoundTrips() throws {
        let data = try XCTUnwrap("alpha\nβeta".data(using: .utf8))

        let document = try TextFileCodec.decode(data)

        XCTAssertEqual(document.text, "alpha\nβeta")
        XCTAssertEqual(document.encoding, .utf8)
        XCTAssertFalse(document.hasByteOrderMark)
        XCTAssertEqual(try TextFileCodec.encode(document), data)
    }

    func testUTF8BOMRoundTrips() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("content".utf8)

        let document = try TextFileCodec.decode(data)

        XCTAssertEqual(document.text, "content")
        XCTAssertEqual(document.encoding, .utf8)
        XCTAssertTrue(document.hasByteOrderMark)
        XCTAssertEqual(try TextFileCodec.encode(document), data)
    }

    func testUTF16LittleEndianBOMRoundTrips() throws {
        let payload = try XCTUnwrap("alpha\nβeta".data(using: .utf16LittleEndian))
        let data = Data([0xFF, 0xFE]) + payload

        let document = try TextFileCodec.decode(data)

        XCTAssertEqual(document.text, "alpha\nβeta")
        XCTAssertEqual(document.encoding, .utf16LittleEndian)
        XCTAssertTrue(document.hasByteOrderMark)
        XCTAssertEqual(try TextFileCodec.encode(document), data)
    }

    func testUTF16BigEndianBOMRoundTrips() throws {
        let payload = try XCTUnwrap("alpha\nβeta".data(using: .utf16BigEndian))
        let data = Data([0xFE, 0xFF]) + payload

        let document = try TextFileCodec.decode(data)

        XCTAssertEqual(document.text, "alpha\nβeta")
        XCTAssertEqual(document.encoding, .utf16BigEndian)
        XCTAssertTrue(document.hasByteOrderMark)
        XCTAssertEqual(try TextFileCodec.encode(document), data)
    }

    func testBOMlessUTF16FailsClosedBecauseByteOrderIsAmbiguous() throws {
        let data = try XCTUnwrap("plain text".data(using: .utf16LittleEndian))

        XCTAssertThrowsError(try TextFileCodec.decode(data)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .missingUTF16ByteOrderMark)
        }
    }

    func testBOMlessUTF16CJKDoesNotDecodeWithWrongByteOrder() throws {
        let data = try XCTUnwrap("一一".data(using: .utf16LittleEndian))

        XCTAssertThrowsError(try TextFileCodec.decode(data)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .missingUTF16ByteOrderMark)
        }
    }

    func testZeroFreeBOMlessUTF16DoesNotDecodeAsUTF8Controls() {
        let data = Data([0x01, 0x4E, 0x01, 0x4E])

        XCTAssertThrowsError(try TextFileCodec.decode(data)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .missingUTF16ByteOrderMark)
        }
    }

    func testUnknownLegacyBytesFailClosed() {
        XCTAssertThrowsError(try TextFileCodec.decode(Data([0x81, 0x8D, 0x8F]))) { error in
            XCTAssertEqual(error as? TextFileCodecError, .invalidTextEncoding)
        }
    }

    func testUTF32BOMsFailClosedBeforeUTF16Detection() {
        for data in [
            Data([0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00]),
            Data([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x41]),
        ] {
            XCTAssertThrowsError(try TextFileCodec.decode(data)) { error in
                XCTAssertEqual(error as? TextFileCodecError, .unsupportedUTF32)
            }
        }
    }

    func testWinMergeLegacyRepresentativeStreamsRoundTripExactly() throws {
        for (data, encoding) in [
            (Data([0x83, 0x65, 0x83, 0x58, 0x83, 0x67]), TextFileEncoding.shiftJIS),
            (Data([0xA5, 0xC6, 0xA5, 0xB9, 0xA5, 0xC8]), .japaneseEUC),
            (Data([0x1B, 0x24, 0x42, 0x25, 0x46, 0x25, 0x39, 0x25, 0x48, 0x1B, 0x28, 0x42]), .iso2022JP),
        ] {
            let document = try TextFileCodec.decode(data, assuming: encoding)

            XCTAssertEqual(document.encoding, encoding)
            XCTAssertFalse(document.hasByteOrderMark)
            XCTAssertEqual(document.text, "テスト")
            XCTAssertEqual(try TextFileCodec.encode(document), data)
            let fresh = DecodedTextFile(
                text: document.text,
                encoding: encoding,
                hasByteOrderMark: false
            )
            XCTAssertEqual(try TextFileCodec.encode(fresh), data)
        }
    }

    func testConflictingLosslessCandidatesFailClosed() {
        for data in [Data([0xA4, 0xA2]), Data([0xA4, 0xA2, 0xA4, 0xA4])] {
            XCTAssertThrowsError(try TextFileCodec.decode(data)) { error in
                guard case let .ambiguousTextEncoding(encodings) = error as? TextFileCodecError else {
                    return XCTFail("Expected ambiguous encoding, got \(error)")
                }
                XCTAssertTrue(encodings.contains(.shiftJIS))
                XCTAssertTrue(encodings.contains(.japaneseEUC))
            }
        }
        XCTAssertEqual(
            try? TextFileCodec.decode(Data([0xA4, 0xA2]), assuming: .japaneseEUC).text,
            "あ"
        )
    }

    func testValidUTF8WinsOverLegacyCandidatesLikeWinMerge() throws {
        let data = Data([0xC2, 0xA1])

        let decoded = try TextFileCodec.decode(data)

        XCTAssertEqual(decoded.encoding, .utf8)
        XCTAssertEqual(decoded.text, "¡")
    }

    func testValidUTF8WinsOverPlausibleZeroFreeUTF16LikeWinMerge() throws {
        let data = Data([0xC3, 0xA9, 0xC3, 0xA9])

        let decoded = try TextFileCodec.decode(data)

        XCTAssertEqual(decoded.encoding, .utf8)
        XCTAssertEqual(decoded.text, "éé")
    }

    func testNoncanonicalLegacyBytesRemainExactWhenUnchanged() throws {
        let data = Data([0xFA, 0x5C])

        let decoded = try TextFileCodec.decode(data, assuming: .shiftJIS)

        XCTAssertEqual(try TextFileCodec.encode(decoded), data)
    }

    func testCP51932UsesWindowsCompatibilityMappings() throws {
        let decoded = try TextFileCodec.decode(Data([0xA1, 0xC1]), assuming: .japaneseEUC)

        XCTAssertEqual(decoded.text, "～")
        XCTAssertEqual(try TextFileCodec.encode(decoded), Data([0xA1, 0xC1]))
        XCTAssertEqual(
            try TextFileCodec.encode(DecodedTextFile(
                text: "～",
                encoding: .japaneseEUC,
                hasByteOrderMark: false
            )),
            Data([0xA1, 0xC1])
        )
    }

    func testCP51932AndCP50220UseCP932VendorMappings() throws {
        let euc = Data([0xAD, 0xA1])
        let jis = Data([0x1B, 0x24, 0x42, 0x2D, 0x21, 0x1B, 0x28, 0x42])

        XCTAssertEqual(try TextFileCodec.decode(euc, assuming: .japaneseEUC).text, "①")
        XCTAssertEqual(try TextFileCodec.decode(jis, assuming: .iso2022JP).text, "①")
        XCTAssertEqual(
            try TextFileCodec.encode(DecodedTextFile(
                text: "①",
                encoding: .japaneseEUC,
                hasByteOrderMark: false
            )),
            euc
        )
        XCTAssertEqual(
            try TextFileCodec.encode(DecodedTextFile(
                text: "①",
                encoding: .iso2022JP,
                hasByteOrderMark: false
            )),
            jis
        )
    }

    func testCP50220SupportsASCIIOnlyDocuments() throws {
        let data = Data("plain text\n".utf8)

        let decoded = try TextFileCodec.decode(data, assuming: .iso2022JP)

        XCTAssertEqual(decoded.text, "plain text\n")
        XCTAssertEqual(try TextFileCodec.encode(DecodedTextFile(
            text: decoded.text,
            encoding: .iso2022JP,
            hasByteOrderMark: false
        )), data)
    }

    func testResetOnlyISO2022SequenceDoesNotOverrideUTF8Detection() throws {
        let data = Data([0x41, 0x1B, 0x28, 0x42, 0x42])

        let decoded = try TextFileCodec.decode(data)

        XCTAssertEqual(decoded.encoding, .utf8)
        XCTAssertEqual(decoded.text, "A\u{1B}(BB")
    }

    func testEvenLengthResetOnlyISO2022SequenceRemainsUTF8() throws {
        let data = Data([0x1B, 0x28, 0x42, 0x41])

        let decoded = try TextFileCodec.decode(data)

        XCTAssertEqual(decoded.encoding, .utf8)
        XCTAssertEqual(decoded.text, "\u{1B}(BA")
    }

    func testEmptyISO2022DesignationDoesNotHideUTF8EscapeBytes() throws {
        let data = Data([0x41, 0x1B, 0x24, 0x42, 0x1B, 0x28, 0x42, 0x42])

        let decoded = try TextFileCodec.decode(data)

        XCTAssertEqual(decoded.encoding, .utf8)
        XCTAssertEqual(decoded.text, "A\u{1B}$B\u{1B}(BB")
    }

    func testCP50220SupportsRomanStateAndRejectsJIS0212() throws {
        let roman = Data([0x1B, 0x28, 0x4A, 0x5C, 0x7E, 0x1B, 0x28, 0x42])
        XCTAssertEqual(try TextFileCodec.decode(roman, assuming: .iso2022JP).text, "\\~")

        XCTAssertThrowsError(try TextFileCodec.decode(roman)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .ambiguousTextEncoding([.utf8, .iso2022JP]))
        }

        let jis0212 = Data([0x1B, 0x24, 0x28, 0x44, 0x21, 0x21])
        XCTAssertThrowsError(try TextFileCodec.decode(jis0212, assuming: .iso2022JP))
    }

    func testCP50220PreservesExistingHalfwidthBytesAndConvertsFreshEdits() throws {
        let data = Data([0x1B, 0x28, 0x49, 0x31, 0x1B, 0x28, 0x42])

        let decoded = try TextFileCodec.decode(data, assuming: .iso2022JP)

        XCTAssertEqual(decoded.encoding, .iso2022JP)
        XCTAssertEqual(decoded.text, "ｱ")
        XCTAssertEqual(try TextFileCodec.encode(decoded), data)
        XCTAssertEqual(try TextFileCodec.encode(DecodedTextFile(
            text: decoded.text,
            encoding: .iso2022JP,
            hasByteOrderMark: false
        )), Data([0x1B, 0x24, 0x42, 0x25, 0x22, 0x1B, 0x28, 0x42]))
    }

    func testCP50220SOAndSIDecodeExistingHalfwidthKana() throws {
        let data = Data([0x0E, 0x31, 0x0F])

        let decoded = try TextFileCodec.decode(data, assuming: .iso2022JP)

        XCTAssertEqual(decoded.text, "ｱ")
        XCTAssertEqual(try TextFileCodec.encode(decoded), data)
    }

    func testCP50220ConsumesRedundantSIInASCIIState() throws {
        let data = Data([0x0F, 0x41])

        let decoded = try TextFileCodec.decode(data, assuming: .iso2022JP)

        XCTAssertEqual(decoded.text, "A")
        XCTAssertEqual(try TextFileCodec.encode(decoded), data)
        XCTAssertEqual(try TextFileCodec.encode(DecodedTextFile(
            text: decoded.text,
            encoding: .iso2022JP,
            hasByteOrderMark: false
        )), Data([0x41]))
    }

    func testMalformedRecognizedCP50220FailsClosedDuringAutomaticDetection() {
        let danglingPair = Data([0x1B, 0x24, 0x42, 0x24])

        XCTAssertThrowsError(try TextFileCodec.decode(danglingPair)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .invalidTextEncoding)
        }
    }

    func testISO2022ContentIsAmbiguousWithValidUTF8Bytes() {
        let data = Data([0x1B, 0x24, 0x42, 0x24, 0x22, 0x1B, 0x28, 0x42])

        XCTAssertThrowsError(try TextFileCodec.decode(data)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .ambiguousTextEncoding([.utf8, .iso2022JP]))
        }
    }

    func testCP50220RejectsLineBreakBeforeASCIIReset() {
        let data = Data([0x1B, 0x24, 0x42, 0x24, 0x22, 0x0A])

        XCTAssertThrowsError(try TextFileCodec.decode(data, assuming: .iso2022JP)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .invalidTextEncoding)
        }
    }

    func testCP51932RejectsUnsupportedC1Bytes() {
        for byte in [UInt8(0x80), 0x81, 0x8D, 0x90, 0x9F] {
            XCTAssertThrowsError(try TextFileCodec.decode(Data([byte]), assuming: .japaneseEUC))
        }
    }

    func testCP50220ConvertsHalfwidthKanaEditsToFullwidthJIS() throws {
        let document = DecodedTextFile(
            text: "AﾊﾟB",
            encoding: .iso2022JP,
            hasByteOrderMark: false
        )

        let data = try TextFileCodec.encode(document)

        XCTAssertEqual(data, Data([0x41, 0x1B, 0x24, 0x42, 0x25, 0x51, 0x1B, 0x28, 0x42, 0x42]))
        XCTAssertEqual(try TextFileCodec.decode(data, assuming: .iso2022JP).text, "AパB")
    }

    func testCP50220ConvertsUnpairedHalfwidthMarksDeterministically() throws {
        let cases: [(String, [UInt8])] = [
            ("ﾞ", [0x1B, 0x24, 0x42, 0x21, 0x2B, 0x1B, 0x28, 0x42]),
            ("ﾟ", [0x1B, 0x24, 0x42, 0x21, 0x2C, 0x1B, 0x28, 0x42]),
            ("ｱﾞ", [0x1B, 0x24, 0x42, 0x25, 0x22, 0x21, 0x2B, 0x1B, 0x28, 0x42]),
            ("ｶﾟ", [0x1B, 0x24, 0x42, 0x25, 0x2B, 0x21, 0x2C, 0x1B, 0x28, 0x42]),
        ]

        for (text, expectedBytes) in cases {
            let data = try TextFileCodec.encode(DecodedTextFile(
                text: text,
                encoding: .iso2022JP,
                hasByteOrderMark: false
            ))
            XCTAssertEqual(data, Data(expectedBytes), text)
        }
    }

    func testEncodingRejectsScalarChangingCanonicalization() {
        let document = DecodedTextFile(
            text: "〜",
            encoding: .shiftJIS,
            hasByteOrderMark: false
        )

        XCTAssertThrowsError(try TextFileCodec.encode(document)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.shiftJIS))
        }
    }

    func testLegacyEncodingRejectsUnrepresentableEdits() throws {
        let data = try XCTUnwrap("テスト".data(using: .shiftJIS))
        let decoded = try TextFileCodec.decode(data)
        let edited = DecodedTextFile(
            text: decoded.text + "🙂",
            encoding: decoded.encoding,
            hasByteOrderMark: false
        )

        XCTAssertThrowsError(try TextFileCodec.encode(edited)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.shiftJIS))
        }
    }

}
