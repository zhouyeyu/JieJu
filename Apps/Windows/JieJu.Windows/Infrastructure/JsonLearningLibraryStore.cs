using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public sealed class JsonLearningLibraryStore(string directory) : ILearningLibraryStore
{
    private readonly string file = Path.Combine(directory, "library.json");
    private readonly SemaphoreSlim gate = new(1, 1);

    public async Task<LearningLibrary> LoadAsync(CancellationToken cancellationToken = default)
    {
        await gate.WaitAsync(cancellationToken);
        try
        {
            Directory.CreateDirectory(directory);
            if (!File.Exists(file))
            {
                await WriteAsync(LearningLibrary.Empty, cancellationToken);
                return LearningLibrary.Empty;
            }
            try
            {
                var loaded = ContractJson.ReadLibrary(await File.ReadAllTextAsync(file, cancellationToken));
                var repaired = LearningLibraryOperations.EnsureRecognitionCards(loaded, DateTimeOffset.UtcNow);
                if (repaired.ReviewCards.Length != loaded.ReviewCards.Length) await WriteAsync(repaired, cancellationToken);
                return repaired;
            }
            catch (UnsupportedLibraryVersionException) { throw; }
            catch (System.Text.Json.JsonException)
            {
                var backup = UniqueBackupPath();
                File.Move(file, backup);
                await WriteAsync(LearningLibrary.Empty, cancellationToken);
                return LearningLibrary.Empty;
            }
        }
        finally { gate.Release(); }
    }

    public async Task SaveAsync(LearningLibrary library, CancellationToken cancellationToken = default)
    {
        await gate.WaitAsync(cancellationToken);
        try
        {
            Directory.CreateDirectory(directory);
            await WriteAsync(library, cancellationToken);
        }
        finally { gate.Release(); }
    }

    private async Task WriteAsync(LearningLibrary library, CancellationToken cancellationToken)
    {
        var temporary = file + ".tmp";
        try
        {
            await File.WriteAllTextAsync(temporary, ContractJson.Serialize(library), cancellationToken);
            File.Move(temporary, file, overwrite: true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private string UniqueBackupPath()
    {
        var stamp = DateTimeOffset.UtcNow.ToString("yyyyMMdd-HHmmss");
        var candidate = Path.Combine(directory, $"library.corrupt-{stamp}.json");
        for (var suffix = 1; File.Exists(candidate); suffix++)
            candidate = Path.Combine(directory, $"library.corrupt-{stamp}-{suffix}.json");
        return candidate;
    }
}
