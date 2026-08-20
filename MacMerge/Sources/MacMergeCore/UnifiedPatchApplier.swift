import Foundation

public enum UnifiedPatchInputKind: String, Equatable, Sendable {
    case patch
    case original
}

public enum UnifiedPatchPathSide: String, Equatable, Sendable {
    case old
    case new
}

public enum UnifiedPatchPathRejection: String, Equatable, Sendable {
    case empty
    case absolute
    case traversal
    case emptyComponent
    case unsupportedSeparator
    case controlCharacter
    case insufficientComponents
}

public enum UnifiedPatchSyntaxRejection: String, Equatable, Sendable {
    case missingOldHeader
    case missingNewHeader
    case malformedPath
    case malformedHunkHeader
    case invalidHunkRange
    case overlappingHunks
    case unexpectedHunkLine
    case hunkLineCountMismatch
    case orphanNoFinalNewlineMarker
    case duplicateNoFinalNewlineMarker
    case fileHasNoHunks
    case nulByte
}

public enum UnifiedPatchHunkRejection: String, Equatable, Sendable {
    case sourceRangeOutOfBounds
    case overlapsPreviousHunk
    case contentMismatch
    case invalidNoFinalNewlinePlacement
    case nonemptyCreationSource
    case nonemptyDeletionResult
}

public enum UnifiedPatchError: Error, LocalizedError, Equatable, Sendable {
    case invalidUTF8
    case invalidLimit(name: String, value: Int)
    case invalidStripCount(Int)
    case invalidFuzzPolicy(maximumOffset: Int, maximumContextLinesToIgnore: Int)
    case inputTooLarge(kind: UnifiedPatchInputKind, maximumBytes: Int)
    case tooManyLines(kind: UnifiedPatchInputKind, maximumLines: Int)
    case lineTooLong(kind: UnifiedPatchInputKind, line: Int, maximumBytes: Int)
    case tooManyFiles(maximumFiles: Int)
    case tooManyHunks(maximumHunks: Int)
    case hunkTooLarge(fileIndex: Int, hunkIndex: Int, maximumLines: Int)
    case outputTooLarge(maximumBytes: Int)
    case tooManyOutputLines(maximumLines: Int)
    case workLimitExceeded(maximumWork: Int)
    case noFilePatches
    case fileIndexOutOfRange(index: Int, fileCount: Int)
    case invalidPath(
        fileIndex: Int,
        side: UnifiedPatchPathSide,
        reason: UnifiedPatchPathRejection
    )
    case malformedPatch(line: Int, reason: UnifiedPatchSyntaxRejection)
    case hunkRejected(
        fileIndex: Int,
        hunkIndex: Int,
        reason: UnifiedPatchHunkRejection
    )

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "Unified patch is not valid UTF-8."
        case .invalidLimit(let name, let value):
            "Unified patch limit \(name) must not be negative: \(value)."
        case .invalidStripCount(let value):
            "Unified patch strip count must not be negative: \(value)."
        case .invalidFuzzPolicy(let offset, let context):
            "Unified patch fuzz values must not be negative: offset \(offset), context \(context)."
        case .inputTooLarge(let kind, let maximumBytes):
            "Unified patch \(kind.rawValue) input exceeds the \(maximumBytes)-byte limit."
        case .tooManyLines(let kind, let maximumLines):
            "Unified patch \(kind.rawValue) input exceeds the \(maximumLines)-line limit."
        case .lineTooLong(let kind, let line, let maximumBytes):
            "Unified patch \(kind.rawValue) line \(line) exceeds the \(maximumBytes)-byte limit."
        case .tooManyFiles(let maximumFiles):
            "Unified patch exceeds the \(maximumFiles)-file limit."
        case .tooManyHunks(let maximumHunks):
            "Unified patch exceeds the \(maximumHunks)-hunk limit."
        case .hunkTooLarge(let fileIndex, let hunkIndex, let maximumLines):
            "Unified patch file \(fileIndex), hunk \(hunkIndex) exceeds the \(maximumLines)-line limit."
        case .outputTooLarge(let maximumBytes):
            "Patched output exceeds the \(maximumBytes)-byte limit."
        case .tooManyOutputLines(let maximumLines):
            "Patched output exceeds the \(maximumLines)-line limit."
        case .workLimitExceeded(let maximumWork):
            "Unified patch application exceeds the \(maximumWork)-unit work limit."
        case .noFilePatches:
            "Input contains no unified file patches."
        case .fileIndexOutOfRange(let index, let fileCount):
            "Unified patch file index \(index) is outside the \(fileCount)-file patch."
        case .invalidPath(let fileIndex, let side, let reason):
            "Unified patch file \(fileIndex) has an invalid \(side.rawValue) path (\(reason.rawValue))."
        case .malformedPatch(let line, let reason):
            "Unified patch is malformed at line \(line) (\(reason.rawValue))."
        case .hunkRejected(let fileIndex, let hunkIndex, let reason):
            "Unified patch file \(fileIndex), hunk \(hunkIndex) was rejected (\(reason.rawValue))."
        }
    }
}

public struct UnifiedPatchLimits: Equatable, Sendable {
    public var maximumPatchBytes: Int
    public var maximumOriginalBytes: Int
    public var maximumLineBytes: Int
    public var maximumPatchLines: Int
    public var maximumOriginalLines: Int
    public var maximumFiles: Int
    public var maximumHunks: Int
    public var maximumHunkLines: Int
    public var maximumOutputBytes: Int
    public var maximumOutputLines: Int
    public var maximumWork: Int

    public init(
        maximumPatchBytes: Int = 64 * 1024 * 1024,
        maximumOriginalBytes: Int = 64 * 1024 * 1024,
        maximumLineBytes: Int = 8 * 1024 * 1024,
        maximumPatchLines: Int = 1024 * 1024,
        maximumOriginalLines: Int = 1024 * 1024,
        maximumFiles: Int = 64 * 1024,
        maximumHunks: Int = 1024 * 1024,
        maximumHunkLines: Int = 1024 * 1024,
        maximumOutputBytes: Int = 128 * 1024 * 1024,
        maximumOutputLines: Int = 2 * 1024 * 1024,
        maximumWork: Int = 512 * 1024 * 1024
    ) {
        self.maximumPatchBytes = maximumPatchBytes
        self.maximumOriginalBytes = maximumOriginalBytes
        self.maximumLineBytes = maximumLineBytes
        self.maximumPatchLines = maximumPatchLines
        self.maximumOriginalLines = maximumOriginalLines
        self.maximumFiles = maximumFiles
        self.maximumHunks = maximumHunks
        self.maximumHunkLines = maximumHunkLines
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumOutputLines = maximumOutputLines
        self.maximumWork = maximumWork
    }
}

public struct UnifiedPatchFuzzPolicy: Equatable, Sendable {
    public var maximumOffset: Int
    public var maximumContextLinesToIgnore: Int

    public static let exact = UnifiedPatchFuzzPolicy()

    public init(maximumOffset: Int = 0, maximumContextLinesToIgnore: Int = 0) {
        self.maximumOffset = maximumOffset
        self.maximumContextLinesToIgnore = maximumContextLinesToIgnore
    }
}

public struct UnifiedPatchApplyOptions: Equatable, Sendable {
    public var reverse: Bool
    public var stripCount: Int
    public var fuzzPolicy: UnifiedPatchFuzzPolicy
    public var limits: UnifiedPatchLimits

    public init(
        reverse: Bool = false,
        stripCount: Int = 0,
        fuzzPolicy: UnifiedPatchFuzzPolicy = .exact,
        limits: UnifiedPatchLimits = UnifiedPatchLimits()
    ) {
        self.reverse = reverse
        self.stripCount = stripCount
        self.fuzzPolicy = fuzzPolicy
        self.limits = limits
    }
}

public struct UnifiedPatchFileMetadata: Equatable, Sendable {
    public let index: Int
    public let oldPath: String?
    public let newPath: String?
    public let hunkCount: Int

    public init(index: Int, oldPath: String?, newPath: String?, hunkCount: Int) {
        self.index = index
        self.oldPath = oldPath
        self.newPath = newPath
        self.hunkCount = hunkCount
    }
}

public struct UnifiedPatchAppliedHunk: Equatable, Sendable {
    public let index: Int
    public let sourceRange: Range<Int>
    public let offset: Int
    public let ignoredContextLines: Int

    public init(
        index: Int,
        sourceRange: Range<Int>,
        offset: Int,
        ignoredContextLines: Int
    ) {
        self.index = index
        self.sourceRange = sourceRange
        self.offset = offset
        self.ignoredContextLines = ignoredContextLines
    }
}

public struct UnifiedPatchApplicationResult: Equatable, Sendable {
    public let text: String
    public let file: UnifiedPatchFileMetadata
    public let sourcePath: String?
    public let destinationPath: String?
    public let reverse: Bool
    public let appliedHunks: [UnifiedPatchAppliedHunk]
    public let outputLineCount: Int

    public init(
        text: String,
        file: UnifiedPatchFileMetadata,
        sourcePath: String?,
        destinationPath: String?,
        reverse: Bool,
        appliedHunks: [UnifiedPatchAppliedHunk],
        outputLineCount: Int
    ) {
        self.text = text
        self.file = file
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.reverse = reverse
        self.appliedHunks = appliedHunks
        self.outputLineCount = outputLineCount
    }
}

public struct UnifiedPatch: Equatable, Sendable {
    public let files: [UnifiedPatchFileMetadata]
    public let stripCount: Int
    fileprivate let parsedFiles: [ParsedUnifiedPatchFile]

    fileprivate init(files: [ParsedUnifiedPatchFile], stripCount: Int) {
        parsedFiles = files
        self.files = files.map(\.metadata)
        self.stripCount = stripCount
    }
}

public enum UnifiedPatchApplier: Sendable {
    public static func parse(
        _ patch: Data,
        stripCount: Int = 0,
        limits: UnifiedPatchLimits = UnifiedPatchLimits()
    ) throws -> UnifiedPatch {
        try validate(limits: limits, stripCount: stripCount)
        guard patch.count <= limits.maximumPatchBytes else {
            throw UnifiedPatchError.inputTooLarge(
                kind: .patch,
                maximumBytes: limits.maximumPatchBytes
            )
        }
        guard let text = String(data: patch, encoding: .utf8) else {
            throw UnifiedPatchError.invalidUTF8
        }
        return try parseValidated(text, stripCount: stripCount, limits: limits)
    }

    public static func parse(
        _ patch: String,
        stripCount: Int = 0,
        limits: UnifiedPatchLimits = UnifiedPatchLimits()
    ) throws -> UnifiedPatch {
        try validate(limits: limits, stripCount: stripCount)
        return try parseValidated(patch, stripCount: stripCount, limits: limits)
    }

    public static func apply(
        patch: Data,
        to original: String,
        fileIndex: Int = 0,
        options: UnifiedPatchApplyOptions = UnifiedPatchApplyOptions()
    ) throws -> UnifiedPatchApplicationResult {
        try validate(options: options)
        let parsed = try parse(
            patch,
            stripCount: options.stripCount,
            limits: options.limits
        )
        return try applyValidated(
            parsed,
            to: original,
            fileIndex: fileIndex,
            reverse: options.reverse,
            fuzzPolicy: options.fuzzPolicy,
            limits: options.limits
        )
    }

    public static func apply(
        patch: String,
        to original: String,
        fileIndex: Int = 0,
        options: UnifiedPatchApplyOptions = UnifiedPatchApplyOptions()
    ) throws -> UnifiedPatchApplicationResult {
        try validate(options: options)
        let parsed = try parse(
            patch,
            stripCount: options.stripCount,
            limits: options.limits
        )
        return try applyValidated(
            parsed,
            to: original,
            fileIndex: fileIndex,
            reverse: options.reverse,
            fuzzPolicy: options.fuzzPolicy,
            limits: options.limits
        )
    }

    public static func apply(
        _ patch: UnifiedPatch,
        to original: String,
        fileIndex: Int = 0,
        reverse: Bool = false,
        fuzzPolicy: UnifiedPatchFuzzPolicy = .exact,
        limits: UnifiedPatchLimits = UnifiedPatchLimits()
    ) throws -> UnifiedPatchApplicationResult {
        try validate(limits: limits, stripCount: patch.stripCount)
        try validate(fuzzPolicy: fuzzPolicy)
        return try applyValidated(
            patch,
            to: original,
            fileIndex: fileIndex,
            reverse: reverse,
            fuzzPolicy: fuzzPolicy,
            limits: limits
        )
    }

    private static func parseValidated(
        _ patch: String,
        stripCount: Int,
        limits: UnifiedPatchLimits
    ) throws -> UnifiedPatch {
        try Task.checkCancellation()
        guard patch.utf8.count <= limits.maximumPatchBytes else {
            throw UnifiedPatchError.inputTooLarge(
                kind: .patch,
                maximumBytes: limits.maximumPatchBytes
            )
        }
        var bytes = Array(patch.utf8)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes.removeFirst(3)
        }
        if bytes.contains(0) {
            throw UnifiedPatchError.malformedPatch(line: 1, reason: .nulByte)
        }
        var work = WorkBudget(maximum: limits.maximumWork)
        let lines = try splitLines(
            bytes,
            kind: .patch,
            maximumLines: limits.maximumPatchLines,
            maximumLineBytes: limits.maximumLineBytes,
            work: &work
        )
        var parser = UnifiedPatchParser(
            lines: lines,
            stripCount: stripCount,
            limits: limits,
            work: work
        )
        let files = try parser.parse()
        guard !files.isEmpty else { throw UnifiedPatchError.noFilePatches }
        try Task.checkCancellation()
        return UnifiedPatch(files: files, stripCount: stripCount)
    }

    private static func applyValidated(
        _ patch: UnifiedPatch,
        to original: String,
        fileIndex: Int,
        reverse: Bool,
        fuzzPolicy: UnifiedPatchFuzzPolicy,
        limits: UnifiedPatchLimits
    ) throws -> UnifiedPatchApplicationResult {
        try Task.checkCancellation()
        guard patch.parsedFiles.indices.contains(fileIndex) else {
            throw UnifiedPatchError.fileIndexOutOfRange(
                index: fileIndex,
                fileCount: patch.parsedFiles.count
            )
        }
        guard original.utf8.count <= limits.maximumOriginalBytes else {
            throw UnifiedPatchError.inputTooLarge(
                kind: .original,
                maximumBytes: limits.maximumOriginalBytes
            )
        }
        let file = patch.parsedFiles[fileIndex]
        guard file.hunks.count <= limits.maximumHunks else {
            throw UnifiedPatchError.tooManyHunks(maximumHunks: limits.maximumHunks)
        }
        var work = WorkBudget(maximum: limits.maximumWork)
        let originalLines = try splitLines(
            Array(original.utf8),
            kind: .original,
            maximumLines: limits.maximumOriginalLines,
            maximumLineBytes: limits.maximumLineBytes,
            work: &work
        )
        let sourcePath = reverse ? file.metadata.newPath : file.metadata.oldPath
        let destinationPath = reverse ? file.metadata.oldPath : file.metadata.newPath
        if sourcePath == nil, !originalLines.isEmpty {
            throw UnifiedPatchError.hunkRejected(
                fileIndex: fileIndex,
                hunkIndex: 0,
                reason: .nonemptyCreationSource
            )
        }

        var output = PatchOutput(limits: limits, work: work)
        var sourceCursor = 0
        var appliedHunks: [UnifiedPatchAppliedHunk] = []
        appliedHunks.reserveCapacity(file.hunks.count)

        for (hunkIndex, hunk) in file.hunks.enumerated() {
            if hunkIndex.isMultiple(of: 256) { try Task.checkCancellation() }
            guard hunk.lines.count <= limits.maximumHunkLines else {
                throw UnifiedPatchError.hunkTooLarge(
                    fileIndex: fileIndex,
                    hunkIndex: hunkIndex,
                    maximumLines: limits.maximumHunkLines
                )
            }
            let sourceRange = reverse ? hunk.newRange : hunk.oldRange
            let match = try findMatch(
                hunk: hunk,
                sourceRange: sourceRange,
                original: originalLines,
                minimumIndex: sourceCursor,
                reverse: reverse,
                fuzzPolicy: fuzzPolicy,
                fileIndex: fileIndex,
                hunkIndex: hunkIndex,
                work: &output.work
            )
            if match.index < sourceCursor {
                throw UnifiedPatchError.hunkRejected(
                    fileIndex: fileIndex,
                    hunkIndex: hunkIndex,
                    reason: .overlapsPreviousHunk
                )
            }
            for index in sourceCursor..<match.index {
                try output.append(originalLines[index], fileIndex: fileIndex, hunkIndex: hunkIndex)
            }

            var matchedCursor = match.index
            for line in hunk.lines {
                switch (line.kind, reverse) {
                case (.context, _):
                    try output.append(
                        originalLines[matchedCursor],
                        fileIndex: fileIndex,
                        hunkIndex: hunkIndex
                    )
                    matchedCursor += 1
                case (.deletion, false), (.addition, true):
                    matchedCursor += 1
                case (.addition, false), (.deletion, true):
                    try output.append(line.record, fileIndex: fileIndex, hunkIndex: hunkIndex)
                }
            }
            sourceCursor = matchedCursor
            let end = try checkedAdd(
                match.index,
                sourceRange.count,
                line: hunk.headerLine,
                reason: .invalidHunkRange
            )
            appliedHunks.append(
                UnifiedPatchAppliedHunk(
                    index: hunkIndex,
                    sourceRange: match.index..<end,
                    offset: match.index - sourceRange.start,
                    ignoredContextLines: match.fuzz
                ))
        }
        for index in sourceCursor..<originalLines.count {
            try output.append(
                originalLines[index],
                fileIndex: fileIndex,
                hunkIndex: max(0, file.hunks.count - 1)
            )
        }
        if destinationPath == nil, output.lineCount != 0 {
            throw UnifiedPatchError.hunkRejected(
                fileIndex: fileIndex,
                hunkIndex: max(0, file.hunks.count - 1),
                reason: .nonemptyDeletionResult
            )
        }
        try Task.checkCancellation()
        return UnifiedPatchApplicationResult(
            text: output.text,
            file: file.metadata,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            reverse: reverse,
            appliedHunks: appliedHunks,
            outputLineCount: output.lineCount
        )
    }

    private static func findMatch(
        hunk: ParsedUnifiedPatchHunk,
        sourceRange: ParsedPatchRange,
        original: [PatchRecord],
        minimumIndex: Int,
        reverse: Bool,
        fuzzPolicy: UnifiedPatchFuzzPolicy,
        fileIndex: Int,
        hunkIndex: Int,
        work: inout WorkBudget
    ) throws -> (index: Int, fuzz: Int) {
        guard sourceRange.count <= original.count else {
            throw UnifiedPatchError.hunkRejected(
                fileIndex: fileIndex,
                hunkIndex: hunkIndex,
                reason: .sourceRangeOutOfBounds
            )
        }
        let maximumStart = original.count - sourceRange.count
        let expected = sourceRange.start
        let lowerByOffset = expected > fuzzPolicy.maximumOffset
            ? expected - fuzzPolicy.maximumOffset
            : 0
        let (upperSum, overflow) = expected.addingReportingOverflow(fuzzPolicy.maximumOffset)
        let upperByOffset = overflow ? Int.max : upperSum
        let lower = max(minimumIndex, lowerByOffset)
        let upper = min(maximumStart, upperByOffset)
        guard lower <= upper else {
            throw UnifiedPatchError.hunkRejected(
                fileIndex: fileIndex,
                hunkIndex: hunkIndex,
                reason: minimumIndex > maximumStart
                    ? .overlapsPreviousHunk
                    : .sourceRangeOutOfBounds
            )
        }

        let leadingContext = hunk.lines.prefix { $0.kind == .context }.count
        let trailingContext = hunk.lines.reversed().prefix { $0.kind == .context }.count
        let maximumFuzz = min(
            fuzzPolicy.maximumContextLinesToIgnore,
            max(leadingContext, trailingContext)
        )
        for fuzz in 0...maximumFuzz {
            var iterator = CandidateIterator(lower: lower, upper: upper, expected: expected)
            while let candidate = iterator.next() {
                try work.consume(1)
                if try matches(
                    hunk: hunk,
                    at: candidate,
                    original: original,
                    reverse: reverse,
                    ignoredLeadingContext: min(fuzz, leadingContext),
                    ignoredTrailingContext: min(fuzz, trailingContext),
                    work: &work
                ) {
                    return (candidate, fuzz)
                }
            }
        }
        throw UnifiedPatchError.hunkRejected(
            fileIndex: fileIndex,
            hunkIndex: hunkIndex,
            reason: .contentMismatch
        )
    }

    private static func matches(
        hunk: ParsedUnifiedPatchHunk,
        at candidate: Int,
        original: [PatchRecord],
        reverse: Bool,
        ignoredLeadingContext: Int,
        ignoredTrailingContext: Int,
        work: inout WorkBudget
    ) throws -> Bool {
        var sourceIndex = candidate
        let trailingStart = hunk.lines.count - ignoredTrailingContext
        for (lineIndex, line) in hunk.lines.enumerated() {
            let isSourceLine = line.kind == .context
                || (reverse ? line.kind == .addition : line.kind == .deletion)
            guard isSourceLine else { continue }
            let ignoreContext = line.kind == .context
                && (lineIndex < ignoredLeadingContext || lineIndex >= trailingStart)
            if !ignoreContext,
               !(try recordsEqual(line.record, original[sourceIndex], work: &work)) {
                return false
            }
            sourceIndex += 1
        }
        return true
    }

    private static func recordsEqual(
        _ left: PatchRecord,
        _ right: PatchRecord,
        work: inout WorkBudget
    ) throws -> Bool {
        let comparisonBytes = max(left.bytes.count, right.bytes.count) + 1
        try work.consume(comparisonBytes)
        guard left.hasLineFeed == right.hasLineFeed, left.bytes.count == right.bytes.count else {
            return false
        }
        for index in left.bytes.indices {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if left.bytes[index] != right.bytes[index] { return false }
        }
        return true
    }

    private static func validate(options: UnifiedPatchApplyOptions) throws {
        try validate(limits: options.limits, stripCount: options.stripCount)
        try validate(fuzzPolicy: options.fuzzPolicy)
    }

    private static func validate(fuzzPolicy: UnifiedPatchFuzzPolicy) throws {
        guard fuzzPolicy.maximumOffset >= 0,
              fuzzPolicy.maximumContextLinesToIgnore >= 0 else {
            throw UnifiedPatchError.invalidFuzzPolicy(
                maximumOffset: fuzzPolicy.maximumOffset,
                maximumContextLinesToIgnore: fuzzPolicy.maximumContextLinesToIgnore
            )
        }
    }

    private static func validate(limits: UnifiedPatchLimits, stripCount: Int) throws {
        guard stripCount >= 0 else { throw UnifiedPatchError.invalidStripCount(stripCount) }
        let values = [
            ("maximumPatchBytes", limits.maximumPatchBytes),
            ("maximumOriginalBytes", limits.maximumOriginalBytes),
            ("maximumLineBytes", limits.maximumLineBytes),
            ("maximumPatchLines", limits.maximumPatchLines),
            ("maximumOriginalLines", limits.maximumOriginalLines),
            ("maximumFiles", limits.maximumFiles),
            ("maximumHunks", limits.maximumHunks),
            ("maximumHunkLines", limits.maximumHunkLines),
            ("maximumOutputBytes", limits.maximumOutputBytes),
            ("maximumOutputLines", limits.maximumOutputLines),
            ("maximumWork", limits.maximumWork)
        ]
        if let invalid = values.first(where: { $0.1 < 0 }) {
            throw UnifiedPatchError.invalidLimit(name: invalid.0, value: invalid.1)
        }
    }

    private static func splitLines(
        _ bytes: [UInt8],
        kind: UnifiedPatchInputKind,
        maximumLines: Int,
        maximumLineBytes: Int,
        work: inout WorkBudget
    ) throws -> [PatchRecord] {
        try work.consume(bytes.count)
        var lines: [PatchRecord] = []
        lines.reserveCapacity(min(maximumLines, 4_096))
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0A {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            try appendSplitLine(
                Array(bytes[start..<index]),
                hasLineFeed: true,
                kind: kind,
                maximumLines: maximumLines,
                maximumLineBytes: maximumLineBytes,
                to: &lines
            )
            start = index + 1
        }
        if start < bytes.count {
            try appendSplitLine(
                Array(bytes[start...]),
                hasLineFeed: false,
                kind: kind,
                maximumLines: maximumLines,
                maximumLineBytes: maximumLineBytes,
                to: &lines
            )
        }
        return lines
    }

    private static func appendSplitLine(
        _ bytes: [UInt8],
        hasLineFeed: Bool,
        kind: UnifiedPatchInputKind,
        maximumLines: Int,
        maximumLineBytes: Int,
        to lines: inout [PatchRecord]
    ) throws {
        guard lines.count < maximumLines else {
            throw UnifiedPatchError.tooManyLines(kind: kind, maximumLines: maximumLines)
        }
        guard bytes.count <= maximumLineBytes else {
            throw UnifiedPatchError.lineTooLong(
                kind: kind,
                line: lines.count + 1,
                maximumBytes: maximumLineBytes
            )
        }
        lines.append(PatchRecord(bytes: bytes, hasLineFeed: hasLineFeed))
    }

    fileprivate static func checkedAdd(
        _ left: Int,
        _ right: Int,
        line: Int,
        reason: UnifiedPatchSyntaxRejection
    ) throws -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        guard !overflow else {
            throw UnifiedPatchError.malformedPatch(line: line, reason: reason)
        }
        return result
    }
}

private struct UnifiedPatchParser {
    let lines: [PatchRecord]
    let stripCount: Int
    let limits: UnifiedPatchLimits
    var work: WorkBudget
    private var lineIndex = 0
    private var totalHunks = 0

    init(
        lines: [PatchRecord],
        stripCount: Int,
        limits: UnifiedPatchLimits,
        work: WorkBudget
    ) {
        self.lines = lines
        self.stripCount = stripCount
        self.limits = limits
        self.work = work
    }

    mutating func parse() throws -> [ParsedUnifiedPatchFile] {
        var files: [ParsedUnifiedPatchFile] = []
        while lineIndex < lines.count {
            if lineIndex.isMultiple(of: 256) { try Task.checkCancellation() }
            let line = controlBytes(lines[lineIndex].bytes)
            if hasPrefix(line, ascii: "@@ ") || isNoFinalNewlineMarker(line) {
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 1,
                    reason: hasPrefix(line, ascii: "@@ ")
                        ? .missingOldHeader
                        : .orphanNoFinalNewlineMarker
                )
            }
            guard hasPrefix(line, ascii: "--- ") else {
                lineIndex += 1
                continue
            }
            guard lineIndex + 1 < lines.count else {
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 1,
                    reason: .missingNewHeader
                )
            }
            let newHeader = controlBytes(lines[lineIndex + 1].bytes)
            guard hasPrefix(newHeader, ascii: "+++ ") else {
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 2,
                    reason: .missingNewHeader
                )
            }
            guard files.count < limits.maximumFiles else {
                throw UnifiedPatchError.tooManyFiles(maximumFiles: limits.maximumFiles)
            }
            let fileIndex = files.count
            let oldPath = try parsePath(
                Array(line.dropFirst(4)),
                fileIndex: fileIndex,
                side: .old
            )
            let newPath = try parsePath(
                Array(newHeader.dropFirst(4)),
                fileIndex: fileIndex,
                side: .new
            )
            guard oldPath != nil || newPath != nil else {
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 1,
                    reason: .malformedPath
                )
            }
            lineIndex += 2
            var hunks: [ParsedUnifiedPatchHunk] = []
            var oldEnd = 0
            var newEnd = 0
            while lineIndex < lines.count,
                  hasPrefix(controlBytes(lines[lineIndex].bytes), ascii: "@@ ") {
                guard totalHunks < limits.maximumHunks else {
                    throw UnifiedPatchError.tooManyHunks(maximumHunks: limits.maximumHunks)
                }
                let hunk = try parseHunk(fileIndex: fileIndex, hunkIndex: hunks.count)
                guard hunk.oldRange.start >= oldEnd, hunk.newRange.start >= newEnd else {
                    throw UnifiedPatchError.malformedPatch(
                        line: hunk.headerLine,
                        reason: .overlappingHunks
                    )
                }
                oldEnd = try UnifiedPatchApplier.checkedAdd(
                    hunk.oldRange.start,
                    hunk.oldRange.count,
                    line: hunk.headerLine,
                    reason: .invalidHunkRange
                )
                newEnd = try UnifiedPatchApplier.checkedAdd(
                    hunk.newRange.start,
                    hunk.newRange.count,
                    line: hunk.headerLine,
                    reason: .invalidHunkRange
                )
                hunks.append(hunk)
                totalHunks += 1
            }
            guard !hunks.isEmpty else {
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 1,
                    reason: .fileHasNoHunks
                )
            }
            let metadata = UnifiedPatchFileMetadata(
                index: fileIndex,
                oldPath: oldPath,
                newPath: newPath,
                hunkCount: hunks.count
            )
            files.append(ParsedUnifiedPatchFile(metadata: metadata, hunks: hunks))
        }
        return files
    }

    private mutating func parseHunk(
        fileIndex: Int,
        hunkIndex: Int
    ) throws -> ParsedUnifiedPatchHunk {
        let headerLine = lineIndex + 1
        let header = controlBytes(lines[lineIndex].bytes)
        let ranges = try parseHunkHeader(header, line: headerLine)
        lineIndex += 1
        var oldCount = 0
        var newCount = 0
        var body: [ParsedUnifiedPatchLine] = []
        body.reserveCapacity(min(limits.maximumHunkLines, max(ranges.old.count, ranges.new.count)))

        while oldCount < ranges.old.count || newCount < ranges.new.count {
            guard lineIndex < lines.count else {
                throw UnifiedPatchError.malformedPatch(
                    line: headerLine,
                    reason: .hunkLineCountMismatch
                )
            }
            guard body.count < limits.maximumHunkLines else {
                throw UnifiedPatchError.hunkTooLarge(
                    fileIndex: fileIndex,
                    hunkIndex: hunkIndex,
                    maximumLines: limits.maximumHunkLines
                )
            }
            let physical = lines[lineIndex]
            guard physical.hasLineFeed, let prefix = physical.bytes.first else {
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 1,
                    reason: .unexpectedHunkLine
                )
            }
            let kind: ParsedUnifiedPatchLine.Kind
            switch prefix {
            case 0x20:
                kind = .context
                oldCount += 1
                newCount += 1
            case 0x2D:
                kind = .deletion
                oldCount += 1
            case 0x2B:
                kind = .addition
                newCount += 1
            default:
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 1,
                    reason: .unexpectedHunkLine
                )
            }
            guard oldCount <= ranges.old.count, newCount <= ranges.new.count else {
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 1,
                    reason: .hunkLineCountMismatch
                )
            }
            body.append(
                ParsedUnifiedPatchLine(
                    kind: kind,
                    record: PatchRecord(bytes: Array(physical.bytes.dropFirst()), hasLineFeed: true)
                ))
            lineIndex += 1
            if lineIndex < lines.count,
               isNoFinalNewlineMarker(controlBytes(lines[lineIndex].bytes)) {
                guard body[body.count - 1].record.hasLineFeed else {
                    throw UnifiedPatchError.malformedPatch(
                        line: lineIndex + 1,
                        reason: .duplicateNoFinalNewlineMarker
                    )
                }
                body[body.count - 1].record.hasLineFeed = false
                lineIndex += 1
            }
        }
        if lineIndex < lines.count {
            let next = controlBytes(lines[lineIndex].bytes)
            if isNoFinalNewlineMarker(next) {
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 1,
                    reason: .duplicateNoFinalNewlineMarker
                )
            }
            if hasUnexpectedBodyPrefix(next), !isFileHeader(at: lineIndex) {
                throw UnifiedPatchError.malformedPatch(
                    line: lineIndex + 1,
                    reason: .hunkLineCountMismatch
                )
            }
        }
        return ParsedUnifiedPatchHunk(
            headerLine: headerLine,
            oldRange: ranges.old,
            newRange: ranges.new,
            lines: body
        )
    }

    private func parseHunkHeader(
        _ bytes: ArraySlice<UInt8>,
        line: Int
    ) throws -> (old: ParsedPatchRange, new: ParsedPatchRange) {
        var cursor = 0
        let input = Array(bytes)
        guard consume("@@ -", in: input, cursor: &cursor),
              let oldStart = parseUnsigned(in: input, cursor: &cursor) else {
            throw UnifiedPatchError.malformedPatch(line: line, reason: .malformedHunkHeader)
        }
        let oldCount = try parseOptionalCount(in: input, cursor: &cursor, line: line)
        guard consume(" +", in: input, cursor: &cursor),
              let newStart = parseUnsigned(in: input, cursor: &cursor) else {
            throw UnifiedPatchError.malformedPatch(line: line, reason: .malformedHunkHeader)
        }
        let newCount = try parseOptionalCount(in: input, cursor: &cursor, line: line)
        guard consume(" @@", in: input, cursor: &cursor) else {
            throw UnifiedPatchError.malformedPatch(line: line, reason: .malformedHunkHeader)
        }
        let oldRange = try parsedRange(start: oldStart, count: oldCount, line: line)
        let newRange = try parsedRange(start: newStart, count: newCount, line: line)
        return (oldRange, newRange)
    }

    private func parseOptionalCount(
        in bytes: [UInt8],
        cursor: inout Int,
        line: Int
    ) throws -> Int {
        guard cursor < bytes.count, bytes[cursor] == 0x2C else { return 1 }
        cursor += 1
        guard let count = parseUnsigned(in: bytes, cursor: &cursor) else {
            throw UnifiedPatchError.malformedPatch(line: line, reason: .malformedHunkHeader)
        }
        return count
    }

    private func parsedRange(start: Int, count: Int, line: Int) throws -> ParsedPatchRange {
        guard count == 0 || start > 0 else {
            throw UnifiedPatchError.malformedPatch(line: line, reason: .invalidHunkRange)
        }
        let zeroBasedStart = count == 0 ? start : start - 1
        _ = try UnifiedPatchApplier.checkedAdd(
            zeroBasedStart,
            count,
            line: line,
            reason: .invalidHunkRange
        )
        return ParsedPatchRange(start: zeroBasedStart, count: count)
    }

    private func parsePath(
        _ header: [UInt8],
        fileIndex: Int,
        side: UnifiedPatchPathSide
    ) throws -> String? {
        let raw: [UInt8]
        if header.first == 0x22 {
            raw = try decodeQuotedPath(header, fileIndex: fileIndex, side: side)
        } else {
            raw = Array(header.prefix { $0 != 0x09 })
        }
        guard let path = String(bytes: raw, encoding: .utf8) else {
            throw UnifiedPatchError.malformedPatch(
                line: lineIndex + (side == .new ? 2 : 1),
                reason: .malformedPath
            )
        }
        if path == "/dev/null" { return nil }
        return try validateAndStripPath(path, fileIndex: fileIndex, side: side)
    }

    private func decodeQuotedPath(
        _ header: [UInt8],
        fileIndex: Int,
        side: UnifiedPatchPathSide
    ) throws -> [UInt8] {
        var result: [UInt8] = []
        var index = 1
        var closed = false
        while index < header.count {
            let byte = header[index]
            if byte == 0x22 {
                closed = true
                index += 1
                break
            }
            if byte != 0x5C {
                result.append(byte)
                index += 1
                continue
            }
            index += 1
            guard index < header.count else {
                throw invalidPath(fileIndex: fileIndex, side: side, reason: .controlCharacter)
            }
            let escaped = header[index]
            switch escaped {
            case 0x61: result.append(0x07)
            case 0x62: result.append(0x08)
            case 0x74: result.append(0x09)
            case 0x6E: result.append(0x0A)
            case 0x76: result.append(0x0B)
            case 0x66: result.append(0x0C)
            case 0x72: result.append(0x0D)
            case 0x22, 0x5C: result.append(escaped)
            case 0x30...0x37:
                var value = Int(escaped - 0x30)
                var digits = 1
                while digits < 3, index + 1 < header.count,
                      (0x30...0x37).contains(header[index + 1]) {
                    index += 1
                    value = value * 8 + Int(header[index] - 0x30)
                    digits += 1
                }
                guard value <= 0xFF else {
                    throw invalidPath(fileIndex: fileIndex, side: side, reason: .controlCharacter)
                }
                result.append(UInt8(value))
            default:
                throw invalidPath(fileIndex: fileIndex, side: side, reason: .controlCharacter)
            }
            index += 1
        }
        guard closed,
              index == header.count || header[index] == 0x09 || header[index] == 0x20 else {
            throw invalidPath(fileIndex: fileIndex, side: side, reason: .controlCharacter)
        }
        return result
    }

    private func validateAndStripPath(
        _ path: String,
        fileIndex: Int,
        side: UnifiedPatchPathSide
    ) throws -> String {
        guard !path.isEmpty else { throw invalidPath(fileIndex: fileIndex, side: side, reason: .empty) }
        guard path.first != "/", path.first != "\\" else {
            throw invalidPath(fileIndex: fileIndex, side: side, reason: .absolute)
        }
        guard !path.contains("\\") else {
            throw invalidPath(fileIndex: fileIndex, side: side, reason: .unsupportedSeparator)
        }
        guard !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            throw invalidPath(fileIndex: fileIndex, side: side, reason: .controlCharacter)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty }) else {
            throw invalidPath(fileIndex: fileIndex, side: side, reason: .emptyComponent)
        }
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw invalidPath(fileIndex: fileIndex, side: side, reason: .traversal)
        }
        if let first = components.first, first.count >= 2 {
            let scalars = first.unicodeScalars
            let firstScalar = scalars[scalars.startIndex].value
            let secondIndex = scalars.index(after: scalars.startIndex)
            if secondIndex < scalars.endIndex,
               scalars[secondIndex].value == 0x3A,
               (0x41...0x5A).contains(firstScalar) || (0x61...0x7A).contains(firstScalar) {
                throw invalidPath(fileIndex: fileIndex, side: side, reason: .absolute)
            }
        }
        guard stripCount < components.count else {
            throw invalidPath(fileIndex: fileIndex, side: side, reason: .insufficientComponents)
        }
        return components.dropFirst(stripCount).joined(separator: "/")
    }

    private func invalidPath(
        fileIndex: Int,
        side: UnifiedPatchPathSide,
        reason: UnifiedPatchPathRejection
    ) -> UnifiedPatchError {
        .invalidPath(fileIndex: fileIndex, side: side, reason: reason)
    }

    private func parseUnsigned(in bytes: [UInt8], cursor: inout Int) -> Int? {
        let start = cursor
        var value = 0
        while cursor < bytes.count, (0x30...0x39).contains(bytes[cursor]) {
            let digit = Int(bytes[cursor] - 0x30)
            let (multiplied, multiplyOverflow) = value.multipliedReportingOverflow(by: 10)
            let (next, addOverflow) = multiplied.addingReportingOverflow(digit)
            guard !multiplyOverflow, !addOverflow else { return nil }
            value = next
            cursor += 1
        }
        return cursor == start ? nil : value
    }

    private func consume(_ value: String, in bytes: [UInt8], cursor: inout Int) -> Bool {
        let expected = Array(value.utf8)
        guard cursor <= bytes.count, expected.count <= bytes.count - cursor else { return false }
        guard bytes[cursor..<(cursor + expected.count)].elementsEqual(expected) else { return false }
        cursor += expected.count
        return true
    }

    private func isFileHeader(at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        return hasPrefix(controlBytes(lines[index].bytes), ascii: "--- ")
            && hasPrefix(controlBytes(lines[index + 1].bytes), ascii: "+++ ")
    }

    private func hasUnexpectedBodyPrefix(_ bytes: ArraySlice<UInt8>) -> Bool {
        guard let first = bytes.first else { return false }
        return first == 0x20 || first == 0x2B || first == 0x2D || first == 0x5C
    }
}

private struct ParsedUnifiedPatchFile: Equatable, Sendable {
    let metadata: UnifiedPatchFileMetadata
    let hunks: [ParsedUnifiedPatchHunk]
}

private struct ParsedUnifiedPatchHunk: Equatable, Sendable {
    let headerLine: Int
    let oldRange: ParsedPatchRange
    let newRange: ParsedPatchRange
    let lines: [ParsedUnifiedPatchLine]
}

private struct ParsedPatchRange: Equatable, Sendable {
    let start: Int
    let count: Int
}

private struct ParsedUnifiedPatchLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case context
        case deletion
        case addition
    }

    let kind: Kind
    var record: PatchRecord
}

private struct PatchRecord: Equatable, Sendable {
    let bytes: [UInt8]
    var hasLineFeed: Bool
}

private struct WorkBudget {
    let maximum: Int
    private(set) var used = 0

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= maximum - used else {
            throw UnifiedPatchError.workLimitExceeded(maximumWork: maximum)
        }
        used += amount
        if used.isMultiple(of: 4_096) { try Task.checkCancellation() }
    }
}

private struct PatchOutput {
    private(set) var bytes: [UInt8] = []
    private(set) var lineCount = 0
    private var lastRecordHadLineFeed: Bool?
    let limits: UnifiedPatchLimits
    var work: WorkBudget

    init(limits: UnifiedPatchLimits, work: WorkBudget) {
        self.limits = limits
        self.work = work
        bytes.reserveCapacity(min(limits.maximumOutputBytes, 64 * 1024))
    }

    var text: String { String(decoding: bytes, as: UTF8.self) }

    mutating func append(
        _ record: PatchRecord,
        fileIndex: Int,
        hunkIndex: Int
    ) throws {
        guard lastRecordHadLineFeed != false else {
            throw UnifiedPatchError.hunkRejected(
                fileIndex: fileIndex,
                hunkIndex: hunkIndex,
                reason: .invalidNoFinalNewlinePlacement
            )
        }
        guard lineCount < limits.maximumOutputLines else {
            throw UnifiedPatchError.tooManyOutputLines(maximumLines: limits.maximumOutputLines)
        }
        let additional = try outputSize(for: record)
        guard additional <= limits.maximumOutputBytes - bytes.count else {
            throw UnifiedPatchError.outputTooLarge(maximumBytes: limits.maximumOutputBytes)
        }
        try work.consume(additional)
        bytes.append(contentsOf: record.bytes)
        if record.hasLineFeed { bytes.append(0x0A) }
        lineCount += 1
        lastRecordHadLineFeed = record.hasLineFeed
    }

    private func outputSize(for record: PatchRecord) throws -> Int {
        let (size, overflow) = record.bytes.count.addingReportingOverflow(record.hasLineFeed ? 1 : 0)
        guard !overflow else {
            throw UnifiedPatchError.outputTooLarge(maximumBytes: limits.maximumOutputBytes)
        }
        return size
    }
}

private struct CandidateIterator: IteratorProtocol {
    let lower: Int
    let upper: Int
    let expected: Int
    private var yieldedExpected = false
    private var distance = 1
    private var yieldUpperAtDistance = false
    private var outsideCandidate: Int?
    private let outsideDirection: Int

    init(lower: Int, upper: Int, expected: Int) {
        self.lower = lower
        self.upper = upper
        self.expected = expected
        if expected < lower {
            outsideCandidate = lower
            outsideDirection = 1
        } else if expected > upper {
            outsideCandidate = upper
            outsideDirection = -1
        } else {
            outsideCandidate = nil
            outsideDirection = 0
        }
    }

    mutating func next() -> Int? {
        if let candidate = outsideCandidate {
            if candidate == (outsideDirection > 0 ? upper : lower) {
                outsideCandidate = nil
            } else {
                outsideCandidate = candidate + outsideDirection
            }
            return candidate
        }
        guard lower <= expected, expected <= upper else { return nil }
        if !yieldedExpected {
            yieldedExpected = true
            return expected
        }
        while true {
            if !yieldUpperAtDistance {
                yieldUpperAtDistance = true
                if expected >= distance, expected - distance >= lower {
                    return expected - distance
                }
            } else {
                yieldUpperAtDistance = false
                let currentDistance = distance
                distance += 1
                if expected <= Int.max - currentDistance,
                   expected + currentDistance <= upper {
                    return expected + currentDistance
                }
            }
            let lowerExhausted = expected < distance || expected - distance < lower
            let upperExhausted = expected > Int.max - distance || expected + distance > upper
            if lowerExhausted, upperExhausted { return nil }
        }
    }
}

private func controlBytes(_ bytes: [UInt8]) -> ArraySlice<UInt8> {
    bytes.last == 0x0D ? bytes.dropLast() : bytes[...]
}

private func hasPrefix(_ bytes: ArraySlice<UInt8>, ascii: String) -> Bool {
    bytes.starts(with: ascii.utf8)
}

private func isNoFinalNewlineMarker(_ bytes: ArraySlice<UInt8>) -> Bool {
    bytes.elementsEqual("\\ No newline at end of file".utf8)
}
