import CXDiff
import Foundation
import XCTest

@testable import MacMergeCore

final class ComparisonOpenRequestTests: XCTestCase {
    func testSourceRedactedDescriptionsNeverExposePayloadSecrets() throws {
        let secrets = ["secret-path", "secret-label", "secret-text", "secret-id", "secret-host", "secret-token"]
        let sources: [(ComparisonOpenSource, String)] = [
            (.localFile(URL(filePath: "/secret-path/file.txt")), "<local-file>"),
            (.localFolder(URL(filePath: "/secret-path/folder", directoryHint: .isDirectory)), "<local-folder>"),
            (.scratchpad(text: "secret-text", label: "secret-label"), "<scratchpad>"),
            (
                .clipboard(
                    try ClipboardSnapshot(
                        text: "secret-text",
                        sourceLabel: "secret-label",
                        stableID: "secret-id"
                    )
                ),
                "<clipboard-snapshot>"
            ),
            (
                .remoteWebPage(URL(string: "https://secret-host.example/path?token=secret-token#secret-id")!),
                "<remote-webpage>"
            )
        ]

        for (source, expected) in sources {
            XCTAssertEqual(source.redactedDescription, expected)
            for secret in secrets {
                XCTAssertFalse(source.redactedDescription.contains(secret), "Leaked \(secret) from \(expected)")
            }
        }
    }

    func testTwoWayRequestExposesLeftAndRightWithoutMiddleOrBase() throws {
        let request = ComparisonOpenRequest(
            sides: [
                side(.right, file("right.txt"), readOnly: true),
                side(.left, file("left.txt"))
            ],
            modeSelection: .explicit(.text)
        )

        XCTAssertFalse(request.isThreeWay)
        XCTAssertEqual(request.leftSide?.source, file("left.txt"))
        XCTAssertNil(request.middleSide)
        XCTAssertNil(request.baseSide)
        XCTAssertEqual(request.rightSide?.source, file("right.txt"))

        let plan = try ComparisonOpenRequestPlanner.plan(request)
        XCTAssertEqual(plan.sides.map(\.position), [.left, .right])
        XCTAssertFalse(plan.isThreeWay)
        XCTAssertNil(plan.middleSide)
        XCTAssertNil(plan.baseSide)
        XCTAssertTrue(try XCTUnwrap(plan.rightSide).effectiveReadOnly)
    }

    func testThreeWayRequestMapsMiddleToBaseAndCanonicalizesSides() throws {
        let request = ComparisonOpenRequest(
            sides: [
                side(.right, file("right.txt")),
                side(.left, file("left.txt")),
                side(.middle, file("base.txt"), readOnly: true)
            ],
            modeSelection: .explicit(.text)
        )

        XCTAssertTrue(request.isThreeWay)
        XCTAssertEqual(request.middleSide, request.baseSide)
        XCTAssertEqual(request.baseSide?.source, file("base.txt"))

        let plan = try ComparisonOpenRequestPlanner.plan(request)
        XCTAssertEqual(plan.sides.map(\.position), [.left, .middle, .right])
        XCTAssertTrue(plan.isThreeWay)
        XCTAssertEqual(plan.middleSide, plan.baseSide)
        XCTAssertEqual(plan.baseSide?.source, file("base.txt"))
        XCTAssertTrue(try XCTUnwrap(plan.baseSide).effectiveReadOnly)
    }

    func testSideArityDuplicatesAndInvalidSetsAreRejected() {
        for count in [0, 1, 4] {
            let positions: [ComparisonOpenSidePosition] = [.left, .middle, .right, .left]
            let request = ComparisonOpenRequest(
                sides: (0..<count).map { side(positions[$0], file("input-\($0).txt")) },
                modeSelection: .explicit(.text)
            )
            assertOpenError(.invalidSideCount(count)) {
                try ComparisonOpenRequestPlanner.plan(request)
            }
        }

        let duplicate = ComparisonOpenRequest(
            sides: [side(.left, file("left.txt")), side(.left, file("other.txt"))],
            modeSelection: .explicit(.text)
        )
        assertOpenError(.duplicateSide(.left)) {
            try ComparisonOpenRequestPlanner.plan(duplicate)
        }

        let invalidSet = ComparisonOpenRequest(
            sides: [side(.left, file("left.txt")), side(.middle, file("middle.txt"))],
            modeSelection: .explicit(.text)
        )
        assertOpenError(.invalidSideSet([.left, .middle])) {
            try ComparisonOpenRequestPlanner.plan(invalidSet)
        }
    }

    func testSwappingMovesCompletePayloadsIssuesDefaultIdentityAndPreservesRequestMetadata() throws {
        let originalIdentity = identity(1)
        let swappedIdentity = identity(2)
        let modeOptions = ComparisonOpenModeOptions.text(
            twoWay: LineDiffOptions(ignoreCase: true),
            threeWay: ThreeWayTextMergeOptions()
        )
        let filenameFilter = ComparisonOpenFilenameFilter(
            rules: [.init(.exclude, pattern: .glob("*.tmp"))]
        )
        let transforms = ComparisonOpenTransforms(
            unpacker: .init(ruleIdentifier: "archive-v1"),
            prediffer: .init(ruleIdentifier: "normalize-v1")
        )
        let projectSaveIntent = ComparisonOpenProjectSaveIntent(
            destinationURL: URL(filePath: "/projects/swap.macmerge"),
            existingFilePolicy: .replaceExisting
        )
        let limits = ComparisonOpenRequestLimits(maximumLabelUTF8Bytes: 99)
        let request = ComparisonOpenRequest(
            identity: originalIdentity,
            left: file("left.txt"),
            middle: file("base.txt"),
            right: file("right.txt"),
            leftReadOnly: false,
            middleReadOnly: true,
            rightReadOnly: false,
            modeSelection: .explicit(.text),
            modeOptions: modeOptions,
            recursive: true,
            filenameFilter: filenameFilter,
            transforms: transforms,
            projectSaveIntent: projectSaveIntent,
            limits: limits
        )

        let swapped = try request.swapping(.left, .middle)

        XCTAssertNotEqual(swapped.identity, originalIdentity)
        XCTAssertEqual(swapped.leftSide?.source, file("base.txt"))
        XCTAssertEqual(swapped.leftSide?.readOnly, true)
        XCTAssertEqual(swapped.baseSide?.source, file("left.txt"))
        XCTAssertEqual(swapped.baseSide?.readOnly, false)
        XCTAssertEqual(swapped.rightSide, request.rightSide)
        XCTAssertEqual(swapped.modeSelection, request.modeSelection)
        XCTAssertEqual(swapped.modeOptions, modeOptions)
        XCTAssertEqual(swapped.recursive, request.recursive)
        XCTAssertEqual(swapped.filenameFilter, filenameFilter)
        XCTAssertEqual(swapped.transforms, transforms)
        XCTAssertEqual(swapped.projectSaveIntent, projectSaveIntent)
        XCTAssertEqual(swapped.limits, limits)

        let refreshed = try request.swapping(.left, .left, identity: swappedIdentity)
        XCTAssertEqual(refreshed.identity, swappedIdentity)
        XCTAssertEqual(
            ComparisonOpenRequest(
                identity: originalIdentity,
                sides: refreshed.sides,
                modeSelection: refreshed.modeSelection,
                modeOptions: refreshed.modeOptions,
                recursive: refreshed.recursive,
                filenameFilter: refreshed.filenameFilter,
                transforms: refreshed.transforms,
                projectSaveIntent: refreshed.projectSaveIntent,
                limits: refreshed.limits
            ),
            request
        )

        let twoWay = ComparisonOpenRequest(left: file("left.txt"), right: file("right.txt"))
        assertOpenError(.missingSide(.middle)) {
            try twoWay.swapping(.left, .middle)
        }
    }

    func testTSVInferenceSelectsTableAndTabParsingForTwoAndThreeWay() throws {
        let twoWay = ComparisonOpenRequest(left: file("left.tsv"), right: file("right.tsv"))
        let threeWay = ComparisonOpenRequest(
            left: file("left.tsv"),
            middle: file("base.tsv"),
            right: file("right.tsv")
        )

        let twoWayPlan = try ComparisonOpenRequestPlanner.plan(twoWay)
        XCTAssertEqual(twoWayPlan.modeResolution, .init(mode: .table, basis: .recognizedFileExtensions))
        guard case .table(let twoWayParsing, _, let retainedThreeWay) = twoWayPlan.modeOptions else {
            return XCTFail("Expected table options")
        }
        XCTAssertEqual(twoWayParsing, .tabSeparated)
        XCTAssertEqual(retainedThreeWay, .default)

        let threeWayPlan = try ComparisonOpenRequestPlanner.plan(threeWay)
        XCTAssertEqual(threeWayPlan.modeResolution, .init(mode: .table, basis: .recognizedFileExtensions))
        guard case .table(let parsing, _, let activeThreeWay) = threeWayPlan.modeOptions else {
            return XCTFail("Expected table options")
        }
        XCTAssertEqual(parsing, .tabSeparated)
        XCTAssertEqual(activeThreeWay.parsingOptions, .tabSeparated)
    }

    func testEveryRecognizedExtensionInfersItsDocumentedModeCaseInsensitively() throws {
        let cases: [(ComparisonProject.Mode, ComparisonOpenModeResolutionBasis, [String])] = [
            (.image, .recognizedFileExtensions, ["bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff"]),
            (.table, .recognizedFileExtensions, ["csv", "tsv"]),
            (.webpage, .recognizedFileExtensions, ["htm", "html", "shtml", "xhtml"]),
            (
                .binary,
                .recognizedFileExtensions,
                [
                    "7z", "a", "app", "bin", "bz2", "class", "dmg", "doc", "docx", "dylib", "eot", "epub", "exe", "gz", "ico", "jar",
                    "macho", "mov", "mp3", "mp4", "o", "otf", "pdf", "pkg", "ppt", "pptx", "rar", "so", "tar", "ttf", "wav", "webp",
                    "woff", "woff2", "xls", "xlsx", "xz", "zip"
                ]
            ),
            (
                .text,
                .textFallback,
                [
                    "adb", "ads", "ascx", "asp", "bat", "bas", "c", "cc", "cfg", "clo", "cmd", "conf", "cpp", "cppm", "cs", "css", "cxx",
                    "d", "di", "diff", "dtd", "f", "f77", "f90", "for", "fs", "fsx", "go", "h", "hh", "hpp", "hxx", "ini", "inl", "ixx",
                    "java", "js", "json", "jsx", "log", "lua", "m", "markdown", "md", "mkd", "mkdn", "mm", "nsh", "nsi", "patch", "php",
                    "pl", "pm", "properties", "ps1", "psd1", "psm1", "py", "rb", "rc", "rs", "rst", "scss", "sh", "sql", "strings", "swift",
                    "tcl", "tex", "toml", "ts", "tsx", "txt", "v", "vb", "vbs", "vhd", "vhdl", "vue", "xml", "yaml", "yml"
                ]
            )
        ]

        for (mode, basis, extensions) in cases {
            for fileExtension in extensions {
                let request = ComparisonOpenRequest(
                    left: file("left.\(fileExtension)"),
                    right: file("right.\(fileExtension.uppercased())")
                )
                let plan = try ComparisonOpenRequestPlanner.plan(request)
                XCTAssertEqual(plan.modeResolution, .init(mode: mode, basis: basis), fileExtension)
            }
        }

        for fileExtension in ["", "unknown"] {
            let request = ComparisonOpenRequest(
                left: file(fileExtension.isEmpty ? "left" : "left.\(fileExtension)"),
                right: file(fileExtension.isEmpty ? "right" : "right.\(fileExtension)")
            )
            assertOpenError(.modeInferenceRequiresExplicitSelection) {
                try ComparisonOpenRequestPlanner.plan(request)
            }
        }
    }

    func testClipboardScratchpadAndMixedSourceInferenceIsExplicitAndComplete() throws {
        let textLeft = try ClipboardSnapshot(text: "left")
        let textRight = try ClipboardSnapshot(text: "right")
        let binaryLeft = try ClipboardSnapshot(data: Data([0x01]))
        let binaryRight = try ClipboardSnapshot(data: Data([0x02]))

        for (left, right, mode, basis) in [
            (textLeft, textRight, ComparisonProject.Mode.text, ComparisonOpenModeResolutionBasis.clipboardText),
            (binaryLeft, binaryRight, .binary, .clipboardBinary)
        ] {
            let plan = try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(left: .clipboard(left), right: .clipboard(right))
            )
            XCTAssertEqual(plan.modeResolution, .init(mode: mode, basis: basis))
            XCTAssertTrue(try XCTUnwrap(plan.leftSide).effectiveReadOnly)
            XCTAssertTrue(try XCTUnwrap(plan.rightSide).effectiveReadOnly)
            XCTAssertTrue(plan.materializationRequirements.contains(.clipboardPairValidation))
        }

        for localSource in [file("left.txt"), file("left.unknown")] {
            let plan = try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(left: localSource, right: .scratchpad(text: "right"))
            )
            XCTAssertEqual(plan.modeResolution, .init(mode: .text, basis: .textFallback))
        }

        let conflicting = ComparisonOpenRequest(left: file("left.csv"), right: .scratchpad(text: "right"))
        assertOpenError(.modeInferenceRequiresExplicitSelection) {
            try ComparisonOpenRequestPlanner.plan(conflicting)
        }
        let explicit = ComparisonOpenRequest(
            left: file("left.csv"),
            right: .scratchpad(text: "right"),
            modeSelection: .explicit(.table)
        )
        XCTAssertEqual(
            try ComparisonOpenRequestPlanner.plan(explicit).modeResolution,
            .init(mode: .table, basis: .explicit)
        )

        assertOpenError(.invalidClipboard(.mixedContentKinds)) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(left: .clipboard(textLeft), right: .clipboard(binaryRight))
            )
        }
        assertOpenError(
            .incompatibleSource(side: nil, mode: .automatic, reason: .clipboardRequiresTwoSnapshots)
        ) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(left: .clipboard(textLeft), right: .scratchpad(text: "right"))
            )
        }
    }

    func testRemoteInferenceSelectsWebpageAndRetainsOfflineRequirements() throws {
        let leftURL = URL(string: "https://example.com/left?revision=1#content")!
        let rightURL = URL(string: "http://example.test:8080/right")!
        let request = ComparisonOpenRequest(
            left: .remoteWebPage(leftURL),
            right: .remoteWebPage(rightURL)
        )

        let plan = try ComparisonOpenRequestPlanner.plan(request)

        XCTAssertEqual(plan.modeResolution, .init(mode: .webpage, basis: .remoteWebPage))
        XCTAssertTrue(try XCTUnwrap(plan.leftSide).effectiveReadOnly)
        XCTAssertTrue(try XCTUnwrap(plan.rightSide).effectiveReadOnly)
        XCTAssertTrue(
            plan.materializationRequirements.contains(
                .offlineWebPageContent(side: .left, url: leftURL)
            )
        )
        XCTAssertTrue(
            plan.materializationRequirements.contains(
                .offlineWebPageContent(side: .right, url: rightURL)
            )
        )
        XCTAssertEqual(plan.unsupportedFeatures, [.remoteWebPageLoading])
    }

    func testScratchpadInferenceSelectsTextFallbackAndPreservesMutability() throws {
        let request = ComparisonOpenRequest(
            left: .scratchpad(text: "left", label: "Left"),
            right: .scratchpad(text: "right", label: "Right")
        )

        let plan = try ComparisonOpenRequestPlanner.plan(request)

        XCTAssertEqual(plan.modeResolution, .init(mode: .text, basis: .textFallback))
        XCTAssertFalse(try XCTUnwrap(plan.leftSide).effectiveReadOnly)
        XCTAssertFalse(try XCTUnwrap(plan.rightSide).effectiveReadOnly)
        XCTAssertTrue(plan.materializationRequirements.isEmpty)
    }

    func testInferenceRejectsConflictingSignalsAndMixedTableSyntax() {
        let conflicting = ComparisonOpenRequest(left: file("left.txt"), right: file("right.bin"))
        assertOpenError(.modeInferenceRequiresExplicitSelection) {
            try ComparisonOpenRequestPlanner.plan(conflicting)
        }

        let mixedTableSyntax = ComparisonOpenRequest(left: file("left.csv"), right: file("right.tsv"))
        assertOpenError(.tableParsingRequiresExplicitSettings) {
            try ComparisonOpenRequestPlanner.plan(mixedTableSyntax)
        }
    }

    func testBinaryPlistRequiresExplicitMode() throws {
        let inferred = ComparisonOpenRequest(left: file("left.plist"), right: file("right.plist"))
        assertOpenError(.modeInferenceRequiresExplicitSelection) {
            try ComparisonOpenRequestPlanner.plan(inferred)
        }

        let explicit = ComparisonOpenRequest(
            left: file("left.plist"),
            right: file("right.plist"),
            modeSelection: .explicit(.binary)
        )
        let plan = try ComparisonOpenRequestPlanner.plan(explicit)
        XCTAssertEqual(plan.modeResolution, .init(mode: .binary, basis: .explicit))
    }

    func testExplicitAutomaticModeIsRejected() {
        let request = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.automatic)
        )
        assertOpenError(.explicitAutomaticMode) {
            try ComparisonOpenRequestPlanner.plan(request)
        }
    }

    func testEverySourceIncompatibilityAndModeOptionMismatchIsSpecific() throws {
        let folder = ComparisonOpenSource.localFolder(URL(filePath: "/inputs/folder", directoryHint: .isDirectory))
        let textClipboard = try ClipboardSnapshot(text: "text")
        let binaryClipboard = try ClipboardSnapshot(data: Data([0x01]))
        let remote = ComparisonOpenSource.remoteWebPage(URL(string: "https://example.test/page")!)
        let incompatibilities: [(ComparisonOpenRequest, ComparisonOpenRequestError)] = [
            (
                ComparisonOpenRequest(left: folder, right: file("right.txt")),
                .incompatibleSource(side: nil, mode: .automatic, reason: .mixedFilesAndFolders)
            ),
            (
                ComparisonOpenRequest(left: folder, right: folder, modeSelection: .explicit(.text)),
                .duplicateLocalSource(first: .left, second: .right)
            ),
            (
                ComparisonOpenRequest(left: file("left.txt"), right: file("right.txt"), modeSelection: .explicit(.folder)),
                .incompatibleSource(side: .left, mode: .folder, reason: .folderModeRequiresFolders)
            ),
            (
                ComparisonOpenRequest(left: .scratchpad(text: "left"), right: file("right.bin"), modeSelection: .explicit(.binary)),
                .incompatibleSource(side: .left, mode: .binary, reason: .scratchpadUnsupported)
            ),
            (
                ComparisonOpenRequest(left: remote, right: file("right.txt"), modeSelection: .explicit(.text)),
                .incompatibleSource(side: .left, mode: .text, reason: .remoteWebPageRequiresWebpageMode)
            ),
            (
                ComparisonOpenRequest(
                    left: .clipboard(textClipboard),
                    right: .clipboard(textClipboard),
                    modeSelection: .explicit(.binary)
                ),
                .incompatibleSource(side: nil, mode: .binary, reason: .clipboardTextRequiresTextMode)
            ),
            (
                ComparisonOpenRequest(
                    left: .clipboard(binaryClipboard),
                    right: .clipboard(binaryClipboard),
                    modeSelection: .explicit(.text)
                ),
                .incompatibleSource(side: nil, mode: .text, reason: .clipboardBinaryRequiresBinaryMode)
            )
        ]
        for (request, expected) in incompatibilities {
            assertOpenError(expected) {
                try ComparisonOpenRequestPlanner.plan(request)
            }
        }

        let distinctFolder = ComparisonOpenSource.localFolder(URL(filePath: "/inputs/other", directoryHint: .isDirectory))
        assertOpenError(.incompatibleSource(side: .left, mode: .text, reason: .foldersRequireFolderMode)) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(left: folder, right: distinctFolder, modeSelection: .explicit(.text))
            )
        }

        let optionsByMode: [(ComparisonProject.Mode, ComparisonOpenModeOptions)] = [
            (.text, .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions())),
            (.table, .table(parsing: .commaSeparated, twoWay: .default, threeWay: .default)),
            (.binary, .binary(twoWay: BinaryComparisonOptions(), threeWay: .default)),
            (.image, .image(loading: .default, comparison: .default)),
            (.webpage, .webpage(twoWay: .default, threeWay: .default)),
            (.folder, .folder(scanning: FolderScanOptions(), twoWay: FolderComparisonOptions(), threeWay: .default))
        ]
        for (optionMode, options) in optionsByMode {
            let actualMode: ComparisonProject.Mode = optionMode == .text ? .binary : .text
            let request = ComparisonOpenRequest(
                left: file("left.bin"),
                right: file("right.bin"),
                modeSelection: .explicit(actualMode),
                modeOptions: options
            )
            assertOpenError(.modeOptionsMismatch(expected: actualMode, actual: optionMode)) {
                try ComparisonOpenRequestPlanner.plan(request)
            }
        }
    }

    func testRecursiveAndFilenameFilterOptionsRequireFolderMode() {
        let filter = ComparisonOpenFilenameFilter(rules: [.init(.exclude, pattern: .glob("*.tmp"))])
        assertOpenError(.recursiveOptionRequiresFolderMode) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(
                    left: file("left.txt"),
                    right: file("right.txt"),
                    modeSelection: .explicit(.text),
                    recursive: true
                )
            )
        }
        assertOpenError(.filenameFilterRequiresFolderMode) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(
                    left: file("left.txt"),
                    right: file("right.txt"),
                    modeSelection: .explicit(.text),
                    filenameFilter: filter
                )
            )
        }
    }

    func testThreeWayTextEngineByteCeilingAcceptsExactAndRejectsOneOver() throws {
        let maximum = 64 * 1024 * 1024
        let exact = threeWayTextRequest(
            options: ThreeWayTextMergeOptions(maximumInputBytes: maximum)
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(exact))

        let excessive = threeWayTextRequest(
            options: ThreeWayTextMergeOptions(maximumInputBytes: maximum + 1)
        )
        assertOpenError(.engineLimitExceeded(name: "text.maximumInputBytes", maximum: maximum)) {
            try ComparisonOpenRequestPlanner.plan(excessive)
        }
    }

    func testThreeWayTextEngineLineCeilingAcceptsExactAndRejectsOneOver() throws {
        let maximum = Int(MMX_MAX_LINE_COUNT)
        let exact = threeWayTextRequest(
            options: ThreeWayTextMergeOptions(maximumInputLines: maximum)
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(exact))

        let excessive = threeWayTextRequest(
            options: ThreeWayTextMergeOptions(maximumInputLines: maximum + 1)
        )
        assertOpenError(.engineLimitExceeded(name: "text.maximumInputLines", maximum: maximum)) {
            try ComparisonOpenRequestPlanner.plan(excessive)
        }
    }

    func testThreeWayTextOutputCapsAcceptExactAndRejectOneOverIndependently() throws {
        let cases: [(String, Int, (Int) -> ThreeWayTextMergeOptions)] = [
            (
                "text.maximumOutputBytes",
                192 * 1024 * 1024,
                { ThreeWayTextMergeOptions(maximumOutputBytes: $0) }
            ),
            (
                "text.maximumOutputLines",
                3 * 1024 * 1024,
                { ThreeWayTextMergeOptions(maximumOutputLines: $0) }
            ),
            (
                "text.maximumRegions",
                3 * 1024 * 1024 + 1,
                { ThreeWayTextMergeOptions(maximumRegions: $0) }
            )
        ]

        for (name, maximum, makeOptions) in cases {
            XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(threeWayTextRequest(options: makeOptions(maximum))), name)
            assertOpenError(.engineLimitExceeded(name: name, maximum: maximum)) {
                try ComparisonOpenRequestPlanner.plan(threeWayTextRequest(options: makeOptions(maximum + 1)))
            }
        }
    }

    func testActiveThreeWayTextByteAndLineBoundsApplyToScratchpads() {
        let byteBounded = ComparisonOpenRequest(
            left: .scratchpad(text: "four"),
            middle: .scratchpad(text: "b"),
            right: .scratchpad(text: "r"),
            modeSelection: .explicit(.text),
            modeOptions: .text(
                twoWay: LineDiffOptions(),
                threeWay: ThreeWayTextMergeOptions(maximumInputBytes: 3)
            )
        )
        assertOpenError(.scratchpadTooLarge(side: .left, maximumUTF8Bytes: 3)) {
            try ComparisonOpenRequestPlanner.plan(byteBounded)
        }

        let lineBounded = ComparisonOpenRequest(
            left: .scratchpad(text: "one\ntwo"),
            middle: .scratchpad(text: "base"),
            right: .scratchpad(text: "right"),
            modeSelection: .explicit(.text),
            modeOptions: .text(
                twoWay: LineDiffOptions(),
                threeWay: ThreeWayTextMergeOptions(maximumInputLines: 1)
            )
        )
        assertOpenError(.sourceLineCountExceeded(side: .left, maximumLines: 1)) {
            try ComparisonOpenRequestPlanner.plan(lineBounded)
        }
    }

    func testTwoWayTextEngineLineCapRejectsActualInputOneOver() {
        let maximum = Int(MMX_MAX_LINE_COUNT)
        let request = ComparisonOpenRequest(
            left: .scratchpad(text: String(repeating: "\n", count: maximum + 1)),
            right: .scratchpad(text: "right")
        )

        assertOpenError(.sourceLineCountExceeded(side: .left, maximumLines: maximum)) {
            try ComparisonOpenRequestPlanner.plan(request)
        }
    }

    func testInactiveRulesRetainItemAndStringBounds() throws {
        let limits = ComparisonOpenRequestLimits(
            maximumOptionItemCount: 2,
            maximumOptionStringUTF8Bytes: 3,
            maximumTotalOptionStringUTF8Bytes: 6
        )
        let exact = LineDiffOptions(
            lineFiltersEnabled: false,
            lineFilters: [.init(pattern: "123")],
            substitutionsEnabled: false,
            substitutions: [.init(pattern: "", replacement: "456")]
        )
        XCTAssertNoThrow(
            try ComparisonOpenRequestPlanner.plan(
                textRequest(options: exact, limits: limits)
            )
        )

        let oversized = LineDiffOptions(
            lineFiltersEnabled: false,
            lineFilters: [.init(pattern: "1234")]
        )
        assertOpenError(
            .optionStringTooLarge(name: "lineFilters[0].pattern", maximumUTF8Bytes: 3)
        ) {
            try ComparisonOpenRequestPlanner.plan(textRequest(options: oversized, limits: limits))
        }

        let tooMany = LineDiffOptions(
            lineFiltersEnabled: false,
            lineFilters: [.init(pattern: "a"), .init(pattern: "b"), .init(pattern: "c")]
        )
        assertOpenError(.tooManyOptionItems(maximum: 2)) {
            try ComparisonOpenRequestPlanner.plan(textRequest(options: tooMany, limits: limits))
        }
    }

    func testAggregateOptionStringCapCombinesAllActiveModeStringsAndTransforms() throws {
        let options = LineDiffOptions(
            lineFiltersEnabled: false,
            lineFilters: [.init(pattern: "aa")],
            substitutionsEnabled: false,
            substitutions: [.init(pattern: "bb", replacement: "cc")]
        )

        func request(totalLimit: Int) -> ComparisonOpenRequest {
            ComparisonOpenRequest(
                left: file("left.txt"),
                right: file("right.txt"),
                modeSelection: .explicit(.text),
                modeOptions: .text(twoWay: options, threeWay: ThreeWayTextMergeOptions()),
                transforms: ComparisonOpenTransforms(unpacker: .init(ruleIdentifier: "dd")),
                limits: ComparisonOpenRequestLimits(
                    maximumOptionStringUTF8Bytes: 2,
                    maximumTotalOptionStringUTF8Bytes: totalLimit
                )
            )
        }

        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(request(totalLimit: 8)))
        assertOpenError(.totalOptionStringsTooLarge(maximumUTF8Bytes: 7)) {
            try ComparisonOpenRequestPlanner.plan(request(totalLimit: 7))
        }

        let filter = ComparisonOpenFilenameFilter(
            rules: [.init(.exclude, pattern: .glob("aa"))],
            limits: filenameFilterLimits(
                maximumRuleCount: 1,
                maximumPatternUTF8Bytes: 2,
                maximumTotalPatternUTF8Bytes: 2
            )
        )
        func folderRequest(totalLimit: Int) -> ComparisonOpenRequest {
            ComparisonOpenRequest(
                left: .localFolder(URL(filePath: "/inputs/left", directoryHint: .isDirectory)),
                right: .localFolder(URL(filePath: "/inputs/right", directoryHint: .isDirectory)),
                modeSelection: .explicit(.folder),
                filenameFilter: filter,
                transforms: ComparisonOpenTransforms(unpacker: .init(ruleIdentifier: "bb")),
                limits: ComparisonOpenRequestLimits(
                    maximumOptionStringUTF8Bytes: 2,
                    maximumTotalOptionStringUTF8Bytes: totalLimit
                )
            )
        }
        assertOpenError(.externalTransformRequiresLocalFiles(capability: .unpacker)) {
            try ComparisonOpenRequestPlanner.plan(folderRequest(totalLimit: 4))
        }
        assertOpenError(.totalOptionStringsTooLarge(maximumUTF8Bytes: 3)) {
            try ComparisonOpenRequestPlanner.plan(folderRequest(totalLimit: 3))
        }
    }

    func testSyntaxValidationOnlyRunsForActiveTwoWayRules() throws {
        let malformed = LineDiffOptions(
            lineFilters: [.init(pattern: "[")],
            substitutions: [.init(pattern: "(", replacement: "value")]
        )
        assertOpenError(.invalidOption(name: "lineFilters[0].pattern")) {
            try ComparisonOpenRequestPlanner.plan(textRequest(options: malformed))
        }

        let disabled = LineDiffOptions(
            lineFiltersEnabled: false,
            lineFilters: [.init(pattern: "[")],
            substitutionsEnabled: false,
            substitutions: [.init(pattern: "(", replacement: "value")]
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(textRequest(options: disabled)))

        let retainedForThreeWay = ComparisonOpenRequest(
            left: .scratchpad(text: "left"),
            middle: .scratchpad(text: "base"),
            right: .scratchpad(text: "right"),
            modeSelection: .explicit(.text),
            modeOptions: .text(twoWay: malformed, threeWay: ThreeWayTextMergeOptions())
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(retainedForThreeWay))
    }

    func testSubstitutionPatternSyntaxAndBothStringBoundsAreValidatedIndependently() throws {
        let malformed = LineDiffOptions(substitutions: [.init(pattern: "(", replacement: "value")])
        assertOpenError(.invalidOption(name: "substitutions[0].pattern")) {
            try ComparisonOpenRequestPlanner.plan(textRequest(options: malformed))
        }

        let boundedLimits = ComparisonOpenRequestLimits(
            maximumOptionStringUTF8Bytes: 3,
            maximumTotalOptionStringUTF8Bytes: 6
        )
        for (rule, name) in [
            (SubstitutionRule(pattern: "1234", replacement: "ok"), "substitutions[0].pattern"),
            (SubstitutionRule(pattern: "ok", replacement: "1234"), "substitutions[0].replacement")
        ] {
            assertOpenError(.optionStringTooLarge(name: name, maximumUTF8Bytes: 3)) {
                try ComparisonOpenRequestPlanner.plan(
                    textRequest(options: LineDiffOptions(substitutions: [rule]), limits: boundedLimits)
                )
            }
        }

        let emptyPattern = LineDiffOptions(substitutions: [.init(pattern: "", replacement: "literal")])
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(textRequest(options: emptyPattern)))
        let capturesAndEscapes = LineDiffOptions(
            substitutions: [.init(pattern: #"(value)\s+(\d+)"#, replacement: #"$2\t$1\literal"#)]
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(textRequest(options: capturesAndEscapes)))
    }

    func testEmptyAndNULRegexesAreHandledAsLengthBoundedPatterns() throws {
        let options = LineDiffOptions(
            lineFilters: [.init(pattern: ""), .init(pattern: "\0")],
            substitutions: [
                .init(pattern: "", replacement: "ignored"),
                .init(pattern: "\0", replacement: "zero")
            ]
        )

        let plan = try ComparisonOpenRequestPlanner.plan(textRequest(options: options))

        XCTAssertEqual(plan.modeOptions, .text(twoWay: options, threeWay: ThreeWayTextMergeOptions()))
    }

    func testValidTransformsRetainRuleIdentityAndPlanBothCapabilities() throws {
        let unpacker = ComparisonOpenExternalRuleReference(ruleIdentifier: "archive.v1")
        let prediffer = ComparisonOpenExternalRuleReference(ruleIdentifier: "normalize-v2")
        let transforms = ComparisonOpenTransforms(unpacker: unpacker, prediffer: prediffer)
        let request = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.text),
            transforms: transforms
        )

        let plan = try ComparisonOpenRequestPlanner.plan(request)

        XCTAssertEqual(plan.transforms, transforms)
        XCTAssertTrue(
            plan.materializationRequirements.contains(
                .externalToolPlan(capability: .unpacker, rule: unpacker)
            )
        )
        XCTAssertTrue(
            plan.materializationRequirements.contains(
                .externalToolPlan(capability: .prediffer, rule: prediffer)
            )
        )
        XCTAssertEqual(
            plan.unsupportedFeatures,
            [.externalToolExecution(.unpacker), .externalToolExecution(.prediffer)]
        )
    }

    func testTransformsRequireExplicitModeDistinctValidIdentifiersAndLocalFiles() {
        let rule = ComparisonOpenExternalRuleReference(ruleIdentifier: "rule")
        let inferred = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            transforms: ComparisonOpenTransforms(unpacker: rule)
        )
        assertOpenError(.modeInferenceRequiresExplicitSelection) {
            try ComparisonOpenRequestPlanner.plan(inferred)
        }

        let duplicate = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.text),
            transforms: ComparisonOpenTransforms(unpacker: rule, prediffer: rule)
        )
        assertOpenError(.externalRuleIdentifiersMustDiffer) {
            try ComparisonOpenRequestPlanner.plan(duplicate)
        }

        let invalid = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.text),
            transforms: ComparisonOpenTransforms(
                prediffer: .init(ruleIdentifier: "not valid")
            )
        )
        assertOpenError(.invalidExternalRuleIdentifier(capability: .prediffer)) {
            try ComparisonOpenRequestPlanner.plan(invalid)
        }

        let scratchpad = ComparisonOpenRequest(
            left: .scratchpad(text: "left"),
            right: .scratchpad(text: "right"),
            modeSelection: .explicit(.text),
            transforms: ComparisonOpenTransforms(unpacker: rule)
        )
        assertOpenError(.externalTransformRequiresLocalFiles(capability: .unpacker)) {
            try ComparisonOpenRequestPlanner.plan(scratchpad)
        }
    }

    func testTransformIdentifierCapsAcceptExactAndRejectOneOverForBothCapabilities() throws {
        let exactIdentifier = String(repeating: "a", count: 128)
        let oversizedIdentifier = String(repeating: "a", count: 129)

        let cases: [(ExternalToolCapability, (String) -> ComparisonOpenTransforms)] = [
            (.unpacker, { ComparisonOpenTransforms(unpacker: .init(ruleIdentifier: $0)) }),
            (.prediffer, { ComparisonOpenTransforms(prediffer: .init(ruleIdentifier: $0)) })
        ]
        for (capability, transforms) in cases {

            let exact = ComparisonOpenRequest(
                left: file("left.txt"),
                right: file("right.txt"),
                modeSelection: .explicit(.text),
                transforms: transforms(exactIdentifier)
            )
            XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(exact))

            let oversized = ComparisonOpenRequest(
                left: file("left.txt"),
                right: file("right.txt"),
                modeSelection: .explicit(.text),
                transforms: transforms(oversizedIdentifier)
            )
            assertOpenError(.externalRuleIdentifierTooLarge(capability: capability, maximumUTF8Bytes: 128)) {
                try ComparisonOpenRequestPlanner.plan(oversized)
            }

            let configured = ComparisonOpenRequest(
                left: file("left.txt"),
                right: file("right.txt"),
                modeSelection: .explicit(.text),
                transforms: transforms("valid"),
                limits: ComparisonOpenRequestLimits(
                    maximumOptionStringUTF8Bytes: 4,
                    maximumTotalOptionStringUTF8Bytes: 4
                )
            )
            assertOpenError(.optionStringTooLarge(name: "optionStrings[0]", maximumUTF8Bytes: 4)) {
                try ComparisonOpenRequestPlanner.plan(configured)
            }
        }
    }

    func testLocalhostFileURLIsAcceptedWhileOriginalAuthorizedURLIsPreserved() throws {
        let leftURL = URL(string: "FiLe://LOCALHOST/inputs/left.txt")!
        let rightURL = URL(filePath: "/inputs/right.txt")
        let request = ComparisonOpenRequest(
            left: .localFile(leftURL),
            right: .localFile(rightURL),
            modeSelection: .explicit(.text)
        )

        let plan = try ComparisonOpenRequestPlanner.plan(request)

        XCTAssertEqual(plan.leftSide?.source, .localFile(leftURL))
        XCTAssertEqual(plan.leftSide?.normalizedPath, "/inputs/left.txt")
        let access = try XCTUnwrap(
            plan.materializationRequirements.compactMap { requirement -> ComparisonOpenLocalAccessRequirement? in
                guard case .localAccess(let access) = requirement, access.side == .left else { return nil }
                return access
            }.first
        )
        XCTAssertEqual(access.url, leftURL)
        XCTAssertEqual(access.url.absoluteString, leftURL.absoluteString)
        XCTAssertEqual(access.normalizedPath, "/inputs/left.txt")
        XCTAssertEqual(access.purpose, .readRegularFile)
        XCTAssertEqual(access.securityScope, .callerManagedWhenRequired)
    }

    func testDuplicateLocalSourcesAreRejectedLexicallyAndDistinctSourcesRequireIdentityValidation() throws {
        let duplicate = ComparisonOpenRequest(
            left: .localFile(URL(string: "file:///inputs/same.txt")!),
            right: .localFile(URL(string: "file://localhost/inputs/same.txt")!),
            modeSelection: .explicit(.text)
        )
        assertOpenError(.duplicateLocalSource(first: .left, second: .right)) {
            try ComparisonOpenRequestPlanner.plan(duplicate)
        }

        let leftURL = URL(filePath: "/inputs/left.txt")
        let rightURL = URL(filePath: "/inputs/right.txt")
        let distinctPlan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .localFile(leftURL),
                right: .localFile(rightURL),
                modeSelection: .explicit(.text)
            )
        )
        XCTAssertTrue(
            distinctPlan.materializationRequirements.contains(
                .distinctSourceIdentityValidation(sourceURLs: [leftURL, rightURL])
            )
        )

        let middleURL = URL(filePath: "/inputs/base.txt")
        let threeWayPlan = try ComparisonOpenRequestPlanner.plan(
            ComparisonOpenRequest(
                left: .localFile(leftURL),
                middle: .localFile(middleURL),
                right: .localFile(rightURL),
                modeSelection: .explicit(.text)
            )
        )
        XCTAssertTrue(
            threeWayPlan.materializationRequirements.contains(
                .distinctSourceIdentityValidation(sourceURLs: [leftURL, middleURL, rightURL])
            )
        )
        let middleDuplicate = ComparisonOpenRequest(
            left: .localFile(leftURL),
            middle: .localFile(URL(string: "file://localhost/inputs/left.txt")!),
            right: .localFile(rightURL),
            modeSelection: .explicit(.text)
        )
        assertOpenError(.duplicateLocalSource(first: .left, second: .middle)) {
            try ComparisonOpenRequestPlanner.plan(middleDuplicate)
        }
    }

    func testProjectDestinationPreservesCallerURLAndSecurityScopeRequirement() throws {
        let destination = URL(string: "file://localhost/projects/request.macmerge")!
        let intent = ComparisonOpenProjectSaveIntent(
            destinationURL: destination,
            existingFilePolicy: .replaceExisting
        )
        let request = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            projectSaveIntent: intent
        )

        let plan = try ComparisonOpenRequestPlanner.plan(request)

        XCTAssertEqual(plan.projectSaveIntent, intent)
        XCTAssertEqual(plan.normalizedProjectDestinationPath, "/projects/request.macmerge")
        let access = try XCTUnwrap(
            plan.materializationRequirements.compactMap { requirement -> ComparisonOpenLocalAccessRequirement? in
                guard case .localAccess(let access) = requirement, access.side == nil else { return nil }
                return access
            }.first
        )
        XCTAssertEqual(access.url, destination)
        XCTAssertEqual(access.normalizedPath, "/projects/request.macmerge")
        XCTAssertEqual(access.purpose, .writeProjectFile)
        XCTAssertEqual(access.securityScope, .callerManagedWhenRequired)
        XCTAssertTrue(
            plan.materializationRequirements.contains(
                .projectSaveValidation(
                    intent: intent,
                    sourceURLs: [URL(filePath: "/inputs/left.txt"), URL(filePath: "/inputs/right.txt")]
                )
            )
        )
    }

    func testDecodedDotPathSegmentsAreRejectedForSourcesAndDestinations() {
        for encodedSegment in ["%2E", "%2E%2E"] {
            let sourceURL = URL(string: "file:///inputs/\(encodedSegment)/left.txt")!
            let request = ComparisonOpenRequest(
                left: .localFile(sourceURL),
                right: file("right.txt"),
                modeSelection: .explicit(.text)
            )
            assertOpenError(.invalidURL(context: .side(.left), reason: .dotPathSegment)) {
                try ComparisonOpenRequestPlanner.plan(request)
            }

            let destination = URL(string: "file:///projects/\(encodedSegment)/request.macmerge")!
            let projectRequest = ComparisonOpenRequest(
                left: file("left.txt"),
                right: file("right.txt"),
                projectSaveIntent: ComparisonOpenProjectSaveIntent(destinationURL: destination)
            )
            assertOpenError(.invalidURL(context: .projectDestination, reason: .dotPathSegment)) {
                try ComparisonOpenRequestPlanner.plan(projectRequest)
            }
        }
    }

    func testLocalAndRemoteURLValidationReasonMatrix() {
        let relativeLocal = URL(string: "left.txt", relativeTo: URL(string: "file:///inputs/")!)!
        let localCases: [(URL, ComparisonOpenURLValidationReason)] = [
            (relativeLocal, .relativeURL),
            (URL(string: "https://example.test/left.txt")!, .wrongScheme),
            (URL(string: "file://example.test/inputs/left.txt")!, .remoteFileHost),
            (URL(string: "file://user:password@localhost/inputs/left.txt")!, .credentials),
            (URL(string: "file:///inputs/left.txt?token=secret")!, .queryOrFragment),
            (URL(string: "file://localhost")!, .missingPath),
            (URL(string: "file://localhost:80/inputs/left.txt")!, .port),
            (URL(string: "file:///inputs/left%00.txt")!, .nullByte)
        ]
        for position in ComparisonOpenSidePosition.allCases {
            for (url, reason) in localCases {
                let sides: [ComparisonOpenSide] =
                    position == .middle
                    ? [side(.left, file("left.txt")), side(.middle, .localFile(url)), side(.right, file("right.txt"))]
                    : [
                        side(.left, position == .left ? .localFile(url) : file("left.txt")),
                        side(.right, position == .right ? .localFile(url) : file("right.txt"))
                    ]
                assertOpenError(.invalidURL(context: .side(position), reason: reason)) {
                    try ComparisonOpenRequestPlanner.plan(
                        ComparisonOpenRequest(sides: sides, modeSelection: .explicit(.text))
                    )
                }
            }
        }

        let destinationCases =
            localCases + [
                (URL(string: "file:///")!, ComparisonOpenURLValidationReason.missingPath),
                (URL(filePath: "/projects/folder", directoryHint: .isDirectory), .directoryDestination),
                (URL(string: "file:///projects/.")!, .dotPathSegment),
                (URL(string: "file:///projects/..")!, .dotPathSegment)
            ]
        for (url, reason) in destinationCases {
            assertOpenError(.invalidURL(context: .projectDestination, reason: reason)) {
                try ComparisonOpenRequestPlanner.plan(
                    ComparisonOpenRequest(
                        left: file("left.txt"),
                        right: file("right.txt"),
                        projectSaveIntent: ComparisonOpenProjectSaveIntent(destinationURL: url)
                    )
                )
            }
        }

        let relativeRemote = URL(string: "page", relativeTo: URL(string: "https://example.test/")!)!
        let remoteCases: [(URL, ComparisonOpenURLValidationReason)] = [
            (relativeRemote, .relativeURL),
            (URL(string: "ftp://example.test/page")!, .wrongScheme),
            (URL(string: "https://user:password@example.test/page")!, .credentials),
            (URL(string: "https:///page")!, .missingHost),
            (URL(string: "https://example.test/page%00tail")!, .nullByte)
        ]
        for (url, reason) in remoteCases {
            assertOpenError(.invalidURL(context: .side(.left), reason: reason)) {
                try ComparisonOpenRequestPlanner.plan(
                    ComparisonOpenRequest(
                        left: .remoteWebPage(url),
                        right: .remoteWebPage(URL(string: "https://example.test/right")!)
                    )
                )
            }
        }

    }

    func testLocalAndRemoteURLBoundsRejectOneOverConfiguredMaximum() {
        let localLimits = ComparisonOpenRequestLimits(
            maximumPathUTF8Bytes: 8,
            maximumTotalPathUTF8Bytes: 24
        )
        let local = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.text),
            limits: localLimits
        )
        assertOpenError(.invalidURL(context: .side(.left), reason: .tooLong)) {
            try ComparisonOpenRequestPlanner.plan(local)
        }

        let remoteLimits = ComparisonOpenRequestLimits(maximumRemoteURLUTF8Bytes: 18)
        let remote = ComparisonOpenRequest(
            left: .remoteWebPage(URL(string: "https://example.com")!),
            right: .remoteWebPage(URL(string: "https://example.test")!),
            limits: remoteLimits
        )
        assertOpenError(.invalidURL(context: .side(.left), reason: .tooLong)) {
            try ComparisonOpenRequestPlanner.plan(remote)
        }
    }

    func testLocalRemoteAndAggregatePathBoundsAcceptExactAndRejectOneOver() throws {
        let localPath = "/a"
        let localExactLimits = ComparisonOpenRequestLimits(
            maximumPathUTF8Bytes: localPath.utf8.count,
            maximumTotalPathUTF8Bytes: 4
        )
        let localExact = ComparisonOpenRequest(
            left: .localFile(URL(filePath: localPath)),
            right: .localFile(URL(filePath: "/b")),
            modeSelection: .explicit(.text),
            limits: localExactLimits
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(localExact))
        let localOver = ComparisonOpenRequest(
            left: .localFile(URL(filePath: localPath)),
            right: .localFile(URL(filePath: "/bb")),
            modeSelection: .explicit(.text),
            limits: localExactLimits
        )
        assertOpenError(.invalidURL(context: .side(.right), reason: .tooLong)) {
            try ComparisonOpenRequestPlanner.plan(localOver)
        }

        let remoteURL = URL(string: "https://x.test")!
        let remoteExactLimits = ComparisonOpenRequestLimits(maximumRemoteURLUTF8Bytes: remoteURL.absoluteString.utf8.count)
        let remoteExact = ComparisonOpenRequest(
            left: .remoteWebPage(remoteURL),
            right: .remoteWebPage(remoteURL),
            limits: remoteExactLimits
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(remoteExact))
        let remoteOverURL = URL(string: "https://xx.test")!
        let remoteOver = ComparisonOpenRequest(
            left: .remoteWebPage(remoteOverURL),
            right: .remoteWebPage(remoteURL),
            limits: remoteExactLimits
        )
        assertOpenError(.invalidURL(context: .side(.left), reason: .tooLong)) {
            try ComparisonOpenRequestPlanner.plan(remoteOver)
        }

        let aggregateExact = ComparisonOpenRequest(
            left: .localFile(URL(filePath: "/a")),
            right: .localFile(URL(filePath: "/b")),
            modeSelection: .explicit(.text),
            limits: ComparisonOpenRequestLimits(maximumPathUTF8Bytes: 2, maximumTotalPathUTF8Bytes: 4)
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(aggregateExact))
        let aggregateOver = ComparisonOpenRequest(
            left: .localFile(URL(filePath: "/a")),
            right: .localFile(URL(filePath: "/b")),
            modeSelection: .explicit(.text),
            projectSaveIntent: ComparisonOpenProjectSaveIntent(destinationURL: URL(filePath: "/c")),
            limits: ComparisonOpenRequestLimits(maximumPathUTF8Bytes: 2, maximumTotalPathUTF8Bytes: 4)
        )
        assertOpenError(.totalPathsTooLarge(maximumUTF8Bytes: 4)) {
            try ComparisonOpenRequestPlanner.plan(aggregateOver)
        }
        let destinationOver = ComparisonOpenRequest(
            left: .localFile(URL(filePath: "/a")),
            right: .localFile(URL(filePath: "/b")),
            modeSelection: .explicit(.text),
            projectSaveIntent: ComparisonOpenProjectSaveIntent(destinationURL: URL(filePath: "/cc")),
            limits: ComparisonOpenRequestLimits(maximumPathUTF8Bytes: 2, maximumTotalPathUTF8Bytes: 6)
        )
        assertOpenError(.invalidURL(context: .projectDestination, reason: .tooLong)) {
            try ComparisonOpenRequestPlanner.plan(destinationOver)
        }
    }

    func testProjectDestinationAndSourcePathsUseNormalizedLexicalValues() throws {
        let destination = URL(string: "file://localhost/projects//request.macmerge")!
        let request = ComparisonOpenRequest(
            left: .localFile(URL(string: "file:///inputs//left.txt")!),
            right: file("right.txt"),
            projectSaveIntent: ComparisonOpenProjectSaveIntent(destinationURL: destination)
        )

        let plan = try ComparisonOpenRequestPlanner.plan(request)

        XCTAssertEqual(plan.leftSide?.normalizedPath, "/inputs/left.txt")
        XCTAssertEqual(plan.normalizedProjectDestinationPath, "/projects/request.macmerge")
        XCTAssertEqual(plan.projectSaveIntent?.destinationURL.absoluteString, destination.absoluteString)
        guard case .macMerge(let data) = plan.projectPayload else {
            return XCTFail("Expected MacMerge payload")
        }
        let project = try JSONDecoder().decode(ComparisonProject.self, from: data)
        XCTAssertEqual(project.side(.left)?.path.path, "/inputs/left.txt")
    }

    func testAutomaticMacMergeProjectIntentEmitsAutomaticCanonicalPayload() throws {
        let intent = ComparisonOpenProjectSaveIntent(
            destinationURL: URL(filePath: "/projects/automatic.macmerge"),
            existingFilePolicy: .replaceExisting
        )
        let request = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            leftReadOnly: true,
            projectSaveIntent: intent
        )

        let plan = try ComparisonOpenRequestPlanner.plan(request)
        guard case .macMerge(let data) = plan.projectPayload else {
            return XCTFail("Expected MacMerge payload")
        }
        let project = try JSONDecoder().decode(ComparisonProject.self, from: data)

        XCTAssertEqual(plan.modeResolution, .init(mode: .text, basis: .textFallback))
        XCTAssertEqual(plan.projectSaveIntent, intent)
        XCTAssertEqual(project.mode, .automatic)
        XCTAssertEqual(project.sides.map(\.identity), [.left, .right])
        XCTAssertEqual(project.side(.left)?.path.path, "/inputs/left.txt")
        XCTAssertEqual(project.side(.left)?.readOnly, true)
        XCTAssertEqual(data.last, 0x0A)
    }

    func testAutomaticMacMergeProjectPayloadMatchesExactCanonicalBytes() throws {
        let request = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            leftReadOnly: true,
            projectSaveIntent: ComparisonOpenProjectSaveIntent(
                destinationURL: URL(filePath: "/projects/automatic.macmerge")
            )
        )
        guard case .macMerge(let data) = try ComparisonOpenRequestPlanner.plan(request).projectPayload else {
            return XCTFail("Expected MacMerge payload")
        }
        let expectedJSON = """
            {
              "lineDiffOptions" : {
                "algorithm" : "default",
                "detectMovedBlocks" : false,
                "ignoreBlankLines" : false,
                "ignoreCase" : false,
                "ignoreComments" : false,
                "ignoreLineEndings" : true,
                "ignoreNumbers" : false,
                "indentHeuristic" : false,
                "lineFilters" : [

                ],
                "lineFiltersEnabled" : true,
                "substitutions" : [

                ],
                "substitutionsEnabled" : true,
                "whitespace" : "compareAll"
              },
              "mode" : "automatic",
              "recursive" : false,
              "schemaVersion" : 1,
              "sides" : [
                {
                  "identity" : "left",
                  "path" : "/inputs/left.txt",
                  "readOnly" : true
                },
                {
                  "identity" : "right",
                  "path" : "/inputs/right.txt",
                  "readOnly" : false
                }
              ]
            }
            """

        XCTAssertEqual(data, Data((expectedJSON + "\n").utf8))
    }

    func testRepresentableTextOptionsRoundTripThroughMacMergeProjectPayload() throws {
        let options = LineDiffOptions(
            algorithm: .patience,
            whitespace: .ignoreChanges,
            ignoreCase: true,
            ignoreNumbers: true,
            ignoreBlankLines: true,
            ignoreLineEndings: false,
            indentHeuristic: true,
            detectMovedBlocks: true,
            lineFilters: [.init(pattern: "^generated:", caseSensitive: false)],
            substitutions: [.init(pattern: "build-[0-9]+", replacement: "build", caseSensitive: false)]
        )
        let request = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.text),
            modeOptions: .text(twoWay: options, threeWay: ThreeWayTextMergeOptions()),
            projectSaveIntent: ComparisonOpenProjectSaveIntent(
                destinationURL: URL(filePath: "/projects/options.macmerge")
            )
        )

        let plan = try ComparisonOpenRequestPlanner.plan(request)
        guard case .macMerge(let data) = plan.projectPayload else {
            return XCTFail("Expected MacMerge payload")
        }
        let project = try JSONDecoder().decode(ComparisonProject.self, from: data)

        XCTAssertEqual(project.mode, .text)
        XCTAssertEqual(project.lineDiffOptions, options)
    }

    func testWinMergeProjectRejectsExplicitFolderModeWithoutLossySerialization() {
        let request = ComparisonOpenRequest(
            left: .localFolder(URL(filePath: "/inputs/left", directoryHint: .isDirectory)),
            right: .localFolder(URL(filePath: "/inputs/right", directoryHint: .isDirectory)),
            modeSelection: .explicit(.folder),
            recursive: true,
            projectSaveIntent: ComparisonOpenProjectSaveIntent(
                destinationURL: URL(filePath: "/projects/folders.WinMerge"),
                format: .winMerge
            )
        )

        assertOpenError(.projectCannotRepresent(.modeSelectionNotRepresentable)) {
            try ComparisonOpenRequestPlanner.plan(request)
        }
    }

    func testProjectSerializationRejectsEveryLossyInputFamily() throws {
        let folderLeft = ComparisonOpenSource.localFolder(URL(filePath: "/inputs/left", directoryHint: .isDirectory))
        let folderRight = ComparisonOpenSource.localFolder(URL(filePath: "/inputs/right", directoryHint: .isDirectory))
        let filter = ComparisonOpenFilenameFilter(rules: [.init(.exclude, pattern: .glob("*.tmp"))])
        let macMergeIntent = ComparisonOpenProjectSaveIntent(
            destinationURL: URL(filePath: "/projects/request.macmerge")
        )
        let winMergeIntent = ComparisonOpenProjectSaveIntent(
            destinationURL: URL(filePath: "/projects/request.WinMerge"),
            format: .winMerge
        )
        let cases: [(ComparisonOpenRequest, ComparisonOpenProjectRepresentationReason)] = [
            (
                ComparisonOpenRequest(
                    left: folderLeft,
                    right: folderRight,
                    filenameFilter: filter,
                    projectSaveIntent: macMergeIntent
                ),
                .filenameFilterNotRepresentable
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.txt"),
                    right: file("right.txt"),
                    modeSelection: .explicit(.text),
                    transforms: ComparisonOpenTransforms(unpacker: .init(ruleIdentifier: "archive")),
                    projectSaveIntent: macMergeIntent
                ),
                .transformsNotRepresentable
            ),
            (
                ComparisonOpenRequest(
                    left: .scratchpad(text: "left"),
                    right: .scratchpad(text: "right"),
                    projectSaveIntent: macMergeIntent
                ),
                .localSourcesRequired
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.bin"),
                    right: file("right.bin"),
                    modeSelection: .explicit(.binary),
                    modeOptions: .binary(twoWay: BinaryComparisonOptions(), threeWay: .default),
                    projectSaveIntent: macMergeIntent
                ),
                .modeOptionsNotRepresentable
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.txt"),
                    right: file("right.txt"),
                    modeSelection: .explicit(.text),
                    modeOptions: .text(
                        twoWay: LineDiffOptions(commentSyntax: .cFamily),
                        threeWay: ThreeWayTextMergeOptions()
                    ),
                    projectSaveIntent: macMergeIntent
                ),
                .modeOptionsNotRepresentable
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.txt"),
                    middle: file("base.txt"),
                    right: file("right.txt"),
                    modeSelection: .explicit(.text),
                    modeOptions: .text(
                        twoWay: LineDiffOptions(algorithm: .patience),
                        threeWay: ThreeWayTextMergeOptions(diffAlgorithm: .minimal)
                    ),
                    projectSaveIntent: macMergeIntent
                ),
                .modeOptionsNotRepresentable
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.txt"),
                    right: file("right.txt"),
                    modeSelection: .explicit(.text),
                    modeOptions: .text(
                        twoWay: LineDiffOptions(),
                        threeWay: ThreeWayTextMergeOptions(maximumRegions: 1)
                    ),
                    projectSaveIntent: macMergeIntent
                ),
                .modeOptionsNotRepresentable
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.txt"),
                    right: file("right.txt"),
                    modeSelection: .explicit(.text),
                    modeOptions: .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions()),
                    projectSaveIntent: winMergeIntent
                ),
                .modeOptionsNotRepresentable
            ),
            (
                ComparisonOpenRequest(
                    left: .localFile(URL(filePath: "/")),
                    right: file("right.txt"),
                    modeSelection: .explicit(.text),
                    projectSaveIntent: macMergeIntent
                ),
                .projectModelRejectedRequest
            )
        ]

        for (request, reason) in cases {
            assertOpenError(.projectCannotRepresent(reason)) {
                try ComparisonOpenRequestPlanner.plan(request)
            }
        }

        let activeEmptySubstitution = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.text),
            modeOptions: .text(
                twoWay: LineDiffOptions(substitutions: [.init(pattern: "", replacement: "literal")]),
                threeWay: ThreeWayTextMergeOptions()
            ),
            projectSaveIntent: macMergeIntent
        )
        assertOpenError(.projectCannotRepresent(.modeOptionsNotRepresentable)) {
            try ComparisonOpenRequestPlanner.plan(activeEmptySubstitution)
        }
    }

    func testInferredFolderModeIsRepresentableInWinMergeProject() throws {
        let request = ComparisonOpenRequest(
            left: .localFolder(URL(filePath: "/inputs/left", directoryHint: .isDirectory)),
            right: .localFolder(URL(filePath: "/inputs/right", directoryHint: .isDirectory)),
            recursive: true,
            projectSaveIntent: ComparisonOpenProjectSaveIntent(
                destinationURL: URL(filePath: "/projects/folders.WinMerge"),
                format: .winMerge
            )
        )

        let plan = try ComparisonOpenRequestPlanner.plan(request)
        guard case .winMerge(let data) = plan.projectPayload else {
            return XCTFail("Expected WinMerge payload")
        }
        let project = try WinMergeProjectFile.parse(data)

        XCTAssertEqual(plan.modeResolution, .init(mode: .folder, basis: .allFolders))
        XCTAssertEqual(project.leftPath, "/inputs/left")
        XCTAssertEqual(project.rightPath, "/inputs/right")
        XCTAssertEqual(project.includesSubfolders, true)
        XCTAssertNil(project.options.windowType)
    }

    func testFolderPlansRetainFilterAndExposeRecursiveAccessRequirements() throws {
        let filter = ComparisonOpenFilenameFilter(
            rules: [
                .init(.exclude, pattern: .glob("**/*.tmp"), applicability: .files),
                .init(.include, pattern: .regularExpression(#"^Sources/"#), applicability: .directories)
            ],
            defaultDecision: .exclude,
            matchSemantics: .firstMatchWins,
            casePolicy: .insensitive
        )
        let urls = [
            URL(filePath: "/inputs/left", directoryHint: .isDirectory),
            URL(filePath: "/inputs/base", directoryHint: .isDirectory),
            URL(filePath: "/inputs/right", directoryHint: .isDirectory)
        ]

        for recursive in [false, true] {
            let request = ComparisonOpenRequest(
                left: .localFolder(urls[0]),
                middle: .localFolder(urls[1]),
                right: .localFolder(urls[2]),
                recursive: recursive,
                filenameFilter: filter
            )
            let plan = try ComparisonOpenRequestPlanner.plan(request)
            XCTAssertEqual(plan.filenameFilter, filter)
            XCTAssertEqual(plan.recursive, recursive)
            let accesses = plan.materializationRequirements.compactMap { requirement -> ComparisonOpenLocalAccessRequirement? in
                guard case .localAccess(let access) = requirement else { return nil }
                return access
            }
            XCTAssertEqual(accesses.map(\.side), [.left, .middle, .right])
            XCTAssertEqual(accesses.map(\.url), urls)
            XCTAssertEqual(accesses.map(\.normalizedPath), ["/inputs/left", "/inputs/base", "/inputs/right"])
            XCTAssertTrue(accesses.allSatisfy { $0.purpose == .readDirectoryTree })
            XCTAssertTrue(accesses.allSatisfy { $0.recursive == recursive })
            XCTAssertTrue(accesses.allSatisfy { $0.securityScope == .callerManagedWhenRequired })
            XCTAssertEqual(plan.unsupportedFeatures, recursive ? [] : [.nonrecursiveFolderEnumeration])
        }
    }

    func testFilenameFilterValidationReportsExactDiagnosticAndRequestCaps() {
        let folders = (
            ComparisonOpenSource.localFolder(URL(filePath: "/inputs/left", directoryHint: .isDirectory)),
            ComparisonOpenSource.localFolder(URL(filePath: "/inputs/right", directoryHint: .isDirectory))
        )
        let emptyPattern = ComparisonOpenFilenameFilter(rules: [.init(.exclude, pattern: .glob(""))])
        assertOpenError(
            .invalidFilenameFilter(.init(ruleIndex: 0, reason: .emptyPattern))
        ) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(left: folders.0, right: folders.1, filenameFilter: emptyPattern)
            )
        }

        let tooManyRules = ComparisonOpenFilenameFilter(
            rules: [
                .init(.exclude, pattern: .glob("a")),
                .init(.exclude, pattern: .glob("b"))
            ]
        )
        assertOpenError(.tooManyOptionItems(maximum: 1)) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(
                    left: folders.0,
                    right: folders.1,
                    filenameFilter: tooManyRules,
                    limits: ComparisonOpenRequestLimits(maximumOptionItemCount: 1)
                )
            )
        }

        let oversizedPattern = ComparisonOpenFilenameFilter(
            rules: [.init(.exclude, pattern: .glob("ab"))],
            limits: FilenameFilterLimits(
                maximumRuleCount: 1,
                maximumPatternUTF8Bytes: 1,
                maximumTotalPatternUTF8Bytes: 1
            )
        )
        assertOpenError(.optionStringTooLarge(name: "optionStrings[0]", maximumUTF8Bytes: 1)) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(
                    left: folders.0,
                    right: folders.1,
                    filenameFilter: oversizedPattern,
                    limits: ComparisonOpenRequestLimits(
                        maximumOptionStringUTF8Bytes: 1,
                        maximumTotalOptionStringUTF8Bytes: 1
                    )
                )
            )
        }
    }

    func testEveryFilenameFilterLimitRejectsOneOverItsRequestOrEngineCeiling() {
        let cases: [(FilenameFilterLimits, ComparisonOpenRequestLimits, ComparisonOpenRequestError)] = [
            (
                filenameFilterLimits(maximumRuleCount: 2),
                ComparisonOpenRequestLimits(maximumOptionItemCount: 1),
                .declaredLimitExceeded(name: "filenameFilter.maximumRuleCount", maximum: 1)
            ),
            (
                filenameFilterLimits(maximumPatternUTF8Bytes: 2),
                ComparisonOpenRequestLimits(
                    maximumOptionStringUTF8Bytes: 1,
                    maximumTotalOptionStringUTF8Bytes: 1_048_576
                ),
                .declaredLimitExceeded(name: "filenameFilter.maximumPatternUTF8Bytes", maximum: 1)
            ),
            (
                filenameFilterLimits(maximumPatternUTF8Bytes: 1, maximumTotalPatternUTF8Bytes: 2),
                ComparisonOpenRequestLimits(
                    maximumOptionStringUTF8Bytes: 1,
                    maximumTotalOptionStringUTF8Bytes: 1
                ),
                .declaredLimitExceeded(name: "filenameFilter.maximumTotalPatternUTF8Bytes", maximum: 1)
            ),
            (
                filenameFilterLimits(maximumRuleCount: 1_025),
                .default,
                .engineLimitExceeded(name: "filenameFilter.maximumRuleCount", maximum: 1_024)
            ),
            (
                filenameFilterLimits(maximumPatternUTF8Bytes: 4_097),
                .default,
                .engineLimitExceeded(name: "filenameFilter.maximumPatternUTF8Bytes", maximum: 4_096)
            ),
            (
                filenameFilterLimits(maximumTotalPatternUTF8Bytes: 1_048_577),
                .default,
                .engineLimitExceeded(name: "filenameFilter.maximumTotalPatternUTF8Bytes", maximum: 1_048_576)
            ),
            (
                filenameFilterLimits(maximumRelativePathUTF8Bytes: 16_385),
                .default,
                .engineLimitExceeded(name: "filenameFilter.maximumRelativePathUTF8Bytes", maximum: 16_384)
            ),
            (
                filenameFilterLimits(maximumCompiledStateCount: 65_537),
                .default,
                .engineLimitExceeded(name: "filenameFilter.maximumCompiledStateCount", maximum: 65_536)
            ),
            (
                filenameFilterLimits(maximumMatchWork: 512 * 1024 * 1024 + 1),
                ComparisonOpenRequestLimits(maximumDeclaredWorkUnits: 512 * 1024 * 1024 + 1),
                .engineLimitExceeded(name: "filenameFilter.maximumMatchWork", maximum: 512 * 1024 * 1024)
            ),
            (
                filenameFilterLimits(maximumRegularExpressionNestingDepth: 65),
                .default,
                .engineLimitExceeded(name: "filenameFilter.maximumRegularExpressionNestingDepth", maximum: 64)
            ),
            (
                filenameFilterLimits(maximumRegularExpressionRepetition: 1_025),
                .default,
                .engineLimitExceeded(name: "filenameFilter.maximumRegularExpressionRepetition", maximum: 1_024)
            ),
            (
                filenameFilterLimits(maximumCompiledStateCount: 2, maximumMatchWork: 1),
                ComparisonOpenRequestLimits(maximumDeclaredWorkUnits: 1),
                .declaredLimitExceeded(name: "filenameFilter.work", maximum: 1)
            )
        ]

        for (filterLimits, requestLimits, expected) in cases {
            assertOpenError(expected) {
                try ComparisonOpenRequestPlanner.plan(
                    folderRequest(
                        filenameFilter: ComparisonOpenFilenameFilter(rules: [], limits: filterLimits),
                        limits: requestLimits
                    )
                )
            }
        }
    }

    func testProjectDestinationCannotLexicallyMatchSource() {
        let source = URL(filePath: "/inputs/left.txt")
        let request = ComparisonOpenRequest(
            left: .localFile(source),
            right: file("right.txt"),
            projectSaveIntent: ComparisonOpenProjectSaveIntent(destinationURL: source)
        )

        assertOpenError(.projectCannotRepresent(.destinationMatchesSource)) {
            try ComparisonOpenRequestPlanner.plan(request)
        }
    }

    func testExpectedIdentityAndPlanFreshnessRejectStaleRequests() throws {
        let currentIdentity = identity(10)
        let staleIdentity = identity(11)
        let request = ComparisonOpenRequest(
            identity: currentIdentity,
            left: file("left.txt"),
            right: file("right.txt")
        )

        assertOpenError(.staleRequest(expected: staleIdentity, actual: currentIdentity)) {
            try ComparisonOpenRequestPlanner.plan(request, expecting: staleIdentity)
        }

        let plan = try ComparisonOpenRequestPlanner.plan(request, expecting: currentIdentity)
        XCTAssertTrue(plan.isCurrent(for: request))
        XCTAssertNoThrow(try plan.requireCurrentRequest(request))

        let replacement = ComparisonOpenRequest(
            identity: staleIdentity,
            left: file("replacement.txt"),
            right: file("right.txt")
        )
        XCTAssertFalse(plan.isCurrent(for: replacement))
        assertOpenError(.staleRequest(expected: currentIdentity, actual: staleIdentity)) {
            try plan.requireCurrentRequest(replacement)
        }

        let changedPayloadWithSameIdentity = ComparisonOpenRequest(
            identity: currentIdentity,
            left: file("changed.txt"),
            right: file("right.txt"),
            modeSelection: .explicit(.binary)
        )
        XCTAssertTrue(plan.isCurrent(for: changedPayloadWithSameIdentity))
        XCTAssertNoThrow(try plan.requireCurrentRequest(changedPayloadWithSameIdentity))
        XCTAssertNotEqual(plan.sourceRequest, changedPayloadWithSameIdentity)
    }

    func testInvalidDeclaredBoundsAndPlanningWorkFailClosed() {
        let invalidLimits = ComparisonOpenRequestLimits(
            maximumPathUTF8Bytes: 9,
            maximumTotalPathUTF8Bytes: 8
        )
        let invalid = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            limits: invalidLimits
        )
        assertOpenError(.invalidLimit(.totalPathUTF8Bytes)) {
            try ComparisonOpenRequestPlanner.plan(invalid)
        }

        let invalidCombinedScratchpads = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            limits: ComparisonOpenRequestLimits(
                maximumScratchpadUTF8Bytes: 9,
                maximumCombinedScratchpadUTF8Bytes: 8
            )
        )
        assertOpenError(.invalidLimit(.combinedScratchpadUTF8Bytes)) {
            try ComparisonOpenRequestPlanner.plan(invalidCombinedScratchpads)
        }

        let invalidTotalOptionStrings = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            limits: ComparisonOpenRequestLimits(
                maximumOptionStringUTF8Bytes: 9,
                maximumTotalOptionStringUTF8Bytes: 8
            )
        )
        assertOpenError(.invalidLimit(.totalOptionStringUTF8Bytes)) {
            try ComparisonOpenRequestPlanner.plan(invalidTotalOptionStrings)
        }

        let noWork = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            limits: ComparisonOpenRequestLimits(maximumPlanningWorkUnits: 0)
        )
        assertOpenError(.planningWorkExceeded(maximumWorkUnits: 0)) {
            try ComparisonOpenRequestPlanner.plan(noWork)
        }

        let overHardMaximum = ComparisonOpenRequest(
            left: file("left.txt"),
            right: file("right.txt"),
            limits: ComparisonOpenRequestLimits(
                maximumPathUTF8Bytes: ComparisonOpenRequestLimits.hardMaximumPathUTF8Bytes + 1
            )
        )
        assertOpenError(.invalidLimit(.pathUTF8Bytes)) {
            try ComparisonOpenRequestPlanner.plan(overHardMaximum)
        }
    }

    func testEveryRequestLimitRejectsNegativeAndHardMaximumPlusOne() {
        let hardMaximums: [ComparisonOpenRequestLimit: Int] = [
            .pathUTF8Bytes: ComparisonOpenRequestLimits.hardMaximumPathUTF8Bytes,
            .totalPathUTF8Bytes: ComparisonOpenRequestLimits.hardMaximumTotalPathUTF8Bytes,
            .remoteURLUTF8Bytes: ComparisonOpenRequestLimits.hardMaximumRemoteURLUTF8Bytes,
            .scratchpadUTF8Bytes: ComparisonOpenRequestLimits.hardMaximumScratchpadUTF8Bytes,
            .combinedScratchpadUTF8Bytes: ComparisonOpenRequestLimits.hardMaximumCombinedScratchpadUTF8Bytes,
            .labelUTF8Bytes: ComparisonOpenRequestLimits.hardMaximumLabelUTF8Bytes,
            .optionItemCount: ComparisonOpenRequestLimits.hardMaximumOptionItemCount,
            .optionStringUTF8Bytes: ComparisonOpenRequestLimits.hardMaximumOptionStringUTF8Bytes,
            .totalOptionStringUTF8Bytes: ComparisonOpenRequestLimits.hardMaximumTotalOptionStringUTF8Bytes,
            .declaredBytes: ComparisonOpenRequestLimits.hardMaximumDeclaredBytes,
            .declaredWorkUnits: ComparisonOpenRequestLimits.hardMaximumDeclaredWorkUnits,
            .planningWorkUnits: ComparisonOpenRequestLimits.hardMaximumPlanningWorkUnits
        ]

        for limit in ComparisonOpenRequestLimit.allCases {
            let maximum = try! XCTUnwrap(hardMaximums[limit])
            for value in [-1, maximum + 1] {
                let request = ComparisonOpenRequest(
                    left: file("left.txt"),
                    right: file("right.txt"),
                    limits: requestLimits(overriding: limit, with: value)
                )
                assertOpenError(.invalidLimit(limit)) {
                    try ComparisonOpenRequestPlanner.plan(request)
                }
            }
        }
    }

    func testScratchpadLabelCombinedAndDeclaredClipboardLimitsUseExactBoundaries() throws {
        let scratchpadLimits = ComparisonOpenRequestLimits(
            maximumScratchpadUTF8Bytes: 4,
            maximumCombinedScratchpadUTF8Bytes: 8,
            maximumLabelUTF8Bytes: 2
        )
        let exact = ComparisonOpenRequest(
            left: .scratchpad(text: "four", label: "ab"),
            right: .scratchpad(text: "five"),
            limits: scratchpadLimits
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(exact))
        assertOpenError(.scratchpadTooLarge(side: .left, maximumUTF8Bytes: 4)) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(
                    left: .scratchpad(text: "12345"),
                    right: .scratchpad(text: "x"),
                    limits: scratchpadLimits
                )
            )
        }
        assertOpenError(.combinedScratchpadsTooLarge(maximumUTF8Bytes: 8)) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(
                    left: .scratchpad(text: "four"),
                    right: .scratchpad(text: "12345"),
                    limits: ComparisonOpenRequestLimits(
                        maximumScratchpadUTF8Bytes: 5,
                        maximumCombinedScratchpadUTF8Bytes: 8,
                        maximumLabelUTF8Bytes: 2
                    )
                )
            )
        }
        assertOpenError(.labelTooLarge(side: .left, maximumUTF8Bytes: 2)) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(
                    left: .scratchpad(text: "x", label: "abc"),
                    right: .scratchpad(text: "y"),
                    limits: scratchpadLimits
                )
            )
        }
        assertOpenError(.invalidLabel(side: .left)) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(
                    left: .scratchpad(text: "x", label: ""),
                    right: .scratchpad(text: "y"),
                    limits: scratchpadLimits
                )
            )
        }

        let exactClipboard = try ClipboardSnapshot(data: Data([0x01, 0x02]), maximumBytes: 2)
        let exactClipboardRequest = ComparisonOpenRequest(
            left: .clipboard(exactClipboard),
            right: .clipboard(exactClipboard),
            limits: ComparisonOpenRequestLimits(maximumDeclaredBytes: 2)
        )
        XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(exactClipboardRequest))
        let overClipboard = try ClipboardSnapshot(data: Data([0x01, 0x02, 0x03]), maximumBytes: 3)
        assertOpenError(.declaredLimitExceeded(name: "clipboard.left.bytes", maximum: 2)) {
            try ComparisonOpenRequestPlanner.plan(
                ComparisonOpenRequest(
                    left: .clipboard(overClipboard),
                    right: .clipboard(exactClipboard),
                    limits: ComparisonOpenRequestLimits(maximumDeclaredBytes: 2)
                )
            )
        }
    }

    func testAllOptionFamiliesAcceptDefaultsAndRejectEveryValidatedFieldOneOver() {
        let defaultRequests: [ComparisonOpenRequest] = [
            ComparisonOpenRequest(
                left: file("left.txt"),
                right: file("right.txt"),
                modeSelection: .explicit(.text),
                modeOptions: .text(twoWay: LineDiffOptions(), threeWay: ThreeWayTextMergeOptions())
            ),
            ComparisonOpenRequest(
                left: file("left.csv"),
                right: file("right.csv"),
                modeSelection: .explicit(.table),
                modeOptions: .table(parsing: .commaSeparated, twoWay: .default, threeWay: .default)
            ),
            ComparisonOpenRequest(
                left: file("left.bin"),
                right: file("right.bin"),
                modeSelection: .explicit(.binary),
                modeOptions: .binary(twoWay: BinaryComparisonOptions(), threeWay: .default)
            ),
            ComparisonOpenRequest(
                left: file("left.png"),
                right: file("right.png"),
                modeSelection: .explicit(.image),
                modeOptions: .image(loading: .default, comparison: .default)
            ),
            ComparisonOpenRequest(
                left: file("left.html"),
                right: file("right.html"),
                modeSelection: .explicit(.webpage),
                modeOptions: .webpage(twoWay: .default, threeWay: .default)
            ),
            folderRequest(
                options: .folder(
                    scanning: FolderScanOptions(),
                    twoWay: FolderComparisonOptions(),
                    threeWay: .default
                )
            )
        ]
        for request in defaultRequests {
            XCTAssertNoThrow(try ComparisonOpenRequestPlanner.plan(request))
        }

        let invalidCases: [(ComparisonOpenRequest, ComparisonOpenRequestError)] = [
            (
                ComparisonOpenRequest(
                    left: file("left.csv"),
                    right: file("right.csv"),
                    modeSelection: .explicit(.table),
                    modeOptions: .table(
                        parsing: DelimitedTableParsingOptions(delimiter: ",", quote: ","),
                        twoWay: .default,
                        threeWay: .default
                    )
                ),
                .invalidOption(name: "table.parsing")
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.csv"),
                    right: file("right.csv"),
                    modeSelection: .explicit(.table),
                    modeOptions: .table(
                        parsing: DelimitedTableParsingOptions(
                            limits: DelimitedTableLimits(maximumRows: 0)
                        ),
                        twoWay: .default,
                        threeWay: .default
                    )
                ),
                .invalidOption(name: "table.parsing.limits")
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.bin"),
                    right: file("right.bin"),
                    modeSelection: .explicit(.binary),
                    modeOptions: .binary(
                        twoWay: BinaryComparisonOptions(maximumExactEditDistance: 2_049),
                        threeWay: .default
                    )
                ),
                .engineLimitExceeded(name: "binary.maximumExactEditDistance", maximum: 2_048)
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.png"),
                    right: file("right.png"),
                    modeSelection: .explicit(.image),
                    modeOptions: .image(
                        loading: ImageComparisonLimits(
                            maximumEncodedBytes: 1,
                            maximumDimension: 1,
                            maximumPixelCount: 1,
                            maximumDecodedBytes: 1,
                            supportedTypeIdentifiers: []
                        ),
                        comparison: .default
                    )
                ),
                .invalidOption(name: "image.loading")
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.png"),
                    right: file("right.png"),
                    modeSelection: .explicit(.image),
                    modeOptions: .image(
                        loading: .default,
                        comparison: ImageComparisonOptions(maximumCanvasPixels: 0)
                    )
                ),
                .invalidOption(name: "image.comparison")
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.png"),
                    right: file("right.png"),
                    modeSelection: .explicit(.image),
                    modeOptions: .image(
                        loading: ImageComparisonLimits(
                            maximumEncodedBytes: 1,
                            maximumDimension: 1,
                            maximumPixelCount: 1,
                            maximumDecodedBytes: 1,
                            supportedTypeIdentifiers: ["unsupported.type"]
                        ),
                        comparison: .default
                    )
                ),
                .invalidOption(name: "image.supportedTypeIdentifier")
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.html"),
                    right: file("right.html"),
                    modeSelection: .explicit(.webpage),
                    modeOptions: .webpage(
                        twoWay: WebPageComparisonOptions(
                            lineDiffOptions: LineDiffOptions(lineFilters: [.init(pattern: "[")])
                        ),
                        threeWay: .default
                    )
                ),
                .invalidOption(name: "lineFilters[0].pattern")
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.html"),
                    right: file("right.html"),
                    modeSelection: .explicit(.webpage),
                    modeOptions: .webpage(
                        twoWay: .default,
                        threeWay: ThreeWayWebPageComparisonOptions(
                            expectedContext: .init(identifier: "", generation: 1)
                        )
                    )
                ),
                .invalidOption(name: "webpage.expectedContext.identifier")
            ),
            (
                folderRequest(
                    options: .folder(
                        scanning: FolderScanOptions(
                            limits: FolderScanLimits(maximumDepth: 513)
                        ),
                        twoWay: FolderComparisonOptions(),
                        threeWay: .default
                    )
                ),
                .engineLimitExceeded(name: "folder.maximumDepth", maximum: 512)
            )
        ]
        for (request, expected) in invalidCases {
            assertOpenError(expected) {
                try ComparisonOpenRequestPlanner.plan(request)
            }
        }

        let maximumInputBytes = Int(MMX_MAX_INPUT_SIZE)
        let fieldCases: [(ComparisonOpenRequest, String, Int)] = [
            tableRequest(parsing: DelimitedTableParsingOptions(limits: DelimitedTableLimits(maximumInputBytes: maximumInputBytes + 1))),
            tableRequest(parsing: DelimitedTableParsingOptions(limits: DelimitedTableLimits(maximumRows: 1_048_577))),
            tableRequest(parsing: DelimitedTableParsingOptions(limits: DelimitedTableLimits(maximumColumnsPerRow: 16_385))),
            tableRequest(parsing: DelimitedTableParsingOptions(limits: DelimitedTableLimits(maximumTotalCells: 1_048_577))),
            tableRequest(parsing: DelimitedTableParsingOptions(limits: DelimitedTableLimits(maximumCellBytes: 16 * 1024 * 1024 + 1))),
            tableRequest(twoWay: TableComparisonOptions(maximumExactEditDistance: 2_049)),
            tableRequest(twoWay: TableComparisonOptions(maximumAlignmentWork: 16 * 1024 * 1024 + 1)),
            tableRequest(twoWay: TableComparisonOptions(maximumComparedRows: 2_097_153)),
            tableRequest(twoWay: TableComparisonOptions(maximumComparedCells: 2_097_153)),
            (
                ComparisonOpenRequest(
                    left: file("left.csv"),
                    middle: file("base.csv"),
                    right: file("right.csv"),
                    modeSelection: .explicit(.table),
                    modeOptions: .table(
                        parsing: .commaSeparated,
                        twoWay: .default,
                        threeWay: ThreeWayTableComparisonOptions(
                            parsingOptions: DelimitedTableParsingOptions(
                                limits: DelimitedTableLimits(maximumRows: 1_048_577)
                            )
                        )
                    )
                ),
                "table.maximumRows",
                1_048_576
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.csv"),
                    middle: file("base.csv"),
                    right: file("right.csv"),
                    modeSelection: .explicit(.table),
                    modeOptions: .table(
                        parsing: .commaSeparated,
                        twoWay: .default,
                        threeWay: ThreeWayTableComparisonOptions(
                            comparisonOptions: TableComparisonOptions(maximumAlignmentWork: 16 * 1024 * 1024 + 1)
                        )
                    )
                ),
                "table.maximumAlignmentWork",
                16 * 1024 * 1024
            ),
            tableRequest(threeWay: ThreeWayTableComparisonOptions(maximumComparedValueBytes: 192 * 1024 * 1024 + 1)),
            tableRequest(threeWay: ThreeWayTableComparisonOptions(maximumResultRows: 3 * 1_048_576 + 1)),
            tableRequest(threeWay: ThreeWayTableComparisonOptions(maximumResultCells: 3 * 1_048_576 + 1)),
            binaryRequest(twoWay: BinaryComparisonOptions(maximumExactEditDistance: 2_049)),
            binaryRequest(twoWay: BinaryComparisonOptions(maximumAlignmentWork: 16 * 1024 * 1024 + 1)),
            binaryRequest(threeWay: ThreeWayBinaryComparisonOptions(maximumInputBytes: 64 * 1024 * 1024 + 1)),
            binaryRequest(threeWay: ThreeWayBinaryComparisonOptions(maximumExactEditDistance: 2_049)),
            binaryRequest(threeWay: ThreeWayBinaryComparisonOptions(maximumAlignmentWork: 32 * 1024 * 1024 + 1)),
            binaryRequest(threeWay: ThreeWayBinaryComparisonOptions(maximumRegions: 16 * 1024 * 1024 + 1)),
            binaryRequest(threeWay: ThreeWayBinaryComparisonOptions(maximumOutputBytes: 192 * 1024 * 1024 + 1)),
            imageRequest(loading: imageLimits(maximumEncodedBytes: maximumInputBytes + 1)),
            imageRequest(loading: imageLimits(maximumDimension: 16_385)),
            imageRequest(loading: imageLimits(maximumPixelCount: 16 * 1024 * 1024 + 1)),
            imageRequest(loading: imageLimits(maximumDecodedBytes: 128 * 1024 * 1024 + 1)),
            imageRequest(comparison: ImageComparisonOptions(maximumCanvasPixels: 16 * 1024 * 1024 + 1)),
            imageRequest(comparison: ImageComparisonOptions(maximumRegions: 250_001)),
            imageRequest(comparison: ImageComparisonOptions(maximumQueuedPixels: 262_145)),
            webpageRequest(twoWayLimits: webPageLimits(maximumInputBytes: maximumInputBytes + 1)),
            webpageRequest(twoWayLimits: webPageLimits(maximumTokenCount: 1_000_001)),
            webpageRequest(twoWayLimits: webPageLimits(maximumAttributeCount: 1_000_001)),
            webpageRequest(twoWayLimits: webPageLimits(maximumAttributesPerTag: 16_385)),
            webpageRequest(twoWayLimits: webPageLimits(maximumElementDepth: 16_385)),
            webpageRequest(twoWayLimits: webPageLimits(maximumWorkUnits: 256 * 1024 * 1024 + 1)),
            webpageRequest(twoWayLimits: webPageLimits(maximumOutputBytes: maximumInputBytes + 1)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumSourceInputBytesPerSnapshot: 64 * 1024 * 1024 + 1)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumNormalizedInputBytesPerSnapshot: 64 * 1024 * 1024 + 1)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumTokenCountPerSnapshot: 1_000_001)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumAttributeCountPerSnapshot: 1_000_001)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumTotalNormalizedInputBytes: 192 * 1024 * 1024 + 1)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumInputLinesPerSnapshot: Int(MMX_MAX_LINE_COUNT) + 1)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumMetadataEntriesPerSnapshot: 1_025)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumMetadataBytes: 1024 * 1024 + 1)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumWorkUnits: 512 * 1024 * 1024 + 1)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumResultRegions: 3 * 1024 * 1024 + 2)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumMappedSegments: 6 * 1024 * 1024 + 1)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumOutputBytes: 192 * 1024 * 1024 + 1)),
            webpageRequest(threeWayLimits: threeWayWebPageLimits(maximumOutputLines: 3 * 1024 * 1024 + 1)),
            folderOptionRequest(scanLimits: folderScanLimits(maximumDepth: 513)),
            folderOptionRequest(scanLimits: folderScanLimits(maximumEntries: 1_000_001)),
            folderOptionRequest(scanLimits: folderScanLimits(maximumExaminedEntries: 10_000_001)),
            folderOptionRequest(scanLimits: folderScanLimits(maximumIssues: 100_001)),
            folderOptionRequest(scanLimits: folderScanLimits(maximumOpenDirectoryDescriptors: 129)),
            folderOptionRequest(scanLimits: folderScanLimits(maximumPendingEntryNames: 1_000_001)),
            folderOptionRequest(scanLimits: folderScanLimits(maximumRelativePathUTF8Bytes: 16_385)),
            folderOptionRequest(scanLimits: folderScanLimits(maximumTotalAccountedBytes: 1_125_899_906_842_625)),
            folderOptionRequest(threeWay: ThreeWayFolderComparisonOptions(maximumEntriesPerSnapshot: 1_000_001)),
            folderOptionRequest(threeWay: ThreeWayFolderComparisonOptions(maximumResultEntries: 3_000_001)),
            folderOptionRequest(threeWay: ThreeWayFolderComparisonOptions(maximumRelativePathUTF8Bytes: 16_385)),
            folderOptionRequest(threeWay: ThreeWayFolderComparisonOptions(maximumDigestBytes: 1_048_577)),
            folderOptionRequest(threeWay: ThreeWayFolderComparisonOptions(maximumDigestAlgorithmUTF8Bytes: 1_025)),
            folderOptionRequest(threeWay: ThreeWayFolderComparisonOptions(maximumWorkUnits: 256 * 1024 * 1024 + 1))
        ]
        for (request, name, maximum) in fieldCases {
            assertOpenError(.engineLimitExceeded(name: name, maximum: maximum)) {
                try ComparisonOpenRequestPlanner.plan(request)
            }
        }
    }

    func testComprehensiveEngineAndDeclaredLimitBoundaries() {
        let cases: [(ComparisonOpenRequest, ComparisonOpenRequestError)] = [
            (
                ComparisonOpenRequest(
                    left: file("left.csv"),
                    right: file("right.csv"),
                    modeSelection: .explicit(.table),
                    modeOptions: .table(
                        parsing: .commaSeparated,
                        twoWay: TableComparisonOptions(maximumComparedCells: 2_097_153),
                        threeWay: .default
                    )
                ),
                .engineLimitExceeded(name: "table.maximumComparedCells", maximum: 2_097_152)
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.csv"),
                    middle: file("base.csv"),
                    right: file("right.csv"),
                    modeSelection: .explicit(.table),
                    modeOptions: .table(
                        parsing: .commaSeparated,
                        twoWay: .default,
                        threeWay: ThreeWayTableComparisonOptions(maximumResultRows: 3 * 1_048_576 + 1)
                    )
                ),
                .engineLimitExceeded(name: "table.maximumResultRows", maximum: 3 * 1_048_576)
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.bin"),
                    middle: file("base.bin"),
                    right: file("right.bin"),
                    modeSelection: .explicit(.binary),
                    modeOptions: .binary(
                        twoWay: BinaryComparisonOptions(),
                        threeWay: ThreeWayBinaryComparisonOptions(maximumOutputBytes: 192 * 1024 * 1024 + 1)
                    )
                ),
                .engineLimitExceeded(name: "binary.maximumOutputBytes", maximum: 192 * 1024 * 1024)
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.png"),
                    right: file("right.png"),
                    modeSelection: .explicit(.image),
                    modeOptions: .image(
                        loading: .default,
                        comparison: ImageComparisonOptions(maximumRegions: 250_001)
                    )
                ),
                .engineLimitExceeded(name: "image.maximumRegions", maximum: 250_000)
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.html"),
                    middle: file("base.html"),
                    right: file("right.html"),
                    modeSelection: .explicit(.webpage),
                    modeOptions: .webpage(
                        twoWay: .default,
                        threeWay: ThreeWayWebPageComparisonOptions(
                            limits: ThreeWayWebPageComparisonLimits(maximumOutputLines: 3 * 1024 * 1024 + 1)
                        )
                    )
                ),
                .engineLimitExceeded(name: "webpage.maximumOutputLines", maximum: 3 * 1024 * 1024)
            ),
            (
                ComparisonOpenRequest(
                    left: .localFolder(URL(filePath: "/inputs/left", directoryHint: .isDirectory)),
                    middle: .localFolder(URL(filePath: "/inputs/base", directoryHint: .isDirectory)),
                    right: .localFolder(URL(filePath: "/inputs/right", directoryHint: .isDirectory)),
                    modeSelection: .explicit(.folder),
                    modeOptions: .folder(
                        scanning: FolderScanOptions(),
                        twoWay: FolderComparisonOptions(),
                        threeWay: ThreeWayFolderComparisonOptions(maximumResultEntries: 3_000_001)
                    )
                ),
                .engineLimitExceeded(name: "folder.maximumResultEntries", maximum: 3_000_000)
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.bin"),
                    right: file("right.bin"),
                    modeSelection: .explicit(.binary),
                    modeOptions: .binary(
                        twoWay: BinaryComparisonOptions(maximumExactEditDistance: 1, maximumAlignmentWork: 2),
                        threeWay: .default
                    ),
                    limits: ComparisonOpenRequestLimits(maximumDeclaredWorkUnits: 1)
                ),
                .declaredLimitExceeded(name: "binary.maximumAlignmentWork", maximum: 1)
            ),
            (
                ComparisonOpenRequest(
                    left: file("left.html"),
                    right: file("right.html"),
                    modeSelection: .explicit(.webpage),
                    modeOptions: .webpage(
                        twoWay: WebPageComparisonOptions(
                            limits: WebPageComparisonLimits(maximumInputBytes: 2)
                        ),
                        threeWay: .default
                    ),
                    limits: ComparisonOpenRequestLimits(maximumDeclaredBytes: 1)
                ),
                .declaredLimitExceeded(name: "webpage.maximumInputBytes", maximum: 1)
            )
        ]

        for (request, expected) in cases {
            assertOpenError(expected) {
                try ComparisonOpenRequestPlanner.plan(request)
            }
        }
    }

    func testPreCancelledPlanningReturnsDomainCancellation() async {
        let request = ComparisonOpenRequest(left: file("left.txt"), right: file("right.txt"))

        let error = await Task { () -> ComparisonOpenRequestError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ComparisonOpenRequestPlanner.plan(request)
                return nil
            } catch {
                return error as? ComparisonOpenRequestError
            }
        }.value

        XCTAssertEqual(error, .cancelled)
    }

    private func textRequest(
        options: LineDiffOptions,
        limits: ComparisonOpenRequestLimits = .default
    ) -> ComparisonOpenRequest {
        ComparisonOpenRequest(
            left: .scratchpad(text: "left"),
            right: .scratchpad(text: "right"),
            modeSelection: .explicit(.text),
            modeOptions: .text(twoWay: options, threeWay: ThreeWayTextMergeOptions()),
            limits: limits
        )
    }

    private func threeWayTextRequest(
        options: ThreeWayTextMergeOptions
    ) -> ComparisonOpenRequest {
        ComparisonOpenRequest(
            left: .scratchpad(text: "left"),
            middle: .scratchpad(text: "base"),
            right: .scratchpad(text: "right"),
            modeSelection: .explicit(.text),
            modeOptions: .text(twoWay: LineDiffOptions(), threeWay: options)
        )
    }

    private func folderRequest(options: ComparisonOpenModeOptions) -> ComparisonOpenRequest {
        ComparisonOpenRequest(
            left: .localFolder(URL(filePath: "/inputs/left", directoryHint: .isDirectory)),
            right: .localFolder(URL(filePath: "/inputs/right", directoryHint: .isDirectory)),
            modeSelection: .explicit(.folder),
            modeOptions: options
        )
    }

    private func folderRequest(
        filenameFilter: ComparisonOpenFilenameFilter,
        limits: ComparisonOpenRequestLimits
    ) -> ComparisonOpenRequest {
        ComparisonOpenRequest(
            left: .localFolder(URL(filePath: "/inputs/left", directoryHint: .isDirectory)),
            right: .localFolder(URL(filePath: "/inputs/right", directoryHint: .isDirectory)),
            filenameFilter: filenameFilter,
            limits: limits
        )
    }

    private func tableRequest(
        parsing: DelimitedTableParsingOptions = .commaSeparated,
        twoWay: TableComparisonOptions = .default,
        threeWay: ThreeWayTableComparisonOptions = .default
    ) -> (ComparisonOpenRequest, String, Int) {
        let defaults = DelimitedTableLimits.default
        let field: (String, Int)
        if parsing.limits.maximumInputBytes != defaults.maximumInputBytes {
            field = ("table.maximumInputBytes", Int(MMX_MAX_INPUT_SIZE))
        } else if parsing.limits.maximumRows != defaults.maximumRows {
            field = ("table.maximumRows", 1_048_576)
        } else if parsing.limits.maximumColumnsPerRow != defaults.maximumColumnsPerRow {
            field = ("table.maximumColumnsPerRow", 16_384)
        } else if parsing.limits.maximumTotalCells != defaults.maximumTotalCells {
            field = ("table.maximumTotalCells", 1_048_576)
        } else if parsing.limits.maximumCellBytes != defaults.maximumCellBytes {
            field = ("table.maximumCellBytes", 16 * 1024 * 1024)
        } else if twoWay.maximumExactEditDistance != TableComparisonOptions.default.maximumExactEditDistance {
            field = ("table.maximumExactEditDistance", 2_048)
        } else if twoWay.maximumAlignmentWork != TableComparisonOptions.default.maximumAlignmentWork {
            field = ("table.maximumAlignmentWork", 16 * 1024 * 1024)
        } else if twoWay.maximumComparedRows != TableComparisonOptions.default.maximumComparedRows {
            field = ("table.maximumComparedRows", 2_097_152)
        } else if twoWay.maximumComparedCells != TableComparisonOptions.default.maximumComparedCells {
            field = ("table.maximumComparedCells", 2_097_152)
        } else if threeWay.maximumComparedValueBytes != ThreeWayTableComparisonOptions.default.maximumComparedValueBytes {
            field = ("table.maximumComparedValueBytes", 192 * 1024 * 1024)
        } else if threeWay.maximumResultRows != ThreeWayTableComparisonOptions.default.maximumResultRows {
            field = ("table.maximumResultRows", 3 * 1_048_576)
        } else {
            field = ("table.maximumResultCells", 3 * 1_048_576)
        }
        let request =
            if threeWay == .default {
                ComparisonOpenRequest(
                    left: file("left.csv"),
                    right: file("right.csv"),
                    modeSelection: .explicit(.table),
                    modeOptions: .table(parsing: parsing, twoWay: twoWay, threeWay: threeWay)
                )
            } else {
                ComparisonOpenRequest(
                    left: file("left.csv"),
                    middle: file("base.csv"),
                    right: file("right.csv"),
                    modeSelection: .explicit(.table),
                    modeOptions: .table(parsing: parsing, twoWay: twoWay, threeWay: threeWay)
                )
            }
        return (request, field.0, field.1)
    }

    private func binaryRequest(
        twoWay: BinaryComparisonOptions = BinaryComparisonOptions(),
        threeWay: ThreeWayBinaryComparisonOptions = .default
    ) -> (ComparisonOpenRequest, String, Int) {
        let twoWayDefaults = BinaryComparisonOptions()
        let field: (String, Int)
        if twoWay.maximumExactEditDistance != twoWayDefaults.maximumExactEditDistance {
            field = ("binary.maximumExactEditDistance", 2_048)
        } else if twoWay.maximumAlignmentWork != twoWayDefaults.maximumAlignmentWork {
            field = ("binary.maximumAlignmentWork", 16 * 1024 * 1024)
        } else if threeWay.maximumInputBytes != ThreeWayBinaryComparisonOptions.default.maximumInputBytes {
            field = ("binary.maximumInputBytes", 64 * 1024 * 1024)
        } else if threeWay.maximumExactEditDistance != ThreeWayBinaryComparisonOptions.default.maximumExactEditDistance {
            field = ("binary.maximumExactEditDistance", 2_048)
        } else if threeWay.maximumAlignmentWork != ThreeWayBinaryComparisonOptions.default.maximumAlignmentWork {
            field = ("binary.maximumAlignmentWork", 32 * 1024 * 1024)
        } else if threeWay.maximumRegions != ThreeWayBinaryComparisonOptions.default.maximumRegions {
            field = ("binary.maximumRegions", 16 * 1024 * 1024)
        } else {
            field = ("binary.maximumOutputBytes", 192 * 1024 * 1024)
        }
        let request =
            if threeWay == .default {
                ComparisonOpenRequest(
                    left: file("left.bin"),
                    right: file("right.bin"),
                    modeSelection: .explicit(.binary),
                    modeOptions: .binary(twoWay: twoWay, threeWay: threeWay)
                )
            } else {
                ComparisonOpenRequest(
                    left: file("left.bin"),
                    middle: file("base.bin"),
                    right: file("right.bin"),
                    modeSelection: .explicit(.binary),
                    modeOptions: .binary(twoWay: twoWay, threeWay: threeWay)
                )
            }
        return (request, field.0, field.1)
    }

    private func imageLimits(
        maximumEncodedBytes: Int = ImageComparisonLimits.default.maximumEncodedBytes,
        maximumDimension: Int = ImageComparisonLimits.default.maximumDimension,
        maximumPixelCount: Int = ImageComparisonLimits.default.maximumPixelCount,
        maximumDecodedBytes: Int = ImageComparisonLimits.default.maximumDecodedBytes
    ) -> ImageComparisonLimits {
        ImageComparisonLimits(
            maximumEncodedBytes: maximumEncodedBytes,
            maximumDimension: maximumDimension,
            maximumPixelCount: maximumPixelCount,
            maximumDecodedBytes: maximumDecodedBytes
        )
    }

    private func imageRequest(
        loading: ImageComparisonLimits = .default,
        comparison: ImageComparisonOptions = .default
    ) -> (ComparisonOpenRequest, String, Int) {
        let field: (String, Int)
        if loading.maximumEncodedBytes != ImageComparisonLimits.default.maximumEncodedBytes {
            field = ("image.maximumEncodedBytes", Int(MMX_MAX_INPUT_SIZE))
        } else if loading.maximumDimension != ImageComparisonLimits.default.maximumDimension {
            field = ("image.maximumDimension", 16_384)
        } else if loading.maximumPixelCount != ImageComparisonLimits.default.maximumPixelCount {
            field = ("image.maximumPixelCount", 16 * 1024 * 1024)
        } else if loading.maximumDecodedBytes != ImageComparisonLimits.default.maximumDecodedBytes {
            field = ("image.maximumDecodedBytes", 128 * 1024 * 1024)
        } else if comparison.maximumCanvasPixels != ImageComparisonOptions.default.maximumCanvasPixels {
            field = ("image.maximumCanvasPixels", 16 * 1024 * 1024)
        } else if comparison.maximumRegions != ImageComparisonOptions.default.maximumRegions {
            field = ("image.maximumRegions", 250_000)
        } else {
            field = ("image.maximumQueuedPixels", 262_144)
        }
        return (
            ComparisonOpenRequest(
                left: file("left.png"),
                right: file("right.png"),
                modeSelection: .explicit(.image),
                modeOptions: .image(loading: loading, comparison: comparison)
            ),
            field.0,
            field.1
        )
    }

    private func webPageLimits(
        maximumInputBytes: Int = WebPageComparisonLimits.default.maximumInputBytes,
        maximumTokenCount: Int = WebPageComparisonLimits.default.maximumTokenCount,
        maximumAttributeCount: Int = WebPageComparisonLimits.default.maximumAttributeCount,
        maximumAttributesPerTag: Int = WebPageComparisonLimits.default.maximumAttributesPerTag,
        maximumElementDepth: Int = WebPageComparisonLimits.default.maximumElementDepth,
        maximumWorkUnits: Int = WebPageComparisonLimits.default.maximumWorkUnits,
        maximumOutputBytes: Int = WebPageComparisonLimits.default.maximumOutputBytes
    ) -> WebPageComparisonLimits {
        WebPageComparisonLimits(
            maximumInputBytes: maximumInputBytes,
            maximumTokenCount: maximumTokenCount,
            maximumAttributeCount: maximumAttributeCount,
            maximumAttributesPerTag: maximumAttributesPerTag,
            maximumElementDepth: maximumElementDepth,
            maximumWorkUnits: maximumWorkUnits,
            maximumOutputBytes: maximumOutputBytes
        )
    }

    private func threeWayWebPageLimits(
        maximumSourceInputBytesPerSnapshot: Int = ThreeWayWebPageComparisonLimits.default.maximumSourceInputBytesPerSnapshot,
        maximumNormalizedInputBytesPerSnapshot: Int = ThreeWayWebPageComparisonLimits.default.maximumNormalizedInputBytesPerSnapshot,
        maximumTokenCountPerSnapshot: Int = ThreeWayWebPageComparisonLimits.default.maximumTokenCountPerSnapshot,
        maximumAttributeCountPerSnapshot: Int = ThreeWayWebPageComparisonLimits.default.maximumAttributeCountPerSnapshot,
        maximumTotalNormalizedInputBytes: Int = ThreeWayWebPageComparisonLimits.default.maximumTotalNormalizedInputBytes,
        maximumInputLinesPerSnapshot: Int = ThreeWayWebPageComparisonLimits.default.maximumInputLinesPerSnapshot,
        maximumMetadataEntriesPerSnapshot: Int = ThreeWayWebPageComparisonLimits.default.maximumMetadataEntriesPerSnapshot,
        maximumMetadataBytes: Int = ThreeWayWebPageComparisonLimits.default.maximumMetadataBytes,
        maximumWorkUnits: Int = ThreeWayWebPageComparisonLimits.default.maximumWorkUnits,
        maximumResultRegions: Int = ThreeWayWebPageComparisonLimits.default.maximumResultRegions,
        maximumMappedSegments: Int = ThreeWayWebPageComparisonLimits.default.maximumMappedSegments,
        maximumOutputBytes: Int = ThreeWayWebPageComparisonLimits.default.maximumOutputBytes,
        maximumOutputLines: Int = ThreeWayWebPageComparisonLimits.default.maximumOutputLines
    ) -> ThreeWayWebPageComparisonLimits {
        ThreeWayWebPageComparisonLimits(
            maximumSourceInputBytesPerSnapshot: maximumSourceInputBytesPerSnapshot,
            maximumNormalizedInputBytesPerSnapshot: maximumNormalizedInputBytesPerSnapshot,
            maximumTokenCountPerSnapshot: maximumTokenCountPerSnapshot,
            maximumAttributeCountPerSnapshot: maximumAttributeCountPerSnapshot,
            maximumTotalNormalizedInputBytes: maximumTotalNormalizedInputBytes,
            maximumInputLinesPerSnapshot: maximumInputLinesPerSnapshot,
            maximumMetadataEntriesPerSnapshot: maximumMetadataEntriesPerSnapshot,
            maximumMetadataBytes: maximumMetadataBytes,
            maximumWorkUnits: maximumWorkUnits,
            maximumResultRegions: maximumResultRegions,
            maximumMappedSegments: maximumMappedSegments,
            maximumOutputBytes: maximumOutputBytes,
            maximumOutputLines: maximumOutputLines
        )
    }

    private func webpageRequest(
        twoWayLimits: WebPageComparisonLimits = .default,
        threeWayLimits: ThreeWayWebPageComparisonLimits = .default
    ) -> (ComparisonOpenRequest, String, Int) {
        let twoWayDefaults = WebPageComparisonLimits.default
        let threeWayDefaults = ThreeWayWebPageComparisonLimits.default
        let field: (String, Int)
        if twoWayLimits.maximumInputBytes != twoWayDefaults.maximumInputBytes {
            field = ("webpage.maximumInputBytes", Int(MMX_MAX_INPUT_SIZE))
        } else if twoWayLimits.maximumTokenCount != twoWayDefaults.maximumTokenCount {
            field = ("webpage.maximumTokenCount", twoWayDefaults.maximumTokenCount)
        } else if twoWayLimits.maximumAttributeCount != twoWayDefaults.maximumAttributeCount {
            field = ("webpage.maximumAttributeCount", twoWayDefaults.maximumAttributeCount)
        } else if twoWayLimits.maximumAttributesPerTag != twoWayDefaults.maximumAttributesPerTag {
            field = ("webpage.maximumAttributesPerTag", twoWayDefaults.maximumAttributesPerTag)
        } else if twoWayLimits.maximumElementDepth != twoWayDefaults.maximumElementDepth {
            field = ("webpage.maximumElementDepth", twoWayDefaults.maximumElementDepth)
        } else if twoWayLimits.maximumWorkUnits != twoWayDefaults.maximumWorkUnits {
            field = ("webpage.maximumWorkUnits", twoWayDefaults.maximumWorkUnits)
        } else if twoWayLimits.maximumOutputBytes != twoWayDefaults.maximumOutputBytes {
            field = ("webpage.maximumOutputBytes", Int(MMX_MAX_INPUT_SIZE))
        } else if threeWayLimits.maximumSourceInputBytesPerSnapshot != threeWayDefaults.maximumSourceInputBytesPerSnapshot {
            field = ("webpage.maximumSourceInputBytes", 64 * 1024 * 1024)
        } else if threeWayLimits.maximumNormalizedInputBytesPerSnapshot != threeWayDefaults.maximumNormalizedInputBytesPerSnapshot {
            field = ("webpage.maximumNormalizedInputBytes", 64 * 1024 * 1024)
        } else if threeWayLimits.maximumTokenCountPerSnapshot != threeWayDefaults.maximumTokenCountPerSnapshot {
            field = ("webpage.maximumTokenCount", threeWayDefaults.maximumTokenCountPerSnapshot)
        } else if threeWayLimits.maximumAttributeCountPerSnapshot != threeWayDefaults.maximumAttributeCountPerSnapshot {
            field = ("webpage.maximumAttributeCount", threeWayDefaults.maximumAttributeCountPerSnapshot)
        } else if threeWayLimits.maximumTotalNormalizedInputBytes != threeWayDefaults.maximumTotalNormalizedInputBytes {
            field = ("webpage.maximumTotalNormalizedInputBytes", 192 * 1024 * 1024)
        } else if threeWayLimits.maximumInputLinesPerSnapshot != threeWayDefaults.maximumInputLinesPerSnapshot {
            field = ("webpage.maximumInputLines", Int(MMX_MAX_LINE_COUNT))
        } else if threeWayLimits.maximumMetadataEntriesPerSnapshot != threeWayDefaults.maximumMetadataEntriesPerSnapshot {
            field = ("webpage.maximumMetadataEntries", threeWayDefaults.maximumMetadataEntriesPerSnapshot)
        } else if threeWayLimits.maximumMetadataBytes != threeWayDefaults.maximumMetadataBytes {
            field = ("webpage.maximumMetadataBytes", threeWayDefaults.maximumMetadataBytes)
        } else if threeWayLimits.maximumWorkUnits != threeWayDefaults.maximumWorkUnits {
            field = ("webpage.maximumWorkUnits", 512 * 1024 * 1024)
        } else if threeWayLimits.maximumResultRegions != threeWayDefaults.maximumResultRegions {
            field = ("webpage.maximumResultRegions", 3 * 1024 * 1024 + 1)
        } else if threeWayLimits.maximumMappedSegments != threeWayDefaults.maximumMappedSegments {
            field = ("webpage.maximumMappedSegments", threeWayDefaults.maximumMappedSegments)
        } else if threeWayLimits.maximumOutputBytes != threeWayDefaults.maximumOutputBytes {
            field = ("webpage.maximumOutputBytes", 192 * 1024 * 1024)
        } else {
            field = ("webpage.maximumOutputLines", 3 * 1024 * 1024)
        }
        return (
            ComparisonOpenRequest(
                left: file("left.html"),
                middle: file("base.html"),
                right: file("right.html"),
                modeSelection: .explicit(.webpage),
                modeOptions: .webpage(
                    twoWay: WebPageComparisonOptions(limits: twoWayLimits),
                    threeWay: ThreeWayWebPageComparisonOptions(limits: threeWayLimits)
                )
            ),
            field.0,
            field.1
        )
    }

    private func folderScanLimits(
        maximumDepth: Int = 512,
        maximumEntries: Int = 1_000_000,
        maximumExaminedEntries: Int = 10_000_000,
        maximumIssues: Int = 100_000,
        maximumOpenDirectoryDescriptors: Int = 128,
        maximumPendingEntryNames: Int = 1_000_000,
        maximumRelativePathUTF8Bytes: Int = 16_384,
        maximumTotalAccountedBytes: Int64 = 1_125_899_906_842_624
    ) -> FolderScanLimits {
        FolderScanLimits(
            maximumDepth: maximumDepth,
            maximumEntries: maximumEntries,
            maximumIssues: maximumIssues,
            maximumRelativePathUTF8Bytes: maximumRelativePathUTF8Bytes,
            maximumTotalAccountedBytes: maximumTotalAccountedBytes,
            maximumExaminedEntries: maximumExaminedEntries,
            maximumOpenDirectoryDescriptors: maximumOpenDirectoryDescriptors,
            maximumPendingEntryNames: maximumPendingEntryNames
        )
    }

    private func folderOptionRequest(
        scanLimits: FolderScanLimits = FolderScanLimits(),
        threeWay: ThreeWayFolderComparisonOptions = .default
    ) -> (ComparisonOpenRequest, String, Int) {
        let defaults = FolderScanLimits()
        let threeWayDefaults = ThreeWayFolderComparisonOptions.default
        let field: (String, Int)
        if scanLimits.maximumDepth != defaults.maximumDepth {
            field = ("folder.maximumDepth", 512)
        } else if scanLimits.maximumEntries != defaults.maximumEntries {
            field = ("folder.maximumEntries", 1_000_000)
        } else if scanLimits.maximumExaminedEntries != defaults.maximumExaminedEntries {
            field = ("folder.maximumExaminedEntries", 10_000_000)
        } else if scanLimits.maximumIssues != defaults.maximumIssues {
            field = ("folder.maximumIssues", 100_000)
        } else if scanLimits.maximumOpenDirectoryDescriptors != defaults.maximumOpenDirectoryDescriptors {
            field = ("folder.maximumOpenDirectoryDescriptors", 128)
        } else if scanLimits.maximumPendingEntryNames != defaults.maximumPendingEntryNames {
            field = ("folder.maximumPendingEntryNames", 1_000_000)
        } else if scanLimits.maximumRelativePathUTF8Bytes != defaults.maximumRelativePathUTF8Bytes {
            field = ("folder.maximumRelativePathUTF8Bytes", 16_384)
        } else if scanLimits.maximumTotalAccountedBytes != defaults.maximumTotalAccountedBytes {
            field = ("folder.maximumTotalAccountedBytes", 1_125_899_906_842_624)
        } else if threeWay.maximumEntriesPerSnapshot != threeWayDefaults.maximumEntriesPerSnapshot {
            field = ("folder.maximumEntriesPerSnapshot", 1_000_000)
        } else if threeWay.maximumResultEntries != threeWayDefaults.maximumResultEntries {
            field = ("folder.maximumResultEntries", 3_000_000)
        } else if threeWay.maximumRelativePathUTF8Bytes != threeWayDefaults.maximumRelativePathUTF8Bytes {
            field = ("folder.maximumRelativePathUTF8Bytes", 16_384)
        } else if threeWay.maximumDigestBytes != threeWayDefaults.maximumDigestBytes {
            field = ("folder.maximumDigestBytes", 1_048_576)
        } else if threeWay.maximumDigestAlgorithmUTF8Bytes != threeWayDefaults.maximumDigestAlgorithmUTF8Bytes {
            field = ("folder.maximumDigestAlgorithmUTF8Bytes", 1_024)
        } else {
            field = ("folder.maximumWorkUnits", 256 * 1024 * 1024)
        }
        return (
            ComparisonOpenRequest(
                left: .localFolder(URL(filePath: "/inputs/left", directoryHint: .isDirectory)),
                middle: .localFolder(URL(filePath: "/inputs/base", directoryHint: .isDirectory)),
                right: .localFolder(URL(filePath: "/inputs/right", directoryHint: .isDirectory)),
                modeSelection: .explicit(.folder),
                modeOptions: .folder(
                    scanning: FolderScanOptions(limits: scanLimits),
                    twoWay: FolderComparisonOptions(),
                    threeWay: threeWay
                )
            ),
            field.0,
            field.1
        )
    }

    private func filenameFilterLimits(
        maximumRuleCount: Int = FilenameFilterLimits.default.maximumRuleCount,
        maximumPatternUTF8Bytes: Int = FilenameFilterLimits.default.maximumPatternUTF8Bytes,
        maximumTotalPatternUTF8Bytes: Int = FilenameFilterLimits.default.maximumTotalPatternUTF8Bytes,
        maximumRelativePathUTF8Bytes: Int = FilenameFilterLimits.default.maximumRelativePathUTF8Bytes,
        maximumCompiledStateCount: Int = FilenameFilterLimits.default.maximumCompiledStateCount,
        maximumMatchWork: Int = FilenameFilterLimits.default.maximumMatchWork,
        maximumRegularExpressionNestingDepth: Int = FilenameFilterLimits.default.maximumRegularExpressionNestingDepth,
        maximumRegularExpressionRepetition: Int = FilenameFilterLimits.default.maximumRegularExpressionRepetition
    ) -> FilenameFilterLimits {
        FilenameFilterLimits(
            maximumRuleCount: maximumRuleCount,
            maximumPatternUTF8Bytes: maximumPatternUTF8Bytes,
            maximumTotalPatternUTF8Bytes: maximumTotalPatternUTF8Bytes,
            maximumRelativePathUTF8Bytes: maximumRelativePathUTF8Bytes,
            maximumCompiledStateCount: maximumCompiledStateCount,
            maximumMatchWork: maximumMatchWork,
            maximumRegularExpressionNestingDepth: maximumRegularExpressionNestingDepth,
            maximumRegularExpressionRepetition: maximumRegularExpressionRepetition
        )
    }

    private func requestLimits(
        overriding limit: ComparisonOpenRequestLimit,
        with value: Int
    ) -> ComparisonOpenRequestLimits {
        let defaults = ComparisonOpenRequestLimits.default
        return ComparisonOpenRequestLimits(
            maximumPathUTF8Bytes: limit == .pathUTF8Bytes ? value : defaults.maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: limit == .totalPathUTF8Bytes ? value : defaults.maximumTotalPathUTF8Bytes,
            maximumRemoteURLUTF8Bytes: limit == .remoteURLUTF8Bytes ? value : defaults.maximumRemoteURLUTF8Bytes,
            maximumScratchpadUTF8Bytes: limit == .scratchpadUTF8Bytes ? value : defaults.maximumScratchpadUTF8Bytes,
            maximumCombinedScratchpadUTF8Bytes: limit == .combinedScratchpadUTF8Bytes
                ? value : defaults.maximumCombinedScratchpadUTF8Bytes,
            maximumLabelUTF8Bytes: limit == .labelUTF8Bytes ? value : defaults.maximumLabelUTF8Bytes,
            maximumOptionItemCount: limit == .optionItemCount ? value : defaults.maximumOptionItemCount,
            maximumOptionStringUTF8Bytes: limit == .optionStringUTF8Bytes ? value : defaults.maximumOptionStringUTF8Bytes,
            maximumTotalOptionStringUTF8Bytes: limit == .totalOptionStringUTF8Bytes
                ? value : defaults.maximumTotalOptionStringUTF8Bytes,
            maximumDeclaredBytes: limit == .declaredBytes ? value : defaults.maximumDeclaredBytes,
            maximumDeclaredWorkUnits: limit == .declaredWorkUnits ? value : defaults.maximumDeclaredWorkUnits,
            maximumPlanningWorkUnits: limit == .planningWorkUnits ? value : defaults.maximumPlanningWorkUnits
        )
    }

    private func file(_ name: String) -> ComparisonOpenSource {
        .localFile(URL(filePath: "/inputs/\(name)"))
    }

    private func side(
        _ position: ComparisonOpenSidePosition,
        _ source: ComparisonOpenSource,
        readOnly: Bool = false
    ) -> ComparisonOpenSide {
        ComparisonOpenSide(position: position, source: source, readOnly: readOnly)
    }

    private func identity(_ byte: UInt8) -> ComparisonOpenRequestIdentity {
        ComparisonOpenRequestIdentity(
            rawValue: UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )
    }

    private func assertOpenError<T>(
        _ expected: ComparisonOpenRequestError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ComparisonOpenRequestError, expected, file: file, line: line)
        }
    }
}
