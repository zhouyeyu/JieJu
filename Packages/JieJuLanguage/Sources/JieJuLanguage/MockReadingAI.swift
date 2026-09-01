public struct MockReadingAI: ReadingAI {
    public init() {}

    public func explain(_ request: ExplanationRequest) async throws -> Explanation {
        _ = try request.validated()
        return Explanation(
            translation: "模拟翻译：\(request.targetText)",
            sentenceCore: "模拟句子主干",
            grammarPoints: [.init(text: "mock grammar", explanation: "用于可重复测试的语法说明")],
            keyPhrases: [.init(text: request.targetText, meaning: "模拟重点表达")]
        )
    }
}
