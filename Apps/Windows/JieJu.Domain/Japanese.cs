namespace JieJu.Domain;

public sealed record JapaneseToken(
    string Surface,
    string Reading,
    string DictionaryForm,
    string PartOfSpeech,
    bool IsInflected);

public sealed record JapaneseReadingSegment(string Surface, string? Reading = null);

public interface IJapaneseMorphology
{
    IReadOnlyList<JapaneseToken> Tokenize(string text);
    IReadOnlyList<JapaneseReadingSegment> ReadingSegments(string text);
}

public static class JapaneseLanguage
{
    public static bool IsJapanese(string language, string? text = null) =>
        language.Contains("Japanese", StringComparison.OrdinalIgnoreCase) ||
        language.StartsWith("ja", StringComparison.OrdinalIgnoreCase) ||
        text?.Any(character => character is >= '\u3040' and <= '\u30ff') == true;
}
