import AppKit
import Foundation
import MacMergeCore
import SwiftUI
import XCTest

@testable import MacMerge

@MainActor
final class DifferenceNavigationKeyRoutingTests: XCTestCase {
    typealias Chord = KeyboardShortcutPolicy.Chord

    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ))
    }

    func testChordMapsNavigationKeysAndIgnoresFunctionFlag() throws {
        let cases: [(UInt16, String, KeyboardShortcutPolicy.Key)] = [
            (125, "\u{F701}", .special(.downArrow)),
            (126, "\u{F700}", .special(.upArrow)),
            (115, "\u{F729}", .special(.home)),
            (119, "\u{F72B}", .special(.end)),
            (36, "\r", .special(.return)),
            (76, "\u{3}", .special(.return))
        ]
        for (keyCode, characters, key) in cases {
            let event = try keyEvent(
                keyCode: keyCode, characters: characters, modifiers: [.option, .function])
            XCTAssertEqual(
                DifferenceNavigationKeyRouter.chord(for: event),
                try Chord(key, modifiers: [.option]),
                "keyCode \(keyCode)"
            )
        }
        let shifted = try keyEvent(
            keyCode: 125, characters: "\u{F701}", modifiers: [.option, .shift, .function])
        XCTAssertEqual(
            DifferenceNavigationKeyRouter.chord(for: shifted),
            try Chord(.special(.downArrow), modifiers: [.option, .shift])
        )
    }

    func testChordIgnoresMenuOwnedFunctionKeysAndOtherKeys() throws {
        // F7 (98) and F8 (100) belong to the Merge menu key equivalents.
        for keyCode: UInt16 in [98, 100, 0, 123, 124] {
            let event = try keyEvent(keyCode: keyCode, characters: "x", modifiers: [.option])
            XCTAssertNil(DifferenceNavigationKeyRouter.chord(for: event), "keyCode \(keyCode)")
        }
    }

    func testMenuShortcutsComeFromCatalog() {
        let next = DifferenceNavigationShortcuts.menuBinding(for: .next)?.menuKeyboardShortcut
        let previous = DifferenceNavigationShortcuts.menuBinding(for: .previous)?
            .menuKeyboardShortcut
        XCTAssertEqual(next?.key, KeyEquivalent("\u{F70B}"))
        XCTAssertEqual(next?.modifiers, [])
        XCTAssertEqual(previous?.key, KeyEquivalent("\u{F70A}"))
        XCTAssertEqual(previous?.modifiers, [])
        for binding in DifferenceNavigationShortcuts.focusRoutedBindings {
            XCTAssertNil(binding.menuKeyboardShortcut, "\(binding.command)")
        }
    }

    func testRepeatedFirstAndLastBumpRevealRevisionAndCurrentStaysEnabledWhenStale()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let leftURL = directory.appending(path: "left.txt")
        let rightURL = directory.appending(path: "right.txt")
        try Data("a\nleft one\nsame\nleft two\n".utf8).write(to: leftURL)
        try Data("a\nright one\nsame\nright two\n".utf8).write(to: rightURL)

        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        let idle = expectation(description: "idle")
        model.whenIdle { idle.fulfill() }
        await fulfillment(of: [idle], timeout: 5)

        XCTAssertEqual(model.differenceNavigationLifecycle, .different)
        model.performDifferenceNavigation(.first)
        let firstID = try XCTUnwrap(model.selectedDifferenceID)
        let afterFirst = model.selectedDifferenceRevealRevision
        model.performDifferenceNavigation(.first)
        XCTAssertEqual(model.selectedDifferenceID, firstID)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, afterFirst &+ 1)

        model.performDifferenceNavigation(.last)
        let lastID = try XCTUnwrap(model.selectedDifferenceID)
        XCTAssertNotEqual(lastID, firstID)
        let afterLast = model.selectedDifferenceRevealRevision
        model.performDifferenceNavigation(.last)
        XCTAssertEqual(model.selectedDifferenceID, lastID)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, afterLast &+ 1)

        // A single-line edit leaves the comparison stale with the difference still current;
        // the Merge menu keeps Current Difference enabled, so Option-Return must route too.
        model.editLine(rowID: lastID, on: .left, replacement: "edited")
        XCTAssertFalse(model.isComparisonCurrent)
        XCTAssertFalse(model.hasDifferences)
        XCTAssertTrue(model.canSelectCurrentDifference)
        XCTAssertEqual(model.enabledDifferenceNavigationCommands, [.current])
        XCTAssertEqual(model.differenceNavigationLifecycle, .different)
        let decision = DifferenceNavigationShortcuts.route(
            try Chord(.special(.return), modifiers: [.option]),
            in: .init(lifecycle: model.differenceNavigationLifecycle),
            enabledCommands: model.enabledDifferenceNavigationCommands,
            policy: try DifferenceNavigationShortcuts.sharedPolicy.get()
        )
        XCTAssertEqual(decision, .perform(.current))
    }

    func testLifecycleReportsDifferentWheneverCurrentDifferenceIsEnabled() {
        let model = ComparisonModel()
        XCTAssertFalse(model.canSelectCurrentDifference)
        XCTAssertNotEqual(model.differenceNavigationLifecycle, .different)
        XCTAssertTrue(model.enabledDifferenceNavigationCommands.isEmpty)
    }
}
