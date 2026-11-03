import Foundation

/// Lane source-only binding from live folder results to ``ComparedFileNavigationPlanner``.
///
/// The owner keeps ``DirectoryResults`` (visible sorted/filtered order, selection, sort
/// descriptors) plus one stable ``ComparedFileNavigationItemBinding`` per logical row and
/// calls this wiring to build a ``ComparedFileNavigationSnapshot`` and plan WinMerge
/// `ID_FIRSTFILE` / `ID_PREVFILE` / `ID_NEXTFILE` / `ID_LASTFILE` as
/// ``ComparedFileNavigationCommand`` `.first` / `.previous` / `.next` / `.last`.
/// All navigation policy lives in ``ComparedFileNavigationPlanner``; this file only binds
/// owner state to it without re-sorting, re-filtering, normalizing, or touching UI.
///
/// Binding contract:
/// - Visible order is exactly `DirectoryResults.visibleResults` after the owner's filter
///   and sort descriptors. Only `isOpenableFilePair` rows plus missing-side file rows are
///   navigable; pending, non-regular-file, type-mismatch, skipped, and error rows report a
///   precise unavailability reason and are skipped by every command.
/// - No wrapping. At a boundary `.first` / `.last` report `.alreadyAtFirst` / `.alreadyAtLast`
///   and `.previous` / `.next` report `.noPreviousItem` / `.noNextItem`. With neither a
///   visible selection nor a cursor, `.first` / `.next` start at `.startBoundary` and
///   `.previous` / `.last` at `.endBoundary`.
/// - Refreshed selection: `DirectoryResults` already intersects `selectedIDs` on replacement.
///   Identities survive a refresh only via ``refreshedBindings(previous:results:cancellationCheck:)``,
///   which carries each binding to the row with byte-exact matching IDs; rows without a
///   carried identity need a fresh owner-issued identity before the next snapshot.
/// - Missing-side policy: `.leftOnly` navigates as `.missingRightRegularFile` and `.rightOnly`
///   as `.missingLeftRegularFile`. The missing side reuses the present side's relative path and
///   requires `.validateMissingFile` while the present side requires `.readRegularFile`; the
///   executor must prove absence under the exact root before representing the missing side.
/// - Exact authorities: at most one authority per side, unique identities, and each `rootURL`
///   must byte-match the corresponding `DirectoryResults` root. Capability or root drift fails
///   the snapshot or staleness validation instead of navigating.
/// - Decoded-path safety: roots are decoded with `path(percentEncoded: false)` and NUL-rejected;
///   relative paths compare as exact UTF-8 bytes with no normalization, so NFC/NFD variants are
///   distinct rows. Pass `DirectoryResults` through untouched.
/// - Stale validation: `revision` covers payload and binding changes, `generation` covers order,
///   filter, selection, cursor, authority, and capability changes. Validate every plan and
///   `ComparedFileNavigationOpenPairRequest` with `validate` / `isCurrent` against the current
///   snapshot before executing; a stale snapshot throws instead of navigating.
/// - Cancellation: each entry point runs `cancellationCheck` before delegating; the planner's
///   own budget checks throw `.cancelled` mid-plan. `CancellationError` is mapped to
///   `.cancelled`.
///
/// This file claims no command, menu, toolbar, or UI behavior. The bools in
/// `ComparedFileNavigationCommandStates.directoryPairNavigationCommandStates` exist so a
/// future UI can mirror enablement without this file driving any control.
public enum ComparedFileNavigationWiring: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    /// Owner-supplied inputs for one snapshot build. `results` carries the live visible
    /// sorted/filtered order, selection, filter, and sort descriptors.
    public struct SnapshotRequest: Sendable {
        public let identity: ComparedFileFolderResultsIdentity
        public let revision: ComparedFileFolderResultsRevision
        public let generation: ComparedFileFolderResultsGeneration
        public let results: DirectoryResults
        public let itemBindings: [ComparedFileNavigationItemBinding]
        public let cursorResultID: DirectoryResult.ID?
        public let authorities: [ComparedFileNavigationRootAuthority]
        public let openCapabilities: Set<ComparedFileNavigationOpenCapability>
        public let limits: ComparedFileNavigationLimits

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
        ) {
            self.identity = identity
            self.revision = revision
            self.generation = generation
            self.results = results
            self.itemBindings = itemBindings
            self.cursorResultID = cursorResultID
            self.authorities = authorities
            self.openCapabilities = openCapabilities
            self.limits = limits
        }
    }

    /// Carried bindings in `results` order plus the exact IDs that still need a fresh
    /// owner-issued identity. `addedResultIDs` follow `results` order.
    public struct RefreshedBindings: Sendable {
        public let bindings: [ComparedFileNavigationItemBinding]
        public let addedResultIDs: [DirectoryResult.ID]

        public init(
            bindings: [ComparedFileNavigationItemBinding],
            addedResultIDs: [DirectoryResult.ID]
        ) {
            self.bindings = bindings
            self.addedResultIDs = addedResultIDs
        }
    }

    /// Builds the planner snapshot for `request` without accessing the filesystem.
    public static func makeSnapshot(
        _ request: SnapshotRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ComparedFileNavigationSnapshot {
        do {
            try cancellationCheck()
            return try ComparedFileNavigationSnapshot(
                identity: request.identity,
                revision: request.revision,
                generation: request.generation,
                results: request.results,
                itemBindings: request.itemBindings,
                cursorResultID: request.cursorResultID,
                authorities: request.authorities,
                openCapabilities: request.openCapabilities,
                limits: request.limits
            )
        } catch is CancellationError {
            throw ComparedFileNavigationError.cancelled
        }
    }

    /// Plans one compared-file command against the snapshot built from `request`.
    public static func plan(
        _ command: ComparedFileNavigationCommand,
        request: SnapshotRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ComparedFileNavigationPlan {
        do {
            try cancellationCheck()
            return try ComparedFileNavigationPlanner.plan(command, in: makeSnapshot(request, cancellationCheck: cancellationCheck))
        } catch is CancellationError {
            throw ComparedFileNavigationError.cancelled
        }
    }

    /// Plans every command's enablement and target against the snapshot built from `request`.
    public static func commandStates(
        request: SnapshotRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ComparedFileNavigationCommandStates {
        do {
            try cancellationCheck()
            return try ComparedFileNavigationPlanner.commandStates(in: makeSnapshot(request, cancellationCheck: cancellationCheck))
        } catch is CancellationError {
            throw ComparedFileNavigationError.cancelled
        }
    }

    /// Plans all four commands in `ComparedFileNavigationCommand.allCases` order.
    public static func resolveAll(
        request: SnapshotRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> [ComparedFileNavigationResolution] {
        do {
            try cancellationCheck()
            return try ComparedFileNavigationPlanner.resolveAll(in: makeSnapshot(request, cancellationCheck: cancellationCheck))
        } catch is CancellationError {
            throw ComparedFileNavigationError.cancelled
        }
    }

    /// Revalidates a previously planned navigation against a freshly built snapshot.
    public static func validate(
        _ plan: ComparedFileNavigationPlan,
        against snapshot: ComparedFileNavigationSnapshot
    ) throws {
        try ComparedFileNavigationPlanner.validate(plan, against: snapshot)
    }

    /// Reports whether a previously planned navigation is still current for `snapshot`.
    public static func isCurrent(
        _ plan: ComparedFileNavigationPlan,
        for snapshot: ComparedFileNavigationSnapshot
    ) throws -> Bool {
        try ComparedFileNavigationPlanner.isCurrent(plan, for: snapshot)
    }

    /// Carries owner identities to rows whose IDs still match byte-exactly after a folder
    /// refresh. Each previous binding is used at most once; a second exact match for one
    /// result ID fails closed as `.duplicateResultID` instead of aliasing two rows.
    /// Runs `cancellationCheck` once per 1,024 rows and maps `CancellationError` to `.cancelled`.
    public static func refreshedBindings(
        previous: [ComparedFileNavigationItemBinding],
        results: [DirectoryResult],
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> RefreshedBindings {
        do {
            try cancellationCheck()
            var indexByExactKey: [String: [Int]] = [:]
            indexByExactKey.reserveCapacity(previous.count)
            for (index, binding) in previous.enumerated() {
                if index % 1_024 == 0 { try cancellationCheck() }
                indexByExactKey[exactKey(for: binding.resultID), default: []].append(index)
            }
            var used = Set<Int>(minimumCapacity: min(previous.count, results.count))
            var bindings: [ComparedFileNavigationItemBinding] = []
            bindings.reserveCapacity(results.count)
            var addedResultIDs: [DirectoryResult.ID] = []
            for result in results {
                if bindings.count % 1_024 == 0 { try cancellationCheck() }
                let candidates = indexByExactKey[exactKey(for: result.id)] ?? []
                var carried: ComparedFileNavigationItemBinding?
                for index in candidates where !used.contains(index) {
                    if carried == nil {
                        used.insert(index)
                        carried = previous[index]
                    } else {
                        throw ComparedFileNavigationError.duplicateResultID(result.id)
                    }
                }
                if let carried {
                    bindings.append(carried)
                } else {
                    addedResultIDs.append(result.id)
                }
            }
            return RefreshedBindings(bindings: bindings, addedResultIDs: addedResultIDs)
        } catch is CancellationError {
            throw ComparedFileNavigationError.cancelled
        }
    }

    /// Length-prefixed exact key: relative paths cannot be confused across the separator
    /// because each side contributes its byte count. NUL-containing paths never match a
    /// validated snapshot row, which rejects them during snapshot construction.
    private static func exactKey(for id: DirectoryResult.ID) -> String {
        let left = id.leftRelativePath ?? ""
        let right = id.rightRelativePath ?? ""
        let leftCount = id.leftRelativePath == nil ? -1 : left.utf8.count
        let rightCount = id.rightRelativePath == nil ? -1 : right.utf8.count
        return "\(leftCount):\(left)\n\(rightCount):\(right)"
    }
}
