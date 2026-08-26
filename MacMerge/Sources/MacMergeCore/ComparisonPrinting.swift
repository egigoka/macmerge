import Foundation

public enum ComparisonPrintOrientation: String, CaseIterable, Equatable, Sendable {
    case portrait
    case landscape
}

public struct ComparisonPrintRect: Equatable, Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: CGFloat { x }
    public var minY: CGFloat { y }
    public var maxX: CGFloat { x + width }
    public var maxY: CGFloat { y + height }
}

public struct ComparisonPrintMargins: Equatable, Sendable {
    public let top: CGFloat
    public let leading: CGFloat
    public let bottom: CGFloat
    public let trailing: CGFloat

    public init(
        top: CGFloat,
        leading: CGFloat,
        bottom: CGFloat,
        trailing: CGFloat
    ) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(_ value: CGFloat) {
        self.init(top: value, leading: value, bottom: value, trailing: value)
    }
}

/// Validated printer geometry expressed in points in the selected orientation.
///
/// Bounds use a lower-left origin with Y increasing upward and must already reflect `orientation`.
/// Margins are measured inward from `paperBounds`; `printableBounds` is their intersection with
/// `imageableBounds`.
public struct ComparisonPrintPageSetup: Equatable, Sendable {
    public static let minimumScale: CGFloat = 0.01
    public static let maximumScale: CGFloat = 10

    public let paperBounds: ComparisonPrintRect
    public let imageableBounds: ComparisonPrintRect
    public let orientation: ComparisonPrintOrientation
    public let margins: ComparisonPrintMargins
    public let scale: CGFloat
    public let printableBounds: ComparisonPrintRect

    public init(
        paperBounds: ComparisonPrintRect,
        imageableBounds: ComparisonPrintRect,
        orientation: ComparisonPrintOrientation = .portrait,
        margins: ComparisonPrintMargins = ComparisonPrintMargins(36),
        scale: CGFloat = 1
    ) throws {
        guard Self.isFinite(paperBounds), Self.hasFiniteMaximums(paperBounds) else {
            throw ComparisonPrintingError.nonFinitePageGeometry
        }
        guard paperBounds.width > 0, paperBounds.height > 0 else {
            throw ComparisonPrintingError.invalidPaperBounds
        }
        guard
            orientation == .portrait
                ? paperBounds.height >= paperBounds.width
                : paperBounds.width >= paperBounds.height
        else {
            throw ComparisonPrintingError.orientationDoesNotMatchPaperBounds
        }
        guard Self.isFinite(imageableBounds), Self.hasFiniteMaximums(imageableBounds) else {
            throw ComparisonPrintingError.nonFinitePageGeometry
        }
        guard imageableBounds.width > 0, imageableBounds.height > 0 else {
            throw ComparisonPrintingError.invalidImageableBounds
        }
        guard imageableBounds.minX >= paperBounds.minX,
            imageableBounds.minY >= paperBounds.minY,
            imageableBounds.maxX <= paperBounds.maxX,
            imageableBounds.maxY <= paperBounds.maxY
        else {
            throw ComparisonPrintingError.imageableBoundsOutsidePaper
        }
        guard margins.top.isFinite,
            margins.leading.isFinite,
            margins.bottom.isFinite,
            margins.trailing.isFinite
        else {
            throw ComparisonPrintingError.nonFiniteMargins
        }
        guard margins.top >= 0,
            margins.leading >= 0,
            margins.bottom >= 0,
            margins.trailing >= 0
        else {
            throw ComparisonPrintingError.negativeMargins
        }
        guard scale.isFinite,
            (Self.minimumScale...Self.maximumScale).contains(scale)
        else {
            throw ComparisonPrintingError.invalidScale
        }

        let marginMinX = paperBounds.minX + margins.leading
        let marginMaxX = paperBounds.maxX - margins.trailing
        let marginMinY = paperBounds.minY + margins.bottom
        let marginMaxY = paperBounds.maxY - margins.top
        guard marginMinX.isFinite,
            marginMaxX.isFinite,
            marginMinY.isFinite,
            marginMaxY.isFinite
        else {
            throw ComparisonPrintingError.arithmeticOverflow
        }

        let printableMinX = max(imageableBounds.minX, marginMinX)
        let printableMaxX = min(imageableBounds.maxX, marginMaxX)
        let printableMinY = max(imageableBounds.minY, marginMinY)
        let printableMaxY = min(imageableBounds.maxY, marginMaxY)
        let printableWidth = printableMaxX - printableMinX
        let printableHeight = printableMaxY - printableMinY
        guard printableWidth.isFinite,
            printableHeight.isFinite,
            printableWidth > 0,
            printableHeight > 0
        else {
            throw ComparisonPrintingError.marginsExcludePrintableArea
        }

        self.paperBounds = paperBounds
        self.imageableBounds = imageableBounds
        self.orientation = orientation
        self.margins = margins
        self.scale = scale
        printableBounds = ComparisonPrintRect(
            x: printableMinX,
            y: printableMinY,
            width: printableWidth,
            height: printableHeight
        )
    }

    private static func isFinite(_ rect: ComparisonPrintRect) -> Bool {
        rect.x.isFinite
            && rect.y.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
    }

    private static func hasFiniteMaximums(_ rect: ComparisonPrintRect) -> Bool {
        rect.maxX.isFinite && rect.maxY.isFinite
    }
}

public enum ComparisonPrintPageLabel: Equatable, Sendable {
    case text(String)
    case documentTitle
    case pageNumber
    case pageNumberAndCount
}

public struct ComparisonPrintHeaderFooter: Equatable, Sendable {
    public static let `default` = ComparisonPrintHeaderFooter(
        header: .documentTitle,
        footer: .pageNumberAndCount
    )

    public let header: ComparisonPrintPageLabel?
    public let footer: ComparisonPrintPageLabel?
    /// Paper-space height reserved for each non-`nil` label. This is not affected by content scale.
    public let bandHeight: CGFloat

    public init(
        header: ComparisonPrintPageLabel? = .documentTitle,
        footer: ComparisonPrintPageLabel? = .pageNumberAndCount,
        bandHeight: CGFloat = 18
    ) {
        self.header = header
        self.footer = footer
        self.bandHeight = bandHeight
    }
}

public struct ComparisonPrintCell: Equatable, Sendable {
    public let lineNumber: Int?
    public let text: String

    public init(lineNumber: Int? = nil, text: String) {
        self.lineNumber = lineNumber
        self.text = text
    }
}

/// One aligned comparison row. Every document row must contain either two or three cells.
public struct ComparisonPrintRow: Equatable, Sendable {
    public let cells: [ComparisonPrintCell]

    public init(cells: [ComparisonPrintCell]) {
        self.cells = cells
    }

    public init(left: ComparisonPrintCell, right: ComparisonPrintCell) {
        cells = [left, right]
    }

    public init(
        base: ComparisonPrintCell,
        left: ComparisonPrintCell,
        right: ComparisonPrintCell
    ) {
        cells = [base, left, right]
    }
}

public struct ComparisonPrintDocument: Equatable, Sendable {
    public let title: String
    public let paneTitles: [String]
    public let rows: [ComparisonPrintRow]

    public init(title: String, paneTitles: [String], rows: [ComparisonPrintRow]) {
        self.title = title
        self.paneTitles = paneTitles
        self.rows = rows
    }
}

/// Deterministic monospaced layout metrics at 100% scale.
///
/// Wrapping assigns one column to each Unicode scalar and expands tabs to spaces.
/// Adapters should use a fixed-advance font matching `characterWidth` and `lineHeight`.
public struct ComparisonPrintLayout: Equatable, Sendable {
    public static let `default` = ComparisonPrintLayout()

    public let characterWidth: CGFloat
    public let lineHeight: CGFloat
    public let horizontalCellPadding: CGFloat
    public let verticalCellPadding: CGFloat
    public let paneSpacing: CGFloat
    /// Minimum width of the line-number column. Planning expands it to fit the largest line number.
    public let lineNumberColumnWidth: CGFloat
    public let paneTitleHeight: CGFloat
    public let tabWidth: Int

    public init(
        characterWidth: CGFloat = 7.2,
        lineHeight: CGFloat = 13,
        horizontalCellPadding: CGFloat = 4,
        verticalCellPadding: CGFloat = 2,
        paneSpacing: CGFloat = 8,
        lineNumberColumnWidth: CGFloat = 40,
        paneTitleHeight: CGFloat = 20,
        tabWidth: Int = 4
    ) {
        self.characterWidth = characterWidth
        self.lineHeight = lineHeight
        self.horizontalCellPadding = horizontalCellPadding
        self.verticalCellPadding = verticalCellPadding
        self.paneSpacing = paneSpacing
        self.lineNumberColumnWidth = lineNumberColumnWidth
        self.paneTitleHeight = paneTitleHeight
        self.tabWidth = tabWidth
    }
}

public struct ComparisonPrintPageRange: Equatable, Sendable {
    public let firstPage: Int
    public let lastPage: Int

    public init(firstPage: Int, lastPage: Int) throws {
        guard firstPage > 0, lastPage >= firstPage else {
            throw ComparisonPrintingError.invalidPageRange(
                firstPage: firstPage,
                lastPage: lastPage
            )
        }
        self.firstPage = firstPage
        self.lastPage = lastPage
    }

    public var closedRange: ClosedRange<Int> { firstPage...lastPage }
}

public struct ComparisonPrintLimits: Equatable, Sendable {
    public static let `default` = ComparisonPrintLimits()

    public let maximumRows: Int
    public let maximumInputBytes: Int
    public let maximumWork: Int
    public let maximumPages: Int
    public let maximumOutputBytes: Int
    public let maximumOutputItems: Int

    public init(
        maximumRows: Int = 1_000_000,
        maximumInputBytes: Int = 64 * 1_024 * 1_024,
        maximumWork: Int = 256 * 1_024 * 1_024,
        maximumPages: Int = 100_000,
        maximumOutputBytes: Int = 128 * 1_024 * 1_024,
        maximumOutputItems: Int = 4_000_000
    ) {
        self.maximumRows = maximumRows
        self.maximumInputBytes = maximumInputBytes
        self.maximumWork = maximumWork
        self.maximumPages = maximumPages
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumOutputItems = maximumOutputItems
    }
}

public struct ComparisonPrintCellFragment: Equatable, Sendable {
    /// Present only on the first fragment of a source row.
    public let lineNumber: Int?
    /// Display lines aligned with the enclosing fragment's `visualLineRange`.
    public let lines: [String]

    fileprivate init(lineNumber: Int?, lines: [String]) {
        self.lineNumber = lineNumber
        self.lines = lines
    }
}

public struct ComparisonPrintRowFragment: Equatable, Sendable {
    public let sourceRowIndex: Int
    public let visualLineRange: Range<Int>
    public let cells: [ComparisonPrintCellFragment]
    public let frame: ComparisonPrintRect
    public let isContinuation: Bool
    public let isContinued: Bool

    fileprivate init(
        sourceRowIndex: Int,
        visualLineRange: Range<Int>,
        cells: [ComparisonPrintCellFragment],
        frame: ComparisonPrintRect,
        isContinuation: Bool,
        isContinued: Bool
    ) {
        self.sourceRowIndex = sourceRowIndex
        self.visualLineRange = visualLineRange
        self.cells = cells
        self.frame = frame
        self.isContinuation = isContinuation
        self.isContinued = isContinued
    }
}

public struct ComparisonPrintPagePlan: Identifiable, Equatable, Sendable {
    public var id: Int { pageNumber }

    /// One-based page number in the complete document, not the selected output range.
    public let pageNumber: Int
    public let paperBounds: ComparisonPrintRect
    public let printableBounds: ComparisonPrintRect
    public let headerBounds: ComparisonPrintRect?
    public let footerBounds: ComparisonPrintRect?
    public let headerText: String?
    public let footerText: String?
    public let paneHeaderBounds: [ComparisonPrintRect]
    public let paneContentBounds: [ComparisonPrintRect]
    public let rowFragments: [ComparisonPrintRowFragment]

    fileprivate init(
        pageNumber: Int,
        paperBounds: ComparisonPrintRect,
        printableBounds: ComparisonPrintRect,
        headerBounds: ComparisonPrintRect?,
        footerBounds: ComparisonPrintRect?,
        headerText: String?,
        footerText: String?,
        paneHeaderBounds: [ComparisonPrintRect],
        paneContentBounds: [ComparisonPrintRect],
        rowFragments: [ComparisonPrintRowFragment]
    ) {
        self.pageNumber = pageNumber
        self.paperBounds = paperBounds
        self.printableBounds = printableBounds
        self.headerBounds = headerBounds
        self.footerBounds = footerBounds
        self.headerText = headerText
        self.footerText = footerText
        self.paneHeaderBounds = paneHeaderBounds
        self.paneContentBounds = paneContentBounds
        self.rowFragments = rowFragments
    }
}

/// Self-contained page data for native print preview or printing adapters.
public struct ComparisonPrintPreviewPlan: Equatable, Sendable {
    public let title: String
    public let paneTitles: [String]
    public let pageSetup: ComparisonPrintPageSetup
    public let layout: ComparisonPrintLayout
    public let totalPageCount: Int
    public let selectedPageRange: ComparisonPrintPageRange
    public let charactersPerLine: Int
    public let pages: [ComparisonPrintPagePlan]

    fileprivate init(
        title: String,
        paneTitles: [String],
        pageSetup: ComparisonPrintPageSetup,
        layout: ComparisonPrintLayout,
        totalPageCount: Int,
        selectedPageRange: ComparisonPrintPageRange,
        charactersPerLine: Int,
        pages: [ComparisonPrintPagePlan]
    ) {
        self.title = title
        self.paneTitles = paneTitles
        self.pageSetup = pageSetup
        self.layout = layout
        self.totalPageCount = totalPageCount
        self.selectedPageRange = selectedPageRange
        self.charactersPerLine = charactersPerLine
        self.pages = pages
    }
}

public enum ComparisonPrintingError: Error, LocalizedError, Equatable, Sendable {
    case nonFinitePageGeometry
    case invalidPaperBounds
    case orientationDoesNotMatchPaperBounds
    case invalidImageableBounds
    case imageableBoundsOutsidePaper
    case nonFiniteMargins
    case negativeMargins
    case marginsExcludePrintableArea
    case invalidScale
    case unsupportedPaneCount(Int)
    case rowPaneCountMismatch(rowIndex: Int, expected: Int, actual: Int)
    case invalidLineNumber(rowIndex: Int, paneIndex: Int, value: Int)
    case nonFiniteLayoutMetric(String)
    case invalidLayoutMetric(String)
    case invalidTabWidth(Int)
    case printableAreaTooSmall
    case invalidPageRange(firstPage: Int, lastPage: Int)
    case pageRangeOutOfBounds(firstPage: Int, lastPage: Int, pageCount: Int)
    case invalidLimit(name: String, value: Int)
    case tooManyRows(maximum: Int)
    case inputTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximum: Int)
    case tooManyPages(maximum: Int)
    case outputTooLarge(maximumBytes: Int)
    case tooManyOutputItems(maximum: Int)
    case arithmeticOverflow

    public var errorDescription: String? {
        switch self {
        case .nonFinitePageGeometry:
            "Paper and imageable bounds must contain only finite values."
        case .invalidPaperBounds:
            "Paper bounds must have positive width and height."
        case .orientationDoesNotMatchPaperBounds:
            "Paper bounds must match the selected portrait or landscape orientation."
        case .invalidImageableBounds:
            "Imageable bounds must have positive width and height."
        case .imageableBoundsOutsidePaper:
            "Imageable bounds must be contained within paper bounds."
        case .nonFiniteMargins:
            "Print margins must contain only finite values."
        case .negativeMargins:
            "Print margins must not be negative."
        case .marginsExcludePrintableArea:
            "Print margins and imageable bounds leave no printable area."
        case .invalidScale:
            "Print scale must be finite and between 1% and 1000%."
        case .unsupportedPaneCount(let count):
            "Comparison printing requires two or three panes, not \(count)."
        case .rowPaneCountMismatch(let rowIndex, let expected, let actual):
            "Print row \(Self.oneBasedDescription(of: rowIndex)) has \(actual) panes; expected \(expected)."
        case .invalidLineNumber(let rowIndex, let paneIndex, let value):
            "Print row \(Self.oneBasedDescription(of: rowIndex)), pane \(Self.oneBasedDescription(of: paneIndex)) has invalid line number \(value)."
        case .nonFiniteLayoutMetric(let name):
            "Print layout metric \(name) must be finite."
        case .invalidLayoutMetric(let name):
            "Print layout metric \(name) is outside its valid range."
        case .invalidTabWidth(let value):
            "Print tab width must be between 1 and 32 columns, not \(value)."
        case .printableAreaTooSmall:
            "Printable area cannot fit one comparison text line."
        case .invalidPageRange(let firstPage, let lastPage):
            "Print page range must be positive and ordered, not \(firstPage)...\(lastPage)."
        case .pageRangeOutOfBounds(let firstPage, let lastPage, let pageCount):
            "Print page range \(firstPage)...\(lastPage) exceeds the \(pageCount)-page document."
        case .invalidLimit(let name, let value):
            "Print limit \(name) must be positive, not \(value)."
        case .tooManyRows(let maximum):
            "Comparison print input exceeds the \(maximum)-row limit."
        case .inputTooLarge(let maximumBytes):
            "Comparison print input exceeds the \(maximumBytes)-byte UTF-8 limit."
        case .workLimitExceeded(let maximum):
            "Comparison print planning exceeds the \(maximum)-unit work limit."
        case .tooManyPages(let maximum):
            "Comparison print output exceeds the \(maximum)-page limit."
        case .outputTooLarge(let maximumBytes):
            "Comparison print plan exceeds the \(maximumBytes)-byte UTF-8 output limit."
        case .tooManyOutputItems(let maximum):
            "Comparison print plan exceeds the \(maximum)-item output limit."
        case .arithmeticOverflow:
            "Comparison print geometry or resource accounting overflowed."
        }
    }

    private static func oneBasedDescription(of zeroBasedIndex: Int) -> String {
        if zeroBasedIndex >= 0 {
            return String(UInt(zeroBasedIndex) + 1)
        }
        return String(zeroBasedIndex + 1)
    }
}

public enum ComparisonPrintPlanner: Sendable {
    /// Paginates all rows, while retaining page payload only for `pageRange` when supplied.
    /// The complete document is still inspected so page counts and `pageNumberAndCount` stay exact.
    public static func planPreview(
        document: ComparisonPrintDocument,
        pageSetup: ComparisonPrintPageSetup,
        layout: ComparisonPrintLayout = .default,
        headerFooter: ComparisonPrintHeaderFooter = .default,
        pageRange: ComparisonPrintPageRange? = nil,
        limits: ComparisonPrintLimits = .default
    ) throws -> ComparisonPrintPreviewPlan {
        try Task.checkCancellation()
        try validate(limits: limits)
        try validate(layout: layout, headerFooter: headerFooter)

        var work = ComparisonPrintWorkBudget(maximum: limits.maximumWork)
        let maximumLineNumber = try validate(
            document: document,
            headerFooter: headerFooter,
            limits: limits,
            work: &work
        )
        let effectiveLayout = try layoutExpandingLineNumberColumn(
            layout,
            maximumLineNumber: maximumLineNumber
        )
        let metrics = try pageMetrics(
            paneCount: document.paneTitles.count,
            pageSetup: pageSetup,
            layout: effectiveLayout,
            headerFooter: headerFooter
        )

        var output = ComparisonPrintOutputBudget(
            maximumBytes: limits.maximumOutputBytes,
            maximumItems: limits.maximumOutputItems
        )
        try output.consume(document.title)
        for paneTitle in document.paneTitles {
            try output.consume(paneTitle)
        }

        var pageNumber = 1
        var usedHeight: CGFloat = 0
        var storedFragments: [ComparisonPrintRowFragment] = []
        var drafts: [ComparisonPrintPageDraft] = []

        func storesPage(_ number: Int) -> Bool {
            guard let pageRange else { return true }
            return pageRange.closedRange.contains(number)
        }

        func finishPage() {
            if storesPage(pageNumber) {
                drafts.append(
                    ComparisonPrintPageDraft(
                        pageNumber: pageNumber,
                        rowFragments: storedFragments
                    ))
            }
            storedFragments = []
        }

        func advancePage() throws {
            finishPage()
            let (nextPage, overflow) = pageNumber.addingReportingOverflow(1)
            guard !overflow else { throw ComparisonPrintingError.arithmeticOverflow }
            guard nextPage <= limits.maximumPages else {
                throw ComparisonPrintingError.tooManyPages(maximum: limits.maximumPages)
            }
            pageNumber = nextPage
            usedHeight = 0
        }

        for (rowIndex, row) in document.rows.enumerated() {
            try work.consume(1)
            var temporary = ComparisonPrintTemporaryBudget(maximum: limits.maximumWork)
            var wrappedCells: [[String]] = []
            wrappedCells.reserveCapacity(row.cells.count)
            for cell in row.cells {
                wrappedCells.append(
                    try wrappedLines(
                        cell.text,
                        maximumColumns: metrics.charactersPerLine,
                        tabWidth: layout.tabWidth,
                        work: &work,
                        temporary: &temporary
                    ))
            }
            let visualLineCount = wrappedCells.map(\.count).max() ?? 1
            var lineOffset = 0

            while lineOffset < visualLineCount {
                try work.consume(1)
                let isFirstFragment = lineOffset == 0
                let topPadding = isFirstFragment ? metrics.verticalCellPadding : 0
                let availableHeight = metrics.bodyBounds.height - usedHeight
                guard availableHeight.isFinite else {
                    throw ComparisonPrintingError.arithmeticOverflow
                }
                if isFirstFragment, usedHeight > 0 {
                    let completeRowHeight =
                        2 * metrics.verticalCellPadding
                        + CGFloat(visualLineCount) * metrics.lineHeight
                    guard completeRowHeight.isFinite else {
                        throw ComparisonPrintingError.arithmeticOverflow
                    }
                    if completeRowHeight <= metrics.bodyBounds.height,
                        completeRowHeight > availableHeight
                    {
                        try advancePage()
                        continue
                    }
                }
                if topPadding + metrics.lineHeight > availableHeight {
                    if usedHeight > 0 {
                        try advancePage()
                        continue
                    }
                    throw ComparisonPrintingError.printableAreaTooSmall
                }

                let lineCapacityValue = ((availableHeight - topPadding) / metrics.lineHeight).rounded(.down)
                guard lineCapacityValue.isFinite,
                    let lineCapacity = Int(exactly: lineCapacityValue),
                    lineCapacity >= 1
                else {
                    throw ComparisonPrintingError.arithmeticOverflow
                }
                let remainingLines = visualLineCount - lineOffset
                var lineCount = min(remainingLines, lineCapacity)
                if lineCount == remainingLines {
                    let completeHeight =
                        topPadding
                        + CGFloat(lineCount) * metrics.lineHeight
                        + metrics.verticalCellPadding
                    guard completeHeight.isFinite else {
                        throw ComparisonPrintingError.arithmeticOverflow
                    }
                    if completeHeight > availableHeight {
                        if lineCount > 1 {
                            lineCount -= 1
                        } else if usedHeight > 0 {
                            try advancePage()
                            continue
                        } else {
                            throw ComparisonPrintingError.printableAreaTooSmall
                        }
                    }
                }
                guard lineCount > 0 else {
                    throw ComparisonPrintingError.printableAreaTooSmall
                }

                let (lineEnd, lineEndOverflow) = lineOffset.addingReportingOverflow(lineCount)
                guard !lineEndOverflow else { throw ComparisonPrintingError.arithmeticOverflow }
                let isLastFragment = lineEnd == visualLineCount
                let fragmentHeight =
                    topPadding
                    + CGFloat(lineCount) * metrics.lineHeight
                    + (isLastFragment ? metrics.verticalCellPadding : 0)
                let frameY = metrics.bodyBounds.maxY - usedHeight - fragmentHeight
                guard fragmentHeight.isFinite, frameY.isFinite else {
                    throw ComparisonPrintingError.arithmeticOverflow
                }
                let lineRange = lineOffset..<lineEnd

                if storesPage(pageNumber) {
                    try output.consumeItem()
                    var cellFragments: [ComparisonPrintCellFragment] = []
                    cellFragments.reserveCapacity(row.cells.count)
                    for paneIndex in row.cells.indices {
                        try output.consumeItem()
                        var lines: [String] = []
                        lines.reserveCapacity(lineCount)
                        for visualLine in lineRange {
                            try work.consume(1)
                            let line =
                                visualLine < wrappedCells[paneIndex].count
                                ? wrappedCells[paneIndex][visualLine]
                                : ""
                            try output.consume(line)
                            lines.append(line)
                        }
                        cellFragments.append(
                            ComparisonPrintCellFragment(
                                lineNumber: isFirstFragment ? row.cells[paneIndex].lineNumber : nil,
                                lines: lines
                            ))
                    }
                    storedFragments.append(
                        ComparisonPrintRowFragment(
                            sourceRowIndex: rowIndex,
                            visualLineRange: lineRange,
                            cells: cellFragments,
                            frame: ComparisonPrintRect(
                                x: metrics.bodyBounds.minX,
                                y: frameY,
                                width: metrics.bodyBounds.width,
                                height: fragmentHeight
                            ),
                            isContinuation: !isFirstFragment,
                            isContinued: !isLastFragment
                        ))
                }

                usedHeight += fragmentHeight
                guard usedHeight.isFinite else {
                    throw ComparisonPrintingError.arithmeticOverflow
                }
                lineOffset = lineEnd
                if lineOffset < visualLineCount {
                    try advancePage()
                }
            }
        }
        finishPage()

        let totalPageCount = pageNumber
        let selectedRange: ComparisonPrintPageRange
        if let pageRange {
            guard pageRange.lastPage <= totalPageCount else {
                throw ComparisonPrintingError.pageRangeOutOfBounds(
                    firstPage: pageRange.firstPage,
                    lastPage: pageRange.lastPage,
                    pageCount: totalPageCount
                )
            }
            selectedRange = pageRange
        } else {
            selectedRange = try ComparisonPrintPageRange(
                firstPage: 1,
                lastPage: totalPageCount
            )
        }

        var pages: [ComparisonPrintPagePlan] = []
        pages.reserveCapacity(drafts.count)
        for draft in drafts {
            try work.consume(1)
            try output.consumeItem()
            let headerText = resolved(
                headerFooter.header,
                title: document.title,
                pageNumber: draft.pageNumber,
                pageCount: totalPageCount
            )
            let footerText = resolved(
                headerFooter.footer,
                title: document.title,
                pageNumber: draft.pageNumber,
                pageCount: totalPageCount
            )
            if let headerText { try output.consume(headerText) }
            if let footerText { try output.consume(footerText) }
            pages.append(
                ComparisonPrintPagePlan(
                    pageNumber: draft.pageNumber,
                    paperBounds: pageSetup.paperBounds,
                    printableBounds: pageSetup.printableBounds,
                    headerBounds: metrics.headerBounds,
                    footerBounds: metrics.footerBounds,
                    headerText: headerText,
                    footerText: footerText,
                    paneHeaderBounds: metrics.paneHeaderBounds,
                    paneContentBounds: metrics.paneContentBounds,
                    rowFragments: draft.rowFragments
                ))
        }

        try Task.checkCancellation()
        return ComparisonPrintPreviewPlan(
            title: document.title,
            paneTitles: document.paneTitles,
            pageSetup: pageSetup,
            layout: effectiveLayout,
            totalPageCount: totalPageCount,
            selectedPageRange: selectedRange,
            charactersPerLine: metrics.charactersPerLine,
            pages: pages
        )
    }

    private static func validate(limits: ComparisonPrintLimits) throws {
        for (name, value) in [
            ("maximumRows", limits.maximumRows),
            ("maximumInputBytes", limits.maximumInputBytes),
            ("maximumWork", limits.maximumWork),
            ("maximumPages", limits.maximumPages),
            ("maximumOutputBytes", limits.maximumOutputBytes),
            ("maximumOutputItems", limits.maximumOutputItems)
        ] where value <= 0 {
            throw ComparisonPrintingError.invalidLimit(name: name, value: value)
        }
    }

    private static func validate(
        layout: ComparisonPrintLayout,
        headerFooter: ComparisonPrintHeaderFooter
    ) throws {
        let positiveMetrics: [(String, CGFloat)] = [
            ("characterWidth", layout.characterWidth),
            ("lineHeight", layout.lineHeight)
        ]
        let nonnegativeMetrics: [(String, CGFloat)] = [
            ("horizontalCellPadding", layout.horizontalCellPadding),
            ("verticalCellPadding", layout.verticalCellPadding),
            ("paneSpacing", layout.paneSpacing),
            ("lineNumberColumnWidth", layout.lineNumberColumnWidth),
            ("paneTitleHeight", layout.paneTitleHeight),
            ("headerFooter.bandHeight", headerFooter.bandHeight)
        ]
        for (name, value) in positiveMetrics + nonnegativeMetrics where !value.isFinite {
            throw ComparisonPrintingError.nonFiniteLayoutMetric(name)
        }
        for (name, value) in positiveMetrics where value <= 0 {
            throw ComparisonPrintingError.invalidLayoutMetric(name)
        }
        for (name, value) in nonnegativeMetrics where value < 0 {
            throw ComparisonPrintingError.invalidLayoutMetric(name)
        }
        if headerFooter.header != nil || headerFooter.footer != nil {
            guard headerFooter.bandHeight > 0 else {
                throw ComparisonPrintingError.invalidLayoutMetric("headerFooter.bandHeight")
            }
        }
        guard (1...32).contains(layout.tabWidth) else {
            throw ComparisonPrintingError.invalidTabWidth(layout.tabWidth)
        }
    }

    private static func validate(
        document: ComparisonPrintDocument,
        headerFooter: ComparisonPrintHeaderFooter,
        limits: ComparisonPrintLimits,
        work: inout ComparisonPrintWorkBudget
    ) throws -> Int? {
        let paneCount = document.paneTitles.count
        guard paneCount == 2 || paneCount == 3 else {
            throw ComparisonPrintingError.unsupportedPaneCount(paneCount)
        }
        guard document.rows.count <= limits.maximumRows else {
            throw ComparisonPrintingError.tooManyRows(maximum: limits.maximumRows)
        }

        var remainingInputBytes = limits.maximumInputBytes
        func consumeInput(_ value: String) throws {
            var byteCount = 0
            for _ in value.utf8 {
                guard byteCount < remainingInputBytes else {
                    throw ComparisonPrintingError.inputTooLarge(
                        maximumBytes: limits.maximumInputBytes
                    )
                }
                byteCount += 1
                if byteCount.isMultiple(of: 4_096) {
                    try work.consume(4_096)
                }
            }
            let remainder = byteCount % 4_096
            if remainder > 0 {
                try work.consume(remainder)
            }
            remainingInputBytes -= byteCount
            if byteCount == 0 { try work.consume(1) }
        }

        try consumeInput(document.title)
        for paneTitle in document.paneTitles {
            try consumeInput(paneTitle)
        }
        if case .text(let text) = headerFooter.header {
            try consumeInput(text)
        }
        if case .text(let text) = headerFooter.footer {
            try consumeInput(text)
        }
        var maximumLineNumber: Int?
        for (rowIndex, row) in document.rows.enumerated() {
            try work.consume(1)
            guard row.cells.count == paneCount else {
                throw ComparisonPrintingError.rowPaneCountMismatch(
                    rowIndex: rowIndex,
                    expected: paneCount,
                    actual: row.cells.count
                )
            }
            for (paneIndex, cell) in row.cells.enumerated() {
                if let lineNumber = cell.lineNumber {
                    guard lineNumber > 0 else {
                        throw ComparisonPrintingError.invalidLineNumber(
                            rowIndex: rowIndex,
                            paneIndex: paneIndex,
                            value: lineNumber
                        )
                    }
                    maximumLineNumber = max(maximumLineNumber ?? lineNumber, lineNumber)
                }
                try consumeInput(cell.text)
            }
        }
        return maximumLineNumber
    }

    private static func layoutExpandingLineNumberColumn(
        _ layout: ComparisonPrintLayout,
        maximumLineNumber: Int?
    ) throws -> ComparisonPrintLayout {
        guard let maximumLineNumber else { return layout }
        let requiredWidth = CGFloat(String(maximumLineNumber).utf8.count) * layout.characterWidth
        guard requiredWidth.isFinite else {
            throw ComparisonPrintingError.arithmeticOverflow
        }
        guard requiredWidth > layout.lineNumberColumnWidth else { return layout }
        return ComparisonPrintLayout(
            characterWidth: layout.characterWidth,
            lineHeight: layout.lineHeight,
            horizontalCellPadding: layout.horizontalCellPadding,
            verticalCellPadding: layout.verticalCellPadding,
            paneSpacing: layout.paneSpacing,
            lineNumberColumnWidth: requiredWidth,
            paneTitleHeight: layout.paneTitleHeight,
            tabWidth: layout.tabWidth
        )
    }

    private static func pageMetrics(
        paneCount: Int,
        pageSetup: ComparisonPrintPageSetup,
        layout: ComparisonPrintLayout,
        headerFooter: ComparisonPrintHeaderFooter
    ) throws -> ComparisonPrintPageMetrics {
        let scale = pageSetup.scale
        let scaledCharacterWidth = layout.characterWidth * scale
        let scaledLineHeight = layout.lineHeight * scale
        let scaledHorizontalPadding = layout.horizontalCellPadding * scale
        let scaledVerticalPadding = layout.verticalCellPadding * scale
        let scaledPaneSpacing = layout.paneSpacing * scale
        let scaledLineNumberWidth = layout.lineNumberColumnWidth * scale
        let scaledPaneTitleHeight = layout.paneTitleHeight * scale
        let scaledValues = [
            scaledCharacterWidth,
            scaledLineHeight,
            scaledHorizontalPadding,
            scaledVerticalPadding,
            scaledPaneSpacing,
            scaledLineNumberWidth,
            scaledPaneTitleHeight
        ]
        guard scaledValues.allSatisfy(\.isFinite),
            scaledCharacterWidth > 0,
            scaledLineHeight > 0
        else {
            throw ComparisonPrintingError.arithmeticOverflow
        }

        let printable = pageSetup.printableBounds
        let headerHeight = headerFooter.header == nil ? 0 : headerFooter.bandHeight
        let footerHeight = headerFooter.footer == nil ? 0 : headerFooter.bandHeight
        let headerBounds = headerFooter.header.map { _ in
            ComparisonPrintRect(
                x: printable.minX,
                y: printable.maxY - headerHeight,
                width: printable.width,
                height: headerHeight
            )
        }
        let footerBounds = headerFooter.footer.map { _ in
            ComparisonPrintRect(
                x: printable.minX,
                y: printable.minY,
                width: printable.width,
                height: footerHeight
            )
        }
        let bodyMinY = printable.minY + footerHeight
        let paneHeaderMaxY = printable.maxY - headerHeight
        let bodyMaxY = paneHeaderMaxY - scaledPaneTitleHeight
        let bodyHeight = bodyMaxY - bodyMinY
        guard bodyMinY.isFinite,
            paneHeaderMaxY.isFinite,
            bodyMaxY.isFinite,
            bodyHeight.isFinite
        else {
            throw ComparisonPrintingError.arithmeticOverflow
        }

        let spacingWidth = scaledPaneSpacing * CGFloat(paneCount - 1)
        let panesWidth = printable.width - spacingWidth
        let paneWidth = panesWidth / CGFloat(paneCount)
        let textWidth =
            paneWidth
            - 2 * scaledHorizontalPadding
            - scaledLineNumberWidth
        guard spacingWidth.isFinite,
            panesWidth.isFinite,
            paneWidth.isFinite,
            textWidth.isFinite,
            paneWidth > 0,
            textWidth >= scaledCharacterWidth
        else {
            throw ComparisonPrintingError.printableAreaTooSmall
        }
        let characterCapacity = (textWidth / scaledCharacterWidth).rounded(.down)
        guard characterCapacity.isFinite,
            let charactersPerLine = Int(exactly: characterCapacity),
            charactersPerLine >= 1
        else {
            throw ComparisonPrintingError.arithmeticOverflow
        }

        let minimumRowHeight = 2 * scaledVerticalPadding + scaledLineHeight
        guard minimumRowHeight.isFinite,
            bodyHeight >= minimumRowHeight
        else {
            throw ComparisonPrintingError.printableAreaTooSmall
        }

        var paneHeaderBounds: [ComparisonPrintRect] = []
        var paneContentBounds: [ComparisonPrintRect] = []
        paneHeaderBounds.reserveCapacity(paneCount)
        paneContentBounds.reserveCapacity(paneCount)
        for paneIndex in 0..<paneCount {
            let paneX =
                printable.minX
                + CGFloat(paneIndex) * (paneWidth + scaledPaneSpacing)
            guard paneX.isFinite else { throw ComparisonPrintingError.arithmeticOverflow }
            paneHeaderBounds.append(
                ComparisonPrintRect(
                    x: paneX,
                    y: bodyMaxY,
                    width: paneWidth,
                    height: scaledPaneTitleHeight
                ))
            paneContentBounds.append(
                ComparisonPrintRect(
                    x: paneX,
                    y: bodyMinY,
                    width: paneWidth,
                    height: bodyHeight
                ))
        }

        return ComparisonPrintPageMetrics(
            headerBounds: headerBounds,
            footerBounds: footerBounds,
            paneHeaderBounds: paneHeaderBounds,
            paneContentBounds: paneContentBounds,
            bodyBounds: ComparisonPrintRect(
                x: printable.minX,
                y: bodyMinY,
                width: printable.width,
                height: bodyHeight
            ),
            lineHeight: scaledLineHeight,
            verticalCellPadding: scaledVerticalPadding,
            charactersPerLine: charactersPerLine
        )
    }

    private static func wrappedLines(
        _ text: String,
        maximumColumns: Int,
        tabWidth: Int,
        work: inout ComparisonPrintWorkBudget,
        temporary: inout ComparisonPrintTemporaryBudget
    ) throws -> [String] {
        var lines: [String] = []
        var currentLine = ""
        var column = 0

        func appendLine() throws {
            try temporary.consumeItem()
            lines.append(currentLine)
            currentLine = ""
            column = 0
        }

        func appendUnit(_ unit: String) throws {
            if column == maximumColumns {
                try appendLine()
            }
            let byteCount = unit.utf8.count
            try temporary.consume(bytes: byteCount)
            try work.consume(max(1, byteCount))
            currentLine.append(unit)
            column += 1
        }

        let scalars = text.unicodeScalars
        var scalarIndex = scalars.startIndex
        while scalarIndex < scalars.endIndex {
            let scalar = scalars[scalarIndex]
            let nextIndex = scalars.index(after: scalarIndex)
            if scalar.value == 0x0D {
                try work.consume(1)
                try appendLine()
                if nextIndex < scalars.endIndex, scalars[nextIndex].value == 0x0A {
                    scalarIndex = scalars.index(after: nextIndex)
                    continue
                }
            } else if scalar.value == 0x0A
                || scalar.value == 0x2028
                || scalar.value == 0x2029
            {
                try work.consume(1)
                try appendLine()
            } else if scalar.value == 0x09 {
                if column == maximumColumns {
                    try appendLine()
                }
                let spaceCount = tabWidth - column % tabWidth
                for _ in 0..<spaceCount {
                    try appendUnit(" ")
                }
            } else {
                try appendUnit(String(scalar))
            }
            scalarIndex = nextIndex
        }
        try appendLine()
        return lines
    }

    private static func resolved(
        _ label: ComparisonPrintPageLabel?,
        title: String,
        pageNumber: Int,
        pageCount: Int
    ) -> String? {
        switch label {
        case nil:
            nil
        case .text(let text):
            text
        case .documentTitle:
            title
        case .pageNumber:
            String(pageNumber)
        case .pageNumberAndCount:
            "\(pageNumber) of \(pageCount)"
        }
    }
}

private struct ComparisonPrintPageMetrics {
    let headerBounds: ComparisonPrintRect?
    let footerBounds: ComparisonPrintRect?
    let paneHeaderBounds: [ComparisonPrintRect]
    let paneContentBounds: [ComparisonPrintRect]
    let bodyBounds: ComparisonPrintRect
    let lineHeight: CGFloat
    let verticalCellPadding: CGFloat
    let charactersPerLine: Int
}

private struct ComparisonPrintPageDraft {
    let pageNumber: Int
    let rowFragments: [ComparisonPrintRowFragment]
}

private struct ComparisonPrintWorkBudget {
    private var consumed = 0
    private var nextCancellationCheck = 0
    private let maximum: Int

    init(maximum: Int) {
        self.maximum = maximum
    }

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= maximum - consumed else {
            throw ComparisonPrintingError.workLimitExceeded(maximum: maximum)
        }
        consumed += amount
        if consumed >= nextCancellationCheck {
            try Task.checkCancellation()
            let (next, overflow) = consumed.addingReportingOverflow(4_096)
            nextCancellationCheck = overflow ? .max : next
        }
    }
}

private struct ComparisonPrintTemporaryBudget {
    private var consumed = 0
    private let maximum: Int

    init(maximum: Int) {
        self.maximum = maximum
    }

    mutating func consume(bytes: Int) throws {
        try consume(bytes)
    }

    mutating func consumeItem() throws {
        try consume(MemoryLayout<String>.stride)
    }

    private mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= maximum - consumed else {
            throw ComparisonPrintingError.workLimitExceeded(maximum: maximum)
        }
        consumed += amount
    }
}

private struct ComparisonPrintOutputBudget {
    private var byteCount = 0
    private var itemCount = 0
    private let maximumBytes: Int
    private let maximumItems: Int

    init(maximumBytes: Int, maximumItems: Int) {
        self.maximumBytes = maximumBytes
        self.maximumItems = maximumItems
    }

    mutating func consume(_ string: String) throws {
        try consumeItem()
        let addedBytes = string.utf8.count
        guard addedBytes <= maximumBytes - byteCount else {
            throw ComparisonPrintingError.outputTooLarge(maximumBytes: maximumBytes)
        }
        byteCount += addedBytes
    }

    mutating func consumeItem() throws {
        guard itemCount < maximumItems else {
            throw ComparisonPrintingError.tooManyOutputItems(maximum: maximumItems)
        }
        itemCount += 1
    }
}
