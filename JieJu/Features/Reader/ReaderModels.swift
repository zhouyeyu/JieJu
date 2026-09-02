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
    let keyPhrases: [String]
}

struct ReaderSavePayload: Sendable {
    let documentURL: URL
    let pageIndex: Int
    let selection: ReaderSelection
    let explanation: ReaderExplanation
    let sourceLanguage: String
    let explanationLanguage: String
}

enum ReaderExplanationState: Equatable, Sendable {
    case idle
    case loading
    case loaded(ReaderExplanation)
    case failed(String)
}

protocol ReaderExplanationProviding: Sendable {
    func explain(_ request: ReaderExplanationRequest) async throws -> ReaderExplanation
}

struct MockReaderExplanationProvider: ReaderExplanationProviding {
    func explain(_ request: ReaderExplanationRequest) async throws -> ReaderExplanation {
        ReaderExplanation(
            translation: "这是“\(request.targetText)”的示例翻译。",
            sentenceCore: request.targetText,
            grammarPoints: ["Mock：这里将展示句子的语法结构。"],
            keyPhrases: ["Mock：这里将展示重点表达。"]
        )
    }
}
