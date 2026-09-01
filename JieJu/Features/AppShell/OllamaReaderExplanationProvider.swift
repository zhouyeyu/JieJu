import Foundation
import JieJuLanguage

struct OllamaReaderExplanationProvider: ReaderExplanationProviding {
    let baseURL: URL
    let model: String

    func explain(_ request: ReaderExplanationRequest) async throws -> ReaderExplanation {
        let result = try await OllamaReadingAI(baseURL: baseURL, model: model).explain(request)
        return ReaderExplanation(
            translation: result.translation,
            sentenceCore: result.sentenceCore,
            grammarPoints: result.grammarPoints.map { "\($0.text)：\($0.explanation)" },
            keyPhrases: result.keyPhrases.map { "\($0.text)：\($0.meaning)" }
        )
    }
}

