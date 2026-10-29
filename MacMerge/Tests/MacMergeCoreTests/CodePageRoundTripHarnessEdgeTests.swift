import Foundation
import XCTest

@testable import MacMergeCore

final class CodePageRoundTripHarnessEdgeTests: XCTestCase {
    private typealias Harness = CodePageRoundTripHarness
    private typealias Stage = CodePageRoundTripHarness.Stage

    private let legacyEncodings: [TextFileEncoding] = [
        .windows1250, .windows1251, .windows1252, .windows1253, .windows1254, .windows1255
    ]

    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodePageRoundTripHarnessEdgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func folderEncoding(_ name: String) throws -> Harness.FixtureFolderEncoding {
        try XCTUnwrap(Harness.fixtureFolderEncodings[name], name)
    }

    private func runSingle(
        bytes: Data,
        folder: String,
        fileName: String = "fixture.txt"
    ) throws -> Harness.FixtureResult {
        let root = try makeScratchDirectory()
        let source = root.appendingPathComponent(fileName)
        try bytes.write(to: source)
        let fixture = Harness.Fixture(
            relativePath: "Codepages/\(folder)/\(fileName)",
            url: source,
            folderName: folder,
            expected: try folderEncoding(folder)
        )
        return Harness.runFixture(fixture, in: root.appendingPathComponent("work", isDirectory: true))
    }

    private func makeDataRoot(files: [String: Data]) throws -> URL {
        let root = try makeScratchDirectory()
        for family in Harness.fixtureFamilies {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(family, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for (path, data) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
        return root
    }

    // MARK: insertLine

    func testInsertLineReusesCRLFTerminator() {
        let edit = Harness.insertLine("X", afterFirstLineOf: "a\r\nb\nc")
        XCTAssertEqual(edit.prefix, "a\r\n")
        XCTAssertEqual(edit.insertedText, "X\r\n")
        XCTAssertEqual(edit.text, "a\r\nX\r\nb\nc")
        XCTAssertFalse(edit.appendsAtEnd)
    }

    func testInsertLineReusesLoneCRAndLF() {
        let cr = Harness.insertLine("X", afterFirstLineOf: "a\rb")
        XCTAssertEqual(cr.insertedText, "X\r")
        XCTAssertEqual(cr.text, "a\rX\rb")
        let lf = Harness.insertLine("X", afterFirstLineOf: "a\nb\r\n")
        XCTAssertEqual(lf.insertedText, "X\n")
        XCTAssertEqual(lf.text, "a\nX\nb\r\n")
    }

    func testInsertLineTrailingCRAtEndOfText() {
        let edit = Harness.insertLine("X", afterFirstLineOf: "a\r")
        XCTAssertEqual(edit.prefix, "a\r")
        XCTAssertEqual(edit.text, "a\rX\r")
        XCTAssertFalse(edit.appendsAtEnd)
    }

    func testInsertLineWithoutTerminatorAppendsDefaultCRLF() {
        let edit = Harness.insertLine("X", afterFirstLineOf: "only")
        XCTAssertTrue(edit.appendsAtEnd)
        XCTAssertEqual(edit.prefix, "only")
        XCTAssertEqual(edit.insertedText, "\r\nX")
        XCTAssertEqual(edit.text, "only\r\nX")
    }

    func testInsertLineTreatsLeadingTerminatorAsFirstLine() {
        let edit = Harness.insertLine("X", afterFirstLineOf: "\r\nrest")
        XCTAssertEqual(edit.prefix, "\r\n")
        XCTAssertEqual(edit.text, "\r\nX\r\nrest")
    }

    func testInsertLineIntoEmptyTextAppendsMarkerOnly() {
        let edit = Harness.insertLine("X", afterFirstLineOf: "")
        XCTAssertTrue(edit.appendsAtEnd)
        XCTAssertEqual(edit.text, "X")
        XCTAssertEqual(edit.insertedText, "X")
    }

    // MARK: difference

    func testDifferenceReportsFirstMismatchAndCounts() {
        let diff = Harness.difference(expected: Data([1, 2, 3, 4]), actual: Data([1, 2, 9]))
        XCTAssertEqual(diff, Harness.ByteDifference(expectedCount: 4, actualCount: 3, firstDifferenceOffset: 2))
    }

    func testDifferenceForPrefixAndEqualAndEmptyInputs() {
        XCTAssertEqual(
            Harness.difference(expected: Data([1, 2]), actual: Data([1, 2, 3])),
            Harness.ByteDifference(expectedCount: 2, actualCount: 3, firstDifferenceOffset: 2)
        )
        XCTAssertEqual(
            Harness.difference(expected: Data([5]), actual: Data([5])),
            Harness.ByteDifference(expectedCount: 1, actualCount: 1, firstDifferenceOffset: 1)
        )
        XCTAssertEqual(
            Harness.difference(expected: Data(), actual: Data()),
            Harness.ByteDifference(expectedCount: 0, actualCount: 0, firstDifferenceOffset: 0)
        )
    }

    func testDifferenceHandlesSlicesWithNonZeroStartIndex() {
        let base = Data([0, 0, 7, 8, 9])
        let slice = base.dropFirst(2)
        let diff = Harness.difference(expected: slice, actual: Data([7, 8, 1]))
        XCTAssertEqual(diff, Harness.ByteDifference(expectedCount: 3, actualCount: 3, firstDifferenceOffset: 2))
    }

    // MARK: runFixture

    func testRunFixturePassesAllStagesForEachLegacyCodePage() throws {
        for encoding in legacyEncodings {
            let bytes = try XCTUnwrap(Harness.synthesizedFixtureBytes(for: encoding))
            let folder = "CP\(try XCTUnwrap(Harness.synthesizedFolderEncoding(for: encoding)).windowsCodePage)"
            let result = try runSingle(bytes: bytes, folder: folder)
            XCTAssertTrue(result.isByteExactRoundTrip, "\(encoding): \(String(describing: result.firstFailure))")
            XCTAssertEqual(result.stages.map(\.stage), Stage.allCases)
            XCTAssertNil(result.firstFailure)
            XCTAssertEqual(result.sourceByteCount, bytes.count)
            let inserted = try TextFileCodec.encode(
                DecodedTextFile(text: Harness.editMarker(for: encoding) + "\r\n", encoding: encoding, hasByteOrderMark: false)
            )
            XCTAssertEqual(result.savedByteCount, bytes.count + inserted.count, "\(encoding)")
        }
    }

    func testRunFixtureUTF16BOMVariantsRoundTrip() throws {
        for folder in ["UCS-2LE", "UCS-2BE", "UTF-8", "UTF-8-NOBOM"] {
            let expected = try folderEncoding(folder)
            let text = "first caf\u{E9}\r\nsecond \u{7DE8}\nthird"
            let encoded = try TextFileCodec.encode(
                DecodedTextFile(text: text, encoding: expected.encoding, hasByteOrderMark: expected.hasByteOrderMark)
            )
            let result = try runSingle(bytes: encoded, folder: folder)
            XCTAssertTrue(result.isByteExactRoundTrip, "\(folder): \(String(describing: result.firstFailure))")
        }
    }

    func testRunFixtureUnterminatedLegacyLineSplicesAtEnd() throws {
        // "Ж" in CP1251 is 0xC6; no terminator anywhere.
        let result = try runSingle(bytes: Data([0x41, 0xC6]), folder: "CP1251")
        XCTAssertTrue(result.isByteExactRoundTrip, String(describing: result.firstFailure))
        // Source, CRLF, then the 35-byte CP1251 marker.
        XCTAssertEqual(result.savedByteCount, 2 + 2 + 35)
    }

    func testRunFixtureOversizedSourceFailsBeforeReading() throws {
        let root = try makeScratchDirectory()
        let url = root.appendingPathComponent("big.txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(Harness.maximumFixtureBytes + 1))
        try handle.close()
        let fixture = Harness.Fixture(
            relativePath: "Codepages/CP1252/big.txt",
            url: url,
            folderName: "CP1252",
            expected: try folderEncoding("CP1252")
        )
        let result = Harness.runFixture(fixture, in: root.appendingPathComponent("work"))
        XCTAssertEqual(result.firstFailure?.failure, .fixtureTooLarge(byteCount: Harness.maximumFixtureBytes + 1))
        XCTAssertEqual(result.sourceByteCount, Harness.maximumFixtureBytes + 1)
    }

    func testRunFixtureWrongFolderEncodingFailsLoad() throws {
        // UTF-16 LE BOM bytes declared as a no-BOM UTF-8 folder.
        let bytes = Data([0xFF, 0xFE, 0x41, 0x00, 0x0A, 0x00])
        let result = try runSingle(bytes: bytes, folder: "UTF-8-NOBOM")
        XCTAssertEqual(result.firstFailure?.stage, .load)
        XCTAssertEqual(
            result.firstFailure?.failure,
            .loadFailed(
                "File encoding is unsupported or ambiguous. Supported legacy encodings are CP932, CP51932, CP50220, "
                    + "CP1250, CP1251, CP1252, CP1253, CP1254, and CP1255."
            ))
    }

    func testRunFixtureBOMExpectationMismatchFailsLoad() throws {
        let bytes = Data([0xEF, 0xBB, 0xBF, 0x61, 0x0A])
        let result = try runSingle(bytes: bytes, folder: "UTF-8-NOBOM")
        XCTAssertEqual(result.firstFailure?.stage, .load)
        XCTAssertEqual(result.firstFailure?.failure, .byteOrderMarkMismatch(expected: false, actual: true))
    }

    func testRunFixtureLeavesNoUntouchedCopyDrift() throws {
        let bytes = try XCTUnwrap(Harness.synthesizedFixtureBytes(for: .windows1252))
        let root = try makeScratchDirectory()
        let source = root.appendingPathComponent("s.txt")
        try bytes.write(to: source)
        let work = root.appendingPathComponent("work", isDirectory: true)
        let fixture = Harness.Fixture(
            relativePath: "Codepages/CP1252/s.txt",
            url: source,
            folderName: "CP1252",
            expected: try folderEncoding("CP1252")
        )
        let result = Harness.runFixture(fixture, in: work)
        XCTAssertTrue(result.isByteExactRoundTrip, String(describing: result.firstFailure))
        XCTAssertEqual(try Data(contentsOf: work.appendingPathComponent("left-s.txt")), bytes)
        XCTAssertEqual(try Data(contentsOf: work.appendingPathComponent("right-s.txt")), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    // MARK: run

    func testRunCleansUpWorkingDirectory() throws {
        let dataRoot = try makeDataRoot(files: ["Codepages/CP1252/a.txt": Data("a\r\nb".utf8)])
        let work = try makeScratchDirectory()
        let report = try Harness.run(dataRoot: dataRoot, workingDirectory: work, synthesizeMissingEncodings: false)
        XCTAssertTrue(report.allFixturesByteExact)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path), [])
    }

    func testRunHonorsCancellationBeforeFirstFixture() throws {
        let dataRoot = try makeDataRoot(files: ["Codepages/CP1252/a.txt": Data("a\nb".utf8)])
        let work = try makeScratchDirectory()
        XCTAssertThrowsError(
            try Harness.run(dataRoot: dataRoot, workingDirectory: work, cancellationCheck: { true })
        ) { error in
            XCTAssertEqual(error as? Harness.HarnessError, .cancelled)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path), [])
    }

    func testRunThrowsWhenWorkingDirectoryCannotBeCreated() throws {
        let dataRoot = try makeDataRoot(files: ["Codepages/CP1252/a.txt": Data("a\nb".utf8)])
        let blocker = try makeScratchDirectory().appendingPathComponent("file")
        try Data("x".utf8).write(to: blocker)
        XCTAssertThrowsError(try Harness.run(dataRoot: dataRoot, workingDirectory: blocker)) { error in
            XCTAssertEqual(error as? Harness.HarnessError, .workingDirectoryUnavailable)
        }
    }

    func testRunCatalogRejectsTooManyFixtures() throws {
        let fixture = Harness.Fixture(
            relativePath: "Codepages/CP1252/a.txt",
            url: URL(fileURLWithPath: "/nonexistent"),
            folderName: "CP1252",
            expected: try folderEncoding("CP1252")
        )
        let catalog = Harness.Catalog(
            dataRoot: URL(fileURLWithPath: "/nonexistent"),
            fixtures: Array(repeating: fixture, count: Harness.maximumFixtures + 1),
            unsupportedFixtures: []
        )
        XCTAssertThrowsError(try Harness.run(catalog: catalog)) { error in
            XCTAssertEqual(error as? Harness.HarnessError, .fixtureLimitExceeded(maximum: Harness.maximumFixtures))
        }
    }

    func testRunSynthesizesOnlyEncodingsWithoutRealFixture() throws {
        let dataRoot = try makeDataRoot(files: ["Codepages/CP1252/a.txt": Data("a\nb".utf8)])
        let report = try Harness.run(dataRoot: dataRoot)
        let synthesized = report.synthesizedResults.map(\.expected.encoding)
        XCTAssertFalse(synthesized.contains(.windows1252))
        XCTAssertEqual(synthesized, report.catalog.encodingsWithoutFixture)
        XCTAssertEqual(synthesized.count, Harness.supportedEncodings.count - 1)
        XCTAssertTrue(
            report.allSynthesizedByteExact,
            report.failedSynthesizedResults.map {
                "\($0.relativePath): \(String(describing: $0.firstFailure))"
            }.joined(separator: "\n"))
        XCTAssertTrue(report.synthesizedResults.allSatisfy { $0.relativePath.hasPrefix(Harness.synthesizedPathPrefix + "/") })
        XCTAssertEqual(report.results.count, 1)
    }

    // MARK: Report

    func testReportAllFixturesByteExactRequiresResultsAndNoUnsupported() throws {
        let expected = try folderEncoding("CP1252")
        let passing = Harness.FixtureResult(
            relativePath: "p",
            expected: expected,
            sourceByteCount: 1,
            automaticDetection: nil,
            stages: Stage.allCases.map { .init(stage: $0, status: .passed) },
            savedByteCount: 2,
            editMarker: "m"
        )
        let partial = Harness.FixtureResult(
            relativePath: "q",
            expected: expected,
            sourceByteCount: 1,
            automaticDetection: nil,
            stages: [.init(stage: .load, status: .passed)],
            savedByteCount: 0,
            editMarker: "m"
        )
        let root = URL(fileURLWithPath: "/r")
        let clean = Harness.Catalog(dataRoot: root, fixtures: [], unsupportedFixtures: [])
        let dirty = Harness.Catalog(
            dataRoot: root,
            fixtures: [],
            unsupportedFixtures: [.init(relativePath: "Unicode/", reason: .missingFixtureFamily)]
        )

        XCTAssertFalse(partial.isByteExactRoundTrip)
        XCTAssertNil(partial.firstFailure)
        XCTAssertFalse(Harness.Report(catalog: clean, results: [], knownUnsupportedCodePages: []).allFixturesByteExact)
        XCTAssertTrue(Harness.Report(catalog: clean, results: [passing], knownUnsupportedCodePages: []).allFixturesByteExact)
        XCTAssertFalse(Harness.Report(catalog: dirty, results: [passing], knownUnsupportedCodePages: []).allFixturesByteExact)
        let mixed = Harness.Report(catalog: clean, results: [passing, partial], knownUnsupportedCodePages: [])
        XCTAssertFalse(mixed.allFixturesByteExact)
        XCTAssertEqual(mixed.passedCount, 1)
        XCTAssertEqual(mixed.failedResults.map(\.relativePath), ["q"])
        let synthFail = Harness.Report(
            catalog: clean,
            results: [passing],
            synthesizedResults: [partial],
            knownUnsupportedCodePages: []
        )
        XCTAssertTrue(synthFail.allFixturesByteExact, "synthesized failures must not affect real-fixture verdict")
        XCTAssertFalse(synthFail.allSynthesizedByteExact)
    }

    func testFirstFailureReturnsEarliestFailedStage() throws {
        let result = Harness.FixtureResult(
            relativePath: "f",
            expected: try folderEncoding("CP1252"),
            sourceByteCount: 0,
            automaticDetection: nil,
            stages: [
                .init(stage: .load, status: .passed),
                .init(stage: .compare, status: .failed(.compareFailed("x"))),
                .init(stage: .edit, status: .failed(.editNotRepresentable))
            ],
            savedByteCount: 0,
            editMarker: "m"
        )
        XCTAssertEqual(result.firstFailure?.stage, .compare)
        XCTAssertEqual(result.firstFailure?.failure, .compareFailed("x"))
    }

    // MARK: Discovery

    func testLocateTestingDataReturnsNilOutsideRepository() throws {
        let root = try makeScratchDirectory()
        XCTAssertNil(Harness.locateTestingData(startingAt: root))
    }

    func testLocateTestingDataFindsAncestor() throws {
        let root = try makeScratchDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Testing/Data/Codepages", isDirectory: true),
            withIntermediateDirectories: true
        )
        let deep = root.appendingPathComponent("a/b/c/file.swift")
        let found = try XCTUnwrap(Harness.locateTestingData(startingAt: deep))
        XCTAssertEqual(
            found.resolvingSymlinksInPath().standardizedFileURL.path,
            root.appendingPathComponent("Testing/Data").resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func testDiscoverReportsEmptyUnknownFolderAndSortsFixtures() throws {
        let root = try makeDataRoot(files: [
            "Unicode/UTF-8/b.txt": Data([0xEF, 0xBB, 0xBF, 0x62]),
            "Unicode/UTF-8/a.txt": Data([0xEF, 0xBB, 0xBF, 0x61])
        ])
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Codepages/Mystery", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Codepages/CP1250", isDirectory: true),
            withIntermediateDirectories: true
        )
        let catalog = try Harness.discover(dataRoot: root)
        XCTAssertEqual(catalog.fixtures.map(\.relativePath), ["Unicode/UTF-8/a.txt", "Unicode/UTF-8/b.txt"])
        XCTAssertEqual(
            catalog.unsupportedFixtures,
            [
                .init(relativePath: "Codepages/Mystery/", reason: .unrecognizedFixtureFolder)
            ])
        XCTAssertTrue(catalog.encodingsWithoutFixture.contains(.windows1250))
        XCTAssertFalse(catalog.encodingsWithoutFixture.contains(.utf8))
    }

    func testDiscoverSkipsHiddenFiles() throws {
        let root = try makeDataRoot(files: [
            "Codepages/CP1252/.DS_Store": Data([0]),
            "Codepages/CP1252/a.txt": Data("a".utf8)
        ])
        let catalog = try Harness.discover(dataRoot: root)
        XCTAssertEqual(catalog.fixtures.map(\.relativePath), ["Codepages/CP1252/a.txt"])
        XCTAssertEqual(catalog.unsupportedFixtures, [])
    }

    func testDiscoverAllowsExactlyMaximumEntries() throws {
        let root = try makeDataRoot(files: [:])
        let folder = root.appendingPathComponent("Codepages/CP1252", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<Harness.maximumFixtures {
            try Data().write(to: folder.appendingPathComponent(String(format: "f%03d.txt", index)))
        }
        let catalog = try Harness.discover(dataRoot: root)
        XCTAssertEqual(catalog.fixtures.count, Harness.maximumFixtures)
    }

    // MARK: Tables

    func testKnownUnsupportedCodePagesAreUniqueAndDisjointFromSupported() {
        let numbers = Harness.knownUnsupportedCodePages.map(\.windowsCodePage)
        XCTAssertEqual(Set(numbers).count, numbers.count)
        XCTAssertTrue(Set(Harness.fixtureFolderEncodings.values.map(\.windowsCodePage)).isDisjoint(with: numbers))
        XCTAssertTrue(Set(CodePageFixtureMatrix.CodePage.allCases.map(\.rawValue)).isDisjoint(with: numbers))
        XCTAssertTrue(Harness.knownUnsupportedCodePages.allSatisfy { !$0.name.isEmpty })
    }

    func testKnownUnsupportedCodePagesPinObservedReasons() throws {
        let pages = Dictionary(uniqueKeysWithValues: Harness.knownUnsupportedCodePages.map { ($0.windowsCodePage, $0) })
        for number in [437, 936, 1256] {
            let page = try XCTUnwrap(pages[number], "\(number)")
            XCTAssertEqual(page.reason, .notWiredIntoTextFileCodec, "\(number)")
            XCTAssertTrue(page.foundationConverterAvailable, "\(number)")
        }
        for number in [12000, 12001] {
            XCTAssertEqual(try XCTUnwrap(pages[number]).reason, .failClosedByCodec, "\(number)")
        }
        // macOS has no converter for CP50222 (JIS with SO/SI kana).
        let jisShiftKana = try XCTUnwrap(pages[50222])
        XCTAssertEqual(jisShiftKana.reason, .noFoundationConverter)
        XCTAssertFalse(jisShiftKana.foundationConverterAvailable)
    }

    func testSupportedEncodingsMatchCodePageMatrix() throws {
        let matrix = Set(CodePageFixtureMatrix.CodePage.allCases.map(\.textFileEncoding))
        let unicode: Set<TextFileEncoding> = [.utf8, .utf16LittleEndian, .utf16BigEndian]
        XCTAssertEqual(Harness.supportedEncodings.count, Set(Harness.supportedEncodings).count)
        XCTAssertEqual(Set(Harness.supportedEncodings), matrix.union(unicode))
        for page in CodePageFixtureMatrix.CodePage.allCases {
            let folder = try XCTUnwrap(Harness.fixtureFolderEncodings["CP\(page.rawValue)"], "\(page)")
            XCTAssertEqual(folder.windowsCodePage, page.rawValue, "\(page)")
            XCTAssertEqual(folder.encoding, page.textFileEncoding, "\(page)")
            XCTAssertFalse(folder.hasByteOrderMark, "\(page)")
        }
        XCTAssertEqual(Set(Harness.fixtureFolderEncodings.values.map(\.encoding)), Set(Harness.supportedEncodings))
    }

    func testFoundationConverterAvailabilityBounds() {
        for page in [932, 1250, 1251, 1252, 1253, 1254, 1255] {
            XCTAssertTrue(Harness.foundationConverterAvailable(windowsCodePage: page), "\(page)")
        }
        XCTAssertFalse(Harness.foundationConverterAvailable(windowsCodePage: -1))
        XCTAssertFalse(Harness.foundationConverterAvailable(windowsCodePage: Int(UInt32.max) + 1))
        XCTAssertFalse(Harness.foundationConverterAvailable(windowsCodePage: 999_999))
    }
}
