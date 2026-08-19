import Darwin
import Foundation

public enum FolderScanEntryKind: String, Equatable, Hashable, Sendable {
    case file
    case folder
    case symbolicLink
    case other
}

public struct FolderScanEntry: Equatable, Hashable, Sendable {
    /// Path relative to the scanned root, using "/" as the separator.
    public let relativePath: String
    public let kind: FolderScanEntryKind
    /// Byte count for a regular file or link payload. Directories and other nodes have no size.
    public let size: Int64?
    public let modificationDate: Date

    public init(
        relativePath: String,
        kind: FolderScanEntryKind,
        size: Int64?,
        modificationDate: Date
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.size = size
        self.modificationDate = modificationDate
    }
}

public enum FolderScanHiddenFilePolicy: String, Equatable, Hashable, Sendable {
    case include
    case excludeEntriesAndSymbolicLinkTargets
}

public enum FolderScanSymbolicLinkPolicy: String, Equatable, Hashable, Sendable {
    /// Report links but never traverse their targets.
    case doNotFollow
    /// Report links and traverse only directory targets physically contained by the scan root.
    case followDirectoriesWithinRoot
}

public enum FolderScanErrorPolicy: String, Equatable, Hashable, Sendable {
    /// Return readable entries and expose skipped entries or subtrees in `FolderScanResult.issues`.
    case collectIssues
    /// Throw on any unreadable entry, unreadable subtree, or repeated directory target.
    case failClosed
}

public enum FolderScanLimit: String, Equatable, Hashable, Sendable {
    case depth
    case entries
    case examinedEntries
    case issues
    case openDirectoryDescriptors
    case pendingEntryNames
    case relativePathUTF8Bytes
    case totalAccountedBytes
}

public enum FolderScanContainmentFailureReason: String, Equatable, Hashable, Sendable {
    case outside
    case indeterminate
    case race
}

public struct FolderScanLimits: Equatable, Hashable, Sendable {
    public var maximumDepth: Int
    public var maximumEntries: Int
    public var maximumExaminedEntries: Int
    public var maximumIssues: Int
    public var maximumOpenDirectoryDescriptors: Int
    public var maximumPendingEntryNames: Int
    public var maximumRelativePathUTF8Bytes: Int
    public var maximumTotalAccountedBytes: Int64

    public init(
        maximumDepth: Int = 512,
        maximumEntries: Int = 1_000_000,
        maximumIssues: Int = 100_000,
        maximumRelativePathUTF8Bytes: Int = 16_384,
        maximumTotalAccountedBytes: Int64 = 1_125_899_906_842_624,
        maximumExaminedEntries: Int = 10_000_000,
        maximumOpenDirectoryDescriptors: Int = 128,
        maximumPendingEntryNames: Int = 1_000_000
    ) {
        precondition(maximumDepth >= 0)
        precondition(maximumEntries >= 0)
        precondition(maximumExaminedEntries >= 0)
        precondition(maximumIssues >= 0)
        precondition(maximumOpenDirectoryDescriptors >= 0)
        precondition(maximumPendingEntryNames >= 0)
        precondition(maximumRelativePathUTF8Bytes >= 0)
        precondition(maximumTotalAccountedBytes >= 0)
        self.maximumDepth = maximumDepth
        self.maximumEntries = maximumEntries
        self.maximumExaminedEntries = maximumExaminedEntries
        self.maximumIssues = maximumIssues
        self.maximumOpenDirectoryDescriptors = maximumOpenDirectoryDescriptors
        self.maximumPendingEntryNames = maximumPendingEntryNames
        self.maximumRelativePathUTF8Bytes = maximumRelativePathUTF8Bytes
        self.maximumTotalAccountedBytes = maximumTotalAccountedBytes
    }
}

public struct FolderScanOptions: Equatable, Hashable, Sendable {
    public var hiddenFilePolicy: FolderScanHiddenFilePolicy
    public var symbolicLinkPolicy: FolderScanSymbolicLinkPolicy
    public var errorPolicy: FolderScanErrorPolicy
    public var limits: FolderScanLimits

    public init(
        hiddenFilePolicy: FolderScanHiddenFilePolicy = .include,
        symbolicLinkPolicy: FolderScanSymbolicLinkPolicy = .doNotFollow,
        errorPolicy: FolderScanErrorPolicy = .failClosed
    ) {
        self.init(
            hiddenFilePolicy: hiddenFilePolicy,
            symbolicLinkPolicy: symbolicLinkPolicy,
            errorPolicy: errorPolicy,
            limits: FolderScanLimits()
        )
    }

    public init(
        hiddenFilePolicy: FolderScanHiddenFilePolicy = .include,
        symbolicLinkPolicy: FolderScanSymbolicLinkPolicy = .doNotFollow,
        errorPolicy: FolderScanErrorPolicy = .failClosed,
        limits: FolderScanLimits
    ) {
        self.hiddenFilePolicy = hiddenFilePolicy
        self.symbolicLinkPolicy = symbolicLinkPolicy
        self.errorPolicy = errorPolicy
        self.limits = limits
    }
}

public struct FolderScanIssue: Error, LocalizedError, Equatable, Hashable, Sendable {
    public enum Operation: String, Equatable, Hashable, Sendable {
        case readDirectory
        case readMetadata
        case followSymbolicLink
        case preventRepeatedTraversal
        case enforceLimit
    }

    /// Empty for an issue affecting the scan root.
    public let relativePath: String
    public let operation: Operation
    public let errorDomain: String?
    public let errorCode: Int?
    public let limit: FolderScanLimit?
    public let containmentFailureReason: FolderScanContainmentFailureReason?
    public let message: String

    public init(
        relativePath: String,
        operation: Operation,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        limit: FolderScanLimit? = nil,
        containmentFailureReason: FolderScanContainmentFailureReason? = nil,
        message: String
    ) {
        self.relativePath = relativePath
        self.operation = operation
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.limit = limit
        self.containmentFailureReason = containmentFailureReason
        self.message = message
    }

    public var errorDescription: String? {
        let path = relativePath.isEmpty ? "." : relativePath
        return "Folder scan could not \(operation.description) at \(path): \(message)"
    }
}

public enum FolderScanError: Error, LocalizedError, Equatable, Sendable {
    case nonFileURL(String)
    case rootIsNotDirectory(String)
    case invalidLimit(FolderScanLimit)
    case fileSystem(FolderScanIssue)
    case limitExceeded(FolderScanIssue)

    public var errorDescription: String? {
        switch self {
        case .nonFileURL(let value):
            "Folder scans require a file URL, not \(value)."
        case .rootIsNotDirectory(let path):
            "Folder scan root is not a directory: \(path)"
        case .invalidLimit(let limit):
            "Folder scan limit is invalid: \(limit.rawValue)"
        case .fileSystem(let issue):
            issue.errorDescription
        case .limitExceeded(let issue):
            issue.errorDescription
        }
    }
}

public struct FolderScanResult: Equatable, Sendable {
    public let rootURL: URL
    /// Entries sorted by raw UTF-8 relative path for locale-independent, deterministic output.
    public let entries: [FolderScanEntry]
    /// Empty under `failClosed`; populated only when `collectIssues` permits a partial scan.
    public let issues: [FolderScanIssue]

    public init(rootURL: URL, entries: [FolderScanEntry], issues: [FolderScanIssue]) {
        self.rootURL = rootURL
        self.entries = entries
        self.issues = issues
    }
}

public struct FolderScanner: Sendable {
    enum DirectoryDescriptorOwnershipEvent: Equatable, Sendable {
        case acquired(Int32)
        case released(Int32, closeResult: Int32)
    }

    enum DirectoryDescriptorSyscall: Equatable, Sendable {
        case openRoot
        case openOrdinaryChild
        case duplicateDirectoryStream
        case openSymbolicLinkResolverInitial
        case openSymbolicLinkResolverReopen
        case openSymbolicLinkResolverComponent
        case duplicatePhysicalAncestry
        case openPhysicalAncestryParent
    }

    enum SymbolicLinkFollowCheckpoint: Equatable, Sendable {
        case targetPayloadReadBeforeVerification
        case linkStatusReadBeforePayloadVerification
        case linkPayloadReadBeforeFinalStatusVerification
        case targetDirectoryOpenedBeforeVerification
        case targetDirectoryVerifiedWithinRootBeforeTraversal
        case finalTargetDirectoryResolvedBeforeLinkReverification
        case finalTargetDirectoryContainedBeforeMetadataRefresh
    }

    enum OrdinaryDirectoryCheckpoint: Equatable, Sendable {
        case openedBeforeContainmentVerification
        case verifiedWithinRootBeforeTraversal
        case traversalCompletedBeforeFinalVerification
        case finalContainmentVerifiedBeforeMetadataRevalidation
    }

    enum SortCheckpoint: Equatable, Sendable {
        case entrySort
        case issueSort
    }

    enum PhysicalAncestryCheckpoint: Equatable, Sendable {
        case reachedRootBeforeFinalRevalidation
        case completedFinalRevalidationPass(Int)
    }

    struct PhysicalAncestryTransition: Sendable {
        let currentDevice: UInt64
        let currentInode: UInt64
        let parentDevice: UInt64
        let parentInode: UInt64
        let currentFileSystemID: (Int32, Int32)
        let parentFileSystemID: (Int32, Int32)
        let currentMountFlags: UInt32
        let parentMountFlags: UInt32
        let currentMountPoint: String
        let parentMountPoint: String
        let currentMountSource: String
        let parentMountSource: String
        let currentFileSystemType: String
        let parentFileSystemType: String
    }

    enum PhysicalAncestryTransitionClassification: Equatable, Sendable {
        case automatic
        case continuous
        case mountRoot
        case unproven
    }

    @TaskLocal
    static var symbolicLinkFollowObserver:
        (@Sendable (SymbolicLinkFollowCheckpoint) -> Void)?

    @TaskLocal
    static var sortCheckpointObserver: (@Sendable (SortCheckpoint) -> Void)?

    @TaskLocal
    static var ordinaryDirectoryObserver:
        (@Sendable (OrdinaryDirectoryCheckpoint) -> Void)?

    @TaskLocal
    static var physicalAncestryTransitionClassifier:
        (@Sendable (PhysicalAncestryTransition) -> PhysicalAncestryTransitionClassification)?

    @TaskLocal
    static var physicalAncestryObserver: (@Sendable (PhysicalAncestryCheckpoint) -> Void)?

    @TaskLocal
    static var directoryDescriptorSyscallObserver:
        (@Sendable (DirectoryDescriptorSyscall) -> Void)?

    @TaskLocal
    static var directoryEntryNameDecoder: (@Sendable ([UInt8]) -> String?)?

    public let options: FolderScanOptions
    private let directoryDescriptorOwnershipObserver:
        (@Sendable (DirectoryDescriptorOwnershipEvent) -> Void)?

    public init(options: FolderScanOptions = FolderScanOptions()) {
        self.options = options
        directoryDescriptorOwnershipObserver = nil
    }

    init(
        options: FolderScanOptions,
        directoryDescriptorOwnershipObserver:
            @escaping @Sendable (DirectoryDescriptorOwnershipEvent) -> Void
    ) {
        self.options = options
        self.directoryDescriptorOwnershipObserver = directoryDescriptorOwnershipObserver
    }

    /// Recursively scans on a cooperative background task. Cancelling the caller cancels the scan.
    public func scan(at rootURL: URL) async throws -> FolderScanResult {
        let options = options
        let directoryDescriptorOwnershipObserver = directoryDescriptorOwnershipObserver
        let symbolicLinkFollowObserver = Self.symbolicLinkFollowObserver
        let sortCheckpointObserver = Self.sortCheckpointObserver
        let ordinaryDirectoryObserver = Self.ordinaryDirectoryObserver
        let physicalAncestryTransitionClassifier = Self.physicalAncestryTransitionClassifier
        let physicalAncestryObserver = Self.physicalAncestryObserver
        let directoryDescriptorSyscallObserver = Self.directoryDescriptorSyscallObserver
        let directoryEntryNameDecoder = Self.directoryEntryNameDecoder
        let scanTask = Task.detached(priority: Task.currentPriority) {
            try Self.$directoryEntryNameDecoder.withValue(directoryEntryNameDecoder) {
                try Self.$directoryDescriptorSyscallObserver.withValue(
                    directoryDescriptorSyscallObserver
                ) {
                    try Self.$symbolicLinkFollowObserver.withValue(symbolicLinkFollowObserver) {
                        try Self.$sortCheckpointObserver.withValue(sortCheckpointObserver) {
                            try Self.$ordinaryDirectoryObserver.withValue(ordinaryDirectoryObserver) {
                                try Self.$physicalAncestryTransitionClassifier.withValue(
                                    physicalAncestryTransitionClassifier
                                ) {
                                    try Self.$physicalAncestryObserver.withValue(
                                        physicalAncestryObserver
                                    ) {
                                        var worker = FolderScanWorker(
                                            options: options,
                                            directoryDescriptorOwnershipObserver:
                                                directoryDescriptorOwnershipObserver
                                        )
                                        return try worker.scan(rootURL: rootURL)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        do {
            let result = try await withTaskCancellationHandler {
                try await scanTask.value
            } onCancel: {
                scanTask.cancel()
            }
            try Task.checkCancellation()
            return result
        } catch {
            scanTask.cancel()
            try Task.checkCancellation()
            throw error
        }
    }

    static func directoryIsPhysicallyWithinRootForTesting(
        directoryURL: URL,
        rootURL: URL
    ) throws -> FolderScanContainmentFailureReason? {
        let directoryFD = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard directoryFD >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(directoryFD) }

        let rootFD = rootURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard rootFD >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(rootFD) }

        var worker = FolderScanWorker(
            options: FolderScanOptions(),
            directoryDescriptorOwnershipObserver: nil
        )
        switch try worker.provenDirectoryContainment(
            descriptor: directoryFD,
            rootFD: rootFD,
            relativePath: ""
        ) {
        case .contained:
            return nil
        case .rejected(let reason):
            return reason
        }
    }
}

private struct FolderScanWorker {
    private struct ScanStopped: Error {}
    private struct ScanStoppedAfterRollback: Error {}
    private struct DirectoryContainmentRejected: LocalizedError {
        let reason: FolderScanContainmentFailureReason

        var errorDescription: String? {
            switch reason {
            case .outside:
                "Directory is physically outside the scan root."
            case .indeterminate:
                "Directory containment within the scan root could not be proven."
            case .race:
                "Directory ancestry changed while containment was being validated."
            }
        }
    }

    fileprivate enum DirectoryContainment {
        case contained
        case rejected(FolderScanContainmentFailureReason)
    }

    private struct NodeIdentity: Hashable {
        let device: UInt64
        let inode: UInt64
        let generation: UInt32

        init(_ status: stat) {
            device = UInt64(bitPattern: Int64(status.st_dev))
            inode = UInt64(status.st_ino)
            generation = status.st_gen
        }
    }

    private struct SymbolicLinkResolutionState: Hashable {
        let identity: NodeIdentity
        let parentIdentity: NodeIdentity
        let remainingComponents: [String]
    }

    private struct SymbolicLinkSnapshot: Equatable {
        let identity: NodeIdentity
        let mode: UInt64
        let linkCount: UInt64
        let userID: UInt64
        let groupID: UInt64
        let deviceType: Int64
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let statusChangeSeconds: Int64
        let statusChangeNanoseconds: Int64
        let birthSeconds: Int64
        let birthNanoseconds: Int64
        let size: Int64
        let blocks: Int64
        let blockSize: Int64
        let flags: UInt64

        init(_ status: stat) {
            identity = NodeIdentity(status)
            mode = UInt64(status.st_mode)
            linkCount = UInt64(status.st_nlink)
            userID = UInt64(status.st_uid)
            groupID = UInt64(status.st_gid)
            deviceType = Int64(status.st_rdev)
            modificationSeconds = Int64(status.st_mtimespec.tv_sec)
            modificationNanoseconds = Int64(status.st_mtimespec.tv_nsec)
            statusChangeSeconds = Int64(status.st_ctimespec.tv_sec)
            statusChangeNanoseconds = Int64(status.st_ctimespec.tv_nsec)
            birthSeconds = Int64(status.st_birthtimespec.tv_sec)
            birthNanoseconds = Int64(status.st_birthtimespec.tv_nsec)
            size = Int64(status.st_size)
            blocks = Int64(status.st_blocks)
            blockSize = Int64(status.st_blksize)
            flags = UInt64(status.st_flags)
        }
    }

    private struct FileSystemSnapshot: Equatable {
        let id: FileSystemID
        let flags: UInt32
        let mountPoint: String
        let mountSource: String
        let type: String

        var hasReliableIdentity: Bool {
            id != FileSystemID(first: 0, second: 0)
                && !mountPoint.isEmpty
                && !mountSource.isEmpty
                && !type.isEmpty
        }
    }

    private struct FileSystemID: Equatable {
        let first: Int32
        let second: Int32
    }

    private struct PhysicalAncestor {
        let descriptor: Int32
        let identity: NodeIdentity
        let fileSystem: FileSystemSnapshot
    }

    private struct PhysicalAncestorValidationSnapshot: Equatable {
        let identity: NodeIdentity
        let fileSystem: FileSystemSnapshot
        let parentIdentity: NodeIdentity?
    }

    private final class DirectoryDescriptorBudget {
        private let maximum: Int
        private var count = 0

        init(maximum: Int) {
            self.maximum = maximum
        }

        func acquire() -> Bool {
            guard count < maximum else { return false }
            count += 1
            return true
        }

        func release() {
            precondition(count > 0)
            count -= 1
        }
    }

    private enum DirectoryTargetResolution {
        case directory(descriptor: Int32, status: stat)
        case nonDirectory
        case hidden
        case rejected(FolderScanContainmentFailureReason)
    }

    private struct OriginSymbolicLinkRejected: LocalizedError {
        let hidden: Bool

        var errorDescription: String? {
            hidden
                ? "Symbolic link became hidden while it was being followed."
                : "Symbolic link changed or could not be verified while it was being followed."
        }
    }
    private struct SymbolicLinkTargetContainmentRejected: LocalizedError {
        let reason: FolderScanContainmentFailureReason

        var errorDescription: String? {
            switch reason {
            case .outside:
                "Symbolic link target is outside the scan root."
            case .indeterminate:
                "Symbolic link target containment could not be proven."
            case .race:
                "Symbolic link target ancestry changed during containment validation."
            }
        }
    }

    private let options: FolderScanOptions
    private let directoryDescriptorOwnershipObserver:
        (@Sendable (FolderScanner.DirectoryDescriptorOwnershipEvent) -> Void)?
    private let directoryDescriptorBudget: DirectoryDescriptorBudget
    private var entries: [FolderScanEntry] = []
    private var issues: [FolderScanIssue] = []
    private var visitedDirectories: Set<NodeIdentity> = []
    private var visitedDirectoryJournal: [NodeIdentity] = []
    private var totalAccountedBytes: Int64 = 0
    private var examinedEntryCount = 0
    private var pendingEntryNameCount = 0

    init(
        options: FolderScanOptions,
        directoryDescriptorOwnershipObserver:
            (@Sendable (FolderScanner.DirectoryDescriptorOwnershipEvent) -> Void)?
    ) {
        self.options = options
        self.directoryDescriptorOwnershipObserver = directoryDescriptorOwnershipObserver
        directoryDescriptorBudget = DirectoryDescriptorBudget(
            maximum: options.limits.maximumOpenDirectoryDescriptors
        )
    }

    mutating func scan(rootURL: URL) throws -> FolderScanResult {
        try Task.checkCancellation()
        try validateLimits()
        guard isLocalFileURL(rootURL) else {
            throw FolderScanError.nonFileURL(rootURL.absoluteString)
        }

        let rootDirectory: (descriptor: Int32, status: stat)
        do {
            rootDirectory = try openPinnedRootDirectoryFollowingInputSymlinks(at: rootURL)
        } catch is ScanStopped {
            try Task.checkCancellation()
            return FolderScanResult(
                rootURL: rootURL.resolvingSymlinksInPath().standardizedFileURL,
                entries: [],
                issues: issues
            )
        } catch {
            try Task.checkCancellation()
            if let scanError = error as? FolderScanError { throw scanError }
            throw FolderScanError.fileSystem(
                issue(relativePath: "", operation: .readMetadata, error: error)
            )
        }
        defer { closeOwnedDirectoryDescriptor(rootDirectory.descriptor) }
        let reportedRootURL: URL
        do {
            reportedRootURL = try directoryURL(for: rootDirectory.descriptor)
        } catch {
            try Task.checkCancellation()
            throw FolderScanError.fileSystem(
                issue(relativePath: "", operation: .readMetadata, error: error)
            )
        }
        let rootIdentity = NodeIdentity(rootDirectory.status)
        visitedDirectories.insert(rootIdentity)
        visitedDirectoryJournal.append(rootIdentity)
        do {
            try walk(
                directoryFD: rootDirectory.descriptor,
                rootFD: rootDirectory.descriptor,
                relativePath: "",
                relativePathUTF8Bytes: 0,
                depth: 0
            )
        } catch is ScanStopped {
        }
        try Task.checkCancellation()
        FolderScanner.sortCheckpointObserver?(.entrySort)
        try Task.checkCancellation()
        try entries.sort {
            try Task.checkCancellation()
            return Self.utf8PathPrecedes($0.relativePath, $1.relativePath)
        }
        try Task.checkCancellation()
        FolderScanner.sortCheckpointObserver?(.issueSort)
        try Task.checkCancellation()
        try issues.sort {
            try Task.checkCancellation()
            if $0.relativePath != $1.relativePath {
                return Self.utf8PathPrecedes($0.relativePath, $1.relativePath)
            }
            if $0.operation.rawValue != $1.operation.rawValue {
                return $0.operation.rawValue < $1.operation.rawValue
            }
            return $0.message < $1.message
        }
        try Task.checkCancellation()
        return FolderScanResult(rootURL: reportedRootURL, entries: entries, issues: issues)
    }

    private mutating func walk(
        directoryFD: Int32,
        rootFD: Int32,
        relativePath: String,
        relativePathUTF8Bytes: Int,
        depth: Int
    ) throws {
        try Task.checkCancellation()

        var listing: (
            names: [String],
            reachedEntryLimit: Bool,
            reachedPendingNameLimit: Bool,
            reachedExaminedEntryLimit: Bool
        )
        do {
            listing = try directoryEntryNames(
                directoryFD: directoryFD,
                relativePath: relativePath,
                relativePathUTF8Bytes: relativePathUTF8Bytes,
                depth: depth
            )
        } catch is ScanStopped {
            throw ScanStopped()
        } catch {
            if let scanError = error as? FolderScanError { throw scanError }
            try handle(
                issue(relativePath: relativePath, operation: .readDirectory, error: error)
            )
            return
        }
        pendingEntryNameCount += listing.names.count
        defer { pendingEntryNameCount -= listing.names.count }

        try Task.checkCancellation()
        try listing.names.sort {
            try Task.checkCancellation()
            return Self.utf8PathPrecedes($1, $0)
        }
        try Task.checkCancellation()

        while let name = listing.names.popLast() {
            pendingEntryNameCount -= 1
            try Task.checkCancellation()
            let childRelativePath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"
            let childStatus: stat
            do {
                childStatus = try fileStatus(parentFD: directoryFD, name: name)
            } catch {
                try handle(
                    issue(relativePath: childRelativePath, operation: .readMetadata, error: error)
                )
                continue
            }

            if options.hiddenFilePolicy == .excludeEntriesAndSymbolicLinkTargets
                && isHidden(name: name, status: childStatus)
            {
                continue
            }

            let (childDepth, depthOverflow) = depth.addingReportingOverflow(1)
            guard !depthOverflow, childDepth <= options.limits.maximumDepth else {
                try handleLimit(
                    .depth,
                    relativePath: childRelativePath,
                    message: "Maximum scan depth was exceeded; entry was skipped."
                )
                continue
            }
            let separatorBytes = relativePath.isEmpty ? 0 : 1
            let (pathPrefixBytes, prefixOverflow) = relativePathUTF8Bytes.addingReportingOverflow(
                separatorBytes
            )
            let (childRelativePathUTF8Bytes, pathOverflow) = pathPrefixBytes.addingReportingOverflow(
                name.utf8.count
            )
            guard !prefixOverflow, !pathOverflow,
                childRelativePathUTF8Bytes <= options.limits.maximumRelativePathUTF8Bytes
            else {
                try handleLimit(
                    .relativePathUTF8Bytes,
                    relativePath: childRelativePath,
                    message: "Maximum relative path UTF-8 byte count was exceeded; entry was skipped."
                )
                continue
            }

            let kind = entryKind(for: childStatus)
            guard try admitEntry(
                relativePath: childRelativePath,
                kind: kind,
                status: childStatus
            ) else {
                continue
            }
            entries.append(
                FolderScanEntry(
                    relativePath: childRelativePath,
                    kind: kind,
                    size: kind == .file || kind == .symbolicLink ? Int64(childStatus.st_size) : nil,
                    modificationDate: modificationDate(for: childStatus)
                )
            )

            switch kind {
            case .file, .other:
                continue
            case .folder:
                try processOrdinaryDirectory(
                    parentFD: directoryFD,
                    name: name,
                    relativePath: childRelativePath,
                    relativePathUTF8Bytes: childRelativePathUTF8Bytes,
                    depth: childDepth,
                    expectedStatus: childStatus,
                    rootFD: rootFD
                )
            case .symbolicLink:
                guard options.symbolicLinkPolicy == .followDirectoriesWithinRoot else { continue }
                try followSymbolicLink(
                    parentFD: directoryFD,
                    name: name,
                    relativePath: childRelativePath,
                    relativePathUTF8Bytes: childRelativePathUTF8Bytes,
                    depth: childDepth,
                    expectedStatus: childStatus,
                    rootFD: rootFD
                )
            }
        }
        if listing.reachedPendingNameLimit {
            try handleLimit(
                .pendingEntryNames,
                relativePath: relativePath,
                message: "Maximum pending directory entry name count was exceeded; remaining entries were skipped.",
                stopsScan: true
            )
        }
        if listing.reachedEntryLimit {
            try handleLimit(
                .entries,
                relativePath: relativePath,
                message: "Maximum entry count was exceeded; remaining entries were skipped.",
                stopsScan: true
            )
        }
        if listing.reachedExaminedEntryLimit {
            try handleLimit(
                .examinedEntries,
                relativePath: relativePath,
                message: "Maximum examined directory entry count was exceeded; remaining entries were skipped.",
                stopsScan: true
            )
        }
    }

    private mutating func processOrdinaryDirectory(
        parentFD: Int32,
        name: String,
        relativePath: String,
        relativePathUTF8Bytes: Int,
        depth: Int,
        expectedStatus: stat,
        rootFD: Int32
    ) throws {
        let childDirectory: (descriptor: Int32, status: stat)
        do {
            childDirectory = try openVerifiedDirectory(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                syscall: .openOrdinaryChild,
                relativePath: relativePath
            )
        } catch {
            if error is ScanStopped { throw ScanStopped() }
            if let scanError = error as? FolderScanError { throw scanError }
            try handle(issue(relativePath: relativePath, operation: .readDirectory, error: error))
            return
        }
        defer { closeOwnedDirectoryDescriptor(childDirectory.descriptor) }

        if options.hiddenFilePolicy == .excludeEntriesAndSymbolicLinkTargets
            && isHidden(name: name, status: childDirectory.status)
        {
            removeLastEntryFromAccounting()
            return
        }

        FolderScanner.ordinaryDirectoryObserver?(.openedBeforeContainmentVerification)
        do {
            try verifyDirectoryRemainsWithinRoot(
                descriptor: childDirectory.descriptor,
                rootFD: rootFD,
                relativePath: relativePath
            )
            let containedStatus = try fileStatus(parentFD: parentFD, name: name)
            guard entryKind(for: containedStatus) == .folder,
                directorySnapshot(containedStatus, matches: childDirectory.status),
                directorySnapshot(containedStatus, matches: expectedStatus)
            else {
                errno = ESTALE
                throw posixError()
            }
            if options.hiddenFilePolicy == .excludeEntriesAndSymbolicLinkTargets
                && isHidden(name: name, status: containedStatus)
            {
                removeLastEntryFromAccounting()
                return
            }
        } catch {
            if error is ScanStopped { throw ScanStopped() }
            if let scanError = error as? FolderScanError { throw scanError }
            try handle(issue(relativePath: relativePath, operation: .readDirectory, error: error))
            return
        }
        FolderScanner.ordinaryDirectoryObserver?(.verifiedWithinRootBeforeTraversal)

        let entryCount = entries.count
        let issueCount = issues.count
        let visitedDirectoryJournalCount = visitedDirectoryJournal.count
        let accountedBytes = totalAccountedBytes
        var stopped = false
        var terminalLimitIssue: FolderScanIssue?
        do {
            try traverseDirectory(
                descriptor: childDirectory.descriptor,
                rootFD: rootFD,
                relativePath: relativePath,
                relativePathUTF8Bytes: relativePathUTF8Bytes,
                depth: depth,
                status: childDirectory.status
            )
        } catch is ScanStopped {
            stopped = true
            terminalLimitIssue = preservedTerminalLimitIssue(
                since: issueCount,
                subtreeRelativePath: relativePath
            )
        }
        FolderScanner.ordinaryDirectoryObserver?(.traversalCompletedBeforeFinalVerification)

        do {
            try verifyDirectoryRemainsWithinRoot(
                descriptor: childDirectory.descriptor,
                rootFD: rootFD,
                relativePath: relativePath
            )
            FolderScanner.ordinaryDirectoryObserver?(
                .finalContainmentVerifiedBeforeMetadataRevalidation
            )
            let finalStatus = try fileStatus(parentFD: parentFD, name: name)
            guard entryKind(for: finalStatus) == .folder,
                NodeIdentity(finalStatus) == NodeIdentity(childDirectory.status),
                NodeIdentity(finalStatus) == NodeIdentity(expectedStatus)
            else {
                errno = ESTALE
                throw posixError()
            }
            if options.hiddenFilePolicy == .excludeEntriesAndSymbolicLinkTargets
                && isHidden(name: name, status: finalStatus)
            {
                rollbackTraversal(
                    entryCount: entryCount,
                    issueCount: issueCount,
                    visitedDirectoryJournalCount: visitedDirectoryJournalCount,
                    accountedBytes: accountedBytes,
                    preserving: terminalLimitIssue
                )
                removeLastEntryFromAccounting()
                if stopped { throw ScanStoppedAfterRollback() }
                return
            }
            guard directorySnapshot(finalStatus, matches: childDirectory.status),
                directorySnapshot(finalStatus, matches: expectedStatus)
            else {
                errno = ESTALE
                throw posixError()
            }
        } catch is ScanStoppedAfterRollback {
            throw ScanStopped()
        } catch {
            let errorStoppedScan = error is ScanStopped
            if errorStoppedScan, terminalLimitIssue == nil {
                terminalLimitIssue = preservedTerminalLimitIssue(
                    since: issueCount,
                    subtreeRelativePath: relativePath
                )
            }
            rollbackTraversal(
                entryCount: entryCount,
                issueCount: issueCount,
                visitedDirectoryJournalCount: visitedDirectoryJournalCount,
                accountedBytes: accountedBytes,
                preserving: terminalLimitIssue
            )
            if errorStoppedScan { throw ScanStopped() }
            if let scanError = error as? FolderScanError { throw scanError }
            try handle(issue(relativePath: relativePath, operation: .readDirectory, error: error))
            if stopped { throw ScanStopped() }
            return
        }
        if stopped { throw ScanStopped() }
    }

    private mutating func followSymbolicLink(
        parentFD: Int32,
        name: String,
        relativePath: String,
        relativePathUTF8Bytes: Int,
        depth: Int,
        expectedStatus: stat,
        rootFD: Int32
    ) throws {
        try Task.checkCancellation()

        let targetPayload: String
        let excludesHiddenTargets =
            options.hiddenFilePolicy == .excludeEntriesAndSymbolicLinkTargets
        do {
            targetPayload = try symbolicLinkTarget(parentFD: parentFD, name: name)
            FolderScanner.symbolicLinkFollowObserver?(.targetPayloadReadBeforeVerification)
            let verifiedStatus = try verifySymbolicLink(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                expectedTarget: targetPayload
            )
            if excludesHiddenTargets && isHidden(name: name, status: verifiedStatus) {
                removeLastEntryFromAccounting()
                return
            }
        } catch {
            let terminalError = terminalSymbolicLinkError(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                expectedTarget: nil,
                excludesHiddenTargets: excludesHiddenTargets,
                resolutionError: error
            )
            if terminalError.removesOriginLink { removeLastEntryFromAccounting() }
            try handle(
                issue(
                    relativePath: relativePath,
                    operation: .followSymbolicLink,
                    error: terminalError.error
                )
            )
            return
        }

        let targetResolution: DirectoryTargetResolution
        do {
            targetResolution = try resolveDirectoryTargetWithinRoot(
                rootFD: rootFD,
                parentFD: parentFD,
                relativePath: relativePath,
                targetPayload: targetPayload,
                originStatus: expectedStatus,
                excludesHiddenTargets: excludesHiddenTargets
            )
        } catch {
            let terminalError = terminalSymbolicLinkError(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                expectedTarget: targetPayload,
                excludesHiddenTargets: excludesHiddenTargets,
                resolutionError: error
            )
            if terminalError.removesOriginLink { removeLastEntryFromAccounting() }
            if error is ScanStopped { throw ScanStopped() }
            if let scanError = error as? FolderScanError { throw scanError }
            try handle(
                issue(
                    relativePath: relativePath,
                    operation: .followSymbolicLink,
                    error: terminalError.error
                )
            )
            return
        }
        let targetDirectory: (descriptor: Int32, status: stat)
        switch targetResolution {
        case .directory(let descriptor, let status):
            targetDirectory = (descriptor, status)
        case .nonDirectory, .hidden:
            do {
                try verifyVisibleOriginSymbolicLink(
                    parentFD: parentFD,
                    name: name,
                    expectedStatus: expectedStatus,
                    expectedTarget: targetPayload,
                    excludesHiddenTargets: excludesHiddenTargets
                )
            } catch {
                removeLastEntryFromAccounting()
                try handle(
                    issue(relativePath: relativePath, operation: .followSymbolicLink, error: error)
                )
            }
            return
        case .rejected(let reason):
            do {
                try verifyVisibleOriginSymbolicLink(
                    parentFD: parentFD,
                    name: name,
                    expectedStatus: expectedStatus,
                    expectedTarget: targetPayload,
                    excludesHiddenTargets: excludesHiddenTargets
                )
            } catch {
                removeLastEntryFromAccounting()
                try handle(
                    issue(relativePath: relativePath, operation: .followSymbolicLink, error: error)
                )
                return
            }
            try handle(
                FolderScanIssue(
                    relativePath: relativePath,
                    operation: .followSymbolicLink,
                    containmentFailureReason: reason,
                    message: containmentMessage(for: reason)
                )
            )
            return
        }
        defer { closeOwnedDirectoryDescriptor(targetDirectory.descriptor) }
        do {
            try verifyVisibleOriginSymbolicLink(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                expectedTarget: targetPayload,
                excludesHiddenTargets: excludesHiddenTargets
            )
        } catch {
            removeLastEntryFromAccounting()
            try handle(
                issue(relativePath: relativePath, operation: .followSymbolicLink, error: error)
            )
            return
        }
        FolderScanner.symbolicLinkFollowObserver?(.targetDirectoryOpenedBeforeVerification)
        try Task.checkCancellation()

        do {
            try verifyDirectoryRemainsWithinRoot(
                descriptor: targetDirectory.descriptor,
                rootFD: rootFD,
                relativePath: relativePath
            )
            var containedTargetStatus = stat()
            guard Darwin.fstat(targetDirectory.descriptor, &containedTargetStatus) == 0 else {
                throw posixError()
            }
            if excludesHiddenTargets && isHidden(name: "", status: containedTargetStatus) {
                try verifyVisibleOriginSymbolicLink(
                    parentFD: parentFD,
                    name: name,
                    expectedStatus: expectedStatus,
                    expectedTarget: targetPayload,
                    excludesHiddenTargets: excludesHiddenTargets
                )
                return
            }
            guard directorySnapshot(containedTargetStatus, matches: targetDirectory.status) else {
                errno = ESTALE
                throw posixError()
            }
            try verifyVisibleOriginSymbolicLink(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                expectedTarget: targetPayload,
                excludesHiddenTargets: excludesHiddenTargets
            )
        } catch {
            let terminalError = terminalSymbolicLinkError(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                expectedTarget: targetPayload,
                excludesHiddenTargets: excludesHiddenTargets,
                resolutionError: error
            )
            if terminalError.removesOriginLink { removeLastEntryFromAccounting() }
            if error is ScanStopped { throw ScanStopped() }
            if let scanError = error as? FolderScanError { throw scanError }
            try handle(
                issue(
                    relativePath: relativePath,
                    operation: .followSymbolicLink,
                    error: terminalError.error
                )
            )
            return
        }
        FolderScanner.symbolicLinkFollowObserver?(
            .targetDirectoryVerifiedWithinRootBeforeTraversal
        )
        try Task.checkCancellation()
        let entryCount = entries.count
        let issueCount = issues.count
        let visitedDirectoryJournalCount = visitedDirectoryJournal.count
        let accountedBytes = totalAccountedBytes
        var stopped = false
        var terminalLimitIssue: FolderScanIssue?
        do {
            try traverseDirectory(
                descriptor: targetDirectory.descriptor,
                rootFD: rootFD,
                relativePath: relativePath,
                relativePathUTF8Bytes: relativePathUTF8Bytes,
                depth: depth,
                status: targetDirectory.status
            )
        } catch is ScanStopped {
            stopped = true
            terminalLimitIssue = preservedTerminalLimitIssue(
                since: issueCount,
                subtreeRelativePath: relativePath
            )
        }

        do {
            let finalResolution = try resolveDirectoryTargetWithinRoot(
                rootFD: rootFD,
                parentFD: parentFD,
                relativePath: relativePath,
                targetPayload: targetPayload,
                originStatus: expectedStatus,
                excludesHiddenTargets: excludesHiddenTargets
            )
            let finalResolvedDirectory: (descriptor: Int32, status: stat)
            switch finalResolution {
            case .directory(let descriptor, let status):
                finalResolvedDirectory = (descriptor, status)
            case .hidden:
                rollbackTraversal(
                    entryCount: entryCount,
                    issueCount: issueCount,
                    visitedDirectoryJournalCount: visitedDirectoryJournalCount,
                    accountedBytes: accountedBytes,
                    preserving: terminalLimitIssue
                )
                try verifyVisibleOriginSymbolicLink(
                    parentFD: parentFD,
                    name: name,
                    expectedStatus: expectedStatus,
                    expectedTarget: targetPayload,
                    excludesHiddenTargets: excludesHiddenTargets
                )
                if stopped { throw ScanStoppedAfterRollback() }
                return
            case .rejected(let reason):
                throw SymbolicLinkTargetContainmentRejected(reason: reason)
            case .nonDirectory:
                errno = ESTALE
                throw posixError()
            }
            defer { closeOwnedDirectoryDescriptor(finalResolvedDirectory.descriptor) }
            guard directorySnapshot(finalResolvedDirectory.status, matches: targetDirectory.status)
            else {
                errno = ESTALE
                throw posixError()
            }
            FolderScanner.symbolicLinkFollowObserver?(
                .finalTargetDirectoryResolvedBeforeLinkReverification
            )
            try verifyDirectoryRemainsWithinRoot(
                descriptor: targetDirectory.descriptor,
                rootFD: rootFD,
                relativePath: relativePath
            )
            FolderScanner.symbolicLinkFollowObserver?(
                .finalTargetDirectoryContainedBeforeMetadataRefresh
            )
            var refreshedTargetStatus = stat()
            guard Darwin.fstat(targetDirectory.descriptor, &refreshedTargetStatus) == 0 else {
                throw posixError()
            }
            if excludesHiddenTargets && isHidden(name: "", status: refreshedTargetStatus) {
                rollbackTraversal(
                    entryCount: entryCount,
                    issueCount: issueCount,
                    visitedDirectoryJournalCount: visitedDirectoryJournalCount,
                    accountedBytes: accountedBytes,
                    preserving: terminalLimitIssue
                )
                try verifyVisibleOriginSymbolicLink(
                    parentFD: parentFD,
                    name: name,
                    expectedStatus: expectedStatus,
                    expectedTarget: targetPayload,
                    excludesHiddenTargets: excludesHiddenTargets
                )
                if stopped { throw ScanStoppedAfterRollback() }
                return
            }
            guard directorySnapshot(refreshedTargetStatus, matches: targetDirectory.status) else {
                errno = ESTALE
                throw posixError()
            }
            try verifyVisibleOriginSymbolicLink(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                expectedTarget: targetPayload,
                excludesHiddenTargets: excludesHiddenTargets
            )
        } catch is ScanStoppedAfterRollback {
            throw ScanStopped()
        } catch {
            let errorStoppedScan = error is ScanStopped
            if errorStoppedScan, terminalLimitIssue == nil {
                terminalLimitIssue = preservedTerminalLimitIssue(
                    since: issueCount,
                    subtreeRelativePath: relativePath
                )
            }
            rollbackTraversal(
                entryCount: entryCount,
                issueCount: issueCount,
                visitedDirectoryJournalCount: visitedDirectoryJournalCount,
                accountedBytes: accountedBytes,
                preserving: terminalLimitIssue
            )
            let terminalError = terminalSymbolicLinkError(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                expectedTarget: targetPayload,
                excludesHiddenTargets: excludesHiddenTargets,
                resolutionError: error
            )
            if terminalError.removesOriginLink { removeLastEntryFromAccounting() }
            if errorStoppedScan { throw ScanStopped() }
            if let scanError = error as? FolderScanError { throw scanError }
            try handle(
                issue(
                    relativePath: relativePath,
                    operation: .followSymbolicLink,
                    error: terminalError.error
                )
            )
            if stopped { throw ScanStopped() }
            return
        }
        if stopped { throw ScanStopped() }
    }

    private func verifyVisibleOriginSymbolicLink(
        parentFD: Int32,
        name: String,
        expectedStatus: stat,
        expectedTarget: String,
        excludesHiddenTargets: Bool
    ) throws {
        let status: stat
        do {
            status = try verifySymbolicLink(
                parentFD: parentFD,
                name: name,
                expectedStatus: expectedStatus,
                expectedTarget: expectedTarget
            )
        } catch {
            throw OriginSymbolicLinkRejected(hidden: false)
        }
        if excludesHiddenTargets && isHidden(name: name, status: status) {
            throw OriginSymbolicLinkRejected(hidden: true)
        }
    }

    private func terminalSymbolicLinkError(
        parentFD: Int32,
        name: String,
        expectedStatus: stat,
        expectedTarget: String?,
        excludesHiddenTargets: Bool,
        resolutionError: any Error
    ) -> (error: any Error, removesOriginLink: Bool) {
        if resolutionError is OriginSymbolicLinkRejected {
            return (resolutionError, true)
        }
        do {
            if let expectedTarget {
                try verifyVisibleOriginSymbolicLink(
                    parentFD: parentFD,
                    name: name,
                    expectedStatus: expectedStatus,
                    expectedTarget: expectedTarget,
                    excludesHiddenTargets: excludesHiddenTargets
                )
            } else {
                let status = try fileStatus(parentFD: parentFD, name: name)
                guard entryKind(for: status) == .symbolicLink,
                    SymbolicLinkSnapshot(status) == SymbolicLinkSnapshot(expectedStatus)
                else {
                    errno = ESTALE
                    throw posixError()
                }
                if excludesHiddenTargets && isHidden(name: name, status: status) {
                    throw OriginSymbolicLinkRejected(hidden: true)
                }
                return (resolutionError, false)
            }
            return (resolutionError, false)
        } catch {
            return (error, true)
        }
    }

    private func containmentMessage(for reason: FolderScanContainmentFailureReason) -> String {
        SymbolicLinkTargetContainmentRejected(reason: reason).localizedDescription
    }

    private mutating func rollbackTraversal(
        entryCount: Int,
        issueCount: Int,
        visitedDirectoryJournalCount: Int,
        accountedBytes: Int64,
        preserving terminalLimitIssue: FolderScanIssue? = nil
    ) {
        entries.removeSubrange(entryCount...)
        issues.removeSubrange(issueCount...)
        for identity in visitedDirectoryJournal[visitedDirectoryJournalCount...] {
            visitedDirectories.remove(identity)
        }
        visitedDirectoryJournal.removeSubrange(visitedDirectoryJournalCount...)
        totalAccountedBytes = accountedBytes
        if let terminalLimitIssue {
            issues.append(terminalLimitIssue)
        }
    }

    private func preservedTerminalLimitIssue(
        since issueCount: Int,
        subtreeRelativePath: String
    ) -> FolderScanIssue? {
        guard let issue = issues[issueCount...].last(where: { issue in
            guard issue.operation == .enforceLimit else { return false }
            switch issue.limit {
            case .entries, .examinedEntries, .openDirectoryDescriptors,
                .pendingEntryNames, .totalAccountedBytes:
                return true
            case .depth, .issues, .relativePathUTF8Bytes, nil:
                return false
            }
        })
        else {
            return nil
        }
        return FolderScanIssue(
            relativePath: subtreeRelativePath,
            operation: issue.operation,
            errorDomain: issue.errorDomain,
            errorCode: issue.errorCode,
            limit: issue.limit,
            containmentFailureReason: issue.containmentFailureReason,
            message: issue.message
        )
    }

    private mutating func verifyDirectoryRemainsWithinRoot(
        descriptor: Int32,
        rootFD: Int32,
        relativePath: String
    ) throws {
        switch try provenDirectoryContainment(
            descriptor: descriptor,
            rootFD: rootFD,
            relativePath: relativePath
        ) {
        case .contained:
            return
        case .rejected(let reason):
            throw DirectoryContainmentRejected(reason: reason)
        }
    }

    fileprivate mutating func provenDirectoryContainment(
        descriptor: Int32,
        rootFD: Int32,
        relativePath: String
    ) throws -> DirectoryContainment {
        do {
            return try directoryContainment(
                descriptor: descriptor,
                rootFD: rootFD,
                relativePath: relativePath
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch is ScanStopped {
            throw ScanStopped()
        } catch let scanError as FolderScanError {
            throw scanError
        } catch {
            return .rejected(containmentFailureReason(for: error))
        }
    }

    private mutating func traverseDirectory(
        descriptor: Int32,
        rootFD: Int32,
        relativePath: String,
        relativePathUTF8Bytes: Int,
        depth: Int,
        status: stat
    ) throws {
        try Task.checkCancellation()
        let identity = NodeIdentity(status)
        guard visitedDirectories.insert(identity).inserted else {
            try handle(
                FolderScanIssue(
                    relativePath: relativePath,
                    operation: .preventRepeatedTraversal,
                    message: "Directory target was already visited; repeated or cyclic traversal was skipped."
                )
            )
            return
        }
        visitedDirectoryJournal.append(identity)
        try walk(
            directoryFD: descriptor,
            rootFD: rootFD,
            relativePath: relativePath,
            relativePathUTF8Bytes: relativePathUTF8Bytes,
            depth: depth
        )
    }

    private mutating func admitEntry(
        relativePath: String,
        kind: FolderScanEntryKind,
        status: stat
    ) throws -> Bool {
        guard entries.count < options.limits.maximumEntries else {
            try handleLimit(
                .entries,
                relativePath: relativePath,
                message: "Maximum entry count was exceeded; remaining entries were skipped.",
                stopsScan: true
            )
            return false
        }

        let byteCount = accountedByteCount(kind: kind, status: status)
        let (updatedBytes, overflow) = totalAccountedBytes.addingReportingOverflow(byteCount)
        guard !overflow, updatedBytes <= options.limits.maximumTotalAccountedBytes else {
            try handleLimit(
                .totalAccountedBytes,
                relativePath: relativePath,
                message: "Maximum total accounted byte count was exceeded; remaining entries were skipped.",
                stopsScan: true
            )
            return false
        }
        totalAccountedBytes = updatedBytes
        return true
    }

    private mutating func removeLastEntryFromAccounting() {
        guard let entry = entries.popLast() else { return }
        if let size = entry.size, size > 0 {
            totalAccountedBytes -= size
        }
    }

    private func accountedByteCount(kind: FolderScanEntryKind, status: stat) -> Int64 {
        guard kind == .file || kind == .symbolicLink else { return 0 }
        return max(Int64(status.st_size), 0)
    }

    private mutating func handleLimit(
        _ limit: FolderScanLimit,
        relativePath: String,
        message: String,
        stopsScan: Bool = false
    ) throws {
        let limitIssue = FolderScanIssue(
            relativePath: relativePath,
            operation: .enforceLimit,
            limit: limit,
            message: message
        )
        switch options.errorPolicy {
        case .collectIssues:
            guard issues.count < options.limits.maximumIssues else {
                throw issueLimitExceeded(relativePath: relativePath)
            }
            issues.append(limitIssue)
            if stopsScan { throw ScanStopped() }
        case .failClosed:
            throw FolderScanError.limitExceeded(limitIssue)
        }
    }

    private mutating func handle(_ issue: FolderScanIssue) throws {
        try Task.checkCancellation()
        switch options.errorPolicy {
        case .collectIssues:
            guard issues.count < options.limits.maximumIssues else {
                throw issueLimitExceeded(relativePath: issue.relativePath)
            }
            issues.append(issue)
        case .failClosed:
            throw FolderScanError.fileSystem(issue)
        }
    }

    private func issue(
        relativePath: String,
        operation: FolderScanIssue.Operation,
        error: any Error
    ) -> FolderScanIssue {
        let cocoaError = error as NSError
        return FolderScanIssue(
            relativePath: relativePath,
            operation: operation,
            errorDomain: cocoaError.domain,
            errorCode: cocoaError.code,
            containmentFailureReason: (error as? DirectoryContainmentRejected)?.reason
                ?? (error as? SymbolicLinkTargetContainmentRejected)?.reason,
            message: cocoaError.localizedDescription
        )
    }

    private func containmentFailureReason(for error: any Error) -> FolderScanContainmentFailureReason {
        let cocoaError = error as NSError
        if cocoaError.domain == NSPOSIXErrorDomain, cocoaError.code == Int(ESTALE) {
            return .race
        }
        return .indeterminate
    }

    private mutating func directoryEntryNames(
        directoryFD: Int32,
        relativePath: String,
        relativePathUTF8Bytes: Int,
        depth: Int
    ) throws -> (
        names: [String],
        reachedEntryLimit: Bool,
        reachedPendingNameLimit: Bool,
        reachedExaminedEntryLimit: Bool
    ) {
        let streamFD = try openOwnedDirectoryDescriptor(
            relativePath: relativePath,
            syscall: .duplicateDirectoryStream
        ) {
            Darwin.fcntl(directoryFD, F_DUPFD_CLOEXEC, 0)
        }
        guard let directory = Darwin.fdopendir(streamFD) else {
            let error = posixError()
            closeOwnedDirectoryDescriptor(streamFD)
            throw error
        }
        defer {
            let result = Darwin.closedir(directory)
            directoryDescriptorBudget.release()
            directoryDescriptorOwnershipObserver?(.released(streamFD, closeResult: result))
        }

        var names: [String] = []
        var reachedEntryLimit = false
        var reachedPendingNameLimit = false
        let remainingEntryCapacity = max(options.limits.maximumEntries - entries.count, 0)
        let remainingPendingNameCapacity = max(
            options.limits.maximumPendingEntryNames - pendingEntryNameCount,
            0
        )
        let retainedNameCapacity = min(remainingEntryCapacity, remainingPendingNameCapacity)
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let entry = Darwin.readdir(directory) else {
                if errno != 0 { throw posixError() }
                return (names, reachedEntryLimit, reachedPendingNameLimit, false)
            }
            guard let name = withUnsafePointer(to: &entry.pointee.d_name, { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    characters -> String? in
                    let buffer = UnsafeBufferPointer(
                        start: characters,
                        count: Int(MAXNAMLEN) + 1
                    )
                    guard let end = buffer.firstIndex(of: 0) else { return nil }
                    let bytes = buffer[..<end].map { UInt8(bitPattern: $0) }
                    if let decoder = FolderScanner.directoryEntryNameDecoder {
                        return decoder(bytes)
                    }
                    return validatedUTF8String(bytes)
                }
            }) else {
                guard consumeExaminedEntry() else {
                    return (names, reachedEntryLimit, reachedPendingNameLimit, true)
                }
                try handle(
                    FolderScanIssue(
                        relativePath: relativePath,
                        operation: .readMetadata,
                        errorDomain: NSPOSIXErrorDomain,
                        errorCode: Int(EILSEQ),
                        message: "Directory entry name is not valid UTF-8."
                    )
                )
                continue
            }
            guard name != "." && name != ".." else { continue }
            guard consumeExaminedEntry() else {
                return (names, reachedEntryLimit, reachedPendingNameLimit, true)
            }
            if options.hiddenFilePolicy == .excludeEntriesAndSymbolicLinkTargets {
                if name.hasPrefix(".") { continue }
                do {
                    if isHidden(
                        name: name,
                        status: try fileStatus(parentFD: directoryFD, name: name)
                    ) {
                        continue
                    }
                } catch {
                    try handle(
                        issue(
                            relativePath: relativePath.isEmpty
                                ? name : "\(relativePath)/\(name)",
                            operation: .readMetadata,
                            error: error
                        )
                    )
                    continue
                }
            }
            let childRelativePath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"
            let (childDepth, depthOverflow) = depth.addingReportingOverflow(1)
            guard !depthOverflow, childDepth <= options.limits.maximumDepth else {
                try handleLimit(
                    .depth,
                    relativePath: childRelativePath,
                    message: "Maximum scan depth was exceeded; entry was skipped."
                )
                continue
            }
            let separatorBytes = relativePath.isEmpty ? 0 : 1
            let (pathPrefixBytes, prefixOverflow) = relativePathUTF8Bytes.addingReportingOverflow(
                separatorBytes
            )
            let (childPathBytes, pathOverflow) = pathPrefixBytes.addingReportingOverflow(
                name.utf8.count
            )
            guard !prefixOverflow, !pathOverflow,
                childPathBytes <= options.limits.maximumRelativePathUTF8Bytes
            else {
                try handleLimit(
                    .relativePathUTF8Bytes,
                    relativePath: childRelativePath,
                    message: "Maximum relative path UTF-8 byte count was exceeded; entry was skipped."
                )
                continue
            }
            let reachedRetainedNameCapacity = retainDeterministicNamePrefix(
                name,
                capacity: retainedNameCapacity,
                names: &names
            )
            guard reachedRetainedNameCapacity else { continue }
            if names.count >= remainingEntryCapacity { reachedEntryLimit = true }
            if remainingPendingNameCapacity < remainingEntryCapacity,
                names.count >= remainingPendingNameCapacity
            {
                reachedPendingNameLimit = true
            }
        }
    }

    private func retainDeterministicNamePrefix(
        _ name: String,
        capacity: Int,
        names: inout [String]
    ) -> Bool {
        guard capacity > 0 else {
            return true
        }
        guard names.count == capacity else {
            names.append(name)
            var child = names.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard Self.utf8PathPrecedes(names[parent], names[child]) else { break }
                names.swapAt(parent, child)
                child = parent
            }
            return false
        }

        guard Self.utf8PathPrecedes(name, names[0]) else { return true }
        names[0] = name
        var parent = 0
        while true {
            let left = parent * 2 + 1
            guard left < names.count else { return true }
            let right = left + 1
            let largerChild = right < names.count
                && Self.utf8PathPrecedes(names[left], names[right]) ? right : left
            guard Self.utf8PathPrecedes(names[parent], names[largerChild]) else { return true }
            names.swapAt(parent, largerChild)
            parent = largerChild
        }
    }

    private mutating func consumeExaminedEntry() -> Bool {
        guard examinedEntryCount < options.limits.maximumExaminedEntries else { return false }
        examinedEntryCount += 1
        return true
    }

    private func fileStatus(parentFD: Int32, name: String) throws -> stat {
        var status = stat()
        let result = name.withCString {
            Darwin.fstatat(parentFD, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0 else { throw posixError() }
        return status
    }

    private mutating func openPinnedRootDirectoryFollowingInputSymlinks(
        at url: URL
    ) throws -> (descriptor: Int32, status: stat) {
        let descriptor: Int32
        do {
            descriptor = try openOwnedDirectoryDescriptor(
                relativePath: "",
                syscall: .openRoot
            ) {
                url.withUnsafeFileSystemRepresentation { path -> Int32 in
                    guard let path else {
                        errno = EINVAL
                        return -1
                    }
                    return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
                }
            }
        } catch let error as NSError
        where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOTDIR) {
            throw FolderScanError.rootIsNotDirectory(url.path)
        }

        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            let error = posixError()
            closeOwnedDirectoryDescriptor(descriptor)
            throw error
        }
        guard entryKind(for: status) == .folder else {
            closeOwnedDirectoryDescriptor(descriptor)
            throw FolderScanError.rootIsNotDirectory(url.path)
        }
        return (descriptor, status)
    }

    private mutating func openVerifiedDirectory(
        parentFD: Int32,
        name: String,
        expectedStatus: stat,
        syscall: FolderScanner.DirectoryDescriptorSyscall,
        relativePath: String
    ) throws -> (descriptor: Int32, status: stat) {
        let descriptor = try openOwnedDirectoryDescriptor(
            relativePath: relativePath,
            syscall: syscall
        ) {
            name.withCString {
                Darwin.openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
        }

        var actualStatus = stat()
        guard Darwin.fstat(descriptor, &actualStatus) == 0 else {
            let error = posixError()
            closeOwnedDirectoryDescriptor(descriptor)
            throw error
        }
        guard entryKind(for: actualStatus) == .folder,
            NodeIdentity(actualStatus) == NodeIdentity(expectedStatus)
        else {
            closeOwnedDirectoryDescriptor(descriptor)
            errno = ESTALE
            throw posixError()
        }
        return (descriptor, actualStatus)
    }

    private mutating func resolveDirectoryTargetWithinRoot(
        rootFD: Int32,
        parentFD: Int32,
        relativePath: String,
        targetPayload: String,
        originStatus: stat,
        excludesHiddenTargets: Bool
    ) throws -> DirectoryTargetResolution {
        let targetStartsAtRoot = targetPayload.hasPrefix("/")
        let initialDescriptor = try openOwnedDirectoryDescriptor(
            relativePath: relativePath,
            syscall: .openSymbolicLinkResolverInitial
        ) {
            targetStartsAtRoot
                ? Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                : Darwin.fcntl(parentFD, F_DUPFD_CLOEXEC, 0)
        }
        var current: Int32? = initialDescriptor
        defer {
            if let current {
                closeOwnedDirectoryDescriptor(current)
            }
        }

        var currentStatus = stat()
        guard Darwin.fstat(initialDescriptor, &currentStatus) == 0 else { throw posixError() }
        var originParentStatus = stat()
        guard Darwin.fstat(parentFD, &originParentStatus) == 0 else { throw posixError() }

        var components = pathComponents(targetPayload)
        var componentIndex = 0
        var visitedLinks: Set<SymbolicLinkResolutionState> = []
        var followedLinkCount = 1
        let originState = SymbolicLinkResolutionState(
            identity: NodeIdentity(originStatus),
            parentIdentity: NodeIdentity(originParentStatus),
            remainingComponents: components
        )
        visitedLinks.insert(originState)

        while componentIndex < components.count {
            try Task.checkCancellation()
            let component = components[componentIndex]
            componentIndex += 1
            if component == "." { continue }
            if component == ".." {
                guard let oldDescriptor = current else {
                    preconditionFailure("Directory descriptor ownership was lost during traversal")
                }
                let parentStatus = try fileStatus(parentFD: oldDescriptor, name: "..")
                guard entryKind(for: parentStatus) == .folder else {
                    errno = ESTALE
                    throw posixError()
                }
                let reopened = try openVerifiedDirectory(
                    parentFD: oldDescriptor,
                    name: "..",
                    expectedStatus: parentStatus,
                    syscall: .openSymbolicLinkResolverComponent,
                    relativePath: relativePath
                )
                closeOwnedDirectoryDescriptor(oldDescriptor)
                current = reopened.descriptor
                currentStatus = reopened.status
                continue
            }

            guard let currentDescriptor = current else {
                preconditionFailure("Directory descriptor ownership was lost during traversal")
            }
            let status = try fileStatus(parentFD: currentDescriptor, name: component)
            if excludesHiddenTargets && isHidden(name: component, status: status) {
                return .hidden
            }

            switch entryKind(for: status) {
            case .symbolicLink:
                guard followedLinkCount < Int(MAXSYMLINKS) else {
                    errno = ELOOP
                    throw posixError()
                }
                let payload = try symbolicLinkTarget(parentFD: currentDescriptor, name: component)
                let verifiedStatus = try verifySymbolicLink(
                    parentFD: currentDescriptor,
                    name: component,
                    expectedStatus: status,
                    expectedTarget: payload
                )
                if excludesHiddenTargets && isHidden(name: component, status: verifiedStatus) {
                    return .hidden
                }
                let payloadComponents = pathComponents(payload)
                let remainingComponents = Array(components[componentIndex...])
                let linkState = SymbolicLinkResolutionState(
                    identity: NodeIdentity(status),
                    parentIdentity: NodeIdentity(currentStatus),
                    remainingComponents: payloadComponents + remainingComponents
                )
                guard visitedLinks.insert(linkState).inserted else {
                    errno = ELOOP
                    throw posixError()
                }
                followedLinkCount += 1

                if payload.hasPrefix("/") {
                    let reopenedDescriptor = try openOwnedDirectoryDescriptor(
                        relativePath: relativePath,
                        syscall: .openSymbolicLinkResolverReopen
                    ) {
                        Darwin.open(
                            "/",
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                        )
                    }
                    var reopenedStatus = stat()
                    guard Darwin.fstat(reopenedDescriptor, &reopenedStatus) == 0 else {
                        let error = posixError()
                        closeOwnedDirectoryDescriptor(reopenedDescriptor)
                        throw error
                    }
                    components = payloadComponents + remainingComponents
                    componentIndex = 0
                    closeOwnedDirectoryDescriptor(currentDescriptor)
                    current = reopenedDescriptor
                    currentStatus = reopenedStatus
                } else {
                    components = payloadComponents + remainingComponents
                    componentIndex = 0
                }
            case .folder:
                let next = try openVerifiedDirectory(
                    parentFD: currentDescriptor,
                    name: component,
                    expectedStatus: status,
                    syscall: .openSymbolicLinkResolverComponent,
                    relativePath: relativePath
                )
                if excludesHiddenTargets && isHidden(name: component, status: next.status) {
                    closeOwnedDirectoryDescriptor(next.descriptor)
                    return .hidden
                }
                closeOwnedDirectoryDescriptor(currentDescriptor)
                current = next.descriptor
                currentStatus = next.status
            case .file, .other:
                return .nonDirectory
            }
        }

        guard let resultDescriptor = current else {
            preconditionFailure("Directory descriptor ownership was lost during traversal")
        }
        switch try provenDirectoryContainment(
            descriptor: resultDescriptor,
            rootFD: rootFD,
            relativePath: relativePath
        ) {
        case .contained:
            break
        case .rejected(let reason):
            return .rejected(reason)
        }
        var containedStatus = stat()
        guard Darwin.fstat(resultDescriptor, &containedStatus) == 0 else { throw posixError() }
        if excludesHiddenTargets && isHidden(name: "", status: containedStatus) {
            return .hidden
        }
        guard directorySnapshot(containedStatus, matches: currentStatus) else {
            errno = ESTALE
            throw posixError()
        }
        current = nil
        return .directory(descriptor: resultDescriptor, status: containedStatus)
    }

    private func closeOwnedDirectoryDescriptor(_ descriptor: Int32) {
        let result = Darwin.close(descriptor)
        directoryDescriptorBudget.release()
        directoryDescriptorOwnershipObserver?(.released(descriptor, closeResult: result))
    }

    private mutating func openOwnedDirectoryDescriptor(
        relativePath: String,
        syscall: FolderScanner.DirectoryDescriptorSyscall,
        operation: () -> Int32
    ) throws -> Int32 {
        guard directoryDescriptorBudget.acquire() else {
            try Task.checkCancellation()
            try handleLimit(
                .openDirectoryDescriptors,
                relativePath: relativePath,
                message: "Maximum live directory descriptor count was exceeded; scan was stopped.",
                stopsScan: true
            )
            preconditionFailure("Stopping descriptor limit did not throw")
        }
        do {
            try Task.checkCancellation()
        } catch {
            directoryDescriptorBudget.release()
            throw error
        }
        FolderScanner.directoryDescriptorSyscallObserver?(syscall)
        let descriptor = operation()
        guard descriptor >= 0 else {
            let error = posixError()
            directoryDescriptorBudget.release()
            throw error
        }
        directoryDescriptorOwnershipObserver?(.acquired(descriptor))
        do {
            try Task.checkCancellation()
        } catch {
            closeOwnedDirectoryDescriptor(descriptor)
            throw error
        }
        return descriptor
    }

    private func symbolicLinkTarget(parentFD: Int32, name: String) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = name.withCString {
            Darwin.readlinkat(parentFD, $0, &buffer, buffer.count - 1)
        }
        guard count >= 0 else { throw posixError() }
        guard count < buffer.count - 1 else {
            errno = ENAMETOOLONG
            throw posixError()
        }
        let bytes = buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }
        guard let target = validatedUTF8String(bytes) else {
            errno = EILSEQ
            throw posixError()
        }
        return target
    }

    @discardableResult
    private func verifySymbolicLink(
        parentFD: Int32,
        name: String,
        expectedStatus: stat,
        expectedTarget: String
    ) throws -> stat {
        let statusBeforePayload = try fileStatus(parentFD: parentFD, name: name)
        guard entryKind(for: statusBeforePayload) == .symbolicLink,
            SymbolicLinkSnapshot(statusBeforePayload) == SymbolicLinkSnapshot(expectedStatus)
        else {
            errno = ESTALE
            throw posixError()
        }
        FolderScanner.symbolicLinkFollowObserver?(.linkStatusReadBeforePayloadVerification)
        let actualTarget = try symbolicLinkTarget(parentFD: parentFD, name: name)
        FolderScanner.symbolicLinkFollowObserver?(.linkPayloadReadBeforeFinalStatusVerification)
        let statusAfterPayload = try fileStatus(parentFD: parentFD, name: name)
        guard actualTarget == expectedTarget,
            entryKind(for: statusAfterPayload) == .symbolicLink,
            SymbolicLinkSnapshot(statusAfterPayload) == SymbolicLinkSnapshot(statusBeforePayload)
        else {
            errno = ESTALE
            throw posixError()
        }
        return statusAfterPayload
    }

    private func directoryURL(for descriptor: Int32) throws -> URL {
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard Darwin.fcntl(descriptor, F_GETPATH, &path) == 0 else { throw posixError() }
        guard let end = path.firstIndex(of: 0),
            let value = validatedUTF8String(path[..<end].map { UInt8(bitPattern: $0) })
        else {
            errno = EILSEQ
            throw posixError()
        }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }

    private func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    fileprivate mutating func directoryContainment(
        descriptor: Int32,
        rootFD: Int32,
        relativePath: String = ""
    ) throws -> DirectoryContainment {
        var rootStatus = stat()
        guard Darwin.fstat(rootFD, &rootStatus) == 0 else { throw posixError() }
        let rootIdentity = NodeIdentity(rootStatus)
        let rootFileSystem = try fileSystemSnapshot(descriptor: rootFD)

        var current = try openOwnedDirectoryDescriptor(
            relativePath: relativePath,
            syscall: .duplicatePhysicalAncestry
        ) {
            Darwin.fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
        }
        var ownedDescriptors = [current]
        defer {
            for descriptor in ownedDescriptors.reversed() {
                closeOwnedDirectoryDescriptor(descriptor)
            }
        }
        var visited: Set<NodeIdentity> = []
        var ancestry: [PhysicalAncestor] = []

        while true {
            try Task.checkCancellation()
            var currentStatus = stat()
            guard Darwin.fstat(current, &currentStatus) == 0 else { throw posixError() }
            let currentIdentity = NodeIdentity(currentStatus)
            let currentFileSystem = try fileSystemSnapshot(descriptor: current)
            ancestry.append(PhysicalAncestor(
                descriptor: current,
                identity: currentIdentity,
                fileSystem: currentFileSystem
            ))
            if currentIdentity == rootIdentity {
                guard currentFileSystem.hasReliableIdentity
                    && rootFileSystem.hasReliableIdentity
                    && currentFileSystem == rootFileSystem
                else {
                    return .rejected(.indeterminate)
                }
                FolderScanner.physicalAncestryObserver?(.reachedRootBeforeFinalRevalidation)
                return try revalidatePhysicalAncestry(
                    ancestry,
                    rootIdentity: rootIdentity,
                    rootFileSystem: rootFileSystem
                )
            }
            guard visited.insert(currentIdentity).inserted else { return .rejected(.race) }

            let parentStatus = try fileStatus(parentFD: current, name: "..")
            guard entryKind(for: parentStatus) == .folder else {
                errno = ESTALE
                throw posixError()
            }
            let parent = try openVerifiedDirectory(
                parentFD: current,
                name: "..",
                expectedStatus: parentStatus,
                syscall: .openPhysicalAncestryParent,
                relativePath: relativePath
            )
            ownedDescriptors.append(parent.descriptor)
            if NodeIdentity(parent.status) == currentIdentity {
                return .rejected(.outside)
            }
            let parentFileSystem: FileSystemSnapshot
            parentFileSystem = try fileSystemSnapshot(descriptor: parent.descriptor)
            let transition = FolderScanner.PhysicalAncestryTransition(
                currentDevice: currentIdentity.device,
                currentInode: currentIdentity.inode,
                parentDevice: NodeIdentity(parent.status).device,
                parentInode: NodeIdentity(parent.status).inode,
                currentFileSystemID: (
                    currentFileSystem.id.first,
                    currentFileSystem.id.second
                ),
                parentFileSystemID: (
                    parentFileSystem.id.first,
                    parentFileSystem.id.second
                ),
                currentMountFlags: currentFileSystem.flags,
                parentMountFlags: parentFileSystem.flags,
                currentMountPoint: currentFileSystem.mountPoint,
                parentMountPoint: parentFileSystem.mountPoint,
                currentMountSource: currentFileSystem.mountSource,
                parentMountSource: parentFileSystem.mountSource,
                currentFileSystemType: currentFileSystem.type,
                parentFileSystemType: parentFileSystem.type
            )
            let injectedClassification =
                FolderScanner.physicalAncestryTransitionClassifier?(transition)
            let classification: FolderScanner.PhysicalAncestryTransitionClassification
            if let injectedClassification, injectedClassification != .automatic {
                classification = injectedClassification
            } else if !currentFileSystem.hasReliableIdentity
                || !parentFileSystem.hasReliableIdentity
                || currentIdentity.device != NodeIdentity(parent.status).device
            {
                classification = .unproven
            } else if currentFileSystem != parentFileSystem {
                classification = .mountRoot
            } else {
                classification = .continuous
            }
            switch classification {
            case .continuous:
                break
            case .mountRoot:
                return .rejected(.outside)
            case .unproven, .automatic:
                return .rejected(.indeterminate)
            }
            current = parent.descriptor
        }
    }

    private func revalidatePhysicalAncestry(
        _ ancestry: [PhysicalAncestor],
        rootIdentity: NodeIdentity,
        rootFileSystem: FileSystemSnapshot
    ) throws -> DirectoryContainment {
        guard let root = ancestry.last,
            root.identity == rootIdentity,
            root.fileSystem == rootFileSystem
        else {
            return .rejected(.race)
        }
        let firstPass: [PhysicalAncestorValidationSnapshot]
        do {
            firstPass = try physicalAncestryValidationSnapshots(ancestry)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .rejected(containmentFailureReason(for: error))
        }
        FolderScanner.physicalAncestryObserver?(.completedFinalRevalidationPass(1))
        let secondPass: [PhysicalAncestorValidationSnapshot]
        do {
            secondPass = try physicalAncestryValidationSnapshots(ancestry)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .rejected(containmentFailureReason(for: error))
        }
        FolderScanner.physicalAncestryObserver?(.completedFinalRevalidationPass(2))
        guard firstPass == secondPass else { return .rejected(.race) }
        return .contained
    }

    private func physicalAncestryValidationSnapshots(
        _ ancestry: [PhysicalAncestor]
    ) throws -> [PhysicalAncestorValidationSnapshot] {
        var snapshots: [PhysicalAncestorValidationSnapshot] = []
        snapshots.reserveCapacity(ancestry.count)
        for (index, ancestor) in ancestry.enumerated() {
            try Task.checkCancellation()
            var status = stat()
            guard Darwin.fstat(ancestor.descriptor, &status) == 0 else { throw posixError() }
            let fileSystem = try fileSystemSnapshot(descriptor: ancestor.descriptor)
            guard NodeIdentity(status) == ancestor.identity,
                fileSystem == ancestor.fileSystem
            else {
                errno = ESTALE
                throw posixError()
            }
            let parentIdentity: NodeIdentity?
            if index + 1 < ancestry.count {
                let parentStatus = try fileStatus(parentFD: ancestor.descriptor, name: "..")
                guard NodeIdentity(parentStatus) == ancestry[index + 1].identity else {
                    errno = ESTALE
                    throw posixError()
                }
                parentIdentity = NodeIdentity(parentStatus)
            } else {
                parentIdentity = nil
            }
            snapshots.append(PhysicalAncestorValidationSnapshot(
                identity: NodeIdentity(status),
                fileSystem: fileSystem,
                parentIdentity: parentIdentity
            ))
        }
        return snapshots
    }

    private func fileSystemSnapshot(descriptor: Int32) throws -> FileSystemSnapshot {
        var status = statfs()
        guard Darwin.fstatfs(descriptor, &status) == 0 else { throw posixError() }
        var mountPoint = status.f_mntonname
        var mountSource = status.f_mntfromname
        var fileSystemType = status.f_fstypename
        return FileSystemSnapshot(
            id: FileSystemID(first: status.f_fsid.val.0, second: status.f_fsid.val.1),
            flags: status.f_flags,
            mountPoint: try fixedFileSystemString(&mountPoint),
            mountSource: try fixedFileSystemString(&mountSource),
            type: try fixedFileSystemString(&fileSystemType)
        )
    }

    private func fixedFileSystemString<T>(_ value: inout T) throws -> String {
        let bytes = withUnsafeBytes(of: &value) { Array($0) }
        guard let end = bytes.firstIndex(of: 0),
            let string = validatedUTF8String(Array(bytes[..<end]))
        else {
            errno = EILSEQ
            throw posixError()
        }
        return string
    }

    private func directorySnapshot(_ status: stat, matches expectedStatus: stat) -> Bool {
        NodeIdentity(status) == NodeIdentity(expectedStatus)
            && status.st_ctimespec.tv_sec == expectedStatus.st_ctimespec.tv_sec
            && status.st_ctimespec.tv_nsec == expectedStatus.st_ctimespec.tv_nsec
    }

    private func isLocalFileURL(_ url: URL) -> Bool {
        guard url.isFileURL,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.user == nil,
            components.password == nil,
            components.port == nil
        else {
            return false
        }
        guard let host = components.host, !host.isEmpty else { return true }
        return host.caseInsensitiveCompare("localhost") == .orderedSame
    }

    private func validatedUTF8String(_ bytes: [UInt8]) -> String? {
        let value = String(decoding: bytes, as: UTF8.self)
        return value.utf8.elementsEqual(bytes) ? value : nil
    }

    private func isHidden(name: String, status: stat) -> Bool {
        name.hasPrefix(".") || status.st_flags & UInt32(UF_HIDDEN) != 0
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private func entryKind(for status: stat) -> FolderScanEntryKind {
        switch status.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFDIR):
            .folder
        case mode_t(S_IFLNK):
            .symbolicLink
        case mode_t(S_IFREG):
            .file
        default:
            .other
        }
    }

    private func modificationDate(for status: stat) -> Date {
        let timestamp = status.st_mtimespec
        return Date(
            timeIntervalSince1970: Double(timestamp.tv_sec) + Double(timestamp.tv_nsec) / 1_000_000_000
        )
    }

    private func validateLimits() throws {
        let limits = options.limits
        if limits.maximumDepth < 0 { throw FolderScanError.invalidLimit(.depth) }
        if limits.maximumEntries < 0 { throw FolderScanError.invalidLimit(.entries) }
        if limits.maximumExaminedEntries < 0 {
            throw FolderScanError.invalidLimit(.examinedEntries)
        }
        if limits.maximumIssues < 0 { throw FolderScanError.invalidLimit(.issues) }
        if limits.maximumOpenDirectoryDescriptors < 0 {
            throw FolderScanError.invalidLimit(.openDirectoryDescriptors)
        }
        if limits.maximumPendingEntryNames < 0 {
            throw FolderScanError.invalidLimit(.pendingEntryNames)
        }
        if limits.maximumRelativePathUTF8Bytes < 0 {
            throw FolderScanError.invalidLimit(.relativePathUTF8Bytes)
        }
        if limits.maximumTotalAccountedBytes < 0 {
            throw FolderScanError.invalidLimit(.totalAccountedBytes)
        }
    }

    private func issueLimitExceeded(relativePath: String) -> FolderScanError {
        .limitExceeded(FolderScanIssue(
            relativePath: relativePath,
            operation: .enforceLimit,
            limit: .issues,
            message: "Maximum issue count was exceeded; scan was stopped."
        ))
    }

    private static func utf8PathPrecedes(_ left: String, _ right: String) -> Bool {
        left.utf8.lexicographicallyPrecedes(right.utf8)
    }
}

extension FolderScanIssue.Operation {
    fileprivate var description: String {
        switch self {
        case .readDirectory:
            "read directory"
        case .readMetadata:
            "read metadata"
        case .followSymbolicLink:
            "follow symbolic link"
        case .preventRepeatedTraversal:
            "traverse directory"
        case .enforceLimit:
            "enforce limit"
        }
    }
}
