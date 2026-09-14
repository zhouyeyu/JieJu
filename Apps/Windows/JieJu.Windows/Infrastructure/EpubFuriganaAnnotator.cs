using System.Xml.Linq;
using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public static class EpubFuriganaAnnotator
{
    private static readonly HashSet<string> ExcludedAncestors = new(StringComparer.OrdinalIgnoreCase)
        { "ruby", "rt", "rp", "script", "style", "head", "textarea", "pre", "code" };

    public static bool Annotate(XDocument document, string bookLanguage, IJapaneseMorphology morphology)
    {
        var root = document.Root;
        if (root is null) return false;
        var textNodes = root.DescendantNodes().OfType<XText>().Where(IsEligible).ToArray();
        var plainText = string.Concat(textNodes.Select(node => node.Value));
        var chapterLanguage = root.Attributes().FirstOrDefault(attribute => attribute.Name.LocalName == "lang")?.Value;
        if (!IsJapaneseChapter(chapterLanguage, bookLanguage, plainText)) return false;

        var analyses = textNodes.ToDictionary(node => node, node => morphology.Tokenize(node.Value));
        var readings = analyses.Values.SelectMany(tokens => tokens)
            .Where(IsRubyCandidate)
            .GroupBy(token => token.Surface, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.Select(token => token.Reading).Distinct(StringComparer.Ordinal).ToArray(), StringComparer.Ordinal);
        var ambiguous = readings.Where(pair => pair.Value.Length > 1).Select(pair => pair.Key).ToHashSet(StringComparer.Ordinal);
        var changed = false;
        foreach (var (node, tokens) in analyses)
        {
            var replacements = BuildNodes(node, tokens, ambiguous);
            if (replacements is null) continue;
            node.ReplaceWith(replacements);
            changed = true;
        }
        return changed;
    }

    public static bool IsJapaneseChapter(string? chapterLanguage, string? bookLanguage, string text)
    {
        static string? Normalize(string? value)
        {
            var normalized = value?.Trim().ToLowerInvariant().Replace('_', '-');
            return string.IsNullOrEmpty(normalized) ? null : normalized;
        }
        var language = Normalize(string.IsNullOrWhiteSpace(chapterLanguage) ? bookLanguage : chapterLanguage);
        if (language is "ja" or "jpn" || language?.StartsWith("ja-", StringComparison.Ordinal) == true) return true;
        var kana = text.Count(character => character is >= '\u3040' and <= '\u30ff');
        var han = text.Count(character => character is >= '\u3400' and <= '\u9fff');
        var latin = text.Count(character => character is >= 'A' and <= 'Z' or >= 'a' and <= 'z');
        var unknown = language is null or "und" or "mul" or "zxx";
        if (unknown) return kana >= 2 && (double)kana / Math.Max(1, kana + han) >= .05;
        return kana >= 12 && (double)kana / Math.Max(1, kana + han) >= .20 && (double)kana / Math.Max(1, kana + han + latin) >= .15;
    }

    private static object[]? BuildNodes(XText node, IReadOnlyList<JapaneseToken> tokens, HashSet<string> ambiguous)
    {
        var result = new List<object>();
        var cursor = 0;
        var inserted = false;
        foreach (var token in tokens)
        {
            var position = node.Value.IndexOf(token.Surface, cursor, StringComparison.Ordinal);
            if (position < 0) continue;
            if (position > cursor) result.Add(node.Value[cursor..position]);
            if (IsRubyCandidate(token) && !ambiguous.Contains(token.Surface))
            {
                var ns = node.Parent?.Name.Namespace ?? XNamespace.None;
                result.Add(new XElement(ns + "ruby", new XAttribute("data-jieju-generated", "true"), token.Surface,
                    new XElement(ns + "rp", "（"), new XElement(ns + "rt", token.Reading), new XElement(ns + "rp", "）")));
                inserted = true;
            }
            else result.Add(token.Surface);
            cursor = position + token.Surface.Length;
        }
        if (cursor < node.Value.Length) result.Add(node.Value[cursor..]);
        return inserted ? result.ToArray() : null;
    }

    private static bool IsEligible(XText node) => !string.IsNullOrWhiteSpace(node.Value) &&
        !node.Ancestors().Any(element => ExcludedAncestors.Contains(element.Name.LocalName));

    private static bool IsRubyCandidate(JapaneseToken token) => token.Reading.Length > 0 &&
        token.Reading != token.Surface && token.Surface.Any(character => character is >= '\u3400' and <= '\u9fff');
}
