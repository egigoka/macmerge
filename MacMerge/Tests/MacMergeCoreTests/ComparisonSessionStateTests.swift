import Foundation
import XCTest

@testable import MacMergeCore

final class ComparisonSessionStateTests: XCTestCase {
    func testRoundTripUsesDeterministicCompactJSON() throws {
        let state = try makeState(
            left: .scratchpad("left\ntext"),
            right: .file(URL(fileURLWithPath: "/tmp/right file.txt")),
            leftReadOnly: true,
            rightReadOnly: true,
            selectedRow: 7,
            activeSide: .right,
            splitOrientation: .horizontal,
            splitFraction: 0.25,
            locationPaneVisible: false,
            locationPaneWidth: 120
        )

        let first = try state.encodedData()
        let second = try state.encodedData()

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.contains(0x0A))
        XCTAssertEqual(try ComparisonSessionState.decode(from: first), state)
        XCTAssertTrue(state.leftReadOnly)
        XCTAssertTrue(state.rightReadOnly)
        requireSendable(state)
        requireSendable(ComparisonSessionStateError.invalidSelectedRow(-1))
    }

    func testEncodedDataMatchesExactCompactSortedWireJSON() throws {
        let state = try makeState(
            left: .scratchpad("left/notes"),
            right: .file(URL(fileURLWithPath: "/tmp/right file.txt")),
            selectedRow: nil,
            activeSide: .right,
            splitOrientation: .horizontal,
            splitFraction: 0.25,
            locationPaneVisible: false,
            locationPaneWidth: 120
        )

        XCTAssertEqual(
            String(decoding: try state.encodedData(), as: UTF8.self),
            #"{"activeSide":"right","left":{"kind":"scratchpad","text":"left/notes"},"locationPaneVisible":false,"locationPaneWidth":120,"right":{"kind":"file","url":"file:///tmp/right%20file.txt"},"schemaVersion":1,"splitFraction":0.25,"splitOrientation":"horizontal","windowFrame":{"height":600,"width":800,"x":10,"y":20}}"#
        )
    }

    func testEncodedDataWithSelectionMatchesExactCompactSortedWireJSON() throws {
        let state = try makeState(selectedRow: 7)

        XCTAssertEqual(
            String(decoding: try state.encodedData(), as: UTF8.self),
            #"{"activeSide":"left","left":{"kind":"scratchpad","text":"left"},"locationPaneVisible":true,"locationPaneWidth":92,"right":{"kind":"scratchpad","text":"right"},"schemaVersion":1,"selectedRow":7,"splitFraction":0.5,"splitOrientation":"vertical","windowFrame":{"height":600,"width":800,"x":10,"y":20}}"#
        )
    }

    func testReadOnlySidesRoundTripAndDefaultToEditableForExistingPayloads() throws {
        let state = try makeState(leftReadOnly: true, rightReadOnly: true)

        XCTAssertEqual(
            String(decoding: try state.encodedData(), as: UTF8.self),
            #"{"activeSide":"left","left":{"kind":"scratchpad","text":"left"},"leftReadOnly":true,"locationPaneVisible":true,"locationPaneWidth":92,"right":{"kind":"scratchpad","text":"right"},"rightReadOnly":true,"schemaVersion":1,"splitFraction":0.5,"splitOrientation":"vertical","windowFrame":{"height":600,"width":800,"x":10,"y":20}}"#
        )
        XCTAssertEqual(try ComparisonSessionState.decode(from: state.encodedData()), state)

        let existing = try ComparisonSessionState.decode(from: Data(stateJSON().utf8))
        XCTAssertFalse(existing.leftReadOnly)
        XCTAssertFalse(existing.rightReadOnly)
        XCTAssertEqual(try existing.encodedData(), try makeState().encodedData())
    }

    func testDecodePreservesIndependentExplicitReadOnlyValues() throws {
        let leftReadOnly = try ComparisonSessionState.decode(
            from: Data(
                stateJSON(addingRootMember: #""leftReadOnly":true,"rightReadOnly":false"#).utf8
            ))
        XCTAssertTrue(leftReadOnly.leftReadOnly)
        XCTAssertFalse(leftReadOnly.rightReadOnly)

        let rightReadOnly = try ComparisonSessionState.decode(
            from: Data(
                stateJSON(addingRootMember: #""leftReadOnly":false,"rightReadOnly":true"#).utf8
            ))
        XCTAssertFalse(rightReadOnly.leftReadOnly)
        XCTAssertTrue(rightReadOnly.rightReadOnly)
    }

    func testFileEncodingsRoundTripIndependentlyAndRejectInvalidPlacement() throws {
        let state = try makeState(
            left: .file(URL(fileURLWithPath: "/tmp/left.txt")),
            right: .file(URL(fileURLWithPath: "/tmp/right.txt")),
            leftEncoding: .iso2022JP,
            rightEncoding: .windows1254
        )
        let data = try state.encodedData()
        XCTAssertTrue(data.contains(Data(#""leftEncoding":"iso2022JP""#.utf8)))
        XCTAssertTrue(data.contains(Data(#""rightEncoding":"windows1254""#.utf8)))
        XCTAssertEqual(try ComparisonSessionState.decode(from: data), state)

        XCTAssertThrowsError(try makeState(leftEncoding: .utf8)) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .invalidFileEncodingSide(.left)
            )
        }
        for member in [
            #""leftEncoding":null"#,
            #""leftEncoding":"unknown""#,
            #""rightEncoding":null"#,
            #""rightEncoding":17"#
        ] {
            XCTAssertThrowsError(
                try ComparisonSessionState.decode(
                    from: Data(stateJSON(addingRootMember: member).utf8)
                )
            ) { XCTAssertTrue($0 is DecodingError) }
        }
    }

    func testScratchpadUTF8BoundaryIsEnforcedForConstructionAndDecoding() throws {
        let exact = String(
            repeating: "é",
            count: ComparisonSessionState.maximumScratchpadUTF8Bytes / 2
        )
        let state = try makeState(left: .scratchpad(exact), right: .scratchpad(exact))
        XCTAssertEqual(try ComparisonSessionState.decode(from: state.encodedData()), state)

        let oversizedCount = ComparisonSessionState.maximumScratchpadUTF8Bytes + 1
        XCTAssertThrowsError(try makeState(left: .scratchpad(exact + "x"))) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .scratchpadTooLarge(
                    side: .left,
                    maximumBytes: ComparisonSessionState.maximumScratchpadUTF8Bytes
                )
            )
        }

        let oversizedJSON = scratchpadJSON(leftTextByteCount: oversizedCount)
        XCTAssertThrowsError(try ComparisonSessionState.decode(from: oversizedJSON)) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .scratchpadTooLarge(
                    side: .left,
                    maximumBytes: ComparisonSessionState.maximumScratchpadUTF8Bytes
                )
            )
        }
    }

    func testJSONPreflightEnforcesGlobalValueCountBoundary() throws {
        let allowedValue = arrayOfNullArrays(elementCounts: [58, 58, 58, 58])
        let rejectedValue = arrayOfNullArrays(elementCounts: [58, 58, 58, 59])

        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(addingRootMember: #""padding":\#(allowedValue)"#).utf8
                )),
            try makeState()
        )
        assertSessionError(
            .tooManyJSONValues(maximumValues: ComparisonSessionState.maximumJSONValueCount),
            json: stateJSON(addingRootMember: #""padding":\#(rejectedValue)"#)
        )
    }

    func testDecodeCapsHostileUnknownFieldBeforeJSONParsing() throws {
        let state = try makeState()
        var padded = try state.encodedData()
        XCTAssertEqual(padded.removeLast(), 0x7D)
        let fieldPrefix = Data(",\"padding\":\"".utf8)
        let fieldSuffix = Data("\"}".utf8)
        padded.append(fieldPrefix)
        padded.append(
            Data(
                repeating: 0x78,
                count: ComparisonSessionState.maximumEncodedBytes
                    - padded.count
                    - fieldSuffix.count
            ))
        padded.append(fieldSuffix)

        XCTAssertEqual(padded.count, ComparisonSessionState.maximumEncodedBytes)
        XCTAssertThrowsError(try ComparisonSessionState.decode(from: padded)) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .jsonStringTooLarge(
                    maximumBytes: ComparisonSessionState.maximumJSONStringUTF8Bytes
                )
            )
        }

        padded = try state.encodedData()
        padded.append(
            Data(
                repeating: 0x20,
                count: ComparisonSessionState.maximumEncodedBytes - padded.count
            ))
        XCTAssertEqual(try ComparisonSessionState.decode(from: padded), state)

        padded.append(0xFF)
        XCTAssertThrowsError(try ComparisonSessionState.decode(from: padded)) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .encodedDataTooLarge(maximumBytes: ComparisonSessionState.maximumEncodedBytes)
            )
        }
    }

    func testEncodingRejectsExpansionBeyondEncodedBound() throws {
        let escapable = String(
            repeating: "\"",
            count: ComparisonSessionState.maximumScratchpadUTF8Bytes
        )
        let state = try makeState(left: .scratchpad(escapable), right: .scratchpad(escapable))

        XCTAssertThrowsError(try state.encodedData()) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .encodedDataTooLarge(maximumBytes: ComparisonSessionState.maximumEncodedBytes)
            )
        }
    }

    func testDirectJSONEncoderAndDecoderCannotBypassBoundedWireAPI() throws {
        let state = try makeState(
            left: .scratchpad(
                String(
                    repeating: "\"",
                    count: ComparisonSessionState.maximumScratchpadUTF8Bytes
                ))
        )
        XCTAssertNil(try directlyEncodeIfSupported(state))

        var padded = try makeState().encodedData()
        padded.append(
            Data(
                repeating: 0x20,
                count: ComparisonSessionState.maximumEncodedBytes - padded.count + 1
            ))
        XCTAssertNil(try directlyDecodeIfSupported(ComparisonSessionState.self, from: padded))
        XCTAssertThrowsError(try ComparisonSessionState.decode(from: padded)) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .encodedDataTooLarge(maximumBytes: ComparisonSessionState.maximumEncodedBytes)
            )
        }

        let oversizedScratchpad = scratchpadJSON(
            leftTextByteCount: ComparisonSessionState.maximumScratchpadUTF8Bytes + 1
        )
        XCTAssertNil(
            try directlyDecodeIfSupported(
                ComparisonSessionState.self,
                from: oversizedScratchpad
            ))
        XCTAssertThrowsError(try ComparisonSessionState.decode(from: oversizedScratchpad)) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .scratchpadTooLarge(
                    side: .left,
                    maximumBytes: ComparisonSessionState.maximumScratchpadUTF8Bytes
                )
            )
        }
    }

    func testControlCharacterScratchpadUsesBoundedEscapedSizePreflight() throws {
        let shortEscapes = "\u{8}\u{9}\u{A}\u{C}\u{D}"
        let longEscapes = "\u{0}\u{1}\u{7}\u{B}\u{1F}"
        XCTAssertEqual(
            try ComparisonSessionState.escapedJSONStringContentByteCount(
                shortEscapes + longEscapes,
                maximumBytes: 40
            ),
            40
        )
        XCTAssertThrowsError(
            try ComparisonSessionState.escapedJSONStringContentByteCount(
                shortEscapes + longEscapes,
                maximumBytes: 39
            )
        ) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .encodedDataTooLarge(maximumBytes: ComparisonSessionState.maximumEncodedBytes)
            )
        }

        let maximumControlText = String(
            repeating: "\u{0}",
            count: ComparisonSessionState.maximumScratchpadUTF8Bytes
        )
        let state = try makeState(left: .scratchpad(maximumControlText))
        XCTAssertThrowsError(try state.encodedData()) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .encodedDataTooLarge(maximumBytes: ComparisonSessionState.maximumEncodedBytes)
            )
        }
    }

    func testEscapedJSONStringContentByteCountCoversEncoderScalarRepresentatives() throws {
        let samples: [(UInt32, Int)] = [
            (0x00, 6), (0x01, 6), (0x07, 6),
            (0x08, 2), (0x09, 2), (0x0A, 2), (0x0B, 6), (0x0C, 2), (0x0D, 2),
            (0x1F, 6), (0x20, 1), (0x21, 1), (0x22, 2), (0x2F, 1), (0x5C, 2),
            (0x7E, 1), (0x7F, 1), (0x80, 2), (0x7FF, 2), (0x800, 3),
            (0x2028, 3), (0x2029, 3), (0xFFFF, 3), (0x10000, 4), (0x10FFFF, 4)
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        for (scalarValue, expectedByteCount) in samples {
            let value = String(try XCTUnwrap(UnicodeScalar(scalarValue)))
            let estimatedByteCount =
                try ComparisonSessionState
                .escapedJSONStringContentByteCount(value, maximumBytes: expectedByteCount)
            let encodedContentByteCount = try encoder.encode(value).count - 2

            XCTAssertEqual(estimatedByteCount, expectedByteCount, "U+\(String(scalarValue, radix: 16))")
            XCTAssertEqual(
                estimatedByteCount,
                encodedContentByteCount,
                "U+\(String(scalarValue, radix: 16))"
            )
        }
    }

    func testMaximumDELScalarScratchpadUsesExactEncodedSizePreflight() throws {
        let maximumText = String(
            repeating: "\u{7F}",
            count: ComparisonSessionState.maximumScratchpadUTF8Bytes
        )
        let state = try makeState(
            left: .scratchpad(maximumText),
            right: .scratchpad(maximumText)
        )

        XCTAssertEqual(try ComparisonSessionState.decode(from: state.encodedData()), state)
    }

    func testJSONPreflightRejectsDuplicateDecodedKeys() {
        for json in [
            stateJSON(addingRootMember: #""schemaVersion":2"#),
            stateJSON(left: #"{"kind":"scratchpad","text":"left","t\u0065xt":"other"}"#)
        ] {
            XCTAssertThrowsError(try ComparisonSessionState.decode(from: Data(json.utf8))) {
                XCTAssertTrue($0 is DecodingError)
            }
        }
    }

    func testJSONPreflightBoundsNumberTokens() throws {
        let allowed = String(repeating: "1", count: ComparisonSessionState.maximumJSONNumberBytes)
        let rejected = allowed + "1"

        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(addingRootMember: #""padding":\#(allowed)"#).utf8
                )),
            try makeState()
        )
        assertSessionError(
            .jsonNumberTooLarge(maximumBytes: ComparisonSessionState.maximumJSONNumberBytes),
            json: stateJSON(addingRootMember: #""padding":\#(rejected)"#)
        )
    }

    func testJSONPreflightEnforcesNestingDepthBoundary() throws {
        let maximumDepth = ComparisonSessionState.maximumJSONNestingDepth
        let allowedValue = nestedArray(depth: maximumDepth - 1)
        let rejectedValue = nestedArray(depth: maximumDepth)

        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(addingRootMember: #""padding":\#(allowedValue)"#).utf8
                )),
            try makeState()
        )
        assertSessionError(
            .jsonNestingTooDeep(maximumDepth: maximumDepth),
            json: stateJSON(addingRootMember: #""padding":\#(rejectedValue)"#)
        )
    }

    func testJSONPreflightEnforcesArrayAndObjectElementBoundaries() throws {
        let maximumElements = ComparisonSessionState.maximumJSONContainerElements
        let allowedValues = Array(repeating: "null", count: maximumElements).joined(separator: ",")
        let rejectedValues = allowedValues + ",null"
        let allowedMembers = (0..<maximumElements).map { #""k\#($0)":null"# }.joined(separator: ",")
        let rejectedMembers = allowedMembers + #", "overflow":null"#
        let expected = try makeState()

        for value in ["[\(allowedValues)]", "{\(allowedMembers)}"] {
            XCTAssertEqual(
                try ComparisonSessionState.decode(
                    from: Data(
                        stateJSON(addingRootMember: #""padding":\#(value)"#).utf8
                    )),
                expected
            )
        }
        for value in ["[\(rejectedValues)]", "{\(rejectedMembers)}"] {
            assertSessionError(
                .jsonContainerTooLarge(maximumElements: maximumElements),
                json: stateJSON(addingRootMember: #""padding":\#(value)"#)
            )
        }
    }

    func testJSONPreflightEnforcesKeyAndStringUTF8ByteBoundaries() throws {
        let maximumKeyBytes = ComparisonSessionState.maximumJSONKeyUTF8Bytes
        let maximumStringBytes = ComparisonSessionState.maximumJSONStringUTF8Bytes
        let allowedKey = String(repeating: "é", count: maximumKeyBytes / 2)
        let rejectedKey = allowedKey + "é"
        let allowedString = String(repeating: "é", count: maximumStringBytes / 2)
        let rejectedString = allowedString + "é"
        let expected = try makeState()

        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(addingRootMember: #""\#(allowedKey)":null"#).utf8
                )),
            expected
        )
        assertSessionError(
            .jsonStringTooLarge(maximumBytes: maximumKeyBytes),
            json: stateJSON(addingRootMember: #""\#(rejectedKey)":null"#)
        )

        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(addingRootMember: #""padding":"\#(allowedString)""#).utf8
                )),
            expected
        )
        assertSessionError(
            .jsonStringTooLarge(maximumBytes: maximumStringBytes),
            json: stateJSON(addingRootMember: #""padding":"\#(rejectedString)""#)
        )
    }

    func testJSONPreflightEnforcesEscapedStringBoundaries() throws {
        let maximumKeyBytes = ComparisonSessionState.maximumJSONKeyUTF8Bytes
        let maximumStringBytes = ComparisonSessionState.maximumJSONStringUTF8Bytes
        let escapedKeyUnit = #"\u00e9"#
        let escapedStringUnit = #"\ud83d\ude00"#
        let allowedKey = String(repeating: escapedKeyUnit, count: maximumKeyBytes / 2)
        let rejectedKey = allowedKey + escapedKeyUnit
        let allowedString = String(repeating: escapedStringUnit, count: maximumStringBytes / 4)
        let rejectedString = allowedString + escapedStringUnit
        let expected = try makeState()

        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(addingRootMember: #""\#(allowedKey)":null"#).utf8
                )),
            expected
        )
        assertSessionError(
            .jsonStringTooLarge(maximumBytes: maximumKeyBytes),
            json: stateJSON(addingRootMember: #""\#(rejectedKey)":null"#)
        )

        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(addingRootMember: #""padding":"\#(allowedString)""#).utf8
                )),
            expected
        )
        assertSessionError(
            .jsonStringTooLarge(maximumBytes: maximumStringBytes),
            json: stateJSON(addingRootMember: #""padding":"\#(rejectedString)""#)
        )
    }

    func testJSONPreflightDecodesEscapedKeysAndShortEscapes() throws {
        let expected = try makeState()
        let escapedLeft = #"{"kind":"scratchpad","t\u0065xt":"line\nfeed\tand\\slash"}"#
        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(left: escapedLeft).utf8
                )
            ).left,
            .scratchpad("line\nfeed\tand\\slash")
        )

        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(addingRootMember: #""p\u0061dding":"\b\f\n\r\t\/\\\"""#).utf8
                )),
            expected
        )
    }

    func testJSONPreflightRejectsMalformedEscapes() {
        let malformedValues = [
            #""\x""#,
            #""\u12G4""#,
            #""\ud83d""#,
            #""\ud83d\u0041""#,
            #""\ude00""#
        ]

        for value in malformedValues {
            XCTAssertThrowsError(
                try ComparisonSessionState.decode(
                    from: Data(
                        stateJSON(addingRootMember: #""padding":\#(value)"#).utf8
                    ))
            ) {
                XCTAssertTrue($0 is DecodingError)
            }
        }
    }

    func testDecodeRejectsInvalidSchemaAndSideIdentities() throws {
        assertSessionError(.unsupportedSchemaVersion(2), json: stateJSON(schemaVersion: "2"))
        assertSessionError(
            .unsupportedSchemaVersion(2),
            json: #"{"schemaVersion":2,"futureShape":{"value":true}}"#
        )
        let nesting =
            String(repeating: "[", count: 24)
            + "true"
            + String(repeating: "]", count: 24)
        assertSessionError(
            .unsupportedSchemaVersion(2),
            json: #"{"schemaVersion":2,"futureShape":\#(nesting)}"#
        )
        assertSessionError(
            .unsupportedSchemaVersion(2),
            json: #"{"futureNumber":1.25e+999,"schemaVersion":2}"#
        )
        XCTAssertThrowsError(
            try ComparisonSessionState.decode(
                from: Data(#"{"schemaVersion":2.5}"#.utf8)
            )
        ) {
            XCTAssertTrue($0 is DecodingError)
        }
        XCTAssertThrowsError(
            try ComparisonSessionState.decode(
                from: Data(#"{"schemaVersion":2,"futureShape":true"#.utf8)
            )
        ) {
            XCTAssertTrue($0 is DecodingError)
        }
        let excessiveNesting =
            String(repeating: "[", count: 80)
            + "true"
            + String(repeating: "]", count: 80)
        assertSessionError(
            .schemaProbeLimitExceeded,
            json: #"{"futureShape":\#(excessiveNesting),"schemaVersion":2}"#
        )
        assertSessionError(
            .invalidSideIdentity,
            json: stateJSON(left: #"{"kind":"other","text":"left"}"#)
        )
        assertSessionError(
            .invalidSideIdentity,
            json: stateJSON(
                left: #"{"kind":"file","url":"file:///tmp/left","text":"left"}"#
            )
        )
        assertSessionError(
            .invalidFileURL(side: .left, value: "https://example.com/left"),
            json: stateJSON(left: #"{"kind":"file","url":"https://example.com/left"}"#)
        )
    }

    func testDecodeRejectsInvalidLayoutValues() throws {
        assertSessionError(.invalidSelectedRow(-1), json: stateJSON(selectedRow: "-1"))
        assertSessionError(
            .nonPositiveWindowSize(width: 0, height: 600),
            json: stateJSON(windowFrame: #"{"x":10,"y":20,"width":0,"height":600}"#)
        )
        assertSessionError(.invalidSplitFraction(1), json: stateJSON(splitFraction: "1"))
        assertSessionError(
            .invalidLocationPaneWidth(241),
            json: stateJSON(locationPaneWidth: "241")
        )
        assertSessionError(
            .nonFiniteWindowFrame,
            json: stateJSON(
                windowFrame: #"{"x":1.7976931348623157e308,"y":20,"width":1.7976931348623157e308,"height":600}"#
            )
        )
    }

    func testDecodeRejectsDecodedNULAndOversizedFilePaths() {
        assertSessionError(
            .invalidFileURL(side: .left, value: "file:///tmp/a%00b"),
            json: stateJSON(left: #"{"kind":"file","url":"file:///tmp/a%00b"}"#)
        )

        let path =
            "/"
            + String(
                repeating: "x",
                count: ComparisonSessionState.maximumFilePathUTF8Bytes
            )
        let value = "file://" + path
        assertSessionError(
            .invalidFileURL(side: .left, value: value),
            json: stateJSON(left: #"{"kind":"file","url":"\#(value)"}"#)
        )
    }

    func testDuplicatePanesRejectSameDotAndSymlinkFileIdentities() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ComparisonSessionStateTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let target = root.appendingPathComponent("target.txt")
        let symlink = root.appendingPathComponent("target-link.txt")
        try Data().write(to: target)
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: target)
        let dotted = URL(fileURLWithPath: root.path + "/missing/../target.txt")

        for right in [target, dotted, symlink] {
            XCTAssertThrowsError(try makeState(left: .file(target), right: .file(right))) {
                XCTAssertEqual(
                    $0 as? ComparisonSessionStateError,
                    .duplicateFileURL(target.path)
                )
            }
        }
    }

    func testDuplicatePanesPreferExistingResourceIdentifiers() {
        let firstIdentifier = NSString(string: "first")
        let secondIdentifier = NSString(string: "second")

        XCTAssertTrue(
            ComparisonSessionState.fileIdentitiesMatch(
                lhsIdentifier: firstIdentifier,
                rhsIdentifier: secondIdentifier,
                canonicalPathsMatch: true
            ))
        XCTAssertTrue(
            ComparisonSessionState.fileIdentitiesMatch(
                lhsIdentifier: firstIdentifier,
                rhsIdentifier: firstIdentifier,
                canonicalPathsMatch: false
            ))
        XCTAssertTrue(
            ComparisonSessionState.fileIdentitiesMatch(
                lhsIdentifier: nil,
                rhsIdentifier: nil,
                canonicalPathsMatch: true
            ))
    }

    func testSelectedRowMaximumIsInclusiveForConstructionAndDecoding() throws {
        let maximum = ComparisonSessionState.maximumSelectedRow
        XCTAssertEqual(try makeState(selectedRow: maximum).selectedRow, maximum)
        XCTAssertEqual(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(selectedRow: String(maximum)).utf8
                )
            ).selectedRow,
            maximum
        )

        let rejected = maximum + 1
        XCTAssertThrowsError(try makeState(selectedRow: rejected)) {
            XCTAssertEqual($0 as? ComparisonSessionStateError, .invalidSelectedRow(rejected))
        }
        assertSessionError(
            .invalidSelectedRow(rejected),
            json: stateJSON(selectedRow: String(rejected))
        )
    }

    func testWindowFramePracticalSizeBoundariesAreInclusive() throws {
        let minimumWidth = ComparisonSessionState.minimumWindowWidth
        let minimumHeight = ComparisonSessionState.minimumWindowHeight
        let maximumWidth = ComparisonSessionState.maximumWindowWidth
        let maximumHeight = ComparisonSessionState.maximumWindowHeight

        for (width, height) in [
            (minimumWidth, minimumHeight),
            (maximumWidth, maximumHeight)
        ] {
            let frame = try ComparisonSessionState.WindowFrame(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
            XCTAssertEqual(frame.width, width)
            XCTAssertEqual(frame.height, height)
        }

        for (width, height) in [
            (minimumWidth.nextDown, minimumHeight),
            (minimumWidth, minimumHeight.nextDown),
            (maximumWidth.nextUp, maximumHeight),
            (maximumWidth, maximumHeight.nextUp)
        ] {
            XCTAssertThrowsError(
                try ComparisonSessionState.WindowFrame(
                    x: 0,
                    y: 0,
                    width: width,
                    height: height
                )
            ) {
                XCTAssertEqual(
                    $0 as? ComparisonSessionStateError,
                    .windowSizeOutOfBounds(width: width, height: height)
                )
            }
        }
    }

    func testNaNAssociatedErrorsHaveReflexiveEquality() {
        let errors: [ComparisonSessionStateError] = [
            .nonPositiveWindowSize(width: .nan, height: .nan),
            .windowSizeOutOfBounds(width: .nan, height: .nan),
            .invalidSplitFraction(.nan),
            .invalidLocationPaneWidth(.nan)
        ]

        for error in errors {
            XCTAssertEqual(error, error)
        }
    }

    func testLayoutBoundariesAreInclusiveOnlyWhereDocumented() throws {
        for width in [
            ComparisonSessionState.minimumLocationPaneWidth,
            ComparisonSessionState.maximumLocationPaneWidth
        ] {
            XCTAssertEqual(try makeState(locationPaneWidth: width).locationPaneWidth, width)
        }

        for fraction in [Double.leastNonzeroMagnitude, 1.nextDown] {
            XCTAssertEqual(try makeState(splitFraction: fraction).splitFraction, fraction)
        }
        XCTAssertThrowsError(try makeState(splitFraction: 0)) {
            XCTAssertEqual($0 as? ComparisonSessionStateError, .invalidSplitFraction(0))
        }
    }

    func testDecodeRejectsInvalidCodableEnumsAndTypes() {
        XCTAssertThrowsError(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(activeSide: #""middle""#).utf8
                ))
        ) { XCTAssertTrue($0 is DecodingError) }
        XCTAssertThrowsError(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(splitOrientation: #""diagonal""#).utf8
                ))
        ) { XCTAssertTrue($0 is DecodingError) }
        XCTAssertThrowsError(
            try ComparisonSessionState.decode(
                from: Data(
                    stateJSON(locationPaneVisible: #""yes""#).utf8
                ))
        ) { XCTAssertTrue($0 is DecodingError) }
        for member in [
            #""leftReadOnly":null"#,
            #""leftReadOnly":"yes""#,
            #""rightReadOnly":null"#,
            #""rightReadOnly":"yes""#
        ] {
            XCTAssertThrowsError(
                try ComparisonSessionState.decode(
                    from: Data(stateJSON(addingRootMember: member).utf8)
                )
            ) { XCTAssertTrue($0 is DecodingError) }
        }
    }

    private func makeState(
        left: ComparisonSessionState.SideIdentity = .scratchpad("left"),
        right: ComparisonSessionState.SideIdentity = .scratchpad("right"),
        leftReadOnly: Bool = false,
        rightReadOnly: Bool = false,
        leftEncoding: ComparisonSessionState.FileEncoding? = nil,
        rightEncoding: ComparisonSessionState.FileEncoding? = nil,
        selectedRow: Int? = nil,
        activeSide: ComparisonSessionState.Side = .left,
        splitOrientation: ComparisonSessionState.SplitOrientation = .vertical,
        splitFraction: Double = 0.5,
        locationPaneVisible: Bool = true,
        locationPaneWidth: Double = 92
    ) throws -> ComparisonSessionState {
        try ComparisonSessionState(
            left: left,
            right: right,
            leftReadOnly: leftReadOnly,
            rightReadOnly: rightReadOnly,
            leftEncoding: leftEncoding,
            rightEncoding: rightEncoding,
            selectedRow: selectedRow,
            activeSide: activeSide,
            windowFrame: ComparisonSessionState.WindowFrame(
                x: 10,
                y: 20,
                width: 800,
                height: 600
            ),
            splitOrientation: splitOrientation,
            splitFraction: splitFraction,
            locationPaneVisible: locationPaneVisible,
            locationPaneWidth: locationPaneWidth
        )
    }

    private func stateJSON(
        schemaVersion: String = "1",
        left: String = #"{"kind":"scratchpad","text":"left"}"#,
        selectedRow: String = "null",
        activeSide: String = #""left""#,
        windowFrame: String = #"{"x":10,"y":20,"width":800,"height":600}"#,
        splitOrientation: String = #""vertical""#,
        splitFraction: String = "0.5",
        locationPaneVisible: String = "true",
        locationPaneWidth: String = "92"
    ) -> String {
        """
        {"schemaVersion":\(schemaVersion),"left":\(left),"right":{"kind":"scratchpad","text":"right"},"selectedRow":\(selectedRow),"activeSide":\(activeSide),"windowFrame":\(windowFrame),"splitOrientation":\(splitOrientation),"splitFraction":\(splitFraction),"locationPaneVisible":\(locationPaneVisible),"locationPaneWidth":\(locationPaneWidth)}
        """
    }

    private func scratchpadJSON(leftTextByteCount: Int) -> Data {
        var data = Data(#"{"schemaVersion":1,"left":{"kind":"scratchpad","text":""#.utf8)
        data.append(Data(repeating: 0x78, count: leftTextByteCount))
        data.append(
            Data(
                #""},"right":{"kind":"scratchpad","text":"right"},"selectedRow":null,"activeSide":"left","windowFrame":{"x":10,"y":20,"width":800,"height":600},"splitOrientation":"vertical","splitFraction":0.5,"locationPaneVisible":true,"locationPaneWidth":92}"#
                    .utf8))
        return data
    }

    private func stateJSON(addingRootMember member: String) -> String {
        var json = stateJSON()
        json.removeLast()
        return json + ",\(member)}"
    }

    private func nestedArray(depth: Int) -> String {
        String(repeating: "[", count: depth)
            + "null"
            + String(repeating: "]", count: depth)
    }

    private func arrayOfNullArrays(elementCounts: [Int]) -> String {
        "["
            + elementCounts.map {
                "[" + Array(repeating: "null", count: $0).joined(separator: ",") + "]"
            }.joined(separator: ",")
            + "]"
    }

    private func assertSessionError(
        _ expected: ComparisonSessionStateError,
        json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ComparisonSessionState.decode(from: Data(json.utf8)),
            file: file,
            line: line
        ) {
            XCTAssertEqual($0 as? ComparisonSessionStateError, expected, file: file, line: line)
        }
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }

    private func directlyEncodeIfSupported<T>(_ value: T) throws -> Data? {
        guard let encodable = value as? any Encodable else { return nil }
        return try JSONEncoder().encode(encodable)
    }

    private func directlyDecodeIfSupported<T>(
        _ type: T.Type,
        from data: Data
    ) throws -> T? {
        guard let decodableType = type as? any Decodable.Type else { return nil }
        return try JSONDecoder().decode(decodableType, from: data) as? T
    }
}
