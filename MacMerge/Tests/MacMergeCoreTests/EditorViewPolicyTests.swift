import Foundation
import MacMergeCore
import XCTest

final class EditorViewPolicyTests: XCTestCase {
    typealias Policy = EditorViewPolicy
    typealias Command = Policy.Command

    private struct ApplyCancellationResult: Sendable {
        let error: EditorViewPolicyError?
        let policy: Policy
    }

    private static let defaultJSON =
        #"{"locksPanes":false,"schemaVersion":1,"showsEndOfLineMarkers":false,"#
        + #""showsLineDifferences":true,"showsLineNumbers":false,"showsMargins":false,"#
        + #""showsTopMargins":false,"showsWhitespace":false,"wrapsLines":false}"#

    func testCommandCatalogDefaultsAndSingleCommandMutationCoverEveryCommand() throws {
        let expectedCommands: [Command] = [
            .lockPanes,
            .viewWhitespace,
            .viewEndOfLineMarkers,
            .viewLineDifferences,
            .viewLineNumbers,
            .viewMargins,
            .viewTopMargins,
            .wrapLines
        ]
        let expectedRawValues = [
            "lockPanes",
            "viewWhitespace",
            "viewEndOfLineMarkers",
            "viewLineDifferences",
            "viewLineNumbers",
            "viewMargins",
            "viewTopMargins",
            "wrapLines"
        ]
        let context = try Policy.Context(paneCount: 2)

        XCTAssertEqual(Command.allCases, expectedCommands)
        XCTAssertEqual(Command.allCases.map(\.rawValue), expectedRawValues)
        XCTAssertEqual(Command.whitespace, .viewWhitespace)
        XCTAssertEqual(Command.endOfLineMarkers, .viewEndOfLineMarkers)
        XCTAssertEqual(Command.lineDifferences, .viewLineDifferences)
        XCTAssertEqual(Command.lineNumbers, .viewLineNumbers)
        XCTAssertEqual(Command.margins, .viewMargins)
        XCTAssertEqual(Command.topMargins, .viewTopMargins)
        XCTAssertEqual(Policy.default.schemaVersion, Policy.currentSchemaVersion)
        XCTAssertEqual(Policy.currentSchemaVersion, 1)

        for command in Command.allCases {
            XCTAssertEqual(
                try JSONDecoder().decode(
                    Command.self,
                    from: JSONEncoder().encode(command)
                ),
                command
            )

            var policy = Policy.default
            let before = policy
            let oldChecked = policy.isChecked(command)
            let mutation = try policy.apply(command, in: context)

            XCTAssertEqual(policy.isChecked(command), !oldChecked, "Command: \(command)")
            for otherCommand in Command.allCases where otherCommand != command {
                XCTAssertEqual(
                    policy.isChecked(otherCommand),
                    before.isChecked(otherCommand),
                    "\(command) changed \(otherCommand)"
                )
            }
            XCTAssertEqual(mutation.before, before)
            XCTAssertEqual(mutation.after, policy)
            XCTAssertEqual(mutation.appliedChanges, [.toggle(command)])
            XCTAssertEqual(mutation.changedCommands, [command])
            XCTAssertTrue(mutation.didChange)

            let noOp = try policy.apply(
                [.set(command, checked: policy.isChecked(command))],
                in: context
            )
            XCTAssertFalse(noOp.didChange)
            XCTAssertEqual(noOp.appliedChanges, [.set(command, checked: !oldChecked)])
            XCTAssertTrue(noOp.changedCommands.isEmpty)
        }
    }

    func testEveryCommandHasOneHotPropertyAndMutationMapping() throws {
        let context = try Policy.Context(paneCount: 2)

        for (command, oneHotPolicy) in oneHotPolicies {
            XCTAssertEqual(checkedCommands(in: oneHotPolicy), [command])

            var mutated = Self.allFalsePolicy
            let mutation = try mutated.apply(
                [.set(command, checked: true)],
                in: context
            )

            XCTAssertEqual(mutated, oneHotPolicy, "Command: \(command)")
            XCTAssertEqual(mutation.before, Self.allFalsePolicy)
            XCTAssertEqual(mutation.after, oneHotPolicy)
            XCTAssertEqual(mutation.appliedChanges, [.set(command, checked: true)])
            XCTAssertEqual(mutation.changedCommands, [command])
        }
    }

    func testOppositeSetReportsExactBeforeAndAfterForEveryCommand() throws {
        let context = try Policy.Context(paneCount: 2)
        let allCommands = Set(Command.allCases)

        for command in Command.allCases {
            for desiredValue in [true, false] {
                let before = desiredValue ? Self.allFalsePolicy : Self.allCheckedPolicy
                let expectedChecked =
                    desiredValue
                    ? Set([command])
                    : allCommands.subtracting([command])
                let expectedAfter = policy(checkedCommands: expectedChecked)
                let change = Policy.Change.set(command, checked: desiredValue)
                var policy = before

                let mutation = try policy.apply([change], in: context)

                XCTAssertEqual(mutation.before, before, "Command: \(command)")
                XCTAssertEqual(mutation.after, expectedAfter, "Command: \(command)")
                XCTAssertEqual(mutation.appliedChanges, [change])
                XCTAssertEqual(mutation.changedCommands, [command])
                XCTAssertTrue(mutation.didChange)
                XCTAssertEqual(policy, expectedAfter)
            }
        }
    }

    func testDisabledNoOpSetStillFailsWithoutMutation() throws {
        let noEditor = try Policy.Context(paneCount: 0)

        for command in Command.allCases {
            var policy = Self.allCheckedPolicy
            assertPolicyError(.commandDisabled(command, reason: .noActiveEditor)) {
                try policy.apply(
                    [.set(command, checked: policy.isChecked(command))],
                    in: noEditor
                )
            }
            XCTAssertEqual(policy, Self.allCheckedPolicy, "Command: \(command)")
        }

        let unsupported = try Policy.Context(paneCount: 2, supportedCommands: [])
        var unsupportedPolicy = Self.allFalsePolicy
        assertPolicyError(
            .commandDisabled(.viewMargins, reason: .unsupportedByEditor(.viewMargins))
        ) {
            try unsupportedPolicy.apply([.set(.viewMargins, checked: false)], in: unsupported)
        }
        XCTAssertEqual(unsupportedPolicy, Self.allFalsePolicy)

        let singlePane = try Policy.Context(paneCount: 1)
        var singlePanePolicy = Self.allFalsePolicy
        assertPolicyError(
            .commandDisabled(
                .lockPanes,
                reason: .requiresMultiplePanes(actualPaneCount: 1)
            )
        ) {
            try singlePanePolicy.apply([.set(.lockPanes, checked: false)], in: singlePane)
        }
        XCTAssertEqual(singlePanePolicy, Self.allFalsePolicy)
    }

    func testAvailabilityDependenciesCheckedStateAndStableStateOrder() throws {
        let allChecked = Policy(
            locksPanes: true,
            showsWhitespace: true,
            showsEndOfLineMarkers: true,
            showsLineDifferences: true,
            showsLineNumbers: true,
            showsMargins: true,
            showsTopMargins: true,
            wrapsLines: true
        )
        let noEditor = try Policy.Context(paneCount: 0, supportedCommands: [])
        let unsupportedSingle = try Policy.Context(paneCount: 1, supportedCommands: [])
        let single = try Policy.Context(paneCount: 1)
        let multiple = try Policy.Context(paneCount: Policy.maximumPaneCount)

        XCTAssertFalse(noEditor.hasActiveEditor)
        XCTAssertTrue(single.hasActiveEditor)
        for command in Command.allCases {
            XCTAssertEqual(
                allChecked.availability(of: command, in: noEditor),
                .disabled(.noActiveEditor),
                "Command: \(command)"
            )
            XCTAssertEqual(
                allChecked.availability(of: command, in: unsupportedSingle),
                .disabled(.unsupportedByEditor(command)),
                "Command: \(command)"
            )

            let singleExpected: Policy.Availability =
                command == .lockPanes
                ? .disabled(.requiresMultiplePanes(actualPaneCount: 1))
                : .enabled
            XCTAssertEqual(
                allChecked.availability(of: command, in: single),
                singleExpected,
                "Command: \(command)"
            )
            XCTAssertEqual(allChecked.availability(of: command, in: multiple), .enabled)

            let disabledState = allChecked.commandState(for: command, in: noEditor)
            XCTAssertEqual(disabledState.command, command)
            XCTAssertTrue(disabledState.isChecked)
            XCTAssertFalse(disabledState.isEnabled)
            XCTAssertEqual(disabledState.disabledReason, .noActiveEditor)
        }

        let states = try allChecked.commandStates(in: multiple)
        XCTAssertEqual(states.map(\.command), Command.allCases)
        XCTAssertTrue(states.allSatisfy(\.isChecked))
        XCTAssertTrue(states.allSatisfy(\.isEnabled))
        XCTAssertTrue(states.allSatisfy { $0.disabledReason == nil })

        let supported: Set<Command> = [.lockPanes, .viewMargins]
        let partial = try Policy.Context(paneCount: 2, supportedCommands: supported)
        for command in Command.allCases {
            let state = allChecked.commandState(for: command, in: partial)
            XCTAssertEqual(state.isEnabled, supported.contains(command))
            XCTAssertEqual(
                state.disabledReason,
                supported.contains(command) ? nil : .unsupportedByEditor(command)
            )
            XCTAssertTrue(state.isChecked, "Disabled state lost checkmark for \(command)")
        }

        for invalidPaneCount in [-1, Policy.maximumPaneCount + 1, Int.max] {
            assertPolicyError(.invalidPaneCount(invalidPaneCount)) {
                try Policy.Context(paneCount: invalidPaneCount)
            }
        }
    }

    func testLockWrapMarginsAndTopMarginsRemainIndependentForEveryCombination() throws {
        let context = try Policy.Context(paneCount: 2)
        let commands: [Command] = [.lockPanes, .wrapLines, .viewMargins, .viewTopMargins]

        for bitmask in 0..<(1 << commands.count) {
            let expected = Dictionary(
                uniqueKeysWithValues: commands.enumerated().map { index, command in
                    (command, bitmask & (1 << index) != 0)
                }
            )
            let policy = Policy(
                locksPanes: expected[.lockPanes]!,
                showsMargins: expected[.viewMargins]!,
                showsTopMargins: expected[.viewTopMargins]!,
                wrapsLines: expected[.wrapLines]!
            )

            for command in commands {
                XCTAssertEqual(
                    policy.isChecked(command),
                    expected[command],
                    "Combination: \(bitmask), command: \(command)"
                )
                XCTAssertEqual(policy.availability(of: command, in: context), .enabled)
            }
            XCTAssertEqual(try Policy.decode(from: policy.encodedData()), policy)
        }
    }

    func testContextTransitionsChangeAvailabilityWithoutChangingPolicyState() throws {
        var policy = Policy(
            locksPanes: true,
            showsWhitespace: true,
            showsMargins: true,
            showsTopMargins: true,
            wrapsLines: true
        )
        let original = policy
        let noEditor = try Policy.Context(paneCount: 0)
        let single = try Policy.Context(paneCount: 1)
        let multiple = try Policy.Context(paneCount: 2)
        let unsupported = try Policy.Context(
            paneCount: 2,
            supportedCommands: Set(Command.allCases).subtracting([.wrapLines])
        )

        XCTAssertEqual(
            policy.commandState(for: .lockPanes, in: noEditor).availability,
            .disabled(.noActiveEditor)
        )
        XCTAssertEqual(
            policy.commandState(for: .lockPanes, in: single).availability,
            .disabled(.requiresMultiplePanes(actualPaneCount: 1))
        )
        XCTAssertEqual(policy.commandState(for: .lockPanes, in: multiple).availability, .enabled)
        XCTAssertEqual(
            policy.commandState(for: .wrapLines, in: unsupported).availability,
            .disabled(.unsupportedByEditor(.wrapLines))
        )
        XCTAssertEqual(policy, original)

        assertPolicyError(
            .commandDisabled(.lockPanes, reason: .requiresMultiplePanes(actualPaneCount: 1))
        ) {
            try policy.apply(.lockPanes, in: single)
        }
        XCTAssertEqual(policy, original)

        _ = try policy.apply(.lockPanes, in: multiple)
        XCTAssertFalse(policy.locksPanes)
        XCTAssertTrue(policy.wrapsLines)
        XCTAssertTrue(policy.showsMargins)
        XCTAssertTrue(policy.showsTopMargins)
    }

    func testCompleteBatchMutationIsOrderedAndAtomic() throws {
        let context = try Policy.Context(paneCount: 2)
        let changes = Command.allCases.map(Policy.Change.toggle)
        var policy = Policy.default

        let mutation = try policy.apply(changes, in: context)

        XCTAssertEqual(mutation.before, .default)
        XCTAssertEqual(mutation.after, policy)
        XCTAssertEqual(mutation.appliedChanges, changes)
        XCTAssertEqual(mutation.changedCommands, Command.allCases)
        XCTAssertTrue(mutation.didChange)
        XCTAssertEqual(
            policy,
            Policy(
                locksPanes: true,
                showsWhitespace: true,
                showsEndOfLineMarkers: true,
                showsLineDifferences: false,
                showsLineNumbers: true,
                showsMargins: true,
                showsTopMargins: true,
                wrapsLines: true
            )
        )
    }

    func testScrambledMixedBatchPreservesRequestAndChangedOrderWhileOmittingNoOps() throws {
        let context = try Policy.Context(paneCount: 2)
        var policy = Policy(
            locksPanes: true,
            showsEndOfLineMarkers: true,
            showsLineDifferences: false,
            showsLineNumbers: true,
            showsTopMargins: true
        )
        let before = policy
        let changes: [Policy.Change] = [
            .set(.wrapLines, checked: true),
            .set(.viewEndOfLineMarkers, checked: true),
            .toggle(.lockPanes),
            .set(.viewMargins, checked: false),
            .toggle(.viewLineNumbers),
            .set(.viewWhitespace, checked: true),
            .toggle(.viewLineDifferences),
            .set(.viewTopMargins, checked: false)
        ]

        let mutation = try policy.apply(changes, in: context)

        XCTAssertEqual(mutation.before, before)
        XCTAssertEqual(mutation.after, policy)
        XCTAssertEqual(mutation.appliedChanges, changes)
        XCTAssertEqual(
            mutation.changedCommands,
            [
                .wrapLines,
                .lockPanes,
                .viewLineNumbers,
                .viewWhitespace,
                .viewLineDifferences,
                .viewTopMargins
            ]
        )
        XCTAssertEqual(
            policy,
            Policy(
                showsWhitespace: true,
                showsEndOfLineMarkers: true,
                showsLineDifferences: true,
                wrapsLines: true
            )
        )
    }

    func testBatchRollsBackOnDisabledDuplicateLimitAndCancellationDuringWork() throws {
        let allCommands = try Policy.Context(paneCount: 2)
        let withoutWrap = try Policy.Context(
            paneCount: 2,
            supportedCommands: Set(Command.allCases).subtracting([.wrapLines])
        )
        let baseline = Policy(
            locksPanes: true,
            showsEndOfLineMarkers: true,
            showsLineDifferences: false,
            showsLineNumbers: true,
            showsTopMargins: true
        )

        var disabledPolicy = baseline
        assertPolicyError(.commandDisabled(.wrapLines, reason: .unsupportedByEditor(.wrapLines))) {
            try disabledPolicy.apply(
                [.toggle(.viewWhitespace), .toggle(.wrapLines)],
                in: withoutWrap
            )
        }
        XCTAssertEqual(disabledPolicy, baseline)

        var duplicatePolicy = baseline
        assertPolicyError(.duplicateCommand(.viewMargins)) {
            try duplicatePolicy.apply(
                [.toggle(.viewWhitespace), .toggle(.viewMargins), .toggle(.viewMargins)],
                in: allCommands
            )
        }
        XCTAssertEqual(duplicatePolicy, baseline)

        var excessivePolicy = baseline
        let excessive = Array(
            repeating: Policy.Change.toggle(.viewWhitespace),
            count: Policy.maximumMutationCount + 1
        )
        assertPolicyError(.tooManyChanges(maximumCount: Policy.maximumMutationCount)) {
            try excessivePolicy.apply(excessive, in: allCommands)
        }
        XCTAssertEqual(excessivePolicy, baseline)

        var workCancelledPolicy = baseline
        let workProbe = EditorViewCancellationProbe(throwOnCheck: 3)
        assertPolicyError(.cancelled) {
            try workCancelledPolicy.apply(
                [
                    .toggle(.viewWhitespace),
                    .toggle(.viewMargins),
                    .toggle(.wrapLines)
                ],
                in: allCommands,
                cancellationCheck: { try workProbe.check() }
            )
        }
        XCTAssertEqual(workProbe.count, 3)
        XCTAssertEqual(workCancelledPolicy, baseline)

        var finalCheckPolicy = baseline
        let finalProbe = EditorViewCancellationProbe(throwOnCheck: 4)
        assertPolicyError(.cancelled) {
            try finalCheckPolicy.apply(
                [.toggle(.viewWhitespace), .toggle(.viewMargins)],
                in: allCommands,
                cancellationCheck: { try finalProbe.check() }
            )
        }
        XCTAssertEqual(finalProbe.count, 4)
        XCTAssertEqual(finalCheckPolicy, baseline)
    }

    func testCancellationChecksStateEnumerationPersistenceAndRestoration() throws {
        let context = try Policy.Context(paneCount: 2)
        let stateProbe = EditorViewCancellationProbe()
        _ = try Policy.default.commandStates(
            in: context,
            cancellationCheck: { try stateProbe.check() }
        )
        XCTAssertEqual(stateProbe.count, Command.allCases.count + 2)

        let stateCancellation = EditorViewCancellationProbe(throwOnCheck: 5)
        assertPolicyError(.cancelled) {
            try Policy.default.commandStates(
                in: context,
                cancellationCheck: { try stateCancellation.check() }
            )
        }

        let encodeCancellation = EditorViewCancellationProbe(throwOnCheck: 2)
        assertPolicyError(.cancelled) {
            try Policy.default.encodedData(
                cancellationCheck: { try encodeCancellation.check() }
            )
        }

        let decodeCancellation = EditorViewCancellationProbe(throwOnCheck: 1)
        assertPolicyError(.cancelled) {
            try Policy.decode(
                from: Data(repeating: 0x20, count: Policy.maximumEncodedBytes + 1),
                cancellationCheck: { try decodeCancellation.check() }
            )
        }

        let scanCancellation = EditorViewCancellationProbe(throwOnCheck: 3)
        let scanWork = Data((String(repeating: " ", count: 512) + "?").utf8)
        assertPolicyError(.cancelled) {
            try Policy.decode(
                from: scanWork,
                cancellationCheck: { try scanCancellation.check() }
            )
        }

        let restoreCancellation = EditorViewCancellationProbe(throwOnCheck: 1)
        assertPolicyError(.cancelled) {
            try Policy.restored(
                from: nil,
                cancellationCheck: { try restoreCancellation.check() }
            )
        }
    }

    func testDefaultCancellationCheckHonorsCancelledTaskAcrossOperations() async throws {
        let context = try Policy.Context(paneCount: 2)
        let data = try Self.allCheckedPolicy.encodedData()

        let statesError = await Task { () -> EditorViewPolicyError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Policy.default.commandStates(in: context)
                return nil
            } catch {
                return error as? EditorViewPolicyError
            }
        }.value
        XCTAssertEqual(statesError, .cancelled)

        let applyTask = Task.detached {
            @Sendable [context, initialPolicy = Self.allCheckedPolicy] () -> ApplyCancellationResult in
            var policy = initialPolicy
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try policy.apply(.viewMargins, in: context)
                return ApplyCancellationResult(error: nil, policy: policy)
            } catch {
                return ApplyCancellationResult(
                    error: error as? EditorViewPolicyError,
                    policy: policy
                )
            }
        }
        let applyResult = await applyTask.value
        XCTAssertEqual(applyResult.error, .cancelled)
        XCTAssertEqual(applyResult.policy, Self.allCheckedPolicy)

        let encodeError = await Task { () -> EditorViewPolicyError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Policy.default.encodedData()
                return nil
            } catch {
                return error as? EditorViewPolicyError
            }
        }.value
        XCTAssertEqual(encodeError, .cancelled)

        let decodeError = await Task { () -> EditorViewPolicyError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Policy.decode(from: data)
                return nil
            } catch {
                return error as? EditorViewPolicyError
            }
        }.value
        XCTAssertEqual(decodeError, .cancelled)

        let restoreError = await Task { () -> EditorViewPolicyError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Policy.restored(from: nil)
                return nil
            } catch {
                return error as? EditorViewPolicyError
            }
        }.value
        XCTAssertEqual(restoreError, .cancelled)
    }

    func testDecodeChecksEveryScanIntervalAndAllFinalCheckpoints() throws {
        let data = Data(Self.defaultJSON.utf8)
        let scanProbe = EditorViewCancellationProbe()

        XCTAssertEqual(
            try Policy.decode(
                from: data,
                cancellationCheck: { try scanProbe.check() }
            ),
            .default
        )
        XCTAssertEqual(scanProbe.count, 8)

        let prefixedData = Data((String(repeating: " ", count: 64) + Self.defaultJSON).utf8)
        let prefixedProbe = EditorViewCancellationProbe()
        XCTAssertEqual(
            try Policy.decode(
                from: prefixedData,
                cancellationCheck: { try prefixedProbe.check() }
            ),
            .default
        )
        XCTAssertEqual(prefixedProbe.count, 9)

        for finalCheckpoint in [6, 7, 8] {
            let probe = EditorViewCancellationProbe(throwOnCheck: finalCheckpoint)
            assertPolicyError(.cancelled) {
                try Policy.decode(
                    from: data,
                    cancellationCheck: { try probe.check() }
                )
            }
            XCTAssertEqual(probe.count, finalCheckpoint)
        }
    }

    func testDeterministicVersionedPersistenceAndBoundedCodableRoundTrip() throws {
        let policy = Policy(
            locksPanes: true,
            showsWhitespace: true,
            showsEndOfLineMarkers: true,
            showsLineDifferences: false,
            showsLineNumbers: true,
            showsMargins: true,
            showsTopMargins: true,
            wrapsLines: true
        )
        let expectedJSON =
            #"{"locksPanes":true,"schemaVersion":1,"showsEndOfLineMarkers":true,"#
            + #""showsLineDifferences":false,"showsLineNumbers":true,"showsMargins":true,"#
            + #""showsTopMargins":true,"showsWhitespace":true,"wrapsLines":true}"#

        let first = try policy.encodedData()
        let second = try policy.encodedData()

        XCTAssertEqual(first, second)
        XCTAssertEqual(String(decoding: first, as: UTF8.self), expectedJSON)
        XCTAssertFalse(first.contains(0x0A))
        XCTAssertLessThanOrEqual(first.count, Policy.maximumEncodedBytes)
        XCTAssertEqual(try Policy.decode(from: first), policy)
        XCTAssertEqual(try Policy.decode(from: first).encodedData(), first)
        XCTAssertNoThrow(try policy.validate())
        assertPolicyError(.boundedDecodingRequired) {
            try JSONDecoder().decode(Policy.self, from: first)
        }

        requireSendable(policy)
        requireSendable(Command.lockPanes)
        requireSendable(Policy.DisabledReason.noActiveEditor)
        requireSendable(Policy.Availability.enabled)
        requireSendable(EditorViewPolicyError.cancelled)
    }

    func testEachPropertyUsesItsSingleCanonicalWireKey() throws {
        let baselineData = try Self.allFalsePolicy.encodedData()
        let baseline = String(decoding: baselineData, as: UTF8.self)
        let expectedKeys = Set(["schemaVersion"] + commandWireKeys.map(\.wireKey))
        XCTAssertEqual(Set(try rootObject(from: baselineData).keys), expectedKeys)

        for ((command, oneHotPolicy), mapping) in zip(oneHotPolicies, commandWireKeys) {
            XCTAssertEqual(command, mapping.command)
            let needle = "\"\(mapping.wireKey)\":false"
            XCTAssertTrue(baseline.contains(needle))
            let expected = baseline.replacingOccurrences(
                of: needle,
                with: "\"\(mapping.wireKey)\":true"
            )
            let encoded = try oneHotPolicy.encodedData()

            XCTAssertEqual(String(decoding: encoded, as: UTF8.self), expected)
            XCTAssertEqual(try Policy.decode(from: encoded), oneHotPolicy)
        }
    }

    func testDecodeRequiresExactCurrentSchemaFieldsAndTypes() throws {
        let requiredFields = [
            "schemaVersion",
            "locksPanes",
            "showsWhitespace",
            "showsEndOfLineMarkers",
            "showsLineDifferences",
            "showsLineNumbers",
            "showsMargins",
            "showsTopMargins",
            "wrapsLines"
        ]
        let root = try defaultRootObject()
        XCTAssertEqual(Set(root.keys), Set(requiredFields))

        for field in requiredFields {
            var missing = root
            missing.removeValue(forKey: field)
            assertPolicyError(.malformedPersistence) {
                try Policy.decode(from: JSONSerialization.data(withJSONObject: missing))
            }
        }

        let wrongTypes: [(String, Any)] = [
            ("schemaVersion", "1"),
            ("locksPanes", 0),
            ("showsWhitespace", "false"),
            ("showsEndOfLineMarkers", NSNull()),
            ("showsLineDifferences", 1),
            ("showsLineNumbers", "false"),
            ("showsMargins", []),
            ("showsTopMargins", [:]),
            ("wrapsLines", "true")
        ]
        for (field, value) in wrongTypes {
            var wrong = root
            wrong[field] = value
            assertPolicyError(.malformedPersistence) {
                try Policy.decode(from: JSONSerialization.data(withJSONObject: wrong))
            }
        }
    }

    func testDecodeRejectsUnknownVersionDuplicateAndMalformedJSON() {
        assertPolicyError(.unknownField("alpha")) {
            try Policy.decode(
                from: json(addingRootMembers: #""zeta":true,"alpha":false"#)
            )
        }

        for version in [-1, 0, 2, 99] {
            assertPolicyError(.unsupportedSchemaVersion(version)) {
                try Policy.decode(
                    from: replacing(
                        #""schemaVersion":1"#,
                        with: #""schemaVersion":\#(version)"#
                    )
                )
            }
        }

        assertPolicyError(.duplicateJSONKey("schemaVersion")) {
            try Policy.decode(
                from: json(addingRootMembers: #""schema\u0056ersion":1"#)
            )
        }
        assertPolicyError(.duplicateJSONKey("x")) {
            try Policy.decode(
                from: json(addingRootMembers: #""future":{"x":1,"\u0078":2}"#)
            )
        }

        let invalidPayloads: [(Data, EditorViewPolicyError)] = [
            (Data(), .invalidJSON),
            (Data("null".utf8), .malformedPersistence),
            (Data("[]".utf8), .malformedPersistence),
            (Data("{".utf8), .invalidJSON),
            (Data((Self.defaultJSON + " trailing").utf8), .invalidJSON),
            (Data([0xFF]), .invalidJSON),
            (replacing(#""schemaVersion":1"#, with: #""schemaVersion":01"#), .malformedPersistence),
            (replacing(#""wrapsLines":false"#, with: #""wrapsLines":null"#), .malformedPersistence)
        ]
        for (payload, expected) in invalidPayloads {
            assertPolicyError(expected) {
                try Policy.decode(from: payload)
            }
        }
    }

    func testDecodeEnforcesByteAndStructuralBoundaries() throws {
        var exactBytes = Data(Self.defaultJSON.utf8)
        exactBytes.append(
            Data(repeating: 0x20, count: Policy.maximumEncodedBytes - exactBytes.count)
        )
        XCTAssertEqual(exactBytes.count, Policy.maximumEncodedBytes)
        XCTAssertEqual(try Policy.decode(from: exactBytes), .default)

        var oversized = exactBytes
        oversized.append(0x20)
        assertPolicyError(.persistenceDataTooLarge(maximumBytes: Policy.maximumEncodedBytes)) {
            try Policy.decode(from: oversized)
        }

        assertPolicyError(.unknownField("future")) {
            try Policy.decode(from: json(addingRootMembers: #""future":[[[0]]]"#))
        }
        assertPolicyError(.jsonNestingTooDeep(maximumDepth: 4)) {
            try Policy.decode(from: json(addingRootMembers: #""future":[[[[0]]]]"#))
        }

        let sixteenValues = Array(repeating: "0", count: 16).joined(separator: ",")
        assertPolicyError(.unknownField("future")) {
            try Policy.decode(
                from: json(addingRootMembers: #""future":[\#(sixteenValues)]"#)
            )
        }
        let seventeenValues = Array(repeating: "0", count: 17).joined(separator: ",")
        assertPolicyError(.jsonContainerTooLarge(maximumElements: 16)) {
            try Policy.decode(
                from: json(addingRootMembers: #""future":[\#(seventeenValues)]"#)
            )
        }

        let exactlyThirtyTwoValues = Array(repeating: "[0,0]", count: 7)
            .joined(separator: ",")
        assertPolicyError(.unknownField("future")) {
            try Policy.decode(
                from: json(addingRootMembers: #""future":[\#(exactlyThirtyTwoValues)]"#)
            )
        }
        let excessiveValues = Array(repeating: "[0,0]", count: 8).joined(separator: ",")
        assertPolicyError(.tooManyJSONValues(maximumValues: 32)) {
            try Policy.decode(
                from: json(addingRootMembers: #""future":[\#(excessiveValues)]"#)
            )
        }

        let maximumString = String(repeating: "x", count: 254)
        assertPolicyError(.unknownField(maximumString)) {
            try Policy.decode(
                from: json(addingRootMembers: #""\#(maximumString)":true"#)
            )
        }
        let oversizedString = String(repeating: "x", count: 255)
        assertPolicyError(.jsonStringTooLarge(maximumBytes: 256)) {
            try Policy.decode(
                from: json(addingRootMembers: #""\#(oversizedString)":true"#)
            )
        }

        let maximumNumber = 9_999_999_999_999_999
        assertPolicyError(.unsupportedSchemaVersion(maximumNumber)) {
            try Policy.decode(
                from: replacing(
                    #""schemaVersion":1"#,
                    with: #""schemaVersion":\#(maximumNumber)"#
                )
            )
        }
        assertPolicyError(.jsonNumberTooLarge(maximumBytes: 16)) {
            try Policy.decode(
                from: replacing(
                    #""schemaVersion":1"#,
                    with: #""schemaVersion":99999999999999999"#
                )
            )
        }
    }

    func testDecodeEnforcesObjectDepthAndMemberBoundaries() {
        assertPolicyError(.unknownField("future")) {
            try Policy.decode(
                from: json(addingRootMembers: #""future":{"a":{"b":{"c":0}}}"#)
            )
        }
        assertPolicyError(.jsonNestingTooDeep(maximumDepth: 4)) {
            try Policy.decode(
                from: json(addingRootMembers: #""future":{"a":{"b":{"c":{"d":0}}}}"#)
            )
        }

        let sixteenMembers = (0..<16)
            .map { #""k\#($0)":0"# }
            .joined(separator: ",")
        assertPolicyError(.unknownField("future")) {
            try Policy.decode(
                from: json(addingRootMembers: #""future":{\#(sixteenMembers)}"#)
            )
        }

        let seventeenMembers = (0..<17)
            .map { #""k\#($0)":0"# }
            .joined(separator: ",")
        assertPolicyError(.jsonContainerTooLarge(maximumElements: 16)) {
            try Policy.decode(
                from: json(addingRootMembers: #""future":{\#(seventeenMembers)}"#)
            )
        }
    }

    func testDecodeStringLimitCountsMultibyteAndEscapedWireBytes() {
        let scalar = "\u{E9}"
        let maximumMultibyteKey = String(repeating: scalar, count: 126) + "xx"
        XCTAssertEqual(maximumMultibyteKey.utf8.count, 254)
        assertPolicyError(.unknownField(maximumMultibyteKey)) {
            try Policy.decode(
                from: json(addingRootMembers: "\"\(maximumMultibyteKey)\":true")
            )
        }

        let oversizedMultibyteKey = maximumMultibyteKey + "x"
        XCTAssertEqual(oversizedMultibyteKey.utf8.count, 255)
        assertPolicyError(.jsonStringTooLarge(maximumBytes: 256)) {
            try Policy.decode(
                from: json(addingRootMembers: "\"\(oversizedMultibyteKey)\":true")
            )
        }

        let maximumEscapedKey = String(repeating: "\\u0061", count: 42) + "xx"
        XCTAssertEqual(maximumEscapedKey.utf8.count, 254)
        assertPolicyError(.unknownField(String(repeating: "a", count: 42) + "xx")) {
            try Policy.decode(
                from: json(addingRootMembers: "\"\(maximumEscapedKey)\":true")
            )
        }

        let oversizedEscapedKey = maximumEscapedKey + "x"
        XCTAssertEqual(oversizedEscapedKey.utf8.count, 255)
        assertPolicyError(.jsonStringTooLarge(maximumBytes: 256)) {
            try Policy.decode(
                from: json(addingRootMembers: "\"\(oversizedEscapedKey)\":true")
            )
        }
    }

    func testRestorationIsDeterministicAndCancellationIsNeverReset() throws {
        let custom = Policy(
            locksPanes: true,
            showsWhitespace: true,
            showsEndOfLineMarkers: true,
            showsLineDifferences: false,
            showsLineNumbers: true,
            showsMargins: true,
            showsTopMargins: true,
            wrapsLines: true
        )
        XCTAssertEqual(try Policy.restored(from: custom.encodedData()), custom)
        XCTAssertEqual(try Policy.restored(from: nil), .default)

        let invalidPayloads = [
            Data(),
            Data("{".utf8),
            Data([0xFF]),
            replacing(#""schemaVersion":1"#, with: #""schemaVersion":2"#),
            json(addingRootMembers: #""future":true"#),
            replacing(#""wrapsLines":false"#, with: #""wrapsLines":"false""#)
        ]
        for payload in invalidPayloads {
            XCTAssertEqual(try Policy.restored(from: payload), .default)
        }

        let probe = EditorViewCancellationProbe(throwOnCheck: 2)
        assertPolicyError(.cancelled) {
            try Policy.restored(
                from: custom.encodedData(),
                cancellationCheck: { try probe.check() }
            )
        }
    }

    func testRestorationChecksCancellationBeforeReturningFallback() {
        let probe = EditorViewCancellationProbe(throwOnCheck: 4)

        assertPolicyError(.cancelled) {
            try Policy.restored(
                from: Data(),
                cancellationCheck: { try probe.check() }
            )
        }
        XCTAssertEqual(probe.count, 4)
    }

    func testDisplayPreferenceProjectionPreservesUnrelatedPreferences() throws {
        let font = try EditorFontDescriptor(familyName: "JetBrains Mono", pointSize: 15.5)
        let sourcePreferences = try EditorDisplayPreferences(
            font: font,
            zoomStep: 23,
            syntaxHighlightingLanguage: .swift,
            showsWhitespace: true,
            showsEndOfLineMarkers: false,
            showsLineDifferences: false,
            showsLineNumbers: true,
            showsMargins: false,
            showsTopMargin: true,
            wrapsLines: false
        )
        let imported = Policy(locksPanes: true, displayPreferences: sourcePreferences)

        XCTAssertTrue(imported.locksPanes)
        XCTAssertTrue(imported.showsWhitespace)
        XCTAssertFalse(imported.showsEndOfLineMarkers)
        XCTAssertFalse(imported.showsLineDifferences)
        XCTAssertTrue(imported.showsLineNumbers)
        XCTAssertFalse(imported.showsMargins)
        XCTAssertTrue(imported.showsTopMargins)
        XCTAssertFalse(imported.wrapsLines)

        let replacement = Policy(
            showsWhitespace: false,
            showsEndOfLineMarkers: true,
            showsLineDifferences: true,
            showsLineNumbers: false,
            showsMargins: true,
            showsTopMargins: false,
            wrapsLines: true
        )
        let projected = replacement.applying(to: sourcePreferences)

        XCTAssertEqual(projected.font, sourcePreferences.font)
        XCTAssertEqual(projected.zoomStep, sourcePreferences.zoomStep)
        XCTAssertEqual(
            projected.syntaxHighlightingLanguage,
            sourcePreferences.syntaxHighlightingLanguage
        )
        XCTAssertEqual(projected.schemaVersion, sourcePreferences.schemaVersion)
        XCTAssertFalse(projected.showsWhitespace)
        XCTAssertTrue(projected.showsEndOfLineMarkers)
        XCTAssertTrue(projected.showsLineDifferences)
        XCTAssertFalse(projected.showsLineNumbers)
        XCTAssertTrue(projected.showsMargins)
        XCTAssertFalse(projected.showsTopMargin)
        XCTAssertTrue(projected.wrapsLines)
        XCTAssertEqual(
            sourcePreferences,
            try EditorDisplayPreferences(
                font: font,
                zoomStep: 23,
                syntaxHighlightingLanguage: .swift,
                showsWhitespace: true,
                showsEndOfLineMarkers: false,
                showsLineDifferences: false,
                showsLineNumbers: true,
                showsMargins: false,
                showsTopMargin: true,
                wrapsLines: false
            )
        )
    }

    func testDisplayPreferenceImportAndProjectionAreOneHot() throws {
        let font = EditorDisplayPreferences.default.font
        let allDisplayFlagsOff = try EditorDisplayPreferences(
            font: font,
            showsLineDifferences: false
        )
        let oneHotPreferences: [(Command, EditorDisplayPreferences)] = [
            (
                .viewWhitespace,
                try EditorDisplayPreferences(
                    font: font,
                    showsWhitespace: true,
                    showsLineDifferences: false
                )
            ),
            (
                .viewEndOfLineMarkers,
                try EditorDisplayPreferences(
                    font: font,
                    showsEndOfLineMarkers: true,
                    showsLineDifferences: false
                )
            ),
            (
                .viewLineDifferences,
                try EditorDisplayPreferences(font: font, showsLineDifferences: true)
            ),
            (
                .viewLineNumbers,
                try EditorDisplayPreferences(
                    font: font,
                    showsLineDifferences: false,
                    showsLineNumbers: true
                )
            ),
            (
                .viewMargins,
                try EditorDisplayPreferences(
                    font: font,
                    showsLineDifferences: false,
                    showsMargins: true
                )
            ),
            (
                .viewTopMargins,
                try EditorDisplayPreferences(
                    font: font,
                    showsLineDifferences: false,
                    showsTopMargin: true
                )
            ),
            (
                .wrapLines,
                try EditorDisplayPreferences(
                    font: font,
                    showsLineDifferences: false,
                    wrapsLines: true
                )
            )
        ]

        for (command, preferences) in oneHotPreferences {
            XCTAssertEqual(displayCheckedCommands(in: preferences), [command])
            XCTAssertEqual(
                checkedCommands(in: Policy(displayPreferences: preferences)),
                [command]
            )
        }

        for (command, oneHotPolicy) in oneHotPolicies where command != .lockPanes {
            let projected = oneHotPolicy.applying(to: allDisplayFlagsOff)
            XCTAssertEqual(displayCheckedCommands(in: projected), [command])
        }

        let lockOnly = Policy(
            locksPanes: true,
            displayPreferences: allDisplayFlagsOff
        )
        XCTAssertEqual(checkedCommands(in: lockOnly), [.lockPanes])
        XCTAssertEqual(lockOnly.applying(to: allDisplayFlagsOff), allDisplayFlagsOff)
    }

    private static let allFalsePolicy = Policy(showsLineDifferences: false)

    private static let allCheckedPolicy = Policy(
        locksPanes: true,
        showsWhitespace: true,
        showsEndOfLineMarkers: true,
        showsLineDifferences: true,
        showsLineNumbers: true,
        showsMargins: true,
        showsTopMargins: true,
        wrapsLines: true
    )

    private var oneHotPolicies: [(Command, Policy)] {
        [
            (
                .lockPanes,
                Policy(locksPanes: true, showsLineDifferences: false)
            ),
            (
                .viewWhitespace,
                Policy(showsWhitespace: true, showsLineDifferences: false)
            ),
            (
                .viewEndOfLineMarkers,
                Policy(showsEndOfLineMarkers: true, showsLineDifferences: false)
            ),
            (.viewLineDifferences, Policy(showsLineDifferences: true)),
            (
                .viewLineNumbers,
                Policy(showsLineDifferences: false, showsLineNumbers: true)
            ),
            (
                .viewMargins,
                Policy(showsLineDifferences: false, showsMargins: true)
            ),
            (
                .viewTopMargins,
                Policy(showsLineDifferences: false, showsTopMargins: true)
            ),
            (
                .wrapLines,
                Policy(showsLineDifferences: false, wrapsLines: true)
            )
        ]
    }

    private var commandWireKeys: [(command: Command, wireKey: String)] {
        [
            (.lockPanes, "locksPanes"),
            (.viewWhitespace, "showsWhitespace"),
            (.viewEndOfLineMarkers, "showsEndOfLineMarkers"),
            (.viewLineDifferences, "showsLineDifferences"),
            (.viewLineNumbers, "showsLineNumbers"),
            (.viewMargins, "showsMargins"),
            (.viewTopMargins, "showsTopMargins"),
            (.wrapLines, "wrapsLines")
        ]
    }

    private func policy(checkedCommands: Set<Command>) -> Policy {
        Policy(
            locksPanes: checkedCommands.contains(.lockPanes),
            showsWhitespace: checkedCommands.contains(.viewWhitespace),
            showsEndOfLineMarkers: checkedCommands.contains(.viewEndOfLineMarkers),
            showsLineDifferences: checkedCommands.contains(.viewLineDifferences),
            showsLineNumbers: checkedCommands.contains(.viewLineNumbers),
            showsMargins: checkedCommands.contains(.viewMargins),
            showsTopMargins: checkedCommands.contains(.viewTopMargins),
            wrapsLines: checkedCommands.contains(.wrapLines)
        )
    }

    private func checkedCommands(in policy: Policy) -> [Command] {
        Command.allCases.filter { policy.isChecked($0) }
    }

    private func displayCheckedCommands(
        in preferences: EditorDisplayPreferences
    ) -> [Command] {
        [
            (.viewWhitespace, preferences.showsWhitespace),
            (.viewEndOfLineMarkers, preferences.showsEndOfLineMarkers),
            (.viewLineDifferences, preferences.showsLineDifferences),
            (.viewLineNumbers, preferences.showsLineNumbers),
            (.viewMargins, preferences.showsMargins),
            (.viewTopMargins, preferences.showsTopMargin),
            (.wrapLines, preferences.wrapsLines)
        ].compactMap { command, isChecked in isChecked ? command : nil }
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }

    private func defaultRootObject() throws -> [String: Any] {
        try rootObject(from: Data(Self.defaultJSON.utf8))
    }

    private func rootObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func replacing(_ target: String, with replacement: String) -> Data {
        let result = Self.defaultJSON.replacingOccurrences(of: target, with: replacement)
        XCTAssertNotEqual(result, Self.defaultJSON, "Test fixture replacement did not match")
        return Data(result.utf8)
    }

    private func json(addingRootMembers members: String) -> Data {
        let prefix = String(Self.defaultJSON.dropLast())
        return Data((prefix + "," + members + "}").utf8)
    }

    private func assertPolicyError<T>(
        _ expected: EditorViewPolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? EditorViewPolicyError, expected, file: file, line: line)
        }
    }
}

private final class EditorViewCancellationProbe: @unchecked Sendable {
    enum ProbeError: Error {
        case cancelled
    }

    private let lock = NSLock()
    private let throwOnCheck: Int?
    private var checkCount = 0

    init(throwOnCheck: Int? = nil) {
        self.throwOnCheck = throwOnCheck
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return checkCount
    }

    func check() throws {
        lock.lock()
        checkCount += 1
        let shouldThrow = checkCount == throwOnCheck
        lock.unlock()
        if shouldThrow { throw ProbeError.cancelled }
    }
}
