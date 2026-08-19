import Darwin
import Foundation

public struct FolderRelativePath: Hashable, Sendable {
    public let rawValue: String
    public let components: [String]

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty,
              !rawValue.hasPrefix("/"),
              !rawValue.contains("\0") else {
            throw FolderFileOperationError.invalidRelativePath(rawValue)
        }

        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw FolderFileOperationError.invalidRelativePath(rawValue)
        }

        self.rawValue = rawValue
        self.components = components
    }
}

public enum FolderFileCollisionPolicy: Equatable, Sendable {
    case fail
    case skip
    case replaceKeepingBackup
}

public enum FolderFileDeletionPolicy: Equatable, Sendable {
    case moveToBackup
}

public struct FolderCopyPlan: Equatable, Sendable {
    public let sourceRoot: URL
    public let source: FolderRelativePath
    public let destinationRoot: URL
    public let destination: FolderRelativePath
    public let collisionPolicy: FolderFileCollisionPolicy

    public init(
        sourceRoot: URL,
        source: FolderRelativePath,
        destinationRoot: URL,
        destination: FolderRelativePath,
        collisionPolicy: FolderFileCollisionPolicy = .fail
    ) {
        self.sourceRoot = sourceRoot
        self.source = source
        self.destinationRoot = destinationRoot
        self.destination = destination
        self.collisionPolicy = collisionPolicy
    }
}

public struct FolderMovePlan: Equatable, Sendable {
    public let sourceRoot: URL
    public let source: FolderRelativePath
    public let destinationRoot: URL
    public let destination: FolderRelativePath
    public let collisionPolicy: FolderFileCollisionPolicy

    public init(
        sourceRoot: URL,
        source: FolderRelativePath,
        destinationRoot: URL,
        destination: FolderRelativePath,
        collisionPolicy: FolderFileCollisionPolicy = .fail
    ) {
        self.sourceRoot = sourceRoot
        self.source = source
        self.destinationRoot = destinationRoot
        self.destination = destination
        self.collisionPolicy = collisionPolicy
    }
}

public struct FolderDeletePlan: Equatable, Sendable {
    public let root: URL
    public let target: FolderRelativePath
    public let deletionPolicy: FolderFileDeletionPolicy

    public init(
        root: URL,
        target: FolderRelativePath,
        deletionPolicy: FolderFileDeletionPolicy = .moveToBackup
    ) {
        self.root = root
        self.target = target
        self.deletionPolicy = deletionPolicy
    }
}

public enum FolderSynchronizationStep: Equatable, Sendable {
    case copy(
        source: FolderRelativePath,
        destination: FolderRelativePath,
        collisionPolicy: FolderFileCollisionPolicy
    )
    case delete(destination: FolderRelativePath, deletionPolicy: FolderFileDeletionPolicy)
}

public struct FolderSynchronizationPlan: Equatable, Sendable {
    public let sourceRoot: URL
    public let destinationRoot: URL
    public let steps: [FolderSynchronizationStep]

    public init(
        sourceRoot: URL,
        destinationRoot: URL,
        steps: [FolderSynchronizationStep]
    ) {
        self.sourceRoot = sourceRoot
        self.destinationRoot = destinationRoot
        self.steps = steps
    }
}

public enum FolderFileOperationPlan: Equatable, Sendable {
    case copy(FolderCopyPlan)
    case move(FolderMovePlan)
    case delete(FolderDeletePlan)
    case synchronize(FolderSynchronizationPlan)
}

public enum FolderFileExecutionMode: Equatable, Sendable {
    case dryRun
    case perform
}

public enum FolderFileOperationKind: Equatable, Sendable {
    case copy
    case move
    case delete
}

public enum FolderFileOperationStatus: Equatable, Sendable {
    case validated
    case completed
    case completedWithWarning
    case skipped
}

public struct FolderFileOperationRecord: Equatable, Sendable {
    public let kind: FolderFileOperationKind
    public let source: URL?
    public let destination: URL
    public let status: FolderFileOperationStatus
    public let backup: URL?

    public init(
        kind: FolderFileOperationKind,
        source: URL?,
        destination: URL,
        status: FolderFileOperationStatus,
        backup: URL? = nil
    ) {
        self.kind = kind
        self.source = source
        self.destination = destination
        self.status = status
        self.backup = backup
    }
}

public enum FolderFileOperationWarning: Equatable, Sendable {
    case sourceCleanupIncomplete(source: String, recovery: String?, reason: String)
    case sourceBackupPreserved(String)
    case backupNameFallback(String)
    case cleanupArtifactPreserved(String)
}

public struct FolderFileOperationResult: Equatable, Sendable {
    public let mode: FolderFileExecutionMode
    public let records: [FolderFileOperationRecord]
    public let warnings: [FolderFileOperationWarning]

    public init(
        mode: FolderFileExecutionMode,
        records: [FolderFileOperationRecord],
        warnings: [FolderFileOperationWarning] = []
    ) {
        self.mode = mode
        self.records = records
        self.warnings = warnings
    }
}

public enum FolderFileOperationFailureCode: Equatable, Sendable {
    case cancelled
    case changedDuringOperation
    case inputRejected
    case safetyUnsupported
    case fileSystem
    case outcomeUncertain
}

public struct FolderFileOperationFailure: Equatable, Sendable {
    public let code: FolderFileOperationFailureCode
    public let path: String?
    public let message: String

    public init(code: FolderFileOperationFailureCode, path: String?, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}

public enum FolderFileOperationError: Error, LocalizedError, Equatable, Sendable {
    case cancelled
    case invalidRoot(String)
    case rootNotDirectory(String)
    case invalidRelativePath(String)
    case pathEscapesRoot(path: String, root: String)
    case itemNotFound(String)
    case destinationParentMissing(String)
    case destinationCollision(String)
    case symbolicLinkNotAllowed(String)
    case aliasNotAllowed(String)
    case volumeBoundaryNotAllowed(String)
    case unsupportedItem(String)
    case sourceDestinationOverlap(source: String, destination: String)
    case conflictingPlan(first: String, second: String)
    case safetyRequirementsUnsupported(operation: FolderFileOperationKind, path: String, reason: String)
    case itemChanged(String)
    case operationFailed(kind: FolderFileOperationKind, path: String, reason: String)
    case outcomeUncertain(path: String, recovery: String?)
    case partialFailure(
        completed: [FolderFileOperationRecord],
        warnings: [FolderFileOperationWarning],
        failure: FolderFileOperationFailure
    )

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Folder operation was cancelled before the next filesystem change."
        case let .invalidRoot(path):
            "Folder operation root is not an absolute file URL: \(path)"
        case let .rootNotDirectory(path):
            "Folder operation root is not a directory: \(path)"
        case let .invalidRelativePath(path):
            "Folder operation path must be a nonempty relative path without '.', '..', or empty components: \(path)"
        case let .pathEscapesRoot(path, root):
            "Folder operation path escapes its root. Path: \(path), root: \(root)"
        case let .itemNotFound(path):
            "Folder operation item does not exist: \(path)"
        case let .destinationParentMissing(path):
            "Folder operation destination parent is missing or is not a directory: \(path)"
        case let .destinationCollision(path):
            "Folder operation destination already exists and replacement was not explicitly authorized: \(path)"
        case let .symbolicLinkNotAllowed(path):
            "Folder operations do not follow or copy symbolic links: \(path)"
        case let .aliasNotAllowed(path):
            "Folder operations do not follow or copy Finder aliases: \(path)"
        case let .volumeBoundaryNotAllowed(path):
            "Folder operation item crosses a mounted volume boundary: \(path)"
        case let .unsupportedItem(path):
            "Folder operations support only regular files and directories: \(path)"
        case let .sourceDestinationOverlap(source, destination):
            "Folder operation source and destination overlap. Source: \(source), destination: \(destination)"
        case let .conflictingPlan(first, second):
            "Folder operation plan contains overlapping mutations: \(first) and \(second)"
        case let .safetyRequirementsUnsupported(operation, path, reason):
            "\(operation.description.capitalized) is disabled for safety at \(path): \(reason)"
        case let .itemChanged(path):
            "Folder operation item changed after validation: \(path)"
        case let .operationFailed(kind, path, reason):
            "\(kind.description.capitalized) failed at \(path): \(reason)"
        case let .outcomeUncertain(path, recovery):
            if let recovery {
                "Folder operation outcome at \(path) needs review. Recovery data may remain at \(recovery)."
            } else {
                "Folder operation outcome at \(path) needs review."
            }
        case let .partialFailure(completed, _, failure):
            "Folder synchronization stopped after \(completed.count) completed step(s): \(failure.message)"
        }
    }
}

public enum FolderFileOperations {
    @TaskLocal
    static var accessObserver: (@Sendable () -> Void)?

    public static func dryRun(_ plan: FolderFileOperationPlan) async throws -> FolderFileOperationResult {
        try await execute(plan, mode: .dryRun)
    }

    public static func perform(_ plan: FolderFileOperationPlan) async throws -> FolderFileOperationResult {
        try await execute(plan, mode: .perform)
    }

    public static func execute(
        _ plan: FolderFileOperationPlan,
        mode: FolderFileExecutionMode
    ) async throws -> FolderFileOperationResult {
        let accessObserver = accessObserver
        let worker = Task.detached {
            try $accessObserver.withValue(accessObserver) {
                try executeBlocking(plan, mode: mode)
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func executeBlocking(
        _ plan: FolderFileOperationPlan,
        mode: FolderFileExecutionMode
    ) throws -> FolderFileOperationResult {
        try checkCancellation()
        guard mode == .dryRun else {
            throw FolderFileOperationError.safetyRequirementsUnsupported(
                operation: plan.primaryKind,
                path: plan.primaryPath,
                reason: "Descriptor-only staging, durable commit, and identity-checked recovery guarantees are not yet complete."
            )
        }
        let roots = plan.roots
        let access = roots.map {
            observeAccess()
            return ($0, $0.startAccessingSecurityScopedResource())
        }
        defer {
            for (root, started) in access where started {
                observeAccess()
                root.stopAccessingSecurityScopedResource()
            }
        }

        let prepared: [PreparedAction]
        do {
            prepared = try prepare(plan)
        } catch let error as FolderFileOperationError {
            throw error
        } catch {
            throw FolderFileOperationError.operationFailed(
                kind: plan.primaryKind,
                path: roots.first?.path ?? "",
                reason: error.localizedDescription
            )
        }
        return FolderFileOperationResult(
            mode: mode,
            records: prepared.map(\.validationRecord)
        )
    }
}

private extension FolderFileOperations {
    struct FileIdentity: Equatable, Hashable {
        let device: dev_t
        let inode: ino_t
    }

    enum ItemKind: Equatable {
        case file
        case directory
    }

    struct ItemState: Equatable {
        let relativePath: String
        let identity: FileIdentity
        let kind: ItemKind
        let size: off_t
        let modificationSeconds: Int
        let modificationNanoseconds: Int
        let changeSeconds: Int
        let changeNanoseconds: Int
    }

    struct RootContext {
        let url: URL
        let identity: FileIdentity
        let device: dev_t
    }

    enum PathRole: Equatable {
        case source
        case destination
    }

    struct PathIdentity {
        let url: URL
        let identity: FileIdentity
    }

    struct ResolvedItem {
        let url: URL
        let ancestors: [PathIdentity]
        let snapshot: [ItemState]?
    }

    struct PreparedAction {
        let kind: FolderFileOperationKind
        let sourceURL: URL?
        let destinationURL: URL
        let sourceRoot: RootContext?
        let destinationRoot: RootContext
        let sourceAncestors: [PathIdentity]
        let destinationAncestors: [PathIdentity]
        let sourceSnapshot: [ItemState]?
        let destinationSnapshot: [ItemState]?
        let sourceComponents: [String]?
        let destinationComponents: [String]
        let collisionPolicy: FolderFileCollisionPolicy?
        let deletionPolicy: FolderFileDeletionPolicy?
        let skipsExistingDestination: Bool

        var validationRecord: FolderFileOperationRecord {
            FolderFileOperationRecord(
                kind: kind,
                source: sourceURL,
                destination: destinationURL,
                status: skipsExistingDestination ? .skipped : .validated
            )
        }
    }

    struct ActionResult {
        let record: FolderFileOperationRecord
        let warnings: [FolderFileOperationWarning]
    }

    struct InstalledItem {
        let backup: URL?
        let warning: FolderFileOperationWarning?
    }

    struct StagedItem {
        let containerURL: URL
        let containerIdentity: FileIdentity
        let url: URL
        let snapshot: [ItemState]
    }

    enum PlanAccessMode {
        case read
        case write
    }

    struct PlanAccess {
        let mode: PlanAccessMode
        let path: String
        let device: dev_t
        let components: [String]
        let identity: FileIdentity?
    }

    final class PlanAccessNode {
        var exactRead: PlanAccess?
        var exactWrite: PlanAccess?
        var subtreeRead: PlanAccess?
        var subtreeWrite: PlanAccess?
        var children: [String: PlanAccessNode] = [:]
    }

    final class IdentityAccesses {
        var read: PlanAccess?
        var write: PlanAccess?
    }

    static func prepare(_ plan: FolderFileOperationPlan) throws -> [PreparedAction] {
        observeAccess()
        switch plan {
        case let .copy(plan):
            return [try prepareCopy(plan)]
        case let .move(plan):
            return [try prepareMove(plan)]
        case let .delete(plan):
            return [try prepareDelete(plan)]
        case let .synchronize(plan):
            return try prepareSynchronization(plan)
        }
    }

    static func prepareCopy(_ plan: FolderCopyPlan) throws -> PreparedAction {
        let sourceRoot = try validateRoot(plan.sourceRoot)
        let destinationRoot = try validateRoot(plan.destinationRoot)
        return try prepareTransfer(
            kind: .copy,
            sourceRoot: sourceRoot,
            source: plan.source,
            destinationRoot: destinationRoot,
            destination: plan.destination,
            collisionPolicy: plan.collisionPolicy
        )
    }

    static func prepareMove(_ plan: FolderMovePlan) throws -> PreparedAction {
        let sourceRoot = try validateRoot(plan.sourceRoot)
        let destinationRoot = try validateRoot(plan.destinationRoot)
        return try prepareTransfer(
            kind: .move,
            sourceRoot: sourceRoot,
            source: plan.source,
            destinationRoot: destinationRoot,
            destination: plan.destination,
            collisionPolicy: plan.collisionPolicy
        )
    }

    static func prepareDelete(_ plan: FolderDeletePlan) throws -> PreparedAction {
        let root = try validateRoot(plan.root)
        let target = try resolve(
            plan.target,
            under: root,
            role: .destination,
            finalMayBeMissing: false,
            scanFinalItem: true
        )
        return PreparedAction(
            kind: .delete,
            sourceURL: nil,
            destinationURL: target.url,
            sourceRoot: nil,
            destinationRoot: root,
            sourceAncestors: [],
            destinationAncestors: target.ancestors,
            sourceSnapshot: nil,
            destinationSnapshot: target.snapshot,
            sourceComponents: nil,
            destinationComponents: plan.target.components,
            collisionPolicy: nil,
            deletionPolicy: plan.deletionPolicy,
            skipsExistingDestination: false
        )
    }

    static func prepareSynchronization(_ plan: FolderSynchronizationPlan) throws -> [PreparedAction] {
        let sourceRoot = try validateRoot(plan.sourceRoot)
        let destinationRoot = try validateRoot(plan.destinationRoot)
        var actions: [PreparedAction] = []
        actions.reserveCapacity(plan.steps.count)

        for step in plan.steps {
            try checkCancellation()
            switch step {
            case let .copy(source, destination, collisionPolicy):
                actions.append(try prepareTransfer(
                    kind: .copy,
                    sourceRoot: sourceRoot,
                    source: source,
                    destinationRoot: destinationRoot,
                    destination: destination,
                    collisionPolicy: collisionPolicy
                ))
            case let .delete(destination, deletionPolicy):
                let item = try resolve(
                    destination,
                    under: destinationRoot,
                    role: .destination,
                    finalMayBeMissing: false,
                    scanFinalItem: true
                )
                actions.append(PreparedAction(
                    kind: .delete,
                    sourceURL: nil,
                    destinationURL: item.url,
                    sourceRoot: nil,
                    destinationRoot: destinationRoot,
                    sourceAncestors: [],
                    destinationAncestors: item.ancestors,
                    sourceSnapshot: nil,
                    destinationSnapshot: item.snapshot,
                    sourceComponents: nil,
                    destinationComponents: destination.components,
                    collisionPolicy: nil,
                    deletionPolicy: deletionPolicy,
                    skipsExistingDestination: false
                ))
            }
        }

        try validatePlanConflicts(actions)
        return actions
    }

    static func prepareTransfer(
        kind: FolderFileOperationKind,
        sourceRoot: RootContext,
        source: FolderRelativePath,
        destinationRoot: RootContext,
        destination: FolderRelativePath,
        collisionPolicy: FolderFileCollisionPolicy
    ) throws -> PreparedAction {
        let sourceItem = try resolve(
            source,
            under: sourceRoot,
            role: .source,
            finalMayBeMissing: false,
            scanFinalItem: true
        )
        let destinationItem = try resolve(
            destination,
            under: destinationRoot,
            role: .destination,
            finalMayBeMissing: true,
            scanFinalItem: true
        )

        guard !pathsOverlap(sourceItem.url, destinationItem.url),
              !destinationAncestorsContainSource(
                  destinationItem.ancestors,
                  sourceIdentity: sourceItem.snapshot?.first?.identity
              ),
              !sourceAncestorsContainDestination(
                  sourceItem.ancestors,
                  destinationIdentity: destinationItem.snapshot?.first?.identity
              ) else {
            throw FolderFileOperationError.sourceDestinationOverlap(
                source: sourceItem.url.path,
                destination: destinationItem.url.path
            )
        }
        if let sourceIdentity = sourceItem.snapshot?.first?.identity,
           sourceIdentity == destinationItem.snapshot?.first?.identity {
            throw FolderFileOperationError.sourceDestinationOverlap(
                source: sourceItem.url.path,
                destination: destinationItem.url.path
            )
        }

        let destinationExists = destinationItem.snapshot != nil
        switch (destinationExists, collisionPolicy) {
        case (true, .fail):
            throw FolderFileOperationError.destinationCollision(destinationItem.url.path)
        case (true, .skip):
            break
        case (true, .replaceKeepingBackup), (false, _):
            break
        }

        return PreparedAction(
            kind: kind,
            sourceURL: sourceItem.url,
            destinationURL: destinationItem.url,
            sourceRoot: sourceRoot,
            destinationRoot: destinationRoot,
            sourceAncestors: sourceItem.ancestors,
            destinationAncestors: destinationItem.ancestors,
            sourceSnapshot: sourceItem.snapshot,
            destinationSnapshot: destinationItem.snapshot,
            sourceComponents: source.components,
            destinationComponents: destination.components,
            collisionPolicy: collisionPolicy,
            deletionPolicy: nil,
            skipsExistingDestination: destinationExists && collisionPolicy == .skip
        )
    }

    static func validatePlanConflicts(_ actions: [PreparedAction]) throws {
        var roots: [dev_t: PlanAccessNode] = [:]
        var identities: [FileIdentity: IdentityAccesses] = [:]

        for action in actions {
            for access in planAccesses(for: action) {
                if let identity = access.identity {
                    let identityAccesses = identities[identity] ?? IdentityAccesses()
                    if let conflict = access.mode == .write
                        ? identityAccesses.write ?? identityAccesses.read
                        : identityAccesses.write {
                        throw planConflict(conflict, access)
                    }
                    switch access.mode {
                    case .read:
                        identityAccesses.read = identityAccesses.read ?? access
                    case .write:
                        identityAccesses.write = identityAccesses.write ?? access
                    }
                    identities[identity] = identityAccesses
                }

                let root = roots[access.device] ?? PlanAccessNode()
                try insert(access, into: root)
                roots[access.device] = root
            }
        }
    }

    static func planAccesses(for action: PreparedAction) -> [PlanAccess] {
        var result: [PlanAccess] = []
        if let source = action.sourceURL, let sourceRoot = action.sourceRoot {
            result.append(PlanAccess(
                mode: .read,
                path: source.path,
                device: sourceRoot.device,
                components: conflictComponents(for: source),
                identity: action.sourceSnapshot?.first?.identity
            ))
        }
        result.append(PlanAccess(
            mode: action.skipsExistingDestination ? .read : .write,
            path: action.destinationURL.path,
            device: action.destinationRoot.device,
            components: conflictComponents(for: action.destinationURL),
            identity: action.destinationSnapshot?.first?.identity
        ))
        return result
    }

    static func insert(_ access: PlanAccess, into root: PlanAccessNode) throws {
        var node = root
        var visited = [root]

        for component in access.components {
            if let conflict = access.mode == .write
                ? node.exactWrite ?? node.exactRead
                : node.exactWrite {
                throw planConflict(conflict, access)
            }
            let child = node.children[component] ?? PlanAccessNode()
            node.children[component] = child
            node = child
            visited.append(child)
        }

        if let conflict = access.mode == .write
            ? node.subtreeWrite ?? node.subtreeRead
            : node.subtreeWrite {
            throw planConflict(conflict, access)
        }

        switch access.mode {
        case .read:
            node.exactRead = node.exactRead ?? access
            for visitedNode in visited {
                visitedNode.subtreeRead = visitedNode.subtreeRead ?? access
            }
        case .write:
            node.exactWrite = node.exactWrite ?? access
            for visitedNode in visited {
                visitedNode.subtreeWrite = visitedNode.subtreeWrite ?? access
            }
        }
    }

    static func planConflict(_ first: PlanAccess, _ second: PlanAccess) -> FolderFileOperationError {
        FolderFileOperationError.conflictingPlan(first: first.path, second: second.path)
    }

    static func conflictComponents(for url: URL) -> [String] {
        let locale = Locale(identifier: "en_US_POSIX")
        return url.standardizedFileURL.pathComponents.compactMap { component -> String? in
            guard component != "/" else { return nil }
            return component
                .decomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive], locale: locale)
                .decomposedStringWithCanonicalMapping
        }
    }

    static func execute(_ action: PreparedAction) throws -> ActionResult {
        observeAccess()
        try revalidate(action)
        if action.skipsExistingDestination {
            return ActionResult(record: action.validationRecord, warnings: [])
        }

        switch action.kind {
        case .copy:
            return try executeCopy(action)
        case .move:
            return try executeMove(action)
        case .delete:
            return try executeDelete(action)
        }
    }

    static func executeCopy(_ action: PreparedAction) throws -> ActionResult {
        guard let source = action.sourceURL,
              let sourceSnapshot = action.sourceSnapshot,
              let sourceRoot = action.sourceRoot,
              let sourceComponents = action.sourceComponents,
              let collisionPolicy = action.collisionPolicy else {
            preconditionFailure("Invalid prepared copy action")
        }
        let staged = try stageCopy(
            kind: .copy,
            sourceRoot: sourceRoot,
            sourceComponents: sourceComponents,
            destination: action.destinationURL,
            destinationComponents: action.destinationComponents,
            sourceSnapshot: sourceSnapshot,
            destinationRoot: action.destinationRoot,
            sourceAncestors: action.sourceAncestors,
            destinationAncestors: action.destinationAncestors
        )
        try revalidate(action)
        let installed = try install(
            staged: staged,
            at: action.destinationURL,
            expectedDestination: action.destinationSnapshot,
            collisionPolicy: collisionPolicy,
            expectedParentIdentity: action.destinationAncestors.last?.identity ?? action.destinationRoot.identity,
            destinationRoot: action.destinationRoot,
            destinationComponents: action.destinationComponents,
            kind: .copy
        )
        return ActionResult(
            record: FolderFileOperationRecord(
                kind: .copy,
                source: source,
                destination: action.destinationURL,
                status: installed.warning == nil ? .completed : .completedWithWarning,
                backup: installed.backup
            ),
            warnings: installed.warning.map { [$0] } ?? []
        )
    }

    static func executeMove(_ action: PreparedAction) throws -> ActionResult {
        guard let source = action.sourceURL,
              let sourceSnapshot = action.sourceSnapshot,
              let sourceRoot = action.sourceRoot,
              let sourceComponents = action.sourceComponents,
              let collisionPolicy = action.collisionPolicy else {
            preconditionFailure("Invalid prepared move action")
        }
        let staged = try stageCopy(
            kind: .move,
            sourceRoot: sourceRoot,
            sourceComponents: sourceComponents,
            destination: action.destinationURL,
            destinationComponents: action.destinationComponents,
            sourceSnapshot: sourceSnapshot,
            destinationRoot: action.destinationRoot,
            sourceAncestors: action.sourceAncestors,
            destinationAncestors: action.destinationAncestors
        )
        try revalidate(action)
        let installed = try install(
            staged: staged,
            at: action.destinationURL,
            expectedDestination: action.destinationSnapshot,
            collisionPolicy: collisionPolicy,
            expectedParentIdentity: action.destinationAncestors.last?.identity ?? action.destinationRoot.identity,
            destinationRoot: action.destinationRoot,
            destinationComponents: action.destinationComponents,
            kind: .move
        )

        var warnings = installed.warning.map { [$0] } ?? []
        do {
            let sourceBackup = try moveToBackup(
                source,
                expected: sourceSnapshot,
                root: sourceRoot,
                components: sourceComponents,
                parentIdentity: action.sourceAncestors.last?.identity ?? sourceRoot.identity
            )
            warnings.append(.sourceBackupPreserved(sourceBackup.path))
        } catch let error as FolderFileOperationError {
            if error == .cancelled {
                let warning = FolderFileOperationWarning.sourceCleanupIncomplete(
                    source: source.path,
                    recovery: error.recoveryPath,
                    reason: error.localizedDescription
                )
                let record = FolderFileOperationRecord(
                    kind: .move,
                    source: source,
                    destination: action.destinationURL,
                    status: .completedWithWarning,
                    backup: installed.backup
                )
                throw FolderFileOperationError.partialFailure(
                    completed: [record],
                    warnings: installed.warning.map { [$0, warning] } ?? [warning],
                    failure: failure(from: error)
                )
            }
            warnings.append(.sourceCleanupIncomplete(
                source: source.path,
                recovery: error.recoveryPath,
                reason: error.localizedDescription
            ))
        } catch {
            warnings.append(.sourceCleanupIncomplete(
                source: source.path,
                recovery: nil,
                reason: error.localizedDescription
            ))
        }

        return ActionResult(
            record: FolderFileOperationRecord(
                kind: .move,
                source: source,
                destination: action.destinationURL,
                status: warnings.isEmpty ? .completed : .completedWithWarning,
                backup: installed.backup
            ),
            warnings: warnings
        )
    }

    static func executeDelete(_ action: PreparedAction) throws -> ActionResult {
        guard let destinationSnapshot = action.destinationSnapshot,
              let deletionPolicy = action.deletionPolicy else {
            preconditionFailure("Invalid prepared delete action")
        }
        let backup: URL?
        switch deletionPolicy {
        case .moveToBackup:
            backup = try moveToBackup(
                action.destinationURL,
                expected: destinationSnapshot,
                root: action.destinationRoot,
                components: action.destinationComponents,
                parentIdentity: action.destinationAncestors.last?.identity ?? action.destinationRoot.identity
            )
        }

        return ActionResult(
            record: FolderFileOperationRecord(
                kind: .delete,
                source: nil,
                destination: action.destinationURL,
                status: .completed,
                backup: backup
            ),
            warnings: []
        )
    }

    static func validateRoot(_ suppliedURL: URL) throws -> RootContext {
        guard suppliedURL.isFileURL, suppliedURL.path.hasPrefix("/") else {
            throw FolderFileOperationError.invalidRoot(suppliedURL.absoluteString)
        }

        let supplied = suppliedURL.standardizedFileURL
        if let suppliedInformation = try fileInformation(at: supplied), suppliedInformation.kind == nil {
            throw FolderFileOperationError.symbolicLinkNotAllowed(supplied.path)
        }
        let canonical = supplied.resolvingSymlinksInPath().standardizedFileURL
        guard let information = try fileInformation(at: canonical) else {
            throw FolderFileOperationError.rootNotDirectory(canonical.path)
        }
        guard information.kind == .directory else {
            throw FolderFileOperationError.rootNotDirectory(canonical.path)
        }
        try rejectAlias(at: canonical)
        return RootContext(url: canonical, identity: information.identity, device: information.identity.device)
    }

    static func resolve(
        _ relativePath: FolderRelativePath,
        under root: RootContext,
        role: PathRole,
        finalMayBeMissing: Bool,
        scanFinalItem: Bool
    ) throws -> ResolvedItem {
        try revalidateRoot(root)
        var current = root.url
        var ancestors: [PathIdentity] = []

        for (index, component) in relativePath.components.enumerated() {
            try checkCancellation()
            current = current.appending(path: component).standardizedFileURL
            guard isContained(current, by: root.url) else {
                throw FolderFileOperationError.pathEscapesRoot(path: current.path, root: root.url.path)
            }

            let isFinal = index == relativePath.components.count - 1
            guard let information = try fileInformation(at: current) else {
                if isFinal, finalMayBeMissing {
                    return ResolvedItem(url: current, ancestors: ancestors, snapshot: nil)
                }
                if isFinal {
                    throw FolderFileOperationError.itemNotFound(current.path)
                }
                if role == .source {
                    throw FolderFileOperationError.itemNotFound(current.path)
                }
                throw FolderFileOperationError.destinationParentMissing(current.path)
            }
            guard information.kind != nil else {
                throw FolderFileOperationError.symbolicLinkNotAllowed(current.path)
            }
            try rejectAlias(at: current)
            guard information.identity.device == root.device else {
                throw FolderFileOperationError.volumeBoundaryNotAllowed(current.path)
            }

            if !isFinal {
                guard information.kind == .directory else {
                    if role == .source {
                        throw FolderFileOperationError.itemNotFound(current.path)
                    }
                    throw FolderFileOperationError.destinationParentMissing(current.path)
                }
                ancestors.append(PathIdentity(url: current, identity: information.identity))
            } else {
                let snapshot = scanFinalItem
                    ? try snapshotTree(at: current, rootDevice: root.device, kind: role.operationKind)
                    : nil
                return ResolvedItem(url: current, ancestors: ancestors, snapshot: snapshot)
            }
        }

        preconditionFailure("FolderRelativePath cannot be empty")
    }

    static func snapshotTree(
        at url: URL,
        rootDevice: dev_t,
        kind: FolderFileOperationKind
    ) throws -> [ItemState] {
        var result: [ItemState] = []
        try appendSnapshot(
            at: url,
            relativePath: "",
            rootDevice: rootDevice,
            kind: kind,
            to: &result
        )
        return result
    }

    static func appendSnapshot(
        at url: URL,
        relativePath: String,
        rootDevice: dev_t,
        kind: FolderFileOperationKind,
        to result: inout [ItemState]
    ) throws {
        try checkCancellation()
        guard let information = try fileInformation(at: url) else {
            throw FolderFileOperationError.itemChanged(url.path)
        }
        guard let itemKind = information.kind else {
            throw FolderFileOperationError.symbolicLinkNotAllowed(url.path)
        }
        try rejectAlias(at: url)
        guard information.identity.device == rootDevice else {
            throw FolderFileOperationError.volumeBoundaryNotAllowed(url.path)
        }
        result.append(ItemState(
            relativePath: relativePath,
            identity: information.identity,
            kind: itemKind,
            size: information.status.st_size,
            modificationSeconds: information.status.st_mtimespec.tv_sec,
            modificationNanoseconds: information.status.st_mtimespec.tv_nsec,
            changeSeconds: information.status.st_ctimespec.tv_sec,
            changeNanoseconds: information.status.st_ctimespec.tv_nsec
        ))

        guard itemKind == .directory else { return }
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isAliasFileKey, .isSymbolicLinkKey],
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw FolderFileOperationError.operationFailed(
                kind: kind,
                path: url.path,
                reason: error.localizedDescription
            )
        }
        for child in children {
            let childRelativePath = relativePath.isEmpty
                ? child.lastPathComponent
                : relativePath + "/" + child.lastPathComponent
            try appendSnapshot(
                at: child,
                relativePath: childRelativePath,
                rootDevice: rootDevice,
                kind: kind,
                to: &result
            )
        }
    }

    static func revalidate(_ action: PreparedAction) throws {
        try checkCancellation()
        if let root = action.sourceRoot {
            try revalidateRoot(root)
        }
        try revalidateRoot(action.destinationRoot)
        try revalidateAncestors(action.sourceAncestors)
        try revalidateAncestors(action.destinationAncestors)

        if let source = action.sourceURL, let expected = action.sourceSnapshot {
            guard try snapshotTree(
                at: source,
                rootDevice: action.sourceRoot?.device ?? 0,
                kind: action.kind
            ) == expected else {
                throw FolderFileOperationError.itemChanged(source.path)
            }
        }
        try revalidateItem(
            at: action.destinationURL,
            expected: action.destinationSnapshot,
            rootDevice: action.destinationRoot.device
        )
    }

    static func revalidateRoot(_ root: RootContext) throws {
        guard let information = try fileInformation(at: root.url),
              information.kind == .directory,
              information.identity == root.identity else {
            throw FolderFileOperationError.itemChanged(root.url.path)
        }
        try rejectAlias(at: root.url)
    }

    static func revalidateAncestors(_ ancestors: [PathIdentity]) throws {
        for ancestor in ancestors {
            guard let information = try fileInformation(at: ancestor.url),
                  information.kind == .directory,
                  information.identity == ancestor.identity else {
                throw FolderFileOperationError.itemChanged(ancestor.url.path)
            }
            try rejectAlias(at: ancestor.url)
        }
    }

    static func revalidateItem(at url: URL, expected: [ItemState]?, rootDevice: dev_t) throws {
        if let expected {
            guard try snapshotTree(at: url, rootDevice: rootDevice, kind: .delete) == expected else {
                throw FolderFileOperationError.itemChanged(url.path)
            }
        } else if try fileInformation(at: url) != nil {
            throw FolderFileOperationError.itemChanged(url.path)
        }
    }

    static func stageCopy(
        kind: FolderFileOperationKind,
        sourceRoot: RootContext,
        sourceComponents: [String],
        destination: URL,
        destinationComponents: [String],
        sourceSnapshot: [ItemState],
        destinationRoot: RootContext,
        sourceAncestors: [PathIdentity],
        destinationAncestors: [PathIdentity]
    ) throws -> StagedItem {
        try checkCancellation()
        let source = sourceRoot.url.appending(path: sourceComponents.joined(separator: "/"))
        let parent = destination.deletingLastPathComponent()
        let stagingContainer = try unusedSibling(of: destination, marker: "stage", kind: kind)
        let staged = stagingContainer.appending(path: "item")
        do {
            let sourceFD = try openVerifiedItem(
                root: sourceRoot,
                components: sourceComponents,
                expected: sourceSnapshot[0],
                kind: kind
            )
            defer { Darwin.close(sourceFD) }
            let destinationParentFD = try openVerifiedParent(
                root: destinationRoot,
                components: destinationComponents,
                expectedIdentity: destinationAncestors.last?.identity ?? destinationRoot.identity,
                kind: kind
            )
            defer { Darwin.close(destinationParentFD) }
            guard try descriptorIdentity(destinationParentFD) ==
                    (destinationAncestors.last?.identity ?? destinationRoot.identity) else {
                throw FolderFileOperationError.itemChanged(parent.path)
            }
            let created = stagingContainer.lastPathComponent.withCString {
                Darwin.mkdirat(destinationParentFD, $0, S_IRWXU)
            }
            guard created == 0 else { throw posixFailure(kind: kind, path: stagingContainer.path) }
            let stagingContainerFD = stagingContainer.lastPathComponent.withCString {
                Darwin.openat(
                    destinationParentFD,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard stagingContainerFD >= 0 else {
                throw posixFailure(kind: kind, path: stagingContainer.path)
            }
            defer { Darwin.close(stagingContainerFD) }
            let stagingContainerIdentity = try descriptorIdentity(stagingContainerFD)
            try copyItem(
                sourceFD: sourceFD,
                sourceKind: sourceSnapshot[0].kind,
                destinationParentFD: stagingContainerFD,
                destinationName: "item",
                sourcePath: source.path,
                destinationPath: staged.path,
                kind: kind
            )
            guard Darwin.fsync(stagingContainerFD) == 0 else {
                throw posixFailure(kind: kind, path: stagingContainer.path)
            }
            try checkCancellation()
            try revalidateRoot(sourceRoot)
            try revalidateAncestors(sourceAncestors)
            guard try snapshotTree(at: source, rootDevice: sourceRoot.device, kind: kind) == sourceSnapshot else {
                throw FolderFileOperationError.itemChanged(source.path)
            }
            try revalidateRoot(destinationRoot)
            try revalidateAncestors(destinationAncestors)
            let stagedSnapshot = try snapshotTree(
                at: staged,
                rootDevice: destinationRoot.device,
                kind: kind
            )
            guard copiedTreeMatches(sourceSnapshot, stagedSnapshot) else {
                throw FolderFileOperationError.itemChanged(source.path)
            }
            guard parentIdentity(parent) ==
                    (destinationAncestors.last?.identity ?? destinationRoot.identity) else {
                throw FolderFileOperationError.itemChanged(parent.path)
            }
            return StagedItem(
                containerURL: stagingContainer,
                containerIdentity: stagingContainerIdentity,
                url: staged,
                snapshot: stagedSnapshot
            )
        } catch let error as FolderFileOperationError {
            if try fileInformation(at: stagingContainer) != nil {
                throw FolderFileOperationError.outcomeUncertain(
                    path: error.errorPath ?? source.path,
                    recovery: stagingContainer.path
                )
            }
            throw error
        } catch {
            throw FolderFileOperationError.outcomeUncertain(
                path: source.path,
                recovery: stagingContainer.path
            )
        }
    }

    static func install(
        staged: StagedItem,
        at destination: URL,
        expectedDestination: [ItemState]?,
        collisionPolicy: FolderFileCollisionPolicy,
        expectedParentIdentity: FileIdentity,
        destinationRoot: RootContext,
        destinationComponents: [String],
        kind: FolderFileOperationKind
    ) throws -> InstalledItem {
        try checkCancellation()
        let parent = destination.deletingLastPathComponent()
        let directoryFD = try openVerifiedParent(
            root: destinationRoot,
            components: destinationComponents,
            expectedIdentity: expectedParentIdentity,
            kind: kind
        )
        defer { Darwin.close(directoryFD) }
        let stagingContainerFD = staged.containerURL.lastPathComponent.withCString {
            Darwin.openat(
                directoryFD,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard stagingContainerFD >= 0 else {
            throw FolderFileOperationError.itemChanged(staged.containerURL.path)
        }
        defer { Darwin.close(stagingContainerFD) }
        guard try descriptorIdentity(directoryFD) == expectedParentIdentity else {
            throw FolderFileOperationError.itemChanged(parent.path)
        }
        guard try descriptorIdentity(stagingContainerFD) == staged.containerIdentity else {
            throw FolderFileOperationError.itemChanged(staged.containerURL.path)
        }

        let currentIdentity = try childIdentity(
            directoryFD: directoryFD,
            name: destination.lastPathComponent
        )
        guard currentIdentity == expectedDestination?.first?.identity else {
            throw FolderFileOperationError.itemChanged(destination.path)
        }
        if expectedDestination != nil, collisionPolicy != .replaceKeepingBackup {
            throw FolderFileOperationError.destinationCollision(destination.path)
        }
        guard try validateKnownItem(
            parentFD: stagingContainerFD,
            name: "item",
            expected: staged.snapshot,
            relativePath: "",
            ignoresRootChangeTime: false
        ) == staged.snapshot.count else {
            throw FolderFileOperationError.itemChanged(staged.url.path)
        }

        if expectedDestination == nil {
            let result = "item".withCString { stagedName in
                destination.lastPathComponent.withCString { destinationName in
                    Darwin.renameatx_np(
                        stagingContainerFD,
                        stagedName,
                        directoryFD,
                        destinationName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard result == 0 else {
                throw posixFailure(kind: kind, path: destination.path)
            }
            do {
                guard try validateKnownItem(
                    parentFD: directoryFD,
                    name: destination.lastPathComponent,
                    expected: staged.snapshot,
                    relativePath: "",
                    ignoresRootChangeTime: true
                ) == staged.snapshot.count else {
                    throw FolderFileOperationError.itemChanged(destination.path)
                }
            } catch {
                let rollback = destination.lastPathComponent.withCString { destinationName in
                    "item".withCString { stagedName in
                        Darwin.renameatx_np(
                            directoryFD,
                            destinationName,
                            stagingContainerFD,
                            stagedName,
                            UInt32(RENAME_EXCL)
                        )
                    }
                }
                guard rollback == 0 else {
                    throw FolderFileOperationError.outcomeUncertain(
                        path: destination.path,
                        recovery: staged.containerURL.path
                    )
                }
                throw FolderFileOperationError.itemChanged(destination.path)
            }
            try syncKnownItem(
                parentFD: directoryFD,
                name: destination.lastPathComponent,
                expected: staged.snapshot,
                relativePath: ""
            )
            try synchronizeDirectory(directoryFD, destination: destination, recovery: nil)
            return InstalledItem(
                backup: nil,
                warning: .cleanupArtifactPreserved(staged.containerURL.path)
            )
        }

        let backup = try unusedSibling(of: destination, marker: "backup", kind: kind)
        let swapResult = "item".withCString { stagedName in
            destination.lastPathComponent.withCString { destinationName in
                Darwin.renameatx_np(
                    stagingContainerFD,
                    stagedName,
                    directoryFD,
                    destinationName,
                    UInt32(RENAME_SWAP)
                )
            }
        }
        guard swapResult == 0 else {
            throw posixFailure(kind: kind, path: destination.path)
        }

        guard let expectedDestination else { preconditionFailure("Missing replacement snapshot") }
        do {
            guard try validateKnownItem(
                parentFD: stagingContainerFD,
                name: "item",
                expected: expectedDestination,
                relativePath: "",
                ignoresRootChangeTime: true
            ) == expectedDestination.count else {
                throw FolderFileOperationError.itemChanged(destination.path)
            }
        } catch {
            let rollback = "item".withCString { stagedName in
                destination.lastPathComponent.withCString { destinationName in
                    Darwin.renameatx_np(
                        stagingContainerFD,
                        stagedName,
                        directoryFD,
                        destinationName,
                        UInt32(RENAME_SWAP)
                    )
                }
            }
            guard rollback == 0 else {
                throw FolderFileOperationError.outcomeUncertain(
                    path: destination.path,
                    recovery: staged.url.path
                )
            }
            throw FolderFileOperationError.itemChanged(destination.path)
        }
        do {
            guard try validateKnownItem(
                parentFD: directoryFD,
                name: destination.lastPathComponent,
                expected: staged.snapshot,
                relativePath: "",
                ignoresRootChangeTime: true
            ) == staged.snapshot.count else {
                throw FolderFileOperationError.itemChanged(destination.path)
            }
            try syncKnownItem(
                parentFD: directoryFD,
                name: destination.lastPathComponent,
                expected: staged.snapshot,
                relativePath: ""
            )
        } catch {
            let rollback = "item".withCString { stagedName in
                destination.lastPathComponent.withCString { destinationName in
                    Darwin.renameatx_np(
                        stagingContainerFD,
                        stagedName,
                        directoryFD,
                        destinationName,
                        UInt32(RENAME_SWAP)
                    )
                }
            }
            guard rollback == 0 else {
                throw FolderFileOperationError.outcomeUncertain(
                    path: destination.path,
                    recovery: staged.containerURL.path
                )
            }
            throw FolderFileOperationError.itemChanged(destination.path)
        }

        let backupResult = "item".withCString { stagedName in
            backup.lastPathComponent.withCString { backupName in
                Darwin.renameatx_np(
                    stagingContainerFD,
                    stagedName,
                    directoryFD,
                    backupName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        let actualBackup: URL
        let warning: FolderFileOperationWarning?
        if backupResult == 0 {
            do {
                guard try validateKnownItem(
                    parentFD: directoryFD,
                    name: backup.lastPathComponent,
                    expected: expectedDestination,
                    relativePath: "",
                    ignoresRootChangeTime: true
                ) == expectedDestination.count else {
                    throw FolderFileOperationError.itemChanged(backup.path)
                }
            } catch {
                throw FolderFileOperationError.outcomeUncertain(
                    path: destination.path,
                    recovery: backup.path
                )
            }
            actualBackup = backup
            warning = .cleanupArtifactPreserved(staged.containerURL.path)
        } else {
            guard try childIdentity(
                directoryFD: stagingContainerFD,
                name: "item"
            ) == expectedDestination.first?.identity else {
                throw FolderFileOperationError.outcomeUncertain(
                    path: destination.path,
                    recovery: staged.url.path
                )
            }
            actualBackup = staged.url
            warning = .backupNameFallback(staged.url.path)
        }
        try synchronizeDirectory(directoryFD, destination: destination, recovery: actualBackup)
        return InstalledItem(backup: actualBackup, warning: warning)
    }

    static func openVerifiedItem(
        root: RootContext,
        components: [String],
        expected: ItemState,
        kind: FolderFileOperationKind
    ) throws -> Int32 {
        var descriptor = try openRoot(root, kind: kind)
        do {
            for (index, component) in components.enumerated() {
                let isFinal = index == components.count - 1
                let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW |
                    (!isFinal || expected.kind == .directory ? O_DIRECTORY : 0)
                let next = component.withCString { Darwin.openat(descriptor, $0, flags) }
                guard next >= 0 else {
                    throw posixFailure(
                        kind: kind,
                        path: root.url.appending(path: components[...index].joined(separator: "/")).path
                    )
                }
                Darwin.close(descriptor)
                descriptor = next
            }
            guard try descriptorIdentity(descriptor) == expected.identity else {
                throw FolderFileOperationError.itemChanged(
                    root.url.appending(path: components.joined(separator: "/")).path
                )
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func copyItem(
        sourceFD: Int32,
        sourceKind: ItemKind,
        destinationParentFD: Int32,
        destinationName: String,
        sourcePath: String,
        destinationPath: String,
        kind: FolderFileOperationKind
    ) throws {
        try checkCancellation()
        switch sourceKind {
        case .file:
            let destinationFD = destinationName.withCString {
                Darwin.openat(
                    destinationParentFD,
                    $0,
                    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                    S_IRUSR | S_IWUSR
                )
            }
            guard destinationFD >= 0 else {
                throw posixFailure(kind: kind, path: destinationPath)
            }
            defer {
                Darwin.close(destinationFD)
            }
            guard Darwin.fcopyfile(sourceFD, destinationFD, nil, copyfile_flags_t(COPYFILE_ALL)) == 0,
                  Darwin.fsync(destinationFD) == 0 else {
                throw posixFailure(kind: kind, path: sourcePath)
            }

        case .directory:
            let created = destinationName.withCString {
                Darwin.mkdirat(destinationParentFD, $0, S_IRWXU)
            }
            guard created == 0 else { throw posixFailure(kind: kind, path: destinationPath) }
            let destinationFD = destinationName.withCString {
                Darwin.openat(
                    destinationParentFD,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard destinationFD >= 0 else {
                throw posixFailure(kind: kind, path: destinationPath)
            }
            defer {
                Darwin.close(destinationFD)
            }
            try copyDirectoryContents(
                sourceFD: sourceFD,
                destinationFD: destinationFD,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                kind: kind
            )
            guard Darwin.fcopyfile(
                sourceFD,
                destinationFD,
                nil,
                copyfile_flags_t(COPYFILE_METADATA)
            ) == 0,
            Darwin.fsync(destinationFD) == 0 else {
                throw posixFailure(kind: kind, path: destinationPath)
            }
        }
    }

    static func copyDirectoryContents(
        sourceFD: Int32,
        destinationFD: Int32,
        sourcePath: String,
        destinationPath: String,
        kind: FolderFileOperationKind
    ) throws {
        let streamFD = Darwin.dup(sourceFD)
        guard streamFD >= 0, let directory = Darwin.fdopendir(streamFD) else {
            if streamFD >= 0 { Darwin.close(streamFD) }
            throw posixFailure(kind: kind, path: sourcePath)
        }
        defer { Darwin.closedir(directory) }

        while let entry = Darwin.readdir(directory) {
            try checkCancellation()
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            var status = stat()
            let statResult = name.withCString {
                Darwin.fstatat(sourceFD, $0, &status, AT_SYMLINK_NOFOLLOW)
            }
            guard statResult == 0 else { throw posixFailure(kind: kind, path: sourcePath + "/" + name) }
            let childKind: ItemKind
            switch status.st_mode & S_IFMT {
            case S_IFREG: childKind = .file
            case S_IFDIR: childKind = .directory
            case S_IFLNK:
                throw FolderFileOperationError.symbolicLinkNotAllowed(sourcePath + "/" + name)
            default:
                throw FolderFileOperationError.unsupportedItem(sourcePath + "/" + name)
            }
            let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (childKind == .directory ? O_DIRECTORY : 0)
            let childFD = name.withCString { Darwin.openat(sourceFD, $0, flags) }
            guard childFD >= 0 else { throw posixFailure(kind: kind, path: sourcePath + "/" + name) }
            do {
                guard try descriptorIdentity(childFD) ==
                        FileIdentity(device: status.st_dev, inode: status.st_ino) else {
                    throw FolderFileOperationError.itemChanged(sourcePath + "/" + name)
                }
                try copyItem(
                    sourceFD: childFD,
                    sourceKind: childKind,
                    destinationParentFD: destinationFD,
                    destinationName: name,
                    sourcePath: sourcePath + "/" + name,
                    destinationPath: destinationPath + "/" + name,
                    kind: kind
                )
                Darwin.close(childFD)
            } catch {
                Darwin.close(childFD)
                throw error
            }
        }
    }

    @discardableResult
    static func validateKnownItem(
        parentFD: Int32,
        name: String,
        expected: [ItemState],
        relativePath: String,
        ignoresRootChangeTime: Bool
    ) throws -> Int {
        var status = stat()
        let statResult = name.withCString {
            Darwin.fstatat(parentFD, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        guard statResult == 0 else { throw FolderFileOperationError.itemChanged(name) }
        let itemKind: ItemKind
        switch status.st_mode & S_IFMT {
        case S_IFREG: itemKind = .file
        case S_IFDIR: itemKind = .directory
        case S_IFLNK: throw FolderFileOperationError.symbolicLinkNotAllowed(name)
        default: throw FolderFileOperationError.unsupportedItem(name)
        }
        guard let expectedItem = expected.first(where: { $0.relativePath == relativePath }),
              expectedItem.identity == FileIdentity(device: status.st_dev, inode: status.st_ino),
              expectedItem.kind == itemKind,
              expectedItem.size == status.st_size,
              expectedItem.modificationSeconds == status.st_mtimespec.tv_sec,
              expectedItem.modificationNanoseconds == status.st_mtimespec.tv_nsec,
              (ignoresRootChangeTime && relativePath.isEmpty ||
                  expectedItem.changeSeconds == status.st_ctimespec.tv_sec &&
                  expectedItem.changeNanoseconds == status.st_ctimespec.tv_nsec) else {
            throw FolderFileOperationError.itemChanged(name)
        }
        guard itemKind == .directory else { return 1 }

        let directoryFD = name.withCString {
            Darwin.openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard directoryFD >= 0 else { throw FolderFileOperationError.itemChanged(name) }
        defer { Darwin.close(directoryFD) }
        guard try descriptorIdentity(directoryFD) == expectedItem.identity else {
            throw FolderFileOperationError.itemChanged(name)
        }
        let streamFD = Darwin.dup(directoryFD)
        guard streamFD >= 0, let directory = Darwin.fdopendir(streamFD) else {
            if streamFD >= 0 { Darwin.close(streamFD) }
            throw FolderFileOperationError.itemChanged(name)
        }
        var count = 1
        while let entry = Darwin.readdir(directory) {
            let childName = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if childName == "." || childName == ".." { continue }
            let childRelativePath = relativePath.isEmpty
                ? childName
                : relativePath + "/" + childName
            do {
                count += try validateKnownItem(
                    parentFD: directoryFD,
                    name: childName,
                    expected: expected,
                    relativePath: childRelativePath,
                    ignoresRootChangeTime: false
                )
            } catch {
                Darwin.closedir(directory)
                throw error
            }
        }
        Darwin.closedir(directory)
        return count
    }

    static func syncKnownItem(
        parentFD: Int32,
        name: String,
        expected: [ItemState],
        relativePath: String
    ) throws {
        guard let expectedItem = expected.first(where: { $0.relativePath == relativePath }) else {
            throw FolderFileOperationError.itemChanged(name)
        }
        let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW |
            (expectedItem.kind == .directory ? O_DIRECTORY : 0)
        let descriptor = name.withCString { Darwin.openat(parentFD, $0, flags) }
        guard descriptor >= 0 else { throw FolderFileOperationError.itemChanged(name) }
        defer { Darwin.close(descriptor) }
        guard try descriptorIdentity(descriptor) == expectedItem.identity else {
            throw FolderFileOperationError.itemChanged(name)
        }
        if expectedItem.kind == .directory {
            let streamFD = Darwin.dup(descriptor)
            guard streamFD >= 0, let directory = Darwin.fdopendir(streamFD) else {
                if streamFD >= 0 { Darwin.close(streamFD) }
                throw FolderFileOperationError.itemChanged(name)
            }
            while let entry = Darwin.readdir(directory) {
                let childName = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                        String(cString: $0)
                    }
                }
                if childName == "." || childName == ".." { continue }
                let childRelativePath = relativePath.isEmpty
                    ? childName
                    : relativePath + "/" + childName
                do {
                    try syncKnownItem(
                        parentFD: descriptor,
                        name: childName,
                        expected: expected,
                        relativePath: childRelativePath
                    )
                } catch {
                    Darwin.closedir(directory)
                    throw error
                }
            }
            Darwin.closedir(directory)
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw FolderFileOperationError.outcomeUncertain(path: name, recovery: nil)
        }
    }

    static func moveToBackup(
        _ target: URL,
        expected: [ItemState],
        root: RootContext,
        components: [String],
        parentIdentity: FileIdentity
    ) throws -> URL {
        try checkCancellation()
        let backup = try unusedSibling(of: target, marker: "backup", kind: .delete)
        let directoryFD = try openVerifiedParent(
            root: root,
            components: components,
            expectedIdentity: parentIdentity,
            kind: .delete
        )
        defer { Darwin.close(directoryFD) }
        guard try childIdentity(directoryFD: directoryFD, name: target.lastPathComponent) == expected.first?.identity else {
            throw FolderFileOperationError.itemChanged(target.path)
        }
        let result = target.lastPathComponent.withCString { targetName in
            backup.lastPathComponent.withCString { backupName in
                Darwin.renameatx_np(
                    directoryFD,
                    targetName,
                    directoryFD,
                    backupName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else { throw posixFailure(kind: .delete, path: target.path) }
        let isValid: Bool
        do {
            isValid = renamedTreeMatches(
                expected,
                try snapshotTree(
                    at: backup,
                    rootDevice: expected[0].identity.device,
                    kind: .delete
                )
            )
        } catch {
            try restoreOrReportUncertain(
                from: backup,
                to: target,
                directoryFD: directoryFD,
                kind: .delete
            )
            throw FolderFileOperationError.itemChanged(target.path)
        }
        guard isValid else {
            try restoreOrReportUncertain(
                from: backup,
                to: target,
                directoryFD: directoryFD,
                kind: .delete
            )
            throw FolderFileOperationError.itemChanged(target.path)
        }
        try synchronizeDirectory(directoryFD, destination: target, recovery: backup)
        return backup
    }

    static func restoreRenamedItem(
        from recovery: URL,
        to target: URL,
        directoryFD: Int32,
        kind: FolderFileOperationKind
    ) throws {
        let result = recovery.lastPathComponent.withCString { recoveryName in
            target.lastPathComponent.withCString { targetName in
                Darwin.renameatx_np(
                    directoryFD,
                    recoveryName,
                    directoryFD,
                    targetName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else { throw posixFailure(kind: kind, path: target.path) }
        guard Darwin.fsync(directoryFD) == 0 else {
            throw FolderFileOperationError.outcomeUncertain(path: target.path, recovery: nil)
        }
    }

    static func restoreOrReportUncertain(
        from recovery: URL,
        to target: URL,
        directoryFD: Int32,
        kind: FolderFileOperationKind
    ) throws {
        do {
            try restoreRenamedItem(
                from: recovery,
                to: target,
                directoryFD: directoryFD,
                kind: kind
            )
        } catch let error as FolderFileOperationError {
            if case .outcomeUncertain = error {
                throw FolderFileOperationError.outcomeUncertain(path: target.path, recovery: nil)
            }
            throw FolderFileOperationError.outcomeUncertain(
                path: target.path,
                recovery: recovery.path
            )
        } catch {
            throw FolderFileOperationError.outcomeUncertain(
                path: target.path,
                recovery: recovery.path
            )
        }
    }

    static func openVerifiedParent(
        root: RootContext,
        components: [String],
        expectedIdentity: FileIdentity,
        kind: FolderFileOperationKind
    ) throws -> Int32 {
        let parentComponents = Array(components.dropLast())
        var directoryFD = try openRoot(root, kind: kind)
        do {
            for (index, component) in parentComponents.enumerated() {
                let next = component.withCString {
                    Darwin.openat(
                        directoryFD,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                    )
                }
                guard next >= 0 else {
                    throw posixFailure(
                        kind: kind,
                        path: root.url.appending(path: parentComponents[...index].joined(separator: "/")).path
                    )
                }
                Darwin.close(directoryFD)
                directoryFD = next
            }
            guard try descriptorIdentity(directoryFD) == expectedIdentity else {
                throw FolderFileOperationError.itemChanged(
                    root.url.appending(path: parentComponents.joined(separator: "/")).path
                )
            }
            return directoryFD
        } catch {
            Darwin.close(directoryFD)
            throw error
        }
    }

    static func openRoot(_ root: RootContext, kind: FolderFileOperationKind) throws -> Int32 {
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixFailure(kind: kind, path: "/") }
        do {
            let components = root.url.pathComponents.filter { $0 != "/" }
            for (index, component) in components.enumerated() {
                let next = component.withCString {
                    Darwin.openat(
                        descriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                    )
                }
                guard next >= 0 else {
                    throw posixFailure(
                        kind: kind,
                        path: "/" + components[...index].joined(separator: "/")
                    )
                }
                Darwin.close(descriptor)
                descriptor = next
            }
            guard try descriptorIdentity(descriptor) == root.identity else {
                throw FolderFileOperationError.itemChanged(root.url.path)
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func synchronizeDirectory(_ descriptor: Int32, destination: URL, recovery: URL?) throws {
        guard Darwin.fsync(descriptor) == 0 else {
            throw FolderFileOperationError.outcomeUncertain(
                path: destination.path,
                recovery: recovery?.path
            )
        }
    }

    static func unusedSibling(
        of target: URL,
        marker: String,
        kind: FolderFileOperationKind
    ) throws -> URL {
        let parent = target.deletingLastPathComponent()
        for _ in 0..<16 {
            let name = ".mm-\(marker.prefix(1))-\(UUID().uuidString)"
            let candidate = parent.appending(path: name).standardizedFileURL
            if try fileInformation(at: candidate) == nil {
                return candidate
            }
        }
        throw FolderFileOperationError.operationFailed(
            kind: kind,
            path: parent.path,
            reason: "Could not reserve a collision-free staging name."
        )
    }

    struct FileInformation {
        let status: stat
        let identity: FileIdentity
        let kind: ItemKind?
    }

    static func fileInformation(at url: URL) throws -> FileInformation? {
        var status = stat()
        if Darwin.lstat(url.path, &status) != 0 {
            if errno == ENOENT || errno == ENOTDIR { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let type = status.st_mode & S_IFMT
        let kind: ItemKind?
        switch type {
        case S_IFREG:
            kind = .file
        case S_IFDIR:
            kind = .directory
        case S_IFLNK:
            kind = nil
        default:
            throw FolderFileOperationError.unsupportedItem(url.path)
        }
        return FileInformation(
            status: status,
            identity: FileIdentity(device: status.st_dev, inode: status.st_ino),
            kind: kind
        )
    }

    static func descriptorIdentity(_ descriptor: Int32) throws -> FileIdentity {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return FileIdentity(device: status.st_dev, inode: status.st_ino)
    }

    static func childIdentity(directoryFD: Int32, name: String) throws -> FileIdentity? {
        try childInformation(directoryFD: directoryFD, name: name)?.identity
    }

    static func childInformation(directoryFD: Int32, name: String) throws -> FileInformation? {
        var status = stat()
        let result = name.withCString {
            Darwin.fstatat(directoryFD, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 {
            let kind: ItemKind
            switch status.st_mode & S_IFMT {
            case S_IFREG: kind = .file
            case S_IFDIR: kind = .directory
            case S_IFLNK:
                throw FolderFileOperationError.symbolicLinkNotAllowed(name)
            default:
                throw FolderFileOperationError.unsupportedItem(name)
            }
            return FileInformation(
                status: status,
                identity: FileIdentity(device: status.st_dev, inode: status.st_ino),
                kind: kind
            )
        }
        if errno == ENOENT { return nil }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    static func parentIdentity(_ parent: URL) -> FileIdentity? {
        do {
            return try fileInformation(at: parent)?.identity
        } catch {
            return nil
        }
    }

    static func copiedTreeMatches(_ source: [ItemState], _ copy: [ItemState]) -> Bool {
        guard source.count == copy.count else { return false }
        return zip(source, copy).allSatisfy { sourceItem, copiedItem in
            guard sourceItem.relativePath == copiedItem.relativePath,
                  sourceItem.kind == copiedItem.kind else {
                return false
            }
            guard sourceItem.kind == .file else { return true }
            return sourceItem.size == copiedItem.size &&
                sourceItem.modificationSeconds == copiedItem.modificationSeconds &&
                sourceItem.modificationNanoseconds == copiedItem.modificationNanoseconds
        }
    }

    static func renamedTreeMatches(_ expected: [ItemState], _ renamed: [ItemState]) -> Bool {
        guard expected.count == renamed.count else { return false }
        return zip(expected, renamed).enumerated().allSatisfy { index, pair in
            let (expectedItem, renamedItem) = pair
            guard expectedItem.relativePath == renamedItem.relativePath,
                  expectedItem.identity == renamedItem.identity,
                  expectedItem.kind == renamedItem.kind,
                  expectedItem.size == renamedItem.size,
                  expectedItem.modificationSeconds == renamedItem.modificationSeconds,
                  expectedItem.modificationNanoseconds == renamedItem.modificationNanoseconds else {
                return false
            }
            return index == 0 ||
                (expectedItem.changeSeconds == renamedItem.changeSeconds &&
                    expectedItem.changeNanoseconds == renamedItem.changeNanoseconds)
        }
    }

    static func rejectAlias(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isAliasFileKey])
        if values.isAliasFile == true {
            throw FolderFileOperationError.aliasNotAllowed(url.path)
        }
    }

    static func isContained(_ child: URL, by root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        if rootPath == "/" { return childPath.hasPrefix("/") }
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }

    static func destinationAncestorsContainSource(
        _ ancestors: [PathIdentity],
        sourceIdentity: FileIdentity?
    ) -> Bool {
        guard let sourceIdentity else { return false }
        return ancestors.contains { $0.identity == sourceIdentity }
    }

    static func sourceAncestorsContainDestination(
        _ ancestors: [PathIdentity],
        destinationIdentity: FileIdentity?
    ) -> Bool {
        guard let destinationIdentity else { return false }
        return ancestors.contains { $0.identity == destinationIdentity }
    }

    static func pathsOverlap(_ first: URL, _ second: URL) -> Bool {
        isContained(first, by: second) || isContained(second, by: first)
    }

    static func checkCancellation() throws {
        if Task<Never, Never>.isCancelled {
            throw FolderFileOperationError.cancelled
        }
    }

    static func observeAccess() {
        accessObserver?()
    }

    static func posixFailure(kind: FolderFileOperationKind, path: String) -> FolderFileOperationError {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        return .operationFailed(kind: kind, path: path, reason: error.localizedDescription)
    }

    static func failure(from error: FolderFileOperationError) -> FolderFileOperationFailure {
        let code: FolderFileOperationFailureCode
        let path: String?
        switch error {
        case .cancelled:
            code = .cancelled
            path = nil
        case let .itemChanged(value):
            code = .changedDuringOperation
            path = value
        case let .symbolicLinkNotAllowed(value),
             let .aliasNotAllowed(value),
             let .volumeBoundaryNotAllowed(value),
             let .unsupportedItem(value):
            code = .changedDuringOperation
            path = value
        case let .operationFailed(_, value, _):
            code = .fileSystem
            path = value
        case let .safetyRequirementsUnsupported(_, value, _):
            code = .safetyUnsupported
            path = value
        case let .outcomeUncertain(value, _):
            code = .outcomeUncertain
            path = value
        default:
            code = .inputRejected
            path = nil
        }
        return FolderFileOperationFailure(
            code: code,
            path: path,
            message: error.localizedDescription
        )
    }
}

private extension FolderFileOperationKind {
    var description: String {
        switch self {
        case .copy: "copy"
        case .move: "move"
        case .delete: "delete"
        }
    }
}

private extension FolderFileOperations.PathRole {
    var operationKind: FolderFileOperationKind {
        switch self {
        case .source: .copy
        case .destination: .delete
        }
    }
}

private extension FolderFileOperationPlan {
    var primaryKind: FolderFileOperationKind {
        switch self {
        case .copy, .synchronize:
            .copy
        case .move:
            .move
        case .delete:
            .delete
        }
    }

    var primaryPath: String {
        switch self {
        case let .copy(plan):
            plan.destinationRoot.appending(path: plan.destination.rawValue).path
        case let .move(plan):
            plan.destinationRoot.appending(path: plan.destination.rawValue).path
        case let .delete(plan):
            plan.root.appending(path: plan.target.rawValue).path
        case let .synchronize(plan):
            plan.destinationRoot.path
        }
    }

    var roots: [URL] {
        let values: [URL]
        switch self {
        case let .copy(plan):
            values = [plan.sourceRoot, plan.destinationRoot]
        case let .move(plan):
            values = [plan.sourceRoot, plan.destinationRoot]
        case let .delete(plan):
            values = [plan.root]
        case let .synchronize(plan):
            values = [plan.sourceRoot, plan.destinationRoot]
        }
        var seen = Set<URL>()
        return values.filter { seen.insert($0.standardizedFileURL).inserted }
    }
}

private extension FolderFileOperationError {
    var recoveryPath: String? {
        if case let .outcomeUncertain(_, recovery) = self { return recovery }
        return nil
    }

    var errorPath: String? {
        switch self {
        case let .invalidRoot(path),
             let .rootNotDirectory(path),
             let .invalidRelativePath(path),
             let .itemNotFound(path),
             let .destinationParentMissing(path),
             let .destinationCollision(path),
             let .symbolicLinkNotAllowed(path),
             let .aliasNotAllowed(path),
             let .volumeBoundaryNotAllowed(path),
             let .unsupportedItem(path),
             let .itemChanged(path):
            path
        case let .pathEscapesRoot(path, _),
             let .safetyRequirementsUnsupported(_, path, _),
             let .operationFailed(_, path, _),
             let .outcomeUncertain(path, _):
            path
        case .cancelled, .sourceDestinationOverlap, .conflictingPlan, .partialFailure:
            nil
        }
    }
}
