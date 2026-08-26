import CryptoKit
import Darwin
import Foundation

public enum ComparisonArchiveContainerFormat: String, CaseIterable, Equatable, Sendable {
    case zip
    case tar
    case sevenZip
}

public enum ComparisonArchiveCompressionFormat: String, CaseIterable, Equatable, Sendable {
    case store
    case deflate
    case bzip2
    case lzma
    case zstandard
}

public enum ComparisonArchiveInputKind: String, Equatable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case specialFile
}

public struct ComparisonArchiveInput: Equatable, Sendable {
    public let sourceRootURL: URL
    public let sourceRelativePath: String
    public let archiveRelativePath: String
    public let kind: ComparisonArchiveInputKind
    /// Expected regular-file size. Ignored for other input kinds.
    public let expectedByteCount: UInt64?
    /// Expected source modification date captured by an upstream directory snapshot.
    public let expectedModificationDate: Date?
    /// Expected regular-file digest captured by an upstream folder snapshot.
    public let expectedContentDigest: FolderContentDigest?
    fileprivate let sourceIdentityPolicy: ComparisonArchiveSourceIdentityPolicy

    public init(
        sourceRootURL: URL,
        sourceRelativePath: String,
        archiveRelativePath: String? = nil,
        kind: ComparisonArchiveInputKind,
        expectedByteCount: UInt64? = nil,
        expectedModificationDate: Date? = nil,
        expectedContentDigest: FolderContentDigest? = nil
    ) {
        self.init(
            sourceRootURL: sourceRootURL,
            sourceRelativePath: sourceRelativePath,
            archiveRelativePath: archiveRelativePath,
            kind: kind,
            expectedByteCount: expectedByteCount,
            expectedModificationDate: expectedModificationDate,
            expectedContentDigest: expectedContentDigest,
            sourceIdentityPolicy: .captureAfterOpeningPinnedRoot
        )
    }

    private init(
        sourceRootURL: URL,
        sourceRelativePath: String,
        archiveRelativePath: String?,
        kind: ComparisonArchiveInputKind,
        expectedByteCount: UInt64?,
        expectedModificationDate: Date?,
        expectedContentDigest: FolderContentDigest?,
        sourceIdentityPolicy: ComparisonArchiveSourceIdentityPolicy
    ) {
        self.sourceRootURL = sourceRootURL
        self.sourceRelativePath = sourceRelativePath
        self.archiveRelativePath = archiveRelativePath ?? sourceRelativePath
        self.kind = kind
        self.expectedByteCount = expectedByteCount
        self.expectedModificationDate = expectedModificationDate
        self.expectedContentDigest = expectedContentDigest
        self.sourceIdentityPolicy = sourceIdentityPolicy
    }

    public init(
        fileURL: URL,
        archiveRelativePath: String? = nil,
        expectedByteCount: UInt64? = nil
    ) throws {
        try Task.checkCancellation()
        let expectedModificationDate = try? fileURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        try Task.checkCancellation()
        let sourceRootURL = fileURL.deletingLastPathComponent()
        try Task.checkCancellation()
        let sourceRelativePath = fileURL.lastPathComponent
        self.init(
            sourceRootURL: sourceRootURL,
            sourceRelativePath: sourceRelativePath,
            archiveRelativePath: archiveRelativePath ?? sourceRelativePath,
            kind: .regularFile,
            expectedByteCount: expectedByteCount,
            expectedModificationDate: expectedModificationDate,
            expectedContentDigest: nil,
            sourceIdentityPolicy: .captureAfterOpeningPinnedRoot
        )
    }

    public init(
        sourceRootURL: URL,
        metadata: DirectoryEntryMetadata,
        archiveRelativePath: String? = nil
    ) {
        self.init(
            sourceRootURL: sourceRootURL,
            sourceRelativePath: metadata.relativePath,
            archiveRelativePath: archiveRelativePath ?? metadata.relativePath,
            kind: ComparisonArchiveInputKind(metadata.kind),
            expectedByteCount: metadata.byteCount,
            expectedModificationDate: metadata.modificationDate,
            expectedContentDigest: nil,
            sourceIdentityPolicy: .captureAfterOpeningPinnedRoot
        )
    }

    public init(
        sourceRootURL: URL,
        entry: FolderEntry,
        archiveRelativePath: String? = nil
    ) {
        self.init(
            sourceRootURL: sourceRootURL,
            sourceRelativePath: entry.relativePath,
            archiveRelativePath: archiveRelativePath ?? entry.relativePath,
            kind: ComparisonArchiveInputKind(entry.kind),
            expectedByteCount: entry.size,
            expectedModificationDate: entry.modificationDate,
            expectedContentDigest: entry.contentDigest,
            sourceIdentityPolicy: .captureAfterOpeningPinnedRoot
        )
    }
}

public enum ComparisonArchiveUnsupportedItemDisposition: String, Equatable, Sendable {
    case reject
    case omit
}

public struct ComparisonArchiveItemPolicy: Equatable, Sendable {
    public static let secureDefault = ComparisonArchiveItemPolicy()

    public let symbolicLinks: ComparisonArchiveUnsupportedItemDisposition
    public let specialFiles: ComparisonArchiveUnsupportedItemDisposition

    public init(
        symbolicLinks: ComparisonArchiveUnsupportedItemDisposition = .reject,
        specialFiles: ComparisonArchiveUnsupportedItemDisposition = .reject
    ) {
        self.symbolicLinks = symbolicLinks
        self.specialFiles = specialFiles
    }
}

public struct ComparisonArchivePlanLimits: Equatable, Sendable {
    public static let `default` = ComparisonArchivePlanLimits()

    public let maximumArchiveBytes: UInt64
    public let maximumEntryCount: Int
    public let maximumEntryUncompressedBytes: UInt64
    public let maximumTotalUncompressedBytes: UInt64
    public let maximumPathDepth: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: UInt64
    public let maximumTotalPathComponents: UInt64
    public let maximumSourceRoots: Int
    public let maximumOpenFileDescriptors: Int

    public init(
        maximumArchiveBytes: UInt64 = 512 * 1_024 * 1_024,
        maximumEntryCount: Int = Int(UInt16.max) - 1,
        maximumEntryUncompressedBytes: UInt64 = 1_024 * 1_024 * 1_024,
        maximumTotalUncompressedBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024,
        maximumPathDepth: Int = 128,
        maximumPathUTF8Bytes: Int = 4_096,
        maximumTotalPathUTF8Bytes: UInt64 = 64 * 1_024 * 1_024,
        maximumTotalPathComponents: UInt64 = 1_000_000,
        maximumSourceRoots: Int = 64,
        maximumOpenFileDescriptors: Int = 128
    ) {
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumEntryCount = maximumEntryCount
        self.maximumEntryUncompressedBytes = maximumEntryUncompressedBytes
        self.maximumTotalUncompressedBytes = maximumTotalUncompressedBytes
        self.maximumPathDepth = maximumPathDepth
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumTotalPathComponents = maximumTotalPathComponents
        self.maximumSourceRoots = maximumSourceRoots
        self.maximumOpenFileDescriptors = maximumOpenFileDescriptors
    }
}

public enum ComparisonArchiveLimit: String, Equatable, Sendable {
    case archiveBytes
    case entries
    case entryUncompressedBytes
    case totalUncompressedBytes
    case pathDepth
    case pathUTF8Bytes
    case totalPathUTF8Bytes
    case totalPathComponents
    case sourceRoots
    case openFileDescriptors
}

public enum ComparisonArchivePathRole: String, Equatable, Sendable {
    case source
    case archive
}

public enum ComparisonArchivePathFailure: String, Equatable, Sendable {
    case empty
    case absolute
    case containsBackslash
    case containsNull
    case emptyComponent
    case currentDirectoryComponent
    case parentTraversal
    case containsColon
    case trailingDotOrSpace
    case reservedDOSDeviceName
    case componentTooLong
    case pathTooLong
    case emptyCollisionKey
}

public enum ComparisonArchivePlanError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedContainerFormat(ComparisonArchiveContainerFormat)
    case unsupportedCompressionFormat(ComparisonArchiveCompressionFormat)
    case invalidLimit(ComparisonArchiveLimit)
    case invalidSourceRoot(String)
    case invalidRelativePath(role: ComparisonArchivePathRole, path: String, reason: ComparisonArchivePathFailure)
    case tooManyEntries(maximum: Int)
    case entryTooLarge(path: String, maximumBytes: UInt64)
    case totalUncompressedSizeTooLarge(maximumBytes: UInt64)
    case pathTooDeep(path: String, maximumDepth: Int)
    case totalPathSizeTooLarge(maximumBytes: UInt64)
    case tooManyPathComponents(maximum: UInt64)
    case tooManySourceRoots(maximum: Int)
    case tooManyOpenFileDescriptors(maximum: Int)
    case duplicateArchivePath(String)
    case caseFoldedPathConflict(first: String, second: String)
    case pathHierarchyConflict(ancestor: String, descendant: String)
    case selectedResultMissingSide(path: String, side: FolderComparisonSide)
    case invalidInputMetadata(path: String)
    case sourceUnavailable(path: String, errorCode: Int32)
    case sourceKindChanged(path: String, expected: ComparisonArchiveInputKind, actual: ComparisonArchiveInputKind)
    case sourceByteCountChanged(path: String, expected: UInt64, actual: UInt64)
    case sourceModificationTimeChanged(String)
    case unsupportedSourceDigest(path: String, algorithm: String)
    case sourceContentDigestChanged(String)
    case sourceChangedDuringPlanning(String)
    case unsupportedSourceItem(path: String, kind: ComparisonArchiveInputKind)
    case archiveTooLarge(maximumBytes: UInt64)

    public var errorDescription: String? {
        switch self {
        case .unsupportedContainerFormat(let format):
            "Comparison archive format is not supported: \(format.rawValue)."
        case .unsupportedCompressionFormat(let format):
            "Comparison archive compression is not supported: \(format.rawValue)."
        case .invalidLimit(let limit):
            "Comparison archive limit is invalid: \(limit.rawValue)."
        case .invalidSourceRoot(let value):
            "Comparison archive source root must be an absolute local directory URL: \(value)"
        case .invalidRelativePath(let role, let path, let reason):
            "Comparison archive \(role.rawValue) path is invalid (\(reason.rawValue)): \(path)"
        case .tooManyEntries(let maximum):
            "Comparison archive selection exceeds the \(maximum)-entry limit."
        case .entryTooLarge(let path, let maximumBytes):
            "Comparison archive entry exceeds the \(maximumBytes)-byte limit: \(path)"
        case .totalUncompressedSizeTooLarge(let maximumBytes):
            "Comparison archive contents exceed the \(maximumBytes)-byte uncompressed limit."
        case .pathTooDeep(let path, let maximumDepth):
            "Comparison archive path exceeds the \(maximumDepth)-component limit: \(path)"
        case .totalPathSizeTooLarge(let maximumBytes):
            "Comparison archive paths exceed the \(maximumBytes)-byte aggregate limit."
        case .tooManyPathComponents(let maximum):
            "Comparison archive paths exceed the \(maximum)-component aggregate limit."
        case .tooManySourceRoots(let maximum):
            "Comparison archive inputs exceed the \(maximum)-source-root limit."
        case .tooManyOpenFileDescriptors(let maximum):
            "Comparison archive planning would exceed the \(maximum)-descriptor limit."
        case .duplicateArchivePath(let path):
            "Comparison archive contains a duplicate normalized path: \(path)"
        case .caseFoldedPathConflict(let first, let second):
            "Comparison archive paths collide on common case-insensitive filesystems: \(first), \(second)"
        case .pathHierarchyConflict(let ancestor, let descendant):
            "Comparison archive file path is also an ancestor of another entry: \(ancestor), \(descendant)"
        case .selectedResultMissingSide(let path, let side):
            "Selected comparison result has no \(side.rawValue) item: \(path)"
        case .invalidInputMetadata(let path):
            "Comparison archive input metadata is inconsistent: \(path)"
        case .sourceUnavailable(let path, let errorCode):
            "Comparison archive source is unavailable (POSIX \(errorCode)): \(path)"
        case .sourceKindChanged(let path, let expected, let actual):
            "Comparison archive source kind changed from \(expected.rawValue) to \(actual.rawValue): \(path)"
        case .sourceByteCountChanged(let path, let expected, let actual):
            "Comparison archive source size changed from \(expected) to \(actual) bytes: \(path)"
        case .sourceModificationTimeChanged(let path):
            "Comparison archive source modification time changed: \(path)"
        case .unsupportedSourceDigest(let path, let algorithm):
            "Comparison archive source digest algorithm is unsupported (\(algorithm)): \(path)"
        case .sourceContentDigestChanged(let path):
            "Comparison archive source content digest changed: \(path)"
        case .sourceChangedDuringPlanning(let path):
            "Comparison archive source changed while its plan was being created: \(path)"
        case .unsupportedSourceItem(let path, let kind):
            "Comparison archive source is an unsupported \(kind.rawValue): \(path)"
        case .archiveTooLarge(let maximumBytes):
            "Comparison archive would exceed the \(maximumBytes)-byte archive limit."
        }
    }
}

public struct ComparisonArchiveFileIdentity: Equatable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let generation: UInt32

    fileprivate init(_ information: stat) {
        deviceID = UInt64(bitPattern: Int64(information.st_dev))
        fileID = UInt64(information.st_ino)
        generation = information.st_gen
    }
}

public struct ComparisonArchiveTimestamp: Equatable, Sendable {
    public let secondsSince1970: Int64
    public let nanoseconds: Int32

    fileprivate init(_ value: timespec) {
        secondsSince1970 = Int64(value.tv_sec)
        nanoseconds = Int32(value.tv_nsec)
    }
}

public struct ComparisonArchiveSourceSnapshot: Equatable, Sendable {
    public let identity: ComparisonArchiveFileIdentity
    public let kind: ComparisonArchiveInputKind
    public let byteCount: UInt64?
    public let modificationTime: ComparisonArchiveTimestamp
    public let statusChangeTime: ComparisonArchiveTimestamp
    public let contentDigest: FolderContentDigest?

    fileprivate init(
        _ information: stat,
        kind: ComparisonArchiveInputKind,
        contentDigest: FolderContentDigest?
    ) throws {
        guard information.st_mtimespec.tv_nsec >= 0,
            information.st_mtimespec.tv_nsec < 1_000_000_000,
            information.st_ctimespec.tv_nsec >= 0,
            information.st_ctimespec.tv_nsec < 1_000_000_000
        else {
            throw ComparisonArchivePlanError.sourceChangedDuringPlanning("")
        }
        if kind == .regularFile {
            guard information.st_size >= 0 else {
                throw ComparisonArchivePlanError.sourceChangedDuringPlanning("")
            }
            byteCount = UInt64(information.st_size)
        } else {
            byteCount = nil
        }
        identity = ComparisonArchiveFileIdentity(information)
        self.kind = kind
        modificationTime = ComparisonArchiveTimestamp(information.st_mtimespec)
        statusChangeTime = ComparisonArchiveTimestamp(information.st_ctimespec)
        self.contentDigest = contentDigest
    }
}

public struct ComparisonArchivePlannedSource: Equatable, Sendable {
    public let rootURL: URL
    public let rootIdentity: ComparisonArchiveFileIdentity
    public let relativePath: String
    public let snapshot: ComparisonArchiveSourceSnapshot
    fileprivate let pinnedRoot: ComparisonArchivePinnedRoot

    public static func == (left: Self, right: Self) -> Bool {
        left.rootURL == right.rootURL
            && left.rootIdentity == right.rootIdentity
            && left.relativePath == right.relativePath
            && left.snapshot == right.snapshot
    }

    /// Supplies the source-root descriptor pinned while this plan remains alive.
    public func withPinnedRootDescriptor<Result>(
        _ body: (Int32) throws -> Result
    ) throws -> Result {
        let descriptor = Darwin.fcntl(pinnedRoot.descriptor, F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0 else {
            throw ComparisonArchivePlanError.sourceUnavailable(
                path: relativePath,
                errorCode: errno
            )
        }
        defer { Darwin.close(descriptor) }
        return try body(descriptor)
    }
}

public struct ComparisonArchiveEntryMetadata: Equatable, Sendable {
    /// Fixed at 1980-01-01 00:00:00 UTC, the earliest portable ZIP timestamp.
    public static let reproducibleModificationTime = ComparisonArchiveTimestamp(
        secondsSince1970: 315_532_800,
        nanoseconds: 0
    )

    public let unixPermissions: UInt16
    public let modificationTime: ComparisonArchiveTimestamp

    fileprivate init(kind: ArchiveEntryKind) {
        unixPermissions = kind == .directory ? 0o700 : 0o600
        modificationTime = Self.reproducibleModificationTime
    }
}

public struct ComparisonArchivePlannedEntry: Equatable, Sendable {
    /// NFC-normalized, "/"-separated, and never directory-suffixed.
    public let relativePath: String
    public let kind: ArchiveEntryKind
    public let uncompressedByteCount: UInt64
    public let source: ComparisonArchivePlannedSource
    public let metadata: ComparisonArchiveEntryMetadata

    fileprivate init(
        relativePath: String,
        kind: ArchiveEntryKind,
        uncompressedByteCount: UInt64,
        source: ComparisonArchivePlannedSource
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.uncompressedByteCount = uncompressedByteCount
        self.source = source
        metadata = ComparisonArchiveEntryMetadata(kind: kind)
    }
}

public enum ComparisonArchiveOmissionReason: String, Equatable, Sendable {
    case symbolicLink
    case specialFile
}

public struct ComparisonArchiveOmission: Equatable, Sendable {
    public let sourceRootURL: URL
    public let sourceRelativePath: String
    public let archiveRelativePath: String
    public let reason: ComparisonArchiveOmissionReason

    fileprivate init(
        input: ComparisonArchiveInput,
        archiveRelativePath: String,
        reason: ComparisonArchiveOmissionReason
    ) {
        sourceRootURL = input.sourceRootURL
        sourceRelativePath = input.sourceRelativePath
        self.archiveRelativePath = archiveRelativePath
        self.reason = reason
    }
}

/// Immutable validated manifest. It performs no archive or destination writes.
public struct ComparisonArchivePlan: Equatable, Sendable {
    public static let manifestVersion = 1

    public let format: ComparisonArchiveContainerFormat
    public let compression: ComparisonArchiveCompressionFormat
    public let entries: [ComparisonArchivePlannedEntry]
    public let omissions: [ComparisonArchiveOmission]
    public let totalUncompressedByteCount: UInt64
    public let estimatedArchiveByteCount: UInt64
    public let totalPathUTF8ByteCount: UInt64
    public let totalPathComponentCount: UInt64
    public let limits: ComparisonArchivePlanLimits
    public let itemPolicy: ComparisonArchiveItemPolicy

    fileprivate init(
        format: ComparisonArchiveContainerFormat,
        compression: ComparisonArchiveCompressionFormat,
        entries: [ComparisonArchivePlannedEntry],
        omissions: [ComparisonArchiveOmission],
        totalUncompressedByteCount: UInt64,
        estimatedArchiveByteCount: UInt64,
        totalPathUTF8ByteCount: UInt64,
        totalPathComponentCount: UInt64,
        limits: ComparisonArchivePlanLimits,
        itemPolicy: ComparisonArchiveItemPolicy
    ) {
        self.format = format
        self.compression = compression
        self.entries = entries
        self.omissions = omissions
        self.totalUncompressedByteCount = totalUncompressedByteCount
        self.estimatedArchiveByteCount = estimatedArchiveByteCount
        self.totalPathUTF8ByteCount = totalPathUTF8ByteCount
        self.totalPathComponentCount = totalPathComponentCount
        self.limits = limits
        self.itemPolicy = itemPolicy
    }
}

public struct ComparisonArchivePlanner: Sendable {
    public static let supportedFormats: [ComparisonArchiveContainerFormat] = [.zip]
    public static let supportedCompressionFormats: [ComparisonArchiveCompressionFormat] = [.store]

    public let limits: ComparisonArchivePlanLimits
    public let itemPolicy: ComparisonArchiveItemPolicy

    public init(
        limits: ComparisonArchivePlanLimits = .default,
        itemPolicy: ComparisonArchiveItemPolicy = .secureDefault
    ) {
        self.limits = limits
        self.itemPolicy = itemPolicy
    }

    /// Plans exactly the selected rows on one side. A selected directory is one empty-directory entry;
    /// descendants are included only when they are independently selected.
    public func plan(
        selectedResults results: DirectoryResults,
        side: FolderComparisonSide,
        format: ComparisonArchiveContainerFormat = .zip,
        compression: ComparisonArchiveCompressionFormat = .store
    ) throws -> ComparisonArchivePlan {
        try Task.checkCancellation()
        try validateConfiguration(format: format, compression: compression)
        try validateCandidateCount(results.selectedIDs.count)
        let rootURL = side == .left ? results.leftRoot : results.rightRoot
        let selectedResults = results.selectedResults
        var inputs: [ComparisonArchiveInput] = []
        inputs.reserveCapacity(selectedResults.count)
        for result in selectedResults {
            try Task.checkCancellation()
            let metadata = side == .left ? result.left : result.right
            guard let metadata else {
                throw ComparisonArchivePlanError.selectedResultMissingSide(
                    path: result.relativePath,
                    side: side
                )
            }
            inputs.append(ComparisonArchiveInput(sourceRootURL: rootURL, metadata: metadata))
        }
        return try plan(inputs: inputs, format: format, compression: compression)
    }

    /// Plans caller-selected folder-comparison rows on one side.
    public func plan(
        selectedEntries entries: [FolderComparisonEntry],
        rootURL: URL,
        side: FolderComparisonSide,
        format: ComparisonArchiveContainerFormat = .zip,
        compression: ComparisonArchiveCompressionFormat = .store
    ) throws -> ComparisonArchivePlan {
        try Task.checkCancellation()
        try validateConfiguration(format: format, compression: compression)
        try validateCandidateCount(entries.count)
        var inputs: [ComparisonArchiveInput] = []
        inputs.reserveCapacity(entries.count)
        for comparisonEntry in entries {
            try Task.checkCancellation()
            let entry = side == .left ? comparisonEntry.left : comparisonEntry.right
            let displayPath =
                comparisonEntry.normalizedRelativePath
                ?? comparisonEntry.left?.relativePath
                ?? comparisonEntry.right?.relativePath
                ?? ""
            guard let entry else {
                throw ComparisonArchivePlanError.selectedResultMissingSide(
                    path: displayPath,
                    side: side
                )
            }
            inputs.append(ComparisonArchiveInput(sourceRootURL: rootURL, entry: entry))
        }
        return try plan(inputs: inputs, format: format, compression: compression)
    }

    public func plan(
        inputs: [ComparisonArchiveInput],
        format: ComparisonArchiveContainerFormat = .zip,
        compression: ComparisonArchiveCompressionFormat = .store
    ) throws -> ComparisonArchivePlan {
        try Task.checkCancellation()
        try validateConfiguration(format: format, compression: compression)
        try validateCandidateCount(inputs.count)

        var prepared: [ComparisonArchivePreparedInput] = []
        prepared.reserveCapacity(
            min(
                inputs.count,
                min(
                    Int(clamping: limits.maximumTotalPathUTF8Bytes),
                    Int(clamping: limits.maximumTotalPathComponents)
                )
            )
        )
        var preparedTotalPathBytes: UInt64 = 0
        var preparedTotalPathComponents: UInt64 = 0
        for input in inputs {
            try Task.checkCancellation()
            try validateSourceRootURL(input.sourceRootURL)
            try Task.checkCancellation()
            let normalizedArchivePath = try normalizedArchivePath(
                input.archiveRelativePath,
                remainingTotalPathUTF8Bytes: limits.maximumTotalPathUTF8Bytes
                    - preparedTotalPathBytes,
                remainingTotalPathComponents: limits.maximumTotalPathComponents
                    - preparedTotalPathComponents
            )
            preparedTotalPathBytes = try adding(
                UInt64(normalizedArchivePath.utf8ByteCount),
                to: preparedTotalPathBytes,
                maximum: limits.maximumTotalPathUTF8Bytes,
                error: .totalPathSizeTooLarge(maximumBytes: limits.maximumTotalPathUTF8Bytes)
            )
            preparedTotalPathComponents = try adding(
                UInt64(normalizedArchivePath.components.count),
                to: preparedTotalPathComponents,
                maximum: limits.maximumTotalPathComponents,
                error: .tooManyPathComponents(maximum: limits.maximumTotalPathComponents)
            )
            try Task.checkCancellation()
            let sourceComponents = try sourcePathComponents(input.sourceRelativePath)
            prepared.append(
                ComparisonArchivePreparedInput(
                    input: input,
                    sourceComponents: sourceComponents,
                    archivePath: normalizedArchivePath.path,
                    archiveComponents: normalizedArchivePath.components
                ))
        }

        prepared = try prepared.sorted { left, right in
            try Task.checkCancellation()
            return ComparisonArchivePreparedInput.precedes(left, right)
        }

        var roots: [String: ComparisonArchivePinnedRoot] = [:]
        var included: [ComparisonArchiveIncludedInput] = []
        included.reserveCapacity(prepared.count)
        var omissions: [ComparisonArchiveOmission] = []
        var inspectedTotalUncompressedBytes: UInt64 = 0
        for preparedInput in prepared {
            try Task.checkCancellation()
            let input = preparedInput.input
            try Task.checkCancellation()
            let rootKey = input.sourceRootURL.absoluteString
            let root: ComparisonArchivePinnedRoot
            if let existing = roots[rootKey] {
                root = existing
            } else {
                guard roots.count < limits.maximumSourceRoots else {
                    throw ComparisonArchivePlanError.tooManySourceRoots(
                        maximum: limits.maximumSourceRoots
                    )
                }
                guard roots.count + 3 <= limits.maximumOpenFileDescriptors else {
                    throw ComparisonArchivePlanError.tooManyOpenFileDescriptors(
                        maximum: limits.maximumOpenFileDescriptors
                    )
                }
                try Task.checkCancellation()
                root = try ComparisonArchivePinnedRoot(url: input.sourceRootURL)
                roots[rootKey] = root
            }
            guard roots.count + 2 <= limits.maximumOpenFileDescriptors else {
                throw ComparisonArchivePlanError.tooManyOpenFileDescriptors(
                    maximum: limits.maximumOpenFileDescriptors
                )
            }

            let inspected = try inspectSource(
                preparedInput,
                root: root,
                remainingTotalUncompressedBytes: limits.maximumTotalUncompressedBytes
                    - inspectedTotalUncompressedBytes
            )
            switch inspected {
            case .omitted(let reason):
                omissions.append(
                    ComparisonArchiveOmission(
                        input: input,
                        archiveRelativePath: preparedInput.archivePath,
                        reason: reason
                    ))
            case .included(let snapshot):
                inspectedTotalUncompressedBytes = try adding(
                    snapshot.byteCount ?? 0,
                    to: inspectedTotalUncompressedBytes,
                    maximum: limits.maximumTotalUncompressedBytes,
                    error: .totalUncompressedSizeTooLarge(
                        maximumBytes: limits.maximumTotalUncompressedBytes
                    )
                )
                included.append(
                    ComparisonArchiveIncludedInput(
                        prepared: preparedInput,
                        root: root,
                        snapshot: snapshot
                    ))
            }
        }

        guard included.count <= limits.maximumEntryCount else {
            throw ComparisonArchivePlanError.tooManyEntries(maximum: limits.maximumEntryCount)
        }
        try validateArchivePathCollisions(included.map(\.prepared))

        var plannedEntries: [ComparisonArchivePlannedEntry] = []
        plannedEntries.reserveCapacity(included.count)
        var totalPathBytes: UInt64 = 0
        var totalPathComponents: UInt64 = 0

        for includedInput in included {
            try Task.checkCancellation()
            let preparedInput = includedInput.prepared
            let input = preparedInput.input
            let snapshot = includedInput.snapshot
            let byteCount = snapshot.byteCount ?? 0
            guard byteCount <= limits.maximumEntryUncompressedBytes else {
                throw ComparisonArchivePlanError.entryTooLarge(
                    path: preparedInput.archivePath,
                    maximumBytes: limits.maximumEntryUncompressedBytes
                )
            }
            totalPathBytes += UInt64(preparedInput.archivePath.utf8.count)
            totalPathComponents += UInt64(preparedInput.archiveComponents.count)
            let kind: ArchiveEntryKind = snapshot.kind == .directory ? .directory : .file
            plannedEntries.append(
                ComparisonArchivePlannedEntry(
                    relativePath: preparedInput.archivePath,
                    kind: kind,
                    uncompressedByteCount: byteCount,
                    source: ComparisonArchivePlannedSource(
                        rootURL: includedInput.root.url,
                        rootIdentity: includedInput.root.identity,
                        relativePath: input.sourceRelativePath,
                        snapshot: snapshot,
                        pinnedRoot: includedInput.root
                    )
                ))
        }

        let archiveBytes = try estimatedStoredZIPByteCount(entries: plannedEntries)
        try Task.checkCancellation()
        return ComparisonArchivePlan(
            format: format,
            compression: compression,
            entries: plannedEntries,
            omissions: omissions,
            totalUncompressedByteCount: inspectedTotalUncompressedBytes,
            estimatedArchiveByteCount: archiveBytes,
            totalPathUTF8ByteCount: totalPathBytes,
            totalPathComponentCount: totalPathComponents,
            limits: limits,
            itemPolicy: itemPolicy
        )
    }

    private func validateConfiguration(
        format: ComparisonArchiveContainerFormat,
        compression: ComparisonArchiveCompressionFormat
    ) throws {
        guard limits.maximumEntryCount >= 0 else {
            throw ComparisonArchivePlanError.invalidLimit(.entries)
        }
        guard limits.maximumPathDepth >= 0 else {
            throw ComparisonArchivePlanError.invalidLimit(.pathDepth)
        }
        guard limits.maximumPathUTF8Bytes >= 0 else {
            throw ComparisonArchivePlanError.invalidLimit(.pathUTF8Bytes)
        }
        guard limits.maximumSourceRoots >= 0 else {
            throw ComparisonArchivePlanError.invalidLimit(.sourceRoots)
        }
        guard limits.maximumOpenFileDescriptors >= 0 else {
            throw ComparisonArchivePlanError.invalidLimit(.openFileDescriptors)
        }
        guard format == .zip else {
            throw ComparisonArchivePlanError.unsupportedContainerFormat(format)
        }
        guard compression == .store else {
            throw ComparisonArchivePlanError.unsupportedCompressionFormat(compression)
        }
    }

    private func validateCandidateCount(_ count: Int) throws {
        let maximum = min(limits.maximumEntryCount, Int(UInt16.max) - 1)
        guard count <= maximum else {
            throw ComparisonArchivePlanError.tooManyEntries(maximum: maximum)
        }
    }

    private func validateArchivePathCollisions(
        _ inputs: [ComparisonArchivePreparedInput]
    ) throws {
        var pathsByCollisionKey: [String: String] = [:]
        var directorySpellings: [String: String] = [:]
        var kindsByCollisionKey: [String: ComparisonArchiveInputKind] = [:]

        for prepared in inputs {
            try Task.checkCancellation()
            let path = prepared.archivePath
            let key = try comparisonArchiveCollisionKey(path)
            if let existing = pathsByCollisionKey[key] {
                if existing == path {
                    throw ComparisonArchivePlanError.duplicateArchivePath(path)
                }
                throw ComparisonArchivePlanError.caseFoldedPathConflict(
                    first: existing,
                    second: path
                )
            }
            pathsByCollisionKey[key] = path
            kindsByCollisionKey[key] = prepared.input.kind

            let directoryCount =
                prepared.input.kind == .directory
                ? prepared.archiveComponents.count
                : max(0, prepared.archiveComponents.count - 1)
            guard directoryCount > 0 else { continue }
            for count in 1...directoryCount {
                try Task.checkCancellation()
                let spelling = prepared.archiveComponents.prefix(count).joined(separator: "/")
                let spellingKey = try comparisonArchiveCollisionKey(spelling)
                if let existing = directorySpellings[spellingKey], existing != spelling {
                    throw ComparisonArchivePlanError.caseFoldedPathConflict(
                        first: existing,
                        second: spelling
                    )
                }
                directorySpellings[spellingKey] = spelling
            }
        }

        for prepared in inputs {
            try Task.checkCancellation()
            guard prepared.archiveComponents.count > 1 else { continue }
            for count in 1..<prepared.archiveComponents.count {
                let ancestor = prepared.archiveComponents.prefix(count).joined(separator: "/")
                let ancestorKey = try comparisonArchiveCollisionKey(ancestor)
                if kindsByCollisionKey[ancestorKey] == .regularFile {
                    throw ComparisonArchivePlanError.pathHierarchyConflict(
                        ancestor: pathsByCollisionKey[ancestorKey] ?? ancestor,
                        descendant: prepared.archivePath
                    )
                }
            }
        }
    }

    private func inspectSource(
        _ prepared: ComparisonArchivePreparedInput,
        root: ComparisonArchivePinnedRoot,
        remainingTotalUncompressedBytes: UInt64
    ) throws -> ComparisonArchiveInspectedSource {
        let input = prepared.input
        var parentFD = Darwin.fcntl(root.descriptor, F_DUPFD_CLOEXEC, 0)
        guard parentFD >= 0 else {
            throw ComparisonArchivePlanError.sourceUnavailable(
                path: input.sourceRelativePath,
                errorCode: errno
            )
        }
        defer { Darwin.close(parentFD) }

        for component in prepared.sourceComponents.dropLast() {
            try Task.checkCancellation()
            let nextFD = component.withCString {
                Darwin.openat(
                    parentFD,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard nextFD >= 0 else {
                throw ComparisonArchivePlanError.sourceUnavailable(
                    path: input.sourceRelativePath,
                    errorCode: errno
                )
            }
            Darwin.close(parentFD)
            parentFD = nextFD
        }

        let leaf = prepared.sourceComponents.last!
        var pathInformation = stat()
        let statusResult = leaf.withCString {
            Darwin.fstatat(parentFD, $0, &pathInformation, AT_SYMLINK_NOFOLLOW)
        }
        guard statusResult == 0 else {
            throw ComparisonArchivePlanError.sourceUnavailable(
                path: input.sourceRelativePath,
                errorCode: errno
            )
        }
        let expectedSourceIdentity: ComparisonArchiveExpectedSourceIdentity
        switch input.sourceIdentityPolicy {
        case .captureAfterOpeningPinnedRoot:
            expectedSourceIdentity = ComparisonArchiveExpectedSourceIdentity(pathInformation)
        }
        let actualKind = comparisonArchiveInputKind(pathInformation)
        guard actualKind == input.kind else {
            throw ComparisonArchivePlanError.sourceKindChanged(
                path: input.sourceRelativePath,
                expected: input.kind,
                actual: actualKind
            )
        }

        switch actualKind {
        case .symbolicLink:
            return try disposition(
                itemPolicy.symbolicLinks,
                input: input,
                reason: .symbolicLink
            )
        case .specialFile:
            return try disposition(
                itemPolicy.specialFiles,
                input: input,
                reason: .specialFile
            )
        case .regularFile, .directory:
            break
        }

        let flags =
            actualKind == .directory
            ? O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            : O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        let itemFD = leaf.withCString { Darwin.openat(parentFD, $0, flags) }
        guard itemFD >= 0 else {
            let code = errno
            if code == ELOOP || code == ENOENT || code == ENOTDIR {
                throw ComparisonArchivePlanError.sourceChangedDuringPlanning(
                    input.sourceRelativePath
                )
            }
            throw ComparisonArchivePlanError.sourceUnavailable(
                path: input.sourceRelativePath,
                errorCode: code
            )
        }
        defer { Darwin.close(itemFD) }
        var descriptorInformation = stat()
        guard Darwin.fstat(itemFD, &descriptorInformation) == 0 else {
            throw ComparisonArchivePlanError.sourceUnavailable(
                path: input.sourceRelativePath,
                errorCode: errno
            )
        }
        guard comparisonArchiveStatIsStable(pathInformation, descriptorInformation) else {
            throw ComparisonArchivePlanError.sourceChangedDuringPlanning(input.sourceRelativePath)
        }

        if actualKind == .regularFile {
            guard descriptorInformation.st_size >= 0 else {
                throw ComparisonArchivePlanError.sourceChangedDuringPlanning(
                    input.sourceRelativePath
                )
            }
            let actualByteCount = UInt64(descriptorInformation.st_size)
            if let expectedByteCount = input.expectedByteCount,
                expectedByteCount != actualByteCount
            {
                throw ComparisonArchivePlanError.sourceByteCountChanged(
                    path: input.sourceRelativePath,
                    expected: expectedByteCount,
                    actual: actualByteCount
                )
            }
            guard actualByteCount <= limits.maximumEntryUncompressedBytes else {
                throw ComparisonArchivePlanError.entryTooLarge(
                    path: prepared.archivePath,
                    maximumBytes: limits.maximumEntryUncompressedBytes
                )
            }
            guard actualByteCount <= remainingTotalUncompressedBytes else {
                throw ComparisonArchivePlanError.totalUncompressedSizeTooLarge(
                    maximumBytes: limits.maximumTotalUncompressedBytes
                )
            }
        }
        if !expectedSourceIdentity.matches(descriptorInformation) {
            throw ComparisonArchivePlanError.sourceChangedDuringPlanning(
                input.sourceRelativePath
            )
        }
        if let expectedModificationDate = input.expectedModificationDate {
            guard
                comparisonArchiveModificationDate(
                    expectedModificationDate,
                    matches: descriptorInformation.st_mtimespec
                )
            else {
                throw ComparisonArchivePlanError.sourceModificationTimeChanged(
                    input.sourceRelativePath
                )
            }
        }
        let contentDigest = try comparisonArchiveVerifiedDigest(
            input.expectedContentDigest,
            descriptor: itemFD,
            information: descriptorInformation,
            path: input.sourceRelativePath
        )
        let snapshot: ComparisonArchiveSourceSnapshot
        do {
            snapshot = try ComparisonArchiveSourceSnapshot(
                descriptorInformation,
                kind: actualKind,
                contentDigest: contentDigest
            )
        } catch {
            throw ComparisonArchivePlanError.sourceChangedDuringPlanning(input.sourceRelativePath)
        }
        return .included(snapshot)
    }

    private func disposition(
        _ disposition: ComparisonArchiveUnsupportedItemDisposition,
        input: ComparisonArchiveInput,
        reason: ComparisonArchiveOmissionReason
    ) throws -> ComparisonArchiveInspectedSource {
        switch disposition {
        case .reject:
            throw ComparisonArchivePlanError.unsupportedSourceItem(
                path: input.sourceRelativePath,
                kind: input.kind
            )
        case .omit:
            return .omitted(reason)
        }
    }

    private func estimatedStoredZIPByteCount(
        entries: [ComparisonArchivePlannedEntry]
    ) throws -> UInt64 {
        guard entries.count < Int(UInt16.max) else {
            throw ComparisonArchivePlanError.tooManyEntries(
                maximum: min(limits.maximumEntryCount, Int(UInt16.max) - 1)
            )
        }
        var total: UInt64 = 22
        guard total <= limits.maximumArchiveBytes else {
            throw ComparisonArchivePlanError.archiveTooLarge(
                maximumBytes: limits.maximumArchiveBytes
            )
        }
        for entry in entries {
            try Task.checkCancellation()
            let trailingSlashBytes: UInt64 = entry.kind == .directory ? 1 : 0
            let pathBytes = UInt64(entry.relativePath.utf8.count) + trailingSlashBytes
            guard pathBytes <= UInt64(UInt16.max),
                entry.uncompressedByteCount <= UInt64(UInt32.max)
            else {
                throw ComparisonArchivePlanError.archiveTooLarge(
                    maximumBytes: limits.maximumArchiveBytes
                )
            }
            let (namesSize, namesOverflow) = pathBytes.multipliedReportingOverflow(by: 2)
            let (headersSize, headersOverflow) = namesSize.addingReportingOverflow(76)
            let (entrySize, entryOverflow) = headersSize.addingReportingOverflow(
                entry.uncompressedByteCount
            )
            let (next, totalOverflow) = total.addingReportingOverflow(entrySize)
            guard !namesOverflow,
                !headersOverflow,
                !entryOverflow,
                !totalOverflow,
                next <= limits.maximumArchiveBytes,
                next <= UInt64(UInt32.max)
            else {
                throw ComparisonArchivePlanError.archiveTooLarge(
                    maximumBytes: limits.maximumArchiveBytes
                )
            }
            total = next
        }
        return total
    }

    private func validateSourceRootURL(_ url: URL) throws {
        try Task.checkCancellation()
        let serializedURL = url.absoluteString
        let redactedURL = comparisonArchiveRedactedURLDescription(url)
        guard serializedURL.utf8.count <= Int(PATH_MAX) * 3 else {
            throw ComparisonArchivePlanError.invalidSourceRoot(redactedURL)
        }
        try Task.checkCancellation()
        let host = url.host?.lowercased(with: Locale(identifier: "en_US_POSIX"))
        try Task.checkCancellation()
        let components = url.pathComponents
        guard url.isFileURL,
            url.baseURL == nil,
            host == nil || host == "" || host == "localhost",
            url.user == nil,
            url.password == nil,
            url.port == nil,
            url.query == nil,
            url.fragment == nil,
            url.path.hasPrefix("/"),
            !url.path.hasPrefix("//"),
            !url.path.contains("//"),
            !url.path.contains("\0"),
            components.first == "/",
            components.dropFirst().allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/")
            })
        else {
            throw ComparisonArchivePlanError.invalidSourceRoot(redactedURL)
        }
    }

    private func sourcePathComponents(_ path: String) throws -> [String] {
        try Task.checkCancellation()
        guard !path.isEmpty else { throw pathError(.source, path, .empty) }
        guard !path.hasPrefix("/") else { throw pathError(.source, path, .absolute) }
        guard !path.contains("\\") else { throw pathError(.source, path, .containsBackslash) }
        guard !path.contains("\0") else { throw pathError(.source, path, .containsNull) }
        guard path.utf8.count <= 4_096 else { throw pathError(.source, path, .pathTooLong) }

        try Task.checkCancellation()
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for component in components {
            guard !component.isEmpty else { throw pathError(.source, path, .emptyComponent) }
            guard component != "." else { throw pathError(.source, path, .currentDirectoryComponent) }
            guard component != ".." else { throw pathError(.source, path, .parentTraversal) }
            guard component.utf8.count <= 255 else {
                throw pathError(.source, path, .componentTooLong)
            }
        }
        return components
    }

    private func normalizedArchivePath(
        _ path: String,
        remainingTotalPathUTF8Bytes: UInt64,
        remainingTotalPathComponents: UInt64
    ) throws -> (path: String, components: [String], utf8ByteCount: Int) {
        try Task.checkCancellation()
        guard !path.isEmpty else { throw pathError(.archive, path, .empty) }
        guard !path.hasPrefix("/") else { throw pathError(.archive, path, .absolute) }
        guard !path.contains("\\") else { throw pathError(.archive, path, .containsBackslash) }
        guard !path.contains("\0") else { throw pathError(.archive, path, .containsNull) }
        let inputUTF8ByteCount = path.utf8.count
        guard inputUTF8ByteCount <= limits.maximumPathUTF8Bytes else {
            throw pathError(.archive, path, .pathTooLong)
        }
        guard UInt64(inputUTF8ByteCount) <= remainingTotalPathUTF8Bytes else {
            throw ComparisonArchivePlanError.totalPathSizeTooLarge(
                maximumBytes: limits.maximumTotalPathUTF8Bytes
            )
        }
        guard limits.maximumPathDepth > 0 else {
            throw ComparisonArchivePlanError.pathTooDeep(
                path: path,
                maximumDepth: limits.maximumPathDepth
            )
        }
        guard remainingTotalPathComponents > 0 else {
            throw ComparisonArchivePlanError.tooManyPathComponents(
                maximum: limits.maximumTotalPathComponents
            )
        }

        var components: [String] = []
        var pathUTF8ByteCount = 0
        let maximumComponentCount = min(
            limits.maximumPathDepth,
            Int(clamping: remainingTotalPathComponents)
        )
        try Task.checkCancellation()
        let rawComponents = path.split(
            separator: "/",
            maxSplits: maximumComponentCount,
            omittingEmptySubsequences: false
        )
        guard rawComponents.count <= maximumComponentCount else {
            if maximumComponentCount == limits.maximumPathDepth {
                throw ComparisonArchivePlanError.pathTooDeep(
                    path: path,
                    maximumDepth: limits.maximumPathDepth
                )
            }
            throw ComparisonArchivePlanError.tooManyPathComponents(
                maximum: limits.maximumTotalPathComponents
            )
        }
        for rawComponent in rawComponents {
            try Task.checkCancellation()
            guard !rawComponent.isEmpty else {
                throw pathError(.archive, path, .emptyComponent)
            }
            guard rawComponent != "." else {
                throw pathError(.archive, path, .currentDirectoryComponent)
            }
            guard rawComponent != ".." else { throw pathError(.archive, path, .parentTraversal) }
            try Task.checkCancellation()
            let component = String(rawComponent).precomposedStringWithCanonicalMapping
            guard !component.contains(":") else {
                throw pathError(.archive, path, .containsColon)
            }
            guard component.last != ".", component.last != " " else {
                throw pathError(.archive, path, .trailingDotOrSpace)
            }
            guard !comparisonArchiveIsReservedDOSDeviceName(component) else {
                throw pathError(.archive, path, .reservedDOSDeviceName)
            }
            guard component.utf8.count <= 255 else {
                throw pathError(.archive, path, .componentTooLong)
            }
            guard try !comparisonArchiveCollisionKey(component).isEmpty else {
                throw pathError(.archive, path, .emptyCollisionKey)
            }
            guard components.count < limits.maximumPathDepth else {
                throw ComparisonArchivePlanError.pathTooDeep(
                    path: path,
                    maximumDepth: limits.maximumPathDepth
                )
            }
            guard UInt64(components.count) < remainingTotalPathComponents else {
                throw ComparisonArchivePlanError.tooManyPathComponents(
                    maximum: limits.maximumTotalPathComponents
                )
            }
            let separatorByteCount = components.isEmpty ? 0 : 1
            let (nextPathUTF8ByteCount, overflow) = pathUTF8ByteCount.addingReportingOverflow(
                separatorByteCount + component.utf8.count
            )
            guard !overflow, nextPathUTF8ByteCount <= limits.maximumPathUTF8Bytes else {
                throw pathError(.archive, path, .pathTooLong)
            }
            guard UInt64(nextPathUTF8ByteCount) <= remainingTotalPathUTF8Bytes else {
                throw ComparisonArchivePlanError.totalPathSizeTooLarge(
                    maximumBytes: limits.maximumTotalPathUTF8Bytes
                )
            }
            components.append(component)
            pathUTF8ByteCount = nextPathUTF8ByteCount
        }
        guard !components.isEmpty else { throw pathError(.archive, path, .empty) }
        try Task.checkCancellation()
        return (components.joined(separator: "/"), components, pathUTF8ByteCount)
    }

    private func pathError(
        _ role: ComparisonArchivePathRole,
        _ path: String,
        _ reason: ComparisonArchivePathFailure
    ) -> ComparisonArchivePlanError {
        .invalidRelativePath(role: role, path: path, reason: reason)
    }

    private func adding(
        _ value: UInt64,
        to total: UInt64,
        maximum: UInt64,
        error: ComparisonArchivePlanError
    ) throws -> UInt64 {
        let (next, overflow) = total.addingReportingOverflow(value)
        guard !overflow, next <= maximum else { throw error }
        return next
    }
}

private struct ComparisonArchivePreparedInput {
    let input: ComparisonArchiveInput
    let sourceComponents: [String]
    let archivePath: String
    let archiveComponents: [String]

    static func precedes(
        _ left: ComparisonArchivePreparedInput,
        _ right: ComparisonArchivePreparedInput
    ) -> Bool {
        if left.archivePath != right.archivePath {
            return comparisonArchiveUTF8Precedes(left.archivePath, right.archivePath)
        }
        let leftRoot = left.input.sourceRootURL.absoluteString
        let rightRoot = right.input.sourceRootURL.absoluteString
        if leftRoot != rightRoot {
            return comparisonArchiveUTF8Precedes(leftRoot, rightRoot)
        }
        return comparisonArchiveUTF8Precedes(
            left.input.sourceRelativePath,
            right.input.sourceRelativePath
        )
    }
}

private struct ComparisonArchiveIncludedInput {
    let prepared: ComparisonArchivePreparedInput
    let root: ComparisonArchivePinnedRoot
    let snapshot: ComparisonArchiveSourceSnapshot
}

private enum ComparisonArchiveInspectedSource {
    case included(ComparisonArchiveSourceSnapshot)
    case omitted(ComparisonArchiveOmissionReason)
}

private enum ComparisonArchiveSourceIdentityPolicy: Equatable, Sendable {
    case captureAfterOpeningPinnedRoot
}

private struct ComparisonArchiveExpectedSourceIdentity: Equatable, Sendable {
    let identity: ComparisonArchiveFileIdentity
    let statusChangeTime: ComparisonArchiveTimestamp

    init(_ information: stat) {
        identity = ComparisonArchiveFileIdentity(information)
        statusChangeTime = ComparisonArchiveTimestamp(information.st_ctimespec)
    }

    func matches(_ information: stat) -> Bool {
        identity == ComparisonArchiveFileIdentity(information)
            && statusChangeTime == ComparisonArchiveTimestamp(information.st_ctimespec)
    }
}

private final class ComparisonArchivePinnedRoot: @unchecked Sendable {
    let url: URL
    let descriptor: Int32
    let identity: ComparisonArchiveFileIdentity
    private let hasSecurityScopedAccess: Bool

    init(url requestedURL: URL) throws {
        let hasSecurityScopedAccess = requestedURL.startAccessingSecurityScopedResource()
        url = requestedURL
        self.hasSecurityScopedAccess = hasSecurityScopedAccess
        do {
            try Task.checkCancellation()
            let openedDescriptor = try comparisonArchiveOpenAbsoluteDirectory(requestedURL)
            var information = stat()
            guard Darwin.fstat(openedDescriptor, &information) == 0 else {
                let code = errno
                Darwin.close(openedDescriptor)
                throw ComparisonArchivePlanError.sourceUnavailable(
                    path: requestedURL.path,
                    errorCode: code
                )
            }
            descriptor = openedDescriptor
            identity = ComparisonArchiveFileIdentity(information)
        } catch {
            if hasSecurityScopedAccess { requestedURL.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    deinit {
        Darwin.close(descriptor)
        if hasSecurityScopedAccess { url.stopAccessingSecurityScopedResource() }
    }
}

extension ComparisonArchiveTimestamp {
    fileprivate init(secondsSince1970: Int64, nanoseconds: Int32) {
        self.secondsSince1970 = secondsSince1970
        self.nanoseconds = nanoseconds
    }
}

extension ComparisonArchiveInputKind {
    fileprivate init(_ kind: DirectoryEntryKind) {
        switch kind {
        case .file: self = .regularFile
        case .directory: self = .directory
        case .symbolicLink: self = .symbolicLink
        case .other: self = .specialFile
        }
    }

    fileprivate init(_ kind: FolderEntryKind) {
        switch kind {
        case .regularFile: self = .regularFile
        case .directory: self = .directory
        case .symbolicLink: self = .symbolicLink
        case .other: self = .specialFile
        }
    }
}

private func comparisonArchiveOpenAbsoluteDirectory(_ url: URL) throws -> Int32 {
    try Task.checkCancellation()
    let current = url.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else {
            errno = EINVAL
            return -1
        }
        return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard current >= 0 else {
        throw ComparisonArchivePlanError.sourceUnavailable(path: url.path, errorCode: errno)
    }
    do {
        try Task.checkCancellation()
        var descriptorInformation = stat()
        guard Darwin.fstat(current, &descriptorInformation) == 0 else {
            throw ComparisonArchivePlanError.sourceUnavailable(path: url.path, errorCode: errno)
        }
        var pathInformation = stat()
        try Task.checkCancellation()
        guard url.path.withCString({ Darwin.lstat($0, &pathInformation) }) == 0 else {
            throw ComparisonArchivePlanError.sourceUnavailable(path: url.path, errorCode: errno)
        }
        guard comparisonArchiveStatIsStable(pathInformation, descriptorInformation) else {
            throw ComparisonArchivePlanError.sourceChangedDuringPlanning(url.path)
        }
        return current
    } catch {
        Darwin.close(current)
        throw error
    }
}

private func comparisonArchiveInputKind(_ information: stat) -> ComparisonArchiveInputKind {
    switch information.st_mode & mode_t(S_IFMT) {
    case mode_t(S_IFREG): .regularFile
    case mode_t(S_IFDIR): .directory
    case mode_t(S_IFLNK): .symbolicLink
    default: .specialFile
    }
}

private func comparisonArchiveRedactedURLDescription(_ url: URL) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return "<invalid URL>"
    }
    components.user = nil
    components.password = nil
    components.query = nil
    components.fragment = nil
    return components.string ?? "<invalid URL>"
}

private func comparisonArchiveStatIsStable(_ first: stat, _ second: stat) -> Bool {
    ComparisonArchiveFileIdentity(first) == ComparisonArchiveFileIdentity(second)
        && comparisonArchiveInputKind(first) == comparisonArchiveInputKind(second)
        && first.st_size == second.st_size
        && first.st_mtimespec.tv_sec == second.st_mtimespec.tv_sec
        && first.st_mtimespec.tv_nsec == second.st_mtimespec.tv_nsec
        && first.st_ctimespec.tv_sec == second.st_ctimespec.tv_sec
        && first.st_ctimespec.tv_nsec == second.st_ctimespec.tv_nsec
}

private func comparisonArchiveModificationDate(
    _ date: Date,
    matches timestamp: timespec
) -> Bool {
    let interval = date.timeIntervalSince1970
    guard interval.isFinite else { return false }
    let actual = Double(timestamp.tv_sec) + Double(timestamp.tv_nsec) / 1_000_000_000
    return date == Date(timeIntervalSince1970: actual)
}

private func comparisonArchiveVerifiedDigest(
    _ expected: FolderContentDigest?,
    descriptor: Int32,
    information: stat,
    path: String
) throws -> FolderContentDigest? {
    guard let expected else { return nil }
    guard comparisonArchiveInputKind(information) == .regularFile else {
        throw ComparisonArchivePlanError.invalidInputMetadata(path: path)
    }
    try Task.checkCancellation()
    let algorithm = expected.algorithm
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
    guard algorithm == "sha256" || algorithm == "sha-256" else {
        throw ComparisonArchivePlanError.unsupportedSourceDigest(
            path: path,
            algorithm: expected.algorithm
        )
    }
    guard expected.bytes.count == SHA256.Digest.byteCount else {
        throw ComparisonArchivePlanError.invalidInputMetadata(path: path)
    }
    guard information.st_size >= 0 else {
        throw ComparisonArchivePlanError.sourceChangedDuringPlanning(path)
    }
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 1_048_576)
    var offset: off_t = 0
    let expectedByteCount = UInt64(information.st_size)
    while UInt64(offset) < expectedByteCount {
        try Task.checkCancellation()
        let remaining = expectedByteCount - UInt64(offset)
        let requestedByteCount = Int(min(remaining, UInt64(buffer.count)))
        let byteCount = buffer.withUnsafeMutableBytes { bytes in
            Darwin.pread(descriptor, bytes.baseAddress, requestedByteCount, offset)
        }
        if byteCount < 0 {
            if errno == EINTR { continue }
            throw ComparisonArchivePlanError.sourceUnavailable(path: path, errorCode: errno)
        }
        guard byteCount > 0 else {
            throw ComparisonArchivePlanError.sourceChangedDuringPlanning(path)
        }
        hasher.update(data: Data(buffer[0..<byteCount]))
        offset += off_t(byteCount)
    }
    var finalInformation = stat()
    guard Darwin.fstat(descriptor, &finalInformation) == 0 else {
        throw ComparisonArchivePlanError.sourceUnavailable(path: path, errorCode: errno)
    }
    guard comparisonArchiveStatIsStable(information, finalInformation) else {
        throw ComparisonArchivePlanError.sourceChangedDuringPlanning(path)
    }
    let actual = Data(hasher.finalize())
    guard actual == expected.bytes else {
        throw ComparisonArchivePlanError.sourceContentDigestChanged(path)
    }
    try Task.checkCancellation()
    return FolderContentDigest(algorithm: "sha256", bytes: actual)
}

private func comparisonArchiveCollisionKey(_ path: String) throws -> String {
    try Task.checkCancellation()
    let hfsPlusFiltered = String(
        path.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x200C...0x200F, 0x202A...0x202E, 0x206A...0x206F, 0xFEFF:
                false
            default:
                true
            }
        }
    )
    try Task.checkCancellation()
    return hfsPlusFiltered.precomposedStringWithCanonicalMapping.folding(
        options: .caseInsensitive,
        locale: Locale(identifier: "en_US_POSIX")
    )
}

private func comparisonArchiveIsReservedDOSDeviceName(_ component: String) -> Bool {
    var stem = String(
        component.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
    )
    while stem.last == "." || stem.last == " " { stem.removeLast() }
    stem = stem.lowercased(with: Locale(identifier: "en_US_POSIX"))
    if stem == "con" || stem == "prn" || stem == "aux" || stem == "nul"
        || stem == "clock$" || stem == "conin$" || stem == "conout$"
    {
        return true
    }
    guard stem.count == 4, let suffix = stem.last else {
        return false
    }
    let hasReservedPrefix = stem.hasPrefix("com") || stem.hasPrefix("lpt")
    return hasReservedPrefix
        && (("1"..."9").contains(String(suffix)) || suffix == "¹" || suffix == "²" || suffix == "³")
}

private func comparisonArchiveUTF8Precedes(_ left: String, _ right: String) -> Bool {
    left.utf8.lexicographicallyPrecedes(right.utf8)
}
