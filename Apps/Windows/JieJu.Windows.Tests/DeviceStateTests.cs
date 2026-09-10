using JieJu.Windows.Infrastructure;
using Xunit;

namespace JieJu.Windows.Tests;

public class DeviceStateTests
{
    [Fact]
    public void SettingsAndPositionSurviveRestartWithoutEnteringSharedLibrary()
    {
        var directory = Path.Combine(Path.GetTempPath(), "jieju-device-test-" + Guid.NewGuid());
        try
        {
            var store = new DeviceStateStore(directory);
            var state = store.Load() with { Settings = new ReadingSettings(24, Theme: "night", ShowsFurigana: true) };
            state = DeviceStateStore.Remember(state, new RecentBook("book", "book.epub", "Book", 2, .4, DateTimeOffset.UtcNow));
            store.Save(state);
            var restored = new DeviceStateStore(directory).Load();
            Assert.Equal(state.Settings, restored.Settings);
            Assert.Equal(state.RecentBooks, restored.RecentBooks);
            Assert.False(File.Exists(Path.Combine(directory, "library.json")));
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }
    [Fact]
    public void RecentBooksDeduplicateByContentAndKeepTwelve()
    {
        var state = new DeviceState(new(), []);
        for (var i = 0; i < 15; i++) state = DeviceStateStore.Remember(state, new RecentBook(i.ToString(), "a.epub", "A", 0, 0, DateTimeOffset.UtcNow));
        state = DeviceStateStore.Remember(state, state.RecentBooks[4] with { Chapter = 3 });
        Assert.Equal(12, state.RecentBooks.Length);
        Assert.Equal(3, state.RecentBooks[0].Chapter);
        Assert.Equal(12, state.RecentBooks.Select(b => b.Id).Distinct().Count());
    }
    [Fact]
    public void InvalidDisplayPreferencesAreClamped()
    {
        var settings = DeviceStateStore.Normalize(new(double.NaN, 200, -4, "invalid"));
        Assert.Equal(18, settings.FontSize); Assert.Equal(2.5, settings.LineHeight);
        Assert.Equal(20, settings.HorizontalMargin); Assert.Equal("paper", settings.Theme);
        Assert.Equal("sidebar", settings.ExplanationPresentation);
    }

    [Fact]
    public void ExplanationPresentationIsValidatedAndPersisted()
    {
        Assert.Equal("popup", DeviceStateStore.Normalize(new(ExplanationPresentation: "popup")).ExplanationPresentation);
        Assert.Equal("sidebar", DeviceStateStore.Normalize(new(ExplanationPresentation: "floating-window")).ExplanationPresentation);
    }

    [Fact]
    public void CloudSettingsPersistWithoutAnApiKeyField()
    {
        var settings = DeviceStateStore.Normalize(new(Provider: "cloud", CloudUrl: "https://example.test/v1", CloudModel: "model"));
        var json = System.Text.Json.JsonSerializer.Serialize(settings);
        Assert.Equal("cloud", settings.Provider);
        Assert.DoesNotContain("apikey", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("secret", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void OlderSettingsDefaultToLocalOllama()
    {
        var settings = System.Text.Json.JsonSerializer.Deserialize<ReadingSettings>("{\"FontSize\":20,\"OllamaUrl\":\"http://127.0.0.1:11434\",\"Model\":\"local\"}")!;
        Assert.Equal("ollama", settings.Provider);
        Assert.Equal("https://api.openai.com/v1", settings.CloudUrl);
    }

    [Fact]
    public void ApiKeyRoundTripsThroughWindowsCredentialManager()
    {
        if (!OperatingSystem.IsWindows()) return;
        var store = new WindowsCredentialStore("JieJu/Tests/" + Guid.NewGuid());
        try { store.Save("temporary-secret"); Assert.Equal("temporary-secret", store.Load()); }
        finally { store.Save(""); }
        Assert.Equal("", store.Load());
    }
}
