using System.Text.Json.Serialization;

namespace JieJu.Domain;

public sealed record Document(string Id, string FileName, string? Fingerprint = null);
public sealed record ReadingProgress(Document Document, int PageIndex, DateTimeOffset UpdatedAt);
// The persisted grammar field is "title"; the AI response field is "text".
public sealed record PersistedGrammarPoint(string Title, string Explanation);
public sealed record PersistedKeyPhrase(string Text, string Meaning, string? Example = null);
public sealed record PersistedExplanation(
    string Translation, string SentenceCore, PersistedGrammarPoint[] GrammarPoints,
    PersistedKeyPhrase[] KeyPhrases, string? ModelName = null);
public sealed record SavedExplanation(
    Guid Id, Document Document, ExplanationRequest Request, PersistedExplanation Explanation,
    DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt, int? PageIndex = null, DocumentLocator? Locator = null);
public sealed record VocabularySense(Guid Id, string Meaning, string ExplanationLanguage);
public sealed record VocabularySource(
    Guid Id, Document Document, string Sentence, string Surface, DateTimeOffset CreatedAt,
    int? PageIndex = null, DocumentLocator? Locator = null);
public sealed record VocabularyEntry(
    Guid Id, string Language, string Lemma, string[] SurfaceForms, VocabularySense[] Senses,
    VocabularySource[] Sources, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt,
    string? Reading = null, string? PartOfSpeech = null);

public enum ReviewTemplate { Recognition, Cloze }
public enum ReviewState { New, Learning, Review, Suspended }
public enum ReviewRating { Again, Hard, Good, Easy }

public sealed record ReviewCard(
    Guid Id, [property: JsonPropertyName("vocabularyEntryID")] Guid VocabularyEntryId,
    ReviewTemplate Template, ReviewState State, DateTimeOffset DueAt, double IntervalDays,
    double EaseFactor, int Repetitions, int Lapses, DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt, DateTimeOffset? LastReviewedAt = null);
public sealed record ReviewLog(
    Guid Id, [property: JsonPropertyName("cardID")] Guid CardId,
    [property: JsonPropertyName("vocabularyEntryID")] Guid VocabularyEntryId,
    ReviewRating Rating, DateTimeOffset ReviewedAt, ReviewState PreviousState,
    double PreviousIntervalDays, double ScheduledIntervalDays, DateTimeOffset ScheduledDueAt,
    string SchedulerVersion);

public sealed record LearningLibrary
{
    public int SchemaVersion => 5;
    public required ReadingProgress[] ReadingProgress { get; init; }
    public required SavedExplanation[] SavedExplanations { get; init; }
    public required VocabularyEntry[] VocabularyEntries { get; init; }
    public required ReviewCard[] ReviewCards { get; init; }
    public required ReviewLog[] ReviewLogs { get; init; }

    public static LearningLibrary Empty => new()
    {
        ReadingProgress = [], SavedExplanations = [], VocabularyEntries = [], ReviewCards = [], ReviewLogs = []
    };
}
