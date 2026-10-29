import MacMergeCore
import SwiftUI
import XCTest

@testable import MacMerge

@MainActor
final class DirectionalCopyKeyRoutingTests: XCTestCase {
    private let optionRight = try! KeyboardShortcutPolicy.Chord(
        .special(.rightArrow), modifiers: [.option])

    func testMenuShortcutsComeFromCatalog() {
        XCTAssertNil(DirectionalCopyShortcuts.menuBinding(for: .copyToRight)?.menuKeyboardShortcut)
        let advance = DirectionalCopyShortcuts.menuBinding(for: .copyToRightAndAdvance)?
            .menuKeyboardShortcut
        XCTAssertEqual(advance?.key, .rightArrow)
        XCTAssertEqual(advance?.modifiers, [.command, .option])
        for binding in DirectionalCopyShortcuts.focusRoutedBindings {
            XCTAssertNil(binding.menuKeyboardShortcut, "\(binding.command)")
        }
    }

    func testOptionArrowCopiesCurrentRowDifferenceWithoutExplicitSelection() async throws {
        let model = ComparisonModel()
        model.enqueueOpen([
            try temporaryFile(name: "left.txt", content: "same\nleft\nsame\n"),
            try temporaryFile(name: "right.txt", content: "same\nright\nsame\n")
        ])
        await waitUntilIdle(model)
        let difference = try XCTUnwrap(model.rows.first { $0.left?.text == "left" })
        model.selectDifference(nil)
        model.moveCursor(to: difference.id)
        XCTAssertNil(model.selectedDifferenceID)
        XCTAssertEqual(model.currentRowID, difference.id)
        XCTAssertTrue(ComparisonCopyCommand.selectedToRight.isEnabled(on: model))

        XCTAssertEqual(
            DirectionalCopyKeyRouter.decision(for: optionRight, editorFocus: .none, model: model),
            .perform(.copyToRight))
        guard
            case .passThrough(.nativeTextEditing) = DirectionalCopyKeyRouter.decision(
                for: optionRight, editorFocus: .readOnly, model: model)
        else {
            return XCTFail("text focus must keep Option-Right for word navigation")
        }
    }

    private func temporaryFile(name: String, content: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: name)
        try Data(content.utf8).write(to: url)
        return url
    }

    private func waitUntilIdle(_ model: ComparisonModel) async {
        await withCheckedContinuation { continuation in
            model.whenIdle { continuation.resume() }
        }
    }
}
