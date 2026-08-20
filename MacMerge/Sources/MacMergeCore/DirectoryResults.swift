import Darwin
import Foundation

public enum DirectoryEntryKind: Int, CaseIterable, Hashable, Sendable {
    case file
    case directory
    case symbolicLink
    case other
}

public struct DirectoryEntryMetadata: Hashable, Sendable {
    public let relativePath: String
    public let kind: DirectoryEntryKind
    public let byteCount: UInt64?
    public let modificationDate: Date?
    public let isHidden: Bool

    public init(
        relativePath: String,
        kind: DirectoryEntryKind,
        byteCount: UInt64? = nil,
        modificationDate: Date? = nil,
        isHidden: Bool? = nil
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.byteCount = byteCount
        self.modificationDate = modificationDate.flatMap {
            $0.timeIntervalSinceReferenceDate.isFinite ? $0 : nil
        }
        let hasHiddenPathComponent = relativePath.split(separator: "/").contains {
            $0.hasPrefix(".") && $0 != "." && $0 != ".."
        }
        self.isHidden = (isHidden ?? false) || hasHiddenPathComponent
    }
}

public enum DirectoryComparisonStatus: Int, CaseIterable, Hashable, Sendable {
    case pending
    case identical
    case different
    case leftOnly
    case rightOnly
    case typeMismatch
    case skipped
    case error
}

public enum DirectoryRenameApplicationError: Error, Equatable, Sendable {
    case duplicateMatch(side: FolderComparisonSide, relativePath: String)
    case staleMatch(side: FolderComparisonSide, relativePath: String)
    case pathCollision(side: FolderComparisonSide, relativePath: String)
}

public struct DirectoryFilePair: Equatable, Sendable {
    enum OpenSide: Equatable, Sendable {
        case left
        case right
    }

    enum OpenCheckpoint: Equatable, Sendable {
        case openedIntermediate(side: OpenSide, relativePath: String, component: String)
        case beforeLeaf(side: OpenSide, relativePath: String)
    }

    @TaskLocal
    static var openObserver: (@Sendable (OpenCheckpoint) -> Void)?

    private let descriptorStorage: DirectoryFileDescriptorStorage

    public init(leftURL: URL, rightURL: URL) throws {
        let leftDescriptor = try openPinnedRegularFile(leftURL)
        do {
            let rightDescriptor = try openPinnedRegularFile(rightURL)
            descriptorStorage = DirectoryFileDescriptorStorage(
                left: leftDescriptor,
                right: rightDescriptor
            )
        } catch {
            Darwin.close(leftDescriptor)
            throw error
        }
    }

    fileprivate init(leftDescriptor: Int32, rightDescriptor: Int32) {
        descriptorStorage = DirectoryFileDescriptorStorage(
            left: leftDescriptor,
            right: rightDescriptor
        )
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.descriptorStorage.identity == right.descriptorStorage.identity
    }

    /// Readers remain valid only for the duration of `body` and never expose filesystem paths.
    /// Throws `DirectoryFilePairError.accessInProgress` for nested or concurrent access.
    public func withReaders<Result>(
        _ body: (DirectoryFileReader, DirectoryFileReader) throws -> Result
    ) throws -> Result {
        try descriptorStorage.withReaders(body)
    }
}

public enum DirectoryFilePairError: Error, Equatable, Sendable {
    case accessInProgress
}

public enum DirectoryFileReaderError: Error, Equatable, Sendable {
    case inactive
    case invalidReadRange
    case invalidFileSize
    case fileTooLarge(maximumByteCount: Int)
    case changedWhileReading
    case posix(Int32)
}

public final class DirectoryFileReader: @unchecked Sendable {
    enum ReadCheckpoint: Equatable, Sendable {
        case afterInitialSnapshot
    }

    @TaskLocal
    static var readObserver: (@Sendable (ReadCheckpoint) -> Void)?

    private let descriptor: Int32
    private let scope: DirectoryFileReadScope

    fileprivate init(descriptor: Int32, scope: DirectoryFileReadScope) {
        self.descriptor = descriptor
        self.scope = scope
    }

    public func read(upToCount count: Int, atOffset offset: UInt64 = 0) throws -> Data {
        guard count >= 0, let readOffset = off_t(exactly: offset) else {
            throw DirectoryFileReaderError.invalidReadRange
        }
        return try scope.withActive {
            guard count > 0 else { return Data() }
            return try readOnce(count: count, offset: readOffset)
        }
    }

    public func readToEnd(
        maximumByteCount: Int,
        fromOffset offset: UInt64 = 0
    ) throws -> Data {
        guard maximumByteCount >= 0,
            let readOffset = off_t(exactly: offset),
            let maximumSize = off_t(exactly: maximumByteCount)
        else {
            throw DirectoryFileReaderError.invalidReadRange
        }
        return try scope.withActive {
            let initialInformation = try fileInformation()
            guard initialInformation.st_mode & S_IFMT == S_IFREG,
                initialInformation.st_size >= 0
            else {
                throw DirectoryFileReaderError.invalidFileSize
            }
            let initialByteCount =
                readOffset < initialInformation.st_size
                ? initialInformation.st_size - readOffset
                : 0
            guard initialByteCount <= maximumSize else {
                throw DirectoryFileReaderError.fileTooLarge(
                    maximumByteCount: maximumByteCount
                )
            }
            guard let expectedByteCount = Int(exactly: initialByteCount) else {
                throw DirectoryFileReaderError.invalidFileSize
            }

            Self.readObserver?(.afterInitialSnapshot)

            var data = Data()
            data.reserveCapacity(expectedByteCount)
            var currentOffset = readOffset
            var remaining = expectedByteCount
            while remaining > 0 {
                let chunk = try readOnce(count: min(remaining, 64 * 1_024), offset: currentOffset)
                guard !chunk.isEmpty else { break }
                data.append(chunk)
                remaining -= chunk.count
                guard let consumedByteCount = off_t(exactly: chunk.count) else {
                    throw DirectoryFileReaderError.invalidFileSize
                }
                currentOffset += consumedByteCount
            }

            let finalInformation = try fileInformation()
            guard
                DirectoryRootIdentity(finalInformation)
                    == DirectoryRootIdentity(initialInformation),
                finalInformation.st_mode & S_IFMT == S_IFREG
            else {
                throw DirectoryFileReaderError.changedWhileReading
            }
            guard finalInformation.st_size >= 0 else {
                throw DirectoryFileReaderError.invalidFileSize
            }
            let finalByteCount =
                readOffset < finalInformation.st_size
                ? finalInformation.st_size - readOffset
                : 0
            guard finalByteCount <= maximumSize else {
                throw DirectoryFileReaderError.fileTooLarge(
                    maximumByteCount: maximumByteCount
                )
            }
            guard data.count == expectedByteCount,
                finalInformation.st_size == initialInformation.st_size,
                finalInformation.st_mtimespec.tv_sec
                    == initialInformation.st_mtimespec.tv_sec,
                finalInformation.st_mtimespec.tv_nsec
                    == initialInformation.st_mtimespec.tv_nsec
            else {
                throw DirectoryFileReaderError.changedWhileReading
            }
            return data
        }
    }

    private func fileInformation() throws -> stat {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            throw DirectoryFileReaderError.posix(errno)
        }
        return information
    }

    private func readOnce(count: Int, offset: off_t) throws -> Data {
        var data = Data(count: count)
        let readCount = try data.withUnsafeMutableBytes { buffer -> Int in
            while true {
                let result = Darwin.pread(descriptor, buffer.baseAddress, count, offset)
                if result >= 0 { return result }
                if errno != EINTR { throw DirectoryFileReaderError.posix(errno) }
            }
        }
        data.removeSubrange(readCount..<count)
        return data
    }
}

private final class DirectoryFileReadScope: @unchecked Sendable {
    private let lock = NSLock()
    private var isActive = true

    func withActive<Result>(_ body: () throws -> Result) throws -> Result {
        lock.lock()
        defer { lock.unlock() }
        guard isActive else { throw DirectoryFileReaderError.inactive }
        return try body()
    }

    func invalidate() {
        lock.lock()
        isActive = false
        lock.unlock()
    }
}

private final class DirectoryFileDescriptorStorage: @unchecked Sendable {
    private let left: Int32
    private let right: Int32
    private let lock = NSLock()
    private var isAccessing = false
    let identity: DirectoryRootPairIdentity

    init(left: Int32, right: Int32) {
        self.left = left
        self.right = right
        guard let leftIdentity = descriptorIdentity(left),
            let rightIdentity = descriptorIdentity(right)
        else {
            preconditionFailure("Open directory file descriptors require identities")
        }
        identity = DirectoryRootPairIdentity(left: leftIdentity, right: rightIdentity)
    }

    func withReaders<Result>(
        _ body: (DirectoryFileReader, DirectoryFileReader) throws -> Result
    ) throws -> Result {
        try beginAccess()
        let scope = DirectoryFileReadScope()
        defer {
            scope.invalidate()
            endAccess()
        }
        return try withExtendedLifetime(self) {
            try body(
                DirectoryFileReader(descriptor: left, scope: scope),
                DirectoryFileReader(descriptor: right, scope: scope)
            )
        }
    }

    private func beginAccess() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isAccessing else { throw DirectoryFilePairError.accessInProgress }
        isAccessing = true
    }

    private func endAccess() {
        lock.lock()
        isAccessing = false
        lock.unlock()
    }

    deinit {
        Darwin.close(left)
        Darwin.close(right)
    }
}

public struct DirectoryResult: Identifiable, Hashable, Sendable {
    public struct ID: Hashable, Sendable {
        public let leftRelativePath: String?
        public let rightRelativePath: String?

        public var relativePath: String {
            leftRelativePath ?? rightRelativePath ?? ""
        }

        public init(leftRelativePath: String?, rightRelativePath: String?) {
            precondition(
                leftRelativePath != nil || rightRelativePath != nil,
                "A directory result ID requires a relative path"
            )
            self.leftRelativePath = leftRelativePath
            self.rightRelativePath = rightRelativePath
        }

        public static func == (left: Self, right: Self) -> Bool {
            left.identity == right.identity
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(identity)
        }

        private enum Identity: Hashable {
            case path(String)
            case pair(left: String, right: String)
        }

        private var identity: Identity {
            switch (leftRelativePath, rightRelativePath) {
            case (let left?, let right?) where left != right:
                .pair(left: left, right: right)
            case (let left?, _):
                .path(left)
            case (_, let right?):
                .path(right)
            case (nil, nil):
                preconditionFailure("A directory result ID requires a relative path")
            }
        }
    }

    public let left: DirectoryEntryMetadata?
    public let right: DirectoryEntryMetadata?
    public let status: DirectoryComparisonStatus

    public var id: ID {
        ID(leftRelativePath: left?.relativePath, rightRelativePath: right?.relativePath)
    }

    public var relativePath: String {
        left?.relativePath ?? right?.relativePath ?? ""
    }

    public var kind: DirectoryEntryKind? {
        switch (left?.kind, right?.kind) {
        case (let left?, let right?) where left == right:
            left
        case (let left?, nil):
            left
        case (nil, let right?):
            right
        default:
            nil
        }
    }

    public var isHidden: Bool {
        left?.isHidden == true || right?.isHidden == true
    }

    public var isOpenableFilePair: Bool {
        left?.kind == .file && right?.kind == .file
    }

    public init(
        left: DirectoryEntryMetadata?,
        right: DirectoryEntryMetadata?,
        status: DirectoryComparisonStatus
    ) {
        precondition(left != nil || right != nil, "A directory result requires at least one side")
        precondition(
            Self.hasValidSidesAndKinds(left: left, right: right, status: status),
            "Directory result status contradicts its sides or kinds"
        )
        self.left = left
        self.right = right
        self.status = status
    }

    public func openableFilePair(leftRoot: URL, rightRoot: URL) -> DirectoryFilePair? {
        DirectoryRootDescriptorStorage(leftRoot: leftRoot, rightRoot: rightRoot)?
            .openableFilePair(for: self)
    }

    private static func hasValidSidesAndKinds(
        left: DirectoryEntryMetadata?,
        right: DirectoryEntryMetadata?,
        status: DirectoryComparisonStatus
    ) -> Bool {
        switch status {
        case .leftOnly:
            left != nil && right == nil
        case .rightOnly:
            left == nil && right != nil
        case .typeMismatch:
            left != nil && right != nil && left?.kind != right?.kind
        case .pending, .identical, .different, .skipped, .error:
            left != nil && right != nil && left?.kind == right?.kind
        }
    }
}

public enum DirectoryHiddenFilter: Hashable, Sendable {
    case include
    case exclude
    case only
}

public struct DirectoryResultFilter: Equatable, Sendable {
    public var statuses: Set<DirectoryComparisonStatus>
    public var pathQuery: String
    public var kinds: Set<DirectoryEntryKind>
    public var hidden: DirectoryHiddenFilter

    public init(
        statuses: Set<DirectoryComparisonStatus> = [],
        pathQuery: String = "",
        kinds: Set<DirectoryEntryKind> = [],
        hidden: DirectoryHiddenFilter = .include
    ) {
        self.statuses = statuses
        self.pathQuery = pathQuery
        self.kinds = kinds
        self.hidden = hidden
    }

    public func matches(_ result: DirectoryResult) -> Bool {
        if !statuses.isEmpty, !statuses.contains(result.status) {
            return false
        }
        if !kinds.isEmpty {
            let leftMatches = result.left.map { kinds.contains($0.kind) } == true
            let rightMatches = result.right.map { kinds.contains($0.kind) } == true
            if !leftMatches && !rightMatches {
                return false
            }
        }
        switch hidden {
        case .include:
            break
        case .exclude where result.isHidden:
            return false
        case .only where !result.isHidden:
            return false
        default:
            break
        }
        guard !pathQuery.isEmpty else { return true }
        return [result.left?.relativePath, result.right?.relativePath]
            .compactMap { $0 }
            .contains { path in
                path.range(
                    of: pathQuery,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                ) != nil
            }
    }
}

public enum DirectoryResultSortKey: Hashable, Sendable {
    case path
    case status
    case kind
    case leftSize
    case rightSize
    case leftModificationDate
    case rightModificationDate
}

public enum DirectoryResultSortOrder: Hashable, Sendable {
    case ascending
    case descending
}

public struct DirectoryResultSortDescriptor: Hashable, Sendable {
    public var key: DirectoryResultSortKey
    public var order: DirectoryResultSortOrder

    public init(
        key: DirectoryResultSortKey,
        order: DirectoryResultSortOrder = .ascending
    ) {
        self.key = key
        self.order = order
    }
}

public struct DirectoryResults: Equatable, Sendable {
    public let leftRoot: URL
    public let rightRoot: URL
    public private(set) var results: [DirectoryResult]
    public var filter: DirectoryResultFilter
    public var sortDescriptors: [DirectoryResultSortDescriptor]
    public private(set) var selectedIDs: Set<DirectoryResult.ID>
    private let rootDescriptorStorage: DirectoryRootDescriptorStorage?

    public var visibleResults: [DirectoryResult] {
        let filtered = results.enumerated().filter { filter.matches($0.element) }
        return filtered.sorted { left, right in
            for descriptor in sortDescriptors {
                let comparison = Self.compare(left.element, right.element, by: descriptor.key)
                guard comparison != .same else { continue }
                return descriptor.order == .ascending
                    ? comparison == .before
                    : comparison == .after
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    public var selectedResults: [DirectoryResult] {
        results.filter { selectedIDs.contains($0.id) }
    }

    public init(
        leftRoot: URL,
        rightRoot: URL,
        results: [DirectoryResult] = [],
        filter: DirectoryResultFilter = DirectoryResultFilter(),
        sortDescriptors: [DirectoryResultSortDescriptor] = [
            DirectoryResultSortDescriptor(key: .path)
        ],
        selectedIDs: Set<DirectoryResult.ID> = []
    ) {
        precondition(Self.hasUniqueIDs(results), "Directory result IDs must be unique")
        self.leftRoot = leftRoot
        self.rightRoot = rightRoot
        self.results = results
        self.filter = filter
        self.sortDescriptors = sortDescriptors
        let availableIDs = Set(results.map(\.id))
        self.selectedIDs = selectedIDs.intersection(availableIDs)
        rootDescriptorStorage = DirectoryRootDescriptorStorage(
            leftRoot: leftRoot,
            rightRoot: rightRoot
        )
    }

    public mutating func replaceResults(_ results: [DirectoryResult]) {
        precondition(Self.hasUniqueIDs(results), "Directory result IDs must be unique")
        let previousResultsByID = Dictionary(uniqueKeysWithValues: self.results.map { ($0.id, $0) })
        let availableIDs = Set(results.map(\.id))
        var leftRenameIDsByPath: [String: [DirectoryResult.ID]] = [:]
        var rightRenameIDsByPath: [String: [DirectoryResult.ID]] = [:]
        for result in results {
            guard let leftPath = result.left?.relativePath,
                let rightPath = result.right?.relativePath,
                leftPath != rightPath
            else {
                continue
            }
            leftRenameIDsByPath[leftPath, default: []].append(result.id)
            rightRenameIDsByPath[rightPath, default: []].append(result.id)
        }
        var replacementSelection: Set<DirectoryResult.ID> = []
        for selectedID in selectedIDs {
            guard let previousResult = previousResultsByID[selectedID] else {
                continue
            }
            guard let selectedSide = Self.oneSidedPath(of: previousResult) else {
                if availableIDs.contains(selectedID) {
                    replacementSelection.insert(selectedID)
                }
                continue
            }
            let matchingIDs: [DirectoryResult.ID]
            switch selectedSide {
            case .left(let path):
                matchingIDs = leftRenameIDsByPath[path] ?? []
            case .right(let path):
                matchingIDs = rightRenameIDsByPath[path] ?? []
            }
            if matchingIDs.count == 1 {
                replacementSelection.insert(matchingIDs[0])
            } else if matchingIDs.isEmpty, availableIDs.contains(selectedID) {
                replacementSelection.insert(selectedID)
            }
        }
        self.results = results
        selectedIDs = replacementSelection
    }

    /// Atomically replaces matched one-sided regular files with paired identical-file rows.
    /// Match order does not affect result order; each pair replaces its earlier source row.
    public mutating func applyRenamedFileMatches(
        _ matches: [RenamedFileMatch]
    ) throws {
        guard !matches.isEmpty else { return }

        let orderedMatches = matches.sorted { left, right in
            if left.left.relativePath != right.left.relativePath {
                return left.left.relativePath.utf8.lexicographicallyPrecedes(
                    right.left.relativePath.utf8
                )
            }
            return left.right.relativePath.utf8.lexicographicallyPrecedes(
                right.right.relativePath.utf8
            )
        }
        var matchedLeftPaths: Set<String> = []
        var matchedRightPaths: Set<String> = []
        for match in orderedMatches {
            guard matchedLeftPaths.insert(match.left.relativePath).inserted else {
                throw DirectoryRenameApplicationError.duplicateMatch(
                    side: .left,
                    relativePath: match.left.relativePath
                )
            }
            guard matchedRightPaths.insert(match.right.relativePath).inserted else {
                throw DirectoryRenameApplicationError.duplicateMatch(
                    side: .right,
                    relativePath: match.right.relativePath
                )
            }
        }

        var leftIndicesByPath: [String: [Int]] = [:]
        var rightIndicesByPath: [String: [Int]] = [:]
        for (index, result) in results.enumerated() {
            if let path = result.left?.relativePath, matchedLeftPaths.contains(path) {
                leftIndicesByPath[path, default: []].append(index)
            }
            if let path = result.right?.relativePath, matchedRightPaths.contains(path) {
                rightIndicesByPath[path, default: []].append(index)
            }
        }

        var removedIndices: Set<Int> = []
        var replacementsByIndex: [Int: DirectoryResult] = [:]
        for match in orderedMatches {
            let leftPath = match.left.relativePath
            let rightPath = match.right.relativePath
            let leftIndices = leftIndicesByPath[leftPath] ?? []
            let rightIndices = rightIndicesByPath[rightPath] ?? []
            guard leftIndices.count <= 1 else {
                throw DirectoryRenameApplicationError.pathCollision(
                    side: .left,
                    relativePath: leftPath
                )
            }
            guard rightIndices.count <= 1 else {
                throw DirectoryRenameApplicationError.pathCollision(
                    side: .right,
                    relativePath: rightPath
                )
            }
            guard let leftIndex = leftIndices.first,
                let left = results[leftIndex].left,
                results[leftIndex].status == .leftOnly,
                results[leftIndex].right == nil,
                left.kind == .file,
                left.byteCount == match.left.size
            else {
                throw DirectoryRenameApplicationError.staleMatch(
                    side: .left,
                    relativePath: leftPath
                )
            }
            guard let rightIndex = rightIndices.first,
                let right = results[rightIndex].right,
                results[rightIndex].status == .rightOnly,
                results[rightIndex].left == nil,
                right.kind == .file,
                right.byteCount == match.right.size
            else {
                throw DirectoryRenameApplicationError.staleMatch(
                    side: .right,
                    relativePath: rightPath
                )
            }

            let replacementIndex = min(leftIndex, rightIndex)
            removedIndices.insert(leftIndex)
            removedIndices.insert(rightIndex)
            replacementsByIndex[replacementIndex] = DirectoryResult(
                left: left,
                right: right,
                status: .identical
            )
        }

        var updatedResults: [DirectoryResult] = []
        updatedResults.reserveCapacity(results.count - matches.count)
        for (index, result) in results.enumerated() {
            if let replacement = replacementsByIndex[index] {
                updatedResults.append(replacement)
            } else if !removedIndices.contains(index) {
                updatedResults.append(result)
            }
        }
        replaceResults(updatedResults)
    }

    public mutating func setSelection(_ ids: Set<DirectoryResult.ID>) {
        selectedIDs = ids.intersection(Set(results.map(\.id)))
    }

    public mutating func select(_ id: DirectoryResult.ID, extendingSelection: Bool = false) {
        if !extendingSelection {
            selectedIDs.removeAll(keepingCapacity: true)
        }
        guard results.contains(where: { $0.id == id }) else { return }
        selectedIDs.insert(id)
    }

    public mutating func toggleSelection(_ id: DirectoryResult.ID) {
        guard results.contains(where: { $0.id == id }) else { return }
        if selectedIDs.remove(id) == nil {
            selectedIDs.insert(id)
        }
    }

    public mutating func selectAllVisible(replacingSelection: Bool = true) {
        if replacingSelection {
            selectedIDs.removeAll(keepingCapacity: true)
        }
        selectedIDs.formUnion(visibleResults.map(\.id))
    }

    public mutating func clearSelection() {
        selectedIDs.removeAll(keepingCapacity: true)
    }

    public func result(withID id: DirectoryResult.ID) -> DirectoryResult? {
        results.first { $0.id == id }
    }

    public func openableFilePair(for id: DirectoryResult.ID) -> DirectoryFilePair? {
        guard let result = result(withID: id) else { return nil }
        return rootDescriptorStorage?.openableFilePair(for: result)
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.leftRoot == right.leftRoot
            && left.rightRoot == right.rightRoot
            && left.results == right.results
            && left.filter == right.filter
            && left.sortDescriptors == right.sortDescriptors
            && left.selectedIDs == right.selectedIDs
            && left.rootDescriptorStorage?.identity == right.rootDescriptorStorage?.identity
    }

    private enum Comparison: Equatable {
        case before
        case same
        case after
    }

    private enum OneSidedPath {
        case left(String)
        case right(String)
    }

    private static func oneSidedPath(of result: DirectoryResult) -> OneSidedPath? {
        switch (result.left?.relativePath, result.right?.relativePath) {
        case (let path?, nil):
            .left(path)
        case (nil, let path?):
            .right(path)
        default:
            nil
        }
    }

    private static func compare(
        _ left: DirectoryResult,
        _ right: DirectoryResult,
        by key: DirectoryResultSortKey
    ) -> Comparison {
        switch key {
        case .path:
            compare(left.relativePath, right.relativePath)
        case .status:
            compare(left.status.rawValue, right.status.rawValue)
        case .kind:
            compare(left.kind?.rawValue, right.kind?.rawValue)
        case .leftSize:
            compare(left.left?.byteCount, right.left?.byteCount)
        case .rightSize:
            compare(left.right?.byteCount, right.right?.byteCount)
        case .leftModificationDate:
            compareDates(left.left?.modificationDate, right.left?.modificationDate)
        case .rightModificationDate:
            compareDates(left.right?.modificationDate, right.right?.modificationDate)
        }
    }

    private static func hasUniqueIDs(_ results: [DirectoryResult]) -> Bool {
        Set(results.map(\.id)).count == results.count
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

    private static func compare(_ left: String, _ right: String) -> Comparison {
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
}

private final class DirectoryRootDescriptorStorage: @unchecked Sendable {
    private let left: Int32
    private let right: Int32
    let identity: DirectoryRootPairIdentity

    init?(leftRoot: URL, rightRoot: URL) {
        guard let left = openPinnedRoot(leftRoot) else { return nil }
        guard let right = openPinnedRoot(rightRoot) else {
            Darwin.close(left)
            return nil
        }
        guard let leftIdentity = descriptorIdentity(left),
            let rightIdentity = descriptorIdentity(right)
        else {
            Darwin.close(left)
            Darwin.close(right)
            return nil
        }
        self.left = left
        self.right = right
        identity = DirectoryRootPairIdentity(left: leftIdentity, right: rightIdentity)
    }

    func openableFilePair(for result: DirectoryResult) -> DirectoryFilePair? {
        guard result.isOpenableFilePair,
            let leftPath = result.left?.relativePath,
            let rightPath = result.right?.relativePath,
            let leftDescriptor = openPinnedDescendantFile(
                rootDescriptor: left,
                relativePath: leftPath,
                side: .left
            )
        else {
            return nil
        }
        guard
            let rightDescriptor = openPinnedDescendantFile(
                rootDescriptor: right,
                relativePath: rightPath,
                side: .right
            )
        else {
            Darwin.close(leftDescriptor)
            return nil
        }
        return DirectoryFilePair(
            leftDescriptor: leftDescriptor,
            rightDescriptor: rightDescriptor
        )
    }

    deinit {
        Darwin.close(left)
        Darwin.close(right)
    }
}

private struct DirectoryRootPairIdentity: Equatable, Sendable {
    let left: DirectoryRootIdentity
    let right: DirectoryRootIdentity
}

private struct DirectoryRootIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t

    init(device: dev_t, inode: ino_t) {
        self.device = device
        self.inode = inode
    }

    init(_ information: stat) {
        self.init(device: information.st_dev, inode: information.st_ino)
    }
}

private func descriptorIdentity(_ descriptor: Int32) -> DirectoryRootIdentity? {
    var information = stat()
    guard Darwin.fstat(descriptor, &information) == 0 else { return nil }
    return DirectoryRootIdentity(information)
}

private func openPinnedRoot(_ root: URL) -> Int32? {
    guard root.isFileURL,
        root.path.hasPrefix("/"),
        root.host == nil || root.host == "localhost",
        !root.path.contains("\0")
    else {
        return nil
    }
    let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    return descriptor >= 0 ? descriptor : nil
}

private func openPinnedDescendantFile(
    rootDescriptor: Int32,
    relativePath: String,
    side: DirectoryFilePair.OpenSide
) -> Int32? {
    guard !relativePath.isEmpty,
        !relativePath.hasPrefix("/"),
        !relativePath.contains("\0")
    else {
        return nil
    }
    let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
        return nil
    }

    var descriptor = Darwin.fcntl(rootDescriptor, F_DUPFD_CLOEXEC, 0)
    guard descriptor >= 0 else { return nil }

    for component in components.dropLast().map(String.init) {
        let next = component.withCString {
            Darwin.openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard next >= 0 else {
            Darwin.close(descriptor)
            return nil
        }
        Darwin.close(descriptor)
        descriptor = next
        DirectoryFilePair.openObserver?(
            .openedIntermediate(
                side: side,
                relativePath: relativePath,
                component: component
            )
        )
    }

    DirectoryFilePair.openObserver?(.beforeLeaf(side: side, relativePath: relativePath))
    let fileDescriptor = components.last.map(String.init)!.withCString {
        Darwin.openat(descriptor, $0, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
    }
    Darwin.close(descriptor)
    guard fileDescriptor >= 0 else { return nil }

    var information = stat()
    guard Darwin.fstat(fileDescriptor, &information) == 0,
        information.st_mode & S_IFMT == S_IFREG
    else {
        Darwin.close(fileDescriptor)
        return nil
    }
    return fileDescriptor
}

private func openPinnedRegularFile(_ url: URL) throws -> Int32 {
    guard url.isFileURL,
        url.path.hasPrefix("/"),
        url.host == nil || url.host == "localhost",
        !url.path.contains("\0")
    else {
        throw DirectoryFileReaderError.posix(EINVAL)
    }
    let descriptor = Darwin.open(
        url.path,
        O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
    )
    guard descriptor >= 0 else { throw DirectoryFileReaderError.posix(errno) }

    var information = stat()
    guard Darwin.fstat(descriptor, &information) == 0 else {
        let error = errno
        Darwin.close(descriptor)
        throw DirectoryFileReaderError.posix(error)
    }
    guard information.st_mode & S_IFMT == S_IFREG else {
        Darwin.close(descriptor)
        throw DirectoryFileReaderError.posix(EINVAL)
    }
    return descriptor
}
