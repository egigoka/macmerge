import Darwin
import Foundation

public struct TextFileDocument: Equatable, Sendable {
    public let url: URL
    var storageURL: URL
    fileprivate var storageIdentity: FileIdentity
    public var text: String
    public private(set) var persistedText: String
    public let encoding: TextFileEncoding
    public let hasByteOrderMark: Bool
    public private(set) var persistedData: Data

    public var isDirty: Bool { !text.unicodeScalars.elementsEqual(persistedText.unicodeScalars) }
    public var displayName: String { url.lastPathComponent }

    public static func == (lhs: TextFileDocument, rhs: TextFileDocument) -> Bool {
        lhs.url == rhs.url
            && lhs.storageURL == rhs.storageURL
            && lhs.storageIdentity == rhs.storageIdentity
            && lhs.text.unicodeScalars.elementsEqual(rhs.text.unicodeScalars)
            && lhs.persistedText.unicodeScalars.elementsEqual(rhs.persistedText.unicodeScalars)
            && lhs.encoding == rhs.encoding
            && lhs.hasByteOrderMark == rhs.hasByteOrderMark
            && lhs.persistedData == rhs.persistedData
    }

    fileprivate init(
        url: URL,
        storageURL: URL,
        storageIdentity: FileIdentity,
        decoded: DecodedTextFile,
        data: Data
    ) {
        self.url = url
        self.storageURL = storageURL
        self.storageIdentity = storageIdentity
        text = decoded.text
        persistedText = decoded.text
        encoding = decoded.encoding
        hasByteOrderMark = decoded.hasByteOrderMark
        persistedData = data
    }

    fileprivate mutating func markPersisted(
        decoded: DecodedTextFile,
        data: Data,
        storageURL: URL,
        storageIdentity: FileIdentity
    ) {
        text = decoded.text
        persistedText = decoded.text
        persistedData = data
        self.storageURL = storageURL
        self.storageIdentity = storageIdentity
    }
}

public enum TextFileDocumentError: Error, LocalizedError, Equatable, Sendable {
    case changedOnDisk
    case fileTooLarge(maximumBytes: Int)
    case saveOutcomeUncertain(String)
    case saveOutcomeUncertainWithoutRecovery

    public var errorDescription: String? {
        switch self {
        case .changedOnDisk:
            "File changed on disk after it was opened. Reload it before saving."
        case let .fileTooLarge(maximumBytes):
            "File exceeds the current \(maximumBytes)-byte safety limit."
        case let .saveOutcomeUncertain(path):
            "Save outcome could not be verified. The document remains edited and a recovery copy is at \(path)."
        case .saveOutcomeUncertainWithoutRecovery:
            "Save outcome could not be verified. The document remains edited, and no recovery copy could be verified."
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
    fileprivate let retainedFile: RetainedFile?

    public init(document: TextFileDocument, warning: TextFileSaveWarning? = nil) {
        self.document = document
        self.warning = warning
        retainedFile = nil
    }

    fileprivate init(
        document: TextFileDocument,
        warning: TextFileSaveWarning?,
        retainedFile: RetainedFile?
    ) {
        self.document = document
        self.warning = warning
        self.retainedFile = retainedFile
    }

    public static func == (lhs: TextFileSaveResult, rhs: TextFileSaveResult) -> Bool {
        lhs.document == rhs.document && lhs.warning == rhs.warning
    }
}

public enum TextFileDocumentIO {
    public static let maximumFileSize = 64 * 1024 * 1024

    public static func create(
        at url: URL,
        text: String,
        encoding: TextFileEncoding = .utf8
    ) throws -> TextFileDocument {
        try create(
            at: url,
            text: text,
            encoding: encoding,
            beforePublishing: {},
            afterPublishing: { _ in }
        )
    }

    static func create(
        at url: URL,
        text: String,
        encoding: TextFileEncoding = .utf8,
        beforePublishing: () throws -> Void,
        afterPublishing: (URL) throws -> Void
    ) throws -> TextFileDocument {
        let decoded = DecodedTextFile(
            text: text,
            encoding: encoding,
            hasByteOrderMark: false
        )
        let data = try TextFileCodec.encode(decoded)
        try validateEncodedSize(data.count)
        let persistedDecoded = try TextFileCodec.decode(data, assuming: encoding)

        return try withSecurityScopedAccess(to: url) {
            let initialStorageURL = url.resolvingSymlinksInPath().standardizedFileURL
            var coordinationError: NSError?
            var operationResult: Result<PublishedFile, any Error>?
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
                    let published = try atomicCreate(
                        data,
                        at: coordinatedURL,
                        beforePublishing: beforePublishing
                    )
                    do {
                        try afterPublishing(published.url)
                        guard let snapshot = verifiedRegularFileSnapshot(at: published.url),
                              snapshot.identity == published.identity,
                              snapshot.data == data else {
                            throw TextFileDocumentError.saveOutcomeUncertainWithoutRecovery
                        }
                    } catch {
                        throw uncertainPublishedOutcome(published)
                    }
                    guard url.resolvingSymlinksInPath().standardizedFileURL ==
                            published.url.standardizedFileURL else {
                        throw uncertainPublishedOutcome(published)
                    }
                    return published
                }
            }
            guard let operationResult else {
                if let coordinationError { throw coordinationError }
                throw CocoaError(.fileWriteUnknown)
            }
            switch operationResult {
            case .failure(let error):
                throw error
            case .success(let published):
                if coordinationError != nil {
                    throw uncertainPublishedOutcome(published)
                }
                guard let snapshot = verifiedRegularFileSnapshot(at: published.url),
                      snapshot.identity == published.identity,
                      snapshot.data == data,
                      url.resolvingSymlinksInPath().standardizedFileURL == published.url else {
                    throw uncertainPublishedOutcome(published)
                }
                let cleanupWarning = cleanupPublishedRecovery(published)
                if cleanupWarning != nil {
                    throw uncertainRetainedOutcome(published.retainedFile)
                }
                return TextFileDocument(
                    url: url,
                    storageURL: published.url,
                    storageIdentity: published.identity,
                    decoded: persistedDecoded,
                    data: data
                )
            }
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
            var operationResult: Result<
                (data: Data, storageURL: URL, storageIdentity: FileIdentity),
                any Error
            >?
            NSFileCoordinator().coordinate(readingItemAt: storageURL, options: [], error: &coordinationError) {
                coordinatedURL in
                operationResult = Result {
                    let snapshot = try pinRegularFile(at: coordinatedURL)
                    defer { Darwin.close(snapshot.descriptor) }
                    guard url.resolvingSymlinksInPath().standardizedFileURL ==
                            coordinatedURL.standardizedFileURL else {
                        throw TextFileDocumentError.changedOnDisk
                    }
                    return (
                        snapshot.data,
                        coordinatedURL.standardizedFileURL,
                        snapshot.identity
                    )
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
                storageIdentity: result.storageIdentity,
                decoded: try encoding.map { try TextFileCodec.decode(result.data, assuming: $0) }
                    ?? TextFileCodec.decode(result.data),
                data: result.data
            )
        }
    }

    public static func save(_ document: TextFileDocument) throws -> TextFileSaveResult {
        try save(document, beforeReplacing: {}, afterReplacing: { _, _ in })
    }

    static func save(
        _ document: TextFileDocument,
        afterReplacing: (_ savedURL: URL, _ backupURL: URL) throws -> Void
    ) throws -> TextFileSaveResult {
        try save(document, beforeReplacing: {}, afterReplacing: afterReplacing)
    }

    static func save(
        _ document: TextFileDocument,
        beforeReplacing: () throws -> Void,
        replaceItem: (
            _ originalURL: URL,
            _ newURL: URL,
            _ backupItemName: String
        ) throws -> URL? = { originalURL, newURL, backupItemName in
            try FileManager.default.replaceItemAt(
                originalURL,
                withItemAt: newURL,
                backupItemName: backupItemName,
                options: .withoutDeletingBackupItem
            )
        },
        afterReplacing: (_ savedURL: URL, _ backupURL: URL) throws -> Void,
        afterVerifyingRecovery: (_ backupURL: URL) throws -> Void = { _ in },
        afterVerifyingRecoveryBeforeDeletion: (_ recoveryURL: URL) throws -> Void = { _ in },
        beforeFinalVerification: () throws -> Void = {}
    ) throws -> TextFileSaveResult {
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
            var warningRetainedFile: RetainedFile?
            var savedStorageURL = document.storageURL
            var savedStorageIdentity = document.storageIdentity
            var replacementAttempted = false
            var attemptedRetainedFile: RetainedFile?
            var pendingRecoveryCleanup: RetainedFile?
            var committedTargetIdentity: FileIdentity?

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
                    let persistedTarget = try pinRegularFile(at: coordinatedURL)
                    var persistedTargetIsOpen = true
                    defer {
                        if persistedTargetIsOpen {
                            Darwin.close(persistedTarget.descriptor)
                        }
                    }
                    let persistedTargetData = persistedTarget.data
                    guard persistedTarget.identity == document.storageIdentity,
                          persistedTargetData == document.persistedData else {
                        throw TextFileDocumentError.changedOnDisk
                    }
                    guard document.isDirty else {
                        savedStorageURL = coordinatedURL.standardizedFileURL
                        savedStorageIdentity = persistedTarget.identity
                        return
                    }
                    let directory = coordinatedURL.deletingLastPathComponent()
                    let stagedURL = directory.appending(path: ".macmerge-\(UUID().uuidString).tmp")
                    let backupName = recoveryName(for: coordinatedURL)
                    let backupURL = directory.appending(path: backupName)
                    let staged = try createStagedFile(encodedData, at: stagedURL)
                    defer {
                        quarantineAndRemoveTemporary(
                            at: stagedURL,
                            expectedIdentity: staged.identity,
                            expectedData: staged.data,
                            stableReference: staged.stableReference
                        )
                        Darwin.close(staged.descriptor)
                    }
                    try beforeReplacing()
                    guard document.url.resolvingSymlinksInPath().standardizedFileURL ==
                            coordinatedURL.standardizedFileURL else {
                        throw TextFileDocumentError.changedOnDisk
                    }
                    guard pinnedFileIsCurrent(staged, at: stagedURL) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let pinnedTarget = try pinRegularFile(at: coordinatedURL)
                    let preReplacementReference = pinnedTarget.stableReference
                    var pinnedTargetIsOpen = true
                    defer {
                        if pinnedTargetIsOpen {
                            Darwin.close(pinnedTarget.descriptor)
                        }
                    }
                    var displacedData = pinnedTarget.data
                    guard pinnedFileIsCurrent(pinnedTarget, at: coordinatedURL) else {
                        throw TextFileDocumentError.changedOnDisk
                    }
                    guard !itemMayExistWithoutFollowingSymlinks(at: backupURL) else {
                        throw CocoaError(.fileWriteFileExists)
                    }
                    replacementAttempted = true
                    do {
                        savedStorageURL = try replaceItem(
                            coordinatedURL,
                            stagedURL,
                            backupName
                        )?.standardizedFileURL ?? coordinatedURL.standardizedFileURL
                    } catch {
                        throw classifyReplacementError(
                            error,
                            targetURL: coordinatedURL,
                            backupURL: backupURL,
                            expectedTargetData: encodedData,
                            pinnedTarget: pinnedTarget
                        )
                    }
                    let replacementTarget = verifiedRegularFileSnapshot(at: savedStorageURL)
                    let replacementBackup = verifiedRegularFileSnapshot(at: backupURL)
                    let backupReference = replacementBackup.flatMap {
                        verifiedStableReference(
                            to: backupURL,
                            expectedIdentity: $0.identity,
                            expectedData: $0.data
                        )
                    } ?? preReplacementReference
                    let postReplacementDisplacedData = replacementBackup.flatMap { backup in
                        verifiedDisplacedData(
                            pinnedTarget: pinnedTarget,
                            target: replacementTarget,
                            backup: backup
                        )
                    }
                    if let postReplacementDisplacedData {
                        displacedData = postReplacementDisplacedData
                        if let replacementBackup {
                            attemptedRetainedFile = RetainedFile(
                                url: backupURL,
                                identity: replacementBackup.identity,
                                data: postReplacementDisplacedData,
                                stableReference: backupReference
                            )
                        }
                    }
                    Darwin.close(pinnedTarget.descriptor)
                    pinnedTargetIsOpen = false
                    guard savedStorageURL == coordinatedURL.standardizedFileURL,
                          let replacementTarget,
                          replacementTarget.identity == staged.identity,
                          replacementTarget.data == encodedData,
                          let replacementBackup,
                          postReplacementDisplacedData != nil
                    else {
                        throw uncertainRetainedOutcome(
                            RetainedFile(
                                url: backupURL,
                                identity: pinnedTarget.identity,
                                data: displacedData,
                                stableReference: backupReference
                            )
                        )
                    }
                    guard document.url.resolvingSymlinksInPath().standardizedFileURL == savedStorageURL else {
                        throw uncertainRetainedOutcome(
                            RetainedFile(
                                url: backupURL,
                                identity: pinnedTarget.identity,
                                data: displacedData,
                                stableReference: backupReference
                            )
                        )
                    }
                    let currentTarget: VerifiedFileSnapshot
                    do {
                        try afterReplacing(savedStorageURL, backupURL)
                        guard let target = verifiedRegularFileSnapshot(at: savedStorageURL) else {
                            throw CocoaError(.fileReadUnknown)
                        }
                        currentTarget = target
                    } catch {
                        throw uncertainRetainedOutcome(
                            RetainedFile(
                                url: backupURL,
                                identity: pinnedTarget.identity,
                                data: displacedData,
                                stableReference: backupReference
                            )
                        )
                    }
                    guard currentTarget.identity == replacementTarget.identity,
                          currentTarget.data == encodedData else {
                        throw uncertainRetainedOutcome(
                            RetainedFile(
                                url: backupURL,
                                identity: pinnedTarget.identity,
                                data: displacedData,
                                stableReference: backupReference
                            )
                        )
                    }
                    guard document.url.resolvingSymlinksInPath().standardizedFileURL == savedStorageURL else {
                        throw uncertainRetainedOutcome(
                            RetainedFile(
                                url: backupURL,
                                identity: pinnedTarget.identity,
                                data: displacedData,
                                stableReference: backupReference
                            )
                        )
                    }
                    committedTargetIdentity = currentTarget.identity

                    guard let currentBackup = verifiedRegularFileSnapshot(at: backupURL) else {
                        if replacementBackup.data == displacedData,
                           let referenceAPI = StableFileReferenceAPI.shared,
                           let backupReference,
                           let retainedBackupURL = verifiedURL(
                               for: backupReference,
                               using: referenceAPI,
                               expectedIdentity: replacementBackup.identity,
                               expectedData: replacementBackup.data
                            ) {
                                warning = .recoveryCopyPreserved(retainedBackupURL.path)
                                warningRetainedFile = RetainedFile(
                                    url: retainedBackupURL,
                                    identity: replacementBackup.identity,
                                    data: replacementBackup.data,
                                    stableReference: backupReference
                                )
                                return
                        }
                        if itemMayExistWithoutFollowingSymlinks(at: backupURL) {
                            guard replacementBackup.data == displacedData else {
                                throw TextFileDocumentError.saveOutcomeUncertainWithoutRecovery
                            }
                            warning = .recoveryCopyPreserved(backupURL.path)
                            warningRetainedFile = RetainedFile(
                                url: backupURL,
                                identity: replacementBackup.identity,
                                data: replacementBackup.data,
                                stableReference: backupReference
                            )
                            return
                        }
                        guard replacementBackup.data == displacedData else {
                            throw TextFileDocumentError.saveOutcomeUncertainWithoutRecovery
                        }
                        return
                    }
                    guard currentBackup.data == displacedData else {
                        throw uncertainRetainedOutcome(attemptedRetainedFile)
                    }
                    guard pinnedTarget.identity == persistedTarget.identity,
                          replacementBackup.identity == pinnedTarget.identity,
                          currentBackup.identity == replacementBackup.identity,
                          currentBackup.data == document.persistedData else {
                        warning = .recoveryCopyPreserved(backupURL.path)
                        warningRetainedFile = RetainedFile(
                            url: backupURL,
                            identity: currentBackup.identity,
                            data: currentBackup.data,
                            stableReference: verifiedStableReference(
                                to: backupURL,
                                expectedIdentity: currentBackup.identity,
                                expectedData: currentBackup.data
                            )
                        )
                        return
                    }
                    Darwin.close(persistedTarget.descriptor)
                    persistedTargetIsOpen = false
                    do {
                        try afterVerifyingRecovery(backupURL)
                    } catch {
                        if let retainedBackup = verifiedRegularFileSnapshot(at: backupURL),
                           retainedBackup.identity == currentBackup.identity,
                           retainedBackup.data == currentBackup.data {
                            warning = .recoveryCopyPreserved(backupURL.path)
                            warningRetainedFile = RetainedFile(
                                url: backupURL,
                                identity: retainedBackup.identity,
                                data: retainedBackup.data,
                                stableReference: backupReference
                            )
                        } else if let warningURL = quarantineAndRemoveRecovery(
                            at: backupURL,
                            expectedIdentity: currentBackup.identity,
                            expectedData: currentBackup.data,
                            stableReference: backupReference
                        ) {
                            warning = .recoveryCopyPreserved(warningURL.path)
                            warningRetainedFile = RetainedFile(
                                url: warningURL,
                                identity: currentBackup.identity,
                                data: currentBackup.data,
                                stableReference: backupReference
                            )
                        }
                        return
                    }
                    pendingRecoveryCleanup = RetainedFile(
                        url: backupURL,
                        identity: currentBackup.identity,
                        data: currentBackup.data,
                        stableReference: backupReference
                    )
                } catch {
                    operationError = error
                }
            }
            if let operationError {
                throw operationError
            }
            if let coordinationError {
                if let pendingRecoveryCleanup {
                    throw uncertainRetainedOutcome(pendingRecoveryCleanup)
                }
                if replacementAttempted {
                    throw uncertainRetainedOutcome(warningRetainedFile ?? attemptedRetainedFile)
                }
                throw coordinationError
            }
            var recoveryCleanupHookFailed = false
            if let pendingRecoveryCleanup {
                do {
                    try afterVerifyingRecoveryBeforeDeletion(pendingRecoveryCleanup.url)
                } catch {
                    recoveryCleanupHookFailed = true
                }
            }
            do {
                try beforeFinalVerification()
            } catch {
                if replacementAttempted {
                    throw uncertainRetainedOutcome(warningRetainedFile ?? pendingRecoveryCleanup)
                }
                throw error
            }
            if replacementAttempted {
                guard let committedTargetIdentity,
                      let finalTarget = verifiedRegularFileSnapshot(at: savedStorageURL),
                      finalTarget.identity == committedTargetIdentity,
                      finalTarget.data == encodedData,
                      document.url.resolvingSymlinksInPath().standardizedFileURL == savedStorageURL else {
                    if let pendingRecoveryCleanup {
                        throw uncertainRetainedOutcome(pendingRecoveryCleanup)
                    }
                    throw uncertainRetainedOutcome(warningRetainedFile)
                }
                savedStorageIdentity = finalTarget.identity
            }
            if let pendingRecoveryCleanup {
                if recoveryCleanupHookFailed {
                    if let retainedURL = verifiedRetainedURL(pendingRecoveryCleanup) {
                        warning = .recoveryCopyPreserved(retainedURL.path)
                        warningRetainedFile = pendingRecoveryCleanup
                    }
                } else if let warningURL = removeIdentityBoundFile(
                    at: pendingRecoveryCleanup.url,
                    expectedIdentity: pendingRecoveryCleanup.identity,
                    expectedData: pendingRecoveryCleanup.data,
                    stableReference: pendingRecoveryCleanup.stableReference
                ) {
                    warning = .recoveryCopyPreserved(warningURL.path)
                    warningRetainedFile = pendingRecoveryCleanup
                }
            }
            if replacementAttempted {
                guard let committedTargetIdentity,
                      let finalTarget = verifiedRegularFileSnapshot(at: savedStorageURL),
                      finalTarget.identity == committedTargetIdentity,
                      finalTarget.data == encodedData,
                      document.url.resolvingSymlinksInPath().standardizedFileURL == savedStorageURL else {
                    throw uncertainRetainedOutcome(warningRetainedFile ?? pendingRecoveryCleanup)
                }
                savedStorageIdentity = finalTarget.identity
            }
            if let warningRetainedFile {
                guard let retainedURL = verifiedRetainedURL(warningRetainedFile) else {
                    throw TextFileDocumentError.saveOutcomeUncertainWithoutRecovery
                }
                warning = .recoveryCopyPreserved(retainedURL.path)
            }

            var saved = document
            saved.markPersisted(
                decoded: persistedDecoded,
                data: encodedData,
                storageURL: savedStorageURL,
                storageIdentity: savedStorageIdentity
            )
            return TextFileSaveResult(
                document: saved,
                warning: warning,
                retainedFile: warningRetainedFile
            )
        }
    }

    public static func saveAs(_ document: TextFileDocument, to url: URL) throws -> TextFileSaveResult {
        try saveAs(
            document,
            to: url,
            beforePublishing: {},
            afterPublishing: { _ in },
            saveSameStorage: save
        )
    }

    static func saveAs(
        _ document: TextFileDocument,
        to url: URL,
        beforePublishing: () throws -> Void,
        afterPublishing: (URL) throws -> Void,
        afterVerifyingDisplacedDestination: (URL) throws -> Void = { _ in },
        afterSwappingDestination: (URL) throws -> Void = { _ in },
        saveSameStorage: (TextFileDocument) throws -> TextFileSaveResult
    ) throws -> TextFileSaveResult {
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
            if initialStorageURL == document.storageURL.standardizedFileURL {
                let result = try saveSameStorage(document)
                let saved = result.document
                let currentStorageURL = url.resolvingSymlinksInPath().standardizedFileURL
                guard currentStorageURL == saved.storageURL.standardizedFileURL,
                      let snapshot = verifiedRegularFileSnapshot(at: currentStorageURL),
                      snapshot.identity == saved.storageIdentity,
                      snapshot.data == saved.persistedData,
                      url.resolvingSymlinksInPath().standardizedFileURL == currentStorageURL else {
                    throw uncertainRetainedOutcome(result.retainedFile)
                }
                let rebound = TextFileDocument(
                    url: url,
                    storageURL: currentStorageURL,
                    storageIdentity: snapshot.identity,
                    decoded: DecodedTextFile(
                        text: saved.persistedText,
                        encoding: saved.encoding,
                        hasByteOrderMark: saved.hasByteOrderMark
                    ),
                    data: saved.persistedData
                )
                let retainedFile: RetainedFile?
                let warning: TextFileSaveWarning?
                if result.warning != nil {
                    guard let candidate = result.retainedFile,
                          let retainedURL = verifiedRetainedURL(candidate) else {
                        throw TextFileDocumentError.saveOutcomeUncertainWithoutRecovery
                    }
                    retainedFile = RetainedFile(
                        url: retainedURL,
                        identity: candidate.identity,
                        data: candidate.data,
                        stableReference: candidate.stableReference
                    )
                    warning = .recoveryCopyPreserved(retainedURL.path)
                } else {
                    retainedFile = nil
                    warning = nil
                }
                return TextFileSaveResult(
                    document: rebound,
                    warning: warning,
                    retainedFile: retainedFile
                )
            }
            var coordinationError: NSError?
            var operationResult: Result<PublishedFile, any Error>?
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
                    let published = try atomicCreate(
                        encodedData,
                        at: coordinatedURL,
                        beforePublishing: beforePublishing,
                        afterSwappingDisplacedFile: afterSwappingDestination
                    )
                    do {
                        try afterPublishing(published.url)
                        guard let snapshot = verifiedRegularFileSnapshot(at: published.url),
                              snapshot.identity == published.identity,
                              snapshot.data == encodedData else {
                            throw TextFileDocumentError.saveOutcomeUncertainWithoutRecovery
                        }
                    } catch {
                        throw uncertainPublishedOutcome(published)
                    }
                    guard url.resolvingSymlinksInPath().standardizedFileURL == published.url else {
                        throw uncertainPublishedOutcome(published)
                    }
                    return published
                }
            }
            guard let operationResult else {
                if let coordinationError { throw coordinationError }
                throw CocoaError(.fileWriteUnknown)
            }
            switch operationResult {
            case .failure(let error):
                throw error
            case .success(let published):
                if coordinationError != nil {
                    throw uncertainPublishedOutcome(published)
                }
                var recoveryCleanupHookFailed = false
                if let retainedFile = published.retainedFile {
                    do {
                        try afterVerifyingDisplacedDestination(retainedFile.url)
                    } catch {
                        recoveryCleanupHookFailed = true
                    }
                }
                guard let snapshot = verifiedRegularFileSnapshot(at: published.url),
                      snapshot.identity == published.identity,
                      snapshot.data == encodedData,
                      url.resolvingSymlinksInPath().standardizedFileURL == published.url else {
                    throw uncertainPublishedOutcome(published)
                }
                let warning: TextFileSaveWarning?
                if recoveryCleanupHookFailed {
                    warning = verifiedRetainedURL(published.retainedFile)
                        .map { .recoveryCopyPreserved($0.path) }
                } else {
                    warning = cleanupPublishedRecovery(published)
                }
                return TextFileSaveResult(
                    document: TextFileDocument(
                        url: url,
                        storageURL: published.url,
                        storageIdentity: published.identity,
                        decoded: persistedDecoded,
                        data: encodedData
                    ),
                    warning: warning,
                    retainedFile: warning == nil ? nil : published.retainedFile
                )
            }
        }
    }

    private static func uncertainPublishedOutcome(_ published: PublishedFile) -> TextFileDocumentError {
        uncertainRetainedOutcome(published.retainedFile)
    }

    private static func uncertainRetainedOutcome(_ retainedFile: RetainedFile?) -> TextFileDocumentError {
        guard let retainedURL = verifiedRetainedURL(retainedFile) else {
            return .saveOutcomeUncertainWithoutRecovery
        }
        return .saveOutcomeUncertain(retainedURL.path)
    }

    private static func cleanupPublishedRecovery(
        _ published: PublishedFile,
        afterVerifying: (URL) throws -> Void = { _ in }
    ) -> TextFileSaveWarning? {
        guard let retainedFile = published.retainedFile else { return nil }
        guard let warningURL = removeIdentityBoundFile(
            at: retainedFile.url,
            expectedIdentity: retainedFile.identity,
            expectedData: retainedFile.data,
            stableReference: retainedFile.stableReference,
            afterVerifying: afterVerifying
        ),
            let snapshot = verifiedRegularFileSnapshot(at: warningURL),
            snapshot.identity == retainedFile.identity,
            snapshot.data == retainedFile.data
        else { return nil }
        return .recoveryCopyPreserved(warningURL.path)
    }

    private static func verifiedRetainedURL(_ retainedFile: RetainedFile?) -> URL? {
        guard let retainedFile else { return nil }
        if let snapshot = verifiedRegularFileSnapshot(at: retainedFile.url),
           snapshot.identity == retainedFile.identity,
           snapshot.data == retainedFile.data {
            return retainedFile.url
        }
        if let referenceAPI = StableFileReferenceAPI.shared,
           let stableReference = retainedFile.stableReference,
           let url = verifiedURL(
               for: stableReference,
               using: referenceAPI,
               expectedIdentity: retainedFile.identity,
               expectedData: retainedFile.data
           ) {
            return url
        }
        guard let snapshot = verifiedRegularFileSnapshot(at: retainedFile.url),
              snapshot.identity == retainedFile.identity,
              snapshot.data == retainedFile.data else { return nil }
        return retainedFile.url
    }

    private static func classifyReplacementError(
        _ error: any Error,
        targetURL: URL,
        backupURL: URL,
        expectedTargetData: Data,
        pinnedTarget: PinnedFileSnapshot
    ) -> any Error {
        let target = verifiedRegularFileSnapshot(at: targetURL)
        let backup = verifiedRegularFileSnapshot(at: backupURL)
        if let backup,
           let displacedData = verifiedDisplacedData(
               pinnedTarget: pinnedTarget,
               target: target,
               backup: backup
           ) {
            return uncertainRetainedOutcome(
                RetainedFile(
                    url: backupURL,
                    identity: backup.identity,
                    data: displacedData,
                    stableReference: verifiedStableReference(
                        to: backupURL,
                        expectedIdentity: backup.identity,
                        expectedData: displacedData
                    ) ?? pinnedTarget.stableReference
                )
            )
        }
        if !itemMayExistWithoutFollowingSymlinks(at: backupURL),
           let finalTarget = verifiedRegularFileSnapshot(at: targetURL) {
            if finalTarget.identity == pinnedTarget.identity,
               finalTarget.data == pinnedTarget.data,
               !itemMayExistWithoutFollowingSymlinks(at: backupURL) {
                return error
            }
            if finalTarget.data == expectedTargetData {
                return TextFileDocumentError.saveOutcomeUncertainWithoutRecovery
            }
        }
        return TextFileDocumentError.saveOutcomeUncertainWithoutRecovery
    }

    private static func verifiedDisplacedData(
        pinnedTarget: PinnedFileSnapshot,
        target: VerifiedFileSnapshot?,
        backup: VerifiedFileSnapshot
    ) -> Data? {
        guard backup.identity == pinnedTarget.identity,
              target?.identity != pinnedTarget.identity,
              verifiedData(
                  from: pinnedTarget.descriptor,
                  expectedIdentity: pinnedTarget.identity
              ) == backup.data
        else { return nil }
        return backup.data
    }

    private static func pinRegularFile(at url: URL) throws -> PinnedFileSnapshot {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw currentPOSIXError() }

        var openedInformation = stat()
        guard Darwin.fstat(descriptor, &openedInformation) == 0 else {
            Darwin.close(descriptor)
            throw currentPOSIXError()
        }
        guard openedInformation.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard openedInformation.st_size >= 0,
              UInt64(openedInformation.st_size) <= UInt64(maximumFileSize) else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadTooLarge)
        }
        let openedIdentity = FileIdentity(
            device: openedInformation.st_dev,
            inode: openedInformation.st_ino
        )
        guard let data = verifiedData(
            from: descriptor,
            expectedIdentity: openedIdentity,
            pathURL: url
        ) else {
            Darwin.close(descriptor)
            throw TextFileDocumentError.changedOnDisk
        }
        return PinnedFileSnapshot(
            descriptor: descriptor,
            identity: openedIdentity,
            data: data,
            stableReference: verifiedStableReference(
                to: url,
                expectedIdentity: openedIdentity,
                expectedData: data
            )
        )
    }

    private static func pinnedFileIsCurrent(_ snapshot: PinnedFileSnapshot, at url: URL) -> Bool {
        verifiedData(
            from: snapshot.descriptor,
            expectedIdentity: snapshot.identity,
            pathURL: url
        ) == snapshot.data
    }

    private static func verifiedRegularFileSnapshot(at url: URL) -> VerifiedFileSnapshot? {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG else { return nil }
        let identity = FileIdentity(device: information.st_dev, inode: information.st_ino)
        guard let data = verifiedData(
            from: descriptor,
            expectedIdentity: identity,
            pathURL: url
        ) else { return nil }
        return VerifiedFileSnapshot(identity: identity, data: data)
    }

    private static func verifiedData(
        from descriptor: Int32,
        expectedIdentity: FileIdentity,
        pathURL: URL? = nil
    ) -> Data? {
        var openedInformation = stat()
        guard Darwin.fstat(descriptor, &openedInformation) == 0,
              openedInformation.st_mode & S_IFMT == S_IFREG,
              openedInformation.st_size >= 0,
              UInt64(openedInformation.st_size) <= UInt64(maximumFileSize),
              FileIdentity(
                  device: openedInformation.st_dev,
                  inode: openedInformation.st_ino
              ) == expectedIdentity,
              Darwin.lseek(descriptor, 0, SEEK_SET) == 0,
              let data = try? readBoundedData(from: descriptor)
        else { return nil }

        var finalInformation = stat()
        guard Darwin.fstat(descriptor, &finalInformation) == 0,
              finalInformation.st_mode & S_IFMT == S_IFREG,
              FileIdentity(device: finalInformation.st_dev, inode: finalInformation.st_ino) == expectedIdentity,
              finalInformation.st_size == off_t(data.count),
              finalInformation.st_mtimespec.tv_sec == openedInformation.st_mtimespec.tv_sec,
              finalInformation.st_mtimespec.tv_nsec == openedInformation.st_mtimespec.tv_nsec,
              finalInformation.st_ctimespec.tv_sec == openedInformation.st_ctimespec.tv_sec,
              finalInformation.st_ctimespec.tv_nsec == openedInformation.st_ctimespec.tv_nsec
        else { return nil }
        if let pathURL,
           !regularFileMatchesWithoutFollowingSymlinks(
               at: pathURL,
               expectedInformation: finalInformation
           ) {
            return nil
        }
        return data
    }

    private static func regularFileMatchesWithoutFollowingSymlinks(
        at url: URL,
        expectedInformation: stat
    ) -> Bool {
        var pathInformation = stat()
        let pathResult = url.path.withCString { Darwin.lstat($0, &pathInformation) }
        guard pathResult == 0,
              pathInformation.st_mode & S_IFMT == S_IFREG,
              FileIdentity(
                  device: pathInformation.st_dev,
                  inode: pathInformation.st_ino
              ) == FileIdentity(
                  device: expectedInformation.st_dev,
                  inode: expectedInformation.st_ino
              ),
              pathInformation.st_size == expectedInformation.st_size,
              pathInformation.st_mtimespec.tv_sec == expectedInformation.st_mtimespec.tv_sec,
              pathInformation.st_mtimespec.tv_nsec == expectedInformation.st_mtimespec.tv_nsec,
              pathInformation.st_ctimespec.tv_sec == expectedInformation.st_ctimespec.tv_sec,
              pathInformation.st_ctimespec.tv_nsec == expectedInformation.st_ctimespec.tv_nsec
        else { return false }
        return true
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

    private static func quarantineAndRemoveRecovery(
        at backupURL: URL,
        expectedIdentity: FileIdentity,
        expectedData: Data,
        stableReference: StableFileReference? = nil,
        afterVerifyingRecovery: (URL) throws -> Void = { _ in }
    ) -> URL? {
        removeIdentityBoundFile(
            at: backupURL,
            expectedIdentity: expectedIdentity,
            expectedData: expectedData,
            stableReference: stableReference,
            afterVerifying: afterVerifyingRecovery
        )
    }

    private static func removeIdentityBoundFile(
        at expectedURL: URL,
        expectedIdentity: FileIdentity,
        expectedData: Data?,
        stableReference: StableFileReference?,
        afterVerifying: (URL) throws -> Void = { _ in }
    ) -> URL? {
        guard let referenceAPI = StableFileReferenceAPI.shared,
              let stableReference else {
            return itemMayExistWithoutFollowingSymlinks(at: expectedURL) ? expectedURL : nil
        }
        guard let initialURL = verifiedURL(
            for: stableReference,
            using: referenceAPI,
            expectedIdentity: expectedIdentity,
            expectedData: expectedData
        ) else {
            return retainedURL(for: stableReference, using: referenceAPI, fallback: expectedURL)
        }
        guard initialURL.standardizedFileURL == expectedURL.standardizedFileURL else {
            return initialURL
        }
        do {
            try afterVerifying(initialURL)
        } catch {
            return retainedURL(for: stableReference, using: referenceAPI, fallback: expectedURL)
        }
        guard verifiedURL(
            for: stableReference,
            using: referenceAPI,
            expectedIdentity: expectedIdentity,
            expectedData: expectedData,
            expectedURL: expectedURL
        ) != nil else {
            return retainedURL(for: stableReference, using: referenceAPI, fallback: expectedURL)
        }
        guard referenceAPI.delete(stableReference) == 0 else {
            return retainedURL(for: stableReference, using: referenceAPI, fallback: expectedURL)
        }
        return itemMayExistWithoutFollowingSymlinks(at: expectedURL) ? expectedURL : nil
    }

    private static func verifiedURL(
        for reference: StableFileReference,
        using referenceAPI: StableFileReferenceAPI,
        expectedIdentity: FileIdentity,
        expectedData: Data?,
        expectedURL: URL? = nil
    ) -> URL? {
        guard let url = referenceAPI.resolve(reference),
              let snapshot = verifiedRegularFileSnapshot(at: url),
              snapshot.identity == expectedIdentity,
              expectedData.map({ snapshot.data == $0 }) ?? true,
              expectedURL.map({ url.standardizedFileURL == $0.standardizedFileURL }) ?? true
        else { return nil }
        return url
    }

    private static func verifiedStableReference(
        to url: URL,
        expectedIdentity: FileIdentity,
        expectedData: Data? = nil
    ) -> StableFileReference? {
        guard let referenceAPI = StableFileReferenceAPI.shared,
              let reference = referenceAPI.makeReference(to: url),
              verifiedURL(
                  for: reference,
                  using: referenceAPI,
                  expectedIdentity: expectedIdentity,
                  expectedData: expectedData,
                  expectedURL: url
              ) != nil else { return nil }
        return reference
    }

    private static func retainedURL(
        for reference: StableFileReference,
        using referenceAPI: StableFileReferenceAPI,
        fallback: URL
    ) -> URL? {
        if let url = referenceAPI.resolve(reference),
           itemMayExistWithoutFollowingSymlinks(at: url) {
            return url
        }
        return itemMayExistWithoutFollowingSymlinks(at: fallback) ? fallback : nil
    }

    private static func quarantineAndRemoveTemporary(
        at url: URL,
        expectedIdentity: FileIdentity,
        expectedData: Data?,
        stableReference: StableFileReference?
    ) {
        _ = removeIdentityBoundFile(
            at: url,
            expectedIdentity: expectedIdentity,
            expectedData: expectedData,
            stableReference: stableReference
        )
    }

    private static func createStagedFile(_ data: Data, at url: URL) throws -> PinnedFileSnapshot {
        let descriptor = Darwin.open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw currentPOSIXError() }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            Darwin.close(descriptor)
            throw currentPOSIXError()
        }
        let identity = FileIdentity(device: information.st_dev, inode: information.st_ino)
        let stableReference = StableFileReferenceAPI.shared?.makeReference(to: url)
        var succeeded = false
        defer {
            if !succeeded {
                quarantineAndRemoveTemporary(
                    at: url,
                    expectedIdentity: identity,
                    expectedData: nil,
                    stableReference: stableReference
                )
            }
            Darwin.close(descriptor)
        }

        try write(data, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else { throw currentPOSIXError() }
        let snapshot = try pinRegularFile(at: url)
        guard snapshot.identity == identity, snapshot.data == data else {
            Darwin.close(snapshot.descriptor)
            throw TextFileDocumentError.changedOnDisk
        }
        succeeded = true
        return PinnedFileSnapshot(
            descriptor: snapshot.descriptor,
            identity: snapshot.identity,
            data: snapshot.data,
            stableReference: stableReference
        )
    }

    private static func readBoundedData(from descriptor: Int32) throws -> Data {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let chunkSize = 1024 * 1024
        var data = Data()
        while true {
            let remaining = maximumFileSize - data.count
            let requestedCount = remaining >= chunkSize ? chunkSize : remaining + 1
            guard let chunk = try handle.read(upToCount: requestedCount), !chunk.isEmpty else {
                return data
            }
            data.append(chunk)
            guard data.count <= maximumFileSize else {
                throw CocoaError(.fileReadTooLarge)
            }
        }
    }

    private static func atomicCreate(
        _ data: Data,
        at url: URL,
        beforePublishing: () throws -> Void,
        afterSwappingDisplacedFile: (URL) throws -> Void = { _ in }
    ) throws -> PublishedFile {
        let storageURL = url.standardizedFileURL
        let directoryURL = storageURL.deletingLastPathComponent()
        let name = storageURL.lastPathComponent
        let directoryFD = Darwin.open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directoryFD >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(directoryFD) }

        let originalIdentity = try fileIdentity(directoryFD: directoryFD, name: name)
        let initialOriginal = try originalIdentity.map { identity in
            let snapshot = try pinRegularFile(at: storageURL)
            guard snapshot.identity == identity else {
                Darwin.close(snapshot.descriptor)
                throw TextFileDocumentError.changedOnDisk
            }
            return snapshot
        }
        defer {
            if let initialOriginal {
                Darwin.close(initialOriginal.descriptor)
            }
        }
        let stagedName = ".macmerge-\(UUID().uuidString).tmp"
        let stagedFD = stagedName.withCString {
            Darwin.openat(directoryFD, $0, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard stagedFD >= 0 else { throw currentPOSIXError() }
        var stagedInformation = stat()
        guard Darwin.fstat(stagedFD, &stagedInformation) == 0 else {
            Darwin.close(stagedFD)
            throw currentPOSIXError()
        }
        let stagedIdentity = FileIdentity(
            device: stagedInformation.st_dev,
            inode: stagedInformation.st_ino
        )
        let stagedURL = directoryURL.appending(path: stagedName)
        let stagedReference = StableFileReferenceAPI.shared?.makeReference(to: stagedURL)
        defer {
            quarantineAndRemoveTemporary(
                at: stagedURL,
                expectedIdentity: stagedIdentity,
                expectedData: nil,
                stableReference: stagedReference
            )
            Darwin.close(stagedFD)
        }

        try write(data, to: stagedFD)
        guard Darwin.fsync(stagedFD) == 0 else { throw currentPOSIXError() }
        guard Darwin.fstat(stagedFD, &stagedInformation) == 0 else { throw currentPOSIXError() }
        guard FileIdentity(
            device: stagedInformation.st_dev,
            inode: stagedInformation.st_ino
        ) == stagedIdentity,
              stagedInformation.st_size == off_t(data.count) else {
            throw TextFileDocumentError.changedOnDisk
        }
        guard try fileIdentity(directoryFD: directoryFD, name: name) == originalIdentity else {
            throw TextFileDocumentError.changedOnDisk
        }
        try beforePublishing()
        guard try fileIdentity(directoryFD: directoryFD, name: stagedName) == stagedIdentity,
              verifiedData(
                  from: stagedFD,
                  expectedIdentity: stagedIdentity,
                  pathURL: stagedURL
        ) == data else {
            throw TextFileDocumentError.changedOnDisk
        }
        let original = try originalIdentity.map { _ in
            try pinRegularFile(at: storageURL)
        }
        let preSwapReference = original?.stableReference
        defer {
            if let original {
                Darwin.close(original.descriptor)
            }
        }
        let renamed = stagedName.withCString { stagedPath in
            name.withCString { targetPath in
                if originalIdentity == nil {
                    return Darwin.renameatx_np(
                        directoryFD,
                        stagedPath,
                        directoryFD,
                        targetPath,
                        UInt32(RENAME_EXCL)
                    )
                }
                return Darwin.renameatx_np(
                    directoryFD,
                    stagedPath,
                    directoryFD,
                    targetPath,
                    UInt32(RENAME_SWAP)
                )
            }
        }
        guard renamed == 0 else {
            if errno == EEXIST { throw TextFileDocumentError.changedOnDisk }
            throw currentPOSIXError()
        }
        if originalIdentity != nil {
            let displacedURL = stagedURL
            guard let original else {
                throw TextFileDocumentError.saveOutcomeUncertainWithoutRecovery
            }
            let retainedOriginal = RetainedFile(
                url: displacedURL,
                identity: original.identity,
                data: original.data,
                stableReference: preSwapReference
            )
            do {
                try afterSwappingDisplacedFile(displacedURL)
            } catch {
                throw uncertainRetainedOutcome(retainedOriginal)
            }
            guard let displaced = verifiedRegularFileSnapshot(at: displacedURL) else {
                throw uncertainRetainedOutcome(retainedOriginal)
            }
            guard displaced.identity == original.identity,
                  displaced.data == original.data,
                  verifiedData(
                      from: original.descriptor,
                   expectedIdentity: original.identity
                  ) == original.data else {
                throw uncertainRetainedOutcome(retainedOriginal)
            }
            guard initialOriginal?.identity == original.identity,
                  initialOriginal?.data == original.data else {
                throw uncertainRetainedOutcome(retainedOriginal)
            }
            let displacedReference = verifiedStableReference(
                to: displacedURL,
                expectedIdentity: displaced.identity,
                expectedData: displaced.data
            ) ?? preSwapReference
            return try finishPublishedFile(
                at: storageURL,
                directoryFD: directoryFD,
                name: name,
                identity: stagedIdentity,
                retainedFile: RetainedFile(
                    url: displacedURL,
                    identity: original.identity,
                    data: displaced.data,
                    stableReference: displacedReference
                )
            )
        }
        return try finishPublishedFile(
            at: storageURL,
            directoryFD: directoryFD,
            name: name,
            identity: stagedIdentity,
            retainedFile: nil
        )
    }

    private static func finishPublishedFile(
        at storageURL: URL,
        directoryFD: Int32,
        name: String,
        identity: FileIdentity,
        retainedFile: RetainedFile?
    ) throws -> PublishedFile {
        let finalIdentity: FileIdentity
        do {
            guard let identity = try fileIdentity(directoryFD: directoryFD, name: name) else {
                throw uncertainRetainedOutcome(retainedFile)
            }
            finalIdentity = identity
        } catch {
            throw uncertainRetainedOutcome(retainedFile)
        }
        guard finalIdentity == identity else {
            throw uncertainRetainedOutcome(retainedFile)
        }
        guard Darwin.fsync(directoryFD) == 0 else {
            throw uncertainRetainedOutcome(retainedFile)
        }
        return PublishedFile(
            url: storageURL,
            identity: identity,
            retainedFile: retainedFile,
            warning: nil
        )
    }

    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw currentPOSIXError() }
                offset += written
            }
        }
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

    static func identityBoundDeleteStatusesForTesting(at url: URL) -> (Int16, Int16)? {
        guard let referenceAPI = StableFileReferenceAPI.shared,
              let snapshot = verifiedRegularFileSnapshot(at: url),
              let reference = verifiedStableReference(
                  to: url,
                  expectedIdentity: snapshot.identity,
                  expectedData: snapshot.data
              ) else { return nil }
        return (
            referenceAPI.deleteResult(reference),
            referenceAPI.deleteResult(reference)
        )
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

fileprivate struct FileIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
}

private struct PinnedFileSnapshot {
    let descriptor: Int32
    let identity: FileIdentity
    let data: Data
    let stableReference: StableFileReference?
}

private struct VerifiedFileSnapshot {
    let identity: FileIdentity
    let data: Data
}

private struct PublishedFile {
    let url: URL
    let identity: FileIdentity
    let retainedFile: RetainedFile?
    let warning: TextFileSaveWarning?
}

fileprivate struct RetainedFile: Equatable, Sendable {
    let url: URL
    let identity: FileIdentity
    let data: Data
    let stableReference: StableFileReference?
}

private struct StableFileReference: Equatable, Sendable {
    var storage = [UInt8](repeating: 0, count: 80)
}

private struct StableFileReferenceAPI: @unchecked Sendable {
    typealias MakeReference = @convention(c) (
        UnsafePointer<UInt8>?,
        UInt32,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UInt8>?
    ) -> OSStatus
    typealias ResolveReference = @convention(c) (
        UnsafeRawPointer?,
        UnsafeMutablePointer<UInt8>?,
        UInt32
    ) -> OSStatus
    typealias DeleteReference = @convention(c) (UnsafeRawPointer?) -> Int16
    static let shared: StableFileReferenceAPI? = {
        guard let handle = Darwin.dlopen(
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
            RTLD_LAZY | RTLD_LOCAL
        ) else {
            return nil
        }
        guard let makeReference = Darwin.dlsym(handle, "FSPathMakeRefWithOptions"),
              let resolveReference = Darwin.dlsym(handle, "FSRefMakePath"),
              let deleteReference = Darwin.dlsym(handle, "FSDeleteObject") else {
            Darwin.dlclose(handle)
            return nil
        }
        return StableFileReferenceAPI(
            handle: handle,
            makeReference: unsafeBitCast(makeReference, to: MakeReference.self),
            resolveReference: unsafeBitCast(resolveReference, to: ResolveReference.self),
            deleteReference: unsafeBitCast(deleteReference, to: DeleteReference.self)
        )
    }()

    private let handle: UnsafeMutableRawPointer
    private let makeReference: MakeReference
    private let resolveReference: ResolveReference
    private let deleteReference: DeleteReference

    func makeReference(to url: URL) -> StableFileReference? {
        var reference = StableFileReference()
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return OSStatus(-1) }
            return reference.storage.withUnsafeMutableBytes { storage in
                makeReference(
                    UnsafeRawPointer(path).assumingMemoryBound(to: UInt8.self),
                    1,
                    storage.baseAddress,
                    nil
                )
            }
        }
        return status == 0 ? reference : nil
    }

    func resolve(_ reference: StableFileReference) -> URL? {
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        let status = reference.storage.withUnsafeBytes { storage in
            path.withUnsafeMutableBufferPointer { pathBuffer in
                resolveReference(
                    storage.baseAddress,
                    UnsafeMutableRawPointer(pathBuffer.baseAddress!).assumingMemoryBound(to: UInt8.self),
                    UInt32(pathBuffer.count)
                )
            }
        }
        guard status == 0, let pathStart = path.withUnsafeBufferPointer({ $0.baseAddress }) else {
            return nil
        }
        return URL(
            fileURLWithFileSystemRepresentation: pathStart,
            isDirectory: false,
            relativeTo: nil
        )
    }

    func delete(_ reference: StableFileReference) -> OSStatus {
        OSStatus(deleteResult(reference))
    }

    func deleteResult(_ reference: StableFileReference) -> Int16 {
        reference.storage.withUnsafeBytes { storage in
            deleteReference(storage.baseAddress)
        }
    }
}

private extension TextFileEncoding {
    var isLegacy: Bool {
        switch self {
        case .shiftJIS, .japaneseEUC, .iso2022JP, .windows1250, .windows1251, .windows1252,
             .windows1253, .windows1254, .windows1255:
            true
        case .utf8, .utf16LittleEndian, .utf16BigEndian:
            false
        }
    }
}
