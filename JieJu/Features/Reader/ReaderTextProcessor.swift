import Foundation

enum ReaderTextProcessor {
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"(?<=\p{L})-\s*\n\s*(?=\p{Ll})"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func context(
        for selectedText: String,
        in surroundingText: String
    ) -> (preceding: String?, following: String?) {
        let target = clean(selectedText)
        let source = clean(surroundingText)
        guard !target.isEmpty, let range = source.range(of: target) else {
            return (nil, nil)
        }

        let sentences = sentenceRanges(in: source)
        guard let selectedIndex = sentences.firstIndex(where: { sentenceRange in
            sentenceRange.overlaps(range) || sentenceRange.contains(range.lowerBound)
        }) else { return (nil, nil) }

        let preceding = selectedIndex > 0 ? clean(String(source[sentences[selectedIndex - 1]])) : nil
        let following = selectedIndex + 1 < sentences.count
            ? clean(String(source[sentences[selectedIndex + 1]]))
            : nil
        return (preceding?.nilIfEmpty, following?.nilIfEmpty)
    }

    /// Removes an accidental trailing sentence fragment while preserving deliberate
    /// fragment-only and multi-sentence selections.
    static func preparedSelection(_ text: String) -> String {
        let cleaned = clean(text)
        guard let terminator = cleaned.lastIndex(where: { ".!?。！？".contains($0) }) else {
            return cleaned
        }
        let remainder = cleaned[cleaned.index(after: terminator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return cleaned }
        return String(cleaned[...terminator])
    }

    private static func sentenceRanges(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if ".!?。！？".contains(text[index]) {
                result.append(start..<next)
                start = next
                while start < text.endIndex, text[start].isWhitespace {
                    start = text.index(after: start)
                }
                index = start
            } else {
                index = next
            }
        }
        if start < text.endIndex { result.append(start..<text.endIndex) }
        return result.filter { !clean(String(text[$0])).isEmpty }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
