using System.Runtime.CompilerServices;
using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public sealed class SmokeReadingAI : IStreamingReadingAI, IVocabularyAI
{
    public Task<Explanation> ExplainAsync(ExplanationRequest request, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(Result(request));
    }

    public async IAsyncEnumerable<ExplanationProgress> ExplainStreamAsync(
        ExplanationRequest request,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await Task.Yield();
        yield return new ExplanationProgress("mock", Result: Result(request));
    }

    public Task<WordExplanation> ExplainWordAsync(WordExplanationRequest request, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(new WordExplanation
        {
            Surface = request.SelectedText,
            Lemma = request.SelectedText,
            PartOfSpeech = "mock",
            ContextualMeaning = "离线测试词义",
            BriefMeaning = "离线测试词义",
            Collocations = []
        });
    }

    private static Explanation Result(ExplanationRequest request) => new()
    {
        Translation = "离线测试译文",
        SentenceCore = request.TargetText,
        GrammarPoints = [],
        KeyPhrases = []
    };
}
