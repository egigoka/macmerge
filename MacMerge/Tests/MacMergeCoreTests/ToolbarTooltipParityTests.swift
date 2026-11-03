import MacMergeCore
import XCTest

final class ToolbarTooltipParityTests: XCTestCase {
    private typealias Parity = ToolbarTooltipParity
    private typealias Command = ToolbarConfiguration.Command

    func testEntriesCountIs26AndMatchesAllCases() {
        XCTAssertEqual(Parity.entries.count, 26)
        XCTAssertEqual(Parity.entries.count, Command.allCases.count)
        XCTAssertEqual(Set(Parity.entries.map(\.command)).count, 26)
    }

    func testOrderedCommandsMatchesAllCases() {
        XCTAssertEqual(Parity.orderedCommands, Command.allCases)
        XCTAssertEqual(Parity.entries.map(\.command), Command.allCases)
    }

    func testValidatePassesOnCanonicalEntries() throws {
        XCTAssertNoThrow(try Parity.validate())
        XCTAssertNoThrow(try Parity.validate(Parity.entries))
    }

    func testGapsEmptyOnCanonicalEntries() {
        XCTAssertTrue(Parity.gaps().isEmpty)
        XCTAssertEqual(Parity.gaps(), [])
    }

    func testGapsDetectsMissingCommand() {
        var candidates = Parity.entries
        candidates.removeAll { $0.command == .save }
        XCTAssertEqual(Parity.gaps(in: candidates), [.save])
    }

    func testNilShortcutSetIsExact() {
        let expected: Set<Command> = [
            .copyAllToRight, .copyAllToLeft,
            .firstComparedFile, .lastComparedFile, .options
        ]
        XCTAssertEqual(Set(Parity.entries.filter { $0.shortcutDisplay == nil }.map(\.command)), expected)
        for command in Command.allCases {
            if expected.contains(command) {
                XCTAssertNil(Parity.shortcutDisplay(for: command), command.rawValue)
            } else {
                XCTAssertNotNil(Parity.shortcutDisplay(for: command), command.rawValue)
            }
        }
    }

    func testParityMatchesAuditCanonicalEntries() {
        XCTAssertEqual(
            Parity.entries.map(\.command),
            ToolbarTooltipShortcutAudit.canonicalEntries.map(\.command)
        )
        for entry in Parity.entries {
            let audit = ToolbarTooltipShortcutAudit.entry(for: entry.command)
            XCTAssertEqual(entry.winMergeID, audit.winMergeID, entry.command.rawValue)
            XCTAssertEqual(entry.tooltip, audit.tooltip, entry.command.rawValue)
            XCTAssertEqual(entry.shortcutDisplay, audit.shortcutDisplay, entry.command.rawValue)
        }
    }

    func testAccessorsRoundTrip() {
        XCTAssertEqual(Parity.winMergeID(for: .save), "ID_FILE_SAVE")
        XCTAssertEqual(Parity.tooltip(for: .save), "Save (Ctrl+S)")
        XCTAssertEqual(Parity.shortcutDisplay(for: .save), "Ctrl+S")
        XCTAssertNil(Parity.shortcutDisplay(for: .options))
        XCTAssertEqual(Parity.entry(for: .refresh)?.tooltip, "Refresh (F5)")
    }

    func testValidateRejectsDuplicateCommand() {
        var candidates = Parity.entries
        candidates.append(Parity.entries[0])
        XCTAssertThrowsError(try Parity.validate(candidates)) { error in
            XCTAssertEqual(
                error as? Parity.ValidationError,
                .duplicateCommand(Parity.entries[0].command)
            )
        }
    }

    func testValidateRejectsDuplicateWinMergeID() {
        var candidates = Parity.entries
        let first = candidates[0]
        let second = candidates[1]
        candidates[1] = Parity.Entry(
            command: second.command,
            winMergeID: first.winMergeID,
            tooltip: second.tooltip,
            shortcutDisplay: second.shortcutDisplay
        )
        XCTAssertThrowsError(try Parity.validate(candidates)) { error in
            XCTAssertEqual(error as? Parity.ValidationError, .duplicateWinMergeID(first.winMergeID))
        }
    }

    func testValidateRejectsEmptyFields() {
        let emptyID = [Parity.Entry(command: .save, winMergeID: "  ", tooltip: "Save (Ctrl+S)", shortcutDisplay: "Ctrl+S")]
        XCTAssertThrowsError(try Parity.validate(emptyID)) { error in
            XCTAssertEqual(error as? Parity.ValidationError, .emptyWinMergeID(.save))
        }
        let emptyTip = [Parity.Entry(command: .save, winMergeID: "ID_FILE_SAVE", tooltip: "  ", shortcutDisplay: "Ctrl+S")]
        XCTAssertThrowsError(try Parity.validate(emptyTip)) { error in
            XCTAssertEqual(error as? Parity.ValidationError, .emptyTooltip(.save))
        }
        let emptyShortcut = [Parity.Entry(command: .save, winMergeID: "ID_FILE_SAVE", tooltip: "Save (Ctrl+S)", shortcutDisplay: " ")]
        XCTAssertThrowsError(try Parity.validate(emptyShortcut)) { error in
            XCTAssertEqual(error as? Parity.ValidationError, .emptyShortcutDisplay(.save))
        }
    }

    func testValidateRejectsStaleWinMergeID() {
        var candidates = Parity.entries
        guard let index = candidates.firstIndex(where: { $0.command == .save }) else {
            return XCTFail("missing .save")
        }
        let original = candidates[index]
        candidates[index] = Parity.Entry(
            command: .save,
            winMergeID: "ID_FILE_STALE",
            tooltip: original.tooltip,
            shortcutDisplay: original.shortcutDisplay
        )
        XCTAssertThrowsError(try Parity.validate(candidates)) { error in
            XCTAssertEqual(
                error as? Parity.ValidationError,
                .staleWinMergeID(.save, "ID_FILE_STALE")
            )
        }
    }

    func testValidateRejectsMissingCommand() {
        var candidates = Parity.entries
        candidates.removeAll { $0.command == .refresh }
        XCTAssertThrowsError(try Parity.validate(candidates)) { error in
            XCTAssertEqual(error as? Parity.ValidationError, .missingCommand(.refresh))
        }
    }
}
