import Foundation

/// Parses the compact dictionary cards returned by Pealim's `/ru/search/` page.
///
/// The parser deliberately depends only on the result-card class names instead
/// of the page's surrounding layout. Malformed cards are skipped so one changed
/// result cannot hide otherwise usable entries.
public struct PealimHTMLParser: Sendable {
    public init() {}

    public func parse(_ html: String, documentURL: URL = PealimClient.defaultBaseURL) -> [PealimSearchResult] {
        HTML.elementContents(named: "div", havingClass: "verb-search-result", in: html).compactMap { resultHTML in
            parseResult(resultHTML, documentURL: documentURL)
        }
    }

    private func parseResult(_ resultHTML: String, documentURL: URL) -> PealimSearchResult? {
        guard
            let dataHTML = HTML.firstElementContent(named: "div", havingClass: "verb-search-data", in: resultHTML),
            let lemmaHTML = HTML.firstElementContent(named: "div", havingClass: "verb-search-lemma", in: dataHTML),
            let lemma = HTML.textContent(named: "span", havingClass: "menukad", in: lemmaHTML),
            !lemma.isEmpty,
            let partOfSpeechHTML = HTML.firstElementContent(named: "div", havingClass: "verb-search-binyan", in: dataHTML),
            let meaningHTML = HTML.firstElementContent(named: "div", havingClass: "verb-search-meaning", in: dataHTML),
            let sourceHref = HTML.firstLink(in: lemmaHTML, pathPrefix: "/ru/dict/"),
            let sourceURL = HTML.resolveURL(sourceHref, relativeTo: documentURL)
        else {
            return nil
        }

        let root = HTML.firstElementContent(named: "div", havingClass: "verb-search-root", in: dataHTML)
            .map(HTML.textWithoutLabel)
            .flatMap { value in
                value == "-" || value.isEmpty ? nil : value
            }

        let transcription = HTML.textContent(named: "span", havingClass: "transcription", in: resultHTML)
            .flatMap { $0.isEmpty ? nil : $0 }

        let audioURL = HTML.firstAttribute(named: "data-audio", in: lemmaHTML)
            .flatMap { HTML.resolveURL($0, relativeTo: documentURL) }

        return PealimSearchResult(
            lemma: lemma,
            transcription: transcription,
            root: root,
            partOfSpeech: HTML.textWithoutLabel(partOfSpeechHTML),
            meaning: HTML.plainText(meaningHTML),
            sourceURL: sourceURL,
            audioURL: audioURL
        )
    }
}

private enum HTML {
    private static let tagExpression = try! NSRegularExpression(
        pattern: #"<\s*(/?)\s*([A-Za-z][A-Za-z0-9:-]*)\b([^>]*)>"#,
        options: [.caseInsensitive]
    )

    private static let stripTagsExpression = try! NSRegularExpression(
        pattern: #"<[^>]+>"#,
        options: [.caseInsensitive]
    )

    private static let numericEntityExpression = try! NSRegularExpression(
        pattern: #"&#(x[0-9A-Fa-f]+|[0-9]+);"#
    )

    private struct Tag {
        let name: String
        let attributes: String
        let isClosing: Bool
        let isSelfClosing: Bool
        let range: NSRange
    }

    static func elementContents(named tagName: String, havingClass className: String, in html: String) -> [String] {
        let tags = tags(in: html)
        var contents: [String] = []
        var index = 0

        while index < tags.count {
            let tag = tags[index]
            guard
                !tag.isClosing,
                tag.name.caseInsensitiveCompare(tagName) == .orderedSame,
                classTokens(in: tag.attributes).contains(className),
                let closingIndex = matchingClosingTagIndex(for: index, in: tags)
            else {
                index += 1
                continue
            }

            let contentLocation = tag.range.location + tag.range.length
            let contentLength = tags[closingIndex].range.location - contentLocation
            if let content = substring(html, range: NSRange(location: contentLocation, length: contentLength)) {
                contents.append(content)
            }
            index = closingIndex + 1
        }

        return contents
    }

    static func firstElementContent(named tagName: String, havingClass className: String, in html: String) -> String? {
        elementContents(named: tagName, havingClass: className, in: html).first
    }

    static func textContent(named tagName: String, havingClass className: String, in html: String) -> String? {
        firstElementContent(named: tagName, havingClass: className, in: html).map(plainText)
    }

    static func firstLink(in html: String, pathPrefix: String) -> String? {
        let tags = tags(in: html)
        for tag in tags where !tag.isClosing && tag.name.caseInsensitiveCompare("a") == .orderedSame {
            guard
                let href = attribute(named: "href", in: tag.attributes),
                decodeEntities(href).hasPrefix(pathPrefix)
            else {
                continue
            }
            return decodeEntities(href)
        }
        return nil
    }

    static func firstAttribute(named name: String, in html: String) -> String? {
        for tag in tags(in: html) where !tag.isClosing {
            if let value = attribute(named: name, in: tag.attributes) {
                return decodeEntities(value)
            }
        }
        return nil
    }

    static func resolveURL(_ value: String, relativeTo documentURL: URL) -> URL? {
        URL(string: value, relativeTo: documentURL)?.absoluteURL
    }

    static func textWithoutLabel(_ html: String) -> String {
        var content = html
        if let label = firstElementContent(named: "span", havingClass: "verb-search-label", in: html) {
            content = content.replacingOccurrences(of: label, with: "")
        }
        return plainText(content)
    }

    static func plainText(_ html: String) -> String {
        let withBreakSpaces = html.replacingOccurrences(
            of: #"<\s*br\s*/?\s*>"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let range = NSRange(withBreakSpaces.startIndex..<withBreakSpaces.endIndex, in: withBreakSpaces)
        let withoutTags = stripTagsExpression.stringByReplacingMatches(
            in: withBreakSpaces,
            range: range,
            withTemplate: ""
        )
        return normalizeWhitespace(decodeEntities(withoutTags))
    }

    private static func tags(in html: String) -> [Tag] {
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return tagExpression.matches(in: html, range: fullRange).compactMap { match in
            guard
                let name = substring(html, range: match.range(at: 2)),
                let attributes = substring(html, range: match.range(at: 3))
            else {
                return nil
            }
            let isClosing = match.range(at: 1).length > 0
            return Tag(
                name: name,
                attributes: attributes,
                isClosing: isClosing,
                isSelfClosing: !isClosing && attributes.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/"),
                range: match.range
            )
        }
    }

    private static func matchingClosingTagIndex(for openingIndex: Int, in tags: [Tag]) -> Int? {
        let openingTag = tags[openingIndex]
        guard !openingTag.isSelfClosing else { return nil }

        var depth = 1
        for index in tags.indices where index > openingIndex {
            let tag = tags[index]
            guard tag.name.caseInsensitiveCompare(openingTag.name) == .orderedSame else {
                continue
            }
            if tag.isClosing {
                depth -= 1
            } else if !tag.isSelfClosing {
                depth += 1
            }
            if depth == 0 {
                return index
            }
        }
        return nil
    }

    private static func classTokens(in attributes: String) -> Set<String> {
        guard let classValue = attribute(named: "class", in: attributes) else {
            return []
        }
        return Set(classValue.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    }

    private static func attribute(named name: String, in attributes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let expression = try! NSRegularExpression(
            pattern: #"(?:^|\s)"# + escapedName + #"\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#,
            options: [.caseInsensitive]
        )
        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        guard let match = expression.firstMatch(in: attributes, range: range) else {
            return nil
        }
        for captureIndex in 1...3 where match.range(at: captureIndex).location != NSNotFound {
            return substring(attributes, range: match.range(at: captureIndex))
        }
        return nil
    }

    private static func decodeEntities(_ input: String) -> String {
        var output = input
        let fullRange = NSRange(output.startIndex..<output.endIndex, in: output)
        for match in numericEntityExpression.matches(in: output, range: fullRange).reversed() {
            guard
                let entityRange = Range(match.range(at: 0), in: output),
                let numberRange = Range(match.range(at: 1), in: output)
            else {
                continue
            }

            let numberText = String(output[numberRange])
            let value: UInt32?
            if numberText.lowercased().hasPrefix("x") {
                value = UInt32(numberText.dropFirst(), radix: 16)
            } else {
                value = UInt32(numberText, radix: 10)
            }
            if let value, let scalar = UnicodeScalar(value) {
                output.replaceSubrange(entityRange, with: String(Character(scalar)))
            }
        }

        let namedEntities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&ndash;": "–",
            "&mdash;": "—"
        ]
        for (entity, replacement) in namedEntities {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }
        return output
    }

    private static func normalizeWhitespace(_ input: String) -> String {
        input
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func substring(_ string: String, range: NSRange) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else {
            return nil
        }
        return String(string[swiftRange])
    }
}
