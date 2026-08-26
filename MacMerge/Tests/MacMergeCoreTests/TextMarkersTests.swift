import Foundation
import XCTest

@testable import MacMergeCore

final class TextMarkersTests: XCTestCase {
    func testNamedMarkerCollectionLifecycleAndCanonicalNameUniqueness() throws {
        let first = try NamedTextMarker(
            id: "first",
            name: "Caf\u{E9}",
            literal: "alpha",
            colorToken: TextMarkerColorToken(rawValue: "search/primary")
        )
        let second = try NamedTextMarker(
            id: "second",
            name: "Second marker",
            regularExpression: #"b.ta"#,
            caseSensitive: false,
            wholeWord: true,
            colorToken: TextMarkerColorToken(rawValue: "search.secondary"),
            scope: .lineRange(2...3)
        )
        var markers = try TextMarkers()

        XCTAssertTrue(try markers.add(first))
        XCTAssertEqual(markers.activeMarkerID, first.id)
        XCTAssertEqual(markers.activeMarker, first)
        XCTAssertEqual(Array(markers), [first])
        XCTAssertTrue(try markers.add(second))
        XCTAssertEqual(markers.marker(id: second.id), second)

        assertMarkerError(.duplicateIdentifier(first.id)) {
            _ = try markers.add(first)
        }
        let canonicallyEquivalentName = try NamedTextMarker(
            id: "equivalent",
            name: "Cafe\u{301}",
            literal: "other"
        )
        assertMarkerError(.duplicateName(canonicallyEquivalentName.name)) {
            _ = try markers.add(canonicallyEquivalentName)
        }

        let updated = try NamedTextMarker(
            id: second.id,
            name: "Updated marker",
            literal: "beta",
            scope: .utf16Range(NSRange(location: 1, length: 4))
        )
        try markers.update(updated)
        XCTAssertEqual(markers.marker(id: second.id), updated)
        assertMarkerError(.unknownMarker("missing")) {
            try markers.update(
                NamedTextMarker(id: "missing", name: "Missing", literal: "missing")
            )
        }

        try markers.activate(id: second.id)
        markers.setRepeatDirection(.backward)
        XCTAssertEqual(markers.activeMarker, updated)
        XCTAssertEqual(markers.repeatDirection, .backward)
        assertMarkerError(.unknownMarker("missing")) {
            try markers.activate(id: "missing")
        }

        XCTAssertTrue(markers.remove(id: second.id))
        XCTAssertEqual(markers.activeMarkerID, first.id)
        XCTAssertFalse(markers.remove(id: second.id))
        XCTAssertTrue(markers.remove(id: first.id))
        XCTAssertNil(markers.activeMarkerID)
        markers.deactivate()
        XCTAssertNil(markers.activeMarker)
    }

    func testCollectionCapAndFailedDuplicateUpdateAreAtomic() throws {
        let markerValues = try (0..<TextMarkers.maximumMarkerCount).map { index in
            try NamedTextMarker(id: "marker-\(index)", name: "Marker \(index)", literal: "x")
        }
        var capped = try TextMarkers(
            markers: markerValues,
            activeMarkerID: markerValues.last?.id
        )
        let beforeAdd = capped

        assertMarkerError(.tooManyMarkers(maximumMarkers: TextMarkers.maximumMarkerCount)) {
            _ = try capped.add(
                NamedTextMarker(id: "overflow", name: "Overflow", literal: "x")
            )
        }
        XCTAssertEqual(capped, beforeAdd)

        var two = try TextMarkers(markers: Array(markerValues.prefix(2)))
        let beforeUpdate = two
        let duplicateName = try NamedTextMarker(
            id: markerValues[0].id,
            name: markerValues[1].name,
            literal: "changed"
        )
        assertMarkerError(.duplicateName(markerValues[1].name)) {
            try two.update(duplicateName)
        }
        XCTAssertEqual(two, beforeUpdate)
    }

    func testNamedMarkerValidationUsesUTF8AndUTF16ExactBounds() throws {
        let exactIdentifier = String(repeating: "i", count: NamedTextMarker.maximumIdentifierUTF8Bytes)
        let exactName = String(repeating: "\u{E9}", count: NamedTextMarker.maximumNameUTF8Bytes / 2)
        let exactColor = String(repeating: "c", count: TextMarkerColorToken.maximumUTF8Bytes)
        let exactPattern = String(repeating: "p", count: NamedTextMarker.maximumPatternUTF16Length)
        let exact = try NamedTextMarker(
            id: exactIdentifier,
            name: exactName,
            literal: exactPattern,
            colorToken: TextMarkerColorToken(rawValue: exactColor)
        )

        XCTAssertEqual(exact.id.utf8.count, NamedTextMarker.maximumIdentifierUTF8Bytes)
        XCTAssertEqual(exact.name.utf8.count, NamedTextMarker.maximumNameUTF8Bytes)
        XCTAssertEqual(exact.colorToken.rawValue.utf8.count, TextMarkerColorToken.maximumUTF8Bytes)
        XCTAssertEqual(exact.query.pattern.text.utf16.count, NamedTextMarker.maximumPatternUTF16Length)

        for invalidIdentifier in ["", " leading", "trailing ", "two words", "line\nbreak"] {
            assertMarkerError(.invalidIdentifier(invalidIdentifier)) {
                _ = try NamedTextMarker(id: invalidIdentifier, name: "Valid", literal: "x")
            }
        }
        for invalidName in ["", " leading", "trailing ", "line\nbreak"] {
            assertMarkerError(.invalidName(invalidName)) {
                _ = try NamedTextMarker(id: "valid", name: invalidName, literal: "x")
            }
        }
        for invalidColor in ["", "has space", "bad#token", "line\nbreak"] {
            assertMarkerError(.invalidColorToken(invalidColor)) {
                _ = try TextMarkerColorToken(rawValue: invalidColor)
            }
        }

        assertMarkerError(
            .identifierTooLarge(maximumUTF8Bytes: NamedTextMarker.maximumIdentifierUTF8Bytes)
        ) {
            _ = try NamedTextMarker(
                id: exactIdentifier + "x",
                name: "Valid",
                literal: "x"
            )
        }
        assertMarkerError(.nameTooLarge(maximumUTF8Bytes: NamedTextMarker.maximumNameUTF8Bytes)) {
            _ = try NamedTextMarker(
                id: "valid",
                name: exactName + "x",
                literal: "x"
            )
        }
        assertMarkerError(
            .colorTokenTooLarge(maximumUTF8Bytes: TextMarkerColorToken.maximumUTF8Bytes)
        ) {
            _ = try TextMarkerColorToken(rawValue: exactColor + "x")
        }
        assertMarkerError(.emptyLiteralPattern) {
            _ = try NamedTextMarker(id: "empty", name: "Empty", literal: "")
        }
        assertMarkerError(
            .patternTooLarge(maximumUTF16Length: NamedTextMarker.maximumPatternUTF16Length)
        ) {
            _ = try NamedTextMarker(
                id: "large",
                name: "Large",
                literal: exactPattern + "x"
            )
        }
        assertMarkerError(.invalidRegularExpression("[")) {
            _ = try NamedTextMarker(id: "regex", name: "Regex", regularExpression: "[")
        }
    }

    func testPersistenceRoundTripIsCompactDeterministicAndFullySpecified() throws {
        let marker = try NamedTextMarker(
            id: "regex/id",
            name: "Regex Marker",
            regularExpression: #"f.o"#,
            caseSensitive: false,
            wholeWord: true,
            colorToken: TextMarkerColorToken(rawValue: "search/primary"),
            scope: .lineRange(1...2)
        )
        let markers = try TextMarkers(
            markers: [marker],
            activeMarkerID: marker.id,
            repeatDirection: .backward
        )
        let expected =
            #"{"activeMarkerID":"regex/id","markers":[{"caseSensitive":false,"colorToken":"search/primary","id":"regex/id","name":"Regex Marker","pattern":"f.o","patternKind":"regularExpression","scope":{"firstLine":1,"kind":"lineRange","lastLine":2},"wholeWord":true}],"repeatDirection":"backward","schemaVersion":1}"#

        let first = try markers.encodedData()
        let second = try markers.encodedData()

        XCTAssertEqual(first, second)
        XCTAssertEqual(String(decoding: first, as: UTF8.self), expected)
        XCTAssertFalse(first.contains(0x0A))
        XCTAssertEqual(try TextMarkers.decode(from: first), markers)
        XCTAssertEqual(try TextMarkers.decode(from: first).encodedData(), first)
        requireSendable(markers)
        requireSendable(TextMarkersError.staleDocument)
    }

    func testPersistencePreservesEveryPatternAndScopeVariant() throws {
        let markers = try TextMarkers(
            markers: [
                NamedTextMarker(
                    id: "literal",
                    name: "Literal",
                    literal: "Caf\u{E9}",
                    caseSensitive: false,
                    scope: .entireDocument
                ),
                NamedTextMarker(
                    id: "range",
                    name: "Range",
                    regularExpression: #"\d+"#,
                    wholeWord: true,
                    scope: .utf16Range(NSRange(location: 2, length: 7))
                ),
                NamedTextMarker(
                    id: "lines",
                    name: "Lines",
                    literal: "x",
                    scope: .lineRange(3...5)
                )
            ],
            activeMarkerID: nil,
            repeatDirection: .forward
        )

        let decoded = try TextMarkers.decode(from: markers.encodedData())

        XCTAssertEqual(decoded, markers)
        XCTAssertNil(decoded.activeMarkerID)
        XCTAssertEqual(
            decoded.markers.map(\.scope),
            [
                .entireDocument,
                .utf16Range(NSRange(location: 2, length: 7)),
                .lineRange(3...5)
            ])
    }

    func testDecodeStreamsMarkerCountAndEncodedByteCaps() throws {
        let one = try TextMarkers(markers: [
            NamedTextMarker(id: "one", name: "One", literal: "1")
        ])
        let two = try TextMarkers(markers: [
            NamedTextMarker(id: "one", name: "One", literal: "1"),
            NamedTextMarker(id: "two", name: "Two", literal: "2")
        ])
        let oneData = try one.encodedData()
        let twoData = try two.encodedData()
        let oneMarkerLimits = limits(maximumMarkers: 1)

        XCTAssertEqual(try TextMarkers.decode(from: oneData, limits: oneMarkerLimits), one)
        assertMarkerError(.tooManyMarkers(maximumMarkers: 1)) {
            _ = try TextMarkers.decode(from: twoData, limits: oneMarkerLimits)
        }

        var exactBoundary = oneData
        exactBoundary.append(Data(repeating: 0x20, count: 32))
        let exactByteLimits = limits(maximumEncodedBytes: exactBoundary.count)
        XCTAssertEqual(try TextMarkers.decode(from: exactBoundary, limits: exactByteLimits), one)

        var oversized = exactBoundary
        oversized.append(0x20)
        assertMarkerError(.encodedDataTooLarge(maximumBytes: exactBoundary.count)) {
            _ = try TextMarkers.decode(from: oversized, limits: exactByteLimits)
        }

        let exactEncodingLimits = limits(maximumEncodedBytes: oneData.count)
        XCTAssertEqual(try one.encodedData(limits: exactEncodingLimits), oneData)
        assertMarkerError(.encodedDataTooLarge(maximumBytes: oneData.count - 1)) {
            _ = try one.encodedData(limits: self.limits(maximumEncodedBytes: oneData.count - 1))
        }

        let escapedPattern = String(repeating: "\"", count: 32 * 1024)
        let encodedOverflow = try TextMarkers(
            markers: (0..<128).map { index in
                try NamedTextMarker(
                    id: "large-\(index)",
                    name: "Large \(index)",
                    literal: escapedPattern
                )
            }
        )
        assertMarkerError(.encodedDataTooLarge(maximumBytes: TextMarkers.maximumEncodedBytes)) {
            _ = try encodedOverflow.encodedData()
        }
    }

    func testStrictDecodeRejectsUnknownRootMarkerAndScopeKeys() throws {
        let data = try TextMarkers(markers: [
            NamedTextMarker(id: "one", name: "One", literal: "1")
        ]).encodedData()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        var unknownRoot = root
        unknownRoot["future"] = true
        assertDecodingFailure(try JSONSerialization.data(withJSONObject: unknownRoot))

        var unknownMarker = root
        var markerArray = try XCTUnwrap(unknownMarker["markers"] as? [[String: Any]])
        markerArray[0]["future"] = true
        unknownMarker["markers"] = markerArray
        assertDecodingFailure(try JSONSerialization.data(withJSONObject: unknownMarker))

        var unknownScope = root
        markerArray = try XCTUnwrap(unknownScope["markers"] as? [[String: Any]])
        var scope = try XCTUnwrap(markerArray[0]["scope"] as? [String: Any])
        scope["future"] = true
        markerArray[0]["scope"] = scope
        unknownScope["markers"] = markerArray
        assertDecodingFailure(try JSONSerialization.data(withJSONObject: unknownScope))
    }

    func testStrictDecodeRejectsDuplicateRawJSONKeysIncludingEscapedAliases() {
        let duplicateRoot = Data(
            #"{"schemaVersion":1,"schema\u0056ersion":1,"markers":[],"repeatDirection":"forward"}"#.utf8
        )
        let duplicateMarker = Data(
            #"{"schemaVersion":1,"markers":[{"id":"one","\u0069d":"two","name":"One","pattern":"1","patternKind":"literal","caseSensitive":true,"wholeWord":false,"colorToken":"search-marker","scope":{"kind":"entireDocument"}}],"repeatDirection":"forward"}"#
                .utf8
        )
        let duplicateScope = Data(
            #"{"schemaVersion":1,"markers":[{"id":"one","name":"One","pattern":"1","patternKind":"literal","caseSensitive":true,"wholeWord":false,"colorToken":"search-marker","scope":{"kind":"entireDocument","\u006Bind":"entireDocument"}}],"repeatDirection":"forward"}"#
                .utf8
        )

        assertDecodingError(duplicateRoot, contains: "Duplicate root key: schemaVersion")
        assertDecodingError(duplicateMarker, contains: "Duplicate marker key at index 0: id")
        assertDecodingError(duplicateScope, contains: "Duplicate scope key at marker index 0: kind")
    }

    func testStrictDecodeRejectsIllegalScopeKeyCombinations() throws {
        let data = try TextMarkers(markers: [
            NamedTextMarker(id: "one", name: "One", literal: "1")
        ]).encodedData()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let invalidScopes: [[String: Any]] = [
            ["kind": "entireDocument", "location": 0],
            ["kind": "utf16Range", "location": 0, "length": 1, "firstLine": 1],
            ["kind": "lineRange", "firstLine": 1, "lastLine": 1, "length": 1],
            ["kind": "utf16Range", "location": 0],
            ["kind": "lineRange", "firstLine": 1]
        ]

        for scope in invalidScopes {
            var invalid = root
            var markerArray = try XCTUnwrap(invalid["markers"] as? [[String: Any]])
            markerArray[0]["scope"] = scope
            invalid["markers"] = markerArray
            assertDecodingError(
                try JSONSerialization.data(withJSONObject: invalid),
                contains: "Illegal key combination"
            )
        }
    }

    func testActiveMarkerIDMissingAndNullFollowExistingOptionalSchemaBehavior() throws {
        let marker = try NamedTextMarker(id: "one", name: "One", literal: "1")
        let encoded = try TextMarkers(markers: [marker], activeMarkerID: marker.id).encodedData()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        root.removeValue(forKey: "activeMarkerID")
        XCTAssertNil(
            try TextMarkers.decode(from: JSONSerialization.data(withJSONObject: root)).activeMarkerID
        )

        root["activeMarkerID"] = NSNull()
        XCTAssertNil(
            try TextMarkers.decode(from: JSONSerialization.data(withJSONObject: root)).activeMarkerID
        )
    }

    func testStrictDecodeRejectsMissingWrongTypedMalformedAndSemanticValues() throws {
        let data = try TextMarkers(markers: [
            NamedTextMarker(id: "one", name: "One", literal: "1")
        ]).encodedData()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        for key in ["schemaVersion", "markers", "repeatDirection"] {
            var missing = root
            missing.removeValue(forKey: key)
            assertDecodingFailure(try JSONSerialization.data(withJSONObject: missing), message: key)
        }
        for (key, value) in [
            ("schemaVersion", "1" as Any),
            ("markers", true as Any),
            ("repeatDirection", 1 as Any)
        ] {
            var wrongType = root
            wrongType[key] = value
            assertDecodingFailure(try JSONSerialization.data(withJSONObject: wrongType), message: key)
        }

        let markerKeys = [
            "id", "name", "pattern", "patternKind", "caseSensitive", "wholeWord",
            "colorToken", "scope"
        ]
        for key in markerKeys {
            var missing = root
            var markerArray = try XCTUnwrap(missing["markers"] as? [[String: Any]])
            markerArray[0].removeValue(forKey: key)
            missing["markers"] = markerArray
            assertDecodingFailure(try JSONSerialization.data(withJSONObject: missing), message: key)
        }

        for malformed in [Data(), Data("null".utf8), Data("[]".utf8), Data("{".utf8), Data([0xFF])] {
            assertDecodingFailure(malformed)
        }
        assertMarkerError(.unsupportedSchemaVersion(2)) {
            _ = try TextMarkers.decode(from: replacing(root, key: "schemaVersion", value: 2))
        }
        assertMarkerError(.unknownMarker("missing")) {
            _ = try TextMarkers.decode(
                from: replacing(root, key: "activeMarkerID", value: "missing")
            )
        }

        var invalidMarker = root
        var markerArray = try XCTUnwrap(invalidMarker["markers"] as? [[String: Any]])
        markerArray[0]["id"] = "two words"
        invalidMarker["markers"] = markerArray
        assertDecodingFailure(try JSONSerialization.data(withJSONObject: invalidMarker))

        var duplicate = root
        markerArray = try XCTUnwrap(duplicate["markers"] as? [[String: Any]])
        markerArray.append(markerArray[0])
        duplicate["markers"] = markerArray
        assertMarkerError(.duplicateIdentifier("one")) {
            _ = try TextMarkers.decode(from: JSONSerialization.data(withJSONObject: duplicate))
        }

        let semanticInvalidValues: [(String, Any)] = [
            ("name", " leading"),
            ("pattern", ""),
            ("colorToken", "bad token")
        ]
        for (key, value) in semanticInvalidValues {
            var invalid = root
            markerArray = try XCTUnwrap(invalid["markers"] as? [[String: Any]])
            markerArray[0][key] = value
            invalid["markers"] = markerArray
            assertDecodingFailure(try JSONSerialization.data(withJSONObject: invalid), message: key)
        }

        var invalidRegex = root
        markerArray = try XCTUnwrap(invalidRegex["markers"] as? [[String: Any]])
        markerArray[0]["pattern"] = "["
        markerArray[0]["patternKind"] = "regularExpression"
        invalidRegex["markers"] = markerArray
        assertDecodingFailure(try JSONSerialization.data(withJSONObject: invalidRegex))

        var duplicateName = root
        markerArray = try XCTUnwrap(duplicateName["markers"] as? [[String: Any]])
        markerArray[0]["name"] = "Caf\u{E9}"
        var secondMarker = markerArray[0]
        secondMarker["id"] = "two"
        secondMarker["name"] = "Cafe\u{301}"
        markerArray.append(secondMarker)
        duplicateName["markers"] = markerArray
        assertMarkerError(.duplicateName("Cafe\u{301}")) {
            _ = try TextMarkers.decode(from: JSONSerialization.data(withJSONObject: duplicateName))
        }
    }

    func testLiteralRegexCaseWholeWordOrderingAndRangeProvenance() throws {
        let text = "Foo foo food _foo foo_"
        let document = TextMarkerDocument(text: text, revision: .init(rawValue: 1))
        let markers = try TextMarkers(
            markers: [
                NamedTextMarker(
                    id: "whole-regex",
                    name: "Whole regex",
                    regularExpression: "f.o",
                    caseSensitive: false,
                    wholeWord: true
                ),
                NamedTextMarker(
                    id: "literal",
                    name: "Literal",
                    literal: "foo"
                ),
                NamedTextMarker(
                    id: "case",
                    name: "Case",
                    literal: "Foo"
                )
            ],
            activeMarkerID: "whole-regex"
        )

        let matchSet = try markers.matches(in: document)

        XCTAssertEqual(
            try matchSet.allRanges(in: document),
            [
                markerRange("whole-regex", 0, 3),
                markerRange("case", 0, 3),
                markerRange("whole-regex", 4, 3),
                markerRange("literal", 4, 3),
                markerRange("literal", 8, 3),
                markerRange("literal", 14, 3),
                markerRange("literal", 18, 3)
            ])
        XCTAssertEqual(
            try matchSet.ranges(forMarker: "whole-regex", in: document),
            [markerRange("whole-regex", 0, 3), markerRange("whole-regex", 4, 3)]
        )
        XCTAssertEqual(matchSet.documentRevision, document.revision)
        XCTAssertEqual(matchSet.documentUTF16Length, text.utf16.count)
        XCTAssertEqual(matchSet.markers, markers.markers)
        XCTAssertEqual(matchSet.activeMarkerID, markers.activeMarkerID)
        XCTAssertEqual(matchSet.repeatDirection, markers.repeatDirection)
        assertMarkerError(.unknownMarker("missing")) {
            _ = try matchSet.ranges(forMarker: "missing", in: document)
        }
    }

    func testScopesFilterFullDocumentResultsWithoutChangingRegexContext() throws {
        let text = "zero\nBeta alpha\nomega"
        let document = TextMarkerDocument(text: text, revision: .init(rawValue: 2))
        let target = NSRange(location: 10, length: 5)
        let markers = try TextMarkers(markers: [
            NamedTextMarker(
                id: "utf16",
                name: "UTF16",
                literal: "alpha",
                scope: .utf16Range(target)
            ),
            NamedTextMarker(
                id: "line",
                name: "Line",
                literal: "alpha",
                scope: .lineRange(2...2)
            ),
            NamedTextMarker(
                id: "lookbehind",
                name: "Lookbehind",
                regularExpression: #"(?<=Beta )alpha"#,
                scope: .utf16Range(target)
            )
        ])

        XCTAssertEqual(
            try markers.matches(in: document).allRanges(in: document),
            [
                markerRange("utf16", 10, 5),
                markerRange("line", 10, 5),
                markerRange("lookbehind", 10, 5)
            ])

        let outOfBounds = try TextMarkers(markers: [
            NamedTextMarker(
                id: "range",
                name: "Range",
                literal: "x",
                scope: .utf16Range(NSRange(location: text.utf16.count, length: 1))
            )
        ])
        assertMarkerError(
            .utf16RangeOutOfBounds(
                range: NSRange(location: text.utf16.count, length: 1),
                documentUTF16Length: text.utf16.count
            )
        ) {
            _ = try outOfBounds.matches(in: document)
        }

        let missingLine = try TextMarkers(markers: [
            NamedTextMarker(
                id: "line",
                name: "Line",
                literal: "x",
                scope: .lineRange(4...4)
            )
        ])
        assertMarkerError(.lineRangeOutOfBounds(range: 4...4, lineCount: 3)) {
            _ = try missingLine.matches(in: document)
        }
    }

    func testScopesRejectMatchesCrossingEitherBound() throws {
        let document = TextMarkerDocument(text: "xabcy", revision: .init(rawValue: 20))
        let scope = TextMarkerScope.utf16Range(NSRange(location: 1, length: 3))
        let markers = try TextMarkers(markers: [
            NamedTextMarker(id: "lower", name: "Lower", literal: "xa", scope: scope),
            NamedTextMarker(id: "inside", name: "Inside", literal: "ab", scope: scope),
            NamedTextMarker(id: "upper", name: "Upper", regularExpression: "cy", scope: scope)
        ])
        let matchSet = try markers.matches(in: document)

        XCTAssertEqual(try matchSet.ranges(forMarker: "lower", in: document), [])
        XCTAssertEqual(
            try matchSet.ranges(forMarker: "inside", in: document),
            [markerRange("inside", 1, 2)]
        )
        XCTAssertEqual(try matchSet.ranges(forMarker: "upper", in: document), [])
    }

    func testLineScopesHandleCRCRLFAndTrailingLogicalLine() throws {
        let document = TextMarkerDocument(text: "a\rb\r\nc\n", revision: .init(rawValue: 21))
        let markers = try TextMarkers(markers: [
            NamedTextMarker(
                id: "cr",
                name: "CR",
                literal: "\r",
                scope: .lineRange(1...1)
            ),
            NamedTextMarker(
                id: "crlf",
                name: "CRLF",
                literal: "\r\n",
                scope: .lineRange(2...2)
            ),
            NamedTextMarker(
                id: "final-content",
                name: "Final content",
                literal: "c",
                scope: .lineRange(3...3)
            ),
            NamedTextMarker(
                id: "trailing-line",
                name: "Trailing line",
                regularExpression: "",
                scope: .lineRange(4...4)
            )
        ])
        let matchSet = try markers.matches(in: document)

        XCTAssertEqual(try matchSet.ranges(forMarker: "cr", in: document), [markerRange("cr", 1, 1)])
        XCTAssertEqual(
            try matchSet.ranges(forMarker: "crlf", in: document),
            [markerRange("crlf", 3, 2)]
        )
        XCTAssertEqual(
            try matchSet.ranges(forMarker: "final-content", in: document),
            [markerRange("final-content", 5, 1)]
        )
        XCTAssertEqual(
            try matchSet.ranges(forMarker: "trailing-line", in: document),
            [markerRange("trailing-line", 7, 0)]
        )

        let missingFifthLine = try TextMarkers(markers: [
            NamedTextMarker(
                id: "missing",
                name: "Missing",
                literal: "x",
                scope: .lineRange(5...5)
            )
        ])
        assertMarkerError(.lineRangeOutOfBounds(range: 5...5, lineCount: 4)) {
            _ = try missingFifthLine.matches(in: document)
        }
    }

    func testNavigationRepeatWrappingDirectionAndMatchSetProvenance() throws {
        let document = TextMarkerDocument(text: "a x a", revision: .init(rawValue: 3))
        var markers = try TextMarkers(
            markers: [NamedTextMarker(id: "a", name: "A", literal: "a")],
            activeMarkerID: "a",
            repeatDirection: .backward
        )
        let matchSet = try markers.matches(in: document)

        let wrappedBackward = try matchSet.navigate(fromUTF16Offset: 0, in: document)
        XCTAssertEqual(wrappedBackward.match, markerRange("a", 4, 1))
        XCTAssertTrue(wrappedBackward.didWrap)
        XCTAssertEqual(wrappedBackward.direction, .backward)

        let first = try matchSet.navigate(
            fromUTF16Offset: 0,
            direction: .forward,
            in: document
        )
        XCTAssertEqual(first.match, markerRange("a", 0, 1))
        XCTAssertFalse(first.didWrap)

        let second = try matchSet.repeatSearch(after: first, in: document)
        XCTAssertEqual(second.match, markerRange("a", 4, 1))
        XCTAssertFalse(second.didWrap)
        XCTAssertEqual(second.direction, .forward)

        let wrappedFirst = try matchSet.repeatSearch(after: second, in: document)
        XCTAssertEqual(wrappedFirst.match, markerRange("a", 0, 1))
        XCTAssertTrue(wrappedFirst.didWrap)

        let previous = try matchSet.repeatSearch(
            after: second,
            direction: .backward,
            in: document
        )
        XCTAssertEqual(previous.match, markerRange("a", 0, 1))
        XCTAssertFalse(previous.didWrap)

        let exhausted = try matchSet.repeatSearch(after: second, wrap: false, in: document)
        XCTAssertNil(exhausted.match)
        XCTAssertFalse(exhausted.didWrap)
        XCTAssertNil(try matchSet.repeatSearch(after: exhausted, in: document).match)

        let otherMatchSet = try markers.matches(in: document)
        assertMarkerError(.staleMatchSet) {
            _ = try otherMatchSet.repeatSearch(after: first, in: document)
        }
        assertMarkerError(.unknownMarker("missing")) {
            _ = try matchSet.navigate(
                fromUTF16Offset: 0,
                markerID: "missing",
                in: document
            )
        }

        markers.deactivate()
        let inactive = try markers.matches(in: document)
        assertMarkerError(.noActiveMarker) {
            _ = try inactive.navigate(fromUTF16Offset: 0, in: document)
        }
    }

    func testMatchSetIsImmutableMarkerConfigurationSnapshot() throws {
        let document = TextMarkerDocument(text: "old new", revision: .init(rawValue: 4))
        let original = try NamedTextMarker(id: "marker", name: "Original", literal: "old")
        var markers = try TextMarkers(markers: [original], activeMarkerID: original.id)
        let snapshot = try markers.matches(in: document)

        let updated = try NamedTextMarker(id: original.id, name: "Updated", literal: "new")
        try markers.update(updated)

        XCTAssertEqual(snapshot.marker(id: original.id), original)
        XCTAssertEqual(try snapshot.allRanges(in: document), [markerRange(original.id, 0, 3)])
        XCTAssertEqual(
            try markers.matches(in: document).allRanges(in: document),
            [markerRange(original.id, 4, 3)]
        )
    }

    func testExactDocumentFingerprintAndRevisionRejectStaleResults() throws {
        let revision = TextMarkerDocumentRevision(rawValue: 5)
        let original = TextMarkerDocument(text: "\u{E9}", revision: revision)
        let markers = try TextMarkers(markers: [
            NamedTextMarker(id: "accent", name: "Accent", literal: "\u{E9}")
        ])
        let matchSet = try markers.matches(in: original)

        XCTAssertNoThrow(try matchSet.validate(in: original))
        assertMarkerError(.staleDocument) {
            try matchSet.validate(
                in: TextMarkerDocument(text: "e\u{301}", revision: revision)
            )
        }
        assertMarkerError(.staleDocument) {
            try matchSet.validate(in: TextMarkerDocument(text: "x", revision: revision))
        }

        let currentRevision = TextMarkerDocumentRevision(rawValue: 6)
        assertMarkerError(
            .staleDocumentRevision(expected: revision, actual: currentRevision)
        ) {
            _ = try matchSet.allRanges(
                in: TextMarkerDocument(text: original.text, revision: currentRevision)
            )
        }
    }

    func testZeroLengthRegexIncludesEOFOnlyForEligibleScopeUpperBounds() throws {
        let document = TextMarkerDocument(text: "a\n", revision: .init(rawValue: 7))
        let markers = try TextMarkers(markers: [
            NamedTextMarker(id: "entire", name: "Entire", regularExpression: ""),
            NamedTextMarker(
                id: "document-range",
                name: "Document range",
                regularExpression: "",
                scope: .utf16Range(NSRange(location: 0, length: 2))
            ),
            NamedTextMarker(
                id: "eof",
                name: "EOF",
                regularExpression: "",
                scope: .utf16Range(NSRange(location: 2, length: 0))
            ),
            NamedTextMarker(
                id: "first-line",
                name: "First line",
                regularExpression: "",
                scope: .lineRange(1...1)
            ),
            NamedTextMarker(
                id: "final-line",
                name: "Final line",
                regularExpression: "",
                scope: .lineRange(2...2)
            )
        ])
        let result = try markers.matches(in: document)

        XCTAssertEqual(
            try result.ranges(forMarker: "entire", in: document),
            [
                markerRange("entire", 0, 0),
                markerRange("entire", 1, 0),
                markerRange("entire", 2, 0)
            ])
        XCTAssertEqual(
            try result.ranges(forMarker: "document-range", in: document),
            [
                markerRange("document-range", 0, 0),
                markerRange("document-range", 1, 0)
            ])
        XCTAssertEqual(
            try result.ranges(forMarker: "eof", in: document),
            [markerRange("eof", 2, 0)]
        )
        XCTAssertEqual(
            try result.ranges(forMarker: "first-line", in: document),
            [
                markerRange("first-line", 0, 0),
                markerRange("first-line", 1, 0)
            ])
        XCTAssertEqual(
            try result.ranges(forMarker: "final-line", in: document),
            [markerRange("final-line", 2, 0)]
        )
    }

    func testZeroLengthNavigationAdvancesAndWrapsInBothDirections() throws {
        let document = TextMarkerDocument(text: "ab", revision: .init(rawValue: 22))
        let markers = try TextMarkers(
            markers: [NamedTextMarker(id: "zero", name: "Zero", regularExpression: "")],
            activeMarkerID: "zero"
        )
        let matchSet = try markers.matches(in: document)

        let first = try matchSet.navigate(fromUTF16Offset: 0, in: document)
        XCTAssertEqual(first.match, markerRange("zero", 0, 0))
        let second = try matchSet.repeatSearch(after: first, in: document)
        XCTAssertEqual(second.match, markerRange("zero", 1, 0))
        let third = try matchSet.repeatSearch(after: second, in: document)
        XCTAssertEqual(third.match, markerRange("zero", 2, 0))
        let wrapped = try matchSet.repeatSearch(after: third, in: document)
        XCTAssertEqual(wrapped.match, markerRange("zero", 0, 0))
        XCTAssertTrue(wrapped.didWrap)

        let last = try matchSet.navigate(
            fromUTF16Offset: 2,
            direction: .backward,
            in: document
        )
        XCTAssertEqual(last.match, markerRange("zero", 2, 0))
        let previous = try matchSet.repeatSearch(after: last, in: document)
        XCTAssertEqual(previous.match, markerRange("zero", 1, 0))
    }

    func testGraphemeBoundariesCoverCombiningZWJAndRegionalIndicatorFlags() throws {
        let text = "e\u{301}|\u{1F469}\u{200D}\u{1F4BB}|\u{1F1FA}\u{1F1F8}|x"
        let document = TextMarkerDocument(text: text, revision: .init(rawValue: 8))
        let markers = try TextMarkers(markers: [
            NamedTextMarker(id: "accent", name: "Accent", literal: "\u{E9}"),
            NamedTextMarker(
                id: "zwj",
                name: "ZWJ",
                literal: "\u{1F469}\u{200D}\u{1F4BB}"
            ),
            NamedTextMarker(
                id: "flag",
                name: "Flag",
                literal: "\u{1F1FA}\u{1F1F8}"
            ),
            NamedTextMarker(
                id: "split-regex",
                name: "Split regex",
                regularExpression: "\u{301}|x"
            )
        ])
        let matchSet = try markers.matches(in: document)

        XCTAssertEqual(
            try matchSet.allRanges(in: document),
            [
                markerRange("accent", 0, 2),
                markerRange("zwj", 3, 5),
                markerRange("flag", 9, 4),
                markerRange("split-regex", 14, 1)
            ])

        for offset in [1, 4, 10] {
            assertMarkerError(.navigationOffsetSplitsCharacter(offset)) {
                _ = try matchSet.navigate(
                    fromUTF16Offset: offset,
                    markerID: "accent",
                    in: document
                )
            }
        }

        let splitScope = NSRange(location: 3, length: 2)
        let scoped = try TextMarkers(markers: [
            NamedTextMarker(
                id: "scope",
                name: "Scope",
                literal: "x",
                scope: .utf16Range(splitScope)
            )
        ])
        assertMarkerError(.utf16RangeSplitsCharacter(splitScope)) {
            _ = try scoped.matches(in: document)
        }
    }

    func testWholeWordRegexRetriesLongerAlternativeAtSameOffset() throws {
        let document = TextMarkerDocument(text: "ab", revision: .init(rawValue: 9))
        let markers = try TextMarkers(markers: [
            NamedTextMarker(
                id: "regex",
                name: "Regex",
                regularExpression: "a|ab",
                wholeWord: true
            ),
            NamedTextMarker(
                id: "short-literal",
                name: "Short literal",
                literal: "a",
                wholeWord: true
            ),
            NamedTextMarker(
                id: "long-literal",
                name: "Long literal",
                literal: "ab",
                wholeWord: true
            )
        ])

        XCTAssertEqual(
            try markers.matches(in: document).allRanges(in: document),
            [
                markerRange("regex", 0, 2),
                markerRange("long-literal", 0, 2)
            ])
    }

    func testStrictLimitsAcceptExactBoundsAndRejectOneMore() throws {
        let exactMarker = try NamedTextMarker(
            id: "\u{E9}",
            name: "\u{E9}",
            literal: "\u{1F600}",
            colorToken: TextMarkerColorToken(rawValue: "cc"),
            scope: .utf16Range(NSRange(location: 0, length: 2))
        )
        let exact = try TextMarkers(markers: [exactMarker])
        let exactSearchLimits = searchLimits(
            maximumInputUTF16Length: 2,
            maximumPatternUTF16Length: 2,
            maximumMatches: 1,
            maximumMarkers: 1,
            maximumCombinedPatternUTF16Length: 2,
            maximumStoredCaptureRanges: 1
        )
        let exactLimits = limits(
            maximumMarkers: 1,
            maximumIdentifierUTF8Bytes: 2,
            maximumNameUTF8Bytes: 2,
            maximumColorTokenUTF8Bytes: 2,
            maximumScopeUTF16Length: 2,
            maximumResultRanges: 1,
            maximumWorkUnits: 5,
            searchLimits: exactSearchLimits
        )
        let exactDocument = TextMarkerDocument(text: "\u{1F600}", revision: .init(rawValue: 10))

        XCTAssertNoThrow(try exact.validate(limits: exactLimits))
        XCTAssertEqual(
            try exact.matches(in: exactDocument, limits: exactLimits).allRanges(in: exactDocument),
            [markerRange(exactMarker.id, 0, 2)]
        )

        let identifierTooLarge = try TextMarkers(markers: [
            NamedTextMarker(id: "\u{E9}x", name: "N", literal: "x")
        ])
        assertMarkerError(.identifierTooLarge(maximumUTF8Bytes: 2)) {
            try identifierTooLarge.validate(limits: self.limits(maximumIdentifierUTF8Bytes: 2))
        }
        let nameTooLarge = try TextMarkers(markers: [
            NamedTextMarker(id: "id", name: "\u{E9}x", literal: "x")
        ])
        assertMarkerError(.nameTooLarge(maximumUTF8Bytes: 2)) {
            try nameTooLarge.validate(limits: self.limits(maximumNameUTF8Bytes: 2))
        }
        let colorTooLarge = try TextMarkers(markers: [
            NamedTextMarker(
                id: "id",
                name: "Name",
                literal: "x",
                colorToken: TextMarkerColorToken(rawValue: "ccc")
            )
        ])
        assertMarkerError(.colorTokenTooLarge(maximumUTF8Bytes: 2)) {
            try colorTooLarge.validate(limits: self.limits(maximumColorTokenUTF8Bytes: 2))
        }

        let scopeTooLarge = try TextMarkers(markers: [
            NamedTextMarker(
                id: "scope",
                name: "Scope",
                literal: "x",
                scope: .utf16Range(NSRange(location: 0, length: 3))
            )
        ])
        assertMarkerError(.scopeTooLarge(markerID: "scope", maximumUTF16Length: 2)) {
            try scopeTooLarge.validate(limits: self.limits(maximumScopeUTF16Length: 2))
        }

        let lineTooHigh = try TextMarkers(markers: [
            NamedTextMarker(
                id: "line",
                name: "Line",
                literal: "x",
                scope: .lineRange(1...3)
            )
        ])
        assertMarkerError(.lineRangeExceedsLimit(maximumLine: 2)) {
            try lineTooHigh.validate(limits: self.limits(maximumLineCount: 2))
        }
    }

    func testAggregatePatternResultWorkLineAndSearchCapsAreStrict() throws {
        let two = try TextMarkers(markers: [
            NamedTextMarker(id: "a", name: "A", literal: "aa"),
            NamedTextMarker(id: "b", name: "B", literal: "\u{1F600}")
        ])
        let combinedExact = limits(
            maximumMarkers: 2,
            searchLimits: searchLimits(
                maximumMarkers: 2,
                maximumCombinedPatternUTF16Length: 4
            )
        )
        XCTAssertNoThrow(try two.validate(limits: combinedExact))

        let three = try TextMarkers(
            markers: two.markers + [
                NamedTextMarker(id: "c", name: "C", literal: "c")
            ])
        assertMarkerError(.tooManyMarkers(maximumMarkers: 2)) {
            try three.validate(limits: combinedExact)
        }
        assertMarkerError(.combinedPatternsTooLarge(maximumUTF16Length: 4)) {
            try three.validate(
                limits: self.limits(
                    maximumMarkers: 3,
                    searchLimits: self.searchLimits(
                        maximumMarkers: 3,
                        maximumCombinedPatternUTF16Length: 4
                    )
                )
            )
        }

        let repeated = try TextMarkers(markers: [
            NamedTextMarker(id: "a", name: "A", literal: "a")
        ])
        let exactDocument = TextMarkerDocument(text: "aa", revision: .init(rawValue: 11))
        let exactLimits = limits(maximumResultRanges: 2, maximumWorkUnits: 5)
        XCTAssertEqual(
            try repeated.matches(in: exactDocument, limits: exactLimits).allRanges(in: exactDocument).count,
            2
        )
        assertMarkerError(.tooManyResultRanges(maximumRanges: 2)) {
            let document = TextMarkerDocument(text: "aaa", revision: .init(rawValue: 11))
            _ = try repeated.matches(
                in: document,
                limits: self.limits(maximumResultRanges: 2)
            )
        }
        assertMarkerError(.workLimitExceeded(maximumWorkUnits: 4)) {
            _ = try repeated.matches(
                in: exactDocument,
                limits: self.limits(maximumWorkUnits: 4)
            )
        }

        let twoMarkerWork = try TextMarkers(markers: [
            NamedTextMarker(id: "a", name: "A", literal: "a"),
            NamedTextMarker(id: "b", name: "B", literal: "b")
        ])
        let twoMarkerDocument = TextMarkerDocument(text: "ab", revision: .init(rawValue: 11))
        XCTAssertNoThrow(
            try twoMarkerWork.matches(
                in: twoMarkerDocument,
                limits: limits(maximumWorkUnits: 8)
            )
        )
        assertMarkerError(.workLimitExceeded(maximumWorkUnits: 7)) {
            _ = try twoMarkerWork.matches(
                in: twoMarkerDocument,
                limits: self.limits(maximumWorkUnits: 7)
            )
        }

        let lineScoped = try TextMarkers(markers: [
            NamedTextMarker(
                id: "line",
                name: "Line",
                literal: "a",
                scope: .lineRange(1...1)
            )
        ])
        XCTAssertNoThrow(
            try lineScoped.matches(
                in: exactDocument,
                limits: limits(maximumLineCount: 1, maximumLineUTF16Length: 2)
            )
        )
        XCTAssertThrowsError(
            try lineScoped.matches(
                in: TextMarkerDocument(text: "aaa", revision: .init(rawValue: 11)),
                limits: limits(maximumLineUTF16Length: 2)
            )
        ) { error in
            XCTAssertEqual(
                error as? TextNavigationError,
                .lineTooLong(line: 1, maximumUTF16Length: 2)
            )
        }
        XCTAssertThrowsError(
            try lineScoped.matches(
                in: TextMarkerDocument(text: "a\n", revision: .init(rawValue: 11)),
                limits: limits(maximumLineCount: 1)
            )
        ) { error in
            XCTAssertEqual(error as? TextNavigationError, .tooManyLines(maximumLines: 1))
        }

        assertTextSearchError(.inputTooLarge(maximumUTF16Length: 2)) {
            let document = TextMarkerDocument(text: "aaa", revision: .init(rawValue: 11))
            _ = try repeated.matches(
                in: document,
                limits: self.limits(
                    searchLimits: self.searchLimits(maximumInputUTF16Length: 2)
                )
            )
        }
        assertMarkerError(.patternTooLarge(maximumUTF16Length: 1)) {
            try two.validate(
                limits: self.limits(
                    searchLimits: self.searchLimits(maximumPatternUTF16Length: 1)
                )
            )
        }

        let aggregateMatches = try TextMarkers(markers: [
            NamedTextMarker(id: "first", name: "First", literal: "a"),
            NamedTextMarker(id: "second", name: "Second", literal: "b")
        ])
        let aggregateDocument = TextMarkerDocument(text: "ab", revision: .init(rawValue: 23))
        assertMarkerError(.tooManyResultRanges(maximumRanges: 1)) {
            _ = try aggregateMatches.matches(
                in: aggregateDocument,
                limits: self.limits(
                    maximumResultRanges: 2,
                    searchLimits: self.searchLimits(maximumMatches: 1)
                )
            )
        }
        assertTextSearchError(.tooManyCaptureRanges(maximumRanges: 1)) {
            _ = try aggregateMatches.matches(
                in: aggregateDocument,
                limits: self.limits(
                    searchLimits: self.searchLimits(maximumStoredCaptureRanges: 1)
                )
            )
        }

        let regexCaptures = try TextMarkers(markers: [
            NamedTextMarker(id: "first", name: "First", regularExpression: "(a)"),
            NamedTextMarker(id: "second", name: "Second", regularExpression: "(b)")
        ])
        XCTAssertEqual(
            try regexCaptures.matches(
                in: aggregateDocument,
                limits: self.limits(
                    searchLimits: self.searchLimits(maximumStoredCaptureRanges: 4)
                )
            ).allRanges(in: aggregateDocument).count,
            2
        )
        assertTextSearchError(.tooManyCaptureRanges(maximumRanges: 3)) {
            _ = try regexCaptures.matches(
                in: aggregateDocument,
                limits: self.limits(
                    searchLimits: self.searchLimits(maximumStoredCaptureRanges: 3)
                )
            )
        }
    }

    func testInvalidLimitsAreRejectedBeforeWork() throws {
        let markers = try TextMarkers()
        let invalidLimits = [
            limits(maximumMarkers: -1),
            limits(maximumIdentifierUTF8Bytes: 0),
            limits(maximumNameUTF8Bytes: 0),
            limits(maximumColorTokenUTF8Bytes: 0),
            limits(maximumLineCount: 0),
            limits(maximumLineUTF16Length: -1),
            limits(maximumScopeUTF16Length: -1),
            limits(maximumResultRanges: 0),
            limits(maximumWorkUnits: -1),
            limits(cancellationCheckInterval: 0),
            limits(maximumEncodedBytes: 0)
        ]

        for invalid in invalidLimits {
            assertMarkerError(.invalidLimits) {
                try markers.validate(limits: invalid)
            }
        }
    }

    func testRegularExpressionProgressLimitStopsBacktrackingAndRecovers() throws {
        let pathological = try TextMarkers(markers: [
            NamedTextMarker(
                id: "regex",
                name: "Regex",
                regularExpression: "^(a+)+$"
            )
        ])
        let progressLimits = limits(
            searchLimits: searchLimits(maximumRegularExpressionProgressSteps: 1)
        )
        let rejected = TextMarkerDocument(
            text: String(repeating: "a", count: 64) + "!",
            revision: .init(rawValue: 12)
        )

        assertTextSearchError(.evaluationLimitExceeded(maximumProgressSteps: 1)) {
            _ = try pathological.matches(in: rejected, limits: progressLimits)
        }

        let simple = try TextMarkers(markers: [
            NamedTextMarker(id: "simple", name: "Simple", regularExpression: "a+")
        ])
        let accepted = TextMarkerDocument(text: "aaaa", revision: .init(rawValue: 12))
        XCTAssertEqual(
            try simple.matches(in: accepted, limits: progressLimits).allRanges(in: accepted),
            [markerRange("simple", 0, 4)]
        )
    }

    func testRegularExpressionEvaluationObservesInFlightCancellation() async {
        let marker: NamedTextMarker
        let markers: TextMarkers
        do {
            marker = try NamedTextMarker(
                id: "regex",
                name: "Regex",
                regularExpression: "^(x+)+$"
            )
            markers = try TextMarkers(markers: [marker])
        } catch {
            XCTFail("Fixture creation failed: \(error)")
            return
        }
        let document = TextMarkerDocument(
            text: String(repeating: "x", count: 8_192) + "!",
            revision: .init(rawValue: 13)
        )
        let cancellationLimits = limits(
            searchLimits: searchLimits(
                maximumInputUTF16Length: 10_000,
                maximumRegularExpressionProgressSteps: 10_000_000
            )
        )
        await assertCancellation(
            at: .regularExpressionProgress,
            operation: { try markers.matches(in: document, limits: cancellationLimits) }
        )
    }

    func testLiteralChunkSearchPreservesCrossChunkMatchesAndObservesCancellation() async throws {
        let marker = try NamedTextMarker(
            id: "literal",
            name: "Literal",
            literal: "Caf\u{E9}",
            caseSensitive: false
        )
        let markers = try TextMarkers(markers: [marker])
        let smallDocument = TextMarkerDocument(
            text: "xxxxCAFE\u{301}tail",
            revision: .init(rawValue: 14)
        )
        let chunkedLimits = limits(
            cancellationCheckInterval: 4,
            searchLimits: searchLimits(maximumInputUTF16Length: 100)
        )

        XCTAssertEqual(
            try markers.matches(in: smallDocument, limits: chunkedLimits)
                .allRanges(in: smallDocument),
            [markerRange(marker.id, 4, 5)]
        )

        let largeDocument = TextMarkerDocument(
            text: String(repeating: "x", count: 8 * 1024 * 1024),
            revision: .init(rawValue: 14)
        )
        let cancellationLimits = limits(
            cancellationCheckInterval: 1,
            searchLimits: searchLimits(maximumInputUTF16Length: 8 * 1024 * 1024)
        )
        await assertCancellation(
            at: .literalSearchChunk,
            operation: { try markers.matches(in: largeDocument, limits: cancellationLimits) }
        )
    }

    func testEncodingChecksCancellationAfterLargeEncodeAndRemainsDeterministic() async throws {
        let pattern = String(repeating: "x", count: NamedTextMarker.maximumPatternUTF16Length)
        let markerCount = 8
        let markerValues = try (0..<markerCount).map { index in
            try NamedTextMarker(
                id: "marker-\(index)",
                name: "Marker \(index)",
                literal: pattern
            )
        }
        let markers = try TextMarkers(markers: markerValues)
        await assertCancellation(at: .encoded, operation: { try markers.encodedData() })

        let first = try markers.encodedData()
        let second = try markers.encodedData()
        XCTAssertEqual(first, second)
        XCTAssertLessThanOrEqual(first.count, TextMarkers.maximumEncodedBytes)
        XCTAssertEqual(try TextMarkers.decode(from: first), markers)
    }

    func testDecodingChecksCancellationAfterStrictPreflight() async throws {
        let data = try TextMarkers(markers: [
            NamedTextMarker(id: "one", name: "One", literal: "1")
        ]).encodedData()

        await assertCancellation(
            at: .decodePreflightComplete,
            operation: { try TextMarkers.decode(from: data) }
        )
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }

    private func markerRange(_ markerID: String, _ location: Int, _ length: Int) -> TextMarkerRange {
        TextMarkerRange(markerID: markerID, range: NSRange(location: location, length: length))
    }

    private func assertMarkerError<T>(
        _ expected: TextMarkersError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? TextMarkersError, expected, file: file, line: line)
        }
    }

    private func assertTextSearchError<T>(
        _ expected: TextSearchError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? TextSearchError, expected, file: file, line: line)
        }
    }

    private func assertDecodingFailure(
        _ data: Data,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try TextMarkers.decode(from: data),
            message,
            file: file,
            line: line
        )
    }

    private func assertDecodingError(
        _ data: Data,
        contains expectedDescription: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try TextMarkers.decode(from: data), file: file, line: line) { error in
            guard case .dataCorrupted(let context) = error as? DecodingError else {
                XCTFail("Expected dataCorrupted, got \(error)", file: file, line: line)
                return
            }
            XCTAssertTrue(
                context.debugDescription.contains(expectedDescription),
                "Unexpected decoding error: \(context.debugDescription)",
                file: file,
                line: line
            )
        }
    }

    private func assertCancellation<T: Sendable>(
        at phase: TextMarkersCancellationPhase,
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: @escaping @Sendable () throws -> T
    ) async {
        let barrier = TextMarkersCancellationBarrier(phase: phase)
        let task = Task.detached {
            try TextMarkersTestHooks.$cancellationPhaseHandler.withValue(barrier.handler) {
                try operation()
            }
        }
        guard await barrier.waitUntilReached(timeout: timeout) else {
            task.cancel()
            barrier.release()
            await assertTaskCompletes(task, timeout: timeout, file: file, line: line)
            XCTFail("Cancellation phase was not reached: \(phase)", file: file, line: line)
            return
        }
        task.cancel()
        barrier.release()
        await assertCancellation(task, file: file, line: line)
    }

    private func assertCancellation<T: Sendable>(
        _ task: Task<T, Error>,
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let result = TextMarkersCancellationResult()
        let completed = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                _ = try await task.value
                result.store(.succeeded)
            } catch is CancellationError {
                result.store(.cancelled)
            } catch {
                result.store(.failed(String(describing: error)))
            }
            completed.signal()
        }
        let didComplete = await waitForSemaphore(completed, timeout: timeout)
        guard didComplete else {
            XCTFail("Cancelled operation exceeded bounded timeout", file: file, line: line)
            return
        }
        switch result.load() {
        case .cancelled:
            break
        case .succeeded:
            XCTFail("Cancelled operation unexpectedly succeeded", file: file, line: line)
        case .failed(let description):
            XCTFail("Expected CancellationError, got \(description)", file: file, line: line)
        case .pending:
            XCTFail("Cancelled operation completed without a result", file: file, line: line)
        }
    }

    private func assertTaskCompletes<T: Sendable>(
        _ task: Task<T, Error>,
        timeout: Duration,
        file: StaticString,
        line: UInt
    ) async {
        let completed = DispatchSemaphore(value: 0)
        Task.detached {
            _ = try? await task.value
            completed.signal()
        }
        let didComplete = await waitForSemaphore(completed, timeout: timeout)
        XCTAssertTrue(didComplete, "Task exceeded bounded timeout", file: file, line: line)
    }

    private func replacing(_ root: [String: Any], key: String, value: Any) throws -> Data {
        var replaced = root
        replaced[key] = value
        return try JSONSerialization.data(withJSONObject: replaced)
    }

    private func searchLimits(
        maximumInputUTF16Length: Int = 64 * 1024 * 1024,
        maximumPatternUTF16Length: Int = 64 * 1024,
        maximumOutputUTF16Length: Int = 64 * 1024 * 1024,
        maximumMatches: Int = 100_000,
        maximumMarkers: Int = 256,
        maximumCombinedPatternUTF16Length: Int = 4 * 1024 * 1024,
        maximumReplacementTemplateUTF16Length: Int = 1024 * 1024,
        maximumStoredCaptureRanges: Int = 1_000_000,
        maximumRegularExpressionProgressSteps: Int = 1_000_000
    ) -> TextSearchLimits {
        TextSearchLimits(
            maximumInputUTF16Length: maximumInputUTF16Length,
            maximumPatternUTF16Length: maximumPatternUTF16Length,
            maximumOutputUTF16Length: maximumOutputUTF16Length,
            maximumMatches: maximumMatches,
            maximumMarkers: maximumMarkers,
            maximumCombinedPatternUTF16Length: maximumCombinedPatternUTF16Length,
            maximumReplacementTemplateUTF16Length: maximumReplacementTemplateUTF16Length,
            maximumStoredCaptureRanges: maximumStoredCaptureRanges,
            maximumRegularExpressionProgressSteps: maximumRegularExpressionProgressSteps
        )
    }

    private func limits(
        maximumMarkers: Int = TextMarkers.maximumMarkerCount,
        maximumIdentifierUTF8Bytes: Int = NamedTextMarker.maximumIdentifierUTF8Bytes,
        maximumNameUTF8Bytes: Int = NamedTextMarker.maximumNameUTF8Bytes,
        maximumColorTokenUTF8Bytes: Int = TextMarkerColorToken.maximumUTF8Bytes,
        maximumLineCount: Int = 1_000_000,
        maximumLineUTF16Length: Int = 1024 * 1024,
        maximumScopeUTF16Length: Int = 64 * 1024 * 1024,
        maximumResultRanges: Int = 100_000,
        maximumWorkUnits: Int = 256 * 1024 * 1024,
        cancellationCheckInterval: Int = 4_096,
        maximumEncodedBytes: Int = TextMarkers.maximumEncodedBytes,
        searchLimits: TextSearchLimits = .default
    ) -> TextMarkersLimits {
        TextMarkersLimits(
            maximumMarkers: maximumMarkers,
            maximumIdentifierUTF8Bytes: maximumIdentifierUTF8Bytes,
            maximumNameUTF8Bytes: maximumNameUTF8Bytes,
            maximumColorTokenUTF8Bytes: maximumColorTokenUTF8Bytes,
            maximumLineCount: maximumLineCount,
            maximumLineUTF16Length: maximumLineUTF16Length,
            maximumScopeUTF16Length: maximumScopeUTF16Length,
            maximumResultRanges: maximumResultRanges,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval,
            maximumEncodedBytes: maximumEncodedBytes,
            searchLimits: searchLimits
        )
    }
}

private enum TextMarkersCancellationOutcome {
    case pending
    case succeeded
    case cancelled
    case failed(String)
}

private final class TextMarkersCancellationResult: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome = TextMarkersCancellationOutcome.pending

    func store(_ outcome: TextMarkersCancellationOutcome) {
        lock.lock()
        self.outcome = outcome
        lock.unlock()
    }

    func load() -> TextMarkersCancellationOutcome {
        lock.lock()
        let outcome = outcome
        lock.unlock()
        return outcome
    }
}

private final class TextMarkersCancellationBarrier: @unchecked Sendable {
    private let phase: TextMarkersCancellationPhase
    private let reached = DispatchSemaphore(value: 0)
    private let resume = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didReach = false

    init(phase: TextMarkersCancellationPhase) {
        self.phase = phase
    }

    lazy var handler: @Sendable (TextMarkersCancellationPhase) -> Void = { [weak self] phase in
        guard let self, phase == self.phase else { return }
        self.lock.lock()
        guard !self.didReach else {
            self.lock.unlock()
            return
        }
        self.didReach = true
        self.lock.unlock()
        self.reached.signal()
        _ = self.resume.wait(timeout: .now() + .seconds(5))
    }

    func waitUntilReached(timeout: Duration) async -> Bool {
        await waitForSemaphore(reached, timeout: timeout)
    }

    func release() {
        resume.signal()
    }
}

extension Duration {
    fileprivate var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private func waitForSemaphore(_ semaphore: DispatchSemaphore, timeout: Duration) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(
                returning: semaphore.wait(timeout: .now() + timeout.timeInterval) == .success
            )
        }
    }
}
