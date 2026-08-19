import Foundation
import XCTest

@testable import MacMerge

final class CrashDiagnosticStoreTests: XCTestCase {
    func testCrashDiagnosticsRetainNewestValidPayloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = CrashDiagnosticStore(directoryURL: directory, maximumReports: 2)

        try store.save([Data(#"{"report":1}"#.utf8)], recordedAt: Date(timeIntervalSince1970: 1))
        try store.save([Data("not json".utf8)], recordedAt: Date(timeIntervalSince1970: 2))
        try store.save([Data(#"{"report":2}"#.utf8)], recordedAt: Date(timeIntervalSince1970: 3))
        try store.save([Data(#"{"report":3}"#.utf8)], recordedAt: Date(timeIntervalSince1970: 4))

        let reports = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(reports.count, 2)
        let values = try reports.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: Int])["report"]
        }
        XCTAssertEqual(values, [2, 3])
    }

    func testEmptyCrashDeliveryDoesNotCreateDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = CrashDiagnosticStore(directoryURL: directory)

        try store.save([])

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
