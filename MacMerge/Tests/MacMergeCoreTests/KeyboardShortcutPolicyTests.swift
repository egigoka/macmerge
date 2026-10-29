import Foundation
import MacMergeCore
import XCTest

final class KeyboardShortcutPolicyTests: XCTestCase {
    typealias Policy = KeyboardShortcutPolicy
    typealias PolicyError = KeyboardShortcutPolicyError

    private struct ApplicationBinding: Hashable {
        let command: Policy.Command
        let chord: String
        let states: Set<Policy.LifecycleState>
        let requiresDirty: Bool
        let requiresSelection: Bool
        let allowsReadOnly: Bool

        init(_ shortcut: Policy.CommandShortcut) {
            command = shortcut.command
            chord = shortcut.chord.canonicalDescription
            states = shortcut.enabledLifecycleStates
            requiresDirty = shortcut.requiresDirty
            requiresSelection = shortcut.requiresSelection
            allowsReadOnly = shortcut.allowsReadOnly
        }

        init(
            command: Policy.Command,
            chord: String,
            states: Set<Policy.LifecycleState>,
            requiresDirty: Bool,
            requiresSelection: Bool,
            allowsReadOnly: Bool
        ) {
            self.command = command
            self.chord = chord
            self.states = states
            self.requiresDirty = requiresDirty
            self.requiresSelection = requiresSelection
            self.allowsReadOnly = allowsReadOnly
        }
    }

    private struct NativeBinding: Hashable {
        let command: Policy.NativeTextEditingCommand
        let chord: String
        let applicability: Policy.NativeTextEditingApplicability

        init(_ reservation: Policy.NativeTextEditingReservation) {
            command = reservation.command
            chord = reservation.chord.canonicalDescription
            applicability = reservation.applicability
        }

        init(
            command: Policy.NativeTextEditingCommand,
            chord: String,
            applicability: Policy.NativeTextEditingApplicability
        ) {
            self.command = command
            self.chord = chord
            self.applicability = applicability
        }
    }

    private struct CollisionInventoryItem: Hashable {
        let chord: String
        let kinds: Set<Policy.CollisionKind>
        let commands: [Policy.Command]
        let nativeCommands: [Policy.NativeTextEditingCommand]
        let commandShortcutCount: Int
        let nativeReservationCount: Int
        let isConditional: Bool

        init(_ collision: Policy.Collision) {
            chord = collision.chord.canonicalDescription
            kinds = collision.kinds
            commands = collision.commands
            nativeCommands = collision.nativeTextEditingCommands
            commandShortcutCount = collision.commandShortcutCount
            nativeReservationCount = collision.nativeReservationCount
            isConditional = collision.isConditional
        }

        init(
            chord: String,
            kinds: Set<Policy.CollisionKind>,
            commands: [Policy.Command],
            nativeCommands: [Policy.NativeTextEditingCommand],
            commandShortcutCount: Int,
            nativeReservationCount: Int,
            isConditional: Bool
        ) {
            self.chord = chord
            self.kinds = kinds
            self.commands = commands
            self.nativeCommands = nativeCommands
            self.commandShortcutCount = commandShortcutCount
            self.nativeReservationCount = nativeReservationCount
            self.isConditional = isConditional
        }
    }

    func testChordCanonicalizationCoversLettersAndEveryShiftedPunctuationAlias() throws {
        for scalarValue in UInt32(0x41)...UInt32(0x5A) {
            let upper = try XCTUnwrap(UnicodeScalar(scalarValue)).description.first!
            let lower = try XCTUnwrap(UnicodeScalar(scalarValue + 0x20)).description.first!
            XCTAssertEqual(
                try chord(.character(upper), [.command]),
                try chord(.character(lower), [.command]),
                "ASCII scalar \(scalarValue)"
            )
        }

        let shiftedAliases: [(shifted: Character, physical: Character)] = [
            ("!", "1"), ("@", "2"), ("#", "3"), ("$", "4"), ("%", "5"),
            ("^", "6"), ("&", "7"), ("*", "8"), ("(", "9"), (")", "0"),
            ("_", "-"), ("+", "="), ("{", "["), ("}", "]"), ("|", "\\"),
            (":", ";"), ("\"", "'"), ("<", ","), (">", "."), ("?", "/"),
            ("~", "`")
        ]
        for alias in shiftedAliases {
            let canonical = try chord(.character(alias.shifted), [.command, .option])
            let explicitShift = try chord(
                .character(alias.shifted),
                [.command, .option, .shift]
            )
            let physical = try chord(
                .character(alias.physical),
                [.command, .option, .shift]
            )
            XCTAssertEqual(canonical, physical, "Alias \(alias.shifted)")
            XCTAssertEqual(explicitShift, canonical, "Explicit Shift alias \(alias.shifted)")
            XCTAssertEqual(canonical.key, .character(alias.physical), "Alias \(alias.shifted)")
            XCTAssertEqual(
                canonical.modifiers,
                [.command, .option, .shift],
                "Alias \(alias.shifted)"
            )
        }

        XCTAssertEqual(
            try chord(.character("?"), [.option, .function]).canonicalDescription,
            "option+shift+function+/"
        )
        XCTAssertEqual(
            try chord(.special(.leftArrow), [.command, .control, .shift])
                .canonicalDescription,
            "command+control+shift+leftArrow"
        )
        XCTAssertEqual(try chord(.function(24), [.function]).canonicalDescription, "function+f24")
        XCTAssertNotEqual(
            try chord(.character("A"), [.command]),
            try chord(.character("a"), [.command, .shift]),
            "Letter case is key identity; Shift remains an explicit event modifier."
        )
        XCTAssertEqual(
            try chord(.character("A"), [.command, .shift]),
            try chord(.character("a"), [.command, .shift]),
            "Canonicalizing an uppercase key must preserve an existing Shift modifier."
        )
    }

    func testUnfinishedAuditHasExactApplicationBindingAndCollisionInventories() throws {
        let policy = try Policy.makeUnfinishedAudit()
        let workspace: Set<Policy.LifecycleState> = [.empty, .equal, .different, .failed]
        let current: Set<Policy.LifecycleState> = [.equal, .different]
        let differences: Set<Policy.LifecycleState> = [.different]
        let all = Set(Policy.LifecycleState.allCases)
        let expectedBindings: Set<ApplicationBinding> = [
            applicationBinding(.newComparison, "command+n", workspace),
            applicationBinding(.openComparison, "command+o", workspace),
            applicationBinding(.save, "command+s", workspace, dirty: true, readOnly: false),
            applicationBinding(.undo, "command+z", workspace, readOnly: false),
            applicationBinding(
                .redo,
                "command+shift+z",
                workspace,
                readOnly: false
            ),
            applicationBinding(.selectLineDifference, "f4", differences),
            applicationBinding(.selectPreviousLineDifference, "shift+f4", differences),
            applicationBinding(.nextDifference, "f8", differences),
            applicationBinding(.nextDifference, "option+downArrow", differences),
            applicationBinding(.previousDifference, "f7", differences),
            applicationBinding(.previousDifference, "option+upArrow", differences),
            applicationBinding(.nextConflict, "shift+f8", differences),
            applicationBinding(.nextConflict, "option+shift+downArrow", differences),
            applicationBinding(.previousConflict, "shift+f7", differences),
            applicationBinding(.previousConflict, "option+shift+upArrow", differences),
            applicationBinding(.firstDifference, "option+home", differences),
            applicationBinding(.currentDifference, "option+return", differences),
            applicationBinding(.lastDifference, "option+end", differences),
            applicationBinding(
                .copyToRight,
                "option+rightArrow",
                differences,
                selection: true,
                readOnly: false
            ),
            applicationBinding(
                .copyToLeft,
                "option+leftArrow",
                differences,
                selection: true,
                readOnly: false
            ),
            applicationBinding(
                .copyToRightAndAdvance,
                "command+option+rightArrow",
                differences,
                selection: true,
                readOnly: false
            ),
            applicationBinding(
                .copyToLeftAndAdvance,
                "command+option+leftArrow",
                differences,
                selection: true,
                readOnly: false
            ),
            applicationBinding(.previousComparedFile, "command+f7", current),
            applicationBinding(.nextComparedFile, "command+f8", current),
            applicationBinding(.reloadFromDisk, "command+f5", current),
            applicationBinding(.refresh, "f5", current.union([.failed])),
            applicationBinding(.changePane, "f6", current),
            applicationBinding(.changePaneBack, "shift+f6", current),
            applicationBinding(.mergeMode, "f9", current),
            applicationBinding(.options, "command+,", all)
        ]
        let actualBindings = Set(policy.commandShortcuts.map(ApplicationBinding.init))

        XCTAssertEqual(actualBindings, expectedBindings)
        XCTAssertEqual(policy.commandShortcuts.count, expectedBindings.count)

        let expectedCollisions: Set<CollisionInventoryItem> = [
            collision("f5", .refresh, .complete),
            collision("option+return", .currentDifference, .insertNewlineIgnoringFieldEditor),
            collision("option+leftArrow", .copyToLeft, .moveWordLeft),
            collision("option+rightArrow", .copyToRight, .moveWordRight),
            collision("option+upArrow", .previousDifference, .moveParagraphUp),
            collision("option+downArrow", .nextDifference, .moveParagraphDown),
            collision("option+home", .firstDifference, .moveBackwardToParagraphStart),
            collision("option+end", .lastDifference, .moveForwardToParagraphEnd),
            collision("command+z", .undo, .undo),
            collision("command+shift+z", .redo, .redo),
            collision(
                "option+shift+upArrow",
                .previousConflict,
                .moveParagraphUpAndModifySelection
            ),
            collision(
                "option+shift+downArrow",
                .nextConflict,
                .moveParagraphDownAndModifySelection
            )
        ]
        let actualCollisions = Set(policy.collisions.map(CollisionInventoryItem.init))

        XCTAssertEqual(actualCollisions, expectedCollisions)
        XCTAssertEqual(policy.collisions.count, expectedCollisions.count)
    }

    func testStandardNativeReservationsHaveExactCompleteTupleInventory() {
        let both = Policy.NativeTextEditingApplicability.readOnlyAndEditable
        let editable = Policy.NativeTextEditingApplicability.editable
        let expected: Set<NativeBinding> = [
            nativeBinding(.selectAll, "command+a", both),
            nativeBinding(.copy, "command+c", both),
            nativeBinding(.cut, "command+x", editable),
            nativeBinding(.paste, "command+v", editable),
            nativeBinding(.undo, "command+z", editable),
            nativeBinding(.redo, "command+shift+z", editable),
            nativeBinding(.find, "command+f", both),
            nativeBinding(.findNext, "command+g", both),
            nativeBinding(.findPrevious, "command+shift+g", both),
            nativeBinding(.moveLeft, "leftArrow", both),
            nativeBinding(.moveRight, "rightArrow", both),
            nativeBinding(.moveUp, "upArrow", both),
            nativeBinding(.moveDown, "downArrow", both),
            nativeBinding(.moveLeftAndModifySelection, "shift+leftArrow", both),
            nativeBinding(.moveRightAndModifySelection, "shift+rightArrow", both),
            nativeBinding(.moveUpAndModifySelection, "shift+upArrow", both),
            nativeBinding(.moveDownAndModifySelection, "shift+downArrow", both),
            nativeBinding(.moveWordLeft, "option+leftArrow", both),
            nativeBinding(.moveWordRight, "option+rightArrow", both),
            nativeBinding(.moveWordLeftAndModifySelection, "option+shift+leftArrow", both),
            nativeBinding(.moveWordRightAndModifySelection, "option+shift+rightArrow", both),
            nativeBinding(.moveParagraphUp, "option+upArrow", both),
            nativeBinding(.moveParagraphDown, "option+downArrow", both),
            nativeBinding(.moveParagraphUpAndModifySelection, "option+shift+upArrow", both),
            nativeBinding(.moveParagraphDownAndModifySelection, "option+shift+downArrow", both),
            nativeBinding(.moveLineStart, "command+leftArrow", both),
            nativeBinding(.moveLineEnd, "command+rightArrow", both),
            nativeBinding(.moveLineStartAndModifySelection, "command+shift+leftArrow", both),
            nativeBinding(.moveLineEndAndModifySelection, "command+shift+rightArrow", both),
            nativeBinding(.moveDocumentStart, "command+upArrow", both),
            nativeBinding(.moveDocumentEnd, "command+downArrow", both),
            nativeBinding(.moveDocumentStartAndModifySelection, "command+shift+upArrow", both),
            nativeBinding(.moveDocumentEndAndModifySelection, "command+shift+downArrow", both),
            nativeBinding(.scrollDocumentStart, "home", both),
            nativeBinding(.scrollDocumentEnd, "end", both),
            nativeBinding(.moveDocumentStartAndModifySelection, "shift+home", both),
            nativeBinding(.moveDocumentEndAndModifySelection, "shift+end", both),
            nativeBinding(.moveBackwardToParagraphStart, "option+home", both),
            nativeBinding(.moveForwardToParagraphEnd, "option+end", both),
            nativeBinding(.moveParagraphUpAndModifySelection, "option+shift+home", both),
            nativeBinding(.moveParagraphDownAndModifySelection, "option+shift+end", both),
            nativeBinding(.scrollPageUp, "pageUp", both),
            nativeBinding(.scrollPageDown, "pageDown", both),
            nativeBinding(.movePageUp, "option+pageUp", both),
            nativeBinding(.movePageDown, "option+pageDown", both),
            nativeBinding(.movePageUpAndModifySelection, "shift+pageUp", both),
            nativeBinding(.movePageDownAndModifySelection, "shift+pageDown", both),
            nativeBinding(.scrollPageUp, "control+upArrow", both),
            nativeBinding(.scrollPageDown, "control+downArrow", both),
            nativeBinding(.moveLineStart, "control+leftArrow", both),
            nativeBinding(.moveLineEnd, "control+rightArrow", both),
            nativeBinding(.moveLineStartAndModifySelection, "control+shift+leftArrow", both),
            nativeBinding(.moveLineEndAndModifySelection, "control+shift+rightArrow", both),
            nativeBinding(.insertNewline, "return", editable),
            nativeBinding(.insertLineBreak, "control+return", editable),
            nativeBinding(.insertNewlineIgnoringFieldEditor, "option+return", editable),
            nativeBinding(.insertTab, "tab", editable),
            nativeBinding(.insertBacktab, "shift+tab", editable),
            nativeBinding(.selectNextKeyView, "control+tab", both),
            nativeBinding(.selectPreviousKeyView, "control+shift+tab", both),
            nativeBinding(.insertTabIgnoringFieldEditor, "option+tab", editable),
            nativeBinding(.insertSpace, "space", editable),
            nativeBinding(.deleteBackward, "backspace", editable),
            nativeBinding(.deleteForward, "delete", editable),
            nativeBinding(.deleteWordBackward, "option+backspace", editable),
            nativeBinding(.deleteWordBackward, "control+option+backspace", editable),
            nativeBinding(.deleteWordForward, "option+delete", editable),
            nativeBinding(.deleteToBeginningOfLine, "command+backspace", editable),
            nativeBinding(.deleteToEndOfLine, "command+delete", editable),
            nativeBinding(.moveToBeginningOfParagraph, "control+a", both),
            nativeBinding(.moveToEndOfParagraph, "control+e", both),
            nativeBinding(.moveBackward, "control+b", both),
            nativeBinding(.insertNewline, "control+c", editable),
            nativeBinding(.moveForward, "control+f", both),
            nativeBinding(.insertNewline, "control+j", editable),
            nativeBinding(.moveUp, "control+p", both),
            nativeBinding(.moveDown, "control+n", both),
            nativeBinding(.moveToBeginningOfParagraphAndModifySelection, "control+shift+a", both),
            nativeBinding(.moveToEndOfParagraphAndModifySelection, "control+shift+e", both),
            nativeBinding(.moveBackwardAndModifySelection, "control+shift+b", both),
            nativeBinding(.moveForwardAndModifySelection, "control+shift+f", both),
            nativeBinding(.moveUpAndModifySelection, "control+shift+p", both),
            nativeBinding(.moveDownAndModifySelection, "control+shift+n", both),
            nativeBinding(.scrollPageDown, "control+v", both),
            nativeBinding(.movePageDownAndModifySelection, "control+shift+v", both),
            nativeBinding(.moveWordLeft, "control+option+b", both),
            nativeBinding(.moveWordRight, "control+option+f", both),
            nativeBinding(
                .moveWordLeftAndModifySelection,
                "control+option+shift+b",
                both
            ),
            nativeBinding(
                .moveWordRightAndModifySelection,
                "control+option+shift+f",
                both
            ),
            nativeBinding(.centerSelectionInVisibleArea, "control+l", both),
            nativeBinding(.deleteBackward, "control+h", editable),
            nativeBinding(.deleteForward, "control+d", editable),
            nativeBinding(.deleteToEndOfParagraph, "control+k", editable),
            nativeBinding(.transpose, "control+t", editable),
            nativeBinding(.insertNewlineIgnoringFieldEditor, "control+o", editable),
            nativeBinding(.insertTab, "control+i", editable),
            nativeBinding(.insertNewline, "control+m", editable),
            nativeBinding(.yank, "control+y", editable),
            nativeBinding(.cancelOperation, "escape", both),
            nativeBinding(.cancelOperation, "command+.", both),
            nativeBinding(.complete, "option+escape", editable),
            nativeBinding(.complete, "f5", editable),
            nativeBinding(
                .deleteBackwardByDecomposingPreviousCharacter,
                "control+backspace",
                editable
            )
        ]
        let actual = Set(Policy.standardNativeTextEditingReservations.map(NativeBinding.init))

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(Policy.standardNativeTextEditingReservations.count, expected.count)
    }

    func testNativeCommandAndCollisionKindInventoriesAreExact() {
        XCTAssertEqual(
            Policy.NativeTextEditingCommand.allCases,
            [
                .selectAll,
                .copy,
                .cut,
                .paste,
                .undo,
                .redo,
                .find,
                .findNext,
                .findPrevious,
                .moveLeft,
                .moveRight,
                .moveUp,
                .moveDown,
                .moveBackward,
                .moveForward,
                .moveLeftAndModifySelection,
                .moveRightAndModifySelection,
                .moveUpAndModifySelection,
                .moveDownAndModifySelection,
                .moveBackwardAndModifySelection,
                .moveForwardAndModifySelection,
                .moveWordLeft,
                .moveWordRight,
                .moveWordLeftAndModifySelection,
                .moveWordRightAndModifySelection,
                .moveParagraphUp,
                .moveParagraphDown,
                .moveParagraphUpAndModifySelection,
                .moveParagraphDownAndModifySelection,
                .moveBackwardToParagraphStart,
                .moveForwardToParagraphEnd,
                .moveLineStart,
                .moveLineEnd,
                .moveLineStartAndModifySelection,
                .moveLineEndAndModifySelection,
                .moveDocumentStart,
                .moveDocumentEnd,
                .moveDocumentStartAndModifySelection,
                .moveDocumentEndAndModifySelection,
                .scrollDocumentStart,
                .scrollDocumentEnd,
                .scrollPageUp,
                .scrollPageDown,
                .movePageUp,
                .movePageDown,
                .movePageUpAndModifySelection,
                .movePageDownAndModifySelection,
                .moveToBeginningOfParagraph,
                .moveToEndOfParagraph,
                .moveToBeginningOfParagraphAndModifySelection,
                .moveToEndOfParagraphAndModifySelection,
                .insertNewline,
                .insertLineBreak,
                .insertNewlineIgnoringFieldEditor,
                .insertTab,
                .insertBacktab,
                .insertTabIgnoringFieldEditor,
                .insertSpace,
                .selectNextKeyView,
                .selectPreviousKeyView,
                .deleteBackward,
                .deleteForward,
                .deleteBackwardByDecomposingPreviousCharacter,
                .deleteWordBackward,
                .deleteWordForward,
                .deleteToBeginningOfLine,
                .deleteToEndOfLine,
                .deleteToEndOfParagraph,
                .transpose,
                .centerSelectionInVisibleArea,
                .cancelOperation,
                .complete,
                .yank
            ]
        )
        XCTAssertEqual(
            Policy.CollisionKind.allCases,
            [.applicationCommands, .nativeTextEditingReservations, .editorFocusReservation]
        )
    }

    func testDisjointApplicationBindingsResolveEveryLifecycleWithoutCollision() throws {
        let sharedChord = try chord(.character("k"), [.control])
        let bindings: [(Policy.LifecycleState, Policy.Command)] = [
            (.empty, .newComparison),
            (.loading, .openComparison),
            (.equal, .save),
            (.different, .nextDifference),
            (.failed, .refresh)
        ]
        let shortcuts = bindings.map { lifecycle, command in
            shortcut(command, sharedChord, states: [lifecycle])
        }
        let policy = try Policy(commandShortcuts: shortcuts.reversed())

        XCTAssertEqual(bindings.map(\.0), Policy.LifecycleState.allCases)
        XCTAssertNil(policy.collision(for: sharedChord))
        XCTAssertTrue(policy.collisions.isEmpty)
        for (lifecycle, command) in bindings {
            let resolution = try policy.resolve(
                sharedChord,
                in: context(lifecycle: lifecycle)
            )
            assertApplicationResolution(resolution, command: command)
            XCTAssertEqual(
                Set(resolution.matchedCommands),
                Set(bindings.map(\.1)),
                lifecycle.rawValue
            )
        }
    }

    func testDirtyAndSelectionFactsRemainIndependentAndCompose() throws {
        let saveChord = try chord(.character("s"), [.command])
        let copyChord = try chord(.special(.rightArrow), [.option])
        let combinedChord = try chord(.character("m"), [.command])
        let policy = try Policy(commandShortcuts: [
            shortcut(
                .save,
                saveChord,
                states: [.different],
                requiresDirty: true,
                allowsReadOnly: false
            ),
            shortcut(
                .copyToRight,
                copyChord,
                states: [.different],
                requiresSelection: true,
                allowsReadOnly: false
            ),
            shortcut(
                .autoMerge,
                combinedChord,
                states: [.different],
                requiresDirty: true,
                requiresSelection: true,
                allowsReadOnly: false
            )
        ])
        let cases:
            [(
                dirty: Bool,
                selected: Bool,
                save: Policy.DisabledReason?,
                copy: Policy.DisabledReason?,
                combined: Policy.DisabledReason?
            )] = [
                (
                    false, false, .commandConditions(.save, .dirty),
                    .commandConditions(.copyToRight, .selection),
                    .commandConditions(.autoMerge, .dirty)
                ),
                (
                    true, false, nil, .commandConditions(.copyToRight, .selection),
                    .commandConditions(.autoMerge, .selection)
                ),
                (
                    false, true, .commandConditions(.save, .dirty), nil,
                    .commandConditions(.autoMerge, .dirty)
                ),
                (true, true, nil, nil, nil)
            ]

        for testCase in cases {
            let state = context(
                lifecycle: .different,
                isDirty: testCase.dirty,
                hasSelection: testCase.selected
            )
            let save = try policy.resolve(saveChord, in: state)
            let copy = try policy.resolve(copyChord, in: state)
            let combined = try policy.resolve(combinedChord, in: state)
            XCTAssertEqual(save.disabledReason, testCase.save)
            XCTAssertEqual(copy.disabledReason, testCase.copy)
            XCTAssertEqual(combined.disabledReason, testCase.combined)
            XCTAssertEqual(save.applicationCommand, testCase.save == nil ? .save : nil)
            XCTAssertEqual(copy.applicationCommand, testCase.copy == nil ? .copyToRight : nil)
            XCTAssertEqual(
                combined.applicationCommand,
                testCase.combined == nil ? .autoMerge : nil
            )
        }

        let readOnly = context(
            lifecycle: .different,
            isDirty: true,
            hasSelection: true,
            isReadOnly: true
        )
        XCTAssertEqual(
            try policy.resolve(saveChord, in: readOnly).disabledReason,
            .commandConditions(.save, .readOnly)
        )
        XCTAssertEqual(
            try policy.resolve(copyChord, in: readOnly).disabledReason,
            .commandConditions(.copyToRight, .readOnly)
        )
        XCTAssertEqual(
            try policy.resolve(combinedChord, in: readOnly).disabledReason,
            .commandConditions(.autoMerge, .readOnly)
        )
    }

    func testEditorFocusRoutesDisjointNativeReservationsByApplicability() throws {
        let sharedChord = try chord(.character("x"), [.command])
        let policy = try Policy(
            commandShortcuts: [shortcut(.openComparison, sharedChord)],
            nativeTextEditingReservations: [
                reservation(.cut, sharedChord, applicability: .editable),
                reservation(.copy, sharedChord, applicability: .readOnly)
            ]
        )
        let collision = try XCTUnwrap(policy.collision(for: sharedChord))

        XCTAssertEqual(collision.kinds, [.editorFocusReservation])
        XCTAssertTrue(collision.isConditional)
        XCTAssertEqual(collision.commandShortcutCount, 1)
        XCTAssertEqual(collision.nativeReservationCount, 2)
        XCTAssertEqual(collision.nativeTextEditingCommands, [.copy, .cut])

        let noFocus = try policy.resolve(
            sharedChord,
            in: context(editorFocus: .none)
        )
        assertApplicationResolution(noFocus, command: .openComparison)
        XCTAssertEqual(noFocus.matchedNativeTextEditingCommands, [])

        let readOnly = try policy.resolve(
            sharedChord,
            in: context(isReadOnly: true, editorFocus: .readOnly)
        )
        assertNativeResolution(readOnly, command: .copy)

        let editable = try policy.resolve(
            sharedChord,
            in: context(editorFocus: .editable)
        )
        assertNativeResolution(editable, command: .cut)

        let readOnlyFocusInWritableDocument = try policy.resolve(
            sharedChord,
            in: context(isReadOnly: false, editorFocus: .readOnly)
        )
        assertNativeResolution(readOnlyFocusInWritableDocument, command: .copy)

        let editableFocusInReadOnlyDocument = try policy.resolve(
            sharedChord,
            in: context(isReadOnly: true, editorFocus: .editable)
        )
        assertNativeResolution(editableFocusInReadOnlyDocument, command: .cut)
    }

    func testNativeCollisionMetadataUsesOverlappingFocusApplicabilityOnly() throws {
        let disjointChord = try chord(.character("x"), [.command])
        let overlappingChord = try chord(.character("v"), [.command])
        let policy = try Policy(
            commandShortcuts: [],
            nativeTextEditingReservations: [
                reservation(.copy, disjointChord, applicability: .readOnly),
                reservation(.cut, disjointChord, applicability: .editable),
                reservation(.copy, overlappingChord),
                reservation(.paste, overlappingChord, applicability: .editable)
            ]
        )

        XCTAssertNil(policy.collision(for: disjointChord))
        let collision = try XCTUnwrap(policy.collision(for: overlappingChord))
        XCTAssertEqual(collision.kinds, [.nativeTextEditingReservations])
        XCTAssertEqual(collision.commands, [])
        XCTAssertEqual(collision.nativeTextEditingCommands, [.copy, .paste])
        XCTAssertEqual(collision.commandShortcutCount, 0)
        XCTAssertEqual(collision.nativeReservationCount, 2)
        XCTAssertFalse(collision.isConditional)
        XCTAssertEqual(policy.collisions, [collision])

        assertNativeResolution(
            try policy.resolve(overlappingChord, in: context(editorFocus: .readOnly)),
            command: .copy
        )
        let editable = try policy.resolve(
            overlappingChord,
            in: context(editorFocus: .editable)
        )
        XCTAssertEqual(editable.route, .blocked)
        XCTAssertEqual(editable.disabledReason, .nativeTextEditingCollision([.copy, .paste]))
    }

    func testNativeFocusOwnsChordWhileNoFocusExposesApplicationCollision() throws {
        let sharedChord = try chord(.character("k"), [.command])
        let policy = try Policy(
            commandShortcuts: [
                shortcut(.save, sharedChord, requiresDirty: true, allowsReadOnly: false),
                shortcut(.copyToRight, sharedChord, requiresSelection: true)
            ],
            nativeTextEditingReservations: [reservation(.copy, sharedChord)]
        )
        let collision = try XCTUnwrap(policy.collision(for: sharedChord))

        XCTAssertEqual(collision.kinds, [.applicationCommands, .editorFocusReservation])
        XCTAssertEqual(collision.commands, [.copyToRight, .save])
        XCTAssertEqual(collision.nativeTextEditingCommands, [.copy])
        XCTAssertEqual(collision.commandShortcutCount, 2)
        XCTAssertEqual(collision.nativeReservationCount, 1)
        XCTAssertFalse(collision.isConditional)

        let native = try policy.resolve(
            sharedChord,
            in: context(isDirty: true, hasSelection: true, editorFocus: .readOnly)
        )
        assertNativeResolution(native, command: .copy)
        XCTAssertEqual(native.matchedCommands, [.copyToRight, .save])
        XCTAssertEqual(native.collision, collision)

        let application = try policy.resolve(
            sharedChord,
            in: context(isDirty: true, hasSelection: true, editorFocus: .none)
        )
        XCTAssertEqual(application.route, .blocked)
        XCTAssertEqual(
            application.disabledReason,
            .applicationCollision([.copyToRight, .save])
        )
        XCTAssertEqual(application.matchedNativeTextEditingCommands, [])
        XCTAssertEqual(application.collision, collision)
    }

    func testDirtyAndReadOnlyConditionsMakeApplicationCollisionConditionalAtResolution() throws {
        let sharedChord = try chord(.character("r"), [.command])
        let policy = try Policy(commandShortcuts: [
            shortcut(.save, sharedChord, requiresDirty: true, allowsReadOnly: false),
            shortcut(.refresh, sharedChord)
        ])
        let collision = try XCTUnwrap(policy.collision(for: sharedChord))

        XCTAssertEqual(collision.kinds, [.applicationCommands])
        XCTAssertEqual(collision.commands, [.refresh, .save])
        XCTAssertEqual(collision.commandShortcutCount, 2)
        XCTAssertEqual(collision.nativeReservationCount, 0)
        XCTAssertFalse(collision.isConditional)

        let cases: [(dirty: Bool, readOnly: Bool, collides: Bool)] = [
            (false, false, false),
            (false, true, false),
            (true, true, false),
            (true, false, true)
        ]
        for testCase in cases {
            let resolution = try policy.resolve(
                sharedChord,
                in: context(isDirty: testCase.dirty, isReadOnly: testCase.readOnly)
            )
            if testCase.collides {
                XCTAssertEqual(resolution.route, .blocked)
                XCTAssertEqual(
                    resolution.disabledReason,
                    .applicationCollision([.refresh, .save])
                )
            } else {
                assertApplicationResolution(resolution, command: .refresh)
            }
            XCTAssertEqual(resolution.collision, collision)
        }
    }

    func testStandardNativeReservationsCoverMovementSelectionReturnTabDeleteAndControl() throws {
        let policy = try Policy(
            commandShortcuts: [],
            nativeTextEditingReservations: Policy.standardNativeTextEditingReservations
        )
        let cases:
            [(
                key: Policy.Key,
                modifiers: Set<Policy.Modifier>,
                focus: Policy.EditorFocus,
                command: Policy.NativeTextEditingCommand
            )] = [
                (.special(.leftArrow), [], .readOnly, .moveLeft),
                (.special(.rightArrow), [.shift], .editable, .moveRightAndModifySelection),
                (.special(.leftArrow), [.option], .readOnly, .moveWordLeft),
                (
                    .special(.downArrow),
                    [.option, .shift],
                    .editable,
                    .moveParagraphDownAndModifySelection
                ),
                (
                    .special(.upArrow),
                    [.command, .shift],
                    .readOnly,
                    .moveDocumentStartAndModifySelection
                ),
                (.special(.upArrow), [.control], .readOnly, .scrollPageUp),
                (
                    .special(.rightArrow),
                    [.control, .shift],
                    .editable,
                    .moveLineEndAndModifySelection
                ),
                (.special(.return), [], .editable, .insertNewline),
                (.special(.return), [.control], .editable, .insertLineBreak),
                (.special(.tab), [], .editable, .insertTab),
                (.special(.tab), [.shift], .editable, .insertBacktab),
                (.special(.tab), [.control], .readOnly, .selectNextKeyView),
                (.special(.backspace), [], .editable, .deleteBackward),
                (.special(.backspace), [.option], .editable, .deleteWordBackward),
                (.special(.delete), [], .editable, .deleteForward),
                (.character("a"), [.control], .readOnly, .moveToBeginningOfParagraph),
                (
                    .character("f"),
                    [.control, .shift],
                    .readOnly,
                    .moveForwardAndModifySelection
                ),
                (.character("d"), [.control], .editable, .deleteForward),
                (.special(.escape), [], .readOnly, .cancelOperation)
            ]

        for testCase in cases {
            let eventChord = try chord(testCase.key, testCase.modifiers)
            let resolution = try policy.resolve(
                eventChord,
                in: context(editorFocus: testCase.focus)
            )
            assertNativeResolution(
                resolution,
                command: testCase.command,
                message: eventChord.canonicalDescription
            )
        }

        for focus in [Policy.EditorFocus.none, .readOnly] {
            let returnResolution = try policy.resolve(
                chord(.special(.return)),
                in: context(editorFocus: focus)
            )
            XCTAssertEqual(returnResolution.route, .unhandled, focus.rawValue)
            XCTAssertEqual(returnResolution.disabledReason, .noBinding, focus.rawValue)
            XCTAssertEqual(returnResolution.matchedNativeTextEditingCommands, [], focus.rawValue)
        }
        let readOnlyDelete = try policy.resolve(
            chord(.special(.backspace)),
            in: context(isReadOnly: true, editorFocus: .readOnly)
        )
        XCTAssertEqual(readOnlyDelete.route, .unhandled)
        XCTAssertEqual(readOnlyDelete.disabledReason, .noBinding)
    }

    func testResolutionFiltersConditionsAndExactCommandStateBeforeReportingCollision() throws {
        let sharedChord = try chord(.character("j"), [.command])
        let policy = try Policy(commandShortcuts: [
            shortcut(.newComparison, sharedChord),
            shortcut(.openComparison, sharedChord, requiresSelection: true)
        ])
        let collision = try XCTUnwrap(policy.collision(for: sharedChord))
        XCTAssertEqual(collision.kinds, [.applicationCommands])
        XCTAssertEqual(collision.commands, [.newComparison, .openComparison])
        XCTAssertFalse(collision.isConditional)

        let noSelection = try policy.resolve(sharedChord, in: context(hasSelection: false))
        assertApplicationResolution(noSelection, command: .newComparison)
        XCTAssertEqual(noSelection.collision, collision)

        let bothApplicable = try policy.resolve(sharedChord, in: context(hasSelection: true))
        XCTAssertEqual(bothApplicable.route, .blocked)
        XCTAssertEqual(
            bothApplicable.availabilityReason,
            .disabled(.applicationCollision([.newComparison, .openComparison]))
        )
        XCTAssertEqual(bothApplicable.disabledReason, .applicationCollision([.newComparison, .openComparison]))
        XCTAssertFalse(bothApplicable.canExecute)

        let narrowed = try policy.resolve(
            sharedChord,
            in: context(
                hasSelection: true,
                enabledCommands: [.openComparison]
            )
        )
        assertApplicationResolution(narrowed, command: .openComparison)

        let unavailable = try policy.resolve(
            sharedChord,
            in: context(hasSelection: false, enabledCommands: [])
        )
        XCTAssertEqual(unavailable.route, .blocked)
        XCTAssertEqual(unavailable.disabledReason, .commandUnavailable(.newComparison))
    }

    func testRoutesAndDisabledReasonsCoverEveryOutcome() throws {
        let lifecycleChord = try chord(.character("1"), [.command])
        let dirtyChord = try chord(.character("2"), [.command])
        let selectionChord = try chord(.character("3"), [.command])
        let readOnlyChord = try chord(.character("4"), [.command])
        let unavailableChord = try chord(.character("5"), [.command])
        let applicationCollisionChord = try chord(.character("6"), [.command])
        let nativeCollisionChord = try chord(.character("7"), [.command])
        let unboundChord = try chord(.character("8"), [.command])
        let policy = try Policy(
            commandShortcuts: [
                shortcut(.newComparison, lifecycleChord, states: [.empty]),
                shortcut(.save, dirtyChord, requiresDirty: true),
                shortcut(.copyToRight, selectionChord, requiresSelection: true),
                shortcut(.undo, readOnlyChord, allowsReadOnly: false),
                shortcut(.redo, unavailableChord),
                shortcut(.newComparison, applicationCollisionChord),
                shortcut(.openComparison, applicationCollisionChord)
            ],
            nativeTextEditingReservations: [
                reservation(.copy, nativeCollisionChord),
                reservation(.selectAll, nativeCollisionChord)
            ]
        )
        let disabledCases:
            [(
                chord: Policy.Chord,
                context: Policy.Context,
                route: Policy.Route,
                reason: Policy.DisabledReason
            )] = [
                (
                    lifecycleChord,
                    context(lifecycle: .different),
                    .blocked,
                    .commandConditions(.newComparison, .lifecycle)
                ),
                (
                    dirtyChord,
                    context(isDirty: false),
                    .blocked,
                    .commandConditions(.save, .dirty)
                ),
                (
                    selectionChord,
                    context(hasSelection: false),
                    .blocked,
                    .commandConditions(.copyToRight, .selection)
                ),
                (
                    readOnlyChord,
                    context(isReadOnly: true),
                    .blocked,
                    .commandConditions(.undo, .readOnly)
                ),
                (
                    unavailableChord,
                    context(enabledCommands: []),
                    .blocked,
                    .commandUnavailable(.redo)
                ),
                (
                    applicationCollisionChord,
                    context(),
                    .blocked,
                    .applicationCollision([.newComparison, .openComparison])
                ),
                (
                    nativeCollisionChord,
                    context(editorFocus: .readOnly),
                    .blocked,
                    .nativeTextEditingCollision([.copy, .selectAll])
                ),
                (unboundChord, context(), .unhandled, .noBinding)
            ]

        for testCase in disabledCases {
            let resolution = try policy.resolve(testCase.chord, in: testCase.context)
            XCTAssertEqual(resolution.route, testCase.route, testCase.chord.canonicalDescription)
            XCTAssertEqual(
                resolution.availabilityReason,
                .disabled(testCase.reason),
                testCase.chord.canonicalDescription
            )
            XCTAssertEqual(
                resolution.availability,
                .disabled(testCase.reason),
                testCase.chord.canonicalDescription
            )
            XCTAssertEqual(
                resolution.disabledReason,
                testCase.reason,
                testCase.chord.canonicalDescription
            )
            XCTAssertNil(resolution.enabledReason, testCase.chord.canonicalDescription)
            XCTAssertFalse(resolution.isEnabled, testCase.chord.canonicalDescription)
            XCTAssertFalse(resolution.canExecute, testCase.chord.canonicalDescription)
            XCTAssertNil(resolution.applicationCommand, testCase.chord.canonicalDescription)
        }
    }

    func testConstructionAndResolveAllAreDeterministicAcrossInputOrder() throws {
        let optionLeft = try chord(.special(.leftArrow), [.option])
        let commands = [
            shortcut(.options, try chord(.character("?"), [.command])),
            shortcut(.previousDifference, optionLeft),
            shortcut(.openComparison, try chord(.character("O"), [.command])),
            shortcut(.nextDifference, optionLeft),
            shortcut(.newComparison, try chord(.character("n"), [.command]))
        ]
        let reservations = [
            reservation(.moveWordLeft, optionLeft),
            reservation(
                .selectAll,
                try chord(.character("a"), [.control]),
                applicability: .readOnlyAndEditable
            )
        ]
        let commandOrders = [
            commands,
            Array(commands.reversed()),
            Array(commands[2...] + commands[..<2])
        ]
        let reservationOrders = [reservations, Array(reservations.reversed()), reservations]
        let policies = try zip(commandOrders, reservationOrders).map {
            try Policy(commandShortcuts: $0.0, nativeTextEditingReservations: $0.1)
        }
        let baseline = try XCTUnwrap(policies.first)
        let baselineResolutions = try baseline.resolveAll(in: context(editorFocus: .editable))

        XCTAssertEqual(Set(policies).count, 1)
        for policy in policies {
            XCTAssertEqual(policy, baseline)
            XCTAssertEqual(policy.commandShortcuts, baseline.commandShortcuts)
            XCTAssertEqual(
                policy.nativeTextEditingReservations,
                baseline.nativeTextEditingReservations
            )
            XCTAssertEqual(policy.collisions, baseline.collisions)
            XCTAssertEqual(
                try policy.resolveAll(in: context(editorFocus: .editable)),
                baselineResolutions
            )
        }
        XCTAssertEqual(
            baselineResolutions.map(\.chord.canonicalDescription),
            ["command+n", "command+o", "control+a", "option+leftArrow", "command+shift+/"]
        )
        XCTAssertEqual(
            baseline.collision(for: optionLeft)?.kinds,
            [.applicationCommands, .editorFocusReservation]
        )
    }

    func testMalformedKeysLimitsCountsAndLifecycleBindingsAreRejected() throws {
        assertPolicyError(.invalidCharacterKey(" ")) {
            try Policy.Chord(.character(" "), modifiers: [.command])
        }
        assertPolicyError(.invalidCharacterKey("é")) {
            try Policy.Chord(.character("é"), modifiers: [.command])
        }
        for invalidFunctionKey in [0, 25, Int.min, Int.max] {
            assertPolicyError(.invalidFunctionKey(invalidFunctionKey)) {
                try Policy.Chord(.function(invalidFunctionKey))
            }
        }
        for modifiers in [Set<Policy.Modifier>(), [.shift], [.function], [.shift, .function]] {
            assertPolicyError(.printableKeyRequiresCommandModifier) {
                try Policy.Chord(.character("a"), modifiers: modifiers)
            }
        }
        _ = try chord(.function(1))
        _ = try chord(.function(24))

        let invalidLimits: [(Policy.Limit, Int, Policy.Limits)] = [
            (.commandShortcuts, -1, limits(.commandShortcuts, -1)),
            (
                .commandShortcuts,
                Policy.Limits.hardMaximumCommandShortcutCount + 1,
                limits(
                    .commandShortcuts,
                    Policy.Limits.hardMaximumCommandShortcutCount + 1
                )
            ),
            (.nativeReservations, -1, limits(.nativeReservations, -1)),
            (
                .nativeReservations,
                Policy.Limits.hardMaximumNativeReservationCount + 1,
                limits(
                    .nativeReservations,
                    Policy.Limits.hardMaximumNativeReservationCount + 1
                )
            ),
            (.collisions, -1, limits(.collisions, -1)),
            (
                .collisions,
                Policy.Limits.hardMaximumCollisionCount + 1,
                limits(.collisions, Policy.Limits.hardMaximumCollisionCount + 1)
            ),
            (.work, 0, limits(.work, 0)),
            (
                .work,
                Policy.Limits.hardMaximumWork + 1,
                limits(.work, Policy.Limits.hardMaximumWork + 1)
            ),
            (.cancellationCheckInterval, 0, limits(.cancellationCheckInterval, 0)),
            (
                .cancellationCheckInterval,
                Policy.Limits.hardMaximumCancellationCheckInterval + 1,
                limits(
                    .cancellationCheckInterval,
                    Policy.Limits.hardMaximumCancellationCheckInterval + 1
                )
            )
        ]
        for (limit, value, malformed) in invalidLimits {
            assertPolicyError(.invalidLimit(limit, value: value)) {
                try Policy(commandShortcuts: [], limits: malformed)
            }
        }

        let binding = shortcut(
            .newComparison,
            try chord(.character("n"), [.command])
        )
        assertPolicyError(.tooManyCommandShortcuts(maximum: 0)) {
            try Policy(
                commandShortcuts: [binding],
                limits: Policy.Limits(maximumCommandShortcutCount: 0)
            )
        }
        let native = reservation(
            .copy,
            try chord(.character("c"), [.command])
        )
        assertPolicyError(.tooManyNativeReservations(maximum: 0)) {
            try Policy(
                commandShortcuts: [],
                nativeTextEditingReservations: [native],
                limits: Policy.Limits(maximumNativeReservationCount: 0)
            )
        }
        assertPolicyError(.emptyLifecycleStates(.newComparison)) {
            try Policy(commandShortcuts: [shortcut(.newComparison, binding.chord, states: [])])
        }
        assertPolicyError(.tooManyCollisions(maximum: 0)) {
            try Policy(
                commandShortcuts: [
                    binding,
                    shortcut(.openComparison, binding.chord)
                ],
                limits: Policy.Limits(maximumCollisionCount: 0)
            )
        }
    }

    func testWorkBudgetsAndCancellationBoundConstructionAndResolution() throws {
        let binding = shortcut(
            .newComparison,
            try chord(.character("n"), [.command])
        )
        let exactConstructionLimits = Policy.Limits(
            maximumWork: 8,
            cancellationCheckInterval: Policy.Limits.hardMaximumCancellationCheckInterval
        )
        _ = try Policy(commandShortcuts: [binding], limits: exactConstructionLimits)
        assertPolicyError(.workLimitExceeded(maximum: 7)) {
            try Policy(
                commandShortcuts: [binding],
                limits: Policy.Limits(
                    maximumWork: 7,
                    cancellationCheckInterval: Policy.Limits.hardMaximumCancellationCheckInterval
                )
            )
        }

        let successfulProbe = KeyboardShortcutCancellationProbe()
        _ = try Policy(
            commandShortcuts: [binding],
            limits: Policy.Limits(maximumWork: 8, cancellationCheckInterval: 2),
            cancellationCheck: { () throws(PolicyError) in try successfulProbe.check() }
        )
        XCTAssertEqual(successfulProbe.count, 6)

        let entryProbe = KeyboardShortcutCancellationProbe(cancelOnCheck: 1)
        assertPolicyError(.cancelled) {
            try Policy(
                commandShortcuts: [binding],
                cancellationCheck: { () throws(PolicyError) in try entryProbe.check() }
            )
        }
        XCTAssertEqual(entryProbe.count, 1)

        let workProbe = KeyboardShortcutCancellationProbe(cancelOnCheck: 2)
        assertPolicyError(.cancelled) {
            try Policy(
                commandShortcuts: [binding],
                limits: Policy.Limits(cancellationCheckInterval: 1),
                cancellationCheck: { () throws(PolicyError) in try workProbe.check() }
            )
        }
        XCTAssertEqual(workProbe.count, 2)

        let policy = try Policy(commandShortcuts: [binding])
        let resolveProbe = KeyboardShortcutCancellationProbe(cancelOnCheck: 1)
        assertPolicyError(.cancelled) {
            try policy.resolve(
                binding.chord,
                in: context(),
                cancellationCheck: { () throws(PolicyError) in try resolveProbe.check() }
            )
        }
        let resolveAllProbe = KeyboardShortcutCancellationProbe(cancelOnCheck: 2)
        assertPolicyError(.cancelled) {
            try policy.resolveAll(
                in: context(),
                cancellationCheck: { () throws(PolicyError) in try resolveAllProbe.check() }
            )
        }
        XCTAssertEqual(resolveAllProbe.count, 2)

        assertPolicyError(.cancelled) {
            try Policy.makeUnfinishedAudit(
                cancellationCheck: { () throws(PolicyError) in throw .cancelled }
            )
        }
    }

    private func chord(
        _ key: Policy.Key,
        _ modifiers: Set<Policy.Modifier> = []
    ) throws -> Policy.Chord {
        try Policy.Chord(key, modifiers: modifiers)
    }

    private func applicationBinding(
        _ command: Policy.Command,
        _ chord: String,
        _ states: Set<Policy.LifecycleState>,
        dirty: Bool = false,
        selection: Bool = false,
        readOnly: Bool = true
    ) -> ApplicationBinding {
        ApplicationBinding(
            command: command,
            chord: chord,
            states: states,
            requiresDirty: dirty,
            requiresSelection: selection,
            allowsReadOnly: readOnly
        )
    }

    private func nativeBinding(
        _ command: Policy.NativeTextEditingCommand,
        _ chord: String,
        _ applicability: Policy.NativeTextEditingApplicability
    ) -> NativeBinding {
        NativeBinding(command: command, chord: chord, applicability: applicability)
    }

    private func collision(
        _ chord: String,
        _ command: Policy.Command,
        _ nativeCommand: Policy.NativeTextEditingCommand
    ) -> CollisionInventoryItem {
        CollisionInventoryItem(
            chord: chord,
            kinds: [.editorFocusReservation],
            commands: [command],
            nativeCommands: [nativeCommand],
            commandShortcutCount: 1,
            nativeReservationCount: 1,
            isConditional: true
        )
    }

    private func shortcut(
        _ command: Policy.Command,
        _ chord: Policy.Chord,
        states: Set<Policy.LifecycleState> = Set(Policy.LifecycleState.allCases),
        requiresDirty: Bool = false,
        requiresSelection: Bool = false,
        allowsReadOnly: Bool = true
    ) -> Policy.CommandShortcut {
        Policy.CommandShortcut(
            command: command,
            chord: chord,
            enabledLifecycleStates: states,
            requiresDirty: requiresDirty,
            requiresSelection: requiresSelection,
            allowsReadOnly: allowsReadOnly
        )
    }

    private func reservation(
        _ command: Policy.NativeTextEditingCommand,
        _ chord: Policy.Chord,
        applicability: Policy.NativeTextEditingApplicability = .readOnlyAndEditable
    ) -> Policy.NativeTextEditingReservation {
        Policy.NativeTextEditingReservation(
            command: command,
            chord: chord,
            applicability: applicability
        )
    }

    private func context(
        lifecycle: Policy.LifecycleState = .equal,
        isDirty: Bool = false,
        hasSelection: Bool = false,
        isReadOnly: Bool = false,
        editorFocus: Policy.EditorFocus = .none,
        enabledCommands: Set<Policy.Command>? = nil
    ) -> Policy.Context {
        Policy.Context(
            lifecycle: lifecycle,
            isDirty: isDirty,
            hasSelection: hasSelection,
            isReadOnly: isReadOnly,
            editorFocus: editorFocus,
            enabledCommands: enabledCommands
        )
    }

    private func limits(_ limit: Policy.Limit, _ value: Int) -> Policy.Limits {
        Policy.Limits(
            maximumCommandShortcutCount: limit == .commandShortcuts ? value : 1_024,
            maximumNativeReservationCount: limit == .nativeReservations ? value : 128,
            maximumCollisionCount: limit == .collisions ? value : 1_024,
            maximumWork: limit == .work ? value : 65_536,
            cancellationCheckInterval: limit == .cancellationCheckInterval ? value : 64
        )
    }

    private func assertApplicationResolution(
        _ resolution: Policy.Resolution,
        command: Policy.Command,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            resolution.route,
            .applicationCommand(command),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            resolution.availabilityReason,
            .enabled(.applicationCommand(command)),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(resolution.availability, .enabled, message, file: file, line: line)
        XCTAssertEqual(
            resolution.enabledReason,
            .applicationCommand(command),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(resolution.applicationCommand, command, message, file: file, line: line)
        XCTAssertNil(resolution.disabledReason, message, file: file, line: line)
        XCTAssertTrue(resolution.isEnabled, message, file: file, line: line)
        XCTAssertTrue(resolution.canExecute, message, file: file, line: line)
    }

    private func assertNativeResolution(
        _ resolution: Policy.Resolution,
        command: Policy.NativeTextEditingCommand,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            resolution.route,
            .nativeTextEditing(command),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            resolution.availabilityReason,
            .enabled(.nativeTextEditing(command)),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(resolution.availability, .enabled, message, file: file, line: line)
        XCTAssertEqual(
            resolution.enabledReason,
            .nativeTextEditing(command),
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            resolution.matchedNativeTextEditingCommands,
            [command],
            message,
            file: file,
            line: line
        )
        XCTAssertNil(resolution.applicationCommand, message, file: file, line: line)
        XCTAssertNil(resolution.disabledReason, message, file: file, line: line)
        XCTAssertTrue(resolution.isEnabled, message, file: file, line: line)
    }

    private func assertPolicyError<T>(
        _ expected: PolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? PolicyError, expected, file: file, line: line)
        }
    }
}

private final class KeyboardShortcutCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelOnCheck: Int?
    private var checkCount = 0

    init(cancelOnCheck: Int? = nil) {
        self.cancelOnCheck = cancelOnCheck
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return checkCount
    }

    func check() throws(KeyboardShortcutPolicyError) {
        lock.lock()
        checkCount += 1
        let shouldCancel = checkCount == cancelOnCheck
        lock.unlock()
        if shouldCancel { throw .cancelled }
    }
}
