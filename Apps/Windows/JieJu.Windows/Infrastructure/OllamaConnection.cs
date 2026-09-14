using System.Text.Json;

namespace JieJu.Windows.Infrastructure;

public static class OllamaConnection
{
    public static async Task<string> CheckAsync(string address, string model)
    {
        if (!Uri.TryCreate(address.TrimEnd('/') + "/api/tags", UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https")) throw new ArgumentException("服务地址无效。");
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
        using var response = await client.GetAsync(uri); response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return json.RootElement.GetProperty("models").EnumerateArray().Any(m => m.GetProperty("name").GetString() == model.Trim())
            ? "连接正常，模型已就绪。" : "已连接 Ollama，但没有找到此模型。请先在 Ollama 中下载。";
    }
}
