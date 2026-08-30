import Foundation
import MacMergeCore
import XCTest

final class DisplayFilterPresetsTests: XCTestCase {
    private static let exactMaximumFixtureWork = 4_315_623
    private static let exactMaximumFixtureEncodedBytes = 1_087_088

    func testDefaultsCollectionsAndPublicLimits() {
        let state = DisplayFilterPresets()
        let limits = DisplayFilterPresetLimits.default

        XCTAssertEqual(DisplayFilterPresets.currentSchemaVersion, 2)
        XCTAssertEqual(DisplayFilterPresets.maximumPresetCount, 100)
        XCTAssertEqual(DisplayFilterPresetHistory.defaultCapacity, 20)
        XCTAssertEqual(DisplayFilterPresetHistory.maximumCapacity, 100)
        XCTAssertEqual(limits.maximumPresetCount, 100)
        XCTAssertEqual(limits.maximumHistoryEntries, 100)
        XCTAssertEqual(limits.maximumPresetNameUTF8Bytes, 256)
        XCTAssertEqual(limits.maximumTotalPresetNameUTF8Bytes, 16 * 1_024)
        XCTAssertEqual(limits.maximumExpressionUTF8Bytes, 12_288)
        XCTAssertEqual(limits.maximumTotalExpressionUTF8Bytes, 1_024 * 1_024)
        XCTAssertEqual(limits.maximumInputBytes, 2 * 1_024 * 1_024)
        XCTAssertEqual(limits.maximumOutputBytes, 2 * 1_024 * 1_024)
        XCTAssertEqual(limits.maximumWork, 8 * 1_024 * 1_024)
        XCTAssertTrue(state.isEmpty)
        XCTAssertEqual(state.startIndex, 0)
        XCTAssertEqual(state.endIndex, 0)
        XCTAssertEqual(state.activeFilter, DisplayFilterPreset.allRows.filter)
        XCTAssertEqual(state.activeExpression, .literal(""))
        XCTAssertEqual(state.recentHistory.capacity, 20)
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertNil(state.selectedPresetName)
        XCTAssertNil(state.selectedPreset)
        XCTAssertEqual(state.version, 0)
        requireSendable(state)
        requireSendable(limits)
        requireSendable(DisplayFilterPresetsError.invalidJSON)
    }

    func testAddCanonicalizesNamesRejectsCanonicalDuplicatesAndAdvancesVersion() throws {
        let decomposedName = "  Caf\u{0065}\u{0301}  \n"
        let composedName = "Caf\u{00E9}"
        let storedFilter = filter("needle", caseSensitive: true)
        var state = DisplayFilterPresets()

        XCTAssertTrue(try state.add(name: decomposedName, filter: storedFilter, expectedVersion: 0))
        XCTAssertEqual(state.version, 1)
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(state[0].name, composedName)
        XCTAssertEqual(Array(state[0].name.utf8), Array(composedName.utf8))
        XCTAssertEqual(state[0].id, composedName)
        XCTAssertEqual(state[0].filter, storedFilter)

        let beforeDuplicate = state
        assertPresetsError(.duplicatePresetName("CAF\u{00C9}")) {
            try state.add(name: " caf\u{0065}\u{0301} ".uppercased(), filter: filter("other"))
        }
        XCTAssertEqual(state, beforeDuplicate)

        assertPresetsError(.emptyPresetName) {
            try state.add(name: " \t\n ", filter: storedFilter)
        }
        assertPresetsError(.invalidPresetName("bad\u{0000}name")) {
            try state.add(name: "bad\u{0000}name", filter: storedFilter)
        }
        XCTAssertEqual(state, beforeDuplicate)
    }

    func testUpdateRenamesSelectedPresetAndClearsSelectionWhenFilterChanges() async throws {
        let first = filter("first")
        let replacement = filter("replacement", invert: true, predicate: .significant)
        var state = DisplayFilterPresets()
        try state.add(name: "Original", filter: first)
        _ = try await state.select(named: "original", applying: { _ in })
        XCTAssertEqual(state.version, 2)
        XCTAssertEqual(state.selectedPresetName, "Original")

        XCTAssertTrue(
            try state.update(
                named: " ORIGINAL ",
                newName: " Renamed ",
                filter: first,
                expectedVersion: 2
            )
        )
        XCTAssertEqual(state.version, 3)
        XCTAssertEqual(state.selectedPresetName, "Renamed")
        XCTAssertEqual(state.selectedPreset?.name, "Renamed")
        XCTAssertEqual(state.activeFilter, first)

        let beforeNoOp = state
        XCTAssertFalse(try state.update(named: "renamed", newName: "Renamed", filter: first))
        XCTAssertEqual(state, beforeNoOp)

        XCTAssertTrue(try state.update(named: "renamed", filter: replacement))
        XCTAssertEqual(state.version, 4)
        XCTAssertNil(state.selectedPresetName)
        XCTAssertNil(state.selectedPreset)
        XCTAssertEqual(state.activeFilter, first)
        XCTAssertEqual(state[0].filter, replacement)

        let beforeMissing = state
        assertPresetsError(.presetNotFound("Missing")) {
            try state.update(named: "Missing", filter: first)
        }
        XCTAssertEqual(state, beforeMissing)
    }

    func testRemoveAndHistoryMutationsHaveNoOpAndVersionSemantics() async throws {
        let first = filter("first")
        let second = filter("second")
        var state = DisplayFilterPresets(historyCapacity: 3)
        try state.add(name: "First", filter: first)
        try state.add(name: "Second", filter: second)
        _ = try await state.select(named: "First", applying: { _ in })
        _ = try await state.select(named: "Second", applying: { _ in })
        XCTAssertEqual(state.version, 4)
        XCTAssertEqual(state.recentHistory.entries, [second, first])

        XCTAssertFalse(try state.remove(named: "Missing"))
        XCTAssertEqual(state.version, 4)
        XCTAssertTrue(try state.remove(named: "Second"))
        XCTAssertEqual(state.version, 5)
        XCTAssertNil(state.selectedPresetName)
        XCTAssertEqual(state.activeFilter, second)

        XCTAssertFalse(try state.removeFromHistory(filter("absent")))
        XCTAssertEqual(state.version, 5)
        XCTAssertTrue(try state.removeFromHistory(first))
        XCTAssertEqual(state.version, 6)
        XCTAssertEqual(state.recentHistory.entries, [second])
        XCTAssertTrue(try state.clearHistory())
        XCTAssertEqual(state.version, 7)
        XCTAssertTrue(state.recentHistory.isEmpty)
        XCTAssertEqual(state.recentHistory.capacity, 3)
        XCTAssertFalse(try state.clearHistory())
        XCTAssertEqual(state.version, 7)
    }

    func testSelectAndActiveMutationsMaintainSelectionAndExactMRUOrder() async throws {
        let first = filter("first")
        let second = filter("second", caseSensitive: true)
        let manual = filter("manual", invert: true)
        let recorder = FilterApplyRecorder()
        var state = DisplayFilterPresets(historyCapacity: 2)
        try state.add(name: "First", filter: first)
        try state.add(name: "Second", filter: second)

        let selectedFirst = try await state.select(named: "first", applying: recorder.handler)
        XCTAssertTrue(selectedFirst)
        XCTAssertEqual(state.selectedPresetName, "First")
        XCTAssertEqual(state.recentHistory.entries, [first])
        let selectedSecond = try await state.select(named: "SECOND", applying: recorder.handler)
        XCTAssertTrue(selectedSecond)
        XCTAssertEqual(state.selectedPresetName, "Second")
        XCTAssertEqual(state.recentHistory.entries, [second, first])
        let reselectedFirst = try await state.select(named: "First", applying: recorder.handler)
        XCTAssertTrue(reselectedFirst)
        XCTAssertEqual(state.recentHistory.entries, [first, second])

        let beforeNoOp = state
        let selectedFirstAgain = try await state.select(named: "First", applying: recorder.handler)
        XCTAssertFalse(selectedFirstAgain)
        XCTAssertEqual(state, beforeNoOp)
        XCTAssertEqual(recorder.filters.count, 3)

        let changedExpression = try await state.setActiveExpression(
            manual.expression,
            applying: recorder.handler
        )
        XCTAssertTrue(changedExpression)
        XCTAssertNil(state.selectedPresetName)
        XCTAssertEqual(state.activeFilter, filter("manual"))
        XCTAssertEqual(state.recentHistory.entries, [filter("manual"), first])

        let changedFilter = try await state.setActiveFilter(manual, applying: recorder.handler)
        XCTAssertTrue(changedFilter)
        XCTAssertEqual(state.activeFilter, manual)
        XCTAssertEqual(state.recentHistory.entries, [manual, filter("manual")])
        let changedFilterAgain = try await state.setActiveFilter(
            manual,
            applying: recorder.handler
        )
        XCTAssertFalse(changedFilterAgain)
        XCTAssertEqual(recorder.filters.count, 5)
    }

    func testSelectingSharedFilterChangesOnlySelectionIdentityAndVersion() async throws {
        let shared = filter("shared", caseSensitive: true, invert: true, predicate: .significant)
        let recorder = FilterApplyRecorder()
        var state = DisplayFilterPresets(historyCapacity: 2)
        try state.add(name: "First", filter: shared)
        try state.add(name: "Second", filter: shared)

        let selectedFirst = try await state.select(named: "First", applying: recorder.handler)
        XCTAssertTrue(selectedFirst)
        let historyAfterFirstSelection = state.recentHistory
        let versionAfterFirstSelection = state.version
        XCTAssertEqual(recorder.filters.count, 1)

        let selectedSecond = try await state.select(named: "Second", applying: recorder.handler)
        XCTAssertTrue(selectedSecond)
        XCTAssertEqual(state.selectedPresetName, "Second")
        XCTAssertEqual(state.selectedPreset?.name, "Second")
        assertExactFilter(state.activeFilter, shared)
        XCTAssertEqual(state.recentHistory, historyAfterFirstSelection)
        XCTAssertEqual(state.version, versionAfterFirstSelection + 1)
        XCTAssertEqual(recorder.filters.count, 1)

        let beforeNoOp = state
        let selectedSecondAgain = try await state.select(
            named: "Second",
            applying: recorder.handler
        )
        XCTAssertFalse(selectedSecondAgain)
        XCTAssertEqual(state, beforeNoOp)
        XCTAssertEqual(recorder.filters.count, 1)
    }

    func testSetActiveExpressionPreservesNondefaultFilterFlags() async throws {
        let recorder = FilterApplyRecorder()
        let initial = filter(
            "literal",
            caseSensitive: true,
            invert: true,
            predicate: .unchanged
        )
        let expected = filter(
            "^changed+$",
            regularExpression: true,
            caseSensitive: true,
            invert: true,
            predicate: .unchanged
        )
        var state = DisplayFilterPresets(historyCapacity: 2)

        let changedFilter = try await state.setActiveFilter(
            initial,
            applying: recorder.handler
        )
        XCTAssertTrue(changedFilter)
        let changedExpression = try await state.setActiveExpression(
            expected.expression,
            applying: recorder.handler
        )
        XCTAssertTrue(changedExpression)

        assertExactFilter(state.activeFilter, expected)
        XCTAssertEqual(state.recentHistory.count, 2)
        assertExactFilter(state.recentHistory[0], expected)
        assertExactFilter(state.recentHistory[1], initial)
        XCTAssertEqual(recorder.filters.count, 2)
        assertExactFilter(recorder.filters[0], initial)
        assertExactFilter(recorder.filters[1], expected)
    }

    func testResetRetainsOrRemovesPresetsAndAppliesOnlyFilterChanges() async throws {
        let recorder = FilterApplyRecorder()
        let active = filter("active")
        var state = DisplayFilterPresets(historyCapacity: 2)
        try state.add(name: "Active", filter: active)
        try state.add(name: "Other", filter: filter("other"))
        _ = try await state.select(named: "Active", applying: recorder.handler)

        let retainedReset = try await state.reset(
            keepingPresets: true,
            applying: recorder.handler
        )
        XCTAssertTrue(retainedReset)
        XCTAssertEqual(state.version, 4)
        XCTAssertEqual(state.count, 2)
        XCTAssertEqual(state.activeFilter, DisplayFilterPreset.allRows.filter)
        XCTAssertTrue(state.recentHistory.isEmpty)
        XCTAssertNil(state.selectedPresetName)
        XCTAssertEqual(recorder.filters, [active, DisplayFilterPreset.allRows.filter])

        let retainedResetAgain = try await state.reset(
            keepingPresets: true,
            applying: recorder.handler
        )
        XCTAssertFalse(retainedResetAgain)
        XCTAssertEqual(state.version, 4)
        let removingReset = try await state.reset(applying: recorder.handler)
        XCTAssertTrue(removingReset)
        XCTAssertEqual(state.version, 5)
        XCTAssertTrue(state.isEmpty)
        XCTAssertEqual(recorder.filters.count, 2, "Preset-only reset must not reapply an unchanged filter")
        let removingResetAgain = try await state.reset(applying: recorder.handler)
        XCTAssertFalse(removingResetAgain)
    }

    func testExpectedVersionAndVersionExhaustionAreAtomic() throws {
        var state = DisplayFilterPresets()
        let original = state
        assertPresetsError(.staleVersion(expected: 1, actual: 0)) {
            try state.add(name: "Stale", filter: filter("stale"), expectedVersion: 1)
        }
        XCTAssertEqual(state, original)

        XCTAssertTrue(try state.add(name: "Current", filter: filter("current"), expectedVersion: 0))
        let current = state
        assertPresetsError(.staleVersion(expected: 0, actual: 1)) {
            try state.remove(named: "Current", expectedVersion: 0)
        }
        XCTAssertEqual(state, current)

        var exhausted = try DisplayFilterPresets(presets: [], version: UInt64.max)
        XCTAssertFalse(try exhausted.remove(named: "Missing"))
        let beforeExhaustion = exhausted
        assertPresetsError(.versionExhausted) {
            try exhausted.add(name: "Impossible", filter: filter("value"))
        }
        XCTAssertEqual(exhausted, beforeExhaustion)
    }

    func testStaleAndExhaustedAsyncSelectionInvokeNoApplyCallbacks() async throws {
        let selectedFilter = filter("selected")
        let preset = try NamedDisplayFilterPreset(name: "Selected", filter: selectedFilter)
        let recorder = FilterApplyRecorder()
        var stale = try DisplayFilterPresets(presets: [preset], version: 7)
        let beforeStale = stale

        do {
            _ = try await stale.select(
                named: "Selected",
                applying: recorder.handler,
                expectedVersion: 6
            )
            XCTFail("Expected stale version")
        } catch let error as DisplayFilterPresetsError {
            XCTAssertEqual(error, .staleVersion(expected: 6, actual: 7))
        }
        XCTAssertEqual(stale, beforeStale)
        XCTAssertTrue(recorder.filters.isEmpty)

        var exhausted = try DisplayFilterPresets(
            presets: [preset],
            version: UInt64.max
        )
        let beforeExhaustion = exhausted
        do {
            _ = try await exhausted.select(named: "Selected", applying: recorder.handler)
            XCTFail("Expected version exhaustion")
        } catch let error as DisplayFilterPresetsError {
            XCTAssertEqual(error, .versionExhausted)
        }
        XCTAssertEqual(exhausted, beforeExhaustion)
        XCTAssertTrue(recorder.filters.isEmpty)
    }

    func testNamedPresetsAndHistoryUseExactUTF8FilterIdentity() throws {
        let composedText = "caf\u{00E9}"
        let decomposedText = "caf\u{0065}\u{0301}"
        XCTAssertEqual(composedText, decomposedText)
        XCTAssertNotEqual(Array(composedText.utf8), Array(decomposedText.utf8))
        let composedFilter = filter(composedText)
        let decomposedFilter = filter(decomposedText)
        XCTAssertEqual(composedFilter, decomposedFilter, "Swift String equality is canonically equivalent")

        let composedPreset = try NamedDisplayFilterPreset(name: "Same", filter: composedFilter)
        let decomposedPreset = try NamedDisplayFilterPreset(name: "Same", filter: decomposedFilter)
        XCTAssertFalse(composedPreset == decomposedPreset)
        XCTAssertEqual(Set([composedPreset, decomposedPreset]).count, 2)
        XCTAssertNotEqual(composedPreset, try NamedDisplayFilterPreset(name: "Same", filter: filter(composedText, regularExpression: true)))

        let history = try DisplayFilterPresetHistory([composedFilter, decomposedFilter], capacity: 2)
        XCTAssertEqual(history.count, 2)
        assertExactFilter(history[0], composedFilter)
        assertExactFilter(history[1], decomposedFilter)
        XCTAssertNotEqual(
            history,
            try DisplayFilterPresetHistory([decomposedFilter, composedFilter], capacity: 2)
        )
        XCTAssertThrowsError(
            try DisplayFilterPresetHistory([composedFilter, composedFilter], capacity: 2)
        ) { error in
            XCTAssertEqual(error as? DisplayFilterError, .duplicateHistoryEntry)
        }
    }

    func testEqualLengthReorderedCombiningSequencesUseExactFilterIdentity() async throws {
        let acuteThenCedilla = "a\u{0301}\u{0327}"
        let cedillaThenAcute = "a\u{0327}\u{0301}"
        XCTAssertEqual(acuteThenCedilla, cedillaThenAcute)
        XCTAssertEqual(acuteThenCedilla.utf8.count, cedillaThenAcute.utf8.count)
        XCTAssertNotEqual(Array(acuteThenCedilla.utf8), Array(cedillaThenAcute.utf8))

        let first = filter(acuteThenCedilla)
        let second = filter(cedillaThenAcute)
        let firstPreset = try NamedDisplayFilterPreset(name: "Same", filter: first)
        let secondPreset = try NamedDisplayFilterPreset(name: "Same", filter: second)
        XCTAssertNotEqual(firstPreset, secondPreset)
        XCTAssertEqual(Set([firstPreset, secondPreset]).count, 2)

        let recorder = FilterApplyRecorder()
        var state = DisplayFilterPresets(historyCapacity: 2)
        let selectedFirst = try await state.setActiveFilter(first, applying: recorder.handler)
        let selectedSecond = try await state.setActiveFilter(second, applying: recorder.handler)
        XCTAssertTrue(selectedFirst)
        XCTAssertTrue(selectedSecond)
        XCTAssertEqual(state.version, 2)
        XCTAssertEqual(recorder.filters.count, 2)
        XCTAssertEqual(state.recentHistory.count, 2)
        assertExactFilter(state.activeFilter, second)
        assertExactFilter(state.recentHistory[0], second)
        assertExactFilter(state.recentHistory[1], first)
    }

    func testCanonicalEquivalentExpressionBytesRemainDistinctThroughHistoryAndRoundTrip() async throws {
        let composed = filter("caf\u{00E9}")
        let decomposed = filter("caf\u{0065}\u{0301}")
        let recorder = FilterApplyRecorder()
        var state = DisplayFilterPresets(historyCapacity: 3)
        try state.add(name: "Composed", filter: composed)
        try state.add(name: "Decomposed", filter: decomposed)

        let selectedDecomposed = try await state.select(
            named: "Decomposed",
            applying: recorder.handler
        )
        let selectedComposed = try await state.select(
            named: "Composed",
            applying: recorder.handler
        )
        XCTAssertTrue(selectedDecomposed)
        XCTAssertTrue(selectedComposed)
        XCTAssertEqual(state.recentHistory.count, 2)
        assertExactFilter(state.recentHistory[0], composed)
        assertExactFilter(state.recentHistory[1], decomposed)

        XCTAssertTrue(try state.removeFromHistory(decomposed))
        XCTAssertEqual(state.recentHistory.count, 1)
        assertExactFilter(state.recentHistory[0], composed)

        let data = try state.encodedData()
        let decoded = try DisplayFilterPresets.decode(from: data)
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(try decoded.encodedData(), data)
        assertExactFilter(decoded.presets[0].filter, composed)
        assertExactFilter(decoded.presets[1].filter, decomposed)
    }

    func testCanonicalEquivalentNamesCollapseToStoredNFCIdentity() throws {
        let composedName = "R\u{00E9}sum\u{00E9}"
        let decomposedName = "R\u{0065}\u{0301}sum\u{0065}\u{0301}"
        let preset = try NamedDisplayFilterPreset(name: " \(decomposedName) ", filter: filter("value"))
        XCTAssertEqual(Array(preset.name.utf8), Array(composedName.utf8))

        var state = DisplayFilterPresets()
        try state.add(preset)
        let beforeDuplicate = state
        assertPresetsError(.duplicatePresetName(composedName.uppercased())) {
            try state.add(name: composedName.uppercased(), filter: filter("other"))
        }
        XCTAssertEqual(state, beforeDuplicate)
    }

    func testSchemaVersionOneMigratesWithoutInferringSelection() throws {
        let chosenFilter = filter("chosen", caseSensitive: true, predicate: .unchanged)
        let preset = try NamedDisplayFilterPreset(name: "Chosen", filter: chosenFilter)
        let history = try DisplayFilterPresetHistory([chosenFilter], capacity: 3)
        let selected = try DisplayFilterPresets(
            presets: [preset],
            activeFilter: chosenFilter,
            recentHistory: history,
            selectedPresetName: "Chosen",
            version: 41
        )
        var versionOneJSON = String(decoding: try selected.encodedData(), as: UTF8.self)
        versionOneJSON = versionOneJSON.replacingOccurrences(of: #""schemaVersion":2"#, with: #""schemaVersion":1"#)

        assertPresetsError(.unknownField("selectedPresetName")) {
            _ = try DisplayFilterPresets.decode(from: Data(versionOneJSON.utf8))
        }

        versionOneJSON = versionOneJSON.replacingOccurrences(of: #", "selectedPresetName":"Chosen""#.replacingOccurrences(of: " ", with: ""), with: "")

        let migrated = try DisplayFilterPresets.decode(from: Data(versionOneJSON.utf8))
        XCTAssertEqual(migrated.presets, selected.presets)
        assertExactFilter(migrated.activeFilter, chosenFilter)
        XCTAssertEqual(migrated.recentHistory, history)
        XCTAssertEqual(migrated.version, 41)
        XCTAssertNil(migrated.selectedPresetName)
        XCTAssertNil(migrated.selectedPreset)

        let migratedJSON = String(decoding: try migrated.encodedData(), as: UTF8.self)
        XCTAssertTrue(migratedJSON.contains(#""schemaVersion":2"#))
        XCTAssertTrue(migratedJSON.contains(#""selectedPresetName":null"#))
    }

    func testRegularExpressionRoundTripPreservesFlagsAndExactExpressionBytes() throws {
        let expression = "(?m)^caf\u{0065}\u{0301}\\p{L}+$"
        let storedFilter = filter(
            expression,
            regularExpression: true,
            caseSensitive: true,
            invert: true,
            predicate: .unchanged
        )
        let preset = try NamedDisplayFilterPreset(name: "Regex", filter: storedFilter)
        let history = try DisplayFilterPresetHistory([storedFilter], capacity: 1)
        let state = try DisplayFilterPresets(
            presets: [preset],
            activeFilter: storedFilter,
            recentHistory: history,
            selectedPresetName: "Regex",
            version: 19
        )

        let data = try state.encodedData()
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""kind":"regularExpression""#))
        XCTAssertTrue(json.contains(#""caseSensitive":true"#))
        XCTAssertTrue(json.contains(#""invert":true"#))
        XCTAssertTrue(json.contains(#""predicate":"unchanged""#))

        let decoded = try DisplayFilterPresets.decode(from: data)
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(try decoded.encodedData(), data)
        assertExactFilter(decoded.activeFilter, storedFilter)
        assertExactFilter(decoded.presets[0].filter, storedFilter)
        assertExactFilter(decoded.recentHistory[0], storedFilter)
        XCTAssertEqual(Array(decoded.activeExpression.text.utf8), Array(expression.utf8))
    }

    func testSchemaVersionTwoNilSelectionAndSelectionValidation() throws {
        let emptyData = try DisplayFilterPresets().encodedData()
        let emptyJSON = String(decoding: emptyData, as: UTF8.self)
        XCTAssertTrue(emptyJSON.contains(#""selectedPresetName":null"#))
        XCTAssertNil(try DisplayFilterPresets.decode(from: emptyData).selectedPresetName)

        let chosenFilter = filter("chosen")
        let preset = try NamedDisplayFilterPreset(name: "Chosen", filter: chosenFilter)
        let selected = try DisplayFilterPresets(
            presets: [preset],
            activeFilter: chosenFilter,
            selectedPresetName: " chosen "
        )
        XCTAssertEqual(selected.selectedPresetName, "Chosen")

        assertPresetsError(.presetNotFound("Missing")) {
            _ = try DisplayFilterPresets(
                presets: [preset],
                activeFilter: chosenFilter,
                selectedPresetName: "Missing"
            )
        }
        assertPresetsError(.selectedPresetFilterMismatch("Chosen")) {
            _ = try DisplayFilterPresets(
                presets: [preset],
                activeFilter: filter("different"),
                selectedPresetName: "Chosen"
            )
        }

        let missingSelection = replacing(#", "selectedPresetName":null"#.replacingOccurrences(of: " ", with: ""), with: "", in: emptyData)
        XCTAssertThrowsError(try DisplayFilterPresets.decode(from: missingSelection)) { error in
            XCTAssertTrue(error is DecodingError)
        }

        let mismatchedSelection = replacing(#""selectedPresetName":"Chosen""#, with: #""selectedPresetName":"chosen""#, in: try selected.encodedData())
        assertPresetsError(.presetNotFound("chosen")) {
            _ = try DisplayFilterPresets.decode(from: mismatchedSelection)
        }
    }

    func testCanonicalEquivalentSelectedFilterBytesMustMatchExactly() throws {
        let composedText = "caf\u{00E9}"
        let decomposedText = "caf\u{0065}\u{0301}"
        XCTAssertEqual(composedText, decomposedText)
        let composedFilter = filter(composedText)
        let decomposedFilter = filter(decomposedText)
        let preset = try NamedDisplayFilterPreset(name: "Chosen", filter: composedFilter)

        assertPresetsError(.selectedPresetFilterMismatch("Chosen")) {
            _ = try DisplayFilterPresets(
                presets: [preset],
                activeFilter: decomposedFilter,
                selectedPresetName: "Chosen"
            )
        }

        let selected = try DisplayFilterPresets(
            presets: [preset],
            activeFilter: composedFilter,
            selectedPresetName: "Chosen"
        )
        let mismatchedData = replacing(
            composedText,
            with: decomposedText,
            in: try selected.encodedData()
        )
        assertPresetsError(.selectedPresetFilterMismatch("Chosen")) {
            _ = try DisplayFilterPresets.decode(from: mismatchedData)
        }
    }

    func testLowHistoryLimitUsesCapacityOneAndRejectsLargerPersistedCapacity() async throws {
        let limits = DisplayFilterPresetLimits(maximumHistoryEntries: 1)
        var state = DisplayFilterPresets(limits: limits)
        XCTAssertEqual(state.recentHistory.capacity, 1)

        _ = try await state.setActiveFilter(filter("first"), applying: { _ in })
        _ = try await state.setActiveFilter(filter("second"), applying: { _ in })
        XCTAssertEqual(state.recentHistory.count, 1)
        assertExactFilter(state.recentHistory[0], filter("second"))
        XCTAssertEqual(try DisplayFilterPresets.decode(from: state.encodedData(), limits: limits), state)

        let capacityTwo = DisplayFilterPresets(historyCapacity: 2)
        let capacityTwoData = try capacityTwo.encodedData()
        assertPresetsError(.invalidHistoryCapacity(2)) {
            _ = try DisplayFilterPresets.decode(from: capacityTwoData, limits: limits)
        }
        assertPresetsError(.invalidHistoryCapacity(2)) {
            _ = try DisplayFilterPresets(
                presets: [],
                recentHistory: DisplayFilterPresetHistory(capacity: 2),
                limits: limits
            )
        }
    }

    func testMaximumHundredPresetsAndHistoryRoundTripAtExactWorkBoundary() throws {
        let exactLimits = DisplayFilterPresetLimits(maximumWork: Self.exactMaximumFixtureWork)
        let state = try maximumFixture(limits: exactLimits)
        XCTAssertEqual(state.presets.count, 100)
        XCTAssertEqual(state.recentHistory.count, 100)
        XCTAssertEqual(state.recentHistory.capacity, 100)

        let data = try state.encodedData()
        XCTAssertEqual(data.count, Self.exactMaximumFixtureEncodedBytes)
        let decoded = try DisplayFilterPresets.decode(from: data, limits: exactLimits)
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(try decoded.encodedData(), data)

        let insufficientLimits = DisplayFilterPresetLimits(maximumWork: Self.exactMaximumFixtureWork - 1)
        let insufficientState = try maximumFixture(limits: insufficientLimits)
        assertPresetsError(.workLimitExceeded(maximumWork: Self.exactMaximumFixtureWork - 1)) {
            _ = try insufficientState.encodedData()
        }
        assertPresetsError(.workLimitExceeded(maximumWork: Self.exactMaximumFixtureWork - 1)) {
            _ = try DisplayFilterPresets.decode(from: data, limits: insufficientLimits)
        }
    }

    func testApplyFailureRollsBackExternalStateAndLeavesPresetStateAtomic() async throws {
        let applicationError = IdentityError()
        let recorder = FilterApplyRecorder()
        let selectedFilter = filter("selected")
        var state = DisplayFilterPresets()
        try state.add(name: "Selected", filter: selectedFilter)
        let before = state

        do {
            _ = try await state.select(named: "Selected") { applied in
                let invocation = recorder.record(applied)
                if invocation == 1 { throw applicationError }
            }
            XCTFail("Expected application failure")
        } catch let error as IdentityError {
            XCTAssertTrue(error === applicationError)
        } catch {
            XCTFail("Expected original application error, got \(error)")
        }

        XCTAssertEqual(state, before)
        XCTAssertEqual(recorder.filters.count, 2)
        assertExactFilter(recorder.filters[0], selectedFilter)
        assertExactFilter(recorder.filters[1], before.activeFilter)
    }

    func testPostApplyCancellationRollsBackInUncancelledTaskAndLeavesStateAtomic() async throws {
        let recorder = FilterApplyRecorder()
        let selectedFilter = filter("selected")
        var initial = DisplayFilterPresets()
        try initial.add(name: "Selected", filter: selectedFilter)

        let outcome = await Task.detached {
            @Sendable [initial, recorder] () -> (
                state: DisplayFilterPresets, cancelled: Bool, unexpected: String?
            ) in
            var state = initial
            do {
                _ = try await state.select(named: "Selected") { applied in
                    if recorder.record(applied) == 1 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
                return (state, false, "Selection unexpectedly succeeded")
            } catch is CancellationError {
                return (state, true, nil)
            } catch {
                return (state, false, String(describing: error))
            }
        }.value

        XCTAssertTrue(outcome.cancelled, outcome.unexpected ?? "Expected cancellation")
        XCTAssertNil(outcome.unexpected)
        XCTAssertEqual(outcome.state, initial)
        XCTAssertEqual(recorder.filters.count, 2)
        assertExactFilter(recorder.filters[0], selectedFilter)
        assertExactFilter(recorder.filters[1], initial.activeFilter)
        XCTAssertEqual(recorder.taskCancellationStates, [false, false])
    }

    func testRollbackFailurePreservesApplicationAndRollbackErrorIdentities() async throws {
        let applicationError = IdentityError()
        let rollbackError = IdentityError()
        let recorder = FilterApplyRecorder()
        let selectedFilter = filter("selected")
        var state = DisplayFilterPresets()
        try state.add(name: "Selected", filter: selectedFilter)
        let before = state

        do {
            _ = try await state.select(named: "Selected") { applied in
                if recorder.record(applied) == 1 {
                    throw applicationError
                }
                throw rollbackError
            }
            XCTFail("Expected rollback failure")
        } catch let error as DisplayFilterPresetsRollbackError {
            guard let actualApplicationError = error.applicationError as? IdentityError,
                let actualRollbackError = error.rollbackError as? IdentityError
            else {
                return XCTFail("Rollback error did not preserve concrete failures")
            }
            XCTAssertTrue(actualApplicationError === applicationError)
            XCTAssertTrue(actualRollbackError === rollbackError)
        } catch {
            XCTFail("Expected DisplayFilterPresetsRollbackError, got \(error)")
        }

        XCTAssertEqual(state, before)
        XCTAssertEqual(recorder.filters.count, 2)
        assertExactFilter(recorder.filters[0], selectedFilter)
        assertExactFilter(recorder.filters[1], before.activeFilter)
    }

    func testConfiguredPresetNameAndCountBoundsFailAtomically() throws {
        var nameLimited = DisplayFilterPresets(
            limits: DisplayFilterPresetLimits(maximumPresetNameUTF8Bytes: 3)
        )
        let emptyNameLimited = nameLimited
        assertPresetsError(.presetNameTooLarge(maximumBytes: 3)) {
            try nameLimited.add(name: "four", filter: filter(""))
        }
        XCTAssertEqual(nameLimited, emptyNameLimited)

        let aggregateLimits = DisplayFilterPresetLimits(
            maximumPresetCount: 2,
            maximumPresetNameUTF8Bytes: 3,
            maximumTotalPresetNameUTF8Bytes: 4
        )
        var aggregateLimited = DisplayFilterPresets(limits: aggregateLimits)
        try aggregateLimited.add(name: "abc", filter: filter(""))
        let beforeAggregateFailure = aggregateLimited
        assertPresetsError(.totalPresetNamesTooLarge(maximumBytes: 4)) {
            try aggregateLimited.add(name: "de", filter: filter(""))
        }
        XCTAssertEqual(aggregateLimited, beforeAggregateFailure)

        var countLimited = DisplayFilterPresets(
            limits: DisplayFilterPresetLimits(maximumPresetCount: 1)
        )
        try countLimited.add(name: "One", filter: filter("one"))
        let beforeCountFailure = countLimited
        assertPresetsError(.tooManyPresets(maximumCount: 1)) {
            try countLimited.add(name: "Two", filter: filter("two"))
        }
        XCTAssertEqual(countLimited, beforeCountFailure)
    }

    func testConfiguredExpressionAndFilterBoundsFailAtomically() throws {
        var expressionLimited = DisplayFilterPresets(
            limits: DisplayFilterPresetLimits(maximumExpressionUTF8Bytes: 3)
        )
        let emptyExpressionLimited = expressionLimited
        assertPresetsError(.expressionTooLarge(maximumBytes: 3)) {
            try expressionLimited.add(name: "Large", filter: filter("four"))
        }
        XCTAssertEqual(expressionLimited, emptyExpressionLimited)

        var aggregateLimited = DisplayFilterPresets(
            limits: DisplayFilterPresetLimits(maximumTotalExpressionUTF8Bytes: 3)
        )
        try aggregateLimited.add(name: "One", filter: filter("12"))
        let beforeAggregateFailure = aggregateLimited
        assertPresetsError(.totalExpressionsTooLarge(maximumBytes: 3)) {
            try aggregateLimited.add(name: "Two", filter: filter("34"))
        }
        XCTAssertEqual(aggregateLimited, beforeAggregateFailure)

        var invalidFilterState = DisplayFilterPresets()
        let invalidFilter = filter("[", regularExpression: true)
        assertPresetsError(.invalidFilter(.invalidRegularExpression("["))) {
            try invalidFilterState.add(name: "Invalid", filter: invalidFilter)
        }
        XCTAssertEqual(invalidFilterState, DisplayFilterPresets())
    }

    func testHistoryInitializerRejectsInvalidCapacityCountFilterAndExactDuplicate() throws {
        for capacity in [0, DisplayFilterPresetHistory.maximumCapacity + 1] {
            XCTAssertThrowsError(try DisplayFilterPresetHistory([], capacity: capacity)) { error in
                XCTAssertEqual(error as? DisplayFilterError, .invalidHistoryCapacity(capacity))
            }
        }

        XCTAssertThrowsError(
            try DisplayFilterPresetHistory([filter("one"), filter("two")], capacity: 1)
        ) { error in
            XCTAssertEqual(error as? DisplayFilterError, .tooManyHistoryEntries(maximumEntries: 1))
        }
        XCTAssertThrowsError(
            try DisplayFilterPresetHistory([filter("[", regularExpression: true)], capacity: 1)
        ) { error in
            XCTAssertEqual(error as? DisplayFilterError, .invalidRegularExpression("["))
        }
        XCTAssertThrowsError(
            try DisplayFilterPresetHistory([filter("same"), filter("same")], capacity: 2)
        ) { error in
            XCTAssertEqual(error as? DisplayFilterError, .duplicateHistoryEntry)
        }
    }

    func testDecodeRejectsMalformedJSONWithoutTrapping() throws {
        let valid = try DisplayFilterPresets().encodedData()
        let malformed = [
            Data(),
            Data("{".utf8),
            Data("[0,]".utf8),
            Data([0xFF]),
            valid + Data(" trailing".utf8),
            replacing(#""literal""#, with: #""lit\qeral""#, in: valid)
        ]

        for payload in malformed {
            assertPresetsError(.invalidJSON, context: String(decoding: payload.prefix(80), as: UTF8.self)) {
                _ = try DisplayFilterPresets.decode(from: payload)
            }
        }
        for payload in [Data("null".utf8), Data("[]".utf8), Data("true".utf8)] {
            XCTAssertThrowsError(try DisplayFilterPresets.decode(from: payload))
        }
    }

    func testDecodeRejectsMalformedLiteralsAndNumbersAtScanner() {
        let malformed = [
            "tru", "truee", "fals", "falsex", "nul", "nullx",
            "-", "+1", ".1", "01", "00", "1.", "1e", "1e+", "1e-", "--1"
        ]

        for source in malformed {
            assertPresetsError(.invalidJSON, context: source) {
                _ = try DisplayFilterPresets.decode(from: Data(source.utf8))
            }
        }
    }

    func testDecodeRejectsLiteralAndEscapedEquivalentDuplicateJSONKeys() throws {
        let valid = try DisplayFilterPresets().encodedData()
        let payloads: [(Data, String)] = [
            (
                replacing(#""schemaVersion":2"#, with: #""schemaVersion":2,"schemaVersion":2"#, in: valid),
                "schemaVersion"
            ),
            (
                replacing(#""schemaVersion":2"#, with: #""schemaVersion":2,"schema\u0056ersion":2"#, in: valid),
                "schemaVersion"
            ),
            (
                replacing(#""kind":"literal""#, with: #""kind":"literal","k\u0069nd":"literal""#, in: valid),
                "kind"
            )
        ]

        for (payload, key) in payloads {
            assertPresetsError(.duplicateJSONKey(key), context: key) {
                _ = try DisplayFilterPresets.decode(from: payload)
            }
        }
    }

    func testDecodeRejectsUnknownFieldsKindsAndSchemaVersions() throws {
        let valid = try DisplayFilterPresets().encodedData()
        let unknownRoot = replacing("{", with: #"{"future":0,"#, in: valid)
        let unknownFilter = replacing(
            #""expression":{"kind":"literal","text":""}"#,
            with: #""expression":{"future":0,"kind":"literal","text":""}"#,
            in: valid
        )
        assertPresetsError(.unknownField("future")) {
            _ = try DisplayFilterPresets.decode(from: unknownRoot)
        }
        assertPresetsError(.unknownField("future")) {
            _ = try DisplayFilterPresets.decode(from: unknownFilter)
        }

        let presetData = try DisplayFilterPresets(
            presets: [try NamedDisplayFilterPreset(name: "One", filter: filter("one"))]
        ).encodedData()
        let unknownPresetMember = replacing(
            #""presets":[{"#,
            with: #""presets":[{"futurePreset":0,"#,
            in: presetData
        )
        let unknownFilterMember = replacing(
            #""activeFilter":{"#,
            with: #""activeFilter":{"futureFilter":0,"#,
            in: presetData
        )
        assertPresetsError(.unknownField("futurePreset")) {
            _ = try DisplayFilterPresets.decode(from: unknownPresetMember)
        }
        assertPresetsError(.unknownField("futureFilter")) {
            _ = try DisplayFilterPresets.decode(from: unknownFilterMember)
        }

        let unknownKind = replacing(#""kind":"literal""#, with: #""kind":"glob""#, in: valid)
        assertPresetsError(.unknownExpressionKind("glob")) {
            _ = try DisplayFilterPresets.decode(from: unknownKind)
        }
        for version in [0, 3, Int.max] {
            let unsupported = replacing(#""schemaVersion":2"#, with: #""schemaVersion":\#(version)"#, in: valid)
            assertPresetsError(.unsupportedSchemaVersion(version)) {
                _ = try DisplayFilterPresets.decode(from: unsupported)
            }
        }
    }

    func testDecodeRejectsDuplicateAndNoncanonicalPersistedIdentities() throws {
        let one = try NamedDisplayFilterPreset(name: "One", filter: filter("one"))
        let two = try NamedDisplayFilterPreset(name: "Two", filter: filter("two"))
        let presetsData = try DisplayFilterPresets(presets: [one, two]).encodedData()
        let duplicateNames = replacing(#""name":"Two""#, with: #""name":"one""#, in: presetsData)
        assertPresetsError(.duplicatePresetName("one")) {
            _ = try DisplayFilterPresets.decode(from: duplicateNames)
        }

        let composedName = "Caf\u{00E9}"
        let decomposedName = "Caf\u{0065}\u{0301}"
        let canonicalData = try DisplayFilterPresets(
            presets: [try NamedDisplayFilterPreset(name: composedName, filter: filter("value"))]
        ).encodedData()
        let noncanonicalName = replacing(composedName, with: decomposedName, in: canonicalData)
        assertPresetsError(.nonCanonicalPresetName(decomposedName)) {
            _ = try DisplayFilterPresets.decode(from: noncanonicalName)
        }

        let history = try DisplayFilterPresetHistory([filter("one"), filter("two")], capacity: 2)
        let historyData = try DisplayFilterPresets(presets: [], recentHistory: history).encodedData()
        let duplicateHistory = replacing(#""text":"two""#, with: #""text":"one""#, in: historyData)
        assertPresetsError(.duplicateHistoryEntry) {
            _ = try DisplayFilterPresets.decode(from: duplicateHistory)
        }
    }

    func testJSONScannerEnforcesNestingContainerValueStringAndNumberBounds() {
        let tooDeep = Data((String(repeating: "[", count: 9) + "0" + String(repeating: "]", count: 9)).utf8)
        assertPresetsError(.jsonNestingTooDeep(maximumDepth: 8)) {
            _ = try DisplayFilterPresets.decode(from: tooDeep)
        }

        let oversizedContainer = Data(("[" + Array(repeating: "0", count: 257).joined(separator: ",") + "]").utf8)
        assertPresetsError(.jsonContainerTooLarge(maximumElements: 256)) {
            _ = try DisplayFilterPresets.decode(from: oversizedContainer)
        }

        let fullContainer = "[" + Array(repeating: "0", count: 256).joined(separator: ",") + "]"
        let tooManyValues = Data(("[" + Array(repeating: fullContainer, count: 7).joined(separator: ",") + "]").utf8)
        assertPresetsError(.tooManyJSONValues(maximumValues: 1_614)) {
            _ = try DisplayFilterPresets.decode(from: tooManyValues)
        }

        let smallStringLimits = DisplayFilterPresetLimits(
            maximumPresetNameUTF8Bytes: 1,
            maximumExpressionUTF8Bytes: 0
        )
        let oversizedString = Data(("\"" + String(repeating: "x", count: 257) + "\"").utf8)
        assertPresetsError(.jsonStringTooLarge(maximumBytes: 256)) {
            _ = try DisplayFilterPresets.decode(from: oversizedString, limits: smallStringLimits)
        }

        let oversizedNumber = Data(String(repeating: "1", count: 33).utf8)
        assertPresetsError(.jsonNumberTooLarge(maximumBytes: 32)) {
            _ = try DisplayFilterPresets.decode(from: oversizedNumber)
        }
    }

    func testJSONScannerUsesDecodedBoundariesForEscapedKeysAndStrings() throws {
        let valid = try DisplayFilterPresets().encodedData()
        let escapedKeyAtLimit = String(repeating: #"\u0061"#, count: 64)
        let keyAtLimit = String(repeating: "a", count: 64)
        let keyAtLimitPayload = replacing(
            "{",
            with: "{\"" + escapedKeyAtLimit + "\":0,",
            in: valid
        )
        assertPresetsError(.unknownField(keyAtLimit)) {
            _ = try DisplayFilterPresets.decode(from: keyAtLimitPayload)
        }

        let escapedKeyOverLimit = escapedKeyAtLimit + #"\u0061"#
        let keyOverLimitPayload = replacing(
            "{",
            with: "{\"" + escapedKeyOverLimit + "\":0,",
            in: valid
        )
        assertPresetsError(.jsonStringTooLarge(maximumBytes: 64)) {
            _ = try DisplayFilterPresets.decode(from: keyOverLimitPayload)
        }

        let limits = DisplayFilterPresetLimits(
            maximumPresetNameUTF8Bytes: 1,
            maximumExpressionUTF8Bytes: 256
        )
        let escapedTextAtLimit = String(repeating: #"\u0078"#, count: 256)
        let textAtLimitPayload = replacing(
            #""text":"""#,
            with: "\"text\":\"" + escapedTextAtLimit + "\"",
            in: valid
        )
        let decoded = try DisplayFilterPresets.decode(from: textAtLimitPayload, limits: limits)
        XCTAssertEqual(Array(decoded.activeExpression.text.utf8), Array(repeating: 0x78, count: 256))

        let escapedTextOverLimit = escapedTextAtLimit + #"\u0078"#
        let textOverLimitPayload = replacing(
            #""text":"""#,
            with: "\"text\":\"" + escapedTextOverLimit + "\"",
            in: valid
        )
        assertPresetsError(.jsonStringTooLarge(maximumBytes: 256)) {
            _ = try DisplayFilterPresets.decode(from: textOverLimitPayload, limits: limits)
        }
    }

    func testInputAndOutputByteBoundsAcceptExactLimitAndRejectOneMore() throws {
        let preset = try NamedDisplayFilterPreset(name: "Bounded", filter: filter("value"))
        let source = try DisplayFilterPresets(presets: [preset], version: 9)
        let data = try source.encodedData()
        let exactLimits = DisplayFilterPresetLimits(
            maximumInputBytes: data.count,
            maximumOutputBytes: data.count
        )
        let exactState = try DisplayFilterPresets(
            presets: source.presets,
            activeFilter: source.activeFilter,
            recentHistory: source.recentHistory,
            selectedPresetName: source.selectedPresetName,
            version: source.version,
            limits: exactLimits
        )
        XCTAssertEqual(try exactState.encodedData(), data)
        XCTAssertEqual(try DisplayFilterPresets.decode(from: data, limits: exactLimits), exactState)

        let smallerOutputLimits = DisplayFilterPresetLimits(maximumOutputBytes: data.count - 1)
        let smallerOutputState = try DisplayFilterPresets(
            presets: source.presets,
            activeFilter: source.activeFilter,
            recentHistory: source.recentHistory,
            version: source.version,
            limits: smallerOutputLimits
        )
        assertPresetsError(.outputTooLarge(maximumBytes: data.count - 1)) {
            _ = try smallerOutputState.encodedData()
        }

        let oversizedInput = data + Data([0x20])
        assertPresetsError(.inputTooLarge(maximumBytes: data.count)) {
            _ = try DisplayFilterPresets.decode(from: oversizedInput, limits: exactLimits)
        }
    }

    func testOutputEstimatorExactlyCountsEveryJSONStringEncodingClass() throws {
        let expression =
            "A\u{0008}\u{0009}\u{000A}\u{000C}\u{000D}\"\\\u{0000}\u{001F}"
            + "\u{007F}\u{00A2}\u{20AC}\u{1F600}"
        let active = filter(expression)
        let baselineData = try DisplayFilterPresets().encodedData()
        let source = try DisplayFilterPresets(presets: [], activeFilter: active)
        let data = try source.encodedData()
        let expectedEncodedExpressionBytes =
            1  // ASCII.
            + 5 * 2  // Short control escapes.
            + 2 * 2  // Quote and backslash escapes.
            + 2 * 6  // Other control escapes.
            + 1  // DEL.
            + 2 + 3 + 4  // Two-, three-, and four-byte UTF-8 scalars.
        XCTAssertEqual(data.count, baselineData.count + expectedEncodedExpressionBytes)

        let exactLimits = DisplayFilterPresetLimits(maximumOutputBytes: data.count)
        let exactState = try DisplayFilterPresets(
            presets: [],
            activeFilter: active,
            limits: exactLimits
        )
        XCTAssertEqual(try exactState.encodedData(), data)

        let insufficientLimits = DisplayFilterPresetLimits(maximumOutputBytes: data.count - 1)
        let insufficientState = try DisplayFilterPresets(
            presets: [],
            activeFilter: active,
            limits: insufficientLimits
        )
        assertPresetsError(.outputTooLarge(maximumBytes: data.count - 1)) {
            _ = try insufficientState.encodedData()
        }
    }

    func testPreCancelledEncodeDecodeMutationAndSelectionAreAtomic() async throws {
        var initial = DisplayFilterPresets()
        try initial.add(name: "Existing", filter: filter("existing"))
        let data = try initial.encodedData()

        let encodeCancelled = await Task.detached { @Sendable [initial] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try initial.encodedData()
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(encodeCancelled)

        let decodeCancelled = await Task.detached { @Sendable [data] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try DisplayFilterPresets.decode(from: data)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(decodeCancelled)

        let mutationOutcome = await Task.detached { @Sendable [initial] in
            var state = initial
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try state.add(name: "Cancelled", filter: DisplayFilter(literal: "cancelled"))
                return (false, state)
            } catch is CancellationError {
                return (true, state)
            } catch {
                return (false, state)
            }
        }.value
        XCTAssertTrue(mutationOutcome.0)
        XCTAssertEqual(mutationOutcome.1, initial)

        let recorder = FilterApplyRecorder()
        let selectionOutcome = await Task.detached { @Sendable [initial, recorder] in
            var state = initial
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await state.select(named: "Existing", applying: recorder.handler)
                return (false, state)
            } catch is CancellationError {
                return (true, state)
            } catch {
                return (false, state)
            }
        }.value
        XCTAssertTrue(selectionOutcome.0)
        XCTAssertEqual(selectionOutcome.1, initial)
        XCTAssertTrue(recorder.filters.isEmpty)
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }

    private func filter(
        _ text: String,
        regularExpression: Bool = false,
        caseSensitive: Bool = false,
        invert: Bool = false,
        predicate: DisplayFilterRowPredicate = .any
    ) -> DisplayFilter {
        DisplayFilter(
            expression: regularExpression ? .regularExpression(text) : .literal(text),
            caseSensitive: caseSensitive,
            invert: invert,
            predicate: predicate
        )
    }

    private func maximumFixture(limits: DisplayFilterPresetLimits) throws -> DisplayFilterPresets {
        let expressionCount =
            1 + DisplayFilterPresets.maximumPresetCount
            + DisplayFilterPresetHistory.maximumCapacity
        let totalExpressionBytes = limits.maximumTotalExpressionUTF8Bytes
        let totalNameBytes = limits.maximumTotalPresetNameUTF8Bytes
        let expressions = (0..<expressionCount).map { index -> DisplayFilter in
            let base = totalExpressionBytes / expressionCount
            let extra = index < totalExpressionBytes % expressionCount ? 1 : 0
            let suffix = String(format: "|%03d|", index)
            return filter(exactUTF8String(byteCount: base + extra, suffix: suffix))
        }
        let presets = try (0..<100).map { index in
            let base = totalNameBytes / DisplayFilterPresets.maximumPresetCount
            let extra = index < totalNameBytes % DisplayFilterPresets.maximumPresetCount ? 1 : 0
            let suffix = String(format: "p%03d", index)
            let name = String(repeating: "n", count: base + extra - suffix.utf8.count) + suffix
            return try NamedDisplayFilterPreset(name: name, filter: expressions[index + 1])
        }
        let history = try DisplayFilterPresetHistory(
            Array(expressions[101...200]),
            capacity: DisplayFilterPresetHistory.maximumCapacity
        )
        return try DisplayFilterPresets(
            presets: presets,
            activeFilter: expressions[0],
            recentHistory: history,
            limits: limits
        )
    }

    private func exactUTF8String(byteCount: Int, suffix: String) -> String {
        let bodyBytes = byteCount - suffix.utf8.count
        return String(repeating: "\u{20AC}", count: bodyBytes / 3)
            + String(repeating: "x", count: bodyBytes % 3)
            + suffix
    }

    private func replacing(_ target: String, with replacement: String, in data: Data) -> Data {
        var string = String(decoding: data, as: UTF8.self)
        guard let range = string.range(of: target) else {
            XCTFail("Fixture replacement did not find \(target.debugDescription)")
            return data
        }
        string.replaceSubrange(range, with: replacement)
        return Data(string.utf8)
    }

    private func assertPresetsError(
        _ expected: DisplayFilterPresetsError,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), context, file: file, line: line) { error in
            XCTAssertEqual(error as? DisplayFilterPresetsError, expected, context, file: file, line: line)
        }
    }

    private func assertExactFilter(
        _ actual: DisplayFilter,
        _ expected: DisplayFilter,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual.expression, expected.expression) {
        case (.literal(let actualText), .literal(let expectedText)),
            (.regularExpression(let actualText), .regularExpression(let expectedText)):
            XCTAssertEqual(Array(actualText.utf8), Array(expectedText.utf8), file: file, line: line)
        default:
            XCTFail("Expression kinds differ", file: file, line: line)
        }
        XCTAssertEqual(actual.caseSensitive, expected.caseSensitive, file: file, line: line)
        XCTAssertEqual(actual.invert, expected.invert, file: file, line: line)
        XCTAssertEqual(actual.predicate, expected.predicate, file: file, line: line)
    }
}

private final class FilterApplyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DisplayFilter] = []
    private var cancellationStorage: [Bool] = []

    var filters: [DisplayFilter] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var taskCancellationStates: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return cancellationStorage
    }

    lazy var handler: @Sendable (DisplayFilter) throws -> Void = { [weak self] filter in
        _ = self?.record(filter)
    }

    @discardableResult
    func record(_ filter: DisplayFilter) -> Int {
        lock.lock()
        storage.append(filter)
        cancellationStorage.append(Task.isCancelled)
        let count = storage.count
        lock.unlock()
        return count
    }
}

private final class IdentityError: Error, @unchecked Sendable {}
