using JieJu.Domain;
using MeCab;

namespace JieJu.Windows.Infrastructure;

public sealed class MeCabJapaneseMorphology : IJapaneseMorphology, IDisposable
{
    private readonly MeCabTagger tagger;
    private readonly object gate = new();

    public MeCabJapaneseMorphology() => tagger = MeCabTagger.Create(new MeCabParam());

    public IReadOnlyList<JapaneseToken> Tokenize(string text)
    {
        if (string.IsNullOrEmpty(text)) return [];
        lock (gate)
        {
            return tagger.ParseToNodes(text)
                .Where(node => node.CharType > 0 && !string.IsNullOrEmpty(node.Surface))
                .Select(ToToken)
                .ToArray();
        }
    }

    public IReadOnlyList<JapaneseReadingSegment> ReadingSegments(string text)
    {
        var tokens = Tokenize(text);
        var result = new List<JapaneseReadingSegment>();
        var cursor = 0;
        foreach (var token in tokens)
        {
            var position = text.IndexOf(token.Surface, cursor, StringComparison.Ordinal);
            if (position < 0) continue;
            if (position > cursor) result.Add(new JapaneseReadingSegment(text[cursor..position]));
            result.Add(new JapaneseReadingSegment(token.Surface,
                ContainsHan(token.Surface) && token.Reading.Length > 0 ? token.Reading : null));
            cursor = position + token.Surface.Length;
        }
        if (cursor < text.Length) result.Add(new JapaneseReadingSegment(text[cursor..]));
        return result;
    }

    private static JapaneseToken ToToken(MeCabNode node)
    {
        var features = node.Feature.Split(',');
        string Feature(int index, string fallback) => features.Length > index && features[index] is { Length: > 0 } value && value != "*" ? value : fallback;
        var surface = node.Surface;
        var dictionaryForm = Feature(6, surface);
        var reading = KatakanaToHiragana(Feature(7, surface));
        var conjugation = Feature(5, "");
        return new JapaneseToken(surface, reading, dictionaryForm, MapPartOfSpeech(Feature(0, "")),
            dictionaryForm != surface || (conjugation.Length > 0 && conjugation != "基本形"));
    }

    private static string MapPartOfSpeech(string value) => value switch
    {
        "名詞" => "noun", "動詞" => "verb", "形容詞" => "adjective", "副詞" => "adverb",
        "助詞" => "particle", "助動詞" => "auxiliary", "記号" => "symbol", "接頭詞" => "prefix",
        "接続詞" => "conjunction", "連体詞" => "adnominal", "感動詞" => "interjection", _ => "other"
    };

    public static string KatakanaToHiragana(string value) => string.Concat(value.Select(character =>
        character is >= '\u30a1' and <= '\u30f6' ? (char)(character - 0x60) : character));

    private static bool ContainsHan(string value) => value.Any(character => character is >= '\u3400' and <= '\u9fff');

    public void Dispose() => tagger.Dispose();
}
