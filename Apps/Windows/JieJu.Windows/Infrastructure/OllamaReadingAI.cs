using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public sealed class OllamaReadingAI(HttpClient client, string address, string model) : IStreamingReadingAI
{
    private const string SystemPrompt = """
        You are a language tutor. Analyze targetText only. Context is reference only.
        Write translation, explanation and meaning in explanationLanguage. Keep sentenceCore and every text field as exact consecutive text copied from targetText.
        Return JSON only with keys in this order: translation, sentenceCore, grammarPoints, keyPhrases. Use empty arrays when unsure.
        """;

    public async Task<Explanation> ExplainAsync(ExplanationRequest request, CancellationToken cancellationToken = default)
    {
        Explanation? result = null;
        await foreach (var update in ExplainStreamAsync(request, cancellationToken)) result = update.Result ?? result;
        return result ?? throw new InvalidDataException("模型没有返回完整解释。");
    }

    public async IAsyncEnumerable<ExplanationProgress> ExplainStreamAsync(ExplanationRequest request, [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var valid = ExplanationValidation.Normalize(request);
        if (!Uri.TryCreate(address.TrimEnd('/') + "/api/chat", UriKind.Absolute, out var endpoint) || endpoint.Scheme is not ("http" or "https"))
            throw new ArgumentException("Ollama 服务地址无效。");
        var generated = "";
        await foreach (var text in GenerateAsync(endpoint, Payload(valid, repair: false), cancellationToken))
        {
            generated = text; yield return new ExplanationProgress(generated);
        }
        Explanation? result = null;
        try { result = ExplanationValidation.Parse(generated, valid); }
        catch (JsonException) { }
        if (result is null)
        {
            generated = "";
            await foreach (var text in GenerateAsync(endpoint, Payload(valid, repair: true), cancellationToken))
            {
                generated = text; yield return new ExplanationProgress(generated);
            }
            result = ExplanationValidation.Parse(generated, valid);
        }
        yield return new ExplanationProgress(generated, result);
    }

    private async IAsyncEnumerable<string> GenerateAsync(Uri endpoint, object payload, [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        using var message = new HttpRequestMessage(HttpMethod.Post, endpoint) { Content = JsonContent.Create(payload) };
        using var response = await client.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (!response.IsSuccessStatusCode) throw new HttpRequestException($"Ollama 返回 HTTP {(int)response.StatusCode}。");
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var reader = new StreamReader(stream, Encoding.UTF8);
        var generated = new StringBuilder();
        while (await reader.ReadLineAsync(cancellationToken) is { } line)
        {
            if (line.Length == 0) continue;
            using var envelope = JsonDocument.Parse(line);
            if (envelope.RootElement.TryGetProperty("error", out var error)) throw new InvalidDataException(error.GetString());
            if (envelope.RootElement.TryGetProperty("message", out var item) && item.TryGetProperty("content", out var content)) generated.Append(content.GetString());
            yield return generated.ToString();
        }
    }

    private object Payload(ExplanationRequest request, bool repair) => new
    {
        model,
        messages = new[]
        {
            new { role = "system", content = SystemPrompt },
            new { role = "user", content = repair
                ? $"Start over. targetText is exactly: {request.TargetText}\nSet sentenceCore exactly to targetText. Write translation in {request.ExplanationLanguage}. Use empty arrays when unsure. Return JSON only."
                : JsonSerializer.Serialize(request, ContractJson.Options) }
        },
        stream = true, format = Schema, options = new { temperature = 0, num_predict = 350 }
    };

    private static readonly object Schema = new
    {
        type = "object", additionalProperties = false,
        properties = new
        {
            translation = new { type = "string" }, sentenceCore = new { type = "string" },
            grammarPoints = new { type = "array", maxItems = 3, items = new { type = "object", additionalProperties = false, properties = new { text = new { type = "string" }, explanation = new { type = "string" } }, required = new[] { "text", "explanation" } } },
            keyPhrases = new { type = "array", maxItems = 4, items = new { type = "object", additionalProperties = false, properties = new { text = new { type = "string" }, meaning = new { type = "string" } }, required = new[] { "text", "meaning" } } }
        },
        required = new[] { "translation", "sentenceCore", "grammarPoints", "keyPhrases" }
    };
}
