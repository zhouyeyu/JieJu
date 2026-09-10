using JieJu.Domain;
using JieJu.Windows.Infrastructure;
using Xunit;

namespace JieJu.Windows.Tests;

public class LearningLibraryTests
{
    [Fact]
    public void SavingTheSameSelectionUpdatesInsteadOfDuplicating()
    {
        var first = Record("旧翻译", DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var library = LearningLibraryOperations.UpsertExplanation(LearningLibrary.Empty, first);
        var updated = Record("新翻译", DateTimeOffset.Parse("2026-01-02T00:00:00Z")) with { Locator = null };

        library = LearningLibraryOperations.UpsertExplanation(library, updated);

        var saved = Assert.Single(library.SavedExplanations);
        Assert.Equal(first.Id, saved.Id);
        Assert.Equal(first.CreatedAt, saved.CreatedAt);
        Assert.Equal("新翻译", saved.Explanation.Translation);
        Assert.Equal(first.Locator, saved.Locator);
    }

    [Fact]
    public void DeleteOnlyRemovesTheRequestedExplanation()
    {
        var first = Record("一", DateTimeOffset.UtcNow);
        var second = Record("二", DateTimeOffset.UtcNow) with
        {
            Id = Guid.NewGuid(),
            Request = first.Request with { TargetText = "Another sentence." }
        };
        var library = LearningLibrary.Empty with { SavedExplanations = [first, second] };

        library = LearningLibraryOperations.DeleteExplanation(library, first.Id);

        Assert.Equal(second.Id, Assert.Single(library.SavedExplanations).Id);
    }

    [Fact]
    public void VocabularyMergesMeaningsAndSourcesByLemma()
    {
        var first = Vocabulary("河岸", "one.epub", "the bank of the river");
        var second = Vocabulary("银行", "two.epub", "went to the bank") with { Id = Guid.NewGuid() };
        var library = LearningLibraryOperations.UpsertVocabulary(LearningLibrary.Empty, first);

        library = LearningLibraryOperations.UpsertVocabulary(library, second);

        var entry = Assert.Single(library.VocabularyEntries);
        Assert.Equal(first.Id, entry.Id);
        Assert.Equal(2, entry.Senses.Length);
        Assert.Equal(2, entry.Sources.Length);
    }

    [Fact]
    public async Task JsonStoreCreatesAndReloadsVersionFiveLibrary()
    {
        var directory = TemporaryDirectory();
        try
        {
            var store = new JsonLearningLibraryStore(directory);
            var empty = await store.LoadAsync();
            Assert.Empty(empty.SavedExplanations);
            var expected = LearningLibraryOperations.UpsertExplanation(empty, Record("翻译", DateTimeOffset.UtcNow));
            await store.SaveAsync(expected);

            var restored = await new JsonLearningLibraryStore(directory).LoadAsync();

            Assert.Equal(5, restored.SchemaVersion);
            var saved = Assert.Single(restored.SavedExplanations);
            var original = Assert.Single(expected.SavedExplanations);
            Assert.Equal(original.Id, saved.Id);
            Assert.Equal(original.Request, saved.Request);
            Assert.Equal(original.Explanation.Translation, saved.Explanation.Translation);
            Assert.Equal(original.Locator, saved.Locator);
            Assert.Contains("\"schemaVersion\": 5", await File.ReadAllTextAsync(Path.Combine(directory, "library.json")));
        }
        finally { Directory.Delete(directory, true); }
    }

    [Fact]
    public async Task JsonStoreBacksUpCorruptDataBeforeRecovering()
    {
        var directory = TemporaryDirectory();
        try
        {
            await File.WriteAllTextAsync(Path.Combine(directory, "library.json"), "not-json");
            var restored = await new JsonLearningLibraryStore(directory).LoadAsync();
            Assert.Empty(restored.SavedExplanations);
            Assert.Single(Directory.GetFiles(directory, "library.corrupt-*.json"));
            Assert.Equal(5, ContractJson.ReadLibrary(await File.ReadAllTextAsync(Path.Combine(directory, "library.json"))).SchemaVersion);
        }
        finally { Directory.Delete(directory, true); }
    }

    [Fact]
    public async Task JsonStoreDoesNotOverwriteAFutureLibraryVersion()
    {
        var directory = TemporaryDirectory();
        try
        {
            var path = Path.Combine(directory, "library.json");
            var future = ContractJson.Serialize(LearningLibrary.Empty).Replace("\"schemaVersion\": 5", "\"schemaVersion\": 6");
            await File.WriteAllTextAsync(path, future);

            await Assert.ThrowsAsync<UnsupportedLibraryVersionException>(() => new JsonLearningLibraryStore(directory).LoadAsync());

            Assert.Equal(future, await File.ReadAllTextAsync(path));
            Assert.Empty(Directory.GetFiles(directory, "library.corrupt-*.json"));
        }
        finally { Directory.Delete(directory, true); }
    }

    private static string TemporaryDirectory()
    {
        var directory = Path.Combine(Path.GetTempPath(), "jieju-library-test-" + Guid.NewGuid());
        Directory.CreateDirectory(directory);
        return directory;
    }

    private static SavedExplanation Record(string translation, DateTimeOffset timestamp) => new(
        Guid.NewGuid(),
        new Document("book-id", "book.epub"),
        new ExplanationRequest
        {
            TargetText = "She reads a book.",
            PrecedingContext = "Before.",
            FollowingContext = "After.",
            SourceLanguage = "English",
            ExplanationLanguage = "Chinese"
        },
        new PersistedExplanation(translation, "She reads a book.", [], [], "test-model"),
        timestamp,
        timestamp,
        Locator: new EpubLocator("Text/chapter.xhtml", TextAnchor: "{\"progress\":0.4}"));

    private static VocabularyEntry Vocabulary(string meaning, string fileName, string sentence)
    {
        var now = DateTimeOffset.UtcNow;
        return new VocabularyEntry(Guid.NewGuid(), "English", "bank", ["bank"],
            [new VocabularySense(Guid.NewGuid(), meaning, "Chinese")],
            [new VocabularySource(Guid.NewGuid(), new Document(fileName, fileName), sentence, "bank", now)],
            now, now, PartOfSpeech: "noun");
    }
}
