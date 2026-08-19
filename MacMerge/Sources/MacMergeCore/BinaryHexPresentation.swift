import Foundation

public struct BinaryHexRow: Equatable, Sendable {
    public let index: Int
    public let alignedOffset: Int
    public let leftOffset: Int
    public let rightOffset: Int
    public let cells: [BinaryByteCell]

    public var alignedOffsetText: String { Self.offsetText(alignedOffset) }
    public var leftOffsetText: String { Self.offsetText(leftOffset) }
    public var rightOffsetText: String { Self.offsetText(rightOffset) }
    public var leftHex: String { hex(onLeft: true) }
    public var rightHex: String { hex(onLeft: false) }
    public var leftASCII: String { ascii(onLeft: true) }
    public var rightASCII: String { ascii(onLeft: false) }

    private static func offsetText(_ offset: Int) -> String {
        String(format: "%08llX", UInt64(offset))
    }

    private func hex(onLeft: Bool) -> String {
        cells.map { cell in
            let byte = onLeft ? cell.leftByte : cell.rightByte
            return byte.map { String(format: "%02X", $0) } ?? "--"
        }.joined(separator: " ")
    }

    private func ascii(onLeft: Bool) -> String {
        let bytes = cells.map { cell -> UInt8 in
            guard let byte = onLeft ? cell.leftByte : cell.rightByte else { return 0x20 }
            return (0x20...0x7E).contains(byte) ? byte : 0x2E
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

public struct BinaryHexPresentation: Equatable, Sendable {
    // Generous for normal 8-64 byte hex rows while bounding one row's cell storage.
    private static let maximumBytesPerRow = 256
    // Viewports should request pages; this also bounds one call to 256K cells.
    private static let maximumRowsPerRequest = 1_024

    public let comparison: BinaryComparisonResult
    public let bytesPerRow: Int

    public init(comparison: BinaryComparisonResult, bytesPerRow: Int = 16) {
        precondition(bytesPerRow > 0, "Bytes per row must be positive")
        precondition(
            min(bytesPerRow, comparison.alignedByteCount) <= Self.maximumBytesPerRow,
            "Bytes per row exceeds the rendering limit of \(Self.maximumBytesPerRow)"
        )
        self.comparison = comparison
        self.bytesPerRow = bytesPerRow
    }

    public var rowCount: Int {
        let completeRows = comparison.alignedByteCount / bytesPerRow
        return completeRows + (comparison.alignedByteCount.isMultiple(of: bytesPerRow) ? 0 : 1)
    }

    public func row(at index: Int) -> BinaryHexRow? {
        guard index >= 0, index < rowCount else { return nil }
        let (alignedOffset, offsetOverflow) = index.multipliedReportingOverflow(by: bytesPerRow)
        guard !offsetOverflow else { return nil }
        let rowByteCount = min(bytesPerRow, comparison.alignedByteCount - alignedOffset)
        let (upperBound, upperBoundOverflow) = alignedOffset.addingReportingOverflow(rowByteCount)
        guard !upperBoundOverflow else { return nil }
        guard let offsets = comparison.sourceOffsets(atAlignedOffset: alignedOffset) else { return nil }
        return BinaryHexRow(
            index: index,
            alignedOffset: alignedOffset,
            leftOffset: offsets.left,
            rightOffset: offsets.right,
            cells: (alignedOffset..<upperBound).compactMap(comparison.byte(atAlignedOffset:))
        )
    }

    public func rows(in requestedRange: Range<Int>) -> [BinaryHexRow] {
        let lowerBound = min(rowCount, max(0, requestedRange.lowerBound))
        let upperBound = min(rowCount, max(lowerBound, requestedRange.upperBound))
        let (requestedRowCount, countOverflow) = upperBound.subtractingReportingOverflow(lowerBound)
        precondition(
            !countOverflow && requestedRowCount <= Self.maximumRowsPerRequest,
            "Row request exceeds the rendering limit of \(Self.maximumRowsPerRequest)"
        )
        return (lowerBound..<upperBound).compactMap(row(at:))
    }
}
