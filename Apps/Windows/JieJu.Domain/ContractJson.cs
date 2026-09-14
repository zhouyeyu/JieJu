using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace JieJu.Domain;

public sealed class UnsupportedLibraryVersionException(int version)
    : JsonException($"Unsupported learning-library version: {version}.");

public static class ContractJson
{
    public static JsonSerializerOptions Options { get; } = CreateOptions();

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
            RespectNullableAnnotations = true,
            RespectRequiredConstructorParameters = true,
            AllowOutOfOrderMetadataProperties = true,
            WriteIndented = true
        };
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false));
        options.MakeReadOnly(populateMissingResolver: true);
        return options;
    }

    public static T Deserialize<T>(string json) => JsonSerializer.Deserialize<T>(json, Options)
        ?? throw new JsonException("Expected a non-null contract object.");

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);

    public static LearningLibrary ReadLibrary(string json)
    {
        var root = JsonNode.Parse(json) as JsonObject ?? throw new JsonException("Expected a library object.");
        if (root["schemaVersion"] is not JsonValue versionNode || !versionNode.TryGetValue<int>(out var version))
            throw new JsonException("Missing or invalid schemaVersion.");
        // v4 defines word AI exchanges; it never published a library format.
        if (version is not (1 or 2 or 3 or 5))
            throw new UnsupportedLibraryVersionException(version);
        var allowed = new HashSet<string> { "schemaVersion", "readingProgress", "savedExplanations" };
        if (version >= 2) allowed.Add("vocabularyEntries");
        if (version >= 3) { allowed.Add("reviewCards"); allowed.Add("reviewLogs"); }
        if (root.Any(property => !allowed.Contains(property.Key)))
            throw new JsonException("Unexpected library field for its schema version.");
        foreach (var field in allowed.Where(field => field != "schemaVersion"))
            if (root[field] is not JsonArray) throw new JsonException($"Missing or invalid {field}.");
        if (version < 5)
        {
            foreach (var record in root["savedExplanations"]!.AsArray())
                RejectOldLocator(record);
            if (version >= 2)
                foreach (var entry in root["vocabularyEntries"]!.AsArray())
                    if (entry?["sources"] is JsonArray sources)
                        foreach (var source in sources) RejectOldLocator(source);
        }
        if (version == 1) root["vocabularyEntries"] = new JsonArray();
        if (version < 3) { root["reviewCards"] = new JsonArray(); root["reviewLogs"] = new JsonArray(); }
        root["schemaVersion"] = 5;
        return Deserialize<LearningLibrary>(root.ToJsonString());
    }

    private static void RejectOldLocator(JsonNode? record)
    {
        if (record is JsonObject item && item.ContainsKey("locator"))
            throw new JsonException("A locator requires learning-library v5.");
    }
}
