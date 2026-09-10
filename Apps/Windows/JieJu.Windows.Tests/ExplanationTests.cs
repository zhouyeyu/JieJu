using System.Net;
using System.Text;
using System.Text.Json;
using JieJu.Domain;
using JieJu.Windows.Infrastructure;
using Xunit;

namespace JieJu.Windows.Tests;

public sealed class ExplanationTests
{
    private static readonly ExplanationRequest Request = new() { TargetText = "  She   opened the book. ", PrecedingContext = "Before.", SourceLanguage = "English", ExplanationLanguage = "Chinese" };

    [Fact]
    public void NormalizesWhitespaceAndRejectsEmptySelection()
    {
        Assert.Equal("She opened the book.", ExplanationValidation.Normalize(Request).TargetText);
        Assert.Throws<ArgumentException>(() => ExplanationValidation.Normalize(Request with { TargetText = " \n " }));
    }

    [Fact]
    public void ParsesFencedResultAndDropsContextLeakWithoutLosingTheExplanation()
    {
        const string valid = "```json\n{\"translation\":\"她打开了书。\",\"sentenceCore\":\"She opened the book.\",\"grammarPoints\":[{\"text\":\"opened\",\"explanation\":\"过去式\"}],\"keyPhrases\":[]}\n```";
        Assert.Equal("她打开了书。", ExplanationValidation.Parse(valid, ExplanationValidation.Normalize(Request)).Translation);
        var cleaned = ExplanationValidation.Parse(valid.Replace("opened\",", "Before\","), ExplanationValidation.Normalize(Request));
        Assert.Empty(cleaned.GrammarPoints);
    }

    [Fact]
    public void RejectsEnglishTranslationWhenChineseWasRequested()
    {
        const string invalid = "{\"translation\":\"She opened the book.\",\"sentenceCore\":\"She opened the book.\",\"grammarPoints\":[],\"keyPhrases\":[]}";
        Assert.Throws<JsonException>(() => ExplanationValidation.Parse(invalid, ExplanationValidation.Normalize(Request)));
    }

    [Fact]
    public void PartialParserPublishesCompletedSectionsAndDropsOutsideReferences()
    {
        const string partial = "{\"translation\":\"她打开了书。\",\"sentenceCore\":\"She opened the book.\",\"grammarPoints\":[{\"text\":\"opened\",\"explanation\":\"过去式\"},{\"text\":\"Before\",\"explanation\":\"越界\"}],\"keyPhrases\":[";
        var preview = PartialExplanationParser.Parse(partial, ExplanationValidation.Normalize(Request));
        Assert.Equal("她打开了书。", preview?.Translation);
        Assert.Equal("She opened the book.", preview?.SentenceCore);
        Assert.Equal("opened", Assert.Single(preview!.GrammarPoints).Text);
        Assert.Empty(preview.KeyPhrases);
    }

    [Fact]
    public async Task OllamaClientStreamsNdjsonAndReturnsValidatedResult()
    {
        var lines = "{\"message\":{\"content\":\"{\\\"translation\\\":\\\"她打开了书。\\\",\\\"sentenceCore\\\":\\\"She opened the book.\\\",\"}}\n" +
                    "{\"message\":{\"content\":\"\\\"grammarPoints\\\":[],\\\"keyPhrases\\\":[]}\"},\"done\":true}\n";
        var handler = new StubHandler(lines); using var http = new HttpClient(handler);
        var ai = new OllamaReadingAI(http, "http://127.0.0.1:11434", "test-model");
        var updates = new List<ExplanationProgress>();
        await foreach (var update in ai.ExplainStreamAsync(Request)) updates.Add(update);
        Assert.Equal("她打开了书。", updates.Last().Result!.Translation);
        Assert.Contains(updates, update => update.Preview?.Translation == "她打开了书。");
        Assert.Contains("\"stream\":true", handler.Body);
        Assert.Contains("\"temperature\":0", handler.Body);
    }

    [Fact]
    public async Task OllamaClientReplacesAnInvalidCoreWithTheSelectedText()
    {
        var invalid = "{\"message\":{\"content\":\"{\\\"translation\\\":\\\"译文\\\",\\\"sentenceCore\\\":\\\"Before.\\\",\\\"grammarPoints\\\":[],\\\"keyPhrases\\\":[]}\"},\"done\":true}\n";
        var repaired = "{\"message\":{\"content\":\"{\\\"translation\\\":\\\"她打开了书。\\\",\\\"sentenceCore\\\":\\\"She opened the book.\\\",\\\"grammarPoints\\\":[],\\\"keyPhrases\\\":[]}\"},\"done\":true}\n";
        var handler = new StubHandler(invalid, repaired); using var http = new HttpClient(handler);
        var result = await new OllamaReadingAI(http, "http://127.0.0.1:11434", "test-model").ExplainAsync(Request);
        Assert.Equal("译文", result.Translation);
        Assert.Equal("She opened the book.", result.SentenceCore);
        Assert.Equal(1, handler.RequestCount);
    }

    private sealed class StubHandler(params string[] responses) : HttpMessageHandler
    {
        public string Body { get; private set; } = "";
        public int RequestCount { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            var response = responses[Math.Min(RequestCount, responses.Length - 1)]; RequestCount++;
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(response, Encoding.UTF8) };
        }
    }
}
