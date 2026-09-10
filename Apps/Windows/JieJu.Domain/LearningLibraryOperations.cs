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

    private static bool IsDuplicate(SavedExplanation left, SavedExplanation right) =>
        left.Document.Id == right.Document.Id
        && left.PageIndex == right.PageIndex
        && Normalize(left.Request.TargetText) == Normalize(right.Request.TargetText)
        && Normalize(left.Request.PrecedingContext) == Normalize(right.Request.PrecedingContext)
        && Normalize(left.Request.FollowingContext) == Normalize(right.Request.FollowingContext);

    private static string Normalize(string? value) =>
        string.Join(' ', (value ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)).ToLowerInvariant();
}
