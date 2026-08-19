import Foundation
import XCTest
@testable import MacMergeCore

final class PairwiseComparisonOptionTests: XCTestCase {
    private static let matrix = makePairwiseMatrix()

    func testGeneratedMatrixCoversEveryPairAndMatchesSemanticOracle() throws {
        assertPairwiseCoverage(Self.matrix)
        XCTAssertLessThanOrEqual(Self.matrix.count, 64, "Pairwise matrix must remain bounded")

        for testCase in Self.matrix {
            for fixture in Self.semanticFixtures {
                let rows = try LineDiff.compare(
                    left: fixture.leftText,
                    right: fixture.rightText,
                    options: testCase.options
                )
                let expected = fixture.feature.isSignificant(for: testCase) ? 1 : 0
                let oracle = Self.significantDistance(
                    Self.normalized(fixture.left, for: testCase),
                    Self.normalized(fixture.right, for: testCase)
                )
                let context = "\(fixture.feature.name): \(testCase.description)"

                XCTAssertEqual(oracle, expected, "Independent transform drift. \(context)")
                let actual = DiffSummary(rows: rows).differences
                if expected == 0 {
                    XCTAssertEqual(actual, 0, context)
                } else {
                    XCTAssertGreaterThan(actual, 0, context)
                }
                XCTAssertEqual(rows.compactMap(\.left?.text), fixture.left.map(\.content), context)
                XCTAssertEqual(rows.compactMap(\.right?.text), fixture.right.map(\.content), context)
            }
        }
    }

    func testGeneratedMatrixPreservesMovedDetectionInteractions() throws {
        let left = "head\nmove seed\nstable one\nstable two\nstable three\ntail"
        let right = "head\nstable one\nstable two\nstable three\nmove seed\ntail"

        for testCase in Self.matrix {
            let result = try LineDiff.compareResult(left: left, right: right, options: testCase.options)
            let context = testCase.description

            if testCase.detectMovedBlocks {
                XCTAssertFalse(result.movedLines.isEmpty, context)
                XCTAssertEqual(result.movedLines.rightLine(forLeftLine: 2), 5, context)
                XCTAssertEqual(result.movedLines.leftLine(forRightLine: 5), 2, context)
            } else {
                XCTAssertTrue(result.movedLines.isEmpty, context)
            }
        }
    }

    func testGeneratedMatrixPreservesIndentAlignmentInteractions() throws {
        let left = ["1", "2", "a", "", "b", "3", "4"].joined(separator: "\n")
        let right = ["1", "2", "a", "", "b", "a", "", "b", "3", "4"]
            .joined(separator: "\n")

        for testCase in Self.matrix {
            let rows = try LineDiff.compare(left: left, right: right, options: testCase.options)
            let insertedRightLines = rows.compactMap { row in
                row.left == nil ? row.right?.number : nil
            }
            let expected: [Int]
            if testCase.algorithm == .none {
                expected = testCase.ignoreBlankLines ? [7, 9, 10] : [8, 9, 10]
            } else {
                expected = testCase.indentHeuristic ? [5, 6, 7] : [6, 7, 8]
            }

            XCTAssertEqual(insertedRightLines, expected, testCase.description)
        }
    }

    private func assertPairwiseCoverage(
        _ matrix: [MatrixCase],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for first in Factor.allCases {
            for second in Factor.allCases where first.rawValue < second.rawValue {
                for firstValue in 0..<first.domainCount {
                    for secondValue in 0..<second.domainCount {
                        XCTAssertTrue(
                            matrix.contains {
                                $0[first] == firstValue && $0[second] == secondValue
                            },
                            "Missing pair \(first.name)=\(firstValue), \(second.name)=\(secondValue)",
                            file: file,
                            line: line
                        )
                    }
                }
            }
        }
    }

    private static func makePairwiseMatrix() -> [MatrixCase] {
        var candidates = [MatrixCase(values: [])]
        for factor in Factor.allCases {
            candidates = candidates.flatMap { candidate in
                (0..<factor.domainCount).map { value in
                    MatrixCase(values: candidate.values + [value])
                }
            }
        }

        let coveredCandidates = candidates.map { candidate in
            (testCase: candidate, requirements: requirements(for: candidate))
        }
        var uncovered = Set(coveredCandidates.flatMap(\.requirements))
        var matrix: [MatrixCase] = []

        while !uncovered.isEmpty {
            var bestIndex = 0
            var bestScore = -1
            for (index, candidate) in coveredCandidates.enumerated() {
                let score = candidate.requirements.reduce(into: 0) { count, requirement in
                    if uncovered.contains(requirement) { count += 1 }
                }
                if score > bestScore {
                    bestIndex = index
                    bestScore = score
                }
            }
            precondition(bestScore > 0, "Pairwise generator stalled")
            let best = coveredCandidates[bestIndex]
            matrix.append(best.testCase)
            uncovered.subtract(best.requirements)
        }

        return matrix
    }

    private static func requirements(for testCase: MatrixCase) -> [PairRequirement] {
        var result: [PairRequirement] = []
        for first in Factor.allCases {
            for second in Factor.allCases where first.rawValue < second.rawValue {
                result.append(
                    PairRequirement(
                        first: first,
                        firstValue: testCase[first],
                        second: second,
                        secondValue: testCase[second]
                    )
                )
            }
        }
        return result
    }

    private static let semanticFixtures: [Fixture] = {
        func line(_ content: String, _ terminator: String = "\n") -> FixtureLine {
            FixtureLine(content: content, terminator: terminator)
        }

        return [
            Fixture(feature: .ignoreCase, left: [line("case: ALPHA")], right: [line("case: alpha")]),
            Fixture(feature: .ignoreNumbers, left: [line("number: build 100")], right: [line("number: build 200")]),
            Fixture(feature: .whitespaceRun, left: [line("space-run: a   b")], right: [line("space-run: a b")]),
            Fixture(feature: .whitespaceGap, left: [line("space-gap: a b")], right: [line("space-gap: ab")]),
            Fixture(
                feature: .ignoreBlankLines,
                left: [line("head"), line(" \t"), line("tail")],
                right: [line("head"), line("tail")]
            ),
            Fixture(
                feature: .ignoreComments,
                left: [line("comment: stable // left")],
                right: [line("comment: stable // right")]
            ),
            Fixture(feature: .lineFilter, left: [line("generated: left")], right: [line("generated: right")]),
            Fixture(
                feature: .substitution,
                left: [line("version: left-token")],
                right: [line("version: right-token")]
            ),
            Fixture(feature: .ignoreLineEndings, left: [line("eol: stable", "\r\n")], right: [line("eol: stable")]),
            Fixture(feature: .control, left: [line("semantic-left")], right: [line("semantic-right")])
        ]
    }()

    private static func normalized(_ lines: [FixtureLine], for testCase: MatrixCase) -> [FixtureLine] {
        lines.compactMap { source in
            if testCase.ignoreBlankLines,
                testCase.algorithm != .none,
                source.content.allSatisfy(isComparisonWhitespace)
            {
                return nil
            }

            var content = source.content
            if testCase.ignoreComments, let comment = content.range(of: "//") {
                content.removeSubrange(comment.lowerBound...)
            }
            if testCase.lineFiltersEnabled, content.hasPrefix("generated:") {
                content = "<filtered>"
            }
            if testCase.substitutionsEnabled {
                content =
                    content
                    .replacingOccurrences(of: "left-token", with: "stable-token")
                    .replacingOccurrences(of: "right-token", with: "stable-token")
            }
            if testCase.ignoreCase {
                content = content.lowercased()
            }
            if testCase.ignoreNumbers {
                content = String(content.unicodeScalars.filter { !(48...57).contains($0.value) })
            }
            switch testCase.whitespace {
            case .compareAll:
                break
            case .ignoreChanges:
                content = content.split(whereSeparator: isComparisonWhitespace).joined(separator: " ")
            case .ignoreAll:
                content.removeAll(where: isComparisonWhitespace)
            }

            return FixtureLine(
                content: content,
                terminator: testCase.ignoreLineEndings ? "\n" : source.terminator
            )
        }
    }

    private static func significantDistance(_ left: [FixtureLine], _ right: [FixtureLine]) -> Int {
        var previous = Array(0...right.count)
        for (leftOffset, leftLine) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftOffset + 1
            for (rightOffset, rightLine) in right.enumerated() {
                current[rightOffset + 1] = min(
                    previous[rightOffset + 1] + 1,
                    current[rightOffset] + 1,
                    previous[rightOffset] + (leftLine == rightLine ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func isComparisonWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\u{0B}" || character == "\u{0C}"
    }
}

extension PairwiseComparisonOptionTests {
    fileprivate enum Factor: Int, CaseIterable, Hashable, Sendable {
        case algorithm
        case whitespace
        case ignoreCase
        case ignoreNumbers
        case ignoreBlankLines
        case ignoreComments
        case ignoreLineEndings
        case indentHeuristic
        case detectMovedBlocks
        case lineFiltersEnabled
        case substitutionsEnabled

        var domainCount: Int {
            switch self {
            case .algorithm: 5
            case .whitespace: 3
            default: 2
            }
        }

        var name: String { String(describing: self) }
    }

    fileprivate struct PairRequirement: Hashable, Sendable {
        let first: Factor
        let firstValue: Int
        let second: Factor
        let secondValue: Int
    }

    fileprivate struct MatrixCase: Hashable, Sendable, CustomStringConvertible {
        let values: [Int]

        subscript(_ factor: Factor) -> Int { values[factor.rawValue] }

        var algorithm: DiffAlgorithm {
            [DiffAlgorithm.default, .minimal, .patience, .histogram, .none][self[.algorithm]]
        }

        var whitespace: WhitespaceComparison {
            [WhitespaceComparison.compareAll, .ignoreChanges, .ignoreAll][self[.whitespace]]
        }

        var ignoreCase: Bool { self[.ignoreCase] == 1 }
        var ignoreNumbers: Bool { self[.ignoreNumbers] == 1 }
        var ignoreBlankLines: Bool { self[.ignoreBlankLines] == 1 }
        var ignoreComments: Bool { self[.ignoreComments] == 1 }
        var ignoreLineEndings: Bool { self[.ignoreLineEndings] == 1 }
        var indentHeuristic: Bool { self[.indentHeuristic] == 1 }
        var detectMovedBlocks: Bool { self[.detectMovedBlocks] == 1 }
        var lineFiltersEnabled: Bool { self[.lineFiltersEnabled] == 1 }
        var substitutionsEnabled: Bool { self[.substitutionsEnabled] == 1 }

        var options: LineDiffOptions {
            LineDiffOptions(
                algorithm: algorithm,
                whitespace: whitespace,
                ignoreCase: ignoreCase,
                ignoreNumbers: ignoreNumbers,
                ignoreBlankLines: ignoreBlankLines,
                ignoreComments: ignoreComments,
                ignoreLineEndings: ignoreLineEndings,
                indentHeuristic: indentHeuristic,
                detectMovedBlocks: detectMovedBlocks,
                lineFiltersEnabled: lineFiltersEnabled,
                lineFilters: [LineFilterRule(pattern: "^generated:")],
                substitutionsEnabled: substitutionsEnabled,
                substitutions: [
                    SubstitutionRule(pattern: "(?:left|right)-token", replacement: "stable-token")
                ],
                commentSyntax: .cFamily
            )
        }

        var description: String {
            [
                "algorithm=\(algorithm.rawValue)",
                "whitespace=\(whitespace.rawValue)",
                "case=\(ignoreCase)",
                "numbers=\(ignoreNumbers)",
                "blank=\(ignoreBlankLines)",
                "comments=\(ignoreComments)",
                "eol=\(ignoreLineEndings)",
                "indent=\(indentHeuristic)",
                "moved=\(detectMovedBlocks)",
                "filters=\(lineFiltersEnabled)",
                "substitutions=\(substitutionsEnabled)"
            ].joined(separator: ", ")
        }
    }

    fileprivate struct FixtureLine: Equatable, Sendable {
        let content: String
        let terminator: String
    }

    fileprivate enum FixtureFeature: Sendable {
        case ignoreCase
        case ignoreNumbers
        case whitespaceRun
        case whitespaceGap
        case ignoreBlankLines
        case ignoreComments
        case ignoreLineEndings
        case lineFilter
        case substitution
        case control

        var name: String { String(describing: self) }

        func isSignificant(for testCase: MatrixCase) -> Bool {
            switch self {
            case .ignoreCase: !testCase.ignoreCase
            case .ignoreNumbers: !testCase.ignoreNumbers
            case .whitespaceRun: testCase.whitespace == .compareAll
            case .whitespaceGap: testCase.whitespace != .ignoreAll
            case .ignoreBlankLines: !testCase.ignoreBlankLines || testCase.algorithm == .none
            case .ignoreComments: !testCase.ignoreComments
            case .ignoreLineEndings: !testCase.ignoreLineEndings
            case .lineFilter: !testCase.lineFiltersEnabled
            case .substitution: !testCase.substitutionsEnabled
            case .control: true
            }
        }
    }

    fileprivate struct Fixture: Sendable {
        let feature: FixtureFeature
        let left: [FixtureLine]
        let right: [FixtureLine]

        var leftText: String { left.map { $0.content + $0.terminator }.joined() }
        var rightText: String { right.map { $0.content + $0.terminator }.joined() }
    }
}
