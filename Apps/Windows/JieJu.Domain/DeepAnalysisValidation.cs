using System.Text.Json;

namespace JieJu.Domain;

public static class DeepAnalysisValidation
{
    public static DeepAnalysis Parse(string raw, ExplanationRequest request)
    {
        var start = raw.IndexOf('{'); var end = raw.LastIndexOf('}');
        if (start < 0 || end <= start) throw new JsonException("模型没有返回深入解析 JSON。");
        var result = ContractJson.Deserialize<DeepAnalysis>(raw[start..(end + 1)]);
        if (string.IsNullOrWhiteSpace(result.SentenceType) || string.IsNullOrWhiteSpace(result.SentencePattern) || string.IsNullOrWhiteSpace(result.Interpretation))
            throw new JsonException("深入解析缺少必要内容。");
        if (RequestsChinese(request.ExplanationLanguage) && !ContainsHan(result.Interpretation))
            throw new JsonException("深入解析没有使用中文说明。");
        bool Inside(string? value) => string.IsNullOrWhiteSpace(value) || request.TargetText.Contains(value.Trim(), StringComparison.Ordinal);
        return result with
        {
            Components = result.Components.Where(item => Inside(item.Text) && Inside(item.Modifies)).Take(8).ToArray(),
            Clauses = result.Clauses.Where(item => Inside(item.Text)).Take(6).ToArray(),
            GrammarPoints = result.GrammarPoints.Where(item => Inside(item.Text)).Take(6).ToArray(),
            JapaneseWords = result.JapaneseWords?.Where(item => Inside(item.Text)).Take(12).ToArray()
        };
    }

    private static bool RequestsChinese(string value) => value.Contains("Chinese", StringComparison.OrdinalIgnoreCase)
        || value.Contains("中文", StringComparison.Ordinal) || value.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
    private static bool ContainsHan(string value) => value.Any(character => character is >= '\u3400' and <= '\u9fff');
}
