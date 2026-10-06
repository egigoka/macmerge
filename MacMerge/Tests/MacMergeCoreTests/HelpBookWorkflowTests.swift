import Foundation
import MacMergeCore
import XCTest

final class HelpBookWorkflowTests: XCTestCase {
    private typealias Catalog = HelpCatalog
    private typealias Planner = HelpBookWorkflowPlanner
    private typealias WorkflowError = HelpBookWorkflowError

    // MARK: - Fixtures

    private func makeTopic(
        id: String,
        kind: Catalog.TopicKind = .helpBook,
        links: [Catalog.Link] = [],
        creditIDs: [String] = []
    ) throws -> Catalog.Topic {
        try Catalog.Topic(
            id: id,
            kind: kind,
            titleLocalizationKey: "topics.\(id).title",
            links: links,
            creditIDs: creditIDs
        )
    }

    private func makeReleaseTopic(id: String) throws -> Catalog.Topic {
        try makeTopic(id: id, kind: .releaseNotes)
    }

    private func makeCatalog(
        topics: [Catalog.Topic] = [],
        credits: [Catalog.Credit] = [],
        about: Catalog.AboutMetadata = .empty
    ) throws -> Catalog {
        try Catalog(topics: topics, credits: credits, about: about)
    }

    private func makeCredit(id: String) throws -> Catalog.Credit {
        try Catalog.Credit(
            id: id,
            kind: .contributor,
            nameLocalizationKey: "credits.\(id).name"
        )
    }

    private func makeRequest(
        catalog: Catalog,
        locales: [String] = [],
        releases: [HelpBookWorkflowReleaseInput] = [],
        trustPolicy: Catalog.TrustPolicy = .denyAll,
        provenance: HelpBookWorkflowProvenance = HelpBookWorkflowProvenance(),
        limits: HelpBookWorkflowLimits = .default,
        searchLimits: Catalog.SearchLimits = .default
    ) -> HelpBookWorkflowRequest {
        HelpBookWorkflowRequest(
            catalog: catalog,
            preferredLocaleIdentifiers: locales,
            releaseInputs: releases,
            trustPolicy: trustPolicy,
            provenance: provenance,
            limits: limits,
            searchLimits: searchLimits
        )
    }

    private func permissivePolicy() throws -> Catalog.TrustPolicy {
        try Catalog.TrustPolicy(trustedExternalHosts: ["example.com"])
    }

    private func happyPathCatalog() throws -> Catalog {
        let anchorLink = try Catalog.Link.helpBook(anchor: "gettingstarted.anchor")
        let main = try makeTopic(id: "gettingstarted", links: [anchorLink])
        let release = try makeReleaseTopic(id: "releasenotes")
        let license = try makeTopic(id: "licenseterms", kind: .license)
        let credit = try makeCredit(id: "ann")
        return try makeCatalog(topics: [main, release, license], credits: [credit])
    }

    private func assertWorkflowError(
        _ expression: @autoclosure () throws -> HelpBookWorkflowPlan,
        equals expected: WorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? WorkflowError, expected, file: file, line: line)
        }
    }

    // MARK: - Expansion planner happy path

    func testEmptyCatalogPlansWithEnglishFallback() throws {
        let catalog = try makeCatalog()
        let plan = try Planner.plan(makeRequest(catalog: catalog))

        XCTAssertEqual(plan.fallbackLocales, ["en"])
        XCTAssertEqual(plan.anchors, [])
        XCTAssertEqual(plan.releases, [])
        XCTAssertEqual(plan.licenseTopicIDs, [])
        XCTAssertEqual(plan.contributorCreditIDs, [])
        XCTAssertEqual(plan.estimate.anchorCount, 0)
        XCTAssertEqual(plan.estimate.releaseNoteCount, 0)
        XCTAssertEqual(plan.estimate.validatedLinkCount, 0)
        XCTAssertEqual(plan.primaryLocale.identifier, "en")
        XCTAssertEqual(plan.orderedReleaseTopicIDs, [])
    }

    func testHappyPathExpansionCountsAndOrdering() throws {
        let catalog = try happyPathCatalog()
        let releases = [HelpBookWorkflowReleaseInput(version: "1.2.0", topicID: "releasenotes")]
        let plan = try Planner.plan(makeRequest(catalog: catalog, locales: ["EN-us"], releases: releases))

        XCTAssertEqual(plan.fallbackLocales, ["en-us", "en"])
        XCTAssertEqual(
            plan.anchors,
            [HelpBookWorkflowAnchorResolution(anchor: "gettingstarted.anchor", topicID: "gettingstarted")]
        )
        XCTAssertEqual(plan.releases.count, 1)
        XCTAssertEqual(plan.releases[0].topicID, "releasenotes")
        XCTAssertEqual(plan.releases[0].version, try HelpBookWorkflowReleaseVersion(parsing: "1.2.0"))
        XCTAssertEqual(plan.licenseTopicIDs, ["licenseterms"])
        XCTAssertEqual(plan.contributorCreditIDs, ["ann"])
        XCTAssertEqual(plan.estimate.anchorCount, 1)
        XCTAssertEqual(plan.estimate.releaseNoteCount, 1)
        XCTAssertEqual(plan.estimate.licenseTopicCount, 1)
        XCTAssertEqual(plan.estimate.contributorCount, 1)
        XCTAssertEqual(plan.estimate.validatedLinkCount, 1)
        XCTAssertGreaterThan(plan.estimate.metadataUTF8ByteCount, 0)
        XCTAssertGreaterThan(plan.estimate.workUnits, 0)
        // Locale canonicalizes the identifier casing for presentation.
        XCTAssertEqual(plan.primaryLocale.identifier, "en-US")
        XCTAssertEqual(plan.orderedReleaseTopicIDs, ["releasenotes"])
    }

    func testTopicLookupByAnchor() throws {
        let catalog = try happyPathCatalog()
        let plan = try Planner.plan(makeRequest(catalog: catalog))

        XCTAssertEqual(try plan.topic(forAnchor: "gettingstarted.anchor").id, "gettingstarted")
        XCTAssertThrowsError(try plan.topic(forAnchor: "missing.anchor")) { error in
            XCTAssertEqual(error as? WorkflowError, .invalidAnchor("missing.anchor"))
        }
    }

    func testLicenseTopicsAndContributorCreditsResolve() throws {
        let catalog = try happyPathCatalog()
        let plan = try Planner.plan(makeRequest(catalog: catalog))

        XCTAssertEqual(try plan.licenseTopics().map(\.id), ["licenseterms"])
        XCTAssertEqual(try plan.contributorCredits().map(\.id), ["ann"])
    }

    func testReleasesSortNumericallyDescending() throws {
        let topics = try [
            makeReleaseTopic(id: "release123"),
            makeReleaseTopic(id: "release1100"),
            makeReleaseTopic(id: "release190")
        ]
        let catalog = try makeCatalog(topics: topics)
        let releases = [
            HelpBookWorkflowReleaseInput(version: "1.2.3", topicID: "release123"),
            HelpBookWorkflowReleaseInput(version: "1.10.0", topicID: "release1100"),
            HelpBookWorkflowReleaseInput(version: "1.9.0", topicID: "release190")
        ]
        let plan = try Planner.plan(makeRequest(catalog: catalog, releases: releases))

        XCTAssertEqual(plan.orderedReleaseTopicIDs, ["release1100", "release190", "release123"])
    }

    func testNumericallyEqualVersionsAreDistinctBindings() throws {
        // Identical version strings are rejected as duplicates, so the
        // topic-ID tie-break only sees numerically equal but textually
        // distinct versions. Both bindings are accepted.
        let catalog = try makeCatalog(topics: [makeReleaseTopic(id: "releasea"), makeReleaseTopic(id: "releaseb")])
        let releases = [
            HelpBookWorkflowReleaseInput(version: "2.0.0", topicID: "releasea"),
            HelpBookWorkflowReleaseInput(version: "02.00.00", topicID: "releaseb")
        ]
        let plan = try Planner.plan(makeRequest(catalog: catalog, releases: releases))

        XCTAssertEqual(plan.releases.count, 2)
        XCTAssertEqual(Set(plan.orderedReleaseTopicIDs), ["releasea", "releaseb"])
    }

    // MARK: - Locale canonicalization and fallback

    func testLocaleCanonicalizationDedupAndDefault() throws {
        let catalog = try makeCatalog()
        let plan = try Planner.plan(makeRequest(catalog: catalog, locales: ["EN-US", " en-us ", "EN-us"]))
        XCTAssertEqual(plan.fallbackLocales, ["en-us", "en"])

        let empty = try Planner.plan(makeRequest(catalog: catalog, locales: []))
        XCTAssertEqual(empty.fallbackLocales, ["en"])
    }

    func testInvalidLocalesThrow() throws {
        let catalog = try makeCatalog()
        for value in ["", "en_US", "-en", "en-", "en--us", String(repeating: "a", count: 36)] {
            assertWorkflowError(
                try Planner.plan(makeRequest(catalog: catalog, locales: [value])),
                equals: .invalidLocale(value)
            )
        }
    }

    func testTooManyLocalesThrows() throws {
        let catalog = try makeCatalog()
        let limits = HelpBookWorkflowLimits(maximumLocales: 1)

        assertWorkflowError(
            try Planner.plan(makeRequest(catalog: catalog, locales: ["fr"], limits: limits)),
            equals: .tooManyLocales(maximum: 1)
        )
    }

    // MARK: - Release versions

    func testDuplicateReleaseVersionThrows() throws {
        let catalog = try makeCatalog(topics: [makeReleaseTopic(id: "releasea"), makeReleaseTopic(id: "releaseb")])
        let releases = [
            HelpBookWorkflowReleaseInput(version: "1.2.3", topicID: "releasea"),
            HelpBookWorkflowReleaseInput(version: "1.2.3", topicID: "releaseb")
        ]

        assertWorkflowError(
            try Planner.plan(makeRequest(catalog: catalog, releases: releases)),
            equals: .duplicateReleaseVersion("1.2.3")
        )
    }

    func testDuplicateReleaseTopicIDThrows() throws {
        let catalog = try makeCatalog(topics: [makeReleaseTopic(id: "releasea")])
        let releases = [
            HelpBookWorkflowReleaseInput(version: "1.2.3", topicID: "releasea"),
            HelpBookWorkflowReleaseInput(version: "1.2.4", topicID: "releasea")
        ]

        assertWorkflowError(
            try Planner.plan(makeRequest(catalog: catalog, releases: releases)),
            equals: .duplicateReleaseVersion("releasea")
        )
    }

    func testBadReleaseTopicBindingsThrow() throws {
        let catalog = try makeCatalog(topics: [makeTopic(id: "plain")])

        assertWorkflowError(
            try Planner.plan(
                makeRequest(
                    catalog: catalog,
                    releases: [HelpBookWorkflowReleaseInput(version: "1.0.0", topicID: "missing")]
                )
            ),
            equals: .unknownReleaseTopic("missing")
        )
        assertWorkflowError(
            try Planner.plan(
                makeRequest(
                    catalog: catalog,
                    releases: [HelpBookWorkflowReleaseInput(version: "1.0.0", topicID: "plain")]
                )
            ),
            equals: .releaseTopicKindMismatch("plain")
        )
    }

    func testInvalidReleaseVersionsThrow() {
        for value in ["", "1.2", "1.2.3.4", "a.b.c", "1..3", "1.2.1000000", "9999999.0.0"] {
            XCTAssertThrowsError(try HelpBookWorkflowReleaseVersion(parsing: value), "version \(value)") { error in
                XCTAssertEqual(error as? WorkflowError, .invalidReleaseVersion(value))
            }
        }
    }

    func testReleaseVersionNumericTupleCompare() throws {
        let low = try HelpBookWorkflowReleaseVersion(parsing: "1.9.0")
        let high = try HelpBookWorkflowReleaseVersion(parsing: "1.10.0")
        XCTAssertLessThan(low, high)

        // Leading zeros compare numerically, but duplicate detection keys on the raw string.
        let padded = try HelpBookWorkflowReleaseVersion(parsing: "01.02.03")
        let canonical = try HelpBookWorkflowReleaseVersion(parsing: "1.2.3")
        XCTAssertFalse(padded < canonical)
        XCTAssertFalse(canonical < padded)
        XCTAssertEqual(padded.original, "01.02.03")

        let catalog = try makeCatalog(topics: [makeReleaseTopic(id: "releasea"), makeReleaseTopic(id: "releaseb")])
        let releases = [
            HelpBookWorkflowReleaseInput(version: "01.02.03", topicID: "releasea"),
            HelpBookWorkflowReleaseInput(version: "1.2.3", topicID: "releaseb")
        ]
        let plan = try Planner.plan(makeRequest(catalog: catalog, releases: releases))
        XCTAssertEqual(plan.orderedReleaseTopicIDs, ["releasea", "releaseb"])
    }

    // MARK: - Trust and staleness

    func testUntrustedLinkRejectedUnderDenyAll() throws {
        let policy = try permissivePolicy()
        let webLink = try Catalog.Link.secureWeb("https://example.com/help", trustPolicy: policy)
        let catalog = try makeCatalog(topics: [makeTopic(id: "webtopic", links: [webLink])])

        assertWorkflowError(
            try Planner.plan(makeRequest(catalog: catalog, trustPolicy: .denyAll)),
            equals: .untrustedLink(topicID: "webtopic", target: "https://example.com/help")
        )
    }

    func testTrustPolicyChangeRequiresReplan() throws {
        let policy = try permissivePolicy()
        let webLink = try Catalog.Link.secureWeb("https://example.com/help", trustPolicy: policy)
        let catalog = try makeCatalog(topics: [makeTopic(id: "webtopic", links: [webLink])])

        // Same snapshot plans cleanly under the trusting policy.
        let plan = try Planner.plan(makeRequest(catalog: catalog, trustPolicy: policy))
        XCTAssertEqual(plan.estimate.validatedLinkCount, 1)

        // Replanning the same snapshot under deny-all rejects the now-untrusted link.
        // Note: validateCurrent/isCurrent do not take a trust policy, so rotation is
        // enforced at plan time, not via snapshot staleness.
        assertWorkflowError(
            try Planner.plan(makeRequest(catalog: catalog, trustPolicy: .denyAll)),
            equals: .untrustedLink(topicID: "webtopic", target: "https://example.com/help")
        )
    }

    func testIsCurrentTrueForIdenticalRebuild() throws {
        let catalog = try happyPathCatalog()
        let releases = [HelpBookWorkflowReleaseInput(version: "1.2.0", topicID: "releasenotes")]
        let plan = try Planner.plan(makeRequest(catalog: catalog, locales: ["en-us"], releases: releases))
        let rebuilt = try happyPathCatalog()

        XCTAssertTrue(try plan.isCurrent(rebuilt, preferredLocaleIdentifiers: ["en-us"], releaseInputs: releases))
        let replanned = try Planner.plan(makeRequest(catalog: rebuilt, locales: ["en-us"], releases: releases))
        XCTAssertEqual(replanned.reference.catalogDigest, plan.reference.catalogDigest)
        XCTAssertEqual(replanned.reference.inputDigest, plan.reference.inputDigest)
        XCTAssertNotEqual(replanned.reference.planID, plan.reference.planID)
    }

    func testCatalogContentChangesInvalidateStalePlan() throws {
        let catalog = try happyPathCatalog()
        let plan = try Planner.plan(makeRequest(catalog: catalog))

        var topics = catalog.topics
        topics.append(try makeTopic(id: "newtopic"))
        let added = try makeCatalog(topics: topics, credits: catalog.credits)

        XCTAssertNotEqual(added.topicIDs, catalog.topicIDs)
        XCTAssertFalse(try plan.isCurrent(added, preferredLocaleIdentifiers: [], releaseInputs: []))
        XCTAssertThrowsError(
            try plan.validateCurrent(added, preferredLocaleIdentifiers: [], releaseInputs: [])
        ) { error in
            XCTAssertEqual(error as? WorkflowError, .snapshotContentsChanged)
        }

        let about = try Catalog.AboutMetadata(
            version: try Catalog.ProvenancedValue(value: "2.0", source: .callerProvided)
        )
        let versioned = try makeCatalog(topics: catalog.topics, credits: catalog.credits, about: about)
        XCTAssertFalse(try plan.isCurrent(versioned, preferredLocaleIdentifiers: [], releaseInputs: []))
    }

    func testLocaleChangeInvalidatesStalePlan() throws {
        let catalog = try happyPathCatalog()
        let plan = try Planner.plan(makeRequest(catalog: catalog, locales: ["fr"]))

        XCTAssertFalse(try plan.isCurrent(catalog, preferredLocaleIdentifiers: ["de"], releaseInputs: []))
    }

    func testReleaseInputsChangeInvalidatesStalePlan() throws {
        let topics = try [makeReleaseTopic(id: "releasea"), makeReleaseTopic(id: "releaseb")]
        let catalog = try makeCatalog(topics: topics)
        let first = [HelpBookWorkflowReleaseInput(version: "1.2.0", topicID: "releasea")]
        let plan = try Planner.plan(makeRequest(catalog: catalog, releases: first))

        // Rebinding to a different topic invalidates the plan.
        let rebound = [HelpBookWorkflowReleaseInput(version: "1.2.0", topicID: "releaseb")]
        XCTAssertFalse(try plan.isCurrent(catalog, preferredLocaleIdentifiers: [], releaseInputs: rebound))

        // Version-only edits move the input digest, but the staleness check
        // compares bound topic IDs, so the plan still reads as current.
        let bumped = [HelpBookWorkflowReleaseInput(version: "1.3.0", topicID: "releasea")]
        XCTAssertTrue(try plan.isCurrent(catalog, preferredLocaleIdentifiers: [], releaseInputs: bumped))
        XCTAssertNotEqual(
            plan.reference.inputDigest,
            try Planner.plan(makeRequest(catalog: catalog, releases: bumped)).reference.inputDigest
        )
    }

    // MARK: - Digest scope

    func testCatalogDigestDistinguishesTopicAndCreditSets() throws {
        let base = try Planner.plan(makeRequest(catalog: happyPathCatalog()))
        let extraTopicCatalog = try makeCatalog(
            topics: happyPathCatalog().topics + [makeTopic(id: "extratopic")],
            credits: happyPathCatalog().credits
        )
        let extraCreditCatalog = try makeCatalog(
            topics: happyPathCatalog().topics,
            credits: happyPathCatalog().credits + [makeCredit(id: "zed")]
        )

        XCTAssertNotEqual(
            base.reference.catalogDigest,
            try Planner.plan(makeRequest(catalog: extraTopicCatalog)).reference.catalogDigest
        )
        XCTAssertNotEqual(
            base.reference.catalogDigest,
            try Planner.plan(makeRequest(catalog: extraCreditCatalog)).reference.catalogDigest
        )
    }

    func testCatalogDigestScopeDocumentsLinkAndKindBlindSpots() throws {
        let base = try happyPathCatalog()
        let basePlan = try Planner.plan(makeRequest(catalog: base))

        // Link-target-only edits keep the same topic/credit IDs and about values,
        // so the catalog digest is unchanged even though the estimate moves.
        let relinkedTopics = try [
            makeTopic(id: "gettingstarted", links: [Catalog.Link.helpBook(anchor: "gettingstarted.other")]),
            makeReleaseTopic(id: "releasenotes"),
            makeTopic(id: "licenseterms", kind: .license)
        ]
        let relinked = try makeCatalog(topics: relinkedTopics, credits: [makeCredit(id: "ann")])
        let relinkedPlan = try Planner.plan(makeRequest(catalog: relinked))
        XCTAssertEqual(relinkedPlan.reference.catalogDigest, basePlan.reference.catalogDigest)
        XCTAssertEqual(relinkedPlan.anchors.first?.anchor, "gettingstarted.other")
        XCTAssertTrue(try basePlan.isCurrent(relinked, preferredLocaleIdentifiers: [], releaseInputs: []))

        // Kind-only edits are likewise invisible to the digest.
        let rekindedTopics = try [
            makeTopic(id: "gettingstarted"),
            makeReleaseTopic(id: "releasenotes"),
            makeTopic(id: "licenseterms", kind: .helpBook)
        ]
        let rekinded = try makeCatalog(topics: rekindedTopics, credits: [makeCredit(id: "ann")])
        let rekindedPlan = try Planner.plan(makeRequest(catalog: rekinded))
        XCTAssertEqual(rekindedPlan.reference.catalogDigest, basePlan.reference.catalogDigest)
        XCTAssertEqual(rekindedPlan.licenseTopicIDs, [])
    }

    func testInputDigestScopeDocumentsProvenanceBlindSpot() throws {
        let catalog = try happyPathCatalog()
        let releases = [HelpBookWorkflowReleaseInput(version: "1.2.0", topicID: "releasenotes")]
        let baseProvenance = HelpBookWorkflowProvenance(versionSource: .callerProvided)
        let otherProvenance = HelpBookWorkflowProvenance(versionSource: .releaseManifest)
        let base = try Planner.plan(
            makeRequest(catalog: catalog, releases: releases, provenance: baseProvenance)
        )
        let other = try Planner.plan(
            makeRequest(catalog: catalog, releases: releases, provenance: otherProvenance)
        )

        // The plan records provenance, but the input digest only mixes fallback
        // locales and release bindings.
        XCTAssertEqual(base.provenance, baseProvenance)
        XCTAssertEqual(other.provenance, otherProvenance)
        XCTAssertEqual(other.reference.inputDigest, base.reference.inputDigest)
        XCTAssertNotEqual(
            base.reference.inputDigest,
            try Planner.plan(makeRequest(catalog: catalog, locales: ["fr"], releases: releases)).reference.inputDigest
        )
    }

    func testPlanPreservesProvenanceLimitsAndSearchLimits() throws {
        let catalog = try happyPathCatalog()
        let provenance = HelpBookWorkflowProvenance(
            versionSource: .callerProvided,
            buildSource: .buildConfiguration
        )
        let limits = HelpBookWorkflowLimits(maximumAnchors: 8, maximumLocales: 4)
        let searchLimits = Catalog.SearchLimits(maximumResults: 10)
        let plan = try Planner.plan(
            makeRequest(catalog: catalog, provenance: provenance, limits: limits, searchLimits: searchLimits)
        )

        XCTAssertEqual(plan.provenance, provenance)
        XCTAssertEqual(plan.limits, limits)
        XCTAssertEqual(plan.searchLimits, searchLimits)
        XCTAssertEqual(plan.receipt().provenance, provenance)
    }

    // MARK: - Negative counts and bounded errors

    func testNegativeAndOversizedLimitsThrowInvalidLimit() throws {
        let catalog = try makeCatalog()
        let cases: [(HelpBookWorkflowLimits, WorkflowError)] = [
            (
                HelpBookWorkflowLimits(maximumAnchors: -1),
                .invalidLimit(name: "maximumAnchors", value: -1)
            ),
            (
                HelpBookWorkflowLimits(maximumReleaseNotes: -1),
                .invalidLimit(name: "maximumReleaseNotes", value: -1)
            ),
            (
                HelpBookWorkflowLimits(maximumLocales: HelpBookWorkflowLimits.hardMaximumLocales + 1),
                .invalidLimit(name: "maximumLocales", value: HelpBookWorkflowLimits.hardMaximumLocales + 1)
            ),
            (
                HelpBookWorkflowLimits(maximumMetadataUTF8Bytes: 0),
                .invalidLimit(name: "maximumMetadataUTF8Bytes", value: 0)
            ),
            (
                HelpBookWorkflowLimits(maximumPersistedBytes: 0),
                .invalidLimit(name: "maximumPersistedBytes", value: 0)
            ),
            (
                HelpBookWorkflowLimits(maximumWorkUnits: 0),
                .invalidLimit(name: "maximumWorkUnits", value: 0)
            ),
            (
                HelpBookWorkflowLimits(cancellationCheckInterval: 0),
                .invalidLimit(name: "cancellationCheckInterval", value: 0)
            )
        ]
        for (limits, expected) in cases {
            assertWorkflowError(try Planner.plan(makeRequest(catalog: catalog, limits: limits)), equals: expected)
        }
    }

    func testInvalidSearchLimitsThrow() throws {
        let catalog = try makeCatalog()

        assertWorkflowError(
            try Planner.plan(makeRequest(catalog: catalog, searchLimits: Catalog.SearchLimits(maximumResults: -1))),
            equals: .invalidLimit(name: "searchLimits", value: -1)
        )
        assertWorkflowError(
            try Planner.plan(
                makeRequest(catalog: catalog, searchLimits: Catalog.SearchLimits(maximumWorkUnits: 0))
            ),
            equals: .invalidLimit(name: "searchLimits", value: 100)
        )
    }

    func testBoundedCountLimitsThrow() throws {
        let anchorLink = try Catalog.Link.helpBook(anchor: "gettingstarted.anchor")
        let anchored = try makeTopic(id: "gettingstarted", links: [anchorLink])
        let release = try makeReleaseTopic(id: "releasenotes")
        let license = try makeTopic(id: "licenseterms", kind: .license)
        let credit = try makeCredit(id: "ann")
        let catalog = try makeCatalog(topics: [anchored, release, license], credits: [credit])
        let releases = [HelpBookWorkflowReleaseInput(version: "1.0.0", topicID: "releasenotes")]

        assertWorkflowError(
            try Planner.plan(
                makeRequest(
                    catalog: catalog,
                    releases: releases,
                    limits: HelpBookWorkflowLimits(maximumReleaseNotes: 0)
                )
            ),
            equals: .tooManyReleaseNotes(maximum: 0)
        )
        assertWorkflowError(
            try Planner.plan(makeRequest(catalog: catalog, limits: HelpBookWorkflowLimits(maximumAnchors: 0))),
            equals: .tooManyAnchors(maximum: 0)
        )
        assertWorkflowError(
            try Planner.plan(
                makeRequest(catalog: catalog, limits: HelpBookWorkflowLimits(maximumValidatedLinks: 0))
            ),
            equals: .tooManyValidatedLinks(maximum: 0)
        )
        assertWorkflowError(
            try Planner.plan(
                makeRequest(catalog: catalog, limits: HelpBookWorkflowLimits(maximumLicenseTopics: 0))
            ),
            equals: .tooManyLicenseTopics(maximum: 0)
        )
        assertWorkflowError(
            try Planner.plan(
                makeRequest(catalog: catalog, limits: HelpBookWorkflowLimits(maximumContributorRefs: 0))
            ),
            equals: .tooManyContributorRefs(maximum: 0)
        )
    }

    func testMetadataWorkAndPersistedBoundsThrow() throws {
        let catalog = try happyPathCatalog()

        assertWorkflowError(
            try Planner.plan(
                makeRequest(catalog: catalog, limits: HelpBookWorkflowLimits(maximumMetadataUTF8Bytes: 1))
            ),
            equals: .metadataTooLarge(maximumUTF8Bytes: 1)
        )
        assertWorkflowError(
            try Planner.plan(
                makeRequest(catalog: catalog, limits: HelpBookWorkflowLimits(maximumWorkUnits: 1))
            ),
            equals: .workLimitExceeded(maximumWorkUnits: 1)
        )

        let plan = try Planner.plan(makeRequest(catalog: catalog))
        let tinyLimits = HelpBookWorkflowLimits(maximumPersistedBytes: 8)
        let tinyPlan = try Planner.plan(makeRequest(catalog: catalog, limits: tinyLimits))
        XCTAssertThrowsError(try tinyPlan.encodeReceipt()) { error in
            XCTAssertEqual(error as? WorkflowError, .persistedDataTooLarge(maximumBytes: 8))
        }
        XCTAssertThrowsError(try Planner.decodeReceipt(from: plan.encodeReceipt(), limits: tinyLimits)) { error in
            XCTAssertEqual(error as? WorkflowError, .persistedDataTooLarge(maximumBytes: 8))
        }
    }

    // MARK: - Receipts

    func testReceiptEncodeDecodeRoundTrip() throws {
        let catalog = try happyPathCatalog()
        let releases = [HelpBookWorkflowReleaseInput(version: "1.2.0", topicID: "releasenotes")]
        let plan = try Planner.plan(makeRequest(catalog: catalog, locales: ["en-us"], releases: releases))

        let receipt = plan.receipt()
        XCTAssertEqual(receipt.receiptVersion, HelpBookWorkflowPlan.currentReceiptVersion)
        XCTAssertEqual(receipt.reference, plan.reference)
        XCTAssertEqual(receipt.fallbackLocales, ["en-us", "en"])
        XCTAssertEqual(receipt.releaseTopicIDs, ["releasenotes"])
        XCTAssertEqual(receipt.anchorCount, 1)
        XCTAssertEqual(receipt.licenseTopicCount, 1)
        XCTAssertEqual(receipt.contributorCount, 1)
        XCTAssertEqual(receipt.validatedLinkCount, 1)

        let decoded = try Planner.decodeReceipt(from: plan.encodeReceipt())
        XCTAssertEqual(decoded, receipt)
    }

    func testDecodeReceiptRejectsUnknownKeyAndVersion() throws {
        let plan = try Planner.plan(makeRequest(catalog: happyPathCatalog()))
        let data = try plan.encodeReceipt()
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        dictionary["extraKey"] = "redacted"
        let tampered = try JSONSerialization.data(withJSONObject: dictionary)
        XCTAssertThrowsError(try Planner.decodeReceipt(from: tampered)) { error in
            XCTAssertEqual(error as? WorkflowError, .unknownReceiptKey(path: "$", key: "extraKey"))
        }

        dictionary["extraKey"] = nil
        dictionary["receiptVersion"] = 999
        let future = try JSONSerialization.data(withJSONObject: dictionary)
        XCTAssertThrowsError(try Planner.decodeReceipt(from: future)) { error in
            XCTAssertEqual(error as? WorkflowError, .unsupportedReceiptVersion(999))
        }
    }
}
