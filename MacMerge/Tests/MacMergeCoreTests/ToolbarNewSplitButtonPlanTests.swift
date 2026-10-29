import Foundation
import XCTest

@testable import MacMergeCore

final class ToolbarNewSplitButtonPlanTests: XCTestCase {
    typealias Plan = ToolbarNewSplitButtonPlan

    /// `IDR_POPUP_NEW` in `Src/Merge.rc` (lines 1180-1191).
    private let toolbarPopup: [(String, String)] = [
        ("&Text", "ID_FILE_NEW"),
        ("T&able", "ID_FILE_NEW_TABLE"),
        ("&Binary", "ID_FILE_NEW_HEX"),
        ("&Image", "ID_FILE_NEW_IMAGE"),
        ("&Webpage", "ID_FILE_NEW_WEBPAGE"),
        ("&Folder", "ID_FILE_NEW_FOLDER")
    ]

    /// File menu `New (&3 panes)` popup in `Src/Merge.rc` (lines 333-341).
    private let threePanePopup: [(String, String)] = [
        ("&Text", "ID_FILE_NEW3"),
        ("T&able", "ID_FILE_NEW3_TABLE"),
        ("&Binary", "ID_FILE_NEW3_HEX"),
        ("&Image", "ID_FILE_NEW3_IMAGE"),
        ("&Webpage", "ID_FILE_NEW3_WEBPAGE"),
        ("&Folder", "ID_FILE_NEW3_FOLDER")
    ]

    func testToolbarPopupMatchesWinMergeOrderAndText() throws {
        let plan = Plan.make(isNewCommandEnabled: true)
        let section = try XCTUnwrap(plan.sections.first)
        XCTAssertEqual(section.kind, .twoPane)
        XCTAssertEqual(section.presentation, .inline)
        XCTAssertNil(section.title)
        XCTAssertEqual(section.entries.map(\.resourceTitle), toolbarPopup.map(\.0))
        XCTAssertEqual(section.entries.map(\.commandID.rawValue), toolbarPopup.map(\.1))
        XCTAssertEqual(
            section.entries.map(\.title), ["Text", "Table", "Binary", "Image", "Webpage", "Folder"])
        XCTAssertEqual(section.entries.map(\.mnemonic), ["t", "a", "b", "i", "w", "f"])
        XCTAssertTrue(section.entries.allSatisfy { $0.source == .winMergeToolbarPopup })
        XCTAssertTrue(plan.representsEveryToolbarPopupCommand)
    }

    func testThreePaneSubmenuMatchesFileMenuResource() throws {
        let plan = Plan.make(isNewCommandEnabled: true)
        XCTAssertEqual(plan.sections.map(\.kind), [.twoPane, .threePane])
        let section = try XCTUnwrap(plan.sections.last)
        XCTAssertEqual(section.presentation, .submenu)
        XCTAssertEqual(section.resourceTitle, "New (&3 panes)")
        XCTAssertEqual(section.title, "New (3 panes)")
        XCTAssertEqual(section.entries.map(\.resourceTitle), threePanePopup.map(\.0))
        XCTAssertEqual(section.entries.map(\.commandID.rawValue), threePanePopup.map(\.1))
        XCTAssertTrue(
            section.entries.allSatisfy { $0.source == .winMergeFileMenuThreePaneExtension })
        XCTAssertEqual(section.entries.first?.accessibilityLabel, "New 3-Pane Text Comparison")
        XCTAssertEqual(plan.entries.count, Plan.CommandID.allCases.count)
        XCTAssertEqual(Set(plan.entries.map(\.commandID)), Set(Plan.CommandID.allCases))
    }

    func testOmittedVariantKeepsStrictToolbarPopupParity() {
        let plan = Plan.make(isNewCommandEnabled: true, threePaneVariants: .omitted)
        XCTAssertEqual(plan.sections.map(\.kind), [.twoPane])
        XCTAssertEqual(plan.entries.map(\.commandID.rawValue), toolbarPopup.map(\.1))
        XCTAssertTrue(plan.representsEveryToolbarPopupCommand)
        XCTAssertNil(plan.entry(for: .threePaneText))
    }

    func testDisabledReasons() {
        let closed = Plan.make(isNewCommandEnabled: false)
        XCTAssertEqual(closed.primaryAvailability, .disabled(.newCommandUnavailable))
        XCTAssertTrue(
            closed.entries.allSatisfy {
                $0.availability.disabledReason == .newCommandUnavailable
            })

        let open = Plan.make(isNewCommandEnabled: true, implementedCommands: [.twoPaneText])
        XCTAssertEqual(open.primaryAvailability, .enabled)
        XCTAssertEqual(open.entry(for: .twoPaneText)?.availability, .enabled)
        XCTAssertEqual(
            open.entry(for: .twoPaneFolder)?.availability,
            .disabled(.notImplemented(mode: .folder, paneCount: .two)))
        XCTAssertEqual(
            open.entry(for: .threePaneImage)?.availability,
            .disabled(.notImplemented(mode: .image, paneCount: .three)))
        XCTAssertEqual(open.entries.filter(\.isEnabled).map(\.commandID), [.twoPaneText])

        let none = Plan.make(isNewCommandEnabled: true, implementedCommands: [])
        XCTAssertEqual(
            none.primaryAvailability,
            .disabled(.notImplemented(mode: .text, paneCount: .two)))
    }

    func testPrimaryActionIsTwoPaneText() {
        let plan = Plan.make(isNewCommandEnabled: true)
        XCTAssertEqual(plan.primaryCommandID, .twoPaneText)
        XCTAssertEqual(plan.entries.filter(\.isPrimaryAction).map(\.commandID), [.twoPaneText])
        // `ComparisonToolbar.perform` in the app routes only `.twoPaneText` and asserts on any
        // other command. Growing this set must come with a new app route.
        XCTAssertEqual(
            Plan.currentlyImplementedCommands, [.twoPaneText],
            "Add an app route in ComparisonToolbar.perform before implementing another command")
    }

    func testPrimaryStringsComeFromStringTablePrompt() {
        // `ID_FILE_NEW "\nNew Documents (Ctrl+N)"`: empty label, tooltip "New Documents".
        XCTAssertEqual(Plan.primaryAccessibilityLabel, "New Documents")
        XCTAssertEqual(Plan.primaryHelp, "New Documents (Command-N)")
        XCTAssertEqual(Plan.primaryTitle, "New")
    }

    func testMnemonicParsing() {
        XCTAssertEqual(Plan.strippingMnemonic("T&able"), "Table")
        XCTAssertEqual(Plan.strippingMnemonic("Save && Close"), "Save & Close")
        XCTAssertEqual(Plan.strippingMnemonic("A&&&B"), "A&B")
        XCTAssertEqual(Plan.strippingMnemonic("Trailing&"), "Trailing")
        XCTAssertEqual(Plan.strippingMnemonic("None"), "None")

        XCTAssertEqual(Plan.mnemonic(in: "T&able"), "a")
        XCTAssertEqual(Plan.mnemonic(in: "New (&3 panes)"), "3")
        XCTAssertEqual(Plan.mnemonic(in: "&Text"), "t")
        XCTAssertNil(Plan.mnemonic(in: "Save && Close"))
        XCTAssertEqual(Plan.mnemonic(in: "Save && &Close"), "c")
        XCTAssertNil(Plan.mnemonic(in: "Trailing&"))
        XCTAssertNil(Plan.mnemonic(in: "None"))
    }

    func testLayoutRendersPlanThroughNewComparisonControl() throws {
        let layout = ToolbarCommandLayout.make(state: .freshWindow)
        let control = try XCTUnwrap(
            layout.slots.lazy.compactMap { slot -> ToolbarCommandLayout.Control? in
                if case .control(let control) = slot, control.command == .newComparison {
                    return control
                }
                return nil
            }.first)
        XCTAssertEqual(control.kind, .splitButton)
        XCTAssertEqual(control.title, Plan.primaryTitle)
        XCTAssertEqual(control.help, Plan.primaryHelp)
        XCTAssertEqual(control.primaryAction, .newDocument(.twoPaneText))
    }

    // MARK: - Src/Merge.rc parity

    func testResourceTablesMatchMergeRC() throws {
        let rcURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MacMergeCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // MacMerge
            .deletingLastPathComponent()  // repo root
            .appending(path: "Src/Merge.rc")
        guard let rc = try? String(contentsOf: rcURL, encoding: .utf8) else {
            throw XCTSkip("Src/Merge.rc not found at \(rcURL.path)")
        }
        let lines = rc.components(separatedBy: .newlines)

        let toolbar = try XCTUnwrap(
            Self.menuItems(in: lines, after: { $0.hasPrefix("IDR_POPUP_NEW ") }),
            "IDR_POPUP_NEW block not found")
        XCTAssertEqual(toolbar.map(\.title), Plan.toolbarPopupResources.map(\.resourceTitle))
        XCTAssertEqual(
            toolbar.map(\.id), Plan.toolbarPopupResources.map(\.commandID.rawValue))

        let threePaneHeader = "POPUP \"\(Plan.threePaneSubmenuResourceTitle)\""
        let threePane = try XCTUnwrap(
            Self.menuItems(
                in: lines,
                after: {
                    $0.trimmingCharacters(in: .whitespaces) == threePaneHeader
                }),
            "First \(threePaneHeader) block not found")
        XCTAssertEqual(threePane.map(\.title), Plan.threePaneResources.map(\.resourceTitle))
        XCTAssertEqual(threePane.map(\.id), Plan.threePaneResources.map(\.commandID.rawValue))
    }

    /// `MENUITEM "<title>", <ID>` pairs of the first innermost `BEGIN`/`END` block that follows
    /// the first line matching `header`.
    private static func menuItems(
        in lines: [String], after header: (String) -> Bool
    ) -> [(title: String, id: String)]? {
        guard let start = lines.firstIndex(where: header) else { return nil }
        var items: [(title: String, id: String)] = []
        var inBlock = false
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "BEGIN" {
                if !items.isEmpty { break }  // a nested block after items ends this one
                inBlock = true
                continue
            }
            if trimmed == "END" {
                if inBlock && !items.isEmpty { return items }
                continue
            }
            guard inBlock, trimmed.hasPrefix("MENUITEM \"") else { continue }
            let body = trimmed.dropFirst("MENUITEM \"".count)
            guard let close = body.firstIndex(of: "\"") else { continue }
            let title = String(body[..<close])
            let id = body[body.index(after: close)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: ", \t"))
            items.append((title, id))
        }
        return items.isEmpty ? nil : items
    }
}
