import Foundation

public enum ConfigurationReportSandboxState: String, CaseIterable, Equatable, Sendable {
    case enabled
    case disabled
    case unknown

    public init(isSandboxed: Bool?) {
        switch isSandboxed {
        case true: self = .enabled
        case false: self = .disabled
        case nil: self = .unknown
        }
    }
}

public struct ConfigurationReportRecord: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    public init(name: String, value: Int) {
        self.init(name: name, value: String(value))
    }
}

public struct ConfigurationReportBounds: Equatable, Sendable {
    public static let `default` = ConfigurationReportBounds()

    public let maximumItemCount: Int
    public let maximumInputBytes: Int
    public let maximumOutputBytes: Int

    public init(
        maximumItemCount: Int = 4_096,
        maximumInputBytes: Int = 4 * 1_024 * 1_024,
        maximumOutputBytes: Int = 4 * 1_024 * 1_024
    ) {
        self.maximumItemCount = maximumItemCount
        self.maximumInputBytes = maximumInputBytes
        self.maximumOutputBytes = maximumOutputBytes
    }
}

public enum ConfigurationReportError: Error, LocalizedError, Equatable, Sendable {
    case invalidMaximumItemCount(Int)
    case invalidMaximumInputBytes(Int)
    case invalidMaximumOutputBytes(Int)
    case tooManyItems(maximum: Int)
    case inputTooLarge(maximumBytes: Int)
    case outputTooLarge(maximumBytes: Int)
    case invalidRedactionRoot(index: Int)
    case invalidUsername(index: Int)
    case redactionDecodingCycle
    case redactionDecodingTooDeep(maximumPasses: Int)
    case redactionDecodedValueTooLarge(maximumBytes: Int)
    case redactionDecodingWorkLimitExceeded(maximumWork: Int)
    case redactionPatternTooLarge(maximumBytes: Int)
    case redactionPatternsTooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidMaximumItemCount(let value):
            "Configuration-report item limit must be nonnegative, not \(value)."
        case .invalidMaximumInputBytes(let value):
            "Configuration-report input limit must be positive, not \(value)."
        case .invalidMaximumOutputBytes(let value):
            "Configuration-report output limit must be positive, not \(value)."
        case .tooManyItems(let maximum):
            "Configuration report exceeds the \(maximum)-item limit."
        case .inputTooLarge(let maximumBytes):
            "Configuration-report input exceeds the \(maximumBytes)-byte UTF-8 limit."
        case .outputTooLarge(let maximumBytes):
            "Configuration-report output exceeds the \(maximumBytes)-byte UTF-8 limit."
        case .invalidRedactionRoot(let index):
            "Redaction root \(index + 1) must contain a non-separator and no control characters."
        case .invalidUsername(let index):
            "Redaction username \(index + 1) must be nonempty and contain no control characters."
        case .redactionDecodingCycle:
            "Configuration-report redaction decoding entered a cycle."
        case .redactionDecodingTooDeep(let maximumPasses):
            "Configuration-report redaction exceeds the \(maximumPasses)-pass decoding limit."
        case .redactionDecodedValueTooLarge(let maximumBytes):
            "Configuration-report redaction decoding exceeds the \(maximumBytes)-byte limit."
        case .redactionDecodingWorkLimitExceeded(let maximumWork):
            "Configuration-report redaction decoding exceeds the \(maximumWork)-unit work limit."
        case .redactionPatternTooLarge(let maximumBytes):
            "A configuration-report redaction pattern exceeds the \(maximumBytes)-byte limit."
        case .redactionPatternsTooLarge(let maximumBytes):
            "Configuration-report redaction patterns exceed the \(maximumBytes)-byte limit."
        }
    }
}

public struct ConfigurationReport: Equatable, Sendable {
    private static let maximumRedactionPatternBytes = 4_096
    private static let maximumRedactionPatternTotalBytes = 64 * 1_024

    public let appName: String
    public let appVersion: String
    public let buildVersion: String
    public let operatingSystem: String
    public let architecture: String
    public let localeIdentifier: String
    public let sandboxState: ConfigurationReportSandboxState
    public let comparisonLimits: [ConfigurationReportRecord]
    public let features: [ConfigurationReportRecord]
    public let redactionRoots: [String]
    public let usernames: [String]

    public init(
        appName: String,
        appVersion: String,
        buildVersion: String,
        operatingSystem: String,
        architecture: String,
        localeIdentifier: String,
        sandboxState: ConfigurationReportSandboxState,
        comparisonLimits: [ConfigurationReportRecord] = [],
        features: [ConfigurationReportRecord] = [],
        redactionRoots: [String] = [],
        usernames: [String] = []
    ) {
        self.appName = appName
        self.appVersion = appVersion
        self.buildVersion = buildVersion
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.localeIdentifier = localeIdentifier
        self.sandboxState = sandboxState
        self.comparisonLimits = comparisonLimits
        self.features = features
        self.redactionRoots = redactionRoots
        self.usernames = usernames
    }

    public func build(bounds: ConfigurationReportBounds = .default) throws -> String {
        try Task.checkCancellation()
        try validate(bounds: bounds)

        let redactor = try ConfigurationReportRedactor(
            roots: redactionRoots,
            usernames: usernames,
            maximumPatternBytes: Self.maximumRedactionPatternBytes,
            maximumTotalPatternBytes: Self.maximumRedactionPatternTotalBytes
        )
        let clean: (String) throws -> String = { value in
            try Task.checkCancellation()
            return try Self.escapingUnsafeScalars(in: redactor.redact(value))
        }
        let orderedLimits = try Self.stablyOrdered(
            try comparisonLimits.map {
                ConfigurationReportRecord(name: try clean($0.name), value: try clean($0.value))
            }
        )
        let orderedFeatures = try Self.stablyOrdered(
            try features.map {
                ConfigurationReportRecord(name: try clean($0.name), value: try clean($0.value))
            }
        )

        var output = ConfigurationReportOutput(maximumBytes: bounds.maximumOutputBytes)
        try output.append(clean(appName))
        try output.append(" Configuration Report\n\nApplication\n")
        try output.append("Name: ")
        try output.append(clean(appName))
        try output.append("\nVersion: ")
        try output.append(clean(appVersion))
        try output.append("\nBuild: ")
        try output.append(clean(buildVersion))
        try output.append("\n\nSystem\nOperating System: ")
        try output.append(clean(operatingSystem))
        try output.append("\nArchitecture: ")
        try output.append(clean(architecture))
        try output.append("\nLocale: ")
        try output.append(clean(localeIdentifier))
        try output.append("\nSandbox: ")
        try output.append(sandboxState.rawValue)
        try output.append("\n\nComparison Limits\n")
        try Self.append(orderedLimits, to: &output)
        try output.append("\nFeatures\n")
        try Self.append(orderedFeatures, to: &output)

        try Task.checkCancellation()
        return output.value
    }

    public func data(bounds: ConfigurationReportBounds = .default) throws -> Data {
        let report = try build(bounds: bounds)
        try Task.checkCancellation()
        let data = Data(report.utf8)
        try Task.checkCancellation()
        return data
    }

    private func validate(bounds: ConfigurationReportBounds) throws {
        try Task.checkCancellation()
        guard bounds.maximumItemCount >= 0 else {
            throw ConfigurationReportError.invalidMaximumItemCount(bounds.maximumItemCount)
        }
        guard bounds.maximumInputBytes > 0 else {
            throw ConfigurationReportError.invalidMaximumInputBytes(bounds.maximumInputBytes)
        }
        guard bounds.maximumOutputBytes > 0 else {
            throw ConfigurationReportError.invalidMaximumOutputBytes(bounds.maximumOutputBytes)
        }

        var remainingItems = bounds.maximumItemCount
        for count in [
            comparisonLimits.count,
            features.count,
            redactionRoots.count,
            usernames.count
        ] {
            guard count <= remainingItems else {
                throw ConfigurationReportError.tooManyItems(maximum: bounds.maximumItemCount)
            }
            remainingItems -= count
        }

        var remainingBytes = bounds.maximumInputBytes
        func consume(_ value: String) throws {
            var consumedBytes = 0
            for (offset, _) in value.utf8.enumerated() {
                if offset.isMultiple(of: 4_096) { try Task.checkCancellation() }
                guard consumedBytes < remainingBytes else {
                    throw ConfigurationReportError.inputTooLarge(
                        maximumBytes: bounds.maximumInputBytes
                    )
                }
                consumedBytes += 1
            }
            remainingBytes -= consumedBytes
        }

        try consume(appName)
        try consume(appVersion)
        try consume(buildVersion)
        try consume(operatingSystem)
        try consume(architecture)
        try consume(localeIdentifier)
        for record in comparisonLimits {
            try consume(record.name)
            try consume(record.value)
        }
        for record in features {
            try consume(record.name)
            try consume(record.value)
        }
        for root in redactionRoots { try consume(root) }
        for username in usernames { try consume(username) }

        for (index, root) in redactionRoots.enumerated() {
            try Task.checkCancellation()
            guard !root.isEmpty else {
                throw ConfigurationReportError.invalidRedactionRoot(index: index)
            }
            if try Self.containsOnlyPathSeparators(root)
                || (try Self.containsControlCharacter(root))
            {
                throw ConfigurationReportError.invalidRedactionRoot(index: index)
            }
        }
        for (index, username) in usernames.enumerated() {
            try Task.checkCancellation()
            guard !username.isEmpty, try !Self.containsControlCharacter(username) else {
                throw ConfigurationReportError.invalidUsername(index: index)
            }
        }
    }

    private static func append(
        _ records: [ConfigurationReportRecord],
        to output: inout ConfigurationReportOutput
    ) throws {
        guard !records.isEmpty else {
            try output.append("(none)\n")
            return
        }
        for (index, record) in records.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            try output.append(record.name)
            try output.append(": ")
            try output.append(record.value)
            try output.append("\n")
        }
    }

    private static func stablyOrdered(
        _ records: [ConfigurationReportRecord]
    ) throws -> [ConfigurationReportRecord] {
        try Task.checkCancellation()
        var source = Array(records.enumerated())
        var width = 1
        while width < source.count {
            var destination = source
            var lowerBound = 0
            while lowerBound < source.count {
                try Task.checkCancellation()
                let middle = min(lowerBound + width, source.count)
                let upperBound = min(middle + width, source.count)
                var left = lowerBound
                var right = middle
                var destinationIndex = lowerBound
                while left < middle, right < upperBound {
                    if try recordPrecedes(source[right], source[left]) {
                        destination[destinationIndex] = source[right]
                        right += 1
                    } else {
                        destination[destinationIndex] = source[left]
                        left += 1
                    }
                    destinationIndex += 1
                }
                while left < middle {
                    destination[destinationIndex] = source[left]
                    left += 1
                    destinationIndex += 1
                }
                while right < upperBound {
                    destination[destinationIndex] = source[right]
                    right += 1
                    destinationIndex += 1
                }
                lowerBound = upperBound
            }
            source = destination
            width *= 2
        }
        try Task.checkCancellation()
        return source.map(\.element)
    }

    private static func recordPrecedes(
        _ left: (offset: Int, element: ConfigurationReportRecord),
        _ right: (offset: Int, element: ConfigurationReportRecord)
    ) throws -> Bool {
        let nameOrder = try compareUTF8(left.element.name, right.element.name)
        if nameOrder != 0 { return nameOrder < 0 }

        let valueOrder = try compareUTF8(left.element.value, right.element.value)
        if valueOrder != 0 { return valueOrder < 0 }
        return left.offset < right.offset
    }

    private static func compareUTF8(_ left: String, _ right: String) throws -> Int {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        var offset = 0
        while true {
            if offset.isMultiple(of: 4_096) { try Task.checkCancellation() }
            switch (leftIterator.next(), rightIterator.next()) {
            case (let leftByte?, let rightByte?):
                if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
            case (nil, nil):
                return 0
            case (nil, _?):
                return -1
            case (_?, nil):
                return 1
            }
            offset += 1
        }
    }

    fileprivate static func canonicalizedForRedaction(_ value: String) throws -> String {
        try ConfigurationReportCanonicalView(source: value).string
    }

    fileprivate static func filesystemAliasForRedaction(_ value: String) throws -> String {
        try Task.checkCancellation()
        let alias = value.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).precomposedStringWithCanonicalMapping
        try Task.checkCancellation()
        return alias
    }

    fileprivate static func hexadecimalValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }

    private static func escapingUnsafeScalars(in value: String) throws -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for (index, scalar) in value.unicodeScalars.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if isUnsafeReportScalar(scalar.value) {
                result.append("\\u{")
                result.append(String(scalar.value, radix: 16, uppercase: true))
                result.append("}")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func containsOnlyPathSeparators(_ value: String) throws -> Bool {
        for (index, scalar) in value.unicodeScalars.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if scalar.value != 0x2F, scalar.value != 0x5C { return false }
        }
        return true
    }

    fileprivate static func redactionBytes(_ value: String) throws -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        for (index, byte) in value.utf8.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            bytes.append(byte)
        }
        return bytes
    }

    static func redactionResultForTesting(
        _ value: String,
        roots: [String],
        usernames: [String],
        workObserver: ((Int) throws -> Void)? = nil
    ) throws -> (value: String, workCount: Int) {
        let redactor = try ConfigurationReportRedactor(
            roots: roots,
            usernames: usernames,
            maximumPatternBytes: maximumRedactionPatternBytes,
            maximumTotalPatternBytes: maximumRedactionPatternTotalBytes
        )
        return try redactor.redactMeasuringWork(value, workObserver: workObserver)
    }

    static func canonicalizedRedactionResultForTesting(
        _ value: String,
        maximumDecodedBytes: Int,
        maximumDecodingWork: Int,
        maximumDecodingPasses: Int
    ) throws -> String {
        try ConfigurationReportCanonicalView(
            source: value,
            maximumDecodedBytes: maximumDecodedBytes,
            maximumDecodingWork: maximumDecodingWork,
            maximumDecodingPasses: maximumDecodingPasses
        ).string
    }

    private static func containsControlCharacter(_ value: String) throws -> Bool {
        for (index, scalar) in value.unicodeScalars.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if isControlCharacter(scalar.value) { return true }
        }
        return false
    }

    private static func isControlCharacter(_ value: UInt32) -> Bool {
        value <= 0x1F || (0x7F...0x9F).contains(value)
    }

    private static func isUnsafeReportScalar(_ value: UInt32) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return true }
        return CharacterSet.controlCharacters.contains(scalar)
            || value == 0x2028
            || value == 0x2029
            || value == 0x061C
            || (0x200E...0x200F).contains(value)
            || (0x202A...0x202E).contains(value)
            || (0x2066...0x2069).contains(value)
    }
}

public typealias ConfigurationReportBuilder = ConfigurationReport

private struct ConfigurationReportRedactor {
    private enum PatternSource {
        case root(index: Int)
        case username(index: Int)
    }

    private enum Replacement: UInt8 {
        case user = 1
        case home = 2

        var bytes: [UInt8] {
            switch self {
            case .user: Array("<user>".utf8)
            case .home: Array("<home>".utf8)
            }
        }
    }

    private struct Node {
        var children: [UInt8: Int] = [:]
        var failure = 0
        var homeLength = 0
        var userLength = 0
    }

    private struct Pattern: Equatable {
        let bytes: [UInt8]
        let replacement: Replacement
    }

    private struct Matcher {
        let nodes: [Node]

        var isEmpty: Bool { nodes.count == 1 }

        init(patterns: [Pattern]) throws {
            var nodes = [Node()]
            for (patternIndex, pattern) in patterns.enumerated() {
                try Task.checkCancellation()
                var nodeIndex = 0
                for (offset, byte) in pattern.bytes.enumerated() {
                    if offset.isMultiple(of: 4_096) { try Task.checkCancellation() }
                    if let childIndex = nodes[nodeIndex].children[byte] {
                        nodeIndex = childIndex
                    } else {
                        let childIndex = nodes.count
                        nodes.append(Node())
                        nodes[nodeIndex].children[byte] = childIndex
                        nodeIndex = childIndex
                    }
                }
                switch pattern.replacement {
                case .home:
                    nodes[nodeIndex].homeLength = max(
                        nodes[nodeIndex].homeLength,
                        pattern.bytes.count
                    )
                case .user:
                    nodes[nodeIndex].userLength = max(
                        nodes[nodeIndex].userLength,
                        pattern.bytes.count
                    )
                }
                if patternIndex.isMultiple(of: 256) { try Task.checkCancellation() }
            }

            var queue: [Int] = []
            queue.reserveCapacity(nodes.count)
            for childIndex in nodes[0].children.values {
                queue.append(childIndex)
            }
            var queueIndex = 0
            while queueIndex < queue.count {
                if queueIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
                let nodeIndex = queue[queueIndex]
                queueIndex += 1
                for (byte, childIndex) in nodes[nodeIndex].children {
                    var failure = nodes[nodeIndex].failure
                    while failure != 0, nodes[failure].children[byte] == nil {
                        try Task.checkCancellation()
                        failure = nodes[failure].failure
                    }
                    if let failureChild = nodes[failure].children[byte],
                        failureChild != childIndex
                    {
                        failure = failureChild
                    }
                    nodes[childIndex].failure = failure
                    nodes[childIndex].homeLength = max(
                        nodes[childIndex].homeLength,
                        nodes[failure].homeLength
                    )
                    nodes[childIndex].userLength = max(
                        nodes[childIndex].userLength,
                        nodes[failure].userLength
                    )
                    queue.append(childIndex)
                }
            }
            self.nodes = nodes
        }

        func scan(
            _ input: [UInt8],
            workCount: inout Int?,
            workObserver: ((Int) throws -> Void)?,
            match: (_ start: Int, _ end: Int, _ replacement: Replacement) -> Void
        ) throws {
            guard nodes.count > 1 else { return }
            var nodeIndex = 0
            for (index, byte) in input.enumerated() {
                if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
                if let count = workCount {
                    workCount = count + 1
                    try workObserver?(count + 1)
                }
                while nodeIndex != 0, nodes[nodeIndex].children[byte] == nil {
                    try Task.checkCancellation()
                    if let count = workCount {
                        workCount = count + 1
                        try workObserver?(count + 1)
                    }
                    nodeIndex = nodes[nodeIndex].failure
                }
                nodeIndex = nodes[nodeIndex].children[byte] ?? 0
                let end = index + 1
                if nodes[nodeIndex].homeLength > 0 {
                    match(end - nodes[nodeIndex].homeLength, end, .home)
                }
                if nodes[nodeIndex].userLength > 0 {
                    match(end - nodes[nodeIndex].userLength, end, .user)
                }
            }
        }
    }

    private struct MatchRange {
        var start: Int32
        var end: Int32
        var replacement: Replacement

        init(start: Int, end: Int, replacement: Replacement) {
            self.start = Int32(start)
            self.end = Int32(end)
            self.replacement = replacement
        }

        var startOffset: Int { Int(start) }
        var endOffset: Int { Int(end) }
    }

    private let exactMatcher: Matcher
    private let aliasMatcher: Matcher
    private let matchersAreEquivalent: Bool

    init(
        roots: [String],
        usernames: [String],
        maximumPatternBytes: Int,
        maximumTotalPatternBytes: Int
    ) throws {
        try Task.checkCancellation()
        var exactPatterns: [Pattern] = []
        var aliasPatterns: [Pattern] = []
        var totalExactPatternBytes = 0
        var totalAliasPatternBytes = 0

        func preflight(_ source: String) throws {
            guard source.utf8.count <= maximumPatternBytes else {
                throw ConfigurationReportError.redactionPatternTooLarge(
                    maximumBytes: maximumPatternBytes
                )
            }
        }

        func appendCanonical(
            _ canonical: String,
            replacement: Replacement,
            patternSource: PatternSource
        ) throws {
            switch patternSource {
            case .root(let index):
                guard Self.isValidRoot(canonical) else {
                    throw ConfigurationReportError.invalidRedactionRoot(index: index)
                }
            case .username(let index):
                guard Self.isValidUsername(canonical) else {
                    throw ConfigurationReportError.invalidUsername(index: index)
                }
            }
            let canonicalByteCount = canonical.utf8.count
            guard canonicalByteCount <= maximumPatternBytes else {
                throw ConfigurationReportError.redactionPatternTooLarge(
                    maximumBytes: maximumPatternBytes
                )
            }
            guard
                canonicalByteCount
                    <= maximumTotalPatternBytes - totalExactPatternBytes
            else {
                throw ConfigurationReportError.redactionPatternsTooLarge(
                    maximumBytes: maximumTotalPatternBytes
                )
            }
            totalExactPatternBytes += canonicalByteCount

            let alias = try ConfigurationReport.filesystemAliasForRedaction(canonical)
            guard Self.isValid(alias, for: patternSource) else {
                throw Self.invalidPatternError(for: patternSource)
            }
            let aliasByteCount = alias.utf8.count
            guard aliasByteCount <= maximumPatternBytes else {
                throw ConfigurationReportError.redactionPatternTooLarge(
                    maximumBytes: maximumPatternBytes
                )
            }
            guard
                aliasByteCount
                    <= maximumTotalPatternBytes - totalAliasPatternBytes
            else {
                throw ConfigurationReportError.redactionPatternsTooLarge(
                    maximumBytes: maximumTotalPatternBytes
                )
            }
            totalAliasPatternBytes += aliasByteCount
            exactPatterns.append(
                Pattern(
                    bytes: try ConfigurationReport.redactionBytes(canonical),
                    replacement: replacement
                ))
            aliasPatterns.append(
                Pattern(
                    bytes: try ConfigurationReport.redactionBytes(alias),
                    replacement: replacement
                ))
        }

        for (index, root) in roots.enumerated() {
            try preflight(root)
            let variants = try Self.rootVariants(root)
            guard variants.allSatisfy(Self.isValidRoot) else {
                throw ConfigurationReportError.invalidRedactionRoot(index: index)
            }
            for variant in variants {
                try appendCanonical(
                    variant,
                    replacement: .home,
                    patternSource: .root(index: index)
                )
            }
        }
        for (index, username) in usernames.enumerated() {
            try preflight(username)
            try appendCanonical(
                ConfigurationReport.canonicalizedForRedaction(username),
                replacement: .user,
                patternSource: .username(index: index)
            )
        }

        matchersAreEquivalent = exactPatterns == aliasPatterns
        exactMatcher = try Matcher(patterns: exactPatterns)
        aliasMatcher = try Matcher(patterns: aliasPatterns)
    }

    func redact(_ value: String) throws -> String {
        try redact(value, measureWork: false, workObserver: nil).value
    }

    func redactMeasuringWork(
        _ value: String,
        workObserver: ((Int) throws -> Void)?
    ) throws -> (value: String, workCount: Int) {
        let result = try redact(value, measureWork: true, workObserver: workObserver)
        return (result.value, result.workCount ?? 0)
    }

    private func redact(
        _ value: String,
        measureWork: Bool,
        workObserver: ((Int) throws -> Void)?
    ) throws -> (value: String, workCount: Int?) {
        try Task.checkCancellation()
        guard !exactMatcher.isEmpty || !aliasMatcher.isEmpty else {
            return (value, measureWork ? 0 : nil)
        }
        var workCount: Int? = measureWork ? 0 : nil
        let canonicalView = try ConfigurationReportCanonicalView(source: value)
        let canonical = canonicalView.string
        let input = try ConfigurationReport.redactionBytes(value)

        func record(
            in ranges: inout [MatchRange],
            start: Int,
            end: Int,
            replacement: Replacement
        ) {
            guard start < end else { return }
            var combined = MatchRange(start: start, end: end, replacement: replacement)
            while let last = ranges.last, combined.startOffset <= last.endOffset {
                ranges.removeLast()
                combined.start = min(combined.start, last.start)
                combined.end = max(combined.end, last.end)
                if last.replacement.rawValue > combined.replacement.rawValue {
                    combined.replacement = last.replacement
                }
            }
            ranges.append(combined)
        }

        var exactRanges: [MatchRange] = []
        try exactMatcher.scan(
            canonicalView.bytes,
            workCount: &workCount,
            workObserver: workObserver
        ) {
            start, end, replacement in
            guard start < end else { return }
            record(
                in: &exactRanges,
                start: canonicalView.sourceRanges[start].lowerBound,
                end: canonicalView.sourceRanges[end - 1].upperBound,
                replacement: replacement
            )
        }

        let aliasView = try ConfigurationReportRedactionView(source: canonical)
        let aliasDuplicatesExact =
            matchersAreEquivalent
            && aliasView.bytes.elementsEqual(canonicalView.bytes)
        var aliasRanges: [MatchRange] = []
        try aliasMatcher.scan(
            aliasView.bytes,
            workCount: &workCount,
            workObserver: workObserver
        ) {
            start, end, replacement in
            guard !aliasDuplicatesExact else { return }
            guard start < end else { return }
            let canonicalStart = aliasView.sourceRanges[start].lowerBound
            let canonicalEnd = aliasView.sourceRanges[end - 1].upperBound
            guard canonicalStart < canonicalEnd else { return }
            record(
                in: &aliasRanges,
                start: canonicalView.sourceRanges[canonicalStart].lowerBound,
                end: canonicalView.sourceRanges[canonicalEnd - 1].upperBound,
                replacement: replacement
            )
        }

        if aliasRanges.isEmpty {
            return try replacing(merged: exactRanges, in: input, value: value, workCount: workCount)
        }
        if exactRanges.isEmpty {
            return try replacing(merged: aliasRanges, in: input, value: value, workCount: workCount)
        }

        var merged: [MatchRange] = []
        merged.reserveCapacity(max(exactRanges.count, aliasRanges.count))
        var exactIndex = 0
        var aliasIndex = 0
        while exactIndex < exactRanges.count || aliasIndex < aliasRanges.count {
            let range: MatchRange
            if aliasIndex >= aliasRanges.count
                || (exactIndex < exactRanges.count
                    && exactRanges[exactIndex].startOffset
                        <= aliasRanges[aliasIndex].startOffset)
            {
                range = exactRanges[exactIndex]
                exactIndex += 1
            } else {
                range = aliasRanges[aliasIndex]
                aliasIndex += 1
            }
            if (exactIndex + aliasIndex).isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            record(
                in: &merged,
                start: range.startOffset,
                end: range.endOffset,
                replacement: range.replacement
            )
        }
        return try replacing(merged: merged, in: input, value: value, workCount: workCount)
    }

    private func replacing(
        merged: [MatchRange],
        in input: [UInt8],
        value: String,
        workCount: Int?
    ) throws -> (value: String, workCount: Int?) {
        guard !merged.isEmpty else { return (value, workCount) }
        var result: [UInt8] = []
        result.reserveCapacity(input.count)
        var cursor = 0
        for (index, range) in merged.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            result.append(contentsOf: input[cursor..<range.startOffset])
            result.append(contentsOf: range.replacement.bytes)
            cursor = range.endOffset
        }
        result.append(contentsOf: input[cursor...])
        try Task.checkCancellation()
        return (String(decoding: result, as: UTF8.self), workCount)
    }

    private static func rootVariants(_ root: String) throws -> [String] {
        let canonicalRoot = try ConfigurationReport.canonicalizedForRedaction(root)
        var sources = [canonicalRoot]
        if let path = try canonicalFileURLPath(root) {
            sources.append(path)
            sources.append(URL(fileURLWithPath: path, isDirectory: false).absoluteString)
        } else if canonicalRoot.hasPrefix("/") {
            let url = URL(fileURLWithPath: canonicalRoot, isDirectory: false)
            sources.append(url.absoluteString)
            sources.append(url.path(percentEncoded: true))
        }

        var variants: [String] = []
        for source in sources {
            try Task.checkCancellation()
            let canonical = try ConfigurationReport.canonicalizedForRedaction(source)
            guard !variants.contains(where: { $0.utf8.elementsEqual(canonical.utf8) }) else {
                continue
            }
            variants.append(canonical)
        }
        return variants
    }

    private static func canonicalFileURLPath(_ value: String) throws -> String? {
        var candidate = value
        for _ in 0...8 {
            if let path = literalFileURLPath(candidate) {
                return try ConfigurationReport.canonicalizedForRedaction(path)
            }
            let decoded = try percentDecodedOnce(candidate)
            guard !decoded.utf8.elementsEqual(candidate.utf8) else { return nil }
            candidate = decoded
        }
        return nil
    }

    private static func literalFileURLPath(_ value: String) -> String? {
        guard value.utf8.count >= 6, value.prefix(5).lowercased() == "file:" else {
            return nil
        }

        let schemeEnd = value.index(value.startIndex, offsetBy: 5)
        let remainder = value[schemeEnd...]
        let pathStart: String.Index
        if remainder.hasPrefix("//") {
            let authorityStart = value.index(schemeEnd, offsetBy: 2)
            let authorityEnd =
                value[authorityStart...].firstIndex {
                    $0 == "?" || $0 == "#"
                } ?? value.endIndex
            guard let start = value[authorityStart..<authorityEnd].firstIndex(of: "/") else {
                return nil
            }
            pathStart = start
        } else {
            guard remainder.first == "/" else { return nil }
            pathStart = schemeEnd
        }

        let pathEnd =
            value[pathStart...].firstIndex { $0 == "?" || $0 == "#" }
            ?? value.endIndex
        return String(value[pathStart..<pathEnd])
    }

    private static func percentDecodedOnce(_ value: String) throws -> String {
        let bytes = try ConfigurationReport.redactionBytes(value)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if bytes[index] == 0x25,
                index + 2 < bytes.count,
                let high = ConfigurationReport.hexadecimalValue(bytes[index + 1]),
                let low = ConfigurationReport.hexadecimalValue(bytes[index + 2])
            {
                output.append(high << 4 | low)
                index += 3
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func isValid(_ value: String, for source: PatternSource) -> Bool {
        switch source {
        case .root:
            isValidRoot(value)
        case .username:
            isValidUsername(value)
        }
    }

    private static func invalidPatternError(
        for source: PatternSource
    ) -> ConfigurationReportError {
        switch source {
        case .root(let index):
            .invalidRedactionRoot(index: index)
        case .username(let index):
            .invalidUsername(index: index)
        }
    }

    private static func isValidRoot(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        var containsNonSeparator = false
        for scalar in value.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { return false }
            if scalar.value != 0x2F, scalar.value != 0x5C {
                containsNonSeparator = true
            }
        }
        return containsNonSeparator
    }

    private static func isValidUsername(_ value: String) -> Bool {
        !value.isEmpty
            && !value.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }
}

private struct ConfigurationReportCanonicalView {
    private static let maximumDecodingPasses = 8
    private static let maximumDecodedBytes = 4 * 1_024 * 1_024
    private static let maximumDecodingWork = 256 * 1_024 * 1_024

    let string: String
    let bytes: [UInt8]
    let sourceRanges: [Range<Int>]

    init(
        source: String,
        maximumDecodedBytes: Int = Self.maximumDecodedBytes,
        maximumDecodingWork: Int = Self.maximumDecodingWork,
        maximumDecodingPasses: Int = Self.maximumDecodingPasses
    ) throws {
        var budget = ConfigurationReportCanonicalizationBudget(
            maximumBytes: maximumDecodedBytes,
            maximumWork: maximumDecodingWork
        )
        try budget.checkByteCount(source.utf8.count)
        var bytes = try ConfigurationReport.redactionBytes(source)
        var ranges = bytes.indices.map { $0..<$0 + 1 }
        (bytes, ranges) = try Self.normalized(
            bytes: bytes,
            sourceRanges: ranges,
            budget: &budget
        )
        try budget.consume(bytes.count)
        var seenStates: Set<[UInt8]> = [bytes]

        for pass in 0...maximumDecodingPasses {
            let decoded = try Self.percentDecoded(
                bytes: bytes,
                sourceRanges: ranges,
                budget: &budget
            )
            let normalized = try Self.normalized(
                bytes: decoded.bytes,
                sourceRanges: decoded.sourceRanges,
                budget: &budget
            )
            try budget.consume(bytes.count)
            guard !normalized.bytes.elementsEqual(bytes) else {
                self.bytes = bytes
                sourceRanges = ranges
                string = String(decoding: bytes, as: UTF8.self)
                return
            }
            guard pass < maximumDecodingPasses else {
                throw ConfigurationReportError.redactionDecodingTooDeep(
                    maximumPasses: maximumDecodingPasses
                )
            }
            try budget.consume(normalized.bytes.count)
            guard seenStates.insert(normalized.bytes).inserted else {
                throw ConfigurationReportError.redactionDecodingCycle
            }
            bytes = normalized.bytes
            ranges = normalized.sourceRanges
        }
        preconditionFailure("Redaction decoding loop must return or throw")
    }

    private static func percentDecoded(
        bytes: [UInt8],
        sourceRanges: [Range<Int>],
        budget: inout ConfigurationReportCanonicalizationBudget
    ) throws -> (bytes: [UInt8], sourceRanges: [Range<Int>]) {
        try budget.consume(bytes.count)
        var output: [UInt8] = []
        var outputRanges: [Range<Int>] = []
        output.reserveCapacity(bytes.count)
        outputRanges.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if bytes[index] == 0x25,
                index + 2 < bytes.count,
                let high = ConfigurationReport.hexadecimalValue(bytes[index + 1]),
                let low = ConfigurationReport.hexadecimalValue(bytes[index + 2])
            {
                output.append(high << 4 | low)
                outputRanges.append(
                    sourceRanges[index].lowerBound..<sourceRanges[index + 2].upperBound
                )
                index += 3
            } else {
                output.append(bytes[index])
                outputRanges.append(sourceRanges[index])
                index += 1
            }
        }
        try budget.checkByteCount(output.count)
        return (output, outputRanges)
    }

    private static func normalized(
        bytes: [UInt8],
        sourceRanges: [Range<Int>],
        budget: inout ConfigurationReportCanonicalizationBudget
    ) throws -> (bytes: [UInt8], sourceRanges: [Range<Int>]) {
        try budget.consume(bytes.count)
        let decoded = try decoded(bytes: bytes, sourceRanges: sourceRanges)
        try budget.checkByteCount(decoded.bytes.count)
        try budget.consume(decoded.bytes.count)
        var output: [UInt8] = []
        var outputRanges: [Range<Int>] = []
        output.reserveCapacity(decoded.bytes.count)
        outputRanges.reserveCapacity(decoded.bytes.count)
        let value = String(decoding: decoded.bytes, as: UTF8.self)
        var byteOffset = 0
        for (index, character) in value.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let characterByteCount = String(character).utf8.count
            let sourceRange = Range(
                uncheckedBounds: (
                    decoded.sourceRanges[byteOffset].lowerBound,
                    decoded.sourceRanges[byteOffset + characterByteCount - 1].upperBound
                )
            )
            let normalizedBytes = try ConfigurationReport.redactionBytes(
                String(character).precomposedStringWithCanonicalMapping
            )
            output.append(contentsOf: normalizedBytes)
            outputRanges.append(contentsOf: repeatElement(sourceRange, count: normalizedBytes.count))
            try budget.checkByteCount(output.count)
            byteOffset += characterByteCount
        }
        return (output, outputRanges)
    }

    private static func decoded(
        bytes: [UInt8],
        sourceRanges: [Range<Int>]
    ) throws -> (bytes: [UInt8], sourceRanges: [Range<Int>]) {
        var output: [UInt8] = []
        var outputRanges: [Range<Int>] = []
        output.reserveCapacity(bytes.count)
        outputRanges.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let expectedLength = utf8SequenceLength(at: index, in: bytes)
            let isValid = isValidUTF8Sequence(
                at: index,
                length: expectedLength,
                in: bytes
            )
            let length = isValid ? expectedLength : 1
            let end = index + length
            let sourceRange = Range(
                uncheckedBounds: (
                    sourceRanges[index].lowerBound,
                    sourceRanges[end - 1].upperBound
                )
            )
            let scalarBytes: [UInt8]
            if isValid {
                scalarBytes = Array(bytes[index..<end])
            } else {
                scalarBytes = [0xEF, 0xBF, 0xBD]
            }
            output.append(contentsOf: scalarBytes)
            outputRanges.append(contentsOf: repeatElement(sourceRange, count: scalarBytes.count))
            index = end
        }
        return (output, outputRanges)
    }

    private static func utf8SequenceLength(at index: Int, in bytes: [UInt8]) -> Int {
        let first = bytes[index]
        let expected: Int
        switch first {
        case 0x00...0x7F: expected = 1
        case 0xC2...0xDF: expected = 2
        case 0xE0...0xEF: expected = 3
        case 0xF0...0xF4: expected = 4
        default: return 1
        }
        return index + expected <= bytes.count ? expected : 1
    }

    private static func isValidUTF8Sequence(
        at index: Int,
        length: Int,
        in bytes: [UInt8]
    ) -> Bool {
        guard length > 1 else { return bytes[index] <= 0x7F }
        guard bytes[(index + 1)..<(index + length)].allSatisfy({ (0x80...0xBF).contains($0) })
        else { return false }
        let first = bytes[index]
        let second = bytes[index + 1]
        if first == 0xE0, second < 0xA0 { return false }
        if first == 0xED, second > 0x9F { return false }
        if first == 0xF0, second < 0x90 { return false }
        if first == 0xF4, second > 0x8F { return false }
        return true
    }
}

private struct ConfigurationReportCanonicalizationBudget {
    private var work = 0
    private let maximumBytes: Int
    private let maximumWork: Int

    init(maximumBytes: Int, maximumWork: Int) {
        self.maximumBytes = maximumBytes
        self.maximumWork = maximumWork
    }

    func checkByteCount(_ count: Int) throws {
        guard count <= maximumBytes else {
            throw ConfigurationReportError.redactionDecodedValueTooLarge(
                maximumBytes: maximumBytes
            )
        }
    }

    mutating func consume(_ amount: Int) throws {
        guard amount <= maximumWork - work else {
            throw ConfigurationReportError.redactionDecodingWorkLimitExceeded(
                maximumWork: maximumWork
            )
        }
        work += amount
    }
}

private struct ConfigurationReportRedactionView {
    let bytes: [UInt8]
    let sourceRanges: [Range<Int>]

    init(source: String) throws {
        var bytes: [UInt8] = []
        var sourceRanges: [Range<Int>] = []
        bytes.reserveCapacity(source.utf8.count)
        sourceRanges.reserveCapacity(source.utf8.count)
        var sourceOffset = 0
        for (index, character) in source.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let sourceLength = String(character).utf8.count
            let sourceRange = sourceOffset..<(sourceOffset + sourceLength)
            let alias = try ConfigurationReport.filesystemAliasForRedaction(String(character))
            let aliasBytes = try ConfigurationReport.redactionBytes(alias)
            bytes.append(contentsOf: aliasBytes)
            sourceRanges.append(contentsOf: repeatElement(sourceRange, count: aliasBytes.count))
            sourceOffset += sourceLength
        }
        try Task.checkCancellation()
        self.bytes = bytes
        self.sourceRanges = sourceRanges
    }
}

private struct ConfigurationReportOutput {
    private(set) var value = ""
    private var byteCount = 0
    private let maximumBytes: Int

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        value.reserveCapacity(min(maximumBytes, 4_096))
    }

    mutating func append(_ string: String) throws {
        let appendedBytes = string.utf8.count
        guard appendedBytes <= maximumBytes - byteCount else {
            throw ConfigurationReportError.outputTooLarge(maximumBytes: maximumBytes)
        }
        value.append(string)
        byteCount += appendedBytes
    }
}
