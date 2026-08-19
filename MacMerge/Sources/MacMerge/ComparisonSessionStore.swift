import Darwin
import Foundation
import MacMergeCore

struct ComparisonSessionStore: Sendable {
    private static let readChunkSize = 64 * 1024
    private static let lock = NSLock()
    private static let lockFileName = ".ComparisonSession.lock"

    let fileURL: URL

    enum LoadResult: Sendable {
        case success(ComparisonSessionState?)
        case corrupt(String, cleared: Bool)
        case failed(String)
    }

    private enum StoreError: LocalizedError {
        case invalidSessionLocation
        case invalidSessionFile
        case sessionChanged

        var errorDescription: String? {
            switch self {
            case .invalidSessionLocation:
                "Saved comparison session location is invalid."
            case .invalidSessionFile:
                "Saved comparison session is not a regular file."
            case .sessionChanged:
                "Saved comparison session changed while it was being read."
            }
        }
    }

    fileprivate struct FileSnapshot: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let mode: mode_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
            mode = status.st_mode
            size = status.st_size
            modifiedSeconds = status.st_mtimespec.tv_sec
            modifiedNanoseconds = status.st_mtimespec.tv_nsec
            changedSeconds = status.st_ctimespec.tv_sec
            changedNanoseconds = status.st_ctimespec.tv_nsec
        }
    }

    fileprivate struct FileIdentity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let generation: UInt32
        let type: mode_t

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
            generation = status.st_gen
            type = status.st_mode & S_IFMT
        }
    }

    private struct LoadedFile {
        let data: Data
    }

    struct SaveReceipt: Sendable {
        fileprivate let identity: FileIdentity
        fileprivate let data: Data
    }

    struct SaveCommitError: LocalizedError, Sendable {
        let receipt: SaveReceipt
        private let message: String

        init(receipt: SaveReceipt, underlyingError: Error) {
            self.receipt = receipt
            message = underlyingError.localizedDescription
        }

        var errorDescription: String? { message }
    }

    private struct LockedDirectory {
        let descriptor: Int32
        let lockDescriptor: Int32

        func close() {
            _ = Darwin.lockf(lockDescriptor, F_ULOCK, 0)
            Darwin.close(lockDescriptor)
            Darwin.close(descriptor)
        }
    }

    static func applicationSupportStore(fileManager: FileManager = .default) -> ComparisonSessionStore {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return ComparisonSessionStore(
            fileURL:
                applicationSupport
                .appending(path: "MacMerge", directoryHint: .isDirectory)
                .appending(path: "ComparisonSession.json")
        )
    }

    func load() throws -> ComparisonSessionState? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let directory = try openLockedDirectory(createIfNeeded: false) else { return nil }
        defer { directory.close() }
        guard let loaded = try readLocked(in: directory.descriptor) else { return nil }
        return try ComparisonSessionState.decode(from: loaded.data)
    }

    func loadAndClearCorrupt() -> LoadResult {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        do {
            guard let directory = try openLockedDirectory(createIfNeeded: false) else {
                return .success(nil)
            }
            defer { directory.close() }
            return loadAndClearCorruptLocked(in: directory.descriptor)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func loadAndClearCorruptLocked(in directoryDescriptor: Int32) -> LoadResult {
        let loaded: LoadedFile
        do {
            guard let value = try readLocked(in: directoryDescriptor) else { return .success(nil) }
            loaded = value
        } catch ComparisonSessionStateError.encodedDataTooLarge {
            return .failed("Saved data exceeds the supported size limit.")
        } catch ComparisonSessionStateError.schemaProbeLimitExceeded {
            return .failed("Saved data uses an unsupported format that could not be inspected safely.")
        } catch StoreError.sessionChanged {
            return .failed(StoreError.sessionChanged.localizedDescription)
        } catch StoreError.invalidSessionFile {
            do {
                let cleared = try quarantineInvalidFile(in: directoryDescriptor)
                return cleared
                    ? .corrupt(StoreError.invalidSessionFile.localizedDescription, cleared: true)
                    : .failed(StoreError.sessionChanged.localizedDescription)
            } catch {
                return .corrupt(StoreError.invalidSessionFile.localizedDescription, cleared: false)
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        do {
            return .success(try ComparisonSessionState.decode(from: loaded.data))
        } catch ComparisonSessionStateError.schemaProbeLimitExceeded {
            return .failed("Saved data uses an unsupported format that could not be inspected safely.")
        } catch ComparisonSessionStateError.unsupportedSchemaVersion(let version) {
            guard version <= ComparisonSessionState.currentSchemaVersion else {
                return .failed("Saved data uses a newer unsupported format.")
            }
            return corruptResult(
                ComparisonSessionStateError.unsupportedSchemaVersion(version),
                expectedData: loaded.data,
                directoryDescriptor: directoryDescriptor
            )
        } catch let error as ComparisonSessionStateError {
            return corruptResult(
                error,
                expectedData: loaded.data,
                directoryDescriptor: directoryDescriptor
            )
        } catch let error as DecodingError {
            return corruptResult(
                error,
                expectedData: loaded.data,
                directoryDescriptor: directoryDescriptor
            )
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func corruptResult(
        _ error: Error,
        expectedData: Data,
        directoryDescriptor: Int32
    ) -> LoadResult {
        do {
            let cleared = try clearLocked(
                in: directoryDescriptor,
                expectedData: expectedData
            )
            return cleared
                ? .corrupt(error.localizedDescription, cleared: true)
                : .failed(StoreError.sessionChanged.localizedDescription)
        } catch {
            return .corrupt(error.localizedDescription, cleared: false)
        }
    }

    private func readLocked(
        named fileName: String? = nil,
        in directoryDescriptor: Int32
    ) throws -> LoadedFile? {
        let fileName = fileName ?? sessionFileName
        var pathStatus = stat()
        guard
            fstatat(
                directoryDescriptor,
                fileName,
                &pathStatus,
                AT_SYMLINK_NOFOLLOW
            ) == 0
        else {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        guard pathStatus.st_mode & S_IFMT == S_IFREG else {
            throw StoreError.invalidSessionFile
        }
        let descriptor = Darwin.openat(
            directoryDescriptor,
            fileName,
            O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        )
        if descriptor == -1, errno == ENOENT { return nil }
        if descriptor == -1, errno == ELOOP { throw StoreError.invalidSessionFile }
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }

        var initialStatus = stat()
        guard fstat(descriptor, &initialStatus) == 0 else { throw posixError() }
        guard initialStatus.st_mode & S_IFMT == S_IFREG else {
            throw StoreError.invalidSessionFile
        }
        guard initialStatus.st_size <= ComparisonSessionState.maximumPersistedBytes else {
            throw ComparisonSessionStateError.encodedDataTooLarge(
                maximumBytes: ComparisonSessionState.maximumPersistedBytes
            )
        }

        var data = Data()
        data.reserveCapacity(Int(initialStatus.st_size))
        var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        while data.count <= ComparisonSessionState.maximumPersistedBytes {
            let remaining = ComparisonSessionState.maximumPersistedBytes + 1 - data.count
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, remaining))
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw posixError()
            }
            data.append(contentsOf: buffer.prefix(count))
        }

        var finalStatus = stat()
        guard fstat(descriptor, &finalStatus) == 0 else { throw posixError() }
        pathStatus = stat()
        guard
            fstatat(
                directoryDescriptor,
                fileName,
                &pathStatus,
                AT_SYMLINK_NOFOLLOW
            ) == 0
        else {
            if errno == ENOENT { throw StoreError.sessionChanged }
            throw posixError()
        }
        guard stableFileStatus(initialStatus, finalStatus),
            FileSnapshot(initialStatus) == FileSnapshot(pathStatus),
            pathStatus.st_mode & S_IFMT == S_IFREG,
            data.count == Int(finalStatus.st_size)
        else {
            throw StoreError.sessionChanged
        }
        guard data.count <= ComparisonSessionState.maximumPersistedBytes else {
            throw ComparisonSessionStateError.encodedDataTooLarge(
                maximumBytes: ComparisonSessionState.maximumPersistedBytes
            )
        }
        return LoadedFile(data: data)
    }

    @discardableResult
    func save(_ state: ComparisonSessionState) throws -> SaveReceipt {
        let data = try state.encodedData()
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let directory = try openLockedDirectory(createIfNeeded: true) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { directory.close() }

        let temporaryName = ".\(sessionFileName).\(UUID().uuidString).tmp"
        let descriptor = Darwin.openat(
            directory.descriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw posixError() }
        var renamed = false
        defer {
            Darwin.close(descriptor)
            if !renamed {
                _ = Darwin.unlinkat(directory.descriptor, temporaryName, 0)
            }
        }
        try data.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    rawBuffer.baseAddress!.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard count > 0 else {
                    if count == -1, errno == EINTR { continue }
                    throw posixError()
                }
                offset += count
            }
        }
        try fullSync(descriptor)
        var descriptorStatus = stat()
        guard fstat(descriptor, &descriptorStatus) == 0 else { throw posixError() }
        let receipt = SaveReceipt(identity: FileIdentity(descriptorStatus), data: data)
        guard
            Darwin.renameat(
                directory.descriptor,
                temporaryName,
                directory.descriptor,
                sessionFileName
            ) == 0
        else { throw posixError() }
        renamed = true
        do {
            try syncDirectory(directory.descriptor)
            var pathStatus = stat()
            guard
                fstatat(
                    directory.descriptor,
                    sessionFileName,
                    &pathStatus,
                    AT_SYMLINK_NOFOLLOW
                ) == 0,
                receipt.identity == FileIdentity(pathStatus)
            else {
                throw StoreError.sessionChanged
            }
        } catch {
            throw SaveCommitError(receipt: receipt, underlyingError: error)
        }
        return receipt
    }

    func clear() throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let directory = try openLockedDirectory(createIfNeeded: false) else { return }
        defer { directory.close() }
        _ = try clearLocked(in: directory.descriptor)
    }

    func clear(savedBy receipt: SaveReceipt) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let directory = try openLockedDirectory(createIfNeeded: false) else { return }
        defer { directory.close() }
        var status = stat()
        guard
            fstatat(
                directory.descriptor,
                sessionFileName,
                &status,
                AT_SYMLINK_NOFOLLOW
            ) == 0
        else {
            if errno == ENOENT {
                try syncDirectory(directory.descriptor)
                return
            }
            throw posixError()
        }
        guard FileIdentity(status) == receipt.identity else { return }
        _ = try clearLocked(
            in: directory.descriptor,
            expectedData: receipt.data,
            expectedIdentity: receipt.identity
        )
    }

    @discardableResult
    private func clearLocked(
        in directoryDescriptor: Int32,
        expectedData: Data? = nil,
        expectedIdentity: FileIdentity? = nil
    ) throws -> Bool {
        guard expectedData != nil || expectedIdentity != nil else {
            if Darwin.unlinkat(directoryDescriptor, sessionFileName, 0) == 0 {
                try syncDirectory(directoryDescriptor)
                return true
            }
            guard errno != ENOENT else {
                try syncDirectory(directoryDescriptor)
                return true
            }
            throw posixError()
        }

        let quarantineName = quarantineFileName
        guard
            Darwin.renameatx_np(
                directoryDescriptor,
                sessionFileName,
                directoryDescriptor,
                quarantineName,
                UInt32(RENAME_EXCL)
            ) == 0
        else {
            if errno == ENOENT {
                try syncDirectory(directoryDescriptor)
                return true
            }
            if errno == EEXIST { throw StoreError.sessionChanged }
            throw posixError()
        }
        let quarantined: LoadedFile?
        do {
            quarantined = try readLocked(
                named: quarantineName,
                in: directoryDescriptor
            )
        } catch {
            _ = try restoreQuarantinedFile(
                named: quarantineName,
                in: directoryDescriptor
            )
            throw error
        }
        var quarantinedStatus = stat()
        let snapshotMatches: Bool
        if let expectedIdentity {
            snapshotMatches =
                fstatat(
                    directoryDescriptor,
                    quarantineName,
                    &quarantinedStatus,
                    AT_SYMLINK_NOFOLLOW
                ) == 0
                && FileIdentity(quarantinedStatus) == expectedIdentity
        } else {
            snapshotMatches = true
        }
        guard snapshotMatches, expectedData == nil || quarantined?.data == expectedData else {
            _ = try restoreQuarantinedFile(
                named: quarantineName,
                in: directoryDescriptor
            )
            return false
        }
        guard Darwin.unlinkat(directoryDescriptor, quarantineName, 0) == 0 else {
            let error = posixError()
            _ = try restoreQuarantinedFile(
                named: quarantineName,
                in: directoryDescriptor
            )
            throw error
        }
        try syncDirectory(directoryDescriptor)
        return true
    }

    private func quarantineInvalidFile(in directoryDescriptor: Int32) throws -> Bool {
        let quarantineName = quarantineFileName
        var originalStatus = stat()
        guard
            fstatat(
                directoryDescriptor,
                sessionFileName,
                &originalStatus,
                AT_SYMLINK_NOFOLLOW
            ) == 0
        else {
            if errno == ENOENT {
                try syncDirectory(directoryDescriptor)
                return true
            }
            throw posixError()
        }
        guard originalStatus.st_mode & S_IFMT != S_IFREG else { return false }
        guard
            Darwin.renameatx_np(
                directoryDescriptor,
                sessionFileName,
                directoryDescriptor,
                quarantineName,
                UInt32(RENAME_EXCL)
            ) == 0
        else {
            if errno == ENOENT {
                try syncDirectory(directoryDescriptor)
                return true
            }
            if errno == EEXIST { throw StoreError.sessionChanged }
            throw posixError()
        }
        var status = stat()
        guard fstatat(directoryDescriptor, quarantineName, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            let error = posixError()
            _ = try restoreQuarantinedFile(
                named: quarantineName,
                in: directoryDescriptor
            )
            throw error
        }
        guard FileIdentity(status) == FileIdentity(originalStatus),
            status.st_mode & S_IFMT != S_IFREG
        else {
            _ = try restoreQuarantinedFile(
                named: quarantineName,
                in: directoryDescriptor
            )
            return false
        }
        if Darwin.unlinkat(directoryDescriptor, quarantineName, 0) == 0 {
            try syncDirectory(directoryDescriptor)
            return true
        }
        let error = posixError()
        _ = try restoreQuarantinedFile(
            named: quarantineName,
            in: directoryDescriptor
        )
        throw error
    }

    private func restoreQuarantinedFile(
        named quarantineName: String,
        in directoryDescriptor: Int32
    ) throws -> Bool {
        guard
            Darwin.renameatx_np(
                directoryDescriptor,
                quarantineName,
                directoryDescriptor,
                sessionFileName,
                UInt32(RENAME_EXCL)
            ) == 0
        else {
            guard errno == EEXIST || errno == ENOENT else { throw posixError() }
            return false
        }
        try syncDirectory(directoryDescriptor)
        return true
    }

    private func openLockedDirectory(createIfNeeded: Bool) throws -> LockedDirectory? {
        try validateSessionLocation()
        guard let directoryDescriptor = try openParentDirectory(createIfNeeded: createIfNeeded) else {
            return nil
        }
        do {
            let lockDescriptor = Darwin.openat(
                directoryDescriptor,
                Self.lockFileName,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
            guard lockDescriptor >= 0 else { throw posixError() }
            do {
                var status = stat()
                guard fstat(lockDescriptor, &status) == 0 else { throw posixError() }
                guard status.st_mode & S_IFMT == S_IFREG else {
                    throw StoreError.invalidSessionFile
                }
                while Darwin.lockf(lockDescriptor, F_LOCK, 0) != 0 {
                    guard errno == EINTR else { throw posixError() }
                }
                var pathStatus = stat()
                guard
                    fstatat(
                        directoryDescriptor,
                        Self.lockFileName,
                        &pathStatus,
                        AT_SYMLINK_NOFOLLOW
                    ) == 0,
                    FileSnapshot(pathStatus) == FileSnapshot(status)
                else {
                    throw StoreError.sessionChanged
                }
                var sessionStatus = stat()
                try preserveAbandonedQuarantine(in: directoryDescriptor)
                if fstatat(
                    directoryDescriptor,
                    sessionFileName,
                    &sessionStatus,
                    AT_SYMLINK_NOFOLLOW
                ) == 0 {
                    guard !sameFileIdentityAndType(sessionStatus, status) else {
                        throw StoreError.invalidSessionLocation
                    }
                } else if errno != ENOENT {
                    throw posixError()
                }
                return LockedDirectory(
                    descriptor: directoryDescriptor,
                    lockDescriptor: lockDescriptor
                )
            } catch {
                Darwin.close(lockDescriptor)
                throw error
            }
        } catch {
            Darwin.close(directoryDescriptor)
            throw error
        }
    }

    private func preserveAbandonedQuarantine(in directoryDescriptor: Int32) throws {
        var quarantineStatus = stat()
        guard
            fstatat(
                directoryDescriptor,
                quarantineFileName,
                &quarantineStatus,
                AT_SYMLINK_NOFOLLOW
            ) == 0
        else {
            guard errno == ENOENT else { throw posixError() }
            return
        }
        var sessionStatus = stat()
        if fstatat(
            directoryDescriptor,
            sessionFileName,
            &sessionStatus,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            let recoveryName = ".\(sessionFileName).\(UUID().uuidString).recovery"
            guard
                Darwin.renameatx_np(
                    directoryDescriptor,
                    quarantineFileName,
                    directoryDescriptor,
                    recoveryName,
                    UInt32(RENAME_EXCL)
                ) == 0
            else {
                throw posixError()
            }
            try syncDirectory(directoryDescriptor)
            return
        }
        guard errno == ENOENT else { throw posixError() }
        throw StoreError.sessionChanged
    }

    private func openParentDirectory(createIfNeeded: Bool) throws -> Int32? {
        let (ancestor, components) = try existingParentDirectoryAndComponents()
        var pathStatus = stat()
        guard Darwin.lstat(ancestor, &pathStatus) == 0 else { throw posixError() }
        var descriptor = Darwin.open(
            ancestor,
            O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw posixError() }
        var descriptorIsOwned = true
        defer {
            if descriptorIsOwned { Darwin.close(descriptor) }
        }
        var descriptorStatus = stat()
        guard fstat(descriptor, &descriptorStatus) == 0,
            FileIdentity(pathStatus) == FileIdentity(descriptorStatus)
        else {
            throw StoreError.sessionChanged
        }

        for component in components {
            let name = String(component)
            var next = Darwin.openat(
                descriptor,
                name,
                O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
            )
            if next == -1, errno == ENOENT, createIfNeeded {
                guard Darwin.mkdirat(descriptor, name, S_IRWXU) == 0 || errno == EEXIST else {
                    throw posixError()
                }
                try syncDirectory(descriptor)
                next = Darwin.openat(
                    descriptor,
                    name,
                    O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
                )
            }
            if next == -1, errno == ENOENT, !createIfNeeded {
                try syncDirectory(descriptor)
                return nil
            }
            guard next >= 0 else {
                throw posixError()
            }
            Darwin.close(descriptor)
            descriptor = next
        }
        descriptorIsOwned = false
        return descriptor
    }

    private func existingParentDirectoryAndComponents() throws -> (String, [String]) {
        let requested = fileURL.deletingLastPathComponent().standardizedFileURL
        var unresolved = [requested.lastPathComponent]
        var ancestor = requested.deletingLastPathComponent()
        while true {
            var status = stat()
            if Darwin.lstat(ancestor.path, &status) == 0 { break }
            guard errno == ENOENT, ancestor.path != "/" else { throw posixError() }
            unresolved.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }

        var resolvedBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved = ancestor.path.withCString { path in
            Darwin.realpath(path, &resolvedBuffer)
        }
        guard resolved != nil else { throw posixError() }
        let terminator = resolvedBuffer.firstIndex(of: 0) ?? resolvedBuffer.endIndex
        let resolvedPath = String(
            decoding: resolvedBuffer[..<terminator].map(UInt8.init(bitPattern:)),
            as: UTF8.self
        )
        return (resolvedPath, unresolved.reversed())
    }

    private var sessionFileName: String {
        fileURL.lastPathComponent
    }

    private var quarantineFileName: String {
        ".\(sessionFileName).quarantine"
    }

    private func validateSessionLocation() throws {
        let fileName = sessionFileName
        guard fileURL.isFileURL, fileURL.host == nil, fileURL.path.hasPrefix("/"),
            !fileURL.hasDirectoryPath,
            !fileURL.path.utf8.contains(0),
            !fileName.isEmpty, fileName.utf8.count <= 200, !fileName.hasPrefix("."),
            fileName.compare(Self.lockFileName, options: .caseInsensitive) != .orderedSame,
            !fileName.utf8.contains(0), !fileName.utf8.contains(UInt8(ascii: "/"))
        else {
            throw StoreError.invalidSessionLocation
        }
    }

    private func stableFileStatus(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_mode == rhs.st_mode
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private func sameFileIdentityAndType(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_mode & S_IFMT == rhs.st_mode & S_IFMT
    }

    private func syncDirectory(_ descriptor: Int32) throws {
        while Darwin.fsync(descriptor) != 0 {
            if errno == EINTR { continue }
            throw posixError()
        }
    }

    private func fullSync(_ descriptor: Int32) throws {
        while Darwin.fcntl(descriptor, F_FULLFSYNC) != 0 {
            if errno == EINTR { continue }
            throw posixError()
        }
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno)!)
    }
}
