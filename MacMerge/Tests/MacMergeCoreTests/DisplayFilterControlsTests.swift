import Foundation
import MacMergeCore
import XCTest

final class DisplayFilterControlsTests: XCTestCase {
    func testPresetAddUpdateRemoveCRUDAndVersion() throws {
        var controls = DisplayFilterControls()
        XCTAssertEqual(controls.version, 0)
        XCTAssertTrue(controls.presetNames.isEmpty)
        XCTAssertFalse(controls.availability(of: .selectPreset))

        XCTAssertTrue(try controls.addPreset(named: "  Needle  ", filter: controlsFilter("needle")))
        XCTAssertEqual(controls.version, 1)
        XCTAssertEqual(controls.presetNames, ["Needle"])
        XCTAssertTrue(controls.availability(of: .selectPreset))
        XCTAssertEqual(controls.selectedPresetName, nil)

        XCTAssertTrue(
            try controls.updatePreset(
                named: "needle",
                newName: "Renamed",
                filter: controlsFilter("needle")
            )
        )
        XCTAssertEqual(controls.version, 2)
        XCTAssertEqual(controls.presetNames, ["Renamed"])

        let beforeNoOp = controls
        XCTAssertFalse(
            try controls.updatePreset(named: "renamed", newName: "Renamed", filter: controlsFilter("needle"))
        )
        XCTAssertEqual(controls, beforeNoOp)

        XCTAssertFalse(try controls.removePreset(named: "Missing"))
        XCTAssertEqual(controls, beforeNoOp)

        XCTAssertTrue(try controls.removePreset(named: "RENAMED"))
        XCTAssertEqual(controls.version, 3)
        XCTAssertTrue(controls.presetNames.isEmpty)
    }

    func testDuplicatePresetSurfacesWrappedPresetsError() throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "Needle", filter: controlsFilter("needle"))
        let before = controls
        assertControlsError(.presets(.duplicatePresetName("needle"))) {
            try controls.addPreset(named: " needle ", filter: self.controlsFilter("other"))
        }
        XCTAssertEqual(controls, before)
    }

    func testValidatedDraftAcceptsLiteralAndRegex() throws {
        let controls = DisplayFilterControls()
        let literal = try controls.validatedDraft(expressionText: "needle")
        XCTAssertEqual(literal, DisplayFilter(literal: "needle"))
        let regex = try controls.validatedDraft(expressionText: "a|b", asRegularExpression: true)
        XCTAssertEqual(regex.expression, .regularExpression("a|b"))
    }

    func testValidatedDraftRejectsInvalidRegex() {
        let controls = DisplayFilterControls()
        assertControlsError(.invalidFilter(.invalidRegularExpression("("))) {
            _ = try controls.validatedDraft(expressionText: "(", asRegularExpression: true)
        }
    }

    func testDraftTooLargeEnforced() {
        let controls = DisplayFilterControls(
            limits: DisplayFilterControls.Limits(maximumDraftUTF8Bytes: 4)
        )
        assertControlsError(.draftTooLarge(maximumBytes: 4)) {
            _ = try controls.validatedDraft(expressionText: "abcde")
        }
    }

    func testFolderVariantForcesAnyPredicateOnAddAndUpdate() throws {
        var controls = DisplayFilterControls()
        XCTAssertTrue(try controls.bind(variant: .folder))
        XCTAssertEqual(controls.version, 1)

        assertControlsError(
            .unsupportedFolderPredicate(.significant),
            operation: {
                try controls.addPreset(
                    named: "Sig",
                    filter: self.controlsFilter("x", predicate: .significant)
                )
            }
        )
        XCTAssertTrue(controls.presetNames.isEmpty)

        try controls.addPreset(named: "Any", filter: controlsFilter("x"))
        let beforeBadUpdate = controls
        assertControlsError(
            .unsupportedFolderPredicate(.moved),
            operation: {
                try controls.updatePreset(
                    named: "Any",
                    filter: self.controlsFilter("y", predicate: .moved)
                )
            }
        )
        XCTAssertEqual(controls, beforeBadUpdate)

        var text = DisplayFilterControls()
        XCTAssertNoThrow(
            try text.addPreset(named: "Sig", filter: controlsFilter("x", predicate: .significant))
        )
    }

    func testFolderDraftRejectsNonAnyPredicate() throws {
        var controls = DisplayFilterControls()
        XCTAssertTrue(try controls.bind(variant: .folder))
        assertControlsError(.unsupportedFolderPredicate(.unchanged)) {
            _ = try controls.validatedDraft(
                expressionText: "x",
                predicate: .unchanged
            )
        }
    }

    func testRestoreRevalidatesFolderAnyPredicate() throws {
        var hostileFolder = DisplayFilterPresets()
        try hostileFolder.add(
            name: "Sig",
            filter: controlsFilter("x", predicate: .significant)
        )
        var controls = DisplayFilterControls()
        let snapshot = DisplayFilterControls.Snapshot(
            variant: .folder,
            version: 7,
            textPresets: DisplayFilterPresets(),
            folderPresets: hostileFolder
        )
        let before = controls
        assertControlsError(.unsupportedFolderPredicate(.significant)) {
            try controls.restore(snapshot)
        }
        XCTAssertEqual(controls, before)
    }

    func testSnapshotRestoreRoundTrip() throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "A", filter: controlsFilter("a"))
        XCTAssertTrue(try controls.bind(variant: .folder))
        try controls.addPreset(named: "F", filter: controlsFilter("f"))
        let snapshot = controls.snapshot()
        XCTAssertEqual(snapshot.variant, .folder)
        XCTAssertEqual(snapshot.version, controls.version)

        try controls.addPreset(named: "G", filter: controlsFilter("g"))
        XCTAssertTrue(try controls.bind(variant: .text))
        XCTAssertNotEqual(controls.snapshot(), snapshot)

        try controls.restore(snapshot)
        XCTAssertEqual(controls.snapshot(), snapshot)
        XCTAssertEqual(controls.variant, .folder)
        XCTAssertEqual(controls.version, snapshot.version)
        XCTAssertEqual(controls.presetNames, ["F"])
    }

    func testRestoreStaleVersionThrows() throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "A", filter: controlsFilter("a"))
        let snapshot = controls.snapshot()
        try controls.addPreset(named: "B", filter: controlsFilter("b"))
        let before = controls
        assertControlsError(
            .staleVersion(expected: snapshot.version + 10, actual: controls.version),
            operation: { try controls.restore(snapshot, expectedVersion: snapshot.version + 10) }
        )
        XCTAssertEqual(controls, before)
        XCTAssertNoThrow(try controls.restore(snapshot, expectedVersion: controls.version))
        XCTAssertEqual(controls.snapshot(), snapshot)
    }

    func testVersionCASStaleLeavesStateUntouched() async throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "A", filter: controlsFilter("a"))
        let version = controls.version
        let before = controls
        let filter = controlsFilter("b")

        assertControlsError(
            .staleVersion(expected: version + 1, actual: version),
            operation: {
                try controls.addPreset(named: "B", filter: filter, expectedVersion: version + 1)
            }
        )
        assertControlsError(
            .staleVersion(expected: version + 1, actual: version),
            operation: {
                try controls.updatePreset(named: "A", filter: filter, expectedVersion: version + 1)
            }
        )
        assertControlsError(
            .staleVersion(expected: version + 1, actual: version),
            operation: { try controls.removePreset(named: "A", expectedVersion: version + 1) }
        )
        assertControlsError(
            .staleVersion(expected: version + 1, actual: version),
            operation: { try controls.bind(variant: .folder, expectedVersion: version + 1) }
        )
        do {
            _ = try await controls.selectPreset(
                named: "A",
                applying: { _ in },
                expectedVersion: version + 1
            )
            XCTFail("Expected stale version")
        } catch let error as DisplayFilterControlsError {
            XCTAssertEqual(error, .staleVersion(expected: version + 1, actual: version))
        }
        do {
            _ = try await controls.applyFilter(filter, applying: { _ in }, expectedVersion: version + 1)
            XCTFail("Expected stale version")
        } catch let error as DisplayFilterControlsError {
            XCTAssertEqual(error, .staleVersion(expected: version + 1, actual: version))
        }
        XCTAssertEqual(controls, before)
    }

    func testStrictJSONRejectsHostilePayloads() throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "A", filter: controlsFilter("a"))
        let data = try controls.encodedData()
        let string = String(decoding: data, as: UTF8.self)

        var unknown = string
        unknown.insert(contentsOf: #""zzz":1,"#, at: string.index(after: string.startIndex))
        assertDecodeError(.unknownField("zzz"), data: Data(unknown.utf8))

        let missing = string.replacingOccurrences(of: #""stateVersion":1,"#, with: "")
        XCTAssertNotEqual(missing, string)
        assertDecodeError(.invalidPersistence, data: Data(missing.utf8))

        let badSchema = string.replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":999"#)
        XCTAssertNotEqual(badSchema, string)
        assertDecodeError(.unsupportedSchemaVersion(999), data: Data(badSchema.utf8))

        let truncated = Data(string.utf8.prefix(10))
        assertDecodeError(.invalidPersistence, data: truncated)
    }

    func testDecodeRejectsNonAnyFolderPredicate() throws {
        var hostileFolder = DisplayFilterPresets()
        try hostileFolder.add(
            name: "Sig",
            filter: controlsFilter("x", predicate: .significant)
        )
        let textData = try DisplayFilterPresets().encodedData()
        let folderData = try hostileFolder.encodedData()
        let json =
            #"{"folderPresets":""# + folderData.base64EncodedString()
            + #"","schemaVersion":1,"stateVersion":0,"textPresets":""#
            + textData.base64EncodedString() + #"","variant":"folder"}"#
        assertDecodeError(
            .unsupportedFolderPredicate(.significant),
            data: Data(json.utf8)
        )
    }

    func testEncodeDecodeRoundTripPreservesBothStores() throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "T", filter: controlsFilter("text"))
        XCTAssertTrue(try controls.bind(variant: .folder))
        try controls.addPreset(named: "F", filter: controlsFilter("folder"))
        let restored = try DisplayFilterControls.decode(from: controls.encodedData())
        XCTAssertEqual(restored.snapshot(), controls.snapshot())
    }

    func testInputTooLargeRejected() throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "A", filter: controlsFilter("a"))
        let data = try controls.encodedData()
        do {
            _ = try DisplayFilterControls.decode(
                from: data,
                limits: DisplayFilterControls.Limits(maximumInputBytes: 1)
            )
            XCTFail("Expected input too large")
        } catch let error as DisplayFilterControlsError {
            XCTAssertEqual(error, .inputTooLarge(maximumBytes: 1))
        }
    }

    func testPreCancelledTasksMapToCancelled() async throws {
        var seed = DisplayFilterControls()
        try seed.addPreset(named: "Existing", filter: controlsFilter("existing"))
        let seedData = try seed.encodedData()

        let draftCancelled = await Task.detached { @Sendable [seed] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try seed.validatedDraft(expressionText: "x")
                return false
            } catch let error as DisplayFilterControlsError {
                return error == .cancelled
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(draftCancelled)

        let mutationOutcome = await Task.detached { @Sendable [seed] in
            var copy = seed
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try copy.addPreset(named: "Cancelled", filter: DisplayFilter(literal: "x"))
                return (false, copy)
            } catch let error as DisplayFilterControlsError {
                return (error == .cancelled, copy)
            } catch {
                return (false, copy)
            }
        }.value
        XCTAssertTrue(mutationOutcome.0)
        XCTAssertEqual(mutationOutcome.1, seed)

        let selectionOutcome = await Task.detached { @Sendable [seed] in
            var copy = seed
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await copy.selectPreset(named: "Existing", applying: { _ in })
                return (false, copy)
            } catch let error as DisplayFilterControlsError {
                return (error == .cancelled, copy)
            } catch {
                return (false, copy)
            }
        }.value
        XCTAssertTrue(selectionOutcome.0)
        XCTAssertEqual(selectionOutcome.1, seed)

        let decodeCancelled = await Task.detached { @Sendable [seedData] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try DisplayFilterControls.decode(from: seedData)
                return false
            } catch let error as DisplayFilterControlsError {
                return error == .cancelled
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(decodeCancelled)
    }

    func testApplyErrorsPropagateUnwrapped() async throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "Needle", filter: controlsFilter("needle"))
        let previous = controls.activeFilter
        let target = controlsFilter("needle")

        let beforeSelect = controls
        do {
            _ = try await controls.selectPreset(named: "Needle") { filter in
                if filter != previous { throw ControlsBoomError() }
            }
            XCTFail("Expected BoomError")
        } catch is ControlsBoomError {
        } catch {
            XCTFail("Wrapped apply error: \(error)")
        }
        XCTAssertEqual(controls, beforeSelect)

        let beforeApply = controls
        do {
            _ = try await controls.applyFilter(target) { filter in
                if filter != previous { throw ControlsBoomError() }
            }
            XCTFail("Expected BoomError")
        } catch is ControlsBoomError {
        } catch {
            XCTFail("Wrapped apply error: \(error)")
        }
        XCTAssertEqual(controls, beforeApply)

        _ = try await controls.applyFilter(target, applying: { _ in })
        let applied = controls.activeFilter
        let beforeClose = controls
        do {
            _ = try await controls.close { filter in
                if filter != applied { throw ControlsBoomError() }
            }
            XCTFail("Expected BoomError")
        } catch is ControlsBoomError {
        } catch {
            XCTFail("Wrapped apply error: \(error)")
        }
        XCTAssertEqual(controls, beforeClose)
    }

    func testRollbackFailurePropagatesRollbackErrorUnwrapped() async throws {
        var controls = DisplayFilterControls()
        let target = controlsFilter("needle")
        let before = controls
        do {
            _ = try await controls.applyFilter(target, applying: { _ in throw ControlsBoomError() })
            XCTFail("Expected rollback error")
        } catch let error as DisplayFilterPresetsRollbackError {
            XCTAssertTrue(error.applicationError is ControlsBoomError)
            XCTAssertTrue(error.rollbackError is ControlsBoomError)
        } catch {
            XCTFail("Wrapped rollback error: \(error)")
        }
        XCTAssertEqual(controls, before)
    }

    func testUpdateMissingAndDuplicateRenameThrow() throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "Alpha", filter: controlsFilter("a"))
        try controls.addPreset(named: "Beta", filter: controlsFilter("b"))
        let before = controls
        assertControlsError(.presets(.presetNotFound("Missing"))) {
            try controls.updatePreset(named: "Missing", filter: self.controlsFilter("x"))
        }
        XCTAssertEqual(controls, before)
        assertControlsError(.presets(.duplicatePresetName("Beta"))) {
            try controls.updatePreset(named: "Alpha", newName: "Beta", filter: self.controlsFilter("a"))
        }
        XCTAssertEqual(controls, before)
    }

    func testFolderApplyFilterAndExpressionRejectNonAnyPredicate() async throws {
        var controls = DisplayFilterControls()
        XCTAssertTrue(try controls.bind(variant: .folder))
        let before = controls
        do {
            _ = try await controls.applyFilter(
                controlsFilter("x", predicate: .significant),
                applying: { _ in }
            )
            XCTFail("Expected unsupported folder predicate")
        } catch let error as DisplayFilterControlsError {
            XCTAssertEqual(error, .unsupportedFolderPredicate(.significant))
        }
        XCTAssertEqual(controls, before)
        do {
            _ = try await controls.applyExpressionText(
                "y",
                predicate: .moved,
                applying: { _ in }
            )
            XCTFail("Expected unsupported folder predicate")
        } catch let error as DisplayFilterControlsError {
            XCTAssertEqual(error, .unsupportedFolderPredicate(.moved))
        }
        XCTAssertEqual(controls, before)
    }

    func testRestoreRejectsPoisonedActiveFilterAndHistory() throws {
        var controls = DisplayFilterControls()
        let before = controls
        let hostileActive = try DisplayFilterPresets(
            presets: [],
            activeFilter: controlsFilter("x", predicate: .significant)
        )
        let poisonedActive = DisplayFilterControls.Snapshot(
            variant: .folder,
            version: 7,
            textPresets: DisplayFilterPresets(),
            folderPresets: hostileActive
        )
        assertControlsError(.unsupportedFolderPredicate(.significant)) {
            try controls.restore(poisonedActive)
        }
        XCTAssertEqual(controls, before)

        let badHistory = try DisplayFilterPresetHistory(
            [controlsFilter("x", predicate: .moved)]
        )
        let hostileHistory = try DisplayFilterPresets(
            presets: [],
            recentHistory: badHistory
        )
        let poisonedHistory = DisplayFilterControls.Snapshot(
            variant: .folder,
            version: 7,
            textPresets: DisplayFilterPresets(),
            folderPresets: hostileHistory
        )
        assertControlsError(.unsupportedFolderPredicate(.moved)) {
            try controls.restore(poisonedHistory)
        }
        XCTAssertEqual(controls, before)
    }

    func testDecodeRejectsPoisonedActiveFilterAndHistory() throws {
        let textData = try DisplayFilterPresets().encodedData()
        func hostileJSON(folder: DisplayFilterPresets) throws -> Data {
            let folderData = try folder.encodedData()
            let json =
                #"{"folderPresets":""# + folderData.base64EncodedString()
                + #"","schemaVersion":1,"stateVersion":0,"textPresets":""#
                + textData.base64EncodedString() + #"","variant":"folder"}"#
            return Data(json.utf8)
        }
        let hostileActive = try DisplayFilterPresets(
            presets: [],
            activeFilter: controlsFilter("x", predicate: .significant)
        )
        assertDecodeError(
            .unsupportedFolderPredicate(.significant),
            data: try hostileJSON(folder: hostileActive)
        )
        let badHistory = try DisplayFilterPresetHistory(
            [controlsFilter("x", predicate: .moved)]
        )
        let hostileHistory = try DisplayFilterPresets(
            presets: [],
            recentHistory: badHistory
        )
        assertDecodeError(
            .unsupportedFolderPredicate(.moved),
            data: try hostileJSON(folder: hostileHistory)
        )
    }

    func testStaleVersionCoversCloseRestoreAndApplyExpression() async throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "A", filter: controlsFilter("a"))
        let version = controls.version
        let before = controls
        do {
            _ = try await controls.close(applying: { _ in }, expectedVersion: version + 1)
            XCTFail("Expected stale version")
        } catch let error as DisplayFilterControlsError {
            XCTAssertEqual(error, .staleVersion(expected: version + 1, actual: version))
        }
        XCTAssertEqual(controls, before)
        do {
            _ = try await controls.applyExpressionText(
                "b",
                applying: { _ in },
                expectedVersion: version + 1
            )
            XCTFail("Expected stale version")
        } catch let error as DisplayFilterControlsError {
            XCTAssertEqual(error, .staleVersion(expected: version + 1, actual: version))
        }
        XCTAssertEqual(controls, before)
        let snapshot = controls.snapshot()
        do {
            try controls.restore(snapshot, expectedVersion: version + 1)
            XCTFail("Expected stale version")
        } catch let error as DisplayFilterControlsError {
            XCTAssertEqual(error, .staleVersion(expected: version + 1, actual: version))
        }
        XCTAssertEqual(controls, before)
        XCTAssertNoThrow(try controls.restore(snapshot, expectedVersion: version))
    }

    func testPreCancelledMutationsMapToCancelled() async throws {
        var seed = DisplayFilterControls()
        try seed.addPreset(named: "Existing", filter: controlsFilter("existing"))
        let seedSnapshot = seed.snapshot()
        let seedData = try seed.encodedData()

        let updateOutcome = await Task.detached { @Sendable [seed] in
            var copy = seed
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try copy.updatePreset(named: "Existing", filter: DisplayFilter(literal: "y"))
                return (false, copy)
            } catch let error as DisplayFilterControlsError {
                return (error == .cancelled, copy)
            } catch {
                return (false, copy)
            }
        }.value
        XCTAssertTrue(updateOutcome.0)
        XCTAssertEqual(updateOutcome.1, seed)

        let removeOutcome = await Task.detached { @Sendable [seed] in
            var copy = seed
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try copy.removePreset(named: "Existing")
                return (false, copy)
            } catch let error as DisplayFilterControlsError {
                return (error == .cancelled, copy)
            } catch {
                return (false, copy)
            }
        }.value
        XCTAssertTrue(removeOutcome.0)
        XCTAssertEqual(removeOutcome.1, seed)

        let bindOutcome = await Task.detached { @Sendable [seed] in
            var copy = seed
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try copy.bind(variant: .folder)
                return (false, copy)
            } catch let error as DisplayFilterControlsError {
                return (error == .cancelled, copy)
            } catch {
                return (false, copy)
            }
        }.value
        XCTAssertTrue(bindOutcome.0)
        XCTAssertEqual(bindOutcome.1, seed)

        let restoreOutcome = await Task.detached { @Sendable [seed, seedSnapshot] in
            var copy = seed
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try copy.restore(seedSnapshot)
                return (false, copy)
            } catch let error as DisplayFilterControlsError {
                return (error == .cancelled, copy)
            } catch {
                return (false, copy)
            }
        }.value
        XCTAssertTrue(restoreOutcome.0)
        XCTAssertEqual(restoreOutcome.1, seed)

        let encodeCancelled = await Task.detached { @Sendable [seed] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try seed.encodedData()
                return false
            } catch let error as DisplayFilterControlsError {
                return error == .cancelled
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(encodeCancelled)

        let applyOutcome = await Task.detached { @Sendable [seed] in
            var copy = seed
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await copy.applyFilter(DisplayFilter(literal: "z"), applying: { _ in })
                return (false, copy)
            } catch let error as DisplayFilterControlsError {
                return (error == .cancelled, copy)
            } catch {
                return (false, copy)
            }
        }.value
        XCTAssertTrue(applyOutcome.0)
        XCTAssertEqual(applyOutcome.1, seed)

        let closeOutcome = await Task.detached { @Sendable [seed] in
            var copy = seed
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await copy.close(applying: { _ in })
                return (false, copy)
            } catch let error as DisplayFilterControlsError {
                return (error == .cancelled, copy)
            } catch {
                return (false, copy)
            }
        }.value
        XCTAssertTrue(closeOutcome.0)
        XCTAssertEqual(closeOutcome.1, seed)

        let decodeCancelled = await Task.detached { @Sendable [seedData] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try DisplayFilterControls.decode(from: seedData)
                return false
            } catch let error as DisplayFilterControlsError {
                return error == .cancelled
            } catch {
                return false
            }
        }.value
        XCTAssertTrue(decodeCancelled)
    }

    func testSelectCloseRollbackAndCancellationUnwrapped() async throws {
        var controls = DisplayFilterControls()
        try controls.addPreset(named: "Needle", filter: controlsFilter("needle"))
        let target = controlsFilter("needle")

        let beforeSelect = controls
        do {
            _ = try await controls.selectPreset(named: "Needle", applying: { _ in throw ControlsBoomError() })
            XCTFail("Expected rollback error")
        } catch let error as DisplayFilterPresetsRollbackError {
            XCTAssertTrue(error.applicationError is ControlsBoomError)
            XCTAssertTrue(error.rollbackError is ControlsBoomError)
        } catch {
            XCTFail("Wrapped rollback error: \(error)")
        }
        XCTAssertEqual(controls, beforeSelect)

        _ = try await controls.applyFilter(target, applying: { _ in })
        let beforeClose = controls
        do {
            _ = try await controls.close { _ in throw ControlsBoomError() }
            XCTFail("Expected rollback error")
        } catch let error as DisplayFilterPresetsRollbackError {
            XCTAssertTrue(error.applicationError is ControlsBoomError)
            XCTAssertTrue(error.rollbackError is ControlsBoomError)
        } catch {
            XCTFail("Wrapped rollback error: \(error)")
        }
        XCTAssertEqual(controls, beforeClose)

        var cancelledControls = DisplayFilterControls()
        try cancelledControls.addPreset(named: "Needle", filter: controlsFilter("needle"))
        let cancelledTarget = controlsFilter("needle")
        let beforeCancelledSelect = cancelledControls
        do {
            _ = try await cancelledControls.selectPreset(named: "Needle") { filter in
                if filter == cancelledTarget { throw CancellationError() }
            }
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Wrapped cancellation: \(error)")
        }
        XCTAssertEqual(cancelledControls, beforeCancelledSelect)

        let beforeCancelledApply = cancelledControls
        do {
            _ = try await cancelledControls.applyFilter(cancelledTarget) { filter in
                if filter == cancelledTarget { throw CancellationError() }
            }
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Wrapped cancellation: \(error)")
        }
        XCTAssertEqual(cancelledControls, beforeCancelledApply)

        _ = try await cancelledControls.applyFilter(cancelledTarget, applying: { _ in })
        let beforeCancelledClose = cancelledControls
        do {
            _ = try await cancelledControls.close { filter in
                if filter == DisplayFilterPreset.allRows.filter { throw CancellationError() }
            }
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Wrapped cancellation: \(error)")
        }
        XCTAssertEqual(cancelledControls, beforeCancelledClose)
    }

    private func controlsFilter(
        _ text: String,
        regularExpression: Bool = false,
        predicate: DisplayFilterRowPredicate = .any
    ) -> DisplayFilter {
        DisplayFilter(
            expression: regularExpression ? .regularExpression(text) : .literal(text),
            predicate: predicate
        )
    }

    private func assertControlsError(
        _ expected: DisplayFilterControlsError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? DisplayFilterControlsError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func assertDecodeError(
        _ expected: DisplayFilterControlsError,
        data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try DisplayFilterControls.decode(from: data), file: file, line: line) {
            error in
            XCTAssertEqual(error as? DisplayFilterControlsError, expected, file: file, line: line)
        }
    }
}

private struct ControlsBoomError: Error, Sendable, Equatable {}
