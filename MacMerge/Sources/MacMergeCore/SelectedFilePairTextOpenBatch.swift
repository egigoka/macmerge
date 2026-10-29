import Foundation

/// Plans which selected folder-result rows can be opened as two-pane text comparisons.
///
/// This is a macOS multi-pair extension inspired by WinMerge `CDirView::OpenSelection`; it does
/// not reproduce that function's rules. Deliberate deviations, pinned by tests:
/// - WinMerge refuses more than three selected rows (`GetSelectedItems`) and, for two both-sided
///   rows, refuses to open them (`AreItemsOpenable`). Here every selected both-sided file row
///   becomes its own comparison, bounded by `Limits.maximumSelectedResults` and
///   `Limits.maximumOpenedPairs`.
/// - Exactly one left-only file plus one right-only file is combined into a single comparison,
///   as WinMerge does for `SELECTIONTYPE_NORMAL`. WinMerge also combines a one-sided row with a
///   both-sided row (`GetOpenTwoItems`); that combination is not implemented, so the one-sided
///   row is rejected with `missingSide`.
/// - WinMerge opens binary and one-sided items in other viewers. This batch only feeds the text
///   pipeline, so folder rows, missing sides, type mismatches, and content that the text pipeline
///   cannot decode (NUL bytes without a UTF-16 byte-order mark, UTF-32) are rejected with an
///   explicit reason instead of being opened.
///
/// Content is sniffed through no-follow readers opened beneath the root descriptors that the
/// `DirectoryResults` pinned when it was created, so a root or descendant swapped for a symbolic
/// link after the scan is reported as unavailable. The pinning covers only the sniff: the
/// resulting `Pair` carries path URLs, and the app's open step re-resolves those paths.
///
/// `SelectedFilePairOpenWorkflow` is the separate, I/O-free planning contract for an atomic
/// stage-then-publish executor with authority bindings; it has no content sniffing and no
/// executor in the app yet. This batch reuses its `Side` but keeps its own `Limits`, because
/// those limits bound snapshot planning work units rather than files touched and pairs opened.
public enum SelectedFilePairTextOpenBatch {
    public typealias CancellationCheck = @Sendable () -> Bool

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumSelectedResults = 100_000
        public static let hardMaximumOpenedPairs = 256
        public static let hardMaximumSniffByteCount = 1_024 * 1_024
        public static let `default` = Limits()

        /// Selections larger than this are refused outright before any file is touched.
        public let maximumSelectedResults: Int
        /// Accepted pairs beyond this count are reported as `openLimitReached` and never sniffed.
        public let maximumOpenedPairs: Int
        /// Number of leading bytes inspected on each side to classify content.
        public let sniffByteCount: Int

        public init(
            maximumSelectedResults: Int = 10_000,
            maximumOpenedPairs: Int = 32,
            sniffByteCount: Int = 8 * 1_024
        ) {
            self.maximumSelectedResults = Self.clamp(
                maximumSelectedResults,
                to: Self.hardMaximumSelectedResults
            )
            self.maximumOpenedPairs = Self.clamp(maximumOpenedPairs, to: Self.hardMaximumOpenedPairs)
            self.sniffByteCount = Self.clamp(sniffByteCount, to: Self.hardMaximumSniffByteCount)
        }

        private static func clamp(_ value: Int, to maximum: Int) -> Int {
            min(max(value, 1), maximum)
        }
    }

    public typealias Side = SelectedFilePairOpenWorkflow.Side

    public enum ContentClassification: Hashable, Sendable {
        case text
        /// Contains NUL bytes and no UTF-16 byte-order mark, so WinMerge would treat it as binary.
        case binary
        /// UTF-32 text, which the macOS text pipeline does not decode yet.
        case unsupportedEncoding
    }

    public enum RejectionReason: Hashable, Sendable {
        /// The row has no entry on this side and was not paired with a one-sided row on the other.
        case missingSide(Side)
        /// The row is a folder; opening folders belongs to the folder comparison workflow.
        case folder
        /// The row is a symbolic link or special file on at least one side.
        case notRegularFile
        /// Left and right entries have different kinds.
        case typeMismatch
        /// The row is selected but hidden by the active filter.
        case notVisible
        /// The row no longer exists in the results.
        case noLongerInResults
        /// The pinned file could not be opened or read; it may have moved or been replaced.
        case unavailable
        case nonText(Side)
        case unsupportedEncoding(Side)
        /// More pairs were acceptable than `Limits.maximumOpenedPairs` allows.
        case openLimitReached
    }

    public struct Pair: Hashable, Sendable {
        /// Result rows that produced the pair: one row, or the two combined one-sided rows.
        public let resultIDs: [DirectoryResult.ID]
        public let leftRelativePath: String
        public let rightRelativePath: String
        public let leftURL: URL
        public let rightURL: URL
        public let status: DirectoryComparisonStatus?

        public var displayName: String {
            leftRelativePath == rightRelativePath
                ? leftRelativePath
                : "\(leftRelativePath) ↔ \(rightRelativePath)"
        }
    }

    public struct Rejection: Hashable, Sendable {
        public let resultID: DirectoryResult.ID
        public let relativePath: String
        public let reason: RejectionReason
    }

    public struct Plan: Hashable, Sendable {
        /// Pairs in visible (filtered and sorted) folder-result order.
        public let pairs: [Pair]
        /// Rejections in visible order, followed by selected rows that are not visible. Every
        /// selected row that does not contribute to a pair has exactly one rejection.
        public let rejections: [Rejection]
        public let selectedCount: Int

        public var isEmpty: Bool { pairs.isEmpty }
    }

    public enum Error: Swift.Error, Hashable, LocalizedError, Sendable {
        case emptySelection
        case selectionTooLarge(count: Int, maximum: Int)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .emptySelection:
                "Select one or more file pairs to open."
            case .selectionTooLarge(let count, let maximum):
                "\(count) items are selected. Select at most \(maximum) items to open."
            case .cancelled:
                "Opening the selected file pairs was canceled."
            }
        }
    }

    /// Builds the open plan for `selectedIDs` (defaults to the results' own selection).
    /// Performs bounded file I/O; call it off the main thread.
    public static func plan(
        results: DirectoryResults,
        selectedIDs: Set<DirectoryResult.ID>? = nil,
        limits: Limits = .default,
        isCancelled: CancellationCheck = { false }
    ) throws(Error) -> Plan {
        let selection = selectedIDs ?? results.selectedIDs
        guard !selection.isEmpty else { throw .emptySelection }
        guard selection.count <= limits.maximumSelectedResults else {
            throw .selectionTooLarge(count: selection.count, maximum: limits.maximumSelectedResults)
        }

        let visible = results.visibleResults
        try checkCancellation(isCancelled)
        var visibleSelected: [DirectoryResult] = []
        visibleSelected.reserveCapacity(min(selection.count, visible.count))
        var visibleSelectedIDs = Set<DirectoryResult.ID>()
        for result in visible where selection.contains(result.id) {
            visibleSelected.append(result)
            visibleSelectedIDs.insert(result.id)
        }

        var pairs: [Pair] = []
        var rejections: [Rejection] = []

        if let combined = combinedOneSidedPair(visibleSelected, selectionCount: selection.count) {
            try checkCancellation(isCancelled)
            appendCandidate(
                combined,
                resultIDs: visibleSelected.map(\.id),
                status: nil,
                rejectionTargets: visibleSelected.map { ($0.id, $0.relativePath) },
                in: results,
                limits: limits,
                pairs: &pairs,
                rejections: &rejections
            )
        } else {
            for result in visibleSelected {
                try checkCancellation(isCancelled)
                if let reason = structuralRejection(for: result) {
                    rejections.append(rejection(result.id, result.relativePath, reason))
                    continue
                }
                appendCandidate(
                    result,
                    resultIDs: [result.id],
                    status: result.status,
                    rejectionTargets: [(result.id, result.relativePath)],
                    in: results,
                    limits: limits,
                    pairs: &pairs,
                    rejections: &rejections
                )
            }
        }

        let hiddenSelected = selection.subtracting(visibleSelectedIDs).sorted {
            $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8)
        }
        if !hiddenSelected.isEmpty {
            try checkCancellation(isCancelled)
            var knownIDs = Set<DirectoryResult.ID>(minimumCapacity: results.results.count)
            for result in results.results {
                knownIDs.insert(result.id)
            }
            for (offset, id) in hiddenSelected.enumerated() {
                if offset % cancellationCheckInterval == 0 {
                    try checkCancellation(isCancelled)
                }
                let reason: RejectionReason =
                    knownIDs.contains(id) ? .notVisible : .noLongerInResults
                rejections.append(rejection(id, id.relativePath, reason))
            }
        }

        return Plan(pairs: pairs, rejections: rejections, selectedCount: selection.count)
    }

    /// Classifies leading file bytes the way WinMerge decides between text and binary panes.
    public static func classify(prefix data: Data) -> ContentClassification {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return .unsupportedEncoding
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            return .text
        }
        return bytes.contains(0) ? .binary : .text
    }

    // MARK: - Private

    private static let cancellationCheckInterval = 256

    private static func checkCancellation(_ isCancelled: CancellationCheck) throws(Error) {
        if isCancelled() { throw .cancelled }
    }

    private static func rejection(
        _ id: DirectoryResult.ID,
        _ path: String,
        _ reason: RejectionReason
    ) -> Rejection {
        Rejection(resultID: id, relativePath: path, reason: reason)
    }

    /// WinMerge combines exactly one left-only and one right-only item into one comparison.
    private static func combinedOneSidedPair(
        _ selected: [DirectoryResult],
        selectionCount: Int
    ) -> DirectoryResult? {
        guard selectionCount == 2, selected.count == 2 else { return nil }
        let leftOnly = selected.first { $0.left != nil && $0.right == nil }
        let rightOnly = selected.first { $0.left == nil && $0.right != nil }
        guard let left = leftOnly?.left, let right = rightOnly?.right,
            left.kind == .file, right.kind == .file
        else {
            return nil
        }
        return DirectoryResult(left: left, right: right, status: .pending)
    }

    private static func structuralRejection(for result: DirectoryResult) -> RejectionReason? {
        switch (result.left, result.right) {
        case (nil, _):
            return .missingSide(.left)
        case (_, nil):
            return .missingSide(.right)
        case (let left?, let right?):
            guard left.kind == right.kind else { return .typeMismatch }
            switch left.kind {
            case .file:
                return nil
            case .directory:
                return .folder
            case .symbolicLink, .other:
                return .notRegularFile
            }
        }
    }

    private static func appendCandidate(
        _ result: DirectoryResult,
        resultIDs: [DirectoryResult.ID],
        status: DirectoryComparisonStatus?,
        rejectionTargets: [(id: DirectoryResult.ID, relativePath: String)],
        in results: DirectoryResults,
        limits: Limits,
        pairs: inout [Pair],
        rejections: inout [Rejection]
    ) {
        // A combined pair rejects every row it came from, so each selected row is accounted for.
        func reject(_ reason: RejectionReason) {
            for target in rejectionTargets {
                rejections.append(rejection(target.id, target.relativePath, reason))
            }
        }
        guard let leftPath = result.left?.relativePath, let rightPath = result.right?.relativePath
        else {
            reject(.unavailable)
            return
        }
        guard pairs.count < limits.maximumOpenedPairs else {
            reject(.openLimitReached)
            return
        }
        if let reason = inspectContent(of: result, in: results, limits: limits) {
            reject(reason)
            return
        }
        pairs.append(
            Pair(
                resultIDs: resultIDs,
                leftRelativePath: leftPath,
                rightRelativePath: rightPath,
                leftURL: fileURL(root: results.leftRoot, relativePath: leftPath),
                rightURL: fileURL(root: results.rightRoot, relativePath: rightPath),
                status: status
            )
        )
    }

    private static func inspectContent(
        of result: DirectoryResult,
        in results: DirectoryResults,
        limits: Limits
    ) -> RejectionReason? {
        guard let filePair = results.pinnedOpenableFilePair(for: result) else {
            return .unavailable
        }
        let prefixes: (Data, Data)
        do {
            prefixes = try filePair.withReaders { left, right in
                (
                    try left.read(upToCount: limits.sniffByteCount),
                    try right.read(upToCount: limits.sniffByteCount)
                )
            }
        } catch {
            return .unavailable
        }
        for (side, prefix) in [(Side.left, prefixes.0), (Side.right, prefixes.1)] {
            switch classify(prefix: prefix) {
            case .text:
                continue
            case .binary:
                return .nonText(side)
            case .unsupportedEncoding:
                return .unsupportedEncoding(side)
            }
        }
        return nil
    }

    private static func fileURL(root: URL, relativePath: String) -> URL {
        relativePath.split(separator: "/", omittingEmptySubsequences: true).reduce(root) {
            $0.appendingPathComponent(String($1), isDirectory: false)
        }
    }
}

extension SelectedFilePairTextOpenBatch.RejectionReason {
    /// Short, user-facing explanation suitable for an alert line.
    public var summary: String {
        switch self {
        case .missingSide(.left):
            "no left file"
        case .missingSide(.right):
            "no right file"
        case .folder:
            "folder"
        case .notRegularFile:
            "not a regular file"
        case .typeMismatch:
            "file and folder mismatch"
        case .notVisible:
            "hidden by the current filter"
        case .noLongerInResults:
            "no longer in the results"
        case .unavailable:
            "could not be read; refresh the comparison"
        case .nonText(.left):
            "left file is binary"
        case .nonText(.right):
            "right file is binary"
        case .unsupportedEncoding(.left):
            "left file uses an unsupported encoding"
        case .unsupportedEncoding(.right):
            "right file uses an unsupported encoding"
        case .openLimitReached:
            "too many files selected"
        }
    }
}
