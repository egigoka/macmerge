import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class DirectoryResultsTests: XCTestCase {
    private static let invalidInitializerCaseEnvironment =
        "MACMERGE_DIRECTORY_RESULTS_INVALID_INITIALIZER_CASE"
    private static let invalidInitializerMarkerEnvironment =
        "MACMERGE_DIRECTORY_RESULTS_INVALID_INITIALIZER_MARKER"
    private static let nonregularOpenChildEnvironment =
        "MACMERGE_DIRECTORY_RESULTS_NONREGULAR_OPEN_CHILD"

    func testIDRemainsStableWhenEitherOrBothSidesArePresent() {
        let leftOnly = result(path: "folder/item.txt", sides: .left, status: .leftOnly)
        let rightOnly = result(path: "folder/item.txt", sides: .right, status: .rightOnly)
        let both = result(path: "folder/item.txt", status: .different)
        let distinct = result(path: "folder/other.txt")

        XCTAssertEqual(leftOnly.id, rightOnly.id)
        XCTAssertEqual(rightOnly.id, both.id)
        XCTAssertNotEqual(both.id, distinct.id)
        XCTAssertEqual(Set([leftOnly.id, rightOnly.id, both.id]).count, 1)
        XCTAssertEqual(Set([leftOnly.id, rightOnly.id, both.id, distinct.id]).count, 2)
        XCTAssertEqual(leftOnly.id.relativePath, "folder/item.txt")
    }

    func testHiddenStatusIncludesDotPathComponentsAndExplicitMetadata() {
        XCTAssertTrue(metadata(".git/config", isHidden: false).isHidden)
        XCTAssertTrue(metadata("folder/.cache/item", isHidden: false).isHidden)
        XCTAssertTrue(metadata("visible/item", isHidden: true).isHidden)
        XCTAssertFalse(metadata("visible/item", isHidden: false).isHidden)
        XCTAssertFalse(metadata("folder/../item", isHidden: false).isHidden)
    }

    func testMetadataCanonicalizesNonFiniteModificationDates() {
        let finiteDate = Date(timeIntervalSinceReferenceDate: 123)
        XCTAssertEqual(metadata("finite", modificationDate: finiteDate).modificationDate, finiteDate)

        for interval in [Double.nan, .infinity, -.infinity] {
            let entry = metadata(
                "non-finite",
                modificationDate: Date(timeIntervalSinceReferenceDate: interval)
            )
            XCTAssertNil(entry.modificationDate)
            XCTAssertEqual(entry, entry)
            XCTAssertEqual(Set([entry, entry]).count, 1)
        }
    }

    func testInitializerAcceptsOnlyValidStatusSideAndKindCombinations() throws {
        if let invalidCase = ProcessInfo.processInfo.environment[
            Self.invalidInitializerCaseEnvironment
        ] {
            markInvalidInitializerChildAsStarted()
            constructInvalidResult(for: invalidCase)
            XCTFail("Invalid directory result was accepted: \(invalidCase)")
            return
        }

        for status in DirectoryComparisonStatus.allCases {
            let validShape = validShape(for: status)
            XCTAssertEqual(matrixResult(status: status, shape: validShape).status, status)

            for shape in ResultShape.allCases where shape != validShape {
                try assertInitializerRejects(matrixCase(status: status, shape: shape))
            }
        }
    }

    func testVisibleResultsUsesStableOrderedMultiDescriptorSort() {
        let firstTie = result(path: "z-first.txt", status: .identical, leftSize: 10)
        let differentSmall = result(path: "different-small.txt", status: .different, leftSize: 1)
        let secondTie = result(path: "a-second.txt", status: .identical, leftSize: 10)
        let identicalSmall = result(path: "identical-small.txt", status: .identical, leftSize: 5)
        let differentLarge = result(path: "different-large.txt", status: .different, leftSize: 8)
        let expected = [firstTie, secondTie, identicalSmall, differentLarge, differentSmall]
        let results = DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/left"),
            rightRoot: URL(fileURLWithPath: "/right"),
            results: [firstTie, differentSmall, secondTie, identicalSmall, differentLarge],
            sortDescriptors: [
                DirectoryResultSortDescriptor(key: .status),
                DirectoryResultSortDescriptor(key: .leftSize, order: .descending)
            ]
        )

        XCTAssertEqual(results.visibleResults, expected)
        XCTAssertEqual(results.visibleResults, expected)
    }

    func testVisibleResultsUsesRawUTF8TieBreakForCaseEquivalentPaths() {
        let uppercase = result(path: "A.txt")
        let lowercase = result(path: "a.txt")

        for input in [[uppercase, lowercase], [lowercase, uppercase]] {
            let results = DirectoryResults(
                leftRoot: URL(fileURLWithPath: "/left"),
                rightRoot: URL(fileURLWithPath: "/right"),
                results: input
            )

            XCTAssertEqual(results.visibleResults, [uppercase, lowercase])
            XCTAssertEqual(results.visibleResults, [uppercase, lowercase])
        }
    }

    func testVisibleResultsSortsLeftAndRightModificationDatesDeterministically() {
        let early = Date(timeIntervalSinceReferenceDate: 100)
        let equal = Date(timeIntervalSinceReferenceDate: 200)
        let late = Date(timeIntervalSinceReferenceDate: 300)
        let leftFirstEqual = result(
            path: "z-left-first-equal.txt",
            leftModificationDate: equal,
            rightModificationDate: late
        )
        let leftNil = result(
            path: "left-nil.txt",
            rightModificationDate: equal
        )
        let leftLate = result(
            path: "left-late.txt",
            leftModificationDate: late,
            rightModificationDate: early
        )
        let leftSecondEqual = result(
            path: "a-left-second-equal.txt",
            leftModificationDate: equal
        )
        let leftEarly = result(
            path: "left-early.txt",
            leftModificationDate: early,
            rightModificationDate: late
        )
        let rightFirstEqual = result(
            path: "z-right-first-equal.txt",
            leftModificationDate: late,
            rightModificationDate: equal
        )
        let rightNil = result(
            path: "right-nil.txt",
            leftModificationDate: equal
        )
        let rightLate = result(
            path: "right-late.txt",
            leftModificationDate: early,
            rightModificationDate: late
        )
        let rightSecondEqual = result(
            path: "a-right-second-equal.txt",
            rightModificationDate: equal
        )
        let rightEarly = result(
            path: "right-early.txt",
            leftModificationDate: late,
            rightModificationDate: early
        )
        let fixtures:
            [(
                key: DirectoryResultSortKey,
                input: [DirectoryResult],
                ascending: [DirectoryResult],
                descending: [DirectoryResult]
            )] = [
                (
                    .leftModificationDate,
                    [leftFirstEqual, leftNil, leftLate, leftSecondEqual, leftEarly],
                    [leftEarly, leftFirstEqual, leftSecondEqual, leftLate, leftNil],
                    [leftNil, leftLate, leftFirstEqual, leftSecondEqual, leftEarly]
                ),
                (
                    .rightModificationDate,
                    [rightFirstEqual, rightNil, rightLate, rightSecondEqual, rightEarly],
                    [rightEarly, rightFirstEqual, rightSecondEqual, rightLate, rightNil],
                    [rightNil, rightLate, rightFirstEqual, rightSecondEqual, rightEarly]
                )
            ]

        for fixture in fixtures {
            let ascending = DirectoryResults(
                leftRoot: URL(fileURLWithPath: "/left"),
                rightRoot: URL(fileURLWithPath: "/right"),
                results: fixture.input,
                sortDescriptors: [DirectoryResultSortDescriptor(key: fixture.key)]
            )
            let descending = DirectoryResults(
                leftRoot: URL(fileURLWithPath: "/left"),
                rightRoot: URL(fileURLWithPath: "/right"),
                results: fixture.input,
                sortDescriptors: [
                    DirectoryResultSortDescriptor(key: fixture.key, order: .descending)
                ]
            )

            XCTAssertEqual(ascending.visibleResults, fixture.ascending)
            XCTAssertEqual(ascending.visibleResults, fixture.ascending)
            XCTAssertEqual(descending.visibleResults, fixture.descending)
            XCTAssertEqual(descending.visibleResults, fixture.descending)
        }
    }

    func testVisibleResultsPreservesAdjacentSubsecondModificationDates() {
        let earlierInterval: TimeInterval = 100.125
        let laterInterval = earlierInterval.nextUp
        let earlierDate = Date(timeIntervalSinceReferenceDate: earlierInterval)
        let laterDate = Date(timeIntervalSinceReferenceDate: laterInterval)

        for key in [
            DirectoryResultSortKey.leftModificationDate,
            .rightModificationDate
        ] {
            let earlier = result(
                path: "earlier-\(key).txt",
                leftModificationDate: key == .leftModificationDate ? earlierDate : nil,
                rightModificationDate: key == .rightModificationDate ? earlierDate : nil
            )
            let later = result(
                path: "later-\(key).txt",
                leftModificationDate: key == .leftModificationDate ? laterDate : nil,
                rightModificationDate: key == .rightModificationDate ? laterDate : nil
            )
            let ascending = DirectoryResults(
                leftRoot: URL(fileURLWithPath: "/left"),
                rightRoot: URL(fileURLWithPath: "/right"),
                results: [later, earlier],
                sortDescriptors: [DirectoryResultSortDescriptor(key: key)]
            )
            let descending = DirectoryResults(
                leftRoot: URL(fileURLWithPath: "/left"),
                rightRoot: URL(fileURLWithPath: "/right"),
                results: [earlier, later],
                sortDescriptors: [
                    DirectoryResultSortDescriptor(key: key, order: .descending)
                ]
            )

            XCTAssertEqual(ascending.visibleResults, [earlier, later])
            XCTAssertEqual(descending.visibleResults, [later, earlier])
        }
    }

    func testFiltersCombineStatusPathKindAndHiddenRules() {
        let visibleDifferent = result(path: "Résumé.txt", status: .different)
        let hiddenLeftOnly = result(path: ".git/config", sides: .left, status: .leftOnly)
        let typeMismatch = DirectoryResult(
            left: metadata("Mixed", kind: .directory),
            right: metadata("Mixed", kind: .file),
            status: .typeMismatch
        )
        let rightLink = DirectoryResult(
            left: nil,
            right: metadata("shortcut", kind: .symbolicLink, isHidden: true),
            status: .rightOnly
        )

        let statusFilter = DirectoryResultFilter(statuses: [.different, .rightOnly])
        XCTAssertTrue(statusFilter.matches(visibleDifferent))
        XCTAssertTrue(statusFilter.matches(rightLink))
        XCTAssertFalse(statusFilter.matches(hiddenLeftOnly))

        XCTAssertTrue(DirectoryResultFilter(pathQuery: "resume.TXT").matches(visibleDifferent))
        XCTAssertTrue(DirectoryResultFilter(kinds: [.directory]).matches(typeMismatch))
        XCTAssertTrue(DirectoryResultFilter(kinds: [.file]).matches(typeMismatch))
        XCTAssertTrue(DirectoryResultFilter(kinds: [.symbolicLink]).matches(rightLink))
        XCTAssertFalse(DirectoryResultFilter(kinds: [.directory]).matches(visibleDifferent))
        XCTAssertTrue(DirectoryResultFilter(hidden: .only).matches(hiddenLeftOnly))
        XCTAssertTrue(DirectoryResultFilter(hidden: .only).matches(rightLink))
        XCTAssertFalse(DirectoryResultFilter(hidden: .exclude).matches(hiddenLeftOnly))
        XCTAssertFalse(DirectoryResultFilter(hidden: .exclude).matches(rightLink))
        XCTAssertEqual(rightLink.kind, .symbolicLink)
        XCTAssertTrue(rightLink.isHidden)

        let statusNearMiss = result(path: "resume-status.txt", status: .identical)
        let pathNearMiss = result(path: "unrelated.txt", status: .different)
        let kindNearMiss = result(
            path: "resume-kind",
            status: .different,
            kind: .directory
        )
        let hiddenNearMiss = DirectoryResult(
            left: metadata("resume-hidden.txt"),
            right: metadata("resume-hidden.txt", isHidden: true),
            status: .different
        )
        let combinedFilter = DirectoryResultFilter(
            statuses: [.different, .typeMismatch],
            pathQuery: "resume",
            kinds: [.file],
            hidden: .exclude
        )
        let nearMisses = [statusNearMiss, pathNearMiss, kindNearMiss, hiddenNearMiss]
        XCTAssertTrue(combinedFilter.matches(visibleDifferent))
        for nearMiss in nearMisses {
            XCTAssertFalse(combinedFilter.matches(nearMiss), nearMiss.relativePath)
        }

        let combined = DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/left"),
            rightRoot: URL(fileURLWithPath: "/right"),
            results: nearMisses + [visibleDifferent],
            filter: combinedFilter
        )
        XCTAssertEqual(combined.visibleResults, [visibleDifferent])
    }

    func testSelectionPersistsAcrossFilteringAndSideChangesUntilIDDisappears() {
        let leftOnly = result(path: "selected.txt", sides: .left, status: .leftOnly)
        let other = result(path: "other.txt")
        let unavailable = DirectoryResult.ID(
            leftRelativePath: "unavailable.txt",
            rightRelativePath: nil
        )
        var results = DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/left"),
            rightRoot: URL(fileURLWithPath: "/right"),
            results: [leftOnly, other],
            selectedIDs: [leftOnly.id, unavailable]
        )

        XCTAssertEqual(results.selectedIDs, [leftOnly.id])
        results.filter = DirectoryResultFilter(statuses: [.identical])
        XCTAssertFalse(results.visibleResults.contains(leftOnly))
        XCTAssertEqual(results.selectedIDs, [leftOnly.id])

        let nowOnBothSides = result(path: "selected.txt", status: .different)
        results.replaceResults([other, nowOnBothSides])
        XCTAssertEqual(results.selectedIDs, [nowOnBothSides.id])
        XCTAssertEqual(results.selectedResults, [nowOnBothSides])

        results.replaceResults([other])
        XCTAssertTrue(results.selectedIDs.isEmpty)
    }

    func testReplacingSelectedOneSidedResultRemapsToUniqueSameSideRenamePair() {
        let leftOnly = result(path: "old-left.txt", sides: .left, status: .leftOnly)
        let leftRename = DirectoryResult(
            left: metadata("old-left.txt"),
            right: metadata("new-left.txt"),
            status: .identical
        )
        let samePathOnRight = result(
            path: "old-left.txt",
            sides: .right,
            status: .rightOnly
        )
        var leftResults = DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/left"),
            rightRoot: URL(fileURLWithPath: "/right"),
            results: [leftOnly],
            selectedIDs: [leftOnly.id]
        )

        leftResults.replaceResults([samePathOnRight, leftRename])
        XCTAssertEqual(leftResults.selectedIDs, [leftRename.id])
        XCTAssertEqual(leftResults.selectedResults, [leftRename])

        let rightOnly = result(path: "old-right.txt", sides: .right, status: .rightOnly)
        let rightRename = DirectoryResult(
            left: metadata("new-right.txt"),
            right: metadata("old-right.txt"),
            status: .identical
        )
        var rightResults = DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/left"),
            rightRoot: URL(fileURLWithPath: "/right"),
            results: [rightOnly],
            selectedIDs: [rightOnly.id]
        )

        rightResults.replaceResults([rightRename])
        XCTAssertEqual(rightResults.selectedIDs, [rightRename.id])
        XCTAssertEqual(rightResults.selectedResults, [rightRename])
    }

    func testReplacingSelectedOneSidedResultClearsAmbiguousRenameMatches() {
        let leftOnly = result(path: "old.txt", sides: .left, status: .leftOnly)
        let firstRename = DirectoryResult(
            left: metadata("old.txt"),
            right: metadata("new-first.txt"),
            status: .identical
        )
        let secondRename = DirectoryResult(
            left: metadata("old.txt"),
            right: metadata("new-second.txt"),
            status: .identical
        )
        let samePathOnRight = result(path: "old.txt", sides: .right, status: .rightOnly)
        var results = DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/left"),
            rightRoot: URL(fileURLWithPath: "/right"),
            results: [leftOnly],
            selectedIDs: [leftOnly.id]
        )

        results.replaceResults([samePathOnRight, firstRename, secondRename])

        XCTAssertTrue(results.selectedIDs.isEmpty)
        XCTAssertTrue(results.selectedResults.isEmpty)
    }

    func testSelectingUnavailableIDWithoutExtensionClearsFilteredSelection() {
        let selected = result(path: "selected.txt")
        let unavailable = result(path: "unavailable.txt").id
        var results = DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/left"),
            rightRoot: URL(fileURLWithPath: "/right"),
            results: [selected],
            filter: DirectoryResultFilter(statuses: [.different]),
            selectedIDs: [selected.id]
        )

        XCTAssertTrue(results.visibleResults.isEmpty)
        results.select(unavailable)
        XCTAssertTrue(results.selectedIDs.isEmpty)
    }

    func testSelectingUnavailableIDWithExtensionPreservesFilteredSelection() {
        let selected = result(path: "selected.txt")
        let unavailable = result(path: "unavailable.txt").id
        var results = DirectoryResults(
            leftRoot: URL(fileURLWithPath: "/left"),
            rightRoot: URL(fileURLWithPath: "/right"),
            results: [selected],
            filter: DirectoryResultFilter(statuses: [.different]),
            selectedIDs: [selected.id]
        )

        XCTAssertTrue(results.visibleResults.isEmpty)
        results.select(unavailable, extendingSelection: true)
        XCTAssertEqual(results.selectedIDs, [selected.id])
    }

    func testReadersProvideRepeatableOffsetIndependentAccessPinnedBeforeLeafReplacement() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try makeDirectory(named: "left", in: workspace)
        let rightRoot = try makeDirectory(named: "right", in: workspace)
        let leftLeaf = leftRoot.appending(path: "item.txt")
        let rightLeaf = rightRoot.appending(path: "item.txt")
        try Data("original left".utf8).write(to: leftLeaf)
        try Data("original right".utf8).write(to: rightLeaf)
        let item = result(path: "item.txt", status: .different)
        let results = DirectoryResults(leftRoot: leftRoot, rightRoot: rightRoot, results: [item])
        let pair = try XCTUnwrap(results.openableFilePair(for: item.id))

        try FileManager.default.moveItem(
            at: leftLeaf,
            to: workspace.appending(path: "original-left.txt")
        )
        try FileManager.default.moveItem(
            at: rightLeaf,
            to: workspace.appending(path: "original-right.txt")
        )
        try Data("replacement left".utf8).write(to: leftLeaf)
        try Data("replacement right".utf8).write(to: rightLeaf)

        var escapedReader: DirectoryFileReader?
        try pair.withReaders { left, right in
            escapedReader = left
            XCTAssertEqual(
                try text(left.readToEnd(maximumByteCount: 1_024)),
                "original left"
            )
            XCTAssertEqual(
                try text(left.readToEnd(maximumByteCount: 1_024)),
                "original left"
            )
            XCTAssertEqual(try text(left.read(upToCount: 8, atOffset: 9)), "left")
            XCTAssertEqual(
                try text(right.readToEnd(maximumByteCount: 1_024)),
                "original right"
            )
            XCTAssertEqual(
                try text(right.readToEnd(maximumByteCount: 1_024)),
                "original right"
            )
        }
        XCTAssertThrowsError(try escapedReader?.readToEnd(maximumByteCount: 1_024)) { error in
            XCTAssertEqual(error as? DirectoryFileReaderError, .inactive)
        }
        XCTAssertThrowsError(try escapedReader?.read(upToCount: 0)) { error in
            XCTAssertEqual(error as? DirectoryFileReaderError, .inactive)
        }
        var readerEscapedFromThrowingAccess: DirectoryFileReader?
        XCTAssertThrowsError(
            try pair.withReaders { left, _ in
                readerEscapedFromThrowingAccess = left
                throw ProbeError.expected
            }
        ) { error in
            XCTAssertEqual(error as? ProbeError, .expected)
        }
        XCTAssertThrowsError(
            try readerEscapedFromThrowingAccess?.readToEnd(maximumByteCount: 1_024)
        ) { error in
            XCTAssertEqual(error as? DirectoryFileReaderError, .inactive)
        }
        XCTAssertEqual(try read(pair), ["original left", "original right"])
        XCTAssertEqual(
            try read(XCTUnwrap(results.openableFilePair(for: item.id))),
            ["replacement left", "replacement right"]
        )
    }

    func testReadToEndAcceptsExactLimitAndRejectsOneByteOverAndNegativeLimit() throws {
        let workspace = try temporaryDirectory()
        let exactData = Data(repeating: 0x41, count: 64 * 1_024)
        let oneOverData = exactData + Data([0x42])
        let leftURL = workspace.appending(path: "exact.bin")
        let rightURL = workspace.appending(path: "one-over.bin")
        try exactData.write(to: leftURL)
        try oneOverData.write(to: rightURL)
        let pair = try DirectoryFilePair(leftURL: leftURL, rightURL: rightURL)

        try pair.withReaders { exact, oneOver in
            XCTAssertEqual(
                try exact.readToEnd(maximumByteCount: exactData.count),
                exactData
            )
            XCTAssertThrowsError(
                try oneOver.readToEnd(maximumByteCount: exactData.count)
            ) { error in
                XCTAssertEqual(
                    error as? DirectoryFileReaderError,
                    .fileTooLarge(maximumByteCount: exactData.count)
                )
            }
            XCTAssertThrowsError(try exact.readToEnd(maximumByteCount: -1)) { error in
                XCTAssertEqual(error as? DirectoryFileReaderError, .invalidReadRange)
            }
        }
    }

    func testReadToEndRejectsHugeSparseFileWithoutReadingOrAllocatingItsSize() throws {
        let workspace = try temporaryDirectory()
        let sparseURL = workspace.appending(path: "sparse.bin")
        let otherURL = workspace.appending(path: "other.bin")
        let descriptor = Darwin.open(
            sparseURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        let sparseSize: off_t = 1 << 40
        XCTAssertEqual(Darwin.ftruncate(descriptor, sparseSize), 0)
        XCTAssertEqual(Darwin.close(descriptor), 0)
        try Data([0]).write(to: otherURL)
        let pair = try DirectoryFilePair(leftURL: sparseURL, rightURL: otherURL)
        let maximumByteCount = 1 * 1_024 * 1_024

        try pair.withReaders { sparse, _ in
            XCTAssertThrowsError(
                try sparse.readToEnd(maximumByteCount: maximumByteCount)
            ) { error in
                XCTAssertEqual(
                    error as? DirectoryFileReaderError,
                    .fileTooLarge(maximumByteCount: maximumByteCount)
                )
            }
        }
    }

    func testReadToEndRejectsGrowthBeyondLimitAfterInitialSnapshot() throws {
        let workspace = try temporaryDirectory()
        let maximumByteCount = 64 * 1_024
        let leftURL = workspace.appending(path: "growing.bin")
        let rightURL = workspace.appending(path: "other.bin")
        try Data(repeating: 0x41, count: maximumByteCount).write(to: leftURL)
        try Data([0]).write(to: rightURL)
        let pair = try DirectoryFilePair(leftURL: leftURL, rightURL: rightURL)
        let growth = ReadGrowth(url: leftURL, data: Data([0x42]))

        try pair.withReaders { growing, _ in
            XCTAssertThrowsError(
                try DirectoryFileReader.$readObserver.withValue(
                    { growth.observe($0) },
                    operation: {
                        try growing.readToEnd(maximumByteCount: maximumByteCount)
                    }
                )
            ) { error in
                XCTAssertEqual(
                    error as? DirectoryFileReaderError,
                    .fileTooLarge(maximumByteCount: maximumByteCount)
                )
            }
        }
        XCTAssertTrue(growth.didGrow)
        XCTAssertNil(growth.error)
    }

    func testReadToEndSupportsRepeatedBoundedChunkedReadsAtIndependentOffsets() throws {
        let workspace = try temporaryDirectory()
        let byteCount = 3 * 64 * 1_024 + 17
        let data = Data((0..<byteCount).map { UInt8($0 % 251) })
        let leftURL = workspace.appending(path: "left.bin")
        let rightURL = workspace.appending(path: "right.bin")
        try data.write(to: leftURL)
        try data.write(to: rightURL)
        let pair = try DirectoryFilePair(leftURL: leftURL, rightURL: rightURL)
        let offset: UInt64 = 64 * 1_024 + 3
        let suffix = data.dropFirst(Int(offset))

        try pair.withReaders { left, right in
            for _ in 0..<3 {
                XCTAssertEqual(
                    try left.readToEnd(maximumByteCount: data.count),
                    data
                )
                XCTAssertEqual(
                    try left.readToEnd(
                        maximumByteCount: suffix.count,
                        fromOffset: offset
                    ),
                    Data(suffix)
                )
                XCTAssertEqual(
                    try right.readToEnd(maximumByteCount: data.count),
                    data
                )
            }
        }
    }

    func testNestedAndConcurrentPairAccessRejectsWithoutDeadlockAndAllowsLaterReads() throws {
        let workspace = try temporaryDirectory()
        let leftURL = workspace.appending(path: "left.txt")
        let rightURL = workspace.appending(path: "right.txt")
        let leftData = Data("left contents".utf8)
        let rightData = Data("right contents".utf8)
        try leftData.write(to: leftURL)
        try rightData.write(to: rightURL)
        let pair = try DirectoryFilePair(leftURL: leftURL, rightURL: rightURL)
        let outerEntered = DispatchSemaphore(value: 0)
        let releaseOuter = DispatchSemaphore(value: 0)
        let sameThreadRejected = DispatchSemaphore(value: 0)
        let sameThreadFailed = DispatchSemaphore(value: 0)
        let repeatedReadsWorked = DispatchSemaphore(value: 0)
        let outerFailed = DispatchSemaphore(value: 0)
        let crossThreadRejected = DispatchSemaphore(value: 0)
        let crossThreadFailed = DispatchSemaphore(value: 0)
        let outerFinished = DispatchGroup()
        let crossThreadFinished = DispatchGroup()

        outerFinished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { outerFinished.leave() }
            do {
                try pair.withReaders { left, right in
                    outerEntered.signal()
                    do {
                        _ = try pair.withReaders { _, _ in () }
                        sameThreadFailed.signal()
                    } catch DirectoryFilePairError.accessInProgress {
                        sameThreadRejected.signal()
                    } catch {
                        sameThreadFailed.signal()
                    }

                    do {
                        let reads = [
                            try left.readToEnd(maximumByteCount: 1_024),
                            try left.readToEnd(maximumByteCount: 1_024),
                            try right.readToEnd(maximumByteCount: 1_024),
                            try right.readToEnd(maximumByteCount: 1_024)
                        ]
                        if reads == [leftData, leftData, rightData, rightData] {
                            repeatedReadsWorked.signal()
                        } else {
                            outerFailed.signal()
                        }
                    } catch {
                        outerFailed.signal()
                    }

                    if releaseOuter.wait(timeout: .now() + .seconds(3)) != .success {
                        outerFailed.signal()
                    }
                }
            } catch {
                outerFailed.signal()
            }
        }
        defer {
            releaseOuter.signal()
            XCTAssertEqual(
                outerFinished.wait(timeout: .now() + .seconds(1)),
                .success,
                "outer access did not finish within cleanup bound"
            )
            XCTAssertEqual(
                crossThreadFinished.wait(timeout: .now() + .seconds(1)),
                .success,
                "concurrent access did not finish within cleanup bound"
            )
        }

        guard outerEntered.wait(timeout: .now() + .seconds(1)) == .success else {
            XCTFail("outer access did not start before deadline")
            return
        }
        XCTAssertEqual(
            sameThreadRejected.wait(timeout: .now() + .seconds(1)),
            .success,
            "same-thread nested access was not rejected"
        )
        XCTAssertEqual(sameThreadFailed.wait(timeout: .now()), .timedOut)
        XCTAssertEqual(
            repeatedReadsWorked.wait(timeout: .now() + .seconds(1)),
            .success,
            "repeated reads failed during active access"
        )

        crossThreadFinished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { crossThreadFinished.leave() }
            do {
                _ = try pair.withReaders { _, _ in () }
                crossThreadFailed.signal()
            } catch DirectoryFilePairError.accessInProgress {
                crossThreadRejected.signal()
            } catch {
                crossThreadFailed.signal()
            }
        }
        XCTAssertEqual(
            crossThreadFinished.wait(timeout: .now() + .seconds(1)),
            .success,
            "cross-thread access blocked instead of rejecting"
        )
        XCTAssertEqual(crossThreadRejected.wait(timeout: .now()), .success)
        XCTAssertEqual(crossThreadFailed.wait(timeout: .now()), .timedOut)

        releaseOuter.signal()
        guard outerFinished.wait(timeout: .now() + .seconds(1)) == .success else {
            XCTFail("outer access did not finish after release")
            return
        }
        XCTAssertEqual(outerFailed.wait(timeout: .now()), .timedOut)
        XCTAssertEqual(try read(pair), ["left contents", "right contents"])
        XCTAssertEqual(try read(pair), ["left contents", "right contents"])
    }

    func testOpenablePairRejectsLeafSymlinkSwappedImmediatelyBeforeLeafOpen() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try makeDirectory(named: "left", in: workspace)
        let rightRoot = try makeDirectory(named: "right", in: workspace)
        let outside = workspace.appending(path: "outside.txt")
        let leftLeaf = leftRoot.appending(path: "item.txt")
        let alternateLeaf = leftRoot.appending(path: "alternate.txt")
        try Data("outside".utf8).write(to: outside)
        try Data("inside".utf8).write(to: leftLeaf)
        try FileManager.default.createSymbolicLink(
            at: alternateLeaf,
            withDestinationURL: outside
        )
        try Data("right".utf8).write(to: rightRoot.appending(path: "item.txt"))
        let item = result(path: "item.txt", status: .different)
        let results = DirectoryResults(leftRoot: leftRoot, rightRoot: rightRoot, results: [item])
        let swap = CheckpointSwap(
            target: .beforeLeaf(side: .left, relativePath: "item.txt"),
            first: leftLeaf,
            second: alternateLeaf
        )
        defer { swap.restoreIfNeeded() }

        let pair = DirectoryFilePair.$openObserver.withValue(
            { swap.observe($0) },
            operation: { results.openableFilePair(for: item.id) }
        )

        XCTAssertEqual(swap.outcome, 0)
        XCTAssertNil(pair)
    }

    func testOpenablePairKeepsIntermediateDescriptorPinnedAcrossSymlinkSwap() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try makeDirectory(named: "left", in: workspace)
        let rightRoot = try makeDirectory(named: "right", in: workspace)
        let outside = try makeDirectory(named: "outside", in: workspace)
        let leftFolder = try makeDirectory(named: "folder", in: leftRoot)
        let rightFolder = try makeDirectory(named: "folder", in: rightRoot)
        let alternate = leftRoot.appending(path: "alternate", directoryHint: .isDirectory)
        try Data("inside".utf8).write(to: leftFolder.appending(path: "item.txt"))
        try Data("outside".utf8).write(to: outside.appending(path: "item.txt"))
        try Data("right".utf8).write(to: rightFolder.appending(path: "item.txt"))
        try FileManager.default.createSymbolicLink(at: alternate, withDestinationURL: outside)
        let item = result(path: "folder/item.txt", status: .different)
        let results = DirectoryResults(leftRoot: leftRoot, rightRoot: rightRoot, results: [item])
        let swap = CheckpointSwap(
            target: .openedIntermediate(
                side: .left,
                relativePath: "folder/item.txt",
                component: "folder"
            ),
            first: leftFolder,
            second: alternate
        )
        defer { swap.restoreIfNeeded() }

        let pair = DirectoryFilePair.$openObserver.withValue(
            { swap.observe($0) },
            operation: { results.openableFilePair(for: item.id) }
        )

        XCTAssertEqual(swap.outcome, 0)
        XCTAssertEqual(try read(XCTUnwrap(pair)), ["inside", "right"])
    }

    func testOpenablePairDoesNotFollowLeafSymlinkDuringBoundedReplacementRace() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try makeDirectory(named: "left", in: workspace)
        let rightRoot = try makeDirectory(named: "right", in: workspace)
        let outside = workspace.appending(path: "outside.txt")
        let leftLeaf = leftRoot.appending(path: "item.txt")
        let alternateLeaf = leftRoot.appending(path: "alternate.txt")
        try Data("outside".utf8).write(to: outside)
        try Data("inside".utf8).write(to: leftLeaf)
        try FileManager.default.createSymbolicLink(
            at: alternateLeaf,
            withDestinationURL: outside
        )
        try Data("right".utf8).write(to: rightRoot.appending(path: "item.txt"))
        let item = result(path: "item.txt", status: .different)
        let results = DirectoryResults(leftRoot: leftRoot, rightRoot: rightRoot, results: [item])
        let writerReady = DispatchSemaphore(value: 0)
        let readerReady = DispatchSemaphore(value: 0)
        let workerRendezvoused = DispatchSemaphore(value: 0)
        let beginSwaps = DispatchSemaphore(value: 0)
        let swapsStarted = DispatchSemaphore(value: 0)
        let stopRequested = DispatchSemaphore(value: 0)
        let raceFinished = DispatchGroup()

        raceFinished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { raceFinished.leave() }
            writerReady.signal()
            guard readerReady.wait(timeout: .now() + .seconds(2)) == .success else {
                XCTFail("reader did not join replacement race before deadline")
                return
            }
            workerRendezvoused.signal()
            guard beginSwaps.wait(timeout: .now() + .seconds(2)) == .success else {
                XCTFail("reader did not start replacement race before deadline")
                return
            }
            let cleanupDeadline = DispatchTime.now() + .seconds(3)
            var iteration = 0
            while DispatchTime.now() < cleanupDeadline,
                stopRequested.wait(timeout: .now()) == .timedOut
            {
                let swapResult = exchangeItems(leftLeaf, alternateLeaf)
                XCTAssertEqual(swapResult, 0, "swap \(iteration) failed with errno \(errno)")
                if swapResult != 0 { return }
                iteration += 1
                if iteration == 1 {
                    swapsStarted.signal()
                }
            }
        }
        defer {
            stopRequested.signal()
            readerReady.signal()
            beginSwaps.signal()
            XCTAssertEqual(
                raceFinished.wait(timeout: .now() + .seconds(1)),
                .success,
                "replacement race did not stop within cleanup bound"
            )
        }

        guard writerReady.wait(timeout: .now() + .seconds(2)) == .success else {
            XCTFail("writer did not reach replacement race rendezvous")
            readerReady.signal()
            return
        }
        readerReady.signal()
        guard workerRendezvoused.wait(timeout: .now() + .seconds(2)) == .success else {
            XCTFail("worker did not complete replacement race rendezvous")
            return
        }
        beginSwaps.signal()
        guard swapsStarted.wait(timeout: .now() + .seconds(2)) == .success else {
            XCTFail("writer did not start swapping before deadline")
            return
        }
        let deadline = DispatchTime.now() + .seconds(2)
        var successfulSafePairs = 0
        while DispatchTime.now() < deadline,
            raceFinished.wait(timeout: .now()) == .timedOut
        {
            guard let pair = results.openableFilePair(for: item.id) else { continue }
            let contents = try read(pair)
            XCTAssertEqual(contents, ["inside", "right"])
            if contents == ["inside", "right"],
                raceFinished.wait(timeout: .now()) == .timedOut
            {
                successfulSafePairs += 1
            }
        }

        XCTAssertGreaterThan(
            successfulSafePairs,
            0,
            "no safe pair was opened while replacements were active"
        )
        if let pair = results.openableFilePair(for: item.id) {
            XCTAssertEqual(try read(pair), ["inside", "right"])
        }
    }

    func testOpenablePairRejectsSymlinksNonregularFilesAndOutOfRootPaths() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try makeDirectory(named: "left", in: workspace)
        let rightRoot = try makeDirectory(named: "right", in: workspace)
        let outsideLeft = try makeDirectory(named: "outside-left", in: workspace)
        let outsideRight = try makeDirectory(named: "outside-right", in: workspace)
        try Data("outside left".utf8).write(to: outsideLeft.appending(path: "item.txt"))
        try Data("outside right".utf8).write(to: outsideRight.appending(path: "item.txt"))

        try FileManager.default.createSymbolicLink(
            at: leftRoot.appending(path: "leaf-link.txt"),
            withDestinationURL: outsideLeft.appending(path: "item.txt")
        )
        try Data("regular right".utf8).write(to: rightRoot.appending(path: "leaf-link.txt"))
        try FileManager.default.createSymbolicLink(
            at: leftRoot.appending(path: "escape"),
            withDestinationURL: outsideLeft
        )
        try FileManager.default.createSymbolicLink(
            at: rightRoot.appending(path: "escape"),
            withDestinationURL: outsideRight
        )
        try FileManager.default.createDirectory(
            at: leftRoot.appending(path: "directory-entry"),
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: rightRoot.appending(path: "directory-entry"),
            withIntermediateDirectories: false
        )
        try Data("outside".utf8).write(to: workspace.appending(path: "outside.txt"))

        let leafSymlink = result(path: "leaf-link.txt")
        let intermediateSymlink = result(path: "escape/item.txt")
        let nonregular = result(path: "directory-entry")
        let outOfRoot = result(path: "../outside.txt")
        let entries = [leafSymlink, intermediateSymlink, nonregular, outOfRoot]
        let results = DirectoryResults(leftRoot: leftRoot, rightRoot: rightRoot, results: entries)

        XCTAssertTrue(entries.allSatisfy(\.isOpenableFilePair))
        for entry in entries {
            XCTAssertNil(results.openableFilePair(for: entry.id), entry.relativePath)
        }
    }

    func testOpenablePairRejectsFIFOAndSocketWithoutHanging() throws {
        if let workspacePath = ProcessInfo.processInfo.environment[
            Self.nonregularOpenChildEnvironment
        ] {
            let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
            let leftRoot = workspace.appending(path: "left", directoryHint: .isDirectory)
            let rightRoot = workspace.appending(path: "right", directoryHint: .isDirectory)
            let entries = [result(path: "fifo"), result(path: "socket")]
            let results = DirectoryResults(leftRoot: leftRoot, rightRoot: rightRoot, results: entries)

            XCTAssertTrue(entries.allSatisfy(\.isOpenableFilePair))
            for entry in entries {
                XCTAssertNil(results.openableFilePair(for: entry.id), entry.relativePath)
            }
            return
        }

        let workspace = try shortTemporaryDirectory()
        let leftRoot = try makeDirectory(named: "left", in: workspace)
        let rightRoot = try makeDirectory(named: "right", in: workspace)
        let fifoURL = leftRoot.appending(path: "fifo")
        let socketURL = rightRoot.appending(path: "socket")
        XCTAssertEqual(Darwin.mkfifo(fifoURL.path, 0o600), 0)
        try createUNIXSocket(at: socketURL)
        try Data("right fifo".utf8).write(to: rightRoot.appending(path: "fifo"))
        try Data("left socket".utf8).write(to: leftRoot.appending(path: "socket"))

        try assertTestPassesInBoundedSubprocess(
            "MacMergeCoreTests.DirectoryResultsTests/testOpenablePairRejectsFIFOAndSocketWithoutHanging",
            environment: [Self.nonregularOpenChildEnvironment: workspace.path]
        )
    }

    func testRootIdentityDistinguishesReplacementAndKeepsOriginalRootsPinned() throws {
        let workspace = try temporaryDirectory()
        let leftRoot = try makeDirectory(named: "left", in: workspace)
        let rightRoot = try makeDirectory(named: "right", in: workspace)
        try Data("original left".utf8).write(to: leftRoot.appending(path: "item.txt"))
        try Data("original right".utf8).write(to: rightRoot.appending(path: "item.txt"))
        let item = result(path: "item.txt", status: .different)
        let original = DirectoryResults(leftRoot: leftRoot, rightRoot: rightRoot, results: [item])
        let sameRoots = DirectoryResults(leftRoot: leftRoot, rightRoot: rightRoot, results: [item])

        XCTAssertEqual(original, sameRoots)

        try FileManager.default.moveItem(
            at: leftRoot,
            to: workspace.appending(path: "original-left")
        )
        try FileManager.default.moveItem(
            at: rightRoot,
            to: workspace.appending(path: "original-right")
        )
        try FileManager.default.createDirectory(at: leftRoot, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: rightRoot, withIntermediateDirectories: false)
        try Data("replacement left".utf8).write(to: leftRoot.appending(path: "item.txt"))
        try Data("replacement right".utf8).write(to: rightRoot.appending(path: "item.txt"))
        let replacement = DirectoryResults(leftRoot: leftRoot, rightRoot: rightRoot, results: [item])

        XCTAssertNotEqual(original, replacement)
        XCTAssertEqual(
            try read(XCTUnwrap(original.openableFilePair(for: item.id))),
            ["original left", "original right"]
        )
        XCTAssertEqual(
            try read(XCTUnwrap(replacement.openableFilePair(for: item.id))),
            ["replacement left", "replacement right"]
        )
    }

    private enum ResultSides: Equatable {
        case left
        case right
        case both
    }

    private enum ResultShape: String, CaseIterable {
        case neither
        case leftOnly
        case rightOnly
        case equalKinds
        case unequalKinds
    }

    private enum ProbeError: Error, Equatable {
        case expected
    }

    private func validShape(for status: DirectoryComparisonStatus) -> ResultShape {
        switch status {
        case .leftOnly:
            .leftOnly
        case .rightOnly:
            .rightOnly
        case .typeMismatch:
            .unequalKinds
        case .pending, .identical, .different, .skipped, .error:
            .equalKinds
        }
    }

    private func matrixCase(
        status: DirectoryComparisonStatus,
        shape: ResultShape
    ) -> String {
        "\(status.rawValue):\(shape.rawValue)"
    }

    private func matrixResult(
        status: DirectoryComparisonStatus,
        shape: ResultShape
    ) -> DirectoryResult {
        let left: DirectoryEntryMetadata?
        let right: DirectoryEntryMetadata?
        switch shape {
        case .neither:
            left = nil
            right = nil
        case .leftOnly:
            left = metadata("item", kind: .file)
            right = nil
        case .rightOnly:
            left = nil
            right = metadata("item", kind: .directory)
        case .equalKinds:
            left = metadata("item", kind: .symbolicLink)
            right = metadata("item", kind: .symbolicLink)
        case .unequalKinds:
            left = metadata("item", kind: .file)
            right = metadata("item", kind: .directory)
        }
        return DirectoryResult(left: left, right: right, status: status)
    }

    private func metadata(
        _ path: String,
        kind: DirectoryEntryKind = .file,
        byteCount: UInt64? = nil,
        modificationDate: Date? = nil,
        isHidden: Bool? = nil
    ) -> DirectoryEntryMetadata {
        DirectoryEntryMetadata(
            relativePath: path,
            kind: kind,
            byteCount: byteCount,
            modificationDate: modificationDate,
            isHidden: isHidden
        )
    }

    private func result(
        path: String,
        sides: ResultSides = .both,
        status: DirectoryComparisonStatus = .identical,
        kind: DirectoryEntryKind = .file,
        leftSize: UInt64? = nil,
        leftModificationDate: Date? = nil,
        rightModificationDate: Date? = nil
    ) -> DirectoryResult {
        let left =
            sides == .right
            ? nil
            : metadata(
                path,
                kind: kind,
                byteCount: leftSize,
                modificationDate: leftModificationDate
            )
        let right =
            sides == .left
            ? nil
            : metadata(path, kind: kind, modificationDate: rightModificationDate)
        return DirectoryResult(left: left, right: right, status: status)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "MacMergeDirectoryResultsTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func shortTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp", isDirectory: true).appending(
            path: "MM-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeDirectory(named name: String, in parent: URL) throws -> URL {
        let url = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func read(_ pair: DirectoryFilePair) throws -> [String] {
        try pair.withReaders { left, right in
            [
                try text(left.readToEnd(maximumByteCount: 1_024)),
                try text(right.readToEnd(maximumByteCount: 1_024))
            ]
        }
    }

    private func text(_ data: Data) throws -> String {
        try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func createUNIXSocket(at url: URL) throws {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard url.path.utf8.count < pathCapacity else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG))
        }
        withUnsafeMutablePointer(to: &address.sun_path) { destination in
            url.path.withCString { source in
                _ = Darwin.strlcpy(
                    UnsafeMutableRawPointer(destination).assumingMemoryBound(to: CChar.self),
                    source,
                    pathCapacity
                )
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func markInvalidInitializerChildAsStarted() {
        guard
            let path = ProcessInfo.processInfo.environment[
                Self.invalidInitializerMarkerEnvironment
            ]
        else {
            return
        }
        _ = FileManager.default.createFile(atPath: path, contents: Data())
    }

    private func constructInvalidResult(for invalidCase: String) {
        let components = invalidCase.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2,
            let rawStatus = Int(components[0]),
            let status = DirectoryComparisonStatus(rawValue: rawStatus),
            let shape = ResultShape(rawValue: components[1])
        else {
            XCTFail("Unknown invalid initializer case: \(invalidCase)")
            return
        }
        _ = matrixResult(status: status, shape: shape)
    }

    private func assertInitializerRejects(
        _ invalidCase: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let marker = FileManager.default.temporaryDirectory.appending(
            path: "MacMergeDirectoryResultsInvalidInitializer-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: marker) }
        let diagnosticsURL = FileManager.default.temporaryDirectory.appending(
            path: "MacMergeDirectoryResultsInvalidInitializer-\(UUID().uuidString).log"
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: diagnosticsURL.path, contents: nil))
        let diagnostics = try FileHandle(forUpdating: diagnosticsURL)
        defer {
            try? diagnostics.close()
            try? FileManager.default.removeItem(at: diagnosticsURL)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [
            "-XCTest",
            "MacMergeCoreTests.DirectoryResultsTests/testInitializerAcceptsOnlyValidStatusSideAndKindCombinations",
            Bundle(for: Self.self).bundleURL.path
        ]
        var environment = ProcessInfo.processInfo.environment
        environment[Self.invalidInitializerCaseEnvironment] = invalidCase
        environment[Self.invalidInitializerMarkerEnvironment] = marker.path
        process.environment = environment
        process.standardOutput = diagnostics
        process.standardError = diagnostics
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        guard terminated.wait(timeout: .now() + .seconds(5)) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            XCTAssertEqual(
                terminated.wait(timeout: .now() + .seconds(1)),
                .success,
                "Invalid initializer child did not terminate after SIGKILL: \(invalidCase)",
                file: file,
                line: line
            )
            XCTFail(
                "Invalid initializer child exceeded bounded timeout: \(invalidCase)",
                file: file,
                line: line
            )
            return
        }
        try diagnostics.synchronize()
        try diagnostics.seek(toOffset: 0)
        let output = try diagnostics.readToEnd() ?? Data()
        let diagnosticText = String(decoding: output, as: UTF8.self)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: marker.path),
            "Child test did not reach invalid initializer case \(invalidCase)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            process.terminationReason,
            .uncaughtSignal,
            "Invalid initializer case did not trap: \(invalidCase)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            process.terminationStatus,
            SIGTRAP,
            "Invalid initializer case trapped with unexpected signal: \(invalidCase)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            diagnosticText.contains("Precondition failed:"),
            "Invalid initializer trap lacked expected precondition diagnostic: \(diagnosticText)",
            file: file,
            line: line
        )
    }

    private func assertTestPassesInBoundedSubprocess(
        _ testName: String,
        environment additions: [String: String],
        timeout: DispatchTimeInterval = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["-XCTest", testName, Bundle(for: Self.self).bundleURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, addition in
            addition
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        guard terminated.wait(timeout: .now() + timeout) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            XCTAssertEqual(
                terminated.wait(timeout: .now() + .seconds(1)),
                .success,
                "Child test did not terminate after SIGKILL",
                file: file,
                line: line
            )
            XCTFail("Child test exceeded bounded timeout", file: file, line: line)
            return
        }
        XCTAssertEqual(process.terminationReason, .exit, file: file, line: line)
        XCTAssertEqual(process.terminationStatus, 0, file: file, line: line)
    }
}

private final class CheckpointSwap: @unchecked Sendable {
    private let target: DirectoryFilePair.OpenCheckpoint
    private let first: URL
    private let second: URL
    private let lock = NSLock()
    private var didSwap = false
    private var swapResult: Int32?

    init(target: DirectoryFilePair.OpenCheckpoint, first: URL, second: URL) {
        self.target = target
        self.first = first
        self.second = second
    }

    var outcome: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return swapResult
    }

    func observe(_ checkpoint: DirectoryFilePair.OpenCheckpoint) {
        guard checkpoint == target else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !didSwap else { return }
        swapResult = exchangeItems(first, second)
        didSwap = swapResult == 0
    }

    func restoreIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard didSwap else { return }
        _ = exchangeItems(first, second)
        didSwap = false
    }
}

private final class ReadGrowth: @unchecked Sendable {
    private let url: URL
    private let data: Data
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    init(url: URL, data: Data) {
        self.url = url
        self.data = data
    }

    var didGrow: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .success? = result else { return false }
        return true
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        guard case .failure(let error)? = result else { return nil }
        return error
    }

    func observe(_ checkpoint: DirectoryFileReader.ReadCheckpoint) {
        guard checkpoint == .afterInitialSnapshot else { return }
        lock.lock()
        defer { lock.unlock() }
        guard result == nil else { return }
        result = Result {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        }
    }
}

private func exchangeItems(_ first: URL, _ second: URL) -> Int32 {
    first.path.withCString { firstPath in
        second.path.withCString { secondPath in
            Darwin.renameatx_np(
                AT_FDCWD,
                firstPath,
                AT_FDCWD,
                secondPath,
                UInt32(RENAME_SWAP)
            )
        }
    }
}
