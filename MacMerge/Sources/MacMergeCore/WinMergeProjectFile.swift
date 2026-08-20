import Foundation

public struct WinMergeProjectFileDiagnostic: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case fileTooLarge
        case invalidUTF8
        case unsupportedEncoding
        case unsafeXMLConstruct
        case malformedXML
        case nestingTooDeep
        case tooManyElements
        case textTooLarge
        case unsupportedElement
        case unsupportedAttribute
        case invalidStructure
        case duplicateElement
        case invalidPathCount
        case invalidValue
        case invalidXMLCharacter
    }

    public let code: Code
    public let line: Int?
    public let column: Int?
    public let context: String?

    public init(
        code: Code,
        line: Int? = nil,
        column: Int? = nil,
        context: String? = nil
    ) {
        self.code = code
        self.line = line
        self.column = column
        self.context = context
    }

    public var errorDescription: String? {
        let subject: String
        switch code {
        case .fileTooLarge:
            subject = "WinMerge project data exceeds the supported byte limit."
        case .invalidUTF8:
            subject = "WinMerge project data is not valid UTF-8."
        case .unsupportedEncoding:
            subject = "WinMerge project XML declares an encoding other than UTF-8."
        case .unsafeXMLConstruct:
            subject = "WinMerge project XML contains a prohibited XML construct."
        case .malformedXML:
            subject = "WinMerge project XML is malformed."
        case .nestingTooDeep:
            subject = "WinMerge project XML exceeds the supported nesting depth."
        case .tooManyElements:
            subject = "WinMerge project XML exceeds the supported element count."
        case .textTooLarge:
            subject = "WinMerge project XML exceeds a supported text limit."
        case .unsupportedElement:
            subject = "WinMerge project XML contains an unsupported element."
        case .unsupportedAttribute:
            subject = "WinMerge project XML contains unsupported attributes or namespaces."
        case .invalidStructure:
            subject = "WinMerge project XML has an unsupported structure."
        case .duplicateElement:
            subject = "WinMerge project XML contains a duplicate singleton element."
        case .invalidPathCount:
            subject = "A WinMerge project must contain left and right paths, with an optional middle path."
        case .invalidValue:
            subject = "WinMerge project XML contains an unsupported value."
        case .invalidXMLCharacter:
            subject = "WinMerge project data contains a character prohibited by XML 1.0."
        }

        var description = subject
        if let context, !context.isEmpty {
            description += " Context: \(context)."
        }
        if let line, let column {
            description += " Location: line \(line), column \(column)."
        }
        return description
    }
}

public struct WinMergeProjectFile: Equatable, Sendable {
    public static let maximumEncodedBytes = 4 * 1024 * 1024
    public static let maximumNestingDepth = 16
    public static let maximumElementCount = 64
    public static let maximumTextUTF8Bytes = 256 * 1024
    public static let maximumElementTextUTF8Bytes = 64 * 1024

    public enum WindowType: Int, CaseIterable, Sendable {
        case text = 1
        case table = 2
        case binary = 3
        case image = 4
        case webpage = 5
    }

    public enum WhitespaceHandling: Int, CaseIterable, Sendable {
        case compare = 0
        case ignoreChanges = 1
        case ignoreAll = 2
    }

    public enum CompareMethod: Int, CaseIterable, Sendable {
        case fullContents = 0
        case quickContents = 1
        case binaryContents = 2
        case modifiedDate = 3
        case modifiedDateAndSize = 4
        case size = 5
    }

    public struct Options: Equatable, Sendable {
        public let windowType: WindowType?
        public let whitespaceHandling: WhitespaceHandling?
        public let ignoreBlankLines: Bool?
        public let ignoreCase: Bool?
        public let ignoreCarriageReturnDifferences: Bool?
        public let ignoreNumbers: Bool?
        public let ignoreCodepageDifferences: Bool?
        public let ignoreCommentDifferences: Bool?
        public let ignoreMissingTrailingEndOfLine: Bool?
        public let ignoreLineBreaks: Bool?
        public let compareMethod: CompareMethod?

        public init(
            windowType: WindowType? = nil,
            whitespaceHandling: WhitespaceHandling? = nil,
            ignoreBlankLines: Bool? = nil,
            ignoreCase: Bool? = nil,
            ignoreCarriageReturnDifferences: Bool? = nil,
            ignoreNumbers: Bool? = nil,
            ignoreCodepageDifferences: Bool? = nil,
            ignoreCommentDifferences: Bool? = nil,
            ignoreMissingTrailingEndOfLine: Bool? = nil,
            ignoreLineBreaks: Bool? = nil,
            compareMethod: CompareMethod? = nil
        ) {
            self.windowType = windowType
            self.whitespaceHandling = whitespaceHandling
            self.ignoreBlankLines = ignoreBlankLines
            self.ignoreCase = ignoreCase
            self.ignoreCarriageReturnDifferences = ignoreCarriageReturnDifferences
            self.ignoreNumbers = ignoreNumbers
            self.ignoreCodepageDifferences = ignoreCodepageDifferences
            self.ignoreCommentDifferences = ignoreCommentDifferences
            self.ignoreMissingTrailingEndOfLine = ignoreMissingTrailingEndOfLine
            self.ignoreLineBreaks = ignoreLineBreaks
            self.compareMethod = compareMethod
        }
    }

    public let leftPath: String
    public let middlePath: String?
    public let rightPath: String
    public let filter: String?
    public let includesSubfolders: Bool?
    public let leftReadOnly: Bool
    public let middleReadOnly: Bool
    public let rightReadOnly: Bool
    public let options: Options

    public init(
        leftPath: String,
        middlePath: String? = nil,
        rightPath: String,
        filter: String? = nil,
        includesSubfolders: Bool? = nil,
        leftReadOnly: Bool = false,
        middleReadOnly: Bool = false,
        rightReadOnly: Bool = false,
        options: Options = Options()
    ) throws {
        self.leftPath = leftPath
        self.middlePath = middlePath
        self.rightPath = rightPath
        self.filter = filter
        self.includesSubfolders = includesSubfolders
        self.leftReadOnly = leftReadOnly
        self.middleReadOnly = middleReadOnly
        self.rightReadOnly = rightReadOnly
        self.options = options
        try validate()
    }

    public static func parse(_ data: Data) throws -> WinMergeProjectFile {
        try Task.checkCancellation()
        guard data.count <= maximumEncodedBytes else {
            throw WinMergeProjectFileDiagnostic(
                code: .fileTooLarge,
                context: "maximum \(maximumEncodedBytes) bytes"
            )
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw WinMergeProjectFileDiagnostic(code: .invalidUTF8)
        }
        try validateXMLDeclaration(in: xml)
        guard !containsProhibitedDeclaration(in: xml) else {
            throw WinMergeProjectFileDiagnostic(code: .unsafeXMLConstruct)
        }

        let collector = XMLCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        collector.parser = parser

        let succeeded = parser.parse()
        if let failure = collector.failure {
            throw failure
        }
        guard succeeded else {
            throw WinMergeProjectFileDiagnostic(
                code: .malformedXML,
                line: positive(parser.lineNumber),
                column: positive(parser.columnNumber),
                context: parser.parserError?.localizedDescription
            )
        }
        try Task.checkCancellation()
        return try collector.makeProject()
    }

    public func serializedData() throws -> Data {
        try Task.checkCancellation()
        try validate()

        var output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<project>\n\t<paths>\n"
        try appendElement("left", value: leftPath, to: &output)
        if let middlePath {
            try appendElement("middle", value: middlePath, to: &output)
        }
        try appendElement("right", value: rightPath, to: &output)
        if let filter {
            try appendElement("filter", value: filter, to: &output)
        }
        if let includesSubfolders {
            appendElement("subfolders", integer: includesSubfolders ? 1 : 0, to: &output)
        }
        appendElement("left-readonly", integer: leftReadOnly ? 1 : 0, to: &output)
        if middlePath != nil {
            appendElement("middle-readonly", integer: middleReadOnly ? 1 : 0, to: &output)
        }
        appendElement("right-readonly", integer: rightReadOnly ? 1 : 0, to: &output)
        if let value = options.windowType?.rawValue {
            appendElement("window-type", integer: value, to: &output)
        }
        if let value = options.whitespaceHandling?.rawValue {
            appendElement("white-spaces", integer: value, to: &output)
        }
        appendOptionalBoolean(options.ignoreBlankLines, name: "ignore-blank-lines", to: &output)
        appendOptionalBoolean(options.ignoreCase, name: "ignore-case", to: &output)
        appendOptionalBoolean(
            options.ignoreCarriageReturnDifferences,
            name: "ignore-carriage-return-diff",
            to: &output
        )
        appendOptionalBoolean(options.ignoreNumbers, name: "ignore-numbers", to: &output)
        appendOptionalBoolean(
            options.ignoreCodepageDifferences,
            name: "ignore-codepage-diff",
            to: &output
        )
        appendOptionalBoolean(
            options.ignoreCommentDifferences,
            name: "ignore-comment-diff",
            to: &output
        )
        appendOptionalBoolean(
            options.ignoreMissingTrailingEndOfLine,
            name: "ignore-missing-trailing-eol",
            to: &output
        )
        appendOptionalBoolean(options.ignoreLineBreaks, name: "ignore-line-breaks", to: &output)
        if let value = options.compareMethod?.rawValue {
            appendElement("compare-method", integer: value, to: &output)
        }
        output += "\t</paths>\n</project>\n"

        let data = Data(output.utf8)
        guard data.count <= Self.maximumEncodedBytes else {
            throw WinMergeProjectFileDiagnostic(
                code: .fileTooLarge,
                context: "maximum \(Self.maximumEncodedBytes) bytes"
            )
        }
        try Task.checkCancellation()
        return data
    }

    private func validate() throws {
        guard !leftPath.isEmpty, !rightPath.isEmpty, middlePath != "" else {
            throw WinMergeProjectFileDiagnostic(code: .invalidPathCount)
        }
        try Self.validateText(leftPath, element: "left")
        if let middlePath {
            try Self.validateText(middlePath, element: "middle")
        }
        try Self.validateText(rightPath, element: "right")
        if let filter {
            try Self.validateText(filter, element: "filter")
        }
        guard middlePath != nil || !middleReadOnly else {
            throw WinMergeProjectFileDiagnostic(
                code: .invalidValue,
                context: "middle-readonly requires middle"
            )
        }
    }

    private static func validateText(_ text: String, element: String) throws {
        guard text.utf8.count <= maximumElementTextUTF8Bytes else {
            throw WinMergeProjectFileDiagnostic(
                code: .textTooLarge,
                context: "\(element), maximum \(maximumElementTextUTF8Bytes) UTF-8 bytes"
            )
        }
        guard text.unicodeScalars.allSatisfy(isValidXMLScalar) else {
            throw WinMergeProjectFileDiagnostic(code: .invalidXMLCharacter, context: element)
        }
    }

    private static func isValidXMLScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
            true
        default:
            false
        }
    }

    private static func validateXMLDeclaration(in xml: String) throws {
        let content = xml.first == "\u{FEFF}" ? xml.dropFirst() : xml[...]
        guard content.hasPrefix("<?xml") else { return }
        guard let end = content.range(of: "?>"), content.distance(from: content.startIndex, to: end.upperBound) <= 512 else {
            throw WinMergeProjectFileDiagnostic(code: .malformedXML, context: "XML declaration")
        }
        let declaration = content[..<end.lowerBound]
        let lowercased = declaration.lowercased()
        guard let encodingRange = lowercased.range(of: "encoding") else { return }
        var index = encodingRange.upperBound
        while index < lowercased.endIndex, lowercased[index].isWhitespace {
            index = lowercased.index(after: index)
        }
        guard index < lowercased.endIndex, lowercased[index] == "=" else {
            throw WinMergeProjectFileDiagnostic(code: .malformedXML, context: "XML encoding declaration")
        }
        index = lowercased.index(after: index)
        while index < lowercased.endIndex, lowercased[index].isWhitespace {
            index = lowercased.index(after: index)
        }
        guard index < lowercased.endIndex, lowercased[index] == "\"" || lowercased[index] == "'" else {
            throw WinMergeProjectFileDiagnostic(code: .malformedXML, context: "XML encoding declaration")
        }
        let quote = lowercased[index]
        let valueStart = lowercased.index(after: index)
        guard let valueEnd = lowercased[valueStart...].firstIndex(of: quote) else {
            throw WinMergeProjectFileDiagnostic(code: .malformedXML, context: "XML encoding declaration")
        }
        guard lowercased[valueStart..<valueEnd] == "utf-8" else {
            throw WinMergeProjectFileDiagnostic(code: .unsupportedEncoding)
        }
    }

    private static func containsProhibitedDeclaration(in xml: String) -> Bool {
        xml.range(of: "<!DOCTYPE") != nil || xml.range(of: "<!ENTITY") != nil
    }

    private func appendElement(_ name: String, value: String, to output: inout String) throws {
        try Task.checkCancellation()
        output += "\t\t<\(name)>\(Self.escape(value))</\(name)>\n"
    }

    private func appendElement(_ name: String, integer: Int, to output: inout String) {
        output += "\t\t<\(name)>\(integer)</\(name)>\n"
    }

    private func appendOptionalBoolean(_ value: Bool?, name: String, to output: inout String) {
        guard let value else { return }
        appendElement(name, integer: value ? 1 : 0, to: &output)
    }

    private static func escape(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.utf8.count)
        for character in value {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    private static func positive(_ value: Int) -> Int? {
        value > 0 ? value : nil
    }
}

private final class XMLCollector: NSObject, XMLParserDelegate {
    private struct Frame {
        let name: String
        var text = ""
        var textByteCount = 0
    }

    private static let leafElements: Set<String> = [
        "left",
        "middle",
        "right",
        "filter",
        "subfolders",
        "left-readonly",
        "middle-readonly",
        "right-readonly",
        "window-type",
        "white-spaces",
        "ignore-blank-lines",
        "ignore-case",
        "ignore-carriage-return-diff",
        "ignore-numbers",
        "ignore-codepage-diff",
        "ignore-comment-diff",
        "ignore-missing-trailing-eol",
        "ignore-line-breaks",
        "compare-method"
    ]

    weak var parser: XMLParser?
    private(set) var failure: Error?
    private var stack: [Frame] = []
    private var values: [String: String] = [:]
    private var elementCount = 0
    private var totalTextByteCount = 0
    private var pathsCount = 0
    private var completedDocument = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard checkCancellation(parser) else { return }
        elementCount += 1
        guard elementCount <= WinMergeProjectFile.maximumElementCount else {
            fail(.tooManyElements, parser: parser, context: "maximum \(WinMergeProjectFile.maximumElementCount)")
            return
        }
        guard stack.count < WinMergeProjectFile.maximumNestingDepth else {
            fail(.nestingTooDeep, parser: parser, context: "maximum \(WinMergeProjectFile.maximumNestingDepth)")
            return
        }
        guard attributeDict.isEmpty, namespaceURI?.isEmpty != false, qName?.contains(":") != true else {
            fail(.unsupportedAttribute, parser: parser, context: elementName)
            return
        }

        switch stack.count {
        case 0:
            guard elementName == "project", !completedDocument else {
                fail(.invalidStructure, parser: parser, context: elementName)
                return
            }
        case 1:
            guard stack[0].name == "project", elementName == "paths", pathsCount == 0 else {
                fail(
                    elementName == "paths" ? .invalidStructure : .unsupportedElement,
                    parser: parser,
                    context: elementName
                )
                return
            }
            pathsCount += 1
        case 2:
            guard stack[1].name == "paths" else {
                fail(.invalidStructure, parser: parser, context: elementName)
                return
            }
            guard Self.leafElements.contains(elementName) else {
                fail(.unsupportedElement, parser: parser, context: elementName)
                return
            }
            guard values[elementName] == nil, !stack.contains(where: { $0.name == elementName }) else {
                fail(.duplicateElement, parser: parser, context: elementName)
                return
            }
        default:
            fail(.invalidStructure, parser: parser, context: elementName)
            return
        }
        stack.append(Frame(name: elementName))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard checkCancellation(parser), !stack.isEmpty else { return }
        let byteCount = string.utf8.count
        guard byteCount <= WinMergeProjectFile.maximumTextUTF8Bytes - totalTextByteCount else {
            fail(.textTooLarge, parser: parser, context: "total text")
            return
        }
        totalTextByteCount += byteCount

        if stack.count < 3 {
            guard string.allSatisfy(\.isWhitespace) else {
                fail(.invalidStructure, parser: parser, context: "text outside a value element")
                return
            }
            return
        }
        guard byteCount <= WinMergeProjectFile.maximumElementTextUTF8Bytes - stack[stack.count - 1].textByteCount else {
            fail(.textTooLarge, parser: parser, context: stack[stack.count - 1].name)
            return
        }
        stack[stack.count - 1].text += string
        stack[stack.count - 1].textByteCount += byteCount
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard checkCancellation(parser), let frame = stack.popLast(), frame.name == elementName else {
            if failure == nil {
                fail(.invalidStructure, parser: parser, context: elementName)
            }
            return
        }
        if Self.leafElements.contains(elementName) {
            values[elementName] = frame.text
        } else if elementName == "project" {
            completedDocument = true
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        fail(.unsafeXMLConstruct, parser: parser, context: "CDATA")
    }

    func parser(
        _ parser: XMLParser,
        foundProcessingInstructionWithTarget target: String,
        data: String?
    ) {
        fail(.unsafeXMLConstruct, parser: parser, context: "processing instruction \(target)")
    }

    func parser(
        _ parser: XMLParser,
        resolveExternalEntityName name: String,
        systemID: String?
    ) -> Data? {
        fail(.unsafeXMLConstruct, parser: parser, context: "external entity \(name)")
        return nil
    }

    func makeProject() throws -> WinMergeProjectFile {
        guard completedDocument, stack.isEmpty, pathsCount == 1 else {
            throw WinMergeProjectFileDiagnostic(code: .invalidStructure)
        }
        guard let left = values["left"], !left.isEmpty,
            let right = values["right"], !right.isEmpty,
            values["middle"] != ""
        else {
            throw WinMergeProjectFileDiagnostic(code: .invalidPathCount)
        }
        let middle = values["middle"]
        let middleReadOnly = try boolean("middle-readonly") ?? false
        guard middle != nil || !middleReadOnly else {
            throw invalidValue("middle-readonly requires middle")
        }

        let options = WinMergeProjectFile.Options(
            windowType: try enumeration("window-type", as: WinMergeProjectFile.WindowType.self),
            whitespaceHandling: try enumeration(
                "white-spaces",
                as: WinMergeProjectFile.WhitespaceHandling.self
            ),
            ignoreBlankLines: try boolean("ignore-blank-lines"),
            ignoreCase: try boolean("ignore-case"),
            ignoreCarriageReturnDifferences: try boolean("ignore-carriage-return-diff"),
            ignoreNumbers: try boolean("ignore-numbers"),
            ignoreCodepageDifferences: try boolean("ignore-codepage-diff"),
            ignoreCommentDifferences: try boolean("ignore-comment-diff"),
            ignoreMissingTrailingEndOfLine: try boolean("ignore-missing-trailing-eol"),
            ignoreLineBreaks: try boolean("ignore-line-breaks"),
            compareMethod: try enumeration("compare-method", as: WinMergeProjectFile.CompareMethod.self)
        )
        return try WinMergeProjectFile(
            leftPath: left,
            middlePath: middle,
            rightPath: right,
            filter: values["filter"],
            includesSubfolders: try boolean("subfolders"),
            leftReadOnly: try boolean("left-readonly") ?? false,
            middleReadOnly: middleReadOnly,
            rightReadOnly: try boolean("right-readonly") ?? false,
            options: options
        )
    }

    private func boolean(_ name: String) throws -> Bool? {
        guard let text = values[name] else { return nil }
        switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "0": return false
        case "1": return true
        default: throw invalidValue(name)
        }
    }

    private func enumeration<T: RawRepresentable>(_ name: String, as type: T.Type) throws -> T?
    where T.RawValue == Int {
        guard let text = values[name] else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue = Int(trimmed), String(rawValue) == trimmed, let value = T(rawValue: rawValue) else {
            throw invalidValue(name)
        }
        return value
    }

    private func invalidValue(_ context: String) -> WinMergeProjectFileDiagnostic {
        WinMergeProjectFileDiagnostic(code: .invalidValue, context: context)
    }

    private func checkCancellation(_ parser: XMLParser) -> Bool {
        guard !Task.isCancelled else {
            failure = CancellationError()
            parser.abortParsing()
            return false
        }
        return failure == nil
    }

    private func fail(
        _ code: WinMergeProjectFileDiagnostic.Code,
        parser: XMLParser,
        context: String? = nil
    ) {
        guard failure == nil else { return }
        failure = WinMergeProjectFileDiagnostic(
            code: code,
            line: parser.lineNumber > 0 ? parser.lineNumber : nil,
            column: parser.columnNumber > 0 ? parser.columnNumber : nil,
            context: context
        )
        parser.abortParsing()
    }
}
