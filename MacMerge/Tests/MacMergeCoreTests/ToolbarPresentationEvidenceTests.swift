import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import MacMergeCore
import XCTest

final class ToolbarPresentationEvidenceTests: XCTestCase {
    func testCompleteEvidenceBindsCanonicalPresentationRuntimeAXAndAttachments() throws {
        let fixture = try makeFixture()
        let result = try evaluate(fixture)

        XCTAssertTrue(result.report.isEvidenceCompleteAndValid)
        XCTAssertFalse(result.report.containsErrors)
        XCTAssertNil(result.report.highestSeverity)
        XCTAssertEqual(result.report.requiredLifecycleCaptureCount, ToolbarAuditLifecycleScenario.allCases.count)
        XCTAssertEqual(result.report.completeLifecycleCaptureCount, result.report.requiredLifecycleCaptureCount)
        XCTAssertEqual(result.report.requiredWindowCaptureCount, ToolbarAuditScreenshotContext.allCases.count)
        XCTAssertEqual(result.report.completeWindowCaptureCount, result.report.requiredWindowCaptureCount)
        XCTAssertEqual(result.report.requiredInteractionCaptureCount, fixture.inventory.auditContract.interactionExpectations.count)
        XCTAssertEqual(result.report.completeInteractionCaptureCount, result.report.requiredInteractionCaptureCount)
        XCTAssertEqual(result.archive.data.prefix(8), Data("MMTBPEV5".utf8))
        XCTAssertEqual(result.archive.sha256, sha256(result.archive.data))
        XCTAssertEqual(result.receipt.evidenceArchiveSHA256, result.archive.sha256)
        XCTAssertEqual(result.receipt.verifiedAttachmentCount, 14)
        XCTAssertEqual(result.receipt.verifiedAttachmentByteCount, UInt64(fixture.payloads.values.reduce(0) { $0 + $1.count }))

        for capture in fixture.evidence.lifecycleCaptures {
            XCTAssertEqual(capture.items, ToolbarConfiguration.winMergeDefaultItems)
            XCTAssertEqual(capture.controls.map(\.command), ToolbarAuditCommand.allCases)
            XCTAssertEqual(capture.accessibilityTree.first?.accessibility.role, .toolbar)
            XCTAssertEqual(Set(capture.accessibilityTree.map(\.elementIdentity)).count, capture.accessibilityTree.count)
            for interaction in capture.interactions {
                XCTAssertTrue(capture.accessibilityTree.contains { $0.elementIdentity == interaction.elementIdentity })
            }
        }
    }

    func testInventoryCoversPrimarySecondaryWinMergeMetadataAndCanonicalGroups() throws {
        let fixture = try makeFixture()
        let contract = fixture.inventory.auditContract
        let expectedGroups: [[ToolbarAuditCommand]] = [
            [.newComparison, .openComparison, .save],
            [.undo, .redo],
            [.selectLineDifference],
            [.nextDifference, .previousDifference],
            [.nextConflict, .previousConflict],
            [.firstDifference, .currentDifference, .lastDifference],
            [.copyToRight, .copyToLeft],
            [.copyToRightAndAdvance, .copyToLeftAndAdvance],
            [.copyAllToRight, .copyAllToLeft],
            [.autoMerge],
            [.firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile],
            [.options],
            [.refresh]
        ]

        XCTAssertEqual(contract.manifest, .canonical)
        XCTAssertEqual(contract.manifest.items, ToolbarConfiguration.winMergeDefaultItems)
        XCTAssertEqual(contract.manifest.groups.map(\.commands), expectedGroups)
        XCTAssertTrue(contract.manifest.groups.allSatisfy(\.hasTrailingSeparator))
        XCTAssertEqual(contract.controls.map(\.command), ToolbarAuditCommand.allCases)
        XCTAssertEqual(contract.controls.map(\.behavior.primaryActionID), ToolbarAuditCommand.allCases.map(primaryActionID))
        XCTAssertTrue(contract.controls.allSatisfy { $0.tooltip == "WinMerge \($0.command.rawValue)" })

        let save = try XCTUnwrap(contract.controls.first { $0.command == .save })
        XCTAssertEqual(save.shortcut?.canonicalChord, "command:1:s")
        XCTAssertEqual(save.shortcut?.display, "Command-S")
        XCTAssertEqual(save.behavior.secondary.actionIDs, [toolbarID("action.save.leftAs"), toolbarID("action.save.rightAs")])
        XCTAssertEqual(Set(fixture.inventory.semanticActionBindings.map(\.actionID)), Set(contract.controls.flatMap(\.behavior.allActionIDs)))
        XCTAssertEqual(
            fixture.inventory.semanticActionBindings.first { $0.actionID == toolbarID("action.save.leftAs") }?.command,
            .saveLeftAs
        )
        XCTAssertEqual(
            fixture.inventory.semanticActionBindings.first { $0.actionID == toolbarID("action.save.rightAs") }?.command,
            .saveRightAs
        )
    }

    func testMenuPresentedItemsHaveOneToOneAXBindingsAndOwnedMenuAncestors() throws {
        let fixture = try makeFixture()
        let captures = fixture.evidence.lifecycleCaptures.filter { capture in
            capture.interactions.contains { interaction in
                if case .menuPresented = interaction.outcome { return true }
                return interaction.invocation == .menuItemSelection
            }
        }
        XCTAssertEqual(captures.count, 2)

        for capture in captures {
            let saveIdentity = controlElementID(.save, scope: captureScope(capture))
            let menu = try XCTUnwrap(
                capture.accessibilityTree.first {
                    $0.parentIdentity == saveIdentity && $0.accessibility.role == .menu
                }
            )
            let menuItems = capture.accessibilityTree.filter {
                $0.parentIdentity == menu.elementIdentity && $0.accessibility.role == .menuItem
            }
            XCTAssertEqual(menuItems.map(\.accessibility.identifier), saveSecondaryActionIDs)
            XCTAssertEqual(Set(menuItems.map(\.elementIdentity)).count, saveSecondaryActionIDs.count)
            for interaction in capture.interactions where interaction.invocation == .menuItemSelection {
                XCTAssertEqual(
                    menuItems.first { $0.accessibility.identifier == interaction.actionID }?.elementIdentity,
                    interaction.elementIdentity
                )
            }
        }
    }

    func testMenuBindingsRejectMissingDuplicateReorderedAndWrongOwnerNodes() throws {
        let fixture = try makeFixture()
        let index = try XCTUnwrap(
            fixture.evidence.lifecycleCaptures.firstIndex {
                $0.interactions.contains { $0.invocation == .menuArrowClick }
            }
        )
        let capture = fixture.evidence.lifecycleCaptures[index]
        let scope = captureScope(capture)
        let actionIdentity = menuActionElementID(saveSecondaryActionIDs[0], scope: scope)
        let menuIdentity = menuElementID(.save, scope: scope)

        let missing = replacingLifecycleCapture(
            capture,
            accessibilityTree: capture.accessibilityTree.filter { $0.elementIdentity != actionIdentity }
        )
        assertInvalidCapture(missing, at: index, in: fixture, field: .accessibilityTree)

        let duplicateNode = try XCTUnwrap(capture.accessibilityTree.first { $0.elementIdentity == actionIdentity })
        let duplicate = replacingLifecycleCapture(
            capture,
            accessibilityTree: capture.accessibilityTree
                + [
                    ToolbarPresentationAXElementObservation(
                        elementIdentity: accessibilityID("element.duplicate.menu-item"),
                        parentIdentity: menuIdentity,
                        siblingIndex: duplicateNode.siblingIndex,
                        frame: duplicateNode.frame,
                        accessibility: duplicateNode.accessibility
                    )
                ]
        )
        assertInvalidCapture(duplicate, at: index, in: fixture, field: .accessibilityTree)

        let wrongOwnerTree = capture.accessibilityTree.map { element in
            guard element.elementIdentity == menuIdentity else { return element }
            return ToolbarPresentationAXElementObservation(
                elementIdentity: element.elementIdentity,
                parentIdentity: controlElementID(.openComparison, scope: scope),
                siblingIndex: element.siblingIndex,
                frame: element.frame,
                accessibility: element.accessibility
            )
        }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: wrongOwnerTree),
            at: index,
            in: fixture,
            field: .accessibilityTree
        )

        let reorderedInteractions = capture.interactions.map { interaction in
            guard case .menuPresented(let ids) = interaction.outcome else { return interaction }
            return ToolbarPresentationInteractionCapture(
                scenario: interaction.scenario,
                controlID: interaction.controlID,
                elementIdentity: interaction.elementIdentity,
                actionID: interaction.actionID,
                invocation: interaction.invocation,
                outcome: .menuPresented(actionIDs: ids.reversed()),
                source: interaction.source
            )
        }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, interactions: reorderedInteractions),
            at: index,
            in: fixture,
            field: .interaction
        )

        let duplicateMenu = ToolbarPresentationAXElementObservation(
            elementIdentity: accessibilityID("element.duplicate.menu"),
            parentIdentity: controlElementID(.save, scope: scope),
            siblingIndex: 1,
            frame: ToolbarPresentationEvidenceRect(x: 4, y: 0, width: 2, height: 2),
            accessibility: ax(
                "ax.duplicate.menu",
                role: .menu,
                label: "",
                hint: "",
                enabled: true,
                focusable: false,
                actions: []
            )
        )
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: capture.accessibilityTree + [duplicateMenu]),
            at: index,
            in: fixture,
            field: .accessibilityTree
        )

        let menuItems = capture.accessibilityTree.filter { $0.parentIdentity == menuIdentity }
        let firstItem = try XCTUnwrap(menuItems.first { $0.siblingIndex == 0 })
        let secondItem = try XCTUnwrap(menuItems.first { $0.siblingIndex == 1 })
        let wrongSiblingOrder = capture.accessibilityTree.map { element in
            if element.elementIdentity == firstItem.elementIdentity {
                return observation(element, siblingIndex: 1)
            }
            if element.elementIdentity == secondItem.elementIdentity {
                return observation(element, siblingIndex: 0)
            }
            return element
        }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: wrongSiblingOrder),
            at: index,
            in: fixture,
            field: .accessibilityTree
        )

        let overlappingMenuItems = capture.accessibilityTree.map { element in
            guard element.elementIdentity == secondItem.elementIdentity else { return element }
            return observation(element, frame: firstItem.frame)
        }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: overlappingMenuItems),
            at: index,
            in: fixture,
            field: .accessibilityTree
        )

        let missingMenuFocus = capture.focusMovements.filter { $0.traversal != .menuNext }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, focusMovements: missingMenuFocus),
            at: index,
            in: fixture,
            field: .focusMovement
        )
    }

    func testDisabledSecondaryActionMustTargetOwnedMenuItem() throws {
        let fixture = try makeFixture()
        let index = try XCTUnwrap(
            fixture.evidence.lifecycleCaptures.firstIndex { capture in
                capture.interactions.contains {
                    saveSecondaryActionIDs.contains($0.actionID) && $0.invocation == .disabledActivation
                }
            }
        )
        let capture = fixture.evidence.lifecycleCaptures[index]
        let scope = captureScope(capture)
        let interactions = capture.interactions.map { interaction in
            guard saveSecondaryActionIDs.contains(interaction.actionID),
                interaction.invocation == .disabledActivation
            else { return interaction }
            return ToolbarPresentationInteractionCapture(
                scenario: interaction.scenario,
                controlID: interaction.controlID,
                elementIdentity: controlElementID(.save, scope: scope),
                actionID: interaction.actionID,
                invocation: interaction.invocation,
                outcome: interaction.outcome,
                source: interaction.source
            )
        }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, interactions: interactions),
            at: index,
            in: fixture,
            field: .interaction
        )
    }

    func testAXTreeRequiresToolbarRootRoleAwareMetadataDeclaredControlsAndVisualLayout() throws {
        let fixture = try makeFixture()
        let capture = fixture.evidence.lifecycleCaptures[0]
        let root = try XCTUnwrap(capture.accessibilityTree.first { $0.parentIdentity == nil })
        XCTAssertEqual(root.accessibility.role, .toolbar)
        XCTAssertEqual(root.frame, capture.captureManifest.geometry.toolbar)

        let wrongRoot = capture.accessibilityTree.map { element in
            guard element.elementIdentity == root.elementIdentity else { return element }
            return ToolbarPresentationAXElementObservation(
                elementIdentity: element.elementIdentity,
                parentIdentity: nil,
                siblingIndex: element.siblingIndex,
                frame: element.frame,
                accessibility: ax(
                    "ax.invalid.root",
                    role: .group,
                    label: "",
                    hint: "",
                    enabled: nil,
                    focusable: false,
                    actions: []
                )
            )
        }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: wrongRoot),
            at: 0,
            in: fixture,
            field: .accessibilityTree
        )

        let undeclared = ToolbarPresentationAXElementObservation(
            elementIdentity: accessibilityID("element.undeclared"),
            parentIdentity: root.elementIdentity,
            siblingIndex: capture.items.count,
            frame: ToolbarPresentationEvidenceRect(x: 0, y: 3, width: 1, height: 1),
            accessibility: ax("ax.undeclared", label: "Undeclared", hint: "Activates undeclared")
        )
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: capture.accessibilityTree + [undeclared]),
            at: 0,
            in: fixture,
            field: .accessibilityTree
        )

        var wrongOrder = capture.accessibilityTree
        let first = try XCTUnwrap(wrongOrder.firstIndex { $0.accessibility.identifier == controlID(.newComparison) })
        let second = try XCTUnwrap(wrongOrder.firstIndex { $0.accessibility.identifier == controlID(.openComparison) })
        let firstElement = wrongOrder[first]
        let secondElement = wrongOrder[second]
        wrongOrder[first] = observation(firstElement, frame: secondElement.frame)
        wrongOrder[second] = observation(secondElement, frame: firstElement.frame)
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: wrongOrder),
            at: 0,
            in: fixture,
            field: .accessibilityTree
        )

        let wrongSiblingOrder = capture.accessibilityTree.map { element in
            if element.elementIdentity == firstElement.elementIdentity {
                return observation(element, siblingIndex: secondElement.siblingIndex)
            }
            if element.elementIdentity == secondElement.elementIdentity {
                return observation(element, siblingIndex: firstElement.siblingIndex)
            }
            return element
        }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: wrongSiblingOrder),
            at: 0,
            in: fixture,
            field: .accessibilityTree
        )

        let overlapping = capture.accessibilityTree.map { element in
            guard element.elementIdentity == secondElement.elementIdentity else { return element }
            return observation(element, frame: firstElement.frame)
        }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: overlapping),
            at: 0,
            in: fixture,
            field: .accessibilityTree
        )

        let withoutSeparator = capture.accessibilityTree.filter { $0.accessibility.role != .separator }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: withoutSeparator),
            at: 0,
            in: fixture,
            field: .accessibilityTree
        )

        let invalidButton = capture.accessibilityTree.map { element in
            guard element.accessibility.identifier == controlID(.newComparison) else { return element }
            return ToolbarPresentationAXElementObservation(
                elementIdentity: element.elementIdentity,
                parentIdentity: element.parentIdentity,
                siblingIndex: element.siblingIndex,
                frame: element.frame,
                accessibility: ax(
                    element.accessibility.identifier.rawValue,
                    label: element.accessibility.label,
                    hint: element.accessibility.hint,
                    enabled: element.accessibility.isEnabled,
                    focusable: true,
                    actions: [.toggle]
                )
            )
        }
        assertInvalidCapture(
            replacingLifecycleCapture(capture, accessibilityTree: invalidButton),
            at: 0,
            in: fixture,
            field: .accessibilityTree
        )
    }

    func testFocusMovementsAreOrderedBidirectionalDistinctAndTargetRuntimeIdentities() throws {
        let fixture = try makeFixture()
        let capture = try XCTUnwrap(fixture.evidence.lifecycleCaptures.first { $0.scenario == .equal })
        let controls = focusableControls(capture.controls, items: capture.items)
        XCTAssertFalse(controls.isEmpty)
        XCTAssertEqual(
            capture.focusMovements.filter { $0.traversal == .tabForward || $0.traversal == .tabBackward }.count,
            controls.count * 2
        )

        for (index, control) in controls.enumerated() {
            let target = controlElementID(control.command, scope: captureScope(capture))
            let previous = controlElementID(
                controls[(index + controls.count - 1) % controls.count].command,
                scope: captureScope(capture)
            )
            let next = controlElementID(controls[(index + 1) % controls.count].command, scope: captureScope(capture))
            let forward = capture.focusMovements.first { $0.controlID == control.id && $0.traversal == .tabForward }
            let backward = capture.focusMovements.first { $0.controlID == control.id && $0.traversal == .tabBackward }
            XCTAssertEqual(forward?.fromElementIdentity, previous)
            XCTAssertEqual(backward?.fromElementIdentity, next)
            XCTAssertEqual(forward?.toElementIdentity, target)
            XCTAssertEqual(backward?.toElementIdentity, target)
            XCTAssertNotEqual(forward?.fromElementIdentity, forward?.toElementIdentity)
            XCTAssertNotEqual(backward?.fromElementIdentity, backward?.toElementIdentity)
        }

        let menuMovements = capture.focusMovements.filter {
            $0.traversal == .menuNext || $0.traversal == .menuPrevious
        }
        XCTAssertEqual(menuMovements.count, saveSecondaryActionIDs.count * 2)
        XCTAssertEqual(Set(menuMovements.map(\.controlID)), Set(saveSecondaryActionIDs))
    }

    func testFocusMovementAndKeyWindowRequirementsFailClosed() throws {
        let fixture = try makeFixture()
        let index = try XCTUnwrap(fixture.evidence.lifecycleCaptures.firstIndex { !$0.focusMovements.isEmpty })
        let capture = fixture.evidence.lifecycleCaptures[index]
        var movements = capture.focusMovements
        let first = movements[0]
        movements[0] = ToolbarPresentationFocusMovement(
            controlID: first.controlID,
            fromElementIdentity: first.toElementIdentity,
            toElementIdentity: first.toElementIdentity,
            traversal: first.traversal
        )
        assertInvalidCapture(
            replacingLifecycleCapture(capture, focusMovements: movements),
            at: index,
            in: fixture,
            field: .focusMovement
        )

        let nonKeyManifest = copyManifest(
            capture.captureManifest,
            windowState: ToolbarPresentationCapturedWindowState(
                isVisible: true,
                isKeyWindow: false,
                isMainWindow: true,
                isMiniaturized: false,
                isFullScreen: false
            )
        )
        assertInvalidCapture(
            replacingLifecycleCapture(capture, captureManifest: nonKeyManifest),
            at: index,
            in: fixture,
            field: .captureManifest,
            reSign: false
        )
    }

    func testSignedManifestBindsAppBuildInventoryContextStateGeometryAndRenderingPipeline() throws {
        let fixture = try makeFixture()
        let capture = fixture.evidence.lifecycleCaptures[0]
        let otherReference = reference("transplant", 999)
        let otherBinding = binding(artifact: 0xA1, signing: 0xB2)
        let resizedGeometry = ToolbarPresentationCaptureGeometry(
            window: ToolbarPresentationEvidenceRect(x: 0, y: 0, width: 41, height: 4),
            toolbar: capture.captureManifest.geometry.toolbar,
            backingScaleThousandths: capture.captureManifest.geometry.backingScaleThousandths
        )
        let reSignableManifests = try [
            copyManifest(capture.captureManifest, app: otherReference),
            copyManifest(capture.captureManifest, build: otherReference),
            copyManifest(capture.captureManifest, buildBinding: otherBinding),
            copyManifest(capture.captureManifest, inventory: otherReference),
            copyManifest(capture.captureManifest, manifest: otherReference),
            copyManifest(capture.captureManifest, layout: otherReference),
            copyManifest(capture.captureManifest, context: .lifecycle(.loading)),
            copyManifest(capture.captureManifest, stateSHA256: digest(0xF1)),
            copyManifest(capture.captureManifest, accessibilityTreeSHA256: digest(0xF2))
        ].map(signedManifest)

        for manifest in reSignableManifests {
            assertInvalidCapture(
                replacingLifecycleCapture(capture, captureManifest: manifest),
                at: 0,
                in: fixture,
                field: .captureManifest,
                reSign: false
            )
        }

        assertInvalidCapture(
            replacingLifecycleCapture(
                capture,
                captureManifest: try signedManifest(
                    copyManifest(capture.captureManifest, geometry: resizedGeometry)
                )
            ),
            at: 0,
            in: fixture,
            field: .attachment,
            reSign: false
        )

        for manifest in [
            copyManifest(capture.captureManifest, renderingPipeline: otherReference),
            copyManifest(capture.captureManifest, renderingImplementation: "untrusted renderer")
        ] {
            assertInvalidCapture(
                replacingLifecycleCapture(capture, captureManifest: manifest),
                at: 0,
                in: fixture,
                field: .captureManifest,
                reSign: false
            )
        }

        let badAuthentication = copyManifest(capture.captureManifest, authentication: digest(0xEE))
        assertInvalidCapture(
            replacingLifecycleCapture(capture, captureManifest: badAuthentication),
            at: 0,
            in: fixture,
            field: .captureManifest,
            reSign: false
        )

        let otherCollector = reference("collector.transplant", 6)
        let otherProvenance = AccessibilityEvidenceCaptureProvenance(
            capturedAtUnixMilliseconds: capture.provenance.capturedAtUnixMilliseconds,
            runNonce: capture.provenance.runNonce,
            collector: otherCollector,
            build: capture.provenance.build,
            buildBinding: capture.provenance.buildBinding
        )
        let otherCollectorManifest = copyManifest(
            capture.captureManifest,
            collector: otherCollector
        )
        let reboundCapture = replacingLifecycleCapture(
            capture,
            provenance: otherProvenance,
            captureManifest: otherCollectorManifest
        )
        let signedOtherCollectorManifest = try signedManifest(
            copyManifest(
                otherCollectorManifest,
                stateSHA256: sha256(captureStateData(reboundCapture))
            )
        )
        assertInvalidCapture(
            replacingLifecycleCapture(
                reboundCapture,
                captureManifest: signedOtherCollectorManifest
            ),
            at: 0,
            in: fixture,
            field: .captureManifest,
            reSign: false
        )
    }

    func testSignedManifestAndAttachmentCannotBeTransplantedOrReused() throws {
        let fixture = try makeFixture()
        let first = fixture.evidence.lifecycleCaptures[0]
        let second = fixture.evidence.lifecycleCaptures[1]
        assertInvalidCapture(
            replacingLifecycleCapture(first, captureManifest: second.captureManifest),
            at: 0,
            in: fixture,
            field: .captureManifest
        )

        var duplicatedCaptures = fixture.evidence.lifecycleCaptures
        duplicatedCaptures.append(first)
        let duplicated = replacingEvidence(fixture, lifecycleCaptures: duplicatedCaptures)
        let result = try evaluate(duplicated)
        XCTAssertTrue(result.report.findings.contains { $0.code == .duplicateLifecycleCapture })
        XCTAssertTrue(result.report.findings.contains { $0.code == .reusedAttachment })

        var duplicatedWindows = fixture.evidence.windowCaptures
        duplicatedWindows.append(try XCTUnwrap(duplicatedWindows.first))
        let duplicatedWindowResult = try evaluate(
            replacingEvidence(fixture, windowCaptures: duplicatedWindows)
        )
        XCTAssertTrue(
            duplicatedWindowResult.report.findings.contains { $0.code == .duplicateWindowCapture }
        )
        XCTAssertTrue(
            duplicatedWindowResult.report.findings.contains { $0.code == .reusedAttachment }
        )

        let originalAttachment = try XCTUnwrap(
            fixture.evidence.attachments.first { $0.id == first.accessibilityAttachmentID }
        )
        let orphanID = accessibilityID("attachment.orphan.same-digest")
        let orphan = ToolbarPresentationEvidenceAttachment(
            id: orphanID,
            kind: .accessibilitySnapshot,
            scenario: originalAttachment.scenario,
            manifest: originalAttachment.manifest,
            layout: originalAttachment.layout,
            provenance: originalAttachment.provenance,
            mediaType: originalAttachment.mediaType,
            byteCount: originalAttachment.byteCount,
            sha256: originalAttachment.sha256,
            contentSHA256: originalAttachment.contentSHA256,
            captureManifestSHA256: originalAttachment.captureManifestSHA256,
            source: originalAttachment.source
        )
        var payloads = fixture.payloads
        payloads[orphanID] = try XCTUnwrap(payloads[originalAttachment.id])
        let withOrphan = Fixture(
            inventory: fixture.inventory,
            evidence: evidence(
                fixture.evidence,
                attachments: fixture.evidence.attachments + [orphan]
            ),
            payloads: payloads
        )
        let orphanResult = try evaluate(withOrphan)
        XCTAssertTrue(orphanResult.report.findings.contains { $0.code == .orphanAttachment })
        XCTAssertEqual(orphanResult.report.findings.filter { $0.code == .reusedAttachmentDigest }.count, 2)
    }

    func testScreenshotAndAXAttachmentsAreIndependentAndMissingKindsStayDistinct() throws {
        let fixture = try makeFixture()
        let window = fixture.evidence.windowCaptures[0]
        XCTAssertNotEqual(window.screenshotAttachmentID, window.accessibilityAttachmentID)
        let screenshot = try XCTUnwrap(fixture.evidence.attachments.first { $0.id == window.screenshotAttachmentID })
        let accessibility = try XCTUnwrap(
            fixture.evidence.attachments.first { $0.id == window.accessibilityAttachmentID }
        )
        XCTAssertEqual(screenshot.kind, .screenshot)
        XCTAssertEqual(accessibility.kind, .accessibilitySnapshot)
        XCTAssertNotEqual(screenshot.contentSHA256, accessibility.contentSHA256)

        let withoutScreenshot = removingAttachment(window.screenshotAttachmentID, from: fixture)
        let screenshotReport = try evaluate(withoutScreenshot).report
        XCTAssertTrue(screenshotReport.findings.contains { $0.code == .missingScreenshotAttachment })
        XCTAssertFalse(screenshotReport.findings.contains { $0.code == .missingAccessibilityAttachment })

        let withoutAX = removingAttachment(window.accessibilityAttachmentID, from: fixture)
        let axReport = try evaluate(withoutAX).report
        XCTAssertTrue(axReport.findings.contains { $0.code == .missingAccessibilityAttachment })
        XCTAssertFalse(axReport.findings.contains { $0.code == .missingScreenshotAttachment })
    }

    func testAttachmentSinkStreamsChunksAndRejectsChunkAndDeclarationOverflow() throws {
        let fixture = try makeFixture()
        let limits = ToolbarPresentationEvidenceLimits(maximumAttachmentChunkBytes: 31)
        let streamed = try evaluate(fixture, limits: limits, resolver: fixture.resolver(chunkSize: 31))
        XCTAssertTrue(streamed.report.isEvidenceCompleteAndValid)

        assertWorkflowError(.invalidEvidence(.attachmentPayload)) {
            try evaluate(
                fixture,
                limits: limits,
                resolver: { id, _, sink in
                    guard let data = fixture.payloads[id] else { throw ResourceError.missing }
                    try sink.append(data)
                }
            )
        }
        assertWorkflowError(.invalidEvidence(.attachmentPayload)) {
            try evaluate(
                fixture,
                resolver: { _, declaredByteCount, sink in
                    try sink.append(Data(repeating: 0x7F, count: declaredByteCount + 1))
                }
            )
        }
    }

    func testManifestTrustRunsBeforeResolverAndResourceErrorsArePreserved() throws {
        let fixture = try makeFixture()
        let resolverProbe = LockedCounter()
        assertWorkflowError(.invalidEvidence(.captureManifest)) {
            try evaluate(
                fixture,
                resolver: { _, _, _ in resolverProbe.increment() },
                authenticator: { _, _, _, _ in false }
            )
        }
        XCTAssertEqual(resolverProbe.value, 0)

        XCTAssertThrowsError(
            try evaluate(fixture, resolver: { _, _, _ in throw ResourceError.offline })
        ) { error in
            XCTAssertEqual(error as? ResourceError, .offline)
        }
        XCTAssertThrowsError(
            try evaluate(fixture, authenticator: { _, _, _, _ in throw ResourceError.denied })
        ) { error in
            XCTAssertEqual(error as? ResourceError, .denied)
        }
    }

    func testCancellationCoversWorkflowResolverAndSinkCheckpoints() throws {
        let fixture = try makeFixture()
        assertWorkflowError(.cancelled) {
            try ToolbarPresentationEvidenceWorkflow.evaluate(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                attachmentResolver: fixture.resolver(),
                captureManifestAuthenticator: authenticator,
                cancellationCheck: { true }
            )
        }
        assertWorkflowError(.cancelled) {
            try evaluate(fixture, resolver: { _, _, _ in throw CancellationError() })
        }

        let cancellation = CancellationLatch(cancelAfter: 2)
        assertWorkflowError(.cancelled) {
            try ToolbarPresentationEvidenceWorkflow.evaluate(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                limits: ToolbarPresentationEvidenceLimits(cancellationCheckInterval: 1),
                attachmentResolver: fixture.resolver(chunkSize: 1),
                captureManifestAuthenticator: authenticator,
                cancellationCheck: { cancellation.shouldCancel() }
            )
        }
    }

    func testStrictSecondaryActionAndSharedBudgetLimitsFailClosed() throws {
        let fixture = try makeFixture()
        let limitCases:
            [(
                ToolbarPresentationEvidenceLimit,
                Int,
                (Int) -> ToolbarPresentationEvidenceLimits
            )] = [
                (
                    .lifecycleCaptures,
                    ToolbarPresentationEvidenceLimits.hardMaximumCaptureCount,
                    { ToolbarPresentationEvidenceLimits(maximumLifecycleCaptures: $0) }
                ),
                (
                    .windowCaptures,
                    ToolbarPresentationEvidenceLimits.hardMaximumCaptureCount,
                    { ToolbarPresentationEvidenceLimits(maximumWindowCaptures: $0) }
                ),
                (
                    .controls,
                    ToolbarPresentationEvidenceLimits.hardMaximumControlCount,
                    { ToolbarPresentationEvidenceLimits(maximumControlsPerCapture: $0) }
                ),
                (
                    .secondaryActions,
                    ToolbarPresentationEvidenceLimits.hardMaximumSecondaryActionCount,
                    { ToolbarPresentationEvidenceLimits(maximumSecondaryActionsPerCapture: $0) }
                ),
                (
                    .interactions,
                    ToolbarPresentationEvidenceLimits.hardMaximumInteractionCount,
                    { ToolbarPresentationEvidenceLimits(maximumInteractionsPerCapture: $0) }
                ),
                (
                    .accessibilityElements,
                    ToolbarPresentationEvidenceLimits.hardMaximumAccessibilityElementCount,
                    { ToolbarPresentationEvidenceLimits(maximumAccessibilityElementsPerCapture: $0) }
                ),
                (
                    .focusMovements,
                    ToolbarPresentationEvidenceLimits.hardMaximumFocusMovementCount,
                    { ToolbarPresentationEvidenceLimits(maximumFocusMovementsPerCapture: $0) }
                ),
                (
                    .attachments,
                    ToolbarPresentationEvidenceLimits.hardMaximumAttachmentCount,
                    { ToolbarPresentationEvidenceLimits(maximumAttachments: $0) }
                ),
                (
                    .stringUTF8Bytes,
                    ToolbarPresentationEvidenceLimits.hardMaximumStringUTF8Bytes,
                    { ToolbarPresentationEvidenceLimits(maximumStringUTF8Bytes: $0) }
                ),
                (
                    .totalStringUTF8Bytes,
                    ToolbarPresentationEvidenceLimits.hardMaximumTotalStringUTF8Bytes,
                    { ToolbarPresentationEvidenceLimits(maximumTotalStringUTF8Bytes: $0) }
                ),
                (
                    .attachmentBytes,
                    ToolbarPresentationEvidenceLimits.hardMaximumAttachmentBytes,
                    { ToolbarPresentationEvidenceLimits(maximumAttachmentBytes: $0) }
                ),
                (
                    .attachmentChunkBytes,
                    ToolbarPresentationEvidenceLimits.hardMaximumAttachmentChunkBytes,
                    { ToolbarPresentationEvidenceLimits(maximumAttachmentChunkBytes: $0) }
                ),
                (
                    .totalAttachmentBytes,
                    Int(ToolbarPresentationEvidenceLimits.hardMaximumTotalAttachmentBytes),
                    { ToolbarPresentationEvidenceLimits(maximumTotalAttachmentBytes: UInt64($0)) }
                ),
                (
                    .aggregateMemoryBytes,
                    Int(ToolbarPresentationEvidenceLimits.hardMaximumAggregateMemoryBytes),
                    { ToolbarPresentationEvidenceLimits(maximumAggregateMemoryBytes: UInt64($0)) }
                ),
                (
                    .archiveBytes,
                    ToolbarPresentationEvidenceLimits.hardMaximumArchiveBytes,
                    { ToolbarPresentationEvidenceLimits(maximumArchiveBytes: $0) }
                ),
                (
                    .workUnits,
                    Int(ToolbarPresentationEvidenceLimits.hardMaximumWorkUnits),
                    { ToolbarPresentationEvidenceLimits(maximumWorkUnits: UInt64($0)) }
                ),
                (
                    .findings,
                    ToolbarPresentationEvidenceLimits.hardMaximumFindingCount,
                    { ToolbarPresentationEvidenceLimits(maximumFindings: $0) }
                ),
                (
                    .cancellationCheckInterval,
                    ToolbarPresentationEvidenceLimits.hardMaximumCancellationCheckInterval,
                    { ToolbarPresentationEvidenceLimits(cancellationCheckInterval: $0) }
                )
            ]
        for (field, hardMaximum, makeLimits) in limitCases {
            assertWorkflowError(.invalidLimit(field)) {
                try evaluate(fixture, limits: makeLimits(0))
            }
            assertWorkflowError(.invalidLimit(field)) {
                try evaluate(fixture, limits: makeLimits(hardMaximum + 1))
            }
        }
        assertWorkflowError(.countLimitExceeded(.secondaryActions, maximum: 1)) {
            try evaluate(
                fixture,
                limits: ToolbarPresentationEvidenceLimits(maximumSecondaryActionsPerCapture: 1)
            )
        }
        assertWorkflowError(.stringTooLarge(maximumUTF8Bytes: 8)) {
            try evaluate(
                fixture,
                limits: ToolbarPresentationEvidenceLimits(maximumStringUTF8Bytes: 8)
            )
        }
        assertWorkflowError(.totalStringsTooLarge(maximumUTF8Bytes: 128)) {
            try evaluate(
                fixture,
                limits: ToolbarPresentationEvidenceLimits(maximumTotalStringUTF8Bytes: 128)
            )
        }
        assertWorkflowError(.workLimitExceeded(maximum: 64)) {
            try evaluate(
                fixture,
                limits: ToolbarPresentationEvidenceLimits(maximumWorkUnits: 64)
            )
        }
        assertWorkflowError(.aggregateMemoryExceeded(maximumBytes: 64)) {
            try evaluate(
                fixture,
                limits: ToolbarPresentationEvidenceLimits(maximumAggregateMemoryBytes: 64)
            )
        }
    }

    func testPNGAndJPEGAreForcedIntoDeterministicNormalizedRGBAWithoutMetadata() throws {
        let png = try encodedImage(type: "public.png", variant: 3)
        let metadataPNG = try encodedImage(type: "public.png", variant: 3, metadataTag: "private metadata")
        let jpeg = try encodedImage(type: "public.jpeg", variant: 4)

        let canonicalPNG = try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
            for: png,
            mediaType: "image/png",
            cancellationCheck: { false }
        )
        let repeatedPNG = try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
            for: png,
            mediaType: "image/png",
            cancellationCheck: { false }
        )
        let sanitizedPNG = try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
            for: metadataPNG,
            mediaType: "image/png",
            cancellationCheck: { false }
        )
        let canonicalJPEG = try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
            for: jpeg,
            mediaType: "image/jpeg",
            cancellationCheck: { false }
        )

        XCTAssertEqual(canonicalPNG.prefix(8), Data("MMRGBA2\0".utf8))
        XCTAssertEqual(readUInt64(canonicalPNG, at: 8), 40)
        XCTAssertEqual(readUInt64(canonicalPNG, at: 16), 4)
        XCTAssertEqual(canonicalPNG.count, 24 + 40 * 4 * 4)
        XCTAssertEqual(canonicalPNG, repeatedPNG)
        XCTAssertEqual(canonicalPNG, sanitizedPNG)
        XCTAssertEqual(sha256(canonicalPNG), sha256(repeatedPNG))
        XCTAssertEqual(canonicalJPEG.prefix(8), Data("MMRGBA2\0".utf8))
        XCTAssertEqual(canonicalJPEG.count, canonicalPNG.count)
        XCTAssertNotEqual(canonicalJPEG, canonicalPNG)
        XCTAssertFalse(String(decoding: canonicalPNG, as: UTF8.self).contains("private metadata"))
    }

    func testScreenshotValidationRejectsWrongTypeAnimationOrientationAndMalformedRasterData() throws {
        let png = try encodedImage(type: "public.png", variant: 5)
        let jpeg = try encodedImage(type: "public.jpeg", variant: 5)
        let animatedPNG = try encodedImage(type: "public.png", variant: 5, frameCount: 2)
        let rotatedJPEG = try encodedImage(type: "public.jpeg", variant: 5, orientation: 6)

        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: png,
                mediaType: "image/jpeg",
                cancellationCheck: { false }
            )
        }
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: animatedPNG,
                mediaType: "image/png",
                cancellationCheck: { false }
            )
        }
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: rotatedJPEG,
                mediaType: "image/jpeg",
                cancellationCheck: { false }
            )
        }
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: Data("not an image".utf8),
                mediaType: "image/png",
                cancellationCheck: { false }
            )
        }
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: corruptPNGCompressedPayload(png),
                mediaType: "image/png",
                cancellationCheck: { false }
            )
        }
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: duplicatePNGHeader(png),
                mediaType: "image/png",
                cancellationCheck: { false }
            )
        }
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: nonconsecutivePNGData(png),
                mediaType: "image/png",
                cancellationCheck: { false }
            )
        }
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: emptyPNGData(png),
                mediaType: "image/png",
                cancellationCheck: { false }
            )
        }
        let zeroLengthData = insertingZeroLengthPNGData(beforeFirstDataIn: png)
        XCTAssertEqual(
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: zeroLengthData,
                mediaType: "image/png",
                cancellationCheck: { false }
            ),
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: png,
                mediaType: "image/png",
                cancellationCheck: { false }
            )
        )
        var prefixedPNG = Data([0])
        prefixedPNG.append(png)
        let slicedPNG = prefixedPNG.dropFirst()
        XCTAssertNotEqual(slicedPNG.startIndex, 0)
        XCTAssertEqual(
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: slicedPNG,
                mediaType: "image/png",
                cancellationCheck: { false }
            ),
            try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                for: png,
                mediaType: "image/png",
                cancellationCheck: { false }
            )
        )
        for malformed in [
            insertingPNGChunk(type: 0x3142_4364, payload: Data(), in: png),
            insertingPNGChunk(type: 0x6162_6361, payload: Data(), in: png),
            pngMetadataFlood(png),
            replacingPNGEXIF(in: png, with: invalidTIFFDirectoryOffset()),
            replacingPNGEXIF(in: png, with: truncatedTIFFDirectory()),
            replacingPNGEXIF(in: png, with: duplicateTIFFOrientations()),
            duplicateJPEGStartOfFrame(jpeg),
            jpegMetadataFlood(jpeg),
            insertingJPEGAPP1(in: jpeg, tiff: truncatedTIFFDirectory())
        ] {
            let mediaType = malformed.starts(with: [0xFF, 0xD8]) ? "image/jpeg" : "image/png"
            assertWorkflowError(.invalidEvidence(.screenshot)) {
                try ToolbarPresentationEvidenceWorkflow.canonicalScreenshotAttachmentData(
                    for: malformed,
                    mediaType: mediaType,
                    cancellationCheck: { false }
                )
            }
        }
    }

    func testScreenshotMustMatchGeometryAndContainOpaqueNonblankToolbarPixels() throws {
        XCTAssertTrue(try evaluate(makeFixture()).report.isEvidenceCompleteAndValid)

        let blank = try makeFixture(blankScreenshots: true)
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try evaluate(blank)
        }

        let fixture = try makeFixture()
        let window = fixture.evidence.windowCaptures[0]
        let wrongGeometry = ToolbarPresentationCaptureGeometry(
            window: ToolbarPresentationEvidenceRect(x: 0, y: 0, width: 41, height: 4),
            toolbar: ToolbarPresentationEvidenceRect(x: 0, y: 3, width: 39, height: 1),
            backingScaleThousandths: 1_000
        )
        let manifest = try signedManifest(copyManifest(window.captureManifest, geometry: wrongGeometry))
        let badWindow = replacingWindowCapture(window, captureManifest: manifest)
        var windows = fixture.evidence.windowCaptures
        windows[0] = badWindow
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try evaluate(replacingEvidence(fixture, windowCaptures: windows))
        }

        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try evaluate(try replacingScreenshotPixels(in: fixture, alpha: 1))
        }
        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try evaluate(try replacingScreenshotPixels(in: fixture, meaningfulPixelCount: 2))
        }
    }

    func testScreenshotsCannotBeSwappedBetweenFreshAndLoadedContexts() throws {
        let fixture = try makeFixture()
        let fresh = try XCTUnwrap(
            fixture.evidence.windowCaptures.first { $0.context == .freshWindow }
        )
        let loaded = try XCTUnwrap(
            fixture.evidence.windowCaptures.first { $0.context == .loadedComparison }
        )
        let freshBytes = try XCTUnwrap(fixture.payloads[fresh.screenshotAttachmentID])
        let loadedBytes = try XCTUnwrap(fixture.payloads[loaded.screenshotAttachmentID])

        assertWorkflowError(.invalidEvidence(.screenshot)) {
            try evaluate(
                try rebindScreenshots(
                    fixture,
                    replacements: [
                        fresh.screenshotAttachmentID: loadedBytes,
                        loaded.screenshotAttachmentID: freshBytes
                    ]))
        }
    }

    func testCanonicalOrderIsDeterministicAcrossAllUnorderedEvidenceCollections() throws {
        let fixture = try makeFixture()
        let baseline = try evaluate(fixture)
        let lifecycle = fixture.evidence.lifecycleCaptures.reversed().map { capture in
            replacingLifecycleCapture(
                capture,
                controls: capture.controls.reversed(),
                interactions: capture.interactions.reversed(),
                accessibilityTree: capture.accessibilityTree.reversed(),
                focusMovements: capture.focusMovements.reversed()
            )
        }
        let windows = fixture.evidence.windowCaptures.reversed().map { capture in
            replacingWindowCapture(
                capture,
                controls: capture.controls.reversed(),
                interactions: capture.interactions.reversed(),
                accessibilityTree: capture.accessibilityTree.reversed(),
                focusMovements: capture.focusMovements.reversed()
            )
        }
        let reordered = replacingEvidence(
            fixture,
            lifecycleCaptures: lifecycle,
            windowCaptures: windows,
            attachments: fixture.evidence.attachments.reversed()
        )
        let reorderedResult = try evaluate(reordered)

        XCTAssertEqual(reorderedResult.report, baseline.report)
        XCTAssertEqual(reorderedResult.archive, baseline.archive)
        XCTAssertEqual(reorderedResult.receipt, baseline.receipt)
        XCTAssertEqual(
            try ToolbarPresentationEvidenceWorkflow.canonicalAccessibilityAttachmentData(
                for: fixture.evidence.lifecycleCaptures[0],
                cancellationCheck: { false }
            ),
            try ToolbarPresentationEvidenceWorkflow.canonicalAccessibilityAttachmentData(
                for: lifecycle.last!,
                cancellationCheck: { false }
            )
        )
    }

    func testReportDistinguishesPresentationGroupingBehaviorAndInteractionFailures() throws {
        let fixture = try makeFixture()
        var captures = fixture.evidence.lifecycleCaptures

        let metadataIndex = try XCTUnwrap(captures.firstIndex { $0.scenario == .equal })
        let metadataCapture = captures[metadataIndex]
        let metadataControls = metadataCapture.controls.map { control in
            guard control.command == .save else { return control }
            return ToolbarAuditControlObservation(
                id: control.id,
                command: control.command,
                behavior: control.behavior,
                tooltip: "Not WinMerge",
                shortcut: ToolbarAuditShortcut(key: "x", modifiers: [.command], display: "Command-X"),
                accessibility: control.accessibility,
                availability: control.availability
            )
        }
        let changedInteractions = metadataCapture.interactions.map { interaction in
            guard interaction.invocation == .primaryClick else { return interaction }
            return ToolbarPresentationInteractionCapture(
                scenario: interaction.scenario,
                controlID: interaction.controlID,
                elementIdentity: interaction.elementIdentity,
                actionID: interaction.actionID,
                invocation: interaction.invocation,
                outcome: .failed(code: toolbarID("interaction.failed")),
                source: interaction.source
            )
        }
        captures[metadataIndex] = replacingLifecycleCapture(
            metadataCapture,
            controls: metadataControls,
            interactions: changedInteractions
        )

        let orderIndex = try XCTUnwrap(captures.firstIndex { $0.scenario == .loading })
        let orderCapture = captures[orderIndex]
        var reorderedItems = orderCapture.items
        reorderedItems.swapAt(0, 1)
        captures[orderIndex] = replacingPresentation(orderCapture, items: reorderedItems)

        let groupingIndex = try XCTUnwrap(captures.firstIndex { $0.scenario == .failed })
        let groupingCapture = captures[groupingIndex]
        var regroupedItems = groupingCapture.items
        regroupedItems.removeLast()
        captures[groupingIndex] = replacingPresentation(groupingCapture, items: regroupedItems)

        let rebound = try rebind(fixture, lifecycleCaptures: captures)
        let codes = Set(try evaluate(rebound).report.findings.map(\.code))
        XCTAssertTrue(codes.contains(.tooltipMismatch))
        XCTAssertTrue(codes.contains(.shortcutMismatch))
        XCTAssertTrue(codes.contains(.interactionOutcomeMismatch))
        XCTAssertTrue(codes.contains(.commandOrderMismatch))
        XCTAssertTrue(codes.contains(.commandGroupingMismatch))
    }

    func testPrimaryAndSecondaryBehaviorMismatchesRemainSeparate() throws {
        let fixture = try makeFixture()
        var captures = fixture.evidence.lifecycleCaptures

        let primaryIndex = try XCTUnwrap(captures.firstIndex { $0.scenario == .externallyChanged })
        let primaryCapture = captures[primaryIndex]
        let primaryControls = primaryCapture.controls.map { control in
            guard control.command == .refresh else { return control }
            return ToolbarAuditControlObservation(
                id: control.id,
                command: control.command,
                behavior: ToolbarAuditControlBehavior(primaryActionID: toolbarID("action.refresh.changed")),
                tooltip: control.tooltip,
                shortcut: control.shortcut,
                accessibility: control.accessibility,
                availability: control.availability
            )
        }
        let primaryInteractions = primaryCapture.interactions.filter { $0.controlID != controlID(.refresh) }
        captures[primaryIndex] = replacingLifecycleCapture(
            primaryCapture,
            controls: primaryControls,
            interactions: primaryInteractions
        )

        let secondaryIndex = try XCTUnwrap(captures.firstIndex { $0.scenario == .readOnly })
        let secondaryCapture = captures[secondaryIndex]
        let secondaryControls = secondaryCapture.controls.map { control in
            guard control.command == .save, case .menu(let actions) = control.behavior.secondary else {
                return control
            }
            return ToolbarAuditControlObservation(
                id: control.id,
                command: control.command,
                behavior: ToolbarAuditControlBehavior(
                    primaryActionID: control.behavior.primaryActionID,
                    secondary: .menu(actions: actions.reversed())
                ),
                tooltip: control.tooltip,
                shortcut: control.shortcut,
                accessibility: control.accessibility,
                availability: control.availability
            )
        }
        captures[secondaryIndex] = replacingLifecycleCapture(secondaryCapture, controls: secondaryControls)

        let rebound = try rebind(fixture, lifecycleCaptures: captures)
        let behaviorFindings = try evaluate(rebound).report.findings.filter { $0.code == .controlBehaviorMismatch }
        XCTAssertEqual(behaviorFindings.count, 2)
        XCTAssertTrue(behaviorFindings.allSatisfy { $0.severity == .error })
    }

    func testArchiveAndReceiptRoundTripRejectMutationAndCurrentStateTransplant() throws {
        let fixture = try makeFixture()
        let result = try evaluate(fixture)
        try ToolbarPresentationEvidenceWorkflow.validate(
            archive: result.archive.data,
            for: fixture.evidence,
            boundTo: fixture.inventory,
            attachmentResolver: fixture.resolver(),
            captureManifestAuthenticator: authenticator,
            cancellationCheck: { false }
        )
        try result.receipt.validateCurrent(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            attachmentResolver: fixture.resolver(),
            captureManifestAuthenticator: authenticator,
            cancellationCheck: { false }
        )

        var corrupted = result.archive.data
        corrupted[corrupted.index(before: corrupted.endIndex)] ^= 1
        assertWorkflowError(.nonCanonicalArchive) {
            try ToolbarPresentationEvidenceWorkflow.validate(
                archive: corrupted,
                for: fixture.evidence,
                boundTo: fixture.inventory,
                attachmentResolver: fixture.resolver(),
                captureManifestAuthenticator: authenticator,
                cancellationCheck: { false }
            )
        }

        let changedEvidence = evidence(fixture.evidence, reference: reference("other.evidence", 1))
        assertWorkflowError(.evidenceContentsChanged) {
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: changedEvidence,
                attachmentResolver: fixture.resolver(),
                captureManifestAuthenticator: authenticator,
                cancellationCheck: { false }
            )
        }
    }

    func testFindingIDsAreOpaqueDeterministicAndDescriptionsReflectionRedactContents() throws {
        let fixture = try makeFixture()
        let emptyEvidence = evidence(
            fixture.evidence,
            lifecycleCaptures: [],
            windowCaptures: [],
            attachments: []
        )
        let missing = Fixture(inventory: fixture.inventory, evidence: emptyEvidence, payloads: [:])
        let first = try evaluate(missing).report
        let second = try evaluate(missing).report
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.findings.isEmpty)
        XCTAssertEqual(Set(first.findings.map(\.id)).count, first.findings.count)
        XCTAssertTrue(
            first.findings.allSatisfy {
                $0.id.rawValue.count == 64
                    && $0.id.rawValue.utf8.allSatisfy { byte in
                        (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
                    }
            }
        )
        XCTAssertTrue(first.findings.allSatisfy { !$0.message.contains("collector.secret") })

        let result = try evaluate(fixture)
        let secret = "collector.secret"
        let values: [Any] = [
            fixture.inventory.layout,
            fixture.inventory,
            fixture.evidence.lifecycleCaptures[0].captureManifest,
            fixture.evidence.attachments[0],
            fixture.evidence.lifecycleCaptures[0],
            fixture.evidence.windowCaptures[0],
            fixture.evidence,
            result.archive,
            result.receipt
        ]
        for value in values {
            XCTAssertTrue(String(describing: value).contains("<redacted>"))
            XCTAssertTrue(String(reflecting: value).contains("<redacted>"))
            XCTAssertFalse(String(describing: value).contains(secret))
            XCTAssertFalse(String(reflecting: value).contains(secret))
            XCTAssertTrue(Mirror(reflecting: value).children.contains { String(describing: $0.value).contains("<redacted>") })
        }
    }

    // Production intentionally exposes screenshot canonicalization but no public raster encoder.
    // Tests therefore create bounded 40x4 images with public ImageIO/CoreGraphics APIs.
    private func makeFixture(blankScreenshots: Bool = false) throws -> Fixture {
        let app = reference("macmerge.app", 7)
        let build = reference("macmerge.build", 11)
        let inventoryReference = reference("toolbar.inventory", 13)
        let manifestReference = reference("toolbar.manifest", ToolbarAuditManifest.canonicalRevision.rawValue)
        let layoutReference = reference("toolbar.layout", 17)
        let buildBinding = binding(artifact: 0x11, signing: 0x22)
        let configurationReference = ToolbarCustomizationWorkflow.ConfigurationReference(
            identity: ToolbarCustomizationWorkflow.ConfigurationIdentity(
                rawValue: UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
            ),
            revision: ToolbarCustomizationWorkflow.ConfigurationRevision(rawValue: layoutReference.revision.rawValue)
        )
        let layout = ToolbarPresentationLayout(
            reference: layoutReference,
            configurationReference: configurationReference,
            configuration: .winMergeDefault,
            manifestRevision: ToolbarAuditManifest.canonicalRevision
        )
        let controls = ToolbarAuditCommand.allCases.map(makeRequirement)
        let semanticBindings = controls.flatMap { control -> [ToolbarPresentationSemanticActionBinding] in
            var bindings = [
                ToolbarPresentationSemanticActionBinding(
                    actionID: control.behavior.primaryActionID,
                    command: ComparisonCommandState.Identifier(control.command)
                )
            ]
            if control.command == .save {
                bindings += [
                    ToolbarPresentationSemanticActionBinding(actionID: saveSecondaryActionIDs[0], command: .saveLeftAs),
                    ToolbarPresentationSemanticActionBinding(actionID: saveSecondaryActionIDs[1], command: .saveRightAs)
                ]
            }
            return bindings
        }
        let semanticByAction = Dictionary(uniqueKeysWithValues: semanticBindings.map { ($0.actionID, $0.command) })
        let lifecycleRequirements = ToolbarAuditLifecycleScenario.allCases.map { scenario in
            ToolbarPresentationLifecycleRequirement(
                scenario: scenario,
                reference: reference("scenario.lifecycle.\(scenario.rawValue)", UInt64(scenarioRank(scenario) + 1)),
                commandState: commandContext(for: scenario)
            )
        }
        let lifecycleExpectations = ToolbarAuditLifecycleScenario.allCases.flatMap { scenario in
            controls.flatMap { control in
                control.behavior.allActionIDs.map { actionID in
                    ToolbarAuditLifecycleExpectation(
                        scenario: scenario,
                        command: control.command,
                        actionID: actionID,
                        availability: availability(
                            for: semanticByAction[actionID]!,
                            scenario: scenario
                        )
                    )
                }
            }
        }
        let interactions = makeInteractionExpectations(
            controls: controls,
            semanticByAction: semanticByAction
        )
        let contract = ToolbarAuditContract(
            revision: ToolbarAuditRevision(rawValue: 23),
            controls: controls,
            lifecycleExpectations: lifecycleExpectations,
            interactionExpectations: interactions
        )
        let windowRequirements = [
            ToolbarPresentationWindowRequirement(
                context: .freshWindow,
                reference: reference("scenario.window.fresh", 1),
                lifecycleScenario: .equal
            ),
            ToolbarPresentationWindowRequirement(
                context: .loadedComparison,
                reference: reference("scenario.window.loaded", 2),
                lifecycleScenario: .dirty
            )
        ]
        let inventory = ToolbarPresentationEvidenceInventory(
            app: app,
            build: build,
            buildBinding: buildBinding,
            reference: inventoryReference,
            manifestReference: manifestReference,
            layout: layout,
            auditContract: contract,
            semanticActionBindings: semanticBindings,
            lifecycleRequirements: lifecycleRequirements,
            windowRequirements: windowRequirements
        )
        let evidenceReference = reference("toolbar.evidence", 29)
        let geometry = captureGeometry
        let lifecycleCaptures = lifecycleRequirements.enumerated().map { offset, requirement in
            let scope = "lifecycle.\(requirement.scenario.rawValue)"
            let observations = observedControls(
                controls,
                scenario: requirement.scenario,
                semanticByAction: semanticByAction
            )
            let scenarioInteractions = interactions.filter { $0.scenario == requirement.scenario }.map {
                interactionCapture($0, scope: scope)
            }
            let tree = accessibilityTree(
                controls: observations,
                interactions: scenarioInteractions,
                items: contract.manifest.items,
                scope: scope,
                geometry: geometry
            )
            return ToolbarPresentationLifecycleCapture(
                scenario: requirement.scenario,
                reference: requirement.reference,
                manifest: manifestReference,
                layout: layoutReference,
                provenance: provenance(
                    collector: reference("collector.secret", 5),
                    build: build,
                    buildBinding: buildBinding,
                    nonce: UInt8(offset + 1)
                ),
                origin: .automatedMeasurement,
                items: contract.manifest.items,
                controls: observations,
                interactions: scenarioInteractions,
                accessibilityTree: tree,
                focusMovements: focusMovements(
                    controls: observations,
                    interactions: scenarioInteractions,
                    items: contract.manifest.items,
                    scope: scope
                ),
                captureManifest: placeholderManifest(
                    capture: requirement.reference,
                    context: .lifecycle(requirement.scenario),
                    inventory: inventory,
                    provenance: provenance(
                        collector: reference("collector.secret", 5),
                        build: build,
                        buildBinding: buildBinding,
                        nonce: UInt8(offset + 1)
                    ),
                    geometry: geometry
                ),
                accessibilityAttachmentID: accessibilityID("attachment.\(scope).ax"),
                source: "collector.secret.\(scope)"
            )
        }
        var screenshotData: [AccessibilityStableID: Data] = [:]
        let windowCaptures = try windowRequirements.enumerated().map { offset, requirement in
            let scope = "window.\(requirement.context.rawValue)"
            let observations = observedControls(
                controls,
                scenario: requirement.lifecycleScenario,
                semanticByAction: semanticByAction
            )
            let screenshotID = accessibilityID("attachment.\(scope).screenshot")
            screenshotData[screenshotID] = try encodedImage(
                type: "public.png",
                variant: offset + 40,
                context: requirement.context,
                blank: blankScreenshots
            )
            let captureProvenance = provenance(
                collector: reference("collector.secret", 5),
                build: build,
                buildBinding: buildBinding,
                nonce: UInt8(offset + 40)
            )
            let tree = accessibilityTree(
                controls: observations,
                interactions: [],
                items: contract.manifest.items,
                scope: scope,
                geometry: geometry
            )
            return ToolbarPresentationWindowCapture(
                context: requirement.context,
                reference: requirement.reference,
                lifecycleScenario: requirement.lifecycleScenario,
                manifest: manifestReference,
                layout: layoutReference,
                provenance: captureProvenance,
                origin: .automatedMeasurement,
                items: contract.manifest.items,
                controls: observations,
                interactions: [],
                accessibilityTree: tree,
                focusMovements: focusMovements(
                    controls: observations,
                    interactions: [],
                    items: contract.manifest.items,
                    scope: scope
                ),
                captureManifest: placeholderManifest(
                    capture: requirement.reference,
                    context: .window(requirement.context, lifecycle: requirement.lifecycleScenario),
                    inventory: inventory,
                    provenance: captureProvenance,
                    geometry: geometry,
                    screenshotAttachmentID: screenshotID
                ),
                screenshotAttachmentID: screenshotID,
                accessibilityAttachmentID: accessibilityID("attachment.\(scope).ax"),
                source: "collector.secret.\(scope)"
            )
        }
        let bareEvidence = ToolbarPresentationEvidenceBundle(
            reference: evidenceReference,
            app: app,
            build: build,
            buildBinding: buildBinding,
            inventory: inventoryReference,
            manifest: manifestReference,
            layout: layoutReference,
            lifecycleCaptures: lifecycleCaptures,
            windowCaptures: windowCaptures,
            attachments: []
        )
        return try bindEvidence(inventory: inventory, evidence: bareEvidence, screenshotData: screenshotData)
    }

    private func bindEvidence(
        inventory: ToolbarPresentationEvidenceInventory,
        evidence bare: ToolbarPresentationEvidenceBundle,
        screenshotData: [AccessibilityStableID: Data]
    ) throws -> Fixture {
        var captures: [ToolbarPresentationLifecycleCapture] = []
        var windows: [ToolbarPresentationWindowCapture] = []
        var attachments: [ToolbarPresentationEvidenceAttachment] = []
        var payloads: [AccessibilityStableID: Data] = [:]

        for capture in bare.lifecycleCaptures {
            let stateDigest = sha256(captureStateData(capture))
            let treeDigest = sha256(accessibilityTreeData(capture.accessibilityTree))
            let manifest = try signedManifest(
                copyManifest(
                    capture.captureManifest,
                    stateSHA256: stateDigest,
                    accessibilityTreeSHA256: treeDigest,
                    screenshotPixelSHA256: nil,
                    authentication: [1]
                )
            )
            let bound = replacingLifecycleCapture(capture, captureManifest: manifest)
            let bytes = try ToolbarPresentationEvidenceWorkflow.canonicalAccessibilityAttachmentData(
                for: bound,
                cancellationCheck: { false }
            )
            captures.append(bound)
            payloads[bound.accessibilityAttachmentID] = bytes
            attachments.append(
                attachment(
                    id: bound.accessibilityAttachmentID,
                    kind: .accessibilitySnapshot,
                    capture: bound.reference,
                    provenance: bound.provenance,
                    manifest: bound.captureManifest,
                    bytes: bytes,
                    content: bytes,
                    evidence: bare
                )
            )
        }

        for capture in bare.windowCaptures {
            let screenshot = try required(screenshotData[capture.screenshotAttachmentID])
            let canonicalScreenshot = try canonicalFixtureScreenshotData(screenshot)
            let stateDigest = sha256(captureStateData(capture))
            let treeDigest = sha256(accessibilityTreeData(capture.accessibilityTree))
            let manifest = try signedManifest(
                copyManifest(
                    capture.captureManifest,
                    stateSHA256: stateDigest,
                    accessibilityTreeSHA256: treeDigest,
                    screenshotPixelSHA256: sha256(canonicalScreenshot),
                    screenshotEncodedSHA256: sha256(screenshot),
                    authentication: [1]
                )
            )
            let bound = replacingWindowCapture(capture, captureManifest: manifest)
            let axBytes = try ToolbarPresentationEvidenceWorkflow.canonicalAccessibilityAttachmentData(
                for: bound,
                cancellationCheck: { false }
            )
            windows.append(bound)
            payloads[bound.screenshotAttachmentID] = screenshot
            payloads[bound.accessibilityAttachmentID] = axBytes
            attachments.append(
                attachment(
                    id: bound.screenshotAttachmentID,
                    kind: .screenshot,
                    capture: bound.reference,
                    provenance: bound.provenance,
                    manifest: bound.captureManifest,
                    bytes: screenshot,
                    content: canonicalScreenshot,
                    evidence: bare,
                    mediaType: "image/png",
                    source: try required(bound.captureManifest.screenshotSource)
                )
            )
            attachments.append(
                attachment(
                    id: bound.accessibilityAttachmentID,
                    kind: .accessibilitySnapshot,
                    capture: bound.reference,
                    provenance: bound.provenance,
                    manifest: bound.captureManifest,
                    bytes: axBytes,
                    content: axBytes,
                    evidence: bare
                )
            )
        }
        return Fixture(
            inventory: inventory,
            evidence: ToolbarPresentationEvidenceBundle(
                reference: bare.reference,
                app: bare.app,
                build: bare.build,
                buildBinding: bare.buildBinding,
                inventory: bare.inventory,
                manifest: bare.manifest,
                layout: bare.layout,
                lifecycleCaptures: captures,
                windowCaptures: windows,
                attachments: attachments
            ),
            payloads: payloads
        )
    }

    private func rebind(
        _ fixture: Fixture,
        lifecycleCaptures: [ToolbarPresentationLifecycleCapture]? = nil,
        windowCaptures: [ToolbarPresentationWindowCapture]? = nil
    ) throws -> Fixture {
        let lifecycle = lifecycleCaptures ?? fixture.evidence.lifecycleCaptures
        let windows = windowCaptures ?? fixture.evidence.windowCaptures
        let bare = evidence(
            fixture.evidence,
            lifecycleCaptures: lifecycle,
            windowCaptures: windows,
            attachments: []
        )
        let screenshotIDs = Set(windows.map(\.screenshotAttachmentID))
        return try bindEvidence(
            inventory: fixture.inventory,
            evidence: bare,
            screenshotData: fixture.payloads.filter { screenshotIDs.contains($0.key) }
        )
    }

    private func makeRequirement(_ command: ToolbarAuditCommand) -> ToolbarAuditControlRequirement {
        let secondary: ToolbarAuditSecondaryBehavior
        if command == .save {
            secondary = .menu(
                actions: saveSecondaryActionIDs.enumerated().map { index, actionID in
                    ToolbarAuditSecondaryAction(
                        id: actionID,
                        accessibility: ax(
                            actionID.rawValue,
                            role: .menuItem,
                            label: index == 0 ? "Save Left As" : "Save Right As",
                            hint: index == 0 ? "Saves left pane as" : "Saves right pane as",
                            enabled: nil,
                            focusable: true,
                            actions: [.activate]
                        )
                    )
                }
            )
        } else {
            secondary = .none
        }
        return ToolbarAuditControlRequirement(
            id: controlID(command),
            command: command,
            behavior: ToolbarAuditControlBehavior(
                primaryActionID: primaryActionID(command),
                secondary: secondary
            ),
            tooltip: "WinMerge \(command.rawValue)",
            shortcut: command == .save
                ? ToolbarAuditShortcut(key: "s", modifiers: [.command], display: "Command-S") : nil,
            accessibility: ax(
                controlID(command).rawValue,
                label: "Toolbar \(command.rawValue)",
                hint: "Runs \(command.rawValue)",
                enabled: nil
            )
        )
    }

    private func observedControls(
        _ requirements: [ToolbarAuditControlRequirement],
        scenario: ToolbarAuditLifecycleScenario,
        semanticByAction: [ToolbarAuditStableID: ComparisonCommandState.Identifier]
    ) -> [ToolbarAuditControlObservation] {
        requirements.map { requirement in
            let primaryEnabled = availability(
                for: semanticByAction[requirement.behavior.primaryActionID]!,
                scenario: scenario
            )
            let secondary: ToolbarAuditSecondaryBehavior
            switch requirement.behavior.secondary {
            case .none:
                secondary = .none
            case .menu(let actions):
                secondary = .menu(
                    actions: actions.map { action in
                        ToolbarAuditSecondaryAction(
                            id: action.id,
                            accessibility: concreteAX(
                                action.accessibility,
                                enabled: availability(for: semanticByAction[action.id]!, scenario: scenario).isEnabled
                            )
                        )
                    }
                )
            }
            return ToolbarAuditControlObservation(
                id: requirement.id,
                command: requirement.command,
                behavior: ToolbarAuditControlBehavior(
                    primaryActionID: requirement.behavior.primaryActionID,
                    secondary: secondary
                ),
                tooltip: requirement.tooltip,
                shortcut: requirement.shortcut,
                accessibility: concreteAX(requirement.accessibility, enabled: primaryEnabled.isEnabled),
                availability: primaryEnabled
            )
        }
    }

    private func makeInteractionExpectations(
        controls: [ToolbarAuditControlRequirement],
        semanticByAction: [ToolbarAuditStableID: ComparisonCommandState.Identifier]
    ) -> [ToolbarAuditInteractionExpectation] {
        var result: [ToolbarAuditInteractionExpectation] = []
        for control in controls {
            let primary = control.behavior.primaryActionID
            let primaryScenario = ToolbarAuditLifecycleScenario.allCases.first {
                availability(for: semanticByAction[primary]!, scenario: $0).isEnabled
            }!
            for invocation in [
                ToolbarAuditInvocationKind.primaryClick, .keyboardActivation, .voiceOverActivation
            ] {
                result.append(
                    ToolbarAuditInteractionExpectation(
                        scenario: primaryScenario,
                        controlID: control.id,
                        actionID: primary,
                        invocation: invocation,
                        outcome: .invoked(actionID: primary)
                    )
                )
            }
            if case .menu(let actions) = control.behavior.secondary {
                result.append(
                    ToolbarAuditInteractionExpectation(
                        scenario: primaryScenario,
                        controlID: control.id,
                        actionID: primary,
                        invocation: .menuArrowClick,
                        outcome: .menuPresented(actionIDs: actions.map(\.id))
                    )
                )
                for action in actions {
                    let scenario = ToolbarAuditLifecycleScenario.allCases.first {
                        availability(for: semanticByAction[action.id]!, scenario: $0).isEnabled
                    }!
                    result.append(
                        ToolbarAuditInteractionExpectation(
                            scenario: scenario,
                            controlID: control.id,
                            actionID: action.id,
                            invocation: .menuItemSelection,
                            outcome: .invoked(actionID: action.id)
                        )
                    )
                }
            }
            for actionID in control.behavior.allActionIDs {
                for scenario in ToolbarAuditLifecycleScenario.allCases
                where !availability(for: semanticByAction[actionID]!, scenario: scenario).isEnabled {
                    result.append(
                        ToolbarAuditInteractionExpectation(
                            scenario: scenario,
                            controlID: control.id,
                            actionID: actionID,
                            invocation: .disabledActivation,
                            outcome: .blocked
                        )
                    )
                }
            }
        }
        return result
    }

    private func interactionCapture(
        _ expectation: ToolbarAuditInteractionExpectation,
        scope: String
    ) -> ToolbarPresentationInteractionCapture {
        let isSecondaryAction = saveSecondaryActionIDs.contains(expectation.actionID)
        return ToolbarPresentationInteractionCapture(
            scenario: expectation.scenario,
            controlID: expectation.controlID,
            elementIdentity: isSecondaryAction
                ? menuActionElementID(expectation.actionID, scope: scope)
                : controlElementID(command(for: expectation.controlID), scope: scope),
            actionID: expectation.actionID,
            invocation: expectation.invocation,
            outcome: expectation.outcome,
            source: "collector.secret.interaction.\(expectation.invocation.rawValue)"
        )
    }

    private func accessibilityTree(
        controls: [ToolbarAuditControlObservation],
        interactions: [ToolbarPresentationInteractionCapture],
        items: [ToolbarAuditItem],
        scope: String,
        geometry: ToolbarPresentationCaptureGeometry
    ) -> [ToolbarPresentationAXElementObservation] {
        let root = accessibilityID("element.\(scope).toolbar")
        var result = [
            ToolbarPresentationAXElementObservation(
                elementIdentity: root,
                parentIdentity: nil,
                siblingIndex: 0,
                frame: geometry.toolbar,
                accessibility: ax(
                    "ax.\(scope).toolbar",
                    role: .toolbar,
                    label: "Comparison toolbar",
                    hint: "",
                    enabled: nil,
                    focusable: false,
                    actions: []
                )
            )
        ]
        let controlsByCommand = Dictionary(uniqueKeysWithValues: controls.map { ($0.command, $0) })
        var x = geometry.toolbar.x
        var separatorIndex = 0
        for (siblingIndex, item) in items.enumerated() {
            switch item {
            case .command(let command):
                let control = controlsByCommand[command]!
                result.append(
                    ToolbarPresentationAXElementObservation(
                        elementIdentity: controlElementID(command, scope: scope),
                        parentIdentity: root,
                        siblingIndex: siblingIndex,
                        frame: ToolbarPresentationEvidenceRect(x: x, y: geometry.toolbar.y, width: 1, height: 1),
                        accessibility: control.accessibility
                    )
                )
            case .separator:
                result.append(
                    ToolbarPresentationAXElementObservation(
                        elementIdentity: accessibilityID("element.\(scope).separator.\(separatorIndex)"),
                        parentIdentity: root,
                        siblingIndex: siblingIndex,
                        frame: ToolbarPresentationEvidenceRect(x: x, y: geometry.toolbar.y, width: 1, height: 1),
                        accessibility: ax(
                            "ax.\(scope).separator.\(separatorIndex)",
                            role: .separator,
                            label: "",
                            hint: "",
                            enabled: nil,
                            focusable: false,
                            actions: []
                        )
                    )
                )
                separatorIndex += 1
            }
            x += 1
        }

        for control in controls {
            guard case .menu(let actions) = control.behavior.secondary else { continue }
            let actionIDs = Set(actions.map(\.id))
            guard
                interactions.contains(where: { interaction in
                    if actionIDs.contains(interaction.actionID) { return true }
                    guard case .menuPresented(let presentedActionIDs) = interaction.outcome else {
                        return false
                    }
                    return !actionIDs.isDisjoint(with: presentedActionIDs)
                })
            else { continue }
            let menuIdentity = menuElementID(control.command, scope: scope)
            let owner = controlElementID(control.command, scope: scope)
            result.append(
                ToolbarPresentationAXElementObservation(
                    elementIdentity: menuIdentity,
                    parentIdentity: owner,
                    siblingIndex: 0,
                    frame: ToolbarPresentationEvidenceRect(x: 2, y: 0, width: 2, height: actions.count),
                    accessibility: ax(
                        "ax.\(scope).menu.\(control.command.rawValue)",
                        role: .menu,
                        label: "",
                        hint: "",
                        enabled: true,
                        focusable: false,
                        actions: []
                    )
                )
            )
            for (index, action) in actions.enumerated() {
                result.append(
                    ToolbarPresentationAXElementObservation(
                        elementIdentity: menuActionElementID(action.id, scope: scope),
                        parentIdentity: menuIdentity,
                        siblingIndex: index,
                        frame: ToolbarPresentationEvidenceRect(x: 2, y: index, width: 2, height: 1),
                        accessibility: action.accessibility
                    )
                )
            }
        }
        return result
    }

    private func focusMovements(
        controls: [ToolbarAuditControlObservation],
        interactions: [ToolbarPresentationInteractionCapture],
        items: [ToolbarAuditItem],
        scope: String
    ) -> [ToolbarPresentationFocusMovement] {
        let focusable = focusableControls(controls, items: items)
        guard !focusable.isEmpty else { return [] }
        let root = accessibilityID("element.\(scope).toolbar")
        var result = focusable.enumerated().flatMap { index, control in
            let target = controlElementID(control.command, scope: scope)
            let previous =
                focusable.count == 1
                ? root
                : controlElementID(
                    focusable[(index + focusable.count - 1) % focusable.count].command,
                    scope: scope
                )
            let next =
                focusable.count == 1
                ? root
                : controlElementID(focusable[(index + 1) % focusable.count].command, scope: scope)
            return [
                ToolbarPresentationFocusMovement(
                    controlID: control.id,
                    fromElementIdentity: previous,
                    toElementIdentity: target,
                    traversal: .tabForward
                ),
                ToolbarPresentationFocusMovement(
                    controlID: control.id,
                    fromElementIdentity: next,
                    toElementIdentity: target,
                    traversal: .tabBackward
                )
            ]
        }
        for control in controls {
            guard case .menu(let actions) = control.behavior.secondary else { continue }
            let actionIDs = Set(actions.map(\.id))
            guard
                interactions.contains(where: { interaction in
                    if actionIDs.contains(interaction.actionID) { return true }
                    guard case .menuPresented(let presentedActionIDs) = interaction.outcome else {
                        return false
                    }
                    return !actionIDs.isDisjoint(with: presentedActionIDs)
                })
            else { continue }
            let focusableActions = actions.filter {
                $0.accessibility.isKeyboardFocusable && $0.accessibility.isEnabled == true
            }
            let menu = menuElementID(control.command, scope: scope)
            for (index, action) in focusableActions.enumerated() {
                let target = menuActionElementID(action.id, scope: scope)
                let previous =
                    focusableActions.count == 1
                    ? menu
                    : menuActionElementID(
                        focusableActions[(index + focusableActions.count - 1) % focusableActions.count].id,
                        scope: scope
                    )
                let next =
                    focusableActions.count == 1
                    ? menu
                    : menuActionElementID(
                        focusableActions[(index + 1) % focusableActions.count].id,
                        scope: scope
                    )
                result.append(
                    ToolbarPresentationFocusMovement(
                        controlID: action.id,
                        fromElementIdentity: previous,
                        toElementIdentity: target,
                        traversal: .menuNext
                    )
                )
                result.append(
                    ToolbarPresentationFocusMovement(
                        controlID: action.id,
                        fromElementIdentity: next,
                        toElementIdentity: target,
                        traversal: .menuPrevious
                    )
                )
            }
        }
        return result
    }

    private func focusableControls(
        _ controls: [ToolbarAuditControlObservation],
        items: [ToolbarAuditItem]
    ) -> [ToolbarAuditControlObservation] {
        let byCommand = Dictionary(uniqueKeysWithValues: controls.map { ($0.command, $0) })
        return items.compactMap(\.command).compactMap { command in
            guard let control = byCommand[command],
                control.accessibility.isKeyboardFocusable,
                control.accessibility.isEnabled == true
            else { return nil }
            return control
        }
    }

    private func commandContext(for scenario: ToolbarAuditLifecycleScenario) -> ComparisonCommandState.Context {
        let loaded = ComparisonCommandState.PaneState(isLoaded: true, isEditable: true)
        let dirty = ComparisonCommandState.PaneState(isLoaded: true, isEditable: true, isDirty: true)
        let navigation = ComparisonCommandState.DifferenceNavigation(
            canSelectLineDifference: true,
            canSelectPreviousLineDifference: true,
            canSelectNextDifference: true,
            canSelectPreviousDifference: true,
            canSelectFirstDifference: true,
            canSelectCurrentDifference: true,
            canSelectLastDifference: true
        )
        let conflicts = ComparisonCommandState.ConflictNavigationState(
            isSupported: true,
            hasConflicts: true,
            canSelectFirstConflict: true,
            canSelectNextConflict: true,
            canSelectPreviousConflict: true,
            canSelectCurrentConflict: true,
            canSelectLastConflict: true
        )
        let files = ComparisonCommandState.ComparedFileNavigation(
            isSupported: true,
            canSelectFirst: true,
            canSelectPrevious: true,
            canSelectNext: true,
            canSelectLast: true
        )
        switch scenario {
        case .empty:
            return ComparisonCommandState.Context()
        case .loading:
            return ComparisonCommandState.Context(lifecycle: .loading)
        case .equal:
            return ComparisonCommandState.Context(
                left: loaded,
                right: loaded,
                layout: .threePane(
                    middle: loaded,
                    automaticMergeDestination: .right,
                    supportsAutomaticMerge: true,
                    isAutomaticMergeEligible: true
                ),
                hasSelection: true,
                hasSignificantDifferences: true,
                canUndo: true,
                canRedo: true,
                differenceNavigation: navigation,
                conflictNavigation: conflicts,
                comparedFileNavigation: files,
                canChangePane: true,
                canChangePaneBack: true
            )
        case .different, .selected:
            return ComparisonCommandState.Context(
                left: loaded,
                right: loaded,
                hasSelection: true,
                hasSignificantDifferences: true,
                canUndo: true,
                canRedo: true,
                differenceNavigation: navigation,
                conflictNavigation: conflicts,
                comparedFileNavigation: files,
                canChangePane: true,
                canChangePaneBack: true
            )
        case .dirty:
            return ComparisonCommandState.Context(
                left: dirty,
                right: loaded,
                hasSelection: true,
                hasSignificantDifferences: true,
                differenceNavigation: navigation,
                conflictNavigation: conflicts,
                comparedFileNavigation: files
            )
        case .readOnly:
            return ComparisonCommandState.Context(
                left: ComparisonCommandState.PaneState(isLoaded: true),
                right: ComparisonCommandState.PaneState(isLoaded: true),
                hasSignificantDifferences: true,
                differenceNavigation: navigation
            )
        case .failed:
            return ComparisonCommandState.Context(left: loaded, right: loaded, lifecycle: .failed)
        case .untitled:
            return ComparisonCommandState.Context(
                left: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true, isUntitled: true),
                right: loaded
            )
        case .externallyChanged:
            return ComparisonCommandState.Context(
                left: ComparisonCommandState.PaneState(
                    isLoaded: true,
                    isEditable: true,
                    isDirty: true,
                    hasExternalChange: true
                ),
                right: loaded
            )
        }
    }

    private func availability(
        for command: ComparisonCommandState.Identifier,
        scenario: ToolbarAuditLifecycleScenario
    ) -> ToolbarAuditAvailability {
        ComparisonCommandState.resolve(command, in: commandContext(for: scenario)).isEnabled
            ? .enabled : .disabled(reason: toolbarID("disabled.\(command.rawValue).\(scenario.rawValue)"))
    }

    private func placeholderManifest(
        capture: AccessibilityEvidenceRevisionReference,
        context: ToolbarPresentationCaptureContext,
        inventory: ToolbarPresentationEvidenceInventory,
        provenance: AccessibilityEvidenceCaptureProvenance,
        geometry: ToolbarPresentationCaptureGeometry,
        screenshotAttachmentID: AccessibilityStableID? = nil
    ) -> ToolbarPresentationCaptureManifest {
        ToolbarPresentationCaptureManifest(
            collector: provenance.collector,
            capture: capture,
            origin: .automatedMeasurement,
            app: inventory.app,
            build: inventory.build,
            buildBinding: inventory.buildBinding,
            inventory: inventory.reference,
            manifest: inventory.manifestReference,
            layout: inventory.layout.reference,
            configuration: inventory.layout.configurationReference,
            contractRevision: inventory.auditContract.revision,
            manifestRevision: inventory.auditContract.manifest.revision,
            context: context,
            geometry: geometry,
            windowState: validWindowState,
            stateSHA256: digest(0x01),
            accessibilityTreeSHA256: digest(0x02),
            screenshotPixelSHA256: screenshotAttachmentID == nil ? nil : digest(0x03),
            accessibilityTreeIsComplete: true,
            renderingPipeline: ToolbarPresentationEvidenceWorkflow.canonicalRenderingPipeline,
            screenshotAttachmentID: screenshotAttachmentID,
            screenshotMediaType: screenshotAttachmentID == nil ? nil : "image/png",
            screenshotSource: screenshotAttachmentID == nil ? nil : "collector.secret.screenshot",
            screenshotEncodedSHA256: screenshotAttachmentID == nil ? nil : digest(0x04),
            authentication: [1]
        )
    }

    private func signedManifest(
        _ manifest: ToolbarPresentationCaptureManifest
    ) throws -> ToolbarPresentationCaptureManifest {
        let authenticationData = try ToolbarPresentationEvidenceWorkflow.canonicalCaptureManifestAuthenticationData(
            for: manifest,
            cancellationCheck: { false }
        )
        return copyManifest(
            manifest,
            authentication: Self.manifestAuthentication(
                collector: manifest.collector,
                canonicalManifest: authenticationData
            )
        )
    }

    private func attachment(
        id: AccessibilityStableID,
        kind: ToolbarPresentationEvidenceAttachmentKind,
        capture: AccessibilityEvidenceRevisionReference,
        provenance: AccessibilityEvidenceCaptureProvenance,
        manifest: ToolbarPresentationCaptureManifest,
        bytes: Data,
        content: Data,
        evidence: ToolbarPresentationEvidenceBundle,
        mediaType: String = ToolbarPresentationEvidenceWorkflow.accessibilityAttachmentMediaType,
        source: String = ToolbarPresentationEvidenceWorkflow.accessibilityAttachmentSource
    ) -> ToolbarPresentationEvidenceAttachment {
        ToolbarPresentationEvidenceAttachment(
            id: id,
            kind: kind,
            scenario: capture,
            manifest: evidence.manifest,
            layout: evidence.layout,
            provenance: provenance,
            mediaType: mediaType,
            byteCount: bytes.count,
            sha256: sha256(bytes),
            contentSHA256: sha256(content),
            captureManifestSHA256: sha256(fullManifestData(manifest)),
            source: source
        )
    }

    private func fullManifestData(_ manifest: ToolbarPresentationCaptureManifest) -> Data {
        var data = try! ToolbarPresentationEvidenceWorkflow.canonicalCaptureManifestAuthenticationData(
            for: manifest,
            cancellationCheck: { false }
        )
        appendUInt64(UInt64(manifest.authentication.count), to: &data)
        data.append(contentsOf: manifest.authentication)
        return data
    }

    private func captureStateData(_ capture: ToolbarPresentationLifecycleCapture) -> Data {
        var writer = WireWriter()
        writer.string("lifecycle-state-v4")
        writer.string(capture.scenario.rawValue)
        writer.reference(capture.reference)
        writer.reference(capture.manifest)
        writer.reference(capture.layout)
        writer.provenance(capture.provenance)
        writer.string(capture.origin.rawValue)
        writer.items(capture.items)
        writer.canonicalControls(capture.controls)
        writer.canonicalInteractions(capture.interactions)
        writer.canonicalFocusMovements(capture.focusMovements)
        writer.string(capture.accessibilityAttachmentID.rawValue)
        writer.string(capture.source)
        return writer.data
    }

    private func captureStateData(_ capture: ToolbarPresentationWindowCapture) -> Data {
        var writer = WireWriter()
        writer.string("window-state-v4")
        writer.string(capture.context.rawValue)
        writer.reference(capture.reference)
        writer.string(capture.lifecycleScenario.rawValue)
        writer.reference(capture.manifest)
        writer.reference(capture.layout)
        writer.provenance(capture.provenance)
        writer.string(capture.origin.rawValue)
        writer.items(capture.items)
        writer.canonicalControls(capture.controls)
        writer.canonicalInteractions(capture.interactions)
        writer.canonicalFocusMovements(capture.focusMovements)
        writer.string(capture.screenshotAttachmentID.rawValue)
        writer.string(capture.accessibilityAttachmentID.rawValue)
        writer.string(capture.source)
        return writer.data
    }

    private func accessibilityTreeData(_ tree: [ToolbarPresentationAXElementObservation]) -> Data {
        var writer = WireWriter()
        writer.string("toolbar-ax-tree-v4")
        writer.canonicalAccessibilityTree(tree)
        return writer.data
    }

    private func evaluate(
        _ fixture: Fixture,
        limits: ToolbarPresentationEvidenceLimits = .default,
        resolver: ToolbarPresentationEvidenceWorkflow.AttachmentResolver? = nil,
        authenticator customAuthenticator: ToolbarPresentationEvidenceWorkflow.CaptureManifestAuthenticator? = nil
    ) throws -> ToolbarPresentationEvidenceWorkflowResult {
        try ToolbarPresentationEvidenceWorkflow.evaluate(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            limits: limits,
            attachmentResolver: resolver ?? fixture.resolver(),
            captureManifestAuthenticator: customAuthenticator ?? authenticator,
            cancellationCheck: { false }
        )
    }

    private var authenticator: ToolbarPresentationEvidenceWorkflow.CaptureManifestAuthenticator {
        let trustedCollector = reference("collector.secret", 5)
        return { collector, canonicalManifest, authentication, checkpoint in
            try checkpoint(UInt64(canonicalManifest.count + authentication.count))
            return collector == trustedCollector
                && Self.manifestAuthentication(
                    collector: collector,
                    canonicalManifest: canonicalManifest
                ) == authentication
        }
    }

    private static func manifestAuthentication(
        collector: AccessibilityEvidenceRevisionReference,
        canonicalManifest: Data
    ) -> [UInt8] {
        var writer = WireWriter()
        writer.reference(collector)
        writer.data.append(canonicalManifest)
        return Array(SHA256.hash(data: writer.data))
    }

    private func assertInvalidCapture(
        _ capture: ToolbarPresentationLifecycleCapture,
        at index: Int,
        in fixture: Fixture,
        field: ToolbarPresentationEvidenceField,
        reSign: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var captures = fixture.evidence.lifecycleCaptures
        captures[index] = capture
        assertWorkflowError(.invalidEvidence(field), file: file, line: line) {
            let changed = replacingEvidence(fixture, lifecycleCaptures: captures)
            return try evaluate(reSign ? rebind(changed, lifecycleCaptures: captures) : changed)
        }
    }

    private func assertWorkflowError<T>(
        _ expected: ToolbarPresentationEvidenceWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ToolbarPresentationEvidenceWorkflowError, expected, file: file, line: line)
        }
    }

    private func replacingPresentation(
        _ capture: ToolbarPresentationLifecycleCapture,
        items: [ToolbarAuditItem]
    ) -> ToolbarPresentationLifecycleCapture {
        let scope = captureScope(capture)
        return replacingLifecycleCapture(
            capture,
            items: items,
            accessibilityTree: accessibilityTree(
                controls: capture.controls,
                interactions: capture.interactions,
                items: items,
                scope: scope,
                geometry: capture.captureManifest.geometry
            ),
            focusMovements: focusMovements(
                controls: capture.controls,
                interactions: capture.interactions,
                items: items,
                scope: scope
            )
        )
    }

    private func replacingLifecycleCapture(
        _ capture: ToolbarPresentationLifecycleCapture,
        provenance: AccessibilityEvidenceCaptureProvenance? = nil,
        items: [ToolbarAuditItem]? = nil,
        controls: [ToolbarAuditControlObservation]? = nil,
        interactions: [ToolbarPresentationInteractionCapture]? = nil,
        accessibilityTree: [ToolbarPresentationAXElementObservation]? = nil,
        focusMovements: [ToolbarPresentationFocusMovement]? = nil,
        captureManifest: ToolbarPresentationCaptureManifest? = nil
    ) -> ToolbarPresentationLifecycleCapture {
        ToolbarPresentationLifecycleCapture(
            scenario: capture.scenario,
            reference: capture.reference,
            manifest: capture.manifest,
            layout: capture.layout,
            provenance: provenance ?? capture.provenance,
            origin: capture.origin,
            items: items ?? capture.items,
            controls: controls ?? capture.controls,
            interactions: interactions ?? capture.interactions,
            accessibilityTree: accessibilityTree ?? capture.accessibilityTree,
            focusMovements: focusMovements ?? capture.focusMovements,
            captureManifest: captureManifest ?? capture.captureManifest,
            accessibilityAttachmentID: capture.accessibilityAttachmentID,
            source: capture.source
        )
    }

    private func replacingWindowCapture(
        _ capture: ToolbarPresentationWindowCapture,
        controls: [ToolbarAuditControlObservation]? = nil,
        interactions: [ToolbarPresentationInteractionCapture]? = nil,
        accessibilityTree: [ToolbarPresentationAXElementObservation]? = nil,
        focusMovements: [ToolbarPresentationFocusMovement]? = nil,
        captureManifest: ToolbarPresentationCaptureManifest? = nil
    ) -> ToolbarPresentationWindowCapture {
        ToolbarPresentationWindowCapture(
            context: capture.context,
            reference: capture.reference,
            lifecycleScenario: capture.lifecycleScenario,
            manifest: capture.manifest,
            layout: capture.layout,
            provenance: capture.provenance,
            origin: capture.origin,
            items: capture.items,
            controls: controls ?? capture.controls,
            interactions: interactions ?? capture.interactions,
            accessibilityTree: accessibilityTree ?? capture.accessibilityTree,
            focusMovements: focusMovements ?? capture.focusMovements,
            captureManifest: captureManifest ?? capture.captureManifest,
            screenshotAttachmentID: capture.screenshotAttachmentID,
            accessibilityAttachmentID: capture.accessibilityAttachmentID,
            source: capture.source
        )
    }

    private func replacingEvidence(
        _ fixture: Fixture,
        lifecycleCaptures: [ToolbarPresentationLifecycleCapture]? = nil,
        windowCaptures: [ToolbarPresentationWindowCapture]? = nil,
        attachments: [ToolbarPresentationEvidenceAttachment]? = nil
    ) -> Fixture {
        Fixture(
            inventory: fixture.inventory,
            evidence: evidence(
                fixture.evidence,
                lifecycleCaptures: lifecycleCaptures,
                windowCaptures: windowCaptures,
                attachments: attachments
            ),
            payloads: fixture.payloads
        )
    }

    private func evidence(
        _ evidence: ToolbarPresentationEvidenceBundle,
        reference: AccessibilityEvidenceRevisionReference? = nil,
        lifecycleCaptures: [ToolbarPresentationLifecycleCapture]? = nil,
        windowCaptures: [ToolbarPresentationWindowCapture]? = nil,
        attachments: [ToolbarPresentationEvidenceAttachment]? = nil
    ) -> ToolbarPresentationEvidenceBundle {
        ToolbarPresentationEvidenceBundle(
            reference: reference ?? evidence.reference,
            app: evidence.app,
            build: evidence.build,
            buildBinding: evidence.buildBinding,
            inventory: evidence.inventory,
            manifest: evidence.manifest,
            layout: evidence.layout,
            lifecycleCaptures: lifecycleCaptures ?? evidence.lifecycleCaptures,
            windowCaptures: windowCaptures ?? evidence.windowCaptures,
            attachments: attachments ?? evidence.attachments
        )
    }

    private func removingAttachment(_ id: AccessibilityStableID, from fixture: Fixture) -> Fixture {
        var payloads = fixture.payloads
        payloads[id] = nil
        return Fixture(
            inventory: fixture.inventory,
            evidence: evidence(
                fixture.evidence,
                attachments: fixture.evidence.attachments.filter { $0.id != id }
            ),
            payloads: payloads
        )
    }

    private func rebindScreenshots(
        _ fixture: Fixture,
        replacements: [AccessibilityStableID: Data]
    ) throws -> Fixture {
        let bare = evidence(fixture.evidence, attachments: [])
        var screenshotData = fixture.payloads.filter { id, _ in
            fixture.evidence.windowCaptures.contains { $0.screenshotAttachmentID == id }
        }
        for (id, data) in replacements { screenshotData[id] = data }
        return try bindEvidence(inventory: fixture.inventory, evidence: bare, screenshotData: screenshotData)
    }

    private func replacingScreenshotPixels(
        in fixture: Fixture,
        alpha: UInt8 = 0xFF,
        meaningfulPixelCount: Int? = nil
    ) throws -> Fixture {
        var replacements: [AccessibilityStableID: Data] = [:]
        for capture in fixture.evidence.windowCaptures {
            replacements[capture.screenshotAttachmentID] = try encodedImage(
                type: "public.png",
                variant: 91,
                context: capture.context,
                alpha: alpha,
                meaningfulPixelCount: meaningfulPixelCount
            )
        }
        return try rebindScreenshots(fixture, replacements: replacements)
    }

    private func copyManifest(
        _ value: ToolbarPresentationCaptureManifest,
        collector: AccessibilityEvidenceRevisionReference? = nil,
        app: AccessibilityEvidenceRevisionReference? = nil,
        build: AccessibilityEvidenceRevisionReference? = nil,
        buildBinding: AccessibilityEvidenceBuildBinding? = nil,
        inventory: AccessibilityEvidenceRevisionReference? = nil,
        manifest: AccessibilityEvidenceRevisionReference? = nil,
        layout: AccessibilityEvidenceRevisionReference? = nil,
        context: ToolbarPresentationCaptureContext? = nil,
        geometry: ToolbarPresentationCaptureGeometry? = nil,
        windowState: ToolbarPresentationCapturedWindowState? = nil,
        stateSHA256: [UInt8]? = nil,
        accessibilityTreeSHA256: [UInt8]? = nil,
        screenshotPixelSHA256: [UInt8]?? = nil,
        renderingPipeline: AccessibilityEvidenceRevisionReference? = nil,
        renderingImplementation: String? = nil,
        screenshotEncodedSHA256: [UInt8]?? = nil,
        authentication: [UInt8]? = nil
    ) -> ToolbarPresentationCaptureManifest {
        ToolbarPresentationCaptureManifest(
            formatVersion: value.formatVersion,
            collector: collector ?? value.collector,
            capture: value.capture,
            origin: value.origin,
            app: app ?? value.app,
            build: build ?? value.build,
            buildBinding: buildBinding ?? value.buildBinding,
            inventory: inventory ?? value.inventory,
            manifest: manifest ?? value.manifest,
            layout: layout ?? value.layout,
            configuration: value.configuration,
            contractRevision: value.contractRevision,
            manifestRevision: value.manifestRevision,
            context: context ?? value.context,
            geometry: geometry ?? value.geometry,
            windowState: windowState ?? value.windowState,
            stateSHA256: stateSHA256 ?? value.stateSHA256,
            accessibilityTreeSHA256: accessibilityTreeSHA256 ?? value.accessibilityTreeSHA256,
            screenshotPixelSHA256: screenshotPixelSHA256 ?? value.screenshotPixelSHA256,
            accessibilityTreeIsComplete: value.accessibilityTreeIsComplete,
            renderingPipeline: renderingPipeline ?? value.renderingPipeline,
            renderingImplementation: renderingImplementation ?? value.renderingImplementation,
            screenshotAttachmentID: value.screenshotAttachmentID,
            screenshotMediaType: value.screenshotMediaType,
            screenshotSource: value.screenshotSource,
            screenshotEncodedSHA256: screenshotEncodedSHA256 ?? value.screenshotEncodedSHA256,
            authentication: authentication ?? value.authentication
        )
    }

    private func observation(
        _ value: ToolbarPresentationAXElementObservation,
        siblingIndex: Int? = nil,
        frame: ToolbarPresentationEvidenceRect? = nil
    ) -> ToolbarPresentationAXElementObservation {
        ToolbarPresentationAXElementObservation(
            elementIdentity: value.elementIdentity,
            parentIdentity: value.parentIdentity,
            siblingIndex: siblingIndex ?? value.siblingIndex,
            frame: frame ?? value.frame,
            accessibility: value.accessibility
        )
    }

    private func concreteAX(_ value: ToolbarAuditAXMetadata, enabled: Bool) -> ToolbarAuditAXMetadata {
        ToolbarAuditAXMetadata(
            identifier: value.identifier,
            role: value.role,
            label: value.label,
            value: value.value,
            hint: value.hint,
            isEnabled: enabled,
            checkedState: value.checkedState,
            selectedState: value.selectedState,
            isKeyboardFocusable: value.isKeyboardFocusable,
            actions: value.actions
        )
    }

    private func ax(
        _ identifier: String,
        role: AccessibilitySemanticRole = .button,
        label: String,
        value: String? = nil,
        hint: String,
        enabled: Bool? = true,
        focusable: Bool = true,
        actions: Set<AccessibilitySemanticActionKind> = [.activate]
    ) -> ToolbarAuditAXMetadata {
        ToolbarAuditAXMetadata(
            identifier: toolbarID(identifier),
            role: role,
            label: label,
            value: value,
            hint: hint,
            isEnabled: enabled,
            isKeyboardFocusable: focusable,
            actions: actions
        )
    }

    private func encodedImage(
        type: String,
        variant: Int,
        context: ToolbarAuditScreenshotContext? = nil,
        metadataTag: String? = nil,
        orientation: Int = 1,
        frameCount: Int = 1,
        blank: Bool = false,
        alpha: UInt8 = 0xFF,
        meaningfulPixelCount: Int? = nil
    ) throws -> Data {
        let width = 40
        let height = 4
        var rgba = Data(capacity: width * height * 4)
        for index in 0..<(width * height) {
            let row = index / width
            let uniformBody = context == .freshWindow && row > 0
            let meaningful = meaningfulPixelCount.map { index < $0 } ?? true
            let base =
                blank || uniformBody || !meaningful
                ? UInt8(80 + variant % 10)
                : UInt8((index * 13 + variant * 17) % 220 + 20)
            rgba.append(
                contentsOf: [
                    base,
                    blank || uniformBody || !meaningful ? base : base ^ 0x55,
                    blank || uniformBody || !meaningful ? base : base ^ 0xAA,
                    alpha
                ]
            )
        }
        guard let provider = CGDataProvider(data: rgba as CFData),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else { throw ImageFixtureError.image }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type as CFString, frameCount, nil) else {
            throw ImageFixtureError.destination
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if let metadataTag {
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: metadataTag]
        }
        for _ in 0..<frameCount {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ImageFixtureError.finalize }
        return output as Data
    }

    private func canonicalFixtureScreenshotData(_ data: Data) throws -> Data {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
            let image = CGImageSourceCreateImageAtIndex(source, 0, imageOptions as CFDictionary),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw ImageFixtureError.image }
        let headerBytes = 24
        var result = Data(count: headerBytes + image.width * image.height * 4)
        let rendered = result.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                let context = CGContext(
                    data: baseAddress.advanced(by: headerBytes),
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            buffer[0..<8].copyBytes(from: "MMRGBA2\0".utf8)
            var width = UInt64(image.width).bigEndian
            var height = UInt64(image.height).bigEndian
            withUnsafeBytes(of: &width) { buffer[8..<16].copyBytes(from: $0) }
            withUnsafeBytes(of: &height) { buffer[16..<24].copyBytes(from: $0) }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else { throw ImageFixtureError.image }
        return result
    }

    private func corruptPNGCompressedPayload(_ data: Data) -> Data {
        var result = data
        var offset = 8
        while offset + 12 <= result.count {
            let length = Int(readUInt32(result, at: offset))
            guard offset + 12 + length <= result.count else { return result }
            let typeRange = (offset + 4)..<(offset + 8)
            if result[typeRange].elementsEqual(Data("IDAT".utf8)), length > 2 {
                result.replaceSubrange((offset + 8)..<(offset + 8 + length), with: [0])
                writeUInt32(1, to: &result, at: offset)
                let crc = crc32(result[(offset + 4)..<(offset + 9)])
                writeUInt32(crc, to: &result, at: offset + 9)
                return result
            }
            offset += length + 12
        }
        return result
    }

    private func duplicatePNGHeader(_ data: Data) -> Data {
        guard data.count >= 33 else { return data }
        var result = data
        result.insert(contentsOf: data[8..<33], at: 33)
        return result
    }

    private func nonconsecutivePNGData(_ data: Data) -> Data {
        guard let firstDataOffset = pngChunkOffset(0x4944_4154, in: data) else { return data }
        let length = Int(readUInt32(data, at: firstDataOffset))
        let chunkEnd = firstDataOffset + length + 12
        var result = data
        let ancillary = pngChunk(type: 0x7445_5874, payload: Data("note\0value".utf8))
        result.insert(contentsOf: ancillary, at: chunkEnd)
        result.insert(contentsOf: pngChunk(type: 0x4944_4154, payload: Data()), at: chunkEnd + ancillary.count)
        return result
    }

    private func insertingZeroLengthPNGData(beforeFirstDataIn data: Data) -> Data {
        guard let offset = pngChunkOffset(0x4944_4154, in: data) else { return data }
        var result = data
        result.insert(contentsOf: pngChunk(type: 0x4944_4154, payload: Data()), at: offset)
        return result
    }

    private func insertingPNGChunk(type: UInt32, payload: Data, in data: Data) -> Data {
        guard let offset = pngChunkOffset(0x4945_4E44, in: data) else { return data }
        var result = data
        result.insert(contentsOf: pngChunk(type: type, payload: payload), at: offset)
        return result
    }

    private func replacingPNGEXIF(in data: Data, with payload: Data) -> Data {
        guard let offset = pngChunkOffset(0x6558_4966, in: data) else { return data }
        let length = Int(readUInt32(data, at: offset))
        var result = data
        result.replaceSubrange(offset..<(offset + length + 12), with: pngChunk(type: 0x6558_4966, payload: payload))
        return result
    }

    private func invalidTIFFDirectoryOffset() -> Data {
        Data([0x49, 0x49, 0x2A, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    private func truncatedTIFFDirectory() -> Data {
        Data([0x49, 0x49, 0x2A, 0, 8, 0, 0, 0, 0, 0])
    }

    private func duplicateTIFFOrientations() -> Data {
        Data([
            0x49, 0x49, 0x2A, 0, 8, 0, 0, 0,
            2, 0,
            0x12, 0x01, 3, 0, 1, 0, 0, 0, 1, 0, 0, 0,
            0x12, 0x01, 3, 0, 1, 0, 0, 0, 1, 0, 0, 0,
            0, 0, 0, 0
        ])
    }

    private func insertingJPEGAPP1(in data: Data, tiff: Data) -> Data {
        guard data.starts(with: [0xFF, 0xD8]) else { return data }
        let payload = Data([0x45, 0x78, 0x69, 0x66, 0, 0]) + tiff
        let length = payload.count + 2
        guard length <= Int(UInt16.max) else { return data }
        var segment = Data([0xFF, 0xE1, UInt8(length >> 8), UInt8(truncatingIfNeeded: length)])
        segment.append(payload)
        var result = data
        result.insert(contentsOf: segment, at: 2)
        return result
    }

    private func pngMetadataFlood(_ data: Data) -> Data {
        var result = data
        let payload = Data(repeating: 0x41, count: 65_536)
        for _ in 0..<17 {
            result = insertingPNGChunk(type: 0x7445_5874, payload: payload, in: result)
        }
        return result
    }

    private func duplicateJPEGStartOfFrame(_ data: Data) -> Data {
        var offset = 2
        while offset + 4 <= data.count {
            guard data[offset] == 0xFF else { return data }
            let marker = data[offset + 1]
            guard marker != 0xDA, marker != 0xD9 else { return data }
            let length = Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            guard length >= 2, offset + 2 + length <= data.count else { return data }
            if [UInt8](arrayLiteral: 0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF)
                .contains(marker)
            {
                var result = data
                let segment = data[offset..<(offset + 2 + length)]
                result.insert(contentsOf: segment, at: offset + 2 + length)
                return result
            }
            offset += 2 + length
        }
        return data
    }

    private func jpegMetadataFlood(_ data: Data) -> Data {
        guard data.starts(with: [0xFF, 0xD8]) else { return data }
        var segment = Data([0xFF, 0xE0, 0xFF, 0xFF])
        segment.append(Data(repeating: 0, count: 65_533))
        var result = data
        for _ in 0..<17 { result.insert(contentsOf: segment, at: 2) }
        return result
    }

    private func emptyPNGData(_ data: Data) -> Data {
        var result = data
        var offset = 8
        while offset + 12 <= result.count {
            let length = Int(readUInt32(result, at: offset))
            guard offset + length + 12 <= result.count else { return data }
            if readUInt32(result, at: offset + 4) == 0x4944_4154 {
                result.replaceSubrange((offset + 8)..<(offset + 8 + length), with: [])
                writeUInt32(0, to: &result, at: offset)
                let checksum = crc32(result[(offset + 4)..<(offset + 8)])
                writeUInt32(checksum, to: &result, at: offset + 8)
                offset += 12
            } else {
                offset += length + 12
            }
        }
        return result
    }

    private func pngChunkOffset(_ type: UInt32, in data: Data) -> Int? {
        var offset = 8
        while offset + 12 <= data.count {
            let length = Int(readUInt32(data, at: offset))
            guard offset + length + 12 <= data.count else { return nil }
            if readUInt32(data, at: offset + 4) == type { return offset }
            offset += length + 12
        }
        return nil
    }

    private func pngChunk(type: UInt32, payload: Data) -> Data {
        var result = Data(count: 8)
        writeUInt32(UInt32(payload.count), to: &result, at: 0)
        writeUInt32(type, to: &result, at: 4)
        result.append(payload)
        var checksumData = result[4...]
        let checksum = crc32(checksumData)
        result.append(Data(count: 4))
        writeUInt32(checksum, to: &result, at: result.count - 4)
        checksumData.removeAll()
        return result
    }

    private func crc32<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for byte in data[offset..<(offset + 8)] { value = value << 8 | UInt64(byte) }
        return value
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for byte in data[offset..<(offset + 4)] { value = value << 8 | UInt32(byte) }
        return value
    }

    private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value >> 24)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
        data[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
        data[offset + 3] = UInt8(truncatingIfNeeded: value)
    }

    private func appendUInt64(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private func sha256(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private func digest(_ byte: UInt8) -> [UInt8] {
        [UInt8](repeating: byte, count: SHA256.Digest.byteCount)
    }

    private func binding(artifact: UInt8, signing: UInt8) -> AccessibilityEvidenceBuildBinding {
        AccessibilityEvidenceBuildBinding(artifactSHA256: digest(artifact), signingIdentitySHA256: digest(signing))
    }

    private func provenance(
        collector: AccessibilityEvidenceRevisionReference,
        build: AccessibilityEvidenceRevisionReference,
        buildBinding: AccessibilityEvidenceBuildBinding,
        nonce: UInt8
    ) -> AccessibilityEvidenceCaptureProvenance {
        AccessibilityEvidenceCaptureProvenance(
            capturedAtUnixMilliseconds: 1_800_000_000_000 + UInt64(nonce),
            runNonce: [UInt8](repeating: nonce, count: 16),
            collector: collector,
            build: build,
            buildBinding: buildBinding
        )
    }

    private func reference(_ value: String, _ revision: UInt64) -> AccessibilityEvidenceRevisionReference {
        AccessibilityEvidenceRevisionReference(
            id: accessibilityID(value),
            revision: AccessibilityEvidenceRevision(rawValue: revision)
        )
    }

    private func controlID(_ command: ToolbarAuditCommand) -> ToolbarAuditStableID {
        toolbarID("control.\(command.rawValue)")
    }

    private func primaryActionID(_ command: ToolbarAuditCommand) -> ToolbarAuditStableID {
        toolbarID("action.\(command.rawValue)")
    }

    private var saveSecondaryActionIDs: [ToolbarAuditStableID] {
        [toolbarID("action.save.leftAs"), toolbarID("action.save.rightAs")]
    }

    private func command(for controlID: ToolbarAuditStableID) -> ToolbarAuditCommand {
        ToolbarAuditCommand.allCases.first { self.controlID($0) == controlID }!
    }

    private func toolbarID(_ value: String) -> ToolbarAuditStableID {
        ToolbarAuditStableID(rawValue: value)
    }

    private func accessibilityID(_ value: String) -> AccessibilityStableID {
        AccessibilityStableID(rawValue: value)
    }

    private func controlElementID(_ command: ToolbarAuditCommand, scope: String) -> AccessibilityStableID {
        accessibilityID("element.\(scope).control.\(command.rawValue)")
    }

    private func menuElementID(_ command: ToolbarAuditCommand, scope: String) -> AccessibilityStableID {
        accessibilityID("element.\(scope).menu.\(command.rawValue)")
    }

    private func menuActionElementID(_ action: ToolbarAuditStableID, scope: String) -> AccessibilityStableID {
        accessibilityID("element.\(scope).menu-item.\(action.rawValue)")
    }

    private func captureScope(_ capture: ToolbarPresentationLifecycleCapture) -> String {
        "lifecycle.\(capture.scenario.rawValue)"
    }

    private func scenarioRank(_ scenario: ToolbarAuditLifecycleScenario) -> Int {
        ToolbarAuditLifecycleScenario.allCases.firstIndex(of: scenario)!
    }

    private var captureGeometry: ToolbarPresentationCaptureGeometry {
        ToolbarPresentationCaptureGeometry(
            window: ToolbarPresentationEvidenceRect(x: 0, y: 0, width: 40, height: 4),
            toolbar: ToolbarPresentationEvidenceRect(x: 0, y: 3, width: 39, height: 1),
            backingScaleThousandths: 1_000
        )
    }

    private var validWindowState: ToolbarPresentationCapturedWindowState {
        ToolbarPresentationCapturedWindowState(
            isVisible: true,
            isKeyWindow: true,
            isMainWindow: true,
            isMiniaturized: false,
            isFullScreen: false
        )
    }

    private func required<T>(_ value: T?) throws -> T {
        guard let value else { throw ResourceError.missing }
        return value
    }

    private struct Fixture: Sendable {
        let inventory: ToolbarPresentationEvidenceInventory
        let evidence: ToolbarPresentationEvidenceBundle
        let payloads: [AccessibilityStableID: Data]

        func resolver(chunkSize: Int = .max) -> ToolbarPresentationEvidenceWorkflow.AttachmentResolver {
            { id, declaredByteCount, sink in
                guard let data = payloads[id], data.count == declaredByteCount else {
                    throw ResourceError.missing
                }
                var offset = 0
                while offset < data.count {
                    let end = min(data.count, offset + chunkSize)
                    try sink.append(data[offset..<end])
                    offset = end
                }
            }
        }
    }

    private struct WireWriter {
        var data = Data()

        mutating func byte(_ value: UInt8) { data.append(value) }

        mutating func uint64(_ value: UInt64) {
            var bigEndian = value.bigEndian
            Swift.withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
        }

        mutating func int64(_ value: Int64) { uint64(UInt64(bitPattern: value)) }
        mutating func bool(_ value: Bool) { byte(value ? 1 : 0) }
        mutating func count(_ value: Int) { uint64(UInt64(value)) }

        mutating func string(_ value: String) {
            count(value.utf8.count)
            data.append(contentsOf: value.utf8)
        }

        mutating func optionalString(_ value: String?) {
            guard let value else {
                bool(false)
                return
            }
            bool(true)
            string(value)
        }

        mutating func reference(_ value: AccessibilityEvidenceRevisionReference) {
            string(value.id.rawValue)
            uint64(value.revision.rawValue)
        }

        mutating func provenance(_ value: AccessibilityEvidenceCaptureProvenance) {
            uint64(value.capturedAtUnixMilliseconds)
            count(value.runNonce.count)
            data.append(contentsOf: value.runNonce)
            reference(value.collector)
            reference(value.build)
            data.append(contentsOf: value.buildBinding.artifactSHA256)
            data.append(contentsOf: value.buildBinding.signingIdentitySHA256)
        }

        mutating func items(_ values: [ToolbarAuditItem]) {
            count(values.count)
            for value in values {
                switch value {
                case .command(let command):
                    byte(0)
                    string(command.rawValue)
                case .separator:
                    byte(1)
                }
            }
        }

        mutating func canonicalControls(_ values: [ToolbarAuditControlObservation]) {
            let sorted = values.sorted {
                ToolbarAuditCommand.allCases.firstIndex(of: $0.command)!
                    < ToolbarAuditCommand.allCases.firstIndex(of: $1.command)!
            }
            count(sorted.count)
            for value in sorted { observation(value) }
        }

        mutating func observation(_ value: ToolbarAuditControlObservation) {
            string(value.id.rawValue)
            string(value.command.rawValue)
            behavior(value.behavior)
            optionalString(value.tooltip)
            shortcut(value.shortcut)
            ax(value.accessibility)
            availability(value.availability)
        }

        mutating func behavior(_ value: ToolbarAuditControlBehavior) {
            string(value.primaryActionID.rawValue)
            switch value.secondary {
            case .none:
                byte(0)
            case .menu(let actions):
                byte(1)
                count(actions.count)
                for action in actions {
                    string(action.id.rawValue)
                    ax(action.accessibility)
                }
            }
        }

        mutating func shortcut(_ value: ToolbarAuditShortcut?) {
            guard let value else {
                bool(false)
                return
            }
            bool(true)
            string(value.key)
            let modifiers = AccessibilityKeyboardModifier.allCases.filter(value.modifiers.contains)
            count(modifiers.count)
            for modifier in modifiers { string(modifier.rawValue) }
            string(value.display)
        }

        mutating func ax(_ value: ToolbarAuditAXMetadata) {
            string(value.identifier.rawValue)
            string(value.role.rawValue)
            string(value.label)
            optionalString(value.value)
            string(value.hint)
            byte(value.isEnabled.map { $0 ? 2 : 1 } ?? 0)
            string(value.checkedState.rawValue)
            string(value.selectedState.rawValue)
            bool(value.isKeyboardFocusable)
            let actions = AccessibilitySemanticActionKind.allCases.filter(value.actions.contains)
            count(actions.count)
            for action in actions { string(action.rawValue) }
        }

        mutating func availability(_ value: ToolbarAuditAvailability) {
            switch value {
            case .enabled:
                byte(0)
            case .disabled(let reason):
                byte(1)
                string(reason.rawValue)
            }
        }

        mutating func canonicalInteractions(_ values: [ToolbarPresentationInteractionCapture]) {
            let sorted = values.sorted(by: interactionLess)
            count(sorted.count)
            for value in sorted {
                string(value.scenario.rawValue)
                string(value.controlID.rawValue)
                string(value.elementIdentity.rawValue)
                string(value.actionID.rawValue)
                string(value.invocation.rawValue)
                outcome(value.outcome)
                string(value.source)
            }
        }

        mutating func outcome(_ value: ToolbarAuditInteractionOutcome) {
            switch value {
            case .invoked(let actionID):
                byte(0)
                string(actionID.rawValue)
            case .menuPresented(let actionIDs):
                byte(1)
                count(actionIDs.count)
                for id in actionIDs { string(id.rawValue) }
            case .blocked:
                byte(2)
            case .noOp:
                byte(3)
            case .failed(let code):
                byte(4)
                string(code.rawValue)
            }
        }

        mutating func canonicalAccessibilityTree(_ values: [ToolbarPresentationAXElementObservation]) {
            let sorted = values.sorted { utf8Less($0.elementIdentity.rawValue, $1.elementIdentity.rawValue) }
            count(sorted.count)
            for value in sorted {
                string(value.elementIdentity.rawValue)
                optionalString(value.parentIdentity?.rawValue)
                count(value.siblingIndex)
                rect(value.frame)
                ax(value.accessibility)
            }
        }

        mutating func rect(_ value: ToolbarPresentationEvidenceRect) {
            int64(Int64(value.x))
            int64(Int64(value.y))
            int64(Int64(value.width))
            int64(Int64(value.height))
        }

        mutating func canonicalFocusMovements(_ values: [ToolbarPresentationFocusMovement]) {
            let sorted = values.sorted(by: focusLess)
            count(sorted.count)
            for value in sorted {
                string(value.controlID.rawValue)
                string(value.fromElementIdentity.rawValue)
                string(value.toElementIdentity.rawValue)
                string(value.traversal.rawValue)
            }
        }

        private func interactionLess(
            _ left: ToolbarPresentationInteractionCapture,
            _ right: ToolbarPresentationInteractionCapture
        ) -> Bool {
            if left.scenario != right.scenario {
                return ToolbarAuditLifecycleScenario.allCases.firstIndex(of: left.scenario)!
                    < ToolbarAuditLifecycleScenario.allCases.firstIndex(of: right.scenario)!
            }
            if left.controlID != right.controlID {
                return utf8Less(left.controlID.rawValue, right.controlID.rawValue)
            }
            if left.elementIdentity != right.elementIdentity {
                return utf8Less(left.elementIdentity.rawValue, right.elementIdentity.rawValue)
            }
            if left.actionID != right.actionID {
                return utf8Less(left.actionID.rawValue, right.actionID.rawValue)
            }
            if left.invocation != right.invocation {
                return ToolbarAuditInvocationKind.allCases.firstIndex(of: left.invocation)!
                    < ToolbarAuditInvocationKind.allCases.firstIndex(of: right.invocation)!
            }
            return utf8Less(outcomeKey(left.outcome), outcomeKey(right.outcome))
        }

        private func focusLess(
            _ left: ToolbarPresentationFocusMovement,
            _ right: ToolbarPresentationFocusMovement
        ) -> Bool {
            if left.controlID != right.controlID {
                return utf8Less(left.controlID.rawValue, right.controlID.rawValue)
            }
            if left.fromElementIdentity != right.fromElementIdentity {
                return utf8Less(left.fromElementIdentity.rawValue, right.fromElementIdentity.rawValue)
            }
            if left.toElementIdentity != right.toElementIdentity {
                return utf8Less(left.toElementIdentity.rawValue, right.toElementIdentity.rawValue)
            }
            return ToolbarPresentationFocusTraversal.allCases.firstIndex(of: left.traversal)!
                < ToolbarPresentationFocusTraversal.allCases.firstIndex(of: right.traversal)!
        }

        private func outcomeKey(_ value: ToolbarAuditInteractionOutcome) -> String {
            switch value {
            case .invoked(let id): "0:\(id.rawValue)"
            case .menuPresented(let ids): "1:\(ids.map(\.rawValue).joined(separator: "\0"))"
            case .blocked: "2"
            case .noOp: "3"
            case .failed(let id): "4:\(id.rawValue)"
            }
        }

        private func utf8Less(_ left: String, _ right: String) -> Bool {
            left.utf8.lexicographicallyPrecedes(right.utf8)
        }
    }

    private final class LockedCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0

        var value: Int {
            lock.withLock { storage }
        }

        func increment() {
            lock.withLock { storage += 1 }
        }
    }

    private final class CancellationLatch: @unchecked Sendable {
        private let lock = NSLock()
        private let cancelAfter: Int
        private var checks = 0

        init(cancelAfter: Int) {
            self.cancelAfter = cancelAfter
        }

        func shouldCancel() -> Bool {
            lock.withLock {
                checks += 1
                return checks >= cancelAfter
            }
        }
    }

    private enum ResourceError: Error, Equatable {
        case missing
        case offline
        case denied
    }

    private enum ImageFixtureError: Error {
        case image
        case destination
        case finalize
    }
}
