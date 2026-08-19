import Darwin
import Foundation

public struct BinaryFileDocument: Equatable, Sendable {
    public let url: URL
    public let maximumByteCount: Int
    public private(set) var data: Data
    public private(set) var persistedData: Data
    public private(set) var isDirty: Bool
    fileprivate var storageURL: URL
    private var differingByteCount: Int?

    public var displayName: String { url.lastPathComponent }
    public var byteCount: Int { data.count }

    fileprivate init(url: URL, storageURL: URL, data: Data, maximumByteCount: Int) {
        self.url = url
        self.storageURL = storageURL
        self.data = data
        persistedData = data
        isDirty = false
        differingByteCount = 0
        self.maximumByteCount = maximumByteCount
    }

    fileprivate mutating func markPersisted(at storageURL: URL) {
        self.storageURL = storageURL
        persistedData = data
        isDirty = false
        differingByteCount = 0
    }

    public mutating func replaceByte(at offset: Int, with byte: UInt8) throws {
        guard offset >= 0, offset < data.count else {
            throw BinaryFileDocumentError.invalidByteOffset(offset)
        }
        let dataIndex = data.index(data.startIndex, offsetBy: offset)
        if let differingByteCount {
            let persistedIndex = persistedData.index(persistedData.startIndex, offsetBy: offset)
            let oldDiffers = data[dataIndex] != persistedData[persistedIndex]
            let newDiffers = byte != persistedData[persistedIndex]
            self.differingByteCount = differingByteCount - (oldDiffers ? 1 : 0) + (newDiffers ? 1 : 0)
        }
        data[dataIndex] = byte
        isDirty = self.differingByteCount != 0
    }

    public mutating func replaceSubrange(_ range: Range<Int>, with replacement: Data) throws {
        guard range.lowerBound >= 0, range.upperBound >= range.lowerBound, range.upperBound <= data.count else {
            throw BinaryFileDocumentError.invalidByteRange(range)
        }
        let retainedCount = data.count - range.count
        let (newCount, overflow) = retainedCount.addingReportingOverflow(replacement.count)
        guard !overflow, newCount <= maximumByteCount else {
            throw BinaryFileDocumentError.fileTooLarge(maximumBytes: maximumByteCount)
        }
        let lowerBound = data.index(data.startIndex, offsetBy: range.lowerBound)
        let upperBound = data.index(data.startIndex, offsetBy: range.upperBound)
        let oldMismatchCount = differingByteCount.map { _ in mismatchCount(in: data, range: range) }
        data.replaceSubrange(lowerBound..<upperBound, with: replacement)
        if let differingByteCount, let oldMismatchCount, replacement.count == range.count {
            self.differingByteCount =
                differingByteCount - oldMismatchCount
                + mismatchCount(in: replacement, persistedOffset: range.lowerBound)
        } else if data.count == persistedData.count {
            differingByteCount = mismatchCount(in: data, range: 0..<data.count)
        } else {
            differingByteCount = nil
        }
        isDirty = differingByteCount != 0
    }

    public mutating func insert(_ bytes: Data, at offset: Int) throws {
        try replaceSubrange(offset..<offset, with: bytes)
    }

    public mutating func removeSubrange(_ range: Range<Int>) throws {
        try replaceSubrange(range, with: Data())
    }

    private func mismatchCount(in data: Data, range: Range<Int>) -> Int {
        range.reduce(into: 0) { count, offset in
            let dataIndex = data.index(data.startIndex, offsetBy: offset)
            let persistedIndex = persistedData.index(persistedData.startIndex, offsetBy: offset)
            if data[dataIndex] != persistedData[persistedIndex] { count += 1 }
        }
    }

    private func mismatchCount(in replacement: Data, persistedOffset: Int) -> Int {
        replacement.enumerated().reduce(into: 0) { count, element in
            let persistedIndex = persistedData.index(persistedData.startIndex, offsetBy: persistedOffset + element.offset)
            if element.element != persistedData[persistedIndex] { count += 1 }
        }
    }
}

public enum BinaryFileSaveWarning: LocalizedError, Equatable, Sendable {
    case recoveryCopyPreserved(String)

    public var errorDescription: String? {
        switch self {
        case .recoveryCopyPreserved(let path):
            "File was saved, but a recovery copy remains at \(path). Review it before deleting it."
        }
    }
}

public struct BinaryFileSaveResult: Equatable, Sendable {
    public let document: BinaryFileDocument
    public let warning: BinaryFileSaveWarning?

    public init(document: BinaryFileDocument, warning: BinaryFileSaveWarning? = nil) {
        self.document = document
        self.warning = warning
    }
}

public enum BinaryFileDocumentError: Error, LocalizedError, Equatable, Sendable {
    case changedOnDisk
    case fileTooLarge(maximumBytes: Int)
    case invalidByteOffset(Int)
    case invalidByteRange(Range<Int>)
    case notRegularFile
    case saveOutcomeUncertain(String)
    case saveOutcomeUncertainWithoutRecovery

    public var errorDescription: String? {
        switch self {
        case .changedOnDisk:
            "File changed on disk after it was opened. Reload it before saving."
        case .fileTooLarge(let maximumBytes):
            "Binary file exceeds the current \(maximumBytes)-byte safety limit."
        case .invalidByteOffset(let offset):
            "Byte offset \(offset) is outside the file."
        case .invalidByteRange(let range):
            "Byte range \(range.lowerBound)..<\(range.upperBound) is outside the file."
        case .notRegularFile:
            "Binary comparison requires a regular file."
        case .saveOutcomeUncertain(let path):
            "Save outcome could not be verified. Recovery copy: \(path)."
        case .saveOutcomeUncertainWithoutRecovery:
            "Save outcome could not be verified, and no recovery copy could be verified."
        }
    }
}

public enum BinaryFileDocumentIO {
    public static let maximumFileSize = 64 * 1_024 * 1_024

    public static func load(
        from url: URL,
        maximumBytes: Int = maximumFileSize
    ) throws -> BinaryFileDocument {
        precondition(maximumBytes >= 0, "Maximum byte count must not be negative")
        return try withSecurityScopedAccess(to: url) {
            let storageURL = url.resolvingSymlinksInPath().standardizedFileURL
            let initialSnapshot = try pinRegularFile(at: storageURL, maximumBytes: maximumBytes)
            Darwin.close(initialSnapshot.descriptor)
            var coordinationError: NSError?
            var operationResult: Result<(Data, URL), any Error>?
            NSFileCoordinator().coordinate(readingItemAt: storageURL, options: [], error: &coordinationError) { coordinatedURL in
                operationResult = Result {
                    let snapshot = try pinRegularFile(at: coordinatedURL, maximumBytes: maximumBytes)
                    defer { Darwin.close(snapshot.descriptor) }
                    guard url.resolvingSymlinksInPath().standardizedFileURL ==
                            coordinatedURL.standardizedFileURL else {
                        throw BinaryFileDocumentError.changedOnDisk
                    }
                    return (snapshot.data, coordinatedURL.standardizedFileURL)
                }
            }
            if let coordinationError { throw coordinationError }
            guard let operationResult else { throw CocoaError(.fileReadUnknown) }
            let (data, coordinatedURL) = try operationResult.get()
            return BinaryFileDocument(
                url: url,
                storageURL: coordinatedURL,
                data: data,
                maximumByteCount: maximumBytes
            )
        }
    }

    public static func save(_ document: BinaryFileDocument) throws -> BinaryFileSaveResult {
        try save(document, beforeReplacing: {}, afterReplacing: {}, beforeRemovingRecovery: {})
    }

    static func save(
        _ document: BinaryFileDocument,
        beforeReplacing: () throws -> Void,
        afterReplacing: () throws -> Void,
        beforeRemovingRecovery: () throws -> Void = {}
    ) throws -> BinaryFileSaveResult {
        try withSecurityScopedAccess(to: document.url) {
            let currentStorageURL = document.url.resolvingSymlinksInPath().standardizedFileURL
            guard currentStorageURL == document.storageURL.standardizedFileURL else {
                throw BinaryFileDocumentError.changedOnDisk
            }
            var coordinationError: NSError?
            var operationResult: Result<BinaryFileSaveResult, any Error>?
            NSFileCoordinator().coordinate(
                writingItemAt: document.storageURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                operationResult = Result {
                    guard document.url.resolvingSymlinksInPath().standardizedFileURL == coordinatedURL.standardizedFileURL else {
                        throw BinaryFileDocumentError.changedOnDisk
                    }
                    let persistedTarget = try pinRegularFile(
                        at: coordinatedURL,
                        maximumBytes: document.maximumByteCount
                    )
                    defer { Darwin.close(persistedTarget.descriptor) }
                    guard persistedTarget.data == document.persistedData else {
                        throw BinaryFileDocumentError.changedOnDisk
                    }

                    let stagedURL = coordinatedURL.deletingLastPathComponent()
                        .appending(path: ".macmerge-binary-\(UUID().uuidString).tmp")
                    let backupName = recoveryName(for: coordinatedURL)
                    let backupURL = coordinatedURL.deletingLastPathComponent().appending(path: backupName)
                    try document.data.write(to: stagedURL, options: .atomic)
                    let staged = try pinRegularFile(
                        at: stagedURL,
                        maximumBytes: document.maximumByteCount
                    )
                    defer {
                        Darwin.close(staged.descriptor)
                        quarantineAndRemoveStaged(
                            at: stagedURL,
                            expectedIdentity: staged.identity,
                            maximumBytes: document.maximumByteCount
                        )
                    }
                    try beforeReplacing()
                    guard document.url.resolvingSymlinksInPath().standardizedFileURL ==
                            coordinatedURL.standardizedFileURL else {
                        throw BinaryFileDocumentError.changedOnDisk
                    }
                    guard pinnedFileIsCurrent(staged, at: stagedURL) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let displaced = try pinRegularFile(
                        at: coordinatedURL,
                        maximumBytes: document.maximumByteCount
                    )
                    defer { Darwin.close(displaced.descriptor) }
                    let displacedData = displaced.data
                    guard pinnedFileIsCurrent(displaced, at: coordinatedURL),
                          !itemMayExistWithoutFollowingSymlinks(at: backupURL) else {
                        throw BinaryFileDocumentError.changedOnDisk
                    }
                    let savedURL: URL
                    do {
                        savedURL =
                            try FileManager.default
                            .replaceItemAt(
                                coordinatedURL,
                                withItemAt: stagedURL,
                                backupItemName: backupName,
                                options: .withoutDeletingBackupItem
                            )?.standardizedFileURL ?? coordinatedURL.standardizedFileURL
                    } catch {
                        throw classifyReplacementError(
                            error,
                            targetURL: coordinatedURL,
                            recoveryURL: backupURL,
                            expectedTarget: staged,
                            displaced: displaced,
                            maximumBytes: document.maximumByteCount
                        )
                    }
                    let replacementTarget = verifiedRegularFileSnapshot(
                        at: savedURL,
                        maximumBytes: document.maximumByteCount
                    )
                    let replacementRecovery = verifiedRegularFileSnapshot(
                        at: backupURL,
                        maximumBytes: document.maximumByteCount
                    )
                    do {
                        try afterReplacing()
                        let savedTarget = verifiedRegularFileSnapshot(
                            at: savedURL,
                            maximumBytes: document.maximumByteCount
                        )
                        let recovery = verifiedRegularFileSnapshot(
                            at: backupURL,
                            maximumBytes: document.maximumByteCount
                        )
                        guard
                            savedURL == coordinatedURL.standardizedFileURL,
                            document.url.resolvingSymlinksInPath().standardizedFileURL == savedURL,
                            replacementTarget?.data == staged.data,
                            savedTarget?.identity == replacementTarget?.identity,
                            savedTarget?.data == document.data,
                            displacedData == document.persistedData,
                            replacementRecovery?.data == displacedData,
                            recovery?.identity == replacementRecovery?.identity,
                            recovery?.data == displacedData,
                            pinnedFileDataIsStable(displaced)
                        else {
                            throw saveOutcomeUncertain(
                                recoveryURL: backupURL,
                                expectedData: displacedData,
                                maximumBytes: document.maximumByteCount
                            )
                        }
                    } catch {
                        throw saveOutcomeUncertain(
                            recoveryURL: backupURL,
                            expectedData: displacedData,
                            maximumBytes: document.maximumByteCount
                        )
                    }
                    var warning: BinaryFileSaveWarning?
                    guard let recovery = verifiedRegularFileSnapshot(
                        at: backupURL,
                        maximumBytes: document.maximumByteCount
                    ), recovery.identity == replacementRecovery?.identity,
                       recovery.data == displacedData else {
                        throw BinaryFileDocumentError.saveOutcomeUncertainWithoutRecovery
                    }
                    if displaced.identity != persistedTarget.identity {
                        warning = .recoveryCopyPreserved(backupURL.path)
                    } else {
                        do {
                            try beforeRemovingRecovery()
                            if let warningURL = quarantineAndRemoveRecovery(
                                at: backupURL,
                                expectedIdentity: recovery.identity,
                                expectedData: recovery.data,
                                maximumBytes: document.maximumByteCount
                            ) {
                                warning = .recoveryCopyPreserved(warningURL.path)
                            }
                        } catch {
                            if let retainedRecovery = verifiedRegularFileSnapshot(
                                at: backupURL,
                                maximumBytes: document.maximumByteCount
                            ), retainedRecovery.identity == recovery.identity,
                               retainedRecovery.data == recovery.data {
                                warning = .recoveryCopyPreserved(backupURL.path)
                            }
                        }
                    }
                    var saved = document
                    saved.markPersisted(at: savedURL)
                    return BinaryFileSaveResult(document: saved, warning: warning)
                }
            }
            guard let operationResult else { throw CocoaError(.fileWriteUnknown) }
            switch operationResult {
            case .failure(let error):
                throw error
            case .success(let result):
                if let coordinationError { throw coordinationError }
                return result
            }
        }
    }

    private static func pinRegularFile(
        at url: URL,
        maximumBytes: Int
    ) throws -> BinaryPinnedFileSnapshot {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard information.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor)
            throw BinaryFileDocumentError.notRegularFile
        }
        guard information.st_size >= 0, UInt64(information.st_size) <= UInt64(maximumBytes) else {
            Darwin.close(descriptor)
            throw BinaryFileDocumentError.fileTooLarge(maximumBytes: maximumBytes)
        }
        let identity = BinaryFileIdentity(device: information.st_dev, inode: information.st_ino)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let chunkSize = 1_024 * 1_024
        var data = Data()
        do {
            while true {
                let remaining = maximumBytes - data.count
                let requestedCount = remaining >= chunkSize ? chunkSize : remaining + 1
                guard let chunk = try handle.read(upToCount: requestedCount), !chunk.isEmpty else { break }
                data.append(chunk)
                guard data.count <= maximumBytes else {
                    throw BinaryFileDocumentError.fileTooLarge(maximumBytes: maximumBytes)
                }
            }
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        let snapshot = BinaryPinnedFileSnapshot(
            descriptor: descriptor,
            identity: identity,
            data: data,
            information: information
        )
        guard pinnedFileIsCurrent(snapshot, at: url) else {
            Darwin.close(descriptor)
            throw BinaryFileDocumentError.changedOnDisk
        }
        return snapshot
    }

    private static func verifiedRegularFileSnapshot(
        at url: URL,
        maximumBytes: Int
    ) -> BinaryVerifiedFileSnapshot? {
        guard let pinned = try? pinRegularFile(at: url, maximumBytes: maximumBytes) else { return nil }
        defer { Darwin.close(pinned.descriptor) }
        return BinaryVerifiedFileSnapshot(identity: pinned.identity, data: pinned.data)
    }

    private static func saveOutcomeUncertain(
        recoveryURL: URL,
        expectedData: Data,
        maximumBytes: Int
    ) -> BinaryFileDocumentError {
        isVerifiedRecoveryArtifact(
            at: recoveryURL,
            expectedData: expectedData,
            maximumBytes: maximumBytes
        ) ? .saveOutcomeUncertain(recoveryURL.path) : .saveOutcomeUncertainWithoutRecovery
    }

    private static func classifyReplacementError(
        _ error: any Error,
        targetURL: URL,
        recoveryURL: URL,
        expectedTarget: BinaryPinnedFileSnapshot,
        displaced: BinaryPinnedFileSnapshot,
        maximumBytes: Int
    ) -> any Error {
        let target = verifiedRegularFileSnapshot(at: targetURL, maximumBytes: maximumBytes)
        let recovery = verifiedRegularFileSnapshot(at: recoveryURL, maximumBytes: maximumBytes)
        if recovery?.data == displaced.data,
           pinnedFileDataIsStable(displaced) {
            return .saveOutcomeUncertain(recoveryURL.path) as BinaryFileDocumentError
        }
        if target?.identity == displaced.identity,
           target?.data == displaced.data,
           !itemMayExistWithoutFollowingSymlinks(at: recoveryURL) {
            return error
        }
        if target?.data == expectedTarget.data {
            return BinaryFileDocumentError.saveOutcomeUncertainWithoutRecovery
        }
        return BinaryFileDocumentError.saveOutcomeUncertainWithoutRecovery
    }

    private static func isVerifiedRecoveryArtifact(
        at url: URL,
        expectedData: Data,
        maximumBytes: Int
    ) -> Bool {
        verifiedRegularFileSnapshot(at: url, maximumBytes: maximumBytes)?.data == expectedData
    }

    private static func pinnedFileDataIsStable(_ snapshot: BinaryPinnedFileSnapshot) -> Bool {
        var initialInformation = stat()
        guard Darwin.fstat(snapshot.descriptor, &initialInformation) == 0,
              initialInformation.st_mode & S_IFMT == S_IFREG,
              BinaryFileIdentity(
                  device: initialInformation.st_dev,
                  inode: initialInformation.st_ino
              ) == snapshot.identity,
              initialInformation.st_size == off_t(snapshot.data.count) else { return false }
        guard Darwin.lseek(snapshot.descriptor, 0, SEEK_SET) == 0 else { return false }
        guard let data = try? readBoundedData(
            from: snapshot.descriptor,
            maximumBytes: snapshot.data.count
        ) else { return false }
        var finalInformation = stat()
        return data == snapshot.data
            && Darwin.fstat(snapshot.descriptor, &finalInformation) == 0
            && BinaryFileIdentity(
                device: finalInformation.st_dev,
                inode: finalInformation.st_ino
            ) == snapshot.identity
            && finalInformation.st_size == initialInformation.st_size
            && finalInformation.st_mtimespec.tv_sec == initialInformation.st_mtimespec.tv_sec
            && finalInformation.st_mtimespec.tv_nsec == initialInformation.st_mtimespec.tv_nsec
            && finalInformation.st_ctimespec.tv_sec == initialInformation.st_ctimespec.tv_sec
            && finalInformation.st_ctimespec.tv_nsec == initialInformation.st_ctimespec.tv_nsec
    }

    private static func pinnedFileIsCurrent(
        _ snapshot: BinaryPinnedFileSnapshot,
        at url: URL
    ) -> Bool {
        guard descriptorMatches(snapshot) else { return false }
        var pathInformation = stat()
        let result = url.path.withCString { Darwin.lstat($0, &pathInformation) }
        return result == 0
            && pathInformation.st_mode & S_IFMT == S_IFREG
            && BinaryFileIdentity(device: pathInformation.st_dev, inode: pathInformation.st_ino)
                == snapshot.identity
    }

    private static func descriptorMatches(_ snapshot: BinaryPinnedFileSnapshot) -> Bool {
        var information = stat()
        return Darwin.fstat(snapshot.descriptor, &information) == 0
            && information.st_mode & S_IFMT == S_IFREG
            && BinaryFileIdentity(device: information.st_dev, inode: information.st_ino) == snapshot.identity
            && information.st_size == off_t(snapshot.data.count)
            && information.st_mtimespec.tv_sec == snapshot.information.st_mtimespec.tv_sec
            && information.st_mtimespec.tv_nsec == snapshot.information.st_mtimespec.tv_nsec
            && information.st_ctimespec.tv_sec == snapshot.information.st_ctimespec.tv_sec
            && information.st_ctimespec.tv_nsec == snapshot.information.st_ctimespec.tv_nsec
    }

    private static func readBoundedData(from descriptor: Int32, maximumBytes: Int) throws -> Data {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let chunkSize = 1_024 * 1_024
        var data = Data()
        while true {
            let remaining = maximumBytes - data.count
            let requestedCount = remaining >= chunkSize ? chunkSize : remaining + 1
            guard let chunk = try handle.read(upToCount: requestedCount), !chunk.isEmpty else {
                return data
            }
            data.append(chunk)
            guard data.count <= maximumBytes else {
                throw BinaryFileDocumentError.fileTooLarge(maximumBytes: maximumBytes)
            }
        }
    }

    private static func quarantineAndRemoveRecovery(
        at recoveryURL: URL,
        expectedIdentity: BinaryFileIdentity,
        expectedData: Data,
        maximumBytes: Int
    ) -> URL? {
        let quarantineURL = recoveryURL.deletingLastPathComponent()
            .appending(path: ".macmerge-binary-cleanup-\(UUID().uuidString)")
        let renamed = recoveryURL.path.withCString { recoveryPath in
            quarantineURL.path.withCString { quarantinePath in
                Darwin.renamex_np(recoveryPath, quarantinePath, UInt32(RENAME_EXCL))
            }
        }
        guard renamed == 0 else {
            return itemMayExistWithoutFollowingSymlinks(at: recoveryURL) ? recoveryURL : nil
        }
        guard let quarantined = verifiedRegularFileSnapshot(
            at: quarantineURL,
            maximumBytes: maximumBytes
        ), quarantined.identity == expectedIdentity, quarantined.data == expectedData else {
            return quarantineURL
        }
        let unlinked = quarantineURL.path.withCString { Darwin.unlink($0) }
        return unlinked == 0 && !itemMayExistWithoutFollowingSymlinks(at: quarantineURL)
            ? nil : quarantineURL
    }

    private static func quarantineAndRemoveStaged(
        at url: URL,
        expectedIdentity: BinaryFileIdentity,
        maximumBytes: Int
    ) {
        let quarantineURL = url.deletingLastPathComponent()
            .appending(path: ".macmerge-binary-abandoned-\(UUID().uuidString)")
        let renamed = url.path.withCString { sourcePath in
            quarantineURL.path.withCString { quarantinePath in
                Darwin.renamex_np(sourcePath, quarantinePath, UInt32(RENAME_EXCL))
            }
        }
        guard renamed == 0,
              verifiedRegularFileSnapshot(at: quarantineURL, maximumBytes: maximumBytes)?.identity ==
                expectedIdentity else { return }
        _ = quarantineURL.path.withCString { Darwin.unlink($0) }
    }

    private static func itemMayExistWithoutFollowingSymlinks(at url: URL) -> Bool {
        var information = stat()
        let result = url.path.withCString { Darwin.lstat($0, &information) }
        let errorNumber = errno
        return result == 0 || errorNumber != ENOENT
    }

    private static func recoveryName(for url: URL) -> String {
        let directoryURL = url.deletingLastPathComponent()
        let configuredLimit = directoryURL.path.withCString { Darwin.pathconf($0, _PC_NAME_MAX) }
        let maximumByteCount = configuredLimit > 0 ? Int(configuredLimit) : Int(NAME_MAX)
        let identifier = UUID().uuidString
        let suffix = ".macmerge-recovery-\(identifier)"
        guard suffix.utf8.count <= maximumByteCount else {
            return String(identifier.prefix(maximumByteCount))
        }
        return utf8Prefix(
            url.lastPathComponent,
            maximumByteCount: maximumByteCount - suffix.utf8.count
        ) + suffix
    }

    private static func utf8Prefix(_ value: String, maximumByteCount: Int) -> String {
        var result = ""
        var byteCount = 0
        for character in value {
            let characterByteCount = character.utf8.count
            guard byteCount + characterByteCount <= maximumByteCount else { break }
            result.append(character)
            byteCount += characterByteCount
        }
        return result
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) rethrows -> T {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
        }
        return try operation()
    }
}

private struct BinaryFileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}

private struct BinaryPinnedFileSnapshot {
    let descriptor: Int32
    let identity: BinaryFileIdentity
    let data: Data
    let information: stat
}

private struct BinaryVerifiedFileSnapshot {
    let identity: BinaryFileIdentity
    let data: Data
}
