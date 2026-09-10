namespace JieJu.Domain;

public static class LearningLibraryOperations
{
    public static LearningLibrary UpsertExplanation(LearningLibrary library, SavedExplanation incoming)
    {
        var records = library.SavedExplanations.ToList();
        var index = records.FindIndex(existing => IsDuplicate(existing, incoming));
        if (index >= 0)
        {
            var existing = records[index];
            records[index] = incoming with
            {
                Id = existing.Id,
                CreatedAt = existing.CreatedAt,
                Locator = incoming.Locator ?? existing.Locator
            };
        }
        else records.Add(incoming);
        return library with { SavedExplanations = records.ToArray() };
    }

    public static LearningLibrary DeleteExplanation(LearningLibrary library, Guid id) =>
        library with { SavedExplanations = library.SavedExplanations.Where(record => record.Id != id).ToArray() };

    public static LearningLibrary UpsertVocabulary(LearningLibrary library, VocabularyEntry incoming)
    {
        var entries = library.VocabularyEntries.ToList();
        var index = entries.FindIndex(item => Normalize(item.Language) == Normalize(incoming.Language)
            && Normalize(item.Lemma) == Normalize(incoming.Lemma)
            && (Normalize(item.Reading).Length == 0 || Normalize(incoming.Reading).Length == 0 || Normalize(item.Reading) == Normalize(incoming.Reading)));
        if (index < 0) entries.Add(incoming);
        else
        {
            var existing = entries[index];
            entries[index] = existing with
            {
                Reading = string.IsNullOrWhiteSpace(existing.Reading) ? incoming.Reading : existing.Reading,
                PartOfSpeech = string.IsNullOrWhiteSpace(existing.PartOfSpeech) ? incoming.PartOfSpeech : existing.PartOfSpeech,
                SurfaceForms = existing.SurfaceForms.Concat(incoming.SurfaceForms).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(),
                Senses = existing.Senses.Concat(incoming.Senses.Where(sense => !existing.Senses.Any(old => Normalize(old.Meaning) == Normalize(sense.Meaning) && Normalize(old.ExplanationLanguage) == Normalize(sense.ExplanationLanguage)))).ToArray(),
                Sources = existing.Sources.Concat(incoming.Sources.Where(source => !existing.Sources.Any(old => old.Document.Id == source.Document.Id && Normalize(old.Sentence) == Normalize(source.Sentence) && Normalize(old.Surface) == Normalize(source.Surface)))).ToArray(),
                UpdatedAt = incoming.UpdatedAt
            };
        }
        return library with { VocabularyEntries = entries.ToArray() };
    }

    public static LearningLibrary DeleteVocabulary(LearningLibrary library, Guid id)
    {
        var cardIds = library.ReviewCards.Where(card => card.VocabularyEntryId == id).Select(card => card.Id).ToHashSet();
        return library with
        {
            VocabularyEntries = library.VocabularyEntries.Where(entry => entry.Id != id).ToArray(),
            ReviewCards = library.ReviewCards.Where(card => card.VocabularyEntryId != id).ToArray(),
            ReviewLogs = library.ReviewLogs.Where(log => log.VocabularyEntryId != id && !cardIds.Contains(log.CardId)).ToArray()
        };
    }

    private static bool IsDuplicate(SavedExplanation left, SavedExplanation right) =>
        left.Document.Id == right.Document.Id
        && left.PageIndex == right.PageIndex
        && Normalize(left.Request.TargetText) == Normalize(right.Request.TargetText)
        && Normalize(left.Request.PrecedingContext) == Normalize(right.Request.PrecedingContext)
        && Normalize(left.Request.FollowingContext) == Normalize(right.Request.FollowingContext);

    private static string Normalize(string? value) =>
        string.Join(' ', (value ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)).ToLowerInvariant();
}
