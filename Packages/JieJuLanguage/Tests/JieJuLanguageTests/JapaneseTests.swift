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

    @Test func JapaneseFragmentsUseUnspacedMatching() throws {
        let request = ExplanationRequest(targetText: "私は本を読みます。", sourceLanguage: "Japanese")
        let explanation = Explanation(
            translation: "我读书。", sentenceCore: "読みます",
            grammarPoints: [.init(text: "読みます", explanation: "礼貌体")],
            keyPhrases: [.init(text: "本", meaning: "书")]
        )
        #expect(try explanation.validated(against: request) == explanation)
    }
}
