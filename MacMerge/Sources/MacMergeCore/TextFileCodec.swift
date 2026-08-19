import Foundation

public enum TextFileEncoding: String, Equatable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
    case shiftJIS
    case japaneseEUC
    case iso2022JP
    case windows1250
    case windows1251
    case windows1252
    case windows1253
    case windows1254

    public var displayName: String {
        switch self {
        case .utf8:
            "UTF-8"
        case .utf16LittleEndian:
            "UTF-16 LE"
        case .utf16BigEndian:
            "UTF-16 BE"
        case .shiftJIS:
            "Shift-JIS (CP932)"
        case .japaneseEUC:
            "EUC-JP (CP51932)"
        case .iso2022JP:
            "ISO-2022-JP (CP50220)"
        case .windows1250:
            "Central European (CP1250)"
        case .windows1251:
            "Cyrillic (CP1251)"
        case .windows1252:
            "Western European (CP1252)"
        case .windows1253:
            "Greek (CP1253)"
        case .windows1254:
            "Turkish (CP1254)"
        }
    }
}

public struct DecodedTextFile: Equatable, Sendable {
    public let text: String
    public let encoding: TextFileEncoding
    public let hasByteOrderMark: Bool
    fileprivate let originalData: Data?

    public init(text: String, encoding: TextFileEncoding, hasByteOrderMark: Bool) {
        self.text = text
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
        originalData = nil
    }

    fileprivate init(
        text: String,
        encoding: TextFileEncoding,
        hasByteOrderMark: Bool,
        originalData: Data
    ) {
        self.text = text
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
        self.originalData = originalData
    }
}

public enum TextFileCodecError: Error, LocalizedError, Equatable, Sendable {
    case invalidTextEncoding
    case missingUTF16ByteOrderMark
    case unsupportedUTF32
    case ambiguousTextEncoding([TextFileEncoding])
    case encodingFailed(TextFileEncoding)

    public var errorDescription: String? {
        switch self {
        case .invalidTextEncoding:
            "File encoding is unsupported or ambiguous. Supported legacy encodings are CP932, CP51932, CP50220, CP1250, CP1251, CP1252, CP1253, and CP1254."
        case .missingUTF16ByteOrderMark:
            "UTF-16 byte order is ambiguous because the file has no byte-order mark."
        case .unsupportedUTF32:
            "UTF-32 text is not supported yet. Convert the file to UTF-8 or UTF-16 first."
        case let .ambiguousTextEncoding(encodings):
            "File matches multiple encodings: \(encodings.map(\.displayName).joined(separator: ", ")). Choose one explicitly."
        case let .encodingFailed(encoding):
            "Text could not be encoded as \(encoding.displayName)."
        }
    }
}

public enum TextFileCodec {
    private enum ISO2022JPInspection {
        case none
        case designationOnly
        case content
        case invalid
    }

    private static let utf8BOM = Data([0xEF, 0xBB, 0xBF])
    private static let utf16LittleEndianBOM = Data([0xFF, 0xFE])
    private static let utf16BigEndianBOM = Data([0xFE, 0xFF])
    private static let utf32LittleEndianBOM = Data([0xFF, 0xFE, 0x00, 0x00])
    private static let utf32BigEndianBOM = Data([0x00, 0x00, 0xFE, 0xFF])

    public static func decode(_ data: Data) throws -> DecodedTextFile {
        if data.starts(with: utf32LittleEndianBOM) || data.starts(with: utf32BigEndianBOM) {
            throw TextFileCodecError.unsupportedUTF32
        }
        if data.starts(with: utf8BOM) {
            return try decode(
                data.dropFirst(utf8BOM.count),
                encoding: .utf8,
                hasByteOrderMark: true
            )
        }
        if data.starts(with: utf16LittleEndianBOM) {
            return try decode(
                data.dropFirst(utf16LittleEndianBOM.count),
                encoding: .utf16LittleEndian,
                hasByteOrderMark: true
            )
        }
        if data.starts(with: utf16BigEndianBOM) {
            return try decode(
                data.dropFirst(utf16BigEndianBOM.count),
                encoding: .utf16BigEndian,
                hasByteOrderMark: true
            )
        }
        let utf8Text = String(data: data, encoding: .utf8)
        let iso2022Inspection = inspectISO2022JP(data)
        if iso2022Inspection == .invalid {
            throw TextFileCodecError.invalidTextEncoding
        }
        if iso2022Inspection == .content {
            guard let document = decodeLegacy(data, encoding: .iso2022JP) else {
                throw TextFileCodecError.invalidTextEncoding
            }
            guard utf8Text == nil else {
                throw TextFileCodecError.ambiguousTextEncoding([.utf8, .iso2022JP])
            }
            return document
        }
        if hasUTF16NullByteSignature(data) ||
            (hasPlausibleZeroFreeUTF16(data, utf8Text: utf8Text) &&
                utf8Text.map(containsSuspiciousControlsExceptEscape) != false) {
            throw TextFileCodecError.missingUTF16ByteOrderMark
        }

        let utf8Candidate: DecodedTextFile?
        if let text = utf8Text {
            utf8Candidate = DecodedTextFile(
                text: text,
                encoding: .utf8,
                hasByteOrderMark: false,
                originalData: data
            )
        } else {
            utf8Candidate = nil
        }
        var legacyCandidates: [DecodedTextFile] = []
        for encoding in [TextFileEncoding.shiftJIS, .japaneseEUC] {
            if let document = decodeLegacy(data, encoding: encoding) {
                legacyCandidates.append(document)
            }
        }
        for encoding in [
            TextFileEncoding.windows1250, .windows1251, .windows1252, .windows1253, .windows1254
        ] {
            if let document = decodeLegacy(data, encoding: encoding) {
                legacyCandidates.append(document)
            }
        }

        if let utf8Candidate {
            return utf8Candidate
        }

        guard let first = legacyCandidates.first else {
            throw TextFileCodecError.invalidTextEncoding
        }
        if legacyCandidates.count == 1 { return first }
        let distinctTexts = legacyCandidates.reduce(into: [String]()) { texts, candidate in
            if !texts.contains(where: { scalarsEqual($0, candidate.text) }) {
                texts.append(candidate.text)
            }
        }
        let hasWindowsCodepage = legacyCandidates.contains {
            windowsStringEncoding(for: $0.encoding) != nil
        }
        if distinctTexts.count == 1, !hasWindowsCodepage {
            return first
        }
        throw TextFileCodecError.ambiguousTextEncoding(legacyCandidates.map(\.encoding))
    }

    public static func decode(
        _ data: Data,
        assuming encoding: TextFileEncoding
    ) throws -> DecodedTextFile {
        switch encoding {
        case .utf8:
            let hasBOM = data.starts(with: utf8BOM)
            return try decode(
                hasBOM ? data.dropFirst(utf8BOM.count) : data[...],
                encoding: encoding,
                hasByteOrderMark: hasBOM,
                originalData: data
            )
        case .utf16LittleEndian:
            let hasBOM = data.starts(with: utf16LittleEndianBOM)
            return try decode(
                hasBOM ? data.dropFirst(utf16LittleEndianBOM.count) : data[...],
                encoding: encoding,
                hasByteOrderMark: hasBOM,
                originalData: data
            )
        case .utf16BigEndian:
            let hasBOM = data.starts(with: utf16BigEndianBOM)
            return try decode(
                hasBOM ? data.dropFirst(utf16BigEndianBOM.count) : data[...],
                encoding: encoding,
                hasByteOrderMark: hasBOM,
                originalData: data
            )
        case .shiftJIS, .japaneseEUC, .iso2022JP, .windows1250, .windows1251, .windows1252,
             .windows1253, .windows1254:
            guard let document = decodeLegacy(data, encoding: encoding) else {
                throw TextFileCodecError.invalidTextEncoding
            }
            return document
        }
    }

    public static func encode(_ document: DecodedTextFile) throws -> Data {
        if let originalData = document.originalData {
            return originalData
        }
        let stringEncoding: String.Encoding
        let byteOrderMark: Data

        switch document.encoding {
        case .utf8:
            stringEncoding = .utf8
            byteOrderMark = utf8BOM
        case .utf16LittleEndian:
            stringEncoding = .utf16LittleEndian
            byteOrderMark = utf16LittleEndianBOM
        case .utf16BigEndian:
            stringEncoding = .utf16BigEndian
            byteOrderMark = utf16BigEndianBOM
        case .shiftJIS:
            stringEncoding = .shiftJIS
            byteOrderMark = Data()
        case .japaneseEUC:
            stringEncoding = .japaneseEUC
            byteOrderMark = Data()
        case .iso2022JP:
            stringEncoding = .iso2022JP
            byteOrderMark = Data()
        case .windows1250:
            stringEncoding = .windowsCP1250
            byteOrderMark = Data()
        case .windows1251:
            stringEncoding = .windowsCP1251
            byteOrderMark = Data()
        case .windows1252:
            stringEncoding = .windowsCP1252
            byteOrderMark = Data()
        case .windows1253:
            stringEncoding = .windowsCP1253
            byteOrderMark = Data()
        case .windows1254:
            stringEncoding = .windowsCP1254
            byteOrderMark = Data()
        }

        let payload: Data
        switch document.encoding {
        case .shiftJIS, .japaneseEUC, .iso2022JP, .windows1250, .windows1251, .windows1252,
             .windows1253, .windows1254:
            guard let encoded = encodeLegacy(document.text, encoding: document.encoding) else {
                throw TextFileCodecError.encodingFailed(document.encoding)
            }
            payload = encoded
        case .utf8, .utf16LittleEndian, .utf16BigEndian:
            guard let encoded = document.text.data(using: stringEncoding, allowLossyConversion: false) else {
                throw TextFileCodecError.encodingFailed(document.encoding)
            }
            payload = encoded
        }
        guard document.hasByteOrderMark else { return payload }

        var data = byteOrderMark
        data.append(payload)
        return data
    }

    private static func decode(
        _ data: Data.SubSequence,
        encoding: TextFileEncoding,
        hasByteOrderMark: Bool,
        originalData: Data? = nil
    ) throws -> DecodedTextFile {
        let stringEncoding: String.Encoding
        switch encoding {
        case .utf8:
            stringEncoding = .utf8
        case .utf16LittleEndian:
            stringEncoding = .utf16LittleEndian
        case .utf16BigEndian:
            stringEncoding = .utf16BigEndian
        case .shiftJIS:
            stringEncoding = .shiftJIS
        case .japaneseEUC:
            stringEncoding = .japaneseEUC
        case .iso2022JP:
            stringEncoding = .iso2022JP
        case .windows1250:
            stringEncoding = .windowsCP1250
        case .windows1251:
            stringEncoding = .windowsCP1251
        case .windows1252:
            stringEncoding = .windowsCP1252
        case .windows1253:
            stringEncoding = .windowsCP1253
        case .windows1254:
            stringEncoding = .windowsCP1254
        }

        guard let text = String(data: Data(data), encoding: stringEncoding) else {
            throw TextFileCodecError.invalidTextEncoding
        }
        if let originalData {
            return DecodedTextFile(
                text: text,
                encoding: encoding,
                hasByteOrderMark: hasByteOrderMark,
                originalData: originalData
            )
        }
        return DecodedTextFile(text: text, encoding: encoding, hasByteOrderMark: hasByteOrderMark)
    }

    private static func hasUTF16NullByteSignature(_ data: Data) -> Bool {
        guard data.count >= 4, data.count.isMultiple(of: 2) else { return false }

        let sample = Array(data.prefix(512))
        let pairCount = sample.count / 2
        var zeroEvenBytes = 0
        var zeroOddBytes = 0
        for index in 0..<(pairCount * 2) where sample[index] == 0 {
            if index.isMultiple(of: 2) {
                zeroEvenBytes += 1
            } else {
                zeroOddBytes += 1
            }
        }

        return (zeroOddBytes * 2 >= pairCount && zeroEvenBytes * 4 <= pairCount) ||
            (zeroEvenBytes * 2 >= pairCount && zeroOddBytes * 4 <= pairCount)
    }

    private static func hasPlausibleZeroFreeUTF16(_ data: Data, utf8Text: String?) -> Bool {
        guard data.count >= 4,
              data.count.isMultiple(of: 2),
              let utf8 = utf8Text,
              (containsSuspiciousControls(utf8) ||
                  utf8.unicodeScalars.contains(where: { $0.value > 0x7F })) else {
            return false
        }

        let encodings: [String.Encoding] = [.utf16LittleEndian, .utf16BigEndian]
        return encodings.contains { encoding in
            guard let text = String(data: data, encoding: encoding), !text.isEmpty else {
                return false
            }
            let scalars = text.unicodeScalars
            let printable = scalars.filter { scalar in
                !CharacterSet.controlCharacters.contains(scalar) ||
                    scalar == "\t" || scalar == "\n" || scalar == "\r"
            }.count
            return printable * 4 >= scalars.count * 3
        }
    }

    private static func containsSuspiciousControls(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar) &&
                scalar != "\t" && scalar != "\n" && scalar != "\r"
        }
    }

    private static func containsSuspiciousControlsExceptEscape(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar) &&
                scalar.value != 0x1B && scalar != "\t" && scalar != "\n" && scalar != "\r"
        }
    }

    private static func inspectISO2022JP(_ data: Data) -> ISO2022JPInspection {
        let bytes = Array(data)
        enum State { case ascii, roman, jis, halfwidthKana }
        var state = State.ascii
        var recognized = false
        var hasContent = false
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0E, state == .ascii || state == .roman {
                recognized = true
                state = .halfwidthKana
                index += 1
            } else if bytes[index] == 0x0F {
                recognized = true
                state = .ascii
                index += 1
            } else if bytes[index] == 0x1B {
                guard index + 2 < bytes.count else {
                    return recognized || index + 1 == bytes.count ||
                        bytes[index + 1] == 0x24 || bytes[index + 1] == 0x28 ? .invalid : .none
                }
                switch (bytes[index + 1], bytes[index + 2]) {
                case (0x24, 0x40), (0x24, 0x42):
                    recognized = true
                    state = .jis
                case (0x28, 0x42):
                    recognized = true
                    state = .ascii
                case (0x28, 0x4A):
                    recognized = true
                    state = .roman
                case (0x28, 0x49):
                    recognized = true
                    state = .halfwidthKana
                default:
                    return recognized || bytes[index + 1] == 0x24 || bytes[index + 1] == 0x28
                        ? .invalid
                        : .none
                }
                index += 3
            } else if state == .jis {
                guard index + 1 < bytes.count,
                      (0x21...0x7E).contains(bytes[index]),
                      (0x21...0x7E).contains(bytes[index + 1]) else {
                    return .invalid
                }
                hasContent = true
                index += 2
            } else if state == .halfwidthKana {
                guard (0x21...0x5F).contains(bytes[index]) else { return .invalid }
                hasContent = true
                index += 1
            } else if state == .roman {
                guard bytes[index] <= 0x7F else { return .invalid }
                if bytes[index] >= 0x20 {
                    hasContent = true
                }
                index += 1
            } else {
                guard bytes[index] <= 0x7F else { return recognized ? .invalid : .none }
                index += 1
            }
        }
        if hasContent { return .content }
        return recognized ? .designationOnly : .none
    }

    private static func decodeLegacy(
        _ data: Data,
        encoding: TextFileEncoding
    ) -> DecodedTextFile? {
        let text: String?
        switch encoding {
        case .shiftJIS:
            text = String(data: data, encoding: .shiftJIS)
        case .japaneseEUC:
            text = eucJPToShiftJIS(data).flatMap { String(data: $0, encoding: .shiftJIS) }
        case .iso2022JP:
            text = iso2022JPToShiftJIS(data).flatMap { String(data: $0, encoding: .shiftJIS) }
        case .windows1250:
            text = String(data: data, encoding: .windowsCP1250)
        case .windows1251:
            text = String(data: data, encoding: .windowsCP1251)
        case .windows1252:
            text = String(data: data, encoding: .windowsCP1252)
        case .windows1253:
            text = String(data: data, encoding: .windowsCP1253)
        case .windows1254:
            text = String(data: data, encoding: .windowsCP1254)
        case .utf8, .utf16LittleEndian, .utf16BigEndian:
            return nil
        }

        guard isValidLegacyByteStream(data, encoding: encoding),
              let text else {
            return nil
        }
        return DecodedTextFile(
            text: text,
            encoding: encoding,
            hasByteOrderMark: false,
            originalData: data
        )
    }

    private static func encodeLegacy(_ text: String, encoding: TextFileEncoding) -> Data? {
        if let windowsEncoding = windowsStringEncoding(for: encoding) {
            guard let data = text.data(using: windowsEncoding, allowLossyConversion: false),
                  let roundTrip = String(data: data, encoding: windowsEncoding),
                  scalarsEqual(roundTrip, text) else {
                return nil
            }
            return data
        }
        let encodedText = encoding == .iso2022JP ? fullwidthKatakana(in: text) : text
        guard let shiftJIS = encodedText.data(using: .shiftJIS, allowLossyConversion: false),
              isValidShiftJIS(shiftJIS),
              let roundTrip = String(data: shiftJIS, encoding: .shiftJIS),
              scalarsEqual(roundTrip, encodedText) else {
            return nil
        }

        let data: Data?
        switch encoding {
        case .shiftJIS:
            data = shiftJIS
        case .japaneseEUC:
            data = shiftJISToEUCJP(shiftJIS)
        case .iso2022JP:
            data = shiftJISToISO2022JP(shiftJIS)
        case .utf8, .utf16LittleEndian, .utf16BigEndian, .windows1250, .windows1251, .windows1252,
             .windows1253, .windows1254:
            return nil
        }

        guard let data,
              isValidLegacyByteStream(data, encoding: encoding),
              let decoded = decodeLegacy(data, encoding: encoding),
              scalarsEqual(decoded.text, encodedText) else {
            return nil
        }
        return data
    }

    private static func windowsStringEncoding(for encoding: TextFileEncoding) -> String.Encoding? {
        switch encoding {
        case .windows1250: .windowsCP1250
        case .windows1251: .windowsCP1251
        case .windows1252: .windowsCP1252
        case .windows1253: .windowsCP1253
        case .windows1254: .windowsCP1254
        default: nil
        }
    }

    private static func fullwidthKatakana(in text: String) -> String {
        var result = ""
        var halfwidthRun = ""

        func appendRun() {
            guard !halfwidthRun.isEmpty else { return }
            let normalized = halfwidthRun
                .precomposedStringWithCompatibilityMapping
                .precomposedStringWithCanonicalMapping
            for scalar in normalized.unicodeScalars {
                switch scalar.value {
                case 0x3099:
                    result.unicodeScalars.append(UnicodeScalar(0x309B)!)
                case 0x309A:
                    result.unicodeScalars.append(UnicodeScalar(0x309C)!)
                default:
                    result.unicodeScalars.append(scalar)
                }
            }
            halfwidthRun.removeAll(keepingCapacity: true)
        }

        for character in text {
            if character.unicodeScalars.allSatisfy({ (0xFF61...0xFF9F).contains($0.value) }) {
                halfwidthRun.append(character)
            } else {
                appendRun()
                result.append(character)
            }
        }
        appendRun()
        return result
    }

    private static func isValidLegacyByteStream(
        _ data: Data,
        encoding: TextFileEncoding
    ) -> Bool {
        switch encoding {
        case .shiftJIS:
            return isValidShiftJIS(data)
        case .japaneseEUC:
            return isValidEUCJP(data)
        case .iso2022JP:
            return iso2022JPToShiftJIS(data) != nil
        case .windows1250, .windows1251, .windows1252, .windows1253, .windows1254:
            return true
        case .utf8, .utf16LittleEndian, .utf16BigEndian:
            return false
        }
    }

    private static func isValidShiftJIS(_ data: Data) -> Bool {
        let bytes = Array(data)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte <= 0x7F || (0xA1...0xDF).contains(byte) {
                index += 1
            } else if (0x81...0x9F).contains(byte) || (0xE0...0xFC).contains(byte) {
                guard index + 1 < bytes.count else { return false }
                let trail = bytes[index + 1]
                guard (0x40...0x7E).contains(trail) || (0x80...0xFC).contains(trail) else {
                    return false
                }
                index += 2
            } else {
                return false
            }
        }
        return true
    }

    private static func isValidEUCJP(_ data: Data) -> Bool {
        let bytes = Array(data)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte <= 0x7F {
                index += 1
            } else if byte == 0x8E {
                guard index + 1 < bytes.count, (0xA1...0xDF).contains(bytes[index + 1]) else {
                    return false
                }
                index += 2
            } else if byte == 0x8F {
                guard index + 2 < bytes.count,
                      (0xA1...0xFE).contains(bytes[index + 1]),
                      (0xA1...0xFE).contains(bytes[index + 2]) else {
                    return false
                }
                index += 3
            } else if (0xA1...0xFE).contains(byte) {
                guard index + 1 < bytes.count, (0xA1...0xFE).contains(bytes[index + 1]) else {
                    return false
                }
                index += 2
            } else {
                return false
            }
        }
        return true
    }

    private static func eucJPToShiftJIS(_ data: Data) -> Data? {
        let bytes = Array(data)
        var result = Data()
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte <= 0x7F {
                result.append(byte)
                index += 1
            } else if byte == 0x8E {
                guard index + 1 < bytes.count, (0xA1...0xDF).contains(bytes[index + 1]) else {
                    return nil
                }
                result.append(bytes[index + 1])
                index += 2
            } else if (0xA1...0xFE).contains(byte) {
                guard index + 1 < bytes.count, (0xA1...0xFE).contains(bytes[index + 1]),
                      let pair = jisToShiftJIS(row: byte - 0x80, cell: bytes[index + 1] - 0x80) else {
                    return nil
                }
                result.append(pair.0)
                result.append(pair.1)
                index += 2
            } else {
                return nil
            }
        }
        return result
    }

    private static func shiftJISToEUCJP(_ data: Data) -> Data? {
        let bytes = Array(data)
        var result = Data()
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte <= 0x7F {
                result.append(byte)
                index += 1
            } else if (0xA1...0xDF).contains(byte) {
                result.append(0x8E)
                result.append(byte)
                index += 1
            } else {
                guard index + 1 < bytes.count,
                      let pair = shiftJISToJIS(lead: byte, trail: bytes[index + 1]) else {
                    return nil
                }
                result.append(pair.0 + 0x80)
                result.append(pair.1 + 0x80)
                index += 2
            }
        }
        return result
    }

    private static func iso2022JPToShiftJIS(_ data: Data) -> Data? {
        enum State { case ascii, jis, halfwidthKana }
        let bytes = Array(data)
        var result = Data()
        var state = State.ascii
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0E, state == .ascii {
                state = .halfwidthKana
                index += 1
            } else if bytes[index] == 0x0F {
                state = .ascii
                index += 1
            } else if bytes[index] == 0x1B {
                guard index + 2 < bytes.count else { return nil }
                let pair = (bytes[index + 1], bytes[index + 2])
                switch pair {
                case (0x24, 0x40), (0x24, 0x42):
                    state = .jis
                case (0x28, 0x42), (0x28, 0x4A):
                    state = .ascii
                case (0x28, 0x49):
                    state = .halfwidthKana
                default:
                    return nil
                }
                index += 3
            } else if bytes[index] < 0x21 || bytes[index] == 0x7F {
                guard state == .ascii else { return nil }
                result.append(bytes[index])
                index += 1
            } else if state == .ascii {
                guard bytes[index] <= 0x7E else { return nil }
                result.append(bytes[index])
                index += 1
            } else if state == .halfwidthKana {
                guard (0x21...0x5F).contains(bytes[index]) else { return nil }
                result.append(bytes[index] + 0x80)
                index += 1
            } else {
                guard index + 1 < bytes.count,
                      let pair = jisToShiftJIS(row: bytes[index], cell: bytes[index + 1]) else {
                    return nil
                }
                result.append(pair.0)
                result.append(pair.1)
                index += 2
            }
        }
        return result
    }

    private static func shiftJISToISO2022JP(_ data: Data) -> Data? {
        let bytes = Array(data)
        var result = Data()
        var inJIS = false
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte <= 0x7F {
                if inJIS {
                    result.append(contentsOf: [0x1B, 0x28, 0x42])
                    inJIS = false
                }
                result.append(byte)
                index += 1
            } else if (0xA1...0xDF).contains(byte) {
                return nil
            } else {
                guard index + 1 < bytes.count,
                      let pair = shiftJISToJIS(lead: byte, trail: bytes[index + 1]) else {
                    return nil
                }
                if !inJIS {
                    result.append(contentsOf: [0x1B, 0x24, 0x42])
                    inJIS = true
                }
                result.append(pair.0)
                result.append(pair.1)
                index += 2
            }
        }
        if inJIS {
            result.append(contentsOf: [0x1B, 0x28, 0x42])
        }
        return result
    }

    private static func jisToShiftJIS(row: UInt8, cell: UInt8) -> (UInt8, UInt8)? {
        guard (0x21...0x7E).contains(row), (0x21...0x7E).contains(cell) else { return nil }
        var lead = ((Int(row) - 0x21) >> 1) + 0x81
        if lead > 0x9F { lead += 0x40 }
        var trail: Int
        if (row - 0x21).isMultiple(of: 2) {
            trail = Int(cell) + 0x1F
            if trail >= 0x7F { trail += 1 }
        } else {
            trail = Int(cell) + 0x7E
        }
        guard lead <= 0xFC, trail <= 0xFC else { return nil }
        return (UInt8(lead), UInt8(trail))
    }

    private static func shiftJISToJIS(lead: UInt8, trail: UInt8) -> (UInt8, UInt8)? {
        guard ((0x81...0x9F).contains(lead) || (0xE0...0xFC).contains(lead)),
              (0x40...0x7E).contains(trail) || (0x80...0xFC).contains(trail) else {
            return nil
        }
        let adjustedLead = Int(lead) - (lead <= 0x9F ? 0x81 : 0xC1)
        var row = adjustedLead * 2 + 0x21
        let cell: Int
        if trail >= 0x9F {
            row += 1
            cell = Int(trail) - 0x7E
        } else {
            cell = Int(trail) - (trail > 0x7E ? 0x20 : 0x1F)
        }
        guard (0x21...0x7E).contains(row), (0x21...0x7E).contains(cell) else { return nil }
        return (UInt8(row), UInt8(cell))
    }

    private static func scalarsEqual(_ left: String, _ right: String) -> Bool {
        left.unicodeScalars.elementsEqual(right.unicodeScalars)
    }
}
