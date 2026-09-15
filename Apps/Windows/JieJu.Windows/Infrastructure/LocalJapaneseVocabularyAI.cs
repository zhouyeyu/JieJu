using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public sealed class LocalJapaneseVocabularyAI(IVocabularyAI inner, IJapaneseMorphology morphology) : IVocabularyAI
{
    public async Task<WordExplanation> ExplainWordAsync(WordExplanationRequest request, CancellationToken cancellationToken = default)
    {
        var explanation = await inner.ExplainWordAsync(request, cancellationToken);
        if (!JapaneseLanguage.IsJapanese(request.SourceLanguage, request.SelectedText)) return explanation;
        var tokens = morphology.Tokenize(request.SelectedText).Where(token => token.PartOfSpeech != "symbol").ToArray();
        if (tokens.Length == 0) return explanation;
        var parts = tokens.Select(token => token.PartOfSpeech).Distinct().ToArray();
        var inflected = tokens.Where(token => token.IsInflected).Select(token => $"{token.Surface} → {token.DictionaryForm}").ToArray();
        return explanation with
        {
            Surface = request.SelectedText,
            Lemma = string.Concat(tokens.Select(token => token.DictionaryForm)),
            Reading = string.Concat(tokens.Select(token => token.Reading)),
            PartOfSpeech = string.Join(" / ", parts),
            Inflection = inflected.Length == 0 ? null : string.Join("、", inflected)
        };
    }
}
