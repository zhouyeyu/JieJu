using System.Text.RegularExpressions;

namespace JieJu.Domain;

public enum SelectionKind { Word, Expression, Sentence, Passage, Ambiguous }

public sealed record SelectionBoundarySuggestion(string OriginalText, string SuggestedText);

public static partial class SelectionClassifier
{
    public static SelectionKind Classify(string text, string sourceLanguage)
    {
        var value = ExplanationValidation.Clean(text);
        if (value.Length == 0) return SelectionKind.Ambiguous;
        var terminators = value.Count(character => ".!?。！？".Contains(character));
        if (terminators >= 2) return SelectionKind.Passage;
        if (terminators == 1) return SelectionKind.Sentence;
        var words = Word().Matches(value).Count;
        if (UsesUnspacedText(sourceLanguage, value))
        {
            if (value.Length <= 4) return SelectionKind.Word;
            if (value.Length <= 10) return SelectionKind.Expression;
            return SelectionKind.Ambiguous;
        }
        if (words == 1) return SelectionKind.Word;
        if (words is >= 2 and <= 5) return SelectionKind.Expression;
        if (words >= 8) return SelectionKind.Sentence;
        return SelectionKind.Ambiguous;
    }

    public static SelectionBoundarySuggestion? SuggestBoundary(string selectedText, string? sentence, string sourceLanguage, IJapaneseMorphology? morphology = null)
    {
        var selected = ExplanationValidation.Clean(selectedText);
        if (selected.Length == 0 || string.IsNullOrWhiteSpace(sentence)) return null;
        if (JapaneseLanguage.IsJapanese(sourceLanguage, sentence) && morphology is not null)
        {
            var containing = morphology.Tokenize(sentence)
                .Where(token => token.Surface.Contains(selected, StringComparison.Ordinal) && token.Surface != selected)
                .Select(token => token.Surface).Distinct().ToArray();
            return containing.Length == 1 ? new SelectionBoundarySuggestion(selected, containing[0]) : null;
        }
        if (UsesUnspacedText(sourceLanguage, sentence)) return null;
        var matches = Word().Matches(sentence).Where(match => match.Value.Contains(selected, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (matches.Length != 1 || matches[0].Value.Equals(selected, StringComparison.OrdinalIgnoreCase)) return null;
        return new SelectionBoundarySuggestion(selected, matches[0].Value);
    }

    public static string ActionTitle(SelectionKind kind) => kind switch
    {
        SelectionKind.Word => "查这个词",
        SelectionKind.Expression => "解释这个表达",
        SelectionKind.Sentence => "解读这句话",
        SelectionKind.Passage => "理解这段文字",
        _ => "解释所选内容"
    };

    public static bool IsLexical(SelectionKind kind) => kind is SelectionKind.Word or SelectionKind.Expression;
    private static bool UsesUnspacedText(string language, string text) => language.Contains("Japanese", StringComparison.OrdinalIgnoreCase)
        || language.StartsWith("ja", StringComparison.OrdinalIgnoreCase) || language.Contains("Chinese", StringComparison.OrdinalIgnoreCase)
        || language.StartsWith("zh", StringComparison.OrdinalIgnoreCase) || !text.Any(char.IsWhiteSpace) && text.Any(character => character is >= '\u3040' and <= '\u9fff');
    [GeneratedRegex(@"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*")]
    private static partial Regex Word();
}
