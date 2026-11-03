import Foundation

/// Lane-2 wiring: adapts WinMerge two-way string-diff ranges into
/// `IntraLineDifferenceRangePair` plan inputs.
///
/// The owners stay untouched: `WinMergeStringDiffs` aligns, `IntraLineDifferenceWorkflow`
/// plans. This adapter only validates and maps, failing closed (`.inconsistentPlan`) on
/// malformed ranges, so a future WinMerge-binary comparison can diff plan output against
/// this mapping without either side trusting the other.
public enum IntraLineWiring: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    /// Maps two-way `Difference` entries to workflow range pairs, preserving order.
    ///
    /// - Parameters:
    ///   - differences: Two-way diffs (`paneCount == 2`); side 0 is source, side 1 is comparison.
    ///   - source: Source line text, or `nil` for a ghost line (yields a `nil` source range).
    ///   - comparison: Comparison line text, or `nil` for a ghost line.
    ///   - expectedGeneration: Generation the caller planned against.
    ///   - actualGeneration: Generation the diffs were computed from; a mismatch throws
    ///     `.staleComparison` before any range is trusted.
    ///   - cancellationCheck: Caller-owned cancellation token, passed through untouched:
    ///     invoked once before mapping and once per difference. A throw aborts the mapping.
    public static func rangePairs(
        differences: [WinMergeStringDiffs.Difference],
        source: String?,
        comparison: String?,
        expectedGeneration: UInt64,
        actualGeneration: UInt64,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> [IntraLineDifferenceRangePair] {
        do {
            guard expectedGeneration == actualGeneration else {
                throw IntraLineDifferenceWorkflowError.staleComparison
            }
            try cancellationCheck()
            let sourceBoundaries = try source.map {
                try graphemeUTF16Boundaries(of: $0, cancellationCheck: cancellationCheck)
            }
            let comparisonBoundaries = try comparison.map {
                try graphemeUTF16Boundaries(of: $0, cancellationCheck: cancellationCheck)
            }
            var pairs: [IntraLineDifferenceRangePair] = []
            pairs.reserveCapacity(differences.count)
            var previousSourceEnd = 0
            var previousComparisonEnd = 0
            for (ordinal, difference) in differences.enumerated() {
                try cancellationCheck()
                guard difference.paneCount == 2,
                    difference.begin.count == 3,
                    difference.end.count == 3
                else {
                    throw IntraLineDifferenceWorkflowError.inconsistentPlan
                }
                let sourceRange = try validatedRange(
                    side: 0,
                    text: source,
                    boundaries: sourceBoundaries,
                    previousEnd: &previousSourceEnd,
                    in: difference
                )
                let comparisonRange = try validatedRange(
                    side: 1,
                    text: comparison,
                    boundaries: comparisonBoundaries,
                    previousEnd: &previousComparisonEnd,
                    in: difference
                )
                let kind: IntraLineDifferenceChangeKind
                if sourceRange == nil || sourceRange?.length == 0 {
                    kind = .insert
                } else if comparisonRange == nil || comparisonRange?.length == 0 {
                    kind = .delete
                } else {
                    kind = .replace
                }
                pairs.append(
                    IntraLineDifferenceRangePair(
                        ordinal: ordinal,
                        kind: kind,
                        sourceUTF16Range: sourceRange,
                        comparisonUTF16Range: comparisonRange
                    )
                )
            }
            return pairs
        } catch is CancellationError {
            throw IntraLineDifferenceWorkflowError.cancelled
        }
    }

    /// Validates one WinMerge side (inclusive `begin...end`) as a grapheme-safe `NSRange`.
    /// An empty side is `end == begin - 1` and yields a zero-length insertion point; anything
    /// shorter is malformed. Deliberately stricter than `Difference/utf16Range(side:)`, which
    /// clamps negative spans with `max(0, ...)`: here those fail closed.
    private static func validatedRange(
        side: Int,
        text: String?,
        boundaries: Set<Int>?,
        previousEnd: inout Int,
        in difference: WinMergeStringDiffs.Difference
    ) throws -> NSRange? {
        guard let text, let boundaries else { return nil }
        let begin = difference.begin[side]
        let end = difference.end[side]
        guard begin >= 0 else {
            throw IntraLineDifferenceWorkflowError.inconsistentPlan
        }
        let (emptyEnd, emptyOverflow) = begin.subtractingReportingOverflow(1)
        guard !emptyOverflow, end >= emptyEnd else {
            throw IntraLineDifferenceWorkflowError.inconsistentPlan
        }
        let (delta, deltaOverflow) = end.subtractingReportingOverflow(begin)
        guard !deltaOverflow else {
            throw IntraLineDifferenceWorkflowError.inconsistentPlan
        }
        let (length, lengthOverflow) = delta.addingReportingOverflow(1)
        guard !lengthOverflow else {
            throw IntraLineDifferenceWorkflowError.inconsistentPlan
        }
        let (rangeEnd, overflow) = begin.addingReportingOverflow(length)
        guard !overflow,
            rangeEnd <= text.utf16.count,
            boundaries.contains(begin),
            boundaries.contains(rangeEnd),
            begin >= previousEnd
        else {
            throw IntraLineDifferenceWorkflowError.inconsistentPlan
        }
        previousEnd = rangeEnd
        return NSRange(location: begin, length: length)
    }

    /// UTF-16 offsets at extended-grapheme boundaries (0 and the length included), the only
    /// offsets a native text view may highlight without splitting a visible character.
    /// Ranges from WinMerge's ICU-63 tables that land inside a newer Swift grapheme fail
    /// closed at the call site; that divergence is documented on `WinMergeStringDiffs`.
    private static func graphemeUTF16Boundaries(
        of text: String,
        cancellationCheck: CancellationCheck
    ) throws -> Set<Int> {
        var boundaries: Set<Int> = [0]
        var offset = 0
        var sinceCheck = 0
        for character in text {
            offset += String(character).utf16.count
            boundaries.insert(offset)
            sinceCheck += 1
            if sinceCheck >= 1024 {
                sinceCheck = 0
                try cancellationCheck()
            }
        }
        return boundaries
    }
}
