import Foundation

public typealias ComparedFileNavigationCommand = DirectoryPairNavigationCommand

public struct ComparedFileFolderResultsIdentity:
    RawRepresentable, Equatable, Hashable, Sendable
{
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct ComparedFileFolderResultsRevision:
    RawRepresentable, Comparable, Equatable, Hashable, Sendable
{
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (
        left: ComparedFileFolderResultsRevision,
        right: ComparedFileFolderResultsRevision
    ) -> Bool {
        left.rawValue < right.rawValue
    }
}

public struct ComparedFileFolderResultsGeneration:
    RawRepresentable, Comparable, Equatable, Hashable, Sendable
{
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (
        left: ComparedFileFolderResultsGeneration,
        right: ComparedFileFolderResultsGeneration
    ) -> Bool {
        left.rawValue < right.rawValue
    }
}

/// Owner-issued identity for one row. It must not be reused for another logical result.
public struct ComparedFileNavigationItemIdentity:
    RawRepresentable, Equatable, Hashable, Sendable
{
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct ComparedFileNavigationAuthorityIdentity:
    RawRepresentable, Equatable, Hashable, Sendable
{
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum ComparedFileNavigationSide:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case left
    case right
}

public enum ComparedFileNavigationAuthorityCapability:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    /// Permits a future executor to open a descendant regular file for reading.
    case readRegularFile
    /// Permits a future executor to prove that a descendant file is absent.
    case validateMissingFile
}

/// Caller-owned authority metadata. This value declares an acquisition route; it does not prove
/// that sandbox or filesystem access is currently available.
public struct ComparedFileNavigationRootAuthority: Equatable, Hashable, Sendable {
    public let identity: ComparedFileNavigationAuthorityIdentity
    public let side: ComparedFileNavigationSide
    public let rootURL: URL
    public let capabilities: Set<ComparedFileNavigationAuthorityCapability>

    public init(
        identity: ComparedFileNavigationAuthorityIdentity,
        side: ComparedFileNavigationSide,
        rootURL: URL,
        capabilities: Set<ComparedFileNavigationAuthorityCapability>
    ) {
        self.identity = identity
        self.side = side
        self.rootURL = rootURL
        self.capabilities = capabilities
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.identity == right.identity
            && left.side == right.side
            && comparedFileNavigationExactURL(left.rootURL, right.rootURL)
            && left.capabilities == right.capabilities
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        hasher.combine(side)
        comparedFileNavigationHashExactURL(rootURL, into: &hasher)
        hasher.combine(capabilities)
    }
}

public enum ComparedFileNavigationOpenCapability:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case identicalRegularFilePair
    case differentRegularFilePair
    case missingLeftRegularFile
    case missingRightRegularFile
}

public struct ComparedFileNavigationItemBinding: Equatable, Hashable, Sendable {
    public let identity: ComparedFileNavigationItemIdentity
    public let resultID: DirectoryResult.ID

    public init(
        identity: ComparedFileNavigationItemIdentity,
        resultID: DirectoryResult.ID
    ) {
        self.identity = identity
        self.resultID = resultID
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.identity == right.identity
            && comparedFileNavigationExactID(left.resultID, right.resultID)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        comparedFileNavigationHashExactID(resultID, into: &hasher)
    }
}

public enum ComparedFileNavigationComparisonState:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case pending
    case identical
    case different
    case missingLeft
    case missingRight
    case typeMismatch
    case skipped
    case error
}

public enum ComparedFileNavigationVisibility:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case visible
    /// Excluded by status, kind, path, or the hidden-only filter.
    case filtered
    /// Hidden and specifically excluded by the exclude-hidden filter.
    case hidden
}

public enum ComparedFileNavigationItemUnavailabilityReason:
    Equatable, Hashable, Sendable
{
    case filtered
    case hidden
    case pending
    case notRegularFile
    case typeMismatch
    case skipped
    case comparisonError
    case missingOpenCapability(ComparedFileNavigationOpenCapability)
    case missingAuthority(ComparedFileNavigationSide)
    case missingAuthorityCapability(
        side: ComparedFileNavigationSide,
        capability: ComparedFileNavigationAuthorityCapability
    )
}

public enum ComparedFileNavigationItemAvailability: Equatable, Hashable, Sendable {
    case available(requiredCapability: ComparedFileNavigationOpenCapability)
    case unavailable(ComparedFileNavigationItemUnavailabilityReason)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var requiredCapability: ComparedFileNavigationOpenCapability? {
        guard case .available(let capability) = self else { return nil }
        return capability
    }

    public var unavailableReason: ComparedFileNavigationItemUnavailabilityReason? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }
}

public struct ComparedFileNavigationItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: ComparedFileNavigationItemIdentity
    public let resultID: DirectoryResult.ID
    public let left: DirectoryEntryMetadata?
    public let right: DirectoryEntryMetadata?
    public let status: DirectoryComparisonStatus
    public let comparisonState: ComparedFileNavigationComparisonState
    public let visibility: ComparedFileNavigationVisibility
    public let availability: ComparedFileNavigationItemAvailability
    /// Zero-based position after applying the folder's exact sort descriptors but before filtering.
    public let ordinal: Int
    /// Zero-based position in `DirectoryResults.visibleResults`, when visible.
    public let visibleOrdinal: Int?

    public var identity: ComparedFileNavigationItemIdentity { id }
    public var isHidden: Bool { left?.isHidden == true || right?.isHidden == true }
    public var isNavigable: Bool { availability.isAvailable }

    fileprivate init(
        binding: ComparedFileNavigationItemBinding,
        result: DirectoryResult,
        comparisonState: ComparedFileNavigationComparisonState,
        visibility: ComparedFileNavigationVisibility,
        availability: ComparedFileNavigationItemAvailability,
        ordinal: Int,
        visibleOrdinal: Int?
    ) {
        id = binding.identity
        resultID = result.id
        left = result.left
        right = result.right
        status = result.status
        self.comparisonState = comparisonState
        self.visibility = visibility
        self.availability = availability
        self.ordinal = ordinal
        self.visibleOrdinal = visibleOrdinal
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.id == right.id
            && comparedFileNavigationExactID(left.resultID, right.resultID)
            && comparedFileNavigationExactMetadata(left.left, right.left)
            && comparedFileNavigationExactMetadata(left.right, right.right)
            && left.status == right.status
            && left.comparisonState == right.comparisonState
            && left.visibility == right.visibility
            && left.availability == right.availability
            && left.ordinal == right.ordinal
            && left.visibleOrdinal == right.visibleOrdinal
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        comparedFileNavigationHashExactID(resultID, into: &hasher)
        comparedFileNavigationHashExactMetadata(left, into: &hasher)
        comparedFileNavigationHashExactMetadata(right, into: &hasher)
        hasher.combine(status)
        hasher.combine(comparisonState)
        hasher.combine(visibility)
        hasher.combine(availability)
        hasher.combine(ordinal)
        hasher.combine(visibleOrdinal)
    }
}

public struct ComparedFileFolderResultsReference: Equatable, Hashable, Sendable {
    public let identity: ComparedFileFolderResultsIdentity
    public let revision: ComparedFileFolderResultsRevision
    public let generation: ComparedFileFolderResultsGeneration

    public init(
        identity: ComparedFileFolderResultsIdentity,
        revision: ComparedFileFolderResultsRevision,
        generation: ComparedFileFolderResultsGeneration
    ) {
        self.identity = identity
        self.revision = revision
        self.generation = generation
    }
}

public enum ComparedFileNavigationLimit:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case items
    case sortDescriptors
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case workUnits
    case cancellationCheckInterval
}

public struct ComparedFileNavigationLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumItemCount = 1_000_000
    public static let hardMaximumSortDescriptorCount = 1_024
    public static let hardMaximumStringUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 128 * 1_024 * 1_024
    public static let hardMaximumWorkUnits = 512 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = ComparedFileNavigationLimits()

    public let maximumItemCount: Int
    public let maximumSortDescriptorCount: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumItemCount: Int = 100_000,
        maximumSortDescriptorCount: Int = 64,
        maximumStringUTF8Bytes: Int = 16 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumWorkUnits: Int = 64 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 1_024
    ) {
        self.maximumItemCount = maximumItemCount
        self.maximumSortDescriptorCount = maximumSortDescriptorCount
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum ComparedFileNavigationBindingRole:
    String, Equatable, Hashable, Sendable
{
    case selected
    case cursor
}

public enum ComparedFileNavigationDisabledReason: Equatable, Hashable, Sendable {
    case noNavigableItems
    case alreadyAtFirst(ComparedFileNavigationItemIdentity)
    case noPreviousItem
    case noNextItem
    case alreadyAtLast(ComparedFileNavigationItemIdentity)
}

public enum ComparedFileNavigationOrigin: Equatable, Hashable, Sendable {
    case selection(ComparedFileNavigationItemIdentity)
    case cursor(ComparedFileNavigationItemIdentity)
    case startBoundary
    case endBoundary
}

public struct ComparedFileNavigationEnabledReason: Equatable, Hashable, Sendable {
    public let target: ComparedFileNavigationItemIdentity
    public let origin: ComparedFileNavigationOrigin

    public init(
        target: ComparedFileNavigationItemIdentity,
        origin: ComparedFileNavigationOrigin
    ) {
        self.target = target
        self.origin = origin
    }
}

public enum ComparedFileNavigationAvailabilityReason: Equatable, Hashable, Sendable {
    case enabled(ComparedFileNavigationEnabledReason)
    case disabled(ComparedFileNavigationDisabledReason)

    public var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }

    public var disabledReason: ComparedFileNavigationDisabledReason? {
        guard case .disabled(let reason) = self else { return nil }
        return reason
    }
}

public struct ComparedFileNavigationCommandState: Equatable, Hashable, Sendable {
    public let command: ComparedFileNavigationCommand
    public let availabilityReason: ComparedFileNavigationAvailabilityReason
    public let targetItemIdentity: ComparedFileNavigationItemIdentity?

    public var isEnabled: Bool { availabilityReason.isEnabled }
    public var canExecute: Bool { isEnabled }
    public var disabledReason: ComparedFileNavigationDisabledReason? {
        availabilityReason.disabledReason
    }

    fileprivate init(
        command: ComparedFileNavigationCommand,
        availabilityReason: ComparedFileNavigationAvailabilityReason,
        targetItemIdentity: ComparedFileNavigationItemIdentity?
    ) {
        self.command = command
        self.availabilityReason = availabilityReason
        self.targetItemIdentity = targetItemIdentity
    }
}

public struct ComparedFileNavigationCommandStates: Equatable, Hashable, Sendable {
    public let first: ComparedFileNavigationCommandState
    public let previous: ComparedFileNavigationCommandState
    public let next: ComparedFileNavigationCommandState
    public let last: ComparedFileNavigationCommandState

    public init(
        first: ComparedFileNavigationCommandState,
        previous: ComparedFileNavigationCommandState,
        next: ComparedFileNavigationCommandState,
        last: ComparedFileNavigationCommandState
    ) {
        self.first = first
        self.previous = previous
        self.next = next
        self.last = last
    }

    public subscript(command: ComparedFileNavigationCommand) -> ComparedFileNavigationCommandState {
        switch command {
        case .first: first
        case .previous: previous
        case .next: next
        case .last: last
        }
    }

    public var directoryPairNavigationCommandStates: DirectoryPairNavigationCommandStates {
        DirectoryPairNavigationCommandStates(
            first: first.isEnabled,
            previous: previous.isEnabled,
            next: next.isEnabled,
            last: last.isEnabled
        )
    }
}

public enum ComparedFileNavigationOpenItemPresence:
    String, Equatable, Hashable, Sendable
{
    case regularFile
    /// Executor must prove absence under the exact root before representing a missing counterpart.
    case missing
}

public struct ComparedFileNavigationOpenSideRequest: Equatable, Hashable, Sendable {
    public let side: ComparedFileNavigationSide
    public let presence: ComparedFileNavigationOpenItemPresence
    public let rootURL: URL
    public let relativePath: String
    public let authorityIdentity: ComparedFileNavigationAuthorityIdentity
    public let requiredAuthorityCapability: ComparedFileNavigationAuthorityCapability

    fileprivate init(
        side: ComparedFileNavigationSide,
        presence: ComparedFileNavigationOpenItemPresence,
        rootURL: URL,
        relativePath: String,
        authorityIdentity: ComparedFileNavigationAuthorityIdentity,
        requiredAuthorityCapability: ComparedFileNavigationAuthorityCapability
    ) {
        self.side = side
        self.presence = presence
        self.rootURL = rootURL
        self.relativePath = relativePath
        self.authorityIdentity = authorityIdentity
        self.requiredAuthorityCapability = requiredAuthorityCapability
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.side == right.side
            && left.presence == right.presence
            && comparedFileNavigationExactURL(left.rootURL, right.rootURL)
            && comparedFileNavigationExactString(left.relativePath, right.relativePath)
            && left.authorityIdentity == right.authorityIdentity
            && left.requiredAuthorityCapability == right.requiredAuthorityCapability
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(side)
        hasher.combine(presence)
        comparedFileNavigationHashExactURL(rootURL, into: &hasher)
        comparedFileNavigationHashExactString(relativePath, into: &hasher)
        hasher.combine(authorityIdentity)
        hasher.combine(requiredAuthorityCapability)
    }
}

public enum ComparedFileNavigationOpenExecutorContract:
    String, Equatable, Hashable, Sendable
{
    /// Revalidate snapshot, retain both authorities, resolve descriptor-relative without following
    /// links, and open or prove absence before publishing the comparison.
    case exactSnapshotAuthoritiesAndDescriptorRelativeNoFollow
}

/// Pure request for a future opener. Constructing it performs no URL or filesystem access.
public struct ComparedFileNavigationOpenPairRequest: Sendable {
    public let expectedFolderResults: ComparedFileFolderResultsReference
    public let expectedSnapshotFingerprint: ComparedFileNavigationSnapshotFingerprint
    public let itemIdentity: ComparedFileNavigationItemIdentity
    public let itemOrdinal: Int
    public let resultID: DirectoryResult.ID
    public let comparisonState: ComparedFileNavigationComparisonState
    public let requiredOpenCapability: ComparedFileNavigationOpenCapability
    public let left: ComparedFileNavigationOpenSideRequest
    public let right: ComparedFileNavigationOpenSideRequest
    public let executorContract: ComparedFileNavigationOpenExecutorContract

    fileprivate init(
        expectedFolderResults: ComparedFileFolderResultsReference,
        expectedSnapshotFingerprint: ComparedFileNavigationSnapshotFingerprint,
        item: ComparedFileNavigationItem,
        requiredOpenCapability: ComparedFileNavigationOpenCapability,
        left: ComparedFileNavigationOpenSideRequest,
        right: ComparedFileNavigationOpenSideRequest
    ) {
        self.expectedFolderResults = expectedFolderResults
        self.expectedSnapshotFingerprint = expectedSnapshotFingerprint
        itemIdentity = item.identity
        itemOrdinal = item.ordinal
        resultID = item.resultID
        comparisonState = item.comparisonState
        self.requiredOpenCapability = requiredOpenCapability
        self.left = left
        self.right = right
        executorContract = .exactSnapshotAuthoritiesAndDescriptorRelativeNoFollow
    }

    public func isCurrent(for snapshot: ComparedFileNavigationSnapshot) throws -> Bool {
        try ComparedFileNavigationPlanner.isCurrent(self, for: snapshot)
    }

    public func validate(against snapshot: ComparedFileNavigationSnapshot) throws {
        try ComparedFileNavigationPlanner.validate(self, against: snapshot)
    }
}

public struct ComparedFileNavigationFilterState: Equatable, Hashable, Sendable {
    public let statuses: Set<DirectoryComparisonStatus>
    public let pathQuery: String
    public let kinds: Set<DirectoryEntryKind>
    public let hidden: DirectoryHiddenFilter

    public init(_ filter: DirectoryResultFilter) {
        statuses = filter.statuses
        pathQuery = filter.pathQuery
        kinds = filter.kinds
        hidden = filter.hidden
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.statuses == right.statuses
            && comparedFileNavigationExactString(left.pathQuery, right.pathQuery)
            && left.kinds == right.kinds
            && left.hidden == right.hidden
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(statuses)
        comparedFileNavigationHashExactString(pathQuery, into: &hasher)
        hasher.combine(kinds)
        hasher.combine(hidden)
    }
}

/// Exact structural fingerprint. Private payload makes equal lineage counters insufficient when an
/// owner violates revision or generation monotonicity.
public struct ComparedFileNavigationSnapshotFingerprint: Sendable {
    public let reference: ComparedFileFolderResultsReference

    fileprivate let leftRoot: URL
    fileprivate let rightRoot: URL
    fileprivate let items: [ComparedFileNavigationItem]
    fileprivate let filter: ComparedFileNavigationFilterState
    fileprivate let sortDescriptors: [DirectoryResultSortDescriptor]
    fileprivate let selectedItemIdentities: Set<ComparedFileNavigationItemIdentity>
    fileprivate let cursorItemIdentity: ComparedFileNavigationItemIdentity?
    fileprivate let authorities: [ComparedFileNavigationRootAuthority]
    fileprivate let openCapabilities: Set<ComparedFileNavigationOpenCapability>
    fileprivate let limits: ComparedFileNavigationLimits
}

public enum ComparedFileNavigationError:
    Error, Equatable, LocalizedError, Sendable
{
    case cancelled
    case invalidLimit(ComparedFileNavigationLimit, value: Int)
    case tooManyItems(maximum: Int)
    case tooManySortDescriptors(maximum: Int)
    case duplicateResultID(DirectoryResult.ID)
    case duplicateItemIdentity(ComparedFileNavigationItemIdentity)
    case missingItemBinding(DirectoryResult.ID)
    case unusedItemBinding(DirectoryResult.ID)
    case invalidRootURL(ComparedFileNavigationSide)
    case invalidRelativePath(
        item: ComparedFileNavigationItemIdentity?,
        side: ComparedFileNavigationSide
    )
    case stringTooLarge(
        item: ComparedFileNavigationItemIdentity?,
        side: ComparedFileNavigationSide?,
        maximumUTF8Bytes: Int
    )
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case duplicateAuthorityIdentity(ComparedFileNavigationAuthorityIdentity)
    case duplicateAuthoritySide(ComparedFileNavigationSide)
    case authorityRootMismatch(ComparedFileNavigationSide)
    case unknownCursorResult(DirectoryResult.ID)
    case workLimitExceeded(maximumWorkUnits: Int)
    case folderResultsIdentityChanged(
        expected: ComparedFileFolderResultsIdentity,
        actual: ComparedFileFolderResultsIdentity
    )
    case staleRevision(
        expected: ComparedFileFolderResultsRevision,
        actual: ComparedFileFolderResultsRevision
    )
    case staleGeneration(
        expected: ComparedFileFolderResultsGeneration,
        actual: ComparedFileFolderResultsGeneration
    )
    case staleItemIdentity(ComparedFileNavigationItemIdentity)
    case staleItemOrder
    case staleItemState(ComparedFileNavigationItemIdentity)
    case staleSnapshot
    case commandDisabled(ComparedFileNavigationDisabledReason)

    public static func == (left: Self, right: Self) -> Bool {
        switch (left, right) {
        case (.cancelled, .cancelled),
            (.staleItemOrder, .staleItemOrder),
            (.staleSnapshot, .staleSnapshot):
            true
        case (.invalidLimit(let leftLimit, let leftValue), .invalidLimit(let rightLimit, let rightValue)):
            leftLimit == rightLimit && leftValue == rightValue
        case (.tooManyItems(let left), .tooManyItems(let right)),
            (.tooManySortDescriptors(let left), .tooManySortDescriptors(let right)),
            (.totalStringsTooLarge(let left), .totalStringsTooLarge(let right)),
            (.workLimitExceeded(let left), .workLimitExceeded(let right)):
            left == right
        case (.duplicateResultID(let left), .duplicateResultID(let right)),
            (.missingItemBinding(let left), .missingItemBinding(let right)),
            (.unusedItemBinding(let left), .unusedItemBinding(let right)),
            (.unknownCursorResult(let left), .unknownCursorResult(let right)):
            comparedFileNavigationExactID(left, right)
        case (.duplicateItemIdentity(let left), .duplicateItemIdentity(let right)),
            (.staleItemIdentity(let left), .staleItemIdentity(let right)),
            (.staleItemState(let left), .staleItemState(let right)):
            left == right
        case (.invalidRootURL(let left), .invalidRootURL(let right)),
            (.duplicateAuthoritySide(let left), .duplicateAuthoritySide(let right)),
            (.authorityRootMismatch(let left), .authorityRootMismatch(let right)):
            left == right
        case (
            .invalidRelativePath(let leftItem, let leftSide),
            .invalidRelativePath(let rightItem, let rightSide)
        ):
            leftItem == rightItem && leftSide == rightSide
        case (
            .stringTooLarge(let leftItem, let leftSide, let leftMaximum),
            .stringTooLarge(let rightItem, let rightSide, let rightMaximum)
        ):
            leftItem == rightItem && leftSide == rightSide && leftMaximum == rightMaximum
        case (.duplicateAuthorityIdentity(let left), .duplicateAuthorityIdentity(let right)):
            left == right
        case (
            .folderResultsIdentityChanged(let leftExpected, let leftActual),
            .folderResultsIdentityChanged(let rightExpected, let rightActual)
        ):
            leftExpected == rightExpected && leftActual == rightActual
        case (.staleRevision(let leftExpected, let leftActual), .staleRevision(let rightExpected, let rightActual)):
            leftExpected == rightExpected && leftActual == rightActual
        case (
            .staleGeneration(let leftExpected, let leftActual),
            .staleGeneration(let rightExpected, let rightActual)
        ):
            leftExpected == rightExpected && leftActual == rightActual
        case (.commandDisabled(let left), .commandDisabled(let right)):
            left == right
        default:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Compared-file navigation was cancelled."
        case .invalidLimit(let limit, let value):
            "Compared-file navigation limit \(limit.rawValue) is invalid: \(value)."
        case .tooManyItems(let maximum):
            "Compared-file navigation exceeds the \(maximum)-item limit."
        case .tooManySortDescriptors(let maximum):
            "Compared-file navigation exceeds the \(maximum)-sort-descriptor limit."
        case .duplicateResultID:
            "Compared-file navigation contains a duplicate directory-result ID."
        case .duplicateItemIdentity:
            "Compared-file navigation contains a duplicate item identity."
        case .missingItemBinding:
            "Compared-file navigation is missing an item identity binding."
        case .unusedItemBinding:
            "Compared-file navigation contains an unused item identity binding."
        case .invalidRootURL(let side):
            "Compared-file navigation has an invalid \(side.rawValue) root URL."
        case .invalidRelativePath(_, let side):
            "Compared-file navigation has an invalid \(side.rawValue) relative path."
        case .stringTooLarge(_, _, let maximum):
            "Compared-file navigation string exceeds \(maximum) UTF-8 bytes."
        case .totalStringsTooLarge(let maximum):
            "Compared-file navigation strings exceed \(maximum) combined UTF-8 bytes."
        case .duplicateAuthorityIdentity:
            "Compared-file navigation reuses a root-authority identity."
        case .duplicateAuthoritySide(let side):
            "Compared-file navigation contains multiple \(side.rawValue) root authorities."
        case .authorityRootMismatch(let side):
            "Compared-file navigation \(side.rawValue) authority belongs to another root."
        case .unknownCursorResult:
            "Compared-file navigation cursor does not identify a folder result."
        case .workLimitExceeded(let maximum):
            "Compared-file navigation exceeds the \(maximum)-unit work limit."
        case .folderResultsIdentityChanged:
            "Compared-file navigation belongs to another folder-result collection."
        case .staleRevision:
            "Compared-file navigation folder-result revision is stale."
        case .staleGeneration:
            "Compared-file navigation folder-result generation is stale."
        case .staleItemIdentity:
            "Compared-file navigation item identity is stale."
        case .staleItemOrder:
            "Compared-file navigation item order changed without a generation change."
        case .staleItemState:
            "Compared-file navigation item state changed without a revision or generation change."
        case .staleSnapshot:
            "Compared-file navigation snapshot changed without advancing its freshness values."
        case .commandDisabled:
            "Compared-file navigation command is disabled."
        }
    }
}

/// Immutable owner snapshot. `revision` must change for result payload or item-binding changes;
/// `generation` must change for any ordering, filtering, selection, cursor, authority, or capability
/// change. Planning verifies full state even when an owner violates those rules.
public struct ComparedFileNavigationSnapshot: Sendable {
    public let reference: ComparedFileFolderResultsReference
    public let leftRoot: URL
    public let rightRoot: URL
    public let items: [ComparedFileNavigationItem]
    public let filter: ComparedFileNavigationFilterState
    public let sortDescriptors: [DirectoryResultSortDescriptor]
    public let selectedItemIdentities: Set<ComparedFileNavigationItemIdentity>
    public let cursorItemIdentity: ComparedFileNavigationItemIdentity?
    public let authorities: [ComparedFileNavigationRootAuthority]
    public let openCapabilities: Set<ComparedFileNavigationOpenCapability>
    public let limits: ComparedFileNavigationLimits

    public var identity: ComparedFileFolderResultsIdentity { reference.identity }
    public var revision: ComparedFileFolderResultsRevision { reference.revision }
    public var generation: ComparedFileFolderResultsGeneration { reference.generation }
    public var navigableItems: [ComparedFileNavigationItem] { items.filter(\.isNavigable) }
    public var fingerprint: ComparedFileNavigationSnapshotFingerprint {
        ComparedFileNavigationSnapshotFingerprint(
            reference: reference,
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            items: items,
            filter: filter,
            sortDescriptors: sortDescriptors,
            selectedItemIdentities: selectedItemIdentities,
            cursorItemIdentity: cursorItemIdentity,
            authorities: authorities,
            openCapabilities: openCapabilities,
            limits: limits
        )
    }

    public init(
        identity: ComparedFileFolderResultsIdentity,
        revision: ComparedFileFolderResultsRevision,
        generation: ComparedFileFolderResultsGeneration,
        results: DirectoryResults,
        itemBindings: [ComparedFileNavigationItemBinding],
        cursorResultID: DirectoryResult.ID? = nil,
        authorities: [ComparedFileNavigationRootAuthority] = [],
        openCapabilities: Set<ComparedFileNavigationOpenCapability> = [],
        limits: ComparedFileNavigationLimits = .default
    ) throws {
        try ComparedFileNavigationPlanner.validate(limits)
        try ComparedFileNavigationPlanner.checkCancellation()
        guard results.results.count <= limits.maximumItemCount else {
            throw ComparedFileNavigationError.tooManyItems(maximum: limits.maximumItemCount)
        }
        guard itemBindings.count <= limits.maximumItemCount else {
            throw ComparedFileNavigationError.tooManyItems(maximum: limits.maximumItemCount)
        }
        guard results.sortDescriptors.count <= limits.maximumSortDescriptorCount else {
            throw ComparedFileNavigationError.tooManySortDescriptors(
                maximum: limits.maximumSortDescriptorCount
            )
        }

        var budget = ComparedFileNavigationWorkBudget(limits: limits)
        var totalStringBytes = 0
        try Self.accountString(
            results.leftRoot.absoluteString,
            item: nil,
            side: .left,
            totalStringBytes: &totalStringBytes,
            limits: limits,
            budget: &budget
        )
        try Self.accountString(
            results.rightRoot.absoluteString,
            item: nil,
            side: .right,
            totalStringBytes: &totalStringBytes,
            limits: limits,
            budget: &budget
        )
        try Self.validateRootURL(results.leftRoot, side: .left, budget: &budget)
        try Self.validateRootURL(results.rightRoot, side: .right, budget: &budget)

        for result in results.results {
            try budget.consume()
            if let path = result.left?.relativePath {
                try Self.validateRelativePath(
                    path,
                    item: nil,
                    side: .left,
                    totalStringBytes: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
            if let path = result.right?.relativePath {
                try Self.validateRelativePath(
                    path,
                    item: nil,
                    side: .right,
                    totalStringBytes: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
        }
        for binding in itemBindings {
            try budget.consume()
            if let path = binding.resultID.leftRelativePath {
                try Self.validateRelativePath(
                    path,
                    item: binding.identity,
                    side: .left,
                    totalStringBytes: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
            if let path = binding.resultID.rightRelativePath {
                try Self.validateRelativePath(
                    path,
                    item: binding.identity,
                    side: .right,
                    totalStringBytes: &totalStringBytes,
                    limits: limits,
                    budget: &budget
                )
            }
        }
        var resultsByID: [ComparedFileNavigationResultIDHash: [DirectoryResult]] = [:]
        resultsByID.reserveCapacity(results.results.count)
        for result in results.results {
            try budget.consume()
            let idHash = try ComparedFileNavigationResultIDHash(result.id, budget: &budget)
            try budget.consume(resultsByID.count + 1)
            if let candidates = resultsByID[idHash] {
                for candidate in candidates {
                    try budget.consume()
                    if try Self.exactID(result.id, matches: candidate.id, budget: &budget) {
                        throw ComparedFileNavigationError.duplicateResultID(result.id)
                    }
                }
            }
            try budget.consume(resultsByID.count + 1)
            resultsByID[idHash, default: []].append(result)
        }
        var bindingsByResultID: [ComparedFileNavigationResultIDHash: [ComparedFileNavigationItemBinding]] = [:]
        var seenItemIdentities: Set<ComparedFileNavigationItemIdentity> = []
        bindingsByResultID.reserveCapacity(itemBindings.count)
        seenItemIdentities.reserveCapacity(itemBindings.count)
        for binding in itemBindings {
            try budget.consume()
            let idHash = try ComparedFileNavigationResultIDHash(
                binding.resultID,
                budget: &budget
            )
            try budget.consume(resultsByID.count + 1)
            guard
                try Self.matchingResult(
                    for: binding.resultID,
                    in: resultsByID[idHash],
                    budget: &budget
                ) != nil
            else {
                throw ComparedFileNavigationError.unusedItemBinding(binding.resultID)
            }
            try budget.consume(bindingsByResultID.count + 1)
            if try Self.matchingBinding(
                for: binding.resultID,
                in: bindingsByResultID[idHash],
                budget: &budget
            ) != nil {
                throw ComparedFileNavigationError.duplicateResultID(binding.resultID)
            }
            try budget.consume(bindingsByResultID.count + 1)
            bindingsByResultID[idHash, default: []].append(binding)
            try budget.consume(seenItemIdentities.count + 1)
            guard seenItemIdentities.insert(binding.identity).inserted else {
                throw ComparedFileNavigationError.duplicateItemIdentity(binding.identity)
            }
        }

        for result in results.results {
            try budget.consume()
            let idHash = try ComparedFileNavigationResultIDHash(result.id, budget: &budget)
            try budget.consume(bindingsByResultID.count + 1)
            guard
                try Self.matchingBinding(
                    for: result.id,
                    in: bindingsByResultID[idHash],
                    budget: &budget
                ) != nil
            else {
                throw ComparedFileNavigationError.missingItemBinding(result.id)
            }
        }
        try Self.accountString(
            results.filter.pathQuery,
            item: nil,
            side: nil,
            totalStringBytes: &totalStringBytes,
            limits: limits,
            budget: &budget
        )

        let canonicalAuthorities = try Self.canonicalAuthorities(
            authorities,
            leftRoot: results.leftRoot,
            rightRoot: results.rightRoot,
            totalStringBytes: &totalStringBytes,
            limits: limits,
            budget: &budget
        )
        let authoritiesBySide = Dictionary(
            uniqueKeysWithValues: canonicalAuthorities.map {
                ($0.side, $0)
            })

        // This is DirectoryResults' stable sort contract with work and cancellation checks added.
        let orderedResults = try Self.orderedResults(
            results.results,
            descriptors: results.sortDescriptors,
            budget: &budget
        )

        var visibleOrdinals: [ComparedFileNavigationResultIDHash: [(DirectoryResult.ID, Int)]] = [:]
        visibleOrdinals.reserveCapacity(orderedResults.count)
        var visibleIndex = 0
        for result in orderedResults {
            try budget.consume()
            if try Self.matches(results.filter, result: result, budget: &budget) {
                let idHash = try ComparedFileNavigationResultIDHash(
                    result.id,
                    budget: &budget
                )
                try budget.consume(visibleOrdinals.count + 1)
                visibleOrdinals[idHash, default: []].append((result.id, visibleIndex))
                visibleIndex += 1
            }
        }

        var items: [ComparedFileNavigationItem] = []
        items.reserveCapacity(orderedResults.count)
        for (ordinal, result) in orderedResults.enumerated() {
            try budget.consume()
            let idHash = try ComparedFileNavigationResultIDHash(result.id, budget: &budget)
            try budget.consume(bindingsByResultID.count + 1)
            guard
                let binding = try Self.matchingBinding(
                    for: result.id,
                    in: bindingsByResultID[idHash],
                    budget: &budget
                )
            else {
                throw ComparedFileNavigationError.missingItemBinding(result.id)
            }
            try budget.consume(visibleOrdinals.count + 1)
            let visibleOrdinal = try Self.matchingVisibleOrdinal(
                for: result.id,
                in: visibleOrdinals[idHash],
                budget: &budget
            )
            let visibility = try Self.visibility(
                of: result,
                filter: results.filter,
                visibleOrdinal: visibleOrdinal,
                budget: &budget
            )
            let comparisonState = Self.comparisonState(for: result.status)
            let availability = Self.availability(
                for: result,
                comparisonState: comparisonState,
                visibility: visibility,
                isPairedRegularFile: visibility == .visible && result.isOpenableFilePair,
                authorities: authoritiesBySide,
                openCapabilities: openCapabilities
            )
            items.append(
                ComparedFileNavigationItem(
                    binding: binding,
                    result: result,
                    comparisonState: comparisonState,
                    visibility: visibility,
                    availability: availability,
                    ordinal: ordinal,
                    visibleOrdinal: visibleOrdinal
                )
            )
        }

        var selectedItemIdentities: Set<ComparedFileNavigationItemIdentity> = []
        selectedItemIdentities.reserveCapacity(results.selectedIDs.count)
        for resultID in results.selectedIDs {
            try budget.consume()
            guard
                let canonicalResult = try Self.matchingEquivalentResult(
                    for: resultID,
                    in: results.results,
                    budget: &budget
                )
            else {
                throw ComparedFileNavigationError.missingItemBinding(resultID)
            }
            let idHash = try ComparedFileNavigationResultIDHash(
                canonicalResult.id,
                budget: &budget
            )
            try budget.consume(bindingsByResultID.count + 1)
            guard
                let binding = try Self.matchingBinding(
                    for: canonicalResult.id,
                    in: bindingsByResultID[idHash],
                    budget: &budget
                )
            else {
                throw ComparedFileNavigationError.missingItemBinding(resultID)
            }
            try budget.consume(selectedItemIdentities.count + 1)
            selectedItemIdentities.insert(binding.identity)
        }
        let cursorItemIdentity: ComparedFileNavigationItemIdentity?
        if let cursorResultID {
            guard
                let canonicalResult = try Self.matchingEquivalentResult(
                    for: cursorResultID,
                    in: results.results,
                    budget: &budget
                )
            else {
                throw ComparedFileNavigationError.unknownCursorResult(cursorResultID)
            }
            let idHash = try ComparedFileNavigationResultIDHash(
                canonicalResult.id,
                budget: &budget
            )
            try budget.consume(bindingsByResultID.count + 1)
            guard
                let binding = try Self.matchingBinding(
                    for: canonicalResult.id,
                    in: bindingsByResultID[idHash],
                    budget: &budget
                )
            else {
                throw ComparedFileNavigationError.unknownCursorResult(cursorResultID)
            }
            cursorItemIdentity = binding.identity
        } else {
            cursorItemIdentity = nil
        }
        try budget.finish()

        reference = ComparedFileFolderResultsReference(
            identity: identity,
            revision: revision,
            generation: generation
        )
        leftRoot = results.leftRoot
        rightRoot = results.rightRoot
        self.items = items
        filter = ComparedFileNavigationFilterState(results.filter)
        sortDescriptors = results.sortDescriptors
        self.selectedItemIdentities = selectedItemIdentities
        self.cursorItemIdentity = cursorItemIdentity
        self.authorities = canonicalAuthorities
        self.openCapabilities = openCapabilities
        self.limits = limits
    }

    public init(
        identity: ComparedFileFolderResultsIdentity,
        revision: UInt64,
        generation: UInt64,
        results: DirectoryResults,
        itemBindings: [ComparedFileNavigationItemBinding],
        cursorResultID: DirectoryResult.ID? = nil,
        authorities: [ComparedFileNavigationRootAuthority] = [],
        openCapabilities: Set<ComparedFileNavigationOpenCapability> = [],
        limits: ComparedFileNavigationLimits = .default
    ) throws {
        try self.init(
            identity: identity,
            revision: ComparedFileFolderResultsRevision(rawValue: revision),
            generation: ComparedFileFolderResultsGeneration(rawValue: generation),
            results: results,
            itemBindings: itemBindings,
            cursorResultID: cursorResultID,
            authorities: authorities,
            openCapabilities: openCapabilities,
            limits: limits
        )
    }

    public func item(
        withIdentity identity: ComparedFileNavigationItemIdentity
    ) -> ComparedFileNavigationItem? {
        items.first { $0.identity == identity }
    }

    public func item(withResultID resultID: DirectoryResult.ID) -> ComparedFileNavigationItem? {
        items.first { Self.exactID($0.resultID, matches: resultID) }
    }

    public func commandStates() throws -> ComparedFileNavigationCommandStates {
        try ComparedFileNavigationPlanner.commandStates(in: self)
    }

    private static func validateRootURL(
        _ url: URL,
        side: ComparedFileNavigationSide,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws {
        try budget.consume()
        let decodedPath = url.path(percentEncoded: false)
        guard url.isFileURL,
            url.path.hasPrefix("/"),
            url.host == nil || url.host == "localhost",
            url.query == nil,
            url.fragment == nil
        else {
            throw ComparedFileNavigationError.invalidRootURL(side)
        }
        for byte in decodedPath.utf8 {
            try budget.consume()
            guard byte != 0 else {
                throw ComparedFileNavigationError.invalidRootURL(side)
            }
        }
    }

    private static func validateRelativePath(
        _ path: String,
        item: ComparedFileNavigationItemIdentity?,
        side: ComparedFileNavigationSide,
        totalStringBytes: inout Int,
        limits: ComparedFileNavigationLimits,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws {
        try accountString(
            path,
            item: item,
            side: side,
            totalStringBytes: &totalStringBytes,
            limits: limits,
            budget: &budget
        )
        guard !path.isEmpty, !path.hasPrefix("/"), !path.utf8.contains(0) else {
            throw ComparedFileNavigationError.invalidRelativePath(item: item, side: side)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ComparedFileNavigationError.invalidRelativePath(item: item, side: side)
        }
    }

    private static func accountString(
        _ string: String,
        item: ComparedFileNavigationItemIdentity?,
        side: ComparedFileNavigationSide?,
        totalStringBytes: inout Int,
        limits: ComparedFileNavigationLimits,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws {
        var count = 0
        for _ in string.utf8 {
            try budget.consume()
            guard count < limits.maximumStringUTF8Bytes else {
                throw ComparedFileNavigationError.stringTooLarge(
                    item: item,
                    side: side,
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            count += 1
        }
        guard totalStringBytes <= limits.maximumTotalStringUTF8Bytes - count else {
            throw ComparedFileNavigationError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        totalStringBytes += count
    }

    private static func canonicalAuthorities(
        _ authorities: [ComparedFileNavigationRootAuthority],
        leftRoot: URL,
        rightRoot: URL,
        totalStringBytes: inout Int,
        limits: ComparedFileNavigationLimits,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> [ComparedFileNavigationRootAuthority] {
        var seenIdentities: Set<ComparedFileNavigationAuthorityIdentity> = []
        var seenSides: Set<ComparedFileNavigationSide> = []
        var bySide: [ComparedFileNavigationSide: ComparedFileNavigationRootAuthority] = [:]
        for authority in authorities {
            try budget.consume()
            try accountString(
                authority.rootURL.absoluteString,
                item: nil,
                side: authority.side,
                totalStringBytes: &totalStringBytes,
                limits: limits,
                budget: &budget
            )
            guard seenIdentities.insert(authority.identity).inserted else {
                throw ComparedFileNavigationError.duplicateAuthorityIdentity(authority.identity)
            }
            guard seenSides.insert(authority.side).inserted else {
                throw ComparedFileNavigationError.duplicateAuthoritySide(authority.side)
            }
            let expectedRoot = authority.side == .left ? leftRoot : rightRoot
            let authorityRoot = authority.rootURL.absoluteString
            let expectedRootString = expectedRoot.absoluteString
            try chargeStringComparison(authorityRoot, expectedRootString, budget: &budget)
            guard authorityRoot.utf8.elementsEqual(expectedRootString.utf8) else {
                throw ComparedFileNavigationError.authorityRootMismatch(authority.side)
            }
            bySide[authority.side] = authority
        }
        return ComparedFileNavigationSide.allCases.compactMap { bySide[$0] }
    }

    private static func visibility(
        of result: DirectoryResult,
        filter: DirectoryResultFilter,
        visibleOrdinal: Int?,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> ComparedFileNavigationVisibility {
        if visibleOrdinal != nil { return .visible }
        if result.isHidden, filter.hidden == .exclude {
            var includingHidden = filter
            includingHidden.hidden = .include
            if try matches(includingHidden, result: result, budget: &budget) { return .hidden }
        }
        return .filtered
    }

    private static func matches(
        _ filter: DirectoryResultFilter,
        result: DirectoryResult,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        if !filter.statuses.isEmpty, !filter.statuses.contains(result.status) {
            return false
        }
        if !filter.kinds.isEmpty {
            let leftMatches = result.left.map { filter.kinds.contains($0.kind) } == true
            let rightMatches = result.right.map { filter.kinds.contains($0.kind) } == true
            if !leftMatches && !rightMatches { return false }
        }
        switch filter.hidden {
        case .include:
            break
        case .exclude where result.isHidden:
            return false
        case .only where !result.isHidden:
            return false
        default:
            break
        }
        guard !filter.pathQuery.isEmpty else { return true }
        for path in [result.left?.relativePath, result.right?.relativePath].compactMap({ $0 }) {
            try chargeStringComparison(path, filter.pathQuery, budget: &budget)
            if path.range(
                of: filter.pathQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ) != nil {
                return true
            }
        }
        return false
    }

    private static func exactID(
        _ left: DirectoryResult.ID,
        matches right: DirectoryResult.ID
    ) -> Bool {
        exactOptionalString(left.leftRelativePath, right.leftRelativePath)
            && exactOptionalString(left.rightRelativePath, right.rightRelativePath)
    }

    private static func exactOptionalString(_ left: String?, _ right: String?) -> Bool {
        switch (left, right) {
        case (nil, nil): true
        case (let left?, let right?): left.utf8.elementsEqual(right.utf8)
        default: false
        }
    }

    private static func exactID(
        _ left: DirectoryResult.ID,
        matches right: DirectoryResult.ID,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        if let path = left.leftRelativePath {
            for _ in path.utf8 { try budget.consume() }
        }
        if let path = right.leftRelativePath {
            for _ in path.utf8 { try budget.consume() }
        }
        if let path = left.rightRelativePath {
            for _ in path.utf8 { try budget.consume() }
        }
        if let path = right.rightRelativePath {
            for _ in path.utf8 { try budget.consume() }
        }
        return exactID(left, matches: right)
    }

    private static func matchingResult(
        for resultID: DirectoryResult.ID,
        in candidates: [DirectoryResult]?,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> DirectoryResult? {
        for candidate in candidates ?? [] {
            try budget.consume()
            if try exactID(resultID, matches: candidate.id, budget: &budget) {
                return candidate
            }
        }
        return nil
    }

    private static func matchingEquivalentResult(
        for resultID: DirectoryResult.ID,
        in candidates: [DirectoryResult],
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> DirectoryResult? {
        for candidate in candidates {
            try budget.consume()
            if try equivalentID(resultID, candidate.id, budget: &budget) {
                return candidate
            }
        }
        return nil
    }

    private enum ResultIDIdentity {
        case path(String)
        case pair(String, String)
    }

    private static func equivalentID(
        _ left: DirectoryResult.ID,
        _ right: DirectoryResult.ID,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        let leftIdentity = try resultIDIdentity(left, budget: &budget)
        let rightIdentity = try resultIDIdentity(right, budget: &budget)
        switch (leftIdentity, rightIdentity) {
        case (.path(let leftPath), .path(let rightPath)):
            return try equivalentString(leftPath, rightPath, budget: &budget)
        case (.pair(let leftLeft, let leftRight), .pair(let rightLeft, let rightRight)):
            return try equivalentString(leftLeft, rightLeft, budget: &budget)
                && equivalentString(leftRight, rightRight, budget: &budget)
        default:
            return false
        }
    }

    private static func resultIDIdentity(
        _ id: DirectoryResult.ID,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> ResultIDIdentity {
        switch (id.leftRelativePath, id.rightRelativePath) {
        case (let left?, let right?):
            try equivalentString(left, right, budget: &budget)
                ? .path(left)
                : .pair(left, right)
        case (let left?, nil):
            .path(left)
        case (nil, let right?):
            .path(right)
        case (nil, nil):
            preconditionFailure("A directory result ID requires a relative path")
        }
    }

    private static func equivalentString(
        _ left: String,
        _ right: String,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        try chargeStringComparison(left, right, budget: &budget)
        return left == right
    }

    private static func matchingBinding(
        for resultID: DirectoryResult.ID,
        in candidates: [ComparedFileNavigationItemBinding]?,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> ComparedFileNavigationItemBinding? {
        for candidate in candidates ?? [] {
            try budget.consume()
            if try exactID(resultID, matches: candidate.resultID, budget: &budget) {
                return candidate
            }
        }
        return nil
    }

    private static func matchingVisibleOrdinal(
        for resultID: DirectoryResult.ID,
        in candidates: [(DirectoryResult.ID, Int)]?,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Int? {
        for (candidateID, ordinal) in candidates ?? [] {
            try budget.consume()
            if try exactID(resultID, matches: candidateID, budget: &budget) {
                return ordinal
            }
        }
        return nil
    }

    private static func orderedResults(
        _ results: [DirectoryResult],
        descriptors: [DirectoryResultSortDescriptor],
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> [DirectoryResult] {
        var indexed: [(offset: Int, result: DirectoryResult)] = []
        indexed.reserveCapacity(results.count)
        for (offset, result) in results.enumerated() {
            try budget.consume()
            indexed.append((offset, result))
        }
        let sorted = try stableMergeSort(indexed, budget: &budget) { left, right, budget in
            for descriptor in descriptors {
                try budget.consume()
                let comparison = try compare(
                    left.result,
                    right.result,
                    by: descriptor.key,
                    budget: &budget
                )
                guard comparison != .same else { continue }
                return descriptor.order == .ascending
                    ? comparison == .before
                    : comparison == .after
            }
            return left.offset < right.offset
        }
        var ordered: [DirectoryResult] = []
        ordered.reserveCapacity(sorted.count)
        for element in sorted {
            try budget.consume()
            ordered.append(element.result)
        }
        return ordered
    }

    private enum Comparison {
        case before
        case same
        case after
    }

    private static func compare(
        _ left: DirectoryResult,
        _ right: DirectoryResult,
        by key: DirectoryResultSortKey,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Comparison {
        switch key {
        case .path: try compare(left.relativePath, right.relativePath, budget: &budget)
        case .status: compare(left.status.rawValue, right.status.rawValue)
        case .kind: compare(left.kind?.rawValue, right.kind?.rawValue)
        case .leftSize: compare(left.left?.byteCount, right.left?.byteCount)
        case .rightSize: compare(left.right?.byteCount, right.right?.byteCount)
        case .leftModificationDate:
            compareDates(left.left?.modificationDate, right.left?.modificationDate)
        case .rightModificationDate:
            compareDates(left.right?.modificationDate, right.right?.modificationDate)
        }
    }

    private static func compare<T: Comparable>(_ left: T?, _ right: T?) -> Comparison {
        switch (left, right) {
        case (nil, nil): .same
        case (nil, _): .after
        case (_, nil): .before
        case (let left?, let right?) where left < right: .before
        case (let left?, let right?) where left > right: .after
        default: .same
        }
    }

    private static func compareDates(_ left: Date?, _ right: Date?) -> Comparison {
        switch (left, right) {
        case (nil, nil): return .same
        case (nil, _): return .after
        case (_, nil): return .before
        case (let left?, let right?):
            let leftValue = left.timeIntervalSinceReferenceDate
            let rightValue = right.timeIntervalSinceReferenceDate
            if leftValue.isNaN { return rightValue.isNaN ? .same : .after }
            if rightValue.isNaN { return .before }
            return compare(leftValue, rightValue)
        }
    }

    private static func compare(
        _ left: String,
        _ right: String,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Comparison {
        try chargeStringComparison(left, right, budget: &budget)
        let result = left.compare(
            right,
            options: [.caseInsensitive, .numeric],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if result == .orderedAscending { return .before }
        if result == .orderedDescending { return .after }
        if left.utf8.lexicographicallyPrecedes(right.utf8) { return .before }
        if right.utf8.lexicographicallyPrecedes(left.utf8) { return .after }
        return .same
    }

    private static func chargeStringComparison(
        _ left: String,
        _ right: String,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws {
        for _ in left.utf8 { try budget.consume() }
        for _ in right.utf8 { try budget.consume() }
    }

    private static func stableMergeSort<Element>(
        _ elements: [Element],
        budget: inout ComparedFileNavigationWorkBudget,
        precedes: (
            Element,
            Element,
            inout ComparedFileNavigationWorkBudget
        ) throws -> Bool
    ) throws -> [Element] {
        guard elements.count > 1 else { return elements }
        var source = elements
        var destination = elements
        var width = 1
        while width < source.count {
            var lowerBound = source.startIndex
            while lowerBound < source.endIndex {
                let middle = min(lowerBound + width, source.endIndex)
                let upperBound = min(middle + width, source.endIndex)
                var left = lowerBound
                var right = middle
                var output = lowerBound
                while left < middle, right < upperBound {
                    try budget.consume()
                    if try precedes(source[right], source[left], &budget) {
                        destination[output] = source[right]
                        right += 1
                    } else {
                        destination[output] = source[left]
                        left += 1
                    }
                    output += 1
                }
                while left < middle {
                    try budget.consume()
                    destination[output] = source[left]
                    left += 1
                    output += 1
                }
                while right < upperBound {
                    try budget.consume()
                    destination[output] = source[right]
                    right += 1
                    output += 1
                }
                lowerBound = upperBound
            }
            swap(&source, &destination)
            let halfRoundedUp = source.count / 2 + source.count % 2
            width = width >= halfRoundedUp ? source.count : width * 2
        }
        return source
    }

    private static func comparisonState(
        for status: DirectoryComparisonStatus
    ) -> ComparedFileNavigationComparisonState {
        switch status {
        case .pending: .pending
        case .identical: .identical
        case .different: .different
        case .leftOnly: .missingRight
        case .rightOnly: .missingLeft
        case .typeMismatch: .typeMismatch
        case .skipped: .skipped
        case .error: .error
        }
    }

    private static func availability(
        for result: DirectoryResult,
        comparisonState: ComparedFileNavigationComparisonState,
        visibility: ComparedFileNavigationVisibility,
        isPairedRegularFile: Bool,
        authorities: [ComparedFileNavigationSide: ComparedFileNavigationRootAuthority],
        openCapabilities: Set<ComparedFileNavigationOpenCapability>
    ) -> ComparedFileNavigationItemAvailability {
        switch visibility {
        case .filtered: return .unavailable(.filtered)
        case .hidden: return .unavailable(.hidden)
        case .visible: break
        }

        let openCapability: ComparedFileNavigationOpenCapability
        let authorityRequirements: [(ComparedFileNavigationSide, ComparedFileNavigationAuthorityCapability)]
        switch comparisonState {
        case .pending:
            return .unavailable(.pending)
        case .identical:
            guard isPairedRegularFile else { return .unavailable(.notRegularFile) }
            openCapability = .identicalRegularFilePair
            authorityRequirements = [(.left, .readRegularFile), (.right, .readRegularFile)]
        case .different:
            guard isPairedRegularFile else { return .unavailable(.notRegularFile) }
            openCapability = .differentRegularFilePair
            authorityRequirements = [(.left, .readRegularFile), (.right, .readRegularFile)]
        case .missingLeft:
            guard result.left == nil, result.right?.kind == .file else {
                return .unavailable(.notRegularFile)
            }
            openCapability = .missingLeftRegularFile
            authorityRequirements = [(.left, .validateMissingFile), (.right, .readRegularFile)]
        case .missingRight:
            guard result.left?.kind == .file, result.right == nil else {
                return .unavailable(.notRegularFile)
            }
            openCapability = .missingRightRegularFile
            authorityRequirements = [(.left, .readRegularFile), (.right, .validateMissingFile)]
        case .typeMismatch:
            return .unavailable(.typeMismatch)
        case .skipped:
            return .unavailable(.skipped)
        case .error:
            return .unavailable(.comparisonError)
        }

        guard openCapabilities.contains(openCapability) else {
            return .unavailable(.missingOpenCapability(openCapability))
        }
        for (side, capability) in authorityRequirements {
            guard let authority = authorities[side] else {
                return .unavailable(.missingAuthority(side))
            }
            guard authority.capabilities.contains(capability) else {
                return .unavailable(
                    .missingAuthorityCapability(side: side, capability: capability)
                )
            }
        }
        return .available(requiredCapability: openCapability)
    }
}

public struct ComparedFileNavigationPlan: Sendable {
    public let command: ComparedFileNavigationCommand
    public let expectedFolderResults: ComparedFileFolderResultsReference
    public let expectedSnapshotFingerprint: ComparedFileNavigationSnapshotFingerprint
    public let commandState: ComparedFileNavigationCommandState
    public let openPairRequest: ComparedFileNavigationOpenPairRequest?
    public let plannedWorkUnits: Int

    public var isEnabled: Bool { commandState.isEnabled }
    public var canExecute: Bool { isEnabled }
    public var targetItemIdentity: ComparedFileNavigationItemIdentity? {
        commandState.targetItemIdentity
    }
    public var disabledReason: ComparedFileNavigationDisabledReason? {
        commandState.disabledReason
    }

    fileprivate init(
        command: ComparedFileNavigationCommand,
        snapshot: ComparedFileNavigationSnapshot,
        commandState: ComparedFileNavigationCommandState,
        openPairRequest: ComparedFileNavigationOpenPairRequest?,
        plannedWorkUnits: Int
    ) {
        self.command = command
        expectedFolderResults = snapshot.reference
        expectedSnapshotFingerprint = snapshot.fingerprint
        self.commandState = commandState
        self.openPairRequest = openPairRequest
        self.plannedWorkUnits = plannedWorkUnits
    }

    public func isCurrent(for snapshot: ComparedFileNavigationSnapshot) throws -> Bool {
        try ComparedFileNavigationPlanner.isCurrent(self, for: snapshot)
    }

    public func validate(against snapshot: ComparedFileNavigationSnapshot) throws {
        try ComparedFileNavigationPlanner.validate(self, against: snapshot)
    }
}

public typealias ComparedFileNavigationResolution = ComparedFileNavigationPlan

/// UI- and filesystem-independent bounded planner. Every destination is strict and no command wraps.
public enum ComparedFileNavigationPlanner: Sendable {
    public static func plan(
        _ command: ComparedFileNavigationCommand,
        in snapshot: ComparedFileNavigationSnapshot
    ) throws -> ComparedFileNavigationPlan {
        try checkCancellation()
        var budget = ComparedFileNavigationWorkBudget(limits: snapshot.limits)
        let plan = try plan(command, in: snapshot, budget: &budget)
        try budget.finish()
        return plan
    }

    public static func resolve(
        _ command: ComparedFileNavigationCommand,
        in snapshot: ComparedFileNavigationSnapshot
    ) throws -> ComparedFileNavigationResolution {
        try plan(command, in: snapshot)
    }

    public static func resolveAll(
        in snapshot: ComparedFileNavigationSnapshot
    ) throws -> [ComparedFileNavigationResolution] {
        try checkCancellation()
        var budget = ComparedFileNavigationWorkBudget(limits: snapshot.limits)
        var plans: [ComparedFileNavigationPlan] = []
        plans.reserveCapacity(ComparedFileNavigationCommand.allCases.count)
        for command in ComparedFileNavigationCommand.allCases {
            plans.append(try plan(command, in: snapshot, budget: &budget))
        }
        try budget.finish()
        return plans
    }

    public static func commandStates(
        in snapshot: ComparedFileNavigationSnapshot
    ) throws -> ComparedFileNavigationCommandStates {
        let plans = try resolveAll(in: snapshot)
        var states: [ComparedFileNavigationCommand: ComparedFileNavigationCommandState] = [:]
        states.reserveCapacity(plans.count)
        for plan in plans { states[plan.command] = plan.commandState }
        guard let first = states[.first],
            let previous = states[.previous],
            let next = states[.next],
            let last = states[.last]
        else {
            throw ComparedFileNavigationError.staleSnapshot
        }
        return ComparedFileNavigationCommandStates(
            first: first,
            previous: previous,
            next: next,
            last: last
        )
    }

    public static func canExecute(
        _ command: ComparedFileNavigationCommand,
        in snapshot: ComparedFileNavigationSnapshot
    ) throws -> Bool {
        try plan(command, in: snapshot).canExecute
    }

    public static func validate(
        _ plan: ComparedFileNavigationPlan,
        against snapshot: ComparedFileNavigationSnapshot
    ) throws {
        var budget = ComparedFileNavigationWorkBudget(limits: snapshot.limits)
        try validateFingerprint(
            plan.expectedSnapshotFingerprint,
            against: snapshot,
            budget: &budget
        )
        if let request = plan.openPairRequest {
            try validateCurrentItem(request, against: snapshot, budget: &budget)
        }
        if let reason = plan.commandState.disabledReason {
            throw ComparedFileNavigationError.commandDisabled(reason)
        }
        try budget.finish()
    }

    public static func validate(
        _ request: ComparedFileNavigationOpenPairRequest,
        against snapshot: ComparedFileNavigationSnapshot
    ) throws {
        var budget = ComparedFileNavigationWorkBudget(limits: snapshot.limits)
        try validateFingerprint(
            request.expectedSnapshotFingerprint,
            against: snapshot,
            budget: &budget
        )
        try validateCurrentItem(request, against: snapshot, budget: &budget)
        try budget.finish()
    }

    private static func validateCurrentItem(
        _ request: ComparedFileNavigationOpenPairRequest,
        against snapshot: ComparedFileNavigationSnapshot,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws {
        guard snapshot.items.indices.contains(request.itemOrdinal) else {
            throw ComparedFileNavigationError.staleItemIdentity(request.itemIdentity)
        }
        let current = snapshot.items[request.itemOrdinal]
        guard current.identity == request.itemIdentity else {
            throw ComparedFileNavigationError.staleItemIdentity(request.itemIdentity)
        }
        let expectedRequest = try openRequest(for: current, in: snapshot)
        guard request.expectedFolderResults == snapshot.reference,
            request.itemOrdinal == expectedRequest.itemOrdinal,
            try exactID(request.resultID, expectedRequest.resultID, budget: &budget),
            request.comparisonState == expectedRequest.comparisonState,
            request.requiredOpenCapability == expectedRequest.requiredOpenCapability,
            try exactOpenSideRequest(request.left, expectedRequest.left, budget: &budget),
            try exactOpenSideRequest(request.right, expectedRequest.right, budget: &budget),
            request.executorContract == expectedRequest.executorContract
        else {
            throw ComparedFileNavigationError.staleItemState(request.itemIdentity)
        }
    }

    public static func isCurrent(
        _ plan: ComparedFileNavigationPlan,
        for snapshot: ComparedFileNavigationSnapshot
    ) throws -> Bool {
        do {
            var budget = ComparedFileNavigationWorkBudget(limits: snapshot.limits)
            try validateFingerprint(
                plan.expectedSnapshotFingerprint,
                against: snapshot,
                budget: &budget
            )
            try budget.finish()
            return true
        } catch ComparedFileNavigationError.folderResultsIdentityChanged,
            ComparedFileNavigationError.staleRevision,
            ComparedFileNavigationError.staleGeneration,
            ComparedFileNavigationError.staleItemIdentity,
            ComparedFileNavigationError.staleItemOrder,
            ComparedFileNavigationError.staleItemState,
            ComparedFileNavigationError.staleSnapshot
        {
            return false
        }
    }

    public static func isCurrent(
        _ request: ComparedFileNavigationOpenPairRequest,
        for snapshot: ComparedFileNavigationSnapshot
    ) throws -> Bool {
        do {
            try validate(request, against: snapshot)
            return true
        } catch ComparedFileNavigationError.folderResultsIdentityChanged,
            ComparedFileNavigationError.staleRevision,
            ComparedFileNavigationError.staleGeneration,
            ComparedFileNavigationError.staleItemIdentity,
            ComparedFileNavigationError.staleItemOrder,
            ComparedFileNavigationError.staleItemState,
            ComparedFileNavigationError.staleSnapshot
        {
            return false
        }
    }

    fileprivate static func validate(_ limits: ComparedFileNavigationLimits) throws {
        guard limits.maximumItemCount >= 0,
            limits.maximumItemCount <= ComparedFileNavigationLimits.hardMaximumItemCount
        else {
            throw ComparedFileNavigationError.invalidLimit(
                .items,
                value: limits.maximumItemCount
            )
        }
        guard limits.maximumSortDescriptorCount >= 0,
            limits.maximumSortDescriptorCount
                <= ComparedFileNavigationLimits.hardMaximumSortDescriptorCount
        else {
            throw ComparedFileNavigationError.invalidLimit(
                .sortDescriptors,
                value: limits.maximumSortDescriptorCount
            )
        }
        guard limits.maximumStringUTF8Bytes > 0,
            limits.maximumStringUTF8Bytes
                <= ComparedFileNavigationLimits.hardMaximumStringUTF8Bytes
        else {
            throw ComparedFileNavigationError.invalidLimit(
                .stringUTF8Bytes,
                value: limits.maximumStringUTF8Bytes
            )
        }
        guard limits.maximumTotalStringUTF8Bytes >= limits.maximumStringUTF8Bytes,
            limits.maximumTotalStringUTF8Bytes
                <= ComparedFileNavigationLimits.hardMaximumTotalStringUTF8Bytes
        else {
            throw ComparedFileNavigationError.invalidLimit(
                .totalStringUTF8Bytes,
                value: limits.maximumTotalStringUTF8Bytes
            )
        }
        guard limits.maximumWorkUnits > 0,
            limits.maximumWorkUnits <= ComparedFileNavigationLimits.hardMaximumWorkUnits
        else {
            throw ComparedFileNavigationError.invalidLimit(
                .workUnits,
                value: limits.maximumWorkUnits
            )
        }
        guard limits.cancellationCheckInterval > 0,
            limits.cancellationCheckInterval
                <= ComparedFileNavigationLimits.hardMaximumCancellationCheckInterval
        else {
            throw ComparedFileNavigationError.invalidLimit(
                .cancellationCheckInterval,
                value: limits.cancellationCheckInterval
            )
        }
    }

    fileprivate static func checkCancellation() throws {
        if Task.isCancelled { throw ComparedFileNavigationError.cancelled }
    }

    private static func plan(
        _ command: ComparedFileNavigationCommand,
        in snapshot: ComparedFileNavigationSnapshot,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> ComparedFileNavigationPlan {
        try checkCancellation()
        let startingWork = budget.completedWork
        let origin = try navigationOrigin(in: snapshot, budget: &budget)
        let target: ComparedFileNavigationItem?
        let disabledReason: ComparedFileNavigationDisabledReason?

        guard try containsNavigableItem(in: snapshot, budget: &budget) else {
            return disabledPlan(
                command,
                reason: .noNavigableItems,
                snapshot: snapshot,
                plannedWorkUnits: budget.completedWork - startingWork
            )
        }

        switch command {
        case .first:
            target = try firstNavigable(in: snapshot, budget: &budget)
            if let target, origin?.item.identity == target.identity {
                disabledReason = .alreadyAtFirst(target.identity)
            } else {
                disabledReason = nil
            }
        case .previous:
            if let origin {
                target = try previousNavigable(
                    before: origin.item.ordinal,
                    in: snapshot,
                    budget: &budget
                )
            } else {
                target = try lastNavigable(in: snapshot, budget: &budget)
            }
            disabledReason = target == nil ? .noPreviousItem : nil
        case .next:
            if let origin {
                target = try nextNavigable(
                    after: origin.item.ordinal,
                    in: snapshot,
                    budget: &budget
                )
            } else {
                target = try firstNavigable(in: snapshot, budget: &budget)
            }
            disabledReason = target == nil ? .noNextItem : nil
        case .last:
            target = try lastNavigable(in: snapshot, budget: &budget)
            if let target, origin?.item.identity == target.identity {
                disabledReason = .alreadyAtLast(target.identity)
            } else {
                disabledReason = nil
            }
        }

        if let disabledReason {
            return disabledPlan(
                command,
                reason: disabledReason,
                snapshot: snapshot,
                plannedWorkUnits: budget.completedWork - startingWork
            )
        }
        guard let target else {
            return disabledPlan(
                command,
                reason: .noNavigableItems,
                snapshot: snapshot,
                plannedWorkUnits: budget.completedWork - startingWork
            )
        }
        let originValue: ComparedFileNavigationOrigin
        if let origin {
            originValue = origin.origin
        } else {
            originValue =
                command == .previous || command == .last
                ? .endBoundary
                : .startBoundary
        }
        let state = ComparedFileNavigationCommandState(
            command: command,
            availabilityReason: .enabled(
                ComparedFileNavigationEnabledReason(
                    target: target.identity,
                    origin: originValue
                )
            ),
            targetItemIdentity: target.identity
        )
        let request = try openRequest(for: target, in: snapshot)
        return ComparedFileNavigationPlan(
            command: command,
            snapshot: snapshot,
            commandState: state,
            openPairRequest: request,
            plannedWorkUnits: budget.completedWork - startingWork
        )
    }

    private static func disabledPlan(
        _ command: ComparedFileNavigationCommand,
        reason: ComparedFileNavigationDisabledReason,
        snapshot: ComparedFileNavigationSnapshot,
        plannedWorkUnits: Int
    ) -> ComparedFileNavigationPlan {
        ComparedFileNavigationPlan(
            command: command,
            snapshot: snapshot,
            commandState: ComparedFileNavigationCommandState(
                command: command,
                availabilityReason: .disabled(reason),
                targetItemIdentity: nil
            ),
            openPairRequest: nil,
            plannedWorkUnits: plannedWorkUnits
        )
    }

    private static func navigationOrigin(
        in snapshot: ComparedFileNavigationSnapshot,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> (item: ComparedFileNavigationItem, origin: ComparedFileNavigationOrigin)? {
        for item in snapshot.items {
            try budget.consume()
            if item.visibility == .visible {
                for selectedIdentity in snapshot.selectedItemIdentities {
                    try budget.consume()
                    if selectedIdentity == item.identity {
                        return (item, .selection(item.identity))
                    }
                }
            }
        }
        if let cursorIdentity = snapshot.cursorItemIdentity {
            for item in snapshot.items {
                try budget.consume()
                if item.identity == cursorIdentity {
                    return (item, .cursor(item.identity))
                }
            }
            throw ComparedFileNavigationError.staleItemIdentity(cursorIdentity)
        }
        return nil
    }

    private static func firstNavigable(
        in snapshot: ComparedFileNavigationSnapshot,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> ComparedFileNavigationItem? {
        for item in snapshot.items {
            try budget.consume()
            if item.isNavigable { return item }
        }
        return nil
    }

    private static func containsNavigableItem(
        in snapshot: ComparedFileNavigationSnapshot,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        for item in snapshot.items {
            try budget.consume()
            if item.isNavigable { return true }
        }
        return false
    }

    private static func lastNavigable(
        in snapshot: ComparedFileNavigationSnapshot,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> ComparedFileNavigationItem? {
        for item in snapshot.items.reversed() {
            try budget.consume()
            if item.isNavigable { return item }
        }
        return nil
    }

    private static func previousNavigable(
        before ordinal: Int,
        in snapshot: ComparedFileNavigationSnapshot,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> ComparedFileNavigationItem? {
        guard ordinal > snapshot.items.startIndex else { return nil }
        for index in stride(from: ordinal - 1, through: snapshot.items.startIndex, by: -1) {
            try budget.consume()
            if snapshot.items[index].isNavigable { return snapshot.items[index] }
        }
        return nil
    }

    private static func nextNavigable(
        after ordinal: Int,
        in snapshot: ComparedFileNavigationSnapshot,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> ComparedFileNavigationItem? {
        guard ordinal < snapshot.items.index(before: snapshot.items.endIndex) else { return nil }
        for index in snapshot.items.index(after: ordinal)..<snapshot.items.endIndex {
            try budget.consume()
            if snapshot.items[index].isNavigable { return snapshot.items[index] }
        }
        return nil
    }

    private static func openRequest(
        for item: ComparedFileNavigationItem,
        in snapshot: ComparedFileNavigationSnapshot
    ) throws -> ComparedFileNavigationOpenPairRequest {
        guard let requiredOpenCapability = item.availability.requiredCapability else {
            throw ComparedFileNavigationError.staleItemState(item.identity)
        }
        guard let leftAuthority = snapshot.authorities.first(where: { $0.side == .left }) else {
            throw ComparedFileNavigationError.staleItemState(item.identity)
        }
        guard let rightAuthority = snapshot.authorities.first(where: { $0.side == .right }) else {
            throw ComparedFileNavigationError.staleItemState(item.identity)
        }

        let leftPresence: ComparedFileNavigationOpenItemPresence
        let rightPresence: ComparedFileNavigationOpenItemPresence
        let leftPath: String
        let rightPath: String
        let leftAuthorityCapability: ComparedFileNavigationAuthorityCapability
        let rightAuthorityCapability: ComparedFileNavigationAuthorityCapability
        switch (
            item.comparisonState,
            item.left,
            item.right,
            requiredOpenCapability
        ) {
        case (.identical, let left?, let right?, .identicalRegularFilePair),
            (.different, let left?, let right?, .differentRegularFilePair)
        where left.kind == .file && right.kind == .file:
            leftPresence = .regularFile
            rightPresence = .regularFile
            leftPath = left.relativePath
            rightPath = right.relativePath
            leftAuthorityCapability = .readRegularFile
            rightAuthorityCapability = .readRegularFile
        case (.missingLeft, nil, let right?, .missingLeftRegularFile)
        where right.kind == .file:
            leftPresence = .missing
            rightPresence = .regularFile
            leftPath = right.relativePath
            rightPath = right.relativePath
            leftAuthorityCapability = .validateMissingFile
            rightAuthorityCapability = .readRegularFile
        case (.missingRight, let left?, nil, .missingRightRegularFile)
        where left.kind == .file:
            leftPresence = .regularFile
            rightPresence = .missing
            leftPath = left.relativePath
            rightPath = left.relativePath
            leftAuthorityCapability = .readRegularFile
            rightAuthorityCapability = .validateMissingFile
        default:
            throw ComparedFileNavigationError.staleItemState(item.identity)
        }
        guard snapshot.openCapabilities.contains(requiredOpenCapability),
            leftAuthority.capabilities.contains(leftAuthorityCapability),
            rightAuthority.capabilities.contains(rightAuthorityCapability)
        else {
            throw ComparedFileNavigationError.staleItemState(item.identity)
        }
        let left = ComparedFileNavigationOpenSideRequest(
            side: .left,
            presence: leftPresence,
            rootURL: snapshot.leftRoot,
            relativePath: leftPath,
            authorityIdentity: leftAuthority.identity,
            requiredAuthorityCapability: leftAuthorityCapability
        )
        let right = ComparedFileNavigationOpenSideRequest(
            side: .right,
            presence: rightPresence,
            rootURL: snapshot.rightRoot,
            relativePath: rightPath,
            authorityIdentity: rightAuthority.identity,
            requiredAuthorityCapability: rightAuthorityCapability
        )
        return ComparedFileNavigationOpenPairRequest(
            expectedFolderResults: snapshot.reference,
            expectedSnapshotFingerprint: snapshot.fingerprint,
            item: item,
            requiredOpenCapability: requiredOpenCapability,
            left: left,
            right: right
        )
    }

    private static func validateFingerprint(
        _ expected: ComparedFileNavigationSnapshotFingerprint,
        against snapshot: ComparedFileNavigationSnapshot,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws {
        try checkCancellation()
        let actual = snapshot.fingerprint
        guard expected.reference.identity == actual.reference.identity else {
            throw ComparedFileNavigationError.folderResultsIdentityChanged(
                expected: expected.reference.identity,
                actual: actual.reference.identity
            )
        }
        guard expected.reference.revision == actual.reference.revision else {
            throw ComparedFileNavigationError.staleRevision(
                expected: expected.reference.revision,
                actual: actual.reference.revision
            )
        }
        guard expected.reference.generation == actual.reference.generation else {
            throw ComparedFileNavigationError.staleGeneration(
                expected: expected.reference.generation,
                actual: actual.reference.generation
            )
        }

        guard expected.items.count == actual.items.count else {
            throw ComparedFileNavigationError.staleSnapshot
        }
        var stateChangedIdentity: ComparedFileNavigationItemIdentity?
        for (expectedItem, actualItem) in zip(expected.items, actual.items) {
            try budget.consume()
            if expectedItem.identity != actualItem.identity {
                var hasSameIdentities = true
                for expectedIdentityItem in expected.items {
                    var found = false
                    for actualIdentityItem in actual.items {
                        try budget.consume()
                        if expectedIdentityItem.identity == actualIdentityItem.identity {
                            found = true
                            break
                        }
                    }
                    if !found {
                        hasSameIdentities = false
                        break
                    }
                }
                if hasSameIdentities {
                    throw ComparedFileNavigationError.staleItemOrder
                }
                throw ComparedFileNavigationError.staleItemIdentity(expectedItem.identity)
            }
            if try !exactItem(expectedItem, actualItem, budget: &budget),
                stateChangedIdentity == nil
            {
                stateChangedIdentity = expectedItem.identity
            }
        }
        if let stateChangedIdentity {
            throw ComparedFileNavigationError.staleItemState(stateChangedIdentity)
        }
        guard try exactURL(expected.leftRoot, actual.leftRoot, budget: &budget),
            try exactURL(expected.rightRoot, actual.rightRoot, budget: &budget),
            expected.filter.statuses == actual.filter.statuses,
            try exactString(
                expected.filter.pathQuery,
                actual.filter.pathQuery,
                budget: &budget
            ),
            expected.filter.kinds == actual.filter.kinds,
            expected.filter.hidden == actual.filter.hidden,
            expected.sortDescriptors == actual.sortDescriptors,
            expected.cursorItemIdentity == actual.cursorItemIdentity,
            expected.openCapabilities == actual.openCapabilities,
            expected.limits == actual.limits
        else {
            throw ComparedFileNavigationError.staleSnapshot
        }
        guard expected.authorities.count == actual.authorities.count else {
            throw ComparedFileNavigationError.staleSnapshot
        }
        for (expectedAuthority, actualAuthority) in zip(
            expected.authorities,
            actual.authorities
        ) {
            try budget.consume()
            guard expectedAuthority.identity == actualAuthority.identity,
                expectedAuthority.side == actualAuthority.side,
                try exactURL(
                    expectedAuthority.rootURL,
                    actualAuthority.rootURL,
                    budget: &budget
                ),
                expectedAuthority.capabilities == actualAuthority.capabilities
            else {
                throw ComparedFileNavigationError.staleSnapshot
            }
        }
        guard expected.selectedItemIdentities.count == actual.selectedItemIdentities.count else {
            throw ComparedFileNavigationError.staleSnapshot
        }
        for identity in expected.selectedItemIdentities {
            var found = false
            for actualIdentity in actual.selectedItemIdentities {
                try budget.consume()
                if identity == actualIdentity {
                    found = true
                    break
                }
            }
            guard found else {
                throw ComparedFileNavigationError.staleSnapshot
            }
        }
    }

    private static func exactItem(
        _ left: ComparedFileNavigationItem,
        _ right: ComparedFileNavigationItem,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        guard left.identity == right.identity,
            left.status == right.status,
            left.comparisonState == right.comparisonState,
            left.visibility == right.visibility,
            left.availability == right.availability,
            left.ordinal == right.ordinal,
            left.visibleOrdinal == right.visibleOrdinal,
            try exactID(left.resultID, right.resultID, budget: &budget),
            try exactMetadata(left.left, right.left, budget: &budget)
        else {
            return false
        }
        return try exactMetadata(left.right, right.right, budget: &budget)
    }

    private static func exactOpenSideRequest(
        _ left: ComparedFileNavigationOpenSideRequest,
        _ right: ComparedFileNavigationOpenSideRequest,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        guard left.side == right.side,
            left.presence == right.presence,
            left.authorityIdentity == right.authorityIdentity,
            left.requiredAuthorityCapability == right.requiredAuthorityCapability,
            try exactURL(left.rootURL, right.rootURL, budget: &budget)
        else {
            return false
        }
        return try exactString(left.relativePath, right.relativePath, budget: &budget)
    }

    private static func exactMetadata(
        _ left: DirectoryEntryMetadata?,
        _ right: DirectoryEntryMetadata?,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        switch (left, right) {
        case (nil, nil): true
        case (let left?, let right?):
            try exactString(left.relativePath, right.relativePath, budget: &budget)
                && left.kind == right.kind
                && left.byteCount == right.byteCount
                && comparedFileNavigationExactOptionalDate(
                    left.modificationDate,
                    right.modificationDate
                )
                && left.isHidden == right.isHidden
        default: false
        }
    }

    private static func exactID(
        _ left: DirectoryResult.ID,
        _ right: DirectoryResult.ID,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        try exactOptionalString(
            left.leftRelativePath,
            right.leftRelativePath,
            budget: &budget
        )
            && exactOptionalString(
                left.rightRelativePath,
                right.rightRelativePath,
                budget: &budget
            )
    }

    private static func exactOptionalString(
        _ left: String?,
        _ right: String?,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        switch (left, right) {
        case (nil, nil): true
        case (let left?, let right?):
            try exactString(left, right, budget: &budget)
        default: false
        }
    }

    private static func exactString(
        _ left: String,
        _ right: String,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        while true {
            try budget.consume()
            switch (leftIterator.next(), rightIterator.next()) {
            case (nil, nil): return true
            case (let left?, let right?) where left == right: continue
            default: return false
            }
        }
    }

    private static func exactURL(
        _ left: URL,
        _ right: URL,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws -> Bool {
        try exactString(left.absoluteString, right.absoluteString, budget: &budget)
    }
}

public typealias ComparedFileNavigation = ComparedFileNavigationPlanner
public typealias ComparedFileNavigationFolderResultIdentity = ComparedFileFolderResultsIdentity
public typealias ComparedFileNavigationFolderResultRevision = ComparedFileFolderResultsRevision
public typealias ComparedFileNavigationFolderResultGeneration = ComparedFileFolderResultsGeneration
public typealias ComparedFileNavigationFolderResultReference = ComparedFileFolderResultsReference

private func comparedFileNavigationExactString(_ left: String, _ right: String) -> Bool {
    left.utf8.elementsEqual(right.utf8)
}

private func comparedFileNavigationHashExactString(
    _ string: String,
    into hasher: inout Hasher
) {
    hasher.combine(string.utf8.count)
    for byte in string.utf8 { hasher.combine(byte) }
}

private func comparedFileNavigationExactOptionalString(
    _ left: String?,
    _ right: String?
) -> Bool {
    switch (left, right) {
    case (nil, nil): true
    case (let left?, let right?): comparedFileNavigationExactString(left, right)
    default: false
    }
}

private func comparedFileNavigationHashExactOptionalString(
    _ string: String?,
    into hasher: inout Hasher
) {
    guard let string else {
        hasher.combine(false)
        return
    }
    hasher.combine(true)
    comparedFileNavigationHashExactString(string, into: &hasher)
}

private func comparedFileNavigationExactID(
    _ left: DirectoryResult.ID,
    _ right: DirectoryResult.ID
) -> Bool {
    comparedFileNavigationExactOptionalString(
        left.leftRelativePath,
        right.leftRelativePath
    )
        && comparedFileNavigationExactOptionalString(
            left.rightRelativePath,
            right.rightRelativePath
        )
}

private func comparedFileNavigationHashExactID(
    _ id: DirectoryResult.ID,
    into hasher: inout Hasher
) {
    comparedFileNavigationHashExactOptionalString(id.leftRelativePath, into: &hasher)
    comparedFileNavigationHashExactOptionalString(id.rightRelativePath, into: &hasher)
}

private struct ComparedFileNavigationResultIDHash: Hashable {
    private let value: UInt64

    init(
        _ value: DirectoryResult.ID,
        budget: inout ComparedFileNavigationWorkBudget
    ) throws {
        var hash: UInt64 = 14_695_981_039_346_656_037
        try comparedFileNavigationHashExactOptionalString(
            value.leftRelativePath,
            into: &hash,
            budget: &budget
        )
        try comparedFileNavigationHashExactOptionalString(
            value.rightRelativePath,
            into: &hash,
            budget: &budget
        )
        self.value = hash
    }
}

private func comparedFileNavigationHashExactOptionalString(
    _ string: String?,
    into hash: inout UInt64,
    budget: inout ComparedFileNavigationWorkBudget
) throws {
    try budget.consume()
    guard let string else {
        hash = (hash ^ 0) &* 1_099_511_628_211
        return
    }
    hash = (hash ^ 1) &* 1_099_511_628_211
    for byte in string.utf8 {
        try budget.consume()
        hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
}

private func comparedFileNavigationExactOptionalDate(_ left: Date?, _ right: Date?) -> Bool {
    switch (left, right) {
    case (nil, nil): true
    case (let left?, let right?):
        left.timeIntervalSinceReferenceDate.bitPattern
            == right.timeIntervalSinceReferenceDate.bitPattern
    default: false
    }
}

private func comparedFileNavigationHashExactOptionalDate(
    _ date: Date?,
    into hasher: inout Hasher
) {
    guard let date else {
        hasher.combine(false)
        return
    }
    hasher.combine(true)
    hasher.combine(date.timeIntervalSinceReferenceDate.bitPattern)
}

private func comparedFileNavigationExactMetadata(
    _ left: DirectoryEntryMetadata?,
    _ right: DirectoryEntryMetadata?
) -> Bool {
    switch (left, right) {
    case (nil, nil): true
    case (let left?, let right?):
        comparedFileNavigationExactString(left.relativePath, right.relativePath)
            && left.kind == right.kind
            && left.byteCount == right.byteCount
            && comparedFileNavigationExactOptionalDate(
                left.modificationDate,
                right.modificationDate
            )
            && left.isHidden == right.isHidden
    default: false
    }
}

private func comparedFileNavigationHashExactMetadata(
    _ metadata: DirectoryEntryMetadata?,
    into hasher: inout Hasher
) {
    guard let metadata else {
        hasher.combine(false)
        return
    }
    hasher.combine(true)
    comparedFileNavigationHashExactString(metadata.relativePath, into: &hasher)
    hasher.combine(metadata.kind)
    hasher.combine(metadata.byteCount)
    comparedFileNavigationHashExactOptionalDate(metadata.modificationDate, into: &hasher)
    hasher.combine(metadata.isHidden)
}

private func comparedFileNavigationExactURL(_ left: URL, _ right: URL) -> Bool {
    comparedFileNavigationExactString(left.absoluteString, right.absoluteString)
}

private func comparedFileNavigationHashExactURL(_ url: URL, into hasher: inout Hasher) {
    comparedFileNavigationHashExactString(url.absoluteString, into: &hasher)
}

private struct ComparedFileNavigationWorkBudget {
    let limits: ComparedFileNavigationLimits
    private(set) var completedWork = 0

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0 else {
            throw ComparedFileNavigationError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        let (newValue, overflow) = completedWork.addingReportingOverflow(amount)
        guard !overflow, newValue <= limits.maximumWorkUnits else {
            throw ComparedFileNavigationError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        let previousChecks = completedWork / limits.cancellationCheckInterval
        completedWork = newValue
        if completedWork / limits.cancellationCheckInterval != previousChecks {
            try ComparedFileNavigationPlanner.checkCancellation()
        }
    }

    func finish() throws {
        try ComparedFileNavigationPlanner.checkCancellation()
    }
}
