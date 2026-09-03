import Foundation
import CoreGraphics

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
            return "找不到所选 PDF。"
        case .unreadableFile:
            return "没有权限读取所选 PDF。"
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
    let precedingContext: String?
    let followingContext: String?
    /// Selection bounds in the PDF view's coordinate space.
    let anchorRect: CGRect

    func explanationRequest(
        sourceLanguage: String = "English",
        explanationLanguage: String = "Chinese"
    ) -> ReaderExplanationRequest {
        ReaderExplanationRequest(
            targetText: targetText,
            precedingContext: precedingContext,
            followingContext: followingContext,
            sourceLanguage: sourceLanguage,
            explanationLanguage: explanationLanguage
        )
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

struct ReaderVocabularySavePayload: Sendable {
    let documentURL: URL
    let pageIndex: Int
    let sentence: String
    let sourceLanguage: String
    let explanationLanguage: String
    let candidate: ReaderVocabularyCandidate
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

enum ReaderDeepAnalysisState: Equatable, Sendable {
    case idle
    case loading
    case loaded(ReaderDeepAnalysis)
    case failed(String)
}
