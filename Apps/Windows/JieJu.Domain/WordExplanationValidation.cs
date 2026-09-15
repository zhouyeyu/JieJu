using System.Text.Json;

namespace JieJu.Domain;

public static class WordExplanationValidation
{
    public static WordExplanationRequest Normalize(WordExplanationRequest request)
    {
        var selected = Clean(request.SelectedText);
        var sentence = Clean(request.SentenceContext);
        if (selected.Length is 0 or > 120 || sentence.Length is 0 or > 2000 || !sentence.Contains(selected, StringComparison.Ordinal))
            throw new ArgumentException("词语必须来自当前句子。");
        return request with
        {
            SelectedText = selected,
            SentenceContext = sentence,
            PrecedingContext = Optional(request.PrecedingContext),
            FollowingContext = Optional(request.FollowingContext)
        };
    }

    public static WordExplanation Parse(string raw, WordExplanationRequest request)
    {
        var start = raw.IndexOf('{'); var end = raw.LastIndexOf('}');
        if (start < 0 || end <= start) throw new JsonException("模型没有返回词语解释 JSON。");
        var result = ContractJson.Deserialize<WordExplanation>(raw[start..(end + 1)]);
        if (Clean(result.Surface) != request.SelectedText || string.IsNullOrWhiteSpace(result.Lemma)
            || string.IsNullOrWhiteSpace(result.PartOfSpeech) || string.IsNullOrWhiteSpace(result.ContextualMeaning)
            || string.IsNullOrWhiteSpace(result.BriefMeaning)
            || result.Collocations.Any(item => string.IsNullOrWhiteSpace(item.Text) || string.IsNullOrWhiteSpace(item.Meaning)))
            throw new JsonException("模型词语解释与选区不一致。");
        if (RequestsChinese(request.ExplanationLanguage)
            && (!ContainsHan(result.ContextualMeaning) || !ContainsHan(result.BriefMeaning)
                || result.Collocations.Any(item => !ContainsHan(item.Meaning))))
            throw new JsonException("模型没有使用中文解释词语。");
        return result;
    }

    private static string? Optional(string? value) => Clean(value) is { Length: > 0 } clean ? clean : null;
    private static string Clean(string? value) => string.Join(' ', (value ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    private static bool RequestsChinese(string value) => value.Contains("Chinese", StringComparison.OrdinalIgnoreCase)
        || value.Contains("中文", StringComparison.Ordinal) || value.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
    private static bool ContainsHan(string value) => value.Any(character => character is >= '\u3400' and <= '\u9fff');
}
