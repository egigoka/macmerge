import CryptoKit
import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class PatchGenerationWorkflowTests: XCTestCase {
    func testPlanningOwnsPayloadAndSeparatesDisplayMetadataFromMutationPlan() throws {
        let broker = clipboardIdentity(value: 7)
        let source = makeSource(
            id: "selected",
            old: "alpha\nold\nomega\n",
            new: "alpha\nnew\nomega\n"
        )
        let unselected = makeSource(id: "ignored", old: "same\n", new: "changed\n")
        let argv = ["patch-tool", "--literal=; rm -rf /", "two words"]
        let plan = try PatchGenerationWorkflow.plan(
            request(
                sources: [unselected, source],
                selection: .only([source.id]),
                contextLines: 0,
                destination: clipboardDestination(broker),
                presentation: PatchGenerationPresentationIntent(
                    commandLine: .record(arguments: argv)
                )
            )
        )

        XCTAssertEqual(plan.sources.map(\.id), [source.id])
        XCTAssertEqual(plan.style, .unified)
        XCTAssertEqual(PatchGenerationStyle.allCases, [.unified])
        XCTAssertEqual(plan.contextLines, 0)
        XCTAssertEqual(plan.direction, .forward)
        XCTAssertEqual(plan.generatedPatchUTF8ByteCount, plan.generatedPatch.utf8.count)
        XCTAssertEqual(plan.mutation.generatedPatchSHA256, digest(Data(plan.generatedPatch.utf8)))
        XCTAssertEqual(plan.displayMetadata.commandLine, .record(arguments: argv))
        XCTAssertEqual(plan.mutation.executorContract, .required)
        guard case .clipboard(let expected, let payload) = plan.mutation.destination else {
            return XCTFail("Expected clipboard destination")
        }
        XCTAssertEqual(expected, broker)
        XCTAssertEqual(payload, plan.generatedPatch)
        XCTAssertEqual(plan.generatedPatch, patch("--- old.txt", "+++ new.txt", "@@ -2 +2 @@", "-old", "+new"))

        let alternateDisplayPlan = try PatchGenerationWorkflow.plan(
            request(
                sources: [unselected, source],
                selection: .only([source.id]),
                contextLines: 0,
                destination: clipboardDestination(broker),
                presentation: PatchGenerationPresentationIntent(
                    commandLine: .record(arguments: ["display-only"])
                )
            )
        )
        XCTAssertNotEqual(plan.displayMetadata, alternateDisplayPlan.displayMetadata)
        XCTAssertEqual(plan.mutation.planSHA256, alternateDisplayPlan.mutation.planSHA256)
        XCTAssertEqual(plan.mutation.destination, alternateDisplayPlan.mutation.destination)
        XCTAssertEqual(plan.mutation.generatedPatch, alternateDisplayPlan.mutation.generatedPatch)

        let contextPlan = try PatchGenerationWorkflow.plan(
            request(
                sources: [source],
                contextLines: 1,
                destination: clipboardDestination(broker)
            )
        )
        XCTAssertEqual(
            contextPlan.generatedPatch,
            patch(
                "--- old.txt",
                "+++ new.txt",
                "@@ -1,3 +1,3 @@",
                " alpha",
                "-old",
                "+new",
                " omega"
            )
        )
        let maximumContext = PatchGenerationPlanningLimits.hardMaximumContextLines
        XCTAssertEqual(
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [source],
                    contextLines: maximumContext,
                    destination: clipboardDestination(broker)
                )
            ).contextLines,
            maximumContext
        )
        for invalidContext in [-1, maximumContext + 1] {
            assertPlanningError(.invalidContextLines(invalidContext)) {
                try PatchGenerationWorkflow.plan(
                    request(
                        sources: [source],
                        contextLines: invalidContext,
                        destination: clipboardDestination(broker)
                    )
                )
            }
        }
    }

    func testSelectionValidationRejectsDuplicatesUnknownEmptyAndInvalidIdentifiers() throws {
        let source = makeSource(id: "source", old: "old\n", new: "new\n")
        let duplicate = makeSource(id: "source", old: "a\n", new: "b\n")
        let destination = clipboardDestination(clipboardIdentity())

        assertPlanningError(.duplicateSourceIdentifier("source")) {
            try PatchGenerationWorkflow.plan(request(sources: [source, duplicate], destination: destination))
        }
        assertPlanningError(.duplicateSelectionIdentifier("source")) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [source],
                    selection: .only([source.id, source.id]),
                    destination: destination
                )
            )
        }
        assertPlanningError(.unknownSourceIdentifier("missing")) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [source],
                    selection: .only([PatchGenerationSourceID(rawValue: "missing")]),
                    destination: destination
                )
            )
        }
        assertPlanningError(.emptySelection) {
            try PatchGenerationWorkflow.plan(
                request(sources: [source], selection: .only([]), destination: destination)
            )
        }
        let invalid = makeSource(id: "-invalid", old: "old\n", new: "new\n")
        assertPlanningError(.invalidSourceIdentifier("-invalid")) {
            try PatchGenerationWorkflow.plan(request(sources: [invalid], destination: destination))
        }
        assertPlanningError(.noDifferences) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "unchanged", old: "same\n", new: "same\n")],
                    destination: destination
                )
            )
        }
    }

    func testSourceCountSelectionAndIdentifierCapsHaveExactBoundaries() throws {
        let destination = clipboardDestination(clipboardIdentity())
        let first = makeSource(id: "id01", old: "old\n", new: "new\n")
        let second = makeSource(id: "id02", old: "left\n", new: "right\n")
        let exactIdentifierLimits = limits(
            maximumSourceIdentifierUTF8Bytes: 4
        )

        XCTAssertNoThrow(
            try PatchGenerationWorkflow.plan(
                request(sources: [first], destination: destination, limits: exactIdentifierLimits)
            )
        )
        let oversizedIdentifier = makeSource(id: "id012", old: "old\n", new: "new\n")
        assertPlanningError(.invalidSourceIdentifier("id012")) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [oversizedIdentifier],
                    destination: destination,
                    limits: exactIdentifierLimits
                )
            )
        }
        assertPlanningError(.invalidSourceIdentifier("id012")) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [first],
                    selection: .only([oversizedIdentifier.id]),
                    destination: destination,
                    limits: exactIdentifierLimits
                )
            )
        }
        assertPlanningError(.tooManySources(maximum: 1)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [first, second],
                    destination: destination,
                    limits: limits(maximumSources: 1, maximumSelectedSources: 1)
                )
            )
        }
        assertPlanningError(.tooManySelectedSources(maximum: 1)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [first, second],
                    destination: destination,
                    limits: limits(maximumSources: 2, maximumSelectedSources: 1)
                )
            )
        }

        let hardMaximum = PatchGenerationPlanningLimits.hardMaximumSourceCount
        let aboveHardMaximum = (0...hardMaximum).map { index in
            makeSource(id: "hard-\(index)", old: "old\n", new: "new\n")
        }
        assertPlanningError(.tooManySources(maximum: hardMaximum)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: aboveHardMaximum,
                    destination: destination,
                    limits: limits(
                        maximumSources: hardMaximum,
                        maximumSelectedSources: hardMaximum
                    )
                )
            )
        }
    }

    func testSnapshotRevisionOwnershipRejectsConflictingTextAndAllowsIdenticalReuse() throws {
        let identity = PatchGenerationSnapshotIdentity.document(UUID())
        let shared = PatchGenerationTextSnapshot(identity: identity, revision: 5, text: "boundary\n")
        let first = makeSource(
            id: "first",
            oldSnapshot: makeSnapshot("old\n"),
            newSnapshot: shared,
            oldPath: "first.txt",
            newPath: "shared.txt"
        )
        let second = makeSource(
            id: "second",
            oldSnapshot: shared,
            newSnapshot: makeSnapshot("new\n"),
            oldPath: "shared.txt",
            newPath: "second.txt"
        )
        let plan = try PatchGenerationWorkflow.plan(
            request(sources: [first, second], destination: clipboardDestination(clipboardIdentity()))
        )
        XCTAssertEqual(plan.sources.map(\.id.rawValue), ["first", "second"])

        let conflicting = PatchGenerationTextSnapshot(identity: identity, revision: 5, text: "changed\n")
        let invalidSecond = makeSource(
            id: "second",
            oldSnapshot: conflicting,
            newSnapshot: makeSnapshot("new\n"),
            oldPath: "shared.txt",
            newPath: "second.txt"
        )
        assertPlanningError(.conflictingSnapshotRevision) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [first, invalidSecond],
                    destination: clipboardDestination(clipboardIdentity())
                )
            )
        }

        let fileIdentity = PatchGenerationCanonicalFileIdentity(
            canonicalURL: URL(fileURLWithPath: "/tmp/file-snapshot"),
            kind: .regularFile,
            deviceID: 11,
            fileID: 22,
            generation: 33
        )
        let fileSource = makeSource(
            id: "file-revision",
            oldSnapshot: makeSnapshot("before\n", identity: .file(fileIdentity), revision: 9),
            newSnapshot: makeSnapshot("after\n", identity: .file(fileIdentity), revision: 9),
            oldPath: "before.txt",
            newPath: "after.txt"
        )
        assertPlanningError(.conflictingSnapshotRevision) {
            try PatchGenerationWorkflow.plan(
                request(sources: [fileSource], destination: clipboardDestination(clipboardIdentity()))
            )
        }
    }

    func testPathDependenciesValidateBoundariesAndReverseInStableDependencyOrder() throws {
        let boundary = makeSnapshot("middle\n", identity: .scratchpad(UUID()), revision: 10)
        let first = makeSource(
            id: "first",
            oldSnapshot: makeSnapshot("old\n"),
            newSnapshot: boundary,
            oldPath: "a.txt",
            newPath: "b.txt"
        )
        let second = makeSource(
            id: "second",
            oldSnapshot: boundary,
            newSnapshot: makeSnapshot("new\n"),
            oldPath: "b.txt",
            newPath: "c.txt"
        )
        let reversePlan = try PatchGenerationWorkflow.plan(
            request(
                sources: [first, second],
                direction: .reverse,
                destination: clipboardDestination(clipboardIdentity())
            )
        )

        XCTAssertEqual(reversePlan.sources.map(\.id.rawValue), ["second", "first"])
        XCTAssertTrue(reversePlan.generatedPatch.hasPrefix("--- c.txt\n+++ b.txt\n"))
        XCTAssertNotNil(reversePlan.generatedPatch.range(of: "--- b.txt\n+++ a.txt\n"))

        assertPlanningError(.sourcePathDependencyOrderConflict(first: first.id, second: second.id)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [second, first],
                    destination: clipboardDestination(clipboardIdentity())
                )
            )
        }
        let mismatched = makeSource(
            id: "mismatch",
            oldSnapshot: makeSnapshot("different\n"),
            newSnapshot: makeSnapshot("new\n"),
            oldPath: "b.txt",
            newPath: "d.txt"
        )
        assertPlanningError(.sourcePathDependencySnapshotMismatch(first: first.id, second: mismatched.id)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [first, mismatched],
                    destination: clipboardDestination(clipboardIdentity())
                )
            )
        }
    }

    func testReverseTopologyUsesInputOrderForIndependentReadyTies() throws {
        let boundary = makeSnapshot("middle\n", identity: .scratchpad(UUID()), revision: 7)
        let independent = makeSource(
            id: "independent",
            old: "independent-old\n",
            new: "independent-new\n",
            oldPath: "independent-old.txt",
            newPath: "independent-new.txt"
        )
        let predecessor = makeSource(
            id: "predecessor",
            oldSnapshot: makeSnapshot("old\n"),
            newSnapshot: boundary,
            oldPath: "a.txt",
            newPath: "b.txt"
        )
        let successor = makeSource(
            id: "successor",
            oldSnapshot: boundary,
            newSnapshot: makeSnapshot("new\n"),
            oldPath: "b.txt",
            newPath: "c.txt"
        )
        let trailingIndependent = makeSource(
            id: "trailing-independent",
            old: "trailing-old\n",
            new: "trailing-new\n",
            oldPath: "trailing-old.txt",
            newPath: "trailing-new.txt"
        )

        let plan = try PatchGenerationWorkflow.plan(
            request(
                sources: [independent, predecessor, successor, trailingIndependent],
                direction: .reverse,
                destination: clipboardDestination(clipboardIdentity())
            )
        )

        XCTAssertEqual(
            plan.sources.map(\.id.rawValue),
            ["independent", "successor", "predecessor", "trailing-independent"]
        )
    }

    func testPathDependencyRejectsAmbiguityAndCycle() throws {
        let duplicateOldA = makeSource(id: "a", old: "a\n", new: "b\n", oldPath: "same", newPath: "a-new")
        let duplicateOldB = makeSource(id: "b", old: "c\n", new: "d\n", oldPath: "same", newPath: "b-new")
        assertPlanningError(.ambiguousSourcePathDependency(first: duplicateOldA.id, second: duplicateOldB.id)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [duplicateOldA, duplicateOldB],
                    destination: clipboardDestination(clipboardIdentity())
                )
            )
        }

        let duplicateNewA = makeSource(id: "new-a", old: "a\n", new: "b\n", oldPath: "a-old", newPath: "same-new")
        let duplicateNewB = makeSource(id: "new-b", old: "c\n", new: "d\n", oldPath: "b-old", newPath: "same-new")
        assertPlanningError(.ambiguousSourcePathDependency(first: duplicateNewA.id, second: duplicateNewB.id)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [duplicateNewA, duplicateNewB],
                    destination: clipboardDestination(clipboardIdentity())
                )
            )
        }

        let left = makeSnapshot("left\n", identity: .document(UUID()), revision: 1)
        let right = makeSnapshot("right\n", identity: .document(UUID()), revision: 2)
        let cycleA = makeSource(id: "cycle-a", oldSnapshot: left, newSnapshot: right, oldPath: "a", newPath: "b")
        let cycleB = makeSource(id: "cycle-b", oldSnapshot: right, newSnapshot: left, oldPath: "b", newPath: "a")
        assertPlanningError(.sourcePathDependencyCycle) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [cycleA, cycleB],
                    destination: clipboardDestination(clipboardIdentity())
                )
            )
        }
    }

    func testAppendOwnsExistingBytesComposesSuccessorAndPreservesMode() throws {
        let directory = try makeTemporaryDirectory()
        let destinationURL = directory.appending(path: "output.patch")
        let existing = Data(repeating: 0x45, count: 64 * 1_024 + 1)
        try existing.write(to: destinationURL)
        XCTAssertEqual(chmod(destinationURL.path, 0o640), 0)
        let parent = try canonicalIdentity(directory, kind: .directory)
        let revision = try fileRevision(destinationURL, metadataMaximum: 1 << 20)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: existing.count, alignment: 1)
        defer { storage.deallocate() }
        existing.copyBytes(to: storage.assumingMemoryBound(to: UInt8.self), count: existing.count)
        let callerBytes = Data(bytesNoCopy: storage, count: existing.count, deallocator: .none)
        let snapshot = try PatchGenerationExistingFileSnapshot(revision: revision, data: callerBytes)
        storage.storeBytes(of: UInt8(0x58), as: UInt8.self)

        let plan = try PatchGenerationWorkflow.plan(
            request(
                sources: [makeSource(id: "append", old: "old\n", new: "new\n")],
                contextLines: 0,
                destination: .file(
                    PatchGenerationFileDestination(
                        url: destinationURL,
                        disposition: .append(
                            expectedParent: parent,
                            expected: snapshot,
                            lineEnding: .crlf
                        )
                    )
                )
            )
        )

        guard case .file(let destination) = plan.destination,
            case .append(let plannedParent, let plannedRevision) = destination.operation
        else { return XCTFail("Expected append destination") }
        XCTAssertEqual(plannedParent, parent)
        XCTAssertEqual(plannedRevision, revision)
        XCTAssertEqual(destination.finalPermissions, 0o640)
        XCTAssertEqual(
            destination.payload,
            existing + Data("\r\n".utf8) + translatingLFToCRLF(Data(plan.generatedPatch.utf8))
        )
        XCTAssertEqual(snapshot.data, existing)
        XCTAssertNotEqual(snapshot.data, callerBytes)

        var invalidRevision = revision
        invalidRevision = replacing(invalidRevision, contentSHA256: [UInt8](repeating: 0, count: 32))
        let invalidSnapshot = try PatchGenerationExistingFileSnapshot(revision: invalidRevision, data: existing)
        assertPlanningError(.existingFileSnapshotMismatch(destinationURL.path)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "append", old: "old\n", new: "new\n")],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: destinationURL,
                            disposition: .append(
                                expectedParent: parent,
                                expected: invalidSnapshot,
                                lineEnding: .lf
                            )
                        )
                    )
                )
            )
        }
    }

    func testCreateOverwriteDestinationAndEditorValidationAreFailClosed() throws {
        let directory = try makeTemporaryDirectory()
        let destinationURL = directory.appending(path: "output.patch")
        let parent = try canonicalIdentity(directory, kind: .directory)
        let createPlan = try PatchGenerationWorkflow.plan(
            request(
                sources: [makeSource(id: "create", old: "old\n", new: "new\n")],
                destination: .file(
                    PatchGenerationFileDestination(
                        url: destinationURL,
                        disposition: .createNew(parentIdentity: parent)
                    )
                ),
                presentation: PatchGenerationPresentationIntent(
                    externalEditor: .openFile(ruleIdentifier: "editor.rule")
                )
            )
        )
        guard case .file(let createDestination) = createPlan.destination,
            case .createNew(let createParent) = createDestination.operation
        else { return XCTFail("Expected create destination") }
        XCTAssertEqual(createParent, parent)
        XCTAssertEqual(createDestination.finalPermissions, 0o600)
        XCTAssertEqual(createDestination.payload, Data(createPlan.generatedPatch.utf8))
        XCTAssertEqual(createPlan.editor?.ruleIdentifier, "editor.rule")

        try Data("old destination".utf8).write(to: destinationURL)
        XCTAssertEqual(chmod(destinationURL.path, 0o644), 0)
        let revision = try fileRevision(destinationURL, metadataMaximum: 1 << 20)
        let overwritePlan = try PatchGenerationWorkflow.plan(
            request(
                sources: [makeSource(id: "overwrite", old: "old\n", new: "new\n")],
                destination: .file(
                    PatchGenerationFileDestination(
                        url: destinationURL,
                        disposition: .overwrite(expectedParent: parent, expected: revision)
                    )
                )
            )
        )
        guard case .file(let overwriteDestination) = overwritePlan.destination,
            case .overwrite(let overwriteParent, let overwriteRevision) = overwriteDestination.operation
        else { return XCTFail("Expected overwrite destination") }
        XCTAssertEqual(overwriteParent, parent)
        XCTAssertEqual(overwriteRevision, revision)
        XCTAssertEqual(overwriteDestination.finalPermissions, 0o644)

        assertPlanningError(.externalEditorRequiresFileDestination) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "clipboard", old: "old\n", new: "new\n")],
                    destination: clipboardDestination(clipboardIdentity()),
                    presentation: PatchGenerationPresentationIntent(
                        externalEditor: .openFile(ruleIdentifier: "editor.rule")
                    )
                )
            )
        }
        assertPlanningError(.invalidExternalEditorIntent) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "invalid-editor", old: "old\n", new: "new\n")],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: directory.appending(path: "other.patch"),
                            disposition: .createNew(parentIdentity: parent)
                        )
                    ),
                    presentation: PatchGenerationPresentationIntent(
                        externalEditor: .openFile(ruleIdentifier: "invalid rule")
                    )
                )
            )
        }
        assertPlanningError(.invalidExternalEditorIntent) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "empty-editor", old: "old\n", new: "new\n")],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: directory.appending(path: "empty-editor.patch"),
                            disposition: .createNew(parentIdentity: parent)
                        )
                    ),
                    presentation: PatchGenerationPresentationIntent(
                        externalEditor: .openFile(ruleIdentifier: "")
                    )
                )
            )
        }

        let exactRule = "rule-123"
        XCTAssertNoThrow(
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "editor-cap", old: "old\n", new: "new\n")],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: directory.appending(path: "exact-rule.patch"),
                            disposition: .createNew(parentIdentity: parent)
                        )
                    ),
                    presentation: PatchGenerationPresentationIntent(
                        externalEditor: .openFile(ruleIdentifier: exactRule)
                    ),
                    limits: limits(maximumExternalRuleIdentifierUTF8Bytes: exactRule.utf8.count)
                )
            )
        )
        assertPlanningError(.invalidExternalEditorIntent) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "editor-over", old: "old\n", new: "new\n")],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: directory.appending(path: "over-rule.patch"),
                            disposition: .createNew(parentIdentity: parent)
                        )
                    ),
                    presentation: PatchGenerationPresentationIntent(
                        externalEditor: .openFile(ruleIdentifier: exactRule + "4")
                    ),
                    limits: limits(maximumExternalRuleIdentifierUTF8Bytes: exactRule.utf8.count)
                )
            )
        }
    }

    func testStrictFileURLsAndCanonicalParentIdentityRejectConfusion() throws {
        let directory = try makeTemporaryDirectory()
        let parent = try canonicalIdentity(directory, kind: .directory)
        let source = makeSource(id: "source", old: "old\n", new: "new\n")
        let mismatchedURL = directory.appending(path: "nested/output.patch")
        assertPlanningError(.destinationIdentityMismatch(mismatchedURL.path)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [source],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: mismatchedURL,
                            disposition: .createNew(parentIdentity: parent)
                        )
                    )
                )
            )
        }

        let relative = URL(string: "file:relative.patch")!
        assertPlanningErrorMatching {
            guard case .invalidFileURL = $0 else { return false }
            return true
        } operation: {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [source],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: relative,
                            disposition: .createNew(parentIdentity: parent)
                        )
                    )
                )
            )
        }

        for confusedURL in [
            URL(string: "file://example.com/tmp/output.patch")!,
            URL(string: "file:///tmp/encoded%2Fleaf.patch")!
        ] {
            assertPlanningErrorMatching {
                guard case .invalidFileURL = $0 else { return false }
                return true
            } operation: {
                try PatchGenerationWorkflow.plan(
                    request(
                        sources: [source],
                        destination: .file(
                            PatchGenerationFileDestination(
                                url: confusedURL,
                                disposition: .createNew(parentIdentity: parent)
                            )
                        )
                    )
                )
            }
        }
    }

    func testPatchPathsAndFileURLsHonorExactDecodedCaps() throws {
        let destination = clipboardDestination(clipboardIdentity())
        for (name, invalidPath) in [
            ("nul", "invalid\0path"),
            ("lf", "invalid\npath"),
            ("cr", "invalid\rpath")
        ] {
            for invalidatesOldPath in [true, false] {
                assertPlanningError(.invalidPatchPath(invalidPath)) {
                    try PatchGenerationWorkflow.plan(
                        request(
                            sources: [
                                makeSource(
                                    id: "control-\(name)-\(invalidatesOldPath ? "old" : "new")",
                                    old: "old\n",
                                    new: "new\n",
                                    oldPath: invalidatesOldPath ? invalidPath : "old.txt",
                                    newPath: invalidatesOldPath ? "new.txt" : invalidPath
                                )
                            ],
                            destination: destination
                        )
                    )
                }
            }
        }
        let exactPathLimits = limits(
            maximumPathUTF8Bytes: 8,
            maximumTotalPathUTF8Bytes: 32
        )
        XCTAssertNoThrow(
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [
                        makeSource(
                            id: "exact",
                            old: "old\n",
                            new: "new\n",
                            oldPath: "12345678",
                            newPath: "abcdefgh"
                        )
                    ],
                    destination: destination,
                    limits: exactPathLimits
                )
            )
        )
        assertPlanningError(.pathTooLarge(maximumBytes: 8)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [
                        makeSource(
                            id: "over",
                            old: "old\n",
                            new: "new\n",
                            oldPath: "123456789",
                            newPath: "new.txt"
                        )
                    ],
                    destination: destination,
                    limits: exactPathLimits
                )
            )
        }
        assertPlanningError(.totalPathsTooLarge(maximumBytes: 15)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [
                        makeSource(
                            id: "total",
                            old: "old\n",
                            new: "new\n",
                            oldPath: "12345678",
                            newPath: "abcdefgh"
                        )
                    ],
                    destination: destination,
                    limits: limits(maximumPathUTF8Bytes: 8, maximumTotalPathUTF8Bytes: 15)
                )
            )
        }

        let directory = try makeTemporaryDirectory()
        let parent = try canonicalIdentity(directory, kind: .directory)
        let fileURL = directory.appending(path: "é.patch")
        let decodedByteCount = fileURL.path(percentEncoded: false).utf8.count
        let exactURLLimits = limits(
            maximumPathUTF8Bytes: decodedByteCount,
            maximumTotalPathUTF8Bytes: decodedByteCount * 3
        )
        XCTAssertNoThrow(
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "url-exact", old: "old\n", new: "new\n")],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: fileURL,
                            disposition: .createNew(parentIdentity: parent)
                        )
                    ),
                    limits: exactURLLimits
                )
            )
        )
        assertPlanningErrorMatching {
            guard case .invalidFileURL = $0 else { return false }
            return true
        } operation: {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "url-over", old: "old\n", new: "new\n")],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: fileURL,
                            disposition: .createNew(parentIdentity: parent)
                        )
                    ),
                    limits: limits(
                        maximumPathUTF8Bytes: decodedByteCount - 1,
                        maximumTotalPathUTF8Bytes: decodedByteCount * 3
                    )
                )
            )
        }

        let oversizedURL = URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 30))
        assertPlanningErrorMatching {
            guard case .invalidFileURL = $0 else { return false }
            return true
        } operation: {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "serialized-over", old: "old\n", new: "new\n")],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: oversizedURL,
                            disposition: .createNew(parentIdentity: parent)
                        )
                    ),
                    limits: limits(maximumPathUTF8Bytes: 16, maximumTotalPathUTF8Bytes: 64)
                )
            )
        }
    }

    func testNoncancelledPlanningRejectsEveryHardLimitOverflow() throws {
        let cases: [(limit: PatchGenerationPlanningLimit, limits: PatchGenerationPlanningLimits)] = [
            (
                .sources,
                limits(maximumSources: PatchGenerationPlanningLimits.hardMaximumSourceCount + 1)
            ),
            (
                .selectedSources,
                limits(
                    maximumSources: PatchGenerationPlanningLimits.hardMaximumSourceCount,
                    maximumSelectedSources: PatchGenerationPlanningLimits.hardMaximumSourceCount + 1
                )
            ),
            (
                .sourceIdentifierUTF8Bytes,
                limits(
                    maximumSourceIdentifierUTF8Bytes:
                        PatchGenerationPlanningLimits.hardMaximumSourceIdentifierUTF8Bytes + 1
                )
            ),
            (
                .pathUTF8Bytes,
                limits(
                    maximumPathUTF8Bytes: PatchGenerationPlanningLimits.hardMaximumPathUTF8Bytes + 1
                )
            ),
            (
                .totalPathUTF8Bytes,
                limits(
                    maximumTotalPathUTF8Bytes:
                        PatchGenerationPlanningLimits.hardMaximumTotalPathUTF8Bytes + 1
                )
            ),
            (
                .inputBytes,
                limits(maximumInputBytes: PatchGenerationPlanningLimits.hardMaximumInputBytes + 1)
            ),
            (
                .combinedInputBytes,
                limits(
                    maximumCombinedInputBytes:
                        PatchGenerationPlanningLimits.hardMaximumCombinedInputBytes + 1
                )
            ),
            (
                .existingFileBytes,
                limits(
                    maximumExistingFileBytes:
                        PatchGenerationPlanningLimits.hardMaximumExistingFileBytes + 1
                )
            ),
            (
                .existingFileMetadataBytes,
                limits(
                    maximumExistingFileMetadataBytes:
                        PatchGenerationPlanningLimits.hardMaximumExistingFileMetadataBytes + 1
                )
            ),
            (
                .patchBytes,
                limits(maximumPatchBytes: PatchGenerationPlanningLimits.hardMaximumPatchBytes + 1)
            ),
            (
                .destinationPayloadBytes,
                limits(
                    maximumDestinationPayloadBytes:
                        PatchGenerationPlanningLimits.hardMaximumDestinationPayloadBytes + 1
                )
            ),
            (
                .planOutputBytes,
                limits(
                    maximumPlanOutputBytes:
                        PatchGenerationPlanningLimits.hardMaximumPlanOutputBytes + 1
                )
            ),
            (
                .contextLines,
                limits(
                    maximumContextLines: PatchGenerationPlanningLimits.hardMaximumContextLines + 1
                )
            ),
            (
                .commandLineArguments,
                limits(
                    maximumCommandLineArgumentCount:
                        PatchGenerationPlanningLimits.hardMaximumCommandLineArgumentCount + 1
                )
            ),
            (
                .commandLineArgumentUTF8Bytes,
                limits(
                    maximumCommandLineArgumentUTF8Bytes:
                        PatchGenerationPlanningLimits.hardMaximumCommandLineArgumentUTF8Bytes + 1
                )
            ),
            (
                .totalCommandLineUTF8Bytes,
                limits(
                    maximumTotalCommandLineUTF8Bytes:
                        PatchGenerationPlanningLimits.hardMaximumTotalCommandLineUTF8Bytes + 1
                )
            ),
            (
                .externalRuleIdentifierUTF8Bytes,
                limits(
                    maximumExternalRuleIdentifierUTF8Bytes:
                        PatchGenerationPlanningLimits.hardMaximumExternalRuleIdentifierUTF8Bytes + 1
                )
            ),
            (
                .workUnits,
                limits(maximumWorkUnits: PatchGenerationPlanningLimits.hardMaximumWorkUnits + 1)
            )
        ]
        XCTAssertEqual(Set(cases.map(\.limit)), Set(PatchGenerationPlanningLimit.allCases))
        let source = makeSource(id: "hard-limits", old: "old\n", new: "new\n")
        let destination = clipboardDestination(clipboardIdentity())

        for testCase in cases {
            assertPlanningError(.invalidLimit(testCase.limit)) {
                try PatchGenerationWorkflow.plan(
                    request(
                        sources: [source],
                        destination: destination,
                        limits: testCase.limits
                    )
                )
            }
        }
    }

    func testAtomicGeneratorByteAndLinePairBoundsAndPreCancellation() async throws {
        let destination = clipboardDestination(clipboardIdentity())
        let byteOversized = makeSource(
            id: "bytes",
            old: String(repeating: "a", count: 512 * 1_024),
            new: String(repeating: "b", count: 512 * 1_024 + 1)
        )
        assertPlanningError(.combinedInputTooLarge(maximumBytes: 1 * 1_024 * 1_024)) {
            try PatchGenerationWorkflow.plan(request(sources: [byteOversized], destination: destination))
        }

        let lines = String(repeating: "x\n", count: 2_048)
        let linePairOversized = makeSource(id: "lines", old: lines, new: lines + "tail\n")
        assertPlanningError(.workLimitExceeded(maximumUnits: 4 * 1_024 * 1_024)) {
            try PatchGenerationWorkflow.plan(request(sources: [linePairOversized], destination: destination))
        }

        let exactBytes = makeSource(
            id: "exact-bytes",
            old: String(repeating: "a", count: 512 * 1_024),
            new: String(repeating: "b", count: 512 * 1_024)
        )
        XCTAssertNoThrow(
            try PatchGenerationWorkflow.plan(request(sources: [exactBytes], destination: destination))
        )
        let exactOldLines = String(repeating: "same\n", count: 2_047)
        let exactNewLines = "changed\n" + String(repeating: "same\n", count: 2_046)
        XCTAssertNoThrow(
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "exact-lines", old: exactOldLines, new: exactNewLines)],
                    destination: destination
                )
            )
        )

        let cancelledRequest = request(
            sources: [makeSource(id: "cancel", old: "old\n", new: "new\n")],
            destination: destination,
            limits: limits(maximumSources: 0)
        )
        let task = Task { @Sendable in
            withUnsafeCurrentTask { $0?.cancel() }
            return try PatchGenerationWorkflow.plan(cancelledRequest)
        }
        do {
            _ = try await task.value
            XCTFail("Pre-cancelled planning unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? PatchGenerationPlanningError, .cancelled)
        }
    }

    func testSourcePathIndexAndStableHeapHandle4096SourcesWithinBoundedWork() throws {
        let sourceCount = PatchGenerationPlanningLimits.hardMaximumSourceCount
        let sources = (0..<sourceCount).map { index in
            makeSource(
                id: "s\(index)",
                old: "old-\(index)\n",
                new: "new-\(index)\n",
                oldPath: "old/\(index).txt",
                newPath: "new/\(index).txt"
            )
        }
        // Fixed path/output reservations consume 70 MiB; remaining 4 MiB bounds indexing and heaps.
        let workCeiling: UInt64 = 74 * 1_024 * 1_024
        let bounded = limits(
            maximumSources: sourceCount,
            maximumSelectedSources: sourceCount,
            maximumPatchBytes: 2 * 1_024 * 1_024,
            maximumDestinationPayloadBytes: 64 * 1_024 * 1_024,
            maximumPlanOutputBytes: 72 * 1_024 * 1_024,
            maximumWorkUnits: workCeiling
        )
        let plan = try PatchGenerationWorkflow.plan(
            request(
                sources: sources,
                direction: .reverse,
                destination: clipboardDestination(clipboardIdentity()),
                limits: bounded
            )
        )

        XCTAssertEqual(plan.sources.count, sourceCount)
        XCTAssertEqual(plan.sources.first?.id.rawValue, "s0")
        XCTAssertEqual(plan.sources.last?.id.rawValue, "s4095")
        XCTAssertLessThanOrEqual(plan.estimatedWorkUnits, workCeiling)

        let exact = limits(
            maximumSources: sourceCount,
            maximumSelectedSources: sourceCount,
            maximumPatchBytes: 2 * 1_024 * 1_024,
            maximumDestinationPayloadBytes: 64 * 1_024 * 1_024,
            maximumPlanOutputBytes: 72 * 1_024 * 1_024,
            maximumWorkUnits: plan.estimatedWorkUnits
        )
        XCTAssertEqual(
            try PatchGenerationWorkflow.plan(
                request(
                    sources: sources,
                    direction: .reverse,
                    destination: clipboardDestination(clipboardIdentity()),
                    limits: exact
                )
            ).estimatedWorkUnits,
            plan.estimatedWorkUnits
        )
        let insufficient = limits(
            maximumSources: sourceCount,
            maximumSelectedSources: sourceCount,
            maximumPatchBytes: 2 * 1_024 * 1_024,
            maximumDestinationPayloadBytes: 64 * 1_024 * 1_024,
            maximumPlanOutputBytes: 72 * 1_024 * 1_024,
            maximumWorkUnits: plan.estimatedWorkUnits - 1
        )
        assertPlanningError(.workLimitExceeded(maximumUnits: plan.estimatedWorkUnits - 1)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: sources,
                    direction: .reverse,
                    destination: clipboardDestination(clipboardIdentity()),
                    limits: insufficient
                )
            )
        }
    }

    func test4096SourceRequestRejectsCancellationBeforePlanningStarts() async {
        let sourceCount = PatchGenerationPlanningLimits.hardMaximumSourceCount
        let sources = (0..<sourceCount).map { index in
            makeSource(
                id: "s\(index)",
                old: "old-\(index)\n",
                new: "new-\(index)\n",
                oldPath: "old/\(index).txt",
                newPath: "new/\(index).txt"
            )
        }
        let cancellationRequest = request(
            sources: sources,
            destination: clipboardDestination(clipboardIdentity()),
            limits: limits(
                maximumSources: sourceCount,
                maximumSelectedSources: sourceCount,
                maximumPatchBytes: 2 * 1_024 * 1_024,
                maximumDestinationPayloadBytes: 64 * 1_024 * 1_024,
                maximumPlanOutputBytes: 72 * 1_024 * 1_024,
                maximumWorkUnits: 74 * 1_024 * 1_024
            )
        )
        let planningStarted = expectation(description: "Planning reached cancellation gate")
        let gate = PlanningStartGate()
        let task = Task.detached { @Sendable in
            planningStarted.fulfill()
            await gate.enterAndWait()
            return try PatchGenerationWorkflow.plan(cancellationRequest)
        }
        await fulfillment(of: [planningStarted], timeout: 2)
        task.cancel()
        await gate.release()
        do {
            _ = try await task.value
            XCTFail("Cancelled 4096-source plan unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? PatchGenerationPlanningError, .cancelled)
        }
    }

    func testPlanDigestUsesFullFramingForMetadataAndExecutionFields() throws {
        let baseRevision = PatchGenerationClipboardRevision(
            brokerIdentifier: PatchGenerationClipboardBrokerIdentifier(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            ),
            epoch: PatchGenerationClipboardBrokerEpoch(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            ),
            value: 1
        )
        let sourceID = PatchGenerationSourceID(rawValue: "source")
        let baseSource = PatchGenerationSource(
            id: sourceID,
            oldSnapshot: PatchGenerationTextSnapshot(
                identity: .clipboard(contentID: "ab"),
                revision: 1,
                text: "old\n"
            ),
            newSnapshot: PatchGenerationTextSnapshot(
                identity: .clipboard(contentID: "c"),
                revision: 2,
                text: "new\n"
            ),
            oldPath: "old.txt",
            newPath: "new.txt"
        )
        let reframedSource = PatchGenerationSource(
            id: sourceID,
            oldSnapshot: PatchGenerationTextSnapshot(
                identity: .clipboard(contentID: "a"),
                revision: 1,
                text: "old\n"
            ),
            newSnapshot: PatchGenerationTextSnapshot(
                identity: .clipboard(contentID: "bc"),
                revision: 2,
                text: "new\n"
            ),
            oldPath: "old.txt",
            newPath: "new.txt"
        )
        let base = try planClipboard(
            source: baseSource,
            revision: baseRevision
        )
        let reframed = try planClipboard(
            source: reframedSource,
            revision: baseRevision
        )
        let differentEpoch = PatchGenerationClipboardRevision(
            brokerIdentifier: baseRevision.brokerIdentifier,
            epoch: PatchGenerationClipboardBrokerEpoch(rawValue: UUID()),
            value: baseRevision.value
        )
        let epochPlan = try planClipboard(
            source: baseSource,
            revision: differentEpoch
        )
        let contextPlan = try PatchGenerationWorkflow.plan(
            request(
                sources: [baseSource],
                contextLines: 1,
                destination: clipboardDestination(baseRevision)
            )
        )

        XCTAssertNotEqual(base.mutation.planSHA256, reframed.mutation.planSHA256)
        XCTAssertNotEqual(base.mutation.planSHA256, epochPlan.mutation.planSHA256)
        XCTAssertNotEqual(base.mutation.planSHA256, contextPlan.mutation.planSHA256)
        XCTAssertEqual(base.mutation.planSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(
            hex(base.mutation.planSHA256),
            "b5dbd30a3ce2d402d17d3c4ead9eec86fbe7a368cd21fe38c762690a613ac9ab"
        )
    }

    func testPlanDigestBindsFileRevisionContentAndMetadataDigestsIndependently() throws {
        let directory = try makeTemporaryDirectory()
        let destinationURL = directory.appending(path: "digest.patch")
        try Data("old destination".utf8).write(to: destinationURL)
        let parent = try canonicalIdentity(directory, kind: .directory)
        let revision = try fileRevision(destinationURL, metadataMaximum: 1 << 20)
        var changedContentSHA256 = revision.contentSHA256
        changedContentSHA256[0] ^= 0xFF
        var changedMetadataSHA256 = revision.metadataSHA256
        changedMetadataSHA256[0] ^= 0xFF
        let contentChanged = replacing(revision, contentSHA256: changedContentSHA256)
        let metadataChanged = replacing(revision, metadataSHA256: changedMetadataSHA256)

        func plannedDigest(_ expected: PatchGenerationFileRevision) throws -> [UInt8] {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "digest", old: "old\n", new: "new\n")],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: destinationURL,
                            disposition: .overwrite(expectedParent: parent, expected: expected)
                        )
                    )
                )
            ).mutation.planSHA256
        }

        let baseDigest = try plannedDigest(revision)
        XCTAssertNotEqual(baseDigest, try plannedDigest(contentChanged))
        XCTAssertNotEqual(baseDigest, try plannedDigest(metadataChanged))
        XCTAssertNotEqual(try plannedDigest(contentChanged), try plannedDigest(metadataChanged))

        for invalid in [
            replacing(revision, contentSHA256: Array(revision.contentSHA256.dropLast())),
            replacing(revision, metadataSHA256: Array(revision.metadataSHA256.dropLast()))
        ] {
            assertPlanningError(.invalidFileRevision(destinationURL.path)) {
                try plannedDigest(invalid)
            }
        }
    }

    func testPlanDigestBindsExternalEditorRuleVariants() throws {
        let directory = try makeTemporaryDirectory()
        let destinationURL = directory.appending(path: "editor-digest.patch")
        let parent = try canonicalIdentity(directory, kind: .directory)
        let source = makeSource(id: "editor-digest", old: "old\n", new: "new\n")

        func plannedDigest(_ editor: PatchGenerationExternalEditorIntent) throws -> [UInt8] {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [source],
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: destinationURL,
                            disposition: .createNew(parentIdentity: parent)
                        )
                    ),
                    presentation: PatchGenerationPresentationIntent(externalEditor: editor)
                )
            ).mutation.planSHA256
        }

        let noEditor = try plannedDigest(.none)
        let firstRule = try plannedDigest(.openFile(ruleIdentifier: "editor.rule-a"))
        let secondRule = try plannedDigest(.openFile(ruleIdentifier: "editor.rule-b"))
        XCTAssertNotEqual(noEditor, firstRule)
        XCTAssertNotEqual(noEditor, secondRule)
        XCTAssertNotEqual(firstRule, secondRule)
    }

    func testStructuralArgvPreservesElementBoundariesRejectsNULAndHonorsFramingCaps() throws {
        let arguments = ["tool", "one two", "$(touch /tmp/never)", "quote'\""]
        let plan = try PatchGenerationWorkflow.plan(
            request(
                sources: [makeSource(id: "argv", old: "old\n", new: "new\n")],
                destination: clipboardDestination(clipboardIdentity()),
                presentation: PatchGenerationPresentationIntent(
                    commandLine: .record(arguments: arguments)
                )
            )
        )
        XCTAssertEqual(plan.displayMetadata.commandLine, .record(arguments: arguments))

        assertPlanningError(.invalidCommandLineIntent) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "nul", old: "old\n", new: "new\n")],
                    destination: clipboardDestination(clipboardIdentity()),
                    presentation: PatchGenerationPresentationIntent(
                        commandLine: .record(arguments: ["valid", "bad\0value"])
                    )
                )
            )
        }
        let capped = limits(
            maximumCommandLineArgumentCount: 2,
            maximumCommandLineArgumentUTF8Bytes: 8,
            maximumTotalCommandLineUTF8Bytes: 18
        )
        assertPlanningError(.commandLineIntentTooLarge(maximumBytes: 18)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "cap", old: "old\n", new: "new\n")],
                    destination: clipboardDestination(clipboardIdentity()),
                    presentation: PatchGenerationPresentationIntent(
                        commandLine: .record(arguments: ["a", "b"])
                    ),
                    limits: capped
                )
            )
        }
        let countLimits = limits(
            maximumCommandLineArgumentCount: 1,
            maximumCommandLineArgumentUTF8Bytes: 8,
            maximumTotalCommandLineUTF8Bytes: 1_024
        )
        assertPlanningError(.invalidCommandLineIntent) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "count", old: "old\n", new: "new\n")],
                    destination: clipboardDestination(clipboardIdentity()),
                    presentation: PatchGenerationPresentationIntent(
                        commandLine: .record(arguments: ["a", "b"])
                    ),
                    limits: countLimits
                )
            )
        }
        XCTAssertNoThrow(
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "arg-exact", old: "old\n", new: "new\n")],
                    destination: clipboardDestination(clipboardIdentity()),
                    presentation: PatchGenerationPresentationIntent(
                        commandLine: .record(arguments: ["12345678"])
                    ),
                    limits: countLimits
                )
            )
        )
        assertPlanningError(.invalidCommandLineIntent) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "arg-over", old: "old\n", new: "new\n")],
                    destination: clipboardDestination(clipboardIdentity()),
                    presentation: PatchGenerationPresentationIntent(
                        commandLine: .record(arguments: ["123456789"])
                    ),
                    limits: countLimits
                )
            )
        }
        let pointerBytes = MemoryLayout<UnsafePointer<CChar>?>.size
        let exactTotal = (2 + 1) * pointerBytes + (1 + 1) + (2 + 1)
        let exactTotalLimits = limits(
            maximumCommandLineArgumentCount: 2,
            maximumCommandLineArgumentUTF8Bytes: 2,
            maximumTotalCommandLineUTF8Bytes: exactTotal
        )
        XCTAssertNoThrow(
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "total-exact", old: "old\n", new: "new\n")],
                    destination: clipboardDestination(clipboardIdentity()),
                    presentation: PatchGenerationPresentationIntent(
                        commandLine: .record(arguments: ["a", "bc"])
                    ),
                    limits: exactTotalLimits
                )
            )
        )
        assertPlanningError(.commandLineIntentTooLarge(maximumBytes: exactTotal - 1)) {
            try PatchGenerationWorkflow.plan(
                request(
                    sources: [makeSource(id: "total-over", old: "old\n", new: "new\n")],
                    destination: clipboardDestination(clipboardIdentity()),
                    presentation: PatchGenerationPresentationIntent(
                        commandLine: .record(arguments: ["a", "bc"])
                    ),
                    limits: limits(
                        maximumCommandLineArgumentCount: 2,
                        maximumCommandLineArgumentUTF8Bytes: 2,
                        maximumTotalCommandLineUTF8Bytes: exactTotal - 1
                    )
                )
            )
        }
    }

    func testExecutorContractRequiresPrivateStagingMetadataCleanupAndAtomicMutation() {
        let contract = PatchGenerationExecutorContract.required
        XCTAssertEqual(PatchGenerationExecutorContract.stagingDirectoryPermissions, 0o700)
        XCTAssertEqual(PatchGenerationExecutorContract.stagingFilePermissions, 0o600)
        XCTAssertEqual(contract.sourceRevalidation, .immutablePinOrRevisionLeaseHeldThroughCommit)
        XCTAssertEqual(contract.pathResolution, .descriptorRelativeNoFollowFromPinnedCanonicalParent)
        XCTAssertEqual(contract.filePublication, .privateStageSyncThenLeaseOrFullRevisionCASPublishAndSyncParent)
        XCTAssertEqual(contract.fileType, .regularFileOnlyAndNonBlockingDescriptorAccess)
        XCTAssertEqual(contract.metadata, .preserveAndVerifyModeOwnerGroupFlagsACLsAndExtendedAttributes)
        XCTAssertEqual(contract.existingDestination, .exactIdentityRevisionAndDigestHeldThroughPublication)
        XCTAssertEqual(contract.newDestination, .exactParentIdentityAndExclusiveCreate)
        XCTAssertEqual(contract.clipboardPublication, .exclusiveBrokerEpochRevisionCompareAndReplaceAtomically)
        XCTAssertEqual(contract.cancellation, .noMutationBeforePublicationAndCommittedSealedCompareMissOrUncertainAfterPublicationStarts)
        XCTAssertEqual(contract.intentExecution, .displayArgvNeverExecutedAndEditorUsesDescriptorReceiptAfterCommit)
        XCTAssertEqual(contract.stagingProtection, .privateDirectory0700AndLeaf0600WithoutBroadInheritedACL)
        XCTAssertEqual(contract.stagingCleanup, .descriptorAndStableIdentityBoundBeforePublicationOnly)
        XCTAssertEqual(contract.destinationMutation, .continuousRevisionLeaseOrAtomicDescriptorRelativeFullRevisionCAS)
    }

    func testFileEvidencePermitCannotRestartCASAfterCancellationOrFailureOutcome() async throws {
        let fixture = try makeFileReceiptFixture(editor: false)
        defer { fixture.close() }
        for mode in [FileEvidenceHarness.Mode.cancelAfterCASStart, .failureAfterCASStart] {
            let probe = FileEvidenceProbe()
            let task = Task { @Sendable in
                await PatchGenerationWorkflow.execute(
                    fixture.plan,
                    with: FileEvidenceHarness(
                        fixture: fixture,
                        mode: mode,
                        probe: probe
                    )
                )
            }
            let outcome = await task.value
            guard case .commitUncertain(let uncertainty) = outcome.state else {
                XCTFail("Expected uncertainty")
                continue
            }
            XCTAssertEqual(uncertainty.destinationURL, fixture.url)
            let state = await probe.snapshot()
            XCTAssertTrue(state.secondPermitRejected)
            XCTAssertTrue(state.firstCASStarted)
            XCTAssertTrue(state.originalPermitRejectedAfterOutcome)
            switch mode {
            case .cancelAfterCASStart:
                XCTAssertTrue(task.isCancelled)
                XCTAssertTrue(state.cancellationObserved)
                XCTAssertEqual(uncertainty.reason, "Cancelled after file CAS started.")
            case .failureAfterCASStart:
                XCTAssertTrue(state.failureObserved)
                XCTAssertEqual(uncertainty.reason, "File CAS failed after start.")
            default:
                XCTFail("Unexpected mode")
            }
        }
    }

    func testFilePublicationTokenPermitAndTerminalEvidenceAreAtomicUnderContention() async throws {
        let fixture = try makeFileReceiptFixture(editor: false)
        defer { fixture.close() }
        let probe = FileRaceProbe()

        let outcome = await PatchGenerationWorkflow.execute(
            fixture.plan,
            with: RacingFileEvidenceHarness(destinationURL: fixture.url, probe: probe)
        )

        guard case .notCommitted(let reason) = outcome.state else {
            return XCTFail("Expected one sealed file compare miss")
        }
        XCTAssertEqual(reason, .destinationChanged)
        let state = await probe.snapshot()
        XCTAssertEqual(state.tokenCount, 1)
        XCTAssertEqual(state.permitCount, 1)
        XCTAssertEqual(state.compareAndSwapStartCount, 1)
        XCTAssertEqual(state.terminalEvidenceCount, 1)
    }

    func testFileReceiptFactoryMetadataDigestUsesFullFramingAndExactCap() async throws {
        let first = try makeFileReceiptFixture(
            editor: false,
            extendedAttributes: ["user.macmerge.a": Data([0x62, 0x63])]
        )
        let second = try makeFileReceiptFixture(
            editor: false,
            extendedAttributes: ["user.macmerge.ab": Data([0x63])]
        )
        defer {
            first.close()
            second.close()
        }

        XCTAssertNotEqual(first.revision.metadataSHA256, second.revision.metadataSHA256)
        for fixture in [first, second] {
            let exactPlan = try makeCreatePlan(
                directory: fixture.url.deletingLastPathComponent(),
                destinationURL: fixture.url,
                editor: false,
                maximumMetadataBytes: Int(fixture.revision.metadataByteCount),
                source: fixture.source
            )
            XCTAssertEqual(exactPlan.mutation.planSHA256, fixture.plan.mutation.planSHA256)
            let probe = FileEvidenceProbe()
            let outcome = await PatchGenerationWorkflow.execute(
                exactPlan,
                with: FileEvidenceHarness(
                    fixture: fixture,
                    mode: .sealValid,
                    probe: probe
                )
            )
            guard case .committed = outcome.state else {
                return XCTFail("Receipt factory rejected metadata at exact configured cap")
            }
            let state = await probe.snapshot()
            XCTAssertTrue(state.receiptSealed)
        }

        let cappedPlan = try makeCreatePlan(
            directory: first.url.deletingLastPathComponent(),
            destinationURL: first.url,
            editor: false,
            maximumMetadataBytes: Int(first.revision.metadataByteCount) - 1,
            source: first.source
        )
        XCTAssertEqual(cappedPlan.mutation.planSHA256, first.plan.mutation.planSHA256)
        let capProbe = FileEvidenceProbe()
        let capped = await PatchGenerationWorkflow.execute(
            cappedPlan,
            with: FileEvidenceHarness(fixture: first, mode: .sealValid, probe: capProbe)
        )
        guard case .commitUncertain = capped.state else {
            return XCTFail("Receipt factory must reject metadata above configured cap")
        }
        let cappedState = await capProbe.snapshot()
        XCTAssertFalse(cappedState.receiptSealed)

        let oversizedXattr = try makeFileReceiptFixture(
            editor: false,
            extendedAttributes: ["user.macmerge.large": Data(repeating: 0x41, count: 1_024)]
        )
        defer { oversizedXattr.close() }
        XCTAssertGreaterThan(oversizedXattr.revision.metadataByteCount, 128)
        let underreportedRevision = replacing(
            oversizedXattr.revision,
            metadataByteCount: 128
        )
        let underreportedPlan = try makeCreatePlan(
            directory: oversizedXattr.url.deletingLastPathComponent(),
            destinationURL: oversizedXattr.url,
            editor: false,
            maximumMetadataBytes: 128,
            source: oversizedXattr.source
        )
        let underreportedProbe = FileEvidenceProbe()
        let underreported = await PatchGenerationWorkflow.execute(
            underreportedPlan,
            with: FileEvidenceHarness(
                fixture: oversizedXattr,
                mode: .sealValid,
                probe: underreportedProbe,
                evidenceRevision: underreportedRevision
            )
        )
        guard case .commitUncertain = underreported.state else {
            return XCTFail("Underreported oversized xattr must fail closed")
        }
        let underreportedState = await underreportedProbe.snapshot()
        XCTAssertEqual(underreportedState.sealErrorCode, Int(EFBIG))

        let changedMetadata = try makeFileReceiptFixture(
            editor: false,
            extendedAttributes: ["user.macmerge.changed": Data([0x61, 0x61])]
        )
        defer { changedMetadata.close() }
        try setExtendedAttribute(
            name: "user.macmerge.changed",
            value: Data([0x62, 0x62]),
            at: changedMetadata.url
        )
        let currentRevision = try fileRevision(changedMetadata.url, metadataMaximum: 1 << 20)
        XCTAssertEqual(currentRevision.metadataByteCount, changedMetadata.revision.metadataByteCount)
        XCTAssertEqual(currentRevision.contentSHA256, changedMetadata.revision.contentSHA256)
        XCTAssertNotEqual(currentRevision.metadataSHA256, changedMetadata.revision.metadataSHA256)
        let currentStatWithPriorMetadataDigest = replacing(
            currentRevision,
            metadataSHA256: changedMetadata.revision.metadataSHA256
        )
        let changedProbe = FileEvidenceProbe()
        let changedOutcome = await PatchGenerationWorkflow.execute(
            changedMetadata.plan,
            with: FileEvidenceHarness(
                fixture: changedMetadata,
                mode: .sealValid,
                probe: changedProbe,
                evidenceRevision: currentStatWithPriorMetadataDigest
            )
        )
        guard case .commitUncertain = changedOutcome.state else {
            return XCTFail("Same-length metadata replacement must invalidate captured evidence")
        }
        let changedState = await changedProbe.snapshot()
        XCTAssertFalse(changedState.receiptSealed)
    }

    func testFileReceiptFactoryAuthenticatesNonemptyACLMetadata() async throws {
        let withoutACL = try makeFileReceiptFixture(editor: false)
        let withACL = try makeFileReceiptFixture(editor: false, includeNonemptyACL: true)
        defer {
            withoutACL.close()
            withACL.close()
        }

        XCTAssertTrue(try hasNonemptyACL(at: withACL.url))
        XCTAssertGreaterThan(withACL.revision.metadataByteCount, withoutACL.revision.metadataByteCount)
        XCTAssertNotEqual(withACL.revision.metadataSHA256, withoutACL.revision.metadataSHA256)
        let probe = FileEvidenceProbe()
        let outcome = await PatchGenerationWorkflow.execute(
            withACL.plan,
            with: FileEvidenceHarness(fixture: withACL, mode: .sealValid, probe: probe)
        )
        guard case .committed = outcome.state else {
            return XCTFail("Valid nonempty ACL metadata must authenticate")
        }
        let state = await probe.snapshot()
        XCTAssertTrue(state.receiptSealed)
    }

    func testFileReceiptFactoryUsesSessionMetadataCeilingNotSubstitutedEvidencePlan() async throws {
        let fixture = try makeFileReceiptFixture(editor: false, maximumMetadataBytes: 1 << 20)
        defer { fixture.close() }
        let lowLimitPlan = try makeCreatePlan(
            directory: fixture.url.deletingLastPathComponent(),
            destinationURL: fixture.url,
            editor: false,
            maximumMetadataBytes: 32,
            source: fixture.source
        )
        XCTAssertEqual(lowLimitPlan.mutation.planSHA256, fixture.plan.mutation.planSHA256)
        let probe = FileEvidenceProbe()
        let outcome = await PatchGenerationWorkflow.execute(
            lowLimitPlan,
            with: FileEvidenceHarness(
                fixture: fixture,
                mode: .sealValid,
                probe: probe,
                evidencePlan: fixture.plan.mutation
            )
        )
        guard case .commitUncertain = outcome.state else {
            return XCTFail("Configured metadata ceiling must fail closed")
        }
        let state = await probe.snapshot()
        XCTAssertFalse(state.receiptSealed)
    }

    func testFileReceiptIsOneShotAndOpenFileFailsClosedWithDarwinENOTSUP() async throws {
        let fixture = try makeFileReceiptFixture(editor: true)
        defer { fixture.close() }
        let probe = FileEvidenceProbe()
        let receiptStore = FileReceiptStore()
        let outcome = await PatchGenerationWorkflow.execute(
            fixture.plan,
            with: FileEvidenceHarness(
                fixture: fixture,
                mode: .sealValid,
                probe: probe,
                receiptStore: receiptStore
            )
        )
        guard case .committed(let commit) = outcome.state else {
            return XCTFail("Expected committed file")
        }
        XCTAssertEqual(commit.destination, PatchGenerationCommittedDestination.file(fixture.revision))
        XCTAssertEqual(commit.committedByteCount, fixture.payload.count)
        XCTAssertEqual(commit.generatedPatchSHA256, fixture.plan.mutation.generatedPatchSHA256)
        XCTAssertEqual(commit.planSHA256, fixture.plan.mutation.planSHA256)
        // Core's Darwin immutable-snapshot path throws ENOTSUP, so .openFile authorization is absent.
        XCTAssertNil(
            commit.fileAuthorization,
            "Darwin immutable snapshot creation is documented fail-closed with ENOTSUP; no functional .openFile backend is claimed"
        )
        XCTAssertNil(PatchGenerationExecutionOutcomeFactory.editorDispatch(plan: fixture.plan.mutation, receipt: commit))
        let state = await probe.snapshot()
        XCTAssertTrue(state.receiptSealed)
        guard let consumedReceipt = await receiptStore.receipt() else {
            return XCTFail("Expected stored consumed receipt")
        }
        XCTAssertEqual(consumedReceipt.revision, fixture.revision)
        XCTAssertEqual(consumedReceipt.planSHA256, fixture.plan.mutation.planSHA256)
        XCTAssertEqual(consumedReceipt.payloadSHA256, fixture.revision.contentSHA256)
        XCTAssertEqual(consumedReceipt.guarantee, .atomicDescriptorRelativeFullRevisionCompareAndSwap)
        let replay = await PatchGenerationWorkflow.execute(
            fixture.plan,
            with: ReplayedFileReceiptExecutor(receipt: consumedReceipt)
        )
        guard case .commitUncertain(let uncertainty) = replay.state else {
            return XCTFail("Consumed receipt must fail in fresh execution")
        }
        XCTAssertEqual(uncertainty.reason, "File publication receipt was already consumed.")
    }

    func testUnconsumedFileReceiptRejectsForeignSession() async throws {
        let fixture = try makeFileReceiptFixture(editor: false)
        defer { fixture.close() }
        let store = FileReceiptStore()
        let producer = await PatchGenerationWorkflow.execute(
            fixture.plan,
            with: FileEvidenceHarness(
                fixture: fixture,
                mode: .storeSealedReceiptWithoutCommit,
                probe: FileEvidenceProbe(),
                receiptStore: store
            )
        )
        guard case .commitUncertain = producer.state,
            let receipt = await store.receipt()
        else { return XCTFail("Expected unconsumed sealed receipt") }

        let replay = await PatchGenerationWorkflow.execute(
            fixture.plan,
            with: ReplayedFileReceiptExecutor(receipt: receipt)
        )
        guard case .commitUncertain(let uncertainty) = replay.state else {
            return XCTFail("Foreign-session file receipt must fail closed")
        }
        XCTAssertEqual(uncertainty.reason, "File commit evidence does not match plan.")
    }

    func testFileReceiptFactoryRejectsWritableDescriptorAndSelfConsistentWrongLeafAndPayload() async throws {
        for mode in [FileEvidenceHarness.Mode.sealWritable, .sealWrongLeaf] {
            let fixture = try makeFileReceiptFixture(editor: false)
            defer { fixture.close() }
            if case .sealWrongLeaf = mode {
                XCTAssertEqual(fixture.decoyRevision.contentSHA256, digest(fixture.payload))
                XCTAssertEqual(fixture.decoyRevision.identity.canonicalURL, fixture.decoyURL)
            }
            let probe = FileEvidenceProbe()
            let outcome = await PatchGenerationWorkflow.execute(
                fixture.plan,
                with: FileEvidenceHarness(fixture: fixture, mode: mode, probe: probe)
            )
            guard case .commitUncertain = outcome.state else {
                XCTFail("Invalid descriptor evidence must be uncertain")
                continue
            }
            let state = await probe.snapshot()
            XCTAssertFalse(state.receiptSealed)
        }

        let wrongPayloadFixture = try makeFileReceiptFixture(editor: false)
        defer { wrongPayloadFixture.close() }
        var wrongPayload = wrongPayloadFixture.payload
        wrongPayload[wrongPayload.startIndex] ^= 0xFF
        try wrongPayload.write(to: wrongPayloadFixture.url)
        let wrongPayloadRevision = try fileRevision(
            wrongPayloadFixture.url,
            metadataMaximum: 1 << 20
        )
        XCTAssertEqual(wrongPayloadRevision.contentSHA256, digest(wrongPayload))
        XCTAssertNotEqual(wrongPayloadRevision.contentSHA256, digest(wrongPayloadFixture.payload))
        let wrongPayloadProbe = FileEvidenceProbe()
        let wrongPayloadOutcome = await PatchGenerationWorkflow.execute(
            wrongPayloadFixture.plan,
            with: FileEvidenceHarness(
                fixture: wrongPayloadFixture,
                mode: .sealWrongPayload,
                probe: wrongPayloadProbe,
                evidenceRevision: wrongPayloadRevision
            )
        )
        guard case .commitUncertain = wrongPayloadOutcome.state else {
            return XCTFail("Self-consistent wrong payload evidence must be uncertain")
        }
        let wrongPayloadState = await wrongPayloadProbe.snapshot()
        XCTAssertFalse(wrongPayloadState.receiptSealed)
    }

    func testFileReceiptFactoryRejectsForeignParentAndMissingCloseOnExecEvidence() async throws {
        for mode in [FileEvidenceHarness.Mode.sealForeignParent, .sealWithoutCloseOnExec] {
            let fixture = try makeFileReceiptFixture(editor: false)
            defer { fixture.close() }
            let probe = FileEvidenceProbe()
            let outcome = await PatchGenerationWorkflow.execute(
                fixture.plan,
                with: FileEvidenceHarness(fixture: fixture, mode: mode, probe: probe)
            )
            guard case .commitUncertain = outcome.state else {
                XCTFail("Foreign descriptor evidence must be uncertain")
                continue
            }
            let state = await probe.snapshot()
            XCTAssertFalse(state.receiptSealed)
            switch mode {
            case .sealForeignParent:
                XCTAssertEqual(state.submittedParentDescriptorMatchesExpected, false)
            case .sealWithoutCloseOnExec:
                XCTAssertEqual(state.submittedFileDescriptorCloseOnExec, false)
            default:
                XCTFail("Unexpected evidence mode")
            }
        }
    }

    func testFileReceiptFactoryAcceptsEvidenceBoundToCreateOverwriteAndAppendOperations() async throws {
        for operation in FileReceiptFixtureOperation.allCases {
            let fixture = try makeFileReceiptFixture(editor: false, operation: operation)
            defer { fixture.close() }
            let probe = FileEvidenceProbe()
            let outcome = await PatchGenerationWorkflow.execute(
                fixture.plan,
                with: FileEvidenceHarness(fixture: fixture, mode: .sealValid, probe: probe)
            )
            guard case .committed(let receipt) = outcome.state else {
                XCTFail("Receipt factory rejected \(operation) evidence")
                continue
            }
            XCTAssertEqual(receipt.destination, .file(fixture.revision))
            XCTAssertEqual(receipt.committedByteCount, fixture.payload.count)
            XCTAssertEqual(receipt.generatedPatchSHA256, fixture.plan.mutation.generatedPatchSHA256)
            XCTAssertEqual(receipt.planSHA256, fixture.plan.mutation.planSHA256)
            let state = await probe.snapshot()
            XCTAssertTrue(state.receiptSealed)

            guard case .file(let destination) = fixture.plan.destination else {
                return XCTFail("Expected file destination")
            }
            switch (operation, destination.operation) {
            case (.createNew, .createNew), (.overwrite, .overwrite), (.append, .append):
                break
            default:
                XCTFail("Planned operation did not match \(operation)")
            }
        }
    }

    func testFileReceiptFactoryRejectsOperationPlanSubstitution() async throws {
        let fixture = try makeFileReceiptFixture(editor: false)
        defer { fixture.close() }
        let overwritePlan = try PatchGenerationWorkflow.plan(
            request(
                sources: [fixture.source],
                contextLines: 0,
                destination: .file(
                    PatchGenerationFileDestination(
                        url: fixture.url,
                        disposition: .overwrite(
                            expectedParent: fixture.parent,
                            expected: fixture.revision
                        )
                    )
                )
            )
        )
        guard case .file(let createDestination) = fixture.plan.destination,
            case .file(let overwriteDestination) = overwritePlan.destination
        else { return XCTFail("Expected file plans") }
        XCTAssertEqual(createDestination.payload, overwriteDestination.payload)
        XCTAssertEqual(createDestination.finalPermissions, overwriteDestination.finalPermissions)
        XCTAssertNotEqual(fixture.plan.mutation.planSHA256, overwritePlan.mutation.planSHA256)

        let probe = FileEvidenceProbe()
        let outcome = await PatchGenerationWorkflow.execute(
            fixture.plan,
            with: FileEvidenceHarness(
                fixture: fixture,
                mode: .sealValid,
                probe: probe,
                evidencePlan: overwritePlan.mutation
            )
        )
        guard case .commitUncertain = outcome.state else {
            return XCTFail("Permit must reject substituted file operation plan")
        }
        let state = await probe.snapshot()
        XCTAssertFalse(state.receiptSealed)
    }

    func testFileCompareMissReceiptRejectsForeignSessionAndSubstitutedPlanReplay() async throws {
        let fixture = try makeFileReceiptFixture(editor: false)
        defer { fixture.close() }
        let store = FileNonPublicationReceiptStore()
        let producer = await PatchGenerationWorkflow.execute(
            fixture.plan,
            with: FileCompareMissExecutor(receiptStore: store)
        )
        guard case .notCommitted(.destinationChanged) = producer.state,
            let receipt = await store.receipt()
        else { return XCTFail("Expected sealed file compare-miss receipt") }
        XCTAssertEqual(receipt.planSHA256, fixture.plan.mutation.planSHA256)

        let foreignSession = await PatchGenerationWorkflow.execute(
            fixture.plan,
            with: ReplayedFileNonPublicationReceiptExecutor(receipt: receipt)
        )
        guard case .commitUncertain(let foreignUncertainty) = foreignSession.state else {
            return XCTFail("Foreign-session file compare-miss receipt must be uncertain")
        }
        XCTAssertEqual(foreignUncertainty.reason, "File non-commit evidence does not match plan.")

        let substitutedPlan = try makeCreatePlan(
            directory: fixture.url.deletingLastPathComponent(),
            destinationURL: fixture.url,
            editor: true,
            source: fixture.source
        )
        XCTAssertNotEqual(fixture.plan.mutation.planSHA256, substitutedPlan.mutation.planSHA256)
        let substituted = await PatchGenerationWorkflow.execute(
            fixture.plan,
            with: FileCompareMissExecutor(
                outcomePlan: substitutedPlan.mutation
            )
        )
        guard case .commitUncertain(let substitutedUncertainty) = substituted.state else {
            return XCTFail("Substituted-plan file compare-miss receipt must be uncertain")
        }
        XCTAssertEqual(
            substitutedUncertainty.reason,
            "File non-commit evidence does not match plan."
        )
    }

    func testExclusiveClipboardBrokerReceiptContractCommitsOnceAndVerifiesReceipt() async throws {
        // Callback models platform CAS result; no concrete pasteboard backend is claimed here.
        let calls = ClipboardCallLog()
        let broker = PatchGenerationWorkflow.makeExclusiveClipboardBroker(initialRevision: 3) { expected, text in
            await calls.record(expected: expected, text: text)
            return .replaced(revision: expected.value + 1)
        }
        let expected = await broker.currentRevision
        let plan = try planClipboard(
            source: makeSource(id: "clipboard", old: "old\n", new: "new\n"),
            revision: expected
        )
        let outcome = await PatchGenerationWorkflow.execute(
            plan,
            with: ClipboardPublishingExecutor(broker: broker)
        )
        guard case .committed(let commit) = outcome.state else {
            return XCTFail("Expected committed clipboard")
        }
        let callState = await calls.snapshot()
        let currentRevision = await broker.currentRevision
        XCTAssertEqual(callState.count, 1)
        XCTAssertEqual(callState.lastExpected, expected)
        XCTAssertEqual(callState.lastText, plan.generatedPatch)
        XCTAssertEqual(currentRevision.value, expected.value + 1)
        XCTAssertEqual(commit.destination, PatchGenerationCommittedDestination.clipboard(revision: currentRevision))
        XCTAssertEqual(commit.committedByteCount, plan.generatedPatchUTF8ByteCount)
        XCTAssertEqual(commit.generatedPatchSHA256, plan.mutation.generatedPatchSHA256)
        XCTAssertEqual(commit.planSHA256, plan.mutation.planSHA256)
        XCTAssertNil(commit.fileAuthorization)

        let retry = await PatchGenerationWorkflow.execute(
            plan,
            with: ClipboardPublishingExecutor(broker: broker)
        )
        guard case .commitUncertain = retry.state else {
            return XCTFail("Stale clipboard plan must not publish")
        }
        let retryCallState = await calls.snapshot()
        XCTAssertEqual(retryCallState.count, 1)
    }

    func testClipboardBrokerRejectsForeignBrokerAndEpochAndPoisonsOnRevisionRegressionABA() async throws {
        let calls = ClipboardCallLog()
        let broker = PatchGenerationWorkflow.makeExclusiveClipboardBroker(initialRevision: 8) { expected, text in
            await calls.record(expected: expected, text: text)
            return .notReplaced(observedRevision: expected.value - 1)
        }
        let expected = await broker.currentRevision
        let foreign = PatchGenerationClipboardRevision(
            brokerIdentifier: expected.brokerIdentifier,
            epoch: PatchGenerationClipboardBrokerEpoch(rawValue: UUID()),
            value: expected.value
        )
        let foreignPlan = try planClipboard(
            source: makeSource(id: "foreign", old: "old\n", new: "new\n"),
            revision: foreign
        )
        let foreignOutcome = await PatchGenerationWorkflow.execute(
            foreignPlan,
            with: ClipboardPublishingExecutor(broker: broker)
        )
        guard case .commitUncertain = foreignOutcome.state else {
            return XCTFail("Foreign epoch must fail closed")
        }
        let foreignCallState = await calls.snapshot()
        XCTAssertEqual(foreignCallState.count, 0)

        let foreignBroker = PatchGenerationClipboardRevision(
            brokerIdentifier: PatchGenerationClipboardBrokerIdentifier(rawValue: UUID()),
            epoch: expected.epoch,
            value: expected.value
        )
        let foreignBrokerPlan = try planClipboard(
            source: makeSource(id: "foreign-broker", old: "old\n", new: "new\n"),
            revision: foreignBroker
        )
        let foreignBrokerOutcome = await PatchGenerationWorkflow.execute(
            foreignBrokerPlan,
            with: ClipboardPublishingExecutor(broker: broker)
        )
        guard case .commitUncertain = foreignBrokerOutcome.state else {
            return XCTFail("Foreign broker under same epoch must fail closed")
        }
        let foreignBrokerCallState = await calls.snapshot()
        XCTAssertEqual(foreignBrokerCallState.count, 0)

        let plan = try planClipboard(
            source: makeSource(id: "aba", old: "old\n", new: "new\n"),
            revision: expected
        )
        let outcome = await PatchGenerationWorkflow.execute(
            plan,
            with: ClipboardPublishingExecutor(broker: broker)
        )
        guard case .commitUncertain(let uncertainty) = outcome.state else {
            return XCTFail("Revision regression must become uncertain")
        }
        let reason = uncertainty.reason
        XCTAssertTrue(reason.contains("regressed"))
        let poisonedCallState = await calls.snapshot()
        XCTAssertEqual(poisonedCallState.count, 1)
        XCTAssertEqual(poisonedCallState.lastExpected, expected)

        let retry = await PatchGenerationWorkflow.execute(
            plan,
            with: ClipboardPublishingExecutor(broker: broker)
        )
        guard case .commitUncertain(let retryUncertainty) = retry.state else {
            return XCTFail("Poisoned broker must remain uncertain")
        }
        let retryReason = retryUncertainty.reason
        XCTAssertTrue(retryReason.contains("invalid"))
        let retryCallState = await calls.snapshot()
        XCTAssertEqual(retryCallState.count, 1)

        let nonadvancingCalls = ClipboardCallLog()
        let nonadvancing = PatchGenerationWorkflow.makeExclusiveClipboardBroker(initialRevision: 5) { expected, text in
            await nonadvancingCalls.record(expected: expected, text: text)
            return .replaced(revision: expected.value)
        }
        let nonadvancingExpected = await nonadvancing.currentRevision
        let nonadvancingPlan = try planClipboard(
            source: makeSource(id: "nonadvancing", old: "old\n", new: "new\n"),
            revision: nonadvancingExpected
        )
        let nonadvancingOutcome = await PatchGenerationWorkflow.execute(
            nonadvancingPlan,
            with: ClipboardPublishingExecutor(broker: nonadvancing)
        )
        guard case .commitUncertain(let nonadvancingUncertainty) = nonadvancingOutcome.state else {
            return XCTFail("Nonadvancing replacement must poison epoch")
        }
        XCTAssertTrue(nonadvancingUncertainty.reason.contains("non-advancing"))
        _ = await PatchGenerationWorkflow.execute(
            nonadvancingPlan,
            with: ClipboardPublishingExecutor(broker: nonadvancing)
        )
        let nonadvancingCallState = await nonadvancingCalls.snapshot()
        XCTAssertEqual(nonadvancingCallState.count, 1)
        XCTAssertEqual(nonadvancingCallState.lastExpected, nonadvancingExpected)

        let uncertainCalls = ClipboardCallLog()
        let uncertainBroker = PatchGenerationWorkflow.makeExclusiveClipboardBroker(initialRevision: 13) { expected, text in
            await uncertainCalls.record(expected: expected, text: text)
            return .replacementUncertain("Platform could not establish publication state.")
        }
        let uncertainExpected = await uncertainBroker.currentRevision
        let uncertainPlan = try planClipboard(
            source: makeSource(id: "uncertain", old: "old\n", new: "new\n"),
            revision: uncertainExpected
        )
        let uncertainOutcome = await PatchGenerationWorkflow.execute(
            uncertainPlan,
            with: ClipboardPublishingExecutor(broker: uncertainBroker)
        )
        guard case .commitUncertain(let explicitUncertainty) = uncertainOutcome.state else {
            return XCTFail("Explicit platform uncertainty must poison broker epoch")
        }
        XCTAssertEqual(explicitUncertainty.reason, "Platform could not establish publication state.")
        _ = await PatchGenerationWorkflow.execute(
            uncertainPlan,
            with: ClipboardPublishingExecutor(broker: uncertainBroker)
        )
        let uncertainCallState = await uncertainCalls.snapshot()
        XCTAssertEqual(uncertainCallState.count, 1)
        XCTAssertEqual(uncertainCallState.lastExpected, uncertainExpected)
        XCTAssertEqual(uncertainCallState.lastText, uncertainPlan.generatedPatch)
    }

    func testClipboardCompareMissReceiptRejectsForeignSessionAndSubstitutedPlanReplay() async throws {
        let calls = ClipboardCallLog()
        let broker = PatchGenerationWorkflow.makeExclusiveClipboardBroker(initialRevision: 11) { expected, text in
            await calls.record(expected: expected, text: text)
            return .notReplaced(observedRevision: expected.value + 2)
        }
        let expected = await broker.currentRevision
        let plan = try planClipboard(
            source: makeSource(id: "miss", old: "old\n", new: "new\n"),
            revision: expected
        )
        let receiptStore = ClipboardNonPublicationReceiptStore()
        let outcome = await PatchGenerationWorkflow.execute(
            plan,
            with: ClipboardPublishingExecutor(
                broker: broker,
                nonPublicationReceiptStore: receiptStore
            )
        )
        guard case .notCommitted(let reason) = outcome.state,
            let receipt = await receiptStore.receipt()
        else {
            return XCTFail("Expected definitive sealed compare miss")
        }
        XCTAssertEqual(reason, .destinationChanged)
        XCTAssertEqual(receipt.expectedRevision, expected)
        XCTAssertEqual(receipt.planSHA256, plan.mutation.planSHA256)
        XCTAssertEqual(receipt.payloadSHA256, plan.mutation.generatedPatchSHA256)
        let callState = await calls.snapshot()
        XCTAssertEqual(callState.count, 1)
        XCTAssertEqual(callState.lastExpected, expected)
        XCTAssertEqual(callState.lastText, plan.generatedPatch)
        let currentRevision = await broker.currentRevision
        XCTAssertEqual(currentRevision.value, expected.value + 2)

        let retry = await PatchGenerationWorkflow.execute(
            plan,
            with: ClipboardPublishingExecutor(broker: broker)
        )
        guard case .commitUncertain = retry.state else {
            return XCTFail("Stale plan must not be reusable after compare miss")
        }
        let retryState = await calls.snapshot()
        XCTAssertEqual(retryState.count, 1)

        let foreignSession = await PatchGenerationWorkflow.execute(
            plan,
            with: ReplayedClipboardNonPublicationReceiptExecutor(receipt: receipt)
        )
        guard case .commitUncertain(let foreignUncertainty) = foreignSession.state else {
            return XCTFail("Foreign-session clipboard compare-miss receipt must be uncertain")
        }
        XCTAssertEqual(
            foreignUncertainty.reason,
            "Clipboard non-commit evidence does not match plan."
        )

        let substitutionBroker = PatchGenerationWorkflow.makeExclusiveClipboardBroker(
            initialRevision: 21
        ) { expected, _ in
            .notReplaced(observedRevision: expected.value + 1)
        }
        let substitutionExpected = await substitutionBroker.currentRevision
        let producerPlan = try planClipboard(
            source: makeSource(id: "miss-producer", old: "old\n", new: "new\n"),
            revision: substitutionExpected
        )
        let substitutedPlan = try planClipboard(
            source: makeSource(id: "miss-substitute", old: "old\n", new: "different\n"),
            revision: substitutionExpected
        )
        XCTAssertNotEqual(producerPlan.mutation.planSHA256, substitutedPlan.mutation.planSHA256)
        let substituted = await PatchGenerationWorkflow.execute(
            producerPlan,
            with: MismatchedClipboardPlanExecutor(
                broker: substitutionBroker,
                substitutedPlan: substitutedPlan.mutation
            )
        )
        guard case .commitUncertain(let substitutedUncertainty) = substituted.state else {
            return XCTFail("Substituted-plan clipboard compare-miss receipt must be uncertain")
        }
        XCTAssertEqual(
            substitutedUncertainty.reason,
            "Clipboard non-commit evidence does not match plan."
        )
    }

    func testConcurrentClipboardPublicationInvokesAtomicAdapterExactlyOnce() async throws {
        let adapterEntered = expectation(description: "Clipboard adapter entered")
        let secondCompleted = expectation(description: "Second publication rejected while adapter blocked")
        let gate = ClipboardGate()
        let broker = PatchGenerationWorkflow.makeExclusiveClipboardBroker(initialRevision: 1) { expected, _ in
            adapterEntered.fulfill()
            await gate.enter()
            return .replaced(revision: expected.value + 1)
        }
        let expected = await broker.currentRevision
        let plan = try planClipboard(
            source: makeSource(id: "concurrent", old: "old\n", new: "new\n"),
            revision: expected
        )
        let executor = ClipboardPublishingExecutor(broker: broker)
        async let first = PatchGenerationWorkflow.execute(plan, with: executor)
        await fulfillment(of: [adapterEntered], timeout: 2)
        let secondTask = Task { @Sendable in
            let outcome = await PatchGenerationWorkflow.execute(plan, with: executor)
            secondCompleted.fulfill()
            return outcome
        }
        await fulfillment(of: [secondCompleted], timeout: 2)
        await gate.release()
        let secondOutcome = await secondTask.value
        let firstOutcome = await first
        let outcomes = [firstOutcome, secondOutcome]

        XCTAssertEqual(outcomes.filter { if case .committed = $0.state { true } else { false } }.count, 1)
        XCTAssertEqual(outcomes.filter { if case .commitUncertain = $0.state { true } else { false } }.count, 1)
        let callCount = await gate.count()
        XCTAssertEqual(callCount, 1)
    }

    func testCommittedOrUncertainTruthAndTerminalOutcomeAreOneShot() async throws {
        let plan = try planClipboard(
            source: makeSource(id: "truth", old: "old\n", new: "new\n"),
            revision: clipboardIdentity()
        )
        let beforeProbe = TerminalOutcomeProbe()
        let cancelled = await PatchGenerationWorkflow.execute(
            plan,
            with: BeforePublicationExecutor(probe: beforeProbe)
        )
        guard case .notCommitted(let reason) = cancelled.state else {
            return XCTFail("Prepublication cancellation must be definitive")
        }
        XCTAssertEqual(reason, .cancelled)
        let beforeState = await beforeProbe.snapshot()
        XCTAssertTrue(beforeState.secondFinishReturnedFirst)
        XCTAssertTrue(beforeState.publicationRejectedAfterTerminal)

        let invalidNonCommit = await PatchGenerationWorkflow.execute(
            plan,
            with: AfterPublicationUnprovenNonCommitExecutor()
        )
        guard case .commitUncertain(let uncertainty) = invalidNonCommit.state else {
            return XCTFail("Post-publication non-commit needs proof")
        }
        XCTAssertEqual(uncertainty.reason, "Non-commit result requested after publication started.")

        let foreign = await PatchGenerationWorkflow.execute(
            plan,
            with: BeforePublicationExecutor(probe: TerminalOutcomeProbe())
        )
        let normalized = await PatchGenerationWorkflow.execute(
            plan,
            with: ForeignOutcomeExecutor(outcome: foreign)
        )
        guard case .commitUncertain(let normalizedUncertainty) = normalized.state else {
            return XCTFail("Foreign executor result must normalize to uncertainty")
        }
        XCTAssertEqual(normalizedUncertainty.reason, "Executor returned a foreign or nonterminal outcome.")
    }

    func testExecutionOutcomeRejectsClipboardReceiptFromForeignSessionAndMismatchedPlan() async throws {
        let broker = PatchGenerationWorkflow.makeExclusiveClipboardBroker(initialRevision: 4) { expected, _ in
            .replaced(revision: expected.value + 1)
        }
        let expected = await broker.currentRevision
        let plan = try planClipboard(
            source: makeSource(id: "plan", old: "old\n", new: "new\n"),
            revision: expected
        )
        let store = ClipboardReceiptStore()
        let producer = await PatchGenerationWorkflow.execute(
            plan,
            with: ClipboardPublishingExecutor(broker: broker, receiptStore: store)
        )
        guard case .committed = producer.state,
            let receipt = await store.receipt()
        else { return XCTFail("Expected producer receipt") }
        XCTAssertEqual(receipt.expectedRevision, expected)
        XCTAssertEqual(receipt.committedRevision.value, expected.value + 1)
        XCTAssertEqual(receipt.planSHA256, plan.mutation.planSHA256)
        XCTAssertEqual(receipt.payloadSHA256, plan.mutation.generatedPatchSHA256)

        let outcome = await PatchGenerationWorkflow.execute(
            plan,
            with: ForeignClipboardReceiptExecutor(receipt: receipt)
        )
        guard case .commitUncertain(let uncertainty) = outcome.state else {
            return XCTFail("Foreign-session receipt must be uncertain")
        }
        XCTAssertEqual(uncertainty.reason, "Clipboard commit evidence does not match plan.")

        let mismatchedBroker = PatchGenerationWorkflow.makeExclusiveClipboardBroker(initialRevision: 9) { expected, _ in
            .replaced(revision: expected.value + 1)
        }
        let mismatchedExpected = await mismatchedBroker.currentRevision
        let producerPlan = try planClipboard(
            source: makeSource(id: "producer", old: "old\n", new: "new\n"),
            revision: mismatchedExpected
        )
        let substitutedPlan = try planClipboard(
            source: makeSource(id: "substituted", old: "old\n", new: "different\n"),
            revision: mismatchedExpected
        )
        XCTAssertNotEqual(producerPlan.mutation.planSHA256, substitutedPlan.mutation.planSHA256)
        let mismatched = await PatchGenerationWorkflow.execute(
            producerPlan,
            with: MismatchedClipboardPlanExecutor(
                broker: mismatchedBroker,
                substitutedPlan: substitutedPlan.mutation
            )
        )
        guard case .commitUncertain(let mismatchUncertainty) = mismatched.state else {
            return XCTFail("Same-session receipt must reject substituted plan")
        }
        XCTAssertEqual(mismatchUncertainty.reason, "Clipboard commit evidence does not match plan.")
    }

    private func request(
        sources: [PatchGenerationSource],
        selection: PatchGenerationSourceSelection = .all,
        contextLines: Int = 3,
        direction: PatchGenerationDirection = .forward,
        destination: PatchGenerationDestination,
        presentation: PatchGenerationPresentationIntent = .none,
        limits: PatchGenerationPlanningLimits = .default
    ) -> PatchGenerationRequest {
        PatchGenerationRequest(
            sources: sources,
            selection: selection,
            style: .unified,
            contextLines: contextLines,
            direction: direction,
            destination: destination,
            presentationIntent: presentation,
            limits: limits
        )
    }

    private func limits(
        maximumSources: Int = 1_024,
        maximumSelectedSources: Int = 1_024,
        maximumSourceIdentifierUTF8Bytes: Int = 256,
        maximumPathUTF8Bytes: Int = 16 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumInputBytes: Int = 64 * 1_024 * 1_024,
        maximumCombinedInputBytes: Int = 128 * 1_024 * 1_024,
        maximumExistingFileBytes: Int = 64 * 1_024 * 1_024,
        maximumPatchBytes: Int = 64 * 1_024 * 1_024,
        maximumDestinationPayloadBytes: Int = 128 * 1_024 * 1_024,
        maximumPlanOutputBytes: Int = 192 * 1_024 * 1_024,
        maximumContextLines: Int = 1_048_576,
        maximumCommandLineArgumentCount: Int = 256,
        maximumCommandLineArgumentUTF8Bytes: Int = 64 * 1_024,
        maximumTotalCommandLineUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumExistingFileMetadataBytes: Int = 16 * 1_024 * 1_024,
        maximumExternalRuleIdentifierUTF8Bytes: Int = 128,
        maximumWorkUnits: UInt64 = 2 * 1_024 * 1_024 * 1_024
    ) -> PatchGenerationPlanningLimits {
        PatchGenerationPlanningLimits(
            maximumSources: maximumSources,
            maximumSelectedSources: maximumSelectedSources,
            maximumSourceIdentifierUTF8Bytes: maximumSourceIdentifierUTF8Bytes,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: maximumTotalPathUTF8Bytes,
            maximumInputBytes: maximumInputBytes,
            maximumCombinedInputBytes: maximumCombinedInputBytes,
            maximumExistingFileBytes: maximumExistingFileBytes,
            maximumExistingFileMetadataBytes: maximumExistingFileMetadataBytes,
            maximumPatchBytes: maximumPatchBytes,
            maximumDestinationPayloadBytes: maximumDestinationPayloadBytes,
            maximumPlanOutputBytes: maximumPlanOutputBytes,
            maximumContextLines: maximumContextLines,
            maximumCommandLineArgumentCount: maximumCommandLineArgumentCount,
            maximumCommandLineArgumentUTF8Bytes: maximumCommandLineArgumentUTF8Bytes,
            maximumTotalCommandLineUTF8Bytes: maximumTotalCommandLineUTF8Bytes,
            maximumExternalRuleIdentifierUTF8Bytes: maximumExternalRuleIdentifierUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits
        )
    }

    private func makeSource(
        id: String,
        old: String,
        new: String,
        oldPath: String = "old.txt",
        newPath: String = "new.txt"
    ) -> PatchGenerationSource {
        makeSource(
            id: id,
            oldSnapshot: makeSnapshot(old),
            newSnapshot: makeSnapshot(new),
            oldPath: oldPath,
            newPath: newPath
        )
    }

    private func makeSource(
        id: String,
        oldSnapshot: PatchGenerationTextSnapshot,
        newSnapshot: PatchGenerationTextSnapshot,
        oldPath: String,
        newPath: String
    ) -> PatchGenerationSource {
        PatchGenerationSource(
            id: PatchGenerationSourceID(rawValue: id),
            oldSnapshot: oldSnapshot,
            newSnapshot: newSnapshot,
            oldPath: oldPath,
            newPath: newPath
        )
    }

    private func makeSnapshot(
        _ text: String,
        identity: PatchGenerationSnapshotIdentity = .document(UUID()),
        revision: UInt64 = 1
    ) -> PatchGenerationTextSnapshot {
        PatchGenerationTextSnapshot(identity: identity, revision: revision, text: text)
    }

    private func clipboardIdentity(value: UInt64 = 0) -> PatchGenerationClipboardRevision {
        PatchGenerationClipboardRevision(
            brokerIdentifier: PatchGenerationClipboardBrokerIdentifier(rawValue: UUID()),
            epoch: PatchGenerationClipboardBrokerEpoch(rawValue: UUID()),
            value: value
        )
    }

    private func clipboardDestination(
        _ revision: PatchGenerationClipboardRevision
    ) -> PatchGenerationDestination {
        .clipboard(PatchGenerationClipboardDestination(expectedRevision: revision))
    }

    private func planClipboard(
        source: PatchGenerationSource,
        revision: PatchGenerationClipboardRevision
    ) throws -> PatchGenerationPlan {
        try PatchGenerationWorkflow.plan(
            request(sources: [source], destination: clipboardDestination(revision))
        )
    }

    private func makeCreatePlan(
        directory: URL,
        destinationURL: URL,
        editor: Bool,
        maximumMetadataBytes: Int = 1 << 20,
        source: PatchGenerationSource? = nil
    ) throws -> PatchGenerationPlan {
        let parent = try canonicalIdentity(directory, kind: .directory)
        return try PatchGenerationWorkflow.plan(
            request(
                sources: [source ?? makeSource(id: "file", old: "old\n", new: "new\n")],
                contextLines: 0,
                destination: .file(
                    PatchGenerationFileDestination(
                        url: destinationURL,
                        disposition: .createNew(parentIdentity: parent)
                    )
                ),
                presentation: PatchGenerationPresentationIntent(
                    externalEditor: editor ? .openFile(ruleIdentifier: "editor.rule") : .none
                ),
                limits: limits(maximumExistingFileMetadataBytes: maximumMetadataBytes)
            )
        )
    }

    private func makeFileReceiptFixture(
        editor: Bool,
        maximumMetadataBytes: Int = 1 << 20,
        extendedAttributes: [String: Data] = [:],
        includeNonemptyACL: Bool = false,
        operation: FileReceiptFixtureOperation = .createNew
    ) throws -> FileReceiptFixture {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "published.patch")
        let source = makeSource(id: "file", old: "old\n", new: "new\n")
        let provisionalPlan = try makeCreatePlan(
            directory: directory,
            destinationURL: url,
            editor: editor,
            maximumMetadataBytes: maximumMetadataBytes,
            source: source
        )
        guard case .file(let provisionalDestination) = provisionalPlan.destination else {
            throw CocoaError(.fileWriteUnknown)
        }
        let existingData = Data("existing\n".utf8)
        try (operation == .append ? existingData : provisionalDestination.payload).write(to: url)
        let decoyURL = directory.appending(path: "decoy.patch")
        try provisionalDestination.payload.write(to: decoyURL)
        XCTAssertEqual(chmod(url.path, 0o600), 0)
        XCTAssertEqual(chmod(decoyURL.path, 0o600), 0)
        if includeNonemptyACL { try addNonemptyACL(to: url) }
        for (name, value) in extendedAttributes {
            try setExtendedAttribute(name: name, value: value, at: url)
        }
        let parent = try canonicalIdentity(directory, kind: .directory)
        let existingRevision = try fileRevision(url, metadataMaximum: maximumMetadataBytes)
        let plan: PatchGenerationPlan
        switch operation {
        case .createNew:
            plan = provisionalPlan
        case .overwrite:
            plan = try PatchGenerationWorkflow.plan(
                request(
                    sources: [source],
                    contextLines: 0,
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: url,
                            disposition: .overwrite(expectedParent: parent, expected: existingRevision)
                        )
                    ),
                    presentation: PatchGenerationPresentationIntent(
                        externalEditor: editor ? .openFile(ruleIdentifier: "editor.rule") : .none
                    ),
                    limits: limits(maximumExistingFileMetadataBytes: maximumMetadataBytes)
                )
            )
        case .append:
            plan = try PatchGenerationWorkflow.plan(
                request(
                    sources: [source],
                    contextLines: 0,
                    destination: .file(
                        PatchGenerationFileDestination(
                            url: url,
                            disposition: .append(
                                expectedParent: parent,
                                expected: try PatchGenerationExistingFileSnapshot(
                                    revision: existingRevision,
                                    data: existingData
                                ),
                                lineEnding: .lf
                            )
                        )
                    ),
                    presentation: PatchGenerationPresentationIntent(
                        externalEditor: editor ? .openFile(ruleIdentifier: "editor.rule") : .none
                    ),
                    limits: limits(maximumExistingFileMetadataBytes: maximumMetadataBytes)
                )
            )
        }
        guard case .file(let destination) = plan.destination else {
            throw CocoaError(.fileWriteUnknown)
        }
        let currentData = try Data(contentsOf: url)
        if destination.payload != currentData {
            try destination.payload.write(to: url)
            XCTAssertEqual(chmod(url.path, mode_t(destination.finalPermissions)), 0)
        }
        let revision = try fileRevision(url, metadataMaximum: maximumMetadataBytes)
        let decoyRevision = try fileRevision(decoyURL, metadataMaximum: maximumMetadataBytes)
        let parentDescriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parentDescriptor >= 0 else { throw posixError() }
        let foreignParentURL = directory.appending(path: "foreign-parent", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: foreignParentURL,
            withIntermediateDirectories: false
        )
        let foreignParentDescriptor = Darwin.open(
            foreignParentURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC
        )
        guard foreignParentDescriptor >= 0 else {
            Darwin.close(parentDescriptor)
            throw posixError()
        }
        return FileReceiptFixture(
            plan: plan,
            source: source,
            url: url,
            decoyURL: decoyURL,
            payload: destination.payload,
            parent: parent,
            revision: revision,
            decoyRevision: decoyRevision,
            parentDescriptor: parentDescriptor,
            foreignParentDescriptor: foreignParentDescriptor
        )
    }

    private func canonicalIdentity(
        _ url: URL,
        kind: PatchGenerationCanonicalItemKind
    ) throws -> PatchGenerationCanonicalFileIdentity {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw posixError() }
        return PatchGenerationCanonicalFileIdentity(
            canonicalURL: URL(
                fileURLWithPath: url.standardizedFileURL.path,
                isDirectory: kind == .directory
            ),
            kind: kind,
            deviceID: UInt64(information.st_dev),
            fileID: UInt64(information.st_ino),
            generation: UInt32(information.st_gen)
        )
    }

    private func fileRevision(
        _ url: URL,
        metadataMaximum: Int
    ) throws -> PatchGenerationFileRevision {
        let descriptor = try openReadOnly(url)
        defer { Darwin.close(descriptor) }
        var initialInformation = stat()
        guard Darwin.fstat(descriptor, &initialInformation) == 0 else { throw posixError() }
        let data = try descriptorData(descriptor, byteCount: Int(initialInformation.st_size))
        let metadata = try descriptorMetadata(descriptor, maximumBytes: metadataMaximum)
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw posixError() }
        guard stableRevisionFields(initialInformation) == stableRevisionFields(information) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ESTALE))
        }
        let identity = PatchGenerationCanonicalFileIdentity(
            canonicalURL: URL(fileURLWithPath: url.standardizedFileURL.path),
            kind: .regularFile,
            deviceID: UInt64(information.st_dev),
            fileID: UInt64(information.st_ino),
            generation: UInt32(information.st_gen)
        )
        return PatchGenerationFileRevision(
            identity: identity,
            byteCount: UInt64(information.st_size),
            linkCount: UInt64(information.st_nlink),
            permissions: UInt16(information.st_mode & mode_t(0o7777)),
            ownerID: information.st_uid,
            groupID: information.st_gid,
            flags: information.st_flags,
            metadataByteCount: UInt64(metadata.data.count),
            modificationTimeSeconds: Int64(information.st_mtimespec.tv_sec),
            modificationTimeNanoseconds: Int32(information.st_mtimespec.tv_nsec),
            statusChangeTimeSeconds: Int64(information.st_ctimespec.tv_sec),
            statusChangeTimeNanoseconds: Int32(information.st_ctimespec.tv_nsec),
            contentSHA256: digest(data),
            metadataSHA256: digest(metadata.data)
        )
    }

    private func descriptorData(_ descriptor: Int32, byteCount: Int) throws -> Data {
        var data = Data(count: byteCount)
        let readCount = try data.withUnsafeMutableBytes { storage -> Int in
            guard let baseAddress = storage.baseAddress else { return 0 }
            var offset = 0
            while offset < storage.count {
                let result = Darwin.pread(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    storage.count - offset,
                    off_t(offset)
                )
                guard result >= 0 else { throw posixError() }
                guard result > 0 else { break }
                offset += result
            }
            return offset
        }
        guard readCount == byteCount else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ESTALE))
        }
        return data
    }

    private func stableRevisionFields(_ information: stat) -> [UInt64] {
        [
            UInt64(information.st_dev),
            UInt64(information.st_ino),
            UInt64(information.st_gen),
            UInt64(information.st_size),
            UInt64(information.st_nlink),
            UInt64(information.st_mode),
            UInt64(information.st_uid),
            UInt64(information.st_gid),
            UInt64(information.st_flags),
            UInt64(bitPattern: Int64(information.st_mtimespec.tv_sec)),
            UInt64(bitPattern: Int64(information.st_mtimespec.tv_nsec)),
            UInt64(bitPattern: Int64(information.st_ctimespec.tv_sec)),
            UInt64(bitPattern: Int64(information.st_ctimespec.tv_nsec))
        ]
    }

    private func descriptorMetadata(
        _ descriptor: Int32,
        maximumBytes: Int
    ) throws -> (data: Data, names: [String]) {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw posixError() }
        var bytes: [UInt8] = []
        func reserve(_ count: Int) throws {
            guard count >= 0, count <= maximumBytes - bytes.count else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EFBIG))
            }
        }
        func appendUInt64(_ value: UInt64) throws {
            try reserve(MemoryLayout<UInt64>.size)
            var bigEndian = value.bigEndian
            withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
        }
        func appendBytes(_ value: [UInt8]) throws {
            try reserve(value.count)
            bytes.append(contentsOf: value)
        }
        try appendUInt64(UInt64(information.st_mode & mode_t(0o7777)))
        try appendUInt64(UInt64(information.st_uid))
        try appendUInt64(UInt64(information.st_gid))
        try appendUInt64(UInt64(information.st_flags))

        errno = 0
        if let acl = Darwin.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) {
            defer { _ = Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
            let aclSize = Darwin.acl_size(acl)
            guard aclSize >= 0 else { throw posixError() }
            try appendUInt64(UInt64(aclSize))
            try reserve(aclSize)
            var aclBytes = [UInt8](repeating: 0, count: aclSize)
            guard aclBytes.withUnsafeMutableBytes({ Darwin.acl_copy_ext($0.baseAddress, acl, aclSize) }) == aclSize else {
                throw posixError()
            }
            try appendBytes(aclBytes)
        } else if errno == ENOENT || errno == ENOTSUP {
            try appendUInt64(0)
        } else {
            throw posixError()
        }

        let nameByteCount = Darwin.flistxattr(descriptor, nil, 0, 0)
        guard nameByteCount >= 0 else { throw posixError() }
        guard nameByteCount <= maximumBytes else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EFBIG))
        }
        var names: [[UInt8]] = []
        if nameByteCount > 0 {
            var rawNames = [CChar](repeating: 0, count: nameByteCount)
            guard Darwin.flistxattr(descriptor, &rawNames, rawNames.count, 0) == nameByteCount else {
                throw posixError()
            }
            var index = 0
            while index < rawNames.count {
                let end = rawNames[index...].firstIndex(of: 0) ?? rawNames.endIndex
                guard end > index else { break }
                names.append(rawNames[index..<end].map(UInt8.init(bitPattern:)))
                index = end + 1
            }
        }
        for nameBytes in names.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            try appendUInt64(UInt64(nameBytes.count))
            try appendBytes(nameBytes)
            let name = String(decoding: nameBytes, as: UTF8.self)
            let valueCount = name.withCString { Darwin.fgetxattr(descriptor, $0, nil, 0, 0, 0) }
            guard valueCount >= 0 else { throw posixError() }
            try appendUInt64(UInt64(valueCount))
            try reserve(valueCount)
            if valueCount > 0 {
                var value = [UInt8](repeating: 0, count: valueCount)
                guard name.withCString({ Darwin.fgetxattr(descriptor, $0, &value, value.count, 0, 0) }) == valueCount else {
                    throw posixError()
                }
                try appendBytes(value)
            }
        }
        return (Data(bytes), names.map { String(decoding: $0, as: UTF8.self) })
    }

    private func replacing(
        _ revision: PatchGenerationFileRevision,
        contentSHA256: [UInt8]
    ) -> PatchGenerationFileRevision {
        PatchGenerationFileRevision(
            identity: revision.identity,
            byteCount: revision.byteCount,
            linkCount: revision.linkCount,
            permissions: revision.permissions,
            ownerID: revision.ownerID,
            groupID: revision.groupID,
            flags: revision.flags,
            metadataByteCount: revision.metadataByteCount,
            modificationTimeSeconds: revision.modificationTimeSeconds,
            modificationTimeNanoseconds: revision.modificationTimeNanoseconds,
            statusChangeTimeSeconds: revision.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: revision.statusChangeTimeNanoseconds,
            contentSHA256: contentSHA256,
            metadataSHA256: revision.metadataSHA256
        )
    }

    private func replacing(
        _ revision: PatchGenerationFileRevision,
        metadataByteCount: UInt64
    ) -> PatchGenerationFileRevision {
        PatchGenerationFileRevision(
            identity: revision.identity,
            byteCount: revision.byteCount,
            linkCount: revision.linkCount,
            permissions: revision.permissions,
            ownerID: revision.ownerID,
            groupID: revision.groupID,
            flags: revision.flags,
            metadataByteCount: metadataByteCount,
            modificationTimeSeconds: revision.modificationTimeSeconds,
            modificationTimeNanoseconds: revision.modificationTimeNanoseconds,
            statusChangeTimeSeconds: revision.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: revision.statusChangeTimeNanoseconds,
            contentSHA256: revision.contentSHA256,
            metadataSHA256: revision.metadataSHA256
        )
    }

    private func replacing(
        _ revision: PatchGenerationFileRevision,
        metadataSHA256: [UInt8]
    ) -> PatchGenerationFileRevision {
        PatchGenerationFileRevision(
            identity: revision.identity,
            byteCount: revision.byteCount,
            linkCount: revision.linkCount,
            permissions: revision.permissions,
            ownerID: revision.ownerID,
            groupID: revision.groupID,
            flags: revision.flags,
            metadataByteCount: revision.metadataByteCount,
            modificationTimeSeconds: revision.modificationTimeSeconds,
            modificationTimeNanoseconds: revision.modificationTimeNanoseconds,
            statusChangeTimeSeconds: revision.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: revision.statusChangeTimeNanoseconds,
            contentSHA256: revision.contentSHA256,
            metadataSHA256: metadataSHA256
        )
    }

    private func openReadOnly(_ url: URL) throws -> Int32 {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        return descriptor
    }

    private func setExtendedAttribute(name: String, value: Data, at url: URL) throws {
        let status = value.withUnsafeBytes { storage in
            name.withCString { attributeName in
                url.path.withCString { path in
                    Darwin.setxattr(path, attributeName, storage.baseAddress, storage.count, 0, 0)
                }
            }
        }
        guard status == 0 else { throw posixError() }
    }

    private func addNonemptyACL(to url: URL) throws {
        guard let initialACL = Darwin.acl_init(1) else {
            throw XCTSkip("Temporary filesystem does not support extended ACL creation.")
        }
        var acl: acl_t? = initialACL
        defer {
            if let acl { Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        }
        var entry: acl_entry_t?
        guard Darwin.acl_create_entry(&acl, &entry) == 0, let entry else {
            throw XCTSkip("Temporary filesystem does not support extended ACL entries.")
        }
        var qualifier: uuid_t = (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
        guard Darwin.acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) == 0,
            Darwin.acl_set_qualifier(entry, &qualifier) == 0
        else {
            throw XCTSkip("Temporary filesystem does not accept extended ACL qualifiers.")
        }
        var permissions: acl_permset_t?
        guard Darwin.acl_get_permset(entry, &permissions) == 0,
            let permissions,
            Darwin.acl_clear_perms(permissions) == 0,
            Darwin.acl_add_perm(permissions, ACL_READ_DATA) == 0,
            Darwin.acl_set_permset(entry, permissions) == 0,
            let acl,
            url.path.withCString({ Darwin.acl_set_file($0, ACL_TYPE_EXTENDED, acl) }) == 0
        else {
            throw XCTSkip("Temporary filesystem does not support nonempty extended ACLs.")
        }
    }

    private func hasNonemptyACL(at url: URL) throws -> Bool {
        let descriptor = try openReadOnly(url)
        defer { Darwin.close(descriptor) }
        errno = 0
        guard let acl = Darwin.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT || errno == ENOTSUP { return false }
            throw posixError()
        }
        defer { Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        return Darwin.acl_get_entry(acl, ACL_FIRST_ENTRY.rawValue, &entry) == 0 && entry != nil
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PatchGenerationWorkflowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        XCTAssertEqual(chmod(directory.path, 0o700), 0)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func assertPlanningError<T>(
        _ expected: PatchGenerationPlanningError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? PatchGenerationPlanningError, expected, file: file, line: line)
        }
    }

    private func assertPlanningErrorMatching<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: (PatchGenerationPlanningError) -> Bool,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard let error = error as? PatchGenerationPlanningError else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            XCTAssertTrue(predicate(error), "Unexpected planning error: \(error)", file: file, line: line)
        }
    }

    private func digest(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func patch(_ lines: String...) -> String {
        lines.joined(separator: "\n") + "\n"
    }

    private func translatingLFToCRLF(_ data: Data) -> Data {
        Data(data.flatMap { $0 == 0x0A ? [0x0D, 0x0A] : [$0] })
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

private struct FileReceiptFixture: Sendable {
    let plan: PatchGenerationPlan
    let source: PatchGenerationSource
    let url: URL
    let decoyURL: URL
    let payload: Data
    let parent: PatchGenerationCanonicalFileIdentity
    let revision: PatchGenerationFileRevision
    let decoyRevision: PatchGenerationFileRevision
    let parentDescriptor: Int32
    let foreignParentDescriptor: Int32

    func close() {
        Darwin.close(parentDescriptor)
        Darwin.close(foreignParentDescriptor)
    }
}

private enum FileReceiptFixtureOperation: String, CaseIterable, Sendable {
    case createNew
    case overwrite
    case append
}

private actor ClipboardCallLog {
    private(set) var count = 0
    private(set) var lastExpected: PatchGenerationClipboardRevision?
    private(set) var lastText: String?

    func record(expected: PatchGenerationClipboardRevision, text: String) {
        count += 1
        lastExpected = expected
        lastText = text
    }

    func snapshot() -> (
        count: Int,
        lastExpected: PatchGenerationClipboardRevision?,
        lastText: String?
    ) {
        (count, lastExpected, lastText)
    }
}

private actor ClipboardGate {
    private var released = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0

    func enter() async {
        callCount += 1
        if released { return }
        precondition(releaseWaiter == nil)
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func release() {
        released = true
        let waiter = releaseWaiter
        releaseWaiter = nil
        waiter?.resume()
    }

    func count() -> Int {
        callCount
    }
}

private actor PlanningStartGate {
    private var released = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        if released { return }
        precondition(releaseWaiter == nil)
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func release() {
        released = true
        let waiter = releaseWaiter
        releaseWaiter = nil
        waiter?.resume()
    }
}

private actor FileRaceProbe {
    struct State: Sendable {
        let tokenCount: Int
        let permitCount: Int
        let compareAndSwapStartCount: Int
        let terminalEvidenceCount: Int
    }

    private var state = State(
        tokenCount: 0,
        permitCount: 0,
        compareAndSwapStartCount: 0,
        terminalEvidenceCount: 0
    )

    func record(
        tokenCount: Int,
        permitCount: Int,
        compareAndSwapStartCount: Int,
        terminalEvidenceCount: Int
    ) {
        state = State(
            tokenCount: tokenCount,
            permitCount: permitCount,
            compareAndSwapStartCount: compareAndSwapStartCount,
            terminalEvidenceCount: terminalEvidenceCount
        )
    }

    func snapshot() -> State {
        state
    }
}

private actor FileEvidenceProbe {
    struct State: Sendable {
        var secondPermitRejected = false
        var firstCASStarted = false
        var originalPermitRejectedAfterOutcome = false
        var receiptSealed = false
        var cancellationObserved = false
        var failureObserved = false
        var sealErrorCode: Int?
        var submittedParentDescriptorMatchesExpected: Bool?
        var submittedFileDescriptorCloseOnExec: Bool?
    }

    private var state = State()

    func update(_ operation: @Sendable (inout State) -> Void) {
        operation(&state)
    }

    func snapshot() -> State {
        state
    }
}

/// Exercises core receipt/session contracts only. No filesystem publication backend exists here.
private struct FileEvidenceHarness: PatchGenerationPlanExecutor {
    enum Mode: Sendable {
        case cancelAfterCASStart
        case failureAfterCASStart
        case sealValid
        case storeSealedReceiptWithoutCommit
        case sealWritable
        case sealWrongLeaf
        case sealWrongPayload
        case sealForeignParent
        case sealWithoutCloseOnExec
    }

    let fixture: FileReceiptFixture
    let mode: Mode
    let probe: FileEvidenceProbe
    let evidencePlan: PatchGenerationMutationPlan?
    let evidenceRevision: PatchGenerationFileRevision?
    let receiptStore: FileReceiptStore?

    init(
        fixture: FileReceiptFixture,
        mode: Mode,
        probe: FileEvidenceProbe,
        evidencePlan: PatchGenerationMutationPlan? = nil,
        evidenceRevision: PatchGenerationFileRevision? = nil,
        receiptStore: FileReceiptStore? = nil
    ) {
        self.fixture = fixture
        self.mode = mode
        self.probe = probe
        self.evidencePlan = evidencePlan
        self.evidenceRevision = evidenceRevision
        self.receiptStore = receiptStore
    }

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        guard let token = session.beginPublication() else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .failed("Publication did not start.")
            )
        }
        guard
            let permit = PatchGenerationFilePublicationReceiptFactory.makeCompareAndSwapPermit(
                token: token,
                plan: plan
            )
        else {
            return PatchGenerationExecutionOutcomeFactory.uncertain(
                session: session,
                token: token,
                destinationURL: fixture.url,
                reason: "File permit unavailable."
            )
        }
        let secondPermit = PatchGenerationFilePublicationReceiptFactory.makeCompareAndSwapPermit(
            token: token,
            plan: plan
        )
        await probe.update { $0.secondPermitRejected = secondPermit == nil }

        switch mode {
        case .cancelAfterCASStart:
            let began = PatchGenerationFilePublicationReceiptFactory.beginCompareAndSwap(
                permit: permit,
                plan: plan
            )
            withUnsafeCurrentTask { $0?.cancel() }
            let outcome = PatchGenerationExecutionOutcomeFactory.uncertain(
                session: session,
                token: token,
                destinationURL: fixture.url,
                reason: "Cancelled after file CAS started."
            )
            let reuse = PatchGenerationFilePublicationReceiptFactory.makeCompareAndSwapPermit(
                token: token,
                plan: plan
            )
            let restarted = PatchGenerationFilePublicationReceiptFactory.beginCompareAndSwap(
                permit: permit,
                plan: plan
            )
            await probe.update {
                $0.cancellationObserved = Task.isCancelled
                $0.secondPermitRejected = reuse == nil
                $0.firstCASStarted = began
                $0.originalPermitRejectedAfterOutcome = !restarted
            }
            return outcome
        case .failureAfterCASStart:
            let began = PatchGenerationFilePublicationReceiptFactory.beginCompareAndSwap(
                permit: permit,
                plan: plan
            )
            let outcome = PatchGenerationExecutionOutcomeFactory.uncertain(
                session: session,
                token: token,
                destinationURL: fixture.url,
                reason: "File CAS failed after start."
            )
            let reuse = PatchGenerationFilePublicationReceiptFactory.makeCompareAndSwapPermit(
                token: token,
                plan: plan
            )
            let restarted = PatchGenerationFilePublicationReceiptFactory.beginCompareAndSwap(
                permit: permit,
                plan: plan
            )
            await probe.update {
                $0.failureObserved = true
                $0.secondPermitRejected = reuse == nil
                $0.firstCASStarted = began
                $0.originalPermitRejectedAfterOutcome = !restarted
            }
            return outcome
        case .sealValid, .storeSealedReceiptWithoutCommit, .sealWritable, .sealWrongLeaf,
            .sealWrongPayload, .sealForeignParent, .sealWithoutCloseOnExec:
            let began = PatchGenerationFilePublicationReceiptFactory.beginCompareAndSwap(
                permit: permit,
                plan: plan
            )
            await probe.update { $0.firstCASStarted = began }
            guard began else {
                return PatchGenerationExecutionOutcomeFactory.uncertain(
                    session: session,
                    token: token,
                    destinationURL: fixture.url,
                    reason: "File CAS did not start."
                )
            }
            let descriptor: Int32
            if case .sealWritable = mode {
                descriptor = Darwin.open(fixture.url.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
            } else if case .sealWrongLeaf = mode {
                descriptor = openReadOnlyDescriptor(fixture.decoyURL)
            } else {
                descriptor = openReadOnlyDescriptor(fixture.url)
            }
            guard descriptor >= 0 else {
                return PatchGenerationExecutionOutcomeFactory.uncertain(
                    session: session,
                    token: token,
                    destinationURL: fixture.url,
                    reason: "Descriptor open failed."
                )
            }
            if case .sealWithoutCloseOnExec = mode {
                guard Darwin.fcntl(descriptor, F_SETFD, 0) == 0 else {
                    Darwin.close(descriptor)
                    return PatchGenerationExecutionOutcomeFactory.uncertain(
                        session: session,
                        token: token,
                        destinationURL: fixture.url,
                        reason: "Descriptor flag mutation failed."
                    )
                }
            }
            let parentDescriptor =
                mode.isForeignParent
                ? fixture.foreignParentDescriptor
                : fixture.parentDescriptor
            var parentInformation = stat()
            let parentMatches =
                Darwin.fstat(parentDescriptor, &parentInformation) == 0
                && UInt64(parentInformation.st_dev) == fixture.parent.deviceID
                && UInt64(parentInformation.st_ino) == fixture.parent.fileID
                && UInt32(parentInformation.st_gen) == fixture.parent.generation
            let descriptorFlags = Darwin.fcntl(descriptor, F_GETFD)
            await probe.update {
                $0.submittedParentDescriptorMatchesExpected = parentMatches
                $0.submittedFileDescriptorCloseOnExec =
                    descriptorFlags >= 0
                    && descriptorFlags & FD_CLOEXEC != 0
            }
            do {
                let receipt = try PatchGenerationFilePublicationReceiptFactory.seal(
                    permit: permit,
                    plan: evidencePlan ?? plan,
                    revision: evidenceRevision
                        ?? (mode.isWrongLeaf ? fixture.decoyRevision : fixture.revision),
                    guarantee: .atomicDescriptorRelativeFullRevisionCompareAndSwap,
                    parentIdentity: fixture.parent,
                    leafName: fixture.url.lastPathComponent,
                    parentDirectoryDescriptor: parentDescriptor,
                    consumingReadOnlyFileDescriptor: descriptor
                )
                await probe.update {
                    $0.receiptSealed = receipt != nil
                }
                guard let receipt else {
                    return PatchGenerationExecutionOutcomeFactory.uncertain(
                        session: session,
                        token: token,
                        destinationURL: fixture.url,
                        reason: "File receipt was rejected."
                    )
                }
                if case .storeSealedReceiptWithoutCommit = mode {
                    await receiptStore?.store(receipt)
                    return PatchGenerationExecutionOutcomeFactory.uncertain(
                        session: session,
                        token: token,
                        destinationURL: fixture.url,
                        reason: "Stored unconsumed file receipt."
                    )
                }
                let outcome = PatchGenerationExecutionOutcomeFactory.committedFile(
                    plan: plan,
                    session: session,
                    token: token,
                    receipt: receipt
                )
                await receiptStore?.store(receipt)
                return outcome
            } catch {
                let errorCode = (error as NSError).code
                await probe.update {
                    $0.sealErrorCode = errorCode
                }
                return PatchGenerationExecutionOutcomeFactory.uncertain(
                    session: session,
                    token: token,
                    destinationURL: fixture.url,
                    reason: "File receipt sealing failed: \(error)"
                )
            }
        }
    }
}

private struct RacingFileEvidenceHarness: PatchGenerationPlanExecutor {
    let destinationURL: URL
    let probe: FileRaceProbe

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        let tokens = await withTaskGroup(of: PatchGenerationPublicationToken?.self) { group in
            for _ in 0..<16 {
                group.addTask { session.beginPublication() }
            }
            return await group.reduce(into: []) { $0.append($1) }.compactMap { $0 }
        }
        guard let token = tokens.first else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .failed("No publication token won contention.")
            )
        }
        let permits = await withTaskGroup(of: PatchGenerationFileCompareAndSwapPermit?.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    PatchGenerationFilePublicationReceiptFactory.makeCompareAndSwapPermit(
                        token: token,
                        plan: plan
                    )
                }
            }
            return await group.reduce(into: []) { $0.append($1) }.compactMap { $0 }
        }
        guard let permit = permits.first else {
            return PatchGenerationExecutionOutcomeFactory.uncertain(
                session: session,
                token: token,
                destinationURL: destinationURL,
                reason: "No file permit won contention."
            )
        }
        let starts = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    PatchGenerationFilePublicationReceiptFactory.beginCompareAndSwap(
                        permit: permit,
                        plan: plan
                    )
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let receipts = await withTaskGroup(of: PatchGenerationFileNonPublicationReceipt?.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    PatchGenerationFilePublicationReceiptFactory.sealCompareMiss(
                        permit: permit,
                        plan: plan
                    )
                }
            }
            return await group.reduce(into: []) { $0.append($1) }.compactMap { $0 }
        }
        await probe.record(
            tokenCount: tokens.count,
            permitCount: permits.count,
            compareAndSwapStartCount: starts.filter { $0 }.count,
            terminalEvidenceCount: receipts.count
        )
        guard let receipt = receipts.first else {
            return PatchGenerationExecutionOutcomeFactory.uncertain(
                session: session,
                token: token,
                destinationURL: destinationURL,
                reason: "No terminal evidence won contention."
            )
        }
        return PatchGenerationExecutionOutcomeFactory.notCommittedFile(
            plan: plan,
            session: session,
            token: token,
            receipt: receipt
        )
    }
}

private actor FileReceiptStore {
    private var storedReceipt: PatchGenerationFilePublicationReceipt?

    func store(_ receipt: PatchGenerationFilePublicationReceipt) {
        storedReceipt = receipt
    }

    func receipt() -> PatchGenerationFilePublicationReceipt? {
        storedReceipt
    }
}

private actor FileNonPublicationReceiptStore {
    private var storedReceipt: PatchGenerationFileNonPublicationReceipt?

    func store(_ receipt: PatchGenerationFileNonPublicationReceipt) {
        storedReceipt = receipt
    }

    func receipt() -> PatchGenerationFileNonPublicationReceipt? {
        storedReceipt
    }
}

private struct ReplayedFileReceiptExecutor: PatchGenerationPlanExecutor {
    let receipt: PatchGenerationFilePublicationReceipt

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        guard let token = session.beginPublication() else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .failed("Publication did not start.")
            )
        }
        return PatchGenerationExecutionOutcomeFactory.committedFile(
            plan: plan,
            session: session,
            token: token,
            receipt: receipt
        )
    }
}

private struct FileCompareMissExecutor: PatchGenerationPlanExecutor {
    let outcomePlan: PatchGenerationMutationPlan?
    let receiptStore: FileNonPublicationReceiptStore?

    init(
        outcomePlan: PatchGenerationMutationPlan? = nil,
        receiptStore: FileNonPublicationReceiptStore? = nil
    ) {
        self.outcomePlan = outcomePlan
        self.receiptStore = receiptStore
    }

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        guard let token = session.beginPublication(),
            let permit = PatchGenerationFilePublicationReceiptFactory.makeCompareAndSwapPermit(
                token: token,
                plan: plan
            ),
            PatchGenerationFilePublicationReceiptFactory.beginCompareAndSwap(
                permit: permit,
                plan: plan
            ),
            let receipt = PatchGenerationFilePublicationReceiptFactory.sealCompareMiss(
                permit: permit,
                plan: plan
            )
        else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .failed("File compare-miss evidence was unavailable.")
            )
        }
        await receiptStore?.store(receipt)
        return PatchGenerationExecutionOutcomeFactory.notCommittedFile(
            plan: outcomePlan ?? plan,
            session: session,
            token: token,
            receipt: receipt
        )
    }
}

private struct ReplayedFileNonPublicationReceiptExecutor: PatchGenerationPlanExecutor {
    let receipt: PatchGenerationFileNonPublicationReceipt

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        guard let token = session.beginPublication() else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .failed("Publication did not start.")
            )
        }
        return PatchGenerationExecutionOutcomeFactory.notCommittedFile(
            plan: plan,
            session: session,
            token: token,
            receipt: receipt
        )
    }
}

extension FileEvidenceHarness.Mode {
    fileprivate var isWrongLeaf: Bool {
        if case .sealWrongLeaf = self { return true }
        return false
    }

    fileprivate var isForeignParent: Bool {
        if case .sealForeignParent = self { return true }
        return false
    }
}

private actor ClipboardReceiptStore {
    private var storedReceipt: PatchGenerationClipboardPublicationReceipt?

    func store(_ receipt: PatchGenerationClipboardPublicationReceipt) {
        storedReceipt = receipt
    }

    func receipt() -> PatchGenerationClipboardPublicationReceipt? {
        storedReceipt
    }
}

private actor ClipboardNonPublicationReceiptStore {
    private var storedReceipt: PatchGenerationClipboardNonPublicationReceipt?

    func store(_ receipt: PatchGenerationClipboardNonPublicationReceipt) {
        storedReceipt = receipt
    }

    func receipt() -> PatchGenerationClipboardNonPublicationReceipt? {
        storedReceipt
    }
}

private struct ClipboardPublishingExecutor: PatchGenerationPlanExecutor {
    let broker: PatchGenerationExclusiveClipboardBroker
    let receiptStore: ClipboardReceiptStore?
    let nonPublicationReceiptStore: ClipboardNonPublicationReceiptStore?

    init(
        broker: PatchGenerationExclusiveClipboardBroker,
        receiptStore: ClipboardReceiptStore? = nil,
        nonPublicationReceiptStore: ClipboardNonPublicationReceiptStore? = nil
    ) {
        self.broker = broker
        self.receiptStore = receiptStore
        self.nonPublicationReceiptStore = nonPublicationReceiptStore
    }

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        guard let token = session.beginPublication() else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .failed("Publication did not start.")
            )
        }
        switch await broker.publish(plan, token: token) {
        case .replaced(let receipt):
            await receiptStore?.store(receipt)
            return PatchGenerationExecutionOutcomeFactory.committedClipboard(
                plan: plan,
                session: session,
                token: token,
                receipt: receipt
            )
        case .notCommitted(let receipt):
            await nonPublicationReceiptStore?.store(receipt)
            return PatchGenerationExecutionOutcomeFactory.notCommittedClipboard(
                plan: plan,
                session: session,
                token: token,
                receipt: receipt
            )
        case .notReplaced:
            return PatchGenerationExecutionOutcomeFactory.uncertain(
                session: session,
                token: token,
                destinationURL: nil,
                reason: "Clipboard comparison was not attempted."
            )
        case .replacementUncertain(let reason):
            return PatchGenerationExecutionOutcomeFactory.uncertain(
                session: session,
                token: token,
                destinationURL: nil,
                reason: reason
            )
        }
    }
}

private struct ReplayedClipboardNonPublicationReceiptExecutor: PatchGenerationPlanExecutor {
    let receipt: PatchGenerationClipboardNonPublicationReceipt

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        guard let token = session.beginPublication() else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .failed("Publication did not start.")
            )
        }
        return PatchGenerationExecutionOutcomeFactory.notCommittedClipboard(
            plan: plan,
            session: session,
            token: token,
            receipt: receipt
        )
    }
}

private struct ForeignClipboardReceiptExecutor: PatchGenerationPlanExecutor {
    let receipt: PatchGenerationClipboardPublicationReceipt

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        guard let token = session.beginPublication() else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .failed("Publication did not start.")
            )
        }
        return PatchGenerationExecutionOutcomeFactory.committedClipboard(
            plan: plan,
            session: session,
            token: token,
            receipt: receipt
        )
    }
}

private struct MismatchedClipboardPlanExecutor: PatchGenerationPlanExecutor {
    let broker: PatchGenerationExclusiveClipboardBroker
    let substitutedPlan: PatchGenerationMutationPlan

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        guard let token = session.beginPublication() else {
            return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
                session: session,
                reason: .failed("Publication did not start.")
            )
        }
        switch await broker.publish(plan, token: token) {
        case .replaced(let receipt):
            return PatchGenerationExecutionOutcomeFactory.committedClipboard(
                plan: substitutedPlan,
                session: session,
                token: token,
                receipt: receipt
            )
        case .notCommitted(let receipt):
            return PatchGenerationExecutionOutcomeFactory.notCommittedClipboard(
                plan: substitutedPlan,
                session: session,
                token: token,
                receipt: receipt
            )
        case .notReplaced:
            return PatchGenerationExecutionOutcomeFactory.uncertain(
                session: session,
                token: token,
                destinationURL: nil,
                reason: "Clipboard comparison was not attempted."
            )
        case .replacementUncertain(let reason):
            return PatchGenerationExecutionOutcomeFactory.uncertain(
                session: session,
                token: token,
                destinationURL: nil,
                reason: reason
            )
        }
    }
}

private actor TerminalOutcomeProbe {
    struct State: Sendable {
        var secondFinishReturnedFirst = false
        var publicationRejectedAfterTerminal = false
    }

    private var state = State()

    func record(first: PatchGenerationExecutionOutcome, second: PatchGenerationExecutionOutcome, publicationRejected: Bool) {
        state.secondFinishReturnedFirst = first == second
        state.publicationRejectedAfterTerminal = publicationRejected
    }

    func snapshot() -> State {
        state
    }
}

private struct BeforePublicationExecutor: PatchGenerationPlanExecutor {
    let probe: TerminalOutcomeProbe

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        _ = plan
        let first = PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
            session: session,
            reason: .cancelled
        )
        let second = PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
            session: session,
            reason: .failed("later")
        )
        await probe.record(
            first: first,
            second: second,
            publicationRejected: session.beginPublication() == nil
        )
        return first
    }
}

private struct AfterPublicationUnprovenNonCommitExecutor: PatchGenerationPlanExecutor {
    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        _ = plan
        _ = session.beginPublication()
        return PatchGenerationExecutionOutcomeFactory.notCommittedBeforePublication(
            session: session,
            reason: .cancelled
        )
    }
}

private struct ForeignOutcomeExecutor: PatchGenerationPlanExecutor {
    let outcome: PatchGenerationExecutionOutcome

    func execute(
        _ plan: PatchGenerationMutationPlan,
        session: PatchGenerationExecutionSession
    ) async -> PatchGenerationExecutionOutcome {
        _ = plan
        _ = session
        return outcome
    }
}

private func openReadOnlyDescriptor(_ url: URL) -> Int32 {
    Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
}
