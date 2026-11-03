import Foundation
import XCTest

@testable import MacMergeCore

final class MiddlePaneReadOnlyStateTests: XCTestCase {
    func testFlagsDefaultToEditableAndStayIndependent() throws {
        let state = try makeState()
        for side in MiddlePaneReadOnlyState.Side.allCases {
            XCTAssertFalse(state.isReadOnly(side))
            XCTAssertTrue(state.isEditable(side))
        }

        let leftLocked = try makeState(leftReadOnly: true)
        XCTAssertTrue(leftLocked.isReadOnly(.left))
        XCTAssertFalse(leftLocked.isReadOnly(.middle))
        XCTAssertFalse(leftLocked.isReadOnly(.right))

        let middleLocked = try leftLocked.settingReadOnly(true, for: .middle)
        XCTAssertTrue(middleLocked.isReadOnly(.left))
        XCTAssertTrue(middleLocked.isReadOnly(.middle))
        XCTAssertFalse(middleLocked.isReadOnly(.right))

        let unlocked = try middleLocked.settingReadOnly(false, for: .left)
        XCTAssertFalse(unlocked.isReadOnly(.left))
        XCTAssertTrue(unlocked.isReadOnly(.middle))
        XCTAssertEqual(unlocked[.left], .scratchpad("left"))
        requireSendable(unlocked)
    }

    func testCanMergeIntoFollowsEditableOnly() throws {
        for readOnly in [false, true] {
            let state = try makeState(
                leftReadOnly: readOnly,
                middleReadOnly: !readOnly,
                rightReadOnly: readOnly
            )
            XCTAssertEqual(state.canMergeInto(.left), !readOnly)
            XCTAssertEqual(state.canMergeInto(.middle), readOnly)
            XCTAssertEqual(state.canMergeInto(.right), !readOnly)
        }
    }

    func testCanSaveMatrixIsLoadedEditableDirty() throws {
        let state = try makeState(middleReadOnly: true)
        let editableSides: [MiddlePaneReadOnlyState.Side] = [.left, .right]
        let lockedSides: [MiddlePaneReadOnlyState.Side] = [.middle]

        for loaded in [false, true] {
            for dirty in [false, true] {
                let runtime = MiddlePaneReadOnlyState.PaneRuntime(
                    isLoaded: loaded,
                    isDirty: dirty
                )
                for side in editableSides {
                    XCTAssertEqual(
                        state.canSave(side, runtime: runtime),
                        loaded && dirty,
                        "side=\(side) loaded=\(loaded) dirty=\(dirty)"
                    )
                }
                for side in lockedSides {
                    XCTAssertFalse(state.canSave(side, runtime: runtime))
                }
            }
        }
    }

    func testEligibilityAggregatesThreeSidesAndSubscript() throws {
        let state = try makeState(middleReadOnly: true)
        let eligibility = state.eligibility(
            left: .init(isLoaded: true, isDirty: true),
            middle: .init(isLoaded: true, isDirty: true),
            right: .init(isLoaded: true, isDirty: false)
        )

        XCTAssertTrue(eligibility.canMergeIntoLeft)
        XCTAssertFalse(eligibility.canMergeIntoMiddle)
        XCTAssertTrue(eligibility.canMergeIntoRight)
        XCTAssertTrue(eligibility.canSaveLeft)
        XCTAssertFalse(eligibility.canSaveMiddle)
        XCTAssertFalse(eligibility.canSaveRight)
        XCTAssertEqual(eligibility[.left].0, true)
        XCTAssertEqual(eligibility[.middle].0, false)
        XCTAssertEqual(eligibility[.middle].1, false)
        XCTAssertEqual(eligibility[.right].1, false)
    }

    func testSaveAsMiddleRejectsPaneAliasesButIgnoresScratchpads() throws {
        let left = URL(fileURLWithPath: "/tmp/mpr-left.txt")
        let middle = URL(fileURLWithPath: "/tmp/mpr-middle.txt")
        let right = URL(fileURLWithPath: "/tmp/mpr-right.txt")
        let state = try makeState(
            left: .file(left),
            middle: .scratchpad("mid"),
            right: .file(right)
        )

        XCTAssertThrowsError(try state.validatedSaveAsMiddleDestination(left)) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .destinationAliasesPane(.left)
            )
        }
        XCTAssertThrowsError(try state.validatedSaveAsMiddleDestination(right)) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .destinationAliasesPane(.right)
            )
        }

        let fileMiddle = try makeState(
            left: .scratchpad("l"),
            middle: .file(middle),
            right: .scratchpad("r"),
            middleReadOnly: true
        )
        XCTAssertThrowsError(try fileMiddle.validatedSaveAsMiddleDestination(middle)) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .destinationAliasesPane(.middle)
            )
        }
        // Read-only does not block Save As: destination receives a copy.
        let fresh = URL(fileURLWithPath: "/tmp/mpr-fresh-\(UUID().uuidString).txt")
        XCTAssertEqual(
            try fileMiddle.validatedSaveAsMiddleDestination(fresh),
            fresh.standardizedFileURL
        )
        XCTAssertEqual(
            try state.validatedSaveAsMiddleDestination(fresh),
            fresh.standardizedFileURL
        )
    }

    func testSaveAsMiddleRejectsNonCanonicalDirectoryAndOversizedPaths() throws {
        let state = try makeState()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        XCTAssertThrowsError(try state.validatedSaveAsMiddleDestination(directory)) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .invalidSaveDestination(directory.absoluteString)
            )
        }

        let dotDot = URL(fileURLWithPath: "/tmp/../tmp/mpr-dotdot.txt")
        XCTAssertNotEqual(dotDot, dotDot.standardizedFileURL)
        XCTAssertThrowsError(try state.validatedSaveAsMiddleDestination(dotDot)) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .invalidSaveDestination(dotDot.absoluteString)
            )
        }

        let web = try XCTUnwrap(URL(string: "https://example.com/middle.txt"))
        XCTAssertThrowsError(try state.validatedSaveAsMiddleDestination(web)) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .invalidSaveDestination(web.absoluteString)
            )
        }

        let oversized = URL(
            fileURLWithPath: "/" + String(
                repeating: "x",
                count: MiddlePaneReadOnlyState.maximumFilePathUTF8Bytes + 1
            )
        )
        XCTAssertThrowsError(try state.validatedSaveAsMiddleDestination(oversized)) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .pathTooLarge(
                    maximumBytes: MiddlePaneReadOnlyState.maximumFilePathUTF8Bytes
                )
            )
        }
    }

    func testRoundTripIsDeterministicCompactAndSorted() throws {
        let state = try makeState(
            middle: .file(URL(fileURLWithPath: "/tmp/mid file.txt")),
            leftReadOnly: true,
            middleReadOnly: true,
            rightReadOnly: true
        )
        let first = try state.encodedData()
        XCTAssertEqual(first, try state.encodedData())
        XCTAssertFalse(first.contains(0x0A))
        XCTAssertEqual(try MiddlePaneReadOnlyState.decode(from: first), state)
    }

    func testEncodedDataMatchesExactCompactSortedWireJSON() throws {
        XCTAssertEqual(
            String(decoding: try makeState().encodedData(), as: UTF8.self),
            #"{"left":{"kind":"scratchpad","text":"left"},"middle":{"kind":"scratchpad","text":"middle"},"right":{"kind":"scratchpad","text":"right"},"schemaVersion":1,"selectedSide":"middle"}"#
        )

        let locked = try makeState(leftReadOnly: true, rightReadOnly: true)
        let json = String(decoding: try locked.encodedData(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""leftReadOnly":true"#))
        XCTAssertTrue(json.contains(#""rightReadOnly":true"#))
        XCTAssertFalse(json.contains("middleReadOnly"))
        XCTAssertEqual(try MiddlePaneReadOnlyState.decode(from: locked.encodedData()), locked)
    }

    func testMissingReadOnlyMembersDefaultToEditable() throws {
        let decoded = try MiddlePaneReadOnlyState.decode(
            from: Data(stateJSON().utf8)
        )
        XCTAssertFalse(decoded.leftReadOnly)
        XCTAssertFalse(decoded.middleReadOnly)
        XCTAssertFalse(decoded.rightReadOnly)
        XCTAssertEqual(decoded, try makeState())

        let leftLocked = try MiddlePaneReadOnlyState.decode(
            from: Data(stateJSON(addingRootMember: #""leftReadOnly":true"#).utf8)
        )
        XCTAssertTrue(leftLocked.leftReadOnly)
        XCTAssertFalse(leftLocked.middleReadOnly)
        XCTAssertFalse(leftLocked.rightReadOnly)
    }

    func testNullAndWrongTypeReadOnlyMembersFailClosed() throws {
        for member in [
            #""leftReadOnly":null"#,
            #""leftReadOnly":"yes""#,
            #""leftReadOnly":1"#,
            #""middleReadOnly":null"#,
            #""middleReadOnly":"yes""#,
            #""rightReadOnly":null"#,
            #""rightReadOnly":17"#
        ] {
            XCTAssertThrowsError(
                try MiddlePaneReadOnlyState.decode(
                    from: Data(stateJSON(addingRootMember: member).utf8)
                )
            ) { XCTAssertTrue($0 is DecodingError, "member=\(member)") }
        }
    }

    func testSelectedSideIsRequired() throws {
        let missing = stateJSON().replacingOccurrences(
            of: #","selectedSide":"middle"}"#,
            with: "}"
        )
        XCTAssertThrowsError(
            try MiddlePaneReadOnlyState.decode(from: Data(missing.utf8))
        ) { XCTAssertTrue($0 is DecodingError) }

        for replacement in [
            #""selectedSide":null"#,
            #""selectedSide":"diagonal""#,
            #""selectedSide":17"#
        ] {
            let json = stateJSON().replacingOccurrences(
                of: #""selectedSide":"middle""#,
                with: replacement
            )
            XCTAssertThrowsError(
                try MiddlePaneReadOnlyState.decode(from: Data(json.utf8))
            ) { XCTAssertTrue($0 is DecodingError, "value=\(replacement)") }
        }

        XCTAssertEqual(
            try MiddlePaneReadOnlyState.decode(from: Data(stateJSON().utf8)),
            try makeState()
        )
    }

    func testScratchpadUTF8BoundaryIsEnforcedForConstructionAndDecoding() throws {
        let exact = String(
            repeating: "é",
            count: MiddlePaneReadOnlyState.maximumScratchpadUTF8Bytes / 2
        )
        let state = try makeState(middle: .scratchpad(exact))
        XCTAssertEqual(try MiddlePaneReadOnlyState.decode(from: state.encodedData()), state)

        XCTAssertThrowsError(try makeState(middle: .scratchpad(exact + "x"))) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .scratchpadTooLarge(
                    side: .middle,
                    maximumBytes: MiddlePaneReadOnlyState.maximumScratchpadUTF8Bytes
                )
            )
        }
        XCTAssertThrowsError(
            try MiddlePaneReadOnlyState.decode(
                from: scratchpadJSON(
                    middleTextByteCount: MiddlePaneReadOnlyState.maximumScratchpadUTF8Bytes + 1
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .scratchpadTooLarge(
                    side: .middle,
                    maximumBytes: MiddlePaneReadOnlyState.maximumScratchpadUTF8Bytes
                )
            )
        }
    }

    func testBoundsRejectOversizedPathsDuplicatesAndEncodedExpansion() throws {
        let path = "/" + String(
            repeating: "x",
            count: MiddlePaneReadOnlyState.maximumFilePathUTF8Bytes + 1
        )
        let value = "file://" + path
        XCTAssertThrowsError(
            try MiddlePaneReadOnlyState.decode(
                from: Data(
                    stateJSON(
                        middle: #"{"kind":"file","url":"\#(value)"}"#
                    ).utf8
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .invalidFileURL(side: .middle, value: value)
            )
        }

        let duplicate = URL(fileURLWithPath: "/tmp/mpr-duplicate.txt")
        let fileDuplicate = MiddlePaneReadOnlyState.SideIdentity.file(duplicate)
        for sides in [
            (fileDuplicate, MiddlePaneReadOnlyState.SideIdentity.scratchpad("m"), fileDuplicate),
            (fileDuplicate, fileDuplicate, MiddlePaneReadOnlyState.SideIdentity.scratchpad("r")),
            (MiddlePaneReadOnlyState.SideIdentity.scratchpad("l"), fileDuplicate, fileDuplicate)
        ] {
            XCTAssertThrowsError(try makeState(left: sides.0, middle: sides.1, right: sides.2)) {
                XCTAssertEqual(
                    $0 as? MiddlePaneReadOnlyStateError,
                    .duplicateFileURL(duplicate.resolvingSymlinksInPath().standardizedFileURL.path)
                )
            }
        }

        let escapable = String(
            repeating: "\"",
            count: MiddlePaneReadOnlyState.maximumScratchpadUTF8Bytes
        )
        let expanded = try makeState(
            left: .scratchpad(escapable),
            middle: .scratchpad(escapable),
            right: .scratchpad(escapable)
        )
        XCTAssertThrowsError(try expanded.encodedData()) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .encodedDataTooLarge(
                    maximumBytes: MiddlePaneReadOnlyState.maximumEncodedBytes
                )
            )
        }
    }

    func testDecodeRejectsInvalidSchemaAndSideIdentities() throws {
        XCTAssertThrowsError(
            try MiddlePaneReadOnlyState.decode(
                from: Data(stateJSON(schemaVersion: "2").utf8)
            )
        ) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .unsupportedSchemaVersion(2)
            )
        }
        XCTAssertThrowsError(
            try MiddlePaneReadOnlyState.decode(
                from: Data(
                    stateJSON(middle: #"{"kind":"other","text":"middle"}"#).utf8
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .invalidSideIdentity
            )
        }
        XCTAssertThrowsError(
            try MiddlePaneReadOnlyState.decode(
                from: Data(
                    stateJSON(middle: #"{"kind":"file","url":"https://example.com/m"}"#).utf8
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? MiddlePaneReadOnlyStateError,
                .invalidFileURL(side: .middle, value: "https://example.com/m")
            )
        }
    }

    private func makeState(
        left: MiddlePaneReadOnlyState.SideIdentity = .scratchpad("left"),
        middle: MiddlePaneReadOnlyState.SideIdentity = .scratchpad("middle"),
        right: MiddlePaneReadOnlyState.SideIdentity = .scratchpad("right"),
        leftReadOnly: Bool = false,
        middleReadOnly: Bool = false,
        rightReadOnly: Bool = false
    ) throws -> MiddlePaneReadOnlyState {
        try MiddlePaneReadOnlyState(
            left: left,
            middle: middle,
            right: right,
            leftReadOnly: leftReadOnly,
            middleReadOnly: middleReadOnly,
            rightReadOnly: rightReadOnly
        )
    }

    private func stateJSON(
        schemaVersion: String = "1",
        middle: String = #"{"kind":"scratchpad","text":"middle"}"#
    ) -> String {
        "{\"schemaVersion\":"
            + schemaVersion
            + ",\"left\":{\"kind\":\"scratchpad\",\"text\":\"left\"},\"middle\":"
            + middle
            + ",\"right\":{\"kind\":\"scratchpad\",\"text\":\"right\"},\"selectedSide\":\"middle\"}"
    }

    private func stateJSON(addingRootMember member: String) -> String {
        var json = stateJSON()
        json.removeLast()
        return json + ",\(member)}"
    }

    private func scratchpadJSON(middleTextByteCount: Int) -> Data {
        var data = Data(
            #"{"schemaVersion":1,"left":{"kind":"scratchpad","text":"left"},"middle":{"kind":"scratchpad","text":""#.utf8
        )
        data.append(Data(repeating: 0x78, count: middleTextByteCount))
        data.append(
            Data(#""},"right":{"kind":"scratchpad","text":"right"},"selectedSide":"middle"}"#.utf8)
        )
        return data
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
