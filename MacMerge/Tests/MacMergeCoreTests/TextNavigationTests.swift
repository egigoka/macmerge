import Foundation
import XCTest

@testable import MacMergeCore

final class TextNavigationTests: XCTestCase {
    func testLineRangesDistinguishCRLFCRAndLF() throws {
        let index = try TextLineIndex(text: "A\r\nB\nC\rD")

        XCTAssertEqual(index.lineCount, 4)
        XCTAssertEqual(index.utf16Length, 8)
        XCTAssertEqual(
            index.line(at: 1),
            TextLine(
                number: 1,
                range: NSRange(location: 0, length: 1),
                terminatorRange: NSRange(location: 1, length: 2)
            )
        )
        XCTAssertEqual(
            index.line(at: 2),
            TextLine(
                number: 2,
                range: NSRange(location: 3, length: 1),
                terminatorRange: NSRange(location: 4, length: 1)
            )
        )
        XCTAssertEqual(
            index.line(at: 3),
            TextLine(
                number: 3,
                range: NSRange(location: 5, length: 1),
                terminatorRange: NSRange(location: 6, length: 1)
            )
        )
        XCTAssertEqual(
            index.line(at: 4),
            TextLine(
                number: 4,
                range: NSRange(location: 7, length: 1),
                terminatorRange: NSRange(location: 8, length: 0)
            )
        )
        XCTAssertNil(index.line(at: 0))
        XCTAssertNil(index.line(at: 5))

        XCTAssertEqual(String(index.text[try index.stringRange(ofLine: 1)]), "A")
        XCTAssertEqual(
            String(index.text[try index.stringRange(ofLine: 1, includingTerminator: true)]),
            "A\r\n"
        )
        XCTAssertEqual(try index.location(atUTF16Offset: 1), location(1, 2, 2, 1))
        assertNavigationError(.offsetSplitsCharacter(2)) {
            try index.location(atUTF16Offset: 2)
        }
        XCTAssertEqual(try index.location(atUTF16Offset: 3), location(2, 1, 1, 3))
        XCTAssertEqual(try index.location(atUTF16Offset: 5), location(3, 1, 1, 5))
        XCTAssertEqual(try index.location(atUTF16Offset: 7), location(4, 1, 1, 7))
    }

    func testTrailingNewlineCreatesAddressableEmptyFinalLine() throws {
        let index = try TextLineIndex(text: "one\n")

        XCTAssertEqual(index.lineCount, 2)
        XCTAssertEqual(
            index.line(at: 1),
            TextLine(
                number: 1,
                range: NSRange(location: 0, length: 3),
                terminatorRange: NSRange(location: 3, length: 1)
            )
        )
        XCTAssertEqual(
            index.line(at: 2),
            TextLine(
                number: 2,
                range: NSRange(location: 4, length: 0),
                terminatorRange: NSRange(location: 4, length: 0)
            )
        )
        XCTAssertEqual(try index.location(atUTF16Offset: 3), location(1, 4, 4, 3))
        XCTAssertEqual(try index.location(atUTF16Offset: 4), location(2, 1, 1, 4))
        XCTAssertEqual(try index.goToLine(2), location(2, 1, 1, 4))

        let empty = try TextLineIndex(text: "")
        XCTAssertEqual(empty.lineCount, 1)
        XCTAssertEqual(
            empty.line(at: 1),
            TextLine(
                number: 1,
                range: NSRange(location: 0, length: 0),
                terminatorRange: NSRange(location: 0, length: 0)
            )
        )
        XCTAssertEqual(try empty.location(atUTF16Offset: 0), location(1, 1, 1, 0))
    }

    func testTextLineCompleteRangeChecksAdjacencyAndOverflow() {
        XCTAssertEqual(
            TextLine(
                number: 1,
                range: NSRange(location: 4, length: 3),
                terminatorRange: NSRange(location: 7, length: 2)
            ).completeRange,
            NSRange(location: 4, length: 5)
        )
        XCTAssertNil(
            TextLine(
                number: 1,
                range: NSRange(location: 0, length: Int.max),
                terminatorRange: NSRange(location: Int.max, length: 1)
            ).completeRange
        )
        XCTAssertNil(
            TextLine(
                number: 1,
                range: NSRange(location: 4, length: 3),
                terminatorRange: NSRange(location: 8, length: 1)
            ).completeRange
        )
        XCTAssertNil(
            TextLine(
                number: 1,
                range: NSRange(location: Int.max, length: 0),
                terminatorRange: NSRange(location: Int.max, length: 1)
            ).completeRange
        )
    }

    func testPositionAndOffsetMappingUsesGraphemeAndUTF16Columns() throws {
        let text = "A😀e\u{301}Z\r\nβ"
        let index = try TextLineIndex(text: text)
        let expected = [
            location(1, 1, 1, 0),
            location(1, 2, 2, 1),
            location(1, 3, 4, 3),
            location(1, 4, 6, 5),
            location(1, 5, 7, 6),
            location(2, 1, 1, 8),
            location(2, 2, 2, 9)
        ]

        for expectedLocation in expected {
            XCTAssertEqual(
                try index.location(at: expectedLocation.position),
                expectedLocation
            )
            XCTAssertEqual(
                try index.location(atUTF16Offset: expectedLocation.utf16Offset),
                expectedLocation
            )
            let stringIndex = try index.stringIndex(
                atUTF16Offset: expectedLocation.utf16Offset
            )
            XCTAssertEqual(index.utf16Offset(of: stringIndex), expectedLocation.utf16Offset)
        }

        XCTAssertEqual(
            try index.location(line: 1, utf16Column: 4),
            location(1, 3, 4, 3)
        )
        XCTAssertEqual(
            try index.location(line: 1, utf16Column: 6),
            location(1, 4, 6, 5)
        )
    }

    func testUTF16NavigationRejectsSurrogateCombiningAndCRLFInteriorBoundaries() throws {
        let index = try TextLineIndex(text: "A😀e\u{301}Z\r\nβ")

        for offset in [2, 4, 7] {
            assertNavigationError(.offsetSplitsCharacter(offset)) {
                try index.location(atUTF16Offset: offset)
            }
            assertNavigationError(.offsetSplitsCharacter(offset)) {
                try index.stringIndex(atUTF16Offset: offset)
            }
        }
        assertNavigationError(.offsetSplitsCharacter(2)) {
            try index.location(line: 1, utf16Column: 3)
        }
        assertNavigationError(.offsetSplitsCharacter(4)) {
            try index.location(line: 1, utf16Column: 5)
        }
        assertNavigationError(.invalidUTF16Column(line: 1, column: 0)) {
            try index.location(line: 1, utf16Column: 0)
        }
        assertNavigationError(.invalidUTF16Column(line: 1, column: 8)) {
            try index.location(line: 1, utf16Column: 8)
        }
        assertNavigationError(.invalidUTF16Offset(-1)) {
            try index.location(atUTF16Offset: -1)
        }
        assertNavigationError(.invalidUTF16Offset(10)) {
            try index.location(atUTF16Offset: 10)
        }
        assertNavigationError(.invalidUTF16Offset(Int.max)) {
            try index.location(atUTF16Offset: Int.max)
        }
    }

    func testGoToLineSupportsStrictRejectionAndDocumentClamping() throws {
        let text = "ab\nx"
        let index = try TextLineIndex(text: text)

        assertNavigationError(.invalidLine(0)) {
            try index.goToLine(0, clamping: .reject)
        }
        assertNavigationError(.invalidLine(3)) {
            try index.goToLine(3, clamping: .reject)
        }
        assertNavigationError(.invalidColumn(line: 1, column: 0)) {
            try index.goToLine(1, column: 0, clamping: .reject)
        }
        assertNavigationError(.invalidColumn(line: 1, column: 4)) {
            try index.goToLine(1, column: 4, clamping: .reject)
        }

        XCTAssertEqual(try index.goToLine(0, column: 0), location(1, 1, 1, 0))
        XCTAssertEqual(try index.goToLine(99, column: 99), location(2, 2, 2, 4))
        XCTAssertEqual(
            try TextNavigation.goToLine(-10, column: -10, in: text),
            location(1, 1, 1, 0)
        )
        XCTAssertEqual(
            try TextNavigation.goToLine(10, column: 10, in: text),
            location(2, 2, 2, 4)
        )
        assertNavigationError(.invalidLine(10)) {
            try TextNavigation.goToLine(10, in: text, clamping: .reject)
        }
    }

    func testNavigationLimitsAcceptExactBoundsAndRejectOneOver() throws {
        let exactLimits = limits(
            maximumInputUTF16Length: 4,
            maximumLineCount: 2,
            maximumLineUTF16Length: 3
        )
        let exact = try TextLineIndex(text: "😀x\n", limits: exactLimits)
        XCTAssertEqual(exact.utf16Length, 4)
        XCTAssertEqual(exact.lineCount, 2)

        assertNavigationError(.inputTooLarge(maximumUTF16Length: 4)) {
            try TextLineIndex(text: "😀xy\n", limits: exactLimits)
        }
        assertNavigationError(.tooManyLines(maximumLines: 2)) {
            try TextLineIndex(
                text: "a\nb\n",
                limits: limits(maximumLineCount: 2)
            )
        }
        assertNavigationError(.lineTooLong(line: 1, maximumUTF16Length: 2)) {
            try TextLineIndex(
                text: "😀x",
                limits: limits(maximumLineUTF16Length: 2)
            )
        }
        assertNavigationError(.invalidLimits) {
            try TextLineIndex(text: "", limits: limits(maximumLineCount: 0))
        }
    }

    func testDefinitionIndexFindsRealSwiftAndCLikeDeclarations() throws {
        let source = [
            "struct Box {}",
            "extension Box {}",
            "typealias Alias = Box",
            "func compute(_ input: Int) -> Int { input }",
            "init() {}",
            "let answer = 42",
            "var count = 0",
            "enum State { case ready, payload(Int) }",
            "#define LIMIT 8",
            "typedef unsigned long Size;",
            "const int capacity = 16;",
            "int global_count;",
            "static inline int add(int lhs, int rhs) { return lhs + rhs; }",
            "std::vector<int> make_values();"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "Box", kinds: [.type, .extensionDeclaration], lines: [1, 2])
        assertDefinitions(index, named: "Alias", kinds: [.type], lines: [3])
        assertDefinitions(index, named: "compute", kinds: [.function], lines: [4])
        assertDefinitions(index, named: "init", kinds: [.initializer], lines: [5])
        assertDefinitions(index, named: "answer", kinds: [.constant], lines: [6])
        assertDefinitions(index, named: "count", kinds: [.variable], lines: [7])
        assertDefinitions(index, named: "State", kinds: [.type], lines: [8])
        assertDefinitions(index, named: "ready", kinds: [.enumerationCase], lines: [8])
        assertDefinitions(index, named: "payload", kinds: [.enumerationCase], lines: [8])
        assertDefinitions(index, named: "LIMIT", kinds: [.macro], lines: [9])
        assertDefinitions(index, named: "Size", kinds: [.type], lines: [10])
        assertDefinitions(index, named: "capacity", kinds: [.constant], lines: [11])
        assertDefinitions(index, named: "global_count", kinds: [.variable], lines: [12])
        assertDefinitions(index, named: "add", kinds: [.function], lines: [13])
        assertDefinitions(index, named: "make_values", kinds: [.function], lines: [14])
        XCTAssertEqual(index.symbolCount, 16)
    }

    func testSwiftOnlyInputDoesNotRunCLikeDeclarationFallback() throws {
        let source = "func declared() {}\nlet value = declared()\nWidget inferred"
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "declared", kinds: [.function], lines: [1])
        assertDefinitions(index, named: "value", kinds: [.constant], lines: [2])
        XCTAssertEqual(try index.definitions(named: "inferred"), [])
    }

    func testCContinuedStringsAndCommentsDoNotLeakFakeDeclarations() throws {
        let source = [
            "const char *continued = \"func hiddenString() {} \\",
            "still string\";",
            "// func hiddenLine() {} \\",
            "int hiddenByLineContinuation(void);",
            "/* func hiddenBlock() {}",
            "int hiddenInsideBlock(void);",
            "*/",
            "int visible(void);"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "continued", kinds: [.constant], lines: [1])
        assertDefinitions(index, named: "visible", kinds: [.function], lines: [8])
        for hidden in [
            "string", "hiddenString", "hiddenLine", "hiddenByLineContinuation",
            "hiddenBlock", "hiddenInsideBlock"
        ] {
            XCTAssertEqual(try index.definitions(named: hidden), [], hidden)
        }
    }

    func testCBlockCommentsCloseAtFirstDelimiterInsteadOfNesting() throws {
        let source = "#include <stddef.h>\n/* outer /* not nested */ int visible_after_comment; */"
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "visible_after_comment", kinds: [.variable], lines: [2])
    }

    func testSwiftLineCommentsDoNotUseCBackslashLineSplicing() throws {
        let source = "// comment ending in backslash \\\nfunc visibleAfterSwiftComment() {}"
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "visibleAfterSwiftComment", kinds: [.function], lines: [2])
    }

    func testCPlusPlusRawStringsDoNotLeakDeclarations() throws {
        let source = [
            "#include <string>",
            "const char *text = R\"tag(func hiddenRaw() {} )tag\";",
            "const char *multiline = u8R\"raw(",
            "int hiddenMultiline(void);",
            ")raw\";",
            "int visibleAfterRaw(void);"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "visibleAfterRaw", kinds: [.function], lines: [6])
        for hidden in ["hiddenRaw", "hiddenMultiline"] {
            XCTAssertEqual(try index.definitions(named: hidden), [], hidden)
        }
    }

    func testPreprocessorReplacementListsDoNotYieldDefinitions() throws {
        let source = [
            "#define FACTORY() int hiddenFunction(void)",
            "#define DECLARE \\",
            "int hiddenContinuation(void);",
            "int visiblePreprocessorNeighbor(void);"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "FACTORY", kinds: [.macro], lines: [1])
        assertDefinitions(index, named: "DECLARE", kinds: [.macro], lines: [2])
        assertDefinitions(index, named: "visiblePreprocessorNeighbor", kinds: [.function], lines: [4])
        for hidden in ["hiddenFunction", "hiddenContinuation"] {
            XCTAssertEqual(try index.definitions(named: hidden), [], hidden)
        }
    }

    func testUsingNamespaceIsNotDefinition() throws {
        let index = try DefinitionSymbolIndex(text: "using namespace std;\nint visibleUsingNeighbor;")

        assertDefinitions(index, named: "visibleUsingNeighbor", kinds: [.variable], lines: [2])
        XCTAssertEqual(try index.definitions(named: "std"), [])
    }

    func testCEnumEnumeratorsAreIndexed() throws {
        let source = [
            "enum Color {",
            "Red = 1, Green = 2,",
            "Blue",
            "};"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "Color", kinds: [.type], lines: [1])
        assertDefinitions(index, named: "Red", kinds: [.enumerationCase], lines: [2])
        assertDefinitions(index, named: "Green", kinds: [.enumerationCase], lines: [2])
        assertDefinitions(index, named: "Blue", kinds: [.enumerationCase], lines: [3])
    }

    func testTypedefFunctionPointerIndexesDeclaratorName() throws {
        let index = try DefinitionSymbolIndex(text: "typedef int (*Callback)(int value);")

        assertDefinitions(index, named: "Callback", kinds: [.type], lines: [1])
        XCTAssertEqual(try index.definitions(named: "value"), [])
    }

    func testCInitFunctionIsNotSwiftInitializer() throws {
        let index = try DefinitionSymbolIndex(text: "void init(void);")

        assertDefinitions(index, named: "init", kinds: [.function], lines: [1])
    }

    func testSwiftTupleAndMultiBindingsAreIndexed() throws {
        let index = try DefinitionSymbolIndex(
            text: "let (first, second) = pair, third = 3\nvar fourth = 4, fifth = 5"
        )

        for name in ["first", "second", "third"] {
            assertDefinitions(index, named: name, kinds: [.constant], lines: [1])
        }
        for name in ["fourth", "fifth"] {
            assertDefinitions(index, named: name, kinds: [.variable], lines: [2])
        }
    }

    func testIfCasePatternIsNotEnumCaseDefinition() throws {
        let source = [
            "enum State { case ready(Int) }",
            "if case let .ready(value) = state { consume(value) }"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "ready", kinds: [.enumerationCase], lines: [1])
        for patternName in ["value", "state"] {
            XCTAssertEqual(try index.definitions(named: patternName), [], patternName)
        }
    }

    func testSwiftEnumCaseListsContinueAfterAssignments() throws {
        let index = try DefinitionSymbolIndex(
            text: "enum Code { case first = 1, second = 2, third }"
        )

        for name in ["first", "second", "third"] {
            assertDefinitions(index, named: name, kinds: [.enumerationCase], lines: [1])
        }
    }

    func testGuardCallsAreNotFunctions() throws {
        let source = "func validate() {}\nguard validate() else { return }"
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "validate", kinds: [.function], lines: [1])
    }

    func testCCommaVariableDeclaratorsAreIndexed() throws {
        let index = try DefinitionSymbolIndex(text: "int first, *second = 0, third[2];")

        for name in ["first", "second", "third"] {
            assertDefinitions(index, named: name, kinds: [.variable], lines: [1])
        }
    }

    func testSymbolLookupIncludesIdentifierContinuationDigits() throws {
        let source = "let value2 = 2"
        let index = try DefinitionSymbolIndex(text: source)
        let digitOffset = (source as NSString).range(of: "2").location

        XCTAssertEqual(try index.symbolName(atUTF16Offset: digitOffset), "value2")
        assertDefinitions(index, named: "value2", kinds: [.constant], lines: [1])
        XCTAssertEqual(
            try index.definition(forSymbolAtUTF16Offset: digitOffset)?.symbolName,
            "value2"
        )
    }

    func testSwiftUnicodeAndEmojiIdentifiersAreIndexed() throws {
        let source = "func café2() {}\nlet 🤖2 = café2()\nlet 👩🏽‍💻2 = 🤖2"
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "café2", kinds: [.function], lines: [1])
        assertDefinitions(index, named: "🤖2", kinds: [.constant], lines: [2])
        assertDefinitions(index, named: "👩🏽‍💻2", kinds: [.constant], lines: [3])
        let emojiOffset = (source as NSString).range(of: "🤖").location
        XCTAssertEqual(try index.symbolName(atUTF16Offset: emojiOffset), "🤖2")
        let sequenceOffset = (source as NSString).range(of: "👩🏽‍💻2").location
        XCTAssertEqual(try index.symbolName(atUTF16Offset: sequenceOffset), "👩🏽‍💻2")
    }

    func testContinuedQuoteUsesTrailingBackslashParity() throws {
        let source = [
            "const char *odd = \"continued \\",
            "\" const int afterOdd = 1;",
            "const char *even = \"continued \\\\",
            "\" const int hiddenByEven = 2;",
            "const int visibleAfterParity = 3;"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "odd", kinds: [.constant], lines: [1])
        assertDefinitions(index, named: "afterOdd", kinds: [.constant], lines: [2])
        assertDefinitions(index, named: "even", kinds: [.constant], lines: [3])
        assertDefinitions(index, named: "visibleAfterParity", kinds: [.constant], lines: [5])
        XCTAssertEqual(try index.definitions(named: "hiddenByEven"), [])
        XCTAssertEqual(index.symbolCount, 4)
    }

    func testSwiftRawAndTripleRawStringsDoNotLeakFakeDeclarations() throws {
        let source = [
            "let single = #\"func hiddenSingle() {}\"#",
            "let multiline = ##\"\"\"",
            "func hiddenTriple() {}",
            "\"\"\"# func hiddenNearDelimiter() {}",
            "\"\"\"##",
            "func visible() {}"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "single", kinds: [.constant], lines: [1])
        assertDefinitions(index, named: "multiline", kinds: [.constant], lines: [2])
        assertDefinitions(index, named: "visible", kinds: [.function], lines: [6])
        for hidden in ["hiddenSingle", "hiddenTriple", "hiddenNearDelimiter"] {
            XCTAssertEqual(try index.definitions(named: hidden), [], hidden)
        }
    }

    func testRawStringsIgnoreBareQuotesAndOverlongClosers() throws {
        let source = [
            "let bareQuote = #\"text \" func hiddenBareQuote() {}\"#",
            "let overlongCloser = ##\"text\"### func hiddenOverlongCloser() {}\"##",
            "func visibleAfterRawDelimiters() {}"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "bareQuote", kinds: [.constant], lines: [1])
        assertDefinitions(index, named: "overlongCloser", kinds: [.constant], lines: [2])
        assertDefinitions(index, named: "visibleAfterRawDelimiters", kinds: [.function], lines: [3])
        for hidden in ["hiddenBareQuote", "hiddenOverlongCloser"] {
            XCTAssertEqual(try index.definitions(named: hidden), [], hidden)
        }
        XCTAssertEqual(index.symbolCount, 3)
    }

    func testRegexLiteralsClassesAndExtendedDelimitersDoNotLeakFakeDeclarations() throws {
        let source = [
            "let bare = /func hiddenBare\\(\\) \\{\\}/",
            "let characterClass = /[a/b]+ func hiddenClass\\(\\)/",
            "let extended = #/[a/#]+ func hiddenExtended\\(\\)/#",
            "func visibleRegexNeighbor() {}"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "bare", kinds: [.constant], lines: [1])
        assertDefinitions(index, named: "characterClass", kinds: [.constant], lines: [2])
        assertDefinitions(index, named: "extended", kinds: [.constant], lines: [3])
        assertDefinitions(index, named: "visibleRegexNeighbor", kinds: [.function], lines: [4])
        for hidden in ["hiddenBare", "hiddenClass", "hiddenExtended"] {
            XCTAssertEqual(try index.definitions(named: hidden), [], hidden)
        }
    }

    func testRegexLiteralsIgnoreEscapedSlashesAndMismatchedExtendedClosers() throws {
        let source = [
            "let escapedSlash = /prefix \\/ func hiddenEscapedSlash\\(\\)/",
            "let underlongCloser = ##/prefix /# func hiddenUnderlongCloser()/##",
            "let overlongCloser = ##/prefix /### func hiddenOverlongCloser()/##",
            "func visibleAfterRegexDelimiters() {}"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "escapedSlash", kinds: [.constant], lines: [1])
        assertDefinitions(index, named: "underlongCloser", kinds: [.constant], lines: [2])
        assertDefinitions(index, named: "overlongCloser", kinds: [.constant], lines: [3])
        assertDefinitions(index, named: "visibleAfterRegexDelimiters", kinds: [.function], lines: [4])
        for hidden in [
            "hiddenEscapedSlash", "hiddenUnderlongCloser", "hiddenOverlongCloser"
        ] {
            XCTAssertEqual(try index.definitions(named: hidden), [], hidden)
        }
        XCTAssertEqual(index.symbolCount, 4)
    }

    func testExpressionCallsAndStdSortAreNotIndexedAsDefinitions() throws {
        let source = [
            "func declared() {}",
            "int c_declared(void);",
            "declared()",
            "consume(value)",
            "let result = declared()",
            "object.method()",
            "values.sort()",
            "std::sort(values.begin(), values.end());"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "declared", kinds: [.function], lines: [1])
        assertDefinitions(index, named: "c_declared", kinds: [.function], lines: [2])
        assertDefinitions(index, named: "result", kinds: [.constant], lines: [5])
        XCTAssertEqual(index.symbolCount, 3)
        for expressionName in ["consume", "method", "sort", "begin", "end"] {
            XCTAssertEqual(try index.definitions(named: expressionName), [], expressionName)
        }
    }

    func testCPlusPlusDeclarationsRemainWhileDeclarationShapedCallsAreRejected() throws {
        let source = [
            "Widget::Widget() {}",
            "template <typename T> Box<T>::Box() {}",
            "std::string current_name;",
            "try foo()",
            "foo + bar()",
            "foo < bar()",
            "label: baz()",
            "Foo<T>::bar()",
            "int declared(void);"
        ].joined(separator: "\n")
        let index = try DefinitionSymbolIndex(text: source)

        assertDefinitions(index, named: "Widget", kinds: [.function], lines: [1])
        assertDefinitions(index, named: "Box", kinds: [.function], lines: [2])
        assertDefinitions(index, named: "current_name", kinds: [.variable], lines: [3])
        assertDefinitions(index, named: "declared", kinds: [.function], lines: [9])
        for call in ["foo", "bar", "baz"] {
            XCTAssertEqual(try index.definitions(named: call), [], call)
        }
        XCTAssertEqual(index.symbolCount, 4)
    }

    func testDefinitionLocationsReportUnicodeGraphemeAndUTF16Columns() throws {
        let decomposedName = "cafe\u{301}"
        let source = [
            "/* 😀 e\u{301} */ func 函数() {}",
            "😀 let \(decomposedName) = 1"
        ].joined(separator: "\r\n")
        let index = try DefinitionSymbolIndex(text: source)

        let function = try XCTUnwrap(index.definitions(named: "函数").first)
        XCTAssertEqual(function.kind, .function)
        XCTAssertEqual(function.location, location(1, 16, 18, 17))
        XCTAssertEqual(function.nameRange, NSRange(location: 17, length: 2))
        XCTAssertEqual((source as NSString).substring(with: function.nameRange), "函数")

        let constant = try XCTUnwrap(index.definitions(named: decomposedName).first)
        XCTAssertEqual(constant.kind, .constant)
        XCTAssertEqual(constant.location, location(2, 7, 8, 33))
        XCTAssertEqual(constant.nameRange, NSRange(location: 33, length: 5))
        XCTAssertEqual((source as NSString).substring(with: constant.nameRange), decomposedName)
        XCTAssertEqual(try index.symbolName(atUTF16Offset: 17), "函数")
        XCTAssertEqual(try index.symbolName(atUTF16Offset: 34), decomposedName)
        XCTAssertEqual(
            try index.definition(forSymbolAtUTF16Offset: 34)?.definitions,
            [constant]
        )
    }

    func testDefinitionIndexAndLookupBounds() throws {
        let duplicateSource = "func same() {}\nfunc same(_ value: Int) {}"
        let index = try DefinitionSymbolIndex(
            text: duplicateSource,
            limits: limits(maximumLookupResults: 2)
        )

        XCTAssertEqual(
            try index.lookup("same", maximumResults: 1),
            DefinitionLookupResult(
                symbolName: "same",
                definitions: Array(try index.definitions(named: "same").prefix(1)),
                isTruncated: true
            )
        )
        XCTAssertFalse(try index.lookup("same", maximumResults: 2).isTruncated)
        assertNavigationError(.invalidLookupLimit(0)) {
            try index.lookup("same", maximumResults: 0)
        }
        assertNavigationError(.invalidLookupLimit(3)) {
            try index.lookup("same", maximumResults: 3)
        }

        XCTAssertEqual(
            try DefinitionSymbolIndex(
                text: "let value",
                limits: limits(maximumTokenCount: 2)
            ).symbolCount,
            1
        )
        assertNavigationError(.tooManyTokens(maximumTokens: 2)) {
            try DefinitionSymbolIndex(
                text: "let value = 1",
                limits: limits(maximumTokenCount: 2)
            )
        }
        assertNavigationError(.tooManySymbols(maximumSymbols: 1)) {
            try DefinitionSymbolIndex(
                text: "let first\nlet second",
                limits: limits(maximumSymbolCount: 1)
            )
        }
        XCTAssertEqual(
            try DefinitionSymbolIndex(
                text: "let ab",
                limits: limits(maximumSymbolNameUTF16Length: 2)
            ).symbolCount,
            1
        )
        assertNavigationError(.symbolNameTooLong(maximumUTF16Length: 2)) {
            try DefinitionSymbolIndex(
                text: "let abc",
                limits: limits(maximumSymbolNameUTF16Length: 2)
            )
        }
        assertNavigationError(.symbolNameTooLong(maximumUTF16Length: 2)) {
            try DefinitionSymbolIndex(
                text: "",
                limits: limits(maximumSymbolNameUTF16Length: 2)
            ).lookup("abc")
        }
    }

    private func location(
        _ line: Int,
        _ column: Int,
        _ utf16Column: Int,
        _ utf16Offset: Int
    ) -> TextLocation {
        TextLocation(
            position: TextPosition(line: line, column: column),
            utf16Column: utf16Column,
            utf16Offset: utf16Offset
        )
    }

    private func assertDefinitions(
        _ index: DefinitionSymbolIndex,
        named name: String,
        kinds: [DefinitionSymbolKind],
        lines: [Int],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let definitions = try index.definitions(named: name)
            XCTAssertEqual(definitions.map(\.kind), kinds, name, file: file, line: line)
            XCTAssertEqual(definitions.map(\.location.line), lines, name, file: file, line: line)
        } catch {
            XCTFail("Lookup for \(name) failed: \(error)", file: file, line: line)
        }
    }

    private func assertNavigationError<T>(
        _ expected: TextNavigationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> T
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? TextNavigationError, expected, file: file, line: line)
        }
    }

    private func limits(
        maximumInputUTF16Length: Int = 100_000,
        maximumLineCount: Int = 100_000,
        maximumLineUTF16Length: Int = 100_000,
        maximumTokenCount: Int = 100_000,
        maximumSymbolCount: Int = 100_000,
        maximumSymbolNameUTF16Length: Int = 256,
        maximumLookupResults: Int = 256
    ) -> TextNavigationLimits {
        TextNavigationLimits(
            maximumInputUTF16Length: maximumInputUTF16Length,
            maximumLineCount: maximumLineCount,
            maximumLineUTF16Length: maximumLineUTF16Length,
            maximumTokenCount: maximumTokenCount,
            maximumSymbolCount: maximumSymbolCount,
            maximumSymbolNameUTF16Length: maximumSymbolNameUTF16Length,
            maximumLookupResults: maximumLookupResults
        )
    }
}
