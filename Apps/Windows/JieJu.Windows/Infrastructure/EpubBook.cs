using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using JieJu.Domain;

namespace JieJu.Windows.Infrastructure;

public sealed record EpubChapter(string Id, string Href, string Title);
public sealed record BookResource(byte[] Bytes, string MediaType);

public sealed class EpubBook
{
    private const string ReaderOrigin = "https://reader.jieju.invalid";
    private const string ContentSecurityPolicy = "default-src 'none'; script-src https://reader.jieju.invalid/book.mjs https://reader.jieju.invalid/bridge.mjs; style-src https://reader.jieju.invalid 'unsafe-inline'; img-src https://reader.jieju.invalid data:; font-src https://reader.jieju.invalid; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri https://reader.jieju.invalid; form-action 'none'";
    public required string Id { get; init; }
    public required string Title { get; init; }
    public required string Language { get; init; }
    public required string FileName { get; init; }
    public required IReadOnlyList<EpubChapter> Chapters { get; init; }
    public required IReadOnlyDictionary<string, BookResource> Resources { get; init; }

    public static EpubBook Open(string path)
    {
        using var file = File.OpenRead(path);
        if (file.Length > 100 * 1024 * 1024) throw new InvalidDataException("这本书超过当前支持的 100 MB，请先使用较小的 EPUB。");
        var id = Convert.ToHexString(SHA256.HashData(file)).ToLowerInvariant();
        file.Position = 0;
        using var zip = new ZipArchive(file, ZipArchiveMode.Read);
        if (zip.Entries.Count > 10000) throw new InvalidDataException("EPUB 文件条目过多。");
        long total = 0;
        var entries = new Dictionary<string, ZipArchiveEntry>(StringComparer.Ordinal);
        foreach (var entry in zip.Entries)
        {
            if (entry.FullName.EndsWith('/')) continue;
            var name = ResolvePath("", entry.FullName, decode: false);
            if (entry.Length > 20 * 1024 * 1024 || (total += entry.Length) > 200 * 1024 * 1024)
                throw new InvalidDataException("EPUB 解压后的资源超过当前支持大小。");
            if (!entries.TryAdd(name, entry)) throw new InvalidDataException("EPUB 含有重复的资源路径。");
        }
        byte[] Read(string name)
        {
            if (!entries.TryGetValue(name, out var entry)) throw new InvalidDataException($"EPUB 缺少资源：{name}");
            using var stream = entry.Open();
            using var data = new MemoryStream();
            stream.CopyTo(data);
            return data.ToArray();
        }
        var container = ParseXml(Read("META-INF/container.xml"));
        var opfPath = container.Descendants().FirstOrDefault(e => e.Name.LocalName == "rootfile")?.Attribute("full-path")?.Value
            ?? throw new InvalidDataException("EPUB 缺少主目录。");
        opfPath = ResolvePath("", opfPath);
        var package = ParseXml(Read(opfPath));
        if (package.Descendants().Any(e => e.Name.LocalName == "meta" && (string?)e.Attribute("property") == "rendition:layout" && e.Value == "pre-paginated"))
            throw new InvalidDataException("暂不支持固定版式 EPUB，请使用可重排版本。");
        var basePath = opfPath.Contains('/') ? opfPath[..(opfPath.LastIndexOf('/') + 1)] : "";
        var resources = new Dictionary<string, BookResource>(StringComparer.Ordinal);
        var manifest = new Dictionary<string, (string Href, string Type)>(StringComparer.Ordinal);
        foreach (var item in package.Descendants().Where(e => e.Name.LocalName == "manifest").Elements())
        {
            var itemId = (string?)item.Attribute("id") ?? throw new InvalidDataException("EPUB manifest 缺少 id。");
            var href = ResolvePath(basePath, (string?)item.Attribute("href") ?? "");
            var mime = (string?)item.Attribute("media-type") ?? "application/octet-stream";
            if (!manifest.TryAdd(itemId, (href, mime))) throw new InvalidDataException("EPUB manifest id 重复。");
            // Only the declared book resources are served; no archive is extracted to disk.
            resources[href] = new BookResource(Read(href), mime);
        }
        var chapters = new List<EpubChapter>();
        foreach (var item in package.Descendants().Where(e => e.Name.LocalName == "spine").Elements())
        {
            if ((string?)item.Attribute("linear") == "no") continue;
            if (!manifest.TryGetValue((string?)item.Attribute("idref") ?? "", out var resource))
                throw new InvalidDataException("EPUB 阅读顺序引用了不存在的章节。");
            if (resource.Type != "application/xhtml+xml") throw new InvalidDataException("暂不支持此 EPUB 章节格式。");
            var xhtml = ParseXml(resources[resource.Href].Bytes);
            var title = xhtml.Descendants().FirstOrDefault(e => e.Name.LocalName is "h1" or "h2")?.Value.Trim();
            if (string.IsNullOrWhiteSpace(title)) title = xhtml.Descendants().FirstOrDefault(e => e.Name.LocalName == "title")?.Value.Trim();
            chapters.Add(new EpubChapter((string)item.Attribute("idref")!, resource.Href,
                string.IsNullOrWhiteSpace(title) ? $"第 {chapters.Count + 1} 章" : title));
        }
        if (chapters.Count == 0) throw new InvalidDataException("EPUB 没有可阅读的章节。");
        return new EpubBook
        {
            Id = id, Title = package.Descendants().FirstOrDefault(e => e.Name.LocalName == "title")?.Value ?? Path.GetFileNameWithoutExtension(path),
            Language = package.Descendants().FirstOrDefault(e => e.Name.LocalName == "language")?.Value ?? "und",
            FileName = Path.GetFileName(path), Chapters = chapters, Resources = resources
        };
    }

    public static string ResolvePath(string directory, string href, bool decode = true)
    {
        if (decode) href = Uri.UnescapeDataString(href.Split('#')[0]);
        if (string.IsNullOrWhiteSpace(href) || href.StartsWith('/') || href.Contains('\\') || href.Contains(':') || href.Contains('?') || href.Any(char.IsControl))
            throw new InvalidDataException("EPUB 含有不受支持的外部或绝对资源路径。");
        var segments = new List<string>();
        foreach (var segment in (directory + href).Split('/'))
        {
            if (segment is "" or ".") continue;
            if (segment == "..")
            {
                if (segments.Count == 0) throw new InvalidDataException("EPUB 资源路径越界。");
                segments.RemoveAt(segments.Count - 1);
            }
            else segments.Add(segment);
        }
        return string.Join('/', segments);
    }

    public static XDocument ParseXml(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes);
        using var reader = XmlReader.Create(stream, new XmlReaderSettings
        { DtdProcessing = DtdProcessing.Ignore, XmlResolver = null, MaxCharactersInDocument = 20 * 1024 * 1024 });
        return XDocument.Load(reader, LoadOptions.PreserveWhitespace);
    }

    public byte[] RenderChapter(int index, IJapaneseMorphology? japaneseMorphology = null)
    {
        var chapter = Chapters[index];
        var document = ParseXml(Resources[chapter.Href].Bytes);
        foreach (var element in document.Descendants().Where(e => e.Name.LocalName is "script" or "iframe" or "object" or "embed" or "base" or "form" or "meta").ToArray()) element.Remove();
        if (japaneseMorphology is not null) EpubFuriganaAnnotator.Annotate(document, Language, japaneseMorphology);
        var html = document.Root ?? throw new InvalidDataException("章节为空。");
        foreach (var attribute in html.DescendantsAndSelf().Attributes().Where(a => a.Name.LocalName.StartsWith("on", StringComparison.OrdinalIgnoreCase)).ToArray()) attribute.Remove();
        var ns = html.Name.Namespace;
        var head = html.Elements().FirstOrDefault(e => e.Name.LocalName == "head");
        if (head is null) { head = new XElement(ns + "head"); html.AddFirst(head); }
        var directory = chapter.Href.Contains('/') ? chapter.Href[..(chapter.Href.LastIndexOf('/') + 1)] : "";
        head.AddFirst(new XElement(ns + "base", new XAttribute("href", $"{ReaderOrigin}/book/{directory}")));
        head.AddFirst(new XElement(ns + "meta", new XAttribute("name", "jieju-chapter"), new XAttribute("content", chapter.Href)));
        head.AddFirst(new XElement(ns + "meta", new XAttribute("http-equiv", "Content-Security-Policy"), new XAttribute("content", ContentSecurityPolicy)));
        head.AddFirst(new XElement(ns + "meta", new XAttribute("charset", "utf-8")));
        head.Add(new XElement(ns + "link", new XAttribute("rel", "stylesheet"), new XAttribute("href", "https://reader.jieju.invalid/book.css")));
        head.Add(new XElement(ns + "script", new XAttribute("type", "module"), new XAttribute("src", "https://reader.jieju.invalid/book.mjs"), " "));
        return Encoding.UTF8.GetBytes(document.ToString(SaveOptions.DisableFormatting));
    }
}
