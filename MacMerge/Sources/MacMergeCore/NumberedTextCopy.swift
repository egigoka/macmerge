import Foundation

public enum NumberedTextCopySide: Equatable, Sendable {
    case left
    case right
}

public enum NumberedTextCopyNumberAlignment: Equatable, Sendable {
    case left
    case right
}

public struct NumberedTextCopyOptions: Equatable, Sendable {
    public static let defaultMaximumRows = 1_048_576
    public static let defaultMaximumOutputBytes = 64 * 1024 * 1024

    /// Text between the padded line-number field and source text.
    public var numberSeparator: String
    /// Text between selected aligned rows. Source text itself is never normalized.
    public var rowSeparator: String
    /// Field value used when the selected side is absent from an aligned row.
    public var missingLineNumber: String
    public var minimumLineNumberWidth: Int
    public var numberAlignment: NumberedTextCopyNumberAlignment
    public var paddingCharacter: Character
    public var includesTrailingRowSeparator: Bool
    public var maximumRows: Int
    public var maximumOutputBytes: Int

    public init(
        numberSeparator: String = ": ",
        rowSeparator: String = "\n",
        missingLineNumber: String = "-",
        minimumLineNumberWidth: Int = 0,
        numberAlignment: NumberedTextCopyNumberAlignment = .right,
        paddingCharacter: Character = " ",
        includesTrailingRowSeparator: Bool = false,
        maximumRows: Int = NumberedTextCopyOptions.defaultMaximumRows,
        maximumOutputBytes: Int = NumberedTextCopyOptions.defaultMaximumOutputBytes
    ) {
        self.numberSeparator = numberSeparator
        self.rowSeparator = rowSeparator
        self.missingLineNumber = missingLineNumber
        self.minimumLineNumberWidth = minimumLineNumberWidth
        self.numberAlignment = numberAlignment
        self.paddingCharacter = paddingCharacter
        self.includesTrailingRowSeparator = includesTrailingRowSeparator
        self.maximumRows = maximumRows
        self.maximumOutputBytes = maximumOutputBytes
    }
}

public enum NumberedTextCopyError: Error, LocalizedError, Equatable, Sendable {
    case emptySelection
    case invalidSelectionRange(
        selectionIndex: Int,
        lowerBound: Int,
        upperBound: Int,
        rowCount: Int
    )
    case unorderedOrOverlappingSelection(selectionIndex: Int)
    case invalidMinimumLineNumberWidth(Int)
    case invalidMaximumRows(Int)
    case invalidMaximumOutputBytes(Int)
    case tooManyRows(maximumRows: Int)
    case outputTooLarge(maximumBytes: Int)
    case unstablePaddingCharacter
    case paddingCharacterTooLarge(maximumUTF8Bytes: Int, maximumUTF16CodeUnits: Int)
    case graphemeSegmentationTooComplex(maximumUnbrokenBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            "Numbered text copy requires at least one selected row range."
        case .invalidSelectionRange(let index, let lowerBound, let upperBound, let rowCount):
            "Selected row range \(index) (\(lowerBound)..<\(upperBound)) is outside 0..<\(rowCount) or empty."
        case .unorderedOrOverlappingSelection(let index):
            "Selected row range \(index) is out of order or overlaps the previous range."
        case .invalidMinimumLineNumberWidth(let width):
            "Minimum line-number width must not be negative: \(width)."
        case .invalidMaximumRows(let maximumRows):
            "Numbered text copy row limit must be positive: \(maximumRows)."
        case .invalidMaximumOutputBytes(let maximumBytes):
            "Numbered text copy output limit must be positive: \(maximumBytes)."
        case .tooManyRows(let maximumRows):
            "Numbered text copy exceeds the \(maximumRows)-row limit."
        case .outputTooLarge(let maximumBytes):
            "Numbered text copy exceeds the \(maximumBytes)-byte output limit."
        case .unstablePaddingCharacter:
            "The padding character does not preserve the requested rendered line-number width."
        case .paddingCharacterTooLarge(let maximumUTF8Bytes, let maximumUTF16CodeUnits):
            "The padding character exceeds the \(maximumUTF8Bytes)-byte or \(maximumUTF16CodeUnits)-UTF-16-code-unit limit."
        case .graphemeSegmentationTooComplex(let maximumUnbrokenBytes):
            "Line-number text contains more than \(maximumUnbrokenBytes) bytes without a bounded grapheme break."
        }
    }
}

public enum NumberedTextCopy: Sendable {
    enum Phase: Equatable, Sendable {
        case lineNumberWidth
        case graphemeSegmentation
        case outputPreflight
        case outputAssembly
        case sourceBytePreflight
        case sourceByteEmission
        case paddingChunk
    }

    struct Progress: Equatable, Sendable {
        let phase: Phase
        let completedUnitCount: Int
    }

    @TaskLocal
    static var progressObserver: (@Sendable (Progress) -> Void)?

    static let maximumChunkBytes = 16 * 1_024
    static let maximumPaddingUTF8Bytes = maximumChunkBytes
    static let maximumPaddingUTF16CodeUnits = maximumChunkBytes

    /// Formats ordered, non-overlapping, half-open ranges of aligned `DiffRow` indices.
    /// Missing rows retain their position and use `options.missingLineNumber` with empty text.
    public static func format(
        rows: [DiffRow],
        selectedRanges: [Range<Int>],
        side: NumberedTextCopySide,
        options: NumberedTextCopyOptions = NumberedTextCopyOptions()
    ) throws -> String {
        try Task.checkCancellation()
        try validate(options: options)
        let selectedRowCount = try validate(
            selectedRanges: selectedRanges,
            rowCount: rows.count,
            maximumRows: options.maximumRows
        )
        let padding = try validatedPadding(options.paddingCharacter)

        try checkpoint(.lineNumberWidth)
        var numberWidth = options.minimumLineNumberWidth
        let missingLineNumberWidth = try cancellableCharacterCount(options.missingLineNumber)
        var visitedRowCount = 0
        for range in selectedRanges {
            for index in range {
                if visitedRowCount > 0, visitedRowCount.isMultiple(of: 1_024) {
                    try checkpoint(.lineNumberWidth, completedUnitCount: visitedRowCount)
                }
                let width =
                    lineNumber(for: rows[index], side: side).map {
                        String($0).utf8.count
                    } ?? missingLineNumberWidth
                numberWidth = max(numberWidth, width)
                visitedRowCount += 1
            }
        }

        let outputByteCount = try preflightOutputByteCount(
            rows: rows,
            selectedRanges: selectedRanges,
            side: side,
            options: options,
            numberWidth: numberWidth,
            missingLineNumberWidth: missingLineNumberWidth,
            selectedRowCount: selectedRowCount,
            padding: padding
        )
        var output = NumberedTextCopyOutput(
            maximumBytes: options.maximumOutputBytes,
            reservingBytes: outputByteCount
        )
        try checkpoint(.outputAssembly)
        var outputRowIndex = 0
        for range in selectedRanges {
            for index in range {
                if outputRowIndex > 0, outputRowIndex.isMultiple(of: 1_024) {
                    try checkpoint(.outputAssembly, completedUnitCount: outputRowIndex)
                }
                if outputRowIndex > 0 {
                    try output.append(options.rowSeparator)
                }

                let row = rows[index]
                let numberValue = lineNumber(for: row, side: side)
                let number = numberValue.map(String.init) ?? options.missingLineNumber
                let numberCharacterCount =
                    numberValue == nil
                    ? missingLineNumberWidth
                    : number.utf8.count
                let paddingCount = numberWidth - numberCharacterCount
                if options.numberAlignment == .right {
                    try output.append(repeating: padding, count: paddingCount)
                }
                try output.append(number)
                if options.numberAlignment == .left {
                    try output.append(repeating: padding, count: paddingCount)
                }
                try output.append(options.numberSeparator)
                if let sourceBytes = sourceTextUTF8(for: row, side: side) {
                    try checkpoint(.sourceByteEmission)
                    try output.append(sourceBytes)
                } else if let line = line(for: row, side: side) {
                    try output.append(line.text)
                }
                outputRowIndex += 1
            }
        }
        assert(outputRowIndex == selectedRowCount)

        if options.includesTrailingRowSeparator {
            try output.append(options.rowSeparator)
        }
        return try output.string()
    }

    private static func validate(options: NumberedTextCopyOptions) throws {
        guard options.minimumLineNumberWidth >= 0 else {
            throw NumberedTextCopyError.invalidMinimumLineNumberWidth(
                options.minimumLineNumberWidth
            )
        }
        guard options.maximumRows > 0 else {
            throw NumberedTextCopyError.invalidMaximumRows(options.maximumRows)
        }
        guard options.maximumOutputBytes > 0 else {
            throw NumberedTextCopyError.invalidMaximumOutputBytes(
                options.maximumOutputBytes
            )
        }
    }

    private static func validate(
        selectedRanges: [Range<Int>],
        rowCount: Int,
        maximumRows: Int
    ) throws -> Int {
        guard !selectedRanges.isEmpty else {
            throw NumberedTextCopyError.emptySelection
        }

        var selectedRowCount = 0
        var previousUpperBound: Int?
        for (index, range) in selectedRanges.enumerated() {
            if index.isMultiple(of: 1_024) {
                try Task.checkCancellation()
            }
            guard
                range.lowerBound >= 0,
                range.lowerBound < range.upperBound,
                range.upperBound <= rowCount
            else {
                throw NumberedTextCopyError.invalidSelectionRange(
                    selectionIndex: index,
                    lowerBound: range.lowerBound,
                    upperBound: range.upperBound,
                    rowCount: rowCount
                )
            }
            if let previousUpperBound, range.lowerBound < previousUpperBound {
                throw NumberedTextCopyError.unorderedOrOverlappingSelection(
                    selectionIndex: index
                )
            }

            let rangeCount = range.upperBound - range.lowerBound
            guard rangeCount <= maximumRows - selectedRowCount else {
                throw NumberedTextCopyError.tooManyRows(maximumRows: maximumRows)
            }
            selectedRowCount += rangeCount
            previousUpperBound = range.upperBound
        }
        return selectedRowCount
    }

    private static func validatedPadding(_ character: Character) throws -> PaddingUnit {
        var paddingUTF8Count = 0
        var paddingUTF16Count = 0
        for (index, scalar) in character.unicodeScalars.enumerated() {
            if index.isMultiple(of: 1_024) {
                try Task.checkCancellation()
            }
            paddingUTF8Count += utf8Count(of: scalar)
            paddingUTF16Count += scalar.value <= 0xFFFF ? 1 : 2
            guard
                paddingUTF8Count <= maximumPaddingUTF8Bytes,
                paddingUTF16Count <= maximumPaddingUTF16CodeUnits
            else {
                throw NumberedTextCopyError.paddingCharacterTooLarge(
                    maximumUTF8Bytes: maximumPaddingUTF8Bytes,
                    maximumUTF16CodeUnits: maximumPaddingUTF16CodeUnits
                )
            }
        }

        let string = String(character)
        try Task.checkCancellation()
        guard String(repeating: string, count: 2).count == 2 else {
            throw NumberedTextCopyError.unstablePaddingCharacter
        }
        return PaddingUnit(string: string, utf8Count: paddingUTF8Count)
    }

    private static func line(for row: DiffRow, side: NumberedTextCopySide) -> DiffLine? {
        switch side {
        case .left:
            row.left
        case .right:
            row.right
        }
    }

    private static func lineNumber(
        for row: DiffRow,
        side: NumberedTextCopySide
    ) -> Int? {
        switch side {
        case .left:
            row.id.leftNumber
        case .right:
            row.id.rightNumber
        }
    }

    private static func preflightOutputByteCount(
        rows: [DiffRow],
        selectedRanges: [Range<Int>],
        side: NumberedTextCopySide,
        options: NumberedTextCopyOptions,
        numberWidth: Int,
        missingLineNumberWidth: Int,
        selectedRowCount: Int,
        padding: PaddingUnit
    ) throws -> Int {
        try checkpoint(.outputPreflight)
        let maximumBytes = options.maximumOutputBytes
        let numberSeparatorBytes = try cancellableUTF8Count(options.numberSeparator)
        let rowSeparatorBytes = try cancellableUTF8Count(options.rowSeparator)
        let missingLineNumberBytes = try cancellableUTF8Count(options.missingLineNumber)

        var byteCount = 0
        var outputRowIndex = 0
        for range in selectedRanges {
            for index in range {
                if outputRowIndex > 0, outputRowIndex.isMultiple(of: 1_024) {
                    try checkpoint(.outputPreflight, completedUnitCount: outputRowIndex)
                }
                if outputRowIndex > 0 {
                    try addBytes(rowSeparatorBytes, to: &byteCount, maximum: maximumBytes)
                }

                let row = rows[index]
                let numberValue = lineNumber(for: row, side: side)
                let number = numberValue.map(String.init) ?? options.missingLineNumber
                let numberCharacterCount =
                    numberValue == nil
                    ? missingLineNumberWidth
                    : number.utf8.count
                let paddingCount = numberWidth - numberCharacterCount
                if paddingCount > 0 {
                    let (addedPaddingBytes, overflow) = padding.utf8Count.multipliedReportingOverflow(
                        by: paddingCount
                    )
                    guard !overflow else {
                        throw NumberedTextCopyError.outputTooLarge(maximumBytes: maximumBytes)
                    }
                    try validateRenderedFieldWidth(
                        number: number,
                        numberWidth: numberWidth,
                        paddingCount: paddingCount,
                        padding: padding,
                        alignment: options.numberAlignment
                    )
                    try addBytes(addedPaddingBytes, to: &byteCount, maximum: maximumBytes)
                }
                let numberBytes =
                    numberValue == nil
                    ? missingLineNumberBytes
                    : number.utf8.count
                try addBytes(numberBytes, to: &byteCount, maximum: maximumBytes)
                try addBytes(numberSeparatorBytes, to: &byteCount, maximum: maximumBytes)
                if let sourceByteCount = sourceTextUTF8Count(for: row, side: side) {
                    try checkpoint(.sourceBytePreflight)
                    try addBytes(sourceByteCount, to: &byteCount, maximum: maximumBytes)
                } else if let line = line(for: row, side: side) {
                    try addBytes(
                        cancellableUTF8Count(line.text),
                        to: &byteCount,
                        maximum: maximumBytes
                    )
                }
                outputRowIndex += 1
            }
        }
        assert(outputRowIndex == selectedRowCount)

        if options.includesTrailingRowSeparator {
            try addBytes(rowSeparatorBytes, to: &byteCount, maximum: maximumBytes)
        }
        return byteCount
    }

    fileprivate static func cancellableUTF8Count(_ string: String) throws -> Int {
        var byteCount = 0
        for (index, scalar) in string.unicodeScalars.enumerated() {
            if index.isMultiple(of: 4_096) {
                try Task.checkCancellation()
            }
            switch scalar.value {
            case ...0x7F:
                byteCount += 1
            case ...0x7FF:
                byteCount += 2
            case ...0xFFFF:
                byteCount += 3
            default:
                byteCount += 4
            }
        }
        return byteCount
    }

    private static func cancellableCharacterCount(_ string: String) throws -> Int {
        try checkpoint(.graphemeSegmentation)
        var count = 0
        var bufferStart = string.startIndex
        var bufferedByteCount = 0
        let scalars = string.unicodeScalars
        for (index, scalarIndex) in scalars.indices.enumerated() {
            if index.isMultiple(of: 4_096) {
                try checkpoint(.graphemeSegmentation, completedUnitCount: index)
            }
            let scalar = scalars[scalarIndex]
            let scalarByteCount = utf8Count(of: scalar)
            bufferedByteCount += scalarByteCount
            guard bufferedByteCount > maximumChunkBytes else { continue }

            let bufferEnd = scalars.index(after: scalarIndex)
            let buffer = string[bufferStart..<bufferEnd]
            // Retain the trailing cluster so RI, ZWJ, and Prepend context crosses scans.
            var trailingCharacterStart = buffer.startIndex
            var nextCharacterStart = buffer.index(after: trailingCharacterStart)
            while nextCharacterStart < buffer.endIndex {
                count += 1
                trailingCharacterStart = nextCharacterStart
                nextCharacterStart = buffer.index(after: trailingCharacterStart)
            }
            bufferStart = trailingCharacterStart
            bufferedByteCount = buffer[trailingCharacterStart...].utf8.count
            guard bufferedByteCount <= maximumChunkBytes else {
                throw NumberedTextCopyError.graphemeSegmentationTooComplex(
                    maximumUnbrokenBytes: maximumChunkBytes
                )
            }
        }
        if bufferStart < string.endIndex {
            try Task.checkCancellation()
            count += string[bufferStart...].count
        }
        return count
    }

    private static func validateRenderedFieldWidth(
        number: String,
        numberWidth: Int,
        paddingCount: Int,
        padding: PaddingUnit,
        alignment: NumberedTextCopyNumberAlignment
    ) throws {
        try Task.checkCancellation()
        let boundaryField =
            switch alignment {
            case .left: number + padding.string
            case .right: padding.string + number
            }
        let numberCharacterCount = numberWidth - paddingCount
        guard try cancellableCharacterCount(boundaryField) == numberCharacterCount + 1 else {
            throw NumberedTextCopyError.unstablePaddingCharacter
        }
    }

    private static func sourceTextUTF8Count(
        for row: DiffRow,
        side: NumberedTextCopySide
    ) -> Int? {
        row.sourceTextUTF8Count(onLeft: side == .left)
    }

    private static func sourceTextUTF8(
        for row: DiffRow,
        side: NumberedTextCopySide
    ) -> ArraySlice<UInt8>? {
        row.sourceTextUTF8(onLeft: side == .left)
    }

    fileprivate static func checkpoint(
        _ phase: Phase,
        completedUnitCount: Int = 0
    ) throws {
        progressObserver?(Progress(phase: phase, completedUnitCount: completedUnitCount))
        try Task.checkCancellation()
    }

    fileprivate static func utf8Count(of scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case ...0x7F: 1
        case ...0x7FF: 2
        case ...0xFFFF: 3
        default: 4
        }
    }

    private static func addBytes(_ added: Int, to total: inout Int, maximum: Int) throws {
        guard added <= maximum - total else {
            throw NumberedTextCopyError.outputTooLarge(maximumBytes: maximum)
        }
        total += added
    }
}

private struct PaddingUnit {
    let string: String
    let utf8Count: Int
}

private struct NumberedTextCopyOutput {
    private var value: [UInt8] = []
    private var byteCount = 0
    private let maximumBytes: Int

    init(maximumBytes: Int, reservingBytes: Int) {
        self.maximumBytes = maximumBytes
        value.reserveCapacity(reservingBytes)
    }

    func string() throws -> String {
        try Task.checkCancellation()
        var result = ""
        result.reserveCapacity(value.count)
        var chunkStart = value.startIndex
        while chunkStart < value.endIndex {
            try Task.checkCancellation()
            var chunkEnd = min(chunkStart + NumberedTextCopy.maximumChunkBytes, value.endIndex)
            while chunkEnd < value.endIndex, value[chunkEnd] & 0xC0 == 0x80 {
                chunkEnd -= 1
            }
            result.append(contentsOf: String(decoding: value[chunkStart..<chunkEnd], as: UTF8.self))
            chunkStart = chunkEnd
        }
        return result
    }

    mutating func append(_ string: String) throws {
        let addedBytes = try NumberedTextCopy.cancellableUTF8Count(string)
        guard addedBytes <= maximumBytes - byteCount else {
            throw NumberedTextCopyError.outputTooLarge(maximumBytes: maximumBytes)
        }
        try appendPreflightedInChunks(string.utf8)
        byteCount += addedBytes
    }

    mutating func append(_ bytes: ArraySlice<UInt8>) throws {
        guard bytes.count <= maximumBytes - byteCount else {
            throw NumberedTextCopyError.outputTooLarge(maximumBytes: maximumBytes)
        }
        try appendPreflightedInChunks(bytes)
        byteCount += bytes.count
    }

    mutating func append(repeating unit: PaddingUnit, count: Int) throws {
        guard count > 0 else { return }
        try Task.checkCancellation()
        let (addedBytes, overflow) = unit.utf8Count.multipliedReportingOverflow(by: count)
        guard !overflow, addedBytes <= maximumBytes - byteCount else {
            throw NumberedTextCopyError.outputTooLarge(maximumBytes: maximumBytes)
        }

        let chunkCharacterCount = min(
            count,
            max(1, NumberedTextCopy.maximumChunkBytes / unit.utf8Count)
        )
        let chunk = String(repeating: unit.string, count: chunkCharacterCount)
        var remaining = count
        while remaining >= chunkCharacterCount {
            try NumberedTextCopy.checkpoint(
                .paddingChunk,
                completedUnitCount: count - remaining
            )
            try appendPreflightedInChunks(chunk.utf8)
            remaining -= chunkCharacterCount
        }
        if remaining > 0 {
            try NumberedTextCopy.checkpoint(
                .paddingChunk,
                completedUnitCount: count - remaining
            )
            try appendPreflightedInChunks(
                String(repeating: unit.string, count: remaining).utf8
            )
        }
        byteCount += addedBytes
    }

    private mutating func appendPreflightedInChunks<Bytes: Collection>(_ bytes: Bytes) throws
    where Bytes.Element == UInt8 {
        var chunkStart = bytes.startIndex
        while chunkStart != bytes.endIndex {
            try Task.checkCancellation()
            let chunkEnd =
                bytes.index(
                    chunkStart,
                    offsetBy: NumberedTextCopy.maximumChunkBytes,
                    limitedBy: bytes.endIndex
                ) ?? bytes.endIndex
            value.append(contentsOf: bytes[chunkStart..<chunkEnd])
            chunkStart = chunkEnd
        }
    }
}
