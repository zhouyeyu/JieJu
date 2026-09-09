import Foundation
import CoreGraphics
import NaturalLanguage

#if canImport(JieJuLanguage)
import JieJuLanguage
typealias ReaderExplanationRequest = JieJuLanguage.ExplanationRequest
#else
struct ReaderExplanationRequest: Codable, Equatable, Sendable {
    let targetText: String
    let precedingContext: String?
    let followingContext: String?
    let sourceLanguage: String
    let explanationLanguage: String
}
#endif

enum ReaderDocumentState: Equatable {
    case empty
    case loading(URL)
    case loaded(ReaderDocumentMetadata)
    case failed(ReaderDocumentError)
}

struct ReaderDocumentMetadata: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case pdf, epub }

    let url: URL
    let pageCount: Int
    let kind: Kind

    var displayName: String { url.lastPathComponent }
}

struct EPUBReadingStyle: Equatable, Sendable {
    var fontSize: Double = 18
    var lineHeight: Double = 1.75
    var horizontalMargin: Double = 54
    var showsFurigana = false
    var theme: EPUBReaderTheme = .paper
}

enum EPUBReaderTheme: String, CaseIterable, Identifiable, Sendable {
    case paper
    case night
    case sepia
    case sage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "白纸"
        case .night: "夜间"
        case .sepia: "羊皮纸"
        case .sage: "护眼绿"
        }
    }

    var backgroundCSS: String {
        switch self {
        case .paper: "#FAFAF8"
        case .night: "#16181D"
        case .sepia: "#F4ECD8"
        case .sage: "#DDE8D5"
        }
    }

    var foregroundCSS: String {
        switch self {
        case .paper: "#1C1C1E"
        case .night: "#F2F2F4"
        case .sepia: "#332B22"
        case .sage: "#223028"
        }
    }

    var linkCSS: String {
        switch self {
        case .paper: "#315F9D"
        case .night: "#8AB4F8"
        case .sepia: "#76552D"
        case .sage: "#356859"
        }
    }
}

enum ReaderDocumentError: LocalizedError, Equatable, Sendable {
    case fileUnavailable
    case unreadableFile
    case invalidPDF
    case invalidEPUB(String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .fileUnavailable:
            return "找不到所选文档。"
        case .unreadableFile:
            return "没有权限读取所选文档。"
        case .invalidPDF:
            return "无法打开这个文件。请确认它是有效的 PDF。"
        case .invalidEPUB(let message):
            return "无法打开这个 EPUB：\(message)"
        case .unsupportedFormat:
            return "目前只支持 PDF 和 EPUB 文件。"
        }
    }
}

struct ReaderSelection: Equatable, Sendable {
    let targetText: String
    let containingSentence: String?
    let precedingContext: String?
    let followingContext: String?
    /// Selection bounds in the PDF view's coordinate space.
    let anchorRect: CGRect
    let locator: DocumentLocator?

    init(
        targetText: String,
        containingSentence: String? = nil,
        precedingContext: String? = nil,
        followingContext: String? = nil,
        anchorRect: CGRect,
        locator: DocumentLocator? = nil
    ) {
        self.targetText = targetText
        self.containingSentence = containingSentence
        self.precedingContext = precedingContext
        self.followingContext = followingContext
        self.anchorRect = anchorRect
        self.locator = locator
    }

    func explanationRequest(
        targetText override: String? = nil,
        sourceLanguage: String = "English",
        explanationLanguage: String = "Chinese"
    ) -> ReaderExplanationRequest {
        ReaderExplanationRequest(
            targetText: override ?? targetText,
            precedingContext: precedingContext,
            followingContext: followingContext,
            sourceLanguage: sourceLanguage,
            explanationLanguage: explanationLanguage
        )
    }
}

enum ReaderSelectionKind: String, Equatable, Sendable {
    case word
    case expression
    case sentence
    case passage
    case ambiguous

    var actionTitle: String {
        switch self {
        case .word: "查这个词"
        case .expression: "解释这个表达"
        case .sentence: "解读这句话"
        case .passage: "理解这段文字"
        case .ambiguous: "解释所选内容"
        }
    }

    var panelTitle: String {
        switch self {
        case .word: "词语解释"
        case .expression: "表达解释"
        case .sentence: "解句"
        case .passage: "选段理解"
        case .ambiguous: "内容解释"
        }
    }

    var canSaveSelectionAsVocabulary: Bool {
        self == .word || self == .expression
    }
}

enum ReaderSelectionClassifier {
    static let japaneseMorphology: (any JapaneseMorphologyProviding)? =
        try? MeCabJapaneseReadingProvider()

    static func classify(_ text: String, sourceLanguage: String) -> ReaderSelectionKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .ambiguous }

        let terminatorCount = trimmed.filter { ".!?。！？".contains($0) }.count
        if terminatorCount >= 2 { return .passage }
        if terminatorCount == 1 { return .sentence }

        if sourceLanguage.localizedCaseInsensitiveContains("Japanese") {
            return classifyJapanese(trimmed)
        }
        return classifyWithNaturalLanguage(trimmed, sourceLanguage: sourceLanguage)
    }

    private static func classifyJapanese(_ text: String) -> ReaderSelectionKind {
        guard let provider = japaneseMorphology else {
            return text.count <= 6 ? .ambiguous : .sentence
        }
        let tokens = provider.tokens(for: text).filter { $0.partOfSpeech != "symbol" }
        guard !tokens.isEmpty else { return .ambiguous }

        let nouns = tokens.filter { $0.partOfSpeech == "noun" }.count
        let predicates = tokens.filter {
            $0.partOfSpeech == "verb" || $0.partOfSpeech == "adjective"
        }.count
        let lexical = tokens.filter {
            ["noun", "verb", "adjective", "adverb"].contains($0.partOfSpeech)
        }.count
        let hasParticle = tokens.contains { $0.partOfSpeech == "particle" }

        if tokens.count == 1, lexical == 1 { return .word }
        if lexical == 1 {
            // 活用尾缀不会被当作独立词；助词则说明用户选中了一个表达片段。
            return hasParticle ? .expression : .word
        }
        if predicates > 0, nouns > 0 { return .sentence }
        if lexical >= 3 { return .ambiguous }
        if hasParticle || lexical == 2 { return .expression }
        return .ambiguous
    }

    private static func classifyWithNaturalLanguage(
        _ text: String,
        sourceLanguage: String
    ) -> ReaderSelectionKind {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        if let language = naturalLanguage(for: sourceLanguage) { tokenizer.setLanguage(language) }
        let ranges = tokenizer.tokens(for: text.startIndex..<text.endIndex)
        guard !ranges.isEmpty else { return .ambiguous }
        if ranges.count == 1 { return .word }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        if let language = naturalLanguage(for: sourceLanguage) {
            tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        }
        var tags: [NLTag] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, _ in
            if let tag { tags.append(tag) }
            return true
        }

        let hasSubjectLike = tags.contains {
            [.noun, .pronoun, .personalName, .placeName, .organizationName].contains($0)
        }
        let hasPredicate = tags.contains { $0 == .verb }
        if hasSubjectLike, hasPredicate { return .sentence }
        if ranges.count <= 5 { return .expression }
        if ranges.count >= 8 { return .sentence }
        return .ambiguous
    }

    private static func naturalLanguage(for name: String) -> NLLanguage? {
        if name.localizedCaseInsensitiveContains("Chinese") { return .simplifiedChinese }
        if name.localizedCaseInsensitiveContains("Japanese") { return .japanese }
        if name.localizedCaseInsensitiveContains("Korean") { return .korean }
        if name.localizedCaseInsensitiveContains("French") { return .french }
        if name.localizedCaseInsensitiveContains("German") { return .german }
        return .english
    }
}

struct ReaderSelectionBoundarySuggestion: Equatable, Sendable {
    let originalText: String
    let suggestedText: String
}

enum ReaderSelectionBoundarySuggester {
    static func suggestion(
        for selectedText: String,
        in sentence: String?,
        sourceLanguage: String
    ) -> ReaderSelectionBoundarySuggestion? {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, let sentence, sentence != selected,
              let selectedRange = uniqueRange(of: selected, in: sentence) else { return nil }

        let tokenRanges: [(text: String, range: Range<String.Index>)]
        if sourceLanguage.localizedCaseInsensitiveContains("Japanese") {
            guard let provider = ReaderSelectionClassifier.japaneseMorphology else { return nil }
            tokenRanges = ranges(for: provider.tokens(for: sentence).map(\.surface), in: sentence)
        } else {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = sentence
            tokenRanges = tokenizer.tokens(for: sentence.startIndex..<sentence.endIndex).map {
                (String(sentence[$0]), $0)
            }
        }

        guard let token = tokenRanges.first(where: {
            $0.range.lowerBound <= selectedRange.lowerBound &&
            $0.range.upperBound >= selectedRange.upperBound &&
            $0.range != selectedRange
        }) else { return nil }
        let suggested = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard suggested.count > selected.count else { return nil }
        return .init(originalText: selected, suggestedText: suggested)
    }

    private static func uniqueRange(of needle: String, in text: String) -> Range<String.Index>? {
        var result: Range<String.Index>?
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let range = text.range(of: needle, range: cursor..<text.endIndex) {
            if result != nil { return nil }
            result = range
            cursor = range.upperBound
        }
        return result
    }

    private static func ranges(
        for tokenSurfaces: [String],
        in text: String
    ) -> [(text: String, range: Range<String.Index>)] {
        var cursor = text.startIndex
        var result: [(text: String, range: Range<String.Index>)] = []
        for surface in tokenSurfaces where !surface.isEmpty {
            guard cursor < text.endIndex,
                  let range = text.range(of: surface, range: cursor..<text.endIndex) else { continue }
            result.append((surface, range))
            cursor = range.upperBound
        }
        return result
    }
}

struct ReaderExplanation: Equatable, Sendable {
    let translation: String
    let sentenceCore: String
    let grammarPoints: [String]
    let keyPhrases: [ReaderKeyPhrase]
}

struct ReaderKeyPhrase: Equatable, Sendable {
    let text: String
    let meaning: String
}

struct ReaderSentenceComponent: Equatable, Sendable {
    let text: String
    let role: String
    let explanation: String
    let modifies: String?
}

struct ReaderClauseExplanation: Equatable, Sendable {
    let text: String
    let type: String
    let function: String
    let explanation: String
}

struct ReaderDeepAnalysis: Equatable, Sendable {
    let sentenceType: String
    let sentencePattern: String
    let components: [ReaderSentenceComponent]
    let clauses: [ReaderClauseExplanation]
    let grammarPoints: [String]
    let interpretation: String
    let japaneseWords: [ReaderJapaneseWord]
}

struct ReaderJapaneseWord: Equatable, Sendable {
    let text: String
    let baseForm: String
    let reading: String
    let inflectionType: String
    let grammaticalFunction: String
}

struct ReaderSavePayload: Sendable {
    let documentURL: URL
    let pageIndex: Int
    let locator: DocumentLocator?
    let selection: ReaderSelection
    let explanation: ReaderExplanation
    let sourceLanguage: String
    let explanationLanguage: String
}

struct ReaderVocabularyCandidate: Equatable, Sendable {
    let surface: String
    let lemma: String
    let reading: String?
    let partOfSpeech: String?
    let meaning: String

    var stableKey: String {
        "\(lemma.lowercased())|\((reading ?? "").lowercased())"
    }
}

struct ReaderWordExplanation: Equatable, Sendable {
    let surface: String
    let lemma: String
    let reading: String?
    let partOfSpeech: String
    let contextualMeaning: String
    let briefMeaning: String
    let inflection: String?
    let collocations: [ReaderKeyPhrase]

    var vocabularyCandidate: ReaderVocabularyCandidate {
        .init(
            surface: surface,
            lemma: lemma,
            reading: reading,
            partOfSpeech: partOfSpeech,
            meaning: contextualMeaning
        )
    }
}

enum ReaderWordExplanationState: Equatable, Sendable {
    case idle
    case loading
    case streaming(ReaderWordExplanation)
    case loaded(ReaderWordExplanation)
    case failed(String)
}

struct ReaderVocabularySavePayload: Sendable {
    let documentURL: URL
    let pageIndex: Int
    let locator: DocumentLocator?
    let sentence: String
    let sourceLanguage: String
    let explanationLanguage: String
    let candidate: ReaderVocabularyCandidate
}

struct ReaderSourceNavigation: Equatable, Sendable {
    let id: UUID
    let document: DocumentIdentity
    let locator: DocumentLocator?
    let legacyPageIndex: Int?

    init(
        id: UUID = UUID(),
        document: DocumentIdentity,
        locator: DocumentLocator?,
        legacyPageIndex: Int?
    ) {
        self.id = id
        self.document = document
        self.locator = locator
        self.legacyPageIndex = legacyPageIndex
    }
}

enum ReaderExplanationState: Equatable, Sendable {
    case idle
    case loading
    case streaming(ReaderExplanation)
    case loaded(ReaderExplanation)
    case failed(String)
}

enum ReaderSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved
    case failed(String)
}

protocol ReaderExplanationProviding: Sendable {
    func explain(_ request: ReaderExplanationRequest) async throws -> ReaderExplanation
    func explanationStream(_ request: ReaderExplanationRequest) async throws -> AsyncThrowingStream<ReaderExplanation, Error>
    func analyzeDeep(_ request: ReaderExplanationRequest) async throws -> ReaderDeepAnalysis
}

protocol ReaderVocabularyProviding: Sendable {
    func explainWord(_ request: WordExplanationRequest) async throws -> ReaderWordExplanation
    func wordExplanationStream(
        _ request: WordExplanationRequest
    ) async throws -> AsyncThrowingStream<ReaderWordExplanation, Error>
}

extension ReaderVocabularyProviding {
    func wordExplanationStream(
        _ request: WordExplanationRequest
    ) async throws -> AsyncThrowingStream<ReaderWordExplanation, Error> {
        let result = try await explainWord(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(result)
            continuation.finish()
        }
    }
}

extension ReaderExplanationProviding {
    func explanationStream(_ request: ReaderExplanationRequest) async throws -> AsyncThrowingStream<ReaderExplanation, Error> {
        let result = try await explain(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(result)
            continuation.finish()
        }
    }

    func analyzeDeep(_ request: ReaderExplanationRequest) async throws -> ReaderDeepAnalysis {
        throw ReadingAIError.invalidResponse("当前解释服务不支持深入解析")
    }
}

struct MockReaderExplanationProvider: ReaderExplanationProviding {
    func explain(_ request: ReaderExplanationRequest) async throws -> ReaderExplanation {
        ReaderExplanation(
            translation: "这是“\(request.targetText)”的示例翻译。",
            sentenceCore: request.targetText,
            grammarPoints: ["Mock：这里将展示句子的语法结构。"],
            keyPhrases: [.init(text: request.targetText, meaning: "Mock：这里将展示重点表达。")]
        )
    }

    func analyzeDeep(_ request: ReaderExplanationRequest) async throws -> ReaderDeepAnalysis {
        ReaderDeepAnalysis(
            sentenceType: "Mock 句子类型",
            sentencePattern: "S + V",
            components: [.init(text: request.targetText, role: "完整句", explanation: "Mock 成分说明", modifies: nil)],
            clauses: [], grammarPoints: ["Mock 深度语法说明"], interpretation: "Mock 整句理解",
            japaneseWords: []
        )
    }
}

struct MockReaderVocabularyProvider: ReaderVocabularyProviding {
    func explainWord(_ request: WordExplanationRequest) async throws -> ReaderWordExplanation {
        let result = try await MockVocabularyAI().explainWord(request)
        return .init(
            surface: result.surface,
            lemma: result.lemma,
            reading: result.reading,
            partOfSpeech: result.partOfSpeech,
            contextualMeaning: result.contextualMeaning,
            briefMeaning: result.briefMeaning,
            inflection: result.inflection,
            collocations: result.collocations.map { .init(text: $0.text, meaning: $0.meaning) }
        )
    }
}

enum ReaderDeepAnalysisState: Equatable, Sendable {
    case idle
    case loading
    case loaded(ReaderDeepAnalysis)
    case failed(String)
}
