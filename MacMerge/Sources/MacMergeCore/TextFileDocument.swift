import Darwin
import Foundation

public struct TextFileDocument: Equatable, Sendable {
    public let url: URL
    var storageURL: URL
    public var text: String
    public private(set) var persistedText: String
    public let encoding: TextFileEncoding
    public let hasByteOrderMark: Bool
    public private(set) var persistedData: Data

    public var isDirty: Bool { !text.unicodeScalars.elementsEqual(persistedText.unicodeScalars) }
    public var displayName: String { url.lastPathComponent }

    init(url: URL, storageURL: URL, decoded: DecodedTextFile, data: Data) {
        self.url = url
        self.storageURL = storageURL
        text = decoded.text
        persistedText = decoded.text
        encoding = decoded.encoding
        hasByteOrderMark = decoded.hasByteOrderMark
        persistedData = data
    }

    mutating func markPersisted(decoded: DecodedTextFile, data: Data, storageURL: URL) {
        text = decoded.text
        persistedText = decoded.text
        persistedData = data
        self.storageURL = storageURL
    }
}

public enum TextFileDocumentError: Error, LocalizedError, Equatable, Sendable {
    case changedOnDisk
    case fileTooLarge(maximumBytes: Int)
    case saveOutcomeUncertain(String)

    public var errorDescription: String? {
        switch self {
        case .changedOnDisk:
            "File changed on disk after it was opened. Reload it before saving."
        case let .fileTooLarge(maximumBytes):
            "File exceeds the current \(maximumBytes)-byte safety limit."
        case let .saveOutcomeUncertain(path):
            "Save outcome could not be verified. The document remains edited and a recovery copy is at \(path)."
        }
    }
}

public enum TextFileSaveWarning: LocalizedError, Equatable, Sendable {
    case recoveryCopyPreserved(String)

    public var errorDescription: String? {
        switch self {
        case let .recoveryCopyPreserved(path):
            "File was saved, but another version or cleanup artifact remains at \(path). Review it before deleting it."
        }
    }
}

public struct TextFileSaveResult: Equatable, Sendable {
    public let document: TextFileDocument
    public let warning: TextFileSaveWarning?

    public init(document: TextFileDocument, warning: TextFileSaveWarning? = nil) {
        self.document = document
        self.warning = warning
    }
}

public enum TextFileDocumentIO {
    public static let maximumFileSize = 64 * 1024 * 1024

    public static func create(
        at url: URL,
        text: String,
        encoding: TextFileEncoding = .utf8
    ) throws -> TextFileDocument {
        let decoded = DecodedTextFile(
            text: text,
            encoding: encoding,
            hasByteOrderMark: false
        )
        let data = try TextFileCodec.encode(decoded)
        try validateEncodedSize(data.count)

        return try withSecurityScopedAccess(to: url) {
            let initialStorageURL = url.resolvingSymlinksInPath().standardizedFileURL
            var coordinationError: NSError?
            var operationResult: Result<URL, any Error>?
            NSFileCoordinator().coordinate(
                writingItemAt: initialStorageURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                operationResult = Result {
                    guard url.resolvingSymlinksInPath().standardizedFileURL ==
                            coordinatedURL.standardizedFileURL else {
                        throw TextFileDocumentError.changedOnDisk
                    }
                    let storageURL = try atomicCreate(data, at: coordinatedURL)
                    guard try readBoundedData(from: storageURL) == data else {
                        throw TextFileDocumentError.saveOutcomeUncertain(storageURL.path)
                    }
                    guard url.resolvingSymlinksInPath().standardizedFileURL ==
                            storageURL.standardizedFileURL else {
                        throw TextFileDocumentError.saveOutcomeUncertain(storageURL.path)
                    }
                    return storageURL
                }
            }
            if let coordinationError {
                throw coordinationError
            }
            guard let operationResult else { throw CocoaError(.fileWriteUnknown) }
            let storageURL = try operationResult.get()
            return TextFileDocument(
                url: url,
                storageURL: storageURL,
                decoded: decoded,
                data: data
            )
        }
    }

    public static func load(from url: URL) throws -> TextFileDocument {
        try load(from: url, assuming: nil)
    }

    public static func load(
        from url: URL,
        assuming encoding: TextFileEncoding
    ) throws -> TextFileDocument {
        try load(from: url, assuming: Optional(encoding))
    }

    private static func load(
        from url: URL,
        assuming encoding: TextFileEncoding?
    ) throws -> TextFileDocument {
        try withSecurityScopedAccess(to: url) {
            let storageURL = url.resolvingSymlinksInPath()
            var coordinationError: NSError?
            var operationResult: Result<(data: Data, storageURL: URL), any Error>?
            NSFileCoordinator().coordinate(readingItemAt: storageURL, options: [], error: &coordinationError) {
                coordinatedURL in
                operationResult = Result {
                    let values = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile == true else {
                        throw CocoaError(.fileReadUnsupportedScheme)
                    }
                    guard let size = values.fileSize, size <= maximumFileSize else {
                        throw CocoaError(.fileReadTooLarge)
                    }
                    let data = try readBoundedData(from: coordinatedURL)
                    return (data, coordinatedURL.standardizedFileURL)
                }
            }
            if let coordinationError {
                throw coordinationError
            }
            guard let operationResult else { throw CocoaError(.fileReadUnknown) }
            let result = try operationResult.get()
            return TextFileDocument(
                url: url,
                storageURL: result.storageURL,
                decoded: try encoding.map { try TextFileCodec.decode(result.data, assuming: $0) }
                    ?? TextFileCodec.decode(result.data),
                data: result.data
            )
        }
    }

    public static func save(_ document: TextFileDocument) throws -> TextFileSaveResult {
        try withSecurityScopedAccess(to: document.url) {
            let currentStorageURL = document.url.resolvingSymlinksInPath().standardizedFileURL
            guard currentStorageURL == document.storageURL.standardizedFileURL else {
                throw TextFileDocumentError.changedOnDisk
            }
            if document.isDirty, document.encoding.isLegacy {
                let canonicalPersistedData = try TextFileCodec.encode(DecodedTextFile(
                    text: document.persistedText,
                    encoding: document.encoding,
                    hasByteOrderMark: document.hasByteOrderMark
                ))
                guard canonicalPersistedData == document.persistedData else {
                    throw TextFileCodecError.encodingFailed(document.encoding)
                }
            }
            let encodedData = document.isDirty
                ? try TextFileCodec.encode(DecodedTextFile(
                    text: document.text,
                    encoding: document.encoding,
                    hasByteOrderMark: document.hasByteOrderMark
                ))
                : document.persistedData
            try validateEncodedSize(encodedData.count)
            let persistedDecoded = try TextFileCodec.decode(encodedData, assuming: document.encoding)
            var coordinationError: NSError?
            var operationError: (any Error)?
            var warning: TextFileSaveWarning?
            var savedStorageURL = document.storageURL

            NSFileCoordinator().coordinate(
                writingItemAt: document.storageURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    guard document.url.resolvingSymlinksInPath().standardizedFileURL ==
                            coordinatedURL.standardizedFileURL else {
                        throw TextFileDocumentError.changedOnDisk
                    }
                    let directory = coordinatedURL.deletingLastPathComponent()
                    let stagedURL = directory.appending(path: ".macmerge-\(UUID().uuidString).tmp")
                    let backupName = "\(coordinatedURL.lastPathComponent).macmerge-recovery-\(UUID().uuidString)"
                    let backupURL = directory.appending(path: backupName)
                    defer { try? FileManager.default.removeItem(at: stagedURL) }
                    try encodedData.write(to: stagedURL, options: .atomic)
                    guard try readBoundedData(from: coordinatedURL) == document.persistedData else {
                        throw TextFileDocumentError.changedOnDisk
                    }
                    savedStorageURL = try FileManager.default.replaceItemAt(
                        coordinatedURL,
                        withItemAt: stagedURL,
                        backupItemName: backupName,
                        options: .withoutDeletingBackupItem
                    )?.standardizedFileURL ?? coordinatedURL.standardizedFileURL
                    let targetData: Data
                    do {
                        targetData = try readBoundedData(from: savedStorageURL)
                    } catch {
                        throw TextFileDocumentError.saveOutcomeUncertain(backupURL.path)
                    }
                    guard targetData == encodedData else {
                        throw TextFileDocumentError.saveOutcomeUncertain(backupURL.path)
                    }
                    guard document.url.resolvingSymlinksInPath().standardizedFileURL ==
                            savedStorageURL.standardizedFileURL else {
                        throw TextFileDocumentError.saveOutcomeUncertain(backupURL.path)
                    }

                    let displacedData: Data
                    do {
                        displacedData = try readBoundedData(from: backupURL)
                    } catch {
                        warning = .recoveryCopyPreserved(backupURL.path)
                        return
                    }
                    guard displacedData == document.persistedData else {
                        warning = .recoveryCopyPreserved(backupURL.path)
                        return
                    }
                    do {
                        try FileManager.default.removeItem(at: backupURL)
                    } catch {
                        warning = .recoveryCopyPreserved(backupURL.path)
                    }
                } catch {
                    operationError = error
                }
            }
            if let error = coordinationError ?? operationError {
                throw error
            }

            var saved = document
            saved.markPersisted(decoded: persistedDecoded, data: encodedData, storageURL: savedStorageURL)
            return TextFileSaveResult(document: saved, warning: warning)
        }
    }

    public static func saveAs(_ document: TextFileDocument, to url: URL) throws -> TextFileDocument {
        try withSecurityScopedAccess(to: url) {
            if document.isDirty, document.encoding.isLegacy {
                let canonicalPersistedData = try TextFileCodec.encode(DecodedTextFile(
                    text: document.persistedText,
                    encoding: document.encoding,
                    hasByteOrderMark: document.hasByteOrderMark
                ))
                guard canonicalPersistedData == document.persistedData else {
                    throw TextFileCodecError.encodingFailed(document.encoding)
                }
            }
            let encodedData = document.isDirty
                ? try TextFileCodec.encode(DecodedTextFile(
                    text: document.text,
                    encoding: document.encoding,
                    hasByteOrderMark: document.hasByteOrderMark
                ))
                : document.persistedData
            try validateEncodedSize(encodedData.count)
            let persistedDecoded = try TextFileCodec.decode(encodedData, assuming: document.encoding)
            let initialStorageURL = url.resolvingSymlinksInPath().standardizedFileURL
            var coordinationError: NSError?
            var operationResult: Result<URL, any Error>?
            NSFileCoordinator().coordinate(
                writingItemAt: initialStorageURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                operationResult = Result {
                    guard url.resolvingSymlinksInPath().standardizedFileURL ==
                            coordinatedURL.standardizedFileURL else {
                        throw TextFileDocumentError.changedOnDisk
                    }
                    let storageURL = try atomicCreate(encodedData, at: coordinatedURL)
                    guard try readBoundedData(from: storageURL) == encodedData else {
                        throw TextFileDocumentError.saveOutcomeUncertain(storageURL.path)
                    }
                    return storageURL
                }
            }
            if let coordinationError { throw coordinationError }
            guard let operationResult else { throw CocoaError(.fileWriteUnknown) }
            return TextFileDocument(
                url: url,
                storageURL: try operationResult.get(),
                decoded: persistedDecoded,
                data: encodedData
            )
        }
    }

    private static func readBoundedData(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard let size = values.fileSize, size <= maximumFileSize else {
            throw CocoaError(.fileReadTooLarge)
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumFileSize else {
            throw CocoaError(.fileReadTooLarge)
        }
        return data
    }

    private static func atomicCreate(_ data: Data, at url: URL) throws -> URL {
        let storageURL = url.resolvingSymlinksInPath().standardizedFileURL
        let directoryURL = storageURL.deletingLastPathComponent()
        let name = storageURL.lastPathComponent
        let directoryFD = Darwin.open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directoryFD >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(directoryFD) }

        let originalIdentity = try fileIdentity(directoryFD: directoryFD, name: name)
        let stagedName = ".macmerge-\(UUID().uuidString).tmp"
        let stagedFD = stagedName.withCString {
            Darwin.openat(directoryFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard stagedFD >= 0 else { throw currentPOSIXError() }
        defer {
            Darwin.close(stagedFD)
            stagedName.withCString { _ = Darwin.unlinkat(directoryFD, $0, 0) }
        }

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(stagedFD, baseAddress.advanced(by: offset), buffer.count - offset)
                guard written > 0 else { throw currentPOSIXError() }
                offset += written
            }
        }
        guard Darwin.fsync(stagedFD) == 0 else { throw currentPOSIXError() }
        guard try fileIdentity(directoryFD: directoryFD, name: name) == originalIdentity else {
            throw TextFileDocumentError.changedOnDisk
        }
        let renamed = stagedName.withCString { stagedPath in
            name.withCString { targetPath in
                Darwin.renameat(directoryFD, stagedPath, directoryFD, targetPath)
            }
        }
        guard renamed == 0 else { throw currentPOSIXError() }
        guard Darwin.fsync(directoryFD) == 0 else {
            throw TextFileDocumentError.saveOutcomeUncertain(storageURL.path)
        }
        return storageURL
    }

    private static func fileIdentity(directoryFD: Int32, name: String) throws -> FileIdentity? {
        var information = stat()
        let result = name.withCString {
            Darwin.fstatat(directoryFD, $0, &information, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 {
            guard information.st_mode & S_IFMT == S_IFREG else {
                throw CocoaError(.fileWriteUnsupportedScheme)
            }
            return FileIdentity(device: information.st_dev, inode: information.st_ino)
        }
        if errno == ENOENT { return nil }
        throw currentPOSIXError()
    }

    private static func currentPOSIXError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    static func validateEncodedSize(_ count: Int) throws {
        guard count <= maximumFileSize else {
            throw TextFileDocumentError.fileTooLarge(maximumBytes: maximumFileSize)
        }
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) rethrows -> T {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}

private struct FileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}

private extension TextFileEncoding {
    var isLegacy: Bool {
        switch self {
        case .shiftJIS, .japaneseEUC, .iso2022JP:
            true
        case .utf8, .utf16LittleEndian, .utf16BigEndian:
            false
        }
    }
}
