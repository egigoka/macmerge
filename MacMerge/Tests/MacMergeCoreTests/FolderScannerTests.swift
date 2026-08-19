import Darwin
import Dispatch
import Foundation
@testable import MacMergeCore
import XCTest

@MainActor
final class FolderScannerTests: XCTestCase {
    func testRecursiveScanIsDeterministicAndUTF8PathSorted() async throws {
        let root = try temporaryDirectory()
        let nested = root.appending(path: "a-folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("last".utf8).write(to: root.appending(path: "z.txt"))
        try Data("nested-last".utf8).write(to: nested.appending(path: "z.txt"))
        try Data("first".utf8).write(to: root.appending(path: "A.txt"))
        try Data("nested-first".utf8).write(to: nested.appending(path: "a.txt"))
        try Data().write(to: root.appending(path: "¢.txt"))
        try Data().write(to: root.appending(path: "ß.txt"))
        try Data().write(to: root.appending(path: "Ω.txt"))
        try Data().write(to: root.appending(path: "一.txt"))
        try Data().write(to: root.appending(path: "😀.txt"))

        let first = try await FolderScanner().scan(at: root)
        let second = try await FolderScanner().scan(at: root)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rootURL, root.standardizedFileURL)
        XCTAssertEqual(first.entries.map(\.relativePath), [
            "A.txt",
            "a-folder",
            "a-folder/a.txt",
            "a-folder/z.txt",
            "z.txt",
            "¢.txt",
            "ß.txt",
            "Ω.txt",
            "一.txt",
            "😀.txt",
        ])
        XCTAssertEqual(first.issues, [])
    }

    func testHiddenPolicyIncludesByDefaultAndRecursivelyExcludesDotEntries() async throws {
        let root = try temporaryDirectory()
        let hiddenDirectory = root.appending(path: ".hidden-directory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: false)
        try Data().write(to: hiddenDirectory.appending(path: "child.txt"))
        try Data().write(to: root.appending(path: ".hidden-file"))
        try Data().write(to: root.appending(path: "visible.txt"))

        let included = try await FolderScanner().scan(at: root)
        let excluded = try await FolderScanner(options: FolderScanOptions(
            hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets
        )).scan(at: root)

        XCTAssertEqual(included.entries.map(\.relativePath), [
            ".hidden-directory",
            ".hidden-directory/child.txt",
            ".hidden-file",
            "visible.txt",
        ])
        XCTAssertEqual(excluded.entries.map(\.relativePath), ["visible.txt"])
        XCTAssertEqual(excluded.issues, [])
    }

    func testHiddenPolicyDoesNotFollowVisibleLinkIntoHiddenTarget() async throws {
        let root = try temporaryDirectory()
        let hiddenTarget = root.appending(path: ".hidden-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hiddenTarget, withIntermediateDirectories: false)
        try Data("secret".utf8).write(to: hiddenTarget.appending(path: "secret.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "visible-link").path,
            withDestinationPath: ".hidden-target"
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets,
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), ["visible-link"])
        XCTAssertEqual(result.entries.map(\.kind), [.symbolicLink])
        XCTAssertEqual(result.issues, [])
    }

    func testHiddenPolicyDoesNotFollowVisibleLinkThroughHiddenAlias() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("secret".utf8).write(to: target.appending(path: "secret.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: ".hidden-alias").path,
            withDestinationPath: "z-target"
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "visible-link").path,
            withDestinationPath: ".hidden-alias"
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets,
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), [
            "visible-link",
            "z-target",
            "z-target/secret.txt",
        ])
        XCTAssertEqual(result.issues, [])
    }

    func testHiddenPolicyDoesNotFollowVisibleLinkThroughUFHiddenAliasWhenSupported() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let hiddenAlias = root.appending(path: "z-hidden-alias")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("secret".utf8).write(to: target.appending(path: "secret.txt"))
        try FileManager.default.createSymbolicLink(at: hiddenAlias, withDestinationURL: target)
        try setUFHiddenFlagIfSupported(at: hiddenAlias)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-visible-link").path,
            withDestinationPath: hiddenAlias.lastPathComponent
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets,
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), [
            "a-visible-link",
            "z-target",
            "z-target/secret.txt",
        ])
        XCTAssertEqual(result.issues, [])
    }

    func testHiddenPolicyInspectsHiddenTargetReachedAfterMultipleVisibleLinks() async throws {
        let root = try temporaryDirectory()
        let hiddenTarget = root.appending(path: ".hidden-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hiddenTarget, withIntermediateDirectories: false)
        try Data("secret".utf8).write(to: hiddenTarget.appending(path: "secret.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-visible-link").path,
            withDestinationPath: hiddenTarget.lastPathComponent
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-visible-link").path,
            withDestinationPath: "b-visible-link"
        )

        let result = try await hiddenExcludingFollowingScanner().scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), [
            "a-visible-link",
            "b-visible-link",
        ])
        XCTAssertEqual(result.issues, [])
    }

    func testHiddenPolicyInspectsHiddenIntermediateDirectoryAtLaterHop() async throws {
        let root = try temporaryDirectory()
        let hiddenDirectory = root.appending(path: ".hidden-directory", directoryHint: .isDirectory)
        let target = hiddenDirectory.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: target.appending(path: "secret.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-visible-link").path,
            withDestinationPath: ".hidden-directory/target"
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-visible-link").path,
            withDestinationPath: "b-visible-link"
        )

        let result = try await hiddenExcludingFollowingScanner().scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), [
            "a-visible-link",
            "b-visible-link",
        ])
        XCTAssertEqual(result.issues, [])
    }

    func testHiddenPolicyInspectsHiddenIntermediateSymbolicLinkAtLaterHop() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("secret".utf8).write(to: target.appending(path: "secret.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: ".hidden-intermediate").path,
            withDestinationPath: target.lastPathComponent
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-visible-link").path,
            withDestinationPath: ".hidden-intermediate"
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-visible-link").path,
            withDestinationPath: "b-visible-link"
        )

        let result = try await hiddenExcludingFollowingScanner().scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), [
            "a-visible-link",
            "b-visible-link",
            "z-target",
            "z-target/secret.txt",
        ])
        XCTAssertEqual(result.issues, [])
    }

    func testHiddenPolicyInspectsUFHiddenIntermediateDirectoryAtLaterHopWhenSupported() async throws {
        let root = try temporaryDirectory()
        let hiddenDirectory = root.appending(path: "z-hidden-directory", directoryHint: .isDirectory)
        let target = hiddenDirectory.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: target.appending(path: "secret.txt"))
        try setUFHiddenFlagIfSupported(at: hiddenDirectory)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-visible-link").path,
            withDestinationPath: "z-hidden-directory/target"
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-visible-link").path,
            withDestinationPath: "b-visible-link"
        )

        let result = try await hiddenExcludingFollowingScanner().scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), [
            "a-visible-link",
            "b-visible-link",
        ])
        XCTAssertEqual(result.issues, [])
    }

    func testHiddenPolicyInspectsUFHiddenIntermediateSymbolicLinkAtLaterHopWhenSupported()
        async throws
    {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let hiddenIntermediate = root.appending(path: "z-hidden-intermediate")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("secret".utf8).write(to: target.appending(path: "secret.txt"))
        try FileManager.default.createSymbolicLink(at: hiddenIntermediate, withDestinationURL: target)
        try setUFHiddenFlagIfSupported(at: hiddenIntermediate)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-visible-link").path,
            withDestinationPath: hiddenIntermediate.lastPathComponent
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-visible-link").path,
            withDestinationPath: "b-visible-link"
        )

        let result = try await hiddenExcludingFollowingScanner().scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), [
            "a-visible-link",
            "b-visible-link",
            "z-target",
            "z-target/secret.txt",
        ])
        XCTAssertEqual(result.issues, [])
    }

    func testFollowPolicyRejectsEscapeIntroducedByIntermediateSymbolicLink() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let outside = workspace.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("outside".utf8).write(to: outside.appending(path: "outside.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-intermediate").path,
            withDestinationPath: "../outside"
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-visible-link").path,
            withDestinationPath: "b-intermediate"
        )

        let result = try await hiddenExcludingFollowingScanner().scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), [
            "a-visible-link",
            "b-intermediate",
        ])
        XCTAssertEqual(result.issues.map(\.relativePath), [
            "a-visible-link",
            "b-intermediate",
        ])
        XCTAssertTrue(result.issues.allSatisfy {
            $0.operation == .followSymbolicLink
                && $0.containmentFailureReason == .outside
        })
    }

    func testClassifiesRegularFolderSymbolicLinkAndOtherKinds() async throws {
        let root = try temporaryDirectory()
        let regular = root.appending(path: "regular")
        let link = root.appending(path: "link")
        try Data("abc".utf8).write(to: regular)
        try FileManager.default.createDirectory(
            at: root.appending(path: "folder", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: regular.lastPathComponent
        )
        let socketDescriptor = try createUnixDomainSocket(at: root.appending(path: "socket"))
        defer { Darwin.close(socketDescriptor) }

        let result = try await FolderScanner().scan(at: root)
        let entries = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.relativePath, $0) })

        XCTAssertEqual(entries["regular"]?.kind, .file)
        XCTAssertEqual(entries["regular"]?.size, 3)
        XCTAssertEqual(entries["folder"]?.kind, .folder)
        XCTAssertNil(entries["folder"]?.size)
        XCTAssertEqual(entries["link"]?.kind, .symbolicLink)
        XCTAssertEqual(entries["link"]?.size, Int64(regular.lastPathComponent.utf8.count))
        XCTAssertEqual(entries["socket"]?.kind, .other)
        XCTAssertNil(entries["socket"]?.size)
        XCTAssertEqual(result.issues, [])
    }

    func testDefaultPolicyReportsButDoesNotFollowDirectorySymbolicLink() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let target = workspace.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("sentinel".utf8).write(to: target.appending(path: "outside-sentinel.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: target.path
        )

        let result = try await FolderScanner().scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), ["a-link"])
        XCTAssertFalse(result.entries.contains { $0.relativePath == "a-link/outside-sentinel.txt" })
        XCTAssertEqual(result.issues, [])
    }

    func testFollowPolicyTraversesInRootDirectoryTargetOnce() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: target.lastPathComponent
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), [
            "a-link",
            "a-link/inside.txt",
            "z-target",
        ])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.relativePath, "z-target")
        XCTAssertEqual(result.issues.first?.operation, .preventRepeatedTraversal)
    }

    func testFollowPolicyRejectsOutOfRootTarget() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let outside = workspace.appending(path: "root-escape", directoryHint: .isDirectory)
        XCTAssertTrue(outside.path.hasPrefix(root.path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("outside".utf8).write(to: outside.appending(path: "outside.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "escape"),
            withDestinationURL: outside
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), ["escape"])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.relativePath, "escape")
        XCTAssertEqual(result.issues.first?.operation, .followSymbolicLink)
        XCTAssertEqual(result.issues.first?.containmentFailureReason, .outside)
    }

    func testFollowPolicyAcceptsAbsoluteMultiHopTargetThroughInputRootAlias() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let rootAlias = workspace.appending(path: "root-alias", directoryHint: .isDirectory)
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        try FileManager.default.createSymbolicLink(at: rootAlias, withDestinationURL: root)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-intermediate").path,
            withDestinationPath: rootAlias.appending(path: "z-target").path
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: "b-intermediate"
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: rootAlias)

        XCTAssertTrue(result.entries.contains { $0.relativePath == "a-link/inside.txt" })
        XCTAssertFalse(result.issues.contains {
            $0.relativePath == "a-link"
                && $0.containmentFailureReason == .outside
        })
    }

    func testFollowPolicyAcceptsAbsoluteTargetThroughUnregisteredThirdRootAlias() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let inputAlias = workspace.appending(path: "input-alias", directoryHint: .isDirectory)
        let secondAlias = workspace.appending(path: "second-alias", directoryHint: .isDirectory)
        let thirdAlias = workspace.appending(
            path: "third-alias",
            directoryHint: .isDirectory
        )
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        try FileManager.default.createSymbolicLink(at: inputAlias, withDestinationURL: root)
        try FileManager.default.createSymbolicLink(at: secondAlias, withDestinationURL: root)
        try FileManager.default.createSymbolicLink(
            at: thirdAlias,
            withDestinationURL: secondAlias
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: thirdAlias.appending(path: "z-target").path
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: inputAlias)

        XCTAssertTrue(result.entries.contains { $0.relativePath == "a-link/inside.txt" })
        XCTAssertFalse(result.issues.contains {
            $0.relativePath == "a-link"
                && $0.containmentFailureReason == .outside
        })
    }

    func testFollowPolicyFailsClosedForInjectedPhysicalAncestryTransition() async throws {
        for classification in [
            FolderScanner.PhysicalAncestryTransitionClassification.mountRoot,
            .unproven,
        ] {
            let root = try temporaryDirectory()
            let target = root.appending(path: "z-target", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
            try FileManager.default.createSymbolicLink(
                atPath: root.appending(path: "a-link").path,
                withDestinationPath: target.lastPathComponent
            )
            let transitions = PhysicalAncestryTransitionRecorder()
            let scanner = FolderScanner(options: FolderScanOptions(
                symbolicLinkPolicy: .followDirectoriesWithinRoot,
                errorPolicy: .collectIssues
            ))

            let result = try await FolderScanner.$physicalAncestryTransitionClassifier.withValue({
                transition in
                transitions.record(transition)
                return classification
            }) {
                try await scanner.scan(at: root)
            }

            XCTAssertGreaterThan(transitions.count, 0)
            XCTAssertFalse(result.entries.contains { $0.relativePath == "a-link/inside.txt" })
            XCTAssertTrue(result.issues.contains {
                $0.relativePath == "a-link"
                    && $0.operation == .followSymbolicLink
                    && $0.containmentFailureReason == classification.expectedFailureReason
            })
        }
    }

    func testPhysicalAncestryRejectsGuardedSameDeviceMountOrFirmlinkEscape() throws {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let rootIdentity = try directoryObjectIdentity(at: root)
        let rootFileSystemID = try fileSystemID(at: root)
        let candidates = ["/Users", "/private", "/System/Volumes/Data"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        guard let candidate = try candidates.first(where: {
            let candidateIdentity = try directoryObjectIdentity(at: $0)
            let candidateFileSystemID = try fileSystemID(at: $0)
            return candidateIdentity.device == rootIdentity.device
                && candidateFileSystemID != rootFileSystemID
        }) else {
            throw XCTSkip("Environment exposes no same-device mount or firmlink transition.")
        }

        XCTAssertNotNil(try FolderScanner.directoryIsPhysicallyWithinRootForTesting(
            directoryURL: candidate,
            rootURL: root
        ))
    }

    func testFollowPolicyRejectsAbsoluteAliasChainEndingInSiblingRoot() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let inputAlias = workspace.appending(path: "input-alias", directoryHint: .isDirectory)
        let outside = workspace.appending(path: "sibling", directoryHint: .isDirectory)
        let outsideTarget = outside.appending(path: "target", directoryHint: .isDirectory)
        let escapeAlias = workspace.appending(path: "escape-alias", directoryHint: .isDirectory)
        let thirdAlias = workspace.appending(
            path: "third-alias",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outsideTarget, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outsideTarget.appending(path: "outside.txt"))
        try FileManager.default.createSymbolicLink(at: inputAlias, withDestinationURL: root)
        try FileManager.default.createSymbolicLink(at: escapeAlias, withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: thirdAlias,
            withDestinationURL: escapeAlias
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: thirdAlias.appending(path: "target").path
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: inputAlias)

        XCTAssertFalse(result.entries.contains { $0.relativePath == "a-link/outside.txt" })
        XCTAssertTrue(result.issues.contains {
            $0.relativePath == "a-link"
                && $0.operation == .followSymbolicLink
                && $0.containmentFailureReason == .outside
        })
    }

    func testFollowPolicyAcceptsMixedCaseAbsoluteTargetThroughAliasOnCaseInsensitiveVolume()
        async throws
    {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let rootAlias = workspace.appending(path: "Root-Alias", directoryHint: .isDirectory)
        let mixedCaseAlias = workspace.appending(path: "rOOT-aLIAS", directoryHint: .isDirectory)
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        try FileManager.default.createSymbolicLink(at: rootAlias, withDestinationURL: root)
        let volumeValues = try workspace.resourceValues(forKeys: [
            .volumeSupportsCaseSensitiveNamesKey
        ])
        if volumeValues.volumeSupportsCaseSensitiveNames == true {
            throw XCTSkip("Temporary filesystem resolves names case-sensitively.")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: mixedCaseAlias.path))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: mixedCaseAlias.appending(path: "z-target").path
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: rootAlias)

        XCTAssertTrue(result.entries.contains { $0.relativePath == "a-link/inside.txt" })
        XCTAssertFalse(result.issues.contains {
            $0.relativePath == "a-link"
                && $0.containmentFailureReason == .outside
        })
    }

    func testFollowPolicyRejectsAliasRootSiblingPrefixEscapeInAbsoluteChain() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let rootAlias = workspace.appending(path: "root-alias", directoryHint: .isDirectory)
        let outside = workspace.appending(path: "root-alias-escape", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("outside".utf8).write(to: outside.appending(path: "outside.txt"))
        try FileManager.default.createSymbolicLink(at: rootAlias, withDestinationURL: root)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-intermediate").path,
            withDestinationPath: outside.path
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: "b-intermediate"
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: rootAlias)

        XCTAssertFalse(result.entries.contains { $0.relativePath == "a-link/outside.txt" })
        XCTAssertTrue(result.issues.contains {
            $0.relativePath == "a-link"
                && $0.operation == .followSymbolicLink
                && $0.containmentFailureReason == .outside
        })
    }

    func testFollowPolicyRejectsCanonicalEquivalentAliasRootSiblingEscape() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let outside = workspace.appending(path: "outside", directoryHint: .isDirectory)
        let rootTarget = root.appending(path: "target", directoryHint: .isDirectory)
        let outsideTarget = outside.appending(path: "target", directoryHint: .isDirectory)
        let rootAlias = workspace.appending(path: "caf\u{00E9}", directoryHint: .isDirectory)
        let outsideAlias = workspace.appending(path: "cafe\u{0301}", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootTarget, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideTarget, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: rootTarget.appending(path: "inside.txt"))
        try Data("outside".utf8).write(to: outsideTarget.appending(path: "outside.txt"))
        try FileManager.default.createSymbolicLink(at: rootAlias, withDestinationURL: root)
        do {
            try FileManager.default.createSymbolicLink(at: outsideAlias, withDestinationURL: outside)
        } catch {
            let cocoaError = error as NSError
            if (cocoaError.domain == NSCocoaErrorDomain
                && cocoaError.code == NSFileWriteFileExistsError)
                || (cocoaError.domain == NSPOSIXErrorDomain && cocoaError.code == Int(EEXIST))
            {
                throw XCTSkip("Temporary filesystem canonicalizes equivalent names.")
            }
            throw error
        }
        guard try FileManager.default.destinationOfSymbolicLink(atPath: rootAlias.path) == root.path,
            try FileManager.default.destinationOfSymbolicLink(atPath: outsideAlias.path) == outside.path
        else {
            throw XCTSkip("Temporary filesystem canonicalizes equivalent names.")
        }
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: outsideAlias.appending(path: "target").path
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: rootAlias)

        XCTAssertFalse(result.entries.contains { $0.relativePath == "a-link/inside.txt" })
        XCTAssertFalse(result.entries.contains { $0.relativePath == "a-link/outside.txt" })
        XCTAssertTrue(result.issues.contains {
            $0.relativePath == "a-link"
                && $0.operation == .followSymbolicLink
                && $0.containmentFailureReason == .outside
        })
    }

    func testFollowDirectoryPolicyDoesNotRejectOutOfRootFileTarget() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let outsideFile = workspace.appending(path: "outside.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("outside".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "file-link"),
            withDestinationURL: outsideFile
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), ["file-link"])
        XCTAssertEqual(result.entries.map(\.kind), [.symbolicLink])
        XCTAssertEqual(result.issues, [])
    }

    func testFollowPolicyStopsDirectoryCycleAndReportsIssue() async throws {
        if let rootPath = ProcessInfo.processInfo.environment[Self.cycleChildRootEnvironment] {
            guard let markerPath = ProcessInfo.processInfo.environment[Self.cycleChildMarkerEnvironment]
            else {
                XCTFail("Cycle child marker path was not supplied")
                return
            }
            try Data().write(to: URL(fileURLWithPath: markerPath))
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            let scanner = FolderScanner(options: FolderScanOptions(
                symbolicLinkPolicy: .followDirectoriesWithinRoot,
                errorPolicy: .collectIssues
            ))
            let result = try await scanner.scan(at: root)

            XCTAssertEqual(result.entries.map(\.relativePath), ["directory", "directory/back"])
            XCTAssertEqual(result.issues.count, 1)
            XCTAssertEqual(result.issues.first?.relativePath, "directory/back")
            XCTAssertEqual(result.issues.first?.operation, .preventRepeatedTraversal)
            return
        }

        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "cycle-root", directoryHint: .isDirectory)
        let directory = root.appending(path: "directory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: directory.appending(path: "back").path,
            withDestinationPath: "../"
        )
        let marker = workspace.appending(path: "cycle-child-started")

        try assertTestPassesInBoundedSubprocess(
            "MacMergeCoreTests.FolderScannerTests/testFollowPolicyStopsDirectoryCycleAndReportsIssue",
            environment: [
                Self.cycleChildRootEnvironment: root.path,
                Self.cycleChildMarkerEnvironment: marker.path,
            ]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testFollowPolicyBoundsSymbolicLinkResolutionCycle() async throws {
        if let rootPath = ProcessInfo.processInfo.environment[Self.resolverCycleRootEnvironment] {
            guard let markerPath = ProcessInfo.processInfo.environment[
                Self.resolverCycleChildMarkerEnvironment
            ] else {
                XCTFail("Resolver-cycle child marker path was not supplied")
                return
            }
            try Data().write(to: URL(fileURLWithPath: markerPath))
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            let scanner = FolderScanner(options: FolderScanOptions(
                symbolicLinkPolicy: .followDirectoriesWithinRoot,
                errorPolicy: .collectIssues
            ))
            let result = try await scanner.scan(at: root)

            XCTAssertEqual(result.entries.map(\.relativePath), ["a-link", "b-link"])
            XCTAssertEqual(result.issues.map(\.relativePath), ["a-link", "b-link"])
            XCTAssertTrue(result.issues.allSatisfy {
                $0.operation == .followSymbolicLink
                    && $0.errorDomain == NSPOSIXErrorDomain
                    && $0.errorCode == Int(ELOOP)
            })
            return
        }

        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "resolver-cycle-root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: "b-link"
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-link").path,
            withDestinationPath: "a-link"
        )
        let marker = workspace.appending(path: "resolver-cycle-child-started")
        try assertTestPassesInBoundedSubprocess(
            "MacMergeCoreTests.FolderScannerTests/testFollowPolicyBoundsSymbolicLinkResolutionCycle",
            environment: [
                Self.resolverCycleRootEnvironment: root.path,
                Self.resolverCycleChildMarkerEnvironment: marker.path,
            ]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: marker.path),
            "Selected resolver-cycle child test did not execute"
        )
    }

    func testFollowPolicyRejectsAcyclicChainBeyondSystemHopLimit() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        for index in 0...Int(MAXSYMLINKS) {
            let destination = index == Int(MAXSYMLINKS)
                ? target.lastPathComponent
                : "link-\(index + 1)"
            try FileManager.default.createSymbolicLink(
                atPath: root.appending(path: "link-\(index)").path,
                withDestinationPath: destination
            )
        }
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertFalse(result.entries.contains { $0.relativePath == "link-0/inside.txt" })
        XCTAssertTrue(result.issues.contains {
            $0.relativePath == "link-0"
                && $0.operation == .followSymbolicLink
                && $0.errorDomain == NSPOSIXErrorDomain
                && $0.errorCode == Int(ELOOP)
        })
    }

    func testFollowPolicyAllowsAcyclicChainAtSystemHopLimit() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        for index in 0..<Int(MAXSYMLINKS) {
            let destination = index == Int(MAXSYMLINKS) - 1
                ? target.lastPathComponent
                : "link-\(index + 1)"
            try FileManager.default.createSymbolicLink(
                atPath: root.appending(path: "link-\(index)").path,
                withDestinationPath: destination
            )
        }
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertTrue(result.entries.contains { $0.relativePath == "link-0/inside.txt" })
        XCTAssertFalse(result.issues.contains {
            $0.relativePath == "link-0" && $0.errorCode == Int(ELOOP)
        })
    }

    func testCancellationTakesPrecedenceOverValidationFailure() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FolderScanner().scan(at: URL(string: "https://example.com/not-a-folder")!)
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testCancellationAtEntryAndIssueSortCheckpointsIsPropagated() async throws {
        for checkpoint in [
            FolderScanner.SortCheckpoint.entrySort,
            FolderScanner.SortCheckpoint.issueSort,
        ] {
            let root = try temporaryDirectory()
            try Data().write(to: root.appending(path: "entry.txt"))
            try FileManager.default.createSymbolicLink(
                atPath: root.appending(path: "broken-link").path,
                withDestinationPath: "missing-directory"
            )
            let scanner = FolderScanner(options: FolderScanOptions(
                symbolicLinkPolicy: .followDirectoriesWithinRoot,
                errorPolicy: .collectIssues
            ))

            let task = Task {
                try await FolderScanner.$sortCheckpointObserver.withValue({ observed in
                    guard observed == checkpoint else { return }
                    withUnsafeCurrentTask { $0?.cancel() }
                }) {
                    try await scanner.scan(at: root)
                }
            }

            do {
                _ = try await task.value
                XCTFail("Expected cancellation at \(checkpoint)")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error at \(checkpoint): \(error)")
            }
        }
    }

    func testFileURLAuthorityAllowsOnlyLocalForms() async throws {
        let root = try temporaryDirectory()
        try Data().write(to: root.appending(path: "entry.txt"))
        let localURLs = [
            URL(string: "file:\(root.path)")!,
            root,
            URL(string: "file://localhost\(root.path)")!,
            URL(string: "file://LOCALHOST\(root.path)")!,
        ]

        for localURL in localURLs {
            let result = try await FolderScanner().scan(at: localURL)
            XCTAssertEqual(result.entries.map(\.relativePath), ["entry.txt"])
        }

        let rejectedURLs = [
            URL(string: "file://example.com\(root.path)")!,
            URL(string: "file://user@localhost\(root.path)")!,
            URL(string: "file://localhost:9\(root.path)")!,
        ]
        for rejectedURL in rejectedURLs {
            do {
                _ = try await FolderScanner().scan(at: rejectedURL)
                XCTFail("Expected nonlocal authority rejection for \(rejectedURL)")
            } catch FolderScanError.nonFileURL(let value) {
                XCTAssertEqual(value, rejectedURL.absoluteString)
            } catch {
                XCTFail("Unexpected error for \(rejectedURL): \(error)")
            }
        }
    }

    func testCancellationBeforeExtraSymlinkTargetComponentClosesOwnedDescriptors() async throws {
        let root = try temporaryDirectory()
        try requireSymbolicLinkSupport(at: root)
        let target = root.appending(
            path: "z-parent/z-child/z-target",
            directoryHint: .isDirectory
        )
        let extra = target.appending(path: "z-extra", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: "z-parent/z-child/z-target/z-extra"
        )
        let targetIdentity = try directoryObjectIdentity(at: target)
        let extraIdentity = try directoryObjectIdentity(at: extra)
        let cancellationPoint = DirectoryDescriptorCancellationPoint(
            identity: targetIdentity,
            occurrence: 1
        )
        let events = DirectoryDescriptorOwnershipRecorder()
        let scanner = FolderScanner(
            options: FolderScanOptions(symbolicLinkPolicy: .followDirectoriesWithinRoot),
            directoryDescriptorOwnershipObserver: { event in
                if events.record(event, cancellationPoint: cancellationPoint) {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        )

        do {
            _ = try await scanner.scan(at: root)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let recorded = events.snapshot()
        XCTAssertEqual(recorded.cancellationAcquisitionCount, recorded.acquired.count)
        XCTAssertEqual(recorded.acquired.filter { $0.identity == targetIdentity }.count, 1)
        XCTAssertEqual(recorded.acquired.filter { $0.identity == extraIdentity }.count, 0)
        assertAllOwnedDirectoryDescriptorsReleased(events)
    }

    func testCancellationAfterRootRelativeParentReopenClosesOwnedDescriptors() async throws {
        let root = try temporaryDirectory()
        try requireSymbolicLinkSupport(at: root)
        let parent = root.appending(path: "z-parent", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: parent.appending(path: "z-child", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: parent.appending(path: "z-target", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: "z-parent/z-child/../z-target"
        )
        let parentIdentity = try directoryObjectIdentity(at: parent)
        let targetIdentity = try directoryObjectIdentity(
            at: parent.appending(path: "z-target", directoryHint: .isDirectory)
        )
        let cancellationPoint = DirectoryDescriptorCancellationPoint(
            identity: parentIdentity,
            occurrence: 2
        )
        let events = DirectoryDescriptorOwnershipRecorder()
        let scanner = FolderScanner(
            options: FolderScanOptions(symbolicLinkPolicy: .followDirectoriesWithinRoot),
            directoryDescriptorOwnershipObserver: { event in
                if events.record(event, cancellationPoint: cancellationPoint) {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        )

        do {
            _ = try await scanner.scan(at: root)
            XCTFail("Expected cancellation after reopening the parent directory")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let recorded = events.snapshot()
        XCTAssertEqual(recorded.cancellationAcquisitionCount, recorded.acquired.count)
        XCTAssertEqual(recorded.acquired.filter { $0.identity == parentIdentity }.count, 2)
        XCTAssertEqual(recorded.acquired.filter { $0.identity == targetIdentity }.count, 0)
        assertAllOwnedDirectoryDescriptorsReleased(events)
    }

    func testCancellationAtAbsoluteResolverOpenObservesAndClosesPostOpenDescriptor() async throws {
        let root = try temporaryDirectory()
        try requireSymbolicLinkSupport(at: root)
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let extra = target.appending(path: "z-extra", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: extra.path
        )
        let targetIdentity = try directoryObjectIdentity(at: target)
        let extraIdentity = try directoryObjectIdentity(at: extra)
        let resolverBaseIdentity = try directoryObjectIdentity(
            at: URL(fileURLWithPath: "/", isDirectory: true)
        )
        let events = DirectoryDescriptorOwnershipRecorder()
        let syscalls = DirectoryDescriptorSyscallRecorder()
        let scanner = FolderScanner(
            options: FolderScanOptions(symbolicLinkPolicy: .followDirectoriesWithinRoot),
            directoryDescriptorOwnershipObserver: { event in events.record(event) }
        )

        do {
            _ = try await FolderScanner.$directoryDescriptorSyscallObserver.withValue({ syscall in
                syscalls.record(syscall)
                guard syscall == .openSymbolicLinkResolverInitial else { return }
                withUnsafeCurrentTask { $0?.cancel() }
            }) {
                try await scanner.scan(at: root)
            }
            XCTFail("Expected cancellation at the absolute resolver open")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let recorded = events.snapshot()
        XCTAssertEqual(
            syscalls.snapshot().filter { $0 == .openSymbolicLinkResolverInitial }.count,
            1
        )
        XCTAssertTrue(syscalls.snapshot().contains(.openSymbolicLinkResolverInitial))
        XCTAssertEqual(
            recorded.acquired.filter { $0.identity == resolverBaseIdentity }.count,
            1,
            "Cancellation must occur after the resolver descriptor is opened and observed"
        )
        XCTAssertEqual(recorded.acquired.filter { $0.identity == targetIdentity }.count, 0)
        XCTAssertEqual(recorded.acquired.filter { $0.identity == extraIdentity }.count, 0)
        assertAllOwnedDirectoryDescriptorsReleased(events)
    }

    func testCancellationAtAbsoluteIntermediateResolverReopenClosesOwnedDescriptors() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let intermediate = root.appending(path: "z-absolute-link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: intermediate, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "a-link").path,
            withDestinationPath: intermediate.lastPathComponent
        )
        let events = DirectoryDescriptorOwnershipRecorder()
        let syscalls = DirectoryDescriptorSyscallRecorder()
        let scanner = FolderScanner(
            options: FolderScanOptions(symbolicLinkPolicy: .followDirectoriesWithinRoot),
            directoryDescriptorOwnershipObserver: { event in events.record(event) }
        )

        do {
            _ = try await FolderScanner.$directoryDescriptorSyscallObserver.withValue({ syscall in
                syscalls.record(syscall)
                guard syscall == .openSymbolicLinkResolverReopen else { return }
                withUnsafeCurrentTask { $0?.cancel() }
            }) {
                try await scanner.scan(at: root)
            }
            XCTFail("Expected cancellation at the absolute intermediate resolver reopen")
        } catch is CancellationError {
        }

        XCTAssertEqual(
            syscalls.snapshot().filter { $0 == .openSymbolicLinkResolverReopen }.count,
            1
        )
        assertAllOwnedDirectoryDescriptorsReleased(events)
    }

    func testCollectIssuesReturnsReadableEntriesAndBrokenLinkIssue() async throws {
        let root = try temporaryDirectory()
        try Data("good".utf8).write(to: root.appending(path: "a-good.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-broken").path,
            withDestinationPath: "missing-directory"
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), ["a-good.txt", "b-broken"])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.relativePath, "b-broken")
        XCTAssertEqual(result.issues.first?.operation, .followSymbolicLink)
    }

    func testUnreadableStableSymlinkPayloadPreservesOriginEntry() async throws {
        let root = try temporaryDirectory()
        let link = root.appending(path: "unreadable-link")
        try createMalformedUTF8SymbolicLink(at: link)
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), ["unreadable-link"])
        XCTAssertEqual(result.entries.map(\.kind), [.symbolicLink])
        XCTAssertEqual(result.issues.map(\.relativePath), ["unreadable-link"])
        XCTAssertEqual(result.issues.map(\.operation), [.followSymbolicLink])
        XCTAssertEqual(result.issues.map(\.errorCode), [Int(EILSEQ)])
    }

    func testFailClosedThrowsForBrokenLinkInsteadOfReturningPartialResult() async throws {
        let root = try temporaryDirectory()
        try Data("good".utf8).write(to: root.appending(path: "a-good.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "b-broken").path,
            withDestinationPath: "missing-directory"
        )
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .failClosed
        ))

        do {
            _ = try await scanner.scan(at: root)
            XCTFail("Expected fail-closed scan error")
        } catch FolderScanError.fileSystem(let issue) {
            XCTAssertEqual(issue.relativePath, "b-broken")
            XCTAssertEqual(issue.operation, .followSymbolicLink)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSymlinkRetargetBetweenOpenAndVerificationNeverPublishesOutOfRootEntries() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let safe = root.appending(path: "z-safe", directoryHint: .isDirectory)
        let outside = workspace.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: safe, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("safe".utf8).write(to: safe.appending(path: "safe-only.txt"))
        try Data("outside".utf8).write(to: outside.appending(path: "outside-only.txt"))
        let link = root.appending(path: "00-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: safe)
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))
        let replacement = workspace.appending(path: "replacement-link")
        let retarget = SymlinkRetargetRecorder()

        let result = try await FolderScanner.$symbolicLinkFollowObserver.withValue({ checkpoint in
            guard checkpoint == .targetDirectoryOpenedBeforeVerification else { return }
            do {
                try replaceSymbolicLinkAtomically(
                    at: link,
                    withDestinationURL: outside,
                    replacement: replacement
                )
                retarget.recordSuccess()
            } catch {
                retarget.recordFailure(error)
            }
        }) {
            try await scanner.scan(at: root)
        }

        let retargetResult = retarget.snapshot()
        XCTAssertEqual(retargetResult.successCount, 1)
        XCTAssertNil(retargetResult.failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertFalse(result.entries.contains { $0.relativePath == "00-link/outside-only.txt" })
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.relativePath, "00-link")
        XCTAssertEqual(result.issues.first?.operation, .followSymbolicLink)
    }

    func testSamePayloadSymlinkReplacementDuringPayloadReadRollsBackLinkAndDescendants()
        async throws
    {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let link = root.appending(path: "00-link")
        let replacement = root.appending(path: "replacement-link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let mutation = SymlinkRetargetRecorder()

        let result = try await FolderScanner.$symbolicLinkFollowObserver.withValue({ checkpoint in
            guard checkpoint == .linkPayloadReadBeforeFinalStatusVerification,
                mutation.snapshot().successCount == 0
            else { return }
            do {
                try replaceSymbolicLinkAtomically(
                    at: link,
                    withDestinationURL: target,
                    replacement: replacement
                )
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await FolderScanner(options: FolderScanOptions(
                symbolicLinkPolicy: .followDirectoriesWithinRoot,
                errorPolicy: .collectIssues
            )).scan(at: root)
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath == "00-link" })
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertEqual(result.issues.map(\.relativePath), ["00-link"])
        XCTAssertEqual(result.issues.map(\.operation), [.followSymbolicLink])
    }

    func testSamePayloadSymlinkReplacementDuringFinalVerificationRollsBackDescendants()
        async throws
    {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let link = root.appending(path: "00-link")
        let replacement = root.appending(path: "replacement-link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.lastPathComponent
        )
        let mutation = SymlinkRetargetRecorder()

        let result = try await FolderScanner.$symbolicLinkFollowObserver.withValue({ checkpoint in
            guard checkpoint == .finalTargetDirectoryResolvedBeforeLinkReverification,
                mutation.snapshot().successCount == 0
            else { return }
            do {
                try? FileManager.default.removeItem(at: replacement)
                try FileManager.default.createSymbolicLink(
                    atPath: replacement.path,
                    withDestinationPath: target.lastPathComponent
                )
                try replaceItemAtomically(at: link, with: replacement)
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await FolderScanner(options: FolderScanOptions(
                symbolicLinkPolicy: .followDirectoriesWithinRoot,
                errorPolicy: .collectIssues
            )).scan(at: root)
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath == "00-link" })
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertEqual(result.issues.map(\.relativePath), ["00-link"])
        XCTAssertEqual(result.issues.map(\.operation), [.followSymbolicLink])
    }

    func testMovedOpenedTargetDirectoryNeverPublishesOutOfRootEntries() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let movedTarget = workspace.appending(path: "moved-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: target.appending(path: "outside-only.txt"))
        let link = root.appending(path: "00-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))
        let mutation = SymlinkRetargetRecorder()

        let result = try await FolderScanner.$symbolicLinkFollowObserver.withValue({ checkpoint in
            guard checkpoint == .targetDirectoryOpenedBeforeVerification else { return }
            do {
                try FileManager.default.moveItem(at: target, to: movedTarget)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await scanner.scan(at: root)
        }

        let mutationResult = mutation.snapshot()
        XCTAssertEqual(mutationResult.successCount, 1)
        XCTAssertNil(mutationResult.failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertFalse(result.entries.contains { $0.relativePath == "00-link/outside-only.txt" })
        XCTAssertTrue(result.issues.contains {
            $0.relativePath == "00-link"
                && $0.operation == .followSymbolicLink
                && $0.containmentFailureReason == .outside
        })
    }

    func testMovedTargetDuringTraversalNeverPublishesOutOfRootEntries() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let movedTarget = workspace.appending(path: "moved-target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: target.appending(path: "outside-only.txt"))
        let link = root.appending(path: "00-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))
        let mutation = SymlinkRetargetRecorder()

        let result = try await FolderScanner.$symbolicLinkFollowObserver.withValue({ checkpoint in
            guard checkpoint == .targetDirectoryVerifiedWithinRootBeforeTraversal else { return }
            do {
                try FileManager.default.moveItem(at: target, to: movedTarget)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await scanner.scan(at: root)
        }

        let mutationResult = mutation.snapshot()
        XCTAssertEqual(mutationResult.successCount, 1)
        XCTAssertNil(mutationResult.failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertFalse(result.entries.contains { $0.relativePath == "00-link/outside-only.txt" })
        XCTAssertTrue(result.issues.contains {
            $0.relativePath == "00-link"
                && $0.operation == .followSymbolicLink
        })
    }

    func testTargetBecomingUFHiddenAfterFinalContainmentRollsBackDescendants() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let link = root.appending(path: "00-link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        try setUFHiddenFlagSupportProbe(in: root)
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.lastPathComponent
        )
        let mutation = SymlinkRetargetRecorder()

        let result = try await FolderScanner.$symbolicLinkFollowObserver.withValue({ checkpoint in
            guard checkpoint == .finalTargetDirectoryContainedBeforeMetadataRefresh else { return }
            do {
                guard try setUFHiddenFlag(at: target) else {
                    mutation.recordFailure(NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(ENOTSUP)
                    ))
                    return
                }
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await hiddenExcludingFollowingScanner().scan(at: root)
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertEqual(result.entries.map(\.relativePath), ["00-link"])
        XCTAssertEqual(result.issues, [])
    }

    func testOrdinaryDirectoryHiddenAfterFinalContainmentRollsBackEntryAndDescendants()
        async throws
    {
        let root = try temporaryDirectory()
        let child = root.appending(path: "child", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: child.appending(path: "inside.txt"))
        try setUFHiddenFlagSupportProbe(in: root)
        let mutation = SymlinkRetargetRecorder()

        let result = try await FolderScanner.$ordinaryDirectoryObserver.withValue({ checkpoint in
            guard checkpoint == .finalContainmentVerifiedBeforeMetadataRevalidation else { return }
            do {
                guard try setUFHiddenFlag(at: child) else {
                    mutation.recordFailure(NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(ENOTSUP)
                    ))
                    return
                }
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await FolderScanner(options: FolderScanOptions(
                hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets,
                errorPolicy: .collectIssues
            )).scan(at: root)
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertEqual(result.entries, [])
        XCTAssertEqual(result.issues, [])
    }

    func testHiddenPolicyRollsBackLinkWhenInitialVerificationSeesHiddenReplacement()
        async throws
    {
        let root = try temporaryDirectory()
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let link = root.appending(path: "00-link")
        let probe = root.appending(path: "hidden-flag-probe")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: probe, withDestinationURL: target)
        try setUFHiddenFlagIfSupported(at: probe)
        try FileManager.default.removeItem(at: probe)
        let mutation = SymlinkRetargetRecorder()

        let result = try await FolderScanner.$symbolicLinkFollowObserver.withValue({ checkpoint in
            guard checkpoint == .targetPayloadReadBeforeVerification else { return }
            do {
                guard try setUFHiddenFlag(at: link) else {
                    mutation.recordFailure(NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(ENOTSUP)
                    ))
                    return
                }
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await hiddenExcludingFollowingScanner().scan(at: root)
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath == "00-link" })
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.issues.contains {
            $0.relativePath == "00-link"
                && $0.operation == .followSymbolicLink
        })
    }

    func testFinalSymlinkRetargetRollsBackPreviouslyTraversedDescendants() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let safe = root.appending(path: "z-safe", directoryHint: .isDirectory)
        let outside = workspace.appending(path: "outside", directoryHint: .isDirectory)
        let link = root.appending(path: "00-link")
        let replacement = workspace.appending(path: "replacement-link")
        try FileManager.default.createDirectory(at: safe, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("safe".utf8).write(to: safe.appending(path: "safe-only.txt"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: safe)
        let mutation = SymlinkRetargetRecorder()
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))

        let result = try await FolderScanner.$symbolicLinkFollowObserver.withValue({ checkpoint in
            guard checkpoint == .finalTargetDirectoryResolvedBeforeLinkReverification else { return }
            do {
                try replaceSymbolicLinkAtomically(
                    at: link,
                    withDestinationURL: outside,
                    replacement: replacement
                )
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await scanner.scan(at: root)
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath == "00-link" })
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertTrue(result.issues.contains {
            $0.relativePath == "00-link" && $0.operation == .followSymbolicLink
        })
    }

    func testContainmentRenameBeforeFinalAncestryValidationReportsTypedRace() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let moved = workspace.appending(path: "moved", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: target.appending(path: "inside.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "00-link").path,
            withDestinationPath: target.lastPathComponent
        )
        let mutation = SymlinkRetargetRecorder()

        let result = try await FolderScanner.$physicalAncestryObserver.withValue({ checkpoint in
            guard checkpoint == .reachedRootBeforeFinalRevalidation,
                mutation.snapshot().successCount == 0
            else { return }
            do {
                try FileManager.default.moveItem(at: target, to: moved)
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await FolderScanner(options: FolderScanOptions(
                symbolicLinkPolicy: .followDirectoriesWithinRoot,
                errorPolicy: .collectIssues
            )).scan(at: root)
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertTrue(result.issues.contains {
            $0.relativePath == "00-link"
                && $0.operation == .followSymbolicLink
                && $0.containmentFailureReason == .race
        })
    }

    func testContainmentRenameBetweenFullRevalidationPassesRejectsStaleChain() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let parent = root.appending(path: "parent", directoryHint: .isDirectory)
        let target = parent.appending(path: "target", directoryHint: .isDirectory)
        let movedParent = workspace.appending(path: "moved-parent", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let mutation = SymlinkRetargetRecorder()

        let failureReason = try FolderScanner.$physicalAncestryObserver.withValue({ checkpoint in
            guard checkpoint == .completedFinalRevalidationPass(1) else { return }
            do {
                try FileManager.default.moveItem(at: parent, to: movedParent)
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try FolderScanner.directoryIsPhysicallyWithinRootForTesting(
                directoryURL: target,
                rootURL: root
            )
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertEqual(failureReason, .race)
    }

    func testContainmentDescriptorsAreObservedAndReleasedOnCancellation() async throws {
        let root = try temporaryDirectory()
        let target = root.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let events = DirectoryDescriptorOwnershipRecorder()
        let syscalls = DirectoryDescriptorSyscallRecorder()
        let scanner = FolderScanner(
            options: FolderScanOptions(errorPolicy: .collectIssues),
            directoryDescriptorOwnershipObserver: { event in
                events.record(event)
            }
        )
        let task = Task {
            try await FolderScanner.$directoryDescriptorSyscallObserver.withValue({ syscall in
                syscalls.record(syscall)
            }) {
                try await FolderScanner.$physicalAncestryObserver.withValue({ checkpoint in
                    guard checkpoint == .reachedRootBeforeFinalRevalidation else { return }
                    withUnsafeCurrentTask { $0?.cancel() }
                }) {
                    try await scanner.scan(at: root)
                }
            }
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation during final ancestry validation")
        } catch is CancellationError {
        }
        XCTAssertEqual(
            syscalls.snapshot().filter { $0 == .duplicatePhysicalAncestry }.count,
            1
        )
        XCTAssertEqual(
            syscalls.snapshot().filter { $0 == .openPhysicalAncestryParent }.count,
            1
        )
        assertAllOwnedDirectoryDescriptorsReleased(events)
        XCTAssertEqual(events.snapshot().acquired.count, 5)
    }

    func testCancellationDuringEachFinalAncestryRevalidationPassPropagates() async throws {
        for checkpoint in [
            FolderScanner.PhysicalAncestryCheckpoint.reachedRootBeforeFinalRevalidation,
            .completedFinalRevalidationPass(1),
        ] {
            let root = try temporaryDirectory()
            let target = root.appending(path: "target", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let task = Task {
                try FolderScanner.$physicalAncestryObserver.withValue({ observed in
                    guard observed == checkpoint else { return }
                    withUnsafeCurrentTask { $0?.cancel() }
                }) {
                    try FolderScanner.directoryIsPhysicallyWithinRootForTesting(
                        directoryURL: target,
                        rootURL: root
                    )
                }
            }

            do {
                _ = try await task.value
                XCTFail("Expected cancellation after \(checkpoint)")
            } catch is CancellationError {
            } catch {
                XCTFail("Expected CancellationError after \(checkpoint), got \(error)")
            }
        }
    }

    func testEntryLimitReturnsDeterministicUTF8PrefixAndTypedIssue() async throws {
        let root = try temporaryDirectory()
        for name in ["z.txt", "a.txt", "m.txt"] {
            try Data(name.utf8).write(to: root.appending(path: name))
        }
        let scanner = FolderScanner(options: FolderScanOptions(
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumEntries: 2)
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), ["a.txt", "m.txt"])
        XCTAssertEqual(result.issues.map(\.relativePath), [""])
        XCTAssertEqual(result.issues.map(\.limit), [.entries])
        XCTAssertEqual(result.issues.map(\.operation), [.enforceLimit])
    }

    func testPendingNameBudgetBoundsNamesAcrossRecursiveListings() async throws {
        let root = try temporaryDirectory()
        let child = root.appending(path: "a", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        try Data().write(to: child.appending(path: "a.txt"))
        try Data().write(to: child.appending(path: "b.txt"))
        try Data().write(to: root.appending(path: "z.txt"))
        let exact = try await FolderScanner(options: FolderScanOptions(
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumPendingEntryNames: 3)
        )).scan(at: root)
        let bounded = try await FolderScanner(options: FolderScanOptions(
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumPendingEntryNames: 2)
        )).scan(at: root)

        XCTAssertEqual(exact.entries.map(\.relativePath), ["a", "a/a.txt", "a/b.txt", "z.txt"])
        XCTAssertEqual(exact.issues, [])
        XCTAssertEqual(bounded.entries.map(\.relativePath), ["a", "a/a.txt"])
        XCTAssertEqual(bounded.issues.map(\.relativePath), ["a"])
        XCTAssertEqual(bounded.issues.map(\.limit), [.pendingEntryNames])
        XCTAssertEqual(bounded.issues.map(\.operation), [.enforceLimit])
    }

    func testExaminedEntryBudgetStopsHiddenEntryFlood() async throws {
        let root = try temporaryDirectory()
        for name in [".a", ".b", ".c"] {
            try Data().write(to: root.appending(path: name))
        }
        let exact = try await FolderScanner(options: FolderScanOptions(
            hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets,
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumExaminedEntries: 3)
        )).scan(at: root)
        let bounded = try await FolderScanner(options: FolderScanOptions(
            hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets,
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumExaminedEntries: 2)
        )).scan(at: root)

        XCTAssertEqual(exact.entries, [])
        XCTAssertEqual(exact.issues, [])
        XCTAssertEqual(bounded.entries, [])
        XCTAssertEqual(bounded.issues.map(\.relativePath), [""])
        XCTAssertEqual(bounded.issues.map(\.limit), [.examinedEntries])
        XCTAssertEqual(bounded.issues.map(\.operation), [.enforceLimit])
    }

    func testDirectoryDescriptorBudgetStopsDeepTraversalBeforeSystemLimit() async throws {
        let root = try temporaryDirectory()
        let child = root.appending(path: "child", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        try Data().write(to: child.appending(path: "nested.txt"))
        let exact = try await FolderScanner(options: FolderScanOptions(
            limits: FolderScanLimits(maximumOpenDirectoryDescriptors: 4)
        )).scan(at: root)
        let events = DirectoryDescriptorOwnershipRecorder()
        let scanner = FolderScanner(
            options: FolderScanOptions(
                errorPolicy: .collectIssues,
                limits: FolderScanLimits(maximumOpenDirectoryDescriptors: 3)
            ),
            directoryDescriptorOwnershipObserver: { event in events.record(event) }
        )

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(exact.entries.map(\.relativePath), ["child", "child/nested.txt"])
        XCTAssertEqual(exact.issues, [])
        XCTAssertEqual(result.entries.map(\.relativePath), ["child"])
        XCTAssertEqual(result.issues.map(\.relativePath), ["child"])
        XCTAssertEqual(result.issues.map(\.limit), [.openDirectoryDescriptors])
        XCTAssertEqual(result.issues.map(\.operation), [.enforceLimit])
        assertAllOwnedDirectoryDescriptorsReleased(events)
    }

    func testZeroDescriptorBudgetPerformsNoDirectoryDescriptorSyscall() async throws {
        let root = try temporaryDirectory()
        try Data().write(to: root.appending(path: "entry.txt"))
        let ownershipEvents = DirectoryDescriptorOwnershipRecorder()
        let syscalls = DirectoryDescriptorSyscallRecorder()
        let scanner = FolderScanner(
            options: FolderScanOptions(
                errorPolicy: .collectIssues,
                limits: FolderScanLimits(maximumOpenDirectoryDescriptors: 0)
            ),
            directoryDescriptorOwnershipObserver: { event in ownershipEvents.record(event) }
        )

        let result = try await FolderScanner.$directoryDescriptorSyscallObserver.withValue({
            syscall in syscalls.record(syscall)
        }) {
            try await scanner.scan(at: root)
        }

        XCTAssertEqual(result.entries, [])
        XCTAssertEqual(result.issues.map(\.relativePath), [""])
        XCTAssertEqual(result.issues.map(\.limit), [.openDirectoryDescriptors])
        XCTAssertEqual(result.issues.map(\.operation), [.enforceLimit])
        XCTAssertEqual(syscalls.snapshot(), [])
        XCTAssertEqual(ownershipEvents.snapshot().acquired.count, 0)
        assertAllOwnedDirectoryDescriptorsReleased(ownershipEvents)
    }

    func testDescriptorBudgetAcceptsExactCapAndRejectsNextOpenBeforeSyscall() async throws {
        let root = try temporaryDirectory()
        try Data().write(to: root.appending(path: "entry.txt"))

        for maximum in [2, 1] {
            let ownershipEvents = DirectoryDescriptorOwnershipRecorder()
            let syscalls = DirectoryDescriptorSyscallRecorder()
            let scanner = FolderScanner(
                options: FolderScanOptions(
                    errorPolicy: .collectIssues,
                    limits: FolderScanLimits(maximumOpenDirectoryDescriptors: maximum)
                ),
                directoryDescriptorOwnershipObserver: { event in ownershipEvents.record(event) }
            )

            let result = try await FolderScanner.$directoryDescriptorSyscallObserver.withValue({
                syscall in syscalls.record(syscall)
            }) {
                try await scanner.scan(at: root)
            }

            if maximum == 2 {
                XCTAssertEqual(result.entries.map(\.relativePath), ["entry.txt"])
                XCTAssertEqual(result.issues, [])
                XCTAssertEqual(syscalls.snapshot(), [.openRoot, .duplicateDirectoryStream])
            } else {
                XCTAssertEqual(result.entries, [])
                XCTAssertEqual(result.issues.map(\.relativePath), [""])
                XCTAssertEqual(result.issues.map(\.limit), [.openDirectoryDescriptors])
                XCTAssertEqual(result.issues.map(\.operation), [.enforceLimit])
                XCTAssertEqual(syscalls.snapshot(), [.openRoot])
            }
            XCTAssertEqual(ownershipEvents.snapshot().acquired.count, maximum)
            assertAllOwnedDirectoryDescriptorsReleased(ownershipEvents)
        }
    }

    func testFailClosedNewLimitsThrowTypedLimitErrors() async throws {
        let root = try temporaryDirectory()
        try Data().write(to: root.appending(path: "entry.txt"))
        let cases: [(FolderScanLimit, (inout FolderScanLimits) -> Void)] = [
            (.examinedEntries, { $0.maximumExaminedEntries = 0 }),
            (.openDirectoryDescriptors, { $0.maximumOpenDirectoryDescriptors = 0 }),
            (.pendingEntryNames, { $0.maximumPendingEntryNames = 0 }),
        ]

        for (expectedLimit, mutate) in cases {
            var limits = FolderScanLimits()
            mutate(&limits)
            do {
                _ = try await FolderScanner(options: FolderScanOptions(limits: limits)).scan(
                    at: root
                )
                XCTFail("Expected \(expectedLimit) limit failure")
            } catch FolderScanError.limitExceeded(let issue) {
                XCTAssertEqual(issue.relativePath, "")
                XCTAssertEqual(issue.limit, expectedLimit)
                XCTAssertEqual(issue.operation, .enforceLimit)
            } catch {
                XCTFail("Unexpected error for \(expectedLimit): \(error)")
            }
        }
    }

    func testFailClosedEntryLimitThrowsTypedLimitError() async throws {
        let root = try temporaryDirectory()
        try Data().write(to: root.appending(path: "a.txt"))
        let scanner = FolderScanner(options: FolderScanOptions(
            limits: FolderScanLimits(maximumEntries: 0)
        ))

        do {
            _ = try await scanner.scan(at: root)
            XCTFail("Expected entry limit failure")
        } catch FolderScanError.limitExceeded(let issue) {
            XCTAssertEqual(issue.relativePath, "")
            XCTAssertEqual(issue.limit, .entries)
            XCTAssertEqual(issue.operation, .enforceLimit)
        }
    }

    func testTotalAccountedByteLimitAcceptsBoundaryAndStopsBeforeOverflow() async throws {
        let root = try temporaryDirectory()
        try Data("aa".utf8).write(to: root.appending(path: "a.txt"))
        try Data("bb".utf8).write(to: root.appending(path: "b.txt"))

        let exact = try await FolderScanner(options: FolderScanOptions(
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumTotalAccountedBytes: 4)
        )).scan(at: root)
        let bounded = try await FolderScanner(options: FolderScanOptions(
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumTotalAccountedBytes: 3)
        )).scan(at: root)

        XCTAssertEqual(exact.entries.map(\.relativePath), ["a.txt", "b.txt"])
        XCTAssertEqual(exact.issues, [])
        XCTAssertEqual(bounded.entries.map(\.relativePath), ["a.txt"])
        XCTAssertEqual(bounded.issues.map(\.relativePath), ["b.txt"])
        XCTAssertEqual(bounded.issues.map(\.limit), [.totalAccountedBytes])
        XCTAssertEqual(bounded.issues.map(\.operation), [.enforceLimit])
    }

    func testDepthAndUTF8PathLimitsSkipOnlyRejectedEntries() async throws {
        let root = try temporaryDirectory()
        let nested = root.appending(path: "a", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data().write(to: nested.appending(path: "child"))
        try Data().write(to: root.appending(path: "é"))
        let scanner = FolderScanner(options: FolderScanOptions(
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(
                maximumDepth: 1,
                maximumRelativePathUTF8Bytes: 1
            )
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries.map(\.relativePath), ["a"])
        XCTAssertEqual(result.issues.map(\.relativePath), ["a/child", "é"])
        XCTAssertEqual(result.issues.map(\.limit), [.depth, .relativePathUTF8Bytes])
        XCTAssertEqual(result.issues.map(\.operation), [.enforceLimit, .enforceLimit])
    }

    func testHiddenEntriesAreExcludedBeforeDepthAndPathLimitChecks() async throws {
        let root = try temporaryDirectory()
        try Data().write(to: root.appending(path: ".hidden"))
        let flagHidden = root.appending(path: "flag-hidden")
        try Data().write(to: flagHidden)
        guard try setUFHiddenFlag(at: flagHidden) else {
            throw XCTSkip("Temporary filesystem does not support UF_HIDDEN.")
        }
        let scanner = FolderScanner(options: FolderScanOptions(
            hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets,
            errorPolicy: .failClosed,
            limits: FolderScanLimits(
                maximumDepth: 0,
                maximumRelativePathUTF8Bytes: 0
            )
        ))

        let result = try await scanner.scan(at: root)

        XCTAssertEqual(result.entries, [])
        XCTAssertEqual(result.issues, [])
    }

    func testIssueLimitBoundsCollectedFailures() async throws {
        let root = try temporaryDirectory()
        try requireSymbolicLinkSupport(at: root)
        for name in ["a-link", "b-link"] {
            try FileManager.default.createSymbolicLink(
                atPath: root.appending(path: name).path,
                withDestinationPath: "missing"
            )
        }
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumIssues: 1)
        ))

        do {
            _ = try await scanner.scan(at: root)
            XCTFail("Expected issue limit failure")
        } catch FolderScanError.limitExceeded(let issue) {
            XCTAssertEqual(issue.relativePath, "b-link")
            XCTAssertEqual(issue.limit, .issues)
            XCTAssertEqual(issue.operation, .enforceLimit)
        }
    }

    func testMutatedNegativeLimitIsRejectedAtScanBoundary() async throws {
        let root = try temporaryDirectory()
        let cases: [(FolderScanLimit, (inout FolderScanLimits) -> Void)] = [
            (.entries, { $0.maximumEntries = -1 }),
            (.examinedEntries, { $0.maximumExaminedEntries = -1 }),
            (.openDirectoryDescriptors, { $0.maximumOpenDirectoryDescriptors = -1 }),
            (.pendingEntryNames, { $0.maximumPendingEntryNames = -1 }),
        ]

        for (expectedLimit, mutate) in cases {
            var limits = FolderScanLimits()
            mutate(&limits)
            do {
                _ = try await FolderScanner(options: FolderScanOptions(limits: limits)).scan(
                    at: root
                )
                XCTFail("Expected invalid \(expectedLimit) limit rejection")
            } catch FolderScanError.invalidLimit(let limit) {
                XCTAssertEqual(limit, expectedLimit)
            } catch {
                XCTFail("Unexpected error for \(expectedLimit): \(error)")
            }
        }
    }

    func testCollectIssuesContinuesAfterMalformedUTF8DirectoryEntry() async throws {
        let root = try temporaryDirectory()
        try Data("before".utf8).write(to: root.appending(path: "00-before.txt"))
        let invalidName = try createMalformedUTF8File(in: root)
        defer { removeMalformedUTF8File(invalidName, from: root) }
        try Data("after".utf8).write(to: root.appending(path: "zz-after.txt"))
        let scanner = FolderScanner(options: FolderScanOptions(errorPolicy: .collectIssues))

        for _ in 0..<5 {
            let result = try await scanner.scan(at: root)

            XCTAssertEqual(result.entries.map(\.relativePath), ["00-before.txt", "zz-after.txt"])
            XCTAssertEqual(result.issues.map(\.relativePath), [""])
            XCTAssertEqual(result.issues.map(\.operation), [.readMetadata])
            XCTAssertEqual(result.issues.map(\.errorCode), [Int(EILSEQ)])
        }
    }

    func testCollectIssuesDeterministicallyContinuesAfterDirectoryEntryDecodeFailure() async throws {
        let root = try temporaryDirectory()
        for name in ["00-before.txt", "50-malformed.txt", "zz-after.txt"] {
            try Data(name.utf8).write(to: root.appending(path: name))
        }
        let rejectedBytes = Array("50-malformed.txt".utf8)
        let scanner = FolderScanner(options: FolderScanOptions(errorPolicy: .collectIssues))

        for _ in 0..<5 {
            let result = try await FolderScanner.$directoryEntryNameDecoder.withValue({ bytes in
                bytes == rejectedBytes ? nil : String(bytes: bytes, encoding: .utf8)
            }) {
                try await scanner.scan(at: root)
            }

            XCTAssertEqual(result.entries.map(\.relativePath), ["00-before.txt", "zz-after.txt"])
            XCTAssertEqual(result.issues.map(\.relativePath), [""])
            XCTAssertEqual(result.issues.map(\.operation), [.readMetadata])
            XCTAssertEqual(result.issues.map(\.errorCode), [Int(EILSEQ)])
        }
    }

    func testOuterTaskCancellationPropagatesAndReleasesDescriptors() async throws {
        let root = try temporaryDirectory()
        try Data().write(to: root.appending(path: "entry.txt"))
        let gate = DirectoryDescriptorScanGate()
        let events = DirectoryDescriptorOwnershipRecorder()
        let scanner = FolderScanner(
            options: FolderScanOptions(),
            directoryDescriptorOwnershipObserver: { event in
                events.record(event)
                if case .acquired = event { gate.pauseFirstAcquisition() }
            }
        )
        let task = Task { try await scanner.scan(at: root) }
        let didPause = await gate.waitUntilPaused(timeout: .seconds(2))
        XCTAssertTrue(didPause)

        task.cancel()
        gate.resume()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        assertAllOwnedDirectoryDescriptorsReleased(events)
    }

    func testFinalContainmentFailureAfterLimitStopRollsBackDescendantIssues() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let child = root.appending(path: "child", directoryHint: .isDirectory)
        let moved = workspace.appending(path: "moved", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try requireSymbolicLinkSupport(at: root)
        try FileManager.default.createSymbolicLink(
            atPath: child.appending(path: "a-broken").path,
            withDestinationPath: "missing"
        )
        try Data().write(to: child.appending(path: "b.txt"))
        let mutation = SymlinkRetargetRecorder()
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumEntries: 2)
        ))

        let result = try await FolderScanner.$ordinaryDirectoryObserver.withValue({ checkpoint in
            guard checkpoint == .verifiedWithinRootBeforeTraversal,
                mutation.snapshot().successCount == 0 else { return }
            do {
                try FileManager.default.moveItem(at: child, to: moved)
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await scanner.scan(at: root)
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("child/") })
        XCTAssertFalse(result.issues.contains { $0.relativePath.hasPrefix("child/") })
        XCTAssertEqual(result.issues.map(\.relativePath), ["child", "child"])
        XCTAssertEqual(result.issues.map(\.operation), [.enforceLimit, .readDirectory])
        XCTAssertEqual(result.issues.map(\.limit), [.entries, nil])
    }

    func testFinalSymlinkFailureAfterLimitStopRollsBackDescendantIssues() async throws {
        let workspace = try temporaryDirectory()
        let root = workspace.appending(path: "root", directoryHint: .isDirectory)
        let target = root.appending(path: "z-target", directoryHint: .isDirectory)
        let outside = workspace.appending(path: "outside", directoryHint: .isDirectory)
        let link = root.appending(path: "00-link")
        let replacement = workspace.appending(path: "replacement-link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try requireSymbolicLinkSupport(at: root)
        try FileManager.default.createSymbolicLink(
            atPath: target.appending(path: "a-broken").path,
            withDestinationPath: "missing"
        )
        try Data().write(to: target.appending(path: "b.txt"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let mutation = SymlinkRetargetRecorder()
        let scanner = FolderScanner(options: FolderScanOptions(
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues,
            limits: FolderScanLimits(maximumEntries: 2)
        ))

        let result = try await FolderScanner.$symbolicLinkFollowObserver.withValue({ checkpoint in
            guard checkpoint == .finalTargetDirectoryResolvedBeforeLinkReverification else { return }
            do {
                try replaceSymbolicLinkAtomically(
                    at: link,
                    withDestinationURL: outside,
                    replacement: replacement
                )
                mutation.recordSuccess()
            } catch {
                mutation.recordFailure(error)
            }
        }) {
            try await scanner.scan(at: root)
        }

        XCTAssertEqual(mutation.snapshot().successCount, 1)
        XCTAssertNil(mutation.snapshot().failure)
        XCTAssertFalse(result.entries.contains { $0.relativePath == "00-link" })
        XCTAssertFalse(result.entries.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertFalse(result.issues.contains { $0.relativePath.hasPrefix("00-link/") })
        XCTAssertEqual(result.issues.map(\.relativePath), ["00-link", "00-link"])
        XCTAssertEqual(result.issues.map(\.operation), [.enforceLimit, .followSymbolicLink])
        XCTAssertEqual(result.issues.map(\.limit), [.entries, nil])
    }

    private func hiddenExcludingFollowingScanner() -> FolderScanner {
        FolderScanner(options: FolderScanOptions(
            hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets,
            symbolicLinkPolicy: .followDirectoriesWithinRoot,
            errorPolicy: .collectIssues
        ))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "MMFS-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func createUnixDomainSocket(at url: URL) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        let copiedCount = url.path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
                Darwin.strlcpy(destination, source, capacity)
            }
        }
        guard copiedCount < capacity else {
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG))
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    private func createMalformedUTF8File(in directory: URL) throws -> [CChar] {
        let directoryFD = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard directoryFD >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { Darwin.close(directoryFD) }
        let name = [CChar(bitPattern: 0xFF), 0]
        let result = name.withUnsafeBufferPointer { nameBuffer in
            "missing".withCString { target in
                Darwin.symlinkat(target, directoryFD, nameBuffer.baseAddress)
            }
        }
        guard result == 0 else {
            if errno == EILSEQ || errno == ENOTSUP {
                throw XCTSkip("Temporary filesystem does not support malformed UTF-8 names.")
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return name
    }

    private func createMalformedUTF8SymbolicLink(at url: URL) throws {
        let target = [CChar(bitPattern: 0xFF), 0]
        let result = target.withUnsafeBufferPointer { targetBuffer in
            url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else {
                    errno = EINVAL
                    return -1
                }
                return Darwin.symlink(targetBuffer.baseAddress, path)
            }
        }
        guard result == 0 else {
            if errno == EILSEQ || errno == ENOTSUP {
                throw XCTSkip("Temporary filesystem does not support malformed UTF-8 link payloads.")
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func removeMalformedUTF8File(_ name: [CChar], from directory: URL) {
        let directoryFD = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard directoryFD >= 0 else { return }
        defer { Darwin.close(directoryFD) }
        name.withUnsafeBufferPointer { buffer in
            _ = Darwin.unlinkat(directoryFD, buffer.baseAddress, 0)
        }
    }

    private func setUFHiddenFlagIfSupported(at url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.lchflags(path, UInt32(UF_HIDDEN))
        }
        if result != 0, errno == ENOTSUP {
            throw XCTSkip("Temporary filesystem does not support UF_HIDDEN.")
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        var status = stat()
        let statusResult = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.lstat(path, &status)
        }
        guard statusResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard status.st_flags & UInt32(UF_HIDDEN) != 0 else {
            throw XCTSkip("Temporary filesystem did not preserve UF_HIDDEN.")
        }
    }

    private func setUFHiddenFlagSupportProbe(in root: URL) throws {
        let probe = root.appending(path: "hidden-flag-probe", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: probe) }
        try setUFHiddenFlagIfSupported(at: probe)
    }

    private func requireSymbolicLinkSupport(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.volumeSupportsSymbolicLinksKey])
        if values.volumeSupportsSymbolicLinks == false {
            throw XCTSkip("Temporary filesystem does not support symbolic links.")
        }
    }

    private func directoryObjectIdentity(at url: URL) throws -> DirectoryObjectIdentity {
        var status = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.lstat(path, &status)
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return DirectoryObjectIdentity(status)
    }

    private func fileSystemID(at url: URL) throws -> TestFileSystemID {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { Darwin.close(descriptor) }

        var status = statfs()
        guard Darwin.fstatfs(descriptor, &status) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return TestFileSystemID(first: status.f_fsid.val.0, second: status.f_fsid.val.1)
    }

    private func assertAllOwnedDirectoryDescriptorsReleased(
        _ events: DirectoryDescriptorOwnershipRecorder,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorded = events.snapshot()
        let acquiredDescriptors = recorded.acquired.map { $0.descriptor }
        let releasedDescriptors = recorded.released.map { $0.descriptor }
        XCTAssertEqual(recorded.released.count, recorded.acquired.count, file: file, line: line)
        XCTAssertEqual(
            descriptorMultiplicities(releasedDescriptors),
            descriptorMultiplicities(acquiredDescriptors),
            file: file,
            line: line
        )
        XCTAssertTrue(
            recorded.released.allSatisfy { $0.closeResult == 0 },
            file: file,
            line: line
        )
        XCTAssertTrue(recorded.outstandingOwnership.isEmpty, file: file, line: line)
        XCTAssertEqual(recorded.invalidOwnershipEventCount, 0, file: file, line: line)
    }

    private func descriptorMultiplicities(_ descriptors: [Int32]) -> [Int32: Int] {
        descriptors.reduce(into: [:]) { counts, descriptor in
            counts[descriptor, default: 0] += 1
        }
    }

    private func assertTestPassesInBoundedSubprocess(
        _ testName: String,
        environment additions: [String: String],
        timeout: DispatchTimeInterval = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["-XCTest", testName, Bundle(for: Self.self).bundleURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, addition in
            addition
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        defer {
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        guard terminated.wait(timeout: .now() + timeout) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            guard terminated.wait(timeout: .now() + .seconds(2)) == .success else {
                XCTFail("Child test could not be terminated after timeout", file: file, line: line)
                return
            }
            process.waitUntilExit()
            XCTFail("Child test exceeded bounded timeout", file: file, line: line)
            return
        }
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit, file: file, line: line)
        XCTAssertEqual(process.terminationStatus, 0, file: file, line: line)
    }

    private static let cycleChildRootEnvironment = "MACMERGE_FOLDER_SCANNER_CYCLE_ROOT"
    private static let cycleChildMarkerEnvironment = "MACMERGE_FOLDER_SCANNER_CYCLE_MARKER"
    private static let resolverCycleRootEnvironment = "MACMERGE_FOLDER_SCANNER_RESOLVER_CYCLE_ROOT"
    private static let resolverCycleChildMarkerEnvironment =
        "MACMERGE_FOLDER_SCANNER_RESOLVER_CYCLE_MARKER"
}

private struct DirectoryObjectIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let generation: UInt32

    init(_ status: stat) {
        device = UInt64(bitPattern: Int64(status.st_dev))
        inode = UInt64(status.st_ino)
        generation = status.st_gen
    }
}

private struct TestFileSystemID: Equatable {
    let first: Int32
    let second: Int32
}

private extension FolderScanner.PhysicalAncestryTransitionClassification {
    var expectedFailureReason: FolderScanContainmentFailureReason {
        switch self {
        case .mountRoot:
            .outside
        case .automatic, .continuous, .unproven:
            .indeterminate
        }
    }
}

private final class PhysicalAncestryTransitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var transitionCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return transitionCount
    }

    func record(_: FolderScanner.PhysicalAncestryTransition) {
        lock.lock()
        transitionCount += 1
        lock.unlock()
    }
}

private struct DirectoryDescriptorCancellationPoint: Sendable {
    let identity: DirectoryObjectIdentity
    let occurrence: Int
}

private final class DirectoryDescriptorSyscallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var syscalls: [FolderScanner.DirectoryDescriptorSyscall] = []

    func record(_ syscall: FolderScanner.DirectoryDescriptorSyscall) {
        lock.lock()
        syscalls.append(syscall)
        lock.unlock()
    }

    func snapshot() -> [FolderScanner.DirectoryDescriptorSyscall] {
        lock.lock()
        defer { lock.unlock() }
        return syscalls
    }
}

private final class DirectoryDescriptorOwnershipRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var acquired: [(descriptor: Int32, identity: DirectoryObjectIdentity?)] = []
    private var released: [(descriptor: Int32, closeResult: Int32)] = []
    private var outstandingOwnership: [Int32: Int] = [:]
    private var invalidOwnershipEventCount = 0
    private var cancellationAcquisitionCount: Int?

    @discardableResult
    func record(
        _ event: FolderScanner.DirectoryDescriptorOwnershipEvent,
        cancellationPoint: DirectoryDescriptorCancellationPoint? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var shouldCancel = false
        switch event {
        case .acquired(let descriptor):
            var status = stat()
            let identity = Darwin.fstat(descriptor, &status) == 0
                ? DirectoryObjectIdentity(status)
                : nil
            acquired.append((descriptor, identity))
            if outstandingOwnership[descriptor] != nil {
                invalidOwnershipEventCount += 1
            }
            outstandingOwnership[descriptor, default: 0] += 1
            if cancellationAcquisitionCount == nil,
                let cancellationPoint,
                identity == cancellationPoint.identity,
                acquired.filter({ $0.identity == cancellationPoint.identity }).count
                    == cancellationPoint.occurrence
            {
                cancellationAcquisitionCount = acquired.count
                shouldCancel = true
            }
        case .released(let descriptor, let closeResult):
            released.append((descriptor, closeResult))
            guard let ownershipCount = outstandingOwnership[descriptor], ownershipCount > 0 else {
                invalidOwnershipEventCount += 1
                return false
            }
            if ownershipCount == 1 {
                outstandingOwnership.removeValue(forKey: descriptor)
            } else {
                outstandingOwnership[descriptor] = ownershipCount - 1
            }
        }
        return shouldCancel
    }

    func snapshot() -> (
        acquired: [(descriptor: Int32, identity: DirectoryObjectIdentity?)],
        released: [(descriptor: Int32, closeResult: Int32)],
        outstandingOwnership: [Int32: Int],
        invalidOwnershipEventCount: Int,
        cancellationAcquisitionCount: Int?
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (
            acquired,
            released,
            outstandingOwnership,
            invalidOwnershipEventCount,
            cancellationAcquisitionCount
        )
    }
}

private final class SymlinkRetargetRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var successCount = 0
    private var failure: String?

    func recordSuccess() {
        lock.lock()
        successCount += 1
        lock.unlock()
    }

    func recordFailure(_ error: any Error) {
        lock.lock()
        failure = String(describing: error)
        lock.unlock()
    }

    func snapshot() -> (successCount: Int, failure: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (successCount, failure)
    }
}

private final class DirectoryDescriptorScanGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var paused = false
    private var didPause = false
    private let resumeSemaphore = DispatchSemaphore(value: 0)

    func pauseFirstAcquisition() {
        lock.lock()
        guard !didPause else {
            lock.unlock()
            return
        }
        didPause = true
        paused = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: true)
        resumeSemaphore.wait()
    }

    func waitUntilPaused(timeout: DispatchTimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if paused {
                lock.unlock()
                continuation.resume(returning: true)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                lock.lock()
                guard let pending = self.continuation else {
                    lock.unlock()
                    return
                }
                self.continuation = nil
                lock.unlock()
                pending.resume(returning: false)
            }
        }
    }

    func resume() {
        resumeSemaphore.signal()
    }
}

private func replaceSymbolicLinkAtomically(
    at link: URL,
    withDestinationURL destination: URL,
    replacement: URL
) throws {
    try? FileManager.default.removeItem(at: replacement)
    try FileManager.default.createSymbolicLink(at: replacement, withDestinationURL: destination)
    try replaceItemAtomically(at: link, with: replacement)
}

private func replaceItemAtomically(at link: URL, with replacement: URL) throws {
    let result: Int32 = replacement.withUnsafeFileSystemRepresentation { replacementPath in
        link.withUnsafeFileSystemRepresentation { linkPath in
            guard let replacementPath, let linkPath else {
                errno = EINVAL
                return Int32(-1)
            }
            return Darwin.rename(replacementPath, linkPath)
        }
    }
    guard result == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

private func setUFHiddenFlag(at url: URL) throws -> Bool {
    let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else {
            errno = EINVAL
            return -1
        }
        return Darwin.lchflags(path, UInt32(UF_HIDDEN))
    }
    if result != 0, errno == ENOTSUP { return false }
    guard result == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var status = stat()
    let statusResult = url.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else {
            errno = EINVAL
            return -1
        }
        return Darwin.lstat(path, &status)
    }
    guard statusResult == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return status.st_flags & UInt32(UF_HIDDEN) != 0
}
