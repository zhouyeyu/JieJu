import Foundation
import IPADic
import Mecab_Swift

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

public struct JapaneseMorphologicalToken: Equatable, Sendable {
    public let surface: String
    public let reading: String
    public let dictionaryForm: String
    public let partOfSpeech: String
    public let isInflected: Bool
}

public protocol JapaneseMorphologyProviding: JapaneseReadingProviding {
    func tokens(for text: String) -> [JapaneseMorphologicalToken]
}

public final class MeCabJapaneseReadingProvider: JapaneseMorphologyProviding, @unchecked Sendable {
    private let tokenizer: Tokenizer
    private let lock = NSLock()

    public init() throws { tokenizer = try Tokenizer(dictionary: IPADic()) }

    public func segments(for text: String) -> [ReadingSegment] {
        lock.withLock {
            let annotations = tokenizer.furiganaAnnotations(for: text, transliteration: .hiragana)
            var result: [ReadingSegment] = []
            var cursor = text.startIndex
            for annotation in annotations.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
                guard annotation.range.lowerBound >= cursor else { continue }
                if cursor < annotation.range.lowerBound {
                    result.append(.init(surface: String(text[cursor..<annotation.range.lowerBound])))
                }
                result.append(.init(surface: String(text[annotation.range]), reading: annotation.reading))
                cursor = annotation.range.upperBound
            }
            if cursor < text.endIndex { result.append(.init(surface: String(text[cursor...]))) }
            return result.isEmpty && !text.isEmpty ? [.init(surface: text)] : result
        }
    }

    public func tokens(for text: String) -> [JapaneseMorphologicalToken] {
        lock.withLock {
            tokenizer.tokenize(text: text, transliteration: .hiragana).map {
                .init(
                    surface: $0.base,
                    reading: $0.reading,
                    dictionaryForm: $0.dictionaryForm,
                    partOfSpeech: $0.partOfSpeech.description,
                    isInflected: $0.base != $0.dictionaryForm
                )
            }
        }
    }
}

public enum JapaneseReadingProviders {
    public static let `default`: any JapaneseReadingProviding = {
        if let provider = try? MeCabJapaneseReadingProvider() {
            return provider as any JapaneseReadingProviding
        }
        return LocalJapaneseReadingProvider() as any JapaneseReadingProviding
    }()
}

public enum JapaneseGrammarAnalyzer {
    public static func localAnalysis(request: ExplanationRequest) throws -> DeepAnalysis {
        let chinese = request.explanationLanguage.localizedCaseInsensitiveContains("Chinese")
        let base = DeepAnalysis(
            sentenceType: chinese ? "日语句" : "Japanese sentence",
            sentencePattern: "",
            components: [],
            clauses: [],
            grammarPoints: [],
            interpretation: chinese
                ? "本地解析展示句式、助词和谓语功能；句意请结合上方翻译理解。"
                : "This local analysis focuses on structure, particles, and predicate forms; use the translation above for meaning.",
            japaneseWords: []
        )
        return try enrich(base, request: request).validated(against: request)
    }

    public static func enrich(_ analysis: DeepAnalysis, request: ExplanationRequest) -> DeepAnalysis {
        guard request.sourceLanguage.localizedCaseInsensitiveContains("Japanese"),
              let provider = try? MeCabJapaneseReadingProvider() else { return analysis }
        let tokens = provider.tokens(for: request.targetText)
        let chinese = request.explanationLanguage.localizedCaseInsensitiveContains("Chinese")
        let localGrammar = grammarPoints(tokens: tokens, text: request.targetText, chinese: chinese)
        let usefulModelGrammar = analysis.grammarPoints.filter { modelPoint in
            modelPoint.explanation.matchableForQuality != modelPoint.text.matchableForQuality &&
            !localGrammar.contains(where: { $0.text == modelPoint.text })
        }
        let grammar = Array((localGrammar + usefulModelGrammar).prefix(6))
        let structure = structure(tokens: tokens, chinese: chinese)
        let localWords = tokens.filter { token in
            token.surface.unicodeScalars.contains(where: \.isHan) && token.partOfSpeech != "particle" && token.partOfSpeech != "symbol"
        }.prefix(12).map { token in
            JapaneseWordAnalysis(
                text: token.surface,
                baseForm: token.dictionaryForm,
                reading: token.reading,
                inflectionType: token.isInflected
                    ? (chinese ? "活用形（原形：\(token.dictionaryForm)）" : "inflected; dictionary form: \(token.dictionaryForm)")
                    : (chinese ? "基本形／无活用" : "dictionary form / not inflected"),
                grammaticalFunction: grammaticalFunction(token.partOfSpeech, chinese: chinese)
            )
        }
        return DeepAnalysis(
            sentenceType: chinese ? "日语句" : "Japanese sentence",
            sentencePattern: structure.pattern.isEmpty
                ? (analysis.sentencePattern.isEmpty ? (chinese ? "单一谓语结构" : "single-predicate structure") : analysis.sentencePattern)
                : structure.pattern,
            components: structure.components.isEmpty ? analysis.components : structure.components,
            clauses: analysis.clauses,
            grammarPoints: grammar,
            interpretation: analysis.interpretation,
            japaneseWords: localWords.isEmpty ? analysis.japaneseWords : Array(localWords)
        )
    }

    private static func grammarPoints(tokens: [JapaneseMorphologicalToken], text: String, chinese: Bool) -> [GrammarPoint] {
        let explanationsZH: [String: String] = [
            "は": "提示主题，说明后面的判断或动作围绕此前项展开；它强调话题，不等同于单纯标记主语的「が」。",
            "が": "标记主语或新信息，指出是谁／什么执行动作或处于某种状态。",
            "を": "标记动作直接作用的对象，连接宾语与后面的动词。",
            "に": "标记到达点、存在位置、具体时间或动作指向的对象，需结合谓语判断。",
            "で": "标记动作发生的场所、采用的手段或原因，需结合前项名词与谓语判断。",
            "の": "连接两个名词，使前项限定后项，可表示所属、种类、内容等关系。",
            "と": "标记共同参与者、引用内容或并列对象，具体作用由后面的谓语决定。",
            "も": "表示“也／连……也”，在已有话题或同类项目上追加信息。",
            "へ": "标记移动方向，侧重朝向；「に」通常更侧重明确到达点。",
            "から": "标记时间、空间或原因的起点。",
            "まで": "标记时间或空间的终点、范围上限。"
        ]
        let explanationsEN: [String: String] = [
            "は": "Marks the topic; unlike が, it frames what the following comment is about.",
            "が": "Marks the grammatical subject or newly identified information.",
            "を": "Marks the direct object affected by the following verb.",
            "に": "Marks a destination, time, location of existence, or indirect target depending on the predicate.",
            "で": "Marks the place of an action, means, material, or cause.",
            "の": "Links nouns so the first limits or describes the second.",
            "と": "Marks accompaniment, quotation, or an item in an exhaustive list.",
            "も": "Adds a parallel item with the sense of also/even.",
            "へ": "Marks direction, with less emphasis on arrival than に.",
            "から": "Marks a temporal, spatial, or causal starting point.",
            "まで": "Marks an endpoint or upper boundary."
        ]
        let table = chinese ? explanationsZH : explanationsEN
        var result: [GrammarPoint] = []
        for index in tokens.indices where isSemanticParticle(at: index, tokens: tokens) {
            let token = tokens[index]
            guard let explanation = table[token.surface], !result.contains(where: { $0.text == token.surface }) else { continue }
            result.append(.init(text: token.surface, explanation: explanation))
        }
        let constructions: [(String, String, String)] = [
            ("でいます", "动词て形（浊音形式「で」）＋「いる」的礼貌形式，依动词语义表示动作正在进行、反复持续或结果状态。", "Polite ている construction after a voiced て-form, expressing an ongoing/repeated action or a resulting state."),
            ("ています", "「て形＋いる」的礼貌形式，依动词语义表示动作正在进行、反复持续或结果状态。", "Polite ている construction, expressing an ongoing/repeated action or a resulting state."),
            ("ている", "「て形＋いる」表示动作正在进行、反复持续或动作完成后的结果状态。", "The ている construction expresses an ongoing/repeated action or a resulting state."),
            ("ません", "「ます」的否定形式，使谓语成为礼貌体现在／将来否定。", "Negative form of ます, making the predicate a polite non-past negative."),
            ("ました", "「ます」的过去形式，使谓语成为礼貌体过去／完成表达。", "Past form of ます, making the predicate polite past or completed."),
            ("たい", "接在动词连用形后表示说话者想做某事。", "Attaches to a verb stem to express the speaker's desire to act.")
        ]
        for (form, zh, en) in constructions where text.contains(form) && result.count < 6 {
            result.append(.init(text: form, explanation: chinese ? zh : en))
        }
        return result
    }

    private static func structure(tokens: [JapaneseMorphologicalToken], chinese: Bool) -> (pattern: String, components: [SentenceComponent]) {
        let labelsZH = ["は": "主题", "が": "主语", "を": "宾语", "に": "目标／时间", "で": "场所／手段", "の": "连体修饰", "と": "引用／共同者", "も": "追加主题", "へ": "方向", "から": "起点", "まで": "终点"]
        var parts: [String] = []
        var components: [SentenceComponent] = []
        var consumed = Set<Int>()
        for index in tokens.indices where isSemanticParticle(at: index, tokens: tokens) && index > 0 {
            guard let zh = labelsZH[tokens[index].surface], !consumed.contains(index - 1) else { continue }
            let surface = tokens[index - 1].surface + tokens[index].surface
            let role = chinese ? zh : "\(tokens[index].surface)-marked phrase"
            parts.append("\(role)(\(surface))")
            components.append(.init(text: surface, role: role,
                                    explanation: chinese ? "由助词「\(tokens[index].surface)」标记的\(zh)成分。" : "A phrase marked by \(tokens[index].surface)."))
            consumed.insert(index - 1); consumed.insert(index)
        }
        if let verbIndex = tokens.firstIndex(where: { $0.partOfSpeech == "verb" }) {
            let predicate = tokens[verbIndex...].map(\.surface).joined()
            if !predicate.isEmpty {
                let role = chinese ? "谓语" : "predicate"
                parts.append("\(role)(\(predicate))")
                components.append(.init(text: predicate, role: role,
                                        explanation: chinese ? "句子的核心述语，表达动作、变化或状态。" : "The core predicate expressing an action, change, or state."))
            }
        }
        return (parts.joined(separator: "＋"), Array(components.prefix(8)))
    }

    private static func grammaticalFunction(_ partOfSpeech: String, chinese: Bool) -> String {
        guard chinese else { return partOfSpeech }
        return ["noun": "名词性成分", "verb": "谓语动词", "adjective": "形容词性成分", "adverb": "副词性修饰语", "prefix": "接头成分"][partOfSpeech] ?? "句中词语"
    }

    private static func isSemanticParticle(at index: Int, tokens: [JapaneseMorphologicalToken]) -> Bool {
        guard tokens[index].partOfSpeech == "particle" else { return false }
        // IPADic exposes broad POS only. A で immediately following a verb is normally the connective
        // part of て-form (読んで), not the case particle for location or means.
        if tokens[index].surface == "で", index > 0, tokens[index - 1].partOfSpeech == "verb" { return false }
        return true
    }
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
    var matchableForQuality: String { trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
