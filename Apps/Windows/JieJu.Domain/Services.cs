namespace JieJu.Domain;

public interface IReadingAI
{
    Task<Explanation> ExplainAsync(ExplanationRequest request, CancellationToken cancellationToken = default);
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
