import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class UnifiedOpenWorkflowTests: XCTestCase {
    typealias Workflow = UnifiedOpenWorkflow

    func testPlansTwoAndThreeWayFilesInCanonicalOrderWithReadOnlyAndAllOrigins() throws {
        let left = fileInput(.left, seed: 1, readOnly: true, origin: .browse(session: uuid(91), selectionIndex: 0))
        let middle = fileInput(.middle, seed: 2, origin: .history(entryIdentifier: "recent/2", revision: 4))
        let right = fileInput(.right, seed: 3, origin: .entered(editRevision: 7))

        let twoWay = try plan(request(sides: [right, left]))
        XCTAssertEqual(twoWay.sides.map(\.side), [.left, .right])
        XCTAssertEqual(twoWay.side(.left), left)
        XCTAssertNil(twoWay.side(.middle))
        XCTAssertEqual(twoWay.side(.right), right)
        XCTAssertFalse(twoWay.isThreeWay)
        XCTAssertEqual(twoWay.resolvedMode, .text)
        XCTAssertEqual(twoWay.authorities, [access(from: left), access(from: right)])
        XCTAssertEqual(twoWay.receipt.sourceRevisions.map(\.side), [.left, .right])
        XCTAssertEqual(twoWay.receipt.sourceRevisions.map(\.revision), [left.source.revision, right.source.revision])
        XCTAssertTrue(twoWay.side(.left)?.readOnly == true)

        let threeWay = try plan(request(sides: [right, middle, left]))
        XCTAssertEqual(threeWay.sides.map(\.side), [.left, .middle, .right])
        XCTAssertTrue(threeWay.isThreeWay)
        XCTAssertEqual(threeWay.receipt.sourceRevisions.map(\.side), [.left, .middle, .right])
    }

    func testPlansFoldersScratchpadsAndMixedFileScratchpadShapes() throws {
        let folders = try plan(
            request(
                sides: [folderInput(.right, seed: 2), folderInput(.left, seed: 1)],
                comparisonOptions: .defaults(mode: .automatic)
            )
        )
        XCTAssertEqual(folders.resolvedMode, .folder)
        XCTAssertEqual(folders.authorities.map(\.coverage), [.directoryTree, .directoryTree])
        let threeFolders = try plan(
            request(sides: [
                folderInput(.right, seed: 3),
                folderInput(.left, seed: 1),
                folderInput(.middle, seed: 2)
            ])
        )
        XCTAssertTrue(threeFolders.isThreeWay)
        XCTAssertEqual(threeFolders.sides.map(\.side), [.left, .middle, .right])
        XCTAssertEqual(threeFolders.authorities.map(\.coverage), [.directoryTree, .directoryTree, .directoryTree])

        let leftScratchpad = scratchpadInput(.left, seed: 1, text: "alpha", label: "Left text")
        let rightScratchpad = scratchpadInput(.right, seed: 2, text: "beta")
        let scratchpads = try plan(
            request(sides: [rightScratchpad, leftScratchpad], comparisonOptions: .defaults(mode: .automatic))
        )
        XCTAssertEqual(scratchpads.resolvedMode, .text)
        XCTAssertTrue(scratchpads.authorities.isEmpty)
        XCTAssertEqual(scratchpads.sides.map(\.source.revision), [leftScratchpad.source.revision, rightScratchpad.source.revision])
        let threeScratchpads = try plan(
            request(sides: [
                rightScratchpad,
                leftScratchpad,
                scratchpadInput(.middle, seed: 3)
            ])
        )
        XCTAssertTrue(threeScratchpads.isThreeWay)
        XCTAssertEqual(threeScratchpads.sides.map(\.side), [.left, .middle, .right])
        XCTAssertTrue(threeScratchpads.authorities.isEmpty)

        let mixed = try plan(
            request(
                sides: [fileInput(.left, seed: 1), scratchpadInput(.right, seed: 2)],
                comparisonOptions: .defaults(mode: .text)
            )
        )
        XCTAssertEqual(mixed.resolvedMode, .text)
        XCTAssertEqual(mixed.authorities.count, 1)
        let threeMixed = try plan(
            request(
                sides: [
                    scratchpadInput(.right, seed: 3),
                    fileInput(.middle, seed: 2),
                    fileInput(.left, seed: 1)
                ],
                comparisonOptions: .defaults(mode: .text)
            )
        )
        XCTAssertTrue(threeMixed.isThreeWay)
        XCTAssertEqual(threeMixed.sides.map(\.side), [.left, .middle, .right])
        XCTAssertEqual(threeMixed.authorities.count, 2)

        assertError(.mixedSourceKinds) {
            try plan(
                request(
                    sides: [folderInput(.left, seed: 1), scratchpadInput(.right, seed: 2)],
                    comparisonOptions: .defaults(mode: .folder)
                )
            )
        }
    }

    func testSwappingMovesCompletePayloadAdvancesGenerationAndPreservesOptions() throws {
        let reference = Workflow.RequestReference(identity: uuid(1), generation: 8)
        let transforms = transformSelections()
        let options = exactOptions(mode: .text, data: Data("options".utf8))
        let save = projectSaveIntent(format: .macMerge, existing: false)
        let limits = makeLimits(maximumItemCount: 17)
        let original = request(
            reference: reference,
            sides: [fileInput(.left, seed: 1, readOnly: true), fileInput(.right, seed: 2)],
            recursive: false,
            filter: nil,
            transforms: transforms,
            comparisonOptions: options,
            projectSaveIntent: save,
            compareButtonIntent: .compareAs(.text),
            limits: limits
        )

        let swapped = try original.swapping(.left, .right)
        XCTAssertEqual(swapped.reference, Workflow.RequestReference(identity: reference.identity, generation: 9))
        XCTAssertEqual(swapped.sides[0].side, .left)
        XCTAssertEqual(swapped.sides[0].source, original.sides[1].source)
        XCTAssertFalse(swapped.sides[0].readOnly)
        XCTAssertEqual(swapped.sides[1].side, .right)
        XCTAssertEqual(swapped.sides[1].source, original.sides[0].source)
        XCTAssertTrue(swapped.sides[1].readOnly)
        XCTAssertEqual(swapped.transforms, transforms)
        XCTAssertEqual(swapped.comparisonOptions, options)
        XCTAssertEqual(swapped.projectSaveIntent, save)
        XCTAssertEqual(swapped.compareButtonIntent, .compareAs(.text))
        XCTAssertEqual(swapped.limits, limits)
        XCTAssertEqual(try original.swapping(.left, .left), original)

        assertError(.missingSide(.middle)) { try original.swapping(.left, .middle) }
        let maximum = request(reference: .init(identity: uuid(2), generation: .max), sides: original.sides)
        assertError(.requestGenerationOverflow) { try maximum.swapping(.left, .right) }

        let threeWay = request(
            reference: reference,
            sides: [
                fileInput(.left, seed: 1, readOnly: true),
                fileInput(.middle, seed: 2),
                fileInput(.right, seed: 3, readOnly: true)
            ],
            transforms: transforms,
            comparisonOptions: options,
            projectSaveIntent: save,
            compareButtonIntent: .compareAs(.text),
            limits: limits
        )
        let swapPairs: [(Workflow.Side, Workflow.Side)] = [(.left, .middle), (.middle, .right)]
        for (first, second) in swapPairs {
            let result = try threeWay.swapping(first, second)
            let resultFirst = result.sides.first { $0.side == first }
            let resultSecond = result.sides.first { $0.side == second }
            XCTAssertEqual(result.reference.generation, reference.generation + 1)
            XCTAssertEqual(resultFirst?.source, threeWay.sides.first { $0.side == second }?.source)
            XCTAssertEqual(resultFirst?.readOnly, threeWay.sides.first { $0.side == second }?.readOnly)
            XCTAssertEqual(resultSecond?.source, threeWay.sides.first { $0.side == first }?.source)
            XCTAssertEqual(resultSecond?.readOnly, threeWay.sides.first { $0.side == first }?.readOnly)
            XCTAssertEqual(result.transforms, transforms)
            XCTAssertEqual(result.projectSaveIntent, save)
        }
    }

    func testSideCountSetAndDuplicateGuardsAreIsolated() throws {
        assertError(.invalidSideCount(1)) { try plan(request(sides: [fileInput(.left, seed: 1)])) }
        assertError(.invalidSideCount(4)) {
            _ = try plan(
                request(sides: [
                    fileInput(.left, seed: 1), fileInput(.middle, seed: 2),
                    fileInput(.right, seed: 3), fileInput(.left, seed: 4)
                ])
            )
        }
        assertError(.duplicateSide(.left)) {
            try plan(request(sides: [fileInput(.left, seed: 1), fileInput(.left, seed: 2)]))
        }
        assertError(.invalidSideSet([.left, .middle])) {
            try plan(request(sides: [fileInput(.left, seed: 1), fileInput(.middle, seed: 2)]))
        }
    }

    func testAutomaticModesResolveEveryRecognizedSourceKindAndRejectAmbiguity() throws {
        let cases: [(String, Workflow.ComparisonMode)] = [
            ("TXT", .text), ("csv", .table), ("png", .image), ("HTML", .webpage), ("zip", .binary)
        ]
        for (extensionName, expected) in cases {
            let result = try plan(
                request(sides: [
                    fileInput(.left, seed: 1, extension: extensionName),
                    fileInput(.right, seed: 2, extension: extensionName)
                ])
            )
            XCTAssertEqual(result.resolvedMode, expected)
        }

        assertError(.automaticModeRequiresExplicitSelection) {
            try plan(request(sides: [fileInput(.left, seed: 1, extension: "txt"), fileInput(.right, seed: 2, extension: "png")]))
        }
        assertError(.automaticModeRequiresExplicitSelection) {
            try plan(request(sides: [fileInput(.left, seed: 1, extension: "unknown"), fileInput(.right, seed: 2, extension: "unknown")]))
        }
        assertError(.automaticModeRequiresExplicitSelection) {
            try plan(request(sides: [fileInput(.left, seed: 1), scratchpadInput(.right, seed: 2)]))
        }
    }

    func testModeCompatibilityAndCompareButtonIntentGuardsAreExact() throws {
        assertError(.incompatibleMode(mode: .text, shape: .folders)) {
            try plan(
                request(
                    sides: [folderInput(.left, seed: 1), folderInput(.right, seed: 2)],
                    comparisonOptions: .defaults(mode: .text)
                )
            )
        }
        assertError(.incompatibleMode(mode: .binary, shape: .scratchpads)) {
            try plan(
                request(
                    sides: [scratchpadInput(.left, seed: 1), scratchpadInput(.right, seed: 2)],
                    comparisonOptions: .defaults(mode: .binary)
                )
            )
        }
        assertError(.incompatibleMode(mode: .folder, shape: .filesAndScratchpads)) {
            try plan(
                request(
                    sides: [fileInput(.left, seed: 1), scratchpadInput(.right, seed: 2)],
                    comparisonOptions: .defaults(mode: .folder)
                )
            )
        }
        assertError(.incompatibleMode(mode: .folder, shape: .files)) {
            try plan(
                request(
                    sides: fileSides(),
                    comparisonOptions: .defaults(mode: .folder)
                )
            )
        }
        assertError(.compareAsRequiresExplicitMode) {
            try plan(request(sides: fileSides(), compareButtonIntent: .compareAs(.automatic)))
        }
        assertError(.compareAsOptionsMismatch(expected: .binary, actual: .text)) {
            try plan(
                request(
                    sides: fileSides(),
                    comparisonOptions: .defaults(mode: .text),
                    compareButtonIntent: .compareAs(.binary)
                )
            )
        }
        let compareAs = try plan(
            request(
                sides: [fileInput(.left, seed: 1, extension: "unknown"), fileInput(.right, seed: 2, extension: "other")],
                comparisonOptions: .defaults(mode: .automatic),
                compareButtonIntent: .compareAs(.binary)
            )
        )
        XCTAssertEqual(compareAs.resolvedMode, .binary)
        XCTAssertEqual(compareAs.steps.last, .compare(mode: .binary, intent: .compareAs(.binary)))
    }

    func testRecursiveFilterTransformsExactOptionsAndStepOrdering() throws {
        let filter = filterSelection()
        let folderPlan = try plan(
            request(
                sides: [folderInput(.right, seed: 2), folderInput(.left, seed: 1)],
                recursive: true,
                filter: filter
            )
        )
        XCTAssertEqual(
            folderPlan.steps,
            [
                .validateExactState,
                .acquireAuthority(access(from: folderPlan.sides[0]).reference),
                .acquireAuthority(access(from: folderPlan.sides[1]).reference),
                .materializeSource(.left),
                .materializeSource(.right),
                .validateImmediatelyAfterMaterialization,
                .applyFilter(filter),
                .validateImmediatelyBeforePublication,
                .compare(mode: .folder, intent: .primary)
            ]
        )

        let transforms = transformSelections()
        let options = exactOptions(mode: .text, data: Data("canonical options".utf8))
        let filePlan = try plan(
            request(sides: fileSides(), transforms: transforms, comparisonOptions: options)
        )
        XCTAssertEqual(filePlan.resolvedMode, .text)
        XCTAssertEqual(
            Array(filePlan.steps.suffix(4)),
            [
                .runTransform(try XCTUnwrap(transforms.unpacker)),
                .runTransform(try XCTUnwrap(transforms.prediffer)),
                .validateImmediatelyBeforePublication,
                .compare(mode: .text, intent: .primary)
            ]
        )
        XCTAssertTrue(filePlan.steps.contains(.validateImmediatelyAfterMaterialization))
    }

    func testRecursiveFilterAndTransformShapeRequirementsAreIsolated() throws {
        assertError(.recursiveRequiresFolders) {
            try plan(request(sides: fileSides(), recursive: true, comparisonOptions: .defaults(mode: .text)))
        }
        assertError(.filterRequiresFolders) {
            try plan(request(sides: fileSides(), filter: filterSelection(), comparisonOptions: .defaults(mode: .text)))
        }
        assertError(.transformRequiresFiles(.unpacker)) {
            try plan(
                request(
                    sides: [folderInput(.left, seed: 1), folderInput(.right, seed: 2)],
                    transforms: .init(unpacker: transform(.unpacker, identifier: "unpack"))
                )
            )
        }
        assertError(.invalidTransformSelection(.unpacker)) {
            try plan(
                request(
                    sides: fileSides(),
                    transforms: .init(unpacker: transform(.prediffer, identifier: "wrong-slot")),
                    comparisonOptions: .defaults(mode: .text)
                )
            )
        }
        assertError(.invalidTransformSelection(.prediffer)) {
            let invalid = Workflow.TransformSelection(
                capability: .prediffer,
                identifier: "prediff",
                revision: 1,
                policySHA256: Data([1]),
                configurationSHA256: digest("config")
            )
            _ = try plan(
                request(
                    sides: fileSides(),
                    transforms: .init(prediffer: invalid),
                    comparisonOptions: .defaults(mode: .text)
                )
            )
        }
        let duplicate = transform(.unpacker, identifier: "same")
        assertError(.duplicateTransformIdentifier) {
            try plan(
                request(
                    sides: fileSides(),
                    transforms: .init(
                        unpacker: duplicate,
                        prediffer: transform(.prediffer, identifier: duplicate.identifier)
                    ),
                    comparisonOptions: .defaults(mode: .text)
                )
            )
        }
    }

    func testFilterTransformAndExactOptionPayloadValidationRejectsWrongReasonEscapes() throws {
        let invalidFilter = Workflow.FilterSelection(identifier: "bad value", revision: 1, definitionSHA256: digest("filter"))
        assertError(.invalidFilterSelection) {
            try plan(
                request(
                    sides: [folderInput(.left, seed: 1), folderInput(.right, seed: 2)],
                    filter: invalidFilter
                )
            )
        }
        let invalidTransform = Workflow.TransformSelection(
            capability: .unpacker,
            identifier: "unpack",
            revision: 1,
            policySHA256: digest("policy"),
            configurationSHA256: Data([1])
        )
        assertError(.invalidTransformSelection(.unpacker)) {
            try plan(
                request(
                    sides: fileSides(),
                    transforms: .init(unpacker: invalidTransform),
                    comparisonOptions: .defaults(mode: .text)
                )
            )
        }
        assertError(.exactOptionsRequireExplicitMode) {
            try plan(
                request(
                    sides: fileSides(),
                    comparisonOptions: exactOptions(mode: .automatic, data: Data())
                )
            )
        }
        let data = Data("payload".utf8)
        let mismatched = Workflow.ExactComparisonOptions(
            mode: .text,
            schemaIdentifier: "schema.v1",
            schemaRevision: 1,
            canonicalData: data,
            dataSHA256: digest("different")
        )
        assertError(.comparisonOptionsDigestMismatch) {
            try plan(request(sides: fileSides(), comparisonOptions: .exact(mismatched)))
        }
    }

    func testCanonicalIdentityRevisionAndAuthorityFieldsArePreserved() throws {
        let identity = canonicalIdentity(kind: .regularFile, seed: 7, path: "/unified/requested/../canonical-7.txt")
        let canonical = canonicalIdentity(kind: .regularFile, seed: 7, path: "/unified/canonical-7.txt")
        let revision = fileRevision(
            identity: canonical,
            byteCount: 99,
            modificationTimeSeconds: -8,
            modificationTimeNanoseconds: 999_999_999,
            statusChangeTimeSeconds: 12,
            statusChangeTimeNanoseconds: 0,
            content: digest("content-7"),
            metadata: digest("metadata-7")
        )
        let authority = Workflow.AccessAuthority(
            reference: .init(identity: uuid(107), generation: .max),
            resource: canonical,
            coverage: .exactItem,
            permissions: [.read, .create, .replace]
        )
        let requested = URL(filePath: identity.canonicalURL.path)
        let source = Workflow.LocalSource(
            requestedURL: requested,
            revision: .file(revision),
            selection: .init(
                requestedURL: requested,
                revision: .file(revision),
                authority: authority.reference,
                origin: .entered(editRevision: .max)
            ),
            access: authority
        )
        let input = Workflow.SideInput(side: .left, source: .file(source))
        let result = try plan(request(sides: [input, fileInput(.right, seed: 8)]))

        XCTAssertEqual(result.side(.left), input)
        XCTAssertEqual(result.authorities.first, authority)
        guard case .file(let plannedRevision) = result.side(.left)?.source.revision else {
            return XCTFail("Expected planned file revision")
        }
        XCTAssertEqual(plannedRevision.identity.kind, .regularFile)
        XCTAssertEqual(plannedRevision.identity.canonicalURL, URL(filePath: "/unified/canonical-7.txt"))
        XCTAssertEqual(plannedRevision.identity.node, .init(volumeID: 10, nodeID: 7, generation: 7))
        XCTAssertEqual(plannedRevision.byteCount, 99)
        XCTAssertEqual(plannedRevision.modificationTimeSeconds, -8)
        XCTAssertEqual(plannedRevision.modificationTimeNanoseconds, 999_999_999)
        XCTAssertEqual(plannedRevision.statusChangeTimeSeconds, 12)
        XCTAssertEqual(plannedRevision.statusChangeTimeNanoseconds, 0)
        XCTAssertEqual(plannedRevision.contentSHA256, digest("content-7"))
        XCTAssertEqual(plannedRevision.metadataSHA256, digest("metadata-7"))
    }

    func testRevisionKindTimestampDigestAndDeclaredLimitsRejectExactErrors() throws {
        let validIdentity = canonicalIdentity(kind: .regularFile, seed: 1)
        let folder = folderRevision(seed: 1)
        let wrongCase = localInput(side: .left, sourceCase: .file, revision: .folder(folder), selectionRevision: .folder(folder))
        assertError(.invalidRevision(side: .left)) {
            try plan(request(sides: [wrongCase, fileInput(.right, seed: 2)]))
        }
        let file = fileRevision(seed: 1)
        let symmetricWrongCase = localInput(
            side: .left,
            sourceCase: .folder,
            revision: .file(file),
            selectionRevision: .file(file)
        )
        assertError(.invalidRevision(side: .left)) {
            try plan(request(sides: [symmetricWrongCase, folderInput(.right, seed: 2)]))
        }

        for useStatusChange in [false, true] {
            for nanoseconds in [-1, 1_000_000_000] as [Int32] {
                let invalid = fileRevision(
                    identity: validIdentity,
                    modificationTimeNanoseconds: useStatusChange ? 20 : nanoseconds,
                    statusChangeTimeNanoseconds: useStatusChange ? nanoseconds : 40
                )
                assertError(.invalidRevision(side: .left)) {
                    try plan(request(sides: [fileInput(.left, revision: invalid), fileInput(.right, seed: 2)]))
                }
            }
        }
        let wrongKind = fileRevision(identity: canonicalIdentity(kind: .directory, seed: 1))
        assertError(.invalidRevision(side: .left)) {
            try plan(request(sides: [fileInput(.left, revision: wrongKind), fileInput(.right, seed: 2)]))
        }
        let badDigest = fileRevision(identity: validIdentity, content: Data(repeating: 1, count: 31))
        assertError(.invalidDigest(.fileContent(.left))) {
            try plan(request(sides: [fileInput(.left, revision: badDigest), fileInput(.right, seed: 2)]))
        }
        let badMetadata = fileRevision(identity: validIdentity, metadata: Data(repeating: 1, count: 31))
        assertError(.invalidDigest(.fileMetadata(.left))) {
            try plan(request(sides: [fileInput(.left, revision: badMetadata), fileInput(.right, seed: 2)]))
        }
        let byteBoundary = fileRevision(identity: validIdentity, byteCount: 5)
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: [fileInput(.left, revision: byteBoundary), fileInput(.right, seed: 2, byteCount: 5)], limits: makeLimits(maximumDeclaredBytes: 5))
            )
        )
        assertError(.declaredByteLimitExceeded(maximumBytes: 4)) {
            try plan(
                request(
                    sides: [fileInput(.left, revision: byteBoundary), fileInput(.right, seed: 2, byteCount: 4)], limits: makeLimits(maximumDeclaredBytes: 4))
            )
        }

        let folderBoundary = folderRevision(seed: 1, entryCount: 5)
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: [folderInput(.left, revision: folderBoundary), folderInput(.right, seed: 2, entryCount: 5)],
                    limits: makeLimits(maximumDeclaredItems: 5))
            )
        )
        assertError(.declaredItemLimitExceeded(maximumItems: 4)) {
            try plan(
                request(
                    sides: [folderInput(.left, revision: folderBoundary), folderInput(.right, seed: 2, entryCount: 4)],
                    limits: makeLimits(maximumDeclaredItems: 4))
            )
        }
        let wrongFolderKind = Workflow.FolderRevision(
            identity: canonicalIdentity(kind: .regularFile, seed: 1),
            entryCount: 1,
            treeSHA256: digest("tree"),
            metadataSHA256: digest("metadata")
        )
        assertError(.invalidRevision(side: .left)) {
            try plan(request(sides: [folderInput(.left, revision: wrongFolderKind), folderInput(.right, seed: 2)]))
        }
        let badFolderTree = Workflow.FolderRevision(
            identity: canonicalIdentity(kind: .directory, seed: 1),
            entryCount: 1,
            treeSHA256: Data([1]),
            metadataSHA256: digest("metadata")
        )
        assertError(.invalidDigest(.folderTree(.left))) {
            try plan(request(sides: [folderInput(.left, revision: badFolderTree), folderInput(.right, seed: 2)]))
        }
        let badFolderMetadata = Workflow.FolderRevision(
            identity: canonicalIdentity(kind: .directory, seed: 1),
            entryCount: 1,
            treeSHA256: digest("tree"),
            metadataSHA256: Data([1])
        )
        assertError(.invalidDigest(.folderMetadata(.left))) {
            try plan(request(sides: [folderInput(.left, revision: badFolderMetadata), folderInput(.right, seed: 2)]))
        }
    }

    func testSelectionAttestationsCoverBrowseHistoryEnteredAndRejectMismatches() throws {
        let origins: [Workflow.SelectionOrigin] = [
            .browse(session: uuid(1), selectionIndex: .max),
            .history(entryIdentifier: "recent/path:1", revision: .max),
            .entered(editRevision: .max)
        ]
        for (offset, origin) in origins.enumerated() {
            XCTAssertNoThrow(
                try plan(
                    request(sides: [fileInput(.left, seed: 10 + offset, origin: origin), fileInput(.right, seed: 20 + offset)])
                )
            )
        }

        let base = fileInput(.left, seed: 1)
        guard case .file(let local) = base.source else { return XCTFail("Expected file source") }
        let requestedMismatch = Workflow.LocalSource(
            requestedURL: local.requestedURL,
            revision: local.revision,
            selection: .init(
                requestedURL: URL(filePath: "/different/request.txt"),
                revision: local.revision,
                authority: local.access.reference,
                origin: .entered(editRevision: 1)
            ),
            access: local.access
        )
        assertError(.invalidSelectionAttestation(side: .left)) {
            try plan(request(sides: [.init(side: .left, source: .file(requestedMismatch)), fileInput(.right, seed: 2)]))
        }

        let wrongRevision = fileRevision(seed: 9)
        let revisionMismatch = Workflow.LocalSource(
            requestedURL: local.requestedURL,
            revision: local.revision,
            selection: .init(
                requestedURL: local.requestedURL,
                revision: .file(wrongRevision),
                authority: local.access.reference,
                origin: .entered(editRevision: 1)
            ),
            access: local.access
        )
        assertError(.invalidSelectionAttestation(side: .left)) {
            try plan(request(sides: [.init(side: .left, source: .file(revisionMismatch)), fileInput(.right, seed: 2)]))
        }

        let folderAttestationForFile = Workflow.LocalSource(
            requestedURL: local.requestedURL,
            revision: local.revision,
            selection: .init(
                requestedURL: local.requestedURL,
                revision: .folder(folderRevision(seed: 9)),
                authority: local.access.reference,
                origin: .entered(editRevision: 1)
            ),
            access: local.access
        )
        assertError(.invalidSelectionAttestation(side: .left)) {
            try plan(request(sides: [.init(side: .left, source: .file(folderAttestationForFile)), fileInput(.right, seed: 2)]))
        }

        let folderBase = folderInput(.left, seed: 1)
        guard case .folder(let folderLocal) = folderBase.source else {
            return XCTFail("Expected folder source")
        }
        let fileAttestationForFolder = Workflow.LocalSource(
            requestedURL: folderLocal.requestedURL,
            revision: folderLocal.revision,
            selection: .init(
                requestedURL: folderLocal.requestedURL,
                revision: .file(fileRevision(seed: 9)),
                authority: folderLocal.access.reference,
                origin: .entered(editRevision: 1)
            ),
            access: folderLocal.access
        )
        assertError(.invalidSelectionAttestation(side: .left)) {
            try plan(request(sides: [.init(side: .left, source: .folder(fileAttestationForFolder)), folderInput(.right, seed: 2)]))
        }

        let originalFileRevision = try XCTUnwrap(fileRevision(from: local.revision))
        for changedRevision in fileRevisionLeafMutations(originalFileRevision) {
            let mismatch = replacingLocalSelectionRevision(local, with: .file(changedRevision))
            assertError(.invalidSelectionAttestation(side: .left)) {
                try plan(request(sides: [.init(side: .left, source: .file(mismatch)), fileInput(.right, seed: 2)]))
            }
        }
        let originalFolderRevision = try XCTUnwrap(folderRevision(from: folderLocal.revision))
        for changedRevision in folderRevisionLeafMutations(originalFolderRevision) {
            let mismatch = replacingLocalSelectionRevision(folderLocal, with: .folder(changedRevision))
            assertError(.invalidSelectionAttestation(side: .left)) {
                try plan(request(sides: [.init(side: .left, source: .folder(mismatch)), folderInput(.right, seed: 2)]))
            }
        }

        let authorityMismatch = Workflow.LocalSource(
            requestedURL: local.requestedURL,
            revision: local.revision,
            selection: .init(
                requestedURL: local.requestedURL,
                revision: local.revision,
                authority: .init(identity: uuid(999), generation: 1),
                origin: .entered(editRevision: 1)
            ),
            access: local.access
        )
        assertError(.invalidSelectionAttestation(side: .left)) {
            try plan(request(sides: [.init(side: .left, source: .file(authorityMismatch)), fileInput(.right, seed: 2)]))
        }
        let authorityGenerationMismatch = replacingLocalAuthorityAttestation(
            local,
            with: .init(
                identity: local.access.reference.identity,
                generation: local.access.reference.generation + 1
            )
        )
        assertError(.invalidSelectionAttestation(side: .left)) {
            try plan(request(sides: [.init(side: .left, source: .file(authorityGenerationMismatch)), fileInput(.right, seed: 2)]))
        }

        let oversizedHistory = fileInput(.left, seed: 1, origin: .history(entryIdentifier: "abcde", revision: 1))
        assertError(.stringLimitExceeded(field: .historyIdentifier, maximumUTF8Bytes: 4)) {
            try plan(
                request(
                    sides: [oversizedHistory, fileInput(.right, seed: 2)],
                    limits: makeLimits(maximumStringUTF8Bytes: 4)
                )
            )
        }
        let malformedHistory = fileInput(.left, seed: 1, origin: .history(entryIdentifier: "bad history", revision: 1))
        assertError(.stringLimitExceeded(field: .historyIdentifier, maximumUTF8Bytes: 64 * 1_024)) {
            try plan(request(sides: [malformedHistory, fileInput(.right, seed: 2)]))
        }
    }

    func testAuthorityCoverageResourcePermissionsAndUniquenessRejectExactly() throws {
        let valid = fileInput(.left, seed: 1)
        let cases: [(Workflow.AccessAuthority, Workflow.PlanningError)] = [
            (authority(seed: 1, resource: identity(from: valid), coverage: .directoryTree, permissions: [.read]), .invalidAuthority(side: .left)),
            (
                authority(seed: 1, resource: canonicalIdentity(kind: .regularFile, seed: 9), coverage: .exactItem, permissions: [.read]),
                .invalidAuthority(side: .left)
            ),
            (authority(seed: 1, resource: identity(from: valid), coverage: .exactItem, permissions: [.create]), .invalidAuthority(side: .left)),
            (authority(seed: 1, resource: identity(from: valid), coverage: .exactItem, permissions: []), .invalidAuthority(side: nil)),
            (authority(seed: 1, resource: identity(from: valid), coverage: .exactItem, permissions: .init(rawValue: 0x80)), .invalidAuthority(side: nil))
        ]
        for (invalid, expected) in cases {
            assertError(expected) {
                try plan(request(sides: [replacingAccess(valid, with: invalid), fileInput(.right, seed: 2)]))
            }
        }

        let left = fileInput(.left, seed: 1)
        let right = fileInput(.right, seed: 2)
        let duplicateReference = Workflow.AccessAuthority(
            reference: access(from: left).reference,
            resource: identity(from: right),
            coverage: .exactItem,
            permissions: [.read]
        )
        assertError(.duplicateAuthority(access(from: left).reference)) {
            try plan(request(sides: [left, replacingAccess(right, with: duplicateReference)]))
        }

        let sameUUIDNewGeneration = Workflow.AccessAuthority(
            reference: .init(identity: access(from: left).reference.identity, generation: 999),
            resource: identity(from: right),
            coverage: .exactItem,
            permissions: [.read]
        )
        assertError(.duplicateAuthority(sameUUIDNewGeneration.reference)) {
            try plan(request(sides: [left, replacingAccess(right, with: sameUUIDNewGeneration)]))
        }
    }

    func testDuplicateCanonicalPathsNodesScratchpadsAndZeroNodeComponents() throws {
        let leftIdentity = canonicalIdentity(kind: .regularFile, seed: 1, path: "/unified/shared.txt")
        let samePath = canonicalIdentity(kind: .regularFile, seed: 2, path: "/unified/shared.txt")
        assertError(.duplicateSourceIdentity(first: .left, second: .right)) {
            try plan(
                request(sides: [fileInput(.left, revision: fileRevision(identity: leftIdentity)), fileInput(.right, revision: fileRevision(identity: samePath))]
                ))
        }

        let sameNodeDifferentGeneration = Workflow.CanonicalIdentity(
            kind: .regularFile,
            canonicalURL: URL(filePath: "/unified/different.txt"),
            node: .init(volumeID: leftIdentity.node.volumeID, nodeID: leftIdentity.node.nodeID, generation: 999)
        )
        assertError(.duplicateSourceIdentity(first: .left, second: .right)) {
            try plan(
                request(sides: [
                    fileInput(.left, revision: fileRevision(identity: leftIdentity)),
                    fileInput(.right, revision: fileRevision(identity: sameNodeDifferentGeneration))
                ]))
        }

        let duplicateScratchpadID = uuid(50)
        assertError(.duplicateSourceIdentity(first: .left, second: .right)) {
            try plan(
                request(sides: [
                    scratchpadInput(.left, seed: 1, identity: duplicateScratchpadID),
                    scratchpadInput(.right, seed: 2, identity: duplicateScratchpadID)
                ])
            )
        }

        for node in [
            Workflow.NodeIdentity(volumeID: 0, nodeID: 1, generation: 1),
            Workflow.NodeIdentity(volumeID: 1, nodeID: 0, generation: 1)
        ] {
            let invalidIdentity = Workflow.CanonicalIdentity(kind: .regularFile, canonicalURL: URL(filePath: "/unified/zero.txt"), node: node)
            assertError(.invalidRevision(side: .left)) {
                try plan(request(sides: [fileInput(.left, revision: fileRevision(identity: invalidIdentity)), fileInput(.right, seed: 2)]))
            }
        }
    }

    func testZeroUUIDIdentitiesRemainValidWhileFilesystemNodeZerosFailClosed() throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let file = fileInput(.left, seed: 1, origin: .browse(session: zero, selectionIndex: 0))
        let zeroAuthority = Workflow.AccessAuthority(
            reference: .init(identity: zero, generation: 0),
            resource: identity(from: file),
            coverage: .exactItem,
            permissions: [.read]
        )
        let request = request(
            reference: .init(identity: zero, generation: 0),
            sides: [
                replacingAccess(file, with: zeroAuthority),
                scratchpadInput(.right, seed: 2, identity: zero)
            ],
            comparisonOptions: .defaults(mode: .text)
        )

        let result = try plan(request)
        XCTAssertEqual(result.request.reference.identity, zero)
        XCTAssertEqual(result.authorities.first?.reference.identity, zero)
        XCTAssertEqual(result.sides[1].source.revision, request.sides[1].source.revision)
    }

    func testScratchpadDigestLabelsAndExactByteBoundaries() throws {
        let text = "é"
        let exactLimits = makeLimits(
            maximumLabelUTF8Bytes: 2,
            maximumScratchpadUTF8Bytes: 2,
            maximumCombinedScratchpadUTF8Bytes: 3
        )
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: [scratchpadInput(.left, seed: 1, text: text, label: "ok"), scratchpadInput(.right, seed: 2, text: "x")],
                    limits: exactLimits
                )
            )
        )
        assertError(.scratchpadTooLarge(side: .left, maximumUTF8Bytes: 1)) {
            try plan(
                request(
                    sides: [scratchpadInput(.left, seed: 1, text: text), scratchpadInput(.right, seed: 2, text: "x")],
                    limits: makeLimits(maximumScratchpadUTF8Bytes: 1, maximumCombinedScratchpadUTF8Bytes: 3)
                )
            )
        }
        assertError(.combinedScratchpadsTooLarge(maximumUTF8Bytes: 2)) {
            try plan(
                request(
                    sides: [scratchpadInput(.left, seed: 1, text: text), scratchpadInput(.right, seed: 2, text: "x")],
                    limits: makeLimits(maximumScratchpadUTF8Bytes: 2, maximumCombinedScratchpadUTF8Bytes: 2)
                )
            )
        }
        assertError(.stringLimitExceeded(field: .label, maximumUTF8Bytes: 1)) {
            try plan(
                request(
                    sides: [scratchpadInput(.left, seed: 1, text: "a", label: "ok"), scratchpadInput(.right, seed: 2, text: "b")],
                    limits: makeLimits(maximumLabelUTF8Bytes: 1)
                )
            )
        }
        assertError(.scratchpadDigestMismatch(side: .left)) {
            try plan(
                request(sides: [scratchpadInput(.left, seed: 1, text: "a", digest: digest("other")), scratchpadInput(.right, seed: 2, text: "b")])
            )
        }
        assertError(.invalidDigest(.scratchpad(.left))) {
            try plan(
                request(sides: [scratchpadInput(.left, seed: 1, text: "a", digest: Data([1])), scratchpadInput(.right, seed: 2, text: "b")])
            )
        }
    }

    func testProjectSaveAbsentRequiresCreateAndAppendsSeparatePublicationValidation() throws {
        let save = projectSaveIntent(format: .macMerge, existing: false, origin: .history(entryIdentifier: "save/recent", revision: 2))
        let result = try plan(request(sides: fileSides(), projectSaveIntent: save))

        XCTAssertEqual(result.authorities.last, save.access)
        XCTAssertEqual(
            Array(result.steps.suffix(4)),
            [
                .validateImmediatelyBeforePublication,
                .compare(mode: .text, intent: .primary),
                .validateImmediatelyBeforePublication,
                .saveProject(save)
            ]
        )
        XCTAssertEqual(result.steps.filter { $0 == .validateImmediatelyBeforePublication }.count, 2)

        let missingCreate = replacingProjectAccess(save, permissions: [.read])
        assertError(.invalidProjectDestination) {
            try plan(request(sides: fileSides(), projectSaveIntent: missingCreate))
        }
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: fileSides(),
                    projectSaveIntent: replacingProjectAccess(save, permissions: [.create])
                )
            )
        )
        let wrongCoverage = replacingProjectAccess(save, coverage: .exactItem)
        assertError(.invalidProjectDestination) {
            try plan(request(sides: fileSides(), projectSaveIntent: wrongCoverage))
        }
        let wrongResource = replacingProjectAccess(
            save,
            resource: canonicalIdentity(kind: .directory, seed: 77, path: "/other")
        )
        assertError(.invalidProjectDestination) {
            try plan(request(sides: fileSides(), projectSaveIntent: wrongResource))
        }
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: fileSides(),
                    projectSaveIntent: projectSaveIntent(format: .winMerge, existing: false, origin: .entered(editRevision: 4))
                )
            )
        )
    }

    func testProjectSaveExistingRequiresReadReplaceAndSupportsBothFormats() throws {
        for format in Workflow.ProjectFormat.allCases {
            let save = projectSaveIntent(format: format, existing: true)
            let result = try plan(request(sides: fileSides(), projectSaveIntent: save))
            XCTAssertEqual(result.authorities.last?.permissions, [.read, .replace])

            for permissions in [Workflow.AuthorityPermissions.read, .replace] {
                assertError(.invalidProjectDestination) {
                    try plan(
                        request(
                            sides: fileSides(),
                            projectSaveIntent: replacingProjectAccess(save, permissions: permissions)
                        )
                    )
                }
            }
            assertError(.invalidProjectDestination) {
                try plan(
                    request(
                        sides: fileSides(),
                        projectSaveIntent: replacingProjectAccess(save, coverage: .directoryTree)
                    )
                )
            }
            assertError(.invalidProjectDestination) {
                try plan(
                    request(
                        sides: fileSides(),
                        projectSaveIntent: replacingProjectAccess(
                            save,
                            resource: canonicalIdentity(kind: .regularFile, seed: 78, path: "/projects/other.txt")
                        )
                    )
                )
            }
        }
    }

    func testProjectAuthorityCannotReuseSourceAuthorityUUIDAtAnyGeneration() throws {
        let left = fileInput(.left, seed: 1)
        let right = fileInput(.right, seed: 2)
        let sourceReference = access(from: left).reference

        for generation in [sourceReference.generation, sourceReference.generation + 1] {
            let save = replacingProjectAuthorityReference(
                projectSaveIntent(format: .macMerge, existing: false),
                with: .init(identity: sourceReference.identity, generation: generation)
            )
            assertError(.duplicateAuthority(save.access.reference)) {
                try plan(request(sides: [left, right], projectSaveIntent: save))
            }
        }
    }

    func testProjectDestinationAttestationExtensionParentAndAliasGuards() throws {
        let valid = projectSaveIntent(format: .macMerge, existing: false)
        let mismatchedSelection = Workflow.ProjectSaveIntent(
            format: valid.format,
            requestedURL: valid.requestedURL,
            destination: valid.destination,
            selection: .init(
                requestedURL: URL(filePath: "/different/new.macmerge"),
                destination: valid.destination,
                authority: valid.access.reference,
                origin: .entered(editRevision: 1)
            ),
            access: valid.access
        )
        assertError(.invalidProjectDestination) {
            try plan(request(sides: fileSides(), projectSaveIntent: mismatchedSelection))
        }

        guard case .absent(let validLocation) = valid.destination else {
            return XCTFail("Expected absent destination")
        }
        let alternateDestination = Workflow.ProjectDestinationState.absent(
            .init(
                canonicalURL: URL(filePath: "/projects/alternate.macmerge"),
                parent: validLocation.parent
            )
        )
        let destinationMismatch = Workflow.ProjectSaveIntent(
            format: valid.format,
            requestedURL: valid.requestedURL,
            destination: valid.destination,
            selection: .init(
                requestedURL: valid.requestedURL,
                destination: alternateDestination,
                authority: valid.access.reference,
                origin: .entered(editRevision: 1)
            ),
            access: valid.access
        )
        assertError(.invalidProjectDestination) {
            try plan(request(sides: fileSides(), projectSaveIntent: destinationMismatch))
        }
        let authorityMismatch = Workflow.ProjectSaveIntent(
            format: valid.format,
            requestedURL: valid.requestedURL,
            destination: valid.destination,
            selection: .init(
                requestedURL: valid.requestedURL,
                destination: valid.destination,
                authority: .init(identity: uuid(999), generation: 1),
                origin: .entered(editRevision: 1)
            ),
            access: valid.access
        )
        assertError(.invalidProjectDestination) {
            try plan(request(sides: fileSides(), projectSaveIntent: authorityMismatch))
        }

        let wrongExtension = projectSaveIntent(format: .macMerge, existing: false, path: "/projects/new.winmerge")
        assertError(.invalidProjectDestination) {
            try plan(request(sides: fileSides(), projectSaveIntent: wrongExtension))
        }

        let wrongParent = projectSaveIntent(format: .macMerge, existing: false, path: "/other/new.macmerge", parentPath: "/projects")
        assertError(.invalidURL(role: .canonicalProjectDestination, issue: .parentMismatch)) {
            try plan(request(sides: fileSides(), projectSaveIntent: wrongParent))
        }

        let aliasRevision = fileRevision(
            identity: canonicalIdentity(kind: .regularFile, seed: 1, path: "/projects/new.macmerge")
        )
        let source = fileInput(.left, revision: aliasRevision)
        let existingAlias = projectSaveIntent(
            format: .macMerge,
            existing: true,
            existingRevision: aliasRevision
        )
        assertError(.projectDestinationAliasesSource(.left)) {
            try plan(
                request(
                    sides: [source, fileInput(.right, seed: 2)],
                    comparisonOptions: .defaults(mode: .text),
                    projectSaveIntent: existingAlias
                )
            )
        }

        let pathAliasIdentity = canonicalIdentity(kind: .regularFile, seed: 99, path: identity(from: source).canonicalURL.path)
        let pathAlias = projectSaveIntent(
            format: .macMerge,
            existing: true,
            existingRevision: fileRevision(identity: pathAliasIdentity)
        )
        assertError(.projectDestinationAliasesSource(.left)) {
            try plan(
                request(
                    sides: [source, fileInput(.right, seed: 2)],
                    comparisonOptions: .defaults(mode: .text),
                    projectSaveIntent: pathAlias
                )
            )
        }

        assertError(.projectCannotRepresentScratchpads) {
            try plan(
                request(
                    sides: [fileInput(.left, seed: 1), scratchpadInput(.right, seed: 2)],
                    comparisonOptions: .defaults(mode: .text),
                    projectSaveIntent: valid
                )
            )
        }
    }

    func testURLValidationRejectsRequestedAndCanonicalFormsWithExactRoles() throws {
        let remote = try XCTUnwrap(URL(string: "https://example.com/file.txt"))
        assertError(.invalidURL(role: .requestedSource(.left), issue: .notFileURL)) {
            try plan(request(sides: [fileInput(.left, seed: 1, requestedURL: remote), fileInput(.right, seed: 2)]))
        }
        let relative = try XCTUnwrap(URL(string: "file:relative.txt"))
        assertError(.invalidURL(role: .requestedSource(.left), issue: .relativeURL)) {
            try plan(request(sides: [fileInput(.left, seed: 1, requestedURL: relative), fileInput(.right, seed: 2)]))
        }
        let authorityURL = try XCTUnwrap(URL(string: "file://host/unified/file.txt"))
        assertError(.invalidURL(role: .requestedSource(.left), issue: .authorityComponent)) {
            try plan(request(sides: [fileInput(.left, seed: 1, requestedURL: authorityURL), fileInput(.right, seed: 2)]))
        }
        let queried = try XCTUnwrap(URL(string: "file:///unified/file.txt?q=1"))
        assertError(.invalidURL(role: .requestedSource(.left), issue: .queryOrFragment)) {
            try plan(request(sides: [fileInput(.left, seed: 1, requestedURL: queried), fileInput(.right, seed: 2)]))
        }
        let missing = try XCTUnwrap(URL(string: "file:"))
        assertError(.invalidURL(role: .requestedSource(.left), issue: .relativeURL)) {
            try plan(request(sides: [fileInput(.left, seed: 1, requestedURL: missing), fileInput(.right, seed: 2)]))
        }

        let noncanonical = canonicalIdentity(kind: .regularFile, seed: 1, path: "/unified/../unified/file.txt")
        assertError(.invalidURL(role: .canonicalSource(.left), issue: .notCanonical)) {
            try plan(request(sides: [fileInput(.left, revision: fileRevision(identity: noncanonical)), fileInput(.right, seed: 2)]))
        }
        let wrongShape = Workflow.CanonicalIdentity(
            kind: .regularFile,
            canonicalURL: URL(fileURLWithPath: "/unified/file.txt", isDirectory: true),
            node: .init(volumeID: 1, nodeID: 1, generation: 1)
        )
        assertError(.invalidURL(role: .canonicalSource(.left), issue: .notCanonical)) {
            try plan(request(sides: [fileInput(.left, revision: fileRevision(identity: wrongShape)), fileInput(.right, seed: 2)]))
        }
    }

    func testDeterministicReceiptsCanonicalizeInputOrderAndDigestFullRequestState() throws {
        let reference = Workflow.RequestReference(identity: uuid(1), generation: 4)
        let left = fileInput(.left, seed: 1)
        let right = fileInput(.right, seed: 2)
        let first = try plan(request(reference: reference, sides: [right, left]))
        let second = try plan(request(reference: reference, sides: [left, right]))

        XCTAssertEqual(first.sides, second.sides)
        XCTAssertEqual(first.authorities, second.authorities)
        XCTAssertEqual(first.steps, second.steps)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(
            first.receipt.planSHA256,
            Data([
                0x12, 0xBC, 0x61, 0xF7, 0xC2, 0x8C, 0xC4, 0x08,
                0xEA, 0xF0, 0xE9, 0x71, 0xCB, 0x1A, 0xCE, 0x37,
                0x96, 0x8F, 0x1A, 0x8F, 0xC5, 0x86, 0xAF, 0x42,
                0xAC, 0xAC, 0x76, 0xD9, 0xC9, 0xF9, 0x37, 0x63
            ])
        )
        XCTAssertEqual(first.receipt.planSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(first.receipt.requestStateSHA256, first.receipt.planSHA256)
        XCTAssertEqual(first.receipt.request.identity, uuid(1))
        XCTAssertEqual(first.receipt.request.generation, 4)
        XCTAssertEqual(first.receipt.retainedByteCount, 450)
        XCTAssertEqual(first.receipt.planningWorkUnits, 2_086)

        let mutations: [Workflow.Request] = [
            request(reference: .init(identity: uuid(2), generation: reference.generation), sides: [left, right]),
            request(reference: .init(identity: reference.identity, generation: 5), sides: [left, right]),
            request(reference: reference, sides: [replacingReadOnly(left, true), right]),
            request(reference: reference, sides: [left, right], comparisonOptions: .defaults(mode: .binary)),
            request(reference: reference, sides: [left, right], compareButtonIntent: .compareAs(.binary)),
            request(reference: reference, sides: [left, right], limits: makeLimits(maximumItemCount: 9))
        ]
        for mutation in mutations {
            XCTAssertNotEqual(try plan(mutation).receipt.planSHA256, first.receipt.planSHA256)
        }
    }

    func testExecutorContractAndMaterializationPublicationStepsAreMandatory() throws {
        let result = try plan(request(sides: fileSides()))
        XCTAssertEqual(result.executorContract, .required)
        XCTAssertEqual(result.executorContract.pathResolution, .descriptorRelativeNoFollowFromPinnedCanonicalParent)
        XCTAssertEqual(result.executorContract.authority, .reacquireExactGenerationAndBalanceAccess)
        XCTAssertEqual(
            result.executorContract.revision,
            .revalidateAllExactRevisionsBeforeMaterializationImmediatelyAfterAndBeforeEveryPublication
        )
        XCTAssertEqual(result.executorContract.publication, .serializeImmediateValidationAndEachEffectPublication)
        XCTAssertEqual(result.executorContract.cancellation, .cancellationBeforeEffectsAndPublication)
        XCTAssertEqual(result.steps.first, .validateExactState)
        XCTAssertEqual(
            result.steps.filter {
                if case .materializeSource = $0 { return true }
                return false
            },
            [.materializeSource(.left), .materializeSource(.right)]
        )
        XCTAssertEqual(result.steps[result.steps.count - 3], .validateImmediatelyAfterMaterialization)
        XCTAssertEqual(result.steps[result.steps.count - 2], .validateImmediatelyBeforePublication)

        let transforms = transformSelections()
        let save = projectSaveIntent(format: .macMerge, existing: false)
        let complete = try plan(
            request(
                sides: fileSides(),
                transforms: transforms,
                comparisonOptions: .defaults(mode: .text),
                projectSaveIntent: save
            )
        )
        XCTAssertEqual(
            complete.steps,
            [
                .validateExactState,
                .acquireAuthority(access(from: complete.sides[0]).reference),
                .acquireAuthority(access(from: complete.sides[1]).reference),
                .acquireAuthority(save.access.reference),
                .materializeSource(.left),
                .materializeSource(.right),
                .validateImmediatelyAfterMaterialization,
                .runTransform(try XCTUnwrap(transforms.unpacker)),
                .runTransform(try XCTUnwrap(transforms.prediffer)),
                .validateImmediatelyBeforePublication,
                .compare(mode: .text, intent: .primary),
                .validateImmediatelyBeforePublication,
                .saveProject(save)
            ]
        )
        for publicationIndex in complete.steps.indices where complete.steps[publicationIndex] == .validateImmediatelyBeforePublication {
            XCTAssertTrue(publicationIndex + 1 < complete.steps.count)
            switch complete.steps[publicationIndex + 1] {
            case .compare, .saveProject:
                break
            default:
                XCTFail("Publication validation must be adjacent to effect")
            }
        }
    }

    func testExecutionValidationAcceptsReorderedExactStateAtExecutionAndPublication() throws {
        let request = request(
            sides: fileSides(),
            transforms: transformSelections(),
            comparisonOptions: exactOptions(mode: .text, data: Data("options".utf8)),
            projectSaveIntent: projectSaveIntent(format: .macMerge, existing: false)
        )
        let result = try plan(request)
        let current = validation(for: result, reverseArrays: true)

        XCTAssertNoThrow(try result.validateForExecution(current))
        XCTAssertNoThrow(try result.validateForPublication(current))
    }

    func testExecutionValidationRejectsReferenceAndFullRequestStateCASMutations() throws {
        let request = request(sides: fileSides())
        let result = try plan(request)
        for staleReference in [
            Workflow.RequestReference(identity: uuid(99), generation: request.reference.generation),
            Workflow.RequestReference(identity: request.reference.identity, generation: request.reference.generation + 1)
        ] {
            let referenceRequest = replacingRequest(request, reference: staleReference)
            assertValidationError(
                .staleRequest(expected: request.reference, actual: staleReference),
                plan: result,
                validation: validation(for: result, request: referenceRequest)
            )
        }

        let stateMutations: [Workflow.Request] = [
            replacingRequest(request, sides: [replacingReadOnly(request.sides[0], true), request.sides[1]]),
            replacingRequest(request, recursive: true),
            replacingRequest(request, comparisonOptions: .defaults(mode: .binary)),
            replacingRequest(request, compareButtonIntent: .compareAs(.binary))
        ]
        for mutation in stateMutations {
            assertValidationError(.staleRequestState, plan: result, validation: validation(for: result, request: mutation))
        }

        let limitMutation = replacingRequest(request, limits: makeLimits(maximumItemCount: 9))
        assertValidationError(.staleRequestState, plan: result, validation: validation(for: result, request: limitMutation))
    }

    func testFullRequestStateCASCoversEverySemanticRequestField() throws {
        let fileRequest = request(
            sides: fileSides(),
            transforms: transformSelections(),
            comparisonOptions: exactOptions(mode: .text, data: Data("options".utf8)),
            projectSaveIntent: projectSaveIntent(format: .macMerge, existing: false),
            compareButtonIntent: .compareAs(.text)
        )
        let filePlan = try plan(fileRequest)
        let left = fileRequest.sides[0]
        let right = fileRequest.sides[1]
        let reordered = replacingRequest(fileRequest, sides: [right, left])
        XCTAssertNoThrow(try filePlan.validateForExecution(validation(for: filePlan, request: reordered)))

        let swappedPayloads = [
            Workflow.SideInput(side: .left, source: right.source, readOnly: right.readOnly),
            Workflow.SideInput(side: .right, source: left.source, readOnly: left.readOnly)
        ]
        let fileMutations: [Workflow.Request] = [
            replacingRequest(fileRequest, sides: swappedPayloads),
            replacingRequest(fileRequest, sides: [replacingReadOnly(left, true), right]),
            replacingRequest(
                fileRequest,
                transforms: .init(
                    unpacker: transform(.unpacker, identifier: "unpack", revision: 99),
                    prediffer: fileRequest.transforms.prediffer
                )
            ),
            replacingRequest(
                fileRequest,
                comparisonOptions: exactOptions(mode: .text, schemaRevision: 99, data: Data("options".utf8))
            ),
            replacingRequest(
                fileRequest,
                projectSaveIntent: projectSaveIntent(format: .winMerge, existing: false)
            ),
            replacingRequest(fileRequest, compareButtonIntent: .primary),
            replacingRequest(fileRequest, limits: makeLimits(maximumItemCount: 12))
        ]
        for mutation in fileMutations {
            assertValidationError(.staleRequestState, plan: filePlan, validation: validation(for: filePlan, request: mutation))
        }

        let folderRequest = request(
            sides: [folderInput(.left, seed: 1), folderInput(.right, seed: 2)],
            recursive: true,
            filter: filterSelection()
        )
        let folderPlan = try plan(folderRequest)
        let folderMutations = [
            replacingRequest(folderRequest, recursive: false),
            replacingRequest(
                folderRequest,
                filter: .some(
                    Workflow.FilterSelection(
                        identifier: "filter.swift",
                        revision: 99,
                        definitionSHA256: digest("filter")
                    )
                )
            )
        ]
        for mutation in folderMutations {
            assertValidationError(.staleRequestState, plan: folderPlan, validation: validation(for: folderPlan, request: mutation))
        }
    }

    func testExecutionAndPublicationValidationMapTaskCancellationExactly() async throws {
        let result = try plan(request(sides: fileSides()))
        let current = validation(for: result)

        for operation in [
            { try result.validateForExecution(current) },
            { try result.validateForPublication(current) }
        ] as [@Sendable () throws -> Void] {
            do {
                try await Task {
                    withUnsafeCurrentTask { $0?.cancel() }
                    try operation()
                }.value
                XCTFail("Expected cancellation")
            } catch {
                XCTAssertEqual(error as? Workflow.PlanningError, .cancelled)
            }
        }
    }

    func testExecutionValidationRejectsMalformedSourceAndAuthorityCollectionsBeforeStaleness() throws {
        let result = try plan(request(sides: fileSides()))
        let exact = validation(for: result)
        assertValidationError(
            .invalidExecutionValidation,
            plan: result,
            validation: replacingValidation(exact, sources: Array(exact.sources.dropLast()))
        )
        assertValidationError(
            .invalidExecutionValidation,
            plan: result,
            validation: replacingValidation(exact, sources: [exact.sources[0], exact.sources[0]])
        )
        assertValidationError(
            .invalidExecutionValidation,
            plan: result,
            validation: replacingValidation(exact, authorities: Array(exact.authorities.dropLast()))
        )
        assertValidationError(
            .invalidExecutionValidation,
            plan: result,
            validation: replacingValidation(exact, authorities: [exact.authorities[0], exact.authorities[0]])
        )

        let sameCountUnknownSide = [
            exact.sources[0],
            Workflow.PositionedRevision(side: .middle, revision: exact.sources[1].revision)
        ]
        assertValidationError(
            .invalidExecutionValidation,
            plan: result,
            validation: replacingValidation(exact, sources: sameCountUnknownSide)
        )

        var sameCountUnknownAuthority = exact.authorities
        sameCountUnknownAuthority[1] = Workflow.AccessAuthority(
            reference: .init(identity: uuid(999), generation: 1),
            resource: sameCountUnknownAuthority[1].resource,
            coverage: sameCountUnknownAuthority[1].coverage,
            permissions: sameCountUnknownAuthority[1].permissions
        )
        assertValidationError(
            .invalidExecutionValidation,
            plan: result,
            validation: replacingValidation(exact, authorities: sameCountUnknownAuthority)
        )
    }

    func testExecutionValidationRejectsEachStaleObservedComponentIndependently() throws {
        let request = request(
            sides: [folderInput(.left, seed: 1), folderInput(.right, seed: 2)],
            filter: filterSelection(),
            projectSaveIntent: projectSaveIntent(format: .macMerge, existing: false)
        )
        let result = try plan(request)
        let exact = validation(for: result)

        var staleSources = exact.sources
        staleSources[0] = .init(side: .left, revision: .folder(folderRevision(seed: 9)))
        assertValidationError(.staleSource(.left), plan: result, validation: replacingValidation(exact, sources: staleSources))

        var staleAuthorities = exact.authorities
        let first = staleAuthorities[0]
        staleAuthorities[0] = Workflow.AccessAuthority(
            reference: first.reference,
            resource: first.resource,
            coverage: first.coverage,
            permissions: [.read, .create]
        )
        assertValidationError(.staleAuthority(first.reference), plan: result, validation: replacingValidation(exact, authorities: staleAuthorities))

        let staleFilter = Workflow.FilterSelection(identifier: "filter.swift", revision: 99, definitionSHA256: digest("filter"))
        assertValidationError(.staleFilter, plan: result, validation: replacingValidation(exact, filter: .some(staleFilter)))

        let staleDestination = projectDestination(format: .macMerge, existing: false, path: "/projects/other.macmerge")
        assertValidationError(
            .staleProjectDestination,
            plan: result,
            validation: replacingValidation(exact, projectDestination: .some(staleDestination))
        )
    }

    func testExecutionValidationRejectsStaleTransformsAndComparisonOptionsIndependently() throws {
        let request = request(
            sides: fileSides(),
            transforms: transformSelections(),
            comparisonOptions: exactOptions(mode: .text, data: Data("abc".utf8))
        )
        let result = try plan(request)
        let exact = validation(for: result)
        let staleUnpacker = transform(.unpacker, identifier: "unpack", revision: 99)
        assertValidationError(
            .staleTransform(.unpacker),
            plan: result,
            validation: replacingValidation(exact, unpacker: .some(staleUnpacker))
        )
        let stalePrediffer = transform(.prediffer, identifier: "prediff", revision: 99)
        assertValidationError(
            .staleTransform(.prediffer),
            plan: result,
            validation: replacingValidation(exact, prediffer: .some(stalePrediffer))
        )

        let staleOptions = exactOptions(mode: .text, schemaRevision: 99, data: Data("abc".utf8))
        assertValidationError(
            .staleComparisonOptions,
            plan: result,
            validation: replacingValidation(exact, comparisonOptions: staleOptions)
        )
    }

    func testObservedFileFolderAndScratchpadRevisionFieldsBecomeStaleIndependently() throws {
        let filePlan = try plan(request(sides: fileSides()))
        let fileValidation = validation(for: filePlan)
        let plannedFile = try XCTUnwrap(fileRevision(from: fileValidation.sources[0].revision))
        for mutation in fileRevisionLeafMutations(plannedFile) {
            var sources = fileValidation.sources
            sources[0] = .init(side: .left, revision: .file(mutation))
            assertValidationError(
                .staleSource(.left),
                plan: filePlan,
                validation: replacingValidation(fileValidation, sources: sources)
            )
        }

        let folderPlan = try plan(request(sides: [folderInput(.left, seed: 1), folderInput(.right, seed: 2)]))
        let folderValidation = validation(for: folderPlan)
        let plannedFolder = try XCTUnwrap(folderRevision(from: folderValidation.sources[0].revision))
        for mutation in folderRevisionLeafMutations(plannedFolder) {
            var sources = folderValidation.sources
            sources[0] = .init(side: .left, revision: .folder(mutation))
            assertValidationError(
                .staleSource(.left),
                plan: folderPlan,
                validation: replacingValidation(folderValidation, sources: sources)
            )
        }

        let scratchpadPlan = try plan(
            request(sides: [scratchpadInput(.left, seed: 1), scratchpadInput(.right, seed: 2)])
        )
        let scratchpadValidation = validation(for: scratchpadPlan)
        guard case .scratchpad(let scratchpad) = scratchpadValidation.sources[0].revision else {
            return XCTFail("Expected scratchpad revision")
        }
        let scratchpadMutations = [
            Workflow.ScratchpadRevision(identity: uuid(999), generation: scratchpad.generation, contentSHA256: scratchpad.contentSHA256),
            Workflow.ScratchpadRevision(identity: scratchpad.identity, generation: scratchpad.generation + 1, contentSHA256: scratchpad.contentSHA256),
            Workflow.ScratchpadRevision(identity: scratchpad.identity, generation: scratchpad.generation, contentSHA256: digest("stale"))
        ]
        for mutation in scratchpadMutations {
            var sources = scratchpadValidation.sources
            sources[0] = .init(side: .left, revision: .scratchpad(mutation))
            assertValidationError(
                .staleSource(.left),
                plan: scratchpadPlan,
                validation: replacingValidation(scratchpadValidation, sources: sources)
            )
        }
    }

    func testObservedAuthorityGenerationResourceAndCoverageBecomeStaleIndependently() throws {
        let result = try plan(request(sides: fileSides()))
        let exact = validation(for: result)
        let planned = exact.authorities[0]
        let resource = planned.resource
        let mutations = [
            Workflow.AccessAuthority(
                reference: .init(identity: planned.reference.identity, generation: planned.reference.generation + 1),
                resource: resource,
                coverage: planned.coverage,
                permissions: planned.permissions
            ),
            Workflow.AccessAuthority(
                reference: planned.reference,
                resource: Workflow.CanonicalIdentity(
                    kind: .directory,
                    canonicalURL: URL(fileURLWithPath: "/unified/authority-folder", isDirectory: true),
                    node: resource.node
                ),
                coverage: planned.coverage,
                permissions: planned.permissions
            ),
            Workflow.AccessAuthority(
                reference: planned.reference,
                resource: Workflow.CanonicalIdentity(
                    kind: resource.kind,
                    canonicalURL: URL(filePath: "/unified/authority-file.txt"),
                    node: resource.node
                ),
                coverage: planned.coverage,
                permissions: planned.permissions
            ),
            Workflow.AccessAuthority(
                reference: planned.reference,
                resource: Workflow.CanonicalIdentity(
                    kind: resource.kind,
                    canonicalURL: resource.canonicalURL,
                    node: .init(
                        volumeID: resource.node.volumeID + 1,
                        nodeID: resource.node.nodeID,
                        generation: resource.node.generation
                    )
                ),
                coverage: planned.coverage,
                permissions: planned.permissions
            ),
            Workflow.AccessAuthority(
                reference: planned.reference,
                resource: Workflow.CanonicalIdentity(
                    kind: resource.kind,
                    canonicalURL: resource.canonicalURL,
                    node: .init(
                        volumeID: resource.node.volumeID,
                        nodeID: resource.node.nodeID + 1,
                        generation: resource.node.generation
                    )
                ),
                coverage: planned.coverage,
                permissions: planned.permissions
            ),
            Workflow.AccessAuthority(
                reference: planned.reference,
                resource: Workflow.CanonicalIdentity(
                    kind: resource.kind,
                    canonicalURL: resource.canonicalURL,
                    node: .init(
                        volumeID: resource.node.volumeID,
                        nodeID: resource.node.nodeID,
                        generation: resource.node.generation + 1
                    )
                ),
                coverage: planned.coverage,
                permissions: planned.permissions
            ),
            Workflow.AccessAuthority(
                reference: planned.reference,
                resource: planned.resource,
                coverage: .directoryTree,
                permissions: planned.permissions
            ),
            Workflow.AccessAuthority(
                reference: planned.reference,
                resource: resource,
                coverage: planned.coverage,
                permissions: [.read, .create]
            )
        ]
        for mutation in mutations {
            var authorities = exact.authorities
            authorities[0] = mutation
            assertValidationError(
                .staleAuthority(planned.reference),
                plan: result,
                validation: replacingValidation(exact, authorities: authorities)
            )
        }
    }

    func testPlanDigestAndRequestCASCoverIsolatedSemanticLeaves() throws {
        let baselineRequest = request(
            sides: fileSides(),
            transforms: transformSelections(),
            comparisonOptions: exactOptions(mode: .text, data: Data("options".utf8)),
            projectSaveIntent: projectSaveIntent(format: .macMerge, existing: false),
            compareButtonIntent: .compareAs(.text)
        )
        let baseline = try plan(baselineRequest)
        let left = baselineRequest.sides[0]
        let sourceRevision = try XCTUnwrap(fileRevision(from: left.source.revision))
        let attestationMutation = replacingRequestedURL(left, with: URL(filePath: "/entered/left.txt"))
        let projectMutation = replacingProjectRequestedURL(
            try XCTUnwrap(baselineRequest.projectSaveIntent),
            with: URL(filePath: "/requested/renamed.macmerge")
        )
        var mutations = [
            replacingRequest(baselineRequest, sides: [attestationMutation, baselineRequest.sides[1]]),
            replacingRequest(
                baselineRequest,
                sides: [
                    replacingAccessReference(left, with: .init(identity: uuid(998), generation: access(from: left).reference.generation)),
                    baselineRequest.sides[1]
                ]
            ),
            replacingRequest(
                baselineRequest,
                sides: [
                    replacingAccessReference(
                        left,
                        with: .init(identity: access(from: left).reference.identity, generation: access(from: left).reference.generation + 1)
                    ),
                    baselineRequest.sides[1]
                ]
            ),
            replacingRequest(
                baselineRequest,
                sides: [
                    replacingAccess(
                        left,
                        with: Workflow.AccessAuthority(
                            reference: access(from: left).reference,
                            resource: access(from: left).resource,
                            coverage: access(from: left).coverage,
                            permissions: [.read, .create]
                        )
                    ),
                    baselineRequest.sides[1]
                ]
            ),
            replacingRequest(baselineRequest, sides: [replacingOrigin(left, with: .entered(editRevision: 2)), baselineRequest.sides[1]]),
            replacingRequest(
                baselineRequest,
                transforms: .init(unpacker: nil, prediffer: baselineRequest.transforms.prediffer)
            ),
            replacingRequest(
                baselineRequest,
                transforms: .init(unpacker: baselineRequest.transforms.unpacker, prediffer: nil)
            ),
            replacingRequest(
                baselineRequest,
                transforms: .init(
                    unpacker: transform(.unpacker, identifier: "unpack-2"),
                    prediffer: baselineRequest.transforms.prediffer
                )
            ),
            replacingRequest(
                baselineRequest,
                transforms: .init(
                    unpacker: transform(.unpacker, identifier: "unpack", revision: 2),
                    prediffer: baselineRequest.transforms.prediffer
                )
            ),
            replacingRequest(
                baselineRequest,
                transforms: .init(
                    unpacker: transform(.unpacker, identifier: "unpack", policy: digest("changed-policy")),
                    prediffer: baselineRequest.transforms.prediffer
                )
            ),
            replacingRequest(
                baselineRequest,
                transforms: .init(
                    unpacker: transform(.unpacker, identifier: "unpack", configuration: digest("changed-configuration")),
                    prediffer: baselineRequest.transforms.prediffer
                )
            ),
            replacingRequest(baselineRequest, comparisonOptions: .defaults(mode: .text)),
            replacingRequest(
                baselineRequest,
                comparisonOptions: exactOptions(mode: .text, schemaIdentifier: "schema.v2", data: Data("options".utf8))
            ),
            replacingRequest(
                baselineRequest,
                comparisonOptions: exactOptions(mode: .text, schemaRevision: 2, data: Data("options".utf8))
            ),
            replacingRequest(baselineRequest, comparisonOptions: exactOptions(mode: .text, data: Data("changed".utf8))),
            replacingRequest(baselineRequest, projectSaveIntent: .some(projectMutation)),
            replacingRequest(baselineRequest, projectSaveIntent: .some(nil)),
            replacingRequest(baselineRequest, projectSaveIntent: projectSaveIntent(format: .winMerge, existing: false)),
            replacingRequest(
                baselineRequest,
                projectSaveIntent: projectSaveIntent(format: .macMerge, existing: false, path: "/projects/renamed.macmerge")
            ),
            replacingRequest(
                baselineRequest,
                projectSaveIntent: projectSaveIntent(
                    format: .macMerge,
                    existing: false,
                    path: "/other/new.macmerge",
                    parentPath: "/other"
                )
            ),
            replacingRequest(baselineRequest, projectSaveIntent: projectSaveIntent(format: .macMerge, existing: true)),
            replacingRequest(
                baselineRequest,
                projectSaveIntent: .some(
                    replacingProjectAuthorityReference(
                        try XCTUnwrap(baselineRequest.projectSaveIntent),
                        with: .init(identity: uuid(997), generation: 1)
                    )
                )
            ),
            replacingRequest(
                baselineRequest,
                projectSaveIntent: .some(
                    replacingProjectAccess(
                        try XCTUnwrap(baselineRequest.projectSaveIntent),
                        permissions: [.read, .create]
                    )
                )
            ),
            replacingRequest(baselineRequest, limits: makeLimits(maximumItemCount: 1_023))
        ]
        for revision in fileRevisionLeafMutations(sourceRevision) {
            mutations.append(
                replacingRequest(
                    baselineRequest,
                    sides: [replacingFileRevision(left, with: revision), baselineRequest.sides[1]]
                )
            )
        }
        for mutation in mutations {
            assertDigestAndCASChanges(from: baseline, to: mutation)
        }

        let primaryRequest = replacingRequest(baselineRequest, compareButtonIntent: .primary)
        let primaryPlan = try plan(primaryRequest)
        assertDigestAndCASChanges(
            from: primaryPlan,
            to: replacingRequest(
                primaryRequest,
                comparisonOptions: exactOptions(mode: .binary, data: Data("options".utf8))
            )
        )

        let browseRequest = replacingRequest(
            baselineRequest,
            sides: [replacingOrigin(left, with: .browse(session: uuid(10), selectionIndex: 1)), baselineRequest.sides[1]]
        )
        let browsePlan = try plan(browseRequest)
        for origin in [
            Workflow.SelectionOrigin.browse(session: uuid(11), selectionIndex: 1),
            .browse(session: uuid(10), selectionIndex: 2)
        ] {
            assertDigestAndCASChanges(
                from: browsePlan,
                to: replacingRequest(browseRequest, sides: [replacingOrigin(browseRequest.sides[0], with: origin), browseRequest.sides[1]])
            )
        }

        let historyRequest = replacingRequest(
            baselineRequest,
            sides: [replacingOrigin(left, with: .history(entryIdentifier: "recent/1", revision: 1)), baselineRequest.sides[1]]
        )
        let historyPlan = try plan(historyRequest)
        for origin in [
            Workflow.SelectionOrigin.history(entryIdentifier: "recent/2", revision: 1),
            .history(entryIdentifier: "recent/1", revision: 2)
        ] {
            assertDigestAndCASChanges(
                from: historyPlan,
                to: replacingRequest(historyRequest, sides: [replacingOrigin(historyRequest.sides[0], with: origin), historyRequest.sides[1]])
            )
        }

        let folderRequest = request(
            sides: [folderInput(.left, seed: 1), folderInput(.right, seed: 2)],
            recursive: true,
            filter: filterSelection()
        )
        let folderPlan = try plan(folderRequest)
        let folderRevision = try XCTUnwrap(folderRevision(from: folderRequest.sides[0].source.revision))
        var folderMutations = folderRevisionLeafMutations(folderRevision).map { revision in
            replacingRequest(
                folderRequest,
                sides: [replacingFolderRevision(folderRequest.sides[0], with: revision), folderRequest.sides[1]]
            )
        }
        folderMutations.append(contentsOf: [
            replacingRequest(folderRequest, filter: .some(nil)),
            replacingRequest(
                folderRequest,
                filter: .some(.init(identifier: "filter-2", revision: 2, definitionSHA256: digest("filter")))
            ),
            replacingRequest(
                folderRequest,
                filter: .some(.init(identifier: "filter.swift", revision: 3, definitionSHA256: digest("filter")))
            ),
            replacingRequest(
                folderRequest,
                filter: .some(.init(identifier: "filter.swift", revision: 2, definitionSHA256: digest("changed-filter")))
            )
        ])
        for mutation in folderMutations {
            assertDigestAndCASChanges(from: folderPlan, to: mutation)
        }

        let scratchpadRequest = request(
            sides: [scratchpadInput(.left, seed: 1, text: "left", label: "label"), scratchpadInput(.right, seed: 2, text: "right")]
        )
        let scratchpadPlan = try plan(scratchpadRequest)
        let scratchpadMutations = [
            replacingScratchpad(scratchpadRequest.sides[0], identity: uuid(999)),
            replacingScratchpad(scratchpadRequest.sides[0], generation: 2),
            replacingScratchpad(scratchpadRequest.sides[0], text: "swap"),
            replacingScratchpad(scratchpadRequest.sides[0], label: .some("other"))
        ]
        for mutation in scratchpadMutations {
            assertDigestAndCASChanges(
                from: scratchpadPlan,
                to: replacingRequest(scratchpadRequest, sides: [mutation, scratchpadRequest.sides[1]])
            )
        }

        let projectBrowse = try XCTUnwrap(baselineRequest.projectSaveIntent)
        for origin in [
            Workflow.SelectionOrigin.browse(session: uuid(100), selectionIndex: 1),
            .browse(session: uuid(99), selectionIndex: 2),
            .history(entryIdentifier: "project/1", revision: 1),
            .entered(editRevision: 1)
        ] {
            assertDigestAndCASChanges(
                from: baseline,
                to: replacingRequest(
                    baselineRequest,
                    projectSaveIntent: .some(replacingProjectOrigin(projectBrowse, with: origin))
                )
            )
        }
    }

    func testEveryLimitSubfieldParticipatesInPlanDigestAndRequestCAS() throws {
        let baselineRequest = request(sides: fileSides())
        let baseline = try plan(baselineRequest)
        let mutations = [
            makeLimits(maximumPathUTF8Bytes: 65_535),
            makeLimits(maximumTotalPathUTF8Bytes: 524_287),
            makeLimits(maximumStringUTF8Bytes: 65_535),
            makeLimits(maximumTotalStringUTF8Bytes: 2_097_151),
            makeLimits(maximumLabelUTF8Bytes: 4_095),
            makeLimits(maximumScratchpadUTF8Bytes: 67_108_863),
            makeLimits(maximumCombinedScratchpadUTF8Bytes: 201_326_591),
            makeLimits(maximumOptionBytes: 4_194_303),
            makeLimits(maximumItemCount: 1_023),
            makeLimits(maximumDeclaredBytes: (1 << 40) - 1),
            makeLimits(maximumDeclaredItems: 99_999_999),
            makeLimits(maximumRetainedBytes: 234_881_023),
            makeLimits(maximumWorkUnits: 536_870_911),
            makeLimits(cancellationCheckInterval: 4_095)
        ]
        for limits in mutations {
            assertDigestAndCASChanges(from: baseline, to: replacingRequest(baselineRequest, limits: limits))
        }
    }

    func testInvalidLimitsNameEveryGuardAndAcceptHardBoundaries() throws {
        let valid = makeLimits(
            maximumPathUTF8Bytes: Workflow.Limits.hardMaximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: Workflow.Limits.hardMaximumTotalPathUTF8Bytes,
            maximumStringUTF8Bytes: Workflow.Limits.hardMaximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: Workflow.Limits.hardMaximumTotalStringUTF8Bytes,
            maximumLabelUTF8Bytes: Workflow.Limits.hardMaximumLabelUTF8Bytes,
            maximumScratchpadUTF8Bytes: Workflow.Limits.hardMaximumScratchpadUTF8Bytes,
            maximumCombinedScratchpadUTF8Bytes: Workflow.Limits.hardMaximumCombinedScratchpadUTF8Bytes,
            maximumOptionBytes: Workflow.Limits.hardMaximumOptionBytes,
            maximumItemCount: Workflow.Limits.hardMaximumItemCount,
            maximumDeclaredBytes: Workflow.Limits.hardMaximumDeclaredBytes,
            maximumDeclaredItems: Workflow.Limits.hardMaximumDeclaredItems,
            maximumRetainedBytes: Workflow.Limits.hardMaximumRetainedBytes,
            maximumWorkUnits: Workflow.Limits.hardMaximumWorkUnits,
            cancellationCheckInterval: Workflow.Limits.hardMaximumCancellationCheckInterval
        )
        XCTAssertNoThrow(try plan(request(sides: fileSides(), limits: valid)))
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: [scratchpadInput(.left, seed: 1, text: ""), scratchpadInput(.right, seed: 2, text: "")],
                    limits: makeLimits(
                        maximumScratchpadUTF8Bytes: 0,
                        maximumCombinedScratchpadUTF8Bytes: 0
                    )
                )
            )
        )
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: fileSides(),
                    comparisonOptions: exactOptions(mode: .text, data: Data()),
                    limits: makeLimits(maximumOptionBytes: 0)
                )
            )
        )

        let invalid: [(Workflow.Limits, Workflow.Limit)] = [
            (makeLimits(maximumPathUTF8Bytes: 0), .pathUTF8Bytes),
            (makeLimits(maximumPathUTF8Bytes: Workflow.Limits.hardMaximumPathUTF8Bytes + 1), .pathUTF8Bytes),
            (makeLimits(maximumPathUTF8Bytes: 2, maximumTotalPathUTF8Bytes: 1), .totalPathUTF8Bytes),
            (makeLimits(maximumTotalPathUTF8Bytes: Workflow.Limits.hardMaximumTotalPathUTF8Bytes + 1), .totalPathUTF8Bytes),
            (makeLimits(maximumStringUTF8Bytes: 0), .stringUTF8Bytes),
            (makeLimits(maximumStringUTF8Bytes: Workflow.Limits.hardMaximumStringUTF8Bytes + 1), .stringUTF8Bytes),
            (makeLimits(maximumStringUTF8Bytes: 2, maximumTotalStringUTF8Bytes: 1), .totalStringUTF8Bytes),
            (makeLimits(maximumTotalStringUTF8Bytes: Workflow.Limits.hardMaximumTotalStringUTF8Bytes + 1), .totalStringUTF8Bytes),
            (makeLimits(maximumLabelUTF8Bytes: 0), .labelUTF8Bytes),
            (makeLimits(maximumLabelUTF8Bytes: Workflow.Limits.hardMaximumLabelUTF8Bytes + 1), .labelUTF8Bytes),
            (makeLimits(maximumScratchpadUTF8Bytes: Workflow.Limits.hardMaximumScratchpadUTF8Bytes + 1), .scratchpadUTF8Bytes),
            (makeLimits(maximumScratchpadUTF8Bytes: 2, maximumCombinedScratchpadUTF8Bytes: 1), .combinedScratchpadUTF8Bytes),
            (
                makeLimits(maximumCombinedScratchpadUTF8Bytes: Workflow.Limits.hardMaximumCombinedScratchpadUTF8Bytes + 1),
                .combinedScratchpadUTF8Bytes
            ),
            (makeLimits(maximumOptionBytes: Workflow.Limits.hardMaximumOptionBytes + 1), .optionBytes),
            (makeLimits(maximumItemCount: 0), .itemCount),
            (makeLimits(maximumItemCount: Workflow.Limits.hardMaximumItemCount + 1), .itemCount),
            (makeLimits(maximumDeclaredBytes: 0), .declaredBytes),
            (makeLimits(maximumDeclaredBytes: Workflow.Limits.hardMaximumDeclaredBytes + 1), .declaredBytes),
            (makeLimits(maximumDeclaredItems: 0), .declaredItems),
            (makeLimits(maximumDeclaredItems: Workflow.Limits.hardMaximumDeclaredItems + 1), .declaredItems),
            (makeLimits(maximumRetainedBytes: 0), .retainedBytes),
            (makeLimits(maximumRetainedBytes: Workflow.Limits.hardMaximumRetainedBytes + 1), .retainedBytes),
            (makeLimits(maximumWorkUnits: 0), .workUnits),
            (makeLimits(maximumWorkUnits: Workflow.Limits.hardMaximumWorkUnits + 1), .workUnits),
            (makeLimits(cancellationCheckInterval: 0), .cancellationCheckInterval),
            (makeLimits(cancellationCheckInterval: Workflow.Limits.hardMaximumCancellationCheckInterval + 1), .cancellationCheckInterval)
        ]
        for (limits, field) in invalid {
            assertError(.invalidLimit(field)) { try plan(request(sides: fileSides(), limits: limits)) }
        }
    }

    func testPathStringAndOptionLimitsAcceptExactBytesThenRejectOneMore() throws {
        let shortPath = "/a"
        let exactPath = makeLimits(maximumPathUTF8Bytes: shortPath.utf8.count)
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: [fileInput(.left, seed: 1, path: shortPath), fileInput(.right, seed: 2, path: "/b")],
                    comparisonOptions: .defaults(mode: .text),
                    limits: exactPath
                )
            )
        )
        assertError(.stringLimitExceeded(field: .path, maximumUTF8Bytes: 1)) {
            try plan(
                request(
                    sides: [fileInput(.left, seed: 1, path: shortPath), fileInput(.right, seed: 2, path: "/b")], limits: makeLimits(maximumPathUTF8Bytes: 1))
            )
        }

        let identifier = "abcd"
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: [folderInput(.left, seed: 1), folderInput(.right, seed: 2)],
                    filter: filterSelection(identifier: identifier),
                    limits: makeLimits(maximumStringUTF8Bytes: identifier.utf8.count)
                )
            )
        )
        assertError(.invalidFilterSelection) {
            try plan(
                request(
                    sides: [folderInput(.left, seed: 1), folderInput(.right, seed: 2)],
                    filter: filterSelection(identifier: identifier + "x"),
                    limits: makeLimits(maximumStringUTF8Bytes: identifier.utf8.count)
                )
            )
        }

        let historyIdentifier = "abcd"
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: [
                        fileInput(.left, seed: 1, origin: .history(entryIdentifier: historyIdentifier, revision: 1)),
                        fileInput(.right, seed: 2)
                    ],
                    limits: makeLimits(maximumStringUTF8Bytes: historyIdentifier.utf8.count)
                )
            )
        )
        assertError(.stringLimitExceeded(field: .historyIdentifier, maximumUTF8Bytes: 4)) {
            try plan(
                request(
                    sides: [
                        fileInput(.left, seed: 1, origin: .history(entryIdentifier: historyIdentifier + "x", revision: 1)),
                        fileInput(.right, seed: 2)
                    ],
                    limits: makeLimits(maximumStringUTF8Bytes: historyIdentifier.utf8.count)
                )
            )
        }

        let schemaIdentifier = "abcd"
        let schemaData = Data()
        let schemaOptions = Workflow.ComparisonOptions.exact(
            .init(
                mode: .text,
                schemaIdentifier: schemaIdentifier,
                schemaRevision: 1,
                canonicalData: schemaData,
                dataSHA256: digest(schemaData)
            )
        )
        XCTAssertNoThrow(
            try plan(
                request(
                    sides: fileSides(),
                    comparisonOptions: schemaOptions,
                    limits: makeLimits(maximumStringUTF8Bytes: schemaIdentifier.utf8.count)
                )
            )
        )
        let longSchemaOptions = Workflow.ComparisonOptions.exact(
            .init(
                mode: .text,
                schemaIdentifier: schemaIdentifier + "x",
                schemaRevision: 1,
                canonicalData: schemaData,
                dataSHA256: digest(schemaData)
            )
        )
        assertError(.stringLimitExceeded(field: .schemaIdentifier, maximumUTF8Bytes: 4)) {
            try plan(
                request(
                    sides: fileSides(),
                    comparisonOptions: longSchemaOptions,
                    limits: makeLimits(maximumStringUTF8Bytes: schemaIdentifier.utf8.count)
                )
            )
        }

        let optionsData = Data([1, 2, 3])
        XCTAssertNoThrow(
            try plan(
                request(sides: fileSides(), comparisonOptions: exactOptions(mode: .text, data: optionsData), limits: makeLimits(maximumOptionBytes: 3))
            )
        )
        assertError(.optionDataTooLarge(maximumBytes: 2)) {
            try plan(
                request(sides: fileSides(), comparisonOptions: exactOptions(mode: .text, data: optionsData), limits: makeLimits(maximumOptionBytes: 2))
            )
        }
    }

    func testTotalPathTotalStringItemAndRetainedLimitsUseExactBoundaries() throws {
        let sides = fileSides()
        let requiredPathBytes = 190
        XCTAssertNoThrow(
            try plan(request(sides: sides, limits: makeLimits(maximumPathUTF8Bytes: 32, maximumTotalPathUTF8Bytes: requiredPathBytes)))
        )
        assertError(.totalPathLimitExceeded(maximumUTF8Bytes: requiredPathBytes - 1)) {
            try plan(request(sides: sides, limits: makeLimits(maximumPathUTF8Bytes: 32, maximumTotalPathUTF8Bytes: requiredPathBytes - 1)))
        }

        let longLabel = String(repeating: "a", count: 40)
        let stringRequest: (Workflow.Limits) -> Workflow.Request = { limits in
            self.request(
                sides: [
                    self.scratchpadInput(.left, seed: 1, label: longLabel),
                    self.scratchpadInput(.middle, seed: 2, label: longLabel),
                    self.scratchpadInput(.right, seed: 3, label: longLabel)
                ],
                limits: limits
            )
        }
        let requiredStringBytes = 120
        XCTAssertNoThrow(
            try plan(stringRequest(makeLimits(maximumStringUTF8Bytes: 40, maximumTotalStringUTF8Bytes: requiredStringBytes)))
        )
        assertError(.totalStringLimitExceeded(maximumUTF8Bytes: requiredStringBytes - 1)) {
            try plan(stringRequest(makeLimits(maximumStringUTF8Bytes: 40, maximumTotalStringUTF8Bytes: requiredStringBytes - 1)))
        }

        XCTAssertNoThrow(try plan(request(sides: sides, limits: makeLimits(maximumItemCount: 3))))
        assertError(.itemLimitExceeded(maximumItems: 2)) {
            try plan(request(sides: sides, limits: makeLimits(maximumItemCount: 2)))
        }

        let filteredRequest: (Int) -> Workflow.Request = { maximum in
            self.request(
                sides: [self.folderInput(.left, seed: 1), self.folderInput(.right, seed: 2)],
                filter: self.filterSelection(),
                limits: self.makeLimits(maximumItemCount: maximum)
            )
        }
        XCTAssertNoThrow(try plan(filteredRequest(4)))
        assertError(.itemLimitExceeded(maximumItems: 3)) { try plan(filteredRequest(3)) }

        let transformedAndSavedRequest: (Int) -> Workflow.Request = { maximum in
            self.request(
                sides: self.fileSides(),
                transforms: self.transformSelections(),
                comparisonOptions: .defaults(mode: .text),
                projectSaveIntent: self.projectSaveIntent(format: .macMerge, existing: false),
                limits: self.makeLimits(maximumItemCount: maximum)
            )
        }
        XCTAssertNoThrow(try plan(transformedAndSavedRequest(6)))
        assertError(.itemLimitExceeded(maximumItems: 5)) {
            try plan(transformedAndSavedRequest(5))
        }

        let requiredRetained: UInt64 = 450
        XCTAssertNoThrow(try plan(request(sides: sides, limits: makeLimits(maximumRetainedBytes: requiredRetained))))
        assertError(.retainedDataTooLarge(maximumBytes: requiredRetained - 1)) {
            try plan(request(sides: sides, limits: makeLimits(maximumRetainedBytes: requiredRetained - 1)))
        }
    }

    func testWorkLimitBoundaryAndCancellationChecksAreDeterministic() throws {
        let sides = [scratchpadInput(.left, seed: 1, text: "abcdefgh"), scratchpadInput(.right, seed: 2, text: "ijklmnop")]
        let requiredWork: UInt64 = 600
        XCTAssertNoThrow(
            try plan(request(sides: sides, limits: makeLimits(maximumWorkUnits: requiredWork, cancellationCheckInterval: 4)))
        )
        assertError(.workLimitExceeded(maximumUnits: requiredWork - 1)) {
            try plan(request(sides: sides, limits: makeLimits(maximumWorkUnits: requiredWork - 1, cancellationCheckInterval: 4)))
        }

        let counter = CancellationCounter(cancelOnCall: nil)
        _ = try plan(
            request(sides: sides, limits: makeLimits(cancellationCheckInterval: 4)),
            cancellationCheck: { try counter.check() }
        )
        XCTAssertEqual(counter.calls, 152)

        for cancellationCall in [1, 2, counter.calls] {
            let cancelling = CancellationCounter(cancelOnCall: cancellationCall)
            assertError(.cancelled) {
                try plan(
                    request(sides: sides, limits: makeLimits(cancellationCheckInterval: 4)),
                    cancellationCheck: { try cancelling.check() }
                )
            }
            XCTAssertEqual(cancelling.calls, cancellationCall)
        }
    }

    func testCancellationCadenceAtMinimumMaximumAndTextChunkBoundaries() throws {
        let sides = [scratchpadInput(.left, seed: 1, text: "abcdefgh"), scratchpadInput(.right, seed: 2, text: "ijklmnop")]
        for (interval, expectedCalls) in [(UInt64(1), 602), (Workflow.Limits.hardMaximumCancellationCheckInterval, 2)] {
            let counter = CancellationCounter(cancelOnCall: nil)
            _ = try plan(
                request(sides: sides, limits: makeLimits(cancellationCheckInterval: interval)),
                cancellationCheck: { try counter.check() }
            )
            XCTAssertEqual(counter.calls, expectedCalls)
        }

        let chunkCases = [(text: "abc", work: UInt64(574), calls: 145), (text: "abcd", work: 576, calls: 146), (text: "abcde", work: 578, calls: 146)]
        for value in chunkCases {
            let counter = CancellationCounter(cancelOnCall: nil)
            let result = try plan(
                request(
                    sides: [scratchpadInput(.left, seed: 1, text: value.text), scratchpadInput(.right, seed: 2, text: "")],
                    limits: makeLimits(cancellationCheckInterval: 4)
                ),
                cancellationCheck: { try counter.check() }
            )
            XCTAssertEqual(result.receipt.planningWorkUnits, value.work)
            XCTAssertEqual(counter.calls, value.calls)
        }

        for (length, expectedCalls) in [(3, 543), (4, 543), (5, 544)] {
            let counter = CancellationCounter(cancelOnCall: nil)
            _ = try plan(
                request(
                    sides: fileSides(),
                    comparisonOptions: exactOptions(mode: .text, data: Data(repeating: 1, count: length)),
                    limits: makeLimits(cancellationCheckInterval: 4)
                ),
                cancellationCheck: { try counter.check() }
            )
            XCTAssertEqual(counter.calls, expectedCalls)
        }

        let exactBoundaryCancellation = CancellationCounter(cancelOnCall: 543)
        assertError(.cancelled) {
            try plan(
                request(
                    sides: fileSides(),
                    comparisonOptions: exactOptions(mode: .text, data: Data(repeating: 1, count: 4)),
                    limits: makeLimits(cancellationCheckInterval: 4)
                ),
                cancellationCheck: { try exactBoundaryCancellation.check() }
            )
        }
    }

    func testExpectedReferencePreconditionAndCancellationPrecedenceAreExact() throws {
        let actual = Workflow.RequestReference(identity: uuid(1), generation: 2)
        let expected = Workflow.RequestReference(identity: uuid(1), generation: 1)
        let value = request(reference: actual, sides: fileSides())
        assertError(.staleRequest(expected: expected, actual: actual)) {
            try plan(value, expecting: expected)
        }

        assertError(.cancelled) {
            try plan(value, expecting: expected, cancellationCheck: { throw CancellationError() })
        }
        let invalidLimits = replacingRequest(value, limits: makeLimits(maximumItemCount: 0))
        assertError(.invalidLimit(.itemCount)) {
            try plan(invalidLimits, expecting: expected)
        }
    }

    func testPublicValuesAreSendableAcrossTaskBoundary() async throws {
        let request = request(sides: fileSides())
        let result = try await Task.detached { try Workflow.Planner.plan(request, cancellationCheck: {}) }.value
        let validation = validation(for: result)
        try await Task.detached {
            try result.validateForExecution(validation)
            try result.validateForPublication(validation)
        }.value
        XCTAssertEqual(result.request, request)
    }

    private enum SourceCase {
        case file
        case folder
    }

    private func plan(
        _ request: Workflow.Request,
        expecting expected: Workflow.RequestReference? = nil,
        cancellationCheck: @escaping Workflow.CancellationCheck = {}
    ) throws -> Workflow.Plan {
        try Workflow.Planner.plan(request, expecting: expected, cancellationCheck: cancellationCheck)
    }

    private func request(
        reference: Workflow.RequestReference = .init(
            identity: UUID(uuidString: "00000000-0000-0000-0000-0000000000C8")!,
            generation: 3
        ),
        sides: [Workflow.SideInput],
        recursive: Bool = false,
        filter: Workflow.FilterSelection? = nil,
        transforms: Workflow.TransformSelections = .init(),
        comparisonOptions: Workflow.ComparisonOptions = .defaults(mode: .automatic),
        projectSaveIntent: Workflow.ProjectSaveIntent? = nil,
        compareButtonIntent: Workflow.CompareButtonIntent = .primary,
        limits: Workflow.Limits = .default
    ) -> Workflow.Request {
        Workflow.Request(
            reference: reference,
            sides: sides,
            recursive: recursive,
            filter: filter,
            transforms: transforms,
            comparisonOptions: comparisonOptions,
            projectSaveIntent: projectSaveIntent,
            compareButtonIntent: compareButtonIntent,
            limits: limits
        )
    }

    private func replacingRequest(
        _ value: Workflow.Request,
        reference: Workflow.RequestReference? = nil,
        sides: [Workflow.SideInput]? = nil,
        recursive: Bool? = nil,
        filter: Workflow.FilterSelection?? = nil,
        transforms: Workflow.TransformSelections? = nil,
        comparisonOptions: Workflow.ComparisonOptions? = nil,
        projectSaveIntent: Workflow.ProjectSaveIntent?? = nil,
        compareButtonIntent: Workflow.CompareButtonIntent? = nil,
        limits: Workflow.Limits? = nil
    ) -> Workflow.Request {
        request(
            reference: reference ?? value.reference,
            sides: sides ?? value.sides,
            recursive: recursive ?? value.recursive,
            filter: filter ?? value.filter,
            transforms: transforms ?? value.transforms,
            comparisonOptions: comparisonOptions ?? value.comparisonOptions,
            projectSaveIntent: projectSaveIntent ?? value.projectSaveIntent,
            compareButtonIntent: compareButtonIntent ?? value.compareButtonIntent,
            limits: limits ?? value.limits
        )
    }

    private func fileSides() -> [Workflow.SideInput] {
        [fileInput(.left, seed: 1), fileInput(.right, seed: 2)]
    }

    private func fileInput(
        _ side: Workflow.Side,
        seed: Int = 1,
        extension extensionName: String = "txt",
        path: String? = nil,
        requestedURL: URL? = nil,
        readOnly: Bool = false,
        origin: Workflow.SelectionOrigin = .entered(editRevision: 1),
        byteCount: UInt64 = 10
    ) -> Workflow.SideInput {
        let revision = fileRevision(
            identity: canonicalIdentity(
                kind: .regularFile,
                seed: seed,
                path: path ?? "/unified/file-\(seed).\(extensionName)"
            ),
            byteCount: byteCount
        )
        return fileInput(side, revision: revision, requestedURL: requestedURL, readOnly: readOnly, origin: origin)
    }

    private func fileInput(
        _ side: Workflow.Side,
        revision: Workflow.FileRevision,
        requestedURL: URL? = nil,
        readOnly: Bool = false,
        origin: Workflow.SelectionOrigin = .entered(editRevision: 1)
    ) -> Workflow.SideInput {
        localInput(
            side: side,
            sourceCase: .file,
            revision: .file(revision),
            requestedURL: requestedURL,
            readOnly: readOnly,
            origin: origin
        )
    }

    private func folderInput(
        _ side: Workflow.Side,
        seed: Int = 1,
        entryCount: UInt64 = 10,
        origin: Workflow.SelectionOrigin = .entered(editRevision: 1)
    ) -> Workflow.SideInput {
        folderInput(side, revision: folderRevision(seed: seed, entryCount: entryCount), origin: origin)
    }

    private func folderInput(
        _ side: Workflow.Side,
        revision: Workflow.FolderRevision,
        origin: Workflow.SelectionOrigin = .entered(editRevision: 1)
    ) -> Workflow.SideInput {
        localInput(side: side, sourceCase: .folder, revision: .folder(revision), origin: origin)
    }

    private func localInput(
        side: Workflow.Side,
        sourceCase: SourceCase,
        revision: Workflow.SourceRevision,
        selectionRevision: Workflow.SourceRevision? = nil,
        requestedURL: URL? = nil,
        readOnly: Bool = false,
        origin: Workflow.SelectionOrigin = .entered(editRevision: 1)
    ) -> Workflow.SideInput {
        let identity: Workflow.CanonicalIdentity
        switch revision {
        case .file(let value): identity = value.identity
        case .folder(let value): identity = value.identity
        case .scratchpad: preconditionFailure("Local input requires filesystem revision")
        }
        let authority = authority(
            seed: 100 + sideIndex(side),
            resource: identity,
            coverage: sourceCase == .file ? .exactItem : .directoryTree,
            permissions: [.read]
        )
        let requested = requestedURL ?? identity.canonicalURL
        let local = Workflow.LocalSource(
            requestedURL: requested,
            revision: revision,
            selection: .init(
                requestedURL: requested,
                revision: selectionRevision ?? revision,
                authority: authority.reference,
                origin: origin
            ),
            access: authority
        )
        let source: Workflow.Source = sourceCase == .file ? .file(local) : .folder(local)
        return Workflow.SideInput(side: side, source: source, readOnly: readOnly)
    }

    private func scratchpadInput(
        _ side: Workflow.Side,
        seed: Int,
        text: String = "text",
        label: String? = nil,
        identity: UUID? = nil,
        digest suppliedDigest: Data? = nil
    ) -> Workflow.SideInput {
        let revision = Workflow.ScratchpadRevision(
            identity: identity ?? uuid(300 + seed),
            generation: UInt64(seed),
            contentSHA256: suppliedDigest ?? digest(text)
        )
        return .init(side: side, source: .scratchpad(.init(revision: revision, text: text, label: label)))
    }

    private func fileRevision(
        seed: Int = 1,
        byteCount: UInt64 = 10
    ) -> Workflow.FileRevision {
        fileRevision(identity: canonicalIdentity(kind: .regularFile, seed: seed), byteCount: byteCount)
    }

    private func fileRevision(
        identity: Workflow.CanonicalIdentity,
        byteCount: UInt64 = 10,
        modificationTimeSeconds: Int64 = 10,
        modificationTimeNanoseconds: Int32 = 20,
        statusChangeTimeSeconds: Int64 = 30,
        statusChangeTimeNanoseconds: Int32 = 40,
        content: Data? = nil,
        metadata: Data? = nil
    ) -> Workflow.FileRevision {
        Workflow.FileRevision(
            identity: identity,
            byteCount: byteCount,
            modificationTimeSeconds: modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds,
            contentSHA256: content ?? digest("content-\(identity.node.nodeID)"),
            metadataSHA256: metadata ?? digest("metadata-\(identity.node.nodeID)")
        )
    }

    private func folderRevision(seed: Int, entryCount: UInt64 = 10) -> Workflow.FolderRevision {
        Workflow.FolderRevision(
            identity: canonicalIdentity(kind: .directory, seed: seed),
            entryCount: entryCount,
            treeSHA256: digest("tree-\(seed)"),
            metadataSHA256: digest("folder-metadata-\(seed)")
        )
    }

    private func canonicalIdentity(
        kind: Workflow.NodeKind,
        seed: Int,
        path: String? = nil
    ) -> Workflow.CanonicalIdentity {
        let defaultPath = kind == .directory ? "/unified/folder-\(seed)" : "/unified/file-\(seed).txt"
        return Workflow.CanonicalIdentity(
            kind: kind,
            canonicalURL: URL(fileURLWithPath: path ?? defaultPath, isDirectory: kind == .directory),
            node: .init(volumeID: 10, nodeID: UInt64(seed), generation: UInt64(seed))
        )
    }

    private func authority(
        seed: Int,
        resource: Workflow.CanonicalIdentity,
        coverage: Workflow.AuthorityCoverage,
        permissions: Workflow.AuthorityPermissions
    ) -> Workflow.AccessAuthority {
        Workflow.AccessAuthority(
            reference: .init(identity: uuid(400 + seed), generation: UInt64(seed)),
            resource: resource,
            coverage: coverage,
            permissions: permissions
        )
    }

    private func access(from input: Workflow.SideInput) -> Workflow.AccessAuthority {
        switch input.source {
        case .file(let source), .folder(let source): source.access
        case .scratchpad: preconditionFailure("Scratchpad has no authority")
        }
    }

    private func identity(from input: Workflow.SideInput) -> Workflow.CanonicalIdentity {
        switch input.source.revision {
        case .file(let revision): revision.identity
        case .folder(let revision): revision.identity
        case .scratchpad: preconditionFailure("Scratchpad has no canonical identity")
        }
    }

    private func replacingAccess(
        _ input: Workflow.SideInput,
        with authority: Workflow.AccessAuthority
    ) -> Workflow.SideInput {
        let local: Workflow.LocalSource
        let source: Workflow.Source
        switch input.source {
        case .file(let value):
            local = Workflow.LocalSource(
                requestedURL: value.requestedURL,
                revision: value.revision,
                selection: .init(
                    requestedURL: value.selection.requestedURL,
                    revision: value.selection.revision,
                    authority: authority.reference,
                    origin: value.selection.origin
                ),
                access: authority
            )
            source = .file(local)
        case .folder(let value):
            local = Workflow.LocalSource(
                requestedURL: value.requestedURL,
                revision: value.revision,
                selection: .init(
                    requestedURL: value.selection.requestedURL,
                    revision: value.selection.revision,
                    authority: authority.reference,
                    origin: value.selection.origin
                ),
                access: authority
            )
            source = .folder(local)
        case .scratchpad:
            preconditionFailure("Scratchpad has no authority")
        }
        return .init(side: input.side, source: source, readOnly: input.readOnly)
    }

    private func replacingReadOnly(_ input: Workflow.SideInput, _ readOnly: Bool) -> Workflow.SideInput {
        .init(side: input.side, source: input.source, readOnly: readOnly)
    }

    private func replacingFileRevision(
        _ input: Workflow.SideInput,
        with revision: Workflow.FileRevision
    ) -> Workflow.SideInput {
        guard case .file(let local) = input.source else { preconditionFailure("Expected file source") }
        let access = Workflow.AccessAuthority(
            reference: local.access.reference,
            resource: revision.identity,
            coverage: local.access.coverage,
            permissions: local.access.permissions
        )
        let replacement = Workflow.LocalSource(
            requestedURL: local.requestedURL,
            revision: .file(revision),
            selection: .init(
                requestedURL: local.selection.requestedURL,
                revision: .file(revision),
                authority: access.reference,
                origin: local.selection.origin
            ),
            access: access
        )
        return .init(side: input.side, source: .file(replacement), readOnly: input.readOnly)
    }

    private func replacingFolderRevision(
        _ input: Workflow.SideInput,
        with revision: Workflow.FolderRevision
    ) -> Workflow.SideInput {
        guard case .folder(let local) = input.source else { preconditionFailure("Expected folder source") }
        let access = Workflow.AccessAuthority(
            reference: local.access.reference,
            resource: revision.identity,
            coverage: local.access.coverage,
            permissions: local.access.permissions
        )
        let replacement = Workflow.LocalSource(
            requestedURL: local.requestedURL,
            revision: .folder(revision),
            selection: .init(
                requestedURL: local.selection.requestedURL,
                revision: .folder(revision),
                authority: access.reference,
                origin: local.selection.origin
            ),
            access: access
        )
        return .init(side: input.side, source: .folder(replacement), readOnly: input.readOnly)
    }

    private func replacingAccessReference(
        _ input: Workflow.SideInput,
        with reference: Workflow.AuthorityReference
    ) -> Workflow.SideInput {
        let original = access(from: input)
        return replacingAccess(
            input,
            with: .init(
                reference: reference,
                resource: original.resource,
                coverage: original.coverage,
                permissions: original.permissions
            )
        )
    }

    private func replacingRequestedURL(_ input: Workflow.SideInput, with url: URL) -> Workflow.SideInput {
        guard case .file(let local) = input.source else { preconditionFailure("Expected file source") }
        let replacement = Workflow.LocalSource(
            requestedURL: url,
            revision: local.revision,
            selection: .init(
                requestedURL: url,
                revision: local.selection.revision,
                authority: local.selection.authority,
                origin: local.selection.origin
            ),
            access: local.access
        )
        return .init(side: input.side, source: .file(replacement), readOnly: input.readOnly)
    }

    private func replacingOrigin(
        _ input: Workflow.SideInput,
        with origin: Workflow.SelectionOrigin
    ) -> Workflow.SideInput {
        guard case .file(let local) = input.source else { preconditionFailure("Expected file source") }
        let replacement = Workflow.LocalSource(
            requestedURL: local.requestedURL,
            revision: local.revision,
            selection: .init(
                requestedURL: local.selection.requestedURL,
                revision: local.selection.revision,
                authority: local.selection.authority,
                origin: origin
            ),
            access: local.access
        )
        return .init(side: input.side, source: .file(replacement), readOnly: input.readOnly)
    }

    private func replacingScratchpad(
        _ input: Workflow.SideInput,
        identity: UUID? = nil,
        generation: UInt64? = nil,
        text: String? = nil,
        label: String?? = nil
    ) -> Workflow.SideInput {
        guard case .scratchpad(let source) = input.source else {
            preconditionFailure("Expected scratchpad source")
        }
        let replacementText = text ?? source.text
        let revision = Workflow.ScratchpadRevision(
            identity: identity ?? source.revision.identity,
            generation: generation ?? source.revision.generation,
            contentSHA256: text == nil ? source.revision.contentSHA256 : digest(replacementText)
        )
        return .init(
            side: input.side,
            source: .scratchpad(
                .init(
                    revision: revision,
                    text: replacementText,
                    label: label ?? source.label
                )
            ),
            readOnly: input.readOnly
        )
    }

    private func replacingLocalSelectionRevision(
        _ local: Workflow.LocalSource,
        with revision: Workflow.SourceRevision
    ) -> Workflow.LocalSource {
        Workflow.LocalSource(
            requestedURL: local.requestedURL,
            revision: local.revision,
            selection: .init(
                requestedURL: local.selection.requestedURL,
                revision: revision,
                authority: local.selection.authority,
                origin: local.selection.origin
            ),
            access: local.access
        )
    }

    private func replacingLocalAuthorityAttestation(
        _ local: Workflow.LocalSource,
        with reference: Workflow.AuthorityReference
    ) -> Workflow.LocalSource {
        Workflow.LocalSource(
            requestedURL: local.requestedURL,
            revision: local.revision,
            selection: .init(
                requestedURL: local.selection.requestedURL,
                revision: local.selection.revision,
                authority: reference,
                origin: local.selection.origin
            ),
            access: local.access
        )
    }

    private func filterSelection(identifier: String = "filter.swift") -> Workflow.FilterSelection {
        .init(identifier: identifier, revision: 2, definitionSHA256: digest("filter"))
    }

    private func transform(
        _ capability: Workflow.TransformCapability,
        identifier: String,
        revision: UInt64 = 1,
        policy: Data? = nil,
        configuration: Data? = nil
    ) -> Workflow.TransformSelection {
        .init(
            capability: capability,
            identifier: identifier,
            revision: revision,
            policySHA256: policy ?? digest("policy-\(capability.rawValue)"),
            configurationSHA256: configuration ?? digest("configuration-\(capability.rawValue)")
        )
    }

    private func transformSelections() -> Workflow.TransformSelections {
        .init(
            unpacker: transform(.unpacker, identifier: "unpack"),
            prediffer: transform(.prediffer, identifier: "prediff")
        )
    }

    private func exactOptions(
        mode: Workflow.ComparisonMode,
        schemaIdentifier: String = "schema.v1",
        schemaRevision: UInt64 = 1,
        data: Data
    ) -> Workflow.ComparisonOptions {
        .exact(
            .init(
                mode: mode,
                schemaIdentifier: schemaIdentifier,
                schemaRevision: schemaRevision,
                canonicalData: data,
                dataSHA256: digest(data)
            )
        )
    }

    private func projectSaveIntent(
        format: Workflow.ProjectFormat,
        existing: Bool,
        path: String? = nil,
        parentPath: String = "/projects",
        existingRevision: Workflow.FileRevision? = nil,
        origin: Workflow.SelectionOrigin = .browse(session: UUID(uuidString: "00000000-0000-0000-0000-000000000063")!, selectionIndex: 1)
    ) -> Workflow.ProjectSaveIntent {
        let destinationPath = path ?? "/projects/new.\(format == .macMerge ? "macmerge" : "winmerge")"
        let destination = projectDestination(
            format: format,
            existing: existing,
            path: destinationPath,
            parentPath: parentPath,
            existingRevision: existingRevision
        )
        let resource: Workflow.CanonicalIdentity
        let coverage: Workflow.AuthorityCoverage
        let permissions: Workflow.AuthorityPermissions
        switch destination {
        case .absent(let location):
            resource = location.parent
            coverage = .directoryTree
            permissions = [.create]
        case .existing(let revision):
            resource = revision.identity
            coverage = .exactItem
            permissions = [.read, .replace]
        }
        let access = authority(seed: 90, resource: resource, coverage: coverage, permissions: permissions)
        let requested = URL(filePath: destinationPath)
        return Workflow.ProjectSaveIntent(
            format: format,
            requestedURL: requested,
            destination: destination,
            selection: .init(
                requestedURL: requested,
                destination: destination,
                authority: access.reference,
                origin: origin
            ),
            access: access
        )
    }

    private func projectDestination(
        format: Workflow.ProjectFormat,
        existing: Bool,
        path: String,
        parentPath: String = "/projects",
        existingRevision: Workflow.FileRevision? = nil
    ) -> Workflow.ProjectDestinationState {
        if existing {
            return .existing(
                existingRevision
                    ?? fileRevision(
                        identity: canonicalIdentity(kind: .regularFile, seed: 90, path: path)
                    )
            )
        }
        return .absent(
            .init(
                canonicalURL: URL(filePath: path),
                parent: canonicalIdentity(kind: .directory, seed: 89, path: parentPath)
            )
        )
    }

    private func replacingProjectAccess(
        _ value: Workflow.ProjectSaveIntent,
        permissions: Workflow.AuthorityPermissions? = nil,
        resource: Workflow.CanonicalIdentity? = nil,
        coverage: Workflow.AuthorityCoverage? = nil
    ) -> Workflow.ProjectSaveIntent {
        let access = Workflow.AccessAuthority(
            reference: value.access.reference,
            resource: resource ?? value.access.resource,
            coverage: coverage ?? value.access.coverage,
            permissions: permissions ?? value.access.permissions
        )
        return Workflow.ProjectSaveIntent(
            format: value.format,
            requestedURL: value.requestedURL,
            destination: value.destination,
            selection: .init(
                requestedURL: value.selection.requestedURL,
                destination: value.selection.destination,
                authority: access.reference,
                origin: value.selection.origin
            ),
            access: access
        )
    }

    private func replacingProjectAuthorityReference(
        _ value: Workflow.ProjectSaveIntent,
        with reference: Workflow.AuthorityReference
    ) -> Workflow.ProjectSaveIntent {
        let access = Workflow.AccessAuthority(
            reference: reference,
            resource: value.access.resource,
            coverage: value.access.coverage,
            permissions: value.access.permissions
        )
        return Workflow.ProjectSaveIntent(
            format: value.format,
            requestedURL: value.requestedURL,
            destination: value.destination,
            selection: .init(
                requestedURL: value.selection.requestedURL,
                destination: value.selection.destination,
                authority: reference,
                origin: value.selection.origin
            ),
            access: access
        )
    }

    private func replacingProjectRequestedURL(
        _ value: Workflow.ProjectSaveIntent,
        with url: URL
    ) -> Workflow.ProjectSaveIntent {
        Workflow.ProjectSaveIntent(
            format: value.format,
            requestedURL: url,
            destination: value.destination,
            selection: .init(
                requestedURL: url,
                destination: value.selection.destination,
                authority: value.selection.authority,
                origin: value.selection.origin
            ),
            access: value.access
        )
    }

    private func replacingProjectOrigin(
        _ value: Workflow.ProjectSaveIntent,
        with origin: Workflow.SelectionOrigin
    ) -> Workflow.ProjectSaveIntent {
        Workflow.ProjectSaveIntent(
            format: value.format,
            requestedURL: value.requestedURL,
            destination: value.destination,
            selection: .init(
                requestedURL: value.selection.requestedURL,
                destination: value.selection.destination,
                authority: value.selection.authority,
                origin: origin
            ),
            access: value.access
        )
    }

    private func validation(
        for plan: Workflow.Plan,
        request: Workflow.Request? = nil,
        reverseArrays: Bool = false
    ) -> Workflow.ExecutionValidation {
        let sources = plan.receipt.sourceRevisions
        let authorities = plan.authorities
        return Workflow.ExecutionValidation(
            request: request ?? plan.request,
            sources: reverseArrays ? Array(sources.reversed()) : sources,
            authorities: reverseArrays ? Array(authorities.reversed()) : authorities,
            filter: plan.request.filter,
            unpacker: plan.request.transforms.unpacker,
            prediffer: plan.request.transforms.prediffer,
            comparisonOptions: plan.request.comparisonOptions,
            projectDestination: plan.request.projectSaveIntent?.destination
        )
    }

    private func replacingValidation(
        _ value: Workflow.ExecutionValidation,
        sources: [Workflow.PositionedRevision]? = nil,
        authorities: [Workflow.AccessAuthority]? = nil,
        filter: Workflow.FilterSelection?? = nil,
        unpacker: Workflow.TransformSelection?? = nil,
        prediffer: Workflow.TransformSelection?? = nil,
        comparisonOptions: Workflow.ComparisonOptions? = nil,
        projectDestination: Workflow.ProjectDestinationState?? = nil
    ) -> Workflow.ExecutionValidation {
        .init(
            request: value.request,
            sources: sources ?? value.sources,
            authorities: authorities ?? value.authorities,
            filter: filter ?? value.filter,
            unpacker: unpacker ?? value.unpacker,
            prediffer: prediffer ?? value.prediffer,
            comparisonOptions: comparisonOptions ?? value.comparisonOptions,
            projectDestination: projectDestination ?? value.projectDestination
        )
    }

    private func makeLimits(
        maximumPathUTF8Bytes: Int = 64 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 512 * 1_024,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 2 * 1_024 * 1_024,
        maximumLabelUTF8Bytes: Int = 4 * 1_024,
        maximumScratchpadUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumCombinedScratchpadUTF8Bytes: Int = 192 * 1_024 * 1_024,
        maximumOptionBytes: Int = 4 * 1_024 * 1_024,
        maximumItemCount: Int = 1_024,
        maximumDeclaredBytes: UInt64 = 1 << 40,
        maximumDeclaredItems: UInt64 = 100_000_000,
        maximumRetainedBytes: UInt64 = 224 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 4_096
    ) -> Workflow.Limits {
        .init(
            maximumPathUTF8Bytes: maximumPathUTF8Bytes,
            maximumTotalPathUTF8Bytes: maximumTotalPathUTF8Bytes,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumLabelUTF8Bytes: maximumLabelUTF8Bytes,
            maximumScratchpadUTF8Bytes: maximumScratchpadUTF8Bytes,
            maximumCombinedScratchpadUTF8Bytes: maximumCombinedScratchpadUTF8Bytes,
            maximumOptionBytes: maximumOptionBytes,
            maximumItemCount: maximumItemCount,
            maximumDeclaredBytes: maximumDeclaredBytes,
            maximumDeclaredItems: maximumDeclaredItems,
            maximumRetainedBytes: maximumRetainedBytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func fileRevision(from revision: Workflow.SourceRevision) -> Workflow.FileRevision? {
        guard case .file(let value) = revision else { return nil }
        return value
    }

    private func folderRevision(from revision: Workflow.SourceRevision) -> Workflow.FolderRevision? {
        guard case .folder(let value) = revision else { return nil }
        return value
    }

    private func fileRevisionLeafMutations(_ value: Workflow.FileRevision) -> [Workflow.FileRevision] {
        let changedIdentityURL = Workflow.CanonicalIdentity(
            kind: value.identity.kind,
            canonicalURL: URL(filePath: "/unified/changed.txt"),
            node: value.identity.node
        )
        let changedNode = Workflow.CanonicalIdentity(
            kind: value.identity.kind,
            canonicalURL: value.identity.canonicalURL,
            node: .init(
                volumeID: value.identity.node.volumeID + 1,
                nodeID: value.identity.node.nodeID,
                generation: value.identity.node.generation
            )
        )
        let changedNodeID = Workflow.CanonicalIdentity(
            kind: value.identity.kind,
            canonicalURL: value.identity.canonicalURL,
            node: .init(
                volumeID: value.identity.node.volumeID,
                nodeID: value.identity.node.nodeID + 1_000,
                generation: value.identity.node.generation
            )
        )
        let changedNodeGeneration = Workflow.CanonicalIdentity(
            kind: value.identity.kind,
            canonicalURL: value.identity.canonicalURL,
            node: .init(
                volumeID: value.identity.node.volumeID,
                nodeID: value.identity.node.nodeID,
                generation: value.identity.node.generation + 1
            )
        )
        return [
            fileRevision(identity: changedIdentityURL, copying: value),
            fileRevision(identity: changedNode, copying: value),
            fileRevision(identity: changedNodeID, copying: value),
            fileRevision(identity: changedNodeGeneration, copying: value),
            fileRevision(copying: value, byteCount: value.byteCount + 1),
            fileRevision(copying: value, modificationTimeSeconds: value.modificationTimeSeconds + 1),
            fileRevision(copying: value, modificationTimeNanoseconds: value.modificationTimeNanoseconds + 1),
            fileRevision(copying: value, statusChangeTimeSeconds: value.statusChangeTimeSeconds + 1),
            fileRevision(copying: value, statusChangeTimeNanoseconds: value.statusChangeTimeNanoseconds + 1),
            fileRevision(copying: value, content: digest("changed-content")),
            fileRevision(copying: value, metadata: digest("changed-metadata"))
        ]
    }

    private func folderRevisionLeafMutations(_ value: Workflow.FolderRevision) -> [Workflow.FolderRevision] {
        let changedIdentityURL = Workflow.CanonicalIdentity(
            kind: value.identity.kind,
            canonicalURL: URL(fileURLWithPath: "/unified/changed-folder", isDirectory: true),
            node: value.identity.node
        )
        let changedNode = Workflow.CanonicalIdentity(
            kind: value.identity.kind,
            canonicalURL: value.identity.canonicalURL,
            node: .init(
                volumeID: value.identity.node.volumeID + 1,
                nodeID: value.identity.node.nodeID,
                generation: value.identity.node.generation
            )
        )
        let changedNodeID = Workflow.CanonicalIdentity(
            kind: value.identity.kind,
            canonicalURL: value.identity.canonicalURL,
            node: .init(
                volumeID: value.identity.node.volumeID,
                nodeID: value.identity.node.nodeID + 1_000,
                generation: value.identity.node.generation
            )
        )
        let changedNodeGeneration = Workflow.CanonicalIdentity(
            kind: value.identity.kind,
            canonicalURL: value.identity.canonicalURL,
            node: .init(
                volumeID: value.identity.node.volumeID,
                nodeID: value.identity.node.nodeID,
                generation: value.identity.node.generation + 1
            )
        )
        return [
            Workflow.FolderRevision(
                identity: changedIdentityURL,
                entryCount: value.entryCount,
                treeSHA256: value.treeSHA256,
                metadataSHA256: value.metadataSHA256
            ),
            Workflow.FolderRevision(
                identity: changedNode,
                entryCount: value.entryCount,
                treeSHA256: value.treeSHA256,
                metadataSHA256: value.metadataSHA256
            ),
            Workflow.FolderRevision(
                identity: changedNodeID,
                entryCount: value.entryCount,
                treeSHA256: value.treeSHA256,
                metadataSHA256: value.metadataSHA256
            ),
            Workflow.FolderRevision(
                identity: changedNodeGeneration,
                entryCount: value.entryCount,
                treeSHA256: value.treeSHA256,
                metadataSHA256: value.metadataSHA256
            ),
            Workflow.FolderRevision(
                identity: value.identity,
                entryCount: value.entryCount + 1,
                treeSHA256: value.treeSHA256,
                metadataSHA256: value.metadataSHA256
            ),
            Workflow.FolderRevision(
                identity: value.identity,
                entryCount: value.entryCount,
                treeSHA256: digest("changed-tree"),
                metadataSHA256: value.metadataSHA256
            ),
            Workflow.FolderRevision(
                identity: value.identity,
                entryCount: value.entryCount,
                treeSHA256: value.treeSHA256,
                metadataSHA256: digest("changed-folder-metadata")
            )
        ]
    }

    private func fileRevision(
        identity: Workflow.CanonicalIdentity? = nil,
        copying value: Workflow.FileRevision,
        byteCount: UInt64? = nil,
        modificationTimeSeconds: Int64? = nil,
        modificationTimeNanoseconds: Int32? = nil,
        statusChangeTimeSeconds: Int64? = nil,
        statusChangeTimeNanoseconds: Int32? = nil,
        content: Data? = nil,
        metadata: Data? = nil
    ) -> Workflow.FileRevision {
        fileRevision(
            identity: identity ?? value.identity,
            byteCount: byteCount ?? value.byteCount,
            modificationTimeSeconds: modificationTimeSeconds ?? value.modificationTimeSeconds,
            modificationTimeNanoseconds: modificationTimeNanoseconds ?? value.modificationTimeNanoseconds,
            statusChangeTimeSeconds: statusChangeTimeSeconds ?? value.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: statusChangeTimeNanoseconds ?? value.statusChangeTimeNanoseconds,
            content: content ?? value.contentSHA256,
            metadata: metadata ?? value.metadataSHA256
        )
    }

    private func assertValidationError(
        _ expected: Workflow.PlanningError,
        plan: Workflow.Plan,
        validation: Workflow.ExecutionValidation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertError(expected, file: file, line: line) {
            try plan.validateForExecution(validation)
        }
        assertError(expected, file: file, line: line) {
            try plan.validateForPublication(validation)
        }
    }

    private func assertDigestAndCASChanges(
        from baseline: Workflow.Plan,
        to mutation: Workflow.Request,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let changed = try plan(mutation)
            XCTAssertNotEqual(changed.receipt.planSHA256, baseline.receipt.planSHA256, file: file, line: line)
            assertValidationError(
                .staleRequestState,
                plan: baseline,
                validation: validation(for: baseline, request: mutation),
                file: file,
                line: line
            )
        } catch {
            XCTFail("Mutation must remain valid: \(error)", file: file, line: line)
        }
    }

    private func assertError<T>(
        _ expected: Workflow.PlanningError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? Workflow.PlanningError, expected, file: file, line: line)
        }
    }

    private func digest(_ string: String) -> Data {
        digest(Data(string.utf8))
    }

    private func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private func uuid(_ seed: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llX", UInt64(seed)))!
    }

    private func sideIndex(_ side: Workflow.Side) -> Int {
        switch side {
        case .left: 1
        case .middle: 2
        case .right: 3
        }
    }
}

private final class CancellationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelOnCall: Int?
    private var count = 0

    init(cancelOnCall: Int?) {
        self.cancelOnCall = cancelOnCall
    }

    var calls: Int {
        lock.withLock { count }
    }

    func check() throws {
        let shouldCancel = lock.withLock {
            count += 1
            return count == cancelOnCall
        }
        if shouldCancel { throw CancellationError() }
    }
}
