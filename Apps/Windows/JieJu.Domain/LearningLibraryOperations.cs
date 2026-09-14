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

    public static LearningLibrary UpsertVocabulary(LearningLibrary library, VocabularyEntry incoming, DateTimeOffset? dueAt = null)
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
        return EnsureRecognitionCards(library with { VocabularyEntries = entries.ToArray() }, dueAt ?? incoming.UpdatedAt);
    }

    public static LearningLibrary EnsureRecognitionCards(LearningLibrary library, DateTimeOffset dueAt)
    {
        var cards = library.ReviewCards.ToList();
        foreach (var entry in library.VocabularyEntries)
        {
            if (cards.Any(card => card.VocabularyEntryId == entry.Id && card.Template == ReviewTemplate.Recognition)) continue;
            cards.Add(new ReviewCard(Guid.NewGuid(), entry.Id, ReviewTemplate.Recognition, ReviewState.New,
                dueAt, 0, 2.5, 0, 0, dueAt, dueAt));
        }
        return library with { ReviewCards = cards.ToArray() };
    }

    public static ReviewQueueItem[] DueReviews(LearningLibrary library, DateTimeOffset at, int limit = 50)
    {
        var entries = library.VocabularyEntries.ToDictionary(entry => entry.Id);
        return library.ReviewCards
            .Where(card => card.State != ReviewState.Suspended && card.DueAt <= at && entries.ContainsKey(card.VocabularyEntryId))
            .OrderBy(card => card.DueAt).ThenBy(card => card.CreatedAt)
            .Take(Math.Max(0, limit))
            .Select(card => new ReviewQueueItem(card, entries[card.VocabularyEntryId]))
            .ToArray();
    }

    public static LearningLibrary Review(LearningLibrary library, Guid cardId, ReviewRating rating, DateTimeOffset at)
    {
        var cards = library.ReviewCards.ToArray();
        var index = Array.FindIndex(cards, card => card.Id == cardId);
        if (index < 0) throw new KeyNotFoundException($"Review card {cardId} was not found.");
        var outcome = ReviewScheduler.Review(cards[index], rating, at);
        cards[index] = outcome.Card;
        return library with { ReviewCards = cards, ReviewLogs = [.. library.ReviewLogs, outcome.Log] };
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

public sealed record ReviewQueueItem(ReviewCard Card, VocabularyEntry Entry);
