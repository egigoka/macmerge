import Foundation
import MacMergeCore
import XCTest

private typealias Adoption = EditorPreferencesAdoption
private typealias Workflow = EditorPreferencesWorkflow

final class EditorPreferencesAdoptionTests: XCTestCase {
    func testTargetsDerivationProjectsSuccessorState() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let plan = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2, tabInsertion: .spaces)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )

        let targets = plan.targets
        XCTAssertEqual(targets.general.display, plan.successor.display)
        XCTAssertEqual(targets.general.view, plan.successor.view)
        XCTAssertEqual(targets.general.editing, plan.successor.editing)
        XCTAssertEqual(targets.compareAndMerge.preferences, plan.successor.compareAndMerge)
        XCTAssertEqual(targets.syntax.selection, plan.successor.syntax.selection)
        XCTAssertEqual(targets.syntax.isHighlightingEnabled, plan.successor.syntax.isHighlightingEnabled)
        XCTAssertEqual(targets.syntax.syntax, plan.resolvedSchemes.syntax)
        XCTAssertEqual(targets.syntax.color, plan.resolvedSchemes.color)
        XCTAssertEqual(plan.changedPages, [.general])
        XCTAssertEqual(
            Adoption.editorTargets(state: plan.successor, resolvedSchemes: plan.resolvedSchemes),
            targets
        )
    }

    func testStateCASMatchesExactContents() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let plan = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )

        XCTAssertTrue(try plan.expectedStateCAS.matches(current))
        XCTAssertNoThrow(try plan.expectedStateCAS.validate(current))
        XCTAssertEqual(plan.expectedStateCAS.revision, current.revision)
        XCTAssertEqual(plan.successor.revision.generation, current.revision.generation + 1)
    }

    func testCatalogFingerprintsPinFullContents() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let plan = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        XCTAssertNoThrow(
            try plan.validateCurrentState(
                current,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
        )

        let changedColor = try makeColorScheme(
            identifier: catalogs.customColor.identifier,
            displayName: "Changed Color"
        )
        let changedColorCatalog = try Workflow.ColorSchemeCatalog(
            revision: catalogs.color.revision,
            schemes: [EditorColorScheme.standard, changedColor]
        )
        XCTAssertThrowsError(
            try plan.validateCurrentState(
                current,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: changedColorCatalog
            )
        ) { error in
            XCTAssertEqual(
                error as? Workflow.Error,
                .staleColorSchemeCatalog(
                    expected: catalogs.color.revision,
                    actual: changedColorCatalog.revision
                )
            )
        }

        let changedSyntax = try makeSyntaxScheme(id: catalogs.selectedSyntax.id, name: "Changed")
        let changedSyntaxCatalog = try SyntaxSchemeCatalog(
            customSchemes: [changedSyntax, catalogs.fallbackSyntax],
            revision: catalogs.syntax.revision
        )
        XCTAssertThrowsError(
            try plan.validateCurrentState(
                current,
                syntaxCatalog: changedSyntaxCatalog,
                colorCatalog: catalogs.color
            )
        ) { error in
            XCTAssertEqual(
                error as? Workflow.Error,
                .syntaxCatalog(
                    .staleCatalog(
                        expected: catalogs.syntax.revision,
                        actual: changedSyntaxCatalog.revision
                    )
                )
            )
        }
    }

    func testColorFallbackFlagReflectsResolution() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let hit = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        XCTAssertFalse(hit.didFallBackColorScheme)
        XCTAssertFalse(hit.targets.syntax.didFallBackColorScheme)
        XCTAssertEqual(hit.targets.syntax.color, catalogs.customColor)

        let missingState = try makeState(
            colorScheme: Workflow.ColorSchemeSelection(
                selectedIdentifier: try Workflow.ColorSchemeIdentifier("missing/color")
            )
        )
        let miss = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 8)),
            current: missingState,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        XCTAssertTrue(miss.didFallBackColorScheme)
        XCTAssertTrue(miss.targets.syntax.didFallBackColorScheme)
        XCTAssertEqual(miss.targets.syntax.color, .standard)
    }

    func testSyntaxNilWhenDisabled() throws {
        let catalogs = try makeCatalogs()
        let disabled = Workflow.SyntaxPreferences(
            isHighlightingEnabled: false,
            selection: SyntaxSchemeSelection(
                selectedIdentifier: catalogs.selectedSyntax.id,
                fallbackIdentifier: catalogs.fallbackSyntax.id
            )
        )
        let current = try makeState()
        let plan = try Adoption.plan(
            intent: .setSyntax(disabled),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        XCTAssertNil(plan.resolvedSchemes.syntax)
        XCTAssertNil(plan.targets.syntax.syntax)
        XCTAssertFalse(plan.targets.syntax.isHighlightingEnabled)
        XCTAssertEqual(plan.targets.syntax.selection, disabled.selection)
    }

    func testPersistenceRoundTrip() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let plan = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )

        let data = try Adoption.encode(plan.successor)
        XCTAssertEqual(data, persistenceData(from: plan.persistence))
        XCTAssertEqual(try Adoption.decode(from: data), plan.successor)
        XCTAssertEqual(try Adoption.encode(try Adoption.decode(from: data)), data)
        XCTAssertEqual(try Adoption.restore(from: data), plan.successor)

        let restoredDefault = try Adoption.restore(from: nil, defaultLineage: 901)
        XCTAssertEqual(restoredDefault.revision, Workflow.Revision(lineage: 901, generation: 0))
    }

    func testLeaseExecutionCommitsExactTransaction() async throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let plan = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2, tabInsertion: .spaces)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        let executor = AdoptionTestExecutor(initialState: current)
        let outcome = try await plan.execute(
            on: executor,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )

        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected completed outcome")
        }
        XCTAssertEqual(receipt.planning, plan.receipt)
        XCTAssertEqual(receipt.completedEffects, plan.requiredEffects)
        let executionCount = await executor.executionCount
        let persistedData = await executor.persistedData
        let appliedState = await executor.appliedState
        let reconciliation = await executor.reconciliation
        let capturedLease = await executor.lease
        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(persistedData, persistenceData(from: plan.persistence))
        XCTAssertEqual(appliedState, plan.successor)
        XCTAssertEqual(reconciliation, .successor)
        let lease = try XCTUnwrap(capturedLease)
        XCTAssertEqual(lease.expectedStateCAS, plan.expectedStateCAS)
        XCTAssertEqual(lease.successor, plan.successor)
        XCTAssertEqual(lease.persistence, plan.persistence)
    }

    func testStaleExecutionYieldsNotCommitted() async throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let plan = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )

        let stale = try Workflow.State(
            revision: Workflow.Revision(lineage: 77, generation: 1),
            display: current.display,
            view: current.view,
            editing: current.editing,
            compareAndMerge: current.compareAndMerge,
            syntax: current.syntax,
            colorScheme: current.colorScheme,
            limits: current.limits
        )
        let staleOutcome = try await plan.execute(
            on: AdoptionTestExecutor(initialState: stale),
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        guard case .notCommitted(let staleReceipt) = staleOutcome else {
            return XCTFail("Expected notCommitted for stale CAS")
        }
        XCTAssertEqual(staleReceipt.reason, .staleState)
        XCTAssertEqual(staleReceipt.blockedEffect, plan.requiredEffects[0])

        let changedColor = try makeColorScheme(
            identifier: catalogs.customColor.identifier,
            displayName: "Changed Color"
        )
        let changedColorCatalog = try Workflow.ColorSchemeCatalog(
            revision: catalogs.color.revision,
            schemes: [EditorColorScheme.standard, changedColor]
        )
        let colorOutcome = try await plan.execute(
            on: AdoptionTestExecutor(initialState: current),
            syntaxCatalog: catalogs.syntax,
            colorCatalog: changedColorCatalog
        )
        guard case .notCommitted(let colorReceipt) = colorOutcome else {
            return XCTFail("Expected notCommitted for changed color catalog")
        }
        XCTAssertEqual(colorReceipt.reason, .schemeCatalogChanged)
        XCTAssertEqual(colorReceipt.blockedEffect, plan.requiredEffects[0])

        let changedSyntax = try makeSyntaxScheme(id: catalogs.selectedSyntax.id, name: "Changed")
        let changedSyntaxCatalog = try SyntaxSchemeCatalog(
            customSchemes: [changedSyntax, catalogs.fallbackSyntax],
            revision: catalogs.syntax.revision
        )
        let syntaxOutcome = try await plan.execute(
            on: AdoptionTestExecutor(initialState: current),
            syntaxCatalog: changedSyntaxCatalog,
            colorCatalog: catalogs.color
        )
        guard case .notCommitted(let syntaxReceipt) = syntaxOutcome else {
            return XCTFail("Expected notCommitted for changed syntax catalog")
        }
        XCTAssertEqual(syntaxReceipt.reason, .schemeCatalogChanged)
        XCTAssertEqual(syntaxReceipt.blockedEffect, plan.requiredEffects[0])
    }

    func testReceiptsExposeSingleExclusiveTransaction() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let plan = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )

        XCTAssertEqual(plan.receipt.expectedRevision, current.revision)
        XCTAssertEqual(plan.receipt.successorRevision, plan.successor.revision)
        XCTAssertEqual(plan.receipt.persistence.persistenceVersion, Workflow.currentPersistenceVersion)
        XCTAssertEqual(plan.receipt.persistedByteCount, persistenceData(from: plan.persistence).count)
        XCTAssertTrue(
            plan.receipt.persistence.matches(
                canonicalData: persistenceData(from: plan.persistence)
            )
        )
        XCTAssertEqual(plan.requiredEffects.count, 1)
        guard
            case .commitExclusiveTransaction(let persistence, let successor) =
                plan.requiredEffects[0]
        else {
            return XCTFail("Expected exclusive transaction effect")
        }
        XCTAssertEqual(persistence, plan.receipt.persistence)
        XCTAssertEqual(successor, plan.successor.revision)
        XCTAssertEqual(plan.executorContract, .required)
    }

    func testStaleStateRejected() throws {
        let catalogs = try makeCatalogs()
        let current = try Workflow.State.defaults(lineage: 77)
        let plan = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 8)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )

        let changedContents = try Workflow.State(
            revision: current.revision,
            display: current.display,
            view: current.view,
            editing: Workflow.EditingPreferences(tabWidth: 2, tabInsertion: .spaces),
            compareAndMerge: current.compareAndMerge,
            syntax: current.syntax,
            colorScheme: current.colorScheme,
            limits: current.limits
        )
        XCTAssertFalse(try plan.expectedStateCAS.matches(changedContents))
        XCTAssertThrowsError(
            try plan.validateCurrentState(
                changedContents,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
        ) { error in
            XCTAssertEqual(error as? Workflow.Error, .stateContentsChanged(current.revision))
        }

        let stale = try Workflow.State(
            revision: Workflow.Revision(lineage: 77, generation: 1),
            display: current.display,
            view: current.view,
            editing: current.editing,
            compareAndMerge: current.compareAndMerge,
            syntax: current.syntax,
            colorScheme: current.colorScheme,
            limits: current.limits
        )
        XCTAssertFalse(try plan.expectedStateCAS.matches(stale))
        XCTAssertThrowsError(
            try plan.validateCurrentState(
                stale,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color
            )
        ) { error in
            XCTAssertEqual(
                error as? Workflow.Error,
                .staleRevision(expected: current.revision, actual: stale.revision)
            )
        }
    }

    func testCancelForwardsAsCancelled() throws {
        let catalogs = try makeCatalogs()
        let current = try makeCustomizedState(catalogs: catalogs)
        let check: @Sendable () throws -> Void = { throw AdoptionProbeError.stop }
        XCTAssertThrowsError(
            try Adoption.plan(
                intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2)),
                current: current,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color,
                cancellationCheck: check
            )
        ) { error in
            XCTAssertEqual(error as? Workflow.Error, .cancelled)
        }

        let plan = try Adoption.plan(
            intent: .setEditing(try Workflow.EditingPreferences(tabWidth: 2)),
            current: current,
            syntaxCatalog: catalogs.syntax,
            colorCatalog: catalogs.color
        )
        XCTAssertThrowsError(
            try plan.validateCurrentState(
                current,
                syntaxCatalog: catalogs.syntax,
                colorCatalog: catalogs.color,
                cancellationCheck: check
            )
        ) { error in
            XCTAssertEqual(error as? Workflow.Error, .cancelled)
        }
        XCTAssertThrowsError(try Adoption.encode(plan.successor, cancellationCheck: check)) { error in
            XCTAssertEqual(error as? Workflow.Error, .cancelled)
        }
    }

    // MARK: - Helpers

    private struct Catalogs: Sendable {
        let selectedSyntax: SyntaxScheme
        let fallbackSyntax: SyntaxScheme
        let syntax: SyntaxSchemeCatalog
        let customColor: EditorColorScheme
        let color: Workflow.ColorSchemeCatalog
    }

    private func makeCatalogs() throws -> Catalogs {
        let selected = try makeSyntaxScheme(id: try SyntaxSchemeIdentifier("custom.selected"), name: "Selected")
        let fallback = try makeSyntaxScheme(id: try SyntaxSchemeIdentifier("custom.fallback"), name: "Fallback")
        let syntax = try SyntaxSchemeCatalog(
            customSchemes: [fallback, selected],
            revision: SyntaxSchemeCatalogRevision(lineage: 30, generation: 4)
        )
        let customColor = try makeColorScheme(identifier: "vendor:theme/dark", displayName: "Vendor Dark")
        let color = try Workflow.ColorSchemeCatalog(
            revision: SyntaxSchemeCatalogRevision(lineage: 31, generation: 5),
            schemes: [customColor, EditorColorScheme.standard]
        )
        return Catalogs(
            selectedSyntax: selected,
            fallbackSyntax: fallback,
            syntax: syntax,
            customColor: customColor,
            color: color
        )
    }

    private func makeSyntaxScheme(
        id: SyntaxSchemeIdentifier,
        name: String
    ) throws -> SyntaxScheme {
        try SyntaxScheme(
            id: id,
            displayName: name,
            supportedLanguages: [.swift],
            applicationModes: [.textComparison]
        )
    }

    private func makeColorScheme(identifier: String, displayName: String) throws -> EditorColorScheme {
        try EditorColorScheme(
            identifier: identifier,
            displayName: displayName,
            palettes: EditorColorScheme.standard.palettes,
            differenceDecorations: EditorColorScheme.standard.differenceDecorations
        )
    }

    private func makeCustomizedState(catalogs: Catalogs) throws -> Workflow.State {
        try Workflow.State(
            revision: Workflow.Revision(lineage: 77, generation: 0),
            display: EditorDisplayPreferences(
                font: EditorFontDescriptor(familyName: "SF Mono", pointSize: 14),
                zoomStep: 17,
                syntaxHighlightingLanguage: .swift,
                showsWhitespace: true,
                showsEndOfLineMarkers: true,
                showsLineDifferences: false,
                showsLineNumbers: true,
                showsMargins: true,
                showsTopMargin: true,
                wrapsLines: true
            ),
            locksPanes: true,
            editing: Workflow.EditingPreferences(tabWidth: 8, tabInsertion: .spaces),
            compareAndMerge: Workflow.CompareAndMergePreferences(
                automaticRescanAfterEdit: true,
                copyGranularity: .inlineDifference,
                lineDifferenceGranularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: "é/:;",
                automaticMergeDestination: .right
            ),
            syntax: Workflow.SyntaxPreferences(
                selection: SyntaxSchemeSelection(
                    selectedIdentifier: catalogs.selectedSyntax.id,
                    fallbackIdentifier: catalogs.fallbackSyntax.id
                )
            ),
            colorScheme: Workflow.ColorSchemeSelection(
                selectedIdentifier: try Workflow.ColorSchemeIdentifier(catalogs.customColor.identifier)
            )
        )
    }

    private func makeState(
        colorScheme: Workflow.ColorSchemeSelection = .default
    ) throws -> Workflow.State {
        try Workflow.State(
            revision: Workflow.Revision(lineage: 77, generation: 0),
            display: .default,
            locksPanes: false,
            colorScheme: colorScheme
        )
    }

    private func persistenceData(from effect: Workflow.PersistenceEffect) -> Data {
        switch effect {
        case .store(let data): data
        }
    }
}

private enum AdoptionProbeError: Error, Sendable {
    case stop
}

private enum AdoptionReconciliation: Sendable, Equatable {
    case successor
}

private actor AdoptionTestExecutor: Workflow.PlanExecutor {
    private var state: Workflow.State?
    private(set) var executionCount = 0
    private(set) var lease: Workflow.ExecutorLease?
    private(set) var persistedData: Data?
    private(set) var appliedState: Workflow.State?
    private(set) var reconciliation: AdoptionReconciliation?

    init(initialState: Workflow.State?) {
        state = initialState
    }

    func execute(
        _ lease: Workflow.ExecutorLease,
        syntaxCatalog: SyntaxSchemeCatalog,
        colorCatalog: Workflow.ColorSchemeCatalog
    ) -> Workflow.ExecutionOutcome {
        executionCount += 1
        self.lease = lease
        let current = state
        if let current {
            do {
                try lease.expectedStateCAS.validate(current)
                try lease.resolvedSchemes.validate(
                    syntaxCatalog: syntaxCatalog,
                    colorCatalog: colorCatalog
                )
            } catch let error as Workflow.Error {
                let reason: Workflow.ExecutionFailureReason
                switch error {
                case .staleRevision, .stateContentsChanged:
                    reason = .staleState
                case .syntaxCatalog, .staleColorSchemeCatalog:
                    reason = .schemeCatalogChanged
                case .cancelled:
                    reason = .cancelled
                default:
                    reason = .rejected
                }
                if let outcome = try? Workflow.ExecutionOutcomeFactory.notCommitted(
                    lease: lease,
                    reason: reason
                ) {
                    return outcome
                }
                return Workflow.ExecutionOutcomeFactory.completed(lease: lease)
            } catch {
                return Workflow.ExecutionOutcomeFactory.completed(lease: lease)
            }
        }
        switch lease.persistence {
        case .store(let data):
            persistedData = data
        }
        if case .apply(let appliedState, _) = lease.application {
            state = lease.successor
            self.appliedState = appliedState
        }
        reconciliation = .successor
        return Workflow.ExecutionOutcomeFactory.completed(lease: lease)
    }
}
