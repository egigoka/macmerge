import XCTest
@testable import MacMergeCore

final class NoneAlgorithmBlankLineTests: XCTestCase {
    private let whitespaceModes: [WhitespaceComparison] = [.compareAll, .ignoreChanges, .ignoreAll]
    private let realigningAlgorithms: [DiffAlgorithm] = [.default, .minimal, .patience, .histogram]

    func testOneSidedBlankLinesDoNotRealignNoneAlgorithm() throws {
        let baseLines = ["alpha", "middle", "omega"]
        let base = baseLines.joined(separator: "\n") + "\n"

        for whitespace in whitespaceModes {
            for blank in ["", " ", "\t", " \t "] {
                for insertionIndex in 0...baseLines.count {
                    var linesWithBlank = baseLines
                    linesWithBlank.insert(blank, at: insertionIndex)
                    let withBlank = linesWithBlank.joined(separator: "\n") + "\n"

                    for blankIsOnLeft in [true, false] {
                        let left = blankIsOnLeft ? withBlank : base
                        let right = blankIsOnLeft ? base : withBlank
                        let context =
                            "whitespace=\(whitespace), blank=\(blank.debugDescription), "
                            + "index=\(insertionIndex), left=\(blankIsOnLeft)"
                        let expectedIDs = expectedIDs(
                            baseLineCount: baseLines.count,
                            insertionIndex: insertionIndex,
                            insertedOnLeft: blankIsOnLeft
                        )
                        let expectedKinds =
                            Array(repeating: DiffKind.unchanged, count: insertionIndex + 1)
                            + Array(
                                repeating: DiffKind.modified,
                                count: baseLines.count - insertionIndex
                            )
                        let noneRows = try compare(
                            left: left,
                            right: right,
                            algorithm: .none,
                            whitespace: whitespace,
                            ignoreBlankLines: true
                        )

                        XCTAssertEqual(noneRows.map(\.id), expectedIDs, context)
                        XCTAssertEqual(noneRows.map(\.kind), expectedKinds, context)
                        XCTAssertEqual(
                            DiffSummary(rows: noneRows).differences,
                            baseLines.count - insertionIndex,
                            context
                        )
                        assertSourceLines(
                            noneRows,
                            left: blankIsOnLeft ? linesWithBlank : baseLines,
                            right: blankIsOnLeft ? baseLines : linesWithBlank,
                            context: context
                        )

                        for algorithm in realigningAlgorithms {
                            let rows = try compare(
                                left: left,
                                right: right,
                                algorithm: algorithm,
                                whitespace: whitespace,
                                ignoreBlankLines: true
                            )
                            XCTAssertEqual(rows.map(\.id), expectedIDs, "\(algorithm): \(context)")
                            XCTAssertTrue(
                                rows.allSatisfy { $0.kind == .unchanged },
                                "\(algorithm): \(context)"
                            )
                        }
                    }
                }
            }
        }
    }

    func testAdjacentUnevenBlankRunsRemainPositional() throws {
        let leftLines = ["head", "", " ", "body", "\t", "tail"]
        let rightLines = ["head", "\t", "body", "", " ", "tail"]
        let left = leftLines.joined(separator: "\n") + "\n"
        let right = rightLines.joined(separator: "\n") + "\n"
        let expectedNonblankIDs = [
            DiffRow.ID(leftNumber: 1, rightNumber: 1),
            DiffRow.ID(leftNumber: 3, rightNumber: 3),
            DiffRow.ID(leftNumber: 4, rightNumber: 4),
            DiffRow.ID(leftNumber: 6, rightNumber: 6)
        ]
        let expectedKinds: [DiffKind] = [
            .unchanged, .unchanged, .modified, .modified, .unchanged, .unchanged
        ]

        for whitespace in whitespaceModes {
            let context = "whitespace=\(whitespace)"
            let rows = try compare(
                left: left,
                right: right,
                algorithm: .none,
                whitespace: whitespace,
                ignoreBlankLines: true
            )

            XCTAssertEqual(DiffSummary(rows: rows).differences, 2, context)
            XCTAssertEqual(rows.map(\.kind), expectedKinds, context)
            XCTAssertEqual(
                rows.filter { row in
                    row.left.map { !isBlank($0.text) } == true
                        || row.right.map { !isBlank($0.text) } == true
                }.map(\.id),
                expectedNonblankIDs,
                context
            )
            assertSourceLines(rows, left: leftLines, right: rightLines, context: context)
        }
    }

    func testIgnoreBlankLinesFalseKeepsNoneAlgorithmPositionalChanges() throws {
        let base = "head\nbody\ntail\n"
        let blankOnLeft = try compare(
            left: "head\n \nbody\ntail\n",
            right: base,
            algorithm: .none,
            whitespace: .compareAll,
            ignoreBlankLines: false
        )
        let blankOnRight = try compare(
            left: base,
            right: "head\n\t\nbody\ntail\n",
            algorithm: .none,
            whitespace: .compareAll,
            ignoreBlankLines: false
        )

        XCTAssertEqual(blankOnLeft.map(\.kind), [.unchanged, .modified, .modified, .removed])
        XCTAssertEqual(blankOnLeft.map(\.id), [id(1, 1), id(2, 2), id(3, 3), id(4, nil)])
        XCTAssertEqual(blankOnRight.map(\.kind), [.unchanged, .modified, .modified, .added])
        XCTAssertEqual(blankOnRight.map(\.id), [id(1, 1), id(2, 2), id(3, 3), id(nil, 4)])
        XCTAssertEqual(DiffSummary(rows: blankOnLeft).differences, 3)
        XCTAssertEqual(DiffSummary(rows: blankOnRight).differences, 3)
    }

    func testWhitespaceModesStillControlNonblankComparisons() throws {
        let runFixtures: [(WhitespaceComparison, Int)] = [
            (.compareAll, 1),
            (.ignoreChanges, 0),
            (.ignoreAll, 0)
        ]
        let gapFixtures: [(WhitespaceComparison, Int)] = [
            (.compareAll, 1),
            (.ignoreChanges, 1),
            (.ignoreAll, 0)
        ]

        for (whitespace, expectedDifferences) in runFixtures {
            try assertAlgorithmParity(
                left: "head\na  b\ntail\n",
                right: "head\na b\ntail\n",
                whitespace: whitespace,
                expectedDifferences: expectedDifferences
            )
        }
        for (whitespace, expectedDifferences) in gapFixtures {
            try assertAlgorithmParity(
                left: "head\na b\ntail\n",
                right: "head\nab\ntail\n",
                whitespace: whitespace,
                expectedDifferences: expectedDifferences
            )
        }
    }

    func testIgnoredTrailingBlankLinePreservesFinalEOLPolicy() throws {
        for whitespace in whitespaceModes {
            let strictBlankOnly = try compare(
                left: "tail\n \n",
                right: "tail\n",
                algorithm: .none,
                whitespace: whitespace,
                ignoreBlankLines: true,
                ignoreLineEndings: false
            )
            let normalizedEOL = try compare(
                left: "tail\n\t\n",
                right: "tail",
                algorithm: .none,
                whitespace: whitespace,
                ignoreBlankLines: true,
                ignoreLineEndings: true
            )
            let strictEOL = try compare(
                left: "tail\n\n",
                right: "tail",
                algorithm: .none,
                whitespace: whitespace,
                ignoreBlankLines: true,
                ignoreLineEndings: false
            )

            XCTAssertEqual(DiffSummary(rows: strictBlankOnly).differences, 0, "\(whitespace)")
            XCTAssertEqual(strictBlankOnly.map(\.kind), [.unchanged, .unchanged], "\(whitespace)")
            XCTAssertEqual(DiffSummary(rows: normalizedEOL).differences, 0, "\(whitespace)")
            XCTAssertEqual(normalizedEOL.map(\.kind), [.unchanged, .unchanged], "\(whitespace)")
            XCTAssertEqual(DiffSummary(rows: strictEOL).differences, 1, "\(whitespace)")
            XCTAssertEqual(strictEOL.map(\.kind), [.modified, .unchanged], "\(whitespace)")
            XCTAssertEqual(strictEOL.map(\.id), [id(1, 1), id(2, nil)], "\(whitespace)")
        }
    }

    func testNonblankInsertionRetainsNoneAlgorithmPositionalSemantics() throws {
        let left = "head\none\ntwo\ntail\n"
        let right = "head\ninserted\none\ntwo\ntail\n"
        let expectedKinds: [DiffKind] = [.unchanged, .modified, .modified, .modified, .added]
        let expectedIDs = [id(1, 1), id(2, 2), id(3, 3), id(4, 4), id(nil, 5)]
        let ignoredBlankRows = try compare(
            left: left,
            right: right,
            algorithm: .none,
            whitespace: .compareAll,
            ignoreBlankLines: true
        )
        let strictRows = try compare(
            left: left,
            right: right,
            algorithm: .none,
            whitespace: .compareAll,
            ignoreBlankLines: false
        )

        XCTAssertEqual(ignoredBlankRows.map(\.kind), expectedKinds)
        XCTAssertEqual(ignoredBlankRows.map(\.id), expectedIDs)
        XCTAssertEqual(ignoredBlankRows, strictRows)
        XCTAssertEqual(DiffSummary(rows: ignoredBlankRows).differences, 4)

        for algorithm in realigningAlgorithms {
            let rows = try compare(
                left: left,
                right: right,
                algorithm: algorithm,
                whitespace: .compareAll,
                ignoreBlankLines: true
            )
            XCTAssertEqual(DiffSummary(rows: rows).differences, 1, "\(algorithm)")
            XCTAssertEqual(rows.filter { $0.kind != .unchanged }.map(\.id), [id(nil, 2)], "\(algorithm)")
            XCTAssertEqual(rows.filter { $0.kind != .unchanged }.map(\.right?.text), ["inserted"], "\(algorithm)")
        }
    }

    private func compare(
        left: String,
        right: String,
        algorithm: DiffAlgorithm,
        whitespace: WhitespaceComparison,
        ignoreBlankLines: Bool,
        ignoreLineEndings: Bool = true
    ) throws -> [DiffRow] {
        try LineDiff.compare(
            left: left,
            right: right,
            options: LineDiffOptions(
                algorithm: algorithm,
                whitespace: whitespace,
                ignoreBlankLines: ignoreBlankLines,
                ignoreLineEndings: ignoreLineEndings
            )
        )
    }

    private func assertAlgorithmParity(
        left: String,
        right: String,
        whitespace: WhitespaceComparison,
        expectedDifferences: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for algorithm in [DiffAlgorithm.none] + realigningAlgorithms {
            let rows = try compare(
                left: left,
                right: right,
                algorithm: algorithm,
                whitespace: whitespace,
                ignoreBlankLines: true
            )
            XCTAssertEqual(
                DiffSummary(rows: rows).differences,
                expectedDifferences,
                "algorithm=\(algorithm), whitespace=\(whitespace)",
                file: file,
                line: line
            )
        }
    }

    private func expectedIDs(
        baseLineCount: Int,
        insertionIndex: Int,
        insertedOnLeft: Bool
    ) -> [DiffRow.ID] {
        var result: [DiffRow.ID] = []
        for baseIndex in 0..<baseLineCount {
            if baseIndex == insertionIndex {
                result.append(insertedOnLeft ? id(baseIndex + 1, nil) : id(nil, baseIndex + 1))
            }
            let insertedNumber = baseIndex + 1 + (baseIndex >= insertionIndex ? 1 : 0)
            result.append(
                insertedOnLeft
                    ? id(insertedNumber, baseIndex + 1)
                    : id(baseIndex + 1, insertedNumber)
            )
        }
        if insertionIndex == baseLineCount {
            result.append(
                insertedOnLeft
                    ? id(baseLineCount + 1, nil)
                    : id(nil, baseLineCount + 1)
            )
        }
        return result
    }

    private func assertSourceLines(
        _ rows: [DiffRow],
        left: [String],
        right: [String],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(rows.compactMap(\.left?.text), left, context, file: file, line: line)
        XCTAssertEqual(rows.compactMap(\.right?.text), right, context, file: file, line: line)
        XCTAssertEqual(rows.compactMap(\.left?.number), Array(1...left.count), context, file: file, line: line)
        XCTAssertEqual(rows.compactMap(\.right?.number), Array(1...right.count), context, file: file, line: line)
    }

    private func isBlank(_ text: String) -> Bool {
        text.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private func id(_ left: Int?, _ right: Int?) -> DiffRow.ID {
        DiffRow.ID(leftNumber: left, rightNumber: right)
    }
}
