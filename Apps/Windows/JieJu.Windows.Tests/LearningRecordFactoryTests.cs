using JieJu.Domain;
using Xunit;

namespace JieJu.Windows.Tests;

public sealed class LearningRecordFactoryTests
{
    private static readonly Document Pdf = new("pdf-id", "book.pdf");
    private static readonly PdfLocator Locator = new(12, 48, new string('a', 64));
    private static readonly ExplanationRequest Request = new()
    {
        TargetText = "The tower was white.",
        SourceLanguage = "English",
        ExplanationLanguage = "Chinese"
    };

    [Fact]
    public void CreatesPdfExplanationWithItsSourcePage()
    {
        var at = DateTimeOffset.Parse("2026-09-16T00:00:00Z");
        var result = new Explanation
        {
            Translation = "那座塔是白色的。",
            SentenceCore = "tower was white",
            GrammarPoints = [new("was", "一般过去时")],
            KeyPhrases = [new("white tower", "白塔")]
        };

        var record = LearningRecordFactory.Explanation(Pdf, Request, result, "local-model", Locator, at);

        Assert.Equal(Pdf, record.Document);
        Assert.Equal(Locator, Assert.IsType<PdfLocator>(record.Locator));
        Assert.Equal("was", record.Explanation.GrammarPoints[0].Title);
        Assert.Equal("local-model", record.Explanation.ModelName);
        Assert.Equal(at, record.CreatedAt);
    }

    [Fact]
    public void CreatesPdfVocabularyWithSentenceAndLocator()
    {
        var at = DateTimeOffset.Parse("2026-09-16T00:00:00Z");
        var result = new WordExplanation
        {
            Surface = "tower",
            Lemma = "tower",
            PartOfSpeech = "noun",
            ContextualMeaning = "塔",
            BriefMeaning = "高塔",
            Collocations = []
        };

        var entry = LearningRecordFactory.Vocabulary(Pdf, Request, Request.TargetText, result, Locator, at);

        var source = Assert.Single(entry.Sources);
        Assert.Equal(Pdf, source.Document);
        Assert.Equal(Request.TargetText, source.Sentence);
        Assert.Equal(Locator, Assert.IsType<PdfLocator>(source.Locator));
        Assert.Equal("塔", Assert.Single(entry.Senses).Meaning);
    }
}
