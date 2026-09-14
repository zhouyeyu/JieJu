using System.Text.Json;
using System.Text.Json.Nodes;
using JieJu.Domain;
using Xunit;

namespace JieJu.Windows.Tests;

public class ContractTests
{
    private static JsonObject Fixture() => JsonNode.Parse(File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures/library-v5.json")))!.AsObject();

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(5)]
    public void PublishedLibrariesMigrateWithoutLosingData(int version)
    {
        var fixture = Fixture();
        fixture["schemaVersion"] = version;
        if (version < 5)
        {
            fixture["savedExplanations"]![0]!.AsObject().Remove("locator");
            fixture["vocabularyEntries"]![0]!["sources"]![0]!.AsObject().Remove("locator");
        }
        if (version < 3) { fixture.Remove("reviewCards"); fixture.Remove("reviewLogs"); }
        if (version < 2) fixture.Remove("vocabularyEntries");

        var library = ContractJson.ReadLibrary(fixture.ToJsonString());
        Assert.Equal(5, library.SchemaVersion);
        Assert.Equal("一般现在时", library.SavedExplanations[0].Explanation.GrammarPoints[0].Explanation);
        Assert.Equal("reads", library.SavedExplanations[0].Explanation.GrammarPoints[0].Title);
        Assert.Equal(library.SavedExplanations[0].CreatedAt, library.SavedExplanations[0].UpdatedAt);
        Assert.Equal(version >= 2 ? 1 : 0, library.VocabularyEntries.Length);
        Assert.Equal(version >= 3 ? 1 : 0, library.ReviewLogs.Length);
        if (version < 5) Assert.Null(library.SavedExplanations[0].Locator);
        else
        {
            Assert.Equal("Text/chapter1.xhtml", Assert.IsType<EpubLocator>(library.SavedExplanations[0].Locator).ChapterHref);
            Assert.Equal(3, Assert.IsType<PdfLocator>(library.VocabularyEntries[0].Sources[0].Locator).TextOffset);
        }
        var serialized = ContractJson.Serialize(library);
        Assert.Equal(serialized, ContractJson.Serialize(ContractJson.ReadLibrary(serialized)));
        if (version >= 3)
        {
            Assert.Contains("\"vocabularyEntryID\"", serialized);
            Assert.Contains("\"cardID\"", serialized);
            Assert.Equal(library.ReviewCards[0].Id, library.ReviewLogs[0].CardId);
            Assert.Equal(ReviewRating.Good, library.ReviewLogs[0].Rating);
        }
    }

    [Theory]
    [InlineData(0)]
    [InlineData(4)]
    [InlineData(6)]
    public void RejectsUnpublishedAndFutureLibraryVersions(int version)
    {
        var fixture = Fixture();
        fixture["schemaVersion"] = version;
        Assert.Throws<UnsupportedLibraryVersionException>(() => ContractJson.ReadLibrary(fixture.ToJsonString()));
    }

    [Fact]
    public void RejectsMissingRequiredCollectionsInsteadOfSilentlyDiscardingData()
    {
        var fixture = Fixture();
        fixture.Remove("reviewLogs");
        Assert.Throws<JsonException>(() => ContractJson.ReadLibrary(fixture.ToJsonString()));
    }

    [Fact]
    public void RejectsUnexpectedFieldsAndNullRequiredValues()
    {
        var fixture = Fixture();
        fixture["savedExplanations"]![0]!["document"]!["absolutePath"] = "private";
        Assert.Throws<JsonException>(() => ContractJson.ReadLibrary(fixture.ToJsonString()));
        fixture = Fixture();
        fixture["savedExplanations"]![0]!["request"]!["targetText"] = null;
        Assert.Throws<JsonException>(() => ContractJson.ReadLibrary(fixture.ToJsonString()));
    }

    [Fact]
    public void RejectsLocatorInOldLibrary()
    {
        var fixture = Fixture();
        fixture["schemaVersion"] = 3;
        Assert.Throws<JsonException>(() => ContractJson.ReadLibrary(fixture.ToJsonString()));
    }

    [Fact]
    public void RequiredRecordConstructorFieldsCannotDisappear()
    {
        Assert.Throws<JsonException>(() => ContractJson.Deserialize<GrammarPoint>("{\"text\":\"reads\"}"));
        Assert.Throws<JsonException>(() => ContractJson.Deserialize<ExplanationRequest>("{}"));
    }

    [Theory]
    [InlineData("word-explanation-request", typeof(WordExplanationRequest))]
    [InlineData("word-explanation", typeof(WordExplanation))]
    public void OfficialV4ExamplesRoundTrip(string fileName, Type type)
    {
        var schema = ReadSchema($"v4/{fileName}.schema.json");
        var example = schema["examples"]![0]!;
        var value = JsonSerializer.Deserialize(example, type, ContractJson.Options);
        var result = JsonSerializer.SerializeToNode(value, type, ContractJson.Options)!;
        foreach (var field in example.AsObject().Where(field => field.Value is not null))
            Assert.True(JsonNode.DeepEquals(field.Value, result[field.Key]), field.Key);
    }

    [Fact]
    public void LocatorDiscriminatorCanAppearLastAndUnknownKindsFail()
    {
        var locator = ContractJson.Deserialize<DocumentLocator>("{\"pageIndex\":2,\"kind\":\"pdf\"}");
        Assert.Equal(2, Assert.IsType<PdfLocator>(locator).PageIndex);
        Assert.Throws<JsonException>(() => ContractJson.Deserialize<DocumentLocator>("{\"kind\":\"web\"}"));
    }

    [Fact]
    public void ReviewEnumsRejectNumbersAndUnknownValues()
    {
        Assert.Throws<JsonException>(() => ContractJson.Deserialize<ReviewRating>("2"));
        Assert.Throws<JsonException>(() => ContractJson.Deserialize<ReviewRating>("\"perfect\""));
    }

    [Fact]
    public void CSharpPropertyNamesMatchPublishedSchemas()
    {
        Check<ExplanationRequest>("v1/explanation-request.schema.json");
        Check<Explanation>("v1/explanation.schema.json");
        Check<GrammarPoint>("v1/explanation.schema.json", "grammarPoint");
        Check<KeyPhrase>("v1/explanation.schema.json", "keyPhrase");
        Check<DeepAnalysis>("v1/deep-analysis.schema.json");
        Check<SentenceComponent>("v1/deep-analysis.schema.json", "sentenceComponent");
        Check<Clause>("v1/deep-analysis.schema.json", "clause");
        Check<JapaneseWord>("v1/deep-analysis.schema.json", "japaneseWord");
        Check<Document>("v1/learning-library.schema.json", "document");
        Check<ReadingProgress>("v1/learning-library.schema.json", "readingProgress");
        Check<PersistedExplanation>("v1/learning-library.schema.json", "persistedExplanation");
        Check<VocabularySense>("v2/learning-library.schema.json", "vocabularySense");
        Check<ReviewCard>("v3/learning-library.schema.json", "reviewCard");
        Check<ReviewLog>("v3/learning-library.schema.json", "reviewLog");
        Check<WordExplanationRequest>("v4/word-explanation-request.schema.json");
        Check<WordExplanation>("v4/word-explanation.schema.json");
        Check<LearningLibrary>("v5/learning-library.schema.json");
        Check<SavedExplanation>("v5/learning-library.schema.json", "savedExplanation");
        Check<VocabularyEntry>("v5/learning-library.schema.json", "vocabularyEntry");
        Check<VocabularySource>("v5/learning-library.schema.json", "vocabularySource");
    }

    private static JsonNode ReadSchema(string file) => JsonNode.Parse(File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Contracts", file)))!;

    private static void Check<T>(string file, string? definition = null)
    {
        var schema = ReadSchema(file);
        if (definition is not null) schema = schema["$defs"]![definition]!;
        var expected = schema["properties"]!.AsObject().Select(p => p.Key).Order().ToArray();
        var actual = ContractJson.Options.GetTypeInfo(typeof(T)).Properties.Select(p => p.Name).Order().ToArray();
        Assert.Equal(expected, actual);
    }
}
