using System.Text.Json;
using System.Text.RegularExpressions;

namespace JieJu.Domain;

public static partial class ExplanationValidation
{
    public static ExplanationRequest Normalize(ExplanationRequest request)
    {
        var target = Clean(request.TargetText);
        if (target.Length is 0 or > 2000) throw new ArgumentException("请选择 1 到 2000 个字符。");
        if (string.IsNullOrWhiteSpace(request.SourceLanguage) || string.IsNullOrWhiteSpace(request.ExplanationLanguage))
            throw new ArgumentException("语言设置不能为空。");
        return request with
        {
            TargetText = target,
            PrecedingContext = Limit(Clean(request.PrecedingContext), 2000),
            FollowingContext = Limit(Clean(request.FollowingContext), 2000),
            SourceLanguage = request.SourceLanguage.Trim(),
            ExplanationLanguage = request.ExplanationLanguage.Trim()
        };
    }

    public static Explanation Parse(string raw, ExplanationRequest request)
    {
        var text = raw.Trim();
        if (text.StartsWith("```", StringComparison.Ordinal))
        {
            var firstLine = text.IndexOf('\n');
            if (firstLine >= 0) text = text[(firstLine + 1)..];
            if (text.EndsWith("```", StringComparison.Ordinal)) text = text[..^3].TrimEnd();
        }
        var result = JsonSerializer.Deserialize<Explanation>(text, ContractJson.Options)
            ?? throw new JsonException("模型返回了空结果。");
        if (string.IsNullOrWhiteSpace(result.Translation) || string.IsNullOrWhiteSpace(result.SentenceCore))
            throw new JsonException("解释缺少翻译或句子主干。");
        if (RequestsChinese(request.ExplanationLanguage) && !result.Translation.Any(character => character is >= '\u3400' and <= '\u9fff'))
            throw new JsonException("模型没有使用中文翻译。");
        if (result.GrammarPoints.Length > 3 || result.KeyPhrases.Length > 4) throw new JsonException("解释条目过多。");
        return result with
        {
            SentenceCore = Contains(request.TargetText, result.SentenceCore) ? result.SentenceCore : request.TargetText,
            GrammarPoints = result.GrammarPoints.Where(item => Contains(request.TargetText, item.Text)).ToArray(),
            KeyPhrases = result.KeyPhrases.Where(item => Contains(request.TargetText, item.Text)).ToArray()
        };
    }

    public static string Clean(string? text) => Whitespace().Replace(text ?? "", " ").Trim();
    private static string? Limit(string value, int length) => value.Length == 0 ? null : value[..Math.Min(value.Length, length)];
    private static bool Contains(string source, string fragment) => !string.IsNullOrWhiteSpace(fragment) && source.Contains(fragment.Trim(), StringComparison.Ordinal);
    private static bool RequestsChinese(string value) => value.Contains("Chinese", StringComparison.OrdinalIgnoreCase)
        || value.Contains("中文", StringComparison.Ordinal) || value.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
    [GeneratedRegex(@"\s+")]
    private static partial Regex Whitespace();
}
