using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public sealed class OpenAICompatibleReadingAI(HttpClient client, string address, string apiKey, string model) : IStreamingReadingAI, IDeepReadingAI
{
    private const string SystemPrompt = "You are a language tutor. Analyze targetText only. Context is reference only. Write translation, explanation and meaning in explanationLanguage. Keep sentenceCore and every text field as exact consecutive text copied from targetText. Return JSON only with keys in this order: translation, sentenceCore, grammarPoints, keyPhrases. Use empty arrays when unsure.";

    public async Task CheckAvailabilityAsync(CancellationToken cancellationToken = default)
    {
        using var request = Authorized(HttpMethod.Get, "models");
        using var response = await client.SendAsync(request, cancellationToken);
        await EnsureSuccess(response, cancellationToken);
    }

    public async Task<Explanation> ExplainAsync(ExplanationRequest request, CancellationToken cancellationToken = default)
    {
        Explanation? result = null;
        await foreach (var progress in ExplainStreamAsync(request, cancellationToken)) result = progress.Result ?? result;
        return result ?? throw new InvalidDataException("云端模型没有返回完整解释。");
    }

    public async IAsyncEnumerable<ExplanationProgress> ExplainStreamAsync(ExplanationRequest request, [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var valid = ExplanationValidation.Normalize(request);
        var raw = "";
        string? previousPreview = null;
        await foreach (var generated in Stream(valid, cancellationToken))
        {
            raw = generated;
            var preview = PartialExplanationParser.Parse(raw, valid);
            var key = preview is null ? null : JsonSerializer.Serialize(preview, PromptJson);
            if (key != previousPreview) { previousPreview = key; yield return new ExplanationProgress(raw, Preview: preview); }
        }
        Explanation? result = null;
        try { result = ExplanationValidation.Parse(raw, valid); } catch (JsonException) { }
        if (result is null) result = ExplanationValidation.Parse(await Complete(QuickPayload(valid, true, false), cancellationToken), valid);
        yield return new ExplanationProgress(raw, result);
    }

    public async Task<DeepAnalysis> AnalyzeDeepAsync(ExplanationRequest request, CancellationToken cancellationToken = default)
    {
        var valid = ExplanationValidation.Normalize(request);
        try { return DeepAnalysisValidation.Parse(await Complete(DeepPayload(valid, false), cancellationToken), valid); }
        catch (JsonException) { return DeepAnalysisValidation.Parse(await Complete(DeepPayload(valid, true), cancellationToken), valid); }
    }

    private async IAsyncEnumerable<string> Stream(ExplanationRequest request, [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        using var message = Authorized(HttpMethod.Post, "chat/completions", QuickPayload(request, false, true));
        using var response = await client.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        await EnsureSuccess(response, cancellationToken);
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var reader = new StreamReader(stream, Encoding.UTF8);
        var generated = new StringBuilder();
        while (await reader.ReadLineAsync(cancellationToken) is { } line)
        {
            line = line.Trim();
            if (line.Length == 0 || line.StartsWith(':')) continue;
            if (line.StartsWith("data:", StringComparison.OrdinalIgnoreCase)) line = line[5..].Trim();
            if (line == "[DONE]") break;
            using var envelope = JsonDocument.Parse(line);
            if (envelope.RootElement.TryGetProperty("error", out var error)) throw new InvalidDataException(ReadError(error));
            if (envelope.RootElement.TryGetProperty("choices", out var choices) && choices.GetArrayLength() > 0 &&
                choices[0].TryGetProperty("delta", out var delta) && delta.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.String)
                generated.Append(content.GetString());
            yield return generated.ToString();
        }
    }

    private async Task<string> Complete(object payload, CancellationToken cancellationToken)
    {
        using var request = Authorized(HttpMethod.Post, "chat/completions", payload);
        using var response = await client.SendAsync(request, cancellationToken);
        await EnsureSuccess(response, cancellationToken);
        using var envelope = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var content = envelope.RootElement.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString();
        return !string.IsNullOrWhiteSpace(content) ? content : throw new InvalidDataException("云端响应没有文本内容。");
    }

    private HttpRequestMessage Authorized(HttpMethod method, string path, object? payload = null)
    {
        if (!Uri.TryCreate(address.TrimEnd('/') + "/" + path, UriKind.Absolute, out var endpoint) || endpoint.Scheme is not ("http" or "https")) throw new ArgumentException("云端 API 地址无效。");
        if (string.IsNullOrWhiteSpace(apiKey)) throw new ArgumentException("API Key 不能为空。");
        if (string.IsNullOrWhiteSpace(model)) throw new ArgumentException("云端模型名称不能为空。");
        var request = new HttpRequestMessage(method, endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());
        if (payload is not null) request.Content = JsonContent.Create(payload);
        return request;
    }

    private static async Task EnsureSuccess(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode) return;
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        string? message = null;
        try
        {
            using var json = JsonDocument.Parse(body);
            if (json.RootElement.TryGetProperty("error", out var error)) message = ReadError(error);
        }
        catch (JsonException) { }
        throw new HttpRequestException(message ?? $"云端服务返回 HTTP {(int)response.StatusCode}。");
    }

    private static string ReadError(JsonElement error) => error.ValueKind == JsonValueKind.Object && error.TryGetProperty("message", out var message) ? message.GetString() ?? "云端服务返回错误。" : error.ToString();

    private object QuickPayload(ExplanationRequest request, bool repair, bool stream) => new
    {
        model, messages = new[] { new { role = "system", content = SystemPrompt }, new { role = "user", content = repair ? $"Start over. targetText is exactly: {request.TargetText}\nSet sentenceCore exactly to targetText. Write translation in {request.ExplanationLanguage}. Use empty arrays when unsure. Return JSON only." : JsonSerializer.Serialize(request, PromptJson) } },
        stream, temperature = 0, max_tokens = 350, response_format = new { type = "json_object" }
    };

    private object DeepPayload(ExplanationRequest request, bool repair) => new
    {
        model, messages = new[] { new { role = "system", content = "You are a rigorous syntax tutor. Analyze targetText only. Copy every components.text, non-empty modifies, clauses.text and grammarPoints.text exactly from targetText. Explain sentence type, pattern, roles, relationships and interpretation in explanationLanguage. Use empty arrays when uncertain. Return JSON only." }, new { role = "user", content = repair ? $"Start over. Analyze only: {request.TargetText}\nAll explanations must use {request.ExplanationLanguage}. Every analyzed text fragment must be copied exactly from targetText. Use fewer items when uncertain. Return JSON only." : $"Deeply analyze targetText syntax. Request:\n{JsonSerializer.Serialize(request, PromptJson)}" } },
        stream = false, temperature = 0, max_tokens = 700, response_format = new { type = "json_object" }
    };

    private static readonly JsonSerializerOptions PromptJson = new(ContractJson.Options) { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping, WriteIndented = false };
}
