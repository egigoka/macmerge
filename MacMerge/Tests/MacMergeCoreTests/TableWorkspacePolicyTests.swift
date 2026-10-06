import Foundation
import MacMergeCore
import XCTest

final class TableWorkspacePolicyTests: XCTestCase {
    func testSettingsForwardEveryParserComparisonAndPresentationOption() {
        let parsing = TableWorkspaceParsingLimits(
            maximumInputBytes: 101,
            maximumRows: 102,
            maximumColumnsPerRow: 103,
            maximumTotalCells: 104,
            maximumCellBytes: 105
        )
        let format = TableWorkspaceFormatSettings(
            delimiter: "|",
            quote: "'",
            allowsNewlinesInQuotedCells: false,
            limits: parsing
        )
        let comparison = TableWorkspaceComparisonSettings(
            maximumExactEditDistance: 201,
            maximumAlignmentWork: 202,
            maximumComparedRows: 203,
            maximumComparedCells: 204
        )
        let presentation = TableWorkspacePresentationOptions(
            headerVisibility: .hidden,
            headerLabels: .firstRecord,
            showsRowNumbers: false,
            wrapsCellText: true,
            synchronizesColumnWidths: false,
            highlightsCellDifferences: false
        )

        XCTAssertEqual(format.parsingOptions.delimiter, "|")
        XCTAssertEqual(format.parsingOptions.quote, "'")
        XCTAssertFalse(format.parsingOptions.allowsNewlinesInQuotedCells)
        XCTAssertEqual(format.parsingOptions.limits.maximumInputBytes, 101)
        XCTAssertEqual(format.parsingOptions.limits.maximumRows, 102)
        XCTAssertEqual(format.parsingOptions.limits.maximumColumnsPerRow, 103)
        XCTAssertEqual(format.parsingOptions.limits.maximumTotalCells, 104)
        XCTAssertEqual(format.parsingOptions.limits.maximumCellBytes, 105)
        XCTAssertEqual(comparison.comparisonOptions.maximumExactEditDistance, 201)
        XCTAssertEqual(comparison.comparisonOptions.maximumAlignmentWork, 202)
        XCTAssertEqual(comparison.comparisonOptions.maximumComparedRows, 203)
        XCTAssertEqual(comparison.comparisonOptions.maximumComparedCells, 204)
        XCTAssertEqual(TableWorkspaceFormatSettings.tabSeparated.delimiter, "\t")
        XCTAssertEqual(TableWorkspaceConfiguration(format: format, comparison: comparison).format, format)
        XCTAssertEqual(presentation.headerVisibility, .hidden)
        XCTAssertEqual(presentation.headerLabels, .firstRecord)
        XCTAssertFalse(presentation.showsRowNumbers)
        XCTAssertTrue(presentation.wrapsCellText)
        XCTAssertFalse(presentation.synchronizesColumnWidths)
        XCTAssertFalse(presentation.highlightsCellDifferences)
    }

    func testExecutorUsesNondefaultParserAndComparisonSettingsEndToEnd() async throws {
        let configuration = TableWorkspaceConfiguration(
            format: TableWorkspaceFormatSettings(
                delimiter: "|",
                quote: "'",
                allowsNewlinesInQuotedCells: false,
                limits: TableWorkspaceParsingLimits(
                    maximumInputBytes: 32,
                    maximumRows: 2,
                    maximumColumnsPerRow: 2,
                    maximumTotalCells: 4,
                    maximumCellBytes: 3
                )
            ),
            comparison: TableWorkspaceComparisonSettings(
                maximumExactEditDistance: 2,
                maximumAlignmentWork: 32,
                maximumComparedRows: 2,
                maximumComparedCells: 4
            )
        )
        let left = "a|'b'"
        let right = "a|'c'"
        let fixture = try await makeFixture(
            left: left,
            right: right,
            configuration: configuration
        )

        let plan = try TableWorkspacePolicy.plan(fixture.request())

        XCTAssertEqual(fixture.comparisonReceipt.result.left.delimiter, "|")
        XCTAssertEqual(fixture.comparisonReceipt.result.left.quote, "'")
        XCTAssertEqual(fixture.comparisonReceipt.result.left.rows[0].values, ["a", "b"])
        XCTAssertEqual(fixture.comparisonReceipt.result.right.rows[0].values, ["a", "c"])
        XCTAssertEqual(plan.presentation.rows[0].cells.map(\.status), [.equal, .modified])
        XCTAssertTrue(try XCTUnwrap(plan.presentation.rows[0].cells[1].left).wasQuoted)
        XCTAssertTrue(try XCTUnwrap(plan.presentation.rows[0].cells[1].right).wasQuoted)
    }

    func testDatasetAndStateCanonicalizeExactLeftRightBindings() throws {
        let left = try makeBinding(side: .left, input: "left")
        let right = try makeBinding(side: .right, input: "right")
        let reference = makeReference()
        let dataset = TableWorkspaceDatasetSnapshot(
            reference: reference,
            configuration: .default,
            sources: [right, left]
        )
        let state = TableWorkspaceState(
            datasetReference: reference,
            sources: [right, left],
            configuration: .default
        )

        XCTAssertEqual(dataset.sources, [left, right])
        XCTAssertEqual(state.sources, [left, right])
        XCTAssertEqual(dataset.source(.left), left)
        XCTAssertEqual(dataset.source(.right), right)
        XCTAssertEqual(state.source(.left), left)
        XCTAssertEqual(state.source(.right), right)
        XCTAssertEqual(TableWorkspaceSide.allCases, [.left, .right])
    }

    func testExecutorContractsAndOpaqueReceiptsExposeRequiredAuthority() async throws {
        let fixture = try await makeFixture()
        let contract = TableWorkspaceExecutorContract.required

        XCTAssertEqual(
            contract.datasetLease,
            .immutableExactSourceAndTableRevisionsHeldDuringPlanningAndRevalidatedBeforeExecution
        )
        XCTAssertEqual(
            contract.comparisonExecution,
            .authoritativeDelimitedTableParserAndTableComparisonOnly
        )
        XCTAssertEqual(
            contract.editExecution,
            .losslessAuthoritativeEditorReparsesAndPublishesNewRevisionsOrMakesNoChange
        )
        XCTAssertEqual(
            contract.cancellation,
            .cancellableBeforeCommitWithExactOutcomeRequiredAfterCommitStarts
        )
        XCTAssertEqual(contract.receipts, .applyOnlyWithAtomicExactDatasetRevisionCompareAndSwap)
        XCTAssertEqual(fixture.comparisonReceipt.executorContract, contract)

        let plan = try TableWorkspacePolicy.plan(fixture.request())
        XCTAssertEqual(plan.executorContract, contract)
        XCTAssertEqual(plan.receipt.executorContract, contract)
    }

    func testAuthoritativeExecutorParsesReturnedBytesAndPreservesSourceMetadata() async throws {
        let boundInput = "a"
        let returnedInput = "b"
        let left = try makeBinding(side: .left, input: boundInput)
        let right = try makeBinding(side: .right, input: boundInput)
        let dataset = makeDataset(sources: [right, left])
        let executor = WorkspaceExecutor(
            sourceData: [.left: Data(returnedInput.utf8), .right: Data(boundInput.utf8)]
        )

        let receipt = try await executor.compare(dataset: dataset)
        let state = makeState(dataset: dataset)
        let plan = try TableWorkspacePolicy.plan(
            TableWorkspaceRequest(comparisonReceipt: receipt, state: state)
        )

        XCTAssertEqual(receipt.result.left.rows[0].values, [returnedInput])
        XCTAssertEqual(receipt.result.right.rows[0].values, [boundInput])
        let presentedValue = try XCTUnwrap(plan.presentation.rows[0].cells[0].left)
        XCTAssertEqual(presentedValue.value, returnedInput)
        XCTAssertEqual(presentedValue.sourceUTF8Range, 0..<1)
        XCTAssertEqual(presentedValue.sourceLine, 1)
        XCTAssertEqual(presentedValue.sourceColumn, 1)
        XCTAssertFalse(presentedValue.wasQuoted)
    }

    func testPresentationPreservesDistinctQuotedMultilineMetadataOnBothSides() async throws {
        let left = "\"left\",\"line 1\nline 2\"\nnext,value"
        let right = "\"R\",\"two\nlines\"\nlast,value"
        let fixture = try await makeFixture(left: left, right: right)
        let plan = try TableWorkspacePolicy.plan(fixture.request())
        let leftValue = try XCTUnwrap(plan.presentation.rows[0].cells[1].left)
        let rightValue = try XCTUnwrap(plan.presentation.rows[0].cells[1].right)

        XCTAssertEqual(leftValue.side, .left)
        XCTAssertEqual(leftValue.value, "line 1\nline 2")
        XCTAssertEqual(leftValue.sourceUTF8Range, 7..<22)
        XCTAssertEqual(leftValue.sourceLine, 1)
        XCTAssertEqual(leftValue.sourceColumn, 8)
        XCTAssertTrue(leftValue.wasQuoted)
        XCTAssertEqual(rightValue.side, .right)
        XCTAssertEqual(rightValue.value, "two\nlines")
        XCTAssertEqual(rightValue.sourceUTF8Range, 4..<15)
        XCTAssertEqual(rightValue.sourceLine, 1)
        XCTAssertEqual(rightValue.sourceColumn, 5)
        XCTAssertTrue(rightValue.wasQuoted)
        XCTAssertEqual(plan.presentation.rows[1].cells[0].left?.sourceLine, 3)
        XCTAssertEqual(plan.presentation.rows[1].cells[0].right?.sourceLine, 3)
    }

    func testExecutorRejectsSourceByteCountMismatchBeforeParsing() async throws {
        let left = try makeBinding(side: .left, input: "a")
        let right = try makeBinding(side: .right, input: "b")
        let dataset = makeDataset(sources: [left, right])
        let executor = WorkspaceExecutor(
            sourceData: [.left: Data("too-long".utf8), .right: Data("b".utf8)]
        )

        await assertPolicyError(.shapeMismatch(.left)) {
            try await executor.compare(dataset: dataset)
        }
    }

    func testExecutorRejectsInvalidUTF8BeforeParsing() async throws {
        let left = try makeBinding(side: .left, input: "a")
        let right = try makeBinding(side: .right, input: "b")
        let dataset = makeDataset(sources: [left, right])
        let executor = WorkspaceExecutor(sourceData: [.left: Data([0xFF]), .right: Data("b".utf8)])

        await assertPolicyError(.shapeMismatch(.left)) {
            try await executor.compare(dataset: dataset)
        }
    }

    func testExecutorRejectsParsedShapeDifferentFromBoundArtifact() async throws {
        let left = try makeBinding(side: .left, input: "a,b")
        let right = try makeBinding(side: .right, input: "x")
        let dataset = makeDataset(sources: [left, right])
        let executor = WorkspaceExecutor(
            sourceData: [.left: Data("abc".utf8), .right: Data("x".utf8)]
        )

        await assertPolicyError(.shapeMismatch(.left)) {
            try await executor.compare(dataset: dataset)
        }
    }

    func testExecutorRejectsBoundRowColumnAndTotalShapeMutationsIndependently() async throws {
        let input = "a,b\nc,d"
        let exact = try makeBinding(side: .left, input: input)
        let right = try makeBinding(side: .right, input: "x")
        let mutations: [(String, TableWorkspaceTableShape)] = [
            (
                "rows",
                TableWorkspaceTableShape(
                    sourceUTF8ByteCount: exact.shape.sourceUTF8ByteCount,
                    rowCount: exact.shape.rowCount + 1,
                    maximumColumnCount: exact.shape.maximumColumnCount,
                    totalCellCount: exact.shape.totalCellCount
                )
            ),
            (
                "columns",
                TableWorkspaceTableShape(
                    sourceUTF8ByteCount: exact.shape.sourceUTF8ByteCount,
                    rowCount: exact.shape.rowCount,
                    maximumColumnCount: exact.shape.maximumColumnCount + 1,
                    totalCellCount: exact.shape.totalCellCount
                )
            ),
            (
                "total",
                TableWorkspaceTableShape(
                    sourceUTF8ByteCount: exact.shape.sourceUTF8ByteCount,
                    rowCount: exact.shape.rowCount,
                    maximumColumnCount: exact.shape.maximumColumnCount,
                    totalCellCount: exact.shape.totalCellCount + 1
                )
            )
        ]

        for (name, shape) in mutations {
            let dataset = makeDataset(sources: [copyBinding(exact, shape: shape), right])
            let executor = WorkspaceExecutor(
                sourceData: [.left: Data(input.utf8), .right: Data("x".utf8)]
            )
            await assertPolicyError(.shapeMismatch(.left), context: name) {
                try await executor.compare(dataset: dataset)
            }
        }
    }

    func testExecutorPropagatesAuthoritativeParserErrors() async throws {
        let left = try makeBinding(side: .left, input: "a")
        let right = try makeBinding(side: .right, input: "b")
        let dataset = makeDataset(sources: [left, right])
        let executor = WorkspaceExecutor(sourceData: [.left: Data([0x22]), .right: Data("b".utf8)])

        do {
            _ = try await executor.compare(dataset: dataset)
            XCTFail("Expected parser failure")
        } catch {
            XCTAssertEqual(
                error as? DelimitedTableParseError,
                .unterminatedQuotedCell(
                    DelimitedTableSourceLocation(line: 1, column: 1, utf8Offset: 0)
                )
            )
        }
    }

    func testExecutorComparisonHonorsPreexistingTaskCancellation() async throws {
        let dataset = try makeDataset(left: "a", right: "b")
        let executor = WorkspaceExecutor(
            sourceData: [.left: Data("a".utf8), .right: Data("b".utf8)]
        )

        let error = await Task.detached { @Sendable [dataset, executor] in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await executor.compare(dataset: dataset)
                return nil as DelimitedTableParseError?
            } catch {
                return error as? DelimitedTableParseError
            }
        }.value

        XCTAssertEqual(error, .cancelled)
    }

    func testDatasetMaximumCellBytesUsesUTF8AtExactBoundary() async throws {
        let exactConfiguration = configuration(maximumCellBytes: 2)
        let exactDataset = try makeDataset(
            left: "\u{E9}",
            right: "x",
            configuration: exactConfiguration
        )
        let exactExecutor = WorkspaceExecutor(
            sourceData: [.left: Data("\u{E9}".utf8), .right: Data("x".utf8)]
        )

        let receipt = try await exactExecutor.compare(dataset: exactDataset)
        XCTAssertEqual(receipt.result.left.rows[0].cells[0].value.utf8.count, 2)

        let overConfiguration = configuration(maximumCellBytes: 1)
        let overDataset = TableWorkspaceDatasetSnapshot(
            reference: exactDataset.reference,
            configuration: overConfiguration,
            sources: exactDataset.sources
        )
        let overExecutor = WorkspaceExecutor(
            sourceData: [.left: Data("\u{E9}".utf8), .right: Data("x".utf8)]
        )
        do {
            _ = try await overExecutor.compare(dataset: overDataset)
            XCTFail("Expected cell byte limit failure")
        } catch {
            XCTAssertEqual(
                error as? DelimitedTableParseError,
                .cellTooLarge(rowIndex: 0, columnIndex: 0, maximumBytes: 1)
            )
        }
    }

    func testExecutorRejectsQuotedNewlineWhenDatasetDisablesIt() async throws {
        let configuration = TableWorkspaceConfiguration(
            format: TableWorkspaceFormatSettings(allowsNewlinesInQuotedCells: false)
        )
        let malformed = "\"line 1\nline 2\""
        let left = try makeBinding(
            side: .left,
            input: String(repeating: "x", count: malformed.utf8.count),
            configuration: configuration
        )
        let right = try makeBinding(side: .right, input: "x", configuration: configuration)
        let dataset = makeDataset(
            sources: [left, right],
            configuration: configuration
        )
        let executor = WorkspaceExecutor(
            sourceData: [.left: Data(malformed.utf8), .right: Data("x".utf8)]
        )

        do {
            _ = try await executor.compare(dataset: dataset)
            XCTFail("Expected quoted-newline rejection")
        } catch {
            XCTAssertEqual(
                error as? DelimitedTableParseError,
                .newlineInQuotedCell(
                    DelimitedTableSourceLocation(line: 1, column: 8, utf8Offset: 7)
                )
            )
        }
    }

    func testMalformedWrongLengthCSVFailsShapeBeforeAuthoritativeParse() async throws {
        let malformed = "\"unterminated"
        let left = try makeBinding(side: .left, input: "a")
        let right = try makeBinding(side: .right, input: "b")
        let dataset = makeDataset(sources: [left, right])
        let executor = WorkspaceExecutor(
            sourceData: [.left: Data(malformed.utf8), .right: Data("b".utf8)]
        )

        await assertPolicyError(.shapeMismatch(.left)) {
            try await executor.compare(dataset: dataset)
        }
    }

    func testAuthoritativeParserRejectsEachDatasetLimitBelowInputShape() async throws {
        let cases: [(DelimitedTableParseError, String, TableWorkspaceParsingLimits)] = [
            (
                .inputTooLarge(maximumBytes: 2),
                "abc",
                TableWorkspaceParsingLimits(maximumInputBytes: 2)
            ),
            (
                .tooManyRows(maximumRows: 1),
                "a\nb",
                TableWorkspaceParsingLimits(maximumRows: 1)
            ),
            (
                .tooManyColumns(rowIndex: 0, maximumColumns: 1),
                "a,b",
                TableWorkspaceParsingLimits(maximumColumnsPerRow: 1)
            ),
            (
                .tooManyCells(maximumCells: 1),
                "a,b",
                TableWorkspaceParsingLimits(maximumTotalCells: 1)
            ),
            (
                .cellTooLarge(rowIndex: 0, columnIndex: 0, maximumBytes: 1),
                "\u{E9}",
                TableWorkspaceParsingLimits(maximumCellBytes: 1)
            )
        ]

        for (expected, input, parsingLimits) in cases {
            let configuration = TableWorkspaceConfiguration(
                format: TableWorkspaceFormatSettings(limits: parsingLimits)
            )
            let left = try makeBinding(side: .left, input: "", configuration: configuration)
            let right = try makeBinding(side: .right, input: "", configuration: configuration)
            let shape = try XCTUnwrap(
                try? makeBinding(side: .left, input: input).shape
            )
            let boundLeft = copyBinding(left, shape: shape)
            let dataset = makeDataset(
                sources: [boundLeft, right],
                configuration: configuration
            )
            let executor = WorkspaceExecutor(
                sourceData: [.left: Data(input.utf8), .right: Data()]
            )

            do {
                _ = try await executor.compare(dataset: dataset)
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? DelimitedTableParseError, expected)
            }
        }
    }

    func testAuthoritativeComparisonRejectsRowAndCellLimitsBelowInputs() async throws {
        let rowConfiguration = TableWorkspaceConfiguration(
            comparison: TableWorkspaceComparisonSettings(maximumComparedRows: 1)
        )
        let rowDataset = try makeDataset(
            left: "a",
            right: "b",
            configuration: rowConfiguration
        )
        do {
            _ = try await WorkspaceExecutor(
                sourceData: [.left: Data("a".utf8), .right: Data("b".utf8)]
            ).compare(dataset: rowDataset)
            XCTFail("Expected compared-row limit")
        } catch {
            XCTAssertEqual(error as? TableComparisonError, .tooManyRows(maximumRows: 1))
        }

        let cellConfiguration = TableWorkspaceConfiguration(
            comparison: TableWorkspaceComparisonSettings(maximumComparedCells: 1)
        )
        let cellDataset = try makeDataset(
            left: "a",
            right: "b",
            configuration: cellConfiguration
        )
        do {
            _ = try await WorkspaceExecutor(
                sourceData: [.left: Data("a".utf8), .right: Data("b".utf8)]
            ).compare(dataset: cellDataset)
            XCTFail("Expected compared-cell limit")
        } catch {
            XCTAssertEqual(error as? TableComparisonError, .tooManyCells(maximumCells: 1))
        }
    }

    func testZeroExactDistanceAndAlignmentWorkUseBoundedFallbackInsteadOfRejectingSettings() async throws {
        let configuration = TableWorkspaceConfiguration(
            comparison: TableWorkspaceComparisonSettings(
                maximumExactEditDistance: 0,
                maximumAlignmentWork: 0,
                maximumComparedRows: 2,
                maximumComparedCells: 2
            )
        )
        let fixture = try await makeFixture(
            left: "left",
            right: "right",
            configuration: configuration
        )

        XCTAssertEqual(fixture.comparisonReceipt.result.alignment, .boundedFallback)
        XCTAssertEqual(fixture.comparisonReceipt.result.rows.map(\.status), [.modified])
    }

    func testExecutorRequiresExactlyTwoSources() async throws {
        let left = try makeBinding(side: .left, input: "a")
        let right = try makeBinding(side: .right, input: "b")
        let executor = WorkspaceExecutor(sourceData: [.left: Data("a".utf8), .right: Data("b".utf8)])

        await assertPolicyError(.sourceCountInvalid(0)) {
            try await executor.compare(dataset: makeDataset(sources: []))
        }
        await assertPolicyError(.sourceCountInvalid(1)) {
            try await executor.compare(dataset: makeDataset(sources: [left]))
        }
        await assertPolicyError(.sourceCountInvalid(3)) {
            try await executor.compare(dataset: makeDataset(sources: [left, right, left]))
        }
    }

    func testExecutorDoubleReceivesExactDatasetAndEachExactBinding() async throws {
        let dataset = try makeDataset(left: "left", right: "right")
        let left = try XCTUnwrap(dataset.source(.left))
        let right = try XCTUnwrap(dataset.source(.right))
        let executor = VerifyingWorkspaceExecutor(
            expectedDataset: dataset,
            expectedSources: [.left: left, .right: right],
            sourceData: [.left: Data("left".utf8), .right: Data("right".utf8)]
        )

        let receipt = try await executor.compare(dataset: dataset)

        XCTAssertEqual(receipt.dataset, dataset)
        XCTAssertEqual(executor.requestedSides, [.left, .right])
        XCTAssertNil(executor.verificationFailure)
    }

    func testExecutorRejectsDuplicateSideBeforeMissingSide() async throws {
        let left = try makeBinding(side: .left, input: "a")
        let duplicate = try makeBinding(side: .left, input: "b", revision: 2)
        let executor = WorkspaceExecutor(sourceData: [.left: Data("a".utf8)])

        await assertPolicyError(.duplicateSide(.left)) {
            try await executor.compare(dataset: makeDataset(sources: [left, duplicate]))
        }

        let right = try makeBinding(side: .right, input: "a")
        let rightDuplicate = try makeBinding(side: .right, input: "b", revision: 2)
        await assertPolicyError(.duplicateSide(.right)) {
            try await executor.compare(dataset: makeDataset(sources: [right, rightDuplicate]))
        }
    }

    func testPresentationProjectsRowsCellsMetadataAndReceiptMetrics() async throws {
        let fixture = try await makeFixture()
        let plan = try TableWorkspacePolicy.plan(fixture.request())
        let presentation = plan.presentation

        XCTAssertEqual(
            presentation.rows.map(\.status),
            [.equal, .removed, .equal, .modified, .equal, .added, .equal]
        )
        XCTAssertEqual(presentation.rows.map(\.leftSourceRowIndex), [0, 1, 2, 3, 4, nil, 5])
        XCTAssertEqual(presentation.rows.map(\.rightSourceRowIndex), [0, nil, 1, 2, 3, 4, 5])
        XCTAssertEqual(presentation.rows[3].cells.map(\.status), [.modified, .equal, .added])
        XCTAssertEqual(presentation.rows[3].cells[0].address, address(3, 0))
        XCTAssertEqual(presentation.rows[3].cells[0].left?.value, "old")
        XCTAssertEqual(presentation.rows[3].cells[0].right?.value, "new")
        XCTAssertEqual(presentation.rows[3].cells[2].right?.value, "extra")
        XCTAssertNil(presentation.rows[3].cells[2].left)
        XCTAssertEqual(presentation.rows[3].cells[0].left?.sourceRowIndex, 3)
        XCTAssertEqual(presentation.rows[3].cells[0].left?.sourceColumnIndex, 0)
        XCTAssertEqual(presentation.datasetReference, fixture.dataset.reference)
        XCTAssertEqual(presentation.comparisonAlignment, fixture.comparisonReceipt.result.alignment)
        XCTAssertEqual(presentation.visibleRowCount, 7)
        XCTAssertEqual(plan.receipt.resultRowCount, 7)
        XCTAssertEqual(plan.receipt.resultCellCount, 15)
        XCTAssertEqual(plan.receipt.visibleRowCount, presentation.visibleRowCount)
        XCTAssertEqual(plan.receipt.presentedUTF8ByteCount, presentation.presentedUTF8ByteCount)
        XCTAssertGreaterThan(plan.receipt.planningWorkUnits, plan.receipt.resultCellCount)

        let expectedBytes = fixture.comparisonReceipt.result.rows.reduce(into: 0) { total, row in
            for cell in row.cells {
                total += cell.left?.value.utf8.count ?? 0
                total += cell.right?.value.utf8.count ?? 0
            }
        }
        XCTAssertEqual(presentation.presentedUTF8ByteCount, expectedBytes)
    }

    func testFirstRecordHeadersRemainOrdinaryRowsAndFlagsArePresentationOnly() async throws {
        let fixture = try await makeFixture(
            left: "left-name,left-value\nremove,left\nanchor,one\nold,keep\nanchor,two\ntail,end",
            right: "right-name,right-value\nanchor,one\nnew,keep,extra\nanchor,two\nadd,right\ntail,end"
        )
        let options = TableWorkspacePresentationOptions(
            headerVisibility: .hidden,
            headerLabels: .firstRecord,
            showsRowNumbers: false,
            wrapsCellText: true,
            synchronizesColumnWidths: false,
            highlightsCellDifferences: false
        )
        let selection = TableWorkspaceSelection.cells(anchor: address(0, 0), focus: address(0, 1))
        let state = makeState(dataset: fixture.dataset, options: options, selection: selection)

        let plan = try TableWorkspacePolicy.plan(fixture.request(state: state))

        XCTAssertEqual(plan.presentation.options, options)
        XCTAssertEqual(plan.presentation.selection, selection)
        XCTAssertEqual(
            plan.presentation.columns.map(\.label),
            [
                .firstRecord(left: "left-name", right: "right-name"),
                .firstRecord(left: "left-value", right: "right-value"),
                .firstRecord(left: nil, right: nil)
            ]
        )
        XCTAssertEqual(plan.presentation.rows[0].status, .modified)
        XCTAssertEqual(
            plan.presentation.rows[0].cells.map(\.left?.value),
            ["left-name", "left-value"]
        )
        XCTAssertTrue(plan.presentation.rows[0].isVisible)
    }

    func testOrdinalHeadersAreOneBased() async throws {
        let fixture = try await makeFixture()
        let plan = try TableWorkspacePolicy.plan(fixture.request())

        XCTAssertEqual(plan.presentation.columns.map(\.index), [0, 1, 2])
        XCTAssertEqual(plan.presentation.columns.map(\.label), [.ordinal(1), .ordinal(2), .ordinal(3)])
    }

    func testStatusFiltersSupportIncludeAndExcludeDispositions() async throws {
        let fixture = try await makeFixture()
        let include = TableWorkspaceColumnFilter(
            identifier: "removed",
            columnIndex: 0,
            condition: .status(.removed)
        )
        let includePlan = try TableWorkspacePolicy.plan(
            fixture.request(state: makeState(dataset: fixture.dataset, filters: [include]))
        )
        XCTAssertEqual(includePlan.presentation.rows.map(\.isVisible), [false, true, false, false, false, false, false])
        XCTAssertEqual(includePlan.presentation.visibleRowCount, 1)
        XCTAssertEqual(includePlan.presentation.columns[0].filters, [include])

        let exclude = TableWorkspaceColumnFilter(
            identifier: "not-added",
            columnIndex: 0,
            condition: .status(.added),
            disposition: .excludeMatchingRows
        )
        let excludePlan = try TableWorkspacePolicy.plan(
            fixture.request(state: makeState(dataset: fixture.dataset, filters: [exclude]))
        )
        XCTAssertEqual(excludePlan.presentation.rows.map(\.isVisible), [true, true, true, true, true, false, true])
        XCTAssertEqual(excludePlan.presentation.visibleRowCount, 6)

        let equalCell = TableWorkspaceColumnFilter(
            identifier: "equal-cell",
            columnIndex: 1,
            condition: .status(.equal)
        )
        let equalCellPlan = try TableWorkspacePolicy.plan(
            fixture.request(state: makeState(dataset: fixture.dataset, filters: [equalCell]))
        )
        XCTAssertTrue(equalCellPlan.presentation.rows[3].isVisible)
        XCTAssertEqual(equalCellPlan.presentation.rows[3].status, .modified)
        XCTAssertEqual(equalCellPlan.presentation.rows[3].cells[1].status, .equal)
    }

    func testValueAndMissingFiltersUseExactRequestedSide() async throws {
        let fixture = try await makeFixture()
        let value = TableWorkspaceColumnFilter(
            identifier: "right-new",
            columnIndex: 0,
            condition: .valueEquals(side: .right, value: "new")
        )
        let valuePlan = try TableWorkspacePolicy.plan(
            fixture.request(state: makeState(dataset: fixture.dataset, filters: [value]))
        )
        XCTAssertEqual(valuePlan.presentation.rows.map(\.isVisible), [false, false, false, true, false, false, false])

        let missing = TableWorkspaceColumnFilter(
            identifier: "missing-left",
            columnIndex: 0,
            condition: .missing(side: .left)
        )
        let missingPlan = try TableWorkspacePolicy.plan(
            fixture.request(state: makeState(dataset: fixture.dataset, filters: [missing]))
        )
        XCTAssertEqual(missingPlan.presentation.rows.map(\.isVisible), [false, false, false, false, false, true, false])
    }

    func testFiltersUseIncludeConjunctionAndExcludeVeto() async throws {
        let fixture = try await makeFixture()
        let filters = [
            TableWorkspaceColumnFilter(
                identifier: "modified",
                columnIndex: 0,
                condition: .status(.modified)
            ),
            TableWorkspaceColumnFilter(
                identifier: "right-new",
                columnIndex: 0,
                condition: .valueEquals(side: .right, value: "new")
            ),
            TableWorkspaceColumnFilter(
                identifier: "veto-keep",
                columnIndex: 1,
                condition: .valueEquals(side: .right, value: "keep"),
                disposition: .excludeMatchingRows
            )
        ]

        let plan = try TableWorkspacePolicy.plan(
            fixture.request(state: makeState(dataset: fixture.dataset, filters: filters))
        )

        XCTAssertEqual(plan.presentation.visibleRowCount, 0)
        XCTAssertTrue(plan.presentation.rows.allSatisfy { !$0.isVisible })
        XCTAssertEqual(plan.presentation.columns[0].filters, Array(filters.prefix(2)))
        XCTAssertEqual(plan.presentation.columns[1].filters, [filters[2]])
    }

    func testFilterCountDuplicateAndIdentifierGuardsAreTyped() async throws {
        let fixture = try await makeFixture()
        let first = statusFilter(identifier: "one")
        let second = statusFilter(identifier: "two")

        assertPolicyError(.tooManyColumnFilters(maximum: 1)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(dataset: fixture.dataset, filters: [first, second]),
                    limits: policyLimits(maximumColumnFilters: 1)
                )
            )
        }
        assertPolicyError(.duplicateFilterIdentifier("one")) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(state: makeState(dataset: fixture.dataset, filters: [first, first]))
            )
        }
        for identifier in ["", "nul\0value"] {
            assertPolicyError(.invalidFilterIdentifier(identifier)) {
                _ = try TableWorkspacePolicy.plan(
                    fixture.request(
                        state: makeState(
                            dataset: fixture.dataset,
                            filters: [statusFilter(identifier: identifier)]
                        )
                    )
                )
            }
        }
    }

    func testFilterIdentifierValueTotalAndCanonicalGuardsAreIndependent() async throws {
        let fixture = try await makeFixture()
        let longIdentifier = "ab"
        let valueFilter = TableWorkspaceColumnFilter(
            identifier: "value",
            columnIndex: 0,
            condition: .valueEquals(side: .left, value: "ab")
        )

        assertPolicyError(.filterIdentifierTooLarge(maximumUTF8Bytes: 1)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(
                        dataset: fixture.dataset,
                        filters: [statusFilter(identifier: longIdentifier)]
                    ),
                    limits: policyLimits(maximumFilterIdentifierUTF8Bytes: 1)
                )
            )
        }
        assertPolicyError(.filterValueTooLarge(identifier: "value", maximumUTF8Bytes: 1)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(dataset: fixture.dataset, filters: [valueFilter]),
                    limits: policyLimits(maximumFilterValueUTF8Bytes: 1)
                )
            )
        }
        assertPolicyError(.totalFilterValuesTooLarge(maximumUTF8Bytes: 6)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(dataset: fixture.dataset, filters: [valueFilter]),
                    limits: policyLimits(maximumTotalFilterUTF8Bytes: 6)
                )
            )
        }

        let decomposed = "e\u{301}"
        assertPolicyError(.nonCanonicalPersistenceString("columnFilters.identifier")) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(
                        dataset: fixture.dataset,
                        filters: [statusFilter(identifier: decomposed)]
                    )
                )
            )
        }
        let noncanonicalValue = TableWorkspaceColumnFilter(
            identifier: "canonical",
            columnIndex: 0,
            condition: .valueEquals(side: .left, value: decomposed)
        )
        assertPolicyError(.nonCanonicalPersistenceString("columnFilters.value")) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(dataset: fixture.dataset, filters: [noncanonicalValue])
                )
            )
        }
    }

    func testFilterColumnsUseGlobalOrExactSideShapeAsRequired() async throws {
        let fixture = try await makeFixture()
        let global = TableWorkspaceColumnFilter(
            identifier: "global",
            columnIndex: 2,
            condition: .status(.added)
        )
        XCTAssertNoThrow(
            try TableWorkspacePolicy.plan(
                fixture.request(state: makeState(dataset: fixture.dataset, filters: [global]))
            )
        )

        let leftBound = TableWorkspaceColumnFilter(
            identifier: "left",
            columnIndex: 2,
            condition: .missing(side: .left)
        )
        assertPolicyError(.filterColumnOutOfBounds(identifier: "left", columnIndex: 2)) {
            _ = try makeState(dataset: fixture.dataset, filters: [leftBound]).encoded()
        }
        XCTAssertNoThrow(
            try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(dataset: fixture.dataset, filters: [leftBound])
                )
            )
        )

        let rightBound = TableWorkspaceColumnFilter(
            identifier: "right",
            columnIndex: 2,
            condition: .valueEquals(side: .right, value: "extra")
        )
        XCTAssertNoThrow(try makeState(dataset: fixture.dataset, filters: [rightBound]).encoded())

        let negative = TableWorkspaceColumnFilter(
            identifier: "negative",
            columnIndex: -1,
            condition: .status(.equal)
        )
        assertPolicyError(.filterColumnOutOfBounds(identifier: "negative", columnIndex: -1)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(state: makeState(dataset: fixture.dataset, filters: [negative]))
            )
        }
    }

    func testSelectionIntentsPreserveNoneColumnAndCellRange() async throws {
        let fixture = try await makeFixture()
        let selections: [TableWorkspaceSelection] = [
            .none,
            .column(2),
            .cells(anchor: address(2, 1), focus: address(3, 2))
        ]

        for selection in selections {
            let plan = try TableWorkspacePolicy.plan(
                fixture.request(state: makeState(dataset: fixture.dataset, selection: selection))
            )
            XCTAssertEqual(plan.presentation.selection, selection)
            XCTAssertEqual(plan.receipt.state.selection, selection)
        }
    }

    func testSelectionRejectsNegativeMissingAndRaggedAddresses() async throws {
        let fixture = try await makeFixture()
        let invalidSelections: [TableWorkspaceSelection] = [
            .column(-1),
            .column(3),
            .cells(anchor: address(-1, 0), focus: address(0, 0)),
            .cells(anchor: address(0, 0), focus: address(7, 0)),
            .cells(anchor: address(0, 0), focus: address(0, 2))
        ]

        for selection in invalidSelections {
            assertPolicyError(.selectionOutOfBounds) {
                _ = try TableWorkspacePolicy.plan(
                    fixture.request(state: makeState(dataset: fixture.dataset, selection: selection))
                )
            }
        }
    }

    func testEditIntentMapsPresentationAddressToExactSourceArtifact() async throws {
        let fixture = try await makeFixture()
        let request = TableWorkspaceEditRequest(
            side: .left,
            address: address(3, 0),
            expectedPresentedValue: "old",
            replacementPresentedValue: "replacement"
        )

        let plan = try TableWorkspacePolicy.plan(fixture.request(editRequest: request))
        let intent = try XCTUnwrap(plan.editIntent)
        let sourceCell = fixture.comparisonReceipt.result.left.rows[3].cells[0]

        XCTAssertEqual(intent.datasetReference, fixture.dataset.reference)
        XCTAssertEqual(intent.source, fixture.dataset.source(.left))
        XCTAssertEqual(intent.presentationAddress, address(3, 0))
        XCTAssertEqual(intent.sourceRowIndex, 3)
        XCTAssertEqual(intent.sourceColumnIndex, 0)
        XCTAssertEqual(intent.sourceUTF8Range, sourceCell.sourceUTF8Range)
        XCTAssertEqual(intent.expectedPresentedValue, "old")
        XCTAssertEqual(intent.replacementPresentedValue, "replacement")
        XCTAssertEqual(plan.receipt.editIntent, intent)

        let rightRequest = TableWorkspaceEditRequest(
            side: .right,
            address: address(3, 2),
            expectedPresentedValue: "extra",
            replacementPresentedValue: "replacement-right"
        )
        let rightPlan = try TableWorkspacePolicy.plan(
            fixture.request(editRequest: rightRequest)
        )
        let rightIntent = try XCTUnwrap(rightPlan.editIntent)
        let rightCell = fixture.comparisonReceipt.result.right.rows[2].cells[2]
        XCTAssertEqual(rightIntent.source, fixture.dataset.source(.right))
        XCTAssertEqual(rightIntent.presentationAddress, address(3, 2))
        XCTAssertEqual(rightIntent.sourceRowIndex, 2)
        XCTAssertEqual(rightIntent.sourceColumnIndex, 2)
        XCTAssertEqual(rightIntent.sourceUTF8Range, rightCell.sourceUTF8Range)
    }

    func testEditRejectsEachAddressReadOnlyMissingAndValueGuard() async throws {
        let fixture = try await makeFixture()
        let cases: [(TableWorkspacePolicyError, TableWorkspaceEditRequest, TableWorkspaceState)] = [
            (
                .editTargetOutOfBounds,
                editRequest(side: .left, row: -1, column: 0, expected: "old", replacement: "new"),
                fixture.state
            ),
            (
                .editTargetOutOfBounds,
                editRequest(side: .left, row: 0, column: 2, expected: "old", replacement: "new"),
                fixture.state
            ),
            (
                .editTargetOutOfBounds,
                editRequest(side: .left, row: 7, column: 0, expected: "old", replacement: "new"),
                fixture.state
            ),
            (
                .editTargetOutOfBounds,
                editRequest(side: .left, row: 0, column: -1, expected: "old", replacement: "new"),
                fixture.state
            ),
            (
                .editTargetMissing(.right),
                editRequest(side: .right, row: 1, column: 0, expected: "", replacement: "new"),
                fixture.state
            ),
            (
                .editExpectedValueChanged,
                editRequest(side: .left, row: 3, column: 0, expected: "stale", replacement: "new"),
                fixture.state
            ),
            (
                .editWouldNotChangeValue,
                editRequest(side: .left, row: 3, column: 0, expected: "old", replacement: "old"),
                fixture.state
            )
        ]

        for (expected, edit, state) in cases {
            assertPolicyError(expected) {
                _ = try TableWorkspacePolicy.plan(fixture.request(state: state, editRequest: edit))
            }
        }

        let readOnlyFixture = try await makeFixture(leftEditable: false)
        let readOnlyEdit = editRequest(
            side: .left,
            row: 3,
            column: 0,
            expected: "old",
            replacement: "new"
        )
        assertPolicyError(.editTargetReadOnly(.left)) {
            _ = try TableWorkspacePolicy.plan(readOnlyFixture.request(editRequest: readOnlyEdit))
        }
    }

    func testEditValueUsesMinimumPolicyAndDatasetCellByteBoundary() async throws {
        let configuration = configuration(maximumCellBytes: 2)
        let fixture = try await makeFixture(
            left: "a",
            right: "b",
            configuration: configuration
        )
        let exact = editRequest(
            side: .left,
            row: 0,
            column: 0,
            expected: "a",
            replacement: "\u{E9}"
        )
        XCTAssertNoThrow(try TableWorkspacePolicy.plan(fixture.request(editRequest: exact)))

        let datasetCapped = editRequest(
            side: .left,
            row: 0,
            column: 0,
            expected: "a",
            replacement: "abc"
        )
        assertPolicyError(.editValueTooLarge(maximumUTF8Bytes: 2)) {
            _ = try TableWorkspacePolicy.plan(fixture.request(editRequest: datasetCapped))
        }

        assertPolicyError(.editValueTooLarge(maximumUTF8Bytes: 1)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    editRequest: exact,
                    limits: policyLimits(maximumEditValueUTF8Bytes: 1)
                )
            )
        }
    }

    func testEditExpectedValueUsesExactAndOverPolicyAndDatasetCaps() async throws {
        let datasetCappedConfiguration = configuration(maximumCellBytes: 2)
        let datasetFixture = try await makeFixture(
            left: "\u{E9}",
            right: "x",
            configuration: datasetCappedConfiguration
        )
        let exactDataset = editRequest(
            side: .left,
            row: 0,
            column: 0,
            expected: "\u{E9}",
            replacement: "ok"
        )
        XCTAssertNoThrow(
            try TableWorkspacePolicy.plan(datasetFixture.request(editRequest: exactDataset))
        )

        let overDataset = editRequest(
            side: .left,
            row: 0,
            column: 0,
            expected: "abc",
            replacement: "ok"
        )
        assertPolicyError(.editValueTooLarge(maximumUTF8Bytes: 2)) {
            _ = try TableWorkspacePolicy.plan(
                datasetFixture.request(editRequest: overDataset)
            )
        }

        let policyFixture = try await makeFixture(left: "ab", right: "x")
        let exactPolicy = editRequest(
            side: .left,
            row: 0,
            column: 0,
            expected: "ab",
            replacement: "xy"
        )
        XCTAssertNoThrow(
            try TableWorkspacePolicy.plan(
                policyFixture.request(
                    editRequest: exactPolicy,
                    limits: policyLimits(maximumEditValueUTF8Bytes: 2)
                )
            )
        )

        let overPolicy = editRequest(
            side: .left,
            row: 0,
            column: 0,
            expected: "abc",
            replacement: "x"
        )
        assertPolicyError(.editValueTooLarge(maximumUTF8Bytes: 2)) {
            _ = try TableWorkspacePolicy.plan(
                policyFixture.request(
                    editRequest: overPolicy,
                    limits: policyLimits(maximumEditValueUTF8Bytes: 2)
                )
            )
        }
    }

    func testPlanRejectsStaleStateIdentityRevisionBindingAndConfigurationIndependently() async throws {
        let fixture = try await makeFixture()
        let foreignReference = TableWorkspaceDatasetReference(
            identity: datasetIdentity(99),
            revision: fixture.dataset.reference.revision
        )
        assertPolicyError(.datasetIdentityChanged) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(dataset: fixture.dataset, reference: foreignReference)
                )
            )
        }

        let staleReference = TableWorkspaceDatasetReference(
            identity: fixture.dataset.reference.identity,
            revision: fixture.dataset.reference.revision - 1
        )
        assertPolicyError(
            .staleDatasetRevision(
                expected: fixture.dataset.reference.revision,
                actual: staleReference.revision
            )
        ) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(dataset: fixture.dataset, reference: staleReference)
                )
            )
        }

        let changedLeft = copyBinding(
            try XCTUnwrap(fixture.dataset.source(.left)),
            sourceRevision: 99
        )
        assertPolicyError(.sourceBindingChanged(.left)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(
                        dataset: fixture.dataset,
                        sources: [changedLeft, try XCTUnwrap(fixture.dataset.source(.right))]
                    )
                )
            )
        }

        let changedConfiguration = configuration(delimiter: "|")
        assertPolicyError(.configurationChanged) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(dataset: fixture.dataset, configuration: changedConfiguration)
                )
            )
        }
    }

    func testPlanRejectsEveryStaleBindingFieldOnBothSides() async throws {
        let fixture = try await makeFixture()
        for side in TableWorkspaceSide.allCases {
            let binding = try XCTUnwrap(fixture.dataset.source(side))
            for (field, changedBinding) in bindingMutations(binding) {
                let sources = fixture.dataset.sources.map {
                    $0.side == side ? changedBinding : $0
                }
                assertPolicyError(.sourceBindingChanged(side), context: "\(side).\(field)") {
                    _ = try TableWorkspacePolicy.plan(
                        fixture.request(
                            state: makeState(dataset: fixture.dataset, sources: sources)
                        )
                    )
                }
            }
        }
    }

    func testCurrentDatasetCASRejectsIdentityRevisionConfigurationAndBothBindings() async throws {
        let fixture = try await makeFixture()
        let plan = try TableWorkspacePolicy.plan(fixture.request())
        let currentChecks: [(TableWorkspacePolicyError, TableWorkspaceDatasetSnapshot)] = [
            (
                .datasetIdentityChanged,
                copyDataset(
                    fixture.dataset,
                    reference: TableWorkspaceDatasetReference(
                        identity: datasetIdentity(77),
                        revision: fixture.dataset.reference.revision
                    )
                )
            ),
            (
                .staleDatasetRevision(
                    expected: fixture.dataset.reference.revision,
                    actual: fixture.dataset.reference.revision - 1
                ),
                copyDataset(
                    fixture.dataset,
                    reference: TableWorkspaceDatasetReference(
                        identity: fixture.dataset.reference.identity,
                        revision: fixture.dataset.reference.revision - 1
                    )
                )
            ),
            (
                .staleDatasetRevision(
                    expected: fixture.dataset.reference.revision,
                    actual: fixture.dataset.reference.revision + 1
                ),
                copyDataset(
                    fixture.dataset,
                    reference: TableWorkspaceDatasetReference(
                        identity: fixture.dataset.reference.identity,
                        revision: fixture.dataset.reference.revision + 1
                    )
                )
            ),
            (
                .configurationChanged,
                copyDataset(fixture.dataset, configuration: configuration(delimiter: "|"))
            ),
            (
                .sourceBindingChanged(.left),
                copyDataset(
                    fixture.dataset,
                    sources: [
                        copyBinding(
                            try XCTUnwrap(fixture.dataset.source(.left)),
                            tableRevision: 88
                        ),
                        try XCTUnwrap(fixture.dataset.source(.right))
                    ]
                )
            ),
            (
                .sourceBindingChanged(.right),
                copyDataset(
                    fixture.dataset,
                    sources: [
                        try XCTUnwrap(fixture.dataset.source(.left)),
                        copyBinding(
                            try XCTUnwrap(fixture.dataset.source(.right)),
                            sourceRevision: 88
                        )
                    ]
                )
            )
        ]

        XCTAssertNoThrow(try TableWorkspacePolicy.validateCurrent(fixture.dataset, expected: fixture.dataset))
        XCTAssertNoThrow(try fixture.comparisonReceipt.requireCurrentDataset(fixture.dataset))
        XCTAssertNoThrow(try plan.requireCurrentDataset(fixture.dataset))
        for (expected, actual) in currentChecks {
            assertPolicyError(expected) {
                try TableWorkspacePolicy.validateCurrent(actual, expected: fixture.dataset)
            }
            assertPolicyError(expected) {
                try fixture.comparisonReceipt.requireCurrentDataset(actual)
            }
            assertPolicyError(expected) {
                try plan.requireCurrentDataset(actual)
            }
        }
    }

    func testCurrentDatasetCASRejectsEveryBindingFieldOnBothSides() async throws {
        let fixture = try await makeFixture()
        let plan = try TableWorkspacePolicy.plan(fixture.request())

        for side in TableWorkspaceSide.allCases {
            let binding = try XCTUnwrap(fixture.dataset.source(side))
            for (field, changedBinding) in bindingMutations(binding) {
                let actual = copyDataset(
                    fixture.dataset,
                    sources: fixture.dataset.sources.map {
                        $0.side == side ? changedBinding : $0
                    }
                )
                let context = "\(side).\(field)"
                assertPolicyError(.sourceBindingChanged(side), context: context) {
                    try TableWorkspacePolicy.validateCurrent(actual, expected: fixture.dataset)
                }
                assertPolicyError(.sourceBindingChanged(side), context: context) {
                    try fixture.comparisonReceipt.requireCurrentDataset(actual)
                }
                assertPolicyError(.sourceBindingChanged(side), context: context) {
                    try plan.requireCurrentDataset(actual)
                }
            }
        }
    }

    func testCurrentDatasetCASRejectsWrongCountAndDuplicateSidesBeforeFieldChecks() async throws {
        let fixture = try await makeFixture()
        let left = try XCTUnwrap(fixture.dataset.source(.left))
        let right = try XCTUnwrap(fixture.dataset.source(.right))
        let cases: [(TableWorkspacePolicyError, [TableWorkspaceSourceBinding])] = [
            (.sourceCountInvalid(0), []),
            (.sourceCountInvalid(1), [left]),
            (.sourceCountInvalid(3), [left, right, left]),
            (.duplicateSide(.left), [left, copyBinding(left, sourceRevision: 99)]),
            (.duplicateSide(.right), [right, copyBinding(right, tableRevision: 99)])
        ]

        for (expected, sources) in cases {
            let actual = copyDataset(fixture.dataset, sources: sources)
            assertPolicyError(expected, context: "count=\(sources.count)") {
                try TableWorkspacePolicy.validateCurrent(actual, expected: fixture.dataset)
            }
        }
    }

    func testEditExecutionReceiptSuccessRequiresAtomicRevisionAdvance() async throws {
        let fixture = try await makeFixture()
        let edit = editRequest(
            side: .left,
            row: 3,
            column: 0,
            expected: "old",
            replacement: "newer"
        )
        let plan = try TableWorkspacePolicy.plan(fixture.request(editRequest: edit))
        let intent = try XCTUnwrap(plan.editIntent)
        let oldLeft = try XCTUnwrap(fixture.dataset.source(.left))
        let revisedLeft = copyBinding(
            oldLeft,
            sourceRevision: oldLeft.sourceRevision + 1,
            tableRevision: oldLeft.tableRevision + 1,
            shape: TableWorkspaceTableShape(
                sourceUTF8ByteCount: oldLeft.shape.sourceUTF8ByteCount + 2,
                rowCount: oldLeft.shape.rowCount,
                maximumColumnCount: oldLeft.shape.maximumColumnCount,
                totalCellCount: oldLeft.shape.totalCellCount
            )
        )
        let resultingDataset = copyDataset(
            fixture.dataset,
            reference: TableWorkspaceDatasetReference(
                identity: fixture.dataset.reference.identity,
                revision: fixture.dataset.reference.revision + 1
            ),
            sources: [revisedLeft, try XCTUnwrap(fixture.dataset.source(.right))]
        )
        let executor = WorkspaceExecutor(sourceData: [:], publication: resultingDataset)

        let executionReceipt = try await executor.execute(intent)
        let validated = try plan.validate(executionReceipt)

        XCTAssertEqual(executionReceipt.intent, intent)
        XCTAssertEqual(executionReceipt.resultingDataset, resultingDataset)
        XCTAssertEqual(validated, resultingDataset)
        XCTAssertEqual(
            try TableWorkspacePolicy.validate(executionReceipt, for: plan.receipt),
            resultingDataset
        )
    }

    func testEditReceiptRejectsUnexpectedAndMismatchedIntent() async throws {
        let fixture = try await makeFixture()
        let leftEdit = editRequest(
            side: .left,
            row: 3,
            column: 0,
            expected: "old",
            replacement: "left-new"
        )
        let rightEdit = editRequest(
            side: .right,
            row: 3,
            column: 0,
            expected: "new",
            replacement: "right-new"
        )
        let noEditPlan = try TableWorkspacePolicy.plan(fixture.request())
        let leftPlan = try TableWorkspacePolicy.plan(fixture.request(editRequest: leftEdit))
        let rightPlan = try TableWorkspacePolicy.plan(fixture.request(editRequest: rightEdit))
        let resultingDataset = validResultingDataset(
            from: fixture.dataset,
            editedSide: .left
        )
        let executor = WorkspaceExecutor(sourceData: [:], publication: resultingDataset)
        let receipt = try await executor.execute(try XCTUnwrap(leftPlan.editIntent))

        assertPolicyError(.unexpectedExecutionReceipt) {
            _ = try noEditPlan.validate(receipt)
        }
        assertPolicyError(.executionIntentMismatch) {
            _ = try rightPlan.validate(receipt)
        }
    }

    func testEditReceiptRejectsDatasetIdentityRevisionAndConfigurationGuards() async throws {
        let context = try await makeEditValidationContext()
        let cases: [(TableWorkspacePolicyError, TableWorkspaceDatasetSnapshot)] = [
            (
                .resultingDatasetIdentityChanged,
                copyDataset(
                    context.validResult,
                    reference: TableWorkspaceDatasetReference(
                        identity: datasetIdentity(66),
                        revision: context.validResult.reference.revision
                    )
                )
            ),
            (
                .resultingDatasetRevisionUnchanged,
                copyDataset(
                    context.validResult,
                    reference: context.fixture.dataset.reference
                )
            ),
            (
                .resultingDatasetRevisionUnchanged,
                copyDataset(
                    context.validResult,
                    reference: TableWorkspaceDatasetReference(
                        identity: context.fixture.dataset.reference.identity,
                        revision: context.fixture.dataset.reference.revision - 1
                    )
                )
            ),
            (
                .configurationChanged,
                copyDataset(context.validResult, configuration: configuration(delimiter: "|"))
            )
        ]

        for (expected, result) in cases {
            let receipt = try await WorkspaceExecutor(sourceData: [:], publication: result)
                .execute(context.intent)
            assertPolicyError(expected) {
                _ = try context.plan.validate(receipt)
            }
        }
    }

    func testEditReceiptRejectsEditedSourceIdentityAndRevisionGuards() async throws {
        let context = try await makeEditValidationContext()
        let oldLeft = try XCTUnwrap(context.fixture.dataset.source(.left))
        let validLeft = try XCTUnwrap(context.validResult.source(.left))
        let cases: [(TableWorkspacePolicyError, TableWorkspaceSourceBinding)] = [
            (
                .resultingSourceIdentityChanged(.left),
                copyBinding(validLeft, sourceIdentity: sourceIdentity(66))
            ),
            (
                .resultingSourceRevisionUnchanged(.left),
                copyBinding(validLeft, sourceRevision: oldLeft.sourceRevision)
            ),
            (
                .resultingSourceRevisionUnchanged(.left),
                copyBinding(validLeft, sourceRevision: oldLeft.sourceRevision - 1)
            ),
            (
                .resultingTableIdentityChanged(.left),
                copyBinding(validLeft, tableIdentity: tableIdentity(66))
            ),
            (
                .resultingTableRevisionUnchanged(.left),
                copyBinding(validLeft, tableRevision: oldLeft.tableRevision)
            ),
            (
                .resultingTableRevisionUnchanged(.left),
                copyBinding(validLeft, tableRevision: oldLeft.tableRevision - 1)
            )
        ]

        for (expected, changedLeft) in cases {
            let result = copyDataset(
                context.validResult,
                sources: [changedLeft, try XCTUnwrap(context.validResult.source(.right))]
            )
            let receipt = try await WorkspaceExecutor(sourceData: [:], publication: result)
                .execute(context.intent)
            assertPolicyError(expected) {
                _ = try context.plan.validate(receipt)
            }
        }
    }

    func testEditReceiptRejectsUnrelatedShapeAndSourceByteGuards() async throws {
        let context = try await makeEditValidationContext()
        let validLeft = try XCTUnwrap(context.validResult.source(.left))
        let oldRight = try XCTUnwrap(context.fixture.dataset.source(.right))

        let unrelated = copyDataset(
            context.validResult,
            sources: [validLeft, copyBinding(oldRight, sourceRevision: oldRight.sourceRevision + 1)]
        )
        let unrelatedReceipt = try await WorkspaceExecutor(sourceData: [:], publication: unrelated)
            .execute(context.intent)
        assertPolicyError(.unrelatedSourceChanged(.right)) {
            _ = try context.plan.validate(unrelatedReceipt)
        }

        let changedShape = TableWorkspaceTableShape(
            sourceUTF8ByteCount: validLeft.shape.sourceUTF8ByteCount,
            rowCount: validLeft.shape.rowCount + 1,
            maximumColumnCount: validLeft.shape.maximumColumnCount,
            totalCellCount: validLeft.shape.totalCellCount
        )
        let shapeResult = copyDataset(
            context.validResult,
            sources: [
                copyBinding(validLeft, shape: changedShape),
                try XCTUnwrap(context.validResult.source(.right))
            ]
        )
        let shapeReceipt = try await WorkspaceExecutor(sourceData: [:], publication: shapeResult)
            .execute(context.intent)
        assertPolicyError(.resultingTableShapeChanged(.left)) {
            _ = try context.plan.validate(shapeReceipt)
        }

        let invalidByteShape = TableWorkspaceTableShape(
            sourceUTF8ByteCount: -1,
            rowCount: validLeft.shape.rowCount,
            maximumColumnCount: validLeft.shape.maximumColumnCount,
            totalCellCount: validLeft.shape.totalCellCount
        )
        let byteResult = copyDataset(
            context.validResult,
            sources: [
                copyBinding(validLeft, shape: invalidByteShape),
                try XCTUnwrap(context.validResult.source(.right))
            ]
        )
        let byteReceipt = try await WorkspaceExecutor(sourceData: [:], publication: byteResult)
            .execute(context.intent)
        assertPolicyError(.shapeMismatch(.left)) {
            _ = try context.plan.validate(byteReceipt)
        }
    }

    func testEditReceiptRejectsEveryUnrelatedArtifactField() async throws {
        let context = try await makeEditValidationContext()
        let oldRight = try XCTUnwrap(context.fixture.dataset.source(.right))
        let validLeft = try XCTUnwrap(context.validResult.source(.left))

        for (field, changedRight) in bindingMutations(oldRight) {
            let result = copyDataset(
                context.validResult,
                sources: [validLeft, changedRight]
            )
            let receipt = try await WorkspaceExecutor(sourceData: [:], publication: result)
                .execute(context.intent)
            assertPolicyError(.unrelatedSourceChanged(.right), context: field) {
                _ = try context.plan.validate(receipt)
            }
        }
    }

    func testEditedShapeRejectsColumnAndTotalMutationsIndependently() async throws {
        let context = try await makeEditValidationContext()
        let validLeft = try XCTUnwrap(context.validResult.source(.left))
        let right = try XCTUnwrap(context.validResult.source(.right))
        let shapes: [(String, TableWorkspaceTableShape)] = [
            (
                "column",
                TableWorkspaceTableShape(
                    sourceUTF8ByteCount: validLeft.shape.sourceUTF8ByteCount,
                    rowCount: validLeft.shape.rowCount,
                    maximumColumnCount: validLeft.shape.maximumColumnCount + 1,
                    totalCellCount: validLeft.shape.totalCellCount
                )
            ),
            (
                "total",
                TableWorkspaceTableShape(
                    sourceUTF8ByteCount: validLeft.shape.sourceUTF8ByteCount,
                    rowCount: validLeft.shape.rowCount,
                    maximumColumnCount: validLeft.shape.maximumColumnCount,
                    totalCellCount: validLeft.shape.totalCellCount + 1
                )
            )
        ]

        for (field, shape) in shapes {
            let result = copyDataset(
                context.validResult,
                sources: [copyBinding(validLeft, shape: shape), right]
            )
            let receipt = try await WorkspaceExecutor(sourceData: [:], publication: result)
                .execute(context.intent)
            assertPolicyError(.resultingTableShapeChanged(.left), context: field) {
                _ = try context.plan.validate(receipt)
            }
        }
    }

    func testEditedSourceByteCountAcceptsExactMaximumAndRejectsBothInvalidBounds() async throws {
        let context = try await makeEditValidationContext()
        let validLeft = try XCTUnwrap(context.validResult.source(.left))
        let right = try XCTUnwrap(context.validResult.source(.right))
        let maximum = context.validResult.configuration.format.limits.maximumInputBytes

        let exactShape = TableWorkspaceTableShape(
            sourceUTF8ByteCount: maximum,
            rowCount: validLeft.shape.rowCount,
            maximumColumnCount: validLeft.shape.maximumColumnCount,
            totalCellCount: validLeft.shape.totalCellCount
        )
        let exactResult = copyDataset(
            context.validResult,
            sources: [copyBinding(validLeft, shape: exactShape), right]
        )
        let exactReceipt = try await WorkspaceExecutor(
            sourceData: [:],
            publication: exactResult
        ).execute(context.intent)
        XCTAssertEqual(try context.plan.validate(exactReceipt), exactResult)

        for byteCount in [-1, maximum + 1] {
            let invalidShape = TableWorkspaceTableShape(
                sourceUTF8ByteCount: byteCount,
                rowCount: validLeft.shape.rowCount,
                maximumColumnCount: validLeft.shape.maximumColumnCount,
                totalCellCount: validLeft.shape.totalCellCount
            )
            let result = copyDataset(
                context.validResult,
                sources: [copyBinding(validLeft, shape: invalidShape), right]
            )
            let receipt = try await WorkspaceExecutor(sourceData: [:], publication: result)
                .execute(context.intent)
            assertPolicyError(.shapeMismatch(.left), context: "bytes=\(byteCount)") {
                _ = try context.plan.validate(receipt)
            }
        }
    }

    func testPublisherDoubleReceivesExactOpaqueIntent() async throws {
        let context = try await makeEditValidationContext()
        let executor = VerifyingWorkspaceExecutor(
            expectedIntent: context.intent,
            publication: context.validResult
        )

        let receipt = try await executor.execute(context.intent)

        XCTAssertEqual(receipt.intent, context.intent)
        XCTAssertEqual(executor.publishedIntent, context.intent)
        XCTAssertNil(executor.verificationFailure)
    }

    func testPersistenceRoundTripsAllFiltersPresentationAndCellSelection() throws {
        let dataset = try makeDataset(left: "a,b,c", right: "x,y,z")
        let options = TableWorkspacePresentationOptions(
            headerVisibility: .hidden,
            headerLabels: .firstRecord,
            showsRowNumbers: false,
            wrapsCellText: true,
            synchronizesColumnWidths: false,
            highlightsCellDifferences: false
        )
        let filters = [
            TableWorkspaceColumnFilter(
                identifier: "status",
                columnIndex: 0,
                condition: .status(.modified),
                disposition: .includeMatchingRows
            ),
            TableWorkspaceColumnFilter(
                identifier: "value",
                columnIndex: 1,
                condition: .valueEquals(side: .right, value: "y"),
                disposition: .excludeMatchingRows
            ),
            TableWorkspaceColumnFilter(
                identifier: "missing",
                columnIndex: 2,
                condition: .missing(side: .left),
                disposition: .includeMatchingRows
            )
        ]
        let selection = TableWorkspaceSelection.cells(anchor: address(0, 0), focus: address(0, 2))
        let state = makeState(
            dataset: dataset,
            options: options,
            filters: filters,
            selection: selection
        )

        let encoded = try state.encoded()
        let decoded = try TableWorkspaceState.decode(from: encoded.data)

        XCTAssertEqual(encoded.state, state)
        XCTAssertEqual(decoded.state, state)
        XCTAssertEqual(decoded.state.presentationOptions, options)
        XCTAssertEqual(decoded.state.columnFilters, filters)
        XCTAssertEqual(decoded.state.selection, selection)
        XCTAssertEqual(decoded.formatVersion, TableWorkspaceState.currentSchemaVersion)
        XCTAssertEqual(decoded.data, encoded.data)
    }

    func testPersistenceRoundTripsNoneAndColumnSelectionShapes() throws {
        let dataset = try makeDataset(left: "a,b", right: "x,y")
        for selection in [TableWorkspaceSelection.none, .column(1)] {
            let state = makeState(dataset: dataset, selection: selection)
            XCTAssertEqual(try TableWorkspaceState.decode(from: state.encoded().data).state.selection, selection)
        }
    }

    func testPersistenceRoundTripsFalseEditabilityNilQuoteAndFalseQuotedNewlines() throws {
        let state = goldenPersistenceState()

        let receipt = try state.encoded()
        let decoded = try TableWorkspaceState.decode(from: receipt.data).state

        XCTAssertEqual(decoded, state)
        XCTAssertNil(decoded.configuration.format.quote)
        XCTAssertFalse(decoded.configuration.format.allowsNewlinesInQuotedCells)
        XCTAssertFalse(try XCTUnwrap(decoded.source(.left)).isEditable)
        XCTAssertFalse(try XCTUnwrap(decoded.source(.right)).isEditable)
        XCTAssertFalse(decoded.presentationOptions.showsRowNumbers)
        XCTAssertTrue(decoded.presentationOptions.wrapsCellText)
        XCTAssertFalse(decoded.presentationOptions.synchronizesColumnWidths)
        XCTAssertTrue(decoded.presentationOptions.highlightsCellDifferences)
    }

    func testPersistenceFullGoldenWireBytesAndBoolWidthRegression() throws {
        let expected = dataFromHex(
            "4d4d54570101000000000000000000000000000001000000000000000202000a00000000000000000000000000000a00000000000000022a00000000000000000000000000002a000000000000000300000000000000010000000000000001000000000000000100000000000000010001140000000000000000000000000000140000000000000002340000000000000000000000000000340000000000000003000000000000000100000000000000010000000000000001000000000000000100000000017c00000000000000000009000000000000000100000000000000010000000000000001000000000000000100000000000000000000000000000000000000000000000200000000000000020001000100010000000300000001730000000000000000000101000000017600000000000000000101000000017800000000016d0000000000000000020001010000000000000000000000000000000000000000000000000000000000000000"
        )

        let actual = try goldenPersistenceState().encoded().data

        XCTAssertEqual(actual.count, 369)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(try TableWorkspaceState.decode(from: expected).state, goldenPersistenceState())
    }

    func testPersistenceRejectsEveryInvalidValueAtEveryBoolByte() throws {
        let encoded = try goldenPersistenceState().encoded().data
        let boolOffsets = [111, 193, 199, 200, 275, 276, 277, 278]

        for offset in boolOffsets {
            for invalid in UInt8(2)...UInt8.max {
                var malformed = encoded
                malformed[offset] = invalid
                assertPolicyError(
                    .malformedPersistence,
                    context: "offset=\(offset), value=\(invalid)"
                ) {
                    _ = try TableWorkspaceState.decode(from: malformed)
                }
            }
        }
    }

    func testPersistenceCanonicalizesLeftRightAndUsesStableBigEndianWireOrder() throws {
        let left = try makeBinding(side: .left, input: "left", identitySeed: 10)
        let right = try makeBinding(side: .right, input: "right", identitySeed: 20)
        let reference = makeReference(identitySeed: 30, revision: 0x0102_0304_0506_0708)
        let forward = TableWorkspaceState(
            datasetReference: reference,
            sources: [left, right],
            configuration: .default
        )
        let reversed = TableWorkspaceState(
            datasetReference: reference,
            sources: [right, left],
            configuration: .default
        )

        let forwardReceipt = try forward.encoded()
        let reversedReceipt = try reversed.encoded()
        let bytes = [UInt8](forwardReceipt.data)

        XCTAssertEqual(forwardReceipt.data, reversedReceipt.data)
        XCTAssertEqual(Array(bytes[0..<4]), [0x4D, 0x4D, 0x54, 0x57])
        XCTAssertEqual(bytes[4], UInt8(TableWorkspaceState.currentSchemaVersion))
        XCTAssertEqual(Array(bytes[21..<29]), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(bytes[29], 2)
        XCTAssertEqual(bytes[30], 0)
        XCTAssertEqual(bytes[112], 1)
        XCTAssertEqual(try TableWorkspaceState.decode(from: forwardReceipt.data).state.sources, [left, right])
    }

    func testPersistenceReceiptsAreDeterministicAndOwnDecodedDataSnapshot() throws {
        let dataset = try makeDataset(left: "a,b", right: "x,y")
        let state = makeState(
            dataset: dataset,
            filters: [
                TableWorkspaceColumnFilter(
                    identifier: "value",
                    columnIndex: 1,
                    condition: .valueEquals(side: .left, value: "b")
                )
            ],
            selection: .column(1)
        )

        let first = try state.encoded()
        let second = try state.encoded()
        XCTAssertEqual(first, second)

        var mutableData = first.data
        let decoded = try TableWorkspaceState.decode(from: mutableData)
        mutableData[0] = 0

        XCTAssertEqual(decoded.data, first.data)
        XCTAssertEqual(decoded.state, state)
        XCTAssertEqual(try decoded.state.encoded().data, first.data)
    }

    func testDecodeSnapshotsExternallyMutableByteBacking() throws {
        let original = try goldenPersistenceState().encoded().data
        let mutableBytes = UnsafeMutableRawPointer.allocate(byteCount: original.count, alignment: 1)
        original.copyBytes(
            to: mutableBytes.assumingMemoryBound(to: UInt8.self),
            count: original.count
        )
        let sharedInput = Data(
            bytesNoCopy: mutableBytes,
            count: original.count,
            deallocator: .custom { bytes, _ in bytes.deallocate() }
        )

        let decoded = try TableWorkspaceState.decode(from: sharedInput)
        mutableBytes.storeBytes(of: UInt8(0), as: UInt8.self)

        XCTAssertEqual(sharedInput[0], 0)
        XCTAssertEqual(decoded.data, original)
        XCTAssertEqual(decoded.state, goldenPersistenceState())
    }

    func testComparisonAndPlanReceiptsAreDeterministicForSameAuthority() async throws {
        let dataset = try makeDataset(left: "a,b", right: "a,c")
        let executor = WorkspaceExecutor(
            sourceData: [.left: Data("a,b".utf8), .right: Data("a,c".utf8)]
        )

        let firstReceipt = try await executor.compare(dataset: dataset)
        let secondReceipt = try await executor.compare(dataset: dataset)
        let state = makeState(dataset: dataset)
        let firstPlan = try TableWorkspacePolicy.plan(
            TableWorkspaceRequest(comparisonReceipt: firstReceipt, state: state)
        )
        let secondPlan = try TableWorkspacePolicy.plan(
            TableWorkspaceRequest(comparisonReceipt: secondReceipt, state: state)
        )

        XCTAssertEqual(firstReceipt, secondReceipt)
        XCTAssertEqual(firstPlan, secondPlan)
        XCTAssertEqual(firstPlan.receipt.planningWorkUnits, secondPlan.receipt.planningWorkUnits)
    }

    func testPersistenceRejectsMalformedVersionCountOrderAndTrailingData() throws {
        let dataset = try makeDataset(left: "a", right: "b")
        let encoded = try makeState(dataset: dataset).encoded().data

        var badMagic = encoded
        badMagic[0] = 0
        assertPolicyError(.malformedPersistence) {
            _ = try TableWorkspaceState.decode(from: badMagic)
        }

        var badVersion = encoded
        badVersion[4] = 2
        assertPolicyError(.unsupportedSchemaVersion(2)) {
            _ = try TableWorkspaceState.decode(from: badVersion)
        }

        var badCount = encoded
        badCount[29] = 1
        assertPolicyError(.sourceCountInvalid(1)) {
            _ = try TableWorkspaceState.decode(from: badCount)
        }

        var noncanonicalSides = encoded
        noncanonicalSides[30] = 1
        noncanonicalSides[112] = 0
        assertPolicyError(.malformedPersistence) {
            _ = try TableWorkspaceState.decode(from: noncanonicalSides)
        }

        var trailing = encoded
        trailing.append(0)
        assertPolicyError(.trailingPersistenceData) {
            _ = try TableWorkspaceState.decode(from: trailing)
        }

        assertPolicyError(.malformedPersistence) {
            _ = try TableWorkspaceState.decode(from: Data(encoded.dropLast()))
        }
    }

    func testPersistenceRejectsNoncanonicalStringsAndInvalidPersistedSelection() throws {
        let dataset = try makeDataset(left: "a,b", right: "x,y")
        let decomposed = "e\u{301}"
        let identifierState = makeState(
            dataset: dataset,
            filters: [statusFilter(identifier: decomposed)]
        )
        assertPolicyError(.nonCanonicalPersistenceString("columnFilters.identifier")) {
            _ = try identifierState.encoded()
        }

        let valueState = makeState(
            dataset: dataset,
            filters: [
                TableWorkspaceColumnFilter(
                    identifier: "value",
                    columnIndex: 0,
                    condition: .valueEquals(side: .left, value: decomposed)
                )
            ]
        )
        assertPolicyError(.nonCanonicalPersistenceString("columnFilters.value")) {
            _ = try valueState.encoded()
        }

        let selections: [TableWorkspaceSelection] = [
            .column(-1),
            .column(2),
            .cells(anchor: address(-1, 0), focus: address(0, 0)),
            .cells(anchor: address(0, -1), focus: address(0, 0)),
            .cells(anchor: address(0, 0), focus: address(0, 2))
        ]
        for selection in selections {
            assertPolicyError(.selectionOutOfBounds) {
                _ = try makeState(dataset: dataset, selection: selection).encoded()
            }
        }
    }

    func testDecodeRejectsCraftedNoncanonicalFilterStringAndOutOfRangeSelection() throws {
        let encoded = try goldenPersistenceState().encoded().data
        var noncanonical = encoded
        replaceUInt32(in: &noncanonical, at: 283, with: 3)
        noncanonical.replaceSubrange(287..<288, with: [0x65, 0xCC, 0x81])
        assertPolicyError(.nonCanonicalPersistenceString("columnFilters.identifier")) {
            _ = try TableWorkspaceState.decode(from: noncanonical)
        }

        var outOfRangeSelection = encoded
        replaceUInt64(in: &outOfRangeSelection, at: 345, with: 1)
        assertPolicyError(.selectionOutOfBounds) {
            _ = try TableWorkspaceState.decode(from: outOfRangeSelection)
        }

        var unrepresentableSelection = encoded
        replaceUInt64(in: &unrepresentableSelection, at: 345, with: UInt64.max)
        assertPolicyError(.malformedPersistence) {
            _ = try TableWorkspaceState.decode(from: unrepresentableSelection)
        }
    }

    func testPersistenceByteLimitAcceptsExactBoundaryAndRejectsOneBelow() throws {
        let dataset = try makeDataset(left: "a,b", right: "x,y")
        let state = makeState(dataset: dataset, selection: .column(1))
        let data = try state.encoded().data
        let exactLimits = policyLimits(maximumPersistedBytes: data.count)
        let tooSmallLimits = policyLimits(maximumPersistedBytes: data.count - 1)

        XCTAssertEqual(try state.encoded(limits: exactLimits).data, data)
        XCTAssertEqual(try TableWorkspaceState.decode(from: data, limits: exactLimits).state, state)
        assertPolicyError(.persistenceDataTooLarge(maximumBytes: data.count - 1)) {
            _ = try state.encoded(limits: tooSmallLimits)
        }
        assertPolicyError(.persistenceDataTooLarge(maximumBytes: data.count - 1)) {
            _ = try TableWorkspaceState.decode(from: data, limits: tooSmallLimits)
        }
    }

    func testPlanDomainLimitsAcceptExactRowsColumnsCellsAndPresentedBytes() async throws {
        let fixture = try await makeFixture(left: "a,b\nc,d", right: "a,b\nc,e")
        let presentedBytes = fixture.comparisonReceipt.result.rows.reduce(into: 0) { total, row in
            total += row.cells.reduce(into: 0) { cellTotal, cell in
                cellTotal += cell.left?.value.utf8.count ?? 0
                cellTotal += cell.right?.value.utf8.count ?? 0
            }
        }
        let exact = policyLimits(
            maximumRows: 2,
            maximumColumns: 2,
            maximumCells: 4,
            maximumPresentedUTF8Bytes: presentedBytes
        )

        XCTAssertNoThrow(try TableWorkspacePolicy.plan(fixture.request(limits: exact)))
        assertPolicyError(.tooManyRows(maximum: 1)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    limits: policyLimits(
                        maximumRows: 1,
                        maximumColumns: 2,
                        maximumCells: 4,
                        maximumPresentedUTF8Bytes: presentedBytes
                    )
                )
            )
        }
        assertPolicyError(.tooManyColumns(maximum: 1)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    limits: policyLimits(
                        maximumRows: 2,
                        maximumColumns: 1,
                        maximumCells: 4,
                        maximumPresentedUTF8Bytes: presentedBytes
                    )
                )
            )
        }
        assertPolicyError(.tooManyCells(maximum: 3)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    limits: policyLimits(
                        maximumRows: 2,
                        maximumColumns: 2,
                        maximumCells: 3,
                        maximumPresentedUTF8Bytes: presentedBytes
                    )
                )
            )
        }
        assertPolicyError(.presentedValuesTooLarge(maximumUTF8Bytes: presentedBytes - 1)) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    limits: policyLimits(
                        maximumRows: 2,
                        maximumColumns: 2,
                        maximumCells: 4,
                        maximumPresentedUTF8Bytes: presentedBytes - 1
                    )
                )
            )
        }
    }

    func testFilterByteLimitsAcceptExactUTF8Boundaries() async throws {
        let fixture = try await makeFixture(left: "\u{E9}", right: "x")
        let filter = TableWorkspaceColumnFilter(
            identifier: "id",
            columnIndex: 0,
            condition: .valueEquals(side: .left, value: "\u{E9}")
        )
        let limits = policyLimits(
            maximumColumnFilters: 1,
            maximumFilterIdentifierUTF8Bytes: 2,
            maximumFilterValueUTF8Bytes: 2,
            maximumTotalFilterUTF8Bytes: 4
        )

        XCTAssertNoThrow(
            try TableWorkspacePolicy.plan(
                fixture.request(
                    state: makeState(dataset: fixture.dataset, filters: [filter]),
                    limits: limits
                )
            )
        )
    }

    func testPlanningWorkLimitAcceptsExactReceiptCountAndRejectsOneBelow() async throws {
        let fixture = try await makeFixture(left: "a,b\nc,d", right: "a,b\nc,e")
        let baseline = try TableWorkspacePolicy.plan(fixture.request())
        let exactLimits = policyLimits(maximumPlanningWorkUnits: baseline.receipt.planningWorkUnits)
        let exact = try TableWorkspacePolicy.plan(fixture.request(limits: exactLimits))

        XCTAssertEqual(exact.receipt.planningWorkUnits, baseline.receipt.planningWorkUnits)
        assertPolicyError(
            .planningWorkLimitExceeded(maximum: baseline.receipt.planningWorkUnits - 1)
        ) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(
                    limits: policyLimits(
                        maximumPlanningWorkUnits: baseline.receipt.planningWorkUnits - 1
                    )
                )
            )
        }
    }

    func testPlanningWorkVectorsHaveIndependentExactCountsAndLimits() async throws {
        let empty = try await makeFixture(left: "", right: "")
        let base = try await makeFixture(left: "a", right: "b")
        let status = statusFilter(identifier: "x", status: .modified)
        let value = TableWorkspaceColumnFilter(
            identifier: "x",
            columnIndex: 0,
            condition: .valueEquals(side: .left, value: "a")
        )
        let edit = editRequest(
            side: .left,
            row: 0,
            column: 0,
            expected: "a",
            replacement: "c"
        )
        let vectors: [(String, Fixture, TableWorkspaceState?, TableWorkspaceEditRequest?, Int)] = [
            ("empty", empty, nil, nil, 2),
            ("base", base, nil, nil, 17),
            (
                "status",
                base,
                makeState(dataset: base.dataset, filters: [status]),
                nil,
                21
            ),
            (
                "value",
                base,
                makeState(dataset: base.dataset, filters: [value]),
                nil,
                23
            ),
            ("edit", base, nil, edit, 20)
        ]

        for (name, fixture, state, editRequest, expectedWork) in vectors {
            let exact = try TableWorkspacePolicy.plan(
                fixture.request(
                    state: state,
                    editRequest: editRequest,
                    limits: policyLimits(maximumPlanningWorkUnits: expectedWork)
                )
            )
            XCTAssertEqual(exact.receipt.planningWorkUnits, expectedWork, name)
            assertPolicyError(
                .planningWorkLimitExceeded(maximum: expectedWork - 1),
                context: name
            ) {
                _ = try TableWorkspacePolicy.plan(
                    fixture.request(
                        state: state,
                        editRequest: editRequest,
                        limits: policyLimits(maximumPlanningWorkUnits: expectedWork - 1)
                    )
                )
            }
        }
    }

    func testEveryPolicyLimitRejectsValuesOutsideExactHardBoundaries() throws {
        let dataset = try makeDataset(left: "a", right: "b")
        let state = makeState(dataset: dataset)
        let invalid: [(TableWorkspacePolicyLimit, TableWorkspacePolicyLimits)] = [
            (.sourceCount, policyLimits(maximumSourceCount: 1)),
            (.sourceCount, policyLimits(maximumSourceCount: 3)),
            (.rows, policyLimits(maximumRows: -1)),
            (.rows, policyLimits(maximumRows: TableWorkspacePolicyLimits.hardMaximumRows + 1)),
            (.columns, policyLimits(maximumColumns: -1)),
            (
                .columns,
                policyLimits(maximumColumns: TableWorkspacePolicyLimits.hardMaximumColumns + 1)
            ),
            (.cells, policyLimits(maximumCells: -1)),
            (.cells, policyLimits(maximumCells: TableWorkspacePolicyLimits.hardMaximumCells + 1)),
            (.presentedUTF8Bytes, policyLimits(maximumPresentedUTF8Bytes: -1)),
            (
                .presentedUTF8Bytes,
                policyLimits(
                    maximumPresentedUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumPresentedUTF8Bytes + 1
                )
            ),
            (.columnFilters, policyLimits(maximumColumnFilters: -1)),
            (
                .columnFilters,
                policyLimits(
                    maximumColumnFilters: TableWorkspacePolicyLimits.hardMaximumColumnFilters + 1
                )
            ),
            (.filterIdentifierUTF8Bytes, policyLimits(maximumFilterIdentifierUTF8Bytes: 0)),
            (
                .filterIdentifierUTF8Bytes,
                policyLimits(
                    maximumFilterIdentifierUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumFilterIdentifierUTF8Bytes + 1
                )
            ),
            (.filterValueUTF8Bytes, policyLimits(maximumFilterValueUTF8Bytes: -1)),
            (
                .filterValueUTF8Bytes,
                policyLimits(
                    maximumFilterValueUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumFilterValueUTF8Bytes + 1
                )
            ),
            (.totalFilterUTF8Bytes, policyLimits(maximumTotalFilterUTF8Bytes: -1)),
            (
                .totalFilterUTF8Bytes,
                policyLimits(
                    maximumTotalFilterUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumTotalFilterUTF8Bytes + 1
                )
            ),
            (.editValueUTF8Bytes, policyLimits(maximumEditValueUTF8Bytes: -1)),
            (
                .editValueUTF8Bytes,
                policyLimits(
                    maximumEditValueUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumEditValueUTF8Bytes + 1
                )
            ),
            (.persistedBytes, policyLimits(maximumPersistedBytes: 0)),
            (
                .persistedBytes,
                policyLimits(
                    maximumPersistedBytes: TableWorkspacePolicyLimits.hardMaximumPersistedBytes + 1
                )
            ),
            (.planningWorkUnits, policyLimits(maximumPlanningWorkUnits: 0)),
            (
                .planningWorkUnits,
                policyLimits(
                    maximumPlanningWorkUnits: TableWorkspacePolicyLimits.hardMaximumPlanningWorkUnits + 1
                )
            ),
            (.cancellationCheckInterval, policyLimits(cancellationCheckInterval: 0)),
            (
                .cancellationCheckInterval,
                policyLimits(
                    cancellationCheckInterval: TableWorkspacePolicyLimits.hardMaximumCancellationCheckInterval + 1
                )
            )
        ]

        for (limit, limits) in invalid {
            assertPolicyError(.invalidLimit(limit)) {
                _ = try state.encoded(limits: limits)
            }
        }
    }

    func testPolicyHardMaximumLimitsAreAcceptedWithoutClamping() throws {
        let dataset = try makeDataset(left: "a", right: "b")
        let limits = policyLimits(
            maximumRows: TableWorkspacePolicyLimits.hardMaximumRows,
            maximumColumns: TableWorkspacePolicyLimits.hardMaximumColumns,
            maximumCells: TableWorkspacePolicyLimits.hardMaximumCells,
            maximumPresentedUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumPresentedUTF8Bytes,
            maximumColumnFilters: TableWorkspacePolicyLimits.hardMaximumColumnFilters,
            maximumFilterIdentifierUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumFilterIdentifierUTF8Bytes,
            maximumFilterValueUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumFilterValueUTF8Bytes,
            maximumTotalFilterUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumTotalFilterUTF8Bytes,
            maximumEditValueUTF8Bytes: TableWorkspacePolicyLimits.hardMaximumEditValueUTF8Bytes,
            maximumPersistedBytes: TableWorkspacePolicyLimits.hardMaximumPersistedBytes,
            maximumPlanningWorkUnits: TableWorkspacePolicyLimits.hardMaximumPlanningWorkUnits,
            cancellationCheckInterval: TableWorkspacePolicyLimits.hardMaximumCancellationCheckInterval
        )

        XCTAssertNoThrow(try makeState(dataset: dataset).encoded(limits: limits))
    }

    func testFormatAndComparisonConfigurationGuardsReturnTypedErrors() throws {
        let dataset = try makeDataset(left: "a", right: "b")
        let invalidFormats: [(String, TableWorkspaceFormatSettings)] = [
            ("delimiter", TableWorkspaceFormatSettings(delimiter: "\n")),
            ("delimiterCanonicalForm", TableWorkspaceFormatSettings(delimiter: "\u{212B}")),
            ("quote", TableWorkspaceFormatSettings(quote: "\r")),
            ("delimiterMatchesQuote", TableWorkspaceFormatSettings(delimiter: "|", quote: "|")),
            ("quoteCanonicalForm", TableWorkspaceFormatSettings(delimiter: "|", quote: "\u{212B}")),
            (
                "maximumInputBytes",
                TableWorkspaceFormatSettings(
                    limits: TableWorkspaceParsingLimits(maximumInputBytes: -1)
                )
            ),
            (
                "maximumRows",
                TableWorkspaceFormatSettings(limits: TableWorkspaceParsingLimits(maximumRows: 0))
            ),
            (
                "maximumColumnsPerRow",
                TableWorkspaceFormatSettings(
                    limits: TableWorkspaceParsingLimits(maximumColumnsPerRow: 0)
                )
            ),
            (
                "maximumTotalCells",
                TableWorkspaceFormatSettings(
                    limits: TableWorkspaceParsingLimits(maximumTotalCells: 0)
                )
            ),
            (
                "maximumCellBytes",
                TableWorkspaceFormatSettings(
                    limits: TableWorkspaceParsingLimits(maximumCellBytes: -1)
                )
            )
        ]

        for (name, format) in invalidFormats {
            let state = makeState(
                dataset: dataset,
                configuration: TableWorkspaceConfiguration(format: format)
            )
            assertPolicyError(.invalidFormat(name)) {
                _ = try state.encoded()
            }
        }

        let comparisonCases: [(String, TableWorkspaceComparisonSettings)] = [
            (
                "maximumExactEditDistance",
                TableWorkspaceComparisonSettings(maximumExactEditDistance: -1)
            ),
            (
                "maximumAlignmentWork",
                TableWorkspaceComparisonSettings(maximumAlignmentWork: -1)
            ),
            (
                "maximumComparedRows",
                TableWorkspaceComparisonSettings(maximumComparedRows: -1)
            ),
            (
                "maximumComparedCells",
                TableWorkspaceComparisonSettings(maximumComparedCells: -1)
            )
        ]
        for (name, comparison) in comparisonCases {
            let state = makeState(
                dataset: dataset,
                configuration: TableWorkspaceConfiguration(comparison: comparison)
            )
            assertPolicyError(.invalidComparisonSetting(name)) {
                _ = try state.encoded()
            }
        }
    }

    func testConfigurationLimitsAcceptExactEngineMaximaAndRejectOneOver() throws {
        let dataset = try makeDataset(left: "a", right: "b")
        let parsingMaximum = DelimitedTableLimits.default
        let comparisonMaximum = TableComparisonOptions.default
        let exact = TableWorkspaceConfiguration(
            format: TableWorkspaceFormatSettings(
                limits: TableWorkspaceParsingLimits(
                    maximumInputBytes: parsingMaximum.maximumInputBytes,
                    maximumRows: parsingMaximum.maximumRows,
                    maximumColumnsPerRow: parsingMaximum.maximumColumnsPerRow,
                    maximumTotalCells: parsingMaximum.maximumTotalCells,
                    maximumCellBytes: parsingMaximum.maximumCellBytes
                )
            ),
            comparison: TableWorkspaceComparisonSettings(
                maximumExactEditDistance: comparisonMaximum.maximumExactEditDistance,
                maximumAlignmentWork: comparisonMaximum.maximumAlignmentWork,
                maximumComparedRows: comparisonMaximum.maximumComparedRows,
                maximumComparedCells: comparisonMaximum.maximumComparedCells
            )
        )
        XCTAssertNoThrow(try makeState(dataset: dataset, configuration: exact).encoded())

        let parsingCases: [(String, TableWorkspaceParsingLimits)] = [
            (
                "maximumInputBytes",
                TableWorkspaceParsingLimits(
                    maximumInputBytes: parsingMaximum.maximumInputBytes + 1
                )
            ),
            (
                "maximumRows",
                TableWorkspaceParsingLimits(maximumRows: parsingMaximum.maximumRows + 1)
            ),
            (
                "maximumColumnsPerRow",
                TableWorkspaceParsingLimits(
                    maximumColumnsPerRow: parsingMaximum.maximumColumnsPerRow + 1
                )
            ),
            (
                "maximumTotalCells",
                TableWorkspaceParsingLimits(
                    maximumTotalCells: parsingMaximum.maximumTotalCells + 1
                )
            ),
            (
                "maximumCellBytes",
                TableWorkspaceParsingLimits(
                    maximumCellBytes: parsingMaximum.maximumCellBytes + 1
                )
            )
        ]
        for (name, limits) in parsingCases {
            let state = makeState(
                dataset: dataset,
                configuration: TableWorkspaceConfiguration(
                    format: TableWorkspaceFormatSettings(limits: limits)
                )
            )
            assertPolicyError(.invalidFormat(name)) {
                _ = try state.encoded()
            }
        }

        let comparisonCases: [(String, TableWorkspaceComparisonSettings)] = [
            (
                "maximumExactEditDistance",
                TableWorkspaceComparisonSettings(
                    maximumExactEditDistance: comparisonMaximum.maximumExactEditDistance + 1
                )
            ),
            (
                "maximumAlignmentWork",
                TableWorkspaceComparisonSettings(
                    maximumAlignmentWork: comparisonMaximum.maximumAlignmentWork + 1
                )
            ),
            (
                "maximumComparedRows",
                TableWorkspaceComparisonSettings(
                    maximumComparedRows: comparisonMaximum.maximumComparedRows + 1
                )
            ),
            (
                "maximumComparedCells",
                TableWorkspaceComparisonSettings(
                    maximumComparedCells: comparisonMaximum.maximumComparedCells + 1
                )
            )
        ]
        for (name, comparison) in comparisonCases {
            let state = makeState(
                dataset: dataset,
                configuration: TableWorkspaceConfiguration(comparison: comparison)
            )
            assertPolicyError(.invalidComparisonSetting(name)) {
                _ = try state.encoded()
            }
        }
    }

    func testConfigurationAndBindingShapesAcceptExactMinimaAndIndependentMaxima() throws {
        let minimumConfiguration = TableWorkspaceConfiguration(
            format: TableWorkspaceFormatSettings(
                quote: nil,
                allowsNewlinesInQuotedCells: false,
                limits: TableWorkspaceParsingLimits(
                    maximumInputBytes: 0,
                    maximumRows: 1,
                    maximumColumnsPerRow: 1,
                    maximumTotalCells: 1,
                    maximumCellBytes: 0
                )
            ),
            comparison: TableWorkspaceComparisonSettings(
                maximumExactEditDistance: 0,
                maximumAlignmentWork: 0,
                maximumComparedRows: 0,
                maximumComparedCells: 0
            )
        )
        let emptyShape = TableWorkspaceTableShape(
            sourceUTF8ByteCount: 0,
            rowCount: 0,
            maximumColumnCount: 0,
            totalCellCount: 0
        )
        let minimumState = TableWorkspaceState(
            datasetReference: makeReference(),
            sources: [
                rawBinding(side: .left, shape: emptyShape, identitySeed: 1),
                rawBinding(side: .right, shape: emptyShape, identitySeed: 2)
            ],
            configuration: minimumConfiguration
        )
        XCTAssertNoThrow(try minimumState.encoded())

        let parsing = DelimitedTableLimits.default
        let maximumConfiguration = TableWorkspaceConfiguration(
            format: TableWorkspaceFormatSettings(
                limits: TableWorkspaceParsingLimits(
                    maximumInputBytes: parsing.maximumInputBytes,
                    maximumRows: parsing.maximumRows,
                    maximumColumnsPerRow: parsing.maximumColumnsPerRow,
                    maximumTotalCells: parsing.maximumTotalCells,
                    maximumCellBytes: parsing.maximumCellBytes
                )
            )
        )
        let maximumShapes = [
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: parsing.maximumInputBytes,
                rowCount: 1,
                maximumColumnCount: 1,
                totalCellCount: 1
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: 1,
                rowCount: parsing.maximumRows,
                maximumColumnCount: 1,
                totalCellCount: parsing.maximumRows
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: 1,
                rowCount: 1,
                maximumColumnCount: parsing.maximumColumnsPerRow,
                totalCellCount: parsing.maximumColumnsPerRow
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: 1,
                rowCount: 64,
                maximumColumnCount: parsing.maximumColumnsPerRow,
                totalCellCount: parsing.maximumTotalCells
            )
        ]

        for (index, shape) in maximumShapes.enumerated() {
            let state = TableWorkspaceState(
                datasetReference: makeReference(identitySeed: UInt8(index + 10)),
                sources: [
                    rawBinding(side: .left, shape: shape, identitySeed: UInt8(index + 10)),
                    rawBinding(side: .right, shape: emptyShape, identitySeed: UInt8(index + 20))
                ],
                configuration: maximumConfiguration
            )
            XCTAssertNoThrow(try state.encoded(), "shape \(index)")
        }
    }

    func testBindingShapeGuardsRejectEachInvalidDimension() throws {
        let dataset = try makeDataset(left: "a,b", right: "x,y")
        let left = try XCTUnwrap(dataset.source(.left))
        let right = try XCTUnwrap(dataset.source(.right))
        let invalidShapes = [
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: -1,
                rowCount: left.shape.rowCount,
                maximumColumnCount: left.shape.maximumColumnCount,
                totalCellCount: left.shape.totalCellCount
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: left.shape.sourceUTF8ByteCount,
                rowCount: -1,
                maximumColumnCount: left.shape.maximumColumnCount,
                totalCellCount: left.shape.totalCellCount
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: left.shape.sourceUTF8ByteCount,
                rowCount: left.shape.rowCount,
                maximumColumnCount: -1,
                totalCellCount: left.shape.totalCellCount
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: left.shape.sourceUTF8ByteCount,
                rowCount: left.shape.rowCount,
                maximumColumnCount: left.shape.maximumColumnCount,
                totalCellCount: -1
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: 0,
                rowCount: 0,
                maximumColumnCount: 1,
                totalCellCount: 0
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: 1,
                rowCount: 1,
                maximumColumnCount: 0,
                totalCellCount: 1
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: left.shape.sourceUTF8ByteCount,
                rowCount: 2,
                maximumColumnCount: 2,
                totalCellCount: 2
            ),
            TableWorkspaceTableShape(
                sourceUTF8ByteCount: left.shape.sourceUTF8ByteCount,
                rowCount: 1,
                maximumColumnCount: 2,
                totalCellCount: 3
            )
        ]

        for shape in invalidShapes {
            let changed = copyBinding(left, shape: shape)
            let state = makeState(dataset: dataset, sources: [changed, right])
            assertPolicyError(.shapeMismatch(.left)) {
                _ = try state.encoded()
            }
        }
    }

    func testStatePersistenceRequiresExactTwoDistinctSides() throws {
        let left = try makeBinding(side: .left, input: "a")
        let right = try makeBinding(side: .right, input: "b")
        let reference = makeReference()

        for sources in [[], [left], [left, right, left]] {
            let state = TableWorkspaceState(
                datasetReference: reference,
                sources: sources,
                configuration: .default
            )
            assertPolicyError(.sourceCountInvalid(sources.count)) {
                _ = try state.encoded()
            }
        }

        let duplicate = TableWorkspaceState(
            datasetReference: reference,
            sources: [left, copyBinding(left, sourceRevision: 2)],
            configuration: .default
        )
        assertPolicyError(.duplicateSide(.left)) {
            _ = try duplicate.encoded()
        }

        let rightDuplicate = TableWorkspaceState(
            datasetReference: reference,
            sources: [right, copyBinding(right, tableRevision: 2)],
            configuration: .default
        )
        assertPolicyError(.duplicateSide(.right)) {
            _ = try rightDuplicate.encoded()
        }
    }

    func testCancellationErrorsAreNormalizedAtPlanEncodeAndDecodeBoundaries() async throws {
        let fixture = try await makeFixture()
        let cancellation: @Sendable () throws -> Void = { throw CancellationError() }

        assertPolicyError(.cancelled) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(),
                cancellationCheck: cancellation
            )
        }
        assertPolicyError(.cancelled) {
            _ = try fixture.state.encoded(cancellationCheck: cancellation)
        }
        let data = try fixture.state.encoded().data
        assertPolicyError(.cancelled) {
            _ = try TableWorkspaceState.decode(from: data, cancellationCheck: cancellation)
        }
    }

    func testLargePlanningWorkChecksCancellationPeriodically() async throws {
        let wideRow = Array(repeating: "value", count: 2_048).joined(separator: ",")
        let fixture = try await makeFixture(left: wideRow, right: wideRow)
        let probe = CancellationProbe(throwOnCall: 8)
        let limits = policyLimits(cancellationCheckInterval: 64)

        assertPolicyError(.cancelled) {
            _ = try TableWorkspacePolicy.plan(
                fixture.request(limits: limits),
                cancellationCheck: probe.check
            )
        }
        XCTAssertEqual(probe.callCount, 8)
    }

    func testPlanningCancellationCadenceMatchesEntryWorkBoundariesAndExit() async throws {
        let fixture = try await makeFixture(left: "", right: "")

        for (interval, expectedCalls) in [(1, 4), (2, 3), (3, 2)] {
            let probe = CancellationProbe(throwOnCall: .max)
            let plan = try TableWorkspacePolicy.plan(
                fixture.request(limits: policyLimits(cancellationCheckInterval: interval)),
                cancellationCheck: probe.check
            )
            XCTAssertEqual(plan.receipt.planningWorkUnits, 2)
            XCTAssertEqual(probe.callCount, expectedCalls, "interval \(interval)")
        }
    }

    func testPersistenceChecksCancellationDuringLargeFilterWorkAndDecodeLoop() throws {
        let dataset = try makeDataset(left: "a", right: "b")
        let filters = (0..<64).map { index in
            TableWorkspaceColumnFilter(
                identifier: "filter-\(index)",
                columnIndex: 0,
                condition: .status(.equal)
            )
        }
        let state = makeState(dataset: dataset, filters: filters)
        let limits = policyLimits(cancellationCheckInterval: 8)
        let encodeProbe = CancellationProbe(throwOnCall: 6)

        assertPolicyError(.cancelled) {
            _ = try state.encoded(limits: limits, cancellationCheck: encodeProbe.check)
        }
        XCTAssertEqual(encodeProbe.callCount, 6)

        let data = try state.encoded(limits: limits).data
        let decodeProbe = CancellationProbe(throwOnCall: 6)
        assertPolicyError(.cancelled) {
            _ = try TableWorkspaceState.decode(
                from: data,
                limits: limits,
                cancellationCheck: decodeProbe.check
            )
        }
        XCTAssertEqual(decodeProbe.callCount, 6)
    }

    func testEncodeDecodeCancellationCadenceUsesExactEntryLoopWorkAndExitChecks() throws {
        let dataset = try makeDataset(left: "a", right: "b")
        let noFilter = makeState(dataset: dataset)
        let oneFilter = makeState(
            dataset: dataset,
            filters: [statusFilter(identifier: "x")]
        )
        let limits = policyLimits(cancellationCheckInterval: 1)

        let noFilterEncode = CancellationProbe(throwOnCall: .max)
        let noFilterData = try noFilter.encoded(
            limits: limits,
            cancellationCheck: noFilterEncode.check
        ).data
        XCTAssertEqual(noFilterEncode.callCount, 4)
        let noFilterDecode = CancellationProbe(throwOnCall: .max)
        _ = try TableWorkspaceState.decode(
            from: noFilterData,
            limits: limits,
            cancellationCheck: noFilterDecode.check
        )
        XCTAssertEqual(noFilterDecode.callCount, 4)

        let oneFilterEncode = CancellationProbe(throwOnCall: .max)
        let oneFilterData = try oneFilter.encoded(
            limits: limits,
            cancellationCheck: oneFilterEncode.check
        ).data
        XCTAssertEqual(oneFilterEncode.callCount, 7)
        let oneFilterDecode = CancellationProbe(throwOnCall: .max)
        _ = try TableWorkspaceState.decode(
            from: oneFilterData,
            limits: limits,
            cancellationCheck: oneFilterDecode.check
        )
        XCTAssertEqual(oneFilterDecode.callCount, 7)
    }

    func testDefaultCancellationHonorsPrecancelledTask() async throws {
        let fixture = try await makeFixture()
        let data = try fixture.state.encoded().data
        let outcome = await Task.detached { @Sendable [fixture, data] in
            withUnsafeCurrentTask { $0?.cancel() }
            var errors: [TableWorkspacePolicyError?] = []
            do {
                _ = try TableWorkspacePolicy.plan(fixture.request())
                errors.append(nil)
            } catch {
                errors.append(error as? TableWorkspacePolicyError)
            }
            do {
                _ = try fixture.state.encoded()
                errors.append(nil)
            } catch {
                errors.append(error as? TableWorkspacePolicyError)
            }
            do {
                _ = try TableWorkspaceState.decode(from: data)
                errors.append(nil)
            } catch {
                errors.append(error as? TableWorkspacePolicyError)
            }
            do {
                try TableWorkspacePolicy.checkCancellation()
                errors.append(nil)
            } catch {
                errors.append(error as? TableWorkspacePolicyError)
            }
            return errors
        }.value

        XCTAssertEqual(outcome, [.cancelled, .cancelled, .cancelled, .cancelled])
    }

    func testTypedErrorsAreHashableSendableAndDescribeGuard() {
        let errors: [TableWorkspacePolicyError] = [
            .cancelled,
            .invalidLimit(.cells),
            .staleDatasetRevision(expected: 2, actual: 1),
            .duplicateSide(.left),
            .invalidTable(
                side: .right,
                issue: .cellValueTooLarge(row: 1, column: 2, maximumUTF8Bytes: 3)
            ),
            .invalidComparisonResult(.invalidCellStatus(row: 1, column: 2)),
            .filterColumnOutOfBounds(identifier: "id", columnIndex: 4),
            .editTargetReadOnly(.right),
            .persistenceDataTooLarge(maximumBytes: 5)
        ]

        XCTAssertEqual(Set(errors).count, errors.count)
        XCTAssertTrue(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
        requireSendable(errors)
    }

    private struct Fixture: Sendable {
        let dataset: TableWorkspaceDatasetSnapshot
        let state: TableWorkspaceState
        let comparisonReceipt: TableWorkspaceComparisonReceipt

        func request(
            state: TableWorkspaceState? = nil,
            editRequest: TableWorkspaceEditRequest? = nil,
            limits: TableWorkspacePolicyLimits = .default
        ) -> TableWorkspaceRequest {
            TableWorkspaceRequest(
                comparisonReceipt: comparisonReceipt,
                state: state ?? self.state,
                editRequest: editRequest,
                limits: limits
            )
        }
    }

    private struct EditValidationContext: Sendable {
        let fixture: Fixture
        let plan: TableWorkspacePlan
        let intent: TableWorkspaceEditIntent
        let validResult: TableWorkspaceDatasetSnapshot
    }

    private func makeFixture(
        left: String = "name,value\nremove,left\nanchor,one\nold,keep\nanchor,two\ntail,end",
        right: String = "name,value\nanchor,one\nnew,keep,extra\nanchor,two\nadd,right\ntail,end",
        configuration: TableWorkspaceConfiguration = .default,
        leftEditable: Bool = true,
        rightEditable: Bool = true
    ) async throws -> Fixture {
        let dataset = try makeDataset(
            left: left,
            right: right,
            configuration: configuration,
            leftEditable: leftEditable,
            rightEditable: rightEditable
        )
        let executor = WorkspaceExecutor(
            sourceData: [.left: Data(left.utf8), .right: Data(right.utf8)]
        )
        return Fixture(
            dataset: dataset,
            state: makeState(dataset: dataset),
            comparisonReceipt: try await executor.compare(dataset: dataset)
        )
    }

    private func makeEditValidationContext() async throws -> EditValidationContext {
        let fixture = try await makeFixture()
        let edit = editRequest(
            side: .left,
            row: 3,
            column: 0,
            expected: "old",
            replacement: "newer"
        )
        let plan = try TableWorkspacePolicy.plan(fixture.request(editRequest: edit))
        return EditValidationContext(
            fixture: fixture,
            plan: plan,
            intent: try XCTUnwrap(plan.editIntent),
            validResult: validResultingDataset(from: fixture.dataset, editedSide: .left)
        )
    }

    private func makeDataset(
        left: String,
        right: String,
        configuration: TableWorkspaceConfiguration = .default,
        leftEditable: Bool = true,
        rightEditable: Bool = true
    ) throws -> TableWorkspaceDatasetSnapshot {
        makeDataset(
            sources: [
                try makeBinding(
                    side: .left,
                    input: left,
                    configuration: configuration,
                    isEditable: leftEditable,
                    identitySeed: 1
                ),
                try makeBinding(
                    side: .right,
                    input: right,
                    configuration: configuration,
                    isEditable: rightEditable,
                    identitySeed: 2
                )
            ],
            configuration: configuration
        )
    }

    private func makeDataset(
        sources: [TableWorkspaceSourceBinding],
        configuration: TableWorkspaceConfiguration = .default,
        reference: TableWorkspaceDatasetReference = makeReference()
    ) -> TableWorkspaceDatasetSnapshot {
        TableWorkspaceDatasetSnapshot(
            reference: reference,
            configuration: configuration,
            sources: sources
        )
    }

    private func makeBinding(
        side: TableWorkspaceSide,
        input: String,
        configuration: TableWorkspaceConfiguration = .default,
        isEditable: Bool = true,
        revision: UInt64 = 1,
        identitySeed: UInt8 = 1
    ) throws -> TableWorkspaceSourceBinding {
        let table = try DelimitedTableParser.parse(input, options: configuration.format.parsingOptions)
        return TableWorkspaceSourceBinding(
            side: side,
            sourceIdentity: sourceIdentity(identitySeed),
            sourceRevision: revision,
            tableIdentity: tableIdentity(identitySeed),
            tableRevision: revision,
            shape: TableWorkspaceTableShape(
                sourceUTF8ByteCount: table.sourceUTF8ByteCount,
                rowCount: table.rows.count,
                maximumColumnCount: table.rows.map(\.cells.count).max() ?? 0,
                totalCellCount: table.totalCellCount
            ),
            isEditable: isEditable
        )
    }

    private func makeState(
        dataset: TableWorkspaceDatasetSnapshot,
        reference: TableWorkspaceDatasetReference? = nil,
        sources: [TableWorkspaceSourceBinding]? = nil,
        configuration: TableWorkspaceConfiguration? = nil,
        options: TableWorkspacePresentationOptions = .default,
        filters: [TableWorkspaceColumnFilter] = [],
        selection: TableWorkspaceSelection = .none
    ) -> TableWorkspaceState {
        TableWorkspaceState(
            datasetReference: reference ?? dataset.reference,
            sources: sources ?? dataset.sources,
            configuration: configuration ?? dataset.configuration,
            presentationOptions: options,
            columnFilters: filters,
            selection: selection
        )
    }

    private func copyDataset(
        _ dataset: TableWorkspaceDatasetSnapshot,
        reference: TableWorkspaceDatasetReference? = nil,
        configuration: TableWorkspaceConfiguration? = nil,
        sources: [TableWorkspaceSourceBinding]? = nil
    ) -> TableWorkspaceDatasetSnapshot {
        TableWorkspaceDatasetSnapshot(
            reference: reference ?? dataset.reference,
            configuration: configuration ?? dataset.configuration,
            sources: sources ?? dataset.sources
        )
    }

    private func copyBinding(
        _ binding: TableWorkspaceSourceBinding,
        sourceIdentity: TableWorkspaceSourceIdentity? = nil,
        sourceRevision: UInt64? = nil,
        tableIdentity: TableWorkspaceTableIdentity? = nil,
        tableRevision: UInt64? = nil,
        shape: TableWorkspaceTableShape? = nil,
        isEditable: Bool? = nil
    ) -> TableWorkspaceSourceBinding {
        TableWorkspaceSourceBinding(
            side: binding.side,
            sourceIdentity: sourceIdentity ?? binding.sourceIdentity,
            sourceRevision: sourceRevision ?? binding.sourceRevision,
            tableIdentity: tableIdentity ?? binding.tableIdentity,
            tableRevision: tableRevision ?? binding.tableRevision,
            shape: shape ?? binding.shape,
            isEditable: isEditable ?? binding.isEditable
        )
    }

    private func validResultingDataset(
        from dataset: TableWorkspaceDatasetSnapshot,
        editedSide: TableWorkspaceSide
    ) -> TableWorkspaceDatasetSnapshot {
        let sources = dataset.sources.map { binding in
            guard binding.side == editedSide else { return binding }
            return copyBinding(
                binding,
                sourceRevision: binding.sourceRevision + 1,
                tableRevision: binding.tableRevision + 1,
                shape: TableWorkspaceTableShape(
                    sourceUTF8ByteCount: binding.shape.sourceUTF8ByteCount + 1,
                    rowCount: binding.shape.rowCount,
                    maximumColumnCount: binding.shape.maximumColumnCount,
                    totalCellCount: binding.shape.totalCellCount
                )
            )
        }
        return copyDataset(
            dataset,
            reference: TableWorkspaceDatasetReference(
                identity: dataset.reference.identity,
                revision: dataset.reference.revision + 1
            ),
            sources: sources
        )
    }

    private func bindingMutations(
        _ binding: TableWorkspaceSourceBinding
    ) -> [(String, TableWorkspaceSourceBinding)] {
        let shape = binding.shape
        return [
            ("sourceIdentity", copyBinding(binding, sourceIdentity: sourceIdentity(63))),
            ("sourceRevision", copyBinding(binding, sourceRevision: binding.sourceRevision + 1)),
            ("tableIdentity", copyBinding(binding, tableIdentity: tableIdentity(63))),
            ("tableRevision", copyBinding(binding, tableRevision: binding.tableRevision + 1)),
            (
                "sourceUTF8ByteCount",
                copyBinding(
                    binding,
                    shape: TableWorkspaceTableShape(
                        sourceUTF8ByteCount: shape.sourceUTF8ByteCount + 1,
                        rowCount: shape.rowCount,
                        maximumColumnCount: shape.maximumColumnCount,
                        totalCellCount: shape.totalCellCount
                    )
                )
            ),
            (
                "rowCount",
                copyBinding(
                    binding,
                    shape: TableWorkspaceTableShape(
                        sourceUTF8ByteCount: shape.sourceUTF8ByteCount,
                        rowCount: shape.rowCount + 1,
                        maximumColumnCount: shape.maximumColumnCount,
                        totalCellCount: shape.totalCellCount
                    )
                )
            ),
            (
                "maximumColumnCount",
                copyBinding(
                    binding,
                    shape: TableWorkspaceTableShape(
                        sourceUTF8ByteCount: shape.sourceUTF8ByteCount,
                        rowCount: shape.rowCount,
                        maximumColumnCount: shape.maximumColumnCount + 1,
                        totalCellCount: shape.totalCellCount
                    )
                )
            ),
            (
                "totalCellCount",
                copyBinding(
                    binding,
                    shape: TableWorkspaceTableShape(
                        sourceUTF8ByteCount: shape.sourceUTF8ByteCount,
                        rowCount: shape.rowCount,
                        maximumColumnCount: shape.maximumColumnCount,
                        totalCellCount: shape.totalCellCount + 1
                    )
                )
            ),
            ("isEditable", copyBinding(binding, isEditable: !binding.isEditable))
        ]
    }

    private func rawBinding(
        side: TableWorkspaceSide,
        shape: TableWorkspaceTableShape,
        isEditable: Bool = true,
        identitySeed: UInt8
    ) -> TableWorkspaceSourceBinding {
        TableWorkspaceSourceBinding(
            side: side,
            sourceIdentity: sourceIdentity(identitySeed),
            sourceRevision: 1,
            tableIdentity: tableIdentity(identitySeed),
            tableRevision: 1,
            shape: shape,
            isEditable: isEditable
        )
    }

    private func goldenPersistenceState() -> TableWorkspaceState {
        func goldenBinding(
            side: TableWorkspaceSide,
            sourceSeed: UInt8,
            tableSeed: UInt8
        ) -> TableWorkspaceSourceBinding {
            TableWorkspaceSourceBinding(
                side: side,
                sourceIdentity: TableWorkspaceSourceIdentity(rawValue: seededUUID(sourceSeed)),
                sourceRevision: 2,
                tableIdentity: TableWorkspaceTableIdentity(rawValue: seededUUID(tableSeed)),
                tableRevision: 3,
                shape: TableWorkspaceTableShape(
                    sourceUTF8ByteCount: 1,
                    rowCount: 1,
                    maximumColumnCount: 1,
                    totalCellCount: 1
                ),
                isEditable: false
            )
        }

        return TableWorkspaceState(
            datasetReference: TableWorkspaceDatasetReference(
                identity: TableWorkspaceDatasetIdentity(rawValue: seededUUID(1)),
                revision: 2
            ),
            sources: [
                goldenBinding(side: .right, sourceSeed: 20, tableSeed: 52),
                goldenBinding(side: .left, sourceSeed: 10, tableSeed: 42)
            ],
            configuration: TableWorkspaceConfiguration(
                format: TableWorkspaceFormatSettings(
                    delimiter: "|",
                    quote: nil,
                    allowsNewlinesInQuotedCells: false,
                    limits: TableWorkspaceParsingLimits(
                        maximumInputBytes: 9,
                        maximumRows: 1,
                        maximumColumnsPerRow: 1,
                        maximumTotalCells: 1,
                        maximumCellBytes: 1
                    )
                ),
                comparison: TableWorkspaceComparisonSettings(
                    maximumExactEditDistance: 0,
                    maximumAlignmentWork: 0,
                    maximumComparedRows: 2,
                    maximumComparedCells: 2
                )
            ),
            presentationOptions: TableWorkspacePresentationOptions(
                headerVisibility: .hidden,
                headerLabels: .firstRecord,
                showsRowNumbers: false,
                wrapsCellText: true,
                synchronizesColumnWidths: false,
                highlightsCellDifferences: true
            ),
            columnFilters: [
                TableWorkspaceColumnFilter(
                    identifier: "s",
                    columnIndex: 0,
                    condition: .status(.modified),
                    disposition: .excludeMatchingRows
                ),
                TableWorkspaceColumnFilter(
                    identifier: "v",
                    columnIndex: 0,
                    condition: .valueEquals(side: .right, value: "x")
                ),
                TableWorkspaceColumnFilter(
                    identifier: "m",
                    columnIndex: 0,
                    condition: .missing(side: .left),
                    disposition: .excludeMatchingRows
                )
            ],
            selection: .cells(anchor: address(0, 0), focus: address(0, 0))
        )
    }

    private func dataFromHex(_ hex: String) -> Data {
        precondition(hex.count.isMultiple(of: 2))
        var data = Data()
        data.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index != hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                preconditionFailure("Invalid test hex")
            }
            data.append(byte)
            index = next
        }
        return data
    }

    private func replaceUInt32(in data: inout Data, at offset: Int, with value: UInt32) {
        data.replaceSubrange(
            offset..<(offset + 4),
            with: (0..<4).map { shift in
                UInt8((value >> UInt32((3 - shift) * 8)) & 0xFF)
            })
    }

    private func replaceUInt64(in data: inout Data, at offset: Int, with value: UInt64) {
        data.replaceSubrange(
            offset..<(offset + 8),
            with: (0..<8).map { shift in
                UInt8((value >> UInt64((7 - shift) * 8)) & 0xFF)
            })
    }

    private func configuration(
        delimiter: Character = ",",
        maximumCellBytes: Int = DelimitedTableLimits.default.maximumCellBytes
    ) -> TableWorkspaceConfiguration {
        TableWorkspaceConfiguration(
            format: TableWorkspaceFormatSettings(
                delimiter: delimiter,
                limits: TableWorkspaceParsingLimits(maximumCellBytes: maximumCellBytes)
            )
        )
    }

    private func policyLimits(
        maximumSourceCount: Int = 2,
        maximumRows: Int = 2_097_152,
        maximumColumns: Int = 16_384,
        maximumCells: Int = 2_097_152,
        maximumPresentedUTF8Bytes: Int = 192 * 1_024 * 1_024,
        maximumColumnFilters: Int = 4_096,
        maximumFilterIdentifierUTF8Bytes: Int = 1_024,
        maximumFilterValueUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumTotalFilterUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumEditValueUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumPersistedBytes: Int = 64 * 1_024 * 1_024,
        maximumPlanningWorkUnits: Int = 512 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 4_096
    ) -> TableWorkspacePolicyLimits {
        TableWorkspacePolicyLimits(
            maximumSourceCount: maximumSourceCount,
            maximumRows: maximumRows,
            maximumColumns: maximumColumns,
            maximumCells: maximumCells,
            maximumPresentedUTF8Bytes: maximumPresentedUTF8Bytes,
            maximumColumnFilters: maximumColumnFilters,
            maximumFilterIdentifierUTF8Bytes: maximumFilterIdentifierUTF8Bytes,
            maximumFilterValueUTF8Bytes: maximumFilterValueUTF8Bytes,
            maximumTotalFilterUTF8Bytes: maximumTotalFilterUTF8Bytes,
            maximumEditValueUTF8Bytes: maximumEditValueUTF8Bytes,
            maximumPersistedBytes: maximumPersistedBytes,
            maximumPlanningWorkUnits: maximumPlanningWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func statusFilter(
        identifier: String,
        status: TableWorkspaceComparisonStatus = .equal
    ) -> TableWorkspaceColumnFilter {
        TableWorkspaceColumnFilter(
            identifier: identifier,
            columnIndex: 0,
            condition: .status(status)
        )
    }

    private func editRequest(
        side: TableWorkspaceSide,
        row: Int,
        column: Int,
        expected: String,
        replacement: String
    ) -> TableWorkspaceEditRequest {
        TableWorkspaceEditRequest(
            side: side,
            address: address(row, column),
            expectedPresentedValue: expected,
            replacementPresentedValue: replacement
        )
    }

    private func assertPolicyError<T>(
        _ expected: TableWorkspacePolicyError,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? TableWorkspacePolicyError,
                expected,
                context,
                file: file,
                line: line
            )
        }
    }

    private func assertPolicyError<T>(
        _ expected: TableWorkspacePolicyError,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected): \(context)", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? TableWorkspacePolicyError,
                expected,
                context,
                file: file,
                line: line
            )
        }
    }
}

private struct WorkspaceExecutor: TableWorkspaceExecutor, Sendable {
    let sourceData: [TableWorkspaceSide: Data]
    let publication: TableWorkspaceDatasetSnapshot?

    init(
        sourceData: [TableWorkspaceSide: Data],
        publication: TableWorkspaceDatasetSnapshot? = nil
    ) {
        self.sourceData = sourceData
        self.publication = publication
    }

    func sourceUTF8Bytes(
        for source: TableWorkspaceSourceBinding,
        in _: TableWorkspaceDatasetSnapshot
    ) async throws -> Data {
        guard let data = sourceData[source.side] else { throw WorkspaceExecutorError.missingSource }
        return data
    }

    func publish(_: TableWorkspaceEditIntent) async throws -> TableWorkspaceDatasetSnapshot {
        guard let publication else { throw WorkspaceExecutorError.missingPublication }
        return publication
    }
}

private enum WorkspaceExecutorError: Error {
    case missingSource
    case missingPublication
    case verificationFailed
}

private final class VerifyingWorkspaceExecutor: TableWorkspaceExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private let expectedDataset: TableWorkspaceDatasetSnapshot?
    private let expectedSources: [TableWorkspaceSide: TableWorkspaceSourceBinding]
    private let sourceData: [TableWorkspaceSide: Data]
    private let expectedIntent: TableWorkspaceEditIntent?
    private let publication: TableWorkspaceDatasetSnapshot?
    private var sides: [TableWorkspaceSide] = []
    private var published: TableWorkspaceEditIntent?
    private var failure: String?

    init(
        expectedDataset: TableWorkspaceDatasetSnapshot? = nil,
        expectedSources: [TableWorkspaceSide: TableWorkspaceSourceBinding] = [:],
        sourceData: [TableWorkspaceSide: Data] = [:],
        expectedIntent: TableWorkspaceEditIntent? = nil,
        publication: TableWorkspaceDatasetSnapshot? = nil
    ) {
        self.expectedDataset = expectedDataset
        self.expectedSources = expectedSources
        self.sourceData = sourceData
        self.expectedIntent = expectedIntent
        self.publication = publication
    }

    var requestedSides: [TableWorkspaceSide] {
        lock.withLock { sides }
    }

    var publishedIntent: TableWorkspaceEditIntent? {
        lock.withLock { published }
    }

    var verificationFailure: String? {
        lock.withLock { failure }
    }

    func sourceUTF8Bytes(
        for source: TableWorkspaceSourceBinding,
        in dataset: TableWorkspaceDatasetSnapshot
    ) async throws -> Data {
        try lock.withLock {
            sides.append(source.side)
            guard dataset == expectedDataset else {
                failure = "dataset"
                throw WorkspaceExecutorError.verificationFailed
            }
            guard source == expectedSources[source.side] else {
                failure = "binding.\(source.side)"
                throw WorkspaceExecutorError.verificationFailed
            }
            guard let data = sourceData[source.side] else {
                throw WorkspaceExecutorError.missingSource
            }
            return data
        }
    }

    func publish(_ intent: TableWorkspaceEditIntent) async throws -> TableWorkspaceDatasetSnapshot {
        try lock.withLock {
            published = intent
            guard intent == expectedIntent else {
                failure = "intent"
                throw WorkspaceExecutorError.verificationFailed
            }
            guard let publication else { throw WorkspaceExecutorError.missingPublication }
            return publication
        }
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let throwOnCall: Int
    private var calls = 0

    init(throwOnCall: Int) {
        self.throwOnCall = throwOnCall
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    lazy var check: @Sendable () throws -> Void = { [weak self] in
        guard let self else { return }
        let shouldThrow = lock.withLock {
            calls += 1
            return calls == throwOnCall
        }
        if shouldThrow { throw CancellationError() }
    }
}

private func address(_ row: Int, _ column: Int) -> TableWorkspaceCellAddress {
    TableWorkspaceCellAddress(rowIndex: row, columnIndex: column)
}

private func makeReference(
    identitySeed: UInt8 = 1,
    revision: UInt64 = 7
) -> TableWorkspaceDatasetReference {
    TableWorkspaceDatasetReference(identity: datasetIdentity(identitySeed), revision: revision)
}

private func datasetIdentity(_ seed: UInt8) -> TableWorkspaceDatasetIdentity {
    TableWorkspaceDatasetIdentity(rawValue: seededUUID(seed))
}

private func sourceIdentity(_ seed: UInt8) -> TableWorkspaceSourceIdentity {
    TableWorkspaceSourceIdentity(rawValue: seededUUID(seed &+ 64))
}

private func tableIdentity(_ seed: UInt8) -> TableWorkspaceTableIdentity {
    TableWorkspaceTableIdentity(rawValue: seededUUID(seed &+ 128))
}

private func seededUUID(_ seed: UInt8) -> UUID {
    UUID(uuid: (seed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, seed))
}

private func requireSendable<T: Sendable>(_: T) {}
