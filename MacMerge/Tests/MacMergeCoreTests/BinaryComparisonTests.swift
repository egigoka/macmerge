import Darwin
import Foundation
import MacMergeCore
import XCTest

final class BinaryComparisonTests: XCTestCase {
    private static let trapScenarioEnvironment = "MACMERGE_BINARY_HEX_TRAP_SCENARIO"
    private static let trapTimeoutEnvironment = "MACMERGE_BINARY_HEX_TRAP_TIMEOUT_SECONDS"
    private static let defaultTrapTimeoutSeconds = 15

    func testIdenticalBytesProduceOneExactUnchangedRun() throws {
        let data = Data([0x00, 0x41, 0xFF])

        let result = BinaryComparison.compare(left: data, right: data)

        XCTAssertEqual(result.alignment, .exact)
        XCTAssertEqual(result.alignedByteCount, 3)
        XCTAssertEqual(result.runs.count, 1)
        XCTAssertEqual(result.runs[0].kind, .unchanged)
        XCTAssertEqual(result.runs[0].alignedRange, 0..<3)
        XCTAssertEqual(result.runs[0].leftRange, 0..<3)
        XCTAssertEqual(result.runs[0].rightRange, 0..<3)
        XCTAssertEqual(try XCTUnwrap(result.byte(atAlignedOffset: 1)).leftByte, 0x41)
        XCTAssertNil(result.byte(atAlignedOffset: 3))
    }

    func testReplacementInsertionAndDeletionUseAlignedSourceOffsets() throws {
        let left = Data([0x10, 0x20, 0x30, 0x40, 0x50])
        let right = Data([0x10, 0x21, 0x30, 0xAA, 0x40])

        let result = BinaryComparison.compare(left: left, right: right)

        XCTAssertEqual(result.alignment, .exact)
        XCTAssertEqual(result.runs.map(\.kind), [.unchanged, .modified, .unchanged, .added, .unchanged, .removed])
        assertReconstructsInputs(result)

        let inserted = try XCTUnwrap(result.runs.first { $0.kind == .added })
        let insertedCell = try XCTUnwrap(result.byte(atAlignedOffset: inserted.alignedRange.lowerBound))
        XCTAssertNil(insertedCell.leftOffset)
        XCTAssertNil(insertedCell.leftByte)
        XCTAssertEqual(insertedCell.rightOffset, 3)
        XCTAssertEqual(insertedCell.rightByte, 0xAA)

        let removed = try XCTUnwrap(result.runs.first { $0.kind == .removed })
        let removedCell = try XCTUnwrap(result.byte(atAlignedOffset: removed.alignedRange.lowerBound))
        XCTAssertEqual(removedCell.leftOffset, 4)
        XCTAssertEqual(removedCell.leftByte, 0x50)
        XCTAssertNil(removedCell.rightOffset)
        XCTAssertNil(removedCell.rightByte)
    }

    func testMiddleInsertionKeepsFollowingBytesAligned() {
        let result = BinaryComparison.compare(
            left: Data([0x00, 0x01, 0x02, 0x03]),
            right: Data([0x00, 0xFE, 0x01, 0x02, 0x03])
        )

        XCTAssertEqual(result.runs.map(\.kind), [.unchanged, .added, .unchanged])
        XCTAssertEqual(result.runs[1].leftRange, 1..<1)
        XCTAssertEqual(result.runs[1].rightRange, 1..<2)
        XCTAssertEqual(result.runs[2].leftRange, 1..<4)
        XCTAssertEqual(result.runs[2].rightRange, 2..<5)
        assertReconstructsInputs(result)
    }

    func testAlignmentIsDeterministicForDuplicateBytes() {
        let left = Data([0x41, 0x42, 0x41, 0x42, 0x43])
        let right = Data([0x41, 0x41, 0x42, 0x42, 0x43])

        let expected = BinaryComparison.compare(left: left, right: right)

        for _ in 0..<20 {
            XCTAssertEqual(BinaryComparison.compare(left: left, right: right), expected)
        }
        assertReconstructsInputs(expected)
    }

    func testSmallInputMatrixReconstructsBothSourcesWithContiguousRanges() {
        let inputs = byteSequences(maximumLength: 4)

        for left in inputs {
            for right in inputs {
                let result = BinaryComparison.compare(left: left, right: right)
                XCTAssertEqual(result.alignment, .exact, "left=\(left) right=\(right)")
                assertReconstructsInputs(result)
                assertContiguousRanges(result)
            }
        }
    }

    func testExactAlignmentMatchesIndependentMinimalityOracle() {
        let inputs = byteSequences(maximumLength: 4)

        for left in inputs {
            for right in inputs {
                let result = BinaryComparison.compare(left: left, right: right)
                let longestCommonSubsequenceCount = longestCommonSubsequenceLength(Array(left), Array(right))
                let unchangedCount = result.runs.reduce(into: 0) { count, run in
                    if run.kind == .unchanged { count += run.alignedRange.count }
                }
                let reportedDistance = result.runs.reduce(into: 0) { distance, run in
                    switch run.kind {
                    case .unchanged:
                        break
                    case .modified:
                        distance += run.alignedRange.count * 2
                    case .removed, .added:
                        distance += run.alignedRange.count
                    }
                }

                XCTAssertEqual(
                    unchangedCount,
                    longestCommonSubsequenceCount,
                    "left=\(left) right=\(right) runs=\(result.runs)"
                )
                XCTAssertEqual(
                    reportedDistance,
                    left.count + right.count - (2 * longestCommonSubsequenceCount),
                    "left=\(left) right=\(right) runs=\(result.runs)"
                )
            }
        }
    }

    func testNonzeroDataStartIndicesPreserveRelativeByteOffsets() {
        let left = Data([0xFF, 0x10, 0x20, 0x30]).dropFirst()
        let right = Data([0xEE, 0x10, 0x21, 0x30]).dropFirst()

        let result = BinaryComparison.compare(left: left, right: right)

        XCTAssertEqual(result.runs.map(\.kind), [.unchanged, .modified, .unchanged])
        XCTAssertEqual(result.byte(atAlignedOffset: 1)?.leftOffset, 1)
        XCTAssertEqual(result.byte(atAlignedOffset: 1)?.rightOffset, 1)
        assertReconstructsInputs(result)
    }

    func testBoundedFallbackIsExplicitAndStillClassifiesEveryByte() {
        let options = BinaryComparisonOptions(maximumExactEditDistance: 1, maximumAlignmentWork: 4)
        let result = BinaryComparison.compare(
            left: Data([0x00, 0x01, 0x02, 0x03]),
            right: Data([0x10, 0x11, 0x12, 0x13, 0x14]),
            options: options
        )

        XCTAssertEqual(result.alignment, .boundedFallback)
        XCTAssertEqual(result.runs.map(\.kind), [.modified, .added])
        XCTAssertEqual(result.runs[0].leftRange, 0..<4)
        XCTAssertEqual(result.runs[0].rightRange, 0..<4)
        XCTAssertEqual(result.runs[1].leftRange, 4..<4)
        XCTAssertEqual(result.runs[1].rightRange, 4..<5)
        assertReconstructsInputs(result)
    }

    func testExactDistanceBoundaryIsIndependentOfWorkLimit() {
        let left = Data([0x00])
        let right = Data([0x01])

        XCTAssertEqual(
            BinaryComparison.compare(
                left: left,
                right: right,
                options: BinaryComparisonOptions(maximumExactEditDistance: 2, maximumAlignmentWork: 100)
            ).alignment,
            .exact
        )
        XCTAssertEqual(
            BinaryComparison.compare(
                left: left,
                right: right,
                options: BinaryComparisonOptions(maximumExactEditDistance: 1, maximumAlignmentWork: 100)
            ).alignment,
            .boundedFallback
        )
    }

    func testAlignmentWorkBoundaryIsIndependentOfDistanceLimit() {
        let left = Data([0x00])
        let right = Data([0x01])

        XCTAssertEqual(
            BinaryComparison.compare(
                left: left,
                right: right,
                options: BinaryComparisonOptions(maximumExactEditDistance: 100, maximumAlignmentWork: 6)
            ).alignment,
            .exact
        )
        XCTAssertEqual(
            BinaryComparison.compare(
                left: left,
                right: right,
                options: BinaryComparisonOptions(maximumExactEditDistance: 100, maximumAlignmentWork: 5)
            ).alignment,
            .boundedFallback
        )
    }

    func testHexRowsHaveStableOffsetsPlaceholdersAndASCII() throws {
        let result = BinaryComparison.compare(
            left: Data([0x41, 0x00, 0x7E, 0xFF]),
            right: Data([0x41, 0x42, 0x00, 0x7E, 0xFF])
        )
        let presentation = BinaryHexPresentation(comparison: result, bytesPerRow: 4)

        XCTAssertEqual(presentation.rowCount, 2)
        let first = try XCTUnwrap(presentation.row(at: 0))
        XCTAssertEqual(first.alignedOffsetText, "00000000")
        XCTAssertEqual(first.leftOffsetText, "00000000")
        XCTAssertEqual(first.rightOffsetText, "00000000")
        XCTAssertEqual(first.leftHex, "41 -- 00 7E")
        XCTAssertEqual(first.rightHex, "41 42 00 7E")
        XCTAssertEqual(first.leftASCII, "A .~")
        XCTAssertEqual(first.rightASCII, "AB.~")

        let second = try XCTUnwrap(presentation.row(at: 1))
        XCTAssertEqual(second.leftOffset, 3)
        XCTAssertEqual(second.rightOffset, 4)
        XCTAssertEqual(second.leftHex, "FF")
        XCTAssertEqual(second.rightHex, "FF")
        XCTAssertEqual(second.leftASCII, ".")
        XCTAssertEqual(presentation.rows(in: -2..<10), [first, second])
        XCTAssertNil(presentation.row(at: 2))
    }

    func testRowsStartingInsideLongInsertionAndDeletionKeepCursorOffsets() throws {
        let base = Data(0..<20)
        let inserted = BinaryHexPresentation(
            comparison: BinaryComparison.compare(
                left: base,
                right: Data(repeating: 0xAA, count: 20) + base
            ),
            bytesPerRow: 8
        )
        let insertedSecondRow = try XCTUnwrap(inserted.row(at: 1))
        XCTAssertEqual(insertedSecondRow.leftOffset, 0)
        XCTAssertEqual(insertedSecondRow.rightOffset, 8)
        XCTAssertEqual(insertedSecondRow.leftHex, "-- -- -- -- -- -- -- --")
        XCTAssertEqual(insertedSecondRow.rightHex, "AA AA AA AA AA AA AA AA")

        let deleted = BinaryHexPresentation(
            comparison: BinaryComparison.compare(
                left: Data(repeating: 0xBB, count: 20) + base,
                right: base
            ),
            bytesPerRow: 8
        )
        let deletedSecondRow = try XCTUnwrap(deleted.row(at: 1))
        XCTAssertEqual(deletedSecondRow.leftOffset, 8)
        XCTAssertEqual(deletedSecondRow.rightOffset, 0)
        XCTAssertEqual(deletedSecondRow.leftHex, "BB BB BB BB BB BB BB BB")
        XCTAssertEqual(deletedSecondRow.rightHex, "-- -- -- -- -- -- -- --")
    }

    func testPathologicalBytesPerRowUsesEffectiveCellCap() throws {
        let data = Data((0..<256).map(UInt8.init))
        let presentation = BinaryHexPresentation(
            comparison: BinaryComparison.compare(left: data, right: data),
            bytesPerRow: Int.max
        )

        XCTAssertEqual(presentation.rowCount, 1)
        let row = try XCTUnwrap(presentation.row(at: 0))
        XCTAssertEqual(row.cells.count, 256)
        XCTAssertEqual(row.cells.first?.alignedOffset, 0)
        XCTAssertEqual(row.cells.last?.alignedOffset, 255)
        XCTAssertEqual(presentation.rows(in: 0..<Int.max), [row])
    }

    func testPathologicalBytesPerRowOneOverEffectiveCellCapTriggersPrecondition() throws {
        let scenario = "oversized-bytes-per-row"
        if Self.isTrapChild(for: scenario) {
            let data = Data(repeating: 0xAA, count: 257)
            _ = BinaryHexPresentation(
                comparison: BinaryComparison.compare(left: data, right: data),
                bytesPerRow: Int.max
            )
            XCTFail("Oversized bytes-per-row value did not trigger its precondition")
            return
        }

        try assertPreconditionTrap(
            testName: "testPathologicalBytesPerRowOneOverEffectiveCellCapTriggersPrecondition",
            scenario: scenario,
            expectedDiagnostic: "Bytes per row exceeds the rendering limit of 256"
        )
    }

    func testNormalBytesPerRowKeepsRequestedRowShape() {
        let data = Data(0..<10)
        let presentation = BinaryHexPresentation(
            comparison: BinaryComparison.compare(left: data, right: data),
            bytesPerRow: 4
        )

        XCTAssertEqual(presentation.rowCount, 3)
        XCTAssertEqual(presentation.rows(in: 0..<3).map(\.alignedOffset), [0, 4, 8])
        XCTAssertEqual(presentation.rows(in: 0..<3).map(\.cells.count), [4, 4, 2])
    }

    func testRowsRequestAtMaximumReturnsAllRows() {
        let data = Data(repeating: 0xAA, count: 1_024)
        let presentation = BinaryHexPresentation(
            comparison: BinaryComparison.compare(left: data, right: data),
            bytesPerRow: 1
        )

        let rows = presentation.rows(in: 0..<1_024)

        XCTAssertEqual(rows.count, 1_024)
        XCTAssertEqual(rows.first?.index, 0)
        XCTAssertEqual(rows.last?.index, 1_023)
    }

    func testRowsRequestOneOverMaximumTriggersPrecondition() throws {
        let scenario = "oversized-row-request"
        if Self.isTrapChild(for: scenario) {
            let data = Data(repeating: 0xAA, count: 1_025)
            let presentation = BinaryHexPresentation(
                comparison: BinaryComparison.compare(left: data, right: data),
                bytesPerRow: 1
            )
            _ = presentation.rows(in: 0..<1_025)
            XCTFail("Oversized row request did not trigger its precondition")
            return
        }

        try assertPreconditionTrap(
            testName: "testRowsRequestOneOverMaximumTriggersPrecondition",
            scenario: scenario,
            expectedDiagnostic: "Row request exceeds the rendering limit of 1024"
        )
    }

    private func assertReconstructsInputs(
        _ result: BinaryComparisonResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cells = (0..<result.alignedByteCount).compactMap(result.byte(atAlignedOffset:))
        XCTAssertEqual(Data(cells.compactMap(\.leftByte)), result.leftData, file: file, line: line)
        XCTAssertEqual(Data(cells.compactMap(\.rightByte)), result.rightData, file: file, line: line)
        XCTAssertEqual(cells.map(\.alignedOffset), Array(0..<result.alignedByteCount), file: file, line: line)
        XCTAssertEqual(cells.compactMap(\.leftOffset), Array(0..<result.leftData.count), file: file, line: line)
        XCTAssertEqual(cells.compactMap(\.rightOffset), Array(0..<result.rightData.count), file: file, line: line)
        for cell in cells {
            switch cell.kind {
            case .unchanged:
                XCTAssertNotNil(cell.leftByte, file: file, line: line)
                XCTAssertEqual(cell.leftByte, cell.rightByte, file: file, line: line)
            case .modified:
                XCTAssertNotNil(cell.leftByte, file: file, line: line)
                XCTAssertNotNil(cell.rightByte, file: file, line: line)
            case .removed:
                XCTAssertNotNil(cell.leftByte, file: file, line: line)
                XCTAssertNil(cell.rightByte, file: file, line: line)
            case .added:
                XCTAssertNil(cell.leftByte, file: file, line: line)
                XCTAssertNotNil(cell.rightByte, file: file, line: line)
            }
        }
    }

    private func assertContiguousRanges(
        _ result: BinaryComparisonResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var alignedOffset = 0
        var leftOffset = 0
        var rightOffset = 0
        for run in result.runs {
            XCTAssertEqual(run.alignedRange.lowerBound, alignedOffset, file: file, line: line)
            XCTAssertEqual(run.leftRange.lowerBound, leftOffset, file: file, line: line)
            XCTAssertEqual(run.rightRange.lowerBound, rightOffset, file: file, line: line)
            XCTAssertEqual(run.alignedRange.count, max(run.leftRange.count, run.rightRange.count), file: file, line: line)
            alignedOffset = run.alignedRange.upperBound
            leftOffset = run.leftRange.upperBound
            rightOffset = run.rightRange.upperBound
        }
        XCTAssertEqual(alignedOffset, result.alignedByteCount, file: file, line: line)
        XCTAssertEqual(leftOffset, result.leftData.count, file: file, line: line)
        XCTAssertEqual(rightOffset, result.rightData.count, file: file, line: line)
    }

    private static func isTrapChild(for scenario: String) -> Bool {
        guard let sentinel = ProcessInfo.processInfo.environment[trapScenarioEnvironment] else {
            return false
        }
        let components = sentinel.split(separator: ":", maxSplits: 2)
        return components.count == 3
            && components[0] == scenario
            && Int32(components[1]) == Darwin.getppid()
            && UUID(uuidString: String(components[2])) != nil
    }

    private func assertPreconditionTrap(
        testName: String,
        scenario: String,
        expectedDiagnostic: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let diagnosticsURL = FileManager.default.temporaryDirectory.appending(
            path: "MacMergeBinaryHexTrap-\(UUID().uuidString).log"
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
            "MacMergeCoreTests.BinaryComparisonTests/\(testName)",
            Bundle(for: Self.self).bundleURL.path
        ]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: Self.trapScenarioEnvironment)
        environment[Self.trapScenarioEnvironment] = "\(scenario):\(Darwin.getpid()):\(UUID().uuidString)"
        process.environment = environment
        process.standardOutput = diagnostics
        process.standardError = diagnostics
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        guard terminated.wait(timeout: .now() + Self.trapTimeout) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            XCTFail("Precondition trap child exceeded bounded timeout: \(scenario)", file: file, line: line)
            return
        }
        process.waitUntilExit()
        try diagnostics.synchronize()
        try diagnostics.seek(toOffset: 0)
        let output = try diagnostics.readToEnd() ?? Data()
        let diagnosticText = String(decoding: output, as: UTF8.self)

        XCTAssertEqual(process.terminationReason, .uncaughtSignal, file: file, line: line)
        XCTAssertTrue(
            [SIGABRT, SIGILL, SIGTRAP].contains(process.terminationStatus),
            "Unexpected fatal signal \(process.terminationStatus): \(diagnosticText)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            diagnosticText.contains(expectedDiagnostic),
            "Unexpected precondition diagnostic: \(diagnosticText)",
            file: file,
            line: line
        )
    }

    private static var trapTimeout: DispatchTimeInterval {
        guard
            let configured = ProcessInfo.processInfo.environment[trapTimeoutEnvironment],
            let seconds = Int(configured),
            (1...300).contains(seconds)
        else {
            return .seconds(defaultTrapTimeoutSeconds)
        }
        return .seconds(seconds)
    }

    private func byteSequences(maximumLength: Int) -> [Data] {
        var sequences = [Data()]
        for length in 1...maximumLength {
            for bits in 0..<(1 << length) {
                sequences.append(Data((0..<length).map { UInt8((bits >> $0) & 1) }))
            }
        }
        return sequences
    }

    private func longestCommonSubsequenceLength(_ left: [UInt8], _ right: [UInt8]) -> Int {
        var previous = [Int](repeating: 0, count: right.count + 1)
        for leftByte in left {
            var current = [Int](repeating: 0, count: right.count + 1)
            for (rightIndex, rightByte) in right.enumerated() {
                if leftByte == rightByte {
                    current[rightIndex + 1] = previous[rightIndex] + 1
                } else {
                    current[rightIndex + 1] = max(previous[rightIndex + 1], current[rightIndex])
                }
            }
            previous = current
        }
        return previous[right.count]
    }
}
