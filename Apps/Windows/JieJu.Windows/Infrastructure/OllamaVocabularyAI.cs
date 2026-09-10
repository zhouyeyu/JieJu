using System.Net.Http.Json;
using System.Text.Encodings.Web;
using System.Text.Json;
using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public sealed class OllamaVocabularyAI(HttpClient client, string address, string model) : IVocabularyAI
{
    public async Task<WordExplanation> ExplainWordAsync(WordExplanationRequest request, CancellationToken cancellationToken = default)
    {
        var valid = WordExplanationValidation.Normalize(request);
        if (!Uri.TryCreate(address.TrimEnd('/') + "/api/chat", UriKind.Absolute, out var endpoint) || endpoint.Scheme is not ("http" or "https"))
            throw new ArgumentException("Ollama 服务地址无效。");
        try { return WordExplanationValidation.Parse(await Complete(endpoint, valid, false, cancellationToken), valid); }
        catch (JsonException) { return WordExplanationValidation.Parse(await Complete(endpoint, valid, true, cancellationToken), valid); }
    }

    private async Task<string> Complete(Uri endpoint, WordExplanationRequest request, bool repair, CancellationToken cancellationToken)
    {
        using var message = new HttpRequestMessage(HttpMethod.Post, endpoint) { Content = JsonContent.Create(Payload(request, repair)) };
        using var response = await client.SendAsync(message, cancellationToken);
        if (!response.IsSuccessStatusCode) throw new HttpRequestException($"Ollama 返回 HTTP {(int)response.StatusCode}。");
        using var envelope = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        if (envelope.RootElement.TryGetProperty("error", out var error)) throw new InvalidDataException(error.GetString());
        return envelope.RootElement.GetProperty("message").GetProperty("content").GetString() ?? "";
    }

    private object Payload(WordExplanationRequest request, bool repair) => new
    {
        model,
        messages = new[]
        {
            new { role = "system", content = "Explain selectedText only as a language tutor. Copy selectedText exactly into surface. Use sentenceContext to determine meaning. contextualMeaning, briefMeaning, inflection and collocations.meaning MUST be written in explanationLanguage. If explanationLanguage is Chinese, use Simplified Chinese and never English. Return JSON only." },
            new { role = "user", content = repair
                ? $"Start over and fix every requirement. Request:\n{JsonSerializer.Serialize(request, PromptJson)}\nsurface must exactly equal selectedText. Explain the actual word, never Unicode codes. All meaning fields must use {request.ExplanationLanguage}. Return JSON only."
                : JsonSerializer.Serialize(request, PromptJson) }
        },
        stream = false, format = Schema, options = new { temperature = 0, num_predict = 280 }
    };

    private static readonly object Schema = new
    {
        type = "object", additionalProperties = false,
        properties = new
        {
            surface = new { type = "string" }, lemma = new { type = "string" }, reading = new { type = new[] { "string", "null" } },
            partOfSpeech = new { type = "string" }, contextualMeaning = new { type = "string" }, briefMeaning = new { type = "string" },
            inflection = new { type = new[] { "string", "null" } },
            collocations = new { type = "array", maxItems = 4, items = new { type = "object", additionalProperties = false, properties = new { text = new { type = "string" }, meaning = new { type = "string" } }, required = new[] { "text", "meaning" } } }
        },
        required = new[] { "surface", "lemma", "partOfSpeech", "contextualMeaning", "briefMeaning", "collocations" }
    };

    private static readonly JsonSerializerOptions PromptJson = new(ContractJson.Options)
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = false
    };
}
