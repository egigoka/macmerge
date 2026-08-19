import Foundation

struct SecurityScopedBookmarkStore: @unchecked Sendable {
    struct Resolution {
        let url: URL
        let isStale: Bool
    }

    typealias BookmarkCreator = (URL) throws -> Data
    typealias BookmarkResolver = (Data) throws -> Resolution

    private static let defaultsKey = "securityScopedBookmarks.v1"
    private static let lock = NSLock()

    private let userDefaults: UserDefaults
    private let createBookmark: BookmarkCreator
    private let resolveBookmark: BookmarkResolver

    init(
        userDefaults: UserDefaults,
        createBookmark: @escaping BookmarkCreator = Self.createSecurityScopedBookmark,
        resolveBookmark: @escaping BookmarkResolver = Self.resolveSecurityScopedBookmark
    ) {
        self.userDefaults = userDefaults
        self.createBookmark = createBookmark
        self.resolveBookmark = resolveBookmark
    }

    func resolveAccess(to url: URL) -> URL {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let key = Self.key(for: url)
        var bookmarks = loadBookmarks()
        guard let bookmark = bookmarks[key],
            let resolution = try? resolveBookmark(bookmark)
        else { return url }
        let resolvedKey = Self.key(for: resolution.url)
        if resolvedKey != key || resolution.isStale {
            if resolution.isStale {
                let accessing = resolution.url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { resolution.url.stopAccessingSecurityScopedResource() }
                }
                guard let refreshedBookmark = try? createBookmark(resolution.url) else {
                    return resolution.url
                }
                bookmarks[resolvedKey] = refreshedBookmark
            } else {
                bookmarks[resolvedKey] = bookmark
            }
            saveBookmarks(bookmarks)
        }
        return resolution.url
    }

    func persistAccess(to url: URL) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var bookmarks = loadBookmarks()
        let key = Self.key(for: url)
        do {
            bookmarks[key] = try createBookmark(url)
        } catch {
            bookmarks.removeValue(forKey: key)
            saveBookmarks(bookmarks)
            throw error
        }
        saveBookmarks(bookmarks)
    }

    func hasPersistedAccess(to url: URL) -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let bookmark = loadBookmarks()[Self.key(for: url)] else { return false }
        return (try? resolveBookmark(bookmark)) != nil
    }

    private func loadBookmarks() -> [String: Data] {
        guard let data = userDefaults.data(forKey: Self.defaultsKey),
            let bookmarks = try? PropertyListDecoder().decode([String: Data].self, from: data)
        else {
            return [:]
        }
        return bookmarks
    }

    private func saveBookmarks(_ bookmarks: [String: Data]) {
        guard !bookmarks.isEmpty else {
            userDefaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        guard let data = try? PropertyListEncoder().encode(bookmarks) else { return }
        userDefaults.set(data, forKey: Self.defaultsKey)
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
    }

    private static func createSecurityScopedBookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolveSecurityScopedBookmark(_ data: Data) throws -> Resolution {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return Resolution(url: url, isStale: isStale)
    }
}
