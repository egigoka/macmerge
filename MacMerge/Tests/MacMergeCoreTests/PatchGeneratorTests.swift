import CXDiff
import Foundation
@testable import MacMergeCore
import XCTest

final class PatchGeneratorTests: XCTestCase {
    func testReplacementProducesApplicableUnifiedDiff() throws {
        let oldText = "alpha\nold\nomega\n"
        let newText = "alpha\nnew\nomega\n"

        let generated = try PatchGenerator.generate(old: oldText, new: newText)

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1,3 +1,3 @@",
                " alpha",
                "-old",
                "+new",
                " omega"
            ))
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testInsertionAndDeletionUseZeroLengthRanges() throws {
        let withoutMiddle = "alpha\nomega\n"
        let withMiddle = "alpha\nbeta\nomega\n"
        let options = PatchGeneratorOptions(contextLines: 0)

        let insertion = try PatchGenerator.generate(
            old: withoutMiddle,
            new: withMiddle,
            options: options
        )
        let deletion = try PatchGenerator.generate(
            old: withMiddle,
            new: withoutMiddle,
            options: options
        )

        XCTAssertEqual(
            insertion,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1,0 +2 @@",
                "+beta"
            ))
        XCTAssertEqual(
            deletion,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -2 +1,0 @@",
                "-beta"
            ))
        try assertPatchApplies(insertion, oldText: withoutMiddle, newText: withMiddle)
        try assertPatchApplies(deletion, oldText: withMiddle, newText: withoutMiddle)
    }

    func testBoundaryInsertionsAndDeletionsUseBOFAndEOFAnchors() throws {
        let middle = "middle\n"
        let cases: [(old: String, new: String, range: String, body: String)] = [
            (middle, "first\n" + middle, "@@ -0,0 +1 @@", "+first"),
            (middle, middle + "last\n", "@@ -1,0 +2 @@", "+last"),
            ("first\n" + middle, middle, "@@ -1 +0,0 @@", "-first"),
            (middle + "last\n", middle, "@@ -2 +1,0 @@", "-last")
        ]

        for testCase in cases {
            let generated = try PatchGenerator.generate(
                old: testCase.old,
                new: testCase.new,
                options: PatchGeneratorOptions(contextLines: 0)
            )
            XCTAssertEqual(
                generated,
                patchText("--- a/file", "+++ b/file", testCase.range, testCase.body)
            )
            try assertPatchApplies(generated, oldText: testCase.old, newText: testCase.new)
        }
    }

    func testEmptyFilesUseZeroOriginRangesAndEqualFilesProduceNoPatch() throws {
        let inserted = try PatchGenerator.generate(
            old: "",
            new: "alpha\n",
            options: PatchGeneratorOptions(contextLines: 0)
        )
        let deleted = try PatchGenerator.generate(
            old: "alpha\n",
            new: "",
            options: PatchGeneratorOptions(contextLines: 0)
        )

        XCTAssertEqual(
            inserted,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -0,0 +1 @@",
                "+alpha"
            ))
        XCTAssertEqual(
            deleted,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1 +0,0 @@",
                "-alpha"
            ))
        XCTAssertEqual(try PatchGenerator.generate(old: "", new: ""), "")
        XCTAssertEqual(try PatchGenerator.generate(old: "same\n", new: "same\n"), "")
        try assertPatchApplies(inserted, oldText: "", newText: "alpha\n")
        try assertPatchApplies(deleted, oldText: "alpha\n", newText: "")
    }

    func testMissingFinalNewlineMarkersFollowEachUnterminatedSide() throws {
        let cases: [(old: String, new: String, body: [String])] = [
            (
                "old",
                "new",
                [
                    "-old",
                    "\\ No newline at end of file",
                    "+new",
                    "\\ No newline at end of file"
                ]
            ),
            (
                "old",
                "new\n",
                [
                    "-old",
                    "\\ No newline at end of file",
                    "+new"
                ]
            ),
            (
                "old\n",
                "new",
                [
                    "-old",
                    "+new",
                    "\\ No newline at end of file"
                ]
            )
        ]

        for testCase in cases {
            let generated = try PatchGenerator.generate(
                old: testCase.old,
                new: testCase.new,
                options: PatchGeneratorOptions(contextLines: 0)
            )
            XCTAssertEqual(
                generated,
                patchText(
                    ["--- a/file", "+++ b/file", "@@ -1 +1 @@"] + testCase.body
                ),
                "old: \(testCase.old.debugDescription), new: \(testCase.new.debugDescription)"
            )
            try assertPatchApplies(generated, oldText: testCase.old, newText: testCase.new)
        }
    }

    func testFinalNewlineOnlyChangesRemainApplicable() throws {
        let cases: [(old: String, new: String, body: [String])] = [
            (
                "same",
                "same\n",
                ["-same", "\\ No newline at end of file", "+same"]
            ),
            (
                "same\n",
                "same",
                ["-same", "+same", "\\ No newline at end of file"]
            )
        ]

        for testCase in cases {
            let generated = try PatchGenerator.generate(
                old: testCase.old,
                new: testCase.new,
                options: PatchGeneratorOptions(contextLines: 0)
            )
            XCTAssertEqual(
                generated,
                patchText(["--- a/file", "+++ b/file", "@@ -1 +1 @@"] + testCase.body)
            )
            try assertPatchApplies(generated, oldText: testCase.old, newText: testCase.new)
        }
    }

    func testCRLFToLFProducesApplicableLineEndingOnlyPatch() throws {
        let oldText = "alpha\r\nbeta\r\n"
        let newText = "alpha\nbeta\n"

        let generated = try PatchGenerator.generate(old: oldText, new: newText)

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1,2 +1,2 @@",
                "-alpha\r",
                "-beta\r",
                "+alpha",
                "+beta"
            ))
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testLFToCRLFProducesApplicableLineEndingOnlyPatch() throws {
        let oldText = "alpha\nbeta\n"
        let newText = "alpha\r\nbeta\r\n"

        let generated = try PatchGenerator.generate(old: oldText, new: newText)

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1,2 +1,2 @@",
                "-alpha",
                "-beta",
                "+alpha\r",
                "+beta\r"
            ))
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testBareCarriageReturnRecordsRemainInApplicableHunkPayload() throws {
        let oldText = "alpha\rold\romega\r"
        let newText = "alpha\rnew\romega\r"

        let generated = try PatchGenerator.generate(old: oldText, new: newText)

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1 +1 @@",
                "-alpha\rold\romega\r",
                "\\ No newline at end of file",
                "+alpha\rnew\romega\r",
                "\\ No newline at end of file"
            ))
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testMixedLineEndingsAndFinalNewlineProduceApplicablePatch() throws {
        let oldText = "same\r\nold\nmiddle\rtail"
        let newText = "same\r\nnew\r\nmiddle\rtail\n"

        let generated = try PatchGenerator.generate(old: oldText, new: newText)

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1,3 +1,3 @@",
                " same\r",
                "-old",
                "-middle\rtail",
                "\\ No newline at end of file",
                "+new\r",
                "+middle\rtail"
            ))
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testNewlineOnlyAndUnterminatedLinesCanBeHunkContext() throws {
        let oldText = "\nold\nshared"
        let newText = "\nnew\nshared"

        let generated = try PatchGenerator.generate(
            old: oldText,
            new: newText,
            options: PatchGeneratorOptions(contextLines: 1)
        )

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1,3 +1,3 @@",
                " ",
                "-old",
                "+new",
                " shared",
                "\\ No newline at end of file"
            ))
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testTouchingContextRangesMergeIntoOneHunk() throws {
        let oldText = "a\nold-one\nc\nd\nold-two\nf\n"
        let newText = "a\nnew-one\nc\nd\nnew-two\nf\n"

        let generated = try PatchGenerator.generate(
            old: oldText,
            new: newText,
            options: PatchGeneratorOptions(contextLines: 1)
        )

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1,6 +1,6 @@",
                " a",
                "-old-one",
                "+new-one",
                " c",
                " d",
                "-old-two",
                "+new-two",
                " f"
            ))
        XCTAssertEqual(generated.components(separatedBy: "@@").count - 1, 2)
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testSeparatedContextRangesRemainDistinctHunks() throws {
        let oldText = "a\nold-one\nc\nd\ne\nold-two\ng\n"
        let newText = "a\nnew-one\nc\nd\ne\nnew-two\ng\n"

        let generated = try PatchGenerator.generate(
            old: oldText,
            new: newText,
            options: PatchGeneratorOptions(contextLines: 1)
        )

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1,3 +1,3 @@",
                " a",
                "-old-one",
                "+new-one",
                " c",
                "@@ -5,3 +5,3 @@",
                " e",
                "-old-two",
                "+new-two",
                " g"
            ))
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testLaterHunkRangesIncludeCumulativeInsertionAndDeletionOffsets() throws {
        let oldText = "a\nremove\nb\nc\nold-value\nd\ne\nremove-later\nf\n"
        let newText = "a\ninsert-one\ninsert-two\nb\nc\nnew-value\nd\ne\nf\n"

        let generated = try PatchGenerator.generate(
            old: oldText,
            new: newText,
            options: PatchGeneratorOptions(contextLines: 0)
        )

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -2 +2,2 @@",
                "-remove",
                "+insert-one",
                "+insert-two",
                "@@ -5 +6 @@",
                "-old-value",
                "+new-value",
                "@@ -8 +8,0 @@",
                "-remove-later"
            ))
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testReverseSwapsInputsPathsAndPatchDirection() throws {
        let oldText = "alpha\nold\nomega\n"
        let newText = "alpha\nnew\nomega\n"
        let options = PatchGeneratorOptions(
            oldPath: "a/original.txt",
            newPath: "b/updated.txt",
            contextLines: 0,
            reverse: true
        )

        let generated = try PatchGenerator.generate(old: oldText, new: newText, options: options)

        XCTAssertEqual(
            generated,
            patchText(
                "--- b/updated.txt",
                "+++ a/original.txt",
                "@@ -2 +2 @@",
                "-new",
                "+old"
            ))
        try assertPatchApplies(
            generated,
            oldText: newText,
            newText: oldText,
            targetName: "updated.txt"
        )
    }

    func testReverseTurnsInsertionsIntoDeletionsAndDeletionsIntoInsertions() throws {
        let withoutMiddle = "alpha\nomega\n"
        let withMiddle = "alpha\nbeta\nomega\n"
        let options = PatchGeneratorOptions(contextLines: 0, reverse: true)

        let reversedInsertion = try PatchGenerator.generate(
            old: withoutMiddle,
            new: withMiddle,
            options: options
        )
        let reversedDeletion = try PatchGenerator.generate(
            old: withMiddle,
            new: withoutMiddle,
            options: options
        )

        XCTAssertEqual(
            reversedInsertion,
            patchText(
                "--- b/file",
                "+++ a/file",
                "@@ -2 +1,0 @@",
                "-beta"
            ))
        XCTAssertEqual(
            reversedDeletion,
            patchText(
                "--- b/file",
                "+++ a/file",
                "@@ -1,0 +2 @@",
                "+beta"
            ))
        try assertPatchApplies(reversedInsertion, oldText: withMiddle, newText: withoutMiddle)
        try assertPatchApplies(reversedDeletion, oldText: withoutMiddle, newText: withMiddle)
    }

    func testMaximumContextDoesNotOverflowAndIncludesWholeDocument() throws {
        let oldText = "alpha\nold\nomega\n"
        let newText = "alpha\nnew\nomega\n"

        let generated = try PatchGenerator.generate(
            old: oldText,
            new: newText,
            options: PatchGeneratorOptions(contextLines: .max)
        )

        XCTAssertEqual(
            generated,
            patchText(
                "--- a/file",
                "+++ b/file",
                "@@ -1,3 +1,3 @@",
                " alpha",
                "-old",
                "+new",
                " omega"
            ))
        try assertPatchApplies(generated, oldText: oldText, newText: newText)
    }

    func testOutputBoundAcceptsExactUTF8SizeAndRejectsSmallerLimits() throws {
        let oldText = "old\n"
        let newText = "n\u{00E9}w\n"
        let generated = try PatchGenerator.generate(old: oldText, new: newText)
        let exactSize = generated.utf8.count

        XCTAssertEqual(
            try PatchGenerator.generate(
                old: oldText,
                new: newText,
                options: PatchGeneratorOptions(maximumOutputBytes: exactSize)
            ),
            generated
        )
        for limit in [0, exactSize - 1] {
            XCTAssertThrowsError(
                try PatchGenerator.generate(
                    old: oldText,
                    new: newText,
                    options: PatchGeneratorOptions(maximumOutputBytes: limit)
                )
            ) { error in
                XCTAssertEqual(error as? PatchGeneratorError, .outputTooLarge(maximumBytes: limit))
            }
        }
        XCTAssertEqual(
            try PatchGenerator.generate(
                old: oldText,
                new: oldText,
                options: PatchGeneratorOptions(maximumOutputBytes: 0)
            ),
            ""
        )
    }

    func testLineCountPreflightRejectsOversizedOldAndNewInputs() {
        let maximumLines = Int(MMX_MAX_LINE_COUNT)
        let expectedError = LineDiffError.tooManyLines(maximumLines: maximumLines)
        let oversizedInputs = [
            String(repeating: "\n", count: maximumLines + 1),
            String(repeating: "\n", count: maximumLines) + "unterminated"
        ]

        for oversized in oversizedInputs {
            for inputs in [(old: oversized, new: ""), (old: "", new: oversized)] {
                XCTAssertThrowsError(
                    try PatchGenerator.generate(old: inputs.old, new: inputs.new)
                ) { error in
                    XCTAssertEqual(error as? LineDiffError, expectedError)
                }
            }
        }
    }

    func testLineCountValidatorDirectlyAcceptsExactLimitAndRejectsLimitPlusOne() throws {
        let maximumLines = 3
        let exactInputs = [
            String(repeating: "\n", count: maximumLines),
            String(repeating: "\n", count: maximumLines - 1) + "unterminated"
        ]
        let oversizedInputs = [
            String(repeating: "\n", count: maximumLines + 1),
            String(repeating: "\n", count: maximumLines) + "unterminated"
        ]
        let expectedError = LineDiffError.tooManyLines(maximumLines: maximumLines)

        for input in exactInputs {
            XCTAssertNoThrow(
                try PatchGenerator.validateRecordCount(input, maximumLines: maximumLines)
            )
        }
        for input in oversizedInputs {
            XCTAssertThrowsError(
                try PatchGenerator.validateRecordCount(input, maximumLines: maximumLines)
            ) { error in
                XCTAssertEqual(error as? LineDiffError, expectedError)
            }
        }
    }

    func testLineCountPreflightTreatsEmptyAndCROnlyInputsAsAtMostOneRecord() throws {
        XCTAssertEqual(try PatchGenerator.generate(old: "", new: ""), "")

        let carriageReturns = String(repeating: "\r", count: Int(MMX_MAX_LINE_COUNT) + 1)
        XCTAssertEqual(
            try PatchGenerator.generate(old: carriageReturns, new: carriageReturns),
            ""
        )
    }

    func testNegativeOptionBoundsAreRejected() {
        XCTAssertThrowsError(
            try PatchGenerator.generate(
                old: "old",
                new: "new",
                options: PatchGeneratorOptions(contextLines: -1)
            )
        ) { error in
            XCTAssertEqual(error as? PatchGeneratorError, .invalidContextLines(-1))
        }
        XCTAssertThrowsError(
            try PatchGenerator.generate(
                old: "old",
                new: "new",
                options: PatchGeneratorOptions(maximumOutputBytes: -1)
            )
        ) { error in
            XCTAssertEqual(error as? PatchGeneratorError, .invalidMaximumOutputBytes(-1))
        }
    }

    func testInvalidOptionsAreRejectedEvenWhenInputsAreEqual() {
        let cases: [(options: PatchGeneratorOptions, error: PatchGeneratorError)] = [
            (PatchGeneratorOptions(contextLines: -1), .invalidContextLines(-1)),
            (PatchGeneratorOptions(maximumOutputBytes: -1), .invalidMaximumOutputBytes(-1)),
            (PatchGeneratorOptions(oldPath: ""), .invalidPath("")),
            (PatchGeneratorOptions(newPath: "new\0path"), .invalidPath("new\0path"))
        ]

        for testCase in cases {
            XCTAssertThrowsError(
                try PatchGenerator.generate(
                    old: "same\n",
                    new: "same\n",
                    options: testCase.options
                )
            ) { error in
                XCTAssertEqual(error as? PatchGeneratorError, testCase.error)
            }
        }
    }

    func testEmptyAndNULPathsAreRejectedOnEitherSide() {
        let cases: [(options: PatchGeneratorOptions, invalidPath: String)] = [
            (PatchGeneratorOptions(oldPath: ""), ""),
            (PatchGeneratorOptions(oldPath: "old\0path"), "old\0path"),
            (PatchGeneratorOptions(newPath: ""), ""),
            (PatchGeneratorOptions(newPath: "new\0path"), "new\0path")
        ]

        for testCase in cases {
            XCTAssertThrowsError(
                try PatchGenerator.generate(
                    old: "old",
                    new: "new",
                    options: testCase.options
                )
            ) { error in
                XCTAssertEqual(error as? PatchGeneratorError, .invalidPath(testCase.invalidPath))
            }
        }
    }

    func testHeaderPathsUseGitCompatibleCQuotingAndRoundTripEveryEscapeClass() throws {
        let cases: [(path: String, header: String)] = [
            ("plain/path.txt", "plain/path.txt"),
            ("space path", "\"space path\""),
            ("\"leading-quote", "\"\\\"leading-quote\""),
            ("back\\slash", "\"back\\\\slash\""),
            ("bell\u{07}path", "\"bell\\apath\""),
            ("backspace\u{08}path", "\"backspace\\bpath\""),
            ("tab\tpath", "\"tab\\tpath\""),
            ("newline\npath", "\"newline\\npath\""),
            ("vertical\u{0B}path", "\"vertical\\vpath\""),
            ("form\u{0C}path", "\"form\\fpath\""),
            ("return\rpath", "\"return\\rpath\""),
            ("control\u{01}path", "\"control\\001path\""),
            ("delete\u{7F}path", "\"delete\\177path\""),
            ("caf\u{00E9}", "\"caf\\303\\251\"")
        ]

        for testCase in cases {
            let generated = try PatchGenerator.generate(
                old: "old\n",
                new: "new\n",
                options: PatchGeneratorOptions(
                    oldPath: testCase.path,
                    newPath: testCase.path,
                    contextLines: 0
                )
            )
            let lines = generated.split(separator: "\n", omittingEmptySubsequences: false)
            let oldHeader = String(lines[0].dropFirst(4))
            let newHeader = String(lines[1].dropFirst(4))

            XCTAssertEqual(oldHeader, testCase.header, testCase.path.debugDescription)
            XCTAssertEqual(newHeader, testCase.header, testCase.path.debugDescription)
            XCTAssertEqual(decodeHeaderPath(oldHeader), testCase.path, testCase.path.debugDescription)
            XCTAssertEqual(decodeHeaderPath(newHeader), testCase.path, testCase.path.debugDescription)
        }
    }

    func testHeaderPathsQuoteWhitespaceAdjacentToHeaderDelimiters() throws {
        let cases: [(path: String, header: String)] = [
            (" leading-space", "\" leading-space\""),
            ("trailing-space ", "\"trailing-space \""),
            ("\tleading-tab", "\"\\tleading-tab\""),
            ("trailing-tab\t", "\"trailing-tab\\t\"")
        ]

        for testCase in cases {
            let generated = try PatchGenerator.generate(
                old: "old\n",
                new: "new\n",
                options: PatchGeneratorOptions(
                    oldPath: testCase.path,
                    newPath: testCase.path,
                    contextLines: 0
                )
            )
            let lines = generated.split(separator: "\n", omittingEmptySubsequences: false)
            let oldHeader = String(lines[0].dropFirst(4))
            let newHeader = String(lines[1].dropFirst(4))

            XCTAssertEqual(oldHeader, testCase.header, testCase.path.debugDescription)
            XCTAssertEqual(newHeader, testCase.header, testCase.path.debugDescription)
            XCTAssertEqual(decodeHeaderPath(oldHeader), testCase.path, testCase.path.debugDescription)
            XCTAssertEqual(decodeHeaderPath(newHeader), testCase.path, testCase.path.debugDescription)
        }
    }

    private func patchText(_ lines: String...) -> String {
        patchText(lines)
    }

    private func patchText(_ lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }

    private func assertPatchApplies(
        _ patch: String,
        oldText: String,
        newText: String,
        targetName: String = "file",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let patchExecutable = "/usr/bin/patch"
        guard FileManager.default.isExecutableFile(atPath: patchExecutable) else {
            throw XCTSkip("/usr/bin/patch is unavailable")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchGeneratorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let targetURL = directory.appendingPathComponent(targetName)
        let patchURL = directory.appendingPathComponent("change.patch")
        try Data(oldText.utf8).write(to: targetURL)
        try Data(patch.utf8).write(to: patchURL)

        let standardError = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: patchExecutable)
        process.arguments = ["-f", "-s", "-p1", "-i", patchURL.path]
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        let errorOutput = String(
            decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard process.terminationStatus == 0 else {
            XCTFail(
                "/usr/bin/patch exited \(process.terminationStatus): \(errorOutput)",
                file: file,
                line: line
            )
            return
        }
        XCTAssertEqual(try Data(contentsOf: targetURL), Data(newText.utf8), file: file, line: line)
    }

    private func decodeHeaderPath(_ header: String) -> String? {
        let source = Array(header.utf8)
        guard source.first == 0x22 else { return header }
        guard source.count >= 2, source.last == 0x22 else { return nil }

        var decoded: [UInt8] = []
        var index = 1
        while index < source.count - 1 {
            let byte = source[index]
            guard byte == 0x5C else {
                guard byte >= 0x20, byte <= 0x7E, byte != 0x22 else { return nil }
                decoded.append(byte)
                index += 1
                continue
            }

            index += 1
            guard index < source.count - 1 else { return nil }
            switch source[index] {
            case 0x61: decoded.append(0x07)
            case 0x62: decoded.append(0x08)
            case 0x74: decoded.append(0x09)
            case 0x6E: decoded.append(0x0A)
            case 0x76: decoded.append(0x0B)
            case 0x66: decoded.append(0x0C)
            case 0x72: decoded.append(0x0D)
            case 0x22: decoded.append(0x22)
            case 0x5C: decoded.append(0x5C)
            case 0x30...0x37:
                guard index + 2 < source.count - 1,
                    source[index + 1] >= 0x30, source[index + 1] <= 0x37,
                    source[index + 2] >= 0x30, source[index + 2] <= 0x37
                else { return nil }
                decoded.append(
                    (source[index] - 0x30) << 6
                        | (source[index + 1] - 0x30) << 3
                        | (source[index + 2] - 0x30)
                )
                index += 2
            default:
                return nil
            }
            index += 1
        }
        return String(bytes: decoded, encoding: .utf8)
    }
}
