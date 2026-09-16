namespace JieJu.Domain;

public static class LearningRecordFactory
{
    public static SavedExplanation Explanation(
        Document document,
        ExplanationRequest request,
        Explanation result,
        string modelName,
        DocumentLocator? locator,
        DateTimeOffset createdAt)
    {
        return new SavedExplanation(
            Guid.NewGuid(), document, request,
            new PersistedExplanation(
                result.Translation,
                result.SentenceCore,
                result.GrammarPoints.Select(point => new PersistedGrammarPoint(point.Text, point.Explanation)).ToArray(),
                result.KeyPhrases.Select(phrase => new PersistedKeyPhrase(phrase.Text, phrase.Meaning)).ToArray(),
                modelName),
            createdAt, createdAt, Locator: locator);
    }

    public static VocabularyEntry Vocabulary(
        Document document,
        ExplanationRequest request,
        string sentence,
        WordExplanation result,
        DocumentLocator? locator,
        DateTimeOffset createdAt)
    {
        return new VocabularyEntry(
            Guid.NewGuid(), request.SourceLanguage, result.Lemma, [result.Surface],
            [new VocabularySense(Guid.NewGuid(), result.ContextualMeaning, request.ExplanationLanguage)],
            [new VocabularySource(Guid.NewGuid(), document, sentence, result.Surface, createdAt, Locator: locator)],
            createdAt, createdAt, result.Reading, result.PartOfSpeech);
    }
}
