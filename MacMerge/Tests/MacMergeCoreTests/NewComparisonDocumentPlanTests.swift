import Foundation
import MacMergeCore
import XCTest

final class NewComparisonDocumentPlanTests: XCTestCase {
    typealias Plan = NewComparisonDocumentPlan
    typealias PlanError = NewComparisonDocumentPlanError

    func testEveryCommandMapsToModePaneCountAndCanonicalPanes() throws {
        let cases: [(Plan.Command, Plan.Mode, Plan.PaneCount)] = [
            (.twoWayText, .text, .two),
            (.twoWayTable, .table, .two),
            (.twoWayBinary, .binary, .two),
            (.twoWayImage, .image, .two),
            (.twoWayWebpage, .webpage, .two),
            (.twoWayFolder, .folder, .two),
            (.threeWayText, .text, .three),
            (.threeWayTable, .table, .three),
            (.threeWayBinary, .binary, .three),
            (.threeWayImage, .image, .three),
            (.threeWayWebpage, .webpage, .three),
            (.threeWayFolder, .folder, .three)
        ]

        XCTAssertEqual(Plan.Command.allCases, cases.map(\.0))
        XCTAssertEqual(Plan.Command.default, .twoWayText)
        XCTAssertEqual(Plan.Mode.default, .text)
        XCTAssertEqual(Plan.PaneCount.default, .two)

        for (command, mode, paneCount) in cases {
            XCTAssertEqual(command.mode, mode, command.rawValue)
            XCTAssertEqual(command.paneCount, paneCount, command.rawValue)
            XCTAssertEqual(Plan.Command(mode: mode, paneCount: paneCount), command)
            XCTAssertEqual(Plan.command(for: mode, paneCount: paneCount), command)

            let options = try validatedOptions(mode: mode, paneCount: paneCount)
            let plan = try Plan.make(command: command, modeOptions: options)

            XCTAssertEqual(plan.command, command)
            XCTAssertEqual(plan.mode, mode)
            XCTAssertEqual(plan.paneCount, paneCount)
            XCTAssertEqual(plan.panes.map(\.pane), paneCount.panes)
            XCTAssertEqual(plan.panes.map(\.source), expectedSources(mode: mode, paneCount: paneCount))
            XCTAssertEqual(plan.modeOptions, options)
            XCTAssertEqual(plan.capability, Plan.capability(for: mode))
            XCTAssertEqual(plan.sourceSemantics, plan.capability.sourceSemantics)
            XCTAssertGreaterThan(plan.workPerformed, 0)
        }
    }

    func testModeAndPaneMappingsCoverEveryCase() {
        let modeCases: [(Plan.Mode, ComparisonProject.Mode)] = [
            (.text, .text),
            (.table, .table),
            (.binary, .binary),
            (.image, .image),
            (.webpage, .webpage),
            (.folder, .folder)
        ]
        XCTAssertEqual(Plan.Mode.allCases, modeCases.map(\.0))
        for (mode, projectMode) in modeCases {
            XCTAssertEqual(mode.comparisonProjectMode, projectMode)
            XCTAssertEqual(Plan.Mode(comparisonProjectMode: projectMode), mode)
        }
        XCTAssertNil(Plan.Mode(comparisonProjectMode: .automatic))

        XCTAssertEqual(Plan.PaneCount.allCases, [.two, .three])
        XCTAssertEqual(Plan.PaneCount.two.rawValue, 2)
        XCTAssertEqual(Plan.PaneCount.two.panes, [.left, .right])
        XCTAssertEqual(Plan.PaneCount.two.paneLayoutPaneCount, .two)
        XCTAssertEqual(Plan.PaneCount.three.rawValue, 3)
        XCTAssertEqual(Plan.PaneCount.three.panes, [.left, .middle, .right])
        XCTAssertEqual(Plan.PaneCount.three.paneLayoutPaneCount, .three)

        XCTAssertEqual(Plan.Pane.allCases, [.left, .middle, .right])
        XCTAssertEqual(Plan.Pane.left.identity, .left)
        XCTAssertEqual(Plan.Pane.middle.identity, .middle)
        XCTAssertEqual(Plan.Pane.right.identity, .right)
    }

    func testCapabilitiesDescribeAllModesAndSourceRequirements() {
        let expected: [(Plan.Mode, Plan.SourceSemantics, Bool)] = [
            (.text, .scratchpad(.text), false),
            (.table, .scratchpad(.text), false),
            (.binary, .scratchpad(.binary), false),
            (.image, .emptyImage, false),
            (.webpage, .blankWebpage, false),
            (.folder, .requiredSource(.emptyFolder), true)
        ]

        XCTAssertEqual(Plan.capabilities.map(\.mode), Plan.Mode.allCases)
        for (mode, semantics, requiresMaterialization) in expected {
            let capability = Plan.capability(for: mode)
            XCTAssertEqual(capability.mode, mode)
            XCTAssertEqual(capability.supportedPaneCounts, [.two, .three])
            XCTAssertEqual(capability.sourceSemantics, semantics)
            XCTAssertEqual(capability.documentCreationSupport, .planningOnly)
            XCTAssertTrue(capability.supportsTwoWay)
            XCTAssertTrue(capability.supportsThreeWay)
            XCTAssertTrue(capability.supports(.two))
            XCTAssertTrue(capability.supports(.three))
            XCTAssertEqual(capability.requiresSourceMaterialization, requiresMaterialization)
        }
    }

    func testImageWebpageAndFolderPlansExposeMaterializationIntentsOnly() throws {
        for paneCount in Plan.PaneCount.allCases {
            let image = try makePlan(mode: .image, paneCount: paneCount)
            XCTAssertEqual(image.panes.map(\.source), Array(repeating: .emptyImage, count: paneCount.rawValue))
            XCTAssertTrue(image.scratchpads.isEmpty)
            XCTAssertTrue(image.requiredSources.isEmpty)
            XCTAssertFalse(image.requiresSourceMaterialization)

            let webpage = try makePlan(mode: .webpage, paneCount: paneCount)
            XCTAssertEqual(webpage.panes.map(\.source), Array(repeating: .blankWebpage, count: paneCount.rawValue))
            XCTAssertTrue(webpage.scratchpads.isEmpty)
            XCTAssertTrue(webpage.requiredSources.isEmpty)
            XCTAssertFalse(webpage.requiresSourceMaterialization)

            let folder = try makePlan(mode: .folder, paneCount: paneCount)
            XCTAssertEqual(
                folder.panes.map(\.source),
                Array(repeating: .requiredSource(.emptyFolder), count: paneCount.rawValue)
            )
            XCTAssertEqual(folder.requiredSources, folder.panes)
            XCTAssertTrue(folder.scratchpads.isEmpty)
            XCTAssertTrue(folder.requiresSourceMaterialization)
        }
    }

    func testScratchpadModesProvideCorrectEmptyDefaults() throws {
        for paneCount in Plan.PaneCount.allCases {
            for mode in [Plan.Mode.text, .table, .binary] {
                let plan = try makePlan(mode: mode, paneCount: paneCount)
                let expectedContent: Plan.ScratchpadContent =
                    mode == .binary
                    ? .binary(Data())
                    : .text("")

                XCTAssertEqual(plan.scratchpads.map(\.pane), paneCount.panes)
                XCTAssertEqual(
                    plan.scratchpads.map(\.content),
                    Array(repeating: expectedContent, count: paneCount.rawValue)
                )
                XCTAssertTrue(plan.requiredSources.isEmpty)
                XCTAssertFalse(plan.requiresSourceMaterialization)
            }
        }
    }

    func testCustomTextAndBinaryScratchpadContentsAreRetainedInCanonicalPaneOrder() throws {
        let textOptions = try validatedOptions(mode: .text, paneCount: .three)
        let textScratchpads = [
            Plan.Scratchpad(pane: .right, label: "Right", content: .text("right\r\ntext")),
            Plan.Scratchpad(pane: .left, label: "Left", content: .text("left\ntext")),
            Plan.Scratchpad(pane: .middle, label: "Base", content: .text("base\rtext"))
        ]
        let textPlan = try Plan.make(
            command: .threeWayText,
            scratchpads: textScratchpads,
            modeOptions: textOptions
        )
        let expectedTextScratchpads = [textScratchpads[1], textScratchpads[2], textScratchpads[0]]
        XCTAssertEqual(textPlan.scratchpads, expectedTextScratchpads)
        XCTAssertEqual(
            textPlan.panes.map(\.source),
            expectedTextScratchpads.map { .scratchpad($0.content) }
        )

        let binaryOptions = try validatedOptions(mode: .binary, paneCount: .two)
        let binaryScratchpads = [
            Plan.Scratchpad(
                pane: .right,
                label: "Right",
                content: .binary(Data([0x00, 0x7F, 0xFF]))
            ),
            Plan.Scratchpad(
                pane: .left,
                label: "Left",
                content: .binary(Data([0xDE, 0xAD, 0xBE, 0xEF]))
            )
        ]
        let binaryPlan = try Plan.make(
            command: .twoWayBinary,
            scratchpads: binaryScratchpads,
            modeOptions: binaryOptions
        )
        let expectedBinaryScratchpads = [binaryScratchpads[1], binaryScratchpads[0]]
        XCTAssertEqual(binaryPlan.scratchpads, expectedBinaryScratchpads)
        XCTAssertEqual(
            binaryPlan.panes.map(\.source),
            expectedBinaryScratchpads.map { .scratchpad($0.content) }
        )
    }

    func testDefaultAndCallerLabelsRetainLocalizationIntent() throws {
        let expectedDefaults: [(Plan.Pane, String)] = [
            (.left, "Untitled Left"),
            (.middle, "Untitled Middle"),
            (.right, "Untitled Right")
        ]
        for (pane, fallback) in expectedDefaults {
            XCTAssertEqual(pane.defaultLabel.resolvedValue, fallback)
            XCTAssertNotNil(pane.defaultLabel.localizationResource)
            XCTAssertEqual(Plan.Scratchpad(pane: pane, content: .text("")).label, pane.defaultLabel)
        }

        let literal: Plan.PaneLabel = "Caller Label"
        XCTAssertEqual(literal.resolvedValue, "Caller Label")
        XCTAssertNil(literal.localizationResource)

        let options = try validatedOptions(mode: .text, paneCount: .three)
        let scratchpads = [
            Plan.Scratchpad(pane: .right, label: "Right", content: .text("r")),
            Plan.Scratchpad(pane: .left, label: "Left", content: .text("l")),
            Plan.Scratchpad(pane: .middle, label: "Base", content: .text("m"))
        ]
        let plan = try Plan.make(
            mode: .text,
            paneCount: .three,
            scratchpads: scratchpads,
            modeOptions: options
        )

        XCTAssertEqual(plan.panes.map(\.pane), [.left, .middle, .right])
        XCTAssertEqual(plan.panes.map(\.label.resolvedValue), ["Left", "Base", "Right"])
        XCTAssertTrue(plan.panes.allSatisfy { $0.label.localizationResource == nil })
    }

    func testValidatedModeOptionsRequireCurrentExplicitNondefaultPlan() throws {
        for paneCount in Plan.PaneCount.allCases {
            for mode in Plan.Mode.allCases {
                let fixture = try openFixture(mode: mode, paneCount: paneCount)
                let options = try XCTUnwrap(
                    Plan.ValidatedModeOptions(fixture.plan, currentRequest: fixture.request)
                )

                XCTAssertEqual(options.requestIdentity, fixture.request.identity)
                XCTAssertEqual(options.mode, mode)
                XCTAssertEqual(options.paneCount, paneCount)
                XCTAssertEqual(options.value, fixture.plan.modeOptions)
            }
        }

        let defaultRequest = comparisonOpenRequest(
            mode: .text,
            paneCount: .two,
            modeOptions: .defaults,
            identityByte: 40
        )
        let defaultPlan = try ComparisonOpenRequestPlanner.plan(defaultRequest)
        XCTAssertNil(try Plan.ValidatedModeOptions(defaultPlan, currentRequest: defaultRequest))

        let staleRequest = comparisonOpenRequest(
            mode: .text,
            paneCount: .two,
            modeOptions: .defaults,
            identityByte: 41
        )
        assertError(
            ComparisonOpenRequestError.staleRequest(
                expected: defaultRequest.identity,
                actual: staleRequest.identity
            )
        ) {
            try Plan.ValidatedModeOptions(defaultPlan, currentRequest: staleRequest)
        }
    }

    func testModeOptionsMustMatchBothModeAndPaneCount() throws {
        let threeWayText = try validatedOptions(mode: .text, paneCount: .three)
        assertPlanError(
            .modeOptionsMismatch(
                expectedMode: .text,
                expectedPaneCount: .two,
                actualMode: .text,
                actualPaneCount: .three
            )
        ) {
            try Plan.make(command: .twoWayText, modeOptions: threeWayText)
        }

        let twoWayBinary = try validatedOptions(mode: .binary, paneCount: .two)
        assertPlanError(
            .modeOptionsMismatch(
                expectedMode: .text,
                expectedPaneCount: .two,
                actualMode: .binary,
                actualPaneCount: .two
            )
        ) {
            try Plan.make(command: .twoWayText, modeOptions: twoWayBinary)
        }
    }

    func testLimitsValidateEveryLowerUpperAndRelationalBoundary() throws {
        let invalidCases: [(Plan.Limits, PlanError)] = [
            (limits(maximumPaneCount: 1), .invalidLimit(.paneCount, value: 1)),
            (
                limits(maximumPaneCount: Plan.Limits.hardMaximumPaneCount + 1),
                .invalidLimit(.paneCount, value: Plan.Limits.hardMaximumPaneCount + 1)
            ),
            (limits(maximumScratchpadBytes: -1), .invalidLimit(.scratchpadBytes, value: -1)),
            (
                limits(maximumScratchpadBytes: Plan.Limits.hardMaximumScratchpadBytes + 1),
                .invalidLimit(.scratchpadBytes, value: Plan.Limits.hardMaximumScratchpadBytes + 1)
            ),
            (
                limits(maximumCombinedScratchpadBytes: -1),
                .invalidLimit(.combinedScratchpadBytes, value: -1)
            ),
            (
                limits(
                    maximumCombinedScratchpadBytes: Plan.Limits.hardMaximumCombinedScratchpadBytes + 1
                ),
                .invalidLimit(
                    .combinedScratchpadBytes,
                    value: Plan.Limits.hardMaximumCombinedScratchpadBytes + 1
                )
            ),
            (
                limits(maximumScratchpadBytes: 2, maximumCombinedScratchpadBytes: 1),
                .invalidLimit(.combinedScratchpadBytes, value: 1)
            ),
            (limits(maximumLabelUTF8Bytes: 0), .invalidLimit(.labelUTF8Bytes, value: 0)),
            (
                limits(maximumLabelUTF8Bytes: Plan.Limits.hardMaximumLabelUTF8Bytes + 1),
                .invalidLimit(.labelUTF8Bytes, value: Plan.Limits.hardMaximumLabelUTF8Bytes + 1)
            ),
            (limits(maximumPlanningWorkUnits: 0), .invalidLimit(.planningWorkUnits, value: 0)),
            (
                limits(maximumPlanningWorkUnits: Plan.Limits.hardMaximumPlanningWorkUnits + 1),
                .invalidLimit(
                    .planningWorkUnits,
                    value: Plan.Limits.hardMaximumPlanningWorkUnits + 1
                )
            ),
            (
                limits(cancellationCheckInterval: 0),
                .invalidLimit(.cancellationCheckInterval, value: 0)
            ),
            (
                limits(
                    cancellationCheckInterval: Plan.Limits.hardMaximumCancellationCheckInterval + 1
                ),
                .invalidLimit(
                    .cancellationCheckInterval,
                    value: Plan.Limits.hardMaximumCancellationCheckInterval + 1
                )
            )
        ]
        for (value, expected) in invalidCases {
            assertPlanError(expected) { try value.validate() }
        }

        let validCases = [
            limits(
                maximumPaneCount: 2,
                maximumScratchpadBytes: 0,
                maximumCombinedScratchpadBytes: 0,
                maximumLabelUTF8Bytes: 1,
                maximumPlanningWorkUnits: 1,
                cancellationCheckInterval: 1
            ),
            limits(
                maximumPaneCount: Plan.Limits.hardMaximumPaneCount,
                maximumScratchpadBytes: Plan.Limits.hardMaximumScratchpadBytes,
                maximumCombinedScratchpadBytes: Plan.Limits.hardMaximumCombinedScratchpadBytes,
                maximumLabelUTF8Bytes: Plan.Limits.hardMaximumLabelUTF8Bytes,
                maximumPlanningWorkUnits: Plan.Limits.hardMaximumPlanningWorkUnits,
                cancellationCheckInterval: Plan.Limits.hardMaximumCancellationCheckInterval
            )
        ]
        for value in validCases {
            XCTAssertNoThrow(try value.validate())
        }
    }

    func testPaneCountLimitRejectsThreeWayAfterValidLimitConfiguration() throws {
        let options = try validatedOptions(mode: .image, paneCount: .three)
        assertPlanError(.paneLimitExceeded(requested: .three, maximum: 2)) {
            try Plan.make(
                command: .threeWayImage,
                modeOptions: options,
                limits: limits(maximumPaneCount: 2)
            )
        }
    }

    func testPerPaneAndCombinedByteBoundsAcceptExactAndRejectOneOver() throws {
        let options = try validatedOptions(mode: .text, paneCount: .two)
        let exactScratchpads = [
            Plan.Scratchpad(pane: .left, label: "L", content: .text("éa")),
            Plan.Scratchpad(pane: .right, label: "R", content: .text("xyz"))
        ]
        let exactLimits = limits(
            maximumScratchpadBytes: 3,
            maximumCombinedScratchpadBytes: 6,
            maximumLabelUTF8Bytes: 1
        )
        XCTAssertNoThrow(
            try Plan.make(
                command: .twoWayText,
                scratchpads: exactScratchpads,
                modeOptions: options,
                limits: exactLimits
            )
        )

        var perPaneOver = exactScratchpads
        perPaneOver[0] = Plan.Scratchpad(pane: .left, label: "L", content: .text("four"))
        assertPlanError(.scratchpadTooLarge(pane: .left, maximumBytes: 3)) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: perPaneOver,
                modeOptions: options,
                limits: exactLimits
            )
        }

        assertPlanError(.combinedScratchpadsTooLarge(maximumBytes: 5)) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: exactScratchpads,
                modeOptions: options,
                limits: limits(
                    maximumScratchpadBytes: 3,
                    maximumCombinedScratchpadBytes: 5,
                    maximumLabelUTF8Bytes: 1
                )
            )
        }

        XCTAssertNoThrow(
            try Plan.make(
                command: .twoWayText,
                modeOptions: options,
                limits: limits(
                    maximumScratchpadBytes: 0,
                    maximumCombinedScratchpadBytes: 0
                )
            )
        )
    }

    func testTwoWayModeOptionScratchpadLimitsAreActiveOnlyForTableParsing() throws {
        let tableOptions = try validatedOptions(
            mode: .table,
            paneCount: .two,
            maximumInputBytes: 3
        )
        let exactTableScratchpads = [
            Plan.Scratchpad(pane: .left, content: .text("abc")),
            Plan.Scratchpad(pane: .right, content: .text("x"))
        ]
        let tablePlan = try Plan.make(
            command: .twoWayTable,
            scratchpads: exactTableScratchpads,
            modeOptions: tableOptions
        )
        XCTAssertEqual(tablePlan.scratchpads.map(\.content), [.text("abc"), .text("x")])
        assertPlanError(.scratchpadTooLarge(pane: .left, maximumBytes: 3)) {
            try Plan.make(
                command: .twoWayTable,
                scratchpads: [
                    Plan.Scratchpad(pane: .left, content: .text("abcd")),
                    Plan.Scratchpad(pane: .right, content: .text("x"))
                ],
                modeOptions: tableOptions
            )
        }

        let textOptions = try validatedOptions(
            mode: .text,
            paneCount: .two,
            maximumInputBytes: 1,
            maximumInputLines: 1
        )
        let textPlan = try Plan.make(
            command: .twoWayText,
            scratchpads: [
                Plan.Scratchpad(pane: .left, content: .text("a\nb")),
                Plan.Scratchpad(pane: .right, content: .text("right"))
            ],
            modeOptions: textOptions
        )
        XCTAssertEqual(textPlan.scratchpads.map(\.content), [.text("a\nb"), .text("right")])

        let binaryOptions = try validatedOptions(
            mode: .binary,
            paneCount: .two,
            maximumInputBytes: 1
        )
        let binaryPlan = try Plan.make(
            command: .twoWayBinary,
            scratchpads: [
                Plan.Scratchpad(pane: .left, content: .binary(Data([1, 2]))),
                Plan.Scratchpad(pane: .right, content: .binary(Data([3, 4, 5])))
            ],
            modeOptions: binaryOptions
        )
        XCTAssertEqual(
            binaryPlan.scratchpads.map(\.content),
            [.binary(Data([1, 2])), .binary(Data([3, 4, 5]))]
        )
    }

    func testThreeWayModeOptionsConstrainTextTableAndBinaryScratchpads() throws {
        let textByteOptions = try validatedOptions(
            mode: .text,
            paneCount: .three,
            maximumInputBytes: 4,
            maximumInputLines: 10
        )
        XCTAssertNoThrow(
            try Plan.make(
                command: .threeWayText,
                scratchpads: scratchpads(.text("1234"), .text("b"), .text("r")),
                modeOptions: textByteOptions
            )
        )
        assertPlanError(.scratchpadTooLarge(pane: .left, maximumBytes: 4)) {
            try Plan.make(
                command: .threeWayText,
                scratchpads: scratchpads(.text("12345"), .text("b"), .text("r")),
                modeOptions: textByteOptions
            )
        }

        let textLineOptions = try validatedOptions(
            mode: .text,
            paneCount: .three,
            maximumInputBytes: 32,
            maximumInputLines: 2
        )
        XCTAssertNoThrow(
            try Plan.make(
                command: .threeWayText,
                scratchpads: scratchpads(.text("a\r\nb"), .text("b"), .text("r")),
                modeOptions: textLineOptions
            )
        )
        assertPlanError(.scratchpadLineLimitExceeded(pane: .left, maximumLines: 2)) {
            try Plan.make(
                command: .threeWayText,
                scratchpads: scratchpads(.text("a\rb\nc"), .text("b"), .text("r")),
                modeOptions: textLineOptions
            )
        }

        let tableOptions = try validatedOptions(
            mode: .table,
            paneCount: .three,
            maximumInputBytes: 3
        )
        XCTAssertNoThrow(
            try Plan.make(
                command: .threeWayTable,
                scratchpads: scratchpads(.text("abc"), .text("b"), .text("r")),
                modeOptions: tableOptions
            )
        )
        assertPlanError(.scratchpadTooLarge(pane: .left, maximumBytes: 3)) {
            try Plan.make(
                command: .threeWayTable,
                scratchpads: scratchpads(.text("abcd"), .text("b"), .text("r")),
                modeOptions: tableOptions
            )
        }

        let binaryOptions = try validatedOptions(
            mode: .binary,
            paneCount: .three,
            maximumInputBytes: 3
        )
        XCTAssertNoThrow(
            try Plan.make(
                command: .threeWayBinary,
                scratchpads: scratchpads(
                    .binary(Data([1, 2, 3])),
                    .binary(Data([4])),
                    .binary(Data([5]))
                ),
                modeOptions: binaryOptions
            )
        )
        assertPlanError(.scratchpadTooLarge(pane: .left, maximumBytes: 3)) {
            try Plan.make(
                command: .threeWayBinary,
                scratchpads: scratchpads(
                    .binary(Data([1, 2, 3, 4])),
                    .binary(Data([5])),
                    .binary(Data([6]))
                ),
                modeOptions: binaryOptions
            )
        }
    }

    func testThreeWayTextTerminalLineLimitAcceptsExactAndRejectsOverForEveryTerminator() throws {
        let maximumLines = 2
        let options = try validatedOptions(
            mode: .text,
            paneCount: .three,
            maximumInputBytes: 64,
            maximumInputLines: maximumLines
        )
        let cases = [
            (name: "LF", terminator: "\n"),
            (name: "CR", terminator: "\r"),
            (name: "CRLF", terminator: "\r\n")
        ]

        for value in cases {
            let exact = "a\(value.terminator)b\(value.terminator)"
            XCTAssertNoThrow(
                try Plan.make(
                    command: .threeWayText,
                    scratchpads: scratchpads(.text(exact), .text("base"), .text("right")),
                    modeOptions: options
                ),
                value.name
            )

            let over = "a\(value.terminator)b\(value.terminator)c\(value.terminator)"
            assertPlanError(
                .scratchpadLineLimitExceeded(pane: .left, maximumLines: maximumLines),
                value.name
            ) {
                try Plan.make(
                    command: .threeWayText,
                    scratchpads: scratchpads(.text(over), .text("base"), .text("right")),
                    modeOptions: options
                )
            }
        }
    }

    func testLabelBoundsAndMalformedLabelsAreRejectedPerPane() throws {
        let options = try validatedOptions(mode: .text, paneCount: .two)
        let exact = [
            Plan.Scratchpad(pane: .left, label: "é", content: .text("")),
            Plan.Scratchpad(pane: .right, label: "R", content: .text(""))
        ]
        XCTAssertNoThrow(
            try Plan.make(
                command: .twoWayText,
                scratchpads: exact,
                modeOptions: options,
                limits: limits(maximumLabelUTF8Bytes: 2)
            )
        )
        assertPlanError(.paneLabelTooLarge(pane: .left, maximumUTF8Bytes: 1)) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: exact,
                modeOptions: options,
                limits: limits(maximumLabelUTF8Bytes: 1)
            )
        }

        for malformed in ["", " \t\n", "Left\0Pane"] {
            assertPlanError(.invalidPaneLabel(.left), malformed.debugDescription) {
                try Plan.make(
                    command: .twoWayText,
                    scratchpads: [
                        Plan.Scratchpad(pane: .left, label: .init(malformed), content: .text("")),
                        Plan.Scratchpad(pane: .right, label: "R", content: .text(""))
                    ],
                    modeOptions: options
                )
            }
        }
    }

    func testMalformedScratchpadCollectionsReturnSpecificErrors() throws {
        let textOptions = try validatedOptions(mode: .text, paneCount: .two)
        assertPlanError(.invalidScratchpadCount(expected: 2, actual: 1)) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: [Plan.Scratchpad(pane: .left, content: .text(""))],
                modeOptions: textOptions
            )
        }
        assertPlanError(.invalidScratchpadCount(expected: 2, actual: 3)) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: scratchpads(.text("l"), .text("m"), .text("r")),
                modeOptions: textOptions
            )
        }
        assertPlanError(.unexpectedScratchpad(.middle)) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: [
                    Plan.Scratchpad(pane: .left, content: .text("")),
                    Plan.Scratchpad(pane: .middle, content: .text(""))
                ],
                modeOptions: textOptions
            )
        }
        assertPlanError(.duplicateScratchpad(.left)) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: [
                    Plan.Scratchpad(pane: .left, content: .text("")),
                    Plan.Scratchpad(pane: .left, content: .text(""))
                ],
                modeOptions: textOptions
            )
        }
        assertPlanError(
            .scratchpadKindMismatch(pane: .left, expected: .text, actual: .binary)
        ) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: [
                    Plan.Scratchpad(pane: .left, content: .binary(Data())),
                    Plan.Scratchpad(pane: .right, content: .text(""))
                ],
                modeOptions: textOptions
            )
        }

        let imageOptions = try validatedOptions(mode: .image, paneCount: .two)
        assertPlanError(.scratchpadsNotSupported(mode: .image)) {
            try Plan.make(
                command: .twoWayImage,
                scratchpads: [
                    Plan.Scratchpad(pane: .left, content: .text("")),
                    Plan.Scratchpad(pane: .right, content: .text(""))
                ],
                modeOptions: imageOptions
            )
        }
    }

    func testCancellationPrecedesInvalidLimitsAndWorkOverflow() throws {
        let options = try validatedOptions(mode: .text, paneCount: .two)
        let initialCancellation = CancellationProbe(cancelAtCall: 1)
        assertPlanError(.cancelled) {
            try Plan.make(
                command: .twoWayText,
                modeOptions: options,
                limits: limits(maximumPlanningWorkUnits: 0),
                cancellationCheck: initialCancellation.check
            )
        }
        XCTAssertEqual(initialCancellation.callCount, 1)

        let workLimits = limits(maximumPlanningWorkUnits: 1)
        assertPlanError(.planningWorkExceeded(maximumWorkUnits: 1)) {
            try Plan.make(
                command: .twoWayText,
                modeOptions: options,
                limits: workLimits,
                cancellationCheck: {}
            )
        }

        let overflowCancellation = CancellationProbe(cancelAtCall: 2)
        assertPlanError(.cancelled) {
            try Plan.make(
                command: .twoWayText,
                modeOptions: options,
                limits: workLimits,
                cancellationCheck: overflowCancellation.check
            )
        }
        XCTAssertEqual(overflowCancellation.callCount, 2)
    }

    func testCancellationIsCheckedAfterSuccessfulPlanningAndOtherErrorsPropagate() throws {
        let options = try validatedOptions(mode: .image, paneCount: .two)
        let finalCancellation = CancellationProbe(cancelAtCall: 2)
        assertPlanError(.cancelled) {
            try Plan.make(
                command: .twoWayImage,
                modeOptions: options,
                cancellationCheck: finalCancellation.check
            )
        }
        XCTAssertEqual(finalCancellation.callCount, 2)

        assertError(CancellationSentinel.failed) {
            try Plan.make(
                command: .twoWayImage,
                modeOptions: options,
                cancellationCheck: { throw CancellationSentinel.failed }
            )
        }
    }

    func testPeriodicCancellationStopsMidScanAfterMoreThanOneInterval() throws {
        let options = try validatedOptions(mode: .text, paneCount: .two)
        let cancellation = CancellationProbe(cancelAtCall: 3)
        assertPlanError(.cancelled) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: [
                    Plan.Scratchpad(
                        pane: .left,
                        label: "L",
                        content: .text(String(repeating: "x", count: 32))
                    ),
                    Plan.Scratchpad(pane: .right, label: "R", content: .text("right"))
                ],
                modeOptions: options,
                limits: limits(
                    maximumScratchpadBytes: 64,
                    maximumCombinedScratchpadBytes: 128,
                    maximumLabelUTF8Bytes: 1,
                    maximumPlanningWorkUnits: 256,
                    cancellationCheckInterval: 8
                ),
                cancellationCheck: cancellation.check
            )
        }
        XCTAssertEqual(cancellation.callCount, 3)
    }

    func testDefaultCancellationCheckRejectsPreCancelledTask() async throws {
        let options = try validatedOptions(mode: .text, paneCount: .two)
        let task = Task { () throws -> Plan in
            withUnsafeCurrentTask { $0?.cancel() }
            return try Plan.make(command: .twoWayText, modeOptions: options)
        }

        do {
            _ = try await task.value
            XCTFail("Pre-cancelled planning unexpectedly returned a plan")
        } catch {
            XCTAssertEqual(error as? PlanError, .cancelled)
        }
    }

    func testWorkPerformedIsDeterministicAndExactMaximumIsInclusive() throws {
        let options = try validatedOptions(mode: .text, paneCount: .two)
        let values = [
            Plan.Scratchpad(pane: .left, label: "Left", content: .text("alpha\n")),
            Plan.Scratchpad(pane: .right, label: "Right", content: .text("beta\r\n"))
        ]
        let generous = limits(
            maximumScratchpadBytes: 16,
            maximumCombinedScratchpadBytes: 32,
            maximumLabelUTF8Bytes: 8,
            maximumPlanningWorkUnits: 1_000,
            cancellationCheckInterval: 1
        )
        let baseline = try Plan.make(
            command: .twoWayText,
            scratchpads: values,
            modeOptions: options,
            limits: generous
        )
        XCTAssertGreaterThan(baseline.workPerformed, 1)

        let exactLimits = limits(
            maximumScratchpadBytes: 16,
            maximumCombinedScratchpadBytes: 32,
            maximumLabelUTF8Bytes: 8,
            maximumPlanningWorkUnits: baseline.workPerformed,
            cancellationCheckInterval: 1
        )
        let exact = try Plan.make(
            command: .twoWayText,
            scratchpads: values,
            modeOptions: options,
            limits: exactLimits
        )
        XCTAssertEqual(exact.workPerformed, baseline.workPerformed)

        assertPlanError(
            .planningWorkExceeded(maximumWorkUnits: baseline.workPerformed - 1)
        ) {
            try Plan.make(
                command: .twoWayText,
                scratchpads: values,
                modeOptions: options,
                limits: limits(
                    maximumScratchpadBytes: 16,
                    maximumCombinedScratchpadBytes: 32,
                    maximumLabelUTF8Bytes: 8,
                    maximumPlanningWorkUnits: baseline.workPerformed - 1,
                    cancellationCheckInterval: 1
                )
            )
        }
    }

    func testMakeModeOverloadAndPlanAliasForwardScratchpadsLimitsAndCancellationCheck() throws {
        let options = try validatedOptions(mode: .table, paneCount: .two)
        let scratchpadValues = [
            Plan.Scratchpad(pane: .right, label: "Right", content: .text("right,value")),
            Plan.Scratchpad(pane: .left, label: "Left", content: .text("left,value"))
        ]
        let customLimits = limits(
            maximumPaneCount: 2,
            maximumScratchpadBytes: 16,
            maximumCombinedScratchpadBytes: 32,
            maximumLabelUTF8Bytes: 8,
            maximumPlanningWorkUnits: 128,
            cancellationCheckInterval: 4
        )
        let commandCancellation = CancellationProbe(cancelAtCall: .max)
        let modeCancellation = CancellationProbe(cancelAtCall: .max)
        let aliasCancellation = CancellationProbe(cancelAtCall: .max)
        let byCommand = try Plan.make(
            command: .twoWayTable,
            scratchpads: scratchpadValues,
            modeOptions: options,
            limits: customLimits,
            cancellationCheck: commandCancellation.check
        )
        let byMode = try Plan.make(
            mode: .table,
            paneCount: .two,
            scratchpads: scratchpadValues,
            modeOptions: options,
            limits: customLimits,
            cancellationCheck: modeCancellation.check
        )
        let alias = try Plan.plan(
            command: .twoWayTable,
            scratchpads: scratchpadValues,
            modeOptions: options,
            limits: customLimits,
            cancellationCheck: aliasCancellation.check
        )

        XCTAssertEqual(byCommand, byMode)
        XCTAssertEqual(byCommand, alias)
        XCTAssertEqual(byMode.scratchpads, [scratchpadValues[1], scratchpadValues[0]])
        XCTAssertEqual(alias.scratchpads, [scratchpadValues[1], scratchpadValues[0]])
        XCTAssertEqual(byMode.limits, customLimits)
        XCTAssertEqual(alias.limits, customLimits)
        XCTAssertGreaterThan(commandCancellation.callCount, 0)
        XCTAssertEqual(modeCancellation.callCount, commandCancellation.callCount)
        XCTAssertEqual(aliasCancellation.callCount, commandCancellation.callCount)
    }

    func testPublicValuesAreSendableAndDeclaredHashableValuesHashConsistently() throws {
        let options = try validatedOptions(mode: .text, paneCount: .two)
        let plan = try Plan.make(command: .twoWayText, modeOptions: options)

        requireSendable(plan)
        requireSendable(options)
        requireSendable(Plan.PaneLabel("Label"))
        requireSendable(Plan.Scratchpad(pane: .left, content: .text("")))
        requireSendable(plan.panes[0])
        requireSendable(PlanError.cancelled)
        let cancellationCheck: Plan.CancellationCheck = {}
        requireSendable(cancellationCheck)

        requireHashable(Plan.Mode.text)
        requireHashable(Plan.PaneCount.two)
        requireHashable(Plan.Pane.left)
        requireHashable(Plan.Command.twoWayText)
        requireHashable(Plan.ScratchpadKind.text)
        requireHashable(Plan.RequiredSourceKind.emptyFolder)
        requireHashable(Plan.SourceSemantics.scratchpad(.text))
        requireHashable(Plan.DocumentCreationSupport.planningOnly)
        requireHashable(Plan.Capability(mode: .text))
        requireHashable(Plan.ScratchpadContent.text("value"))
        requireHashable(Plan.PaneSource.scratchpad(.text("value")))
        requireHashable(Plan.Limit.planningWorkUnits)
        requireHashable(Plan.Limits.default)
    }

    private func makePlan(mode: Plan.Mode, paneCount: Plan.PaneCount) throws -> Plan {
        try Plan.make(
            mode: mode,
            paneCount: paneCount,
            modeOptions: validatedOptions(mode: mode, paneCount: paneCount)
        )
    }

    private func validatedOptions(
        mode: Plan.Mode,
        paneCount: Plan.PaneCount,
        maximumInputBytes: Int? = nil,
        maximumInputLines: Int? = nil
    ) throws -> Plan.ValidatedModeOptions {
        let fixture = try openFixture(
            mode: mode,
            paneCount: paneCount,
            maximumInputBytes: maximumInputBytes,
            maximumInputLines: maximumInputLines
        )
        return try XCTUnwrap(
            Plan.ValidatedModeOptions(fixture.plan, currentRequest: fixture.request)
        )
    }

    private func openFixture(
        mode: Plan.Mode,
        paneCount: Plan.PaneCount,
        maximumInputBytes: Int? = nil,
        maximumInputLines: Int? = nil
    ) throws -> (request: ComparisonOpenRequest, plan: ComparisonOpenPlan) {
        let options = comparisonModeOptions(
            mode: mode,
            maximumInputBytes: maximumInputBytes,
            maximumInputLines: maximumInputLines
        )
        let identityByte = UInt8(1 + modeIndex(mode) * 2 + (paneCount == .three ? 1 : 0))
        let request = comparisonOpenRequest(
            mode: mode,
            paneCount: paneCount,
            modeOptions: options,
            identityByte: identityByte
        )
        return (request, try ComparisonOpenRequestPlanner.plan(request))
    }

    private func comparisonOpenRequest(
        mode: Plan.Mode,
        paneCount: Plan.PaneCount,
        modeOptions: ComparisonOpenModeOptions,
        identityByte: UInt8
    ) -> ComparisonOpenRequest {
        let identity = ComparisonOpenRequestIdentity(
            rawValue: UUID(
                uuid: (identityByte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            )
        )
        let projectMode = mode.comparisonProjectMode
        if mode == .folder {
            let left = ComparisonOpenSource.localFolder(
                URL(filePath: "/new-plan/left", directoryHint: .isDirectory)
            )
            let middle = ComparisonOpenSource.localFolder(
                URL(filePath: "/new-plan/middle", directoryHint: .isDirectory)
            )
            let right = ComparisonOpenSource.localFolder(
                URL(filePath: "/new-plan/right", directoryHint: .isDirectory)
            )
            if paneCount == .three {
                return ComparisonOpenRequest(
                    identity: identity,
                    left: left,
                    middle: middle,
                    right: right,
                    modeSelection: .explicit(projectMode),
                    modeOptions: modeOptions
                )
            }
            return ComparisonOpenRequest(
                identity: identity,
                left: left,
                right: right,
                modeSelection: .explicit(projectMode),
                modeOptions: modeOptions
            )
        }

        let fileExtension: String
        switch mode {
        case .text: fileExtension = "txt"
        case .table: fileExtension = "csv"
        case .binary: fileExtension = "bin"
        case .image: fileExtension = "png"
        case .webpage: fileExtension = "html"
        case .folder: preconditionFailure("Folder handled above")
        }
        let left = ComparisonOpenSource.localFile(URL(filePath: "/new-plan/left.\(fileExtension)"))
        let middle = ComparisonOpenSource.localFile(URL(filePath: "/new-plan/middle.\(fileExtension)"))
        let right = ComparisonOpenSource.localFile(URL(filePath: "/new-plan/right.\(fileExtension)"))
        if paneCount == .three {
            return ComparisonOpenRequest(
                identity: identity,
                left: left,
                middle: middle,
                right: right,
                modeSelection: .explicit(projectMode),
                modeOptions: modeOptions
            )
        }
        return ComparisonOpenRequest(
            identity: identity,
            left: left,
            right: right,
            modeSelection: .explicit(projectMode),
            modeOptions: modeOptions
        )
    }

    private func comparisonModeOptions(
        mode: Plan.Mode,
        maximumInputBytes: Int?,
        maximumInputLines: Int?
    ) -> ComparisonOpenModeOptions {
        switch mode {
        case .text:
            return .text(
                twoWay: LineDiffOptions(ignoreCase: true),
                threeWay: ThreeWayTextMergeOptions(
                    maximumInputBytes: maximumInputBytes ?? 64 * 1024 * 1024,
                    maximumInputLines: maximumInputLines ?? 1024 * 1024
                )
            )
        case .table:
            let parsing = DelimitedTableParsingOptions(
                limits: DelimitedTableLimits(
                    maximumInputBytes: maximumInputBytes ?? 64 * 1024 * 1024
                )
            )
            return .table(
                parsing: parsing,
                twoWay: .default,
                threeWay: ThreeWayTableComparisonOptions(parsingOptions: parsing)
            )
        case .binary:
            return .binary(
                twoWay: BinaryComparisonOptions(maximumExactEditDistance: 1),
                threeWay: ThreeWayBinaryComparisonOptions(
                    maximumInputBytes: maximumInputBytes ?? 64 * 1024 * 1024
                )
            )
        case .image:
            return .image(loading: .default, comparison: ImageComparisonOptions(channelTolerance: 1))
        case .webpage:
            return .webpage(twoWay: .default, threeWay: .default)
        case .folder:
            return .folder(
                scanning: FolderScanOptions(),
                twoWay: FolderComparisonOptions(),
                threeWay: .default
            )
        }
    }

    private func expectedSources(
        mode: Plan.Mode,
        paneCount: Plan.PaneCount
    ) -> [Plan.PaneSource] {
        let source: Plan.PaneSource
        switch mode {
        case .text, .table: source = .scratchpad(.text(""))
        case .binary: source = .scratchpad(.binary(Data()))
        case .image: source = .emptyImage
        case .webpage: source = .blankWebpage
        case .folder: source = .requiredSource(.emptyFolder)
        }
        return Array(repeating: source, count: paneCount.rawValue)
    }

    private func scratchpads(
        _ left: Plan.ScratchpadContent,
        _ middle: Plan.ScratchpadContent,
        _ right: Plan.ScratchpadContent
    ) -> [Plan.Scratchpad] {
        [
            Plan.Scratchpad(pane: .left, content: left),
            Plan.Scratchpad(pane: .middle, content: middle),
            Plan.Scratchpad(pane: .right, content: right)
        ]
    }

    private func modeIndex(_ mode: Plan.Mode) -> Int {
        switch mode {
        case .text: 0
        case .table: 1
        case .binary: 2
        case .image: 3
        case .webpage: 4
        case .folder: 5
        }
    }

    private func limits(
        maximumPaneCount: Int = Plan.Limits.default.maximumPaneCount,
        maximumScratchpadBytes: Int = Plan.Limits.default.maximumScratchpadBytes,
        maximumCombinedScratchpadBytes: Int = Plan.Limits.default.maximumCombinedScratchpadBytes,
        maximumLabelUTF8Bytes: Int = Plan.Limits.default.maximumLabelUTF8Bytes,
        maximumPlanningWorkUnits: Int = Plan.Limits.default.maximumPlanningWorkUnits,
        cancellationCheckInterval: Int = Plan.Limits.default.cancellationCheckInterval
    ) -> Plan.Limits {
        Plan.Limits(
            maximumPaneCount: maximumPaneCount,
            maximumScratchpadBytes: maximumScratchpadBytes,
            maximumCombinedScratchpadBytes: maximumCombinedScratchpadBytes,
            maximumLabelUTF8Bytes: maximumLabelUTF8Bytes,
            maximumPlanningWorkUnits: maximumPlanningWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func assertPlanError<T>(
        _ expected: PlanError,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        assertError(expected, message, file: file, line: line, operation: operation)
    }

    private func assertError<E: Error & Equatable, T>(
        _ expected: E,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), message, file: file, line: line) { error in
            XCTAssertEqual(error as? E, expected, message, file: file, line: line)
        }
    }

    private func requireSendable<T: Sendable>(_: T) {}

    private func requireHashable<T: Hashable & Sendable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set([value, value]).count, 1, file: file, line: line)
    }
}

private enum CancellationSentinel: Error, Equatable {
    case failed
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAtCall: Int
    private var calls = 0

    init(cancelAtCall: Int) {
        self.cancelAtCall = cancelAtCall
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func check() throws {
        let shouldCancel = lock.withLock {
            calls += 1
            return calls >= cancelAtCall
        }
        if shouldCancel { throw CancellationError() }
    }
}
