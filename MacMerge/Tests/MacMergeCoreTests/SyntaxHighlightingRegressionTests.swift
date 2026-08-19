import Foundation
import XCTest

@testable import MacMergeCore

private final class SyntaxWorkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    func record(_ value: Int) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}

private enum SyntaxObservedEvent: Equatable {
    case checkpoint(SyntaxHighlighter.Checkpoint)
    case work(Int)
}

private final class SyntaxEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [SyntaxObservedEvent] = []

    func record(_ event: SyntaxObservedEvent) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }

    var events: [SyntaxObservedEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }
}

final class SyntaxHighlightingTestsRegressions: XCTestCase {
    func testKeywordSetsCoverSupportedSwift6AndC23Cxx23Forms() throws {
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(
                "in lazy Self borrowing sending yield",
                language: .swift
            ),
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 2)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 3, length: 4)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 8, length: 4)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 13, length: 9)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 23, length: 7)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 31, length: 5))
            ]
        )
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(
                "_BitInt constexpr co_await requires char8_t",
                language: .cLike
            ),
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 7)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 8, length: 9)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 18, length: 8)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 27, length: 8)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 36, length: 7))
            ]
        )
    }

    func testSwiftMacroRolesAndAssignmentAreKeywords() throws {
        let source = "@attached(member) macro M = X\n@freestanding(expression) assignment throw"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:attached",
                "keyword:macro",
                "keyword:freestanding",
                "keyword:assignment",
                "keyword:throw"
            ]
        )
    }

    func testSwiftSelfDollarUnicodeAndBacktickedIdentifiersPreserveBoundaries() throws {
        let source = "🤖if7 self Self $0 classπ π123 `return` return"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift),
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 6, length: 4)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 11, length: 4)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 40, length: 6))
            ]
        )
    }

    func testSwiftSingleLineRawStringStopsAtNewline() throws {
        let rawOneLine = "#\"raw\nlet value = 1"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(rawOneLine, language: .swift),
            [
                SyntaxToken(kind: .string, range: NSRange(location: 0, length: 5)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 6, length: 3)),
                SyntaxToken(kind: .number, range: NSRange(location: 18, length: 1))
            ]
        )
    }

    func testSwiftNestedInterpolationPreservesFollowingToken() throws {
        let interpolation = #"let value = "x \(make(")")) y"; return"#

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(interpolation, language: .swift),
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 3)),
                SyntaxToken(kind: .string, range: NSRange(location: 12, length: 18)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 32, length: 6))
            ]
        )
    }

    func testSwiftDeepInterpolationHandlesNestedStringsRegexAndComments() throws {
        let source = ###"let value = "outer \(make("middle \(wrap(#"inner \#(call(")"))"#))", #/a//b/# /* ) */)) tail"; return"###
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:let",
                "string:"
                    + text.substring(
                        with: NSRange(location: 12, length: text.length - 20)
                    ),
                "keyword:return"
            ]
        )
    }

    func testSwiftRegexLiteralWinsBeforeLineComment() throws {
        let source = #"let regex = #/https?://example\.com/path/#; return"#
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:let",
                "string:#/https?://example\\.com/path/#",
                "keyword:return"
            ]
        )
    }

    func testSwiftRegexSupportsNestedClassesAndExpressionIntroducers() throws {
        let source = "if /[[a]/]/ { return }\nlet value = try /x//.firstMatch(in: text)"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:if",
                "string:/[[a]/]/",
                "keyword:return",
                "keyword:let",
                "keyword:try",
                "string:/x/",
                "keyword:in"
            ]
        )
    }

    func testSwiftBareRegexEscapeStopsBeforeLineBreak() throws {
        let cases = ["/bad\\\nreturn /", "/bad\\\rreturn /", "/bad\\\r\nreturn /"]

        for source in cases {
            let returnLocation = (source as NSString).range(of: "return").location
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .swift),
                [
                    SyntaxToken(
                        kind: .keyword,
                        range: NSRange(location: returnLocation, length: 6)
                    )
                ],
                source.debugDescription
            )
        }
    }

    func testSwiftRegexInterpolationAndKeywordContextPreserveDelimiters() throws {
        let source = ##"return /x\(value / 2)y/; let raw = #/a\#("/")b/#"##
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:return",
                #"string:/x\(value / 2)y/"#,
                "keyword:let",
                ##"string:#/a\#("/")b/#"##
            ]
        )
    }

    func testSwiftRawRegexEscapesSkipScalarForEveryHashCount() throws {
        let sources = ["#/\\[/#", "##/\\[/##", "###/\\[/###"]

        for source in sources {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .swift),
                [
                    SyntaxToken(
                        kind: .string,
                        range: NSRange(location: 0, length: (source as NSString).length)
                    )
                ],
                source
            )
        }
    }

    func testSwiftRawRegexDistinctHashFailuresFitProportionalBudget() throws {
        let source = (1...256).map { String(repeating: "#", count: $0) + "/x " }.joined()

        XCTAssertTrue(
            try SyntaxHighlighter.highlight(
                source,
                language: .swift,
                limits: SyntaxHighlightingLimits(maximumWorkUnits: source.utf16.count * 4)
            ).isEmpty
        )
    }

    func testSwiftFailedRawRegexClassDoesNotSuppressLaterLiteral() throws {
        let cases = ["#/[ #/x/#", "#/[ #/x/# ]", "#/x\\#( #/ok/# );"]
        let expectedLocations = [4, 4, 7]
        let expectedLengths = [5, 5, 6]

        for ((source, location), length) in zip(zip(cases, expectedLocations), expectedLengths) {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .swift),
                [SyntaxToken(kind: .string, range: NSRange(location: location, length: length))],
                source
            )
        }
    }

    func testSwiftStatefulRawRegexFailuresRemainWorkBounded() throws {
        let hashes = String(repeating: "#", count: 100)
        let source =
            (1...100).map { String(repeating: "#", count: $0) + "/[ " }.joined()
            + "/" + hashes

        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                source,
                language: .swift,
                limits: SyntaxHighlightingLimits(maximumWorkUnits: source.utf16.count * 4)
            )
        ) { error in
            XCTAssertEqual(
                error as? SyntaxHighlightingError,
                .workLimitExceeded(maximumWorkUnits: source.utf16.count * 4)
            )
        }
    }

    func testSwiftRawRegexDelimiterComparisonAndContextWhitespaceConsumeWork() throws {
        let hashes = String(repeating: "#", count: 1_000)
        let rawRegex = hashes + "/x/" + hashes
        let separatedRegex = "return" + String(repeating: " ", count: 1_000) + "/x/"

        for source in [rawRegex, separatedRegex] {
            XCTAssertThrowsError(
                try SyntaxHighlighter.highlight(
                    source,
                    language: .swift,
                    limits: SyntaxHighlightingLimits(maximumWorkUnits: 1_500)
                )
            ) { error in
                XCTAssertEqual(
                    error as? SyntaxHighlightingError,
                    .workLimitExceeded(maximumWorkUnits: 1_500)
                )
            }
        }
    }

    func testSwiftInterpolationRegexQuotesDoNotCloseOuterString() throws {
        let source = #"let value = "x \(/"quoted"/) y"; return"#
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:let",
                #"string:"x \(/"quoted"/) y""#,
                "keyword:return"
            ]
        )
    }

    func testUnterminatedSingleLineInterpolationStopsAtNewline() throws {
        let source = "let value = \"x \\(call(\nreturn 1"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            ["keyword:let", "string:\"x \\(call(", "keyword:return", "number:1"]
        )

        let cachedContext = "let value = \"x \\(x = /[ /* comment */\n/ok/"
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(cachedContext, language: .swift),
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 3)),
                SyntaxToken(kind: .string, range: NSRange(location: 12, length: 25)),
                SyntaxToken(kind: .string, range: NSRange(location: 38, length: 4))
            ]
        )
    }

    func testSwiftIdentifierHeadsIncludeNonXIDGrammarRanges() throws {
        let source = "\u{00AD}return \u{200B}class \u{203F}while let"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift),
            [SyntaxToken(kind: .keyword, range: NSRange(location: 22, length: 3))]
        )
    }

    func testCLineCommentSpliceConsumesContinuationLine() throws {
        let comment = "😀 // comment\\\r\nreturn true;\nint value;"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(comment, language: .cLike),
            [
                SyntaxToken(kind: .comment, range: NSRange(location: 3, length: 25)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 29, length: 3))
            ]
        )
    }

    func testCSplicedCommentOpenersAndDecimalEdgeForms() throws {
        let source = "int x; /\\\n/ line\nreturn .5; /\\\r\n* block */ true 1.;"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:int",
                "comment:/\\\n/ line",
                "keyword:return",
                "number:.5",
                "comment:/\\\r\n* block */",
                "literal:true",
                "number:1."
            ]
        )
    }

    func testCxx23DecimalFormsAndStandardSuffixes() throws {
        let source = ".5 1. 1.e3 42z 42UZ 1.0f16 1e2BF16 7LL 8zu 1.0f16x"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike).map {
                text.substring(with: $0.range)
            },
            [".5", "1.", "1.e3", "42z", "42UZ", "1.0f16", "1e2BF16", "7LL", "8zu"]
        )
    }

    func testC23BitPreciseSuffixCombinationsAndCxx23KeywordBoundary() throws {
        let source = "1wb 2WB 3uwb 4UWB 5wbu 6WBU contract_assert"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "number:1wb", "number:2WB", "number:3uwb", "number:4UWB",
                "number:5wbu", "number:6WBU"
            ]
        )
    }

    func testCLikePhaseTwoSplicesIdentifiersNumbersAndWhitespaceExtension() throws {
        let source = "ret\\\nurn 1\\\n23 0x\\\nFF ret\\ \nurn \"x\\ \ny\" 1'\\\n000 1\\\n'000"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:ret\\\nurn",
                "number:1\\\n23",
                "number:0x\\\nFF",
                "keyword:ret\\ \nurn",
                "string:\"x\\ \ny\"",
                "number:1'\\\n000",
                "number:1\\\n'000"
            ]
        )
    }

    func testCLikeInvalidPreprocessingNumberTailCrossesPhaseTwoSplices() throws {
        let source = "1foo\\\nreturn int"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike),
            [SyntaxToken(kind: .keyword, range: NSRange(location: 13, length: 3))]
        )
    }

    func testCMalformedPreprocessingNumberConsumesPhaseTwoSplicedIdentifierTail() throws {
        let cases = [
            "1x\\\nreturn",
            "1'return",
            "1'\\\nreturn",
            "1\\\n'return",
            "1'\\ \r\nreturn",
            "1e+return",
            "1E-return",
            "0x1p+return",
            "0X1P-return",
            "1e\\\n+\\\nreturn",
            "0x1p\\ \r\n+\\\r\nreturn"
        ]

        for source in cases {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .cLike),
                [],
                source.debugDescription
            )
        }
    }

    func testCNumberSuffixDoesNotOwnTrailingSplice() throws {
        let source = "1u\\\n; 1\\\nu;"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike),
            [
                SyntaxToken(kind: .number, range: NSRange(location: 0, length: 2)),
                SyntaxToken(kind: .number, range: NSRange(location: 6, length: 4))
            ]
        )
    }

    func testCPhaseTwoSpliceStartsLeadingDotDecimalAndJoinsDigitSeparators() throws {
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(".\\\n5 1'\\\n000", language: .cLike),
            [
                SyntaxToken(kind: .number, range: NSRange(location: 0, length: 4)),
                SyntaxToken(kind: .number, range: NSRange(location: 5, length: 7))
            ]
        )
    }

    func testCSpliceWhitespaceProbeConsumesWorkBudget() throws {
        let whitespace = String(repeating: " ", count: 1_000)
        let source = "/" + "\\" + whitespace + "x"

        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                source,
                language: .cLike,
                limits: SyntaxHighlightingLimits(maximumWorkUnits: 1_500)
            )
        ) { error in
            XCTAssertEqual(
                error as? SyntaxHighlightingError,
                .workLimitExceeded(maximumWorkUnits: 1_500)
            )
        }
    }

    func testCLikeHexMemberDotRemainsOneInvalidPreprocessingNumber() throws {
        let source = "0x1.member 0x1.toString 0x1.2p3"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike).map(\.range),
            [NSRange(location: 24, length: 7)]
        )
    }

    func testMalformedRadixAndDottedPreprocessingNumbersStayUnstyled() throws {
        for source in [
            "0x", "0xp1", "0x1.2", "0x1\\\np", "0b", "0o7", "08", "078", "0'8", "1.2.3"
        ] {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .cLike),
                [],
                source
            )
        }

        for source in [
            "0x", "0xp1", "0x1.2", "0x.8p1", "0b", "0b2", "0b102",
            "0o", "0o8", "0o78", "0xG", "0x1G", "0x1p1G", "1e", "1e+", "1e_2",
            "1foo", "1e2bar", "1_", "0x1__2"
        ] {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .swift),
                [],
                source
            )
        }

        let validC = "0x.8p1 08.0 09e1"
        let text = validC as NSString
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(validC, language: .cLike).map {
                text.substring(with: $0.range)
            },
            ["0x.8p1", "08.0", "09e1"]
        )
    }

    func testAdjacentQuotesStaySeparateAndSwiftTripleQuotesRequireNewline() throws {
        let cSource = "😀 \"left\" \"right\"\nint"
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(cSource, language: .cLike),
            [
                SyntaxToken(kind: .string, range: NSRange(location: 3, length: 6)),
                SyntaxToken(kind: .string, range: NSRange(location: 10, length: 7)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 18, length: 3))
            ]
        )

        let swiftSource = "\"\"\"return\"\"\"\nlet"
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(swiftSource, language: .swift),
            [
                SyntaxToken(kind: .string, range: NSRange(location: 0, length: 2)),
                SyntaxToken(kind: .string, range: NSRange(location: 2, length: 8)),
                SyntaxToken(kind: .string, range: NSRange(location: 10, length: 2)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 13, length: 3))
            ]
        )
    }

    func testCxxStringPrefixesAndRawStringsAreSingleUTF16Tokens() throws {
        let source = "😀 u8\"x\" L'x' R\"tag(return \"quoted\")tag\" u8R\"(raw\ntext)\" return"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike),
            [
                SyntaxToken(kind: .string, range: NSRange(location: 3, length: 5)),
                SyntaxToken(kind: .string, range: NSRange(location: 9, length: 4)),
                SyntaxToken(kind: .string, range: NSRange(location: 14, length: 26)),
                SyntaxToken(kind: .string, range: NSRange(location: 41, length: 15)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 57, length: 6))
            ]
        )
    }

    func testCxxStringAndRawPrefixesHonorPhaseTwoSplices() throws {
        let source = "u\\\n8\"x\" u8\\\n\"y\" R\\\n\"(raw)\" u8\\\nR\"(wide)\" return"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "string:u\\\n8\"x\"",
                "string:u8\\\n\"y\"",
                "string:R\\\n\"(raw)\"",
                "string:u8\\\nR\"(wide)\"",
                "keyword:return"
            ]
        )

        XCTAssertEqual(
            try SyntaxHighlighter.highlight("\\\nu8\"x\"", language: .cLike),
            [SyntaxToken(kind: .string, range: NSRange(location: 2, length: 5))]
        )
    }

    func testSwiftRadixAndHexFloatingLiteralsAreSingleTokens() throws {
        let source = "0xFF 0b1010 0o755 0x1.8p1"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                text.substring(with: $0.range)
            },
            ["0xFF", "0b1010", "0o755", "0x1.8p1"]
        )
    }

    func testSwiftBareRegexRejectsUnescapedLeadingHorizontalWhitespace() throws {
        for source in ["return / foo/", "return /\tfoo/", "return /foo /"] {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .swift),
                [SyntaxToken(kind: .keyword, range: NSRange(location: 0, length: 6))],
                source.debugDescription
            )
        }

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(#"return /foo\ /"#, language: .swift).map(\.kind),
            [.keyword, .string]
        )
    }

    func testSwiftRegexKeywordContextUsesSwiftIdentifierBoundaries() throws {
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("\u{200B}return /x/", language: .swift),
            []
        )
    }

    func testCSplicedBlockCommentTerminatorPreservesFollowingCode() throws {
        let source = "/* comment *\\\n\\\n/ int value;"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            ["comment:/* comment *\\\n\\\n/", "keyword:int"]
        )
    }

    func testRawStringMatrixAndCxxDelimiterGrammar() throws {
        let swiftCases = [
            #""x""#,
            ##"#"x " y"#"##,
            ###"##"x " y"##"###,
            "#\"\"\"\nx\n\"\"\"#",
            ##"#"\#(1)"#"##
        ]
        for source in swiftCases {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .swift),
                [
                    SyntaxToken(
                        kind: .string,
                        range: NSRange(location: 0, length: (source as NSString).length)
                    )
                ],
                source
            )
        }

        let cxxCases = [
            "R\"(x)\"", "u8R\"(x)\"", "uR\"d(x)d\"", "UR\"d(x)d\"", "LR\"d(x)d\"",
            "R\"1234567890123456(x)1234567890123456\""
        ]
        for source in cxxCases {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .cLike),
                [
                    SyntaxToken(
                        kind: .string,
                        range: NSRange(location: 0, length: (source as NSString).length)
                    )
                ],
                source
            )
        }

        let invalid = [
            "R\"é(x)é\"", "R\"a b(x)a b\"", "R\"a\\b(x)a\\b\"",
            "R\"12345678901234567(x)12345678901234567\"", "xR\"(x)\""
        ]
        for source in invalid {
            XCTAssertFalse(
                try SyntaxHighlighter.highlight(source, language: .cLike).contains {
                    $0.kind == .string && $0.range.location == 0
                },
                source
            )
        }
    }

    func testCxxDigitSeparatorsRemainInsideNumbers() throws {
        let source = "😀 0xDEAD'BEEF 0b1010'0110 07'55 1'000 return"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .cLike),
            [
                SyntaxToken(kind: .number, range: NSRange(location: 3, length: 11)),
                SyntaxToken(kind: .number, range: NSRange(location: 15, length: 11)),
                SyntaxToken(kind: .number, range: NSRange(location: 27, length: 5)),
                SyntaxToken(kind: .number, range: NSRange(location: 33, length: 5)),
                SyntaxToken(kind: .keyword, range: NSRange(location: 39, length: 6))
            ]
        )
    }

    func testJSONEscapedNewlineDoesNotConsumeLaterLiterals() throws {
        let source = "😀 \"x\\\ntrue\nnull"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .json),
            [
                SyntaxToken(kind: .literal, range: NSRange(location: 7, length: 4)),
                SyntaxToken(kind: .literal, range: NSRange(location: 12, length: 4))
            ]
        )
    }

    func testJSONRawControlEndsStringAndLiteralsNeedBothBoundaries() throws {
        let source = "\"bad\u{0001}\\\" still\" true false truex atrue _null null étrue trueé"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .json).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "literal:true",
                "literal:false",
                "literal:null"
            ]
        )
    }

    func testJSONMalformedLeadingZeroConsumesFullNumberTail() throws {
        let source = "01.2 00e+3 true"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .json),
            [SyntaxToken(kind: .literal, range: NSRange(location: 11, length: 4))]
        )
    }

    func testJSONLeadingZerosAndMalformedTokenBoundariesStayUnstyled() throws {
        let source = "0 10 -2 01 -01 1x x-1 --1 +1 .1 1. 1e 00e+true 1.true true xtrue truex true1 null"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .json).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            ["number:0", "number:10", "number:-2", "literal:true", "literal:null"]
        )
    }

    func testJSONStrictEscapesAndMalformedExponentRecovery() throws {
        let source = #""ok\"\\\/\b\f\n\r\t\u00E9" "bad\q" "short\u123" 1e+ true 2E- false"#
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .json).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                #"string:"ok\"\\\/\b\f\n\r\t\u00E9""#,
                "literal:true",
                "literal:false"
            ]
        )
    }

    func testMarkdownCompletedLinkDiscardsLabelLocalDelimiterRuns() throws {
        let source = "[x*y](u) a*b*"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            ["link:[x*y](u)", "emphasis:*b*"]
        )
    }

    func testMarkdownCompletedCodeSpanDiscardsCoveredPendingRuns() throws {
        let source = "`` `a``b` ``c``"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                text.substring(with: $0.range)
            },
            ["`` `a``", "``c``"]
        )
    }

    func testMarkdownCompletedContainersReclaimCoveredMetadata() throws {
        let fixtures: [(String, [String])] = [
            ("[x *a*](u) *b*", ["[x *a*](u)", "*b*"]),
            ("**x *a* x** *b*", ["**x *a* x**", "*b*"]),
            ("`` `a` `` `b`", ["`` `a` ``", "`b`"])
        ]

        for (source, expected) in fixtures {
            let text = source as NSString
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(
                    source,
                    language: .markdown,
                    limits: SyntaxHighlightingLimits(maximumMetadataEntries: 2)
                ).map { text.substring(with: $0.range) },
                expected,
                source
            )
        }
    }

    func testMarkdownNestedDestinationWhitespaceCannotTruncateLink() throws {
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("[x](a( )) *ok*", language: .markdown),
            [SyntaxToken(kind: .emphasis, range: NSRange(location: 10, length: 4))]
        )
    }

    func testMarkdownNestedLinksRecoveryFenceInfoAndCodePrecedence() throws {
        let fenced = "```swift\nlet x = `code`\n```\n# heading"
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(fenced, language: .markdown),
            [
                SyntaxToken(kind: .code, range: NSRange(location: 0, length: 27)),
                SyntaxToken(kind: .heading, range: NSRange(location: 28, length: 9))
            ]
        )
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("```swift`bad\n# heading", language: .markdown),
            [SyntaxToken(kind: .heading, range: NSRange(location: 13, length: 9))]
        )

        let link = "[outer [inner]](url \"title (ok)\")"
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(link, language: .markdown),
            [SyntaxToken(kind: .link, range: NSRange(location: 0, length: 33))]
        )
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("[**bold**] and *after*", language: .markdown),
            [
                SyntaxToken(kind: .emphasis, range: NSRange(location: 1, length: 8)),
                SyntaxToken(kind: .emphasis, range: NSRange(location: 15, length: 7))
            ]
        )

        let emphasis = "*before `*` after*"
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(emphasis, language: .markdown),
            [SyntaxToken(kind: .emphasis, range: NSRange(location: 0, length: 18))]
        )

        XCTAssertEqual(
            try SyntaxHighlighter.highlight("[x](don't) *after*", language: .markdown),
            [
                SyntaxToken(kind: .link, range: NSRange(location: 0, length: 10)),
                SyntaxToken(kind: .emphasis, range: NSRange(location: 11, length: 7))
            ]
        )
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("`open\n\n# heading\n`close`", language: .markdown),
            [
                SyntaxToken(kind: .heading, range: NSRange(location: 7, length: 9)),
                SyntaxToken(kind: .code, range: NSRange(location: 17, length: 7))
            ]
        )
    }

    func testMarkdownSoftBreaksDestinationGrammarAndNestedLinkRejection() throws {
        let source = """
            [multi
            line](  <url>
             "title"
             )
            [outer [inner](one)](two)
            [bad](url title)
            *soft
            break*
            """
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "link:[multi\nline](  <url>\n \"title\"\n )",
                "link:[inner](one)",
                "emphasis:*soft\nbreak*"
            ]
        )
    }

    func testMarkdownImageMayContainLinkButLinkMayNotContainLink() throws {
        let source = "![outer [inner](one)](image) [outer [inner](one)](two)"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "link:![outer [inner](one)](image)",
                "link:[inner](one)"
            ]
        )
    }

    func testMarkdownIntrawordUnderscoresAndBackslashesBeforeCodeDelimiters() throws {
        let source = "foo_bar_baz é_é_é é_!_é a*$x* _yes_ foo__bar __strong__ \\`code\\`"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "emphasis:_yes_",
                "emphasis:__strong__"
            ]
        )
    }

    func testMarkdownPartialRunsIntrawordClosingAndFailedTitleRollback() throws {
        let source = "***foo** **bar*** *a**b* _foo_bar_ [x](url \"bad) *after*"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "emphasis:**foo**",
                "emphasis:**bar**",
                "emphasis:*a**b*",
                "emphasis:_foo_bar_",
                "emphasis:*after*"
            ]
        )
    }

    func testMarkdownEmphasisCannotCrossActiveLinkBracket() throws {
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("*[x*](url)", language: .markdown),
            [SyntaxToken(kind: .link, range: NSRange(location: 1, length: 9))]
        )
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("*![x*](url)", language: .markdown),
            [SyntaxToken(kind: .link, range: NSRange(location: 1, length: 10))]
        )
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("*[x*]", language: .markdown),
            [SyntaxToken(kind: .emphasis, range: NSRange(location: 0, length: 4))]
        )
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("*![x*]", language: .markdown),
            [SyntaxToken(kind: .emphasis, range: NSRange(location: 0, length: 5))]
        )
    }

    func testMarkdownMetadataCapIsIndependentOfTokenCap() throws {
        for (source, kind) in [
            ("*x*", SyntaxTokenKind.emphasis),
            ("`unterminated [y](z)", SyntaxTokenKind.link)
        ] {
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(
                    source,
                    language: .markdown,
                    limits: SyntaxHighlightingLimits(maximumMetadataEntries: 1)
                ).map(\.kind),
                [kind]
            )
        }

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(
                "[bad](url title) [ok](url)",
                language: .markdown,
                limits: SyntaxHighlightingLimits(maximumMetadataEntries: 1)
            ).map(\.kind),
            [.link]
        )
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(
                "[bad](foo(bar title) [one](1) [two](2)",
                language: .markdown,
                limits: SyntaxHighlightingLimits(maximumMetadataEntries: 2)
            ).map(\.kind),
            [.link, .link]
        )

        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                "[[[",
                language: .markdown,
                limits: SyntaxHighlightingLimits(maximumMetadataEntries: 2)
            )
        ) { error in
            XCTAssertEqual(
                error as? SyntaxHighlightingError,
                .metadataLimitExceeded(maximumEntries: 2)
            )
        }
    }

    func testMarkdownReclaimsFailedDelimiterMetadataAtBlankLines() throws {
        let source = "[\n\n[\n\n*\n\n**kept**"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(
                source,
                language: .markdown,
                limits: SyntaxHighlightingLimits(maximumMetadataEntries: 1)
            ),
            [SyntaxToken(kind: .emphasis, range: NSRange(location: 9, length: 8))]
        )
    }

    func testMarkdownBlankLineBreaksMultilineDelimiterState() throws {
        let source = "[broken\n\nlabel](url) *broken\n\nafter* `open\n\nclose` **kept**"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown),
            [SyntaxToken(kind: .emphasis, range: NSRange(location: 51, length: 8))]
        )
    }

    func testMarkdownMalformedDestinationCannotLeakStateAcrossBlankLine() throws {
        let source = "[bad](url\n\n# heading\n) *open\n\nclose* **kept**"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "heading:# heading",
                "emphasis:**kept**"
            ]
        )
    }

    func testMarkdownFailedDestinationRollbackAndEscapedLineState() throws {
        let source = "[x](url \"bad # not-heading *kept*\\\n```\ncode\n```"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            ["emphasis:*kept*", "code:```\ncode\n```"]
        )
    }

    func testMarkdownDestinationEscapesAndTitlesFollowGrammar() throws {
        let source = "\\![x](url) [space](foo\\ bar) [nested](url (a(b))) [ok](url (title))"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "link:[x](url)",
                "link:[ok](url (title))"
            ]
        )
    }

    func testMarkdownDestinationEscapeStateRejectsPostDestinationEscapes() throws {
        let source = "[ok](\\#) [leading](\\# tail) [bare](url \\#) [angle](<url> \\#) [title](url \"t\" \\#)"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown),
            [SyntaxToken(kind: .link, range: NSRange(location: 0, length: 8))]
        )
    }

    func testMarkdownEscapedDestinationParenthesisPreservesMetadataDepth() throws {
        XCTAssertEqual(
            try SyntaxHighlighter.highlight("[x](a(\\)))", language: .markdown),
            [SyntaxToken(kind: .link, range: NSRange(location: 0, length: 10))]
        )
    }

    func testMarkdownIncompatibleDelimiterStackConsumesWorkBudget() throws {
        let openings = String(repeating: " *a", count: 1_000)
        let baseline = try measuredWork(openings + " bxxc")
        let source = openings + " b**c"

        XCTAssertGreaterThan(try measuredWork(source), baseline + 900)
        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                source,
                language: .markdown,
                limits: SyntaxHighlightingLimits(maximumWorkUnits: baseline + 500)
            )
        ) { error in
            XCTAssertEqual(
                error as? SyntaxHighlightingError,
                .workLimitExceeded(maximumWorkUnits: baseline + 500)
            )
        }
    }

    func testMarkdownFailedOuterDestinationPreservesNestedLink() throws {
        let source = "[bad]([ok](url)"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown),
            [SyntaxToken(kind: .link, range: NSRange(location: 6, length: 9))]
        )
    }

    func testMarkdownLongInlineLabelAndControlDestinations() throws {
        let longLabel = String(repeating: "x", count: 1_200)
        let source = "[\(longLabel)](url) [c0](\u{0001}) [del](\u{007F}) [angle](<\u{007F}>) [ok](valid)"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "link:[\(longLabel)](url)",
                "link:[ok](valid)"
            ]
        )
    }

    func testMarkdownInlineLinkTextHasNoReferenceLabel999CodePointCap() throws {
        for count in [999, 1_000] {
            let label = String(repeating: "x", count: count)
            let source = "[\(label)](url)"
            XCTAssertEqual(
                try SyntaxHighlighter.highlight(source, language: .markdown),
                [
                    SyntaxToken(
                        kind: .link,
                        range: NSRange(location: 0, length: count + 7)
                    )
                ]
            )
        }
    }

    func testMarkdownHeadingAndFenceInterruptMultilineDestination() throws {
        let source = "[heading](url\n# heading\n) [fence](url\n```\ncode\n```\n) **kept**"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            ["heading:# heading", "code:```\ncode\n```", "emphasis:**kept**"]
        )
    }

    func testMarkdownUnicodeSymbolsDriveFlankingAndRuleOfThree() throws {
        let source = "a©_yes_©b ***foo** *a**b*"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown).map {
                text.substring(with: $0.range)
            },
            ["_yes_", "**foo**", "*a**b*"]
        )
    }

    func testMarkdownWhitespaceOnlyBlankLineBreaksCodeSpan() throws {
        let source = "`open\n    \nplain\n`kept`"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .markdown),
            [SyntaxToken(kind: .code, range: NSRange(location: 17, length: 6))]
        )
    }

    func testMarkdownLinkMetadataHonorsTokenBound() throws {
        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                "[one](1) [two](2)",
                language: .markdown,
                limits: SyntaxHighlightingLimits(maximumTokenCount: 1)
            )
        ) { error in
            XCTAssertEqual(
                error as? SyntaxHighlightingError,
                .tooManyTokens(maximumTokens: 1)
            )
        }
    }

    func testUnmatchedMarkdownLinkAndEmphasisPreserveLaterTokens() throws {
        let unmatchedLink = "😀 [broken](unterminated **later**"
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(unmatchedLink, language: .markdown),
            [SyntaxToken(kind: .emphasis, range: NSRange(location: 25, length: 9))]
        )

        let unmatchedEmphasis = "😀 *unmatched **later**"
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(unmatchedEmphasis, language: .markdown),
            [SyntaxToken(kind: .emphasis, range: NSRange(location: 14, length: 9))]
        )
    }

    func testFailedRawHashProbeIsLinearAndPreservesLaterTokens() throws {
        let hashes = String(repeating: "#", count: 1_000)
        let source = hashes + " return 7"

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(
                source,
                language: .swift,
                limits: SyntaxHighlightingLimits(maximumWorkUnits: 1_100)
            ),
            [
                SyntaxToken(kind: .keyword, range: NSRange(location: 1_001, length: 6)),
                SyntaxToken(kind: .number, range: NSRange(location: 1_008, length: 1))
            ]
        )
    }

    func testMarkdownAdversaryIsBounded() throws {
        let markdown = (1...100).map { String(repeating: "`", count: $0) }.joined(separator: " ")
        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                markdown,
                language: .markdown,
                limits: SyntaxHighlightingLimits(maximumWorkUnits: 1_000)
            )
        ) { error in
            XCTAssertEqual(
                error as? SyntaxHighlightingError,
                .workLimitExceeded(maximumWorkUnits: 1_000)
            )
        }

        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                "1" + String(repeating: "U", count: 1_000),
                language: .cLike,
                limits: SyntaxHighlightingLimits(maximumWorkUnits: 100)
            )
        ) { error in
            XCTAssertEqual(
                error as? SyntaxHighlightingError,
                .workLimitExceeded(maximumWorkUnits: 100)
            )
        }
    }

    func testInvalidWorkLimitIsRejected() {
        let limits = [
            SyntaxHighlightingLimits(maximumInputUTF8Bytes: -1),
            SyntaxHighlightingLimits(maximumTokenCount: -1),
            SyntaxHighlightingLimits(maximumWorkUnits: -1),
            SyntaxHighlightingLimits(maximumMetadataEntries: -1)
        ]
        for limit in limits {
            XCTAssertThrowsError(
                try SyntaxHighlighter.highlight(
                    "text",
                    language: .swift,
                    limits: limit
                )
            ) { error in
                XCTAssertEqual(error as? SyntaxHighlightingError, .invalidLimits)
            }
        }
    }

    func testEmojiInputUTF8ExactBoundIsAccepted() throws {
        XCTAssertTrue(
            try SyntaxHighlighter.highlight(
                "😀",
                language: .swift,
                limits: SyntaxHighlightingLimits(maximumInputUTF8Bytes: 4)
            ).isEmpty
        )
        XCTAssertThrowsError(
            try SyntaxHighlighter.highlight(
                "😀",
                language: .swift,
                limits: SyntaxHighlightingLimits(maximumInputUTF8Bytes: 3)
            )
        ) { error in
            XCTAssertEqual(
                error as? SyntaxHighlightingError,
                .inputTooLarge(maximumUTF8Bytes: 3)
            )
        }
    }

    func testSwiftRegexContextSurvivesCommentTrivia() throws {
        let source = "return/* block */ /one/\nreturn// line\n/two/"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:return", "comment:/* block */", "string:/one/",
                "keyword:return", "comment:// line", "string:/two/"
            ]
        )
    }

    func testSwiftCommentContextWhitespaceCacheStopsAfterNonTrivia() throws {
        let suffix = String(repeating: " /", count: 1_000)
        let baseline = try measuredWork("x" + suffix, language: .swift)
        let source = "return/* comment */   x" + suffix

        XCTAssertLessThanOrEqual(try measuredWork(source, language: .swift), baseline + 64)
    }

    func testCancellationStopsInFlightScanningAtWorkCheckpoint() async {
        let source = String(repeating: ";", count: 100_000)
        let work = SyntaxWorkRecorder()
        let task = Task.detached {
            try SyntaxHighlighter.highlight(
                source,
                language: .swift,
                workObserver: { units in
                    work.record(units)
                    if units >= 4_096 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            )
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation during scanning")
        } catch is CancellationError {
            XCTAssertEqual(work.value, 4_096)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationAtScannerAndMarkdownStageCheckpoints() async {
        let fixtures: [(SyntaxHighlighter.Checkpoint, SyntaxHighlightingLanguage, String)] = [
            (.scanner, .swift, "let value = 1"),
            (.markdownCodeSpanMetadata, .markdown, "`code`"),
            (.markdownInlineMetadata, .markdown, String(repeating: ";", count: 5_000)),
            (.markdownEmission, .markdown, String(repeating: ";", count: 5_000))
        ]
        for (target, language, source) in fixtures {
            let events = SyntaxEventRecorder()
            let task = Task {
                try SyntaxHighlighter.$checkpointObserver.withValue(
                    { checkpoint in
                        events.record(.checkpoint(checkpoint))
                        if checkpoint == target {
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                    },
                    operation: {
                        try SyntaxHighlighter.highlight(
                            source,
                            language: language,
                            workObserver: { events.record(.work($0)) }
                        )
                    }
                )
            }
            do {
                _ = try await task.value
                XCTFail("Expected cancellation at \(target)")
            } catch is CancellationError {
                XCTAssertEqual(events.events.last, .checkpoint(target))
            } catch {
                XCTFail("Unexpected error at \(target): \(error)")
            }
        }
    }

    func testMarkdownDestinationParenthesisReclaimIsMeteredAndCancelable() async {
        let source = "[x](" + String(repeating: "(", count: 1_000)
        let events = SyntaxEventRecorder()
        let task = Task.detached {
            try SyntaxHighlighter.$checkpointObserver.withValue(
                { events.record(.checkpoint($0)) },
                operation: {
                    try SyntaxHighlighter.highlight(
                        source,
                        language: .markdown,
                        workObserver: { units in
                            events.record(.work(units))
                            if units >= 4_096 {
                                withUnsafeCurrentTask { $0?.cancel() }
                            }
                        }
                    )
                }
            )
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation while reclaiming destination metadata")
        } catch is CancellationError {
            XCTAssertEqual(events.events.last, .work(4_096))
            XCTAssertFalse(events.events.contains(.checkpoint(.markdownEmission)))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMarkdownDestinationParenthesisTransferIsMeteredAndCancelable() async {
        let source = "[x](" + String(repeating: "(", count: 3_000)
        let events = SyntaxEventRecorder()
        let task = Task.detached {
            try SyntaxHighlighter.$checkpointObserver.withValue(
                { events.record(.checkpoint($0)) },
                operation: {
                    try SyntaxHighlighter.highlight(
                        source,
                        language: .markdown,
                        workObserver: { units in
                            events.record(.work(units))
                            if units >= 8_192 {
                                withUnsafeCurrentTask { $0?.cancel() }
                            }
                        }
                    )
                }
            )
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation while transferring destination metadata")
        } catch is CancellationError {
            XCTAssertEqual(events.events.last, .work(8_192))
            XCTAssertFalse(events.events.contains(.checkpoint(.markdownEmission)))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLargeSuccessfulScansFitProportionalBudgets() throws {
        let swift = String(repeating: "identifier ", count: 1_000)
        XCTAssertTrue(
            try SyntaxHighlighter.highlight(
                swift,
                language: .swift,
                limits: SyntaxHighlightingLimits(maximumWorkUnits: swift.utf16.count * 2)
            ).isEmpty)

        let markdown = String(repeating: "# h\n", count: 1_000)
        XCTAssertEqual(
            try SyntaxHighlighter.highlight(
                markdown,
                language: .markdown,
                limits: SyntaxHighlightingLimits(maximumWorkUnits: markdown.utf16.count * 8)
            ).count, 1_000)
    }

    func testMarkdownWorkGrowsProportionallyWithInput() throws {
        let line = "[label](destination \"title\") *word* `code`\n"
        let smallWork = try measuredWork(String(repeating: line, count: 500))
        let largeWork = try measuredWork(String(repeating: line, count: 1_000))

        XCTAssertGreaterThan(largeWork, smallWork)
        XCTAssertLessThanOrEqual(largeWork, smallWork * 2 + 64)
    }

    func testMalformedRegexAndLinkRecoveryWorkGrowsProportionally() throws {
        let regexUnit = "= /[[ "
        let interpolationPrefix = "let value = \"\\("
        let markdownUnit = "[x]("
        let smallRegexWork = try measuredWork(
            String(repeating: regexUnit, count: 500),
            language: .swift
        )
        let largeRegexWork = try measuredWork(
            String(repeating: regexUnit, count: 1_000),
            language: .swift
        )
        let smallInterpolationWork = try measuredWork(
            interpolationPrefix + String(repeating: regexUnit, count: 500) + "\n",
            language: .swift
        )
        let largeInterpolationWork = try measuredWork(
            interpolationPrefix + String(repeating: regexUnit, count: 1_000) + "\n",
            language: .swift
        )
        let smallMarkdownWork = try measuredWork(
            String(repeating: markdownUnit, count: 500),
            language: .markdown
        )
        let largeMarkdownWork = try measuredWork(
            String(repeating: markdownUnit, count: 1_000),
            language: .markdown
        )

        XCTAssertLessThanOrEqual(largeRegexWork, smallRegexWork * 2 + 64)
        XCTAssertLessThanOrEqual(
            largeInterpolationWork,
            smallInterpolationWork * 2 + 64
        )
        XCTAssertLessThanOrEqual(largeMarkdownWork, smallMarkdownWork * 2 + 64)
    }

    func testFailedRawRegexDoesNotSuppressLaterBareRegex() throws {
        let source = "let bad = #/unterminated\nlet good = /ok/"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            [
                "keyword:let",
                "keyword:let",
                "string:/ok/"
            ]
        )
    }

    func testUnmatchedBareRegexClassDoesNotSuppressLaterRegex() throws {
        let source = "let bad = /[unterminated; let good = /ok/"
        let text = source as NSString

        XCTAssertEqual(
            try SyntaxHighlighter.highlight(source, language: .swift).map {
                "\($0.kind.rawValue):\(text.substring(with: $0.range))"
            },
            ["keyword:let", "keyword:let", "string:/ok/"]
        )
    }

    private func measuredWork(
        _ source: String,
        language: SyntaxHighlightingLanguage = .markdown
    ) throws -> Int {
        let work = SyntaxWorkRecorder()
        _ = try SyntaxHighlighter.highlight(
            source,
            language: language,
            workObserver: { work.record($0) }
        )
        return work.value
    }
}
