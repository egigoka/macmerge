import MacMergeCore
import XCTest

final class ToolbarTooltipShortcutAuditTests: XCTestCase {
    private typealias Audit = ToolbarTooltipShortcutAudit
    private typealias Command = ToolbarConfiguration.Command
    private typealias Item = ToolbarConfiguration.Item
    private typealias Shortcut = ToolbarAuditShortcut
    private typealias Modifier = AccessibilityKeyboardModifier

    private struct TestCancellation: Error {}

    private func canonicalObservations() -> [Audit.Observation] {
        Audit.canonicalObservations()
    }

    private func observation(
        for command: Command,
        tooltip: String?? = nil,
        shortcut: Shortcut?? = nil
    ) -> Audit.Observation {
        let entry = Audit.entry(for: command)
        return Audit.Observation(
            command: command,
            tooltip: tooltip ?? entry.tooltip,
            shortcut: shortcut ?? entry.shortcut
        )
    }

    private func cleanReport() throws -> Audit.Report {
        try Audit.audit(observations: canonicalObservations(), cancellationCheck: {})
    }

    // MARK: - Inventory exactness

    func testScopeStatementIsStaticAndNonEmpty() {
        XCTAssertFalse(Audit.scopeStatement.isEmpty)
        XCTAssertTrue(Audit.scopeStatement.contains("Static checks"))
    }

    func testCanonicalRevisionMatchesManifest() {
        XCTAssertEqual(Audit.canonicalRevision, ToolbarAuditManifest.canonicalRevision)
        XCTAssertEqual(Audit.canonicalRevision.rawValue, 1)
    }

    func testCanonicalEntriesCountIs26AndMatchesAllCases() {
        XCTAssertEqual(Audit.canonicalEntries.count, 26)
        XCTAssertEqual(Audit.canonicalEntries.count, Command.allCases.count)
        XCTAssertEqual(Set(Audit.canonicalEntries.map(\.command)).count, 26)
    }

    func testOrderedCommandsMatchesAllCasesOrder() {
        XCTAssertEqual(Audit.orderedCommands, Command.allCases)
        XCTAssertEqual(Audit.canonicalEntries.map(\.command), Command.allCases)
        XCTAssertEqual(Audit.winMergeItems.compactMap(\.command), Command.allCases)
    }

    func testCanonicalEntriesExactIDsAndTooltips() {
        let expected: [(Command, String, String)] = [
            (.newComparison, "ID_FILE_NEW", "New Documents (Ctrl+N)"),
            (.openComparison, "ID_FILE_OPEN", "Open (Ctrl+O)"),
            (.save, "ID_FILE_SAVE", "Save (Ctrl+S)"),
            (.undo, "ID_EDIT_UNDO", "Undo (Ctrl+Z)"),
            (.redo, "ID_EDIT_REDO", "Redo (Ctrl+Y)"),
            (.selectLineDifference, "ID_SELECTLINEDIFF", "Difference in Current Line (F4)"),
            (.nextDifference, "ID_NEXTDIFF", "Next Difference (Alt+Down)"),
            (.previousDifference, "ID_PREVDIFF", "Previous Difference (Alt+Up)"),
            (.nextConflict, "ID_NEXTCONFLICT", "Next Conflict (Alt+Shift+Down)"),
            (.previousConflict, "ID_PREVCONFLICT", "Previous Conflict (Alt+Shift+Up)"),
            (.firstDifference, "ID_FIRSTDIFF", "First Difference (Alt+Home)"),
            (.currentDifference, "ID_CURDIFF", "Current Difference (Alt+Enter)"),
            (.lastDifference, "ID_LASTDIFF", "Last Difference (Alt+End)"),
            (.copyToRight, "ID_L2R", "Copy to Right (Alt+Right)"),
            (.copyToLeft, "ID_R2L", "Copy to Left (Alt+Left)"),
            (.copyToRightAndAdvance, "ID_L2RNEXT", "Copy to Right and Advance (Ctrl+Alt+Right)"),
            (.copyToLeftAndAdvance, "ID_R2LNEXT", "Copy to Left and Advance (Ctrl+Alt+Left)"),
            (.copyAllToRight, "ID_ALL_RIGHT", "Copy All to Right"),
            (.copyAllToLeft, "ID_ALL_LEFT", "Copy All to Left"),
            (.autoMerge, "ID_AUTO_MERGE", "Auto Merge (Ctrl+Alt+M)"),
            (.firstComparedFile, "ID_FIRSTFILE", "First File"),
            (.previousComparedFile, "ID_PREVFILE", "Previous File (Ctrl+F7)"),
            (.nextComparedFile, "ID_NEXTFILE", "Next File (Ctrl+F8)"),
            (.lastComparedFile, "ID_LASTFILE", "Last File"),
            (.options, "ID_OPTIONS", "Options"),
            (.refresh, "ID_REFRESH", "Refresh (F5)")
        ]
        XCTAssertEqual(Audit.canonicalEntries.count, expected.count)
        for (entry, spec) in zip(Audit.canonicalEntries, expected) {
            XCTAssertEqual(entry.command, spec.0, spec.1)
            XCTAssertEqual(entry.winMergeID, spec.1, spec.0.rawValue)
            XCTAssertEqual(entry.tooltip, spec.2, spec.0.rawValue)
        }
    }

    func testNilShortcutCommandsAreExact() {
        let expected: Set<Command> = [
            .copyAllToRight, .copyAllToLeft,
            .firstComparedFile, .lastComparedFile, .options
        ]
        XCTAssertEqual(Set(Audit.canonicalEntries.filter { $0.shortcut == nil }.map(\.command)), expected)
        for command in expected {
            XCTAssertNil(Audit.shortcut(for: command), command.rawValue)
            XCTAssertNil(Audit.shortcutDisplay(for: command), command.rawValue)
            XCTAssertNil(Audit.entry(for: command).shortcutDisplay, command.rawValue)
        }
    }

    func testShortcutBindingsExact() {
        let expected: [(Command, String, Set<Modifier>, String)] = [
            (.newComparison, "n", [.control], "Ctrl+N"),
            (.openComparison, "o", [.control], "Ctrl+O"),
            (.save, "s", [.control], "Ctrl+S"),
            (.undo, "z", [.control], "Ctrl+Z"),
            (.redo, "y", [.control], "Ctrl+Y"),
            (.selectLineDifference, "F4", [], "F4"),
            (.nextDifference, "Down", [.option], "Alt+Down"),
            (.previousDifference, "Up", [.option], "Alt+Up"),
            (.nextConflict, "Down", [.option, .shift], "Alt+Shift+Down"),
            (.previousConflict, "Up", [.option, .shift], "Alt+Shift+Up"),
            (.firstDifference, "Home", [.option], "Alt+Home"),
            (.currentDifference, "Enter", [.option], "Alt+Enter"),
            (.lastDifference, "End", [.option], "Alt+End"),
            (.copyToRight, "Right", [.option], "Alt+Right"),
            (.copyToLeft, "Left", [.option], "Alt+Left"),
            (.copyToRightAndAdvance, "Right", [.control, .option], "Ctrl+Alt+Right"),
            (.copyToLeftAndAdvance, "Left", [.control, .option], "Ctrl+Alt+Left"),
            (.autoMerge, "m", [.control, .option], "Ctrl+Alt+M"),
            (.previousComparedFile, "F7", [.control], "Ctrl+F7"),
            (.nextComparedFile, "F8", [.control], "Ctrl+F8"),
            (.refresh, "F5", [], "F5")
        ]
        XCTAssertEqual(Audit.canonicalEntries.compactMap(\.shortcut).count, expected.count)
        for (command, key, modifiers, display) in expected {
            let actual = Audit.entry(for: command).shortcut
            XCTAssertEqual(actual?.key, key, command.rawValue)
            XCTAssertEqual(actual?.modifiers, modifiers, command.rawValue)
            XCTAssertEqual(actual?.display, display, command.rawValue)
            XCTAssertEqual(Audit.shortcutDisplay(for: command), display, command.rawValue)
        }
    }

    func testShortcutDisplayMatchesTooltipSuffix() {
        for entry in Audit.canonicalEntries {
            if let display = entry.shortcutDisplay {
                XCTAssertTrue(entry.tooltip.hasSuffix("(\(display))"), entry.command.rawValue)
            } else {
                XCTAssertFalse(entry.tooltip.contains("("), entry.command.rawValue)
            }
        }
    }

    func testWinMergeGroupsAreExact() {
        let expected: [[Command]] = [
            [.newComparison, .openComparison, .save],
            [.undo, .redo],
            [.selectLineDifference],
            [.nextDifference, .previousDifference],
            [.nextConflict, .previousConflict],
            [.firstDifference, .currentDifference, .lastDifference],
            [.copyToRight, .copyToLeft],
            [.copyToRightAndAdvance, .copyToLeftAndAdvance],
            [.copyAllToRight, .copyAllToLeft],
            [.autoMerge],
            [.firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile],
            [.options],
            [.refresh]
        ]
        XCTAssertEqual(Audit.winMergeGroups, expected)
        XCTAssertEqual(Audit.winMergeGroups.count, 13)
        XCTAssertEqual(Audit.winMergeGroups.flatMap { $0 }, Command.allCases)
    }

    func testEntryAccessors() {
        XCTAssertEqual(Audit.tooltip(for: .save), "Save (Ctrl+S)")
        XCTAssertEqual(Audit.winMergeID(for: .save), "ID_FILE_SAVE")
        XCTAssertEqual(Audit.shortcut(for: .save)?.display, "Ctrl+S")
        XCTAssertEqual(Audit.shortcutDisplay(for: .refresh), "F5")
        XCTAssertEqual(Audit.entry(for: .options).tooltip, "Options")
        XCTAssertEqual(Audit.orderedCommands.count, 26)
    }

    // MARK: - Order / group / mismatch audit

    func testCanonicalObservationsPassClean() throws {
        let report = try cleanReport()
        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.mismatchCount, 0)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.checkedCommands, 26)
        XCTAssertTrue(report.receipt.passed)
        XCTAssertEqual(report.receipt.findingCount, 0)
        XCTAssertEqual(report.receipt.checkedCommands, 26)
    }

    func testMissingEntryFinding() throws {
        var observations = canonicalObservations()
        observations.removeAll { $0.command == .save }
        let report = try Audit.audit(observations: observations, cancellationCheck: {})
        XCTAssertFalse(report.passed)
        let codes = report.findings.filter { $0.command == .save }.map(\.code)
        XCTAssertTrue(codes.contains(.missingEntry))
    }

    func testTooltipMissingFinding() throws {
        var observations = canonicalObservations()
        let index = try XCTUnwrap(observations.firstIndex { $0.command == .save })
        observations[index] = Audit.Observation(command: .save, tooltip: nil, shortcut: Audit.shortcut(for: .save))
        let report = try Audit.audit(observations: observations, cancellationCheck: {})
        XCTAssertTrue(report.findings.contains { $0.code == .tooltipMissing && $0.command == .save })
    }

    func testTooltipMismatchFinding() throws {
        var observations = canonicalObservations()
        let index = try XCTUnwrap(observations.firstIndex { $0.command == .save })
        observations[index] = Audit.Observation(command: .save, tooltip: "Save", shortcut: Audit.shortcut(for: .save))
        let report = try Audit.audit(observations: observations, cancellationCheck: {})
        XCTAssertTrue(report.findings.contains { $0.code == .tooltipMismatch && $0.command == .save })
        let mismatch = try XCTUnwrap(report.findings.first { $0.code == .tooltipMismatch })
        XCTAssertEqual(mismatch.message, "Toolbar tooltip differs from exact WinMerge-equivalent text.")
    }

    func testShortcutMissingFinding() throws {
        var observations = canonicalObservations()
        let index = try XCTUnwrap(observations.firstIndex { $0.command == .save })
        observations[index] = Audit.Observation(command: .save, tooltip: Audit.tooltip(for: .save), shortcut: nil)
        let report = try Audit.audit(observations: observations, cancellationCheck: {})
        XCTAssertTrue(report.findings.contains { $0.code == .shortcutMissing && $0.command == .save })
    }

    func testShortcutMismatchFinding() throws {
        var observations = canonicalObservations()
        let wrong = Shortcut(key: "s", modifiers: [.control, .shift], display: "Ctrl+Shift+S")
        let saveIndex = try XCTUnwrap(observations.firstIndex { $0.command == .save })
        observations[saveIndex] = Audit.Observation(command: .save, tooltip: Audit.tooltip(for: .save), shortcut: wrong)
        let optionsIndex = try XCTUnwrap(observations.firstIndex { $0.command == .options })
        observations[optionsIndex] = Audit.Observation(
            command: .options,
            tooltip: Audit.tooltip(for: .options),
            shortcut: Shortcut(key: "F5", display: "F5")
        )
        let report = try Audit.audit(observations: observations, cancellationCheck: {})
        XCTAssertTrue(report.findings.contains { $0.code == .shortcutMismatch && $0.command == .save })
        XCTAssertTrue(report.findings.contains { $0.code == .shortcutMismatch && $0.command == .options })
    }

    func testDuplicateEntryFinding() throws {
        var observations = canonicalObservations()
        let index = try XCTUnwrap(observations.firstIndex { $0.command == .refresh })
        observations[index] = observation(for: .save)
        let report = try Audit.audit(observations: observations, cancellationCheck: {})
        XCTAssertTrue(report.findings.contains { $0.code == .duplicateEntry && $0.command == .save })
        XCTAssertTrue(report.findings.contains { $0.code == .missingEntry && $0.command == .refresh })
    }

    func testDuplicateShortcutFinding() throws {
        var observations = canonicalObservations()
        let shared = Shortcut(key: "x", modifiers: [.control], display: "Ctrl+X")
        for command in [Command.copyAllToRight, Command.copyAllToLeft] {
            let index = try XCTUnwrap(observations.firstIndex { $0.command == command })
            observations[index] = Audit.Observation(
                command: command,
                tooltip: Audit.tooltip(for: command),
                shortcut: shared
            )
        }
        let report = try Audit.audit(observations: observations, cancellationCheck: {})
        let duplicates = report.findings.filter { $0.code == .duplicateShortcut }
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertEqual(Set(duplicates.compactMap(\.command)), [.copyAllToRight, .copyAllToLeft])
    }

    func testOrderMismatchFromObservations() throws {
        let observations = Array(canonicalObservations().reversed())
        let report = try Audit.audit(observations: observations, cancellationCheck: {})
        XCTAssertTrue(report.findings.contains { $0.code == .orderMismatch })
    }

    func testItemsOrderMismatchFinding() throws {
        var items = Audit.winMergeItems
        items.swapAt(0, 1)
        let report = try Audit.audit(observations: canonicalObservations(), items: items, cancellationCheck: {})
        XCTAssertTrue(report.findings.contains { $0.code == .orderMismatch })
    }

    func testGroupingMismatchFinding() throws {
        var items = Audit.winMergeItems
        items.remove(at: 3)
        items.insert(.separator, at: 0)
        XCTAssertEqual(items.compactMap(\.command), Audit.winMergeItems.compactMap(\.command))
        let report = try Audit.audit(observations: canonicalObservations(), items: items, cancellationCheck: {})
        XCTAssertFalse(report.findings.contains { $0.code == .orderMismatch })
        XCTAssertTrue(report.findings.contains { $0.code == .groupingMismatch })
    }

    func testAuditControlsPassThroughMatchesAudit() throws {
        let controls = Audit.canonicalEntries.map { entry in
            ToolbarAuditControlObservation(
                id: ToolbarAuditStableID(rawValue: "control-\(entry.command.rawValue)"),
                command: entry.command,
                behavior: ToolbarAuditControlBehavior(
                    primaryActionID: ToolbarAuditStableID(rawValue: "action-\(entry.command.rawValue)")
                ),
                tooltip: entry.tooltip,
                shortcut: entry.shortcut,
                accessibility: ToolbarAuditAXMetadata(
                    identifier: ToolbarAuditStableID(rawValue: "ax-\(entry.command.rawValue)"),
                    label: entry.tooltip,
                    hint: "hint"
                ),
                availability: .enabled
            )
        }
        let viaControls = try Audit.auditControls(controls, cancellationCheck: {})
        let direct = try Audit.audit(observations: canonicalObservations(), cancellationCheck: {})
        XCTAssertTrue(viaControls.passed)
        XCTAssertEqual(viaControls.findings, direct.findings)
        XCTAssertEqual(viaControls.checkedCommands, direct.checkedCommands)
    }

    // MARK: - Receipt determinism

    func testReceiptDeterminism() throws {
        let first = try Audit.audit(observations: canonicalObservations(), cancellationCheck: {})
        let second = try Audit.audit(observations: canonicalObservations(), cancellationCheck: {})
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.findings, second.findings)
        XCTAssertEqual(first.workPerformed, second.workPerformed)
        XCTAssertEqual(first.checkedCommands, second.checkedCommands)
        XCTAssertEqual(first.revision, second.revision)
    }

    func testReportPassedFlagsMatchFindings() throws {
        let clean = try cleanReport()
        XCTAssertTrue(clean.passed)
        XCTAssertTrue(clean.receipt.passed)
        XCTAssertEqual(clean.mismatchCount, clean.findings.count)

        var observations = canonicalObservations()
        let index = try XCTUnwrap(observations.firstIndex { $0.command == .refresh })
        observations[index] = Audit.Observation(command: .refresh, tooltip: "Wrong", shortcut: nil)
        let dirty = try Audit.audit(observations: observations, cancellationCheck: {})
        XCTAssertFalse(dirty.passed)
        XCTAssertFalse(dirty.receipt.passed)
        XCTAssertEqual(dirty.mismatchCount, dirty.findings.count)
        XCTAssertEqual(dirty.receipt.findingCount, dirty.findings.count)
    }

    // MARK: - Boundary limits

    func testLimitsDefaultsAndHardMaxima() throws {
        try Audit.Limits.default.validate()
        XCTAssertEqual(Audit.Limits.hardMaximumEntries, Command.allCases.count)
        XCTAssertEqual(Audit.Limits.hardMaximumItems, ToolbarConfiguration.maximumItemCount)
        XCTAssertEqual(Audit.Limits.hardMaximumStringUTF8Bytes, 4 * 1_024)
        XCTAssertEqual(Audit.Limits.hardMaximumTotalStringUTF8Bytes, 256 * 1_024)
        XCTAssertEqual(Audit.Limits.hardMaximumWorkUnits, 1_024 * 1_024)
        XCTAssertEqual(Audit.Limits.hardMaximumFindings, 4_096)
        XCTAssertEqual(Audit.Limits.hardMaximumCancellationCheckInterval, 4_096)
        XCTAssertEqual(Audit.Limit.allCases.count, 7)
    }

    func testLimitsValidateRejectsInvalid() {
        XCTAssertThrowsError(
            try Audit.Limits(maximumEntries: Command.allCases.count + 1).validate()
        )
        XCTAssertThrowsError(
            try Audit.Limits(maximumStringUTF8Bytes: 0).validate()
        )
        XCTAssertThrowsError(
            try Audit.Limits(maximumTotalStringUTF8Bytes: 0).validate()
        )
        XCTAssertThrowsError(
            try Audit.Limits(maximumWorkUnits: 0).validate()
        )
        XCTAssertThrowsError(
            try Audit.Limits(cancellationCheckInterval: 0).validate()
        )
    }

    func testCountLimitsExceeded() {
        XCTAssertThrowsError(
            try Audit.audit(
                observations: canonicalObservations(),
                limits: Audit.Limits(maximumEntries: 1),
                cancellationCheck: {}
            )
        ) { error in
            XCTAssertEqual(error as? Audit.AuditError, .countLimitExceeded(kind: "observation", maximum: 1))
        }
        XCTAssertThrowsError(
            try Audit.audit(
                observations: canonicalObservations(),
                items: Audit.winMergeItems,
                limits: Audit.Limits(maximumItems: 0),
                cancellationCheck: {}
            )
        ) { error in
            XCTAssertEqual(error as? Audit.AuditError, .countLimitExceeded(kind: "item", maximum: 0))
        }
    }

    func testStringBudgetsEnforced() {
        XCTAssertThrowsError(
            try Audit.audit(
                observations: canonicalObservations(),
                limits: Audit.Limits(maximumStringUTF8Bytes: 1),
                cancellationCheck: {}
            )
        ) { error in
            guard case .stringTooLarge = error as? Audit.AuditError else {
                return XCTFail("Expected stringTooLarge, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try Audit.audit(
                observations: canonicalObservations(),
                limits: Audit.Limits(maximumTotalStringUTF8Bytes: 1),
                cancellationCheck: {}
            )
        ) { error in
            guard case .totalStringsTooLarge = error as? Audit.AuditError else {
                return XCTFail("Expected totalStringsTooLarge, got \(error)")
            }
        }
    }

    func testWorkFindingAndCancellationLimits() {
        XCTAssertThrowsError(
            try Audit.audit(
                observations: canonicalObservations(),
                limits: Audit.Limits(maximumWorkUnits: 1),
                cancellationCheck: {}
            )
        ) { error in
            guard case .workLimitExceeded = error as? Audit.AuditError else {
                return XCTFail("Expected workLimitExceeded, got \(error)")
            }
        }
        var observations = canonicalObservations()
        observations.removeAll { $0.command == .save }
        XCTAssertThrowsError(
            try Audit.audit(
                observations: observations,
                limits: Audit.Limits(maximumFindings: 0),
                cancellationCheck: {}
            )
        ) { error in
            XCTAssertEqual(error as? Audit.AuditError, .findingLimitExceeded(maximum: 0))
        }
        XCTAssertThrowsError(
            try Audit.audit(
                observations: canonicalObservations(),
                cancellationCheck: { throw TestCancellation() }
            )
        ) { error in
            XCTAssertEqual(error as? Audit.AuditError, .cancelled)
        }
    }

    // MARK: - Redacted output

    func testRedactedOutput() throws {
        let secret = Audit.tooltip(for: .newComparison)
        let observation = Audit.Observation(
            command: .newComparison,
            tooltip: secret,
            shortcut: Audit.shortcut(for: .newComparison)
        )
        XCTAssertTrue(observation.description.contains("<redacted>"))
        XCTAssertFalse(observation.description.contains(secret))
        XCTAssertTrue(observation.debugDescription.contains("<redacted>"))
        XCTAssertTrue(
            observation.customMirror.children.contains { _, value in
                (value as? String) == "<redacted>"
            })

        let report = try cleanReport()
        XCTAssertTrue(report.description.contains("<redacted>"))
        XCTAssertFalse(report.description.contains(secret))
        XCTAssertTrue(report.debugDescription.contains("<redacted>"))
        XCTAssertTrue(
            report.customMirror.children.contains { _, value in
                (value as? String) == "<redacted>"
            })
        XCTAssertTrue(report.receipt.description.contains("<redacted>"))
        XCTAssertTrue(report.receipt.debugDescription.contains("<redacted>"))
        XCTAssertTrue(
            report.receipt.customMirror.children.contains { _, value in
                (value as? String) == "<redacted>"
            })
        for finding in report.findings {
            XCTAssertFalse(finding.message.contains(secret))
        }
    }
}
