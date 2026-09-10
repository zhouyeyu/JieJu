using System.Text.Json;

namespace JieJu.Windows.Infrastructure;

public sealed record ReadingSettings(double FontSize = 18, double LineHeight = 1.75, double HorizontalMargin = 54,
    string Theme = "paper", bool ShowsFurigana = false, string OllamaUrl = "http://127.0.0.1:11434",
    string Model = "qwen2.5:1.5b-instruct", string ExplanationLanguage = "Chinese");
public sealed record RecentBook(string Id, string Path, string Title, int Chapter, double Progress, DateTimeOffset OpenedAt);
public sealed record DeviceState(ReadingSettings Settings, RecentBook[] RecentBooks);

public sealed class DeviceStateStore(string directory)
{
    private readonly string file = Path.Combine(directory, "device-state.json");
    public DeviceState Load()
    {
        if (!File.Exists(file)) return new(new(), []);
        var state = JsonSerializer.Deserialize<DeviceState>(File.ReadAllText(file)) ?? throw new InvalidDataException("阅读设置文件为空。");
        if (state.Settings is null || state.RecentBooks is null) throw new InvalidDataException("阅读设置文件损坏。");
        return state with { Settings = Normalize(state.Settings) };
    }
    public static ReadingSettings Normalize(ReadingSettings settings) => settings with
    {
        FontSize = double.IsFinite(settings.FontSize) ? Math.Clamp(settings.FontSize, 12, 32) : 18,
        LineHeight = double.IsFinite(settings.LineHeight) ? Math.Clamp(settings.LineHeight, 1.2, 2.5) : 1.75,
        HorizontalMargin = double.IsFinite(settings.HorizontalMargin) ? Math.Clamp(settings.HorizontalMargin, 20, 120) : 54,
        Theme = settings.Theme is "paper" or "night" or "sepia" or "sage" ? settings.Theme : "paper"
    };
    public void Save(DeviceState state)
    {
        Directory.CreateDirectory(directory);
        var temporary = file + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(state));
        File.Move(temporary, file, overwrite: true);
    }
    public static DeviceState Remember(DeviceState state, RecentBook book) => state with
    { RecentBooks = new[] { book }.Concat(state.RecentBooks.Where(b => b.Id != book.Id)).Take(12).ToArray() };
}
