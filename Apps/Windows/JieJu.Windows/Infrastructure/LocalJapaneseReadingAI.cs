using System.Runtime.CompilerServices;
using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public sealed class LocalJapaneseReadingAI(IStreamingReadingAI inner, IJapaneseMorphology morphology) : IStreamingReadingAI, IDeepReadingAI
{
    public Task<Explanation> ExplainAsync(ExplanationRequest request, CancellationToken cancellationToken = default) =>
        inner.ExplainAsync(request, cancellationToken);

    public async IAsyncEnumerable<ExplanationProgress> ExplainStreamAsync(ExplanationRequest request, [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        await foreach (var progress in inner.ExplainStreamAsync(request, cancellationToken)) yield return progress;
    }

    public Task<DeepAnalysis> AnalyzeDeepAsync(ExplanationRequest request, CancellationToken cancellationToken = default)
    {
        if (JapaneseLanguage.IsJapanese(request.SourceLanguage, request.TargetText))
            return Task.FromResult(JapaneseGrammarAnalyzer.LocalAnalysis(request, morphology));
        return inner is IDeepReadingAI deep
            ? deep.AnalyzeDeepAsync(request, cancellationToken)
            : Task.FromException<DeepAnalysis>(new NotSupportedException("当前解释服务不支持深入解析。"));
    }
}
