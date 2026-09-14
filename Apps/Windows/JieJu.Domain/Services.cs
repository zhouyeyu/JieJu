namespace JieJu.Domain;

public interface IReadingAI
{
    Task<Explanation> ExplainAsync(ExplanationRequest request, CancellationToken cancellationToken = default);
}

public sealed record ExplanationPreview(string? Translation, string? SentenceCore, GrammarPoint[] GrammarPoints, KeyPhrase[] KeyPhrases);
public sealed record ExplanationProgress(string GeneratedText, Explanation? Result = null, ExplanationPreview? Preview = null);

public interface IStreamingReadingAI : IReadingAI
{
    IAsyncEnumerable<ExplanationProgress> ExplainStreamAsync(ExplanationRequest request, CancellationToken cancellationToken = default);
}

public interface IDeepReadingAI
{
    Task<DeepAnalysis> AnalyzeDeepAsync(ExplanationRequest request, CancellationToken cancellationToken = default);
}

public interface IVocabularyAI
{
    Task<WordExplanation> ExplainWordAsync(WordExplanationRequest request, CancellationToken cancellationToken = default);
}

public interface ILearningLibraryStore
{
    Task<LearningLibrary> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(LearningLibrary library, CancellationToken cancellationToken = default);
}
