import CXDiff
import Foundation

public struct PatchGeneratorOptions: Equatable, Sendable {
    public var oldPath: String
    public var newPath: String
    public var contextLines: Int
    public var reverse: Bool
    public var maximumOutputBytes: Int

    public init(
        oldPath: String = "a/file",
        newPath: String = "b/file",
        contextLines: Int = 3,
        reverse: Bool = false,
        maximumOutputBytes: Int = 64 * 1024 * 1024
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.contextLines = contextLines
        self.reverse = reverse
        self.maximumOutputBytes = maximumOutputBytes
    }
}

public enum PatchGeneratorError: Error, LocalizedError, Equatable, Sendable {
    case invalidContextLines(Int)
    case invalidMaximumOutputBytes(Int)
    case invalidPath(String)
    case outputTooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidContextLines(let value):
            "Patch context line count must not be negative: \(value)."
        case .invalidMaximumOutputBytes(let value):
            "Patch output byte limit must not be negative: \(value)."
        case .invalidPath(let path):
            "Patch path is empty or contains NUL: \(path)."
        case .outputTooLarge(let maximumBytes):
            "Generated patch exceeds the \(maximumBytes)-byte output limit."
        }
    }
}

public enum PatchGenerator: Sendable {
    public static func generate(
        old oldText: String,
        new newText: String,
        options: PatchGeneratorOptions = PatchGeneratorOptions()
    ) throws -> String {
        guard options.contextLines >= 0 else {
            throw PatchGeneratorError.invalidContextLines(options.contextLines)
        }
        guard options.maximumOutputBytes >= 0 else {
            throw PatchGeneratorError.invalidMaximumOutputBytes(options.maximumOutputBytes)
        }
        try validate(path: options.oldPath)
        try validate(path: options.newPath)

        let oldInput = options.reverse ? newText : oldText
        let newInput = options.reverse ? oldText : newText
        let maximumInputBytes = Int(MMX_MAX_INPUT_SIZE)
        guard oldInput.utf8.count <= maximumInputBytes,
            newInput.utf8.count <= maximumInputBytes
        else {
            throw LineDiffError.inputTooLarge(maximumBytes: maximumInputBytes)
        }
        let maximumLines = Int(MMX_MAX_LINE_COUNT)
        try validateRecordCount(oldInput, maximumLines: maximumLines)
        try validateRecordCount(newInput, maximumLines: maximumLines)
        let oldPath = options.reverse ? options.newPath : options.oldPath
        let newPath = options.reverse ? options.oldPath : options.newPath
        let oldDocument = PatchDocument(oldInput)
        let newDocument = PatchDocument(newInput)
        let comparisonTexts = PatchDocument.comparisonTexts(
            old: oldDocument,
            new: newDocument
        )
        let rows = try LineDiff.compare(
            left: comparisonTexts.old,
            right: comparisonTexts.new,
            options: LineDiffOptions(
                ignoreLineEndings: false,
                lineFiltersEnabled: false,
                substitutionsEnabled: false
            )
        )
        let hunks = hunkRanges(rows: rows, contextLines: options.contextLines)
        guard !hunks.isEmpty else { return "" }

        var output = BoundedOutput(maximumBytes: options.maximumOutputBytes)
        try output.append("--- ")
        try output.append(headerPath(oldPath))
        try output.appendLF()
        try output.append("+++ ")
        try output.append(headerPath(newPath))
        try output.appendLF()

        var rowIndex = 0
        var oldLinesConsumed = 0
        var newLinesConsumed = 0
        for hunk in hunks {
            while rowIndex < hunk.lowerBound {
                let id = rows[rowIndex].id
                if id.leftNumber != nil { oldLinesConsumed += 1 }
                if id.rightNumber != nil { newLinesConsumed += 1 }
                rowIndex += 1
            }

            var oldCount = 0
            var newCount = 0
            for row in rows[hunk] {
                let id = row.id
                if id.leftNumber != nil { oldCount += 1 }
                if id.rightNumber != nil { newCount += 1 }
            }
            let oldStart = oldCount == 0 ? oldLinesConsumed : oldLinesConsumed + 1
            let newStart = newCount == 0 ? newLinesConsumed : newLinesConsumed + 1
            try output.append("@@ -")
            try output.append(range(start: oldStart, count: oldCount))
            try output.append(" +")
            try output.append(range(start: newStart, count: newCount))
            try output.append(" @@")
            try output.appendLF()

            var bodyIndex = hunk.lowerBound
            while bodyIndex < hunk.upperBound {
                if rows[bodyIndex].kind == .unchanged {
                    let row = rows[bodyIndex]
                    try append(
                        record: row.id.leftNumber.flatMap(oldDocument.record)
                            ?? row.id.rightNumber.flatMap(newDocument.record),
                        prefix: 0x20,
                        to: &output
                    )
                    bodyIndex += 1
                    continue
                }

                var changeEnd = bodyIndex + 1
                while changeEnd < hunk.upperBound, rows[changeEnd].kind != .unchanged {
                    changeEnd += 1
                }
                for row in rows[bodyIndex..<changeEnd] {
                    try append(
                        record: row.id.leftNumber.flatMap(oldDocument.record),
                        prefix: 0x2D,
                        to: &output
                    )
                }
                for row in rows[bodyIndex..<changeEnd] {
                    try append(
                        record: row.id.rightNumber.flatMap(newDocument.record),
                        prefix: 0x2B,
                        to: &output
                    )
                }
                bodyIndex = changeEnd
            }

            for row in rows[hunk] {
                let id = row.id
                if id.leftNumber != nil { oldLinesConsumed += 1 }
                if id.rightNumber != nil { newLinesConsumed += 1 }
            }
            rowIndex = hunk.upperBound
        }
        return output.string
    }

    static func validateRecordCount(_ text: String, maximumLines: Int) throws {
        var lineCount = 0
        var lastByte: UInt8?
        for byte in text.utf8 {
            lastByte = byte
            if byte == 0x0A {
                lineCount += 1
                guard lineCount <= maximumLines else {
                    throw LineDiffError.tooManyLines(maximumLines: maximumLines)
                }
            }
        }
        if lastByte != nil, lastByte != 0x0A, lineCount == maximumLines {
            throw LineDiffError.tooManyLines(maximumLines: maximumLines)
        }
    }

    private static func validate(path: String) throws {
        guard !path.isEmpty,
            !path.utf8.contains(0)
        else {
            throw PatchGeneratorError.invalidPath(path)
        }
    }

    private static func headerPath(_ path: String) -> String {
        let bytes = Array(path.utf8)
        let needsQuoting = bytes.contains {
            $0 <= 0x20 || $0 >= 0x7F || $0 == 0x22 || $0 == 0x5C
        }
        guard needsQuoting else { return path }

        var escaped: [UInt8] = [0x22]
        escaped.reserveCapacity(bytes.count + 2)
        for byte in bytes {
            switch byte {
            case 0x07: escaped.append(contentsOf: [0x5C, 0x61])
            case 0x08: escaped.append(contentsOf: [0x5C, 0x62])
            case 0x09: escaped.append(contentsOf: [0x5C, 0x74])
            case 0x0A: escaped.append(contentsOf: [0x5C, 0x6E])
            case 0x0B: escaped.append(contentsOf: [0x5C, 0x76])
            case 0x0C: escaped.append(contentsOf: [0x5C, 0x66])
            case 0x0D: escaped.append(contentsOf: [0x5C, 0x72])
            case 0x22, 0x5C:
                escaped.append(0x5C)
                escaped.append(byte)
            case 0x20...0x7E:
                escaped.append(byte)
            default:
                escaped.append(0x5C)
                escaped.append(0x30 + ((byte >> 6) & 0x07))
                escaped.append(0x30 + ((byte >> 3) & 0x07))
                escaped.append(0x30 + (byte & 0x07))
            }
        }
        escaped.append(0x22)
        return String(decoding: escaped, as: UTF8.self)
    }

    private static func hunkRanges(rows: [DiffRow], contextLines: Int) -> [Range<Int>] {
        var hunks: [Range<Int>] = []
        for index in rows.indices where rows[index].kind != .unchanged {
            let lowerBound = index > contextLines ? index - contextLines : 0
            let linesAfter = rows.count - index - 1
            let upperBound = contextLines >= linesAfter ? rows.count : index + contextLines + 1
            if let lastIndex = hunks.indices.last, lowerBound <= hunks[lastIndex].upperBound {
                hunks[lastIndex] = hunks[lastIndex].lowerBound..<max(hunks[lastIndex].upperBound, upperBound)
            } else {
                hunks.append(lowerBound..<upperBound)
            }
        }
        return hunks
    }

    private static func range(start: Int, count: Int) -> String {
        count == 1 ? String(start) : "\(start),\(count)"
    }

    private static func append(
        record: PatchDocument.Record?,
        prefix: UInt8,
        to output: inout BoundedOutput
    ) throws {
        guard let record else { return }
        try output.append(byte: prefix)
        try output.append(record.payload)
        try output.appendLF()
        if !record.hasLineFeed {
            try output.append("\\ No newline at end of file")
            try output.appendLF()
        }
    }
}

private struct PatchDocument {
    struct Record {
        let payload: [UInt8]
        let hasLineFeed: Bool
    }

    let records: [Record]

    init(_ source: String) {
        let bytes = Array(source.utf8)
        var records: [Record] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0A {
            records.append(Record(payload: Array(bytes[start..<index]), hasLineFeed: true))
            start = index + 1
        }
        if start < bytes.count {
            records.append(Record(payload: Array(bytes[start...]), hasLineFeed: false))
        }
        self.records = records
    }

    func record(number: Int) -> Record? {
        guard number > 0, number <= records.count else { return nil }
        return records[number - 1]
    }

    static func comparisonTexts(
        old: PatchDocument,
        new: PatchDocument
    ) -> (old: String, new: String) {
        var identifiers: [[UInt8]: Int] = [:]
        return (
            comparisonText(for: old, identifiers: &identifiers),
            comparisonText(for: new, identifiers: &identifiers)
        )
    }

    private static func comparisonText(
        for document: PatchDocument,
        identifiers: inout [[UInt8]: Int]
    ) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(document.records.count * 4)
        for record in document.records {
            let identifier: Int
            if let existing = identifiers[record.payload] {
                identifier = existing
            } else {
                identifier = identifiers.count
                identifiers[record.payload] = identifier
            }
            bytes.append(contentsOf: String(identifier).utf8)
            if record.hasLineFeed { bytes.append(0x0A) }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private struct BoundedOutput {
    private var bytes: [UInt8] = []
    private let maximumBytes: Int

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        bytes.reserveCapacity(min(maximumBytes, 64 * 1024))
    }

    var string: String { String(decoding: bytes, as: UTF8.self) }

    mutating func append(_ value: String) throws {
        try reserve(value.utf8.count)
        bytes.append(contentsOf: value.utf8)
    }

    mutating func append(_ value: [UInt8]) throws {
        try reserve(value.count)
        bytes.append(contentsOf: value)
    }

    mutating func append(byte: UInt8) throws {
        try reserve(1)
        bytes.append(byte)
    }

    mutating func appendLF() throws {
        try append(byte: 0x0A)
    }

    private mutating func reserve(_ count: Int) throws {
        guard count <= maximumBytes - bytes.count else {
            throw PatchGeneratorError.outputTooLarge(maximumBytes: maximumBytes)
        }
    }
}
