using JieJu.Domain;
using JieJu.Windows.Infrastructure;
using Xunit;

namespace JieJu.Windows.Tests;

public sealed class JapaneseMorphologyTests
{
    [Fact]
    public void IPADicProvidesReadingLemmaPartOfSpeechAndInflection()
    {
        using var morphology = new MeCabJapaneseMorphology();

        var tokens = morphology.Tokenize("彼女は本を読んでいます。");

        Assert.Contains(tokens, token => token.Surface == "彼女" && token.Reading == "かのじょ" && token.PartOfSpeech == "noun");
        Assert.Contains(tokens, token => token.Surface == "読ん" && token.DictionaryForm == "読む" && token.PartOfSpeech == "verb" && token.IsInflected);
        Assert.DoesNotContain(morphology.ReadingSegments("かなだけ"), segment => segment.Reading is not null);
    }

    [Fact]
    public void JapaneseBoundaryUsesMorphologicalToken()
    {
        using var morphology = new MeCabJapaneseMorphology();

        var result = SelectionClassifier.SuggestBoundary("行機", "その飛行機は降下した。", "ja", morphology);

        Assert.Equal("飛行機", result?.SuggestedText);
    }

    [Fact]
    public async Task VocabularyUsesLocalDictionaryFacts()
    {
        using var morphology = new MeCabJapaneseMorphology();
        var request = new WordExplanationRequest
        {
            SelectedText = "読んだ", SentenceContext = "昨日、本を読んだ。", SourceLanguage = "Japanese", ExplanationLanguage = "Chinese"
        };
        var provider = new LocalJapaneseVocabularyAI(new StubVocabularyAI(), morphology);

        var result = await provider.ExplainWordAsync(request);

        Assert.Equal("読むだ", result.Lemma);
        Assert.Equal("よんだ", result.Reading);
        Assert.Equal("verb / auxiliary", result.PartOfSpeech);
        Assert.Contains("読ん → 読む", result.Inflection);
    }

    private sealed class StubVocabularyAI : IVocabularyAI
    {
        public Task<WordExplanation> ExplainWordAsync(WordExplanationRequest request, CancellationToken cancellationToken = default) =>
            Task.FromResult(new WordExplanation
            {
                Surface = request.SelectedText, Lemma = "wrong", Reading = "wrong", PartOfSpeech = "wrong",
                ContextualMeaning = "阅读", BriefMeaning = "读", Inflection = "wrong", Collocations = []
            });
    }
}
