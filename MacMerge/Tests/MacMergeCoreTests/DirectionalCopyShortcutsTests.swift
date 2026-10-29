import MacMergeCore
import XCTest

final class DirectionalCopyShortcutsTests: XCTestCase {
    typealias Catalog = DirectionalCopyShortcuts

    func testSharedPolicyAuditFindsNoConflicts() throws {
        let policy = try DifferenceNavigationShortcuts.sharedPolicy.get()
        XCTAssertEqual(Catalog.auditConflicts(policy: policy), [])
    }

    func testOnlyCopyAndAdvanceHaveMenuKeyEquivalents() {
        XCTAssertNil(Catalog.menuBinding(for: .copyToRight))
        XCTAssertNil(Catalog.menuBinding(for: .copyToLeft))
        XCTAssertEqual(
            Catalog.menuBinding(for: .copyToRightAndAdvance)?.chord.modifiers, [.command, .option])
        XCTAssertEqual(
            Catalog.menuBinding(for: .copyToLeftAndAdvance)?.chord.modifiers, [.command, .option])
    }

    func testHintsNameChordAndFocusCondition() {
        XCTAssertEqual(
            Catalog.shortcutHint(for: .copyToRight), "Option-Right Arrow when the diff list has focus")
        XCTAssertEqual(
            Catalog.shortcutHint(for: .copyToLeft), "Option-Left Arrow when the diff list has focus")
        XCTAssertEqual(Catalog.shortcutHint(for: .copyToRightAndAdvance), "Option-Command-Right Arrow")
        XCTAssertNil(Catalog.alternateHint(for: .copyToLeftAndAdvance))
        let hint = try? XCTUnwrap(Catalog.alternateHint(for: .copyToRight))
        XCTAssertEqual(
            hint,
            "Also Option-Right Arrow (WinMerge VK_RIGHT, ALT) when the diff list has focus. "
                + "A focused text view keeps the chord for word navigation.")
    }

    func testUnmappedCopyFromAcceleratorsCiteNativeReservation() {
        XCTAssertEqual(
            Catalog.unmappedWinMergeAccelerators.map(\.reason),
            [
                .nativeTextReservation(.moveWordRightAndModifySelection),
                .nativeTextReservation(.moveWordLeftAndModifySelection)
            ])
    }
}
