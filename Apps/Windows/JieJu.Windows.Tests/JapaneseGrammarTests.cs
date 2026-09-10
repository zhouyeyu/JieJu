using JieJu.Domain;
using JieJu.Windows.Infrastructure;
using System.Runtime.CompilerServices;
using Xunit;

namespace JieJu.Windows.Tests;

public sealed class JapaneseGrammarTests
{
    [Fact]
    public void LocalAnalysisExplainsParticlesPredicateAndDictionaryFacts()
    {
        using var morphology = new MeCabJapaneseMorphology();
        var request = Request("彼女は本を読んでいます。");

        var result = JapaneseGrammarAnalyzer.LocalAnalysis(request, morphology);

        Assert.Equal("日语句", result.SentenceType);
        Assert.Contains("主题(彼女は)", result.SentencePattern);
        Assert.Contains("宾语(本を)", result.SentencePattern);
        Assert.Contains("谓语(読んでいます。)", result.SentencePattern);
        Assert.Contains(result.GrammarPoints, point => point.Text == "は" && point.Explanation.Contains("主题"));
        Assert.Contains(result.GrammarPoints, point => point.Text == "でいます" && point.Explanation.Contains("进行"));
        Assert.Contains(result.JapaneseWords!, word => word.Text == "読ん" && word.BaseForm == "読む" && word.Reading == "よん");
    }

    [Fact]
    public void LocalAnalysisDistinguishesAgeConnectorAndPastJustCompletedForm()
    {
        using var morphology = new MeCabJapaneseMorphology();
        var age = JapaneseGrammarAnalyzer.LocalAnalysis(Request("彼女は十八で、卒業したばかりだった。"), morphology);

        Assert.Contains(age.GrammarPoints, point => point.Text == "で" && point.Explanation.Contains("不是表示场所"));
        Assert.Contains(age.GrammarPoints, point => point.Text == "たばかり");
        Assert.Contains("年龄状态／连接(十八で)", age.SentencePattern);
    }

    [Fact]
    public async Task JapaneseDeepAnalysisDoesNotCallTheModel()
    {
        using var morphology = new MeCabJapaneseMorphology();
        var inner = new ThrowingReadingAI();
        var provider = new LocalJapaneseReadingAI(inner, morphology);

        var result = await provider.AnalyzeDeepAsync(Request("本を読みます。"));

        Assert.Equal("日语句", result.SentenceType);
        Assert.False(inner.Called);
    }

    private static ExplanationRequest Request(string text) => new()
    {
        TargetText = text, SourceLanguage = "Japanese", ExplanationLanguage = "Chinese"
    };

    private sealed class ThrowingReadingAI : IStreamingReadingAI, IDeepReadingAI
    {
        public bool Called { get; private set; }
        public Task<Explanation> ExplainAsync(ExplanationRequest request, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public async IAsyncEnumerable<ExplanationProgress> ExplainStreamAsync(ExplanationRequest request, [EnumeratorCancellation] CancellationToken cancellationToken = default) { await Task.CompletedTask; yield break; }
        public Task<DeepAnalysis> AnalyzeDeepAsync(ExplanationRequest request, CancellationToken cancellationToken = default) { Called = true; throw new NotSupportedException(); }
    }
}
