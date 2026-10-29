import Foundation
import XCTest

@testable import MacMergeCore

final class CodePageRoundTripHarnessTests: XCTestCase {
    private typealias Harness = CodePageRoundTripHarness

    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodePageRoundTripHarnessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func describe(_ results: [Harness.FixtureResult]) -> String {
        results.compactMap { result in
            result.firstFailure.map { "\(result.relativePath): \($0.stage) \($0.failure)" }
        }.joined(separator: "\n")
    }

    /// One full run over the real `Testing/Data` tree, shared by every real-fixture test.
    private static let realReport: Result<Harness.Report, any Error> = Result {
        guard let dataRoot = Harness.locateTestingData(startingAt: URL(fileURLWithPath: #filePath)) else {
            throw Harness.HarnessError.dataRootNotFound
        }
        return try Harness.run(dataRoot: dataRoot)
    }

    private static let realFixturePaths = [
        "Codepages/CP50220/DiffItem.h",
        "Codepages/CP51932/DiffItem.h",
        "Codepages/CP932/DiffItem.h",
        "Unicode/UCS-2BE/DiffItem.h",
        "Unicode/UCS-2LE/DiffItem.h",
        "Unicode/UTF-8/DiffItem.h",
        "Unicode/UTF-8-NOBOM/DiffItem.h"
    ]

    func testRealWinMergeFixturesRoundTripByteExactly() throws {
        let report = try Self.realReport.get()

        XCTAssertEqual(report.results.map(\.relativePath), Self.realFixturePaths)
        XCTAssertTrue(report.allFixturesByteExact, describe(report.failedResults))
        XCTAssertEqual(report.catalog.unsupportedFixtures, [])
        XCTAssertEqual(
            report.catalog.encodingsWithoutFixture,
            [.windows1250, .windows1251, .windows1252, .windows1253, .windows1254, .windows1255]
        )
        for result in report.results {
            let encoding = result.expected.encoding
            XCTAssertEqual(result.stages.map(\.stage), CodePageRoundTripHarness.Stage.allCases, result.relativePath)
            XCTAssertTrue(result.stages.allSatisfy(\.passed), result.relativePath)
            XCTAssertEqual(result.editMarker, Harness.editMarker(for: encoding), result.relativePath)
            // Every real fixture uses CRLF, so the saved file grows by exactly the encoded
            // marker line; the BOM is already part of the source.
            let inserted = try TextFileCodec.encode(
                DecodedTextFile(text: result.editMarker + "\r\n", encoding: encoding, hasByteOrderMark: false)
            )
            XCTAssertEqual(result.savedByteCount, result.sourceByteCount + inserted.count, result.relativePath)
        }
    }

    func testRealFixtureBytesMatchFolderEncodings() throws {
        let dataRoot = try XCTUnwrap(Harness.locateTestingData(startingAt: URL(fileURLWithPath: #filePath)))
        func bytes(_ path: String) throws -> Data {
            try Data(contentsOf: dataRoot.appendingPathComponent(path))
        }
        let firstLine = Data([0x2F, 0x2A, 0x2A, 0x0D, 0x0A])
        XCTAssertEqual(Array(try bytes("Unicode/UTF-8/DiffItem.h").prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(Array(try bytes("Unicode/UCS-2LE/DiffItem.h").prefix(2)), [0xFF, 0xFE])
        XCTAssertEqual(Array(try bytes("Unicode/UCS-2BE/DiffItem.h").prefix(2)), [0xFE, 0xFF])
        for path in ["Unicode/UTF-8-NOBOM", "Codepages/CP932", "Codepages/CP51932", "Codepages/CP50220"] {
            XCTAssertTrue(try bytes("\(path)/DiffItem.h").starts(with: firstLine), path)
        }
        let jis = try bytes("Codepages/CP50220/DiffItem.h")
        XCTAssertNotNil(jis.firstRange(of: Data([0x1B, 0x24, 0x42])))
        XCTAssertFalse(jis.contains { $0 >= 0x80 })
        // テスト in Shift_JIS and in EUC-JP.
        XCTAssertNotNil(try bytes("Codepages/CP932/DiffItem.h").firstRange(of: Data([0x83, 0x65, 0x83, 0x58, 0x83, 0x67])))
        XCTAssertNotNil(try bytes("Codepages/CP51932/DiffItem.h").firstRange(of: Data([0xA5, 0xC6, 0xA5, 0xB9, 0xA5, 0xC8])))
    }

    func testAutomaticDetectionIsRecordedButDoesNotGateRoundTrip() throws {
        let report = try Self.realReport.get()
        let detection = Dictionary(uniqueKeysWithValues: report.results.map { ($0.relativePath, $0.automaticDetection) })

        XCTAssertEqual(detection["Unicode/UTF-8/DiffItem.h"], .detected(.utf8, hasByteOrderMark: true))
        XCTAssertEqual(detection["Unicode/UTF-8-NOBOM/DiffItem.h"], .detected(.utf8, hasByteOrderMark: false))
        XCTAssertEqual(detection["Unicode/UCS-2LE/DiffItem.h"], .detected(.utf16LittleEndian, hasByteOrderMark: true))
        XCTAssertEqual(detection["Unicode/UCS-2BE/DiffItem.h"], .detected(.utf16BigEndian, hasByteOrderMark: true))
        // The Japanese legacy fixtures are ambiguous to automatic detection, yet still
        // round-trip because the harness loads them with the folder's explicit encoding.
        XCTAssertEqual(detection["Codepages/CP50220/DiffItem.h"], .ambiguous([.utf8, .iso2022JP]))
        XCTAssertEqual(
            detection["Codepages/CP51932/DiffItem.h"],
            .ambiguous([.shiftJIS, .japaneseEUC, .windows1250, .windows1251, .windows1252, .windows1253, .windows1254, .windows1255])
        )
        XCTAssertEqual(
            detection["Codepages/CP932/DiffItem.h"],
            .ambiguous([.shiftJIS, .windows1251, .windows1252, .windows1253, .windows1254, .windows1255])
        )
        XCTAssertTrue(report.allFixturesByteExact)
    }

    func testSynthesizedLegacyCodePagesRoundTripAndStaySeparate() throws {
        let report = try Self.realReport.get()

        XCTAssertTrue(report.allSynthesizedByteExact, describe(report.failedSynthesizedResults))
        XCTAssertEqual(
            report.synthesizedResults.map(\.relativePath),
            [1250, 1251, 1252, 1253, 1254, 1255].map { "synthesized/CP\($0)/synthesized.txt" }
        )
        XCTAssertFalse(report.results.contains { $0.relativePath.hasPrefix(Harness.synthesizedPathPrefix) })
    }

    func testDiscoverReportsMissingFamilyNestedAndLooseEntries() throws {
        let root = try makeScratchDirectory()
        let codepages = root.appendingPathComponent("Codepages", isDirectory: true)
        let cp1252 = codepages.appendingPathComponent("CP1252", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cp1252.appendingPathComponent("Nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("a\r\nb".utf8).write(to: cp1252.appendingPathComponent("ok.txt"))
        try Data("loose".utf8).write(to: codepages.appendingPathComponent("loose.txt"))
        let unknown = codepages.appendingPathComponent("CP9999", isDirectory: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: unknown.appendingPathComponent("x.txt"))

        let catalog = try Harness.discover(dataRoot: root)
        XCTAssertEqual(catalog.fixtures.map(\.relativePath), ["Codepages/CP1252/ok.txt"])
        XCTAssertEqual(
            catalog.unsupportedFixtures,
            [
                .init(relativePath: "Codepages/CP1252/Nested/", reason: .unrecognizedFixtureFolder),
                .init(relativePath: "Codepages/CP9999/x.txt", reason: .unrecognizedFixtureFolder),
                .init(relativePath: "Codepages/loose.txt", reason: .unrecognizedFixtureFolder),
                .init(relativePath: "Unicode/", reason: .missingFixtureFamily)
            ])
    }

    func testDiscoverThrowsWhenEveryFamilyIsMissing() throws {
        let root = try makeScratchDirectory()
        XCTAssertThrowsError(try Harness.discover(dataRoot: root)) { error in
            XCTAssertEqual(error as? Harness.HarnessError, .dataRootNotFound)
        }
    }

    func testFixtureLimitCountsUnsupportedEntries() throws {
        let root = try makeScratchDirectory()
        let unknown = root.appendingPathComponent("Codepages/CP9999", isDirectory: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        for index in 0...Harness.maximumFixtures {
            try Data().write(to: unknown.appendingPathComponent("f\(index).txt"))
        }
        XCTAssertThrowsError(try Harness.discover(dataRoot: root)) { error in
            XCTAssertEqual(error as? Harness.HarnessError, .fixtureLimitExceeded(maximum: Harness.maximumFixtures))
        }
    }

    func testKnownUnsupportedCodePagesIncludeEnumeratedSystemPages() {
        let pages = Set(Harness.knownUnsupportedCodePages.map(\.windowsCodePage))
        for page in [20127, 28598, 855, 857, 1361, 10001, 12000, 65000] {
            XCTAssertTrue(pages.contains(page), "\(page)")
        }
    }
}
