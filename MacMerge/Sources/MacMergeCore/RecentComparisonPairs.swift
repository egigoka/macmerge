import Foundation

public enum RecentComparisonPairError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            "Invalid recent comparison URL: \(value)."
        }
    }
}

/// Ordered filesystem inputs for one reopenable comparison.
///
/// Project documents need their own recent-project list. Scratchpads have no
/// stable filesystem identity and must not be added to this history.
public struct RecentComparisonPair: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case file
        case folder
    }

    public let left: URL
    public let right: URL
    public let kind: Kind

    public init(left: URL, right: URL, kind: Kind) throws {
        self.left = try Self.canonicalURL(left, kind: kind)
        self.right = try Self.canonicalURL(right, kind: kind)
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case left
        case right
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let left = try container.decode(URL.self, forKey: .left)
        let right = try container.decode(URL.self, forKey: .right)
        let kind = try container.decode(Kind.self, forKey: .kind)

        do {
            try self.init(left: left, right: right, kind: kind)
        } catch let error as RecentComparisonPairError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.localizedDescription)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(left, forKey: .left)
        try container.encode(right, forKey: .right)
        try container.encode(kind, forKey: .kind)
    }

    private static func canonicalURL(_ url: URL, kind: Kind) throws -> URL {
        guard url.isFileURL,
            url.baseURL == nil,
            url.query == nil,
            url.fragment == nil,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "file",
            components.host?.isEmpty != false
                || components.host?.caseInsensitiveCompare("localhost") == .orderedSame,
            components.user == nil,
            components.password == nil,
            components.port == nil,
            url.path.hasPrefix("/"),
            !url.path(percentEncoded: false).utf8.contains(0)
        else {
            throw RecentComparisonPairError.invalidURL(url.absoluteString)
        }

        return URL(
            fileURLWithPath: url.standardizedFileURL.path,
            isDirectory: kind == .folder
        ).standardizedFileURL
    }
}

/// Bounded most-recently-used history. `pairs[0]` is always most recent.
public struct RecentComparisonPairs: Codable, Equatable, Sendable, RandomAccessCollection {
    public static let defaultCapacity = 20
    public static let maximumCapacity = 1_000

    public typealias Index = Int

    public let capacity: Int
    public private(set) var pairs: [RecentComparisonPair]

    public var startIndex: Int { pairs.startIndex }
    public var endIndex: Int { pairs.endIndex }

    public subscript(position: Int) -> RecentComparisonPair {
        pairs[position]
    }

    public init(capacity: Int = defaultCapacity) {
        precondition(
            capacity > 0 && capacity <= Self.maximumCapacity,
            "Recent comparison capacity must be between 1 and \(Self.maximumCapacity)"
        )
        self.capacity = capacity
        pairs = []
    }

    public init(_ pairs: [RecentComparisonPair], capacity: Int = defaultCapacity) {
        precondition(
            capacity > 0 && capacity <= Self.maximumCapacity,
            "Recent comparison capacity must be between 1 and \(Self.maximumCapacity)"
        )
        self.capacity = capacity
        self.pairs = Self.normalized(pairs, capacity: capacity)
    }

    /// Adds or promotes a pair while preserving its left/right order.
    @discardableResult
    public mutating func record(_ pair: RecentComparisonPair) -> Bool {
        guard pairs.first != pair else { return false }

        pairs.removeAll { $0 == pair }
        pairs.insert(pair, at: 0)
        if pairs.count > capacity {
            pairs.removeLast(pairs.count - capacity)
        }
        return true
    }

    @discardableResult
    public mutating func record(left: URL, right: URL, kind: RecentComparisonPair.Kind) throws -> Bool {
        try record(RecentComparisonPair(left: left, right: right, kind: kind))
    }

    @discardableResult
    public mutating func remove(_ pair: RecentComparisonPair) -> Bool {
        guard let index = pairs.firstIndex(of: pair) else { return false }
        pairs.remove(at: index)
        return true
    }

    @discardableResult
    public mutating func remove(
        left: URL,
        right: URL,
        kind: RecentComparisonPair.Kind
    ) throws -> Bool {
        try remove(RecentComparisonPair(left: left, right: right, kind: kind))
    }

    public mutating func removeAll(keepingCapacity: Bool = false) {
        pairs.removeAll(keepingCapacity: keepingCapacity)
    }

    private enum CodingKeys: String, CodingKey {
        case capacity
        case pairs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let capacity = try container.decode(Int.self, forKey: .capacity)
        guard capacity > 0 && capacity <= Self.maximumCapacity else {
            throw DecodingError.dataCorruptedError(
                forKey: .capacity,
                in: container,
                debugDescription:
                    "Recent comparison capacity must be between 1 and \(Self.maximumCapacity)."
            )
        }

        var pairsContainer = try container.nestedUnkeyedContainer(forKey: .pairs)
        if let count = pairsContainer.count, count > Self.maximumCapacity {
            throw DecodingError.dataCorruptedError(
                forKey: .pairs,
                in: container,
                debugDescription:
                    "Recent comparison history cannot exceed \(Self.maximumCapacity) entries."
            )
        }

        var seen: Set<RecentComparisonPair> = []
        var pairs: [RecentComparisonPair] = []
        pairs.reserveCapacity(Swift.min(pairsContainer.count ?? capacity, capacity))
        var decodedCount = 0

        while !pairsContainer.isAtEnd {
            guard decodedCount < Self.maximumCapacity else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: pairsContainer.codingPath,
                        debugDescription:
                            "Recent comparison history cannot exceed \(Self.maximumCapacity) entries."
                    )
                )
            }

            let pair = try pairsContainer.decode(RecentComparisonPair.self)
            decodedCount += 1
            if pairs.count < capacity, seen.insert(pair).inserted {
                pairs.append(pair)
            }
        }

        self.capacity = capacity
        self.pairs = pairs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(pairs, forKey: .pairs)
    }

    private static func normalized(
        _ pairs: [RecentComparisonPair],
        capacity: Int
    ) -> [RecentComparisonPair] {
        var seen: Set<RecentComparisonPair> = []
        var result: [RecentComparisonPair] = []
        result.reserveCapacity(Swift.min(pairs.count, capacity))

        for pair in pairs where seen.insert(pair).inserted {
            result.append(pair)
            if result.count == capacity { break }
        }
        return result
    }
}
