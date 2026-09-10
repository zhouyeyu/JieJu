using System.Net;
using System.Text;
using JieJu.Domain;
using JieJu.Windows.Infrastructure;
using Xunit;

namespace JieJu.Windows.Tests;

public sealed class VocabularyAITests
{
    private static readonly WordExplanationRequest Request = new()
    {
        SelectedText = "bank", SentenceContext = "They sat on the bank of the river.",
        SourceLanguage = "English", ExplanationLanguage = "Chinese"
    };

    [Fact]
    public void ValidationRejectsAWordOutsideTheSentence()
    {
        Assert.Throws<ArgumentException>(() => WordExplanationValidation.Normalize(Request with { SelectedText = "train" }));
    }

    [Fact]
    public void ValidationRejectsEnglishMeaningWhenChineseWasRequested()
    {
        const string json = "{\"surface\":\"bank\",\"lemma\":\"bank\",\"reading\":null,\"partOfSpeech\":\"noun\",\"contextualMeaning\":\"river edge\",\"briefMeaning\":\"bank\",\"inflection\":null,\"collocations\":[]}";
        Assert.Throws<System.Text.Json.JsonException>(() => WordExplanationValidation.Parse(json, Request));
    }

    [Fact]
    public async Task OllamaVocabularyReturnsAContextualMeaning()
    {
        const string content = "{\"surface\":\"bank\",\"lemma\":\"bank\",\"reading\":null,\"partOfSpeech\":\"noun\",\"contextualMeaning\":\"河岸\",\"briefMeaning\":\"岸；银行\",\"inflection\":null,\"collocations\":[]}";
        var handler = new StubHandler("{\"message\":{\"content\":" + System.Text.Json.JsonSerializer.Serialize(content) + "}}");
        using var http = new HttpClient(handler);

        var result = await new OllamaVocabularyAI(http, "http://127.0.0.1:11434", "test").ExplainWordAsync(Request);

        Assert.Equal("河岸", result.ContextualMeaning);
        Assert.Contains("\"stream\":false", handler.Body);
        Assert.Contains("\"temperature\":0", handler.Body);
    }

    private sealed class StubHandler(string response) : HttpMessageHandler
    {
        public string Body { get; private set; } = "";
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(response, Encoding.UTF8, "application/json") };
        }
    }
}
