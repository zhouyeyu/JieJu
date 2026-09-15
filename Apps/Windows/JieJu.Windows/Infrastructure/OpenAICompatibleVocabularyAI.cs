using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Encodings.Web;
using System.Text.Json;
using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public sealed class OpenAICompatibleVocabularyAI(HttpClient client, string address, string apiKey, string model) : IVocabularyAI
{
    public async Task<WordExplanation> ExplainWordAsync(WordExplanationRequest request, CancellationToken cancellationToken = default)
    {
        var valid = WordExplanationValidation.Normalize(request);
        try { return WordExplanationValidation.Parse(await Complete(valid, false, cancellationToken), valid); }
        catch (JsonException) { return WordExplanationValidation.Parse(await Complete(valid, true, cancellationToken), valid); }
    }

    private async Task<string> Complete(WordExplanationRequest request, bool repair, CancellationToken cancellationToken)
    {
        if (!Uri.TryCreate(address.TrimEnd('/') + "/chat/completions", UriKind.Absolute, out var endpoint) || endpoint.Scheme is not ("http" or "https")) throw new ArgumentException("云端 API 地址无效。");
        if (string.IsNullOrWhiteSpace(apiKey)) throw new ArgumentException("API Key 不能为空。");
        if (string.IsNullOrWhiteSpace(model)) throw new ArgumentException("云端模型名称不能为空。");
        var payload = new
        {
            model, messages = new[] { new { role = "system", content = "Explain selectedText only as a language tutor. Copy selectedText exactly into surface. Use sentenceContext to determine meaning. contextualMeaning, briefMeaning, inflection and collocations.meaning MUST be written in explanationLanguage. If explanationLanguage is Chinese, use Simplified Chinese and never English. Return JSON only." }, new { role = "user", content = repair ? $"Start over and fix every requirement. Request:\n{JsonSerializer.Serialize(request, PromptJson)}\nsurface must exactly equal selectedText. All meaning fields must use {request.ExplanationLanguage}. Return JSON only." : JsonSerializer.Serialize(request, PromptJson) } },
            stream = false, temperature = 0, max_tokens = 300, response_format = new { type = "json_object" }
        };
        using var message = new HttpRequestMessage(HttpMethod.Post, endpoint) { Content = JsonContent.Create(payload) };
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());
        using var response = await client.SendAsync(message, cancellationToken);
        var responseText = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            string? errorMessage = null;
            try { using var error = JsonDocument.Parse(responseText); errorMessage = error.RootElement.GetProperty("error").GetProperty("message").GetString(); }
            catch (Exception exception) when (exception is JsonException or KeyNotFoundException or InvalidOperationException) { }
            throw new HttpRequestException(errorMessage ?? $"云端服务返回 HTTP {(int)response.StatusCode}。");
        }
        using var envelope = JsonDocument.Parse(responseText);
        return envelope.RootElement.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString() ?? throw new InvalidDataException("云端响应没有文本内容。");
    }

    private static readonly JsonSerializerOptions PromptJson = new(ContractJson.Options) { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping, WriteIndented = false };
}
