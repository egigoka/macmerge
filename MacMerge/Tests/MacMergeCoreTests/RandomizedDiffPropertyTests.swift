@testable import MacMergeCore
import XCTest

final class RandomizedDiffPropertyTests: XCTestCase {
    private let alignmentSeed: UInt64 = 0xD1FF_A11C_E5EE_D001
    private let mergeSeed: UInt64 = 0xA11C_E5AF_E123_9009

    func testGeneratedDocumentsPreserveAlignedRowsAndSourceLines() throws {
        var random = SeededRandomNumberGenerator(seed: alignmentSeed)
        var serial = 0
        let algorithms: [DiffAlgorithm] = [.default, .minimal, .patience, .histogram, .none]

        for caseIndex in 0..<96 {
            let pair = makeDocumentPair(random: &random, serial: &serial)
            let options = LineDiffOptions(
                algorithm: algorithms[caseIndex % algorithms.count],
                ignoreLineEndings: caseIndex % 3 != 0
            )
            let rows = try LineDiff.compare(left: pair.left, right: pair.right, options: options)
            let context = caseContext(
                seed: alignmentSeed,
                caseIndex: caseIndex,
                left: pair.left,
                right: pair.right
            )

            assertAlignment(rows, left: pair.left, right: pair.right, context: context)
        }
    }

    func testGeneratedDocumentsPreserveSafeMergeInvariants() throws {
        var random = SeededRandomNumberGenerator(seed: mergeSeed)
        var serial = 0
        let algorithms: [DiffAlgorithm] = [.default, .minimal, .patience, .histogram, .none]

        for caseIndex in 0..<48 {
            let pair = makeDocumentPair(random: &random, serial: &serial)
            let options = LineDiffOptions(
                algorithm: algorithms[caseIndex % algorithms.count],
                ignoreLineEndings: false
            )
            let rows = try LineDiff.compare(left: pair.left, right: pair.right, options: options)
            let context = caseContext(
                seed: mergeSeed,
                caseIndex: caseIndex,
                left: pair.left,
                right: pair.right
            )
            let leftToRight = try LineMerge.applyAll(
                direction: .leftToRight,
                left: pair.left,
                right: pair.right,
                options: options
            )
            let rightToLeft = try LineMerge.applyAll(
                direction: .rightToLeft,
                left: pair.left,
                right: pair.right,
                options: options
            )

            guard DiffSummary(rows: rows).differences > 0 else {
                XCTAssertNil(leftToRight, context)
                XCTAssertNil(rightToLeft, context)
                continue
            }
            guard let leftToRight, let rightToLeft else {
                XCTFail("Merge unexpectedly returned nil. \(context)")
                continue
            }

            XCTAssertEqual(leftToRight.left, pair.left, context)
            XCTAssertEqual(rightToLeft.right, pair.right, context)
            XCTAssertEqual(
                records(in: leftToRight.right).map(\.content),
                records(in: pair.left).map(\.content),
                context
            )
            XCTAssertEqual(
                records(in: rightToLeft.left).map(\.content),
                records(in: pair.right).map(\.content),
                context
            )
            if !options.ignoreLineEndings {
                XCTAssertEqual(leftToRight.right, pair.left, context)
                XCTAssertEqual(rightToLeft.left, pair.right, context)
            }

            XCTAssertEqual(
                try DiffSummary(rows: LineDiff.compare(
                    left: pair.left,
                    right: leftToRight.right,
                    options: options
                )).differences,
                0,
                context
            )
            XCTAssertEqual(
                try DiffSummary(rows: LineDiff.compare(
                    left: rightToLeft.left,
                    right: pair.right,
                    options: options
                )).differences,
                0,
                context
            )
            XCTAssertNil(
                try LineMerge.applyAll(
                    direction: .leftToRight,
                    left: pair.left,
                    right: leftToRight.right,
                    options: options
                ),
                context
            )
            XCTAssertNil(
                try LineMerge.applyAll(
                    direction: .rightToLeft,
                    left: rightToLeft.left,
                    right: pair.right,
                    options: options
                ),
                context
            )
        }
    }

    private func assertAlignment(
        _ rows: [DiffRow],
        left: String,
        right: String,
        context: String
    ) {
        let leftRecords = records(in: left)
        let rightRecords = records(in: right)

        assertSourceReconstruction(
            lines: rows.compactMap(\.left),
            records: leftRecords,
            original: left,
            side: "left",
            context: context
        )
        assertSourceReconstruction(
            lines: rows.compactMap(\.right),
            records: rightRecords,
            original: right,
            side: "right",
            context: context
        )

        for row in rows {
            XCTAssertTrue(row.left != nil || row.right != nil, context)
            XCTAssertEqual(row.id.leftNumber, row.left?.number, context)
            XCTAssertEqual(row.id.rightNumber, row.right?.number, context)

            switch row.kind {
            case .unchanged:
                XCTAssertNotNil(row.left, context)
                XCTAssertNotNil(row.right, context)
                if let left = row.left, let right = row.right {
                    XCTAssertEqual(Array(left.text.utf8), Array(right.text.utf8), context)
                }
            case .modified:
                XCTAssertNotNil(row.left, context)
                XCTAssertNotNil(row.right, context)
            case .removed:
                XCTAssertNotNil(row.left, context)
                XCTAssertNil(row.right, context)
            case .added:
                XCTAssertNil(row.left, context)
                XCTAssertNotNil(row.right, context)
            }
        }
    }

    private func assertSourceReconstruction(
        lines: [DiffLine],
        records: [LineRecord],
        original: String,
        side: String,
        context: String
    ) {
        let expectedNumbers = records.isEmpty ? [] : Array(1...records.count)
        XCTAssertEqual(lines.map(\.number), expectedNumbers, "\(side): \(context)")
        XCTAssertEqual(lines.map(\.text), records.map(\.content), "\(side): \(context)")

        var reconstructed = ""
        for line in lines {
            let recordIndex = line.number - 1
            guard records.indices.contains(recordIndex) else {
                XCTFail("\(side) line number out of range: \(line.number). \(context)")
                continue
            }
            reconstructed += line.text + records[recordIndex].terminator
        }
        XCTAssertEqual(reconstructed, original, "\(side): \(context)")
    }

    private func makeDocumentPair(
        random: inout SeededRandomNumberGenerator,
        serial: inout Int
    ) -> (left: String, right: String) {
        var leftLines = (0..<random.int(through: 24)).map { _ in
            randomLine(random: &random, serial: &serial)
        }
        var rightLines = leftLines

        for _ in 0..<random.int(through: 12) {
            switch random.int(through: 4) {
            case 0:
                rightLines.insert(
                    randomLine(random: &random, serial: &serial),
                    at: random.int(through: rightLines.count)
                )
            case 1 where !rightLines.isEmpty:
                rightLines.remove(at: random.int(below: rightLines.count))
            case 2 where !rightLines.isEmpty:
                rightLines[random.int(below: rightLines.count)] = randomLine(
                    random: &random,
                    serial: &serial
                )
            case 3 where !rightLines.isEmpty:
                let line = rightLines[random.int(below: rightLines.count)]
                rightLines.insert(line, at: random.int(through: rightLines.count))
            case 4 where rightLines.count > 1:
                let line = rightLines.remove(at: random.int(below: rightLines.count))
                rightLines.insert(line, at: random.int(through: rightLines.count))
            default:
                leftLines.append(randomLine(random: &random, serial: &serial))
            }
        }

        return (
            render(lines: leftLines, random: &random),
            render(lines: rightLines, random: &random)
        )
    }

    private func randomLine(
        random: inout SeededRandomNumberGenerator,
        serial: inout Int
    ) -> String {
        serial += 1
        return switch random.int(through: 9) {
        case 0:
            ""
        case 1:
            " \t"
        case 2:
            "value \(serial)"
        case 3:
            "caf\u{00E9} \(serial)"
        case 4:
            "cafe\u{0301} \(serial)"
        case 5:
            "emoji \u{1F642} \(serial)"
        case 6:
            "tabs\t\(serial)"
        case 7:
            "# record \(serial)"
        case 8:
            "repeat-\(random.int(through: 3))"
        default:
            "\(String(repeating: "x", count: random.int(through: 15) + 1))-\(serial)"
        }
    }

    private func render(
        lines: [String],
        random: inout SeededRandomNumberGenerator
    ) -> String {
        guard !lines.isEmpty else { return "" }
        let endings = ["\n", "\r\n", "\r"]
        var text = ""

        for (index, line) in lines.enumerated() {
            text += line
            if index < lines.count - 1 || line.isEmpty || random.bool() {
                text += endings[random.int(below: endings.count)]
            }
        }
        return text
    }

    private func records(in text: String) -> [LineRecord] {
        var records: [LineRecord] = []
        var start = text.startIndex
        var index = start

        while index < text.endIndex {
            let character = text[index]
            guard character == "\n" || character == "\r" || character == "\r\n" else {
                index = text.index(after: index)
                continue
            }
            records.append(LineRecord(
                content: String(text[start..<index]),
                terminator: String(character)
            ))
            index = text.index(after: index)
            start = index
        }
        if start < text.endIndex {
            records.append(LineRecord(content: String(text[start..<text.endIndex]), terminator: ""))
        }
        return records
    }

    private func caseContext(seed: UInt64, caseIndex: Int, left: String, right: String) -> String {
        "Seed 0x\(String(seed, radix: 16)), case \(caseIndex), " +
            "left \(left.debugDescription), right \(right.debugDescription)"
    }
}

private struct LineRecord: Equatable {
    let content: String
    let terminator: String
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func int(below upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    mutating func int(through upperBound: Int) -> Int {
        int(below: upperBound + 1)
    }

    mutating func bool() -> Bool {
        next() & 1 == 0
    }
}
