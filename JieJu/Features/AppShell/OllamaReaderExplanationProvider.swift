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

    func explanationStream(_ request: ReaderExplanationRequest) async throws -> AsyncThrowingStream<ReaderExplanation, Error> {
        let stream = try await OllamaReadingAI(baseURL: baseURL, model: model).explanationStream(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await result in stream {
                        continuation.yield(Self.readerExplanation(result))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func analyzeDeep(_ request: ReaderExplanationRequest) async throws -> ReaderDeepAnalysis {
        let result = try await OllamaReadingAI(baseURL: baseURL, model: model).analyzeDeep(request)
        return ReaderDeepAnalysis(
            sentenceType: result.sentenceType,
            sentencePattern: result.sentencePattern,
            components: result.components.map {
                .init(text: $0.text, role: $0.role, explanation: $0.explanation, modifies: $0.modifies)
            },
            clauses: result.clauses.map {
                .init(text: $0.text, type: $0.type, function: $0.function, explanation: $0.explanation)
            },
            grammarPoints: result.grammarPoints.map { "\($0.text)：\($0.explanation)" },
            interpretation: result.interpretation,
            japaneseWords: (result.japaneseWords ?? []).map {
                .init(text: $0.text, baseForm: $0.baseForm, reading: $0.reading,
                      inflectionType: $0.inflectionType, grammaticalFunction: $0.grammaticalFunction)
            }
        )
    }

    private static func readerExplanation(_ result: Explanation) -> ReaderExplanation {
        ReaderExplanation(
            translation: result.translation,
            sentenceCore: result.sentenceCore,
            grammarPoints: result.grammarPoints.map { "\($0.text)：\($0.explanation)" },
            keyPhrases: result.keyPhrases.map { "\($0.text)：\($0.meaning)" }
        )
    }
}
