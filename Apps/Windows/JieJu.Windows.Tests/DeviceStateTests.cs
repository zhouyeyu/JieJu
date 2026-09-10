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
}
