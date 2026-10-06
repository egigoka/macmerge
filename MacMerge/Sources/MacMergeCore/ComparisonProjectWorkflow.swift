import CoreFoundation
import CryptoKit
import Foundation

public enum ComparisonProjectWorkflowFormat: String, CaseIterable, Hashable, Sendable {
    case macMerge
    case winMerge
}

public enum ComparisonProjectWorkflowMode: String, CaseIterable, Hashable, Sendable {
    case automatic
    case text
    case table
    case binary
    case image
    case webpage
    case folder
}

public enum ComparisonProjectWorkflowSideIdentity: String, CaseIterable, Hashable, Sendable {
    case left
    case middle
    case right

    fileprivate var sortOrder: Int {
        switch self {
        case .left: 0
        case .middle: 1
        case .right: 2
        }
    }
}

public struct ComparisonProjectWorkflowSide: Hashable, Sendable {
    public let identity: ComparisonProjectWorkflowSideIdentity
    public let fileURL: URL
    public let readOnly: Bool
    /// Original relative WinMerge spelling. It is reused only when it still resolves to `fileURL`.
    public let winMergeRelativePath: String?

    public init(
        identity: ComparisonProjectWorkflowSideIdentity,
        fileURL: URL,
        readOnly: Bool = false,
        winMergeRelativePath: String? = nil
    ) {
        self.identity = identity
        self.fileURL = fileURL
        self.readOnly = readOnly
        self.winMergeRelativePath = winMergeRelativePath
    }
}

public enum ComparisonProjectWorkflowFilter: Hashable, Sendable {
    case named(String)
    case file(URL)
    /// Raw WinMerge filter expression, not a MacMerge named-filter identifier.
    case winMergeExpression(String)
}

public enum ComparisonProjectWorkflowDiffAlgorithm: String, CaseIterable, Hashable, Sendable {
    case `default`
    case minimal
    case patience
    case histogram
    case none
}

public enum ComparisonProjectWorkflowWhitespace: String, CaseIterable, Hashable, Sendable {
    case compareAll
    case ignoreChanges
    case ignoreAll
}

public struct ComparisonProjectWorkflowLineFilter: Hashable, Sendable {
    public let pattern: String
    public let caseSensitive: Bool

    public init(pattern: String, caseSensitive: Bool = true) {
        self.pattern = pattern
        self.caseSensitive = caseSensitive
    }
}

public struct ComparisonProjectWorkflowSubstitution: Hashable, Sendable {
    public let pattern: String
    public let replacement: String
    public let caseSensitive: Bool

    public init(pattern: String, replacement: String, caseSensitive: Bool = true) {
        self.pattern = pattern
        self.replacement = replacement
        self.caseSensitive = caseSensitive
    }
}

public struct ComparisonProjectWorkflowLineOptions: Hashable, Sendable {
    public let algorithm: ComparisonProjectWorkflowDiffAlgorithm
    public let whitespace: ComparisonProjectWorkflowWhitespace
    public let ignoreCase: Bool
    public let ignoreNumbers: Bool
    public let ignoreBlankLines: Bool
    public let ignoreComments: Bool
    public let ignoreLineEndings: Bool
    public let indentHeuristic: Bool
    public let detectMovedBlocks: Bool
    public let lineFiltersEnabled: Bool
    public let lineFilters: [ComparisonProjectWorkflowLineFilter]
    public let substitutionsEnabled: Bool
    public let substitutions: [ComparisonProjectWorkflowSubstitution]

    public init(
        algorithm: ComparisonProjectWorkflowDiffAlgorithm = .default,
        whitespace: ComparisonProjectWorkflowWhitespace = .compareAll,
        ignoreCase: Bool = false,
        ignoreNumbers: Bool = false,
        ignoreBlankLines: Bool = false,
        ignoreComments: Bool = false,
        ignoreLineEndings: Bool = true,
        indentHeuristic: Bool = false,
        detectMovedBlocks: Bool = false,
        lineFiltersEnabled: Bool = true,
        lineFilters: [ComparisonProjectWorkflowLineFilter] = [],
        substitutionsEnabled: Bool = true,
        substitutions: [ComparisonProjectWorkflowSubstitution] = []
    ) {
        self.algorithm = algorithm
        self.whitespace = whitespace
        self.ignoreCase = ignoreCase
        self.ignoreNumbers = ignoreNumbers
        self.ignoreBlankLines = ignoreBlankLines
        self.ignoreComments = ignoreComments
        self.ignoreLineEndings = ignoreLineEndings
        self.indentHeuristic = indentHeuristic
        self.detectMovedBlocks = detectMovedBlocks
        self.lineFiltersEnabled = lineFiltersEnabled
        self.lineFilters = lineFilters
        self.substitutionsEnabled = substitutionsEnabled
        self.substitutions = substitutions
    }
}

/// WinMerge serialization presence retained when opening and resaving a WinMerge project.
/// Duplicated values never override authoritative semantic fields on the project.
public struct ComparisonProjectWorkflowWinMergeOptions: Hashable, Sendable {
    /// True only for values decoded from WinMerge XML, where absent and explicit default differ.
    public let preservesSerializedOptionPresence: Bool
    public let windowTypeRawValue: Int?
    public let includesSubfolders: Bool?
    public let whitespaceHandlingRawValue: Int?
    public let ignoreBlankLines: Bool?
    public let ignoreCase: Bool?
    public let ignoreCarriageReturnDifferences: Bool?
    public let ignoreNumbers: Bool?
    public let ignoreCodepageDifferences: Bool?
    public let ignoreCommentDifferences: Bool?
    public let ignoreMissingTrailingEndOfLine: Bool?
    public let ignoreLineBreaks: Bool?
    public let compareMethodRawValue: Int?

    public init(
        preservesSerializedOptionPresence: Bool = false,
        windowTypeRawValue: Int? = nil,
        includesSubfolders: Bool? = nil,
        whitespaceHandlingRawValue: Int? = nil,
        ignoreBlankLines: Bool? = nil,
        ignoreCase: Bool? = nil,
        ignoreCarriageReturnDifferences: Bool? = nil,
        ignoreNumbers: Bool? = nil,
        ignoreCodepageDifferences: Bool? = nil,
        ignoreCommentDifferences: Bool? = nil,
        ignoreMissingTrailingEndOfLine: Bool? = nil,
        ignoreLineBreaks: Bool? = nil,
        compareMethodRawValue: Int? = nil
    ) {
        self.preservesSerializedOptionPresence = preservesSerializedOptionPresence
        self.windowTypeRawValue = windowTypeRawValue
        self.includesSubfolders = includesSubfolders
        self.whitespaceHandlingRawValue = whitespaceHandlingRawValue
        self.ignoreBlankLines = ignoreBlankLines
        self.ignoreCase = ignoreCase
        self.ignoreCarriageReturnDifferences = ignoreCarriageReturnDifferences
        self.ignoreNumbers = ignoreNumbers
        self.ignoreCodepageDifferences = ignoreCodepageDifferences
        self.ignoreCommentDifferences = ignoreCommentDifferences
        self.ignoreMissingTrailingEndOfLine = ignoreMissingTrailingEndOfLine
        self.ignoreLineBreaks = ignoreLineBreaks
        self.compareMethodRawValue = compareMethodRawValue
    }
}

/// Format-neutral, immutable project state. It can be built from either existing project model.
public struct ComparisonProjectWorkflowProject: Hashable, Sendable {
    public let mode: ComparisonProjectWorkflowMode
    public let sides: [ComparisonProjectWorkflowSide]
    public let recursive: Bool
    public let filter: ComparisonProjectWorkflowFilter?
    public let lineOptions: ComparisonProjectWorkflowLineOptions
    public let winMergeOptions: ComparisonProjectWorkflowWinMergeOptions

    public init(
        mode: ComparisonProjectWorkflowMode = .automatic,
        sides: [ComparisonProjectWorkflowSide],
        recursive: Bool = false,
        filter: ComparisonProjectWorkflowFilter? = nil,
        lineOptions: ComparisonProjectWorkflowLineOptions = ComparisonProjectWorkflowLineOptions(),
        winMergeOptions: ComparisonProjectWorkflowWinMergeOptions = ComparisonProjectWorkflowWinMergeOptions()
    ) {
        self.mode = mode
        self.sides = sides
        self.recursive = recursive
        self.filter = filter
        self.lineOptions = lineOptions
        self.winMergeOptions = winMergeOptions
    }

    public init(macMerge project: ComparisonProject, relativeTo projectFileURL: URL) throws {
        try project.validate()
        mode = ComparisonProjectWorkflowMode(project.mode)
        sides = project.sides.map {
            ComparisonProjectWorkflowSide(
                identity: ComparisonProjectWorkflowSideIdentity($0.identity),
                fileURL: Self.resolve($0.path, relativeTo: projectFileURL),
                readOnly: $0.readOnly
            )
        }.sorted { $0.identity.sortOrder < $1.identity.sortOrder }
        recursive = project.recursive
        switch project.filter {
        case .named(let name):
            filter = .named(name)
        case .file(let url):
            filter = .file(Self.resolve(url, relativeTo: projectFileURL))
        case nil:
            filter = nil
        }
        lineOptions = ComparisonProjectWorkflowLineOptions(project.lineDiffOptions)
        winMergeOptions = ComparisonProjectWorkflowWinMergeOptions()
    }

    public init(winMerge project: WinMergeProjectFile, relativeTo projectFileURL: URL) throws {
        let directoryURL = projectFileURL.deletingLastPathComponent()
        let left = try Self.resolveWinMergePath(project.leftPath, relativeTo: directoryURL)
        let middle = try project.middlePath.map {
            try Self.resolveWinMergePath($0, relativeTo: directoryURL)
        }
        let right = try Self.resolveWinMergePath(project.rightPath, relativeTo: directoryURL)
        try Self.rejectUnsupportedWinMergeSemantics(project.options)
        var convertedSides = [
            ComparisonProjectWorkflowSide(
                identity: .left,
                fileURL: left.url,
                readOnly: project.leftReadOnly,
                winMergeRelativePath: left.relativePath
            )
        ]
        if let middle {
            convertedSides.append(
                ComparisonProjectWorkflowSide(
                    identity: .middle,
                    fileURL: middle.url,
                    readOnly: project.middleReadOnly,
                    winMergeRelativePath: middle.relativePath
                )
            )
        }
        convertedSides.append(
            ComparisonProjectWorkflowSide(
                identity: .right,
                fileURL: right.url,
                readOnly: project.rightReadOnly,
                winMergeRelativePath: right.relativePath
            )
        )
        mode = Self.winMergeMode(
            windowType: project.options.windowType,
            includesSubfolders: project.includesSubfolders
        )
        sides = convertedSides
        recursive = mode == .folder ? (project.includesSubfolders ?? false) : false
        filter = project.filter.map(ComparisonProjectWorkflowFilter.winMergeExpression)
        lineOptions = ComparisonProjectWorkflowLineOptions(project.options)
        winMergeOptions = ComparisonProjectWorkflowWinMergeOptions(
            preservesSerializedOptionPresence: true,
            windowTypeRawValue: project.options.windowType?.rawValue,
            includesSubfolders: project.includesSubfolders,
            whitespaceHandlingRawValue: project.options.whitespaceHandling?.rawValue,
            ignoreBlankLines: project.options.ignoreBlankLines,
            ignoreCase: project.options.ignoreCase,
            ignoreCarriageReturnDifferences: project.options.ignoreCarriageReturnDifferences,
            ignoreNumbers: project.options.ignoreNumbers,
            ignoreCodepageDifferences: project.options.ignoreCodepageDifferences,
            ignoreCommentDifferences: project.options.ignoreCommentDifferences,
            ignoreMissingTrailingEndOfLine: project.options.ignoreMissingTrailingEndOfLine,
            ignoreLineBreaks: project.options.ignoreLineBreaks,
            compareMethodRawValue: project.options.compareMethod?.rawValue
        )
    }

    private static func resolve(_ url: URL, relativeTo projectFileURL: URL) -> URL {
        guard url.baseURL != nil else { return url }
        return projectFileURL.deletingLastPathComponent().appending(path: url.relativePath)
    }

    fileprivate static func winMergeMode(
        windowType: WinMergeProjectFile.WindowType?,
        includesSubfolders: Bool?
    ) -> ComparisonProjectWorkflowMode {
        if let windowType { return ComparisonProjectWorkflowMode(windowType) }
        return includesSubfolders == nil ? .automatic : .folder
    }

    fileprivate static func resolveWinMergePath(
        _ path: String,
        relativeTo directoryURL: URL
    ) throws -> (url: URL, relativePath: String?) {
        guard isRepresentableWinMergePath(path) else {
            throw ComparisonProjectWorkflowError.unsupportedWinMergePath(path)
        }
        if path.hasPrefix("/") {
            return (URL(fileURLWithPath: path), nil)
        }
        return (directoryURL.appending(path: path).standardizedFileURL, path)
    }

    fileprivate static func isRepresentableWinMergePath(_ path: String) -> Bool {
        guard !path.isEmpty,
            !path.contains("\0"),
            !path.contains("\\"),
            !path.hasPrefix("//"),
            !hasURIScheme(path),
            !path.hasPrefix("~"),
            !containsEnvironmentReference(path)
        else {
            return false
        }
        if path.count >= 2 {
            let characters = Array(path.prefix(2))
            if characters[0].isASCII, characters[0].isLetter,
                characters[1] == ":"
            {
                return false
            }
        }
        if path.count >= 4 {
            let characters = Array(path.prefix(4))
            if characters[0] == "/", characters[1].isASCII, characters[1].isLetter,
                characters[2] == ":", characters[3] == "/"
            {
                return false
            }
        }
        return true
    }

    private static func hasURIScheme(_ path: String) -> Bool {
        guard let colon = path.firstIndex(of: ":"), colon != path.startIndex else { return false }
        let scheme = path[..<colon]
        guard scheme.first?.isASCII == true, scheme.first?.isLetter == true else { return false }
        return scheme.dropFirst().allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".")
        }
    }

    private static func containsEnvironmentReference(_ path: String) -> Bool {
        var index = path.startIndex
        while index < path.endIndex {
            if path[index] == "$" { return true }
            index = path.index(after: index)
        }
        var percent = path.startIndex
        while let opening = path[percent...].firstIndex(of: "%") {
            let valueStart = path.index(after: opening)
            guard let closing = path[valueStart...].firstIndex(of: "%") else { break }
            if valueStart != closing { return true }
            percent = path.index(after: closing)
        }
        return false
    }

    private static func rejectUnsupportedWinMergeSemantics(
        _ options: WinMergeProjectFile.Options
    ) throws {
        if let method = options.compareMethod, method != .fullContents {
            throw ComparisonProjectWorkflowError.unsupportedWinMergeCompareMethod(method.rawValue)
        }
        guard options.ignoreCodepageDifferences != true,
            options.ignoreMissingTrailingEndOfLine != true,
            options.ignoreLineBreaks != true
        else {
            throw ComparisonProjectWorkflowError.unsupportedWinMergeTextSemantics
        }
    }
}

public struct ComparisonProjectWorkflowNodeIdentity: Hashable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let generation: UInt32

    public init(deviceID: UInt64, fileID: UInt64, generation: UInt32) {
        self.deviceID = deviceID
        self.fileID = fileID
        self.generation = generation
    }
}

/// Caller-captured canonical directory identity. Planner never resolves `canonicalURL`.
public struct ComparisonProjectWorkflowCanonicalDirectoryIdentity: Hashable, Sendable {
    public let canonicalURL: URL
    public let node: ComparisonProjectWorkflowNodeIdentity

    public init(canonicalURL: URL, node: ComparisonProjectWorkflowNodeIdentity) {
        self.canonicalURL = canonicalURL
        self.node = node
    }
}

/// Caller-captured canonical regular-file identity. URL is audit data, not authority.
public struct ComparisonProjectWorkflowCanonicalFileIdentity: Hashable, Sendable {
    public let canonicalURL: URL
    public let parent: ComparisonProjectWorkflowCanonicalDirectoryIdentity
    public let node: ComparisonProjectWorkflowNodeIdentity

    public init(
        canonicalURL: URL,
        parent: ComparisonProjectWorkflowCanonicalDirectoryIdentity,
        node: ComparisonProjectWorkflowNodeIdentity
    ) {
        self.canonicalURL = canonicalURL
        self.parent = parent
        self.node = node
    }
}

/// Exact revision captured through a pinned regular-file descriptor.
public struct ComparisonProjectWorkflowFileRevision: Hashable, Sendable {
    public let identity: ComparisonProjectWorkflowCanonicalFileIdentity
    public let byteCount: UInt64
    public let linkCount: UInt64
    public let permissions: UInt16
    public let ownerID: UInt32
    public let groupID: UInt32
    public let flags: UInt32
    public let modificationTimeSeconds: Int64
    public let modificationTimeNanoseconds: Int32
    public let statusChangeTimeSeconds: Int64
    public let statusChangeTimeNanoseconds: Int32
    public let contentSHA256: [UInt8]
    /// Digest of complete executor-defined metadata, including ACLs and extended attributes.
    public let metadataSHA256: [UInt8]

    public init(
        identity: ComparisonProjectWorkflowCanonicalFileIdentity,
        byteCount: UInt64,
        linkCount: UInt64,
        permissions: UInt16,
        ownerID: UInt32,
        groupID: UInt32,
        flags: UInt32,
        modificationTimeSeconds: Int64,
        modificationTimeNanoseconds: Int32,
        statusChangeTimeSeconds: Int64,
        statusChangeTimeNanoseconds: Int32,
        contentSHA256: [UInt8],
        metadataSHA256: [UInt8]
    ) {
        self.identity = identity
        self.byteCount = byteCount
        self.linkCount = linkCount
        self.permissions = permissions
        self.ownerID = ownerID
        self.groupID = groupID
        self.flags = flags
        self.modificationTimeSeconds = modificationTimeSeconds
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
        self.statusChangeTimeSeconds = statusChangeTimeSeconds
        self.statusChangeTimeNanoseconds = statusChangeTimeNanoseconds
        self.contentSHA256 = contentSHA256
        self.metadataSHA256 = metadataSHA256
    }
}

/// Immutable bytes paired with their exact canonical revision.
public struct ComparisonProjectWorkflowFileSnapshot: Hashable, Sendable {
    public let revision: ComparisonProjectWorkflowFileRevision
    public let data: Data

    public init(revision: ComparisonProjectWorkflowFileRevision, data: Data) {
        self.revision = revision
        self.data = data
    }
}

public enum ComparisonProjectWorkflowAuthorityCoverage: String, CaseIterable, Hashable, Sendable {
    case exactFile
    case directoryTree
}

/// Declared access acquisition intent. It is not proof that sandbox access is available.
public enum ComparisonProjectWorkflowAccess: Hashable, Sendable {
    case ambient
    case callerManagedWhenRequired
    case securityScoped(resourceURL: URL, coverage: ComparisonProjectWorkflowAuthorityCoverage)
}

public enum ComparisonProjectWorkflowAuthorityPurpose: Hashable, Sendable {
    case readProjectFile
    case readComparisonSource(ComparisonProjectWorkflowSideIdentity)
    case readProjectFilter
    case createProjectFile
    case replaceProjectFile
}

public struct ComparisonProjectWorkflowAuthorityRequirement: Hashable, Sendable {
    public let purpose: ComparisonProjectWorkflowAuthorityPurpose
    public let requestedURL: URL
    /// Present only when caller supplied a canonical identity. Planner never invents one.
    public let canonicalURL: URL?
    public let requiredCoverage: ComparisonProjectWorkflowAuthorityCoverage
    public let access: ComparisonProjectWorkflowAccess

    public init(
        purpose: ComparisonProjectWorkflowAuthorityPurpose,
        requestedURL: URL,
        canonicalURL: URL? = nil,
        requiredCoverage: ComparisonProjectWorkflowAuthorityCoverage = .exactFile,
        access: ComparisonProjectWorkflowAccess
    ) {
        self.purpose = purpose
        self.requestedURL = requestedURL
        self.canonicalURL = canonicalURL
        self.requiredCoverage = requiredCoverage
        self.access = access
    }
}

/// Caller attestation that a possibly aliased requested URL resolves to this exact canonical target.
public enum ComparisonProjectWorkflowRequestedURLAttestation: Hashable, Sendable {
    case file(requestedURL: URL, identity: ComparisonProjectWorkflowCanonicalFileIdentity)
    case location(requestedURL: URL, location: ComparisonProjectWorkflowCanonicalLocation)
}

public struct ComparisonProjectWorkflowSnapshotIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum ComparisonProjectWorkflowProjectBinding: Hashable, Sendable {
    case untitled
    case file(ComparisonProjectWorkflowFileRevision)
}

/// Immutable owner snapshot. Owners must never reuse `generation` for changed project or dirty state.
public struct ComparisonProjectWorkflowSnapshot: Hashable, Sendable {
    public let identity: ComparisonProjectWorkflowSnapshotIdentity
    public let generation: UInt64
    public let project: ComparisonProjectWorkflowProject
    public let binding: ComparisonProjectWorkflowProjectBinding
    public let isDirty: Bool

    public init(
        identity: ComparisonProjectWorkflowSnapshotIdentity,
        generation: UInt64,
        project: ComparisonProjectWorkflowProject,
        binding: ComparisonProjectWorkflowProjectBinding = .untitled,
        isDirty: Bool
    ) {
        self.identity = identity
        self.generation = generation
        self.project = project
        self.binding = binding
        self.isDirty = isDirty
    }
}

public struct ComparisonProjectWorkflowSnapshotReference: Hashable, Sendable {
    public let identity: ComparisonProjectWorkflowSnapshotIdentity
    public let generation: UInt64

    public init(identity: ComparisonProjectWorkflowSnapshotIdentity, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }

    public init(_ snapshot: ComparisonProjectWorkflowSnapshot) {
        identity = snapshot.identity
        generation = snapshot.generation
    }
}

/// Exact owner-state compare-and-swap token. Reference detects ordinary staleness; digest detects
/// contract violations where contents changed without advancing generation.
public struct ComparisonProjectWorkflowSnapshotCAS: Hashable, Sendable {
    public let reference: ComparisonProjectWorkflowSnapshotReference
    public let stateSHA256: [UInt8]

    fileprivate init(
        reference: ComparisonProjectWorkflowSnapshotReference,
        stateSHA256: [UInt8]
    ) {
        self.reference = reference
        self.stateSHA256 = stateSHA256
    }
}

public enum ComparisonProjectOpenReplacementPolicy: String, CaseIterable, Hashable, Sendable {
    case requireEmptyWorkspace
    case replaceIfClean
    case discardChangesAndReplace
}

public enum ComparisonProjectSaveDirtyPolicy: String, CaseIterable, Hashable, Sendable {
    case allowUnmodified
    case requireModified
}

public struct ComparisonProjectWorkflowCanonicalLocation: Hashable, Sendable {
    public let canonicalURL: URL
    public let parent: ComparisonProjectWorkflowCanonicalDirectoryIdentity

    public init(
        canonicalURL: URL,
        parent: ComparisonProjectWorkflowCanonicalDirectoryIdentity
    ) {
        self.canonicalURL = canonicalURL
        self.parent = parent
    }
}

public enum ComparisonProjectSaveIntention: Hashable, Sendable {
    /// Publish only if this leaf is absent under the exact canonical parent.
    case createNew(ComparisonProjectWorkflowCanonicalLocation)
    /// Replace only this exact revision and preserve its complete metadata.
    case replaceExisting(ComparisonProjectWorkflowFileRevision)

    public var canonicalURL: URL {
        switch self {
        case .createNew(let location): location.canonicalURL
        case .replaceExisting(let revision): revision.identity.canonicalURL
        }
    }
}

public struct ComparisonProjectSaveDestination: Hashable, Sendable {
    /// Original URL may carry sandbox authorization and is retained without canonicalization.
    public let requestedURL: URL
    public let intention: ComparisonProjectSaveIntention
    public let requestedURLAttestation: ComparisonProjectWorkflowRequestedURLAttestation?
    public let access: ComparisonProjectWorkflowAccess

    public init(
        requestedURL: URL,
        intention: ComparisonProjectSaveIntention,
        requestedURLAttestation: ComparisonProjectWorkflowRequestedURLAttestation? = nil,
        access: ComparisonProjectWorkflowAccess = .callerManagedWhenRequired
    ) {
        self.requestedURL = requestedURL
        self.intention = intention
        self.requestedURLAttestation = requestedURLAttestation
        self.access = access
    }
}

public enum ComparisonProjectWorkflowLimit: String, CaseIterable, Hashable, Sendable {
    case projectFileBytes
    case pathUTF8Bytes
    case totalPathUTF8Bytes
    case optionItemCount
    case optionStringUTF8Bytes
    case totalOptionStringUTF8Bytes
    case planBytes
    case workUnits
}

public struct ComparisonProjectWorkflowLimits: Hashable, Sendable {
    public static let hardMaximumProjectFileBytes = 4 * 1_024 * 1_024
    public static let hardMaximumPathUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalPathUTF8Bytes = 1 * 1_024 * 1_024
    public static let hardMaximumOptionItemCount = 65_536
    public static let hardMaximumOptionStringUTF8Bytes = 256 * 1_024
    public static let hardMaximumTotalOptionStringUTF8Bytes = 4 * 1_024 * 1_024
    public static let hardMaximumPlanBytes = 16 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 512 * 1_024 * 1_024
    public static let `default` = ComparisonProjectWorkflowLimits()

    public let maximumProjectFileBytes: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumOptionItemCount: Int
    public let maximumOptionStringUTF8Bytes: Int
    public let maximumTotalOptionStringUTF8Bytes: Int
    public let maximumPlanBytes: Int
    public let maximumWorkUnits: UInt64

    public init(
        maximumProjectFileBytes: Int = ComparisonProject.maximumFileSize,
        maximumPathUTF8Bytes: Int = 16 * 1_024,
        maximumTotalPathUTF8Bytes: Int = 256 * 1_024,
        maximumOptionItemCount: Int = 4_096,
        maximumOptionStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalOptionStringUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumPlanBytes: Int = 12 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 64 * 1_024 * 1_024
    ) {
        self.maximumProjectFileBytes = maximumProjectFileBytes
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumOptionItemCount = maximumOptionItemCount
        self.maximumOptionStringUTF8Bytes = maximumOptionStringUTF8Bytes
        self.maximumTotalOptionStringUTF8Bytes = maximumTotalOptionStringUTF8Bytes
        self.maximumPlanBytes = maximumPlanBytes
        self.maximumWorkUnits = maximumWorkUnits
    }
}

public struct ComparisonProjectOpenRequest: Hashable, Sendable {
    public let requestedURL: URL
    public let format: ComparisonProjectWorkflowFormat
    public let source: ComparisonProjectWorkflowFileSnapshot
    public let requestedURLAttestation: ComparisonProjectWorkflowRequestedURLAttestation?
    public let access: ComparisonProjectWorkflowAccess
    public let currentWorkspace: ComparisonProjectWorkflowSnapshot?
    public let replacementPolicy: ComparisonProjectOpenReplacementPolicy
    public let limits: ComparisonProjectWorkflowLimits

    public init(
        requestedURL: URL,
        format: ComparisonProjectWorkflowFormat,
        source: ComparisonProjectWorkflowFileSnapshot,
        requestedURLAttestation: ComparisonProjectWorkflowRequestedURLAttestation? = nil,
        access: ComparisonProjectWorkflowAccess = .callerManagedWhenRequired,
        currentWorkspace: ComparisonProjectWorkflowSnapshot? = nil,
        replacementPolicy: ComparisonProjectOpenReplacementPolicy = .replaceIfClean,
        limits: ComparisonProjectWorkflowLimits = .default
    ) {
        self.requestedURL = requestedURL
        self.format = format
        self.source = source
        self.requestedURLAttestation = requestedURLAttestation
        self.access = access
        self.currentWorkspace = currentWorkspace
        self.replacementPolicy = replacementPolicy
        self.limits = limits
    }
}

public struct ComparisonProjectSaveRequest: Hashable, Sendable {
    public let snapshot: ComparisonProjectWorkflowSnapshot
    public let format: ComparisonProjectWorkflowFormat
    public let destination: ComparisonProjectSaveDestination
    public let dirtyPolicy: ComparisonProjectSaveDirtyPolicy
    public let limits: ComparisonProjectWorkflowLimits

    public init(
        snapshot: ComparisonProjectWorkflowSnapshot,
        format: ComparisonProjectWorkflowFormat,
        destination: ComparisonProjectSaveDestination,
        dirtyPolicy: ComparisonProjectSaveDirtyPolicy = .allowUnmodified,
        limits: ComparisonProjectWorkflowLimits = .default
    ) {
        self.snapshot = snapshot
        self.format = format
        self.destination = destination
        self.dirtyPolicy = dirtyPolicy
        self.limits = limits
    }
}

public enum ComparisonProjectWorkflowRequest: Hashable, Sendable {
    case open(ComparisonProjectOpenRequest)
    case save(ComparisonProjectSaveRequest)
}

public enum ComparisonProjectWorkspaceReplacementReceipt: Hashable, Sendable {
    case noWorkspace
    case replacedClean(ComparisonProjectWorkflowSnapshotReference)
    case discardedChanges(ComparisonProjectWorkflowSnapshotReference)
}

public enum ComparisonProjectPlanningReceiptKind: String, CaseIterable, Hashable, Sendable {
    case open
    case create
    case replace
}

/// Deterministic receipt for successful planning. No random identifier or wall-clock value is used.
public struct ComparisonProjectPlanningReceipt: Hashable, Sendable {
    public let kind: ComparisonProjectPlanningReceiptKind
    public let projectContentSHA256: [UInt8]
    public let planSHA256: [UInt8]
    public let payloadByteCount: Int
    public let estimatedWorkUnits: UInt64

    fileprivate init(
        kind: ComparisonProjectPlanningReceiptKind,
        projectContentSHA256: [UInt8],
        planSHA256: [UInt8],
        payloadByteCount: Int,
        estimatedWorkUnits: UInt64
    ) {
        self.kind = kind
        self.projectContentSHA256 = projectContentSHA256
        self.planSHA256 = planSHA256
        self.payloadByteCount = payloadByteCount
        self.estimatedWorkUnits = estimatedWorkUnits
    }
}

public enum ComparisonProjectPathResolutionContract: String, Hashable, Sendable {
    case descriptorRelativeNoFollowFromPinnedCanonicalParent
}

public enum ComparisonProjectAuthorityContract: String, Hashable, Sendable {
    case balancedAccessAroundValidationAndMaterialization
}

public enum ComparisonProjectOpenExecutionContract: String, Hashable, Sendable {
    case revalidateSourceAndWorkspaceBeforeReplacingState
}

public enum ComparisonProjectSaveExecutionContract: String, Hashable, Sendable {
    case privateStageExactBytesThenAtomicSnapshotAndDestinationCASPublishDurably
}

public enum ComparisonProjectMetadataContract: String, Hashable, Sendable {
    case preserveAndVerifyCompleteMetadataWhenReplacing
}

public enum ComparisonProjectCancellationContract: String, Hashable, Sendable {
    case cancellationBeforeEffects
}

/// Mandatory boundary for any future executor. This module intentionally supplies no executor.
public struct ComparisonProjectWorkflowExecutorContract: Hashable, Sendable {
    public static let required = ComparisonProjectWorkflowExecutorContract()

    public let pathResolution =
        ComparisonProjectPathResolutionContract.descriptorRelativeNoFollowFromPinnedCanonicalParent
    public let authority =
        ComparisonProjectAuthorityContract.balancedAccessAroundValidationAndMaterialization
    public let opening =
        ComparisonProjectOpenExecutionContract.revalidateSourceAndWorkspaceBeforeReplacingState
    public let saving =
        ComparisonProjectSaveExecutionContract.privateStageExactBytesThenAtomicSnapshotAndDestinationCASPublishDurably
    public let metadata =
        ComparisonProjectMetadataContract.preserveAndVerifyCompleteMetadataWhenReplacing
    public let cancellation = ComparisonProjectCancellationContract.cancellationBeforeEffects

    public init() {}
}

public struct ComparisonProjectOpenPlan: Hashable, Sendable {
    public let format: ComparisonProjectWorkflowFormat
    public let requestedURL: URL
    public let sourceRevision: ComparisonProjectWorkflowFileRevision
    public let project: ComparisonProjectWorkflowProject
    public let canonicalProjectData: Data
    public let replacementPolicy: ComparisonProjectOpenReplacementPolicy
    public let workspaceReplacement: ComparisonProjectWorkspaceReplacementReceipt
    public let authorityRequirements: [ComparisonProjectWorkflowAuthorityRequirement]
    public let receipt: ComparisonProjectPlanningReceipt
    public let limits: ComparisonProjectWorkflowLimits
    public let executorContract: ComparisonProjectWorkflowExecutorContract
    public let expectedWorkspaceCAS: ComparisonProjectWorkflowSnapshotCAS?

    fileprivate init(
        format: ComparisonProjectWorkflowFormat,
        requestedURL: URL,
        sourceRevision: ComparisonProjectWorkflowFileRevision,
        project: ComparisonProjectWorkflowProject,
        canonicalProjectData: Data,
        replacementPolicy: ComparisonProjectOpenReplacementPolicy,
        workspaceReplacement: ComparisonProjectWorkspaceReplacementReceipt,
        authorityRequirements: [ComparisonProjectWorkflowAuthorityRequirement],
        receipt: ComparisonProjectPlanningReceipt,
        limits: ComparisonProjectWorkflowLimits,
        expectedWorkspaceCAS: ComparisonProjectWorkflowSnapshotCAS?
    ) {
        self.format = format
        self.requestedURL = requestedURL
        self.sourceRevision = sourceRevision
        self.project = project
        self.canonicalProjectData = canonicalProjectData
        self.replacementPolicy = replacementPolicy
        self.workspaceReplacement = workspaceReplacement
        self.authorityRequirements = authorityRequirements
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
        self.expectedWorkspaceCAS = expectedWorkspaceCAS
    }

    public func validateCurrentSourceRevision(
        _ revision: ComparisonProjectWorkflowFileRevision
    ) throws {
        do {
            try Task.checkCancellation()
            guard revision == sourceRevision else {
                throw ComparisonProjectWorkflowError.sourceChanged
            }
        } catch is CancellationError {
            throw ComparisonProjectWorkflowError.cancelled
        }
    }

    public func validateCurrentWorkspace(
        _ snapshot: ComparisonProjectWorkflowSnapshot?
    ) throws {
        do {
            try ComparisonProjectWorkflowPlanner.validateCurrentWorkspace(
                snapshot,
                expected: expectedWorkspaceCAS,
                limits: limits
            )
        } catch is CancellationError {
            throw ComparisonProjectWorkflowError.cancelled
        }
    }

    /// Executor calls this after materialization and immediately before committing owner state.
    public func validateForPublication(
        currentSourceRevision: ComparisonProjectWorkflowFileRevision,
        currentWorkspace: ComparisonProjectWorkflowSnapshot?
    ) throws {
        try validateCurrentSourceRevision(currentSourceRevision)
        try validateCurrentWorkspace(currentWorkspace)
    }
}

public struct ComparisonProjectSavePlan: Hashable, Sendable {
    public let snapshotCAS: ComparisonProjectWorkflowSnapshotCAS
    public var snapshotReference: ComparisonProjectWorkflowSnapshotReference { snapshotCAS.reference }
    public let format: ComparisonProjectWorkflowFormat
    public let destination: ComparisonProjectSaveDestination
    /// Complete successor bytes. Future executors publish these bytes without regeneration.
    public let payload: Data
    public let dirtyPolicy: ComparisonProjectSaveDirtyPolicy
    public let authorityRequirements: [ComparisonProjectWorkflowAuthorityRequirement]
    public let receipt: ComparisonProjectPlanningReceipt
    public let limits: ComparisonProjectWorkflowLimits
    public let executorContract: ComparisonProjectWorkflowExecutorContract

    fileprivate init(
        snapshot: ComparisonProjectWorkflowSnapshot,
        snapshotCAS: ComparisonProjectWorkflowSnapshotCAS,
        format: ComparisonProjectWorkflowFormat,
        destination: ComparisonProjectSaveDestination,
        payload: Data,
        dirtyPolicy: ComparisonProjectSaveDirtyPolicy,
        authorityRequirements: [ComparisonProjectWorkflowAuthorityRequirement],
        receipt: ComparisonProjectPlanningReceipt,
        limits: ComparisonProjectWorkflowLimits
    ) {
        self.snapshotCAS = snapshotCAS
        self.format = format
        self.destination = destination
        self.payload = payload
        self.dirtyPolicy = dirtyPolicy
        self.authorityRequirements = authorityRequirements
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public func validateCurrentSnapshot(
        _ snapshot: ComparisonProjectWorkflowSnapshot
    ) throws {
        do {
            try ComparisonProjectWorkflowPlanner.validateCurrentSnapshot(
                snapshot,
                expected: snapshotCAS,
                limits: limits
            )
        } catch is CancellationError {
            throw ComparisonProjectWorkflowError.cancelled
        }
    }

    /// Executor must perform this check and publication in one serialized destination/owner commit.
    public func validateForPublication(
        currentSnapshot: ComparisonProjectWorkflowSnapshot,
        currentDestinationRevision: ComparisonProjectWorkflowFileRevision?
    ) throws {
        try validateCurrentSnapshot(currentSnapshot)
        switch destination.intention {
        case .createNew:
            guard currentDestinationRevision == nil else {
                throw ComparisonProjectWorkflowError.destinationChanged
            }
        case .replaceExisting(let expectedRevision):
            guard currentDestinationRevision == expectedRevision else {
                throw ComparisonProjectWorkflowError.destinationChanged
            }
        }
    }
}

public enum ComparisonProjectWorkflowPlan: Hashable, Sendable {
    case open(ComparisonProjectOpenPlan)
    case save(ComparisonProjectSavePlan)
}

public enum ComparisonProjectWorkflowURLRole: Hashable, Sendable {
    case requestedProject
    case canonicalProject
    case canonicalParent
    case comparisonSide(ComparisonProjectWorkflowSideIdentity)
    case filter
    case securityScope
}

public enum ComparisonProjectWorkflowURLIssue: String, CaseIterable, Hashable, Sendable {
    case notFileURL
    case relativeURL
    case remoteHost
    case credentialsOrPort
    case queryOrFragment
    case directoryURL
    case missingFileName
    case nullByte
    case pathTooLong
    case notCanonical
    case parentMismatch
    case unattestedAlias
    case insufficientAuthorityCoverage
}

public enum ComparisonProjectWorkflowError: Error, Equatable, Hashable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(ComparisonProjectWorkflowLimit)
    case workLimitExceeded(maximumUnits: UInt64)
    case invalidURL(role: ComparisonProjectWorkflowURLRole, issue: ComparisonProjectWorkflowURLIssue)
    case invalidFileRevision(String)
    case snapshotByteCountMismatch(expected: UInt64, actual: Int)
    case snapshotDigestMismatch
    case projectFileTooLarge(maximumBytes: Int)
    case planTooLarge(maximumBytes: Int)
    case invalidMacMergeProject
    case macMergeProject(ComparisonProjectError)
    case winMergeProject(WinMergeProjectFileDiagnostic)
    case invalidSideCount(Int)
    case duplicateSide(ComparisonProjectWorkflowSideIdentity)
    case invalidSideSet([ComparisonProjectWorkflowSideIdentity])
    case optionLimitExceeded(ComparisonProjectWorkflowLimit)
    case workspaceAlreadyOpen
    case dirtyWorkspaceRequiresReplacementApproval
    case projectMustBeModified
    case staleWorkspace(
        expected: ComparisonProjectWorkflowSnapshotReference?,
        actual: ComparisonProjectWorkflowSnapshotReference?
    )
    case workspaceContentsChanged
    case sourceChanged
    case destinationChanged
    case destinationDoesNotMatchIntention
    case replacementDoesNotMatchBinding
    case formatCannotRepresentProject(ComparisonProjectWorkflowFormat)
    case unsupportedWinMergeCompareMethod(Int)
    case unsupportedWinMergeTextSemantics
    case unsupportedWinMergePath(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Comparison project planning was cancelled."
        case .invalidLimit(let limit):
            "Invalid comparison project workflow limit: \(limit.rawValue)."
        case .workLimitExceeded(let maximum):
            "Comparison project planning exceeds the \(maximum)-unit work limit."
        case .invalidURL(let role, let issue):
            "Invalid comparison project URL for \(String(describing: role)): \(issue.rawValue)."
        case .invalidFileRevision(let path):
            "Invalid comparison project file revision: \(path)."
        case .snapshotByteCountMismatch(let expected, let actual):
            "Comparison project snapshot contains \(actual) bytes instead of \(expected)."
        case .snapshotDigestMismatch:
            "Comparison project snapshot bytes do not match their revision digest."
        case .projectFileTooLarge(let maximum):
            "Comparison project file exceeds the \(maximum)-byte workflow limit."
        case .planTooLarge(let maximum):
            "Comparison project plan exceeds the \(maximum)-byte retained-output limit."
        case .invalidMacMergeProject:
            "MacMerge project data is not a valid comparison project."
        case .macMergeProject(let error):
            error.localizedDescription
        case .winMergeProject(let diagnostic):
            diagnostic.localizedDescription
        case .invalidSideCount(let count):
            "Comparison project workflow requires two or three sides, not \(count)."
        case .duplicateSide(let side):
            "Comparison project workflow repeats the \(side.rawValue) side."
        case .invalidSideSet(let sides):
            "Comparison project workflow has invalid sides: \(sides.map(\.rawValue).joined(separator: ", "))."
        case .optionLimitExceeded(let limit):
            "Comparison project options exceed the \(limit.rawValue) limit."
        case .workspaceAlreadyOpen:
            "Opening this project requires an empty workspace."
        case .dirtyWorkspaceRequiresReplacementApproval:
            "Opening this project would discard unsaved project changes."
        case .projectMustBeModified:
            "Save Project requires a modified project under the selected dirty policy."
        case .staleWorkspace:
            "Comparison project workspace identity or generation is stale."
        case .workspaceContentsChanged:
            "Comparison project workspace changed without advancing its generation."
        case .sourceChanged:
            "Comparison project source changed after planning."
        case .destinationChanged:
            "Comparison project destination changed before publication."
        case .destinationDoesNotMatchIntention:
            "Comparison project destination does not match its canonical create or replace intention."
        case .replacementDoesNotMatchBinding:
            "Comparison project replacement does not match the workspace's bound project revision."
        case .formatCannotRepresentProject(let format):
            "\(format.rawValue) project format cannot represent this project without data loss."
        case .unsupportedWinMergeCompareMethod(let rawValue):
            "Unsupported WinMerge comparison method raw value: \(rawValue)."
        case .unsupportedWinMergeTextSemantics:
            "WinMerge codepage or end-of-line semantics cannot be represented safely."
        case .unsupportedWinMergePath(let path):
            "WinMerge path requires an explicit platform path mapper: \(path)."
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(errorDescription)
    }
}

/// Pure planner. It parses supplied bytes and creates immutable plans without filesystem or UI access.
public enum ComparisonProjectWorkflowPlanner: Sendable {
    public static func plan(_ request: ComparisonProjectWorkflowRequest) throws -> ComparisonProjectWorkflowPlan {
        switch request {
        case .open(let request): .open(try planOpen(request))
        case .save(let request): .save(try planSave(request))
        }
    }

    public static func planOpen(_ request: ComparisonProjectOpenRequest) throws -> ComparisonProjectOpenPlan {
        do {
            return try makeOpenPlan(request)
        } catch is CancellationError {
            throw ComparisonProjectWorkflowError.cancelled
        }
    }

    public static func planSave(_ request: ComparisonProjectSaveRequest) throws -> ComparisonProjectSavePlan {
        do {
            return try makeSavePlan(request)
        } catch is CancellationError {
            throw ComparisonProjectWorkflowError.cancelled
        }
    }

    fileprivate static func validateCurrentWorkspace(
        _ snapshot: ComparisonProjectWorkflowSnapshot?,
        expected: ComparisonProjectWorkflowSnapshotCAS?,
        limits: ComparisonProjectWorkflowLimits
    ) throws {
        try Task.checkCancellation()
        guard snapshot.map(ComparisonProjectWorkflowSnapshotReference.init) == expected?.reference
        else {
            throw ComparisonProjectWorkflowError.staleWorkspace(
                expected: expected?.reference,
                actual: snapshot.map(ComparisonProjectWorkflowSnapshotReference.init)
            )
        }
        guard let snapshot else { return }
        var work = ComparisonProjectWorkflowWorkBudget(maximum: limits.maximumWorkUnits)
        try validateSnapshot(snapshot, limits: limits, work: &work)
        guard try snapshotCAS(snapshot, work: &work) == expected else {
            throw ComparisonProjectWorkflowError.workspaceContentsChanged
        }
    }

    fileprivate static func validateCurrentSnapshot(
        _ snapshot: ComparisonProjectWorkflowSnapshot,
        expected: ComparisonProjectWorkflowSnapshotCAS,
        limits: ComparisonProjectWorkflowLimits
    ) throws {
        try validateCurrentWorkspace(snapshot, expected: expected, limits: limits)
    }

    private static func makeOpenPlan(
        _ request: ComparisonProjectOpenRequest
    ) throws -> ComparisonProjectOpenPlan {
        try Task.checkCancellation()
        try validate(request.limits)
        var work = ComparisonProjectWorkflowWorkBudget(maximum: request.limits.maximumWorkUnits)
        try validateProjectFileURL(
            request.requestedURL,
            role: .requestedProject,
            maximumPathBytes: request.limits.maximumPathUTF8Bytes,
            canonical: false,
            work: &work
        )
        try validate(
            request.source.revision,
            limits: request.limits,
            work: &work
        )
        try validateRequestedURLAttestation(
            requestedURL: request.requestedURL,
            canonicalIdentity: request.source.revision.identity,
            attestation: request.requestedURLAttestation
        )
        guard request.source.data.count <= request.limits.maximumProjectFileBytes else {
            throw ComparisonProjectWorkflowError.projectFileTooLarge(
                maximumBytes: request.limits.maximumProjectFileBytes
            )
        }
        guard UInt64(request.source.data.count) == request.source.revision.byteCount else {
            throw ComparisonProjectWorkflowError.snapshotByteCountMismatch(
                expected: request.source.revision.byteCount,
                actual: request.source.data.count
            )
        }
        let sourceDigest = try digest(request.source.data, work: &work)
        guard sourceDigest == request.source.revision.contentSHA256 else {
            throw ComparisonProjectWorkflowError.snapshotDigestMismatch
        }
        let replacement = try workspaceReplacement(
            request.currentWorkspace,
            policy: request.replacementPolicy
        )
        try validateAccess(request.access, limits: request.limits, work: &work)
        try validateAuthorityCoverage(
            access: request.access,
            requestedURL: request.requestedURL,
            canonicalURL: request.source.revision.identity.canonicalURL,
            requiredCoverage: .exactFile
        )
        if let workspace = request.currentWorkspace {
            try validateSnapshot(workspace, limits: request.limits, work: &work)
        }
        let project = try decode(
            request.source.data,
            format: request.format,
            projectFileURL: request.source.revision.identity.canonicalURL,
            limits: request.limits,
            work: &work
        )
        try validate(project, limits: request.limits, work: &work)
        let canonicalData = try encode(
            project,
            format: request.format,
            projectFileURL: request.source.revision.identity.canonicalURL
        )
        guard canonicalData.count <= request.limits.maximumProjectFileBytes else {
            throw ComparisonProjectWorkflowError.projectFileTooLarge(
                maximumBytes: request.limits.maximumProjectFileBytes
            )
        }
        guard canonicalData.count <= request.limits.maximumPlanBytes else {
            throw ComparisonProjectWorkflowError.planTooLarge(maximumBytes: request.limits.maximumPlanBytes)
        }
        try work.consume(UInt64(canonicalData.count))
        let canonicalDigest = try digest(canonicalData, work: &work)
        let authorityRequirements = openAuthorityRequirements(request: request, project: project)
        try validateAuthorityRequirements(authorityRequirements)
        let expectedWorkspaceCAS = try request.currentWorkspace.map {
            try snapshotCAS($0, work: &work)
        }
        try Task.checkCancellation()
        try validateRetainedPlanBytes(
            project: project,
            payloadByteCount: canonicalData.count,
            snapshotCAS: expectedWorkspaceCAS,
            destination: nil,
            sourceRevision: request.source.revision,
            authorities: authorityRequirements,
            limits: request.limits,
            work: &work
        )
        let planDigest = try openPlanDigest(
            request: request,
            canonicalDigest: canonicalDigest,
            replacement: replacement,
            expectedWorkspaceCAS: expectedWorkspaceCAS,
            authorityRequirements: authorityRequirements,
            work: &work
        )
        try Task.checkCancellation()
        return ComparisonProjectOpenPlan(
            format: request.format,
            requestedURL: request.requestedURL,
            sourceRevision: request.source.revision,
            project: project,
            canonicalProjectData: canonicalData,
            replacementPolicy: request.replacementPolicy,
            workspaceReplacement: replacement,
            authorityRequirements: authorityRequirements,
            receipt: ComparisonProjectPlanningReceipt(
                kind: .open,
                projectContentSHA256: canonicalDigest,
                planSHA256: planDigest,
                payloadByteCount: canonicalData.count,
                estimatedWorkUnits: work.consumed
            ),
            limits: request.limits,
            expectedWorkspaceCAS: expectedWorkspaceCAS
        )
    }

    private static func makeSavePlan(
        _ request: ComparisonProjectSaveRequest
    ) throws -> ComparisonProjectSavePlan {
        try Task.checkCancellation()
        try validate(request.limits)
        if request.dirtyPolicy == .requireModified, !request.snapshot.isDirty {
            throw ComparisonProjectWorkflowError.projectMustBeModified
        }
        var work = ComparisonProjectWorkflowWorkBudget(maximum: request.limits.maximumWorkUnits)
        try validate(
            request.destination,
            snapshot: request.snapshot,
            limits: request.limits,
            work: &work
        )
        try validateSnapshot(request.snapshot, limits: request.limits, work: &work)
        let snapshotCAS = try snapshotCAS(request.snapshot, work: &work)
        try Task.checkCancellation()
        let payload = try encode(
            request.snapshot.project,
            format: request.format,
            projectFileURL: request.destination.intention.canonicalURL
        )
        guard payload.count <= request.limits.maximumProjectFileBytes else {
            throw ComparisonProjectWorkflowError.projectFileTooLarge(
                maximumBytes: request.limits.maximumProjectFileBytes
            )
        }
        guard payload.count <= request.limits.maximumPlanBytes else {
            throw ComparisonProjectWorkflowError.planTooLarge(maximumBytes: request.limits.maximumPlanBytes)
        }
        try work.consume(UInt64(payload.count))
        let payloadDigest = try digest(payload, work: &work)
        let kind: ComparisonProjectPlanningReceiptKind
        let purpose: ComparisonProjectWorkflowAuthorityPurpose
        switch request.destination.intention {
        case .createNew:
            kind = .create
            purpose = .createProjectFile
        case .replaceExisting:
            kind = .replace
            purpose = .replaceProjectFile
        }
        let authorityRequirements = [
            ComparisonProjectWorkflowAuthorityRequirement(
                purpose: purpose,
                requestedURL: request.destination.requestedURL,
                canonicalURL: request.destination.intention.canonicalURL,
                requiredCoverage: .exactFile,
                access: request.destination.access
            )
        ]
        try validateAuthorityRequirements(authorityRequirements)
        try validateRetainedPlanBytes(
            project: nil,
            payloadByteCount: payload.count,
            snapshotCAS: snapshotCAS,
            destination: request.destination,
            sourceRevision: nil,
            authorities: authorityRequirements,
            limits: request.limits,
            work: &work
        )
        let planDigest = try savePlanDigest(
            request: request,
            payloadDigest: payloadDigest,
            snapshotCAS: snapshotCAS,
            authorityRequirements: authorityRequirements,
            work: &work
        )
        try Task.checkCancellation()
        return ComparisonProjectSavePlan(
            snapshot: request.snapshot,
            snapshotCAS: snapshotCAS,
            format: request.format,
            destination: request.destination,
            payload: payload,
            dirtyPolicy: request.dirtyPolicy,
            authorityRequirements: authorityRequirements,
            receipt: ComparisonProjectPlanningReceipt(
                kind: kind,
                projectContentSHA256: payloadDigest,
                planSHA256: planDigest,
                payloadByteCount: payload.count,
                estimatedWorkUnits: work.consumed
            ),
            limits: request.limits
        )
    }
}

extension ComparisonProjectWorkflowPlanner {
    fileprivate static func validate(_ limits: ComparisonProjectWorkflowLimits) throws {
        let checks: [(ComparisonProjectWorkflowLimit, Bool)] = [
            (.projectFileBytes, (1...ComparisonProjectWorkflowLimits.hardMaximumProjectFileBytes).contains(limits.maximumProjectFileBytes)),
            (.pathUTF8Bytes, (1...ComparisonProjectWorkflowLimits.hardMaximumPathUTF8Bytes).contains(limits.maximumPathUTF8Bytes)),
            (.totalPathUTF8Bytes, (1...ComparisonProjectWorkflowLimits.hardMaximumTotalPathUTF8Bytes).contains(limits.maximumTotalPathUTF8Bytes)),
            (.optionItemCount, (1...ComparisonProjectWorkflowLimits.hardMaximumOptionItemCount).contains(limits.maximumOptionItemCount)),
            (.optionStringUTF8Bytes, (1...ComparisonProjectWorkflowLimits.hardMaximumOptionStringUTF8Bytes).contains(limits.maximumOptionStringUTF8Bytes)),
            (
                .totalOptionStringUTF8Bytes,
                (1...ComparisonProjectWorkflowLimits.hardMaximumTotalOptionStringUTF8Bytes).contains(limits.maximumTotalOptionStringUTF8Bytes)
            ),
            (.planBytes, (1...ComparisonProjectWorkflowLimits.hardMaximumPlanBytes).contains(limits.maximumPlanBytes)),
            (.workUnits, limits.maximumWorkUnits > 0 && limits.maximumWorkUnits <= ComparisonProjectWorkflowLimits.hardMaximumWorkUnits)
        ]
        guard let failed = checks.first(where: { !$0.1 })?.0 else { return }
        throw ComparisonProjectWorkflowError.invalidLimit(failed)
    }

    fileprivate static func validate(
        _ revision: ComparisonProjectWorkflowFileRevision,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        try validate(
            revision.identity,
            limits: limits,
            work: &work
        )
        guard revision.byteCount <= UInt64(limits.maximumProjectFileBytes),
            revision.linkCount > 0,
            revision.permissions <= 0o7777,
            (0..<1_000_000_000).contains(revision.modificationTimeNanoseconds),
            (0..<1_000_000_000).contains(revision.statusChangeTimeNanoseconds),
            revision.contentSHA256.count == SHA256.Digest.byteCount,
            revision.metadataSHA256.count == SHA256.Digest.byteCount
        else {
            throw ComparisonProjectWorkflowError.invalidFileRevision(
                revision.identity.canonicalURL.path
            )
        }
        try work.consume(64)
    }

    fileprivate static func validate(
        _ identity: ComparisonProjectWorkflowCanonicalFileIdentity,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        try validateProjectFileURL(
            identity.canonicalURL,
            role: .canonicalProject,
            maximumPathBytes: limits.maximumPathUTF8Bytes,
            canonical: true,
            work: &work
        )
        try validateCanonicalDirectory(identity.parent, limits: limits, work: &work)
        guard identity.parent.canonicalURL.path == identity.canonicalURL.deletingLastPathComponent().path else {
            throw ComparisonProjectWorkflowError.invalidURL(
                role: .canonicalParent,
                issue: .parentMismatch
            )
        }
    }

    fileprivate static func validateCanonicalDirectory(
        _ identity: ComparisonProjectWorkflowCanonicalDirectoryIdentity,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        try validateFileURL(
            identity.canonicalURL,
            role: .canonicalParent,
            maximumPathBytes: limits.maximumPathUTF8Bytes,
            requiresFileName: false,
            canonical: true,
            work: &work
        )
    }

    fileprivate static func validate(
        _ destination: ComparisonProjectSaveDestination,
        snapshot: ComparisonProjectWorkflowSnapshot,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        try validateProjectFileURL(
            destination.requestedURL,
            role: .requestedProject,
            maximumPathBytes: limits.maximumPathUTF8Bytes,
            canonical: false,
            work: &work
        )
        switch destination.intention {
        case .createNew(let location):
            try validateProjectFileURL(
                location.canonicalURL,
                role: .canonicalProject,
                maximumPathBytes: limits.maximumPathUTF8Bytes,
                canonical: true,
                work: &work
            )
            try validateCanonicalDirectory(location.parent, limits: limits, work: &work)
            guard location.parent.canonicalURL.path == location.canonicalURL.deletingLastPathComponent().path else {
                throw ComparisonProjectWorkflowError.destinationDoesNotMatchIntention
            }
            try validateRequestedURLAttestation(
                requestedURL: destination.requestedURL,
                canonicalLocation: location,
                attestation: destination.requestedURLAttestation
            )
        case .replaceExisting(let revision):
            try validate(revision, limits: limits, work: &work)
            try validateRequestedURLAttestation(
                requestedURL: destination.requestedURL,
                canonicalIdentity: revision.identity,
                attestation: destination.requestedURLAttestation
            )
            if case .file(let binding) = snapshot.binding,
                samePath(binding.identity.canonicalURL, revision.identity.canonicalURL)
                    || binding.identity.node == revision.identity.node,
                binding.identity.parent != revision.identity.parent
                    || !sameRevisionState(binding, revision)
            {
                throw ComparisonProjectWorkflowError.replacementDoesNotMatchBinding
            }
        }
        try validateAccess(destination.access, limits: limits, work: &work)
        try validateAuthorityCoverage(
            access: destination.access,
            requestedURL: destination.requestedURL,
            canonicalURL: destination.intention.canonicalURL,
            requiredCoverage: .exactFile
        )
    }

    fileprivate static func validateSnapshot(
        _ snapshot: ComparisonProjectWorkflowSnapshot,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        try validate(snapshot.project, limits: limits, work: &work)
        if case .file(let revision) = snapshot.binding {
            try validate(revision, limits: limits, work: &work)
        }
    }

    fileprivate static func validate(
        _ project: ComparisonProjectWorkflowProject,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        guard project.sides.count == 2 || project.sides.count == 3 else {
            throw ComparisonProjectWorkflowError.invalidSideCount(project.sides.count)
        }
        var seen = Set<ComparisonProjectWorkflowSideIdentity>()
        var totalPathBytes = 0
        for side in project.sides {
            try Task.checkCancellation()
            guard seen.insert(side.identity).inserted else {
                throw ComparisonProjectWorkflowError.duplicateSide(side.identity)
            }
            let pathBytes = try validateSourceURL(
                side.fileURL,
                role: .comparisonSide(side.identity),
                limits: limits,
                work: &work
            )
            totalPathBytes = try boundedAdd(
                pathBytes,
                to: totalPathBytes,
                maximum: limits.maximumTotalPathUTF8Bytes,
                error: .optionLimitExceeded(.totalPathUTF8Bytes)
            )
            if let relativePath = side.winMergeRelativePath {
                guard ComparisonProjectWorkflowProject.isRepresentableWinMergePath(relativePath),
                    let relativeBytes = try boundedUTF8Count(
                        relativePath,
                        maximum: limits.maximumPathUTF8Bytes,
                        work: &work
                    )
                else {
                    throw ComparisonProjectWorkflowError.invalidURL(
                        role: .comparisonSide(side.identity),
                        issue: .pathTooLong
                    )
                }
                totalPathBytes = try boundedAdd(
                    relativeBytes,
                    to: totalPathBytes,
                    maximum: limits.maximumTotalPathUTF8Bytes,
                    error: .optionLimitExceeded(.totalPathUTF8Bytes)
                )
            }
        }
        let expected: Set<ComparisonProjectWorkflowSideIdentity> =
            project.sides.count == 2 ? [.left, .right] : [.left, .middle, .right]
        guard seen == expected else {
            throw ComparisonProjectWorkflowError.invalidSideSet(
                project.sides.map(\.identity).sorted { $0.sortOrder < $1.sortOrder }
            )
        }
        if case .file(let url) = project.filter {
            let pathBytes = try validateSourceURL(
                url,
                role: .filter,
                limits: limits,
                work: &work
            )
            totalPathBytes = try boundedAdd(
                pathBytes,
                to: totalPathBytes,
                maximum: limits.maximumTotalPathUTF8Bytes,
                error: .optionLimitExceeded(.totalPathUTF8Bytes)
            )
        }
        _ = totalPathBytes
        try validateOptions(project, limits: limits, work: &work)
        do {
            _ = try makeMacMergeProject(project, validatingOnly: true)
        } catch let error as ComparisonProjectError {
            throw ComparisonProjectWorkflowError.macMergeProject(error)
        }
    }

    fileprivate static func validateOptions(
        _ project: ComparisonProjectWorkflowProject,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        let maximumAtomicRegularExpressionCount = 256
        let maximumRegularExpressionUTF8Bytes = 4 * 1_024
        let options = project.lineOptions
        let itemCount = options.lineFilters.count + options.substitutions.count
        guard itemCount <= limits.maximumOptionItemCount,
            itemCount <= maximumAtomicRegularExpressionCount
        else {
            throw ComparisonProjectWorkflowError.optionLimitExceeded(.optionItemCount)
        }
        for pattern in options.lineFilters.map(\.pattern)
            + options.substitutions.map(\.pattern)
        {
            try Task.checkCancellation()
            guard
                try boundedUTF8Count(
                    pattern,
                    maximum: maximumRegularExpressionUTF8Bytes,
                    work: &work
                ) != nil
            else {
                throw ComparisonProjectWorkflowError.optionLimitExceeded(.optionStringUTF8Bytes)
            }
        }
        var totalBytes = 0
        var strings = options.lineFilters.map(\.pattern)
        strings.append(contentsOf: options.substitutions.flatMap { [$0.pattern, $0.replacement] })
        switch project.filter {
        case .named(let value), .winMergeExpression(let value): strings.append(value)
        case .file, nil: break
        }
        for string in strings {
            try Task.checkCancellation()
            guard
                let count = try boundedUTF8Count(
                    string,
                    maximum: limits.maximumOptionStringUTF8Bytes,
                    work: &work
                )
            else {
                throw ComparisonProjectWorkflowError.optionLimitExceeded(.optionStringUTF8Bytes)
            }
            totalBytes = try boundedAdd(
                count,
                to: totalBytes,
                maximum: limits.maximumTotalOptionStringUTF8Bytes,
                error: .optionLimitExceeded(.totalOptionStringUTF8Bytes)
            )
        }
    }

    fileprivate static func validateRetainedPlanBytes(
        project: ComparisonProjectWorkflowProject?,
        payloadByteCount: Int,
        snapshotCAS: ComparisonProjectWorkflowSnapshotCAS?,
        destination: ComparisonProjectSaveDestination?,
        sourceRevision: ComparisonProjectWorkflowFileRevision?,
        authorities: [ComparisonProjectWorkflowAuthorityRequirement],
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        var retainedBytes = payloadByteCount
        if let project {
            let projectBytes = try retainedByteCount(project, work: &work)
            retainedBytes = try boundedAdd(
                projectBytes,
                to: retainedBytes,
                maximum: limits.maximumPlanBytes,
                error: .planTooLarge(maximumBytes: limits.maximumPlanBytes)
            )
        }
        if let snapshotCAS {
            let snapshotBytes = try retainedByteCount(snapshotCAS, work: &work)
            retainedBytes = try boundedAdd(
                snapshotBytes,
                to: retainedBytes,
                maximum: limits.maximumPlanBytes,
                error: .planTooLarge(maximumBytes: limits.maximumPlanBytes)
            )
        }
        if let destination {
            let destinationBytes = try retainedByteCount(destination, work: &work)
            retainedBytes = try boundedAdd(
                destinationBytes,
                to: retainedBytes,
                maximum: limits.maximumPlanBytes,
                error: .planTooLarge(maximumBytes: limits.maximumPlanBytes)
            )
        }
        if let sourceRevision {
            let revisionBytes = try retainedByteCount(sourceRevision, work: &work)
            retainedBytes = try boundedAdd(
                revisionBytes,
                to: retainedBytes,
                maximum: limits.maximumPlanBytes,
                error: .planTooLarge(maximumBytes: limits.maximumPlanBytes)
            )
        }
        for authority in authorities {
            let authorityBytes = try retainedByteCount(authority, work: &work)
            retainedBytes = try boundedAdd(
                authorityBytes,
                to: retainedBytes,
                maximum: limits.maximumPlanBytes,
                error: .planTooLarge(maximumBytes: limits.maximumPlanBytes)
            )
        }
        _ = retainedBytes
    }

    fileprivate static func retainedByteCount<T: Hashable & Sendable>(
        _ value: T,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws -> Int {
        var writer = ComparisonProjectWorkflowDigestWriter(hashing: false, work: work)
        switch value {
        case let project as ComparisonProjectWorkflowProject:
            writer.add(project)
        case let snapshotCAS as ComparisonProjectWorkflowSnapshotCAS:
            writer.add(snapshotCAS)
        case let destination as ComparisonProjectSaveDestination:
            writer.add(destination)
        case let authority as ComparisonProjectWorkflowAuthorityRequirement:
            writer.add([authority])
        case let revision as ComparisonProjectWorkflowFileRevision:
            writer.add(revision)
        default:
            preconditionFailure("Unsupported retained plan value")
        }
        work = try writer.checkedWork()
        return writer.byteCount
    }

    fileprivate static func boundedUTF8Count(
        _ value: String,
        maximum: Int,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws -> Int? {
        var count = 0
        for byte in value.utf8 {
            _ = byte
            try work.consume(1)
            if count == maximum { return nil }
            count += 1
            if count.isMultiple(of: 1_024) { try Task.checkCancellation() }
        }
        return count
    }

    fileprivate static func validateAccess(
        _ access: ComparisonProjectWorkflowAccess,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        guard case .securityScoped(let resourceURL, _) = access else { return }
        try validateFileURL(
            resourceURL,
            role: .securityScope,
            maximumPathBytes: limits.maximumPathUTF8Bytes,
            requiresFileName: false,
            canonical: false,
            work: &work
        )
    }

    fileprivate static func validateAuthorityRequirements(
        _ requirements: [ComparisonProjectWorkflowAuthorityRequirement]
    ) throws {
        for requirement in requirements {
            try validateAuthorityCoverage(
                access: requirement.access,
                requestedURL: requirement.requestedURL,
                canonicalURL: requirement.canonicalURL,
                requiredCoverage: requirement.requiredCoverage
            )
        }
    }

    fileprivate static func validateAuthorityCoverage(
        access: ComparisonProjectWorkflowAccess,
        requestedURL: URL,
        canonicalURL: URL?,
        requiredCoverage: ComparisonProjectWorkflowAuthorityCoverage
    ) throws {
        guard case .securityScoped(let resourceURL, let coverage) = access else { return }
        guard coverage == .directoryTree || requiredCoverage == .exactFile else {
            throw ComparisonProjectWorkflowError.invalidURL(
                role: .securityScope,
                issue: .insufficientAuthorityCoverage
            )
        }
        let resourcePath = resourceURL.standardizedFileURL.path
        let targetPaths = Set([requestedURL, canonicalURL].compactMap { $0?.standardizedFileURL.path })
        let coversTarget: Bool
        switch coverage {
        case .exactFile:
            coversTarget = targetPaths.contains(resourcePath)
        case .directoryTree:
            let prefix = resourcePath == "/" ? "/" : resourcePath + "/"
            coversTarget = targetPaths.contains {
                $0 == resourcePath || $0.hasPrefix(prefix)
            }
        }
        guard coversTarget else {
            throw ComparisonProjectWorkflowError.invalidURL(
                role: .securityScope,
                issue: .insufficientAuthorityCoverage
            )
        }
    }

    fileprivate static func validateRequestedURLAttestation(
        requestedURL: URL,
        canonicalIdentity: ComparisonProjectWorkflowCanonicalFileIdentity,
        attestation: ComparisonProjectWorkflowRequestedURLAttestation?
    ) throws {
        if samePath(requestedURL, canonicalIdentity.canonicalURL) {
            guard
                attestation == nil
                    || attestation == .file(requestedURL: requestedURL, identity: canonicalIdentity)
            else {
                throw ComparisonProjectWorkflowError.invalidURL(
                    role: .requestedProject,
                    issue: .unattestedAlias
                )
            }
            return
        }
        guard attestation == .file(requestedURL: requestedURL, identity: canonicalIdentity) else {
            throw ComparisonProjectWorkflowError.invalidURL(
                role: .requestedProject,
                issue: .unattestedAlias
            )
        }
    }

    fileprivate static func validateRequestedURLAttestation(
        requestedURL: URL,
        canonicalLocation: ComparisonProjectWorkflowCanonicalLocation,
        attestation: ComparisonProjectWorkflowRequestedURLAttestation?
    ) throws {
        if samePath(requestedURL, canonicalLocation.canonicalURL) {
            guard
                attestation == nil
                    || attestation == .location(requestedURL: requestedURL, location: canonicalLocation)
            else {
                throw ComparisonProjectWorkflowError.invalidURL(
                    role: .requestedProject,
                    issue: .unattestedAlias
                )
            }
            return
        }
        guard attestation == .location(requestedURL: requestedURL, location: canonicalLocation) else {
            throw ComparisonProjectWorkflowError.invalidURL(
                role: .requestedProject,
                issue: .unattestedAlias
            )
        }
    }

    fileprivate static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path == rhs.path
    }

    fileprivate static func sameRevisionState(
        _ lhs: ComparisonProjectWorkflowFileRevision,
        _ rhs: ComparisonProjectWorkflowFileRevision
    ) -> Bool {
        lhs.identity.node == rhs.identity.node
            && lhs.byteCount == rhs.byteCount
            && lhs.linkCount == rhs.linkCount
            && lhs.permissions == rhs.permissions
            && lhs.ownerID == rhs.ownerID
            && lhs.groupID == rhs.groupID
            && lhs.flags == rhs.flags
            && lhs.modificationTimeSeconds == rhs.modificationTimeSeconds
            && lhs.modificationTimeNanoseconds == rhs.modificationTimeNanoseconds
            && lhs.statusChangeTimeSeconds == rhs.statusChangeTimeSeconds
            && lhs.statusChangeTimeNanoseconds == rhs.statusChangeTimeNanoseconds
            && lhs.contentSHA256 == rhs.contentSHA256
            && lhs.metadataSHA256 == rhs.metadataSHA256
    }

    fileprivate static func validateProjectFileURL(
        _ url: URL,
        role: ComparisonProjectWorkflowURLRole,
        maximumPathBytes: Int,
        canonical: Bool,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        try validateFileURL(
            url,
            role: role,
            maximumPathBytes: maximumPathBytes,
            requiresFileName: true,
            canonical: canonical,
            work: &work
        )
        guard !url.hasDirectoryPath else {
            throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .directoryURL)
        }
    }

    @discardableResult
    fileprivate static func validateSourceURL(
        _ url: URL,
        role: ComparisonProjectWorkflowURLRole,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws -> Int {
        try validateFileURL(
            url,
            role: role,
            maximumPathBytes: limits.maximumPathUTF8Bytes,
            requiresFileName: true,
            canonical: false,
            work: &work
        )
        return url.path.utf8.count
    }

    fileprivate static func validateFileURL(
        _ url: URL,
        role: ComparisonProjectWorkflowURLRole,
        maximumPathBytes: Int,
        requiresFileName: Bool,
        canonical: Bool,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        try Task.checkCancellation()
        let maximumSerializedBytes = maximumPathBytes * 3 + 32
        var serializedBytes = [UInt8](repeating: 0, count: maximumSerializedBytes + 1)
        let serializedCount = CFURLGetBytes(
            url as CFURL,
            &serializedBytes,
            serializedBytes.count
        )
        guard serializedCount >= 0, serializedCount <= maximumSerializedBytes else {
            throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .pathTooLong)
        }
        let serialized = String(decoding: serializedBytes[..<serializedCount], as: UTF8.self)
        try work.consume(UInt64(serializedCount))
        guard url.isFileURL else {
            throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .notFileURL)
        }
        guard url.baseURL == nil, url.path.hasPrefix("/") else {
            throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .relativeURL)
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.host == nil || components.host == ""
        else {
            throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .remoteHost)
        }
        guard components.user == nil, components.password == nil, components.port == nil else {
            throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .credentialsOrPort)
        }
        guard url.query == nil, url.fragment == nil else {
            throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .queryOrFragment)
        }
        guard !url.path.utf8.contains(0) else {
            throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .nullByte)
        }
        guard
            let pathBytes = try boundedUTF8Count(
                url.path,
                maximum: maximumPathBytes,
                work: &work
            )
        else {
            throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .pathTooLong)
        }
        if requiresFileName {
            guard url.path != "/", url.lastPathComponent != ".", url.lastPathComponent != ".." else {
                throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .missingFileName)
            }
        }
        if canonical {
            let standardized = url.standardizedFileURL.path
            let rebuilt = URL(
                fileURLWithPath: url.path,
                isDirectory: url.hasDirectoryPath
            ).absoluteString
            guard standardized == url.path,
                !url.path.contains("//"),
                rebuilt == serialized
            else {
                throw ComparisonProjectWorkflowError.invalidURL(role: role, issue: .notCanonical)
            }
        }
        _ = pathBytes
    }

    fileprivate static func workspaceReplacement(
        _ workspace: ComparisonProjectWorkflowSnapshot?,
        policy: ComparisonProjectOpenReplacementPolicy
    ) throws -> ComparisonProjectWorkspaceReplacementReceipt {
        guard let workspace else { return .noWorkspace }
        switch policy {
        case .requireEmptyWorkspace:
            throw ComparisonProjectWorkflowError.workspaceAlreadyOpen
        case .replaceIfClean:
            guard !workspace.isDirty else {
                throw ComparisonProjectWorkflowError.dirtyWorkspaceRequiresReplacementApproval
            }
            return .replacedClean(ComparisonProjectWorkflowSnapshotReference(workspace))
        case .discardChangesAndReplace:
            let reference = ComparisonProjectWorkflowSnapshotReference(workspace)
            return workspace.isDirty ? .discardedChanges(reference) : .replacedClean(reference)
        }
    }

    fileprivate static func decode(
        _ data: Data,
        format: ComparisonProjectWorkflowFormat,
        projectFileURL: URL,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws -> ComparisonProjectWorkflowProject {
        try Task.checkCancellation()
        try preflightDecode(data, format: format, limits: limits, work: &work)
        switch format {
        case .macMerge:
            do {
                let project = try JSONDecoder().decode(ComparisonProject.self, from: data)
                return try ComparisonProjectWorkflowProject(
                    macMerge: project,
                    relativeTo: projectFileURL
                )
            } catch let error as ComparisonProjectError {
                throw ComparisonProjectWorkflowError.macMergeProject(error)
            } catch {
                throw ComparisonProjectWorkflowError.invalidMacMergeProject
            }
        case .winMerge:
            do {
                return try ComparisonProjectWorkflowProject(
                    winMerge: WinMergeProjectFile.parse(data),
                    relativeTo: projectFileURL
                )
            } catch let diagnostic as WinMergeProjectFileDiagnostic {
                throw ComparisonProjectWorkflowError.winMergeProject(diagnostic)
            }
        }
    }

    fileprivate static func preflightDecode(
        _ data: Data,
        format: ComparisonProjectWorkflowFormat,
        limits: ComparisonProjectWorkflowLimits,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws {
        guard data.count <= limits.maximumProjectFileBytes else {
            throw ComparisonProjectWorkflowError.projectFileTooLarge(
                maximumBytes: limits.maximumProjectFileBytes
            )
        }
        let maximumStructuralDepth = 64
        let maximumStructuralTokens = min(
            1_000_000,
            limits.maximumOptionItemCount * 16 + 4_096
        )
        var depth = 0
        var maximumDepth = 0
        var structuralTokens = 0
        var inString = false
        var escaped = false
        var index = 0
        for byte in data {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            index += 1
            try work.consume(1)
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }
            if byte == 0x22 {
                inString = true
                continue
            }
            switch format {
            case .macMerge:
                if byte == 0x7B || byte == 0x5B {
                    depth += 1
                    maximumDepth = max(maximumDepth, depth)
                } else if byte == 0x7D || byte == 0x5D {
                    depth -= 1
                    guard depth >= 0 else {
                        throw ComparisonProjectWorkflowError.invalidMacMergeProject
                    }
                }
                if byte == 0x7B || byte == 0x5B || byte == 0x2C || byte == 0x3A {
                    structuralTokens += 1
                }
            case .winMerge:
                break
            }
            guard maximumDepth <= maximumStructuralDepth,
                structuralTokens <= maximumStructuralTokens
            else {
                throw ComparisonProjectWorkflowError.invalidMacMergeProject
            }
        }
        if format == .macMerge, depth != 0 || inString || escaped {
            throw ComparisonProjectWorkflowError.invalidMacMergeProject
        }
    }

    fileprivate static func encode(
        _ project: ComparisonProjectWorkflowProject,
        format: ComparisonProjectWorkflowFormat,
        projectFileURL: URL
    ) throws -> Data {
        try Task.checkCancellation()
        do {
            switch format {
            case .macMerge:
                guard project.winMergeOptions.ignoreCodepageDifferences != true,
                    project.winMergeOptions.ignoreMissingTrailingEndOfLine != true,
                    project.winMergeOptions.ignoreLineBreaks != true,
                    project.winMergeOptions.compareMethodRawValue == nil
                        || project.winMergeOptions.compareMethodRawValue
                            == WinMergeProjectFile.CompareMethod.fullContents.rawValue
                else {
                    throw ComparisonProjectWorkflowError.formatCannotRepresentProject(.macMerge)
                }
                return try makeMacMergeProject(project).encodedData(relativeTo: projectFileURL)
            case .winMerge:
                return try makeWinMergeProject(
                    project,
                    projectFileURL: projectFileURL
                ).serializedData()
            }
        } catch let error as ComparisonProjectError {
            throw ComparisonProjectWorkflowError.macMergeProject(error)
        } catch let diagnostic as WinMergeProjectFileDiagnostic {
            throw ComparisonProjectWorkflowError.winMergeProject(diagnostic)
        }
    }

    fileprivate static func makeMacMergeProject(
        _ project: ComparisonProjectWorkflowProject,
        validatingOnly: Bool = false
    ) throws -> ComparisonProject {
        let sides = try project.sides.map {
            try ComparisonProject.Side(
                identity: $0.identity.comparisonProjectIdentity,
                path: $0.fileURL,
                readOnly: $0.readOnly
            )
        }
        let filter: ComparisonProject.FilterReference?
        switch project.filter {
        case .named(let name): filter = .named(name)
        case .file(let url): filter = .file(url)
        case .winMergeExpression:
            guard validatingOnly else {
                throw ComparisonProjectWorkflowError.formatCannotRepresentProject(.macMerge)
            }
            filter = nil
        case nil: filter = nil
        }
        return try ComparisonProject(
            mode: project.mode.comparisonProjectMode,
            sides: sides,
            recursive: project.recursive,
            filter: filter,
            lineDiffOptions: project.lineOptions.lineDiffOptions
        )
    }

    fileprivate static func makeWinMergeProject(
        _ project: ComparisonProjectWorkflowProject,
        projectFileURL: URL
    ) throws -> WinMergeProjectFile {
        guard project.lineOptions.algorithm == .default,
            !project.lineOptions.indentHeuristic,
            !project.lineOptions.detectMovedBlocks,
            project.lineOptions.lineFiltersEnabled,
            project.lineOptions.lineFilters.isEmpty,
            project.lineOptions.substitutionsEnabled,
            project.lineOptions.substitutions.isEmpty
        else {
            throw ComparisonProjectWorkflowError.formatCannotRepresentProject(.winMerge)
        }
        guard let left = project.sides.first(where: { $0.identity == .left }),
            let right = project.sides.first(where: { $0.identity == .right })
        else {
            throw ComparisonProjectWorkflowError.invalidSideSet(project.sides.map(\.identity))
        }
        let middle = project.sides.first(where: { $0.identity == .middle })
        let compareMethod: WinMergeProjectFile.CompareMethod?
        if let rawValue = project.winMergeOptions.compareMethodRawValue {
            guard let value = WinMergeProjectFile.CompareMethod(rawValue: rawValue),
                value == .fullContents
            else {
                throw ComparisonProjectWorkflowError.unsupportedWinMergeCompareMethod(rawValue)
            }
            compareMethod = value
        } else {
            compareMethod = nil
        }
        let filter: String?
        switch project.filter {
        case .winMergeExpression(let expression): filter = expression
        case .named:
            throw ComparisonProjectWorkflowError.formatCannotRepresentProject(.winMerge)
        case .file:
            throw ComparisonProjectWorkflowError.formatCannotRepresentProject(.winMerge)
        case nil: filter = nil
        }
        let retained = project.winMergeOptions
        guard retained.ignoreCodepageDifferences != true,
            retained.ignoreMissingTrailingEndOfLine != true,
            retained.ignoreLineBreaks != true
        else {
            throw ComparisonProjectWorkflowError.unsupportedWinMergeTextSemantics
        }
        guard !project.recursive || project.mode == .folder else {
            throw ComparisonProjectWorkflowError.formatCannotRepresentProject(.winMerge)
        }
        let windowType = project.mode.winMergeWindowType
        let whitespaceHandling = serializedOption(
            project.lineOptions.whitespace.winMergeWhitespace,
            defaultValue: .compare,
            preservedPresence: retained.preservesSerializedOptionPresence
                && retained.whitespaceHandlingRawValue != nil
        )
        let includesSubfolders: Bool?
        switch project.mode {
        case .folder:
            includesSubfolders = project.recursive
        case .automatic:
            includesSubfolders = nil
        default:
            includesSubfolders =
                retained.preservesSerializedOptionPresence
                ? retained.includesSubfolders
                : nil
        }
        return try WinMergeProjectFile(
            leftPath: winMergePath(for: left, relativeTo: projectFileURL),
            middlePath: try middle.map { try winMergePath(for: $0, relativeTo: projectFileURL) },
            rightPath: winMergePath(for: right, relativeTo: projectFileURL),
            filter: filter,
            includesSubfolders: includesSubfolders,
            leftReadOnly: left.readOnly,
            middleReadOnly: middle?.readOnly ?? false,
            rightReadOnly: right.readOnly,
            options: WinMergeProjectFile.Options(
                windowType: windowType,
                whitespaceHandling: whitespaceHandling,
                ignoreBlankLines: serializedOption(
                    project.lineOptions.ignoreBlankLines,
                    defaultValue: false,
                    preservedPresence: retained.preservesSerializedOptionPresence
                        && retained.ignoreBlankLines != nil
                ),
                ignoreCase: serializedOption(
                    project.lineOptions.ignoreCase,
                    defaultValue: false,
                    preservedPresence: retained.preservesSerializedOptionPresence
                        && retained.ignoreCase != nil
                ),
                ignoreCarriageReturnDifferences: serializedOption(
                    project.lineOptions.ignoreLineEndings,
                    defaultValue: true,
                    preservedPresence: retained.preservesSerializedOptionPresence
                        && retained.ignoreCarriageReturnDifferences != nil
                ),
                ignoreNumbers: serializedOption(
                    project.lineOptions.ignoreNumbers,
                    defaultValue: false,
                    preservedPresence: retained.preservesSerializedOptionPresence
                        && retained.ignoreNumbers != nil
                ),
                ignoreCodepageDifferences: project.winMergeOptions.ignoreCodepageDifferences,
                ignoreCommentDifferences: serializedOption(
                    project.lineOptions.ignoreComments,
                    defaultValue: false,
                    preservedPresence: retained.preservesSerializedOptionPresence
                        && retained.ignoreCommentDifferences != nil
                ),
                ignoreMissingTrailingEndOfLine: project.winMergeOptions.ignoreMissingTrailingEndOfLine,
                ignoreLineBreaks: project.winMergeOptions.ignoreLineBreaks,
                compareMethod: compareMethod
            )
        )
    }

    fileprivate static func serializedOption<T: Equatable>(
        _ value: T,
        defaultValue: T,
        preservedPresence: Bool
    ) -> T? {
        preservedPresence || value != defaultValue ? value : nil
    }

    fileprivate static func winMergePath(
        for side: ComparisonProjectWorkflowSide,
        relativeTo projectFileURL: URL
    ) throws -> String {
        guard let originalRelativePath = side.winMergeRelativePath else { return side.fileURL.path }
        let directoryURL = projectFileURL.deletingLastPathComponent()
        let resolved = try ComparisonProjectWorkflowProject.resolveWinMergePath(
            originalRelativePath,
            relativeTo: directoryURL
        ).url
        guard resolved.standardizedFileURL.path == side.fileURL.standardizedFileURL.path else {
            return relativeWinMergePath(from: directoryURL, to: side.fileURL)
                ?? side.fileURL.path
        }
        return originalRelativePath
    }

    fileprivate static func relativeWinMergePath(from directoryURL: URL, to targetURL: URL) -> String? {
        let base = directoryURL.standardizedFileURL.pathComponents
        let target = targetURL.standardizedFileURL.pathComponents
        guard base.first == target.first else { return nil }
        var common = 0
        while common < base.count, common < target.count, base[common] == target[common] {
            common += 1
        }
        let components =
            Array(repeating: "..", count: base.count - common)
            + target.dropFirst(common)
        guard !components.isEmpty else { return nil }
        let relativePath = components.joined(separator: "/")
        return ComparisonProjectWorkflowProject.isRepresentableWinMergePath(relativePath)
            ? relativePath
            : nil
    }

    fileprivate static func openAuthorityRequirements(
        request: ComparisonProjectOpenRequest,
        project: ComparisonProjectWorkflowProject
    ) -> [ComparisonProjectWorkflowAuthorityRequirement] {
        var requirements = [
            ComparisonProjectWorkflowAuthorityRequirement(
                purpose: .readProjectFile,
                requestedURL: request.requestedURL,
                canonicalURL: request.source.revision.identity.canonicalURL,
                requiredCoverage: .exactFile,
                access: request.access
            )
        ]
        requirements.append(
            contentsOf: project.sides.sorted {
                $0.identity.sortOrder < $1.identity.sortOrder
            }.map {
                ComparisonProjectWorkflowAuthorityRequirement(
                    purpose: .readComparisonSource($0.identity),
                    requestedURL: $0.fileURL,
                    requiredCoverage: project.mode == .folder || project.mode == .automatic
                        ? .directoryTree
                        : .exactFile,
                    access: .callerManagedWhenRequired
                )
            })
        if case .file(let filterURL) = project.filter {
            requirements.append(
                ComparisonProjectWorkflowAuthorityRequirement(
                    purpose: .readProjectFilter,
                    requestedURL: filterURL,
                    requiredCoverage: .exactFile,
                    access: .callerManagedWhenRequired
                )
            )
        }
        return requirements
    }

    fileprivate static func digest(
        _ data: Data,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws -> [UInt8] {
        var hasher = SHA256()
        let chunkSize = 64 * 1_024
        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            let end = min(offset + chunkSize, data.count)
            hasher.update(data: data[offset..<end])
            try work.consume(UInt64(end - offset))
            offset = end
        }
        return Array(hasher.finalize())
    }

    fileprivate static func openPlanDigest(
        request: ComparisonProjectOpenRequest,
        canonicalDigest: [UInt8],
        replacement: ComparisonProjectWorkspaceReplacementReceipt,
        expectedWorkspaceCAS: ComparisonProjectWorkflowSnapshotCAS?,
        authorityRequirements: [ComparisonProjectWorkflowAuthorityRequirement],
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws -> [UInt8] {
        var writer = ComparisonProjectWorkflowDigestWriter(work: work)
        writer.add("ComparisonProjectWorkflow.Open.v4")
        writer.add(request.format.rawValue)
        writer.add(request.requestedURL.absoluteString)
        writer.add(request.source.revision)
        switch request.requestedURLAttestation {
        case .file(let requestedURL, let identity):
            writer.add(UInt8(1))
            writer.add(requestedURL.absoluteString)
            writer.add(identity)
        case .location(let requestedURL, let location):
            writer.add(UInt8(2))
            writer.add(requestedURL.absoluteString)
            writer.add(location.canonicalURL.absoluteString)
            writer.add(location.parent)
        case nil:
            writer.add(UInt8(0))
        }
        writer.add(canonicalDigest)
        writer.add(request.replacementPolicy.rawValue)
        writer.add(replacement)
        if let expectedWorkspaceCAS {
            writer.add(UInt8(1))
            writer.add(expectedWorkspaceCAS)
        } else {
            writer.add(UInt8(0))
        }
        writer.add(authorityRequirements)
        writer.add(request.limits)
        work = try writer.checkedWork()
        return writer.finalize()
    }

    fileprivate static func savePlanDigest(
        request: ComparisonProjectSaveRequest,
        payloadDigest: [UInt8],
        snapshotCAS: ComparisonProjectWorkflowSnapshotCAS,
        authorityRequirements: [ComparisonProjectWorkflowAuthorityRequirement],
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws -> [UInt8] {
        var writer = ComparisonProjectWorkflowDigestWriter(work: work)
        writer.add("ComparisonProjectWorkflow.Save.v4")
        writer.add(snapshotCAS)
        writer.add(request.format.rawValue)
        writer.add(request.destination)
        writer.add(request.dirtyPolicy.rawValue)
        writer.add(payloadDigest)
        writer.add(authorityRequirements)
        writer.add(request.limits)
        work = try writer.checkedWork()
        return writer.finalize()
    }

    fileprivate static func snapshotCAS(
        _ snapshot: ComparisonProjectWorkflowSnapshot,
        work: inout ComparisonProjectWorkflowWorkBudget
    ) throws -> ComparisonProjectWorkflowSnapshotCAS {
        var writer = ComparisonProjectWorkflowDigestWriter(work: work)
        writer.add("ComparisonProjectWorkflow.Snapshot.v1")
        writer.add(snapshot)
        work = try writer.checkedWork()
        return ComparisonProjectWorkflowSnapshotCAS(
            reference: ComparisonProjectWorkflowSnapshotReference(snapshot),
            stateSHA256: writer.finalize()
        )
    }

    fileprivate static func boundedAdd(
        _ value: Int,
        to total: Int,
        maximum: Int,
        error: ComparisonProjectWorkflowError
    ) throws -> Int {
        let (result, overflow) = total.addingReportingOverflow(value)
        guard !overflow, result <= maximum else { throw error }
        return result
    }
}

private struct ComparisonProjectWorkflowWorkBudget {
    let maximum: UInt64
    fileprivate(set) var consumed: UInt64 = 0

    mutating func consume(_ units: UInt64) throws {
        let (next, overflow) = consumed.addingReportingOverflow(units)
        guard !overflow, next <= maximum else {
            throw ComparisonProjectWorkflowError.workLimitExceeded(maximumUnits: maximum)
        }
        consumed = next
    }

}

private struct ComparisonProjectWorkflowDigestWriter {
    private var hasher: SHA256?
    private(set) var byteCount = 0
    private(set) var work: ComparisonProjectWorkflowWorkBudget?
    private var exhausted = false

    init(
        hashing: Bool = true,
        work: ComparisonProjectWorkflowWorkBudget? = nil
    ) {
        hasher = hashing ? SHA256() : nil
        self.work = work
    }

    mutating func finalize() -> [UInt8] {
        guard let hasher else { return [] }
        return Array(hasher.finalize())
    }

    func checkedWork() throws -> ComparisonProjectWorkflowWorkBudget {
        guard let work else {
            preconditionFailure("Digest writer has no work budget")
        }
        guard work.consumed <= work.maximum else {
            throw ComparisonProjectWorkflowError.workLimitExceeded(maximumUnits: work.maximum)
        }
        return work
    }

    private mutating func append<D: DataProtocol>(_ bytes: D) {
        guard consume(bytes.count) else { return }
        byteCount += bytes.count
        guard var hasher else { return }
        hasher.update(data: bytes)
        self.hasher = hasher
    }

    private mutating func append(_ bytes: UnsafeRawBufferPointer) {
        guard consume(bytes.count) else { return }
        byteCount += bytes.count
        guard var hasher else { return }
        hasher.update(bufferPointer: bytes)
        self.hasher = hasher
    }

    mutating func add(_ value: Bool) {
        add(value ? UInt8(1) : UInt8(0))
    }

    mutating func add<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { append($0) }
    }

    mutating func add(_ value: String) {
        guard !exhausted else { return }
        add(UInt64(value.utf8.count))
        guard consume(value.utf8.count) else { return }
        byteCount += value.utf8.count
        guard var hasher else { return }
        value.utf8.withContiguousStorageIfAvailable {
            hasher.update(bufferPointer: UnsafeRawBufferPointer($0))
        }
            ?? {
                for byte in value.utf8 {
                    withUnsafeBytes(of: byte) { hasher.update(bufferPointer: $0) }
                }
            }()
        self.hasher = hasher
    }

    private mutating func consume(_ count: Int) -> Bool {
        guard !exhausted else { return false }
        guard var work else { return true }
        let units = UInt64(count)
        let (next, overflow) = work.consumed.addingReportingOverflow(units)
        guard !overflow, next <= work.maximum else {
            work.consumed = work.maximum + 1
            self.work = work
            exhausted = true
            return false
        }
        work.consumed = next
        self.work = work
        return true
    }

    mutating func add(_ value: [UInt8]) {
        add(UInt64(value.count))
        value.withUnsafeBytes { append($0) }
    }

    mutating func add(_ value: ComparisonProjectWorkflowNodeIdentity) {
        add(value.deviceID)
        add(value.fileID)
        add(value.generation)
    }

    mutating func add(_ value: ComparisonProjectWorkflowCanonicalDirectoryIdentity) {
        add(value.canonicalURL.absoluteString)
        add(value.node)
    }

    mutating func add(_ value: ComparisonProjectWorkflowCanonicalFileIdentity) {
        add(value.canonicalURL.absoluteString)
        add(value.parent)
        add(value.node)
    }

    mutating func add(_ value: ComparisonProjectWorkflowFileRevision) {
        add(value.identity)
        add(value.byteCount)
        add(value.linkCount)
        add(value.permissions)
        add(value.ownerID)
        add(value.groupID)
        add(value.flags)
        add(value.modificationTimeSeconds)
        add(value.modificationTimeNanoseconds)
        add(value.statusChangeTimeSeconds)
        add(value.statusChangeTimeNanoseconds)
        add(value.contentSHA256)
        add(value.metadataSHA256)
    }

    mutating func add(_ value: ComparisonProjectWorkflowProject) {
        guard !exhausted else { return }
        add(value.mode.rawValue)
        add(UInt64(value.sides.count))
        for side in value.sides {
            guard !exhausted else { return }
            add(side.identity.rawValue)
            add(side.fileURL.absoluteString)
            add(side.readOnly)
            if let path = side.winMergeRelativePath {
                add(UInt8(1))
                add(path)
            } else {
                add(UInt8(0))
            }
        }
        add(value.recursive)
        switch value.filter {
        case .named(let name):
            add(UInt8(1))
            add(name)
        case .file(let url):
            add(UInt8(2))
            add(url.absoluteString)
        case .winMergeExpression(let expression):
            add(UInt8(3))
            add(expression)
        case nil:
            add(UInt8(0))
        }
        let options = value.lineOptions
        add(options.algorithm.rawValue)
        add(options.whitespace.rawValue)
        add(options.ignoreCase)
        add(options.ignoreNumbers)
        add(options.ignoreBlankLines)
        add(options.ignoreComments)
        add(options.ignoreLineEndings)
        add(options.indentHeuristic)
        add(options.detectMovedBlocks)
        add(options.lineFiltersEnabled)
        add(UInt64(options.lineFilters.count))
        for rule in options.lineFilters {
            guard !exhausted else { return }
            add(rule.pattern)
            add(rule.caseSensitive)
        }
        add(options.substitutionsEnabled)
        add(UInt64(options.substitutions.count))
        for rule in options.substitutions {
            guard !exhausted else { return }
            add(rule.pattern)
            add(rule.replacement)
            add(rule.caseSensitive)
        }
        let retained = value.winMergeOptions
        add(retained.preservesSerializedOptionPresence)
        addOptional(retained.windowTypeRawValue)
        addOptional(retained.includesSubfolders)
        addOptional(retained.whitespaceHandlingRawValue)
        addOptional(retained.ignoreBlankLines)
        addOptional(retained.ignoreCase)
        addOptional(retained.ignoreCarriageReturnDifferences)
        addOptional(retained.ignoreNumbers)
        addOptional(retained.ignoreCodepageDifferences)
        addOptional(retained.ignoreCommentDifferences)
        addOptional(retained.ignoreMissingTrailingEndOfLine)
        addOptional(retained.ignoreLineBreaks)
        addOptional(retained.compareMethodRawValue)
    }

    mutating func add(_ value: ComparisonProjectWorkflowSnapshot) {
        add(value.identity.rawValue.uuidString.lowercased())
        add(value.generation)
        add(value.project)
        switch value.binding {
        case .untitled:
            add(UInt8(0))
        case .file(let revision):
            add(UInt8(1))
            add(revision)
        }
        add(value.isDirty)
    }

    mutating func add(_ value: ComparisonProjectWorkspaceReplacementReceipt) {
        switch value {
        case .noWorkspace:
            add(UInt8(0))
        case .replacedClean(let reference):
            add(UInt8(1))
            add(reference)
        case .discardedChanges(let reference):
            add(UInt8(2))
            add(reference)
        }
    }

    mutating func add(_ value: ComparisonProjectWorkflowSnapshotReference) {
        add(value.identity.rawValue.uuidString.lowercased())
        add(value.generation)
    }

    mutating func add(_ value: ComparisonProjectWorkflowSnapshotCAS) {
        add(value.reference)
        add(value.stateSHA256)
    }

    mutating func add(_ value: ComparisonProjectSaveDestination) {
        add(value.requestedURL.absoluteString)
        switch value.intention {
        case .createNew(let location):
            add(UInt8(0))
            add(location.canonicalURL.absoluteString)
            add(location.parent)
        case .replaceExisting(let revision):
            add(UInt8(1))
            add(revision)
        }
        switch value.requestedURLAttestation {
        case .file(let requestedURL, let identity):
            add(UInt8(1))
            add(requestedURL.absoluteString)
            add(identity)
        case .location(let requestedURL, let location):
            add(UInt8(2))
            add(requestedURL.absoluteString)
            add(location.canonicalURL.absoluteString)
            add(location.parent)
        case nil:
            add(UInt8(0))
        }
        add(value.access)
    }

    mutating func add(_ value: ComparisonProjectWorkflowLimits) {
        add(Int64(value.maximumProjectFileBytes))
        add(Int64(value.maximumPathUTF8Bytes))
        add(Int64(value.maximumTotalPathUTF8Bytes))
        add(Int64(value.maximumOptionItemCount))
        add(Int64(value.maximumOptionStringUTF8Bytes))
        add(Int64(value.maximumTotalOptionStringUTF8Bytes))
        add(Int64(value.maximumPlanBytes))
        add(value.maximumWorkUnits)
    }

    mutating func add(_ value: ComparisonProjectWorkflowAccess) {
        switch value {
        case .ambient:
            add(UInt8(0))
        case .callerManagedWhenRequired:
            add(UInt8(1))
        case .securityScoped(let resourceURL, let coverage):
            add(UInt8(2))
            add(resourceURL.absoluteString)
            add(coverage.rawValue)
        }
    }

    mutating func add(_ values: [ComparisonProjectWorkflowAuthorityRequirement]) {
        guard !exhausted else { return }
        add(UInt64(values.count))
        for value in values {
            guard !exhausted else { return }
            switch value.purpose {
            case .readProjectFile: add(UInt8(0))
            case .readComparisonSource(let side):
                add(UInt8(1))
                add(side.rawValue)
            case .readProjectFilter: add(UInt8(2))
            case .createProjectFile: add(UInt8(3))
            case .replaceProjectFile: add(UInt8(4))
            }
            add(value.requestedURL.absoluteString)
            if let canonicalURL = value.canonicalURL {
                add(UInt8(1))
                add(canonicalURL.absoluteString)
            } else {
                add(UInt8(0))
            }
            add(value.requiredCoverage.rawValue)
            add(value.access)
        }
    }

    mutating func addOptional(_ value: Bool?) {
        guard let value else {
            add(UInt8(0))
            return
        }
        add(UInt8(1))
        add(value)
    }

    mutating func addOptional(_ value: Int?) {
        guard let value else {
            add(UInt8(0))
            return
        }
        add(UInt8(1))
        add(Int64(value))
    }
}

extension ComparisonProjectWorkflowMode {
    fileprivate init(_ mode: ComparisonProject.Mode) {
        self = Self(rawValue: mode.rawValue) ?? .automatic
    }

    fileprivate init(_ windowType: WinMergeProjectFile.WindowType?) {
        switch windowType {
        case .text: self = .text
        case .table: self = .table
        case .binary: self = .binary
        case .image: self = .image
        case .webpage: self = .webpage
        case nil: self = .automatic
        }
    }

    fileprivate var comparisonProjectMode: ComparisonProject.Mode {
        ComparisonProject.Mode(rawValue: rawValue) ?? .automatic
    }

    fileprivate var winMergeWindowType: WinMergeProjectFile.WindowType? {
        switch self {
        case .automatic, .folder: nil
        case .text: .text
        case .table: .table
        case .binary: .binary
        case .image: .image
        case .webpage: .webpage
        }
    }
}

extension ComparisonProjectWorkflowSideIdentity {
    fileprivate init(_ identity: ComparisonProject.Side.Identity) {
        self = Self(rawValue: identity.rawValue) ?? .left
    }

    fileprivate var comparisonProjectIdentity: ComparisonProject.Side.Identity {
        ComparisonProject.Side.Identity(rawValue: rawValue) ?? .left
    }
}

extension ComparisonProjectWorkflowLineOptions {
    fileprivate init(_ options: LineDiffOptions) {
        algorithm = ComparisonProjectWorkflowDiffAlgorithm(rawValue: options.algorithm.rawValue) ?? .default
        whitespace = ComparisonProjectWorkflowWhitespace(rawValue: options.whitespace.rawValue) ?? .compareAll
        ignoreCase = options.ignoreCase
        ignoreNumbers = options.ignoreNumbers
        ignoreBlankLines = options.ignoreBlankLines
        ignoreComments = options.ignoreComments
        ignoreLineEndings = options.ignoreLineEndings
        indentHeuristic = options.indentHeuristic
        detectMovedBlocks = options.detectMovedBlocks
        lineFiltersEnabled = options.lineFiltersEnabled
        lineFilters = options.lineFilters.map {
            ComparisonProjectWorkflowLineFilter(
                pattern: $0.pattern,
                caseSensitive: $0.caseSensitive
            )
        }
        substitutionsEnabled = options.substitutionsEnabled
        substitutions = options.substitutions.map {
            ComparisonProjectWorkflowSubstitution(
                pattern: $0.pattern,
                replacement: $0.replacement,
                caseSensitive: $0.caseSensitive
            )
        }
    }

    fileprivate init(_ options: WinMergeProjectFile.Options) {
        algorithm = .default
        switch options.whitespaceHandling {
        case .compare, nil: whitespace = .compareAll
        case .ignoreChanges: whitespace = .ignoreChanges
        case .ignoreAll: whitespace = .ignoreAll
        }
        ignoreCase = options.ignoreCase ?? false
        ignoreNumbers = options.ignoreNumbers ?? false
        ignoreBlankLines = options.ignoreBlankLines ?? false
        ignoreComments = options.ignoreCommentDifferences ?? false
        ignoreLineEndings = options.ignoreCarriageReturnDifferences ?? true
        indentHeuristic = false
        detectMovedBlocks = false
        lineFiltersEnabled = true
        lineFilters = []
        substitutionsEnabled = true
        substitutions = []
    }

    fileprivate var lineDiffOptions: LineDiffOptions {
        LineDiffOptions(
            algorithm: DiffAlgorithm(rawValue: algorithm.rawValue) ?? .default,
            whitespace: WhitespaceComparison(rawValue: whitespace.rawValue) ?? .compareAll,
            ignoreCase: ignoreCase,
            ignoreNumbers: ignoreNumbers,
            ignoreBlankLines: ignoreBlankLines,
            ignoreComments: ignoreComments,
            ignoreLineEndings: ignoreLineEndings,
            indentHeuristic: indentHeuristic,
            detectMovedBlocks: detectMovedBlocks,
            lineFiltersEnabled: lineFiltersEnabled,
            lineFilters: lineFilters.map {
                LineFilterRule(pattern: $0.pattern, caseSensitive: $0.caseSensitive)
            },
            substitutionsEnabled: substitutionsEnabled,
            substitutions: substitutions.map {
                SubstitutionRule(
                    pattern: $0.pattern,
                    replacement: $0.replacement,
                    caseSensitive: $0.caseSensitive
                )
            }
        )
    }
}

extension ComparisonProjectWorkflowWhitespace {
    fileprivate init(_ whitespace: WinMergeProjectFile.WhitespaceHandling?) {
        switch whitespace {
        case .compare, nil: self = .compareAll
        case .ignoreChanges: self = .ignoreChanges
        case .ignoreAll: self = .ignoreAll
        }
    }

    fileprivate var winMergeWhitespace: WinMergeProjectFile.WhitespaceHandling {
        switch self {
        case .compareAll: .compare
        case .ignoreChanges: .ignoreChanges
        case .ignoreAll: .ignoreAll
        }
    }
}
