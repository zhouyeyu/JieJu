namespace JieJu.Domain;

public sealed record ExplanationRequest
{
    public required string TargetText { get; init; }
    public string? PrecedingContext { get; init; }
    public string? FollowingContext { get; init; }
    public required string SourceLanguage { get; init; }
    public required string ExplanationLanguage { get; init; }
}

public sealed record Explanation
{
    public required string Translation { get; init; }
    public required string SentenceCore { get; init; }
    public required GrammarPoint[] GrammarPoints { get; init; }
    public required KeyPhrase[] KeyPhrases { get; init; }
}

public sealed record GrammarPoint(string Text, string Explanation);
public sealed record KeyPhrase(string Text, string Meaning);

public sealed record DeepAnalysis
{
    public required string SentenceType { get; init; }
    public required string SentencePattern { get; init; }
    public required SentenceComponent[] Components { get; init; }
    public required Clause[] Clauses { get; init; }
    public required GrammarPoint[] GrammarPoints { get; init; }
    public required string Interpretation { get; init; }
    public JapaneseWord[]? JapaneseWords { get; init; }
}

public sealed record SentenceComponent(string Text, string Role, string Explanation, string? Modifies = null);
public sealed record Clause(string Text, string Type, string Function, string Explanation);
public sealed record JapaneseWord(string Text, string BaseForm, string Reading, string InflectionType, string GrammaticalFunction);

public sealed record WordExplanationRequest
{
    public required string SelectedText { get; init; }
    public required string SentenceContext { get; init; }
    public string? PrecedingContext { get; init; }
    public string? FollowingContext { get; init; }
    public required string SourceLanguage { get; init; }
    public required string ExplanationLanguage { get; init; }
}

public sealed record WordExplanation
{
    public required string Surface { get; init; }
    public required string Lemma { get; init; }
    public string? Reading { get; init; }
    public required string PartOfSpeech { get; init; }
    public required string ContextualMeaning { get; init; }
    public required string BriefMeaning { get; init; }
    public string? Inflection { get; init; }
    public required KeyPhrase[] Collocations { get; init; }
}
