import Foundation
import XCTest

@testable import MacMergeCore

final class RenamedFileDetectionTestsRegressions: XCTestCase {
    func testPathCostUsesCanonicalUnicodeAndSelectedCasePolicy() throws {
        let digest = trustedDigest(0x11)
        let canonical = try RenamedFileDetection.detect(
            unmatchedLeft: [candidate("caf\u{E9}.txt", digest: digest)],
            unmatchedRight: [candidate("cafe\u{301}.txt", digest: digest)]
        )
        XCTAssertEqual(canonical.matches.map(\.pathSimilarityCost), [0])

        let sensitive = try RenamedFileDetection.detect(
            unmatchedLeft: [candidate("Folder/File.txt", digest: digest)],
            unmatchedRight: [candidate("folder/file.txt", digest: digest)]
        )
        let insensitive = try RenamedFileDetection.detect(
            unmatchedLeft: [candidate("Folder/File.txt", digest: digest)],
            unmatchedRight: [candidate("folder/file.txt", digest: digest)],
            options: RenamedFileDetectionOptions(pathCaseSensitivity: .insensitive)
        )
        XCTAssertGreaterThan(sensitive.matches[0].pathSimilarityCost, 0)
        XCTAssertEqual(insensitive.matches[0].pathSimilarityCost, 0)
    }

    func testInvalidLimitsAreRejected() {
        let invalidOptions = [
            RenamedFileDetectionOptions(maximumCostMatrixCells: -1),
            RenamedFileDetectionOptions(maximumPathCharacterComparisons: -1),
            RenamedFileDetectionOptions(maximumAssignmentOperations: -1),
            RenamedFileDetectionOptions(maximumNormalizedPathScalars: -1),
            RenamedFileDetectionOptions(maximumNormalizedPathUTF8Bytes: -1),
        ]
        for options in invalidOptions {
            XCTAssertThrowsError(
                try RenamedFileDetection.detect(
                    unmatchedLeft: [],
                    unmatchedRight: [],
                    options: options
                )
            ) { error in
                XCTAssertEqual(error as? RenamedFileDetectionError, .invalidLimits)
            }
        }
    }

    func testPathLimitsApplyBeforeAndAfterCaseNormalization() throws {
        let scalarExpandingPath = "ß"
        let byteExpandingPath = "İ"
        let digest = trustedDigest(0x22)

        XCTAssertThrowsError(
            try RenamedFileDetection.detect(
                unmatchedLeft: [candidate(scalarExpandingPath, digest: digest)],
                unmatchedRight: [],
                options: RenamedFileDetectionOptions(
                    pathCaseSensitivity: .insensitive,
                    maximumNormalizedPathScalars: 1,
                    maximumNormalizedPathUTF8Bytes: 2
                )
            )
        ) { error in
            XCTAssertEqual(error as? RenamedFileDetectionError, .workLimitExceeded)
        }

        XCTAssertThrowsError(
            try RenamedFileDetection.detect(
                unmatchedLeft: [candidate(byteExpandingPath, digest: digest)],
                unmatchedRight: [],
                options: RenamedFileDetectionOptions(
                    pathCaseSensitivity: .insensitive,
                    maximumNormalizedPathScalars: 2,
                    maximumNormalizedPathUTF8Bytes: 2
                )
            )
        ) { error in
            XCTAssertEqual(error as? RenamedFileDetectionError, .workLimitExceeded)
        }

        let result = try RenamedFileDetection.detect(
            unmatchedLeft: [candidate(byteExpandingPath, digest: digest)],
            unmatchedRight: [],
            options: RenamedFileDetectionOptions(
                pathCaseSensitivity: .insensitive,
                maximumNormalizedPathScalars: 2,
                maximumNormalizedPathUTF8Bytes: 3
            )
        )
        XCTAssertEqual(result.unmatchedLeft.map(\.relativePath), [byteExpandingPath])
    }
}

private func candidate(
    _ path: String,
    size: UInt64 = 1,
    digest: FolderContentDigest?
) -> RenamedFileCandidate {
    RenamedFileCandidate(relativePath: path, size: size, contentDigest: digest)
}

private func trustedDigest(_ byte: UInt8) -> FolderContentDigest {
    FolderContentDigest(algorithm: "sha256", bytes: Data(repeating: byte, count: 32))
}
