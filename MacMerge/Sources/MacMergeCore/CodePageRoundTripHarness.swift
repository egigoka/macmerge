import CoreFoundation
import Foundation

/// Executable round-trip harness over the real WinMerge encoding fixtures in
/// `Testing/Data/Codepages` and `Testing/Data/Unicode`.
///
/// Every discovered fixture runs through the production text pipeline:
/// load (`TextFileDocumentIO.load`), compare (`LineDiff`), edit, save
/// (`TextFileDocumentIO.save`), reload, and byte comparison. The byte stage
/// verifies that the saved file equals the source bytes with only the edited
/// line spliced in, and that reverting the edit restores the source bytes
/// exactly. Missing fixture families, unrecognized folders, nested entries, and
/// loose files are reported explicitly instead of being skipped silently.
///
/// Supported encodings without an on-disk WinMerge fixture (the Windows
/// CP1250-CP1255 pages) are exercised through synthesized fixtures whose bytes
/// come from Foundation's own converter. Synthesized results are reported
/// separately from the real WinMerge fixtures and never count toward them.
public enum CodePageRoundTripHarness {
    public typealias CancellationCheck = @Sendable () -> Bool
    public typealias Stage = CodePageFixtureMatrix.Stage

    public static let fixtureFamilies = ["Codepages", "Unicode"]
    public static let maximumFixtureBytes = 4 * 1024 * 1024
    public static let maximumFixtures = 256

    // MARK: Fixture catalog

    public struct FixtureFolderEncoding: Hashable, Sendable {
        public let encoding: TextFileEncoding
        public let hasByteOrderMark: Bool
        public let windowsCodePage: Int

        public init(encoding: TextFileEncoding, hasByteOrderMark: Bool, windowsCodePage: Int) {
            self.encoding = encoding
            self.hasByteOrderMark = hasByteOrderMark
            self.windowsCodePage = windowsCodePage
        }
    }

    /// WinMerge fixture folder names mapped to the encoding the folder contains.
    public static let fixtureFolderEncodings: [String: FixtureFolderEncoding] = [
        "UTF-8": FixtureFolderEncoding(encoding: .utf8, hasByteOrderMark: true, windowsCodePage: 65001),
        "UTF-8-NOBOM": FixtureFolderEncoding(encoding: .utf8, hasByteOrderMark: false, windowsCodePage: 65001),
        "UCS-2LE": FixtureFolderEncoding(encoding: .utf16LittleEndian, hasByteOrderMark: true, windowsCodePage: 1200),
        "UCS-2BE": FixtureFolderEncoding(encoding: .utf16BigEndian, hasByteOrderMark: true, windowsCodePage: 1201),
        "CP932": FixtureFolderEncoding(encoding: .shiftJIS, hasByteOrderMark: false, windowsCodePage: 932),
        "CP51932": FixtureFolderEncoding(encoding: .japaneseEUC, hasByteOrderMark: false, windowsCodePage: 51932),
        "CP50220": FixtureFolderEncoding(encoding: .iso2022JP, hasByteOrderMark: false, windowsCodePage: 50220),
        "CP1250": FixtureFolderEncoding(encoding: .windows1250, hasByteOrderMark: false, windowsCodePage: 1250),
        "CP1251": FixtureFolderEncoding(encoding: .windows1251, hasByteOrderMark: false, windowsCodePage: 1251),
        "CP1252": FixtureFolderEncoding(encoding: .windows1252, hasByteOrderMark: false, windowsCodePage: 1252),
        "CP1253": FixtureFolderEncoding(encoding: .windows1253, hasByteOrderMark: false, windowsCodePage: 1253),
        "CP1254": FixtureFolderEncoding(encoding: .windows1254, hasByteOrderMark: false, windowsCodePage: 1254),
        "CP1255": FixtureFolderEncoding(encoding: .windows1255, hasByteOrderMark: false, windowsCodePage: 1255)
    ]

    /// Every encoding the codec can load and save, in a stable order.
    public static let supportedEncodings: [TextFileEncoding] = [
        .utf8, .utf16LittleEndian, .utf16BigEndian, .shiftJIS, .japaneseEUC, .iso2022JP,
        .windows1250, .windows1251, .windows1252, .windows1253, .windows1254, .windows1255
    ]

    public struct Fixture: Hashable, Sendable {
        /// Path relative to the `Testing/Data` root, using `/` separators.
        public let relativePath: String
        public let url: URL
        public let folderName: String
        public let expected: FixtureFolderEncoding

        public init(relativePath: String, url: URL, folderName: String, expected: FixtureFolderEncoding) {
            self.relativePath = relativePath
            self.url = url
            self.folderName = folderName
            self.expected = expected
        }
    }

    public enum UnsupportedReason: Hashable, Sendable {
        /// The fixture folder name does not map to any known encoding, or the entry
        /// is not a regular file directly inside a fixture folder (a nested folder or
        /// a loose file at family level).
        case unrecognizedFixtureFolder
        /// A fixture family directory (`Codepages` or `Unicode`) is missing.
        case missingFixtureFamily
        /// The codec deliberately fails closed for this encoding.
        case failClosedByCodec
        /// Foundation exposes a converter, but `TextFileEncoding` does not wire it.
        case notWiredIntoTextFileCodec
        /// No Foundation converter exists for this Windows code page.
        case noFoundationConverter
    }

    public struct UnsupportedFixture: Hashable, Sendable {
        public let relativePath: String
        public let reason: UnsupportedReason

        public init(relativePath: String, reason: UnsupportedReason) {
            self.relativePath = relativePath
            self.reason = reason
        }
    }

    public struct UnsupportedCodePage: Hashable, Sendable {
        public let windowsCodePage: Int
        public let name: String
        public let reason: UnsupportedReason
        public let foundationConverterAvailable: Bool

        public init(windowsCodePage: Int, name: String, reason: UnsupportedReason, foundationConverterAvailable: Bool) {
            self.windowsCodePage = windowsCodePage
            self.name = name
            self.reason = reason
            self.foundationConverterAvailable = foundationConverterAvailable
        }
    }

    /// A representative, non-exhaustive list of code pages WinMerge can select but the
    /// macOS codec cannot round-trip. WinMerge's code-page dialogs
    /// (`Src/LoadSaveCodepageDlg.cpp`, `Src/PropCodepage.cpp`) enumerate every code
    /// page installed on the Windows host via `EnumSystemCodePages`, so the real
    /// unsupported set is larger than this list and depends on the host. Coverage
    /// reports must treat this as a known lower bound of the gap, never as the full gap.
    public static var knownUnsupportedCodePages: [UnsupportedCodePage] {
        let failClosed: [(Int, String)] = [
            (12000, "UTF-32 LE"),
            (12001, "UTF-32 BE")
        ]
        let unwired: [(Int, String)] = [
            (437, "OEM United States"),
            (850, "OEM Multilingual Latin 1"),
            (852, "OEM Latin 2"),
            (855, "OEM Cyrillic"),
            (857, "OEM Turkish"),
            (866, "OEM Russian"),
            (874, "Thai (Windows)"),
            (936, "Chinese Simplified (GBK)"),
            (949, "Korean (Unified Hangul)"),
            (950, "Chinese Traditional (Big5)"),
            (1256, "Arabic (Windows)"),
            (1257, "Baltic (Windows)"),
            (1258, "Vietnamese (Windows)"),
            (1361, "Korean (Johab)"),
            (10000, "Mac Roman"),
            (10001, "Mac Japanese"),
            (10029, "Mac Central European"),
            (20127, "US-ASCII"),
            (20866, "Cyrillic (KOI8-R)"),
            (21866, "Cyrillic (KOI8-U)"),
            (28591, "ISO 8859-1 Latin 1"),
            (28592, "ISO 8859-2 Central European"),
            (28595, "ISO 8859-5 Cyrillic"),
            (28597, "ISO 8859-7 Greek"),
            (28598, "ISO 8859-8 Hebrew"),
            (28605, "ISO 8859-15 Latin 9"),
            (50221, "Japanese (JIS-Allow 1 byte Kana)"),
            (50222, "Japanese (JIS-Allow 1 byte Kana - SO/SI)"),
            (51949, "Korean (EUC)"),
            (54936, "Chinese Simplified (GB18030)"),
            (65000, "UTF-7")
        ]
        return failClosed.map {
            UnsupportedCodePage(
                windowsCodePage: $0.0,
                name: $0.1,
                reason: .failClosedByCodec,
                foundationConverterAvailable: foundationConverterAvailable(windowsCodePage: $0.0)
            )
        }
            + unwired.map {
                let available = foundationConverterAvailable(windowsCodePage: $0.0)
                return UnsupportedCodePage(
                    windowsCodePage: $0.0,
                    name: $0.1,
                    reason: available ? .notWiredIntoTextFileCodec : .noFoundationConverter,
                    foundationConverterAvailable: available
                )
            }
    }

    public static func foundationConverterAvailable(windowsCodePage: Int) -> Bool {
        guard let codePage = UInt32(exactly: windowsCodePage) else { return false }
        let encoding = CFStringConvertWindowsCodepageToEncoding(codePage)
        guard encoding != kCFStringEncodingInvalidId else { return false }
        return CFStringIsEncodingAvailable(encoding)
    }

    public struct Catalog: Hashable, Sendable {
        public let dataRoot: URL
        public let fixtures: [Fixture]
        public let unsupportedFixtures: [UnsupportedFixture]

        public init(dataRoot: URL, fixtures: [Fixture], unsupportedFixtures: [UnsupportedFixture]) {
            self.dataRoot = dataRoot
            self.fixtures = fixtures
            self.unsupportedFixtures = unsupportedFixtures
        }

        /// Supported encodings that have no on-disk WinMerge fixture.
        public var encodingsWithoutFixture: [TextFileEncoding] {
            let covered = Set(fixtures.map(\.expected.encoding))
            return supportedEncodings.filter { !covered.contains($0) }
        }
    }

    public enum HarnessError: Error, Equatable, Sendable {
        case cancelled
        case dataRootNotFound
        case fixtureLimitExceeded(maximum: Int)
        case workingDirectoryUnavailable
    }

    /// Walks up from `start` until a directory containing `Testing/Data/Codepages` is found.
    public static func locateTestingData(startingAt start: URL) -> URL? {
        var directory = start.standardizedFileURL
        let fileManager = FileManager.default
        for _ in 0..<32 {
            let candidate = directory.appendingPathComponent("Testing/Data", isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(
                atPath: candidate.appendingPathComponent("Codepages").path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue {
                return candidate
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { return nil }
            directory = parent
        }
        return nil
    }

    /// Discovers fixtures under `dataRoot`. `maximumFixtures` bounds fixtures and
    /// unsupported entries combined, so an oversized tree fails closed either way.
    public static func discover(dataRoot: URL) throws -> Catalog {
        let fileManager = FileManager.default
        var fixtures: [Fixture] = []
        var unsupported: [UnsupportedFixture] = []
        var foundFamily = false

        func record(_ entry: UnsupportedFixture) throws {
            unsupported.append(entry)
            try checkLimit()
        }
        func checkLimit() throws {
            guard fixtures.count + unsupported.count <= maximumFixtures else {
                throw HarnessError.fixtureLimitExceeded(maximum: maximumFixtures)
            }
        }
        func isDirectory(_ url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        func isRegularFile(_ url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
        func entryPath(_ base: String, _ url: URL) -> String {
            "\(base)/\(url.lastPathComponent)" + (isDirectory(url) ? "/" : "")
        }

        for family in fixtureFamilies {
            let familyURL = dataRoot.appendingPathComponent(family, isDirectory: true)
            guard
                let entries = try? fileManager.contentsOfDirectory(
                    at: familyURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
            else {
                try record(UnsupportedFixture(relativePath: "\(family)/", reason: .missingFixtureFamily))
                continue
            }
            foundFamily = true
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard isDirectory(entry) else {
                    try record(UnsupportedFixture(relativePath: entryPath(family, entry), reason: .unrecognizedFixtureFolder))
                    continue
                }
                let folderName = entry.lastPathComponent
                let folderPath = "\(family)/\(folderName)"
                let children =
                    ((try? fileManager.contentsOfDirectory(
                        at: entry,
                        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
                let expected = fixtureFolderEncodings[folderName]
                if children.isEmpty, expected == nil {
                    try record(UnsupportedFixture(relativePath: "\(folderPath)/", reason: .unrecognizedFixtureFolder))
                }
                for child in children {
                    let relativePath = entryPath(folderPath, child)
                    guard let expected, isRegularFile(child) else {
                        try record(UnsupportedFixture(relativePath: relativePath, reason: .unrecognizedFixtureFolder))
                        continue
                    }
                    fixtures.append(Fixture(relativePath: relativePath, url: child, folderName: folderName, expected: expected))
                    try checkLimit()
                }
            }
        }
        guard foundFamily else { throw HarnessError.dataRootNotFound }
        return Catalog(dataRoot: dataRoot, fixtures: fixtures, unsupportedFixtures: unsupported)
    }

    // MARK: Results

    public enum AutomaticDetection: Equatable, Sendable {
        case detected(TextFileEncoding, hasByteOrderMark: Bool)
        case ambiguous([TextFileEncoding])
        case rejected(TextFileCodecError?)
    }

    public struct ByteDifference: Hashable, Sendable {
        public let expectedCount: Int
        public let actualCount: Int
        /// First differing byte offset, or the shorter length when one is a prefix of the other.
        public let firstDifferenceOffset: Int

        public init(expectedCount: Int, actualCount: Int, firstDifferenceOffset: Int) {
            self.expectedCount = expectedCount
            self.actualCount = actualCount
            self.firstDifferenceOffset = firstDifferenceOffset
        }
    }

    public enum Failure: Hashable, Sendable {
        case fixtureUnreadable
        case fixtureTooLarge(byteCount: Int)
        case workingCopyFailed
        case loadFailed(String)
        case encodingMismatch(expected: TextFileEncoding, actual: TextFileEncoding)
        case byteOrderMarkMismatch(expected: Bool, actual: Bool)
        case persistedBytesMismatch(ByteDifference)
        case compareFailed(String)
        case unexpectedDifferences(DiffCounts)
        case editNotRepresentable
        case spliceUnavailable
        case saveFailed(String)
        case savedBytesNotCanonical(ByteDifference)
        case reloadFailed(String)
        case reloadTextMismatch
        case reloadBytesMismatch(ByteDifference)
        /// Saved bytes match the codec's canonical encoding but not the source
        /// bytes with only the edit spliced in, so unedited bytes were rewritten.
        case canonicalizedUneditedBytes(ByteDifference)
        case revertSaveFailed(String)
        case revertBytesMismatch(ByteDifference)
        /// The never-edited left working copy could not be read back.
        case untouchedCopyUnreadable
        /// The never-edited left working copy no longer matches the source bytes.
        case untouchedCopyMismatch(ByteDifference)
    }

    public struct DiffCounts: Hashable, Sendable {
        public let modified: Int
        public let removed: Int
        public let added: Int

        public init(modified: Int, removed: Int, added: Int) {
            self.modified = modified
            self.removed = removed
            self.added = added
        }

        init(_ summary: DiffSummary) {
            self.init(modified: summary.modified, removed: summary.removed, added: summary.added)
        }
    }

    public enum StageStatus: Hashable, Sendable {
        case passed
        case failed(Failure)
        case notRun
    }

    public struct StageOutcome: Hashable, Sendable {
        public let stage: Stage
        public let status: StageStatus

        public init(stage: Stage, status: StageStatus) {
            self.stage = stage
            self.status = status
        }

        public var passed: Bool { status == .passed }
    }

    public struct FixtureResult: Equatable, Sendable {
        public let relativePath: String
        public let expected: FixtureFolderEncoding
        public let sourceByteCount: Int
        public let automaticDetection: AutomaticDetection?
        public let stages: [StageOutcome]
        public let savedByteCount: Int
        public let editMarker: String

        public init(
            relativePath: String,
            expected: FixtureFolderEncoding,
            sourceByteCount: Int,
            automaticDetection: AutomaticDetection?,
            stages: [StageOutcome],
            savedByteCount: Int,
            editMarker: String
        ) {
            self.relativePath = relativePath
            self.expected = expected
            self.sourceByteCount = sourceByteCount
            self.automaticDetection = automaticDetection
            self.stages = stages
            self.savedByteCount = savedByteCount
            self.editMarker = editMarker
        }

        public var isByteExactRoundTrip: Bool {
            stages.count == Stage.allCases.count && stages.allSatisfy(\.passed)
        }

        public var firstFailure: (stage: Stage, failure: Failure)? {
            for outcome in stages {
                if case .failed(let failure) = outcome.status { return (outcome.stage, failure) }
            }
            return nil
        }
    }

    public struct Report: Equatable, Sendable {
        public let catalog: Catalog
        /// Results for the real WinMerge fixtures discovered under `Testing/Data`.
        public let results: [FixtureResult]
        /// Results for harness-synthesized fixtures. These are not WinMerge fixtures
        /// and never count toward `allFixturesByteExact`.
        public let synthesizedResults: [FixtureResult]
        public let knownUnsupportedCodePages: [UnsupportedCodePage]

        public init(
            catalog: Catalog,
            results: [FixtureResult],
            synthesizedResults: [FixtureResult] = [],
            knownUnsupportedCodePages: [UnsupportedCodePage]
        ) {
            self.catalog = catalog
            self.results = results
            self.synthesizedResults = synthesizedResults
            self.knownUnsupportedCodePages = knownUnsupportedCodePages
        }

        public var passedCount: Int { results.filter(\.isByteExactRoundTrip).count }
        public var failedResults: [FixtureResult] { results.filter { !$0.isByteExactRoundTrip } }
        public var failedSynthesizedResults: [FixtureResult] { synthesizedResults.filter { !$0.isByteExactRoundTrip } }

        /// True only when real fixtures exist, every one round-trips byte-exactly, and no
        /// fixture family, folder, or entry was left unrecognized.
        public var allFixturesByteExact: Bool {
            !results.isEmpty && failedResults.isEmpty && catalog.unsupportedFixtures.isEmpty
        }

        /// True only when synthesized fixtures ran and every one round-trips byte-exactly.
        public var allSynthesizedByteExact: Bool {
            !synthesizedResults.isEmpty && failedSynthesizedResults.isEmpty
        }
    }

    // MARK: Execution

    /// Runs every discovered fixture. When `synthesizeMissingEncodings` is true, each
    /// supported encoding without a real fixture also runs through a synthesized fixture,
    /// reported separately in `Report.synthesizedResults`.
    public static func run(
        dataRoot: URL,
        workingDirectory: URL? = nil,
        synthesizeMissingEncodings: Bool = true,
        cancellationCheck: CancellationCheck = { Task.isCancelled }
    ) throws -> Report {
        try run(
            catalog: discover(dataRoot: dataRoot),
            workingDirectory: workingDirectory,
            synthesizeMissingEncodings: synthesizeMissingEncodings,
            cancellationCheck: cancellationCheck
        )
    }

    public static func run(
        catalog: Catalog,
        workingDirectory: URL? = nil,
        synthesizeMissingEncodings: Bool = true,
        cancellationCheck: CancellationCheck = { Task.isCancelled }
    ) throws -> Report {
        guard catalog.fixtures.count <= maximumFixtures else {
            throw HarnessError.fixtureLimitExceeded(maximum: maximumFixtures)
        }
        let fileManager = FileManager.default
        let parent = workingDirectory ?? fileManager.temporaryDirectory
        let root =
            parent
            .appendingPathComponent("MacMergeCodePageRoundTrip-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw HarnessError.workingDirectoryUnavailable
        }
        defer { try? fileManager.removeItem(at: root) }
        let resolvedRoot = root.resolvingSymlinksInPath()

        var results: [FixtureResult] = []
        results.reserveCapacity(catalog.fixtures.count)
        for (index, fixture) in catalog.fixtures.enumerated() {
            guard !cancellationCheck() else { throw HarnessError.cancelled }
            let fixtureDirectory = resolvedRoot.appendingPathComponent("\(index)", isDirectory: true)
            results.append(runFixture(fixture, in: fixtureDirectory))
        }
        var synthesizedResults: [FixtureResult] = []
        if synthesizeMissingEncodings {
            let encodings = catalog.encodingsWithoutFixture
            synthesizedResults.reserveCapacity(encodings.count)
            for (index, encoding) in encodings.enumerated() {
                guard !cancellationCheck() else { throw HarnessError.cancelled }
                let fixtureDirectory = resolvedRoot.appendingPathComponent("synthesized-\(index)", isDirectory: true)
                synthesizedResults.append(runSynthesizedFixture(for: encoding, in: fixtureDirectory))
            }
        }
        guard !cancellationCheck() else { throw HarnessError.cancelled }
        return Report(
            catalog: catalog,
            results: results,
            synthesizedResults: synthesizedResults,
            knownUnsupportedCodePages: knownUnsupportedCodePages
        )
    }

    // MARK: Synthesized fixtures

    /// Relative path prefix that marks a result as synthesized rather than a WinMerge fixture.
    public static let synthesizedPathPrefix = "synthesized"

    /// Fixture folder metadata for a synthesized fixture of `encoding`.
    public static func synthesizedFolderEncoding(for encoding: TextFileEncoding) -> FixtureFolderEncoding? {
        fixtureFolderEncodings.values
            .filter { $0.encoding == encoding }
            .min { ($0.hasByteOrderMark ? 1 : 0, $0.windowsCodePage) < ($1.hasByteOrderMark ? 1 : 0, $1.windowsCodePage) }
    }

    /// Source text for a synthesized fixture: mixed CRLF and LF terminators,
    /// high-byte characters from the code page, and an unterminated last line.
    /// The first line ends in non-ASCII text so the edit is spliced after a
    /// multibyte (or, for ISO-2022-JP, shift-state) prefix.
    public static func synthesizedFixtureText(for encoding: TextFileEncoding) -> String {
        let sample: String
        switch encoding {
        case .utf8, .utf16LittleEndian, .utf16BigEndian:
            sample = "caf\u{E9} \u{2713} \u{7DE8}\u{96C6}"
        case .shiftJIS, .japaneseEUC, .iso2022JP:
            sample = "\u{65E5}\u{672C}\u{8A9E}\u{30C6}\u{30AD}\u{30B9}\u{30C8}"
        case .windows1250:
            sample = "P\u{159}\u{ED}li\u{161} \u{17E}lu\u{165}ou\u{10D}k\u{FD} k\u{16F}\u{148} \u{150}\u{171}"
        case .windows1251:
            sample = "\u{421}\u{44A}\u{435}\u{448}\u{44C} \u{436}\u{435} \u{435}\u{449}\u{451} \u{404}\u{407}"
        case .windows1252:
            sample = "Fa\u{E7}ade na\u{EF}ve \u{20AC}5 \u{2014} \u{C6}\u{FE}"
        case .windows1253:
            sample = "\u{39E}\u{3B5}\u{3C3}\u{3BA}\u{3B5}\u{3C0}\u{3AC}\u{3B6}\u{3C9} \u{3C8}\u{3C5}\u{3C7}\u{3BF}\u{3C6}\u{3B8}\u{3CC}\u{3C1}\u{3B1}"
        case .windows1254:
            sample = "Pijamal\u{131} hasta \u{15F}o\u{11F}uk \u{E7}ay\u{131} \u{130}\u{11E}\u{15E}"
        case .windows1255:
            sample = "\u{5D3}\u{5D2} \u{5E1}\u{5E7}\u{5E8}\u{5DF} \u{5E9}\u{5D8} \u{20AA}"
        }
        return "// MacMerge synthesized \(encoding.displayName) fixture: \(sample)\r\n"
            + "\(sample)\n"
            + "line three: \(sample)\r\n"
            + "\n"
            + "last line without terminator: \(sample)"
    }

    /// Bytes for a synthesized fixture, produced by Foundation's converter for the
    /// fixture's Windows code page. This bypasses `TextFileCodec.encode`, but the
    /// CP125x and Shift_JIS converters are the same Foundation tables the codec
    /// uses, so tests pin the expected bytes against Windows code page tables.
    public static func synthesizedFixtureBytes(for encoding: TextFileEncoding) -> Data? {
        guard let folder = synthesizedFolderEncoding(for: encoding) else { return nil }
        let text = synthesizedFixtureText(for: encoding)
        let stringEncoding: String.Encoding
        switch encoding {
        case .utf8: stringEncoding = .utf8
        case .utf16LittleEndian: stringEncoding = .utf16LittleEndian
        case .utf16BigEndian: stringEncoding = .utf16BigEndian
        // CFStringConvertWindowsCodepageToEncoding has no mapping for 50220.
        case .iso2022JP: stringEncoding = .iso2022JP
        default:
            guard let codePage = UInt32(exactly: folder.windowsCodePage) else { return nil }
            let cfEncoding = CFStringConvertWindowsCodepageToEncoding(codePage)
            guard cfEncoding != kCFStringEncodingInvalidId, CFStringIsEncodingAvailable(cfEncoding) else { return nil }
            stringEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        }
        guard let body = text.data(using: stringEncoding, allowLossyConversion: false) else { return nil }
        guard folder.hasByteOrderMark else { return body }
        let bom: Data
        switch encoding {
        case .utf8: bom = Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndian: bom = Data([0xFF, 0xFE])
        case .utf16BigEndian: bom = Data([0xFE, 0xFF])
        default: return nil
        }
        return bom + body
    }

    /// Writes a synthesized fixture into `directory` and runs it through every stage.
    /// The result's `relativePath` starts with `synthesizedPathPrefix`.
    public static func runSynthesizedFixture(for encoding: TextFileEncoding, in directory: URL) -> FixtureResult {
        let folder =
            synthesizedFolderEncoding(for: encoding)
            ?? FixtureFolderEncoding(encoding: encoding, hasByteOrderMark: false, windowsCodePage: 0)
        let folderName = "CP\(folder.windowsCodePage)"
        let fileName = "synthesized.txt"
        let relativePath = "\(synthesizedPathPrefix)/\(folderName)/\(fileName)"
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        let sourceURL = sourceDirectory.appendingPathComponent(fileName)
        var recorder = StageRecorder()
        guard let bytes = synthesizedFixtureBytes(for: encoding) else {
            recorder.fail(.load, .fixtureUnreadable)
            return FixtureResult(
                relativePath: relativePath,
                expected: folder,
                sourceByteCount: 0,
                automaticDetection: nil,
                stages: recorder.outcomes,
                savedByteCount: 0,
                editMarker: editMarker(for: encoding)
            )
        }
        do {
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            try bytes.write(to: sourceURL, options: .withoutOverwriting)
        } catch {
            recorder.fail(.load, .workingCopyFailed)
            return FixtureResult(
                relativePath: relativePath,
                expected: folder,
                sourceByteCount: bytes.count,
                automaticDetection: nil,
                stages: recorder.outcomes,
                savedByteCount: 0,
                editMarker: editMarker(for: encoding)
            )
        }
        let fixture = Fixture(relativePath: relativePath, url: sourceURL, folderName: folderName, expected: folder)
        return runFixture(fixture, in: directory.appendingPathComponent("work", isDirectory: true))
    }

    /// Text inserted as a new line. Includes non-ASCII characters the encoding can represent.
    public static func editMarker(for encoding: TextFileEncoding) -> String {
        switch encoding {
        case .utf8, .utf16LittleEndian, .utf16BigEndian:
            "// MacMerge round-trip edit: caf\u{E9} \u{2713} \u{7DE8}\u{96C6} \u{1F600}"
        case .shiftJIS, .japaneseEUC, .iso2022JP:
            "// MacMerge round-trip edit: \u{7DE8}\u{96C6}\u{30C6}\u{30B9}\u{30C8}"
        case .windows1250:
            "// MacMerge round-trip edit: \u{17E}lu\u{165}ou\u{10D}k\u{FD}"
        case .windows1251:
            "// MacMerge round-trip edit: \u{43F}\u{440}\u{430}\u{432}\u{43A}\u{430}"
        case .windows1252:
            "// MacMerge round-trip edit: caf\u{E9} \u{20AC}"
        case .windows1253:
            "// MacMerge round-trip edit: \u{3B4}\u{3BF}\u{3BA}\u{3B9}\u{3BC}\u{3AE}"
        case .windows1254:
            "// MacMerge round-trip edit: d\u{FC}zenleme \u{11F}\u{131}\u{15F}"
        case .windows1255:
            "// MacMerge round-trip edit: \u{5E2}\u{5E8}\u{5D9}\u{5DB}\u{5D4}"
        }
    }

    /// Points where `FaultInjection` may tamper with the working copies.
    enum FaultPoint: Sendable {
        /// After the edited right copy is saved, before it is reloaded.
        case afterSave
        /// After the reverted right copy is saved, before the final byte checks.
        case afterRevertSave
    }

    /// Test seam that receives the left and right working-copy URLs at each
    /// `FaultPoint`, so tests can prove every later check actually fails.
    typealias FaultInjection = (_ point: FaultPoint, _ left: URL, _ right: URL) -> Void

    /// Runs one fixture through every stage. `byteLimit`, `markerOverride`,
    /// `saveOverride` (replaces only the edited save), and `faultInjection` exist
    /// for tests; production callers use the defaults.
    static func runFixture(
        _ fixture: Fixture,
        in directory: URL,
        byteLimit: Int = maximumFixtureBytes,
        markerOverride: String? = nil,
        saveOverride: ((TextFileDocument) throws -> TextFileDocument)? = nil,
        faultInjection: FaultInjection? = nil
    ) -> FixtureResult {
        var recorder = StageRecorder()
        let encoding = fixture.expected.encoding
        let marker = markerOverride ?? editMarker(for: encoding)
        var sourceByteCount = 0
        var detection: AutomaticDetection?
        var savedByteCount = 0

        func finish() -> FixtureResult {
            FixtureResult(
                relativePath: fixture.relativePath,
                expected: fixture.expected,
                sourceByteCount: sourceByteCount,
                automaticDetection: detection,
                stages: recorder.outcomes,
                savedByteCount: savedByteCount,
                editMarker: marker
            )
        }

        // Load.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fixture.url.path),
            let size = (attributes[.size] as? NSNumber)?.intValue
        else {
            recorder.fail(.load, .fixtureUnreadable)
            return finish()
        }
        guard size <= byteLimit else {
            sourceByteCount = size
            recorder.fail(.load, .fixtureTooLarge(byteCount: size))
            return finish()
        }
        guard let source = try? Data(contentsOf: fixture.url, options: .uncached),
            source.count <= byteLimit
        else {
            recorder.fail(.load, .fixtureUnreadable)
            return finish()
        }
        sourceByteCount = source.count
        detection = automaticDetection(of: source)

        let fileName = fixture.url.lastPathComponent
        let leftURL = directory.appendingPathComponent("left-\(fileName)")
        let rightURL = directory.appendingPathComponent("right-\(fileName)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try source.write(to: leftURL, options: .withoutOverwriting)
            try source.write(to: rightURL, options: .withoutOverwriting)
        } catch {
            recorder.fail(.load, .workingCopyFailed)
            return finish()
        }

        let left: TextFileDocument
        var right: TextFileDocument
        do {
            left = try TextFileDocumentIO.load(from: leftURL, assuming: encoding)
            right = try TextFileDocumentIO.load(from: rightURL, assuming: encoding)
        } catch {
            recorder.fail(.load, .loadFailed(summary(of: error)))
            return finish()
        }
        if let failure = verifyLoaded(left, expected: fixture.expected, bytes: source)
            ?? verifyLoaded(right, expected: fixture.expected, bytes: source)
        {
            recorder.fail(.load, failure)
            return finish()
        }
        recorder.pass(.load)

        // Compare: identical copies must produce no differences.
        do {
            let counts = DiffCounts(DiffSummary(rows: try LineDiff.compare(left: left.text, right: right.text)))
            guard counts == DiffCounts(modified: 0, removed: 0, added: 0) else {
                recorder.fail(.compare, .unexpectedDifferences(counts))
                return finish()
            }
        } catch {
            recorder.fail(.compare, .compareFailed(summary(of: error)))
            return finish()
        }
        recorder.pass(.compare)

        // Edit: insert one marker line after the first line.
        let edit = insertLine(marker, afterFirstLineOf: right.persistedText)
        guard
            let insertedBytes = try? TextFileCodec.encode(
                DecodedTextFile(text: edit.insertedText, encoding: encoding, hasByteOrderMark: false)
            ),
            (try? TextFileCodec.decode(insertedBytes, assuming: encoding))?.text.unicodeScalars
                .elementsEqual(edit.insertedText.unicodeScalars) == true
        else {
            recorder.fail(.edit, .editNotRepresentable)
            return finish()
        }
        let spliceOffset: Int
        if edit.appendsAtEnd {
            spliceOffset = source.count
        } else if let offset = byteOffset(ofTextPrefix: edit.prefix, in: source, fixture: fixture.expected) {
            spliceOffset = offset
        } else {
            recorder.fail(.edit, .spliceUnavailable)
            return finish()
        }
        var expectedSaved = Data(source.prefix(spliceOffset))
        expectedSaved.append(insertedBytes)
        expectedSaved.append(source.dropFirst(spliceOffset))
        right.text = edit.text
        if let failure = verifySingleInsertion(left: left.text, right: right.text) {
            recorder.fail(.edit, failure)
            return finish()
        }
        recorder.pass(.edit)

        // Save.
        let saved: TextFileDocument
        do {
            saved = try saveOverride?(right) ?? TextFileDocumentIO.save(right).document
        } catch {
            recorder.fail(.save, .saveFailed(summary(of: error)))
            return finish()
        }
        savedByteCount = saved.persistedData.count
        // A save that reproduces the source with only the edit spliced in passes even
        // if it differs from the codec's canonical encoding; any other output must at
        // least be canonical so the byte stage can classify what was rewritten.
        let canonical = try? TextFileCodec.encode(
            DecodedTextFile(text: edit.text, encoding: encoding, hasByteOrderMark: fixture.expected.hasByteOrderMark)
        )
        guard saved.persistedData == expectedSaved || canonical == saved.persistedData else {
            recorder.fail(.save, .savedBytesNotCanonical(difference(expected: canonical ?? Data(), actual: saved.persistedData)))
            return finish()
        }
        recorder.pass(.save)
        faultInjection?(.afterSave, leftURL, rightURL)

        // Reload from disk and recompare.
        let reloaded: TextFileDocument
        let diskBytes: Data
        do {
            reloaded = try TextFileDocumentIO.load(from: rightURL, assuming: encoding)
            diskBytes = try Data(contentsOf: rightURL, options: .uncached)
        } catch {
            recorder.fail(.reload, .reloadFailed(summary(of: error)))
            return finish()
        }
        guard reloaded.text.unicodeScalars.elementsEqual(edit.text.unicodeScalars) else {
            recorder.fail(.reload, .reloadTextMismatch)
            return finish()
        }
        guard reloaded.hasByteOrderMark == fixture.expected.hasByteOrderMark else {
            recorder.fail(.reload, .byteOrderMarkMismatch(expected: fixture.expected.hasByteOrderMark, actual: reloaded.hasByteOrderMark))
            return finish()
        }
        guard diskBytes == saved.persistedData, reloaded.persistedData == diskBytes else {
            recorder.fail(.reload, .reloadBytesMismatch(difference(expected: saved.persistedData, actual: diskBytes)))
            return finish()
        }
        if let failure = verifySingleInsertion(left: left.text, right: reloaded.text) {
            recorder.fail(.reload, failure)
            return finish()
        }
        recorder.pass(.reload)

        // Byte comparison: only the edit may change bytes, and reverting restores the source.
        // The save stage guarantees diskBytes is either the splice or the canonical
        // encoding, so any mismatch here means unedited bytes were canonicalized.
        guard diskBytes == expectedSaved else {
            recorder.fail(.byteComparison, .canonicalizedUneditedBytes(difference(expected: expectedSaved, actual: diskBytes)))
            return finish()
        }
        var reverting = reloaded
        reverting.text = left.persistedText
        do {
            _ = try TextFileDocumentIO.save(reverting)
        } catch {
            recorder.fail(.byteComparison, .revertSaveFailed(summary(of: error)))
            return finish()
        }
        faultInjection?(.afterRevertSave, leftURL, rightURL)
        guard let revertedBytes = try? Data(contentsOf: rightURL, options: .uncached) else {
            recorder.fail(.byteComparison, .revertSaveFailed("reverted file unreadable"))
            return finish()
        }
        guard revertedBytes == source else {
            recorder.fail(.byteComparison, .revertBytesMismatch(difference(expected: source, actual: revertedBytes)))
            return finish()
        }
        guard let leftBytes = try? Data(contentsOf: leftURL, options: .uncached) else {
            recorder.fail(.byteComparison, .untouchedCopyUnreadable)
            return finish()
        }
        guard leftBytes == source else {
            recorder.fail(.byteComparison, .untouchedCopyMismatch(difference(expected: source, actual: leftBytes)))
            return finish()
        }
        recorder.pass(.byteComparison)
        return finish()
    }

    // MARK: Helpers

    struct StageRecorder {
        private(set) var outcomes: [StageOutcome] = Stage.allCases.map { StageOutcome(stage: $0, status: .notRun) }

        mutating func pass(_ stage: Stage) {
            outcomes[stage.rawValue] = StageOutcome(stage: stage, status: .passed)
        }

        mutating func fail(_ stage: Stage, _ failure: Failure) {
            outcomes[stage.rawValue] = StageOutcome(stage: stage, status: .failed(failure))
        }
    }

    struct LineInsertion {
        /// Text before the insertion point.
        let prefix: String
        /// Full edited text.
        let text: String
        /// Exact text spliced in at the insertion point.
        let insertedText: String
        /// True when the insertion is appended after the last byte of the source.
        let appendsAtEnd: Bool
    }

    /// Line ending used when the source has no terminator to reuse. Matches WinMerge,
    /// which picks DOS (CRLF) style for a file without any EOL
    /// (`GetTextFileStyle` in `Src/DiffTextBuffer.cpp`).
    static let defaultLineEnding = "\r\n"

    /// Inserts `line` after the first line terminator, reusing that terminator. When the
    /// text has no terminator (a single unterminated line or an empty file), appends the
    /// default line ending plus `line` at the end instead.
    static func insertLine(_ line: String, afterFirstLineOf text: String) -> LineInsertion {
        let scalars = text.unicodeScalars
        guard let newline = scalars.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else {
            let inserted = text.isEmpty ? line : defaultLineEnding + line
            return LineInsertion(prefix: text, text: text + inserted, insertedText: inserted, appendsAtEnd: true)
        }
        var end = scalars.index(after: newline)
        var lineEnding = String(scalars[newline])
        if scalars[newline] == "\r", end < scalars.endIndex, scalars[end] == "\n" {
            end = scalars.index(after: end)
            lineEnding = "\r\n"
        }
        let prefix = String(String.UnicodeScalarView(scalars[..<end]))
        let suffix = String(String.UnicodeScalarView(scalars[end...]))
        return LineInsertion(
            prefix: prefix,
            text: prefix + line + lineEnding + suffix,
            insertedText: line + lineEnding,
            appendsAtEnd: false
        )
    }

    /// Byte length of `prefix` within `source`, verified by re-encoding.
    static func byteOffset(ofTextPrefix prefix: String, in source: Data, fixture: FixtureFolderEncoding) -> Int? {
        guard
            let encoded = try? TextFileCodec.encode(
                DecodedTextFile(text: prefix, encoding: fixture.encoding, hasByteOrderMark: fixture.hasByteOrderMark)
            ), source.starts(with: encoded)
        else { return nil }
        return encoded.count
    }

    static func verifyLoaded(_ document: TextFileDocument, expected: FixtureFolderEncoding, bytes: Data) -> Failure? {
        guard document.encoding == expected.encoding else {
            return .encodingMismatch(expected: expected.encoding, actual: document.encoding)
        }
        guard document.hasByteOrderMark == expected.hasByteOrderMark else {
            return .byteOrderMarkMismatch(expected: expected.hasByteOrderMark, actual: document.hasByteOrderMark)
        }
        guard document.persistedData == bytes else {
            return .persistedBytesMismatch(difference(expected: bytes, actual: document.persistedData))
        }
        return nil
    }

    static func verifySingleInsertion(left: String, right: String) -> Failure? {
        do {
            let counts = DiffCounts(DiffSummary(rows: try LineDiff.compare(left: left, right: right)))
            guard counts == DiffCounts(modified: 0, removed: 0, added: 1) else {
                return .unexpectedDifferences(counts)
            }
            return nil
        } catch {
            return .compareFailed(summary(of: error))
        }
    }

    static func automaticDetection(of data: Data) -> AutomaticDetection {
        do {
            let decoded = try TextFileCodec.decode(data)
            return .detected(decoded.encoding, hasByteOrderMark: decoded.hasByteOrderMark)
        } catch let error as TextFileCodecError {
            if case .ambiguousTextEncoding(let encodings) = error { return .ambiguous(encodings) }
            return .rejected(error)
        } catch {
            return .rejected(nil)
        }
    }

    static func difference(expected: Data, actual: Data) -> ByteDifference {
        var offset = 0
        var expectedIndex = expected.startIndex
        var actualIndex = actual.startIndex
        while expectedIndex < expected.endIndex, actualIndex < actual.endIndex,
            expected[expectedIndex] == actual[actualIndex]
        {
            offset += 1
            expectedIndex = expected.index(after: expectedIndex)
            actualIndex = actual.index(after: actualIndex)
        }
        return ByteDifference(expectedCount: expected.count, actualCount: actual.count, firstDifferenceOffset: offset)
    }

    static func summary(of error: any Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: type(of: error))
    }
}
