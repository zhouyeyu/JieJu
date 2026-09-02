import Foundation

public struct ReadingSegment: Codable, Equatable, Sendable {
    public let surface: String
    public let reading: String?

    public init(surface: String, reading: String? = nil) {
        self.surface = surface
        self.reading = reading?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct JapaneseWordAnalysis: Codable, Equatable, Sendable {
    public let text: String
    public let baseForm: String
    public let reading: String
    public let inflectionType: String
    public let grammaticalFunction: String

    public init(text: String, baseForm: String, reading: String, inflectionType: String, grammaticalFunction: String) {
        self.text = text
        self.baseForm = baseForm
        self.reading = reading
        self.inflectionType = inflectionType
        self.grammaticalFunction = grammaticalFunction
    }
}

public enum TextLanguageDetector {
    public static func languageName(for text: String, fallback: String = "English") -> String {
        let scalars = text.unicodeScalars
        let japanese = scalars.filter { $0.isHiragana || $0.isKatakana }.count
        let han = scalars.filter(\.isHan).count
        guard japanese > 0 else { return fallback }
        return japanese + han >= max(2, scalars.filter { !$0.properties.isWhitespace }.count / 4) ? "Japanese" : fallback
    }
}

public protocol JapaneseReadingProviding: Sendable {
    func segments(for text: String) -> [ReadingSegment]
}

/// A deliberately conservative local annotator. Unknown kanji remain unannotated instead of being guessed.
public struct LocalJapaneseReadingProvider: JapaneseReadingProviding {
    public let lexicon: [String: String]

    public init(lexicon: [String: String] = Self.foundationLexicon) { self.lexicon = lexicon }

    public func segments(for text: String) -> [ReadingSegment] {
        guard !text.isEmpty else { return [] }
        let keys = lexicon.keys.sorted { $0.count > $1.count }
        var result: [ReadingSegment] = []
        var index = text.startIndex
        var plain = ""

        func appendPlain() {
            guard !plain.isEmpty else { return }
            result.append(.init(surface: plain))
            plain = ""
        }

        while index < text.endIndex {
            if let key = keys.first(where: { text[index...].hasPrefix($0) }), let reading = lexicon[key] {
                appendPlain()
                result.append(.init(surface: key, reading: reading))
                index = text.index(index, offsetBy: key.count)
            } else {
                plain.append(text[index])
                index = text.index(after: index)
            }
        }
        appendPlain()
        return result
    }

    public static let foundationLexicon: [String: String] = [
        "日本語": "にほんご", "日本": "にほん", "今日": "きょう", "明日": "あした",
        "昨日": "きのう", "学校": "がっこう", "先生": "せんせい", "学生": "がくせい",
        "私": "わたし", "彼女": "かのじょ", "彼": "かれ", "東京": "とうきょう",
        "京都": "きょうと", "電車": "でんしゃ", "時間": "じかん", "本": "ほん",
        "読む": "よむ", "読んだ": "よんだ", "食べる": "たべる", "行く": "いく",
        "行った": "いった", "見る": "みる", "話す": "はなす", "勉強": "べんきょう"
    ]
}

private extension Unicode.Scalar {
    var isHiragana: Bool { (0x3040...0x309F).contains(value) }
    var isKatakana: Bool { (0x30A0...0x30FF).contains(value) || (0xFF66...0xFF9D).contains(value) }
    var isHan: Bool { (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value) }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
