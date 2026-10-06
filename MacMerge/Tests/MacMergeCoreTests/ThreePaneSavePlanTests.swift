import Foundation
import XCTest

@testable import MacMergeCore

final class ThreePaneSavePlanTests: XCTestCase {
    func testSaveMiddleLoadedDirtyPlansExactInPlaceCAS() throws {
        let middle = loadedState(side: .middle, dirty: true)
        let request = makeRequest(middle: middle, action: .saveMiddle())

        let plan = try ThreePaneSavePlanner.plan(request)
        let operation = try XCTUnwrap(plan.operations.first)
        guard case .loaded(let content, let binding) = middle else {
            return XCTFail("Expected loaded fixture")
        }

        XCTAssertEqual(plan.operations.count, 1)
        XCTAssertEqual(operation.side, .middle)
        XCTAssertEqual(operation.kind, .saveInPlace)
        XCTAssertEqual(operation.source, content)
        XCTAssertEqual(operation.sourceFile, binding)
        XCTAssertEqual(operation.destination.canonicalURL, binding.revision.identity.canonicalURL)
        XCTAssertEqual(operation.destination.parentIdentity, binding.parentIdentity)
        XCTAssertEqual(operation.destination.canonicalLeafIdentity, binding.canonicalLeafIdentity)
        XCTAssertEqual(operation.destination.state, .existing(binding.revision))
        XCTAssertEqual(operation.preservesEncoding, content.encoding)
        XCTAssertEqual(operation.preservesReadOnlyState, content.isReadOnly)
    }

    func testSaveMiddleLoadedCleanRejectsButCleanUntitledSaves() throws {
        assertPlanningError(.paneNotDirty(.middle)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(middle: self.loadedState(side: .middle, dirty: false), action: .saveMiddle())
            )
        }

        let cleanUntitled = untitledState(side: .middle, dirty: false)
        let destination = destination(side: .middle)
        let plan = try ThreePaneSavePlanner.plan(
            makeRequest(
                middle: cleanUntitled,
                action: .saveMiddle(destination: destination)
            )
        )

        XCTAssertEqual(plan.operations.count, 1)
        XCTAssertEqual(plan.operations[0].kind, .saveAsNewFile)
        XCTAssertNil(plan.operations[0].sourceFile)
        XCTAssertEqual(plan.operations[0].destination, destination.identity)
    }

    func testSaveMiddleRequiresDestinationOnlyForUntitledAndRejectsReadOnly() {
        assertPlanningError(.missingDestination(.middle)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    middle: self.untitledState(side: .middle, dirty: true),
                    action: .saveMiddle()
                )
            )
        }
        assertPlanningError(.unexpectedDestination(.middle)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    middle: self.loadedState(side: .middle, dirty: true),
                    action: .saveMiddle(destination: self.destination(side: .middle))
                )
            )
        }
        for state in [
            loadedState(side: .middle, dirty: true, readOnly: true),
            untitledState(side: .middle, dirty: true, readOnly: true),
            untitledState(side: .middle, dirty: false, readOnly: true)
        ] {
            assertPlanningError(.paneReadOnly(.middle)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(
                        middle: state,
                        action: .saveMiddle(destination: state.isUntitled ? self.destination(side: .middle) : nil)
                    )
                )
            }
        }
    }

    func testSaveAsMiddleHandlesLoadedUntitledCleanDirtyReadOnlyAndReplacement() throws {
        let vacant = destination(side: .middle)
        for state in [
            loadedState(side: .middle, dirty: false),
            loadedState(side: .middle, dirty: true, readOnly: true),
            untitledState(side: .middle, dirty: false),
            untitledState(side: .middle, dirty: true, readOnly: true)
        ] {
            let plan = try ThreePaneSavePlanner.plan(
                makeRequest(middle: state, action: .saveAsMiddle(destination: vacant))
            )
            let operation = try XCTUnwrap(plan.operations.first)

            XCTAssertEqual(plan.operations.count, 1)
            XCTAssertEqual(operation.side, .middle)
            XCTAssertEqual(operation.kind, .saveAsNewFile)
            XCTAssertEqual(operation.source, state.content)
            XCTAssertEqual(operation.sourceFile == nil, state.isUntitled)
            XCTAssertEqual(operation.preservesReadOnlyState, state.content?.isReadOnly)
        }

        let replacementRevision = fileRevision(
            url: fileURL(parentName: "replacement", fileName: "middle.txt"),
            fileID: 8_001,
            byteCount: 91,
            metadataByteCount: 17,
            contentHashByte: 0x91,
            metadataHashByte: 0x17,
            modificationTimeSeconds: 111,
            statusChangeTimeSeconds: 222
        )
        let replacement = destination(
            side: .middle,
            parentName: "replacement",
            state: .existing(replacementRevision)
        )
        let plan = try ThreePaneSavePlanner.plan(
            makeRequest(
                middle: loadedState(side: .middle, dirty: false),
                action: .saveAsMiddle(destination: replacement)
            )
        )

        XCTAssertEqual(plan.operations[0].kind, .saveAsReplacingFile)
        XCTAssertEqual(plan.operations[0].destination.state, .existing(replacementRevision))
    }

    func testSaveAllSelectsOnlyDirtyPanesInStableSideOrder() throws {
        let left = loadedState(side: .left, dirty: true)
        let middle = untitledState(side: .middle, dirty: true)
        let right = untitledState(side: .right, dirty: false)
        let middleDestination = destination(side: .middle)

        let plan = try ThreePaneSavePlanner.plan(
            makeRequest(
                left: left,
                middle: middle,
                right: right,
                action: .saveAll(destinations: [middleDestination])
            )
        )

        XCTAssertEqual(plan.operations.map(\.side), [.left, .middle])
        XCTAssertEqual(plan.operations.map(\.kind), [.saveInPlace, .saveAsNewFile])
        XCTAssertNotNil(plan.operations[0].sourceFile)
        XCTAssertNil(plan.operations[1].sourceFile)
        XCTAssertEqual(plan.operations[1].destination, middleDestination.identity)
    }

    func testSaveAllCleanLoadedAndUntitledPanesProduceEmptyPlan() throws {
        let plan = try ThreePaneSavePlanner.plan(
            makeRequest(
                left: loadedState(side: .left, dirty: false),
                middle: untitledState(side: .middle, dirty: false),
                right: loadedState(side: .right, dirty: false),
                action: .saveAll()
            )
        )

        XCTAssertTrue(plan.operations.isEmpty)
        XCTAssertGreaterThan(plan.estimatedWorkUnits, 0)
    }

    func testSaveAllRejectsDirtyReadOnlyMissingAndUnexpectedDestinations() {
        for side in ThreePaneSaveSide.allCases {
            var states = cleanUntitledStates()
            states[side] = untitledState(side: side, dirty: true, readOnly: true)
            assertPlanningError(.paneReadOnly(side)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(states: states, action: .saveAll(destinations: [self.destination(side: side)]))
                )
            }

            states[side] = untitledState(side: side, dirty: true)
            assertPlanningError(.missingDestination(side)) {
                try ThreePaneSavePlanner.plan(self.makeRequest(states: states, action: .saveAll()))
            }

            states[side] = loadedState(side: side, dirty: true)
            assertPlanningError(.unexpectedDestination(side)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(states: states, action: .saveAll(destinations: [self.destination(side: side)]))
                )
            }

            states[side] = untitledState(side: side, dirty: false)
            assertPlanningError(.unexpectedDestination(side)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(states: states, action: .saveAll(destinations: [self.destination(side: side)]))
                )
            }
        }
    }

    func testAllActionsRequireExactlyOneValidPanePerSide() {
        let normal = normalLoadedPanes()
        assertPlanningError(.invalidPaneCount(2)) {
            try ThreePaneSavePlanner.plan(
                ThreePaneSaveRequest(
                    panes: [
                        ThreePaneSavePane(side: .left, state: normal[.left]!),
                        ThreePaneSavePane(side: .middle, state: normal[.middle]!)
                    ],
                    action: .saveMiddle()
                )
            )
        }
        assertPlanningError(.duplicatePane(.left)) {
            try ThreePaneSavePlanner.plan(
                ThreePaneSaveRequest(
                    panes: [
                        ThreePaneSavePane(side: .left, state: normal[.left]!),
                        ThreePaneSavePane(side: .left, state: normal[.middle]!),
                        ThreePaneSavePane(side: .right, state: normal[.right]!)
                    ],
                    action: .saveMiddle()
                )
            )
        }
        assertPlanningError(.paneNotLoaded(.left)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(left: .unloaded, action: .saveAll())
            )
        }
    }

    func testDestinationSideDuplicateMissingAndUnexpectedValidation() {
        assertPlanningError(.wrongDestinationSide(expected: .middle, actual: .right)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    middle: self.untitledState(side: .middle, dirty: true),
                    action: .saveMiddle(destination: self.destination(side: .right))
                )
            )
        }
        assertPlanningError(.wrongDestinationSide(expected: .middle, actual: .left)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    action: .saveAsMiddle(destination: self.destination(side: .left))
                )
            )
        }

        var states = cleanUntitledStates()
        states[.left] = untitledState(side: .left, dirty: true)
        let left = destination(side: .left)
        assertPlanningError(.duplicateDestination(.left)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(states: states, action: .saveAll(destinations: [left, left]))
            )
        }
    }

    func testDestinationCanonicalIdentityAndExistingRevisionValidation() {
        let middle = untitledState(side: .middle, dirty: true)
        let parent = parentIdentity(name: "dest")
        let canonicalURL = fileURL(parentName: "dest", fileName: "middle.txt")

        let directoryURL = URL(fileURLWithPath: "/tmp/macmerge-three-pane-save/dest/", isDirectory: true)
        assertPlanningError(.invalidFileURL(directoryURL.absoluteString)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    middle: middle,
                    action: .saveMiddle(
                        destination: ThreePaneSaveDestination(
                            side: .middle,
                            identity: ThreePaneSaveDestinationIdentity(
                                canonicalURL: directoryURL,
                                parentIdentity: parent,
                                canonicalLeafIdentity: "middle.txt",
                                state: .vacant
                            )
                        ))
                )
            )
        }

        let wrongParent = parentIdentity(name: "other")
        assertPlanningError(.invalidDestination(.middle)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    middle: middle,
                    action: .saveMiddle(
                        destination: ThreePaneSaveDestination(
                            side: .middle,
                            identity: ThreePaneSaveDestinationIdentity(
                                canonicalURL: canonicalURL,
                                parentIdentity: wrongParent,
                                canonicalLeafIdentity: "middle.txt",
                                state: .vacant
                            )
                        ))
                )
            )
        }

        let wrongRevision = fileRevision(
            url: fileURL(parentName: "dest", fileName: "other.txt"),
            fileID: 7_001
        )
        assertPlanningError(.invalidDestination(.middle)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    middle: middle,
                    action: .saveMiddle(
                        destination: ThreePaneSaveDestination(
                            side: .middle,
                            identity: ThreePaneSaveDestinationIdentity(
                                canonicalURL: canonicalURL,
                                parentIdentity: parent,
                                canonicalLeafIdentity: "middle.txt",
                                state: .existing(wrongRevision)
                            )
                        ))
                )
            )
        }

        for kind in [ThreePaneSaveResolvedPathKind.symbolicLink, .finderAlias] {
            assertPlanningError(.aliasedPath(side: .middle, kind: kind)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(
                        middle: middle,
                        action: .saveMiddle(destination: self.destination(side: .middle, resolvedPathKind: kind))
                    )
                )
            }
        }
    }

    func testLoadedPaneAliasesAreRejectedForEverySideAndAliasKind() {
        for side in ThreePaneSaveSide.allCases {
            for kind in [ThreePaneSaveResolvedPathKind.symbolicLink, .finderAlias] {
                var states = normalLoadedPanes()
                states[side] = loadedState(side: side, dirty: true, resolvedPathKind: kind)

                assertPlanningError(.aliasedPath(side: side, kind: kind)) {
                    try ThreePaneSavePlanner.plan(self.makeRequest(states: states, action: .saveAll()))
                }
            }
        }
    }

    func testDestinationAliasesAreRejectedForEverySideAndAliasKind() {
        for side in ThreePaneSaveSide.allCases {
            for kind in [ThreePaneSaveResolvedPathKind.symbolicLink, .finderAlias] {
                var states = cleanUntitledStates()
                states[side] = untitledState(side: side, dirty: true)
                let aliased = destination(side: side, resolvedPathKind: kind)

                assertPlanningError(.aliasedPath(side: side, kind: kind)) {
                    try ThreePaneSavePlanner.plan(
                        self.makeRequest(states: states, action: .saveAll(destinations: [aliased]))
                    )
                }
            }
        }
    }

    func testCanonicalPaneResourceAndSlotCollisionsCoverEveryPair() {
        for (first, second) in sidePairs {
            let sharedFileID = fileID(for: first)
            var resourceCollision = normalLoadedPanes()
            resourceCollision[second] = loadedState(
                side: second,
                dirty: true,
                fileID: sharedFileID
            )
            assertPlanningError(.paneFileCollision(first: first, second: second)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(states: resourceCollision, action: .saveAll())
                )
            }

            var slotCollision = normalLoadedPanes()
            slotCollision[second] = loadedState(
                side: second,
                dirty: true,
                canonicalLeafIdentity: fileName(for: first)
            )
            assertPlanningError(.paneFileCollision(first: first, second: second)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(states: slotCollision, action: .saveAll())
                )
            }
        }
    }

    func testSaveAsDestinationCannotAliasAnyLoadedPane() {
        let states = normalLoadedPanes()
        for paneSide in ThreePaneSaveSide.allCases {
            guard case .loaded(_, let binding) = states[paneSide] else {
                return XCTFail("Expected loaded fixture")
            }
            let aliased = ThreePaneSaveDestination(
                side: .middle,
                identity: destinationIdentity(for: binding)
            )

            assertPlanningError(.destinationAliasesPane(destination: .middle, pane: paneSide)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(
                        states: states,
                        action: .saveAsMiddle(destination: aliased)
                    )
                )
            }
        }
    }

    func testCanonicalDestinationResourceAndSlotCollisionsCoverEveryPair() {
        let states = dirtyUntitledStates()
        for (first, second) in sidePairs {
            var slotDestinations = ThreePaneSaveSide.allCases.map { destination(side: $0) }
            let firstIndex = first.index
            let secondIndex = second.index
            slotDestinations[secondIndex] = destination(
                side: second,
                fileName: fileName(for: second),
                canonicalLeafIdentity: slotDestinations[firstIndex].identity.canonicalLeafIdentity
            )
            assertPlanningError(.destinationCollision(first: first, second: second)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(states: states, action: .saveAll(destinations: slotDestinations))
                )
            }

            let sharedFileID = UInt64(9_000 + firstIndex)
            let resourceDestinations = ThreePaneSaveSide.allCases.map { side in
                let url = fileURL(parentName: "dest", fileName: fileName(for: side))
                let revision = fileRevision(
                    url: url,
                    fileID: side == first || side == second ? sharedFileID : UInt64(9_100 + side.index)
                )
                return destination(side: side, state: .existing(revision))
            }
            assertPlanningError(.destinationCollision(first: first, second: second)) {
                try ThreePaneSavePlanner.plan(
                    self.makeRequest(states: states, action: .saveAll(destinations: resourceDestinations))
                )
            }
        }
    }

    func testCleanLoadedContentMustMatchPersistedRevisionButDirtyContentMayDiffer() throws {
        guard case .loaded(_, let binding) = loadedState(side: .middle, dirty: false) else {
            return XCTFail("Expected loaded fixture")
        }
        let mismatchedClean = ThreePaneSavePaneState.loaded(
            content: content(side: .middle, dirty: false, byteCount: binding.revision.byteCount + 1),
            file: binding
        )
        assertPlanningError(.invalidContentRevision(.middle)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(middle: mismatchedClean, action: .saveAsMiddle(destination: self.destination(side: .middle)))
            )
        }

        let mismatchedDirty = ThreePaneSavePaneState.loaded(
            content: content(
                side: .middle,
                dirty: true,
                byteCount: binding.revision.byteCount + 1,
                hashByte: 0xEE
            ),
            file: binding
        )
        let plan = try ThreePaneSavePlanner.plan(
            makeRequest(middle: mismatchedDirty, action: .saveMiddle())
        )
        XCTAssertEqual(plan.operations[0].source, mismatchedDirty.content)
        XCTAssertEqual(plan.operations[0].sourceFile?.revision, binding.revision)
    }

    func testFullExistingRevisionIsPreservedAsDestinationCAS() throws {
        let url = fileURL(parentName: "dest", fileName: "middle.txt")
        let exact = fileRevision(
            url: url,
            fileID: 42_424,
            generation: 77,
            byteCount: 1_234,
            metadataByteCount: 321,
            contentHashByte: 0xA1,
            metadataHashByte: 0xB2,
            modificationTimeSeconds: 111,
            modificationTimeNanoseconds: 222,
            statusChangeTimeSeconds: 333,
            statusChangeTimeNanoseconds: 444
        )
        let distinctRevisions = [
            fileRevision(
                url: url,
                volumeID: 2,
                fileID: 42_424,
                generation: 77,
                byteCount: 1_234,
                metadataByteCount: 321,
                contentHashByte: 0xA1,
                metadataHashByte: 0xB2,
                modificationTimeSeconds: 111,
                modificationTimeNanoseconds: 222,
                statusChangeTimeSeconds: 333,
                statusChangeTimeNanoseconds: 444
            ),
            fileRevision(
                url: url,
                fileID: 42_425,
                generation: 77,
                byteCount: 1_234,
                metadataByteCount: 321,
                contentHashByte: 0xA1,
                metadataHashByte: 0xB2,
                modificationTimeSeconds: 111,
                modificationTimeNanoseconds: 222,
                statusChangeTimeSeconds: 333,
                statusChangeTimeNanoseconds: 444
            ),
            fileRevision(
                url: url,
                fileID: 42_424,
                generation: 78,
                byteCount: 1_234,
                metadataByteCount: 321,
                contentHashByte: 0xA1,
                metadataHashByte: 0xB2,
                modificationTimeSeconds: 111,
                modificationTimeNanoseconds: 222,
                statusChangeTimeSeconds: 333,
                statusChangeTimeNanoseconds: 444
            )
        ]
        let plan = try ThreePaneSavePlanner.plan(
            makeRequest(
                middle: untitledState(side: .middle, dirty: true),
                action: .saveMiddle(destination: destination(side: .middle, state: .existing(exact)))
            )
        )

        XCTAssertEqual(plan.operations[0].destination.state, .existing(exact))
        for distinct in distinctRevisions {
            XCTAssertEqual(distinct.identity.canonicalURL, exact.identity.canonicalURL)
            XCTAssertNotEqual(exact, distinct)
            XCTAssertNotEqual(plan.operations[0].destination.state, .existing(distinct))
        }
        XCTAssertEqual(
            plan.operations[0].executorContract.destinationCAS,
            .descriptorRelativeExactParentAndVacancyOrFullRevisionCompareAndSwap
        )
    }

    func testPathLimitsCountDecodedUTF8BytesAtExactBoundary() throws {
        let decodedURL = URL(fileURLWithPath: "/t/é", isDirectory: false)
        let parent = canonicalIdentity(
            url: URL(fileURLWithPath: "/t", isDirectory: true),
            kind: .directory,
            fileID: 71
        )
        let destination = ThreePaneSaveDestination(
            side: .middle,
            identity: ThreePaneSaveDestinationIdentity(
                canonicalURL: decodedURL,
                parentIdentity: parent,
                canonicalLeafIdentity: "é",
                state: .vacant
            )
        )
        let decodedByteCount = decodedURL.path(percentEncoded: false).utf8.count
        let parentByteCount = parent.canonicalURL.path(percentEncoded: false).utf8.count
        let totalDecodedByteCount = decodedByteCount + parentByteCount
        XCTAssertGreaterThan(decodedURL.path(percentEncoded: true).utf8.count, decodedByteCount)

        let exactLimits = try planningLimits(
            maximumPathUTF8Bytes: decodedByteCount,
            maximumTotalPathUTF8Bytes: totalDecodedByteCount
        )
        let exact = try ThreePaneSavePlanner.plan(
            makeRequest(
                left: untitledState(side: .left, dirty: false, byteCount: 0),
                middle: untitledState(side: .middle, dirty: true),
                right: untitledState(side: .right, dirty: false, byteCount: 0),
                action: .saveMiddle(destination: destination),
                limits: exactLimits
            )
        )
        XCTAssertEqual(exact.operations[0].destination.canonicalURL, decodedURL)

        let shortLimit = try planningLimits(
            maximumPathUTF8Bytes: decodedByteCount - 1,
            maximumTotalPathUTF8Bytes: totalDecodedByteCount
        )
        assertPlanningError(.pathTooLarge(maximumBytes: decodedByteCount - 1)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    left: self.untitledState(side: .left, dirty: false, byteCount: 0),
                    middle: self.untitledState(side: .middle, dirty: true),
                    right: self.untitledState(side: .right, dirty: false, byteCount: 0),
                    action: .saveMiddle(destination: destination),
                    limits: shortLimit
                )
            )
        }

        let aggregateLimit = try planningLimits(
            maximumPathUTF8Bytes: decodedByteCount,
            maximumTotalPathUTF8Bytes: totalDecodedByteCount - 1
        )
        assertPlanningError(.totalPathsTooLarge(maximumBytes: totalDecodedByteCount - 1)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    left: self.untitledState(side: .left, dirty: false, byteCount: 0),
                    middle: self.untitledState(side: .middle, dirty: true),
                    right: self.untitledState(side: .right, dirty: false, byteCount: 0),
                    action: .saveMiddle(destination: destination),
                    limits: aggregateLimit
                )
            )
        }
    }

    func testBOMMinimumsUTF16ParityAndAllLegacyEncodingRejections() throws {
        for (byteCount, isValid) in [(UInt64(2), false), (3, true)] {
            try assertEncodingValidity(
                encoding: .utf8,
                hasBOM: true,
                byteCount: byteCount,
                isValid: isValid
            )
        }

        for encoding in [ThreePaneSaveTextEncoding.utf16LittleEndian, .utf16BigEndian] {
            for hasBOM in [false, true] {
                for (byteCount, isValid) in [(UInt64(0), true), (1, false), (2, true), (3, false), (4, true)] {
                    try assertEncodingValidity(
                        encoding: encoding,
                        hasBOM: hasBOM,
                        byteCount: byteCount,
                        isValid: isValid && (!hasBOM || byteCount >= 2)
                    )
                }
            }
        }

        let legacyEncodings: [ThreePaneSaveTextEncoding] = [
            .shiftJIS, .japaneseEUC, .iso2022JP,
            .windows1250, .windows1251, .windows1252,
            .windows1253, .windows1254, .windows1255
        ]
        for encoding in legacyEncodings {
            try assertEncodingValidity(
                encoding: encoding,
                hasBOM: false,
                byteCount: 1,
                isValid: true
            )
            try assertEncodingValidity(
                encoding: encoding,
                hasBOM: true,
                byteCount: 3,
                isValid: false
            )
        }
    }

    func testExecutorContractRequiresPreflightPublicationCancellationAndPaneFreshness() throws {
        let plan = try ThreePaneSavePlanner.plan(
            makeRequest(
                middle: untitledState(side: .middle, dirty: true),
                action: .saveMiddle(destination: destination(side: .middle))
            )
        )
        let contract = try XCTUnwrap(plan.operations.first).executorContract

        XCTAssertEqual(contract.sourceRevision, .exactOwnerRevisionLeaseHeldThroughPublication)
        XCTAssertEqual(
            contract.destinationCAS,
            .descriptorRelativeExactParentAndVacancyOrFullRevisionCompareAndSwap
        )
        XCTAssertEqual(contract.pathResolution, .canonicalDescriptorRelativeNoFollowWithAliasesRejected)
        XCTAssertEqual(contract.publication, .privateStageSyncAtomicPublishVerifyAndSyncParent)
        XCTAssertEqual(
            contract.cancellation,
            .cancellableBeforePublicationCommittedOrUncertainAfterPublicationStarts
        )
        XCTAssertEqual(
            contract.paneUpdate,
            .consumePlanIDOnceAndApplyOnlyIfExactOwnerRevisionAndBindingRemainCurrent
        )
        XCTAssertEqual(contract.batchPreflight, .leaseAllSourcesAndCASDestinationsBeforeFirstPublication)
        XCTAssertEqual(
            contract.batchOutcome,
            .noCommitOnPreflightFailureAndExactPerOperationOutcomesAfterPublicationStarts
        )
    }

    func testValidCommitReceiptsAreReorderedAndExposeCommittedSides() throws {
        let plan = try threeOperationPlan()
        let receipts = plan.operations.map { operation in
            ThreePaneSaveOperationReceipt(
                operation: operation,
                outcome: .committed(commitReceipt(for: operation))
            )
        }

        let execution = try plan.validate(receipts: receipts.reversed())

        XCTAssertEqual(execution.outcomes, receipts)
        XCTAssertEqual(execution.committedSides, [.left, .middle, .right])
        XCTAssertFalse(execution.hasCommitUncertainty)
    }

    func testReceiptMembershipCountAndPlanFreshnessAreValidated() throws {
        let request = makeRequest(
            middle: untitledState(side: .middle, dirty: true),
            action: .saveMiddle(destination: destination(side: .middle))
        )
        let first = try ThreePaneSavePlanner.plan(request)
        let second = try ThreePaneSavePlanner.plan(request)
        let firstOperation = try XCTUnwrap(first.operations.first)
        let secondOperation = try XCTUnwrap(second.operations.first)

        XCTAssertNotEqual(firstOperation.planID, secondOperation.planID)
        assertReceiptError(.receiptCountMismatch(expected: 1, actual: 0)) {
            try first.validate(receipts: [])
        }
        assertReceiptError(.unknownOperation(.middle)) {
            try first.validate(receipts: [
                ThreePaneSaveOperationReceipt(operation: secondOperation, outcome: .notCommitted(.cancelled))
            ])
        }

        let batch = try threeOperationPlan()
        let duplicate = ThreePaneSaveOperationReceipt(
            operation: batch.operations[0],
            outcome: .notCommitted(.publicationFailedBeforeMutation)
        )
        assertReceiptError(.duplicateOperationReceipt(.left)) {
            try batch.validate(receipts: [
                duplicate, duplicate,
                ThreePaneSaveOperationReceipt(
                    operation: batch.operations[2],
                    outcome: .notCommitted(.publicationFailedBeforeMutation)
                )
            ])
        }
    }

    func testCommittedReceiptValidatesRevisionDestinationParentPayloadAndMetadata() throws {
        let plan = try oneOperationPlan()
        let operation = try XCTUnwrap(plan.operations.first)

        let wrongParent = commitReceipt(
            for: operation,
            parent: parentIdentity(name: "wrong-receipt-parent")
        )
        assertReceiptError(.committedParentMismatch(.middle)) {
            try plan.validate(receipts: [self.receipt(operation, committed: wrongParent)])
        }

        let invalidRevisions = [
            commitReceipt(for: operation, contentHash: [0x01]),
            commitReceipt(for: operation, metadataHash: [0x02]),
            commitReceipt(for: operation, modificationTimeNanoseconds: 1_000_000_000),
            commitReceipt(for: operation, statusChangeTimeNanoseconds: 1_000_000_000),
            commitReceipt(for: operation, byteCount: plan.limits.maximumEncodedFileBytes + 1),
            commitReceipt(for: operation, metadataByteCount: plan.limits.maximumMetadataBytes + 1)
        ]
        for invalidRevision in invalidRevisions {
            assertReceiptError(.invalidCommittedRevision(.middle)) {
                try plan.validate(receipts: [self.receipt(operation, committed: invalidRevision)])
            }
        }

        let wrongURL = fileURL(parentName: "dest", fileName: "different.txt")
        let wrongDestination = commitReceipt(for: operation, destinationURL: wrongURL)
        assertReceiptError(.committedDestinationMismatch(.middle)) {
            try plan.validate(receipts: [self.receipt(operation, committed: wrongDestination)])
        }

        let payloadMismatches = [
            commitReceipt(for: operation, byteCount: operation.source.encodedByteCount + 1),
            commitReceipt(for: operation, contentHash: hash(0xFE)),
            commitReceipt(
                for: operation,
                encoding: ThreePaneSaveEncodingMetadata(
                    encoding: ThreePaneSaveTextEncoding.utf16LittleEndian,
                    hasByteOrderMark: true
                )
            ),
            commitReceipt(for: operation, paneReadOnly: !operation.preservesReadOnlyState)
        ]
        for mismatch in payloadMismatches {
            assertReceiptError(.committedPayloadMismatch(.middle)) {
                try plan.validate(receipts: [self.receipt(operation, committed: mismatch)])
            }
        }
    }

    func testBatchPreflightFailureForbidsAnyPublicationOutcome() throws {
        let plan = try threeOperationPlan()
        let preflightReasons: [ThreePaneSaveNonCommitReason] = [
            .cancelled, .sourceRevisionChanged, .destinationCompareFailed, .safetyContractUnavailable
        ]
        for reason in preflightReasons {
            let preflight = ThreePaneSaveOperationReceipt(
                operation: plan.operations[0],
                outcome: .notCommitted(reason)
            )
            let forbiddenOutcomes: [ThreePaneSaveOperationOutcome] = [
                .committed(commitReceipt(for: plan.operations[1])),
                .commitUncertain(.publicationStateUnknown),
                .notCommitted(.publicationFailedBeforeMutation)
            ]
            for forbidden in forbiddenOutcomes {
                assertReceiptError(.inconsistentBatchOutcome) {
                    try plan.validate(receipts: [
                        preflight,
                        ThreePaneSaveOperationReceipt(operation: plan.operations[1], outcome: forbidden),
                        ThreePaneSaveOperationReceipt(
                            operation: plan.operations[2],
                            outcome: .notCommitted(reason)
                        )
                    ])
                }
            }
        }
    }

    func testAllPreflightFailureReceiptSetsAreValid() throws {
        let plan = try threeOperationPlan()
        let preflightReasons: [ThreePaneSaveNonCommitReason] = [
            .cancelled, .sourceRevisionChanged, .destinationCompareFailed, .safetyContractUnavailable
        ]

        for reason in preflightReasons {
            let receipts = plan.operations.map { operation in
                ThreePaneSaveOperationReceipt(operation: operation, outcome: .notCommitted(reason))
            }
            let execution = try plan.validate(receipts: receipts.reversed())

            XCTAssertEqual(execution.outcomes, receipts)
            XCTAssertTrue(execution.committedSides.isEmpty)
            XCTAssertFalse(execution.hasCommitUncertainty)
        }
    }

    func testPublicationOutcomesRemainExactAfterSuccessfulPreflight() throws {
        let plan = try threeOperationPlan()
        let receipts = [
            ThreePaneSaveOperationReceipt(
                operation: plan.operations[0],
                outcome: .committed(commitReceipt(for: plan.operations[0]))
            ),
            ThreePaneSaveOperationReceipt(
                operation: plan.operations[1],
                outcome: .notCommitted(.publicationFailedBeforeMutation)
            ),
            ThreePaneSaveOperationReceipt(
                operation: plan.operations[2],
                outcome: .commitUncertain(.durabilityUnverified)
            )
        ]

        let execution = try plan.validate(receipts: receipts)

        XCTAssertEqual(execution.outcomes, receipts)
        XCTAssertEqual(execution.committedSides, [.left])
        XCTAssertTrue(execution.hasCommitUncertainty)
    }

    func testPlanningLimitsRejectInvalidValuesAndAcceptHardBoundaries() throws {
        assertPlanningError(.invalidLimit(.operations)) {
            try ThreePaneSavePlanningLimits(maximumOperations: 0)
        }
        assertPlanningError(.invalidLimit(.operations)) {
            try ThreePaneSavePlanningLimits(
                maximumOperations: ThreePaneSavePlanningLimits.hardMaximumOperations + 1
            )
        }
        assertPlanningError(.invalidLimit(.pathUTF8Bytes)) {
            try ThreePaneSavePlanningLimits(maximumPathUTF8Bytes: 0)
        }
        assertPlanningError(.invalidLimit(.pathUTF8Bytes)) {
            try ThreePaneSavePlanningLimits(
                maximumPathUTF8Bytes: ThreePaneSavePlanningLimits.hardMaximumPathUTF8Bytes + 1,
                maximumTotalPathUTF8Bytes: ThreePaneSavePlanningLimits.hardMaximumTotalPathUTF8Bytes
            )
        }
        assertPlanningError(.invalidLimit(.totalPathUTF8Bytes)) {
            try ThreePaneSavePlanningLimits(maximumPathUTF8Bytes: 10, maximumTotalPathUTF8Bytes: 9)
        }
        assertPlanningError(.invalidLimit(.totalPathUTF8Bytes)) {
            try ThreePaneSavePlanningLimits(
                maximumTotalPathUTF8Bytes: ThreePaneSavePlanningLimits.hardMaximumTotalPathUTF8Bytes + 1
            )
        }
        assertPlanningError(.invalidLimit(.canonicalLeafIdentityUTF8Bytes)) {
            try ThreePaneSavePlanningLimits(maximumCanonicalLeafIdentityUTF8Bytes: 0)
        }
        assertPlanningError(.invalidLimit(.canonicalLeafIdentityUTF8Bytes)) {
            try ThreePaneSavePlanningLimits(
                maximumCanonicalLeafIdentityUTF8Bytes:
                    ThreePaneSavePlanningLimits.hardMaximumCanonicalLeafIdentityUTF8Bytes + 1
            )
        }
        assertPlanningError(.invalidLimit(.encodedFileBytes)) {
            try ThreePaneSavePlanningLimits(maximumEncodedFileBytes: 0)
        }
        assertPlanningError(.invalidLimit(.encodedFileBytes)) {
            try ThreePaneSavePlanningLimits(
                maximumEncodedFileBytes: ThreePaneSavePlanningLimits.hardMaximumEncodedFileBytes + 1
            )
        }
        assertPlanningError(.invalidLimit(.metadataBytes)) {
            try ThreePaneSavePlanningLimits(
                maximumMetadataBytes: ThreePaneSavePlanningLimits.hardMaximumMetadataBytes + 1
            )
        }
        assertPlanningError(.invalidLimit(.workUnits)) {
            try ThreePaneSavePlanningLimits(maximumWorkUnits: 0)
        }
        assertPlanningError(.invalidLimit(.workUnits)) {
            try ThreePaneSavePlanningLimits(
                maximumWorkUnits: ThreePaneSavePlanningLimits.hardMaximumWorkUnits + 1
            )
        }

        let hard = try ThreePaneSavePlanningLimits(
            maximumOperations: ThreePaneSavePlanningLimits.hardMaximumOperations,
            maximumPathUTF8Bytes: ThreePaneSavePlanningLimits.hardMaximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: ThreePaneSavePlanningLimits.hardMaximumTotalPathUTF8Bytes,
            maximumCanonicalLeafIdentityUTF8Bytes:
                ThreePaneSavePlanningLimits.hardMaximumCanonicalLeafIdentityUTF8Bytes,
            maximumEncodedFileBytes: ThreePaneSavePlanningLimits.hardMaximumEncodedFileBytes,
            maximumMetadataBytes: ThreePaneSavePlanningLimits.hardMaximumMetadataBytes,
            maximumWorkUnits: ThreePaneSavePlanningLimits.hardMaximumWorkUnits
        )
        XCTAssertEqual(hard.maximumOperations, ThreePaneSavePlanningLimits.hardMaximumOperations)
        XCTAssertEqual(hard.maximumWorkUnits, ThreePaneSavePlanningLimits.hardMaximumWorkUnits)
    }

    func testOperationalSizeMetadataLeafAndCountLimits() throws {
        let twoOperationStates: [ThreePaneSaveSide: ThreePaneSavePaneState] = [
            .left: untitledState(side: .left, dirty: true),
            .middle: untitledState(side: .middle, dirty: true),
            .right: untitledState(side: .right, dirty: false)
        ]
        let exactOperationLimit = try planningLimits(maximumOperations: 2)
        let exactOperationPlan = try ThreePaneSavePlanner.plan(
            makeRequest(
                states: twoOperationStates,
                action: .saveAll(destinations: [destination(side: .left), destination(side: .middle)]),
                limits: exactOperationLimit
            )
        )
        XCTAssertEqual(exactOperationPlan.operations.count, 2)

        let oneOperation = try planningLimits(maximumOperations: 1)
        assertPlanningError(.tooManyOperations(maximum: 1)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    states: twoOperationStates,
                    action: .saveAll(destinations: [self.destination(side: .left), self.destination(side: .middle)]),
                    limits: oneOperation
                )
            )
        }

        let fourBytes = try planningLimits(maximumEncodedFileBytes: 4)
        let exactEncodedFilePlan = try ThreePaneSavePlanner.plan(
            makeRequest(
                left: untitledState(side: .left, dirty: false, byteCount: 0),
                middle: untitledState(side: .middle, dirty: true, byteCount: 4),
                right: untitledState(side: .right, dirty: false, byteCount: 0),
                action: .saveMiddle(destination: destination(side: .middle)),
                limits: fourBytes
            )
        )
        XCTAssertEqual(exactEncodedFilePlan.operations[0].source.encodedByteCount, 4)

        let threeBytes = try planningLimits(maximumEncodedFileBytes: 3)
        assertPlanningError(.encodedFileTooLarge(side: .middle, maximumBytes: 3)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    left: self.untitledState(side: .left, dirty: false, byteCount: 0),
                    middle: self.untitledState(side: .middle, dirty: true, byteCount: 4),
                    right: self.untitledState(side: .right, dirty: false, byteCount: 0),
                    action: .saveMiddle(destination: self.destination(side: .middle)),
                    limits: threeBytes
                )
            )
        }

        let twoMetadataBytes = try planningLimits(maximumMetadataBytes: 2)
        let exactMetadataPlan = try ThreePaneSavePlanner.plan(
            makeRequest(
                left: untitledState(side: .left, dirty: false),
                middle: loadedState(side: .middle, dirty: true, metadataByteCount: 2),
                right: untitledState(side: .right, dirty: false),
                action: .saveMiddle(),
                limits: twoMetadataBytes
            )
        )
        XCTAssertEqual(exactMetadataPlan.operations[0].sourceFile?.revision.metadataByteCount, 2)

        let oneMetadataByte = try planningLimits(maximumMetadataBytes: 1)
        assertPlanningError(.metadataTooLarge(side: .middle, maximumBytes: 1)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    left: self.untitledState(side: .left, dirty: false),
                    middle: self.loadedState(side: .middle, dirty: true, metadataByteCount: 2),
                    right: self.untitledState(side: .right, dirty: false),
                    action: .saveMiddle(),
                    limits: oneMetadataByte
                )
            )
        }

        let exactLeafByteCount = "é".utf8.count
        let exactLeafLimit = try planningLimits(
            maximumCanonicalLeafIdentityUTF8Bytes: exactLeafByteCount
        )
        let exactLeafPlan = try ThreePaneSavePlanner.plan(
            makeRequest(
                left: untitledState(side: .left, dirty: false),
                middle: untitledState(side: .middle, dirty: true),
                right: untitledState(side: .right, dirty: false),
                action: .saveMiddle(
                    destination: destination(
                        side: .middle,
                        fileName: "é",
                        canonicalLeafIdentity: "é"
                    )),
                limits: exactLeafLimit
            )
        )
        XCTAssertEqual(exactLeafPlan.operations[0].destination.canonicalLeafIdentity, "é")

        let oneLeafByte = try planningLimits(maximumCanonicalLeafIdentityUTF8Bytes: 1)
        assertPlanningError(.invalidCanonicalLeafIdentity(.middle)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    left: self.untitledState(side: .left, dirty: false),
                    middle: self.untitledState(side: .middle, dirty: true),
                    right: self.untitledState(side: .right, dirty: false),
                    action: .saveMiddle(
                        destination: self.destination(
                            side: .middle,
                            fileName: "é",
                            canonicalLeafIdentity: "é"
                        )),
                    limits: oneLeafByte
                )
            )
        }
    }

    func testWorkLimitAndCancellationCoverEveryBoundary() throws {
        let request = makeRequest(
            states: dirtyUntitledStates(),
            action: .saveAll(destinations: ThreePaneSaveSide.allCases.map { destination(side: $0) })
        )
        let baseline = try ThreePaneSavePlanner.plan(request)
        XCTAssertEqual(baseline.estimatedWorkUnits, 21)

        let exactLimits = try planningLimits(maximumWorkUnits: baseline.estimatedWorkUnits)
        let exact = try ThreePaneSavePlanner.plan(
            makeRequest(
                states: dirtyUntitledStates(),
                action: .saveAll(destinations: ThreePaneSaveSide.allCases.map { destination(side: $0) }),
                limits: exactLimits
            )
        )
        XCTAssertEqual(exact.estimatedWorkUnits, baseline.estimatedWorkUnits)

        let shortLimits = try planningLimits(maximumWorkUnits: baseline.estimatedWorkUnits - 1)
        assertPlanningError(.workLimitExceeded(maximumUnits: baseline.estimatedWorkUnits - 1)) {
            try ThreePaneSavePlanner.plan(
                self.makeRequest(
                    states: self.dirtyUntitledStates(),
                    action: .saveAll(destinations: ThreePaneSaveSide.allCases.map { self.destination(side: $0) }),
                    limits: shortLimits
                )
            )
        }

        let expectedChecks = Int(baseline.estimatedWorkUnits) + 2
        for throwOnCheck in 1...expectedChecks {
            let probe = SaveCancellationProbe(throwOnCheck: throwOnCheck)
            assertPlanningError(.cancelled) {
                try ThreePaneSavePlanner.plan(request, cancellationCheck: { try probe.check() })
            }
            XCTAssertEqual(probe.count, throwOnCheck)
        }

        let nonCancelling = SaveCancellationProbe(throwOnCheck: expectedChecks + 1)
        let completed = try ThreePaneSavePlanner.plan(
            request,
            cancellationCheck: { try nonCancelling.check() }
        )
        XCTAssertEqual(completed.estimatedWorkUnits, baseline.estimatedWorkUnits)
        XCTAssertEqual(nonCancelling.count, expectedChecks)
    }

    func testPlanningIsDeterministicExceptFreshPlanID() throws {
        let states = dirtyUntitledStates()
        let destinations = ThreePaneSaveSide.allCases.map { destination(side: $0) }
        let forward = ThreePaneSaveRequest(
            panes: ThreePaneSaveSide.allCases.map { ThreePaneSavePane(side: $0, state: states[$0]!) },
            action: .saveAll(destinations: destinations)
        )
        let reverse = ThreePaneSaveRequest(
            panes: ThreePaneSaveSide.allCases.reversed().map { ThreePaneSavePane(side: $0, state: states[$0]!) },
            action: .saveAll(destinations: destinations.reversed())
        )

        let first = try ThreePaneSavePlanner.plan(forward)
        let second = try ThreePaneSavePlanner.plan(reverse)

        XCTAssertEqual(first.operations.map(\.side), [.left, .middle, .right])
        XCTAssertEqual(second.operations.map(\.side), [.left, .middle, .right])
        XCTAssertEqual(first.estimatedWorkUnits, second.estimatedWorkUnits)
        XCTAssertEqual(first.limits, second.limits)
        XCTAssertEqual(Set(first.operations.map(\.planID)).count, 1)
        XCTAssertEqual(Set(second.operations.map(\.planID)).count, 1)
        XCTAssertNotEqual(first.operations[0].planID, second.operations[0].planID)
        for (lhs, rhs) in zip(first.operations, second.operations) {
            XCTAssertEqual(lhs.side, rhs.side)
            XCTAssertEqual(lhs.kind, rhs.kind)
            XCTAssertEqual(lhs.source, rhs.source)
            XCTAssertEqual(lhs.sourceFile, rhs.sourceFile)
            XCTAssertEqual(lhs.destination, rhs.destination)
            XCTAssertEqual(lhs.preservesEncoding, rhs.preservesEncoding)
            XCTAssertEqual(lhs.preservesReadOnlyState, rhs.preservesReadOnlyState)
            XCTAssertEqual(lhs.executorContract, rhs.executorContract)
        }
    }

    private var sidePairs: [(ThreePaneSaveSide, ThreePaneSaveSide)] {
        [(.left, .middle), (.left, .right), (.middle, .right)]
    }

    private func makeRequest(
        left: ThreePaneSavePaneState? = nil,
        middle: ThreePaneSavePaneState? = nil,
        right: ThreePaneSavePaneState? = nil,
        action: ThreePaneSaveAction,
        limits: ThreePaneSavePlanningLimits = .default
    ) -> ThreePaneSaveRequest {
        ThreePaneSaveRequest(
            left: left ?? loadedState(side: .left, dirty: false),
            middle: middle ?? loadedState(side: .middle, dirty: true),
            right: right ?? loadedState(side: .right, dirty: false),
            action: action,
            limits: limits
        )
    }

    private func makeRequest(
        states: [ThreePaneSaveSide: ThreePaneSavePaneState],
        action: ThreePaneSaveAction,
        limits: ThreePaneSavePlanningLimits = .default
    ) -> ThreePaneSaveRequest {
        ThreePaneSaveRequest(
            panes: ThreePaneSaveSide.allCases.map { side in
                ThreePaneSavePane(side: side, state: states[side]!)
            },
            action: action,
            limits: limits
        )
    }

    private func normalLoadedPanes() -> [ThreePaneSaveSide: ThreePaneSavePaneState] {
        Dictionary(
            uniqueKeysWithValues: ThreePaneSaveSide.allCases.map { side in
                (side, loadedState(side: side, dirty: true))
            })
    }

    private func dirtyUntitledStates() -> [ThreePaneSaveSide: ThreePaneSavePaneState] {
        Dictionary(
            uniqueKeysWithValues: ThreePaneSaveSide.allCases.map { side in
                (side, untitledState(side: side, dirty: true))
            })
    }

    private func cleanUntitledStates() -> [ThreePaneSaveSide: ThreePaneSavePaneState] {
        Dictionary(
            uniqueKeysWithValues: ThreePaneSaveSide.allCases.map { side in
                (side, untitledState(side: side, dirty: false))
            })
    }

    private func content(
        side: ThreePaneSaveSide,
        dirty: Bool,
        readOnly: Bool = false,
        byteCount: UInt64 = 4,
        hashByte: UInt8? = nil,
        encoding: ThreePaneSaveTextEncoding = .utf8,
        hasBOM: Bool = false
    ) -> ThreePaneSaveContentRevision {
        ThreePaneSaveContentRevision(
            documentID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 100 + side.index))!,
            revision: UInt64(1_000 + side.index),
            isDirty: dirty,
            isReadOnly: readOnly,
            encodedByteCount: byteCount,
            encodedContentSHA256: hash(hashByte ?? (dirty ? UInt8(0xD0 + side.index) : fileHashByte(for: side))),
            encoding: ThreePaneSaveEncodingMetadata(encoding: encoding, hasByteOrderMark: hasBOM)
        )
    }

    private func untitledState(
        side: ThreePaneSaveSide,
        dirty: Bool,
        readOnly: Bool = false,
        byteCount: UInt64 = 4,
        encoding: ThreePaneSaveTextEncoding = .utf8,
        hasBOM: Bool = false
    ) -> ThreePaneSavePaneState {
        .untitled(
            content(
                side: side,
                dirty: dirty,
                readOnly: readOnly,
                byteCount: byteCount,
                encoding: encoding,
                hasBOM: hasBOM
            ))
    }

    private func loadedState(
        side: ThreePaneSaveSide,
        dirty: Bool,
        readOnly: Bool = false,
        fileID: UInt64? = nil,
        canonicalLeafIdentity: String? = nil,
        resolvedPathKind: ThreePaneSaveResolvedPathKind = .direct,
        metadataByteCount: UInt64 = 2
    ) -> ThreePaneSavePaneState {
        let binding = fileBinding(
            side: side,
            fileID: fileID,
            canonicalLeafIdentity: canonicalLeafIdentity,
            resolvedPathKind: resolvedPathKind,
            metadataByteCount: metadataByteCount
        )
        return .loaded(
            content: content(
                side: side,
                dirty: dirty,
                readOnly: readOnly,
                byteCount: binding.revision.byteCount
            ),
            file: binding
        )
    }

    private func fileBinding(
        side: ThreePaneSaveSide,
        fileID: UInt64? = nil,
        canonicalLeafIdentity: String? = nil,
        resolvedPathKind: ThreePaneSaveResolvedPathKind = .direct,
        metadataByteCount: UInt64 = 2
    ) -> ThreePaneSaveFileBinding {
        let fileName = fileName(for: side)
        return ThreePaneSaveFileBinding(
            revision: fileRevision(
                url: fileURL(parentName: "source", fileName: fileName),
                fileID: fileID ?? self.fileID(for: side),
                byteCount: 4,
                metadataByteCount: metadataByteCount,
                contentHashByte: fileHashByte(for: side)
            ),
            parentIdentity: parentIdentity(name: "source"),
            canonicalLeafIdentity: canonicalLeafIdentity ?? fileName,
            resolvedPathKind: resolvedPathKind
        )
    }

    private func destination(
        side: ThreePaneSaveSide,
        parentName: String = "dest",
        fileName: String? = nil,
        canonicalLeafIdentity: String? = nil,
        resolvedPathKind: ThreePaneSaveResolvedPathKind = .direct,
        state: ThreePaneSaveDestinationState = .vacant
    ) -> ThreePaneSaveDestination {
        let name = fileName ?? self.fileName(for: side)
        return ThreePaneSaveDestination(
            side: side,
            identity: ThreePaneSaveDestinationIdentity(
                canonicalURL: fileURL(parentName: parentName, fileName: name),
                parentIdentity: parentIdentity(name: parentName),
                canonicalLeafIdentity: canonicalLeafIdentity ?? name,
                resolvedPathKind: resolvedPathKind,
                state: state
            )
        )
    }

    private func destinationIdentity(
        for binding: ThreePaneSaveFileBinding
    ) -> ThreePaneSaveDestinationIdentity {
        ThreePaneSaveDestinationIdentity(
            canonicalURL: binding.revision.identity.canonicalURL,
            parentIdentity: binding.parentIdentity,
            canonicalLeafIdentity: binding.canonicalLeafIdentity,
            state: .existing(binding.revision)
        )
    }

    private func fileRevision(
        url: URL,
        volumeID: UInt64 = 1,
        fileID: UInt64,
        generation: UInt32 = 1,
        byteCount: UInt64 = 4,
        metadataByteCount: UInt64 = 2,
        contentHashByte: UInt8 = 0x44,
        metadataHashByte: UInt8 = 0x55,
        modificationTimeSeconds: Int64 = 10,
        modificationTimeNanoseconds: UInt32 = 20,
        statusChangeTimeSeconds: Int64 = 30,
        statusChangeTimeNanoseconds: UInt32 = 40
    ) -> ThreePaneSaveFileRevision {
        ThreePaneSaveFileRevision(
            identity: canonicalIdentity(
                url: url,
                kind: .regularFile,
                volumeID: volumeID,
                fileID: fileID,
                generation: generation
            ),
            byteCount: byteCount,
            metadataByteCount: metadataByteCount,
            modificationTimeSeconds: modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds,
            contentSHA256: hash(contentHashByte),
            metadataSHA256: hash(metadataHashByte)
        )
    }

    private func parentIdentity(name: String) -> ThreePaneSaveCanonicalFileIdentity {
        canonicalIdentity(
            url: URL(
                fileURLWithPath: "/tmp/macmerge-three-pane-save/\(name)",
                isDirectory: true
            ),
            kind: .directory,
            fileID: UInt64(500 + stableByteSum(name))
        )
    }

    private func canonicalIdentity(
        url: URL,
        kind: ThreePaneSaveCanonicalItemKind,
        volumeID: UInt64 = 1,
        fileID: UInt64,
        generation: UInt32 = 1
    ) -> ThreePaneSaveCanonicalFileIdentity {
        ThreePaneSaveCanonicalFileIdentity(
            canonicalURL: url,
            kind: kind,
            volumeID: volumeID,
            fileID: fileID,
            generation: generation
        )
    }

    private func fileURL(parentName: String, fileName: String) -> URL {
        URL(
            fileURLWithPath: "/tmp/macmerge-three-pane-save/\(parentName)/\(fileName)",
            isDirectory: false
        )
    }

    private func fileName(for side: ThreePaneSaveSide) -> String {
        "\(side.rawValue).txt"
    }

    private func fileID(for side: ThreePaneSaveSide) -> UInt64 {
        UInt64(1_000 + side.index)
    }

    private func fileHashByte(for side: ThreePaneSaveSide) -> UInt8 {
        UInt8(0x40 + side.index)
    }

    private func hash(_ byte: UInt8) -> [UInt8] {
        [UInt8](repeating: byte, count: 32)
    }

    private func stableByteSum(_ value: String) -> Int {
        value.utf8.reduce(0) { $0 + Int($1) }
    }

    private func planningLimits(
        maximumOperations: Int = 3,
        maximumPathUTF8Bytes: Int = 16 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 128 * 1_024,
        maximumCanonicalLeafIdentityUTF8Bytes: Int = 1_024,
        maximumEncodedFileBytes: UInt64 = 64 * 1_024 * 1_024,
        maximumMetadataBytes: UInt64 = 16 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 1_024
    ) throws -> ThreePaneSavePlanningLimits {
        try ThreePaneSavePlanningLimits(
            maximumOperations: maximumOperations,
            maximumPathUTF8Bytes: maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: maximumTotalPathUTF8Bytes,
            maximumCanonicalLeafIdentityUTF8Bytes: maximumCanonicalLeafIdentityUTF8Bytes,
            maximumEncodedFileBytes: maximumEncodedFileBytes,
            maximumMetadataBytes: maximumMetadataBytes,
            maximumWorkUnits: maximumWorkUnits
        )
    }

    private func oneOperationPlan() throws -> ThreePaneSavePlan {
        try ThreePaneSavePlanner.plan(
            makeRequest(
                middle: untitledState(side: .middle, dirty: true),
                action: .saveMiddle(destination: destination(side: .middle))
            )
        )
    }

    private func threeOperationPlan() throws -> ThreePaneSavePlan {
        try ThreePaneSavePlanner.plan(
            makeRequest(
                states: dirtyUntitledStates(),
                action: .saveAll(destinations: ThreePaneSaveSide.allCases.map { destination(side: $0) })
            )
        )
    }

    private func commitReceipt(
        for operation: ThreePaneSaveOperation,
        parent: ThreePaneSaveCanonicalFileIdentity? = nil,
        destinationURL: URL? = nil,
        byteCount: UInt64? = nil,
        metadataByteCount: UInt64? = nil,
        contentHash: [UInt8]? = nil,
        metadataHash: [UInt8]? = nil,
        modificationTimeNanoseconds: UInt32? = nil,
        statusChangeTimeNanoseconds: UInt32? = nil,
        encoding: ThreePaneSaveEncodingMetadata? = nil,
        paneReadOnly: Bool? = nil
    ) -> ThreePaneSaveCommitReceipt {
        let revision = ThreePaneSaveFileRevision(
            identity: canonicalIdentity(
                url: destinationURL ?? operation.destination.canonicalURL,
                kind: .regularFile,
                fileID: UInt64(20_000 + operation.side.index)
            ),
            byteCount: byteCount ?? operation.source.encodedByteCount,
            metadataByteCount: metadataByteCount ?? 0,
            modificationTimeSeconds: 100,
            modificationTimeNanoseconds: modificationTimeNanoseconds ?? 200,
            statusChangeTimeSeconds: 300,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds ?? 400,
            contentSHA256: contentHash ?? operation.source.encodedContentSHA256,
            metadataSHA256: metadataHash ?? hash(0xCC)
        )
        return ThreePaneSaveCommitReceipt(
            committedParentIdentity: parent ?? operation.destination.parentIdentity,
            committedRevision: revision,
            encoding: encoding ?? operation.preservesEncoding,
            paneReadOnly: paneReadOnly ?? operation.preservesReadOnlyState
        )
    }

    private func receipt(
        _ operation: ThreePaneSaveOperation,
        committed: ThreePaneSaveCommitReceipt
    ) -> ThreePaneSaveOperationReceipt {
        ThreePaneSaveOperationReceipt(operation: operation, outcome: .committed(committed))
    }

    private func assertEncodingValidity(
        encoding: ThreePaneSaveTextEncoding,
        hasBOM: Bool,
        byteCount: UInt64,
        isValid: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let state = untitledState(
            side: .middle,
            dirty: true,
            byteCount: byteCount,
            encoding: encoding,
            hasBOM: hasBOM
        )
        let request = makeRequest(
            left: untitledState(side: .left, dirty: false),
            middle: state,
            right: untitledState(side: .right, dirty: false),
            action: .saveMiddle(destination: destination(side: .middle))
        )
        if isValid {
            XCTAssertNoThrow(try ThreePaneSavePlanner.plan(request), file: file, line: line)
        } else {
            assertPlanningError(.invalidEncodingMetadata(.middle), file: file, line: line) {
                try ThreePaneSavePlanner.plan(request)
            }
        }
    }

    private func assertPlanningError<T>(
        _ expected: ThreePaneSavePlanningError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ThreePaneSavePlanningError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertReceiptError<T>(
        _ expected: ThreePaneSaveReceiptError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        do {
            _ = try operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ThreePaneSaveReceiptError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

extension ThreePaneSaveSide {
    fileprivate var index: Int {
        switch self {
        case .left: 0
        case .middle: 1
        case .right: 2
        }
    }
}

private final class SaveCancellationProbe: @unchecked Sendable {
    private enum ProbeError: Error {
        case cancelled
    }

    private let lock = NSLock()
    private let throwOnCheck: Int
    private var checkCount = 0

    init(throwOnCheck: Int) {
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
