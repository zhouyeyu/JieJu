using System.Net;
using System.Text;
using System.Text.Json;
using JieJu.Domain;
using JieJu.Windows.Infrastructure;
using Xunit;

namespace JieJu.Windows.Tests;

public sealed class OpenAICompatibleTests
{
    private static readonly ExplanationRequest Request = new()
    {
        TargetText = "She reads.", SourceLanguage = "English", ExplanationLanguage = "Chinese"
    };

    [Fact]
    public async Task StreamsAuthorizedChatCompletionAndProducesValidatedResult()
    {
        const string result = "{\"translation\":\"她阅读。\",\"sentenceCore\":\"She reads.\",\"grammarPoints\":[],\"keyPhrases\":[]}";
        var eventJson = JsonSerializer.Serialize(new { choices = new[] { new { delta = new { content = result } } } });
        var handler = new StubHandler("data: " + eventJson + "\n\ndata: [DONE]\n\n", "text/event-stream");
        using var http = new HttpClient(handler);
        var provider = new OpenAICompatibleReadingAI(http, "https://example.test/v1", "secret", "cloud-model");

        var updates = new List<ExplanationProgress>();
        await foreach (var update in provider.ExplainStreamAsync(Request)) updates.Add(update);

        Assert.Equal("她阅读。", updates.Last().Result?.Translation);
        Assert.Equal("Bearer", handler.AuthorizationScheme);
        Assert.Equal("secret", handler.AuthorizationParameter);
        Assert.Equal("https://example.test/v1/chat/completions", handler.Uri);
        Assert.Contains("\"response_format\":{\"type\":\"json_object\"}", handler.Body);
        Assert.Contains("\"stream\":true", handler.Body);
    }

    [Fact]
    public async Task ChecksModelsEndpointWithoutSendingContent()
    {
        var handler = new StubHandler("{}", "application/json");
        using var http = new HttpClient(handler);

        await new OpenAICompatibleReadingAI(http, "https://example.test/v1/", "secret", "model").CheckAvailabilityAsync();

        Assert.Equal(HttpMethod.Get, handler.Method);
        Assert.Equal("https://example.test/v1/models", handler.Uri);
        Assert.Equal("", handler.Body);
    }

    [Fact]
    public async Task VocabularyUsesAuthorizedJsonCompletion()
    {
        const string content = "{\"surface\":\"bank\",\"lemma\":\"bank\",\"reading\":null,\"partOfSpeech\":\"noun\",\"contextualMeaning\":\"河岸\",\"briefMeaning\":\"岸；银行\",\"inflection\":null,\"collocations\":[]}";
        var response = JsonSerializer.Serialize(new { choices = new[] { new { message = new { content } } } });
        var handler = new StubHandler(response, "application/json");
        using var http = new HttpClient(handler);
        var request = new WordExplanationRequest { SelectedText = "bank", SentenceContext = "They sat on the bank.", SourceLanguage = "English", ExplanationLanguage = "Chinese" };

        var result = await new OpenAICompatibleVocabularyAI(http, "https://example.test/v1", "secret", "model").ExplainWordAsync(request);

        Assert.Equal("河岸", result.ContextualMeaning);
        Assert.Equal("secret", handler.AuthorizationParameter);
        Assert.Contains("\"max_tokens\":300", handler.Body);
    }

    [Fact]
    public async Task MissingKeyStopsBeforeAnyNetworkRequest()
    {
        var handler = new StubHandler("{}", "application/json");
        using var http = new HttpClient(handler);
        var provider = new OpenAICompatibleReadingAI(http, "https://example.test/v1", "", "model");

        await Assert.ThrowsAsync<ArgumentException>(() => provider.CheckAvailabilityAsync());

        Assert.Null(handler.Method);
    }

    private sealed class StubHandler(string response, string contentType) : HttpMessageHandler
    {
        public HttpMethod? Method { get; private set; }
        public string Uri { get; private set; } = "";
        public string Body { get; private set; } = "";
        public string? AuthorizationScheme { get; private set; }
        public string? AuthorizationParameter { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Method = request.Method; Uri = request.RequestUri!.ToString();
            Body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(response, Encoding.UTF8, contentType) };
        }
    }
}
