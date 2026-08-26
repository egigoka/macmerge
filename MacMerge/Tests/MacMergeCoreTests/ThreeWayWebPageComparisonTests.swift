import CXDiff
import XCTest

@testable import MacMergeCore

final class ThreeWayWebPageComparisonTests: XCTestCase {
    func testNormalizedDocumentsProduceEveryThreeWayOutcome() throws {
        struct Fixture {
            let name: String
            let left: [String]
            let middle: [String]
            let right: [String]
            let outcome: ThreeWayWebPageComparisonOutcome
            let resolutions: [ThreeWayWebPageComparisonResolution]
            let mergedText: String?
            let equality: (leftMiddle: Bool, rightMiddle: Bool, leftRight: Bool)
            let differenceIDs: [Int]
            let conflictIDs: [Int]
            let regionDifferenceFlags: [Bool]
            let regionConflictFlags: [Bool]
        }

        let fixtures = [
            Fixture(
                name: "equal",
                left: ["alpha", "beta", "gamma"],
                middle: ["alpha", "beta", "gamma"],
                right: ["alpha", "beta", "gamma"],
                outcome: .equal,
                resolutions: [.unchanged],
                mergedText: "alpha\nbeta\ngamma\n",
                equality: (true, true, true),
                differenceIDs: [],
                conflictIDs: [],
                regionDifferenceFlags: [false],
                regionConflictFlags: [false]
            ),
            Fixture(
                name: "left only",
                left: ["alpha", "BETA", "gamma"],
                middle: ["alpha", "beta", "gamma"],
                right: ["alpha", "beta", "gamma"],
                outcome: .leftOnly,
                resolutions: [.unchanged, .left, .unchanged],
                mergedText: "alpha\nBETA\ngamma\n",
                equality: (false, true, false),
                differenceIDs: [1],
                conflictIDs: [],
                regionDifferenceFlags: [false, true, false],
                regionConflictFlags: [false, false, false]
            ),
            Fixture(
                name: "right only",
                left: ["alpha", "beta", "gamma"],
                middle: ["alpha", "beta", "gamma"],
                right: ["alpha", "BETA", "gamma"],
                outcome: .rightOnly,
                resolutions: [.unchanged, .right, .unchanged],
                mergedText: "alpha\nBETA\ngamma\n",
                equality: (true, false, false),
                differenceIDs: [1],
                conflictIDs: [],
                regionDifferenceFlags: [false, true, false],
                regionConflictFlags: [false, false, false]
            ),
            Fixture(
                name: "identical edits",
                left: ["alpha", "BETA", "gamma"],
                middle: ["alpha", "beta", "gamma"],
                right: ["alpha", "BETA", "gamma"],
                outcome: .identical,
                resolutions: [.unchanged, .identical, .unchanged],
                mergedText: "alpha\nBETA\ngamma\n",
                equality: (false, false, true),
                differenceIDs: [1],
                conflictIDs: [],
                regionDifferenceFlags: [false, true, false],
                regionConflictFlags: [false, false, false]
            ),
            Fixture(
                name: "both sides",
                left: ["alpha", "BETA", "gamma"],
                middle: ["alpha", "beta", "gamma"],
                right: ["alpha", "beta", "GAMMA"],
                outcome: .merged,
                resolutions: [.unchanged, .left, .right],
                mergedText: "alpha\nBETA\nGAMMA\n",
                equality: (false, false, false),
                differenceIDs: [1, 2],
                conflictIDs: [],
                regionDifferenceFlags: [false, true, true],
                regionConflictFlags: [false, false, false]
            ),
            Fixture(
                name: "conflict",
                left: ["alpha", "left beta", "gamma"],
                middle: ["alpha", "beta", "gamma"],
                right: ["alpha", "right beta", "gamma"],
                outcome: .conflict,
                resolutions: [.unchanged, .conflict, .unchanged],
                mergedText: nil,
                equality: (false, false, false),
                differenceIDs: [1],
                conflictIDs: [1],
                regionDifferenceFlags: [false, true, false],
                regionConflictFlags: [false, true, false]
            )
        ]

        for fixture in fixtures {
            let result = try compare(
                left: html(fixture.left),
                middle: html(fixture.middle),
                right: html(fixture.right),
                mode: .renderedText
            )

            XCTAssertEqual(result.outcome, fixture.outcome, fixture.name)
            XCTAssertEqual(result.regions.map(\.resolution), fixture.resolutions, fixture.name)
            XCTAssertEqual(result.automaticallyMergedComparisonText, fixture.mergedText, fixture.name)
            XCTAssertEqual(result.leftEqualsMiddle, fixture.equality.leftMiddle, fixture.name)
            XCTAssertEqual(result.rightEqualsMiddle, fixture.equality.rightMiddle, fixture.name)
            XCTAssertEqual(result.leftEqualsRight, fixture.equality.leftRight, fixture.name)
            XCTAssertEqual(result.differences.map(\.id), fixture.differenceIDs, fixture.name)
            XCTAssertEqual(result.conflicts.map(\.id), fixture.conflictIDs, fixture.name)
            XCTAssertEqual(result.regions.map(\.isDifference), fixture.regionDifferenceFlags, fixture.name)
            XCTAssertEqual(result.regions.map(\.isConflict), fixture.regionConflictFlags, fixture.name)
            XCTAssertEqual(result.hasDifferences, !fixture.differenceIDs.isEmpty, fixture.name)
            XCTAssertEqual(result.hasConflicts, !fixture.conflictIDs.isEmpty, fixture.name)
            XCTAssertEqual(result.isEqual, fixture.outcome == .equal, fixture.name)
        }
    }

    func testDifferentHTMLWithSameNormalizedTextIsEqual() throws {
        let result = try compare(
            left: "<div>alpha beta</div>",
            middle: "<p> alpha   beta </p>",
            right: "<section>alpha\tbeta</section>",
            mode: .renderedText
        )

        XCTAssertEqual(result.left.normalizedText, "alpha beta\n")
        XCTAssertEqual(result.left.normalizedText, result.middle.normalizedText)
        XCTAssertEqual(result.middle.normalizedText, result.right.normalizedText)
        XCTAssertEqual(result.outcome, .equal)
        XCTAssertEqual(result.regions.map(\.resolution), [.unchanged])
    }

    func testSourceModeMergedOutputIsReturnedWhenItExactlyEqualsOneCompleteSide() throws {
        let right = "X\nB\n"
        let result = try compare(
            left: "X\nA\n",
            middle: "A\n",
            right: right,
            mode: .source
        )

        XCTAssertEqual(result.outcome, .merged)
        XCTAssertEqual(result.regions.map(\.resolution), [.identical, .right])
        XCTAssertEqual(result.regions.map(\.left.lineRange), [0..<1, 1..<2])
        XCTAssertEqual(result.regions.map(\.middle.lineRange), [0..<0, 0..<1])
        XCTAssertEqual(result.regions.map(\.right.lineRange), [0..<1, 1..<2])
        XCTAssertEqual(result.regions.map(\.left.normalizedUTF8Range), [0..<2, 2..<4])
        XCTAssertEqual(result.regions.map(\.middle.normalizedUTF8Range), [0..<0, 0..<2])
        XCTAssertEqual(result.regions.map(\.right.normalizedUTF8Range), [0..<2, 2..<4])
        XCTAssertEqual(result.regions.map(\.left.sourceUTF8Ranges), [[0..<4], [0..<4]])
        XCTAssertEqual(result.regions.map(\.middle.sourceUTF8Ranges), [[], [0..<2]])
        XCTAssertEqual(result.regions.map(\.right.sourceUTF8Ranges), [[0..<4], [0..<4]])
        XCTAssertEqual(result.regions.map(\.automaticSource), [.left, .right])
        XCTAssertEqual(result.automaticallyMergedComparisonText, right)
        XCTAssertEqual(
            Array(try XCTUnwrap(result.automaticallyMergedComparisonText).utf8),
            Array(right.utf8)
        )
    }

    func testSharedBoundaryInsertionHasExactRangesWhenMirrored() throws {
        struct Fixture {
            let name: String
            let left: [String]
            let right: [String]
            let resolutions: [ThreeWayWebPageComparisonResolution]
            let automaticSources: [ThreeWayWebPageComparisonSource]
            let leftLineRanges: [Range<Int>]
            let middleLineRanges: [Range<Int>]
            let rightLineRanges: [Range<Int>]
            let leftNormalizedRanges: [Range<Int>]
            let middleNormalizedRanges: [Range<Int>]
            let rightNormalizedRanges: [Range<Int>]
            let leftSourceRanges: [[Range<Int>]]
            let middleSourceRanges: [[Range<Int>]]
            let rightSourceRanges: [[Range<Int>]]
        }

        let fixtures = [
            Fixture(
                name: "left then right",
                left: ["L", "X", "B"],
                right: ["A", "X", "R"],
                resolutions: [.left, .identical, .right, .right],
                automaticSources: [.left, .left, .right, .right],
                leftLineRanges: [0..<1, 1..<2, 2..<3, 3..<3],
                middleLineRanges: [0..<1, 1..<1, 1..<2, 2..<2],
                rightLineRanges: [0..<1, 1..<2, 2..<2, 2..<3],
                leftNormalizedRanges: [0..<2, 2..<4, 4..<6, 6..<6],
                middleNormalizedRanges: [0..<2, 2..<2, 2..<4, 4..<4],
                rightNormalizedRanges: [0..<2, 2..<4, 4..<4, 4..<6],
                leftSourceRanges: [
                    [3..<4, 4..<8], [11..<12, 12..<16], [19..<20, 20..<24], []
                ],
                middleSourceRanges: [
                    [3..<4, 4..<8], [], [11..<12, 12..<16], []
                ],
                rightSourceRanges: [
                    [3..<4, 4..<8], [11..<12, 12..<16], [], [19..<20, 20..<24]
                ]
            ),
            Fixture(
                name: "right then left",
                left: ["A", "X", "R"],
                right: ["L", "X", "B"],
                resolutions: [.right, .identical, .left, .left],
                automaticSources: [.right, .left, .left, .left],
                leftLineRanges: [0..<1, 1..<2, 2..<2, 2..<3],
                middleLineRanges: [0..<1, 1..<1, 1..<2, 2..<2],
                rightLineRanges: [0..<1, 1..<2, 2..<3, 3..<3],
                leftNormalizedRanges: [0..<2, 2..<4, 4..<4, 4..<6],
                middleNormalizedRanges: [0..<2, 2..<2, 2..<4, 4..<4],
                rightNormalizedRanges: [0..<2, 2..<4, 4..<6, 6..<6],
                leftSourceRanges: [
                    [3..<4, 4..<8], [11..<12, 12..<16], [], [19..<20, 20..<24]
                ],
                middleSourceRanges: [
                    [3..<4, 4..<8], [], [11..<12, 12..<16], []
                ],
                rightSourceRanges: [
                    [3..<4, 4..<8], [11..<12, 12..<16], [19..<20, 20..<24], []
                ]
            )
        ]

        for fixture in fixtures {
            let result = try compare(
                left: html(fixture.left),
                middle: html(["A", "B"]),
                right: html(fixture.right),
                mode: .renderedText
            )

            XCTAssertEqual(result.outcome, .merged, fixture.name)
            XCTAssertEqual(result.automaticallyMergedComparisonText, "L\nX\nR\n", fixture.name)
            XCTAssertEqual(result.regions.map(\.resolution), fixture.resolutions, fixture.name)
            XCTAssertEqual(result.regions.map(\.automaticSource), fixture.automaticSources, fixture.name)
            XCTAssertEqual(result.regions.map(\.left.lineRange), fixture.leftLineRanges, fixture.name)
            XCTAssertEqual(result.regions.map(\.middle.lineRange), fixture.middleLineRanges, fixture.name)
            XCTAssertEqual(result.regions.map(\.right.lineRange), fixture.rightLineRanges, fixture.name)
            XCTAssertEqual(result.regions.map(\.left.normalizedUTF8Range), fixture.leftNormalizedRanges, fixture.name)
            XCTAssertEqual(result.regions.map(\.middle.normalizedUTF8Range), fixture.middleNormalizedRanges, fixture.name)
            XCTAssertEqual(result.regions.map(\.right.normalizedUTF8Range), fixture.rightNormalizedRanges, fixture.name)
            XCTAssertEqual(result.regions.map(\.left.sourceUTF8Ranges), fixture.leftSourceRanges, fixture.name)
            XCTAssertEqual(result.regions.map(\.middle.sourceUTF8Ranges), fixture.middleSourceRanges, fixture.name)
            XCTAssertEqual(result.regions.map(\.right.sourceUTF8Ranges), fixture.rightSourceRanges, fixture.name)
            XCTAssertEqual(result.differences.map(\.id), [0, 1, 2, 3], fixture.name)
            XCTAssertEqual(result.conflicts, [], fixture.name)
            XCTAssertTrue(result.hasDifferences, fixture.name)
            XCTAssertFalse(result.hasConflicts, fixture.name)
        }
    }

    func testSourceModeRejectsCompositeOutputWhileRenderedTextRemainsSafe() throws {
        let sourceResult = try compare(
            left: "A\nb\n",
            middle: "a\nb\n",
            right: "a\nB\n",
            mode: .source
        )
        XCTAssertEqual(sourceResult.outcome, .merged)
        XCTAssertNil(sourceResult.automaticallyMergedComparisonText)
        XCTAssertEqual(sourceResult.conflicts, [])
        XCTAssertFalse(sourceResult.hasConflicts)

        let renderedResult = try compare(
            left: html(["A", "b"]),
            middle: html(["a", "b"]),
            right: html(["a", "B"]),
            mode: .renderedText
        )
        XCTAssertEqual(renderedResult.outcome, .merged)
        XCTAssertEqual(renderedResult.automaticallyMergedComparisonText, "A\nB\n")
        XCTAssertFalse(try XCTUnwrap(renderedResult.automaticallyMergedComparisonText).contains("<p>"))
    }

    func testResultPreservesMetadataAndMapsNormalizedAndSourceRanges() throws {
        let context = ThreeWayWebPageComparisonContext(identifier: "rendered-fixture", generation: 42)
        let middleHTML = "<div>alpha</div><p>beta</p>"
        let leftHTML = "<div>alpha</div><p>BETA</p>"
        let leftMetadata = [
            ThreeWayWebPageComparisonMetadataEntry(key: "path", value: "/left.html"),
            ThreeWayWebPageComparisonMetadataEntry(key: "etag", value: "left-v2")
        ]
        let middleMetadata = [ThreeWayWebPageComparisonMetadataEntry(key: "path", value: "/base.html")]
        let rightMetadata = [ThreeWayWebPageComparisonMetadataEntry(key: "path", value: "/right.html")]
        let left = try snapshot(
            leftHTML,
            source: .left,
            mode: .renderedText,
            context: context,
            metadata: leftMetadata
        )
        let middle = try snapshot(
            middleHTML,
            source: .middle,
            mode: .renderedText,
            context: context,
            metadata: middleMetadata
        )
        let right = try snapshot(
            middleHTML,
            source: .right,
            mode: .renderedText,
            context: context,
            metadata: rightMetadata
        )

        let result = try ThreeWayWebPageComparison.compare(left: left, middle: middle, right: right)

        XCTAssertEqual(result.context, context)
        XCTAssertEqual(result.left.metadata, leftMetadata)
        XCTAssertEqual(result.middle.metadata, middleMetadata)
        XCTAssertEqual(result.right.metadata, rightMetadata)
        XCTAssertEqual(result.regions.map(\.id), [0, 1])
        XCTAssertEqual(result.regions.map(\.resolution), [.unchanged, .left])
        XCTAssertEqual(result.regions.map(\.automaticSource), [.middle, .left])
        XCTAssertEqual(result.regions.map(\.left.lineRange), [0..<1, 1..<2])
        XCTAssertEqual(result.regions.map(\.middle.lineRange), [0..<1, 1..<2])
        XCTAssertEqual(result.regions.map(\.right.lineRange), [0..<1, 1..<2])
        XCTAssertEqual(result.regions.map(\.left.normalizedUTF8Range), [0..<6, 6..<11])
        XCTAssertEqual(result.regions.map(\.middle.normalizedUTF8Range), [0..<6, 6..<11])
        XCTAssertEqual(result.regions.map(\.right.normalizedUTF8Range), [0..<6, 6..<11])
        XCTAssertEqual(result.regions.map(\.left.sourceUTF8Ranges), [[5..<10, 10..<16], [19..<23, 23..<27]])
        XCTAssertEqual(result.regions.map(\.middle.sourceUTF8Ranges), [[5..<10, 10..<16], [19..<23, 23..<27]])
        XCTAssertEqual(result.regions.map(\.right.sourceUTF8Ranges), [[5..<10, 10..<16], [19..<23, 23..<27]])
        XCTAssertEqual(result.differences.map(\.id), [1])
        XCTAssertEqual(result.conflicts, [])
    }

    func testExpectedContextRejectsEveryStaleSnapshotPosition() throws {
        let expected = ThreeWayWebPageComparisonContext(identifier: "page", generation: 8)
        let stale = ThreeWayWebPageComparisonContext(identifier: "page", generation: 7)

        for staleSource in ThreeWayWebPageComparisonSource.allCases {
            let left = try snapshot(
                "same",
                source: .left,
                mode: .source,
                context: staleSource == .left ? stale : expected
            )
            let middle = try snapshot(
                "same",
                source: .middle,
                mode: .source,
                context: staleSource == .middle ? stale : expected
            )
            let right = try snapshot(
                "same",
                source: .right,
                mode: .source,
                context: staleSource == .right ? stale : expected
            )

            XCTAssertThrowsError(
                try ThreeWayWebPageComparison.compare(
                    left: left,
                    middle: middle,
                    right: right,
                    options: ThreeWayWebPageComparisonOptions(expectedContext: expected)
                )
            ) { error in
                XCTAssertEqual(
                    error as? ThreeWayWebPageComparisonError,
                    .staleSnapshot(source: staleSource, expectedGeneration: 8, actualGeneration: 7)
                )
            }
        }
    }

    func testSnapshotPositionsAndSetsReportExactValidationMismatch() throws {
        let expected = ThreeWayWebPageComparisonContext(identifier: "page", generation: 8)
        let wrongSet = ThreeWayWebPageComparisonContext(identifier: "other", generation: 8)

        for position in ThreeWayWebPageComparisonSource.allCases {
            let actualSource: ThreeWayWebPageComparisonSource = position == .right ? .left : .right
            let left = try snapshot(
                "same",
                source: position == .left ? actualSource : .left,
                mode: .source,
                context: expected
            )
            let middle = try snapshot(
                "same",
                source: position == .middle ? actualSource : .middle,
                mode: .source,
                context: expected
            )
            let right = try snapshot(
                "same",
                source: position == .right ? actualSource : .right,
                mode: .source,
                context: expected
            )

            XCTAssertThrowsError(
                try ThreeWayWebPageComparison.compare(
                    left: left,
                    middle: middle,
                    right: right,
                    options: ThreeWayWebPageComparisonOptions(expectedContext: expected)
                )
            ) { error in
                XCTAssertEqual(
                    error as? ThreeWayWebPageComparisonError,
                    .mismatchedSource(expected: position, actual: actualSource)
                )
            }
        }

        for position in ThreeWayWebPageComparisonSource.allCases {
            let left = try snapshot(
                "same",
                source: .left,
                mode: .source,
                context: position == .left ? wrongSet : expected
            )
            let middle = try snapshot(
                "same",
                source: .middle,
                mode: .source,
                context: position == .middle ? wrongSet : expected
            )
            let right = try snapshot(
                "same",
                source: .right,
                mode: .source,
                context: position == .right ? wrongSet : expected
            )

            XCTAssertThrowsError(
                try ThreeWayWebPageComparison.compare(
                    left: left,
                    middle: middle,
                    right: right,
                    options: ThreeWayWebPageComparisonOptions(expectedContext: expected)
                )
            ) { error in
                XCTAssertEqual(
                    error as? ThreeWayWebPageComparisonError,
                    .mismatchedSnapshotSet(
                        source: position,
                        expectedIdentifier: "page",
                        actualIdentifier: "other"
                    )
                )
            }
        }
    }

    func testEmptyIdentifiersAndModesReportExactValidationMismatch() throws {
        let expected = ThreeWayWebPageComparisonContext(identifier: "page", generation: 8)
        let empty = ThreeWayWebPageComparisonContext(identifier: "", generation: 8)

        for position in ThreeWayWebPageComparisonSource.allCases {
            let left = try snapshot(
                "same",
                source: .left,
                mode: .source,
                context: position == .left ? empty : expected
            )
            let middle = try snapshot(
                "same",
                source: .middle,
                mode: .source,
                context: position == .middle ? empty : expected
            )
            let right = try snapshot(
                "same",
                source: .right,
                mode: .source,
                context: position == .right ? empty : expected
            )

            XCTAssertThrowsError(
                try ThreeWayWebPageComparison.compare(
                    left: left,
                    middle: middle,
                    right: right,
                    options: ThreeWayWebPageComparisonOptions(expectedContext: expected)
                )
            ) { error in
                XCTAssertEqual(
                    error as? ThreeWayWebPageComparisonError,
                    .invalidSnapshot(source: position, issue: .emptyContextIdentifier)
                )
            }
        }

        for position in [ThreeWayWebPageComparisonSource.left, .right] {
            let left = try snapshot(
                "same",
                source: .left,
                mode: position == .left ? .renderedText : .source,
                context: expected
            )
            let middle = try snapshot("same", source: .middle, mode: .source, context: expected)
            let right = try snapshot(
                "same",
                source: .right,
                mode: position == .right ? .renderedText : .source,
                context: expected
            )

            XCTAssertThrowsError(
                try ThreeWayWebPageComparison.compare(left: left, middle: middle, right: right)
            ) { error in
                XCTAssertEqual(
                    error as? ThreeWayWebPageComparisonError,
                    .mismatchedMode(source: position, expected: .source, actual: .renderedText)
                )
            }
        }
    }

    func testMiddleRevisionRejectsEachMismatchedSideWithoutAuthoritativeContext() throws {
        let middleContext = ThreeWayWebPageComparisonContext(identifier: "page", generation: 8)
        let staleContext = ThreeWayWebPageComparisonContext(identifier: "page", generation: 7)

        for staleSource in [ThreeWayWebPageComparisonSource.left, .right] {
            let left = try snapshot(
                "same",
                source: .left,
                mode: .source,
                context: staleSource == .left ? staleContext : middleContext
            )
            let middle = try snapshot("same", source: .middle, mode: .source, context: middleContext)
            let right = try snapshot(
                "same",
                source: .right,
                mode: .source,
                context: staleSource == .right ? staleContext : middleContext
            )

            XCTAssertThrowsError(
                try ThreeWayWebPageComparison.compare(left: left, middle: middle, right: right)
            ) { error in
                XCTAssertEqual(
                    error as? ThreeWayWebPageComparisonError,
                    .mismatchedSnapshotGeneration(
                        source: staleSource,
                        middleGeneration: 8,
                        actualGeneration: 7
                    )
                )
            }
        }
    }

    func testByteMetadataAndResultLimitsFailClosed() throws {
        let context = ThreeWayWebPageComparisonContext(identifier: "x", generation: 1)
        let left = try snapshot("<p>é</p>", source: .left, mode: .renderedText, context: context)
        let middle = try snapshot("<p>é</p>", source: .middle, mode: .renderedText, context: context)
        let right = try snapshot("<p>é</p>", source: .right, mode: .renderedText, context: context)
        let normalizedByteCount = left.normalizedText.utf8.count

        XCTAssertEqual(normalizedByteCount, 3)
        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: left,
                middle: middle,
                right: right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(
                        maximumNormalizedInputBytesPerSnapshot: normalizedByteCount - 1
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .normalizedInputTooLarge(source: .left, maximumBytes: normalizedByteCount - 1)
            )
        }

        let exactByteResult = try ThreeWayWebPageComparison.compare(
            left: left,
            middle: middle,
            right: right,
            options: ThreeWayWebPageComparisonOptions(
                limits: ThreeWayWebPageComparisonLimits(
                    maximumNormalizedInputBytesPerSnapshot: normalizedByteCount
                )
            )
        )
        XCTAssertEqual(exactByteResult.outcome, .equal)

        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: left,
                middle: middle,
                right: right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(
                        maximumTotalNormalizedInputBytes: normalizedByteCount * 3 - 1
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .totalNormalizedInputTooLarge(maximumBytes: normalizedByteCount * 3 - 1)
            )
        }

        let metadataLeft = try snapshot(
            "<p>é</p>",
            source: .left,
            mode: .renderedText,
            context: context,
            metadata: [ThreeWayWebPageComparisonMetadataEntry(key: "path", value: "left")]
        )
        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: metadataLeft,
                middle: middle,
                right: right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(maximumMetadataEntriesPerSnapshot: 0)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .tooManyMetadataEntries(source: .left, maximumEntries: 0)
            )
        }

        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: left,
                middle: middle,
                right: right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(maximumResultRegions: 0)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .tooManyResultRegions(maximumRegions: 0)
            )
        }

        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: left,
                middle: middle,
                right: right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(maximumMappedSegments: 0)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .tooManyMappedSegments(maximumSegments: 0)
            )
        }
    }

    func testRemainingSnapshotAndMergeLimitsReportExactFailures() throws {
        let sourceInputs = try snapshots(
            left: "<p>left</p>",
            middle: "<p>middle</p>",
            right: "<p>right</p>",
            mode: .source
        )
        let leftSourceBytes = sourceInputs.left.document.sourceUTF8ByteCount

        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: sourceInputs.left,
                middle: sourceInputs.middle,
                right: sourceInputs.right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(
                        maximumSourceInputBytesPerSnapshot: leftSourceBytes - 1
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .sourceInputTooLarge(source: .left, maximumBytes: leftSourceBytes - 1)
            )
        }

        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: sourceInputs.left,
                middle: sourceInputs.middle,
                right: sourceInputs.right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(maximumTokenCountPerSnapshot: 2)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .tooManyTokens(source: .left, maximumTokens: 2)
            )
        }

        let attributedInputs = try snapshots(
            left: "<p id=left>value</p>",
            middle: "<p id=middle>value</p>",
            right: "<p id=right>value</p>",
            mode: .renderedText
        )
        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: attributedInputs.left,
                middle: attributedInputs.middle,
                right: attributedInputs.right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(maximumAttributeCountPerSnapshot: 0)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .tooManyAttributes(source: .left, maximumAttributes: 0)
            )
        }

        let metadataContext = ThreeWayWebPageComparisonContext(identifier: "é", generation: 1)
        let metadataEntry = ThreeWayWebPageComparisonMetadataEntry(key: "鍵", value: "🙂")
        let metadataLeft = try snapshot(
            "<p>value</p>",
            source: .left,
            mode: .renderedText,
            context: metadataContext,
            metadata: [metadataEntry]
        )
        let metadataMiddle = try snapshot(
            "<p>value</p>",
            source: .middle,
            mode: .renderedText,
            context: metadataContext
        )
        let metadataRight = try snapshot(
            "<p>value</p>",
            source: .right,
            mode: .renderedText,
            context: metadataContext
        )
        let metadataByteCount = metadataContext.identifier.utf8.count * 4 + metadataEntry.key.utf8.count + metadataEntry.value.utf8.count
        XCTAssertEqual(metadataByteCount, 15)
        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: metadataLeft,
                middle: metadataMiddle,
                right: metadataRight,
                options: ThreeWayWebPageComparisonOptions(
                    expectedContext: metadataContext,
                    limits: ThreeWayWebPageComparisonLimits(maximumMetadataBytes: 14)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .metadataTooLarge(maximumBytes: 14)
            )
        }
        let exactMetadataResult = try ThreeWayWebPageComparison.compare(
            left: metadataLeft,
            middle: metadataMiddle,
            right: metadataRight,
            options: ThreeWayWebPageComparisonOptions(
                expectedContext: metadataContext,
                limits: ThreeWayWebPageComparisonLimits(maximumMetadataBytes: 15)
            )
        )
        XCTAssertEqual(exactMetadataResult.outcome, .equal)

        let multilineInputs = try snapshots(
            left: html(["one", "two"]),
            middle: html(["one", "two"]),
            right: html(["one", "two"]),
            mode: .renderedText
        )
        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: multilineInputs.left,
                middle: multilineInputs.middle,
                right: multilineInputs.right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(maximumInputLinesPerSnapshot: 1)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .tooManyInputLines(source: .middle, maximumLines: 1)
            )
        }

        let outputText = multilineInputs.left.normalizedText
        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: multilineInputs.left,
                middle: multilineInputs.middle,
                right: multilineInputs.right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(
                        maximumOutputBytes: outputText.utf8.count - 1
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .outputTooLarge(maximumBytes: outputText.utf8.count - 1)
            )
        }
        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: multilineInputs.left,
                middle: multilineInputs.middle,
                right: multilineInputs.right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(maximumOutputLines: 1)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .tooManyOutputLines(maximumLines: 1)
            )
        }

        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: multilineInputs.left,
                middle: multilineInputs.middle,
                right: multilineInputs.right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(maximumWorkUnits: -1)
                )
            )
        ) { error in
            XCTAssertEqual(error as? ThreeWayWebPageComparisonError, .invalidLimits)
        }
    }

    func testEveryMalformedSnapshotIssueFailsClosedWithExactSourceAndIssue() throws {
        struct Fixture {
            let name: String
            let document: WebPageComparisonDocument
            let metadata: [ThreeWayWebPageComparisonMetadataEntry]
            let issue: ThreeWayWebPageComparisonSnapshotIssue
        }

        func document(
            mode: WebPageComparisonMode = .renderedText,
            text: String = "",
            segments: [WebPageComparisonSegment] = [],
            sourceByteCount: Int = 0,
            tokenCount: Int = 0,
            attributeCount: Int = 0
        ) -> WebPageComparisonDocument {
            WebPageComparisonDocument(
                mode: mode,
                comparisonText: text,
                segments: segments,
                sourceUTF8ByteCount: sourceByteCount,
                tokenCount: tokenCount,
                attributeCount: attributeCount
            )
        }

        let textSegment = WebPageComparisonSegment(
            kind: .text,
            sourceUTF8Range: 0..<1,
            outputUTF8Range: 0..<1
        )
        let fixtures = [
            Fixture(
                name: "negative source byte count",
                document: document(sourceByteCount: -1),
                metadata: [],
                issue: .negativeSourceByteCount
            ),
            Fixture(
                name: "negative token count",
                document: document(tokenCount: -1),
                metadata: [],
                issue: .negativeTokenCount
            ),
            Fixture(
                name: "negative attribute count",
                document: document(attributeCount: -1),
                metadata: [],
                issue: .negativeAttributeCount
            ),
            Fixture(
                name: "duplicate metadata key",
                document: document(),
                metadata: [
                    ThreeWayWebPageComparisonMetadataEntry(key: "same", value: "one"),
                    ThreeWayWebPageComparisonMetadataEntry(key: "same", value: "two")
                ],
                issue: .duplicateMetadataKey("same")
            ),
            Fixture(
                name: "invalid segment source range",
                document: document(
                    text: "x",
                    segments: [
                        WebPageComparisonSegment(
                            kind: .text,
                            sourceUTF8Range: 0..<2,
                            outputUTF8Range: 0..<1
                        )
                    ],
                    sourceByteCount: 1,
                    tokenCount: 1
                ),
                metadata: [],
                issue: .invalidSegmentSourceRange(index: 0)
            ),
            Fixture(
                name: "invalid segment output range",
                document: document(
                    text: "x",
                    segments: [
                        WebPageComparisonSegment(
                            kind: .text,
                            sourceUTF8Range: 0..<1,
                            outputUTF8Range: 0..<2
                        )
                    ],
                    sourceByteCount: 1,
                    tokenCount: 1
                ),
                metadata: [],
                issue: .invalidSegmentOutputRange(index: 0)
            ),
            Fixture(
                name: "nonmonotonic segment source range",
                document: document(
                    text: "xy",
                    segments: [
                        WebPageComparisonSegment(
                            kind: .text,
                            sourceUTF8Range: 1..<2,
                            outputUTF8Range: 0..<1
                        ),
                        WebPageComparisonSegment(
                            kind: .text,
                            sourceUTF8Range: 0..<1,
                            outputUTF8Range: 1..<2
                        )
                    ],
                    sourceByteCount: 2,
                    tokenCount: 2
                ),
                metadata: [],
                issue: .nonmonotonicSegmentSourceRange(index: 1)
            ),
            Fixture(
                name: "noncontiguous segment output",
                document: document(
                    text: "xy",
                    segments: [
                        textSegment,
                        WebPageComparisonSegment(
                            kind: .text,
                            sourceUTF8Range: 1..<2,
                            outputUTF8Range: 0..<1
                        )
                    ],
                    sourceByteCount: 2,
                    tokenCount: 2
                ),
                metadata: [],
                issue: .noncontiguousSegmentOutput(index: 1)
            ),
            Fixture(
                name: "incomplete segment output",
                document: document(
                    text: "xy",
                    segments: [textSegment],
                    sourceByteCount: 1,
                    tokenCount: 1
                ),
                metadata: [],
                issue: .incompleteSegmentOutput
            ),
            Fixture(
                name: "invalid source-mode segment",
                document: document(
                    mode: .source,
                    text: "x",
                    segments: [
                        WebPageComparisonSegment(
                            kind: .renderedBoundary,
                            sourceUTF8Range: 0..<1,
                            outputUTF8Range: 0..<1
                        )
                    ],
                    sourceByteCount: 1,
                    tokenCount: 1
                ),
                metadata: [],
                issue: .invalidSourceModeSegment(index: 0)
            ),
            Fixture(
                name: "invalid rendered-mode segment",
                document: document(
                    text: "x",
                    segments: [
                        WebPageComparisonSegment(
                            kind: .rawText,
                            sourceUTF8Range: 0..<1,
                            outputUTF8Range: 0..<1
                        )
                    ],
                    sourceByteCount: 1,
                    tokenCount: 1
                ),
                metadata: [],
                issue: .invalidRenderedModeSegment(index: 0)
            ),
            Fixture(
                name: "invalid source-mode counts",
                document: document(
                    mode: .source,
                    text: "x",
                    segments: [textSegment],
                    sourceByteCount: 1,
                    tokenCount: 2
                ),
                metadata: [],
                issue: .invalidSourceModeCounts
            ),
            Fixture(
                name: "rendered segment count exceeds token count",
                document: document(
                    text: "x",
                    segments: [textSegment],
                    sourceByteCount: 1,
                    tokenCount: 0
                ),
                metadata: [],
                issue: .renderedSegmentCountExceedsTokenCount
            )
        ]

        for fixture in fixtures {
            let validDocument = document(mode: fixture.document.mode)
            let left = ThreeWayWebPageComparisonSnapshot(
                source: .left,
                context: defaultContext,
                document: fixture.document,
                metadata: fixture.metadata
            )
            let middle = ThreeWayWebPageComparisonSnapshot(
                source: .middle,
                context: defaultContext,
                document: validDocument
            )
            let right = ThreeWayWebPageComparisonSnapshot(
                source: .right,
                context: defaultContext,
                document: validDocument
            )

            XCTAssertThrowsError(
                try ThreeWayWebPageComparison.compare(left: left, middle: middle, right: right),
                fixture.name
            ) { error in
                XCTAssertEqual(
                    error as? ThreeWayWebPageComparisonError,
                    .invalidSnapshot(source: .left, issue: fixture.issue),
                    fixture.name
                )
            }
        }
    }

    func testWorkLimitIncludesIncrementalUTF8Scanning() throws {
        let comparisonText = String(repeating: "é", count: 4_097)
        let byteCount = comparisonText.utf8.count
        let document = WebPageComparisonDocument(
            mode: .renderedText,
            comparisonText: comparisonText,
            segments: [
                WebPageComparisonSegment(
                    kind: .text,
                    sourceUTF8Range: 0..<1,
                    outputUTF8Range: 0..<byteCount
                )
            ],
            sourceUTF8ByteCount: 1,
            tokenCount: 1,
            attributeCount: 0
        )
        let snapshots = snapshots(document: document)

        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: snapshots.left,
                middle: snapshots.middle,
                right: snapshots.right,
                options: ThreeWayWebPageComparisonOptions(
                    limits: ThreeWayWebPageComparisonLimits(maximumWorkUnits: 4_096)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreeWayWebPageComparisonError,
                .workLimitExceeded(maximumWorkUnits: 4_096)
            )
        }
    }

    func testCancellationStopsBeforeNativeMergeAndNativeFailureIsMapped() async throws {
        let inputs = try snapshots(
            left: "alpha\nleft\n",
            middle: "alpha\nmiddle\n",
            right: "alpha\nright\n",
            mode: .source
        )
        let cancelledTask = Task { () -> (ThreeWayWebPageComparisonError?, Int, Int) in
            mmx_test_disable_allocation_failures()
            defer { mmx_test_disable_allocation_failures() }
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ThreeWayWebPageComparison.compare(
                    left: inputs.left,
                    middle: inputs.middle,
                    right: inputs.right
                )
                return (
                    nil,
                    Int(mmx_test_allocation_attempt_count()),
                    Int(mmx_test_outstanding_allocation_count())
                )
            } catch {
                return (
                    error as? ThreeWayWebPageComparisonError,
                    Int(mmx_test_allocation_attempt_count()),
                    Int(mmx_test_outstanding_allocation_count())
                )
            }
        }

        let cancelled = await cancelledTask.value
        XCTAssertEqual(cancelled.0, .cancelled)
        XCTAssertEqual(cancelled.1, 0)
        XCTAssertEqual(cancelled.2, 0)

        mmx_test_disable_allocation_failures()
        mmx_test_fail_allocation_after(0)
        defer { mmx_test_disable_allocation_failures() }
        XCTAssertThrowsError(
            try ThreeWayWebPageComparison.compare(
                left: inputs.left,
                middle: inputs.middle,
                right: inputs.right
            )
        ) { error in
            guard let comparisonError = error as? ThreeWayWebPageComparisonError,
                case .lineDiff(.nativeEngineFailure) = comparisonError
            else {
                return XCTFail("Expected mapped native merge failure, got \(error)")
            }
        }
        XCTAssertGreaterThan(mmx_test_allocation_attempt_count(), 0)
        XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
    }

    func testAmbiguousRepeatedLinesHaveAlgorithmSpecificGoldenRanges() throws {
        struct Golden {
            let algorithm: DiffAlgorithm
            let resolutions: [ThreeWayWebPageComparisonResolution]
            let leftRanges: [Range<Int>]
            let middleRanges: [Range<Int>]
            let rightRanges: [Range<Int>]
        }

        let base = ["A", "B", "E", "B", "F", "B", "B", "C", "F", "B", "E", "E"]
            .joined(separator: "\n")
        let edited = ["E", "D", "D", "D", "E", "B", "C", "B", "B", "F", "D", "E"]
            .joined(separator: "\n")
        let inputs = try snapshots(
            left: edited,
            middle: base,
            right: base,
            mode: .source
        )
        let pairedResolutions: [ThreeWayWebPageComparisonResolution] = [
            .left, .unchanged, .left, .unchanged, .left, .unchanged, .left, .unchanged
        ]
        let goldens = [
            Golden(
                algorithm: .default,
                resolutions: pairedResolutions,
                leftRanges: [0..<4, 4..<6, 6..<7, 7..<9, 9..<9, 9..<10, 10..<11, 11..<12],
                middleRanges: [0..<2, 2..<4, 4..<5, 5..<7, 7..<8, 8..<9, 9..<11, 11..<12],
                rightRanges: [0..<2, 2..<4, 4..<5, 5..<7, 7..<8, 8..<9, 9..<11, 11..<12]
            ),
            Golden(
                algorithm: .minimal,
                resolutions: pairedResolutions,
                leftRanges: [0..<4, 4..<6, 6..<7, 7..<9, 9..<9, 9..<10, 10..<11, 11..<12],
                middleRanges: [0..<2, 2..<4, 4..<5, 5..<7, 7..<8, 8..<9, 9..<11, 11..<12],
                rightRanges: [0..<2, 2..<4, 4..<5, 5..<7, 7..<8, 8..<9, 9..<11, 11..<12]
            ),
            Golden(
                algorithm: .patience,
                resolutions: pairedResolutions,
                leftRanges: [0..<0, 0..<1, 1..<5, 5..<7, 7..<9, 9..<10, 10..<11, 11..<12],
                middleRanges: [0..<2, 2..<3, 3..<6, 6..<8, 8..<8, 8..<9, 9..<11, 11..<12],
                rightRanges: [0..<2, 2..<3, 3..<6, 6..<8, 8..<8, 8..<9, 9..<11, 11..<12]
            ),
            Golden(
                algorithm: .histogram,
                resolutions: pairedResolutions,
                leftRanges: [0..<0, 0..<1, 1..<5, 5..<7, 7..<7, 7..<8, 8..<11, 11..<12],
                middleRanges: [0..<2, 2..<3, 3..<6, 6..<8, 8..<9, 9..<10, 10..<11, 11..<12],
                rightRanges: [0..<2, 2..<3, 3..<6, 6..<8, 8..<9, 9..<10, 10..<11, 11..<12]
            ),
            Golden(
                algorithm: .none,
                resolutions: [.left, .unchanged, .left, .unchanged],
                leftRanges: [0..<5, 5..<6, 6..<11, 11..<12],
                middleRanges: [0..<5, 5..<6, 6..<11, 11..<12],
                rightRanges: [0..<5, 5..<6, 6..<11, 11..<12]
            )
        ]
        for golden in goldens {
            for iteration in 0..<8 {
                let result = try ThreeWayWebPageComparison.compare(
                    left: inputs.left,
                    middle: inputs.middle,
                    right: inputs.right,
                    options: ThreeWayWebPageComparisonOptions(diffAlgorithm: golden.algorithm)
                )
                let message = "Algorithm: \(golden.algorithm), iteration: \(iteration)"
                XCTAssertEqual(result.outcome, .leftOnly, message)
                XCTAssertEqual(result.regions.map(\.resolution), golden.resolutions, message)
                XCTAssertEqual(result.regions.map(\.left.lineRange), golden.leftRanges, message)
                XCTAssertEqual(result.regions.map(\.middle.lineRange), golden.middleRanges, message)
                XCTAssertEqual(result.regions.map(\.right.lineRange), golden.rightRanges, message)
            }
        }
    }

    private let defaultContext = ThreeWayWebPageComparisonContext(
        identifier: "three-way-web-test",
        generation: 1
    )

    private func compare(
        left: String,
        middle: String,
        right: String,
        mode: WebPageComparisonMode
    ) throws -> ThreeWayWebPageComparisonResult {
        let inputs = try snapshots(left: left, middle: middle, right: right, mode: mode)
        return try ThreeWayWebPageComparison.compare(
            left: inputs.left,
            middle: inputs.middle,
            right: inputs.right
        )
    }

    private func snapshots(
        left: String,
        middle: String,
        right: String,
        mode: WebPageComparisonMode
    ) throws -> (
        left: ThreeWayWebPageComparisonSnapshot,
        middle: ThreeWayWebPageComparisonSnapshot,
        right: ThreeWayWebPageComparisonSnapshot
    ) {
        (
            try snapshot(left, source: .left, mode: mode, context: defaultContext),
            try snapshot(middle, source: .middle, mode: mode, context: defaultContext),
            try snapshot(right, source: .right, mode: mode, context: defaultContext)
        )
    }

    private func snapshots(document: WebPageComparisonDocument) -> (
        left: ThreeWayWebPageComparisonSnapshot,
        middle: ThreeWayWebPageComparisonSnapshot,
        right: ThreeWayWebPageComparisonSnapshot
    ) {
        (
            ThreeWayWebPageComparisonSnapshot(
                source: .left,
                context: defaultContext,
                document: document
            ),
            ThreeWayWebPageComparisonSnapshot(
                source: .middle,
                context: defaultContext,
                document: document
            ),
            ThreeWayWebPageComparisonSnapshot(
                source: .right,
                context: defaultContext,
                document: document
            )
        )
    }

    private func snapshot(
        _ html: String,
        source: ThreeWayWebPageComparisonSource,
        mode: WebPageComparisonMode,
        context: ThreeWayWebPageComparisonContext,
        metadata: [ThreeWayWebPageComparisonMetadataEntry] = []
    ) throws -> ThreeWayWebPageComparisonSnapshot {
        let normalized = try WebPageComparison.compare(
            left: html,
            right: html,
            options: WebPageComparisonOptions(mode: mode)
        ).left
        return ThreeWayWebPageComparisonSnapshot(
            source: source,
            context: context,
            document: normalized,
            metadata: metadata
        )
    }

    private func html(_ lines: [String]) -> String {
        lines.map { "<p>\($0)</p>" }.joined()
    }

}
