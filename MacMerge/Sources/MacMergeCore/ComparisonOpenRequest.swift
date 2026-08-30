import CXDiff
import Foundation

/// Stable identity for one immutable open request.
///
/// Consumers must create a new identity whenever user input changes. A completed plan can then be
/// rejected instead of publishing work for an older request.
public struct ComparisonOpenRequestIdentity: Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum ComparisonOpenSidePosition: String, CaseIterable, Equatable, Hashable, Sendable {
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

/// Input origin only. The planner never reads a URL, resolves a symbolic link, or loads a webpage.
public enum ComparisonOpenSource: Equatable, Sendable {
    /// A caller-declared regular file. Its existence and type remain materialization requirements.
    case localFile(URL)
    /// A caller-declared directory. Its existence and type remain materialization requirements.
    case localFolder(URL)
    case scratchpad(text: String, label: String? = nil)
    /// Clipboard snapshots use the bounded, immutable representation from `ClipboardComparison`.
    case clipboard(ClipboardSnapshot)
    /// A remote HTML origin. MacMergeCore does not load this URL or access the network.
    case remoteWebPage(URL)

    /// Safe for logs and validation messages. It intentionally omits paths, hosts, queries, and IDs.
    public var redactedDescription: String {
        switch self {
        case .localFile:
            "<local-file>"
        case .localFolder:
            "<local-folder>"
        case .scratchpad:
            "<scratchpad>"
        case .clipboard:
            "<clipboard-snapshot>"
        case .remoteWebPage:
            "<remote-webpage>"
        }
    }
}

public struct ComparisonOpenSide: Equatable, Sendable {
    public let position: ComparisonOpenSidePosition
    public let source: ComparisonOpenSource
    public let readOnly: Bool

    public init(
        position: ComparisonOpenSidePosition,
        source: ComparisonOpenSource,
        readOnly: Bool = false
    ) {
        self.position = position
        self.source = source
        self.readOnly = readOnly
    }
}

public enum ComparisonOpenModeSelection: Equatable, Sendable {
    case inferred
    /// `.automatic` is not an explicit mode and is rejected by the planner.
    case explicit(ComparisonProject.Mode)
}

/// Exact core option families retained by a request. `.defaults` chooses each engine's defaults.
/// No option family implies that this planner invokes its engine.
public enum ComparisonOpenModeOptions: Equatable, Sendable {
    case defaults
    case text(twoWay: LineDiffOptions, threeWay: ThreeWayTextMergeOptions)
    case table(
        parsing: DelimitedTableParsingOptions,
        twoWay: TableComparisonOptions,
        threeWay: ThreeWayTableComparisonOptions
    )
    case binary(twoWay: BinaryComparisonOptions, threeWay: ThreeWayBinaryComparisonOptions)
    case image(loading: ImageComparisonLimits, comparison: ImageComparisonOptions)
    case webpage(twoWay: WebPageComparisonOptions, threeWay: ThreeWayWebPageComparisonOptions)
    case folder(
        scanning: FolderScanOptions,
        twoWay: FolderComparisonOptions,
        threeWay: ThreeWayFolderComparisonOptions
    )
}

/// Serializable filename-filter inputs. The planner compiles these with `FilenameFilter` for
/// deterministic validation, but plans retain this descriptor rather than compiled implementation
/// state.
public struct ComparisonOpenFilenameFilter: Equatable, Sendable {
    public let rules: [FilenameFilterRule]
    public let defaultDecision: FilenameFilterDecision
    public let matchSemantics: FilenameFilterMatchSemantics
    public let casePolicy: FilenameFilterCasePolicy
    public let limits: FilenameFilterLimits

    public init(
        rules: [FilenameFilterRule],
        defaultDecision: FilenameFilterDecision = .include,
        matchSemantics: FilenameFilterMatchSemantics = .lastMatchWins,
        casePolicy: FilenameFilterCasePolicy = .sensitive,
        limits: FilenameFilterLimits = .default
    ) {
        self.rules = rules
        self.defaultDecision = defaultDecision
        self.matchSemantics = matchSemantics
        self.casePolicy = casePolicy
        self.limits = limits
    }
}

/// Reference to a trusted external-tool policy rule. It is not a shell command or executable path.
public struct ComparisonOpenExternalRuleReference: Equatable, Hashable, Sendable {
    public let ruleIdentifier: String

    public init(ruleIdentifier: String) {
        self.ruleIdentifier = ruleIdentifier
    }
}

public struct ComparisonOpenTransforms: Equatable, Sendable {
    public let unpacker: ComparisonOpenExternalRuleReference?
    public let prediffer: ComparisonOpenExternalRuleReference?

    public init(
        unpacker: ComparisonOpenExternalRuleReference? = nil,
        prediffer: ComparisonOpenExternalRuleReference? = nil
    ) {
        self.unpacker = unpacker
        self.prediffer = prediffer
    }
}

public enum ComparisonOpenProjectFormat: String, Equatable, Hashable, Sendable {
    case macMerge
    case winMerge
}

public enum ComparisonOpenProjectExistingFilePolicy: String, Equatable, Hashable, Sendable {
    case createNew
    case replaceExisting
}

/// Save intent only. Planning creates an in-memory project payload; it never writes the destination.
public struct ComparisonOpenProjectSaveIntent: Equatable, Sendable {
    public let destinationURL: URL
    public let format: ComparisonOpenProjectFormat
    public let existingFilePolicy: ComparisonOpenProjectExistingFilePolicy

    public init(
        destinationURL: URL,
        format: ComparisonOpenProjectFormat = .macMerge,
        existingFilePolicy: ComparisonOpenProjectExistingFilePolicy = .createNew
    ) {
        self.destinationURL = destinationURL
        self.format = format
        self.existingFilePolicy = existingFilePolicy
    }
}

public enum ComparisonOpenRequestLimit: String, CaseIterable, Equatable, Hashable, Sendable {
    case pathUTF8Bytes
    case totalPathUTF8Bytes
    case remoteURLUTF8Bytes
    case scratchpadUTF8Bytes
    case combinedScratchpadUTF8Bytes
    case labelUTF8Bytes
    case optionItemCount
    case optionStringUTF8Bytes
    case totalOptionStringUTF8Bytes
    case declaredBytes
    case declaredWorkUnits
    case planningWorkUnits
}

public struct ComparisonOpenRequestLimits: Equatable, Sendable {
    public static let hardMaximumPathUTF8Bytes = 64 * 1024
    public static let hardMaximumTotalPathUTF8Bytes = 4 * hardMaximumPathUTF8Bytes
    public static let hardMaximumRemoteURLUTF8Bytes = 64 * 1024
    public static let hardMaximumScratchpadUTF8Bytes = 64 * 1024 * 1024
    public static let hardMaximumCombinedScratchpadUTF8Bytes = 192 * 1024 * 1024
    public static let hardMaximumLabelUTF8Bytes = 4 * 1024
    public static let hardMaximumOptionItemCount = 4_096
    public static let hardMaximumOptionStringUTF8Bytes = 64 * 1024
    public static let hardMaximumTotalOptionStringUTF8Bytes = 4 * 1024 * 1024
    public static let hardMaximumDeclaredBytes = 1_125_899_906_842_624
    public static let hardMaximumDeclaredWorkUnits = 2 * 1024 * 1024 * 1024
    public static let hardMaximumPlanningWorkUnits = 512 * 1024 * 1024
    public static let `default` = ComparisonOpenRequestLimits()

    public let maximumPathUTF8Bytes: Int
    public let maximumTotalPathUTF8Bytes: Int
    public let maximumRemoteURLUTF8Bytes: Int
    public let maximumScratchpadUTF8Bytes: Int
    public let maximumCombinedScratchpadUTF8Bytes: Int
    public let maximumLabelUTF8Bytes: Int
    public let maximumOptionItemCount: Int
    public let maximumOptionStringUTF8Bytes: Int
    public let maximumTotalOptionStringUTF8Bytes: Int
    public let maximumDeclaredBytes: Int
    public let maximumDeclaredWorkUnits: Int
    public let maximumPlanningWorkUnits: Int

    public init(
        maximumPathUTF8Bytes: Int = ComparisonSessionState.maximumFilePathUTF8Bytes,
        maximumTotalPathUTF8Bytes: Int = 4 * ComparisonSessionState.maximumFilePathUTF8Bytes,
        maximumRemoteURLUTF8Bytes: Int = 64 * 1024,
        maximumScratchpadUTF8Bytes: Int = ComparisonSessionState.maximumScratchpadUTF8Bytes,
        maximumCombinedScratchpadUTF8Bytes: Int = 3
            * ComparisonSessionState.maximumScratchpadUTF8Bytes,
        maximumLabelUTF8Bytes: Int = 1_024,
        maximumOptionItemCount: Int = 4_096,
        maximumOptionStringUTF8Bytes: Int = 64 * 1024,
        maximumTotalOptionStringUTF8Bytes: Int = 4 * 1024 * 1024,
        maximumDeclaredBytes: Int = 1_125_899_906_842_624,
        maximumDeclaredWorkUnits: Int = 1024 * 1024 * 1024,
        maximumPlanningWorkUnits: Int = 256 * 1024 * 1024
    ) {
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTotalPathUTF8Bytes = maximumTotalPathUTF8Bytes
        self.maximumRemoteURLUTF8Bytes = maximumRemoteURLUTF8Bytes
        self.maximumScratchpadUTF8Bytes = maximumScratchpadUTF8Bytes
        self.maximumCombinedScratchpadUTF8Bytes = maximumCombinedScratchpadUTF8Bytes
        self.maximumLabelUTF8Bytes = maximumLabelUTF8Bytes
        self.maximumOptionItemCount = maximumOptionItemCount
        self.maximumOptionStringUTF8Bytes = maximumOptionStringUTF8Bytes
        self.maximumTotalOptionStringUTF8Bytes = maximumTotalOptionStringUTF8Bytes
        self.maximumDeclaredBytes = maximumDeclaredBytes
        self.maximumDeclaredWorkUnits = maximumDeclaredWorkUnits
        self.maximumPlanningWorkUnits = maximumPlanningWorkUnits
    }
}

private enum ComparisonOpenEngineCeilings {
    static let maximumTwoWayInputBytes = Int(MMX_MAX_INPUT_SIZE)
    static let maximumLineCount = Int(MMX_MAX_LINE_COUNT)
    static let maximumThreeWayInputBytes = 64 * 1024 * 1024
    static let maximumThreeWayOutputBytes = 192 * 1024 * 1024
    static let maximumThreeWayOutputLines = 3 * 1024 * 1024
    static let maximumThreeWayRegions = maximumThreeWayOutputLines + 1
    static let maximumTableRows = 1_048_576
    static let maximumTableColumnsPerRow = 16_384
    static let maximumTableCells = 1_048_576
    static let maximumTableCellBytes = 16 * 1024 * 1024
    static let maximumComparedTableItems = 2_097_152
    static let maximumThreeWayTableItems = 3 * 1_048_576
    static let maximumExactEditDistance = 2_048
    static let maximumTwoWayAlignmentWork = 16 * 1024 * 1024
    static let maximumThreeWayAlignmentWork = 32 * 1024 * 1024
    static let maximumImageDimension = 16_384
    static let maximumImagePixels = 16 * 1024 * 1024
    static let maximumImageDecodedBytes = 128 * 1024 * 1024
    static let maximumImageRegions = 250_000
    static let maximumImageQueuedPixels = 262_144
    static let maximumCollectionItems = 16 * 1024 * 1024
    static let maximumEngineWorkUnits = 512 * 1024 * 1024
    static let maximumFolderEntries = 10_000_000
    static let maximumFolderIssues = 100_000
    static let maximumFolderOpenDirectoryDescriptors = 128
    static let maximumRelativePathUTF8Bytes = 16_384
    static let maximumFilenameFilterRuleCount = 1_024
    static let maximumFilenameFilterPatternUTF8Bytes = 4_096
    static let maximumFilenameFilterTotalPatternUTF8Bytes = 1_048_576
    static let maximumFilenameFilterCompiledStateCount = 65_536
    static let maximumFilenameFilterRegularExpressionNestingDepth = 64
    static let maximumFilenameFilterRegularExpressionRepetition = 1_024
    static let maximumPCREPatternUTF8Bytes = 4_096
}

/// Immutable, UI-independent input to `ComparisonOpenRequestPlanner`.
public struct ComparisonOpenRequest: Equatable, Sendable {
    public let identity: ComparisonOpenRequestIdentity
    public let sides: [ComparisonOpenSide]
    public let modeSelection: ComparisonOpenModeSelection
    public let modeOptions: ComparisonOpenModeOptions
    public let recursive: Bool
    public let filenameFilter: ComparisonOpenFilenameFilter?
    public let transforms: ComparisonOpenTransforms
    public let projectSaveIntent: ComparisonOpenProjectSaveIntent?
    public let limits: ComparisonOpenRequestLimits

    public var isThreeWay: Bool {
        sides.count == 3 && Set(sides.map(\.position)) == [.left, .middle, .right]
    }
    public var leftSide: ComparisonOpenSide? { side(.left) }
    public var middleSide: ComparisonOpenSide? { side(.middle) }
    /// Three-way engines use the middle pane as their base input.
    public var baseSide: ComparisonOpenSide? { isThreeWay ? middleSide : nil }
    public var rightSide: ComparisonOpenSide? { side(.right) }

    public func side(_ position: ComparisonOpenSidePosition) -> ComparisonOpenSide? {
        sides.first { $0.position == position }
    }

    public init(
        identity: ComparisonOpenRequestIdentity = ComparisonOpenRequestIdentity(),
        sides: [ComparisonOpenSide],
        modeSelection: ComparisonOpenModeSelection = .inferred,
        modeOptions: ComparisonOpenModeOptions = .defaults,
        recursive: Bool = false,
        filenameFilter: ComparisonOpenFilenameFilter? = nil,
        transforms: ComparisonOpenTransforms = ComparisonOpenTransforms(),
        projectSaveIntent: ComparisonOpenProjectSaveIntent? = nil,
        limits: ComparisonOpenRequestLimits = .default
    ) {
        self.identity = identity
        self.sides = sides
        self.modeSelection = modeSelection
        self.modeOptions = modeOptions
        self.recursive = recursive
        self.filenameFilter = filenameFilter
        self.transforms = transforms
        self.projectSaveIntent = projectSaveIntent
        self.limits = limits
    }

    public init(
        identity: ComparisonOpenRequestIdentity = ComparisonOpenRequestIdentity(),
        left: ComparisonOpenSource,
        right: ComparisonOpenSource,
        leftReadOnly: Bool = false,
        rightReadOnly: Bool = false,
        modeSelection: ComparisonOpenModeSelection = .inferred,
        modeOptions: ComparisonOpenModeOptions = .defaults,
        recursive: Bool = false,
        filenameFilter: ComparisonOpenFilenameFilter? = nil,
        transforms: ComparisonOpenTransforms = ComparisonOpenTransforms(),
        projectSaveIntent: ComparisonOpenProjectSaveIntent? = nil,
        limits: ComparisonOpenRequestLimits = .default
    ) {
        self.init(
            identity: identity,
            sides: [
                ComparisonOpenSide(position: .left, source: left, readOnly: leftReadOnly),
                ComparisonOpenSide(position: .right, source: right, readOnly: rightReadOnly)
            ],
            modeSelection: modeSelection,
            modeOptions: modeOptions,
            recursive: recursive,
            filenameFilter: filenameFilter,
            transforms: transforms,
            projectSaveIntent: projectSaveIntent,
            limits: limits
        )
    }

    public init(
        identity: ComparisonOpenRequestIdentity = ComparisonOpenRequestIdentity(),
        left: ComparisonOpenSource,
        middle: ComparisonOpenSource,
        right: ComparisonOpenSource,
        leftReadOnly: Bool = false,
        middleReadOnly: Bool = false,
        rightReadOnly: Bool = false,
        modeSelection: ComparisonOpenModeSelection = .inferred,
        modeOptions: ComparisonOpenModeOptions = .defaults,
        recursive: Bool = false,
        filenameFilter: ComparisonOpenFilenameFilter? = nil,
        transforms: ComparisonOpenTransforms = ComparisonOpenTransforms(),
        projectSaveIntent: ComparisonOpenProjectSaveIntent? = nil,
        limits: ComparisonOpenRequestLimits = .default
    ) {
        self.init(
            identity: identity,
            sides: [
                ComparisonOpenSide(position: .left, source: left, readOnly: leftReadOnly),
                ComparisonOpenSide(position: .middle, source: middle, readOnly: middleReadOnly),
                ComparisonOpenSide(position: .right, source: right, readOnly: rightReadOnly)
            ],
            modeSelection: modeSelection,
            modeOptions: modeOptions,
            recursive: recursive,
            filenameFilter: filenameFilter,
            transforms: transforms,
            projectSaveIntent: projectSaveIntent,
            limits: limits
        )
    }

    /// Swaps complete side payloads while preserving canonical pane positions.
    /// The returned request receives a new identity so in-flight plans become stale.
    public func swapping(
        _ first: ComparisonOpenSidePosition,
        _ second: ComparisonOpenSidePosition,
        identity: ComparisonOpenRequestIdentity = ComparisonOpenRequestIdentity()
    ) throws -> ComparisonOpenRequest {
        guard let firstIndex = sides.firstIndex(where: { $0.position == first }) else {
            throw ComparisonOpenRequestError.missingSide(first)
        }
        guard first != second else {
            return ComparisonOpenRequest(
                identity: identity,
                sides: sides,
                modeSelection: modeSelection,
                modeOptions: modeOptions,
                recursive: recursive,
                filenameFilter: filenameFilter,
                transforms: transforms,
                projectSaveIntent: projectSaveIntent,
                limits: limits
            )
        }
        guard let secondIndex = sides.firstIndex(where: { $0.position == second }) else {
            throw ComparisonOpenRequestError.missingSide(second)
        }

        var swapped = sides
        let firstSide = swapped[firstIndex]
        let secondSide = swapped[secondIndex]
        swapped[firstIndex] = ComparisonOpenSide(
            position: first,
            source: secondSide.source,
            readOnly: secondSide.readOnly
        )
        swapped[secondIndex] = ComparisonOpenSide(
            position: second,
            source: firstSide.source,
            readOnly: firstSide.readOnly
        )
        return ComparisonOpenRequest(
            identity: identity,
            sides: swapped,
            modeSelection: modeSelection,
            modeOptions: modeOptions,
            recursive: recursive,
            filenameFilter: filenameFilter,
            transforms: transforms,
            projectSaveIntent: projectSaveIntent,
            limits: limits
        )
    }
}

public enum ComparisonOpenURLContext: Equatable, Hashable, Sendable {
    case side(ComparisonOpenSidePosition)
    case projectDestination
}

public enum ComparisonOpenURLValidationReason: String, Equatable, Hashable, Sendable {
    case relativeURL
    case wrongScheme
    case remoteFileHost
    case credentials
    case queryOrFragment
    case missingPath
    case missingHost
    case port
    case directoryDestination
    case invalidFileName
    case dotPathSegment
    case nullByte
    case tooLong
}

public enum ComparisonOpenSourceCompatibilityReason: String, Equatable, Hashable, Sendable {
    case mixedFilesAndFolders
    case foldersRequireFolderMode
    case folderModeRequiresFolders
    case scratchpadUnsupported
    case remoteWebPageRequiresWebpageMode
    case clipboardRequiresTwoSnapshots
    case clipboardContentKindsDiffer
    case clipboardTextRequiresTextMode
    case clipboardBinaryRequiresBinaryMode
    case localFilesRequired
}

public enum ComparisonOpenProjectRepresentationReason: String, Equatable, Hashable, Sendable {
    case localSourcesRequired
    case filenameFilterNotRepresentable
    case transformsNotRepresentable
    case modeSelectionNotRepresentable
    case modeOptionsNotRepresentable
    case destinationMatchesSource
    case projectModelRejectedRequest
}

public enum ComparisonOpenRequestError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case staleRequest(
        expected: ComparisonOpenRequestIdentity,
        actual: ComparisonOpenRequestIdentity
    )
    case invalidLimit(ComparisonOpenRequestLimit)
    case invalidSideCount(Int)
    case duplicateSide(ComparisonOpenSidePosition)
    case missingSide(ComparisonOpenSidePosition)
    case invalidSideSet([ComparisonOpenSidePosition])
    case invalidURL(context: ComparisonOpenURLContext, reason: ComparisonOpenURLValidationReason)
    case duplicateLocalSource(
        first: ComparisonOpenSidePosition,
        second: ComparisonOpenSidePosition
    )
    case scratchpadTooLarge(side: ComparisonOpenSidePosition, maximumUTF8Bytes: Int)
    case combinedScratchpadsTooLarge(maximumUTF8Bytes: Int)
    case sourceLineCountExceeded(side: ComparisonOpenSidePosition, maximumLines: Int)
    case totalPathsTooLarge(maximumUTF8Bytes: Int)
    case invalidLabel(side: ComparisonOpenSidePosition)
    case labelTooLarge(side: ComparisonOpenSidePosition, maximumUTF8Bytes: Int)
    case explicitAutomaticMode
    case modeInferenceRequiresExplicitSelection
    case tableParsingRequiresExplicitSettings
    case incompatibleSource(
        side: ComparisonOpenSidePosition?,
        mode: ComparisonProject.Mode,
        reason: ComparisonOpenSourceCompatibilityReason
    )
    case recursiveOptionRequiresFolderMode
    case filenameFilterRequiresFolderMode
    case invalidClipboard(ClipboardComparisonError)
    case invalidFilenameFilter(FilenameFilterDiagnostic)
    case modeOptionsMismatch(expected: ComparisonProject.Mode, actual: ComparisonProject.Mode)
    case tooManyOptionItems(maximum: Int)
    case invalidOption(name: String)
    case optionStringTooLarge(name: String, maximumUTF8Bytes: Int)
    case totalOptionStringsTooLarge(maximumUTF8Bytes: Int)
    case declaredLimitExceeded(name: String, maximum: Int)
    case engineLimitExceeded(name: String, maximum: Int)
    case invalidExternalRuleIdentifier(capability: ExternalToolCapability)
    case externalRuleIdentifiersMustDiffer
    case externalRuleIdentifierTooLarge(
        capability: ExternalToolCapability,
        maximumUTF8Bytes: Int
    )
    case externalTransformRequiresLocalFiles(capability: ExternalToolCapability)
    case projectCannotRepresent(ComparisonOpenProjectRepresentationReason)
    case planningWorkExceeded(maximumWorkUnits: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Comparison open request planning was cancelled."
        case .staleRequest:
            return "Comparison open request identity is stale."
        case .invalidLimit(let limit):
            return "Comparison open request limit is invalid: \(limit.rawValue)."
        case .invalidSideCount(let count):
            return "Comparison open request requires two or three sides, not \(count)."
        case .duplicateSide(let side):
            return "Comparison open request contains the \(side.rawValue) side more than once."
        case .missingSide(let side):
            return "Comparison open request is missing the \(side.rawValue) side."
        case .invalidSideSet(let sides):
            let names = sides.map(\.rawValue).joined(separator: ", ")
            return "Comparison open request has invalid sides: \(names)."
        case .invalidURL(let context, let reason):
            return "Comparison open request has an invalid \(Self.description(of: context)) URL: \(reason.rawValue)."
        case .duplicateLocalSource(let first, let second):
            return "Comparison open request repeats one local source on the \(first.rawValue) and \(second.rawValue) sides."
        case .scratchpadTooLarge(let side, let maximum):
            return "Comparison open request \(side.rawValue) scratchpad exceeds \(maximum) UTF-8 bytes."
        case .combinedScratchpadsTooLarge(let maximum):
            return "Comparison open request scratchpads exceed \(maximum) combined UTF-8 bytes."
        case .sourceLineCountExceeded(let side, let maximum):
            return "Comparison open request \(side.rawValue) source exceeds \(maximum) lines."
        case .totalPathsTooLarge(let maximum):
            return "Comparison open request paths exceed \(maximum) combined UTF-8 bytes."
        case .invalidLabel(let side):
            return "Comparison open request \(side.rawValue) scratchpad label is invalid."
        case .labelTooLarge(let side, let maximum):
            return "Comparison open request \(side.rawValue) label exceeds \(maximum) UTF-8 bytes."
        case .explicitAutomaticMode:
            return "Automatic comparison mode must be inferred rather than selected explicitly."
        case .modeInferenceRequiresExplicitSelection:
            return "Comparison mode cannot be inferred safely; select one explicitly."
        case .tableParsingRequiresExplicitSettings:
            return "Mixed CSV and TSV inputs require explicit table parsing settings."
        case .incompatibleSource(let side, let mode, let reason):
            let sideDescription = side.map { " on the \($0.rawValue) side" } ?? ""
            return "Comparison source\(sideDescription) is incompatible with \(mode.rawValue) mode: \(reason.rawValue)."
        case .recursiveOptionRequiresFolderMode:
            return "Recursive traversal is available only for folder comparisons."
        case .filenameFilterRequiresFolderMode:
            return "Filename filters are available only for folder comparisons."
        case .invalidClipboard(let error):
            return error.errorDescription
        case .invalidFilenameFilter(let diagnostic):
            return diagnostic.errorDescription
        case .modeOptionsMismatch(let expected, let actual):
            return "Comparison options for \(actual.rawValue) mode cannot be used with \(expected.rawValue) mode."
        case .tooManyOptionItems(let maximum):
            return "Comparison open request exceeds the \(maximum)-item option limit."
        case .invalidOption(let name):
            return "Comparison open request option is invalid: \(name)."
        case .optionStringTooLarge(let name, let maximum):
            return "Comparison open request option \(name) exceeds \(maximum) UTF-8 bytes."
        case .totalOptionStringsTooLarge(let maximum):
            return "Comparison open request option strings exceed \(maximum) combined UTF-8 bytes."
        case .declaredLimitExceeded(let name, let maximum):
            return "Comparison open request option \(name) exceeds the declared limit of \(maximum)."
        case .engineLimitExceeded(let name, let maximum):
            return "Comparison open request option \(name) exceeds the engine limit of \(maximum)."
        case .invalidExternalRuleIdentifier(let capability):
            return "Comparison open request has an invalid \(capability.rawValue) rule identifier."
        case .externalRuleIdentifiersMustDiffer:
            return "Comparison open request unpacker and prediffer rule identifiers must differ."
        case .externalRuleIdentifierTooLarge(let capability, let maximum):
            return "Comparison open request \(capability.rawValue) rule identifier exceeds \(maximum) UTF-8 bytes."
        case .externalTransformRequiresLocalFiles(let capability):
            return "Comparison open request \(capability.rawValue) requires local-file sources."
        case .projectCannotRepresent(let reason):
            return "Comparison project cannot represent this open request without data loss: \(reason.rawValue)."
        case .planningWorkExceeded(let maximum):
            return "Comparison open request planning exceeds the \(maximum)-unit work limit."
        }
    }

    private static func description(of context: ComparisonOpenURLContext) -> String {
        switch context {
        case .side(let side): "\(side.rawValue)-side"
        case .projectDestination: "project-destination"
        }
    }
}

public enum ComparisonOpenModeResolutionBasis: Equatable, Hashable, Sendable {
    case explicit
    case allFolders
    case clipboardText
    case clipboardBinary
    case remoteWebPage
    case recognizedFileExtensions
    case textFallback
}

public struct ComparisonOpenModeResolution: Equatable, Sendable {
    public let mode: ComparisonProject.Mode
    public let basis: ComparisonOpenModeResolutionBasis

    public init(mode: ComparisonProject.Mode, basis: ComparisonOpenModeResolutionBasis) {
        self.mode = mode
        self.basis = basis
    }
}

public enum ComparisonOpenLocalAccessPurpose: String, Equatable, Hashable, Sendable {
    case readRegularFile
    case readDirectoryTree
    case writeProjectFile
}

public enum ComparisonOpenSecurityScopeRequirement: String, Equatable, Hashable, Sendable {
    /// Caller must establish and retain sandbox authorization when the process requires it.
    case callerManagedWhenRequired
}

/// Requirement emitted without probing the filesystem or opening a security scope.
public struct ComparisonOpenLocalAccessRequirement: Equatable, Sendable {
    public let side: ComparisonOpenSidePosition?
    public let url: URL
    /// Validated lexical path used for comparisons and serialization. `url` remains caller-owned so
    /// sandbox authorization attached to it is not discarded.
    public let normalizedPath: String
    public let purpose: ComparisonOpenLocalAccessPurpose
    public let recursive: Bool
    public let securityScope: ComparisonOpenSecurityScopeRequirement

    public init(
        side: ComparisonOpenSidePosition?,
        url: URL,
        normalizedPath: String? = nil,
        purpose: ComparisonOpenLocalAccessPurpose,
        recursive: Bool = false,
        securityScope: ComparisonOpenSecurityScopeRequirement = .callerManagedWhenRequired
    ) {
        self.side = side
        self.url = url
        self.normalizedPath = normalizedPath ?? url.path
        self.purpose = purpose
        self.recursive = recursive
        self.securityScope = securityScope
    }
}

public enum ComparisonOpenMaterializationRequirement: Equatable, Sendable {
    case localAccess(ComparisonOpenLocalAccessRequirement)
    /// Caller must supply bounded HTML bytes. MacMergeCore does not fetch the URL.
    case offlineWebPageContent(side: ComparisonOpenSidePosition, url: URL)
    /// Caller must revalidate the two immutable snapshots through `ClipboardComparison.inputs`.
    case clipboardPairValidation
    /// Caller must use `ExternalToolRequestPlanner`; this plan is not an execution plan.
    case externalToolPlan(
        capability: ExternalToolCapability,
        rule: ComparisonOpenExternalRuleReference
    )
    /// Materializer must reject aliases after obtaining filesystem identities. Planning performs
    /// lexical duplicate checks only because identity resolution would require filesystem access.
    case distinctSourceIdentityValidation(sourceURLs: [URL])
    /// Save executor must honor create/replace policy and reject a destination whose resolved file
    /// identity aliases an input. Planning cannot prove either property without filesystem access.
    case projectSaveValidation(intent: ComparisonOpenProjectSaveIntent, sourceURLs: [URL])
}

public enum ComparisonOpenUnsupportedFeature: Equatable, Hashable, Sendable {
    /// Network loading is outside the current comparison core.
    case remoteWebPageLoading
    /// External-tool policy can plan an invocation, but no executor is supplied by this request core.
    case externalToolExecution(ExternalToolCapability)
    /// `FolderScanner` is recursive; a caller must provide bounded nonrecursive enumeration.
    case nonrecursiveFolderEnumeration
}

public enum ComparisonOpenProjectPayload: Equatable, Sendable {
    /// Canonical bytes only. Caller still must enforce save intent and destination requirements.
    case macMerge(Data)
    /// Canonical bytes only. Caller still must enforce save intent and destination requirements.
    case winMerge(Data)
}

private struct ComparisonOpenMacMergeProjectPayload: Encodable {
    let schemaVersion = ComparisonProject.currentSchemaVersion
    let mode: ComparisonProject.Mode
    let sides: [ComparisonOpenMacMergeProjectSide]
    let recursive: Bool
    let filter: ComparisonProject.FilterReference? = nil
    let lineDiffOptions: LineDiffOptions
}

private struct ComparisonOpenMacMergeProjectSide: Encodable {
    let identity: ComparisonProject.Side.Identity
    let path: String
    let readOnly: Bool
}

public struct ComparisonOpenPlannedSide: Equatable, Sendable {
    public let position: ComparisonOpenSidePosition
    public let source: ComparisonOpenSource
    /// Validated lexical path for local sources. Original URL remains in `source`.
    public let normalizedPath: String?
    public let effectiveReadOnly: Bool

    public init(
        position: ComparisonOpenSidePosition,
        source: ComparisonOpenSource,
        normalizedPath: String? = nil,
        effectiveReadOnly: Bool
    ) {
        self.position = position
        self.source = source
        self.normalizedPath = normalizedPath
        self.effectiveReadOnly = effectiveReadOnly
    }
}

/// Validated planning output. It deliberately has no execution method.
public struct ComparisonOpenPlan: Equatable, Sendable {
    public let requestIdentity: ComparisonOpenRequestIdentity
    public let sourceRequest: ComparisonOpenRequest
    public let sides: [ComparisonOpenPlannedSide]
    public let modeResolution: ComparisonOpenModeResolution
    public let modeOptions: ComparisonOpenModeOptions
    public let recursive: Bool
    public let filenameFilter: ComparisonOpenFilenameFilter?
    public let transforms: ComparisonOpenTransforms
    public let projectSaveIntent: ComparisonOpenProjectSaveIntent?
    /// Validated lexical destination path. Save intent retains caller's authorized URL.
    public let normalizedProjectDestinationPath: String?
    public let projectPayload: ComparisonOpenProjectPayload?
    public let materializationRequirements: [ComparisonOpenMaterializationRequirement]
    public let unsupportedFeatures: [ComparisonOpenUnsupportedFeature]

    public var isThreeWay: Bool {
        sides.count == 3 && Set(sides.map(\.position)) == [.left, .middle, .right]
    }
    public var leftSide: ComparisonOpenPlannedSide? { side(.left) }
    public var middleSide: ComparisonOpenPlannedSide? { side(.middle) }
    /// Three-way engines use the middle pane as their base input.
    public var baseSide: ComparisonOpenPlannedSide? { isThreeWay ? middleSide : nil }
    public var rightSide: ComparisonOpenPlannedSide? { side(.right) }

    public func side(_ position: ComparisonOpenSidePosition) -> ComparisonOpenPlannedSide? {
        sides.first { $0.position == position }
    }

    /// Request identity is the bounded freshness token. Callers must replace it whenever input
    /// changes; comparing the retained payload could otherwise scan hundreds of MiB without a
    /// cancellation point.
    public func isCurrent(for request: ComparisonOpenRequest) -> Bool {
        requestIdentity == request.identity
    }

    public func requireCurrentRequest(_ request: ComparisonOpenRequest) throws {
        guard isCurrent(for: request) else {
            throw ComparisonOpenRequestError.staleRequest(
                expected: requestIdentity,
                actual: request.identity
            )
        }
    }
}

public enum ComparisonOpenRequestPlanner: Sendable {
    /// Validates and plans only in-memory request state. No URL is opened or queried.
    public static func plan(
        _ request: ComparisonOpenRequest,
        expecting expectedIdentity: ComparisonOpenRequestIdentity? = nil
    ) throws -> ComparisonOpenPlan {
        try checkCancellation()
        if let expectedIdentity, expectedIdentity != request.identity {
            throw ComparisonOpenRequestError.staleRequest(
                expected: expectedIdentity,
                actual: request.identity
            )
        }
        try validate(request.limits)
        var work = ComparisonOpenPlanningWork(maximum: request.limits.maximumPlanningWorkUnits)
        let sides = try canonicalSides(request.sides, work: &work)

        var totalPathBytes = 0
        var totalScratchpadBytes = 0
        var scratchpadMetrics: [ComparisonOpenSidePosition: ComparisonOpenTextMetrics] = [:]
        var normalizedLocalPaths: [ComparisonOpenSidePosition: String] = [:]
        var localSources: [(position: ComparisonOpenSidePosition, url: URL, normalizedPath: String)] = []
        for side in sides {
            try checkCancellation()
            try work.charge(1)
            switch side.source {
            case .localFile(let url), .localFolder(let url):
                let isDirectory: Bool
                if case .localFolder = side.source {
                    isDirectory = true
                } else {
                    isDirectory = false
                }
                let (normalizedPath, pathBytes) = try validateLocalURL(
                    url,
                    context: .side(side.position),
                    isDirectory: isDirectory,
                    limits: request.limits,
                    work: &work
                )
                totalPathBytes = try addingPathBytes(
                    pathBytes,
                    to: totalPathBytes,
                    limits: request.limits
                )
                if let duplicate = localSources.first(where: { $0.normalizedPath == normalizedPath }) {
                    throw ComparisonOpenRequestError.duplicateLocalSource(
                        first: duplicate.position,
                        second: side.position
                    )
                }
                normalizedLocalPaths[side.position] = normalizedPath
                localSources.append((side.position, url, normalizedPath))
            case .scratchpad(let text, let label):
                let metrics = try boundedLineDiffTextMetrics(
                    text,
                    maximum: request.limits.maximumScratchpadUTF8Bytes,
                    side: side.position,
                    work: &work
                )
                guard let metrics else {
                    throw ComparisonOpenRequestError.scratchpadTooLarge(
                        side: side.position,
                        maximumUTF8Bytes: request.limits.maximumScratchpadUTF8Bytes
                    )
                }
                scratchpadMetrics[side.position] = metrics
                let (combined, overflow) = totalScratchpadBytes.addingReportingOverflow(metrics.utf8Bytes)
                guard !overflow,
                    combined <= request.limits.maximumCombinedScratchpadUTF8Bytes
                else {
                    throw ComparisonOpenRequestError.combinedScratchpadsTooLarge(
                        maximumUTF8Bytes: request.limits.maximumCombinedScratchpadUTF8Bytes
                    )
                }
                totalScratchpadBytes = combined
                if let label {
                    guard
                        try boundedUTF8Count(
                            label,
                            maximum: request.limits.maximumLabelUTF8Bytes,
                            work: &work
                        ) != nil
                    else {
                        throw ComparisonOpenRequestError.labelTooLarge(
                            side: side.position,
                            maximumUTF8Bytes: request.limits.maximumLabelUTF8Bytes
                        )
                    }
                    guard !label.isEmpty, !label.contains("\0") else {
                        throw ComparisonOpenRequestError.invalidLabel(side: side.position)
                    }
                }
            case .clipboard(let snapshot):
                try validateClipboardSnapshot(
                    snapshot,
                    side: side.position,
                    limits: request.limits,
                    work: &work
                )
            case .remoteWebPage(let url):
                try validateRemoteWebURL(
                    url,
                    side: side.position,
                    limits: request.limits,
                    work: &work
                )
            }
        }

        let resolution = try resolveMode(for: request, sides: sides, work: &work)
        let modeOptions = try effectiveModeOptions(
            request.modeOptions,
            selection: request.modeSelection,
            resolution: resolution,
            sides: sides,
            isThreeWay: request.isThreeWay
        )
        try validateSourceCompatibility(sides, mode: resolution.mode)
        if request.recursive, resolution.mode != .folder {
            throw ComparisonOpenRequestError.recursiveOptionRequiresFolderMode
        }
        if request.filenameFilter != nil, resolution.mode != .folder {
            throw ComparisonOpenRequestError.filenameFilterRequiresFolderMode
        }
        try validate(
            modeOptions,
            for: resolution.mode,
            isThreeWay: request.isThreeWay,
            limits: request.limits,
            work: &work
        )
        try validateScratchpads(
            scratchpadMetrics,
            mode: resolution.mode,
            modeOptions: modeOptions,
            isThreeWay: request.isThreeWay
        )
        try validateAggregateOptionStrings(
            request,
            modeOptions: modeOptions,
            work: &work
        )
        if let filenameFilter = request.filenameFilter {
            try validate(filenameFilter, requestLimits: request.limits, work: &work)
        }
        try validate(request.transforms, sides: sides, limits: request.limits, work: &work)

        var projectPayload: ComparisonOpenProjectPayload?
        var projectSaveIntent: ComparisonOpenProjectSaveIntent?
        var normalizedProjectDestinationPath: String?
        if let saveIntent = request.projectSaveIntent {
            let (normalizedDestinationPath, pathBytes) = try validateLocalURL(
                saveIntent.destinationURL,
                context: .projectDestination,
                isDirectory: false,
                limits: request.limits,
                work: &work
            )
            _ = try addingPathBytes(pathBytes, to: totalPathBytes, limits: request.limits)
            guard !localSources.contains(where: { $0.normalizedPath == normalizedDestinationPath }) else {
                throw ComparisonOpenRequestError.projectCannotRepresent(.destinationMatchesSource)
            }
            normalizedProjectDestinationPath = normalizedDestinationPath
            projectSaveIntent = saveIntent
            projectPayload = try makeProjectPayload(
                intent: saveIntent,
                request: request,
                sides: sides,
                normalizedLocalPaths: normalizedLocalPaths,
                mode: resolution.mode,
                work: &work
            )
        }

        let requirements = materializationRequirements(
            request: request,
            sides: sides,
            normalizedLocalPaths: normalizedLocalPaths,
            mode: resolution.mode,
            projectSaveIntent: projectSaveIntent,
            normalizedProjectDestinationPath: normalizedProjectDestinationPath
        )
        let unsupportedFeatures = unsupportedFeatures(request: request, sides: sides, mode: resolution.mode)
        let plannedSides = sides.map {
            ComparisonOpenPlannedSide(
                position: $0.position,
                source: $0.source,
                normalizedPath: normalizedLocalPaths[$0.position],
                effectiveReadOnly: $0.readOnly || $0.source.isImmutableSnapshot
            )
        }
        try checkCancellation()
        return ComparisonOpenPlan(
            requestIdentity: request.identity,
            sourceRequest: request,
            sides: plannedSides,
            modeResolution: resolution,
            modeOptions: modeOptions,
            recursive: request.recursive,
            filenameFilter: request.filenameFilter,
            transforms: request.transforms,
            projectSaveIntent: projectSaveIntent,
            normalizedProjectDestinationPath: normalizedProjectDestinationPath,
            projectPayload: projectPayload,
            materializationRequirements: requirements,
            unsupportedFeatures: unsupportedFeatures
        )
    }

    private static func canonicalSides(
        _ sides: [ComparisonOpenSide],
        work: inout ComparisonOpenPlanningWork
    ) throws -> [ComparisonOpenSide] {
        guard sides.count == 2 || sides.count == 3 else {
            throw ComparisonOpenRequestError.invalidSideCount(sides.count)
        }
        var seen = Set<ComparisonOpenSidePosition>()
        for side in sides {
            try work.charge(1)
            guard seen.insert(side.position).inserted else {
                throw ComparisonOpenRequestError.duplicateSide(side.position)
            }
        }
        let expected: Set<ComparisonOpenSidePosition> =
            sides.count == 2
            ? [.left, .right]
            : [.left, .middle, .right]
        guard seen == expected else {
            throw ComparisonOpenRequestError.invalidSideSet(
                sides.map(\.position).sorted { $0.sortOrder < $1.sortOrder }
            )
        }
        return sides.sorted { $0.position.sortOrder < $1.position.sortOrder }
    }

    private static func resolveMode(
        for request: ComparisonOpenRequest,
        sides: [ComparisonOpenSide],
        work: inout ComparisonOpenPlanningWork
    ) throws -> ComparisonOpenModeResolution {
        switch request.modeSelection {
        case .explicit(.automatic):
            throw ComparisonOpenRequestError.explicitAutomaticMode
        case .explicit(let mode):
            return ComparisonOpenModeResolution(mode: mode, basis: .explicit)
        case .inferred:
            guard request.transforms.unpacker == nil, request.transforms.prediffer == nil else {
                throw ComparisonOpenRequestError.modeInferenceRequiresExplicitSelection
            }
        }

        let folderCount = sides.count { if case .localFolder = $0.source { true } else { false } }
        if folderCount == sides.count {
            return ComparisonOpenModeResolution(mode: .folder, basis: .allFolders)
        }
        if folderCount > 0 {
            throw ComparisonOpenRequestError.incompatibleSource(
                side: nil,
                mode: .automatic,
                reason: .mixedFilesAndFolders
            )
        }

        if sides.contains(where: { if case .remoteWebPage = $0.source { true } else { false } }) {
            return ComparisonOpenModeResolution(mode: .webpage, basis: .remoteWebPage)
        }

        let clipboardSides = sides.filter { if case .clipboard = $0.source { true } else { false } }
        if !clipboardSides.isEmpty {
            guard clipboardSides.count == 2, sides.count == 2 else {
                throw ComparisonOpenRequestError.incompatibleSource(
                    side: nil,
                    mode: .automatic,
                    reason: .clipboardRequiresTwoSnapshots
                )
            }
            switch try validatedClipboardKind(clipboardSides) {
            case .text:
                return ComparisonOpenModeResolution(mode: .text, basis: .clipboardText)
            case .binary:
                return ComparisonOpenModeResolution(mode: .binary, basis: .clipboardBinary)
            }
        }

        var signals: [(ComparisonProject.Mode, ComparisonOpenModeResolutionBasis)] = []
        var localFileCount = 0
        var recognizedLocalFileCount = 0
        for side in sides {
            try work.charge(1)
            switch side.source {
            case .scratchpad:
                signals.append((.text, .textFallback))
            case .localFile(let url):
                localFileCount += 1
                if let mode = recognizedMode(forFileExtension: url.pathExtension.lowercased()) {
                    recognizedLocalFileCount += 1
                    let basis: ComparisonOpenModeResolutionBasis =
                        mode == .text ? .textFallback : .recognizedFileExtensions
                    signals.append((mode, basis))
                }
            case .localFolder, .clipboard, .remoteWebPage:
                break
            }
        }
        guard let first = signals.first,
            signals.allSatisfy({ $0.0 == first.0 }),
            localFileCount != sides.count || recognizedLocalFileCount == localFileCount
        else {
            throw ComparisonOpenRequestError.modeInferenceRequiresExplicitSelection
        }
        return ComparisonOpenModeResolution(mode: first.0, basis: first.1)
    }

    private static func recognizedMode(forFileExtension fileExtension: String) -> ComparisonProject.Mode? {
        let imageExtensions: Set<String> = ["bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff"]
        let tableExtensions: Set<String> = ["csv", "tsv"]
        let webpageExtensions: Set<String> = ["htm", "html", "shtml", "xhtml"]
        let binaryExtensions: Set<String> = [
            "7z", "a", "app", "bin", "bz2", "class", "dmg", "doc", "docx", "dylib", "eot", "epub", "exe", "gz", "ico", "jar", "macho", "mov",
            "mp3", "mp4", "o", "otf", "pdf", "pkg", "ppt", "pptx", "rar", "so", "tar", "ttf", "wav", "webp", "woff", "woff2", "xls", "xlsx",
            "xz", "zip"
        ]
        let textExtensions: Set<String> = [
            "adb", "ads", "ascx", "asp", "bat", "bas", "c", "cc", "cfg", "clo", "cmd", "conf", "cpp", "cppm", "cs", "css", "cxx", "d",
            "di", "diff", "dtd", "f", "f77", "f90", "for", "fs", "fsx", "go", "h", "hh", "hpp", "hxx", "ini", "inl", "ixx", "java", "js", "json",
            "jsx", "log", "lua", "m", "markdown", "md", "mkd", "mkdn", "mm", "nsh", "nsi", "patch", "php", "pl", "pm", "properties", "ps1",
            "psd1", "psm1", "py", "rb", "rc", "rs", "rst", "scss", "sh", "sql", "strings", "swift", "tcl", "tex", "toml", "ts", "tsx",
            "txt", "v", "vb", "vbs", "vhd", "vhdl", "vue", "xml", "yaml", "yml"
        ]
        if imageExtensions.contains(fileExtension) { return .image }
        if tableExtensions.contains(fileExtension) { return .table }
        if webpageExtensions.contains(fileExtension) { return .webpage }
        if binaryExtensions.contains(fileExtension) { return .binary }
        if textExtensions.contains(fileExtension) { return .text }
        return nil
    }

    private static func effectiveModeOptions(
        _ options: ComparisonOpenModeOptions,
        selection: ComparisonOpenModeSelection,
        resolution: ComparisonOpenModeResolution,
        sides: [ComparisonOpenSide],
        isThreeWay: Bool
    ) throws -> ComparisonOpenModeOptions {
        guard resolution.mode == .table else { return options }
        let extensions = sides.compactMap { side -> String? in
            guard case .localFile(let url) = side.source else { return nil }
            return url.pathExtension.lowercased()
        }
        let hasCSV = extensions.contains("csv")
        let hasTSV = extensions.contains("tsv")
        if hasCSV, hasTSV, options == .defaults {
            throw ComparisonOpenRequestError.tableParsingRequiresExplicitSettings
        }
        guard case .inferred = selection, hasTSV, !hasCSV, options == .defaults else {
            return options
        }
        if isThreeWay {
            return .table(
                parsing: .tabSeparated,
                twoWay: .default,
                threeWay: ThreeWayTableComparisonOptions(parsingOptions: .tabSeparated)
            )
        }
        return .table(
            parsing: .tabSeparated,
            twoWay: .default,
            threeWay: .default
        )
    }

    private static func validateSourceCompatibility(
        _ sides: [ComparisonOpenSide],
        mode: ComparisonProject.Mode
    ) throws {
        let clipboardSides = sides.filter { if case .clipboard = $0.source { true } else { false } }
        if !clipboardSides.isEmpty {
            guard sides.count == 2, clipboardSides.count == 2 else {
                throw ComparisonOpenRequestError.incompatibleSource(
                    side: nil,
                    mode: mode,
                    reason: .clipboardRequiresTwoSnapshots
                )
            }
            switch (try validatedClipboardKind(clipboardSides), mode) {
            case (.text, .text), (.binary, .binary):
                break
            case (.text, _):
                throw ComparisonOpenRequestError.incompatibleSource(
                    side: nil,
                    mode: mode,
                    reason: .clipboardTextRequiresTextMode
                )
            case (.binary, _):
                throw ComparisonOpenRequestError.incompatibleSource(
                    side: nil,
                    mode: mode,
                    reason: .clipboardBinaryRequiresBinaryMode
                )
            }
            return
        }

        for side in sides {
            switch (mode, side.source) {
            case (.folder, .localFolder),
                (.text, .localFile),
                (.text, .scratchpad),
                (.table, .localFile),
                (.table, .scratchpad),
                (.binary, .localFile),
                (.image, .localFile),
                (.webpage, .localFile),
                (.webpage, .scratchpad),
                (.webpage, .remoteWebPage):
                continue
            case (.folder, _):
                throw ComparisonOpenRequestError.incompatibleSource(
                    side: side.position,
                    mode: mode,
                    reason: .folderModeRequiresFolders
                )
            case (_, .localFolder):
                throw ComparisonOpenRequestError.incompatibleSource(
                    side: side.position,
                    mode: mode,
                    reason: .foldersRequireFolderMode
                )
            case (_, .scratchpad):
                throw ComparisonOpenRequestError.incompatibleSource(
                    side: side.position,
                    mode: mode,
                    reason: .scratchpadUnsupported
                )
            case (_, .remoteWebPage):
                throw ComparisonOpenRequestError.incompatibleSource(
                    side: side.position,
                    mode: mode,
                    reason: .remoteWebPageRequiresWebpageMode
                )
            case (_, .clipboard):
                preconditionFailure("Clipboard sources were handled before per-side validation")
            case (.automatic, _):
                preconditionFailure("Mode resolution cannot produce automatic mode")
            }
        }
    }

    private static func validatedClipboardKind(
        _ sides: [ComparisonOpenSide]
    ) throws -> ClipboardComparisonInputs.Kind {
        guard sides.count == 2,
            case .clipboard(let left) = sides[0].source,
            case .clipboard(let right) = sides[1].source
        else {
            throw ComparisonOpenRequestError.incompatibleSource(
                side: nil,
                mode: .automatic,
                reason: .clipboardRequiresTwoSnapshots
            )
        }
        switch (left.content, right.content) {
        case (.text(let leftText), .text(let rightText)):
            guard !leftText.isEmpty else {
                throw ComparisonOpenRequestError.invalidClipboard(.emptySnapshot(.left))
            }
            guard !rightText.isEmpty else {
                throw ComparisonOpenRequestError.invalidClipboard(.emptySnapshot(.right))
            }
            return .text
        case (.binary(let leftData, _), .binary(let rightData, _)):
            guard !leftData.isEmpty else {
                throw ComparisonOpenRequestError.invalidClipboard(.emptySnapshot(.left))
            }
            guard !rightData.isEmpty else {
                throw ComparisonOpenRequestError.invalidClipboard(.emptySnapshot(.right))
            }
            return .binary
        case (.empty, _):
            throw ComparisonOpenRequestError.invalidClipboard(.emptySnapshot(.left))
        case (_, .empty):
            throw ComparisonOpenRequestError.invalidClipboard(.emptySnapshot(.right))
        default:
            throw ComparisonOpenRequestError.invalidClipboard(.mixedContentKinds)
        }
    }

    private static func validateClipboardSnapshot(
        _ snapshot: ClipboardSnapshot,
        side: ComparisonOpenSidePosition,
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        let maximumBytes = min(
            limits.maximumDeclaredBytes,
            ClipboardComparisonLimits.default.maximumSnapshotBytes,
            ComparisonOpenEngineCeilings.maximumTwoWayInputBytes
        )
        switch snapshot.content {
        case .text(let text):
            guard
                let metrics = try boundedLineDiffTextMetrics(
                    text,
                    maximum: maximumBytes,
                    side: side,
                    work: &work
                )
            else {
                throw ComparisonOpenRequestError.declaredLimitExceeded(
                    name: "clipboard.\(side.rawValue).bytes",
                    maximum: maximumBytes
                )
            }
            guard metrics.lineCount <= ComparisonOpenEngineCeilings.maximumLineCount else {
                throw ComparisonOpenRequestError.sourceLineCountExceeded(
                    side: side,
                    maximumLines: ComparisonOpenEngineCeilings.maximumLineCount
                )
            }
        case .binary(let data, _):
            guard data.count <= maximumBytes else {
                throw ComparisonOpenRequestError.declaredLimitExceeded(
                    name: "clipboard.\(side.rawValue).bytes",
                    maximum: maximumBytes
                )
            }
            try work.charge(data.count)
        case .empty:
            break
        }
    }

    private static func validate(
        _ transforms: ComparisonOpenTransforms,
        sides: [ComparisonOpenSide],
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        if let unpacker = transforms.unpacker, let prediffer = transforms.prediffer,
            unpacker.ruleIdentifier == prediffer.ruleIdentifier
        {
            throw ComparisonOpenRequestError.externalRuleIdentifiersMustDiffer
        }
        let references: [(ExternalToolCapability, ComparisonOpenExternalRuleReference?)] = [
            (.unpacker, transforms.unpacker),
            (.prediffer, transforms.prediffer)
        ]
        for (capability, reference) in references {
            guard let reference else { continue }
            guard sides.allSatisfy({ if case .localFile = $0.source { true } else { false } }) else {
                throw ComparisonOpenRequestError.externalTransformRequiresLocalFiles(capability: capability)
            }
            guard
                try boundedUTF8Count(
                    reference.ruleIdentifier,
                    maximum: min(limits.maximumOptionStringUTF8Bytes, 128),
                    work: &work
                ) != nil
            else {
                throw ComparisonOpenRequestError.externalRuleIdentifierTooLarge(
                    capability: capability,
                    maximumUTF8Bytes: min(limits.maximumOptionStringUTF8Bytes, 128)
                )
            }
            let bytes = Array(reference.ruleIdentifier.utf8)
            guard let first = bytes.first,
                isASCIIAlphaNumeric(first),
                bytes.allSatisfy({
                    isASCIIAlphaNumeric($0) || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
                })
            else {
                throw ComparisonOpenRequestError.invalidExternalRuleIdentifier(capability: capability)
            }
        }
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte)
            || (0x61...0x7A).contains(byte)
    }

    private static func validate(
        _ filter: ComparisonOpenFilenameFilter,
        requestLimits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        guard filter.rules.count <= requestLimits.maximumOptionItemCount else {
            throw ComparisonOpenRequestError.tooManyOptionItems(
                maximum: requestLimits.maximumOptionItemCount
            )
        }
        let limits = filter.limits
        let nonnegativeLimits = [
            limits.maximumRuleCount,
            limits.maximumPatternUTF8Bytes,
            limits.maximumTotalPatternUTF8Bytes,
            limits.maximumRelativePathUTF8Bytes,
            limits.maximumCompiledStateCount,
            limits.maximumMatchWork,
            limits.maximumRegularExpressionNestingDepth,
            limits.maximumRegularExpressionRepetition
        ]
        guard nonnegativeLimits.allSatisfy({ $0 >= 0 }) else {
            throw ComparisonOpenRequestError.invalidOption(name: "filenameFilter.limits")
        }
        guard limits.maximumRuleCount <= requestLimits.maximumOptionItemCount else {
            throw ComparisonOpenRequestError.declaredLimitExceeded(
                name: "filenameFilter.maximumRuleCount",
                maximum: requestLimits.maximumOptionItemCount
            )
        }
        guard limits.maximumPatternUTF8Bytes <= requestLimits.maximumOptionStringUTF8Bytes else {
            throw ComparisonOpenRequestError.declaredLimitExceeded(
                name: "filenameFilter.maximumPatternUTF8Bytes",
                maximum: requestLimits.maximumOptionStringUTF8Bytes
            )
        }
        guard limits.maximumTotalPatternUTF8Bytes <= requestLimits.maximumTotalOptionStringUTF8Bytes else {
            throw ComparisonOpenRequestError.declaredLimitExceeded(
                name: "filenameFilter.maximumTotalPatternUTF8Bytes",
                maximum: requestLimits.maximumTotalOptionStringUTF8Bytes
            )
        }
        try requireEngineMaximum(
            "filenameFilter.maximumRuleCount",
            limits.maximumRuleCount,
            ComparisonOpenEngineCeilings.maximumFilenameFilterRuleCount
        )
        try requireEngineMaximum(
            "filenameFilter.maximumPatternUTF8Bytes",
            limits.maximumPatternUTF8Bytes,
            ComparisonOpenEngineCeilings.maximumFilenameFilterPatternUTF8Bytes
        )
        try requireEngineMaximum(
            "filenameFilter.maximumTotalPatternUTF8Bytes",
            limits.maximumTotalPatternUTF8Bytes,
            ComparisonOpenEngineCeilings.maximumFilenameFilterTotalPatternUTF8Bytes
        )
        try requireEngineMaximum(
            "filenameFilter.maximumRelativePathUTF8Bytes",
            limits.maximumRelativePathUTF8Bytes,
            ComparisonOpenEngineCeilings.maximumRelativePathUTF8Bytes
        )
        try requireEngineMaximum(
            "filenameFilter.maximumCompiledStateCount",
            limits.maximumCompiledStateCount,
            ComparisonOpenEngineCeilings.maximumFilenameFilterCompiledStateCount
        )
        try requireEngineMaximum(
            "filenameFilter.maximumMatchWork",
            limits.maximumMatchWork,
            ComparisonOpenEngineCeilings.maximumEngineWorkUnits
        )
        try requireEngineMaximum(
            "filenameFilter.maximumRegularExpressionNestingDepth",
            limits.maximumRegularExpressionNestingDepth,
            ComparisonOpenEngineCeilings.maximumFilenameFilterRegularExpressionNestingDepth
        )
        try requireEngineMaximum(
            "filenameFilter.maximumRegularExpressionRepetition",
            limits.maximumRegularExpressionRepetition,
            ComparisonOpenEngineCeilings.maximumFilenameFilterRegularExpressionRepetition
        )
        guard limits.maximumCompiledStateCount <= requestLimits.maximumDeclaredWorkUnits,
            limits.maximumMatchWork <= requestLimits.maximumDeclaredWorkUnits
        else {
            throw ComparisonOpenRequestError.declaredLimitExceeded(
                name: "filenameFilter.work",
                maximum: requestLimits.maximumDeclaredWorkUnits
            )
        }
        try work.charge(limits.maximumCompiledStateCount)

        var totalBytes = 0
        for (index, rule) in filter.rules.enumerated() {
            try checkCancellation()
            try work.charge(1)
            let name = "filenameFilter.rules[\(index)]"
            guard
                let count = try boundedUTF8Count(
                    rule.pattern.source,
                    maximum: requestLimits.maximumOptionStringUTF8Bytes,
                    work: &work
                )
            else {
                throw ComparisonOpenRequestError.optionStringTooLarge(
                    name: name,
                    maximumUTF8Bytes: requestLimits.maximumOptionStringUTF8Bytes
                )
            }
            totalBytes = try addingOptionBytes(count, to: totalBytes, limits: requestLimits)
        }
        let compiled: FilenameFilter
        try checkCancellation()
        do {
            compiled = try FilenameFilter(
                rules: filter.rules,
                defaultDecision: filter.defaultDecision,
                matchSemantics: filter.matchSemantics,
                casePolicy: filter.casePolicy,
                limits: filter.limits
            )
        } catch is CancellationError {
            throw ComparisonOpenRequestError.cancelled
        }
        try checkCancellation()
        if let diagnostic = compiled.diagnostics.first {
            throw ComparisonOpenRequestError.invalidFilenameFilter(diagnostic)
        }
    }

    private static func validateAggregateOptionStrings(
        _ request: ComparisonOpenRequest,
        modeOptions: ComparisonOpenModeOptions,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        let limits = request.limits
        var itemCount = 0
        func checkedCount(_ addition: Int) throws {
            let (next, overflow) = itemCount.addingReportingOverflow(addition)
            guard !overflow, next <= limits.maximumOptionItemCount else {
                throw ComparisonOpenRequestError.tooManyOptionItems(
                    maximum: limits.maximumOptionItemCount
                )
            }
            itemCount = next
        }

        var values: [String] = []
        switch modeOptions {
        case .defaults, .table, .binary, .folder:
            break
        case .text(let twoWay, _):
            try checkedCount(twoWay.lineFilters.count)
            try checkedCount(twoWay.substitutions.count)
            values.append(contentsOf: lineOptionStrings(twoWay))
        case .image(let loading, _):
            try checkedCount(loading.supportedTypeIdentifiers.count)
            values.append(contentsOf: loading.supportedTypeIdentifiers)
        case .webpage(let twoWay, let threeWay):
            let lineOptions = twoWay.lineDiffOptions
            try checkedCount(lineOptions.lineFilters.count)
            try checkedCount(lineOptions.substitutions.count)
            values.append(contentsOf: lineOptionStrings(lineOptions))
            if let identifier = threeWay.expectedContext?.identifier {
                try checkedCount(1)
                values.append(identifier)
            }
        }
        if case .table(let parsing, _, let threeWay) = modeOptions {
            let parsingOptions = [parsing, threeWay.parsingOptions]
            for selectedParsing in parsingOptions {
                try checkedCount(1 + (selectedParsing.quote == nil ? 0 : 1))
                values.append(String(selectedParsing.delimiter))
                if let quote = selectedParsing.quote { values.append(String(quote)) }
            }
        }
        if let filter = request.filenameFilter {
            try checkedCount(filter.rules.count)
            values.append(contentsOf: filter.rules.map { $0.pattern.source })
        }
        if let identifier = request.transforms.unpacker?.ruleIdentifier {
            try checkedCount(1)
            values.append(identifier)
        }
        if let identifier = request.transforms.prediffer?.ruleIdentifier {
            try checkedCount(1)
            values.append(identifier)
        }

        var totalBytes = 0
        for (index, value) in values.enumerated() {
            try checkCancellation()
            guard
                let count = try boundedUTF8Count(
                    value,
                    maximum: request.limits.maximumOptionStringUTF8Bytes,
                    work: &work
                )
            else {
                throw ComparisonOpenRequestError.optionStringTooLarge(
                    name: "optionStrings[\(index)]",
                    maximumUTF8Bytes: request.limits.maximumOptionStringUTF8Bytes
                )
            }
            totalBytes = try addingOptionBytes(count, to: totalBytes, limits: request.limits)
        }
    }

    private static func lineOptionStrings(_ options: LineDiffOptions) -> [String] {
        let lineFilters = options.lineFilters.map(\.pattern)
        let substitutions = options.substitutions.flatMap { [$0.pattern, $0.replacement] }
        return lineFilters + substitutions
    }

    private static func validate(
        _ options: ComparisonOpenModeOptions,
        for mode: ComparisonProject.Mode,
        isThreeWay: Bool,
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        switch options {
        case .defaults:
            return
        case .text(let twoWay, let threeWay):
            try requireMode(.text, actual: mode)
            try validate(
                twoWay,
                syntaxIsActive: !isThreeWay,
                limits: limits,
                work: &work
            )
            try validate(threeWay, limits: limits)
        case .table(let parsing, let twoWay, let threeWay):
            try requireMode(.table, actual: mode)
            try validate(parsing, limits: limits)
            try validate(twoWay, limits: limits)
            try validate(threeWay, limits: limits)
        case .binary(let twoWay, let threeWay):
            try requireMode(.binary, actual: mode)
            try validate(twoWay, limits: limits)
            try validate(threeWay, limits: limits)
        case .image(let loading, let comparison):
            try requireMode(.image, actual: mode)
            try validate(loading, limits: limits, work: &work)
            try validate(comparison, limits: limits)
        case .webpage(let twoWay, let threeWay):
            try requireMode(.webpage, actual: mode)
            try validate(
                twoWay,
                lineRuleSyntaxIsActive: !isThreeWay,
                limits: limits,
                work: &work
            )
            try validate(threeWay, limits: limits, work: &work)
        case .folder(let scanning, let twoWay, let threeWay):
            try requireMode(.folder, actual: mode)
            try validate(scanning, limits: limits)
            try validate(twoWay)
            try validate(threeWay, limits: limits)
        }
    }

    private static func requireMode(
        _ optionMode: ComparisonProject.Mode,
        actual mode: ComparisonProject.Mode
    ) throws {
        guard optionMode == mode else {
            throw ComparisonOpenRequestError.modeOptionsMismatch(expected: mode, actual: optionMode)
        }
    }

    private static func validate(
        _ options: LineDiffOptions,
        syntaxIsActive: Bool,
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        let lineFilters = options.lineFilters
        let substitutions = options.substitutions
        let (itemCount, itemCountOverflow) = lineFilters.count.addingReportingOverflow(
            substitutions.count
        )
        guard !itemCountOverflow, itemCount <= limits.maximumOptionItemCount
        else {
            throw ComparisonOpenRequestError.tooManyOptionItems(maximum: limits.maximumOptionItemCount)
        }
        var totalBytes = 0
        for (index, rule) in lineFilters.enumerated() {
            try checkCancellation()
            totalBytes = try validateOptionString(
                rule.pattern,
                name: "lineFilters[\(index)].pattern",
                totalBytes: totalBytes,
                limits: limits,
                work: &work
            )
            if syntaxIsActive, options.lineFiltersEnabled {
                try validateRegularExpression(
                    rule.pattern,
                    name: "lineFilters[\(index)].pattern",
                    caseSensitive: rule.caseSensitive,
                    work: &work
                )
            }
        }
        for (index, rule) in substitutions.enumerated() {
            try checkCancellation()
            totalBytes = try validateOptionString(
                rule.pattern,
                name: "substitutions[\(index)].pattern",
                totalBytes: totalBytes,
                limits: limits,
                work: &work
            )
            totalBytes = try validateOptionString(
                rule.replacement,
                name: "substitutions[\(index)].replacement",
                totalBytes: totalBytes,
                limits: limits,
                work: &work
            )
            if syntaxIsActive, options.substitutionsEnabled {
                if !rule.pattern.isEmpty {
                    try validateRegularExpression(
                        rule.pattern,
                        name: "substitutions[\(index)].pattern",
                        caseSensitive: rule.caseSensitive,
                        substitution: true,
                        work: &work
                    )
                }
            }
        }
    }

    private static func validateRegularExpression(
        _ pattern: String,
        name: String,
        caseSensitive: Bool,
        substitution: Bool = false,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        try checkCancellation()
        guard pattern.utf8.count <= ComparisonOpenEngineCeilings.maximumPCREPatternUTF8Bytes else {
            throw ComparisonOpenRequestError.engineLimitExceeded(
                name: name,
                maximum: ComparisonOpenEngineCeilings.maximumPCREPatternUTF8Bytes
            )
        }
        try work.charge(pattern.utf8.count)
        let bytes = Array(pattern.utf8)
        let status: Int32
        if substitution {
            var result = mmx_bytes_result(bytes: nil, size: 0)
            status = bytes.withUnsafeBytes {
                mmx_regex_substitute(
                    nil,
                    0,
                    $0.baseAddress,
                    $0.count,
                    nil,
                    0,
                    caseSensitive ? 1 : 0,
                    0,
                    &result
                )
            }
            mmx_bytes_result_free(&result)
        } else {
            var filter: UnsafeMutableRawPointer?
            status = bytes.withUnsafeBytes {
                mmx_line_filter_create(
                    $0.baseAddress,
                    $0.count,
                    caseSensitive ? 1 : 0,
                    &filter
                )
            }
            if let filter { mmx_line_filter_free(filter) }
        }
        try checkCancellation()
        guard status == 0 else {
            throw ComparisonOpenRequestError.invalidOption(name: name)
        }
    }

    private static func validate(
        _ options: ThreeWayTextMergeOptions,
        limits: ComparisonOpenRequestLimits
    ) throws {
        try requireEngineMaximum(
            "text.maximumInputBytes",
            options.maximumInputBytes,
            ComparisonOpenEngineCeilings.maximumThreeWayInputBytes
        )
        try requireEngineMaximum(
            "text.maximumInputLines",
            options.maximumInputLines,
            ComparisonOpenEngineCeilings.maximumLineCount
        )
        try requireEngineMaximum(
            "text.maximumOutputBytes",
            options.maximumOutputBytes,
            ComparisonOpenEngineCeilings.maximumThreeWayOutputBytes
        )
        try requireEngineMaximum(
            "text.maximumOutputLines",
            options.maximumOutputLines,
            ComparisonOpenEngineCeilings.maximumThreeWayOutputLines
        )
        try requireEngineMaximum(
            "text.maximumRegions",
            options.maximumRegions,
            ComparisonOpenEngineCeilings.maximumThreeWayRegions
        )
        try validateNonnegative(
            [
                ("text.maximumInputBytes", options.maximumInputBytes),
                ("text.maximumInputLines", options.maximumInputLines),
                ("text.maximumOutputBytes", options.maximumOutputBytes),
                ("text.maximumOutputLines", options.maximumOutputLines),
                ("text.maximumRegions", options.maximumRegions)
            ],
            limits: limits
        )
    }

    private static func validate(
        _ options: DelimitedTableParsingOptions,
        limits: ComparisonOpenRequestLimits
    ) throws {
        guard validTableCharacter(options.delimiter),
            options.quote.map(validTableCharacter) ?? true,
            options.delimiter != options.quote
        else {
            throw ComparisonOpenRequestError.invalidOption(name: "table.parsing")
        }
        let declared = options.limits
        guard declared.maximumRows > 0,
            declared.maximumColumnsPerRow > 0,
            declared.maximumTotalCells > 0
        else {
            throw ComparisonOpenRequestError.invalidOption(name: "table.parsing.limits")
        }
        try requireEngineMaximum(
            "table.maximumInputBytes",
            declared.maximumInputBytes,
            ComparisonOpenEngineCeilings.maximumTwoWayInputBytes
        )
        try requireEngineMaximum(
            "table.maximumRows",
            declared.maximumRows,
            ComparisonOpenEngineCeilings.maximumTableRows
        )
        try requireEngineMaximum(
            "table.maximumColumnsPerRow",
            declared.maximumColumnsPerRow,
            ComparisonOpenEngineCeilings.maximumTableColumnsPerRow
        )
        try requireEngineMaximum(
            "table.maximumTotalCells",
            declared.maximumTotalCells,
            ComparisonOpenEngineCeilings.maximumTableCells
        )
        try requireEngineMaximum(
            "table.maximumCellBytes",
            declared.maximumCellBytes,
            ComparisonOpenEngineCeilings.maximumTableCellBytes
        )
        try validateNonnegative(
            [
                ("table.maximumInputBytes", declared.maximumInputBytes),
                ("table.maximumRows", declared.maximumRows),
                ("table.maximumColumnsPerRow", declared.maximumColumnsPerRow),
                ("table.maximumTotalCells", declared.maximumTotalCells),
                ("table.maximumCellBytes", declared.maximumCellBytes)
            ],
            limits: limits
        )
    }

    private static func validTableCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character != "\0" && character != "\r"
            && character != "\n"
    }

    private static func validate(
        _ options: TableComparisonOptions,
        limits: ComparisonOpenRequestLimits
    ) throws {
        try requireEngineMaximum(
            "table.maximumExactEditDistance",
            options.maximumExactEditDistance,
            ComparisonOpenEngineCeilings.maximumExactEditDistance
        )
        try requireEngineMaximum(
            "table.maximumAlignmentWork",
            options.maximumAlignmentWork,
            ComparisonOpenEngineCeilings.maximumTwoWayAlignmentWork
        )
        try requireEngineMaximum(
            "table.maximumComparedRows",
            options.maximumComparedRows,
            ComparisonOpenEngineCeilings.maximumComparedTableItems
        )
        try requireEngineMaximum(
            "table.maximumComparedCells",
            options.maximumComparedCells,
            ComparisonOpenEngineCeilings.maximumComparedTableItems
        )
        try validateNonnegative(
            [
                ("table.maximumExactEditDistance", options.maximumExactEditDistance),
                ("table.maximumAlignmentWork", options.maximumAlignmentWork),
                ("table.maximumComparedRows", options.maximumComparedRows),
                ("table.maximumComparedCells", options.maximumComparedCells)
            ],
            limits: limits
        )
    }

    private static func validate(
        _ options: ThreeWayTableComparisonOptions,
        limits: ComparisonOpenRequestLimits
    ) throws {
        try validate(options.parsingOptions, limits: limits)
        try validate(options.comparisonOptions, limits: limits)
        try requireEngineMaximum(
            "table.maximumComparedValueBytes",
            options.maximumComparedValueBytes,
            ComparisonOpenEngineCeilings.maximumThreeWayOutputBytes
        )
        try requireEngineMaximum(
            "table.maximumResultRows",
            options.maximumResultRows,
            ComparisonOpenEngineCeilings.maximumThreeWayTableItems
        )
        try requireEngineMaximum(
            "table.maximumResultCells",
            options.maximumResultCells,
            ComparisonOpenEngineCeilings.maximumThreeWayTableItems
        )
        try validateNonnegative(
            [
                ("table.maximumComparedValueBytes", options.maximumComparedValueBytes),
                ("table.maximumResultRows", options.maximumResultRows),
                ("table.maximumResultCells", options.maximumResultCells)
            ],
            limits: limits
        )
    }

    private static func validate(
        _ options: BinaryComparisonOptions,
        limits: ComparisonOpenRequestLimits
    ) throws {
        try requireEngineMaximum(
            "binary.maximumExactEditDistance",
            options.maximumExactEditDistance,
            ComparisonOpenEngineCeilings.maximumExactEditDistance
        )
        try requireEngineMaximum(
            "binary.maximumAlignmentWork",
            options.maximumAlignmentWork,
            ComparisonOpenEngineCeilings.maximumTwoWayAlignmentWork
        )
        try validateNonnegative(
            [
                ("binary.maximumExactEditDistance", options.maximumExactEditDistance),
                ("binary.maximumAlignmentWork", options.maximumAlignmentWork)
            ],
            limits: limits
        )
    }

    private static func validate(
        _ options: ThreeWayBinaryComparisonOptions,
        limits: ComparisonOpenRequestLimits
    ) throws {
        try requireEngineMaximum(
            "binary.maximumInputBytes",
            options.maximumInputBytes,
            ComparisonOpenEngineCeilings.maximumThreeWayInputBytes
        )
        try requireEngineMaximum(
            "binary.maximumExactEditDistance",
            options.maximumExactEditDistance,
            ComparisonOpenEngineCeilings.maximumExactEditDistance
        )
        try requireEngineMaximum(
            "binary.maximumAlignmentWork",
            options.maximumAlignmentWork,
            ComparisonOpenEngineCeilings.maximumThreeWayAlignmentWork
        )
        try requireEngineMaximum(
            "binary.maximumRegions",
            options.maximumRegions,
            ComparisonOpenEngineCeilings.maximumCollectionItems
        )
        try requireEngineMaximum(
            "binary.maximumOutputBytes",
            options.maximumOutputBytes,
            ComparisonOpenEngineCeilings.maximumThreeWayOutputBytes
        )
        try validateNonnegative(
            [
                ("binary.maximumInputBytes", options.maximumInputBytes),
                ("binary.maximumExactEditDistance", options.maximumExactEditDistance),
                ("binary.maximumAlignmentWork", options.maximumAlignmentWork),
                ("binary.maximumRegions", options.maximumRegions),
                ("binary.maximumOutputBytes", options.maximumOutputBytes)
            ],
            limits: limits
        )
    }

    private static func validate(
        _ options: ImageComparisonLimits,
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        guard options.maximumEncodedBytes > 0,
            options.maximumDimension > 0,
            options.maximumPixelCount > 0,
            options.maximumDecodedBytes > 0,
            !options.supportedTypeIdentifiers.isEmpty
        else {
            throw ComparisonOpenRequestError.invalidOption(name: "image.loading")
        }
        try requireEngineMaximum(
            "image.maximumEncodedBytes",
            options.maximumEncodedBytes,
            ComparisonOpenEngineCeilings.maximumTwoWayInputBytes
        )
        try requireEngineMaximum(
            "image.maximumDimension",
            options.maximumDimension,
            ComparisonOpenEngineCeilings.maximumImageDimension
        )
        try requireEngineMaximum(
            "image.maximumPixelCount",
            options.maximumPixelCount,
            ComparisonOpenEngineCeilings.maximumImagePixels
        )
        try requireEngineMaximum(
            "image.maximumDecodedBytes",
            options.maximumDecodedBytes,
            ComparisonOpenEngineCeilings.maximumImageDecodedBytes
        )
        try validateNonnegative(
            [
                ("image.maximumEncodedBytes", options.maximumEncodedBytes),
                ("image.maximumDimension", options.maximumDimension),
                ("image.maximumPixelCount", options.maximumPixelCount),
                ("image.maximumDecodedBytes", options.maximumDecodedBytes)
            ],
            limits: limits
        )
        guard options.supportedTypeIdentifiers.count <= limits.maximumOptionItemCount else {
            throw ComparisonOpenRequestError.tooManyOptionItems(maximum: limits.maximumOptionItemCount)
        }
        var totalBytes = 0
        for identifier in options.supportedTypeIdentifiers {
            guard ImageComparisonLimits.supportedStaticTypeIdentifiers.contains(identifier) else {
                throw ComparisonOpenRequestError.invalidOption(name: "image.supportedTypeIdentifier")
            }
            totalBytes = try validateOptionString(
                identifier,
                name: "image.supportedTypeIdentifier",
                totalBytes: totalBytes,
                limits: limits,
                work: &work
            )
        }
    }

    private static func validate(
        _ options: ImageComparisonOptions,
        limits: ComparisonOpenRequestLimits
    ) throws {
        guard options.maximumCanvasPixels > 0,
            options.maximumRegions > 0,
            options.maximumQueuedPixels > 0
        else {
            throw ComparisonOpenRequestError.invalidOption(name: "image.comparison")
        }
        try requireEngineMaximum(
            "image.maximumCanvasPixels",
            options.maximumCanvasPixels,
            ComparisonOpenEngineCeilings.maximumImagePixels
        )
        try requireEngineMaximum(
            "image.maximumRegions",
            options.maximumRegions,
            ComparisonOpenEngineCeilings.maximumImageRegions
        )
        try requireEngineMaximum(
            "image.maximumQueuedPixels",
            options.maximumQueuedPixels,
            ComparisonOpenEngineCeilings.maximumImageQueuedPixels
        )
        try validateNonnegative(
            [
                ("image.maximumCanvasPixels", options.maximumCanvasPixels),
                ("image.maximumRegions", options.maximumRegions),
                ("image.maximumQueuedPixels", options.maximumQueuedPixels)
            ],
            limits: limits
        )
    }

    private static func validate(
        _ options: WebPageComparisonOptions,
        lineRuleSyntaxIsActive: Bool,
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        try validate(
            options.lineDiffOptions,
            syntaxIsActive: lineRuleSyntaxIsActive,
            limits: limits,
            work: &work
        )
        let declared = options.limits
        try requireEngineMaximum(
            "webpage.maximumInputBytes",
            declared.maximumInputBytes,
            ComparisonOpenEngineCeilings.maximumTwoWayInputBytes
        )
        try requireEngineMaximum(
            "webpage.maximumTokenCount",
            declared.maximumTokenCount,
            WebPageComparisonLimits.default.maximumTokenCount
        )
        try requireEngineMaximum(
            "webpage.maximumAttributeCount",
            declared.maximumAttributeCount,
            WebPageComparisonLimits.default.maximumAttributeCount
        )
        try requireEngineMaximum(
            "webpage.maximumAttributesPerTag",
            declared.maximumAttributesPerTag,
            WebPageComparisonLimits.default.maximumAttributesPerTag
        )
        try requireEngineMaximum(
            "webpage.maximumElementDepth",
            declared.maximumElementDepth,
            WebPageComparisonLimits.default.maximumElementDepth
        )
        try requireEngineMaximum(
            "webpage.maximumWorkUnits",
            declared.maximumWorkUnits,
            WebPageComparisonLimits.default.maximumWorkUnits
        )
        try requireEngineMaximum(
            "webpage.maximumOutputBytes",
            declared.maximumOutputBytes,
            ComparisonOpenEngineCeilings.maximumTwoWayInputBytes
        )
        try validateNonnegative(
            [
                ("webpage.maximumInputBytes", declared.maximumInputBytes),
                ("webpage.maximumTokenCount", declared.maximumTokenCount),
                ("webpage.maximumAttributeCount", declared.maximumAttributeCount),
                ("webpage.maximumAttributesPerTag", declared.maximumAttributesPerTag),
                ("webpage.maximumElementDepth", declared.maximumElementDepth),
                ("webpage.maximumWorkUnits", declared.maximumWorkUnits),
                ("webpage.maximumOutputBytes", declared.maximumOutputBytes)
            ],
            limits: limits
        )
    }

    private static func validate(
        _ options: ThreeWayWebPageComparisonOptions,
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        let declared = options.limits
        try requireEngineMaximum(
            "webpage.maximumSourceInputBytes",
            declared.maximumSourceInputBytesPerSnapshot,
            ComparisonOpenEngineCeilings.maximumThreeWayInputBytes
        )
        try requireEngineMaximum(
            "webpage.maximumNormalizedInputBytes",
            declared.maximumNormalizedInputBytesPerSnapshot,
            ComparisonOpenEngineCeilings.maximumThreeWayInputBytes
        )
        try requireEngineMaximum(
            "webpage.maximumTokenCount",
            declared.maximumTokenCountPerSnapshot,
            ThreeWayWebPageComparisonLimits.default.maximumTokenCountPerSnapshot
        )
        try requireEngineMaximum(
            "webpage.maximumAttributeCount",
            declared.maximumAttributeCountPerSnapshot,
            ThreeWayWebPageComparisonLimits.default.maximumAttributeCountPerSnapshot
        )
        try requireEngineMaximum(
            "webpage.maximumTotalNormalizedInputBytes",
            declared.maximumTotalNormalizedInputBytes,
            ComparisonOpenEngineCeilings.maximumThreeWayOutputBytes
        )
        try requireEngineMaximum(
            "webpage.maximumInputLines",
            declared.maximumInputLinesPerSnapshot,
            ComparisonOpenEngineCeilings.maximumLineCount
        )
        try requireEngineMaximum(
            "webpage.maximumMetadataEntries",
            declared.maximumMetadataEntriesPerSnapshot,
            ThreeWayWebPageComparisonLimits.default.maximumMetadataEntriesPerSnapshot
        )
        try requireEngineMaximum(
            "webpage.maximumMetadataBytes",
            declared.maximumMetadataBytes,
            ThreeWayWebPageComparisonLimits.default.maximumMetadataBytes
        )
        try requireEngineMaximum(
            "webpage.maximumWorkUnits",
            declared.maximumWorkUnits,
            ComparisonOpenEngineCeilings.maximumEngineWorkUnits
        )
        try requireEngineMaximum(
            "webpage.maximumResultRegions",
            declared.maximumResultRegions,
            ComparisonOpenEngineCeilings.maximumThreeWayRegions
        )
        try requireEngineMaximum(
            "webpage.maximumMappedSegments",
            declared.maximumMappedSegments,
            ThreeWayWebPageComparisonLimits.default.maximumMappedSegments
        )
        try requireEngineMaximum(
            "webpage.maximumOutputBytes",
            declared.maximumOutputBytes,
            ComparisonOpenEngineCeilings.maximumThreeWayOutputBytes
        )
        try requireEngineMaximum(
            "webpage.maximumOutputLines",
            declared.maximumOutputLines,
            ComparisonOpenEngineCeilings.maximumThreeWayOutputLines
        )
        try validateNonnegative(
            [
                ("webpage.maximumSourceInputBytes", declared.maximumSourceInputBytesPerSnapshot),
                ("webpage.maximumNormalizedInputBytes", declared.maximumNormalizedInputBytesPerSnapshot),
                ("webpage.maximumTokenCount", declared.maximumTokenCountPerSnapshot),
                ("webpage.maximumAttributeCount", declared.maximumAttributeCountPerSnapshot),
                ("webpage.maximumTotalNormalizedInputBytes", declared.maximumTotalNormalizedInputBytes),
                ("webpage.maximumInputLines", declared.maximumInputLinesPerSnapshot),
                ("webpage.maximumMetadataEntries", declared.maximumMetadataEntriesPerSnapshot),
                ("webpage.maximumMetadataBytes", declared.maximumMetadataBytes),
                ("webpage.maximumWorkUnits", declared.maximumWorkUnits),
                ("webpage.maximumResultRegions", declared.maximumResultRegions),
                ("webpage.maximumMappedSegments", declared.maximumMappedSegments),
                ("webpage.maximumOutputBytes", declared.maximumOutputBytes),
                ("webpage.maximumOutputLines", declared.maximumOutputLines)
            ],
            limits: limits
        )
        if let context = options.expectedContext {
            guard !context.identifier.isEmpty else {
                throw ComparisonOpenRequestError.invalidOption(name: "webpage.expectedContext.identifier")
            }
            _ = try validateOptionString(
                context.identifier,
                name: "webpage.expectedContext.identifier",
                totalBytes: 0,
                limits: limits,
                work: &work
            )
        }
    }

    private static func validateScratchpads(
        _ metrics: [ComparisonOpenSidePosition: ComparisonOpenTextMetrics],
        mode: ComparisonProject.Mode,
        modeOptions: ComparisonOpenModeOptions,
        isThreeWay: Bool
    ) throws {
        let maximumBytes: Int?
        let maximumLines: Int?
        let maximumCombinedBytes: Int?
        switch mode {
        case .text:
            if isThreeWay {
                let options =
                    if case .text(_, let threeWay) = modeOptions {
                        threeWay
                    } else {
                        ThreeWayTextMergeOptions()
                    }
                maximumBytes = options.maximumInputBytes
                maximumLines = options.maximumInputLines
            } else {
                maximumBytes = ComparisonOpenEngineCeilings.maximumTwoWayInputBytes
                maximumLines = ComparisonOpenEngineCeilings.maximumLineCount
            }
            maximumCombinedBytes = nil
        case .table:
            let parsing: DelimitedTableParsingOptions
            if case .table(let twoWay, _, let threeWay) = modeOptions {
                parsing = isThreeWay ? threeWay.parsingOptions : twoWay
            } else {
                parsing = .commaSeparated
            }
            maximumBytes = parsing.limits.maximumInputBytes
            maximumLines = nil
            maximumCombinedBytes = nil
        case .webpage:
            let twoWay =
                if case .webpage(let twoWay, _) = modeOptions {
                    twoWay
                } else {
                    WebPageComparisonOptions.default
                }
            if isThreeWay {
                let threeWay =
                    if case .webpage(_, let threeWay) = modeOptions {
                        threeWay
                    } else {
                        ThreeWayWebPageComparisonOptions.default
                    }
                if twoWay.mode == .source {
                    maximumBytes = min(
                        twoWay.limits.maximumInputBytes,
                        twoWay.limits.maximumOutputBytes,
                        threeWay.limits.maximumSourceInputBytesPerSnapshot,
                        threeWay.limits.maximumNormalizedInputBytesPerSnapshot
                    )
                    maximumLines = threeWay.limits.maximumInputLinesPerSnapshot
                    maximumCombinedBytes = threeWay.limits.maximumTotalNormalizedInputBytes
                } else {
                    maximumBytes = min(
                        twoWay.limits.maximumInputBytes,
                        threeWay.limits.maximumSourceInputBytesPerSnapshot
                    )
                    maximumLines = nil
                    maximumCombinedBytes = nil
                }
            } else {
                if twoWay.mode == .source {
                    maximumBytes = min(
                        twoWay.limits.maximumInputBytes,
                        twoWay.limits.maximumOutputBytes,
                        ComparisonOpenEngineCeilings.maximumTwoWayInputBytes
                    )
                    maximumLines = ComparisonOpenEngineCeilings.maximumLineCount
                } else {
                    maximumBytes = twoWay.limits.maximumInputBytes
                    maximumLines = nil
                }
                maximumCombinedBytes = nil
            }
        case .automatic, .binary, .image, .folder:
            maximumBytes = nil
            maximumLines = nil
            maximumCombinedBytes = nil
        }

        var combinedBytes = 0
        for (side, metric) in metrics {
            if let maximumBytes, metric.utf8Bytes > maximumBytes {
                throw ComparisonOpenRequestError.scratchpadTooLarge(
                    side: side,
                    maximumUTF8Bytes: maximumBytes
                )
            }
            if let maximumLines, metric.lineCount > maximumLines {
                throw ComparisonOpenRequestError.sourceLineCountExceeded(
                    side: side,
                    maximumLines: maximumLines
                )
            }
            let (nextCombinedBytes, overflow) = combinedBytes.addingReportingOverflow(metric.utf8Bytes)
            guard !overflow else {
                throw ComparisonOpenRequestError.combinedScratchpadsTooLarge(
                    maximumUTF8Bytes: maximumCombinedBytes ?? 0
                )
            }
            combinedBytes = nextCombinedBytes
        }
        if let maximumCombinedBytes, combinedBytes > maximumCombinedBytes {
            throw ComparisonOpenRequestError.combinedScratchpadsTooLarge(
                maximumUTF8Bytes: maximumCombinedBytes
            )
        }
    }

    private static func validate(
        _ options: FolderScanOptions,
        limits: ComparisonOpenRequestLimits
    ) throws {
        let declared = options.limits
        try requireEngineMaximum("folder.maximumDepth", declared.maximumDepth, 512)
        try requireEngineMaximum("folder.maximumEntries", declared.maximumEntries, 1_000_000)
        try requireEngineMaximum(
            "folder.maximumExaminedEntries",
            declared.maximumExaminedEntries,
            ComparisonOpenEngineCeilings.maximumFolderEntries
        )
        try requireEngineMaximum(
            "folder.maximumIssues",
            declared.maximumIssues,
            ComparisonOpenEngineCeilings.maximumFolderIssues
        )
        try requireEngineMaximum(
            "folder.maximumOpenDirectoryDescriptors",
            declared.maximumOpenDirectoryDescriptors,
            ComparisonOpenEngineCeilings.maximumFolderOpenDirectoryDescriptors
        )
        try requireEngineMaximum(
            "folder.maximumPendingEntryNames",
            declared.maximumPendingEntryNames,
            1_000_000
        )
        try requireEngineMaximum(
            "folder.maximumRelativePathUTF8Bytes",
            declared.maximumRelativePathUTF8Bytes,
            ComparisonOpenEngineCeilings.maximumRelativePathUTF8Bytes
        )
        guard declared.maximumTotalAccountedBytes <= 1_125_899_906_842_624 else {
            throw ComparisonOpenRequestError.engineLimitExceeded(
                name: "folder.maximumTotalAccountedBytes",
                maximum: 1_125_899_906_842_624
            )
        }
        try validateNonnegative(
            [
                ("folder.maximumDepth", declared.maximumDepth),
                ("folder.maximumEntries", declared.maximumEntries),
                ("folder.maximumExaminedEntries", declared.maximumExaminedEntries),
                ("folder.maximumIssues", declared.maximumIssues),
                ("folder.maximumOpenDirectoryDescriptors", declared.maximumOpenDirectoryDescriptors),
                ("folder.maximumPendingEntryNames", declared.maximumPendingEntryNames),
                ("folder.maximumRelativePathUTF8Bytes", declared.maximumRelativePathUTF8Bytes),
                ("folder.maximumTotalAccountedBytes", Int(clamping: declared.maximumTotalAccountedBytes))
            ],
            limits: limits
        )
    }

    private static func validate(_ options: FolderComparisonOptions) throws {
        guard options.modificationDateTolerance.isFinite,
            options.modificationDateTolerance >= 0
        else {
            throw ComparisonOpenRequestError.invalidOption(name: "folder.modificationDateTolerance")
        }
    }

    private static func validate(
        _ options: ThreeWayFolderComparisonOptions,
        limits: ComparisonOpenRequestLimits
    ) throws {
        try validate(options.comparison)
        try requireEngineMaximum(
            "folder.maximumEntriesPerSnapshot",
            options.maximumEntriesPerSnapshot,
            1_000_000
        )
        try requireEngineMaximum(
            "folder.maximumResultEntries",
            options.maximumResultEntries,
            3_000_000
        )
        try requireEngineMaximum(
            "folder.maximumRelativePathUTF8Bytes",
            options.maximumRelativePathUTF8Bytes,
            ComparisonOpenEngineCeilings.maximumRelativePathUTF8Bytes
        )
        try requireEngineMaximum(
            "folder.maximumDigestBytes",
            options.maximumDigestBytes,
            1_048_576
        )
        try requireEngineMaximum(
            "folder.maximumDigestAlgorithmUTF8Bytes",
            options.maximumDigestAlgorithmUTF8Bytes,
            1_024
        )
        try requireEngineMaximum(
            "folder.maximumWorkUnits",
            options.maximumWorkUnits,
            256 * 1024 * 1024
        )
        try validateNonnegative(
            [
                ("folder.maximumEntriesPerSnapshot", options.maximumEntriesPerSnapshot),
                ("folder.maximumResultEntries", options.maximumResultEntries),
                ("folder.maximumRelativePathUTF8Bytes", options.maximumRelativePathUTF8Bytes),
                ("folder.maximumDigestBytes", options.maximumDigestBytes),
                ("folder.maximumDigestAlgorithmUTF8Bytes", options.maximumDigestAlgorithmUTF8Bytes),
                ("folder.maximumWorkUnits", options.maximumWorkUnits)
            ],
            limits: limits
        )
    }

    private static func validateNonnegative(
        _ values: [(String, Int)],
        limits: ComparisonOpenRequestLimits
    ) throws {
        for (name, value) in values {
            guard value >= 0 else {
                throw ComparisonOpenRequestError.invalidOption(name: name)
            }
            let maximum =
                name.lowercased().contains("byte")
                ? limits.maximumDeclaredBytes
                : limits.maximumDeclaredWorkUnits
            guard value <= maximum else {
                throw ComparisonOpenRequestError.declaredLimitExceeded(name: name, maximum: maximum)
            }
        }
    }

    private static func requireEngineMaximum(
        _ name: String,
        _ value: Int,
        _ maximum: Int
    ) throws {
        guard value <= maximum else {
            throw ComparisonOpenRequestError.engineLimitExceeded(name: name, maximum: maximum)
        }
    }

    private static func validate(_ limits: ComparisonOpenRequestLimits) throws {
        let values: [(ComparisonOpenRequestLimit, Int, Int)] = [
            (.pathUTF8Bytes, limits.maximumPathUTF8Bytes, ComparisonOpenRequestLimits.hardMaximumPathUTF8Bytes),
            (
                .totalPathUTF8Bytes,
                limits.maximumTotalPathUTF8Bytes,
                ComparisonOpenRequestLimits.hardMaximumTotalPathUTF8Bytes
            ),
            (
                .remoteURLUTF8Bytes,
                limits.maximumRemoteURLUTF8Bytes,
                ComparisonOpenRequestLimits.hardMaximumRemoteURLUTF8Bytes
            ),
            (
                .scratchpadUTF8Bytes,
                limits.maximumScratchpadUTF8Bytes,
                ComparisonOpenRequestLimits.hardMaximumScratchpadUTF8Bytes
            ),
            (
                .combinedScratchpadUTF8Bytes,
                limits.maximumCombinedScratchpadUTF8Bytes,
                ComparisonOpenRequestLimits.hardMaximumCombinedScratchpadUTF8Bytes
            ),
            (
                .labelUTF8Bytes,
                limits.maximumLabelUTF8Bytes,
                ComparisonOpenRequestLimits.hardMaximumLabelUTF8Bytes
            ),
            (
                .optionItemCount,
                limits.maximumOptionItemCount,
                ComparisonOpenRequestLimits.hardMaximumOptionItemCount
            ),
            (
                .optionStringUTF8Bytes,
                limits.maximumOptionStringUTF8Bytes,
                ComparisonOpenRequestLimits.hardMaximumOptionStringUTF8Bytes
            ),
            (
                .totalOptionStringUTF8Bytes,
                limits.maximumTotalOptionStringUTF8Bytes,
                ComparisonOpenRequestLimits.hardMaximumTotalOptionStringUTF8Bytes
            ),
            (
                .declaredBytes,
                limits.maximumDeclaredBytes,
                ComparisonOpenRequestLimits.hardMaximumDeclaredBytes
            ),
            (
                .declaredWorkUnits,
                limits.maximumDeclaredWorkUnits,
                ComparisonOpenRequestLimits.hardMaximumDeclaredWorkUnits
            ),
            (
                .planningWorkUnits,
                limits.maximumPlanningWorkUnits,
                ComparisonOpenRequestLimits.hardMaximumPlanningWorkUnits
            )
        ]
        for (limit, value, hardMaximum) in values {
            guard value >= 0, value <= hardMaximum else {
                throw ComparisonOpenRequestError.invalidLimit(limit)
            }
        }
        guard limits.maximumTotalPathUTF8Bytes >= limits.maximumPathUTF8Bytes else {
            throw ComparisonOpenRequestError.invalidLimit(.totalPathUTF8Bytes)
        }
        guard limits.maximumCombinedScratchpadUTF8Bytes >= limits.maximumScratchpadUTF8Bytes else {
            throw ComparisonOpenRequestError.invalidLimit(.combinedScratchpadUTF8Bytes)
        }
        guard limits.maximumTotalOptionStringUTF8Bytes >= limits.maximumOptionStringUTF8Bytes else {
            throw ComparisonOpenRequestError.invalidLimit(.totalOptionStringUTF8Bytes)
        }
    }

    private static func validateLocalURL(
        _ url: URL,
        context: ComparisonOpenURLContext,
        isDirectory: Bool,
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws -> (normalizedPath: String, pathBytes: Int) {
        let (tripledPathMaximum, pathMaximumOverflow) =
            limits.maximumPathUTF8Bytes.multipliedReportingOverflow(by: 3)
        let (rawMaximum, rawMaximumOverflow) = tripledPathMaximum.addingReportingOverflow(32)
        guard !pathMaximumOverflow, !rawMaximumOverflow else {
            throw ComparisonOpenRequestError.invalidLimit(.pathUTF8Bytes)
        }
        let rawValue = url.absoluteString
        guard
            try boundedUTF8Count(
                rawValue,
                maximum: rawMaximum,
                work: &work
            ) != nil
        else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .tooLong)
        }
        guard url.baseURL == nil else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .relativeURL)
        }
        guard url.isFileURL,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.caseInsensitiveCompare("file") == .orderedSame
        else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .wrongScheme)
        }
        guard components.user == nil, components.password == nil else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .credentials)
        }
        guard components.query == nil, components.fragment == nil else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .queryOrFragment)
        }
        guard components.port == nil else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .port)
        }
        if let host = components.host, !host.isEmpty,
            host.caseInsensitiveCompare("localhost") != .orderedSame
        {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .remoteFileHost)
        }
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/"), !path.isEmpty else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .missingPath)
        }
        guard
            path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                $0 != "." && $0 != ".."
            })
        else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .dotPathSegment)
        }
        if case .projectDestination = context {
            guard path != "/" else {
                throw ComparisonOpenRequestError.invalidURL(context: context, reason: .missingPath)
            }
            guard !isDirectory, !url.hasDirectoryPath else {
                throw ComparisonOpenRequestError.invalidURL(
                    context: context,
                    reason: .directoryDestination
                )
            }
            guard url.lastPathComponent != ".", url.lastPathComponent != ".." else {
                throw ComparisonOpenRequestError.invalidURL(context: context, reason: .invalidFileName)
            }
        }
        guard !path.contains("\0"), !rawValue.contains("%00") else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .nullByte)
        }
        guard
            try boundedUTF8Count(
                path,
                maximum: limits.maximumPathUTF8Bytes,
                work: &work
            ) != nil
        else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .tooLong)
        }
        let normalizedPath = (path as NSString).standardizingPath
        guard
            let normalizedPathBytes = try boundedUTF8Count(
                normalizedPath,
                maximum: limits.maximumPathUTF8Bytes,
                work: &work
            )
        else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .tooLong)
        }
        return (normalizedPath, normalizedPathBytes)
    }

    private static func validateRemoteWebURL(
        _ url: URL,
        side: ComparisonOpenSidePosition,
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        let context = ComparisonOpenURLContext.side(side)
        let value = url.absoluteString
        guard
            try boundedUTF8Count(
                value,
                maximum: limits.maximumRemoteURLUTF8Bytes,
                work: &work
            ) != nil
        else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .tooLong)
        }
        guard url.baseURL == nil else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .relativeURL)
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .wrongScheme)
        }
        guard components.user == nil, components.password == nil else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .credentials)
        }
        guard let host = components.host, !host.isEmpty else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .missingHost)
        }
        guard !value.contains("\0"), !value.contains("%00") else {
            throw ComparisonOpenRequestError.invalidURL(context: context, reason: .nullByte)
        }
    }

    private static func makeProjectPayload(
        intent: ComparisonOpenProjectSaveIntent,
        request: ComparisonOpenRequest,
        sides: [ComparisonOpenSide],
        normalizedLocalPaths: [ComparisonOpenSidePosition: String],
        mode: ComparisonProject.Mode,
        work: inout ComparisonOpenPlanningWork
    ) throws -> ComparisonOpenProjectPayload {
        guard request.filenameFilter == nil else {
            throw ComparisonOpenRequestError.projectCannotRepresent(.filenameFilterNotRepresentable)
        }
        guard request.transforms == ComparisonOpenTransforms() else {
            throw ComparisonOpenRequestError.projectCannotRepresent(.transformsNotRepresentable)
        }
        let paths: [(ComparisonOpenSidePosition, String, Bool)] = try sides.map { side in
            switch side.source {
            case .localFile, .localFolder:
                guard let path = normalizedLocalPaths[side.position], path != "/" else {
                    throw ComparisonOpenRequestError.projectCannotRepresent(.projectModelRejectedRequest)
                }
                return (side.position, path, side.readOnly)
            default:
                throw ComparisonOpenRequestError.projectCannotRepresent(.localSourcesRequired)
            }
        }

        do {
            switch intent.format {
            case .macMerge:
                let lineDiffOptions = try macMergeProjectLineDiffOptions(
                    request.modeOptions,
                    isThreeWay: request.isThreeWay
                )
                let projectSides = paths.map { position, path, readOnly in
                    ComparisonOpenMacMergeProjectSide(
                        identity: position.projectIdentity,
                        path: path,
                        readOnly: readOnly
                    )
                }
                let projectMode: ComparisonProject.Mode =
                    if case .inferred = request.modeSelection { .automatic } else { mode }
                try validateProjectRegularExpressions(lineDiffOptions, work: &work)
                let project = ComparisonOpenMacMergeProjectPayload(
                    mode: projectMode,
                    sides: projectSides,
                    recursive: request.recursive,
                    lineDiffOptions: lineDiffOptions
                )
                return .macMerge(try encodedMacMergeProjectPayload(project))
            case .winMerge:
                guard request.modeSelection != .explicit(.folder) else {
                    throw ComparisonOpenRequestError.projectCannotRepresent(
                        .modeSelectionNotRepresentable
                    )
                }
                guard request.modeOptions == .defaults else {
                    throw ComparisonOpenRequestError.projectCannotRepresent(
                        .modeOptionsNotRepresentable
                    )
                }
                guard let left = paths.first(where: { $0.0 == .left }),
                    let right = paths.first(where: { $0.0 == .right })
                else {
                    throw ComparisonOpenRequestError.projectCannotRepresent(
                        .projectModelRejectedRequest
                    )
                }
                let middle = paths.first(where: { $0.0 == .middle })
                let windowType: WinMergeProjectFile.WindowType? =
                    if case .inferred = request.modeSelection { nil } else { mode.winMergeWindowType }
                let project = try WinMergeProjectFile(
                    leftPath: left.1,
                    middlePath: middle?.1,
                    rightPath: right.1,
                    includesSubfolders: mode == .folder ? request.recursive : nil,
                    leftReadOnly: left.2,
                    middleReadOnly: middle?.2 ?? false,
                    rightReadOnly: right.2,
                    options: WinMergeProjectFile.Options(windowType: windowType)
                )
                return .winMerge(try project.serializedData())
            }
        } catch let error as ComparisonOpenRequestError {
            throw error
        } catch is CancellationError {
            throw ComparisonOpenRequestError.cancelled
        } catch {
            throw ComparisonOpenRequestError.projectCannotRepresent(.projectModelRejectedRequest)
        }
    }

    private static func validateProjectRegularExpressions(
        _ options: LineDiffOptions,
        work: inout ComparisonOpenPlanningWork
    ) throws {
        if options.lineFiltersEnabled {
            for (index, rule) in options.lineFilters.enumerated() {
                try checkCancellation()
                try validateRegularExpression(
                    rule.pattern,
                    name: "lineFilters[\(index)].pattern",
                    caseSensitive: rule.caseSensitive,
                    work: &work
                )
            }
        }
        if options.substitutionsEnabled {
            for (index, rule) in options.substitutions.enumerated() {
                try checkCancellation()
                guard !rule.pattern.isEmpty else {
                    throw ComparisonOpenRequestError.projectCannotRepresent(.modeOptionsNotRepresentable)
                }
                try validateRegularExpression(
                    rule.pattern,
                    name: "substitutions[\(index)].pattern",
                    caseSensitive: rule.caseSensitive,
                    substitution: true,
                    work: &work
                )
            }
        }
    }

    private static func encodedMacMergeProjectPayload(
        _ project: ComparisonOpenMacMergeProjectPayload
    ) throws -> Data {
        try checkCancellation()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(project)
        data.append(0x0A)
        guard data.count <= ComparisonProject.maximumFileSize else {
            throw ComparisonProjectError.projectFileTooLarge(
                maximumBytes: ComparisonProject.maximumFileSize
            )
        }
        try checkCancellation()
        return data
    }

    private static func macMergeProjectLineDiffOptions(
        _ modeOptions: ComparisonOpenModeOptions,
        isThreeWay: Bool
    ) throws -> LineDiffOptions {
        switch modeOptions {
        case .defaults:
            return LineDiffOptions()
        case .text(let twoWay, let threeWay):
            guard twoWay.commentSyntax == nil else {
                throw ComparisonOpenRequestError.projectCannotRepresent(
                    .modeOptionsNotRepresentable
                )
            }
            let defaultThreeWay = ThreeWayTextMergeOptions()
            if isThreeWay {
                guard threeWay.maximumInputBytes == defaultThreeWay.maximumInputBytes,
                    threeWay.maximumInputLines == defaultThreeWay.maximumInputLines,
                    threeWay.maximumOutputBytes == defaultThreeWay.maximumOutputBytes,
                    threeWay.maximumOutputLines == defaultThreeWay.maximumOutputLines,
                    threeWay.maximumRegions == defaultThreeWay.maximumRegions,
                    threeWay.diffAlgorithm == twoWay.algorithm
                else {
                    throw ComparisonOpenRequestError.projectCannotRepresent(
                        .modeOptionsNotRepresentable
                    )
                }
            } else {
                guard threeWay == defaultThreeWay else {
                    throw ComparisonOpenRequestError.projectCannotRepresent(
                        .modeOptionsNotRepresentable
                    )
                }
            }
            return twoWay
        case .table, .binary, .image, .webpage, .folder:
            throw ComparisonOpenRequestError.projectCannotRepresent(.modeOptionsNotRepresentable)
        }
    }

    private static func materializationRequirements(
        request: ComparisonOpenRequest,
        sides: [ComparisonOpenSide],
        normalizedLocalPaths: [ComparisonOpenSidePosition: String],
        mode: ComparisonProject.Mode,
        projectSaveIntent: ComparisonOpenProjectSaveIntent?,
        normalizedProjectDestinationPath: String?
    ) -> [ComparisonOpenMaterializationRequirement] {
        var requirements: [ComparisonOpenMaterializationRequirement] = []
        requirements.reserveCapacity(sides.count + 3)
        for side in sides {
            switch side.source {
            case .localFile(let url):
                requirements.append(
                    .localAccess(
                        ComparisonOpenLocalAccessRequirement(
                            side: side.position,
                            url: url,
                            normalizedPath: normalizedLocalPaths[side.position],
                            purpose: .readRegularFile
                        )
                    )
                )
            case .localFolder(let url):
                requirements.append(
                    .localAccess(
                        ComparisonOpenLocalAccessRequirement(
                            side: side.position,
                            url: url,
                            normalizedPath: normalizedLocalPaths[side.position],
                            purpose: .readDirectoryTree,
                            recursive: request.recursive
                        )
                    )
                )
            case .remoteWebPage(let url):
                requirements.append(.offlineWebPageContent(side: side.position, url: url))
            case .scratchpad, .clipboard:
                break
            }
        }
        if sides.allSatisfy({ if case .clipboard = $0.source { true } else { false } }) {
            requirements.append(.clipboardPairValidation)
        }
        let localSourceURLs = sides.compactMap { side -> URL? in
            switch side.source {
            case .localFile(let url), .localFolder(let url): url
            case .scratchpad, .clipboard, .remoteWebPage: nil
            }
        }
        if localSourceURLs.count > 1 {
            requirements.append(.distinctSourceIdentityValidation(sourceURLs: localSourceURLs))
        }
        if let unpacker = request.transforms.unpacker {
            requirements.append(.externalToolPlan(capability: .unpacker, rule: unpacker))
        }
        if let prediffer = request.transforms.prediffer {
            requirements.append(.externalToolPlan(capability: .prediffer, rule: prediffer))
        }
        if let intent = projectSaveIntent {
            requirements.append(
                .localAccess(
                    ComparisonOpenLocalAccessRequirement(
                        side: nil,
                        url: intent.destinationURL,
                        normalizedPath: normalizedProjectDestinationPath,
                        purpose: .writeProjectFile
                    )
                )
            )
            requirements.append(
                .projectSaveValidation(intent: intent, sourceURLs: localSourceURLs)
            )
        }
        _ = mode
        return requirements
    }

    private static func unsupportedFeatures(
        request: ComparisonOpenRequest,
        sides: [ComparisonOpenSide],
        mode: ComparisonProject.Mode
    ) -> [ComparisonOpenUnsupportedFeature] {
        var features: [ComparisonOpenUnsupportedFeature] = []
        if sides.contains(where: { if case .remoteWebPage = $0.source { true } else { false } }) {
            features.append(.remoteWebPageLoading)
        }
        if request.transforms.unpacker != nil {
            features.append(.externalToolExecution(.unpacker))
        }
        if request.transforms.prediffer != nil {
            features.append(.externalToolExecution(.prediffer))
        }
        if mode == .folder, !request.recursive {
            features.append(.nonrecursiveFolderEnumeration)
        }
        return features
    }

    private static func validateOptionString(
        _ value: String,
        name: String,
        totalBytes: Int,
        limits: ComparisonOpenRequestLimits,
        work: inout ComparisonOpenPlanningWork
    ) throws -> Int {
        guard
            let count = try boundedUTF8Count(
                value,
                maximum: limits.maximumOptionStringUTF8Bytes,
                work: &work
            )
        else {
            throw ComparisonOpenRequestError.optionStringTooLarge(
                name: name,
                maximumUTF8Bytes: limits.maximumOptionStringUTF8Bytes
            )
        }
        return try addingOptionBytes(count, to: totalBytes, limits: limits)
    }

    private static func addingOptionBytes(
        _ count: Int,
        to total: Int,
        limits: ComparisonOpenRequestLimits
    ) throws -> Int {
        let (next, overflow) = total.addingReportingOverflow(count)
        guard !overflow, next <= limits.maximumTotalOptionStringUTF8Bytes else {
            throw ComparisonOpenRequestError.totalOptionStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalOptionStringUTF8Bytes
            )
        }
        return next
    }

    private static func addingPathBytes(
        _ count: Int,
        to total: Int,
        limits: ComparisonOpenRequestLimits
    ) throws -> Int {
        let (next, overflow) = total.addingReportingOverflow(count)
        guard !overflow, next <= limits.maximumTotalPathUTF8Bytes else {
            throw ComparisonOpenRequestError.totalPathsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalPathUTF8Bytes
            )
        }
        return next
    }

    private static func boundedUTF8Count(
        _ value: String,
        maximum: Int,
        work: inout ComparisonOpenPlanningWork
    ) throws -> Int? {
        var count = 0
        for _ in value.utf8 {
            guard count < maximum else { return nil }
            count += 1
            try work.charge(1)
            if count.isMultiple(of: 4_096) { try checkCancellation() }
        }
        return count
    }

    private static func boundedLineDiffTextMetrics(
        _ value: String,
        maximum: Int,
        side: ComparisonOpenSidePosition,
        work: inout ComparisonOpenPlanningWork
    ) throws -> ComparisonOpenTextMetrics? {
        var byteCount = 0
        var lineCount = 0
        var previousWasCarriageReturn = false
        var endsWithTerminator = false
        for byte in value.utf8 {
            guard byteCount < maximum else { return nil }
            byteCount += 1
            try work.charge(1)
            if byte == 0x0A {
                if !previousWasCarriageReturn { lineCount += 1 }
                endsWithTerminator = true
            } else if byte == 0x0D {
                lineCount += 1
                endsWithTerminator = true
            } else {
                endsWithTerminator = false
            }
            previousWasCarriageReturn = byte == 0x0D
            if byteCount.isMultiple(of: 4_096) { try checkCancellation() }
        }
        let finalLineCount = lineCount + ((!value.isEmpty && !endsWithTerminator) ? 1 : 0)
        return ComparisonOpenTextMetrics(utf8Bytes: byteCount, lineCount: finalLineCount)
    }

    private static func checkCancellation() throws {
        if Task<Never, Never>.isCancelled {
            throw ComparisonOpenRequestError.cancelled
        }
    }
}

private struct ComparisonOpenTextMetrics {
    let utf8Bytes: Int
    let lineCount: Int
}

private struct ComparisonOpenPlanningWork {
    let maximum: Int
    var completed = 0

    mutating func charge(_ amount: Int) throws {
        guard amount >= 0,
            amount <= maximum,
            completed <= maximum - amount
        else {
            throw ComparisonOpenRequestError.planningWorkExceeded(maximumWorkUnits: maximum)
        }
        completed += amount
    }
}

extension ComparisonOpenSource {
    fileprivate var isImmutableSnapshot: Bool {
        switch self {
        case .clipboard, .remoteWebPage: true
        case .localFile, .localFolder, .scratchpad: false
        }
    }
}

extension ComparisonOpenSidePosition {
    fileprivate var projectIdentity: ComparisonProject.Side.Identity {
        switch self {
        case .left: .left
        case .middle: .middle
        case .right: .right
        }
    }
}

extension ComparisonProject.Mode {
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
