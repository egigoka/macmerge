import CoreFoundation
import CryptoKit
import Foundation

public enum ComparisonPreferencesMode: String, Codable, CaseIterable, Hashable, Sendable {
    case text
    case folder
    case table
    case binary
    case image
    case webpage

    public init?(comparisonProjectMode: ComparisonProject.Mode) {
        switch comparisonProjectMode {
        case .text: self = .text
        case .folder: self = .folder
        case .table: self = .table
        case .binary: self = .binary
        case .image: self = .image
        case .webpage: self = .webpage
        case .automatic: return nil
        }
    }

    public var comparisonProjectMode: ComparisonProject.Mode {
        switch self {
        case .text: .text
        case .folder: .folder
        case .table: .table
        case .binary: .binary
        case .image: .image
        case .webpage: .webpage
        }
    }
}

public enum ComparisonPreferencesLimit: String, CaseIterable, Hashable, Sendable {
    case optionItems
    case optionStringUTF8Bytes
    case totalOptionStringUTF8Bytes
    case persistenceInputBytes
    case persistenceOutputBytes
    case workUnits
    case cancellationCheckInterval
}

/// Runtime and persistence bounds. Limits are policy, not persisted preferences.
public struct ComparisonPreferencesWorkflowLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumOptionItems = 8_192
    public static let hardMaximumOptionStringUTF8Bytes = 256 * 1_024
    public static let hardMaximumTotalOptionStringUTF8Bytes = 8 * 1_024 * 1_024
    public static let hardMaximumPersistenceBytes = 16 * 1_024 * 1_024
    public static let hardMaximumWorkUnits = 128 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 65_536

    public static let `default` = ComparisonPreferencesWorkflowLimits(
        validatedMaximumOptionItems: 4_096,
        maximumOptionStringUTF8Bytes: 64 * 1_024,
        maximumTotalOptionStringUTF8Bytes: 4 * 1_024 * 1_024,
        maximumPersistenceInputBytes: 8 * 1_024 * 1_024,
        maximumPersistenceOutputBytes: 8 * 1_024 * 1_024,
        maximumWorkUnits: 64 * 1_024 * 1_024,
        cancellationCheckInterval: 4_096
    )

    public let maximumOptionItems: Int
    public let maximumOptionStringUTF8Bytes: Int
    public let maximumTotalOptionStringUTF8Bytes: Int
    public let maximumPersistenceInputBytes: Int
    public let maximumPersistenceOutputBytes: Int
    public let maximumWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumOptionItems: Int = 4_096,
        maximumOptionStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalOptionStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumPersistenceInputBytes: Int = 8 * 1_024 * 1_024,
        maximumPersistenceOutputBytes: Int = 8 * 1_024 * 1_024,
        maximumWorkUnits: Int = 64 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 4_096
    ) throws {
        guard (0...Self.hardMaximumOptionItems).contains(maximumOptionItems) else {
            throw ComparisonPreferencesWorkflowError.invalidLimit(.optionItems)
        }
        guard
            (0...Self.hardMaximumOptionStringUTF8Bytes).contains(
                maximumOptionStringUTF8Bytes
            )
        else {
            throw ComparisonPreferencesWorkflowError.invalidLimit(.optionStringUTF8Bytes)
        }
        guard
            maximumOptionStringUTF8Bytes...Self.hardMaximumTotalOptionStringUTF8Bytes
                ~= maximumTotalOptionStringUTF8Bytes
        else {
            throw ComparisonPreferencesWorkflowError.invalidLimit(.totalOptionStringUTF8Bytes)
        }
        guard
            (1...Self.hardMaximumPersistenceBytes).contains(maximumPersistenceInputBytes)
        else {
            throw ComparisonPreferencesWorkflowError.invalidLimit(.persistenceInputBytes)
        }
        guard
            (1...Self.hardMaximumPersistenceBytes).contains(maximumPersistenceOutputBytes)
        else {
            throw ComparisonPreferencesWorkflowError.invalidLimit(.persistenceOutputBytes)
        }
        guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
            throw ComparisonPreferencesWorkflowError.invalidLimit(.workUnits)
        }
        guard
            (1...Self.hardMaximumCancellationCheckInterval).contains(
                cancellationCheckInterval
            )
        else {
            throw ComparisonPreferencesWorkflowError.invalidLimit(.cancellationCheckInterval)
        }
        self.init(
            validatedMaximumOptionItems: maximumOptionItems,
            maximumOptionStringUTF8Bytes: maximumOptionStringUTF8Bytes,
            maximumTotalOptionStringUTF8Bytes: maximumTotalOptionStringUTF8Bytes,
            maximumPersistenceInputBytes: maximumPersistenceInputBytes,
            maximumPersistenceOutputBytes: maximumPersistenceOutputBytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    fileprivate init(
        validatedMaximumOptionItems maximumOptionItems: Int,
        maximumOptionStringUTF8Bytes: Int,
        maximumTotalOptionStringUTF8Bytes: Int,
        maximumPersistenceInputBytes: Int,
        maximumPersistenceOutputBytes: Int,
        maximumWorkUnits: Int,
        cancellationCheckInterval: Int
    ) {
        self.maximumOptionItems = maximumOptionItems
        self.maximumOptionStringUTF8Bytes = maximumOptionStringUTF8Bytes
        self.maximumTotalOptionStringUTF8Bytes = maximumTotalOptionStringUTF8Bytes
        self.maximumPersistenceInputBytes = maximumPersistenceInputBytes
        self.maximumPersistenceOutputBytes = maximumPersistenceOutputBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public struct TextComparisonPreferences:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = TextComparisonPreferences(
        uncheckedTwoWay: LineDiffOptions(),
        threeWay: ThreeWayTextMergeOptions(),
        displayFilter: DisplayFilter()
    )

    public let twoWay: LineDiffOptions
    public let threeWay: ThreeWayTextMergeOptions
    public let displayFilter: DisplayFilter

    public init(
        twoWay: LineDiffOptions = LineDiffOptions(),
        threeWay: ThreeWayTextMergeOptions = ThreeWayTextMergeOptions(),
        displayFilter: DisplayFilter = DisplayFilter(),
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        self.init(uncheckedTwoWay: twoWay, threeWay: threeWay, displayFilter: displayFilter)
        try ComparisonPreferencesValidation.validate(self, limits: limits)
    }

    fileprivate init(
        uncheckedTwoWay twoWay: LineDiffOptions,
        threeWay: ThreeWayTextMergeOptions,
        displayFilter: DisplayFilter
    ) {
        self.twoWay = twoWay
        self.threeWay = threeWay
        self.displayFilter = displayFilter
    }

    public var comparisonOpenModeOptions: ComparisonOpenModeOptions {
        .text(twoWay: twoWay, threeWay: threeWay)
    }

    public var description: String { "TextComparisonPreferences(values: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public struct FolderFilenameFilterPreferences:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = FolderFilenameFilterPreferences(
        uncheckedRules: [],
        defaultDecision: .include,
        matchSemantics: .lastMatchWins,
        casePolicy: .sensitive,
        limits: .default
    )

    public let rules: [FilenameFilterRule]
    public let defaultDecision: FilenameFilterDecision
    public let matchSemantics: FilenameFilterMatchSemantics
    public let casePolicy: FilenameFilterCasePolicy
    public let limits: FilenameFilterLimits

    public init(
        rules: [FilenameFilterRule] = [],
        defaultDecision: FilenameFilterDecision = .include,
        matchSemantics: FilenameFilterMatchSemantics = .lastMatchWins,
        casePolicy: FilenameFilterCasePolicy = .sensitive,
        limits: FilenameFilterLimits = .default,
        workflowLimits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        self.init(
            uncheckedRules: rules,
            defaultDecision: defaultDecision,
            matchSemantics: matchSemantics,
            casePolicy: casePolicy,
            limits: limits
        )
        try ComparisonPreferencesValidation.validate(self, limits: workflowLimits)
    }

    fileprivate init(
        uncheckedRules rules: [FilenameFilterRule],
        defaultDecision: FilenameFilterDecision,
        matchSemantics: FilenameFilterMatchSemantics,
        casePolicy: FilenameFilterCasePolicy,
        limits: FilenameFilterLimits
    ) {
        self.rules = rules
        self.defaultDecision = defaultDecision
        self.matchSemantics = matchSemantics
        self.casePolicy = casePolicy
        self.limits = limits
    }

    public var comparisonOpenFilter: ComparisonOpenFilenameFilter {
        ComparisonOpenFilenameFilter(
            rules: rules,
            defaultDecision: defaultDecision,
            matchSemantics: matchSemantics,
            casePolicy: casePolicy,
            limits: limits
        )
    }

    public var description: String { "FolderFilenameFilterPreferences(values: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public struct FolderComparisonPreferences:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = FolderComparisonPreferences(
        uncheckedScanning: FolderScanOptions(),
        twoWay: FolderComparisonOptions(),
        threeWay: ThreeWayFolderComparisonOptions(),
        filenameFilter: .default,
        resultFilter: DirectoryResultFilter()
    )

    public let scanning: FolderScanOptions
    public let twoWay: FolderComparisonOptions
    public let threeWay: ThreeWayFolderComparisonOptions
    public let filenameFilter: FolderFilenameFilterPreferences
    public let resultFilter: DirectoryResultFilter

    public init(
        scanning: FolderScanOptions = FolderScanOptions(),
        twoWay: FolderComparisonOptions = FolderComparisonOptions(),
        threeWay: ThreeWayFolderComparisonOptions = ThreeWayFolderComparisonOptions(),
        filenameFilter: FolderFilenameFilterPreferences = .default,
        resultFilter: DirectoryResultFilter = DirectoryResultFilter(),
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        self.init(
            uncheckedScanning: scanning,
            twoWay: twoWay,
            threeWay: threeWay,
            filenameFilter: filenameFilter,
            resultFilter: resultFilter
        )
        try ComparisonPreferencesValidation.validate(self, limits: limits)
    }

    fileprivate init(
        uncheckedScanning scanning: FolderScanOptions,
        twoWay: FolderComparisonOptions,
        threeWay: ThreeWayFolderComparisonOptions,
        filenameFilter: FolderFilenameFilterPreferences,
        resultFilter: DirectoryResultFilter
    ) {
        self.scanning = scanning
        self.twoWay = twoWay
        self.threeWay = threeWay
        self.filenameFilter = filenameFilter
        self.resultFilter = resultFilter
    }

    public var comparisonOpenModeOptions: ComparisonOpenModeOptions {
        .folder(scanning: scanning, twoWay: twoWay, threeWay: threeWay)
    }

    public var description: String { "FolderComparisonPreferences(values: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public struct TableComparisonPreferences:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = TableComparisonPreferences(
        uncheckedParsing: .commaSeparated,
        twoWay: .default,
        threeWay: .default,
        presentation: .default
    )

    public let parsing: DelimitedTableParsingOptions
    public let twoWay: TableComparisonOptions
    public let threeWay: ThreeWayTableComparisonOptions
    public let presentation: TableWorkspacePresentationOptions

    public init(
        parsing: DelimitedTableParsingOptions = .commaSeparated,
        twoWay: TableComparisonOptions = .default,
        threeWay: ThreeWayTableComparisonOptions = .default,
        presentation: TableWorkspacePresentationOptions = .default,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        self.init(
            uncheckedParsing: parsing,
            twoWay: twoWay,
            threeWay: threeWay,
            presentation: presentation
        )
        try ComparisonPreferencesValidation.validate(self, limits: limits)
    }

    fileprivate init(
        uncheckedParsing parsing: DelimitedTableParsingOptions,
        twoWay: TableComparisonOptions,
        threeWay: ThreeWayTableComparisonOptions,
        presentation: TableWorkspacePresentationOptions
    ) {
        self.parsing = parsing
        self.twoWay = twoWay
        self.threeWay = threeWay
        self.presentation = presentation
    }

    public var comparisonOpenModeOptions: ComparisonOpenModeOptions {
        .table(parsing: parsing, twoWay: twoWay, threeWay: threeWay)
    }

    public var description: String { "TableComparisonPreferences(values: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public struct BinaryComparisonPreferences:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = BinaryComparisonPreferences(
        uncheckedTwoWay: BinaryComparisonOptions(),
        threeWay: .default,
        bytesPerRow: 16
    )

    public let twoWay: BinaryComparisonOptions
    public let threeWay: ThreeWayBinaryComparisonOptions
    public let bytesPerRow: Int

    public init(
        twoWay: BinaryComparisonOptions = BinaryComparisonOptions(),
        threeWay: ThreeWayBinaryComparisonOptions = .default,
        bytesPerRow: Int = 16,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        self.init(uncheckedTwoWay: twoWay, threeWay: threeWay, bytesPerRow: bytesPerRow)
        try ComparisonPreferencesValidation.validate(self, limits: limits)
    }

    fileprivate init(
        uncheckedTwoWay twoWay: BinaryComparisonOptions,
        threeWay: ThreeWayBinaryComparisonOptions,
        bytesPerRow: Int
    ) {
        self.twoWay = twoWay
        self.threeWay = threeWay
        self.bytesPerRow = bytesPerRow
    }

    public var comparisonOpenModeOptions: ComparisonOpenModeOptions {
        .binary(twoWay: twoWay, threeWay: threeWay)
    }

    public var description: String { "BinaryComparisonPreferences(values: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public struct ImageComparisonPreferences:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = ImageComparisonPreferences(
        uncheckedLoading: .default,
        controls: .default
    )

    public let loading: ImageComparisonLimits
    public let controls: ImageToolControlState

    public init(
        loading: ImageComparisonLimits = .default,
        controls: ImageToolControlState = .default,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        self.init(uncheckedLoading: loading, controls: controls)
        try ComparisonPreferencesValidation.validate(self, limits: limits)
    }

    fileprivate init(uncheckedLoading loading: ImageComparisonLimits, controls: ImageToolControlState) {
        self.loading = loading
        self.controls = controls
    }

    public var comparisonOpenModeOptions: ComparisonOpenModeOptions {
        .image(loading: loading, comparison: controls.differences.pixelComparison)
    }

    public var description: String { "ImageComparisonPreferences(values: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public struct WebpageComparisonPreferences:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let `default` = WebpageComparisonPreferences(
        uncheckedTwoWay: .default,
        threeWay: .default,
        displayFilter: DisplayFilter()
    )

    public let twoWay: WebPageComparisonOptions
    public let threeWay: ThreeWayWebPageComparisonOptions
    public let displayFilter: DisplayFilter

    public init(
        twoWay: WebPageComparisonOptions = .default,
        threeWay: ThreeWayWebPageComparisonOptions = .default,
        displayFilter: DisplayFilter = DisplayFilter(),
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        self.init(uncheckedTwoWay: twoWay, threeWay: threeWay, displayFilter: displayFilter)
        try ComparisonPreferencesValidation.validate(self, limits: limits)
    }

    fileprivate init(
        uncheckedTwoWay twoWay: WebPageComparisonOptions,
        threeWay: ThreeWayWebPageComparisonOptions,
        displayFilter: DisplayFilter
    ) {
        self.twoWay = twoWay
        self.threeWay = threeWay
        self.displayFilter = displayFilter
    }

    public var comparisonOpenModeOptions: ComparisonOpenModeOptions {
        .webpage(twoWay: twoWay, threeWay: threeWay)
    }

    public var description: String { "WebpageComparisonPreferences(values: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public enum ComparisonPreferencesModeSettings:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case text(TextComparisonPreferences)
    case folder(FolderComparisonPreferences)
    case table(TableComparisonPreferences)
    case binary(BinaryComparisonPreferences)
    case image(ImageComparisonPreferences)
    case webpage(WebpageComparisonPreferences)

    public var mode: ComparisonPreferencesMode {
        switch self {
        case .text: .text
        case .folder: .folder
        case .table: .table
        case .binary: .binary
        case .image: .image
        case .webpage: .webpage
        }
    }

    public var comparisonOpenModeOptions: ComparisonOpenModeOptions {
        switch self {
        case .text(let value): value.comparisonOpenModeOptions
        case .folder(let value): value.comparisonOpenModeOptions
        case .table(let value): value.comparisonOpenModeOptions
        case .binary(let value): value.comparisonOpenModeOptions
        case .image(let value): value.comparisonOpenModeOptions
        case .webpage(let value): value.comparisonOpenModeOptions
        }
    }

    public static func defaults(for mode: ComparisonPreferencesMode) -> Self {
        switch mode {
        case .text: .text(.default)
        case .folder: .folder(.default)
        case .table: .table(.default)
        case .binary: .binary(.default)
        case .image: .image(.default)
        case .webpage: .webpage(.default)
        }
    }

    public var description: String {
        "ComparisonPreferencesModeSettings(mode: \(mode.rawValue), values: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self, mode: mode) }
}

public struct ComparisonPreferences:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let currentSchemaVersion = 1
    public static let `default` = ComparisonPreferences(
        uncheckedText: .default,
        folder: .default,
        table: .default,
        binary: .default,
        image: .default,
        webpage: .default
    )

    public let text: TextComparisonPreferences
    public let folder: FolderComparisonPreferences
    public let table: TableComparisonPreferences
    public let binary: BinaryComparisonPreferences
    public let image: ImageComparisonPreferences
    public let webpage: WebpageComparisonPreferences

    public init(
        text: TextComparisonPreferences = .default,
        folder: FolderComparisonPreferences = .default,
        table: TableComparisonPreferences = .default,
        binary: BinaryComparisonPreferences = .default,
        image: ImageComparisonPreferences = .default,
        webpage: WebpageComparisonPreferences = .default,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        self.init(
            uncheckedText: text,
            folder: folder,
            table: table,
            binary: binary,
            image: image,
            webpage: webpage
        )
        try ComparisonPreferencesValidation.validate(self, limits: limits)
    }

    fileprivate init(
        uncheckedText text: TextComparisonPreferences,
        folder: FolderComparisonPreferences,
        table: TableComparisonPreferences,
        binary: BinaryComparisonPreferences,
        image: ImageComparisonPreferences,
        webpage: WebpageComparisonPreferences
    ) {
        self.text = text
        self.folder = folder
        self.table = table
        self.binary = binary
        self.image = image
        self.webpage = webpage
    }

    public func settings(for mode: ComparisonPreferencesMode) -> ComparisonPreferencesModeSettings {
        switch mode {
        case .text: .text(text)
        case .folder: .folder(folder)
        case .table: .table(table)
        case .binary: .binary(binary)
        case .image: .image(image)
        case .webpage: .webpage(webpage)
        }
    }

    public func replacing(
        _ settings: ComparisonPreferencesModeSettings,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> ComparisonPreferences {
        let candidate = replacingUnchecked(settings)
        try ComparisonPreferencesValidation.validate(candidate, limits: limits)
        return candidate
    }

    fileprivate func replacingUnchecked(
        _ settings: ComparisonPreferencesModeSettings
    ) -> ComparisonPreferences {
        let candidate: ComparisonPreferences
        switch settings {
        case .text(let value):
            candidate = ComparisonPreferences(
                uncheckedText: value,
                folder: folder,
                table: table,
                binary: binary,
                image: image,
                webpage: webpage
            )
        case .folder(let value):
            candidate = ComparisonPreferences(
                uncheckedText: text,
                folder: value,
                table: table,
                binary: binary,
                image: image,
                webpage: webpage
            )
        case .table(let value):
            candidate = ComparisonPreferences(
                uncheckedText: text,
                folder: folder,
                table: value,
                binary: binary,
                image: image,
                webpage: webpage
            )
        case .binary(let value):
            candidate = ComparisonPreferences(
                uncheckedText: text,
                folder: folder,
                table: table,
                binary: value,
                image: image,
                webpage: webpage
            )
        case .image(let value):
            candidate = ComparisonPreferences(
                uncheckedText: text,
                folder: folder,
                table: table,
                binary: binary,
                image: value,
                webpage: webpage
            )
        case .webpage(let value):
            candidate = ComparisonPreferences(
                uncheckedText: text,
                folder: folder,
                table: table,
                binary: binary,
                image: image,
                webpage: value
            )
        }
        return candidate
    }

    public func resetting(
        _ mode: ComparisonPreferencesMode,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> ComparisonPreferences {
        try replacing(.defaults(for: mode), limits: limits)
    }

    public func comparisonOpenModeOptions(
        for mode: ComparisonProject.Mode
    ) -> ComparisonOpenModeOptions? {
        guard let preferenceMode = ComparisonPreferencesMode(comparisonProjectMode: mode) else {
            return nil
        }
        return settings(for: preferenceMode).comparisonOpenModeOptions
    }

    /// Applies only project-owned line options. Paths, read-only state, recursion, and filters stay
    /// unchanged; other mode settings remain executor-owned application preferences.
    public func applyingLineOptions(to project: ComparisonProject) throws -> ComparisonProject {
        try project.validate()
        let options: LineDiffOptions
        switch project.mode {
        case .text:
            options = text.twoWay
        case .webpage:
            options = webpage.twoWay.lineDiffOptions
        case .automatic, .folder, .table, .binary, .image:
            options = project.lineDiffOptions
        }
        return try ComparisonProject(
            mode: project.mode,
            sides: project.sides,
            recursive: project.recursive,
            filter: project.filter,
            lineDiffOptions: options
        )
    }

    public var description: String { "ComparisonPreferences(modes: 6, values: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

extension ComparisonPreferences {
    /// SHA-256 of the canonical preferences content (no revision envelope).
    ///
    /// Matches the bytes `ComparisonPreferencesWorkflow` hashes into plan
    /// SHAs, so plan-only adoption can re-verify exact content binding under
    /// caller limits without touching persistence I/O.
    internal func canonicalContentSHA256(
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> [UInt8] {
        var work = 0
        return try ComparisonPreferencesPersistence.validatedCanonicalContent(
            self,
            limits: limits,
            work: &work
        ).sha256
    }
}

public struct ComparisonPreferencesRevision:
    Codable, Comparable, Equatable, Hashable, Sendable, CustomStringConvertible
{
    private enum CodingKeys: String, CodingKey {
        case lineage
        case generation
    }

    public let lineage: UInt64
    public let generation: UInt64

    /// `lineage` is caller-owned and must uniquely identify a newly bootstrapped preference store.
    public init(lineage: UInt64, generation: UInt64 = 0) throws {
        guard lineage != 0 else {
            throw ComparisonPreferencesWorkflowError.invalidRevisionLineage
        }
        self.init(uncheckedLineage: lineage, generation: generation)
    }

    fileprivate init(uncheckedLineage lineage: UInt64, generation: UInt64) {
        self.lineage = lineage
        self.generation = generation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lineage: container.decode(UInt64.self, forKey: .lineage),
            generation: container.decode(UInt64.self, forKey: .generation)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lineage, forKey: .lineage)
        try container.encode(generation, forKey: .generation)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.lineage, lhs.generation) < (rhs.lineage, rhs.generation)
    }

    public var description: String { "\(lineage)/\(generation)" }

    fileprivate func advanced() throws -> Self {
        guard generation < UInt64.max else {
            throw ComparisonPreferencesWorkflowError.revisionExhausted
        }
        return Self(uncheckedLineage: lineage, generation: generation + 1)
    }
}

public struct ComparisonPreferencesSnapshot:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let revision: ComparisonPreferencesRevision
    public let preferences: ComparisonPreferences

    public init(
        revision: ComparisonPreferencesRevision,
        preferences: ComparisonPreferences = .default,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        self.init(uncheckedRevision: revision, preferences: preferences)
        try ComparisonPreferencesValidation.validate(preferences, limits: limits)
    }

    fileprivate init(
        uncheckedRevision revision: ComparisonPreferencesRevision,
        preferences: ComparisonPreferences
    ) {
        self.revision = revision
        self.preferences = preferences
    }

    public func encodedDocument(
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> ComparisonPreferencesEncodedDocument {
        try ComparisonPreferencesPersistence.encode(self, limits: limits)
    }

    public func encodedData(
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> Data {
        try encodedDocument(limits: limits).data
    }

    public static func decodeDocument(
        from data: Data,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> ComparisonPreferencesDecodedDocument {
        try ComparisonPreferencesPersistence.decode(data, limits: limits)
    }

    public static func decode(
        from data: Data,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws -> ComparisonPreferencesSnapshot {
        try decodeDocument(from: data, limits: limits).snapshot
    }

    public var description: String {
        "ComparisonPreferencesSnapshot(revision: \(revision), preferences: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public struct ComparisonPreferencesEncodedDocument:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let data: Data
    public let sha256: [UInt8]
    public let workUnits: Int

    fileprivate init(data: Data, sha256: [UInt8], workUnits: Int) {
        self.data = data
        self.sha256 = sha256
        self.workUnits = workUnits
    }

    public var description: String {
        "ComparisonPreferencesEncodedDocument(bytes: \(data.count), workUnits: \(workUnits), data: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public struct ComparisonPreferencesDecodedDocument:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let snapshot: ComparisonPreferencesSnapshot
    public let sha256: [UInt8]
    public let workUnits: Int

    fileprivate init(
        snapshot: ComparisonPreferencesSnapshot,
        sha256: [UInt8],
        workUnits: Int
    ) {
        self.snapshot = snapshot
        self.sha256 = sha256
        self.workUnits = workUnits
    }

    public var description: String {
        "ComparisonPreferencesDecodedDocument(revision: \(snapshot.revision), workUnits: \(workUnits), preferences: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public enum ComparisonPreferencesIntent:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    /// Apply validated values for exactly one preference page.
    case apply(ComparisonPreferencesModeSettings)
    /// Restore factory defaults for exactly one preference page.
    case defaults(ComparisonPreferencesMode)
    /// Reset the complete comparison-preference domain to factory defaults.
    case reset

    public var kind: ComparisonPreferencesIntentKind {
        switch self {
        case .apply: .apply
        case .defaults: .defaults
        case .reset: .reset
        }
    }

    public var mode: ComparisonPreferencesMode? {
        switch self {
        case .apply(let settings): settings.mode
        case .defaults(let mode): mode
        case .reset: nil
        }
    }

    public var description: String {
        "ComparisonPreferencesIntent(kind: \(kind.rawValue), mode: \(mode?.rawValue ?? "all"), values: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self, mode: mode) }
}

public enum ComparisonPreferencesIntentKind: String, CaseIterable, Hashable, Sendable {
    case apply
    case defaults
    case reset
}

public struct ComparisonPreferencesPlan:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let intentKind: ComparisonPreferencesIntentKind
    public let mode: ComparisonPreferencesMode?
    public let expectedRevision: ComparisonPreferencesRevision
    public let resultingRevision: ComparisonPreferencesRevision
    public let expectedSHA256: [UInt8]
    public let resultingSHA256: [UInt8]
    public let preferences: ComparisonPreferences
    public let didChange: Bool
    public let planningWorkUnits: Int

    fileprivate init(
        intentKind: ComparisonPreferencesIntentKind,
        mode: ComparisonPreferencesMode?,
        expectedRevision: ComparisonPreferencesRevision,
        resultingRevision: ComparisonPreferencesRevision,
        expectedSHA256: [UInt8],
        resultingSHA256: [UInt8],
        preferences: ComparisonPreferences,
        didChange: Bool,
        planningWorkUnits: Int
    ) {
        self.intentKind = intentKind
        self.mode = mode
        self.expectedRevision = expectedRevision
        self.resultingRevision = resultingRevision
        self.expectedSHA256 = expectedSHA256
        self.resultingSHA256 = resultingSHA256
        self.preferences = preferences
        self.didChange = didChange
        self.planningWorkUnits = planningWorkUnits
    }

    public var description: String {
        "ComparisonPreferencesPlan(kind: \(intentKind.rawValue), expected: \(expectedRevision), resulting: \(resultingRevision), changed: \(didChange), preferences: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self, mode: mode) }
}

public enum ComparisonPreferencesExecutorAtomicity: String, CaseIterable, Hashable, Sendable {
    /// Executor atomically compares `expectedRevision` plus `expectedPreferencesSHA256`, adopts all
    /// candidate settings, and exposes no candidate effects when it throws.
    case exactRevisionAndContentCompareAndSwapWithoutEffectsOnFailure
}

public struct ComparisonPreferencesAdoptionContract:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let atomicity: ComparisonPreferencesExecutorAtomicity
    public let expectedRevision: ComparisonPreferencesRevision
    public let adoptedRevision: ComparisonPreferencesRevision
    public let expectedPreferencesSHA256: [UInt8]
    public let preferencesSHA256: [UInt8]
    public let preferences: ComparisonPreferences

    fileprivate init(plan: ComparisonPreferencesPlan) {
        atomicity = .exactRevisionAndContentCompareAndSwapWithoutEffectsOnFailure
        expectedRevision = plan.expectedRevision
        adoptedRevision = plan.resultingRevision
        expectedPreferencesSHA256 = plan.expectedSHA256
        preferencesSHA256 = plan.resultingSHA256
        preferences = plan.preferences
    }

    public func settings(for mode: ComparisonPreferencesMode) -> ComparisonPreferencesModeSettings {
        preferences.settings(for: mode)
    }

    public var description: String {
        "ComparisonPreferencesAdoptionContract(expected: \(expectedRevision), adopted: \(adoptedRevision), preferences: <redacted>)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { redactedComparisonPreferencesMirror(self) }
}

public struct ComparisonPreferencesExecutorReceipt: Equatable, Hashable, Sendable {
    public let expectedRevision: ComparisonPreferencesRevision
    public let adoptedRevision: ComparisonPreferencesRevision
    public let expectedPreferencesSHA256: [UInt8]
    public let preferencesSHA256: [UInt8]

    /// Call only after exact atomic adoption succeeds.
    public static func adopted(
        _ contract: ComparisonPreferencesAdoptionContract
    ) -> ComparisonPreferencesExecutorReceipt {
        ComparisonPreferencesExecutorReceipt(
            expectedRevision: contract.expectedRevision,
            adoptedRevision: contract.adoptedRevision,
            expectedPreferencesSHA256: contract.expectedPreferencesSHA256,
            preferencesSHA256: contract.preferencesSHA256
        )
    }

    private init(
        expectedRevision: ComparisonPreferencesRevision,
        adoptedRevision: ComparisonPreferencesRevision,
        expectedPreferencesSHA256: [UInt8],
        preferencesSHA256: [UInt8]
    ) {
        self.expectedRevision = expectedRevision
        self.adoptedRevision = adoptedRevision
        self.expectedPreferencesSHA256 = expectedPreferencesSHA256
        self.preferencesSHA256 = preferencesSHA256
    }
}

public protocol ComparisonPreferencesAdopting: Sendable {
    func adoptComparisonPreferences(
        _ contract: ComparisonPreferencesAdoptionContract
    ) async throws -> ComparisonPreferencesExecutorReceipt
}

public struct ComparisonPreferencesReceipt: Equatable, Hashable, Sendable {
    public let intentKind: ComparisonPreferencesIntentKind
    public let mode: ComparisonPreferencesMode?
    public let previousRevision: ComparisonPreferencesRevision
    public let revision: ComparisonPreferencesRevision
    public let didChange: Bool
    public let preferencesSHA256: [UInt8]
    public let planningWorkUnits: Int

    fileprivate init(plan: ComparisonPreferencesPlan) {
        intentKind = plan.intentKind
        mode = plan.mode
        previousRevision = plan.expectedRevision
        revision = plan.resultingRevision
        didChange = plan.didChange
        preferencesSHA256 = plan.resultingSHA256
        planningWorkUnits = plan.planningWorkUnits
    }
}

/// Actor serialization protects in-process state. Executor contract extends same exact CAS to app
/// state without making this UI-independent workflow own documents, engines, or persistence I/O.
public actor ComparisonPreferencesWorkflow {
    public let limits: ComparisonPreferencesWorkflowLimits
    private var current: ComparisonPreferencesSnapshot
    private var adoptionInProgress = false
    private var requiresReload = false

    public init(
        snapshot: ComparisonPreferencesSnapshot,
        limits: ComparisonPreferencesWorkflowLimits = .default
    ) throws {
        guard snapshot.revision.lineage != 0 else {
            throw ComparisonPreferencesWorkflowError.invalidRevisionLineage
        }
        try ComparisonPreferencesValidation.validate(snapshot.preferences, limits: limits)
        self.limits = limits
        current = snapshot
    }

    public func snapshot() throws -> ComparisonPreferencesSnapshot {
        guard !requiresReload else {
            throw ComparisonPreferencesWorkflowError.reloadRequired
        }
        guard !adoptionInProgress else {
            throw ComparisonPreferencesWorkflowError.adoptionInProgress
        }
        return current
    }

    public func reload(_ snapshot: ComparisonPreferencesSnapshot) throws {
        guard !adoptionInProgress else {
            throw ComparisonPreferencesWorkflowError.adoptionInProgress
        }
        guard snapshot.revision.lineage != 0 else {
            throw ComparisonPreferencesWorkflowError.invalidRevisionLineage
        }
        try ComparisonPreferencesValidation.validate(snapshot.preferences, limits: limits)
        current = snapshot
        requiresReload = false
    }

    public func plan(
        _ intent: ComparisonPreferencesIntent,
        expectedRevision: ComparisonPreferencesRevision
    ) throws -> ComparisonPreferencesPlan {
        guard !requiresReload else {
            throw ComparisonPreferencesWorkflowError.reloadRequired
        }
        guard !adoptionInProgress else {
            throw ComparisonPreferencesWorkflowError.adoptionInProgress
        }
        guard expectedRevision == current.revision else {
            throw ComparisonPreferencesWorkflowError.staleRevision(
                expected: expectedRevision,
                actual: current.revision
            )
        }
        try ComparisonPreferencesValidation.checkCancellation()
        let candidate: ComparisonPreferences
        switch intent {
        case .apply(let settings):
            candidate = current.preferences.replacingUnchecked(settings)
        case .defaults(let mode):
            candidate = current.preferences.replacingUnchecked(.defaults(for: mode))
        case .reset:
            candidate = .default
        }
        var planningWorkUnits = 0
        let expectedContent = try ComparisonPreferencesPersistence.validatedCanonicalContent(
            current.preferences,
            limits: limits,
            work: &planningWorkUnits
        )
        let resultingContent = try ComparisonPreferencesPersistence.validatedCanonicalContent(
            candidate,
            limits: limits,
            work: &planningWorkUnits
        )
        planningWorkUnits = try ComparisonPreferencesPersistence.chargeByteComparison(
            expectedContent.data,
            resultingContent.data,
            work: planningWorkUnits,
            limits: limits
        )
        let didChange = resultingContent.data != expectedContent.data
        let resultingRevision = didChange ? try current.revision.advanced() : current.revision
        return ComparisonPreferencesPlan(
            intentKind: intent.kind,
            mode: intent.mode,
            expectedRevision: current.revision,
            resultingRevision: resultingRevision,
            expectedSHA256: expectedContent.sha256,
            resultingSHA256: resultingContent.sha256,
            preferences: candidate,
            didChange: didChange,
            planningWorkUnits: planningWorkUnits
        )
    }

    public func execute(
        _ plan: ComparisonPreferencesPlan,
        using adopter: any ComparisonPreferencesAdopting
    ) async throws -> ComparisonPreferencesReceipt {
        guard !requiresReload else {
            throw ComparisonPreferencesWorkflowError.reloadRequired
        }
        guard !adoptionInProgress else {
            throw ComparisonPreferencesWorkflowError.adoptionInProgress
        }
        guard plan.expectedRevision == current.revision else {
            throw ComparisonPreferencesWorkflowError.staleRevision(
                expected: plan.expectedRevision,
                actual: current.revision
            )
        }
        var planningWorkUnits = 0
        let currentContent = try ComparisonPreferencesPersistence.validatedCanonicalContent(
            current.preferences,
            limits: limits,
            work: &planningWorkUnits
        )
        guard currentContent.sha256 == plan.expectedSHA256 else {
            throw ComparisonPreferencesWorkflowError.staleSnapshot
        }
        let plannedContent = try ComparisonPreferencesPersistence.validatedCanonicalContent(
            plan.preferences,
            limits: limits,
            work: &planningWorkUnits
        )
        planningWorkUnits = try ComparisonPreferencesPersistence.chargeByteComparison(
            currentContent.data,
            plannedContent.data,
            work: planningWorkUnits,
            limits: limits
        )
        let validResultingRevision: Bool
        if plan.didChange {
            validResultingRevision = plan.resultingRevision == (try current.revision.advanced())
        } else {
            validResultingRevision = plan.resultingRevision == current.revision
        }
        guard plannedContent.sha256 == plan.resultingSHA256,
            plan.didChange == (plannedContent.data != currentContent.data),
            plan.planningWorkUnits == planningWorkUnits,
            validResultingRevision
        else {
            throw ComparisonPreferencesWorkflowError.invalidPlan
        }

        try ComparisonPreferencesValidation.checkCancellation()
        adoptionInProgress = true
        defer { adoptionInProgress = false }
        let contract = ComparisonPreferencesAdoptionContract(plan: plan)
        let executorReceipt: ComparisonPreferencesExecutorReceipt
        do {
            executorReceipt = try await adopter.adoptComparisonPreferences(contract)
        } catch is CancellationError {
            throw ComparisonPreferencesWorkflowError.cancelled
        } catch {
            requiresReload = true
            let bridged = error as NSError
            throw ComparisonPreferencesWorkflowError.executorFailed(
                domain: try comparisonPreferencesErrorDomainToken(bridged.domain),
                code: bridged.code
            )
        }
        guard executorReceipt.expectedRevision == contract.expectedRevision,
            executorReceipt.adoptedRevision == contract.adoptedRevision,
            executorReceipt.expectedPreferencesSHA256 == contract.expectedPreferencesSHA256,
            executorReceipt.preferencesSHA256 == contract.preferencesSHA256
        else {
            requiresReload = true
            throw ComparisonPreferencesWorkflowError.invalidExecutorReceipt
        }
        current = ComparisonPreferencesSnapshot(
            uncheckedRevision: plan.resultingRevision,
            preferences: plan.preferences
        )
        return ComparisonPreferencesReceipt(plan: plan)
    }

}

public enum ComparisonPreferencesWorkflowError:
    Error, Equatable, Hashable, LocalizedError, Sendable
{
    case invalidLimit(ComparisonPreferencesLimit)
    case invalidOption(mode: ComparisonPreferencesMode, field: String)
    case invalidCrossField(mode: ComparisonPreferencesMode, fields: String)
    case tooManyOptionItems(maximumCount: Int)
    case optionStringTooLarge(field: String, maximumUTF8Bytes: Int)
    case totalOptionStringsTooLarge(maximumUTF8Bytes: Int)
    case persistenceInputTooLarge(maximumBytes: Int)
    case persistenceOutputTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumWorkUnits: Int)
    case unsupportedSchemaVersion(Int)
    case malformedPersistence
    case nonCanonicalPersistence
    case invalidRevisionLineage
    case staleRevision(
        expected: ComparisonPreferencesRevision,
        actual: ComparisonPreferencesRevision
    )
    case staleSnapshot
    case revisionExhausted
    case invalidPlan
    case adoptionInProgress
    case invalidExecutorReceipt
    case reloadRequired
    case executorFailed(domain: String, code: Int)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let limit):
            "Invalid comparison-preference limit: \(limit.rawValue)."
        case .invalidOption(let mode, let field):
            "Invalid \(mode.rawValue) comparison preference: \(field)."
        case .invalidCrossField(let mode, let fields):
            "Incompatible \(mode.rawValue) comparison preferences: \(fields)."
        case .tooManyOptionItems(let maximumCount):
            "Comparison preferences exceed the \(maximumCount)-item limit."
        case .optionStringTooLarge(let field, let maximumUTF8Bytes):
            "Comparison preference \(field) exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .totalOptionStringsTooLarge(let maximumUTF8Bytes):
            "Comparison preference strings exceed the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .persistenceInputTooLarge(let maximumBytes):
            "Comparison preference input exceeds the \(maximumBytes)-byte limit."
        case .persistenceOutputTooLarge(let maximumBytes):
            "Comparison preference output exceeds the \(maximumBytes)-byte limit."
        case .workLimitExceeded(let maximumWorkUnits):
            "Comparison preference work exceeds the \(maximumWorkUnits)-unit limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported comparison preference schema version: \(version)."
        case .malformedPersistence:
            "Comparison preference persistence is malformed."
        case .nonCanonicalPersistence:
            "Comparison preference persistence is not canonical."
        case .invalidRevisionLineage:
            "Comparison preference revision lineage must be nonzero."
        case .staleRevision(let expected, let actual):
            "Comparison preferences changed from revision \(expected) to \(actual)."
        case .staleSnapshot:
            "Comparison preference plan does not match exact current state."
        case .revisionExhausted:
            "Comparison preference revision space is exhausted."
        case .invalidPlan:
            "Comparison preference plan is internally inconsistent."
        case .adoptionInProgress:
            "Comparison preference adoption is already in progress."
        case .invalidExecutorReceipt:
            "Comparison preference executor returned an invalid adoption receipt."
        case .reloadRequired:
            "Comparison preferences must be reloaded from executor state."
        case .executorFailed(let domain, let code):
            "Comparison preference executor failed (\(domain), \(code))."
        case .cancelled:
            "Comparison preference operation was cancelled."
        }
    }
}

private func redactedComparisonPreferencesMirror(
    _ value: Any,
    mode: ComparisonPreferencesMode? = nil
) -> Mirror {
    var children: [(label: String?, value: Any)] = [("values", "<redacted>")]
    if let mode { children.append(("mode", mode.rawValue)) }
    return Mirror(value, children: children, displayStyle: .struct)
}

private let comparisonPreferencesMaximumRegularExpressionUTF8Bytes = 4 * 1_024

private func canonicalComparisonPreferencesDoubleBits(_ value: Double) -> UInt64 {
    value == 0 ? 0 : value.bitPattern
}

private func comparisonPreferencesErrorDomainToken(_ value: String) throws -> String {
    var hasher = SHA256()
    var chunk: [UInt8] = []
    chunk.reserveCapacity(4_096)
    var truncated = false
    for byte in value.utf8.prefix(4_097) {
        guard chunk.count < 4_096 else {
            truncated = true
            break
        }
        chunk.append(byte)
    }
    try ComparisonPreferencesValidation.checkCancellation()
    if !chunk.isEmpty { hasher.update(data: Data(chunk)) }
    if truncated { hasher.update(data: Data([0xFF])) }
    return "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

package enum ComparisonPreferencesWorkflowTestHooks {
    @TaskLocal
    private static var cancellationCheckpoint: @Sendable () throws -> Void = {
        if Task.isCancelled { throw ComparisonPreferencesWorkflowError.cancelled }
    }

    package static func withCancellationCheckpoint<Result>(
        _ checkpoint: @escaping @Sendable () throws -> Void,
        operation: () throws -> Result
    ) rethrows -> Result {
        try $cancellationCheckpoint.withValue(checkpoint, operation: operation)
    }

    package static func withCancellationCheckpoint<Result>(
        _ checkpoint: @escaping @Sendable () throws -> Void,
        operation: () async throws -> Result
    ) async rethrows -> Result {
        try await $cancellationCheckpoint.withValue(checkpoint, operation: operation)
    }

    package static func checkCancellation() throws {
        try cancellationCheckpoint()
    }
}

private enum ComparisonPreferencesValidation {
    static func checkCancellation() throws {
        try ComparisonPreferencesWorkflowTestHooks.checkCancellation()
    }

    static func validate(
        _ preferences: ComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws {
        _ = try measuredValidation(of: preferences, limits: limits)
    }

    static func measuredValidation(
        of preferences: ComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        startingAt consumed: Int = 0
    ) throws -> Int {
        var work = try ComparisonPreferencesWorkBudget(limits: limits, consumed: consumed)
        try validate(preferences.text, limits: limits, work: &work)
        try validate(preferences.folder, limits: limits, work: &work)
        try validate(preferences.table, limits: limits, work: &work)
        try validate(preferences.binary, limits: limits, work: &work)
        try validate(preferences.image, limits: limits, work: &work)
        try validate(preferences.webpage, limits: limits, work: &work)
        try checkCancellation()
        return work.consumed
    }

    static func validate(
        _ preferences: TextComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws {
        try checkCancellation()
        var work = ComparisonPreferencesWorkBudget(limits: limits)
        try validate(preferences, limits: limits, work: &work)
        try checkCancellation()
    }

    static func validate(
        _ preferences: FolderFilenameFilterPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws {
        try checkCancellation()
        var work = ComparisonPreferencesWorkBudget(limits: limits)
        try validate(preferences, limits: limits, work: &work)
        try checkCancellation()
    }

    static func validate(
        _ preferences: FolderComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws {
        try checkCancellation()
        var work = ComparisonPreferencesWorkBudget(limits: limits)
        try validate(preferences, limits: limits, work: &work)
        try checkCancellation()
    }

    static func validate(
        _ preferences: TableComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws {
        try checkCancellation()
        var work = ComparisonPreferencesWorkBudget(limits: limits)
        try validate(preferences, limits: limits, work: &work)
        try checkCancellation()
    }

    static func validate(
        _ preferences: BinaryComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws {
        try checkCancellation()
        var work = ComparisonPreferencesWorkBudget(limits: limits)
        try validate(preferences, limits: limits, work: &work)
        try checkCancellation()
    }

    static func validate(
        _ preferences: ImageComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws {
        try checkCancellation()
        var work = ComparisonPreferencesWorkBudget(limits: limits)
        try validate(preferences, limits: limits, work: &work)
        try checkCancellation()
    }

    static func validate(
        _ preferences: WebpageComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws {
        try checkCancellation()
        var work = ComparisonPreferencesWorkBudget(limits: limits)
        try validate(preferences, limits: limits, work: &work)
        try checkCancellation()
    }

    private static func validate(
        _ preferences: TextComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        try work.charge(8)
        try validateLineOptions(
            preferences.twoWay,
            mode: .text,
            prefix: "text.twoWay",
            limits: limits,
            work: &work
        )
        let threeWay = preferences.threeWay
        try requireRange(
            threeWay.maximumInputBytes,
            0...ThreeWayTextMergeOptions().maximumInputBytes,
            mode: .text,
            field: "threeWay.maximumInputBytes"
        )
        try requireRange(
            threeWay.maximumInputLines,
            0...ThreeWayTextMergeOptions().maximumInputLines,
            mode: .text,
            field: "threeWay.maximumInputLines"
        )
        try requireRange(
            threeWay.maximumOutputBytes,
            0...ThreeWayTextMergeOptions().maximumOutputBytes,
            mode: .text,
            field: "threeWay.maximumOutputBytes"
        )
        try requireRange(
            threeWay.maximumOutputLines,
            0...ThreeWayTextMergeOptions().maximumOutputLines,
            mode: .text,
            field: "threeWay.maximumOutputLines"
        )
        try requireRange(
            threeWay.maximumRegions,
            0...ThreeWayTextMergeOptions().maximumRegions,
            mode: .text,
            field: "threeWay.maximumRegions"
        )
        guard threeWay.diffAlgorithm == preferences.twoWay.algorithm else {
            throw ComparisonPreferencesWorkflowError.invalidCrossField(
                mode: .text,
                fields: "twoWay.algorithm, threeWay.diffAlgorithm"
            )
        }
        try validateDisplayFilter(
            preferences.displayFilter,
            detectsMovedBlocks: preferences.twoWay.detectMovedBlocks,
            mode: .text,
            work: &work
        )
    }

    private static func validate(
        _ preferences: FolderFilenameFilterPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        try work.charge(10)
        try work.addItems(preferences.rules.count)
        let declared = preferences.limits
        let ceiling = FilenameFilterLimits.default
        let values: [(String, Int, Int)] = [
            ("maximumRuleCount", declared.maximumRuleCount, ceiling.maximumRuleCount),
            (
                "maximumPatternUTF8Bytes",
                declared.maximumPatternUTF8Bytes,
                ceiling.maximumPatternUTF8Bytes
            ),
            (
                "maximumTotalPatternUTF8Bytes",
                declared.maximumTotalPatternUTF8Bytes,
                ceiling.maximumTotalPatternUTF8Bytes
            ),
            (
                "maximumRelativePathUTF8Bytes",
                declared.maximumRelativePathUTF8Bytes,
                ceiling.maximumRelativePathUTF8Bytes
            ),
            (
                "maximumCompiledStateCount",
                declared.maximumCompiledStateCount,
                ceiling.maximumCompiledStateCount
            ),
            ("maximumMatchWork", declared.maximumMatchWork, ceiling.maximumMatchWork),
            (
                "maximumRegularExpressionNestingDepth",
                declared.maximumRegularExpressionNestingDepth,
                ceiling.maximumRegularExpressionNestingDepth
            ),
            (
                "maximumRegularExpressionRepetition",
                declared.maximumRegularExpressionRepetition,
                ceiling.maximumRegularExpressionRepetition
            )
        ]
        for (field, value, maximum) in values {
            try requireRange(
                value,
                0...maximum,
                mode: .folder,
                field: "filenameFilter.limits.\(field)"
            )
        }
        guard preferences.rules.count <= declared.maximumRuleCount else {
            throw ComparisonPreferencesWorkflowError.invalidCrossField(
                mode: .folder,
                fields: "filenameFilter.rules, filenameFilter.limits.maximumRuleCount"
            )
        }
        var totalPatternBytes = 0
        for (index, rule) in preferences.rules.enumerated() {
            let patternBytes = try work.addString(
                rule.pattern.source,
                field: "folder.filenameFilter.rules[\(index)].pattern"
            )
            totalPatternBytes = try work.checkedSum(totalPatternBytes, patternBytes)
            if case .regularExpression = rule.pattern {
                guard patternBytes <= comparisonPreferencesMaximumRegularExpressionUTF8Bytes else {
                    throw ComparisonPreferencesWorkflowError.optionStringTooLarge(
                        field: "folder.filenameFilter.rules[\(index)].pattern",
                        maximumUTF8Bytes: comparisonPreferencesMaximumRegularExpressionUTF8Bytes
                    )
                }
            }
        }
        if !preferences.rules.isEmpty {
            try work.charge(totalPatternBytes)
            try work.charge(declared.maximumCompiledStateCount)
        }
        do {
            let compiled = try FilenameFilter(
                rules: preferences.rules,
                defaultDecision: preferences.defaultDecision,
                matchSemantics: preferences.matchSemantics,
                casePolicy: preferences.casePolicy,
                limits: declared
            )
            guard compiled.diagnostics.isEmpty else {
                throw ComparisonPreferencesWorkflowError.invalidOption(
                    mode: .folder,
                    field: "filenameFilter.rules"
                )
            }
        } catch is CancellationError {
            throw ComparisonPreferencesWorkflowError.cancelled
        } catch let error as ComparisonPreferencesWorkflowError {
            throw error
        } catch {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: .folder,
                field: "filenameFilter.rules"
            )
        }
    }

    private static func validate(
        _ preferences: FolderComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        try work.charge(24)
        let scan = preferences.scanning.limits
        let scanCeiling = FolderScanLimits()
        let scanValues: [(String, Int64, Int64)] = [
            ("maximumDepth", Int64(scan.maximumDepth), Int64(scanCeiling.maximumDepth)),
            ("maximumEntries", Int64(scan.maximumEntries), Int64(scanCeiling.maximumEntries)),
            (
                "maximumExaminedEntries",
                Int64(scan.maximumExaminedEntries),
                Int64(scanCeiling.maximumExaminedEntries)
            ),
            ("maximumIssues", Int64(scan.maximumIssues), Int64(scanCeiling.maximumIssues)),
            (
                "maximumOpenDirectoryDescriptors",
                Int64(scan.maximumOpenDirectoryDescriptors),
                Int64(scanCeiling.maximumOpenDirectoryDescriptors)
            ),
            (
                "maximumPendingEntryNames",
                Int64(scan.maximumPendingEntryNames),
                Int64(scanCeiling.maximumPendingEntryNames)
            ),
            (
                "maximumRelativePathUTF8Bytes",
                Int64(scan.maximumRelativePathUTF8Bytes),
                Int64(scanCeiling.maximumRelativePathUTF8Bytes)
            ),
            (
                "maximumTotalAccountedBytes",
                scan.maximumTotalAccountedBytes,
                scanCeiling.maximumTotalAccountedBytes
            )
        ]
        for (field, value, maximum) in scanValues {
            guard value >= 0, value <= maximum else {
                throw ComparisonPreferencesWorkflowError.invalidOption(
                    mode: .folder,
                    field: "scanning.limits.\(field)"
                )
            }
        }
        if preferences.scanning.symbolicLinkPolicy == .followDirectoriesWithinRoot,
            scan.maximumOpenDirectoryDescriptors == 0
                || scan.maximumPendingEntryNames == 0
        {
            throw ComparisonPreferencesWorkflowError.invalidCrossField(
                mode: .folder,
                fields: "scanning.symbolicLinkPolicy, scanning.limits"
            )
        }
        guard preferences.twoWay.modificationDateTolerance.isFinite,
            preferences.twoWay.modificationDateTolerance >= 0
        else {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: .folder,
                field: "twoWay.modificationDateTolerance"
            )
        }
        guard preferences.threeWay.comparison == preferences.twoWay else {
            throw ComparisonPreferencesWorkflowError.invalidCrossField(
                mode: .folder,
                fields: "twoWay, threeWay.comparison"
            )
        }
        let threeWay = preferences.threeWay
        let threeWayCeiling = ThreeWayFolderComparisonOptions.default
        let threeWayValues: [(String, Int, Int)] = [
            (
                "maximumEntriesPerSnapshot",
                threeWay.maximumEntriesPerSnapshot,
                threeWayCeiling.maximumEntriesPerSnapshot
            ),
            (
                "maximumResultEntries",
                threeWay.maximumResultEntries,
                threeWayCeiling.maximumResultEntries
            ),
            (
                "maximumRelativePathUTF8Bytes",
                threeWay.maximumRelativePathUTF8Bytes,
                threeWayCeiling.maximumRelativePathUTF8Bytes
            ),
            (
                "maximumDigestBytes",
                threeWay.maximumDigestBytes,
                threeWayCeiling.maximumDigestBytes
            ),
            (
                "maximumDigestAlgorithmUTF8Bytes",
                threeWay.maximumDigestAlgorithmUTF8Bytes,
                threeWayCeiling.maximumDigestAlgorithmUTF8Bytes
            ),
            ("maximumWorkUnits", threeWay.maximumWorkUnits, threeWayCeiling.maximumWorkUnits)
        ]
        for (field, value, maximum) in threeWayValues {
            try requireRange(value, 0...maximum, mode: .folder, field: "threeWay.\(field)")
        }
        try validate(preferences.filenameFilter, limits: limits, work: &work)
        try work.addString(preferences.resultFilter.pathQuery, field: "folder.resultFilter.pathQuery")
        guard !preferences.resultFilter.pathQuery.contains("\0") else {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: .folder,
                field: "resultFilter.pathQuery"
            )
        }
        if preferences.scanning.hiddenFilePolicy == .excludeEntriesAndSymbolicLinkTargets,
            preferences.resultFilter.hidden == .only
        {
            throw ComparisonPreferencesWorkflowError.invalidCrossField(
                mode: .folder,
                fields: "scanning.hiddenFilePolicy, resultFilter.hidden"
            )
        }
    }

    private static func validate(
        _ preferences: TableComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        try work.charge(14)
        try validateTableParsing(
            preferences.parsing,
            prefix: "table.parsing",
            work: &work
        )
        try validateTableComparison(preferences.twoWay, prefix: "table.twoWay")
        try validateTableParsing(
            preferences.threeWay.parsingOptions,
            prefix: "table.threeWay.parsingOptions",
            work: &work
        )
        try validateTableComparison(
            preferences.threeWay.comparisonOptions,
            prefix: "table.threeWay.comparisonOptions"
        )
        guard preferences.threeWay.parsingOptions == preferences.parsing else {
            throw ComparisonPreferencesWorkflowError.invalidCrossField(
                mode: .table,
                fields: "parsing, threeWay.parsingOptions"
            )
        }
        guard preferences.threeWay.comparisonOptions == preferences.twoWay else {
            throw ComparisonPreferencesWorkflowError.invalidCrossField(
                mode: .table,
                fields: "twoWay, threeWay.comparisonOptions"
            )
        }
        let threeWay = preferences.threeWay
        let ceiling = ThreeWayTableComparisonOptions.default
        try requireRange(
            threeWay.maximumComparedValueBytes,
            0...ceiling.maximumComparedValueBytes,
            mode: .table,
            field: "threeWay.maximumComparedValueBytes"
        )
        try requireRange(
            threeWay.maximumResultRows,
            0...ceiling.maximumResultRows,
            mode: .table,
            field: "threeWay.maximumResultRows"
        )
        try requireRange(
            threeWay.maximumResultCells,
            0...ceiling.maximumResultCells,
            mode: .table,
            field: "threeWay.maximumResultCells"
        )
        _ = limits
    }

    private static func validate(
        _ preferences: BinaryComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        try work.charge(9)
        let twoWayCeiling = BinaryComparisonOptions()
        try requireRange(
            preferences.twoWay.maximumExactEditDistance,
            0...twoWayCeiling.maximumExactEditDistance,
            mode: .binary,
            field: "twoWay.maximumExactEditDistance"
        )
        try requireRange(
            preferences.twoWay.maximumAlignmentWork,
            0...twoWayCeiling.maximumAlignmentWork,
            mode: .binary,
            field: "twoWay.maximumAlignmentWork"
        )
        let threeWay = preferences.threeWay
        let threeWayCeiling = ThreeWayBinaryComparisonOptions.default
        let values: [(String, Int, Int)] = [
            ("maximumInputBytes", threeWay.maximumInputBytes, threeWayCeiling.maximumInputBytes),
            (
                "maximumExactEditDistance",
                threeWay.maximumExactEditDistance,
                threeWayCeiling.maximumExactEditDistance
            ),
            (
                "maximumAlignmentWork",
                threeWay.maximumAlignmentWork,
                threeWayCeiling.maximumAlignmentWork
            ),
            ("maximumRegions", threeWay.maximumRegions, threeWayCeiling.maximumRegions),
            ("maximumOutputBytes", threeWay.maximumOutputBytes, threeWayCeiling.maximumOutputBytes)
        ]
        for (field, value, maximum) in values {
            try requireRange(value, 0...maximum, mode: .binary, field: "threeWay.\(field)")
        }
        try requireRange(preferences.bytesPerRow, 1...256, mode: .binary, field: "bytesPerRow")
        _ = limits
    }

    private static func validate(
        _ preferences: ImageComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        try work.charge(16)
        let loading = preferences.loading
        let loadingCeiling = ImageComparisonLimits.default
        try requireRange(
            loading.maximumEncodedBytes,
            1...loadingCeiling.maximumEncodedBytes,
            mode: .image,
            field: "loading.maximumEncodedBytes"
        )
        try requireRange(
            loading.maximumDimension,
            1...loadingCeiling.maximumDimension,
            mode: .image,
            field: "loading.maximumDimension"
        )
        try requireRange(
            loading.maximumPixelCount,
            1...loadingCeiling.maximumPixelCount,
            mode: .image,
            field: "loading.maximumPixelCount"
        )
        try requireRange(
            loading.maximumDecodedBytes,
            1...loadingCeiling.maximumDecodedBytes,
            mode: .image,
            field: "loading.maximumDecodedBytes"
        )
        guard !loading.supportedTypeIdentifiers.isEmpty,
            loading.supportedTypeIdentifiers.isSubset(
                of: ImageComparisonLimits.supportedStaticTypeIdentifiers
            )
        else {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: .image,
                field: "loading.supportedTypeIdentifiers"
            )
        }
        try work.addItems(loading.supportedTypeIdentifiers.count)
        for identifier in loading.supportedTypeIdentifiers.sorted() {
            try work.addString(identifier, field: "image.loading.supportedTypeIdentifiers")
        }
        let controls = preferences.controls
        let comparison = controls.differences.pixelComparison
        let comparisonCeiling = ImageComparisonOptions.default
        try requireRange(
            comparison.maximumCanvasPixels,
            1...comparisonCeiling.maximumCanvasPixels,
            mode: .image,
            field: "controls.differences.pixelComparison.maximumCanvasPixels"
        )
        try requireRange(
            comparison.maximumRegions,
            1...comparisonCeiling.maximumRegions,
            mode: .image,
            field: "controls.differences.pixelComparison.maximumRegions"
        )
        try requireRange(
            comparison.maximumQueuedPixels,
            1...comparisonCeiling.maximumQueuedPixels,
            mode: .image,
            field: "controls.differences.pixelComparison.maximumQueuedPixels"
        )
        try requireRange(
            controls.differences.differenceBlockSize,
            1...64,
            mode: .image,
            field: "controls.differences.differenceBlockSize"
        )
        guard controls.differences.colorDistanceThreshold.isFinite,
            (0...442).contains(controls.differences.colorDistanceThreshold)
        else {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: .image,
                field: "controls.differences.colorDistanceThreshold"
            )
        }
        guard controls.zoom.scale.isFinite, (0.01...8).contains(controls.zoom.scale) else {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: .image,
                field: "controls.zoom.scale"
            )
        }
        guard controls.overlay.alpha.isFinite, (0...1).contains(controls.overlay.alpha) else {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: .image,
                field: "controls.overlay.alpha"
            )
        }
        guard controls.wipe.position.isFinite, (0...1).contains(controls.wipe.position) else {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: .image,
                field: "controls.wipe.position"
            )
        }
        for (field, value) in [
            ("blinkIntervalMilliseconds", controls.animation.blinkIntervalMilliseconds),
            ("overlayIntervalMilliseconds", controls.animation.overlayIntervalMilliseconds)
        ] {
            try requireRange(
                value,
                200...8_000,
                mode: .image,
                field: "controls.animation.\(field)"
            )
        }
        _ = limits
    }

    private static func validate(
        _ preferences: WebpageComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        try work.charge(26)
        try validateLineOptions(
            preferences.twoWay.lineDiffOptions,
            mode: .webpage,
            prefix: "webpage.twoWay.lineDiffOptions",
            limits: limits,
            work: &work
        )
        let twoWayLimits = preferences.twoWay.limits
        let twoWayCeiling = WebPageComparisonLimits.default
        let twoWayValues: [(String, Int, Int)] = [
            ("maximumInputBytes", twoWayLimits.maximumInputBytes, twoWayCeiling.maximumInputBytes),
            ("maximumTokenCount", twoWayLimits.maximumTokenCount, twoWayCeiling.maximumTokenCount),
            (
                "maximumAttributeCount",
                twoWayLimits.maximumAttributeCount,
                twoWayCeiling.maximumAttributeCount
            ),
            (
                "maximumAttributesPerTag",
                twoWayLimits.maximumAttributesPerTag,
                twoWayCeiling.maximumAttributesPerTag
            ),
            (
                "maximumElementDepth",
                twoWayLimits.maximumElementDepth,
                twoWayCeiling.maximumElementDepth
            ),
            ("maximumWorkUnits", twoWayLimits.maximumWorkUnits, twoWayCeiling.maximumWorkUnits),
            ("maximumOutputBytes", twoWayLimits.maximumOutputBytes, twoWayCeiling.maximumOutputBytes)
        ]
        for (field, value, maximum) in twoWayValues {
            try requireRange(value, 0...maximum, mode: .webpage, field: "twoWay.limits.\(field)")
        }
        let threeWay = preferences.threeWay
        guard threeWay.diffAlgorithm == preferences.twoWay.lineDiffOptions.algorithm else {
            throw ComparisonPreferencesWorkflowError.invalidCrossField(
                mode: .webpage,
                fields: "twoWay.lineDiffOptions.algorithm, threeWay.diffAlgorithm"
            )
        }
        if let context = threeWay.expectedContext {
            try work.addItem()
            try work.addString(context.identifier, field: "webpage.threeWay.expectedContext.identifier")
            guard !context.identifier.isEmpty, !context.identifier.contains("\0") else {
                throw ComparisonPreferencesWorkflowError.invalidOption(
                    mode: .webpage,
                    field: "threeWay.expectedContext.identifier"
                )
            }
        }
        let threeWayLimits = threeWay.limits
        let threeWayCeiling = ThreeWayWebPageComparisonLimits.default
        let threeWayValues: [(String, Int, Int)] = [
            (
                "maximumSourceInputBytesPerSnapshot",
                threeWayLimits.maximumSourceInputBytesPerSnapshot,
                threeWayCeiling.maximumSourceInputBytesPerSnapshot
            ),
            (
                "maximumNormalizedInputBytesPerSnapshot",
                threeWayLimits.maximumNormalizedInputBytesPerSnapshot,
                threeWayCeiling.maximumNormalizedInputBytesPerSnapshot
            ),
            (
                "maximumTokenCountPerSnapshot",
                threeWayLimits.maximumTokenCountPerSnapshot,
                threeWayCeiling.maximumTokenCountPerSnapshot
            ),
            (
                "maximumAttributeCountPerSnapshot",
                threeWayLimits.maximumAttributeCountPerSnapshot,
                threeWayCeiling.maximumAttributeCountPerSnapshot
            ),
            (
                "maximumTotalNormalizedInputBytes",
                threeWayLimits.maximumTotalNormalizedInputBytes,
                threeWayCeiling.maximumTotalNormalizedInputBytes
            ),
            (
                "maximumInputLinesPerSnapshot",
                threeWayLimits.maximumInputLinesPerSnapshot,
                threeWayCeiling.maximumInputLinesPerSnapshot
            ),
            (
                "maximumMetadataEntriesPerSnapshot",
                threeWayLimits.maximumMetadataEntriesPerSnapshot,
                threeWayCeiling.maximumMetadataEntriesPerSnapshot
            ),
            (
                "maximumMetadataBytes",
                threeWayLimits.maximumMetadataBytes,
                threeWayCeiling.maximumMetadataBytes
            ),
            ("maximumWorkUnits", threeWayLimits.maximumWorkUnits, threeWayCeiling.maximumWorkUnits),
            (
                "maximumResultRegions",
                threeWayLimits.maximumResultRegions,
                threeWayCeiling.maximumResultRegions
            ),
            (
                "maximumMappedSegments",
                threeWayLimits.maximumMappedSegments,
                threeWayCeiling.maximumMappedSegments
            ),
            ("maximumOutputBytes", threeWayLimits.maximumOutputBytes, threeWayCeiling.maximumOutputBytes),
            ("maximumOutputLines", threeWayLimits.maximumOutputLines, threeWayCeiling.maximumOutputLines)
        ]
        for (field, value, maximum) in threeWayValues {
            try requireRange(value, 0...maximum, mode: .webpage, field: "threeWay.limits.\(field)")
        }
        try validateDisplayFilter(
            preferences.displayFilter,
            detectsMovedBlocks: preferences.twoWay.lineDiffOptions.detectMovedBlocks,
            mode: .webpage,
            work: &work
        )
    }

    private static func validateLineOptions(
        _ options: LineDiffOptions,
        mode: ComparisonPreferencesMode,
        prefix: String,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        guard options.commentSyntax == nil else {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: mode,
                field: "\(prefix).commentSyntax"
            )
        }
        let (itemCount, overflow) = options.lineFilters.count.addingReportingOverflow(
            options.substitutions.count
        )
        guard !overflow else {
            throw ComparisonPreferencesWorkflowError.tooManyOptionItems(
                maximumCount: limits.maximumOptionItems
            )
        }
        try work.addItems(itemCount)
        for (index, rule) in options.lineFilters.enumerated() {
            let field = "\(prefix).lineFilters[\(index)].pattern"
            let patternBytes = try work.addString(rule.pattern, field: field)
            guard patternBytes <= comparisonPreferencesMaximumRegularExpressionUTF8Bytes else {
                throw ComparisonPreferencesWorkflowError.optionStringTooLarge(
                    field: field,
                    maximumUTF8Bytes: comparisonPreferencesMaximumRegularExpressionUTF8Bytes
                )
            }
            if options.lineFiltersEnabled { try work.charge(patternBytes) }
        }
        for (index, rule) in options.substitutions.enumerated() {
            let field = "\(prefix).substitutions[\(index)].pattern"
            let patternBytes = try work.addString(rule.pattern, field: field)
            guard patternBytes <= comparisonPreferencesMaximumRegularExpressionUTF8Bytes else {
                throw ComparisonPreferencesWorkflowError.optionStringTooLarge(
                    field: field,
                    maximumUTF8Bytes: comparisonPreferencesMaximumRegularExpressionUTF8Bytes
                )
            }
            if options.substitutionsEnabled, !rule.pattern.isEmpty {
                try work.charge(patternBytes)
            }
            try work.addString(
                rule.replacement,
                field: "\(prefix).substitutions[\(index)].replacement"
            )
        }
        do {
            let sides = [
                try ComparisonProject.Side(
                    identity: .left,
                    path: URL(fileURLWithPath: "/dev/null")
                ),
                try ComparisonProject.Side(
                    identity: .right,
                    path: URL(fileURLWithPath: "/dev/null")
                )
            ]
            _ = try ComparisonProject(mode: mode.comparisonProjectMode, sides: sides, lineDiffOptions: options)
        } catch {
            if Task.isCancelled { throw ComparisonPreferencesWorkflowError.cancelled }
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: mode,
                field: "\(prefix).regularExpressions"
            )
        }
    }

    private static func validateDisplayFilter(
        _ filter: DisplayFilter,
        detectsMovedBlocks: Bool,
        mode: ComparisonPreferencesMode,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        let field = "\(mode.rawValue).displayFilter.expression"
        let expressionBytes = try work.addString(filter.expression.text, field: field)
        if filter.expression.isRegularExpression {
            guard expressionBytes <= comparisonPreferencesMaximumRegularExpressionUTF8Bytes else {
                throw ComparisonPreferencesWorkflowError.optionStringTooLarge(
                    field: field,
                    maximumUTF8Bytes: comparisonPreferencesMaximumRegularExpressionUTF8Bytes
                )
            }
            try work.charge(expressionBytes)
        }
        do {
            try filter.validate()
        } catch {
            if Task.isCancelled { throw ComparisonPreferencesWorkflowError.cancelled }
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: mode,
                field: "displayFilter"
            )
        }
        guard filter.predicate != .moved || detectsMovedBlocks else {
            throw ComparisonPreferencesWorkflowError.invalidCrossField(
                mode: mode,
                fields: "displayFilter.predicate, detectMovedBlocks"
            )
        }
    }

    private static func validateTableParsing(
        _ options: DelimitedTableParsingOptions,
        prefix: String,
        work: inout ComparisonPreferencesWorkBudget
    ) throws {
        try work.addItem()
        try work.addString(String(options.delimiter), field: "\(prefix).delimiter")
        guard isValidTableCharacter(options.delimiter) else {
            throw ComparisonPreferencesWorkflowError.invalidOption(
                mode: .table,
                field: "\(prefix).delimiter"
            )
        }
        if let quote = options.quote {
            try work.addItem()
            try work.addString(String(quote), field: "\(prefix).quote")
            guard isValidTableCharacter(quote), quote != options.delimiter else {
                throw ComparisonPreferencesWorkflowError.invalidCrossField(
                    mode: .table,
                    fields: "\(prefix).delimiter, \(prefix).quote"
                )
            }
        }
        let declared = options.limits
        let ceiling = DelimitedTableLimits.default
        let values: [(String, Int, ClosedRange<Int>)] = [
            ("maximumInputBytes", declared.maximumInputBytes, 0...ceiling.maximumInputBytes),
            ("maximumRows", declared.maximumRows, 1...ceiling.maximumRows),
            (
                "maximumColumnsPerRow",
                declared.maximumColumnsPerRow,
                1...ceiling.maximumColumnsPerRow
            ),
            ("maximumTotalCells", declared.maximumTotalCells, 1...ceiling.maximumTotalCells),
            ("maximumCellBytes", declared.maximumCellBytes, 0...ceiling.maximumCellBytes)
        ]
        for (field, value, range) in values {
            try requireRange(value, range, mode: .table, field: "\(prefix).limits.\(field)")
        }
    }

    private static func validateTableComparison(
        _ options: TableComparisonOptions,
        prefix: String
    ) throws {
        let ceiling = TableComparisonOptions.default
        let values: [(String, Int, Int)] = [
            (
                "maximumExactEditDistance",
                options.maximumExactEditDistance,
                ceiling.maximumExactEditDistance
            ),
            ("maximumAlignmentWork", options.maximumAlignmentWork, ceiling.maximumAlignmentWork),
            ("maximumComparedRows", options.maximumComparedRows, ceiling.maximumComparedRows),
            ("maximumComparedCells", options.maximumComparedCells, ceiling.maximumComparedCells)
        ]
        for (field, value, maximum) in values {
            try requireRange(value, 0...maximum, mode: .table, field: "\(prefix).\(field)")
        }
    }

    private static func isValidTableCharacter(_ value: Character) -> Bool {
        let scalars = value.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return false }
        return scalar.value != 0 && scalar.value != 0x0A && scalar.value != 0x0D
    }

    private static func requireRange(
        _ value: Int,
        _ range: ClosedRange<Int>,
        mode: ComparisonPreferencesMode,
        field: String
    ) throws {
        guard range.contains(value) else {
            throw ComparisonPreferencesWorkflowError.invalidOption(mode: mode, field: field)
        }
    }
}

private struct ComparisonPreferencesWorkBudget {
    let limits: ComparisonPreferencesWorkflowLimits
    private(set) var consumed = 0
    private var optionItems = 0
    private var totalStringUTF8Bytes = 0
    private var nextCancellationCheck: Int

    init(limits: ComparisonPreferencesWorkflowLimits) {
        self.init(uncheckedLimits: limits, consumed: 0)
    }

    init(limits: ComparisonPreferencesWorkflowLimits, consumed: Int) throws {
        guard (0...limits.maximumWorkUnits).contains(consumed) else {
            throw ComparisonPreferencesWorkflowError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        self.init(uncheckedLimits: limits, consumed: consumed)
    }

    private init(uncheckedLimits limits: ComparisonPreferencesWorkflowLimits, consumed: Int) {
        self.limits = limits
        self.consumed = consumed
        let (next, overflow) = consumed.addingReportingOverflow(limits.cancellationCheckInterval)
        nextCancellationCheck = overflow ? Int.max : next
    }

    mutating func addItem() throws { try addItems(1) }

    mutating func addItems(_ count: Int) throws {
        guard count >= 0,
            count <= limits.maximumOptionItems - optionItems
        else {
            throw ComparisonPreferencesWorkflowError.tooManyOptionItems(
                maximumCount: limits.maximumOptionItems
            )
        }
        optionItems += count
        try charge(count)
    }

    @discardableResult
    mutating func addString(_ value: String, field: String) throws -> Int {
        var count = 0
        for _ in value.utf8 {
            guard count < limits.maximumOptionStringUTF8Bytes else {
                throw ComparisonPreferencesWorkflowError.optionStringTooLarge(
                    field: field,
                    maximumUTF8Bytes: limits.maximumOptionStringUTF8Bytes
                )
            }
            count += 1
            try charge(1)
        }
        guard count <= limits.maximumOptionStringUTF8Bytes else {
            throw ComparisonPreferencesWorkflowError.optionStringTooLarge(
                field: field,
                maximumUTF8Bytes: limits.maximumOptionStringUTF8Bytes
            )
        }
        guard count <= limits.maximumTotalOptionStringUTF8Bytes - totalStringUTF8Bytes else {
            throw ComparisonPreferencesWorkflowError.totalOptionStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalOptionStringUTF8Bytes
            )
        }
        totalStringUTF8Bytes += count
        return count
    }

    mutating func checkedSum(_ lhs: Int, _ rhs: Int) throws -> Int {
        guard rhs >= 0, rhs <= Int.max - lhs else {
            throw ComparisonPreferencesWorkflowError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        return lhs + rhs
    }

    mutating func charge(_ amount: Int) throws {
        guard amount >= 0, amount <= limits.maximumWorkUnits - consumed else {
            throw ComparisonPreferencesWorkflowError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        consumed += amount
        if consumed >= nextCancellationCheck {
            try ComparisonPreferencesValidation.checkCancellation()
            let (next, overflow) = consumed.addingReportingOverflow(
                limits.cancellationCheckInterval
            )
            nextCancellationCheck = overflow ? Int.max : next
        }
    }
}

private enum ComparisonPreferencesPersistence {
    struct CanonicalContent {
        let data: Data
        let sha256: [UInt8]
        let workUnits: Int
    }

    private struct CanonicalPayload {
        let data: Data
        let workUnits: Int
    }

    static func encode(
        _ snapshot: ComparisonPreferencesSnapshot,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws -> ComparisonPreferencesEncodedDocument {
        do {
            var work = try ComparisonPreferencesValidation.measuredValidation(
                of: snapshot.preferences,
                limits: limits
            )
            let intermediateUpperBound = try preflightIntermediateEncoding(
                snapshot.preferences,
                limits: limits,
                work: &work
            )
            let canonical = try canonicalPayload(
                ComparisonPreferencesWireDocument(snapshot),
                limits: limits,
                maximumWorkUnits: limits.maximumWorkUnits - work,
                maximumEncodedBytes: intermediateUpperBound
            )
            work = try addingPersistenceWork(canonical.workUnits, to: work, limits: limits)
            work = try addingPersistenceWork(canonical.data.count, to: work, limits: limits)
            return ComparisonPreferencesEncodedDocument(
                data: canonical.data,
                sha256: try sha256(
                    canonical.data,
                    cancellationCheckInterval: limits.cancellationCheckInterval
                ),
                workUnits: work
            )
        } catch let error as ComparisonPreferencesWorkflowError {
            throw error
        } catch is CancellationError {
            throw ComparisonPreferencesWorkflowError.cancelled
        } catch {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
    }

    static func validatedCanonicalContent(
        _ preferences: ComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout Int
    ) throws -> CanonicalContent {
        work = try ComparisonPreferencesValidation.measuredValidation(
            of: preferences,
            limits: limits,
            startingAt: work
        )
        let intermediateUpperBound = try preflightIntermediateEncoding(
            preferences,
            limits: limits,
            work: &work
        )
        let canonical = try canonicalPayload(
            ComparisonPreferencesWireContent(preferences),
            limits: limits,
            maximumWorkUnits: limits.maximumWorkUnits - work,
            maximumEncodedBytes: intermediateUpperBound
        )
        work = try addingPersistenceWork(canonical.workUnits, to: work, limits: limits)
        work = try addingPersistenceWork(canonical.data.count, to: work, limits: limits)
        return CanonicalContent(
            data: canonical.data,
            sha256: try sha256(
                canonical.data,
                cancellationCheckInterval: limits.cancellationCheckInterval
            ),
            workUnits: canonical.workUnits + canonical.data.count
        )
    }

    static func decode(
        _ suppliedData: Data,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws -> ComparisonPreferencesDecodedDocument {
        do {
            try ComparisonPreferencesValidation.checkCancellation()
            guard suppliedData.count <= limits.maximumPersistenceInputBytes else {
                throw ComparisonPreferencesWorkflowError.persistenceInputTooLarge(
                    maximumBytes: limits.maximumPersistenceInputBytes
                )
            }
            let data = immutableSnapshot(of: suppliedData)
            guard data.count <= limits.maximumPersistenceInputBytes else {
                throw ComparisonPreferencesWorkflowError.persistenceInputTooLarge(
                    maximumBytes: limits.maximumPersistenceInputBytes
                )
            }
            var work = try addingPersistenceWork(data.count, to: 0, limits: limits)
            work = try addingPersistenceWork(data.count, to: work, limits: limits)
            try preflightJSON(data, limits: limits)
            work = try addingPersistenceWork(data.count, to: work, limits: limits)
            let wire = try JSONDecoder().decode(ComparisonPreferencesWireDocument.self, from: data)
            try wire.preflightMaterialization(limits: limits)
            work = try addingPersistenceWork(data.count, to: work, limits: limits)
            let preferences = try wire.preferences()
            work = try ComparisonPreferencesValidation.measuredValidation(
                of: preferences,
                limits: limits,
                startingAt: work
            )
            let snapshot = ComparisonPreferencesSnapshot(
                uncheckedRevision: try wire.revision.value,
                preferences: preferences
            )
            let intermediateUpperBound = try preflightIntermediateEncoding(
                preferences,
                limits: limits,
                work: &work
            )
            let canonical = try canonicalPayload(
                ComparisonPreferencesWireDocument(snapshot),
                limits: limits,
                maximumWorkUnits: limits.maximumWorkUnits - work,
                maximumEncodedBytes: intermediateUpperBound
            )
            work = try addingPersistenceWork(canonical.workUnits, to: work, limits: limits)
            work = try chargeByteComparison(
                canonical.data,
                data,
                work: work,
                limits: limits
            )
            guard canonical.data == data else {
                throw ComparisonPreferencesWorkflowError.nonCanonicalPersistence
            }
            work = try addingPersistenceWork(canonical.data.count, to: work, limits: limits)
            return ComparisonPreferencesDecodedDocument(
                snapshot: snapshot,
                sha256: try sha256(
                    canonical.data,
                    cancellationCheckInterval: limits.cancellationCheckInterval
                ),
                workUnits: work
            )
        } catch let error as ComparisonPreferencesWorkflowError {
            throw error
        } catch is CancellationError {
            throw ComparisonPreferencesWorkflowError.cancelled
        } catch {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
    }

    private static func addingPersistenceWork(
        _ addition: Int,
        to consumed: Int,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws -> Int {
        guard addition >= 0, addition <= limits.maximumWorkUnits - consumed else {
            throw ComparisonPreferencesWorkflowError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        return consumed + addition
    }

    static func chargeByteComparison(
        _ lhs: Data,
        _ rhs: Data,
        work: Int,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws -> Int {
        try addingPersistenceWork(min(lhs.count, rhs.count), to: work, limits: limits)
    }

    private static func immutableSnapshot(of data: Data) -> Data {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return Data() }
            return Data(bytes: baseAddress, count: bytes.count)
        }
    }

    private static func preflightIntermediateEncoding(
        _ preferences: ComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits,
        work: inout Int
    ) throws -> Int {
        let itemCount = try persistenceItemCount(preferences, limits: limits)
        let (dynamicStructuralBytes, overflow) = itemCount.multipliedReportingOverflow(by: 256)
        guard !overflow, dynamicStructuralBytes <= Int.max - 16 * 1_024 else {
            throw ComparisonPreferencesWorkflowError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        let maximumStructuralBytes = 16 * 1_024 + dynamicStructuralBytes
        let maximumStringBytes = try persistenceEscapedStringBytes(
            preferences,
            limits: limits
        )
        guard maximumStructuralBytes <= limits.maximumPersistenceOutputBytes,
            maximumStringBytes <= limits.maximumPersistenceOutputBytes - maximumStructuralBytes
        else {
            throw ComparisonPreferencesWorkflowError.persistenceOutputTooLarge(
                maximumBytes: limits.maximumPersistenceOutputBytes
            )
        }
        let upperBound = maximumStructuralBytes + maximumStringBytes
        work = try addingPersistenceWork(upperBound, to: work, limits: limits)
        return upperBound
    }

    private static func persistenceItemCount(
        _ preferences: ComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws -> Int {
        let counts = [
            preferences.text.twoWay.lineFilters.count,
            preferences.text.twoWay.substitutions.count,
            preferences.folder.filenameFilter.rules.count,
            preferences.image.loading.supportedTypeIdentifiers.count,
            preferences.webpage.twoWay.lineDiffOptions.lineFilters.count,
            preferences.webpage.twoWay.lineDiffOptions.substitutions.count
        ]
        var total = 0
        for count in counts {
            guard count <= limits.maximumOptionItems - total else {
                throw ComparisonPreferencesWorkflowError.tooManyOptionItems(
                    maximumCount: limits.maximumOptionItems
                )
            }
            total += count
        }
        return total
    }

    private static func persistenceEscapedStringBytes(
        _ preferences: ComparisonPreferences,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws -> Int {
        var total = 0
        func add(_ value: String) throws {
            for byte in value.utf8 {
                let escapedBytes =
                    switch byte {
                    case 0x00...0x1F: 6
                    case 0x22, 0x2F, 0x5C: 2
                    default: 1
                    }
                guard escapedBytes <= limits.maximumPersistenceOutputBytes - total else {
                    throw ComparisonPreferencesWorkflowError.persistenceOutputTooLarge(
                        maximumBytes: limits.maximumPersistenceOutputBytes
                    )
                }
                total += escapedBytes
                if total / limits.cancellationCheckInterval
                    != (total - escapedBytes) / limits.cancellationCheckInterval
                {
                    try ComparisonPreferencesValidation.checkCancellation()
                }
            }
        }
        func add(_ options: LineDiffOptions) throws {
            for rule in options.lineFilters { try add(rule.pattern) }
            for rule in options.substitutions {
                try add(rule.pattern)
                try add(rule.replacement)
            }
        }
        try add(preferences.text.twoWay)
        try add(preferences.text.displayFilter.expression.text)
        for rule in preferences.folder.filenameFilter.rules { try add(rule.pattern.source) }
        try add(preferences.folder.resultFilter.pathQuery)
        try add(String(preferences.table.parsing.delimiter))
        if let quote = preferences.table.parsing.quote { try add(String(quote)) }
        try add(String(preferences.table.threeWay.parsingOptions.delimiter))
        if let quote = preferences.table.threeWay.parsingOptions.quote { try add(String(quote)) }
        for identifier in preferences.image.loading.supportedTypeIdentifiers { try add(identifier) }
        try add(preferences.webpage.twoWay.lineDiffOptions)
        if let context = preferences.webpage.threeWay.expectedContext { try add(context.identifier) }
        try add(preferences.webpage.displayFilter.expression.text)
        try ComparisonPreferencesValidation.checkCancellation()
        return total
    }

    private static func canonicalPayload<Value: Encodable>(
        _ value: Value,
        limits: ComparisonPreferencesWorkflowLimits,
        maximumWorkUnits: Int,
        maximumEncodedBytes: Int
    ) throws -> CanonicalPayload {
        let encoded = try JSONEncoder().encode(value)
        guard encoded.count <= maximumEncodedBytes else {
            throw ComparisonPreferencesWorkflowError.persistenceOutputTooLarge(
                maximumBytes: limits.maximumPersistenceOutputBytes
            )
        }
        try ComparisonPreferencesValidation.checkCancellation()
        guard encoded.count <= maximumWorkUnits / 4 else {
            throw ComparisonPreferencesWorkflowError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        let object = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed])
        var writer = ComparisonPreferencesCanonicalJSONWriter(limits: limits)
        try writer.append(object)
        let intermediateWork = try addingPersistenceWork(
            encoded.count,
            to: encoded.count,
            limits: limits
        )
        return CanonicalPayload(
            data: writer.data,
            workUnits: try addingPersistenceWork(
                writer.data.count,
                to: intermediateWork,
                limits: limits
            )
        )
    }

    private static func preflightJSON(
        _ data: Data,
        limits: ComparisonPreferencesWorkflowLimits
    ) throws {
        try data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var scanner = ComparisonPreferencesJSONScanner(bytes: bytes, limits: limits)
            try scanner.validate()
        }
    }

    private static func sha256(
        _ data: Data,
        cancellationCheckInterval: Int
    ) throws -> [UInt8] {
        var hasher = SHA256()
        var offset = 0
        while offset < data.count {
            try ComparisonPreferencesValidation.checkCancellation()
            let upper = min(data.count, offset + cancellationCheckInterval)
            hasher.update(data: data[offset..<upper])
            offset = upper
        }
        try ComparisonPreferencesValidation.checkCancellation()
        return Array(hasher.finalize())
    }
}

private struct ComparisonPreferencesCanonicalJSONWriter {
    private(set) var data = Data()
    private let limits: ComparisonPreferencesWorkflowLimits
    private var bytesSinceCancellationCheck = 0

    init(limits: ComparisonPreferencesWorkflowLimits) {
        self.limits = limits
        data.reserveCapacity(min(limits.maximumPersistenceOutputBytes, 64 * 1_024))
    }

    mutating func append(_ value: Any) throws {
        switch value {
        case is NSNull:
            try appendASCII("null")
        case let value as String:
            try appendString(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                try appendASCII(value.boolValue ? "true" : "false")
            } else {
                try appendInteger(value)
            }
        case let value as [Any]:
            try appendByte(0x5B)
            for (index, element) in value.enumerated() {
                if index != 0 { try appendByte(0x2C) }
                try append(element)
            }
            try appendByte(0x5D)
        case let value as [String: Any]:
            let entries = value.sorted {
                Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8))
            }
            try appendByte(0x7B)
            for (index, entry) in entries.enumerated() {
                if index != 0 { try appendByte(0x2C) }
                try appendString(entry.key)
                try appendByte(0x3A)
                try append(entry.value)
            }
            try appendByte(0x7D)
        default:
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
    }

    private mutating func appendInteger(_ value: NSNumber) throws {
        let text = value.stringValue
        guard !text.isEmpty,
            text == "0" || text.first != "0",
            text != "-0",
            text.allSatisfy({ $0 == "-" || $0.isASCII && $0.isNumber })
        else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        try appendASCII(text)
    }

    private mutating func appendString(_ value: String) throws {
        try appendByte(0x22)
        for byte in value.utf8 {
            switch byte {
            case 0x08: try appendASCII("\\b")
            case 0x09: try appendASCII("\\t")
            case 0x0A: try appendASCII("\\n")
            case 0x0C: try appendASCII("\\f")
            case 0x0D: try appendASCII("\\r")
            case 0x22: try appendASCII("\\\"")
            case 0x5C: try appendASCII("\\\\")
            case 0x00...0x07, 0x0B, 0x0E...0x1F:
                try appendASCII(String(format: "\\u%04x", byte))
            default:
                try appendByte(byte)
            }
        }
        try appendByte(0x22)
    }

    private mutating func appendASCII(_ value: String) throws {
        for byte in value.utf8 { try appendByte(byte) }
    }

    private mutating func appendByte(_ byte: UInt8) throws {
        guard data.count < limits.maximumPersistenceOutputBytes else {
            throw ComparisonPreferencesWorkflowError.persistenceOutputTooLarge(
                maximumBytes: limits.maximumPersistenceOutputBytes
            )
        }
        data.append(byte)
        bytesSinceCancellationCheck += 1
        if bytesSinceCancellationCheck >= limits.cancellationCheckInterval {
            try ComparisonPreferencesValidation.checkCancellation()
            bytesSinceCancellationCheck = 0
        }
    }
}

private struct ComparisonPreferencesJSONScanner {
    private static let maximumDepth = 64
    private static let maximumNumberBytes = 32
    private static let maximumKeyUTF8Bytes = 128
    private static let maximumContainerElements =
        ComparisonPreferencesWorkflowLimits.hardMaximumOptionItems
    private static let maximumValues =
        ComparisonPreferencesWorkflowLimits.hardMaximumOptionItems * 16 + 4_096

    private let bytes: UnsafeBufferPointer<UInt8>
    private let cancellationCheckInterval: Int
    private var index = 0
    private var valueCount = 0
    private var nextCancellationIndex: Int

    init(bytes: UnsafeBufferPointer<UInt8>, limits: ComparisonPreferencesWorkflowLimits) {
        self.bytes = bytes
        cancellationCheckInterval = limits.cancellationCheckInterval
        nextCancellationIndex = limits.cancellationCheckInterval
    }

    mutating func validate() throws {
        try skipWhitespace()
        try parseValue(depth: 0)
        try skipWhitespace()
        guard index == bytes.count else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
    }

    private mutating func parseValue(depth: Int) throws {
        guard valueCount < Self.maximumValues else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        valueCount += 1
        try checkCancellation()
        guard let byte = currentByte else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        switch byte {
        case 0x7B: try parseObject(depth: depth + 1)
        case 0x5B: try parseArray(depth: depth + 1)
        case 0x22: try skipString()
        case 0x74: try consumeLiteral("true")
        case 0x66: try consumeLiteral("false")
        case 0x6E: try consumeLiteral("null")
        case 0x2D, 0x30...0x39: try parseNumber()
        default: throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        try skipWhitespace()
        if consume(0x7D) { return }

        var count = 0
        var keys: Set<String> = []
        while true {
            try incrementContainerCount(&count)
            let key = try parseKey()
            guard keys.insert(key).inserted else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            try skipWhitespace()
            guard consume(0x3A) else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            try skipWhitespace()
            try parseValue(depth: depth)
            try skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            try skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        try skipWhitespace()
        if consume(0x5D) { return }

        var count = 0
        while true {
            try incrementContainerCount(&count)
            try parseValue(depth: depth)
            try skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            try skipWhitespace()
        }
    }

    private mutating func parseKey() throws -> String {
        guard consume(0x22) else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        var decoded: [UInt8] = []
        decoded.reserveCapacity(32)
        while let byte = currentByte {
            try checkCancellation()
            index += 1
            switch byte {
            case 0x22:
                guard decoded.count <= Self.maximumKeyUTF8Bytes,
                    let key = String(bytes: decoded, encoding: .utf8)
                else {
                    throw ComparisonPreferencesWorkflowError.malformedPersistence
                }
                return key
            case 0x00...0x1F:
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            case 0x5C:
                try appendEscape(to: &decoded)
            default:
                decoded.append(byte)
            }
            guard decoded.count <= Self.maximumKeyUTF8Bytes else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
        }
        throw ComparisonPreferencesWorkflowError.malformedPersistence
    }

    private mutating func skipString() throws {
        guard consume(0x22) else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        while let byte = currentByte {
            try checkCancellation()
            index += 1
            switch byte {
            case 0x22: return
            case 0x00...0x1F:
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            case 0x5C:
                try skipEscape()
            default:
                break
            }
        }
        throw ComparisonPreferencesWorkflowError.malformedPersistence
    }

    private mutating func appendEscape(to decoded: inout [UInt8]) throws {
        guard let escaped = currentByte else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C: decoded.append(escaped)
        case 0x62: decoded.append(0x08)
        case 0x66: decoded.append(0x0C)
        case 0x6E: decoded.append(0x0A)
        case 0x72: decoded.append(0x0D)
        case 0x74: decoded.append(0x09)
        case 0x75:
            let first = try parseUnicodeEscape()
            let scalar: UInt32
            if (0xD800...0xDBFF).contains(first) {
                guard consume(0x5C), consume(0x75) else {
                    throw ComparisonPreferencesWorkflowError.malformedPersistence
                }
                let second = try parseUnicodeEscape()
                guard (0xDC00...0xDFFF).contains(second) else {
                    throw ComparisonPreferencesWorkflowError.malformedPersistence
                }
                scalar = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
            } else {
                guard !(0xDC00...0xDFFF).contains(first) else {
                    throw ComparisonPreferencesWorkflowError.malformedPersistence
                }
                scalar = first
            }
            guard let unicodeScalar = Unicode.Scalar(scalar) else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            decoded.append(contentsOf: String(unicodeScalar).utf8)
        default:
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
    }

    private mutating func skipEscape() throws {
        guard let escaped = currentByte else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74:
            return
        case 0x75:
            _ = try parseUnicodeEscape()
        default:
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
    }

    private mutating func parseUnicodeEscape() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            index += 1
            value = value * 16 + UInt32(digit)
        }
        return value
    }

    private mutating func parseNumber() throws {
        let start = index
        _ = try consumeNumberByte(0x2D, start: start)
        guard let first = currentByte else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        if first == 0x30 {
            try advanceNumberByte(start: start)
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            repeat {
                try advanceNumberByte(start: start)
            } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if try consumeNumberByte(0x2E, start: start) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            repeat {
                try advanceNumberByte(start: start)
            } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        var hasExponent = try consumeNumberByte(0x65, start: start)
        if !hasExponent { hasExponent = try consumeNumberByte(0x45, start: start) }
        if hasExponent {
            if try !consumeNumberByte(0x2B, start: start) {
                _ = try consumeNumberByte(0x2D, start: start)
            }
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            repeat {
                try advanceNumberByte(start: start)
            } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
    }

    private mutating func consumeNumberByte(_ byte: UInt8, start: Int) throws -> Bool {
        guard currentByte == byte else { return false }
        try advanceNumberByte(start: start)
        return true
    }

    private mutating func advanceNumberByte(start: Int) throws {
        guard index - start < Self.maximumNumberBytes else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        index += 1
        try checkCancellation()
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        for byte in literalBytes {
            guard bytes[index] == byte else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            index += 1
        }
    }

    private mutating func incrementContainerCount(_ count: inout Int) throws {
        guard count < Self.maximumContainerElements else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
        count += 1
        try checkCancellation()
    }

    private func validateDepth(_ depth: Int) throws {
        guard depth <= Self.maximumDepth else {
            throw ComparisonPreferencesWorkflowError.malformedPersistence
        }
    }

    private mutating func skipWhitespace() throws {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
            try checkCancellation()
        }
    }

    private mutating func checkCancellation() throws {
        guard index >= nextCancellationIndex else { return }
        try ComparisonPreferencesValidation.checkCancellation()
        let (next, overflow) = index.addingReportingOverflow(cancellationCheckInterval)
        nextCancellationIndex = overflow ? Int.max : next
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }
}

private struct ComparisonPreferencesWireDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case text
        case folder
        case table
        case binary
        case image
        case webpage
    }

    let schemaVersion: Int
    let revision: ComparisonPreferencesRevisionWire
    let text: TextComparisonPreferencesWire
    let folder: FolderComparisonPreferencesWire
    let table: TableComparisonPreferencesWire
    let binary: BinaryComparisonPreferencesWire
    let image: ImageComparisonPreferencesWire
    let webpage: WebpageComparisonPreferencesWire

    init(_ snapshot: ComparisonPreferencesSnapshot) {
        schemaVersion = ComparisonPreferences.currentSchemaVersion
        revision = ComparisonPreferencesRevisionWire(snapshot.revision)
        text = TextComparisonPreferencesWire(snapshot.preferences.text)
        folder = FolderComparisonPreferencesWire(snapshot.preferences.folder)
        table = TableComparisonPreferencesWire(snapshot.preferences.table)
        binary = BinaryComparisonPreferencesWire(snapshot.preferences.binary)
        image = ImageComparisonPreferencesWire(snapshot.preferences.image)
        webpage = WebpageComparisonPreferencesWire(snapshot.preferences.webpage)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == ComparisonPreferences.currentSchemaVersion else {
            throw ComparisonPreferencesWorkflowError.unsupportedSchemaVersion(schemaVersion)
        }
        revision = try container.decode(ComparisonPreferencesRevisionWire.self, forKey: .revision)
        text = try container.decode(TextComparisonPreferencesWire.self, forKey: .text)
        folder = try container.decode(FolderComparisonPreferencesWire.self, forKey: .folder)
        table = try container.decode(TableComparisonPreferencesWire.self, forKey: .table)
        binary = try container.decode(BinaryComparisonPreferencesWire.self, forKey: .binary)
        image = try container.decode(ImageComparisonPreferencesWire.self, forKey: .image)
        webpage = try container.decode(WebpageComparisonPreferencesWire.self, forKey: .webpage)
    }

    func preferences() throws -> ComparisonPreferences {
        try ComparisonPreferences(
            uncheckedText: text.value,
            folder: folder.value,
            table: table.value,
            binary: binary.value,
            image: image.value,
            webpage: webpage.value
        )
    }

    func preflightMaterialization(limits: ComparisonPreferencesWorkflowLimits) throws {
        let counts = [
            text.twoWay.lineFilters.count,
            text.twoWay.substitutions.count,
            folder.filenameFilter.rules.count,
            folder.resultFilter.statuses.count,
            folder.resultFilter.kinds.count,
            image.loading.supportedTypeIdentifiers.count,
            webpage.twoWay.lineDiffOptions.lineFilters.count,
            webpage.twoWay.lineDiffOptions.substitutions.count
        ]
        var total = 0
        for count in counts {
            guard count <= limits.maximumOptionItems - total else {
                throw ComparisonPreferencesWorkflowError.tooManyOptionItems(
                    maximumCount: limits.maximumOptionItems
                )
            }
            total += count
            try ComparisonPreferencesValidation.checkCancellation()
        }
    }
}

private struct ComparisonPreferencesWireContent: Encodable {
    let text: TextComparisonPreferencesWire
    let folder: FolderComparisonPreferencesWire
    let table: TableComparisonPreferencesWire
    let binary: BinaryComparisonPreferencesWire
    let image: ImageComparisonPreferencesWire
    let webpage: WebpageComparisonPreferencesWire

    init(_ preferences: ComparisonPreferences) {
        text = TextComparisonPreferencesWire(preferences.text)
        folder = FolderComparisonPreferencesWire(preferences.folder)
        table = TableComparisonPreferencesWire(preferences.table)
        binary = BinaryComparisonPreferencesWire(preferences.binary)
        image = ImageComparisonPreferencesWire(preferences.image)
        webpage = WebpageComparisonPreferencesWire(preferences.webpage)
    }
}

private struct ComparisonPreferencesRevisionWire: Codable {
    let lineage: UInt64
    let generation: UInt64

    init(_ revision: ComparisonPreferencesRevision) {
        lineage = revision.lineage
        generation = revision.generation
    }

    var value: ComparisonPreferencesRevision {
        get throws {
            try ComparisonPreferencesRevision(lineage: lineage, generation: generation)
        }
    }
}

private struct ComparisonPreferencesRawValueWire<Value>: Codable
where Value: RawRepresentable, Value.RawValue: Codable {
    let rawValue: Value.RawValue

    init(_ value: Value) {
        rawValue = value.rawValue
    }

    var value: Value {
        get throws {
            guard let value = Value(rawValue: rawValue) else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            return value
        }
    }
}

private struct LineFilterRuleWire: Codable {
    let pattern: String
    let caseSensitive: Bool

    init(_ value: LineFilterRule) {
        pattern = value.pattern
        caseSensitive = value.caseSensitive
    }

    var value: LineFilterRule { LineFilterRule(pattern: pattern, caseSensitive: caseSensitive) }
}

private struct SubstitutionRuleWire: Codable {
    let pattern: String
    let replacement: String
    let caseSensitive: Bool

    init(_ value: SubstitutionRule) {
        pattern = value.pattern
        replacement = value.replacement
        caseSensitive = value.caseSensitive
    }

    var value: SubstitutionRule {
        SubstitutionRule(
            pattern: pattern,
            replacement: replacement,
            caseSensitive: caseSensitive
        )
    }
}

private struct LineDiffOptionsWire: Codable {
    let algorithm: DiffAlgorithm
    let whitespace: WhitespaceComparison
    let ignoreCase: Bool
    let ignoreNumbers: Bool
    let ignoreBlankLines: Bool
    let ignoreComments: Bool
    let ignoreLineEndings: Bool
    let indentHeuristic: Bool
    let detectMovedBlocks: Bool
    let lineFiltersEnabled: Bool
    let lineFilters: [LineFilterRuleWire]
    let substitutionsEnabled: Bool
    let substitutions: [SubstitutionRuleWire]

    init(_ value: LineDiffOptions) {
        algorithm = value.algorithm
        whitespace = value.whitespace
        ignoreCase = value.ignoreCase
        ignoreNumbers = value.ignoreNumbers
        ignoreBlankLines = value.ignoreBlankLines
        ignoreComments = value.ignoreComments
        ignoreLineEndings = value.ignoreLineEndings
        indentHeuristic = value.indentHeuristic
        detectMovedBlocks = value.detectMovedBlocks
        lineFiltersEnabled = value.lineFiltersEnabled
        lineFilters = value.lineFilters.map(LineFilterRuleWire.init)
        substitutionsEnabled = value.substitutionsEnabled
        substitutions = value.substitutions.map(SubstitutionRuleWire.init)
    }

    var value: LineDiffOptions {
        LineDiffOptions(
            algorithm: algorithm,
            whitespace: whitespace,
            ignoreCase: ignoreCase,
            ignoreNumbers: ignoreNumbers,
            ignoreBlankLines: ignoreBlankLines,
            ignoreComments: ignoreComments,
            ignoreLineEndings: ignoreLineEndings,
            indentHeuristic: indentHeuristic,
            detectMovedBlocks: detectMovedBlocks,
            lineFiltersEnabled: lineFiltersEnabled,
            lineFilters: lineFilters.map(\.value),
            substitutionsEnabled: substitutionsEnabled,
            substitutions: substitutions.map(\.value),
            commentSyntax: nil
        )
    }
}

private struct ThreeWayTextMergeOptionsWire: Codable {
    let diffAlgorithm: DiffAlgorithm
    let maximumInputBytes: Int
    let maximumInputLines: Int
    let maximumOutputBytes: Int
    let maximumOutputLines: Int
    let maximumRegions: Int

    init(_ value: ThreeWayTextMergeOptions) {
        diffAlgorithm = value.diffAlgorithm
        maximumInputBytes = value.maximumInputBytes
        maximumInputLines = value.maximumInputLines
        maximumOutputBytes = value.maximumOutputBytes
        maximumOutputLines = value.maximumOutputLines
        maximumRegions = value.maximumRegions
    }

    var value: ThreeWayTextMergeOptions {
        get throws {
            guard maximumInputBytes >= 0,
                maximumInputLines >= 0,
                maximumOutputBytes >= 0,
                maximumOutputLines >= 0,
                maximumRegions >= 0
            else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            return ThreeWayTextMergeOptions(
                diffAlgorithm: diffAlgorithm,
                maximumInputBytes: maximumInputBytes,
                maximumInputLines: maximumInputLines,
                maximumOutputBytes: maximumOutputBytes,
                maximumOutputLines: maximumOutputLines,
                maximumRegions: maximumRegions
            )
        }
    }
}

private enum DisplayFilterExpressionKindWire: String, Codable {
    case literal
    case regularExpression
}

private struct DisplayFilterWire: Codable {
    let expressionKind: DisplayFilterExpressionKindWire
    let expression: String
    let caseSensitive: Bool
    let invert: Bool
    let predicate: DisplayFilterRowPredicate

    init(_ value: DisplayFilter) {
        switch value.expression {
        case .literal(let expression):
            expressionKind = .literal
            self.expression = expression
        case .regularExpression(let expression):
            expressionKind = .regularExpression
            self.expression = expression
        }
        caseSensitive = value.caseSensitive
        invert = value.invert
        predicate = value.predicate
    }

    var value: DisplayFilter {
        let expression: DisplayFilterExpression =
            switch expressionKind {
            case .literal: .literal(self.expression)
            case .regularExpression: .regularExpression(self.expression)
            }
        return DisplayFilter(
            expression: expression,
            caseSensitive: caseSensitive,
            invert: invert,
            predicate: predicate
        )
    }
}

private struct TextComparisonPreferencesWire: Codable {
    let twoWay: LineDiffOptionsWire
    let threeWay: ThreeWayTextMergeOptionsWire
    let displayFilter: DisplayFilterWire

    init(_ value: TextComparisonPreferences) {
        twoWay = LineDiffOptionsWire(value.twoWay)
        threeWay = ThreeWayTextMergeOptionsWire(value.threeWay)
        displayFilter = DisplayFilterWire(value.displayFilter)
    }

    var value: TextComparisonPreferences {
        get throws {
            try TextComparisonPreferences(
                uncheckedTwoWay: twoWay.value,
                threeWay: threeWay.value,
                displayFilter: displayFilter.value
            )
        }
    }
}

private enum FilenameFilterPatternKindWire: String, Codable {
    case glob
    case regularExpression
}

private struct FilenameFilterRuleWire: Codable {
    let decision: ComparisonPreferencesRawValueWire<FilenameFilterDecision>
    let patternKind: FilenameFilterPatternKindWire
    let pattern: String
    let applicability: ComparisonPreferencesRawValueWire<FilenameFilterRuleApplicability>

    init(_ value: FilenameFilterRule) {
        decision = ComparisonPreferencesRawValueWire(value.decision)
        switch value.pattern {
        case .glob(let pattern):
            patternKind = .glob
            self.pattern = pattern
        case .regularExpression(let pattern):
            patternKind = .regularExpression
            self.pattern = pattern
        }
        applicability = ComparisonPreferencesRawValueWire(value.applicability)
    }

    var value: FilenameFilterRule {
        get throws {
            let pattern: FilenameFilterPattern =
                switch patternKind {
                case .glob: .glob(self.pattern)
                case .regularExpression: .regularExpression(self.pattern)
                }
            return try FilenameFilterRule(
                decision.value,
                pattern: pattern,
                applicability: applicability.value
            )
        }
    }
}

private struct FilenameFilterLimitsWire: Codable {
    let maximumRuleCount: Int
    let maximumPatternUTF8Bytes: Int
    let maximumTotalPatternUTF8Bytes: Int
    let maximumRelativePathUTF8Bytes: Int
    let maximumCompiledStateCount: Int
    let maximumMatchWork: Int
    let maximumRegularExpressionNestingDepth: Int
    let maximumRegularExpressionRepetition: Int

    init(_ value: FilenameFilterLimits) {
        maximumRuleCount = value.maximumRuleCount
        maximumPatternUTF8Bytes = value.maximumPatternUTF8Bytes
        maximumTotalPatternUTF8Bytes = value.maximumTotalPatternUTF8Bytes
        maximumRelativePathUTF8Bytes = value.maximumRelativePathUTF8Bytes
        maximumCompiledStateCount = value.maximumCompiledStateCount
        maximumMatchWork = value.maximumMatchWork
        maximumRegularExpressionNestingDepth = value.maximumRegularExpressionNestingDepth
        maximumRegularExpressionRepetition = value.maximumRegularExpressionRepetition
    }

    var value: FilenameFilterLimits {
        get throws {
            guard maximumRuleCount >= 0,
                maximumPatternUTF8Bytes >= 0,
                maximumTotalPatternUTF8Bytes >= 0,
                maximumRelativePathUTF8Bytes >= 0,
                maximumCompiledStateCount >= 0,
                maximumMatchWork >= 0,
                maximumRegularExpressionNestingDepth >= 0,
                maximumRegularExpressionRepetition >= 0
            else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            return FilenameFilterLimits(
                maximumRuleCount: maximumRuleCount,
                maximumPatternUTF8Bytes: maximumPatternUTF8Bytes,
                maximumTotalPatternUTF8Bytes: maximumTotalPatternUTF8Bytes,
                maximumRelativePathUTF8Bytes: maximumRelativePathUTF8Bytes,
                maximumCompiledStateCount: maximumCompiledStateCount,
                maximumMatchWork: maximumMatchWork,
                maximumRegularExpressionNestingDepth: maximumRegularExpressionNestingDepth,
                maximumRegularExpressionRepetition: maximumRegularExpressionRepetition
            )
        }
    }
}

private struct FolderFilenameFilterPreferencesWire: Codable {
    let rules: [FilenameFilterRuleWire]
    let defaultDecision: ComparisonPreferencesRawValueWire<FilenameFilterDecision>
    let matchSemantics: ComparisonPreferencesRawValueWire<FilenameFilterMatchSemantics>
    let casePolicy: ComparisonPreferencesRawValueWire<FilenameFilterCasePolicy>
    let limits: FilenameFilterLimitsWire

    init(_ value: FolderFilenameFilterPreferences) {
        rules = value.rules.map(FilenameFilterRuleWire.init)
        defaultDecision = ComparisonPreferencesRawValueWire(value.defaultDecision)
        matchSemantics = ComparisonPreferencesRawValueWire(value.matchSemantics)
        casePolicy = ComparisonPreferencesRawValueWire(value.casePolicy)
        limits = FilenameFilterLimitsWire(value.limits)
    }

    var value: FolderFilenameFilterPreferences {
        get throws {
            try FolderFilenameFilterPreferences(
                uncheckedRules: rules.map { try $0.value },
                defaultDecision: defaultDecision.value,
                matchSemantics: matchSemantics.value,
                casePolicy: casePolicy.value,
                limits: limits.value
            )
        }
    }
}

private struct FolderScanLimitsWire: Codable {
    let maximumDepth: Int
    let maximumEntries: Int
    let maximumExaminedEntries: Int
    let maximumIssues: Int
    let maximumOpenDirectoryDescriptors: Int
    let maximumPendingEntryNames: Int
    let maximumRelativePathUTF8Bytes: Int
    let maximumTotalAccountedBytes: Int64

    init(_ value: FolderScanLimits) {
        maximumDepth = value.maximumDepth
        maximumEntries = value.maximumEntries
        maximumExaminedEntries = value.maximumExaminedEntries
        maximumIssues = value.maximumIssues
        maximumOpenDirectoryDescriptors = value.maximumOpenDirectoryDescriptors
        maximumPendingEntryNames = value.maximumPendingEntryNames
        maximumRelativePathUTF8Bytes = value.maximumRelativePathUTF8Bytes
        maximumTotalAccountedBytes = value.maximumTotalAccountedBytes
    }

    var value: FolderScanLimits {
        get throws {
            guard maximumDepth >= 0,
                maximumEntries >= 0,
                maximumExaminedEntries >= 0,
                maximumIssues >= 0,
                maximumOpenDirectoryDescriptors >= 0,
                maximumPendingEntryNames >= 0,
                maximumRelativePathUTF8Bytes >= 0,
                maximumTotalAccountedBytes >= 0
            else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            return FolderScanLimits(
                maximumDepth: maximumDepth,
                maximumEntries: maximumEntries,
                maximumIssues: maximumIssues,
                maximumRelativePathUTF8Bytes: maximumRelativePathUTF8Bytes,
                maximumTotalAccountedBytes: maximumTotalAccountedBytes,
                maximumExaminedEntries: maximumExaminedEntries,
                maximumOpenDirectoryDescriptors: maximumOpenDirectoryDescriptors,
                maximumPendingEntryNames: maximumPendingEntryNames
            )
        }
    }
}

private struct FolderScanOptionsWire: Codable {
    let hiddenFilePolicy: ComparisonPreferencesRawValueWire<FolderScanHiddenFilePolicy>
    let symbolicLinkPolicy: ComparisonPreferencesRawValueWire<FolderScanSymbolicLinkPolicy>
    let errorPolicy: ComparisonPreferencesRawValueWire<FolderScanErrorPolicy>
    let limits: FolderScanLimitsWire

    init(_ value: FolderScanOptions) {
        hiddenFilePolicy = ComparisonPreferencesRawValueWire(value.hiddenFilePolicy)
        symbolicLinkPolicy = ComparisonPreferencesRawValueWire(value.symbolicLinkPolicy)
        errorPolicy = ComparisonPreferencesRawValueWire(value.errorPolicy)
        limits = FolderScanLimitsWire(value.limits)
    }

    var value: FolderScanOptions {
        get throws {
            try FolderScanOptions(
                hiddenFilePolicy: hiddenFilePolicy.value,
                symbolicLinkPolicy: symbolicLinkPolicy.value,
                errorPolicy: errorPolicy.value,
                limits: limits.value
            )
        }
    }
}

private struct FolderComparisonOptionsWire: Codable {
    let method: FolderComparisonMethod
    let pathCaseSensitivity: FolderPathCaseSensitivity
    let modificationDateToleranceBits: UInt64

    init(_ value: FolderComparisonOptions) {
        method = value.method
        pathCaseSensitivity = value.pathCaseSensitivity
        modificationDateToleranceBits = canonicalComparisonPreferencesDoubleBits(
            value.modificationDateTolerance
        )
    }

    var value: FolderComparisonOptions {
        get throws {
            let modificationDateTolerance = Double(bitPattern: modificationDateToleranceBits)
            guard modificationDateTolerance.isFinite, modificationDateTolerance >= 0 else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            return FolderComparisonOptions(
                method: method,
                pathCaseSensitivity: pathCaseSensitivity,
                modificationDateTolerance: modificationDateTolerance
            )
        }
    }
}

private struct ThreeWayFolderComparisonOptionsWire: Codable {
    let comparison: FolderComparisonOptionsWire
    let maximumEntriesPerSnapshot: Int
    let maximumResultEntries: Int
    let maximumRelativePathUTF8Bytes: Int
    let maximumDigestBytes: Int
    let maximumDigestAlgorithmUTF8Bytes: Int
    let maximumWorkUnits: Int

    init(_ value: ThreeWayFolderComparisonOptions) {
        comparison = FolderComparisonOptionsWire(value.comparison)
        maximumEntriesPerSnapshot = value.maximumEntriesPerSnapshot
        maximumResultEntries = value.maximumResultEntries
        maximumRelativePathUTF8Bytes = value.maximumRelativePathUTF8Bytes
        maximumDigestBytes = value.maximumDigestBytes
        maximumDigestAlgorithmUTF8Bytes = value.maximumDigestAlgorithmUTF8Bytes
        maximumWorkUnits = value.maximumWorkUnits
    }

    var value: ThreeWayFolderComparisonOptions {
        get throws {
            try ThreeWayFolderComparisonOptions(
                comparison: comparison.value,
                maximumEntriesPerSnapshot: maximumEntriesPerSnapshot,
                maximumResultEntries: maximumResultEntries,
                maximumRelativePathUTF8Bytes: maximumRelativePathUTF8Bytes,
                maximumDigestBytes: maximumDigestBytes,
                maximumDigestAlgorithmUTF8Bytes: maximumDigestAlgorithmUTF8Bytes,
                maximumWorkUnits: maximumWorkUnits
            )
        }
    }
}

private enum DirectoryHiddenFilterWire: String, Codable {
    case include
    case exclude
    case only

    init(_ value: DirectoryHiddenFilter) {
        switch value {
        case .include: self = .include
        case .exclude: self = .exclude
        case .only: self = .only
        }
    }

    var value: DirectoryHiddenFilter {
        switch self {
        case .include: .include
        case .exclude: .exclude
        case .only: .only
        }
    }
}

private struct DirectoryResultFilterWire: Codable {
    let statuses: [ComparisonPreferencesRawValueWire<DirectoryComparisonStatus>]
    let pathQuery: String
    let kinds: [ComparisonPreferencesRawValueWire<DirectoryEntryKind>]
    let hidden: DirectoryHiddenFilterWire

    init(_ value: DirectoryResultFilter) {
        statuses = value.statuses.sorted { $0.rawValue < $1.rawValue }
            .map(ComparisonPreferencesRawValueWire.init)
        pathQuery = value.pathQuery
        kinds = value.kinds.sorted { $0.rawValue < $1.rawValue }
            .map(ComparisonPreferencesRawValueWire.init)
        hidden = DirectoryHiddenFilterWire(value.hidden)
    }

    var value: DirectoryResultFilter {
        get throws {
            try DirectoryResultFilter(
                statuses: Set(statuses.map { try $0.value }),
                pathQuery: pathQuery,
                kinds: Set(kinds.map { try $0.value }),
                hidden: hidden.value
            )
        }
    }
}

private struct FolderComparisonPreferencesWire: Codable {
    let scanning: FolderScanOptionsWire
    let twoWay: FolderComparisonOptionsWire
    let threeWay: ThreeWayFolderComparisonOptionsWire
    let filenameFilter: FolderFilenameFilterPreferencesWire
    let resultFilter: DirectoryResultFilterWire

    init(_ value: FolderComparisonPreferences) {
        scanning = FolderScanOptionsWire(value.scanning)
        twoWay = FolderComparisonOptionsWire(value.twoWay)
        threeWay = ThreeWayFolderComparisonOptionsWire(value.threeWay)
        filenameFilter = FolderFilenameFilterPreferencesWire(value.filenameFilter)
        resultFilter = DirectoryResultFilterWire(value.resultFilter)
    }

    var value: FolderComparisonPreferences {
        get throws {
            try FolderComparisonPreferences(
                uncheckedScanning: scanning.value,
                twoWay: twoWay.value,
                threeWay: threeWay.value,
                filenameFilter: filenameFilter.value,
                resultFilter: resultFilter.value
            )
        }
    }
}

private struct DelimitedTableLimitsWire: Codable {
    let maximumInputBytes: Int
    let maximumRows: Int
    let maximumColumnsPerRow: Int
    let maximumTotalCells: Int
    let maximumCellBytes: Int

    init(_ value: DelimitedTableLimits) {
        maximumInputBytes = value.maximumInputBytes
        maximumRows = value.maximumRows
        maximumColumnsPerRow = value.maximumColumnsPerRow
        maximumTotalCells = value.maximumTotalCells
        maximumCellBytes = value.maximumCellBytes
    }

    var value: DelimitedTableLimits {
        DelimitedTableLimits(
            maximumInputBytes: maximumInputBytes,
            maximumRows: maximumRows,
            maximumColumnsPerRow: maximumColumnsPerRow,
            maximumTotalCells: maximumTotalCells,
            maximumCellBytes: maximumCellBytes
        )
    }
}

private struct DelimitedTableParsingOptionsWire: Codable {
    let delimiter: String
    let quote: String?
    let allowsNewlinesInQuotedCells: Bool
    let limits: DelimitedTableLimitsWire

    init(_ value: DelimitedTableParsingOptions) {
        delimiter = String(value.delimiter)
        quote = value.quote.map(String.init)
        allowsNewlinesInQuotedCells = value.allowsNewlinesInQuotedCells
        limits = DelimitedTableLimitsWire(value.limits)
    }

    var value: DelimitedTableParsingOptions {
        get throws {
            guard delimiter.count == 1, let delimiter = delimiter.first else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            let quote: Character?
            if let encodedQuote {
                guard encodedQuote.count == 1, let decodedQuote = encodedQuote.first else {
                    throw ComparisonPreferencesWorkflowError.malformedPersistence
                }
                quote = decodedQuote
            } else {
                quote = nil
            }
            return DelimitedTableParsingOptions(
                delimiter: delimiter,
                quote: quote,
                allowsNewlinesInQuotedCells: allowsNewlinesInQuotedCells,
                limits: limits.value
            )
        }
    }

    private var encodedQuote: String? { quote }
}

private struct TableComparisonOptionsWire: Codable {
    let maximumExactEditDistance: Int
    let maximumAlignmentWork: Int
    let maximumComparedRows: Int
    let maximumComparedCells: Int

    init(_ value: TableComparisonOptions) {
        maximumExactEditDistance = value.maximumExactEditDistance
        maximumAlignmentWork = value.maximumAlignmentWork
        maximumComparedRows = value.maximumComparedRows
        maximumComparedCells = value.maximumComparedCells
    }

    var value: TableComparisonOptions {
        TableComparisonOptions(
            maximumExactEditDistance: maximumExactEditDistance,
            maximumAlignmentWork: maximumAlignmentWork,
            maximumComparedRows: maximumComparedRows,
            maximumComparedCells: maximumComparedCells
        )
    }
}

private struct ThreeWayTableComparisonOptionsWire: Codable {
    let parsingOptions: DelimitedTableParsingOptionsWire
    let comparisonOptions: TableComparisonOptionsWire
    let maximumComparedValueBytes: Int
    let maximumResultRows: Int
    let maximumResultCells: Int

    init(_ value: ThreeWayTableComparisonOptions) {
        parsingOptions = DelimitedTableParsingOptionsWire(value.parsingOptions)
        comparisonOptions = TableComparisonOptionsWire(value.comparisonOptions)
        maximumComparedValueBytes = value.maximumComparedValueBytes
        maximumResultRows = value.maximumResultRows
        maximumResultCells = value.maximumResultCells
    }

    var value: ThreeWayTableComparisonOptions {
        get throws {
            try ThreeWayTableComparisonOptions(
                parsingOptions: parsingOptions.value,
                comparisonOptions: comparisonOptions.value,
                maximumComparedValueBytes: maximumComparedValueBytes,
                maximumResultRows: maximumResultRows,
                maximumResultCells: maximumResultCells
            )
        }
    }
}

private struct TableWorkspacePresentationOptionsWire: Codable {
    let headerVisibility: UInt8
    let headerLabels: UInt8
    let showsRowNumbers: Bool
    let wrapsCellText: Bool
    let synchronizesColumnWidths: Bool
    let highlightsCellDifferences: Bool

    init(_ value: TableWorkspacePresentationOptions) {
        headerVisibility = value.headerVisibility.rawValue
        headerLabels = value.headerLabels.rawValue
        showsRowNumbers = value.showsRowNumbers
        wrapsCellText = value.wrapsCellText
        synchronizesColumnWidths = value.synchronizesColumnWidths
        highlightsCellDifferences = value.highlightsCellDifferences
    }

    var value: TableWorkspacePresentationOptions {
        get throws {
            guard let headerVisibility = TableWorkspaceHeaderVisibility(rawValue: headerVisibility),
                let headerLabels = TableWorkspaceHeaderLabels(rawValue: headerLabels)
            else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            return TableWorkspacePresentationOptions(
                headerVisibility: headerVisibility,
                headerLabels: headerLabels,
                showsRowNumbers: showsRowNumbers,
                wrapsCellText: wrapsCellText,
                synchronizesColumnWidths: synchronizesColumnWidths,
                highlightsCellDifferences: highlightsCellDifferences
            )
        }
    }
}

private struct TableComparisonPreferencesWire: Codable {
    let parsing: DelimitedTableParsingOptionsWire
    let twoWay: TableComparisonOptionsWire
    let threeWay: ThreeWayTableComparisonOptionsWire
    let presentation: TableWorkspacePresentationOptionsWire

    init(_ value: TableComparisonPreferences) {
        parsing = DelimitedTableParsingOptionsWire(value.parsing)
        twoWay = TableComparisonOptionsWire(value.twoWay)
        threeWay = ThreeWayTableComparisonOptionsWire(value.threeWay)
        presentation = TableWorkspacePresentationOptionsWire(value.presentation)
    }

    var value: TableComparisonPreferences {
        get throws {
            try TableComparisonPreferences(
                uncheckedParsing: parsing.value,
                twoWay: twoWay.value,
                threeWay: threeWay.value,
                presentation: presentation.value
            )
        }
    }
}

private struct BinaryComparisonOptionsWire: Codable {
    let maximumExactEditDistance: Int
    let maximumAlignmentWork: Int

    init(_ value: BinaryComparisonOptions) {
        maximumExactEditDistance = value.maximumExactEditDistance
        maximumAlignmentWork = value.maximumAlignmentWork
    }

    var value: BinaryComparisonOptions {
        get throws {
            guard maximumExactEditDistance >= 0, maximumAlignmentWork >= 0 else {
                throw ComparisonPreferencesWorkflowError.malformedPersistence
            }
            return BinaryComparisonOptions(
                maximumExactEditDistance: maximumExactEditDistance,
                maximumAlignmentWork: maximumAlignmentWork
            )
        }
    }
}

private struct ThreeWayBinaryComparisonOptionsWire: Codable {
    let maximumInputBytes: Int
    let maximumExactEditDistance: Int
    let maximumAlignmentWork: Int
    let maximumRegions: Int
    let maximumOutputBytes: Int

    init(_ value: ThreeWayBinaryComparisonOptions) {
        maximumInputBytes = value.maximumInputBytes
        maximumExactEditDistance = value.maximumExactEditDistance
        maximumAlignmentWork = value.maximumAlignmentWork
        maximumRegions = value.maximumRegions
        maximumOutputBytes = value.maximumOutputBytes
    }

    var value: ThreeWayBinaryComparisonOptions {
        ThreeWayBinaryComparisonOptions(
            maximumInputBytes: maximumInputBytes,
            maximumExactEditDistance: maximumExactEditDistance,
            maximumAlignmentWork: maximumAlignmentWork,
            maximumRegions: maximumRegions,
            maximumOutputBytes: maximumOutputBytes
        )
    }
}

private struct BinaryComparisonPreferencesWire: Codable {
    let twoWay: BinaryComparisonOptionsWire
    let threeWay: ThreeWayBinaryComparisonOptionsWire
    let bytesPerRow: Int

    init(_ value: BinaryComparisonPreferences) {
        twoWay = BinaryComparisonOptionsWire(value.twoWay)
        threeWay = ThreeWayBinaryComparisonOptionsWire(value.threeWay)
        bytesPerRow = value.bytesPerRow
    }

    var value: BinaryComparisonPreferences {
        get throws {
            try BinaryComparisonPreferences(
                uncheckedTwoWay: twoWay.value,
                threeWay: threeWay.value,
                bytesPerRow: bytesPerRow
            )
        }
    }
}

private struct ImageComparisonLimitsWire: Codable {
    let maximumEncodedBytes: Int
    let maximumDimension: Int
    let maximumPixelCount: Int
    let maximumDecodedBytes: Int
    let supportedTypeIdentifiers: [String]

    init(_ value: ImageComparisonLimits) {
        maximumEncodedBytes = value.maximumEncodedBytes
        maximumDimension = value.maximumDimension
        maximumPixelCount = value.maximumPixelCount
        maximumDecodedBytes = value.maximumDecodedBytes
        supportedTypeIdentifiers = value.supportedTypeIdentifiers.sorted()
    }

    var value: ImageComparisonLimits {
        ImageComparisonLimits(
            maximumEncodedBytes: maximumEncodedBytes,
            maximumDimension: maximumDimension,
            maximumPixelCount: maximumPixelCount,
            maximumDecodedBytes: maximumDecodedBytes,
            supportedTypeIdentifiers: Set(supportedTypeIdentifiers)
        )
    }
}

private struct ImageComparisonOptionsWire: Codable {
    let channelTolerance: UInt8
    let maximumCanvasPixels: Int
    let maximumRegions: Int
    let maximumQueuedPixels: Int

    init(_ value: ImageComparisonOptions) {
        channelTolerance = value.channelTolerance
        maximumCanvasPixels = value.maximumCanvasPixels
        maximumRegions = value.maximumRegions
        maximumQueuedPixels = value.maximumQueuedPixels
    }

    var value: ImageComparisonOptions {
        ImageComparisonOptions(
            channelTolerance: channelTolerance,
            maximumCanvasPixels: maximumCanvasPixels,
            maximumRegions: maximumRegions,
            maximumQueuedPixels: maximumQueuedPixels
        )
    }
}

private struct ImageToolDifferenceOptionsWire: Codable {
    let pixelComparison: ImageComparisonOptionsWire
    let showsDifferences: Bool
    let differenceBlockSize: Int
    let colorDistanceThresholdBits: UInt64
    let insertionDetection: ComparisonPreferencesRawValueWire<ImageToolInsertionDetection>

    init(_ value: ImageToolDifferenceOptions) {
        pixelComparison = ImageComparisonOptionsWire(value.pixelComparison)
        showsDifferences = value.showsDifferences
        differenceBlockSize = value.differenceBlockSize
        colorDistanceThresholdBits = canonicalComparisonPreferencesDoubleBits(
            value.colorDistanceThreshold
        )
        insertionDetection = ComparisonPreferencesRawValueWire(value.insertionDetection)
    }

    var value: ImageToolDifferenceOptions {
        get throws {
            try ImageToolDifferenceOptions(
                pixelComparison: pixelComparison.value,
                showsDifferences: showsDifferences,
                differenceBlockSize: differenceBlockSize,
                colorDistanceThreshold: Double(bitPattern: colorDistanceThresholdBits),
                insertionDetection: insertionDetection.value
            )
        }
    }
}

private struct ImageToolZoomWire: Codable {
    let mode: ComparisonPreferencesRawValueWire<ImageToolZoomMode>
    let scaleBits: UInt64

    init(_ value: ImageToolZoom) {
        mode = ComparisonPreferencesRawValueWire(value.mode)
        scaleBits = canonicalComparisonPreferencesDoubleBits(value.scale)
    }

    var value: ImageToolZoom {
        get throws { try ImageToolZoom(mode: mode.value, scale: Double(bitPattern: scaleBits)) }
    }
}

private struct ImageToolOverlayWire: Codable {
    let mode: ComparisonPreferencesRawValueWire<ImageToolOverlayMode>
    let alphaBits: UInt64

    init(_ value: ImageToolOverlay) {
        mode = ComparisonPreferencesRawValueWire(value.mode)
        alphaBits = canonicalComparisonPreferencesDoubleBits(value.alpha)
    }

    var value: ImageToolOverlay {
        get throws { try ImageToolOverlay(mode: mode.value, alpha: Double(bitPattern: alphaBits)) }
    }
}

private struct ImageToolWipeWire: Codable {
    let mode: ComparisonPreferencesRawValueWire<ImageToolWipeMode>
    let positionBits: UInt64

    init(_ value: ImageToolWipe) {
        mode = ComparisonPreferencesRawValueWire(value.mode)
        positionBits = canonicalComparisonPreferencesDoubleBits(value.position)
    }

    var value: ImageToolWipe {
        get throws { try ImageToolWipe(mode: mode.value, position: Double(bitPattern: positionBits)) }
    }
}

private struct ImageToolAnimationWire: Codable {
    let blinksDifferences: Bool
    let blinkIntervalMilliseconds: Int
    let overlayIntervalMilliseconds: Int

    init(_ value: ImageToolAnimation) {
        blinksDifferences = value.blinksDifferences
        blinkIntervalMilliseconds = value.blinkIntervalMilliseconds
        overlayIntervalMilliseconds = value.overlayIntervalMilliseconds
    }

    var value: ImageToolAnimation {
        ImageToolAnimation(
            blinksDifferences: blinksDifferences,
            blinkIntervalMilliseconds: blinkIntervalMilliseconds,
            overlayIntervalMilliseconds: overlayIntervalMilliseconds
        )
    }
}

private struct ImageToolControlStateWire: Codable {
    let pageSelectionMode: ComparisonPreferencesRawValueWire<ImageToolPageSelectionMode>
    let differences: ImageToolDifferenceOptionsWire
    let zoom: ImageToolZoomWire
    let overlay: ImageToolOverlayWire
    let wipe: ImageToolWipeWire
    let animation: ImageToolAnimationWire

    init(_ value: ImageToolControlState) {
        pageSelectionMode = ComparisonPreferencesRawValueWire(value.pageSelectionMode)
        differences = ImageToolDifferenceOptionsWire(value.differences)
        zoom = ImageToolZoomWire(value.zoom)
        overlay = ImageToolOverlayWire(value.overlay)
        wipe = ImageToolWipeWire(value.wipe)
        animation = ImageToolAnimationWire(value.animation)
    }

    var value: ImageToolControlState {
        get throws {
            try ImageToolControlState(
                pageSelectionMode: pageSelectionMode.value,
                differences: differences.value,
                zoom: zoom.value,
                overlay: overlay.value,
                wipe: wipe.value,
                animation: animation.value
            )
        }
    }
}

private struct ImageComparisonPreferencesWire: Codable {
    let loading: ImageComparisonLimitsWire
    let controls: ImageToolControlStateWire

    init(_ value: ImageComparisonPreferences) {
        loading = ImageComparisonLimitsWire(value.loading)
        controls = ImageToolControlStateWire(value.controls)
    }

    var value: ImageComparisonPreferences {
        get throws {
            try ImageComparisonPreferences(
                uncheckedLoading: loading.value,
                controls: controls.value
            )
        }
    }
}

private struct WebPageComparisonLimitsWire: Codable {
    let maximumInputBytes: Int
    let maximumTokenCount: Int
    let maximumAttributeCount: Int
    let maximumAttributesPerTag: Int
    let maximumElementDepth: Int
    let maximumWorkUnits: Int
    let maximumOutputBytes: Int

    init(_ value: WebPageComparisonLimits) {
        maximumInputBytes = value.maximumInputBytes
        maximumTokenCount = value.maximumTokenCount
        maximumAttributeCount = value.maximumAttributeCount
        maximumAttributesPerTag = value.maximumAttributesPerTag
        maximumElementDepth = value.maximumElementDepth
        maximumWorkUnits = value.maximumWorkUnits
        maximumOutputBytes = value.maximumOutputBytes
    }

    var value: WebPageComparisonLimits {
        WebPageComparisonLimits(
            maximumInputBytes: maximumInputBytes,
            maximumTokenCount: maximumTokenCount,
            maximumAttributeCount: maximumAttributeCount,
            maximumAttributesPerTag: maximumAttributesPerTag,
            maximumElementDepth: maximumElementDepth,
            maximumWorkUnits: maximumWorkUnits,
            maximumOutputBytes: maximumOutputBytes
        )
    }
}

private struct WebPageComparisonOptionsWire: Codable {
    let mode: ComparisonPreferencesRawValueWire<WebPageComparisonMode>
    let lineDiffOptions: LineDiffOptionsWire
    let limits: WebPageComparisonLimitsWire

    init(_ value: WebPageComparisonOptions) {
        mode = ComparisonPreferencesRawValueWire(value.mode)
        lineDiffOptions = LineDiffOptionsWire(value.lineDiffOptions)
        limits = WebPageComparisonLimitsWire(value.limits)
    }

    var value: WebPageComparisonOptions {
        get throws {
            try WebPageComparisonOptions(
                mode: mode.value,
                lineDiffOptions: lineDiffOptions.value,
                limits: limits.value
            )
        }
    }
}

private struct ThreeWayWebPageComparisonContextWire: Codable {
    let identifier: String
    let generation: UInt64

    init(_ value: ThreeWayWebPageComparisonContext) {
        identifier = value.identifier
        generation = value.generation
    }

    var value: ThreeWayWebPageComparisonContext {
        ThreeWayWebPageComparisonContext(identifier: identifier, generation: generation)
    }
}

private struct ThreeWayWebPageComparisonLimitsWire: Codable {
    let maximumSourceInputBytesPerSnapshot: Int
    let maximumNormalizedInputBytesPerSnapshot: Int
    let maximumTokenCountPerSnapshot: Int
    let maximumAttributeCountPerSnapshot: Int
    let maximumTotalNormalizedInputBytes: Int
    let maximumInputLinesPerSnapshot: Int
    let maximumMetadataEntriesPerSnapshot: Int
    let maximumMetadataBytes: Int
    let maximumWorkUnits: Int
    let maximumResultRegions: Int
    let maximumMappedSegments: Int
    let maximumOutputBytes: Int
    let maximumOutputLines: Int

    init(_ value: ThreeWayWebPageComparisonLimits) {
        maximumSourceInputBytesPerSnapshot = value.maximumSourceInputBytesPerSnapshot
        maximumNormalizedInputBytesPerSnapshot = value.maximumNormalizedInputBytesPerSnapshot
        maximumTokenCountPerSnapshot = value.maximumTokenCountPerSnapshot
        maximumAttributeCountPerSnapshot = value.maximumAttributeCountPerSnapshot
        maximumTotalNormalizedInputBytes = value.maximumTotalNormalizedInputBytes
        maximumInputLinesPerSnapshot = value.maximumInputLinesPerSnapshot
        maximumMetadataEntriesPerSnapshot = value.maximumMetadataEntriesPerSnapshot
        maximumMetadataBytes = value.maximumMetadataBytes
        maximumWorkUnits = value.maximumWorkUnits
        maximumResultRegions = value.maximumResultRegions
        maximumMappedSegments = value.maximumMappedSegments
        maximumOutputBytes = value.maximumOutputBytes
        maximumOutputLines = value.maximumOutputLines
    }

    var value: ThreeWayWebPageComparisonLimits {
        ThreeWayWebPageComparisonLimits(
            maximumSourceInputBytesPerSnapshot: maximumSourceInputBytesPerSnapshot,
            maximumNormalizedInputBytesPerSnapshot: maximumNormalizedInputBytesPerSnapshot,
            maximumTokenCountPerSnapshot: maximumTokenCountPerSnapshot,
            maximumAttributeCountPerSnapshot: maximumAttributeCountPerSnapshot,
            maximumTotalNormalizedInputBytes: maximumTotalNormalizedInputBytes,
            maximumInputLinesPerSnapshot: maximumInputLinesPerSnapshot,
            maximumMetadataEntriesPerSnapshot: maximumMetadataEntriesPerSnapshot,
            maximumMetadataBytes: maximumMetadataBytes,
            maximumWorkUnits: maximumWorkUnits,
            maximumResultRegions: maximumResultRegions,
            maximumMappedSegments: maximumMappedSegments,
            maximumOutputBytes: maximumOutputBytes,
            maximumOutputLines: maximumOutputLines
        )
    }
}

private struct ThreeWayWebPageComparisonOptionsWire: Codable {
    let diffAlgorithm: DiffAlgorithm
    let expectedContext: ThreeWayWebPageComparisonContextWire?
    let limits: ThreeWayWebPageComparisonLimitsWire

    init(_ value: ThreeWayWebPageComparisonOptions) {
        diffAlgorithm = value.diffAlgorithm
        expectedContext = value.expectedContext.map(ThreeWayWebPageComparisonContextWire.init)
        limits = ThreeWayWebPageComparisonLimitsWire(value.limits)
    }

    var value: ThreeWayWebPageComparisonOptions {
        ThreeWayWebPageComparisonOptions(
            diffAlgorithm: diffAlgorithm,
            expectedContext: expectedContext?.value,
            limits: limits.value
        )
    }
}

private struct WebpageComparisonPreferencesWire: Codable {
    let twoWay: WebPageComparisonOptionsWire
    let threeWay: ThreeWayWebPageComparisonOptionsWire
    let displayFilter: DisplayFilterWire

    init(_ value: WebpageComparisonPreferences) {
        twoWay = WebPageComparisonOptionsWire(value.twoWay)
        threeWay = ThreeWayWebPageComparisonOptionsWire(value.threeWay)
        displayFilter = DisplayFilterWire(value.displayFilter)
    }

    var value: WebpageComparisonPreferences {
        get throws {
            try WebpageComparisonPreferences(
                uncheckedTwoWay: twoWay.value,
                threeWay: threeWay.value,
                displayFilter: displayFilter.value
            )
        }
    }
}
