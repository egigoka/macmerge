import Foundation
import XCTest

@testable import MacMergeCore

final class SyntaxHighlightingTests: XCTestCase {
    func testSwiftKindsUseUTF16Ranges() throws {
        let text = "let 😀 = \"é\"; // note\nreturn 42"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(text, language: .swift),
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 3)),
                SyntaxToken(kind: .string, range: NSRange(location: 9, length: 3)),
                SyntaxToken(kind: .comment, range: NSRange(location: 14, length: 7)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 22, length: 6)),
                SyntaxToken(kind: .number, range: NSRange(location: 29, length: 2))
            ]
        )
    }

    func testCLikeKindsAndAdjacentQuotedStringsStaySingleLine() throws {
        let text = "const char *s = \"left\" \"right\";\n\"third\"\nreturn 7; // note"
        let tokens = try SyntaxHighlighter.highlight(text, language: .cLike)

        XCTAssertEqual(
            tokens,
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 5)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 6, length: 4)),
                SyntaxToken(kind: .string, range: NSRange(location: 16, length: 6)),
                SyntaxToken(kind: .string, range: NSRange(location: 23, length: 7)),
                SyntaxToken(kind: .string, range: NSRange(location: 32, length: 7)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 40, length: 6)),
                SyntaxToken(kind: .number, range: NSRange(location: 47, length: 1)),
                SyntaxToken(kind: .comment, range: NSRange(location: 50, length: 7))
            ]
        )
        let source = text as NSString
        for token in tokens where token.kind == .string {
            XCTAssertFalse(source.substring(with: token.range).contains("\n"))
        }
    }

    func testJSONKindsUseUTF16Ranges() throws {
        let text = "{\"😀\": -12.5e+2, \"ok\": true, \"n\": null}"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(text, language: .json),
            [
                SyntaxToken(kind: .string, range: NSRange(location: 1, length: 4)),
                SyntaxToken(kind: .number, range: NSRange(location: 7, length: 8)),
                SyntaxToken(kind: .string, range: NSRange(location: 17, length: 4)),
                SyntaxToken(kind: .literal, range: NSRange(location: 23, length: 4)),
                SyntaxToken(kind: .string, range: NSRange(location: 29, length: 3)),
                SyntaxToken(kind: .literal, range: NSRange(location: 34, length: 4))
            ]
        )
    }

    func testMarkdownKindsUseUTF16Ranges() throws {
        let text = "# 😀\n**bold** `code` [link](url)"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(text, language: .markdown),
            [
                SyntaxToken(kind: .heading, range: NSRange(location: 0, length: 4)),
                SyntaxToken(kind: .emphasis, range: NSRange(location: 5, length: 8)),
                SyntaxToken(kind: .code, range: NSRange(location: 14, length: 6)),
                SyntaxToken(kind: .link, range: NSRange(location: 21, length: 11))
            ]
        )
    }

    func testMalformedMarkdownBracketsPreserveNestedEmphasis() throws {
        let cases = [
            ("[*kept*](unterminated", NSRange(location: 1, length: 6)),
            ("[broken *also*", NSRange(location: 8, length: 6))
        ]

        for (text, range) in cases {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(text, language: .markdown),
                [SyntaxToken(kind: .emphasis, range: range)]
            )
        }
    }

    func testUnicodeSwiftIdentifiersContainKeywordsAndNumbersWithoutInnerTokens() throws {
        let text = "let caféreturn42 = 0\nlet 🤖if7 = 1\nlet 变量while9 = 2\nreturn 3"
        let source = text as NSString
        let tokens = try SyntaxHighlighter.highlight(text, language: .swift)

        XCTAssertEqual(
            tokens.map { "\($0.kind.rawValue):\(source.substring(with: $0.range))" },
            [
                "keyword:let",
                "number:0",
                "keyword:let",
                "number:1",
                "keyword:let",
                "number:2",
                "keyword:return",
                "number:3"
            ]
        )
    }

    func testExactInputTokenAndWorkBoundsAreAccepted() throws {
        let text = "let 1"
        let exactLimits = SyntaxHighlightingLimits(
            maximumInputUTF8Bytes: 5,
            maximumTokenCount: 2,
            maximumWorkUnits: 6
        )

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(text, language: .swift, limits: exactLimits),
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 3)),
                SyntaxToken(kind: .number, range: NSRange(location: 4, length: 1))
            ]
        )

        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                text,
                language: .swift,
                limits: SyntaxHighlightingLimits(
                    maximumInputUTF8Bytes: 4,
                    maximumTokenCount: 2,
                    maximumWorkUnits: 6
                )
            )
        ) { error in
            XCTAssertEqual(error as? SyntaxHighlightingError, .inputTooLarge(maximumUTF8Bytes: 4))
        }

        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                text,
                language: .swift,
                limits: SyntaxHighlightingLimits(
                    maximumInputUTF8Bytes: 5,
                    maximumTokenCount: 1,
                    maximumWorkUnits: 6
                )
            )
        ) { error in
            XCTAssertEqual(error as? SyntaxHighlightingError, .tooManyTokens(maximumTokens: 1))
        }

        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                text,
                language: .swift,
                limits: SyntaxHighlightingLimits(
                    maximumInputUTF8Bytes: 5,
                    maximumTokenCount: 2,
                    maximumWorkUnits: 5
                )
            )
        ) { error in
            XCTAssertEqual(error as? SyntaxHighlightingError, .workLimitExceeded(maximumWorkUnits: 5))
        }
    }

    func testTokensAreOrderedNonOverlappingAndWithinUTF16Input() throws {
        let samples: [(SyntaxHighlightingLanguage, String)] = [
            (.swift, "let 😀 = \"value\" // comment\nreturn 1"),
            (.cLike, "const char *value = \"x\"; // comment"),
            (.json, "{\"value\": true, \"count\": 1}"),
            (.markdown, "# Heading\n**bold** `code` [link](url)")
        ]

        for (language, text) in samples {
            let tokens = try SyntaxHighlighter.highlight(text, language: language)
            let inputLength = (text as NSString).length

            for token in tokens {
                XCTAssertGreaterThan(token.range.length, 0)
                XCTAssertGreaterThanOrEqual(token.range.location, 0)
                XCTAssertLessThanOrEqual(NSMaxRange(token.range), inputLength)
            }
            for (previous, current) in zip(tokens, tokens.dropFirst()) {
                XCTAssertLessThanOrEqual(NSMaxRange(previous.range), current.range.location)
            }
        }
    }

    func testCancellationIsObservedBeforeScanning() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SyntaxHighlighter.highlight("let value = 1", language: .swift)
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
