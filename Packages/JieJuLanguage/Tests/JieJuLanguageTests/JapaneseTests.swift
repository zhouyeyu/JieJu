import Foundation
import Testing
@testable import JieJuLanguage

@Suite struct JapaneseTests {
    @Test func readingSegmentCodableRoundTrip() throws {
        let segments = [ReadingSegment(surface: "日本語", reading: "にほんご"), ReadingSegment(surface: "を読む")]
        let data = try JSONEncoder().encode(segments)
        #expect(try JSONDecoder().decode([ReadingSegment].self, from: data) == segments)
    }

    @Test func detectsJapaneseFromKanaAndHan() {
        #expect(TextLanguageDetector.languageName(for: "私は本を読みます。") == "Japanese")
        #expect(TextLanguageDetector.languageName(for: "The book is new.") == "English")
        #expect(TextLanguageDetector.languageName(for: "2026年") == "English")
    }

    @Test func localProviderUsesLongestKnownReadingAndPreservesSource() {
        let segments = LocalJapaneseReadingProvider().segments(for: "私は日本語の本を読む。")
        #expect(segments.map(\.surface).joined() == "私は日本語の本を読む。")
        #expect(segments.contains(.init(surface: "日本語", reading: "にほんご")))
        #expect(segments.contains(.init(surface: "読む", reading: "よむ")))
    }

    @Test func localProviderDoesNotGuessUnknownKanji() {
        let segments = LocalJapaneseReadingProvider(lexicon: [:]).segments(for: "難読")
        #expect(segments == [.init(surface: "難読")])
    }

    @Test func mecabProvidesReadingLemmaAndPartOfSpeech() throws {
        let provider = try MeCabJapaneseReadingProvider()
        let text = "昨日、その本を読んだ。"
        let segments = provider.segments(for: text)
        #expect(segments.map(\.surface).joined() == text)
        #expect(segments.contains { $0.surface == "昨日" && $0.reading == "きのう" })
        #expect(segments.contains { $0.surface == "読" && $0.reading == "よ" })

        let tokens = provider.tokens(for: text)
        let verb = try #require(tokens.first { $0.surface == "読ん" })
        #expect(verb.reading == "よん")
        #expect(verb.dictionaryForm == "読む")
        #expect(verb.partOfSpeech == "verb")
        #expect(verb.isInflected)
    }

    @Test func JapaneseFragmentsUseUnspacedMatching() throws {
        let request = ExplanationRequest(targetText: "私は本を読みます。", sourceLanguage: "Japanese")
        let explanation = Explanation(
            translation: "我读书。", sentenceCore: "読みます",
            grammarPoints: [.init(text: "読みます", explanation: "礼貌体")],
            keyPhrases: [.init(text: "本", meaning: "书")]
        )
        #expect(try explanation.validated(against: request) == explanation)
    }

    @Test func deterministicGrammarEnrichmentExplainsParticlesAndAspect() throws {
        let request = ExplanationRequest(
            targetText: "私は日本語の本を読んでいます。",
            sourceLanguage: "Japanese",
            explanationLanguage: "Chinese"
        )
        let sparse = DeepAnalysis(
            sentenceType: "S", sentencePattern: "SVO", components: [], clauses: [],
            grammarPoints: [.init(text: "は", explanation: "は")], interpretation: "我正在读日语书。",
            japaneseWords: []
        )
        let enriched = JapaneseGrammarAnalyzer.enrich(sparse, request: request)
        #expect(enriched.sentencePattern.contains("主题(私は)"))
        #expect(enriched.sentencePattern.contains("宾语(本を)"))
        #expect(enriched.sentencePattern.contains("谓语(読んでいます。)"))
        #expect(enriched.grammarPoints.contains { $0.text == "は" && $0.explanation.contains("主题") })
        #expect(enriched.grammarPoints.contains { $0.text == "の" && $0.explanation.contains("限定") })
        #expect(enriched.grammarPoints.contains { $0.text == "を" && $0.explanation.contains("对象") })
        #expect(enriched.grammarPoints.contains { $0.text == "でいます" && $0.explanation.contains("正在进行") })
        #expect(enriched.japaneseWords?.contains { $0.text == "読ん" && $0.baseForm == "読む" } == true)
        #expect(try enriched.validated(against: request) == enriched)
    }
}
