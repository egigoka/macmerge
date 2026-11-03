import MacMergeCore
import XCTest

final class DiffContextViewPolicyTests: XCTestCase {
    typealias Policy = DiffContextViewPolicy

    func testAllNineCommandsExposedInStableOrder() throws {
        let policy = Policy.default
        let states = try policy.commandStates(in: Policy.Context(hasComparison: true))

        XCTAssertEqual(states.map(\.command), Policy.Command.allCases)
        XCTAssertEqual(Policy.Command.allCases.count, 9)
        XCTAssertEqual(
            Policy.Command.allCases.map(\.rawValue),
            ["showAll", "showZero", "showOne", "showThree", "showFive", "showSeven", "showNine", "toggle", "invert"]
        )
        XCTAssertEqual(Policy.Command.allCases.filter(\.isLevelCommand).count, 7)
        XCTAssertEqual(Policy.Command.showAll.lineCount, nil)
        XCTAssertEqual(Policy.Command.showThree.lineCount, 3)
        XCTAssertNil(Policy.Command.toggle.lineCount)
        XCTAssertNil(Policy.Command.invert.lineCount)
        XCTAssertEqual(Policy.Command.showFive.mode, .lines(3 + 2))
    }

    func testEnableCheckDerivationGatesOnComparisonAndMode() throws {
        let live = Policy.Context(hasComparison: true)
        let dead = Policy.Context(hasComparison: false)

        var limited = Policy.default
        try limited.apply(.showThree, in: live)
        let limitedStates = try limited.commandStates(in: live)
        XCTAssertTrue(limitedStates.allSatisfy(\.isEnabled))
        XCTAssertTrue(limited.commandState(for: .showThree, in: live).isChecked)
        XCTAssertFalse(limited.commandState(for: .showAll, in: live).isChecked)
        XCTAssertFalse(limited.commandState(for: .toggle, in: live).isChecked)
        XCTAssertFalse(limited.commandState(for: .invert, in: live).isChecked)

        try limited.apply(.invert, in: live)
        XCTAssertTrue(limited.commandState(for: .invert, in: live).isChecked)

        let allChecked = Policy.default.commandState(for: .showAll, in: live)
        XCTAssertTrue(allChecked.isChecked)
        XCTAssertEqual(
            Policy.default.availability(of: .invert, in: live),
            .disabled(.requiresLimitedContext)
        )
        // Flag retained under All never shows checked while disabled.
        let retained = try Policy(context: DiffContext(mode: .all, isInverted: true))
        XCTAssertTrue(retained.isInverted)
        XCTAssertFalse(retained.isChecked(.invert))
        XCTAssertEqual(retained.availability(of: .invert, in: live), .disabled(.requiresLimitedContext))

        let deadStates = try Policy.default.commandStates(in: dead)
        XCTAssertTrue(deadStates.allSatisfy { $0.availability == .disabled(.noComparison) })
        XCTAssertFalse(deadStates.contains(where: \.isEnabled))
    }

    func testAtomicBatchAppliesInOrderAndRejectsWithoutPartialState() throws {
        let live = Policy.Context(hasComparison: true)
        var policy = Policy.default

        let mutation = try policy.apply([.showThree, .invert], in: live)
        XCTAssertTrue(mutation.didChange)
        XCTAssertEqual(mutation.appliedCommands, [.showThree, .invert])
        XCTAssertEqual(mutation.changedCommands, [.showThree, .invert])
        XCTAssertEqual(policy.lineCount, 3)
        XCTAssertTrue(policy.isInverted)

        // Duplicate leaves self unchanged.
        let beforeDuplicate = policy
        XCTAssertThrowsError(try policy.apply([.showOne, .showOne], in: live)) { error in
            XCTAssertEqual(error as? PolicyError, .duplicateCommand(.showOne))
        }
        XCTAssertEqual(policy, beforeDuplicate)

        // Disabled command aborts whole batch: first command must not stick.
        var all = Policy.default
        let beforeDisabled = all
        XCTAssertThrowsError(try all.apply([.showOne, .invert, .showFive], in: Policy.Context(hasComparison: false))) { error in
            guard case .commandDisabled = error as? PolicyError else {
                return XCTFail("Expected commandDisabled, got \(error)")
            }
        }
        XCTAssertEqual(all, beforeDisabled)

        // Over-limit batch rejected.
        var over = Policy.default
        XCTAssertThrowsError(
            try over.apply(Array(repeating: Policy.Command.showOne, count: Policy.maximumMutationCount + 1), in: live)
        ) { error in
            XCTAssertEqual(
                error as? PolicyError,
                .tooManyChanges(maximumCount: Policy.maximumMutationCount)
            )
        }
        XCTAssertEqual(over, Policy.default)
    }

    func testSchemaOnePersistenceRoundTrip() throws {
        var policy = Policy.default
        try policy.apply([.showFive, .invert], in: Policy.Context(hasComparison: true))

        let data = try policy.encodedData()
        XCTAssertLessThanOrEqual(data.count, Policy.maximumEncodedBytes)
        let decoded = try Policy.decode(from: data)
        XCTAssertEqual(decoded, policy)
        XCTAssertEqual(decoded.schemaVersion, Policy.currentSchemaVersion)
        XCTAssertEqual(decoded.lineCount, 5)
        XCTAssertTrue(decoded.isInverted)
        XCTAssertEqual(decoded.lastLimitedLineCount, 5)

        // Default (All) round-trips without a lineCount key.
        let defaultData = try Policy.default.encodedData()
        XCTAssertFalse(String(decoding: defaultData, as: UTF8.self).contains("lineCount\":"))
        XCTAssertEqual(try Policy.decode(from: defaultData), .default)

        // Nil data restores default; corrupt data restores default via fallback.
        XCTAssertEqual(try Policy.restored(from: nil), .default)
        XCTAssertEqual(try Policy.restored(from: Data("{\"broken\"".utf8)), .default)
    }

    func testHostilePersistenceRejected() {
        let good = try? Policy.default.encodedData()
        XCTAssertNotNil(good)

        XCTAssertThrowsError(try Policy.decode(from: Data("{\"schemaVersion\":1,\"isInverted\":false,\"lastLimitedLineCount\":0,\"extra\":true}".utf8))) {
            error in
            XCTAssertEqual(error as? PolicyError, .unknownField("extra"))
        }
        XCTAssertThrowsError(
            try Policy.decode(from: Data("{\"schemaVersion\":1,\"schemaVersion\":1,\"isInverted\":false,\"lastLimitedLineCount\":0}".utf8))
        ) { error in
            XCTAssertEqual(error as? PolicyError, .duplicateJSONKey("schemaVersion"))
        }
        XCTAssertThrowsError(
            try Policy.decode(from: Data("{\"schemaVersion\":2,\"isInverted\":false,\"lastLimitedLineCount\":0}".utf8))
        ) { error in
            XCTAssertEqual(error as? PolicyError, .unsupportedSchemaVersion(2))
        }
        XCTAssertThrowsError(
            try Policy.decode(from: Data("{\"schemaVersion\":1,\"lineCount\":2,\"isInverted\":false,\"lastLimitedLineCount\":0}".utf8))
        ) { error in
            XCTAssertEqual(error as? PolicyError, .unsupportedLineCount(2))
        }
        XCTAssertThrowsError(
            try Policy.decode(from: Data("{\"schemaVersion\":{\"v\":1},\"isInverted\":false,\"lastLimitedLineCount\":0}".utf8))
        ) { error in
            XCTAssertEqual(error as? PolicyError, .invalidJSON)
        }
        XCTAssertThrowsError(try Policy.decode(from: Data("[1,2]".utf8))) { error in
            XCTAssertEqual(error as? PolicyError, .invalidJSON)
        }
        // Raw JSONDecoder path without bounded token is refused even for valid payload.
        if let good {
            XCTAssertThrowsError(try JSONDecoder().decode(Policy.self, from: good)) { error in
                XCTAssertEqual(error as? PolicyError, .boundedDecodingRequired)
            }
        }
    }

    func testStaleValidationRejectsGenerationAndForgedSnapshot() throws {
        let policy = Policy.default
        let rows = numberedRows(count: 9, differences: [4])
        let view = try policy.projectedView(rows: rows, generation: 7)

        XCTAssertNoThrow(try policy.validate(view, expectedGeneration: 7))
        XCTAssertThrowsError(try policy.validate(view, expectedGeneration: 8)) { error in
            XCTAssertEqual(error as? PolicyError, .staleGeneration(expected: 8, actual: 7))
        }

        let forged = DiffContextProjectedView(
            projection: view.projection,
            snapshot: DiffContextViewSnapshot(
                generation: 7,
                sourceRowCount: rows.count,
                context: DiffContext(lineCount: 1)
            )
        )
        XCTAssertThrowsError(try policy.validate(forged, expectedGeneration: 7)) { error in
            XCTAssertEqual(error as? PolicyError, .staleSnapshotContents)
        }
    }

    func testSelectionRemapAnchorsOnIdentityAndBounds() throws {
        var policy = Policy.default
        try policy.apply(.showZero, in: Policy.Context(hasComparison: true))
        let rows = numberedRows(count: 9, differences: [4])
        let view = try policy.projectedView(rows: rows, generation: 1)

        // Visible difference row maps to a projected index.
        let visible = try policy.remappedSelection(forSourceIndex: 4, in: view, expectedGeneration: 1)
        XCTAssertEqual(visible?.sourceIndex, 4)
        XCTAssertNotNil(visible?.projectedIndex)
        XCTAssertNil(visible?.gapIndex)

        // Hidden equal row maps to a gap.
        let hidden = try policy.remappedSelection(forSourceIndex: 0, in: view, expectedGeneration: 1)
        XCTAssertEqual(hidden?.sourceIndex, 0)
        XCTAssertNil(hidden?.projectedIndex)
        XCTAssertNotNil(hidden?.gapIndex)

        // Index+ID agree: index wins; disagree: ID lookup wins.
        let agree = try policy.remappedSelection(
            forSourceIndex: 4, selectedRowID: rows[4].id, in: view, expectedGeneration: 1)
        XCTAssertEqual(agree, visible)
        let disagree = try policy.remappedSelection(
            forSourceIndex: 0, selectedRowID: rows[4].id, in: view, expectedGeneration: 1)
        XCTAssertEqual(disagree?.sourceIndex, 4)

        // Out-of-range and unknown IDs return nil without trapping.
        XCTAssertNil(try policy.remappedSelection(forSourceIndex: 99, in: view, expectedGeneration: 1))
        XCTAssertNil(try policy.remappedSelection(forSourceIndex: -1, in: view, expectedGeneration: 1))
        let unknownID = DiffRow.ID(leftNumber: 10_000, rightNumber: 10_000)
        XCTAssertNil(try policy.remappedSelection(forSourceIndex: 0, selectedRowID: unknownID, in: view, expectedGeneration: 1))
        XCTAssertNil(try policy.remappedSelection(forRowID: unknownID, in: view, expectedGeneration: 1))
        XCTAssertEqual(
            try policy.remappedSelection(forRowID: rows[4].id, in: view, expectedGeneration: 1),
            visible
        )
    }

    func testEncodedBytesCapEnforcedOnWriteAndRead() throws {
        let policy = Policy.default
        let tiny = DiffContextViewLimits(maximumRows: 1024, maximumEncodedBytes: 4)
        XCTAssertThrowsError(try policy.encodedData(limits: tiny)) { error in
            XCTAssertEqual(error as? PolicyError, .persistenceDataTooLarge(maximumBytes: 4))
        }
        let data = try policy.encodedData()
        XCTAssertGreaterThan(data.count, 4)
        XCTAssertThrowsError(try Policy.decode(from: data, limits: tiny)) { error in
            XCTAssertEqual(error as? PolicyError, .persistenceDataTooLarge(maximumBytes: 4))
        }
        XCTAssertThrowsError(
            try Policy.decode(from: Data(repeating: 0x20, count: Policy.maximumEncodedBytes + 1))
        ) { error in
            XCTAssertEqual(
                error as? PolicyError,
                .persistenceDataTooLarge(maximumBytes: Policy.maximumEncodedBytes)
            )
        }
    }

    func testInvertGatedToLimitedModes() throws {
        let live = Policy.Context(hasComparison: true)
        var policy = Policy.default

        // All: disabled, never checked, apply throws.
        XCTAssertEqual(policy.availability(of: .invert, in: live), .disabled(.requiresLimitedContext))
        XCTAssertFalse(policy.isChecked(.invert))
        XCTAssertThrowsError(try policy.apply(.invert, in: live)) { error in
            XCTAssertEqual(
                error as? PolicyError,
                .commandDisabled(.invert, reason: .requiresLimitedContext)
            )
        }

        // Limited: enabled and tracks flag.
        try policy.apply(.showOne, in: live)
        XCTAssertEqual(policy.availability(of: .invert, in: live), .enabled)
        try policy.apply(.invert, in: live)
        XCTAssertTrue(policy.isChecked(.invert))
        XCTAssertTrue(policy.isInverted)

        // Toggling back to All keeps flag but hides check; returning restores it.
        try policy.apply(.toggle, in: live)
        XCTAssertTrue(policy.isAll)
        XCTAssertFalse(policy.isChecked(.invert))
        XCTAssertEqual(policy.availability(of: .invert, in: live), .disabled(.requiresLimitedContext))
        try policy.apply(.toggle, in: live)
        XCTAssertEqual(policy.lineCount, 1)
        XCTAssertTrue(policy.isChecked(.invert))
    }

    private typealias PolicyError = DiffContextViewPolicyError

    private func numberedRows(count: Int, differences: Set<Int>) -> [DiffRow] {
        (0..<count).map { index in
            let number = index + 1
            return DiffRow(
                left: DiffLine(number: number, text: "L\(number)"),
                right: DiffLine(number: number, text: "R\(number)"),
                kind: differences.contains(index) ? .modified : .unchanged
            )
        }
    }
}
