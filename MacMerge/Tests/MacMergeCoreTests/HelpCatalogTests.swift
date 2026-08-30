import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class HelpCatalogTests: XCTestCase {
    private static let oneMiB = 1 * 1_024 * 1_024

    func testStructuralDefaultContainsNoVisibleOrInventedMetadata() throws {
        let catalog = HelpCatalog.structuralDefault

        XCTAssertEqual(catalog, .empty)
        XCTAssertEqual(catalog.manifestVersion, HelpCatalog.currentManifestVersion)
        XCTAssertEqual(catalog.topics, [])
        XCTAssertEqual(catalog.credits, [])
        XCTAssertEqual(catalog.topicIDs, [])
        XCTAssertEqual(catalog.creditIDs, [])
        XCTAssertEqual(catalog.about, .empty)
        XCTAssertNil(catalog.about.version)
        XCTAssertNil(catalog.about.build)
        XCTAssertNil(catalog.about.copyrightLocalizationKey)
        XCTAssertEqual(catalog.about.links, [])
        XCTAssertEqual(catalog.about.creditIDs, [])

        let data = try catalog.manifestData()
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            #"{"about":{"creditIDs":[],"links":[]},"credits":[],"manifestVersion":1,"topics":[]}"#
        )
        XCTAssertEqual(try HelpCatalog.decodeManifest(from: data), catalog)
    }

    func testAllFieldsManifestUsesExactCanonicalWire() throws {
        let root = try makeTemporaryDirectory()
        let guides = root.appending(path: "Guides", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: guides, withIntermediateDirectories: false)
        try Data("help".utf8).write(to: guides.appending(path: "Help.txt"))
        let policy = try HelpCatalogTrustPolicy(
            trustedExternalHosts: ["docs.example.com"],
            resolvedBundleRoot: root,
            bundledResourceResolver: { path in root.appending(path: path) }
        )
        let context = try HelpCatalogContext(kind: .command, identifier: "file.open")
        let resourceLink = try HelpCatalogLink.bundledResource(
            path: "Guides/Help.txt",
            fragment: "overview",
            labelLocalizationKey: "links.resource",
            trustPolicy: policy
        )
        let webLink = try HelpCatalogLink.secureWeb(
            "https://docs.example.com/person",
            labelLocalizationKey: "links.person",
            trustPolicy: policy
        )
        let credit = try HelpCatalogCredit(
            id: "person",
            kind: .contributor,
            nameLocalizationKey: "credits.person.name",
            roleLocalizationKey: "credits.person.role",
            detailLocalizationKey: "credits.person.detail",
            links: [webLink]
        )
        let primary = try HelpCatalogTopic(
            id: "primary",
            kind: .command,
            titleLocalizationKey: "topics.primary.title",
            summaryLocalizationKey: "topics.primary.summary",
            keywordLocalizationKeys: ["topics.primary.keyword"],
            contexts: [context],
            links: [resourceLink],
            relatedTopicIDs: ["related"],
            creditIDs: [credit.id]
        )
        let related = try makeTopic(id: "related", kind: .releaseNotes)
        let aboutLink = try HelpCatalogLink.secureWeb(
            "https://docs.example.com/help",
            labelLocalizationKey: "links.help",
            trustPolicy: policy
        )
        let about = try HelpCatalogAboutMetadata(
            version: try HelpCatalogProvenancedValue(
                value: "1.2.3",
                source: .applicationBundleMetadata
            ),
            build: try HelpCatalogProvenancedValue(value: "42", source: .buildConfiguration),
            copyrightLocalizationKey: "about.copyright",
            links: [aboutLink],
            creditIDs: [credit.id]
        )
        let catalog = try HelpCatalog(
            topics: [primary, related],
            credits: [credit],
            about: about
        )

        let data = try catalog.manifestData()
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            #"{"about":{"build":{"value":"42"},"copyrightLocalizationKey":"about.copyright","creditIDs":["person"],"links":[{"labelLocalizationKey":"links.help","scheme":"https","target":"https://docs.example.com/help"}],"version":{"value":"1.2.3"}},"credits":[{"detailLocalizationKey":"credits.person.detail","id":"person","kind":"contributor","links":[{"labelLocalizationKey":"links.person","scheme":"https","target":"https://docs.example.com/person"}],"nameLocalizationKey":"credits.person.name","roleLocalizationKey":"credits.person.role"}],"manifestVersion":1,"topics":[{"contexts":[{"identifier":"file.open","kind":"command"}],"creditIDs":["person"],"id":"primary","keywordLocalizationKeys":["topics.primary.keyword"],"kind":"command","links":[{"fragment":"overview","labelLocalizationKey":"links.resource","scheme":"bundledResource","target":"Guides/Help.txt"}],"relatedTopicIDs":["related"],"summaryLocalizationKey":"topics.primary.summary","titleLocalizationKey":"topics.primary.title"},{"contexts":[],"creditIDs":[],"id":"related","keywordLocalizationKeys":[],"kind":"releaseNotes","links":[],"relatedTopicIDs":[],"titleLocalizationKey":"topics.related.title"}]}"#
        )
        XCTAssertEqual(
            try HelpCatalog.decodeManifest(
                from: data,
                provenance: HelpCatalogManifestProvenance(
                    versionSource: .applicationBundleMetadata,
                    buildSource: .buildConfiguration
                ),
                trustPolicy: policy
            ),
            catalog
        )
    }

    func testManifestVersionAndBuildProvenanceMustComeFromTrustedCaller() throws {
        let about = try HelpCatalogAboutMetadata(
            version: HelpCatalogProvenancedValue(value: "1.2.3", source: .applicationBundleMetadata),
            build: HelpCatalogProvenancedValue(value: "456", source: .buildConfiguration)
        )
        let catalog = try HelpCatalog(topics: [], about: about)
        let data = try catalog.manifestData()
        let wireText = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(wireText.contains("applicationBundleMetadata"))
        XCTAssertFalse(wireText.contains("buildConfiguration"))
        assertHelpCatalogError(.missingManifestProvenance(field: "version")) {
            try HelpCatalog.decodeManifest(from: data)
        }
        assertHelpCatalogError(.missingManifestProvenance(field: "build")) {
            try HelpCatalog.decodeManifest(
                from: data,
                provenance: HelpCatalogManifestProvenance(
                    versionSource: .applicationBundleMetadata
                )
            )
        }

        let decoded = try HelpCatalog.decodeManifest(
            from: data,
            provenance: HelpCatalogManifestProvenance(
                versionSource: .applicationBundleMetadata,
                buildSource: .buildConfiguration
            )
        )
        XCTAssertEqual(decoded, catalog)
        XCTAssertEqual(decoded.about.version?.source, .applicationBundleMetadata)
        XCTAssertEqual(decoded.about.build?.source, .buildConfiguration)

        let callerAttributed = try HelpCatalog.decodeManifest(
            from: data,
            provenance: HelpCatalogManifestProvenance(
                versionSource: .callerProvided,
                buildSource: .releaseManifest
            )
        )
        XCTAssertNotEqual(callerAttributed, catalog)
        XCTAssertEqual(callerAttributed.about.version?.source, .callerProvided)
        XCTAssertEqual(callerAttributed.about.build?.source, .releaseManifest)

        let encodedValue = try JSONEncoder().encode(
            HelpCatalogProvenancedValue(value: "1.2.3", source: .callerProvided)
        )
        XCTAssertEqual(String(decoding: encodedValue, as: UTF8.self), #"{"value":"1.2.3"}"#)
        assertHelpCatalogError(.boundedManifestDecodingRequired) {
            try JSONDecoder().decode(HelpCatalogProvenancedValue.self, from: encodedValue)
        }
    }

    func testCatalogIndexesRelationshipsAndNavigationPreserveSourceOrder() throws {
        let openContext = try HelpCatalogContext(kind: .command, identifier: "file.open")
        let preferencesContext = try HelpCatalogContext(
            kind: .dialog,
            identifier: "settings.preferences"
        )
        let contributor = try HelpCatalogCredit(
            id: "core-team",
            kind: .contributor,
            nameLocalizationKey: "credits.core-team.name"
        )
        let introduction = try makeTopic(
            id: "introduction",
            kind: .helpBook,
            links: [try .helpBook(anchor: "introduction")],
            relatedTopicIDs: ["file-open"],
            creditIDs: [contributor.id]
        )
        let open = try makeTopic(
            id: "file-open",
            kind: .command,
            contexts: [openContext],
            links: [try .helpBook(anchor: "file-open")]
        )
        let preferences = try makeTopic(
            id: "preferences",
            kind: .dialog,
            contexts: [preferencesContext]
        )
        let release = try makeTopic(id: "release-1", kind: .releaseNotes)
        let catalog = try HelpCatalog(
            topics: [introduction, open, preferences, release],
            credits: [contributor]
        )

        XCTAssertEqual(catalog.topicIDs, ["introduction", "file-open", "preferences", "release-1"])
        XCTAssertEqual(catalog.creditIDs, ["core-team"])
        XCTAssertEqual(catalog.topic(withID: open.id), open)
        XCTAssertNil(catalog.topic(withID: "missing"))
        XCTAssertEqual(catalog.credit(withID: contributor.id), contributor)
        XCTAssertNil(catalog.credit(withID: "missing"))
        XCTAssertEqual(try catalog.lookupTopic(introduction.id), introduction)
        XCTAssertEqual(try catalog.lookupCredit(contributor.id), contributor)
        XCTAssertEqual(try catalog.topic(for: openContext), open)
        XCTAssertEqual(try catalog.topic(for: preferencesContext), preferences)
        XCTAssertEqual(try catalog.topic(forHelpBookAnchor: "file-open"), open)
        XCTAssertEqual(try catalog.topics(ofKind: .command), [open])
        XCTAssertEqual(try catalog.relatedTopics(to: introduction.id), [open])
        XCTAssertEqual(
            try catalog.topic(
                adjacentTo: introduction.id,
                direction: .next,
                kinds: [.command]
            ),
            open
        )
        XCTAssertEqual(
            try catalog.topic(
                adjacentTo: introduction.id,
                direction: .previous,
                kinds: [.releaseNotes]
            ),
            release
        )
        XCTAssertNil(
            try catalog.topic(
                adjacentTo: release.id,
                direction: .next,
                wrapping: false
            )
        )
        XCTAssertNil(
            try catalog.topic(
                adjacentTo: open.id,
                direction: .next,
                kinds: [.about]
            )
        )
        assertHelpCatalogError(.unknownTopicID("missing")) {
            try catalog.relatedTopics(to: "missing")
        }
        assertHelpCatalogError(.unknownTopicID("missing")) {
            try catalog.topic(adjacentTo: "missing", direction: .next)
        }
        assertHelpCatalogError(.invalidLinkTarget(scheme: .helpBook)) {
            try catalog.topic(forHelpBookAnchor: "../unsafe")
        }

        XCTAssertEqual(
            catalog,
            try HelpCatalog(
                topics: [introduction, open, preferences, release],
                credits: [contributor]
            )
        )
    }

    func testCatalogValidationRejectsDuplicateAndDanglingRelationships() throws {
        let contributor = try HelpCatalogCredit(
            id: "person",
            kind: .contributor,
            nameLocalizationKey: "credits.person.name"
        )
        let first = try makeTopic(id: "first")
        let sameContext = try HelpCatalogContext(kind: .command, identifier: "shared.command")
        let contextOwner = try makeTopic(
            id: "context-owner",
            kind: .command,
            contexts: [sameContext]
        )
        let secondContextOwner = try makeTopic(
            id: "second-context-owner",
            kind: .command,
            contexts: [sameContext]
        )
        let firstAnchorOwner = try makeTopic(
            id: "first-anchor-owner",
            links: [try .helpBook(anchor: "shared-anchor")]
        )
        let secondAnchorOwner = try makeTopic(
            id: "second-anchor-owner",
            links: [try .helpBook(anchor: "shared-anchor")]
        )

        assertHelpCatalogError(.duplicateTopicID(first.id)) {
            try HelpCatalog(topics: [first, first])
        }
        assertHelpCatalogError(.duplicateCreditID(contributor.id)) {
            try HelpCatalog(topics: [], credits: [contributor, contributor])
        }
        assertHelpCatalogError(.duplicateContext(sameContext)) {
            try HelpCatalog(topics: [contextOwner, secondContextOwner])
        }
        assertHelpCatalogError(.duplicateHelpBookAnchor("shared-anchor")) {
            try HelpCatalog(topics: [firstAnchorOwner, secondAnchorOwner])
        }
        assertHelpCatalogError(.missingRelatedTopic("missing")) {
            try HelpCatalog(
                topics: [try makeTopic(id: "source", relatedTopicIDs: ["missing"])]
            )
        }
        assertHelpCatalogError(.missingCredit("missing")) {
            try HelpCatalog(
                topics: [try makeTopic(id: "source", creditIDs: ["missing"])]
            )
        }
        assertHelpCatalogError(.missingCredit("missing")) {
            try HelpCatalog(
                topics: [],
                about: HelpCatalogAboutMetadata(creditIDs: ["missing"])
            )
        }
        assertHelpCatalogError(.selfRelatedTopic("self")) {
            try makeTopic(id: "self", relatedTopicIDs: ["self"])
        }
        assertHelpCatalogError(.contextKindMismatch(topicID: "wrong-kind")) {
            try makeTopic(id: "wrong-kind", contexts: [sameContext])
        }
    }

    func testTopicCreditAndLimitValidationIsStrict() throws {
        let context = try HelpCatalogContext(kind: .command, identifier: "command.open")
        let link = try HelpCatalogLink.helpBook(anchor: "open")

        assertHelpCatalogError(.invalidIdentifier(field: "context.identifier")) {
            try HelpCatalogContext(kind: .command, identifier: "not valid")
        }
        assertHelpCatalogError(.invalidIdentifier(field: "topic.id")) {
            try makeTopic(id: "not/valid")
        }
        assertHelpCatalogError(.invalidLocalizationKey(field: "topic.titleLocalizationKey")) {
            try HelpCatalogTopic(
                id: "topic",
                kind: .helpBook,
                titleLocalizationKey: ".invalid"
            )
        }
        assertHelpCatalogError(.duplicateValue(field: "topic.keywordLocalizationKeys")) {
            try makeTopic(
                id: "topic",
                keywordLocalizationKeys: ["topic.keyword", "topic.keyword"]
            )
        }
        assertHelpCatalogError(.duplicateValue(field: "topic.contexts")) {
            try makeTopic(
                id: "topic",
                kind: .command,
                contexts: [context, context]
            )
        }
        assertHelpCatalogError(.duplicateValue(field: "topic.links")) {
            try makeTopic(id: "topic", links: [link, link])
        }
        assertHelpCatalogError(.duplicateValue(field: "topic.relatedTopicIDs")) {
            try makeTopic(
                id: "topic",
                relatedTopicIDs: ["other", "other"]
            )
        }
        assertHelpCatalogError(.duplicateValue(field: "topic.creditIDs")) {
            try makeTopic(id: "topic", creditIDs: ["person", "person"])
        }
        assertHelpCatalogError(.duplicateValue(field: "credit.links")) {
            try HelpCatalogCredit(
                id: "person",
                kind: .contributor,
                nameLocalizationKey: "credits.person.name",
                links: [link, link]
            )
        }
        assertHelpCatalogError(.duplicateValue(field: "about.creditIDs")) {
            try HelpCatalogAboutMetadata(creditIDs: ["person", "person"])
        }
        assertHelpCatalogError(.invalidLimit(name: "maximumTopics", value: -1)) {
            try HelpCatalog(
                topics: [],
                limits: catalogLimits(maximumTopics: -1)
            )
        }
        assertHelpCatalogError(.tooManyTopics(maximum: 1)) {
            try HelpCatalog(
                topics: [try makeTopic(id: "first"), try makeTopic(id: "second")],
                limits: catalogLimits(maximumTopics: 1)
            )
        }

        let topicData = Data(topicJSON(id: "topic").utf8)
        assertHelpCatalogError(.boundedManifestDecodingRequired) {
            try JSONDecoder().decode(HelpCatalogTopic.self, from: topicData)
        }
    }

    func testVersionMetadataRequiresVisibleNonFillerContent() throws {
        let visible = try HelpCatalogProvenancedValue(
            value: "1.2-β+🚀",
            source: .callerProvided
        )
        XCTAssertEqual(visible.value, "1.2-β+🚀")
        XCTAssertEqual(visible.source, .callerProvided)

        let rejectedValues = [
            "",
            " ",
            " 1.2",
            "1.2 ",
            "1\u{200B}2",
            "\u{115F}",
            "\u{1160}",
            "\u{2800}",
            "\u{3164}",
            "\u{FFA0}",
            "\u{13441}",
            "\u{13442}",
            "\u{16FE4}"
        ]
        for value in rejectedValues {
            assertHelpCatalogError(.invalidVersionOrBuildValue, value.debugDescription) {
                try HelpCatalogProvenancedValue(value: value, source: .callerProvided)
            }
        }

        let combiningAfterVisible = try HelpCatalogProvenancedValue(
            value: "e\u{0301}",
            source: .releaseManifest
        )
        XCTAssertEqual(combiningAfterVisible.value, "e\u{0301}")
        XCTAssertEqual(
            try HelpCatalogProvenancedValue(
                value: "\u{0301}",
                source: .callerProvided
            ).value,
            "\u{0301}"
        )
    }

    func testTrustedHostLinksRejectAuthorityAndDecodingConfusion() throws {
        let policy = try HelpCatalogTrustPolicy(
            trustedExternalHosts: ["Docs.Example.COM", "mail.example"]
        )
        let web = try HelpCatalogLink.secureWeb(
            "https://DOCS.EXAMPLE.COM/guides?q=one-two",
            labelLocalizationKey: "links.documentation",
            trustPolicy: policy
        )
        let email = try HelpCatalogLink.email(
            "person+help@mail.example",
            trustPolicy: policy
        )

        XCTAssertEqual(web.scheme, .https)
        XCTAssertEqual(web.target, "https://DOCS.EXAMPLE.COM/guides?q=one-two")
        XCTAssertNil(web.resolvedBundledResourceURL)
        XCTAssertEqual(email.scheme, .mailto)
        XCTAssertEqual(email.target, "person+help@mail.example")

        for target in [
            "http://docs.example.com",
            "https://sub.docs.example.com",
            "https://user@docs.example.com",
            "https://docs.example.com:443",
            "https://docs.example.com/%",
            "https://docs.example.com/%2",
            "https://docs.example.com/%GG",
            "https://docs.example.com/%00",
            "https://docs.example.com/%0A",
            "https://docs.example.com/%0D%0AHost:%20evil.example",
            "https://docs.example.com/%20",
            "https://docs.example.com/%E2%80%8B",
            "https://docs.example.com/%E2%80%AE",
            "https://docs.example.com%40evil.example/",
            "HTTPS://docs.example.com",
            "https://docs.example.com\\@evil.example"
        ] {
            assertHelpCatalogError(.invalidLinkTarget(scheme: .https), target) {
                try HelpCatalogLink.secureWeb(target, trustPolicy: policy)
            }
        }
        for address in [
            "person@other.example",
            ".person@mail.example",
            "person..help@mail.example",
            "person@mail.example?subject=help",
            "person@@mail.example",
            "pérson@mail.example"
        ] {
            assertHelpCatalogError(.invalidLinkTarget(scheme: .mailto), address) {
                try HelpCatalogLink.email(address, trustPolicy: policy)
            }
        }
        assertHelpCatalogError(.invalidLinkTarget(scheme: .https)) {
            try HelpCatalogLink.secureWeb(
                "https://docs.example.com",
                trustPolicy: .denyAll
            )
        }
        assertHelpCatalogError(.invalidLinkFragment) {
            try HelpCatalogLink(
                scheme: .https,
                target: "https://docs.example.com",
                fragment: "section",
                trustPolicy: policy
            )
        }
        for host in ["", "-bad.example", "bad-.example", "bad..example", "https://example.com"] {
            assertHelpCatalogError(.invalidTrustedExternalHost(host), host) {
                try HelpCatalogTrustPolicy(trustedExternalHosts: [host])
            }
        }
    }

    func testBundledResourceOpenIsReadOnlyBlockingAndCloseOnExec() throws {
        let root = try makeTemporaryDirectory()
        let guideDirectory = root.appending(path: "Guides", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: guideDirectory,
            withIntermediateDirectories: false
        )
        let resourceURL = guideDirectory.appending(path: "Help.txt")
        let expected = Data("trusted help".utf8)
        try expected.write(to: resourceURL)
        let policy = try bundlePolicy(root: root)
        let link = try HelpCatalogLink.bundledResource(
            path: "Guides/Help.txt",
            fragment: "overview",
            labelLocalizationKey: "links.help",
            trustPolicy: policy
        )

        XCTAssertEqual(link.resolvedBundledResourceURL, resourceURL.standardizedFileURL)
        let handle = try link.openBundledResource()
        defer { try? handle.close() }
        XCTAssertEqual(try handle.readToEnd(), expected)
        let descriptorFlags = Darwin.fcntl(handle.fileDescriptor, F_GETFD)
        XCTAssertGreaterThanOrEqual(descriptorFlags, 0)
        XCTAssertNotEqual(descriptorFlags & FD_CLOEXEC, 0)
        let statusFlags = Darwin.fcntl(handle.fileDescriptor, F_GETFL)
        XCTAssertGreaterThanOrEqual(statusFlags, 0)
        XCTAssertEqual(statusFlags & O_ACCMODE, O_RDONLY)
        XCTAssertEqual(statusFlags & O_NONBLOCK, 0)

        assertHelpCatalogError(.invalidLinkTarget(scheme: .helpBook)) {
            try HelpCatalogLink.helpBook(anchor: "overview").openBundledResource()
        }
        for path in [
            "",
            "/absolute.txt",
            "../outside.txt",
            "Guides/../Help.txt",
            "Guides//Help.txt",
            "Guides\\Help.txt",
            "Guides/%48elp.txt",
            "Guides/Help.txt?query",
            "Guides/Help.txt#fragment"
        ] {
            assertHelpCatalogError(.invalidLinkTarget(scheme: .bundledResource), path) {
                try HelpCatalogLink.bundledResource(
                    path: path,
                    trustPolicy: policy
                )
            }
        }
    }

    func testBundlePolicyRejectsInvalidRootsAndResolverEscapes() throws {
        let parent = try makeTemporaryDirectory()
        let root = parent.appending(path: "Bundle", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let inside = root.appending(path: "inside.txt")
        let outside = parent.appending(path: "outside.txt")
        try Data("inside".utf8).write(to: inside)
        try Data("outside".utf8).write(to: outside)

        assertHelpCatalogError(.invalidResolvedBundleRoot) {
            try HelpCatalogTrustPolicy(resolvedBundleRoot: root)
        }
        assertHelpCatalogError(.invalidResolvedBundleRoot) {
            try HelpCatalogTrustPolicy(bundledResourceResolver: { _ in nil })
        }
        assertHelpCatalogError(.invalidResolvedBundleRoot) {
            try HelpCatalogTrustPolicy(
                resolvedBundleRoot: URL(string: "file:relative")!,
                bundledResourceResolver: { _ in nil }
            )
        }
        assertHelpCatalogError(.invalidResolvedBundleRoot) {
            try HelpCatalogTrustPolicy(
                resolvedBundleRoot: inside,
                bundledResourceResolver: { _ in inside }
            )
        }

        let outsidePolicy = try HelpCatalogTrustPolicy(
            resolvedBundleRoot: root,
            bundledResourceResolver: { _ in outside }
        )
        assertHelpCatalogError(.bundledResourceResolutionFailed("inside.txt")) {
            try HelpCatalogLink.bundledResource(
                path: "inside.txt",
                trustPolicy: outsidePolicy
            )
        }
        let rootPolicy = try HelpCatalogTrustPolicy(
            resolvedBundleRoot: root,
            bundledResourceResolver: { _ in root }
        )
        assertHelpCatalogError(.bundledResourceResolutionFailed("inside.txt")) {
            try HelpCatalogLink.bundledResource(
                path: "inside.txt",
                trustPolicy: rootPolicy
            )
        }
    }

    func testBundlePolicyRejectsSymlinkRoot() throws {
        let parent = try makeTemporaryDirectory()
        let root = parent.appending(path: "Bundle", directoryHint: .isDirectory)
        let rootLink = parent.appending(path: "BundleLink")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: root)
        } catch {
            throw XCTSkip("Temporary filesystem does not support symbolic links: \(error)")
        }

        assertHelpCatalogError(.invalidResolvedBundleRoot) {
            try HelpCatalogTrustPolicy(
                resolvedBundleRoot: rootLink,
                bundledResourceResolver: { path in rootLink.appending(path: path) }
            )
        }
    }

    func testBundledResourceUsesPinnedRootWhenLinkIsCreatedAfterPathReplacement() throws {
        let parent = try makeTemporaryDirectory()
        let root = parent.appending(path: "Bundle", directoryHint: .isDirectory)
        let relocatedRoot = parent.appending(path: "Relocated", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let resource = root.appending(path: "help.txt")
        try Data("trusted".utf8).write(to: resource)
        let policy = try bundlePolicy(root: root)

        try FileManager.default.moveItem(at: root, to: relocatedRoot)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: root.appending(path: "help.txt"))
        let link = try HelpCatalogLink.bundledResource(
            path: "help.txt",
            trustPolicy: policy
        )

        let handle = try link.openBundledResource()
        defer { try? handle.close() }
        XCTAssertEqual(try handle.readToEnd(), Data("trusted".utf8))
        XCTAssertEqual(
            try Data(contentsOf: relocatedRoot.appending(path: "help.txt")),
            Data("trusted".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: root.appending(path: "help.txt")),
            Data("replacement".utf8)
        )
    }

    func testBundledResourceRejectsAncestorSymlink() throws {
        let root = try makeTemporaryDirectory()
        let ancestor = root.appending(path: "Ancestor", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ancestor, withIntermediateDirectories: false)
        let ancestorResource = ancestor.appending(path: "help.txt")
        try Data("ancestor".utf8).write(to: ancestorResource)
        let policy = try bundlePolicy(root: root)
        let ancestorLink = try HelpCatalogLink.bundledResource(
            path: "Ancestor/help.txt",
            trustPolicy: policy
        )
        let movedAncestor = root.appending(path: "MovedAncestor", directoryHint: .isDirectory)
        do {
            try FileManager.default.moveItem(at: ancestor, to: movedAncestor)
            try FileManager.default.createSymbolicLink(
                at: ancestor,
                withDestinationURL: movedAncestor
            )
        } catch {
            throw XCTSkip("Temporary filesystem does not support ancestor symlinks: \(error)")
        }
        assertHelpCatalogError(.bundledResourceResolutionFailed("Ancestor/help.txt")) {
            try ancestorLink.openBundledResource()
        }
    }

    func testBundledResourceRejectsFinalSymlink() throws {
        let root = try makeTemporaryDirectory()
        let finalResource = root.appending(path: "final.txt")
        try Data("final".utf8).write(to: finalResource)
        let finalLink = try HelpCatalogLink.bundledResource(
            path: "final.txt",
            trustPolicy: try bundlePolicy(root: root)
        )
        let movedFinal = root.appending(path: "moved-final.txt")
        do {
            try FileManager.default.moveItem(at: finalResource, to: movedFinal)
            try FileManager.default.createSymbolicLink(
                at: finalResource,
                withDestinationURL: movedFinal
            )
        } catch {
            throw XCTSkip("Temporary filesystem does not support final symlinks: \(error)")
        }

        assertHelpCatalogError(.bundledResourceResolutionFailed("final.txt")) {
            try finalLink.openBundledResource()
        }
    }

    func testBundledResourceRejectsNonSymlinkIdentityReplacement() throws {
        let root = try makeTemporaryDirectory()
        let resource = root.appending(path: "help.txt")
        try Data("original".utf8).write(to: resource)
        let link = try HelpCatalogLink.bundledResource(
            path: "help.txt",
            trustPolicy: try bundlePolicy(root: root)
        )

        let replacement = root.appending(path: "replacement.txt")
        try Data("replacement".utf8).write(to: replacement)
        let replacementResult = replacement.path.withCString { replacementPath in
            resource.path.withCString { resourcePath in
                Darwin.rename(replacementPath, resourcePath)
            }
        }
        guard replacementResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        assertHelpCatalogError(.bundledResourceResolutionFailed("help.txt")) {
            try link.openBundledResource()
        }
    }

    func testBundledResourceRejectsAtomicAncestorSwapsWithoutHanging() throws {
        if let childRoot = ProcessInfo.processInfo.environment[
            Self.ancestorSwapChildRootEnvironment
        ] {
            try runAncestorSwapChild(root: URL(filePath: childRoot, directoryHint: .isDirectory))
            return
        }

        let root = try makeTemporaryDirectory()
        let ancestor = root.appending(path: "Ancestor", directoryHint: .isDirectory)
        let alternate = root.appending(path: "Alternate", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ancestor, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: false)
        try Data("trusted".utf8).write(to: ancestor.appending(path: "help.txt"))
        try Data("untrusted".utf8).write(to: alternate.appending(path: "help.txt"))
        guard exchangeItems(ancestor, alternate) == 0 else {
            throw XCTSkip("Temporary filesystem does not support atomic directory swaps: errno \(errno)")
        }
        guard exchangeItems(ancestor, alternate) == 0 else {
            return XCTFail("Temporary filesystem could not restore atomic directory swap: errno \(errno)")
        }

        try assertTestPassesInBoundedSubprocess(
            "MacMergeCoreTests.HelpCatalogTests/testBundledResourceRejectsAtomicAncestorSwapsWithoutHanging",
            environment: [Self.ancestorSwapChildRootEnvironment: root.path],
            timeout: .seconds(10)
        )
    }

    func testBundledResourceFIFOIsRejectedWithoutBlocking() throws {
        if let childRoot = ProcessInfo.processInfo.environment[Self.fifoChildRootEnvironment] {
            let root = URL(filePath: childRoot, directoryHint: .isDirectory)
            assertHelpCatalogError(.bundledResourceResolutionFailed("help.fifo")) {
                try HelpCatalogLink.bundledResource(
                    path: "help.fifo",
                    trustPolicy: try bundlePolicy(root: root)
                )
            }
            return
        }

        let root = try makeTemporaryDirectory()
        let fifo = root.appending(path: "help.fifo")
        let result = fifo.path.withCString { Darwin.mkfifo($0, 0o600) }
        guard result == 0 else {
            throw XCTSkip("Temporary filesystem does not support FIFOs: errno \(errno)")
        }
        try assertTestPassesInBoundedSubprocess(
            "MacMergeCoreTests.HelpCatalogTests/testBundledResourceFIFOIsRejectedWithoutBlocking",
            environment: [Self.fifoChildRootEnvironment: root.path]
        )
    }

    func testBundledResourceEqualityAndHashIncludeResolverProvenance() throws {
        let root = try makeTemporaryDirectory()
        let resource = root.appending(path: "help.txt")
        try Data("help".utf8).write(to: resource)
        let firstPolicy = try bundlePolicy(root: root)
        let secondPolicy = try bundlePolicy(root: root)
        let first = try HelpCatalogLink.bundledResource(
            path: "help.txt",
            trustPolicy: firstPolicy
        )
        let samePolicy = try HelpCatalogLink.bundledResource(
            path: "help.txt",
            trustPolicy: firstPolicy
        )
        let differentPolicy = try HelpCatalogLink.bundledResource(
            path: "help.txt",
            trustPolicy: secondPolicy
        )

        XCTAssertEqual(first, samePolicy)
        XCTAssertEqual(Set([first, samePolicy]).count, 1)
        XCTAssertNotEqual(first, differentPolicy)
        XCTAssertEqual(Set([first, differentPolicy]).count, 2)

        let firstDirectory = root.appending(path: "First", directoryHint: .isDirectory)
        let secondDirectory = root.appending(path: "Second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: firstDirectory,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: secondDirectory,
            withIntermediateDirectories: false
        )
        let firstResource = firstDirectory.appending(path: "logical.txt")
        let secondResource = secondDirectory.appending(path: "logical.txt")
        try Data("first".utf8).write(to: firstResource)
        try Data("second".utf8).write(to: secondResource)
        let selection = HelpCatalogResourceSelection(firstResource)
        let selectingPolicy = try HelpCatalogTrustPolicy(
            resolvedBundleRoot: root,
            bundledResourceResolver: { _ in selection.url }
        )
        let selectedFirst = try HelpCatalogLink.bundledResource(
            path: "logical.txt",
            trustPolicy: selectingPolicy
        )
        selection.url = secondResource
        let selectedSecond = try HelpCatalogLink.bundledResource(
            path: "logical.txt",
            trustPolicy: selectingPolicy
        )
        XCTAssertNotEqual(selectedFirst, selectedSecond)
        XCTAssertEqual(Set([selectedFirst, selectedSecond]).count, 2)

        let catalog = try HelpCatalog(
            topics: [try makeTopic(id: "resource", links: [first])]
        )
        let data = try catalog.manifestData()
        XCTAssertEqual(
            try HelpCatalog.decodeManifest(from: data, trustPolicy: firstPolicy),
            catalog
        )
        XCTAssertNotEqual(
            try HelpCatalog.decodeManifest(from: data, trustPolicy: secondPolicy),
            catalog
        )

        let hostPolicy = try HelpCatalogTrustPolicy(trustedExternalHosts: ["example.com"])
        let otherHostPolicy = try HelpCatalogTrustPolicy(trustedExternalHosts: ["example.com"])
        XCTAssertEqual(
            try HelpCatalogLink.secureWeb("https://example.com", trustPolicy: hostPolicy),
            try HelpCatalogLink.secureWeb("https://example.com", trustPolicy: otherHostPolicy)
        )
    }

    func testProvenanceDistinctSameWireLinksCollideButDistinctWireLinksRoundTrip() throws {
        let root = try makeTemporaryDirectory()
        try Data("first".utf8).write(to: root.appending(path: "first.txt"))
        try Data("second".utf8).write(to: root.appending(path: "second.txt"))
        let firstPolicy = try bundlePolicy(root: root)
        let secondPolicy = try bundlePolicy(root: root)
        let first = try HelpCatalogLink.bundledResource(
            path: "first.txt",
            trustPolicy: firstPolicy
        )
        let sameWireDifferentProvenance = try HelpCatalogLink.bundledResource(
            path: "first.txt",
            trustPolicy: secondPolicy
        )

        XCTAssertNotEqual(first, sameWireDifferentProvenance)
        XCTAssertEqual(
            try HelpCatalog(topics: [try makeTopic(id: "resource", links: [first])])
                .manifestData(),
            try HelpCatalog(
                topics: [
                    try makeTopic(id: "resource", links: [sameWireDifferentProvenance])
                ]
            ).manifestData()
        )
        assertHelpCatalogError(.duplicateValue(field: "topic.links")) {
            try makeTopic(
                id: "collision",
                links: [first, sameWireDifferentProvenance]
            )
        }

        let differentWire = try HelpCatalogLink.bundledResource(
            path: "second.txt",
            trustPolicy: firstPolicy
        )
        let catalog = try HelpCatalog(
            topics: [try makeTopic(id: "resources", links: [first, differentWire])]
        )
        let data = try catalog.manifestData()

        XCTAssertEqual(
            try HelpCatalog.decodeManifest(from: data, trustPolicy: firstPolicy),
            catalog
        )
    }

    func testSearchScoresExactPrefixAndContainmentAndUsesStableSourceOrder() throws {
        let contains = try makeTopic(id: "contains-topic", titleLocalizationKey: "search.contains")
        let exactSecond = try makeTopic(id: "exact-second", titleLocalizationKey: "search.exact-second")
        let prefix = try makeTopic(id: "prefix-topic", titleLocalizationKey: "search.prefix")
        let exactFirst = try makeTopic(id: "exact-first", titleLocalizationKey: "search.exact-first")
        let catalog = try HelpCatalog(topics: [contains, exactSecond, prefix, exactFirst])
        let localizedValues = [
            "search.contains": "xneedlex",
            "search.exact-second": "needle",
            "search.prefix": "needles",
            "search.exact-first": "needle"
        ]

        let results = try catalog.search(
            "needle",
            locale: Locale(identifier: "en_US"),
            localizedValues: localizedValues
        )
        XCTAssertEqual(
            results.map(\.topic.id),
            ["exact-second", "exact-first", "prefix-topic", "contains-topic"]
        )
        XCTAssertEqual(results.map(\.score), [8, 8, 4, 2])
        XCTAssertTrue(results.allSatisfy { $0.matchedTokens == ["needle"] })
        XCTAssertEqual(
            try catalog.search(
                "needle",
                locale: Locale(identifier: "en_US"),
                localizedValues: localizedValues,
                limits: searchLimits(maximumResults: 2)
            ).map(\.topic.id),
            ["exact-second", "exact-first"]
        )
        XCTAssertEqual(
            try catalog.search(
                "needle absent",
                locale: Locale(identifier: "en_US"),
                localizedValues: localizedValues
            ),
            []
        )
    }

    func testSearchRepeatedQueryTokensRequireDistinctDocumentOccurrences() throws {
        let topic = try makeTopic(id: "repeated", titleLocalizationKey: "search.repeated")
        let catalog = try HelpCatalog(topics: [topic])
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(
            try catalog.search(
                "needle needle",
                locale: locale,
                localizedValues: ["search.repeated": "needle"]
            ),
            []
        )
        XCTAssertEqual(
            try catalog.search(
                "needle needle",
                locale: locale,
                localizedValues: ["search.repeated": "needle needle"]
            ),
            [
                HelpCatalogSearchResult(
                    topic: topic,
                    score: 16,
                    matchedTokens: ["needle", "needle"]
                )
            ]
        )
    }

    func testSearchSeparatesPOSIXStructureFromTurkishLocalizedFolding() throws {
        let structural = try makeTopic(
            id: "file-command",
            titleLocalizationKey: "search.structural"
        )
        let localized = try makeTopic(
            id: "turkish-topic",
            titleLocalizationKey: "search.turkish"
        )
        let catalog = try HelpCatalog(topics: [structural, localized])
        let turkish = Locale(identifier: "tr_TR")

        XCTAssertEqual(
            try catalog.search("FILE", locale: turkish),
            [
                HelpCatalogSearchResult(
                    topic: structural,
                    score: 8,
                    matchedTokens: ["fıle"]
                )
            ]
        )

        let localizedValues = ["search.turkish": "ISPARTA"]
        XCTAssertEqual(
            try catalog.search(
                "ısparta",
                locale: turkish,
                localizedValues: localizedValues
            ),
            [
                HelpCatalogSearchResult(
                    topic: localized,
                    score: 8,
                    matchedTokens: ["ısparta"]
                )
            ]
        )
        XCTAssertEqual(
            try catalog.search(
                "İSPARTA",
                locale: turkish,
                localizedValues: localizedValues
            ),
            [
                HelpCatalogSearchResult(
                    topic: localized,
                    score: 8,
                    matchedTokens: ["ısparta"]
                )
            ]
        )
        XCTAssertEqual(
            try catalog.search(
                "isparta",
                locale: turkish,
                localizedValues: localizedValues
            ),
            []
        )
    }

    func testSearchRetainsHebrewAndArabicMarksInTokens() throws {
        let hebrew = try makeTopic(
            id: "hebrew-topic",
            titleLocalizationKey: "search.hebrew"
        )
        let arabic = try makeTopic(
            id: "arabic-topic",
            titleLocalizationKey: "search.arabic"
        )
        let catalog = try HelpCatalog(topics: [hebrew, arabic])
        let localizedValues = [
            "search.hebrew": "שָׁלוֹם",
            "search.arabic": "سَلَام"
        ]

        XCTAssertEqual(
            try catalog.search(
                "שָׁלוֹם",
                locale: Locale(identifier: "he_IL"),
                localizedValues: localizedValues
            ),
            [
                HelpCatalogSearchResult(
                    topic: hebrew,
                    score: 8,
                    matchedTokens: ["שָׁלוֹם"]
                )
            ]
        )
        XCTAssertEqual(
            try catalog.search(
                "سَلَام",
                locale: Locale(identifier: "ar"),
                localizedValues: localizedValues
            ),
            [
                HelpCatalogSearchResult(
                    topic: arabic,
                    score: 8,
                    matchedTokens: ["سَلَام"]
                )
            ]
        )
        XCTAssertEqual(
            try catalog.search(
                "שלום",
                locale: Locale(identifier: "he_IL"),
                localizedValues: localizedValues
            ),
            []
        )
        XCTAssertEqual(
            try catalog.search(
                "سلام",
                locale: Locale(identifier: "ar"),
                localizedValues: localizedValues
            ),
            []
        )
    }

    func testSearchStripsDefaultIgnorablesForVisibleEquivalence() throws {
        let topic = try makeTopic(
            id: "localized-topic",
            titleLocalizationKey: "search.localized"
        )
        let catalog = try HelpCatalog(topics: [topic])
        let locale = Locale(identifier: "en_US")

        for scalar in ["\u{200B}", "\u{2060}", "\u{FEFF}"] {
            let localizedValues = ["search.localized": "alpha\(scalar)beta"]
            XCTAssertEqual(
                try catalog.search(
                    "alpha beta",
                    locale: locale,
                    localizedValues: localizedValues
                ),
                [],
                "scalar=\(scalar.debugDescription)"
            )
            let expected = [
                HelpCatalogSearchResult(
                    topic: topic,
                    score: 8,
                    matchedTokens: ["alphabeta"]
                )
            ]
            XCTAssertEqual(
                try catalog.search(
                    "alpha\(scalar)beta",
                    locale: locale,
                    localizedValues: localizedValues
                ),
                expected,
                "scalar=\(scalar.debugDescription)"
            )
            XCTAssertEqual(
                try catalog.search(
                    "alphabeta",
                    locale: locale,
                    localizedValues: localizedValues
                ),
                expected,
                "scalar=\(scalar.debugDescription)"
            )
        }
    }

    func testSearchWorkBoundaryAndInputLimitsAreExact() throws {
        let catalog = try HelpCatalog(
            topics: [try makeTopic(id: "needle", titleLocalizationKey: "title.key")]
        )
        let exact = try catalog.search(
            "needle",
            locale: Locale(identifier: "en_US"),
            limits: searchLimits(maximumWorkUnits: 82)
        )
        XCTAssertEqual(exact.map(\.topic.id), ["needle"])
        XCTAssertEqual(exact.map(\.score), [8])
        assertHelpCatalogError(.searchWorkLimitExceeded(maximum: 81)) {
            try catalog.search(
                "needle",
                locale: Locale(identifier: "en_US"),
                limits: searchLimits(maximumWorkUnits: 81)
            )
        }
        assertHelpCatalogError(.queryTooLarge(maximumUTF8Bytes: 5)) {
            try catalog.search(
                "needle",
                locale: Locale(identifier: "en_US"),
                limits: searchLimits(maximumQueryUTF8Bytes: 5)
            )
        }
        assertHelpCatalogError(.tooManyQueryTokens(maximum: 1)) {
            try catalog.search(
                "one two",
                locale: Locale(identifier: "en_US"),
                limits: searchLimits(maximumQueryTokens: 1)
            )
        }
        assertHelpCatalogError(.tooManyDocumentTokens(maximum: 1)) {
            try catalog.search(
                "needle",
                locale: Locale(identifier: "en_US"),
                limits: searchLimits(maximumDocumentTokens: 1)
            )
        }
        assertHelpCatalogError(.searchTokenTooLarge(maximumUTF8Bytes: 5)) {
            try catalog.search(
                "needle",
                locale: Locale(identifier: "en_US"),
                limits: searchLimits(maximumTokenUTF8Bytes: 5)
            )
        }
        assertHelpCatalogError(.tooManyLocalizedValues(maximum: 0)) {
            try catalog.search(
                "needle",
                locale: Locale(identifier: "en_US"),
                localizedValues: ["title.key": "needle"],
                limits: searchLimits(maximumLocalizedValues: 0)
            )
        }
        assertHelpCatalogError(.localizedValuesTooLarge(maximumUTF8Bytes: 5)) {
            try catalog.search(
                "needle",
                locale: Locale(identifier: "en_US"),
                localizedValues: ["title.key": "needle"],
                limits: searchLimits(maximumLocalizedValueUTF8Bytes: 5)
            )
        }
        assertHelpCatalogError(.invalidLimit(name: "maximumResults", value: -1)) {
            try catalog.search(
                "needle",
                locale: Locale(identifier: "en_US"),
                limits: searchLimits(maximumResults: -1)
            )
        }
    }

    func testManifestSchemaRejectsVersionsDuplicatesAndUnknownKeysAtExactPaths() throws {
        let base = minimalManifest()
        XCTAssertEqual(try HelpCatalog.decodeManifest(from: Data(base.utf8)), .empty)

        for version in [0, 2, -1] {
            let json = base.replacingOccurrences(
                of: #""manifestVersion":1"#,
                with: #""manifestVersion":\#(version)"#
            )
            assertHelpCatalogError(.unsupportedManifestVersion(version), "version=\(version)") {
                try HelpCatalog.decodeManifest(from: Data(json.utf8))
            }
        }

        for futureSchema in [
            #"{"futurePayload":{"newField":true},"manifestVersion":2}"#,
            #"{"manifestVersion":2,"topics":"future-shape"}"#
        ] {
            assertHelpCatalogError(.unsupportedManifestVersion(2), futureSchema) {
                try HelpCatalog.decodeManifest(from: Data(futureSchema.utf8))
            }
        }

        let duplicateRoot = base.replacingOccurrences(
            of: #""manifestVersion":1"#,
            with: #""manifestVersion":1,"\u006DanifestVersion":1"#
        )
        assertHelpCatalogError(.duplicateJSONKey("manifestVersion")) {
            try HelpCatalog.decodeManifest(from: Data(duplicateRoot.utf8))
        }

        let duplicateNested = manifest(
            topics: "[\(topicJSON(id: "topic", additionalFields: ",\"\\u0069d\":\"other\""))]"
        )
        assertHelpCatalogError(.duplicateJSONKey("id")) {
            try HelpCatalog.decodeManifest(from: Data(duplicateNested.utf8))
        }

        let unknownRoot = base.dropLast() + ",\"zeta\":0,\"alpha\":0}"
        assertHelpCatalogError(.unknownManifestKey(path: "$", key: "alpha")) {
            try HelpCatalog.decodeManifest(from: Data(unknownRoot.utf8))
        }

        let unknownTopic = manifest(
            topics: "[\(topicJSON(id: "topic", additionalFields: ",\"surprise\":true"))]"
        )
        assertHelpCatalogError(.unknownManifestKey(path: "$.topics[0]", key: "surprise")) {
            try HelpCatalog.decodeManifest(from: Data(unknownTopic.utf8))
        }

        let context = #"{"identifier":"open","kind":"command","unexpected":0}"#
        let unknownContext = manifest(
            topics: "[\(topicJSON(id: "topic", kind: "command", contexts: "[\(context)]"))]"
        )
        assertHelpCatalogError(
            .unknownManifestKey(
                path: "$.topics[0].contexts[0]",
                key: "unexpected"
            )
        ) {
            try HelpCatalog.decodeManifest(from: Data(unknownContext.utf8))
        }

        let sourceInjection = manifest(
            about: #"{"creditIDs":[],"links":[],"version":{"source":"callerProvided","value":"1"}}"#
        )
        assertHelpCatalogError(
            .unknownManifestKey(path: "$.about.version", key: "source")
        ) {
            try HelpCatalog.decodeManifest(
                from: Data(sourceInjection.utf8),
                provenance: HelpCatalogManifestProvenance(versionSource: .callerProvided)
            )
        }
    }

    func testManifestScannerAppliesAggregateLimitsOnlyAtSchemaPaths() throws {
        let topicWithLink = topicJSON(
            id: "topic",
            links: #"[{"scheme":"helpBook","target":"topic-anchor"}]"#
        )
        let creditWithLink = creditJSON(
            id: "person",
            links: #"[{"scheme":"helpBook","target":"credit-anchor"}]"#
        )
        let twoLinks = manifest(
            topics: "[\(topicWithLink)]",
            credits: "[\(creditWithLink)]"
        )
        assertHelpCatalogError(.tooManyLinks(maximum: 1)) {
            try HelpCatalog.decodeManifest(
                from: Data(twoLinks.utf8),
                limits: catalogLimits(maximumLinks: 1)
            )
        }

        let topicWithRelationships = topicJSON(
            id: "topic",
            relatedTopicIDs: #"["other"]"#,
            creditIDs: #"["person"]"#
        )
        let twoRelationships = manifest(topics: "[\(topicWithRelationships)]")
        assertHelpCatalogError(.tooManyRelationships(maximum: 1)) {
            try HelpCatalog.decodeManifest(
                from: Data(twoRelationships.utf8),
                limits: catalogLimits(maximumRelationships: 1)
            )
        }

        let unknownPayload =
            minimalManifest().dropLast()
            + ",\"payload\":{\"links\":[{},{}],\"topics\":[{},{}]}}"
        assertHelpCatalogError(.unknownManifestKey(path: "$", key: "payload")) {
            try HelpCatalog.decodeManifest(
                from: Data(unknownPayload.utf8),
                limits: catalogLimits(maximumTopics: 0, maximumLinks: 0)
            )
        }

        let seventeenValues = (0..<17).map(String.init).joined(separator: ",")
        let oversizedUnknownContainer =
            minimalManifest().dropLast()
            + ",\"payload\":[\(seventeenValues)]}"
        assertHelpCatalogError(.jsonContainerTooLarge(maximumElements: 16)) {
            try HelpCatalog.decodeManifest(
                from: Data(oversizedUnknownContainer.utf8),
                limits: catalogLimits(
                    maximumTopics: 0,
                    maximumCredits: 0,
                    maximumContexts: 0,
                    maximumLinks: 0,
                    maximumRelationships: 0,
                    maximumLocalizationKeys: 0
                )
            )
        }
        assertHelpCatalogError(.jsonValueLimitExceeded(maximum: 1)) {
            try HelpCatalog.decodeManifest(
                from: Data(minimalManifest().utf8),
                limits: catalogLimits(maximumJSONValues: 1)
            )
        }
    }

    func testManifestScannerRejectsDepthKeyStringAndNumberBounds() throws {
        let longKey = String(repeating: "k", count: 129)
        let longKeyManifest = minimalManifest().dropLast() + ",\"\(longKey)\":0}"
        assertHelpCatalogError(.jsonKeyTooLarge(maximumUTF8Bytes: 128)) {
            try HelpCatalog.decodeManifest(from: Data(longKeyManifest.utf8))
        }

        let longString = String(repeating: "x", count: 64 * 1_024 + 1)
        let longStringManifest = minimalManifest().dropLast() + ",\"payload\":\"\(longString)\"}"
        assertHelpCatalogError(.jsonStringTooLarge(maximumUTF8Bytes: 64 * 1_024)) {
            try HelpCatalog.decodeManifest(from: Data(longStringManifest.utf8))
        }

        let longNumber = String(repeating: "1", count: 65)
        let longNumberManifest = minimalManifest().replacingOccurrences(
            of: #""manifestVersion":1"#,
            with: "\"manifestVersion\":\(longNumber)"
        )
        assertHelpCatalogError(.jsonNumberTooLarge(maximumBytes: 64)) {
            try HelpCatalog.decodeManifest(from: Data(longNumberManifest.utf8))
        }

        var nested = "0"
        for _ in 0..<17 {
            nested = "{\"nested\":\(nested)}"
        }
        let deepManifest = minimalManifest().dropLast() + ",\"payload\":\(nested)}"
        assertHelpCatalogError(.jsonNestingTooDeep(maximum: 16)) {
            try HelpCatalog.decodeManifest(from: Data(deepManifest.utf8))
        }
    }

    func testPersistenceBoundaryIsSymmetricAtExactlyOneMiB() throws {
        let catalogs = try makePersistenceBoundaryCatalogs()

        let exactData = try catalogs.exact.manifestData()
        XCTAssertEqual(exactData.count, Self.oneMiB)
        XCTAssertEqual(try HelpCatalog.decodeManifest(from: exactData), catalogs.exact)

        assertHelpCatalogError(.manifestDataTooLarge(maximumBytes: Self.oneMiB)) {
            try catalogs.overflow.manifestData()
        }
        var oneByteTooLarge = exactData
        oneByteTooLarge.append(0x20)
        XCTAssertEqual(oneByteTooLarge.count, Self.oneMiB + 1)
        assertHelpCatalogError(.manifestDataTooLarge(maximumBytes: Self.oneMiB)) {
            try HelpCatalog.decodeManifest(from: oneByteTooLarge)
        }
    }

    func testPublicWorkObservesPreexistingCancellation() async throws {
        let root = try makeTemporaryDirectory()
        let resource = root.appending(path: "help.txt")
        try Data("help".utf8).write(to: resource)
        let resourceLink = try HelpCatalogLink.bundledResource(
            path: "help.txt",
            trustPolicy: try bundlePolicy(root: root)
        )
        let topic = try makeTopic(id: "topic")
        let credit = try HelpCatalogCredit(
            id: "person",
            kind: .contributor,
            nameLocalizationKey: "credits.person.name"
        )
        let catalog = try HelpCatalog(topics: [topic], credits: [credit])
        let manifestData = try catalog.manifestData()
        let operations: [(String, @Sendable () throws -> Void)] = [
            (
                "topic init",
                {
                    _ = try HelpCatalogTopic(
                        id: "cancelled",
                        kind: .helpBook,
                        titleLocalizationKey: "cancelled.title"
                    )
                }
            ),
            (
                "credit init",
                {
                    _ = try HelpCatalogCredit(
                        id: "cancelled",
                        kind: .contributor,
                        nameLocalizationKey: "cancelled.name"
                    )
                }
            ),
            ("about init", { _ = try HelpCatalogAboutMetadata() }),
            ("catalog init", { _ = try HelpCatalog(topics: []) }),
            ("topic lookup", { _ = try catalog.lookupTopic(topic.id) }),
            ("credit lookup", { _ = try catalog.lookupCredit(credit.id) }),
            ("kind index", { _ = try catalog.topics(ofKind: .helpBook) }),
            ("relationship index", { _ = try catalog.relatedTopics(to: topic.id) }),
            (
                "navigation",
                { _ = try catalog.topic(adjacentTo: topic.id, direction: .next) }
            ),
            (
                "search",
                { _ = try catalog.search("topic", locale: Locale(identifier: "en_US")) }
            ),
            ("manifest write", { _ = try catalog.manifestData() }),
            ("manifest decode", { _ = try HelpCatalog.decodeManifest(from: manifestData) }),
            (
                "resource open",
                {
                    let handle = try resourceLink.openBundledResource()
                    try handle.close()
                }
            )
        ]

        for (name, operation) in operations {
            let outcome = await Task { () -> String? in
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    try operation()
                    return "completed"
                } catch is CancellationError {
                    return nil
                } catch {
                    return String(describing: error)
                }
            }.value
            XCTAssertNil(outcome, "\(name): \(outcome ?? "")")
        }
    }

    func testPreexistingCancellationHasZeroResolverSideEffects() async throws {
        let root = try makeTemporaryDirectory()
        let resource = root.appending(path: "help.txt")
        try Data("help".utf8).write(to: resource)
        let invocations = HelpCatalogResolverInvocations()
        let policy = try HelpCatalogTrustPolicy(
            resolvedBundleRoot: root,
            bundledResourceResolver: { path in
                invocations.record()
                return root.appending(path: path)
            }
        )
        let resourceTopic = topicJSON(
            id: "resource",
            links: #"[{"scheme":"bundledResource","target":"help.txt"}]"#
        )
        let manifestData = Data(manifest(topics: "[\(resourceTopic)]").utf8)

        let outcome = await Task { () -> String? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try HelpCatalog.decodeManifest(from: manifestData, trustPolicy: policy)
                return "completed"
            } catch is CancellationError {
                return nil
            } catch {
                return String(describing: error)
            }
        }.value

        XCTAssertNil(outcome, outcome ?? "")
        XCTAssertEqual(invocations.count, 0)
    }

    private func makeTopic(
        id: String,
        kind: HelpCatalogTopicKind = .helpBook,
        titleLocalizationKey: String? = nil,
        keywordLocalizationKeys: [String] = [],
        contexts: [HelpCatalogContext] = [],
        links: [HelpCatalogLink] = [],
        relatedTopicIDs: [String] = [],
        creditIDs: [String] = []
    ) throws -> HelpCatalogTopic {
        try HelpCatalogTopic(
            id: id,
            kind: kind,
            titleLocalizationKey: titleLocalizationKey ?? "topics.\(id).title",
            keywordLocalizationKeys: keywordLocalizationKeys,
            contexts: contexts,
            links: links,
            relatedTopicIDs: relatedTopicIDs,
            creditIDs: creditIDs
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let cacheDirectory = try XCTUnwrap(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )
        let requestedDirectory =
            cacheDirectory
            .appending(
                path: "MacMergeHelpCatalogTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: requestedDirectory,
            withIntermediateDirectories: false
        )
        let directory = requestedDirectory.resolvingSymlinksInPath().standardizedFileURL
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func bundlePolicy(root: URL) throws -> HelpCatalogTrustPolicy {
        try HelpCatalogTrustPolicy(
            resolvedBundleRoot: root,
            bundledResourceResolver: { path in root.appending(path: path) }
        )
    }

    private func runAncestorSwapChild(root: URL) throws {
        let ancestor = root.appending(path: "Ancestor", directoryHint: .isDirectory)
        let alternate = root.appending(path: "Alternate", directoryHint: .isDirectory)
        let link = try HelpCatalogLink.bundledResource(
            path: "Ancestor/help.txt",
            trustPolicy: try bundlePolicy(root: root)
        )
        guard exchangeItems(ancestor, alternate) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = exchangeItems(ancestor, alternate) }

        assertHelpCatalogError(.bundledResourceResolutionFailed("Ancestor/help.txt")) {
            try link.openBundledResource()
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
        process.executableURL = URL(filePath: CommandLine.arguments[0])
        process.arguments = ["-XCTest", testName, Bundle(for: Self.self).bundleURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, addition in
            addition
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        defer {
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        guard terminated.wait(timeout: .now() + timeout) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            XCTAssertEqual(
                terminated.wait(timeout: .now() + .seconds(2)),
                .success,
                "Child test did not terminate after SIGKILL",
                file: file,
                line: line
            )
            XCTFail("Child test exceeded bounded timeout", file: file, line: line)
            return
        }
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit, file: file, line: line)
        XCTAssertEqual(process.terminationStatus, 0, file: file, line: line)
    }

    private func assertHelpCatalogError<T>(
        _ expected: HelpCatalogError,
        _ context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), context, file: file, line: line) { error in
            XCTAssertEqual(error as? HelpCatalogError, expected, context, file: file, line: line)
        }
    }

    private func minimalManifest() -> String {
        manifest()
    }

    private func manifest(
        topics: String = "[]",
        credits: String = "[]",
        about: String = #"{"creditIDs":[],"links":[]}"#
    ) -> String {
        "{\"about\":\(about),\"credits\":\(credits),\"manifestVersion\":1,\"topics\":\(topics)}"
    }

    private func topicJSON(
        id: String,
        kind: String = "helpBook",
        contexts: String = "[]",
        links: String = "[]",
        relatedTopicIDs: String = "[]",
        creditIDs: String = "[]",
        additionalFields: String = ""
    ) -> String {
        "{\"contexts\":\(contexts),\"creditIDs\":\(creditIDs),\"id\":\"\(id)\",\"keywordLocalizationKeys\":[],\"kind\":\"\(kind)\",\"links\":\(links),\"relatedTopicIDs\":\(relatedTopicIDs),\"titleLocalizationKey\":\"topics.\(id).title\"\(additionalFields)}"
    }

    private func creditJSON(id: String, links: String = "[]") -> String {
        "{\"id\":\"\(id)\",\"kind\":\"contributor\",\"links\":\(links),\"nameLocalizationKey\":\"credits.\(id).name\"}"
    }

    private func makePersistenceBoundaryCatalogs() throws -> (
        exact: HelpCatalog,
        overflow: HelpCatalog
    ) {
        let baseTopic = try makeTopic(
            id: "boundary",
            titleLocalizationKey: "boundary.title"
        )
        let baseCatalog = try HelpCatalog(topics: [baseTopic])
        let baseCount = try baseCatalog.manifestData().count
        let neededContribution = Self.oneMiB - baseCount
        let minimumKeyCount = (neededContribution + 515) / 515
        let keyCount = minimumKeyCount + 1
        var remainingLength = neededContribution - 3 * keyCount + 1
        let prefixes = (0..<keyCount).map { "k\($0)_" }
        var minimumRemaining = prefixes.reduce(0) { $0 + $1.utf8.count }
        var keys: [String] = []
        keys.reserveCapacity(keyCount)

        for prefix in prefixes {
            minimumRemaining -= prefix.utf8.count
            let length = Swift.min(512, remainingLength - minimumRemaining)
            XCTAssertGreaterThanOrEqual(length, prefix.utf8.count)
            keys.append(prefix + String(repeating: "x", count: length - prefix.utf8.count))
            remainingLength -= length
        }
        XCTAssertEqual(remainingLength, 0)

        let exactTopic = try makeTopic(
            id: "boundary",
            titleLocalizationKey: "boundary.title",
            keywordLocalizationKeys: keys
        )
        let exact = try HelpCatalog(topics: [exactTopic])
        guard let expandableIndex = keys.firstIndex(where: { $0.utf8.count < 512 }) else {
            XCTFail("Boundary construction requires one expandable key")
            throw CocoaError(.coderInvalidValue)
        }
        keys[expandableIndex].append("x")
        let overflowTopic = try makeTopic(
            id: "boundary",
            titleLocalizationKey: "boundary.title",
            keywordLocalizationKeys: keys
        )
        return (exact, try HelpCatalog(topics: [overflowTopic]))
    }

    private func catalogLimits(
        maximumTopics: Int = HelpCatalogLimits.default.maximumTopics,
        maximumCredits: Int = HelpCatalogLimits.default.maximumCredits,
        maximumContexts: Int = HelpCatalogLimits.default.maximumContexts,
        maximumLinks: Int = HelpCatalogLimits.default.maximumLinks,
        maximumRelationships: Int = HelpCatalogLimits.default.maximumRelationships,
        maximumLocalizationKeys: Int = HelpCatalogLimits.default.maximumLocalizationKeys,
        maximumMetadataUTF8Bytes: Int = HelpCatalogLimits.default.maximumMetadataUTF8Bytes,
        maximumManifestBytes: Int = HelpCatalogLimits.default.maximumManifestBytes,
        maximumJSONValues: Int = HelpCatalogLimits.default.maximumJSONValues
    ) -> HelpCatalogLimits {
        HelpCatalogLimits(
            maximumTopics: maximumTopics,
            maximumCredits: maximumCredits,
            maximumContexts: maximumContexts,
            maximumLinks: maximumLinks,
            maximumRelationships: maximumRelationships,
            maximumLocalizationKeys: maximumLocalizationKeys,
            maximumMetadataUTF8Bytes: maximumMetadataUTF8Bytes,
            maximumManifestBytes: maximumManifestBytes,
            maximumJSONValues: maximumJSONValues
        )
    }

    private func searchLimits(
        maximumResults: Int = HelpCatalogSearchLimits.default.maximumResults,
        maximumQueryUTF8Bytes: Int = HelpCatalogSearchLimits.default.maximumQueryUTF8Bytes,
        maximumQueryTokens: Int = HelpCatalogSearchLimits.default.maximumQueryTokens,
        maximumDocumentTokens: Int = HelpCatalogSearchLimits.default.maximumDocumentTokens,
        maximumTokenUTF8Bytes: Int = HelpCatalogSearchLimits.default.maximumTokenUTF8Bytes,
        maximumLocalizedValues: Int = HelpCatalogSearchLimits.default.maximumLocalizedValues,
        maximumLocalizedValueUTF8Bytes: Int = HelpCatalogSearchLimits.default.maximumLocalizedValueUTF8Bytes,
        maximumLocalizedUTF8Bytes: Int = HelpCatalogSearchLimits.default.maximumLocalizedUTF8Bytes,
        maximumWorkUnits: Int = HelpCatalogSearchLimits.default.maximumWorkUnits
    ) -> HelpCatalogSearchLimits {
        HelpCatalogSearchLimits(
            maximumResults: maximumResults,
            maximumQueryUTF8Bytes: maximumQueryUTF8Bytes,
            maximumQueryTokens: maximumQueryTokens,
            maximumDocumentTokens: maximumDocumentTokens,
            maximumTokenUTF8Bytes: maximumTokenUTF8Bytes,
            maximumLocalizedValues: maximumLocalizedValues,
            maximumLocalizedValueUTF8Bytes: maximumLocalizedValueUTF8Bytes,
            maximumLocalizedUTF8Bytes: maximumLocalizedUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits
        )
    }

    private static let ancestorSwapChildRootEnvironment =
        "MACMERGE_HELP_CATALOG_ANCESTOR_SWAP_CHILD_ROOT"
    private static let fifoChildRootEnvironment = "MACMERGE_HELP_CATALOG_FIFO_CHILD_ROOT"
}

private final class HelpCatalogResourceSelection: @unchecked Sendable {
    private let lock = NSLock()
    private var selectedURL: URL

    init(_ url: URL) {
        selectedURL = url
    }

    var url: URL {
        get {
            lock.lock()
            defer { lock.unlock() }
            return selectedURL
        }
        set {
            lock.lock()
            selectedURL = newValue
            lock.unlock()
        }
    }
}

private final class HelpCatalogResolverInvocations: @unchecked Sendable {
    private let lock = NSLock()
    private var invocationCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCount
    }

    func record() {
        lock.lock()
        invocationCount += 1
        lock.unlock()
    }
}

private func exchangeItems(_ first: URL, _ second: URL) -> Int32 {
    first.path.withCString { firstPath in
        second.path.withCString { secondPath in
            Darwin.renameatx_np(
                AT_FDCWD,
                firstPath,
                AT_FDCWD,
                secondPath,
                UInt32(RENAME_SWAP)
            )
        }
    }
}
