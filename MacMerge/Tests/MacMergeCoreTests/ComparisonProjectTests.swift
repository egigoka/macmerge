import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class ComparisonProjectTests: XCTestCase {
    func testTwoAndThreeSideInitializersExposeVersionedSchema() throws {
        let left = URL(filePath: "/inputs/left.txt")
        let middle = URL(filePath: "/inputs/middle.txt")
        let right = URL(filePath: "/inputs/right.txt")

        let twoSide = try ComparisonProject(
            left: left,
            right: right,
            leftReadOnly: true,
            mode: .text,
            recursive: true,
            filter: .named("Source")
        )

        XCTAssertEqual(twoSide.schemaVersion, ComparisonProject.currentSchemaVersion)
        XCTAssertEqual(twoSide.sides.map(\.identity), [.left, .right])
        XCTAssertEqual(twoSide.side(.left)?.path, left)
        XCTAssertEqual(twoSide.side(.left)?.readOnly, true)
        XCTAssertEqual(twoSide.side(.right)?.path, right)
        XCTAssertFalse(twoSide.isThreeWay)
        XCTAssertEqual(twoSide.mode, .text)
        XCTAssertTrue(twoSide.recursive)
        XCTAssertEqual(twoSide.filter, .named("Source"))

        let threeSide = try ComparisonProject(
            left: left,
            middle: middle,
            right: right,
            middleReadOnly: true,
            mode: .folder
        )

        XCTAssertEqual(threeSide.sides.map(\.identity), [.left, .middle, .right])
        XCTAssertEqual(threeSide.side(.middle)?.path, middle)
        XCTAssertEqual(threeSide.side(.middle)?.readOnly, true)
        XCTAssertTrue(threeSide.isThreeWay)
    }

    func testEncodedJSONIsDeterministicSortedAndNewlineTerminated() throws {
        let projectFileURL = URL(filePath: "/projects/comparison.macmerge")
        let project = try ComparisonProject(
            mode: .binary,
            sides: [
                try .init(identity: .right, path: URL(filePath: "/inputs/right.bin"), readOnly: true),
                try .init(identity: .left, path: URL(filePath: "/inputs/left.bin"))
            ],
            recursive: true,
            filter: .file(URL(filePath: "/filters/binary.filter")),
            lineDiffOptions: LineDiffOptions(ignoreCase: true, detectMovedBlocks: true)
        )

        let first = try project.encodedData(relativeTo: projectFileURL)
        let second = try project.encodedData(relativeTo: projectFileURL)
        let expectedJSON = """
            {
              "filter" : {
                "kind" : "file",
                "path" : "/filters/binary.filter"
              },
              "lineDiffOptions" : {
                "algorithm" : "default",
                "detectMovedBlocks" : true,
                "ignoreBlankLines" : false,
                "ignoreCase" : true,
                "ignoreComments" : false,
                "ignoreLineEndings" : true,
                "ignoreNumbers" : false,
                "indentHeuristic" : false,
                "lineFilters" : [

                ],
                "lineFiltersEnabled" : true,
                "substitutions" : [

                ],
                "substitutionsEnabled" : true,
                "whitespace" : "compareAll"
              },
              "mode" : "binary",
              "recursive" : true,
              "schemaVersion" : 1,
              "sides" : [
                {
                  "identity" : "left",
                  "path" : "/inputs/left.bin",
                  "readOnly" : false
                },
                {
                  "identity" : "right",
                  "path" : "/inputs/right.bin",
                  "readOnly" : true
                }
              ]
            }
            """
        let expected = Data((expectedJSON + "\n").utf8)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, expected)
    }

    func testMaximumFileSizeIsAcceptedAndOneByteOverIsRejectedByEncodeAndLoad() throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let seed = try ComparisonProject(
            left: URL(filePath: "/left"),
            right: URL(filePath: "/right"),
            filter: .named("x")
        )
        let seedData = try seed.encodedData(relativeTo: projectFileURL)
        let exactNameLength = ComparisonProject.maximumFileSize - seedData.count + 1
        let exactProject = try ComparisonProject(
            left: URL(filePath: "/left"),
            right: URL(filePath: "/right"),
            filter: .named(String(repeating: "x", count: exactNameLength))
        )
        let exactData = try exactProject.encodedData(relativeTo: projectFileURL)

        XCTAssertEqual(exactData.count, ComparisonProject.maximumFileSize)
        try exactData.write(to: projectFileURL)
        XCTAssertEqual(try ComparisonProject.load(from: projectFileURL), exactProject)

        let oversizedProject = try ComparisonProject(
            left: URL(filePath: "/left"),
            right: URL(filePath: "/right"),
            filter: .named(String(repeating: "x", count: exactNameLength + 1))
        )
        assertProjectError(.projectFileTooLarge(maximumBytes: ComparisonProject.maximumFileSize)) {
            try oversizedProject.encodedData(relativeTo: projectFileURL)
        }
        let oversizedSaveURL = directory.appending(path: "oversized.macmerge")
        assertProjectError(.projectFileTooLarge(maximumBytes: ComparisonProject.maximumFileSize)) {
            try oversizedProject.save(to: oversizedSaveURL)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: oversizedSaveURL.path))

        var oversizedData = exactData
        oversizedData.append(0x20)
        try oversizedData.write(to: projectFileURL)
        assertProjectError(.projectFileTooLarge(maximumBytes: ComparisonProject.maximumFileSize)) {
            try ComparisonProject.load(from: projectFileURL)
        }
    }

    func testRelativeSchemaPathsResolveAgainstProjectDirectoryWithoutChangingAbsolutePaths() throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let absoluteRight = URL(filePath: "/external/right.txt")
        let data = projectJSON(
            sides: [
                sideJSON(identity: "left", path: "inputs/link/../left.txt"),
                sideJSON(identity: "right", path: absoluteRight.path)
            ],
            filter: ["kind": "file", "path": "filters/default.filter"]
        )
        try data.write(to: projectFileURL)

        let project = try ComparisonProject.load(from: projectFileURL)

        XCTAssertEqual(
            project.side(.left)?.path.path,
            directory.appending(path: "inputs/link/../left.txt").path
        )
        XCTAssertEqual(project.side(.right)?.path, absoluteRight)
        guard case .file(let filterURL) = project.filter else {
            return XCTFail("Expected file filter")
        }
        XCTAssertEqual(filterURL.path, directory.appending(path: "filters/default.filter").path)

        let encoded = try project.encodedData(relativeTo: projectFileURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let encodedSides = try XCTUnwrap(object["sides"] as? [[String: Any]])
        XCTAssertEqual(
            encodedSides.compactMap { $0["path"] as? String },
            [
                directory.appending(path: "inputs/link/../left.txt").path,
                absoluteRight.path
            ]
        )
        let encodedFilter = try XCTUnwrap(object["filter"] as? [String: Any])
        XCTAssertEqual(
            encodedFilter["path"] as? String,
            directory.appending(path: "filters/default.filter").path
        )
    }

    func testStandaloneCodablePreservesRelativePathsAndValidatesValues() throws {
        let sideData = try JSONSerialization.data(
            withJSONObject: sideJSON(
                identity: "left",
                path: "inputs/left.txt"
            ))
        let side = try JSONDecoder().decode(ComparisonProject.Side.self, from: sideData)

        XCTAssertEqual(side.path.relativePath, "inputs/left.txt")
        XCTAssertNotNil(side.path.baseURL)
        let encodedSide = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(side)) as? [String: Any]
        )
        XCTAssertEqual(encodedSide["path"] as? String, "inputs/left.txt")

        for filter in [
            ComparisonProject.FilterReference.named(" \n"),
            .file(URL(string: "https://example.com/filter")!)
        ] {
            assertProjectError(.invalidFilterReference) {
                try JSONEncoder().encode(filter)
            }
        }

        let malformedFilter = try JSONSerialization.data(withJSONObject: [
            "kind": "file",
            "name": "unexpected",
            "path": "/filters/default.filter"
        ])
        assertProjectError(.invalidFilterReference) {
            try JSONDecoder().decode(ComparisonProject.FilterReference.self, from: malformedFilter)
        }
        for object: [String: Any] in [
            ["kind": "named", "name": " \n"],
            ["kind": "file", "path": "//server/filter"]
        ] {
            let data = try JSONSerialization.data(withJSONObject: object)
            assertProjectError(.invalidFilterReference) {
                try JSONDecoder().decode(ComparisonProject.FilterReference.self, from: data)
            }
        }
    }

    func testDecodeRejectsMalformedVersionsAndSideSets() throws {
        for version in [-1, 0, 2] {
            assertProjectError(.unsupportedSchemaVersion(version)) {
                try decodeProject(projectJSON(schemaVersion: version))
            }
        }

        for count in [0, 1, 4] {
            let sides = (0..<count).map {
                sideJSON(identity: $0 == 0 ? "left" : "right", path: "/input-\($0)")
            }
            assertProjectError(.invalidSideCount(count)) {
                try decodeProject(projectJSON(sides: sides))
            }
        }

        assertProjectError(.invalidSideIdentity("center")) {
            try decodeProject(
                projectJSON(sides: [
                    sideJSON(identity: "left", path: "/left"),
                    sideJSON(identity: "center", path: "/right")
                ]))
        }
        assertProjectError(.duplicateSideIdentity(.left)) {
            try decodeProject(
                projectJSON(sides: [
                    sideJSON(identity: "left", path: "/left"),
                    sideJSON(identity: "left", path: "/other-left")
                ]))
        }
        assertProjectError(.invalidSideIdentities([.left, .middle])) {
            try decodeProject(
                projectJSON(sides: [
                    sideJSON(identity: "left", path: "/left"),
                    sideJSON(identity: "middle", path: "/middle")
                ]))
        }
    }

    func testRejectsMalformedSideAndProjectFileURLs() throws {
        let invalidSideURLs = [
            URL(string: "https://example.com/input")!,
            URL(string: "file:relative")!,
            URL(string: "file://example.com/input")!,
            URL(string: "file:///input?query=value")!,
            URL(string: "file:///input#fragment")!
        ]
        for url in invalidSideURLs {
            assertProjectError(.invalidSidePath(.left)) {
                try ComparisonProject.Side(identity: .left, path: url)
            }
            assertProjectError(.invalidSidePath(.left)) {
                try ComparisonProject(left: url, right: URL(filePath: "/right"))
            }
            assertProjectError(.invalidSidePath(.right)) {
                try ComparisonProject(left: URL(filePath: "/left"), right: url)
            }
            assertProjectError(.invalidSidePath(.middle)) {
                try ComparisonProject(
                    left: URL(filePath: "/left"),
                    middle: url,
                    right: URL(filePath: "/right")
                )
            }
            assertProjectError(.invalidFilterReference) {
                try ComparisonProject(
                    left: URL(filePath: "/left"),
                    right: URL(filePath: "/right"),
                    filter: .file(url)
                )
            }
            assertProjectError(.invalidFilterReference) {
                try JSONEncoder().encode(ComparisonProject.FilterReference.file(url))
            }
        }

        for path in ["", "//server/share", "inputs//left", "/inputs//left", "/input\0tail"] {
            let data = try JSONSerialization.data(withJSONObject: sideJSON(identity: "left", path: path))
            assertProjectError(.invalidSidePath(.left)) {
                try JSONDecoder().decode(ComparisonProject.Side.self, from: data)
            }
            assertProjectError(.invalidSidePath(.left)) {
                try decodeProject(projectJSON(sides: [
                    sideJSON(identity: "left", path: path),
                    sideJSON(identity: "right", path: "/right")
                ]))
            }
            let filterData = try JSONSerialization.data(withJSONObject: ["kind": "file", "path": path])
            assertProjectError(.invalidFilterReference) {
                try JSONDecoder().decode(ComparisonProject.FilterReference.self, from: filterData)
            }
            assertProjectError(.invalidFilterReference) {
                try decodeProject(projectJSON(filter: ["kind": "file", "path": path]))
            }
        }

        let project = try ComparisonProject(left: URL(filePath: "/left"), right: URL(filePath: "/right"))
        let invalidProjectURLs = [
            URL(string: "https://example.com/project")!,
            URL(string: "file:project.macmerge")!,
            URL(string: "file://example.com/project.macmerge")!,
            URL(string: "file:///project.macmerge?query=value")!,
            URL(string: "file:///project.macmerge#fragment")!,
            URL(filePath: "/projects", directoryHint: .isDirectory)
        ]
        for url in invalidProjectURLs {
            let expected = ComparisonProjectError.invalidProjectFileURL(url.absoluteString)
            assertProjectError(expected) {
                try project.encodedData(relativeTo: url)
            }
            assertProjectError(expected) {
                try project.save(to: url)
            }
            assertProjectError(expected) {
                try ComparisonProject.load(from: url)
            }
        }
    }

    func testRejectsMalformedEnabledRegexesButIgnoresDisabledRules() throws {
        let validEnabled = try ComparisonProject(
            left: URL(filePath: "/left"),
            right: URL(filePath: "/right"),
            lineDiffOptions: LineDiffOptions(
                lineFilters: [.init(pattern: "^keep$")],
                substitutions: [.init(pattern: "([0-9]+)", replacement: "number")]
            )
        )
        XCTAssertNoThrow(try validEnabled.validate())

        assertProjectError(.invalidRegularExpression("[")) {
            try ComparisonProject(
                left: URL(filePath: "/left"),
                right: URL(filePath: "/right"),
                lineDiffOptions: LineDiffOptions(lineFilters: [.init(pattern: "[")])
            )
        }
        for pattern in ["", "["] {
            assertProjectError(.invalidRegularExpression(pattern)) {
                try ComparisonProject(
                    left: URL(filePath: "/left"),
                    right: URL(filePath: "/right"),
                    lineDiffOptions: LineDiffOptions(
                        substitutions: [.init(pattern: pattern, replacement: "value")]
                    )
                )
            }
        }

        let disabled = try ComparisonProject(
            left: URL(filePath: "/left"),
            right: URL(filePath: "/right"),
            lineDiffOptions: LineDiffOptions(
                lineFiltersEnabled: false,
                lineFilters: [.init(pattern: "[")],
                substitutionsEnabled: false,
                substitutions: [.init(pattern: "", replacement: "value")]
            )
        )
        XCTAssertNoThrow(try disabled.validate())

        let malformedEnabledData = projectJSON(lineDiffOptions: [
            "lineFilters": [["pattern": "[", "caseSensitive": true]]
        ])
        assertProjectError(.invalidRegularExpression("[")) {
            try decodeProject(malformedEnabledData)
        }

        let malformedDisabledData = projectJSON(lineDiffOptions: [
            "lineFiltersEnabled": false,
            "lineFilters": [["pattern": "[", "caseSensitive": true]],
            "substitutionsEnabled": false,
            "substitutions": [["pattern": "", "replacement": "value", "caseSensitive": true]]
        ])
        let decodedDisabled = try decodeProject(malformedDisabledData)
        XCTAssertFalse(decodedDisabled.lineDiffOptions.lineFiltersEnabled)
        XCTAssertEqual(decodedDisabled.lineDiffOptions.lineFilters, [.init(pattern: "[")])
        XCTAssertFalse(decodedDisabled.lineDiffOptions.substitutionsEnabled)
        XCTAssertEqual(
            decodedDisabled.lineDiffOptions.substitutions,
            [.init(pattern: "", replacement: "value")]
        )
    }

    func testLoadAndSaveRejectFinalComponentSymlinksButAllowAncestorSymlinks() throws {
        let directory = try makeTemporaryDirectory()
        let target = directory.appending(path: "target.macmerge")
        let link = directory.appending(path: "link.macmerge")
        let targetData = projectJSON()
        try targetData.write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try ComparisonProject.load(from: link)) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(ELOOP))
        }

        let project = try ComparisonProject(left: URL(filePath: "/left"), right: URL(filePath: "/right"))
        assertProjectError(.replacementDisabled(link.path)) {
            try project.save(to: link)
        }
        XCTAssertEqual(try Data(contentsOf: target), targetData)
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(try artifactNames(in: directory), [])

        let realDirectory = directory.appending(path: "real", directoryHint: .isDirectory)
        let linkedDirectory = directory.appending(path: "linked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: realDirectory)

        let loadURL = linkedDirectory.appending(path: "load.macmerge")
        try targetData.write(to: realDirectory.appending(path: "load.macmerge"))
        XCTAssertEqual(try ComparisonProject.load(from: loadURL), try decodeProject(targetData))

        let saveURL = linkedDirectory.appending(path: "save.macmerge")
        let expectedSavedData = try project.encodedData(relativeTo: saveURL)
        try project.save(to: saveURL)
        XCTAssertEqual(
            try Data(contentsOf: realDirectory.appending(path: "save.macmerge")),
            expectedSavedData
        )
        XCTAssertEqual(try artifactNames(in: realDirectory), [])
    }

    func testSaveExclusivelyPublishesExactDataAndReportsAnyDurabilityUncertainty() throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let project = try ComparisonProject(
            left: URL(filePath: "/left"),
            right: URL(filePath: "/right"),
            rightReadOnly: true,
            mode: .text,
            filter: .named("Saved")
        )
        let expected = try project.encodedData(relativeTo: projectFileURL)

        try project.save(to: projectFileURL)

        var information = stat()
        XCTAssertEqual(projectFileURL.path.withCString { Darwin.lstat($0, &information) }, 0)
        XCTAssertEqual(information.st_mode & S_IFMT, S_IFREG)
        XCTAssertEqual(information.st_mode & 0o177, 0)
        XCTAssertEqual(information.st_nlink, 1)
        XCTAssertEqual(information.st_size, off_t(expected.count))
        XCTAssertEqual(try Data(contentsOf: projectFileURL), expected)
        XCTAssertEqual(try ComparisonProject.load(from: projectFileURL), project)
        XCTAssertEqual(try artifactNames(in: directory), [])
    }

    func testReplacementDisabledPreservesExistingBytesAndMetadata() throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let original = Data("existing user data".utf8)
        try original.write(to: projectFileURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o640))],
            ofItemAtPath: projectFileURL.path
        )
        let originalMetadata = try fileMetadata(at: projectFileURL)
        let project = try ComparisonProject(left: URL(filePath: "/left"), right: URL(filePath: "/right"))

        assertProjectError(.replacementDisabled(projectFileURL.path)) {
            try project.save(to: projectFileURL)
        }

        XCTAssertEqual(try Data(contentsOf: projectFileURL), original)
        XCTAssertEqual(try fileMetadata(at: projectFileURL), originalMetadata)
        XCTAssertEqual(try artifactNames(in: directory), [])
    }

    func testExclusiveSaveRejectsSameSizeStagedOverwriteBeforeRename() throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let project = try ComparisonProject(left: URL(filePath: "/left"), right: URL(filePath: "/right"))
        let expected = try project.encodedData(relativeTo: projectFileURL)
        let overwrite = Data(repeating: 0xA5, count: expected.count)

        assertProjectError(.changedOnDisk) {
            try project.save(to: projectFileURL) {
                let stagedName = try XCTUnwrap(try self.artifactNames(in: directory).first)
                try overwrite.write(to: directory.appending(path: stagedName))
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: projectFileURL.path))
        let stagedName = try XCTUnwrap(try artifactNames(in: directory).first)
        XCTAssertEqual(try artifactNames(in: directory).count, 1)
        XCTAssertEqual(try Data(contentsOf: directory.appending(path: stagedName)), overwrite)
    }

    func testExclusiveSaveRejectsHardLinkMutationBeforeRename() throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let hardLinkURL = directory.appending(path: "staged-hard-link.macmerge")
        let project = try ComparisonProject(left: URL(filePath: "/left"), right: URL(filePath: "/right"))
        let expected = try project.encodedData(relativeTo: projectFileURL)
        let mutation = Data(repeating: 0xA5, count: expected.count)

        assertProjectError(.changedOnDisk) {
            try project.save(to: projectFileURL) {
                let stagedName = try XCTUnwrap(try self.artifactNames(in: directory).first)
                try FileManager.default.linkItem(
                    at: directory.appending(path: stagedName),
                    to: hardLinkURL
                )
                try mutation.write(to: hardLinkURL)
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: projectFileURL.path))
        let stagedName = try XCTUnwrap(try artifactNames(in: directory).first)
        XCTAssertEqual(try artifactNames(in: directory).count, 1)
        XCTAssertEqual(try Data(contentsOf: directory.appending(path: stagedName)), mutation)
        XCTAssertEqual(try Data(contentsOf: hardLinkURL), mutation)
        XCTAssertEqual(try fileMetadata(at: hardLinkURL).links, 2)
    }

    func testUncertainExclusiveSaveWhenAncestorSymlinkRetargetedAfterPublish() throws {
        let directory = try makeTemporaryDirectory()
        let firstDirectory = directory.appending(path: "first", directoryHint: .isDirectory)
        let secondDirectory = directory.appending(path: "second", directoryHint: .isDirectory)
        let linkedDirectory = directory.appending(path: "linked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: firstDirectory)
        let projectFileURL = linkedDirectory.appending(path: "comparison.macmerge")
        let firstProjectFileURL = firstDirectory.appending(path: "comparison.macmerge")
        let secondProjectFileURL = secondDirectory.appending(path: "comparison.macmerge")
        let project = try ComparisonProject(left: URL(filePath: "/left"), right: URL(filePath: "/right"))
        let expected = try project.encodedData(relativeTo: projectFileURL)
        var observedPhases: [ExclusiveSaveRacePhase] = []
        var publishedMetadata: ComparisonProjectFileMetadata?

        assertProjectError(.saveOutcomeUncertain(projectFileURL.path)) {
            try project.save(
                to: projectFileURL,
                afterInitialPublishValidation: {
                    XCTAssertEqual(observedPhases, [])
                    XCTAssertEqual(try Data(contentsOf: projectFileURL), expected)
                    XCTAssertEqual(try Data(contentsOf: firstProjectFileURL), expected)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: secondProjectFileURL.path))
                    XCTAssertEqual(try self.artifactNames(in: firstDirectory), [])
                    publishedMetadata = try self.fileMetadata(at: firstProjectFileURL)
                    observedPhases.append(.initialPublicationValidated)

                    try FileManager.default.removeItem(at: linkedDirectory)
                    try FileManager.default.createSymbolicLink(
                        at: linkedDirectory,
                        withDestinationURL: secondDirectory
                    )
                    XCTAssertFalse(FileManager.default.fileExists(atPath: projectFileURL.path))
                    observedPhases.append(.ancestorRetargeted)
                },
                afterRecoveryOwnershipObservation: {
                    XCTAssertEqual(observedPhases, [.initialPublicationValidated, .ancestorRetargeted])
                    XCTAssertEqual(try Data(contentsOf: firstProjectFileURL), expected)
                    XCTAssertEqual(try self.fileMetadata(at: firstProjectFileURL), publishedMetadata)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: projectFileURL.path))
                    XCTAssertEqual(try self.artifactNames(in: firstDirectory), [])
                    observedPhases.append(.recoveryOwnershipObserved)
                }
            )
        }

        XCTAssertEqual(
            observedPhases,
            [.initialPublicationValidated, .ancestorRetargeted, .recoveryOwnershipObserved]
        )
        XCTAssertEqual(try Data(contentsOf: firstProjectFileURL), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondProjectFileURL.path))
        XCTAssertEqual(try artifactNames(in: firstDirectory), [])
        XCTAssertEqual(try artifactNames(in: secondDirectory), [])
    }

    func testUncertainExclusiveSaveWhenTargetReplacedAfterPublish() throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let displacedPublicationURL = directory.appending(path: "published.macmerge")
        let project = try ComparisonProject(left: URL(filePath: "/left"), right: URL(filePath: "/right"))
        let publishedData = try project.encodedData(relativeTo: projectFileURL)
        let replacement = Data(repeating: 0xA5, count: publishedData.count)
        var observedPhases: [ExclusiveSaveRacePhase] = []

        assertProjectError(.saveOutcomeUncertain(projectFileURL.path)) {
            try project.save(
                to: projectFileURL,
                afterInitialPublishValidation: {
                    XCTAssertEqual(observedPhases, [])
                    XCTAssertEqual(try Data(contentsOf: projectFileURL), publishedData)
                    XCTAssertEqual(try self.fileMetadata(at: projectFileURL).links, 1)
                    XCTAssertEqual(try self.artifactNames(in: directory), [])
                    observedPhases.append(.initialPublicationValidated)

                    try FileManager.default.moveItem(at: projectFileURL, to: displacedPublicationURL)
                    try replacement.write(to: projectFileURL)
                    observedPhases.append(.targetReplaced)
                },
                afterRecoveryOwnershipObservation: {
                    observedPhases.append(.unexpectedRecoveryOwnershipObservation)
                    XCTFail("Recovery callback ran after target ownership was lost")
                }
            )
        }

        XCTAssertEqual(observedPhases, [.initialPublicationValidated, .targetReplaced])
        XCTAssertEqual(try Data(contentsOf: projectFileURL), replacement)
        XCTAssertEqual(try Data(contentsOf: displacedPublicationURL), publishedData)
        XCTAssertEqual(try artifactNames(in: directory), [])
    }

    func testUncertainExclusiveSaveWhenTargetDeletedAfterPublish() throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let project = try ComparisonProject(left: URL(filePath: "/left"), right: URL(filePath: "/right"))
        let publishedData = try project.encodedData(relativeTo: projectFileURL)
        var observedPhases: [ExclusiveSaveRacePhase] = []

        assertProjectError(.saveOutcomeUncertain(projectFileURL.path)) {
            try project.save(
                to: projectFileURL,
                afterInitialPublishValidation: {
                    XCTAssertEqual(observedPhases, [])
                    XCTAssertEqual(try Data(contentsOf: projectFileURL), publishedData)
                    XCTAssertEqual(try self.fileMetadata(at: projectFileURL).links, 1)
                    XCTAssertEqual(try self.artifactNames(in: directory), [])
                    observedPhases.append(.initialPublicationValidated)

                    try FileManager.default.removeItem(at: projectFileURL)
                    observedPhases.append(.targetDeleted)
                },
                afterRecoveryOwnershipObservation: {
                    observedPhases.append(.unexpectedRecoveryOwnershipObservation)
                    XCTFail("Recovery callback ran after target ownership was lost")
                }
            )
        }

        XCTAssertEqual(observedPhases, [.initialPublicationValidated, .targetDeleted])
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectFileURL.path))
        XCTAssertEqual(try artifactNames(in: directory), [])
    }

    func testUncertainExclusiveSavePreservesSameSizeReplacementAfterOwnershipObservation() throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let displacedPublicationURL = directory.appending(path: "published.macmerge")
        let project = try ComparisonProject(left: URL(filePath: "/left"), right: URL(filePath: "/right"))
        let publishedData = try project.encodedData(relativeTo: projectFileURL)
        let unrelatedReplacement = Data(repeating: 0xA5, count: publishedData.count)
        var observedPhases: [ExclusiveSaveRacePhase] = []
        var publishedMetadata: ComparisonProjectFileMetadata?

        assertProjectError(.saveOutcomeUncertain(projectFileURL.path)) {
            try project.save(
                to: projectFileURL,
                afterInitialPublishValidation: {
                    XCTAssertEqual(observedPhases, [])
                    XCTAssertEqual(try Data(contentsOf: projectFileURL), publishedData)
                    XCTAssertEqual(try self.fileMetadata(at: projectFileURL).links, 1)
                    XCTAssertEqual(try self.artifactNames(in: directory), [])
                    publishedMetadata = try self.fileMetadata(at: projectFileURL)
                    observedPhases.append(.initialPublicationValidated)
                    observedPhases.append(.initialFailureInjected)
                    throw ComparisonProjectTestError.injectedSaveFailure
                },
                afterRecoveryOwnershipObservation: {
                    XCTAssertEqual(
                        observedPhases,
                        [.initialPublicationValidated, .initialFailureInjected]
                    )
                    XCTAssertEqual(try Data(contentsOf: projectFileURL), publishedData)
                    XCTAssertEqual(try self.fileMetadata(at: projectFileURL), publishedMetadata)
                    XCTAssertEqual(try self.artifactNames(in: directory), [])
                    observedPhases.append(.recoveryOwnershipObserved)

                    try FileManager.default.moveItem(at: projectFileURL, to: displacedPublicationURL)
                    try unrelatedReplacement.write(to: projectFileURL)
                    observedPhases.append(.targetReplaced)
                }
            )
        }

        XCTAssertEqual(
            observedPhases,
            [
                .initialPublicationValidated,
                .initialFailureInjected,
                .recoveryOwnershipObserved,
                .targetReplaced
            ]
        )
        XCTAssertEqual(try Data(contentsOf: projectFileURL), unrelatedReplacement)
        XCTAssertEqual(try Data(contentsOf: displacedPublicationURL), publishedData)
        XCTAssertEqual(try artifactNames(in: directory), [])
    }

    func testConcurrentExclusiveSavesPublishExactlyOneCompleteProject() async throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let projects = [
            try ComparisonProject(left: URL(filePath: "/first-left"), right: URL(filePath: "/first-right"), mode: .text),
            try ComparisonProject(left: URL(filePath: "/second-left"), right: URL(filePath: "/second-right"), mode: .binary)
        ]
        let renameBarrier = ComparisonProjectRenameBarrier(participantCount: projects.count)

        let results = await withTaskGroup(of: ExclusiveSaveResult.self) { group in
            for project in projects {
                group.addTask {
                    do {
                        try project.save(to: projectFileURL) {
                            try renameBarrier.wait()
                        }
                        return .published(project)
                    } catch let error as ComparisonProjectError {
                        return .rejected(project, error)
                    } catch {
                        return .unexpected(project, String(describing: error))
                    }
                }
            }

            var values: [ExclusiveSaveResult] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        let publications = results.compactMap { result -> ComparisonProject? in
            guard case .published(let project) = result else { return nil }
            return project
        }
        let publication = try XCTUnwrap(publications.first)
        XCTAssertEqual(publications.count, 1)
        XCTAssertEqual(try ComparisonProject.load(from: projectFileURL), publication)
        XCTAssertEqual(
            try Data(contentsOf: projectFileURL),
            try publication.encodedData(relativeTo: projectFileURL)
        )
        let rejection = try XCTUnwrap(results.compactMap(\.rejection).first)
        XCTAssertEqual(results.compactMap(\.rejection).count, 1)
        XCTAssertEqual(rejection.error, .changedOnDisk)
        XCTAssertFalse(results.contains { if case .unexpected = $0 { true } else { false } })

        let artifacts = try artifactNames(in: directory)
        let artifactName = try XCTUnwrap(artifacts.first)
        XCTAssertEqual(artifacts.count, 1)
        let artifactURL = directory.appending(path: artifactName)
        let artifactMetadata = try fileMetadata(at: artifactURL)
        XCTAssertEqual(artifactMetadata.mode & S_IFMT, S_IFREG)
        XCTAssertEqual(artifactMetadata.mode & 0o177, 0)
        XCTAssertEqual(artifactMetadata.links, 1)
        XCTAssertEqual(
            try Data(contentsOf: artifactURL),
            try rejection.project.encodedData(relativeTo: projectFileURL)
        )
    }

    func testConcurrentAtomicReplacementReadsReturnCompleteVersionOrChangedWhileReading() async throws {
        let directory = try makeTemporaryDirectory()
        let projectFileURL = directory.appending(path: "comparison.macmerge")
        let padding = String(repeating: "x", count: 512 * 1024)
        let first = try ComparisonProject(
            left: URL(filePath: "/first-left"),
            right: URL(filePath: "/first-right"),
            mode: .text,
            filter: .named("first-\(padding)")
        )
        let second = try ComparisonProject(
            left: URL(filePath: "/second-left"),
            right: URL(filePath: "/second-right"),
            mode: .binary,
            filter: .named("second-\(padding)")
        )
        let firstData = try first.encodedData(relativeTo: projectFileURL)
        let secondData = try second.encodedData(relativeTo: projectFileURL)
        try firstData.write(to: projectFileURL)
        let operationCount = 24
        let readerCount = 4
        let startGate = ComparisonProjectStartGate(participantCount: readerCount + 1)
        let roundGate = ComparisonProjectRoundGate(participantCount: readerCount + 1)

        let results = await withTaskGroup(of: ReadWriteRaceResult.self) { group in
            group.addTask {
                await startGate.wait()
                var errorDescription: String?
                for index in 0..<operationCount {
                    await roundGate.wait()
                    if errorDescription == nil {
                        do {
                            try (index.isMultiple(of: 2) ? firstData : secondData)
                                .write(to: projectFileURL, options: .atomic)
                        } catch {
                            errorDescription = String(describing: error)
                        }
                    }
                    await roundGate.wait()
                }
                return .writerCompleted(errorDescription: errorDescription)
            }
            for _ in 0..<readerCount {
                group.addTask {
                    await startGate.wait()
                    var outcomes: [ProjectReadOutcome] = []
                    var errorDescription: String?
                    for _ in 0..<operationCount {
                        await roundGate.wait()
                        if errorDescription == nil {
                            do {
                                let project = try ComparisonProject.load(from: projectFileURL)
                                if project == first {
                                    outcomes.append(.first)
                                } else if project == second {
                                    outcomes.append(.second)
                                } else {
                                    throw ComparisonProjectTestError.unexpectedProject
                                }
                            } catch ComparisonProjectError.changedWhileReading {
                                outcomes.append(.changedWhileReading)
                            } catch {
                                errorDescription = String(describing: error)
                            }
                        }
                        await roundGate.wait()
                    }
                    return .readerCompleted(outcomes, errorDescription: errorDescription)
                }
            }

            var values: [ReadWriteRaceResult] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertTrue(results.contains(.writerCompleted(errorDescription: nil)))
        let readerOutcomes = results.compactMap(\.readOutcomes)
        XCTAssertEqual(readerOutcomes.count, readerCount)
        XCTAssertTrue(readerOutcomes.allSatisfy { $0.count == operationCount })
        XCTAssertNil(results.compactMap(\.errorDescription).first)
        XCTAssertEqual(try ComparisonProject.load(from: projectFileURL), second)
        XCTAssertEqual(try Data(contentsOf: projectFileURL), secondData)
    }

    private func decodeProject(_ data: Data) throws -> ComparisonProject {
        try JSONDecoder().decode(ComparisonProject.self, from: data)
    }

    private func projectJSON(
        schemaVersion: Int = ComparisonProject.currentSchemaVersion,
        sides: [[String: Any]] = [
            ["identity": "left", "path": "/left", "readOnly": false],
            ["identity": "right", "path": "/right", "readOnly": false]
        ],
        filter: [String: Any]? = nil,
        lineDiffOptions: [String: Any] = [:]
    ) -> Data {
        var object: [String: Any] = [
            "schemaVersion": schemaVersion,
            "mode": "automatic",
            "sides": sides,
            "recursive": false,
            "lineDiffOptions": lineDiffOptions
        ]
        object["filter"] = filter
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sideJSON(identity: String, path: String, readOnly: Bool = false) -> [String: Any] {
        ["identity": identity, "path": path, "readOnly": readOnly]
    }

    private func assertProjectError<T>(
        _ expected: ComparisonProjectError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ComparisonProjectError, expected, file: file, line: line)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func artifactNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix(".macmerge-project-") }
            .sorted()
    }

    private func fileMetadata(at url: URL) throws -> ComparisonProjectFileMetadata {
        var information = stat()
        guard url.path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return ComparisonProjectFileMetadata(information)
    }
}

private actor ComparisonProjectStartGate {
    private let participantCount: Int
    private var arrivalCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func wait() async {
        arrivalCount += 1
        if arrivalCount == participantCount {
            let waiting = waiters
            waiters.removeAll()
            for waiter in waiting {
                waiter.resume()
            }
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }
}

private actor ComparisonProjectRoundGate {
    private let participantCount: Int
    private var arrivalCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func wait() async {
        arrivalCount += 1
        if arrivalCount == participantCount {
            arrivalCount = 0
            let waiting = waiters
            waiters.removeAll()
            for waiter in waiting {
                waiter.resume()
            }
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }
}

private final class ComparisonProjectRenameBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private let participantCount: Int
    private var arrivalCount = 0

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func wait() throws {
        condition.lock()
        defer { condition.unlock() }

        arrivalCount += 1
        if arrivalCount == participantCount {
            condition.broadcast()
            return
        }

        let deadline = Date().addingTimeInterval(5)
        while arrivalCount < participantCount {
            guard condition.wait(until: deadline) else {
                throw ComparisonProjectTestError.renameBarrierTimedOut
            }
        }
    }
}

private enum ExclusiveSaveResult: Sendable {
    case published(ComparisonProject)
    case rejected(ComparisonProject, ComparisonProjectError)
    case unexpected(ComparisonProject, String)

    var rejection: (project: ComparisonProject, error: ComparisonProjectError)? {
        guard case .rejected(let project, let error) = self else { return nil }
        return (project, error)
    }
}

private enum ProjectReadOutcome: Equatable, Sendable {
    case first
    case second
    case changedWhileReading
}

private enum ReadWriteRaceResult: Equatable, Sendable {
    case writerCompleted(errorDescription: String?)
    case readerCompleted([ProjectReadOutcome], errorDescription: String?)

    var readOutcomes: [ProjectReadOutcome]? {
        guard case .readerCompleted(let outcomes, _) = self else { return nil }
        return outcomes
    }

    var errorDescription: String? {
        switch self {
        case .writerCompleted(let errorDescription), .readerCompleted(_, let errorDescription):
            errorDescription
        }
    }
}

private enum ComparisonProjectTestError: Error {
    case injectedSaveFailure
    case renameBarrierTimedOut
    case unexpectedProject
}

private enum ExclusiveSaveRacePhase: Equatable {
    case initialPublicationValidated
    case initialFailureInjected
    case ancestorRetargeted
    case targetReplaced
    case targetDeleted
    case recoveryOwnershipObserved
    case unexpectedRecoveryOwnershipObservation
}

private struct ComparisonProjectFileMetadata: Equatable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let links: nlink_t
    let owner: uid_t
    let group: gid_t
    let size: off_t
    let flags: UInt32
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init(_ information: stat) {
        device = information.st_dev
        inode = information.st_ino
        mode = information.st_mode
        links = information.st_nlink
        owner = information.st_uid
        group = information.st_gid
        size = information.st_size
        flags = information.st_flags
        modifiedSeconds = information.st_mtimespec.tv_sec
        modifiedNanoseconds = information.st_mtimespec.tv_nsec
        changedSeconds = information.st_ctimespec.tv_sec
        changedNanoseconds = information.st_ctimespec.tv_nsec
    }
}
